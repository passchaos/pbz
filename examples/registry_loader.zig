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
        \\service Events { rpc Get (Event) returns (Event); }
    );

    var loaded = try pbz.loadMemory(allocator, &tree, "app.proto");
    defer loaded.deinit();

    const event_desc = loaded.registry.findMessage(".demo.app.Event", null).?;
    const user_desc = loaded.registry.findMessage(".demo.common.User", null).?;
    const events_service = loaded.registry.findService(".demo.app.Events", null).?;
    std.debug.assert(std.mem.eql(u8, event_desc.name, "Event"));
    std.debug.assert(std.mem.eql(u8, user_desc.name, "User"));
    std.debug.assert(std.mem.eql(u8, events_service.methods.items[0].name, "Get"));

    // The filesystem loader follows the same recursive import and registry
    // validation path as MemorySourceTree, but exercises the public loadDir API
    // used by build tools that already have an open source directory handle.
    const io = std.Io.Threaded.global_single_threaded.io();
    const tmp_name = ".pbz-registry-loader-example";
    const cwd = std.Io.Dir.cwd();
    cwd.deleteTree(io, tmp_name) catch {};
    var tmp_dir = try cwd.createDirPathOpen(io, tmp_name, .{});
    defer {
        tmp_dir.close(io);
        cwd.deleteTree(io, tmp_name) catch {};
    }
    try tmp_dir.writeFile(io, .{ .sub_path = "shared.proto", .data =
        \\syntax = "proto3";
        \\package fs.shared;
        \\message Payload { string label = 1; }
    });
    try tmp_dir.writeFile(io, .{ .sub_path = "root.proto", .data =
        \\syntax = "proto3";
        \\package fs.root;
        \\import "shared.proto";
        \\message Envelope { fs.shared.Payload payload = 1; }
    });

    var fs_loaded = try pbz.loadDir(allocator, tmp_dir, "root.proto");
    defer fs_loaded.deinit();
    const envelope_desc = fs_loaded.registry.findMessage(".fs.root.Envelope", null).?;
    const payload_desc = fs_loaded.registry.findMessage(".fs.shared.Payload", null).?;
    std.debug.assert(envelope_desc.findField("payload").?.kind.message.len != 0);

    const payload_ptr = try allocator.create(pbz.DynamicMessage);
    payload_ptr.* = pbz.DynamicMessage.init(allocator, payload_desc);
    errdefer {
        payload_ptr.deinit();
        allocator.destroy(payload_ptr);
    }
    try payload_ptr.add(payload_desc.findField("label").?, .{ .string = try allocator.dupe(u8, "from-dir") });
    var envelope = pbz.DynamicMessage.init(allocator, envelope_desc);
    defer envelope.deinit();
    try envelope.add(envelope_desc.findField("payload").?, .{ .message = payload_ptr });

    const root_file = fs_loaded.registry.findFile("root.proto").?;
    const json = try pbz.stringifyJsonAllocWithRegistry(allocator, root_file, &fs_loaded.registry, &envelope, .{});
    defer allocator.free(json);
    std.debug.assert(std.mem.indexOf(u8, json, "\"from-dir\"") != null);
}
