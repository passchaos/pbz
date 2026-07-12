const std = @import("std");
const pbz = @import("pbz");

const default_descriptor_env = "PBZ_CONFORMANCE_DESCRIPTOR_SET";

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var arg_it = init.minimal.args.iterate();
    _ = arg_it.next();
    var descriptor_path: ?[]const u8 = null;
    while (arg_it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--descriptor_set") or std.mem.eql(u8, arg, "--descriptor-set")) {
            descriptor_path = arg_it.next() orelse return error.MissingDescriptorSetPath;
        } else if (std.mem.startsWith(u8, arg, "--descriptor_set=")) {
            descriptor_path = arg["--descriptor_set=".len..];
        } else if (std.mem.startsWith(u8, arg, "--descriptor-set=")) {
            descriptor_path = arg["--descriptor-set=".len..];
        } else if (std.mem.eql(u8, arg, "--help")) {
            try printUsage(io);
            return;
        }
    }
    if (descriptor_path == null) descriptor_path = init.environ_map.get(default_descriptor_env);

    const path = descriptor_path orelse {
        try printUsage(io);
        return error.MissingDescriptorSetPath;
    };

    var descriptor_file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer descriptor_file.close(io);
    var file_reader_buffer: [16 * 1024]u8 = undefined;
    var file_reader = descriptor_file.reader(io, &file_reader_buffer);
    const descriptor_bytes = try file_reader.interface.allocRemaining(allocator, .limited(256 * 1024 * 1024));
    defer allocator.free(descriptor_bytes);

    const files = try pbz.decodeFileDescriptorSet(allocator, descriptor_bytes);
    defer {
        for (files) |*file| file.deinit();
        allocator.free(files);
    }

    var registry = pbz.Registry.init(allocator);
    defer registry.deinit();
    for (files) |*file| try registry.addFile(file);

    var stdin_buffer: [16 * 1024]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().readerStreaming(io, &stdin_buffer);
    var stdout_buffer: [16 * 1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writerStreaming(io, &stdout_buffer);
    defer stdout_writer.interface.flush() catch {};

    while (true) {
        const len = stdin_reader.interface.takeInt(u32, .little) catch |err| switch (err) {
            error.EndOfStream => return,
            else => return err,
        };
        const request_bytes = try stdin_reader.interface.readAlloc(allocator, len);
        defer allocator.free(request_bytes);

        const request = try pbz.ConformanceRequest.decode(request_bytes);
        const response = try pbz.runConformanceDynamic(allocator, &registry, request);
        defer allocator.free(response);

        try stdout_writer.interface.writeInt(u32, @intCast(response.len), .little);
        try stdout_writer.interface.writeAll(response);
        try stdout_writer.interface.flush();
    }
}

fn printUsage(io: std.Io) !void {
    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writerStreaming(io, &stderr_buffer);
    defer stderr_writer.interface.flush() catch {};
    try stderr_writer.interface.writeAll(
        \\usage: pbz-conformance --descriptor_set FILE
        \\
        \\Implements the protobuf conformance subprocess protocol. The descriptor
        \\set must contain the message types referenced by ConformanceRequest.
        \\The descriptor set may also be supplied with PBZ_CONFORMANCE_DESCRIPTOR_SET.
        \\
    );
}
