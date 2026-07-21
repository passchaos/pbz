const std = @import("std");
const pbz = @import("pbz");
const json_names_pb = @import("generated/json_names.pb.zig");

const jsonnames = json_names_pb.demo.jsonnames;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Explicit json_name is a compatibility surface used by protoc-generated
    // C++ APIs and JSON bridges. Generated Zig should emit that custom spelling
    // by default, accept both proto and JSON names on input, and keep TextFormat
    // aligned with protobuf field names.
    std.debug.assert(std.mem.eql(u8, jsonnames.JsonNames.display_name_field.name, "display_name"));
    std.debug.assert(std.mem.eql(u8, jsonnames.JsonNames.display_name_field.json_name, "shownName"));
    std.debug.assert(std.mem.eql(u8, jsonnames.JsonNames.legacy_count_field.json_name, "legacy-count"));
    std.debug.assert(std.mem.eql(u8, jsonnames.JsonNames.same_name_field.json_name, "same_name"));

    var msg = jsonnames.JsonNames.init();
    defer msg.deinit(allocator);
    msg.display_name = "visible";
    msg.legacy_count = 17;
    msg.same_name = "proto-spelling";

    const json = try msg.jsonStringifyAlloc(allocator);
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"shownName\":\"visible\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"legacy-count\":17") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"same_name\":\"proto-spelling\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"display_name\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"legacy_count\"") == null);

    const proto_json = try msg.jsonStringifyAllocWithOptions(allocator, .{ .preserve_proto_field_names = true });
    defer allocator.free(proto_json);
    try std.testing.expect(std.mem.indexOf(u8, proto_json, "\"display_name\":\"visible\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, proto_json, "\"legacy_count\":17") != null);
    try std.testing.expect(std.mem.indexOf(u8, proto_json, "\"legacy-count\"") == null);

    var json_roundtrip = try jsonnames.JsonNames.jsonParseInitialized(allocator, json);
    defer json_roundtrip.deinit(allocator);
    try std.testing.expectEqualStrings("visible", json_roundtrip.display_name);
    try std.testing.expectEqual(@as(i32, 17), json_roundtrip.legacy_count);
    try std.testing.expectEqualStrings("proto-spelling", json_roundtrip.same_name);

    var proto_name_input = try jsonnames.JsonNames.jsonParseInitialized(
        allocator,
        "{\"display_name\":\"proto\",\"legacy_count\":18,\"same_name\":\"same\"}",
    );
    defer proto_name_input.deinit(allocator);
    try std.testing.expectEqualStrings("proto", proto_name_input.display_name);
    try std.testing.expectEqual(@as(i32, 18), proto_name_input.legacy_count);

    var mixed_input = try jsonnames.JsonNames.jsonParseInitialized(
        allocator,
        "{\"shownName\":\"custom\",\"legacy-count\":19,\"same_name\":\"same\"}",
    );
    defer mixed_input.deinit(allocator);
    try std.testing.expectEqualStrings("custom", mixed_input.display_name);
    try std.testing.expectEqual(@as(i32, 19), mixed_input.legacy_count);

    var null_reset = try jsonnames.JsonNames.jsonParseInitialized(
        allocator,
        "{\"shownName\":null,\"legacy-count\":null,\"same_name\":null}",
    );
    defer null_reset.deinit(allocator);
    try std.testing.expectEqualStrings("", null_reset.display_name);
    try std.testing.expectEqual(@as(i32, 0), null_reset.legacy_count);
    try std.testing.expectEqualStrings("", null_reset.same_name);

    const text = try msg.formatTextAlloc(allocator);
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "display_name: \"visible\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "legacy_count: 17") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "shownName") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "legacy-count") == null);

    var text_proto = try jsonnames.JsonNames.parseTextInitialized(allocator, text);
    defer text_proto.deinit(allocator);
    try std.testing.expectEqualStrings("visible", text_proto.display_name);
    try std.testing.expectEqual(@as(i32, 17), text_proto.legacy_count);

    var text_json_alias = try jsonnames.JsonNames.parseTextInitialized(
        allocator,
        "shownName: \"alias\"\nlegacy-count: 20\nsame_name: \"same\"\n",
    );
    defer text_json_alias.deinit(allocator);
    try std.testing.expectEqualStrings("alias", text_json_alias.display_name);
    try std.testing.expectEqual(@as(i32, 20), text_json_alias.legacy_count);
}

comptime {
    _ = pbz;
}
