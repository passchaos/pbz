const std = @import("std");
const wire = @import("wire.zig");
const schema = @import("schema.zig");
const dynamic = @import("dynamic.zig");
const wkt = @import("wkt.zig");
const registry_mod = @import("registry.zig");

pub const Error = std.Io.Writer.Error || dynamic.DecodeError || error{ TimestampOutOfRange, DurationOutOfRange, InvalidNanos, DurationSignMismatch, InvalidFieldMask, InvalidNumber };

pub const Options = struct {
    enum_as_name: bool = true,
    preserve_proto_field_names: bool = false,
    ignore_unknown_fields: bool = false,
    always_print_primitive_fields: bool = false,
    validate_any_payloads: bool = false,
};

/// Parse a protobuf JSON integer value with the same public compatibility
/// contract used by generated messages and WKT wrappers.
///
/// C++/Go protobuf accept unquoted numeric tokens such as `1.2345e4` for
/// integer fields when the represented value is integral and in range. Zig's
/// JSON parser can surface those tokens as either `.float` or `.number_string`
/// depending on parser options, while quoted strings are intentionally kept to
/// decimal integer spelling. Exporting this helper keeps generated code and
/// dynamic JSON parsing from drifting apart on that edge case.
pub fn intValue(comptime T: type, json_value: std.json.Value) !T {
    switch (json_value) {
        .integer => |value| {
            if (value < std.math.minInt(T) or value > std.math.maxInt(T)) return error.Overflow;
            return @intCast(value);
        },
        .float => |value| return try floatAsInt(T, value),
        .number_string => |value| return try intText(T, value),
        .string => |value| return try std.fmt.parseInt(T, value, 10),
        else => return error.TypeMismatch,
    }
}

fn intText(comptime T: type, value: []const u8) !T {
    return std.fmt.parseInt(T, value, 10) catch |int_err| switch (int_err) {
        error.InvalidCharacter => try floatAsInt(T, try std.fmt.parseFloat(f64, value)),
        error.Overflow => return error.Overflow,
    };
}

pub fn stringifyAlloc(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    message: *const dynamic.DynamicMessage,
    options: Options,
) Error![]u8 {
    return try stringifyAllocWithRegistry(allocator, file, null, message, options);
}

pub fn stringifyAllocWithRegistry(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    registry: ?*const registry_mod.Registry,
    message: *const dynamic.DynamicMessage,
    options: Options,
) Error![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    try stringifyWithRegistry(file, registry, message, options, &out.writer);
    return try out.toOwnedSlice();
}

pub fn stringify(
    file: *const schema.FileDescriptor,
    message: *const dynamic.DynamicMessage,
    options: Options,
    writer: *std.Io.Writer,
) Error!void {
    try stringifyWithRegistry(file, null, message, options, writer);
}

pub fn stringifyWithRegistry(
    file: *const schema.FileDescriptor,
    registry: ?*const registry_mod.Registry,
    message: *const dynamic.DynamicMessage,
    options: Options,
    writer: *std.Io.Writer,
) Error!void {
    try writeMessage(file, registry, message, options, writer);
}

pub fn parseAlloc(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    descriptor: *const schema.MessageDescriptor,
    bytes: []const u8,
    options: Options,
) anyerror!dynamic.DynamicMessage {
    return try parseAllocWithRegistry(allocator, file, null, descriptor, bytes, options);
}

pub fn parseAllocWithRegistry(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    registry: ?*const registry_mod.Registry,
    descriptor: *const schema.MessageDescriptor,
    bytes: []const u8,
    options: Options,
) anyerror!dynamic.DynamicMessage {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, bytes, .{ .duplicate_field_behavior = .use_last });
    defer parsed.deinit();

    var message = dynamic.DynamicMessage.init(allocator, descriptor);
    errdefer message.deinit();
    try fillMessageWithRegistry(allocator, file, registry, &message, parsed.value, options);
    return message;
}

pub fn parseInitializedAlloc(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    descriptor: *const schema.MessageDescriptor,
    bytes: []const u8,
    options: Options,
) anyerror!dynamic.DynamicMessage {
    return try parseInitializedAllocWithRegistry(allocator, file, null, descriptor, bytes, options);
}

pub fn parseInitializedAllocWithRegistry(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    registry: ?*const registry_mod.Registry,
    descriptor: *const schema.MessageDescriptor,
    bytes: []const u8,
    options: Options,
) anyerror!dynamic.DynamicMessage {
    var initialized_options = options;
    initialized_options.validate_any_payloads = true;
    var message = try parseAllocWithRegistry(allocator, file, registry, descriptor, bytes, initialized_options);
    errdefer message.deinit();
    try message.validateRequired();
    return message;
}

pub fn fillMessage(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    message: *dynamic.DynamicMessage,
    json_value: std.json.Value,
    options: Options,
) anyerror!void {
    try fillMessageWithRegistry(allocator, file, null, message, json_value, options);
}

pub fn fillMessageWithRegistry(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    registry: ?*const registry_mod.Registry,
    message: *dynamic.DynamicMessage,
    json_value: std.json.Value,
    options: Options,
) anyerror!void {
    const object = switch (json_value) {
        .object => |object| object,
        else => return error.TypeMismatch,
    };
    try fillMessageObject(allocator, file, registry, message, object, options, false);
}

fn fillMessageObject(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    registry: ?*const registry_mod.Registry,
    message: *dynamic.DynamicMessage,
    object: std.json.ObjectMap,
    options: Options,
    skip_type_field: bool,
) anyerror!void {
    var seen_fields: std.ArrayList(wire.FieldNumber) = .empty;
    defer seen_fields.deinit(allocator);
    var it = object.iterator();
    while (it.next()) |entry| {
        if (skip_type_field and std.mem.eql(u8, entry.key_ptr.*, "@type")) continue;
        const field = findJsonField(file, registry, message.descriptor, entry.key_ptr.*, options) orelse {
            if (options.ignore_unknown_fields) continue;
            return error.UnknownField;
        };
        if (entry.value_ptr.* == .null and jsonNullSkipsField(file, registry, message.descriptor, field)) continue;
        if (seenJsonField(seen_fields.items, field.number)) return error.DuplicateField;
        if (field.oneof_name) |oneof_name| {
            if (seenJsonOneof(seen_fields.items, message.descriptor, oneof_name, field.number)) return error.DuplicateField;
        }
        try seen_fields.append(allocator, field.number);
        if (field.kind == .map) {
            try parseMapField(allocator, file, registry, message, field, entry.value_ptr.*, options);
        } else if (field.cardinality == .repeated) {
            const array = switch (entry.value_ptr.*) {
                .array => |array| array,
                else => return error.TypeMismatch,
            };
            for (array.items) |item| {
                const value = parseValue(allocator, file, registry, message.descriptor, field.kind, item, options) catch |err| {
                    if (shouldIgnoreEnumParseError(options, file, registry, message.descriptor, field.kind, err)) continue;
                    return err;
                };
                try addOwnedValue(allocator, message, field, value);
            }
        } else {
            const value = parseValue(allocator, file, registry, message.descriptor, field.kind, entry.value_ptr.*, options) catch |err| {
                if (shouldIgnoreEnumParseError(options, file, registry, message.descriptor, field.kind, err)) continue;
                return err;
            };
            try addOwnedValue(allocator, message, field, value);
        }
    }
}

fn seenJsonField(seen_fields: []const wire.FieldNumber, number: wire.FieldNumber) bool {
    for (seen_fields) |seen| {
        if (seen == number) return true;
    }
    return false;
}

fn seenJsonOneof(seen_fields: []const wire.FieldNumber, descriptor: *const schema.MessageDescriptor, oneof_name: []const u8, current_number: wire.FieldNumber) bool {
    for (seen_fields) |seen| {
        if (seen == current_number) continue;
        const field = descriptor.findFieldByNumber(seen) orelse continue;
        const seen_oneof = field.oneof_name orelse continue;
        if (std.mem.eql(u8, seen_oneof, oneof_name)) return true;
    }
    return false;
}

fn jsonNullSkipsField(file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, current: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) bool {
    switch (field.kind) {
        .message => |name| {
            if (typeNameEqualsInFile(file, name, "google.protobuf.Value")) return false;
        },
        .enumeration => |name| {
            if (field.oneof_name != null and typeNameEqualsInFile(file, name, "google.protobuf.NullValue")) return false;
        },
        else => {},
    }
    if (field.oneof_name != null) {
        if (fieldKindIsNullValueEnum(file, registry, current, field.kind)) return false;
    }
    return true;
}

fn fieldKindIsNullValueEnum(file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, current: *const schema.MessageDescriptor, kind: schema.FieldKind) bool {
    const enum_name = switch (kind) {
        .enumeration, .message => |name| name,
        else => return false,
    };
    if (typeNameEqualsInFile(file, enum_name, "google.protobuf.NullValue")) return true;
    if (registryEnumDescriptor(file, registry, current, enum_name)) |enum_desc| {
        return enum_desc.findValue("NULL_VALUE") != null and enum_desc.values.items.len == 1;
    }
    return false;
}

fn parseMapField(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    registry: ?*const registry_mod.Registry,
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
        var owns_key = true;
        errdefer if (owns_key) dynamic.deinitValue(&key, allocator);
        var map_value = parseValue(allocator, file, registry, message.descriptor, map_type.value.*, entry.value_ptr.*, options) catch |err| {
            if (shouldIgnoreEnumParseError(options, file, registry, message.descriptor, map_type.value.*, err)) {
                dynamic.deinitValue(&key, allocator);
                owns_key = false;
                continue;
            }
            return err;
        };
        var owns_map_value = true;
        errdefer if (owns_map_value) dynamic.deinitValue(&map_value, allocator);
        const map_entry = try allocator.create(dynamic.MapEntry);
        map_entry.* = .{ .key = key, .value = map_value };
        owns_key = false;
        owns_map_value = false;
        try addOwnedValue(allocator, message, field, .{ .map_entry = map_entry });
    }
}

fn addOwnedValue(allocator: std.mem.Allocator, message: *dynamic.DynamicMessage, field: *const schema.FieldDescriptor, value: dynamic.Value) std.mem.Allocator.Error!void {
    var owned = value;
    errdefer dynamic.deinitValue(&owned, allocator);
    try message.add(field, owned);
}

fn shouldIgnoreEnumParseError(options: Options, file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, current: *const schema.MessageDescriptor, kind: schema.FieldKind, err: anyerror) bool {
    if (!options.ignore_unknown_fields or err != error.InvalidEnumValue) return false;
    return switch (kind) {
        .enumeration => true,
        .message => |name| registryEnumDescriptor(file, registry, current, name) != null,
        else => false,
    };
}

