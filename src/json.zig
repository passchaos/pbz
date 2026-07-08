const std = @import("std");
const schema = @import("schema.zig");
const dynamic = @import("dynamic.zig");
const wkt = @import("wkt.zig");

pub const Error = std.Io.Writer.Error || std.mem.Allocator.Error || error{ TypeMismatch, TimestampOutOfRange, DurationOutOfRange, InvalidNanos, DurationSignMismatch };

pub const Options = struct {
    enum_as_name: bool = true,
    preserve_proto_field_names: bool = false,
    ignore_unknown_fields: bool = false,
    always_print_primitive_fields: bool = false,
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
            if (try parseKnownMessage(allocator, file, descriptor, name, json_value)) |known| break :blk .{ .message = known };
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
            return .{ .enumeration = std.fmt.parseInt(i32, value, 10) catch return error.InvalidEnumValue };
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
    if (options.always_print_primitive_fields) {
        for (message.descriptor.fields.items) |*field| {
            if (message.getByNumber(field.number) != null) continue;
            if (!shouldPrintAbsentField(field)) continue;
            if (!first) try writer.writeAll(",");
            first = false;
            try writeFieldName(field, options, writer);
            try writer.writeAll(":");
            try writeAbsentFieldDefault(file, field, options, writer);
        }
    }
    try writer.writeAll("}");
}

fn shouldPrintAbsentField(field: *const schema.FieldDescriptor) bool {
    if (field.oneof_name != null) return false;
    return switch (field.kind) {
        .scalar, .enumeration, .map => true,
        else => field.cardinality == .repeated,
    };
}

fn writeAbsentFieldDefault(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, options: Options, writer: *std.Io.Writer) Error!void {
    if (field.kind == .map or field.cardinality == .repeated) return writer.writeAll(if (field.kind == .map) "{}" else "[]");
    switch (field.kind) {
        .scalar => |scalar| try writeDefaultScalar(scalar, field.default_value, writer),
        .enumeration => |name| {
            const number: i32 = if (field.default_value) |value| switch (value) {
                .integer => |v| @intCast(v),
                else => 0,
            } else 0;
            try writeEnum(file, name, .{ .enumeration = number }, options, writer);
        },
        else => try writer.writeAll("null"),
    }
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
        .message => |name| switch (value) {
            .message => |message| if (try writeKnownMessage(name, message, writer)) {} else try writeMessage(file, message, options, writer),
            else => return error.TypeMismatch,
        },
        .group => switch (value) {
            .group => |message| try writeMessage(file, message, options, writer),
            else => return error.TypeMismatch,
        },
        .map => return error.TypeMismatch,
    }
}

fn writeStructMessage(message: *const dynamic.DynamicMessage, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("{");
    if (message.get("fields")) |fields| {
        for (fields.values.items, 0..) |value, index| {
            const entry = switch (value) {
                .map_entry => |entry| entry,
                else => return error.TypeMismatch,
            };
            if (entry.key != .string or entry.value != .message) return error.TypeMismatch;
            if (index != 0) try writer.writeAll(",");
            try writeJsonString(entry.key.string, writer);
            try writer.writeAll(":");
            try writeValueMessage(entry.value.message, writer);
        }
    }
    try writer.writeAll("}");
}

fn writeListValueMessage(message: *const dynamic.DynamicMessage, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("[");
    if (message.get("values")) |values| {
        for (values.values.items, 0..) |value, index| {
            if (value != .message) return error.TypeMismatch;
            if (index != 0) try writer.writeAll(",");
            try writeValueMessage(value.message, writer);
        }
    }
    try writer.writeAll("]");
}

fn writeValueMessage(message: *const dynamic.DynamicMessage, writer: *std.Io.Writer) Error!void {
    if (message.get("null_value")) |_| return try writer.writeAll("null");
    if (message.get("number_value")) |field| {
        if (field.values.items.len == 0 or field.values.items[0] != .double) return error.TypeMismatch;
        return try writeFloat(field.values.items[0].double, writer);
    }
    if (message.get("string_value")) |field| {
        if (field.values.items.len == 0 or field.values.items[0] != .string) return error.TypeMismatch;
        return try writeJsonString(field.values.items[0].string, writer);
    }
    if (message.get("bool_value")) |field| {
        if (field.values.items.len == 0 or field.values.items[0] != .boolean) return error.TypeMismatch;
        return try writer.writeAll(if (field.values.items[0].boolean) "true" else "false");
    }
    if (message.get("struct_value")) |field| {
        if (field.values.items.len == 0 or field.values.items[0] != .message) return error.TypeMismatch;
        return try writeStructMessage(field.values.items[0].message, writer);
    }
    if (message.get("list_value")) |field| {
        if (field.values.items.len == 0 or field.values.items[0] != .message) return error.TypeMismatch;
        return try writeListValueMessage(field.values.items[0].message, writer);
    }
    try writer.writeAll("null");
}

