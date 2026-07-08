const std = @import("std");
const wire = @import("wire.zig");
const schema = @import("schema.zig");
const parser = @import("parser.zig");

pub const DecodeError = wire.Error || std.mem.Allocator.Error || error{TypeMismatch};
pub const EncodeError = wire.Error || std.mem.Allocator.Error || error{TypeMismatch};
pub const ValidationError = error{MissingRequiredField};

pub const MapEntry = struct {
    key: Value,
    value: Value,

    pub fn deinit(self: *MapEntry, allocator: std.mem.Allocator) void {
        deinitValue(&self.key, allocator);
        deinitValue(&self.value, allocator);
        self.* = undefined;
    }
};

pub const Value = union(enum) {
    double: f64,
    float: f32,
    int32: i32,
    int64: i64,
    uint32: u32,
    uint64: u64,
    sint32: i32,
    sint64: i64,
    fixed32: u32,
    fixed64: u64,
    sfixed32: i32,
    sfixed64: i64,
    boolean: bool,
    string: []u8,
    bytes: []u8,
    enumeration: i32,
    message: *DynamicMessage,
    group: *DynamicMessage,
    map_entry: *MapEntry,
};

pub const FieldValue = struct {
    descriptor: *const schema.FieldDescriptor,
    values: std.ArrayList(Value) = .empty,

    pub fn deinit(self: *FieldValue, allocator: std.mem.Allocator) void {
        for (self.values.items) |*value| deinitValue(value, allocator);
        self.values.deinit(allocator);
        self.* = undefined;
    }
};

pub const UnknownField = struct {
    number: wire.FieldNumber,
    wire_type: wire.WireType,
    data: []u8,

    pub fn deinit(self: *UnknownField, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
        self.* = undefined;
    }
};