fn parseValue(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    registry: ?*const registry_mod.Registry,
    current: *const schema.MessageDescriptor,
    kind: schema.FieldKind,
    json_value: std.json.Value,
    options: Options,
) anyerror!dynamic.Value {
    return switch (kind) {
        .scalar => |scalar| try parseScalar(allocator, scalar, json_value),
        .enumeration => |name| try parseEnumWithRegistry(file, registry, current, name, json_value),
        .message => |name| blk: {
            if (registryEnumDescriptor(file, registry, current, name)) |_| break :blk try parseEnumWithRegistry(file, registry, current, name, json_value);
            const descriptor = resolveMessageDescriptorWithRegistry(file, registry, current, name) orelse return error.TypeMismatch;
            const descriptor_file = messageDescriptorFile(file, registry, descriptor);
            if (try parseKnownMessage(allocator, descriptor_file, registry, descriptor, name, json_value, options)) |known| break :blk .{ .message = known };
            const nested = try allocator.create(dynamic.DynamicMessage);
            nested.* = dynamic.DynamicMessage.init(allocator, descriptor);
            errdefer {
                nested.deinit();
                allocator.destroy(nested);
            }
            try fillMessageWithRegistry(allocator, descriptor_file, registry, nested, json_value, options);
            break :blk .{ .message = nested };
        },
        .group => |name| blk: {
            const descriptor = resolveMessageDescriptorWithRegistry(file, registry, current, name) orelse return error.TypeMismatch;
            const descriptor_file = messageDescriptorFile(file, registry, descriptor);
            const nested = try allocator.create(dynamic.DynamicMessage);
            nested.* = dynamic.DynamicMessage.init(allocator, descriptor);
            errdefer {
                nested.deinit();
                allocator.destroy(nested);
            }
            try fillMessageWithRegistry(allocator, descriptor_file, registry, nested, json_value, options);
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

fn parseEnumWithRegistry(file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, current: *const schema.MessageDescriptor, name: []const u8, json_value: std.json.Value) !dynamic.Value {
    const enumeration = registryEnumDescriptor(file, registry, current, name);
    switch (json_value) {
        .string => |value| {
            if (enumeration) |enum_desc| {
                for (enum_desc.values.items) |enum_value| {
                    if (std.mem.eql(u8, enum_value.name, value)) return .{ .enumeration = enum_value.number };
                }
            }
            const number = std.fmt.parseInt(i32, value, 10) catch return error.InvalidEnumValue;
            if (enumeration) |enum_desc| {
                if (enumIsClosed(file, registry, enum_desc) and !enumHasNumber(enum_desc, number)) return error.InvalidEnumValue;
            }
            return .{ .enumeration = number };
        },
        .null => {
            if (typeNameEqualsInFile(file, name, "google.protobuf.NullValue")) return .{ .enumeration = 0 };
            if (enumeration) |enum_desc| {
                if (enum_desc.findValue("NULL_VALUE")) |value| {
                    if (value.number == 0 and enum_desc.values.items.len == 1) return .{ .enumeration = 0 };
                }
            }
            return error.TypeMismatch;
        },
        else => {
            const number = try numberAsInt(i32, json_value);
            if (enumeration) |enum_desc| {
                if (enumIsClosed(file, registry, enum_desc) and !enumHasNumber(enum_desc, number)) return error.InvalidEnumValue;
            }
            return .{ .enumeration = number };
        },
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
    return try intValue(T, json_value);
}

fn floatAsInt(comptime T: type, value: f64) !T {
    if (!std.math.isFinite(value)) return error.InvalidNumber;
    if (@trunc(value) != value) return error.TypeMismatch;
    const info = @typeInfo(T).int;
    if (info.signedness == .unsigned and value < 0) return error.Overflow;
    if (info.bits < 64) {
        if (value < @as(f64, @floatFromInt(std.math.minInt(T))) or value > @as(f64, @floatFromInt(std.math.maxInt(T)))) return error.Overflow;
        return @intFromFloat(value);
    }
    if (info.signedness == .signed) {
        if (value < -9223372036854775808.0 or value >= 9223372036854775808.0) return error.Overflow;
    } else {
        if (value < 0 or value >= 18446744073709551616.0) return error.Overflow;
    }
    return @intFromFloat(value);
}

fn numberAsFloat(comptime T: type, json_value: std.json.Value) !T {
    const out: T = switch (json_value) {
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
        else => return error.TypeMismatch,
    };
    if (json_value != .string and !std.math.isFinite(out)) return error.InvalidNumber;
    return out;
}

fn decodeBase64(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    var data_chars: usize = 0;
    var padding_chars: usize = 0;
    var saw_padding = false;
    for (value) |byte| {
        if (byte == '=') {
            saw_padding = true;
            padding_chars += 1;
            continue;
        }
        if (saw_padding) return error.InvalidPadding;
        _ = base64Index(byte) orelse return error.InvalidCharacter;
        data_chars += 1;
    }
    if (data_chars % 4 == 1) return error.InvalidPadding;
    if (padding_chars > 2) return error.InvalidPadding;
    if (padding_chars != 0) {
        const expected_padding: usize = switch (data_chars % 4) {
            0 => 0,
            2 => 2,
            3 => 1,
            else => unreachable,
        };
        if (padding_chars != expected_padding) return error.InvalidPadding;
    }
    const size = (data_chars * 6) / 8;
    const out = try allocator.alloc(u8, size);
    errdefer allocator.free(out);
    var out_index: usize = 0;
    var acc: u32 = 0;
    var acc_bits: u5 = 0;
    for (value) |byte| {
        if (byte == '=') break;
        const idx = base64Index(byte).?;
        acc = (acc << 6) | idx;
        acc_bits += 6;
        while (acc_bits >= 8) {
            acc_bits -= 8;
            out[out_index] = @truncate(acc >> acc_bits);
            out_index += 1;
            acc &= (@as(u32, 1) << acc_bits) - 1;
        }
    }
    std.debug.assert(out_index == out.len);
    return out;
}

fn base64Index(byte: u8) ?u32 {
    return switch (byte) {
        'A'...'Z' => byte - 'A',
        'a'...'z' => 26 + byte - 'a',
        '0'...'9' => 52 + byte - '0',
        '+', '-' => 62,
        '/', '_' => 63,
        else => null,
    };
}

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

fn registryEnumDescriptor(file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, current: *const schema.MessageDescriptor, name: []const u8) ?*const schema.EnumDescriptor {
    if (typeNameEqualsInFile(file, name, "google.protobuf.NullValue")) {
        if (file.findEnumDeep("NullValue")) |enumeration| return enumeration;
    }
    if (registry) |reg| {
        if (std.mem.indexOfScalar(u8, name, '.') == null) {
            if (current.findEnumDeep(name) orelse file.findEnumDeep(name)) |enumeration| return enumeration;
        }
        var scope_buf: [512]u8 = undefined;
        const scope = messageScope(file, current, &scope_buf) orelse if (file.package.len != 0) file.package else null;
        if (reg.findEnumVisible(file, name, scope)) |enumeration| return enumeration;
        if (reg.findEnum(name, scope)) |enumeration| return enumeration;
    }
    const trimmed = if (std.mem.startsWith(u8, name, ".")) name[1..] else name;
    return current.findEnumDeep(trimmed) orelse file.findEnumDeep(trimmed);
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

fn messageDescriptorFile(default_file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, descriptor: *const schema.MessageDescriptor) *const schema.FileDescriptor {
    const reg = registry orelse return default_file;
    return reg.fileContainingMessage(descriptor) orelse default_file;
}

fn enumDescriptorFile(default_file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, descriptor: *const schema.EnumDescriptor) *const schema.FileDescriptor {
    const reg = registry orelse return default_file;
    return reg.fileContainingEnum(descriptor) orelse default_file;
}

fn enumIsClosed(file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, enumeration: *const schema.EnumDescriptor) bool {
    if (enumeration.features) |features| return features.enum_type == .closed;
    return enumDescriptorFile(file, registry, enumeration).features.enum_type == .closed;
}

fn enumHasNumber(enumeration: *const schema.EnumDescriptor, number: i32) bool {
    for (enumeration.values.items) |value| {
        if (value.number == number) return true;
    }
    return false;
}

fn findJsonField(file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, message: *const schema.MessageDescriptor, key: []const u8, options: Options) ?*const schema.FieldDescriptor {
    _ = options;
    for (message.fields.items) |*field| {
        if (std.mem.eql(u8, field.name, key)) return field;
        if (field.json_name) |json_name| {
            if (std.mem.eql(u8, json_name, key)) return field;
        } else if (schema.eqlDefaultJsonName(field.name, key)) return field;
    }
    if (jsonExtensionName(key)) |extension_name| {
        if (registry) |reg| {
            if (reg.findExtensionByNameForMessage(message, extension_name)) |field| return field;
            const leaf = leafName(extension_name);
            if (reg.findExtensionByNameForMessage(message, leaf)) |field| return field;
        } else {
            for (file.extensions.items) |*field| {
                if (field.extendee != null and extensionExtendsMessage(field.extendee.?, message) and (std.mem.eql(u8, field.name, extension_name) or std.mem.eql(u8, field.name, leafName(extension_name)))) return field;
            }
        }
    }
    return null;
}

fn jsonExtensionName(key: []const u8) ?[]const u8 {
    if (key.len < 2 or key[0] != '[' or key[key.len - 1] != ']') return null;
    return key[1 .. key.len - 1];
}

fn leafName(name: []const u8) []const u8 {
    const trimmed = if (std.mem.startsWith(u8, name, ".")) name[1..] else name;
    return if (std.mem.lastIndexOfScalar(u8, trimmed, '.')) |idx| trimmed[idx + 1 ..] else trimmed;
}

fn extensionExtendsMessage(extendee: []const u8, message: *const schema.MessageDescriptor) bool {
    const trimmed = if (std.mem.startsWith(u8, extendee, ".")) extendee[1..] else extendee;
    const leaf = leafName(trimmed);
    return std.mem.eql(u8, message.name, trimmed) or std.mem.eql(u8, message.name, leaf);
}

fn writeMessage(
    file: *const schema.FileDescriptor,
    registry: ?*const registry_mod.Registry,
    message: *const dynamic.DynamicMessage,
    options: Options,
    writer: *std.Io.Writer,
) Error!void {
    try writer.writeAll("{");
    var first = true;
    try writeMessageContents(file, registry, message, options, writer, &first);
    try writer.writeAll("}");
}

fn writeMessageContents(
    file: *const schema.FileDescriptor,
    registry: ?*const registry_mod.Registry,
    message: *const dynamic.DynamicMessage,
    options: Options,
    writer: *std.Io.Writer,
    first: *bool,
) Error!void {
    for (message.fields.items) |*entry| {
        if (entry.values.items.len == 0) continue;
        if (shouldSkipDefaultJsonField(file, registry, message.descriptor, entry)) continue;
        if (!first.*) try writer.writeAll(",");
        first.* = false;
        try writeFieldName(file, registry, entry.descriptor, options, writer);
        try writer.writeAll(":");
        if (entry.descriptor.kind == .map) {
            try writeMap(file, registry, message.descriptor, entry.descriptor, entry.values.items, options, writer);
        } else if (entry.descriptor.cardinality == .repeated) {
            try writer.writeAll("[");
            for (entry.values.items, 0..) |value, index| {
                if (index != 0) try writer.writeAll(",");
                try writeValue(file, registry, message.descriptor, entry.descriptor.kind, value, options, writer);
            }
            try writer.writeAll("]");
        } else {
            try writeValue(file, registry, message.descriptor, entry.descriptor.kind, entry.values.items[entry.values.items.len - 1], options, writer);
        }
    }
    if (options.always_print_primitive_fields) {
        for (message.descriptor.fields.items) |*field| {
            if (message.getByNumber(field.number) != null) continue;
            if (!shouldPrintAbsentField(file, registry, message.descriptor, field)) continue;
            if (!first.*) try writer.writeAll(",");
            first.* = false;
            try writeFieldName(file, registry, field, options, writer);
            try writer.writeAll(":");
            try writeAbsentFieldDefault(file, registry, message.descriptor, field, options, writer);
        }
    }
}

fn shouldSkipDefaultJsonField(file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, current: *const schema.MessageDescriptor, entry: *const dynamic.FieldValue) bool {
    if (entry.descriptor.isRepeatedLike() or entry.descriptor.oneof_name != null or entry.values.items.len != 1) return false;
    if (jsonFieldHasPresence(file, registry, current, entry.descriptor)) return false;
    return jsonValueIsDefault(file, registry, current, entry.descriptor, entry.values.items[0]);
}

fn jsonFieldHasPresence(file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, current: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) bool {
    if (file.syntax == .proto3 and !field.proto3_optional and field.oneof_name == null and field.cardinality != .required and (field.kind == .scalar or field.kind == .enumeration or jsonFieldKindIsRegistryEnum(file, registry, current, field.kind))) return false;
    if (field.cardinality == .required or field.cardinality == .optional or field.proto3_optional or field.oneof_name != null or field.kind == .group) return true;
    if (field.kind == .message and registryEnumDescriptor(file, registry, current, field.kind.message) == null) return true;
    if (field.cardinality == .repeated or field.kind == .map) return false;
    if (field.features) |features| return features.field_presence != .implicit;
    return file.features.field_presence != .implicit;
}

fn jsonValueIsDefault(file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, current: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor, value: dynamic.Value) bool {
    if (field.default_value != null) return false;
    if (jsonFieldKindIsRegistryEnum(file, registry, current, field.kind)) return value == .enumeration and value.enumeration == 0;
    return switch (field.kind) {
        .scalar => |scalar| switch (scalar) {
            .double => value == .double and value.double == 0,
            .float => value == .float and value.float == 0,
            .int32 => value == .int32 and value.int32 == 0,
            .int64 => value == .int64 and value.int64 == 0,
            .uint32 => value == .uint32 and value.uint32 == 0,
            .uint64 => value == .uint64 and value.uint64 == 0,
            .sint32 => value == .sint32 and value.sint32 == 0,
            .sint64 => value == .sint64 and value.sint64 == 0,
            .fixed32 => value == .fixed32 and value.fixed32 == 0,
            .fixed64 => value == .fixed64 and value.fixed64 == 0,
            .sfixed32 => value == .sfixed32 and value.sfixed32 == 0,
            .sfixed64 => value == .sfixed64 and value.sfixed64 == 0,
            .bool => value == .boolean and !value.boolean,
            .string => value == .string and value.string.len == 0,
            .bytes => value == .bytes and value.bytes.len == 0,
        },
        .enumeration => value == .enumeration and value.enumeration == 0,
        else => false,
    };
}

fn jsonFieldKindIsRegistryEnum(file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, current: *const schema.MessageDescriptor, kind: schema.FieldKind) bool {
    const enum_name = switch (kind) {
        .enumeration, .message => |name| name,
        else => return false,
    };
    return registryEnumDescriptor(file, registry, current, enum_name) != null;
}

fn shouldPrintAbsentField(file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, current: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) bool {
    if (field.oneof_name != null) return false;
    return switch (field.kind) {
        .scalar, .enumeration, .map => true,
        .message => |name| registryEnumDescriptor(file, registry, current, name) != null,
        else => field.cardinality == .repeated,
    };
}

fn writeAbsentFieldDefault(file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, current: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor, options: Options, writer: *std.Io.Writer) Error!void {
    if (field.kind == .map or field.cardinality == .repeated) return writer.writeAll(if (field.kind == .map) "{}" else "[]");
    switch (field.kind) {
        .scalar => |scalar| try writeDefaultScalar(scalar, field.default_value, writer),
        .enumeration => |name| {
            const number: i32 = defaultEnumNumber(file, registry, current, name, field.default_value);
            try writeEnum(file, registry, current, name, .{ .enumeration = number }, options, writer);
        },
        .message => |name| if (registryEnumDescriptor(file, registry, current, name) != null) {
            const number: i32 = defaultEnumNumber(file, registry, current, name, field.default_value);
            try writeEnum(file, registry, current, name, .{ .enumeration = number }, options, writer);
        } else try writer.writeAll("null"),
        else => try writer.writeAll("null"),
    }
}

fn writeMap(
    file: *const schema.FileDescriptor,
    registry: ?*const registry_mod.Registry,
    current: *const schema.MessageDescriptor,
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
        try writeValue(file, registry, current, map_type.value.*, entry.value, options, writer);
    }
    try writer.writeAll("}");
}

fn writeValue(
    file: *const schema.FileDescriptor,
    registry: ?*const registry_mod.Registry,
    current: *const schema.MessageDescriptor,
    kind: schema.FieldKind,
    value: dynamic.Value,
    options: Options,
    writer: *std.Io.Writer,
) Error!void {
    switch (kind) {
        .scalar => |scalar| try writeScalar(scalar, value, writer),
        .enumeration => |name| try writeEnum(file, registry, current, name, value, options, writer),
        .message => |name| if (registryEnumDescriptor(file, registry, current, name) != null)
            try writeEnum(file, registry, current, name, value, options, writer)
        else switch (value) {
            .message => |message| {
                const message_file = messageDescriptorFile(file, registry, message.descriptor);
                if (!try writeKnownMessage(message_file, registry, name, message, options, writer)) {
                    try writeMessage(message_file, registry, message, options, writer);
                }
            },
            else => return error.TypeMismatch,
        },
        .group => switch (value) {
            .group => |message| try writeMessage(messageDescriptorFile(file, registry, message.descriptor), registry, message, options, writer),
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
        if (!std.math.isFinite(field.values.items[0].double)) return error.InvalidNumber;
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
        var owns_value_message = true;
        errdefer if (owns_value_message) {
            value_message.deinit();
            allocator.destroy(value_message);
        };
        const key = try allocator.dupe(u8, entry.key_ptr.*);
        var owns_key = true;
        errdefer if (owns_key) allocator.free(key);
        const map_entry = try allocator.create(dynamic.MapEntry);
        map_entry.* = .{
            .key = .{ .string = key },
            .value = .{ .message = value_message },
        };
        owns_key = false;
        owns_value_message = false;
        try addOwnedValue(allocator, message, field, .{ .map_entry = map_entry });
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
    for (array.items) |item| {
        try addOwnedValue(allocator, message, field, .{ .message = try parseValueMessage(allocator, file, value_desc, item) });
    }
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
        .float, .number_string => try message.add(descriptor.findField("number_value") orelse return error.TypeMismatch, .{ .double = try numberAsFloat(f64, json_value) }),
        .string => |value| try addOwnedValue(allocator, message, descriptor.findField("string_value") orelse return error.TypeMismatch, .{ .string = try allocator.dupe(u8, value) }),
        .object => {
            const struct_desc = resolveMessageDescriptor(file, descriptor, "Struct") orelse return error.TypeMismatch;
            try addOwnedValue(allocator, message, descriptor.findField("struct_value") orelse return error.TypeMismatch, .{ .message = try parseStructMessage(allocator, file, struct_desc, json_value) });
        },
        .array => {
            const list_desc = resolveMessageDescriptor(file, descriptor, "ListValue") orelse return error.TypeMismatch;
            try addOwnedValue(allocator, message, descriptor.findField("list_value") orelse return error.TypeMismatch, .{ .message = try parseListValueMessage(allocator, file, list_desc, json_value) });
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

fn writeKnownMessage(file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, name: []const u8, message: *const dynamic.DynamicMessage, options: Options, writer: *std.Io.Writer) Error!bool {
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
        if (any.type_url.len == 0 and any.value.len == 0) {
            try writer.writeAll("{}");
            return true;
        }
        if (resolveAnyTypeWithRegistry(file, registry, message.descriptor, any.type_url)) |descriptor| {
            var nested = dynamic.DynamicMessage.init(message.allocator, descriptor);
            defer nested.deinit();
            const payload_file = messageDescriptorFile(file, registry, descriptor);
            if (registry) |reg| {
                try nested.decodeWithRegistry(payload_file, reg, any.value);
            } else {
                try nested.decode(payload_file, any.value);
            }
            try writer.writeAll("{\"@type\":");
            try std.json.Stringify.value(any.type_url, .{}, writer);
            const type_name = anyTypeName(any.type_url);
            if (anyUsesValueEnvelope(type_name)) {
                try writer.writeAll(",\"value\":");
                if (!try writeKnownMessage(payload_file, registry, type_name, &nested, options, writer)) {
                    try writeMessage(payload_file, registry, &nested, options, writer);
                }
            } else {
                var first = false;
                try writeMessageContents(payload_file, registry, &nested, options, writer, &first);
            }
            try writer.writeAll("}");
            return true;
        }
        try writeStandaloneAnyJson(message.allocator, any, writer);
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

fn writeStandaloneAnyJson(allocator: std.mem.Allocator, any: wkt.Any, writer: *std.Io.Writer) Error!void {
    any.jsonStringifyWithAllocator(allocator, writer) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.WriteFailed => return error.WriteFailed,
        error.TypeMismatch => return error.TypeMismatch,
        error.InvalidUtf8 => return error.InvalidUtf8,
        error.InvalidWireType => return error.InvalidWireType,
        error.InvalidFieldNumber => return error.InvalidFieldNumber,
        error.MalformedVarint => return error.MalformedVarint,
        error.TruncatedInput => return error.TruncatedInput,
        error.UnsupportedWireType => return error.UnsupportedWireType,
        error.Overflow => return error.Overflow,
        error.RecursionLimitExceeded => return error.RecursionLimitExceeded,
        error.TimestampOutOfRange => return error.TimestampOutOfRange,
        error.InvalidNanos => return error.InvalidNanos,
        error.DurationOutOfRange => return error.DurationOutOfRange,
        error.DurationSignMismatch => return error.DurationSignMismatch,
        error.InvalidFieldMask => return error.InvalidFieldMask,
        else => return error.TypeMismatch,
    };
}

fn parseKnownMessage(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, descriptor: *const schema.MessageDescriptor, name: []const u8, json_value: std.json.Value, options: Options) anyerror!?*dynamic.DynamicMessage {
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
        const field = descriptor.findField("value") orelse return error.TypeMismatch;
        try addOwnedValue(allocator, message, field, try parseWrapperValue(allocator, kind, json_value));
        return message;
    }
    if (typeNameEquals(name, "google.protobuf.Empty")) {
        const object = switch (json_value) {
            .object => |object| object,
            else => return error.TypeMismatch,
        };
        if (object.count() != 0) return error.UnknownField;
        return try emptyKnownMessage(allocator, descriptor);
    }
    if (typeNameEquals(name, "google.protobuf.Any")) {
        return try parseAnyMessage(allocator, file, registry, descriptor, json_value, options);
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
        for (paths) |path| try addOwnedValue(allocator, message, field, .{ .string = try allocator.dupe(u8, path) });
        return message;
    }
    message.deinit();
    allocator.destroy(message);
    return null;
}

fn parseAnyMessage(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, descriptor: *const schema.MessageDescriptor, json_value: std.json.Value, options: Options) anyerror!*dynamic.DynamicMessage {
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
    const type_json = object.get("@type") orelse {
        try fillMessageObject(allocator, file, registry, message, object, options, false);
        return message;
    };
    const type_url = switch (type_json) {
        .string => |value| value,
        else => return error.TypeMismatch,
    };
    if (!anyTypeUrlIsValid(type_url)) return error.TypeMismatch;
    try addOwnedValue(allocator, message, type_field, .{ .string = try allocator.dupe(u8, type_url) });
    const payload_desc = resolveAnyTypeWithRegistry(file, registry, descriptor, type_url);
    if (object.get("value")) |value_json| {
        if (payload_desc) |resolved| {
            const payload_name = anyTypeName(type_url);
            if (anyUsesValueEnvelope(payload_name)) {
                var it = object.iterator();
                while (it.next()) |entry| {
                    if (!std.mem.eql(u8, entry.key_ptr.*, "@type") and !std.mem.eql(u8, entry.key_ptr.*, "value")) return error.UnknownField;
                }
                const payload_file = messageDescriptorFile(file, registry, resolved);
                const payload = (try parseKnownMessage(allocator, payload_file, registry, resolved, payload_name, value_json, options)) orelse return error.TypeMismatch;
                defer {
                    payload.deinit();
                    allocator.destroy(payload);
                }
                if (options.validate_any_payloads) try payload.validateRequired();
                const encoded = try payload.encodedDeterministicWithRegistry(payload_file, registry);
                defer allocator.free(encoded);
                try addOwnedValue(allocator, message, value_field, .{ .bytes = try allocator.dupe(u8, encoded) });
                return message;
            }
        }
        if (payload_desc == null) {
            var it = object.iterator();
            while (it.next()) |entry| {
                if (!std.mem.eql(u8, entry.key_ptr.*, "@type") and !std.mem.eql(u8, entry.key_ptr.*, "value")) return error.UnknownField;
            }
            const encoded = switch (value_json) {
                .string => |value| value,
                else => return error.TypeMismatch,
            };
            try addOwnedValue(allocator, message, value_field, .{ .bytes = try decodeBase64(allocator, encoded) });
            return message;
        }
    }
    if (payload_desc) |payload_desc_value| {
        const payload = try allocator.create(dynamic.DynamicMessage);
        payload.* = dynamic.DynamicMessage.init(allocator, payload_desc_value);
        defer {
            payload.deinit();
            allocator.destroy(payload);
        }
        const payload_file = messageDescriptorFile(file, registry, payload_desc_value);
        try fillMessageObject(allocator, payload_file, registry, payload, object, options, true);
        if (options.validate_any_payloads) try payload.validateRequired();
        const encoded = try payload.encodedDeterministicWithRegistry(payload_file, registry);
        defer allocator.free(encoded);
        try addOwnedValue(allocator, message, value_field, .{ .bytes = try allocator.dupe(u8, encoded) });
    } else return error.TypeMismatch;
    return message;
}

fn anyTypeName(type_url: []const u8) []const u8 {
    return if (std.mem.lastIndexOfScalar(u8, type_url, '/')) |idx| type_url[idx + 1 ..] else type_url;
}

fn anyTypeUrlIsValid(type_url: []const u8) bool {
    const slash = std.mem.lastIndexOfScalar(u8, type_url, '/') orelse return false;
    return slash != type_url.len - 1;
}

fn anyUsesValueEnvelope(name: []const u8) bool {
    return typeNameEquals(name, "google.protobuf.Any") or
        typeNameEquals(name, "google.protobuf.Timestamp") or
        typeNameEquals(name, "google.protobuf.Duration") or
        typeNameEquals(name, "google.protobuf.FieldMask") or
        typeNameEquals(name, "google.protobuf.Struct") or
        typeNameEquals(name, "google.protobuf.Value") or
        typeNameEquals(name, "google.protobuf.ListValue") or
        wrapperKind(name) != null;
}

fn resolveAnyTypeWithRegistry(file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, current: *const schema.MessageDescriptor, type_url: []const u8) ?*const schema.MessageDescriptor {
    const name = if (std.mem.lastIndexOfScalar(u8, type_url, '/')) |idx| type_url[idx + 1 ..] else type_url;
    return resolveMessageDescriptorWithRegistry(file, registry, current, name);
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

fn typeNameEqualsInFile(file: *const schema.FileDescriptor, name: []const u8, expected: []const u8) bool {
    if (typeNameEquals(name, expected)) return true;
    const normalized = if (std.mem.startsWith(u8, name, ".")) name[1..] else name;
    if (std.mem.indexOfScalar(u8, normalized, '.') != null) return false;
    if (file.package.len == 0) return false;
    if (!std.mem.startsWith(u8, expected, file.package)) return false;
    if (expected.len != file.package.len + 1 + normalized.len) return false;
    if (expected[file.package.len] != '.') return false;
    return std.mem.eql(u8, expected[file.package.len + 1 ..], normalized);
}

fn addKnownTimeFields(message: *dynamic.DynamicMessage, seconds: i64, nanos: i32) !void {
    if (seconds != 0) try message.add(message.descriptor.findField("seconds") orelse return error.TypeMismatch, .{ .int64 = seconds });
    if (nanos != 0) try message.add(message.descriptor.findField("nanos") orelse return error.TypeMismatch, .{ .int32 = nanos });
}

fn writeFieldMaskMessage(message: *const dynamic.DynamicMessage, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("\"");
    if (message.get("paths")) |field| {
        var mask_paths: [1][]const u8 = undefined;
        for (field.values.items, 0..) |value, index| {
            if (value != .string) return error.TypeMismatch;
            mask_paths[0] = value.string;
            try (wkt.FieldMask{ .paths = &mask_paths }).validate();
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
        .unsigned_integer => |v| if (v <= std.math.maxInt(T)) @intCast(v) else 0,
        .identifier, .string => |text| parseIntegerDefault(T, text) catch 0,
        else => 0,
    };
}

fn defaultFloat(default_value: ?schema.OptionValue) f64 {
    const value = default_value orelse return 0;
    return switch (value) {
        .float => |v| v,
        .integer => |v| @floatFromInt(v),
        .unsigned_integer => |v| @floatFromInt(v),
        .identifier, .string => |text| parseSpecialFloatDefault(text) orelse (std.fmt.parseFloat(f64, text) catch 0),
        else => 0,
    };
}

fn defaultEnumNumber(file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, current: *const schema.MessageDescriptor, name: []const u8, default_value: ?schema.OptionValue) i32 {
    const enumeration = registryEnumDescriptor(file, registry, current, name);
    if (default_value) |value| switch (value) {
        .integer => |v| return if (v >= std.math.minInt(i32) and v <= std.math.maxInt(i32)) @intCast(v) else 0,
        .unsigned_integer => |v| return if (v <= std.math.maxInt(i32)) @intCast(v) else 0,
        .identifier, .string => |text| {
            if (std.fmt.parseInt(i32, text, 10)) |number| return number else |_| {}
            if (enumeration) |enum_desc| {
                if (enum_desc.findValue(text)) |enum_value| return enum_value.number;
            }
            return 0;
        },
        else => return 0,
    };
    if (enumeration) |enum_desc| {
        if (enum_desc.values.items.len != 0) return enum_desc.values.items[0].number;
    }
    return 0;
}

fn parseSpecialFloatDefault(text: []const u8) ?f64 {
    var body = text;
    var negative = false;
    if (body.len != 0 and (body[0] == '-' or body[0] == '+')) {
        negative = body[0] == '-';
        body = body[1..];
    }
    if (std.ascii.eqlIgnoreCase(body, "inf") or std.ascii.eqlIgnoreCase(body, "infinity")) {
        const value = std.math.inf(f64);
        return if (negative) -value else value;
    }
    if (std.ascii.eqlIgnoreCase(body, "nan")) return std.math.nan(f64);
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

fn writeEnum(
    file: *const schema.FileDescriptor,
    registry: ?*const registry_mod.Registry,
    current: *const schema.MessageDescriptor,
    name: []const u8,
    value: dynamic.Value,
    options: Options,
    writer: *std.Io.Writer,
) Error!void {
    const number = switch (value) {
        .enumeration => |v| v,
        else => return error.TypeMismatch,
    };
    if (typeNameEqualsInFile(file, name, "google.protobuf.NullValue")) {
        if (number == 0) return try writer.writeAll("null");
    }
    if (options.enum_as_name) {
        if (registryEnumDescriptor(file, registry, current, name)) |enumeration| {
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
    if (!std.unicode.utf8ValidateSlice(value)) return error.InvalidUtf8;
    if (!jsonStringNeedsEscape(value)) {
        try writer.writeByte('"');
        try writer.writeAll(value);
        try writer.writeByte('"');
        return;
    }
    try std.json.Stringify.value(value, .{}, writer);
}

fn writeJsonStringContents(value: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeAll(value);
}

fn jsonStringNeedsEscape(value: []const u8) bool {
    const vector_len = std.simd.suggestVectorLength(u8) orelse 0;
    if (vector_len >= 8) {
        const V = @Vector(vector_len, u8);
        var index: usize = 0;
        const quote: V = @splat('"');
        const slash: V = @splat('\\');
        const control: V = @splat(0x20);
        while (index + vector_len <= value.len) : (index += vector_len) {
            const chunk: V = value[index..][0..vector_len].*;
            if (@reduce(.Or, (chunk == quote) | (chunk == slash) | (chunk < control))) return true;
        }
        for (value[index..]) |byte| {
            if (byte == '"' or byte == '\\' or byte < 0x20) return true;
        }
        return false;
    }
    for (value) |byte| {
        if (byte == '"' or byte == '\\' or byte < 0x20) return true;
    }
    return false;
}

fn writeJsonStringFmt(writer: *std.Io.Writer, comptime fmt: []const u8, args: anytype) Error!void {
    try writer.writeAll("\"");
    try writer.print(fmt, args);
    try writer.writeAll("\"");
}

fn writeFieldName(file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, field: *const schema.FieldDescriptor, options: Options, writer: *std.Io.Writer) Error!void {
    if (field.extendee != null) return writeJsonStringExtensionName(file, registry, field, writer);
    if (options.preserve_proto_field_names) return writeJsonString(field.name, writer);
    if (field.json_name) |json_name| return writeJsonString(json_name, writer);
    try writer.writeAll("\"");
    try schema.writeDefaultJsonName(field.name, writer);
    try writer.writeAll("\"");
}

fn writeJsonStringExtensionName(file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, field: *const schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("\"[");
    const full_name = schema.extensionFullName(field);
    if (std.mem.startsWith(u8, full_name, ".")) {
        try writeJsonStringContents(full_name[1..], writer);
    } else if (std.mem.indexOfScalar(u8, full_name, '.') != null) {
        try writeJsonStringContents(full_name, writer);
    } else {
        const package = extensionDefiningPackage(registry, field) orelse file.package;
        if (package.len != 0) {
            try writeJsonStringContents(package, writer);
            try writer.writeByte('.');
        }
        try writeJsonStringContents(full_name, writer);
    }
    try writer.writeAll("]\"");
}

fn extensionDefiningPackage(registry: ?*const registry_mod.Registry, field: *const schema.FieldDescriptor) ?[]const u8 {
    const reg = registry orelse return null;
    for (reg.files.items) |file| {
        for (file.extensions.items) |*candidate| if (candidate == field) return file.package;
        for (file.messages.items) |*message| if (extensionPackageInMessage(file, message, field)) |package| return package;
    }
    return null;
}

fn extensionPackageInMessage(file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) ?[]const u8 {
    for (message.extensions.items) |*candidate| if (candidate == field) return file.package;
    for (message.messages.items) |*nested| if (extensionPackageInMessage(file, nested, field)) |package| return package;
    return null;
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

test "json stringify rejects invalid utf8 strings" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message M {
        \\  optional string name = 1;
        \\  repeated string tags = 2;
        \\  map<string, int32> keyed = 3;
        \\}
    );
    defer file.deinit();
    const desc = file.findMessage("M").?;

    var bad_name = dynamic.DynamicMessage.init(allocator, desc);
    defer bad_name.deinit();
    try bad_name.add(desc.findField("name").?, .{ .string = try allocator.dupe(u8, &.{0xc0}) });
    try std.testing.expectError(error.InvalidUtf8, stringifyAlloc(allocator, &file, &bad_name, .{}));

    var bad_repeated = dynamic.DynamicMessage.init(allocator, desc);
    defer bad_repeated.deinit();
    try bad_repeated.add(desc.findField("tags").?, .{ .string = try allocator.dupe(u8, "ok") });
    try bad_repeated.add(desc.findField("tags").?, .{ .string = try allocator.dupe(u8, &.{0xc0}) });
    try std.testing.expectError(error.InvalidUtf8, stringifyAlloc(allocator, &file, &bad_repeated, .{}));

    var bad_key = dynamic.DynamicMessage.init(allocator, desc);
    defer bad_key.deinit();
    const entry = try allocator.create(dynamic.MapEntry);
    entry.* = .{ .key = .{ .string = try allocator.dupe(u8, &.{0xc0}) }, .value = .{ .int32 = 1 } };
    try bad_key.add(desc.findField("keyed").?, .{ .map_entry = entry });
    try std.testing.expectError(error.InvalidUtf8, stringifyAlloc(allocator, &file, &bad_key, .{}));
}

fn exerciseJsonMapParseCleanup(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, descriptor: *const schema.MessageDescriptor) !void {
    var parsed = try parseAlloc(allocator, file, descriptor, "{\"keyed\":{\"a\":\"owned\"}}", .{});
    defer parsed.deinit();

    const entry = parsed.get("keyed").?.values.items[0].map_entry;
    try std.testing.expectEqualStrings("a", entry.key.string);
    try std.testing.expectEqualStrings("owned", entry.value.string);
}

test "json map parse cleans up allocation failures" {
    var file = try @import("parser.zig").Parser.parse(std.testing.allocator,
        \\syntax = "proto3";
        \\message M { map<string, string> keyed = 1; }
    );
    defer file.deinit();
    try std.testing.checkAllAllocationFailures(std.testing.allocator, exerciseJsonMapParseCleanup, .{ &file, file.findMessage("M").? });
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

test "json parse dynamic message uses last duplicate object key" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\message M { int32 id = 1; map<string, int32> counts = 2; }
    );
    defer file.deinit();
    const desc = file.findMessage("M").?;

    var msg = try parseAlloc(allocator, &file, desc,
        \\{"id":1,"id":2,"counts":{"red":1,"red":3}}
    , .{});
    defer msg.deinit();

    try std.testing.expectEqual(@as(i32, 2), msg.get("id").?.values.items[0].int32);
    try std.testing.expectEqual(@as(usize, 1), msg.get("counts").?.values.items.len);
    try std.testing.expectEqual(@as(i32, 3), msg.get("counts").?.values.items[0].map_entry.value.int32);
}

test "json parseInitialized validates required fields recursively" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Child { required int32 id = 1; }
        \\message Parent { required Child child = 1; }
    );
    defer file.deinit();
    const parent_desc = file.findMessage("Parent").?;

    try std.testing.expectError(error.MissingRequiredField, parseInitializedAlloc(allocator, &file, parent_desc, "{}", .{}));
    try std.testing.expectError(error.MissingRequiredField, parseInitializedAlloc(allocator, &file, parent_desc, "{\"child\":{}}", .{}));

    var parsed = try parseInitializedAlloc(allocator, &file, parent_desc, "{\"child\":{\"id\":7}}", .{});
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

    try std.testing.expectError(error.MissingRequiredField, parseInitializedAllocWithRegistry(allocator, &app, &registry, imported_parent, "{\"child\":{}}", .{}));
    var imported = try parseInitializedAllocWithRegistry(allocator, &app, &registry, imported_parent, "{\"child\":{\"id\":9}}", .{});
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
    try std.testing.expectError(error.MissingRequiredField, parseInitializedAllocWithRegistry(allocator, &ext_file, &ext_registry, host_desc, "{\"[demo.ext]\":{}}", .{}));
    var ext_parsed = try parseInitializedAllocWithRegistry(allocator, &ext_file, &ext_registry, host_desc, "{\"[demo.ext]\":{\"id\":11}}", .{});
    defer ext_parsed.deinit();
    try std.testing.expectEqual(@as(i32, 11), ext_parsed.get("ext").?.values.items[0].message.get("id").?.values.items[0].int32);
    try std.testing.expectError(error.MissingRequiredField, parseInitializedAllocWithRegistry(allocator, &ext_file, &ext_registry, host_desc, "{\"[demo.exts]\":[{\"id\":1},{}]}", .{}));
    var repeated_ext_parsed = try parseInitializedAllocWithRegistry(allocator, &ext_file, &ext_registry, host_desc, "{\"[demo.exts]\":[{\"id\":1},{\"id\":2}]}", .{});
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
    try std.testing.expectError(error.MissingRequiredField, parseInitializedAllocWithRegistry(allocator, &messageset_file, &messageset_registry, messageset_host, "{\"[demo.ms.ext]\":{}}", .{}));
    var messageset_parsed = try parseInitializedAllocWithRegistry(allocator, &messageset_file, &messageset_registry, messageset_host, "{\"[demo.ms.ext]\":{\"id\":12}}", .{});
    defer messageset_parsed.deinit();
    try std.testing.expectEqual(@as(i32, 12), messageset_parsed.get("ext").?.values.items[0].message.get("id").?.values.items[0].int32);
}

test "json registry resolves same-package imported unqualified fields" {
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
        \\{"user":{"name":"Ada"},"kind":"ADMIN"}
    , .{});
    defer parsed.deinit();

    try std.testing.expectEqualStrings("Ada", parsed.get("user").?.values.items[0].message.get("name").?.values.items[0].string);
    try std.testing.expectEqual(@as(i32, 7), parsed.get("kind").?.values.items[0].enumeration);

    const rendered = try stringifyAllocWithRegistry(allocator, &app, &registry, &parsed, .{});
    defer allocator.free(rendered);
    try std.testing.expectEqualStrings("{\"user\":{\"name\":\"Ada\"},\"kind\":\"ADMIN\"}", rendered);
}

test "json parse with registry resolves imported message and enum fields" {
    const allocator = std.testing.allocator;
    var common = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package common;
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message User { string name = 1; }
    );
    defer common.deinit();
    var app = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package app;
        \\message Event { common.User user = 1; common.Kind kind = 2; repeated common.Kind roles = 3; }
    );
    defer app.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);

    var event = try parseAllocWithRegistry(allocator, &app, &registry, app.findMessage("Event").?,
        \\{"user":{"name":"Ada"},"kind":"ADMIN","roles":["ADMIN",0]}
    , .{});
    defer event.deinit();

    try std.testing.expectEqualSlices(u8, "Ada", event.get("user").?.values.items[0].message.get("name").?.values.items[0].string);
    try std.testing.expectEqual(@as(i32, 1), event.get("kind").?.values.items[0].enumeration);
    try std.testing.expectEqual(@as(i32, 1), event.get("roles").?.values.items[0].enumeration);
    try std.testing.expectEqual(@as(i32, 0), event.get("roles").?.values.items[1].enumeration);

    const rendered = try stringifyAllocWithRegistry(allocator, &app, &registry, &event, .{});
    defer allocator.free(rendered);
    try std.testing.expectEqualSlices(u8, "{\"user\":{\"name\":\"Ada\"},\"kind\":\"ADMIN\",\"roles\":[\"ADMIN\",\"UNKNOWN\"]}", rendered);
}

test "json imported enums use owning file features" {
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

    var open_in_proto2 = try parseAllocWithRegistry(allocator, &proto2_app, &registry, proto2_app.findMessage("Event").?, "{\"kind\":123}", .{});
    defer open_in_proto2.deinit();
    try std.testing.expectEqual(@as(i32, 123), open_in_proto2.get("kind").?.values.items[0].enumeration);

    try std.testing.expectError(error.InvalidEnumValue, parseAllocWithRegistry(allocator, &proto3_app, &registry, proto3_app.findMessage("Event").?, "{\"kind\":123}", .{}));
}

test "json imported messages use owning file features" {
    const allocator = std.testing.allocator;
    var common = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package common;
        \\message Payload { optional int32 id = 1; optional bytes raw = 2; }
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
        \\{"payload":{"id":0,"raw":"wA=="},"keyed":{"one":{"id":0,"raw":"wA=="}}}
    , .{});
    defer parsed.deinit();

    try std.testing.expect(parsed.get("payload").?.values.items[0].message.has(common.findMessage("Payload").?.findField("id").?));
    try std.testing.expectEqual(@as(i32, 0), parsed.get("payload").?.values.items[0].message.get("id").?.values.items[0].int32);
    try std.testing.expectEqualSlices(u8, &.{0xc0}, parsed.get("payload").?.values.items[0].message.get("raw").?.values.items[0].bytes);
    const entry = parsed.get("keyed").?.values.items[0].map_entry;
    try std.testing.expectEqualStrings("one", entry.key.string);
    try std.testing.expect(entry.value.message.has(common.findMessage("Payload").?.findField("id").?));
    try std.testing.expectEqual(@as(i32, 0), entry.value.message.get("id").?.values.items[0].int32);
    try std.testing.expectEqualSlices(u8, &.{0xc0}, entry.value.message.get("raw").?.values.items[0].bytes);

    const rendered = try stringifyAllocWithRegistry(allocator, &app, &registry, &parsed, .{});
    defer allocator.free(rendered);
    try std.testing.expectEqualSlices(u8, "{\"payload\":{\"id\":0,\"raw\":\"wA==\"},\"keyed\":{\"one\":{\"id\":0,\"raw\":\"wA==\"}}}", rendered);
}

test "json Any payloads use owning file features" {
    const allocator = std.testing.allocator;
    var common = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package common;
        \\message Payload { optional int32 id = 1; optional bytes raw = 2; }
    );
    defer common.deinit();
    common.name = "common.proto";
    var app = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package app;
        \\import "common.proto";
        \\message Any { optional string type_url = 1; optional bytes value = 2; }
        \\message Holder { .google.protobuf.Any any = 1; }
    );
    defer app.deinit();
    app.name = "app.proto";
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);

    const holder_desc = app.findMessage("Holder").?;
    const any_desc = app.findMessage("Any").?;
    const payload_desc = common.findMessage("Payload").?;

    var payload = dynamic.DynamicMessage.init(allocator, payload_desc);
    defer payload.deinit();
    try payload.add(payload_desc.findField("id").?, .{ .int32 = 0 });
    try payload.add(payload_desc.findField("raw").?, .{ .bytes = try allocator.dupe(u8, &.{0xc0}) });
    const payload_bytes = try payload.encodedDeterministicWithRegistry(&common, &registry);
    defer allocator.free(payload_bytes);

    var holder = dynamic.DynamicMessage.init(allocator, holder_desc);
    defer holder.deinit();
    const any_msg = try allocator.create(dynamic.DynamicMessage);
    any_msg.* = dynamic.DynamicMessage.init(allocator, any_desc);
    try any_msg.add(any_desc.findField("type_url").?, .{ .string = try allocator.dupe(u8, "type.googleapis.com/common.Payload") });
    try any_msg.add(any_desc.findField("value").?, .{ .bytes = try allocator.dupe(u8, payload_bytes) });
    try holder.add(holder_desc.findField("any").?, .{ .message = any_msg });

    const rendered = try stringifyAllocWithRegistry(allocator, &app, &registry, &holder, .{});
    defer allocator.free(rendered);
    try std.testing.expectEqualSlices(u8, "{\"any\":{\"@type\":\"type.googleapis.com/common.Payload\",\"id\":0,\"raw\":\"wA==\"}}", rendered);

    var parsed = try parseAllocWithRegistry(allocator, &app, &registry, holder_desc, "{\"any\":{\"@type\":\"type.googleapis.com/common.Payload\",\"id\":0,\"raw\":\"wA==\"}}", .{});
    defer parsed.deinit();
    const parsed_value = parsed.get("any").?.values.items[0].message.get("value").?.values.items[0].bytes;
    var decoded_payload = dynamic.DynamicMessage.init(allocator, payload_desc);
    defer decoded_payload.deinit();
    try decoded_payload.decodeWithRegistry(&common, &registry, parsed_value);
    try std.testing.expect(decoded_payload.has(payload_desc.findField("id").?));
    try std.testing.expectEqual(@as(i32, 0), decoded_payload.get("id").?.values.items[0].int32);
    try std.testing.expectEqualSlices(u8, &.{0xc0}, decoded_payload.get("raw").?.values.items[0].bytes);
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

test "json honors closed enum feature for numeric values" {
    const allocator = std.testing.allocator;
    {
        var file = try @import("parser.zig").Parser.parse(allocator,
            \\edition = "2023";
            \\option features.enum_type = CLOSED;
            \\enum Kind { option features.enum_type = OPEN; UNKNOWN = 0; ADMIN = 1; }
            \\message M { Kind kind = 1; repeated Kind roles = 2; }
        );
        defer file.deinit();
        const desc = file.findMessage("M").?;
        var msg = try parseAlloc(allocator, &file, desc, "{\"kind\":123,\"roles\":[\"123\"]}", .{});
        defer msg.deinit();
        try std.testing.expectEqual(@as(i32, 123), msg.get("kind").?.values.items[0].enumeration);
        try std.testing.expectEqual(@as(i32, 123), msg.get("roles").?.values.items[0].enumeration);
    }
    {
        var file = try @import("parser.zig").Parser.parse(allocator,
            \\edition = "2023";
            \\option features.enum_type = OPEN;
            \\enum Kind { option features.enum_type = CLOSED; UNKNOWN = 0; ADMIN = 1; }
            \\message M {
            \\  Kind kind = 1;
            \\  repeated Kind roles = 2;
            \\  map<string, Kind> keyed = 3;
            \\}
        );
        defer file.deinit();
        const desc = file.findMessage("M").?;
        try std.testing.expectError(error.InvalidEnumValue, parseAlloc(allocator, &file, desc, "{\"kind\":123}", .{}));
        try std.testing.expectError(error.InvalidEnumValue, parseAlloc(allocator, &file, desc, "{\"roles\":[\"123\"]}", .{}));
        try std.testing.expectError(error.InvalidEnumValue, parseAlloc(allocator, &file, desc, "{\"keyed\":{\"bad\":123}}", .{}));

        var ignored = try parseAlloc(allocator, &file, desc, "{\"kind\":123,\"roles\":[1,123],\"keyed\":{\"ok\":1,\"bad\":123}}", .{ .ignore_unknown_fields = true });
        defer ignored.deinit();
        try std.testing.expect(ignored.get("kind") == null);
        try std.testing.expectEqual(@as(usize, 1), ignored.get("roles").?.values.items.len);
        try std.testing.expectEqual(@as(i32, 1), ignored.get("roles").?.values.items[0].enumeration);
        try std.testing.expectEqual(@as(usize, 1), ignored.get("keyed").?.values.items.len);
        try std.testing.expectEqualStrings("ok", ignored.get("keyed").?.values.items[0].map_entry.key.string);
    }
}

test "json ignore unknown fields skips unknown enum names" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message M {
        \\  Kind kind = 1;
        \\  repeated Kind roles = 2;
        \\  map<string, Kind> keyed = 3;
        \\}
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("M").?;

    try std.testing.expectError(error.InvalidEnumValue, parseAlloc(allocator, &file, desc, "{\"kind\":\"BOGUS\"}", .{}));

    var parsed = try parseAlloc(allocator, &file, desc,
        \\{"kind":"BOGUS","roles":["ADMIN","BOGUS",1],"keyed":{"ok":"ADMIN","bad":"BOGUS"}}
    , .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    try std.testing.expect(parsed.get("kind") == null);
    try std.testing.expectEqual(@as(usize, 2), parsed.get("roles").?.values.items.len);
    try std.testing.expectEqual(@as(i32, 1), parsed.get("roles").?.values.items[0].enumeration);
    try std.testing.expectEqual(@as(i32, 1), parsed.get("roles").?.values.items[1].enumeration);
    try std.testing.expectEqual(@as(usize, 1), parsed.get("keyed").?.values.items.len);
    try std.testing.expectEqualSlices(u8, "ok", parsed.get("keyed").?.values.items[0].map_entry.key.string);
}

test "json ignore unknown fields skips imported enum names" {
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
        \\message Event {
        \\  common.Kind kind = 1;
        \\  repeated common.Kind roles = 2;
        \\  map<string, common.Kind> keyed = 3;
        \\}
    );
    defer app.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);
    const desc = app.findMessage("Event").?;

    var parsed = try parseAllocWithRegistry(allocator, &app, &registry, desc,
        \\{"kind":"BOGUS","roles":["ADMIN","BOGUS"],"keyed":{"ok":"ADMIN","bad":"BOGUS"}}
    , .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    try std.testing.expect(parsed.get("kind") == null);
    try std.testing.expectEqual(@as(usize, 1), parsed.get("roles").?.values.items.len);
    try std.testing.expectEqual(@as(i32, 1), parsed.get("roles").?.values.items[0].enumeration);
    try std.testing.expectEqual(@as(usize, 1), parsed.get("keyed").?.values.items.len);
    try std.testing.expectEqualStrings("ok", parsed.get("keyed").?.values.items[0].map_entry.key.string);
}

