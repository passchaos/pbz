const std = @import("std");
const pbz = @import("pbz");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var leaf = try pbz.ProtoParser.parse(allocator,
        \\syntax = "proto3";
        \\package demo.publics.leaf;
        \\message Leaf { int32 id = 1; string name = 2; }
    );
    defer leaf.deinit();
    leaf.name = "public_leaf.proto";

    var mid = try pbz.ProtoParser.parse(allocator,
        \\syntax = "proto3";
        \\package demo.publics.mid;
        \\import public "public_leaf.proto";
        \\message Mid { demo.publics.leaf.Leaf leaf = 1; }
    );
    defer mid.deinit();
    mid.name = "public_mid.proto";

    var app = try pbz.ProtoParser.parse(allocator,
        \\syntax = "proto3";
        \\package demo.publics.app;
        \\import "public_mid.proto";
        \\message App {
        \\  demo.publics.leaf.Leaf direct_leaf = 1;
        \\  demo.publics.mid.Mid mid = 2;
        \\}
    );
    defer app.deinit();
    app.name = "public_app.proto";

    var registry = pbz.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&leaf);
    try registry.addFile(&mid);
    try registry.addFile(&app);
    try registry.validateAllFileReferences();

    const app_desc = app.findMessage("App").?;
    const leaf_desc = registry.findMessageVisible(&app, "demo.publics.leaf.Leaf", "demo.publics.app") orelse return error.MissingPublicImport;
    const mid_desc = registry.findMessageVisible(&app, "demo.publics.mid.Mid", "demo.publics.app") orelse return error.MissingMid;

    var direct_leaf = pbz.DynamicMessage.init(allocator, leaf_desc);
    defer direct_leaf.deinit();
    try direct_leaf.add(leaf_desc.findField("id").?, .{ .int32 = 7 });
    try direct_leaf.add(leaf_desc.findField("name").?, .{ .string = try allocator.dupe(u8, "direct") });

    var nested_leaf = pbz.DynamicMessage.init(allocator, leaf_desc);
    defer nested_leaf.deinit();
    try nested_leaf.add(leaf_desc.findField("id").?, .{ .int32 = 8 });
    try nested_leaf.add(leaf_desc.findField("name").?, .{ .string = try allocator.dupe(u8, "via-mid") });

    const nested_leaf_bytes = try nested_leaf.encodedWithRegistry(&leaf, &registry);
    defer allocator.free(nested_leaf_bytes);
    const nested_leaf_value = try allocator.create(pbz.DynamicMessage);
    nested_leaf_value.* = pbz.DynamicMessage.init(allocator, leaf_desc);
    errdefer { nested_leaf_value.deinit(); allocator.destroy(nested_leaf_value); }
    try nested_leaf_value.decodeWithRegistry(&leaf, &registry, nested_leaf_bytes);
    var mid_msg = pbz.DynamicMessage.init(allocator, mid_desc);
    defer mid_msg.deinit();
    try mid_msg.add(mid_desc.findField("leaf").?, .{ .message = nested_leaf_value });

    const direct_leaf_bytes = try direct_leaf.encodedWithRegistry(&leaf, &registry);
    defer allocator.free(direct_leaf_bytes);
    const direct_leaf_value = try allocator.create(pbz.DynamicMessage);
    direct_leaf_value.* = pbz.DynamicMessage.init(allocator, leaf_desc);
    errdefer { direct_leaf_value.deinit(); allocator.destroy(direct_leaf_value); }
    try direct_leaf_value.decodeWithRegistry(&leaf, &registry, direct_leaf_bytes);

    const mid_bytes = try mid_msg.encodedWithRegistry(&mid, &registry);
    defer allocator.free(mid_bytes);
    const mid_value = try allocator.create(pbz.DynamicMessage);
    mid_value.* = pbz.DynamicMessage.init(allocator, mid_desc);
    errdefer { mid_value.deinit(); allocator.destroy(mid_value); }
    try mid_value.decodeWithRegistry(&mid, &registry, mid_bytes);

    var app_msg = pbz.DynamicMessage.init(allocator, app_desc);
    defer app_msg.deinit();
    try app_msg.add(app_desc.findField("direct_leaf").?, .{ .message = direct_leaf_value });
    try app_msg.add(app_desc.findField("mid").?, .{ .message = mid_value });

    const encoded = try app_msg.encodedWithRegistry(&app, &registry);
    defer allocator.free(encoded);
    var decoded = pbz.DynamicMessage.init(allocator, app_desc);
    defer decoded.deinit();
    try decoded.decodeWithRegistry(&app, &registry, encoded);
    const decoded_leaf = decoded.get("direct_leaf").?.values.items[0].message;
    try std.testing.expectEqual(@as(i32, 7), decoded_leaf.get("id").?.values.items[0].int32);

    const json = try pbz.stringifyJsonAllocWithRegistry(allocator, &app, &registry, &decoded, .{});
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "directLeaf") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "via-mid") != null);

    var json_roundtrip = try pbz.parseJsonAllocWithRegistry(allocator, &app, &registry, app_desc, json, .{});
    defer json_roundtrip.deinit();
    const roundtrip_mid = json_roundtrip.get("mid").?.values.items[0].message;
    const roundtrip_nested_leaf = roundtrip_mid.get("leaf").?.values.items[0].message;
    try std.testing.expectEqual(@as(i32, 8), roundtrip_nested_leaf.get("id").?.values.items[0].int32);
}