pub const DynamicMessage = struct {
    allocator: std.mem.Allocator,
    descriptor: *const schema.MessageDescriptor,
    fields: std.ArrayList(FieldValue) = .empty,
    unknown_fields: std.ArrayList(UnknownField) = .empty,

    pub fn init(allocator: std.mem.Allocator, descriptor: *const schema.MessageDescriptor) DynamicMessage {
        return .{ .allocator = allocator, .descriptor = descriptor };
    }

    pub fn deinit(self: *DynamicMessage) void {
        for (self.fields.items) |*field| field.deinit(self.allocator);
        self.fields.deinit(self.allocator);
        for (self.unknown_fields.items) |*field| field.deinit(self.allocator);
        self.unknown_fields.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn clear(self: *DynamicMessage) void {
        for (self.fields.items) |*field| field.deinit(self.allocator);
        self.fields.clearRetainingCapacity();
        for (self.unknown_fields.items) |*field| field.deinit(self.allocator);
        self.unknown_fields.clearRetainingCapacity();
    }

    pub fn get(self: *const DynamicMessage, name: []const u8) ?*const FieldValue {
        for (self.fields.items) |*field| {
            if (std.mem.eql(u8, field.descriptor.name, name)) return field;
        }
        return null;
    }

    pub fn getByNumber(self: *const DynamicMessage, number: wire.FieldNumber) ?*const FieldValue {
        for (self.fields.items) |*field| {
            if (field.descriptor.number == number) return field;
        }
        return null;
    }

    pub fn unknownCount(self: *const DynamicMessage) usize {
        return self.unknown_fields.items.len;
    }

    pub fn unknownByNumber(self: *const DynamicMessage, number: wire.FieldNumber) []const UnknownField {
        var first: ?usize = null;
        var last: usize = 0;
        for (self.unknown_fields.items, 0..) |field, index| {
            if (field.number == number) {
                if (first == null) first = index;
                last = index + 1;
            } else if (first != null) break;
        }
        return if (first) |start| self.unknown_fields.items[start..last] else &.{};
    }

    pub fn clearUnknownFields(self: *DynamicMessage) void {
        for (self.unknown_fields.items) |*field| field.deinit(self.allocator);
        self.unknown_fields.clearRetainingCapacity();
    }

    pub fn add(self: *DynamicMessage, field: *const schema.FieldDescriptor, value: Value) std.mem.Allocator.Error!void {
        if (field.oneof_name) |oneof_name| self.clearOneofExcept(oneof_name, field.number);
        var entry = try self.getOrCreateMutable(field);
        if (!field.isRepeatedLike() and entry.values.items.len != 0) {
            deinitValue(&entry.values.items[0], self.allocator);
            entry.values.items.len = 0;
        }
        try entry.values.append(self.allocator, value);
    }

    pub fn addClone(self: *DynamicMessage, field: *const schema.FieldDescriptor, value: Value) std.mem.Allocator.Error!void {
        try self.add(field, try cloneValue(self.allocator, value));
    }

    pub fn whichOneof(self: *const DynamicMessage, oneof_name: []const u8) ?*const schema.FieldDescriptor {
        for (self.fields.items) |*entry| {
            if (entry.values.items.len == 0) continue;
            if (entry.descriptor.oneof_name) |name| {
                if (std.mem.eql(u8, name, oneof_name)) return entry.descriptor;
            }
        }
        return null;
    }

    pub fn validateRequired(self: *const DynamicMessage) ValidationError!void {
        for (self.descriptor.fields.items) |*field| {
            if (field.cardinality == .required and self.getByNumber(field.number) == null) return error.MissingRequiredField;
        }
        for (self.fields.items) |*entry| {
            for (entry.values.items) |value| switch (value) {
                .message => |message| try message.validateRequired(),
                .group => |message| try message.validateRequired(),
                .map_entry => |map_entry| switch (map_entry.value) {
                    .message => |message| try message.validateRequired(),
                    .group => |message| try message.validateRequired(),
                    else => {},
                },
                else => {},
            };
        }
    }

    fn getOrCreateMutable(self: *DynamicMessage, field: *const schema.FieldDescriptor) std.mem.Allocator.Error!*FieldValue {
        for (self.fields.items) |*entry| {
            if (entry.descriptor.number == field.number) return entry;
        }
        try self.fields.append(self.allocator, .{ .descriptor = field });
        return &self.fields.items[self.fields.items.len - 1];
    }

    fn clearOneofExcept(self: *DynamicMessage, oneof_name: []const u8, keep_number: wire.FieldNumber) void {
        var index: usize = 0;
        while (index < self.fields.items.len) {
            const entry = &self.fields.items[index];
            const same_oneof = if (entry.descriptor.oneof_name) |name| std.mem.eql(u8, name, oneof_name) else false;
            if (same_oneof and entry.descriptor.number != keep_number) {
                entry.deinit(self.allocator);
                _ = self.fields.swapRemove(index);
                continue;
            }
            index += 1;
        }
    }

    pub fn encode(self: *const DynamicMessage, file: *const schema.FileDescriptor, writer: *wire.Writer) EncodeError!void {
        for (self.fields.items) |*entry| {
            if (entry.descriptor.resolvedPacked(file)) {
                try encodePacked(entry.descriptor, entry.values.items, writer);
            } else {
                for (entry.values.items) |value| try encodeField(entry.descriptor, value, file, writer);
            }
        }
        for (self.unknown_fields.items) |unknown| try writer.appendSlice(unknown.data);
    }

    pub fn encoded(self: *const DynamicMessage, file: *const schema.FileDescriptor) EncodeError![]u8 {
        var writer = wire.Writer.init(self.allocator);
        errdefer writer.deinit();
        try self.encode(file, &writer);
        return try writer.toOwnedSlice();
    }

    pub fn decode(self: *DynamicMessage, file: *const schema.FileDescriptor, bytes: []const u8) DecodeError!void {
        self.clear();
        var reader = wire.Reader.init(bytes);
        try self.decodeStream(file, &reader, null);
    }

    fn decodeStream(self: *DynamicMessage, file: *const schema.FileDescriptor, reader: *wire.Reader, end_group: ?wire.FieldNumber) DecodeError!void {
        while (try reader.nextTag()) |tag| {
            if (tag.wire_type == .end_group) {
                if (end_group) |expected| {
                    if (tag.number != expected) return error.InvalidFieldNumber;
                    return;
                }
                return error.InvalidWireType;
            }

            const start = reader.position() - wire.encodedVarintSize(try tag.encode());
            const field = self.descriptor.findFieldByNumber(tag.number) orelse {
                try reader.skipValue(tag);
                const raw = try self.allocator.dupe(u8, reader.input[start..reader.position()]);
                self.unknown_fields.append(self.allocator, .{
                    .number = tag.number,
                    .wire_type = tag.wire_type,
                    .data = raw,
                }) catch |err| {
                    self.allocator.free(raw);
                    return err;
                };
                continue;
            };

            if (field.kind == .group) {
                if (tag.wire_type != .start_group) return error.InvalidWireType;
                var value = try decodeGroupValue(self.allocator, file, self.descriptor, field, reader);
                self.add(field, value) catch |err| {
                    deinitValue(&value, self.allocator);
                    return err;
                };
                continue;
            }

            if (field.kind == .map) {
                if (tag.wire_type != .length_delimited) return error.InvalidWireType;
                var value = try decodeMapEntryValue(self.allocator, file, self.descriptor, field.kind.map, reader);
                self.add(field, value) catch |err| {
                    deinitValue(&value, self.allocator);
                    return err;
                };
                continue;
            }

            // Protobuf decoders must accept packed input for packable repeated
            // fields regardless of whether the schema currently emits packed
            // or expanded encoding. This is especially important across
            // proto2 options, proto3 defaults, and editions features.
            if (tag.wire_type == .length_delimited and field.isPackable()) {
                const payload = try reader.readBytes();
                var packed_reader = wire.Reader.init(payload);
                while (!packed_reader.eof()) {
                    const value = try decodeScalarLike(field.kind, &packed_reader);
                    try self.add(field, value);
                }
                continue;
            }

            if (tag.wire_type != field.kind.wireType()) return error.InvalidWireType;
            var value = try decodeValue(self.allocator, file, self.descriptor, field.kind, reader);
            self.add(field, value) catch |err| {
                deinitValue(&value, self.allocator);
                return err;
            };
        }
        if (end_group != null) return error.TruncatedInput;
    }
};

fn encodeField(field: *const schema.FieldDescriptor, value: Value, file: *const schema.FileDescriptor, writer: *wire.Writer) EncodeError!void {
    switch (field.kind) {
        .scalar => |scalar| try encodeScalar(field.number, scalar, value, writer),
        .enumeration => switch (value) {
            .enumeration => |v| {
                try writer.writeTag(field.number, .varint);
                try writer.writeVarint(@as(u64, @bitCast(@as(i64, v))));
            },
            else => return error.TypeMismatch,
        },
        .message => switch (value) {
            .message => |message| {
                var nested_writer = wire.Writer.init(writer.allocator);
                defer nested_writer.deinit();
                // Nested message packing depends on its own file-level features only for repeated scalar fields.
                try message.encode(file, &nested_writer);
                try writer.writeMessage(field.number, nested_writer.slice());
            },
            else => return error.TypeMismatch,
        },
        .group => switch (value) {
            .group => |message| {
                try writer.writeTag(field.number, .start_group);
                try message.encode(file, writer);
                try writer.writeTag(field.number, .end_group);
            },
            else => return error.TypeMismatch,
        },
        .map => |map_type| try encodeMapEntry(field.number, map_type, value, file, writer),
    }
}

fn encodeMapEntry(
    number: wire.FieldNumber,
    map_type: schema.MapType,
    value: Value,
    file: *const schema.FileDescriptor,
    writer: *wire.Writer,
) EncodeError!void {
    const entry = switch (value) {
        .map_entry => |map_entry| map_entry,
        else => return error.TypeMismatch,
    };

    var entry_writer = wire.Writer.init(writer.allocator);
    defer entry_writer.deinit();
    try encodeMapElement(1, .{ .scalar = map_type.key }, entry.key, file, &entry_writer);
    try encodeMapElement(2, map_type.value.*, entry.value, file, &entry_writer);
    try writer.writeMessage(number, entry_writer.slice());
}

fn encodeMapElement(
    number: wire.FieldNumber,
    kind: schema.FieldKind,
    value: Value,
    file: *const schema.FileDescriptor,
    writer: *wire.Writer,
) EncodeError!void {
    switch (kind) {
        .scalar => |scalar| try encodeScalar(number, scalar, value, writer),
        .enumeration => switch (value) {
            .enumeration => |v| {
                try writer.writeTag(number, .varint);
                try writer.writeVarint(@as(u64, @bitCast(@as(i64, v))));
            },
            else => return error.TypeMismatch,
        },
        .message => switch (value) {
            .message => |message| {
                var nested_writer = wire.Writer.init(writer.allocator);
                defer nested_writer.deinit();
                try message.encode(file, &nested_writer);
                try writer.writeMessage(number, nested_writer.slice());
            },
            else => return error.TypeMismatch,
        },
        .group, .map => return error.TypeMismatch,
    }
}

fn encodePacked(field: *const schema.FieldDescriptor, values: []const Value, writer: *wire.Writer) EncodeError!void {
    var packed_writer = wire.Writer.init(writer.allocator);
    defer packed_writer.deinit();
    for (values) |value| try encodeScalarPayload(field.kind, value, &packed_writer);
    try writer.writeBytes(field.number, packed_writer.slice());
}

fn encodeScalar(number: wire.FieldNumber, scalar: schema.ScalarType, value: Value, writer: *wire.Writer) EncodeError!void {
    try writer.writeTag(number, scalar.wireType());
    try encodeScalarPayload(.{ .scalar = scalar }, value, writer);
}

fn encodeScalarPayload(kind: schema.FieldKind, value: Value, writer: *wire.Writer) EncodeError!void {
    switch (kind) {
        .scalar => |scalar| switch (scalar) {
            .double => if (value == .double) try writer.writeRawLittle(u64, @bitCast(value.double)) else return error.TypeMismatch,
            .float => if (value == .float) try writer.writeRawLittle(u32, @bitCast(value.float)) else return error.TypeMismatch,
            .int32 => if (value == .int32) try writer.writeVarint(@as(u64, @bitCast(@as(i64, value.int32)))) else return error.TypeMismatch,
            .int64 => if (value == .int64) try writer.writeVarint(@as(u64, @bitCast(value.int64))) else return error.TypeMismatch,
            .uint32 => if (value == .uint32) try writer.writeVarint(value.uint32) else return error.TypeMismatch,
            .uint64 => if (value == .uint64) try writer.writeVarint(value.uint64) else return error.TypeMismatch,
            .sint32 => if (value == .sint32) try writer.writeVarint(wire.zigZagEncode32(value.sint32)) else return error.TypeMismatch,
            .sint64 => if (value == .sint64) try writer.writeVarint(wire.zigZagEncode64(value.sint64)) else return error.TypeMismatch,
            .fixed32 => if (value == .fixed32) try writer.writeRawLittle(u32, value.fixed32) else return error.TypeMismatch,
            .fixed64 => if (value == .fixed64) try writer.writeRawLittle(u64, value.fixed64) else return error.TypeMismatch,
            .sfixed32 => if (value == .sfixed32) try writer.writeRawLittle(i32, value.sfixed32) else return error.TypeMismatch,
            .sfixed64 => if (value == .sfixed64) try writer.writeRawLittle(i64, value.sfixed64) else return error.TypeMismatch,
            .bool => if (value == .boolean) try writer.writeVarint(if (value.boolean) 1 else 0) else return error.TypeMismatch,
            .string => if (value == .string) {
                try writer.writeVarint(value.string.len);
                try writer.appendSlice(value.string);
            } else return error.TypeMismatch,
            .bytes => if (value == .bytes) {
                try writer.writeVarint(value.bytes.len);
                try writer.appendSlice(value.bytes);
            } else return error.TypeMismatch,
        },
        .enumeration => if (value == .enumeration) try writer.writeVarint(@as(u64, @bitCast(@as(i64, value.enumeration)))) else return error.TypeMismatch,
        else => return error.TypeMismatch,
    }
}

fn decodeValue(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    current: *const schema.MessageDescriptor,
    kind: schema.FieldKind,
    reader: *wire.Reader,
) DecodeError!Value {
    return switch (kind) {
        .scalar => |scalar| switch (scalar) {
            .string => .{ .string = try allocator.dupe(u8, try reader.readBytes()) },
            .bytes => .{ .bytes = try allocator.dupe(u8, try reader.readBytes()) },
            else => try decodeScalarLike(kind, reader),
        },
        .enumeration => try decodeScalarLike(kind, reader),
        .message => |name| blk: {
            const payload = try reader.readBytes();
            const descriptor = resolveMessageDescriptor(file, current, name) orelse return error.TypeMismatch;
            const message = try allocator.create(DynamicMessage);
            message.* = DynamicMessage.init(allocator, descriptor);
            errdefer {
                message.deinit();
                allocator.destroy(message);
            }
            try message.decode(file, payload);
            break :blk .{ .message = message };
        },
        .group => error.TypeMismatch,
        .map => error.TypeMismatch,
    };
}

fn decodeMapEntryValue(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    current: *const schema.MessageDescriptor,
    map_type: schema.MapType,
    reader: *wire.Reader,
) DecodeError!Value {
    const payload = try reader.readBytes();
    var entry_reader = wire.Reader.init(payload);

    var maybe_key: ?Value = null;
    var maybe_value: ?Value = null;
    errdefer {
        if (maybe_key) |*key| deinitValue(key, allocator);
        if (maybe_value) |*map_value| deinitValue(map_value, allocator);
    }

    while (try entry_reader.nextTag()) |tag| {
        switch (tag.number) {
            1 => {
                if (tag.wire_type != map_type.key.wireType()) return error.InvalidWireType;
                if (maybe_key) |*old| deinitValue(old, allocator);
                maybe_key = try decodeValue(allocator, file, current, .{ .scalar = map_type.key }, &entry_reader);
            },
            2 => {
                if (tag.wire_type != map_type.value.wireType()) return error.InvalidWireType;
                if (maybe_value) |*old| deinitValue(old, allocator);
                maybe_value = try decodeValue(allocator, file, current, map_type.value.*, &entry_reader);
            },
            else => try entry_reader.skipValue(tag),
        }
    }

    const key = maybe_key orelse try defaultValue(allocator, file, current, .{ .scalar = map_type.key });
    maybe_key = null;
    const map_value = maybe_value orelse try defaultValue(allocator, file, current, map_type.value.*);
    maybe_value = null;

    const entry = try allocator.create(MapEntry);
    entry.* = .{ .key = key, .value = map_value };
    return .{ .map_entry = entry };
}

fn defaultValue(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    current: *const schema.MessageDescriptor,
    kind: schema.FieldKind,
) DecodeError!Value {
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
        .enumeration => .{ .enumeration = 0 },
        .message => |name| blk: {
            const descriptor = resolveMessageDescriptor(file, current, name) orelse return error.TypeMismatch;
            const message = try allocator.create(DynamicMessage);
            message.* = DynamicMessage.init(allocator, descriptor);
            break :blk .{ .message = message };
        },
        .group, .map => error.TypeMismatch,
    };
}

