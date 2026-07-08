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
