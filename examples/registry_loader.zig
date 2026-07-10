const std = @import("std");
const pbz = @import("pbz");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var tree = pbz.MemorySourceTree.init(allocator);
    defer tree.deinit();
    try tree.add("common.proto",
        \\syntax = "proto3";
        \\package demo.common;
        \\message User { int32 id = 1; }
    );
    try tree.add("app.proto",
        \\syntax = "proto3";
        \\package demo.app;
        \\import "common.proto";
        \\message Event { demo.common.User user = 1; }
    );

    var loaded = try pbz.loadMemory(allocator, &tree, "app.proto");
    defer loaded.deinit();

    const event_desc = loaded.registry.findMessage(".demo.app.Event", null).?;
    const user_desc = loaded.registry.findMessage(".demo.common.User", null).?;
    std.debug.assert(std.mem.eql(u8, event_desc.name, "Event"));
    std.debug.assert(std.mem.eql(u8, user_desc.name, "User"));
}
