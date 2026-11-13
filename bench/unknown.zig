pub const std = @import("std");
pub const pbz = @import("pbz");
pub const person_pb = @import("person_pb");
pub const root = @import("pbz_bench.zig");

pub const GeneratedUnknownDecodeCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };

pub fn generatedUnknownDecode(ctx: GeneratedUnknownDecodeCtx) !void {
    var decoded = try person_pb.demo.Person.decode(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    if (decoded.unknownFieldCount() != root.UnknownFieldStressCount) return error.InvalidWireType;
    decoded.deinit(ctx.allocator);
}

pub const GeneratedUnknownQueryCtx = struct { message: *const person_pb.demo.Person, number: pbz.FieldNumber };

pub fn generatedUnknownCountByNumber(ctx: GeneratedUnknownQueryCtx) !void {
    const count = try ctx.message.unknownFieldCountByNumber(ctx.number);
    std.mem.doNotOptimizeAway(count);
}

pub const GeneratedUnknownNumberQueryCtx = struct { numbers: []const pbz.FieldNumber, number: pbz.FieldNumber };

pub fn generatedUnknownNumberCountByNumber(ctx: GeneratedUnknownNumberQueryCtx) !void {
    const count = pbz.wire.rawFieldNumberCount(ctx.numbers, ctx.number);
    std.mem.doNotOptimizeAway(count);
}

pub const GeneratedUnknownRunQueryCtx = struct { runs: []const pbz.wire.RawFieldNumberRun, number: pbz.FieldNumber };

pub fn generatedUnknownNumberRunCountByNumber(ctx: GeneratedUnknownRunQueryCtx) !void {
    const count = pbz.wire.rawFieldNumberRunCount(ctx.runs, ctx.number);
    std.mem.doNotOptimizeAway(count);
}

pub const DynamicUnknownDecodeCtx = struct { allocator: std.mem.Allocator, descriptor: *const pbz.MessageDescriptor, file: *const pbz.FileDescriptor, bytes: []const u8 };

pub fn dynamicUnknownDecode(ctx: DynamicUnknownDecodeCtx) !void {
    var msg = pbz.DynamicMessage.init(ctx.allocator, ctx.descriptor);
    defer msg.deinit();
    try msg.decode(ctx.file, ctx.bytes);
    std.mem.doNotOptimizeAway(&msg);
    if (msg.unknownCount() != root.UnknownFieldStressCount) return error.InvalidWireType;
}

pub const DynamicUnknownQueryCtx = struct { message: *const pbz.DynamicMessage, number: pbz.FieldNumber };

pub fn dynamicUnknownCountByNumber(ctx: DynamicUnknownQueryCtx) !void {
    const count = ctx.message.unknownFieldCountByNumber(ctx.number);
    std.mem.doNotOptimizeAway(count);
}

pub const DynamicUnknownNumberQueryCtx = struct { numbers: []const pbz.FieldNumber, number: pbz.FieldNumber };

pub fn dynamicUnknownNumberCountByNumber(ctx: DynamicUnknownNumberQueryCtx) !void {
    const count = pbz.wire.rawFieldNumberCount(ctx.numbers, ctx.number);
    std.mem.doNotOptimizeAway(count);
}

pub const DynamicUnknownRunQueryCtx = struct { runs: []const pbz.wire.RawFieldNumberRun, number: pbz.FieldNumber };

pub fn dynamicUnknownNumberRunCountByNumber(ctx: DynamicUnknownRunQueryCtx) !void {
    const count = pbz.wire.rawFieldNumberRunCount(ctx.runs, ctx.number);
    std.mem.doNotOptimizeAway(count);
}
