const std = @import("std");
const schema = @import("schema.zig");
const dynamic = @import("dynamic.zig");

pub const Error = std.Io.Writer.Error || error{TypeMismatch};

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
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    try format(file, message, options, &out.writer);
    return try out.toOwnedSlice();
}

pub fn format(
    file: *const schema.FileDescriptor,
    message: *const dynamic.DynamicMessage,
    options: Options,
    writer: *std.Io.Writer,
) Error!void {
    try writeMessageFields(file, message, options, writer, 0);
}

fn writeMessageFields(
    file: *const schema.FileDescriptor,
    message: *const dynamic.DynamicMessage,
    options: Options,
    writer: *std.Io.Writer,
    depth: usize,
) Error!void {
    for (message.fields.items) |*entry| {
        if (entry.descriptor.kind == .map) {
            for (entry.values.items) |value| try writeMapEntry(file, entry.descriptor, value, options, writer, depth);
        } else if (entry.descriptor.cardinality == .repeated) {
            for (entry.values.items) |value| try writeField(file, entry.descriptor.name, entry.descriptor.kind, value, options, writer, depth);
        } else if (entry.values.items.len != 0) {
            try writeField(file, entry.descriptor.name, entry.descriptor.kind, entry.values.items[entry.values.items.len - 1], options, writer, depth);
        }
    }
}

fn writeMapEntry(
    file: *const schema.FileDescriptor,
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
    try writer.print("{s} {{\n", .{field.name});
    try writeField(file, "key", .{ .scalar = map_type.key }, entry.key, options, writer, depth + 1);
    try writeField(file, "value", map_type.value.*, entry.value, options, writer, depth + 1);
    try writeIndent(writer, options, depth);
    try writer.writeAll("}\n");
}

fn writeField(
    file: *const schema.FileDescriptor,
    name: []const u8,
    kind: schema.FieldKind,
    value: dynamic.Value,
    options: Options,
    writer: *std.Io.Writer,
    depth: usize,
) Error!void {
    try writeIndent(writer, options, depth);
    switch (kind) {
        .message => switch (value) {
            .message => |message| {
                try writer.print("{s} {{\n", .{name});
                try writeMessageFields(file, message, options, writer, depth + 1);
                try writeIndent(writer, options, depth);
                try writer.writeAll("}\n");
            },
            else => return error.TypeMismatch,
        },
        .group => switch (value) {
            .group => |message| {
                try writer.print("{s} {{\n", .{name});
                try writeMessageFields(file, message, options, writer, depth + 1);
                try writeIndent(writer, options, depth);
                try writer.writeAll("}\n");
            },
            else => return error.TypeMismatch,
        },
        else => {
            try writer.print("{s}: ", .{name});
            try writeValue(file, kind, value, options, writer);
            try writer.writeAll("\n");
        },
    }
}