fn decodeGroupValue(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    current: *const schema.MessageDescriptor,
    field: *const schema.FieldDescriptor,
    reader: *wire.Reader,
) DecodeError!Value {
    const name = switch (field.kind) {
        .group => |group_name| group_name,
        else => return error.TypeMismatch,
    };
    const descriptor = resolveMessageDescriptor(file, current, name) orelse return error.TypeMismatch;
    const message = try allocator.create(DynamicMessage);
    message.* = DynamicMessage.init(allocator, descriptor);
    errdefer {
        message.deinit();
        allocator.destroy(message);
    }
    try message.decodeStream(file, reader, field.number);
    return .{ .group = message };
}

fn resolveMessageDescriptor(file: *const schema.FileDescriptor, current: *const schema.MessageDescriptor, name: []const u8) ?*const schema.MessageDescriptor {
    const trimmed = if (std.mem.startsWith(u8, name, ".")) name[1..] else name;
    const leaf = if (std.mem.lastIndexOfScalar(u8, trimmed, '.')) |idx| trimmed[idx + 1 ..] else trimmed;
    if (std.mem.eql(u8, current.name, trimmed) or std.mem.eql(u8, current.name, leaf)) return current;
    if (current.findMessageDeep(trimmed)) |message| return message;
    return file.findMessageDeep(trimmed);
}