fn parseStructMessage(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, descriptor: *const schema.MessageDescriptor, json_value: std.json.Value) anyerror!*dynamic.DynamicMessage {
    const object = switch (json_value) {
        .object => |object| object,
        else => return error.TypeMismatch,
    };
    const message = try allocator.create(dynamic.DynamicMessage);
    message.* = dynamic.DynamicMessage.init(allocator, descriptor);
    errdefer {
        message.deinit();
        allocator.destroy(message);
    }
    const field = descriptor.findField("fields") orelse return error.TypeMismatch;
    const map_type = switch (field.kind) {
        .map => |map_type| map_type,
        else => return error.TypeMismatch,
    };
    const value_desc = switch (map_type.value.*) {
        .message => |name| resolveMessageDescriptor(file, descriptor, name) orelse return error.TypeMismatch,
        else => return error.TypeMismatch,
    };
    var it = object.iterator();
    while (it.next()) |entry| {
        const value_message = try parseValueMessage(allocator, file, value_desc, entry.value_ptr.*);
        const map_entry = try allocator.create(dynamic.MapEntry);
        map_entry.* = .{
            .key = .{ .string = try allocator.dupe(u8, entry.key_ptr.*) },
            .value = .{ .message = value_message },
        };
        try message.add(field, .{ .map_entry = map_entry });
    }
    return message;
}

fn parseListValueMessage(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, descriptor: *const schema.MessageDescriptor, json_value: std.json.Value) anyerror!*dynamic.DynamicMessage {
    const array = switch (json_value) {
        .array => |array| array,
        else => return error.TypeMismatch,
    };
    const message = try allocator.create(dynamic.DynamicMessage);
    message.* = dynamic.DynamicMessage.init(allocator, descriptor);
    errdefer {
        message.deinit();
        allocator.destroy(message);
    }
    const field = descriptor.findField("values") orelse return error.TypeMismatch;
    const value_desc = switch (field.kind) {
        .message => |name| resolveMessageDescriptor(file, descriptor, name) orelse return error.TypeMismatch,
        else => return error.TypeMismatch,
    };
    for (array.items) |item| try message.add(field, .{ .message = try parseValueMessage(allocator, file, value_desc, item) });
    return message;
}

fn parseValueMessage(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, descriptor: *const schema.MessageDescriptor, json_value: std.json.Value) anyerror!*dynamic.DynamicMessage {
    const message = try allocator.create(dynamic.DynamicMessage);
    message.* = dynamic.DynamicMessage.init(allocator, descriptor);
    errdefer {
        message.deinit();
        allocator.destroy(message);
    }
    switch (json_value) {
        .null => try message.add(descriptor.findField("null_value") orelse return error.TypeMismatch, .{ .enumeration = 0 }),
        .bool => |value| try message.add(descriptor.findField("bool_value") orelse return error.TypeMismatch, .{ .boolean = value }),
        .integer => |value| try message.add(descriptor.findField("number_value") orelse return error.TypeMismatch, .{ .double = @floatFromInt(value) }),
        .float => |value| try message.add(descriptor.findField("number_value") orelse return error.TypeMismatch, .{ .double = value }),
        .number_string => |value| try message.add(descriptor.findField("number_value") orelse return error.TypeMismatch, .{ .double = try std.fmt.parseFloat(f64, value) }),
        .string => |value| try message.add(descriptor.findField("string_value") orelse return error.TypeMismatch, .{ .string = try allocator.dupe(u8, value) }),
        .object => {
            const struct_desc = resolveMessageDescriptor(file, descriptor, "Struct") orelse return error.TypeMismatch;
            try message.add(descriptor.findField("struct_value") orelse return error.TypeMismatch, .{ .message = try parseStructMessage(allocator, file, struct_desc, json_value) });
        },
        .array => {
            const list_desc = resolveMessageDescriptor(file, descriptor, "ListValue") orelse return error.TypeMismatch;
            try message.add(descriptor.findField("list_value") orelse return error.TypeMismatch, .{ .message = try parseListValueMessage(allocator, file, list_desc, json_value) });
        },
    }
    return message;
}

