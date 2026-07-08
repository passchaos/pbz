const std = @import("std");
const schema = @import("schema.zig");
const dynamic = @import("dynamic.zig");

pub const Error = std.Io.Writer.Error || std.mem.Allocator.Error || error{TypeMismatch};

pub const Options = struct {
    enum_as_name: bool = true,
    preserve_proto_field_names: bool = true,
};

pub fn stringifyAlloc(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    message: *const dynamic.DynamicMessage,
    options: Options,
) Error![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    try stringify(file, message, options, &out.writer);
    return try out.toOwnedSlice();
}

pub fn stringify(
    file: *const schema.FileDescriptor,
    message: *const dynamic.DynamicMessage,
    options: Options,
    writer: *std.Io.Writer,
) Error!void {
    try writeMessage(file, message, options, writer);
}

fn writeMessage(
    file: *const schema.FileDescriptor,
    message: *const dynamic.DynamicMessage,
    options: Options,
    writer: *std.Io.Writer,
) Error!void {
    try writer.writeAll("{");
    var first = true;
    for (message.fields.items) |*entry| {
        if (entry.values.items.len == 0) continue;
        if (!first) try writer.writeAll(",");
        first = false;
        try writeJsonString(fieldJsonName(entry.descriptor, options), writer);
        try writer.writeAll(":");
        if (entry.descriptor.kind == .map) {
            try writeMap(file, entry.descriptor, entry.values.items, options, writer);
        } else if (entry.descriptor.cardinality == .repeated) {
            try writer.writeAll("[");
            for (entry.values.items, 0..) |value, index| {
                if (index != 0) try writer.writeAll(",");
                try writeValue(file, entry.descriptor.kind, value, options, writer);
            }
            try writer.writeAll("]");
        } else {
            try writeValue(file, entry.descriptor.kind, entry.values.items[entry.values.items.len - 1], options, writer);
        }
    }
    try writer.writeAll("}");
}

fn writeMap(
    file: *const schema.FileDescriptor,
    field: *const schema.FieldDescriptor,
    values: []const dynamic.Value,
    options: Options,
    writer: *std.Io.Writer,
) Error!void {
    const map_type = switch (field.kind) {
        .map => |map| map,
        else => return error.TypeMismatch,
    };
    try writer.writeAll("{");
    for (values, 0..) |value, index| {
        const entry = switch (value) {
            .map_entry => |map_entry| map_entry,
            else => return error.TypeMismatch,
        };
        if (index != 0) try writer.writeAll(",");
        try writeMapKey(map_type.key, entry.key, writer);
        try writer.writeAll(":");
        try writeValue(file, map_type.value.*, entry.value, options, writer);
    }
    try writer.writeAll("}");
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
        .message => switch (value) {
            .message => |message| try writeMessage(file, message, options, writer),
            else => return error.TypeMismatch,
        },
        .group => switch (value) {
            .group => |message| try writeMessage(file, message, options, writer),
            else => return error.TypeMismatch,
        },
        .map => return error.TypeMismatch,
    }
}

fn writeScalar(scalar: schema.ScalarType, value: dynamic.Value, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .double => switch (value) {
            .double => |v| try writeFloat(v, writer),
            else => return error.TypeMismatch,
        },
        .float => switch (value) {
            .float => |v| try writeFloat(@as(f64, v), writer),
            else => return error.TypeMismatch,
        },
        .int32 => switch (value) {
            .int32 => |v| try writer.print("{d}", .{v}),
            else => return error.TypeMismatch,
        },
        .uint32 => switch (value) {
            .uint32 => |v| try writer.print("{d}", .{v}),
            else => return error.TypeMismatch,
        },
        .sint32 => switch (value) {
            .sint32 => |v| try writer.print("{d}", .{v}),
            else => return error.TypeMismatch,
        },
        .fixed32 => switch (value) {
            .fixed32 => |v| try writer.print("{d}", .{v}),
            else => return error.TypeMismatch,
        },
        .sfixed32 => switch (value) {
            .sfixed32 => |v| try writer.print("{d}", .{v}),
            else => return error.TypeMismatch,
        },
        .int64 => switch (value) {
            .int64 => |v| try writeJsonStringFmt(writer, "{d}", .{v}),
            else => return error.TypeMismatch,
        },
        .uint64 => switch (value) {
            .uint64 => |v| try writeJsonStringFmt(writer, "{d}", .{v}),
            else => return error.TypeMismatch,
        },
        .sint64 => switch (value) {
            .sint64 => |v| try writeJsonStringFmt(writer, "{d}", .{v}),
            else => return error.TypeMismatch,
        },
        .fixed64 => switch (value) {
            .fixed64 => |v| try writeJsonStringFmt(writer, "{d}", .{v}),
            else => return error.TypeMismatch,
        },
        .sfixed64 => switch (value) {
            .sfixed64 => |v| try writeJsonStringFmt(writer, "{d}", .{v}),
            else => return error.TypeMismatch,
        },
        .bool => switch (value) {
            .boolean => |v| try writer.writeAll(if (v) "true" else "false"),
            else => return error.TypeMismatch,
        },
        .string => switch (value) {
            .string => |v| try writeJsonString(v, writer),
            else => return error.TypeMismatch,
        },
        .bytes => switch (value) {
            .bytes => |v| try writeBase64String(v, writer),
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
                if (enum_value.number == number) {
                    try writeJsonString(enum_value.name, writer);
                    return;
                }
            }
        }
    }
    try writer.print("{d}", .{number});
}

