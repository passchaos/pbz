const std = @import("std");
const schema = @import("schema.zig");
const dynamic = @import("dynamic.zig");
const registry_mod = @import("registry.zig");
const wire = @import("wire.zig");

pub const Error = std.Io.Writer.Error || wire.Error || error{TypeMismatch};

pub const Options = struct {
    indent: []const u8 = "  ",
    enum_as_name: bool = true,
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
            for (entry.values.items) |value| try writeMapEntry(file, registry, entry.descriptor, value, options, writer, depth);
        } else if (entry.descriptor.cardinality == .repeated) {
            for (entry.values.items) |value| try writeField(file, registry, entry.descriptor, entry.descriptor.name, entry.descriptor.kind, value, options, writer, depth);
        } else if (entry.values.items.len != 0) {
            try writeField(file, registry, entry.descriptor, entry.descriptor.name, entry.descriptor.kind, entry.values.items[entry.values.items.len - 1], options, writer, depth);
        }
    }
    for (message.unknown_fields.items) |*unknown| try writeUnknownRaw(unknown.data, options, writer, depth);
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
            try writer.print("{d}: ", .{tag.number});
            try writeQuoted(try reader.readBytes(), writer);
            try writer.writeAll("\n");
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

fn writeMapEntry(
    file: *const schema.FileDescriptor,
    registry: ?*const registry_mod.Registry,
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
    try writeField(file, registry, null, "key", .{ .scalar = map_type.key }, entry.key, options, writer, depth + 1);
    try writeField(file, registry, null, "value", map_type.value.*, entry.value, options, writer, depth + 1);
    try writeIndent(writer, options, depth);
    try writer.writeAll("}\n");
}

fn writeField(
    file: *const schema.FileDescriptor,
    registry: ?*const registry_mod.Registry,
    field: ?*const schema.FieldDescriptor,
    name: []const u8,
    kind: schema.FieldKind,
    value: dynamic.Value,
    options: Options,
    writer: *std.Io.Writer,
    depth: usize,
) Error!void {
    try writeIndent(writer, options, depth);
    switch (kind) {
        .message => |type_name| {
            if (value == .enumeration) {
                if (registryEnumDescriptor(file, registry, field, type_name)) |_| {
                    try writeFieldName(file, field, name, writer);
                    try writer.writeAll(": ");
                    try writeEnum(file, registry, type_name, value, options, writer);
                    try writer.writeAll("\n");
                    return;
                }
            }
            switch (value) {
                .message => |message| {
                    try writeFieldName(file, field, name, writer);
                    try writer.writeAll(" {\n");
                    try writeMessageFields(file, registry, message, options, writer, depth + 1);
                    try writeIndent(writer, options, depth);
                    try writer.writeAll("}\n");
                },
                else => return error.TypeMismatch,
            }
        },
        .group => switch (value) {
            .group => |message| {
                try writeFieldName(file, field, name, writer);
                try writer.writeAll(" {\n");
                try writeMessageFields(file, registry, message, options, writer, depth + 1);
                try writeIndent(writer, options, depth);
                try writer.writeAll("}\n");
            },
            else => return error.TypeMismatch,
        },
        else => {
            try writeFieldName(file, field, name, writer);
            try writer.writeAll(": ");
            try writeValue(file, registry, kind, value, options, writer);
            try writer.writeAll("\n");
        },
    }
}

fn writeFieldName(file: *const schema.FileDescriptor, field: ?*const schema.FieldDescriptor, fallback: []const u8, writer: *std.Io.Writer) Error!void {
    const descriptor = field orelse return try writer.writeAll(fallback);
    if (descriptor.extendee == null) return try writer.writeAll(fallback);
    try writer.writeByte('[');
    if (file.package.len != 0 and std.mem.indexOfScalar(u8, descriptor.name, '.') == null) {
        try writer.print("{s}.{s}", .{ file.package, descriptor.name });
    } else {
        try writer.writeAll(descriptor.name);
    }
    try writer.writeByte(']');
}

