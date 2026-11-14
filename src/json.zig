const std = @import("std");

const wire = @import("wire.zig");

const schema = @import("schema.zig");

const dynamic = @import("dynamic.zig");

const wkt = @import("wkt.zig");

const registry_mod = @import("registry.zig");

const json_tree = @import("json_value.zig");

/// Lean JSON value tree shared with generated code. See `json_value.zig`.
pub const Value = json_tree.Value;

/// Parse a complete JSON document into a `Value` tree.
pub const parseValueTree = json_tree.parse;

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
pub fn intValue(comptime T: type, json_value: Value) !T {
    switch (json_value) {
        .integer => |value| {
            if (value < std.math.minInt(T) or value > std.math.maxInt(T)) return error.Overflow;
            return @intCast(value);
        },
        .float => |value| return try floatAsInt(T, value),
        .number_string => |value| return try intText(T, value),
        .string => |value| return try intText(T, value),
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
    // Parse the DOM in a dedicated arena: the tree is append-only and the
    // message copies every string/key it keeps, so one arena release is both
    // faster and simpler than freeing each DOM node individually.
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const parsed = try parseValueTree(arena.allocator(), bytes, .{});

    var message = dynamic.DynamicMessage.init(allocator, descriptor);
    errdefer message.deinit();
    try fillMessageWithRegistry(allocator, file, registry, &message, parsed, options);
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
    json_value: Value,
    options: Options,
) anyerror!void {
    try fillMessageWithRegistry(allocator, file, null, message, json_value, options);
}

pub fn fillMessageWithRegistry(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    registry: ?*const registry_mod.Registry,
    message: *dynamic.DynamicMessage,
    json_value: Value,
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
    object: Value.Object,
    options: Options,
    skip_type_field: bool,
) anyerror!void {
    var seen_fields: std.ArrayList(wire.FieldNumber) = .empty;
    defer seen_fields.deinit(allocator);
    var it = object.iterator();
    while (it.next()) |entry| {
        if (skip_type_field and std.mem.eql(u8, entry.key, "@type")) continue;
        const field = findJsonField(file, registry, message.descriptor, entry.key, options) orelse {
            if (options.ignore_unknown_fields) continue;
            return error.UnknownField;
        };
        const field_file = registry_mod.fieldDefiningFile(file, registry, field);
        if (entry.value == .null and jsonNullSkipsField(field_file, registry, message.descriptor, field)) continue;
        if (seenJsonField(seen_fields.items, field.number)) return error.DuplicateField;
        if (field.oneof_name) |oneof_name| {
            if (seenJsonOneof(seen_fields.items, message.descriptor, oneof_name, field.number)) return error.DuplicateField;
        }
        try seen_fields.append(allocator, field.number);
        if (field.kind == .map) {
            try parseMapField(allocator, field_file, registry, message, field, entry.value, options);
        } else if (field.cardinality == .repeated) {
            const array = switch (entry.value) {
                .array => |array| array,
                else => return error.TypeMismatch,
            };
            for (array.items) |item| {
                const value = parseValue(allocator, field_file, registry, message.descriptor, field.kind, item, options) catch |err| {
                    if (shouldIgnoreEnumParseError(options, field_file, registry, message.descriptor, field.kind, err)) continue;
                    return err;
                };
                try addOwnedValue(allocator, message, field, value);
            }
        } else {
            const value = parseValue(allocator, field_file, registry, message.descriptor, field.kind, entry.value, options) catch |err| {
                if (shouldIgnoreEnumParseError(options, field_file, registry, message.descriptor, field.kind, err)) continue;
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
    json_value: Value,
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
        var key = try parseMapKey(allocator, map_type.key, entry.key);
        var owns_key = true;
        errdefer if (owns_key) dynamic.deinitValue(&key, allocator);
        var map_value = parseValue(allocator, file, registry, message.descriptor, map_type.value.*, entry.value, options) catch |err| {
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
    json_value: Value,
    options: Options,
) anyerror!dynamic.Value {
    return switch (kind) {
        .scalar => |scalar| try parseScalar(allocator, scalar, json_value),
        .enumeration => |name| try parseEnumWithRegistry(file, registry, current, name, json_value),
        .message => |name| blk: {
            if (registryEnumDescriptor(file, registry, current, name)) |_| break :blk try parseEnumWithRegistry(file, registry, current, name, json_value);
            const descriptor = resolveMessageDescriptorWithRegistry(file, registry, current, name) orelse return error.TypeMismatch;
            const descriptor_file = registry_mod.messageDefiningFile(file, registry, descriptor);
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
            const descriptor_file = registry_mod.messageDefiningFile(file, registry, descriptor);
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

fn parseScalar(allocator: std.mem.Allocator, scalar: schema.ScalarType, json_value: Value) !dynamic.Value {
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

fn parseEnumWithRegistry(file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, current: *const schema.MessageDescriptor, name: []const u8, json_value: Value) !dynamic.Value {
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

fn numberAsInt(comptime T: type, json_value: Value) !T {
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

fn numberAsFloat(comptime T: type, json_value: Value) !T {
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

pub fn decodeBase64(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    // Locate padding first; protobuf JSON accepts both base64 and base64url
    // alphabets with optional padding.
    const pad_start = std.mem.indexOfScalar(u8, value, '=') orelse value.len;
    const padding = value.len - pad_start;
    if (padding > 2) return error.InvalidPadding;
    if (padding != 0) {
        for (value[pad_start..]) |byte| {
            if (byte != '=') return error.InvalidPadding;
        }
        const expected: usize = switch (pad_start % 4) {
            0 => 0,
            2 => 2,
            3 => 1,
            else => return error.InvalidPadding,
        };
        if (padding != expected) return error.InvalidPadding;
    } else if (pad_start % 4 == 1) {
        // Keep invalid-character errors distinct from padding errors.
        for (value[0..pad_start]) |byte| {
            if (base64_decode_table[byte] == 0xff) return error.InvalidCharacter;
        }
        return error.InvalidPadding;
    }
    const out = try allocator.alloc(u8, (pad_start * 6) / 8);
    errdefer allocator.free(out);
    var out_index: usize = 0;
    var index: usize = 0;
    while (index + 4 <= pad_start) : (index += 4) {
        const a: u32 = base64_decode_table[value[index]];
        const b: u32 = base64_decode_table[value[index + 1]];
        const c: u32 = base64_decode_table[value[index + 2]];
        const d: u32 = base64_decode_table[value[index + 3]];
        if ((a | b | c | d) & 0xc0 != 0) return error.InvalidCharacter;
        out[out_index] = @truncate((a << 2) | (b >> 4));
        out[out_index + 1] = @truncate((b << 4) | (c >> 2));
        out[out_index + 2] = @truncate((c << 6) | d);
        out_index += 3;
    }
    const remaining = pad_start - index;
    if (remaining >= 1) {
        const a: u32 = base64_decode_table[value[index]];
        const b: u32 = base64_decode_table[value[index + 1]];
        if ((a | b) & 0xc0 != 0) return error.InvalidCharacter;
        out[out_index] = @truncate((a << 2) | (b >> 4));
        out_index += 1;
        if (remaining == 3) {
            const c: u32 = base64_decode_table[value[index + 2]];
            if (c & 0xc0 != 0) return error.InvalidCharacter;
            out[out_index] = @truncate((b << 4) | (c >> 2));
            out_index += 1;
        }
    }
    std.debug.assert(out_index == out.len);
    return out;
}

const base64_decode_table = blk: {
    @setEvalBranchQuota(4000);
    var table = [_]u8{0xff} ** 256;
    for ('A'..'Z' + 1, 0..) |byte, i| table[byte] = @intCast(i);
    for ('a'..'z' + 1, 26..) |byte, i| table[byte] = @intCast(i);
    for ('0'..'9' + 1, 52..) |byte, i| table[byte] = @intCast(i);
    table['+'] = 62;
    table['-'] = 62;
    table['/'] = 63;
    table['_'] = 63;
    break :blk table;
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

fn enumIsClosed(file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, enumeration: *const schema.EnumDescriptor) bool {
    const enum_file = registry_mod.enumDefiningFile(file, registry, enumeration);
    return schema.FeatureSet.effective(enumeration.features, enum_file.features).enum_type == .closed;
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
        const field_file = registry_mod.fieldDefiningFile(file, registry, entry.descriptor);
        if (shouldSkipDefaultJsonField(field_file, registry, message.descriptor, entry)) continue;
        if (!first.*) try writer.writeAll(",");
        first.* = false;
        try writeFieldName(file, registry, entry.descriptor, options, writer);
        try writer.writeAll(":");
        if (entry.descriptor.kind == .map) {
            try writeMap(field_file, registry, message.descriptor, entry.descriptor, entry.values.items, options, writer);
        } else if (entry.descriptor.cardinality == .repeated) {
            try writer.writeAll("[");
            for (entry.values.items, 0..) |value, index| {
                if (index != 0) try writer.writeAll(",");
                try writeValue(field_file, registry, message.descriptor, entry.descriptor.kind, value, options, writer);
            }
            try writer.writeAll("]");
        } else {
            try writeValue(field_file, registry, message.descriptor, entry.descriptor.kind, entry.values.items[entry.values.items.len - 1], options, writer);
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
    return schema.FeatureSet.effective(field.features, file.features).field_presence != .implicit;
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
                const message_file = registry_mod.messageDefiningFile(file, registry, message.descriptor);
                if (!try writeKnownMessage(message_file, registry, name, message, options, writer)) {
                    try writeMessage(message_file, registry, message, options, writer);
                }
            },
            else => return error.TypeMismatch,
        },
        .group => switch (value) {
            .group => |message| try writeMessage(registry_mod.messageDefiningFile(file, registry, message.descriptor), registry, message, options, writer),
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

fn parseStructMessage(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, descriptor: *const schema.MessageDescriptor, json_value: Value) anyerror!*dynamic.DynamicMessage {
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
        const value_message = try parseValueMessage(allocator, file, value_desc, entry.value);
        var owns_value_message = true;
        errdefer if (owns_value_message) {
            value_message.deinit();
            allocator.destroy(value_message);
        };
        const key = try allocator.dupe(u8, entry.key);
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

fn parseListValueMessage(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, descriptor: *const schema.MessageDescriptor, json_value: Value) anyerror!*dynamic.DynamicMessage {
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

fn parseValueMessage(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, descriptor: *const schema.MessageDescriptor, json_value: Value) anyerror!*dynamic.DynamicMessage {
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

fn parseWrapperValue(allocator: std.mem.Allocator, kind: schema.FieldKind, json_value: Value) !dynamic.Value {
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
            const payload_file = registry_mod.messageDefiningFile(file, registry, descriptor);
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

fn parseKnownMessage(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, descriptor: *const schema.MessageDescriptor, name: []const u8, json_value: Value, options: Options) anyerror!?*dynamic.DynamicMessage {
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

/// Stringify a dynamic Any message using the canonical `{"@type":...}` form.
/// `stringifyAllocWithRegistry` treats the message as a normal object when
/// called directly; this wrapper routes through the Any field logic.
pub fn stringifyAnyAllocWithRegistry(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    registry: ?*const registry_mod.Registry,
    message: *const dynamic.DynamicMessage,
    options: Options,
) anyerror![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    if (!try writeKnownMessage(file, registry, "google.protobuf.Any", message, options, &out.writer)) return error.TypeMismatch;
    return try out.toOwnedSlice();
}

/// Parse a protobuf JSON Any object (`{"@type":...}`) into deterministic wire
/// bytes for the Any message. Generated code uses this because it has a
/// descriptor registry but no text-level Any entry point.
pub fn parseAnyWireAllocWithRegistry(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    registry: ?*const registry_mod.Registry,
    any_descriptor: *const schema.MessageDescriptor,
    json_value: Value,
    options: Options,
) anyerror![]u8 {
    const message = try parseAnyMessage(allocator, file, registry, any_descriptor, json_value, options);
    defer {
        message.deinit();
        allocator.destroy(message);
    }
    return try message.encodedDeterministicWithRegistry(file, registry);
}

fn parseAnyMessage(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, descriptor: *const schema.MessageDescriptor, json_value: Value, options: Options) anyerror!*dynamic.DynamicMessage {
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
                    if (!std.mem.eql(u8, entry.key, "@type") and !std.mem.eql(u8, entry.key, "value")) return error.UnknownField;
                }
                const payload_file = registry_mod.messageDefiningFile(file, registry, resolved);
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
                if (!std.mem.eql(u8, entry.key, "@type") and !std.mem.eql(u8, entry.key, "value")) return error.UnknownField;
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
        const payload_file = registry_mod.messageDefiningFile(file, registry, payload_desc_value);
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
        const package = registry_mod.fieldDefiningFile(file, registry, field).package;
        if (package.len != 0) {
            try writeJsonStringContents(package, writer);
            try writer.writeByte('.');
        }
        try writeJsonStringContents(full_name, writer);
    }
    try writer.writeAll("]\"");
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

/// Internal declarations exposed for the externalized test suite.
const __pbz_test_jsonStringNeedsEscape = jsonStringNeedsEscape;
pub const test_helpers = struct {
    pub const jsonStringNeedsEscape = __pbz_test_jsonStringNeedsEscape;
};

test {
    _ = @import("json_tests.zig");
}
