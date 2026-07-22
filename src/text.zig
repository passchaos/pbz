const std = @import("std");
const schema = @import("schema.zig");
const dynamic = @import("dynamic.zig");
const registry_mod = @import("registry.zig");
const wire = @import("wire.zig");

pub const Error = std.Io.Writer.Error || wire.Error || std.mem.Allocator.Error || error{ TypeMismatch, InvalidUtf8 };

pub const Options = struct {
    indent: []const u8 = "  ",
    enum_as_name: bool = true,
    print_unknown_fields: bool = false,
};

pub fn formatAlloc(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    message: *const dynamic.DynamicMessage,
    options: Options,
) (Error || std.mem.Allocator.Error)![]u8 {
    return try formatAllocWithRegistry(allocator, file, null, message, options);
}

pub fn formatAllocWithRegistry(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    registry: ?*const registry_mod.Registry,
    message: *const dynamic.DynamicMessage,
    options: Options,
) (Error || std.mem.Allocator.Error)![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    try formatWithRegistry(file, registry, message, options, &out.writer);
    return try out.toOwnedSlice();
}

pub fn format(
    file: *const schema.FileDescriptor,
    message: *const dynamic.DynamicMessage,
    options: Options,
    writer: *std.Io.Writer,
) Error!void {
    try formatWithRegistry(file, null, message, options, writer);
}

pub fn formatWithRegistry(
    file: *const schema.FileDescriptor,
    registry: ?*const registry_mod.Registry,
    message: *const dynamic.DynamicMessage,
    options: Options,
    writer: *std.Io.Writer,
) Error!void {
    try writeMessageFields(file, registry, message, options, writer, 0);
}

fn writeMessageFields(
    file: *const schema.FileDescriptor,
    registry: ?*const registry_mod.Registry,
    message: *const dynamic.DynamicMessage,
    options: Options,
    writer: *std.Io.Writer,
    depth: usize,
) Error!void {
    for (message.fields.items) |*entry| {
        if (entry.descriptor.kind == .map) {
            for (entry.values.items) |value| try writeMapEntry(file, registry, message.descriptor, entry.descriptor, value, options, writer, depth);
        } else if (entry.descriptor.cardinality == .repeated) {
            for (entry.values.items) |value| try writeField(file, registry, message.descriptor, entry.descriptor, entry.descriptor.name, entry.descriptor.kind, value, options, writer, depth);
        } else if (entry.values.items.len != 0) {
            try writeField(file, registry, message.descriptor, entry.descriptor, entry.descriptor.name, entry.descriptor.kind, entry.values.items[entry.values.items.len - 1], options, writer, depth);
        }
    }
    if (options.print_unknown_fields) {
        for (message.unknown_fields.items) |*unknown| try writeUnknownRaw(unknown.data, options, writer, depth);
    }
}

fn writeUnknownRaw(
    raw: []const u8,
    options: Options,
    writer: *std.Io.Writer,
    depth: usize,
) Error!void {
    var reader = wire.Reader.init(raw);
    while (try reader.nextTag()) |tag| try writeUnknownField(tag, &reader, options, writer, depth);
}

fn writeUnknownField(
    tag: wire.Tag,
    reader: *wire.Reader,
    options: Options,
    writer: *std.Io.Writer,
    depth: usize,
) Error!void {
    switch (tag.wire_type) {
        .varint => {
            try writeIndent(writer, options, depth);
            try writer.print("{d}: {d}\n", .{ tag.number, try reader.readVarint() });
        },
        .fixed32 => {
            try writeIndent(writer, options, depth);
            try writer.print("{d}: {d}\n", .{ tag.number, try reader.readFixed32() });
        },
        .fixed64 => {
            try writeIndent(writer, options, depth);
            try writer.print("{d}: {d}\n", .{ tag.number, try reader.readFixed64() });
        },
        .length_delimited => {
            try writeIndent(writer, options, depth);
            const bytes = try reader.readBytes();
            if (isLikelyUnknownMessage(bytes)) {
                try writer.print("{d} {{\n", .{tag.number});
                var nested = wire.Reader.init(bytes);
                while (try nested.nextTag()) |inner| try writeUnknownField(inner, &nested, options, writer, depth + 1);
                try writeIndent(writer, options, depth);
                try writer.writeAll("}\n");
            } else {
                try writer.print("{d}: ", .{tag.number});
                try writeQuoted(bytes, writer);
                try writer.writeAll("\n");
            }
        },
        .start_group => {
            try writeIndent(writer, options, depth);
            try writer.print("{d} {{\n", .{tag.number});
            while (try reader.nextTag()) |inner| {
                if (inner.wire_type == .end_group) {
                    if (inner.number != tag.number) return error.TypeMismatch;
                    try writeIndent(writer, options, depth);
                    try writer.writeAll("}\n");
                    return;
                }
                try writeUnknownField(inner, reader, options, writer, depth + 1);
            }
            return error.TypeMismatch;
        },
        .end_group => return error.TypeMismatch,
    }
}

fn isLikelyUnknownMessage(bytes: []const u8) bool {
    if (bytes.len == 0) return false;
    var reader = wire.Reader.init(bytes);
    while (true) {
        const tag = reader.nextTag() catch return false;
        const actual = tag orelse return reader.eof();
        reader.skipValue(actual) catch return false;
    }
}

fn writeMapEntry(
    file: *const schema.FileDescriptor,
    registry: ?*const registry_mod.Registry,
    current: *const schema.MessageDescriptor,
    field: *const schema.FieldDescriptor,
    value: dynamic.Value,
    options: Options,
    writer: *std.Io.Writer,
    depth: usize,
) Error!void {
    const map_type = switch (field.kind) {
        .map => |map| map,
        else => return error.TypeMismatch,
    };
    const entry = switch (value) {
        .map_entry => |entry| entry,
        else => return error.TypeMismatch,
    };
    try writeIndent(writer, options, depth);
    try writeFieldName(file, field, field.name, writer);
    try writer.writeAll(" {\n");
    try validateTextFormatUtf8(file, registry, field, .{ .scalar = map_type.key }, entry.key);
    try validateTextFormatUtf8(file, registry, field, map_type.value.*, entry.value);
    try writeField(file, registry, current, null, "key", .{ .scalar = map_type.key }, entry.key, options, writer, depth + 1);
    try writeField(file, registry, current, null, "value", map_type.value.*, entry.value, options, writer, depth + 1);
    try writeIndent(writer, options, depth);
    try writer.writeAll("}\n");
}

fn writeField(
    file: *const schema.FileDescriptor,
    registry: ?*const registry_mod.Registry,
    current: ?*const schema.MessageDescriptor,
    field: ?*const schema.FieldDescriptor,
    name: []const u8,
    kind: schema.FieldKind,
    value: dynamic.Value,
    options: Options,
    writer: *std.Io.Writer,
    depth: usize,
) Error!void {
    const field_file = registry_mod.fieldDefiningFile(file, registry, field);
    try writeIndent(writer, options, depth);
    switch (kind) {
        .message => |type_name| {
            if (value == .enumeration) {
                if (registryEnumDescriptor(field_file, registry, current, field, type_name)) |_| {
                    try writeFieldName(file, field, name, writer);
                    try writer.writeAll(": ");
                    try writeEnum(field_file, registry, current, type_name, value, options, writer);
                    try writer.writeAll("\n");
                    return;
                }
            }
            switch (value) {
                .message => |message| {
                    try writeFieldName(file, field, name, writer);
                    try writer.writeAll(" {\n");
                    if (!try writeAnyContents(field_file, registry, message, options, writer, depth + 1)) {
                        try writeMessageFields(registry_mod.messageDefiningFile(field_file, registry, message.descriptor), registry, message, options, writer, depth + 1);
                    }
                    try writeIndent(writer, options, depth);
                    try writer.writeAll("}\n");
                },
                else => return error.TypeMismatch,
            }
        },
        .group => switch (value) {
            .group => |message| {
                const group_name = if (field) |descriptor| switch (descriptor.kind) {
                    .group => |type_name| type_name,
                    else => name,
                } else name;
                try writeFieldName(file, field, group_name, writer);
                try writer.writeAll(" {\n");
                try writeMessageFields(registry_mod.messageDefiningFile(field_file, registry, message.descriptor), registry, message, options, writer, depth + 1);
                try writeIndent(writer, options, depth);
                try writer.writeAll("}\n");
            },
            else => return error.TypeMismatch,
        },
        else => {
            try validateTextFormatUtf8(file, registry, field, kind, value);
            try writeFieldName(file, field, name, writer);
            try writer.writeAll(": ");
            try writeValue(field_file, registry, current, kind, value, options, writer);
            try writer.writeAll("\n");
        },
    }
}

fn writeAnyContents(
    file: *const schema.FileDescriptor,
    registry: ?*const registry_mod.Registry,
    message: *const dynamic.DynamicMessage,
    options: Options,
    writer: *std.Io.Writer,
    depth: usize,
) (Error || std.mem.Allocator.Error)!bool {
    if (!isAnyDescriptor(message.descriptor)) return false;
    const type_url = readStringField(message, "type_url") orelse return false;
    const value = readBytesField(message, "value") orelse return false;
    const payload_desc = resolveMessageDescriptorWithRegistry(file, registry, message.descriptor, anyTypeName(type_url)) orelse return false;
    var nested = dynamic.DynamicMessage.init(message.allocator, payload_desc);
    defer nested.deinit();
    const payload_file = registry_mod.messageDefiningFile(file, registry, payload_desc);
    if (registry) |reg| {
        try nested.decodeWithRegistry(payload_file, reg, value);
    } else {
        try nested.decode(payload_file, value);
    }
    try writeIndent(writer, options, depth);
    try writer.print("[{s}] {{\n", .{type_url});
    try writeMessageFields(payload_file, registry, &nested, options, writer, depth + 1);
    try writeIndent(writer, options, depth);
    try writer.writeAll("}\n");
    return true;
}

fn isAnyDescriptor(descriptor: *const schema.MessageDescriptor) bool {
    return std.mem.eql(u8, descriptor.name, "Any") and
        descriptor.findField("type_url") != null and
        descriptor.findField("value") != null;
}

fn readStringField(message: *const dynamic.DynamicMessage, name: []const u8) ?[]const u8 {
    if (message.get(name)) |field| if (field.values.items.len != 0 and field.values.items[0] == .string) return field.values.items[0].string;
    return null;
}

fn readBytesField(message: *const dynamic.DynamicMessage, name: []const u8) ?[]const u8 {
    if (message.get(name)) |field| if (field.values.items.len != 0 and field.values.items[0] == .bytes) return field.values.items[0].bytes;
    return null;
}

fn anyTypeName(type_url: []const u8) []const u8 {
    return if (std.mem.lastIndexOfScalar(u8, type_url, '/')) |idx| type_url[idx + 1 ..] else type_url;
}

fn anyTypeUrlIsValid(type_url: []const u8) bool {
    const slash = std.mem.lastIndexOfScalar(u8, type_url, '/') orelse return false;
    return slash != type_url.len - 1;
}

fn validateAnyTypeUrlPercentEscapes(type_url: []const u8) !void {
    var index: usize = 0;
    while (index < type_url.len) : (index += 1) {
        if (type_url[index] != '%') continue;
        if (index + 2 >= type_url.len) return error.InvalidCharacter;
        _ = hexValue(type_url[index + 1]) orelse return error.InvalidCharacter;
        _ = hexValue(type_url[index + 2]) orelse return error.InvalidCharacter;
        index += 2;
    }
}

fn writeFieldName(file: *const schema.FileDescriptor, field: ?*const schema.FieldDescriptor, fallback: []const u8, writer: *std.Io.Writer) Error!void {
    const descriptor = field orelse return try writer.writeAll(fallback);
    if (descriptor.extendee == null) return try writer.writeAll(fallback);
    try writer.writeByte('[');
    const full_name = schema.extensionFullName(descriptor);
    if (std.mem.startsWith(u8, full_name, ".")) {
        try writer.writeAll(full_name[1..]);
    } else if (std.mem.indexOfScalar(u8, full_name, '.') != null or file.package.len == 0) {
        try writer.writeAll(full_name);
    } else {
        try writer.print("{s}.{s}", .{ file.package, full_name });
    }
    try writer.writeByte(']');
}

fn validateTextFormatUtf8(file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, field: ?*const schema.FieldDescriptor, kind: schema.FieldKind, value: dynamic.Value) Error!void {
    if (fieldUtf8Validation(registry_mod.fieldDefiningFile(file, registry, field), field) != .verify) return;
    switch (kind) {
        .scalar => |scalar| if (scalar == .string and value == .string and !std.unicode.utf8ValidateSlice(value.string)) return error.InvalidUtf8,
        else => {},
    }
}

fn writeValue(
    file: *const schema.FileDescriptor,
    registry: ?*const registry_mod.Registry,
    current: ?*const schema.MessageDescriptor,
    kind: schema.FieldKind,
    value: dynamic.Value,
    options: Options,
    writer: *std.Io.Writer,
) Error!void {
    switch (kind) {
        .scalar => |scalar| try writeScalar(scalar, value, writer),
        .enumeration => |name| try writeEnum(file, registry, current, name, value, options, writer),
        .message => |name| {
            if (value == .enumeration and registryEnumDescriptor(file, registry, current, null, name) != null) return try writeEnum(file, registry, current, name, value, options, writer);
            return error.TypeMismatch;
        },
        .group, .map => return error.TypeMismatch,
    }
}