fn writeWrapperValue(kind: schema.FieldKind, value: dynamic.Value, writer: *std.Io.Writer) Error!void {
    return switch (kind) {
        .scalar => |scalar| try writeScalar(scalar, value, writer),
        else => error.TypeMismatch,
    };
}

fn parseWrapperValue(allocator: std.mem.Allocator, kind: schema.FieldKind, json_value: std.json.Value) !dynamic.Value {
    return switch (kind) {
        .scalar => |scalar| try parseScalar(allocator, scalar, json_value),
        else => error.TypeMismatch,
    };
}

fn writeKnownMessage(name: []const u8, message: *const dynamic.DynamicMessage, writer: *std.Io.Writer) !bool {
    if (typeNameEquals(name, "google.protobuf.Timestamp")) {
        const ts = wkt.Timestamp{ .seconds = readInt64Field(message, "seconds"), .nanos = readInt32Field(message, "nanos") };
        try ts.jsonStringify(writer);
        return true;
    }
    if (typeNameEquals(name, "google.protobuf.Duration")) {
        const duration = wkt.Duration{ .seconds = readInt64Field(message, "seconds"), .nanos = readInt32Field(message, "nanos") };
        try duration.jsonStringify(writer);
        return true;
    }
    if (typeNameEquals(name, "google.protobuf.Any")) {
        const any = wkt.Any{ .type_url = readStringField(message, "type_url"), .value = readBytesField(message, "value") };
        try any.jsonStringify(writer);
        return true;
    }
    if (typeNameEquals(name, "google.protobuf.FieldMask")) {
        try writeFieldMaskMessage(message, writer);
        return true;
    }
    if (typeNameEquals(name, "google.protobuf.Empty")) {
        try wkt.Empty.jsonStringify(writer);
        return true;
    }
    if (typeNameEquals(name, "google.protobuf.Struct")) {
        try writeStructMessage(message, writer);
        return true;
    }
    if (typeNameEquals(name, "google.protobuf.Value")) {
        try writeValueMessage(message, writer);
        return true;
    }
    if (typeNameEquals(name, "google.protobuf.ListValue")) {
        try writeListValueMessage(message, writer);
        return true;
    }
    if (wrapperKind(name)) |kind| {
        if (message.get("value")) |field| {
            if (field.values.items.len != 0) try writeWrapperValue(kind, field.values.items[field.values.items.len - 1], writer) else try writer.writeAll("null");
        } else try writer.writeAll("null");
        return true;
    }
    return false;
}

fn parseKnownMessage(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, descriptor: *const schema.MessageDescriptor, name: []const u8, json_value: std.json.Value) !?*dynamic.DynamicMessage {
    if (typeNameEquals(name, "google.protobuf.Struct")) return try parseStructMessage(allocator, file, descriptor, json_value);
    if (typeNameEquals(name, "google.protobuf.Value")) return try parseValueMessage(allocator, file, descriptor, json_value);
    if (typeNameEquals(name, "google.protobuf.ListValue")) return try parseListValueMessage(allocator, file, descriptor, json_value);
    if (wrapperKind(name)) |kind| {
        if (json_value == .null) return try emptyKnownMessage(allocator, descriptor);
        const message = try allocator.create(dynamic.DynamicMessage);
        message.* = dynamic.DynamicMessage.init(allocator, descriptor);
        errdefer {
            message.deinit();
            allocator.destroy(message);
        }
        var value = try parseWrapperValue(allocator, kind, json_value);
        message.add(descriptor.findField("value") orelse return error.TypeMismatch, value) catch |err| {
            dynamic.deinitValue(&value, allocator);
            return err;
        };
        return message;
    }
    if (typeNameEquals(name, "google.protobuf.Empty")) {
        if (json_value != .object) return error.TypeMismatch;
        return try emptyKnownMessage(allocator, descriptor);
    }
    if (typeNameEquals(name, "google.protobuf.Any")) {
        return try parseAnyMessage(allocator, descriptor, json_value);
    }
    const text = switch (json_value) {
        .string => |value| value,
        else => return null,
    };
    const message = try allocator.create(dynamic.DynamicMessage);
    message.* = dynamic.DynamicMessage.init(allocator, descriptor);
    errdefer {
        message.deinit();
        allocator.destroy(message);
    }
    if (typeNameEquals(name, "google.protobuf.Timestamp")) {
        const ts = try wkt.Timestamp.jsonParse(text);
        try addKnownTimeFields(message, ts.seconds, ts.nanos);
        return message;
    }
    if (typeNameEquals(name, "google.protobuf.Duration")) {
        const duration = try wkt.Duration.jsonParse(text);
        try addKnownTimeFields(message, duration.seconds, duration.nanos);
        return message;
    }
    if (typeNameEquals(name, "google.protobuf.Empty")) return message;
    if (typeNameEquals(name, "google.protobuf.FieldMask")) {
        const paths = try wkt.FieldMask.jsonParse(allocator, text);
        defer {
            for (paths) |path| allocator.free(path);
            allocator.free(paths);
        }
        const field = descriptor.findField("paths") orelse return error.TypeMismatch;
        for (paths) |path| try message.add(field, .{ .string = try allocator.dupe(u8, path) });
        return message;
    }
    message.deinit();
    allocator.destroy(message);
    return null;
}

