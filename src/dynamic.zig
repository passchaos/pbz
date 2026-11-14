const std = @import("std");

const wire = @import("wire.zig");

const schema = @import("schema.zig");

const parser = @import("parser.zig");

const registry_mod = @import("registry.zig");

pub const DecodeError = wire.Error || std.mem.Allocator.Error || error{ TypeMismatch, InvalidUtf8 };

pub const EncodeError = wire.Error || std.mem.Allocator.Error || error{ TypeMismatch, InvalidUtf8 };

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

    pub fn clearRetainingCapacity(self: *FieldValue, allocator: std.mem.Allocator) void {
        for (self.values.items) |*value| deinitValue(value, allocator);
        self.values.clearRetainingCapacity();
    }
};

pub fn defaultValueForField(field: *const schema.FieldDescriptor) DefaultValue {
    if (field.isRepeatedLike()) return .none;
    return defaultForField(field);
}

pub fn defaultValueForFieldWithFile(file: *const schema.FileDescriptor, current: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) DefaultValue {
    return defaultValueForFieldWithRegistry(file, null, current, field);
}

pub fn defaultValueForFieldWithRegistry(file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, current: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) DefaultValue {
    if (field.isRepeatedLike()) return .none;
    return defaultForFieldWithRegistry(file, registry, current, field);
}

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

    /// Deep-clone field values and unknown fields into `allocator`.
    ///
    /// Descriptors are intentionally not cloned: DynamicMessage values are
    /// views over an existing schema graph. Callers moving a dynamic message out
    /// of an arena must keep the registry/file descriptors alive for at least as
    /// long as the cloned message.
    pub fn cloneOwned(self: *const DynamicMessage, allocator: std.mem.Allocator) std.mem.Allocator.Error!DynamicMessage {
        const cloned = try cloneDynamicMessage(allocator, self);
        defer allocator.destroy(cloned);
        return cloned.*;
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

    pub fn listFieldsAlloc(self: *const DynamicMessage, allocator: std.mem.Allocator) std.mem.Allocator.Error![]*const schema.FieldDescriptor {
        var fields: std.ArrayList(*const schema.FieldDescriptor) = .empty;
        errdefer fields.deinit(allocator);
        try fields.ensureTotalCapacity(allocator, self.fields.items.len);
        for (self.fields.items) |*entry| {
            if (entry.values.items.len == 0) continue;
            fields.appendAssumeCapacity(entry.descriptor);
        }
        const result = try fields.toOwnedSlice(allocator);
        sortFieldDescriptorsByNumber(result);
        return result;
    }

    pub fn listFieldCount(self: *const DynamicMessage) usize {
        var count: usize = 0;
        for (self.fields.items) |*entry| {
            if (entry.values.items.len != 0) count += 1;
        }
        return count;
    }

    pub fn listFieldAt(self: *const DynamicMessage, index: usize) ?*const schema.FieldDescriptor {
        // `listFieldsAlloc` exposes present fields in descriptor-number order,
        // matching protobuf reflection rather than mutation/storage order.  Keep
        // the scalar at/index helpers on the same ordering without allocating by
        // selecting the Nth present descriptor by field number.
        var lower_bound: wire.FieldNumber = 0;
        var remaining = index;
        while (true) {
            var best: ?*const schema.FieldDescriptor = null;
            for (self.fields.items) |*entry| {
                if (entry.values.items.len == 0) continue;
                const number = entry.descriptor.number;
                if (number <= lower_bound) continue;
                if (best == null or number < best.?.number) best = entry.descriptor;
            }
            const current = best orelse return null;
            if (remaining == 0) return current;
            lower_bound = current.number;
            remaining -= 1;
        }
    }

    pub fn listFieldIndex(self: *const DynamicMessage, descriptor: *const schema.FieldDescriptor) ?usize {
        var index: usize = 0;
        var lower_bound: wire.FieldNumber = 0;
        while (true) {
            var best: ?*const schema.FieldDescriptor = null;
            for (self.fields.items) |*entry| {
                if (entry.values.items.len == 0) continue;
                const number = entry.descriptor.number;
                if (number <= lower_bound) continue;
                if (best == null or number < best.?.number) best = entry.descriptor;
            }
            const current = best orelse return null;
            if (current == descriptor) return index;
            lower_bound = current.number;
            index += 1;
        }
    }

    pub fn clearField(self: *DynamicMessage, field: *const schema.FieldDescriptor) bool {
        var index: usize = 0;
        while (index < self.fields.items.len) : (index += 1) {
            if (self.fields.items[index].descriptor.number == field.number) {
                self.fields.items[index].deinit(self.allocator);
                _ = self.fields.swapRemove(index);
                return true;
            }
        }
        return false;
    }

    pub fn clearFieldByName(self: *DynamicMessage, name: []const u8) bool {
        const field = self.descriptor.findField(name) orelse return false;
        return self.clearField(field);
    }

    pub fn removeRepeatedValue(self: *DynamicMessage, field: *const schema.FieldDescriptor, index: usize) bool {
        if (!field.isRepeatedLike()) return false;
        const field_value = self.getMutableByNumber(field.number) orelse return false;
        if (index >= field_value.values.items.len) return false;
        deinitValue(&field_value.values.items[index], self.allocator);
        const tail = field_value.values.items[index + 1 ..];
        std.mem.copyForwards(Value, field_value.values.items[index .. index + tail.len], tail);
        field_value.values.items.len -= 1;
        if (field_value.values.items.len == 0) _ = self.clearField(field);
        return true;
    }

    pub fn removeRepeatedValueByName(self: *DynamicMessage, name: []const u8, index: usize) bool {
        const field = self.descriptor.findField(name) orelse return false;
        return self.removeRepeatedValue(field, index);
    }

    pub fn setRepeatedValue(self: *DynamicMessage, field: *const schema.FieldDescriptor, index: usize, value: Value) bool {
        if (!field.isRepeatedLike()) return false;
        const field_value = self.getMutableByNumber(field.number) orelse return false;
        if (index >= field_value.values.items.len) return false;
        deinitValue(&field_value.values.items[index], self.allocator);
        field_value.values.items[index] = value;
        return true;
    }

    pub fn setRepeatedValueByName(self: *DynamicMessage, name: []const u8, index: usize, value: Value) bool {
        const field = self.descriptor.findField(name) orelse return false;
        return self.setRepeatedValue(field, index, value);
    }

    pub fn swapRepeatedValues(self: *DynamicMessage, field: *const schema.FieldDescriptor, lhs: usize, rhs: usize) bool {
        if (!field.isRepeatedLike()) return false;
        const field_value = self.getMutableByNumber(field.number) orelse return false;
        if (lhs >= field_value.values.items.len or rhs >= field_value.values.items.len) return false;
        std.mem.swap(Value, &field_value.values.items[lhs], &field_value.values.items[rhs]);
        return true;
    }

    pub fn swapRepeatedValuesByName(self: *DynamicMessage, name: []const u8, lhs: usize, rhs: usize) bool {
        const field = self.descriptor.findField(name) orelse return false;
        return self.swapRepeatedValues(field, lhs, rhs);
    }

    pub fn hasOneof(self: *const DynamicMessage, oneof_name: []const u8) bool {
        return self.whichOneof(oneof_name) != null;
    }

    pub fn clearOneof(self: *DynamicMessage, oneof_name: []const u8) bool {
        if (self.descriptor.findOneof(oneof_name) == null) return false;
        var removed = false;
        var index: usize = 0;
        while (index < self.fields.items.len) {
            const entry = &self.fields.items[index];
            const same_oneof = if (entry.descriptor.oneof_name) |name| std.mem.eql(u8, name, oneof_name) else false;
            if (same_oneof) {
                entry.deinit(self.allocator);
                _ = self.fields.swapRemove(index);
                removed = true;
                continue;
            }
            index += 1;
        }
        return removed;
    }

    pub fn clearMapEntry(self: *DynamicMessage, field: *const schema.FieldDescriptor, key: Value) bool {
        if (field.kind != .map) return false;
        const field_value = self.getMutableByNumber(field.number) orelse return false;
        var index: usize = 0;
        while (index < field_value.values.items.len) : (index += 1) {
            const value = &field_value.values.items[index];
            if (value.* != .map_entry or !valueEqual(value.map_entry.key, key)) continue;

            deinitValue(value, self.allocator);
            const tail = field_value.values.items[index + 1 ..];
            std.mem.copyForwards(Value, field_value.values.items[index .. index + tail.len], tail);
            field_value.values.items.len -= 1;
            if (field_value.values.items.len == 0) _ = self.clearField(field);
            return true;
        }
        return false;
    }

    pub fn clearMapEntryByName(self: *DynamicMessage, name: []const u8, key: Value) bool {
        const field = self.descriptor.findField(name) orelse return false;
        return self.clearMapEntry(field, key);
    }

    pub fn getMapEntry(self: *const DynamicMessage, field: *const schema.FieldDescriptor, key: Value) ?*const MapEntry {
        if (field.kind != .map) return null;
        const field_value = self.getByNumber(field.number) orelse return null;
        for (field_value.values.items) |*value| {
            if (value.* == .map_entry and valueEqual(value.map_entry.key, key)) return value.map_entry;
        }
        return null;
    }

    pub fn getMapEntryByName(self: *const DynamicMessage, name: []const u8, key: Value) ?*const MapEntry {
        const field = self.descriptor.findField(name) orelse return null;
        return self.getMapEntry(field, key);
    }

    pub fn getMapValue(self: *const DynamicMessage, field: *const schema.FieldDescriptor, key: Value) ?Value {
        const entry = self.getMapEntry(field, key) orelse return null;
        return entry.value;
    }

    pub fn getMapValueByName(self: *const DynamicMessage, name: []const u8, key: Value) ?Value {
        const field = self.descriptor.findField(name) orelse return null;
        return self.getMapValue(field, key);
    }

    fn getMutableByNumber(self: *DynamicMessage, number: wire.FieldNumber) ?*FieldValue {
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

    pub fn getOrDefaultWithFile(self: *const DynamicMessage, file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor) DefaultValue {
        return self.getOrDefaultWithRegistry(file, null, field);
    }

    pub fn getOrDefaultWithRegistry(self: *const DynamicMessage, file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, field: *const schema.FieldDescriptor) DefaultValue {
        if (self.getByNumber(field.number)) |field_value| {
            if (field_value.values.items.len != 0) return valueAsDefault(field_value.values.items[field_value.values.items.len - 1]);
        }
        return defaultForFieldWithRegistry(file, registry, self.descriptor, field);
    }

    pub fn getEnumNameOrDefaultWithFile(self: *const DynamicMessage, file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor) ?[]const u8 {
        return self.getEnumNameOrDefaultWithRegistry(file, null, field);
    }

    pub fn getEnumNameOrDefaultWithRegistry(self: *const DynamicMessage, file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, field: *const schema.FieldDescriptor) ?[]const u8 {
        const enumeration = registryEnumDescriptor(file, registry, self.descriptor, field.kind) orelse return null;
        const number = switch (self.getOrDefaultWithRegistry(file, registry, field)) {
            .enumeration => |value| value,
            else => return null,
        };
        return enumNameForNumber(enumeration, number);
    }

    pub fn getEnumNamesWithFile(self: *const DynamicMessage, allocator: std.mem.Allocator, file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor) ![]const []const u8 {
        return try self.getEnumNamesWithRegistry(allocator, file, null, field);
    }

    pub fn getEnumNamesWithRegistry(self: *const DynamicMessage, allocator: std.mem.Allocator, file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, field: *const schema.FieldDescriptor) ![]const []const u8 {
        const enumeration = registryEnumDescriptor(file, registry, self.descriptor, field.kind) orelse return error.TypeMismatch;
        const values = if (self.getByNumber(field.number)) |field_value| field_value.values.items else &.{};
        const names = try allocator.alloc([]const u8, values.len);
        errdefer allocator.free(names);
        for (values, 0..) |value, index| {
            const number = switch (value) {
                .enumeration => |v| v,
                else => return error.TypeMismatch,
            };
            names[index] = enumNameForNumber(enumeration, number) orelse return error.InvalidEnumValue;
        }
        return names;
    }

    pub fn getEnumMapValueNameWithFile(self: *const DynamicMessage, file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, key: Value) !?[]const u8 {
        return try self.getEnumMapValueNameWithRegistry(file, null, field, key);
    }

    pub fn getEnumMapValueNameWithRegistry(self: *const DynamicMessage, file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, field: *const schema.FieldDescriptor, key: Value) !?[]const u8 {
        const map_type = switch (field.kind) {
            .map => |map| map,
            else => return error.TypeMismatch,
        };
        const enumeration = registryEnumDescriptor(file, registry, self.descriptor, map_type.value.*) orelse return error.TypeMismatch;
        const values = if (self.getByNumber(field.number)) |field_value| field_value.values.items else return null;
        for (values) |value| {
            const entry = switch (value) {
                .map_entry => |map_entry| map_entry,
                else => return error.TypeMismatch,
            };
            if (!valueEqual(entry.key, key)) continue;
            const number = switch (entry.value) {
                .enumeration => |v| v,
                else => return error.TypeMismatch,
            };
            return enumNameForNumber(enumeration, number) orelse error.InvalidEnumValue;
        }
        return null;
    }

    pub fn unknownCount(self: *const DynamicMessage) usize {
        return self.unknown_fields.items.len;
    }

    pub fn unknownFields(self: *const DynamicMessage) []const UnknownField {
        return self.unknown_fields.items;
    }

    pub fn unknownFieldCountByNumber(self: *const DynamicMessage, number: wire.FieldNumber) usize {
        var count: usize = 0;
        for (self.unknown_fields.items) |field| {
            if (field.number == number) count += 1;
        }
        return count;
    }

    pub fn hasUnknownFieldNumber(self: *const DynamicMessage, number: wire.FieldNumber) bool {
        for (self.unknown_fields.items) |field| {
            if (field.number == number) return true;
        }
        return false;
    }

    pub fn unknownFieldNumbersAlloc(self: *const DynamicMessage, allocator: std.mem.Allocator) std.mem.Allocator.Error![]wire.FieldNumber {
        if (self.unknown_fields.items.len == 0) return &.{};
        const numbers = try allocator.alloc(wire.FieldNumber, self.unknown_fields.items.len);
        for (self.unknown_fields.items, numbers) |field, *number| number.* = field.number;
        return numbers;
    }

    pub fn unknownFieldNumberRunsAlloc(self: *const DynamicMessage, allocator: std.mem.Allocator) std.mem.Allocator.Error![]wire.RawFieldNumberRun {
        if (self.unknown_fields.items.len == 0) return &.{};
        const numbers = try self.unknownFieldNumbersAlloc(allocator);
        defer allocator.free(numbers);
        return try wire.rawFieldNumberRunsFromNumbersInPlaceAlloc(allocator, numbers);
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

    pub fn appendUnknownRaw(self: *DynamicMessage, raw: []const u8) DecodeError!void {
        var reader = wire.Reader.init(raw);
        const tag = (try reader.nextTag()) orelse return error.InvalidWireType;
        try reader.skipValue(tag);
        if (!reader.eof()) return error.InvalidWireType;
        try self.addUnknownRaw(tag.number, tag.wire_type, raw);
    }

    pub fn clearUnknownFieldsByNumber(self: *DynamicMessage, number: wire.FieldNumber) void {
        var write_index: usize = 0;
        var read_index: usize = 0;
        while (read_index < self.unknown_fields.items.len) : (read_index += 1) {
            if (self.unknown_fields.items[read_index].number == number) {
                self.unknown_fields.items[read_index].deinit(self.allocator);
                continue;
            }
            if (write_index != read_index) self.unknown_fields.items[write_index] = self.unknown_fields.items[read_index];
            write_index += 1;
        }
        self.unknown_fields.items.len = write_index;
    }

    pub fn clearUnknownFields(self: *DynamicMessage) void {
        for (self.unknown_fields.items) |*field| field.deinit(self.allocator);
        self.unknown_fields.clearRetainingCapacity();
    }

    pub fn add(self: *DynamicMessage, field: *const schema.FieldDescriptor, value: Value) std.mem.Allocator.Error!void {
        var owned = value;
        if (try self.mergeSingularMessageValue(field, owned)) {
            deinitValue(&owned, self.allocator);
            return;
        }
        if (field.oneof_name) |oneof_name| self.clearOneofExcept(oneof_name, field.number);
        var entry = try self.getOrCreateMutable(field);
        if (field.kind == .map and owned == .map_entry) {
            for (entry.values.items) |*existing| {
                if (existing.* == .map_entry and valueEqual(existing.map_entry.key, owned.map_entry.key)) {
                    deinitValue(existing, self.allocator);
                    existing.* = owned;
                    return;
                }
            }
        }
        if (!field.isRepeatedLike() and entry.values.items.len != 0) {
            deinitValue(&entry.values.items[0], self.allocator);
            entry.values.items.len = 0;
        }
        try entry.values.append(self.allocator, owned);
    }

    pub fn addClone(self: *DynamicMessage, field: *const schema.FieldDescriptor, value: Value) std.mem.Allocator.Error!void {
        var cloned = try cloneValue(self.allocator, value);
        errdefer deinitValue(&cloned, self.allocator);
        try self.add(field, cloned);
    }

    fn addPackedVarintScalar(self: *DynamicMessage, field: *const schema.FieldDescriptor, scalar: schema.ScalarType, payload: []const u8) (std.mem.Allocator.Error || wire.Error || error{TypeMismatch})!void {
        switch (scalar) {
            .int32, .int64, .uint32, .uint64, .sint32, .sint64, .bool => {},
            else => return error.TypeMismatch,
        }

        // Packed fields are always repeated, so decoding can append directly to
        // the destination FieldValue. That avoids routing every scalar through
        // add(), whose singular/map/oneof bookkeeping is useful for public
        // mutation but pure overhead for a validated packed payload.
        if (field.oneof_name) |oneof_name| self.clearOneofExcept(oneof_name, field.number);
        var entry = try self.getOrCreateMutable(field);
        try entry.values.ensureUnusedCapacity(self.allocator, payload.len);
        var index: usize = 0;
        switch (scalar) {
            .int32 => while (index < payload.len) {
                const raw = try wire.readVarintAt(payload, &index);
                entry.values.appendAssumeCapacity(.{ .int32 = @truncate(@as(i64, @bitCast(raw))) });
            },
            .int64 => while (index < payload.len) {
                const raw = try wire.readVarintAt(payload, &index);
                entry.values.appendAssumeCapacity(.{ .int64 = @bitCast(raw) });
            },
            .uint32 => while (index < payload.len) {
                const raw = try wire.readVarintAt(payload, &index);
                entry.values.appendAssumeCapacity(.{ .uint32 = @as(u32, @truncate(raw)) });
            },
            .uint64 => while (index < payload.len) {
                entry.values.appendAssumeCapacity(.{ .uint64 = try wire.readVarintAt(payload, &index) });
            },
            .sint32 => while (index < payload.len) {
                const raw = try wire.readVarintAt(payload, &index);
                entry.values.appendAssumeCapacity(.{ .sint32 = wire.zigZagDecode32(@as(u32, @truncate(raw))) });
            },
            .sint64 => while (index < payload.len) {
                entry.values.appendAssumeCapacity(.{ .sint64 = wire.zigZagDecode64(try wire.readVarintAt(payload, &index)) });
            },
            .bool => while (index < payload.len) {
                entry.values.appendAssumeCapacity(.{ .boolean = (try wire.readVarintAt(payload, &index)) != 0 });
            },
            else => unreachable,
        }
    }

    fn addPackedEnum(self: *DynamicMessage, field: *const schema.FieldDescriptor, enumeration: *const schema.EnumDescriptor, closed: bool, payload: []const u8) DecodeError!void {
        // Open enum payloads can be appended just like packed int32 values.
        // Closed enums still need per-value validation, but the common known
        // value path should not pay the public add() bookkeeping cost.
        if (field.oneof_name) |oneof_name| self.clearOneofExcept(oneof_name, field.number);
        var entry = try self.getOrCreateMutable(field);
        try entry.values.ensureUnusedCapacity(self.allocator, payload.len);
        var index: usize = 0;
        while (index < payload.len) {
            const value_start = index;
            const raw = try wire.readVarintAt(payload, &index);
            const value: i32 = @truncate(@as(i64, @bitCast(raw)));
            if (closed and !enumHasNumber(enumeration, value)) {
                try self.addUnknownVarintPayload(field.number, payload[value_start..index]);
                continue;
            }
            entry.values.appendAssumeCapacity(.{ .enumeration = value });
        }
    }

    fn addPackedFixedWidth(self: *DynamicMessage, field: *const schema.FieldDescriptor, scalar: schema.ScalarType, payload: []const u8) (std.mem.Allocator.Error || wire.Error || error{TypeMismatch})!void {
        const width = fixedWidthPackedScalarSize(scalar) orelse return error.TypeMismatch;
        if (payload.len % width != 0) return error.InvalidWireType;
        if (field.oneof_name) |oneof_name| self.clearOneofExcept(oneof_name, field.number);
        var entry = try self.getOrCreateMutable(field);
        const count = payload.len / width;
        try entry.values.ensureUnusedCapacity(self.allocator, count);
        const out = entry.values.addManyAsSliceAssumeCapacity(count);
        for (out, 0..) |*value, index| {
            const raw = payload[index * width ..][0..width];
            value.* = switch (scalar) {
                .fixed32 => .{ .fixed32 = std.mem.readInt(u32, raw[0..4], .little) },
                .fixed64 => .{ .fixed64 = std.mem.readInt(u64, raw[0..8], .little) },
                .sfixed32 => .{ .sfixed32 = std.mem.readInt(i32, raw[0..4], .little) },
                .sfixed64 => .{ .sfixed64 = std.mem.readInt(i64, raw[0..8], .little) },
                .float => .{ .float = @bitCast(std.mem.readInt(u32, raw[0..4], .little)) },
                .double => .{ .double = @bitCast(std.mem.readInt(u64, raw[0..8], .little)) },
                else => unreachable,
            };
        }
    }

    fn addDecodedMapEntry(self: *DynamicMessage, field: *const schema.FieldDescriptor, value: Value) std.mem.Allocator.Error!void {
        std.debug.assert(field.kind == .map);
        std.debug.assert(value == .map_entry);
        var owned = value;
        var owns_owned = true;
        errdefer if (owns_owned) deinitValue(&owned, self.allocator);

        if (field.oneof_name) |oneof_name| self.clearOneofExcept(oneof_name, field.number);
        var entry = try self.getOrCreateMutable(field);
        try entry.values.append(self.allocator, owned);
        owns_owned = false;
    }

    fn deduplicateDecodedMapFields(self: *DynamicMessage) std.mem.Allocator.Error!void {
        for (self.fields.items) |*entry| {
            if (entry.descriptor.kind == .map) try self.deduplicateDecodedMapField(entry);
        }
    }

    fn deduplicateDecodedMapField(self: *DynamicMessage, entry: *FieldValue) std.mem.Allocator.Error!void {
        if (entry.values.items.len < 2) return;
        if (entry.values.items.len < 16) {
            self.deduplicateDecodedMapFieldLinear(entry);
            return;
        }

        // Map fields have last-wins semantics, but checking for an existing
        // key on every decoded entry makes large maps quadratic. Decode now
        // appends entries in wire order and performs one hash-assisted
        // compaction pass here. The retained slot is the first occurrence of a
        // key (matching the public add() ordering), while its payload is
        // replaced by the last occurrence.
        var retained_by_key: std.HashMapUnmanaged(Value, usize, MapKeyContext, std.hash_map.default_max_load_percentage) = .empty;
        defer retained_by_key.deinit(self.allocator);
        const expected_count: u32 = std.math.cast(u32, entry.values.items.len) orelse return error.OutOfMemory;
        try retained_by_key.ensureTotalCapacityContext(self.allocator, expected_count, .{});

        var write_index: usize = 0;
        var read_index: usize = 0;
        while (read_index < entry.values.items.len) : (read_index += 1) {
            const value = entry.values.items[read_index];
            if (value != .map_entry) {
                if (write_index != read_index) {
                    entry.values.items[write_index] = value;
                    entry.values.items[read_index] = undefined;
                }
                write_index += 1;
                continue;
            }

            const result = retained_by_key.getOrPutAssumeCapacityContext(value.map_entry.key, .{});
            if (result.found_existing) {
                const retained_index = result.value_ptr.*;
                // For string keys the hash-table key is a borrowed slice into
                // the retained map entry. Repoint it before destroying the old
                // entry so later duplicate probes never read freed key bytes.
                result.key_ptr.* = value.map_entry.key;
                deinitValue(&entry.values.items[retained_index], self.allocator);
                entry.values.items[retained_index] = value;
                entry.values.items[read_index] = undefined;
                continue;
            }

            result.value_ptr.* = write_index;
            if (write_index != read_index) {
                entry.values.items[write_index] = value;
                entry.values.items[read_index] = undefined;
            }
            write_index += 1;
        }
        entry.values.items.len = write_index;
    }

    fn deduplicateDecodedMapFieldLinear(self: *DynamicMessage, entry: *FieldValue) void {
        var write_index: usize = 0;
        var read_index: usize = 0;
        while (read_index < entry.values.items.len) : (read_index += 1) {
            const value = entry.values.items[read_index];
            if (value != .map_entry) {
                if (write_index != read_index) {
                    entry.values.items[write_index] = value;
                    entry.values.items[read_index] = undefined;
                }
                write_index += 1;
                continue;
            }

            var duplicate_index: ?usize = null;
            var retained_index: usize = 0;
            while (retained_index < write_index) : (retained_index += 1) {
                const retained = entry.values.items[retained_index];
                if (retained == .map_entry and valueEqual(retained.map_entry.key, value.map_entry.key)) {
                    duplicate_index = retained_index;
                    break;
                }
            }
            if (duplicate_index) |index| {
                deinitValue(&entry.values.items[index], self.allocator);
                entry.values.items[index] = value;
                entry.values.items[read_index] = undefined;
                continue;
            }

            if (write_index != read_index) {
                entry.values.items[write_index] = value;
                entry.values.items[read_index] = undefined;
            }
            write_index += 1;
        }
        entry.values.items.len = write_index;
    }

    pub fn mergeFrom(self: *DynamicMessage, other: *const DynamicMessage) std.mem.Allocator.Error!void {
        for (other.fields.items) |*entry| {
            for (entry.values.items) |value| try self.mergeFieldFrom(entry.descriptor, value);
        }
        for (other.unknown_fields.items) |unknown| try self.addUnknownClone(unknown);
    }

    fn addOwned(self: *DynamicMessage, field: *const schema.FieldDescriptor, value: Value) std.mem.Allocator.Error!void {
        var owned = value;
        var owns_owned = true;
        errdefer if (owns_owned) deinitValue(&owned, self.allocator);
        if (try self.mergeSingularMessageValue(field, owned)) {
            deinitValue(&owned, self.allocator);
            owns_owned = false;
            return;
        }
        try self.add(field, owned);
        owns_owned = false;
    }

    fn mergeFieldFrom(self: *DynamicMessage, field: *const schema.FieldDescriptor, value: Value) std.mem.Allocator.Error!void {
        if (try self.mergeSingularMessageValue(field, value)) return;
        try self.addClone(field, value);
    }

    fn mergeSingularMessageValue(self: *DynamicMessage, field: *const schema.FieldDescriptor, value: Value) std.mem.Allocator.Error!bool {
        if (!shouldMergeSingularMessageField(field)) return false;
        const entry = self.findMutableByNumber(field.number) orelse return false;
        if (entry.values.items.len == 0) return false;
        switch (entry.values.items[0]) {
            .message => |target| switch (value) {
                .message => |source| {
                    try target.mergeFrom(source);
                    return true;
                },
                else => return false,
            },
            .group => |target| switch (value) {
                .group => |source| {
                    try target.mergeFrom(source);
                    return true;
                },
                else => return false,
            },
            else => return false,
        }
    }

    fn addUnknownClone(self: *DynamicMessage, unknown: UnknownField) std.mem.Allocator.Error!void {
        const data = try self.allocator.dupe(u8, unknown.data);
        errdefer self.allocator.free(data);
        try self.unknown_fields.append(self.allocator, .{
            .number = unknown.number,
            .wire_type = unknown.wire_type,
            .data = data,
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
            if (fieldIsRequired(field) and !self.has(field)) return error.MissingRequiredField;
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
            if (fieldIsRequired(field) and !self.has(field)) return try allocator.dupe(u8, field.name);
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

    fn findMutableByNumber(self: *DynamicMessage, number: wire.FieldNumber) ?*FieldValue {
        for (self.fields.items) |*entry| {
            if (entry.descriptor.number == number) return entry;
        }
        return null;
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
        return try self.encodeWithRegistry(file, null, writer);
    }

    pub fn encodeWithRegistry(self: *const DynamicMessage, file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, writer: *wire.Writer) EncodeError!void {
        if (self.descriptor.messageSetWireFormat()) return try self.encodeMessageSet(file, registry, writer, false);
        for (self.fields.items) |*entry| {
            if (entry.values.items.len == 0) continue;
            try validateFieldTargetsMessage(file, registry, self.descriptor, entry.descriptor);
            if (!entry.descriptor.isRepeatedLike() and !fieldHasPresenceForEncoding(file, registry, self.descriptor, entry.descriptor) and entry.values.items.len == 1 and isDefaultSingularValueForEncoding(file, registry, self.descriptor, entry.descriptor, entry.values.items[0])) continue;
            if (resolvedPackedForEncoding(file, registry, self.descriptor, entry.descriptor)) {
                try encodePackedWithRegistry(self.descriptor, entry.descriptor, entry.values.items, file, registry, writer);
            } else {
                for (entry.values.items) |value| try encodeField(self.descriptor, entry.descriptor, value, file, registry, writer, false);
            }
        }
        for (self.unknown_fields.items) |unknown| try writer.appendSlice(unknown.data);
    }

    pub fn encodeInitialized(self: *const DynamicMessage, file: *const schema.FileDescriptor, writer: *wire.Writer) (EncodeError || ValidationError)!void {
        return try self.encodeInitializedWithRegistry(file, null, writer);
    }

    pub fn encodeInitializedWithRegistry(self: *const DynamicMessage, file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, writer: *wire.Writer) (EncodeError || ValidationError)!void {
        try self.validateRequired();
        try self.encodeWithRegistry(file, registry, writer);
    }

    pub fn encodeDeterministic(self: *const DynamicMessage, file: *const schema.FileDescriptor, writer: *wire.Writer) EncodeError!void {
        return try self.encodeDeterministicWithRegistry(file, null, writer);
    }

    pub fn encodeDeterministicWithRegistry(self: *const DynamicMessage, file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, writer: *wire.Writer) EncodeError!void {
        if (self.descriptor.messageSetWireFormat()) return try self.encodeMessageSet(file, registry, writer, true);
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
            if (entry.values.items.len == 0) continue;
            try validateFieldTargetsMessage(file, registry, self.descriptor, entry.descriptor);
            if (!entry.descriptor.isRepeatedLike() and !fieldHasPresenceForEncoding(file, registry, self.descriptor, entry.descriptor) and entry.values.items.len == 1 and isDefaultSingularValueForEncoding(file, registry, self.descriptor, entry.descriptor, entry.values.items[0])) continue;
            if (resolvedPackedForEncoding(file, registry, self.descriptor, entry.descriptor)) {
                try encodePackedWithRegistry(self.descriptor, entry.descriptor, entry.values.items, file, registry, writer);
            } else if (entry.descriptor.kind == .map) {
                const value_indexes = try self.allocator.alloc(usize, entry.values.items.len);
                defer self.allocator.free(value_indexes);
                for (value_indexes, 0..) |*value_index, i| value_index.* = i;
                std.mem.sort(usize, value_indexes, entry, struct {
                    fn lessThan(field_value: *const FieldValue, a: usize, b: usize) bool {
                        return mapEntryLessThan(field_value.values.items[a], field_value.values.items[b]);
                    }
                }.lessThan);
                for (value_indexes) |value_index| try encodeField(self.descriptor, entry.descriptor, entry.values.items[value_index], file, registry, writer, true);
            } else {
                for (entry.values.items) |value| try encodeField(self.descriptor, entry.descriptor, value, file, registry, writer, true);
            }
        }
        const unknown_indexes = try self.allocator.alloc(usize, self.unknown_fields.items.len);
        defer self.allocator.free(unknown_indexes);
        for (unknown_indexes, 0..) |*index, i| index.* = i;
        std.mem.sort(usize, unknown_indexes, self, struct {
            fn lessThan(message: *const DynamicMessage, a: usize, b: usize) bool {
                return unknownFieldIndexLessThan(message, a, b);
            }
        }.lessThan);
        for (unknown_indexes) |index| try writer.appendSlice(self.unknown_fields.items[index].data);
    }

    pub fn encodeDeterministicInitialized(self: *const DynamicMessage, file: *const schema.FileDescriptor, writer: *wire.Writer) (EncodeError || ValidationError)!void {
        return try self.encodeDeterministicInitializedWithRegistry(file, null, writer);
    }

    pub fn encodeDeterministicInitializedWithRegistry(self: *const DynamicMessage, file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, writer: *wire.Writer) (EncodeError || ValidationError)!void {
        try self.validateRequired();
        try self.encodeDeterministicWithRegistry(file, registry, writer);
    }

    pub fn encoded(self: *const DynamicMessage, file: *const schema.FileDescriptor) EncodeError![]u8 {
        return try self.encodedWithRegistry(file, null);
    }

    pub fn encodedWithRegistry(self: *const DynamicMessage, file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry) EncodeError![]u8 {
        var writer = wire.Writer.init(self.allocator);
        errdefer writer.deinit();
        try self.encodeWithRegistry(file, registry, &writer);
        return try writer.toOwnedSlice();
    }

    pub fn encodedInitialized(self: *const DynamicMessage, file: *const schema.FileDescriptor) (EncodeError || ValidationError)![]u8 {
        return try self.encodedInitializedWithRegistry(file, null);
    }

    pub fn encodedInitializedWithRegistry(self: *const DynamicMessage, file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry) (EncodeError || ValidationError)![]u8 {
        var writer = wire.Writer.init(self.allocator);
        errdefer writer.deinit();
        try self.encodeInitializedWithRegistry(file, registry, &writer);
        return try writer.toOwnedSlice();
    }

    pub fn encodedDeterministic(self: *const DynamicMessage, file: *const schema.FileDescriptor) EncodeError![]u8 {
        return try self.encodedDeterministicWithRegistry(file, null);
    }

    pub fn encodedDeterministicWithRegistry(self: *const DynamicMessage, file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry) EncodeError![]u8 {
        var writer = wire.Writer.init(self.allocator);
        errdefer writer.deinit();
        try self.encodeDeterministicWithRegistry(file, registry, &writer);
        return try writer.toOwnedSlice();
    }

    pub fn encodedDeterministicInitialized(self: *const DynamicMessage, file: *const schema.FileDescriptor) (EncodeError || ValidationError)![]u8 {
        return try self.encodedDeterministicInitializedWithRegistry(file, null);
    }

    pub fn encodedDeterministicInitializedWithRegistry(self: *const DynamicMessage, file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry) (EncodeError || ValidationError)![]u8 {
        var writer = wire.Writer.init(self.allocator);
        errdefer writer.deinit();
        try self.encodeDeterministicInitializedWithRegistry(file, registry, &writer);
        return try writer.toOwnedSlice();
    }

    pub fn decode(self: *DynamicMessage, file: *const schema.FileDescriptor, bytes: []const u8) DecodeError!void {
        self.clear();
        var reader = wire.Reader.init(bytes);
        try self.decodeStream(file, null, &reader, null);
        try self.deduplicateDecodedMapFields();
    }

    pub fn decodeWithRegistry(self: *DynamicMessage, file: *const schema.FileDescriptor, registry: *const registry_mod.Registry, bytes: []const u8) DecodeError!void {
        self.clear();
        var reader = wire.Reader.init(bytes);
        try self.decodeStream(file, registry, &reader, null);
        try self.deduplicateDecodedMapFields();
    }

    pub fn decodeInitialized(self: *DynamicMessage, file: *const schema.FileDescriptor, bytes: []const u8) (DecodeError || ValidationError)!void {
        try self.decode(file, bytes);
        try self.validateRequired();
    }

    pub fn decodeInitializedWithRegistry(self: *DynamicMessage, file: *const schema.FileDescriptor, registry: *const registry_mod.Registry, bytes: []const u8) (DecodeError || ValidationError)!void {
        try self.decodeWithRegistry(file, registry, bytes);
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

            const start = reader.lastTagStart();
            const field = self.descriptor.findFieldByNumber(tag.number) orelse registryExtension(registry, self.descriptor, tag.number) orelse {
                try reader.skipValue(tag);
                try self.addUnknownRaw(tag.number, tag.wire_type, reader.input[start..reader.position()]);
                continue;
            };

            // Extensions carry their own defining file in DescriptorPool. Use
            // that file for edition feature defaults instead of the extendee's
            // file so cross-file dynamic decoding matches FieldDescriptor::file().
            const field_file = registry_mod.fieldDefiningFile(file, registry, field);
            if (field.kind == .message and registryEnumDescriptor(field_file, registry, self.descriptor, field.kind) == null and field.messageEncoding(field_file) == .delimited) {
                if (tag.wire_type != .start_group) return error.InvalidWireType;
                try self.addOwned(field, try decodeDelimitedMessageValue(self.allocator, field_file, registry, self.descriptor, field, reader));
                continue;
            }

            if (field.kind == .group) {
                if (tag.wire_type != .start_group) return error.InvalidWireType;
                try self.addOwned(field, try decodeGroupValue(self.allocator, file, registry, self.descriptor, field, reader));
                continue;
            }

            if (field.kind == .map) {
                if (tag.wire_type != .length_delimited) return error.InvalidWireType;
                const payload = try reader.readBytes();
                var entry_reader = try reader.nested(payload);
                const value = (try decodeMapEntryValue(self.allocator, file, registry, self.descriptor, field, field.kind.map, &entry_reader)) orelse {
                    try self.addUnknownRaw(tag.number, tag.wire_type, reader.input[start..reader.position()]);
                    continue;
                };
                try self.addDecodedMapEntry(field, value);
                continue;
            }

            if (registryEnumDescriptor(field_file, registry, self.descriptor, field.kind)) |enumeration| {
                if (tag.wire_type == .length_delimited and field.cardinality == .repeated) {
                    const payload = try reader.readBytes();
                    try self.addPackedEnum(field, enumeration, enumIsClosed(field_file, registry, enumeration), payload);
                    continue;
                }
                if (tag.wire_type != .varint) return error.InvalidWireType;
                const value = try reader.readInt32();
                if (enumIsClosed(field_file, registry, enumeration) and !enumHasNumber(enumeration, value)) {
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
            if (tag.wire_type == .length_delimited and field.kind == .scalar and field.isPackable()) {
                if (fixedWidthPackedScalarSize(field.kind.scalar) != null) {
                    const payload = try reader.readBytes();
                    try self.addPackedFixedWidth(field, field.kind.scalar, payload);
                    continue;
                }
                const payload = try reader.readBytes();
                try self.addPackedVarintScalar(field, field.kind.scalar, payload);
                continue;
            }
            if (tag.wire_type == .length_delimited and field.isPackable()) {
                const payload = try reader.readBytes();
                var packed_reader = wire.Reader.init(payload);
                while (!packed_reader.eof()) {
                    if (closedEnumDescriptor(field_file, registry, self.descriptor, field.kind)) |enumeration| {
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
            if (closedEnumDescriptor(field_file, registry, self.descriptor, field.kind)) |enumeration| {
                const value = try reader.readInt32();
                if (enumHasNumber(enumeration, value)) {
                    try self.add(field, .{ .enumeration = value });
                } else {
                    try self.addUnknownRaw(tag.number, tag.wire_type, reader.input[start..reader.position()]);
                }
                continue;
            }
            try self.addOwned(field, try decodeValue(self.allocator, field_file, registry, self.descriptor, field, field.kind, reader));
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

    fn encodeMessageSet(self: *const DynamicMessage, file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, writer: *wire.Writer, deterministic: bool) EncodeError!void {
        if (deterministic) {
            const indexes = try self.allocator.alloc(usize, self.fields.items.len);
            defer self.allocator.free(indexes);
            for (indexes, 0..) |*index, i| index.* = i;
            std.mem.sort(usize, indexes, self, struct {
                fn lessThan(message: *const DynamicMessage, a: usize, b: usize) bool {
                    return message.fields.items[a].descriptor.number < message.fields.items[b].descriptor.number;
                }
            }.lessThan);
            for (indexes) |index| try encodeMessageSetEntry(self.descriptor, &self.fields.items[index], file, registry, writer, true);

            const unknown_indexes = try self.allocator.alloc(usize, self.unknown_fields.items.len);
            defer self.allocator.free(unknown_indexes);
            for (unknown_indexes, 0..) |*index, i| index.* = i;
            std.mem.sort(usize, unknown_indexes, self, struct {
                fn lessThan(message: *const DynamicMessage, a: usize, b: usize) bool {
                    return unknownFieldIndexLessThan(message, a, b);
                }
            }.lessThan);
            for (unknown_indexes) |index| try encodeUnknownMessageSetField(&self.unknown_fields.items[index], writer);
            return;
        }

        for (self.fields.items) |*entry| try encodeMessageSetEntry(self.descriptor, entry, file, registry, writer, false);
        for (self.unknown_fields.items) |*unknown| try encodeUnknownMessageSetField(unknown, writer);
    }

    fn decodeMessageSetItem(self: *DynamicMessage, file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, reader: *wire.Reader) DecodeError!void {
        try reader.enterRecursion();
        defer reader.leaveRecursion();

        var type_id: ?wire.FieldNumber = null;
        var payload: ?[]const u8 = null;

        while (try reader.nextTag()) |tag| {
            if (tag.wire_type == .end_group) {
                if (tag.number != 1) return error.InvalidFieldNumber;
                if (type_id) |number| {
                    if (payload) |bytes| try self.addMessageSetPayload(file, registry, reader, number, bytes);
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

    fn addMessageSetPayload(self: *DynamicMessage, file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, source_reader: *wire.Reader, number: wire.FieldNumber, payload: []const u8) DecodeError!void {
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
        var payload_reader = try source_reader.nested(payload);
        try self.addOwned(field, try decodeMessagePayload(self.allocator, file, registry, self.descriptor, field.kind.message, &payload_reader));
    }
};

const MapKeyContext = struct {
    pub fn hash(_: MapKeyContext, key: Value) u64 {
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(std.mem.asBytes(&std.meta.activeTag(key)));
        switch (key) {
            .boolean => |value| hasher.update(std.mem.asBytes(&value)),
            .int32 => |value| hasher.update(std.mem.asBytes(&value)),
            .int64 => |value| hasher.update(std.mem.asBytes(&value)),
            .uint32 => |value| hasher.update(std.mem.asBytes(&value)),
            .uint64 => |value| hasher.update(std.mem.asBytes(&value)),
            .sint32 => |value| hasher.update(std.mem.asBytes(&value)),
            .sint64 => |value| hasher.update(std.mem.asBytes(&value)),
            .fixed32 => |value| hasher.update(std.mem.asBytes(&value)),
            .fixed64 => |value| hasher.update(std.mem.asBytes(&value)),
            .sfixed32 => |value| hasher.update(std.mem.asBytes(&value)),
            .sfixed64 => |value| hasher.update(std.mem.asBytes(&value)),
            .string => |bytes| hasher.update(bytes),
            else => {},
        }
        return hasher.final();
    }

    pub fn eql(_: MapKeyContext, a: Value, b: Value) bool {
        return valueEqual(a, b);
    }
};

fn registryExtension(registry: ?*const registry_mod.Registry, descriptor: *const schema.MessageDescriptor, number: wire.FieldNumber) ?*const schema.FieldDescriptor {
    const reg = registry orelse return null;
    return reg.findExtensionForMessage(descriptor, number);
}

fn validateFieldTargetsMessage(file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, current: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) EncodeError!void {
    if (field.extendee == null) return;
    if (!extensionFieldTargetsMessage(file, registry, current, field)) return error.TypeMismatch;
}

fn extensionFieldTargetsMessage(file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, current: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) bool {
    const extendee = field.extendee orelse return true;
    if (registry) |reg| {
        const owner = reg.fileContainingExtension(field) orelse file;
        if (reg.findMessageVisible(owner, extendee, extensionScope(owner, field))) |message| return message == current;
        return false;
    }
    if (file.findMessageDeep(extendee)) |message| {
        if (message == current) return true;
    }
    return extensionExtendsMessage(extendee, current);
}

fn encodeMessageSetEntry(host: *const schema.MessageDescriptor, entry: *const FieldValue, file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, writer: *wire.Writer, deterministic: bool) EncodeError!void {
    if (entry.descriptor.kind != .message or entry.descriptor.extendee == null or entry.descriptor.cardinality == .repeated or entry.descriptor.cardinality == .required) return error.TypeMismatch;
    if (!extensionFieldTargetsMessage(file, registry, host, entry.descriptor)) return error.TypeMismatch;
    for (entry.values.items) |value| {
        const message = switch (value) {
            .message => |message_value| message_value,
            else => return error.TypeMismatch,
        };
        const message_file = registry_mod.messageDefiningFile(file, registry, message.descriptor);
        var payload_writer = wire.Writer.init(writer.allocator);
        defer payload_writer.deinit();
        if (deterministic) {
            try message.encodeDeterministicWithRegistry(message_file, registry, &payload_writer);
        } else {
            try message.encodeWithRegistry(message_file, registry, &payload_writer);
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

fn extensionScope(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor) ?[]const u8 {
    if (field.full_name) |full_name| {
        const normalized = if (std.mem.startsWith(u8, full_name, ".")) full_name[1..] else full_name;
        if (std.mem.lastIndexOfScalar(u8, normalized, '.')) |idx| return normalized[0..idx];
        if (std.mem.startsWith(u8, full_name, ".")) return null;
    }
    return if (file.package.len != 0) file.package else null;
}

fn encodeField(current: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor, value: Value, file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, writer: *wire.Writer, deterministic: bool) EncodeError!void {
    // Extensions carry their own defining file in DescriptorPool. Use that
    // owner file for edition feature defaults instead of the extendee context
    // so cross-file dynamic encoding matches C++ FieldDescriptor::file().
    const field_file = registry_mod.fieldDefiningFile(file, registry, field);
    switch (field.kind) {
        .scalar => |scalar| try encodeScalar(field_file, field, field.number, scalar, value, writer),
        .enumeration => switch (value) {
            .enumeration => |v| {
                try writer.writeTag(field.number, .varint);
                try writer.writeVarint(@as(u64, @bitCast(@as(i64, v))));
            },
            else => return error.TypeMismatch,
        },
        .message => switch (value) {
            .enumeration => |v| {
                if (registryEnumDescriptor(field_file, registry, current, field.kind) == null) return error.TypeMismatch;
                try writer.writeTag(field.number, .varint);
                try writer.writeVarint(@as(u64, @bitCast(@as(i64, v))));
            },
            .message => |message| {
                if (registryEnumDescriptor(field_file, registry, current, field.kind) != null) return error.TypeMismatch;
                const message_file = registry_mod.messageDefiningFile(field_file, registry, message.descriptor);
                if (field.messageEncoding(field_file) == .delimited) {
                    try writer.writeTag(field.number, .start_group);
                    if (deterministic) {
                        try message.encodeDeterministicWithRegistry(message_file, registry, writer);
                    } else {
                        try message.encodeWithRegistry(message_file, registry, writer);
                    }
                    try writer.writeTag(field.number, .end_group);
                } else {
                    var nested_writer = wire.Writer.init(writer.allocator);
                    defer nested_writer.deinit();
                    if (deterministic) {
                        try message.encodeDeterministicWithRegistry(message_file, registry, &nested_writer);
                    } else {
                        try message.encodeWithRegistry(message_file, registry, &nested_writer);
                    }
                    try writer.writeMessage(field.number, nested_writer.slice());
                }
            },
            else => return error.TypeMismatch,
        },
        .group => switch (value) {
            .group => |message| {
                try writer.writeTag(field.number, .start_group);
                const message_file = registry_mod.messageDefiningFile(field_file, registry, message.descriptor);
                if (deterministic) {
                    try message.encodeDeterministicWithRegistry(message_file, registry, writer);
                } else {
                    try message.encodeWithRegistry(message_file, registry, writer);
                }
                try writer.writeTag(field.number, .end_group);
            },
            else => return error.TypeMismatch,
        },
        .map => |map_type| try encodeMapEntry(current, field, map_type, value, file, registry, writer, deterministic),
    }
}

fn encodeMapEntry(
    current: *const schema.MessageDescriptor,
    field: *const schema.FieldDescriptor,
    map_type: schema.MapType,
    value: Value,
    file: *const schema.FileDescriptor,
    registry: ?*const registry_mod.Registry,
    writer: *wire.Writer,
    deterministic: bool,
) EncodeError!void {
    const entry = switch (value) {
        .map_entry => |map_entry| map_entry,
        else => return error.TypeMismatch,
    };

    var entry_writer = wire.Writer.init(writer.allocator);
    defer entry_writer.deinit();
    try encodeMapElement(current, field, 1, .{ .scalar = map_type.key }, entry.key, file, registry, &entry_writer, deterministic);
    try encodeMapElement(current, field, 2, map_type.value.*, entry.value, file, registry, &entry_writer, deterministic);
    try writer.writeMessage(field.number, entry_writer.slice());
}

fn encodeMapElement(
    current: *const schema.MessageDescriptor,
    field: *const schema.FieldDescriptor,
    number: wire.FieldNumber,
    kind: schema.FieldKind,
    value: Value,
    file: *const schema.FileDescriptor,
    registry: ?*const registry_mod.Registry,
    writer: *wire.Writer,
    deterministic: bool,
) EncodeError!void {
    switch (kind) {
        .scalar => |scalar| try encodeScalar(file, field, number, scalar, value, writer),
        .enumeration => switch (value) {
            .enumeration => |v| {
                try writer.writeTag(number, .varint);
                try writer.writeVarint(@as(u64, @bitCast(@as(i64, v))));
            },
            else => return error.TypeMismatch,
        },
        .message => switch (value) {
            .enumeration => |v| {
                if (registryEnumDescriptor(file, registry, current, kind) == null) return error.TypeMismatch;
                try writer.writeTag(number, .varint);
                try writer.writeVarint(@as(u64, @bitCast(@as(i64, v))));
            },
            .message => |message| {
                if (registryEnumDescriptor(file, registry, current, kind) != null) return error.TypeMismatch;
                var nested_writer = wire.Writer.init(writer.allocator);
                defer nested_writer.deinit();
                const message_file = registry_mod.messageDefiningFile(file, registry, message.descriptor);
                if (deterministic) {
                    try message.encodeDeterministicWithRegistry(message_file, registry, &nested_writer);
                } else {
                    try message.encodeWithRegistry(message_file, registry, &nested_writer);
                }
                try writer.writeMessage(number, nested_writer.slice());
            },
            else => return error.TypeMismatch,
        },
        .group, .map => return error.TypeMismatch,
    }
}

fn encodePackedWithRegistry(current: ?*const schema.MessageDescriptor, field: *const schema.FieldDescriptor, values: []const Value, file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, writer: *wire.Writer) EncodeError!void {
    const field_file = registry_mod.fieldDefiningFile(file, registry, field);
    const kind = scalarLikeKindForEncoding(file, registry, current, field.kind);
    if (kind == .scalar and kind.scalar == .int32) return try encodePackedInt32(field, values, writer);
    if (kind == .scalar and fixedWidthPackedScalarSize(kind.scalar) != null) return try encodePackedFixedWidth(field, values, kind.scalar, writer);

    var packed_writer = wire.Writer.init(writer.allocator);
    defer packed_writer.deinit();
    for (values) |value| try encodeScalarPayloadWithValidation(field_file, field, kind, value, &packed_writer);
    try writer.writeBytes(field.number, packed_writer.slice());
}

fn encodePackedInt32(field: *const schema.FieldDescriptor, values: []const Value, writer: *wire.Writer) EncodeError!void {
    var packed_len: usize = 0;
    for (values) |value| {
        if (value != .int32) return error.TypeMismatch;
        packed_len += wire.encodedVarintSize(@as(u64, @bitCast(@as(i64, value.int32))));
    }
    try writer.bytes.ensureUnusedCapacity(writer.allocator, (try wire.tagSize(field.number, .length_delimited)) + wire.encodedVarintSize(packed_len) + packed_len);
    writer.writeTagAssumeCapacity(field.number, .length_delimited);
    writer.writeVarintAssumeCapacity(packed_len);
    for (values) |value| writer.writeVarintAssumeCapacity(@as(u64, @bitCast(@as(i64, value.int32))));
}

fn fixedWidthPackedScalarSize(scalar: schema.ScalarType) ?usize {
    return switch (scalar) {
        .fixed32, .sfixed32, .float => 4,
        .fixed64, .sfixed64, .double => 8,
        else => null,
    };
}

fn encodePackedFixedWidth(field: *const schema.FieldDescriptor, values: []const Value, scalar: schema.ScalarType, writer: *wire.Writer) EncodeError!void {
    const width = fixedWidthPackedScalarSize(scalar) orelse return error.TypeMismatch;
    const packed_len = values.len * width;
    try writer.bytes.ensureUnusedCapacity(writer.allocator, (try wire.tagSize(field.number, .length_delimited)) + wire.encodedVarintSize(packed_len) + packed_len);
    writer.writeTagAssumeCapacity(field.number, .length_delimited);
    writer.writeVarintAssumeCapacity(packed_len);
    for (values) |value| {
        switch (scalar) {
            .fixed32 => if (value == .fixed32) writer.writeRawLittleAssumeCapacity(u32, value.fixed32) else return error.TypeMismatch,
            .fixed64 => if (value == .fixed64) writer.writeRawLittleAssumeCapacity(u64, value.fixed64) else return error.TypeMismatch,
            .sfixed32 => if (value == .sfixed32) writer.writeRawLittleAssumeCapacity(i32, value.sfixed32) else return error.TypeMismatch,
            .sfixed64 => if (value == .sfixed64) writer.writeRawLittleAssumeCapacity(i64, value.sfixed64) else return error.TypeMismatch,
            .float => if (value == .float) writer.writeRawLittleAssumeCapacity(u32, @bitCast(value.float)) else return error.TypeMismatch,
            .double => if (value == .double) writer.writeRawLittleAssumeCapacity(u64, @bitCast(value.double)) else return error.TypeMismatch,
            else => unreachable,
        }
    }
}

fn encodeScalar(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, number: wire.FieldNumber, scalar: schema.ScalarType, value: Value, writer: *wire.Writer) EncodeError!void {
    try validateScalarUtf8(file, field, .{ .scalar = scalar }, value);
    try writer.writeTag(number, scalar.wireType());
    try encodeScalarPayload(.{ .scalar = scalar }, value, writer);
}

fn encodeScalarPayloadWithValidation(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, kind: schema.FieldKind, value: Value, writer: *wire.Writer) EncodeError!void {
    try validateScalarUtf8(file, field, kind, value);
    try encodeScalarPayload(kind, value, writer);
}

fn validateScalarUtf8(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, kind: schema.FieldKind, value: Value) error{InvalidUtf8}!void {
    if (field.utf8Validation(file) != .verify) return;
    switch (kind) {
        .scalar => |scalar| {
            if (scalar == .string and value == .string and !std.unicode.utf8ValidateSlice(value.string)) return error.InvalidUtf8;
        },
        else => {},
    }
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
    field: *const schema.FieldDescriptor,
    kind: schema.FieldKind,
    reader: *wire.Reader,
) DecodeError!Value {
    return switch (kind) {
        .scalar => |scalar| switch (scalar) {
            .string => .{ .string = try decodeStringValue(allocator, file, field, try reader.readBytes()) },
            .bytes => .{ .bytes = try allocator.dupe(u8, try reader.readBytes()) },
            else => try decodeScalarLike(kind, reader),
        },
        .enumeration => try decodeScalarLike(kind, reader),
        .message => |name| blk: {
            const payload = try reader.readBytes();
            var payload_reader = try reader.nested(payload);
            break :blk try decodeMessagePayload(allocator, file, registry, current, name, &payload_reader);
        },
        .group => error.TypeMismatch,
        .map => error.TypeMismatch,
    };
}

fn decodeStringValue(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, bytes: []const u8) DecodeError![]u8 {
    if (field.utf8Validation(file) == .verify and !std.unicode.utf8ValidateSlice(bytes)) return error.InvalidUtf8;
    return try allocator.dupe(u8, bytes);
}

fn decodeMessagePayload(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    registry: ?*const registry_mod.Registry,
    current: *const schema.MessageDescriptor,
    name: []const u8,
    reader: *wire.Reader,
) DecodeError!Value {
    const descriptor = resolveMessageDescriptorWithRegistry(file, registry, current, name) orelse return error.TypeMismatch;
    const message = try allocator.create(DynamicMessage);
    message.* = DynamicMessage.init(allocator, descriptor);
    errdefer {
        message.deinit();
        allocator.destroy(message);
    }
    const descriptor_file = registry_mod.messageDefiningFile(file, registry, descriptor);
    try message.decodeStream(descriptor_file, registry, reader, null);
    try message.deduplicateDecodedMapFields();
    return .{ .message = message };
}

fn decodeMapEntryValue(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    registry: ?*const registry_mod.Registry,
    current: *const schema.MessageDescriptor,
    field: *const schema.FieldDescriptor,
    map_type: schema.MapType,
    entry_reader: *wire.Reader,
) DecodeError!?Value {
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
                if (maybe_key) |*old| {
                    deinitValue(old, allocator);
                    maybe_key = null;
                }
                maybe_key = try decodeValue(allocator, file, registry, current, field, .{ .scalar = map_type.key }, entry_reader);
            },
            2 => {
                if (maybe_value) |*old| {
                    deinitValue(old, allocator);
                    maybe_value = null;
                }
                if (registryEnumDescriptor(file, registry, current, map_type.value.*)) |enumeration| {
                    if (tag.wire_type != .varint) return error.InvalidWireType;
                    const value = try entry_reader.readInt32();
                    if (enumIsClosed(file, registry, enumeration) and !enumHasNumber(enumeration, value)) return null;
                    maybe_value = .{ .enumeration = value };
                } else {
                    if (tag.wire_type != map_type.value.wireType()) return error.InvalidWireType;
                    maybe_value = try decodeValue(allocator, file, registry, current, field, map_type.value.*, entry_reader);
                }
            },
            else => try entry_reader.skipValue(tag),
        }
    }

    var key = maybe_key orelse try defaultValue(allocator, file, registry, current, .{ .scalar = map_type.key });
    maybe_key = null;
    var map_value = maybe_value orelse blk: {
        if (registryEnumDescriptor(file, registry, current, map_type.value.*) != null) break :blk Value{ .enumeration = 0 };
        break :blk try defaultValue(allocator, file, registry, current, map_type.value.*);
    };
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
    registry: ?*const registry_mod.Registry,
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
            const descriptor = resolveMessageDescriptorWithRegistry(file, registry, current, name) orelse return error.TypeMismatch;
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
    try reader.enterRecursion();
    defer reader.leaveRecursion();
    try message.decodeStream(registry_mod.messageDefiningFile(file, registry, descriptor), registry, reader, field.number);
    try message.deduplicateDecodedMapFields();
    return .{ .group = message };
}

fn decodeDelimitedMessageValue(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    registry: ?*const registry_mod.Registry,
    current: *const schema.MessageDescriptor,
    field: *const schema.FieldDescriptor,
    reader: *wire.Reader,
) DecodeError!Value {
    const name = switch (field.kind) {
        .message => |message_name| message_name,
        else => return error.TypeMismatch,
    };
    const descriptor = resolveMessageDescriptorWithRegistry(file, registry, current, name) orelse return error.TypeMismatch;
    const message = try allocator.create(DynamicMessage);
    message.* = DynamicMessage.init(allocator, descriptor);
    errdefer {
        message.deinit();
        allocator.destroy(message);
    }
    try reader.enterRecursion();
    defer reader.leaveRecursion();
    try message.decodeStream(registry_mod.messageDefiningFile(file, registry, descriptor), registry, reader, field.number);
    try message.deduplicateDecodedMapFields();
    return .{ .message = message };
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

fn closedEnumDescriptor(file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, current: *const schema.MessageDescriptor, kind: schema.FieldKind) ?*const schema.EnumDescriptor {
    const enumeration = registryEnumDescriptor(file, registry, current, kind) orelse return null;
    return if (enumIsClosed(file, registry, enumeration)) enumeration else null;
}

fn registryEnumDescriptor(file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, current: *const schema.MessageDescriptor, kind: schema.FieldKind) ?*const schema.EnumDescriptor {
    const enum_name = switch (kind) {
        .enumeration => |name| name,
        .message => |name| name,
        else => return null,
    };
    if (registry) |reg| {
        if (std.mem.indexOfScalar(u8, enum_name, '.') == null) {
            if (current.findEnumDeep(enum_name) orelse file.findEnumDeep(enum_name)) |enumeration| return enumeration;
        }
        var scope_buf: [512]u8 = undefined;
        const scope = messageScope(file, current, &scope_buf) orelse if (file.package.len != 0) file.package else null;
        if (reg.findEnumVisible(file, enum_name, scope)) |enumeration| return enumeration;
        if (reg.findEnum(enum_name, scope)) |enumeration| return enumeration;
    }
    return current.findEnumDeep(enum_name) orelse file.findEnumDeep(enum_name);
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

fn enumHasNumber(enumeration: *const schema.EnumDescriptor, number: i32) bool {
    for (enumeration.values.items) |value| {
        if (value.number == number) return true;
    }
    return false;
}

fn enumNameForNumber(enumeration: *const schema.EnumDescriptor, number: i32) ?[]const u8 {
    for (enumeration.values.items) |*value| {
        if (value.number == number) return value.name;
    }
    return null;
}

fn enumIsClosed(file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, enumeration: *const schema.EnumDescriptor) bool {
    const enum_file = registry_mod.enumDefiningFile(file, registry, enumeration);
    return schema.FeatureSet.effective(enumeration.features, enum_file.features).enum_type == .closed;
}

fn fieldHasPresenceForEncoding(file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, current: ?*const schema.MessageDescriptor, field: *const schema.FieldDescriptor) bool {
    const field_file = registry_mod.fieldDefiningFile(file, registry, field);
    if (fieldIsRequired(field) or field.proto3_optional or field.oneof_name != null or field.kind == .group) return true;
    if (field.kind == .message and fieldKindIsRegistryEnum(field_file, registry, current, field.kind) == null) return true;
    if (field.cardinality == .repeated or field.kind == .map) return false;
    return schema.FeatureSet.effective(field.features, field_file.features).field_presence != .implicit;
}

fn fieldIsRequired(field: *const schema.FieldDescriptor) bool {
    if (field.cardinality == .required) return true;
    if (field.features) |features| return features.field_presence == .legacy_required;
    return false;
}

fn shouldMergeSingularMessageField(field: *const schema.FieldDescriptor) bool {
    if (field.cardinality == .repeated or field.kind == .map) return false;
    return field.kind == .message or field.kind == .group;
}

fn isDefaultSingularValue(field: *const schema.FieldDescriptor, value: Value) bool {
    if (field.default_value != null) return false;
    return switch (field.kind) {
        .scalar => |scalar| switch (scalar) {
            .double => value == .double and value.double == 0 and !std.math.isNegativeZero(value.double),
            .float => value == .float and value.float == 0 and !std.math.isNegativeZero(value.float),
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

fn isDefaultSingularValueForEncoding(file: ?*const schema.FileDescriptor, registry: ?*const registry_mod.Registry, current: ?*const schema.MessageDescriptor, field: *const schema.FieldDescriptor, value: Value) bool {
    if (field.default_value != null) return false;
    const field_file = if (file) |f| registry_mod.fieldDefiningFile(f, registry, field) else null;
    if (fieldKindIsRegistryEnum(field_file, registry, current, field.kind) == null) return isDefaultSingularValue(field, value);
    return value == .enumeration and value.enumeration == 0;
}

fn resolvedPackedForEncoding(file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, current: ?*const schema.MessageDescriptor, field: *const schema.FieldDescriptor) bool {
    if (field.cardinality != .repeated) return false;
    const field_file = registry_mod.fieldDefiningFile(file, registry, field);
    const kind = scalarLikeKindForEncoding(field_file, registry, current, field.kind);
    if (!kind.packable()) return false;
    if (field.packed_override) |is_packed| return is_packed;
    return schema.FeatureSet.effective(field.features, field_file.features).repeated_field_encoding == schema.FeatureSet.RepeatedFieldEncoding.packed_encoding;
}

fn scalarLikeKindForEncoding(file: ?*const schema.FileDescriptor, registry: ?*const registry_mod.Registry, current: ?*const schema.MessageDescriptor, kind: schema.FieldKind) schema.FieldKind {
    if (fieldKindIsRegistryEnum(file, registry, current, kind)) |name| return .{ .enumeration = name };
    return kind;
}

fn fieldKindIsRegistryEnum(file: ?*const schema.FileDescriptor, registry: ?*const registry_mod.Registry, current: ?*const schema.MessageDescriptor, kind: schema.FieldKind) ?[]const u8 {
    const enum_name = switch (kind) {
        .message, .enumeration => |name| name,
        else => return null,
    };
    const f = file orelse return null;
    const c = current orelse return if (f.findEnumDeep(enum_name) != null) enum_name else null;
    return if (registryEnumDescriptor(f, registry, c, kind) != null) enum_name else null;
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
        .message => |message| .{ .message = try cloneDynamicMessage(allocator, message) },
        .group => |message| .{ .group = try cloneDynamicMessage(allocator, message) },
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

fn cloneDynamicMessage(allocator: std.mem.Allocator, message: *const DynamicMessage) std.mem.Allocator.Error!*DynamicMessage {
    const cloned = try allocator.create(DynamicMessage);
    cloned.* = DynamicMessage.init(allocator, message.descriptor);
    errdefer {
        cloned.deinit();
        allocator.destroy(cloned);
    }

    // Clone the stored field/value arrays directly instead of routing through
    // add().  DynamicMessage state is already normalized when it is built, and
    // direct cloning both preserves the exact stored shape and keeps ownership
    // transfer explicit for every allocation-failure edge.
    try cloned.fields.ensureTotalCapacity(allocator, message.fields.items.len);
    for (message.fields.items) |*field| {
        cloned.fields.appendAssumeCapacity(.{ .descriptor = field.descriptor });
        const cloned_field = &cloned.fields.items[cloned.fields.items.len - 1];
        try cloned_field.values.ensureTotalCapacity(allocator, field.values.items.len);
        for (field.values.items) |item| {
            var cloned_item = try cloneValue(allocator, item);
            var owns_item = true;
            errdefer if (owns_item) deinitValue(&cloned_item, allocator);
            cloned_field.values.appendAssumeCapacity(cloned_item);
            owns_item = false;
        }
    }

    try cloned.unknown_fields.ensureTotalCapacity(allocator, message.unknown_fields.items.len);
    for (message.unknown_fields.items) |unknown| {
        const data = try allocator.dupe(u8, unknown.data);
        var owns_data = true;
        errdefer if (owns_data) allocator.free(data);
        cloned.unknown_fields.appendAssumeCapacity(.{
            .number = unknown.number,
            .wire_type = unknown.wire_type,
            .data = data,
        });
        owns_data = false;
    }

    return cloned;
}

fn exerciseCloneValueCleanup(allocator: std.mem.Allocator) !void {
    const field = schema.FieldDescriptor{
        .name = "name",
        .number = 1,
        .kind = .{ .scalar = .string },
    };
    const descriptor = schema.MessageDescriptor{ .name = "Cloneable" };

    const message = try allocator.create(DynamicMessage);
    message.* = DynamicMessage.init(allocator, &descriptor);
    defer {
        message.deinit();
        allocator.destroy(message);
    }

    const owned_string = try allocator.dupe(u8, "owned");
    var owns_string = true;
    errdefer if (owns_string) allocator.free(owned_string);
    try message.fields.append(allocator, .{ .descriptor = &field });
    try message.fields.items[0].values.append(allocator, .{ .string = owned_string });
    owns_string = false;

    const raw_unknown = try allocator.dupe(u8, &.{ 0x08, 0x01 });
    var owns_unknown = true;
    errdefer if (owns_unknown) allocator.free(raw_unknown);
    try message.unknown_fields.append(allocator, .{
        .number = 1,
        .wire_type = .varint,
        .data = raw_unknown,
    });
    owns_unknown = false;

    var cloned_value = try cloneValue(allocator, .{ .message = message });
    defer deinitValue(&cloned_value, allocator);
    const cloned = cloned_value.message;
    try std.testing.expect(cloned != message);
    try std.testing.expectEqual(@as(usize, 1), cloned.fields.items.len);
    try std.testing.expectEqual(@as(usize, 1), cloned.fields.items[0].values.items.len);
    try std.testing.expectEqualStrings("owned", cloned.fields.items[0].values.items[0].string);
    try std.testing.expect(cloned.fields.items[0].values.items[0].string.ptr != owned_string.ptr);
    try std.testing.expectEqual(@as(usize, 1), cloned.unknown_fields.items.len);
    try std.testing.expectEqualSlices(u8, raw_unknown, cloned.unknown_fields.items[0].data);
    try std.testing.expect(cloned.unknown_fields.items[0].data.ptr != raw_unknown.ptr);
}

fn unknownFieldIndexLessThan(message: *const DynamicMessage, a: usize, b: usize) bool {
    const lhs = message.unknown_fields.items[a];
    const rhs = message.unknown_fields.items[b];
    if (lhs.number != rhs.number) return lhs.number < rhs.number;
    return a < b;
}

fn sortFieldDescriptorsByNumber(fields: []*const schema.FieldDescriptor) void {
    std.mem.sort(*const schema.FieldDescriptor, fields, {}, struct {
        fn lessThan(_: void, lhs: *const schema.FieldDescriptor, rhs: *const schema.FieldDescriptor) bool {
            return lhs.number < rhs.number;
        }
    }.lessThan);
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

pub fn valueEqual(a: Value, b: Value) bool {
    return switch (a) {
        .boolean => |av| b == .boolean and av == b.boolean,
        .int32 => |av| b == .int32 and av == b.int32,
        .int64 => |av| b == .int64 and av == b.int64,
        .uint32 => |av| b == .uint32 and av == b.uint32,
        .uint64 => |av| b == .uint64 and av == b.uint64,
        .sint32 => |av| b == .sint32 and av == b.sint32,
        .sint64 => |av| b == .sint64 and av == b.sint64,
        .fixed32 => |av| b == .fixed32 and av == b.fixed32,
        .fixed64 => |av| b == .fixed64 and av == b.fixed64,
        .sfixed32 => |av| b == .sfixed32 and av == b.sfixed32,
        .sfixed64 => |av| b == .sfixed64 and av == b.sfixed64,
        .float => |av| b == .float and av == b.float,
        .double => |av| b == .double and av == b.double,
        .string => |av| b == .string and std.mem.eql(u8, av, b.string),
        .bytes => |av| b == .bytes and std.mem.eql(u8, av, b.bytes),
        .enumeration => |av| b == .enumeration and av == b.enumeration,
        .message => |av| b == .message and av == b.message,
        .group => |av| b == .group and av == b.group,
        .map_entry => |av| b == .map_entry and av == b.map_entry,
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

fn defaultForFieldWithRegistry(file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, current: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) DefaultValue {
    if (field.default_value) |value| {
        if (registryEnumDescriptor(file, registry, current, field.kind)) |enumeration| {
            return .{ .enumeration = enumDefaultNumber(enumeration, value) orelse 0 };
        }
        return defaultFromOption(field.kind, value);
    }
    if (registryEnumDescriptor(file, registry, current, field.kind)) |enumeration| {
        if (enumeration.values.items.len != 0) return .{ .enumeration = enumeration.values.items[0].number };
    }
    return defaultForField(field);
}

fn enumDefaultNumber(enumeration: *const schema.EnumDescriptor, value: schema.OptionValue) ?i32 {
    switch (value) {
        .integer => |v| return if (v >= std.math.minInt(i32) and v <= std.math.maxInt(i32)) @intCast(v) else null,
        .unsigned_integer => |v| return if (v <= std.math.maxInt(i32)) @intCast(v) else null,
        .identifier, .string => |text| {
            if (parseIntegerDefault(i32, text)) |number| return number else |_| {}
            if (enumeration.findValue(text)) |enum_value| return enum_value.number;
            return null;
        },
        else => return null,
    }
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
        .unsigned_integer => |v| if (v <= std.math.maxInt(T)) @intCast(v) else null,
        .identifier, .string => |text| parseIntegerDefault(T, text) catch null,
        else => null,
    };
}

fn optionFloat(comptime T: type, value: schema.OptionValue) ?T {
    return switch (value) {
        .float => |v| @floatCast(v),
        .integer => |v| @floatFromInt(v),
        .unsigned_integer => |v| @floatFromInt(v),
        .identifier, .string => |text| parseSpecialFloatDefault(T, text) orelse (std.fmt.parseFloat(T, text) catch null),
        else => null,
    };
}

fn parseSpecialFloatDefault(comptime T: type, text: []const u8) ?T {
    var body = text;
    var negative = false;
    if (body.len != 0 and (body[0] == '-' or body[0] == '+')) {
        negative = body[0] == '-';
        body = body[1..];
    }
    if (std.ascii.eqlIgnoreCase(body, "inf") or std.ascii.eqlIgnoreCase(body, "infinity")) {
        const value = std.math.inf(T);
        return if (negative) -value else value;
    }
    if (std.ascii.eqlIgnoreCase(body, "nan")) return std.math.nan(T);
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

/// Internal declarations exposed for the externalized test suite.
const __pbz_test_exerciseCloneValueCleanup = exerciseCloneValueCleanup;
const __pbz_test_writeMessageSetItem = writeMessageSetItem;
pub const test_helpers = struct {
    pub const exerciseCloneValueCleanup = __pbz_test_exerciseCloneValueCleanup;
    pub const writeMessageSetItem = __pbz_test_writeMessageSetItem;

    pub fn decodeStream(self: *DynamicMessage, file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, reader: *wire.Reader, end_group: ?wire.FieldNumber) DecodeError!void {
        return self.decodeStream(file, registry, reader, end_group);
    }
};

test {
    _ = @import("dynamic_tests.zig");
}