fn decodeScalarLike(kind: schema.FieldKind, reader: *wire.Reader) DecodeError!Value {
    return switch (kind) {
        .scalar => |scalar| switch (scalar) {
            .double => .{ .double = try reader.readDouble() },
            .float => .{ .float = try reader.readFloat() },
            .int32 => .{ .int32 = try reader.readInt32() },
            .int64 => .{ .int64 = try reader.readInt64() },
            .uint32 => .{ .uint32 = try reader.readUInt32() },
            .uint64 => .{ .uint64 = try reader.readUInt64() },
            .sint32 => .{ .sint32 = try reader.readSInt32() },
            .sint64 => .{ .sint64 = try reader.readSInt64() },
            .fixed32 => .{ .fixed32 = try reader.readFixed32() },
            .fixed64 => .{ .fixed64 = try reader.readFixed64() },
            .sfixed32 => .{ .sfixed32 = try reader.readSFixed32() },
            .sfixed64 => .{ .sfixed64 = try reader.readSFixed64() },
            .bool => .{ .boolean = try reader.readBool() },
            .string => return error.TypeMismatch,
            .bytes => return error.TypeMismatch,
        },
        .enumeration => .{ .enumeration = try reader.readInt32() },
        else => return error.TypeMismatch,
    };
}

pub fn decodeBytesValue(allocator: std.mem.Allocator, scalar: schema.ScalarType, reader: *wire.Reader) DecodeError!Value {
    switch (scalar) {
        .string => return .{ .string = try allocator.dupe(u8, try reader.readBytes()) },
        .bytes => return .{ .bytes = try allocator.dupe(u8, try reader.readBytes()) },
        else => return decodeScalarLike(.{ .scalar = scalar }, reader),
    }
}