fn writeScalar(scalar: schema.ScalarType, value: dynamic.Value, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .double => switch (value) {
            .double => |v| try writer.print("{d}", .{v}),
            else => return error.TypeMismatch,
        },
        .float => switch (value) {
            .float => |v| try writer.print("{d}", .{v}),
            else => return error.TypeMismatch,
        },
        .int32 => switch (value) {
            .int32 => |v| try writer.print("{d}", .{v}),
            else => return error.TypeMismatch,
        },
        .int64 => switch (value) {
            .int64 => |v| try writer.print("{d}", .{v}),
            else => return error.TypeMismatch,
        },
        .uint32 => switch (value) {
            .uint32 => |v| try writer.print("{d}", .{v}),
            else => return error.TypeMismatch,
        },
        .uint64 => switch (value) {
            .uint64 => |v| try writer.print("{d}", .{v}),
            else => return error.TypeMismatch,
        },
        .sint32 => switch (value) {
            .sint32 => |v| try writer.print("{d}", .{v}),
            else => return error.TypeMismatch,
        },
        .sint64 => switch (value) {
            .sint64 => |v| try writer.print("{d}", .{v}),
            else => return error.TypeMismatch,
        },
        .fixed32 => switch (value) {
            .fixed32 => |v| try writer.print("{d}", .{v}),
            else => return error.TypeMismatch,
        },
        .fixed64 => switch (value) {
            .fixed64 => |v| try writer.print("{d}", .{v}),
            else => return error.TypeMismatch,
        },
        .sfixed32 => switch (value) {
            .sfixed32 => |v| try writer.print("{d}", .{v}),
            else => return error.TypeMismatch,
        },
        .sfixed64 => switch (value) {
            .sfixed64 => |v| try writer.print("{d}", .{v}),
            else => return error.TypeMismatch,
        },
        .bool => switch (value) {
            .boolean => |v| try writer.writeAll(if (v) "true" else "false"),
            else => return error.TypeMismatch,
        },
        .string => switch (value) {
            .string => |v| try writeQuoted(v, writer),
            else => return error.TypeMismatch,
        },
        .bytes => switch (value) {
            .bytes => |v| try writeQuoted(v, writer),
            else => return error.TypeMismatch,
        },
    }
}

fn writeEnum(
    file: *const schema.FileDescriptor,
    registry: ?*const registry_mod.Registry,
    current: ?*const schema.MessageDescriptor,
    name: []const u8,
    value: dynamic.Value,
    options: Options,
    writer: *std.Io.Writer,
) Error!void {
    const number = switch (value) {
        .enumeration => |v| v,
        else => return error.TypeMismatch,
    };
    if (options.enum_as_name) {
        if (registryEnumDescriptor(file, registry, current, null, name) orelse file.findEnumDeep(name)) |enumeration| {
            for (enumeration.values.items) |enum_value| {
                if (enum_value.number == number) return try writer.writeAll(enum_value.name);
            }
        }
    }
    try writer.print("{d}", .{number});
}

fn registryEnumDescriptor(file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, current: ?*const schema.MessageDescriptor, field: ?*const schema.FieldDescriptor, name: []const u8) ?*const schema.EnumDescriptor {
    if (std.mem.indexOfScalar(u8, name, '.') == null) {
        if (current) |message| {
            if (message.findEnumDeep(name)) |enumeration| return enumeration;
        }
        if (file.findEnumDeep(name)) |enumeration| return enumeration;
    }
    if (registry) |reg| {
        var scope_buf: [512]u8 = undefined;
        const scope = if (current) |message| messageScope(file, message, &scope_buf) orelse if (file.package.len != 0) file.package else null else if (file.package.len != 0) file.package else null;
        if (reg.findEnumVisible(file, name, scope)) |enumeration| return enumeration;
        if (reg.findEnum(name, scope)) |enumeration| return enumeration;
        if (field) |descriptor| {
            if (reg.findEnum(name, descriptor.name)) |enumeration| return enumeration;
        }
    }
    const trimmed = if (std.mem.startsWith(u8, name, ".")) name[1..] else name;
    return file.findEnumDeep(trimmed);
}

fn messageScope(file: *const schema.FileDescriptor, current: *const schema.MessageDescriptor, buf: *[512]u8) ?[]const u8 {
    for (file.messages.items) |*message| {
        if (message == current) return formatMessageScope(file.package, message.name, buf);
        if (messageScopeInMessage(file.package, message.name, message, current, buf)) |path| return path;
    }
    return null;
}

fn messageScopeInMessage(package: []const u8, prefix: []const u8, message: *const schema.MessageDescriptor, target: *const schema.MessageDescriptor, buf: *[512]u8) ?[]const u8 {
    for (message.messages.items) |*nested| {
        var path_buf: [512]u8 = undefined;
        const nested_path = std.fmt.bufPrint(&path_buf, "{s}.{s}", .{ prefix, nested.name }) catch return null;
        if (nested == target) return formatMessageScope(package, nested_path, buf);
        if (messageScopeInMessage(package, nested_path, nested, target, buf)) |path| return path;
    }
    return null;
}

fn formatMessageScope(package: []const u8, path: []const u8, buf: *[512]u8) ?[]const u8 {
    if (package.len == 0) return std.fmt.bufPrint(buf, "{s}", .{path}) catch null;
    return std.fmt.bufPrint(buf, "{s}.{s}", .{ package, path }) catch null;
}

fn writeQuoted(bytes: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("\"");
    if (!textStringNeedsEscape(bytes)) {
        try writer.writeAll(bytes);
        try writer.writeAll("\"");
        return;
    }
    for (bytes) |c| {
        if (c == '\\') try writer.writeAll("\\\\") else if (c == '"') try writer.writeAll("\\\"") else if (c == '\n') try writer.writeAll("\\n") else if (c == '\r') try writer.writeAll("\\r") else if (c == '\t') try writer.writeAll("\\t") else if (c >= 0x20 and c <= 0x7e) try writer.writeByte(c) else try writer.print("\\{o:0>3}", .{c});
    }
    try writer.writeAll("\"");
}

fn textStringNeedsEscape(bytes: []const u8) bool {
    const vector_len = std.simd.suggestVectorLength(u8) orelse 0;
    if (vector_len >= 8) {
        const V = @Vector(vector_len, u8);
        var index: usize = 0;
        const quote: V = @splat('"');
        const slash: V = @splat('\\');
        const min_printable: V = @splat(0x20);
        const max_printable: V = @splat(0x7e);
        while (index + vector_len <= bytes.len) : (index += vector_len) {
            const chunk: V = bytes[index..][0..vector_len].*;
            if (@reduce(.Or, (chunk == quote) | (chunk == slash) | (chunk < min_printable) | (chunk > max_printable))) return true;
        }
        for (bytes[index..]) |byte| {
            if (byte == '"' or byte == '\\' or byte < 0x20 or byte > 0x7e) return true;
        }
        return false;
    }
    for (bytes) |byte| {
        if (byte == '"' or byte == '\\' or byte < 0x20 or byte > 0x7e) return true;
    }
    return false;
}

fn writeIndent(writer: *std.Io.Writer, options: Options, depth: usize) Error!void {
    var i: usize = 0;
    while (i < depth) : (i += 1) try writer.writeAll(options.indent);
}

test "text format writes dynamic messages" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message Child { string label = 1; }
        \\message Bag {
        \\  int32 id = 1;
        \\  repeated string tags = 2;
        \\  map<string, int32> counts = 3;
        \\  Child child = 4;
        \\  Kind kind = 5;
        \\}
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const bag_desc = file.findMessage("Bag").?;
    const child_desc = file.findMessage("Child").?;

    var bag = dynamic.DynamicMessage.init(allocator, bag_desc);
    defer bag.deinit();
    try bag.add(bag_desc.findField("id").?, .{ .int32 = 7 });
    try bag.add(bag_desc.findField("tags").?, .{ .string = try allocator.dupe(u8, "a") });
    const entry = try allocator.create(dynamic.MapEntry);
    entry.* = .{ .key = .{ .string = try allocator.dupe(u8, "red") }, .value = .{ .int32 = 3 } };
    try bag.add(bag_desc.findField("counts").?, .{ .map_entry = entry });
    const child = try allocator.create(dynamic.DynamicMessage);
    child.* = dynamic.DynamicMessage.init(allocator, child_desc);
    try child.add(child_desc.findField("label").?, .{ .string = try allocator.dupe(u8, "kid") });
    try bag.add(bag_desc.findField("child").?, .{ .message = child });
    try bag.add(bag_desc.findField("kind").?, .{ .enumeration = 1 });

    const text = try formatAlloc(allocator, &file, &bag, .{});
    defer allocator.free(text);
    try std.testing.expectEqualSlices(u8,
        \\id: 7
        \\tags: "a"
        \\counts {
        \\  key: "red"
        \\  value: 3
        \\}
        \\child {
        \\  label: "kid"
        \\}
        \\kind: ADMIN
        \\
    , text);
}

test "text format formats imported enum names with registry" {
    const allocator = std.testing.allocator;
    var common = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package common;
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
    );
    defer common.deinit();
    var app = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package app;
        \\message Event { common.Kind kind = 1; }
    );
    defer app.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);

    const desc = app.findMessage("Event").?;
    var msg = dynamic.DynamicMessage.init(allocator, desc);
    defer msg.deinit();
    try msg.add(desc.findField("kind").?, .{ .enumeration = 1 });

    const rendered = try formatAllocWithRegistry(allocator, &app, &registry, &msg, .{});
    defer allocator.free(rendered);
    try std.testing.expectEqualSlices(u8, "kind: ADMIN\n", rendered);
}

test "text registry keeps local enum priority over imported enum" {
    const allocator = std.testing.allocator;
    var common = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\enum Kind { UNKNOWN = 0; IMPORTED = 1; }
    );
    defer common.deinit();
    common.name = "common.proto";
    var app = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\import "common.proto";
        \\message Event {
        \\  enum Kind { LOCAL = 7; }
        \\  optional Kind kind = 1 [default = LOCAL];
        \\  map<string, Kind> keyed = 2;
        \\}
    );
    defer app.deinit();
    app.name = "app.proto";
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);
    try registry.validateFileReferences(&app);

    var parsed = try parseAllocWithRegistry(allocator, &app, &registry, app.findMessage("Event").?,
        \\kind: LOCAL
        \\keyed { key: "one" value: LOCAL }
    );
    defer parsed.deinit();
    try std.testing.expectEqual(@as(i32, 7), parsed.get("kind").?.values.items[0].enumeration);
    try std.testing.expectEqual(@as(i32, 7), parsed.get("keyed").?.values.items[0].map_entry.value.enumeration);

    const rendered = try formatAllocWithRegistry(allocator, &app, &registry, &parsed, .{});
    defer allocator.free(rendered);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "kind: LOCAL\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "value: LOCAL\n") != null);
}

test "text registry resolves same-package imported unqualified fields" {
    const allocator = std.testing.allocator;
    var common = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message User { optional string name = 1; }
        \\enum Kind { UNKNOWN = 0; ADMIN = 7; }
    );
    defer common.deinit();
    common.name = "common.proto";
    var app = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\import "common.proto";
        \\message Event { optional User user = 1; optional Kind kind = 2 [default = ADMIN]; }
    );
    defer app.deinit();
    app.name = "app.proto";
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);
    try registry.validateFileReferences(&app);

    var parsed = try parseAllocWithRegistry(allocator, &app, &registry, app.findMessage("Event").?,
        \\user { name: "Ada" }
        \\kind: ADMIN
    );
    defer parsed.deinit();

    try std.testing.expectEqualStrings("Ada", parsed.get("user").?.values.items[0].message.get("name").?.values.items[0].string);
    try std.testing.expectEqual(@as(i32, 7), parsed.get("kind").?.values.items[0].enumeration);

    const rendered = try formatAllocWithRegistry(allocator, &app, &registry, &parsed, .{});
    defer allocator.free(rendered);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "user {\n  name: \"Ada\"\n}\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "kind: ADMIN\n") != null);
}

test "text format parses imported message and enum fields with registry" {
    const allocator = std.testing.allocator;
    var common = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package common;
        \\message User { string name = 1; }
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
    );
    defer common.deinit();
    var app = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package app;
        \\message Event {
        \\  common.User user = 1;
        \\  common.Kind kind = 2;
        \\  map<string, common.Kind> roles = 3;
        \\}
    );
    defer app.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);

    const desc = app.findMessage("Event").?;
    var parsed = try parseAllocWithRegistry(allocator, &app, &registry, desc,
        \\user { name: "Ada" }
        \\kind: ADMIN
        \\roles { key: "root" value: ADMIN }
    );
    defer parsed.deinit();
    try std.testing.expectEqualSlices(u8, "Ada", parsed.get("user").?.values.items[0].message.get("name").?.values.items[0].string);
    try std.testing.expectEqual(@as(i32, 1), parsed.get("kind").?.values.items[0].enumeration);
    try std.testing.expectEqual(@as(i32, 1), parsed.get("roles").?.values.items[0].map_entry.value.enumeration);
}