test "json parses and stringifies repeated and enum proto2 extensions" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host { extensions 100 to 200; }
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\extend Host {
        \\  repeated int32 scores = 100;
        \\  optional Kind role = 101;
        \\}
    );
    defer file.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);
    const desc = file.findMessage("Host").?;

    var parsed = try parseAllocWithRegistry(allocator, &file, &registry, desc, "{\"[demo.scores]\":[1,2],\"[demo.role]\":\"ADMIN\"}", .{});
    defer parsed.deinit();
    const scores = registry.findExtension("demo.Host", 100).?;
    const role = registry.findExtension("demo.Host", 101).?;
    try std.testing.expectEqual(@as(i32, 1), parsed.getByNumber(scores.number).?.values.items[0].int32);
    try std.testing.expectEqual(@as(i32, 2), parsed.getByNumber(scores.number).?.values.items[1].int32);
    try std.testing.expectEqual(@as(i32, 1), parsed.getByNumber(role.number).?.values.items[0].enumeration);

    const rendered = try stringifyAllocWithRegistry(allocator, &file, &registry, &parsed, .{});
    defer allocator.free(rendered);
    try std.testing.expectEqualSlices(u8, "{\"[demo.scores]\":[1,2],\"[demo.role]\":\"ADMIN\"}", rendered);
}

