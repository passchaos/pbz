pub const std = @import("std");
pub const pbz = @import("pbz");
pub const person_pb = @import("person_pb");
pub const root = @import("pbz_bench.zig");

pub const GeneratedScalarMixEncodeCtx = struct { allocator: std.mem.Allocator, message: *const person_pb.demo.ScalarMix };

pub fn generatedScalarMixEncode(ctx: GeneratedScalarMixEncodeCtx) !void {
    const bytes = try ctx.message.encode(ctx.allocator);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.allocator.free(bytes);
}

pub const GeneratedScalarMixWriteToCtx = struct { writer: *pbz.Writer, message: *const person_pb.demo.ScalarMix };

pub fn generatedScalarMixWriteToReuse(ctx: GeneratedScalarMixWriteToCtx) !void {
    ctx.writer.clearRetainingCapacity();
    try ctx.message.writeToAssumeCapacity(ctx.writer);
    std.mem.doNotOptimizeAway(ctx.writer.slice().ptr);
}

pub const GeneratedScalarMixEncodeIntoCtx = struct { buffer: []u8, message: *const person_pb.demo.ScalarMix };

pub fn generatedScalarMixEncodeIntoReuse(ctx: GeneratedScalarMixEncodeIntoCtx) !void {
    const bytes = try ctx.message.encodeIntoAssumeCapacity(ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

pub const GeneratedScalarMixDecodeCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };

pub fn generatedScalarMixDecode(ctx: GeneratedScalarMixDecodeCtx) !void {
    var decoded = try person_pb.demo.ScalarMix.decode(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

pub const GeneratedScalarMixDecodeReuseCtx = struct { allocator: std.mem.Allocator, bytes: []const u8, message: *person_pb.demo.ScalarMix };

pub fn generatedScalarMixDecodeReuse(ctx: GeneratedScalarMixDecodeReuseCtx) !void {
    try ctx.message.decodeReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

pub fn generatedScalarMixKnownDecodeReuse(ctx: GeneratedScalarMixDecodeReuseCtx) !void {
    try ctx.message.decodeKnownReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

pub const GeneratedTextBytesEncodeCtx = struct { allocator: std.mem.Allocator, message: *const person_pb.demo.TextBytes };

pub fn generatedTextBytesEncode(ctx: GeneratedTextBytesEncodeCtx) !void {
    const bytes = try ctx.message.encode(ctx.allocator);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.allocator.free(bytes);
}

pub const GeneratedTextBytesWriteToCtx = struct { writer: *pbz.Writer, message: *const person_pb.demo.TextBytes };

pub fn generatedTextBytesWriteToReuse(ctx: GeneratedTextBytesWriteToCtx) !void {
    ctx.writer.clearRetainingCapacity();
    try ctx.message.writeToAssumeCapacity(ctx.writer);
    std.mem.doNotOptimizeAway(ctx.writer.slice().ptr);
}

pub fn generatedTextBytesTrustedUtf8WriteToReuse(ctx: GeneratedTextBytesWriteToCtx) !void {
    ctx.writer.clearRetainingCapacity();
    const msg = ctx.message;
    if (msg.title.len != 0) ctx.writer.writeStringAssumeCapacity(1, msg.title);
    if (msg.payload.len != 0) ctx.writer.writeBytesAssumeCapacity(2, msg.payload);
    for (msg.tags) |tag| ctx.writer.writeStringAssumeCapacity(3, tag);
    for (msg.chunks) |chunk| ctx.writer.writeBytesAssumeCapacity(4, chunk);
    std.mem.doNotOptimizeAway(ctx.writer.slice().ptr);
}

pub const GeneratedTextBytesEncodeIntoCtx = struct { buffer: []u8, message: *const person_pb.demo.TextBytes };

pub fn generatedTextBytesEncodeIntoReuse(ctx: GeneratedTextBytesEncodeIntoCtx) !void {
    const bytes = try ctx.message.encodeIntoAssumeCapacity(ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

pub fn generatedTextBytesTrustedUtf8EncodeIntoReuse(ctx: GeneratedTextBytesEncodeIntoCtx) !void {
    const bytes = try ctx.message.encodeIntoAssumeCapacityTrustedUtf8(ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

pub const GeneratedTextBytesBorrowedSlicesCtx = struct { message: *const person_pb.demo.TextBytes };

pub fn generatedTextBytesBorrowedSlices(ctx: GeneratedTextBytesBorrowedSlicesCtx) !void {
    var header: [10][20]u8 = undefined;
    const msg = ctx.message;
    var header_index: usize = 0;
    var total_len: usize = 0;
    if (msg.title.len != 0) {
        const slices = try person_pb.demo.TextBytes.titleStringSlices(&header[header_index], msg.title);
        header_index += 1;
        total_len += slices.header.len + slices.payload.len;
        std.mem.doNotOptimizeAway(slices.header.ptr);
        std.mem.doNotOptimizeAway(slices.payload.ptr);
    }
    if (msg.payload.len != 0) {
        const slices = try person_pb.demo.TextBytes.payloadBytesSlices(&header[header_index], msg.payload);
        header_index += 1;
        total_len += slices.header.len + slices.payload.len;
        std.mem.doNotOptimizeAway(slices.header.ptr);
        std.mem.doNotOptimizeAway(slices.payload.ptr);
    }
    for (msg.tags) |tag| {
        const slices = try person_pb.demo.TextBytes.tagsStringSlices(&header[header_index], tag);
        header_index += 1;
        total_len += slices.header.len + slices.payload.len;
        std.mem.doNotOptimizeAway(slices.header.ptr);
        std.mem.doNotOptimizeAway(slices.payload.ptr);
    }
    for (msg.chunks) |chunk| {
        const slices = try person_pb.demo.TextBytes.chunksBytesSlices(&header[header_index], chunk);
        header_index += 1;
        total_len += slices.header.len + slices.payload.len;
        std.mem.doNotOptimizeAway(slices.header.ptr);
        std.mem.doNotOptimizeAway(slices.payload.ptr);
    }
    std.mem.doNotOptimizeAway(total_len);
}

pub const GeneratedTextBytesDecodeCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };

pub fn generatedTextBytesDecode(ctx: GeneratedTextBytesDecodeCtx) !void {
    var decoded = try person_pb.demo.TextBytes.decode(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

pub const GeneratedTextBytesDecodeOwnedCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };

pub fn generatedTextBytesDecodeOwned(ctx: GeneratedTextBytesDecodeOwnedCtx) !void {
    var decoded = try person_pb.demo.TextBytes.decodeOwned(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

pub const GeneratedTextBytesDecodeReuseCtx = struct { allocator: std.mem.Allocator, bytes: []const u8, message: *person_pb.demo.TextBytes };

pub fn generatedTextBytesDecodeReuse(ctx: GeneratedTextBytesDecodeReuseCtx) !void {
    try ctx.message.decodeReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

pub const GeneratedTextBytesDecodeOwnedReuseCtx = struct { allocator: std.mem.Allocator, bytes: []const u8, message: *person_pb.demo.TextBytes };

pub fn generatedTextBytesDecodeOwnedReuse(ctx: GeneratedTextBytesDecodeOwnedReuseCtx) !void {
    try ctx.message.decodeOwnedReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

pub const GeneratedLargeBytesEncodeCtx = struct { allocator: std.mem.Allocator, message: *const person_pb.demo.LargeBytes };

pub fn generatedLargeBytesEncode(ctx: GeneratedLargeBytesEncodeCtx) !void {
    const bytes = try ctx.message.encode(ctx.allocator);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.allocator.free(bytes);
}

pub const GeneratedLargeBytesWriteToCtx = struct { writer: *pbz.Writer, message: *const person_pb.demo.LargeBytes };

pub fn generatedLargeBytesWriteToReuse(ctx: GeneratedLargeBytesWriteToCtx) !void {
    ctx.writer.clearRetainingCapacity();
    try ctx.message.writeToAssumeCapacity(ctx.writer);
    std.mem.doNotOptimizeAway(ctx.writer.slice().ptr);
}

pub const GeneratedLargeBytesEncodeIntoCtx = struct { buffer: []u8, message: *const person_pb.demo.LargeBytes };

pub fn generatedLargeBytesEncodeIntoReuse(ctx: GeneratedLargeBytesEncodeIntoCtx) !void {
    const bytes = try ctx.message.encodeIntoAssumeCapacity(ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

pub const GeneratedLargeBytesBorrowedSlicesCtx = struct { message: *const person_pb.demo.LargeBytes };

pub fn generatedLargeBytesBorrowedSlices(ctx: GeneratedLargeBytesBorrowedSlicesCtx) !void {
    var header: [root.LargeBytesChunkCount + 1][20]u8 = undefined;
    const msg = ctx.message;
    var total_len: usize = 0;
    if (msg.payload.len != 0) {
        const slices = try person_pb.demo.LargeBytes.payloadBytesSlices(&header[0], msg.payload);
        total_len += slices.header.len + slices.payload.len;
        std.mem.doNotOptimizeAway(slices.header.ptr);
        std.mem.doNotOptimizeAway(slices.payload.ptr);
    }
    for (msg.chunks, 0..) |chunk, i| {
        const slices = try person_pb.demo.LargeBytes.chunksBytesSlices(&header[i + 1], chunk);
        total_len += slices.header.len + slices.payload.len;
        std.mem.doNotOptimizeAway(slices.header.ptr);
        std.mem.doNotOptimizeAway(slices.payload.ptr);
    }
    std.mem.doNotOptimizeAway(total_len);
}

pub const GeneratedLargeBytesDecodeCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };

pub fn generatedLargeBytesDecode(ctx: GeneratedLargeBytesDecodeCtx) !void {
    var decoded = try person_pb.demo.LargeBytes.decode(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

pub const GeneratedLargeBytesDecodeReuseCtx = struct { allocator: std.mem.Allocator, bytes: []const u8, message: *person_pb.demo.LargeBytes };

pub fn generatedLargeBytesDecodeReuse(ctx: GeneratedLargeBytesDecodeReuseCtx) !void {
    try ctx.message.decodeReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

pub const GeneratedLargeBytesDecodeOwnedReuseCtx = struct { allocator: std.mem.Allocator, bytes: []const u8, message: *person_pb.demo.LargeBytes };

pub fn generatedLargeBytesDecodeOwnedReuse(ctx: GeneratedLargeBytesDecodeOwnedReuseCtx) !void {
    try ctx.message.decodeOwnedReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

pub const GeneratedLargeBytesDecodeOwnedCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };

pub fn generatedLargeBytesDecodeOwned(ctx: GeneratedLargeBytesDecodeOwnedCtx) !void {
    var decoded = try person_pb.demo.LargeBytes.decodeOwned(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

pub const GeneratedPresenceMixEncodeCtx = struct { allocator: std.mem.Allocator, message: *const person_pb.demo.PresenceMix };

pub fn generatedPresenceMixEncode(ctx: GeneratedPresenceMixEncodeCtx) !void {
    const bytes = try ctx.message.encode(ctx.allocator);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.allocator.free(bytes);
}

pub const GeneratedPresenceMixWriteToCtx = struct { writer: *pbz.Writer, message: *const person_pb.demo.PresenceMix };

pub fn generatedPresenceMixWriteToReuse(ctx: GeneratedPresenceMixWriteToCtx) !void {
    ctx.writer.clearRetainingCapacity();
    try ctx.message.writeToAssumeCapacity(ctx.writer);
    std.mem.doNotOptimizeAway(ctx.writer.slice().ptr);
}

pub const GeneratedPresenceMixEncodeIntoCtx = struct { buffer: []u8, message: *const person_pb.demo.PresenceMix };

pub fn generatedPresenceMixEncodeIntoReuse(ctx: GeneratedPresenceMixEncodeIntoCtx) !void {
    const bytes = try ctx.message.encodeIntoAssumeCapacity(ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

pub fn generatedPresenceMixTrustedUtf8EncodeIntoReuse(ctx: GeneratedPresenceMixEncodeIntoCtx) !void {
    const bytes = try ctx.message.encodeIntoAssumeCapacityTrustedUtf8(ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

pub const GeneratedPresenceMixDecodeCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };

pub fn generatedPresenceMixDecode(ctx: GeneratedPresenceMixDecodeCtx) !void {
    var decoded = try person_pb.demo.PresenceMix.decode(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

pub const GeneratedPresenceMixDecodeOwnedCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };

pub fn generatedPresenceMixDecodeOwned(ctx: GeneratedPresenceMixDecodeOwnedCtx) !void {
    var decoded = try person_pb.demo.PresenceMix.decodeOwned(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

pub const GeneratedPresenceMixDecodeReuseCtx = struct { allocator: std.mem.Allocator, bytes: []const u8, message: *person_pb.demo.PresenceMix };

pub fn generatedPresenceMixDecodeReuse(ctx: GeneratedPresenceMixDecodeReuseCtx) !void {
    try ctx.message.decodeReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

pub const GeneratedPresenceMixDecodeOwnedReuseCtx = struct { allocator: std.mem.Allocator, bytes: []const u8, message: *person_pb.demo.PresenceMix };

pub fn generatedPresenceMixDecodeOwnedReuse(ctx: GeneratedPresenceMixDecodeOwnedReuseCtx) !void {
    try ctx.message.decodeOwnedReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

pub const GeneratedComplexEncodeCtx = struct { allocator: std.mem.Allocator, message: *const person_pb.demo.Complex };

pub fn generatedComplexEncode(ctx: GeneratedComplexEncodeCtx) !void {
    const bytes = try ctx.message.encode(ctx.allocator);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.allocator.free(bytes);
}

pub const GeneratedComplexWriteToCtx = struct { writer: *pbz.Writer, message: *const person_pb.demo.Complex };

pub fn generatedComplexWriteToReuse(ctx: GeneratedComplexWriteToCtx) !void {
    ctx.writer.clearRetainingCapacity();
    try ctx.message.writeToAssumeCapacity(ctx.writer);
    std.mem.doNotOptimizeAway(ctx.writer.slice().ptr);
}

pub const GeneratedComplexEncodeIntoCtx = struct { buffer: []u8, message: *const person_pb.demo.Complex };

pub fn generatedComplexEncodeIntoReuse(ctx: GeneratedComplexEncodeIntoCtx) !void {
    const bytes = try ctx.message.encodeIntoAssumeCapacity(ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

pub const GeneratedComplexManualEncodeIntoCtx = struct { buffer: []u8, message: *const person_pb.demo.Complex };

pub fn generatedComplexManualEncodeIntoReuse(ctx: GeneratedComplexManualEncodeIntoCtx) !void {
    const bytes = try ctx.message.encodeIntoAssumeCapacityTrustedUtf8(ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

pub const GeneratedComplexDecodeCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };

pub fn generatedComplexDecode(ctx: GeneratedComplexDecodeCtx) !void {
    var decoded = try person_pb.demo.Complex.decode(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

pub const GeneratedComplexDecodeOwnedCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };

pub fn generatedComplexDecodeOwned(ctx: GeneratedComplexDecodeOwnedCtx) !void {
    var decoded = try person_pb.demo.Complex.decodeOwned(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

pub const GeneratedComplexDecodeReuseCtx = struct { allocator: std.mem.Allocator, bytes: []const u8, message: *person_pb.demo.Complex };

pub fn generatedComplexDecodeReuse(ctx: GeneratedComplexDecodeReuseCtx) !void {
    try ctx.message.decodeReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

pub const GeneratedComplexDecodeOwnedReuseCtx = struct { allocator: std.mem.Allocator, bytes: []const u8, message: *person_pb.demo.Complex };

pub fn generatedComplexDecodeOwnedReuse(ctx: GeneratedComplexDecodeOwnedReuseCtx) !void {
    try ctx.message.decodeOwnedReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

pub const GeneratedComplexDeterministicEncodeCtx = struct { allocator: std.mem.Allocator, message: *const person_pb.demo.Complex };

pub fn generatedComplexDeterministicEncode(ctx: GeneratedComplexDeterministicEncodeCtx) !void {
    const bytes = try ctx.message.encodeDeterministic(ctx.allocator);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.allocator.free(bytes);
}

pub const GeneratedComplexDeterministicEncodeIntoCtx = struct { allocator: std.mem.Allocator, buffer: []u8, message: *const person_pb.demo.Complex };

pub fn generatedComplexDeterministicEncodeIntoReuse(ctx: GeneratedComplexDeterministicEncodeIntoCtx) !void {
    const bytes = try ctx.message.encodeDeterministicIntoAssumeCapacity(ctx.allocator, ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

pub const GeneratedEncodeCtx = struct { allocator: std.mem.Allocator, person: *const person_pb.demo.Person };

pub fn generatedEncode(ctx: GeneratedEncodeCtx) !void {
    const bytes = try ctx.person.encode(ctx.allocator);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.allocator.free(bytes);
}

pub const GeneratedWriteToCtx = struct { writer: *pbz.Writer, person: *const person_pb.demo.Person };

pub fn generatedWriteToReuse(ctx: GeneratedWriteToCtx) !void {
    ctx.writer.clearRetainingCapacity();
    try ctx.person.writeToAssumeCapacity(ctx.writer);
    std.mem.doNotOptimizeAway(ctx.writer.slice().ptr);
}

pub const GeneratedEncodeIntoCtx = struct { buffer: []u8, person: *const person_pb.demo.Person };

pub fn generatedEncodeIntoReuse(ctx: GeneratedEncodeIntoCtx) !void {
    const bytes = try ctx.person.encodeIntoAssumeCapacity(ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

pub const GeneratedPersonFastEncodeIntoCtx = struct { buffer: []u8, person: *const person_pb.demo.Person };

pub fn generatedPersonTrustedUtf8EncodeIntoReuse(ctx: GeneratedPersonFastEncodeIntoCtx) !void {
    const bytes = try ctx.person.encodeIntoAssumeCapacityTrustedUtf8(ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

pub const GeneratedDeterministicEncodeCtx = struct { allocator: std.mem.Allocator, person: *const person_pb.demo.Person };

pub fn generatedDeterministicEncode(ctx: GeneratedDeterministicEncodeCtx) !void {
    const bytes = try ctx.person.encodeDeterministic(ctx.allocator);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.allocator.free(bytes);
}

pub const GeneratedDeterministicEncodeIntoCtx = struct { allocator: std.mem.Allocator, buffer: []u8, person: *const person_pb.demo.Person };

pub fn generatedDeterministicEncodeIntoReuse(ctx: GeneratedDeterministicEncodeIntoCtx) !void {
    const bytes = try ctx.person.encodeDeterministicIntoAssumeCapacity(ctx.allocator, ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

pub const GeneratedDecodeCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };

pub fn generatedDecode(ctx: GeneratedDecodeCtx) !void {
    var decoded = try person_pb.demo.Person.decode(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

pub const GeneratedDecodeOwnedCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };

pub fn generatedDecodeOwned(ctx: GeneratedDecodeOwnedCtx) !void {
    var decoded = try person_pb.demo.Person.decodeOwned(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

pub const GeneratedDecodeReuseCtx = struct { allocator: std.mem.Allocator, bytes: []const u8, message: *person_pb.demo.Person };

pub fn generatedDecodeReuse(ctx: GeneratedDecodeReuseCtx) !void {
    try ctx.message.decodeReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

pub const GeneratedDecodeOwnedReuseCtx = struct { allocator: std.mem.Allocator, bytes: []const u8, message: *person_pb.demo.Person };

pub fn generatedDecodeOwnedReuse(ctx: GeneratedDecodeOwnedReuseCtx) !void {
    try ctx.message.decodeOwnedReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}