test "text imported enums use owning file features" {
    const allocator = std.testing.allocator;
    var open_file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package openpkg;
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
    );
    defer open_file.deinit();
    open_file.name = "open.proto";
    var closed_file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package closedpkg;
        \\enum Kind { ADMIN = 1; }
    );
    defer closed_file.deinit();
    closed_file.name = "closed.proto";
    var proto2_app = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package app2;
        \\import "open.proto";
        \\message Event { optional openpkg.Kind kind = 1; }
    );
    defer proto2_app.deinit();
    proto2_app.name = "app2.proto";
    var proto3_app = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package app3;
        \\import "closed.proto";
        \\message Event { closedpkg.Kind kind = 1; }
    );
    defer proto3_app.deinit();
    proto3_app.name = "app3.proto";

    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&open_file);
    try registry.addFile(&closed_file);
    try registry.addFile(&proto2_app);
    try registry.addFile(&proto3_app);

    var open_in_proto2 = try parseAllocWithRegistry(allocator, &proto2_app, &registry, proto2_app.findMessage("Event").?, "kind: 123");
    defer open_in_proto2.deinit();
    try std.testing.expectEqual(@as(i32, 123), open_in_proto2.get("kind").?.values.items[0].enumeration);

    try std.testing.expectError(error.InvalidEnumValue, parseAllocWithRegistry(allocator, &proto3_app, &registry, proto3_app.findMessage("Event").?, "kind: 123"));
}

test "text imported messages use owning file features" {
    const allocator = std.testing.allocator;
    var common = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package common;
        \\message Payload { optional string raw = 1; }
    );
    defer common.deinit();
    common.name = "common.proto";
    var app = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package app;
        \\import "common.proto";
        \\message Event {
        \\  common.Payload payload = 1;
        \\  map<string, common.Payload> keyed = 2;
        \\}
    );
    defer app.deinit();
    app.name = "app.proto";
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);

    const desc = app.findMessage("Event").?;
    var parsed = try parseAllocWithRegistry(allocator, &app, &registry, desc,
        \\payload { raw: "\300" }
        \\keyed { key: "one" value { raw: "\300" } }
    );
    defer parsed.deinit();

    try std.testing.expectEqualSlices(u8, &.{0xc0}, parsed.get("payload").?.values.items[0].message.get("raw").?.values.items[0].string);
    const entry = parsed.get("keyed").?.values.items[0].map_entry;
    try std.testing.expectEqualStrings("one", entry.key.string);
    try std.testing.expectEqualSlices(u8, &.{0xc0}, entry.value.message.get("raw").?.values.items[0].string);

    const rendered = try formatAllocWithRegistry(allocator, &app, &registry, &parsed, .{});
    defer allocator.free(rendered);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "payload {\n  raw: \"\\300\"\n}\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "value {\n    raw: \"\\300\"\n  }\n") != null);
}

pub fn parseAlloc(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    descriptor: *const schema.MessageDescriptor,
    input: []const u8,
) !dynamic.DynamicMessage {
    return parseAllocWithRegistry(allocator, file, null, descriptor, input);
}

pub fn parseAllocWithRegistry(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    registry: ?*const registry_mod.Registry,
    descriptor: *const schema.MessageDescriptor,
    input: []const u8,
) !dynamic.DynamicMessage {
    var parser_state = TextParser{ .allocator = allocator, .input = input, .registry = registry };
    var message = dynamic.DynamicMessage.init(allocator, descriptor);
    errdefer message.deinit();
    try parser_state.parseMessage(file, &message, null);
    return message;
}

pub fn parseInitializedAlloc(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    descriptor: *const schema.MessageDescriptor,
    input: []const u8,
) !dynamic.DynamicMessage {
    return parseInitializedAllocWithRegistry(allocator, file, null, descriptor, input);
}

pub fn parseInitializedAllocWithRegistry(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    registry: ?*const registry_mod.Registry,
    descriptor: *const schema.MessageDescriptor,
    input: []const u8,
) !dynamic.DynamicMessage {
    var message = try parseAllocWithRegistry(allocator, file, registry, descriptor, input);
    errdefer message.deinit();
    try message.validateRequired();
    return message;
}