pub fn deinitValue(value: *Value, allocator: std.mem.Allocator) void {
    switch (value.*) {
        .string => |bytes| allocator.free(bytes),
        .bytes => |bytes| allocator.free(bytes),
        .message => |message| {
            message.deinit();
            allocator.destroy(message);
        },
        .group => |message| {
            message.deinit();
            allocator.destroy(message);
        },
        .map_entry => |entry| {
            entry.deinit(allocator);
            allocator.destroy(entry);
        },
        else => {},
    }
    value.* = undefined;
}

pub fn cloneValue(allocator: std.mem.Allocator, value: Value) std.mem.Allocator.Error!Value {
    return switch (value) {
        .string => |bytes| .{ .string = try allocator.dupe(u8, bytes) },
        .bytes => |bytes| .{ .bytes = try allocator.dupe(u8, bytes) },
        .message => |message| blk: {
            const cloned = try allocator.create(DynamicMessage);
            cloned.* = DynamicMessage.init(allocator, message.descriptor);
            errdefer {
                cloned.deinit();
                allocator.destroy(cloned);
            }
            for (message.fields.items) |*field| {
                for (field.values.items) |item| try cloned.add(field.descriptor, try cloneValue(allocator, item));
            }
            for (message.unknown_fields.items) |unknown| try cloned.unknown_fields.append(allocator, .{
                .number = unknown.number,
                .wire_type = unknown.wire_type,
                .data = try allocator.dupe(u8, unknown.data),
            });
            break :blk .{ .message = cloned };
        },
        .group => |message| blk: {
            const cloned = try allocator.create(DynamicMessage);
            cloned.* = DynamicMessage.init(allocator, message.descriptor);
            errdefer {
                cloned.deinit();
                allocator.destroy(cloned);
            }
            for (message.fields.items) |*field| {
                for (field.values.items) |item| try cloned.add(field.descriptor, try cloneValue(allocator, item));
            }
            for (message.unknown_fields.items) |unknown| try cloned.unknown_fields.append(allocator, .{
                .number = unknown.number,
                .wire_type = unknown.wire_type,
                .data = try allocator.dupe(u8, unknown.data),
            });
            break :blk .{ .group = cloned };
        },
        .map_entry => |entry| blk: {
            var cloned_key = try cloneValue(allocator, entry.key);
            errdefer deinitValue(&cloned_key, allocator);
            var cloned_value = try cloneValue(allocator, entry.value);
            errdefer deinitValue(&cloned_value, allocator);

            const cloned = try allocator.create(MapEntry);
            cloned.* = .{ .key = cloned_key, .value = cloned_value };
            break :blk .{ .map_entry = cloned };
        },
        else => value,
    };
}

