const std = @import("std");
const pbz = @import("pbz");
const groups_pb = @import("generated/groups.pb.zig");

const groups = groups_pb.demo.groups;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Proto2 group fields are generated as concrete nested message structs.
    std.debug.assert(groups.Parent.box_field.has_type_ref);
    std.debug.assert(groups.Parent.box_field.type_ref == groups.Parent.Box);
    std.debug.assert(groups.Parent.item_field.type_ref == groups.Parent.Item);

    var box = groups.Parent.Box.init();
    defer box.deinit(allocator);
    box.label = "typed-box";
    box.has_label = true;

    var item = groups.Parent.Item.init();
    defer item.deinit(allocator);
    item.rank = 7;
    item.has_rank = true;

    var picked = groups.Parent.Box.init();
    defer picked.deinit(allocator);
    picked.label = "picked-box";
    picked.has_label = true;

    var parent = groups.Parent.init();
    defer parent.deinit(allocator);
    parent.id = 1;
    parent.has_id = true;
    parent.box = try box.cloneOwned(allocator);
    const items = try allocator.alloc(groups.Parent.Item, 1);
    items[0] = try item.cloneOwned(allocator);
    parent.item = items;
    parent.picked = .{ .picked_box = try picked.cloneOwned(allocator) };

    const bytes = try parent.encodeInitialized(allocator);
    defer allocator.free(bytes);

    var decoded = try groups.Parent.decodeOwnedInitialized(allocator, bytes);
    defer decoded.deinit(allocator);
    std.debug.assert(std.mem.eql(u8, decoded.box.?.label, "typed-box"));
    std.debug.assert(decoded.item.len == 1);
    std.debug.assert(decoded.item[0].rank == 7);
    switch (decoded.picked) {
        .picked_box => |selected| std.debug.assert(std.mem.eql(u8, selected.label, "picked-box")),
        else => return error.UnexpectedOneof,
    }

    const deterministic = try decoded.encodeDeterministicInitialized(allocator);
    defer allocator.free(deterministic);
    std.debug.assert(deterministic.len == bytes.len);

    const json = try decoded.jsonStringifyAllocWithOptions(allocator, .{ .preserve_proto_field_names = true });
    defer allocator.free(json);
    std.debug.assert(std.mem.indexOf(u8, json, "\"box\":") != null);
    std.debug.assert(std.mem.indexOf(u8, json, "\"item\":") != null);
    std.debug.assert(std.mem.indexOf(u8, json, "\"picked_box\":") != null);
    var json_roundtrip = try groups.Parent.jsonParseInitialized(allocator, json);
    defer json_roundtrip.deinit(allocator);
    std.debug.assert(std.mem.eql(u8, json_roundtrip.box.?.label, "typed-box"));

    const text = try decoded.formatTextAlloc(allocator);
    defer allocator.free(text);
    std.debug.assert(std.mem.indexOf(u8, text, "box {") != null);
    std.debug.assert(std.mem.indexOf(u8, text, "item {") != null);
    std.debug.assert(std.mem.indexOf(u8, text, "picked_box {") != null);
    var text_roundtrip = try groups.Parent.parseTextInitialized(allocator, text);
    defer text_roundtrip.deinit(allocator);
    std.debug.assert(text_roundtrip.item[0].rank == 7);
}

comptime {
    _ = pbz;
}
