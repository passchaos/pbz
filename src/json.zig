const std = @import("std");
const schema = @import("schema.zig");
const dynamic = @import("dynamic.zig");

pub const Error = std.Io.Writer.Error || std.mem.Allocator.Error || error{TypeMismatch};

pub const Options = struct {
    enum_as_name: bool = true,
    preserve_proto_field_names: bool = true,
    ignore_unknown_fields: bool = false,
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

pub fn parseAlloc(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    descriptor: *const schema.MessageDescriptor,
    bytes: []const u8,
    options: Options,
) anyerror!dynamic.DynamicMessage {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, bytes, .{});
    defer parsed.deinit();

    var message = dynamic.DynamicMessage.init(allocator, descriptor);
    errdefer message.deinit();
    try fillMessage(allocator, file, &message, parsed.value, options);
    return message;
}

pub fn fillMessage(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    message: *dynamic.DynamicMessage,
    json_value: std.json.Value,
    options: Options,
) anyerror!void {
    const object = switch (json_value) {
        .object => |object| object,
        else => return error.TypeMismatch,
    };

    var it = object.iterator();
    while (it.next()) |entry| {
        const field = findJsonField(message.descriptor, entry.key_ptr.*, options) orelse {
            if (options.ignore_unknown_fields) continue;
            return error.UnknownField;
        };
        if (entry.value_ptr.* == .null) continue;
        if (field.kind == .map) {
            try parseMapField(allocator, file, message, field, entry.value_ptr.*, options);
        } else if (field.cardinality == .repeated) {
            const array = switch (entry.value_ptr.*) {
                .array => |array| array,
                else => return error.TypeMismatch,
            };
            for (array.items) |item| {
                var value = try parseValue(allocator, file, message.descriptor, field.kind, item, options);
                message.add(field, value) catch |err| {
                    dynamic.deinitValue(&value, allocator);
                    return err;
                };
            }
        } else {
            var value = try parseValue(allocator, file, message.descriptor, field.kind, entry.value_ptr.*, options);
            message.add(field, value) catch |err| {
                dynamic.deinitValue(&value, allocator);
                return err;
            };
        }
    }
}

fn parseMapField(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    message: *dynamic.DynamicMessage,
    field: *const schema.FieldDescriptor,
    json_value: std.json.Value,
    options: Options,
) anyerror!void {
    const map_type = switch (field.kind) {
        .map => |map| map,
        else => return error.TypeMismatch,
    };
    const object = switch (json_value) {
        .object => |object| object,
        else => return error.TypeMismatch,
    };
    var it = object.iterator();
    while (it.next()) |entry| {
        var key = try parseMapKey(allocator, map_type.key, entry.key_ptr.*);
        errdefer dynamic.deinitValue(&key, allocator);
        var map_value = try parseValue(allocator, file, message.descriptor, map_type.value.*, entry.value_ptr.*, options);
        errdefer dynamic.deinitValue(&map_value, allocator);
        const map_entry = try allocator.create(dynamic.MapEntry);
        map_entry.* = .{ .key = key, .value = map_value };
        message.add(field, .{ .map_entry = map_entry }) catch |err| {
            map_entry.deinit(allocator);
            allocator.destroy(map_entry);
            return err;
        };
    }
}

fn parseValue(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    current: *const schema.MessageDescriptor,
    kind: schema.FieldKind,
    json_value: std.json.Value,
    options: Options,
) anyerror!dynamic.Value {
    return switch (kind) {
        .scalar => |scalar| try parseScalar(allocator, scalar, json_value),
        .enumeration => |name| try parseEnum(file, name, json_value),
        .message => |name| blk: {
            const descriptor = resolveMessageDescriptor(file, current, name) orelse return error.TypeMismatch;
            const nested = try allocator.create(dynamic.DynamicMessage);
            nested.* = dynamic.DynamicMessage.init(allocator, descriptor);
            errdefer {
                nested.deinit();
                allocator.destroy(nested);
            }
            try fillMessage(allocator, file, nested, json_value, options);
            break :blk .{ .message = nested };
        },
        .group => |name| blk: {
            const descriptor = resolveMessageDescriptor(file, current, name) orelse return error.TypeMismatch;
            const nested = try allocator.create(dynamic.DynamicMessage);
            nested.* = dynamic.DynamicMessage.init(allocator, descriptor);
            errdefer {
                nested.deinit();
                allocator.destroy(nested);
            }
            try fillMessage(allocator, file, nested, json_value, options);
            break :blk .{ .group = nested };
        },
        .map => error.TypeMismatch,
    };
}

