pub const std = @import("std");
pub const pbz = @import("pbz");
pub const person_pb = @import("person_pb");
pub const root = @import("pbz_bench.zig");

pub const GeneratedLargeMapEncodeCtx = struct { allocator: std.mem.Allocator, message: *const person_pb.demo.LargeMap };

pub fn generatedLargeMapEncode(ctx: GeneratedLargeMapEncodeCtx) !void {
    const bytes = try ctx.message.encode(ctx.allocator);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.allocator.free(bytes);
}

pub const GeneratedLargeMapWriteToCtx = struct { writer: *pbz.Writer, message: *const person_pb.demo.LargeMap };

pub fn generatedLargeMapWriteToReuse(ctx: GeneratedLargeMapWriteToCtx) !void {
    ctx.writer.clearRetainingCapacity();
    try ctx.message.writeToAssumeCapacity(ctx.writer);
    std.mem.doNotOptimizeAway(ctx.writer.slice().ptr);
}

pub const GeneratedLargeMapEncodeIntoCtx = struct { buffer: []u8, message: *const person_pb.demo.LargeMap };

pub fn generatedLargeMapEncodeIntoReuse(ctx: GeneratedLargeMapEncodeIntoCtx) !void {
    const bytes = try ctx.message.encodeIntoAssumeCapacity(ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

pub const GeneratedLargeMapDeterministicEncodeIntoCtx = struct { allocator: std.mem.Allocator, buffer: []u8, message: *const person_pb.demo.LargeMap };

pub fn generatedLargeMapDeterministicEncodeIntoReuse(ctx: GeneratedLargeMapDeterministicEncodeIntoCtx) !void {
    const bytes = try ctx.message.encodeDeterministicIntoAssumeCapacity(ctx.allocator, ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

pub const GeneratedLargeMapDecodeCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };

pub fn generatedLargeMapDecode(ctx: GeneratedLargeMapDecodeCtx) !void {
    var decoded = try person_pb.demo.LargeMap.decode(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

pub const GeneratedLargeMapDecodeOwnedCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };

pub fn generatedLargeMapDecodeOwned(ctx: GeneratedLargeMapDecodeOwnedCtx) !void {
    var decoded = try person_pb.demo.LargeMap.decodeOwned(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

pub const GeneratedLargeMapDecodeReuseCtx = struct { allocator: std.mem.Allocator, bytes: []const u8, message: *person_pb.demo.LargeMap };

pub fn generatedLargeMapDecodeReuse(ctx: GeneratedLargeMapDecodeReuseCtx) !void {
    try ctx.message.decodeReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

pub const GeneratedLargeMapDecodeOwnedReuseCtx = struct { allocator: std.mem.Allocator, bytes: []const u8, message: *person_pb.demo.LargeMap };

pub fn generatedLargeMapDecodeOwnedReuse(ctx: GeneratedLargeMapDecodeOwnedReuseCtx) !void {
    try ctx.message.decodeOwnedReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}