fn parseAnyMessage(allocator: std.mem.Allocator, descriptor: *const schema.MessageDescriptor, json_value: std.json.Value) !*dynamic.DynamicMessage {
    const object = switch (json_value) {
        .object => |object| object,
        else => return error.TypeMismatch,
    };
    const message = try allocator.create(dynamic.DynamicMessage);
    message.* = dynamic.DynamicMessage.init(allocator, descriptor);
    errdefer {
        message.deinit();
        allocator.destroy(message);
    }
    const type_field = descriptor.findField("type_url") orelse return error.TypeMismatch;
    const value_field = descriptor.findField("value") orelse return error.TypeMismatch;
    if (object.get("@type")) |type_json| {
        const type_url = switch (type_json) {
            .string => |value| value,
            else => return error.TypeMismatch,
        };
        try message.add(type_field, .{ .string = try allocator.dupe(u8, type_url) });
    }
    if (object.get("value")) |value_json| {
        const encoded = switch (value_json) {
            .string => |value| value,
            else => return error.TypeMismatch,
        };
        try message.add(value_field, .{ .bytes = try decodeBase64(allocator, encoded) });
    }
    return message;
}

fn emptyKnownMessage(allocator: std.mem.Allocator, descriptor: *const schema.MessageDescriptor) !*dynamic.DynamicMessage {
    const message = try allocator.create(dynamic.DynamicMessage);
    message.* = dynamic.DynamicMessage.init(allocator, descriptor);
    return message;
}

fn wrapperKind(name: []const u8) ?schema.FieldKind {
    if (typeNameEquals(name, "google.protobuf.DoubleValue")) return .{ .scalar = .double };
    if (typeNameEquals(name, "google.protobuf.FloatValue")) return .{ .scalar = .float };
    if (typeNameEquals(name, "google.protobuf.Int64Value")) return .{ .scalar = .int64 };
    if (typeNameEquals(name, "google.protobuf.UInt64Value")) return .{ .scalar = .uint64 };
    if (typeNameEquals(name, "google.protobuf.Int32Value")) return .{ .scalar = .int32 };
    if (typeNameEquals(name, "google.protobuf.UInt32Value")) return .{ .scalar = .uint32 };
    if (typeNameEquals(name, "google.protobuf.BoolValue")) return .{ .scalar = .bool };
    if (typeNameEquals(name, "google.protobuf.StringValue")) return .{ .scalar = .string };
    if (typeNameEquals(name, "google.protobuf.BytesValue")) return .{ .scalar = .bytes };
    return null;
}

fn addKnownTimeFields(message: *dynamic.DynamicMessage, seconds: i64, nanos: i32) !void {
    if (seconds != 0) try message.add(message.descriptor.findField("seconds") orelse return error.TypeMismatch, .{ .int64 = seconds });
    if (nanos != 0) try message.add(message.descriptor.findField("nanos") orelse return error.TypeMismatch, .{ .int32 = nanos });
}

fn writeFieldMaskMessage(message: *const dynamic.DynamicMessage, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("\"");
    if (message.get("paths")) |field| {
        for (field.values.items, 0..) |value, index| {
            if (value != .string) return error.TypeMismatch;
            if (index != 0) try writer.writeAll(",");
            try writeLowerCamel(value.string, writer);
        }
    }
    try writer.writeAll("\"");
}

fn readStringField(message: *const dynamic.DynamicMessage, name: []const u8) []const u8 {
    if (message.get(name)) |field| if (field.values.items.len != 0 and field.values.items[0] == .string) return field.values.items[0].string;
    return "";
}

