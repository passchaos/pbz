const std = @import("std");
const wire = @import("wire.zig");
const schema = @import("schema.zig");
const parser = @import("parser.zig");
const registry_mod = @import("registry.zig");

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

pub const DefaultValue = union(enum) {
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
    string: []const u8,
    bytes: []const u8,
    enumeration: i32,
    none,
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

    pub fn has(self: *const DynamicMessage, field: *const schema.FieldDescriptor) bool {
        return if (self.getByNumber(field.number)) |value| value.values.items.len != 0 else false;
    }

    pub fn getOrDefault(self: *const DynamicMessage, field: *const schema.FieldDescriptor) DefaultValue {
        if (self.getByNumber(field.number)) |field_value| {
            if (field_value.values.items.len != 0) return valueAsDefault(field_value.values.items[field_value.values.items.len - 1]);
        }
        return defaultForField(field);
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

    pub fn unknownByNumberAlloc(self: *const DynamicMessage, allocator: std.mem.Allocator, number: wire.FieldNumber) std.mem.Allocator.Error![]UnknownField {
        var fields: std.ArrayList(UnknownField) = .empty;
        errdefer fields.deinit(allocator);
        for (self.unknown_fields.items) |field| {
            if (field.number == number) try fields.append(allocator, field);
        }
        return try fields.toOwnedSlice(allocator);
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

    pub fn mergeFrom(self: *DynamicMessage, other: *const DynamicMessage) std.mem.Allocator.Error!void {
        for (other.fields.items) |*entry| {
            for (entry.values.items) |value| try self.addClone(entry.descriptor, value);
        }
        for (other.unknown_fields.items) |unknown| try self.unknown_fields.append(self.allocator, .{
            .number = unknown.number,
            .wire_type = unknown.wire_type,
            .data = try self.allocator.dupe(u8, unknown.data),
        });
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
            if (field.cardinality == .required and !self.has(field)) return error.MissingRequiredField;
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

    pub fn missingRequiredFieldPath(self: *const DynamicMessage, allocator: std.mem.Allocator) std.mem.Allocator.Error!?[]u8 {
        for (self.descriptor.fields.items) |*field| {
            if (field.cardinality == .required and !self.has(field)) return try allocator.dupe(u8, field.name);
        }
        for (self.fields.items) |*entry| {
            for (entry.values.items) |value| {
                const nested = switch (value) {
                    .message => |message| message,
                    .group => |message| message,
                    .map_entry => |map_entry| switch (map_entry.value) {
                        .message => |message| message,
                        .group => |message| message,
                        else => null,
                    },
                    else => null,
                };
                if (nested) |message| {
                    if (try message.missingRequiredFieldPath(allocator)) |suffix| {
                        defer allocator.free(suffix);
                        return try std.fmt.allocPrint(allocator, "{s}.{s}", .{ entry.descriptor.name, suffix });
                    }
                }
            }
        }
        return null;
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
        if (self.descriptor.messageSetWireFormat()) return try self.encodeMessageSet(file, writer, false);
        for (self.fields.items) |*entry| {
            if (entry.descriptor.resolvedPacked(file)) {
                try encodePacked(entry.descriptor, entry.values.items, writer);
            } else {
                for (entry.values.items) |value| try encodeField(entry.descriptor, value, file, writer);
            }
        }
        for (self.unknown_fields.items) |unknown| try writer.appendSlice(unknown.data);
    }

    pub fn encodeInitialized(self: *const DynamicMessage, file: *const schema.FileDescriptor, writer: *wire.Writer) (EncodeError || ValidationError)!void {
        try self.validateRequired();
        try self.encode(file, writer);
    }

    pub fn encodeDeterministic(self: *const DynamicMessage, file: *const schema.FileDescriptor, writer: *wire.Writer) EncodeError!void {
        if (self.descriptor.messageSetWireFormat()) return try self.encodeMessageSet(file, writer, true);
        const indexes = try self.allocator.alloc(usize, self.fields.items.len);
        defer self.allocator.free(indexes);
        for (indexes, 0..) |*index, i| index.* = i;
        std.mem.sort(usize, indexes, self, struct {
            fn lessThan(message: *const DynamicMessage, a: usize, b: usize) bool {
                return message.fields.items[a].descriptor.number < message.fields.items[b].descriptor.number;
            }
        }.lessThan);
        for (indexes) |index| {
            const entry = &self.fields.items[index];
            if (entry.descriptor.resolvedPacked(file)) {
                try encodePacked(entry.descriptor, entry.values.items, writer);
            } else if (entry.descriptor.kind == .map) {
                const value_indexes = try self.allocator.alloc(usize, entry.values.items.len);
                defer self.allocator.free(value_indexes);
                for (value_indexes, 0..) |*value_index, i| value_index.* = i;
                std.mem.sort(usize, value_indexes, entry, struct {
                    fn lessThan(field_value: *const FieldValue, a: usize, b: usize) bool {
                        return mapEntryLessThan(field_value.values.items[a], field_value.values.items[b]);
                    }
                }.lessThan);
                for (value_indexes) |value_index| try encodeField(entry.descriptor, entry.values.items[value_index], file, writer);
            } else {
                for (entry.values.items) |value| try encodeField(entry.descriptor, value, file, writer);
            }
        }
        const unknown_indexes = try self.allocator.alloc(usize, self.unknown_fields.items.len);
        defer self.allocator.free(unknown_indexes);
        for (unknown_indexes, 0..) |*index, i| index.* = i;
        std.mem.sort(usize, unknown_indexes, self, struct {
            fn lessThan(message: *const DynamicMessage, a: usize, b: usize) bool {
                return message.unknown_fields.items[a].number < message.unknown_fields.items[b].number;
            }
        }.lessThan);
        for (unknown_indexes) |index| try writer.appendSlice(self.unknown_fields.items[index].data);
    }

    pub fn encodeDeterministicInitialized(self: *const DynamicMessage, file: *const schema.FileDescriptor, writer: *wire.Writer) (EncodeError || ValidationError)!void {
        try self.validateRequired();
        try self.encodeDeterministic(file, writer);
    }

    pub fn encoded(self: *const DynamicMessage, file: *const schema.FileDescriptor) EncodeError![]u8 {
        var writer = wire.Writer.init(self.allocator);
        errdefer writer.deinit();
        try self.encode(file, &writer);
        return try writer.toOwnedSlice();
    }

    pub fn encodedInitialized(self: *const DynamicMessage, file: *const schema.FileDescriptor) (EncodeError || ValidationError)![]u8 {
        var writer = wire.Writer.init(self.allocator);
        errdefer writer.deinit();
        try self.encodeInitialized(file, &writer);
        return try writer.toOwnedSlice();
    }

    pub fn encodedDeterministic(self: *const DynamicMessage, file: *const schema.FileDescriptor) EncodeError![]u8 {
        var writer = wire.Writer.init(self.allocator);
        errdefer writer.deinit();
        try self.encodeDeterministic(file, &writer);
        return try writer.toOwnedSlice();
    }

    pub fn encodedDeterministicInitialized(self: *const DynamicMessage, file: *const schema.FileDescriptor) (EncodeError || ValidationError)![]u8 {
        var writer = wire.Writer.init(self.allocator);
        errdefer writer.deinit();
        try self.encodeDeterministicInitialized(file, &writer);
        return try writer.toOwnedSlice();
    }

    pub fn decode(self: *DynamicMessage, file: *const schema.FileDescriptor, bytes: []const u8) DecodeError!void {
        self.clear();
        var reader = wire.Reader.init(bytes);
        try self.decodeStream(file, null, &reader, null);
    }

    pub fn decodeWithRegistry(self: *DynamicMessage, file: *const schema.FileDescriptor, registry: *const registry_mod.Registry, bytes: []const u8) DecodeError!void {
        self.clear();
        var reader = wire.Reader.init(bytes);
        try self.decodeStream(file, registry, &reader, null);
    }

    pub fn decodeInitialized(self: *DynamicMessage, file: *const schema.FileDescriptor, bytes: []const u8) (DecodeError || ValidationError)!void {
        try self.decode(file, bytes);
        try self.validateRequired();
    }

    fn decodeStream(self: *DynamicMessage, file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, reader: *wire.Reader, end_group: ?wire.FieldNumber) DecodeError!void {
        while (try reader.nextTag()) |tag| {
            if (tag.wire_type == .end_group) {
                if (end_group) |expected| {
                    if (tag.number != expected) return error.InvalidFieldNumber;
                    return;
                }
                return error.InvalidWireType;
            }

            if (self.descriptor.messageSetWireFormat() and tag.number == 1 and tag.wire_type == .start_group) {
                try self.decodeMessageSetItem(file, registry, reader);
                continue;
            }

            const start = reader.position() - wire.encodedVarintSize(try tag.encode());
            const field = self.descriptor.findFieldByNumber(tag.number) orelse registryExtension(registry, self.descriptor, tag.number) orelse {
                try reader.skipValue(tag);
                try self.addUnknownRaw(tag.number, tag.wire_type, reader.input[start..reader.position()]);
                continue;
            };

            if (field.kind == .group) {
                if (tag.wire_type != .start_group) return error.InvalidWireType;
                var value = try decodeGroupValue(self.allocator, file, registry, self.descriptor, field, reader);
                self.add(field, value) catch |err| {
                    deinitValue(&value, self.allocator);
                    return err;
                };
                continue;
            }

            if (field.kind == .map) {
                if (tag.wire_type != .length_delimited) return error.InvalidWireType;
                const payload = try reader.readBytes();
                var value = (try decodeMapEntryValue(self.allocator, file, registry, self.descriptor, field.kind.map, payload)) orelse {
                    try self.addUnknownRaw(tag.number, tag.wire_type, reader.input[start..reader.position()]);
                    continue;
                };
                self.add(field, value) catch |err| {
                    deinitValue(&value, self.allocator);
                    return err;
                };
                continue;
            }

            if (registryEnumDescriptor(file, registry, self.descriptor, field.kind)) |enumeration| {
                if (tag.wire_type == .length_delimited and field.cardinality == .repeated) {
                    const payload = try reader.readBytes();
                    var packed_reader = wire.Reader.init(payload);
                    while (!packed_reader.eof()) {
                        const value_start = packed_reader.position();
                        const value = try packed_reader.readInt32();
                        const value_end = packed_reader.position();
                        if (enumIsClosed(file, enumeration) and !enumHasNumber(enumeration, value)) {
                            try self.addUnknownVarintPayload(field.number, payload[value_start..value_end]);
                        } else {
                            try self.add(field, .{ .enumeration = value });
                        }
                    }
                    continue;
                }
                if (tag.wire_type != .varint) return error.InvalidWireType;
                const value = try reader.readInt32();
                if (enumIsClosed(file, enumeration) and !enumHasNumber(enumeration, value)) {
                    try self.addUnknownRaw(tag.number, tag.wire_type, reader.input[start..reader.position()]);
                } else {
                    try self.add(field, .{ .enumeration = value });
                }
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
                    if (closedEnumDescriptor(file, self.descriptor, field.kind)) |enumeration| {
                        const value_start = packed_reader.position();
                        const value = try packed_reader.readInt32();
                        const value_end = packed_reader.position();
                        if (enumHasNumber(enumeration, value)) {
                            try self.add(field, .{ .enumeration = value });
                        } else {
                            try self.addUnknownVarintPayload(field.number, payload[value_start..value_end]);
                        }
                    } else {
                        const value = try decodeScalarLike(field.kind, &packed_reader);
                        try self.add(field, value);
                    }
                }
                continue;
            }

            if (tag.wire_type != field.kind.wireType()) return error.InvalidWireType;
            if (closedEnumDescriptor(file, self.descriptor, field.kind)) |enumeration| {
                const value = try reader.readInt32();
                if (enumHasNumber(enumeration, value)) {
                    try self.add(field, .{ .enumeration = value });
                } else {
                    try self.addUnknownRaw(tag.number, tag.wire_type, reader.input[start..reader.position()]);
                }
                continue;
            }
            var value = try decodeValue(self.allocator, file, registry, self.descriptor, field.kind, reader);
            self.add(field, value) catch |err| {
                deinitValue(&value, self.allocator);
                return err;
            };
        }
        if (end_group != null) return error.TruncatedInput;
    }

    fn addUnknownRaw(self: *DynamicMessage, number: wire.FieldNumber, wire_type: wire.WireType, raw_bytes: []const u8) std.mem.Allocator.Error!void {
        const raw = try self.allocator.dupe(u8, raw_bytes);
        errdefer self.allocator.free(raw);
        try self.unknown_fields.append(self.allocator, .{
            .number = number,
            .wire_type = wire_type,
            .data = raw,
        });
    }

    fn addUnknownVarintPayload(self: *DynamicMessage, number: wire.FieldNumber, varint_payload: []const u8) DecodeError!void {
        var raw_writer = wire.Writer.init(self.allocator);
        defer raw_writer.deinit();
        try raw_writer.writeTag(number, .varint);
        try raw_writer.appendSlice(varint_payload);
        try self.addUnknownRaw(number, .varint, raw_writer.slice());
    }

    fn encodeMessageSet(self: *const DynamicMessage, file: *const schema.FileDescriptor, writer: *wire.Writer, deterministic: bool) EncodeError!void {
        if (deterministic) {
            const indexes = try self.allocator.alloc(usize, self.fields.items.len);
            defer self.allocator.free(indexes);
            for (indexes, 0..) |*index, i| index.* = i;
            std.mem.sort(usize, indexes, self, struct {
                fn lessThan(message: *const DynamicMessage, a: usize, b: usize) bool {
                    return message.fields.items[a].descriptor.number < message.fields.items[b].descriptor.number;
                }
            }.lessThan);
            for (indexes) |index| try encodeMessageSetEntry(self.descriptor, &self.fields.items[index], file, writer, true);

            const unknown_indexes = try self.allocator.alloc(usize, self.unknown_fields.items.len);
            defer self.allocator.free(unknown_indexes);
            for (unknown_indexes, 0..) |*index, i| index.* = i;
            std.mem.sort(usize, unknown_indexes, self, struct {
                fn lessThan(message: *const DynamicMessage, a: usize, b: usize) bool {
                    return message.unknown_fields.items[a].number < message.unknown_fields.items[b].number;
                }
            }.lessThan);
            for (unknown_indexes) |index| try encodeUnknownMessageSetField(&self.unknown_fields.items[index], writer);
            return;
        }

        for (self.fields.items) |*entry| try encodeMessageSetEntry(self.descriptor, entry, file, writer, false);
        for (self.unknown_fields.items) |*unknown| try encodeUnknownMessageSetField(unknown, writer);
    }

    fn decodeMessageSetItem(self: *DynamicMessage, file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, reader: *wire.Reader) DecodeError!void {
        var type_id: ?wire.FieldNumber = null;
        var payload: ?[]const u8 = null;

        while (try reader.nextTag()) |tag| {
            if (tag.wire_type == .end_group) {
                if (tag.number != 1) return error.InvalidFieldNumber;
                if (type_id) |number| {
                    if (payload) |bytes| try self.addMessageSetPayload(file, registry, number, bytes);
                }
                return;
            }
            switch (tag.number) {
                2 => {
                    if (tag.wire_type != .varint) return error.InvalidWireType;
                    const raw = try reader.readUInt32();
                    if (raw == 0 or raw > std.math.maxInt(wire.FieldNumber)) return error.InvalidFieldNumber;
                    type_id = @intCast(raw);
                },
                3 => {
                    if (tag.wire_type != .length_delimited) return error.InvalidWireType;
                    payload = try reader.readBytes();
                },
                else => try reader.skipValue(tag),
            }
        }
        return error.TruncatedInput;
    }

    fn addMessageSetPayload(self: *DynamicMessage, file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, number: wire.FieldNumber, payload: []const u8) DecodeError!void {
        const field = registryExtension(registry, self.descriptor, number) orelse {
            var raw_writer = wire.Writer.init(self.allocator);
            defer raw_writer.deinit();
            try raw_writer.writeBytes(number, payload);
            const raw = try self.allocator.dupe(u8, raw_writer.slice());
            errdefer self.allocator.free(raw);
            try self.unknown_fields.append(self.allocator, .{
                .number = number,
                .wire_type = .length_delimited,
                .data = raw,
            });
            return;
        };
        if (field.kind != .message or field.cardinality == .repeated or field.cardinality == .required) return error.TypeMismatch;
        var value = try decodeMessagePayload(self.allocator, file, registry, self.descriptor, field.kind.message, payload);
        self.add(field, value) catch |err| {
            deinitValue(&value, self.allocator);
            return err;
        };
    }
};

fn registryExtension(registry: ?*const registry_mod.Registry, descriptor: *const schema.MessageDescriptor, number: wire.FieldNumber) ?*const schema.FieldDescriptor {
    const reg = registry orelse return null;
    return reg.findExtension(descriptor.name, number);
}

fn encodeMessageSetEntry(host: *const schema.MessageDescriptor, entry: *const FieldValue, file: *const schema.FileDescriptor, writer: *wire.Writer, deterministic: bool) EncodeError!void {
    if (entry.descriptor.kind != .message or entry.descriptor.extendee == null or entry.descriptor.cardinality == .repeated or entry.descriptor.cardinality == .required) return error.TypeMismatch;
    if (!extensionExtendsMessage(entry.descriptor.extendee.?, host)) return error.TypeMismatch;
    for (entry.values.items) |value| {
        const message = switch (value) {
            .message => |message_value| message_value,
            else => return error.TypeMismatch,
        };
        var payload_writer = wire.Writer.init(writer.allocator);
        defer payload_writer.deinit();
        if (deterministic) {
            try message.encodeDeterministic(file, &payload_writer);
        } else {
            try message.encode(file, &payload_writer);
        }
        try writeMessageSetItem(writer, entry.descriptor.number, payload_writer.slice());
    }
}

fn encodeUnknownMessageSetField(unknown: *const UnknownField, writer: *wire.Writer) EncodeError!void {
    if (unknown.wire_type == .length_delimited) {
        var reader = wire.Reader.init(unknown.data);
        if ((try reader.nextTag())) |tag| {
            if (tag.number == unknown.number and tag.wire_type == .length_delimited) {
                const payload = try reader.readBytes();
                if (reader.eof()) {
                    try writeMessageSetItem(writer, unknown.number, payload);
                    return;
                }
            }
        }
    }
    try writer.appendSlice(unknown.data);
}

fn writeMessageSetItem(writer: *wire.Writer, type_id: wire.FieldNumber, payload: []const u8) EncodeError!void {
    try writer.writeTag(1, .start_group);
    try writer.writeUInt32(2, @intCast(type_id));
    try writer.writeMessage(3, payload);
    try writer.writeTag(1, .end_group);
}

fn extensionExtendsMessage(extendee: []const u8, message: *const schema.MessageDescriptor) bool {
    const trimmed = if (std.mem.startsWith(u8, extendee, ".")) extendee[1..] else extendee;
    const leaf = if (std.mem.lastIndexOfScalar(u8, trimmed, '.')) |idx| trimmed[idx + 1 ..] else trimmed;
    return std.mem.eql(u8, trimmed, message.name) or std.mem.eql(u8, leaf, message.name);
}

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
    registry: ?*const registry_mod.Registry,
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
            break :blk try decodeMessagePayload(allocator, file, registry, current, name, payload);
        },
        .group => error.TypeMismatch,
        .map => error.TypeMismatch,
    };
}