test "json parses and stringifies proto2 extension fields" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host { extensions 100 to 200; }
        \\extend Host { optional int32 tag = 100; }
    );
    defer file.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);
    const desc = file.findMessage("Host").?;

    var parsed = try parseAllocWithRegistry(allocator, &file, &registry, desc, "{\"[demo.tag]\":7}", .{});
    defer parsed.deinit();
    const ext = registry.findExtension("demo.Host", 100).?;
    try std.testing.expectEqual(@as(i32, 7), parsed.getByNumber(ext.number).?.values.items[0].int32);

    const rendered = try stringifyAllocWithRegistry(allocator, &file, &registry, &parsed, .{});
    defer allocator.free(rendered);
    try std.testing.expectEqualSlices(u8, "{\"[demo.tag]\":7}", rendered);

    var leaf = try parseAllocWithRegistry(allocator, &file, &registry, desc, "{\"[tag]\":8}", .{});
    defer leaf.deinit();
    try std.testing.expectEqual(@as(i32, 8), leaf.getByNumber(ext.number).?.values.items[0].int32);
}

test "json parses and stringifies proto2 group extensions" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
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
    );
    defer file.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);
    const desc = file.findMessage("Host").?;
    const box = registry.findExtension("demo.Host", 100).?;
    const item = registry.findExtension("demo.Host", 103).?;

    var parsed = try parseAllocWithRegistry(allocator, &file, &registry, desc,
        \\{"id":1,"[demo.box]":{"a":7,"label":"seven"},"[demo.item]":[{"a":1},{"a":2}]}
    , .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(i32, 1), parsed.get("id").?.values.items[0].int32);
    const parsed_box = parsed.getByNumber(box.number).?.values.items[0].group;
    try std.testing.expectEqual(@as(i32, 7), parsed_box.get("a").?.values.items[0].int32);
    try std.testing.expectEqualSlices(u8, "seven", parsed_box.get("label").?.values.items[0].string);
    const parsed_items = parsed.getByNumber(item.number).?.values.items;
    try std.testing.expectEqual(@as(usize, 2), parsed_items.len);
    try std.testing.expectEqual(@as(i32, 1), parsed_items[0].group.get("a").?.values.items[0].int32);
    try std.testing.expectEqual(@as(i32, 2), parsed_items[1].group.get("a").?.values.items[0].int32);

    const rendered = try stringifyAllocWithRegistry(allocator, &file, &registry, &parsed, .{});
    defer allocator.free(rendered);
    try std.testing.expectEqualSlices(u8,
        \\{"id":1,"[demo.box]":{"a":7,"label":"seven"},"[demo.item]":[{"a":1},{"a":2}]}
    , rendered);

    var leaf = try parseAllocWithRegistry(allocator, &file, &registry, desc, "{\"[box]\":{\"a\":9}}", .{});
    defer leaf.deinit();
    try std.testing.expectEqual(@as(i32, 9), leaf.getByNumber(box.number).?.values.items[0].group.get("a").?.values.items[0].int32);
}

