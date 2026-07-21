const std = @import("std");
const schema = @import("schema.zig");
const parser = @import("parser.zig");
const registry_mod = @import("registry.zig");
const dynamic = @import("dynamic.zig");
const wire = @import("wire.zig");

pub const Error = std.mem.Allocator.Error || error{ UnknownMessage, UnknownService, UnknownField, MissingField, TypeMismatch };

const ValueTag = std.meta.Tag(dynamic.Value);

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

    pub fn service(self: Reflection, name: []const u8) Error!*const schema.ServiceDescriptor {
        return self.registry.findService(name, null) orelse error.UnknownService;
    }

    pub fn fileOfService(self: Reflection, descriptor: *const schema.ServiceDescriptor) Error!*const schema.FileDescriptor {
        return self.registry.fileContainingService(descriptor) orelse error.UnknownService;
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
        _ = self;
        _ = message_value.clearField(field);
    }

    pub fn clearField(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8) Error!void {
        self.clear(message_value, try self.fieldByName(message_value.descriptor, name));
    }

    pub fn whichOneof(_: Reflection, message_value: *const dynamic.DynamicMessage, oneof_name: []const u8) ?*const schema.FieldDescriptor {
        return message_value.whichOneof(oneof_name);
    }

    fn setScalar(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, comptime tag: ValueTag, value: anytype) Error!void {
        try self.set(message_value, try self.fieldByName(message_value.descriptor, name), @unionInit(dynamic.Value, @tagName(tag), value));
    }

    fn addScalar(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, comptime tag: ValueTag, value: anytype) Error!void {
        try self.add(message_value, try self.fieldByName(message_value.descriptor, name), @unionInit(dynamic.Value, @tagName(tag), value));
    }

    fn getScalar(self: Reflection, comptime T: type, message_value: *const dynamic.DynamicMessage, name: []const u8, comptime tag: ValueTag) Error!T {
        const field = try self.fieldByName(message_value.descriptor, name);
        const value = lastValue(message_value, field) orelse return error.MissingField;
        if (std.meta.activeTag(value) != tag) return error.TypeMismatch;
        return @field(value, @tagName(tag));
    }

    pub fn setInt32(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: i32) Error!void {
        try self.setScalar(message_value, name, .int32, value);
    }

    pub fn addInt32(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: i32) Error!void {
        try self.addScalar(message_value, name, .int32, value);
    }

    pub fn getInt32(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!i32 {
        return try self.getScalar(i32, message_value, name, .int32);
    }

    pub fn setInt64(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: i64) Error!void {
        try self.setScalar(message_value, name, .int64, value);
    }

    pub fn addInt64(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: i64) Error!void {
        try self.addScalar(message_value, name, .int64, value);
    }

    pub fn getInt64(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!i64 {
        return try self.getScalar(i64, message_value, name, .int64);
    }

    pub fn setUInt32(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: u32) Error!void {
        try self.setScalar(message_value, name, .uint32, value);
    }

    pub fn addUInt32(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: u32) Error!void {
        try self.addScalar(message_value, name, .uint32, value);
    }

    pub fn getUInt32(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!u32 {
        return try self.getScalar(u32, message_value, name, .uint32);
    }

    pub fn setUInt64(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: u64) Error!void {
        try self.setScalar(message_value, name, .uint64, value);
    }

    pub fn addUInt64(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: u64) Error!void {
        try self.addScalar(message_value, name, .uint64, value);
    }

    pub fn getUInt64(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!u64 {
        return try self.getScalar(u64, message_value, name, .uint64);
    }

    pub fn setSInt32(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: i32) Error!void {
        try self.setScalar(message_value, name, .sint32, value);
    }

    pub fn addSInt32(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: i32) Error!void {
        try self.addScalar(message_value, name, .sint32, value);
    }

    pub fn getSInt32(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!i32 {
        return try self.getScalar(i32, message_value, name, .sint32);
    }

    pub fn setSInt64(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: i64) Error!void {
        try self.setScalar(message_value, name, .sint64, value);
    }

    pub fn addSInt64(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: i64) Error!void {
        try self.addScalar(message_value, name, .sint64, value);
    }

    pub fn getSInt64(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!i64 {
        return try self.getScalar(i64, message_value, name, .sint64);
    }

    pub fn setFixed32(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: u32) Error!void {
        try self.setScalar(message_value, name, .fixed32, value);
    }

    pub fn addFixed32(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: u32) Error!void {
        try self.addScalar(message_value, name, .fixed32, value);
    }

    pub fn getFixed32(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!u32 {
        return try self.getScalar(u32, message_value, name, .fixed32);
    }

    pub fn setFixed64(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: u64) Error!void {
        try self.setScalar(message_value, name, .fixed64, value);
    }

    pub fn addFixed64(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: u64) Error!void {
        try self.addScalar(message_value, name, .fixed64, value);
    }

    pub fn getFixed64(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!u64 {
        return try self.getScalar(u64, message_value, name, .fixed64);
    }

    pub fn setSFixed32(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: i32) Error!void {
        try self.setScalar(message_value, name, .sfixed32, value);
    }

    pub fn addSFixed32(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: i32) Error!void {
        try self.addScalar(message_value, name, .sfixed32, value);
    }

    pub fn getSFixed32(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!i32 {
        return try self.getScalar(i32, message_value, name, .sfixed32);
    }

    pub fn setSFixed64(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: i64) Error!void {
        try self.setScalar(message_value, name, .sfixed64, value);
    }

    pub fn addSFixed64(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: i64) Error!void {
        try self.addScalar(message_value, name, .sfixed64, value);
    }

    pub fn getSFixed64(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!i64 {
        return try self.getScalar(i64, message_value, name, .sfixed64);
    }

    pub fn setFloat(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: f32) Error!void {
        try self.setScalar(message_value, name, .float, value);
    }

    pub fn addFloat(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: f32) Error!void {
        try self.addScalar(message_value, name, .float, value);
    }

    pub fn getFloat(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!f32 {
        return try self.getScalar(f32, message_value, name, .float);
    }

    pub fn setDouble(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: f64) Error!void {
        try self.setScalar(message_value, name, .double, value);
    }

    pub fn addDouble(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: f64) Error!void {
        try self.addScalar(message_value, name, .double, value);
    }

    pub fn getDouble(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!f64 {
        return try self.getScalar(f64, message_value, name, .double);
    }

    pub fn setBool(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: bool) Error!void {
        try self.setScalar(message_value, name, .boolean, value);
    }

    pub fn addBool(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: bool) Error!void {
        try self.addScalar(message_value, name, .boolean, value);
    }

    pub fn getBool(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!bool {
        return try self.getScalar(bool, message_value, name, .boolean);
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
        return try self.getScalar([]const u8, message_value, name, .string);
    }

    pub fn setBytes(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: []const u8) Error!void {
        const field = try self.fieldByName(message_value.descriptor, name);
        const owned = try self.allocator.dupe(u8, value);
        var owns_owned = true;
        errdefer if (owns_owned) self.allocator.free(owned);
        owns_owned = false;
        try self.set(message_value, field, .{ .bytes = owned });
    }

    pub fn addBytes(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: []const u8) Error!void {
        const field = try self.fieldByName(message_value.descriptor, name);
        const owned = try self.allocator.dupe(u8, value);
        var owns_owned = true;
        errdefer if (owns_owned) self.allocator.free(owned);
        owns_owned = false;
        try self.add(message_value, field, .{ .bytes = owned });
    }

    pub fn getBytes(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error![]const u8 {
        return try self.getScalar([]const u8, message_value, name, .bytes);
    }

    pub fn setEnum(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: i32) Error!void {
        try self.setScalar(message_value, name, .enumeration, value);
    }

    pub fn addEnum(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, value: i32) Error!void {
        try self.addScalar(message_value, name, .enumeration, value);
    }

    pub fn getEnum(self: Reflection, message_value: *const dynamic.DynamicMessage, name: []const u8) Error!i32 {
        return try self.getScalar(i32, message_value, name, .enumeration);
    }

    pub fn putMapEntryOwned(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, key: dynamic.Value, value: dynamic.Value) Error!void {
        var owned_key = key;
        var owns_key = true;
        errdefer if (owns_key) dynamic.deinitValue(&owned_key, self.allocator);
        var owned_value = value;
        var owns_value = true;
        errdefer if (owns_value) dynamic.deinitValue(&owned_value, self.allocator);
        const field = try self.fieldByName(message_value.descriptor, name);
        const entry = try self.allocator.create(dynamic.MapEntry);
        var owns_entry = true;
        errdefer if (owns_entry) self.allocator.destroy(entry);
        entry.* = .{ .key = owned_key, .value = owned_value };
        owns_key = false;
        owns_value = false;
        errdefer if (owns_entry) entry.deinit(self.allocator);
        try message_value.add(field, .{ .map_entry = entry });
        owns_entry = false;
    }

    pub fn putStringInt32MapEntry(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, key: []const u8, value: i32) Error!void {
        const owned_key = try self.allocator.dupe(u8, key);
        try self.putMapEntryOwned(message_value, name, .{ .string = owned_key }, .{ .int32 = value });
    }

    pub fn clearMapEntry(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, key: dynamic.Value) Error!bool {
        return message_value.clearMapEntry(try self.fieldByName(message_value.descriptor, name), key);
    }

    pub fn clearStringMapEntry(self: Reflection, message_value: *dynamic.DynamicMessage, name: []const u8, key: []const u8) Error!bool {
        const owned_key = try self.allocator.dupe(u8, key);
        defer self.allocator.free(owned_key);
        return try self.clearMapEntry(message_value, name, .{ .string = owned_key });
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

fn exerciseReflectionCleanup(allocator: std.mem.Allocator, registry: *const registry_mod.Registry) !void {
    const refl = Reflection.init(allocator, registry);
    var msg = try refl.newMessage("demo.Person");
    defer msg.deinit();

    try refl.setString(&msg, "name", "Zig");
    try refl.addString(&msg, "tags", "one");
    try refl.putStringInt32MapEntry(&msg, "counts", "red", 1);

    try std.testing.expectEqualStrings("Zig", try refl.getString(&msg, "name"));
    try std.testing.expectEqual(@as(usize, 1), try refl.repeatedLen(&msg, "tags"));
    try std.testing.expectEqual(@as(usize, 1), msg.get("counts").?.values.items.len);
}

test "reflection facade cleans up allocation failures" {
    const allocator = std.testing.allocator;
    var file = try parser.Parser.parse(allocator,
        \\syntax = "proto3";
        \\package demo;
        \\message Person {
        \\  string name = 1;
        \\  repeated string tags = 2;
        \\  map<string, int32> counts = 3;
        \\}
    );
    defer file.deinit();
    var reg = registry_mod.Registry.init(allocator);
    defer reg.deinit();
    try reg.addFile(&file);

    try std.testing.checkAllAllocationFailures(allocator, exerciseReflectionCleanup, .{&reg});
}