fn decodeMessagePayload(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    registry: ?*const registry_mod.Registry,
    current: *const schema.MessageDescriptor,
    name: []const u8,
    payload: []const u8,
) DecodeError!Value {
    const descriptor = resolveMessageDescriptorWithRegistry(file, registry, current, name) orelse return error.TypeMismatch;
    const message = try allocator.create(DynamicMessage);
    message.* = DynamicMessage.init(allocator, descriptor);
    errdefer {
        message.deinit();
        allocator.destroy(message);
    }
    if (registry) |reg| {
        try message.decodeWithRegistry(file, reg, payload);
    } else {
        try message.decode(file, payload);
    }
    return .{ .message = message };
}

fn decodeMapEntryValue(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    registry: ?*const registry_mod.Registry,
    current: *const schema.MessageDescriptor,
    map_type: schema.MapType,
    payload: []const u8,
) DecodeError!?Value {
    var entry_reader = wire.Reader.init(payload);

    var maybe_key: ?Value = null;
    var maybe_value: ?Value = null;
    var success = false;
    defer {
        if (!success) {
            if (maybe_key) |*key| deinitValue(key, allocator);
            if (maybe_value) |*map_value| deinitValue(map_value, allocator);
        }
    }

    while (try entry_reader.nextTag()) |tag| {
        switch (tag.number) {
            1 => {
                if (tag.wire_type != map_type.key.wireType()) return error.InvalidWireType;
                if (maybe_key) |*old| deinitValue(old, allocator);
                maybe_key = try decodeValue(allocator, file, registry, current, .{ .scalar = map_type.key }, &entry_reader);
            },
            2 => {
                if (tag.wire_type != map_type.value.wireType()) return error.InvalidWireType;
                if (maybe_value) |*old| deinitValue(old, allocator);
                if (closedEnumDescriptor(file, current, map_type.value.*)) |enumeration| {
                    const value = try entry_reader.readInt32();
                    if (!enumHasNumber(enumeration, value)) return null;
                    maybe_value = .{ .enumeration = value };
                } else {
                    maybe_value = try decodeValue(allocator, file, registry, current, map_type.value.*, &entry_reader);
                }
            },
            else => try entry_reader.skipValue(tag),
        }
    }

    var key = maybe_key orelse try defaultValue(allocator, file, current, .{ .scalar = map_type.key });
    maybe_key = null;
    var map_value = maybe_value orelse try defaultValue(allocator, file, current, map_type.value.*);
    maybe_value = null;
    defer {
        if (!success) {
            deinitValue(&key, allocator);
            deinitValue(&map_value, allocator);
        }
    }

    const entry = try allocator.create(MapEntry);
    entry.* = .{ .key = key, .value = map_value };
    success = true;
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
    registry: ?*const registry_mod.Registry,
    current: *const schema.MessageDescriptor,
    field: *const schema.FieldDescriptor,
    reader: *wire.Reader,
) DecodeError!Value {
    const name = switch (field.kind) {
        .group => |group_name| group_name,
        else => return error.TypeMismatch,
    };
    const descriptor = resolveMessageDescriptorWithRegistry(file, registry, current, name) orelse return error.TypeMismatch;
    const message = try allocator.create(DynamicMessage);
    message.* = DynamicMessage.init(allocator, descriptor);
    errdefer {
        message.deinit();
        allocator.destroy(message);
    }
    try message.decodeStream(file, registry, reader, field.number);
    return .{ .group = message };
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
        if (reg.findMessage(name, current.name)) |message| return message;
        if (reg.findMessage(name, null)) |message| return message;
    }
    return resolveMessageDescriptor(file, current, name);
}

