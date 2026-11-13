const std = @import("std");
const schema = @import("../schema.zig");

const cg = @import("../codegen.zig");
const Error = cg.Error;
const CodegenContext = cg.CodegenContext;

pub fn writeJsonMethods(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try cg.indent(writer, depth);
    try writer.writeAll("pub const JsonStringifyOptions = struct { enum_as_name: bool = true, preserve_proto_field_names: bool = false, always_print_primitive_fields: bool = false };\n\n");

    try cg.indent(writer, depth);
    try writer.writeAll("pub fn jsonStringifyAlloc(self: @This(), allocator: std.mem.Allocator) ![]u8 {\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("return try self.jsonStringifyAllocWithOptions(allocator, .{});\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n\n");

    try cg.indent(writer, depth);
    try writer.writeAll("pub fn jsonStringifyAllocWithOptions(self: @This(), allocator: std.mem.Allocator, options: @This().JsonStringifyOptions) ![]u8 {\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("var out: std.Io.Writer.Allocating = .init(allocator);\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("errdefer out.deinit();\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("try self.jsonStringifyWithOptions(allocator, &out.writer, options);\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("return try out.toOwnedSlice();\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n\n");

    try cg.indent(writer, depth);
    try writer.writeAll("pub fn jsonStringify(self: @This(), writer: *std.Io.Writer) !void {\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("try self.jsonStringifyWithOptions(std.heap.page_allocator, writer, .{});\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n\n");

    try cg.indent(writer, depth);
    try writer.writeAll("pub fn jsonStringifyWithAllocator(self: @This(), allocator: std.mem.Allocator, writer: *std.Io.Writer) !void {\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("try self.jsonStringifyWithOptions(allocator, writer, .{});\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n\n");

    try cg.indent(writer, depth);
    try writer.writeAll("pub fn jsonStringifyWithOptions(self: @This(), allocator: std.mem.Allocator, writer: *std.Io.Writer, options: @This().JsonStringifyOptions) anyerror!void {\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("_ = &allocator;\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("_ = &options;\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("try writer.writeAll(\"{\");\n");
    if (messageJsonStringifyHasFields(ctx, message)) {
        try cg.indent(writer, depth + 1);
        try writer.writeAll("var first = true;\n");
        for (message.fields.items) |*field| {
            if (field.oneof_name == null) try writeJsonField(ctx, field, writer, depth + 1);
        }
        for (message.oneofs.items) |oneof| {
            if (oneofHasJsonField(ctx, message, oneof.name)) try writeJsonOneof(ctx, message, oneof, writer, depth + 1);
        }
        try writeJsonExtensionFields(ctx, message, writer, depth + 1);
    } else {
        try cg.indent(writer, depth + 1);
        try writer.writeAll("_ = self;\n");
    }
    try cg.indent(writer, depth + 1);
    try writer.writeAll("try writer.writeAll(\"}\");\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n");

    try writer.writeAll("\n");
    try writeJsonParseMethods(ctx, message, writer, depth);
}

pub fn messageContainsJsonField(message: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) bool {
    for (message.fields.items) |*candidate| {
        if (candidate == field) return true;
    }
    for (message.messages.items) |*nested| {
        if (messageContainsJsonField(nested, field)) return true;
    }
    return false;
}

pub fn findJsonFieldMessage(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor) ?*const schema.MessageDescriptor {
    for (file.messages.items) |*message| {
        if (messageContainsJsonField(message, field)) return message;
    }
    return null;
}

/// Emit duplicate-field tracking for a JSON object key that matched `field`.
/// Protobuf JSON rejects the same field spelled twice, including through
/// different accepted spellings (`big_delta` and `bigDelta`), and rejects two
/// different members of the same oneof.
pub fn writeJsonSeenCheck(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const message = findJsonFieldMessage(file, field) orelse return;
    var field_index: ?usize = null;
    for (message.fields.items, 0..) |*candidate, i| {
        if (candidate == field) {
            field_index = i;
            break;
        }
    }
    const seen_index = field_index orelse return;
    try cg.indent(writer, depth);
    try writer.print("if (_pbz_seen.isSet({d})) return error.DuplicateField;\n", .{seen_index});
    try cg.indent(writer, depth);
    try writer.print("_pbz_seen.set({d});\n", .{seen_index});
    if (field.oneof_name) |oneof_name| {
        for (message.oneofs.items, 0..) |oneof, oneof_index| {
            if (!std.mem.eql(u8, oneof.name, oneof_name)) continue;
            try cg.indent(writer, depth);
            try writer.print("if (_pbz_seen_oneofs.isSet({d})) return error.DuplicateField;\n", .{oneof_index});
            try cg.indent(writer, depth);
            try writer.print("_pbz_seen_oneofs.set({d});\n", .{oneof_index});
            break;
        }
    }
}

const WktWrapperKind = struct {
    pbz_type: []const u8,
    value_type: []const u8,
    parse: enum { float, int, bool, string, bytes },
};

const WktJson = union(enum) {
    timestamp,
    duration,
    field_mask,
    empty,
    struct_value,
    value_value,
    list_value,
    any_value,
    wrapper: WktWrapperKind,
};

pub fn wktJsonSupportAvailable(ctx: *const CodegenContext) bool {
    return cg.codegenCanReferenceMessageWithContext(ctx, "google.protobuf.Struct") and
        cg.codegenCanReferenceMessageWithContext(ctx, "google.protobuf.Value") and
        cg.codegenCanReferenceMessageWithContext(ctx, "google.protobuf.ListValue");
}

pub fn anyJsonSupportAvailable(ctx: *const CodegenContext) bool {
    return cg.codegenCanReferenceMessageWithContext(ctx, "google.protobuf.Any");
}

pub fn wktJson(ctx: *const CodegenContext, type_name: []const u8) ?WktJson {
    if (std.mem.eql(u8, type_name, "google.protobuf.Timestamp")) return .timestamp;
    if (std.mem.eql(u8, type_name, "google.protobuf.Duration")) return .duration;
    if (std.mem.eql(u8, type_name, "google.protobuf.FieldMask")) return .field_mask;
    if (std.mem.eql(u8, type_name, "google.protobuf.Empty")) return .empty;
    if (wktJsonSupportAvailable(ctx)) {
        if (std.mem.eql(u8, type_name, "google.protobuf.Struct")) return .struct_value;
        if (std.mem.eql(u8, type_name, "google.protobuf.Value")) return .value_value;
        if (std.mem.eql(u8, type_name, "google.protobuf.ListValue")) return .list_value;
    }
    if (anyJsonSupportAvailable(ctx) and std.mem.eql(u8, type_name, "google.protobuf.Any")) return .any_value;
    const wrappers = [_]struct { name: []const u8, kind: WktWrapperKind }{
        .{ .name = "google.protobuf.DoubleValue", .kind = .{ .pbz_type = "pbz.DoubleValue", .value_type = "f64", .parse = .float } },
        .{ .name = "google.protobuf.FloatValue", .kind = .{ .pbz_type = "pbz.FloatValue", .value_type = "f32", .parse = .float } },
        .{ .name = "google.protobuf.Int64Value", .kind = .{ .pbz_type = "pbz.Int64Value", .value_type = "i64", .parse = .int } },
        .{ .name = "google.protobuf.UInt64Value", .kind = .{ .pbz_type = "pbz.UInt64Value", .value_type = "u64", .parse = .int } },
        .{ .name = "google.protobuf.Int32Value", .kind = .{ .pbz_type = "pbz.Int32Value", .value_type = "i32", .parse = .int } },
        .{ .name = "google.protobuf.UInt32Value", .kind = .{ .pbz_type = "pbz.UInt32Value", .value_type = "u32", .parse = .int } },
        .{ .name = "google.protobuf.BoolValue", .kind = .{ .pbz_type = "pbz.BoolValue", .value_type = "bool", .parse = .bool } },
        .{ .name = "google.protobuf.StringValue", .kind = .{ .pbz_type = "pbz.StringValue", .value_type = "[]const u8", .parse = .string } },
        .{ .name = "google.protobuf.BytesValue", .kind = .{ .pbz_type = "pbz.BytesValue", .value_type = "[]const u8", .parse = .bytes } },
    };
    inline for (wrappers) |wrapper| {
        if (std.mem.eql(u8, type_name, wrapper.name)) return .{ .wrapper = wrapper.kind };
    }
    return null;
}

/// Parse a `pbz.json.Value` into the generated well-known-type struct. The
/// hand-written WKT types own the canonical JSON validation and formatting.
pub fn writeWktJsonParseExpr(kind: WktJson, value_expr: []const u8, arena_expr: []const u8, writer: *std.Io.Writer) Error!void {
    switch (kind) {
        .timestamp => try writer.print("blk: {{ const _pbz_wkt = try pbz.Timestamp.jsonParseUnquoted(try @This().jsonString({s})); break :blk .{{ .seconds = _pbz_wkt.seconds, .nanos = _pbz_wkt.nanos }}; }}", .{value_expr}),
        .duration => try writer.print("blk: {{ const _pbz_wkt = try pbz.Duration.jsonParseUnquoted(try @This().jsonString({s})); break :blk .{{ .seconds = _pbz_wkt.seconds, .nanos = _pbz_wkt.nanos }}; }}", .{value_expr}),
        .field_mask => try writer.print("blk: {{ const _pbz_paths = try pbz.FieldMask.jsonParseUnquoted({s}, try @This().jsonString({s})); break :blk .{{ .paths = try allocator.dupe([]const u8, _pbz_paths) }}; }}", .{ arena_expr, value_expr }),
        .empty => try writer.print("blk: {{ switch ({s}) {{ .object => |_pbz_obj| if (_pbz_obj.count() != 0) return error.UnknownField, else => return error.TypeMismatch }} break :blk .{{}}; }}", .{value_expr}),
        .struct_value => try writer.print("try _pbzJsonParseWktStruct(allocator, {s}, {s})", .{ arena_expr, value_expr }),
        .value_value => try writer.print("try _pbzJsonParseWktValue(allocator, {s}, {s})", .{ arena_expr, value_expr }),
        .list_value => try writer.print("try _pbzJsonParseWktListValue(allocator, {s}, {s})", .{ arena_expr, value_expr }),
        .any_value => try writer.print("try _pbzJsonParseWktAny(allocator, {s}, {s}, options.ignore_unknown_fields)", .{ arena_expr, value_expr }),
        .wrapper => |wrapper| switch (wrapper.parse) {
            .float => try writer.print(".{{ .value = try @This().jsonFloat({s}, {s}) }}", .{ wrapper.value_type, value_expr }),
            .int => try writer.print(".{{ .value = try @This().jsonInt({s}, {s}) }}", .{ wrapper.value_type, value_expr }),
            .bool => try writer.print(".{{ .value = try @This().jsonBool({s}) }}", .{value_expr}),
            .string => try writer.print(".{{ .value = try @This().jsonString({s}) }}", .{value_expr}),
            .bytes => try writer.print(".{{ .value = try @This().jsonBytes({s}, {s}) }}", .{ arena_expr, value_expr }),
        },
    }
}

pub fn writeWktJsonStringifyExpr(kind: WktJson, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    switch (kind) {
        .timestamp => try writer.print("(pbz.Timestamp{{ .seconds = {s}.seconds, .nanos = {s}.nanos }}).jsonStringify(writer)", .{ value_expr, value_expr }),
        .duration => try writer.print("(pbz.Duration{{ .seconds = {s}.seconds, .nanos = {s}.nanos }}).jsonStringify(writer)", .{ value_expr, value_expr }),
        .field_mask => try writer.print("(pbz.FieldMask{{ .paths = {s}.paths }}).jsonStringify(writer)", .{value_expr}),
        .empty => try writer.writeAll("pbz.Empty.jsonStringify(writer)"),
        .struct_value => try writer.print("_pbzJsonStringifyWktStruct({s}, writer)", .{value_expr}),
        .value_value => try writer.print("_pbzJsonStringifyWktValue({s}, writer)", .{value_expr}),
        .list_value => try writer.print("_pbzJsonStringifyWktListValue({s}, writer)", .{value_expr}),
        .any_value => try writer.print("_pbzJsonStringifyWktAny(allocator, {s}, writer)", .{value_expr}),
        .wrapper => |wrapper| try writer.print("({s}{{ .value = {s}.value }}).jsonStringify(writer)", .{ wrapper.pbz_type, value_expr }),
    }
}

/// Emit the recursive Struct/Value/ListValue JSON converters once per file.
/// These are the three WKT types whose JSON form is arbitrary JSON rather than
/// a fixed message shape; generated message JSON cannot express them inline.
pub fn writeWktJsonHelpers(ctx: *const CodegenContext, writer: *std.Io.Writer) Error!void {
    if (!wktJsonSupportAvailable(ctx)) return;
    const struct_type = "google.protobuf.Struct";
    const value_type = "google.protobuf.Value";
    const list_type = "google.protobuf.ListValue";

    try writer.writeAll("fn _pbzJsonParseWktStruct(allocator: std.mem.Allocator, arena_allocator: std.mem.Allocator, value: pbz.json.Value) anyerror!");
    try cg.writeFileScopeMessageReference(ctx, struct_type, writer);
    try writer.writeAll(" {\n    const object = switch (value) { .object => |object| object, else => return error.TypeMismatch };\n    var out = ");
    try cg.writeFileScopeMessageReference(ctx, struct_type, writer);
    try writer.writeAll(".init();\n    errdefer out.deinit(allocator);\n    try out.fields.ensureTotalCapacity(allocator, object.count());\n    var it = object.iterator();\n    while (it.next()) |entry| {\n        var parsed = try _pbzJsonParseWktValue(allocator, arena_allocator, entry.value);\n        errdefer parsed.deinit(allocator);\n        try out.fields.put(allocator, entry.key, parsed);\n    }\n    return out;\n}\n\n");

    try writer.writeAll("fn _pbzJsonParseWktValue(allocator: std.mem.Allocator, arena_allocator: std.mem.Allocator, value: pbz.json.Value) anyerror!");
    try cg.writeFileScopeMessageReference(ctx, value_type, writer);
    try writer.writeAll(" {\n    var out = ");
    try cg.writeFileScopeMessageReference(ctx, value_type, writer);
    try writer.writeAll(".init();\n    errdefer out.deinit(allocator);\n    switch (value) {\n        .null => out.kind = .{ .null_value = 0 },\n        .bool => |v| out.kind = .{ .bool_value = v },\n        .integer => |v| out.kind = .{ .number_value = @floatFromInt(v) },\n        .float => |v| out.kind = .{ .number_value = v },\n        .number_string => |text| out.kind = .{ .number_value = try std.fmt.parseFloat(f64, text) },\n        .string => |text| out.kind = .{ .string_value = text },\n        .object => |object| {\n            var nested = ");
    try cg.writeFileScopeMessageReference(ctx, struct_type, writer);
    try writer.writeAll(".init();\n            errdefer nested.deinit(allocator);\n            try nested.fields.ensureTotalCapacity(allocator, object.count());\n            var it = object.iterator();\n            while (it.next()) |entry| {\n                var parsed = try _pbzJsonParseWktValue(allocator, arena_allocator, entry.value);\n                errdefer parsed.deinit(allocator);\n                try nested.fields.put(allocator, entry.key, parsed);\n            }\n            out.kind = .{ .struct_value = nested };\n        },\n        .array => |array| {\n            const items = try allocator.alloc(");
    try cg.writeFileScopeMessageReference(ctx, value_type, writer);
    try writer.writeAll(", array.items.len);\n            errdefer allocator.free(items);\n            var initialized: usize = 0;\n            errdefer for (items[0..initialized]) |*item| item.deinit(allocator);\n            for (array.items, 0..) |item, i| {\n                items[i] = try _pbzJsonParseWktValue(allocator, arena_allocator, item);\n                initialized += 1;\n            }\n            var list = ");
    try cg.writeFileScopeMessageReference(ctx, list_type, writer);
    try writer.writeAll(".init();\n            list.values = items;\n            out.kind = .{ .list_value = list };\n        },\n    }\n    return out;\n}\n\n");

    try writer.writeAll("fn _pbzJsonParseWktListValue(allocator: std.mem.Allocator, arena_allocator: std.mem.Allocator, value: pbz.json.Value) anyerror!");
    try cg.writeFileScopeMessageReference(ctx, list_type, writer);
    try writer.writeAll(" {\n    const array = switch (value) { .array => |array| array, else => return error.TypeMismatch };\n    var out = ");
    try cg.writeFileScopeMessageReference(ctx, list_type, writer);
    try writer.writeAll(".init();\n    errdefer out.deinit(allocator);\n    const items = try allocator.alloc(");
    try cg.writeFileScopeMessageReference(ctx, value_type, writer);
    try writer.writeAll(", array.items.len);\n    errdefer allocator.free(items);\n    var initialized: usize = 0;\n    errdefer for (items[0..initialized]) |*item| item.deinit(allocator);\n    for (array.items, 0..) |item, i| {\n        items[i] = try _pbzJsonParseWktValue(allocator, arena_allocator, item);\n        initialized += 1;\n    }\n    out.values = items;\n    return out;\n}\n\n");

    try writer.writeAll("fn _pbzJsonStringifyWktStruct(value: ");
    try cg.writeFileScopeMessageReference(ctx, struct_type, writer);
    try writer.writeAll(", writer: *std.Io.Writer) anyerror!void {\n    try writer.writeAll(\"{\");\n    var it = value.fields.iterator();\n    var first = true;\n    while (it.next()) |entry| {\n        if (!first) try writer.writeAll(\",\");\n        first = false;\n        if (!pbz.validateUtf8(entry.key_ptr.*)) return error.InvalidUtf8;\n        try std.json.Stringify.value(entry.key_ptr.*, .{}, writer);\n        try writer.writeAll(\":\");\n        try _pbzJsonStringifyWktValue(entry.value_ptr.*, writer);\n    }\n    try writer.writeAll(\"}\");\n}\n\n");

    try writer.writeAll("fn _pbzJsonStringifyWktValue(value: ");
    try cg.writeFileScopeMessageReference(ctx, value_type, writer);
    try writer.writeAll(", writer: *std.Io.Writer) anyerror!void {\n    switch (value.kind) {\n        .none, .null_value => try writer.writeAll(\"null\"),\n        .number_value => |v| {\n            if (!std.math.isFinite(v)) return error.InvalidNumber;\n            try std.json.Stringify.value(v, .{}, writer);\n        },\n        .string_value => |v| {\n            if (!pbz.validateUtf8(v)) return error.InvalidUtf8;\n            try std.json.Stringify.value(v, .{}, writer);\n        },\n        .bool_value => |v| try writer.writeAll(if (v) \"true\" else \"false\"),\n        .struct_value => |v| try _pbzJsonStringifyWktStruct(v, writer),\n        .list_value => |v| try _pbzJsonStringifyWktListValue(v, writer),\n    }\n}\n\n");

    try writer.writeAll("fn _pbzJsonStringifyWktListValue(value: ");
    try cg.writeFileScopeMessageReference(ctx, list_type, writer);
    try writer.writeAll(", writer: *std.Io.Writer) anyerror!void {\n    try writer.writeAll(\"[\");\n    for (value.values, 0..) |item, i| {\n        if (i != 0) try writer.writeAll(\",\");\n        try _pbzJsonStringifyWktValue(item, writer);\n    }\n    try writer.writeAll(\"]\");\n}\n\n");

}

pub fn writeFileRegistryHelper(ctx: *const CodegenContext, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("fn _pbzFileRegistry(arena: std.mem.Allocator, registry_out: *pbz.Registry) !*pbz.schema.FileDescriptor {\n    registry_out.* = pbz.Registry.init(arena);\n    const file = try arena.create(pbz.schema.FileDescriptor);\n    file.* = try pbz_generated_file.decodeFileDescriptor(arena);\n    try registry_out.addFile(file);\n");
    for (ctx.file.imports.items) |import| {
        if (import.kind == .weak) continue;
        const alias = try cg.makeImportAlias(ctx.allocator, import.path);
        defer ctx.allocator.free(alias);
        try writer.writeAll("    {\n        const imported = try arena.create(pbz.schema.FileDescriptor);\n        imported.* = try imports.");
        try writer.writeAll(alias);
        try writer.writeAll(".decodeFileDescriptor(arena);\n        try registry_out.addFile(imported);\n    }\n");
    }
    try writer.writeAll("    return file;\n}\n\n");
}

pub fn writeAnyJsonHelpers(ctx: *const CodegenContext, writer: *std.Io.Writer) Error!void {
    if (!anyJsonSupportAvailable(ctx)) return;
    try writer.writeAll("fn _pbzJsonParseWktAny(allocator: std.mem.Allocator, arena_allocator: std.mem.Allocator, value: pbz.json.Value, ignore_unknown_fields: bool) anyerror!");
    try cg.writeFileScopeMessageReference(ctx, "google.protobuf.Any", writer);
    try writer.writeAll(" {\n    _ = arena_allocator;\n    var arena = std.heap.ArenaAllocator.init(allocator);\n    defer arena.deinit();\n    var registry: pbz.Registry = undefined;\n    const file = try _pbzFileRegistry(arena.allocator(), &registry);\n    defer registry.deinit();\n    const any_desc = registry.findMessage(\"google.protobuf.Any\", null) orelse return error.TypeMismatch;\n    const wire = try pbz.json.parseAnyWireAllocWithRegistry(allocator, file, &registry, any_desc, value, .{ .ignore_unknown_fields = ignore_unknown_fields });\n    defer allocator.free(wire);\n    return try ");
    try cg.writeFileScopeMessageReference(ctx, "google.protobuf.Any", writer);
    try writer.writeAll(".decodeOwned(allocator, wire);\n}\n\n");
    try writer.writeAll("fn _pbzJsonStringifyWktAny(allocator: std.mem.Allocator, value: ");
    try cg.writeFileScopeMessageReference(ctx, "google.protobuf.Any", writer);
    try writer.writeAll(", writer: *std.Io.Writer) anyerror!void {\n    var arena = std.heap.ArenaAllocator.init(allocator);\n    defer arena.deinit();\n    var registry: pbz.Registry = undefined;\n    const file = try _pbzFileRegistry(arena.allocator(), &registry);\n    defer registry.deinit();\n    const any_desc = registry.findMessage(\"google.protobuf.Any\", null) orelse return error.TypeMismatch;\n    var dynamic = pbz.DynamicMessage.init(allocator, any_desc);\n    defer dynamic.deinit();\n    try dynamic.addClone(any_desc.findField(\"type_url\").?, .{ .string = @constCast(value.type_url) });\n    try dynamic.addClone(any_desc.findField(\"value\").?, .{ .bytes = @constCast(value.value) });\n    const json = try pbz.json.stringifyAnyAllocWithRegistry(allocator, file, &registry, &dynamic, .{});\n    defer allocator.free(json);\n    try writer.writeAll(json);\n}\n\n");
}

pub fn writeJsonSeenIndexCheck(index: usize, writer: *std.Io.Writer, depth: usize) Error!void {
    try cg.indent(writer, depth);
    try writer.print("if (_pbz_seen.isSet({d})) return error.DuplicateField;\n", .{index});
    try cg.indent(writer, depth);
    try writer.print("_pbz_seen.set({d});\n", .{index});
}

pub fn writeJsonParseMethods(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try cg.indent(writer, depth);
    try writer.writeAll("pub const JsonParseOptions = struct { ignore_unknown_fields: bool = false };\n\n");

    try cg.indent(writer, depth);
    try writer.writeAll("pub fn jsonParse(allocator: std.mem.Allocator, text: []const u8) !@This() {\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("return try @This().jsonParseWithOptions(allocator, text, .{});\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n\n");

    try cg.indent(writer, depth);
    try writer.writeAll("pub fn jsonParseWithOptions(allocator: std.mem.Allocator, text: []const u8, options: @This().JsonParseOptions) !@This() {\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("var arena = try allocator.create(std.heap.ArenaAllocator);\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("errdefer allocator.destroy(arena);\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("arena.* = std.heap.ArenaAllocator.init(allocator);\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("errdefer arena.deinit();\n");
    // Keep one arena-owned copy of the input text so the lean JSON value tree
    // can borrow string slices instead of allocating each key/value. Duplicate
    // JSON object keys are rejected by the parser (protobuf conformance
    // requires it); generated map parsing can then insert directly into the
    // destination map.
    try cg.indent(writer, depth + 1);
    try writer.writeAll("const owned_text = try arena.allocator().dupe(u8, text);\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("const parsed = try pbz.json.parseValueTree(arena.allocator(), owned_text, .{});\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("var self = try @This().jsonParseValueWithOptions(allocator, arena.allocator(), parsed, options);\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("self._json_arena = arena;\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("return self;\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n\n");

    try cg.indent(writer, depth);
    try writer.writeAll("/// Parse a pre-parsed JSON subtree without serializing it back to text first.\n");
    try cg.indent(writer, depth);
    try writer.writeAll("/// The caller must keep `arena_allocator` alive for decoded bytes and keep\n");
    try cg.indent(writer, depth);
    try writer.writeAll("/// the text backing `json_value` alive for borrowed string slices.\n");
    try cg.indent(writer, depth);
    try writer.writeAll("pub fn jsonParseValue(allocator: std.mem.Allocator, arena_allocator: std.mem.Allocator, json_value: pbz.json.Value) !@This() {\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("return try @This().jsonParseValueWithOptions(allocator, arena_allocator, json_value, .{});\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n\n");

    try cg.indent(writer, depth);
    try writer.writeAll("/// Option-bearing variant of jsonParseValue for generated nested-message parsers.\n");
    try cg.indent(writer, depth);
    try writer.writeAll("pub fn jsonParseValueWithOptions(allocator: std.mem.Allocator, arena_allocator: std.mem.Allocator, json_value: pbz.json.Value, options: @This().JsonParseOptions) anyerror!@This() {\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("var self = @This().init();\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("errdefer self.deinit(allocator);\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("try self.jsonFillFromValue(allocator, arena_allocator, json_value, options);\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("return self;\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n\n");

    try cg.indent(writer, depth);
    try writer.writeAll("pub fn jsonParseInitialized(allocator: std.mem.Allocator, text: []const u8) !@This() {\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("var self = try @This().jsonParse(allocator, text);\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("errdefer self.deinit(allocator);\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("try self.validateRequiredRecursive(allocator);\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("return self;\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n\n");

    try cg.indent(writer, depth);
    try writer.writeAll("pub fn jsonParseInitializedWithOptions(allocator: std.mem.Allocator, text: []const u8, options: @This().JsonParseOptions) !@This() {\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("var self = try @This().jsonParseWithOptions(allocator, text, options);\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("errdefer self.deinit(allocator);\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("try self.validateRequiredRecursive(allocator);\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("return self;\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n\n");

    try cg.indent(writer, depth);
    try writer.writeAll("fn jsonFillFromValue(self: *@This(), allocator: std.mem.Allocator, arena_allocator: std.mem.Allocator, json_value: pbz.json.Value, options: @This().JsonParseOptions) !void {\n");
    const has_parse_fields = messageJsonParseHasFields(ctx, message);
    try cg.indent(writer, depth + 1);
    try writer.writeAll("_ = &self;\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("_ = &allocator;\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("_ = &arena_allocator;\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("const object = switch (json_value) { .object => |object| object, else => return error.TypeMismatch };\n");
    const seen_count = message.fields.items.len + messageJsonExtensionCount(ctx, message);
    if (seen_count != 0) {
        try cg.indent(writer, depth + 1);
        try writer.print("var _pbz_seen = std.StaticBitSet({d}).initEmpty();\n", .{seen_count});
        try cg.indent(writer, depth + 1);
        try writer.writeAll("_ = &_pbz_seen;\n");
    }
    if (message.oneofs.items.len != 0) {
        try cg.indent(writer, depth + 1);
        try writer.print("var _pbz_seen_oneofs = std.StaticBitSet({d}).initEmpty();\n", .{message.oneofs.items.len});
        try cg.indent(writer, depth + 1);
        try writer.writeAll("_ = &_pbz_seen_oneofs;\n");
    }
    try cg.indent(writer, depth + 1);
    try writer.writeAll("var it = object.iterator();\n");
    try cg.indent(writer, depth + 1);
    if (has_parse_fields) {
        try writer.writeAll("while (it.next()) |entry| {\n");
    } else {
        try writer.writeAll("while (it.next()) |_| {\n");
    }
    if (has_parse_fields) {
        try cg.indent(writer, depth + 2);
        try writer.writeAll("const key = entry.key;\n");
        try cg.indent(writer, depth + 2);
        try writer.writeAll("const value = entry.value;\n");
        try cg.indent(writer, depth + 2);
        try writer.writeAll("if (value == .null) {\n");
        for (message.fields.items) |*field| {
            if (field.oneof_name == null) try writeJsonClearField(ctx, field, writer, depth + 3);
        }
        for (message.oneofs.items) |oneof| {
            for (message.fields.items) |*field| {
                if (field.oneof_name) |name| {
                    if (std.mem.eql(u8, name, oneof.name)) try writeJsonClearOneofField(ctx, oneof, field, writer, depth + 3);
                }
            }
        }
        try writeJsonClearExtensions(ctx, message, writer, depth + 3);
        try cg.indent(writer, depth + 3);
        try writer.writeAll("if (options.ignore_unknown_fields) continue;\n");
        try cg.indent(writer, depth + 3);
        try writer.writeAll("return error.UnknownField;\n");
        try cg.indent(writer, depth + 2);
        try writer.writeAll("}\n");
        for (message.fields.items) |*field| {
            if (field.oneof_name == null) try writeJsonParseField(ctx, field, writer, depth + 2);
        }
        for (message.oneofs.items) |oneof| {
            for (message.fields.items) |*field| {
                if (field.oneof_name) |name| {
                    if (std.mem.eql(u8, name, oneof.name)) try writeJsonParseOneofField(ctx, oneof, field, writer, depth + 2);
                }
            }
        }
        try writeJsonParseExtensions(ctx, message, writer, depth + 2);
    }
    try cg.indent(writer, depth + 2);
    try writer.writeAll("if (options.ignore_unknown_fields) continue;\n");
    try cg.indent(writer, depth + 2);
    try writer.writeAll("return error.UnknownField;\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n\n");

    try writeJsonParseHelpers(writer, depth);
}

pub fn messageJsonParseUsesAllocator(ctx: *const CodegenContext, message: *const schema.MessageDescriptor) bool {
    for (message.fields.items) |*field| {
        if (fieldJsonParseUsesAllocator(ctx, field)) return true;
    }
    if (messageHasJsonExtensions(ctx, message)) return true;
    return false;
}

pub fn messageJsonParseHasFields(ctx: *const CodegenContext, message: *const schema.MessageDescriptor) bool {
    for (message.fields.items) |field| {
        if (field.kind == .scalar or field.kind == .enumeration or field.kind == .map or field.kind == .message or field.kind == .group) return true;
    }
    if (messageHasJsonExtensions(ctx, message)) return true;
    return false;
}

pub fn messageJsonStringifyHasFields(ctx: *const CodegenContext, message: *const schema.MessageDescriptor) bool {
    for (message.fields.items) |field| {
        if (field.oneof_name == null and fieldJsonStringifySupported(ctx, field)) return true;
    }
    for (message.oneofs.items) |oneof| {
        if (oneofHasJsonField(ctx, message, oneof.name)) return true;
    }
    if (messageHasJsonExtensions(ctx, message)) return true;
    return false;
}

pub fn messageJsonStringifyUsesAllocator(ctx: *const CodegenContext, message: *const schema.MessageDescriptor) bool {
    for (message.fields.items) |field| {
        if (field.kind == .message or field.kind == .group) return true;
        if (field.kind == .map and jsonMapStringifyValueUsesAllocator(ctx, field.kind.map.value.*)) return true;
    }
    if (messageHasJsonExtensions(ctx, message)) return true;
    return false;
}

pub fn jsonMapStringifyValueUsesAllocator(ctx: *const CodegenContext, kind: schema.FieldKind) bool {
    return switch (kind) {
        .message, .group => |name| cg.codegenCanReferenceMessageWithContext(ctx, name),
        else => false,
    };
}

pub fn messageJsonStringifyUsesOptions(ctx: *const CodegenContext, message: *const schema.MessageDescriptor) bool {
    for (message.fields.items) |field| {
        if (field.oneof_name == null and fieldJsonStringifySupported(ctx, field)) return true;
    }
    for (message.oneofs.items) |oneof| {
        if (oneofHasJsonField(ctx, message, oneof.name)) return true;
    }
    if (messageHasJsonOptionUsingExtensions(ctx, message)) return true;
    return false;
}

pub fn fieldJsonStringifySupported(ctx: *const CodegenContext, field: schema.FieldDescriptor) bool {
    return switch (field.kind) {
        .scalar, .enumeration => true,
        .message, .group => |name| cg.codegenCanReferenceMessageWithContext(ctx, name),
        .map => |map_type| jsonMapValueSupported(ctx, map_type.value.*),
    };
}

pub fn oneofHasJsonField(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, oneof_name: []const u8) bool {
    for (message.fields.items) |field| {
        if (field.oneof_name) |name| {
            if (std.mem.eql(u8, name, oneof_name) and fieldJsonStringifySupported(ctx, field)) return true;
        }
    }
    return false;
}

pub fn messageJsonParseUsesArenaAllocator(ctx: *const CodegenContext, message: *const schema.MessageDescriptor) bool {
    for (message.fields.items) |field| {
        switch (field.kind) {
            .scalar => |scalar| if (scalar == .bytes) return true,
            .message, .group => return true,
            .map => |map_type| switch (map_type.value.*) {
                .scalar => |scalar| if (scalar == .bytes) return true,
                .message, .group => return true,
                else => {},
            },
            else => {},
        }
    }
    if (messageHasJsonMessageExtension(ctx, message)) return true;
    return false;
}

pub fn fieldJsonParseUsesAllocator(ctx: *const CodegenContext, field: *const schema.FieldDescriptor) bool {
    if (field.kind == .map) return true;
    if (field.cardinality == .repeated) {
        return field.kind == .scalar or field.kind == .enumeration or field.kind == .message or field.kind == .group;
    }
    if (field.kind == .scalar or field.kind == .enumeration) return false;
    if (field.oneof_name != null) return cg.typedOneofMessageFieldWithContext(ctx, field) != null;
    return cg.typedSingularMessageFieldWithContext(ctx, field) != null;
}

pub fn messageHasJsonExtensions(ctx: *const CodegenContext, message: *const schema.MessageDescriptor) bool {
    const file = ctx.file;
    for (file.extensions.items) |*field| {
        if (cg.extensionAppliesToMessage(file, message, field) and jsonExtensionSupportedWithContext(ctx, field)) return true;
    }
    for (file.messages.items) |*scope| {
        if (messageScopeHasJsonExtensions(ctx, message, scope)) return true;
    }
    return false;
}

pub fn messageScopeHasJsonExtensions(ctx: *const CodegenContext, target: *const schema.MessageDescriptor, scope: *const schema.MessageDescriptor) bool {
    const file = ctx.file;
    for (scope.extensions.items) |*field| {
        if (cg.extensionAppliesToMessage(file, target, field) and jsonExtensionSupportedWithContext(ctx, field)) return true;
    }
    for (scope.messages.items) |*_pbz_nested| {
        if (messageScopeHasJsonExtensions(ctx, target, _pbz_nested)) return true;
    }
    return false;
}

pub fn messageHasJsonOptionUsingExtensions(ctx: *const CodegenContext, message: *const schema.MessageDescriptor) bool {
    const file = ctx.file;
    for (file.extensions.items) |*field| {
        if (cg.extensionAppliesToMessage(file, message, field) and jsonExtensionUsesOptions(ctx, field)) return true;
    }
    for (file.messages.items) |*scope| {
        if (messageScopeHasJsonOptionUsingExtensions(ctx, message, scope)) return true;
    }
    return false;
}

pub fn messageScopeHasJsonOptionUsingExtensions(ctx: *const CodegenContext, target: *const schema.MessageDescriptor, scope: *const schema.MessageDescriptor) bool {
    const file = ctx.file;
    for (scope.extensions.items) |*field| {
        if (cg.extensionAppliesToMessage(file, target, field) and jsonExtensionUsesOptions(ctx, field)) return true;
    }
    for (scope.messages.items) |*_pbz_nested| {
        if (messageScopeHasJsonOptionUsingExtensions(ctx, target, _pbz_nested)) return true;
    }
    return false;
}

pub fn messageHasJsonMessageExtension(ctx: *const CodegenContext, message: *const schema.MessageDescriptor) bool {
    const file = ctx.file;
    for (file.extensions.items) |*field| {
        if (cg.extensionAppliesToMessage(file, message, field) and jsonExtensionUsesArenaWithContext(ctx, field)) return true;
    }
    for (file.messages.items) |*scope| {
        if (messageScopeHasJsonMessageExtension(ctx, message, scope)) return true;
    }
    return false;
}

pub fn messageScopeHasJsonMessageExtension(ctx: *const CodegenContext, target: *const schema.MessageDescriptor, scope: *const schema.MessageDescriptor) bool {
    const file = ctx.file;
    for (scope.extensions.items) |*field| {
        if (cg.extensionAppliesToMessage(file, target, field) and jsonExtensionUsesArenaWithContext(ctx, field)) return true;
    }
    for (scope.messages.items) |*_pbz_nested| {
        if (messageScopeHasJsonMessageExtension(ctx, target, _pbz_nested)) return true;
    }
    return false;
}

pub fn jsonExtensionSupported(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor) bool {
    return switch (field.kind) {
        .scalar, .enumeration => true,
        .message, .group => |name| cg.codegenCanReferenceMessage(file, name),
        else => false,
    };
}

pub fn jsonExtensionSupportedWithContext(ctx: *const CodegenContext, field: *const schema.FieldDescriptor) bool {
    return switch (field.kind) {
        .scalar, .enumeration => true,
        .message, .group => |name| cg.codegenCanReferenceMessageWithContext(ctx, name),
        else => false,
    };
}

pub fn jsonExtensionUsesOptions(ctx: *const CodegenContext, field: *const schema.FieldDescriptor) bool {
    return switch (field.kind) {
        .enumeration => true,
        .message, .group => |name| cg.codegenCanReferenceMessageWithContext(ctx, name),
        else => false,
    };
}

pub fn jsonExtensionUsesArenaWithContext(ctx: *const CodegenContext, field: *const schema.FieldDescriptor) bool {
    return switch (field.kind) {
        .scalar => |scalar| scalar == .bytes,
        .message, .group => |name| cg.codegenCanReferenceMessageWithContext(ctx, name),
        else => false,
    };
}

pub fn writeJsonClearField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    try cg.indent(writer, depth);
    try writer.writeAll("if (");
    try writeJsonKeyCondition(field, writer);
    try writer.writeAll(") {\n");
    try writeJsonSeenCheck(file, field, writer, depth + 1);
    if (field.cardinality != .repeated) {
        const null_value_type = switch (field.kind) {
            .message => |name| name,
            else => null,
        };
        if (null_value_type) |name| {
            if (std.mem.eql(u8, name, "google.protobuf.Value") and wktJsonSupportAvailable(ctx)) {
                try cg.indent(writer, depth + 1);
                try writer.writeAll("self.");
                try cg.writeQuotedIdent(field.name, writer);
                try writer.writeAll(" = try _pbzJsonParseWktValue(allocator, arena_allocator, value);\n");
                try cg.indent(writer, depth + 1);
                try writer.writeAll("continue;\n");
                try cg.indent(writer, depth);
                try writer.writeAll("}\n");
                return;
            }
        }
    }
    if (field.kind == .map) {
        try cg.indent(writer, depth + 1);
        try writer.writeAll("@This().");
        try cg.writeQuotedIdentWithPrefix(field.name, "deinitMap_", writer);
        try writer.writeAll("(allocator, &self.");
        try cg.writeQuotedIdent(field.name, writer);
        try writer.writeAll(");\n");
    } else if (cg.typedSingularMessageFieldWithContext(ctx, field)) |_| {
        try cg.indent(writer, depth + 1);
        try writer.writeAll("if (self.");
        try cg.writeQuotedIdent(field.name, writer);
        try writer.writeAll(") |*old_value| old_value.deinit(allocator); self.");
        try cg.writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = null;\n");
    } else if (cg.typedRepeatedMessageFieldWithContext(ctx, field)) |_| {
        try cg.indent(writer, depth + 1);
        try writer.writeAll("const old = self.");
        try cg.writeQuotedIdent(field.name, writer);
        try writer.writeAll("; self.");
        try cg.writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = &.{}; for (old) |item| { var mutable = item; mutable.deinit(allocator); } if (old.len != 0) allocator.free(old);\n");
    } else if (field.cardinality == .repeated) {
        try cg.indent(writer, depth + 1);
        try writer.writeAll("const old = self.");
        try cg.writeQuotedIdent(field.name, writer);
        try writer.writeAll("; self.");
        try cg.writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = &.{}; if (old.len != 0) allocator.free(old);\n");
    } else {
        try cg.indent(writer, depth + 1);
        try writer.writeAll("self.");
        try cg.writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = ");
        try cg.writeFieldDefault(file, field.*, writer);
        try writer.writeAll(";\n");
        if (cg.hasPresence(file, field.*)) {
            try cg.indent(writer, depth + 1);
            try writer.writeAll("self.");
            try cg.writePresenceIdent(field.name, writer);
            try writer.writeAll(" = false;\n");
        }
    }
    try cg.indent(writer, depth + 1);
    try writer.writeAll("continue;\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeJsonClearOneofField(ctx: *const CodegenContext, oneof: schema.OneofDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try cg.indent(writer, depth);
    try writer.writeAll("if (");
    try writeJsonKeyCondition(field, writer);
    try writer.writeAll(") {\n");
    const null_value_type = switch (field.kind) {
        .message => |name| name,
        else => null,
    };
    const null_enum_type = switch (field.kind) {
        .enumeration => |name| name,
        else => null,
    };
    if (null_value_type != null and std.mem.eql(u8, null_value_type.?, "google.protobuf.Value") and wktJsonSupportAvailable(ctx)) {
        try cg.indent(writer, depth + 1);
        try writer.writeAll("self.");
        try cg.writeQuotedIdent(oneof.name, writer);
        try writer.writeAll(" = .{ .");
        try cg.writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = try _pbzJsonParseWktValue(allocator, arena_allocator, value) };\n");
    } else if (null_enum_type != null and std.mem.eql(u8, null_enum_type.?, "google.protobuf.NullValue")) {
        try cg.indent(writer, depth + 1);
        try writer.writeAll("self.");
        try cg.writeQuotedIdent(oneof.name, writer);
        try writer.writeAll(" = .{ .");
        try cg.writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = 0 };\n");
    } else {
        try cg.indent(writer, depth + 1);
    }
    try writer.writeAll("continue;\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn messageJsonExtensionCount(ctx: *const CodegenContext, message: *const schema.MessageDescriptor) usize {
    var count: usize = 0;
    for (ctx.file.extensions.items) |*field| {
        if (cg.extensionAppliesToMessage(ctx.file, message, field) and jsonExtensionSupportedWithContext(ctx, field)) count += 1;
    }
    for (ctx.file.messages.items) |*scope| count += scopedJsonExtensionCount(ctx, message, scope);
    return count;
}

pub fn scopedJsonExtensionCount(ctx: *const CodegenContext, target: *const schema.MessageDescriptor, scope: *const schema.MessageDescriptor) usize {
    var count: usize = 0;
    for (scope.extensions.items) |*field| {
        if (cg.extensionAppliesToMessage(ctx.file, target, field) and jsonExtensionSupportedWithContext(ctx, field)) count += 1;
    }
    for (scope.messages.items) |*nested| count += scopedJsonExtensionCount(ctx, target, nested);
    return count;
}

pub fn writeJsonClearExtensions(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    var seen_index = message.fields.items.len;
    for (ctx.file.extensions.items) |*field| {
        if (cg.extensionAppliesToMessage(ctx.file, message, field) and jsonExtensionSupportedWithContext(ctx, field)) {
            try writeJsonClearExtension(ctx.file, field, writer, depth, seen_index);
            seen_index += 1;
        }
    }
    for (ctx.file.messages.items) |*scope| try writeJsonClearScopedExtensions(ctx, message, scope, writer, depth, &seen_index);
}

pub fn writeJsonClearScopedExtensions(ctx: *const CodegenContext, target: *const schema.MessageDescriptor, scope: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize, seen_index: *usize) Error!void {
    for (scope.extensions.items) |*field| {
        if (cg.extensionAppliesToMessage(ctx.file, target, field) and jsonExtensionSupportedWithContext(ctx, field)) {
            try writeJsonClearExtension(ctx.file, field, writer, depth, seen_index.*);
            seen_index.* += 1;
        }
    }
    for (scope.messages.items) |*nested| try writeJsonClearScopedExtensions(ctx, target, nested, writer, depth, seen_index);
}

pub fn writeJsonClearExtension(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize, seen_index: usize) Error!void {
    try cg.indent(writer, depth);
    try writer.writeAll("if (");
    try writeExtensionJsonKeyCondition(file, field, writer);
    try writer.writeAll(") {\n");
    try writeJsonSeenIndexCheck(seen_index, writer, depth + 1);
    try cg.indent(writer, depth + 1);
    try writer.writeAll("try self.clearUnknownFieldsByNumber(allocator, ");
    try cg.writeExtensionHelperReference(field, writer);
    try writer.writeAll(".number); continue;\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeJsonParseField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    switch (field.kind) {
        .scalar, .enumeration => {},
        .message, .group => |name| return try writeJsonParseMessageField(ctx, field, name, writer, depth),
        .map => return try writeJsonParseMapField(ctx, field, writer, depth),
    }
    try cg.indent(writer, depth);
    try writer.writeAll("if (");
    try writeJsonKeyCondition(field, writer);
    try writer.writeAll(") {\n");
    try writeJsonSeenCheck(file, field, writer, depth + 1);
    if (field.cardinality == .repeated) {
        try cg.indent(writer, depth + 1);
        try writer.writeAll("const array = switch (value) { .array => |array| array, else => return error.TypeMismatch };\n");
        try cg.indent(writer, depth + 1);
        try writer.writeAll("var list: std.ArrayList(");
        try cg.writeRepeatedElementType(field.*, writer);
        try writer.writeAll(") = .empty;\n");
        try cg.indent(writer, depth + 1);
        try writer.writeAll("errdefer list.deinit(allocator);\n");
        try cg.indent(writer, depth + 1);
        try writer.writeAll("try list.ensureTotalCapacity(allocator, array.items.len);\n");
        if (field.kind == .enumeration) {
            try cg.indent(writer, depth + 1);
            try writer.writeAll("for (array.items) |item| {\n");
            try cg.indent(writer, depth + 2);
            try writer.writeAll("const parsed_enum = ");
            try writeJsonParseEnumExpr(file, field.kind.enumeration, "item", writer);
            try writer.writeAll(" catch |err| { if (options.ignore_unknown_fields) continue; return err; };\n");
            try cg.indent(writer, depth + 2);
            try writer.writeAll("try list.append(allocator, parsed_enum);\n");
            try cg.indent(writer, depth + 1);
            try writer.writeAll("}\n");
        } else {
            try cg.indent(writer, depth + 1);
            try writer.writeAll("for (array.items) |item| try list.append(allocator, ");
            try writeJsonParseValueExpr(file, field.kind, "item", "arena_allocator", writer);
            try writer.writeAll(");\n");
        }
        try cg.indent(writer, depth + 1);
        try writer.writeAll("self.");
        try cg.writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = blk: { const old = self.");
        try cg.writeQuotedIdent(field.name, writer);
        try writer.writeAll("; const owned = try list.toOwnedSlice(allocator); if (old.len != 0) allocator.free(old); break :blk owned; };\n");
    } else {
        try cg.indent(writer, depth + 1);
        try writer.writeAll("self.");
        try cg.writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = ");
        if (field.kind == .enumeration) {
            try writeJsonParseEnumExpr(file, field.kind.enumeration, "value", writer);
            try writer.writeAll(" catch |err| { if (options.ignore_unknown_fields) continue; return err; }");
        } else {
            try writeJsonParseValueExpr(file, field.kind, "value", "arena_allocator", writer);
        }
        try writer.writeAll(";\n");
        if (cg.hasPresence(file, field.*)) {
            try cg.indent(writer, depth + 1);
            try writer.writeAll("self.");
            try cg.writePresenceIdent(field.name, writer);
            try writer.writeAll(" = true;\n");
        }
    }
    try cg.indent(writer, depth + 1);
    try writer.writeAll("continue;\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeJsonParseMessageField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, type_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    if (!cg.codegenCanReferenceMessageWithContext(ctx, type_name)) return;
    try cg.indent(writer, depth);
    try writer.writeAll("if (");
    try writeJsonKeyCondition(field, writer);
    try writer.writeAll(") {\n");
    try writeJsonSeenCheck(file, field, writer, depth + 1);
    if (wktJson(ctx, type_name)) |wkt_kind| {
        if (field.cardinality == .repeated) {
            try cg.indent(writer, depth + 1);
            try writer.writeAll("const array = switch (value) { .array => |array| array, else => return error.TypeMismatch };\n");
            try cg.indent(writer, depth + 1);
            try writer.writeAll("var list: std.ArrayList(");
            try cg.writeMessageTypeReferenceWithContext(ctx, type_name, writer);
            try writer.writeAll(") = .empty;\n");
            try cg.indent(writer, depth + 1);
            try writer.writeAll("errdefer list.deinit(allocator);\n");
        try cg.indent(writer, depth + 1);
        try writer.writeAll("try list.ensureTotalCapacity(allocator, array.items.len);\n");
            try cg.indent(writer, depth + 1);
            try writer.writeAll("for (array.items) |item| try list.append(allocator, ");
            try writeWktJsonParseExpr(wkt_kind, "item", "arena_allocator", writer);
            try writer.writeAll(");\n");
            try cg.indent(writer, depth + 1);
            try writer.writeAll("self.");
            try cg.writeQuotedIdent(field.name, writer);
            try writer.writeAll(" = blk: { const old = self.");
            try cg.writeQuotedIdent(field.name, writer);
            try writer.writeAll("; const owned = try list.toOwnedSlice(allocator); if (old.len != 0) allocator.free(old); break :blk owned; };\n");
        } else {
            try cg.indent(writer, depth + 1);
            try writer.writeAll("self.");
            try cg.writeQuotedIdent(field.name, writer);
            try writer.writeAll(" = ");
            try writeWktJsonParseExpr(wkt_kind, "value", "arena_allocator", writer);
            try writer.writeAll(";\n");
        }
        try cg.indent(writer, depth + 1);
        try writer.writeAll("continue;\n");
        try cg.indent(writer, depth);
        try writer.writeAll("}\n");
        return;
    }
    if (field.cardinality == .repeated) {
        if (cg.typedRepeatedMessageFieldWithContext(ctx, field)) |_| {
            try cg.indent(writer, depth + 1);
            try writer.writeAll("const array = switch (value) { .array => |array| array, else => return error.TypeMismatch };\n");
            try cg.indent(writer, depth + 1);
            try writer.writeAll("var list: std.ArrayList(");
            try cg.writeMessageTypeReferenceWithContext(ctx, type_name, writer);
            try writer.writeAll(") = .empty;\n");
            try cg.indent(writer, depth + 1);
            try writer.writeAll("errdefer { for (list.items) |item| { var mutable = item; mutable.deinit(allocator); } list.deinit(allocator); }\n");
            try cg.indent(writer, depth + 1);
            try writer.writeAll("try list.ensureTotalCapacity(allocator, array.items.len);\n");
            try cg.indent(writer, depth + 1);
            try writer.writeAll("for (array.items) |item| {\n");
            try cg.indent(writer, depth + 2);
            try writer.writeAll("var _pbz_nested = try ");
            try cg.writeMessageTypeReferenceWithContext(ctx, type_name, writer);
            try writer.writeAll(".jsonParseValueWithOptions(allocator, arena_allocator, item, .{ .ignore_unknown_fields = options.ignore_unknown_fields });\n");
            try cg.indent(writer, depth + 2);
            try writer.writeAll("errdefer _pbz_nested.deinit(allocator);\n");
            try cg.indent(writer, depth + 2);
            try writer.writeAll("try list.append(allocator, _pbz_nested);\n");
            try cg.indent(writer, depth + 1);
            try writer.writeAll("}\n");
            try cg.indent(writer, depth + 1);
            try writer.writeAll("{ const old = self.");
            try cg.writeQuotedIdent(field.name, writer);
            try writer.writeAll("; self.");
            try cg.writeQuotedIdent(field.name, writer);
            try writer.writeAll(" = try list.toOwnedSlice(allocator); for (old) |item| { var mutable = item; mutable.deinit(allocator); } if (old.len != 0) allocator.free(old); }\n");
            try cg.indent(writer, depth + 1);
            try writer.writeAll("continue;\n");
            try cg.indent(writer, depth);
            try writer.writeAll("}\n");
            return;
        }
        try cg.indent(writer, depth + 1);
        try writer.writeAll("const array = switch (value) { .array => |array| array, else => return error.TypeMismatch };\n");
        try cg.indent(writer, depth + 1);
        try writer.writeAll("var list: std.ArrayList([]const u8) = .empty;\n");
        try cg.indent(writer, depth + 1);
        try writer.writeAll("errdefer list.deinit(allocator);\n");
        try cg.indent(writer, depth + 1);
        try writer.writeAll("try list.ensureTotalCapacity(allocator, array.items.len);\n");
        try cg.indent(writer, depth + 1);
        try writer.writeAll("for (array.items) |item| {\n");
        try cg.indent(writer, depth + 2);
        try writer.writeAll("var _pbz_nested = try ");
        try cg.writeMessageTypeReferenceWithContext(ctx, type_name, writer);
        try writer.writeAll(".jsonParseValueWithOptions(arena_allocator, arena_allocator, item, .{ .ignore_unknown_fields = options.ignore_unknown_fields });\n");
        try cg.indent(writer, depth + 2);
        try writer.writeAll("defer _pbz_nested.deinit(arena_allocator);\n");
        try cg.indent(writer, depth + 2);
        try writer.writeAll("try list.append(allocator, try _pbz_nested.encode(arena_allocator));\n");
        try cg.indent(writer, depth + 1);
        try writer.writeAll("}\n");
        try cg.indent(writer, depth + 1);
        try writer.writeAll("self.");
        try cg.writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = blk: { const old = self.");
        try cg.writeQuotedIdent(field.name, writer);
        try writer.writeAll("; const owned = try list.toOwnedSlice(allocator); if (old.len != 0) allocator.free(old); break :blk owned; };\n");
    } else {
        if (cg.typedOneofMessageFieldWithContext(ctx, field)) |_| {
            const oneof_name = field.oneof_name orelse return;
            try cg.indent(writer, depth + 1);
            try writer.writeAll("var _pbz_nested = try ");
            try cg.writeMessageTypeReferenceWithContext(ctx, type_name, writer);
            try writer.writeAll(".jsonParseValueWithOptions(allocator, arena_allocator, value, .{ .ignore_unknown_fields = options.ignore_unknown_fields });\n");
            try cg.indent(writer, depth + 1);
            try writer.writeAll("errdefer _pbz_nested.deinit(allocator);\n");
            try cg.indent(writer, depth + 1);
            try writer.writeAll("self.");
            try cg.writeQuotedIdent(oneof_name, writer);
            try writer.writeAll(" = .{ .");
            try cg.writeQuotedIdent(field.name, writer);
            try writer.writeAll(" = _pbz_nested };\n");
            try cg.indent(writer, depth + 1);
            try writer.writeAll("continue;\n");
            try cg.indent(writer, depth);
            try writer.writeAll("}\n");
            return;
        }
        if (cg.typedSingularMessageFieldWithContext(ctx, field)) |_| {
            try cg.indent(writer, depth + 1);
            try writer.writeAll("var _pbz_nested = try ");
            try cg.writeMessageTypeReferenceWithContext(ctx, type_name, writer);
            try writer.writeAll(".jsonParseValueWithOptions(allocator, arena_allocator, value, .{ .ignore_unknown_fields = options.ignore_unknown_fields });\n");
            try cg.indent(writer, depth + 1);
            try writer.writeAll("errdefer _pbz_nested.deinit(allocator);\n");
            try cg.indent(writer, depth + 1);
            try writer.writeAll("if (self.");
            try cg.writeQuotedIdent(field.name, writer);
            try writer.writeAll(") |*existing| { try existing.mergeFrom(allocator, _pbz_nested); _pbz_nested.deinit(allocator); } else { self.");
            try cg.writeQuotedIdent(field.name, writer);
            try writer.writeAll(" = _pbz_nested; }\n");
            try cg.indent(writer, depth + 1);
            try writer.writeAll("continue;\n");
            try cg.indent(writer, depth);
            try writer.writeAll("}\n");
            return;
        }
        try cg.indent(writer, depth + 1);
        try writer.writeAll("var _pbz_nested = try ");
        try cg.writeMessageTypeReferenceWithContext(ctx, type_name, writer);
        try writer.writeAll(".jsonParseValueWithOptions(arena_allocator, arena_allocator, value, .{ .ignore_unknown_fields = options.ignore_unknown_fields });\n");
        try cg.indent(writer, depth + 1);
        try writer.writeAll("defer _pbz_nested.deinit(arena_allocator);\n");
        try cg.indent(writer, depth + 1);
        try writer.writeAll("self.");
        try cg.writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = try _pbz_nested.encode(arena_allocator);\n");
        if (cg.hasPresence(file, field.*)) {
            try cg.indent(writer, depth + 1);
            try writer.writeAll("self.");
            try cg.writePresenceIdent(field.name, writer);
            try writer.writeAll(" = true;\n");
        }
    }
    try cg.indent(writer, depth + 1);
    try writer.writeAll("continue;\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeJsonParseExtensions(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    var seen_index = message.fields.items.len;
    for (file.extensions.items) |*field| {
        if (cg.extensionAppliesToMessage(file, message, field) and jsonExtensionSupportedWithContext(ctx, field)) {
            try writeJsonParseExtensionField(ctx, field, writer, depth, seen_index);
            seen_index += 1;
        }
    }
    for (file.messages.items) |*scope| try writeJsonParseScopedExtensions(ctx, message, scope, writer, depth, &seen_index);
}

pub fn writeJsonParseScopedExtensions(ctx: *const CodegenContext, target: *const schema.MessageDescriptor, scope: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize, seen_index: *usize) Error!void {
    const file = ctx.file;
    for (scope.extensions.items) |*field| {
        if (cg.extensionAppliesToMessage(file, target, field) and jsonExtensionSupportedWithContext(ctx, field)) {
            try writeJsonParseExtensionField(ctx, field, writer, depth, seen_index.*);
            seen_index.* += 1;
        }
    }
    for (scope.messages.items) |*nested| try writeJsonParseScopedExtensions(ctx, target, nested, writer, depth, seen_index);
}

pub fn writeJsonParseExtensionField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize, seen_index: usize) Error!void {
    const file = ctx.file;
    switch (field.kind) {
        .scalar, .enumeration => return try writeJsonParseScalarExtensionField(file, field, writer, depth, seen_index),
        .message, .group => |type_name| return try writeJsonParseMessageExtensionField(ctx, field, type_name, writer, depth, seen_index),
        else => return,
    }
}

pub fn writeJsonParseScalarExtensionField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize, seen_index: usize) Error!void {
    try cg.indent(writer, depth);
    try writer.writeAll("if (");
    try writeExtensionJsonKeyCondition(file, field, writer);
    try writer.writeAll(") {\n");
    try writeJsonSeenIndexCheck(seen_index, writer, depth + 1);
    if (field.cardinality == .repeated) {
        try cg.indent(writer, depth + 1);
        try writer.writeAll("try self.clearUnknownFieldsByNumber(allocator, ");
        try cg.writeExtensionHelperReference(field, writer);
        try writer.writeAll(".number);\n");
        try cg.indent(writer, depth + 1);
        try writer.writeAll("const array = switch (value) { .array => |array| array, else => return error.TypeMismatch };\n");
        try cg.indent(writer, depth + 1);
        try writer.writeAll("for (array.items) |item| {\n");
        try cg.indent(writer, depth + 2);
        if (field.kind == .enumeration) {
            try writer.writeAll("const parsed_enum = ");
            try writeJsonParseEnumExpr(file, field.kind.enumeration, "item", writer);
            try writer.writeAll(" catch |err| { if (options.ignore_unknown_fields) continue; return err; };\n");
            try cg.indent(writer, depth + 2);
            try writer.writeAll("try ");
            try cg.writeExtensionHelperReference(field, writer);
            try writer.writeAll(".appendToUnknown(self, allocator, parsed_enum);\n");
        } else {
            try writer.writeAll("try ");
            try cg.writeExtensionHelperReference(field, writer);
            try writer.writeAll(".appendToUnknown(self, allocator, ");
            try writeJsonParseValueExpr(file, field.kind, "item", "arena_allocator", writer);
            try writer.writeAll(");\n");
        }
        try cg.indent(writer, depth + 1);
        try writer.writeAll("}\n");
    } else {
        try cg.indent(writer, depth + 1);
        try writer.writeAll("try ");
        try cg.writeExtensionHelperReference(field, writer);
        try writer.writeAll(".replaceInUnknown(self, allocator, ");
        if (field.kind == .enumeration) {
            try writeJsonParseEnumExpr(file, field.kind.enumeration, "value", writer);
            try writer.writeAll(" catch |err| { if (options.ignore_unknown_fields) continue; return err; }");
        } else {
            try writeJsonParseValueExpr(file, field.kind, "value", "arena_allocator", writer);
        }
        try writer.writeAll(");\n");
    }
    try cg.indent(writer, depth + 1);
    try writer.writeAll("continue;\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeJsonParseMessageExtensionField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, type_name: []const u8, writer: *std.Io.Writer, depth: usize, seen_index: usize) Error!void {
    const file = ctx.file;
    if (!cg.codegenCanReferenceMessageWithContext(ctx, type_name)) return;
    try cg.indent(writer, depth);
    try writer.writeAll("if (");
    try writeExtensionJsonKeyCondition(file, field, writer);
    try writer.writeAll(") {\n");
    try writeJsonSeenIndexCheck(seen_index, writer, depth + 1);
    if (field.cardinality == .repeated) {
        try cg.indent(writer, depth + 1);
        try writer.writeAll("try self.clearUnknownFieldsByNumber(allocator, ");
        try cg.writeExtensionHelperReference(field, writer);
        try writer.writeAll(".number);\n");
        try cg.indent(writer, depth + 1);
        try writer.writeAll("const array = switch (value) { .array => |array| array, else => return error.TypeMismatch };\n");
        try cg.indent(writer, depth + 1);
        try writer.writeAll("for (array.items) |item| {\n");
        try cg.indent(writer, depth + 2);
        try writer.writeAll("var _pbz_nested = try ");
        try cg.writeMessageTypeReferenceWithContext(ctx, type_name, writer);
        try writer.writeAll(".jsonParseValueWithOptions(arena_allocator, arena_allocator, item, .{ .ignore_unknown_fields = options.ignore_unknown_fields });\n");
        try cg.indent(writer, depth + 2);
        try writer.writeAll("defer _pbz_nested.deinit(arena_allocator);\n");
        try cg.indent(writer, depth + 2);
        try writer.writeAll("try ");
        try cg.writeExtensionHelperReference(field, writer);
        try writer.writeAll(".appendToUnknown(self, allocator, try _pbz_nested.encode(arena_allocator));\n");
        try cg.indent(writer, depth + 1);
        try writer.writeAll("}\n");
    } else {
        try cg.indent(writer, depth + 1);
        try writer.writeAll("var _pbz_nested = try ");
        try cg.writeMessageTypeReferenceWithContext(ctx, type_name, writer);
        try writer.writeAll(".jsonParseValueWithOptions(arena_allocator, arena_allocator, value, .{ .ignore_unknown_fields = options.ignore_unknown_fields });\n");
        try cg.indent(writer, depth + 1);
        try writer.writeAll("defer _pbz_nested.deinit(arena_allocator);\n");
        try cg.indent(writer, depth + 1);
        try writer.writeAll("try ");
        try cg.writeExtensionHelperReference(field, writer);
        try writer.writeAll(".replaceInUnknown(self, allocator, try _pbz_nested.encode(arena_allocator));\n");
    }
    try cg.indent(writer, depth + 1);
    try writer.writeAll("continue;\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeJsonParseMapField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    const map_type = switch (field.kind) {
        .map => |map| map,
        else => return,
    };
    if (!jsonMapValueSupported(ctx, map_type.value.*)) return;
    try cg.indent(writer, depth);
    try writer.writeAll("if (");
    try writeJsonKeyCondition(field, writer);
    try writer.writeAll(") {\n");
    try writeJsonSeenCheck(file, field, writer, depth + 1);
    try cg.indent(writer, depth + 1);
    try writer.writeAll("const object_value = switch (value) { .object => |map_object| map_object, else => return error.TypeMismatch };\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("@This().");
    try cg.writeQuotedIdentWithPrefix(field.name, "deinitMap_", writer);
    try writer.writeAll("(allocator, &self.");
    try cg.writeQuotedIdent(field.name, writer);
    try writer.writeAll(");\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("try self.");
    try cg.writeQuotedIdent(field.name, writer);
    try writer.writeAll(".ensureUnusedCapacity(allocator, object_value.count());\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("var map_it = object_value.iterator();\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("while (map_it.next()) |map_entry| {\n");
    try cg.indent(writer, depth + 2);
    if (map_type.value.* == .enumeration) {
        try writer.writeAll("const parsed_value = ");
        try writeJsonParseEnumExpr(file, map_type.value.enumeration, "map_entry.value", writer);
        try writer.writeAll(" catch |err| { if (options.ignore_unknown_fields) continue; return err; };\n");
        try cg.indent(writer, depth + 2);
        try writer.writeAll("try @This().");
        try cg.writeQuotedIdentWithPrefix(field.name, "putMapEntry_", writer);
        try writer.writeAll("(allocator, &self.");
        try cg.writeQuotedIdent(field.name, writer);
        try writer.writeAll(", .{ .key = ");
        try writeJsonParseMapKeyExpr(map_type.key, "map_entry.key", writer);
        try writer.writeAll(", .value = parsed_value });\n");
    } else if (cg.typedMapMessageValueWithContext(ctx, field)) |type_name| {
        try writer.writeAll("{\n");
        try cg.indent(writer, depth + 3);
        try writer.writeAll("var parsed_value = try ");
        try cg.writeMessageTypeReferenceWithContext(ctx, type_name, writer);
        try writer.writeAll(".jsonParseValueWithOptions(allocator, arena_allocator, map_entry.value, .{ .ignore_unknown_fields = options.ignore_unknown_fields });\n");
        try cg.indent(writer, depth + 3);
        try writer.writeAll("errdefer parsed_value.deinit(allocator);\n");
        try cg.indent(writer, depth + 3);
        try writer.writeAll("try @This().");
        try cg.writeQuotedIdentWithPrefix(field.name, "putMapEntry_", writer);
        try writer.writeAll("(allocator, &self.");
        try cg.writeQuotedIdent(field.name, writer);
        try writer.writeAll(", .{ .key = ");
        try writeJsonParseMapKeyExpr(map_type.key, "map_entry.key", writer);
        try writer.writeAll(", .value = parsed_value });\n");
        try cg.indent(writer, depth + 2);
        try writer.writeAll("}\n");
    } else {
        try writer.writeAll("try @This().");
        try cg.writeQuotedIdentWithPrefix(field.name, "putMapEntry_", writer);
        try writer.writeAll("(allocator, &self.");
        try cg.writeQuotedIdent(field.name, writer);
        try writer.writeAll(", .{ .key = ");
        try writeJsonParseMapKeyExpr(map_type.key, "map_entry.key", writer);
        try writer.writeAll(", .value = ");
        try writeJsonParseMapValueExpr(ctx, field, map_type.value.*, "map_entry.value", "arena_allocator", writer);
        try writer.writeAll(" });\n");
    }
    try cg.indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("continue;\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeJsonParseMapKeyExpr(scalar: schema.ScalarType, key_expr: []const u8, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .string => try writer.writeAll(key_expr),
        .bool => try writer.print("try @This().jsonMapKeyBool({s})", .{key_expr}),
        .int32, .sint32, .sfixed32 => try writer.print("try std.fmt.parseInt(i32, {s}, 10)", .{key_expr}),
        .int64, .sint64, .sfixed64 => try writer.print("try std.fmt.parseInt(i64, {s}, 10)", .{key_expr}),
        .uint32, .fixed32 => try writer.print("try std.fmt.parseInt(u32, {s}, 10)", .{key_expr}),
        .uint64, .fixed64 => try writer.print("try std.fmt.parseInt(u64, {s}, 10)", .{key_expr}),
        .double, .float, .bytes => try writer.writeAll("@compileError(\"invalid map key\")"),
    }
}

pub fn writeJsonParseOneofField(ctx: *const CodegenContext, oneof: schema.OneofDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    switch (field.kind) {
        .scalar, .enumeration, .message, .group => {},
        else => return,
    }
    try cg.indent(writer, depth);
    try writer.writeAll("if (");
    try writeJsonKeyCondition(field, writer);
    try writer.writeAll(") {\n");
    try writeJsonSeenCheck(file, field, writer, depth + 1);
    const maybe_message_type = switch (field.kind) {
        .message, .group => |type_name| type_name,
        else => null,
    };
    if (maybe_message_type) |type_name| {
        if (wktJson(ctx, type_name)) |wkt_kind| {
            try cg.indent(writer, depth + 1);
            try writer.writeAll("self.");
            try cg.writeQuotedIdent(oneof.name, writer);
            try writer.writeAll(" = .{ .");
            try cg.writeQuotedIdent(field.name, writer);
            try writer.writeAll(" = ");
            try writeWktJsonParseExpr(wkt_kind, "value", "arena_allocator", writer);
            try writer.writeAll(" };\n");
            try cg.indent(writer, depth + 1);
            try writer.writeAll("continue;\n");
            try cg.indent(writer, depth);
            try writer.writeAll("}\n");
            return;
        }
        try cg.indent(writer, depth + 1);
        if (cg.codegenCanReferenceMessageWithContext(ctx, type_name)) {
            if (cg.typedOneofMessageFieldWithContext(ctx, field)) |_| {
                try writer.writeAll("{ var _pbz_nested = try ");
                try cg.writeMessageTypeReferenceWithContext(ctx, type_name, writer);
                try writer.writeAll(".jsonParseValueWithOptions(allocator, arena_allocator, value, .{ .ignore_unknown_fields = options.ignore_unknown_fields }); errdefer _pbz_nested.deinit(allocator); ");
                try cg.writeOneofDeinitCall(oneof.name, writer);
                try writer.writeAll(" self.");
                try cg.writeQuotedIdent(oneof.name, writer);
                try writer.writeAll(" = .{ .");
                try cg.writeQuotedIdent(field.name, writer);
                try writer.writeAll(" = _pbz_nested }; }\n");
                try cg.indent(writer, depth + 1);
                try writer.writeAll("continue;\n");
                try cg.indent(writer, depth);
                try writer.writeAll("}\n");
                return;
            } else {
                try writer.writeAll("{ var _pbz_nested = try ");
                try cg.writeMessageTypeReferenceWithContext(ctx, type_name, writer);
                try writer.writeAll(".jsonParseValueWithOptions(arena_allocator, arena_allocator, value, .{ .ignore_unknown_fields = options.ignore_unknown_fields }); defer _pbz_nested.deinit(arena_allocator); const payload = try _pbz_nested.encode(arena_allocator); ");
                try cg.writeOneofDeinitCall(oneof.name, writer);
                try writer.writeAll(" self.");
                try cg.writeQuotedIdent(oneof.name, writer);
                try writer.writeAll(" = .{ .");
                try cg.writeQuotedIdent(field.name, writer);
                try writer.writeAll(" = payload }; }\n");
                try cg.indent(writer, depth + 1);
                try writer.writeAll("continue;\n");
                try cg.indent(writer, depth);
                try writer.writeAll("}\n");
                return;
            }
        } else {
            try cg.writeOneofDeinitCall(oneof.name, writer);
            try writer.writeAll(" self.");
            try cg.writeQuotedIdent(oneof.name, writer);
            try writer.writeAll(" = .{ .");
            try cg.writeQuotedIdent(field.name, writer);
            try writer.writeAll(" = ");
            try writeJsonParseValueExpr(file, field.kind, "value", "arena_allocator", writer);
        }
    } else if (field.kind == .enumeration) {
        try cg.indent(writer, depth + 1);
        try cg.writeOneofDeinitCall(oneof.name, writer);
        try writer.writeAll(" self.");
        try cg.writeQuotedIdent(oneof.name, writer);
        try writer.writeAll(" = .{ .");
        try cg.writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = ");
        try writeJsonParseEnumExpr(file, field.kind.enumeration, "value", writer);
        try writer.writeAll(" catch |err| { if (options.ignore_unknown_fields) continue; return err; }");
    } else {
        try cg.indent(writer, depth + 1);
        try cg.writeOneofDeinitCall(oneof.name, writer);
        try writer.writeAll(" self.");
        try cg.writeQuotedIdent(oneof.name, writer);
        try writer.writeAll(" = .{ .");
        try cg.writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = ");
        try writeJsonParseValueExpr(file, field.kind, "value", "arena_allocator", writer);
    }
    try writer.writeAll(" };\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("continue;\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeJsonKeyCondition(field: *const schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("std.mem.eql(u8, key, ");
    try cg.writeZigStringLiteral(field.name, writer);
    try writer.writeAll(")");
    if (field.json_name) |json_name| {
        if (!std.mem.eql(u8, json_name, field.name)) {
            try writer.writeAll(" or std.mem.eql(u8, key, ");
            try cg.writeZigStringLiteral(json_name, writer);
            try writer.writeAll(")");
        }
    } else if (std.mem.indexOfScalar(u8, field.name, '_') != null) {
        try writer.writeAll(" or std.mem.eql(u8, key, ");
        try cg.writeZigLowerCamelStringLiteral(field.name, writer);
        try writer.writeAll(")");
    }
}

pub fn writeExtensionJsonKeyCondition(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("std.mem.eql(u8, key, ");
    try cg.writeExtensionTextNameLiteral(file, field, true, writer);
    try writer.writeAll(")");
    if (cg.extensionHasLeafAlias(file, field)) {
        try writer.writeAll(" or std.mem.eql(u8, key, ");
        try cg.writeExtensionTextNameLiteral(file, field, false, writer);
        try writer.writeAll(")");
    }
}

pub fn writeJsonParseValueExpr(file: *const schema.FileDescriptor, kind: schema.FieldKind, value_expr: []const u8, arena_expr: []const u8, writer: *std.Io.Writer) Error!void {
    switch (kind) {
        .scalar => |scalar| switch (scalar) {
            .double => try writer.print("try @This().jsonFloat(f64, {s})", .{value_expr}),
            .float => try writer.print("try @This().jsonFloat(f32, {s})", .{value_expr}),
            .int32, .sint32, .sfixed32 => try writer.print("try @This().jsonInt(i32, {s})", .{value_expr}),
            .int64, .sint64, .sfixed64 => try writer.print("try @This().jsonInt(i64, {s})", .{value_expr}),
            .uint32, .fixed32 => try writer.print("try @This().jsonInt(u32, {s})", .{value_expr}),
            .uint64, .fixed64 => try writer.print("try @This().jsonInt(u64, {s})", .{value_expr}),
            .bool => try writer.print("try @This().jsonBool({s})", .{value_expr}),
            .string => try writer.print("try @This().jsonString({s})", .{value_expr}),
            .bytes => try writer.print("try @This().jsonBytes({s}, {s})", .{ arena_expr, value_expr }),
        },
        .enumeration => |name| {
            try writer.print("try @This().jsonEnum({s}, ", .{value_expr});
            try cg.enum_emit.writeEnumNameArray(file, name, writer);
            try writer.writeAll(", ");
            try cg.enum_emit.writeEnumNumberArray(file, name, writer);
            try writer.writeAll(", ");
            try writer.writeAll(if (cg.enum_emit.enumIsClosed(file, name)) "true" else "false");
            try writer.writeAll(")");
        },
        else => try writer.writeAll("@compileError(\"unsupported JSON parse field kind\")"),
    }
}

pub fn writeJsonParseEnumExpr(file: *const schema.FileDescriptor, enum_name: []const u8, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.print("@This().jsonEnum({s}, ", .{value_expr});
    try cg.enum_emit.writeEnumNameArray(file, enum_name, writer);
    try writer.writeAll(", ");
    try cg.enum_emit.writeEnumNumberArray(file, enum_name, writer);
    try writer.writeAll(", ");
    try writer.writeAll(if (cg.enum_emit.enumIsClosed(file, enum_name)) "true" else "false");
    try writer.writeAll(")");
}

pub fn writeJsonParseMapValueExpr(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, kind: schema.FieldKind, value_expr: []const u8, arena_expr: []const u8, writer: *std.Io.Writer) Error!void {
    const file = ctx.file;
    switch (kind) {
        .message => |name| if (cg.codegenCanReferenceMessageWithContext(ctx, name)) {
            if (wktJson(ctx, name)) |wkt_kind| {
                try writeWktJsonParseExpr(wkt_kind, value_expr, arena_expr, writer);
                return;
            }
            if (cg.typedMapMessageValueWithContext(ctx, field)) |_| {
                try writer.writeAll("blk: { var _pbz_nested = try ");
                try cg.writeMessageTypeReferenceWithContext(ctx, name, writer);
                try writer.writeAll(".jsonParseValueWithOptions(allocator, ");
                try writer.writeAll(arena_expr);
                try writer.writeAll(", ");
                try writer.writeAll(value_expr);
                try writer.writeAll(", .{ .ignore_unknown_fields = options.ignore_unknown_fields }); errdefer _pbz_nested.deinit(allocator");
                try writer.writeAll("); break :blk nested; }");
            } else {
                try writer.writeAll("blk: { var _pbz_nested = try ");
                try cg.writeMessageTypeReferenceWithContext(ctx, name, writer);
                try writer.writeAll(".jsonParseValueWithOptions(");
                try writer.writeAll(arena_expr);
                try writer.writeAll(", ");
                try writer.writeAll(arena_expr);
                try writer.writeAll(", ");
                try writer.writeAll(value_expr);
                try writer.writeAll(", .{ .ignore_unknown_fields = options.ignore_unknown_fields }); defer _pbz_nested.deinit(");
                try writer.writeAll(arena_expr);
                try writer.writeAll("); break :blk try _pbz_nested.encode(");
                try writer.writeAll(arena_expr);
                try writer.writeAll("); }");
            }
        } else try writer.writeAll("@compileError(\"unsupported JSON parse field kind\")"),
        else => try writeJsonParseValueExpr(file, kind, value_expr, arena_expr, writer),
    }
}




pub fn writeJsonParseHelpers(writer: *std.Io.Writer, depth: usize) Error!void {
    try cg.indent(writer, depth);
    try writer.writeAll(
        \\fn jsonInt(comptime T: type, value: pbz.json.Value) !T {
        \\    return try pbz.json.intValue(T, value);
        \\}
        \\
        \\fn jsonFloat(comptime T: type, value: pbz.json.Value) !T {
        \\    return switch (value) {
        \\        .integer => |v| @as(T, @floatFromInt(v)),
        \\        .float => |v| blk: {
        \\            const out: T = @floatCast(v);
        \\            if (!std.math.isFinite(out)) return error.InvalidNumber;
        \\            break :blk out;
        \\        },
        \\        .number_string => |text| blk: {
        \\            const out = std.fmt.parseFloat(T, text) catch return error.InvalidNumber;
        \\            if (!std.math.isFinite(out)) return error.InvalidNumber;
        \\            break :blk out;
        \\        },
        \\        .string => |text| if (std.mem.eql(u8, text, "NaN"))
        \\            std.math.nan(T)
        \\        else if (std.mem.eql(u8, text, "Infinity"))
        \\            std.math.inf(T)
        \\        else if (std.mem.eql(u8, text, "-Infinity"))
        \\            -std.math.inf(T)
        \\        else blk: {
        \\            const out = std.fmt.parseFloat(T, text) catch return error.InvalidNumber;
        \\            if (!std.math.isFinite(out)) return error.InvalidNumber;
        \\            break :blk out;
        \\        },
        \\        else => error.TypeMismatch,
        \\    };
        \\}
        \\
        \\fn jsonBool(value: pbz.json.Value) !bool {
        \\    return switch (value) {
        \\        .bool => |v| v,
        \\        else => error.TypeMismatch,
        \\    };
        \\}
        \\
        \\fn jsonString(value: pbz.json.Value) ![]const u8 {
        \\    return switch (value) {
        \\        .string => |v| v,
        \\        else => error.TypeMismatch,
        \\    };
        \\}
        \\
        \\fn jsonBytes(allocator: std.mem.Allocator, value: pbz.json.Value) ![]const u8 {
        \\    return try @This().jsonDecodeBase64(allocator, try @This().jsonString(value));
        \\}
        \\
        \\fn jsonEnum(value: pbz.json.Value, comptime names: []const []const u8, comptime numbers: []const i32, comptime closed: bool) !i32 {
        \\    return switch (value) {
        \\        .integer => |v| try @This().jsonEnumNumber(std.math.cast(i32, v) orelse return error.Overflow, numbers, closed),
        \\        .number_string => |text| try @This().jsonEnumNumber(try std.fmt.parseInt(i32, text, 10), numbers, closed),
        \\        .string => |text| {
        \\            inline for (names, 0..) |name, i| {
        \\                if (std.mem.eql(u8, text, name)) return numbers[i];
        \\            }
        \\            return try @This().jsonEnumNumber(std.fmt.parseInt(i32, text, 10) catch return error.InvalidEnumValue, numbers, closed);
        \\        },
        \\        else => error.TypeMismatch,
        \\    };
        \\}
        \\
        \\fn jsonEnumNumber(value: i32, comptime numbers: []const i32, comptime closed: bool) !i32 {
        \\    if (closed) {
        \\        inline for (numbers) |number| {
        \\            if (value == number) return value;
        \\        }
        \\        return error.InvalidEnumValue;
        \\    }
        \\    return value;
        \\}
        \\
        \\fn jsonWriteEnum(writer: *std.Io.Writer, value: i32, comptime names: []const []const u8, comptime numbers: []const i32, enum_as_name: bool) !void {
        \\    if (!enum_as_name) return try writer.print("{d}", .{value});
        \\    inline for (numbers, 0..) |number, i| {
        \\        if (value == number) return try std.json.Stringify.value(names[i], .{}, writer);
        \\    }
        \\    try writer.print("{d}", .{value});
        \\}
        \\
        \\fn textWriteEnum(writer: *std.Io.Writer, value: i32, comptime names: []const []const u8, comptime numbers: []const i32, enum_as_name: bool) !void {
        \\    if (!enum_as_name) return try writer.print("{d}", .{value});
        \\    inline for (numbers, 0..) |number, i| {
        \\        if (value == number) return try writer.writeAll(names[i]);
        \\    }
        \\    try writer.print("{d}", .{value});
        \\}
        \\
        \\fn enumKnown(value: i32, comptime numbers: []const i32) bool {
        \\    inline for (numbers) |number| {
        \\        if (value == number) return true;
        \\    }
        \\    return false;
        \\}
        \\
        \\fn textFieldValue(line: []const u8, comptime name: []const u8) ?[]const u8 {
        \\    if (!std.mem.startsWith(u8, line, name)) return null;
        \\    const rest = line[name.len..];
        \\    if (rest.len != 0 and rest[0] == ':') {
        \\        const value = rest[1..];
        \\        if (value.len == 0) return value;
        \\        if (value[0] == ' ') {
        \\            const body = value[1..];
        \\            if (body.len == 0 or (body[0] != ' ' and body[0] != '\t' and body[0] != '\r' and body[body.len - 1] != ' ' and body[body.len - 1] != '\t' and body[body.len - 1] != '\r')) return body;
        \\        } else if (value[0] != '\t' and value[0] != '\r' and value[value.len - 1] != ' ' and value[value.len - 1] != '\t' and value[value.len - 1] != '\r') return value;
        \\    }
        \\    const trimmed = std.mem.trimStart(u8, rest, " \t");
        \\    if (trimmed.len == 0 or trimmed[0] != ':') return null;
        \\    return std.mem.trim(u8, trimmed[1..], " \t\r");
        \\}
        \\
        \\fn textBlockField(line: []const u8, comptime name: []const u8) bool {
        \\    if (!std.mem.startsWith(u8, line, name)) return false;
        \\    const rest = line[name.len..];
        \\    if (rest.len == 1 and (rest[0] == '{' or rest[0] == '<')) return true;
        \\    if (rest.len == 2 and rest[0] == ' ' and (rest[1] == '{' or rest[1] == '<')) return true;
        \\    var trimmed = std.mem.trimStart(u8, rest, " \t");
        \\    if (trimmed.len != 0 and trimmed[0] == ':') {
        \\        trimmed = std.mem.trimStart(u8, trimmed[1..], " \t");
        \\    }
        \\    return std.mem.eql(u8, trimmed, "{") or std.mem.eql(u8, trimmed, "<");
        \\}
        \\
        \\fn textNormalizeSeparators(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
        \\    var out: std.ArrayList(u8) = .empty;
        \\    errdefer out.deinit(allocator);
        \\    var quote: ?u8 = null;
        \\    var escaped = false;
        \\    var expect_field = true;
        \\    for (text) |c| {
        \\        if (escaped) {
        \\            escaped = false;
        \\            try out.append(allocator, c);
        \\            continue;
        \\        }
        \\        if (quote) |q| {
        \\            if (c == '\\') {
        \\                escaped = true;
        \\            } else if (c == q) {
        \\                quote = null;
        \\            }
        \\            try out.append(allocator, c);
        \\            continue;
        \\        }
        \\        if (c == '"' or c == '\'') {
        \\            quote = c;
        \\            expect_field = false;
        \\            try out.append(allocator, c);
        \\        } else if (c == ';' or c == ',') {
        \\            if (expect_field) return error.InvalidCharacter;
        \\            expect_field = true;
        \\            try out.append(allocator, '\n');
        \\        } else if (c == '{' or c == '<') {
        \\            try out.append(allocator, c);
        \\            try out.append(allocator, '\n');
        \\            expect_field = true;
        \\        } else if (c == '}' or c == '>') {
        \\            try out.append(allocator, '\n');
        \\            try out.append(allocator, c);
        \\            try out.append(allocator, '\n');
        \\            expect_field = false;
        \\        } else {
        \\            if (!std.ascii.isWhitespace(c)) expect_field = false;
        \\            try out.append(allocator, c);
        \\        }
        \\    }
        \\    return try out.toOwnedSlice(allocator);
        \\}
        \\
        \\fn textNeedsSeparatorNormalization(text: []const u8) bool {
        \\    var quote: ?u8 = null;
        \\    var escaped = false;
        \\    for (text, 0..) |c, index| {
        \\        if (escaped) {
        \\            escaped = false;
        \\            continue;
        \\        }
        \\        if (quote) |q| {
        \\            if (c == '\\') {
        \\                escaped = true;
        \\            } else if (c == q) {
        \\                quote = null;
        \\            }
        \\            continue;
        \\        }
        \\        if (c == '"' or c == '\'') {
        \\            quote = c;
        \\        } else if (c == ';' or c == ',') {
        \\            return true;
        \\        } else if ((c == '{' or c == '<') and !@This().textSeparatorHasLineAfter(text, index)) {
        \\            return true;
        \\        } else if ((c == '}' or c == '>') and !@This().textSeparatorHasLineBefore(text, index)) {
        \\            return true;
        \\        }
        \\    }
        \\    return false;
        \\}
        \\
        \\fn textSeparatorHasLineAfter(text: []const u8, index: usize) bool {
        \\    var i = index + 1;
        \\    while (i < text.len and (text[i] == ' ' or text[i] == '\t' or text[i] == '\r')) : (i += 1) {}
        \\    return i >= text.len or text[i] == '\n';
        \\}
        \\
        \\fn textSeparatorHasLineBefore(text: []const u8, index: usize) bool {
        \\    var i = index;
        \\    while (i > 0 and (text[i - 1] == ' ' or text[i - 1] == '\t' or text[i - 1] == '\r')) : (i -= 1) {}
        \\    return i == 0 or text[i - 1] == '\n';
        \\}
        \\
        \\fn textCleanLine(raw_line: []const u8, text_has_comments: bool) []const u8 {
        \\    var end = raw_line.len;
        \\    if (!text_has_comments) return @This().textTrimLine(raw_line);
        \\    var quote: ?u8 = null;
        \\    var escaped = false;
        \\    for (raw_line, 0..) |c, i| {
        \\        if (escaped) {
        \\            escaped = false;
        \\            continue;
        \\        }
        \\        if (quote) |q| {
        \\            if (c == '\\') {
        \\                escaped = true;
        \\            } else if (c == q) {
        \\                quote = null;
        \\            }
        \\            continue;
        \\        }
        \\        if (c == '"' or c == '\'') {
        \\            quote = c;
        \\        } else if (c == '#') {
        \\            end = i;
        \\            break;
        \\        }
        \\    }
        \\    return @This().textTrimLine(raw_line[0..end]);
        \\}
        \\
        \\fn textTrimLine(raw_line: []const u8) []const u8 {
        \\    if (raw_line.len == 0) return raw_line;
        \\    const first = raw_line[0];
        \\    const last = raw_line[raw_line.len - 1];
        \\    if (first != ' ' and first != '\t' and first != '\r' and last != ' ' and last != '\t' and last != '\r' and last != ';' and last != ',') return raw_line;
        \\    var line = std.mem.trim(u8, raw_line, " \t\r");
        \\    while (line.len != 0 and (line[line.len - 1] == ';' or line[line.len - 1] == ',')) {
        \\        line = std.mem.trim(u8, line[0 .. line.len - 1], " \t\r");
        \\    }
        \\    return line;
        \\}
        \\
        \\fn textBool(value: []const u8) !bool {
        \\    if (std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "t") or std.mem.eql(u8, value, "1")) return true;
        \\    if (std.mem.eql(u8, value, "false") or std.mem.eql(u8, value, "f") or std.mem.eql(u8, value, "0")) return false;
        \\    return error.TypeMismatch;
        \\}
        \\
        \\fn textInt(comptime T: type, value: []const u8) !T {
        \\    return try std.fmt.parseInt(T, value, 0);
        \\}
        \\
        \\fn textFloat(comptime T: type, value: []const u8) !T {
        \\    var body = value;
        \\    var negative = false;
        \\    if (body.len != 0 and (body[0] == '-' or body[0] == '+')) {
        \\        negative = body[0] == '-';
        \\        body = body[1..];
        \\    }
        \\    if (body.len >= 2 and body[0] == '0' and (body[1] == 'x' or body[1] == 'X')) return error.TypeMismatch;
        \\    if (body.len > 1 and body[0] == '0' and std.ascii.isDigit(body[1]) and std.mem.indexOfAny(u8, body, ".eE") == null) return error.TypeMismatch;
        \\    if (std.ascii.eqlIgnoreCase(body, "nan")) return std.math.nan(T);
        \\    if (std.ascii.eqlIgnoreCase(body, "inf") or std.ascii.eqlIgnoreCase(body, "infinity")) {
        \\        const parsed = std.math.inf(T);
        \\        return if (negative) -parsed else parsed;
        \\    }
        \\    return try std.fmt.parseFloat(T, value);
        \\}
        \\
        \\fn textUnquote(allocator: std.mem.Allocator, raw_value: []const u8) ![]const u8 {
        \\    var value = raw_value;
        \\    if (value.len >= 2 and value[0] == '[' and value[value.len - 1] == ']') {
        \\        value = std.mem.trim(u8, value[1 .. value.len - 1], " \\t\\r\\n");
        \\    }
        \\    if (value.len >= 2) {
        \\        const quote = value[0];
        \\        if ((quote == '"' or quote == '\'') and value[value.len - 1] == quote) {
        \\            const body = value[1 .. value.len - 1];
        \\            const escaped_or_closed = if (quote == '"') std.mem.indexOfAny(u8, body, "\\\"") else std.mem.indexOfAny(u8, body, "\\'");
        \\            if (escaped_or_closed == null) return try allocator.dupe(u8, body);
        \\        }
        \\    }
        \\    var out: std.ArrayList(u8) = .empty;
        \\    errdefer out.deinit(allocator);
        \\    var i: usize = 0;
        \\    var read_quoted = false;
        \\    while (true) {
        \\        while (i < value.len and std.ascii.isWhitespace(value[i])) : (i += 1) {}
        \\        if (i >= value.len) break;
        \\        const quote = value[i];
        \\        if (quote != '"' and quote != '\'') {
        \\            if (read_quoted) return error.InvalidEscape;
        \\            try out.appendSlice(allocator, value[i..]);
        \\            break;
        \\        }
        \\        read_quoted = true;
        \\        i += 1;
        \\        var closed = false;
        \\        while (i < value.len) {
        \\            const c = value[i];
        \\            i += 1;
        \\            if (c == quote) {
        \\                closed = true;
        \\                break;
        \\            }
        \\            if (c != '\\') {
        \\                try out.append(allocator, c);
        \\                continue;
        \\            }
        \\            if (i >= value.len) return error.InvalidEscape;
        \\            const esc = value[i];
        \\            i += 1;
        \\            switch (esc) {
        \\                'n' => try out.append(allocator, '\n'),
        \\                'r' => try out.append(allocator, '\r'),
        \\                't' => try out.append(allocator, '\t'),
        \\                'a' => try out.append(allocator, 0x07),
        \\                'b' => try out.append(allocator, 0x08),
        \\                'f' => try out.append(allocator, 0x0c),
        \\                'v' => try out.append(allocator, 0x0b),
        \\                '\\' => try out.append(allocator, '\\'),
        \\                '"' => try out.append(allocator, '"'),
        \\                '\'' => try out.append(allocator, '\''),
        \\                '?' => try out.append(allocator, '?'),
        \\                'x', 'X' => {
        \\                    const start = i;
        \\                    var end = i;
        \\                    var decoded: u8 = 0;
        \\                    while (end < value.len and end < start + 2) : (end += 1) {
        \\                        const digit = @This().textHexDigit(value[end]) orelse break;
        \\                        decoded = decoded * 16 + digit;
        \\                    }
        \\                    if (end == start) return error.InvalidEscape;
        \\                    try out.append(allocator, decoded);
        \\                    i = end;
        \\                },
        \\                'u', 'U' => {
        \\                    const count: usize = if (esc == 'u') 4 else 8;
        \\                    var codepoint: u32 = 0;
        \\                    var digits: usize = 0;
        \\                    while (digits < count) : (digits += 1) {
        \\                        if (i >= value.len) return error.InvalidEscape;
        \\                        const digit = @This().textHexDigit(value[i]) orelse return error.InvalidEscape;
        \\                        codepoint = codepoint * 16 + digit;
        \\                        i += 1;
        \\                    }
        \\                    if (codepoint > 0x10ffff or (codepoint >= 0xd800 and codepoint <= 0xdfff)) return error.InvalidEscape;
        \\                    var buf: [4]u8 = undefined;
        \\                    const len = std.unicode.utf8Encode(@intCast(codepoint), &buf) catch return error.InvalidEscape;
        \\                    try out.appendSlice(allocator, buf[0..len]);
        \\                },
        \\                '0'...'7' => {
        \\                    const start = i - 1;
        \\                    var end = i;
        \\                    var decoded: u16 = esc - '0';
        \\                    while (end < value.len and end < start + 3 and value[end] >= '0' and value[end] <= '7') : (end += 1) {
        \\                        decoded = decoded * 8 + (value[end] - '0');
        \\                    }
        \\                    if (decoded > std.math.maxInt(u8)) return error.Overflow;
        \\                    try out.append(allocator, @intCast(decoded));
        \\                    i = end;
        \\                },
        \\                else => |unknown| try out.append(allocator, unknown),
        \\            }
        \\        }
        \\        if (!closed) return error.InvalidEscape;
        \\    }
        \\    return try out.toOwnedSlice(allocator);
        \\}
        \\
        \\fn textHexDigit(c: u8) ?u8 {
        \\    return switch (c) {
        \\        '0'...'9' => c - '0',
        \\        'a'...'f' => c - 'a' + 10,
        \\        'A'...'F' => c - 'A' + 10,
        \\        else => null,
        \\    };
        \\}
        \\
        \\fn textEnum(value: []const u8, comptime names: []const []const u8, comptime numbers: []const i32, comptime closed: bool) !i32 {
        \\    inline for (names, 0..) |name, i| {
        \\        if (std.mem.eql(u8, value, name)) return numbers[i];
        \\    }
        \\    const number = try std.fmt.parseInt(i32, value, 10);
        \\    if (closed) {
        \\        inline for (numbers) |known| {
        \\            if (number == known) return number;
        \\        }
        \\        return error.InvalidEnumValue;
        \\    }
        \\    return number;
        \\}
        \\
        \\fn textUnknownField(allocator: std.mem.Allocator, line: []const u8) !?[]const u8 {
        \\    var colon_index: ?usize = null;
        \\    for (line, 0..) |c, i| {
        \\        if (c == ':') { colon_index = i; break; }
        \\        if (i == 0 and !std.ascii.isDigit(c)) return null;
        \\        if (i != 0 and !std.ascii.isDigit(c)) return null;
        \\    }
        \\    const idx = colon_index orelse return null;
        \\    const number = try std.fmt.parseInt(pbz.FieldNumber, std.mem.trim(u8, line[0..idx], " \t\r"), 10);
        \\    const value = std.mem.trim(u8, line[idx + 1 ..], " \t\r");
        \\    var raw = pbz.Writer.init(allocator);
        \\    defer raw.deinit();
        \\    if (value.len >= 2 and ((value[0] == '"' and value[value.len - 1] == '"') or (value[0] == '\'' and value[value.len - 1] == '\''))) {
        \\        const bytes = try @This().textUnquote(allocator, value);
        \\        defer allocator.free(bytes);
        \\        try raw.writeBytes(number, bytes);
        \\    } else {
        \\        try raw.writeUInt64(number, try std.fmt.parseInt(u64, value, 0));
        \\    }
        \\    return try raw.toOwnedSlice();
        \\}
        \\
        \\fn textUnknownGroup(allocator: std.mem.Allocator, line: []const u8, lines: anytype, text_has_comments: bool) !?[]const u8 {
        \\    var end: usize = 0;
        \\    while (end < line.len and std.ascii.isDigit(line[end])) : (end += 1) {}
        \\    if (end == 0) return null;
        \\    const rest = std.mem.trim(u8, line[end..], " \t\r");
        \\    if (!std.mem.eql(u8, rest, "{") and !std.mem.eql(u8, rest, "<")) return null;
        \\    const number = try std.fmt.parseInt(pbz.FieldNumber, line[0..end], 10);
        \\    var raw = pbz.Writer.init(allocator);
        \\    defer raw.deinit();
        \\    try raw.writeTag(number, .start_group);
        \\    while (lines.next()) |raw_line| {
        \\        const child = @This().textCleanLine(raw_line, text_has_comments);
        \\        if (child.len == 0) continue;
        \\        if (std.mem.eql(u8, child, "}") or std.mem.eql(u8, child, ">")) {
        \\            try raw.writeTag(number, .end_group);
        \\            return try raw.toOwnedSlice();
        \\        }
        \\        if (try @This().textUnknownField(allocator, child)) |field_raw| {
        \\            defer allocator.free(field_raw);
        \\            try raw.appendSlice(field_raw);
        \\            continue;
        \\        }
        \\        if (try @This().textUnknownGroup(allocator, child, lines, text_has_comments)) |group_raw| {
        \\            defer allocator.free(group_raw);
        \\            try raw.appendSlice(group_raw);
        \\            continue;
        \\        }
        \\        return error.UnknownField;
        \\    }
        \\    return error.UnexpectedEof;
        \\}
        \\
        \\fn textWriteUnknownRaw(raw: []const u8, writer: *std.Io.Writer) !void {
        \\    var r = pbz.Reader.init(raw);
        \\    while (try r.nextTag()) |tag| try @This().textWriteUnknownField(tag, &r, writer);
        \\}
        \\
        \\fn textLikelyUnknownMessage(bytes: []const u8) bool {
        \\    if (bytes.len == 0) return false;
        \\    var reader = pbz.Reader.init(bytes);
        \\    while (true) {
        \\        const tag = reader.nextTag() catch return false;
        \\        const actual = tag orelse return reader.eof();
        \\        reader.skipValue(actual) catch return false;
        \\    }
        \\}
        \\
        \\fn textWriteQuotedBytes(bytes: []const u8, writer: *std.Io.Writer) !void {
        \\    try writer.writeByte('"');
        \\    for (bytes) |c| {
        \\        if (c == '\\') try writer.writeAll("\\\\") else if (c == '"') try writer.writeAll("\\\"") else if (c == '\n') try writer.writeAll("\\n") else if (c == '\r') try writer.writeAll("\\r") else if (c == '\t') try writer.writeAll("\\t") else if (c >= 0x20 and c <= 0x7e) try writer.writeByte(c) else try writer.print("\\{o:0>3}", .{c});
        \\    }
        \\    try writer.writeByte('"');
        \\}
        \\
        \\fn textWriteUnknownField(tag: pbz.wire.Tag, r: *pbz.Reader, writer: *std.Io.Writer) !void {
        \\    switch (tag.wire_type) {
        \\        .varint => try writer.print("{d}: {d}\n", .{ tag.number, try r.readVarint() }),
        \\        .fixed32 => try writer.print("{d}: {d}\n", .{ tag.number, try r.readFixed32() }),
        \\        .fixed64 => try writer.print("{d}: {d}\n", .{ tag.number, try r.readFixed64() }),
        \\        .length_delimited => {
        \\            const bytes = try r.readBytes();
        \\            if (@This().textLikelyUnknownMessage(bytes)) {
        \\                try writer.print("{d} {{\n", .{tag.number});
        \\                var _pbz_nested_reader = pbz.Reader.init(bytes);
        \\                while (try _pbz_nested_reader.nextTag()) |inner| try @This().textWriteUnknownField(inner, &_pbz_nested_reader, writer);
        \\                try writer.writeAll("}\n");
        \\            } else {
        \\                try writer.print("{d}: ", .{tag.number});
        \\                try @This().textWriteQuotedBytes(bytes, writer);
        \\                try writer.writeByte('\n');
        \\            }
        \\        },
        \\        .start_group => {
        \\            try writer.print("{d} {{\n", .{tag.number});
        \\            while (try r.nextTag()) |inner| {
        \\                if (inner.wire_type == .end_group) {
        \\                    if (inner.number != tag.number) return error.InvalidFieldNumber;
        \\                    try writer.writeAll("}\n");
        \\                    return;
        \\                }
        \\                try @This().textWriteUnknownField(inner, r, writer);
        \\            }
        \\            return error.TruncatedInput;
        \\        },
        \\        .end_group => return error.InvalidWireType,
        \\    }
        \\}
        \\
        \\fn textBlock(allocator: std.mem.Allocator, lines: anytype, text_has_comments: bool) ![]u8 {
        \\    var out: std.Io.Writer.Allocating = .init(allocator);
        \\    errdefer out.deinit();
        \\    var depth: usize = 1;
        \\    while (lines.next()) |raw_line| {
        \\        const line = @This().textCleanLine(raw_line, text_has_comments);
        \\        if (line.len == 0) continue;
        \\        if (std.mem.eql(u8, line, "}") or std.mem.eql(u8, line, ">")) {
        \\            depth -= 1;
        \\            if (depth == 0) return try out.toOwnedSlice();
        \\        }
        \\        if (std.mem.endsWith(u8, line, "{") or std.mem.endsWith(u8, line, "<")) depth += 1;
        \\        try out.writer.writeAll(line);
        \\        try out.writer.writeByte('\n');
        \\    }
        \\    return error.UnexpectedEof;
        \\}
        \\
        \\fn jsonDecodeBase64(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
        \\    return try pbz.json.decodeBase64(allocator, value);
        \\}
        \\
        \\fn jsonMapKeyBool(key: []const u8) !bool {
        \\    if (std.mem.eql(u8, key, "true")) return true;
        \\    if (std.mem.eql(u8, key, "false")) return false;
        \\    return error.TypeMismatch;
        \\}
        \\
        \\fn jsonWriteString(writer: *std.Io.Writer, value: []const u8) !void {
        \\    if (!pbz.validateUtf8(value)) return error.InvalidUtf8;
        \\    try std.json.Stringify.value(value, .{}, writer);
        \\}
        \\
    );
}

pub fn writeJsonField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    switch (field.kind) {
        .scalar => |scalar| try writeJsonScalarField(file, field, scalar, writer, depth),
        .enumeration => |name| try writeJsonEnumField(file, field, name, writer, depth),
        .map => try writeJsonMapField(ctx, field, writer, depth),
        .message, .group => |name| try writeJsonMessageField(ctx, field, name, writer, depth),
    }
}

pub fn writeJsonPrefix(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try cg.indent(writer, depth);
    if (jsonFieldNameMatchesProtoName(field)) {
        try writer.writeAll("try writer.writeAll(if (first) \"\\\"");
        try cg.writeEscapedStringContents(field.name, writer);
        try writer.writeAll("\\\":\" else \",\\\"");
        try cg.writeEscapedStringContents(field.name, writer);
        try writer.writeAll("\\\":\"); first = false;\n");
        return;
    }
    try writer.writeAll("try writer.writeAll(if (options.preserve_proto_field_names) (if (first) \"\\\"");
    try cg.writeEscapedStringContents(field.name, writer);
    try writer.writeAll("\\\":\" else \",\\\"");
    try cg.writeEscapedStringContents(field.name, writer);
    try writer.writeAll("\\\":\") else (if (first) \"\\\"");
    try cg.writeJsonFieldNameLiteralContents(field, writer);
    try writer.writeAll("\\\":\" else \",\\\"");
    try cg.writeJsonFieldNameLiteralContents(field, writer);
    try writer.writeAll("\\\":\")); first = false;\n");
}

pub fn jsonFieldNameMatchesProtoName(field: *const schema.FieldDescriptor) bool {
    if (field.json_name) |json_name| return std.mem.eql(u8, json_name, field.name);
    return std.mem.indexOfScalar(u8, field.name, '_') == null;
}

pub fn writeJsonScalarField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.cardinality == .repeated) {
        try cg.indent(writer, depth);
        try writer.writeAll("if (self.");
        try cg.writeQuotedIdent(field.name, writer);
        try writer.writeAll(".len != 0 or options.always_print_primitive_fields) {\n");
        try writeJsonPrefix(field, writer, depth + 1);
        try cg.indent(writer, depth + 1);
        try writer.writeAll("try writer.writeAll(\"[\");\n");
        try cg.indent(writer, depth + 1);
        try writer.writeAll("for (self.");
        try cg.writeQuotedIdent(field.name, writer);
        try writer.writeAll(", 0..) |item, i| { if (i != 0) try writer.writeAll(\",\"); ");
        try writeJsonScalarValue(scalar, "item", writer);
        try writer.writeAll("; }\n");
        try cg.indent(writer, depth + 1);
        try writer.writeAll("try writer.writeAll(\"]\");\n");
        try cg.indent(writer, depth);
        try writer.writeAll("}\n");
    } else {
        try cg.indent(writer, depth);
        if (cg.hasPresence(file, field.*)) {
            try writer.writeAll("if (self.");
            try cg.writePresenceIdent(field.name, writer);
            if (cg.isRequired(field.*)) {
                try writer.writeAll(") {\n");
            } else {
                try writer.writeAll(" or options.always_print_primitive_fields) {\n");
            }
        } else {
            try cg.writeScalarSkipConditionWithOptions("self.", field.name, scalar, writer);
            try writer.writeAll("{\n");
        }
        try writeJsonPrefix(field, writer, depth + 1);
        try cg.indent(writer, depth + 1);
        try writer.writeAll("const value = self.");
        try cg.writeQuotedIdent(field.name, writer);
        try writer.writeAll(";\n");
        try cg.indent(writer, depth + 1);
        try writeJsonScalarValue(scalar, "value", writer);
        try writer.writeAll(";\n");
        try cg.indent(writer, depth);
        try writer.writeAll("}\n");
    }
}

pub fn writeJsonEnumField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, enum_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.cardinality == .repeated) {
        try cg.indent(writer, depth);
        try writer.writeAll("if (self.");
        try cg.writeQuotedIdent(field.name, writer);
        try writer.writeAll(".len != 0 or options.always_print_primitive_fields) {\n");
        try writeJsonPrefix(field, writer, depth + 1);
        try cg.indent(writer, depth + 1);
        try writer.writeAll("try writer.writeAll(\"[\");\n");
        try cg.indent(writer, depth + 1);
        try writer.writeAll("for (self.");
        try cg.writeQuotedIdent(field.name, writer);
        try writer.writeAll(", 0..) |item, i| { if (i != 0) try writer.writeAll(\",\"); ");
        try writeJsonEnumValue(file, enum_name, "item", writer);
        try writer.writeAll("; }\n");
        try cg.indent(writer, depth + 1);
        try writer.writeAll("try writer.writeAll(\"]\");\n");
        try cg.indent(writer, depth);
        try writer.writeAll("}\n");
    } else {
        try cg.indent(writer, depth);
        if (cg.hasPresence(file, field.*)) {
            try writer.writeAll("if (self.");
            try cg.writePresenceIdent(field.name, writer);
            if (cg.isRequired(field.*)) {
                try writer.writeAll(") {\n");
            } else {
                try writer.writeAll(" or options.always_print_primitive_fields) {\n");
            }
        } else {
            try writer.writeAll("if (self.");
            try cg.writeQuotedIdent(field.name, writer);
            try writer.writeAll(" != 0 or options.always_print_primitive_fields) {\n");
        }
        try writeJsonPrefix(field, writer, depth + 1);
        try cg.indent(writer, depth + 1);
        try writer.writeAll("const value = self.");
        try cg.writeQuotedIdent(field.name, writer);
        try writer.writeAll(";\n");
        try cg.indent(writer, depth + 1);
        try writeJsonEnumValue(file, enum_name, "value", writer);
        try writer.writeAll(";\n");
        try cg.indent(writer, depth);
        try writer.writeAll("}\n");
    }
}

pub fn writeJsonMapField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const map_type = switch (field.kind) {
        .map => |map| map,
        else => return,
    };
    if (!jsonMapValueSupported(ctx, map_type.value.*)) return;
    try cg.indent(writer, depth);
    try writer.writeAll("if (self.");
    try cg.writeQuotedIdent(field.name, writer);
    try writer.writeAll(".count() != 0 or options.always_print_primitive_fields) {\n");
    try writeJsonPrefix(field, writer, depth + 1);
    try cg.indent(writer, depth + 1);
    try writer.writeAll("try writer.writeAll(\"{\");\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("var map_it = self.");
    try cg.writeQuotedIdent(field.name, writer);
    try writer.writeAll(".iterator();\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("var i: usize = 0;\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("while (map_it.next()) |map_entry| : (i += 1) {\n");
    try cg.indent(writer, depth + 2);
    try writer.writeAll("const entry = ");
    try cg.writeQuotedIdentWithSuffix(field.name, "Entry", writer);
    try writer.writeAll("{ .key = map_entry.key_ptr.*, .value = map_entry.value_ptr.* };\n");
    try cg.indent(writer, depth + 2);
    try writer.writeAll("if (i != 0) try writer.writeAll(\",\");\n");
    try cg.indent(writer, depth + 2);
    try writeJsonMapKeyValue(map_type.key, "entry.key", writer);
    try writer.writeAll(";\n");
    try cg.indent(writer, depth + 2);
    try writer.writeAll("try writer.writeAll(\":\");\n");
    try cg.indent(writer, depth + 2);
    try writeJsonMapEntryValue(ctx, field, map_type.value.*, "entry.value", writer);
    try writer.writeAll(";\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("try writer.writeAll(\"}\");\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeJsonMessageField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, type_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    if (!cg.codegenCanReferenceMessageWithContext(ctx, type_name)) return;
    if (wktJson(ctx, type_name)) |wkt_kind| {
        if (field.cardinality == .repeated) {
            try cg.indent(writer, depth);
            try writer.writeAll("if (self.");
            try cg.writeQuotedIdent(field.name, writer);
            try writer.writeAll(".len != 0 or options.always_print_primitive_fields) {\n");
            try writeJsonPrefix(field, writer, depth + 1);
            try cg.indent(writer, depth + 1);
            try writer.writeAll("try writer.writeAll(\"[\");\n");
            try cg.indent(writer, depth + 1);
            try writer.writeAll("for (self.");
            try cg.writeQuotedIdent(field.name, writer);
            try writer.writeAll(", 0..) |item, i| { if (i != 0) try writer.writeAll(\",\"); _ = &item; try ");
            try writeWktJsonStringifyExpr(wkt_kind, "item", writer);
            try writer.writeAll("; }\n");
            try cg.indent(writer, depth + 1);
            try writer.writeAll("try writer.writeAll(\"]\");\n");
            try cg.indent(writer, depth);
            try writer.writeAll("}\n");
        } else {
            try cg.indent(writer, depth);
            try writer.writeAll("if (self.");
            try cg.writeQuotedIdent(field.name, writer);
            try writer.writeAll(") |value| {\n");
            try writeJsonPrefix(field, writer, depth + 1);
            try cg.indent(writer, depth + 1);
            try writer.writeAll("_ = &value;\n");
            try cg.indent(writer, depth + 1);
            try writer.writeAll("try ");
            try writeWktJsonStringifyExpr(wkt_kind, "value", writer);
            try writer.writeAll(";\n");
            try cg.indent(writer, depth);
            try writer.writeAll("}\n");
        }
        return;
    }
    if (field.cardinality == .repeated) {
        try cg.indent(writer, depth);
        try writer.writeAll("if (self.");
        try cg.writeQuotedIdent(field.name, writer);
        try writer.writeAll(".len != 0 or options.always_print_primitive_fields) {\n");
        try writeJsonPrefix(field, writer, depth + 1);
        try cg.indent(writer, depth + 1);
        try writer.writeAll("try writer.writeAll(\"[\");\n");
        try cg.indent(writer, depth + 1);
        try writer.writeAll("for (self.");
        try cg.writeQuotedIdent(field.name, writer);
        try writer.writeAll(", 0..) |item, i| {\n");
        try cg.indent(writer, depth + 2);
        try writer.writeAll("if (i != 0) try writer.writeAll(\",\");\n");
        if (cg.typedRepeatedMessageFieldWithContext(ctx, field)) |_| {
            try cg.indent(writer, depth + 2);
            try writer.writeAll("try item.jsonStringifyWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name, .preserve_proto_field_names = options.preserve_proto_field_names, .always_print_primitive_fields = options.always_print_primitive_fields });\n");
        } else {
            try writeDecodeAndStringifyPayload(ctx, type_name, "item", writer, depth + 2);
        }
        try cg.indent(writer, depth + 1);
        try writer.writeAll("}\n");
        try cg.indent(writer, depth + 1);
        try writer.writeAll("try writer.writeAll(\"]\");\n");
        try cg.indent(writer, depth);
        try writer.writeAll("}\n");
    } else {
        try cg.indent(writer, depth);
        if (cg.typedSingularMessageFieldWithContext(ctx, field)) |_| {
            try writer.writeAll("if (self.");
            try cg.writeQuotedIdent(field.name, writer);
            try writer.writeAll(") |_pbz_nested| {\n");
            try writeJsonPrefix(field, writer, depth + 1);
            try cg.indent(writer, depth + 1);
            try writer.writeAll("try _pbz_nested.jsonStringifyWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name, .preserve_proto_field_names = options.preserve_proto_field_names, .always_print_primitive_fields = options.always_print_primitive_fields });\n");
            try cg.indent(writer, depth);
            try writer.writeAll("}\n");
            return;
        }
        try writer.writeAll("if (self.");
        try cg.writeQuotedIdent(field.name, writer);
        try writer.writeAll(".len != 0");
        if (cg.hasPresence(ctx.file, field.*)) {
            try writer.writeAll(" or self.");
            try cg.writePresenceIdent(field.name, writer);
        }
        try writer.writeAll(") {\n");
        try writeJsonPrefix(field, writer, depth + 1);
        try cg.indent(writer, depth + 1);
        try writer.writeAll("var _pbz_nested = try ");
        try cg.writeMessageTypeReferenceWithContext(ctx, type_name, writer);
        try writer.writeAll(".decode(allocator, self.");
        try cg.writeQuotedIdent(field.name, writer);
        try writer.writeAll(");\n");
        try cg.indent(writer, depth + 1);
        try writer.writeAll("defer _pbz_nested.deinit(allocator);\n");
        try cg.indent(writer, depth + 1);
        try writer.writeAll("try _pbz_nested.jsonStringifyWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name, .preserve_proto_field_names = options.preserve_proto_field_names, .always_print_primitive_fields = options.always_print_primitive_fields });\n");
        try cg.indent(writer, depth);
        try writer.writeAll("}\n");
    }
}

pub fn writeDecodeAndStringifyPayload(ctx: *const CodegenContext, type_name: []const u8, payload_expr: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    try cg.indent(writer, depth);
    try writer.writeAll("var _pbz_nested = try ");
    try cg.writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    try writer.writeAll(".decode(allocator, ");
    try writer.writeAll(payload_expr);
    try writer.writeAll(");\n");
    try cg.indent(writer, depth);
    try writer.writeAll("defer _pbz_nested.deinit(allocator);\n");
    try cg.indent(writer, depth);
    try writer.writeAll("try _pbz_nested.jsonStringifyWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name, .preserve_proto_field_names = options.preserve_proto_field_names, .always_print_primitive_fields = options.always_print_primitive_fields });\n");
}

pub fn jsonMapValueSupported(ctx: *const CodegenContext, kind: schema.FieldKind) bool {
    return switch (kind) {
        .scalar, .enumeration => true,
        .message => |name| cg.codegenCanReferenceMessageWithContext(ctx, name),
        else => false,
    };
}

pub fn writeJsonMapKeyValue(scalar: schema.ScalarType, key_expr: []const u8, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .string => try writer.print("try @This().jsonWriteString(writer, {s})", .{key_expr}),
        .bool => try writer.print("try writer.writeAll(if ({s}) \"\\\"true\\\"\" else \"\\\"false\\\"\")", .{key_expr}),
        .int32, .int64, .uint32, .uint64, .sint32, .sint64, .fixed32, .fixed64, .sfixed32, .sfixed64 => try writer.print("try writer.print(\"\\\"{{d}}\\\"\", .{{{s}}})", .{key_expr}),
        .double, .float, .bytes => try writer.writeAll("@compileError(\"invalid map key\")"),
    }
}

pub fn writeJsonMapEntryValue(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, kind: schema.FieldKind, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    const file = ctx.file;
    switch (kind) {
        .scalar => |scalar| try writeJsonScalarValue(scalar, value_expr, writer),
        .enumeration => |name| try writeJsonEnumValue(file, name, value_expr, writer),
        .message => |name| if (cg.codegenCanReferenceMessageWithContext(ctx, name)) {
            if (wktJson(ctx, name)) |wkt_kind| {
                try writer.writeAll("try ");
                try writeWktJsonStringifyExpr(wkt_kind, value_expr, writer);
                return;
            }
            if (cg.typedMapMessageValueWithContext(ctx, field)) |_| {
                try writer.print("try {s}.jsonStringifyWithOptions(allocator, writer, .{{ .enum_as_name = options.enum_as_name, .preserve_proto_field_names = options.preserve_proto_field_names, .always_print_primitive_fields = options.always_print_primitive_fields }})", .{value_expr});
            } else {
                try writer.writeAll("var _pbz_nested = try ");
                try cg.writeMessageTypeReferenceWithContext(ctx, name, writer);
                try writer.writeAll(".decode(allocator, ");
                try writer.writeAll(value_expr);
                try writer.writeAll("); defer _pbz_nested.deinit(allocator); try _pbz_nested.jsonStringifyWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name, .preserve_proto_field_names = options.preserve_proto_field_names, .always_print_primitive_fields = options.always_print_primitive_fields })");
            }
        } else try writer.writeAll("@compileError(\"unsupported map JSON value\")"),
        else => try writer.writeAll("@compileError(\"unsupported map JSON value\")"),
    }
}

pub fn writeJsonOneof(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, oneof: schema.OneofDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    try cg.indent(writer, depth);
    try writer.writeAll("switch (self.");
    try cg.writeQuotedIdent(oneof.name, writer);
    try writer.writeAll(") {\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll(".none => {},\n");
    for (message.fields.items) |*field| {
        if (field.oneof_name) |name| {
            if (std.mem.eql(u8, name, oneof.name)) {
                try cg.indent(writer, depth + 1);
                try writer.writeAll(".");
                try cg.writeQuotedIdent(field.name, writer);
                try writer.writeAll(" => |value| {\n");
                switch (field.kind) {
                    .scalar => |scalar| {
                        try writeJsonPrefix(field, writer, depth + 2);
                        try cg.indent(writer, depth + 2);
                        try writeJsonScalarValue(scalar, "value", writer);
                        try writer.writeAll(";\n");
                    },
                    .enumeration => |enum_name| {
                        try writeJsonPrefix(field, writer, depth + 2);
                        try cg.indent(writer, depth + 2);
                        try writeJsonEnumValue(file, enum_name, "value", writer);
                        try writer.writeAll(";\n");
                    },
                    .message, .group => |type_name| {
                        if (wktJson(ctx, type_name)) |wkt_kind| {
                            try writeJsonPrefix(field, writer, depth + 2);
                            try cg.indent(writer, depth + 2);
                            try writer.writeAll("_ = &value;\n");
                            try cg.indent(writer, depth + 2);
                            try writer.writeAll("try ");
                            try writeWktJsonStringifyExpr(wkt_kind, "value", writer);
                            try writer.writeAll(";\n");
                        } else if (cg.codegenCanReferenceMessageWithContext(ctx, type_name)) {
                            try writeJsonPrefix(field, writer, depth + 2);
                            if (cg.typedOneofMessageFieldWithContext(ctx, field)) |_| {
                                try cg.indent(writer, depth + 2);
                                try writer.writeAll("try value.jsonStringifyWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name, .preserve_proto_field_names = options.preserve_proto_field_names, .always_print_primitive_fields = options.always_print_primitive_fields });\n");
                            } else {
                                try writeDecodeAndStringifyPayload(ctx, type_name, "value", writer, depth + 2);
                            }
                        } else {
                            try cg.indent(writer, depth + 2);
                            try writer.writeAll("_ = value;\n");
                        }
                    },
                    else => {
                        try cg.indent(writer, depth + 2);
                        try writer.writeAll("_ = value;\n");
                    },
                }
                try cg.indent(writer, depth + 1);
                try writer.writeAll("},\n");
            }
        }
    }
    try cg.indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeJsonExtensionFields(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    for (file.extensions.items) |*field| {
        if (cg.extensionAppliesToMessage(file, message, field) and jsonExtensionSupportedWithContext(ctx, field)) try writeJsonExtensionField(ctx, field, writer, depth);
    }
    for (file.messages.items) |*scope| try writeJsonScopedExtensionFields(ctx, message, scope, writer, depth);
}

pub fn writeJsonScopedExtensionFields(ctx: *const CodegenContext, target: *const schema.MessageDescriptor, scope: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    for (scope.extensions.items) |*field| {
        if (cg.extensionAppliesToMessage(file, target, field) and jsonExtensionSupportedWithContext(ctx, field)) try writeJsonExtensionField(ctx, field, writer, depth);
    }
    for (scope.messages.items) |*nested| try writeJsonScopedExtensionFields(ctx, target, nested, writer, depth);
}

pub fn writeJsonExtensionField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    switch (field.kind) {
        .scalar, .enumeration => {},
        .message => |type_name| {
            if (!cg.codegenCanReferenceMessageWithContext(ctx, type_name)) return;
        },
        else => return,
    }
    try cg.indent(writer, depth);
    try writer.writeAll("{\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("const values = try ");
    try cg.writeExtensionHelperReference(field, writer);
    try writer.writeAll(".decodeAllFromUnknown(self, allocator);\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("defer allocator.free(values);\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("if (values.len != 0) {\n");
    try writeJsonExtensionPrefix(file, field, writer, depth + 2);
    if (field.cardinality == .repeated) {
        try cg.indent(writer, depth + 2);
        try writer.writeAll("try writer.writeAll(\"[\");\n");
        try cg.indent(writer, depth + 2);
        try writer.writeAll("for (values, 0..) |value, i| { if (i != 0) try writer.writeAll(\",\"); ");
        try writeJsonExtensionValue(ctx, field.kind, "value", writer);
        try writer.writeAll("; }\n");
        try cg.indent(writer, depth + 2);
        try writer.writeAll("try writer.writeAll(\"]\");\n");
    } else {
        try cg.indent(writer, depth + 2);
        try writer.writeAll("const value = values[values.len - 1];\n");
        try cg.indent(writer, depth + 2);
        try writeJsonExtensionValue(ctx, field.kind, "value", writer);
        try writer.writeAll(";\n");
    }
    try cg.indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeJsonExtensionValue(ctx: *const CodegenContext, kind: schema.FieldKind, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    const file = ctx.file;
    switch (kind) {
        .scalar => |scalar| try writeJsonScalarValue(scalar, value_expr, writer),
        .enumeration => |name| try writeJsonEnumValue(file, name, value_expr, writer),
        .message, .group => |type_name| {
            try writer.writeAll("try struct { fn write(allocator_: std.mem.Allocator, writer_: *std.Io.Writer, options_: anytype, payload_: []const u8) !void { var _pbz_nested = try ");
            try cg.writeMessageTypeReferenceWithContext(ctx, type_name, writer);
            try writer.writeAll(".decode(allocator_, payload_); defer _pbz_nested.deinit(allocator_); try _pbz_nested.jsonStringifyWithOptions(allocator_, writer_, .{ .enum_as_name = options_.enum_as_name, .preserve_proto_field_names = options_.preserve_proto_field_names, .always_print_primitive_fields = options_.always_print_primitive_fields }); } }.write(allocator, writer, options, ");
            try writer.writeAll(value_expr);
            try writer.writeAll(")");
        },
        else => try writer.writeAll("@compileError(\"unsupported JSON extension value\")"),
    }
}

pub fn writeJsonExtensionPrefix(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try cg.indent(writer, depth);
    try writer.writeAll("try writer.writeAll(if (first) \"\\\"[");
    try cg.writeExtensionTextNameContents(file, field, true, writer);
    try writer.writeAll("]\\\":\" else \",\\\"[");
    try cg.writeExtensionTextNameContents(file, field, true, writer);
    try writer.writeAll("]\\\":\"); first = false;\n");
}

pub fn writeJsonScalarValue(scalar: schema.ScalarType, prefix: []const u8, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .string => try writer.print("try @This().jsonWriteString(writer, {s})", .{prefix}),
        .bytes => try writer.print("try writer.writeByte('\"'); try std.base64.standard.Encoder.encodeWriter(writer, {s}); try writer.writeByte('\"')", .{prefix}),
        .int64, .uint64, .sint64, .fixed64, .sfixed64 => try writer.print("try writer.print(\"\\\"{{d}}\\\"\", .{{{s}}})", .{prefix}),
        .bool => try writer.print("try writer.writeAll(if ({s}) \"true\" else \"false\")", .{prefix}),
        .double, .float => try writer.print("if (std.math.isNan({s})) try writer.writeAll(\"\\\"NaN\\\"\") else if (std.math.isPositiveInf({s})) try writer.writeAll(\"\\\"Infinity\\\"\") else if (std.math.isNegativeInf({s})) try writer.writeAll(\"\\\"-Infinity\\\"\") else try writer.print(\"{{d}}\", .{{{s}}})", .{ prefix, prefix, prefix, prefix }),
        else => try writer.print("try writer.print(\"{{d}}\", .{{{s}}})", .{prefix}),
    }
}

pub fn writeJsonEnumValue(file: *const schema.FileDescriptor, enum_name: []const u8, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    if (std.mem.eql(u8, enum_name, "google.protobuf.NullValue")) {
        try writer.print("_ = &{s}; try writer.writeAll(\"null\")", .{value_expr});
        return;
    }
    try writer.print("try @This().jsonWriteEnum(writer, {s}, ", .{value_expr});
    try cg.enum_emit.writeEnumNameArray(file, enum_name, writer);
    try writer.writeAll(", ");
    try cg.enum_emit.writeEnumNumberArray(file, enum_name, writer);
    try writer.writeAll(", options.enum_as_name");
    try writer.writeAll(")");
}