fn writeMapKey(scalar: schema.ScalarType, value: dynamic.Value, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .bool => switch (value) {
            .boolean => |v| try writeJsonString(if (v) "true" else "false", writer),
            else => return error.TypeMismatch,
        },
        .string => switch (value) {
            .string => |v| try writeJsonString(v, writer),
            else => return error.TypeMismatch,
        },
        .int32 => switch (value) {
            .int32 => |v| try writeJsonStringFmt(writer, "{d}", .{v}),
            else => return error.TypeMismatch,
        },
        .uint32 => switch (value) {
            .uint32 => |v| try writeJsonStringFmt(writer, "{d}", .{v}),
            else => return error.TypeMismatch,
        },
        .sint32 => switch (value) {
            .sint32 => |v| try writeJsonStringFmt(writer, "{d}", .{v}),
            else => return error.TypeMismatch,
        },
        .fixed32 => switch (value) {
            .fixed32 => |v| try writeJsonStringFmt(writer, "{d}", .{v}),
            else => return error.TypeMismatch,
        },
        .sfixed32 => switch (value) {
            .sfixed32 => |v| try writeJsonStringFmt(writer, "{d}", .{v}),
            else => return error.TypeMismatch,
        },
        .int64 => switch (value) {
            .int64 => |v| try writeJsonStringFmt(writer, "{d}", .{v}),
            else => return error.TypeMismatch,
        },
        .uint64 => switch (value) {
            .uint64 => |v| try writeJsonStringFmt(writer, "{d}", .{v}),
            else => return error.TypeMismatch,
        },
        .sint64 => switch (value) {
            .sint64 => |v| try writeJsonStringFmt(writer, "{d}", .{v}),
            else => return error.TypeMismatch,
        },
        .fixed64 => switch (value) {
            .fixed64 => |v| try writeJsonStringFmt(writer, "{d}", .{v}),
            else => return error.TypeMismatch,
        },
        .sfixed64 => switch (value) {
            .sfixed64 => |v| try writeJsonStringFmt(writer, "{d}", .{v}),
            else => return error.TypeMismatch,
        },
        .float, .double, .bytes => return error.TypeMismatch,
    }
}

fn writeFloat(value: f64, writer: *std.Io.Writer) Error!void {
    if (std.math.isNan(value)) return try writeJsonString("NaN", writer);
    if (std.math.isPositiveInf(value)) return try writeJsonString("Infinity", writer);
    if (std.math.isNegativeInf(value)) return try writeJsonString("-Infinity", writer);
    try writer.print("{d}", .{value});
}

fn writeBase64String(bytes: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("\"");
    try std.base64.standard.Encoder.encodeWriter(writer, bytes);
    try writer.writeAll("\"");
}

fn writeJsonString(value: []const u8, writer: *std.Io.Writer) Error!void {
    try std.json.Stringify.value(value, .{}, writer);
}

fn writeJsonStringFmt(writer: *std.Io.Writer, comptime fmt: []const u8, args: anytype) Error!void {
    try writer.writeAll("\"");
    try writer.print(fmt, args);
    try writer.writeAll("\"");
}

fn fieldJsonName(field: *const schema.FieldDescriptor, options: Options) []const u8 {
    if (options.preserve_proto_field_names) return field.name;
    return field.json_name orelse field.name;
}

test "json stringify dynamic message with scalars repeated maps enums and nested messages" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\package demo;
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message Child { string label = 1; }
        \\message Bag {
        \\  int32 id = 1;
        \\  int64 big = 2;
        \\  bytes raw = 3;
        \\  repeated string tags = 4;
        \\  map<string, int32> counts = 5;
        \\  Child child = 6;
        \\  Kind kind = 7;
        \\}
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const bag_desc = file.findMessage("Bag").?;
    const child_desc = file.findMessage("Child").?;

    var bag = dynamic.DynamicMessage.init(allocator, bag_desc);
    defer bag.deinit();
    try bag.add(bag_desc.findField("id").?, .{ .int32 = 7 });
    try bag.add(bag_desc.findField("big").?, .{ .int64 = 9007199254740993 });
    try bag.add(bag_desc.findField("raw").?, .{ .bytes = try allocator.dupe(u8, "hi") });
    try bag.add(bag_desc.findField("tags").?, .{ .string = try allocator.dupe(u8, "a") });
    try bag.add(bag_desc.findField("tags").?, .{ .string = try allocator.dupe(u8, "b") });

    const count_entry = try allocator.create(dynamic.MapEntry);
    count_entry.* = .{ .key = .{ .string = try allocator.dupe(u8, "red") }, .value = .{ .int32 = 3 } };
    try bag.add(bag_desc.findField("counts").?, .{ .map_entry = count_entry });

    const child = try allocator.create(dynamic.DynamicMessage);
    child.* = dynamic.DynamicMessage.init(allocator, child_desc);
    try child.add(child_desc.findField("label").?, .{ .string = try allocator.dupe(u8, "kid") });
    try bag.add(bag_desc.findField("child").?, .{ .message = child });
    try bag.add(bag_desc.findField("kind").?, .{ .enumeration = 1 });

    const json = try stringifyAlloc(allocator, &file, &bag, .{});
    defer allocator.free(json);
    try std.testing.expectEqualSlices(u8, "{\"id\":7,\"big\":\"9007199254740993\",\"raw\":\"aGk=\",\"tags\":[\"a\",\"b\"],\"counts\":{\"red\":3},\"child\":{\"label\":\"kid\"},\"kind\":\"ADMIN\"}", json);
}