const TextParser = struct {
    allocator: std.mem.Allocator,
    input: []const u8,
    registry: ?*const registry_mod.Registry = null,
    index: usize = 0,

    fn parseMessage(self: *TextParser, file: *const schema.FileDescriptor, message: *dynamic.DynamicMessage, end: ?u8) anyerror!void {
        while (true) {
            self.skipSpace();
            if (self.eof()) {
                if (end != null) return error.UnexpectedEof;
                return;
            }
            if (end) |end_char| {
                if (self.peek() == end_char) {
                    self.index += 1;
                    return;
                }
            }
            if (isAnyDescriptor(message.descriptor) and self.peek() == '[') {
                try self.parseAnyExpandedField(file, message);
                self.consumeSeparator();
                continue;
            }
            const unknown_number = if (self.peekIsDigit() != null) try self.readUnknownNumber() else null;
            const field = if (unknown_number != null) null else self.readFieldReference(message.descriptor) catch |err| switch (err) {
                error.ReservedField => {
                    try self.skipReservedFieldValue();
                    self.consumeSeparator();
                    continue;
                },
                else => return err,
            };
            self.skipSpace();
            if (self.consume(':')) {
                self.skipSpace();
                if (field == null) {
                    try self.parseUnknownField(message, unknown_number.?);
                    self.consumeSeparator();
                } else {
                    const field_file = registry_mod.fieldDefiningFile(file, self.registry, field);
                    if (field.?.kind == .map or field.?.kind == .group or (field.?.kind == .message and !self.fieldIsRegistryEnum(field_file, message.descriptor, field.?))) {
                        const close = try self.consumeAggregateStart();
                        try self.parseAggregateField(field_file, message, field.?, close);
                    } else if (field.?.cardinality == .repeated and self.peek() == '[') {
                        try self.parseRepeatedList(field_file, message, field.?);
                        self.consumeSeparator();
                    } else {
                        try self.addOwnedValue(message, field.?, try self.parseValue(field_file, message.descriptor, field.?, field.?.kind));
                        self.consumeSeparator();
                    }
                }
            } else if (self.peek() == '{' or self.peek() == '<') {
                const close = try self.consumeAggregateStart();
                if (field == null) {
                    try self.parseUnknownGroup(message, unknown_number.?, close);
                    self.consumeSeparator();
                } else {
                    try self.parseAggregateField(registry_mod.fieldDefiningFile(file, self.registry, field), message, field.?, close);
                }
            } else return error.UnexpectedToken;
        }
    }

    fn parseAnyExpandedField(self: *TextParser, file: *const schema.FileDescriptor, message: *dynamic.DynamicMessage) anyerror!void {
        const type_url = try self.readAnyTypeUrl();
        defer self.allocator.free(type_url);
        if (!anyTypeUrlIsValid(type_url)) return error.TypeMismatch;
        const close = try self.consumeAggregateStart();
        const payload_desc = resolveMessageDescriptorWithRegistry(file, self.registry, message.descriptor, anyTypeName(type_url)) orelse return error.TypeMismatch;
        var payload = dynamic.DynamicMessage.init(self.allocator, payload_desc);
        defer payload.deinit();
        const payload_file = registry_mod.messageDefiningFile(file, self.registry, payload_desc);
        try self.parseMessage(payload_file, &payload, close);
        const encoded = try payload.encodedDeterministicWithRegistry(payload_file, self.registry);
        defer self.allocator.free(encoded);
        const type_field = message.descriptor.findField("type_url") orelse return error.TypeMismatch;
        const value_field = message.descriptor.findField("value") orelse return error.TypeMismatch;
        try self.addOwnedValue(message, type_field, .{ .string = try self.allocator.dupe(u8, type_url) });
        try self.addOwnedValue(message, value_field, .{ .bytes = try self.allocator.dupe(u8, encoded) });
    }

    fn addOwnedValue(self: *TextParser, message: *dynamic.DynamicMessage, field: *const schema.FieldDescriptor, value: dynamic.Value) std.mem.Allocator.Error!void {
        var owned = value;
        errdefer dynamic.deinitValue(&owned, self.allocator);
        try message.add(field, owned);
    }

    fn skipReservedFieldValue(self: *TextParser) anyerror!void {
        self.skipSpace();
        if (self.consume(':')) self.skipSpace();
        if (!self.eof() and (self.peek() == '{' or self.peek() == '<')) {
            const close = try self.consumeAggregateStart();
            try self.skipAggregate(close);
            return;
        }
        if (!self.eof() and self.peek() == '[') {
            try self.skipList();
            return;
        }
        if (!self.eof() and (self.peek() == '"' or self.peek() == '\'')) {
            const bytes = try self.readString();
            self.allocator.free(bytes);
            return;
        }
        _ = try self.readAtom();
    }

    fn skipList(self: *TextParser) anyerror!void {
        try self.expect('[');
        self.skipSpace();
        if (self.consume(']')) return;
        while (true) {
            if (self.eof()) return error.UnexpectedEof;
            if (self.peek() == '{' or self.peek() == '<') {
                const close = try self.consumeAggregateStart();
                try self.skipAggregate(close);
            } else if (self.peek() == '[') {
                try self.skipList();
            } else if (self.peek() == '"' or self.peek() == '\'') {
                const bytes = try self.readString();
                self.allocator.free(bytes);
            } else {
                _ = try self.readAtom();
            }
            self.skipSpace();
            if (self.consume(']')) return;
            try self.expect(',');
            self.skipSpace();
            if (self.peek() == ']') return error.UnexpectedToken;
        }
    }

    fn skipAggregate(self: *TextParser, close: u8) anyerror!void {
        while (true) {
            self.skipSpace();
            if (self.eof()) return error.UnexpectedEof;
            if (self.consume(close)) return;
            _ = try self.readFieldLikeName();
            self.skipSpace();
            if (self.peek() == ':' or self.peek() == '{' or self.peek() == '<') {
                try self.skipReservedFieldValue();
                self.consumeSeparator();
            } else return error.UnexpectedToken;
        }
    }

    fn parseRepeatedList(self: *TextParser, file: *const schema.FileDescriptor, message: *dynamic.DynamicMessage, field: *const schema.FieldDescriptor) !void {
        try self.expect('[');
        self.skipSpace();
        if (self.consume(']')) return;
        while (true) {
            try self.addOwnedValue(message, field, try self.parseValue(file, message.descriptor, field, field.kind));
            self.skipSpace();
            if (self.consume(']')) return;
            try self.expect(',');
            self.skipSpace();
            if (self.peek() == ']') return error.UnexpectedToken;
        }
    }

    fn parseUnknownField(self: *TextParser, message: *dynamic.DynamicMessage, number: wire.FieldNumber) !void {
        var raw = wire.Writer.init(self.allocator);
        defer raw.deinit();
        try self.parseUnknownValueInto(number, &raw);
        try self.appendUnknown(message, number, raw.slice());
    }

    fn parseUnknownGroup(self: *TextParser, message: *dynamic.DynamicMessage, number: wire.FieldNumber, close: u8) !void {
        var raw = wire.Writer.init(self.allocator);
        defer raw.deinit();
        try self.parseUnknownGroupInto(number, close, &raw);
        try self.appendUnknown(message, number, raw.slice());
    }

    fn parseUnknownGroupInto(self: *TextParser, number: wire.FieldNumber, close: u8, raw: *wire.Writer) !void {
        try raw.writeTag(number, .start_group);
        while (true) {
            self.skipSpace();
            if (self.consume(close)) break;
            if (self.eof()) return error.UnexpectedEof;
            const child_number = try self.readUnknownNumber();
            self.skipSpace();
            if (self.consume(':')) {
                self.skipSpace();
                try self.parseUnknownValueInto(child_number, raw);
                self.consumeSeparator();
            } else if (self.peek() == '{' or self.peek() == '<') {
                const child_close = try self.consumeAggregateStart();
                try self.parseUnknownGroupInto(child_number, child_close, raw);
                self.consumeSeparator();
            } else return error.UnexpectedToken;
        }
        try raw.writeTag(number, .end_group);
    }

    fn parseUnknownValueInto(self: *TextParser, number: wire.FieldNumber, raw: *wire.Writer) !void {
        if (!self.eof() and (self.peek() == '"' or self.peek() == '\'')) {
            const bytes = try self.readString();
            defer self.allocator.free(bytes);
            try raw.writeBytes(number, bytes);
        } else {
            const value = try parseTextInt(u64, try self.readAtom());
            try raw.writeUInt64(number, value);
        }
    }

    fn appendUnknown(self: *TextParser, message: *dynamic.DynamicMessage, number: wire.FieldNumber, raw_bytes: []const u8) !void {
        const owned = try self.allocator.dupe(u8, raw_bytes);
        errdefer self.allocator.free(owned);
        var raw_reader = wire.Reader.init(owned);
        const tag = (try raw_reader.nextTag()) orelse return error.UnexpectedToken;
        try message.unknown_fields.append(self.allocator, .{
            .number = number,
            .wire_type = tag.wire_type,
            .data = owned,
        });
    }

    fn fieldIsRegistryEnum(self: *TextParser, file: *const schema.FileDescriptor, current: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) bool {
        const name = switch (field.kind) {
            .message => |type_name| type_name,
            else => return false,
        };
        return registryEnumDescriptor(file, self.registry, current, field, name) != null or current.findEnumDeep(name) != null;
    }

    fn readFieldReference(self: *TextParser, descriptor: *const schema.MessageDescriptor) !*const schema.FieldDescriptor {
        self.skipSpace();
        if (self.consume('[')) {
            const name = try self.readExtensionName();
            return self.findExtension(descriptor, name) orelse return error.UnknownField;
        }
        const name = try self.readIdent();
        if (isReservedName(descriptor, name)) return error.ReservedField;
        return descriptor.findField(name) orelse findGroupFieldByTypeName(descriptor, name) orelse return error.UnknownField;
    }

    fn readFieldLikeName(self: *TextParser) ![]const u8 {
        self.skipSpace();
        if (self.consume('[')) return try self.readExtensionName();
        if (self.peekIsDigit() != null) {
            const start = self.index;
            _ = try self.readUnknownNumber();
            return self.input[start..self.index];
        }
        return try self.readIdent();
    }

    fn isReservedName(descriptor: *const schema.MessageDescriptor, name: []const u8) bool {
        for (descriptor.reserved_names.items) |reserved| {
            if (std.mem.eql(u8, reserved, name)) return true;
        }
        return false;
    }

    fn readExtensionName(self: *TextParser) ![]const u8 {
        self.skipSpace();
        const start = self.index;
        while (!self.eof() and self.peek() != ']') self.index += 1;
        if (self.eof()) return error.UnexpectedEof;
        const raw = std.mem.trim(u8, self.input[start..self.index], " \t\r\n");
        try self.expect(']');
        if (raw.len == 0) return error.UnexpectedToken;
        return raw;
    }

    fn readAnyTypeUrl(self: *TextParser) ![]const u8 {
        self.skipSpace();
        try self.expect('[');
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(self.allocator);
        while (true) {
            if (self.eof()) return error.UnexpectedEof;
            const c = self.peek();
            if (c == ']') {
                self.index += 1;
                const text = try out.toOwnedSlice(self.allocator);
                errdefer self.allocator.free(text);
                if (text.len == 0) return error.UnexpectedToken;
                try validateAnyTypeUrlPercentEscapes(text);
                return text;
            }
            if (std.ascii.isWhitespace(c)) {
                self.index += 1;
                continue;
            }
            if (c == '#') {
                while (!self.eof() and self.peek() != '\n') self.index += 1;
                continue;
            }
            try out.append(self.allocator, c);
            self.index += 1;
        }
    }

    fn findGroupFieldByTypeName(descriptor: *const schema.MessageDescriptor, name: []const u8) ?*const schema.FieldDescriptor {
        for (descriptor.fields.items) |*field| {
            switch (field.kind) {
                .group => |type_name| if (std.mem.eql(u8, type_name, name)) return field,
                else => {},
            }
        }
        return null;
    }

    fn findExtension(self: *TextParser, descriptor: *const schema.MessageDescriptor, name: []const u8) ?*const schema.FieldDescriptor {
        const registry = self.registry orelse return null;
        if (registry.findExtensionByNameForMessage(descriptor, name)) |field| return field;
        const trimmed = if (std.mem.startsWith(u8, name, ".")) name[1..] else name;
        const leaf = if (std.mem.lastIndexOfScalar(u8, trimmed, '.')) |idx| trimmed[idx + 1 ..] else trimmed;
        if (!std.mem.eql(u8, leaf, name)) {
            if (registry.findExtensionByNameForMessage(descriptor, leaf)) |field| return field;
        }
        return null;
    }

    fn consumeAggregateStart(self: *TextParser) !u8 {
        self.skipSpace();
        if (self.consume('{')) return '}';
        try self.expect('<');
        return '>';
    }

    fn parseAggregateField(self: *TextParser, file: *const schema.FileDescriptor, message: *dynamic.DynamicMessage, field: *const schema.FieldDescriptor, close: u8) anyerror!void {
        if (field.kind == .map) {
            try self.addOwnedValue(message, field, try self.parseMapEntry(file, message.descriptor, field, field.kind.map, close));
            self.consumeSeparator();
        } else {
            const nested_desc = switch (field.kind) {
                .message => |type_name| resolveMessageDescriptorWithRegistry(file, self.registry, message.descriptor, type_name) orelse return error.TypeMismatch,
                .group => |type_name| resolveMessageDescriptorWithRegistry(file, self.registry, message.descriptor, type_name) orelse return error.TypeMismatch,
                else => return error.TypeMismatch,
            };
            const nested = try self.allocator.create(dynamic.DynamicMessage);
            nested.* = dynamic.DynamicMessage.init(self.allocator, nested_desc);
            errdefer {
                nested.deinit();
                self.allocator.destroy(nested);
            }
            try self.parseMessage(registry_mod.messageDefiningFile(file, self.registry, nested_desc), nested, close);
            try self.addOrMergeAggregate(message, field, nested);
            self.consumeSeparator();
        }
    }

    fn addOrMergeAggregate(self: *TextParser, message: *dynamic.DynamicMessage, field: *const schema.FieldDescriptor, nested: *dynamic.DynamicMessage) !void {
        if (shouldMergeAggregateField(field)) {
            if (message.getByNumber(field.number)) |entry| {
                if (entry.values.items.len != 0) {
                    switch (entry.values.items[0]) {
                        .message => |target| if (field.kind == .message) {
                            errdefer {
                                nested.deinit();
                                self.allocator.destroy(nested);
                            }
                            try target.mergeFrom(nested);
                            nested.deinit();
                            self.allocator.destroy(nested);
                            return;
                        },
                        .group => |target| if (field.kind == .group) {
                            errdefer {
                                nested.deinit();
                                self.allocator.destroy(nested);
                            }
                            try target.mergeFrom(nested);
                            nested.deinit();
                            self.allocator.destroy(nested);
                            return;
                        },
                        else => {},
                    }
                }
            }
        }

        const value = if (field.kind == .group) dynamic.Value{ .group = nested } else dynamic.Value{ .message = nested };
        try self.addOwnedValue(message, field, value);
    }

    fn shouldMergeAggregateField(field: *const schema.FieldDescriptor) bool {
        if (field.cardinality == .repeated or field.kind == .map or field.oneof_name != null) return false;
        return field.kind == .message or field.kind == .group;
    }

    fn parseMapEntry(self: *TextParser, file: *const schema.FileDescriptor, current: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor, map_type: schema.MapType, end: u8) !dynamic.Value {
        var key: ?dynamic.Value = null;
        var value: ?dynamic.Value = null;
        errdefer {
            if (key) |*v| dynamic.deinitValue(v, self.allocator);
            if (value) |*v| dynamic.deinitValue(v, self.allocator);
        }
        while (true) {
            self.skipSpace();
            if (self.consume(end)) break;
            if (self.eof()) return error.UnexpectedEof;
            const name = try self.readIdent();
            self.skipSpace();
            if (std.mem.eql(u8, name, "key")) {
                try self.expect(':');
                if (key) |*old| {
                    dynamic.deinitValue(old, self.allocator);
                    key = null;
                }
                key = try self.parseValue(file, current, field, .{ .scalar = map_type.key });
            } else if (std.mem.eql(u8, name, "value")) {
                if (value) |*old| {
                    dynamic.deinitValue(old, self.allocator);
                    value = null;
                }
                value = try self.parseMapEntryValue(file, current, field, map_type.value.*);
            } else return error.UnknownField;
            self.consumeSeparator();
        }
        var final_key = key orelse try defaultTextValue(self.allocator, file, self.registry, current, .{ .scalar = map_type.key });
        var final_value = value orelse try defaultTextValue(self.allocator, file, self.registry, current, map_type.value.*);
        key = null;
        value = null;
        errdefer {
            dynamic.deinitValue(&final_key, self.allocator);
            dynamic.deinitValue(&final_value, self.allocator);
        }
        const entry = try self.allocator.create(dynamic.MapEntry);
        entry.* = .{ .key = final_key, .value = final_value };
        return .{ .map_entry = entry };
    }

    fn parseMapEntryValue(self: *TextParser, file: *const schema.FileDescriptor, current: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor, kind: schema.FieldKind) !dynamic.Value {
        if (kind == .message and registryEnumDescriptor(file, self.registry, current, field, kind.message) == null) {
            _ = self.consume(':');
            const close = try self.consumeAggregateStart();
            const descriptor = resolveMessageDescriptorWithRegistry(file, self.registry, current, kind.message) orelse return error.TypeMismatch;
            const nested = try self.allocator.create(dynamic.DynamicMessage);
            nested.* = dynamic.DynamicMessage.init(self.allocator, descriptor);
            errdefer {
                nested.deinit();
                self.allocator.destroy(nested);
            }
            try self.parseMessage(registry_mod.messageDefiningFile(file, self.registry, descriptor), nested, close);
            return .{ .message = nested };
        }
        try self.expect(':');
        return try self.parseValue(file, current, field, kind);
    }

    fn defaultTextValue(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, current: *const schema.MessageDescriptor, kind: schema.FieldKind) !dynamic.Value {
        return switch (kind) {
            .scalar => |scalar| switch (scalar) {
                .double => .{ .double = 0 },
                .float => .{ .float = 0 },
                .int32 => .{ .int32 = 0 },
                .int64 => .{ .int64 = 0 },
                .uint32 => .{ .uint32 = 0 },
                .uint64 => .{ .uint64 = 0 },
                .sint32 => .{ .sint32 = 0 },
                .sint64 => .{ .sint64 = 0 },
                .fixed32 => .{ .fixed32 = 0 },
                .fixed64 => .{ .fixed64 = 0 },
                .sfixed32 => .{ .sfixed32 = 0 },
                .sfixed64 => .{ .sfixed64 = 0 },
                .bool => .{ .boolean = false },
                .string => .{ .string = try allocator.dupe(u8, "") },
                .bytes => .{ .bytes = try allocator.dupe(u8, "") },
            },
            .enumeration => |name| .{ .enumeration = defaultEnumNumber(file, registry, current, name) },
            .message => |name| blk: {
                if (registryEnumDescriptor(file, registry, current, null, name) != null) break :blk .{ .enumeration = defaultEnumNumber(file, registry, current, name) };
                const descriptor = resolveMessageDescriptorWithRegistry(file, registry, current, name) orelse return error.TypeMismatch;
                const nested = try allocator.create(dynamic.DynamicMessage);
                nested.* = dynamic.DynamicMessage.init(allocator, descriptor);
                break :blk .{ .message = nested };
            },
            .group, .map => error.TypeMismatch,
        };
    }

    fn parseValue(self: *TextParser, file: *const schema.FileDescriptor, current: *const schema.MessageDescriptor, field: ?*const schema.FieldDescriptor, kind: schema.FieldKind) !dynamic.Value {
        self.skipSpace();
        return switch (kind) {
            .scalar => |scalar| try self.parseScalar(file, field, scalar),
            .enumeration => |name| try self.parseEnum(file, current, name),
            .message => |name| if (registryEnumDescriptor(file, self.registry, current, field, name) != null) try self.parseEnum(file, current, name) else error.TypeMismatch,
            .group, .map => error.TypeMismatch,
        };
    }

    fn parseScalar(self: *TextParser, file: *const schema.FileDescriptor, field: ?*const schema.FieldDescriptor, scalar: schema.ScalarType) !dynamic.Value {
        return switch (scalar) {
            .string => blk: {
                const value = try self.readString();
                errdefer self.allocator.free(value);
                if (fieldUtf8Validation(file, field) == .verify and !std.unicode.utf8ValidateSlice(value)) return error.InvalidUtf8;
                break :blk .{ .string = value };
            },
            .bytes => .{ .bytes = try self.readString() },
            .bool => .{ .boolean = try self.readBool() },
            .double => .{ .double = try parseTextFloat(f64, try self.readAtom()) },
            .float => .{ .float = try parseTextFloat(f32, try self.readAtom()) },
            .int32 => .{ .int32 = try parseTextInt(i32, try self.readAtom()) },
            .int64 => .{ .int64 = try parseTextInt(i64, try self.readAtom()) },
            .uint32 => .{ .uint32 = try parseTextInt(u32, try self.readAtom()) },
            .uint64 => .{ .uint64 = try parseTextInt(u64, try self.readAtom()) },
            .sint32 => .{ .sint32 = try parseTextInt(i32, try self.readAtom()) },
            .sint64 => .{ .sint64 = try parseTextInt(i64, try self.readAtom()) },
            .fixed32 => .{ .fixed32 = try parseTextInt(u32, try self.readAtom()) },
            .fixed64 => .{ .fixed64 = try parseTextInt(u64, try self.readAtom()) },
            .sfixed32 => .{ .sfixed32 = try parseTextInt(i32, try self.readAtom()) },
            .sfixed64 => .{ .sfixed64 = try parseTextInt(i64, try self.readAtom()) },
        };
    }

    fn parseEnum(self: *TextParser, file: *const schema.FileDescriptor, current: *const schema.MessageDescriptor, name: []const u8) !dynamic.Value {
        const atom = try self.readAtom();
        const enumeration = registryEnumDescriptor(file, self.registry, current, null, name) orelse current.findEnumDeep(name) orelse file.findEnumDeep(name);
        if (std.fmt.parseInt(i32, atom, 10)) |number| {
            if (enumeration) |enum_desc| {
                if (enumIsClosed(file, self.registry, enum_desc) and !enumHasNumber(enum_desc, number)) return error.InvalidEnumValue;
            }
            return .{ .enumeration = number };
        } else |_| {}
        if (enumeration) |enum_desc| {
            if (enum_desc.findValue(atom)) |value| return .{ .enumeration = value.number };
        }
        return error.InvalidEnumValue;
    }

    fn readBool(self: *TextParser) !bool {
        const atom = try self.readAtom();
        if (std.mem.eql(u8, atom, "true") or std.mem.eql(u8, atom, "t") or std.mem.eql(u8, atom, "1")) return true;
        if (std.mem.eql(u8, atom, "false") or std.mem.eql(u8, atom, "f") or std.mem.eql(u8, atom, "0")) return false;
        return error.TypeMismatch;
    }

    fn readString(self: *TextParser) ![]u8 {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(self.allocator);
        var read_any = false;
        while (true) {
            self.skipSpace();
            if (self.eof() or (self.peek() != '"' and self.peek() != '\'')) {
                if (read_any) return try out.toOwnedSlice(self.allocator);
                return error.UnexpectedToken;
            }
            read_any = true;
            try self.readQuotedStringPart(&out);
        }
    }

    fn readQuotedStringPart(self: *TextParser, out: *std.ArrayList(u8)) !void {
        const quote = self.peek();
        self.index += 1;
        while (!self.eof()) {
            const c = self.input[self.index];
            self.index += 1;
            if (c == quote) return;
            if (c == '\\') {
                if (self.eof()) return error.UnexpectedEof;
                const esc = self.input[self.index];
                self.index += 1;
                switch (esc) {
                    'n' => try out.append(self.allocator, '\n'),
                    'r' => try out.append(self.allocator, '\r'),
                    't' => try out.append(self.allocator, '\t'),
                    'a' => try out.append(self.allocator, 0x07),
                    'b' => try out.append(self.allocator, 0x08),
                    'f' => try out.append(self.allocator, 0x0c),
                    'v' => try out.append(self.allocator, 0x0b),
                    '\\' => try out.append(self.allocator, '\\'),
                    '\'' => try out.append(self.allocator, '\''),
                    '"' => try out.append(self.allocator, '"'),
                    '?' => try out.append(self.allocator, '?'),
                    'x', 'X' => {
                        var value: u8 = 0;
                        var digits: usize = 0;
                        while (!self.eof() and digits < 2) : (digits += 1) {
                            const digit = hexValue(self.peek()) orelse break;
                            value = value * 16 + digit;
                            self.index += 1;
                        }
                        if (digits == 0) return error.InvalidCharacter;
                        try out.append(self.allocator, value);
                    },
                    'u', 'U' => {
                        const count: usize = if (esc == 'u') 4 else 8;
                        const codepoint = try self.readUnicodeEscape(count);
                        var buf: [4]u8 = undefined;
                        const len = std.unicode.utf8Encode(codepoint, &buf) catch return error.InvalidCharacter;
                        try out.appendSlice(self.allocator, buf[0..len]);
                    },
                    '0'...'7' => {
                        var value: u8 = esc - '0';
                        var digits: usize = 1;
                        while (!self.eof() and digits < 3 and self.peek() >= '0' and self.peek() <= '7') : (digits += 1) {
                            value = value * 8 + (self.peek() - '0');
                            self.index += 1;
                        }
                        try out.append(self.allocator, value);
                    },
                    else => try out.append(self.allocator, esc),
                }
            } else {
                if (c == '\n' or c == '\r') return error.InvalidCharacter;
                try out.append(self.allocator, c);
            }
        }
        return error.UnexpectedEof;
    }

    fn readUnicodeEscape(self: *TextParser, count: usize) !u21 {
        var value: u32 = 0;
        var i: usize = 0;
        while (i < count) : (i += 1) {
            if (self.eof()) return error.UnexpectedEof;
            const digit = hexValue(self.peek()) orelse return error.InvalidCharacter;
            value = value * 16 + digit;
            self.index += 1;
        }
        if (value > 0x10ffff or (value >= 0xd800 and value <= 0xdfff)) return error.InvalidCharacter;
        return @intCast(value);
    }

    fn readIdent(self: *TextParser) ![]const u8 {
        self.skipSpace();
        if (self.eof() or !(std.ascii.isAlphabetic(self.peek()) or self.peek() == '_')) return error.UnexpectedToken;
        const start = self.index;
        self.index += 1;
        while (!self.eof() and (std.ascii.isAlphanumeric(self.peek()) or self.peek() == '_' or self.peek() == '.')) self.index += 1;
        return self.input[start..self.index];
    }

    fn readAtom(self: *TextParser) ![]const u8 {
        self.skipSpace();
        const start = self.index;
        while (!self.eof() and !std.ascii.isWhitespace(self.peek()) and self.peek() != '}' and self.peek() != '>' and self.peek() != ']' and self.peek() != ',' and self.peek() != ';') self.index += 1;
        if (self.index == start) return error.UnexpectedToken;
        return self.input[start..self.index];
    }

    fn readUnknownNumber(self: *TextParser) !wire.FieldNumber {
        self.skipSpace();
        const start = self.index;
        var value: u64 = 0;
        while (!self.eof() and std.ascii.isDigit(self.peek())) {
            value = value * 10 + (self.peek() - '0');
            if (value == 0 or value > std.math.maxInt(wire.FieldNumber)) return error.InvalidFieldNumber;
            self.index += 1;
        }
        if (self.index == start) return error.UnexpectedToken;
        return @intCast(value);
    }

    fn peekIsDigit(self: *const TextParser) ?wire.FieldNumber {
        if (self.eof() or !std.ascii.isDigit(self.input[self.index])) return null;
        var idx = self.index;
        var value: u64 = 0;
        while (idx < self.input.len and std.ascii.isDigit(self.input[idx])) : (idx += 1) {
            value = value * 10 + (self.input[idx] - '0');
            if (value > std.math.maxInt(wire.FieldNumber)) return null;
        }
        return @intCast(value);
    }

    fn consumeSeparator(self: *TextParser) void {
        self.skipSpace();
        _ = self.consume(';') or self.consume(',');
    }

    fn expect(self: *TextParser, c: u8) !void {
        self.skipSpace();
        if (!self.consume(c)) return error.UnexpectedToken;
    }

    fn consume(self: *TextParser, c: u8) bool {
        if (!self.eof() and self.input[self.index] == c) {
            self.index += 1;
            return true;
        }
        return false;
    }

    fn skipSpace(self: *TextParser) void {
        while (!self.eof()) {
            if (std.ascii.isWhitespace(self.peek())) {
                self.index += 1;
                continue;
            }
            if (self.peek() == '#') {
                while (!self.eof() and self.peek() != '\n') self.index += 1;
                continue;
            }
            break;
        }
    }

    fn peek(self: *const TextParser) u8 {
        return self.input[self.index];
    }

    fn eof(self: *const TextParser) bool {
        return self.index >= self.input.len;
    }
};

