pub const std = @import("std");
pub const pbz = @import("pbz");
pub const person_pb = @import("person_pb");
pub const root = @import("pbz_bench.zig");

pub const DynamicLargeMapEncodeCtx = struct { message: *const pbz.DynamicMessage, file: *const pbz.FileDescriptor };

pub fn dynamicLargeMapEncode(ctx: DynamicLargeMapEncodeCtx) !void {
    const bytes = try ctx.message.encoded(ctx.file);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.message.allocator.free(bytes);
}

pub const DynamicLargeMapDecodeCtx = struct { allocator: std.mem.Allocator, descriptor: *const pbz.MessageDescriptor, file: *const pbz.FileDescriptor, bytes: []const u8 };

pub fn dynamicLargeMapDecode(ctx: DynamicLargeMapDecodeCtx) !void {
    var msg = pbz.DynamicMessage.init(ctx.allocator, ctx.descriptor);
    defer msg.deinit();
    try msg.decode(ctx.file, ctx.bytes);
    std.mem.doNotOptimizeAway(&msg);
}

pub const DynamicEncodeCtx = struct { message: *const pbz.DynamicMessage, file: *const pbz.FileDescriptor };

pub fn dynamicEncode(ctx: DynamicEncodeCtx) !void {
    const bytes = try ctx.message.encoded(ctx.file);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.message.allocator.free(bytes);
}

pub const DynamicDecodeCtx = struct { allocator: std.mem.Allocator, descriptor: *const pbz.MessageDescriptor, file: *const pbz.FileDescriptor, bytes: []const u8 };

pub fn dynamicDecode(ctx: DynamicDecodeCtx) !void {
    var msg = pbz.DynamicMessage.init(ctx.allocator, ctx.descriptor);
    defer msg.deinit();
    try msg.decode(ctx.file, ctx.bytes);
    std.mem.doNotOptimizeAway(&msg);
}