fn closedEnumDescriptor(file: *const schema.FileDescriptor, current: *const schema.MessageDescriptor, kind: schema.FieldKind) ?*const schema.EnumDescriptor {
    const enum_name = switch (kind) {
        .enumeration => |name| name,
        else => return null,
    };
    const enumeration = current.findEnumDeep(enum_name) orelse file.findEnumDeep(enum_name) orelse return null;
    return if (enumIsClosed(file, enumeration)) enumeration else null;
}

fn registryEnumDescriptor(file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, current: *const schema.MessageDescriptor, kind: schema.FieldKind) ?*const schema.EnumDescriptor {
    const enum_name = switch (kind) {
        .enumeration => |name| name,
        .message => |name| name,
        else => return null,
    };
    if (registry) |reg| {
        if (reg.findEnum(enum_name, current.name)) |enumeration| return enumeration;
        if (reg.findEnum(enum_name, null)) |enumeration| return enumeration;
    }
    return current.findEnumDeep(enum_name) orelse file.findEnumDeep(enum_name);
}

fn enumHasNumber(enumeration: *const schema.EnumDescriptor, number: i32) bool {
    for (enumeration.values.items) |value| {
        if (value.number == number) return true;
    }
    return false;
}

fn enumIsClosed(file: *const schema.FileDescriptor, enumeration: *const schema.EnumDescriptor) bool {
    if (enumeration.features) |features| return features.enum_type == .closed;
    return file.features.enum_type == .closed;
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

fn mapEntryLessThan(a: Value, b: Value) bool {
    if (a != .map_entry or b != .map_entry) return false;
    return valueLessThan(a.map_entry.key, b.map_entry.key);
}

fn valueLessThan(a: Value, b: Value) bool {
    return switch (a) {
        .boolean => |av| b == .boolean and !av and b.boolean,
        .int32 => |av| b == .int32 and av < b.int32,
        .int64 => |av| b == .int64 and av < b.int64,
        .uint32 => |av| b == .uint32 and av < b.uint32,
        .uint64 => |av| b == .uint64 and av < b.uint64,
        .sint32 => |av| b == .sint32 and av < b.sint32,
        .sint64 => |av| b == .sint64 and av < b.sint64,
        .fixed32 => |av| b == .fixed32 and av < b.fixed32,
        .fixed64 => |av| b == .fixed64 and av < b.fixed64,
        .sfixed32 => |av| b == .sfixed32 and av < b.sfixed32,
        .sfixed64 => |av| b == .sfixed64 and av < b.sfixed64,
        .string => |av| b == .string and std.mem.lessThan(u8, av, b.string),
        else => false,
    };
}

fn valueAsDefault(value: Value) DefaultValue {
    return switch (value) {
        .double => |v| .{ .double = v },
        .float => |v| .{ .float = v },
        .int32 => |v| .{ .int32 = v },
        .int64 => |v| .{ .int64 = v },
        .uint32 => |v| .{ .uint32 = v },
        .uint64 => |v| .{ .uint64 = v },
        .sint32 => |v| .{ .sint32 = v },
        .sint64 => |v| .{ .sint64 = v },
        .fixed32 => |v| .{ .fixed32 = v },
        .fixed64 => |v| .{ .fixed64 = v },
        .sfixed32 => |v| .{ .sfixed32 = v },
        .sfixed64 => |v| .{ .sfixed64 = v },
        .boolean => |v| .{ .boolean = v },
        .string => |v| .{ .string = v },
        .bytes => |v| .{ .bytes = v },
        .enumeration => |v| .{ .enumeration = v },
        else => .none,
    };
}

fn defaultForField(field: *const schema.FieldDescriptor) DefaultValue {
    if (field.default_value) |value| {
        return defaultFromOption(field.kind, value);
    }
    return switch (field.kind) {
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
            .string => .{ .string = "" },
            .bytes => .{ .bytes = "" },
        },
        .enumeration => .{ .enumeration = 0 },
        else => .none,
    };
}