test "dynamic message encodes decodes scalar and preserves unknown fields" {
    const allocator = std.testing.allocator;
    var file = schema.FileDescriptor.init(allocator);
    defer file.deinit();
    file.setSyntax(.proto3);

    var msg = schema.MessageDescriptor{ .name = "Person" };
    try msg.fields.append(allocator, .{ .name = "id", .number = 1, .kind = .{ .scalar = .int32 } });
    try msg.fields.append(allocator, .{ .name = "name", .number = 2, .kind = .{ .scalar = .string } });
    try file.messages.append(allocator, msg);

    var dyn = DynamicMessage.init(allocator, &file.messages.items[0]);
    defer dyn.deinit();
    try dyn.add(file.messages.items[0].findField("id").?, .{ .int32 = 42 });

    var w = wire.Writer.init(allocator);
    defer w.deinit();
    try dyn.encode(&file, &w);
    try w.writeUInt32(99, 7);

    var decoded = DynamicMessage.init(allocator, &file.messages.items[0]);
    defer decoded.deinit();
    try decoded.decode(&file, w.slice());
    try std.testing.expectEqual(@as(i32, 42), decoded.get("id").?.values.items[0].int32);
    try std.testing.expectEqual(@as(usize, 1), decoded.unknown_fields.items.len);
}

test "dynamic proto2 round-trips required optional repeated packed message and group fields" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto2";
        \\package demo;
        \\message Child { optional string label = 1; }
        \\message Parent {
        \\  required int32 id = 1;
        \\  optional string name = 2 [default = "anon"];
        \\  optional bytes blob = 3;
        \\  repeated sint32 nums = 4 [packed = true];
        \\  optional Child child = 5;
        \\  optional group Legacy = 6 { optional bool flag = 7; }
        \\}
    ;
    var file = try parser.Parser.parse(allocator, source);
    defer file.deinit();
    const parent_desc = file.findMessage("Parent").?;
    const child_desc = file.findMessage("Child").?;
    const group_desc = parent_desc.findMessageDeep("Legacy").?;

    var message = DynamicMessage.init(allocator, parent_desc);
    defer message.deinit();
    try std.testing.expectError(error.MissingRequiredField, message.validateRequired());

    try message.add(parent_desc.findField("id").?, .{ .int32 = 123 });
    try message.add(parent_desc.findField("name").?, .{ .string = try allocator.dupe(u8, "pb2") });
    try message.add(parent_desc.findField("blob").?, .{ .bytes = try allocator.dupe(u8, "raw") });
    try message.add(parent_desc.findField("nums").?, .{ .sint32 = -1 });
    try message.add(parent_desc.findField("nums").?, .{ .sint32 = 2 });

    const child = try allocator.create(DynamicMessage);
    child.* = DynamicMessage.init(allocator, child_desc);
    try child.add(child_desc.findField("label").?, .{ .string = try allocator.dupe(u8, "kid") });
    try message.add(parent_desc.findField("child").?, .{ .message = child });

    const group = try allocator.create(DynamicMessage);
    group.* = DynamicMessage.init(allocator, group_desc);
    try group.add(group_desc.findField("flag").?, .{ .boolean = true });
    try message.add(parent_desc.findField("Legacy").?, .{ .group = group });
    try message.validateRequired();

    const encoded = try message.encoded(&file);
    defer allocator.free(encoded);

    var decoded = DynamicMessage.init(allocator, parent_desc);
    defer decoded.deinit();
    try decoded.decode(&file, encoded);
    try decoded.validateRequired();
    try std.testing.expectEqual(@as(i32, 123), decoded.get("id").?.values.items[0].int32);
    try std.testing.expectEqualSlices(u8, "pb2", decoded.get("name").?.values.items[0].string);
    try std.testing.expectEqualSlices(u8, "raw", decoded.get("blob").?.values.items[0].bytes);
    try std.testing.expectEqual(@as(usize, 2), decoded.get("nums").?.values.items.len);
    try std.testing.expectEqual(@as(i32, -1), decoded.get("nums").?.values.items[0].sint32);
    try std.testing.expectEqual(@as(i32, 2), decoded.get("nums").?.values.items[1].sint32);
    try std.testing.expectEqualSlices(u8, "kid", decoded.get("child").?.values.items[0].message.get("label").?.values.items[0].string);
    try std.testing.expect(decoded.get("Legacy").?.values.items[0].group.get("flag").?.values.items[0].boolean);
}

