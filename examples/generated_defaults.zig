const std = @import("std");
const pbz = @import("pbz");
const defaults_pb = @import("generated/defaults.pb.zig");

const defaults = defaults_pb.demo.defaults;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Proto2 defaults are read values, not implicit wire presence. A freshly
    // initialized generated message exposes the schema defaults while every
    // has_* bit remains false, matching protobuf's partial-message semantics.
    var msg = defaults.Defaults.init();
    defer msg.deinit(allocator);
    try std.testing.expectEqual(@as(i32, 42), msg.count);
    try std.testing.expect(!msg.has_count);
    try std.testing.expectEqual(@as(u64, std.math.maxInt(u64)), msg.max_count);
    try std.testing.expect(!msg.has_max_count);
    try std.testing.expect(msg.enabled);
    try std.testing.expectEqualStrings("hello\nzig", msg.label);
    try std.testing.expectEqualSlices(u8, &.{ 0x01, 0x02 }, msg.raw);
    try std.testing.expectEqual(defaults.Mode.MODE_BETA.toInt(), msg.mode);
    try std.testing.expect(std.math.isPositiveInf(msg.ratio));
    try std.testing.expect(std.math.isNegativeInf(msg.neg_ratio));
    try std.testing.expectEqual(@as(usize, 0), msg.encodedSize());

    const empty_bytes = try msg.encode(allocator);
    defer allocator.free(empty_bytes);
    try std.testing.expectEqual(@as(usize, 0), empty_bytes.len);

    const empty_json = try msg.jsonStringifyAlloc(allocator);
    defer allocator.free(empty_json);
    try std.testing.expectEqualStrings("{}", empty_json);

    const default_json = try msg.jsonStringifyAllocWithOptions(allocator, .{ .always_print_primitive_fields = true });
    defer allocator.free(default_json);
    try std.testing.expect(std.mem.indexOf(u8, default_json, "\"count\":42") != null);
    try std.testing.expect(std.mem.indexOf(u8, default_json, "\"maxCount\":\"18446744073709551615\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, default_json, "\"enabled\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, default_json, "\"label\":\"hello\\nzig\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, default_json, "\"raw\":\"AQI=\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, default_json, "\"mode\":\"MODE_BETA\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, default_json, "\"ratio\":\"Infinity\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, default_json, "\"negRatio\":\"-Infinity\"") != null);

    var parsed_empty = try defaults.Defaults.jsonParse(allocator, "{}");
    defer parsed_empty.deinit(allocator);
    try std.testing.expectEqual(@as(i32, 42), parsed_empty.count);
    try std.testing.expect(!parsed_empty.has_count);

    var parsed_null = try defaults.Defaults.jsonParse(allocator, "{\"count\":null,\"maxCount\":null,\"enabled\":null,\"label\":null,\"raw\":null,\"mode\":null,\"ratio\":null,\"negRatio\":null}");
    defer parsed_null.deinit(allocator);
    try std.testing.expectEqual(@as(i32, 42), parsed_null.count);
    try std.testing.expect(!parsed_null.has_count);
    try std.testing.expectEqual(@as(u64, std.math.maxInt(u64)), parsed_null.max_count);
    try std.testing.expect(!parsed_null.has_max_count);
    try std.testing.expect(parsed_null.enabled);
    try std.testing.expect(!parsed_null.has_enabled);
    try std.testing.expectEqualStrings("hello\nzig", parsed_null.label);
    try std.testing.expect(!parsed_null.has_label);
    try std.testing.expectEqual(defaults.Mode.MODE_BETA.toInt(), parsed_null.mode);
    try std.testing.expect(!parsed_null.has_mode);
    try std.testing.expect(std.math.isPositiveInf(parsed_null.ratio));
    try std.testing.expect(!parsed_null.has_ratio);
    try std.testing.expect(std.math.isNegativeInf(parsed_null.neg_ratio));
    try std.testing.expect(!parsed_null.has_neg_ratio);

    var explicit = defaults.Defaults.init();
    defer explicit.deinit(allocator);
    explicit.count = 7;
    explicit.has_count = true;
    explicit.max_count = 9;
    explicit.has_max_count = true;
    explicit.enabled = false;
    explicit.has_enabled = true;
    explicit.label = "set";
    explicit.has_label = true;
    explicit.raw = "abc";
    explicit.has_raw = true;
    explicit.mode = defaults.Mode.MODE_ALPHA.toInt();
    explicit.has_mode = true;
    explicit.ratio = 1.5;
    explicit.has_ratio = true;
    explicit.neg_ratio = -2.5;
    explicit.has_neg_ratio = true;

    const explicit_bytes = try explicit.encode(allocator);
    defer allocator.free(explicit_bytes);
    try std.testing.expect(explicit_bytes.len != 0);

    var decoded = try defaults.Defaults.decodeOwned(allocator, explicit_bytes);
    defer decoded.deinit(allocator);
    try std.testing.expectEqual(@as(i32, 7), decoded.count);
    try std.testing.expect(decoded.has_count);
    try std.testing.expectEqual(@as(u64, 9), decoded.max_count);
    try std.testing.expect(decoded.has_max_count);
    try std.testing.expect(!decoded.enabled);
    try std.testing.expect(decoded.has_enabled);
    try std.testing.expectEqualStrings("set", decoded.label);
    try std.testing.expect(decoded.has_label);
    try std.testing.expectEqualSlices(u8, "abc", decoded.raw);
    try std.testing.expect(decoded.has_raw);
    try std.testing.expectEqual(defaults.Mode.MODE_ALPHA.toInt(), decoded.mode);
    try std.testing.expect(decoded.has_mode);
    try std.testing.expectEqual(@as(f32, 1.5), decoded.ratio);
    try std.testing.expect(decoded.has_ratio);
    try std.testing.expectEqual(@as(f64, -2.5), decoded.neg_ratio);
    try std.testing.expect(decoded.has_neg_ratio);

    const text = try explicit.formatTextAlloc(allocator);
    defer allocator.free(text);
    var text_roundtrip = try defaults.Defaults.parseText(allocator, text);
    defer text_roundtrip.deinit(allocator);
    try std.testing.expectEqual(@as(i32, 7), text_roundtrip.count);
    try std.testing.expect(text_roundtrip.has_count);
    try std.testing.expectEqual(defaults.Mode.MODE_ALPHA.toInt(), text_roundtrip.mode);
    try std.testing.expect(text_roundtrip.has_mode);
}

comptime {
    _ = pbz;
}