fn resolveMessageDescriptor(file: *const schema.FileDescriptor, current: *const schema.MessageDescriptor, name: []const u8) ?*const schema.MessageDescriptor {
    const trimmed = if (std.mem.startsWith(u8, name, ".")) name[1..] else name;
    const leaf = if (std.mem.lastIndexOfScalar(u8, trimmed, '.')) |idx| trimmed[idx + 1 ..] else trimmed;
    if (std.mem.eql(u8, current.name, trimmed) or std.mem.eql(u8, current.name, leaf)) return current;
    if (current.findMessageDeep(trimmed)) |message| return message;
    return file.findMessageDeep(trimmed);
}

fn resolveMessageDescriptorWithRegistry(file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, current: *const schema.MessageDescriptor, name: []const u8) ?*const schema.MessageDescriptor {
    if (registry) |reg| {
        if (std.mem.indexOfScalar(u8, name, '.') == null) {
            if (resolveMessageDescriptor(file, current, name)) |message| return message;
        }
        var scope_buf: [512]u8 = undefined;
        const scope = messageScope(file, current, &scope_buf) orelse if (file.package.len != 0) file.package else null;
        if (reg.findMessageVisible(file, name, scope)) |message| return message;
        if (reg.findMessage(name, scope)) |message| return message;
    }
    return resolveMessageDescriptor(file, current, name);
}

fn enumIsClosed(file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, enumeration: *const schema.EnumDescriptor) bool {
    if (enumeration.features) |features| return features.enum_type == .closed;
    return registry_mod.enumDefiningFile(file, registry, enumeration).features.enum_type == .closed;
}

fn defaultEnumNumber(file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, current: *const schema.MessageDescriptor, name: []const u8) i32 {
    const enumeration = registryEnumDescriptor(file, registry, current, null, name) orelse current.findEnumDeep(name) orelse file.findEnumDeep(name) orelse return 0;
    if (enumeration.values.items.len == 0) return 0;
    return enumeration.values.items[0].number;
}

fn enumHasNumber(enumeration: *const schema.EnumDescriptor, number: i32) bool {
    for (enumeration.values.items) |value| {
        if (value.number == number) return true;
    }
    return false;
}

fn fieldUtf8Validation(file: *const schema.FileDescriptor, field: ?*const schema.FieldDescriptor) schema.FeatureSet.Utf8Validation {
    if (field) |descriptor| {
        if (descriptor.features) |features| return features.utf8_validation;
    }
    return file.features.utf8_validation;
}

fn parseTextInt(comptime T: type, atom: []const u8) !T {
    var text = atom;
    var negative = false;
    if (text.len != 0 and (text[0] == '+' or text[0] == '-')) {
        negative = text[0] == '-';
        text = text[1..];
    }
    if (text.len == 0) return error.InvalidCharacter;

    const base: u8 = if (std.mem.startsWith(u8, text, "0x") or std.mem.startsWith(u8, text, "0X")) blk: {
        text = text[2..];
        break :blk 16;
    } else if (text.len > 1 and text[0] == '0') 8 else 10;
    if (text.len == 0) return error.InvalidCharacter;

    if (negative) {
        const signed = try std.fmt.parseInt(i128, text, base);
        const value = -signed;
        if (value < std.math.minInt(T) or value > std.math.maxInt(T)) return error.Overflow;
        return @intCast(value);
    }
    const unsigned = try std.fmt.parseInt(u128, text, base);
    if (unsigned > std.math.maxInt(T)) return error.Overflow;
    return @intCast(unsigned);
}

fn parseTextFloat(comptime T: type, atom: []const u8) !T {
    var text = atom;
    var negative = false;
    if (text.len != 0 and (text[0] == '+' or text[0] == '-')) {
        negative = text[0] == '-';
        text = text[1..];
    }
    if (std.ascii.eqlIgnoreCase(text, "nan")) return std.math.nan(T);
    if (std.ascii.eqlIgnoreCase(text, "inf") or std.ascii.eqlIgnoreCase(text, "infinity")) {
        const value = std.math.inf(T);
        return if (negative) -value else value;
    }
    if (text.len >= 2 and text[0] == '0' and std.ascii.isDigit(text[1])) return error.InvalidCharacter;
    if (text.len >= 3 and text[0] == '0' and (text[1] == 'x' or text[1] == 'X')) return error.InvalidCharacter;
    var parse_atom = atom;
    if (parse_atom.len != 0 and (parse_atom[parse_atom.len - 1] == 'f' or parse_atom[parse_atom.len - 1] == 'F')) {
        parse_atom = parse_atom[0 .. parse_atom.len - 1];
        if (parse_atom.len == 0) return error.InvalidCharacter;
    }
    if (parse_atom.len != 0 and parse_atom[0] == '.') {
        var buf: [256]u8 = undefined;
        if (parse_atom.len + 1 > buf.len) return error.InvalidCharacter;
        buf[0] = '0';
        @memcpy(buf[1 .. parse_atom.len + 1], parse_atom);
        parse_atom = buf[0 .. parse_atom.len + 1];
        return parseFloatAllowOverflow(T, parse_atom);
    }
    if (parse_atom.len >= 2 and (parse_atom[0] == '+' or parse_atom[0] == '-') and parse_atom[1] == '.') {
        var buf: [256]u8 = undefined;
        if (parse_atom.len + 1 > buf.len) return error.InvalidCharacter;
        buf[0] = parse_atom[0];
        buf[1] = '0';
        @memcpy(buf[2 .. parse_atom.len + 1], parse_atom[1..]);
        parse_atom = buf[0 .. parse_atom.len + 1];
        return parseFloatAllowOverflow(T, parse_atom);
    }
    return parseFloatAllowOverflow(T, parse_atom);
}

fn parseFloatAllowOverflow(comptime T: type, atom: []const u8) !T {
    return try std.fmt.parseFloat(T, atom);
}

fn hexValue(c: u8) ?u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => null,
    };
}

test "text format parses dynamic messages" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message Child { string label = 1; }
        \\message Bag { int32 id = 1; repeated string tags = 2; map<string, int32> counts = 3; Child child = 4; Kind kind = 5; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("Bag").?;
    var msg = try parseAlloc(allocator, &file, desc,
        \\id: 7
        \\tags: "a"
        \\counts { key: "red" value: 3 }
        \\child { label: "kid" }
        \\kind: ADMIN
    );
    defer msg.deinit();
    try std.testing.expectEqual(@as(i32, 7), msg.get("id").?.values.items[0].int32);
    try std.testing.expectEqualSlices(u8, "a", msg.get("tags").?.values.items[0].string);
    try std.testing.expectEqual(@as(i32, 3), msg.get("counts").?.values.items[0].map_entry.value.int32);
    try std.testing.expectEqualSlices(u8, "kid", msg.get("child").?.values.items[0].message.get("label").?.values.items[0].string);
    try std.testing.expectEqual(@as(i32, 1), msg.get("kind").?.values.items[0].enumeration);
}