test "json registry extension lookup distinguishes same leaf message names" {
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

    try std.testing.expectError(error.UnknownField, parseAllocWithRegistry(allocator, &b_file, &registry, b_file.findMessage("Host").?, "{\"[a.note]\":\"wrong-host\"}", .{}));

    var a_msg = try parseAllocWithRegistry(allocator, &a_file, &registry, a_file.findMessage("Host").?, "{\"[a.note]\":\"right-host\"}", .{});
    defer a_msg.deinit();
    try std.testing.expectEqualStrings("right-host", a_msg.get("note").?.values.items[0].string);
}

test "json parses and stringifies scoped proto2 extensions" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host { extensions 100 to 200; }
        \\message Scope { extend Host { optional string tag = 100; } }
    );
    defer file.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);
    const desc = file.findMessage("Host").?;
    const ext = registry.findExtensionByName("demo.Host", "demo.Scope.tag").?;

    var parsed = try parseAllocWithRegistry(allocator, &file, &registry, desc, "{\"[demo.Scope.tag]\":\"scoped\"}", .{});
    defer parsed.deinit();
    try std.testing.expectEqualSlices(u8, "scoped", parsed.getByNumber(ext.number).?.values.items[0].string);

    const rendered = try stringifyAllocWithRegistry(allocator, &file, &registry, &parsed, .{});
    defer allocator.free(rendered);
    try std.testing.expectEqualSlices(u8, "{\"[demo.Scope.tag]\":\"scoped\"}", rendered);
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