fn readBytesField(message: *const dynamic.DynamicMessage, name: []const u8) []const u8 {
    if (message.get(name)) |field| if (field.values.items.len != 0 and field.values.items[0] == .bytes) return field.values.items[0].bytes;
    return "";
}

fn readInt64Field(message: *const dynamic.DynamicMessage, name: []const u8) i64 {
    if (message.get(name)) |field| if (field.values.items.len != 0 and field.values.items[0] == .int64) return field.values.items[0].int64;
    return 0;
}

fn readInt32Field(message: *const dynamic.DynamicMessage, name: []const u8) i32 {
    if (message.get(name)) |field| if (field.values.items.len != 0 and field.values.items[0] == .int32) return field.values.items[0].int32;
    return 0;
}

fn typeNameEquals(name: []const u8, expected: []const u8) bool {
    const normalized = if (std.mem.startsWith(u8, name, ".")) name[1..] else name;
    return std.mem.eql(u8, normalized, expected) or std.mem.endsWith(u8, normalized, expected);
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

fn writeDefaultScalar(scalar: schema.ScalarType, default_value: ?schema.OptionValue, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .double, .float => try writeFloat(defaultFloat(default_value), writer),
        .int32, .sint32, .sfixed32 => try writer.print("{d}", .{defaultInt(i32, default_value)}),
        .int64, .sint64, .sfixed64 => try writeJsonStringFmt(writer, "{d}", .{defaultInt(i64, default_value)}),
        .uint32, .fixed32 => try writer.print("{d}", .{defaultInt(u32, default_value)}),
        .uint64, .fixed64 => try writeJsonStringFmt(writer, "{d}", .{defaultInt(u64, default_value)}),
        .bool => try writer.writeAll(if (defaultBool(default_value)) "true" else "false"),
        .string => try writeJsonString(defaultText(default_value), writer),
        .bytes => try writeBase64String(defaultText(default_value), writer),
    }
}

fn defaultText(default_value: ?schema.OptionValue) []const u8 {
    const value = default_value orelse return "";
    return switch (value) {
        .string, .identifier => |text| text,
        else => "",
    };
}

fn defaultBool(default_value: ?schema.OptionValue) bool {
    const value = default_value orelse return false;
    return schema.optionAsBool(value) orelse false;
}

fn defaultInt(comptime T: type, default_value: ?schema.OptionValue) T {
    const value = default_value orelse return 0;
    return switch (value) {
        .integer => |v| if (v >= std.math.minInt(T) and v <= std.math.maxInt(T)) @intCast(v) else 0,
        .identifier, .string => |text| std.fmt.parseInt(T, text, 10) catch 0,
        else => 0,
    };
}