test "text format fills default map entry key and value" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\enum Kind { FIRST = 7; SECOND = 8; }
        \\message Child { optional int32 id = 1; }
        \\message M {
        \\  map<string, int32> missing_value = 1;
        \\  map<int32, string> missing_key_value = 2;
        \\  map<bool, Kind> enum_value = 3;
        \\  map<string, Child> message_value = 4;
        \\}
    );
    defer file.deinit();
    const desc = file.findMessage("M").?;

    var msg = try parseAlloc(allocator, &file, desc,
        \\missing_value { key: "present" }
        \\missing_key_value {}
        \\enum_value { key: true }
        \\message_value { key: "child" }
    );
    defer msg.deinit();

    const missing_value = msg.get("missing_value").?.values.items[0].map_entry;
    try std.testing.expectEqualStrings("present", missing_value.key.string);
    try std.testing.expectEqual(@as(i32, 0), missing_value.value.int32);

    const missing_key_value = msg.get("missing_key_value").?.values.items[0].map_entry;
    try std.testing.expectEqual(@as(i32, 0), missing_key_value.key.int32);
    try std.testing.expectEqualStrings("", missing_key_value.value.string);

    const enum_value = msg.get("enum_value").?.values.items[0].map_entry;
    try std.testing.expect(enum_value.key.boolean);
    try std.testing.expectEqual(@as(i32, 7), enum_value.value.enumeration);

    const message_value = msg.get("message_value").?.values.items[0].map_entry;
    try std.testing.expectEqualStrings("child", message_value.key.string);
    try std.testing.expectEqual(@as(usize, 0), message_value.value.message.fields.items.len);
}

test "text format parses protobuf special float values" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Floats {
        \\  optional double pos = 1;
        \\  optional double neg = 2;
        \\  optional float quiet = 3;
        \\  optional float negative_quiet = 4;
        \\}
    );
    defer file.deinit();
    const desc = file.findMessage("Floats").?;
    var msg = try parseAlloc(allocator, &file, desc,
        \\pos: +Infinity
        \\neg: -inf
        \\quiet: nan
        \\negative_quiet: -nan
    );
    defer msg.deinit();

    try std.testing.expect(std.math.isPositiveInf(msg.get("pos").?.values.items[0].double));
    try std.testing.expect(std.math.isNegativeInf(msg.get("neg").?.values.items[0].double));
    try std.testing.expect(std.math.isNan(msg.get("quiet").?.values.items[0].float));
    try std.testing.expect(std.math.isNan(msg.get("negative_quiet").?.values.items[0].float));
}

test "text format honors closed enum feature for numeric values" {
    const allocator = std.testing.allocator;
    {
        var file = try @import("parser.zig").Parser.parse(allocator,
            \\edition = "2023";
            \\option features.enum_type = CLOSED;
            \\enum Kind { option features.enum_type = OPEN; A = 0; B = 1; }
            \\message M { Kind kind = 1; repeated Kind many = 2; }
        );
        defer file.deinit();
        const desc = file.findMessage("M").?;
        var msg = try parseAlloc(allocator, &file, desc, "kind: 123 many: 123");
        defer msg.deinit();
        try std.testing.expectEqual(@as(i32, 123), msg.get("kind").?.values.items[0].enumeration);
        try std.testing.expectEqual(@as(i32, 123), msg.get("many").?.values.items[0].enumeration);
    }
    {
        var file = try @import("parser.zig").Parser.parse(allocator,
            \\edition = "2023";
            \\option features.enum_type = OPEN;
            \\enum Kind { option features.enum_type = CLOSED; A = 0; B = 1; }
            \\message M { Kind kind = 1; map<string, Kind> keyed = 2; }
        );
        defer file.deinit();
        const desc = file.findMessage("M").?;
        try std.testing.expectError(error.InvalidEnumValue, parseAlloc(allocator, &file, desc, "kind: 123"));
        try std.testing.expectError(error.InvalidEnumValue, parseAlloc(allocator, &file, desc, "keyed { key: \"bad\" value: 123 }"));
    }
}

test "text format validates string utf8 according to syntax and features" {
    const allocator = std.testing.allocator;
    {
        var file = try @import("parser.zig").Parser.parse(allocator,
            \\syntax = "proto3";
            \\message M { string name = 1; }
        );
        defer file.deinit();
        const desc = file.findMessage("M").?;
        try std.testing.expectError(error.InvalidUtf8, parseAlloc(allocator, &file, desc, "name: '\xc0'"));
    }
    {
        var file = try @import("parser.zig").Parser.parse(allocator,
            \\syntax = "proto2";
            \\message M { optional string name = 1; }
        );
        defer file.deinit();
        const desc = file.findMessage("M").?;
        var msg = try parseAlloc(allocator, &file, desc, "name: '\xc0'");
        defer msg.deinit();
        try std.testing.expectEqualSlices(u8, &.{0xc0}, msg.get("name").?.values.items[0].string);
    }
    {
        var file = try @import("parser.zig").Parser.parse(allocator,
            \\edition = "2023";
            \\message M {
            \\  string relaxed = 1 [features.utf8_validation = NONE];
            \\  string strict = 2;
            \\  map<string, string> labels = 3 [features.utf8_validation = NONE];
            \\}
        );
        defer file.deinit();
        const desc = file.findMessage("M").?;
        var relaxed = try parseAlloc(allocator, &file, desc, "relaxed: '\xc0' labels { key: '\xc0' value: '\xc0' }");
        defer relaxed.deinit();
        try std.testing.expectEqualSlices(u8, &.{0xc0}, relaxed.get("relaxed").?.values.items[0].string);
        try std.testing.expectEqualSlices(u8, &.{0xc0}, relaxed.get("labels").?.values.items[0].map_entry.key.string);
        try std.testing.expectEqualSlices(u8, &.{0xc0}, relaxed.get("labels").?.values.items[0].map_entry.value.string);
        try std.testing.expectError(error.InvalidUtf8, parseAlloc(allocator, &file, desc, "strict: '\xc0'"));
    }
}

test "text format formatting validates string utf8 according to syntax and features" {
    const allocator = std.testing.allocator;
    {
        var file = try @import("parser.zig").Parser.parse(allocator,
            \\syntax = "proto3";
            \\message M { string name = 1; repeated string tags = 2; map<string, string> labels = 3; }
        );
        defer file.deinit();
        const desc = file.findMessage("M").?;
        var msg = dynamic.DynamicMessage.init(allocator, desc);
        defer msg.deinit();
        try msg.add(desc.findField("name").?, .{ .string = try allocator.dupe(u8, &.{0xc0}) });
        try std.testing.expectError(error.InvalidUtf8, formatAlloc(allocator, &file, &msg, .{}));

        var repeated = dynamic.DynamicMessage.init(allocator, desc);
        defer repeated.deinit();
        try repeated.add(desc.findField("tags").?, .{ .string = try allocator.dupe(u8, &.{0xc0}) });
        try std.testing.expectError(error.InvalidUtf8, formatAlloc(allocator, &file, &repeated, .{}));

        var keyed = dynamic.DynamicMessage.init(allocator, desc);
        defer keyed.deinit();
        const entry = try allocator.create(dynamic.MapEntry);
        entry.* = .{ .key = .{ .string = try allocator.dupe(u8, &.{0xc0}) }, .value = .{ .string = try allocator.dupe(u8, "ok") } };
        try keyed.add(desc.findField("labels").?, .{ .map_entry = entry });
        try std.testing.expectError(error.InvalidUtf8, formatAlloc(allocator, &file, &keyed, .{}));
    }
    {
        var file = try @import("parser.zig").Parser.parse(allocator,
            \\syntax = "proto2";
            \\message M { optional string name = 1; }
        );
        defer file.deinit();
        const desc = file.findMessage("M").?;
        var msg = dynamic.DynamicMessage.init(allocator, desc);
        defer msg.deinit();
        try msg.add(desc.findField("name").?, .{ .string = try allocator.dupe(u8, &.{0xc0}) });
        const rendered = try formatAlloc(allocator, &file, &msg, .{});
        defer allocator.free(rendered);
        try std.testing.expectEqualStrings("name: \"\\300\"\n", rendered);
    }
}

test "text parseInitialized validates required fields recursively" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Child { required int32 id = 1; }
        \\message Parent { required Child child = 1; }
    );
    defer file.deinit();
    const parent_desc = file.findMessage("Parent").?;

    try std.testing.expectError(error.MissingRequiredField, parseInitializedAlloc(allocator, &file, parent_desc, ""));
    try std.testing.expectError(error.MissingRequiredField, parseInitializedAlloc(allocator, &file, parent_desc, "child {}"));

    var parsed = try parseInitializedAlloc(allocator, &file, parent_desc, "child { id: 7 }");
    defer parsed.deinit();
    try std.testing.expectEqual(@as(i32, 7), parsed.get("child").?.values.items[0].message.get("id").?.values.items[0].int32);

    var common = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package common;
        \\message Child { required int32 id = 1; }
    );
    defer common.deinit();
    var app = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package app;
        \\message Parent { required common.Child child = 1; }
    );
    defer app.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);
    const imported_parent = app.findMessage("Parent").?;

    try std.testing.expectError(error.MissingRequiredField, parseInitializedAllocWithRegistry(allocator, &app, &registry, imported_parent, "child {}"));
    var imported = try parseInitializedAllocWithRegistry(allocator, &app, &registry, imported_parent, "child { id: 9 }");
    defer imported.deinit();
    try std.testing.expectEqual(@as(i32, 9), imported.get("child").?.values.items[0].message.get("id").?.values.items[0].int32);

    var ext_file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host { extensions 100 to max; }
        \\message Ext { required int32 id = 1; }
        \\extend Host {
        \\  optional Ext ext = 100;
        \\  repeated Ext exts = 101;
        \\}
    );
    defer ext_file.deinit();
    var ext_registry = registry_mod.Registry.init(allocator);
    defer ext_registry.deinit();
    try ext_registry.addFile(&ext_file);
    const host_desc = ext_file.findMessage("Host").?;
    try std.testing.expectError(error.MissingRequiredField, parseInitializedAllocWithRegistry(allocator, &ext_file, &ext_registry, host_desc, "[demo.ext] {}"));
    var ext_parsed = try parseInitializedAllocWithRegistry(allocator, &ext_file, &ext_registry, host_desc, "[demo.ext] { id: 11 }");
    defer ext_parsed.deinit();
    try std.testing.expectEqual(@as(i32, 11), ext_parsed.get("ext").?.values.items[0].message.get("id").?.values.items[0].int32);
    try std.testing.expectError(error.MissingRequiredField, parseInitializedAllocWithRegistry(allocator, &ext_file, &ext_registry, host_desc, "[demo.exts] { id: 1 } [demo.exts] {}"));
    var repeated_ext_parsed = try parseInitializedAllocWithRegistry(allocator, &ext_file, &ext_registry, host_desc, "[demo.exts] { id: 1 } [demo.exts] { id: 2 }");
    defer repeated_ext_parsed.deinit();
    try std.testing.expectEqual(@as(usize, 2), repeated_ext_parsed.get("exts").?.values.items.len);

    var messageset_file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.ms;
        \\message Host { option message_set_wire_format = true; extensions 4 to max; }
        \\message Ext { required int32 id = 1; }
        \\extend Host { optional Ext ext = 100; }
    );
    defer messageset_file.deinit();
    var messageset_registry = registry_mod.Registry.init(allocator);
    defer messageset_registry.deinit();
    try messageset_registry.addFile(&messageset_file);
    const messageset_host = messageset_file.findMessage("Host").?;
    try std.testing.expectError(error.MissingRequiredField, parseInitializedAllocWithRegistry(allocator, &messageset_file, &messageset_registry, messageset_host, "[demo.ms.ext] {}"));
    var messageset_parsed = try parseInitializedAllocWithRegistry(allocator, &messageset_file, &messageset_registry, messageset_host, "[demo.ms.ext] { id: 12 }");
    defer messageset_parsed.deinit();
    try std.testing.expectEqual(@as(i32, 12), messageset_parsed.get("ext").?.values.items[0].message.get("id").?.values.items[0].int32);
}