test "json parser rejects alternate spelling and oneof duplicate fields" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\message Child { int32 id = 1; string name = 2; }
        \\message Names {
        \\  int32 user_id = 1;
        \\  repeated string tag_list = 2;
        \\  map<string, int32> count_map = 3;
        \\  Child child_msg = 4;
        \\  oneof choice { int32 choice_id = 5; string choice_text = 7; }
        \\  string explicit_name = 6 [json_name = "shownName"];
        \\}
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("Names").?;

    try std.testing.expectError(error.DuplicateField, parseAlloc(allocator, &file, desc, "{\"user_id\":1,\"userId\":2}", .{}));
    try std.testing.expectError(error.DuplicateField, parseAlloc(allocator, &file, desc, "{\"tag_list\":[\"a\"],\"tagList\":[\"b\"]}", .{}));
    try std.testing.expectError(error.DuplicateField, parseAlloc(allocator, &file, desc, "{\"count_map\":{\"a\":1},\"countMap\":{\"b\":2}}", .{}));
    try std.testing.expectError(error.DuplicateField, parseAlloc(allocator, &file, desc, "{\"child_msg\":{\"id\":1},\"childMsg\":{\"name\":\"two\"}}", .{}));
    try std.testing.expectError(error.DuplicateField, parseAlloc(allocator, &file, desc, "{\"choice_id\":7,\"choiceId\":8}", .{}));
    try std.testing.expectError(error.DuplicateField, parseAlloc(allocator, &file, desc, "{\"choiceId\":7,\"choiceText\":\"text\"}", .{}));
    try std.testing.expectError(error.DuplicateField, parseAlloc(allocator, &file, desc, "{\"choice_id\":7,\"shownName\":\"json\",\"explicit_name\":\"proto\"}", .{}));
}

