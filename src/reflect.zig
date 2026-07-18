const std = @import("std");
const schema = @import("schema.zig");
const parser = @import("parser.zig");
const registry_mod = @import("registry.zig");
const dynamic = @import("dynamic.zig");
const wire = @import("wire.zig");

pub const Error = std.mem.Allocator.Error || error{ UnknownMessage, UnknownField, MissingField, TypeMismatch };

pub const Reflection = struct {
    allocator: std.mem.Allocator,
    registry: *const registry_mod.Registry,

    pub fn init(allocator: std.mem.Allocator, registry: *const registry_mod.Registry) Reflection {
        return .{ .allocator = allocator, .registry = registry };
    }

    pub fn message(self: Reflection, name: []const u8) Error!*const schema.MessageDescriptor {
        return self.registry.findMessage(name, null) orelse error.UnknownMessage;
    }

    pub fn fileOfMessage(self: Reflection, descriptor: *const schema.MessageDescriptor) Error!*const schema.FileDescriptor {
        return self.registry.fileContainingMessage(descriptor) orelse error.UnknownMessage;
    }

    pub fn newMessage(self: Reflection, name: []const u8) Error!dynamic.DynamicMessage {
        return dynamic.DynamicMessage.init(self.allocator, try self.message(name));
    }

    pub fn fieldByName(_: Reflection, descriptor: *const schema.MessageDescriptor, name: []const u8) Error!*const schema.FieldDescriptor {
        return descriptor.findField(name) orelse error.UnknownField;
    }

    pub fn fieldByNumber(_: Reflection, descriptor: *const schema.MessageDescriptor, number: wire.FieldNumber) Error!*const schema.FieldDescriptor {
        return descriptor.findFieldByNumber(number) orelse error.UnknownField;
    }

    pub fn has(_: Reflection, message_value: *const dynamic.DynamicMessage, field: *const schema.FieldDescriptor) bool {
        return message_value.has(field);
    }

    pub fn hasField(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!bool {
        return self.has(message_value, try self.fieldByName(message_value.descriptor, name));
    }

    pub fn get(_: Reflection, message_value: *const dynamic.DynamicMessage, field: *const schema.FieldDescriptor) ?*const dynamic.FieldValue {
        return message_value.getByNumber(field.number);
    }

    pub fn getField(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!?*const dynamic.FieldValue {
        return self.get(message_value, try self.fieldByName(message_value.descriptor, name));
    }

    pub fn repeatedLen(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!usize {
        const field = try self.fieldByName(message_value.descriptor, name);
        return if (message_value.getByNumber(field.number)) |value| value.values.items.len else 0;
    }

    pub fn repeatedValue(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8, index: usize) Error!dynamic.Value {
        const field = try self.fieldByName(message_value.descriptor, name);
        const value = message_value.getByNumber(field.number) orelse return error.MissingField;
        if (index >= value.values.items.len) return error.MissingField;
        return value.values.items[index];
    }

    /// Replace a singular field or append/replace map entries using an owned
    /// dynamic value. String, bytes, message, group, and map-entry payloads are
    /// consumed on success and freed on failure.
    pub fn set(self: Reflection, message_value: *dynamic.DynamicMessage, field: *const schema.FieldDescriptor, value: dynamic.Value) Error!void {
        var owned = value;
        errdefer dynamic.deinitValue(&owned, self.allocator);
        // DynamicMessage.add already replaces singular values and map entries.
        // Avoid clearing those fields first: if allocation fails while adding
        // the replacement, callers should not lose the previous value.
        if (field.cardinality == .repeated and field.kind != .map) self.clear(message_value, field);
        try message_value.add(field, owned);
    }

    /// Add an owned dynamic value. String, bytes, message, group, and map-entry
    /// payloads are consumed on success and freed on failure.
    pub fn add(_: Reflection, message_value: *dynamic.DynamicMessage, field: *const schema.FieldDescriptor, value: dynamic.Value) Error!void {
        var owned = value;
        errdefer dynamic.deinitValue(&owned, message_value.allocator);
        try message_value.add(field, owned);
    }

    pub fn clear(self: Reflection, message_value: *dynamic.DynamicMessage, field: *const schema.FieldDescriptor) void {
        var index: usize = 0;
        while (index < message_value.fields.items.len) {
            if (message_value.fields.items[index].descriptor.number == field.number) {
                message_value.fields.items[index].deinit(self.allocator);
                _ = message_value.fields.swapRemove(index);
                return;
            }
            index += 1;
        }
    }

    pub fn clearField(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8) Error!void {
        self.clear(message_value, try self.fieldByName(message_value.descriptor, name));
    }

    pub fn whichOneof(_: Reflection, message_value: *const dynamic.DynamicMessage, oneof_name: []const u8) ?*const schema.FieldDescriptor {
        return message_value.whichOneof(oneof_name);
    }

    pub fn setInt32(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: i32) Error!void {
        try self.set(message_value, try self.fieldByName(message_value.descriptor, name), .{ .int32 = value });
    }

    pub fn addInt32(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: i32) Error!void {
        try self.add(message_value, try self.fieldByName(message_value.descriptor, name), .{ .int32 = value });
    }

    pub fn getInt32(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!i32 {
        const field = try self.fieldByName(message_value.descriptor, name);
        const value = lastValue(message_value, field) orelse return error.MissingField;
        return switch (value) {
            .int32 => |v| v,
            else => error.TypeMismatch,
        };
    }

    pub fn setInt64(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: i64) Error!void {
        try self.set(message_value, try self.fieldByName(message_value.descriptor, name), .{ .int64 = value });
    }

    pub fn getInt64(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!i64 {
        const field = try self.fieldByName(message_value.descriptor, name);
        const value = lastValue(message_value, field) orelse return error.MissingField;
        return switch (value) {
            .int64 => |v| v,
            else => error.TypeMismatch,
        };
    }

    pub fn setBool(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: bool) Error!void {
        try self.set(message_value, try self.fieldByName(message_value.descriptor, name), .{ .boolean = value });
    }

    pub fn getBool(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!bool {
        const field = try self.fieldByName(message_value.descriptor, name);
        const value = lastValue(message_value, field) orelse return error.MissingField;
        return switch (value) {
            .boolean => |v| v,
            else => error.TypeMismatch,
        };
    }

    pub fn setString(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: []const u8) Error!void {
        const field = try self.fieldByName(message_value.descriptor, name);
        const owned = try self.allocator.dupe(u8, value);
        var owns_owned = true;
        errdefer if (owns_owned) self.allocator.free(owned);
        owns_owned = false;
        try self.set(message_value, field, .{ .string = owned });
    }

    pub fn addString(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: []const u8) Error!void {
        const field = try self.fieldByName(message_value.descriptor, name);
        const owned = try self.allocator.dupe(u8, value);
        var owns_owned = true;
        errdefer if (owns_owned) self.allocator.free(owned);
        owns_owned = false;
        try self.add(message_value, field, .{ .string = owned });
    }

    pub fn getString(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error![]const u8 {
        const field = try self.fieldByName(message_value.descriptor, name);
        const value = lastValue(message_value, field) orelse return error.MissingField;
        return switch (value) {
            .string => |v| v,
            else => error.TypeMismatch,
        };
    }

    pub fn setBytes(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: []const u8) Error!void {
        const field = try self.fieldByName(message_value.descriptor, name);
        const owned = try self.allocator.dupe(u8, value);
        var owns_owned = true;
        errdefer if (owns_owned) self.allocator.free(owned);
        owns_owned = false;
        try self.set(message_value, field, .{ .bytes = owned });
    }

    pub fn getBytes(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error![]const u8 {
        const field = try self.fieldByName(message_value.descriptor, name);
        const value = lastValue(message_value, field) orelse return error.MissingField;
        return switch (value) {
            .bytes => |v| v,
            else => error.TypeMismatch,
        };
    }

    pub fn setEnum(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: i32) Error!void {
        try self.set(message_value, try self.fieldByName(message_value.descriptor, name), .{ .enumeration = value });
    }

    pub fn getEnum(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!i32 {
        const field = try self.fieldByName(message_value.descriptor, name);
        const value = lastValue(message_value, field) orelse return error.MissingField;
        return switch (value) {
            .enumeration => |v| v,
            else => error.TypeMismatch,
        };
    }

    pub fn putMapEntryOwned(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, key: dynamic.Value, value: dynamic.Value) Error!void {
        const field = try self.fieldByName(message_value.descriptor, name);
        const entry = try self.allocator.create(dynamic.MapEntry);
        var owns_entry = true;
        errdefer if (owns_entry) self.allocator.destroy(entry);
        entry.* = .{ .key = key, .value = value };
        errdefer if (owns_entry) entry.deinit(self.allocator);
        owns_entry = false;
        try self.add(message_value, field, .{ .map_entry = entry });
    }

    pub fn putStringInt32MapEntry(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, key: []const u8, value: i32) Error!void {
        const owned_key = try self.allocator.dupe(u8, key);
        var key_value = dynamic.Value{ .string = owned_key };
        errdefer dynamic.deinitValue(&key_value, self.allocator);
        try self.putMapEntryOwned(message_value, name, key_value, .{ .int32 = value });
    }
};

fn lastValue(message_value: *const dynamic.DynamicMessage, field: *const schema.FieldDescriptor) ?dynamic.Value {
    const field_value = message_value.getByNumber(field.number) orelse return null;
    if (field_value.values.items.len == 0) return null;
    return field_value.values.items[field_value.values.items.len - 1];
}

test "reflection facade creates and edits dynamic messages" {
    const allocator = std.testing.allocator;
    var file = try parser.Parser.parse(allocator,
        \\syntax = "proto3";
        \\package demo;
        \\message Person {
        \\  int32 id = 1;
        \\  string name = 2;
        \\  repeated int32 score = 3;
        \\  map<string, int32> counts = 4;
        \\  oneof pick { bool active = 5; string label = 6; }
        \\}
    );
    defer file.deinit();
    var reg = registry_mod.Registry.init(allocator);
    defer reg.deinit();
    try reg.addFile(&file);

    const refl = Reflection.init(allocator, &reg);
    var msg = try refl.newMessage("demo.Person");
    defer msg.deinit();

    try refl.setInt32(&msg, "id", 7);
    try refl.setString(&msg, "name", "Zig");
    try refl.addInt32(&msg, "score", 10);
    try refl.addInt32(&msg, "score", 20);
    try refl.putStringInt32MapEntry(&msg, "counts", "red", 1);
    try refl.setBool(&msg, "active", true);
    try std.testing.expectEqual(@as(i32, 7), try refl.getInt32(&msg, "id"));
    try std.testing.expectEqualStrings("Zig", try refl.getString(&msg, "name"));
    try std.testing.expectEqual(@as(usize, 2), try refl.repeatedLen(&msg, "score"));
    try std.testing.expectEqual(@as(i32, 20), (try refl.repeatedValue(&msg, "score", 1)).int32);
    try std.testing.expectEqualStrings("active", refl.whichOneof(&msg, "pick").?.name);

    try refl.setString(&msg, "label", "chosen");
    try std.testing.expectEqualStrings("label", refl.whichOneof(&msg, "pick").?.name);
    try std.testing.expectEqualStrings("chosen", try refl.getString(&msg, "label"));

    try refl.clearField(&msg, "name");
    try std.testing.expect(!(try refl.hasField(&msg, "name")));
}