fn defaultFromOption(kind: schema.FieldKind, value: schema.OptionValue) DefaultValue {
    return switch (kind) {
        .scalar => |scalar| switch (scalar) {
            .double => .{ .double = optionFloat(f64, value) orelse 0 },
            .float => .{ .float = optionFloat(f32, value) orelse 0 },
            .int32 => .{ .int32 = optionInt(i32, value) orelse 0 },
            .int64 => .{ .int64 = optionInt(i64, value) orelse 0 },
            .uint32 => .{ .uint32 = optionInt(u32, value) orelse 0 },
            .uint64 => .{ .uint64 = optionInt(u64, value) orelse 0 },
            .sint32 => .{ .sint32 = optionInt(i32, value) orelse 0 },
            .sint64 => .{ .sint64 = optionInt(i64, value) orelse 0 },
            .fixed32 => .{ .fixed32 = optionInt(u32, value) orelse 0 },
            .fixed64 => .{ .fixed64 = optionInt(u64, value) orelse 0 },
            .sfixed32 => .{ .sfixed32 = optionInt(i32, value) orelse 0 },
            .sfixed64 => .{ .sfixed64 = optionInt(i64, value) orelse 0 },
            .bool => .{ .boolean = schema.optionAsBool(value) orelse false },
            .string => .{ .string = optionText(value) orelse "" },
            .bytes => .{ .bytes = optionText(value) orelse "" },
        },
        .enumeration => .{ .enumeration = optionInt(i32, value) orelse 0 },
        else => .none,
    };
}

