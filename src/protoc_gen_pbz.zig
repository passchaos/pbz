const std = @import("std");
const pbz = @import("pbz");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const io = std.Io.Threaded.global_single_threaded.io();
    var stdin_buffer: [16 * 1024]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().readerStreaming(io, &stdin_buffer);
    const request_bytes = try stdin_reader.interface.allocRemaining(allocator, .limited(64 * 1024 * 1024));
    defer allocator.free(request_bytes);

    var stdout_buffer: [16 * 1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writerStreaming(io, &stdout_buffer);
    try pbz.runPluginRequestBytes(allocator, request_bytes, &stdout_writer.interface);
    try stdout_writer.interface.flush();
}
