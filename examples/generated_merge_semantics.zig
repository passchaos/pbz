const std = @import("std");
const pbz = @import("pbz");
const person_pb = @import("generated/person.pb.zig");

const demo = person_pb.demo;

fn encodePresenceMixName(allocator: std.mem.Allocator, count: i32, name: []const u8) ![]u8 {
    var msg = demo.PresenceMix.init();
    defer msg.deinit(allocator);
    msg.count = count;
    msg.has_count = true;
    msg.pick = .{ .name = name };
    return try msg.encode(allocator);
}

fn encodePresenceMixNested(allocator: std.mem.Allocator, id: i32, label: []const u8) ![]u8 {
    var msg = demo.PresenceMix.init();
    defer msg.deinit(allocator);
    msg.pick = .{ .nested = try presenceChild(id, label).cloneOwned(allocator) };
    return try msg.encode(allocator);
}

fn presenceChild(id: i32, label: []const u8) demo.PresenceMix.Child {
    var child = demo.PresenceMix.Child.init();
    child.id = id;
    child.label = label;
    return child;
}

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Protobuf binary parsing merges repeated occurrences of singular message
    // fields, appends repeated fields, applies map last-wins by key, and lets
    // the last oneof arm win. These are subtle C++ protobuf compatibility rules
    // that generated decode/decodeReuse must preserve.

    var writer = pbz.Writer.init(allocator);
    defer writer.deinit();
    const first_child_bytes = try childBytes(allocator, 1, "first");
    defer allocator.free(first_child_bytes);
    const second_child_bytes = try childBytes(allocator, 2, "second");
    defer allocator.free(second_child_bytes);
    try writer.writeMessage(4, first_child_bytes);
    try writer.writeMessage(4, second_child_bytes);
    const merged_child_bytes = try writer.toOwnedSlice();
    defer allocator.free(merged_child_bytes);
    var decoded_presence = try demo.PresenceMix.decodeOwnedInitialized(allocator, merged_child_bytes);
    defer decoded_presence.deinit(allocator);
    try std.testing.expectEqual(@as(i32, 2), decoded_presence.child.?.id);
    try std.testing.expectEqualStrings("second", decoded_presence.child.?.label);

    const first_oneof = try encodePresenceMixName(allocator, 1, "first-name");
    defer allocator.free(first_oneof);
    const second_oneof = try encodePresenceMixNested(allocator, 3, "nested-wins");
    defer allocator.free(second_oneof);
    var oneof_payload = try allocator.alloc(u8, first_oneof.len + second_oneof.len);
    defer allocator.free(oneof_payload);
    @memcpy(oneof_payload[0..first_oneof.len], first_oneof);
    @memcpy(oneof_payload[first_oneof.len..], second_oneof);
    var decoded_oneof = try demo.PresenceMix.decodeOwnedInitialized(allocator, oneof_payload);
    defer decoded_oneof.deinit(allocator);
    try std.testing.expect(decoded_oneof.has_count);
    try std.testing.expectEqual(@as(i32, 1), decoded_oneof.count);
    switch (decoded_oneof.pick) {
        .nested => |child| {
            try std.testing.expectEqual(@as(i32, 3), child.id);
            try std.testing.expectEqualStrings("nested-wins", child.label);
        },
        else => return error.UnexpectedOneof,
    }

    var person_writer = pbz.Writer.init(allocator);
    defer person_writer.deinit();
    try person_writer.writeInt32(3, 10);
    try person_writer.writeInt32(3, 20);
    const first_map_entry = try mapEntryBytes(allocator, "same", 1);
    defer allocator.free(first_map_entry);
    const second_map_entry = try mapEntryBytes(allocator, "same", 2);
    defer allocator.free(second_map_entry);
    try person_writer.writeBytes(4, first_map_entry);
    try person_writer.writeBytes(4, second_map_entry);
    const person_bytes = try person_writer.toOwnedSlice();
    defer allocator.free(person_bytes);
    var person = try demo.Person.decodeOwnedInitialized(allocator, person_bytes);
    defer person.deinit(allocator);
    try std.testing.expectEqualSlices(i32, &.{ 10, 20 }, person.scores);
    try std.testing.expectEqual(@as(i32, 2), person.counts.get("same").?);

    var reuse = demo.Person.init();
    defer reuse.deinit(allocator);
    try reuse.decodeReuse(allocator, person_bytes);
    try std.testing.expectEqualSlices(i32, &.{ 10, 20 }, reuse.scores);
    try std.testing.expectEqual(@as(i32, 2), reuse.counts.get("same").?);
}

fn childBytes(allocator: std.mem.Allocator, id: i32, label: []const u8) ![]u8 {
    var child = presenceChild(id, label);
    defer child.deinit(allocator);
    return try child.encode(allocator);
}

fn mapEntryBytes(allocator: std.mem.Allocator, key: []const u8, value: i32) ![]u8 {
    const entry = demo.Person.countsEntry{ .key = key, .value = value };
    var writer = pbz.Writer.init(allocator);
    errdefer writer.deinit();
    try writer.writeString(1, entry.key);
    try writer.writeInt32(2, entry.value);
    return try writer.toOwnedSlice();
}

comptime {
    _ = pbz;
}