fn optionText(value: schema.OptionValue) ?[]const u8 {
    return switch (value) {
        .string => |text| text,
        .identifier => |text| text,
        else => null,
    };
}

fn optionInt(comptime T: type, value: schema.OptionValue) ?T {
    return switch (value) {
        .integer => |v| if (v >= std.math.minInt(T) and v <= std.math.maxInt(T)) @intCast(v) else null,
        .identifier, .string => |text| std.fmt.parseInt(T, text, 10) catch null,
        else => null,
    };
}

fn optionFloat(comptime T: type, value: schema.OptionValue) ?T {
    return switch (value) {
        .float => |v| @floatCast(v),
        .integer => |v| @floatFromInt(v),
        .identifier, .string => |text| std.fmt.parseFloat(T, text) catch null,
        else => null,
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

test "dynamic has and getOrDefault expose proto2 defaults and explicit values" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto2";
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message Defaults {
        \\  optional int32 count = 1 [default = 42];
        \\  optional string name = 2 [default = "anon"];
        \\  optional bool enabled = 3 [default = true];
        \\  optional Kind kind = 4 [default = ADMIN];
        \\  optional bytes blob = 5;
        \\}
    ;
    var file = try parser.Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("Defaults").?;

    var message = DynamicMessage.init(allocator, desc);
    defer message.deinit();
    try std.testing.expect(!message.has(desc.findField("count").?));
    try std.testing.expectEqual(@as(i32, 42), message.getOrDefault(desc.findField("count").?).int32);
    try std.testing.expectEqualStrings("anon", message.getOrDefault(desc.findField("name").?).string);
    try std.testing.expect(message.getOrDefault(desc.findField("enabled").?).boolean);
    // Enum symbolic defaults resolve through the parser into their numeric value.
    try std.testing.expectEqual(@as(i32, 1), message.getOrDefault(desc.findField("kind").?).enumeration);
    try std.testing.expectEqualStrings("", message.getOrDefault(desc.findField("blob").?).bytes);

    try message.add(desc.findField("count").?, .{ .int32 = 7 });
    try std.testing.expect(message.has(desc.findField("count").?));
    try std.testing.expectEqual(@as(i32, 7), message.getOrDefault(desc.findField("count").?).int32);
}

test "dynamic decodeInitialized enforces proto2 required fields" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto2";
        \\message Required { required int32 id = 1; optional string name = 2; }
    ;
    var file = try parser.Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("Required").?;

    var writer = wire.Writer.init(allocator);
    defer writer.deinit();
    try writer.writeString(2, "missing id");

    var message = DynamicMessage.init(allocator, desc);
    defer message.deinit();
    try std.testing.expectError(error.MissingRequiredField, message.decodeInitialized(&file, writer.slice()));

    writer.clearRetainingCapacity();
    try writer.writeInt32(1, 9);
    try message.decodeInitialized(&file, writer.slice());
    try std.testing.expectEqual(@as(i32, 9), message.get("id").?.values.items[0].int32);
}

test "dynamic encodeInitialized enforces proto2 required fields" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto2";
        \\message Required { required int32 id = 1; optional string name = 2; }
    ;
    var file = try parser.Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("Required").?;

    var message = DynamicMessage.init(allocator, desc);
    defer message.deinit();
    var writer = wire.Writer.init(allocator);
    defer writer.deinit();
    try std.testing.expectError(error.MissingRequiredField, message.encodeInitialized(&file, &writer));
    try std.testing.expectError(error.MissingRequiredField, message.encodedInitialized(&file));
    try std.testing.expectError(error.MissingRequiredField, message.encodeDeterministicInitialized(&file, &writer));
    try std.testing.expectError(error.MissingRequiredField, message.encodedDeterministicInitialized(&file));

    try message.add(desc.findField("id").?, .{ .int32 = 9 });
    try message.encodeInitialized(&file, &writer);
    try std.testing.expect(writer.slice().len != 0);
    const encoded = try message.encodedInitialized(&file);
    defer allocator.free(encoded);
    try std.testing.expect(encoded.len != 0);
    const deterministic = try message.encodedDeterministicInitialized(&file);
    defer allocator.free(deterministic);
    try std.testing.expectEqualSlices(u8, encoded, deterministic);
}

test "dynamic reports missing required field path" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto2";
        \\message Child { required int32 id = 1; }
        \\message Parent { required string name = 1; optional Child child = 2; }
    ;
    var file = try parser.Parser.parse(allocator, source);
    defer file.deinit();
    const parent_desc = file.findMessage("Parent").?;
    const child_desc = file.findMessage("Child").?;

    var parent = DynamicMessage.init(allocator, parent_desc);
    defer parent.deinit();
    const missing_name = (try parent.missingRequiredFieldPath(allocator)).?;
    defer allocator.free(missing_name);
    try std.testing.expectEqualStrings("name", missing_name);

    try parent.add(parent_desc.findField("name").?, .{ .string = try allocator.dupe(u8, "p") });
    const child = try allocator.create(DynamicMessage);
    child.* = DynamicMessage.init(allocator, child_desc);
    try parent.add(parent_desc.findField("child").?, .{ .message = child });
    const missing_child = (try parent.missingRequiredFieldPath(allocator)).?;
    defer allocator.free(missing_child);
    try std.testing.expectEqualStrings("child.id", missing_child);
    try std.testing.expectError(error.MissingRequiredField, parent.validateRequired());

    try child.add(child_desc.findField("id").?, .{ .int32 = 1 });
    try parent.validateRequired();
    try std.testing.expectEqual(@as(?[]u8, null), try parent.missingRequiredFieldPath(allocator));
}