fn parseScalar(allocator: std.mem.Allocator, scalar: schema.ScalarType, json_value: std.json.Value) !dynamic.Value {
    return switch (scalar) {
        .double => .{ .double = try numberAsFloat(f64, json_value) },
        .float => .{ .float = try numberAsFloat(f32, json_value) },
        .int32 => .{ .int32 = try numberAsInt(i32, json_value) },
        .int64 => .{ .int64 = try numberAsInt(i64, json_value) },
        .uint32 => .{ .uint32 = try numberAsInt(u32, json_value) },
        .uint64 => .{ .uint64 = try numberAsInt(u64, json_value) },
        .sint32 => .{ .sint32 = try numberAsInt(i32, json_value) },
        .sint64 => .{ .sint64 = try numberAsInt(i64, json_value) },
        .fixed32 => .{ .fixed32 = try numberAsInt(u32, json_value) },
        .fixed64 => .{ .fixed64 = try numberAsInt(u64, json_value) },
        .sfixed32 => .{ .sfixed32 = try numberAsInt(i32, json_value) },
        .sfixed64 => .{ .sfixed64 = try numberAsInt(i64, json_value) },
        .bool => switch (json_value) {
            .bool => |value| .{ .boolean = value },
            else => error.TypeMismatch,
        },
        .string => switch (json_value) {
            .string => |value| .{ .string = try allocator.dupe(u8, value) },
            else => error.TypeMismatch,
        },
        .bytes => switch (json_value) {
            .string => |value| .{ .bytes = try decodeBase64(allocator, value) },
            else => error.TypeMismatch,
        },
    };
}

fn parseEnum(file: *const schema.FileDescriptor, name: []const u8, json_value: std.json.Value) !dynamic.Value {
    switch (json_value) {
        .string => |value| {
            if (file.findEnumDeep(name)) |enumeration| {
                for (enumeration.values.items) |enum_value| {
                    if (std.mem.eql(u8, enum_value.name, value)) return .{ .enumeration = enum_value.number };
                }
            }
            return error.InvalidEnumValue;
        },
        else => return .{ .enumeration = try numberAsInt(i32, json_value) },
    }
}

fn parseMapKey(allocator: std.mem.Allocator, scalar: schema.ScalarType, key: []const u8) !dynamic.Value {
    return switch (scalar) {
        .bool => if (std.mem.eql(u8, key, "true"))
            .{ .boolean = true }
        else if (std.mem.eql(u8, key, "false"))
            .{ .boolean = false }
        else
            error.TypeMismatch,
        .string => .{ .string = try allocator.dupe(u8, key) },
        .int32 => .{ .int32 = try std.fmt.parseInt(i32, key, 10) },
        .int64 => .{ .int64 = try std.fmt.parseInt(i64, key, 10) },
        .uint32 => .{ .uint32 = try std.fmt.parseInt(u32, key, 10) },
        .uint64 => .{ .uint64 = try std.fmt.parseInt(u64, key, 10) },
        .sint32 => .{ .sint32 = try std.fmt.parseInt(i32, key, 10) },
        .sint64 => .{ .sint64 = try std.fmt.parseInt(i64, key, 10) },
        .fixed32 => .{ .fixed32 = try std.fmt.parseInt(u32, key, 10) },
        .fixed64 => .{ .fixed64 = try std.fmt.parseInt(u64, key, 10) },
        .sfixed32 => .{ .sfixed32 = try std.fmt.parseInt(i32, key, 10) },
        .sfixed64 => .{ .sfixed64 = try std.fmt.parseInt(i64, key, 10) },
        .double, .float, .bytes => error.TypeMismatch,
    };
}

