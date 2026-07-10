const std = @import("std");
const pbz = @import("pbz");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var file = try pbz.ProtoParser.parse(allocator,
        \\syntax = "proto3";
        \\message Event {
        \\  int32 id = 1;
        \\  repeated string tags = 2;
        \\  map<string, int32> counts = 3;
        \\  oneof payload { string note = 4; bytes raw = 5; }
        \\}
    );
    defer file.deinit();

    const event_desc = file.findMessage("Event").?;
    var event = pbz.DynamicMessage.init(allocator, event_desc);
    defer event.deinit();

    try event.add(event_desc.findField("id").?, .{ .int32 = 7 });
    try event.add(event_desc.findField("tags").?, .{ .string = try allocator.dupe(u8, "zig") });
    try event.add(event_desc.findField("note").?, .{ .string = try allocator.dupe(u8, "hello") });

    const first_count = try allocator.create(pbz.dynamic.MapEntry);
    first_count.* = .{
        .key = .{ .string = try allocator.dupe(u8, "red") },
        .value = .{ .int32 = 1 },
    };
    try event.add(event_desc.findField("counts").?, .{ .map_entry = first_count });

    // Adding the same key replaces the previous value (last value wins).
    const replacement_count = try allocator.create(pbz.dynamic.MapEntry);
    replacement_count.* = .{
        .key = .{ .string = try allocator.dupe(u8, "red") },
        .value = .{ .int32 = 9 },
    };
    try event.add(event_desc.findField("counts").?, .{ .map_entry = replacement_count });
    std.debug.assert(event.get("counts").?.values.items.len == 1);
    std.debug.assert(event.get("counts").?.values.items[0].map_entry.value.int32 == 9);

    const encoded = try event.encodedDeterministic(&file);
    defer allocator.free(encoded);

    var decoded = pbz.DynamicMessage.init(allocator, event_desc);
    defer decoded.deinit();
    try decoded.decode(&file, encoded);
    std.debug.assert(decoded.has(event_desc.findField("id").?));
}