test "dynamic mergeFrom appends repeated fields overrides singular and preserves unknown" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\message Merge { int32 id = 1; repeated string tags = 2; oneof pick { string name = 3; int32 code = 4; } }
    ;
    var file = try parser.Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("Merge").?;

    var left = DynamicMessage.init(allocator, desc);
    defer left.deinit();
    try left.add(desc.findField("id").?, .{ .int32 = 1 });
    try left.add(desc.findField("tags").?, .{ .string = try allocator.dupe(u8, "a") });
    try left.add(desc.findField("name").?, .{ .string = try allocator.dupe(u8, "old") });

    var right = DynamicMessage.init(allocator, desc);
    defer right.deinit();
    try right.add(desc.findField("id").?, .{ .int32 = 2 });
    try right.add(desc.findField("tags").?, .{ .string = try allocator.dupe(u8, "b") });
    try right.add(desc.findField("code").?, .{ .int32 = 9 });
    var unknown_writer = wire.Writer.init(allocator);
    defer unknown_writer.deinit();
    try unknown_writer.writeUInt32(99, 1);
    try right.unknown_fields.append(allocator, .{ .number = 99, .wire_type = .varint, .data = try allocator.dupe(u8, unknown_writer.slice()) });

    try left.mergeFrom(&right);
    try std.testing.expectEqual(@as(i32, 2), left.get("id").?.values.items[0].int32);
    try std.testing.expectEqual(@as(usize, 2), left.get("tags").?.values.items.len);
    try std.testing.expect(left.get("name") == null);
    try std.testing.expectEqual(@as(i32, 9), left.get("code").?.values.items[0].int32);
    try std.testing.expectEqual(@as(usize, 1), left.unknownCount());
}

test "dynamic decodeWithRegistry decodes proto2 extensions" {
    const allocator = std.testing.allocator;
    var file = try parser.Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host { optional int32 id = 1; extensions 100 to max; }
        \\extend Host { optional string note = 100; }
    );
    defer file.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);
    const host = file.findMessage("Host").?;

    var writer = wire.Writer.init(allocator);
    defer writer.deinit();
    try writer.writeInt32(1, 7);
    try writer.writeString(100, "hello");

    var msg = DynamicMessage.init(allocator, host);
    defer msg.deinit();
    try msg.decodeWithRegistry(&file, &registry, writer.slice());
    try std.testing.expectEqual(@as(usize, 0), msg.unknownCount());
    try std.testing.expectEqualSlices(u8, "hello", msg.get("note").?.values.items[0].string);
}

test "dynamic decodeWithRegistry resolves imported message fields" {
    const allocator = std.testing.allocator;
    var common = try parser.Parser.parse(allocator,
        \\syntax = "proto2";
        \\package common;
        \\message User { optional string name = 1; }
    );
    defer common.deinit();
    var app = try parser.Parser.parse(allocator,
        \\syntax = "proto2";
        \\package app;
        \\message Request { optional common.User user = 1; }
    );
    defer app.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);

    const user_desc = common.findMessage("User").?;
    var user_msg = DynamicMessage.init(allocator, user_desc);
    defer user_msg.deinit();
    try user_msg.add(user_desc.findField("name").?, .{ .string = try allocator.dupe(u8, "Ada") });
    const user_bytes = try user_msg.encoded(&common);
    defer allocator.free(user_bytes);

    var writer = wire.Writer.init(allocator);
    defer writer.deinit();
    try writer.writeMessage(1, user_bytes);

    const request_desc = app.findMessage("Request").?;
    var request = DynamicMessage.init(allocator, request_desc);
    defer request.deinit();
    try request.decodeWithRegistry(&app, &registry, writer.slice());
    const decoded_user = request.get("user").?.values.items[0].message;
    try std.testing.expectEqualStrings("User", decoded_user.descriptor.name);
    try std.testing.expectEqualSlices(u8, "Ada", decoded_user.get("name").?.values.items[0].string);
}

test "dynamic decodeWithRegistry resolves imported enum fields" {
    const allocator = std.testing.allocator;
    var common = try parser.Parser.parse(allocator,
        \\syntax = "proto2";
        \\package common;
        \\enum Kind { A = 1; B = 2; }
    );
    defer common.deinit();
    var app = try parser.Parser.parse(allocator,
        \\syntax = "proto2";
        \\package app;
        \\message Event { optional common.Kind kind = 1; repeated common.Kind many = 2; }
    );
    defer app.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);

    var writer = wire.Writer.init(allocator);
    defer writer.deinit();
    try writer.writeInt32(1, 2);
    try writer.writeInt32(2, 1);
    try writer.writeInt32(2, 123);

    const event_desc = app.findMessage("Event").?;
    var event = DynamicMessage.init(allocator, event_desc);
    defer event.deinit();
    try event.decodeWithRegistry(&app, &registry, writer.slice());
    try std.testing.expectEqual(@as(i32, 2), event.get("kind").?.values.items[0].enumeration);
    try std.testing.expectEqual(@as(i32, 1), event.get("many").?.values.items[0].enumeration);
    try std.testing.expectEqual(@as(usize, 1), event.get("many").?.values.items.len);
    try std.testing.expectEqual(@as(usize, 1), event.unknownCount());
}

test "dynamic encodes extension fields using extension descriptors" {
    const allocator = std.testing.allocator;
    var file = try parser.Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host { extensions 100 to max; }
        \\extend Host { optional int32 score = 100; }
    );
    defer file.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);
    const host = file.findMessage("Host").?;
    const score = registry.findExtension("demo.Host", 100).?;

    var msg = DynamicMessage.init(allocator, host);
    defer msg.deinit();
    try msg.add(score, .{ .int32 = 123 });
    const encoded = try msg.encoded(&file);
    defer allocator.free(encoded);
    try std.testing.expectEqualSlices(u8, &.{ 0xa0, 0x06, 0x7b }, encoded);

    var decoded = DynamicMessage.init(allocator, host);
    defer decoded.deinit();
    try decoded.decodeWithRegistry(&file, &registry, encoded);
    try std.testing.expectEqual(@as(i32, 123), decoded.get("score").?.values.items[0].int32);
}

