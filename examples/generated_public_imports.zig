const std = @import("std");
const pbz = @import("pbz");
const app_pb = @import("generated/public_app.pb.zig");

const app = app_pb.demo.publics.app;
const mid = app_pb.imports.public_mid_proto.demo.publics.mid;
const leaf = app_pb.imports.public_mid_proto.imports.public_leaf_proto.demo.publics.leaf;

fn makeLeaf(id: i32, name: []const u8) leaf.Leaf {
    var out = leaf.Leaf.init();
    out.id = id;
    out.name = name;
    return out;
}

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // `import public` lets a file re-export symbols from another dependency.
    // The generated module should follow that public import chain so App can
    // reference Leaf through public_mid.proto without importing public_leaf.proto
    // directly, matching protoc/C++ visibility semantics.
    std.debug.assert(std.mem.eql(u8, app_pb.imports.public_mid_proto_kind, "normal"));
    std.debug.assert(std.mem.eql(u8, app_pb.imports.public_mid_proto.imports.public_leaf_proto_kind, "public"));
    std.debug.assert(app.App.direct_leaf_field.has_type_ref);
    std.debug.assert(app.App.direct_leaf_field.type_ref == leaf.Leaf);
    std.debug.assert(app.App.mid_field.type_ref == mid.Mid);

    var message = app.App.init();
    defer message.deinit(allocator);
    message.direct_leaf = try makeLeaf(7, "direct").cloneOwned(allocator);
    var mid_value = mid.Mid.init();
    defer mid_value.deinit(allocator);
    mid_value.leaf = try makeLeaf(8, "via-mid").cloneOwned(allocator);
    message.mid = try mid_value.cloneOwned(allocator);

    const bytes = try message.encodeInitialized(allocator);
    defer allocator.free(bytes);
    var decoded = try app.App.decodeOwnedInitialized(allocator, bytes);
    defer decoded.deinit(allocator);
    try std.testing.expectEqual(@as(i32, 7), decoded.direct_leaf.?.id);
    try std.testing.expectEqualStrings("direct", decoded.direct_leaf.?.name);
    try std.testing.expectEqual(@as(i32, 8), decoded.mid.?.leaf.?.id);
    try std.testing.expectEqualStrings("via-mid", decoded.mid.?.leaf.?.name);

    const json = try decoded.jsonStringifyAlloc(allocator);
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"directLeaf\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"mid\":") != null);
    var json_roundtrip = try app.App.jsonParseInitialized(allocator, json);
    defer json_roundtrip.deinit(allocator);
    try std.testing.expectEqual(@as(i32, 7), json_roundtrip.direct_leaf.?.id);
    try std.testing.expectEqual(@as(i32, 8), json_roundtrip.mid.?.leaf.?.id);

    var proto_name_json = try app.App.jsonParseInitialized(
        allocator,
        "{\"direct_leaf\":{\"id\":9,\"name\":\"proto\"},\"mid\":{\"leaf\":{\"id\":10,\"name\":\"nested\"}}}",
    );
    defer proto_name_json.deinit(allocator);
    try std.testing.expectEqual(@as(i32, 9), proto_name_json.direct_leaf.?.id);
    try std.testing.expectEqual(@as(i32, 10), proto_name_json.mid.?.leaf.?.id);

    const text = try decoded.formatTextAlloc(allocator);
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "direct_leaf {") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "via-mid") != null);
    var text_roundtrip = try app.App.parseTextInitialized(allocator, text);
    defer text_roundtrip.deinit(allocator);
    try std.testing.expectEqual(@as(i32, 7), text_roundtrip.direct_leaf.?.id);
    try std.testing.expectEqual(@as(i32, 8), text_roundtrip.mid.?.leaf.?.id);
}

comptime {
    _ = pbz;
}
