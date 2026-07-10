const std = @import("std");
const pbz = @import("pbz");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var file = try pbz.ProtoParser.parse(allocator,
        \\syntax = "proto3";
        \\package demo;
        \\message Event { int32 id = 1; }
    );
    defer file.deinit();

    var registry = pbz.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);

    const response = try pbz.runConformanceDynamic(allocator, &registry, .{
        .payload = .{ .json_payload = "{\"id\":7}" },
        .requested_output_format = .protobuf,
        .message_type = "demo.Event",
        .test_category = .json_test,
    });
    defer allocator.free(response);

    var reader = pbz.Reader.init(response);
    const tag = (try reader.nextTag()).?;
    std.debug.assert(tag.number == 3); // ConformanceResponse.protobuf_payload
    std.debug.assert((try reader.readBytes()).len != 0);
}