test "dynamic encodes and decodes proto2 MessageSet items" {
    const allocator = std.testing.allocator;
    var file = try parser.Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host { option message_set_wire_format = true; extensions 4 to max; }
        \\message Ext { optional int32 value = 1; }
        \\extend Host { optional Ext ext = 100; }
    );
    defer file.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);
    const host = file.findMessage("Host").?;
    const ext_desc = file.findMessage("Ext").?;
    const ext_field = registry.findExtension("demo.Host", 100).?;

    const ext_msg = try allocator.create(DynamicMessage);
    ext_msg.* = DynamicMessage.init(allocator, ext_desc);
    try ext_msg.add(ext_desc.findField("value").?, .{ .int32 = 7 });

    var msg = DynamicMessage.init(allocator, host);
    defer msg.deinit();
    try msg.add(ext_field, .{ .message = ext_msg });

    const encoded = try msg.encoded(&file);
    defer allocator.free(encoded);
    try std.testing.expectEqualSlices(u8, &.{ 0x0b, 0x10, 0x64, 0x1a, 0x02, 0x08, 0x07, 0x0c }, encoded);

    const deterministic = try msg.encodedDeterministic(&file);
    defer allocator.free(deterministic);
    try std.testing.expectEqualSlices(u8, encoded, deterministic);

    var decoded = DynamicMessage.init(allocator, host);
    defer decoded.deinit();
    try decoded.decodeWithRegistry(&file, &registry, encoded);
    const decoded_ext = decoded.get("ext").?.values.items[0].message;
    try std.testing.expectEqual(@as(i32, 7), decoded_ext.get("value").?.values.items[0].int32);
}

test "dynamic MessageSet accepts payload before type id and preserves unknown items" {
    const allocator = std.testing.allocator;
    var file = try parser.Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host { option message_set_wire_format = true; extensions 4 to max; }
        \\message Ext { optional int32 value = 1; }
        \\extend Host { optional Ext ext = 100; }
    );
    defer file.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);
    const host = file.findMessage("Host").?;

    var reordered = wire.Writer.init(allocator);
    defer reordered.deinit();
    try reordered.writeTag(1, .start_group);
    try reordered.writeMessage(3, &.{ 0x08, 0x09 });
    try reordered.writeUInt32(2, 100);
    try reordered.writeTag(1, .end_group);

    var decoded = DynamicMessage.init(allocator, host);
    defer decoded.deinit();
    try decoded.decodeWithRegistry(&file, &registry, reordered.slice());
    try std.testing.expectEqual(@as(i32, 9), decoded.get("ext").?.values.items[0].message.get("value").?.values.items[0].int32);

    var unknown = wire.Writer.init(allocator);
    defer unknown.deinit();
    try unknown.writeTag(1, .start_group);
    try unknown.writeUInt32(2, 150);
    try unknown.writeMessage(3, &.{ 0x08, 0x2a });
    try unknown.writeTag(1, .end_group);

    var unknown_msg = DynamicMessage.init(allocator, host);
    defer unknown_msg.deinit();
    try unknown_msg.decodeWithRegistry(&file, &registry, unknown.slice());
    try std.testing.expectEqual(@as(usize, 1), unknown_msg.unknownCount());
    try std.testing.expectEqual(@as(wire.FieldNumber, 150), unknown_msg.unknown_fields.items[0].number);
    try std.testing.expectEqual(wire.WireType.length_delimited, unknown_msg.unknown_fields.items[0].wire_type);

    const unknown_roundtrip = try unknown_msg.encoded(&file);
    defer allocator.free(unknown_roundtrip);
    try std.testing.expectEqualSlices(u8, unknown.slice(), unknown_roundtrip);
}

test "dynamic closed enum unknown values are preserved as unknown fields" {
    const allocator = std.testing.allocator;
    var file = try parser.Parser.parse(allocator,
        \\syntax = "proto2";
        \\enum Kind { A = 1; B = 2; }
        \\message M {
        \\  optional Kind single = 1;
        \\  repeated Kind many = 2;
        \\  repeated Kind packed = 3 [packed = true];
        \\}
    );
    defer file.deinit();
    const desc = file.findMessage("M").?;

    var packed_payload = wire.Writer.init(allocator);
    defer packed_payload.deinit();
    try packed_payload.writeVarint(2);
    try packed_payload.writeVarint(123);

    var encoded = wire.Writer.init(allocator);
    defer encoded.deinit();
    try encoded.writeInt32(1, 123);
    try encoded.writeInt32(2, 1);
    try encoded.writeInt32(2, 123);
    try encoded.writeBytes(3, packed_payload.slice());

    var msg = DynamicMessage.init(allocator, desc);
    defer msg.deinit();
    try msg.decode(&file, encoded.slice());

    try std.testing.expect(msg.get("single") == null);
    try std.testing.expectEqual(@as(i32, 1), msg.get("many").?.values.items[0].enumeration);
    try std.testing.expectEqual(@as(usize, 1), msg.get("many").?.values.items.len);
    try std.testing.expectEqual(@as(i32, 2), msg.get("packed").?.values.items[0].enumeration);
    try std.testing.expectEqual(@as(usize, 1), msg.get("packed").?.values.items.len);
    try std.testing.expectEqual(@as(usize, 3), msg.unknownCount());

    const unknown_single = try msg.unknownByNumberAlloc(allocator, 1);
    defer allocator.free(unknown_single);
    try std.testing.expectEqual(@as(usize, 1), unknown_single.len);
    try std.testing.expectEqualSlices(u8, &.{ 0x08, 0x7b }, unknown_single[0].data);

    const unknown_many = try msg.unknownByNumberAlloc(allocator, 2);
    defer allocator.free(unknown_many);
    try std.testing.expectEqual(@as(usize, 1), unknown_many.len);
    try std.testing.expectEqualSlices(u8, &.{ 0x10, 0x7b }, unknown_many[0].data);

    const unknown_packed = try msg.unknownByNumberAlloc(allocator, 3);
    defer allocator.free(unknown_packed);
    try std.testing.expectEqual(@as(usize, 1), unknown_packed.len);
    try std.testing.expectEqualSlices(u8, &.{ 0x18, 0x7b }, unknown_packed[0].data);
}

test "dynamic open enums keep unknown numeric values" {
    const allocator = std.testing.allocator;
    var file = try parser.Parser.parse(allocator,
        \\syntax = "proto3";
        \\enum Kind { A = 0; B = 1; }
        \\message M { Kind single = 1; repeated Kind many = 2; }
    );
    defer file.deinit();
    const desc = file.findMessage("M").?;

    var encoded = wire.Writer.init(allocator);
    defer encoded.deinit();
    try encoded.writeInt32(1, 123);
    try encoded.writeInt32(2, 123);

    var msg = DynamicMessage.init(allocator, desc);
    defer msg.deinit();
    try msg.decode(&file, encoded.slice());
    try std.testing.expectEqual(@as(i32, 123), msg.get("single").?.values.items[0].enumeration);
    try std.testing.expectEqual(@as(i32, 123), msg.get("many").?.values.items[0].enumeration);
    try std.testing.expectEqual(@as(usize, 0), msg.unknownCount());
}

