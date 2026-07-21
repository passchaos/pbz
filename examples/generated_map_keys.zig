const std = @import("std");
const pbz = @import("pbz");
const map_keys_pb = @import("generated/map_keys.pb.zig");

const mapkeys = map_keys_pb.demo.mapkeys;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Protobuf JSON object keys are strings even when the map key type is a
    // numeric or bool scalar. Generated maps should keep typed Zig keys while
    // accepting/emitting the protobuf JSON string representation.
    var msg = mapkeys.MapKeys.init();
    defer msg.deinit(allocator);
    try msg.by_int.put(allocator, -7, "minus-seven");
    try msg.by_int.put(allocator, 42, "answer");
    try msg.by_bool.put(allocator, false, 0);
    try msg.by_bool.put(allocator, true, 1);
    try msg.by_i64.put(allocator, -9_007_199_254_740_993, "min-safe-minus-one");
    try msg.by_u64.put(allocator, 18_446_744_073_709_551_615, "max-u64");

    const bytes = try msg.encodeInitialized(allocator);
    defer allocator.free(bytes);
    var decoded = try mapkeys.MapKeys.decodeOwnedInitialized(allocator, bytes);
    defer decoded.deinit(allocator);
    try std.testing.expectEqualStrings("minus-seven", decoded.by_int.get(-7).?);
    try std.testing.expectEqual(@as(i32, 1), decoded.by_bool.get(true).?);
    try std.testing.expectEqualStrings("min-safe-minus-one", decoded.by_i64.get(-9_007_199_254_740_993).?);
    try std.testing.expectEqualStrings("max-u64", decoded.by_u64.get(18_446_744_073_709_551_615).?);

    const deterministic = try decoded.encodeDeterministicInitialized(allocator);
    defer allocator.free(deterministic);
    var deterministic_roundtrip = try mapkeys.MapKeys.decodeOwnedInitialized(allocator, deterministic);
    defer deterministic_roundtrip.deinit(allocator);
    try std.testing.expectEqualStrings("answer", deterministic_roundtrip.by_int.get(42).?);

    const json = try decoded.jsonStringifyAlloc(allocator);
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"-7\":\"minus-seven\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"true\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"false\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"-9007199254740993\":\"min-safe-minus-one\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"18446744073709551615\":\"max-u64\"") != null);

    var json_roundtrip = try mapkeys.MapKeys.jsonParseInitialized(allocator, json);
    defer json_roundtrip.deinit(allocator);
    try std.testing.expectEqualStrings("minus-seven", json_roundtrip.by_int.get(-7).?);
    try std.testing.expectEqual(@as(i32, 1), json_roundtrip.by_bool.get(true).?);
    try std.testing.expectEqualStrings("max-u64", json_roundtrip.by_u64.get(18_446_744_073_709_551_615).?);

    var proto_name_json = try mapkeys.MapKeys.jsonParseInitialized(
        allocator,
        "{\"by_int\":{\"42\":\"answer\"},\"by_bool\":{\"true\":1},\"by_i64\":{\"-9007199254740993\":\"wide\"},\"by_u64\":{\"18446744073709551615\":\"max\"}}",
    );
    defer proto_name_json.deinit(allocator);
    try std.testing.expectEqualStrings("answer", proto_name_json.by_int.get(42).?);
    try std.testing.expectEqual(@as(i32, 1), proto_name_json.by_bool.get(true).?);
    try std.testing.expectEqualStrings("wide", proto_name_json.by_i64.get(-9_007_199_254_740_993).?);

    const text = try decoded.formatTextAlloc(allocator);
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "by_int {") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "key: -7") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "key: true") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "18446744073709551615") != null);

    var text_roundtrip = try mapkeys.MapKeys.parseTextInitialized(allocator, text);
    defer text_roundtrip.deinit(allocator);
    try std.testing.expectEqualStrings("minus-seven", text_roundtrip.by_int.get(-7).?);
    try std.testing.expectEqual(@as(i32, 0), text_roundtrip.by_bool.get(false).?);
}

comptime {
    _ = pbz;
}