fn numberAsInt(comptime T: type, json_value: std.json.Value) !T {
    const info = @typeInfo(T).int;
    switch (json_value) {
        .integer => |value| {
            if (value < std.math.minInt(T) or value > std.math.maxInt(T)) return error.Overflow;
            return @intCast(value);
        },
        .number_string, .string => |value| return try std.fmt.parseInt(T, value, 10),
        else => {
            _ = info;
            return error.TypeMismatch;
        },
    }
}

fn numberAsFloat(comptime T: type, json_value: std.json.Value) !T {
    return switch (json_value) {
        .integer => |value| @floatFromInt(value),
        .float => |value| @floatCast(value),
        .number_string => |value| try std.fmt.parseFloat(T, value),
        .string => |value| if (std.mem.eql(u8, value, "NaN"))
            std.math.nan(T)
        else if (std.mem.eql(u8, value, "Infinity"))
            std.math.inf(T)
        else if (std.mem.eql(u8, value, "-Infinity"))
            -std.math.inf(T)
        else
            try std.fmt.parseFloat(T, value),
        else => error.TypeMismatch,
    };
}

fn decodeBase64(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    return decodeBase64With(allocator, &std.base64.standard.Decoder, value) catch
        decodeBase64With(allocator, &std.base64.url_safe.Decoder, value) catch
        decodeBase64With(allocator, &std.base64.standard_no_pad.Decoder, value) catch
        decodeBase64With(allocator, &std.base64.url_safe_no_pad.Decoder, value);
}

fn decodeBase64With(allocator: std.mem.Allocator, decoder: *const std.base64.Base64Decoder, value: []const u8) ![]u8 {
    const size = try decoder.calcSizeForSlice(value);
    const out = try allocator.alloc(u8, size);
    errdefer allocator.free(out);
    try decoder.decode(out, value);
    return out;
}

fn resolveMessageDescriptor(file: *const schema.FileDescriptor, current: *const schema.MessageDescriptor, name: []const u8) ?*const schema.MessageDescriptor {
    const trimmed = if (std.mem.startsWith(u8, name, ".")) name[1..] else name;
    const leaf = if (std.mem.lastIndexOfScalar(u8, trimmed, '.')) |idx| trimmed[idx + 1 ..] else trimmed;
    if (std.mem.eql(u8, current.name, trimmed) or std.mem.eql(u8, current.name, leaf)) return current;
    if (current.findMessageDeep(trimmed)) |message| return message;
    return file.findMessageDeep(trimmed);
}