fn writeValue(
    file: *const schema.FileDescriptor,
    kind: schema.FieldKind,
    value: dynamic.Value,
    options: Options,
    writer: *std.Io.Writer,
) Error!void {
    switch (kind) {
        .scalar => |scalar| try writeScalar(scalar, value, writer),
        .enumeration => |name| try writeEnum(file, name, value, options, writer),
        .message, .group, .map => return error.TypeMismatch,
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
        if (file.findEnumDeep(name)) |enumeration| {
            for (enumeration.values.items) |enum_value| {
                if (enum_value.number == number) return try writer.writeAll(enum_value.name);
            }
        }
    }
    try writer.print("{d}", .{number});
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

pub fn parseAlloc(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    descriptor: *const schema.MessageDescriptor,
    input: []const u8,
) !dynamic.DynamicMessage {
    var parser_state = TextParser{ .allocator = allocator, .input = input };
    var message = dynamic.DynamicMessage.init(allocator, descriptor);
    errdefer message.deinit();
    try parser_state.parseMessage(file, &message, null);
    return message;
}

const TextParser = struct {
    allocator: std.mem.Allocator,
    input: []const u8,
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
            const name = try self.readIdent();
            const field = message.descriptor.findField(name) orelse return error.UnknownField;
            self.skipSpace();
            if (self.consume(':')) {
                if (field.kind == .map) return error.TypeMismatch;
                var value = try self.parseValue(file, message.descriptor, field.kind);
                message.add(field, value) catch |err| {
                    dynamic.deinitValue(&value, self.allocator);
                    return err;
                };
                self.consumeSeparator();
            } else if (self.consume('{') or self.consume('<')) {
                if (field.kind == .map) {
                    var value = try self.parseMapEntry(file, message.descriptor, field.kind.map);
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
                    try self.parseMessage(file, nested, '}');
                    try message.add(field, if (field.kind == .group) .{ .group = nested } else .{ .message = nested });
                    self.consumeSeparator();
                }
            } else return error.UnexpectedToken;
        }
    }

    fn parseMapEntry(self: *TextParser, file: *const schema.FileDescriptor, current: *const schema.MessageDescriptor, map_type: schema.MapType) !dynamic.Value {
        var key: ?dynamic.Value = null;
        var value: ?dynamic.Value = null;
        errdefer {
            if (key) |*v| dynamic.deinitValue(v, self.allocator);
            if (value) |*v| dynamic.deinitValue(v, self.allocator);
        }
        while (true) {
            self.skipSpace();
            if (self.consume('}')) break;
            const name = try self.readIdent();
            self.skipSpace();
            try self.expect(':');
            if (std.mem.eql(u8, name, "key")) {
                key = try self.parseValue(file, current, .{ .scalar = map_type.key });
            } else if (std.mem.eql(u8, name, "value")) {
                value = try self.parseValue(file, current, map_type.value.*);
            } else return error.UnknownField;
            self.consumeSeparator();
        }
        const entry = try self.allocator.create(dynamic.MapEntry);
        entry.* = .{ .key = key orelse return error.TypeMismatch, .value = value orelse return error.TypeMismatch };
        return .{ .map_entry = entry };
    }

    fn parseValue(self: *TextParser, file: *const schema.FileDescriptor, current: *const schema.MessageDescriptor, kind: schema.FieldKind) !dynamic.Value {
        _ = current;
        self.skipSpace();
        return switch (kind) {
            .scalar => |scalar| try self.parseScalar(scalar),
            .enumeration => |name| try self.parseEnum(file, name),
            .message, .group, .map => error.TypeMismatch,
        };
    }

    fn parseScalar(self: *TextParser, scalar: schema.ScalarType) !dynamic.Value {
        return switch (scalar) {
            .string => .{ .string = try self.readString() },
            .bytes => .{ .bytes = try self.readString() },
            .bool => .{ .boolean = try self.readBool() },
            .double => .{ .double = try std.fmt.parseFloat(f64, try self.readAtom()) },
            .float => .{ .float = try std.fmt.parseFloat(f32, try self.readAtom()) },
            .int32 => .{ .int32 = try std.fmt.parseInt(i32, try self.readAtom(), 10) },
            .int64 => .{ .int64 = try std.fmt.parseInt(i64, try self.readAtom(), 10) },
            .uint32 => .{ .uint32 = try std.fmt.parseInt(u32, try self.readAtom(), 10) },
            .uint64 => .{ .uint64 = try std.fmt.parseInt(u64, try self.readAtom(), 10) },
            .sint32 => .{ .sint32 = try std.fmt.parseInt(i32, try self.readAtom(), 10) },
            .sint64 => .{ .sint64 = try std.fmt.parseInt(i64, try self.readAtom(), 10) },
            .fixed32 => .{ .fixed32 = try std.fmt.parseInt(u32, try self.readAtom(), 10) },
            .fixed64 => .{ .fixed64 = try std.fmt.parseInt(u64, try self.readAtom(), 10) },
            .sfixed32 => .{ .sfixed32 = try std.fmt.parseInt(i32, try self.readAtom(), 10) },
            .sfixed64 => .{ .sfixed64 = try std.fmt.parseInt(i64, try self.readAtom(), 10) },
        };
    }

    fn parseEnum(self: *TextParser, file: *const schema.FileDescriptor, name: []const u8) !dynamic.Value {
        const atom = try self.readAtom();
        if (std.fmt.parseInt(i32, atom, 10)) |number| return .{ .enumeration = number } else |_| {}
        if (file.findEnumDeep(name)) |enumeration| {
            if (enumeration.findValue(atom)) |value| return .{ .enumeration = value.number };
        }
        return error.InvalidEnumValue;
    }

    fn readBool(self: *TextParser) !bool {
        const atom = try self.readAtom();
        if (std.mem.eql(u8, atom, "true")) return true;
        if (std.mem.eql(u8, atom, "false")) return false;
        return error.TypeMismatch;
    }

    fn readString(self: *TextParser) ![]u8 {
        self.skipSpace();
        try self.expect('"');
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(self.allocator);
        while (!self.eof()) {
            const c = self.input[self.index];
            self.index += 1;
            if (c == '"') return try out.toOwnedSlice(self.allocator);
            if (c == '\\') {
                if (self.eof()) return error.UnexpectedEof;
                const esc = self.input[self.index];
                self.index += 1;
                try out.append(self.allocator, switch (esc) {
                    'n' => '\n',
                    'r' => '\r',
                    't' => '\t',
                    '\\' => '\\',
                    '"' => '"',
                    else => esc,
                });
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