test "text parser merges duplicate singular message and group fields" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Grand { optional int32 a = 1; optional int32 b = 2; }
        \\message Child {
        \\  optional int32 id = 1;
        \\  optional string name = 2;
        \\  repeated int32 nums = 3;
        \\  optional Grand grand = 4;
        \\  optional group Legacy = 5 { optional int32 a = 6; optional int32 b = 7; }
        \\}
        \\message Parent {
        \\  optional Child child = 1;
        \\  optional group Box = 2 { optional int32 a = 3; optional int32 b = 4; }
        \\  repeated Child children = 5;
        \\  oneof pick { Child picked = 6; }
        \\}
    );
    defer file.deinit();
    const parent_desc = file.findMessage("Parent").?;

    var parsed = try parseAlloc(allocator, &file, parent_desc,
        \\child { id: 1 nums: 10 grand { a: 100 } Legacy { a: 1000 } }
        \\child { name: "two" nums: 20 grand { b: 200 } Legacy { b: 2000 } }
        \\Box { a: 11 }
        \\Box { b: 22 }
        \\children { id: 1 }
        \\children { name: "two" }
        \\picked { id: 1 }
        \\picked { name: "two" nums: 20 }
    );
    defer parsed.deinit();

    const merged_child = parsed.get("child").?.values.items[0].message;
    try std.testing.expectEqual(@as(i32, 1), merged_child.get("id").?.values.items[0].int32);
    try std.testing.expectEqualSlices(u8, "two", merged_child.get("name").?.values.items[0].string);
    try std.testing.expectEqual(@as(usize, 2), merged_child.get("nums").?.values.items.len);
    try std.testing.expectEqual(@as(i32, 10), merged_child.get("nums").?.values.items[0].int32);
    try std.testing.expectEqual(@as(i32, 20), merged_child.get("nums").?.values.items[1].int32);
    const merged_grand = merged_child.get("grand").?.values.items[0].message;
    try std.testing.expectEqual(@as(i32, 100), merged_grand.get("a").?.values.items[0].int32);
    try std.testing.expectEqual(@as(i32, 200), merged_grand.get("b").?.values.items[0].int32);
    const merged_legacy = merged_child.get("legacy").?.values.items[0].group;
    try std.testing.expectEqual(@as(i32, 1000), merged_legacy.get("a").?.values.items[0].int32);
    try std.testing.expectEqual(@as(i32, 2000), merged_legacy.get("b").?.values.items[0].int32);

    const merged_box = parsed.get("box").?.values.items[0].group;
    try std.testing.expectEqual(@as(i32, 11), merged_box.get("a").?.values.items[0].int32);
    try std.testing.expectEqual(@as(i32, 22), merged_box.get("b").?.values.items[0].int32);

    try std.testing.expectEqual(@as(usize, 2), parsed.get("children").?.values.items.len);
    try std.testing.expectEqual(@as(i32, 1), parsed.get("children").?.values.items[0].message.get("id").?.values.items[0].int32);
    try std.testing.expectEqualSlices(u8, "two", parsed.get("children").?.values.items[1].message.get("name").?.values.items[0].string);

    const picked = parsed.get("picked").?.values.items[0].message;
    try std.testing.expectEqual(@as(i32, 1), picked.get("id").?.values.items[0].int32);
    try std.testing.expectEqualSlices(u8, "two", picked.get("name").?.values.items[0].string);
    try std.testing.expectEqual(@as(usize, 1), picked.get("nums").?.values.items.len);
    try std.testing.expectEqual(@as(i32, 20), picked.get("nums").?.values.items[0].int32);
}

test "text format formats and parses proto2 extensions" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto2";
        \\package demo;
        \\message Host {
        \\  optional int32 id = 1;
        \\  extensions 100 to max;
        \\}
        \\message Note { optional string text = 1; }
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\extend Host {
        \\  optional string tag = 100;
        \\  repeated int32 nums = 101;
        \\  optional Note note = 102;
        \\  optional Kind role = 103;
        \\}
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);
    const host = file.findMessage("Host").?;
    const note_desc = file.findMessage("Note").?;
    const tag = registry.findExtension("demo.Host", 100).?;
    const nums = registry.findExtension("demo.Host", 101).?;
    const note = registry.findExtension("demo.Host", 102).?;
    const role = registry.findExtension("demo.Host", 103).?;

    var msg = dynamic.DynamicMessage.init(allocator, host);
    defer msg.deinit();
    try msg.add(host.findField("id").?, .{ .int32 = 7 });
    try msg.add(tag, .{ .string = try allocator.dupe(u8, "hello") });
    try msg.add(nums, .{ .int32 = 1 });
    try msg.add(nums, .{ .int32 = 2 });
    const nested = try allocator.create(dynamic.DynamicMessage);
    nested.* = dynamic.DynamicMessage.init(allocator, note_desc);
    try nested.add(note_desc.findField("text").?, .{ .string = try allocator.dupe(u8, "body") });
    try msg.add(note, .{ .message = nested });
    try msg.add(role, .{ .enumeration = 1 });

    const text = try formatAlloc(allocator, &file, &msg, .{ .print_unknown_fields = true });
    defer allocator.free(text);
    try std.testing.expectEqualSlices(u8,
        \\id: 7
        \\[demo.tag]: "hello"
        \\[demo.nums]: 1
        \\[demo.nums]: 2
        \\[demo.note] {
        \\  text: "body"
        \\}
        \\[demo.role]: ADMIN
        \\
    , text);

    var parsed = try parseAllocWithRegistry(allocator, &file, &registry, host,
        \\id: 8
        \\[demo.tag]: "parsed"
        \\[demo.nums]: 3
        \\[demo.nums]: 4
        \\[demo.note] < text: "parsed body" >
        \\[demo.role]: ADMIN
    );
    defer parsed.deinit();
    try std.testing.expectEqual(@as(i32, 8), parsed.get("id").?.values.items[0].int32);
    try std.testing.expectEqualSlices(u8, "parsed", parsed.get("tag").?.values.items[0].string);
    try std.testing.expectEqual(@as(i32, 3), parsed.get("nums").?.values.items[0].int32);
    try std.testing.expectEqual(@as(i32, 4), parsed.get("nums").?.values.items[1].int32);
    try std.testing.expectEqualSlices(u8, "parsed body", parsed.get("note").?.values.items[0].message.get("text").?.values.items[0].string);
    try std.testing.expectEqual(@as(i32, 1), parsed.get("role").?.values.items[0].enumeration);
}

test "text format formats and parses proto2 group extensions" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto2";
        \\package demo;
        \\message Host {
        \\  optional int32 id = 1;
        \\  extensions 100 to max;
        \\}
        \\extend Host {
        \\  optional group Box = 100 {
        \\    optional int32 a = 101;
        \\    optional string label = 102;
        \\  }
        \\  repeated group Item = 103 {
        \\    optional int32 a = 104;
        \\  }
        \\}
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);
    const host = file.findMessage("Host").?;
    const box_desc = file.findMessage("Box").?;
    const item_desc = file.findMessage("Item").?;
    const box = registry.findExtension("demo.Host", 100).?;
    const item = registry.findExtension("demo.Host", 103).?;

    var msg = dynamic.DynamicMessage.init(allocator, host);
    defer msg.deinit();
    try msg.add(host.findField("id").?, .{ .int32 = 7 });
    const box_value = try allocator.create(dynamic.DynamicMessage);
    box_value.* = dynamic.DynamicMessage.init(allocator, box_desc);
    try box_value.add(box_desc.findField("a").?, .{ .int32 = 11 });
    try box_value.add(box_desc.findField("label").?, .{ .string = try allocator.dupe(u8, "box") });
    try msg.add(box, .{ .group = box_value });
    const first_item = try allocator.create(dynamic.DynamicMessage);
    first_item.* = dynamic.DynamicMessage.init(allocator, item_desc);
    try first_item.add(item_desc.findField("a").?, .{ .int32 = 1 });
    try msg.add(item, .{ .group = first_item });
    const second_item = try allocator.create(dynamic.DynamicMessage);
    second_item.* = dynamic.DynamicMessage.init(allocator, item_desc);
    try second_item.add(item_desc.findField("a").?, .{ .int32 = 2 });
    try msg.add(item, .{ .group = second_item });

    const rendered = try formatAllocWithRegistry(allocator, &file, &registry, &msg, .{});
    defer allocator.free(rendered);
    try std.testing.expectEqualSlices(u8,
        \\id: 7
        \\[demo.box] {
        \\  a: 11
        \\  label: "box"
        \\}
        \\[demo.item] {
        \\  a: 1
        \\}
        \\[demo.item] {
        \\  a: 2
        \\}
        \\
    , rendered);

    var parsed = try parseAllocWithRegistry(allocator, &file, &registry, host,
        \\id: 8
        \\[demo.box] < a: 21 label: "parsed" >
        \\[demo.item] { a: 3 }
        \\[demo.item] < a: 4 >
    );
    defer parsed.deinit();
    try std.testing.expectEqual(@as(i32, 8), parsed.get("id").?.values.items[0].int32);
    const parsed_box = parsed.getByNumber(box.number).?.values.items[0].group;
    try std.testing.expectEqual(@as(i32, 21), parsed_box.get("a").?.values.items[0].int32);
    try std.testing.expectEqualSlices(u8, "parsed", parsed_box.get("label").?.values.items[0].string);
    const parsed_items = parsed.getByNumber(item.number).?.values.items;
    try std.testing.expectEqual(@as(usize, 2), parsed_items.len);
    try std.testing.expectEqual(@as(i32, 3), parsed_items[0].group.get("a").?.values.items[0].int32);
    try std.testing.expectEqual(@as(i32, 4), parsed_items[1].group.get("a").?.values.items[0].int32);

    var leaf = try parseAllocWithRegistry(allocator, &file, &registry, host, "[box] { a: 31 }");
    defer leaf.deinit();
    try std.testing.expectEqual(@as(i32, 31), leaf.getByNumber(box.number).?.values.items[0].group.get("a").?.values.items[0].int32);
}

test "text format formats and parses MessageSet extensions" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto2";
        \\package demo;
        \\message Host { option message_set_wire_format = true; extensions 4 to max; }
        \\message Note { optional string text = 1; }
        \\extend Host { optional Note note = 100; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);
    const host = file.findMessage("Host").?;
    const note_desc = file.findMessage("Note").?;
    const note = registry.findExtension("demo.Host", 100).?;

    var msg = dynamic.DynamicMessage.init(allocator, host);
    defer msg.deinit();
    const nested = try allocator.create(dynamic.DynamicMessage);
    nested.* = dynamic.DynamicMessage.init(allocator, note_desc);
    try nested.add(note_desc.findField("text").?, .{ .string = try allocator.dupe(u8, "body") });
    try msg.add(note, .{ .message = nested });

    const text = try formatAlloc(allocator, &file, &msg, .{ .print_unknown_fields = true });
    defer allocator.free(text);
    try std.testing.expectEqualSlices(u8,
        \\[demo.note] {
        \\  text: "body"
        \\}
        \\
    , text);

    var parsed = try parseAllocWithRegistry(allocator, &file, &registry, host,
        \\[demo.note] { text: "parsed" }
    );
    defer parsed.deinit();
    try std.testing.expectEqualSlices(u8, "parsed", parsed.get("note").?.values.items[0].message.get("text").?.values.items[0].string);
    const encoded = try parsed.encoded(&file);
    defer allocator.free(encoded);
    try std.testing.expectEqual(@as(u8, 0x0b), encoded[0]); // MessageSet item start group.
}

test "text format formats and parses scoped proto2 extensions" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto2";
        \\package demo;
        \\message Host { extensions 100 to 200; }
        \\message Scope { extend Host { optional string tag = 100; } }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);
    const host = file.findMessage("Host").?;
    const tag = registry.findExtensionByName("demo.Host", "demo.Scope.tag").?;

    var msg = dynamic.DynamicMessage.init(allocator, host);
    defer msg.deinit();
    try msg.add(tag, .{ .string = try allocator.dupe(u8, "scoped") });

    const rendered = try formatAllocWithRegistry(allocator, &file, &registry, &msg, .{});
    defer allocator.free(rendered);
    try std.testing.expectEqualSlices(u8, "[demo.Scope.tag]: \"scoped\"\n", rendered);

    var parsed = try parseAllocWithRegistry(allocator, &file, &registry, host, "[demo.Scope.tag]: \"parsed\"");
    defer parsed.deinit();
    try std.testing.expectEqualSlices(u8, "parsed", parsed.getByNumber(tag.number).?.values.items[0].string);
}

test "text registry extension lookup distinguishes same leaf message names" {
    const allocator = std.testing.allocator;
    var a_file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package a;
        \\message Host { extensions 100 to max; }
        \\extend Host { optional string note = 100; }
    );
    defer a_file.deinit();
    a_file.name = "a.proto";
    var b_file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package b;
        \\message Host { optional int32 id = 1; }
    );
    defer b_file.deinit();
    b_file.name = "b.proto";
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&a_file);
    try registry.addFile(&b_file);

    try std.testing.expectError(error.UnknownField, parseAllocWithRegistry(allocator, &b_file, &registry, b_file.findMessage("Host").?, "[a.note]: \"wrong-host\""));

    var a_msg = try parseAllocWithRegistry(allocator, &a_file, &registry, a_file.findMessage("Host").?, "[a.note]: \"right-host\"");
    defer a_msg.deinit();
    try std.testing.expectEqualStrings("right-host", a_msg.get("note").?.values.items[0].string);
}