fn defaultFloat(default_value: ?schema.OptionValue) f64 {
    const value = default_value orelse return 0;
    return switch (value) {
        .float => |v| v,
        .integer => |v| @floatFromInt(v),
        .identifier, .string => |text| std.fmt.parseFloat(f64, text) catch 0,
        else => 0,
    };
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

test "json parses and prints enum numbers and unknown enum values" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message M { Kind kind = 1; repeated Kind roles = 2; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("M").?;

    var numeric = try parseAlloc(allocator, &file, desc, "{\"kind\":123,\"roles\":[\"1\",\"123\"]}", .{});
    defer numeric.deinit();
    try std.testing.expectEqual(@as(i32, 123), numeric.get("kind").?.values.items[0].enumeration);
    try std.testing.expectEqual(@as(i32, 1), numeric.get("roles").?.values.items[0].enumeration);
    try std.testing.expectEqual(@as(i32, 123), numeric.get("roles").?.values.items[1].enumeration);

    const rendered_unknown = try stringifyAlloc(allocator, &file, &numeric, .{});
    defer allocator.free(rendered_unknown);
    try std.testing.expectEqualSlices(u8, "{\"kind\":123,\"roles\":[\"ADMIN\",123]}", rendered_unknown);

    const rendered_numbers = try stringifyAlloc(allocator, &file, &numeric, .{ .enum_as_name = false });
    defer allocator.free(rendered_numbers);
    try std.testing.expectEqualSlices(u8, "{\"kind\":123,\"roles\":[1,123]}", rendered_numbers);
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
    const rendered = try stringifyAlloc(allocator, &file, &msg, .{});
    defer allocator.free(rendered);
    try std.testing.expectEqualSlices(u8, "{\"userId\":7,\"displayName\":\"Zig\"}", rendered);

    const preserved = try stringifyAlloc(allocator, &file, &msg, .{ .preserve_proto_field_names = true });
    defer allocator.free(preserved);
    try std.testing.expectEqualSlices(u8, "{\"user_id\":7,\"display_name\":\"Zig\"}", preserved);

    var parsed = try parseAlloc(allocator, &file, desc, "{\"userId\":8,\"displayName\":\"Trae\"}", .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(i32, 8), parsed.get("user_id").?.values.items[0].int32);
    try std.testing.expectEqualSlices(u8, "Trae", parsed.get("display_name").?.values.items[0].string);
}

test "json stringify can always print absent primitive repeated and map fields" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto2";
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message Defaults {
        \\  optional int32 count = 1 [default = 42];
        \\  optional string name = 2 [default = "anon"];
        \\  optional bool enabled = 3 [default = true];
        \\  optional Kind kind = 4 [default = ADMIN];
        \\  repeated string tags = 5;
        \\  map<string, int32> counts = 6;
        \\  optional bytes raw = 7 [default = "hi"];
        \\  optional int64 big = 8 [default = 9007199254740993];
        \\}
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("Defaults").?;

    var msg = dynamic.DynamicMessage.init(allocator, desc);
    defer msg.deinit();
    const rendered = try stringifyAlloc(allocator, &file, &msg, .{ .always_print_primitive_fields = true });
    defer allocator.free(rendered);
    try std.testing.expectEqualSlices(u8, "{\"count\":42,\"name\":\"anon\",\"enabled\":true,\"kind\":\"ADMIN\",\"tags\":[],\"counts\":{},\"raw\":\"aGk=\",\"big\":\"9007199254740993\"}", rendered);
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

test "json maps Timestamp and Duration messages as well-known strings" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\package demo;
        \\message Timestamp { int64 seconds = 1; int32 nanos = 2; }
        \\message Duration { int64 seconds = 1; int32 nanos = 2; }
        \\message Event { google.protobuf.Timestamp at = 1; google.protobuf.Duration span = 2; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const event_desc = file.findMessage("Event").?;
    const ts_desc = file.findMessage("Timestamp").?;
    const dur_desc = file.findMessage("Duration").?;

    var event = dynamic.DynamicMessage.init(allocator, event_desc);
    defer event.deinit();
    const ts = try allocator.create(dynamic.DynamicMessage);
    ts.* = dynamic.DynamicMessage.init(allocator, ts_desc);
    try ts.add(ts_desc.findField("seconds").?, .{ .int64 = 1_577_836_800 });
    try ts.add(ts_desc.findField("nanos").?, .{ .int32 = 123_000_000 });
    try event.add(event_desc.findField("at").?, .{ .message = ts });
    const dur = try allocator.create(dynamic.DynamicMessage);
    dur.* = dynamic.DynamicMessage.init(allocator, dur_desc);
    try dur.add(dur_desc.findField("seconds").?, .{ .int64 = -3 });
    try dur.add(dur_desc.findField("nanos").?, .{ .int32 = -250_000_000 });
    try event.add(event_desc.findField("span").?, .{ .message = dur });

    const rendered = try stringifyAlloc(allocator, &file, &event, .{});
    defer allocator.free(rendered);
    try std.testing.expectEqualSlices(u8, "{\"at\":\"2020-01-01T00:00:00.123Z\",\"span\":\"-3.25s\"}", rendered);

    var parsed = try parseAlloc(allocator, &file, event_desc, rendered, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(i64, 1_577_836_800), parsed.get("at").?.values.items[0].message.get("seconds").?.values.items[0].int64);
    try std.testing.expectEqual(@as(i32, 123_000_000), parsed.get("at").?.values.items[0].message.get("nanos").?.values.items[0].int32);
    try std.testing.expectEqual(@as(i64, -3), parsed.get("span").?.values.items[0].message.get("seconds").?.values.items[0].int64);
    try std.testing.expectEqual(@as(i32, -250_000_000), parsed.get("span").?.values.items[0].message.get("nanos").?.values.items[0].int32);
}

test "json maps wrapper messages as their value field" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\package google.protobuf;
        \\message StringValue { string value = 1; }
        \\message Int32Value { int32 value = 1; }
        \\message Event { .google.protobuf.StringValue name = 1; .google.protobuf.Int32Value count = 2; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const event_desc = file.findMessage("Event").?;
    const string_desc = file.findMessage("StringValue").?;
    const int_desc = file.findMessage("Int32Value").?;

    var event = dynamic.DynamicMessage.init(allocator, event_desc);
    defer event.deinit();
    const name = try allocator.create(dynamic.DynamicMessage);
    name.* = dynamic.DynamicMessage.init(allocator, string_desc);
    try name.add(string_desc.findField("value").?, .{ .string = try allocator.dupe(u8, "zig") });
    try event.add(event_desc.findField("name").?, .{ .message = name });
    const count = try allocator.create(dynamic.DynamicMessage);
    count.* = dynamic.DynamicMessage.init(allocator, int_desc);
    try count.add(int_desc.findField("value").?, .{ .int32 = 42 });
    try event.add(event_desc.findField("count").?, .{ .message = count });

    const rendered = try stringifyAlloc(allocator, &file, &event, .{});
    defer allocator.free(rendered);
    try std.testing.expectEqualSlices(u8, "{\"name\":\"zig\",\"count\":42}", rendered);

    var parsed = try parseAlloc(allocator, &file, event_desc, rendered, .{});
    defer parsed.deinit();
    try std.testing.expectEqualSlices(u8, "zig", parsed.get("name").?.values.items[0].message.get("value").?.values.items[0].string);
    try std.testing.expectEqual(@as(i32, 42), parsed.get("count").?.values.items[0].message.get("value").?.values.items[0].int32);
}

test "json maps Any message with type and base64 value" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\package google.protobuf;
        \\message Any { string type_url = 1; bytes value = 2; }
        \\message Holder { .google.protobuf.Any any = 1; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const holder_desc = file.findMessage("Holder").?;
    const any_desc = file.findMessage("Any").?;
    var holder = dynamic.DynamicMessage.init(allocator, holder_desc);
    defer holder.deinit();
    const any_msg = try allocator.create(dynamic.DynamicMessage);
    any_msg.* = dynamic.DynamicMessage.init(allocator, any_desc);
    try any_msg.add(any_desc.findField("type_url").?, .{ .string = try allocator.dupe(u8, "type.googleapis.com/demo.Msg") });
    try any_msg.add(any_desc.findField("value").?, .{ .bytes = try allocator.dupe(u8, "abc") });
    try holder.add(holder_desc.findField("any").?, .{ .message = any_msg });

    const rendered = try stringifyAlloc(allocator, &file, &holder, .{});
    defer allocator.free(rendered);
    try std.testing.expectEqualSlices(u8, "{\"any\":{\"@type\":\"type.googleapis.com/demo.Msg\",\"value\":\"YWJj\"}}", rendered);
}

test "json maps FieldMask message as comma-separated string" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\package google.protobuf;
        \\message FieldMask { repeated string paths = 1; }
        \\message Holder { .google.protobuf.FieldMask mask = 1; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const holder_desc = file.findMessage("Holder").?;
    const mask_desc = file.findMessage("FieldMask").?;

    var holder = dynamic.DynamicMessage.init(allocator, holder_desc);
    defer holder.deinit();
    const mask = try allocator.create(dynamic.DynamicMessage);
    mask.* = dynamic.DynamicMessage.init(allocator, mask_desc);
    try mask.add(mask_desc.findField("paths").?, .{ .string = try allocator.dupe(u8, "foo_bar") });
    try mask.add(mask_desc.findField("paths").?, .{ .string = try allocator.dupe(u8, "baz.qux_value") });
    try holder.add(holder_desc.findField("mask").?, .{ .message = mask });

    const rendered = try stringifyAlloc(allocator, &file, &holder, .{});
    defer allocator.free(rendered);
    try std.testing.expectEqualSlices(u8, "{\"mask\":\"fooBar,baz.quxValue\"}", rendered);

    var parsed = try parseAlloc(allocator, &file, holder_desc, rendered, .{});
    defer parsed.deinit();
    const parsed_mask = parsed.get("mask").?.values.items[0].message;
    try std.testing.expectEqualSlices(u8, "foo_bar", parsed_mask.get("paths").?.values.items[0].string);
    try std.testing.expectEqualSlices(u8, "baz.qux_value", parsed_mask.get("paths").?.values.items[1].string);
}

test "json maps Empty message as empty object" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\package google.protobuf;
        \\message Empty {}
        \\message Holder { .google.protobuf.Empty empty = 1; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const holder_desc = file.findMessage("Holder").?;
    const empty_desc = file.findMessage("Empty").?;
    var holder = dynamic.DynamicMessage.init(allocator, holder_desc);
    defer holder.deinit();
    const empty = try allocator.create(dynamic.DynamicMessage);
    empty.* = dynamic.DynamicMessage.init(allocator, empty_desc);
    try holder.add(holder_desc.findField("empty").?, .{ .message = empty });
    const rendered = try stringifyAlloc(allocator, &file, &holder, .{});
    defer allocator.free(rendered);
    try std.testing.expectEqualSlices(u8, "{\"empty\":{}}", rendered);
    var parsed = try parseAlloc(allocator, &file, holder_desc, rendered, .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.get("empty") != null);
}

test "json parses Any message with type and base64 value" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\package google.protobuf;
        \\message Any { string type_url = 1; bytes value = 2; }
        \\message Holder { .google.protobuf.Any any = 1; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const holder_desc = file.findMessage("Holder").?;
    var parsed = try parseAlloc(allocator, &file, holder_desc, "{\"any\":{\"@type\":\"type.googleapis.com/demo.Msg\",\"value\":\"YWJj\"}}", .{});
    defer parsed.deinit();
    const any_msg = parsed.get("any").?.values.items[0].message;
    try std.testing.expectEqualSlices(u8, "type.googleapis.com/demo.Msg", any_msg.get("type_url").?.values.items[0].string);
    try std.testing.expectEqualSlices(u8, "abc", any_msg.get("value").?.values.items[0].bytes);
}

test "json maps Struct Value and ListValue messages" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\package google.protobuf;
        \\enum NullValue { NULL_VALUE = 0; }
        \\message Struct { map<string, Value> fields = 1; }
        \\message ListValue { repeated Value values = 1; }
        \\message Value {
        \\  oneof kind {
        \\    NullValue null_value = 1;
        \\    double number_value = 2;
        \\    string string_value = 3;
        \\    bool bool_value = 4;
        \\    Struct struct_value = 5;
        \\    ListValue list_value = 6;
        \\  }
        \\}
        \\message Holder { .google.protobuf.Struct data = 1; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const holder_desc = file.findMessage("Holder").?;
    const struct_desc = file.findMessage("Struct").?;
    const value_desc = file.findMessage("Value").?;
    const list_desc = file.findMessage("ListValue").?;

    var holder = dynamic.DynamicMessage.init(allocator, holder_desc);
    defer holder.deinit();
    const st = try allocator.create(dynamic.DynamicMessage);
    st.* = dynamic.DynamicMessage.init(allocator, struct_desc);
    const fields = struct_desc.findField("fields").?;

    const name_value = try allocator.create(dynamic.DynamicMessage);
    name_value.* = dynamic.DynamicMessage.init(allocator, value_desc);
    try name_value.add(value_desc.findField("string_value").?, .{ .string = try allocator.dupe(u8, "zig") });
    const name_entry = try allocator.create(dynamic.MapEntry);
    name_entry.* = .{ .key = .{ .string = try allocator.dupe(u8, "name") }, .value = .{ .message = name_value } };
    try st.add(fields, .{ .map_entry = name_entry });

    const list = try allocator.create(dynamic.DynamicMessage);
    list.* = dynamic.DynamicMessage.init(allocator, list_desc);
    const list_item = try allocator.create(dynamic.DynamicMessage);
    list_item.* = dynamic.DynamicMessage.init(allocator, value_desc);
    try list_item.add(value_desc.findField("number_value").?, .{ .double = 1.5 });
    try list.add(list_desc.findField("values").?, .{ .message = list_item });
    const list_value = try allocator.create(dynamic.DynamicMessage);
    list_value.* = dynamic.DynamicMessage.init(allocator, value_desc);
    try list_value.add(value_desc.findField("list_value").?, .{ .message = list });
    const list_entry = try allocator.create(dynamic.MapEntry);
    list_entry.* = .{ .key = .{ .string = try allocator.dupe(u8, "items") }, .value = .{ .message = list_value } };
    try st.add(fields, .{ .map_entry = list_entry });

    try holder.add(holder_desc.findField("data").?, .{ .message = st });
    const rendered = try stringifyAlloc(allocator, &file, &holder, .{});
    defer allocator.free(rendered);
    try std.testing.expectEqualSlices(u8, "{\"data\":{\"name\":\"zig\",\"items\":[1.5]}}", rendered);

    var parsed = try parseAlloc(allocator, &file, holder_desc, rendered, .{});
    defer parsed.deinit();
    const parsed_struct = parsed.get("data").?.values.items[0].message;
    try std.testing.expectEqual(@as(usize, 2), parsed_struct.get("fields").?.values.items.len);
}