test "dynamic proto3 round-trips map fields and default packed repeated scalars" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\package demo;
        \\message Child { string label = 1; }
        \\message Bag {
        \\  repeated int32 nums = 1;
        \\  map<string, int32> counts = 2;
        \\  map<int32, string> names = 3;
        \\  map<string, Child> children = 4;
        \\}
    ;
    var file = try parser.Parser.parse(allocator, source);
    defer file.deinit();
    const bag_desc = file.findMessage("Bag").?;
    const child_desc = file.findMessage("Child").?;

    var bag = DynamicMessage.init(allocator, bag_desc);
    defer bag.deinit();
    try bag.add(bag_desc.findField("nums").?, .{ .int32 = 1 });
    try bag.add(bag_desc.findField("nums").?, .{ .int32 = 2 });

    const count_entry = try allocator.create(MapEntry);
    count_entry.* = .{
        .key = .{ .string = try allocator.dupe(u8, "red") },
        .value = .{ .int32 = 7 },
    };
    try bag.add(bag_desc.findField("counts").?, .{ .map_entry = count_entry });

    const name_entry = try allocator.create(MapEntry);
    name_entry.* = .{
        .key = .{ .int32 = 42 },
        .value = .{ .string = try allocator.dupe(u8, "forty-two") },
    };
    try bag.add(bag_desc.findField("names").?, .{ .map_entry = name_entry });

    const child = try allocator.create(DynamicMessage);
    child.* = DynamicMessage.init(allocator, child_desc);
    try child.add(child_desc.findField("label").?, .{ .string = try allocator.dupe(u8, "kid") });
    const child_entry = try allocator.create(MapEntry);
    child_entry.* = .{
        .key = .{ .string = try allocator.dupe(u8, "first") },
        .value = .{ .message = child },
    };
    try bag.add(bag_desc.findField("children").?, .{ .map_entry = child_entry });

    const encoded = try bag.encoded(&file);
    defer allocator.free(encoded);

    // Proto3 numeric repeated fields are packed by default: field 1 appears as
    // one length-delimited record containing the two varints.
    try std.testing.expectEqualSlices(u8, &.{ 0x0a, 0x02, 0x01, 0x02 }, encoded[0..4]);

    var decoded = DynamicMessage.init(allocator, bag_desc);
    defer decoded.deinit();
    try decoded.decode(&file, encoded);

    try std.testing.expectEqual(@as(usize, 2), decoded.get("nums").?.values.items.len);
    try std.testing.expectEqual(@as(i32, 1), decoded.get("nums").?.values.items[0].int32);
    try std.testing.expectEqual(@as(i32, 2), decoded.get("nums").?.values.items[1].int32);

    const decoded_count = decoded.get("counts").?.values.items[0].map_entry;
    try std.testing.expectEqualSlices(u8, "red", decoded_count.key.string);
    try std.testing.expectEqual(@as(i32, 7), decoded_count.value.int32);

    const decoded_name = decoded.get("names").?.values.items[0].map_entry;
    try std.testing.expectEqual(@as(i32, 42), decoded_name.key.int32);
    try std.testing.expectEqualSlices(u8, "forty-two", decoded_name.value.string);

    const decoded_child = decoded.get("children").?.values.items[0].map_entry;
    try std.testing.expectEqualSlices(u8, "first", decoded_child.key.string);
    try std.testing.expectEqualSlices(u8, "kid", decoded_child.value.message.get("label").?.values.items[0].string);
}

