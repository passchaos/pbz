const std = @import("std");
const pbz = @import("pbz");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var file = try pbz.ProtoParser.parse(allocator,
        \\syntax = "proto3";
        \\package demo.textopts;
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message Child { string label = 1; }
        \\message Bag {
        \\  int32 id = 1;
        \\  Kind kind = 2;
        \\  Child child = 3;
        \\}
    );
    defer file.deinit();
    const bag_desc = file.findMessage("Bag") orelse return error.MissingDescriptor;
    const child_desc = file.findMessage("Child") orelse return error.MissingDescriptor;

    const child = try allocator.create(pbz.DynamicMessage);
    var owns_child = true;
    errdefer if (owns_child) {
        child.deinit();
        allocator.destroy(child);
    };
    child.* = pbz.DynamicMessage.init(allocator, child_desc);
    try child.add(child_desc.findField("label") orelse return error.MissingField, .{ .string = try allocator.dupe(u8, "kid") });

    var bag = pbz.DynamicMessage.init(allocator, bag_desc);
    defer bag.deinit();
    try bag.add(bag_desc.findField("id") orelse return error.MissingField, .{ .int32 = 7 });
    try bag.add(bag_desc.findField("kind") orelse return error.MissingField, .{ .enumeration = 1 });
    try bag.add(bag_desc.findField("child") orelse return error.MissingField, .{ .message = child });
    owns_child = false;

    var unknown_100 = pbz.Writer.init(allocator);
    defer unknown_100.deinit();
    try unknown_100.writeUInt32(100, 1);
    try bag.appendUnknownRaw(unknown_100.slice());
    var unknown_101 = pbz.Writer.init(allocator);
    defer unknown_101.deinit();
    try unknown_101.writeString(101, "raw");
    try bag.appendUnknownRaw(unknown_101.slice());

    const default_text = try pbz.formatTextAlloc(allocator, &file, &bag, .{});
    defer allocator.free(default_text);
    try std.testing.expect(std.mem.indexOf(u8, default_text, "kind: ADMIN") != null);
    try std.testing.expect(std.mem.indexOf(u8, default_text, "100:") == null);

    const numeric_enum_text = try pbz.formatTextAlloc(allocator, &file, &bag, .{ .enum_as_name = false });
    defer allocator.free(numeric_enum_text);
    try std.testing.expect(std.mem.indexOf(u8, numeric_enum_text, "kind: 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, numeric_enum_text, "ADMIN") == null);

    const custom_indent_text = try pbz.formatTextAlloc(allocator, &file, &bag, .{ .indent = "    " });
    defer allocator.free(custom_indent_text);
    try std.testing.expect(std.mem.indexOf(u8, custom_indent_text, "child {\n    label: \"kid\"") != null);

    const unknown_text = try pbz.formatTextAlloc(allocator, &file, &bag, .{ .print_unknown_fields = true });
    defer allocator.free(unknown_text);
    try std.testing.expect(std.mem.indexOf(u8, unknown_text, "100: 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, unknown_text, "101: \"raw\"") != null);

    var parsed_numeric = try pbz.parseTextAlloc(allocator, &file, bag_desc,
        \\id: 8
        \\kind: 1
        \\child { label: "parsed" }
    );
    defer parsed_numeric.deinit();
    try std.testing.expectEqual(@as(i32, 1), parsed_numeric.get("kind").?.values.items[0].enumeration);
    try std.testing.expectEqualStrings("parsed", parsed_numeric.get("child").?.values.items[0].message.get("label").?.values.items[0].string);
}

comptime {
    _ = pbz;
}