fn writeValue(
    file: *const schema.FileDescriptor,
    registry: ?*const registry_mod.Registry,
    kind: schema.FieldKind,
    value: dynamic.Value,
    options: Options,
    writer: *std.Io.Writer,
) Error!void {
    switch (kind) {
        .scalar => |scalar| try writeScalar(scalar, value, writer),
        .enumeration => |name| try writeEnum(file, registry, name, value, options, writer),
        .message => |name| {
            if (value == .enumeration and registryEnumDescriptor(file, registry, null, name) != null) return try writeEnum(file, registry, name, value, options, writer);
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
        if (registryEnumDescriptor(file, registry, null, name) orelse file.findEnumDeep(name)) |enumeration| {
            for (enumeration.values.items) |enum_value| {
                if (enum_value.number == number) return try writer.writeAll(enum_value.name);
            }
        }
    }
    try writer.print("{d}", .{number});
}

fn registryEnumDescriptor(file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, field: ?*const schema.FieldDescriptor, name: []const u8) ?*const schema.EnumDescriptor {
    if (registry) |reg| {
        if (field) |descriptor| {
            if (reg.findEnum(name, descriptor.name)) |enumeration| return enumeration;
        }
        if (reg.findEnum(name, null)) |enumeration| return enumeration;
    }
    const trimmed = if (std.mem.startsWith(u8, name, ".")) name[1..] else name;
    return file.findEnumDeep(trimmed);
}

fn writeQuoted(bytes: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("\"");
    for (bytes) |c| {
        if (c == '\\') try writer.writeAll("\\\\") else if (c == '"') try writer.writeAll("\\\"") else if (c == '\n') try writer.writeAll("\\n") else if (c == '\r') try writer.writeAll("\\r") else if (c == '\t') try writer.writeAll("\\t") else if (c >= 0x20 and c <= 0x7e) try writer.writeByte(c) else try writer.print("\\{o:0>3}", .{c});
    }
    try writer.writeAll("\"");
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

const TextParser = struct {
    allocator: std.mem.Allocator,
    input: []const u8,
    registry: ?*const registry_mod.Registry = null,
    index: usize = 0,

    fn parseMessage(self: *TextParser, file: *const schema.FileDescriptor, message: *dynamic.DynamicMessage, end: ?u8) !void {
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
            const unknown_number = if (self.peekIsDigit() != null) try self.readUnknownNumber() else null;
            const field = if (unknown_number != null) null else try self.readFieldReference(message.descriptor);
            self.skipSpace();
            if (self.consume(':')) {
                self.skipSpace();
                if (field == null) {
                    try self.parseUnknownField(message, unknown_number.?);
                    self.consumeSeparator();
                } else if (field.?.kind == .map or field.?.kind == .message or field.?.kind == .group) {
                    const close = try self.consumeAggregateStart();
                    try self.parseAggregateField(file, message, field.?, close);
                } else {
                    var value = try self.parseValue(file, message.descriptor, field.?, field.?.kind);
                    message.add(field.?, value) catch |err| {
                        dynamic.deinitValue(&value, self.allocator);
                        return err;
                    };
                    self.consumeSeparator();
                }
            } else if (self.peek() == '{' or self.peek() == '<') {
                const close = try self.consumeAggregateStart();
                if (field == null) {
                    try self.parseUnknownGroup(message, unknown_number.?, close);
                    self.consumeSeparator();
                } else {
                    try self.parseAggregateField(file, message, field.?, close);
                }
            } else return error.UnexpectedToken;
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

    fn readFieldReference(self: *TextParser, descriptor: *const schema.MessageDescriptor) !*const schema.FieldDescriptor {
        self.skipSpace();
        if (self.consume('[')) {
            const name = try self.readExtensionName();
            return self.findExtension(descriptor, name) orelse return error.UnknownField;
        }
        const name = try self.readIdent();
        return descriptor.findField(name) orelse return error.UnknownField;
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

    fn findExtension(self: *TextParser, descriptor: *const schema.MessageDescriptor, name: []const u8) ?*const schema.FieldDescriptor {
        const registry = self.registry orelse return null;
        if (registry.findExtensionByName(descriptor.name, name)) |field| return field;
        const trimmed = if (std.mem.startsWith(u8, name, ".")) name[1..] else name;
        const leaf = if (std.mem.lastIndexOfScalar(u8, trimmed, '.')) |idx| trimmed[idx + 1 ..] else trimmed;
        if (!std.mem.eql(u8, leaf, name)) {
            if (registry.findExtensionByName(descriptor.name, leaf)) |field| return field;
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
            var value = try self.parseMapEntry(file, message.descriptor, field, field.kind.map, close);
            message.add(field, value) catch |err| {
                dynamic.deinitValue(&value, self.allocator);
                return err;
            };
            self.consumeSeparator();
        } else {
            const nested_desc = switch (field.kind) {
                .message => |type_name| resolveMessageDescriptor(file, message.descriptor, type_name) orelse return error.TypeMismatch,
                .group => |type_name| resolveMessageDescriptor(file, message.descriptor, type_name) orelse return error.TypeMismatch,
                else => return error.TypeMismatch,
            };
            const nested = try self.allocator.create(dynamic.DynamicMessage);
            nested.* = dynamic.DynamicMessage.init(self.allocator, nested_desc);
            errdefer {
                nested.deinit();
                self.allocator.destroy(nested);
            }
            try self.parseMessage(file, nested, close);
            try message.add(field, if (field.kind == .group) .{ .group = nested } else .{ .message = nested });
            self.consumeSeparator();
        }
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
            try self.expect(':');
            if (std.mem.eql(u8, name, "key")) {
                key = try self.parseValue(file, current, field, .{ .scalar = map_type.key });
            } else if (std.mem.eql(u8, name, "value")) {
                value = try self.parseValue(file, current, field, map_type.value.*);
            } else return error.UnknownField;
            self.consumeSeparator();
        }
        const entry = try self.allocator.create(dynamic.MapEntry);
        entry.* = .{ .key = key orelse return error.TypeMismatch, .value = value orelse return error.TypeMismatch };
        return .{ .map_entry = entry };
    }

    fn parseValue(self: *TextParser, file: *const schema.FileDescriptor, current: *const schema.MessageDescriptor, field: ?*const schema.FieldDescriptor, kind: schema.FieldKind) !dynamic.Value {
        self.skipSpace();
        return switch (kind) {
            .scalar => |scalar| try self.parseScalar(file, field, scalar),
            .enumeration => |name| try self.parseEnum(file, current, name),
            .message, .group, .map => error.TypeMismatch,
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
            .double => .{ .double = try std.fmt.parseFloat(f64, try self.readAtom()) },
            .float => .{ .float = try std.fmt.parseFloat(f32, try self.readAtom()) },
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
        const enumeration = current.findEnumDeep(name) orelse file.findEnumDeep(name);
        if (std.fmt.parseInt(i32, atom, 10)) |number| {
            if (enumeration) |enum_desc| {
                if (enumIsClosed(file, enum_desc) and !enumHasNumber(enum_desc, number)) return error.InvalidEnumValue;
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
            } else try out.append(self.allocator, c);
        }
        return error.UnexpectedEof;
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
        while (!self.eof() and !std.ascii.isWhitespace(self.peek()) and self.peek() != '}' and self.peek() != '>' and self.peek() != ',' and self.peek() != ';') self.index += 1;
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

fn enumIsClosed(file: *const schema.FileDescriptor, enumeration: *const schema.EnumDescriptor) bool {
    if (enumeration.features) |features| return features.enum_type == .closed;
    return file.features.enum_type == .closed;
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
            \\syntax = "proto3";
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
        \\extend Host {
        \\  optional string tag = 100;
        \\  repeated int32 nums = 101;
        \\  optional Note note = 102;
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

    const text = try formatAlloc(allocator, &file, &msg, .{});
    defer allocator.free(text);
    try std.testing.expectEqualSlices(u8,
        \\id: 7
        \\[demo.tag]: "hello"
        \\[demo.nums]: 1
        \\[demo.nums]: 2
        \\[demo.note] {
        \\  text: "body"
        \\}
        \\
    , text);

    var parsed = try parseAllocWithRegistry(allocator, &file, &registry, host,
        \\id: 8
        \\[demo.tag]: "parsed"
        \\[demo.nums]: 3
        \\[demo.nums]: 4
        \\[demo.note] < text: "parsed body" >
    );
    defer parsed.deinit();
    try std.testing.expectEqual(@as(i32, 8), parsed.get("id").?.values.items[0].int32);
    try std.testing.expectEqualSlices(u8, "parsed", parsed.get("tag").?.values.items[0].string);
    try std.testing.expectEqual(@as(i32, 3), parsed.get("nums").?.values.items[0].int32);
    try std.testing.expectEqual(@as(i32, 4), parsed.get("nums").?.values.items[1].int32);
    try std.testing.expectEqualSlices(u8, "parsed body", parsed.get("note").?.values.items[0].message.get("text").?.values.items[0].string);
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

    const text = try formatAlloc(allocator, &file, &msg, .{});
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

    const text = try formatAlloc(allocator, &file, &msg, .{});
    defer allocator.free(text);
    try std.testing.expectEqualSlices(u8,
        \\id: 7
        \\100: 123
        \\101: "blob"
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

    const text = try formatAlloc(allocator, &file, &parsed, .{});
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