test "text format formats and parses numeric unknown fields" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto2";
        \\message M { optional int32 id = 1; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("M").?;

    var msg = dynamic.DynamicMessage.init(allocator, desc);
    defer msg.deinit();
    try msg.add(desc.findField("id").?, .{ .int32 = 7 });
    var raw_varint = wire.Writer.init(allocator);
    defer raw_varint.deinit();
    try raw_varint.writeUInt64(100, 123);
    try msg.unknown_fields.append(allocator, .{ .number = 100, .wire_type = .varint, .data = try allocator.dupe(u8, raw_varint.slice()) });
    var raw_bytes = wire.Writer.init(allocator);
    defer raw_bytes.deinit();
    try raw_bytes.writeBytes(101, "blob");
    try msg.unknown_fields.append(allocator, .{ .number = 101, .wire_type = .length_delimited, .data = try allocator.dupe(u8, raw_bytes.slice()) });
    var raw_message = wire.Writer.init(allocator);
    defer raw_message.deinit();
    try raw_message.writeMessage(102, raw_varint.slice());
    try msg.unknown_fields.append(allocator, .{ .number = 102, .wire_type = .length_delimited, .data = try allocator.dupe(u8, raw_message.slice()) });

    const text = try formatAlloc(allocator, &file, &msg, .{ .print_unknown_fields = true });
    defer allocator.free(text);
    try std.testing.expectEqualSlices(u8,
        \\id: 7
        \\100: 123
        \\101: "blob"
        \\102 {
        \\  100: 123
        \\}
        \\
    , text);

    var parsed = try parseAlloc(allocator, &file, desc,
        \\id: 8
        \\100: 123
        \\101: "blob"
    );
    defer parsed.deinit();
    try std.testing.expectEqual(@as(i32, 8), parsed.get("id").?.values.items[0].int32);
    try std.testing.expectEqual(@as(usize, 2), parsed.unknownCount());
    try std.testing.expectEqualSlices(u8, raw_varint.slice(), parsed.unknown_fields.items[0].data);
    try std.testing.expectEqualSlices(u8, raw_bytes.slice(), parsed.unknown_fields.items[1].data);
}

test "text format parses numeric unknown groups" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto2";
        \\message M {}
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("M").?;

    var raw_group = wire.Writer.init(allocator);
    defer raw_group.deinit();
    try raw_group.writeTag(100, .start_group);
    try raw_group.writeUInt64(101, 1);
    try raw_group.writeBytes(102, "x");
    try raw_group.writeTag(100, .end_group);

    var parsed = try parseAlloc(allocator, &file, desc,
        \\100 {
        \\  101: 1
        \\  102: "x"
        \\}
    );
    defer parsed.deinit();
    try std.testing.expectEqual(@as(usize, 1), parsed.unknownCount());
    try std.testing.expectEqual(wire.WireType.start_group, parsed.unknown_fields.items[0].wire_type);
    try std.testing.expectEqualSlices(u8, raw_group.slice(), parsed.unknown_fields.items[0].data);

    const text = try formatAlloc(allocator, &file, &parsed, .{ .print_unknown_fields = true });
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "100 {\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "101: 1\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "102: \"x\"\n") != null);
}

test "text format parser accepts comma and semicolon separators" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\message M { int32 a = 1; int32 b = 2; map<string, int32> counts = 3; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("M").?;
    var msg = try parseAlloc(allocator, &file, desc, "a: 1; b: 2, counts { key: \"x\"; value: 3; },");
    defer msg.deinit();
    try std.testing.expectEqual(@as(i32, 1), msg.get("a").?.values.items[0].int32);
    try std.testing.expectEqual(@as(i32, 2), msg.get("b").?.values.items[0].int32);
    try std.testing.expectEqual(@as(i32, 3), msg.get("counts").?.values.items[0].map_entry.value.int32);
}

test "text format parser accepts repeated list and float literal variants" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\message M { repeated int32 nums = 1; repeated string names = 2; float f = 3; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("M").?;

    var msg = try parseAlloc(allocator, &file, desc, "nums: [1,2] names: [\"a\", \"b\"] f: -.123e2F");
    defer msg.deinit();
    try std.testing.expectEqual(@as(usize, 2), msg.get("nums").?.values.items.len);
    try std.testing.expectEqual(@as(i32, 1), msg.get("nums").?.values.items[0].int32);
    try std.testing.expectEqual(@as(i32, 2), msg.get("nums").?.values.items[1].int32);
    try std.testing.expectEqualSlices(u8, "a", msg.get("names").?.values.items[0].string);
    try std.testing.expectEqualSlices(u8, "b", msg.get("names").?.values.items[1].string);
    try std.testing.expectEqual(@as(f32, -12.3), msg.get("f").?.values.items[0].float);

    try std.testing.expectError(error.UnexpectedToken, parseAlloc(allocator, &file, desc, "nums: [1,]"));
    try std.testing.expectError(error.UnexpectedToken, parseAlloc(allocator, &file, desc, "nums: [1,,2]"));
    try std.testing.expectError(error.UnexpectedToken, parseAlloc(allocator, &file, desc, "nums: [1;2]"));
    try std.testing.expectError(error.InvalidCharacter, parseAlloc(allocator, &file, desc, "f: 0x1"));
    try std.testing.expectError(error.InvalidCharacter, parseAlloc(allocator, &file, desc, "f: 012"));
}

test "text format parser ignores reserved field names" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\message M {
        \\  reserved "reserved_field";
        \\  int32 id = 1;
        \\}
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("M").?;

    var msg = try parseAlloc(allocator, &file, desc,
        \\reserved_field: true
        \\reserved_field: -123
        \\reserved_field: 0.123
        \\reserved_field: ENUM_VALUE
        \\reserved_field: "hello"
        \\reserved_field: { a: 123 }
        \\reserved_field: < a: 123 >
        \\reserved_field: [-123, 456]
        \\reserved_field: [0.123, 1e-10]
        \\reserved_field: ["hello", "world"]
        \\id: 7
    );
    defer msg.deinit();
    try std.testing.expectEqual(@as(i32, 7), msg.get("id").?.values.items[0].int32);
}

test "text format parses and formats expanded Any fields" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\package demo;
        \\message Payload { int32 id = 1; }
        \\message Any { string type_url = 1; bytes value = 2; }
        \\message Holder { .google.protobuf.Any any = 1; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const holder_desc = file.findMessage("Holder").?;
    const payload_desc = file.findMessage("Payload").?;

    var parsed = try parseAlloc(allocator, &file, holder_desc,
        \\any {
        \\  [type.googleapis.com/demo.Payload] { id: 123 }
        \\}
    );
    defer parsed.deinit();
    const any = parsed.get("any").?.values.items[0].message;
    try std.testing.expectEqualSlices(u8, "type.googleapis.com/demo.Payload", any.get("type_url").?.values.items[0].string);
    var payload = dynamic.DynamicMessage.init(allocator, payload_desc);
    defer payload.deinit();
    try payload.decode(&file, any.get("value").?.values.items[0].bytes);
    try std.testing.expectEqual(@as(i32, 123), payload.get("id").?.values.items[0].int32);

    const rendered = try formatAlloc(allocator, &file, &parsed, .{});
    defer allocator.free(rendered);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "[type.googleapis.com/demo.Payload]") != null);

    var whitespace = try parseAlloc(
        allocator,
        &file,
        holder_desc,
        "any { [ type.goog # c\nleapis.com/demo.Pay\tload ] { id: 7 } }",
    );
    defer whitespace.deinit();
    try std.testing.expectEqualSlices(u8, "type.googleapis.com/demo.Payload", whitespace.get("any").?.values.items[0].message.get("type_url").?.values.items[0].string);
    try std.testing.expectError(error.InvalidCharacter, parseAlloc(allocator, &file, holder_desc, "any { [bad/%ZZ/demo.Payload] { id: 1 } }"));
}

test "text format parser decodes unicode escapes and rejects invalid string literals" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\message M { string s = 1; bytes b = 2; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("M").?;

    var msg = try parseAlloc(allocator, &file, desc, "s: '\\u1234\\U00010437' b: '\\u1234'");
    defer msg.deinit();
    try std.testing.expectEqualSlices(u8, "ሴ𐐷", msg.get("s").?.values.items[0].string);
    try std.testing.expectEqualSlices(u8, "ሴ", msg.get("b").?.values.items[0].bytes);

    try std.testing.expectError(error.InvalidCharacter, parseAlloc(allocator, &file, desc, "s: 'first\nsecond'"));
    try std.testing.expectError(error.InvalidCharacter, parseAlloc(allocator, &file, desc, "s: '\\U00110000'"));
    try std.testing.expectError(error.InvalidCharacter, parseAlloc(allocator, &file, desc, "s: '\\ud800'"));
    try std.testing.expectError(error.InvalidCharacter, parseAlloc(allocator, &file, desc, "s: '\\ud801\\udc37'"));
}

test "text format quoted string escape scanner distinguishes fast and escaped paths" {
    try std.testing.expect(!textStringNeedsEscape("plain ascii"));
    try std.testing.expect(textStringNeedsEscape("quote\""));
    try std.testing.expect(textStringNeedsEscape("slash\\"));
    try std.testing.expect(textStringNeedsEscape("line\n"));
    try std.testing.expect(textStringNeedsEscape("non-ascii 世界"));
}

test "text format parser accepts angle bracket message and map delimiters" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\message Child { string label = 1; }
        \\message M { Child child = 1; map<string, int32> counts = 2; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("M").?;
    var msg = try parseAlloc(allocator, &file, desc,
        \\child < label: "kid" >
        \\counts < key: "x" value: 3 >
    );
    defer msg.deinit();
    try std.testing.expectEqualSlices(u8, "kid", msg.get("child").?.values.items[0].message.get("label").?.values.items[0].string);
    try std.testing.expectEqual(@as(i32, 3), msg.get("counts").?.values.items[0].map_entry.value.int32);
}

test "text format parser accepts colon before message and map aggregates" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\message Child { string label = 1; }
        \\message M { Child child = 1; map<string, int32> counts = 2; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("M").?;
    var msg = try parseAlloc(allocator, &file, desc,
        \\child: { label: "kid" }
        \\counts: < key: "x" value: 3 >
    );
    defer msg.deinit();
    try std.testing.expectEqualSlices(u8, "kid", msg.get("child").?.values.items[0].message.get("label").?.values.items[0].string);
    try std.testing.expectEqual(@as(i32, 3), msg.get("counts").?.values.items[0].map_entry.value.int32);
}

test "text format parser skips hash comments" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\message M { int32 a = 1; string b = 2; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("M").?;
    var msg = try parseAlloc(allocator, &file, desc,
        \\# before
        \\a: 1 # inline
        \\b: "x"
    );
    defer msg.deinit();
    try std.testing.expectEqual(@as(i32, 1), msg.get("a").?.values.items[0].int32);
    try std.testing.expectEqualSlices(u8, "x", msg.get("b").?.values.items[0].string);
}

test "text format parser decodes single quoted hex octal and C escapes" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto2";
        \\message M { optional string text = 1; optional bytes raw = 2; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("M").?;
    var msg = try parseAlloc(allocator, &file, desc,
        \\text: 'line\n\x41\101'
        \\raw: "\001\x02\a\b\f\v\?"
    );
    defer msg.deinit();
    try std.testing.expectEqualSlices(u8, "line\nAA", msg.get("text").?.values.items[0].string);
    try std.testing.expectEqualSlices(u8, &.{ 0x01, 0x02, 0x07, 0x08, 0x0c, 0x0b, '?' }, msg.get("raw").?.values.items[0].bytes);
}

test "text format parser concatenates adjacent string literals" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto2";
        \\message M { optional string text = 1; optional bytes raw = 2; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("M").?;
    var msg = try parseAlloc(allocator, &file, desc,
        \\text: "hello" ' ' "world"
        \\raw: "\001" '\x02'
    );
    defer msg.deinit();
    try std.testing.expectEqualSlices(u8, "hello world", msg.get("text").?.values.items[0].string);
    try std.testing.expectEqualSlices(u8, &.{ 0x01, 0x02 }, msg.get("raw").?.values.items[0].bytes);
}

test "text format parser accepts bool aliases" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\message M { repeated bool flags = 1; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("M").?;
    var msg = try parseAlloc(allocator, &file, desc, "flags: true flags: false flags: t flags: f flags: 1 flags: 0");
    defer msg.deinit();
    const flags = msg.get("flags").?.values.items;
    try std.testing.expectEqual(@as(usize, 6), flags.len);
    try std.testing.expect(flags[0].boolean);
    try std.testing.expect(!flags[1].boolean);
    try std.testing.expect(flags[2].boolean);
    try std.testing.expect(!flags[3].boolean);
    try std.testing.expect(flags[4].boolean);
    try std.testing.expect(!flags[5].boolean);
}

test "text format parser accepts decimal hex and octal integers" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\message M {
        \\  int32 a = 1;
        \\  int64 b = 2;
        \\  uint32 c = 3;
        \\  fixed64 d = 4;
        \\  sfixed32 e = 5;
        \\}
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("M").?;
    var msg = try parseAlloc(allocator, &file, desc, "a: -0x10 b: +010 c: 0x10 d: 010 e: -010");
    defer msg.deinit();
    try std.testing.expectEqual(@as(i32, -16), msg.get("a").?.values.items[0].int32);
    try std.testing.expectEqual(@as(i64, 8), msg.get("b").?.values.items[0].int64);
    try std.testing.expectEqual(@as(u32, 16), msg.get("c").?.values.items[0].uint32);
    try std.testing.expectEqual(@as(u64, 8), msg.get("d").?.values.items[0].fixed64);
    try std.testing.expectEqual(@as(i32, -8), msg.get("e").?.values.items[0].sfixed32);
}