fn findJsonField(message: *const schema.MessageDescriptor, key: []const u8, options: Options) ?*const schema.FieldDescriptor {
    _ = options;
    for (message.fields.items) |*field| {
        if (std.mem.eql(u8, field.name, key)) return field;
        if (field.json_name) |json_name| {
            if (std.mem.eql(u8, json_name, key)) return field;
        } else if (eqlLowerCamel(field.name, key)) return field;
    }
    return null;
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
        try writeFieldName(entry.descriptor, options, writer);
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

fn writeFieldName(field: *const schema.FieldDescriptor, options: Options, writer: *std.Io.Writer) Error!void {
    if (options.preserve_proto_field_names) return writeJsonString(field.name, writer);
    if (field.json_name) |json_name| return writeJsonString(json_name, writer);
    try writer.writeAll("\"");
    try writeLowerCamel(field.name, writer);
    try writer.writeAll("\"");
}

fn writeLowerCamel(name: []const u8, writer: *std.Io.Writer) Error!void {
    var upper_next = false;
    for (name) |c| {
        if (c == '_') {
            upper_next = true;
        } else if (upper_next) {
            try writer.writeByte(std.ascii.toUpper(c));
            upper_next = false;
        } else {
            try writer.writeByte(c);
        }
    }
}

fn eqlLowerCamel(name: []const u8, candidate: []const u8) bool {
    var i: usize = 0;
    var upper_next = false;
    for (name) |c| {
        if (c == '_') {
            upper_next = true;
            continue;
        }
        if (i >= candidate.len) return false;
        const expected = if (upper_next) std.ascii.toUpper(c) else c;
        upper_next = false;
        if (candidate[i] != expected) return false;
        i += 1;
    }
    return i == candidate.len;
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

test "json parse dynamic message with scalars repeated maps enums and nested messages" {
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

    var bag = try parseAlloc(allocator, &file, bag_desc,
        \\{"id":7,"big":"9007199254740993","raw":"aGk=","tags":["a","b"],"counts":{"red":3},"child":{"label":"kid"},"kind":"ADMIN"}
    , .{});
    defer bag.deinit();

    try std.testing.expectEqual(@as(i32, 7), bag.get("id").?.values.items[0].int32);
    try std.testing.expectEqual(@as(i64, 9007199254740993), bag.get("big").?.values.items[0].int64);
    try std.testing.expectEqualSlices(u8, "hi", bag.get("raw").?.values.items[0].bytes);
    try std.testing.expectEqual(@as(usize, 2), bag.get("tags").?.values.items.len);
    try std.testing.expectEqualSlices(u8, "a", bag.get("tags").?.values.items[0].string);
    try std.testing.expectEqualSlices(u8, "b", bag.get("tags").?.values.items[1].string);

    const count = bag.get("counts").?.values.items[0].map_entry;
    try std.testing.expectEqualSlices(u8, "red", count.key.string);
    try std.testing.expectEqual(@as(i32, 3), count.value.int32);

    try std.testing.expectEqualSlices(u8, "kid", bag.get("child").?.values.items[0].message.get("label").?.values.items[0].string);
    try std.testing.expectEqual(@as(i32, 1), bag.get("kind").?.values.items[0].enumeration);

    const rendered = try stringifyAlloc(allocator, &file, &bag, .{});
    defer allocator.free(rendered);
    try std.testing.expectEqualSlices(u8, "{\"id\":7,\"big\":\"9007199254740993\",\"raw\":\"aGk=\",\"tags\":[\"a\",\"b\"],\"counts\":{\"red\":3},\"child\":{\"label\":\"kid\"},\"kind\":\"ADMIN\"}", rendered);
}

test "json parse ignores null fields" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\message Nulls { int32 id = 1; repeated string tags = 2; map<string, int32> counts = 3; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("Nulls").?;

    var msg = try parseAlloc(allocator, &file, desc, "{\"id\":null,\"tags\":null,\"counts\":null}", .{});
    defer msg.deinit();
    try std.testing.expect(msg.get("id") == null);
    try std.testing.expect(msg.get("tags") == null);
    try std.testing.expect(msg.get("counts") == null);
}

test "json uses default lowerCamelCase field names" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\message Names { int32 user_id = 1; string display_name = 2; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("Names").?;

    var msg = dynamic.DynamicMessage.init(allocator, desc);
    defer msg.deinit();
    try msg.add(desc.findField("user_id").?, .{ .int32 = 7 });
    try msg.add(desc.findField("display_name").?, .{ .string = try allocator.dupe(u8, "Zig") });
    const rendered = try stringifyAlloc(allocator, &file, &msg, .{ .preserve_proto_field_names = false });
    defer allocator.free(rendered);
    try std.testing.expectEqualSlices(u8, "{\"userId\":7,\"displayName\":\"Zig\"}", rendered);

    var parsed = try parseAlloc(allocator, &file, desc, "{\"userId\":8,\"displayName\":\"Trae\"}", .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(i32, 8), parsed.get("user_id").?.values.items[0].int32);
    try std.testing.expectEqualSlices(u8, "Trae", parsed.get("display_name").?.values.items[0].string);
}

test "json parses bytes from base64 variants" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\message Bytes { bytes raw = 1; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("Bytes").?;

    var standard = try parseAlloc(allocator, &file, desc, "{\"raw\":\"++8=\"}", .{});
    defer standard.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0xfb, 0xef }, standard.get("raw").?.values.items[0].bytes);

    var url_safe_no_pad = try parseAlloc(allocator, &file, desc, "{\"raw\":\"--8\"}", .{});
    defer url_safe_no_pad.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0xfb, 0xef }, url_safe_no_pad.get("raw").?.values.items[0].bytes);
}