test "json round-trips proto3 optional message fields" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\message Child { int32 id = 1; }
        \\message Parent { optional Child child = 1; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const parent_desc = file.findMessage("Parent").?;
    const child_desc = file.findMessage("Child").?;
    const child_field = parent_desc.findField("child").?;

    var absent = dynamic.DynamicMessage.init(allocator, parent_desc);
    defer absent.deinit();
    const absent_json = try stringifyAlloc(allocator, &file, &absent, .{});
    defer allocator.free(absent_json);
    try std.testing.expectEqualSlices(u8, "{}", absent_json);

    var present = dynamic.DynamicMessage.init(allocator, parent_desc);
    defer present.deinit();
    const child = try allocator.create(dynamic.DynamicMessage);
    child.* = dynamic.DynamicMessage.init(allocator, child_desc);
    try child.add(child_desc.findField("id").?, .{ .int32 = 7 });
    try present.add(child_field, .{ .message = child });
    const present_json = try stringifyAlloc(allocator, &file, &present, .{});
    defer allocator.free(present_json);
    try std.testing.expectEqualSlices(u8, "{\"child\":{\"id\":7}}", present_json);

    var parsed = try parseAlloc(allocator, &file, parent_desc, "{\"child\":{}}", .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.has(child_field));
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
        \\  optional double pos_inf = 9 [default = inf];
        \\  optional double neg_inf = 10 [default = -inf];
        \\  optional float quiet_nan = 11 [default = nan];
        \\  optional float neg_nan = 12 [default = -nan];
        \\  optional double pos_infinity = 13 [default = Infinity];
        \\  optional double neg_infinity = 14 [default = -INFINITY];
        \\  optional uint64 max_u64 = 15 [default = 0xFFFFFFFFFFFFFFFF];
        \\}
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("Defaults").?;

    var msg = dynamic.DynamicMessage.init(allocator, desc);
    defer msg.deinit();
    const rendered = try stringifyAlloc(allocator, &file, &msg, .{ .always_print_primitive_fields = true });
    defer allocator.free(rendered);
    try std.testing.expectEqualSlices(u8, "{\"count\":42,\"name\":\"anon\",\"enabled\":true,\"kind\":\"ADMIN\",\"tags\":[],\"counts\":{},\"raw\":\"aGk=\",\"big\":\"9007199254740993\",\"posInf\":\"Infinity\",\"negInf\":\"-Infinity\",\"quietNan\":\"NaN\",\"negNan\":\"NaN\",\"posInfinity\":\"Infinity\",\"negInfinity\":\"-Infinity\",\"maxU64\":\"18446744073709551615\"}", rendered);
}

test "json stringify prints imported enum defaults with registry" {
    const allocator = std.testing.allocator;
    var common = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package common;
        \\enum Kind { UNKNOWN = 0; ADMIN = 7; }
    );
    defer common.deinit();
    common.name = "common.proto";
    var app = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package app;
        \\import "common.proto";
        \\message Event {
        \\  optional common.Kind kind = 1 [default = ADMIN];
        \\}
    );
    defer app.deinit();
    app.name = "app.proto";
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);
    try registry.validateAllFileReferences();

    var msg = dynamic.DynamicMessage.init(allocator, app.findMessage("Event").?);
    defer msg.deinit();
    const rendered = try stringifyAllocWithRegistry(allocator, &app, &registry, &msg, .{ .always_print_primitive_fields = true });
    defer allocator.free(rendered);
    try std.testing.expectEqualSlices(u8, "{\"kind\":\"ADMIN\"}", rendered);

    const rendered_number = try stringifyAllocWithRegistry(allocator, &app, &registry, &msg, .{ .always_print_primitive_fields = true, .enum_as_name = false });
    defer allocator.free(rendered_number);
    try std.testing.expectEqualSlices(u8, "{\"kind\":7}", rendered_number);
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

    var url_safe_short = try parseAlloc(allocator, &file, desc, "{\"raw\":\"-_\"}", .{});
    defer url_safe_short.deinit();
    try std.testing.expectEqualSlices(u8, &.{0xfb}, url_safe_short.get("raw").?.values.items[0].bytes);
}

test "json string escape scanner distinguishes fast and escaped paths" {
    try std.testing.expect(!jsonStringNeedsEscape("plain ascii and 世界"));
    try std.testing.expect(jsonStringNeedsEscape("quote\""));
    try std.testing.expect(jsonStringNeedsEscape("slash\\"));
    try std.testing.expect(jsonStringNeedsEscape("line\n"));
}

test "json accepts unquoted integral float spellings for 32-bit integers" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\message Numbers { int32 i32 = 1; uint32 u32 = 2; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("Numbers").?;

    var parsed = try parseAlloc(allocator, &file, desc, "{\"i32\":1e5,\"u32\":4.294967295e9}", .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(i32, 100000), parsed.get("i32").?.values.items[0].int32);
    try std.testing.expectEqual(@as(u32, 4294967295), parsed.get("u32").?.values.items[0].uint32);

    // Quoted integer fields intentionally remain decimal-only strings. This
    // mirrors C++/Go protobuf JSON: numeric exponent compatibility applies to
    // numeric tokens, not to arbitrary quoted strings.
    try std.testing.expectError(error.InvalidCharacter, parseAlloc(allocator, &file, desc, "{\"i32\":\"1e5\"}", .{}));

    try std.testing.expectError(error.TypeMismatch, parseAlloc(allocator, &file, desc, "{\"i32\":1.5}", .{}));
}

test "json omits proto3 implicit default scalar fields" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\message Defaults {
        \\  int32 count = 1;
        \\  string name = 2;
        \\  bool enabled = 3;
        \\  optional int32 present = 4;
        \\}
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("Defaults").?;

    var parsed = try parseAlloc(allocator, &file, desc, "{\"count\":0,\"name\":\"\",\"enabled\":false,\"present\":0}", .{});
    defer parsed.deinit();
    const rendered = try stringifyAlloc(allocator, &file, &parsed, .{});
    defer allocator.free(rendered);
    try std.testing.expectEqualSlices(u8, "{\"present\":0}", rendered);
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
    try std.testing.expectEqualSlices(u8, "{\"at\":\"2020-01-01T00:00:00.123Z\",\"span\":\"-3.250s\"}", rendered);

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
        \\message Any { optional string type_url = 1; optional bytes value = 2; }
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

    const bad_any = try allocator.create(dynamic.DynamicMessage);
    bad_any.* = dynamic.DynamicMessage.init(allocator, any_desc);
    try bad_any.add(any_desc.findField("value").?, .{ .bytes = try allocator.dupe(u8, "abc") });
    var bad_holder = dynamic.DynamicMessage.init(allocator, holder_desc);
    defer bad_holder.deinit();
    try bad_holder.add(holder_desc.findField("any").?, .{ .message = bad_any });
    try std.testing.expectError(error.TypeMismatch, stringifyAlloc(allocator, &file, &bad_holder, .{}));
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

    const bad_mask = try allocator.create(dynamic.DynamicMessage);
    bad_mask.* = dynamic.DynamicMessage.init(allocator, mask_desc);
    try bad_mask.add(mask_desc.findField("paths").?, .{ .string = try allocator.dupe(u8, "foo_1") });
    var bad_holder = dynamic.DynamicMessage.init(allocator, holder_desc);
    defer bad_holder.deinit();
    try bad_holder.add(holder_desc.findField("mask").?, .{ .message = bad_mask });
    try std.testing.expectError(error.InvalidFieldMask, stringifyAlloc(allocator, &file, &bad_holder, .{}));
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
    try std.testing.expectError(error.UnknownField, parseAlloc(allocator, &file, holder_desc, "{\"empty\":{\"x\":1}}", .{}));
}

test "json parses Any message with type and base64 value" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\package google.protobuf;
        \\message Any { optional string type_url = 1; optional bytes value = 2; }
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

    var empty_any = try parseAlloc(allocator, &file, holder_desc, "{\"any\":{\"value\":\"YWJj\"}}", .{});
    defer empty_any.deinit();
    try std.testing.expectEqualSlices(u8, "abc", empty_any.get("any").?.values.items[0].message.get("value").?.values.items[0].bytes);
    try std.testing.expectError(error.TypeMismatch, parseAlloc(allocator, &file, holder_desc, "{\"any\":{\"@type\":\"\",\"value\":\"YWJj\"}}", .{}));
    try std.testing.expectError(error.TypeMismatch, parseAlloc(allocator, &file, holder_desc, "{\"any\":{\"@type\":\"type.googleapis.com/\",\"value\":\"YWJj\"}}", .{}));
    try std.testing.expectError(error.TypeMismatch, parseAlloc(allocator, &file, holder_desc, "{\"any\":{\"@type\":\"type.googleapis.com/unknown.Msg\"}}", .{}));
}

