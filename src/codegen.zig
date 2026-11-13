const std = @import("std");
const schema = @import("schema.zig");
const plugin = @import("plugin.zig");
const registry_mod = @import("registry.zig");
const wire = @import("wire.zig");
const plugin_emit = @import("codegen/plugin.zig");
const service_emit = @import("codegen/service.zig");
pub const enum_emit = @import("codegen/enum.zig");
const json_emit = @import("codegen/json_emit.zig");
pub const text_emit = @import("codegen/text_emit.zig");

pub const Error = std.mem.Allocator.Error || std.Io.Writer.Error || plugin.Error || registry_mod.Error;

pub const CodegenContext = struct {
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    registry: ?*const registry_mod.Registry = null,
    pbz_import: []const u8 = "pbz",
    emit_json: bool = true,
    emit_text: bool = true,
    emit_descriptor: bool = true,
    output_suffix: []const u8 = ".pb.zig",
    strip_proto_ext: bool = true,
};

pub fn generateZigFile(allocator: std.mem.Allocator, file: *const schema.FileDescriptor) Error![]u8 {
    return try generateZigFileWithContext(.{ .allocator = allocator, .file = file });
}

pub fn generateZigFileWithRegistry(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, registry: *const registry_mod.Registry) Error![]u8 {
    return try generateZigFileWithContext(.{ .allocator = allocator, .file = file, .registry = registry });
}

pub fn generateZigFileWithContext(ctx: CodegenContext) Error![]u8 {
    var arena = std.heap.ArenaAllocator.init(ctx.allocator);
    defer arena.deinit();
    var active_ctx = ctx;
    var resolved_file = try cloneFileForCodegen(arena.allocator(), ctx.file);
    normalizeSyntheticProto3OptionalOneofsForCodegen(&resolved_file);
    if (ctx.registry) |registry| {
        try resolveImportedEnumsForCodegen(arena.allocator(), &resolved_file, registry);
    }
    active_ctx.file = &resolved_file;

    var out: std.Io.Writer.Allocating = .init(ctx.allocator);
    errdefer out.deinit();
    try out.writer.writeAll("const std = @import(\"std\");\nconst pbz = @import(");
    try writeZigStringLiteral(active_ctx.pbz_import, &out.writer);
    try out.writer.writeAll(");\n\n");
    try writeFileMetadata(&active_ctx, &out.writer, 0);
    if (active_ctx.emit_descriptor) {
        var descriptor_file = try cloneFileForCodegen(arena.allocator(), ctx.file);
        descriptor_file.source_code_info = .{};
        if (active_ctx.registry) |registry| {
            try resolveImportedEnumsForCodegen(arena.allocator(), &descriptor_file, registry);
        }
        try writeGeneratedFileDescriptor(&active_ctx, &descriptor_file, &out.writer, 0);
    }
    try writePackagedFileDecls(&active_ctx, &out.writer, 0);
    try json_emit.writeFileRegistryHelper(&active_ctx, &out.writer);
    try json_emit.writeWktJsonHelpers(&active_ctx, &out.writer);
    try json_emit.writeAnyJsonHelpers(&active_ctx, &out.writer);
    return try finalizeGeneratedZig(ctx.allocator, try out.toOwnedSlice());
}

fn finalizeGeneratedZig(allocator: std.mem.Allocator, raw: []u8) Error![]u8 {
    var raw_owned: ?[]u8 = raw;
    errdefer if (raw_owned) |buf| allocator.free(buf);

    const input = trimTrailingBlankLines(raw);
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    var changed = input.len != raw.len;
    var index: usize = 0;
    while (index < input.len) {
        if (input[index] == '"') {
            index = try copyQuotedZigString(input, index, &out.writer);
        } else if (input[index] == '\'') {
            index = try copyQuotedZigChar(input, index, &out.writer);
        } else if (index + 1 < input.len and input[index] == '/' and input[index + 1] == '/') {
            index = try copyZigLineComment(input, index, &out.writer);
        } else if (quotedBareIdent(input, index)) |range| {
            changed = true;
            try out.writer.writeAll(input[range.ident_begin..range.ident_end]);
            index = range.end;
        } else {
            try out.writer.writeByte(input[index]);
            index += 1;
        }
    }

    if (changed) {
        const final = try out.toOwnedSlice();
        allocator.free(raw);
        raw_owned = null;
        return final;
    }
    out.deinit();
    return raw;
}

fn trimTrailingBlankLines(input: []const u8) []const u8 {
    var end = input.len;
    while (end >= 2 and input[end - 1] == '\n' and input[end - 2] == '\n') end -= 1;
    return input[0..end];
}

fn quotedBareIdent(input: []const u8, start: usize) ?struct { ident_begin: usize, ident_end: usize, end: usize } {
    if (start + 2 > input.len or input[start] != '@' or input[start + 1] != '"') return null;
    var index = start + 2;
    while (index < input.len) : (index += 1) {
        switch (input[index]) {
            '\\' => return null,
            '"' => {
                const ident_begin = start + 2;
                const ident_end = index;
                if (!canWriteBareIdent(input[ident_begin..ident_end])) return null;
                return .{ .ident_begin = ident_begin, .ident_end = ident_end, .end = index + 1 };
            },
            else => {},
        }
    }
    return null;
}

fn copyQuotedZigString(input: []const u8, start: usize, writer: *std.Io.Writer) Error!usize {
    var index = start;
    try writer.writeByte(input[index]);
    index += 1;
    while (index < input.len) {
        const c = input[index];
        try writer.writeByte(c);
        index += 1;
        if (c == '\\') {
            if (index < input.len) {
                try writer.writeByte(input[index]);
                index += 1;
            }
        } else if (c == '"') {
            break;
        }
    }
    return index;
}

fn copyQuotedZigChar(input: []const u8, start: usize, writer: *std.Io.Writer) Error!usize {
    var index = start;
    try writer.writeByte(input[index]);
    index += 1;
    while (index < input.len) {
        const c = input[index];
        try writer.writeByte(c);
        index += 1;
        if (c == '\\') {
            if (index < input.len) {
                try writer.writeByte(input[index]);
                index += 1;
            }
        } else if (c == '\'') {
            break;
        }
    }
    return index;
}

fn copyZigLineComment(input: []const u8, start: usize, writer: *std.Io.Writer) Error!usize {
    var index = start;
    while (index < input.len) : (index += 1) {
        const c = input[index];
        try writer.writeByte(c);
        if (c == '\n') {
            index += 1;
            break;
        }
    }
    return index;
}

fn writePackagedFileDecls(ctx: *const CodegenContext, writer: *std.Io.Writer, depth: usize) Error!void {
    if (ctx.file.package.len == 0) return try writeFileDecls(ctx, writer, depth);
    try writePackageNamespace(ctx, ctx.file.package, writer, depth);
}

fn writePackageNamespace(ctx: *const CodegenContext, package: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    const dot = std.mem.indexOfScalar(u8, package, '.');
    const segment = if (dot) |idx| package[0..idx] else package;
    if (segment.len == 0) {
        if (dot) |idx| return try writePackageNamespace(ctx, package[idx + 1 ..], writer, depth);
        return try writeFileDecls(ctx, writer, depth);
    }

    try indent(writer, depth);
    try writer.writeAll("pub const ");
    try writeQuotedIdent(segment, writer);
    try writer.writeAll(" = struct {\n");
    if (dot) |idx| {
        try writePackageNamespace(ctx, package[idx + 1 ..], writer, depth + 1);
    } else {
        try writeFileDecls(ctx, writer, depth + 1);
    }
    try indent(writer, depth);
    try writer.writeAll("};\n\n");
}

fn writeFileDecls(ctx: *const CodegenContext, writer: *std.Io.Writer, depth: usize) Error!void {
    for (ctx.file.enums.items) |*enumeration| try enum_emit.writeEnum(ctx, enumeration, writer, depth);
    for (ctx.file.messages.items) |*message| try writeMessage(ctx, message, writer, depth);
    try writeExtensionMetadata(ctx, writer, depth);
    try service_emit.writeServiceMetadata(ctx, writer, depth);
}

fn cloneFileForCodegen(allocator: std.mem.Allocator, file: *const schema.FileDescriptor) std.mem.Allocator.Error!schema.FileDescriptor {
    var out = file.*;
    out.messages = .empty;
    out.enums = .empty;
    out.extensions = .empty;
    for (file.messages.items) |*message| try out.messages.append(allocator, try cloneMessageForCodegen(allocator, message));
    for (file.enums.items) |enumeration| try out.enums.append(allocator, enumeration);
    for (file.extensions.items) |*field| try out.extensions.append(allocator, try cloneFieldForCodegen(allocator, field));
    return out;
}

fn cloneMessageForCodegen(allocator: std.mem.Allocator, message: *const schema.MessageDescriptor) std.mem.Allocator.Error!schema.MessageDescriptor {
    var out = message.*;
    out.fields = .empty;
    out.oneofs = .empty;
    out.messages = .empty;
    out.extensions = .empty;
    for (message.fields.items) |*field| try out.fields.append(allocator, try cloneFieldForCodegen(allocator, field));
    for (message.oneofs.items) |oneof| try out.oneofs.append(allocator, oneof);
    for (message.messages.items) |*nested| try out.messages.append(allocator, try cloneMessageForCodegen(allocator, nested));
    for (message.extensions.items) |*field| try out.extensions.append(allocator, try cloneFieldForCodegen(allocator, field));
    return out;
}

fn normalizeSyntheticProto3OptionalOneofsForCodegen(file: *schema.FileDescriptor) void {
    for (file.messages.items) |*message| normalizeMessageSyntheticProto3OptionalOneofsForCodegen(message);
}

fn normalizeMessageSyntheticProto3OptionalOneofsForCodegen(message: *schema.MessageDescriptor) void {
    // protoc represents `optional` proto3 scalars as single-field synthetic
    // oneofs in FileDescriptorProto for reflection compatibility. Generated
    // Zig should expose the source-level field shape instead of leaking those
    // implementation details into public APIs, so codegen rewrites synthetic
    // oneofs back to ordinary proto3-optional fields before emitting structs.
    var write_index: usize = 0;
    for (message.oneofs.items, 0..) |oneof, read_index| {
        if (syntheticProto3OptionalFieldIndex(message, oneof.name)) |field_index| {
            message.fields.items[field_index].oneof_name = null;
            continue;
        }
        if (write_index != read_index) message.oneofs.items[write_index] = oneof;
        write_index += 1;
    }
    message.oneofs.items.len = write_index;
    for (message.messages.items) |*nested| normalizeMessageSyntheticProto3OptionalOneofsForCodegen(nested);
}

fn syntheticProto3OptionalFieldIndex(message: *const schema.MessageDescriptor, oneof_name: []const u8) ?usize {
    var found: ?usize = null;
    for (message.fields.items, 0..) |field, index| {
        const field_oneof = field.oneof_name orelse continue;
        if (!std.mem.eql(u8, field_oneof, oneof_name)) continue;
        if (found != null) return null;
        if (!field.proto3_optional) return null;
        found = index;
    }
    return found;
}

fn cloneFieldForCodegen(allocator: std.mem.Allocator, field: *const schema.FieldDescriptor) std.mem.Allocator.Error!schema.FieldDescriptor {
    var out = field.*;
    out.kind = try cloneFieldKindForCodegen(allocator, field.kind);
    return out;
}

fn cloneFieldKindForCodegen(allocator: std.mem.Allocator, kind: schema.FieldKind) std.mem.Allocator.Error!schema.FieldKind {
    return switch (kind) {
        .map => |map_type| blk: {
            const value = try allocator.create(schema.FieldKind);
            errdefer allocator.destroy(value);
            value.* = try cloneFieldKindForCodegen(allocator, map_type.value.*);
            break :blk .{ .map = .{ .key = map_type.key, .value = value } };
        },
        else => kind,
    };
}

fn resolveImportedEnumsForCodegen(allocator: std.mem.Allocator, file: *schema.FileDescriptor, registry: *const registry_mod.Registry) std.mem.Allocator.Error!void {
    for (file.messages.items) |*message| {
        const scope = try codegenQualifiedName(allocator, file.package, message.name);
        try resolveMessageImportedEnumsForCodegen(allocator, file, registry, message, scope);
    }
    const file_scope: ?[]const u8 = if (file.package.len == 0) null else file.package;
    for (file.extensions.items) |*field| try resolveFieldImportedEnumForCodegen(allocator, file, registry, field, file_scope);
}

fn resolveMessageImportedEnumsForCodegen(allocator: std.mem.Allocator, file: *schema.FileDescriptor, registry: *const registry_mod.Registry, message: *schema.MessageDescriptor, scope: []const u8) std.mem.Allocator.Error!void {
    for (message.fields.items) |*field| try resolveFieldImportedEnumForCodegen(allocator, file, registry, field, scope);
    for (message.extensions.items) |*field| try resolveFieldImportedEnumForCodegen(allocator, file, registry, field, scope);
    for (message.messages.items) |*nested| {
        const nested_scope = try codegenQualifiedName(allocator, scope, nested.name);
        try resolveMessageImportedEnumsForCodegen(allocator, file, registry, nested, nested_scope);
    }
}

fn resolveFieldImportedEnumForCodegen(allocator: std.mem.Allocator, file: *schema.FileDescriptor, registry: *const registry_mod.Registry, field: *schema.FieldDescriptor, scope: ?[]const u8) std.mem.Allocator.Error!void {
    try resolveFieldExtendeeForCodegen(allocator, file, registry, field);
    switch (field.kind) {
        .message => |name| {
            if (registry.findEnumVisible(file, name, scope)) |enumeration| {
                try resolveEnumDefaultAndAliasForCodegen(allocator, file, registry, field, enumeration, name);
                field.kind = .{ .enumeration = name };
            }
        },
        .enumeration => |name| {
            if (registry.findEnumVisible(file, name, scope)) |enumeration| {
                try resolveEnumDefaultAndAliasForCodegen(allocator, file, registry, field, enumeration, name);
            }
        },
        .map => |map_type| switch (map_type.value.*) {
            .message => |name| {
                if (registry.findEnumVisible(file, name, scope)) |enumeration| {
                    try ensureImportedEnumAliasForCodegen(allocator, file, registry, enumeration, name);
                    map_type.value.* = .{ .enumeration = name };
                }
            },
            .enumeration => |name| {
                if (registry.findEnumVisible(file, name, scope)) |enumeration| {
                    try ensureImportedEnumAliasForCodegen(allocator, file, registry, enumeration, name);
                }
            },
            else => {},
        },
        else => {},
    }
}

fn resolveEnumDefaultAndAliasForCodegen(allocator: std.mem.Allocator, file: *schema.FileDescriptor, registry: *const registry_mod.Registry, field: *schema.FieldDescriptor, enumeration: *const schema.EnumDescriptor, type_name: []const u8) std.mem.Allocator.Error!void {
    try resolveImportedEnumDefaultForCodegen(field, enumeration);
    try ensureImportedEnumAliasForCodegen(allocator, file, registry, enumeration, type_name);
}

fn ensureImportedEnumAliasForCodegen(allocator: std.mem.Allocator, file: *schema.FileDescriptor, registry: *const registry_mod.Registry, enumeration: *const schema.EnumDescriptor, type_name: []const u8) std.mem.Allocator.Error!void {
    const owner = registry.fileContainingEnum(enumeration) orelse return;
    if (sameFileForCodegen(owner, file)) return;
    try ensureEnumAliasForCodegen(allocator, file, registry, enumeration, type_name);
}

fn codegenQualifiedName(allocator: std.mem.Allocator, prefix: []const u8, name: []const u8) std.mem.Allocator.Error![]const u8 {
    if (prefix.len == 0) return try allocator.dupe(u8, name);
    return try std.fmt.allocPrint(allocator, "{s}.{s}", .{ prefix, name });
}

fn resolveFieldExtendeeForCodegen(allocator: std.mem.Allocator, file: *schema.FileDescriptor, registry: *const registry_mod.Registry, field: *schema.FieldDescriptor) std.mem.Allocator.Error!void {
    const extendee = field.extendee orelse return;
    const message = registry.findMessageVisible(file, extendee, extensionScopeForCodegen(file, field)) orelse return;
    const owner = registry.fileContainingMessage(message) orelse return;
    if (try messageFullNameForCodegen(allocator, owner, message)) |full_name| field.extendee = full_name;
}

fn resolveImportedEnumDefaultForCodegen(field: *schema.FieldDescriptor, enumeration: *const schema.EnumDescriptor) std.mem.Allocator.Error!void {
    const default_name = switch (field.default_value orelse return) {
        .identifier, .string => |text| text,
        else => return,
    };
    if (enumeration.findValue(default_name)) |value| field.default_value = .{ .integer = value.number };
}

fn ensureEnumAliasForCodegen(allocator: std.mem.Allocator, file: *schema.FileDescriptor, registry: *const registry_mod.Registry, enumeration: *const schema.EnumDescriptor, type_name: []const u8) std.mem.Allocator.Error!void {
    const alias = normalizedTypeName(type_name);
    for (file.enums.items) |existing| {
        if (std.mem.eql(u8, existing.name, alias)) return;
    }
    var copy = enumeration.*;
    copy.name = alias;
    if (copy.features == null) {
        if (registry.fileContainingEnum(enumeration)) |owner| copy.features = owner.features;
    }
    try file.enums.append(allocator, copy);
}

fn normalizedTypeName(type_name: []const u8) []const u8 {
    return if (std.mem.startsWith(u8, type_name, ".")) type_name[1..] else type_name;
}

pub fn extensionScopeForCodegen(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor) ?[]const u8 {
    if (field.full_name) |full_name| {
        const normalized = normalizedTypeName(full_name);
        if (std.mem.lastIndexOfScalar(u8, normalized, '.')) |idx| return normalized[0..idx];
        if (std.mem.startsWith(u8, full_name, ".")) return null;
    }
    return if (file.package.len != 0) file.package else null;
}

fn messageFullNameForCodegen(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, target: *const schema.MessageDescriptor) std.mem.Allocator.Error!?[]const u8 {
    for (file.messages.items) |*message| {
        if (message == target) return try joinFullProtoName(allocator, file.package, message.name);
        if (try nestedMessageFullNameForCodegen(allocator, file.package, message.name, message, target)) |full_name| return full_name;
    }
    return null;
}

fn nestedMessageFullNameForCodegen(allocator: std.mem.Allocator, package: []const u8, prefix: []const u8, message: *const schema.MessageDescriptor, target: *const schema.MessageDescriptor) std.mem.Allocator.Error!?[]const u8 {
    for (message.messages.items) |*nested| {
        const path = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ prefix, nested.name });
        if (nested == target) return try joinFullProtoName(allocator, package, path);
        if (try nestedMessageFullNameForCodegen(allocator, package, path, nested, target)) |full_name| return full_name;
    }
    return null;
}

fn joinFullProtoName(allocator: std.mem.Allocator, package: []const u8, relative: []const u8) std.mem.Allocator.Error![]const u8 {
    if (package.len == 0) return try std.fmt.allocPrint(allocator, ".{s}", .{relative});
    return try std.fmt.allocPrint(allocator, ".{s}.{s}", .{ package, relative });
}

pub fn enumFullNameForCodegen(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, target: *const schema.EnumDescriptor) std.mem.Allocator.Error!?[]const u8 {
    for (file.enums.items) |*enumeration| {
        if (enumeration == target) return try joinFullProtoName(allocator, file.package, enumeration.name);
    }
    for (file.messages.items) |*message| {
        if (try nestedEnumFullNameForCodegen(allocator, file.package, message.name, message, target)) |full_name| return full_name;
    }
    return null;
}

fn nestedEnumFullNameForCodegen(allocator: std.mem.Allocator, package: []const u8, prefix: []const u8, message: *const schema.MessageDescriptor, target: *const schema.EnumDescriptor) std.mem.Allocator.Error!?[]const u8 {
    for (message.enums.items) |*enumeration| {
        if (enumeration == target) {
            const path = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ prefix, enumeration.name });
            return try joinFullProtoName(allocator, package, path);
        }
    }
    for (message.messages.items) |*nested| {
        const path = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ prefix, nested.name });
        if (try nestedEnumFullNameForCodegen(allocator, package, path, nested, target)) |full_name| return full_name;
    }
    return null;
}

// Plugin protocol and GeneratedCodeInfo emission live in a submodule; these
// re-exports keep the existing public API stable.
pub const generatePluginResponseFromRequestBytes = plugin_emit.generatePluginResponseFromRequestBytes;
pub const runPluginRequestBytes = plugin_emit.runPluginRequestBytes;
pub const runPluginRequest = plugin_emit.runPluginRequest;
pub const generatePluginResponseFromRequest = plugin_emit.generatePluginResponseFromRequest;
pub const generatePluginResponse = plugin_emit.generatePluginResponse;
pub const generatedResponseFeatureMask = plugin_emit.generatedResponseFeatureMask;


fn writeFileMetadata(ctx: *const CodegenContext, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    try indent(writer, depth);
    try writer.writeAll("pub const proto_package = ");
    try writeZigStringLiteral(file.package, writer);
    try writer.writeAll(";\n");
    try indent(writer, depth);
    try writer.writeAll("pub const proto_syntax = ");
    try writeZigStringLiteral(switch (file.syntax) {
        .proto2 => "proto2",
        .proto3 => "proto3",
        .editions => "editions",
    }, writer);
    try writer.writeAll(";\n");
    if (file.imports.items.len != 0) {
        try indent(writer, depth);
        try writer.writeAll("pub const imports = struct {\n");
        for (file.imports.items) |import| try writeImportDecl(ctx, import, writer, depth + 1);
        try indent(writer, depth);
        try writer.writeAll("};\n");
    }
    if (file.imports.items.len != 0 or ctx.emit_descriptor) {
        try indent(writer, depth);
        try writer.writeAll("const pbz_generated_file = @This();\n");
    }
    try writer.writeAll("\n");
}

fn writeGeneratedFileDescriptor(ctx: *const CodegenContext, file: *const schema.FileDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const descriptor_mod = @import("descriptor.zig");
    // Imported enum references are materialized into `file.enums` with their
    // fully qualified names so generated code can spell them. Those aliases are
    // not part of the original FileDescriptorProto (whose enum names are simple
    // identifiers), so filter them out before serializing the embedded
    // descriptor; otherwise decodeFileDescriptor rejects the dotted names.
    var descriptor_file = file.*;
    var filtered_enums: std.ArrayList(schema.EnumDescriptor) = .empty;
    defer filtered_enums.deinit(ctx.allocator);
    for (file.enums.items) |enumeration| {
        if (std.mem.indexOfScalar(u8, enumeration.name, '.') == null) try filtered_enums.append(ctx.allocator, enumeration);
    }
    descriptor_file.enums = .{ .items = filtered_enums.items, .capacity = filtered_enums.items.len };
    const descriptor_bytes = if (ctx.registry) |registry|
        try descriptor_mod.encodeFileDescriptorProtoWithRegistry(ctx.allocator, &descriptor_file, registry, file.name)
    else
        try descriptor_mod.encodeFileDescriptorProto(ctx.allocator, &descriptor_file, file.name);
    defer ctx.allocator.free(descriptor_bytes);

    try indent(writer, depth);
    try writer.writeAll("/// Serialized google.protobuf.FileDescriptorProto for this generated file.\n");
    try indent(writer, depth);
    try writer.writeAll("/// Use decodeFileDescriptor() to build registry/reflection metadata.\n");
    try indent(writer, depth);
    try writer.writeAll("pub const file_descriptor_proto = [_]u8{");
    for (descriptor_bytes, 0..) |byte, i| {
        if (i % 12 == 0) {
            try writer.writeAll("\n");
            try indent(writer, depth + 1);
        } else {
            try writer.writeAll(" ");
        }
        try writer.print("0x{x:0>2},", .{byte});
    }
    if (descriptor_bytes.len != 0) {
        try writer.writeAll("\n");
        try indent(writer, depth);
    }
    try writer.writeAll("};\n");
    try indent(writer, depth);
    try writer.writeAll("/// Decode the embedded FileDescriptorProto. The caller owns the result and\n");
    try indent(writer, depth);
    try writer.writeAll("/// must call deinit() on it.\n");
    try indent(writer, depth);
    try writer.writeAll("pub fn decodeFileDescriptor(allocator: std.mem.Allocator) !pbz.schema.FileDescriptor {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return pbz.decodeFileDescriptorProto(allocator, &file_descriptor_proto);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");
}

fn writeImportDecl(ctx: *const CodegenContext, import: schema.Import, writer: *std.Io.Writer, depth: usize) Error!void {
    const allocator = ctx.allocator;
    const module_path = try outputNameWithOptions(allocator, import.path, ctx.output_suffix, ctx.strip_proto_ext);
    defer allocator.free(module_path);
    const relative_path = try relativeModulePath(allocator, ctx.file.name, module_path);
    defer allocator.free(relative_path);
    const import_alias = try makeImportAlias(allocator, import.path);
    defer allocator.free(import_alias);
    try indent(writer, depth);
    try writer.writeAll("pub const ");
    try writer.writeAll(import_alias);
    try writer.writeAll(" = @import(");
    try writeZigStringLiteral(relative_path, writer);
    try writer.writeAll(");\n");
    try indent(writer, depth);
    try writer.writeAll("pub const ");
    try writer.writeAll(import_alias);
    try writer.writeAll("_path");
    try writer.writeAll(" = ");
    try writeZigStringLiteral(import.path, writer);
    try writer.writeAll(";\n");
    try indent(writer, depth);
    try writer.writeAll("pub const ");
    try writer.writeAll(import_alias);
    try writer.writeAll("_kind");
    try writer.writeAll(" = ");
    try writeZigStringLiteral(@tagName(import.kind), writer);
    try writer.writeAll(";\n");
}

/// Zig resolves `@import("...")` relative to the importing file, so generated
/// files in subdirectories need `../` prefixes to reach modules that live
/// elsewhere in the same generation root.
fn relativeModulePath(allocator: std.mem.Allocator, from_file: []const u8, to_module: []const u8) Error![]u8 {
    const from_dir = std.fs.path.dirname(from_file) orelse "";
    if (from_dir.len == 0) return allocator.dupe(u8, to_module);
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    var components = std.mem.tokenizeScalar(u8, from_dir, '/');
    while (components.next()) |_| try out.writer.writeAll("../");
    try out.writer.writeAll(to_module);
    return out.toOwnedSlice();
}

pub fn makeImportAlias(allocator: std.mem.Allocator, path: []const u8) Error![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();

    const source = if (path.len == 0) "import" else path;
    for (source) |c| {
        if (isBareIdentChar(c, out.written().len == 0)) {
            try out.writer.writeByte(c);
        } else if (out.written().len == 0 or out.written()[out.written().len - 1] != '_') {
            try out.writer.writeByte('_');
        }
    }

    if (out.written().len == 0 or std.mem.eql(u8, out.written(), "_") or !canWriteBareIdent(out.written())) {
        try out.writer.writeAll("_pb");
    }
    return try out.toOwnedSlice();
}

fn writeMessage(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    try indent(writer, depth);
    try writer.writeAll("pub const ");
    try writeQuotedIdent(message.name, writer);
    try writer.writeAll(" = struct {\n");
    for (message.fields.items) |*field| {
        try indent(writer, depth + 1);
        try writer.writeAll("pub const ");
        try writeQuotedFieldNumber(field.name, writer);
        try writer.print(" = {d};\n", .{field.number});
    }
    if (message.fields.items.len != 0) try writer.writeAll("\n");
    for (message.fields.items) |*field| try writeFieldMetadataDecl(ctx, field, writer, depth + 1);
    if (message.fields.items.len != 0) try writer.writeAll("\n");
    try writeMessageDescriptorLookup(ctx, message, writer, depth + 1);
    try writeMessageDynamicBridge(ctx, writer, depth + 1);
    try writeMessageConformantParsers(ctx, writer, depth + 1);
    for (message.fields.items) |*field| {
        if (field.kind == .map) {
            try writeMapEntryType(ctx, field, writer, depth + 1);
            try writeMapEntryHelpers(ctx, field, writer, depth + 1);
        }
    }
    for (message.oneofs.items) |oneof| try writeOneofUnion(ctx, message, oneof, writer, depth + 1);
    for (message.fields.items) |*field| {
        if (field.oneof_name == null) try writeFieldDecl(ctx, field, writer, depth + 1);
    }
    for (message.oneofs.items) |oneof| try writeOneofField(oneof, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("_json_arena: ?*std.heap.ArenaAllocator = null,\n");
    try indent(writer, depth + 1);
    try writer.writeAll("_unknown_fields: []const []const u8 = &.{},\n");
    if (message.fields.items.len != 0) try writer.writeAll("\n");
    try writeInit(writer, depth + 1);
    try writer.writeAll("\n");
    try writeDeinit(ctx, message, writer, depth + 1);
    try writer.writeAll("\n");
    try writeClear(writer, depth + 1);
    try writer.writeAll("\n");
    try writeCloneOwned(ctx, message, writer, depth + 1);
    try writer.writeAll("\n");
    try writeAdoptOwned(ctx, message, writer, depth + 1);
    try writer.writeAll("\n");
    try writeOwnedAllocator(writer, depth + 1);
    try writer.writeAll("\n");
    try writeUnknownFieldMethods(writer, depth + 1);
    try writer.writeAll("\n");
    try writeOneofDeinitHelpers(ctx, message, writer, depth + 1);
    try writer.writeAll("\n");
    try writeBorrowedViewMethods(file, message, writer, depth + 1);
    try writer.writeAll("\n");
    try writeMessageExtensionAccessors(ctx, message, writer, depth + 1);
    try writer.writeAll("\n");
    try writeMergeFrom(ctx, message, writer, depth + 1);
    try writer.writeAll("\n");
    try writeEncode(ctx, message, writer, depth + 1);
    try writer.writeAll("\n");
    try writeEncodeDeterministic(ctx, message, writer, depth + 1);
    try writer.writeAll("\n");
    try writeEncodeInitialized(writer, depth + 1);
    try writer.writeAll("\n");
    try writeDecode(ctx, message, writer, depth + 1);
    try writer.writeAll("\n");
    try writeDecodeReuse(ctx, message, writer, depth + 1);
    try writer.writeAll("\n");
    try writeDecodeOwnedReuse(ctx, message, writer, depth + 1);
    try writer.writeAll("\n");
    if (messageCanDecodeKnownReuse(ctx.file, message)) {
        try writeDecodeKnownReuse(ctx, message, writer, depth + 1);
        try writer.writeAll("\n");
    }
    try writeDecodeInitialized(writer, depth + 1);
    try writer.writeAll("\n");
    try writeMissingRequiredFieldName(message, writer, depth + 1);
    try writer.writeAll("\n");
    try writeMissingRequiredFieldPath(ctx, message, writer, depth + 1);
    try writer.writeAll("\n");
    try writeValidateRequired(ctx, message, writer, depth + 1);
    try writer.writeAll("\n");
    if (ctx.emit_json) {
        try json_emit.writeJsonMethods(ctx, message, writer, depth + 1);
        try writer.writeAll("\n");
    }
    if (ctx.emit_text) {
        try text_emit.writeTextMethods(ctx, message, writer, depth + 1);
        try writer.writeAll("\n");
    }
    for (message.enums.items) |*enumeration| try enum_emit.writeEnum(ctx, enumeration, writer, depth + 1);
    for (message.messages.items) |*nested| try writeMessage(ctx, nested, writer, depth + 1);
    try indent(writer, depth);
    try writer.writeAll("};\n\n");
}

fn writeOneofUnion(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, oneof: schema.OneofDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub const ");
    try writeOneofTypeName(oneof.name, writer);
    try writer.writeAll(" = union(enum) {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("none,\n");
    for (message.fields.items) |*field| {
        if (field.oneof_name) |name| {
            if (std.mem.eql(u8, name, oneof.name)) {
                try indent(writer, depth + 1);
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(": ");
                if (typedOneofMessageFieldWithContext(ctx, field)) |type_name| {
                    try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
                } else {
                    try writeFieldType(field.*, writer);
                }
                try writer.writeAll(",\n");
            }
        }
    }
    try indent(writer, depth);
    try writer.writeAll("};\n\n");
}

fn writeOneofField(oneof: schema.OneofDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writeQuotedIdent(oneof.name, writer);
    try writer.writeAll(": @This().");
    try writeOneofTypeName(oneof.name, writer);
    try writer.writeAll(" = .none,\n");
}

fn writeOneofTypeName(name: []const u8, writer: *std.Io.Writer) Error!void {
    try writeQuotedIdentWithSuffix(name, "Oneof", writer);
}

fn writeOneofDeinitHelpers(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    for (message.oneofs.items) |oneof| {
        const has_typed_message = oneofHasTypedMessageWithContext(ctx, message, oneof.name);
        try indent(writer, depth);
        try writer.writeAll("fn ");
        try writeQuotedIdentWithPrefix(oneof.name, "_pbzDeinitOneof_", writer);
        try writer.writeAll("(self: *@This(), allocator: std.mem.Allocator) void {\n");
        if (!has_typed_message) {
            try indent(writer, depth + 1);
            try writer.writeAll("_ = allocator;\n");
        } else {
            try indent(writer, depth + 1);
            try writer.writeAll("switch (self.");
            try writeQuotedIdent(oneof.name, writer);
            try writer.writeAll(") {\n");
            for (message.fields.items) |*field| {
                const field_oneof = field.oneof_name orelse continue;
                if (!std.mem.eql(u8, field_oneof, oneof.name)) continue;
                if (typedOneofMessageFieldWithContext(ctx, field) == null) continue;
                try indent(writer, depth + 2);
                try writer.writeAll(".");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(" => |*value| value.deinit(allocator),\n");
            }
            try indent(writer, depth + 2);
            try writer.writeAll("else => {},\n");
            try indent(writer, depth + 1);
            try writer.writeAll("}\n");
        }
        try indent(writer, depth + 1);
        try writer.writeAll("self.");
        try writeQuotedIdent(oneof.name, writer);
        try writer.writeAll(" = .none;\n");
        try indent(writer, depth);
        try writer.writeAll("}\n\n");
    }
}

fn oneofHasTypedMessageWithContext(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, oneof_name: []const u8) bool {
    for (message.fields.items) |*field| {
        const name = field.oneof_name orelse continue;
        if (std.mem.eql(u8, name, oneof_name) and typedOneofMessageFieldWithContext(ctx, field) != null) return true;
    }
    return false;
}

pub fn writeOneofDeinitCall(oneof_name: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("self.");
    try writeQuotedIdentWithPrefix(oneof_name, "_pbzDeinitOneof_", writer);
    try writer.writeAll("(allocator);");
}

fn writeFieldMetadataDecl(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    try indent(writer, depth);
    try writer.writeAll("pub const ");
    try writeQuotedIdentWithSuffix(field.name, "_field", writer);
    try writer.writeAll(" = struct {\n");
    try indent(writer, depth + 1);
    try writer.print("pub const number = {d};\n", .{field.number});
    try indent(writer, depth + 1);
    try writer.writeAll("pub const name = ");
    try writeZigStringLiteral(field.name, writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const json_name = ");
    if (field.json_name) |json_name| {
        try writeZigStringLiteral(json_name, writer);
    } else {
        try writeZigLowerCamelStringLiteral(field.name, writer);
    }
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const cardinality = ");
    try writeZigStringLiteral(@tagName(field.cardinality), writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const kind = ");
    try writeZigStringLiteral(fieldKindName(field.kind), writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const type_name = ");
    try writeZigStringLiteral(fieldTypeName(field.kind), writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const zig_type = ");
    if (typedSingularMessageFieldWithContext(ctx, field)) |type_name| {
        var type_buf: std.Io.Writer.Allocating = .init(ctx.allocator);
        defer type_buf.deinit();
        try type_buf.writer.writeByte('?');
        try writeMessageTypeReferenceWithContext(ctx, type_name, &type_buf.writer);
        try writeZigStringLiteral(type_buf.written(), writer);
    } else if (typedRepeatedMessageFieldWithContext(ctx, field)) |type_name| {
        var type_buf: std.Io.Writer.Allocating = .init(ctx.allocator);
        defer type_buf.deinit();
        try type_buf.writer.writeAll("[]const ");
        try writeMessageTypeReferenceWithContext(ctx, type_name, &type_buf.writer);
        try writeZigStringLiteral(type_buf.written(), writer);
    } else if (typedOneofMessageFieldWithContext(ctx, field)) |type_name| {
        var type_buf: std.Io.Writer.Allocating = .init(ctx.allocator);
        defer type_buf.deinit();
        try writeMessageTypeReferenceWithContext(ctx, type_name, &type_buf.writer);
        try writeZigStringLiteral(type_buf.written(), writer);
    } else {
        var type_buf: std.Io.Writer.Allocating = .init(ctx.allocator);
        defer type_buf.deinit();
        try writeFieldType(field.*, &type_buf.writer);
        try writeZigStringLiteral(type_buf.written(), writer);
    }
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const has_type_ref = ");
    try writer.writeAll(if (canReferenceMessageWithContext(ctx, field.kind)) "true" else "false");
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const type_ref = ");
    try writeMessageTypeReferenceOrVoid(ctx, field.kind, writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const has_enum_ref = ");
    try writer.writeAll(if (canReferenceEnumWithContext(ctx, field.kind)) "true" else "false");
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const enum_ref = ");
    try writeEnumTypeReferenceOrVoid(ctx, field.kind, writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const has_presence = ");
    try writer.writeAll(if (hasPresence(file, field.*)) "true" else "false");
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const default_value = ");
    try writeOptionValueTextLiteral(field.default_value, writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const is_packed = ");
    try writer.writeAll(if (field.resolvedPacked(file)) "true" else "false");
    try writer.writeAll(";\n");
    if (field.kind == .map) {
        try indent(writer, depth + 1);
        try writer.writeAll("pub const map_key = ");
        try writeZigStringLiteral(@tagName(field.kind.map.key), writer);
        try writer.writeAll(";\n");
        try indent(writer, depth + 1);
        try writer.writeAll("pub const map_value_kind = ");
        try writeZigStringLiteral(fieldKindName(field.kind.map.value.*), writer);
        try writer.writeAll(";\n");
        try indent(writer, depth + 1);
        try writer.writeAll("pub const map_value_type_name = ");
        try writeZigStringLiteral(fieldTypeName(field.kind.map.value.*), writer);
        try writer.writeAll(";\n");
        try indent(writer, depth + 1);
        try writer.writeAll("pub const map_value_has_type_ref = ");
        try writer.writeAll(if (canReferenceMessageWithContext(ctx, field.kind.map.value.*)) "true" else "false");
        try writer.writeAll(";\n");
        try indent(writer, depth + 1);
        try writer.writeAll("pub const map_value_type_ref = ");
        try writeMessageTypeReferenceOrVoid(ctx, field.kind.map.value.*, writer);
        try writer.writeAll(";\n");
        try indent(writer, depth + 1);
        try writer.writeAll("pub const map_value_has_enum_ref = ");
        try writer.writeAll(if (canReferenceEnumWithContext(ctx, field.kind.map.value.*)) "true" else "false");
        try writer.writeAll(";\n");
        try indent(writer, depth + 1);
        try writer.writeAll("pub const map_value_enum_ref = ");
        try writeEnumTypeReferenceOrVoid(ctx, field.kind.map.value.*, writer);
        try writer.writeAll(";\n");
    }
    try indent(writer, depth);
    try writer.writeAll("};\n");
}

fn fieldKindName(kind: schema.FieldKind) []const u8 {
    return switch (kind) {
        .scalar => |scalar| @tagName(scalar),
        .message => "message",
        .enumeration => "enum",
        .group => "group",
        .map => "map",
    };
}

fn fieldTypeName(kind: schema.FieldKind) []const u8 {
    return switch (kind) {
        .scalar => |scalar| @tagName(scalar),
        .message => |name| name,
        .enumeration => |name| name,
        .group => |name| name,
        .map => "",
    };
}

fn writeEncodeOneof(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, oneof: schema.OneofDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("switch (self.");
    try writeQuotedIdent(oneof.name, writer);
    try writer.writeAll(") {\n");
    try indent(writer, depth + 1);
    try writer.writeAll(".none => {},\n");
    for (message.fields.items) |*field| {
        if (field.oneof_name) |name| {
            if (std.mem.eql(u8, name, oneof.name)) {
                try indent(writer, depth + 1);
                try writer.writeAll(".");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(" => |value| ");
                try writeOneofValueEncode(ctx, field, "value", writer);
                try writer.writeAll(",\n");
            }
        }
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeEncodeOneofAssumeCapacity(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, oneof: schema.OneofDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("switch (self.");
    try writeQuotedIdent(oneof.name, writer);
    try writer.writeAll(") {\n");
    try indent(writer, depth + 1);
    try writer.writeAll(".none => {},\n");
    for (message.fields.items) |*field| {
        if (field.oneof_name) |name| {
            if (std.mem.eql(u8, name, oneof.name)) {
                try indent(writer, depth + 1);
                try writer.writeAll(".");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(" => |value| ");
                try writeOneofValueEncodeAssumeCapacity(ctx, field, "value", writer);
                try writer.writeAll(",\n");
            }
        }
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeFieldDecl(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    try indent(writer, depth);
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(": ");
    if (typedSingularMessageFieldWithContext(ctx, field)) |type_name| {
        try writeTypedMessageTypeWithContext(ctx, type_name, writer);
        try writer.writeAll(" = null,\n");
        return;
    }
    if (typedRepeatedMessageFieldWithContext(ctx, field)) |type_name| {
        try writeTypedRepeatedMessageTypeWithContext(ctx, type_name, writer);
        try writer.writeAll(" = &.{},\n");
        return;
    }
    try writeFieldType(field.*, writer);
    try writer.writeAll(" = ");
    try writeFieldDefault(file, field.*, writer);
    try writer.writeAll(",\n");
    if (hasPresence(file, field.*)) {
        try indent(writer, depth);
        try writePresenceIdent(field.name, writer);
        try writer.writeAll(": bool = false,\n");
    }
}

fn writeMapEntryType(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    const map_type = switch (field.kind) {
        .map => |map| map,
        else => return,
    };
    try indent(writer, depth);
    try writer.writeAll("pub const ");
    try writeQuotedIdentWithSuffix(field.name, "Map", writer);
    try writer.writeAll(" = ");
    try writeMapStorageType(ctx, field, writer);
    try writer.writeAll(";\n\n");
    try indent(writer, depth);
    try writer.writeAll("pub const ");
    try writeQuotedIdentWithSuffix(field.name, "Entry", writer);
    try writer.writeAll(" = struct {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("key: ");
    try writer.writeAll(scalarZigType(map_type.key));
    try writer.writeAll(" = ");
    try writeScalarDefault(map_type.key, null, writer);
    try writer.writeAll(",\n");
    try indent(writer, depth + 1);
    try writer.writeAll("value: ");
    if (typedMapMessageValueWithContext(ctx, field)) |type_name| {
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    } else {
        try writeFieldKindType(map_type.value.*, writer);
    }
    try writer.writeAll(" = ");
    if (typedMapMessageValueWithContext(ctx, field)) |_| {
        try writer.writeAll(".{}");
    } else {
        try writeFieldKindDefault(file, map_type.value.*, null, writer);
    }
    try writer.writeAll(",\n");
    try indent(writer, depth);
    try writer.writeAll("};\n\n");
}

fn writeMapEntryHelpers(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const map_type = switch (field.kind) {
        .map => |map| map,
        else => return,
    };
    try indent(writer, depth);
    try writer.writeAll("fn ");
    try writeQuotedIdentWithPrefix(field.name, "appendOrReplaceMapEntry_", writer);
    try writer.writeAll("(allocator: std.mem.Allocator, list: *std.ArrayList(");
    try writeQuotedIdentWithSuffix(field.name, "Entry", writer);
    try writer.writeAll("), entry: ");
    try writeQuotedIdentWithSuffix(field.name, "Entry", writer);
    try writer.writeAll(") !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("for (list.items) |*existing| {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("if (");
    try writeMapKeyEqualExpr(map_type.key, "existing.key", "entry.key", writer);
    try writer.writeAll(") { ");
    if (typedMapMessageValueWithContext(ctx, field)) |_| {
        try writer.writeAll("existing.value.deinit(allocator); ");
    }
    try writer.writeAll("existing.* = entry; return; }\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try list.append(allocator, entry);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("fn ");
    try writeQuotedIdentWithPrefix(field.name, "putMapEntry_", writer);
    try writer.writeAll("(allocator: std.mem.Allocator, map: *");
    try writeQuotedIdentWithSuffix(field.name, "Map", writer);
    try writer.writeAll(", entry: ");
    try writeQuotedIdentWithSuffix(field.name, "Entry", writer);
    try writer.writeAll(") !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const result = try map.getOrPut(allocator, entry.key);\n");
    if (typedMapMessageValueWithContext(ctx, field)) |_| {
        try indent(writer, depth + 1);
        try writer.writeAll("if (result.found_existing) result.value_ptr.deinit(allocator);\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("result.value_ptr.* = entry.value;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("fn ");
    try writeQuotedIdentWithPrefix(field.name, "deinitMap_", writer);
    try writer.writeAll("(allocator: std.mem.Allocator, map: *");
    try writeQuotedIdentWithSuffix(field.name, "Map", writer);
    try writer.writeAll(") void {\n");
    if (typedMapMessageValueWithContext(ctx, field)) |_| {
        try indent(writer, depth + 1);
        try writer.writeAll("var it = map.iterator();\n");
        try indent(writer, depth + 1);
        try writer.writeAll("while (it.next()) |entry| entry.value_ptr.deinit(allocator);\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("map.deinit(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("map.* = .empty;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");
}

fn writeMapKeyEqualExpr(scalar: schema.ScalarType, lhs: []const u8, rhs: []const u8, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .string => try writer.print("std.mem.eql(u8, {s}, {s})", .{ lhs, rhs }),
        else => try writer.print("{s} == {s}", .{ lhs, rhs }),
    }
}

fn writeInit(writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn init() @This() {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return .{};\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeEncode(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try writeEncodedSize(ctx, message, writer, depth);
    try writer.writeAll("\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn writeTo(self: @This(), w: *pbz.Writer) anyerror!void {\n");
    for (message.fields.items) |*field| {
        if (field.oneof_name == null) try writeEncodeField(ctx, field, writer, depth + 1);
    }
    for (message.oneofs.items) |oneof| try writeEncodeOneof(ctx, message, oneof, writer, depth + 1);
    try writeEncodeUnknownFields(writer, depth + 1);
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn writeToAssumeCapacity(self: @This(), w: *pbz.Writer) anyerror!void {\n");
    for (message.fields.items) |*field| {
        if (field.oneof_name == null) try writeEncodeFieldAssumeCapacity(ctx, field, writer, depth + 1);
    }
    for (message.oneofs.items) |oneof| try writeEncodeOneofAssumeCapacity(ctx, message, oneof, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("for (self._unknown_fields) |raw| w.appendSliceAssumeCapacity(raw);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn encode(self: @This(), allocator: std.mem.Allocator) ![]u8 {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var w = pbz.Writer.init(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer w.deinit();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try w.bytes.ensureTotalCapacity(allocator, self.encodedSize());\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.writeToAssumeCapacity(&w);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try w.toOwnedSlice();\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try writer.writeAll("\n");
    try indent(writer, depth);
    try writer.writeAll("pub fn encodeInto(self: @This(), buffer: []u8) ![]u8 {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const size = self.encodedSize();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (buffer.len < size) return error.NoSpaceLeft;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var w = pbz.Writer.initBuffer(std.heap.page_allocator, buffer[0..size]);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.writeToAssumeCapacity(&w);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return buffer[0..w.slice().len];\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try writer.writeAll("\n");
    try indent(writer, depth);
    try writer.writeAll("pub fn encodeIntoAssumeCapacity(self: @This(), buffer: []u8) ![]u8 {\n");
    if (messageCanFastDirectEncode(ctx, message)) {
        try writeFastDirectEncodeIntoAssumeCapacity(ctx, message, true, writer, depth + 1);
    } else {
        try indent(writer, depth + 1);
        try writer.writeAll("var w = pbz.Writer.initBuffer(std.heap.page_allocator, buffer);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try self.writeToAssumeCapacity(&w);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return buffer[0..w.slice().len];\n");
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try writer.writeAll("\n");
    try indent(writer, depth);
    try writer.writeAll("/// Like encodeIntoAssumeCapacity, but skips UTF-8 validation. The caller\n");
    try indent(writer, depth);
    try writer.writeAll("/// must guarantee that all string fields contain valid UTF-8.\n");
    try indent(writer, depth);
    try writer.writeAll("pub fn encodeIntoAssumeCapacityTrustedUtf8(self: @This(), buffer: []u8) ![]u8 {\n");
    if (messageCanFastDirectEncode(ctx, message)) {
        try writeFastDirectEncodeIntoAssumeCapacity(ctx, message, false, writer, depth + 1);
    } else {
        try indent(writer, depth + 1);
        try writer.writeAll("return try self.encodeIntoAssumeCapacity(buffer);\n");
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn messageCanFastDirectEncode(ctx: *const CodegenContext, message: *const schema.MessageDescriptor) bool {
    const file = ctx.file;
    var has_packed_repeated = false;
    var has_length_delimited_scalar = false;
    var has_typed_message = false;
    const has_oneof = message.oneofs.items.len != 0;
    var has_presence = false;
    var has_map = false;
    for (message.fields.items) |*field| {
        if (field.oneof_name == null and hasPresence(file, field.*)) has_presence = true;
        switch (field.kind) {
            .scalar => |scalar| switch (scalar) {
                .string, .bytes => has_length_delimited_scalar = true,
                else => {
                    if (field.cardinality == .repeated and field.resolvedPacked(file)) has_packed_repeated = true;
                },
            },
            .enumeration => {
                if (field.cardinality == .repeated and field.resolvedPacked(file)) has_packed_repeated = true;
            },
            .message, .group => {
                if (field.oneof_name != null) {
                    if (typedOneofMessageFieldWithContext(ctx, field) == null) return false;
                } else if (field.cardinality == .repeated) {
                    if (typedRepeatedMessageFieldWithContext(ctx, field) == null) return false;
                } else {
                    if (typedSingularMessageFieldWithContext(ctx, field) == null) return false;
                }
                has_typed_message = true;
            },
            .map => {
                if (!mapCanFastDirectEncode(ctx, field)) return false;
                has_map = true;
            },
        }
    }
    return has_packed_repeated or has_length_delimited_scalar or has_typed_message or has_oneof or has_presence or has_map or message.fields.items.len >= 8;
}

fn mapCanFastDirectEncode(ctx: *const CodegenContext, field: *const schema.FieldDescriptor) bool {
    _ = ctx;
    const map_type = switch (field.kind) {
        .map => |map| map,
        else => return false,
    };
    _ = map_type.key;
    return switch (map_type.value.*) {
        .scalar, .enumeration => true,
        .message => true,
        .group, .map => false,
    };
}

fn writeFastDirectEncodeIntoAssumeCapacity(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, validate_utf8: bool, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    try indent(writer, depth);
    try writer.writeAll("var index: usize = 0;\n");
    for (message.fields.items) |*field| {
        if (field.oneof_name != null) continue;
        if (field.kind == .map) {
            try writeFastDirectMapEncode(ctx, field, validate_utf8, writer, depth);
            continue;
        }
        if (field.cardinality == .repeated) {
            if (field.kind == .scalar and field.resolvedPacked(file)) {
                try writeFastDirectPackedScalarEncode(field, field.kind.scalar, writer, depth);
            } else if (field.kind == .enumeration and field.resolvedPacked(file)) {
                try writeFastDirectPackedEnumEncode(field, writer, depth);
            } else if (field.kind == .scalar) {
                try writeFastDirectRepeatedScalarEncode(ctx.file, field, field.kind.scalar, validate_utf8, writer, depth);
            } else if (field.kind == .enumeration) {
                try writeFastDirectRepeatedEnumEncode(field, writer, depth);
            } else if (field.kind == .message or field.kind == .group) {
                try writeFastDirectRepeatedMessageEncode(ctx, field, validate_utf8, writer, depth);
            }
            continue;
        }
        switch (field.kind) {
            .scalar => |scalar| try writeFastDirectScalarEncode(ctx.file, field, scalar, validate_utf8, writer, depth),
            .enumeration => try writeFastDirectEnumEncode(ctx.file, field, writer, depth),
            .message, .group => try writeFastDirectSingularMessageEncode(ctx, field, validate_utf8, writer, depth),
            .map => unreachable,
        }
    }
    for (message.oneofs.items) |oneof| try writeFastDirectOneofEncode(ctx, message, oneof, validate_utf8, writer, depth);
    try indent(writer, depth);
    try writer.writeAll("for (self._unknown_fields) |raw| { @memcpy(buffer[index..][0..raw.len], raw); index += raw.len; }\n");
    try indent(writer, depth);
    try writer.writeAll("return buffer[0..index];\n");
}

fn writeFastDirectScalarEncode(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, scalar: schema.ScalarType, validate_utf8: bool, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    if (hasPresence(file, field.*)) {
        try writer.writeAll("if (self.");
        try writePresenceIdent(field.name, writer);
        try writer.writeAll(") ");
    } else {
        try writeScalarSkipCondition("self.", field.name, scalar, writer);
    }
    try writer.writeAll("{ ");
    if (scalar == .string or scalar == .bytes) {
        try writeFastDirectLengthDelimitedValidation(file, field, validate_utf8, "self.", field.name, writer);
        try writeFastDirectTag(field.number, .{ .scalar = scalar }, writer);
        try writer.writeAll(" ");
        try writeFastDirectLengthDelimitedPayload("self.", field.name, writer);
        try writer.writeAll(" }\n");
        return;
    }
    try writeFastDirectTag(field.number, .{ .scalar = scalar }, writer);
    try writer.writeAll(" ");
    try writeFastDirectScalarPayload("self.", field.name, scalar, writer);
    try writer.writeAll(" }\n");
}

fn writeFastDirectEnumEncode(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("if (");
    if (hasPresence(file, field.*)) {
        try writer.writeAll("self.");
        try writePresenceIdent(field.name, writer);
        try writer.writeAll(") ");
    } else {
        try writer.writeAll("self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" != 0) ");
    }
    try writer.writeAll("{ ");
    try writeFastDirectTag(field.number, .{ .enumeration = "" }, writer);
    try writer.writeAll(" if (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" > 0 and self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" < 0x80) { buffer[index] = @intCast(self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll("); index += 1; } else pbz.wire.writeVarintToSlice(buffer, &index, @as(u64, @bitCast(@as(i64, self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(")))); }\n");
}

fn writeFastDirectRepeatedScalarEncode(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, scalar: schema.ScalarType, validate_utf8: bool, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("for (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(") |item| { ");
    if (scalar == .string or scalar == .bytes) {
        try writeFastDirectLengthDelimitedValidation(file, field, validate_utf8, "", "item", writer);
        try writeFastDirectTag(field.number, .{ .scalar = scalar }, writer);
        try writer.writeAll(" ");
        try writeFastDirectLengthDelimitedPayload("", "item", writer);
        try writer.writeAll(" }\n");
        return;
    }
    try writeFastDirectTag(field.number, .{ .scalar = scalar }, writer);
    try writer.writeAll(" ");
    try writeFastDirectScalarPayload("item", "", scalar, writer);
    try writer.writeAll(" }\n");
}

fn writeFastDirectSingularMessageEncode(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, validate_utf8: bool, writer: *std.Io.Writer, depth: usize) Error!void {
    if (typedSingularMessageFieldWithContext(ctx, field) == null) return;
    try indent(writer, depth);
    try writer.writeAll("if (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(") |value| { ");
    try writeFastDirectMessagePayload(field, "value", validate_utf8, writer);
    try writer.writeAll(" }\n");
}

fn writeFastDirectRepeatedMessageEncode(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, validate_utf8: bool, writer: *std.Io.Writer, depth: usize) Error!void {
    if (typedRepeatedMessageFieldWithContext(ctx, field) == null) return;
    try indent(writer, depth);
    try writer.writeAll("for (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(") |item| { ");
    try writeFastDirectMessagePayload(field, "item", validate_utf8, writer);
    try writer.writeAll(" }\n");
}

fn writeFastDirectMapEncode(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, validate_utf8: bool, writer: *std.Io.Writer, depth: usize) Error!void {
    const map_type = switch (field.kind) {
        .map => |map| map,
        else => return,
    };
    try indent(writer, depth);
    try writer.writeAll("{ var map_it = self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".iterator(); while (map_it.next()) |map_entry| {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const key = map_entry.key_ptr.*; const value = map_entry.value_ptr.*;\n");
    if (validate_utf8) {
        try writeFastDirectMapUtf8Validation(ctx.file, field, "key", .{ .scalar = map_type.key }, writer, depth + 1);
        try writeFastDirectMapUtf8Validation(ctx.file, field, "value", map_type.value.*, writer, depth + 1);
    }
    try indent(writer, depth + 1);
    try writer.writeAll("const entry_len = ");
    try writeMapEntryFieldSizeExpr(1, .{ .scalar = map_type.key }, "key", writer);
    try writer.writeAll(" + ");
    try writeMapEntryValueFieldSizeExpr(ctx, field, "value", writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writeFastDirectTag(field.number, .{ .scalar = .bytes }, writer);
    try writer.writeAll("\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pbz.wire.writeVarintToSlice(buffer, &index, entry_len);\n");
    try indent(writer, depth + 1);
    try writeFastDirectMapScalarPayload(1, map_type.key, "key", writer);
    try writer.writeAll("\n");
    try writeFastDirectMapValuePayload(ctx, field, map_type, validate_utf8, writer, depth + 1);
    try indent(writer, depth);
    try writer.writeAll("} }\n");
}

fn writeFastDirectMapUtf8Validation(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, value_expr: []const u8, kind: schema.FieldKind, writer: *std.Io.Writer, depth: usize) Error!void {
    if (kind == .scalar and kind.scalar == .string and fieldUtf8Validation(file, field) == .verify) {
        try indent(writer, depth);
        try writer.print("if (!pbz.validateUtf8({s})) return error.InvalidUtf8;\n", .{value_expr});
    }
}

fn writeFastDirectMapValuePayload(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, map_type: schema.MapType, validate_utf8: bool, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    switch (map_type.value.*) {
        .scalar => |scalar| try writeFastDirectMapScalarPayload(2, scalar, "value", writer),
        .enumeration => {
            try writeFastDirectTag(2, .{ .enumeration = "" }, writer);
            try writer.writeAll(" pbz.wire.writeVarintToSlice(buffer, &index, @as(u64, @bitCast(@as(i64, value))));");
        },
        .message => {
            if (typedMapMessageValueWithContext(ctx, field)) |_| {
                try writer.writeAll("const value_len = value.encodedSize(); ");
                try writeFastDirectTag(2, .{ .scalar = .bytes }, writer);
                try writer.writeAll(" pbz.wire.writeVarintToSlice(buffer, &index, value_len); _ = try value.");
                try writer.writeAll(if (validate_utf8) "encodeIntoAssumeCapacity" else "encodeIntoAssumeCapacityTrustedUtf8");
                try writer.writeAll("(buffer[index..][0..value_len]); index += value_len;");
            } else {
                try writeFastDirectTag(2, .{ .scalar = .bytes }, writer);
                try writer.writeAll(" ");
                try writeFastDirectLengthDelimitedPayload("", "value", writer);
            }
        },
        .group, .map => try writer.writeAll("@compileError(\"unsupported map value\")"),
    }
    try writer.writeAll("\n");
}

fn writeFastDirectMapScalarPayload(number: u29, scalar: schema.ScalarType, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    try writeFastDirectTag(number, .{ .scalar = scalar }, writer);
    try writer.writeByte(' ');
    if (scalar == .string or scalar == .bytes) {
        try writeFastDirectLengthDelimitedPayload("", value_expr, writer);
    } else {
        try writeFastDirectScalarPayload(value_expr, "", scalar, writer);
    }
}

fn writeFastDirectOneofEncode(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, oneof: schema.OneofDescriptor, validate_utf8: bool, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("switch (self.");
    try writeQuotedIdent(oneof.name, writer);
    try writer.writeAll(") {\n");
    try indent(writer, depth + 1);
    try writer.writeAll(".none => {},\n");
    for (message.fields.items) |*field| {
        const oneof_name = field.oneof_name orelse continue;
        if (!std.mem.eql(u8, oneof_name, oneof.name)) continue;
        try indent(writer, depth + 1);
        try writer.writeAll(".");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" => |value| { ");
        switch (field.kind) {
            .scalar => |scalar| {
                if (scalar == .string or scalar == .bytes) {
                    try writeFastDirectLengthDelimitedValidation(ctx.file, field, validate_utf8, "", "value", writer);
                    try writeFastDirectTag(field.number, .{ .scalar = scalar }, writer);
                    try writer.writeAll(" ");
                    try writeFastDirectLengthDelimitedPayload("", "value", writer);
                } else {
                    try writeFastDirectTag(field.number, .{ .scalar = scalar }, writer);
                    try writer.writeAll(" ");
                    try writeFastDirectScalarPayload("value", "", scalar, writer);
                }
            },
            .enumeration => {
                try writeFastDirectTag(field.number, .{ .enumeration = "" }, writer);
                try writer.writeAll(" pbz.wire.writeVarintToSlice(buffer, &index, @as(u64, @bitCast(@as(i64, value))));");
            },
            .message, .group => try writeFastDirectMessagePayload(field, "value", validate_utf8, writer),
            .map => try writer.writeAll("@compileError(\"unsupported oneof map\")"),
        }
        try writer.writeAll(" },\n");
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeFastDirectMessagePayload(field: *const schema.FieldDescriptor, value_expr: []const u8, validate_utf8: bool, writer: *std.Io.Writer) Error!void {
    if (field.kind == .group) {
        try writeFastDirectRawTag(field.number, .start_group, writer);
        try writer.writeAll(" _ = try ");
        try writer.writeAll(value_expr);
        try writer.writeAll(if (validate_utf8) ".encodeIntoAssumeCapacity(buffer[index..]);" else ".encodeIntoAssumeCapacityTrustedUtf8(buffer[index..]);");
        try writer.writeAll(" index += ");
        try writer.writeAll(value_expr);
        try writer.writeAll(".encodedSize(); ");
        try writeFastDirectRawTag(field.number, .end_group, writer);
        return;
    }
    try writer.writeAll("const payload_len = ");
    try writer.writeAll(value_expr);
    try writer.writeAll(".encodedSize(); ");
    try writeFastDirectTag(field.number, .{ .scalar = .bytes }, writer);
    try writer.writeAll(" pbz.wire.writeVarintToSlice(buffer, &index, payload_len); ");
    try writer.writeAll("_ = try ");
    try writer.writeAll(value_expr);
    try writer.writeAll(if (validate_utf8) ".encodeIntoAssumeCapacity(buffer[index..][0..payload_len]);" else ".encodeIntoAssumeCapacityTrustedUtf8(buffer[index..][0..payload_len]);");
    try writer.writeAll(" index += payload_len;");
}

fn writeFastDirectLengthDelimitedValidation(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, validate_utf8: bool, prefix: []const u8, value_name: []const u8, writer: *std.Io.Writer) Error!void {
    if (!validate_utf8 or field.kind != .scalar or field.kind.scalar != .string or fieldUtf8Validation(file, field) != .verify) return;
    try writer.writeAll("if (!pbz.validateUtf8(");
    try writer.writeAll(prefix);
    if (value_name.len != 0) try writeQuotedIdent(value_name, writer);
    try writer.writeAll(")) return error.InvalidUtf8; ");
}

fn writeFastDirectLengthDelimitedPayload(prefix: []const u8, value_name: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("pbz.wire.writeVarintToSlice(buffer, &index, ");
    try writer.writeAll(prefix);
    if (value_name.len != 0) try writeQuotedIdent(value_name, writer);
    try writer.writeAll(".len); pbz.wire.copyBytes(buffer[index..][0..");
    try writer.writeAll(prefix);
    if (value_name.len != 0) try writeQuotedIdent(value_name, writer);
    try writer.writeAll(".len], ");
    try writer.writeAll(prefix);
    if (value_name.len != 0) try writeQuotedIdent(value_name, writer);
    try writer.writeAll("); index += ");
    try writer.writeAll(prefix);
    if (value_name.len != 0) try writeQuotedIdent(value_name, writer);
    try writer.writeAll(".len;");
}

fn writeFastDirectRepeatedEnumEncode(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("for (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(") |item| { ");
    try writeFastDirectTag(field.number, .{ .enumeration = "" }, writer);
    try writer.writeAll(" pbz.wire.writeVarintToSlice(buffer, &index, @as(u64, @bitCast(@as(i64, item)))); }\n");
}

fn writeFastDirectPackedScalarEncode(field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("if (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".len != 0) {\n");
    if (fixedPackedScalarWidth(scalar)) |width| {
        try indent(writer, depth + 1);
        try writer.writeAll("const packed_len = self.");
        try writeQuotedIdent(field.name, writer);
        try writer.print(".len * {d};\n", .{width});
        try indent(writer, depth + 1);
        try writeFastDirectTag(field.number, .{ .scalar = .bytes }, writer);
        try writer.writeAll("\n");
        try indent(writer, depth + 1);
        try writer.writeAll("pbz.wire.writeVarintToSlice(buffer, &index, packed_len);\n");
        if (fixedWidthViewScalarType(scalar)) |_| {
            try indent(writer, depth + 1);
            if (scalar == .double) {
                try writer.writeAll("if (comptime @import(\"builtin\").target.cpu.arch.endian() == .little) { const payload = std.mem.sliceAsBytes(self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll("); pbz.wire.copyBytes(buffer[index..][0..payload.len], payload); index += payload.len; } else { for (self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(") |item| pbz.wire.writeRawLittleToSlice(u64, buffer, &index, @bitCast(item)); }\n");
            } else if (scalar == .float) {
                try writer.writeAll("if (comptime @import(\"builtin\").target.cpu.arch.endian() == .little) { const payload = std.mem.sliceAsBytes(self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll("); pbz.wire.copyBytes(buffer[index..][0..payload.len], payload); index += payload.len; } else { for (self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(") |item| pbz.wire.writeRawLittleToSlice(u32, buffer, &index, @bitCast(item)); }\n");
            } else {
                try writer.writeAll("const payload = std.mem.sliceAsBytes(self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll("); pbz.wire.copyBytes(buffer[index..][0..payload.len], payload); index += payload.len;\n");
            }
        } else if (scalar == .bool) {
            try indent(writer, depth + 1);
            try writer.writeAll("const payload = std.mem.sliceAsBytes(self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll("); pbz.wire.copyBytes(buffer[index..][0..payload.len], payload); index += payload.len;\n");
        } else {
            try indent(writer, depth + 1);
            try writer.writeAll("for (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(") |item| ");
            try writeFastDirectPackedScalarPayload("item", scalar, writer);
            try writer.writeAll("\n");
        }
    } else {
        try indent(writer, depth + 1);
        try writeFastDirectTag(field.number, .{ .scalar = .bytes }, writer);
        try writer.writeAll("\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const packed_len_reserved = pbz.wire.encodedVarintSize(self.");
        try writeQuotedIdent(field.name, writer);
        try writer.print(".len * {d});\n", .{maxPackedScalarWidth(scalar)});
        try indent(writer, depth + 1);
        try writer.writeAll("const packed_len_index = index; index += packed_len_reserved;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const payload_start = index;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("for (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(") |item| ");
        try writeFastDirectPackedScalarPayload("item", scalar, writer);
        try writer.writeAll("\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const packed_len = index - payload_start;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const packed_len_size = pbz.wire.encodedVarintSize(packed_len);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("if (packed_len_size != packed_len_reserved) {\n");
        try indent(writer, depth + 2);
        try writer.writeAll("if (packed_len_size > packed_len_reserved) { std.mem.copyBackwards(u8, buffer[payload_start + (packed_len_size - packed_len_reserved) .. index + (packed_len_size - packed_len_reserved)], buffer[payload_start..index]); index += packed_len_size - packed_len_reserved; }\n");
        try indent(writer, depth + 2);
        try writer.writeAll("else { std.mem.copyForwards(u8, buffer[payload_start - (packed_len_reserved - packed_len_size) .. index - (packed_len_reserved - packed_len_size)], buffer[payload_start..index]); index -= packed_len_reserved - packed_len_size; }\n");
        try indent(writer, depth + 1);
        try writer.writeAll("}\n");
        try indent(writer, depth + 1);
        try writer.writeAll("var packed_len_write_index = packed_len_index; pbz.wire.writeVarintToSlice(buffer, &packed_len_write_index, packed_len);\n");
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeFastDirectPackedEnumEncode(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("if (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".len != 0) {\n");
    try indent(writer, depth + 1);
    try writeFastDirectTag(field.number, .{ .scalar = .bytes }, writer);
    try writer.writeAll("\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const packed_len_reserved = pbz.wire.encodedVarintSize(self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".len * 10);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const packed_len_index = index; index += packed_len_reserved;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const payload_start = index;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("for (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(") |item| { if (item >= 0 and item < 0x80) { buffer[index] = @intCast(item); index += 1; } else pbz.wire.writeVarintToSlice(buffer, &index, @as(u64, @bitCast(@as(i64, item)))); }\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const packed_len = index - payload_start;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const packed_len_size = pbz.wire.encodedVarintSize(packed_len);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (packed_len_size != packed_len_reserved) {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("if (packed_len_size > packed_len_reserved) { std.mem.copyBackwards(u8, buffer[payload_start + (packed_len_size - packed_len_reserved) .. index + (packed_len_size - packed_len_reserved)], buffer[payload_start..index]); index += packed_len_size - packed_len_reserved; }\n");
    try indent(writer, depth + 2);
    try writer.writeAll("else { std.mem.copyForwards(u8, buffer[payload_start - (packed_len_reserved - packed_len_size) .. index - (packed_len_reserved - packed_len_size)], buffer[payload_start..index]); index -= packed_len_reserved - packed_len_size; }\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var packed_len_write_index = packed_len_index; pbz.wire.writeVarintToSlice(buffer, &packed_len_write_index, packed_len);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeFastDirectTag(number: u29, kind: schema.FieldKind, writer: *std.Io.Writer) Error!void {
    const tag = rawFieldTag(number, kind);
    try writeFastDirectTagValue(tag, writer);
}

fn writeFastDirectRawTag(number: u29, wire_type: wire.WireType, writer: *std.Io.Writer) Error!void {
    const tag = rawTagValue(number, wire_type);
    try writeFastDirectTagValue(tag, writer);
}

fn writeFastDirectTagValue(tag: u64, writer: *std.Io.Writer) Error!void {
    if (tag <= std.math.maxInt(u8)) {
        try writer.print("buffer[index] = {d}; index += 1;", .{tag});
    } else {
        try writer.print("pbz.wire.writeVarintToSlice(buffer, &index, {d});", .{tag});
    }
}

fn writeFastDirectScalarPayload(prefix: []const u8, field_name: []const u8, scalar: schema.ScalarType, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .double => try writeFastDirectRawFieldPayload(prefix, field_name, "u64", true, writer),
        .float => try writeFastDirectRawFieldPayload(prefix, field_name, "u32", true, writer),
        .fixed32 => try writeFastDirectRawFieldPayload(prefix, field_name, "u32", false, writer),
        .fixed64 => try writeFastDirectRawFieldPayload(prefix, field_name, "u64", false, writer),
        .sfixed32 => try writeFastDirectRawFieldPayload(prefix, field_name, "i32", false, writer),
        .sfixed64 => try writeFastDirectRawFieldPayload(prefix, field_name, "i64", false, writer),
        .int32 => try writeFastDirectVarintFieldPayload(prefix, field_name, "@as(u64, @bitCast(@as(i64, ", ")))", writer),
        .int64 => try writeFastDirectVarintFieldPayload(prefix, field_name, "@as(u64, @bitCast(", "))", writer),
        .uint32, .uint64 => try writeFastDirectVarintFieldPayload(prefix, field_name, "", "", writer),
        .sint32 => try writeFastDirectVarintFieldPayload(prefix, field_name, "pbz.wire.zigZagEncode32(", ")", writer),
        .sint64 => try writeFastDirectVarintFieldPayload(prefix, field_name, "pbz.wire.zigZagEncode64(", ")", writer),
        .bool => try writeFastDirectBoolFieldPayload(prefix, field_name, writer),
        .string, .bytes => try writer.writeAll("@compileError(\"unsupported direct payload\")"),
    }
}

fn writeFastDirectRawFieldPayload(prefix: []const u8, field_name: []const u8, zig_type: []const u8, bitcast_value: bool, writer: *std.Io.Writer) Error!void {
    try writer.print("pbz.wire.writeRawLittleToSlice({s}, buffer, &index, ", .{zig_type});
    if (bitcast_value) try writer.writeAll("@bitCast(");
    try writer.writeAll(prefix);
    if (field_name.len != 0) try writeQuotedIdent(field_name, writer);
    if (bitcast_value) try writer.writeAll(")");
    try writer.writeAll(");");
}

fn writeFastDirectVarintFieldPayload(prefix: []const u8, field_name: []const u8, before: []const u8, after: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("pbz.wire.writeDirectScalarVarintToSlice(buffer, &index, ");
    try writer.writeAll(before);
    try writer.writeAll(prefix);
    if (field_name.len != 0) try writeQuotedIdent(field_name, writer);
    try writer.writeAll(after);
    try writer.writeAll(");");
}

fn writeFastDirectBoolFieldPayload(prefix: []const u8, field_name: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("buffer[index] = if (");
    try writer.writeAll(prefix);
    if (field_name.len != 0) try writeQuotedIdent(field_name, writer);
    try writer.writeAll(") 1 else 0; index += 1;");
}

fn writeFastDirectPackedScalarPayload(value_expr: []const u8, scalar: schema.ScalarType, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .int32 => try writer.print("pbz.wire.writeVarintToSlice(buffer, &index, @as(u64, @bitCast(@as(i64, {s}))));", .{value_expr}),
        .int64 => try writer.print("if ({s} < 0) pbz.wire.writeNegativeInt64VarintToSlice(buffer, &index, {s}) else pbz.wire.writeVarintToSlice(buffer, &index, @intCast({s}));", .{ value_expr, value_expr, value_expr }),
        .uint32 => try writer.print("pbz.wire.writeUInt32VarintToSlice(buffer, &index, {s});", .{value_expr}),
        .uint64 => try writer.print("pbz.wire.writeVarintToSlice(buffer, &index, {s});", .{value_expr}),
        .sint32 => try writer.print("pbz.wire.writeVarintToSlice(buffer, &index, pbz.wire.zigZagEncode32({s}));", .{value_expr}),
        .sint64 => try writer.print("pbz.wire.writeVarintToSlice(buffer, &index, pbz.wire.zigZagEncode64({s}));", .{value_expr}),
        .bool => try writer.print("{{ buffer[index] = if ({s}) 1 else 0; index += 1; }}", .{value_expr}),
        else => try writer.writeAll("@compileError(\"unsupported packed direct payload\")"),
    }
}

fn maxPackedScalarWidth(scalar: schema.ScalarType) usize {
    return switch (scalar) {
        .bool => 1,
        .uint32, .sint32 => 5,
        .int32, .int64, .uint64, .sint64 => 10,
        .double, .fixed64, .sfixed64 => 8,
        .float, .fixed32, .sfixed32 => 4,
        .string, .bytes => unreachable,
    };
}

fn writeEncodedSize(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn encodedSize(self: @This()) usize {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var size: usize = 0;\n");
    for (message.fields.items) |*field| {
        if (field.oneof_name == null) try writeEncodedSizeField(ctx, field, "self.", writer, depth + 1);
    }
    for (message.oneofs.items) |oneof| try writeEncodedSizeOneof(ctx, message, oneof, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("for (self._unknown_fields) |raw| size += raw.len;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return size;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeEncodedSizeField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, receiver: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    if (field.kind == .map) return try writeEncodedSizeMapField(ctx, field, receiver, writer, depth);
    if (field.cardinality == .repeated) return try writeEncodedSizeRepeatedField(ctx, field, receiver, writer, depth);
    try indent(writer, depth);
    if (typedSingularMessageFieldWithContext(ctx, field)) |_| {
        try writer.writeAll("if (");
        try writer.writeAll(receiver);
        try writeQuotedIdent(field.name, writer);
        if (field.kind == .group) {
            try writer.writeAll(") |value| size += ");
            try writer.print("{d}", .{(wire.tagSize(field.number, .start_group) catch unreachable) + (wire.tagSize(field.number, .end_group) catch unreachable)});
            try writer.writeAll(" + value.encodedSize();\n");
        } else {
            try writer.writeAll(") |value| { const payload_len = value.encodedSize(); size += ");
            try writer.print("{d}", .{wire.tagSize(field.number, .length_delimited) catch unreachable});
            try writer.writeAll(" + pbz.wire.encodedVarintSize(payload_len) + payload_len; }\n");
        }
        return;
    }
    if (hasPresence(file, field.*)) {
        try writer.writeAll("if (");
        try writer.writeAll(receiver);
        try writePresenceIdent(field.name, writer);
        try writer.writeAll(") size += ");
        try writeSingleFieldEncodedSizeExpr(field.number, field.kind, receiver, field.name, writer);
        try writer.writeAll(";\n");
    } else {
        switch (field.kind) {
            .scalar => |scalar| {
                try writeScalarSkipCondition(receiver, field.name, scalar, writer);
                try writer.writeAll("size += ");
                try writeSingleFieldEncodedSizeExpr(field.number, field.kind, receiver, field.name, writer);
                try writer.writeAll(";\n");
            },
            .enumeration => {
                try writer.writeAll("if (");
                try writer.writeAll(receiver);
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(" != 0) size += ");
                try writeSingleFieldEncodedSizeExpr(field.number, field.kind, receiver, field.name, writer);
                try writer.writeAll(";\n");
            },
            .message, .group => {
                try writer.writeAll("if (");
                try writer.writeAll(receiver);
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(".len != 0) size += ");
                try writeSingleFieldEncodedSizeExpr(field.number, field.kind, receiver, field.name, writer);
                try writer.writeAll(";\n");
            },
            .map => unreachable,
        }
    }
}

fn writeEncodedSizeRepeatedField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, receiver: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    if (typedRepeatedMessageFieldWithContext(ctx, field)) |_| {
        try indent(writer, depth);
        try writer.writeAll("for (");
        try writer.writeAll(receiver);
        try writeQuotedIdent(field.name, writer);
        if (field.kind == .group) {
            try writer.writeAll(") |item| size += ");
            try writer.print("{d}", .{(wire.tagSize(field.number, .start_group) catch unreachable) + (wire.tagSize(field.number, .end_group) catch unreachable)});
            try writer.writeAll(" + item.encodedSize();\n");
        } else {
            try writer.writeAll(") |item| { const payload_len = item.encodedSize(); size += ");
            try writer.print("{d}", .{wire.tagSize(field.number, .length_delimited) catch unreachable});
            try writer.writeAll(" + pbz.wire.encodedVarintSize(payload_len) + payload_len; }\n");
        }
        return;
    }
    if ((field.kind == .scalar or field.kind == .enumeration) and field.resolvedPacked(file)) {
        try indent(writer, depth);
        try writer.writeAll("if (");
        try writer.writeAll(receiver);
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(".len != 0) {\n");
        try indent(writer, depth + 1);
        const fixed_width = if (field.kind == .scalar) fixedPackedScalarWidth(field.kind.scalar) else null;
        if (fixed_width) |width| {
            try writer.writeAll("const packed_len = ");
            try writer.writeAll(receiver);
            try writeQuotedIdent(field.name, writer);
            try writer.print(".len * {d};\n", .{width});
        } else {
            try writer.writeAll("var packed_len: usize = 0;\n");
            try indent(writer, depth + 1);
            try writer.writeAll("for (");
            try writer.writeAll(receiver);
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(") |item| packed_len += ");
            if (field.kind == .scalar) {
                try writeScalarPayloadSizeExpr(field.kind.scalar, "item", writer);
            } else {
                try writer.writeAll("pbz.wire.encodedVarintSize(@as(u64, @bitCast(@as(i64, item))))");
            }
            try writer.writeAll(";\n");
        }
        try indent(writer, depth + 1);
        try writer.print("size += {d} + pbz.wire.encodedVarintSize(packed_len) + packed_len;\n", .{wire.tagSize(field.number, .length_delimited) catch unreachable});
        try indent(writer, depth);
        try writer.writeAll("}\n");
        return;
    }

    try indent(writer, depth);
    try writer.writeAll("for (");
    try writer.writeAll(receiver);
    try writeQuotedIdent(field.name, writer);
    if (field.kind == .scalar and scalarPayloadSizeIsConstant(field.kind.scalar)) {
        try writer.writeAll(") |_| size += ");
    } else {
        try writer.writeAll(") |item| size += ");
    }
    try writeSingleFieldEncodedSizeExprForValue(field.number, field.kind, "item", writer);
    try writer.writeAll(";\n");
}

fn writeEncodedSizeMapField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, receiver: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    const map_type = field.kind.map;
    const key_constant = scalarPayloadSizeIsConstant(map_type.key);
    const value_kind = map_type.value.*;
    const value_constant = value_kind == .scalar and scalarPayloadSizeIsConstant(value_kind.scalar);
    try indent(writer, depth);
    try writer.writeAll("{ var map_it = ");
    try writer.writeAll(receiver);
    try writeQuotedIdent(field.name, writer);
    if (key_constant and value_constant) {
        try writer.writeAll(".iterator(); while (map_it.next()) |_| {\n");
    } else {
        try writer.writeAll(".iterator(); while (map_it.next()) |entry| {\n");
    }
    if (!key_constant or !value_constant) {
        try indent(writer, depth + 1);
        if (!key_constant) try writer.writeAll("const key = entry.key_ptr.*; ");
        if (!value_constant) try writer.writeAll("const value = entry.value_ptr.*;");
        try writer.writeAll("\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("const entry_len = ");
    try writeMapEntryFieldSizeExpr(1, .{ .scalar = map_type.key }, "key", writer);
    try writer.writeAll(" + ");
    try writeMapEntryValueFieldSizeExpr(ctx, field, "value", writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.print("size += {d} + pbz.wire.encodedVarintSize(entry_len) + entry_len;\n", .{wire.tagSize(field.number, .length_delimited) catch unreachable});
    try indent(writer, depth);
    try writer.writeAll("} }\n");
}

fn writeEncodedSizeOneof(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, oneof: schema.OneofDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("switch (self.");
    try writeQuotedIdent(oneof.name, writer);
    try writer.writeAll(") {\n");
    try indent(writer, depth + 1);
    try writer.writeAll(".none => {},\n");
    for (message.fields.items) |*field| {
        if (field.oneof_name) |name| {
            if (!std.mem.eql(u8, name, oneof.name)) continue;
            try indent(writer, depth + 1);
            try writer.writeAll(".");
            try writeQuotedIdent(field.name, writer);
            if (typedOneofMessageFieldWithContext(ctx, field)) |_| {
                if (field.kind == .group) {
                    try writer.writeAll(" => |value| size += ");
                    try writer.print("{d}", .{(wire.tagSize(field.number, .start_group) catch unreachable) + (wire.tagSize(field.number, .end_group) catch unreachable)});
                    try writer.writeAll(" + value.encodedSize(),\n");
                } else {
                    try writer.writeAll(" => |value| { const payload_len = value.encodedSize(); size += ");
                    try writer.print("{d}", .{wire.tagSize(field.number, .length_delimited) catch unreachable});
                    try writer.writeAll(" + pbz.wire.encodedVarintSize(payload_len) + payload_len; },\n");
                }
            } else {
                if (field.kind == .scalar and scalarPayloadSizeIsConstant(field.kind.scalar)) {
                    try writer.writeAll(" => size += ");
                } else {
                    try writer.writeAll(" => |value| size += ");
                }
                try writeSingleFieldEncodedSizeExprForValue(field.number, field.kind, "value", writer);
                try writer.writeAll(",\n");
            }
        }
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeSingleFieldEncodedSizeExpr(number: u29, kind: schema.FieldKind, receiver: []const u8, field_name: []const u8, writer: *std.Io.Writer) Error!void {
    try writeSingleFieldEncodedSizePrefix(number, kind, writer);
    try writer.writeAll(" + ");
    try writeKindPayloadSizeExprForField(kind, receiver, field_name, writer);
}

fn writeSingleFieldEncodedSizeExprForValue(number: u29, kind: schema.FieldKind, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    try writeSingleFieldEncodedSizePrefix(number, kind, writer);
    try writer.writeAll(" + ");
    try writeKindPayloadSizeExpr(kind, value_expr, writer);
}

fn writeSingleFieldEncodedSizePrefix(number: u29, kind: schema.FieldKind, writer: *std.Io.Writer) Error!void {
    switch (kind) {
        .group => {
            const start = wire.tagSize(number, .start_group) catch unreachable;
            const end = wire.tagSize(number, .end_group) catch unreachable;
            try writer.print("{d} + {d}", .{ start, end });
        },
        else => {
            const tag = wire.tagSize(number, kind.wireType()) catch unreachable;
            try writer.print("{d}", .{tag});
        },
    }
}

fn writeKindPayloadSizeExprForField(kind: schema.FieldKind, receiver: []const u8, field_name: []const u8, writer: *std.Io.Writer) Error!void {
    switch (kind) {
        .scalar => |scalar| try writeScalarPayloadSizeExprForField(scalar, receiver, field_name, writer),
        .enumeration => {
            try writer.writeAll("pbz.wire.encodedVarintSize(@as(u64, @bitCast(@as(i64, ");
            try writer.writeAll(receiver);
            try writeQuotedIdent(field_name, writer);
            try writer.writeAll("))))");
        },
        .message => {
            try writer.writeAll("pbz.wire.encodedVarintSize(");
            try writer.writeAll(receiver);
            try writeQuotedIdent(field_name, writer);
            try writer.writeAll(".len) + ");
            try writer.writeAll(receiver);
            try writeQuotedIdent(field_name, writer);
            try writer.writeAll(".len");
        },
        .group => {
            try writer.writeAll(receiver);
            try writeQuotedIdent(field_name, writer);
            try writer.writeAll(".len");
        },
        .map => unreachable,
    }
}

fn writeScalarPayloadSizeExprForField(scalar: schema.ScalarType, receiver: []const u8, field_name: []const u8, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .double, .fixed64, .sfixed64 => try writer.writeAll("8"),
        .float, .fixed32, .sfixed32 => try writer.writeAll("4"),
        .int32 => {
            try writer.writeAll("pbz.wire.encodedVarintSize(@as(u64, @bitCast(@as(i64, ");
            try writer.writeAll(receiver);
            try writeQuotedIdent(field_name, writer);
            try writer.writeAll("))))");
        },
        .int64 => {
            try writer.writeAll("pbz.wire.encodedVarintSize(@as(u64, @bitCast(");
            try writer.writeAll(receiver);
            try writeQuotedIdent(field_name, writer);
            try writer.writeAll(")))");
        },
        .uint32, .uint64 => {
            try writer.writeAll("pbz.wire.encodedVarintSize(");
            try writer.writeAll(receiver);
            try writeQuotedIdent(field_name, writer);
            try writer.writeAll(")");
        },
        .sint32 => {
            try writer.writeAll("pbz.wire.encodedVarintSize(pbz.wire.zigZagEncode32(");
            try writer.writeAll(receiver);
            try writeQuotedIdent(field_name, writer);
            try writer.writeAll("))");
        },
        .sint64 => {
            try writer.writeAll("pbz.wire.encodedVarintSize(pbz.wire.zigZagEncode64(");
            try writer.writeAll(receiver);
            try writeQuotedIdent(field_name, writer);
            try writer.writeAll("))");
        },
        .bool => {
            try writer.writeAll("(if (");
            try writer.writeAll(receiver);
            try writeQuotedIdent(field_name, writer);
            try writer.writeAll(") @as(usize, 1) else @as(usize, 1))");
        },
        .string, .bytes => {
            try writer.writeAll("pbz.wire.encodedVarintSize(");
            try writer.writeAll(receiver);
            try writeQuotedIdent(field_name, writer);
            try writer.writeAll(".len) + ");
            try writer.writeAll(receiver);
            try writeQuotedIdent(field_name, writer);
            try writer.writeAll(".len");
        },
    }
}

fn writeEncodeDeterministic(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn writeDeterministicTo(self: @This(), allocator: std.mem.Allocator, w: *pbz.Writer) anyerror!void {\n");
    try writeEncodeFieldsByNumber(ctx, message, writer, depth + 1);
    try writeEncodeUnknownFieldsDeterministic(writer, depth + 1);
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn writeDeterministicToAssumeCapacity(self: @This(), allocator: std.mem.Allocator, w: *pbz.Writer) anyerror!void {\n");
    try writeEncodeFieldsByNumberAssumeCapacity(ctx, message, writer, depth + 1);
    try writeEncodeUnknownFieldsDeterministicAssumeCapacity(writer, depth + 1);
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn encodeDeterministic(self: @This(), allocator: std.mem.Allocator) ![]u8 {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var w = pbz.Writer.init(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer w.deinit();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try w.bytes.ensureTotalCapacity(allocator, self.encodedSize());\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.writeDeterministicToAssumeCapacity(allocator, &w);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try w.toOwnedSlice();\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn encodeDeterministicInto(self: @This(), allocator: std.mem.Allocator, buffer: []u8) ![]u8 {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const size = self.encodedSize();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (buffer.len < size) return error.NoSpaceLeft;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var w = pbz.Writer.initBuffer(std.heap.page_allocator, buffer[0..size]);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.writeDeterministicToAssumeCapacity(allocator, &w);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return buffer[0..w.slice().len];\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn encodeDeterministicIntoAssumeCapacity(self: @This(), allocator: std.mem.Allocator, buffer: []u8) ![]u8 {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var w = pbz.Writer.initBuffer(std.heap.page_allocator, buffer);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.writeDeterministicToAssumeCapacity(allocator, &w);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return buffer[0..w.slice().len];\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn encodeDeterministicInitialized(self: @This(), allocator: std.mem.Allocator) ![]u8 {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.validateRequiredRecursive(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try self.encodeDeterministic(allocator);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeEncodeUnknownFields(writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("for (self._unknown_fields) |raw| try w.appendSlice(raw);\n");
}

fn writeEncodeUnknownFieldsDeterministic(writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("try pbz.wire.writeRawFieldsDeterministic(allocator, self._unknown_fields, w);\n");
}

fn writeEncodeUnknownFieldsDeterministicAssumeCapacity(writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("try pbz.wire.writeRawFieldsDeterministicAssumeCapacity(allocator, self._unknown_fields, w);\n");
}

fn writeEncodeFieldsByNumber(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    var emitted: usize = 0;
    var previous: u29 = 0;
    while (emitted < message.fields.items.len) : (emitted += 1) {
        var next: ?*const schema.FieldDescriptor = null;
        for (message.fields.items) |*field| {
            if (field.number <= previous) continue;
            if (next == null or field.number < next.?.number) next = field;
        }
        const field = next orelse break;
        previous = field.number;
        if (field.oneof_name) |oneof_name| {
            try writeEncodeOneofSingleField(ctx, field, oneof_name, writer, depth);
        } else if (field.kind == .map) {
            try writeEncodeMapFieldDeterministic(ctx, field, writer, depth);
        } else {
            try writeEncodeFieldDeterministic(ctx, field, writer, depth);
        }
    }
}

fn writeEncodeFieldsByNumberAssumeCapacity(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    var emitted: usize = 0;
    var previous: u29 = 0;
    while (emitted < message.fields.items.len) : (emitted += 1) {
        var next: ?*const schema.FieldDescriptor = null;
        for (message.fields.items) |*field| {
            if (field.number <= previous) continue;
            if (next == null or field.number < next.?.number) next = field;
        }
        const field = next orelse break;
        previous = field.number;
        if (field.oneof_name) |oneof_name| {
            try writeEncodeOneofSingleFieldDeterministicAssumeCapacity(ctx, field, oneof_name, writer, depth);
        } else if (field.kind == .map) {
            try writeEncodeMapFieldDeterministicAssumeCapacity(ctx, field, writer, depth);
        } else {
            try writeEncodeFieldDeterministicAssumeCapacity(ctx, field, writer, depth);
        }
    }
}

fn writeEncodeOneofSingleField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, oneof_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("switch (self.");
    try writeQuotedIdent(oneof_name, writer);
    try writer.writeAll(") {\n");
    try indent(writer, depth + 1);
    try writer.writeAll(".");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" => |value| ");
    try writeOneofValueEncodeDeterministic(ctx, field, "value", writer);
    try writer.writeAll(",\n");
    try indent(writer, depth + 1);
    try writer.writeAll("else => {},\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeEncodeOneofSingleFieldDeterministicAssumeCapacity(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, oneof_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("switch (self.");
    try writeQuotedIdent(oneof_name, writer);
    try writer.writeAll(") {\n");
    try indent(writer, depth + 1);
    try writer.writeAll(".");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" => |value| ");
    try writeOneofValueEncodeDeterministicAssumeCapacity(ctx, field, "value", writer);
    try writer.writeAll(",\n");
    try indent(writer, depth + 1);
    try writer.writeAll("else => {},\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeOneofValueEncodeDeterministic(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    const file = ctx.file;
    switch (field.kind) {
        .message => |type_name| {
            if (codegenCanReferenceMessageWithContext(ctx, type_name)) {
                if (typedOneofMessageFieldWithContext(ctx, field)) |_| {
                    try writer.print("{{ const payload_len = {s}.encodedSize(); try w.writeTag({d}, .length_delimited); try w.writeVarint(payload_len); try {s}.writeDeterministicTo(allocator, w); }}", .{ value_expr, field.number, value_expr });
                } else {
                    try writer.writeAll("{ ");
                    try writeEncodeMessagePayloadDeterministic(ctx, field.number, fieldMessageEncoding(file, field) == .delimited, type_name, value_expr, "w", writer);
                    try writer.writeAll(" }");
                }
            } else try writeOneofValueEncode(ctx, field, value_expr, writer);
        },
        .group => |type_name| {
            if (codegenCanReferenceMessageWithContext(ctx, type_name)) {
                if (typedOneofMessageFieldWithContext(ctx, field)) |_| {
                    try writer.print("{{ try w.writeTag({d}, .start_group); try {s}.writeDeterministicTo(allocator, w); try w.writeTag({d}, .end_group); }}", .{ field.number, value_expr, field.number });
                } else {
                    try writer.writeAll("{ ");
                    try writeEncodeMessagePayloadDeterministic(ctx, field.number, true, type_name, value_expr, "w", writer);
                    try writer.writeAll(" }");
                }
            } else try writeOneofValueEncode(ctx, field, value_expr, writer);
        },
        else => try writeOneofValueEncode(ctx, field, value_expr, writer),
    }
}

fn writeOneofValueEncodeDeterministicAssumeCapacity(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    const file = ctx.file;
    switch (field.kind) {
        .message => |type_name| {
            if (codegenCanReferenceMessageWithContext(ctx, type_name)) {
                if (typedOneofMessageFieldWithContext(ctx, field)) |_| {
                    try writer.print("{{ const payload_len = {s}.encodedSize(); w.writeTagAssumeCapacity({d}, .length_delimited); w.writeVarintAssumeCapacity(payload_len); try {s}.writeDeterministicToAssumeCapacity(allocator, w); }}", .{ value_expr, field.number, value_expr });
                } else {
                    try writer.writeAll("{ ");
                    try writeEncodeMessagePayloadDeterministic(ctx, field.number, fieldMessageEncoding(file, field) == .delimited, type_name, value_expr, "w", writer);
                    try writer.writeAll(" }");
                }
            } else try writeOneofValueEncodeAssumeCapacity(ctx, field, value_expr, writer);
        },
        .group => |type_name| {
            if (codegenCanReferenceMessageWithContext(ctx, type_name)) {
                if (typedOneofMessageFieldWithContext(ctx, field)) |_| {
                    try writer.print("{{ w.writeTagAssumeCapacity({d}, .start_group); try {s}.writeDeterministicToAssumeCapacity(allocator, w); w.writeTagAssumeCapacity({d}, .end_group); }}", .{ field.number, value_expr, field.number });
                } else {
                    try writer.writeAll("{ ");
                    try writeEncodeMessagePayloadDeterministic(ctx, field.number, true, type_name, value_expr, "w", writer);
                    try writer.writeAll(" }");
                }
            } else try writeOneofValueEncodeAssumeCapacity(ctx, field, value_expr, writer);
        },
        else => try writeOneofValueEncodeAssumeCapacity(ctx, field, value_expr, writer),
    }
}

fn writeEncodeInitialized(writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn encodeInitialized(self: @This(), allocator: std.mem.Allocator) ![]u8 {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.validateRequiredRecursive(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try self.encode(allocator);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeOwnedAllocator(writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("fn _pbzOwnedAllocator(self: *@This(), allocator: std.mem.Allocator) !std.mem.Allocator {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (self._json_arena == null) {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("const arena = try allocator.create(std.heap.ArenaAllocator);\n");
    try indent(writer, depth + 2);
    try writer.writeAll("errdefer allocator.destroy(arena);\n");
    try indent(writer, depth + 2);
    try writer.writeAll("arena.* = std.heap.ArenaAllocator.init(allocator);\n");
    try indent(writer, depth + 2);
    try writer.writeAll("self._json_arena = arena;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return self._json_arena.?.allocator();\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeUnknownFieldMethods(writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn unknownFieldCount(self: @This()) usize {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return self._unknown_fields.len;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn unknownFields(self: @This()) []const []const u8 {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return self._unknown_fields;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn unknownFieldCountByNumber(self: @This(), number: pbz.FieldNumber) !usize {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return pbz.wire.rawFieldCountByNumberAssumeValid(self._unknown_fields, number);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn hasUnknownFieldNumber(self: @This(), number: pbz.FieldNumber) !bool {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return pbz.wire.rawFieldHasNumberAssumeValid(self._unknown_fields, number);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn unknownFieldNumbersAlloc(self: @This(), allocator: std.mem.Allocator) ![]pbz.FieldNumber {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try pbz.wire.rawFieldNumbersAlloc(allocator, self._unknown_fields);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn unknownFieldNumberRunsAlloc(self: @This(), allocator: std.mem.Allocator) ![]pbz.wire.RawFieldNumberRun {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try pbz.wire.rawFieldNumberRunsAlloc(allocator, self._unknown_fields);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn unknownFieldsByNumberAlloc(self: @This(), allocator: std.mem.Allocator, number: pbz.FieldNumber) ![]const []const u8 {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try pbz.wire.rawFieldsByNumberAllocAssumeValid(allocator, self._unknown_fields, number);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn appendUnknownRaw(self: *@This(), allocator: std.mem.Allocator, raw: []const u8) !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try pbz.wire.appendRawFieldClone(allocator, &self._unknown_fields, raw);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn clearUnknownFieldsByNumber(self: *@This(), allocator: std.mem.Allocator, number: pbz.FieldNumber) !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try pbz.wire.clearRawFieldsByNumber(allocator, &self._unknown_fields, number);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn clearUnknownFields(self: *@This(), allocator: std.mem.Allocator) void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pbz.wire.clearRawFields(allocator, &self._unknown_fields);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeBorrowedViewMethods(file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    for (message.fields.items) |*field| {
        if (field.oneof_name != null) continue;
        if (field.kind != .scalar) continue;
        if (field.kind.scalar == .string or field.kind.scalar == .bytes) {
            try writeLengthDelimitedBorrowedSlicesMethod(field, writer, depth);
            continue;
        }
        if (field.cardinality != .repeated) continue;
        if (!field.resolvedPacked(file)) continue;
        if (field.kind.scalar == .bool) {
            try writePackedBoolSlicesMethod(field, writer, depth);
            continue;
        }
        if (packedVarintIteratorType(field.kind.scalar)) |iterator_type| {
            try writePackedVarintIteratorMethod(field, iterator_type, writer, depth);
            continue;
        }
        if (fixedWidthViewScalarType(field.kind.scalar) == null) continue;
        const view_type = fixedWidthViewScalarType(field.kind.scalar).?;
        try indent(writer, depth);
        try writer.writeAll("pub fn ");
        try writeQuotedIdentWithSuffix(field.name, "PackedFixedView", writer);
        try writer.writeAll("(bytes: []const u8) !?[]align(1) const ");
        try writer.writeAll(view_type);
        try writer.writeAll(" {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return try pbz.wire.packedFixedWidthFieldView(");
        try writer.writeAll(view_type);
        try writer.print(", bytes, {d});\n", .{field.number});
        try indent(writer, depth);
        try writer.writeAll("}\n\n");
        try indent(writer, depth);
        try writer.writeAll("pub fn ");
        try writeQuotedIdentWithSuffix(field.name, "PackedFixedSlices", writer);
        try writer.writeAll("(header: *[20]u8, values: []const ");
        try writer.writeAll(view_type);
        try writer.writeAll(") !pbz.wire.BorrowedFieldSlices {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return try pbz.wire.packedFixedWidthFieldSlices(");
        try writer.writeAll(view_type);
        try writer.print(", header, {d}, values);\n", .{field.number});
        try indent(writer, depth);
        try writer.writeAll("}\n\n");
        if (field.kind.scalar == .fixed32) {
            try indent(writer, depth);
            try writer.writeAll("pub fn ");
            try writeQuotedIdentWithSuffix(field.name, "PackedFixed32View", writer);
            try writer.writeAll("(bytes: []const u8) !?[]align(1) const u32 {\n");
            try indent(writer, depth + 1);
            try writer.writeAll("return try ");
            try writeQuotedIdentWithSuffix(field.name, "PackedFixedView", writer);
            try writer.writeAll("(bytes);\n");
            try indent(writer, depth);
            try writer.writeAll("}\n\n");
            try indent(writer, depth);
            try writer.writeAll("pub fn ");
            try writeQuotedIdentWithSuffix(field.name, "PackedFixed32Slices", writer);
            try writer.writeAll("(header: *[20]u8, values: []const u32) !pbz.wire.BorrowedFieldSlices {\n");
            try indent(writer, depth + 1);
            try writer.writeAll("return try ");
            try writeQuotedIdentWithSuffix(field.name, "PackedFixedSlices", writer);
            try writer.writeAll("(header, values);\n");
            try indent(writer, depth);
            try writer.writeAll("}\n\n");
        }
    }
}

fn writePackedBoolSlicesMethod(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedIdentWithSuffix(field.name, "PackedBoolSlices", writer);
    try writer.writeAll("(header: *[20]u8, values: []const bool) !pbz.wire.BorrowedFieldSlices {\n");
    try indent(writer, depth + 1);
    try writer.print("return try pbz.wire.packedBoolFieldSlices(header, {d}, values);\n", .{field.number});
    try indent(writer, depth);
    try writer.writeAll("}\n\n");
}

fn writePackedVarintIteratorMethod(field: *const schema.FieldDescriptor, iterator_type: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedIdentWithSuffix(field.name, "PackedIterator", writer);
    try writer.writeAll("(bytes: []const u8) !?");
    try writer.writeAll(iterator_type);
    try writer.writeAll(" {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try pbz.wire.");
    try writer.writeAll(packedVarintIteratorFunction(field.kind.scalar).?);
    try writer.print("(bytes, {d});\n", .{field.number});
    try indent(writer, depth);
    try writer.writeAll("}\n\n");
}

fn packedVarintIteratorType(scalar: schema.ScalarType) ?[]const u8 {
    return switch (scalar) {
        .uint64 => "pbz.wire.PackedUInt64Iterator",
        .int32 => "pbz.wire.PackedInt32Iterator",
        .uint32 => "pbz.wire.PackedUInt32Iterator",
        .int64 => "pbz.wire.PackedInt64Iterator",
        .sint32 => "pbz.wire.PackedSInt32Iterator",
        .sint64 => "pbz.wire.PackedSInt64Iterator",
        else => null,
    };
}

fn packedVarintIteratorFunction(scalar: schema.ScalarType) ?[]const u8 {
    return switch (scalar) {
        .uint64 => "packedUInt64FieldIterator",
        .int32 => "packedInt32FieldIterator",
        .uint32 => "packedUInt32FieldIterator",
        .int64 => "packedInt64FieldIterator",
        .sint32 => "packedSInt32FieldIterator",
        .sint64 => "packedSInt64FieldIterator",
        else => null,
    };
}

fn writeLengthDelimitedBorrowedSlicesMethod(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedIdentWithSuffix(field.name, "FieldView", writer);
    try writer.writeAll("(bytes: []const u8) !?[]const u8 {\n");
    try indent(writer, depth + 1);
    try writer.print("return try pbz.wire.bytesFieldView(bytes, {d});\n", .{field.number});
    try indent(writer, depth);
    try writer.writeAll("}\n\n");
    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedIdentWithSuffix(field.name, "FieldSlices", writer);
    try writer.writeAll("(header: *[20]u8, value: []const u8) !pbz.wire.BorrowedFieldSlices {\n");
    try indent(writer, depth + 1);
    try writer.print("return pbz.wire.lengthDelimitedFieldSlicesAssumeValid(header, {d}, value);\n", .{field.number});
    try indent(writer, depth);
    try writer.writeAll("}\n\n");
    if (field.kind.scalar == .bytes) {
        try indent(writer, depth);
        try writer.writeAll("pub fn ");
        try writeQuotedIdentWithSuffix(field.name, "BytesView", writer);
        try writer.writeAll("(bytes: []const u8) !?[]const u8 {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return try ");
        try writeQuotedIdentWithSuffix(field.name, "FieldView", writer);
        try writer.writeAll("(bytes);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n\n");
        try indent(writer, depth);
        try writer.writeAll("pub fn ");
        try writeQuotedIdentWithSuffix(field.name, "BytesSlices", writer);
        try writer.writeAll("(header: *[20]u8, value: []const u8) !pbz.wire.BorrowedFieldSlices {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return try ");
        try writeQuotedIdentWithSuffix(field.name, "FieldSlices", writer);
        try writer.writeAll("(header, value);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n\n");
    } else if (field.kind.scalar == .string) {
        try indent(writer, depth);
        try writer.writeAll("pub fn ");
        try writeQuotedIdentWithSuffix(field.name, "StringView", writer);
        try writer.writeAll("(bytes: []const u8) !?[]const u8 {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return try ");
        try writeQuotedIdentWithSuffix(field.name, "FieldView", writer);
        try writer.writeAll("(bytes);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n\n");
        try indent(writer, depth);
        try writer.writeAll("pub fn ");
        try writeQuotedIdentWithSuffix(field.name, "StringSlices", writer);
        try writer.writeAll("(header: *[20]u8, value: []const u8) !pbz.wire.BorrowedFieldSlices {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return try ");
        try writeQuotedIdentWithSuffix(field.name, "FieldSlices", writer);
        try writer.writeAll("(header, value);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n\n");
    }
}

fn fixedWidthViewScalarType(scalar: schema.ScalarType) ?[]const u8 {
    return switch (scalar) {
        .double => "f64",
        .float => "f32",
        .fixed32 => "u32",
        .fixed64 => "u64",
        .sfixed32 => "i32",
        .sfixed64 => "i64",
        else => null,
    };
}

fn writeMessageExtensionAccessors(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    var fields: std.ArrayList(*const schema.FieldDescriptor) = .empty;
    defer fields.deinit(ctx.allocator);
    for (file.extensions.items) |*field| {
        if (extensionAppliesToMessage(file, message, field)) try fields.append(ctx.allocator, field);
    }
    for (file.messages.items) |*scope| try collectScopedMessageExtensionFields(ctx, message, scope, &fields);
    if (fields.items.len == 0) {
        try indent(writer, depth);
        try writer.writeAll("// no same-file extension accessors\n");
        return;
    }
    const suffixes = try uniqueExtensionSuffixes(ctx.allocator, fields.items);
    defer {
        for (suffixes) |suffix| ctx.allocator.free(suffix);
        ctx.allocator.free(suffixes);
    }
    for (fields.items, suffixes) |field, suffix| try writeMessageExtensionAccessor(ctx, field, suffix, writer, depth);
}

fn collectScopedMessageExtensionFields(ctx: *const CodegenContext, target: *const schema.MessageDescriptor, scope: *const schema.MessageDescriptor, fields: *std.ArrayList(*const schema.FieldDescriptor)) Error!void {
    const file = ctx.file;
    for (scope.extensions.items) |*field| {
        if (extensionAppliesToMessage(file, target, field)) try fields.append(ctx.allocator, field);
    }
    for (scope.messages.items) |*nested| try collectScopedMessageExtensionFields(ctx, target, nested, fields);
}

fn uniqueExtensionSuffixes(allocator: std.mem.Allocator, fields: []const *const schema.FieldDescriptor) Error![][]const u8 {
    const suffixes = try allocator.alloc([]const u8, fields.len);
    errdefer allocator.free(suffixes);
    for (fields, 0..) |_, index| {
        suffixes[index] = try uniqueExtensionSuffix(allocator, fields, index);
    }
    return suffixes;
}

fn uniqueExtensionSuffix(allocator: std.mem.Allocator, fields: []const *const schema.FieldDescriptor, index: usize) Error![]u8 {
    var components: usize = 1;
    while (components <= 16) : (components += 1) {
        const candidate = try suffixFromComponents(allocator, schema.extensionFullName(fields[index]), components);
        var collision = false;
        for (fields, 0..) |other, other_index| {
            if (other_index == index) continue;
            const other_candidate = try suffixFromComponents(allocator, schema.extensionFullName(other), components);
            defer allocator.free(other_candidate);
            if (std.mem.eql(u8, candidate, other_candidate)) {
                collision = true;
                break;
            }
        }
        if (!collision) return candidate;
        allocator.free(candidate);
    }
    return suffixFromComponents(allocator, schema.extensionFullName(fields[index]), 16);
}

fn suffixFromComponents(allocator: std.mem.Allocator, full_name: []const u8, components: usize) Error![]u8 {
    const trimmed = if (std.mem.startsWith(u8, full_name, ".")) full_name[1..] else full_name;
    var starts: [32]usize = undefined;
    var count: usize = 1;
    starts[0] = 0;
    for (trimmed, 0..) |c, index| {
        if (c == '.' and count < starts.len) {
            starts[count] = index + 1;
            count += 1;
        }
    }
    const take = @min(components, count);
    const start = starts[count - take];
    const out = try allocator.alloc(u8, trimmed.len - start);
    for (trimmed[start..], out) |c, *d| d.* = if (c == '.') '_' else c;
    return out;
}

fn writeMessageExtensionAccessor(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, helper_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedIdentWithPrefix(helper_name, "hasExtension_", writer);
    try writer.writeAll("(self: @This()) !bool {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try ");
    try writeExtensionHelperReference(field, writer);
    try writer.writeAll(".hasInUnknown(self);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedIdentWithPrefix(helper_name, "countExtension_", writer);
    try writer.writeAll("(self: @This()) !usize {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try ");
    try writeExtensionHelperReference(field, writer);
    try writer.writeAll(".countInUnknown(self);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedIdentWithPrefix(helper_name, "getExtension_", writer);
    try writer.writeAll("(self: @This(), allocator: std.mem.Allocator) !");
    if (field.cardinality == .repeated) {
        try writer.writeAll("[]");
        try writer.writeAll(extensionSingleZigType(field.kind));
    } else {
        try writer.writeAll("?");
        try writer.writeAll(extensionSingleZigType(field.kind));
    }
    try writer.writeAll(" {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try ");
    try writeExtensionHelperReference(field, writer);
    if (field.cardinality == .repeated) {
        try writer.writeAll(".decodeAllFromUnknown(self, allocator);\n");
    } else {
        try writer.writeAll(".decodeFirstFromUnknown(self, allocator);\n");
    }
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    if (field.cardinality != .repeated and (field.kind == .scalar or field.kind == .enumeration)) {
        try indent(writer, depth);
        try writer.writeAll("pub fn ");
        try writeQuotedIdentWithPrefix(helper_name, "getExtensionOrDefault_", writer);
        try writer.writeAll("(self: @This(), allocator: std.mem.Allocator) !");
        try writer.writeAll(extensionSingleZigType(field.kind));
        try writer.writeAll(" {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return (try self.");
        try writeQuotedIdentWithPrefix(helper_name, "getExtension_", writer);
        try writer.writeAll("(allocator)) orelse ");
        try writeExtensionHelperReference(field, writer);
        try writer.writeAll(".default_value_zig");
        try writer.writeAll(";\n");
        try indent(writer, depth);
        try writer.writeAll("}\n\n");
    }

    if (field.kind == .enumeration and codegenCanReferenceEnumWithContext(ctx, field.kind.enumeration)) {
        try writeMessageEnumExtensionAccessor(ctx, field, helper_name, writer, depth);
    }

    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedIdentWithPrefix(helper_name, if (field.cardinality == .repeated) "appendExtension_" else "setExtension_", writer);
    try writer.writeAll("(self: *@This(), allocator: std.mem.Allocator, ");
    if (field.cardinality == .repeated) {
        try writer.writeAll("values: ");
        try writer.writeAll(fieldType(field.*));
    } else {
        try writer.writeAll("value: ");
        try writer.writeAll(extensionSingleZigType(field.kind));
    }
    try writer.writeAll(") !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try ");
    try writeExtensionHelperReference(field, writer);
    if (field.cardinality == .repeated) {
        try writer.writeAll(".appendAllToUnknown(self, allocator, values);\n");
    } else {
        try writer.writeAll(".replaceInUnknown(self, allocator, value);\n");
    }
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        try writer.writeAll("pub fn ");
        try writeQuotedIdentWithPrefix(helper_name, "addExtension_", writer);
        try writer.writeAll("(self: *@This(), allocator: std.mem.Allocator, value: ");
        try writer.writeAll(extensionSingleZigType(field.kind));
        try writer.writeAll(") !void {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try ");
        try writeExtensionHelperReference(field, writer);
        try writer.writeAll(".appendToUnknown(self, allocator, value);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n\n");

        try indent(writer, depth);
        try writer.writeAll("pub fn ");
        try writeQuotedIdentWithPrefix(helper_name, "replaceExtension_", writer);
        try writer.writeAll("(self: *@This(), allocator: std.mem.Allocator, values: ");
        try writer.writeAll(fieldType(field.*));
        try writer.writeAll(") !void {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try ");
        try writeExtensionHelperReference(field, writer);
        try writer.writeAll(".replaceAllInUnknown(self, allocator, values);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n\n");
    }

    if ((field.kind == .message or field.kind == .group) and codegenCanReferenceMessageWithContext(ctx, switch (field.kind) {
        .message => |name| name,
        .group => |name| name,
        else => unreachable,
    })) {
        try writeMessageExtensionTypedAccessor(ctx, field, helper_name, writer, depth);
    }

    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedIdentWithPrefix(helper_name, "clearExtension_", writer);
    try writer.writeAll("(self: *@This(), allocator: std.mem.Allocator) !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try ");
    try writeExtensionHelperReference(field, writer);
    try writer.writeAll(".clearFromUnknown(self, allocator);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");
}

fn writeMessageEnumExtensionAccessor(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, helper_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        try writer.writeAll("pub fn ");
        try writeQuotedIdentWithPrefix(helper_name, "getEnumExtensions_", writer);
        try writer.writeAll("(self: @This(), allocator: std.mem.Allocator) ![]");
        try writeEnumTypeReferenceWithContext(ctx, field.kind.enumeration, writer);
        try writer.writeAll(" {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const raw = try self.");
        try writeQuotedIdentWithPrefix(helper_name, "getExtension_", writer);
        try writer.writeAll("(allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("defer allocator.free(raw);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const out = try allocator.alloc(");
        try writeEnumTypeReferenceWithContext(ctx, field.kind.enumeration, writer);
        try writer.writeAll(", raw.len);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("errdefer allocator.free(out);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("for (raw, 0..) |value, i| out[i] = ");
        try writeEnumTypeReferenceWithContext(ctx, field.kind.enumeration, writer);
        try writer.writeAll(".fromInt(value) orelse return error.InvalidEnumValue;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return out;\n");
        try indent(writer, depth);
        try writer.writeAll("}\n\n");

        try indent(writer, depth);
        try writer.writeAll("pub fn ");
        try writeQuotedIdentWithPrefix(helper_name, "addEnumExtension_", writer);
        try writer.writeAll("(self: *@This(), allocator: std.mem.Allocator, value: ");
        try writeEnumTypeReferenceWithContext(ctx, field.kind.enumeration, writer);
        try writer.writeAll(") !void {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try self.");
        try writeQuotedIdentWithPrefix(helper_name, "addExtension_", writer);
        try writer.writeAll("(allocator, value.toInt());\n");
        try indent(writer, depth);
        try writer.writeAll("}\n\n");

        try indent(writer, depth);
        try writer.writeAll("pub fn ");
        try writeQuotedIdentWithPrefix(helper_name, "appendEnumExtensions_", writer);
        try writer.writeAll("(self: *@This(), allocator: std.mem.Allocator, values: []const ");
        try writeEnumTypeReferenceWithContext(ctx, field.kind.enumeration, writer);
        try writer.writeAll(") !void {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const raw = try allocator.alloc(i32, values.len);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("defer allocator.free(raw);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("for (values, 0..) |value, i| raw[i] = value.toInt();\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try self.");
        try writeQuotedIdentWithPrefix(helper_name, "appendExtension_", writer);
        try writer.writeAll("(allocator, raw);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n\n");

        try indent(writer, depth);
        try writer.writeAll("pub fn ");
        try writeQuotedIdentWithPrefix(helper_name, "replaceEnumExtensions_", writer);
        try writer.writeAll("(self: *@This(), allocator: std.mem.Allocator, values: []const ");
        try writeEnumTypeReferenceWithContext(ctx, field.kind.enumeration, writer);
        try writer.writeAll(") !void {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const raw = try allocator.alloc(i32, values.len);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("defer allocator.free(raw);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("for (values, 0..) |value, i| raw[i] = value.toInt();\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try self.");
        try writeQuotedIdentWithPrefix(helper_name, "replaceExtension_", writer);
        try writer.writeAll("(allocator, raw);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n\n");
        return;
    }

    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedIdentWithPrefix(helper_name, "getEnumExtension_", writer);
    try writer.writeAll("(self: @This(), allocator: std.mem.Allocator) !?");
    try writeEnumTypeReferenceWithContext(ctx, field.kind.enumeration, writer);
    try writer.writeAll(" {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const raw = (try self.");
    try writeQuotedIdentWithPrefix(helper_name, "getExtension_", writer);
    try writer.writeAll("(allocator)) orelse return null;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return ");
    try writeEnumTypeReferenceWithContext(ctx, field.kind.enumeration, writer);
    try writer.writeAll(".fromInt(raw);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedIdentWithPrefix(helper_name, "getEnumOrDefaultExtension_", writer);
    try writer.writeAll("(self: @This(), allocator: std.mem.Allocator) !");
    try writeEnumTypeReferenceWithContext(ctx, field.kind.enumeration, writer);
    try writer.writeAll(" {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return (try self.");
    try writeQuotedIdentWithPrefix(helper_name, "getEnumExtension_", writer);
    try writer.writeAll("(allocator)) orelse ");
    try writeEnumTypeReferenceWithContext(ctx, field.kind.enumeration, writer);
    try writer.writeAll(".fromInt(");
    try writeExtensionHelperReference(field, writer);
    try writer.writeAll(".default_value_zig) orelse unreachable;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedIdentWithPrefix(helper_name, "setEnumExtension_", writer);
    try writer.writeAll("(self: *@This(), allocator: std.mem.Allocator, value: ");
    try writeEnumTypeReferenceWithContext(ctx, field.kind.enumeration, writer);
    try writer.writeAll(") !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.");
    try writeQuotedIdentWithPrefix(helper_name, "setExtension_", writer);
    try writer.writeAll("(allocator, value.toInt());\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");
}

fn writeMessageExtensionTypedAccessor(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, helper_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    const type_name = switch (field.kind) {
        .message => |name| name,
        .group => |name| name,
        else => return,
    };
    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        try writer.writeAll("pub fn ");
        try writeQuotedIdentWithPrefix(helper_name, "addExtensionMessage_", writer);
        try writer.writeAll("(self: *@This(), allocator: std.mem.Allocator, value: ");
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
        try writer.writeAll(") !void {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const payload = try value.encode(allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("defer allocator.free(payload);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try ");
        try writeExtensionHelperReference(field, writer);
        try writer.writeAll(".appendToUnknown(self, allocator, payload);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n\n");

        try indent(writer, depth);
        try writer.writeAll("pub fn ");
        try writeQuotedIdentWithPrefix(helper_name, "appendExtensionMessages_", writer);
        try writer.writeAll("(self: *@This(), allocator: std.mem.Allocator, values: []const ");
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
        try writer.writeAll(") !void {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("for (values) |value| try self.");
        try writeQuotedIdentWithPrefix(helper_name, "addExtensionMessage_", writer);
        try writer.writeAll("(allocator, value);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n\n");

        try indent(writer, depth);
        try writer.writeAll("pub fn ");
        try writeQuotedIdentWithPrefix(helper_name, "replaceExtensionMessages_", writer);
        try writer.writeAll("(self: *@This(), allocator: std.mem.Allocator, values: []const ");
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
        try writer.writeAll(") !void {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try ");
        try writeExtensionHelperReference(field, writer);
        try writer.writeAll(".clearFromUnknown(self, allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try self.");
        try writeQuotedIdentWithPrefix(helper_name, "appendExtensionMessages_", writer);
        try writer.writeAll("(allocator, values);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n\n");

        try indent(writer, depth);
        try writer.writeAll("pub fn ");
        try writeQuotedIdentWithPrefix(helper_name, "getExtensionMessages_", writer);
        try writer.writeAll("(self: @This(), allocator: std.mem.Allocator) ![]");
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
        try writer.writeAll(" {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const payloads = try ");
        try writeExtensionHelperReference(field, writer);
        try writer.writeAll(".decodeAllFromUnknown(self, allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("defer allocator.free(payloads);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("var list: std.ArrayList(");
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
        try writer.writeAll(") = .empty;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("errdefer { for (list.items) |*item| item.deinit(allocator); list.deinit(allocator); }\n");
        try indent(writer, depth + 1);
        try writer.writeAll("for (payloads) |payload| try list.append(allocator, try ");
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
        try writer.writeAll(".decode(allocator, payload));\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return try list.toOwnedSlice(allocator);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n\n");
    } else {
        try indent(writer, depth);
        try writer.writeAll("pub fn ");
        try writeQuotedIdentWithPrefix(helper_name, "setExtensionMessage_", writer);
        try writer.writeAll("(self: *@This(), allocator: std.mem.Allocator, value: ");
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
        try writer.writeAll(") !void {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const payload = try value.encode(allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("defer allocator.free(payload);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try ");
        try writeExtensionHelperReference(field, writer);
        try writer.writeAll(".replaceInUnknown(self, allocator, payload);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n\n");

        try indent(writer, depth);
        try writer.writeAll("pub fn ");
        try writeQuotedIdentWithPrefix(helper_name, "getExtensionMessage_", writer);
        try writer.writeAll("(self: @This(), allocator: std.mem.Allocator) !");
        try writer.writeAll("?");
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
        try writer.writeAll(" {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const payload = (try ");
        try writeExtensionHelperReference(field, writer);
        try writer.writeAll(".decodeFirstFromUnknown(self, allocator)) orelse return null;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return try ");
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
        try writer.writeAll(".decode(allocator, payload);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n\n");
    }
}

fn writeMergeFrom(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("/// Merge other into self. String/bytes payloads, raw message payloads,\n");
    try indent(writer, depth);
    try writer.writeAll("/// and map keys/values are deep-copied, so other remains independently valid.\n");
    try indent(writer, depth);
    try writer.writeAll("pub fn mergeFrom(self: *@This(), allocator: std.mem.Allocator, other: @This()) anyerror!void {\n");
    if (mergeUsesOwnedAllocator(ctx, message)) {
        try indent(writer, depth + 1);
        try writer.writeAll("const _pbz_owned_allocator = try self._pbzOwnedAllocator(allocator);\n");
    }
    for (message.fields.items) |*field| {
        if (field.oneof_name == null) try writeMergeField(ctx, field, writer, depth + 1);
    }
    for (message.oneofs.items) |oneof| try writeMergeOneof(ctx, message, oneof, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("try pbz.wire.appendRawFieldsClone(allocator, &self._unknown_fields, other._unknown_fields);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn mergeUsesOwnedAllocator(ctx: *const CodegenContext, message: *const schema.MessageDescriptor) bool {
    for (message.fields.items) |*field| {
        if (field.oneof_name == null and mergeFieldUsesOwnedAllocator(ctx, field)) return true;
    }
    for (message.oneofs.items) |oneof| {
        for (message.fields.items) |*field| {
            if (field.oneof_name) |name| {
                if (std.mem.eql(u8, name, oneof.name) and mergeFieldUsesOwnedAllocator(ctx, field)) return true;
            }
        }
    }
    return false;
}

fn mergeFieldUsesOwnedAllocator(ctx: *const CodegenContext, field: *const schema.FieldDescriptor) bool {
    if (field.kind == .map) {
        const map_type = field.kind.map;
        if (map_type.key == .string) return true;
        const value_kind = map_type.value.*;
        if (value_kind == .scalar and (value_kind.scalar == .string or value_kind.scalar == .bytes)) return true;
        if ((value_kind == .message or value_kind == .group) and typedMapMessageValueWithContext(ctx, field) == null) return true;
        return false;
    }
    if (field.kind == .scalar and (field.kind.scalar == .string or field.kind.scalar == .bytes)) return true;
    if (field.kind == .message or field.kind == .group) {
        const typed = if (field.cardinality == .repeated)
            typedRepeatedMessageFieldWithContext(ctx, field)
        else if (field.oneof_name != null)
            typedOneofMessageFieldWithContext(ctx, field)
        else
            typedSingularMessageFieldWithContext(ctx, field);
        return typed == null;
    }
    return false;
}

fn writeMergeField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    if (field.kind == .map) return try writeMergeMapField(ctx, field, writer, depth);
    if (field.cardinality == .repeated) return try writeMergeRepeatedField(ctx, field, writer, depth);
    switch (field.kind) {
        .message, .group => try writeMergeSingularMessageField(ctx, field, writer, depth),
        .scalar => |scalar| try writeMergeSingularScalarField(file, field, scalar, writer, depth),
        .enumeration => try writeMergeSingularEnumField(file, field, writer, depth),
        else => {},
    }
}

fn writeMergeRepeatedField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const typed_message = typedRepeatedMessageFieldWithContext(ctx, field);
    const raw_message = typed_message == null and (field.kind == .message or field.kind == .group);
    const string_or_bytes = field.kind == .scalar and (field.kind.scalar == .string or field.kind.scalar == .bytes);
    const needs_dup = raw_message or string_or_bytes;
    try indent(writer, depth);
    try writer.writeAll("if (other.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".len != 0) {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const old = self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("{\n");
    try indent(writer, depth + 2);
    try writer.writeAll("const merged = try allocator.alloc(");
    if (typed_message) |type_name| {
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    } else {
        try writeRepeatedElementType(field.*, writer);
    }
    try writer.writeAll(", old.len + other.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".len);\n");
    try indent(writer, depth + 2);
    try writer.writeAll("errdefer allocator.free(merged);\n");
    try indent(writer, depth + 2);
    try writer.writeAll("@memcpy(merged[0..old.len], old);\n");
    if (typed_message != null) {
        try indent(writer, depth + 2);
        try writer.writeAll("var _pbz_cloned: usize = 0;\n");
        try indent(writer, depth + 2);
        try writer.writeAll("errdefer for (merged[old.len..old.len + _pbz_cloned]) |*item| item.deinit(allocator);\n");
        try indent(writer, depth + 2);
        try writer.writeAll("for (other.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(", 0..) |item, i| { merged[old.len + i] = try item.cloneOwned(allocator); _pbz_cloned += 1; }\n");
    } else if (needs_dup) {
        try indent(writer, depth + 2);
        try writer.writeAll("for (other.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(", 0..) |item, i| merged[old.len + i] = try pbz.wire.dupeBytes(_pbz_owned_allocator,item);\n");
    } else {
        try indent(writer, depth + 2);
        try writer.writeAll("@memcpy(merged[old.len..], other.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(");\n");
    }
    try indent(writer, depth + 2);
    try writer.writeAll("self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = merged;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (old.len != 0) allocator.free(old);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeMergeMapField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const map_type = switch (field.kind) {
        .map => |map| map,
        else => return,
    };
    const typed_message_value = typedMapMessageValueWithContext(ctx, field);
    const raw_message_value = typed_message_value == null and (map_type.value.* == .message or map_type.value.* == .group);
    const string_key = map_type.key == .string;
    const string_value = map_type.value.* == .scalar and (map_type.value.scalar == .string or map_type.value.scalar == .bytes);
    try indent(writer, depth);
    try writer.writeAll("const ");
    try writeQuotedIdentWithSuffix(field.name, "_other_count", writer);
    try writer.writeAll(" = other.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".count();\n");
    try indent(writer, depth);
    try writer.writeAll("if (");
    try writeQuotedIdentWithSuffix(field.name, "_other_count", writer);
    try writer.writeAll(" != 0) {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".ensureUnusedCapacity(allocator, ");
    try writeQuotedIdentWithSuffix(field.name, "_other_count", writer);
    try writer.writeAll(");\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var other_it = other.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".iterator();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("while (other_it.next()) |entry| {\n");
    if (string_key) {
        try indent(writer, depth + 2);
        try writer.writeAll("const key = try pbz.wire.dupeBytes(_pbz_owned_allocator,entry.key_ptr.*);\n");
    } else {
        try indent(writer, depth + 2);
        try writer.writeAll("const key = entry.key_ptr.*;\n");
    }
    if (typed_message_value) |_| {
        try indent(writer, depth + 2);
        try writer.writeAll("const value = try entry.value_ptr.cloneOwned(allocator);\n");
    } else if (string_value or raw_message_value) {
        try indent(writer, depth + 2);
        try writer.writeAll("const value = try pbz.wire.dupeBytes(_pbz_owned_allocator,entry.value_ptr.*);\n");
    } else {
        try indent(writer, depth + 2);
        try writer.writeAll("const value = entry.value_ptr.*;\n");
    }
    try indent(writer, depth + 2);
    try writer.writeAll("const result = self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".getOrPutAssumeCapacity(key);\n");
    if (typed_message_value != null) {
        try indent(writer, depth + 2);
        try writer.writeAll("if (result.found_existing) result.value_ptr.deinit(allocator);\n");
    }
    try indent(writer, depth + 2);
    try writer.writeAll("result.value_ptr.* = value;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeMergeSingularMessageField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (typedSingularMessageFieldWithContext(ctx, field)) |_| {
        try indent(writer, depth);
        try writer.writeAll("if (other.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(") |other_value| {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("if (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(") |*self_value| { try self_value.mergeFrom(allocator, other_value); } else { self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = try other_value.cloneOwned(allocator); }\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");
        return;
    }
    try indent(writer, depth);
    try writer.writeAll("if (other.");
    try writePresenceIdent(field.name, writer);
    try writer.writeAll(") {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (self.");
    try writePresenceIdent(field.name, writer);
    try writer.writeAll(" and self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".len != 0 and other.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".len != 0) {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("const owned_allocator = try self._pbzOwnedAllocator(allocator);\n");
    try indent(writer, depth + 2);
    try writer.writeAll("const merged = try owned_allocator.alloc(u8, self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".len + other.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".len);\n");
    try indent(writer, depth + 2);
    try writer.writeAll("@memcpy(merged[0..self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".len], self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(");\n");
    try indent(writer, depth + 2);
    try writer.writeAll("@memcpy(merged[self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".len..], other.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(");\n");
    try indent(writer, depth + 2);
    try writer.writeAll("self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = merged;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("} else if (!self.");
    try writePresenceIdent(field.name, writer);
    try writer.writeAll(" or self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".len == 0) {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = try pbz.wire.dupeBytes(_pbz_owned_allocator,other.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(");\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("self.");
    try writePresenceIdent(field.name, writer);
    try writer.writeAll(" = true;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeMergeSingularScalarField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
    const needs_dup = scalar == .string or scalar == .bytes;
    try indent(writer, depth);
    if (hasPresence(file, field.*)) {
        try writer.writeAll("if (other.");
        try writePresenceIdent(field.name, writer);
        try writer.writeAll(") { self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = ");
        if (needs_dup) {
            try writer.writeAll("try pbz.wire.dupeBytes(_pbz_owned_allocator,other.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(")");
        } else {
            try writer.writeAll("other.");
            try writeQuotedIdent(field.name, writer);
        }
        try writer.writeAll("; self.");
        try writePresenceIdent(field.name, writer);
        try writer.writeAll(" = true; }\n");
    } else {
        try writeScalarSkipCondition("other.", field.name, scalar, writer);
        try writer.writeAll("self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = ");
        if (needs_dup) {
            try writer.writeAll("try pbz.wire.dupeBytes(_pbz_owned_allocator,other.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(")");
        } else {
            try writer.writeAll("other.");
            try writeQuotedIdent(field.name, writer);
        }
        try writer.writeAll(";\n");
    }
}

fn writeMergeSingularEnumField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    if (hasPresence(file, field.*)) {
        try writer.writeAll("if (other.");
        try writePresenceIdent(field.name, writer);
        try writer.writeAll(") { self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = other.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll("; self.");
        try writePresenceIdent(field.name, writer);
        try writer.writeAll(" = true; }\n");
    } else {
        try writer.writeAll("if (other.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" != 0) self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = other.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(";\n");
    }
}

fn writeMergeOneof(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, oneof: schema.OneofDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("switch (other.");
    try writeQuotedIdent(oneof.name, writer);
    try writer.writeAll(") {\n");
    try indent(writer, depth + 1);
    try writer.writeAll(".none => {},\n");
    for (message.fields.items) |*field| {
        if (field.oneof_name) |name| {
            if (std.mem.eql(u8, name, oneof.name)) {
                try indent(writer, depth + 1);
                try writer.writeAll(".");
                try writeQuotedIdent(field.name, writer);
                if (typedOneofMessageFieldWithContext(ctx, field)) |_| {
                    try writer.writeAll(" => |value| { const owned_value = try value.cloneOwned(allocator); errdefer owned_value.deinit(allocator); ");
                    try writeOneofDeinitCall(oneof.name, writer);
                    try writer.writeAll(" self.");
                    try writeQuotedIdent(oneof.name, writer);
                    try writer.writeAll(" = .{ .");
                    try writeQuotedIdent(field.name, writer);
                    try writer.writeAll(" = owned_value }; },\n");
                } else if (field.kind == .message or field.kind == .group or (field.kind == .scalar and (field.kind.scalar == .string or field.kind.scalar == .bytes))) {
                    try writer.writeAll(" => |value| { const owned_value = try pbz.wire.dupeBytes(_pbz_owned_allocator,value); ");
                    try writeOneofDeinitCall(oneof.name, writer);
                    try writer.writeAll(" self.");
                    try writeQuotedIdent(oneof.name, writer);
                    try writer.writeAll(" = .{ .");
                    try writeQuotedIdent(field.name, writer);
                    try writer.writeAll(" = owned_value }; },\n");
                } else {
                    try writer.writeAll(" => |value| { ");
                    try writeOneofDeinitCall(oneof.name, writer);
                    try writer.writeAll(" self.");
                    try writeQuotedIdent(oneof.name, writer);
                    try writer.writeAll(" = .{ .");
                    try writeQuotedIdent(field.name, writer);
                    try writer.writeAll(" = value }; },\n");
                }
            }
        }
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeDeinit(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {\n");
    for (message.fields.items) |*field| {
        if (typedSingularMessageFieldWithContext(ctx, field)) |_| {
            try indent(writer, depth + 1);
            try writer.writeAll("if (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(") |*value| value.deinit(allocator);\n");
        } else if (typedRepeatedMessageFieldWithContext(ctx, field)) |_| {
            try indent(writer, depth + 1);
            try writer.writeAll("for (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(") |value| { var mutable = value; mutable.deinit(allocator); }\n");
            try indent(writer, depth + 1);
            try writer.writeAll("allocator.free(self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(");\n");
        } else if (field.kind == .map) {
            try indent(writer, depth + 1);
            try writer.writeAll("@This().");
            try writeQuotedIdentWithPrefix(field.name, "deinitMap_", writer);
            try writer.writeAll("(allocator, &self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(");\n");
        } else if (field.cardinality == .repeated) {
            try indent(writer, depth + 1);
            try writer.writeAll("allocator.free(self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(");\n");
        }
    }
    for (message.oneofs.items) |oneof| {
        if (!oneofHasTypedMessageWithContext(ctx, message, oneof.name)) continue;
        try indent(writer, depth + 1);
        try writeOneofDeinitCall(oneof.name, writer);
        try writer.writeAll("\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("pbz.wire.freeRawFields(allocator, self._unknown_fields);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (self._json_arena) |arena| { const child_allocator = arena.child_allocator; arena.deinit(); child_allocator.destroy(arena); }\n");
    try indent(writer, depth + 1);
    try writer.writeAll("self.* = undefined;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeClear(writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("/// Release owned storage and reset to the protobuf default value.\n");
    try indent(writer, depth);
    try writer.writeAll("pub fn clear(self: *@This(), allocator: std.mem.Allocator) void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("self.deinit(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("self.* = @This().init();\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeCloneOwned(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn cloneOwned(self: @This(), allocator: std.mem.Allocator) anyerror!@This() {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var out = @This().init();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer out.deinit(allocator);\n");
    if (cloneUsesOwnedAllocator(ctx, message)) {
        try indent(writer, depth + 1);
        try writer.writeAll("const owned_allocator = try out._pbzOwnedAllocator(allocator);\n");
    }
    for (message.fields.items) |*field| {
        if (field.oneof_name == null) try writeCloneField(ctx, field, writer, depth + 1);
    }
    for (message.oneofs.items) |oneof| try writeCloneOneof(ctx, message, oneof, writer, depth + 1);
    try writeCloneUnknownFields(writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("return out;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn cloneUsesOwnedAllocator(ctx: *const CodegenContext, message: *const schema.MessageDescriptor) bool {
    for (message.fields.items) |*field| {
        if (field.oneof_name == null and cloneFieldUsesOwnedAllocator(ctx, field)) return true;
    }
    for (message.oneofs.items) |oneof| {
        for (message.fields.items) |*field| {
            if (field.oneof_name) |name| {
                if (std.mem.eql(u8, name, oneof.name) and cloneFieldUsesOwnedAllocator(ctx, field)) return true;
            }
        }
    }
    return false;
}

fn cloneFieldUsesOwnedAllocator(ctx: *const CodegenContext, field: *const schema.FieldDescriptor) bool {
    if (field.kind == .map) {
        const map_type = field.kind.map;
        return cloneKindUsesOwnedAllocator(.{ .scalar = map_type.key }) or
            (typedMapMessageValueWithContext(ctx, field) == null and cloneKindUsesOwnedAllocator(map_type.value.*));
    }
    if (typedSingularMessageFieldWithContext(ctx, field) != null) return false;
    if (typedRepeatedMessageFieldWithContext(ctx, field) != null) return false;
    if (typedOneofMessageFieldWithContext(ctx, field) != null) return false;
    return cloneKindUsesOwnedAllocator(field.kind);
}

fn cloneKindUsesOwnedAllocator(kind: schema.FieldKind) bool {
    return switch (kind) {
        .scalar => |scalar| scalar == .string or scalar == .bytes,
        .message, .group => true,
        else => false,
    };
}

fn writeCloneField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    if (field.kind == .map) return try writeCloneMapField(ctx, field, writer, depth);
    if (field.cardinality == .repeated) return try writeCloneRepeatedField(ctx, field, writer, depth);
    if (typedSingularMessageFieldWithContext(ctx, field)) |_| {
        try indent(writer, depth);
        try writer.writeAll("if (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(") |value| out.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = try value.cloneOwned(allocator);\n");
        return;
    }
    try indent(writer, depth);
    try writer.writeAll("out.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = ");
    try writeCloneFieldValueExpr(field.kind, field.name, writer);
    try writer.writeAll(";\n");
    if (hasPresence(file, field.*)) {
        try indent(writer, depth);
        try writer.writeAll("out.");
        try writePresenceIdent(field.name, writer);
        try writer.writeAll(" = self.");
        try writePresenceIdent(field.name, writer);
        try writer.writeAll(";\n");
    }
}

fn writeCloneRepeatedField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("if (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".len != 0) {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const cloned = try allocator.alloc(");
    if (typedRepeatedMessageFieldWithContext(ctx, field)) |type_name| {
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    } else {
        try writeRepeatedElementType(field.*, writer);
    }
    try writer.writeAll(", self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".len);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("for (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(", 0..) |item, i| cloned[i] = ");
    if (typedRepeatedMessageFieldWithContext(ctx, field)) |_| {
        try writer.writeAll("try item.cloneOwned(allocator)");
    } else {
        try writeCloneValueExpr(field.kind, "item", writer);
    }
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("out.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = cloned;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeCloneMapField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const map_type = switch (field.kind) {
        .map => |map| map,
        else => return,
    };
    try indent(writer, depth);
    try writer.writeAll("if (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".count() != 0) {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try out.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".ensureUnusedCapacity(allocator, self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".count());\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var map_it = self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".iterator();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("while (map_it.next()) |entry| out.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".putAssumeCapacityNoClobber(");
    try writeCloneValueExpr(.{ .scalar = map_type.key }, "entry.key_ptr.*", writer);
    try writer.writeAll(", ");
    if (typedMapMessageValueWithContext(ctx, field)) |_| {
        try writer.writeAll("try entry.value_ptr.cloneOwned(allocator)");
    } else {
        try writeCloneValueExpr(map_type.value.*, "entry.value_ptr.*", writer);
    }
    try writer.writeAll(");\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeCloneOneof(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, oneof: schema.OneofDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("out.");
    try writeQuotedIdent(oneof.name, writer);
    try writer.writeAll(" = switch (self.");
    try writeQuotedIdent(oneof.name, writer);
    try writer.writeAll(") {\n");
    try indent(writer, depth + 1);
    try writer.writeAll(".none => .none,\n");
    for (message.fields.items) |*field| {
        if (field.oneof_name) |name| {
            if (!std.mem.eql(u8, name, oneof.name)) continue;
            try indent(writer, depth + 1);
            try writer.writeAll(".");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(" => |value| .{ .");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(" = ");
            if (typedOneofMessageFieldWithContext(ctx, field)) |_| {
                try writer.writeAll("try value.cloneOwned(allocator)");
            } else {
                try writeCloneValueExpr(field.kind, "value", writer);
            }
            try writer.writeAll(" },\n");
        }
    }
    try indent(writer, depth);
    try writer.writeAll("};\n");
}

fn writeCloneUnknownFields(writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("out._unknown_fields = try pbz.wire.cloneRawFields(allocator, self._unknown_fields);\n");
}

fn writeAdoptOwned(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("/// Take ownership of borrowed string/bytes payloads after decode.\n");
    try indent(writer, depth);
    try writer.writeAll("/// Owned payloads, including nested message payloads, live in this message's arena.\n");
    try indent(writer, depth);
    try writer.writeAll("pub fn adoptOwned(self: *@This(), allocator: std.mem.Allocator) anyerror!void {\n");
    if (adoptHasWork(ctx, message)) {
        try indent(writer, depth + 1);
        try writer.writeAll("const _pbz_owned_allocator = try self._pbzOwnedAllocator(allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try self.adoptOwnedInto(allocator, _pbz_owned_allocator);\n");
    } else {
        try indent(writer, depth + 1);
        try writer.writeAll("_ = self;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("_ = allocator;\n");
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");
    try indent(writer, depth);
    try writer.writeAll("pub fn adoptOwnedInto(self: *@This(), allocator: std.mem.Allocator, _pbz_owned_allocator: std.mem.Allocator) anyerror!void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("_ = &self;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("_ = &allocator;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("_ = &_pbz_owned_allocator;\n");
    if (mergeUsesOwnedAllocator(ctx, message)) {
        try indent(writer, depth + 1);
        try writer.writeAll("var _pbz_owned_total: usize = 0;\n");
        for (message.fields.items) |*field| {
            if (field.oneof_name == null) try writeAdoptTotalField(ctx, field, writer, depth + 1);
        }
        for (message.oneofs.items) |oneof| try writeAdoptTotalOneof(ctx, message, oneof, writer, depth + 1);
        try indent(writer, depth + 1);
        try writer.writeAll("var _pbz_owned_block = pbz.wire.OwnedBlock.init(if (_pbz_owned_total == 0) &.{} else try _pbz_owned_allocator.alloc(u8, _pbz_owned_total));\n");
    }
    for (message.fields.items) |*field| {
        if (field.oneof_name == null) try writeAdoptField(ctx, field, writer, depth + 1, "_pbz_owned_allocator");
    }
    for (message.oneofs.items) |oneof| try writeAdoptOneof(ctx, message, oneof, writer, depth + 1, "_pbz_owned_allocator");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn adoptIntoUsesAllocator(ctx: *const CodegenContext, message: *const schema.MessageDescriptor) bool {
    for (message.fields.items) |*field| {
        if (field.oneof_name != null) continue;
        if (field.kind == .map) {
            const map_type = field.kind.map;
            if (map_type.key == .string) return true;
            if (typedMapMessageValueWithContext(ctx, field) != null) return true;
            continue;
        }
        if (field.cardinality == .repeated) {
            if (typedRepeatedMessageFieldWithContext(ctx, field) != null) return true;
            continue;
        }
        if (typedSingularMessageFieldWithContext(ctx, field) != null) return true;
    }
    for (message.oneofs.items) |oneof| {
        for (message.fields.items) |*field| {
            if (field.oneof_name) |name| {
                if (std.mem.eql(u8, name, oneof.name) and typedOneofMessageFieldWithContext(ctx, field) != null) return true;
            }
        }
    }
    return false;
}

fn writeAdoptTotalField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    if (field.kind == .map) return try writeAdoptTotalMapField(ctx, field, writer, depth);
    if (field.cardinality == .repeated) return try writeAdoptTotalRepeatedField(ctx, field, writer, depth);
    if (typedSingularMessageFieldWithContext(ctx, field)) |_| return;
    switch (field.kind) {
        .message, .group => {
            try indent(writer, depth);
            if (hasPresence(file, field.*)) {
                try writer.writeAll("if (self.");
                try writePresenceIdent(field.name, writer);
                try writer.writeAll(") _pbz_owned_total += self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(".len;\n");
            } else {
                try writer.writeAll("_pbz_owned_total += self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(".len;\n");
            }
        },
        .scalar => |scalar| {
            if (scalar != .string and scalar != .bytes) return;
            try indent(writer, depth);
            if (hasPresence(file, field.*)) {
                try writer.writeAll("if (self.");
                try writePresenceIdent(field.name, writer);
                try writer.writeAll(") _pbz_owned_total += self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(".len;\n");
            } else {
                try writer.writeAll("_pbz_owned_total += self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(".len;\n");
            }
        },
        else => {},
    }
}

fn writeAdoptTotalRepeatedField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (typedRepeatedMessageFieldWithContext(ctx, field)) |_| return;
    const raw_message = field.kind == .message or field.kind == .group;
    const string_or_bytes = field.kind == .scalar and (field.kind.scalar == .string or field.kind.scalar == .bytes);
    if (!raw_message and !string_or_bytes) return;
    try indent(writer, depth);
    try writer.writeAll("for (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(") |item| _pbz_owned_total += item.len;\n");
}

fn writeAdoptTotalMapField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const map_type = switch (field.kind) {
        .map => |map| map,
        else => return,
    };
    const typed_message_value = typedMapMessageValueWithContext(ctx, field);
    const raw_message_value = typed_message_value == null and (map_type.value.* == .message or map_type.value.* == .group);
    const string_key = map_type.key == .string;
    const string_value = map_type.value.* == .scalar and (map_type.value.scalar == .string or map_type.value.scalar == .bytes);
    if (!string_key and !string_value and !raw_message_value) return;
    try indent(writer, depth);
    try writer.writeAll("var ");
    try writeQuotedIdentWithSuffix(field.name, "_owned_total_it", writer);
    try writer.writeAll(" = self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".iterator();\n");
    try indent(writer, depth);
    try writer.writeAll("while (");
    try writeQuotedIdentWithSuffix(field.name, "_owned_total_it", writer);
    try writer.writeAll(".next()) |entry| {\n");
    if (string_key) {
        try indent(writer, depth + 1);
        try writer.writeAll("_pbz_owned_total += entry.key_ptr.*.len;\n");
    }
    if (string_value or raw_message_value) {
        try indent(writer, depth + 1);
        try writer.writeAll("_pbz_owned_total += entry.value_ptr.*.len;\n");
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeAdoptTotalOneof(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, oneof: schema.OneofDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    var any = false;
    for (message.fields.items) |*field| {
        if (field.oneof_name) |name| {
            if (!std.mem.eql(u8, name, oneof.name)) continue;
            if (typedOneofMessageFieldWithContext(ctx, field) != null) continue;
            if (field.kind == .message or field.kind == .group or (field.kind == .scalar and (field.kind.scalar == .string or field.kind.scalar == .bytes))) {
                any = true;
            }
        }
    }
    if (!any) return;
    try indent(writer, depth);
    try writer.writeAll("switch (self.");
    try writeQuotedIdent(oneof.name, writer);
    try writer.writeAll(") {\n");
    for (message.fields.items) |*field| {
        if (field.oneof_name) |name| {
            if (!std.mem.eql(u8, name, oneof.name)) continue;
            if (typedOneofMessageFieldWithContext(ctx, field) != null) continue;
            if (field.kind == .message or field.kind == .group or (field.kind == .scalar and (field.kind.scalar == .string or field.kind.scalar == .bytes))) {
                try indent(writer, depth + 1);
                try writer.writeAll(".");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(" => |value| _pbz_owned_total += value.len,\n");
            }
        }
    }
    try indent(writer, depth + 1);
    try writer.writeAll("else => {},\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn adoptHasWork(ctx: *const CodegenContext, message: *const schema.MessageDescriptor) bool {
    if (mergeUsesOwnedAllocator(ctx, message)) return true;
    for (message.fields.items) |*field| {
        if (field.oneof_name != null) continue;
        if (typedSingularMessageFieldWithContext(ctx, field) != null) return true;
        if (field.cardinality == .repeated and typedRepeatedMessageFieldWithContext(ctx, field) != null) return true;
    }
    for (message.oneofs.items) |oneof| {
        for (message.fields.items) |*field| {
            if (field.oneof_name) |name| {
                if (std.mem.eql(u8, name, oneof.name) and typedOneofMessageFieldWithContext(ctx, field) != null) return true;
            }
        }
    }
    return false;
}

fn writeAdoptField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize, nested_allocator: []const u8) Error!void {
    const file = ctx.file;
    if (field.kind == .map) return try writeAdoptMapField(ctx, field, writer, depth, nested_allocator);
    if (field.cardinality == .repeated) return try writeAdoptRepeatedField(ctx, field, writer, depth, nested_allocator);
    if (typedSingularMessageFieldWithContext(ctx, field)) |_| {
        try indent(writer, depth);
        try writer.writeAll("if (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(") |*value| try value.adoptOwnedInto(allocator, ");
        try writer.writeAll(nested_allocator);
        try writer.writeAll(");\n");
        return;
    }
    switch (field.kind) {
        .message, .group => {
            try indent(writer, depth);
            if (hasPresence(file, field.*)) {
                try writer.writeAll("if (self.");
                try writePresenceIdent(field.name, writer);
                try writer.writeAll(") self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(" = _pbz_owned_block.take(self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(");\n");
            } else {
                try writer.writeAll("if (self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(".len != 0) self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(" = _pbz_owned_block.take(self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(");\n");
            }
        },
        .scalar => |scalar| {
            if (scalar != .string and scalar != .bytes) return;
            try indent(writer, depth);
            if (hasPresence(file, field.*)) {
                try writer.writeAll("if (self.");
                try writePresenceIdent(field.name, writer);
                try writer.writeAll(") self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(" = _pbz_owned_block.take(self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(");\n");
            } else {
                try writer.writeAll("if (self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(".len != 0) self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(" = _pbz_owned_block.take(self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(");\n");
            }
        },
        else => {},
    }
}

fn writeAdoptRepeatedField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize, nested_allocator: []const u8) Error!void {
    if (typedRepeatedMessageFieldWithContext(ctx, field)) |_| {
        try indent(writer, depth);
        try writer.writeAll("for (@constCast(self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(")) |*item| try item.adoptOwnedInto(allocator, ");
        try writer.writeAll(nested_allocator);
        try writer.writeAll(");\n");
        return;
    }
    const raw_message = field.kind == .message or field.kind == .group;
    const string_or_bytes = field.kind == .scalar and (field.kind.scalar == .string or field.kind.scalar == .bytes);
    if (!raw_message and !string_or_bytes) return;
    try indent(writer, depth);
    try writer.writeAll("for (@constCast(self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(")) |*item| item.* = _pbz_owned_block.take(item.*);\n");
}

fn writeAdoptMapField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize, nested_allocator: []const u8) Error!void {
    const map_type = switch (field.kind) {
        .map => |map| map,
        else => return,
    };
    const typed_message_value = typedMapMessageValueWithContext(ctx, field);
    const raw_message_value = typed_message_value == null and (map_type.value.* == .message or map_type.value.* == .group);
    const string_key = map_type.key == .string;
    const string_value = map_type.value.* == .scalar and (map_type.value.scalar == .string or map_type.value.scalar == .bytes);
    if (!string_key) {
        if (typed_message_value == null and !string_value and !raw_message_value) return;
        try indent(writer, depth);
        try writer.writeAll("var ");
        try writeQuotedIdentWithSuffix(field.name, "_map_it", writer);
        try writer.writeAll(" = self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(".iterator();\n");
        try indent(writer, depth);
        try writer.writeAll("while (");
        try writeQuotedIdentWithSuffix(field.name, "_map_it", writer);
        try writer.writeAll(".next()) |entry| {\n");
        if (typed_message_value != null) {
            try indent(writer, depth + 1);
            try writer.writeAll("try entry.value_ptr.adoptOwnedInto(allocator, ");
            try writer.writeAll(nested_allocator);
            try writer.writeAll(");\n");
        } else {
            try indent(writer, depth + 1);
            try writer.writeAll("entry.value_ptr.* = _pbz_owned_block.take(entry.value_ptr.*);\n");
        }
        try indent(writer, depth);
        try writer.writeAll("}\n");
        return;
    }

    try indent(writer, depth);
    try writer.writeAll("if (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".count() != 0) {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var ");
    try writeQuotedIdentWithSuffix(field.name, "_owned_map", writer);
    try writer.writeAll(" = ");
    try writeQuotedIdentWithSuffix(field.name, "Map", writer);
    try writer.writeAll(".empty;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer ");
    try writeQuotedIdentWithSuffix(field.name, "_owned_map", writer);
    try writer.writeAll(".deinit(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try ");
    try writeQuotedIdentWithSuffix(field.name, "_owned_map", writer);
    try writer.writeAll(".ensureUnusedCapacity(allocator, self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".count());\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var ");
    try writeQuotedIdentWithSuffix(field.name, "_map_it", writer);
    try writer.writeAll(" = self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".iterator();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("while (");
    try writeQuotedIdentWithSuffix(field.name, "_map_it", writer);
    try writer.writeAll(".next()) |entry| {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("const key = _pbz_owned_block.take(entry.key_ptr.*);\n");
    if (typed_message_value != null) {
        try indent(writer, depth + 2);
        try writer.writeAll("try entry.value_ptr.adoptOwnedInto(allocator, ");
            try writer.writeAll(nested_allocator);
            try writer.writeAll(");\n");
        try indent(writer, depth + 2);
        try writeQuotedIdentWithSuffix(field.name, "_owned_map", writer);
        try writer.writeAll(".putAssumeCapacityNoClobber(key, entry.value_ptr.*);\n");
    } else if (string_value or raw_message_value) {
        try indent(writer, depth + 2);
        try writer.writeAll("const value = _pbz_owned_block.take(entry.value_ptr.*);\n");
        try indent(writer, depth + 2);
        try writeQuotedIdentWithSuffix(field.name, "_owned_map", writer);
        try writer.writeAll(".putAssumeCapacityNoClobber(key, value);\n");
    } else {
        try indent(writer, depth + 2);
        try writeQuotedIdentWithSuffix(field.name, "_owned_map", writer);
        try writer.writeAll(".putAssumeCapacityNoClobber(key, entry.value_ptr.*);\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".deinit(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = ");
    try writeQuotedIdentWithSuffix(field.name, "_owned_map", writer);
    try writer.writeAll(";\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeAdoptOneof(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, oneof: schema.OneofDescriptor, writer: *std.Io.Writer, depth: usize, nested_allocator: []const u8) Error!void {
    var any = false;
    for (message.fields.items) |*field| {
        if (field.oneof_name) |name| {
            if (!std.mem.eql(u8, name, oneof.name)) continue;
            if (typedOneofMessageFieldWithContext(ctx, field) != null) {
                any = true;
            } else if (field.kind == .message or field.kind == .group or (field.kind == .scalar and (field.kind.scalar == .string or field.kind.scalar == .bytes))) {
                any = true;
            }
        }
    }
    if (!any) return;
    try indent(writer, depth);
    try writer.writeAll("switch (self.");
    try writeQuotedIdent(oneof.name, writer);
    try writer.writeAll(") {\n");
    for (message.fields.items) |*field| {
        if (field.oneof_name) |name| {
            if (!std.mem.eql(u8, name, oneof.name)) continue;
            if (typedOneofMessageFieldWithContext(ctx, field) != null) {
                try indent(writer, depth + 1);
                try writer.writeAll(".");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(" => |*value| try value.adoptOwnedInto(allocator, ");
                try writer.writeAll(nested_allocator);
                try writer.writeAll("),\n");
            } else if (field.kind == .message or field.kind == .group or (field.kind == .scalar and (field.kind.scalar == .string or field.kind.scalar == .bytes))) {
                try indent(writer, depth + 1);
                try writer.writeAll(".");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(" => |value| self.");
                try writeQuotedIdent(oneof.name, writer);
                try writer.writeAll(" = .{ .");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(" = _pbz_owned_block.take(value) },\n");
            }
        }
    }
    try indent(writer, depth + 1);
    try writer.writeAll("else => {},\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeCloneFieldValueExpr(kind: schema.FieldKind, field_name: []const u8, writer: *std.Io.Writer) Error!void {
    switch (kind) {
        .scalar => |scalar| switch (scalar) {
            .string, .bytes => {
                try writer.writeAll("try owned_allocator.dupe(u8, self.");
                try writeQuotedIdent(field_name, writer);
                try writer.writeAll(")");
            },
            else => {
                try writer.writeAll("self.");
                try writeQuotedIdent(field_name, writer);
            },
        },
        .message, .group => {
            try writer.writeAll("try owned_allocator.dupe(u8, self.");
            try writeQuotedIdent(field_name, writer);
            try writer.writeAll(")");
        },
        .enumeration => {
            try writer.writeAll("self.");
            try writeQuotedIdent(field_name, writer);
        },
        .map => unreachable,
    }
}

fn writeCloneValueExpr(kind: schema.FieldKind, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    switch (kind) {
        .scalar => |scalar| switch (scalar) {
            .string, .bytes => try writer.print("try owned_allocator.dupe(u8, {s})", .{value_expr}),
            else => try writer.writeAll(value_expr),
        },
        .message, .group => try writer.print("try pbz.wire.dupeBytes(owned_allocator, {s})", .{value_expr}),
        .enumeration => try writer.writeAll(value_expr),
        .map => try writer.writeAll(value_expr),
    }
}

fn writeMissingRequiredFieldName(message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn missingRequiredFieldName(self: @This()) ?[]const u8 {\n");
    var has_required = false;
    for (message.fields.items) |*field| {
        if (isRequired(field.*)) {
            has_required = true;
            try indent(writer, depth + 1);
            try writer.writeAll("if (!self.");
            try writePresenceIdent(field.name, writer);
            try writer.writeAll(") return ");
            try writeZigStringLiteral(field.name, writer);
            try writer.writeAll(";\n");
        }
    }
    if (!has_required) {
        try indent(writer, depth + 1);
        try writer.writeAll("_ = &self;\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("return null;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeMissingRequiredFieldPath(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn missingRequiredFieldPath(self: @This(), allocator: std.mem.Allocator) anyerror!?[]u8 {\n");
    var uses_allocator = false;
    for (message.fields.items) |*field| {
        if (isRequired(field.*)) {
            uses_allocator = true;
            try indent(writer, depth + 1);
            try writer.writeAll("if (!self.");
            try writePresenceIdent(field.name, writer);
            try writer.writeAll(") return try allocator.dupe(u8, ");
            try writeZigStringLiteral(field.name, writer);
            try writer.writeAll(");\n");
        }
    }
    for (message.fields.items) |*field| {
        if (field.kind == .message or field.kind == .group or fieldHasMessageMapValue(field)) {
            if (try writeMissingRequiredPathField(ctx, field, writer, depth + 1)) uses_allocator = true;
        }
    }
    for (message.oneofs.items) |oneof| {
        if (oneofHasMessageField(message, oneof.name)) {
            uses_allocator = true;
            try writeMissingRequiredPathOneof(ctx, message, oneof, writer, depth + 1);
        }
    }
    if (try writeMissingRequiredPathExtensionPayloads(ctx, message, writer, depth + 1)) uses_allocator = true;
    if (!uses_allocator) {
        try indent(writer, depth + 1);
        try writer.writeAll("_ = &self; _ = &allocator;\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("return null;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeMissingRequiredPathExtensionPayloads(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!bool {
    const file = ctx.file;
    var wrote_any = false;
    for (file.extensions.items) |*field| {
        if (try writeMissingRequiredPathExtensionPayload(ctx, message, field, writer, depth)) wrote_any = true;
    }
    for (file.messages.items) |*scope| {
        if (try writeMissingRequiredPathScopedExtensionPayloads(ctx, message, scope, writer, depth)) wrote_any = true;
    }
    return wrote_any;
}

fn writeMissingRequiredPathScopedExtensionPayloads(ctx: *const CodegenContext, target: *const schema.MessageDescriptor, scope: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!bool {
    var wrote_any = false;
    for (scope.extensions.items) |*field| {
        if (try writeMissingRequiredPathExtensionPayload(ctx, target, field, writer, depth)) wrote_any = true;
    }
    for (scope.messages.items) |*nested| {
        if (try writeMissingRequiredPathScopedExtensionPayloads(ctx, target, nested, writer, depth)) wrote_any = true;
    }
    return wrote_any;
}

fn writeMissingRequiredPathExtensionPayload(ctx: *const CodegenContext, target: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!bool {
    const file = ctx.file;
    if (!extensionAppliesToMessage(file, target, field)) return false;
    const type_name = switch (field.kind) {
        .message => |name| name,
        .group => |name| name,
        else => return false,
    };
    if (!codegenCanReferenceMessageWithContext(ctx, type_name)) return false;

    try indent(writer, depth);
    try writer.writeAll("{\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const payloads = try ");
    try writeExtensionHelperReference(field, writer);
    try writer.writeAll(".decodeAllFromUnknown(self, allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("defer allocator.free(payloads);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("for (payloads) |payload| {\n");
    try writeMissingRequiredPathPayload(ctx, type_name, field.name, "payload", writer, depth + 2);
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
    return true;
}

fn writeMissingRequiredPathField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!bool {
    if (field.kind == .map) return try writeMissingRequiredPathMapField(ctx, field, writer, depth);
    const type_name = switch (field.kind) {
        .message => |name| name,
        .group => |name| name,
        else => return false,
    };
    if (!codegenCanReferenceMessageWithContext(ctx, type_name)) return false;
    if (field.oneof_name != null) return false;
    if (field.cardinality == .repeated) {
        if (typedRepeatedMessageFieldWithContext(ctx, field)) |_| {
            try indent(writer, depth);
            try writer.writeAll("for (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(") |_pbz_nested| {\n");
            try indent(writer, depth + 1);
            try writer.writeAll("if (try _pbz_nested.missingRequiredFieldPath(allocator)) |suffix| { defer allocator.free(suffix); return try std.fmt.allocPrint(allocator, \"");
            try writeEscapedStringContents(field.name, writer);
            try writer.writeAll(".{s}\", .{suffix}); }\n");
            try indent(writer, depth);
            try writer.writeAll("}\n");
        } else {
            try indent(writer, depth);
            try writer.writeAll("for (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(") |payload| {\n");
            try writeMissingRequiredPathPayload(ctx, type_name, field.name, "payload", writer, depth + 1);
            try indent(writer, depth);
            try writer.writeAll("}\n");
        }
    } else {
        if (typedSingularMessageFieldWithContext(ctx, field)) |_| {
            try indent(writer, depth);
            try writer.writeAll("if (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(") |_pbz_nested| {\n");
            try indent(writer, depth + 1);
            try writer.writeAll("if (try _pbz_nested.missingRequiredFieldPath(allocator)) |suffix| { defer allocator.free(suffix); return try std.fmt.allocPrint(allocator, \"");
            try writeEscapedStringContents(field.name, writer);
            try writer.writeAll(".{s}\", .{suffix}); }\n");
            try indent(writer, depth);
            try writer.writeAll("}\n");
            return true;
        }
        try indent(writer, depth);
        try writer.writeAll("if (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(".len != 0) {\n");
        try writeMissingRequiredPathPayload(ctx, type_name, field.name, "self.", writer, depth + 1);
        try indent(writer, depth);
        try writer.writeAll("}\n");
    }
    return true;
}

fn writeMissingRequiredPathMapField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!bool {
    const map_type = switch (field.kind) {
        .map => |map_type| map_type,
        else => return false,
    };
    const type_name = switch (map_type.value.*) {
        .message => |name| name,
        else => return false,
    };
    if (!codegenCanReferenceMessageWithContext(ctx, type_name)) return false;
    try indent(writer, depth);
    try writer.writeAll("{ var map_it = self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".iterator(); while (map_it.next()) |entry| {\n");
    if (typedMapMessageValueWithContext(ctx, field)) |_| {
        try indent(writer, depth + 1);
        try writer.writeAll("if (try entry.value_ptr.missingRequiredFieldPath(allocator)) |suffix| { defer allocator.free(suffix); return try std.fmt.allocPrint(allocator, \"");
        try writeEscapedStringContents(field.name, writer);
        try writer.writeAll(".{s}\", .{suffix}); }\n");
    } else {
        try writeMissingRequiredPathPayload(ctx, type_name, field.name, "entry.value_ptr.*", writer, depth + 1);
    }
    try indent(writer, depth);
    try writer.writeAll("} }\n");
    return true;
}

fn writeMissingRequiredPathOneof(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, oneof: schema.OneofDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("switch (self.");
    try writeQuotedIdent(oneof.name, writer);
    try writer.writeAll(") {\n");
    try indent(writer, depth + 1);
    try writer.writeAll(".none => {},\n");
    for (message.fields.items) |*field| {
        if (field.oneof_name) |name| {
            const type_name = switch (field.kind) {
                .message => |message_name| message_name,
                .group => |group_name| group_name,
                else => continue,
            };
            if (std.mem.eql(u8, name, oneof.name) and codegenCanReferenceMessageWithContext(ctx, type_name)) {
                try indent(writer, depth + 1);
                try writer.writeAll(".");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(" => |");
                if (typedOneofMessageFieldWithContext(ctx, field)) |_| {
                    try writer.writeAll("_pbz_nested| {\n");
                    try indent(writer, depth + 2);
                    try writer.writeAll("if (try _pbz_nested.missingRequiredFieldPath(allocator)) |suffix| { defer allocator.free(suffix); return try std.fmt.allocPrint(allocator, \"");
                    try writeEscapedStringContents(field.name, writer);
                    try writer.writeAll(".{s}\", .{suffix}); }\n");
                } else {
                    try writer.writeAll("payload| {\n");
                    try writeMissingRequiredPathPayload(ctx, type_name, field.name, "payload", writer, depth + 2);
                }
                try indent(writer, depth + 1);
                try writer.writeAll("},\n");
            }
        }
    }
    try indent(writer, depth + 1);
    try writer.writeAll("else => {},\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeMissingRequiredPathPayload(ctx: *const CodegenContext, type_name: []const u8, field_name: []const u8, payload_expr: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("var _pbz_nested = try ");
    try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    try writer.writeAll(".decode(allocator, ");
    try writer.writeAll(payload_expr);
    if (std.mem.eql(u8, payload_expr, "self.")) try writeQuotedIdent(field_name, writer);
    try writer.writeAll(");\n");
    try indent(writer, depth);
    try writer.writeAll("defer _pbz_nested.deinit(allocator);\n");
    try indent(writer, depth);
    try writer.writeAll("if (try _pbz_nested.missingRequiredFieldPath(allocator)) |suffix| {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("defer allocator.free(suffix);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try std.fmt.allocPrint(allocator, \"");
    try writeEscapedStringContents(field_name, writer);
    try writer.writeAll(".{s}\", .{suffix});\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeValidateRequired(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn validateRequired(self: @This()) !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (self.missingRequiredFieldName() != null) return error.MissingRequiredField;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try writer.writeAll("\n");
    try indent(writer, depth);
    try writer.writeAll("pub fn validateRequiredRecursive(self: @This(), allocator: std.mem.Allocator) anyerror!void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.validateRequired();\n");
    var uses_allocator = false;
    for (message.fields.items) |*field| {
        if (field.kind == .message or field.kind == .group or fieldHasMessageMapValue(field)) {
            uses_allocator = true;
            try writeValidateMessagePayloadField(ctx, field, writer, depth + 1);
        }
    }
    for (message.oneofs.items) |oneof| {
        if (oneofHasMessageField(message, oneof.name)) {
            uses_allocator = true;
            try writeValidateMessagePayloadOneof(ctx, message, oneof, writer, depth + 1);
        }
    }
    if (try writeValidateMessageExtensionPayloads(ctx, message, writer, depth + 1)) uses_allocator = true;
    if (!uses_allocator) {
        try indent(writer, depth + 1);
        try writer.writeAll("_ = &allocator;\n");
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeValidateMessageExtensionPayloads(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!bool {
    const file = ctx.file;
    var wrote_any = false;
    for (file.extensions.items) |*field| {
        if (try writeValidateMessageExtensionPayload(ctx, message, field, writer, depth)) wrote_any = true;
    }
    for (file.messages.items) |*scope| {
        if (try writeValidateScopedMessageExtensionPayloads(ctx, message, scope, writer, depth)) wrote_any = true;
    }
    return wrote_any;
}

fn writeValidateScopedMessageExtensionPayloads(ctx: *const CodegenContext, target: *const schema.MessageDescriptor, scope: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!bool {
    var wrote_any = false;
    for (scope.extensions.items) |*field| {
        if (try writeValidateMessageExtensionPayload(ctx, target, field, writer, depth)) wrote_any = true;
    }
    for (scope.messages.items) |*nested| {
        if (try writeValidateScopedMessageExtensionPayloads(ctx, target, nested, writer, depth)) wrote_any = true;
    }
    return wrote_any;
}

fn writeValidateMessageExtensionPayload(ctx: *const CodegenContext, target: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!bool {
    const file = ctx.file;
    if (!extensionAppliesToMessage(file, target, field)) return false;
    const type_name = switch (field.kind) {
        .message => |name| name,
        .group => |name| name,
        else => return false,
    };
    if (!codegenCanReferenceMessageWithContext(ctx, type_name)) return false;

    try indent(writer, depth);
    try writer.writeAll("{\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const payloads = try ");
    try writeExtensionHelperReference(field, writer);
    try writer.writeAll(".decodeAllFromUnknown(self, allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("defer allocator.free(payloads);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("for (payloads) |payload| {\n");
    try writeDecodeAndValidatePayload(ctx, type_name, "payload", writer, depth + 2);
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
    return true;
}

fn writeValidateMessagePayloadField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.kind == .map) return try writeValidateMapMessagePayloadField(ctx, field, writer, depth);
    const type_name = switch (field.kind) {
        .message => |name| name,
        .group => |name| name,
        else => return,
    };
    if (!codegenCanReferenceMessageWithContext(ctx, type_name)) return;
    if (field.oneof_name != null) return;
    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        try writer.writeAll("for (self.");
        try writeQuotedIdent(field.name, writer);
        if (typedRepeatedMessageFieldWithContext(ctx, field)) |_| {
            try writer.writeAll(") |_pbz_nested| try _pbz_nested.validateRequiredRecursive(allocator);\n");
        } else {
            try writer.writeAll(") |payload| {\n");
            try writeDecodeAndValidatePayload(ctx, type_name, "payload", writer, depth + 1);
            try indent(writer, depth);
            try writer.writeAll("}\n");
        }
    } else {
        if (typedSingularMessageFieldWithContext(ctx, field)) |_| {
            try indent(writer, depth);
            try writer.writeAll("if (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(") |_pbz_nested| try _pbz_nested.validateRequiredRecursive(allocator);\n");
            return;
        }
        try indent(writer, depth);
        try writer.writeAll("if (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(".len != 0) {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("var _pbz_nested = try ");
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
        try writer.writeAll(".decode(allocator, self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(");\n");
        try indent(writer, depth + 1);
        try writer.writeAll("defer _pbz_nested.deinit(allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try _pbz_nested.validateRequiredRecursive(allocator);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");
    }
}

fn writeValidateMapMessagePayloadField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const map_type = switch (field.kind) {
        .map => |map_type| map_type,
        else => return,
    };
    const type_name = switch (map_type.value.*) {
        .message => |name| name,
        else => return,
    };
    if (!codegenCanReferenceMessageWithContext(ctx, type_name)) return;
    try indent(writer, depth);
    try writer.writeAll("{ var map_it = self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".iterator(); while (map_it.next()) |entry| {\n");
    if (typedMapMessageValueWithContext(ctx, field)) |_| {
        try indent(writer, depth + 1);
        try writer.writeAll("try entry.value_ptr.validateRequiredRecursive(allocator);\n");
    } else {
        try writeDecodeAndValidatePayload(ctx, type_name, "entry.value_ptr.*", writer, depth + 1);
    }
    try indent(writer, depth);
    try writer.writeAll("} }\n");
}

fn fieldHasMessageMapValue(field: *const schema.FieldDescriptor) bool {
    const map_type = switch (field.kind) {
        .map => |map_type| map_type,
        else => return false,
    };
    return map_type.value.* == .message;
}

fn writeValidateMessagePayloadOneof(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, oneof: schema.OneofDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("switch (self.");
    try writeQuotedIdent(oneof.name, writer);
    try writer.writeAll(") {\n");
    try indent(writer, depth + 1);
    try writer.writeAll(".none => {},\n");
    for (message.fields.items) |*field| {
        if (field.oneof_name) |name| {
            const type_name = switch (field.kind) {
                .message => |message_name| message_name,
                .group => |group_name| group_name,
                else => continue,
            };
            if (std.mem.eql(u8, name, oneof.name) and codegenCanReferenceMessageWithContext(ctx, type_name)) {
                try indent(writer, depth + 1);
                try writer.writeAll(".");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(" => |");
                if (typedOneofMessageFieldWithContext(ctx, field)) |_| {
                    try writer.writeAll("_pbz_nested| try _pbz_nested.validateRequiredRecursive(allocator),\n");
                    continue;
                } else {
                    try writer.writeAll("payload| {\n");
                    try writeDecodeAndValidatePayload(ctx, type_name, "payload", writer, depth + 2);
                }
                try indent(writer, depth + 1);
                try writer.writeAll("},\n");
            }
        }
    }
    try indent(writer, depth + 1);
    try writer.writeAll("else => {},\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeDecodeAndValidatePayload(ctx: *const CodegenContext, type_name: []const u8, payload_expr: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("var _pbz_nested = try ");
    try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    try writer.writeAll(".decode(allocator, ");
    try writer.writeAll(payload_expr);
    try writer.writeAll(");\n");
    try indent(writer, depth);
    try writer.writeAll("defer _pbz_nested.deinit(allocator);\n");
    try indent(writer, depth);
    try writer.writeAll("try _pbz_nested.validateRequiredRecursive(allocator);\n");
}

fn oneofHasMessageField(message: *const schema.MessageDescriptor, oneof_name: []const u8) bool {
    for (message.fields.items) |*field| {
        if (field.oneof_name) |name| {
            if (std.mem.eql(u8, name, oneof_name) and (field.kind == .message or field.kind == .group)) return true;
        }
    }
    return false;
}

pub fn codegenCanReferenceMessage(file: *const schema.FileDescriptor, type_name: []const u8) bool {
    return resolveSameFileMessageReference(file, type_name) != null;
}

pub fn writeMessageTypeReference(type_name: []const u8, writer: *std.Io.Writer) Error!void {
    const trimmed = if (std.mem.startsWith(u8, type_name, ".")) type_name[1..] else type_name;
    const leaf = if (std.mem.lastIndexOfScalar(u8, trimmed, '.')) |idx| trimmed[idx + 1 ..] else trimmed;
    try writeQuotedIdent(leaf, writer);
}

const MessageReference = struct {
    message: *const schema.MessageDescriptor,
    file: *const schema.FileDescriptor,
    import_chain: ?registry_mod.ImportChain = null,
};

const EnumReference = struct {
    enumeration: *const schema.EnumDescriptor,
    file: *const schema.FileDescriptor,
};

fn canReferenceMessageWithContext(ctx: *const CodegenContext, kind: schema.FieldKind) bool {
    const type_name = switch (kind) {
        .message, .group => |name| name,
        else => return false,
    };
    return codegenCanReferenceMessageWithContext(ctx, type_name);
}

fn canReferenceEnumWithContext(ctx: *const CodegenContext, kind: schema.FieldKind) bool {
    const type_name = switch (kind) {
        .enumeration => |name| name,
        else => return false,
    };
    return codegenCanReferenceEnumWithContext(ctx, type_name);
}

pub fn codegenCanReferenceMessageWithContext(ctx: *const CodegenContext, type_name: []const u8) bool {
    return resolveMessageReference(ctx, type_name) != null;
}

fn codegenCanReferenceEnumWithContext(ctx: *const CodegenContext, type_name: []const u8) bool {
    return resolveEnumReference(ctx, type_name) != null;
}

fn writeMessageTypeReferenceOrVoid(ctx: *const CodegenContext, kind: schema.FieldKind, writer: *std.Io.Writer) Error!void {
    const type_name = switch (kind) {
        .message, .group => |name| name,
        else => return try writer.writeAll("void"),
    };
    if (codegenCanReferenceMessageWithContext(ctx, type_name)) {
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    } else {
        try writer.writeAll("void");
    }
}

fn writeEnumTypeReferenceOrVoid(ctx: *const CodegenContext, kind: schema.FieldKind, writer: *std.Io.Writer) Error!void {
    const type_name = switch (kind) {
        .enumeration => |name| name,
        else => return try writer.writeAll("void"),
    };
    if (codegenCanReferenceEnumWithContext(ctx, type_name)) {
        try writeEnumTypeReferenceWithContext(ctx, type_name, writer);
    } else {
        try writer.writeAll("void");
    }
}

pub fn writeMessageTypeReferenceWithContext(ctx: *const CodegenContext, type_name: []const u8, writer: *std.Io.Writer) Error!void {
    const reference = resolveMessageReference(ctx, type_name) orelse {
        return try writeMessageTypeReference(type_name, writer);
    };
    if (reference.import_chain) |chain| {
        try writeImportChainPrefix(ctx, chain.slice(), writer);
        try writePackagePath(reference.file.package, writer);
        if (!(try writeMessagePathInFile(reference.file, reference.message, writer))) try writeMessageTypeReference(type_name, writer);
    } else {
        try writeMessageTypeReference(type_name, writer);
    }
}

/// Like writeMessageTypeReferenceWithContext, but always qualifies same-file
/// references with their message path. Use this from file-scope namespaces such
/// as `extensions`, where a nested type's leaf name is not in scope.
/// Reference a message from file scope (outside the package structs), where
/// same-file leaf names are not in scope.
pub fn writeFileScopeMessageReference(ctx: *const CodegenContext, type_name: []const u8, writer: *std.Io.Writer) Error!void {
    const reference = resolveMessageReference(ctx, type_name) orelse {
        return try writeMessageTypeReference(type_name, writer);
    };
    if (reference.import_chain) |chain| {
        try writeImportChainPrefix(ctx, chain.slice(), writer);
        try writePackagePath(reference.file.package, writer);
        _ = try writeMessagePathInFile(reference.file, reference.message, writer);
    } else {
        try writePackagePath(ctx.file.package, writer);
        _ = try writeMessagePathInFile(ctx.file, reference.message, writer);
    }
}

fn writeQualifiedMessageTypeReference(ctx: *const CodegenContext, type_name: []const u8, writer: *std.Io.Writer) Error!void {
    const reference = resolveMessageReference(ctx, type_name) orelse {
        return try writeMessageTypeReference(type_name, writer);
    };
    if (reference.import_chain) |chain| {
        try writeImportChainPrefix(ctx, chain.slice(), writer);
        try writePackagePath(reference.file.package, writer);
        if (!(try writeMessagePathInFile(reference.file, reference.message, writer))) try writeMessageTypeReference(type_name, writer);
    } else {
        if (!(try writeMessagePathInFile(ctx.file, reference.message, writer))) try writeMessageTypeReference(type_name, writer);
    }
}

fn writeEnumTypeReferenceWithContext(ctx: *const CodegenContext, type_name: []const u8, writer: *std.Io.Writer) Error!void {
    const reference = resolveEnumReference(ctx, type_name) orelse {
        return try writeMessageTypeReference(type_name, writer);
    };
    if (!(try writeEnumPathInFile(reference.file, reference.enumeration, writer))) try writeMessageTypeReference(type_name, writer);
}

pub fn resolveMessageReference(ctx: *const CodegenContext, type_name: []const u8) ?MessageReference {
    if (ctx.registry) |registry| {
        if (registry.findMessageVisible(ctx.file, type_name, ctx.file.package)) |message| {
            if (registry.fileContainingMessage(message)) |owner| {
                if (sameFileForCodegen(owner, ctx.file)) return .{ .message = message, .file = owner };
                if (registry.importChain(ctx.file, owner)) |chain| {
                    if (chain.len == 0) return .{ .message = message, .file = owner };
                    return .{ .message = message, .file = owner, .import_chain = chain };
                }
            }
        }
    }
    if (resolveSameFileMessageReference(ctx.file, type_name)) |message| return .{ .message = message, .file = ctx.file };
    return null;
}

fn resolveSameFileMessageReference(file: *const schema.FileDescriptor, type_name: []const u8) ?*const schema.MessageDescriptor {
    return findMessageByQualifiedName(file, type_name) orelse file.findMessageDeep(type_name);
}

fn resolveEnumReference(ctx: *const CodegenContext, type_name: []const u8) ?EnumReference {
    if (ctx.file.findEnumDeep(type_name)) |enumeration| return .{ .enumeration = enumeration, .file = ctx.file };
    if (ctx.registry) |registry| {
        if (registry.findEnumVisible(ctx.file, type_name, ctx.file.package)) |enumeration| {
            if (registry.fileContainingEnum(enumeration)) |owner| {
                if (sameFileForCodegen(owner, ctx.file)) return .{ .enumeration = enumeration, .file = owner };
            }
        }
    }
    return null;
}

pub fn sameFileForCodegen(a: *const schema.FileDescriptor, b: *const schema.FileDescriptor) bool {
    if (a == b) return true;
    if (a.name.len != 0 and b.name.len != 0 and std.mem.eql(u8, a.name, b.name)) return true;
    return false;
}

fn writeImportChainPrefix(ctx: *const CodegenContext, paths: []const []const u8, writer: *std.Io.Writer) Error!void {
    if (packageHasSegment(ctx.file.package, "imports")) try writer.writeAll("pbz_generated_file.");
    try writer.writeAll("imports.");
    for (paths, 0..) |path, index| {
        if (index != 0) {
            try writer.writeAll(".imports.");
        }
        const import_alias = try makeImportAlias(ctx.allocator, path);
        defer ctx.allocator.free(import_alias);
        try writer.writeAll(import_alias);
    }
    try writer.writeByte('.');
}

fn packageHasSegment(package: []const u8, needle: []const u8) bool {
    var parts = std.mem.splitScalar(u8, package, '.');
    while (parts.next()) |part| {
        if (std.mem.eql(u8, part, needle)) return true;
    }
    return false;
}

fn writePackagePath(package: []const u8, writer: *std.Io.Writer) Error!void {
    if (package.len == 0) return;
    var parts = std.mem.splitScalar(u8, package, '.');
    while (parts.next()) |part| {
        if (part.len == 0) continue;
        try writeQuotedIdent(part, writer);
        try writer.writeByte('.');
    }
}

fn writeMessagePathInFile(file: *const schema.FileDescriptor, target: *const schema.MessageDescriptor, writer: *std.Io.Writer) Error!bool {
    for (file.messages.items) |*message| {
        if (try writeMessagePathInMessage(message, target, writer)) return true;
    }
    return false;
}

fn writeMessagePathInMessage(message: *const schema.MessageDescriptor, target: *const schema.MessageDescriptor, writer: *std.Io.Writer) Error!bool {
    if (message == target) {
        try writeQuotedIdent(message.name, writer);
        return true;
    }
    for (message.messages.items) |*nested| {
        if (messageContainsMessage(nested, target) or nested == target) {
            try writeQuotedIdent(message.name, writer);
            try writer.writeByte('.');
            return try writeMessagePathInMessage(nested, target, writer);
        }
    }
    return false;
}

fn messageContainsMessage(message: *const schema.MessageDescriptor, target: *const schema.MessageDescriptor) bool {
    for (message.messages.items) |*nested| {
        if (nested == target or messageContainsMessage(nested, target)) return true;
    }
    return false;
}

fn writeEnumPathInFile(file: *const schema.FileDescriptor, target: *const schema.EnumDescriptor, writer: *std.Io.Writer) Error!bool {
    for (file.enums.items) |*enumeration| {
        if (enumeration == target) {
            try writeQuotedIdent(enumeration.name, writer);
            return true;
        }
    }
    for (file.messages.items) |*message| {
        if (try writeEnumPathInMessage(message, target, writer)) return true;
    }
    return false;
}

fn writeEnumPathInMessage(message: *const schema.MessageDescriptor, target: *const schema.EnumDescriptor, writer: *std.Io.Writer) Error!bool {
    for (message.enums.items) |*enumeration| {
        if (enumeration == target) {
            try writeQuotedIdent(message.name, writer);
            try writer.writeByte('.');
            try writeQuotedIdent(enumeration.name, writer);
            return true;
        }
    }
    for (message.messages.items) |*nested| {
        if (messageContainsEnumDescriptor(nested, target)) {
            try writeQuotedIdent(message.name, writer);
            try writer.writeByte('.');
            return try writeEnumPathInMessage(nested, target, writer);
        }
    }
    return false;
}

fn messageContainsEnumDescriptor(message: *const schema.MessageDescriptor, target: *const schema.EnumDescriptor) bool {
    for (message.enums.items) |*enumeration| {
        if (enumeration == target) return true;
    }
    for (message.messages.items) |*nested| {
        if (messageContainsEnumDescriptor(nested, target)) return true;
    }
    return false;
}

fn writeDecode(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (messageCanFastRawTagDecode(ctx.file, message)) return try writeDecodeFastRawTag(ctx, message, writer, depth);

    try indent(writer, depth);
    try writer.writeAll("/// Decode from wire bytes. String/bytes fields borrow the input slice;\n");
    try indent(writer, depth);
    try writer.writeAll("/// use decodeOwned when the decoded message must outlive the input.\n");
    try indent(writer, depth);
    try writer.writeAll("pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) !@This() {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var r = pbz.Reader.init(bytes);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try @This().decodeFromReader(allocator, &r);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("/// Decode from an existing reader. String/bytes fields borrow the reader input.\n");
    try indent(writer, depth);
    try writer.writeAll("pub fn decodeFromReader(allocator: std.mem.Allocator, r: *pbz.Reader) anyerror!@This() {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var self = @This().init();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer self.deinit(allocator);\n");
    for (message.fields.items) |*field| try writeRepeatedListDeclForDecode(ctx, field, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("var _unknown_fields_list: std.ArrayList([]const u8) = .empty;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer pbz.wire.deinitRawFieldList(allocator, &_unknown_fields_list);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("while (try r.nextTag()) |tag| {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("if (!@This().decodeAcceptsTag(tag)) {\n");
    try writeUnknownFieldFallback(writer, depth + 3, true);
    try indent(writer, depth + 2);
    try writer.writeAll("continue;\n");
    try indent(writer, depth + 2);
    try writer.writeAll("}\n");
    try indent(writer, depth + 2);
    try writer.writeAll("switch (tag.number) {\n");
    for (message.fields.items) |*field| try writeDecodeField(ctx, field, writer, depth + 3);
    try indent(writer, depth + 3);
    try writer.writeAll("else => try pbz.wire.appendSkippedRawField(allocator, &_unknown_fields_list, r, r.lastTagStart(), tag),\n");
    try indent(writer, depth + 2);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    for (message.fields.items) |*field| try writeRepeatedAssignForDecode(field, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("self._unknown_fields = try pbz.wire.rawFieldListToOwnedSlice(allocator, &_unknown_fields_list);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return self;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");
    try writeDecodeAcceptsTag(ctx, message, writer, depth);
}

fn writeUnknownFieldFallback(writer: *std.Io.Writer, depth: usize, reader_is_pointer: bool) Error!void {
    try indent(writer, depth);
    try writer.writeAll("try pbz.wire.appendSkippedRawField(allocator, &_unknown_fields_list, ");
    try writer.writeAll(if (reader_is_pointer) "r" else "&r");
    try writer.writeAll(", r.lastTagStart(), tag);\n");
}

fn writeDecodeAcceptsTag(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("fn decodeAcceptsTag(tag: pbz.wire.Tag) bool {\n");
    if (message.fields.items.len == 0) {
        try indent(writer, depth + 1);
        try writer.writeAll("_ = tag;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return true;\n");
    } else {
        try indent(writer, depth + 1);
        try writer.writeAll("return switch (tag.number) {\n");
        for (message.fields.items) |*field| {
            try indent(writer, depth + 2);
            try writer.print("{d} => ", .{field.number});
            try writeDecodeAcceptedWireType(ctx.file, field, writer);
            try writer.writeAll(",\n");
        }
        try indent(writer, depth + 2);
        try writer.writeAll("else => true,\n");
        try indent(writer, depth + 1);
        try writer.writeAll("};\n");
    }
    try indent(writer, depth);
    try writer.writeAll("}\n\n");
}

fn writeDecodeAcceptedWireType(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    if (field.cardinality == .repeated and field.kind.packable()) {
        try writer.writeAll("tag.wire_type == .");
        try writer.writeAll(@tagName(field.kind.wireType()));
        try writer.writeAll(" or tag.wire_type == .length_delimited");
        return;
    }
    if (field.kind == .message) {
        if (fieldMessageEncoding(file, field) == .delimited) {
            try writer.writeAll("tag.wire_type == .start_group");
        } else {
            try writer.writeAll("tag.wire_type == .length_delimited");
        }
        return;
    }
    try writer.writeAll("tag.wire_type == .");
    try writer.writeAll(@tagName(field.kind.wireType()));
}

fn messageCanFastRawTagDecode(file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor) bool {
    if (message.oneofs.items.len != 0) return false;
    var has_length_delimited_scalar = false;
    for (message.fields.items) |field| {
        switch (field.kind) {
            .scalar => |scalar| switch (scalar) {
                .string, .bytes => has_length_delimited_scalar = true,
                else => {},
            },
            .enumeration => |name| if (enum_emit.enumIsClosed(file, name)) return false,
            .message, .group, .map => return false,
        }
    }
    return has_length_delimited_scalar or message.fields.items.len >= 8;
}

fn writeDecodeFastRawTag(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("/// Decode from wire bytes. String/bytes fields borrow the input slice;\n");
    try indent(writer, depth);
    try writer.writeAll("/// use decodeOwned when the decoded message must outlive the input.\n");
    try indent(writer, depth);
    try writer.writeAll("pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) !@This() {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var r = pbz.Reader.init(bytes);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try @This().decodeFromReader(allocator, &r);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("/// Decode from an existing reader. String/bytes fields borrow the reader input.\n");
    try indent(writer, depth);
    try writer.writeAll("pub fn decodeFromReader(allocator: std.mem.Allocator, r: *pbz.Reader) anyerror!@This() {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var self = @This().init();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer self.deinit(allocator);\n");
    for (message.fields.items) |*field| try writeRepeatedListDeclForDecode(ctx, field, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("var _unknown_fields_list: std.ArrayList([]const u8) = .empty;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer pbz.wire.deinitRawFieldList(allocator, &_unknown_fields_list);\n");
    try writeRawTagDecodeLoop(ctx, message, writer, depth + 1, true);
    for (message.fields.items) |*field| try writeRepeatedAssignForDecode(field, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("self._unknown_fields = try pbz.wire.rawFieldListToOwnedSlice(allocator, &_unknown_fields_list);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return self;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeRawTagDecodeLoop(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize, r_is_pointer: bool) Error!void {
    try indent(writer, depth);
    try writer.writeAll("while (!r.eof()) {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const raw_tag_start = r.position();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const first_tag_byte = try r.readByte();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const raw_tag: u64 = if (first_tag_byte < 0x80) first_tag_byte else blk: { r.index = raw_tag_start; break :blk try r.readVarint(); };\n");
    try indent(writer, depth + 1);
    try writer.writeAll("switch (raw_tag) {\n");
    for (message.fields.items) |*field| try writeRawTagDecodeFieldCases(ctx, field, writer, depth + 2);
    try indent(writer, depth + 2);
    try writer.writeAll("else => try pbz.wire.appendSkippedRawField(allocator, &_unknown_fields_list, ");
    try writer.writeAll(if (r_is_pointer) "r" else "&r");
    try writer.writeAll(", raw_tag_start, try pbz.wire.Tag.decode(raw_tag)),\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeRawTagDecodeFieldCases(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    switch (field.kind) {
        .scalar => |scalar| {
            if (field.cardinality == .repeated and scalar.packable()) {
                try writeRawTagDecodePackedScalarCase(field, scalar, writer, depth);
                try writeRawTagDecodeUnpackedScalarCase(ctx.file, field, scalar, writer, depth);
            } else if (field.cardinality == .repeated) {
                try writeRawTagDecodeUnpackedScalarCase(ctx.file, field, scalar, writer, depth);
            } else {
                try writeRawTagDecodeSingularScalarCase(ctx.file, field, scalar, writer, depth);
            }
        },
        .enumeration => {
            if (field.cardinality == .repeated) {
                if (field.resolvedPacked(ctx.file)) try writeRawTagDecodePackedEnumCase(ctx.file, field, writer, depth);
                try writeRawTagDecodeUnpackedEnumCase(field, writer, depth);
            } else {
                try writeRawTagDecodeSingularEnumCase(ctx.file, field, writer, depth);
            }
        },
        else => unreachable,
    }
}

fn writeRawTagDecodeSingularScalarCase(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.print("{d} => {{ self.", .{rawFieldTag(field.number, .{ .scalar = scalar })});
    try writeQuotedIdent(field.name, writer);
    try writer.print(" = try r.{s}();", .{scalarReaderName(scalar)});
    if (scalar == .string and fieldUtf8Validation(file, field) == .verify) {
        try writer.writeAll(" if (!pbz.validateUtf8(self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(")) return error.InvalidUtf8;");
    }
    try writeSetPresence(file, field, writer);
    try writer.writeAll(" },\n");
}

fn writeRawTagDecodeUnpackedScalarCase(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.print("{d} => ", .{rawFieldTag(field.number, .{ .scalar = scalar })});
    if (scalar == .string and fieldUtf8Validation(file, field) == .verify) {
        try writer.writeAll("{ const value = try r.readBytes(); if (!pbz.validateUtf8(value)) return error.InvalidUtf8; ");
        try writeRepeatedAppendPrefix(field, writer);
        try writer.writeAll("value); },\n");
        return;
    }
    try writeRepeatedAppendPrefix(field, writer);
    try writer.print("try r.{s}()),\n", .{scalarReaderName(scalar)});
}

fn writeRawTagDecodePackedScalarCase(field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.print("{d} => {{\n", .{rawTagValue(field.number, .length_delimited)});
    try writeDecodePackedScalarPayload(field, scalar, writer, depth + 1);
    try indent(writer, depth);
    try writer.writeAll("},\n");
}

fn writeRawTagDecodeSingularEnumCase(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.print("{d} => {{ const value = try r.readInt32(); self.", .{rawTagValue(field.number, .varint)});
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = value;");
    try writeSetPresence(file, field, writer);
    try writer.writeAll(" },\n");
}

fn writeRawTagDecodeUnpackedEnumCase(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.print("{d} => ", .{rawTagValue(field.number, .varint)});
    try writeRepeatedAppendPrefix(field, writer);
    try writer.writeAll("try r.readInt32()),\n");
}

fn writeRawTagDecodePackedEnumCase(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.print("{d} => {{\n", .{rawTagValue(field.number, .length_delimited)});
    try indent(writer, depth + 1);
    try writer.writeAll("const payload = try r.readBytes();\n");
    if (field.kind == .enumeration and !enum_emit.enumIsClosed(file, field.kind.enumeration)) {
        try indent(writer, depth + 1);
        try writer.writeAll("try pbz.wire.appendPackedInt32(allocator, &");
        try writeQuotedIdentWithSuffix(field.name, "_list", writer);
        try writer.writeAll(", payload);\n");
    } else {
        try indent(writer, depth + 1);
        try writer.writeAll("try ");
        try writeQuotedIdentWithSuffix(field.name, "_list", writer);
        try writer.writeAll(".ensureUnusedCapacity(allocator, payload.len);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("var packed_reader = pbz.Reader.init(payload);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("while (!packed_reader.eof()) ");
        try writeQuotedIdentWithSuffix(field.name, "_list", writer);
        try writer.writeAll(".appendAssumeCapacity(try packed_reader.readInt32());\n");
    }
    try indent(writer, depth);
    try writer.writeAll("},\n");
}

fn rawFieldTag(number: u29, kind: schema.FieldKind) u64 {
    return rawTagValue(number, kind.wireType());
}

fn rawTagValue(number: u29, wire_type: wire.WireType) u64 {
    return (@as(u64, number) << 3) | @intFromEnum(wire_type);
}

fn messageCanDecodeKnownReuse(file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor) bool {
    if (message.oneofs.items.len != 0) return false;
    var has_repeated = false;
    for (message.fields.items) |field| {
        if (field.cardinality == .repeated) {
            has_repeated = true;
            switch (field.kind) {
                .scalar => |scalar| if (knownReuseRepeatedScalarSupported(scalar) == false) return false,
                .enumeration => |name| if (enum_emit.enumIsClosed(file, name)) return false,
                else => return false,
            }
            continue;
        }
        switch (field.kind) {
            .scalar => {},
            .enumeration => |name| if (enum_emit.enumIsClosed(file, name)) return false,
            .message, .group, .map => return false,
        }
    }
    return has_repeated;
}

fn knownReuseRepeatedScalarSupported(scalar: schema.ScalarType) bool {
    return switch (scalar) {
        .bool,
        .uint64,
        .uint32,
        .int32,
        .int64,
        .sint32,
        .sint64,
        .fixed32,
        .fixed64,
        .sfixed32,
        .sfixed64,
        .float,
        .double,
        => true,
        else => false,
    };
}

fn writeDecodeReuse(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("/// Decode into an existing message, reusing repeated/map storage.\n");
    try indent(writer, depth);
    try writer.writeAll("/// String/bytes fields still borrow the input slice.\n");
    try indent(writer, depth);
    try writer.writeAll("pub fn decodeReuse(self: *@This(), allocator: std.mem.Allocator, bytes: []const u8) !void {\n");
    for (message.fields.items) |*field| try writeRepeatedReuseListDecl(ctx, field, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("pbz.wire.clearRawFields(allocator, &self._unknown_fields);\n");
    for (message.fields.items) |*field| try writeDecodeReuseClearMap(ctx, field, writer, depth + 1);
    for (message.oneofs.items) |oneof| try writeDecodeReuseClearOneof(oneof, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("if (self._json_arena) |arena| { _ = arena.reset(.retain_capacity); }\n");
    for (message.fields.items) |*field| try writeDecodeReuseResetField(ctx, field, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer self.deinit(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var _unknown_fields_list: std.ArrayList([]const u8) = .empty;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer pbz.wire.deinitRawFieldList(allocator, &_unknown_fields_list);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var r = pbz.Reader.init(bytes);\n");
    if (messageCanFastRawTagDecode(ctx.file, message)) {
        try writeRawTagDecodeLoop(ctx, message, writer, depth + 1, false);
    } else {
        try indent(writer, depth + 1);
        try writer.writeAll("while (try r.nextTag()) |tag| {\n");
        try indent(writer, depth + 2);
        try writer.writeAll("if (!@This().decodeAcceptsTag(tag)) {\n");
        try writeUnknownFieldFallback(writer, depth + 3, false);
        try indent(writer, depth + 2);
        try writer.writeAll("continue;\n");
        try indent(writer, depth + 2);
        try writer.writeAll("}\n");
        try indent(writer, depth + 2);
        try writer.writeAll("switch (tag.number) {\n");
        for (message.fields.items) |*field| try writeDecodeField(ctx, field, writer, depth + 3);
        try indent(writer, depth + 3);
        try writer.writeAll("else => try pbz.wire.appendSkippedRawField(allocator, &_unknown_fields_list, &r, r.lastTagStart(), tag),\n");
        try indent(writer, depth + 2);
        try writer.writeAll("}\n");
        try indent(writer, depth + 1);
        try writer.writeAll("}\n");
    }
    for (message.fields.items) |*field| try writeRepeatedAssignForDecode(field, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("self._unknown_fields = try pbz.wire.rawFieldListToOwnedSlice(allocator, &_unknown_fields_list);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeDecodeOwnedReuse(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    _ = ctx;
    _ = message;
    try indent(writer, depth);
    try writer.writeAll("/// Decode into an existing message, reusing arrays/maps and retained owned string storage.\n");
    try indent(writer, depth);
    try writer.writeAll("pub fn decodeOwnedReuse(self: *@This(), allocator: std.mem.Allocator, bytes: []const u8) !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer self.deinit(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.decodeReuse(allocator, bytes);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.adoptOwned(allocator);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeDecodeKnownReuse(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("/// Trusted same-schema hot path that reuses existing repeated buffers.\n");
    try indent(writer, depth);
    try writer.writeAll("/// The caller must pre-size those buffers for the decoded element counts.\n");
    try indent(writer, depth);
    try writer.writeAll("/// Unknown or schema-mismatched fields are rejected instead of preserved.\n");
    try indent(writer, depth);
    try writer.writeAll("pub fn decodeKnownReuse(self: *@This(), allocator: std.mem.Allocator, bytes: []const u8) !void {\n");
    for (message.fields.items) |*field| {
        if (field.cardinality != .repeated) continue;
        try indent(writer, depth + 1);
        try writer.writeAll("const ");
        try writeQuotedIdentWithSuffix(field.name, "_buffer", writer);
        try writer.writeAll(" = @constCast(self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(");\n");
        try indent(writer, depth + 1);
        try writer.writeAll("var ");
        try writeQuotedIdentWithSuffix(field.name, "_len", writer);
        try writer.writeAll(": usize = 0;\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("pbz.wire.clearRawFields(allocator, &self._unknown_fields);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (self._json_arena) |arena| { const child_allocator = arena.child_allocator; arena.deinit(); child_allocator.destroy(arena); self._json_arena = null; }\n");
    for (message.fields.items) |*field| try writeDecodeReuseResetField(ctx, field, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("var r = pbz.Reader.init(bytes);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("while (!r.eof()) {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("const raw_tag_start = r.position();\n");
    try indent(writer, depth + 2);
    try writer.writeAll("const first_tag_byte = try r.readByte();\n");
    try indent(writer, depth + 2);
    try writer.writeAll("const raw_tag: u64 = if (first_tag_byte < 0x80) first_tag_byte else blk: { r.index = raw_tag_start; break :blk try r.readVarint(); };\n");
    try indent(writer, depth + 2);
    try writer.writeAll("switch (raw_tag) {\n");
    for (message.fields.items) |*field| {
        if (field.cardinality == .repeated) {
            switch (field.kind) {
                .scalar => |scalar| try writeKnownReuseRepeatedScalarCases(ctx.file, field, scalar, writer, depth + 3),
                .enumeration => try writeKnownReuseRepeatedEnumCases(field, writer, depth + 3),
                else => {},
            }
            continue;
        }
        switch (field.kind) {
            .scalar => |scalar| try writeKnownReuseSingularScalarCase(ctx.file, field, scalar, writer, depth + 3),
            .enumeration => try writeKnownReuseSingularEnumCase(ctx.file, field, writer, depth + 3),
            else => {},
        }
    }
    try indent(writer, depth + 3);
    try writer.writeAll("else => return error.InvalidWireType,\n");
    try indent(writer, depth + 2);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    for (message.fields.items) |*field| {
        if (field.cardinality != .repeated) continue;
        try indent(writer, depth + 1);
        try writer.writeAll("if (");
        try writeQuotedIdentWithSuffix(field.name, "_len", writer);
        try writer.writeAll(" != ");
        try writeQuotedIdentWithSuffix(field.name, "_buffer", writer);
        try writer.writeAll(".len) return error.InvalidWireType;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = ");
        try writeQuotedIdentWithSuffix(field.name, "_buffer", writer);
        try writer.writeAll(";\n");
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeKnownReuseRepeatedScalarCases(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
    _ = file;
    try indent(writer, depth);
    try writer.print("{d} => {{\n", .{rawTagValue(field.number, .length_delimited)});
    try indent(writer, depth + 1);
    try writer.writeAll("const payload = try r.readBytes();\n");
    try writeKnownReuseRepeatedScalarPayload(field, scalar, "payload", writer, depth + 1);
    try indent(writer, depth);
    try writer.writeAll("},\n");

    try indent(writer, depth);
    try writer.print("{d} => {{\n", .{rawTagValue(field.number, scalar.wireType())});
    try indent(writer, depth + 1);
    try writeQuotedIdentWithSuffix(field.name, "_buffer", writer);
    try writer.writeAll("[");
    try writeQuotedIdentWithSuffix(field.name, "_len", writer);
    try writer.writeAll("] = try r.");
    try writer.writeAll(scalarReaderName(scalar));
    try writer.writeAll("();\n");
    try indent(writer, depth + 1);
    try writeQuotedIdentWithSuffix(field.name, "_len", writer);
    try writer.writeAll(" += 1;\n");
    try indent(writer, depth);
    try writer.writeAll("},\n");
}

fn writeKnownReuseRepeatedEnumCases(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.print("{d} => {{\n", .{rawTagValue(field.number, .length_delimited)});
    try indent(writer, depth + 1);
    try writer.writeAll("const payload = try r.readBytes();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (pbz.wire.packedEnumAllSingleByte(payload)) {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("for (payload) |byte| {\n");
    try indent(writer, depth + 3);
    try writeQuotedIdentWithSuffix(field.name, "_buffer", writer);
    try writer.writeAll("[");
    try writeQuotedIdentWithSuffix(field.name, "_len", writer);
    try writer.writeAll("] = @intCast(byte);\n");
    try indent(writer, depth + 3);
    try writeQuotedIdentWithSuffix(field.name, "_len", writer);
    try writer.writeAll(" += 1;\n");
    try indent(writer, depth + 2);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("} else {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var payload_index: usize = 0;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("while (payload_index < payload.len) {\n");
    try indent(writer, depth + 2);
    try writeQuotedIdentWithSuffix(field.name, "_buffer", writer);
    try writer.writeAll("[");
    try writeQuotedIdentWithSuffix(field.name, "_len", writer);
    try writer.writeAll("] = @truncate(@as(i64, @bitCast(try pbz.wire.readVarintAt(payload, &payload_index))));\n");
    try indent(writer, depth + 2);
    try writeQuotedIdentWithSuffix(field.name, "_len", writer);
    try writer.writeAll(" += 1;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth);
    try writer.writeAll("},\n");

    try indent(writer, depth);
    try writer.print("{d} => {{\n", .{rawTagValue(field.number, .varint)});
    try indent(writer, depth + 1);
    try writeQuotedIdentWithSuffix(field.name, "_buffer", writer);
    try writer.writeAll("[");
    try writeQuotedIdentWithSuffix(field.name, "_len", writer);
    try writer.writeAll("] = try r.readInt32();\n");
    try indent(writer, depth + 1);
    try writeQuotedIdentWithSuffix(field.name, "_len", writer);
    try writer.writeAll(" += 1;\n");
    try indent(writer, depth);
    try writer.writeAll("},\n");
}

fn writeKnownReuseSingularScalarCase(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.print("{d} => {{ self.", .{rawFieldTag(field.number, .{ .scalar = scalar })});
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = ");
    try writeKnownReuseSingularScalarDecodeExpr(scalar, "r.input", "r.index", writer);
    try writer.writeAll(";");
    if (scalar == .string and fieldUtf8Validation(file, field) == .verify) {
        try writer.writeAll(" if (!pbz.validateUtf8(self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(")) return error.InvalidUtf8;");
    }
    try writeSetPresence(file, field, writer);
    try writer.writeAll(" },\n");
}

fn writeKnownReuseSingularEnumCase(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.print("{d} => {{ const value = try pbz.wire.readInt32At(r.input, &r.index); self.", .{rawTagValue(field.number, .varint)});
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = value;");
    try writeSetPresence(file, field, writer);
    try writer.writeAll(" },\n");
}

fn writeKnownReuseRepeatedScalarPayload(field: *const schema.FieldDescriptor, scalar: schema.ScalarType, payload_expr: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    if (scalar == .bool) {
        try indent(writer, depth);
        try writer.writeAll("try pbz.wire.decodePackedBoolInto(");
        try writeQuotedIdentWithSuffix(field.name, "_buffer", writer);
        try writer.writeAll(", &");
        try writeQuotedIdentWithSuffix(field.name, "_len", writer);
        try writer.writeAll(", ");
        try writer.writeAll(payload_expr);
        try writer.writeAll(");\n");
        return;
    }

    if (fixedWidthPackedScalarSizeForCodegen(scalar)) |width| {
        try indent(writer, depth);
        try writer.print("if ({s}.len % {d} != 0) return error.InvalidWireType;\n", .{ payload_expr, width });
        try indent(writer, depth);
        try writer.print("const value_count = {s}.len / {d};\n", .{ payload_expr, width });
        try indent(writer, depth);
        try writer.writeAll("if (");
        try writeQuotedIdentWithSuffix(field.name, "_len", writer);
        try writer.writeAll(" + value_count > ");
        try writeQuotedIdentWithSuffix(field.name, "_buffer", writer);
        try writer.writeAll(".len) return error.InvalidWireType;\n");
        try indent(writer, depth);
        try writer.writeAll("{\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const out = ");
        try writeQuotedIdentWithSuffix(field.name, "_buffer", writer);
        try writer.writeAll("[");
        try writeQuotedIdentWithSuffix(field.name, "_len", writer);
        try writer.writeAll("..][0..value_count];\n");
        try indent(writer, depth + 1);
        try writer.writeAll("if (comptime @import(\"builtin\").target.cpu.arch.endian() == .little) {\n");
        try indent(writer, depth + 2);
        try writer.print("pbz.wire.copyBytes(std.mem.sliceAsBytes(out), {s});\n", .{payload_expr});
        try indent(writer, depth + 1);
        try writer.writeAll("} else {\n");
        try indent(writer, depth + 2);
        try writer.writeAll("var payload_index: usize = 0;\n");
        try indent(writer, depth + 2);
        try writer.writeAll("for (out) |*value| {\n");
        try indent(writer, depth + 3);
        try writer.writeAll("value.* = ");
        try writeKnownReuseFixedWidthScalarDecodeExpr(scalar, payload_expr, "payload_index", width, writer);
        try writer.writeAll(";\n");
        try indent(writer, depth + 3);
        try writer.print("payload_index += {d};\n", .{width});
        try indent(writer, depth + 2);
        try writer.writeAll("}\n");
        try indent(writer, depth + 1);
        try writer.writeAll("}\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");
        try indent(writer, depth);
        try writeQuotedIdentWithSuffix(field.name, "_len", writer);
        try writer.writeAll(" += value_count;\n");
        return;
    }

    try indent(writer, depth);
    try writer.writeAll("var payload_index: usize = 0;\n");
    try indent(writer, depth);
    try writer.print("while (payload_index < {s}.len) {{\n", .{payload_expr});
    try indent(writer, depth + 1);
    try writeQuotedIdentWithSuffix(field.name, "_buffer", writer);
    try writer.writeAll("[");
    try writeQuotedIdentWithSuffix(field.name, "_len", writer);
    try writer.writeAll("] = ");
    try writeKnownReuseRepeatedScalarDecodeExpr(scalar, payload_expr, writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writeQuotedIdentWithSuffix(field.name, "_len", writer);
    try writer.writeAll(" += 1;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeKnownReuseSingularScalarDecodeExpr(scalar: schema.ScalarType, input_expr: []const u8, index_expr: []const u8, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .double => try writer.print("@bitCast(try pbz.wire.readRawLittleAt(u64, {s}, &{s}))", .{ input_expr, index_expr }),
        .float => try writer.print("@bitCast(try pbz.wire.readRawLittleAt(u32, {s}, &{s}))", .{ input_expr, index_expr }),
        .int32 => try writer.print("try pbz.wire.readInt32At({s}, &{s})", .{ input_expr, index_expr }),
        .int64 => try writer.print("@bitCast(try pbz.wire.readVarintAt({s}, &{s}))", .{ input_expr, index_expr }),
        .uint32 => try writer.print("try pbz.wire.readUInt32At({s}, &{s})", .{ input_expr, index_expr }),
        .uint64 => try writer.print("try pbz.wire.readVarintAt({s}, &{s})", .{ input_expr, index_expr }),
        .sint32 => try writer.print("try pbz.wire.readSInt32At({s}, &{s})", .{ input_expr, index_expr }),
        .sint64 => try writer.print("pbz.wire.zigZagDecode64(try pbz.wire.readVarintAt({s}, &{s}))", .{ input_expr, index_expr }),
        .fixed32 => try writer.print("try pbz.wire.readRawLittleAt(u32, {s}, &{s})", .{ input_expr, index_expr }),
        .fixed64 => try writer.print("try pbz.wire.readRawLittleAt(u64, {s}, &{s})", .{ input_expr, index_expr }),
        .sfixed32 => try writer.print("@bitCast(try pbz.wire.readRawLittleAt(u32, {s}, &{s}))", .{ input_expr, index_expr }),
        .sfixed64 => try writer.print("@bitCast(try pbz.wire.readRawLittleAt(u64, {s}, &{s}))", .{ input_expr, index_expr }),
        .bool => try writer.print("try pbz.wire.readBoolAt({s}, &{s})", .{ input_expr, index_expr }),
        .string, .bytes => try writer.writeAll("try r.readBytes()"),
    }
}

fn writeKnownReuseRepeatedScalarDecodeExpr(scalar: schema.ScalarType, payload_expr: []const u8, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .uint64 => try writer.print("try pbz.wire.readVarintAt({s}, &payload_index)", .{payload_expr}),
        .uint32 => try writer.print("@as(u32, @truncate(try pbz.wire.readVarintAt({s}, &payload_index)))", .{payload_expr}),
        .int32 => try writer.print("try pbz.wire.readInt32At({s}, &payload_index)", .{payload_expr}),
        .int64 => try writer.print("@bitCast(try pbz.wire.readVarintAt({s}, &payload_index))", .{payload_expr}),
        .sint32 => try writer.print("try pbz.wire.readSInt32At({s}, &payload_index)", .{payload_expr}),
        .sint64 => try writer.print("pbz.wire.zigZagDecode64(try pbz.wire.readVarintAt({s}, &payload_index))", .{payload_expr}),
        else => try writer.writeAll("@compileError(\"unsupported known reuse scalar\")"),
    }
}

fn fixedWidthPackedScalarSizeForCodegen(scalar: schema.ScalarType) ?usize {
    return switch (scalar) {
        .fixed32, .sfixed32, .float => 4,
        .fixed64, .sfixed64, .double => 8,
        else => null,
    };
}

fn writeKnownReuseFixedWidthScalarDecodeExpr(scalar: schema.ScalarType, payload_expr: []const u8, index_expr: []const u8, width: usize, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .fixed32 => try writer.print("std.mem.readInt(u32, {s}[{s}..][0..{d}], .little)", .{ payload_expr, index_expr, width }),
        .fixed64 => try writer.print("std.mem.readInt(u64, {s}[{s}..][0..{d}], .little)", .{ payload_expr, index_expr, width }),
        .sfixed32 => try writer.print("std.mem.readInt(i32, {s}[{s}..][0..{d}], .little)", .{ payload_expr, index_expr, width }),
        .sfixed64 => try writer.print("std.mem.readInt(i64, {s}[{s}..][0..{d}], .little)", .{ payload_expr, index_expr, width }),
        .float => try writer.print("@bitCast(std.mem.readInt(u32, {s}[{s}..][0..{d}], .little))", .{ payload_expr, index_expr, width }),
        .double => try writer.print("@bitCast(std.mem.readInt(u64, {s}[{s}..][0..{d}], .little))", .{ payload_expr, index_expr, width }),
        else => try writer.writeAll("@compileError(\"unsupported fixed-width known reuse scalar\")"),
    }
}

fn writeRepeatedReuseListDecl(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.kind == .map) return;
    if (field.cardinality != .repeated) return;
    try indent(writer, depth);
    try writer.writeAll("var ");
    try writeQuotedIdentWithSuffix(field.name, "_list", writer);
    try writer.writeAll(": std.ArrayList(");
    if (typedRepeatedMessageFieldWithContext(ctx, field)) |type_name| {
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    } else {
        try writeRepeatedElementType(field.*, writer);
    }
    try writer.writeAll(") = std.ArrayList(");
    if (typedRepeatedMessageFieldWithContext(ctx, field)) |type_name| {
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    } else {
        try writeRepeatedElementType(field.*, writer);
    }
    try writer.writeAll(").fromOwnedSlice(@constCast(self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll("));\n");
    if (typedRepeatedMessageFieldWithContext(ctx, field) != null) {
        try indent(writer, depth);
        try writer.writeAll("for (");
        try writeQuotedIdentWithSuffix(field.name, "_list", writer);
        try writer.writeAll(".items) |*item| item.deinit(allocator);\n");
    }
    try indent(writer, depth);
    try writeQuotedIdentWithSuffix(field.name, "_list", writer);
    try writer.writeAll(".clearRetainingCapacity();\n");
    try indent(writer, depth);
    try writer.writeAll("self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = &.{};\n");
    try indent(writer, depth);
    try writer.writeAll("errdefer ");
    try writeQuotedIdentWithSuffix(field.name, "_list", writer);
    try writer.writeAll(".deinit(allocator);\n");
}

fn writeDecodeReuseResetField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.oneof_name != null) return;
    if (field.kind == .map) return;
    if (field.cardinality == .repeated) return;
    if (typedSingularMessageFieldWithContext(ctx, field) != null) {
        try indent(writer, depth);
        try writer.writeAll("if (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(") |*value| value.deinit(allocator);\n");
        try indent(writer, depth);
        try writer.writeAll("self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = null;\n");
        return;
    }
    try indent(writer, depth);
    try writer.writeAll("self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = ");
    try writeFieldDefault(ctx.file, field.*, writer);
    try writer.writeAll(";\n");
    if (hasPresence(ctx.file, field.*)) {
        try indent(writer, depth);
        try writer.writeAll("self.");
        try writePresenceIdent(field.name, writer);
        try writer.writeAll(" = false;\n");
    }
}

fn writeDecodeReuseClearMap(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.kind != .map) return;
    if (typedMapMessageValueWithContext(ctx, field)) |_| {
        try indent(writer, depth);
        try writer.writeAll("{ var map_it = self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(".iterator(); while (map_it.next()) |entry| entry.value_ptr.deinit(allocator); }\n");
    }
    try indent(writer, depth);
    try writer.writeAll("self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".clearRetainingCapacity();\n");
}

fn writeDecodeReuseClearOneof(oneof: schema.OneofDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writeOneofDeinitCall(oneof.name, writer);
    try writer.writeAll("\n");
}

fn writeDecodeInitialized(writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn decodeOwned(allocator: std.mem.Allocator, bytes: []const u8) !@This() {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var self = try @This().decode(allocator, bytes);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer self.deinit(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.adoptOwned(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return self;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("/// Decode and validate required fields. String/bytes fields borrow the input slice.\n");
    try indent(writer, depth);
    try writer.writeAll("pub fn decodeInitialized(allocator: std.mem.Allocator, bytes: []const u8) !@This() {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var self = try @This().decode(allocator, bytes);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer self.deinit(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.validateRequiredRecursive(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return self;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try writer.writeAll("\n");
    try indent(writer, depth);
    try writer.writeAll("/// Decode, deep-copy, and validate required fields.\n");
    try indent(writer, depth);
    try writer.writeAll("pub fn decodeOwnedInitialized(allocator: std.mem.Allocator, bytes: []const u8) !@This() {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var self = try @This().decodeOwned(allocator, bytes);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer self.deinit(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.validateRequiredRecursive(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return self;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeRepeatedListDecl(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.cardinality != .repeated and field.kind != .map) return;
    try indent(writer, depth);
    try writer.writeAll("var ");
    try writeQuotedIdentWithSuffix(field.name, "_list", writer);
    try writer.writeAll(": std.ArrayList(");
    if (typedRepeatedMessageFieldWithContext(ctx, field)) |type_name| {
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    } else {
        try writeRepeatedElementType(field.*, writer);
    }
    try writer.writeAll(") = .empty;\n");
    try indent(writer, depth);
    try writer.writeAll("defer ");
    try writeQuotedIdentWithSuffix(field.name, "_list", writer);
    try writer.writeAll(".deinit(allocator);\n");
    if (typedRepeatedMessageFieldWithContext(ctx, field)) |_| {
        try indent(writer, depth);
        try writer.writeAll("errdefer for (");
        try writeQuotedIdentWithSuffix(field.name, "_list", writer);
        try writer.writeAll(".items) |item| { var mutable = item; mutable.deinit(allocator); };\n");
    } else if (typedMapMessageValueWithContext(ctx, field)) |_| {
        try indent(writer, depth);
        try writer.writeAll("errdefer for (");
        try writeQuotedIdentWithSuffix(field.name, "_list", writer);
        try writer.writeAll(".items) |list_entry| { var old_value = list_entry.value; old_value.deinit(allocator); };\n");
    }
}

fn writeRepeatedListDeclForDecode(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.kind == .map) return;
    try writeRepeatedListDecl(ctx, field, writer, depth);
}

pub fn writeRepeatedAssign(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.cardinality != .repeated and field.kind != .map) return;
    if (field.kind == .map) return try writeMapAssign(field, writer, depth);
    try indent(writer, depth);
    try writer.writeAll("self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = if (");
    try writeQuotedIdentWithSuffix(field.name, "_list", writer);
    try writer.writeAll(".items.len != 0 and ");
    try writeQuotedIdentWithSuffix(field.name, "_list", writer);
    try writer.writeAll(".items.len == ");
    try writeQuotedIdentWithSuffix(field.name, "_list", writer);
    try writer.writeAll(".capacity) ");
    try writeQuotedIdentWithSuffix(field.name, "_list", writer);
    try writer.writeAll(".toOwnedSliceAssert() else try ");
    try writeQuotedIdentWithSuffix(field.name, "_list", writer);
    try writer.writeAll(".toOwnedSlice(allocator);\n");
}

fn writeRepeatedAssignForDecode(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.kind == .map) return;
    try writeRepeatedAssign(field, writer, depth);
}

fn writeMapAssign(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = .empty;\n");
    try indent(writer, depth);
    try writer.writeAll("try self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".ensureUnusedCapacity(allocator, ");
    try writeQuotedIdentWithSuffix(field.name, "_list", writer);
    try writer.writeAll(".items.len);\n");
    try indent(writer, depth);
    try writer.writeAll("for (");
    try writeQuotedIdentWithSuffix(field.name, "_list", writer);
    try writer.writeAll(".items) |entry| self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".putAssumeCapacityNoClobber(entry.key, entry.value);\n");
}

pub fn writeRepeatedElementType(field: schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    switch (field.kind) {
        .scalar => |scalar| try writer.writeAll(scalarZigType(scalar)),
        .enumeration => try writer.writeAll("i32"),
        .message, .group => try writer.writeAll("[]const u8"),
        .map => try writeQuotedIdentWithSuffix(field.name, "Entry", writer),
    }
}

fn writeDecodeField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    switch (field.kind) {
        .scalar => |scalar| try writeDecodeScalarField(file, field, scalar, writer, depth),
        .enumeration => try writeDecodeEnumField(file, field, writer, depth),
        .message, .group => try writeDecodeMessageField(ctx, field, writer, depth),
        .map => try writeDecodeMapField(ctx, field, writer, depth),
    }
}

fn writeDecodeScalarField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.print("{d} => ", .{field.number});
    if (field.cardinality == .repeated) {
        if (scalar.packable()) {
            try writeDecodePackedScalarField(field, scalar, writer, depth);
        } else {
            if (scalar == .string and fieldUtf8Validation(file, field) == .verify) {
                try writer.writeAll("{ const value = try r.readBytes(); if (!pbz.validateUtf8(value)) return error.InvalidUtf8; ");
                try writeRepeatedAppendPrefix(field, writer);
                try writer.writeAll("value); },\n");
            } else {
                try writeRepeatedAppendPrefix(field, writer);
                try writer.print("try r.{s}()),\n", .{scalarReaderName(scalar)});
            }
        }
    } else if (field.oneof_name != null) {
        try writeOneofDecodeAssign(file, field, scalarReaderName(scalar), writer);
    } else {
        try writer.writeAll("{ self.");
        try writeQuotedIdent(field.name, writer);
        try writer.print(" = try r.{s}();", .{scalarReaderName(scalar)});
        if (scalar == .string and fieldUtf8Validation(file, field) == .verify) {
            try writer.writeAll(" if (!pbz.validateUtf8(self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(")) return error.InvalidUtf8;");
        }
        try writeSetPresence(file, field, writer);
        try writer.writeAll(" },\n");
    }
}

fn writeDecodeEnumField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.print("{d} => ", .{field.number});
    if (field.cardinality == .repeated) {
        try writeDecodePackedEnumField(file, field, writer, depth);
    } else if (field.oneof_name != null) {
        try writeOneofEnumDecodeAssign(file, field, writer);
    } else if (field.kind == .enumeration and enum_emit.enumIsClosed(file, field.kind.enumeration)) {
        try writer.writeAll("{ const value = try r.readInt32(); if (!@This().enumKnown(value, ");
        try enum_emit.writeEnumNumberArray(file, field.kind.enumeration, writer);
        try writer.writeAll(")) { try pbz.wire.appendConsumedRawField(allocator, &_unknown_fields_list, r, r.lastTagStart()); } else { self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = value;");
        try writeSetPresence(file, field, writer);
        try writer.writeAll(" } },\n");
    } else {
        try writer.writeAll("{ const value = try r.readInt32();");
        try writeEnumClosedCheck(file, field, "value", writer);
        try writer.writeAll(" self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = value;");
        try writeSetPresence(file, field, writer);
        try writer.writeAll(" },\n");
    }
}

fn writeDecodeMessageField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    try indent(writer, depth);
    try writer.print("{d} => ", .{field.number});
    if (field.cardinality == .repeated) {
        if (typedRepeatedMessageFieldWithContext(ctx, field)) |type_name| {
            try writer.writeAll("{ const payload = ");
            try writeMessagePayloadRead(file, field, "r", writer);
            try writer.writeAll("; var payload_reader = try r.nested(payload); var _pbz_nested = try ");
            try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
            try writer.writeAll(".decodeFromReader(allocator, &payload_reader); errdefer _pbz_nested.deinit(allocator); try ");
            try writeQuotedIdentWithSuffix(field.name, "_list", writer);
            try writer.writeAll(".append(allocator, _pbz_nested); },\n");
        } else {
            try writeRepeatedAppendPrefix(field, writer);
            try writeMessagePayloadRead(file, field, "r", writer);
            try writer.writeAll("),\n");
        }
    } else if (field.oneof_name != null) {
        try writeOneofMessageDecodeAssign(ctx, field, writer);
    } else if (typedSingularMessageFieldWithContext(ctx, field)) |type_name| {
        try writer.writeAll("{ const payload = ");
        try writeMessagePayloadRead(file, field, "r", writer);
        try writer.writeAll("; var payload_reader = try r.nested(payload); var _pbz_nested = try ");
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
        try writer.writeAll(".decodeFromReader(allocator, &payload_reader); errdefer _pbz_nested.deinit(allocator); if (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(") |*existing| { try existing.mergeFrom(allocator, _pbz_nested); _pbz_nested.deinit(allocator); } else { self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = _pbz_nested; } },\n");
    } else {
        try writer.writeAll("{ const payload = ");
        try writeMessagePayloadRead(file, field, "r", writer);
        try writer.writeAll("; if (self.");
        try writePresenceIdent(field.name, writer);
        try writer.writeAll(" and self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(".len != 0 and payload.len != 0) { const owned_allocator = try self._pbzOwnedAllocator(allocator); const merged = try owned_allocator.alloc(u8, self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(".len + payload.len); @memcpy(merged[0..self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(".len], self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll("); @memcpy(merged[self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(".len..], payload); self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = merged; } else if (!self.");
        try writePresenceIdent(field.name, writer);
        try writer.writeAll(" or self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(".len == 0) { self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = payload; }");
        try writer.writeAll(" self.");
        try writePresenceIdent(field.name, writer);
        try writer.writeAll(" = true;");
        try writer.writeAll(" },\n");
    }
}

fn writeDecodePackedScalarField(field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
    try writer.writeAll("{\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (tag.wire_type == .length_delimited) {\n");
    try writeDecodePackedScalarPayload(field, scalar, writer, depth + 2);
    try indent(writer, depth + 1);
    try writer.writeAll("} else {\n");
    try indent(writer, depth + 2);
    try writeRepeatedAppendPrefix(field, writer);
    try writer.print("try r.{s}());\n", .{scalarReaderName(scalar)});
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth);
    try writer.writeAll("},\n");
}

fn writeDecodePackedScalarPayload(field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("const payload = try r.readBytes();\n");
    if (packedScalarAppendHelperName(scalar)) |helper_name| {
        try indent(writer, depth);
        try writer.writeAll("try pbz.wire.");
        try writer.writeAll(helper_name);
        try writer.writeAll("(allocator, &");
        try writeQuotedIdentWithSuffix(field.name, "_list", writer);
        try writer.writeAll(", payload);\n");
    } else {
        try indent(writer, depth);
        try writer.writeAll("try ");
        try writeQuotedIdentWithSuffix(field.name, "_list", writer);
        try writer.writeAll(".ensureUnusedCapacity(allocator, ");
        try writePackedScalarDecodeCapacityExpr(scalar, "payload", writer);
        try writer.writeAll(");\n");
        try indent(writer, depth);
        try writer.writeAll("var packed_reader = pbz.Reader.init(payload);\n");
        try indent(writer, depth);
        try writer.writeAll("while (!packed_reader.eof()) ");
        try writeQuotedIdentWithSuffix(field.name, "_list", writer);
        try writer.print(".appendAssumeCapacity(try packed_reader.{s}());\n", .{scalarReaderName(scalar)});
    }
}

fn packedScalarAppendHelperName(scalar: schema.ScalarType) ?[]const u8 {
    return switch (scalar) {
        .int32 => "appendPackedInt32",
        .int64 => "appendPackedInt64",
        .uint32 => "appendPackedUInt32",
        .uint64 => "appendPackedUInt64",
        .sint32 => "appendPackedSInt32",
        .sint64 => "appendPackedSInt64",
        .bool => "appendPackedBool",
        .fixed32 => "appendPackedFixed32",
        .fixed64 => "appendPackedFixed64",
        .sfixed32 => "appendPackedSFixed32",
        .sfixed64 => "appendPackedSFixed64",
        .float => "appendPackedFloat",
        .double => "appendPackedDouble",
        else => null,
    };
}

fn writePackedScalarDecodeCapacityExpr(scalar: schema.ScalarType, payload_expr: []const u8, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .double, .fixed64, .sfixed64 => try writer.print("{s}.len / 8", .{payload_expr}),
        .float, .fixed32, .sfixed32 => try writer.print("{s}.len / 4", .{payload_expr}),
        .int32, .int64, .uint32, .uint64, .sint32, .sint64, .bool => try writer.print("{s}.len", .{payload_expr}),
        .string, .bytes => try writer.writeAll("@compileError(\"non-packable scalar\")"),
    }
}

fn writeDecodePackedEnumField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try writer.writeAll("{\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (tag.wire_type == .length_delimited) {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("const payload = try r.readBytes();\n");
    if (field.kind == .enumeration and !enum_emit.enumIsClosed(file, field.kind.enumeration)) {
        try indent(writer, depth + 2);
        try writer.writeAll("try pbz.wire.appendPackedInt32(allocator, &");
        try writeQuotedIdentWithSuffix(field.name, "_list", writer);
        try writer.writeAll(", payload);\n");
    } else {
        try indent(writer, depth + 2);
        try writer.writeAll("var packed_reader = pbz.Reader.init(payload);\n");
        try indent(writer, depth + 2);
        try writer.writeAll("while (!packed_reader.eof()) { const value_start = packed_reader.position(); const value = try packed_reader.readInt32(); const value_end = packed_reader.position();");
        try writer.writeAll(" if (!@This().enumKnown(value, ");
        try enum_emit.writeEnumNumberArray(file, field.kind.enumeration, writer);
        try writer.writeAll(")) { try pbz.wire.appendRawVarintPayload(allocator, &_unknown_fields_list, ");
        try writer.print("{d}", .{field.number});
        try writer.writeAll(", payload[value_start..value_end]); continue; }");
        try writer.writeAll(" try ");
        try writeQuotedIdentWithSuffix(field.name, "_list", writer);
        try writer.writeAll(".append(allocator, value); }\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("} else {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("{ const value = try r.readInt32();");
    if (field.kind == .enumeration and enum_emit.enumIsClosed(file, field.kind.enumeration)) {
        try writer.writeAll(" if (!@This().enumKnown(value, ");
        try enum_emit.writeEnumNumberArray(file, field.kind.enumeration, writer);
        try writer.writeAll(")) { try pbz.wire.appendConsumedRawField(allocator, &_unknown_fields_list, r, r.lastTagStart()); } else { try ");
        try writeQuotedIdentWithSuffix(field.name, "_list", writer);
        try writer.writeAll(".append(allocator, value); } }\n");
    } else {
        try writeEnumClosedCheck(file, field, "value", writer);
        try writer.writeAll(" try ");
        try writeQuotedIdentWithSuffix(field.name, "_list", writer);
        try writer.writeAll(".append(allocator, value); }\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth);
    try writer.writeAll("},\n");
}

fn writeDecodeMapField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    const map_type = switch (field.kind) {
        .map => |map| map,
        else => return,
    };
    try indent(writer, depth);
    try writer.print("{d} => {{\n", .{field.number});
    try indent(writer, depth + 1);
    try writer.writeAll("var entry = ");
    try writeQuotedIdentWithSuffix(field.name, "Entry", writer);
    try writer.writeAll("{};\n");
    if (typedMapMessageValueWithContext(ctx, field)) |_| {
        try indent(writer, depth + 1);
        try writer.writeAll("errdefer entry.value.deinit(allocator);\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("const payload = try r.readBytes();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var entry_reader = try r.nested(payload);\n");
    const can_skip_entry = wireMapEntryCanSkip(file, map_type);
    if (can_skip_entry) {
        try indent(writer, depth + 1);
        try writer.writeAll("var skip_entry = false;\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("while (try entry_reader.nextTag()) |entry_tag| {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("switch (entry_tag.number) {\n");
    try writeMapEntryDecodeAssign(ctx, field, "entry.key", 1, .{ .scalar = map_type.key }, writer, depth + 3);
    try writeMapEntryDecodeAssign(ctx, field, "entry.value", 2, map_type.value.*, writer, depth + 3);
    try indent(writer, depth + 3);
    try writer.writeAll("else => try entry_reader.skipValue(entry_tag),\n");
    try indent(writer, depth + 2);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    if (can_skip_entry) {
        try writer.writeAll("if (skip_entry) { try pbz.wire.appendConsumedRawField(allocator, &_unknown_fields_list, r, r.lastTagStart()); } else ");
    }
    try writer.writeAll("try @This().");
    try writeQuotedIdentWithPrefix(field.name, "putMapEntry_", writer);
    try writer.writeAll("(allocator, &self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(", entry);\n");
    try indent(writer, depth);
    try writer.writeAll("},\n");
}

fn wireMapEntryCanSkip(file: *const schema.FileDescriptor, map_type: schema.MapType) bool {
    return map_type.value.* == .enumeration and enum_emit.enumIsClosed(file, map_type.value.enumeration);
}

fn writeMapEntryDecodeAssign(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, target: []const u8, number: u29, kind: schema.FieldKind, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    const typed_message_value = if (number == 2) typedMapMessageValueWithContext(ctx, field) else null;
    try indent(writer, depth);
    try writer.print("{d} => {{\n", .{number});
    try indent(writer, depth + 1);
    try writer.print("if (entry_tag.wire_type != .{s}) {{\n", .{@tagName(kind.wireType())});
    try indent(writer, depth + 2);
    try writer.writeAll("try entry_reader.skipValue(entry_tag);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("} else {\n");
    if (kind == .scalar and kind.scalar == .string and fieldUtf8Validation(file, field) == .verify) {
        try indent(writer, depth + 2);
        try writer.writeAll("const value = ");
        try writeEntryReadExpr(kind, "entry_reader", writer);
        try writer.writeAll(";\n");
        try indent(writer, depth + 2);
        try writer.writeAll("if (!pbz.validateUtf8(value)) return error.InvalidUtf8;\n");
        try indent(writer, depth + 2);
        try writer.writeAll(target);
        try writer.writeAll(" = value;\n");
    } else if (kind == .enumeration and enum_emit.enumIsClosed(file, kind.enumeration)) {
        try indent(writer, depth + 2);
        try writer.writeAll("const value = ");
        try writeEntryReadExpr(kind, "entry_reader", writer);
        try writer.writeAll(";\n");
        try indent(writer, depth + 2);
        try writer.writeAll("if (!@This().enumKnown(value, ");
        try enum_emit.writeEnumNumberArray(file, kind.enumeration, writer);
        try writer.writeAll(")) {\n");
        try indent(writer, depth + 3);
        try writer.writeAll("skip_entry = true;\n");
        try indent(writer, depth + 2);
        try writer.writeAll("} else {\n");
        try indent(writer, depth + 3);
        try writer.writeAll(target);
        try writer.writeAll(" = value;\n");
        try indent(writer, depth + 2);
        try writer.writeAll("}\n");
    } else if (typed_message_value) |type_name| {
        try indent(writer, depth + 2);
        try writer.writeAll("const value_payload = try entry_reader.readBytes();\n");
        try indent(writer, depth + 2);
        try writer.writeAll("var value_reader = try entry_reader.nested(value_payload);\n");
        try indent(writer, depth + 2);
        try writer.writeAll(target);
        try writer.writeAll(".deinit(allocator);\n");
        try indent(writer, depth + 2);
        try writer.writeAll(target);
        try writer.writeAll(" = try ");
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
        try writer.writeAll(".decodeFromReader(allocator, &value_reader);\n");
    } else {
        try indent(writer, depth + 2);
        try writer.writeAll(target);
        try writer.writeAll(" = ");
        try writeEntryReadExpr(kind, "entry_reader", writer);
        try writer.writeAll(";\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth);
    try writer.writeAll("},\n");
}

fn writeOneofDecodeAssign(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, reader_method: []const u8, writer: *std.Io.Writer) Error!void {
    const oneof_name = field.oneof_name orelse return;
    if (field.kind == .scalar and field.kind.scalar == .string and fieldUtf8Validation(file, field) == .verify) {
        try writer.writeAll("{ const value = try r.");
        try writer.writeAll(reader_method);
        try writer.writeAll("(); if (!pbz.validateUtf8(value)) return error.InvalidUtf8; ");
        try writeOneofDeinitCall(oneof_name, writer);
        try writer.writeAll(" self.");
        try writeQuotedIdent(oneof_name, writer);
        try writer.writeAll(" = .{ .");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = value }; },\n");
        return;
    }
    try writer.writeAll("{ const value = try r.");
    try writer.writeAll(reader_method);
    try writer.writeAll("(); ");
    try writeOneofDeinitCall(oneof_name, writer);
    try writer.writeAll(" self.");
    try writeQuotedIdent(oneof_name, writer);
    try writer.writeAll(" = .{ .");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = value }; },\n");
}

fn writeOneofMessageDecodeAssign(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    const file = ctx.file;
    const oneof_name = field.oneof_name orelse return;
    if (typedOneofMessageFieldWithContext(ctx, field)) |type_name| {
        try writer.writeAll("{ const payload = ");
        try writeMessagePayloadRead(file, field, "r", writer);
        try writer.writeAll("; var payload_reader = try r.nested(payload); var _pbz_nested = try ");
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
        try writer.writeAll(".decodeFromReader(allocator, &payload_reader); errdefer _pbz_nested.deinit(allocator); ");
        try writeOneofDeinitCall(oneof_name, writer);
        try writer.writeAll(" self.");
        try writeQuotedIdent(oneof_name, writer);
        try writer.writeAll(" = .{ .");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = _pbz_nested }; },\n");
        return;
    }
    try writer.writeAll("{ const value = ");
    try writeMessagePayloadRead(file, field, "r", writer);
    try writer.writeAll("; switch (self.");
    try writeQuotedIdent(oneof_name, writer);
    try writer.writeAll(") { .");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" => |existing| { const owned_allocator = try self._pbzOwnedAllocator(allocator); const merged = try owned_allocator.alloc(u8, existing.len + value.len); @memcpy(merged[0..existing.len], existing); @memcpy(merged[existing.len..], value); self.");
    try writeQuotedIdent(oneof_name, writer);
    try writer.writeAll(" = .{ .");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = merged }; }, else => { ");
    try writeOneofDeinitCall(oneof_name, writer);
    try writer.writeAll(" self.");
    try writeQuotedIdent(oneof_name, writer);
    try writer.writeAll(" = .{ .");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = value }; } } },\n");
}

fn writeOneofEnumDecodeAssign(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    const oneof_name = field.oneof_name orelse return;
    try writer.writeAll("{ const value = try r.readInt32();");
    if (field.kind == .enumeration and enum_emit.enumIsClosed(file, field.kind.enumeration)) {
        try writer.writeAll(" if (!@This().enumKnown(value, ");
        try enum_emit.writeEnumNumberArray(file, field.kind.enumeration, writer);
        try writer.writeAll(")) { try pbz.wire.appendConsumedRawField(allocator, &_unknown_fields_list, r, r.lastTagStart()); } else {");
    } else {
        try writeEnumClosedCheck(file, field, "value", writer);
    }
    try writer.writeAll(" ");
    try writeOneofDeinitCall(oneof_name, writer);
    try writer.writeAll(" self.");
    try writeQuotedIdent(oneof_name, writer);
    try writer.writeAll(" = .{ .");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = value };");
    if (field.kind == .enumeration and enum_emit.enumIsClosed(file, field.kind.enumeration)) try writer.writeAll(" }");
    try writer.writeAll(" },\n");
}

fn writeEnumClosedCheck(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    const enum_name = switch (field.kind) {
        .enumeration => |name| name,
        else => return,
    };
    try writeEnumClosedCheckByName(file, enum_name, value_expr, writer);
}

fn writeEnumClosedCheckByName(file: *const schema.FileDescriptor, enum_name: []const u8, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    if (!enum_emit.enumIsClosed(file, enum_name)) return;
    try writer.writeAll(" if (");
    if (file.findEnumDeep(enum_name)) |enumeration| {
        for (enumeration.values.items, 0..) |value, i| {
            if (i != 0) try writer.writeAll(" and ");
            try writer.print("{s} != {d}", .{ value_expr, value.number });
        }
    } else {
        try writer.writeAll("true");
    }
    try writer.writeAll(") return error.InvalidEnumValue;");
}

fn writeEntryReadExpr(kind: schema.FieldKind, reader_name: []const u8, writer: *std.Io.Writer) Error!void {
    switch (kind) {
        .scalar => |scalar| try writer.print("try {s}.{s}()", .{ reader_name, scalarReaderName(scalar) }),
        .enumeration => try writer.print("try {s}.readInt32()", .{reader_name}),
        .message => try writer.print("try {s}.readBytes()", .{reader_name}),
        else => try writer.writeAll("@compileError(\"unsupported map decode kind\")"),
    }
}

fn writeRepeatedAppendPrefix(field: *const schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("try ");
    try writeQuotedIdentWithSuffix(field.name, "_list", writer);
    try writer.writeAll(".append(allocator, ");
}

fn scalarReaderName(scalar: schema.ScalarType) []const u8 {
    return switch (scalar) {
        .double => "readDouble",
        .float => "readFloat",
        .int32 => "readInt32",
        .int64 => "readInt64",
        .uint32 => "readUInt32",
        .uint64 => "readUInt64",
        .sint32 => "readSInt32",
        .sint64 => "readSInt64",
        .fixed32 => "readFixed32",
        .fixed64 => "readFixed64",
        .sfixed32 => "readSFixed32",
        .sfixed64 => "readSFixed64",
        .bool => "readBool",
        .string, .bytes => "readBytes",
    };
}

fn writeEncodeField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    switch (field.kind) {
        .scalar => |scalar| try writeEncodeScalarField(file, field, scalar, writer, depth),
        .enumeration => try writeEncodeEnumField(file, field, writer, depth),
        .message => try writeEncodeMessageField(ctx, field, writer, depth),
        .group => try writeEncodeGroupField(ctx, field, writer, depth),
        .map => try writeEncodeMapField(ctx, field, writer, depth),
    }
}

fn writeEncodeFieldAssumeCapacity(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    switch (field.kind) {
        .scalar => |scalar| try writeEncodeScalarFieldAssumeCapacity(file, field, scalar, writer, depth),
        .enumeration => try writeEncodeEnumFieldAssumeCapacity(file, field, writer, depth),
        .message => try writeEncodeMessageFieldAssumeCapacity(ctx, field, writer, depth),
        .group => try writeEncodeGroupFieldAssumeCapacity(ctx, field, writer, depth),
        .map => try writeEncodeMapFieldAssumeCapacity(ctx, field, writer, depth),
    }
}

fn writeEncodeFieldDeterministic(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    switch (field.kind) {
        .scalar => |scalar| try writeEncodeScalarField(file, field, scalar, writer, depth),
        .enumeration => try writeEncodeEnumField(file, field, writer, depth),
        .message => |type_name| if (codegenCanReferenceMessageWithContext(ctx, type_name)) {
            try writeEncodeMessageFieldDeterministic(ctx, field, type_name, writer, depth);
        } else try writeEncodeMessageField(ctx, field, writer, depth),
        .group => |type_name| if (codegenCanReferenceMessageWithContext(ctx, type_name)) {
            try writeEncodeGroupFieldDeterministic(ctx, field, type_name, writer, depth);
        } else try writeEncodeGroupField(ctx, field, writer, depth),
        .map => try writeEncodeMapFieldDeterministic(ctx, field, writer, depth),
    }
}

fn writeEncodeFieldDeterministicAssumeCapacity(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    switch (field.kind) {
        .scalar => |scalar| try writeEncodeScalarFieldAssumeCapacity(file, field, scalar, writer, depth),
        .enumeration => try writeEncodeEnumFieldAssumeCapacity(file, field, writer, depth),
        .message => |type_name| if (codegenCanReferenceMessageWithContext(ctx, type_name)) {
            try writeEncodeMessageFieldDeterministicAssumeCapacity(ctx, field, type_name, writer, depth);
        } else try writeEncodeMessageFieldAssumeCapacity(ctx, field, writer, depth),
        .group => |type_name| if (codegenCanReferenceMessageWithContext(ctx, type_name)) {
            try writeEncodeGroupFieldDeterministicAssumeCapacity(ctx, field, type_name, writer, depth);
        } else try writeEncodeGroupFieldAssumeCapacity(ctx, field, writer, depth),
        .map => try writeEncodeMapFieldDeterministicAssumeCapacity(ctx, field, writer, depth),
    }
}

fn writeEncodeScalarField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.cardinality == .repeated) {
        if (field.resolvedPacked(file)) {
            try writeEncodePackedScalarField(field, scalar, writer, depth);
        } else {
            try indent(writer, depth);
            if (scalar == .string and fieldUtf8Validation(file, field) == .verify) {
                try writer.writeAll("for (self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(") |item| { if (!pbz.validateUtf8(item)) return error.InvalidUtf8; ");
                try writeScalarWriteCall(field.number, scalar, "item", writer);
                try writer.writeAll("); }\n");
            } else {
                try writer.writeAll("for (self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(") |item| ");
                try writeScalarWriteCall(field.number, scalar, "item", writer);
                try writer.writeAll(");\n");
            }
        }
    } else {
        try indent(writer, depth);
        if (hasPresence(file, field.*)) {
            try writer.writeAll("if (self.");
            try writePresenceIdent(field.name, writer);
            try writer.writeAll(") ");
        } else if (shouldSkipDefault(scalar)) {
            try writeScalarSkipCondition("self.", field.name, scalar, writer);
        }
        if (scalar == .string and fieldUtf8Validation(file, field) == .verify) {
            try writer.writeAll("{ if (!pbz.validateUtf8(self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(")) return error.InvalidUtf8; ");
        }
        try writeScalarWriteCall(field.number, scalar, "self.", writer);
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(")");
        if (scalar == .string and fieldUtf8Validation(file, field) == .verify) try writer.writeAll("; }\n") else try writer.writeAll(";\n");
    }
}

fn writeEncodeEnumField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.cardinality == .repeated) {
        if (field.resolvedPacked(file)) {
            try writeEncodePackedEnumField(field, writer, depth);
        } else {
            try indent(writer, depth);
            try writer.writeAll("for (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.print(") |item| try w.writeInt32({d}, item);\n", .{field.number});
        }
    } else {
        try indent(writer, depth);
        if (hasPresence(file, field.*)) {
            try writer.writeAll("if (self.");
            try writePresenceIdent(field.name, writer);
            try writer.writeAll(") ");
        } else {
            try writer.writeAll("if (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(" != 0) ");
        }
        try writer.print("try w.writeInt32({d}, self.", .{field.number});
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(");\n");
    }
}

fn writeEncodeScalarFieldAssumeCapacity(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.cardinality == .repeated) {
        if (field.resolvedPacked(file)) {
            try writeEncodePackedScalarFieldAssumeCapacity(field, scalar, writer, depth);
        } else {
            try indent(writer, depth);
            if (scalar == .string and fieldUtf8Validation(file, field) == .verify) {
                try writer.writeAll("for (self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(") |item| { if (!pbz.validateUtf8(item)) return error.InvalidUtf8; ");
                try writeScalarWriteCallAssumeCapacity(field.number, scalar, "item", writer);
                try writer.writeAll("); }\n");
            } else {
                try writer.writeAll("for (self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(") |item| ");
                try writeScalarWriteCallAssumeCapacity(field.number, scalar, "item", writer);
                try writer.writeAll(");\n");
            }
        }
    } else {
        try indent(writer, depth);
        if (hasPresence(file, field.*)) {
            try writer.writeAll("if (self.");
            try writePresenceIdent(field.name, writer);
            try writer.writeAll(") ");
        } else if (shouldSkipDefault(scalar)) {
            try writeScalarSkipCondition("self.", field.name, scalar, writer);
        }
        if (scalar == .string and fieldUtf8Validation(file, field) == .verify) {
            try writer.writeAll("{ if (!pbz.validateUtf8(self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(")) return error.InvalidUtf8; ");
        }
        try writeScalarWriteCallAssumeCapacity(field.number, scalar, "self.", writer);
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(")");
        if (scalar == .string and fieldUtf8Validation(file, field) == .verify) try writer.writeAll("; }\n") else try writer.writeAll(";\n");
    }
}

fn writeEncodeEnumFieldAssumeCapacity(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.cardinality == .repeated) {
        if (field.resolvedPacked(file)) {
            try writeEncodePackedEnumFieldAssumeCapacity(field, writer, depth);
        } else {
            try indent(writer, depth);
            try writer.writeAll("for (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.print(") |item| w.writeInt32AssumeCapacity({d}, item);\n", .{field.number});
        }
    } else {
        try indent(writer, depth);
        if (hasPresence(file, field.*)) {
            try writer.writeAll("if (self.");
            try writePresenceIdent(field.name, writer);
            try writer.writeAll(") ");
        } else {
            try writer.writeAll("if (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(" != 0) ");
        }
        try writer.print("w.writeInt32AssumeCapacity({d}, self.", .{field.number});
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(");\n");
    }
}

fn writeEncodePackedScalarField(field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
    try writeEncodePackedPrefix(field, writer, depth);
    try indent(writer, depth + 1);
    if (fixedPackedScalarWidth(scalar)) |width| {
        try writer.writeAll("const packed_len = self.");
        try writeQuotedIdent(field.name, writer);
        try writer.print(".len * {d};\n", .{width});
    } else {
        try writer.writeAll("var packed_len: usize = 0;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("for (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(") |item| packed_len += ");
        try writePackedScalarSizeExpr(scalar, "item", writer);
        try writer.writeAll(";\n");
    }
    try writeEncodePackedLength(field, writer, depth);
    try indent(writer, depth + 1);
    if (fixedWidthViewScalarType(scalar)) |payload_type| {
        try writer.writeAll("try pbz.wire.writePackedFixedWidthPayload(");
        try writer.writeAll(payload_type);
        try writer.writeAll(", w, self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(");\n");
    } else if (scalar == .bool) {
        try writer.writeAll("try w.appendSlice(std.mem.sliceAsBytes(self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll("));\n");
    } else {
        try writer.writeAll("for (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(") |item| ");
        try writePackedScalarPayload(scalar, "item", "w", writer);
        try writer.writeAll(";\n");
    }
    try writeEncodePackedSuffix(field, writer, depth);
}

fn writeEncodePackedEnumField(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try writeEncodePackedPrefix(field, writer, depth);
    try indent(writer, depth + 1);
    try writer.writeAll("var packed_len: usize = 0;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("for (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(") |item| packed_len += pbz.wire.encodedVarintSize(@as(u64, @bitCast(@as(i64, item))));\n");
    try writeEncodePackedLength(field, writer, depth);
    try indent(writer, depth + 1);
    try writer.writeAll("for (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(") |item| ");
    try writePackedEnumPayload("item", "w", writer);
    try writer.writeAll(";\n");
    try writeEncodePackedSuffix(field, writer, depth);
}

fn writeEncodePackedScalarFieldAssumeCapacity(field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
    try writeEncodePackedPrefix(field, writer, depth);
    try indent(writer, depth + 1);
    if (fixedPackedScalarWidth(scalar)) |width| {
        try writer.writeAll("const packed_len = self.");
        try writeQuotedIdent(field.name, writer);
        try writer.print(".len * {d};\n", .{width});
    } else {
        try writer.writeAll("var packed_len: usize = 0;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("for (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(") |item| packed_len += ");
        try writePackedScalarSizeExpr(scalar, "item", writer);
        try writer.writeAll(";\n");
    }
    try writeEncodePackedLengthAssumeCapacity(field, writer, depth);
    try indent(writer, depth + 1);
    if (fixedWidthViewScalarType(scalar)) |payload_type| {
        try writer.writeAll("pbz.wire.writePackedFixedWidthPayloadAssumeCapacity(");
        try writer.writeAll(payload_type);
        try writer.writeAll(", w, self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(");\n");
    } else if (scalar == .bool) {
        try writer.writeAll("w.appendSliceAssumeCapacity(std.mem.sliceAsBytes(self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll("));\n");
    } else {
        try writer.writeAll("for (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(") |item| ");
        try writePackedScalarPayloadAssumeCapacity(scalar, "item", "w", writer);
        try writer.writeAll(";\n");
    }
    try writeEncodePackedSuffix(field, writer, depth);
}

fn writeEncodePackedEnumFieldAssumeCapacity(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try writeEncodePackedPrefix(field, writer, depth);
    try indent(writer, depth + 1);
    try writer.writeAll("var packed_len: usize = 0;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("for (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(") |item| packed_len += pbz.wire.encodedVarintSize(@as(u64, @bitCast(@as(i64, item))));\n");
    try writeEncodePackedLengthAssumeCapacity(field, writer, depth);
    try indent(writer, depth + 1);
    try writer.writeAll("for (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(") |item| ");
    try writePackedEnumPayloadAssumeCapacity("item", "w", writer);
    try writer.writeAll(";\n");
    try writeEncodePackedSuffix(field, writer, depth);
}

fn writeEncodePackedPrefix(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("if (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".len != 0) {\n");
}

fn writeEncodePackedLength(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth + 1);
    try writer.print("try w.writeTag({d}, .length_delimited);\n", .{field.number});
    try indent(writer, depth + 1);
    try writer.writeAll("try w.writeVarint(packed_len);\n");
}

fn writeEncodePackedLengthAssumeCapacity(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth + 1);
    try writer.print("w.writeTagAssumeCapacity({d}, .length_delimited);\n", .{field.number});
    try indent(writer, depth + 1);
    try writer.writeAll("w.writeVarintAssumeCapacity(packed_len);\n");
}

fn writeEncodePackedSuffix(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    _ = field;
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn scalarPayloadSizeIsConstant(scalar: schema.ScalarType) bool {
    return switch (scalar) {
        .double, .fixed64, .sfixed64, .float, .fixed32, .sfixed32 => true,
        else => false,
    };
}

fn fixedPackedScalarWidth(scalar: schema.ScalarType) ?usize {
    return switch (scalar) {
        .double, .fixed64, .sfixed64 => 8,
        .float, .fixed32, .sfixed32 => 4,
        .bool => 1,
        else => null,
    };
}

fn writePackedScalarSizeExpr(scalar: schema.ScalarType, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .double, .fixed64, .sfixed64 => try writer.writeAll("8"),
        .float, .fixed32, .sfixed32 => try writer.writeAll("4"),
        .int32 => try writer.print("pbz.wire.encodedVarintSize(@as(u64, @bitCast(@as(i64, {s}))))", .{value_expr}),
        .int64 => try writer.print("pbz.wire.encodedVarintSize(@as(u64, @bitCast({s})))", .{value_expr}),
        .uint32, .uint64 => try writer.print("pbz.wire.encodedVarintSize({s})", .{value_expr}),
        .sint32 => try writer.print("pbz.wire.encodedVarintSize(pbz.wire.zigZagEncode32({s}))", .{value_expr}),
        .sint64 => try writer.print("pbz.wire.encodedVarintSize(pbz.wire.zigZagEncode64({s}))", .{value_expr}),
        .bool => try writer.print("(if ({s}) @as(usize, 1) else @as(usize, 1))", .{value_expr}),
        .string, .bytes => try writer.writeAll("@compileError(\"non-packable scalar\")"),
    }
}

fn writePackedScalarPayload(scalar: schema.ScalarType, value_expr: []const u8, writer_name: []const u8, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .double => try writer.print("try {s}.writeRawLittle(u64, @bitCast({s}))", .{ writer_name, value_expr }),
        .float => try writer.print("try {s}.writeRawLittle(u32, @bitCast({s}))", .{ writer_name, value_expr }),
        .int32 => try writer.print("try {s}.writeVarint(@as(u64, @bitCast(@as(i64, {s}))))", .{ writer_name, value_expr }),
        .int64 => try writer.print("try {s}.writeVarint(@as(u64, @bitCast({s})))", .{ writer_name, value_expr }),
        .uint32 => try writer.print("try {s}.writeVarint({s})", .{ writer_name, value_expr }),
        .uint64 => try writer.print("try {s}.writeVarint({s})", .{ writer_name, value_expr }),
        .sint32 => try writer.print("try {s}.writeVarint(pbz.wire.zigZagEncode32({s}))", .{ writer_name, value_expr }),
        .sint64 => try writer.print("try {s}.writeVarint(pbz.wire.zigZagEncode64({s}))", .{ writer_name, value_expr }),
        .fixed32 => try writer.print("try {s}.writeRawLittle(u32, {s})", .{ writer_name, value_expr }),
        .fixed64 => try writer.print("try {s}.writeRawLittle(u64, {s})", .{ writer_name, value_expr }),
        .sfixed32 => try writer.print("try {s}.writeRawLittle(i32, {s})", .{ writer_name, value_expr }),
        .sfixed64 => try writer.print("try {s}.writeRawLittle(i64, {s})", .{ writer_name, value_expr }),
        .bool => try writer.print("try {s}.writeVarint(@as(u64, if ({s}) 1 else 0))", .{ writer_name, value_expr }),
        .string, .bytes => try writer.writeAll("@compileError(\"non-packable scalar\")"),
    }
}

fn writePackedEnumPayload(value_expr: []const u8, writer_name: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.print("try {s}.writeVarint(@as(u64, @bitCast(@as(i64, {s}))))", .{ writer_name, value_expr });
}

fn writePackedScalarPayloadAssumeCapacity(scalar: schema.ScalarType, value_expr: []const u8, writer_name: []const u8, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .double => try writer.print("{s}.writeRawLittleAssumeCapacity(u64, @bitCast({s}))", .{ writer_name, value_expr }),
        .float => try writer.print("{s}.writeRawLittleAssumeCapacity(u32, @bitCast({s}))", .{ writer_name, value_expr }),
        .int32 => try writer.print("{s}.writeVarintAssumeCapacity(@as(u64, @bitCast(@as(i64, {s}))))", .{ writer_name, value_expr }),
        .int64 => try writer.print("{s}.writeVarintAssumeCapacity(@as(u64, @bitCast({s})))", .{ writer_name, value_expr }),
        .uint32 => try writer.print("{s}.writeVarintAssumeCapacity({s})", .{ writer_name, value_expr }),
        .uint64 => try writer.print("{s}.writeVarintAssumeCapacity({s})", .{ writer_name, value_expr }),
        .sint32 => try writer.print("{s}.writeVarintAssumeCapacity(pbz.wire.zigZagEncode32({s}))", .{ writer_name, value_expr }),
        .sint64 => try writer.print("{s}.writeVarintAssumeCapacity(pbz.wire.zigZagEncode64({s}))", .{ writer_name, value_expr }),
        .fixed32 => try writer.print("{s}.writeRawLittleAssumeCapacity(u32, {s})", .{ writer_name, value_expr }),
        .fixed64 => try writer.print("{s}.writeRawLittleAssumeCapacity(u64, {s})", .{ writer_name, value_expr }),
        .sfixed32 => try writer.print("{s}.writeRawLittleAssumeCapacity(i32, {s})", .{ writer_name, value_expr }),
        .sfixed64 => try writer.print("{s}.writeRawLittleAssumeCapacity(i64, {s})", .{ writer_name, value_expr }),
        .bool => try writer.print("{s}.appendByteAssumeCapacity(if ({s}) 1 else 0)", .{ writer_name, value_expr }),
        .string, .bytes => try writer.writeAll("@compileError(\"non-packable scalar\")"),
    }
}

fn writePackedEnumPayloadAssumeCapacity(value_expr: []const u8, writer_name: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.print("{s}.writeVarintAssumeCapacity(@as(u64, @bitCast(@as(i64, {s}))))", .{ writer_name, value_expr });
}

fn writePackedKindPayload(kind: schema.FieldKind, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    switch (kind) {
        .scalar => |scalar| try writePackedScalarPayload(scalar, value_expr, "packed_writer", writer),
        .enumeration => try writePackedEnumPayload(value_expr, "packed_writer", writer),
        else => try writer.writeAll("@compileError(\"non-packable extension\")"),
    }
}

fn writeEncodeMessageField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        if (typedRepeatedMessageFieldWithContext(ctx, field)) |_| {
            try writer.writeAll("for (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.print(") |item| {{ const payload_len = item.encodedSize(); try w.writeTag({d}, .length_delimited); try w.writeVarint(payload_len); try item.writeTo(w); }}\n", .{field.number});
            return;
        }
        if (fieldMessageEncoding(file, field) == .delimited) {
            try writer.writeAll("for (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.print(") |item| {{ try w.writeTag({d}, .start_group); try w.appendSlice(item); try w.writeTag({d}, .end_group); }}\n", .{ field.number, field.number });
        } else {
            try writer.writeAll("for (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.print(") |item| try w.writeMessage({d}, item);\n", .{field.number});
        }
    } else {
        try indent(writer, depth);
        if (typedSingularMessageFieldWithContext(ctx, field)) |_| {
            try writer.writeAll("if (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(") |value| { const payload_len = value.encodedSize(); try w.writeTag(");
            try writer.print("{d}", .{field.number});
            try writer.writeAll(", .length_delimited); try w.writeVarint(payload_len); try value.writeTo(w); }\n");
            return;
        }
        if (fieldMessageEncoding(file, field) == .delimited) {
            try writer.writeAll("if (self.");
            if (hasPresence(file, field.*)) {
                try writePresenceIdent(field.name, writer);
                try writer.writeAll(") { ");
            } else {
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(".len != 0) { ");
            }
            try writer.print("try w.writeTag({d}, .start_group); try w.appendSlice(self.", .{field.number});
            try writeQuotedIdent(field.name, writer);
            try writer.print("); try w.writeTag({d}, .end_group); }}\n", .{field.number});
        } else {
            try writer.writeAll("if (self.");
            if (hasPresence(file, field.*)) {
                try writePresenceIdent(field.name, writer);
                try writer.writeAll(") ");
            } else {
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(".len != 0) ");
            }
            try writer.print("try w.writeMessage({d}, self.", .{field.number});
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(");\n");
        }
    }
}

fn writeEncodeMessageFieldAssumeCapacity(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        if (typedRepeatedMessageFieldWithContext(ctx, field)) |_| {
            try writer.writeAll("for (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.print(") |item| {{ const payload_len = item.encodedSize(); w.writeTagAssumeCapacity({d}, .length_delimited); w.writeVarintAssumeCapacity(payload_len); try item.writeToAssumeCapacity(w); }}\n", .{field.number});
            return;
        }
        try writeEncodeMessageField(ctx, field, writer, depth);
    } else {
        try indent(writer, depth);
        if (typedSingularMessageFieldWithContext(ctx, field)) |_| {
            try writer.writeAll("if (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(") |value| { const payload_len = value.encodedSize(); ");
            if (fieldMessageEncoding(file, field) == .delimited) {
                try writer.print("w.writeTagAssumeCapacity({d}, .start_group); try value.writeToAssumeCapacity(w); w.writeTagAssumeCapacity({d}, .end_group);", .{ field.number, field.number });
            } else {
                try writer.print("w.writeTagAssumeCapacity({d}, .length_delimited); w.writeVarintAssumeCapacity(payload_len); try value.writeToAssumeCapacity(w);", .{field.number});
            }
            try writer.writeAll(" }\n");
            return;
        }
        try writeEncodeMessageField(ctx, field, writer, depth);
    }
}

fn writeEncodeMessageFieldDeterministic(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, type_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        if (typedRepeatedMessageFieldWithContext(ctx, field)) |_| {
            try writer.writeAll("for (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.print(") |item| {{ const payload_len = item.encodedSize(); try w.writeTag({d}, .length_delimited); try w.writeVarint(payload_len); try item.writeDeterministicTo(allocator, w); }}\n", .{field.number});
            return;
        }
        try writer.writeAll("for (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(") |item| { ");
        try writeEncodeMessagePayloadDeterministic(ctx, field.number, fieldMessageEncoding(file, field) == .delimited, type_name, "item", "w", writer);
        try writer.writeAll(" }\n");
    } else {
        try indent(writer, depth);
        if (typedSingularMessageFieldWithContext(ctx, field)) |_| {
            try writer.writeAll("if (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(") |item| { const payload_len = item.encodedSize(); ");
            if (fieldMessageEncoding(file, field) == .delimited) {
                try writer.print("try w.writeTag({d}, .start_group); try item.writeDeterministicTo(allocator, w); try w.writeTag({d}, .end_group);", .{ field.number, field.number });
            } else {
                try writer.print("try w.writeTag({d}, .length_delimited); try w.writeVarint(payload_len); try item.writeDeterministicTo(allocator, w);", .{field.number});
            }
            try writer.writeAll(" }\n");
            return;
        }
        try writer.writeAll("if (self.");
        if (hasPresence(file, field.*)) {
            try writePresenceIdent(field.name, writer);
            try writer.writeAll(") { ");
        } else {
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(".len != 0) { ");
        }
        try writer.writeAll("const item = self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll("; ");
        try writeEncodeMessagePayloadDeterministic(ctx, field.number, fieldMessageEncoding(file, field) == .delimited, type_name, "item", "w", writer);
        try writer.writeAll(" }\n");
    }
}

fn writeEncodeMessageFieldDeterministicAssumeCapacity(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, type_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        if (typedRepeatedMessageFieldWithContext(ctx, field)) |_| {
            try writer.writeAll("for (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.print(") |item| {{ const payload_len = item.encodedSize(); w.writeTagAssumeCapacity({d}, .length_delimited); w.writeVarintAssumeCapacity(payload_len); try item.writeDeterministicToAssumeCapacity(allocator, w); }}\n", .{field.number});
            return;
        }
        try writeEncodeMessageFieldDeterministic(ctx, field, type_name, writer, depth);
    } else {
        try indent(writer, depth);
        if (typedSingularMessageFieldWithContext(ctx, field)) |_| {
            try writer.writeAll("if (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(") |item| { const payload_len = item.encodedSize(); ");
            if (fieldMessageEncoding(file, field) == .delimited) {
                try writer.print("w.writeTagAssumeCapacity({d}, .start_group); try item.writeDeterministicToAssumeCapacity(allocator, w); w.writeTagAssumeCapacity({d}, .end_group);", .{ field.number, field.number });
            } else {
                try writer.print("w.writeTagAssumeCapacity({d}, .length_delimited); w.writeVarintAssumeCapacity(payload_len); try item.writeDeterministicToAssumeCapacity(allocator, w);", .{field.number});
            }
            try writer.writeAll(" }\n");
            return;
        }
        try writeEncodeMessageFieldDeterministic(ctx, field, type_name, writer, depth);
    }
}

fn writeEncodeGroupFieldDeterministic(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, type_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        if (typedRepeatedMessageFieldWithContext(ctx, field)) |_| {
            try writer.writeAll("for (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.print(") |item| {{ try w.writeTag({d}, .start_group); try item.writeDeterministicTo(allocator, w); try w.writeTag({d}, .end_group); }}\n", .{ field.number, field.number });
        } else {
            try writer.writeAll("for (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(") |item| { ");
            try writeEncodeMessagePayloadDeterministic(ctx, field.number, true, type_name, "item", "w", writer);
            try writer.writeAll(" }\n");
        }
    } else {
        try indent(writer, depth);
        if (typedSingularMessageFieldWithContext(ctx, field)) |_| {
            try writer.writeAll("if (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.print(") |item| {{ try w.writeTag({d}, .start_group); try item.writeDeterministicTo(allocator, w); try w.writeTag({d}, .end_group); }}\n", .{ field.number, field.number });
        } else {
            try writer.writeAll("if (self.");
            try writePresenceIdent(field.name, writer);
            try writer.writeAll(") { const item = self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll("; ");
            try writeEncodeMessagePayloadDeterministic(ctx, field.number, true, type_name, "item", "w", writer);
            try writer.writeAll(" }\n");
        }
    }
}

fn writeEncodeGroupFieldDeterministicAssumeCapacity(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, type_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        if (typedRepeatedMessageFieldWithContext(ctx, field)) |_| {
            try writer.writeAll("for (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.print(") |item| {{ w.writeTagAssumeCapacity({d}, .start_group); try item.writeDeterministicToAssumeCapacity(allocator, w); w.writeTagAssumeCapacity({d}, .end_group); }}\n", .{ field.number, field.number });
            return;
        }
        try writeEncodeGroupFieldDeterministic(ctx, field, type_name, writer, depth);
    } else {
        try indent(writer, depth);
        if (typedSingularMessageFieldWithContext(ctx, field)) |_| {
            try writer.writeAll("if (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.print(") |item| {{ w.writeTagAssumeCapacity({d}, .start_group); try item.writeDeterministicToAssumeCapacity(allocator, w); w.writeTagAssumeCapacity({d}, .end_group); }}\n", .{ field.number, field.number });
            return;
        }
        try writeEncodeGroupFieldDeterministic(ctx, field, type_name, writer, depth);
    }
}

fn writeEncodeGroupFieldAssumeCapacity(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        if (typedRepeatedMessageFieldWithContext(ctx, field)) |_| {
            try writer.writeAll("for (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.print(") |item| {{ w.writeTagAssumeCapacity({d}, .start_group); try item.writeToAssumeCapacity(w); w.writeTagAssumeCapacity({d}, .end_group); }}\n", .{ field.number, field.number });
            return;
        }
        try writeEncodeGroupField(ctx, field, writer, depth);
    } else {
        try indent(writer, depth);
        if (typedSingularMessageFieldWithContext(ctx, field)) |_| {
            try writer.writeAll("if (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.print(") |value| {{ w.writeTagAssumeCapacity({d}, .start_group); try value.writeToAssumeCapacity(w); w.writeTagAssumeCapacity({d}, .end_group); }}\n", .{ field.number, field.number });
            return;
        }
        try writeEncodeGroupField(ctx, field, writer, depth);
    }
}

fn writeEncodeMessagePayloadDeterministic(ctx: *const CodegenContext, number: u29, delimited: bool, type_name: []const u8, payload_expr: []const u8, writer_name: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("var _pbz_nested = try ");
    try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    try writer.writeAll(".decode(allocator, ");
    try writer.writeAll(payload_expr);
    try writer.writeAll("); defer _pbz_nested.deinit(allocator); const payload = try _pbz_nested.encodeDeterministic(allocator); defer allocator.free(payload); ");
    if (delimited) {
        try writer.print("try {s}.writeTag({d}, .start_group); try {s}.appendSlice(payload); try {s}.writeTag({d}, .end_group);", .{ writer_name, number, writer_name, writer_name, number });
    } else {
        try writer.print("try {s}.writeMessage({d}, payload);", .{ writer_name, number });
    }
}

fn writeEncodeGroupField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        if (typedRepeatedMessageFieldWithContext(ctx, field)) |_| {
            try writer.writeAll("for (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.print(") |item| {{ try w.writeTag({d}, .start_group); try item.writeTo(w); try w.writeTag({d}, .end_group); }}\n", .{ field.number, field.number });
        } else {
            try writer.writeAll("for (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.print(") |item| {{ try w.writeTag({d}, .start_group); try w.appendSlice(item); try w.writeTag({d}, .end_group); }}\n", .{ field.number, field.number });
        }
    } else {
        try indent(writer, depth);
        if (typedSingularMessageFieldWithContext(ctx, field)) |_| {
            try writer.writeAll("if (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.print(") |value| {{ try w.writeTag({d}, .start_group); try value.writeTo(w); try w.writeTag({d}, .end_group); }}\n", .{ field.number, field.number });
        } else {
            try writer.writeAll("if (self.");
            try writePresenceIdent(field.name, writer);
            try writer.print(") {{ try w.writeTag({d}, .start_group); try w.appendSlice(self.", .{field.number});
            try writeQuotedIdent(field.name, writer);
            try writer.print("); try w.writeTag({d}, .end_group); }}\n", .{field.number});
        }
    }
}

fn writeEncodeMapField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try writeEncodeMapEntries(ctx, field, "w", false, writer, depth);
}

fn writeEncodeMapFieldAssumeCapacity(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try writeEncodeMapEntries(ctx, field, "w", true, writer, depth);
}

fn writeEncodeMapEntries(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer_name: []const u8, assume_capacity: bool, writer: *std.Io.Writer, depth: usize) Error!void {
    const map_type = switch (field.kind) {
        .map => |map| map,
        else => return,
    };
    try indent(writer, depth);
    try writer.writeAll("{ var map_it = self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".iterator(); while (map_it.next()) |map_entry| {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const entry = ");
    try writeQuotedIdentWithSuffix(field.name, "Entry", writer);
    try writer.writeAll("{ .key = map_entry.key_ptr.*, .value = map_entry.value_ptr.* };\n");
    try writeEncodeMapEntryBody(ctx, field, map_type, writer_name, assume_capacity, writer, depth + 1);
    try indent(writer, depth);
    try writer.writeAll("} }\n");
}

fn writeEncodeMapFieldDeterministic(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try writeEncodeMapFieldDeterministicCommon(ctx, field, "w", false, writer, depth);
}

fn writeEncodeMapFieldDeterministicAssumeCapacity(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try writeEncodeMapFieldDeterministicCommon(ctx, field, "w", true, writer, depth);
}

fn writeEncodeMapFieldDeterministicCommon(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer_name: []const u8, assume_capacity: bool, writer: *std.Io.Writer, depth: usize) Error!void {
    const map_type = switch (field.kind) {
        .map => |map| map,
        else => return,
    };
    try indent(writer, depth);
    try writer.writeAll("if (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".count() != 0) {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const insertion_sort_limit: usize = 32;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const stack_entry_count: usize = @max(insertion_sort_limit, (32 * 1024) / @max(@sizeOf(");
    try writeQuotedIdentWithSuffix(field.name, "Entry", writer);
    try writer.writeAll("), 1));\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var stack_entries: [stack_entry_count]");
    try writeQuotedIdentWithSuffix(field.name, "Entry", writer);
    try writer.writeAll(" = undefined;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const use_stack_entries = self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".count() <= stack_entries.len;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const entries = if (use_stack_entries) blk: { var map_it = self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".iterator(); var i: usize = 0; while (map_it.next()) |entry| : (i += 1) stack_entries[i] = .{ .key = entry.key_ptr.*, .value = entry.value_ptr.* }; break :blk stack_entries[0..self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".count()]; } else blk: { const owned = try allocator.alloc(");
    try writeQuotedIdentWithSuffix(field.name, "Entry", writer);
    try writer.writeAll(", self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".count()); var map_it = self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".iterator(); var i: usize = 0; while (map_it.next()) |entry| : (i += 1) owned[i] = .{ .key = entry.key_ptr.*, .value = entry.value_ptr.* }; break :blk owned; };\n");
    try indent(writer, depth + 1);
    try writer.writeAll("defer if (!use_stack_entries) allocator.free(entries);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (entries.len <= insertion_sort_limit) {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("var sort_i: usize = 1;\n");
    try indent(writer, depth + 2);
    try writer.writeAll("while (sort_i < entries.len) : (sort_i += 1) {\n");
    try indent(writer, depth + 3);
    try writer.writeAll("const item = entries[sort_i];\n");
    try indent(writer, depth + 3);
    try writer.writeAll("var sort_j = sort_i;\n");
    try indent(writer, depth + 3);
    try writer.writeAll("while (sort_j > 0 and ");
    try writeMapKeyLessExpr(map_type.key, "item.key", "entries[sort_j - 1].key", writer);
    try writer.writeAll(") : (sort_j -= 1) entries[sort_j] = entries[sort_j - 1];\n");
    try indent(writer, depth + 3);
    try writer.writeAll("entries[sort_j] = item;\n");
    try indent(writer, depth + 2);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("} else {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("const entries_already_sorted = sorted: {\n");
    try indent(writer, depth + 3);
    try writer.writeAll("var check_i: usize = 1;\n");
    try indent(writer, depth + 3);
    try writer.writeAll("while (check_i < entries.len) : (check_i += 1) {\n");
    try indent(writer, depth + 4);
    try writer.writeAll("if (");
    try writeMapKeyLessExpr(map_type.key, "entries[check_i].key", "entries[check_i - 1].key", writer);
    try writer.writeAll(") break :sorted false;\n");
    try indent(writer, depth + 3);
    try writer.writeAll("}\n");
    try indent(writer, depth + 3);
    try writer.writeAll("break :sorted true;\n");
    try indent(writer, depth + 2);
    try writer.writeAll("};\n");
    try indent(writer, depth + 2);
    try writer.writeAll("if (!entries_already_sorted) {\n");
    try indent(writer, depth + 3);
    // Keep tiny maps on an unrolled allocation-free insertion sort, but sort
    // larger stack-backed maps with the std stable sort. The stack buffer only
    // avoids allocator traffic; it should not force O(n^2) behavior for the
    // large deterministic-map benchmark.
    try writer.writeAll("std.mem.sort(");
    try writeQuotedIdentWithSuffix(field.name, "Entry", writer);
    try writer.writeAll(", entries, {}, struct { fn lessThan(_: void, a: ");
    try writeQuotedIdentWithSuffix(field.name, "Entry", writer);
    try writer.writeAll(", b: ");
    try writeQuotedIdentWithSuffix(field.name, "Entry", writer);
    try writer.writeAll(") bool { return ");
    try writeMapKeyLessExpr(map_type.key, "a.key", "b.key", writer);
    try writer.writeAll("; } }.lessThan);\n");
    try indent(writer, depth + 2);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("for (entries) |entry| {\n");
    try writeEncodeMapEntryBody(ctx, field, map_type, writer_name, assume_capacity, writer, depth + 2);
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeEncodeMapEntryBody(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, map_type: schema.MapType, writer_name: []const u8, assume_capacity: bool, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    try writeMapEntryEncodeUtf8Check(file, field, "entry.key", .{ .scalar = map_type.key }, writer, depth);
    try writeMapEntryEncodeUtf8Check(file, field, "entry.value", map_type.value.*, writer, depth);
    try indent(writer, depth);
    try writer.writeAll("const entry_len = ");
    try writeMapEntryFieldSizeExpr(1, .{ .scalar = map_type.key }, "entry.key", writer);
    try writer.writeAll(" + ");
    try writeMapEntryValueFieldSizeExpr(ctx, field, "entry.value", writer);
    try writer.writeAll(";\n");
    try indent(writer, depth);
    if (assume_capacity) {
        try writer.print("{s}.writeTagAssumeCapacity({d}, .length_delimited);\n", .{ writer_name, field.number });
        try indent(writer, depth);
        try writer.print("{s}.writeVarintAssumeCapacity(entry_len);\n", .{writer_name});
        try indent(writer, depth);
        try writeKindWriteCallAssumeCapacity(1, .{ .scalar = map_type.key }, "entry.key", writer_name, writer);
        try writer.writeAll(";\n");
    } else {
        try writer.print("try {s}.writeTag({d}, .length_delimited);\n", .{ writer_name, field.number });
        try indent(writer, depth);
        try writer.print("try {s}.writeVarint(entry_len);\n", .{writer_name});
        try indent(writer, depth);
        try writeKindWriteCall(1, .{ .scalar = map_type.key }, "entry.key", writer_name, writer);
        try writer.writeAll(");\n");
    }
    try indent(writer, depth);
    try writeMapEntryValueWriteCall(ctx, field, "entry.value", writer_name, assume_capacity, writer);
}

fn writeMapEntryEncodeUtf8Check(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, value_expr: []const u8, kind: schema.FieldKind, writer: *std.Io.Writer, depth: usize) Error!void {
    if (kind == .scalar and kind.scalar == .string and fieldUtf8Validation(file, field) == .verify) {
        try indent(writer, depth);
        try writer.print("if (!pbz.validateUtf8({s})) return error.InvalidUtf8;\n", .{value_expr});
    }
}

fn writeMapKeyLessExpr(scalar: schema.ScalarType, a: []const u8, b: []const u8, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .string => try writer.print("pbz.wire.bytesLessThan({s}, {s})", .{ a, b }),
        .bool => try writer.print("!{s} and {s}", .{ a, b }),
        .int32, .int64, .uint32, .uint64, .sint32, .sint64, .fixed32, .fixed64, .sfixed32, .sfixed64 => try writer.print("{s} < {s}", .{ a, b }),
        .double, .float, .bytes => try writer.writeAll("false"),
    }
}

fn writeMapEntryValueFieldSizeExpr(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    const map_type = field.kind.map;
    if (typedMapMessageValueWithContext(ctx, field)) |_| {
        try writer.print("blk: {{ const value_len = {s}.encodedSize(); break :blk 1 + pbz.wire.encodedVarintSize(value_len) + value_len; }}", .{value_expr});
    } else {
        try writeMapEntryFieldSizeExpr(2, map_type.value.*, value_expr, writer);
    }
}

fn writeMapEntryValueWriteCall(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, value_expr: []const u8, writer_name: []const u8, assume_capacity: bool, writer: *std.Io.Writer) Error!void {
    const map_type = field.kind.map;
    if (typedMapMessageValueWithContext(ctx, field)) |_| {
        if (assume_capacity) {
            try writer.print("{{ const value_len = {s}.encodedSize(); {s}.writeTagAssumeCapacity(2, .length_delimited); {s}.writeVarintAssumeCapacity(value_len); try {s}.writeToAssumeCapacity({s}); }}\n", .{ value_expr, writer_name, writer_name, value_expr, writer_name });
        } else {
            try writer.print("{{ const value_len = {s}.encodedSize(); try {s}.writeTag(2, .length_delimited); try {s}.writeVarint(value_len); try {s}.writeTo({s}); }}\n", .{ value_expr, writer_name, writer_name, value_expr, writer_name });
        }
    } else {
        if (assume_capacity) {
            try writeKindWriteCallAssumeCapacity(2, map_type.value.*, value_expr, writer_name, writer);
            try writer.writeAll(";\n");
        } else {
            try writeKindWriteCall(2, map_type.value.*, value_expr, writer_name, writer);
            try writer.writeAll(");\n");
        }
    }
}

fn writeMapEntryFieldSizeExpr(number: u29, kind: schema.FieldKind, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    const tag_size = wire.tagSize(number, kind.wireType()) catch unreachable;
    try writer.print("{d} + ", .{tag_size});
    if (kind == .scalar and kind.scalar == .bool) {
        // Map-entry encoded-size loops bind both key and value once so the
        // generated shape remains uniform across scalar key/value kinds.  Bool
        // payload size is always one byte, but mention the expression so Zig's
        // unused-local analysis does not reject `map<bool, ...>` entries.
        return try writer.print("(if ({s}) @as(usize, 1) else @as(usize, 1))", .{value_expr});
    }
    try writeKindPayloadSizeExpr(kind, value_expr, writer);
}

fn writeKindPayloadSizeExpr(kind: schema.FieldKind, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    switch (kind) {
        .scalar => |scalar| try writeScalarPayloadSizeExpr(scalar, value_expr, writer),
        .enumeration => try writer.print("pbz.wire.encodedVarintSize(@as(u64, @bitCast(@as(i64, {s}))))", .{value_expr}),
        .message => try writer.print("pbz.wire.encodedVarintSize({s}.len) + {s}.len", .{ value_expr, value_expr }),
        else => try writer.writeAll("@compileError(\"unsupported map field kind\")"),
    }
}

fn writeScalarPayloadSizeExpr(scalar: schema.ScalarType, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .double, .fixed64, .sfixed64 => try writer.writeAll("8"),
        .float, .fixed32, .sfixed32 => try writer.writeAll("4"),
        .int32 => try writer.print("pbz.wire.encodedVarintSize(@as(u64, @bitCast(@as(i64, {s}))))", .{value_expr}),
        .int64 => try writer.print("pbz.wire.encodedVarintSize(@as(u64, @bitCast({s})))", .{value_expr}),
        .uint32, .uint64 => try writer.print("pbz.wire.encodedVarintSize({s})", .{value_expr}),
        .sint32 => try writer.print("pbz.wire.encodedVarintSize(pbz.wire.zigZagEncode32({s}))", .{value_expr}),
        .sint64 => try writer.print("pbz.wire.encodedVarintSize(pbz.wire.zigZagEncode64({s}))", .{value_expr}),
        .bool => try writer.print("(if ({s}) @as(usize, 1) else @as(usize, 1))", .{value_expr}),
        .string, .bytes => try writer.print("pbz.wire.encodedVarintSize({s}.len) + {s}.len", .{ value_expr, value_expr }),
    }
}

fn writeKindWriteCall(number: u29, kind: schema.FieldKind, value_expr: []const u8, writer_name: []const u8, writer: *std.Io.Writer) Error!void {
    switch (kind) {
        .scalar => |scalar| try writer.print("try {s}.{s}({d}, {s}", .{ writer_name, scalarWriterName(scalar), number, value_expr }),
        .enumeration => try writer.print("try {s}.writeInt32({d}, {s}", .{ writer_name, number, value_expr }),
        .message => try writer.print("try {s}.writeMessage({d}, {s}", .{ writer_name, number, value_expr }),
        else => try writer.writeAll("@compileError(\"unsupported map field kind\")"),
    }
}

fn writeKindWriteCallAssumeCapacity(number: u29, kind: schema.FieldKind, value_expr: []const u8, writer_name: []const u8, writer: *std.Io.Writer) Error!void {
    switch (kind) {
        .scalar => |scalar| try writer.print("{s}.{s}AssumeCapacity({d}, {s})", .{ writer_name, scalarWriterName(scalar), number, value_expr }),
        .enumeration => try writer.print("{s}.writeInt32AssumeCapacity({d}, {s})", .{ writer_name, number, value_expr }),
        .message => try writer.print("{s}.writeMessageAssumeCapacity({d}, {s})", .{ writer_name, number, value_expr }),
        else => try writer.writeAll("@compileError(\"unsupported map field kind\")"),
    }
}

fn writeMessagePayloadRead(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, reader_name: []const u8, writer: *std.Io.Writer) Error!void {
    if (field.kind == .group) {
        try writer.print("try {s}.readGroupBytes({d})", .{ reader_name, field.number });
        return;
    }
    if (fieldMessageEncoding(file, field) == .delimited) {
        try writer.print("try {s}.readGroupBytes({d})", .{ reader_name, field.number });
    } else {
        try writer.print("try {s}.readBytes()", .{reader_name});
    }
}

pub fn fieldMessageEncoding(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor) schema.FeatureSet.MessageEncoding {
    return schema.FeatureSet.effective(field.features, file.features).message_encoding;
}

pub fn fieldUtf8Validation(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor) schema.FeatureSet.Utf8Validation {
    return schema.FeatureSet.effective(field.features, file.features).utf8_validation;
}

pub fn fieldUtf8ValidationOptional(file: *const schema.FileDescriptor, field: ?*const schema.FieldDescriptor) schema.FeatureSet.Utf8Validation {
    if (field) |descriptor| return fieldUtf8Validation(file, descriptor);
    return file.features.utf8_validation;
}

pub fn writeScalarWriteCall(number: u29, scalar: schema.ScalarType, prefix: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.print("try w.{s}({d}, {s}", .{ scalarWriterName(scalar), number, prefix });
}

pub fn writeScalarWriteCallAssumeCapacity(number: u29, scalar: schema.ScalarType, prefix: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.print("w.{s}AssumeCapacity({d}, {s}", .{ scalarWriterName(scalar), number, prefix });
}

/// Emit a default-skip condition for implicit-presence scalar fields. Floats
/// compare their bit pattern so `-0.0` is serialized instead of being treated
/// as the zero default.
pub fn writeScalarSkipCondition(receiver: []const u8, field_name: []const u8, scalar: schema.ScalarType, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .string, .bytes => {
            try writer.writeAll("if (");
            try writer.writeAll(receiver);
            try writeQuotedIdent(field_name, writer);
            try writer.writeAll(".len != 0) ");
        },
        .bool => {
            try writer.writeAll("if (");
            try writer.writeAll(receiver);
            try writeQuotedIdent(field_name, writer);
            try writer.writeAll(") ");
        },
        .float => {
            try writer.writeAll("if (@as(u32, @bitCast(");
            try writer.writeAll(receiver);
            try writeQuotedIdent(field_name, writer);
            try writer.writeAll(")) != 0) ");
        },
        .double => {
            try writer.writeAll("if (@as(u64, @bitCast(");
            try writer.writeAll(receiver);
            try writeQuotedIdent(field_name, writer);
            try writer.writeAll(")) != 0) ");
        },
        else => {
            try writer.writeAll("if (");
            try writer.writeAll(receiver);
            try writeQuotedIdent(field_name, writer);
            try writer.writeAll(" != 0) ");
        },
    }
}

pub fn writeScalarSkipConditionWithOptions(receiver: []const u8, field_name: []const u8, scalar: schema.ScalarType, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .string, .bytes => {
            try writer.writeAll("if (");
            try writer.writeAll(receiver);
            try writeQuotedIdent(field_name, writer);
            try writer.writeAll(".len != 0 or options.always_print_primitive_fields) ");
        },
        .bool => {
            try writer.writeAll("if (");
            try writer.writeAll(receiver);
            try writeQuotedIdent(field_name, writer);
            try writer.writeAll(" or options.always_print_primitive_fields) ");
        },
        .float => {
            try writer.writeAll("if (@as(u32, @bitCast(");
            try writer.writeAll(receiver);
            try writeQuotedIdent(field_name, writer);
            try writer.writeAll(")) != 0 or options.always_print_primitive_fields) ");
        },
        .double => {
            try writer.writeAll("if (@as(u64, @bitCast(");
            try writer.writeAll(receiver);
            try writeQuotedIdent(field_name, writer);
            try writer.writeAll(")) != 0 or options.always_print_primitive_fields) ");
        },
        else => {
            try writer.writeAll("if (");
            try writer.writeAll(receiver);
            try writeQuotedIdent(field_name, writer);
            try writer.writeAll(" != 0 or options.always_print_primitive_fields) ");
        },
    }
}

fn shouldSkipDefault(scalar: schema.ScalarType) bool {
    _ = scalar;
    return true;
}

fn scalarWriterName(scalar: schema.ScalarType) []const u8 {
    return switch (scalar) {
        .double => "writeDouble",
        .float => "writeFloat",
        .int32 => "writeInt32",
        .int64 => "writeInt64",
        .uint32 => "writeUInt32",
        .uint64 => "writeUInt64",
        .sint32 => "writeSInt32",
        .sint64 => "writeSInt64",
        .fixed32 => "writeFixed32",
        .fixed64 => "writeFixed64",
        .sfixed32 => "writeSFixed32",
        .sfixed64 => "writeSFixed64",
        .bool => "writeBool",
        .string => "writeString",
        .bytes => "writeBytes",
    };
}

fn writeFieldType(field: schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    if (field.kind == .map) {
        try writeQuotedIdentWithSuffix(field.name, "Map", writer);
        return;
    }
    try writer.writeAll(fieldType(field));
}

fn writeMapStorageType(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    const map_type = switch (field.kind) {
        .map => |map| map,
        else => return,
    };
    if (map_type.key == .string) {
        try writer.writeAll("std.StringArrayHashMapUnmanaged(");
    } else {
        try writer.writeAll("std.AutoArrayHashMapUnmanaged(");
        try writer.writeAll(scalarZigType(map_type.key));
        try writer.writeAll(", ");
    }
    try writeMapValueType(ctx, field, writer);
    try writer.writeAll(")");
}

fn writeMapValueType(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    const map_type = switch (field.kind) {
        .map => |map| map,
        else => return,
    };
    if (typedMapMessageValueWithContext(ctx, field)) |type_name| {
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    } else {
        try writeFieldKindType(map_type.value.*, writer);
    }
}

fn writeFieldKindType(kind: schema.FieldKind, writer: *std.Io.Writer) Error!void {
    switch (kind) {
        .scalar => |scalar| try writer.writeAll(scalarZigType(scalar)),
        .enumeration => try writer.writeAll("i32"),
        .message, .group => try writer.writeAll("[]const u8"),
        else => try writer.writeAll("void"),
    }
}

fn fieldType(field: schema.FieldDescriptor) []const u8 {
    const base = switch (field.kind) {
        .scalar => |scalar| scalarZigType(scalar),
        .enumeration => "i32",
        .message, .group => "[]const u8",
        else => "void",
    };
    if (field.cardinality != .repeated) return base;
    return switch (field.kind) {
        .scalar => |scalar| repeatedScalarZigType(scalar),
        .enumeration => "[]const i32",
        .message, .group => "[]const []const u8",
        else => "[]const void",
    };
}

fn repeatedScalarZigType(scalar: schema.ScalarType) []const u8 {
    return switch (scalar) {
        .string, .bytes => "[]const []const u8",
        else => repeatedPrefix(scalarZigType(scalar)),
    };
}

fn repeatedPrefix(base: []const u8) []const u8 {
    if (std.mem.eql(u8, base, "f64")) return "[]const f64";
    if (std.mem.eql(u8, base, "f32")) return "[]const f32";
    if (std.mem.eql(u8, base, "i32")) return "[]const i32";
    if (std.mem.eql(u8, base, "i64")) return "[]const i64";
    if (std.mem.eql(u8, base, "u32")) return "[]const u32";
    if (std.mem.eql(u8, base, "u64")) return "[]const u64";
    if (std.mem.eql(u8, base, "bool")) return "[]const bool";
    return "[]const void";
}

fn scalarZigType(scalar: schema.ScalarType) []const u8 {
    return switch (scalar) {
        .double => "f64",
        .float => "f32",
        .int32, .sint32, .sfixed32 => "i32",
        .int64, .sint64, .sfixed64 => "i64",
        .uint32, .fixed32 => "u32",
        .uint64, .fixed64 => "u64",
        .bool => "bool",
        .string, .bytes => "[]const u8",
    };
}

pub fn writeFieldDefault(file: *const schema.FileDescriptor, field: schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    if (field.kind == .map) return writer.writeAll(".empty");
    if (field.cardinality == .repeated) return writer.writeAll("&.{}");
    try writeFieldKindDefault(file, field.kind, field.default_value, writer);
}

fn writeFieldKindDefault(file: ?*const schema.FileDescriptor, kind: schema.FieldKind, default_value: ?schema.OptionValue, writer: *std.Io.Writer) Error!void {
    switch (kind) {
        .scalar => |scalar| try writeScalarDefault(scalar, default_value, writer),
        .enumeration => |name| try writeEnumDefault(file, name, default_value, writer),
        .message, .group => try writer.writeAll("\"\""),
        else => try writer.writeAll("{}"),
    }
}

fn writeEnumDefault(file: ?*const schema.FileDescriptor, enum_name: []const u8, default_value: ?schema.OptionValue, writer: *std.Io.Writer) Error!void {
    if (optionInt(i32, default_value)) |value| return try writer.print("{d}", .{value});
    if (file) |schema_file| {
        if (schema_file.findEnumDeep(enum_name)) |enumeration| {
            if (enumeration.values.items.len != 0) return try writer.print("{d}", .{enumeration.values.items[0].number});
        }
    }
    try writer.writeAll("0");
}

fn writeScalarDefault(scalar: schema.ScalarType, default_value: ?schema.OptionValue, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .double => try writeFloatDefault(f64, default_value, writer),
        .float => try writeFloatDefault(f32, default_value, writer),
        .int32, .sint32, .sfixed32 => try writeIntDefault(i32, default_value, writer),
        .int64, .sint64, .sfixed64 => try writeIntDefault(i64, default_value, writer),
        .uint32, .fixed32 => try writeIntDefault(u32, default_value, writer),
        .uint64, .fixed64 => try writeIntDefault(u64, default_value, writer),
        .bool => try writeBoolDefault(default_value, writer),
        .string, .bytes => try writeBytesDefault(default_value, writer),
    }
}

fn writeIntDefault(comptime T: type, default_value: ?schema.OptionValue, writer: *std.Io.Writer) Error!void {
    const value = optionInt(T, default_value) orelse 0;
    try writer.print("{d}", .{value});
}

fn writeFloatDefault(comptime T: type, default_value: ?schema.OptionValue, writer: *std.Io.Writer) Error!void {
    const value = optionFloat(T, default_value) orelse 0;
    if (std.math.isNan(value)) {
        try writer.print("std.math.nan({s})", .{scalarZigTypeName(T)});
    } else if (std.math.isPositiveInf(value)) {
        try writer.print("std.math.inf({s})", .{scalarZigTypeName(T)});
    } else if (std.math.isNegativeInf(value)) {
        try writer.print("-std.math.inf({s})", .{scalarZigTypeName(T)});
    } else {
        // Use scientific notation so integer-valued defaults (for example 9e9)
        // stay float literals instead of invalid `f32 = 9000000000` text.
        try writer.print("{e}", .{value});
    }
}

fn scalarZigTypeName(comptime T: type) []const u8 {
    return if (T == f32) "f32" else "f64";
}

fn writeBoolDefault(default_value: ?schema.OptionValue, writer: *std.Io.Writer) Error!void {
    const value = optionBool(default_value) orelse false;
    try writer.writeAll(if (value) "true" else "false");
}

fn writeBytesDefault(default_value: ?schema.OptionValue, writer: *std.Io.Writer) Error!void {
    const value = optionText(default_value) orelse "";
    try writeZigStringLiteral(value, writer);
}

fn optionText(default_value: ?schema.OptionValue) ?[]const u8 {
    const value = default_value orelse return null;
    return switch (value) {
        .string, .identifier => |text| text,
        else => null,
    };
}

fn writeOptionValueTextLiteral(default_value: ?schema.OptionValue, writer: *std.Io.Writer) Error!void {
    const value = default_value orelse return try writer.writeAll("\"\"");
    switch (value) {
        .string, .identifier => |text| try writeZigStringLiteral(text, writer),
        .integer => |v| try writer.print("\"{d}\"", .{v}),
        .unsigned_integer => |v| try writer.print("\"{d}\"", .{v}),
        .float => |v| try writer.print("\"{d}\"", .{v}),
        .boolean => |v| try writer.writeAll(if (v) "\"true\"" else "\"false\""),
        .aggregate => |text| try writeZigStringLiteral(text, writer),
    }
}

fn optionBool(default_value: ?schema.OptionValue) ?bool {
    const value = default_value orelse return null;
    return schema.optionAsBool(value);
}

fn optionInt(comptime T: type, default_value: ?schema.OptionValue) ?T {
    const value = default_value orelse return null;
    return switch (value) {
        .integer => |v| if (v >= std.math.minInt(T) and v <= std.math.maxInt(T)) @intCast(v) else null,
        .unsigned_integer => |v| if (v <= std.math.maxInt(T)) @intCast(v) else null,
        .identifier, .string => |text| parseIntegerDefault(T, text) catch null,
        else => null,
    };
}

fn optionFloat(comptime T: type, default_value: ?schema.OptionValue) ?T {
    const value = default_value orelse return null;
    return switch (value) {
        .float => |v| @floatCast(v),
        .integer => |v| @floatFromInt(v),
        .unsigned_integer => |v| @floatFromInt(v),
        .identifier, .string => |text| parseSpecialFloatDefault(T, text) orelse (std.fmt.parseFloat(T, text) catch null),
        else => null,
    };
}

fn parseSpecialFloatDefault(comptime T: type, text: []const u8) ?T {
    var body = text;
    var negative = false;
    if (body.len != 0 and (body[0] == '-' or body[0] == '+')) {
        negative = body[0] == '-';
        body = body[1..];
    }
    if (std.ascii.eqlIgnoreCase(body, "inf") or std.ascii.eqlIgnoreCase(body, "infinity")) {
        const value = std.math.inf(T);
        return if (negative) -value else value;
    }
    if (std.ascii.eqlIgnoreCase(body, "nan")) return std.math.nan(T);
    return null;
}

fn parseIntegerDefault(comptime T: type, text: []const u8) !T {
    if (text.len == 0) return error.InvalidCharacter;
    var body = text;
    if (body[0] == '+' or body[0] == '-') {
        body = body[1..];
        if (body.len == 0) return error.InvalidCharacter;
    }
    if (body.len > 1 and body[0] == '0') {
        switch (body[1]) {
            'x', 'X', 'o', 'O', 'b', 'B' => return std.fmt.parseInt(T, text, 0),
            else => return std.fmt.parseInt(T, text, 8),
        }
    }
    return std.fmt.parseInt(T, text, 10);
}

pub fn writeZigStringLiteral(value: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeByte('"');
    for (value) |c| {
        switch (c) {
            '\\' => try writer.writeAll("\\\\"),
            '"' => try writer.writeAll("\\\""),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            0 => try writer.writeAll("\\x00"),
            0x01...0x08, 0x0b, 0x0c, 0x0e...0x1f, 0x7f...0xff => try writer.print("\\x{x:0>2}", .{c}),
            else => try writer.writeByte(c),
        }
    }
    try writer.writeByte('"');
}

pub fn writeZigLowerCamelStringLiteral(value: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeByte('"');
    try writeLowerCamelEscaped(value, writer);
    try writer.writeByte('"');
}

pub fn writeJsonFieldNameLiteralContents(field: *const schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    if (field.json_name) |json_name| {
        try writeEscapedStringContents(json_name, writer);
    } else {
        try writeLowerCamelEscaped(field.name, writer);
    }
}

fn writeLowerCamelEscaped(value: []const u8, writer: *std.Io.Writer) Error!void {
    var upper_next = false;
    for (value) |c| {
        if (c == '_') {
            upper_next = true;
            continue;
        }
        const out = if (upper_next) std.ascii.toUpper(c) else c;
        upper_next = false;
        try writeEscapedStringChar(out, writer);
    }
}

pub fn writeEscapedStringContents(value: []const u8, writer: *std.Io.Writer) Error!void {
    for (value) |c| try writeEscapedStringChar(c, writer);
}

fn writeEscapedStringChar(c: u8, writer: *std.Io.Writer) Error!void {
    switch (c) {
        '\\' => try writer.writeAll("\\\\"),
        '"' => try writer.writeAll("\\\""),
        '\n' => try writer.writeAll("\\n"),
        '\r' => try writer.writeAll("\\r"),
        '\t' => try writer.writeAll("\\t"),
        0 => try writer.writeAll("\\x00"),
        0x01...0x08, 0x0b, 0x0c, 0x0e...0x1f, 0x7f...0xff => try writer.print("\\x{x:0>2}", .{c}),
        else => try writer.writeByte(c),
    }
}

fn writeMessageDynamicBridge(ctx: *const CodegenContext, writer: *std.Io.Writer, depth: usize) Error!void {
    if (!ctx.emit_descriptor) return;
    try indent(writer, depth);
    try writer.writeAll("/// Convert to a dynamic message via the wire format for reflection workflows.\n");
    try indent(writer, depth);
    try writer.writeAll("pub fn toDynamic(self: @This(), allocator: std.mem.Allocator, file: *const pbz.schema.FileDescriptor) !pbz.DynamicMessage {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const message_descriptor = @This().descriptor(file) orelse return error.TypeMismatch;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var writer = pbz.Writer.init(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("defer writer.deinit();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.writeTo(&writer);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var message = pbz.DynamicMessage.init(allocator, message_descriptor);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer message.deinit();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try message.decode(file, writer.slice());\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return message;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");
    try indent(writer, depth);
    try writer.writeAll("/// Build from a dynamic message via the wire format. `file` must be the\n");
    try indent(writer, depth);
    try writer.writeAll("/// same decoded descriptor used to create `message`.\n");
    try indent(writer, depth);
    try writer.writeAll("pub fn fromDynamic(allocator: std.mem.Allocator, file: *const pbz.schema.FileDescriptor, message: *const pbz.DynamicMessage) !@This() {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const message_descriptor = @This().descriptor(file) orelse return error.TypeMismatch;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (message.descriptor != message_descriptor) return error.TypeMismatch;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var writer = pbz.Writer.init(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("defer writer.deinit();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try message.encode(file, &writer);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try @This().decodeOwned(allocator, writer.slice());\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");
}

fn writeMessageConformantParsers(ctx: *const CodegenContext, writer: *std.Io.Writer, depth: usize) Error!void {
    if (!ctx.emit_descriptor) return;
    if (ctx.emit_text) {
        try indent(writer, depth);
        try writer.writeAll("/// Full TextFormat parser backed by the dynamic parser. parseText falls\n");
        try indent(writer, depth);
        try writer.writeAll("/// back to this parser when the fast line-oriented path cannot parse.\n");
        try indent(writer, depth);
        try writer.writeAll("pub fn parseTextConformant(allocator: std.mem.Allocator, text: []const u8) !@This() {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return try @This().parseTextConformantWithOptions(allocator, text, .{});\n");
        try indent(writer, depth);
        try writer.writeAll("}\n\n");
    }
    if (ctx.emit_json) {
        try indent(writer, depth);
        try writer.writeAll("/// Full JSON parser backed by the dynamic parser.\n");
        try indent(writer, depth);
        try writer.writeAll("pub fn jsonParseConformant(allocator: std.mem.Allocator, text: []const u8) !@This() {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("var file = try pbz_generated_file.decodeFileDescriptor(allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("defer file.deinit();\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const message_descriptor = @This().descriptor(&file) orelse return error.TypeMismatch;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("var dynamic = try pbz.json.parseAlloc(allocator, &file, message_descriptor, text, .{});\n");
        try indent(writer, depth + 1);
        try writer.writeAll("defer dynamic.deinit();\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return try @This().fromDynamic(allocator, &file, &dynamic);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n\n");
    }
}

fn writeMessageDescriptorLookup(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (!ctx.emit_descriptor) return;
    var arena = std.heap.ArenaAllocator.init(ctx.allocator);
    defer arena.deinit();
    const full_name = (try messageFullNameForCodegen(arena.allocator(), ctx.file, message)) orelse return;
    try indent(writer, depth);
    try writer.writeAll("/// Look up this message's descriptor in a decoded file descriptor.\n");
    try indent(writer, depth);
    try writer.writeAll("pub fn descriptor(file: *const pbz.schema.FileDescriptor) ?*const pbz.schema.MessageDescriptor {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return file.findMessageDeep(");
    try writeZigStringLiteral(full_name, writer);
    try writer.writeAll(");\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");
}





fn writeExtensionMetadata(ctx: *const CodegenContext, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    const count = countExtensions(file);
    if (count == 0) return;
    try indent(writer, depth);
    try writer.writeAll("pub const extensions = struct {\n");
    for (file.extensions.items) |*field| try writeExtensionDecl(ctx, field, writer, depth + 1);
    for (file.messages.items) |*message| try writeMessageExtensions(ctx, message, writer, depth + 1);
    try indent(writer, depth);
    try writer.writeAll("};\n\n");
}

fn writeMessageExtensions(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    for (message.extensions.items) |*field| try writeExtensionDecl(ctx, field, writer, depth);
    for (message.messages.items) |*nested| try writeMessageExtensions(ctx, nested, writer, depth);
}

fn writeExtensionDecl(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    try indent(writer, depth);
    try writer.writeAll("pub const ");
    try writeExtensionHelperIdent(field, writer);
    try writer.writeAll(" = struct {\n");
    try indent(writer, depth + 1);
    try writer.print("pub const number = {d};\n", .{field.number});
    try indent(writer, depth + 1);
    try writer.writeAll("pub const extendee = ");
    try writeZigStringLiteral(field.extendee orelse "", writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const extendee_has_type_ref = ");
    try writer.writeAll(if (extensionExtendeeHasTypeRef(ctx, field)) "true" else "false");
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const extendee_type_ref = ");
    try writeExtensionExtendeeTypeRef(ctx, field, writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const cardinality = ");
    try writeZigStringLiteral(@tagName(field.cardinality), writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const value_type = ");
    try writeZigStringLiteral(extensionValueTypeName(file, field), writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const value_has_type_ref = ");
    try writer.writeAll(if (canReferenceMessageWithContext(ctx, field.kind)) "true" else "false");
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const value_type_ref = ");
    switch (field.kind) {
        .message, .group => |type_name| {
            if (codegenCanReferenceMessageWithContext(ctx, type_name)) {
                try writeQualifiedMessageTypeReference(ctx, type_name, writer);
            } else {
                try writer.writeAll("void");
            }
        },
        else => try writer.writeAll("void"),
    }
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const value_has_enum_ref = ");
    try writer.writeAll(if (canReferenceEnumWithContext(ctx, field.kind)) "true" else "false");
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const value_enum_ref = ");
    try writeEnumTypeReferenceOrVoid(ctx, field.kind, writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const zig_type = ");
    try writeZigStringLiteral(fieldType(field.*), writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const typed_zig_type = ");
    try writeExtensionTypedZigTypeLiteral(ctx, field, writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const has_default = ");
    try writer.writeAll(if (field.default_value != null) "true" else "false");
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const default_value = ");
    try writeOptionValueTextLiteral(field.default_value, writer);
    try writer.writeAll(";\n");
    if (field.kind == .scalar or field.kind == .enumeration) {
        try indent(writer, depth + 1);
        try writer.writeAll("pub const default_value_zig: ");
        try writer.writeAll(extensionSingleZigType(field.kind));
        try writer.writeAll(" = ");
        try writeFieldKindDefault(file, field.kind, field.default_value, writer);
        try writer.writeAll(";\n");
    }
    if (extensionExtendeeHasTypeRef(ctx, field)) try writeExtensionFacadeHelpers(ctx, field, writer, depth + 1);
    try writeExtensionWriteHelpers(ctx, field, writer, depth + 1);
    try writeExtensionDecodeHelpers(ctx, field, writer, depth + 1);
    try indent(writer, depth);
    try writer.writeAll("};\n");
}

fn extensionExtendeeHasTypeRef(ctx: *const CodegenContext, field: *const schema.FieldDescriptor) bool {
    return codegenCanReferenceMessageWithContext(ctx, field.extendee orelse return false);
}

fn writeExtensionTypedZigTypeLiteral(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    const type_name = switch (field.kind) {
        .message, .group => |name| name,
        else => return try writeZigStringLiteral(fieldType(field.*), writer),
    };
    if (!codegenCanReferenceMessageWithContext(ctx, type_name)) return try writeZigStringLiteral(fieldType(field.*), writer);
    var type_buf: std.Io.Writer.Allocating = .init(ctx.allocator);
    defer type_buf.deinit();
    if (field.cardinality == .repeated) try type_buf.writer.writeAll("[]const ");
    try writeQualifiedMessageTypeReference(ctx, type_name, &type_buf.writer);
    try writeZigStringLiteral(type_buf.written(), writer);
}

fn writeExtensionExtendeeTypeRef(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    const extendee = field.extendee orelse return try writer.writeAll("void");
    if (codegenCanReferenceMessageWithContext(ctx, extendee)) {
        try writeQualifiedMessageTypeReference(ctx, extendee, writer);
    } else {
        try writer.writeAll("void");
    }
}

fn writeExtensionFacadeHelpers(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn hasOn(message: ");
    try writeExtensionExtendeeTypeRef(ctx, field, writer);
    try writer.writeAll(") !bool {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try hasInUnknown(message);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn countOn(message: ");
    try writeExtensionExtendeeTypeRef(ctx, field, writer);
    try writer.writeAll(") !usize {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try countInUnknown(message);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn clearOn(message: *");
    try writeExtensionExtendeeTypeRef(ctx, field, writer);
    try writer.writeAll(", allocator: std.mem.Allocator) !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try clearFromUnknown(message, allocator);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn getOn(message: ");
    try writeExtensionExtendeeTypeRef(ctx, field, writer);
    try writer.writeAll(", allocator: std.mem.Allocator) !");
    if (field.cardinality == .repeated) {
        try writer.writeAll("[]");
        try writer.writeAll(extensionSingleZigType(field.kind));
    } else {
        try writer.writeByte('?');
        try writer.writeAll(extensionSingleZigType(field.kind));
    }
    try writer.writeAll(" {\n");
    try indent(writer, depth + 1);
    if (field.cardinality == .repeated) {
        try writer.writeAll("return try decodeAllFromUnknown(message, allocator);\n");
    } else {
        try writer.writeAll("return try decodeFirstFromUnknown(message, allocator);\n");
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");

    if (field.cardinality != .repeated and (field.kind == .scalar or field.kind == .enumeration)) {
        try indent(writer, depth);
        try writer.writeAll("pub fn getOrDefaultOn(message: ");
        try writeExtensionExtendeeTypeRef(ctx, field, writer);
        try writer.writeAll(", allocator: std.mem.Allocator) !");
        try writer.writeAll(extensionSingleZigType(field.kind));
        try writer.writeAll(" {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return (try getOn(message, allocator)) orelse default_value_zig;\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");
    }

    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        try writer.writeAll("pub fn addOn(message: *");
        try writeExtensionExtendeeTypeRef(ctx, field, writer);
        try writer.writeAll(", allocator: std.mem.Allocator, value: ");
        try writer.writeAll(extensionSingleZigType(field.kind));
        try writer.writeAll(") !void {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try appendToUnknown(message, allocator, value);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");

        try indent(writer, depth);
        try writer.writeAll("pub fn appendAllOn(message: *");
        try writeExtensionExtendeeTypeRef(ctx, field, writer);
        try writer.writeAll(", allocator: std.mem.Allocator, values: ");
        try writer.writeAll(fieldType(field.*));
        try writer.writeAll(") !void {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try appendAllToUnknown(message, allocator, values);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");

        try indent(writer, depth);
        try writer.writeAll("pub fn replaceAllOn(message: *");
        try writeExtensionExtendeeTypeRef(ctx, field, writer);
        try writer.writeAll(", allocator: std.mem.Allocator, values: ");
        try writer.writeAll(fieldType(field.*));
        try writer.writeAll(") !void {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try replaceAllInUnknown(message, allocator, values);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");
    } else {
        try indent(writer, depth);
        try writer.writeAll("pub fn setOn(message: *");
        try writeExtensionExtendeeTypeRef(ctx, field, writer);
        try writer.writeAll(", allocator: std.mem.Allocator, value: ");
        try writer.writeAll(extensionSingleZigType(field.kind));
        try writer.writeAll(") !void {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try replaceInUnknown(message, allocator, value);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");
    }

    if (field.kind == .enumeration and canReferenceEnumWithContext(ctx, field.kind)) {
        try writeExtensionEnumFacadeHelpers(ctx, field, writer, depth);
    }
    if ((field.kind == .message or field.kind == .group) and canReferenceMessageWithContext(ctx, field.kind)) {
        try writeExtensionMessageFacadeHelpers(ctx, field, writer, depth);
    }
}

fn writeExtensionEnumFacadeHelpers(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        try writer.writeAll("pub fn getEnumsOn(message: ");
        try writeExtensionExtendeeTypeRef(ctx, field, writer);
        try writer.writeAll(", allocator: std.mem.Allocator) ![]");
        try writeEnumTypeReferenceWithContext(ctx, field.kind.enumeration, writer);
        try writer.writeAll(" {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const _pbz_raw = try getOn(message, allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("defer allocator.free(_pbz_raw);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const _pbz_out = try allocator.alloc(");
        try writeEnumTypeReferenceWithContext(ctx, field.kind.enumeration, writer);
        try writer.writeAll(", _pbz_raw.len);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("errdefer allocator.free(_pbz_out);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("for (_pbz_raw, 0..) |_pbz_value, _pbz_i| _pbz_out[_pbz_i] = ");
        try writeEnumTypeReferenceWithContext(ctx, field.kind.enumeration, writer);
        try writer.writeAll(".fromInt(_pbz_value) orelse return error.InvalidEnumValue;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return _pbz_out;\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");

        try indent(writer, depth);
        try writer.writeAll("pub fn addEnumOn(message: *");
        try writeExtensionExtendeeTypeRef(ctx, field, writer);
        try writer.writeAll(", allocator: std.mem.Allocator, value: ");
        try writeEnumTypeReferenceWithContext(ctx, field.kind.enumeration, writer);
        try writer.writeAll(") !void {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try addOn(message, allocator, value.toInt());\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");

        try indent(writer, depth);
        try writer.writeAll("pub fn appendAllEnumsOn(message: *");
        try writeExtensionExtendeeTypeRef(ctx, field, writer);
        try writer.writeAll(", allocator: std.mem.Allocator, values: []const ");
        try writeEnumTypeReferenceWithContext(ctx, field.kind.enumeration, writer);
        try writer.writeAll(") !void {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const _pbz_raw = try allocator.alloc(i32, values.len);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("defer allocator.free(_pbz_raw);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("for (values, 0..) |_pbz_value, _pbz_i| _pbz_raw[_pbz_i] = _pbz_value.toInt();\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try appendAllOn(message, allocator, _pbz_raw);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");

        try indent(writer, depth);
        try writer.writeAll("pub fn replaceAllEnumsOn(message: *");
        try writeExtensionExtendeeTypeRef(ctx, field, writer);
        try writer.writeAll(", allocator: std.mem.Allocator, values: []const ");
        try writeEnumTypeReferenceWithContext(ctx, field.kind.enumeration, writer);
        try writer.writeAll(") !void {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const _pbz_raw = try allocator.alloc(i32, values.len);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("defer allocator.free(_pbz_raw);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("for (values, 0..) |_pbz_value, _pbz_i| _pbz_raw[_pbz_i] = _pbz_value.toInt();\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try replaceAllOn(message, allocator, _pbz_raw);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");
        return;
    }

    try indent(writer, depth);
    try writer.writeAll("pub fn getEnumOn(message: ");
    try writeExtensionExtendeeTypeRef(ctx, field, writer);
    try writer.writeAll(", allocator: std.mem.Allocator) !?");
    try writeEnumTypeReferenceWithContext(ctx, field.kind.enumeration, writer);
    try writer.writeAll(" {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const _pbz_raw = (try getOn(message, allocator)) orelse return null;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return ");
    try writeEnumTypeReferenceWithContext(ctx, field.kind.enumeration, writer);
    try writer.writeAll(".fromInt(_pbz_raw);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn getEnumOrDefaultOn(message: ");
    try writeExtensionExtendeeTypeRef(ctx, field, writer);
    try writer.writeAll(", allocator: std.mem.Allocator) !");
    try writeEnumTypeReferenceWithContext(ctx, field.kind.enumeration, writer);
    try writer.writeAll(" {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return (try getEnumOn(message, allocator)) orelse ");
    try writeEnumTypeReferenceWithContext(ctx, field.kind.enumeration, writer);
    try writer.writeAll(".fromInt(default_value_zig) orelse unreachable;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn setEnumOn(message: *");
    try writeExtensionExtendeeTypeRef(ctx, field, writer);
    try writer.writeAll(", allocator: std.mem.Allocator, value: ");
    try writeEnumTypeReferenceWithContext(ctx, field.kind.enumeration, writer);
    try writer.writeAll(") !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try setOn(message, allocator, value.toInt());\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeExtensionMessageFacadeHelpers(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const type_name = switch (field.kind) {
        .message => |name| name,
        .group => |name| name,
        else => return,
    };
    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        try writer.writeAll("pub fn addMessageOn(message: *");
        try writeExtensionExtendeeTypeRef(ctx, field, writer);
        try writer.writeAll(", allocator: std.mem.Allocator, value: ");
        try writeQualifiedMessageTypeReference(ctx, type_name, writer);
        try writer.writeAll(") !void {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const _pbz_payload = try value.encode(allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("defer allocator.free(_pbz_payload);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try appendToUnknown(message, allocator, _pbz_payload);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");

        try indent(writer, depth);
        try writer.writeAll("pub fn getMessagesOn(message: ");
        try writeExtensionExtendeeTypeRef(ctx, field, writer);
        try writer.writeAll(", allocator: std.mem.Allocator) ![]");
        try writeQualifiedMessageTypeReference(ctx, type_name, writer);
        try writer.writeAll(" {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const _pbz_payloads = try decodeAllFromUnknown(message, allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("defer allocator.free(_pbz_payloads);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("var _pbz_list: std.ArrayList(");
        try writeQualifiedMessageTypeReference(ctx, type_name, writer);
        try writer.writeAll(") = .empty;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("errdefer { for (_pbz_list.items) |*item| item.deinit(allocator); _pbz_list.deinit(allocator); }\n");
        try indent(writer, depth + 1);
        try writer.writeAll("for (_pbz_payloads) |_pbz_payload| try _pbz_list.append(allocator, try ");
        try writeQualifiedMessageTypeReference(ctx, type_name, writer);
        try writer.writeAll(".decode(allocator, _pbz_payload));\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return try _pbz_list.toOwnedSlice(allocator);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");
    } else {
        try indent(writer, depth);
        try writer.writeAll("pub fn setMessageOn(message: *");
        try writeExtensionExtendeeTypeRef(ctx, field, writer);
        try writer.writeAll(", allocator: std.mem.Allocator, value: ");
        try writeQualifiedMessageTypeReference(ctx, type_name, writer);
        try writer.writeAll(") !void {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const _pbz_payload = try value.encode(allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("defer allocator.free(_pbz_payload);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try replaceInUnknown(message, allocator, _pbz_payload);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");

        try indent(writer, depth);
        try writer.writeAll("pub fn getMessageOn(message: ");
        try writeExtensionExtendeeTypeRef(ctx, field, writer);
        try writer.writeAll(", allocator: std.mem.Allocator) !?");
        try writeQualifiedMessageTypeReference(ctx, type_name, writer);
        try writer.writeAll(" {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const _pbz_payload = (try decodeFirstFromUnknown(message, allocator)) orelse return null;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return try ");
        try writeQualifiedMessageTypeReference(ctx, type_name, writer);
        try writer.writeAll(".decode(allocator, _pbz_payload);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");
    }
}

fn writeExtensionWriteHelpers(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    try indent(writer, depth);
    try writer.writeAll("pub fn write(w: *pbz.Writer, value: ");
    try writer.writeAll(extensionSingleZigType(field.kind));
    try writer.writeAll(") !void {\n");
    if (extensionUsesMessageSet(ctx, field)) {
        try indent(writer, depth + 1);
        try writer.writeAll("try w.writeTag(1, .start_group);\n");
        try indent(writer, depth + 1);
        try writer.print("try w.writeUInt32(2, {d});\n", .{field.number});
        try indent(writer, depth + 1);
        try writer.writeAll("try w.writeMessage(3, value);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try w.writeTag(1, .end_group);\n");
    } else {
        try indent(writer, depth + 1);
        if (field.kind == .group) {
            try writer.print("try w.writeTag({d}, .start_group);\n", .{field.number});
            try indent(writer, depth + 1);
            try writer.writeAll("try w.appendSlice(value);\n");
            try indent(writer, depth + 1);
            try writer.print("try w.writeTag({d}, .end_group);\n", .{field.number});
        } else {
            try writeKindWriteCall(field.number, field.kind, "value", "w", writer);
            try writer.writeAll(");\n");
        }
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn encodeRaw(allocator: std.mem.Allocator, value: ");
    try writer.writeAll(extensionSingleZigType(field.kind));
    try writer.writeAll(") ![]u8 {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var w = pbz.Writer.init(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer w.deinit();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try write(&w, value);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try w.toOwnedSlice();\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn appendToUnknown(message: anytype, allocator: std.mem.Allocator, value: ");
    try writer.writeAll(extensionSingleZigType(field.kind));
    try writer.writeAll(") !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const _pbz_raw = try encodeRaw(allocator, value);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("defer allocator.free(_pbz_raw);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try message.appendUnknownRaw(allocator, _pbz_raw);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn hasInUnknown(message: anytype) !bool {\n");
    try indent(writer, depth + 1);
    if (extensionUsesMessageSet(ctx, field)) {
        try writer.writeAll("for (message.unknownFields()) |_pbz_raw| { if ((try decodeRaw(_pbz_raw)) != null) return true; }\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return false;\n");
    } else {
        try writer.writeAll("return try message.hasUnknownFieldNumber(number);\n");
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn countInUnknown(message: anytype) !usize {\n");
    try indent(writer, depth + 1);
    if (extensionUsesMessageSet(ctx, field)) {
        try writer.writeAll("var _pbz_count: usize = 0;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("for (message.unknownFields()) |_pbz_raw| { if ((try decodeRaw(_pbz_raw)) != null) _pbz_count += 1; }\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return _pbz_count;\n");
    } else {
        try writer.writeAll("return try message.unknownFieldCountByNumber(number);\n");
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn clearFromUnknown(message: anytype, allocator: std.mem.Allocator) !void {\n");
    try indent(writer, depth + 1);
    if (extensionUsesMessageSet(ctx, field)) {
        try writer.writeAll("const _pbz_old = message.unknownFields();\n");
        try indent(writer, depth + 1);
        try writer.writeAll("if (_pbz_old.len == 0) return;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("var _pbz_keep: std.ArrayList([]const u8) = .empty;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("errdefer _pbz_keep.deinit(allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("for (_pbz_old) |_pbz_raw| { if ((try decodeRaw(_pbz_raw)) == null) try _pbz_keep.append(allocator, _pbz_raw) else allocator.free(_pbz_raw); }\n");
        try indent(writer, depth + 1);
        try writer.writeAll("if (_pbz_keep.items.len == 0) { _pbz_keep.deinit(allocator); message._unknown_fields = &.{}; } else message._unknown_fields = try _pbz_keep.toOwnedSlice(allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("allocator.free(_pbz_old);\n");
    } else {
        try writer.writeAll("try message.clearUnknownFieldsByNumber(allocator, number);\n");
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn replaceInUnknown(message: anytype, allocator: std.mem.Allocator, value: ");
    try writer.writeAll(extensionSingleZigType(field.kind));
    try writer.writeAll(") !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try clearFromUnknown(message, allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try appendToUnknown(message, allocator, value);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");

    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        try writer.writeAll("pub fn writeAll(w: *pbz.Writer, values: ");
        try writer.writeAll(fieldType(field.*));
        try writer.writeAll(") !void {\n");
        if (field.resolvedPacked(file)) {
            try indent(writer, depth + 1);
            try writer.writeAll("if (values.len == 0) return;\n");
            try indent(writer, depth + 1);
            try writer.writeAll("var packed_writer = pbz.Writer.init(w.allocator);\n");
            try indent(writer, depth + 1);
            try writer.writeAll("defer packed_writer.deinit();\n");
            try indent(writer, depth + 1);
            try writer.writeAll("for (values) |value| ");
            try writePackedKindPayload(field.kind, "value", writer);
            try writer.writeAll(";\n");
            try indent(writer, depth + 1);
            try writer.print("try w.writeBytes({d}, packed_writer.slice());\n", .{field.number});
        } else {
            try indent(writer, depth + 1);
            try writer.writeAll("for (values) |_pbz_value| try write(w, _pbz_value);\n");
        }
        try indent(writer, depth);
        try writer.writeAll("}\n");

        try indent(writer, depth);
        try writer.writeAll("pub fn encodeAllRaw(allocator: std.mem.Allocator, values: ");
        try writer.writeAll(fieldType(field.*));
        try writer.writeAll(") ![]u8 {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("var w = pbz.Writer.init(allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("errdefer w.deinit();\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try writeAll(&w, values);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return try w.toOwnedSlice();\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");

        try indent(writer, depth);
        try writer.writeAll("pub fn appendAllToUnknown(message: anytype, allocator: std.mem.Allocator, values: ");
        try writer.writeAll(fieldType(field.*));
        try writer.writeAll(") !void {\n");
        if (field.resolvedPacked(file)) {
            try indent(writer, depth + 1);
            try writer.writeAll("if (values.len == 0) return;\n");
            try indent(writer, depth + 1);
            try writer.writeAll("const _pbz_raw = try encodeAllRaw(allocator, values);\n");
            try indent(writer, depth + 1);
            try writer.writeAll("defer allocator.free(_pbz_raw);\n");
            try indent(writer, depth + 1);
            try writer.writeAll("try message.appendUnknownRaw(allocator, _pbz_raw);\n");
        } else {
            try indent(writer, depth + 1);
            try writer.writeAll("for (values) |_pbz_value| try appendToUnknown(message, allocator, _pbz_value);\n");
        }
        try indent(writer, depth);
        try writer.writeAll("}\n");

        try indent(writer, depth);
        try writer.writeAll("pub fn replaceAllInUnknown(message: anytype, allocator: std.mem.Allocator, values: ");
        try writer.writeAll(fieldType(field.*));
        try writer.writeAll(") !void {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try clearFromUnknown(message, allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try appendAllToUnknown(message, allocator, values);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");
    }
}

fn extensionUsesMessageSet(ctx: *const CodegenContext, field: *const schema.FieldDescriptor) bool {
    if (field.kind != .message) return false;
    const extendee = field.extendee orelse return false;
    const ref = resolveMessageReference(ctx, extendee) orelse return false;
    return ref.message.messageSetWireFormat();
}

fn writeExtensionDecodeHelpers(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    try indent(writer, depth);
    try writer.writeAll("pub fn decodeValue(r: *pbz.Reader) !");
    try writer.writeAll(extensionSingleZigType(field.kind));
    try writer.writeAll(" {\n");
    try indent(writer, depth + 1);
    if (field.kind == .group) {
        try writer.writeAll("return try r.readGroupBytes(number);\n");
    } else {
        try writer.writeAll("return ");
        try writeEntryReadExpr(field.kind, "r", writer);
        try writer.writeAll(";\n");
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn decodeRaw(raw: []const u8) !?");
    try writer.writeAll(extensionSingleZigType(field.kind));
    try writer.writeAll(" {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var r = pbz.Reader.init(raw);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const _pbz_tag = (try r.nextTag()) orelse return null;\n");
    if (extensionUsesMessageSet(ctx, field)) {
        try indent(writer, depth + 1);
        try writer.writeAll("if (_pbz_tag.number == 1 and _pbz_tag.wire_type == .start_group) { const _pbz_value = try decodeMessageSetItem(&r); if (!r.eof()) return error.InvalidWireType; return _pbz_value; }\n");
        try indent(writer, depth + 1);
        try writer.print("if (_pbz_tag.number == {d} and _pbz_tag.wire_type == .length_delimited) {{ const _pbz_value = try r.readBytes(); if (!r.eof()) return error.InvalidWireType; return _pbz_value; }}\n", .{field.number});
        try indent(writer, depth + 1);
        try writer.writeAll("return null;\n");
    } else {
        try indent(writer, depth + 1);
        try writer.print("if (_pbz_tag.number != number or _pbz_tag.wire_type != .{s}) return null;\n", .{@tagName(field.kind.wireType())});
        try indent(writer, depth + 1);
        try writer.writeAll("const _pbz_value = try decodeValue(&r);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("if (!r.eof()) return error.InvalidWireType;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return _pbz_value;\n");
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");

    if (field.resolvedPacked(file)) {
        try indent(writer, depth);
        try writer.writeAll("pub fn decodePackedRaw(allocator: std.mem.Allocator, raw: []const u8) !?[]");
        try writer.writeAll(extensionSingleZigType(field.kind));
        try writer.writeAll(" {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("var r = pbz.Reader.init(raw);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const _pbz_tag = (try r.nextTag()) orelse return null;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("if (_pbz_tag.number != number or _pbz_tag.wire_type != .length_delimited) return null;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("var packed_reader = pbz.Reader.init(try r.readBytes());\n");
        try indent(writer, depth + 1);
        try writer.writeAll("if (!r.eof()) return error.InvalidWireType;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("var _pbz_list: std.ArrayList(");
        try writer.writeAll(extensionSingleZigType(field.kind));
        try writer.writeAll(") = .empty;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("errdefer _pbz_list.deinit(allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("while (!packed_reader.eof()) try _pbz_list.append(allocator, ");
        try writeEntryReadExpr(field.kind, "packed_reader", writer);
        try writer.writeAll(");\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return try _pbz_list.toOwnedSlice(allocator);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");
    }

    try indent(writer, depth);
    try writer.writeAll("pub fn decodeAllRaw(allocator: std.mem.Allocator, raw_fields: []const []const u8) ![]");
    try writer.writeAll(extensionSingleZigType(field.kind));
    try writer.writeAll(" {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var _pbz_list: std.ArrayList(");
    try writer.writeAll(extensionSingleZigType(field.kind));
    try writer.writeAll(") = .empty;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer _pbz_list.deinit(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("for (raw_fields) |_pbz_raw| {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("if (try decodeRaw(_pbz_raw)) |_pbz_value| try _pbz_list.append(allocator, _pbz_value);\n");
    if (field.resolvedPacked(file)) {
        try indent(writer, depth + 2);
        try writer.writeAll("if (try decodePackedRaw(allocator, _pbz_raw)) |_pbz_values| { defer allocator.free(_pbz_values); try _pbz_list.appendSlice(allocator, _pbz_values); }\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try _pbz_list.toOwnedSlice(allocator);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn decodeFromUnknownFieldsAlloc(message: anytype, allocator: std.mem.Allocator) ![]");
    try writer.writeAll(extensionSingleZigType(field.kind));
    try writer.writeAll(" {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try decodeAllRaw(allocator, message.unknownFields());\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn decodeAllFromUnknown(message: anytype, allocator: std.mem.Allocator) ![]");
    try writer.writeAll(extensionSingleZigType(field.kind));
    try writer.writeAll(" {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try decodeFromUnknownFieldsAlloc(message, allocator);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn decodeFirstFromUnknown(message: anytype, allocator: std.mem.Allocator) !");
    try writer.writeAll("?");
    try writer.writeAll(extensionSingleZigType(field.kind));
    try writer.writeAll(" {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const _pbz_values = try decodeFromUnknownFieldsAlloc(message, allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("defer allocator.free(_pbz_values);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return if (_pbz_values.len == 0) null else _pbz_values[_pbz_values.len - 1];\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");

    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        try writer.writeAll("pub fn decodeAppend(allocator: std.mem.Allocator, list: *std.ArrayList(");
        try writer.writeAll(extensionSingleZigType(field.kind));
        try writer.writeAll("), r: *pbz.Reader) !void {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try list.append(allocator, try decodeValue(r));\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");

        try indent(writer, depth);
        try writer.writeAll("pub fn decodeAppendRaw(allocator: std.mem.Allocator, list: *std.ArrayList(");
        try writer.writeAll(extensionSingleZigType(field.kind));
        try writer.writeAll("), raw: []const u8) !void {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("if (try decodeRaw(raw)) |_pbz_value| try list.append(allocator, _pbz_value);\n");
        if (field.resolvedPacked(file)) {
            try indent(writer, depth + 1);
            try writer.writeAll("if (try decodePackedRaw(allocator, raw)) |_pbz_values| { defer allocator.free(_pbz_values); try list.appendSlice(allocator, _pbz_values); }\n");
        }
        try indent(writer, depth);
        try writer.writeAll("}\n");
    }
    if (extensionUsesMessageSet(ctx, field)) {
        try indent(writer, depth);
        try writer.writeAll("pub fn decodeMessageSetItem(r: *pbz.Reader) !?[]const u8 {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("var type_id: ?u32 = null;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("var _pbz_payload: ?[]const u8 = null;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("while (try r.nextTag()) |_pbz_tag| {\n");
        try indent(writer, depth + 2);
        try writer.writeAll("if (_pbz_tag.wire_type == .end_group) {\n");
        try indent(writer, depth + 3);
        try writer.writeAll("if (_pbz_tag.number != 1) return error.InvalidFieldNumber;\n");
        try indent(writer, depth + 3);
        try writer.print("return if (type_id != null and type_id.? == {d}) _pbz_payload else null;\n", .{field.number});
        try indent(writer, depth + 2);
        try writer.writeAll("}\n");
        try indent(writer, depth + 2);
        try writer.writeAll("switch (_pbz_tag.number) {\n");
        try indent(writer, depth + 3);
        try writer.writeAll("2 => { if (_pbz_tag.wire_type != .varint) return error.InvalidWireType; const raw_type_id = try r.readUInt32(); if (raw_type_id == 0 or raw_type_id > std.math.maxInt(pbz.FieldNumber)) return error.InvalidFieldNumber; type_id = raw_type_id; },\n");
        try indent(writer, depth + 3);
        try writer.writeAll("3 => { if (_pbz_tag.wire_type != .length_delimited) return error.InvalidWireType; _pbz_payload = try r.readBytes(); },\n");
        try indent(writer, depth + 3);
        try writer.writeAll("else => try r.skipValue(_pbz_tag),\n");
        try indent(writer, depth + 2);
        try writer.writeAll("}\n");
        try indent(writer, depth + 1);
        try writer.writeAll("}\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return error.TruncatedInput;\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");
    }
}

fn extensionSingleZigType(kind: schema.FieldKind) []const u8 {
    return switch (kind) {
        .scalar => |scalar| scalarZigType(scalar),
        .enumeration => "i32",
        .message, .group => "[]const u8",
        else => "void",
    };
}

fn extensionValueTypeName(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor) []const u8 {
    _ = file;
    return switch (field.kind) {
        .scalar => |scalar| @tagName(scalar),
        .message => |name| name,
        .enumeration => |name| name,
        .group => |name| name,
        .map => "map",
    };
}

fn countExtensions(file: *const schema.FileDescriptor) usize {
    var count: usize = file.extensions.items.len;
    for (file.messages.items) |*message| count += countMessageExtensions(message);
    return count;
}

fn countMessageExtensions(message: *const schema.MessageDescriptor) usize {
    var count: usize = message.extensions.items.len;
    for (message.messages.items) |*nested| count += countMessageExtensions(nested);
    return count;
}

fn writeIdentWithSuffix(name: []const u8, suffix: []const u8, writer: *std.Io.Writer) Error!void {
    if (canWriteBareIdentParts("", name, suffix)) {
        try writer.writeAll(name);
        return try writer.writeAll(suffix);
    }
    return try writeQuotedIdentWithSuffix(name, suffix, writer);
}

fn writeIdentWithPrefix(name: []const u8, prefix: []const u8, writer: *std.Io.Writer) Error!void {
    if (canWriteBareIdentParts(prefix, name, "")) {
        try writer.writeAll(prefix);
        return try writer.writeAll(name);
    }
    return try writeQuotedIdentWithPrefix(name, prefix, writer);
}

fn canWriteBareIdent(name: []const u8) bool {
    if (std.mem.eql(u8, name, "_")) return false;
    if (!canWriteBareIdentParts("", name, "")) return false;
    if (std.zig.Token.getKeyword(name) != null) return false;
    if (isPrimitiveIdent(name)) return false;
    return true;
}

fn canWriteBareIdentParts(prefix: []const u8, name: []const u8, suffix: []const u8) bool {
    const total_len = prefix.len + name.len + suffix.len;
    if (total_len == 0) return false;
    var index: usize = 0;
    for (prefix) |c| {
        if (!isBareIdentChar(c, index == 0)) return false;
        index += 1;
    }
    for (name) |c| {
        if (!isBareIdentChar(c, index == 0)) return false;
        index += 1;
    }
    for (suffix) |c| {
        if (!isBareIdentChar(c, index == 0)) return false;
        index += 1;
    }
    return true;
}

fn isBareIdentChar(c: u8, first: bool) bool {
    return switch (c) {
        'a'...'z', 'A'...'Z', '_' => true,
        '0'...'9' => !first,
        else => false,
    };
}

fn isPrimitiveIdent(name: []const u8) bool {
    if (std.mem.eql(u8, name, "bool") or
        std.mem.eql(u8, name, "void") or
        std.mem.eql(u8, name, "noreturn") or
        std.mem.eql(u8, name, "type") or
        std.mem.eql(u8, name, "anyerror") or
        std.mem.eql(u8, name, "anyopaque") or
        std.mem.eql(u8, name, "comptime_int") or
        std.mem.eql(u8, name, "comptime_float") or
        std.mem.eql(u8, name, "isize") or
        std.mem.eql(u8, name, "usize") or
        std.mem.eql(u8, name, "true") or
        std.mem.eql(u8, name, "false") or
        std.mem.eql(u8, name, "null") or
        std.mem.eql(u8, name, "undefined") or
        std.mem.eql(u8, name, "c_char") or
        std.mem.eql(u8, name, "c_short") or
        std.mem.eql(u8, name, "c_ushort") or
        std.mem.eql(u8, name, "c_int") or
        std.mem.eql(u8, name, "c_uint") or
        std.mem.eql(u8, name, "c_long") or
        std.mem.eql(u8, name, "c_ulong") or
        std.mem.eql(u8, name, "c_longlong") or
        std.mem.eql(u8, name, "c_ulonglong") or
        std.mem.eql(u8, name, "c_longdouble") or
        std.mem.eql(u8, name, "f16") or
        std.mem.eql(u8, name, "f32") or
        std.mem.eql(u8, name, "f64") or
        std.mem.eql(u8, name, "f80") or
        std.mem.eql(u8, name, "f128"))
    {
        return true;
    }
    if (name.len >= 2 and (name[0] == 'i' or name[0] == 'u')) {
        for (name[1..]) |c| if (c < '0' or c > '9') return false;
        return true;
    }
    return false;
}

pub fn writeQuotedIdent(name: []const u8, writer: *std.Io.Writer) Error!void {
    if (canWriteBareIdent(name)) return try writer.writeAll(name);
    try writer.writeAll("@\"");
    for (name) |c| {
        if (c == '\\' or c == '"') try writer.writeByte('\\');
        try writer.writeByte(c);
    }
    try writer.writeAll("\"");
}

pub fn writeQuotedIdentWithSuffix(name: []const u8, suffix: []const u8, writer: *std.Io.Writer) Error!void {
    if (canWriteBareIdentParts("", name, suffix)) {
        try writer.writeAll(name);
        return try writer.writeAll(suffix);
    }
    try writer.writeAll("@\"");
    for (name) |c| {
        if (c == '\\' or c == '"') try writer.writeByte('\\');
        try writer.writeByte(c);
    }
    try writer.writeAll(suffix);
    try writer.writeAll("\"");
}

pub fn writeQuotedIdentWithPrefix(name: []const u8, prefix: []const u8, writer: *std.Io.Writer) Error!void {
    if (canWriteBareIdentParts(prefix, name, "")) {
        try writer.writeAll(prefix);
        return try writer.writeAll(name);
    }
    try writer.writeAll("@\"");
    try writer.writeAll(prefix);
    for (name) |c| {
        if (c == '\\' or c == '"') try writer.writeByte('\\');
        try writer.writeByte(c);
    }
    try writer.writeAll("\"");
}

fn extensionAccessorSuffix(name: []const u8) []const u8 {
    return leafTypeName(name);
}

pub fn hasPresence(file: *const schema.FileDescriptor, field: schema.FieldDescriptor) bool {
    if (field.cardinality == .required or field.proto3_optional or field.oneof_name != null or field.kind == .message or field.kind == .group) return true;
    if (field.cardinality == .repeated or field.kind == .map) return false;
    return schema.FeatureSet.effective(field.features, file.features).field_presence != .implicit;
}

pub fn isRequired(field: schema.FieldDescriptor) bool {
    if (field.cardinality == .required) return true;
    if (field.features) |features| return features.field_presence == .legacy_required;
    return false;
}

pub fn writePresenceIdent(name: []const u8, writer: *std.Io.Writer) Error!void {
    try writeIdentWithPrefix(name, "has_", writer);
}

fn writeSetPresence(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    if (hasPresence(file, field.*)) {
        try writer.writeAll(" self.");
        try writePresenceIdent(field.name, writer);
        try writer.writeAll(" = true;");
    }
}

fn writeQuotedFieldNumber(name: []const u8, writer: *std.Io.Writer) Error!void {
    try writeIdentWithSuffix(name, "_number", writer);
}

pub fn indent(writer: *std.Io.Writer, depth: usize) Error!void {
    var i: usize = 0;
    while (i < depth) : (i += 1) try writer.writeAll("    ");
}

pub fn outputNameWithOptions(allocator: std.mem.Allocator, input: []const u8, suffix: []const u8, strip_proto_ext: bool) std.mem.Allocator.Error![]u8 {
    const base = if (input.len == 0) "schema.proto" else input;
    const stem = if (strip_proto_ext and std.mem.endsWith(u8, base, ".proto")) base[0 .. base.len - 6] else base;
    return try std.fmt.allocPrint(allocator, "{s}{s}", .{ stem, suffix });
}


pub fn extensionAppliesToMessage(file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) bool {
    const extendee = field.extendee orelse return false;
    if (findExtensionExtendeeInFile(file, field)) |resolved| return resolved == message;
    const trimmed = if (std.mem.startsWith(u8, extendee, ".")) extendee[1..] else extendee;
    const leaf = if (std.mem.lastIndexOfScalar(u8, trimmed, '.')) |idx| trimmed[idx + 1 ..] else trimmed;
    return std.mem.eql(u8, message.name, trimmed) or std.mem.eql(u8, message.name, leaf);
}

pub fn findMessageByQualifiedName(file: *const schema.FileDescriptor, name: []const u8) ?*const schema.MessageDescriptor {
    var normalized = if (std.mem.startsWith(u8, name, ".")) name[1..] else name;
    if (file.package.len != 0 and std.mem.startsWith(u8, normalized, file.package)) {
        if (normalized.len == file.package.len) return null;
        if (normalized.len > file.package.len and normalized[file.package.len] == '.') normalized = normalized[file.package.len + 1 ..];
    }
    return findMessageByPath(file.messages.items, normalized);
}

pub fn leafTypeName(name: []const u8) []const u8 {
    const trimmed = if (std.mem.startsWith(u8, name, ".")) name[1..] else name;
    return if (std.mem.lastIndexOfScalar(u8, trimmed, '.')) |idx| trimmed[idx + 1 ..] else trimmed;
}

pub fn writeExtensionHelperReference(field: *const schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("extensions.");
    try writeExtensionHelperIdent(field, writer);
}

pub fn writeExtensionHelperIdent(field: *const schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    try writeQuotedIdent(schema.extensionFullName(field), writer);
}

pub fn writeOneofValueEncode(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    const file = ctx.file;
    switch (field.kind) {
        .scalar => |scalar| {
            if (scalar == .string and fieldUtf8Validation(file, field) == .verify) {
                try writer.writeAll("{ if (!pbz.validateUtf8(");
                try writer.writeAll(value_expr);
                try writer.writeAll(")) return error.InvalidUtf8; ");
                try writeScalarWriteCall(field.number, scalar, value_expr, writer);
                try writer.writeAll("); }");
            } else {
                try writeScalarWriteCall(field.number, scalar, value_expr, writer);
                try writer.writeAll(")");
            }
        },
        .enumeration => try writer.print("try w.writeInt32({d}, {s})", .{ field.number, value_expr }),
        .message => {
            if (typedOneofMessageFieldWithContext(ctx, field)) |_| {
                try writer.print("{{ const payload_len = {s}.encodedSize(); try w.writeTag({d}, .length_delimited); try w.writeVarint(payload_len); try {s}.writeTo(w); }}", .{ value_expr, field.number, value_expr });
            } else if (fieldMessageEncoding(file, field) == .delimited) {
                try writer.print("{{ try w.writeTag({d}, .start_group); try w.appendSlice({s}); try w.writeTag({d}, .end_group); }}", .{ field.number, value_expr, field.number });
            } else {
                try writer.print("try w.writeMessage({d}, {s})", .{ field.number, value_expr });
            }
        },
        .group => {
            if (typedOneofMessageFieldWithContext(ctx, field)) |_| {
                try writer.print("{{ try w.writeTag({d}, .start_group); try {s}.writeTo(w); try w.writeTag({d}, .end_group); }}", .{ field.number, value_expr, field.number });
            } else {
                try writer.print("{{ try w.writeTag({d}, .start_group); try w.appendSlice({s}); try w.writeTag({d}, .end_group); }}", .{ field.number, value_expr, field.number });
            }
        },
        else => try writer.writeAll("@compileError(\"unsupported oneof field\")"),
    }
}

pub fn writeOneofValueEncodeAssumeCapacity(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    const file = ctx.file;
    switch (field.kind) {
        .scalar => |scalar| {
            if (scalar == .string and fieldUtf8Validation(file, field) == .verify) {
                try writer.writeAll("{ if (!pbz.validateUtf8(");
                try writer.writeAll(value_expr);
                try writer.writeAll(")) return error.InvalidUtf8; ");
                try writeScalarWriteCallAssumeCapacity(field.number, scalar, value_expr, writer);
                try writer.writeAll("); }");
            } else {
                try writeScalarWriteCallAssumeCapacity(field.number, scalar, value_expr, writer);
                try writer.writeAll(")");
            }
        },
        .enumeration => try writer.print("w.writeInt32AssumeCapacity({d}, {s})", .{ field.number, value_expr }),
        .message => {
            if (typedOneofMessageFieldWithContext(ctx, field)) |_| {
                try writer.print("{{ const payload_len = {s}.encodedSize(); w.writeTagAssumeCapacity({d}, .length_delimited); w.writeVarintAssumeCapacity(payload_len); try {s}.writeToAssumeCapacity(w); }}", .{ value_expr, field.number, value_expr });
            } else if (fieldMessageEncoding(file, field) == .delimited) {
                try writer.print("{{ w.writeTagAssumeCapacity({d}, .start_group); w.appendSliceAssumeCapacity({s}); w.writeTagAssumeCapacity({d}, .end_group); }}", .{ field.number, value_expr, field.number });
            } else {
                try writer.print("w.writeMessageAssumeCapacity({d}, {s})", .{ field.number, value_expr });
            }
        },
        .group => {
            if (typedOneofMessageFieldWithContext(ctx, field)) |_| {
                try writer.print("{{ w.writeTagAssumeCapacity({d}, .start_group); try {s}.writeToAssumeCapacity(w); w.writeTagAssumeCapacity({d}, .end_group); }}", .{ field.number, value_expr, field.number });
            } else {
                try writer.print("{{ w.writeTagAssumeCapacity({d}, .start_group); w.appendSliceAssumeCapacity({s}); w.writeTagAssumeCapacity({d}, .end_group); }}", .{ field.number, value_expr, field.number });
            }
        },
        else => try writer.writeAll("@compileError(\"unsupported oneof field\")"),
    }
}

pub fn typedSingularMessageFieldWithContext(ctx: *const CodegenContext, field: *const schema.FieldDescriptor) ?[]const u8 {
    if (field.oneof_name != null or field.cardinality == .repeated) return null;
    return typedLengthPrefixedOrGroupFieldWithContext(ctx, field);
}

pub fn typedRepeatedMessageFieldWithContext(ctx: *const CodegenContext, field: *const schema.FieldDescriptor) ?[]const u8 {
    if (field.oneof_name != null or field.cardinality != .repeated) return null;
    return typedLengthPrefixedOrGroupFieldWithContext(ctx, field);
}

pub fn typedOneofMessageFieldWithContext(ctx: *const CodegenContext, field: *const schema.FieldDescriptor) ?[]const u8 {
    if (field.oneof_name == null) return null;
    return typedLengthPrefixedOrGroupFieldWithContext(ctx, field);
}

pub fn typedMapMessageValueWithContext(ctx: *const CodegenContext, field: *const schema.FieldDescriptor) ?[]const u8 {
    const map_type = switch (field.kind) {
        .map => |map| map,
        else => return null,
    };
    return switch (map_type.value.*) {
        .message => |name| if (codegenCanReferenceMessageWithContext(ctx, name)) name else null,
        else => null,
    };
}



pub fn findExtensionExtendeeInFile(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor) ?*const schema.MessageDescriptor {
    const extendee = field.extendee orelse return null;
    if (std.mem.startsWith(u8, extendee, ".")) return findMessageByQualifiedName(file, extendee);
    if (extensionScopeForCodegen(file, field)) |scope| {
        var current = scope;
        while (true) {
            var buf: [512]u8 = undefined;
            if (current.len + 1 + extendee.len <= buf.len) {
                const candidate = std.fmt.bufPrint(&buf, "{s}.{s}", .{ current, extendee }) catch unreachable;
                if (findMessageByQualifiedName(file, candidate)) |message| return message;
            }
            if (std.mem.lastIndexOfScalar(u8, current, '.')) |idx| {
                current = current[0..idx];
            } else break;
        }
    }
    if (std.mem.indexOfScalar(u8, extendee, '.') != null) return findMessageByQualifiedName(file, extendee);
    return null;
}

pub fn findMessageByPath(messages: []const schema.MessageDescriptor, path: []const u8) ?*const schema.MessageDescriptor {
    if (path.len == 0) return null;
    const head, const tail = splitFirst(path);
    for (messages) |*message| {
        if (!std.mem.eql(u8, message.name, head)) continue;
        if (tail.len == 0) return message;
        return findMessageByPath(message.messages.items, tail);
    }
    return null;
}

pub fn typedLengthPrefixedOrGroupFieldWithContext(ctx: *const CodegenContext, field: *const schema.FieldDescriptor) ?[]const u8 {
    const type_name = switch (field.kind) {
        .message => |name| blk: {
            if (fieldMessageEncoding(ctx.file, field) != .length_prefixed) return null;
            break :blk name;
        },
        .group => |name| name,
        else => return null,
    };
    if (!codegenCanReferenceMessageWithContext(ctx, type_name)) return null;
    if (field.cardinality != .repeated and fieldCreatesValueDependencyCycle(ctx, field, type_name)) return null;
    return type_name;
}

pub fn writeTypedMessageTypeWithContext(ctx: *const CodegenContext, type_name: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeByte('?');
    try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
}



pub fn splitFirst(name: []const u8) struct { []const u8, []const u8 } {
    if (std.mem.indexOfScalar(u8, name, '.')) |idx| return .{ name[0..idx], name[idx + 1 ..] };
    return .{ name, "" };
}

pub fn fieldCreatesValueDependencyCycle(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, type_name: []const u8) bool {
    const current = containingMessageForField(ctx.file, field) orelse return false;
    const target_ref = resolveMessageReference(ctx, type_name) orelse return false;
    if (!sameFileForCodegen(target_ref.file, ctx.file)) return false;
    return messageHasValuePathTo(ctx, target_ref.message, current, 0);
}

pub fn writeTypedRepeatedMessageTypeWithContext(ctx: *const CodegenContext, type_name: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("[]const ");
    try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
}



pub fn containingMessageForField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor) ?*const schema.MessageDescriptor {
    for (file.messages.items) |*message| {
        if (messageContainsField(message, field)) |owner| return owner;
    }
    return null;
}



pub fn messageContainsField(message: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) ?*const schema.MessageDescriptor {
    for (message.fields.items) |*candidate| {
        if (candidate == field) return message;
    }
    for (message.messages.items) |*nested| {
        if (messageContainsField(nested, field)) |owner| return owner;
    }
    return null;
}

pub fn messageHasValuePathTo(ctx: *const CodegenContext, from: *const schema.MessageDescriptor, target: *const schema.MessageDescriptor, depth: usize) bool {
    if (from == target) return true;
    if (depth >= 64) return true;
    for (from.fields.items) |*field| {
        if (field.cardinality == .repeated or field.kind == .map) continue;
        const type_name = switch (field.kind) {
            .message => |name| blk: {
                if (fieldMessageEncoding(ctx.file, field) != .length_prefixed) continue;
                break :blk name;
            },
            .group => |name| name,
            else => continue,
        };
        const ref = resolveMessageReference(ctx, type_name) orelse continue;
        if (!sameFileForCodegen(ref.file, ctx.file)) continue;
        if (messageHasValuePathTo(ctx, ref.message, target, depth + 1)) return true;
    }
    return false;
}



test {
    _ = @import("codegen/tests.zig");
}