test "dynamic enum-level features override file enum openness" {
    const allocator = std.testing.allocator;
    {
        var file = try parser.Parser.parse(allocator,
            \\edition = "2023";
            \\option features.enum_type = CLOSED;
            \\enum Kind { option features.enum_type = OPEN; A = 0; B = 1; }
            \\message M { Kind single = 1; repeated Kind many = 2; }
        );
        defer file.deinit();
        const desc = file.findMessage("M").?;

        var encoded = wire.Writer.init(allocator);
        defer encoded.deinit();
        try encoded.writeInt32(1, 123);
        try encoded.writeInt32(2, 123);

        var msg = DynamicMessage.init(allocator, desc);
        defer msg.deinit();
        try msg.decode(&file, encoded.slice());
        try std.testing.expectEqual(@as(i32, 123), msg.get("single").?.values.items[0].enumeration);
        try std.testing.expectEqual(@as(i32, 123), msg.get("many").?.values.items[0].enumeration);
        try std.testing.expectEqual(@as(usize, 0), msg.unknownCount());
    }
    {
        var file = try parser.Parser.parse(allocator,
            \\edition = "2023";
            \\option features.enum_type = OPEN;
            \\enum Kind { option features.enum_type = CLOSED; A = 0; B = 1; }
            \\message M { Kind single = 1; repeated Kind many = 2; }
        );
        defer file.deinit();
        const desc = file.findMessage("M").?;

        var encoded = wire.Writer.init(allocator);
        defer encoded.deinit();
        try encoded.writeInt32(1, 123);
        try encoded.writeInt32(2, 1);
        try encoded.writeInt32(2, 123);

        var msg = DynamicMessage.init(allocator, desc);
        defer msg.deinit();
        try msg.decode(&file, encoded.slice());
        try std.testing.expect(msg.get("single") == null);
        try std.testing.expectEqual(@as(i32, 1), msg.get("many").?.values.items[0].enumeration);
        try std.testing.expectEqual(@as(usize, 1), msg.get("many").?.values.items.len);
        try std.testing.expectEqual(@as(usize, 2), msg.unknownCount());
    }
}

test "dynamic closed enum map entries with unknown values are preserved whole" {
    const allocator = std.testing.allocator;
    var file = try parser.Parser.parse(allocator,
        \\edition = "2023";
        \\option features.enum_type = CLOSED;
        \\enum Kind { A = 0; B = 1; }
        \\message M { map<string, Kind> vals = 1; }
    );
    defer file.deinit();
    const desc = file.findMessage("M").?;

    var bad_entry = wire.Writer.init(allocator);
    defer bad_entry.deinit();
    try bad_entry.writeString(1, "bad");
    try bad_entry.writeInt32(2, 123);

    var good_entry = wire.Writer.init(allocator);
    defer good_entry.deinit();
    try good_entry.writeString(1, "ok");
    try good_entry.writeInt32(2, 1);

    var encoded = wire.Writer.init(allocator);
    defer encoded.deinit();
    try encoded.writeMessage(1, bad_entry.slice());
    const bad_raw = try allocator.dupe(u8, encoded.slice());
    defer allocator.free(bad_raw);
    try encoded.writeMessage(1, good_entry.slice());

    var msg = DynamicMessage.init(allocator, desc);
    defer msg.deinit();
    try msg.decode(&file, encoded.slice());
    try std.testing.expectEqual(@as(usize, 1), msg.get("vals").?.values.items.len);
    const entry = msg.get("vals").?.values.items[0].map_entry;
    try std.testing.expectEqualStrings("ok", entry.key.string);
    try std.testing.expectEqual(@as(i32, 1), entry.value.enumeration);
    try std.testing.expectEqual(@as(usize, 1), msg.unknownCount());
    try std.testing.expectEqualSlices(u8, bad_raw, msg.unknown_fields.items[0].data);
}

test "dynamic deterministic encoding sorts fields and unknowns by number" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\message Order { int32 a = 1; int32 b = 2; repeated int32 c = 3; }
    ;
    var file = try parser.Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("Order").?;

    var msg = DynamicMessage.init(allocator, desc);
    defer msg.deinit();
    try msg.add(desc.findField("b").?, .{ .int32 = 2 });
    try msg.add(desc.findField("a").?, .{ .int32 = 1 });
    try msg.add(desc.findField("c").?, .{ .int32 = 3 });
    try msg.unknown_fields.append(allocator, .{ .number = 50, .wire_type = .varint, .data = try allocator.dupe(u8, &.{ 0x90, 0x03, 0x01 }) });
    try msg.unknown_fields.append(allocator, .{ .number = 40, .wire_type = .varint, .data = try allocator.dupe(u8, &.{ 0xc0, 0x02, 0x01 }) });

    const normal = try msg.encoded(&file);
    defer allocator.free(normal);
    try std.testing.expectEqualSlices(u8, &.{ 0x10, 0x02, 0x08, 0x01, 0x1a, 0x01, 0x03, 0x90, 0x03, 0x01, 0xc0, 0x02, 0x01 }, normal);

    const deterministic = try msg.encodedDeterministic(&file);
    defer allocator.free(deterministic);
    try std.testing.expectEqualSlices(u8, &.{ 0x08, 0x01, 0x10, 0x02, 0x1a, 0x01, 0x03, 0xc0, 0x02, 0x01, 0x90, 0x03, 0x01 }, deterministic);
}

test "dynamic deterministic encoding sorts map entries by key" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\message M { map<string, int32> counts = 1; }
    ;
    var file = try parser.Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("M").?;
    const field = desc.findField("counts").?;

    var msg = DynamicMessage.init(allocator, desc);
    defer msg.deinit();
    const b = try allocator.create(MapEntry);
    b.* = .{ .key = .{ .string = try allocator.dupe(u8, "b") }, .value = .{ .int32 = 2 } };
    try msg.add(field, .{ .map_entry = b });
    const a = try allocator.create(MapEntry);
    a.* = .{ .key = .{ .string = try allocator.dupe(u8, "a") }, .value = .{ .int32 = 1 } };
    try msg.add(field, .{ .map_entry = a });

    const deterministic = try msg.encodedDeterministic(&file);
    defer allocator.free(deterministic);
    try std.testing.expect(std.mem.indexOf(u8, deterministic, &.{ 'a', 0x10, 0x01 }).? < std.mem.indexOf(u8, deterministic, &.{ 'b', 0x10, 0x02 }).?);
}

test "dynamic unknownByNumberAlloc returns non-contiguous unknown fields" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\message Empty {}
    ;
    var file = try parser.Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("Empty").?;

    var writer = wire.Writer.init(allocator);
    defer writer.deinit();
    try writer.writeUInt32(100, 1);
    try writer.writeUInt32(101, 2);
    try writer.writeUInt32(100, 3);

    var msg = DynamicMessage.init(allocator, desc);
    defer msg.deinit();
    try msg.decode(&file, writer.slice());
    const fields = try msg.unknownByNumberAlloc(allocator, 100);
    defer allocator.free(fields);
    try std.testing.expectEqual(@as(usize, 2), fields.len);
    try std.testing.expectEqual(@as(wire.FieldNumber, 100), fields[0].number);
    try std.testing.expectEqual(@as(wire.FieldNumber, 100), fields[1].number);
}
