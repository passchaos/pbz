const std = @import("std");
const pbz = @import("pbz");
const nested_pb = @import("generated/nested_types.pb.zig");

const nested = nested_pb.demo.nested;

fn inner(id: i32, state: nested.Outer.State) nested.Outer.Inner {
    var out = nested.Outer.Inner.init();
    out.id = id;
    out.state = state.toInt();
    return out;
}

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Nested messages/enums should be addressable through package and parent
    // namespaces like C++ generated types, and field metadata should expose the
    // nested type references for reflection-free generic helpers.
    std.debug.assert(nested.Outer.primary_field.has_type_ref);
    std.debug.assert(nested.Outer.primary_field.type_ref == nested.Outer.Inner);
    std.debug.assert(nested.Outer.history_field.type_ref == nested.Outer.Inner);
    std.debug.assert(nested.Outer.by_name_field.map_value_has_type_ref);
    std.debug.assert(nested.Outer.by_name_field.map_value_type_ref == nested.Outer.Inner);
    std.debug.assert(nested.Outer.chosen_field.type_ref == nested.Outer.Inner);
    std.debug.assert(nested.Outer.chosen_state_field.has_enum_ref);
    std.debug.assert(nested.Outer.chosen_state_field.enum_ref == nested.Outer.State);
    std.debug.assert(nested.Outer.State.fromName("STATE_READY") == .STATE_READY);

    var outer = nested.Outer.init();
    defer outer.deinit(allocator);
    outer.primary = try inner(1, .STATE_READY).cloneOwned(allocator);
    const history = try allocator.alloc(nested.Outer.Inner, 2);
    history[0] = try inner(2, .STATE_UNKNOWN).cloneOwned(allocator);
    history[1] = try inner(3, .STATE_READY).cloneOwned(allocator);
    outer.history = history;
    try outer.by_name.put(allocator, "primary", try inner(4, .STATE_READY).cloneOwned(allocator));
    try outer.by_name.put(allocator, "backup", try inner(5, .STATE_UNKNOWN).cloneOwned(allocator));
    outer.selected = .{ .chosen = try inner(6, .STATE_READY).cloneOwned(allocator) };

    const bytes = try outer.encodeInitialized(allocator);
    defer allocator.free(bytes);
    var decoded = try nested.Outer.decodeOwnedInitialized(allocator, bytes);
    defer decoded.deinit(allocator);
    try std.testing.expectEqual(@as(i32, 1), decoded.primary.?.id);
    try std.testing.expectEqual(@as(usize, 2), decoded.history.len);
    try std.testing.expectEqual(@as(i32, 5), decoded.by_name.get("backup").?.id);
    switch (decoded.selected) {
        .chosen => |value| try std.testing.expectEqual(@as(i32, 6), value.id),
        else => return error.UnexpectedOneof,
    }

    const json = try decoded.jsonStringifyAlloc(allocator);
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"primary\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"history\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"byName\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"chosen\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "STATE_READY") != null);

    var json_roundtrip = try nested.Outer.jsonParseInitialized(allocator, json);
    defer json_roundtrip.deinit(allocator);
    try std.testing.expectEqual(@as(i32, 1), json_roundtrip.primary.?.id);
    try std.testing.expectEqual(@as(i32, 4), json_roundtrip.by_name.get("primary").?.id);

    var proto_name_json = try nested.Outer.jsonParseInitialized(
        allocator,
        "{\"primary\":{\"id\":7,\"state\":\"STATE_READY\"},\"history\":[{\"id\":8}],\"by_name\":{\"x\":{\"id\":9}},\"chosen_state\":\"STATE_READY\"}",
    );
    defer proto_name_json.deinit(allocator);
    try std.testing.expectEqual(@as(i32, 7), proto_name_json.primary.?.id);
    try std.testing.expectEqual(@as(i32, 9), proto_name_json.by_name.get("x").?.id);
    switch (proto_name_json.selected) {
        .chosen_state => |value| try std.testing.expectEqual(nested.Outer.State.STATE_READY.toInt(), value),
        else => return error.UnexpectedOneof,
    }

    const text = try decoded.formatTextAlloc(allocator);
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "primary {") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "history {") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "by_name {") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "chosen {") != null);

    var text_roundtrip = try nested.Outer.parseTextInitialized(allocator, text);
    defer text_roundtrip.deinit(allocator);
    try std.testing.expectEqual(@as(i32, 1), text_roundtrip.primary.?.id);
    try std.testing.expectEqual(@as(i32, 5), text_roundtrip.by_name.get("backup").?.id);
}

comptime {
    _ = pbz;
}
