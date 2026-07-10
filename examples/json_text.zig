const std = @import("std");
const pbz = @import("pbz");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var file = try pbz.ProtoParser.parse(allocator,
        \\syntax = "proto3";
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message Child { string label = 1; }
        \\message Bag {
        \\  int32 id = 1;
        \\  repeated string tags = 2;
        \\  map<string, int32> counts = 3;
        \\  Child child = 4;
        \\  Kind kind = 5;
        \\}
    );
    defer file.deinit();

    const bag_desc = file.findMessage("Bag").?;
    var bag = try pbz.parseJsonAlloc(allocator, &file, bag_desc,
        \\{"id":7,"tags":["a","b"],"counts":{"red":3},"child":{"label":"kid"},"kind":"ADMIN"}
    , .{});
    defer bag.deinit();

    const json = try pbz.stringifyJsonAlloc(allocator, &file, &bag, .{
        .enum_as_name = true,
        .always_print_primitive_fields = true,
    });
    defer allocator.free(json);
    std.debug.assert(std.mem.indexOf(u8, json, "\"kind\":\"ADMIN\"") != null);

    const text = try pbz.formatTextAlloc(allocator, &file, &bag, .{ .indent = "  " });
    defer allocator.free(text);
    std.debug.assert(std.mem.indexOf(u8, text, "kind: ADMIN") != null);

    var from_text = try pbz.parseTextAlloc(allocator, &file, bag_desc, text);
    defer from_text.deinit();
    std.debug.assert(from_text.has(bag_desc.findField("child").?));
}