test "dynamic editions honors repeated field encoding features and accepts packed compatibility" {
    const allocator = std.testing.allocator;

    const expanded_source =
        \\edition = "2023";
        \\package demo;
        \\option features.repeated_field_encoding = EXPANDED;
        \\message Metrics { repeated int32 values = 1; }
    ;
    var expanded_file = try parser.Parser.parse(allocator, expanded_source);
    defer expanded_file.deinit();
    const expanded_desc = expanded_file.findMessage("Metrics").?;
    try std.testing.expectEqual(schema.FeatureSet.RepeatedFieldEncoding.expanded, expanded_file.features.repeated_field_encoding);
    try std.testing.expect(!expanded_desc.findField("values").?.resolvedPacked(&expanded_file));

    var expanded = DynamicMessage.init(allocator, expanded_desc);
    defer expanded.deinit();
    try expanded.add(expanded_desc.findField("values").?, .{ .int32 = 1 });
    try expanded.add(expanded_desc.findField("values").?, .{ .int32 = 2 });
    const expanded_bytes = try expanded.encoded(&expanded_file);
    defer allocator.free(expanded_bytes);
    try std.testing.expectEqualSlices(u8, &.{ 0x08, 0x01, 0x08, 0x02 }, expanded_bytes);

    var expanded_decoded_from_packed = DynamicMessage.init(allocator, expanded_desc);
    defer expanded_decoded_from_packed.deinit();
    try expanded_decoded_from_packed.decode(&expanded_file, &.{ 0x0a, 0x02, 0x01, 0x02 });
    try std.testing.expectEqual(@as(usize, 2), expanded_decoded_from_packed.get("values").?.values.items.len);
    try std.testing.expectEqual(@as(i32, 1), expanded_decoded_from_packed.get("values").?.values.items[0].int32);
    try std.testing.expectEqual(@as(i32, 2), expanded_decoded_from_packed.get("values").?.values.items[1].int32);

    const packed_source =
        \\edition = "2023";
        \\package demo;
        \\message Metrics { repeated int32 values = 1; }
    ;
    var packed_file = try parser.Parser.parse(allocator, packed_source);
    defer packed_file.deinit();
    const packed_desc = packed_file.findMessage("Metrics").?;
    try std.testing.expectEqual(schema.FeatureSet.RepeatedFieldEncoding.packed_encoding, packed_file.features.repeated_field_encoding);
    try std.testing.expect(packed_desc.findField("values").?.resolvedPacked(&packed_file));

    var packed_msg = DynamicMessage.init(allocator, packed_desc);
    defer packed_msg.deinit();
    try packed_msg.add(packed_desc.findField("values").?, .{ .int32 = 1 });
    try packed_msg.add(packed_desc.findField("values").?, .{ .int32 = 2 });
    const packed_bytes = try packed_msg.encoded(&packed_file);
    defer allocator.free(packed_bytes);
    try std.testing.expectEqualSlices(u8, &.{ 0x0a, 0x02, 0x01, 0x02 }, packed_bytes);

    var packed_decoded_from_expanded = DynamicMessage.init(allocator, packed_desc);
    defer packed_decoded_from_expanded.deinit();
    try packed_decoded_from_expanded.decode(&packed_file, &.{ 0x08, 0x01, 0x08, 0x02 });
    try std.testing.expectEqual(@as(usize, 2), packed_decoded_from_expanded.get("values").?.values.items.len);
    try std.testing.expectEqual(@as(i32, 1), packed_decoded_from_expanded.get("values").?.values.items[0].int32);
    try std.testing.expectEqual(@as(i32, 2), packed_decoded_from_expanded.get("values").?.values.items[1].int32);
}

test "dynamic oneof keeps only the last selected field" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto2";
        \\package demo;
        \\message Choice {
        \\  oneof pick {
        \\    string name = 1;
        \\    int32 id = 2;
        \\  }
        \\}
    ;
    var file = try parser.Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("Choice").?;

    var message = DynamicMessage.init(allocator, desc);
    defer message.deinit();
    try message.add(desc.findField("name").?, .{ .string = try allocator.dupe(u8, "first") });
    try std.testing.expectEqualStrings("name", message.whichOneof("pick").?.name);
    try message.add(desc.findField("id").?, .{ .int32 = 99 });
    try std.testing.expect(message.get("name") == null);
    try std.testing.expectEqualStrings("id", message.whichOneof("pick").?.name);
    try std.testing.expectEqual(@as(i32, 99), message.get("id").?.values.items[0].int32);

    var writer = wire.Writer.init(allocator);
    defer writer.deinit();
    try writer.writeString(1, "wire-first");
    try writer.writeInt32(2, 7);

    var decoded = DynamicMessage.init(allocator, desc);
    defer decoded.deinit();
    try decoded.decode(&file, writer.slice());
    try std.testing.expect(decoded.get("name") == null);
    try std.testing.expectEqualStrings("id", decoded.whichOneof("pick").?.name);
    try std.testing.expectEqual(@as(i32, 7), decoded.get("id").?.values.items[0].int32);
}

test "dynamic unknown field API preserves queries and clears raw fields" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\message Known { int32 id = 1; }
    ;
    var file = try parser.Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("Known").?;

    var writer = wire.Writer.init(allocator);
    defer writer.deinit();
    try writer.writeInt32(1, 5);
    try writer.writeString(100, "extra");
    try writer.writeUInt32(101, 7);

    var message = DynamicMessage.init(allocator, desc);
    defer message.deinit();
    try message.decode(&file, writer.slice());

    try std.testing.expectEqual(@as(usize, 2), message.unknownCount());
    const unknown_100 = message.unknownByNumber(100);
    try std.testing.expectEqual(@as(usize, 1), unknown_100.len);
    try std.testing.expectEqual(wire.WireType.length_delimited, unknown_100[0].wire_type);
    try std.testing.expectEqualSlices(u8, &.{ 0xa2, 0x06, 0x05, 'e', 'x', 't', 'r', 'a' }, unknown_100[0].data);

    const encoded = try message.encoded(&file);
    defer allocator.free(encoded);
    try std.testing.expectEqualSlices(u8, writer.slice(), encoded);

    message.clearUnknownFields();
    try std.testing.expectEqual(@as(usize, 0), message.unknownCount());
    const encoded_clean = try message.encoded(&file);
    defer allocator.free(encoded_clean);
    try std.testing.expectEqualSlices(u8, &.{ 0x08, 0x05 }, encoded_clean);
}
