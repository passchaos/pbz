const std = @import("std");
const pbz = @import("pbz");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var file = try pbz.ProtoParser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host { extensions 100 to max; }
        \\extend Host { optional int32 priority = 100; }
    );
    defer file.deinit();

    var registry = pbz.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);

    const host_desc = file.findMessage("Host").?;
    var host = try pbz.parseTextAllocWithRegistry(
        allocator,
        &file,
        &registry,
        host_desc,
        "[demo.priority]: 5\n",
    );
    defer host.deinit();

    const priority_ext = registry.findExtension("demo.Host", 100).?;
    std.debug.assert(host.getByNumber(priority_ext.number).?.values.items[0].int32 == 5);

    const host_json = try pbz.stringifyJsonAllocWithRegistry(allocator, &file, &registry, &host, .{});
    defer allocator.free(host_json);
    std.debug.assert(std.mem.indexOf(u8, host_json, "[demo.priority]") != null);
}
