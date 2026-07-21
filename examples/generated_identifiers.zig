const std = @import("std");
const pbz = @import("pbz");
const identifiers_pb = @import("generated/identifiers.pb.zig");

const ids = identifiers_pb.demo.identifiers;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Protobuf schemas in the wild sometimes use words that are Zig keywords,
    // primitive type names, or common test declarations. Generated code must
    // quote those identifiers consistently while preserving the original proto
    // and JSON/TextFormat names on the wire.
    std.debug.assert(ids.@"type".type_number == 1);
    std.debug.assert(std.mem.eql(u8, ids.@"type".type_field.name, "type"));
    std.debug.assert(std.mem.eql(u8, ids.@"type".error_field.name, "error"));
    std.debug.assert(std.mem.eql(u8, ids.@"type".opaque_field.name, "opaque"));

    var msg = ids.@"type".init();
    defer msg.deinit(allocator);
    msg.@"type" = 7;
    msg.@"error" = "keyword-safe";
    msg.@"test" = try allocator.dupe([]const u8, &.{ "alpha", "beta" });
    try msg.@"align".put(allocator, "left", 1);
    try msg.@"align".put(allocator, "right", 2);
    msg.@"null" = true;
    msg.async = .{ .await = "ready" };

    const bytes = try msg.encodeInitialized(allocator);
    defer allocator.free(bytes);

    var decoded = try ids.@"type".decodeOwnedInitialized(allocator, bytes);
    defer decoded.deinit(allocator);
    try std.testing.expectEqual(@as(i32, 7), decoded.@"type");
    try std.testing.expectEqualStrings("keyword-safe", decoded.@"error");
    try std.testing.expectEqual(@as(usize, 2), decoded.@"test".len);
    try std.testing.expectEqual(@as(i32, 1), decoded.@"align".get("left").?);
    try std.testing.expect(decoded.@"null");
    switch (decoded.async) {
        .await => |value| try std.testing.expectEqualStrings("ready", value),
        else => return error.UnexpectedOneof,
    }

    const json = try decoded.jsonStringifyAlloc(allocator);
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"type\":7") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"error\":\"keyword-safe\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"align\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"await\":\"ready\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"null\":true") != null);

    var json_roundtrip = try ids.@"type".jsonParseInitialized(allocator, json);
    defer json_roundtrip.deinit(allocator);
    try std.testing.expectEqual(@as(i32, 7), json_roundtrip.@"type");
    try std.testing.expectEqual(@as(i32, 2), json_roundtrip.@"align".get("right").?);
    switch (json_roundtrip.async) {
        .await => |value| try std.testing.expectEqualStrings("ready", value),
        else => return error.UnexpectedOneof,
    }

    const text = try decoded.formatTextAlloc(allocator);
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "type: 7") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "error: \"keyword-safe\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "await: \"ready\"") != null);

    var text_roundtrip = try ids.@"type".parseTextInitialized(allocator, text);
    defer text_roundtrip.deinit(allocator);
    try std.testing.expectEqual(@as(i32, 7), text_roundtrip.@"type");
    switch (text_roundtrip.async) {
        .await => |value| try std.testing.expectEqualStrings("ready", value),
        else => return error.UnexpectedOneof,
    }

    text_roundtrip.async = .{ .@"opaque" = 99 };
    const opaque_bytes = try text_roundtrip.encodeInitialized(allocator);
    defer allocator.free(opaque_bytes);
    var decoded_opaque = try ids.@"type".decodeOwnedInitialized(allocator, opaque_bytes);
    defer decoded_opaque.deinit(allocator);
    switch (decoded_opaque.async) {
        .@"opaque" => |value| try std.testing.expectEqual(@as(i32, 99), value),
        else => return error.UnexpectedOneof,
    }
}

comptime {
    _ = pbz;
}
