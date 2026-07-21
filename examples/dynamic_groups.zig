const std = @import("std");
const pbz = @import("pbz");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var file = try pbz.ProtoParser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.dynamicgroups;
        \\message Parent {
        \\  optional int32 id = 1;
        \\  optional group Box = 2 {
        \\    optional int32 a = 3;
        \\    optional string label = 4;
        \\  }
        \\  repeated group Item = 5 {
        \\    optional int32 rank = 6;
        \\  }
        \\}
    );
    defer file.deinit();

    const parent_desc = file.findMessage("Parent") orelse return error.MissingDescriptor;
    const box_desc = parent_desc.findMessageDeep("Box") orelse return error.MissingDescriptor;
    const item_desc = parent_desc.findMessageDeep("Item") orelse return error.MissingDescriptor;
    const box_field = parent_desc.findField("box") orelse return error.MissingField;
    const item_field = parent_desc.findField("item") orelse return error.MissingField;

    var parent = pbz.DynamicMessage.init(allocator, parent_desc);
    defer parent.deinit();
    try parent.add(parent_desc.findField("id") orelse return error.MissingField, .{ .int32 = 7 });

    const box = try allocator.create(pbz.DynamicMessage);
    box.* = pbz.DynamicMessage.init(allocator, box_desc);
    errdefer {
        box.deinit();
        allocator.destroy(box);
    }
    try box.add(box_desc.findField("a") orelse return error.MissingField, .{ .int32 = 11 });
    try box.add(box_desc.findField("label") orelse return error.MissingField, .{ .string = try allocator.dupe(u8, "box") });
    try parent.add(box_field, .{ .group = box });

    const first_item = try allocator.create(pbz.DynamicMessage);
    first_item.* = pbz.DynamicMessage.init(allocator, item_desc);
    errdefer {
        first_item.deinit();
        allocator.destroy(first_item);
    }
    try first_item.add(item_desc.findField("rank") orelse return error.MissingField, .{ .int32 = 1 });
    try parent.add(item_field, .{ .group = first_item });

    const second_item = try allocator.create(pbz.DynamicMessage);
    second_item.* = pbz.DynamicMessage.init(allocator, item_desc);
    errdefer {
        second_item.deinit();
        allocator.destroy(second_item);
    }
    try second_item.add(item_desc.findField("rank") orelse return error.MissingField, .{ .int32 = 2 });
    try parent.add(item_field, .{ .group = second_item });

    const bytes = try parent.encodedInitialized(&file);
    defer allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, &.{0x13}) != null); // field 2 start_group
    try std.testing.expect(std.mem.indexOf(u8, bytes, &.{0x14}) != null); // field 2 end_group
    try std.testing.expect(std.mem.indexOf(u8, bytes, &.{0x2b}) != null); // field 5 start_group
    try std.testing.expect(std.mem.indexOf(u8, bytes, &.{0x2c}) != null); // field 5 end_group

    var decoded = pbz.DynamicMessage.init(allocator, parent_desc);
    defer decoded.deinit();
    try decoded.decodeInitialized(&file, bytes);
    const decoded_box = decoded.getByNumber(box_field.number).?.values.items[0].group;
    try std.testing.expectEqual(@as(i32, 11), decoded_box.get("a").?.values.items[0].int32);
    try std.testing.expectEqualStrings("box", decoded_box.get("label").?.values.items[0].string);
    const decoded_items = decoded.getByNumber(item_field.number).?.values.items;
    try std.testing.expectEqual(@as(usize, 2), decoded_items.len);
    try std.testing.expectEqual(@as(i32, 2), decoded_items[1].group.get("rank").?.values.items[0].int32);

    const json = try pbz.stringifyJsonAlloc(allocator, &file, &decoded, .{ .preserve_proto_field_names = true });
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"box\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"item\":") != null);
    var json_roundtrip = try pbz.parseJsonAlloc(allocator, &file, parent_desc, json, .{});
    defer json_roundtrip.deinit();
    try std.testing.expectEqual(@as(i32, 11), json_roundtrip.getByNumber(box_field.number).?.values.items[0].group.get("a").?.values.items[0].int32);

    const text = try pbz.formatTextAlloc(allocator, &file, &decoded, .{});
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Box {") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "Item {") != null);
    var text_roundtrip = try pbz.parseTextAlloc(allocator, &file, parent_desc,
        \\id: 8
        \\Box < a: 21 label: "parsed" >
        \\Item { rank: 3 }
        \\Item < rank: 4 >
    );
    defer text_roundtrip.deinit();
    try std.testing.expectEqual(@as(i32, 8), text_roundtrip.get("id").?.values.items[0].int32);
    try std.testing.expectEqual(@as(i32, 21), text_roundtrip.getByNumber(box_field.number).?.values.items[0].group.get("a").?.values.items[0].int32);
    try std.testing.expectEqual(@as(i32, 4), text_roundtrip.getByNumber(item_field.number).?.values.items[1].group.get("rank").?.values.items[0].int32);

    // Singular groups merge exactly like singular messages when they appear
    // repeatedly on the wire.
    var merged_wire = pbz.Writer.init(allocator);
    defer merged_wire.deinit();
    try merged_wire.writeTag(2, .start_group);
    try merged_wire.writeInt32(3, 100);
    try merged_wire.writeTag(2, .end_group);
    try merged_wire.writeTag(2, .start_group);
    try merged_wire.writeString(4, "merged");
    try merged_wire.writeTag(2, .end_group);
    var merged = pbz.DynamicMessage.init(allocator, parent_desc);
    defer merged.deinit();
    try merged.decode(&file, merged_wire.slice());
    const merged_box = merged.getByNumber(box_field.number).?.values.items[0].group;
    try std.testing.expectEqual(@as(i32, 100), merged_box.get("a").?.values.items[0].int32);
    try std.testing.expectEqualStrings("merged", merged_box.get("label").?.values.items[0].string);

    var unknown_wire = pbz.Writer.init(allocator);
    defer unknown_wire.deinit();
    try unknown_wire.writeTag(100, .start_group);
    try unknown_wire.writeInt32(1, 9);
    try unknown_wire.writeTag(100, .end_group);
    var unknown_decoded = pbz.DynamicMessage.init(allocator, parent_desc);
    defer unknown_decoded.deinit();
    try unknown_decoded.decode(&file, unknown_wire.slice());
    try std.testing.expectEqual(@as(usize, 1), unknown_decoded.unknownFieldCountByNumber(100));
}

comptime {
    _ = pbz;
}