test "json expands Any message payloads when type is known" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\package demo;
        \\message Msg { int32 id = 1; string label = 2; }
        \\message Any { optional string type_url = 1; optional bytes value = 2; }
        \\message Holder { .google.protobuf.Any any = 1; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const holder_desc = file.findMessage("Holder").?;
    const any_desc = file.findMessage("Any").?;
    const msg_desc = file.findMessage("Msg").?;

    var payload = dynamic.DynamicMessage.init(allocator, msg_desc);
    defer payload.deinit();
    try payload.add(msg_desc.findField("id").?, .{ .int32 = 7 });
    try payload.add(msg_desc.findField("label").?, .{ .string = try allocator.dupe(u8, "known") });
    const payload_bytes = try payload.encodedDeterministic(&file);
    defer allocator.free(payload_bytes);

    var holder = dynamic.DynamicMessage.init(allocator, holder_desc);
    defer holder.deinit();
    const any_msg = try allocator.create(dynamic.DynamicMessage);
    any_msg.* = dynamic.DynamicMessage.init(allocator, any_desc);
    try any_msg.add(any_desc.findField("type_url").?, .{ .string = try allocator.dupe(u8, "type.googleapis.com/demo.Msg") });
    try any_msg.add(any_desc.findField("value").?, .{ .bytes = try allocator.dupe(u8, payload_bytes) });
    try holder.add(holder_desc.findField("any").?, .{ .message = any_msg });

    const rendered = try stringifyAlloc(allocator, &file, &holder, .{});
    defer allocator.free(rendered);
    try std.testing.expectEqualSlices(u8, "{\"any\":{\"@type\":\"type.googleapis.com/demo.Msg\",\"id\":7,\"label\":\"known\"}}", rendered);

    try std.testing.expectError(error.UnknownField, parseAlloc(allocator, &file, holder_desc, "{\"any\":{\"@type\":\"type.googleapis.com/demo.Msg\",\"value\":\"AA==\",\"id\":8}}", .{}));

    var parsed = try parseAlloc(allocator, &file, holder_desc, "{\"any\":{\"@type\":\"type.googleapis.com/demo.Msg\",\"id\":8,\"label\":\"parsed\"}}", .{});
    defer parsed.deinit();
    const parsed_any = parsed.get("any").?.values.items[0].message;
    const parsed_value = parsed_any.get("value").?.values.items[0].bytes;
    var decoded_payload = dynamic.DynamicMessage.init(allocator, msg_desc);
    defer decoded_payload.deinit();
    try decoded_payload.decode(&file, parsed_value);
    try std.testing.expectEqual(@as(i32, 8), decoded_payload.get("id").?.values.items[0].int32);
    try std.testing.expectEqualSlices(u8, "parsed", decoded_payload.get("label").?.values.items[0].string);

    var empty_any = try parseAlloc(allocator, &file, holder_desc, "{\"any\":{}}", .{});
    defer empty_any.deinit();
    const empty_rendered = try stringifyAlloc(allocator, &file, &empty_any, .{});
    defer allocator.free(empty_rendered);
    try std.testing.expectEqualSlices(u8, "{\"any\":{}}", empty_rendered);
}

test "json parses Any value envelopes for well-known payloads" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\package google.protobuf;
        \\enum NullValue { NULL_VALUE = 0; }
        \\message Any { string type_url = 1; bytes value = 2; }
        \\message Int32Value { int32 value = 1; }
        \\message Timestamp { int64 seconds = 1; int32 nanos = 2; }
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
        \\message Holder { .google.protobuf.Any any = 1; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const holder_desc = file.findMessage("Holder").?;
    const int_desc = file.findMessage("Int32Value").?;
    const ts_desc = file.findMessage("Timestamp").?;
    const struct_desc = file.findMessage("Struct").?;

    var parsed_int = try parseAlloc(allocator, &file, holder_desc, "{\"any\":{\"@type\":\"type.googleapis.com/google.protobuf.Int32Value\",\"value\":12345}}", .{});
    defer parsed_int.deinit();
    var decoded_int = dynamic.DynamicMessage.init(allocator, int_desc);
    defer decoded_int.deinit();
    try decoded_int.decode(&file, parsed_int.get("any").?.values.items[0].message.get("value").?.values.items[0].bytes);
    try std.testing.expectEqual(@as(i32, 12345), decoded_int.get("value").?.values.items[0].int32);
    const rendered_int = try stringifyAlloc(allocator, &file, &parsed_int, .{});
    defer allocator.free(rendered_int);
    try std.testing.expectEqualSlices(u8, "{\"any\":{\"@type\":\"type.googleapis.com/google.protobuf.Int32Value\",\"value\":12345}}", rendered_int);

    var parsed_ts = try parseAlloc(allocator, &file, holder_desc, "{\"any\":{\"@type\":\"type.googleapis.com/google.protobuf.Timestamp\",\"value\":\"1970-01-01T00:00:00Z\"}}", .{});
    defer parsed_ts.deinit();
    var decoded_ts = dynamic.DynamicMessage.init(allocator, ts_desc);
    defer decoded_ts.deinit();
    try decoded_ts.decode(&file, parsed_ts.get("any").?.values.items[0].message.get("value").?.values.items[0].bytes);
    try std.testing.expect(decoded_ts.get("seconds") == null);
    const rendered_ts = try stringifyAlloc(allocator, &file, &parsed_ts, .{});
    defer allocator.free(rendered_ts);
    try std.testing.expectEqualSlices(u8, "{\"any\":{\"@type\":\"type.googleapis.com/google.protobuf.Timestamp\",\"value\":\"1970-01-01T00:00:00Z\"}}", rendered_ts);

    var parsed_struct = try parseAlloc(allocator, &file, holder_desc, "{\"any\":{\"@type\":\"type.googleapis.com/google.protobuf.Struct\",\"value\":{\"foo\":1}}}", .{});
    defer parsed_struct.deinit();
    var decoded_struct = dynamic.DynamicMessage.init(allocator, struct_desc);
    defer decoded_struct.deinit();
    try decoded_struct.decode(&file, parsed_struct.get("any").?.values.items[0].message.get("value").?.values.items[0].bytes);
    try std.testing.expectEqual(@as(usize, 1), decoded_struct.get("fields").?.values.items.len);
    const rendered_struct = try stringifyAlloc(allocator, &file, &parsed_struct, .{});
    defer allocator.free(rendered_struct);
    try std.testing.expectEqualSlices(u8, "{\"any\":{\"@type\":\"type.googleapis.com/google.protobuf.Struct\",\"value\":{\"foo\":1}}}", rendered_struct);

    try std.testing.expectError(error.TypeMismatch, parseAlloc(allocator, &file, holder_desc, "{\"any\":{\"@type\":\"not_a_url\",\"value\":\"\"}}", .{}));
}

test "json initialized parse validates expanded Any payloads" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto2";
        \\package demo;
        \\message Msg { required int32 id = 1; }
        \\message Any { optional string type_url = 1; optional bytes value = 2; }
        \\message Holder { optional .google.protobuf.Any any = 1; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const holder_desc = file.findMessage("Holder").?;

    var parsed = try parseAlloc(allocator, &file, holder_desc, "{\"any\":{\"@type\":\"type.googleapis.com/demo.Msg\"}}", .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.get("any").?.values.items[0].message.get("value") != null);

    try std.testing.expectError(error.MissingRequiredField, parseInitializedAlloc(allocator, &file, holder_desc, "{\"any\":{\"@type\":\"type.googleapis.com/demo.Msg\"}}", .{}));
    var initialized = try parseInitializedAlloc(allocator, &file, holder_desc, "{\"any\":{\"@type\":\"type.googleapis.com/demo.Msg\",\"id\":7}}", .{});
    defer initialized.deinit();
    const any_msg = initialized.get("any").?.values.items[0].message;
    const payload = any_msg.get("value").?.values.items[0].bytes;
    var decoded = dynamic.DynamicMessage.init(allocator, file.findMessage("Msg").?);
    defer decoded.deinit();
    try decoded.decodeInitialized(&file, payload);
    try std.testing.expectEqual(@as(i32, 7), decoded.get("id").?.values.items[0].int32);
}

test "json expands Any payloads using registry imports" {
    const allocator = std.testing.allocator;
    var common = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package common;
        \\message Payload { int32 id = 1; string label = 2; }
    );
    defer common.deinit();
    var app = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package app;
        \\import "common.proto";
        \\message Any { optional string type_url = 1; optional bytes value = 2; }
        \\message Holder { .google.protobuf.Any any = 1; }
    );
    defer app.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    common.name = "common.proto";
    app.name = "app.proto";
    try registry.addFile(&common);
    try registry.addFile(&app);

    const holder_desc = app.findMessage("Holder").?;
    const any_desc = app.findMessage("Any").?;
    const payload_desc = common.findMessage("Payload").?;

    var payload = dynamic.DynamicMessage.init(allocator, payload_desc);
    defer payload.deinit();
    try payload.add(payload_desc.findField("id").?, .{ .int32 = 7 });
    try payload.add(payload_desc.findField("label").?, .{ .string = try allocator.dupe(u8, "known") });
    const payload_bytes = try payload.encodedDeterministic(&common);
    defer allocator.free(payload_bytes);

    var holder = dynamic.DynamicMessage.init(allocator, holder_desc);
    defer holder.deinit();
    const any_msg = try allocator.create(dynamic.DynamicMessage);
    any_msg.* = dynamic.DynamicMessage.init(allocator, any_desc);
    try any_msg.add(any_desc.findField("type_url").?, .{ .string = try allocator.dupe(u8, "type.googleapis.com/common.Payload") });
    try any_msg.add(any_desc.findField("value").?, .{ .bytes = try allocator.dupe(u8, payload_bytes) });
    try holder.add(holder_desc.findField("any").?, .{ .message = any_msg });

    const rendered = try stringifyAllocWithRegistry(allocator, &app, &registry, &holder, .{});
    defer allocator.free(rendered);
    try std.testing.expectEqualSlices(u8, "{\"any\":{\"@type\":\"type.googleapis.com/common.Payload\",\"id\":7,\"label\":\"known\"}}", rendered);

    var parsed = try parseAllocWithRegistry(allocator, &app, &registry, holder_desc, "{\"any\":{\"@type\":\"type.googleapis.com/common.Payload\",\"id\":8,\"label\":\"parsed\"}}", .{});
    defer parsed.deinit();
    const parsed_any = parsed.get("any").?.values.items[0].message;
    const parsed_value = parsed_any.get("value").?.values.items[0].bytes;
    var decoded_payload = dynamic.DynamicMessage.init(allocator, payload_desc);
    defer decoded_payload.deinit();
    try decoded_payload.decodeWithRegistry(&common, &registry, parsed_value);
    try std.testing.expectEqual(@as(i32, 8), decoded_payload.get("id").?.values.items[0].int32);
    try std.testing.expectEqualSlices(u8, "parsed", decoded_payload.get("label").?.values.items[0].string);
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

    const holder_value_source =
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
        \\message HolderValue { .google.protobuf.Value value = 1; }
    ;
    var value_file = try @import("parser.zig").Parser.parse(allocator, holder_value_source);
    defer value_file.deinit();
    const holder_value_desc = value_file.findMessage("HolderValue").?;
    var parsed_null = try parseAlloc(allocator, &value_file, holder_value_desc, "{\"value\":null}", .{});
    defer parsed_null.deinit();
    const value_msg = parsed_null.get("value").?.values.items[0].message;
    try std.testing.expect(value_msg.get("null_value") != null);

    var bad_holder = dynamic.DynamicMessage.init(allocator, holder_value_desc);
    defer bad_holder.deinit();
    const bad_value = try allocator.create(dynamic.DynamicMessage);
    bad_value.* = dynamic.DynamicMessage.init(allocator, value_file.findMessage("Value").?);
    try bad_value.add(value_file.findMessage("Value").?.findField("number_value").?, .{ .double = std.math.inf(f64) });
    try bad_holder.add(holder_value_desc.findField("value").?, .{ .message = bad_value });
    try std.testing.expectError(error.InvalidNumber, stringifyAlloc(allocator, &value_file, &bad_holder, .{}));
}
