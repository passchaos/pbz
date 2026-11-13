pub const std = @import("std");
pub const pbz = @import("pbz");
pub const person_pb = @import("person_pb");
pub const root = @import("pbz_bench.zig");

pub const GeneratedPackedEncodeCtx = struct { allocator: std.mem.Allocator, message: *const person_pb.demo.Packed };

pub fn generatedPackedEncode(ctx: GeneratedPackedEncodeCtx) !void {
    const bytes = try ctx.message.encode(ctx.allocator);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.allocator.free(bytes);
}

pub const GeneratedPackedWriteToCtx = struct { writer: *pbz.Writer, message: *const person_pb.demo.Packed };

pub fn generatedPackedWriteToReuse(ctx: GeneratedPackedWriteToCtx) !void {
    ctx.writer.clearRetainingCapacity();
    try ctx.message.writeToAssumeCapacity(ctx.writer);
    std.mem.doNotOptimizeAway(ctx.writer.slice().ptr);
}

pub const GeneratedPackedEncodeIntoCtx = struct { buffer: []u8, message: *const person_pb.demo.Packed };

pub fn generatedPackedEncodeIntoReuse(ctx: GeneratedPackedEncodeIntoCtx) !void {
    const bytes = try ctx.message.encodeIntoAssumeCapacity(ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

pub const GeneratedPackedDecodeCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };

pub fn generatedPackedDecode(ctx: GeneratedPackedDecodeCtx) !void {
    var decoded = try person_pb.demo.Packed.decode(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

pub const GeneratedPackedDecodeReuseCtx = struct { allocator: std.mem.Allocator, bytes: []const u8, message: *person_pb.demo.Packed };

pub fn generatedPackedKnownDecodeReuse(ctx: GeneratedPackedDecodeReuseCtx) !void {
    try ctx.message.decodeKnownReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

pub const GeneratedFixedPackedEncodeCtx = struct { allocator: std.mem.Allocator, message: *const person_pb.demo.FixedPacked };

pub fn generatedFixedPackedEncode(ctx: GeneratedFixedPackedEncodeCtx) !void {
    const bytes = try ctx.message.encode(ctx.allocator);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.allocator.free(bytes);
}

pub const GeneratedFixedPackedEncodeIntoCtx = struct { buffer: []u8, message: *const person_pb.demo.FixedPacked };

pub fn generatedFixedPackedEncodeIntoReuse(ctx: GeneratedFixedPackedEncodeIntoCtx) !void {
    const bytes = try ctx.message.encodeIntoAssumeCapacity(ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

pub const GeneratedFixedPackedSlicesCtx = struct { message: *const person_pb.demo.FixedPacked };

pub fn generatedFixedPackedBorrowedSlices(ctx: GeneratedFixedPackedSlicesCtx) !void {
    var header: [20]u8 = undefined;
    const slices = try person_pb.demo.FixedPacked.valuesPackedFixed32Slices(&header, ctx.message.values);
    std.mem.doNotOptimizeAway(slices.header.ptr);
    std.mem.doNotOptimizeAway(slices.payload.ptr);
}

pub const GeneratedFixedPackedDecodeCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };

pub fn generatedFixedPackedDecode(ctx: GeneratedFixedPackedDecodeCtx) !void {
    var decoded = try person_pb.demo.FixedPacked.decode(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

pub const GeneratedFixedPackedDecodeReuseCtx = struct { allocator: std.mem.Allocator, bytes: []const u8, message: *person_pb.demo.FixedPacked };

pub fn generatedFixedPackedKnownDecodeReuse(ctx: GeneratedFixedPackedDecodeReuseCtx) !void {
    try ctx.message.decodeKnownReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

pub const FixedPackedBorrowedViewCtx = struct { bytes: []const u8 };

pub fn fixedPackedBorrowedViewDecode(ctx: FixedPackedBorrowedViewCtx) !void {
    const values = (try person_pb.demo.FixedPacked.valuesPackedFixed32View(ctx.bytes)) orelse return error.InvalidWireType;
    std.mem.doNotOptimizeAway(values.ptr);
}

pub const GeneratedFixed64PackedEncodeCtx = struct { allocator: std.mem.Allocator, message: *const person_pb.demo.Fixed64Packed };

pub fn generatedFixed64PackedEncode(ctx: GeneratedFixed64PackedEncodeCtx) !void {
    const bytes = try ctx.message.encode(ctx.allocator);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.allocator.free(bytes);
}

pub const GeneratedFixed64PackedEncodeIntoCtx = struct { buffer: []u8, message: *const person_pb.demo.Fixed64Packed };

pub fn generatedFixed64PackedEncodeIntoReuse(ctx: GeneratedFixed64PackedEncodeIntoCtx) !void {
    const bytes = try ctx.message.encodeIntoAssumeCapacity(ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

pub const GeneratedFixed64PackedSlicesCtx = struct { message: *const person_pb.demo.Fixed64Packed };

pub fn generatedFixed64PackedBorrowedSlices(ctx: GeneratedFixed64PackedSlicesCtx) !void {
    var header: [20]u8 = undefined;
    const slices = try person_pb.demo.Fixed64Packed.valuesPackedFixedSlices(&header, ctx.message.values);
    std.mem.doNotOptimizeAway(slices.header.ptr);
    std.mem.doNotOptimizeAway(slices.payload.ptr);
}

pub const GeneratedFixed64PackedDecodeCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };

pub fn generatedFixed64PackedDecode(ctx: GeneratedFixed64PackedDecodeCtx) !void {
    var decoded = try person_pb.demo.Fixed64Packed.decode(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

pub const GeneratedFixed64PackedDecodeReuseCtx = struct { allocator: std.mem.Allocator, bytes: []const u8, message: *person_pb.demo.Fixed64Packed };

pub fn generatedFixed64PackedKnownDecodeReuse(ctx: GeneratedFixed64PackedDecodeReuseCtx) !void {
    try ctx.message.decodeKnownReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

pub const GeneratedSFixedPackedEncodeCtx = struct { allocator: std.mem.Allocator, message: *const person_pb.demo.SFixedPacked };

pub fn generatedSFixedPackedEncode(ctx: GeneratedSFixedPackedEncodeCtx) !void {
    const bytes = try ctx.message.encode(ctx.allocator);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.allocator.free(bytes);
}

pub const GeneratedSFixedPackedEncodeIntoCtx = struct { buffer: []u8, message: *const person_pb.demo.SFixedPacked };

pub fn generatedSFixedPackedEncodeIntoReuse(ctx: GeneratedSFixedPackedEncodeIntoCtx) !void {
    const bytes = try ctx.message.encodeIntoAssumeCapacity(ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

pub const GeneratedSFixedPackedSlicesCtx = struct { message: *const person_pb.demo.SFixedPacked };

pub fn generatedSFixedPackedBorrowedSlices(ctx: GeneratedSFixedPackedSlicesCtx) !void {
    var header: [20]u8 = undefined;
    const slices = try person_pb.demo.SFixedPacked.valuesPackedFixedSlices(&header, ctx.message.values);
    std.mem.doNotOptimizeAway(slices.header.ptr);
    std.mem.doNotOptimizeAway(slices.payload.ptr);
}

pub const GeneratedSFixedPackedDecodeCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };

pub fn generatedSFixedPackedDecode(ctx: GeneratedSFixedPackedDecodeCtx) !void {
    var decoded = try person_pb.demo.SFixedPacked.decode(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

pub const GeneratedSFixedPackedDecodeReuseCtx = struct { allocator: std.mem.Allocator, bytes: []const u8, message: *person_pb.demo.SFixedPacked };

pub fn generatedSFixedPackedKnownDecodeReuse(ctx: GeneratedSFixedPackedDecodeReuseCtx) !void {
    try ctx.message.decodeKnownReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

pub const GeneratedSFixed64PackedEncodeCtx = struct { allocator: std.mem.Allocator, message: *const person_pb.demo.SFixed64Packed };

pub fn generatedSFixed64PackedEncode(ctx: GeneratedSFixed64PackedEncodeCtx) !void {
    const bytes = try ctx.message.encode(ctx.allocator);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.allocator.free(bytes);
}

pub const GeneratedSFixed64PackedEncodeIntoCtx = struct { buffer: []u8, message: *const person_pb.demo.SFixed64Packed };

pub fn generatedSFixed64PackedEncodeIntoReuse(ctx: GeneratedSFixed64PackedEncodeIntoCtx) !void {
    const bytes = try ctx.message.encodeIntoAssumeCapacity(ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

pub const GeneratedSFixed64PackedSlicesCtx = struct { message: *const person_pb.demo.SFixed64Packed };

pub fn generatedSFixed64PackedBorrowedSlices(ctx: GeneratedSFixed64PackedSlicesCtx) !void {
    var header: [20]u8 = undefined;
    const slices = try person_pb.demo.SFixed64Packed.valuesPackedFixedSlices(&header, ctx.message.values);
    std.mem.doNotOptimizeAway(slices.header.ptr);
    std.mem.doNotOptimizeAway(slices.payload.ptr);
}

pub const GeneratedSFixed64PackedDecodeCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };

pub fn generatedSFixed64PackedDecode(ctx: GeneratedSFixed64PackedDecodeCtx) !void {
    var decoded = try person_pb.demo.SFixed64Packed.decode(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

pub const GeneratedSFixed64PackedDecodeReuseCtx = struct { allocator: std.mem.Allocator, bytes: []const u8, message: *person_pb.demo.SFixed64Packed };

pub fn generatedSFixed64PackedKnownDecodeReuse(ctx: GeneratedSFixed64PackedDecodeReuseCtx) !void {
    try ctx.message.decodeKnownReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

pub const GeneratedFloatPackedEncodeCtx = struct { allocator: std.mem.Allocator, message: *const person_pb.demo.FloatPacked };

pub fn generatedFloatPackedEncode(ctx: GeneratedFloatPackedEncodeCtx) !void {
    const bytes = try ctx.message.encode(ctx.allocator);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.allocator.free(bytes);
}

pub const GeneratedFloatPackedEncodeIntoCtx = struct { buffer: []u8, message: *const person_pb.demo.FloatPacked };

pub fn generatedFloatPackedEncodeIntoReuse(ctx: GeneratedFloatPackedEncodeIntoCtx) !void {
    const bytes = try ctx.message.encodeIntoAssumeCapacity(ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

pub const GeneratedFloatPackedSlicesCtx = struct { message: *const person_pb.demo.FloatPacked };

pub fn generatedFloatPackedBorrowedSlices(ctx: GeneratedFloatPackedSlicesCtx) !void {
    var header: [20]u8 = undefined;
    const slices = try person_pb.demo.FloatPacked.valuesPackedFixedSlices(&header, ctx.message.values);
    std.mem.doNotOptimizeAway(slices.header.ptr);
    std.mem.doNotOptimizeAway(slices.payload.ptr);
}

pub const GeneratedFloatPackedDecodeCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };

pub fn generatedFloatPackedDecode(ctx: GeneratedFloatPackedDecodeCtx) !void {
    var decoded = try person_pb.demo.FloatPacked.decode(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

pub const GeneratedFloatPackedDecodeReuseCtx = struct { allocator: std.mem.Allocator, bytes: []const u8, message: *person_pb.demo.FloatPacked };

pub fn generatedFloatPackedKnownDecodeReuse(ctx: GeneratedFloatPackedDecodeReuseCtx) !void {
    try ctx.message.decodeKnownReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

pub const GeneratedDoublePackedEncodeCtx = struct { allocator: std.mem.Allocator, message: *const person_pb.demo.DoublePacked };

pub fn generatedDoublePackedEncode(ctx: GeneratedDoublePackedEncodeCtx) !void {
    const bytes = try ctx.message.encode(ctx.allocator);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.allocator.free(bytes);
}

pub const GeneratedDoublePackedEncodeIntoCtx = struct { buffer: []u8, message: *const person_pb.demo.DoublePacked };

pub fn generatedDoublePackedEncodeIntoReuse(ctx: GeneratedDoublePackedEncodeIntoCtx) !void {
    const bytes = try ctx.message.encodeIntoAssumeCapacity(ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

pub const GeneratedDoublePackedSlicesCtx = struct { message: *const person_pb.demo.DoublePacked };

pub fn generatedDoublePackedBorrowedSlices(ctx: GeneratedDoublePackedSlicesCtx) !void {
    var header: [20]u8 = undefined;
    const slices = try person_pb.demo.DoublePacked.valuesPackedFixedSlices(&header, ctx.message.values);
    std.mem.doNotOptimizeAway(slices.header.ptr);
    std.mem.doNotOptimizeAway(slices.payload.ptr);
}

pub const GeneratedDoublePackedDecodeCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };

pub fn generatedDoublePackedDecode(ctx: GeneratedDoublePackedDecodeCtx) !void {
    var decoded = try person_pb.demo.DoublePacked.decode(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

pub const GeneratedDoublePackedDecodeReuseCtx = struct { allocator: std.mem.Allocator, bytes: []const u8, message: *person_pb.demo.DoublePacked };

pub fn generatedDoublePackedKnownDecodeReuse(ctx: GeneratedDoublePackedDecodeReuseCtx) !void {
    try ctx.message.decodeKnownReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

pub const GeneratedUInt64PackedEncodeCtx = struct { allocator: std.mem.Allocator, message: *const person_pb.demo.UInt64Packed };

pub fn generatedUInt64PackedEncode(ctx: GeneratedUInt64PackedEncodeCtx) !void {
    const bytes = try ctx.message.encode(ctx.allocator);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.allocator.free(bytes);
}

pub const GeneratedUInt64PackedEncodeIntoCtx = struct { buffer: []u8, message: *const person_pb.demo.UInt64Packed };

pub fn generatedUInt64PackedEncodeIntoReuse(ctx: GeneratedUInt64PackedEncodeIntoCtx) !void {
    const bytes = try ctx.message.encodeIntoAssumeCapacity(ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

pub const GeneratedUInt64PackedDecodeCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };

pub fn generatedUInt64PackedDecode(ctx: GeneratedUInt64PackedDecodeCtx) !void {
    var decoded = try person_pb.demo.UInt64Packed.decode(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

pub const GeneratedUInt64PackedDecodeReuseCtx = struct { allocator: std.mem.Allocator, bytes: []const u8, message: *person_pb.demo.UInt64Packed };

pub fn generatedUInt64PackedDecodeReuse(ctx: GeneratedUInt64PackedDecodeReuseCtx) !void {
    try ctx.message.decodeReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

pub fn generatedUInt64PackedKnownDecodeReuse(ctx: GeneratedUInt64PackedDecodeReuseCtx) !void {
    try ctx.message.decodeKnownReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

pub const GeneratedUInt32PackedEncodeCtx = struct { allocator: std.mem.Allocator, message: *const person_pb.demo.UInt32Packed };

pub fn generatedUInt32PackedEncode(ctx: GeneratedUInt32PackedEncodeCtx) !void {
    const bytes = try ctx.message.encode(ctx.allocator);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.allocator.free(bytes);
}

pub const GeneratedUInt32PackedEncodeIntoCtx = struct { buffer: []u8, message: *const person_pb.demo.UInt32Packed };

pub fn generatedUInt32PackedEncodeIntoReuse(ctx: GeneratedUInt32PackedEncodeIntoCtx) !void {
    const bytes = try ctx.message.encodeIntoAssumeCapacity(ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

pub const GeneratedUInt32PackedDecodeCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };

pub fn generatedUInt32PackedDecode(ctx: GeneratedUInt32PackedDecodeCtx) !void {
    var decoded = try person_pb.demo.UInt32Packed.decode(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

pub const GeneratedUInt32PackedDecodeReuseCtx = struct { allocator: std.mem.Allocator, bytes: []const u8, message: *person_pb.demo.UInt32Packed };

pub fn generatedUInt32PackedDecodeReuse(ctx: GeneratedUInt32PackedDecodeReuseCtx) !void {
    try ctx.message.decodeReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

pub fn generatedUInt32PackedKnownDecodeReuse(ctx: GeneratedUInt32PackedDecodeReuseCtx) !void {
    try ctx.message.decodeKnownReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

pub const GeneratedInt64PackedEncodeCtx = struct { allocator: std.mem.Allocator, message: *const person_pb.demo.Int64Packed };

pub fn generatedInt64PackedEncode(ctx: GeneratedInt64PackedEncodeCtx) !void {
    const bytes = try ctx.message.encode(ctx.allocator);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.allocator.free(bytes);
}

pub const GeneratedInt64PackedEncodeIntoCtx = struct { buffer: []u8, message: *const person_pb.demo.Int64Packed };

pub fn generatedInt64PackedEncodeIntoReuse(ctx: GeneratedInt64PackedEncodeIntoCtx) !void {
    const bytes = try ctx.message.encodeIntoAssumeCapacity(ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

pub const GeneratedInt64PackedDecodeCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };

pub fn generatedInt64PackedDecode(ctx: GeneratedInt64PackedDecodeCtx) !void {
    var decoded = try person_pb.demo.Int64Packed.decode(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

pub const GeneratedInt64PackedDecodeReuseCtx = struct { allocator: std.mem.Allocator, bytes: []const u8, message: *person_pb.demo.Int64Packed };

pub fn generatedInt64PackedKnownDecodeReuse(ctx: GeneratedInt64PackedDecodeReuseCtx) !void {
    try ctx.message.decodeKnownReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

pub const GeneratedSInt32PackedEncodeCtx = struct { allocator: std.mem.Allocator, message: *const person_pb.demo.SInt32Packed };

pub fn generatedSInt32PackedEncode(ctx: GeneratedSInt32PackedEncodeCtx) !void {
    const bytes = try ctx.message.encode(ctx.allocator);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.allocator.free(bytes);
}

pub const GeneratedSInt32PackedEncodeIntoCtx = struct { buffer: []u8, message: *const person_pb.demo.SInt32Packed };

pub fn generatedSInt32PackedEncodeIntoReuse(ctx: GeneratedSInt32PackedEncodeIntoCtx) !void {
    const bytes = try ctx.message.encodeIntoAssumeCapacity(ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

pub const GeneratedSInt32PackedDecodeCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };

pub fn generatedSInt32PackedDecode(ctx: GeneratedSInt32PackedDecodeCtx) !void {
    var decoded = try person_pb.demo.SInt32Packed.decode(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

pub const GeneratedSInt32PackedDecodeReuseCtx = struct { allocator: std.mem.Allocator, bytes: []const u8, message: *person_pb.demo.SInt32Packed };

pub fn generatedSInt32PackedKnownDecodeReuse(ctx: GeneratedSInt32PackedDecodeReuseCtx) !void {
    try ctx.message.decodeKnownReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

pub const GeneratedSInt64PackedEncodeCtx = struct { allocator: std.mem.Allocator, message: *const person_pb.demo.SInt64Packed };

pub fn generatedSInt64PackedEncode(ctx: GeneratedSInt64PackedEncodeCtx) !void {
    const bytes = try ctx.message.encode(ctx.allocator);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.allocator.free(bytes);
}

pub const GeneratedSInt64PackedEncodeIntoCtx = struct { buffer: []u8, message: *const person_pb.demo.SInt64Packed };

pub fn generatedSInt64PackedEncodeIntoReuse(ctx: GeneratedSInt64PackedEncodeIntoCtx) !void {
    const bytes = try ctx.message.encodeIntoAssumeCapacity(ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

pub const GeneratedSInt64PackedDecodeCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };

pub fn generatedSInt64PackedDecode(ctx: GeneratedSInt64PackedDecodeCtx) !void {
    var decoded = try person_pb.demo.SInt64Packed.decode(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

pub const GeneratedSInt64PackedDecodeReuseCtx = struct { allocator: std.mem.Allocator, bytes: []const u8, message: *person_pb.demo.SInt64Packed };

pub fn generatedSInt64PackedKnownDecodeReuse(ctx: GeneratedSInt64PackedDecodeReuseCtx) !void {
    try ctx.message.decodeKnownReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

pub const GeneratedBoolPackedEncodeCtx = struct { allocator: std.mem.Allocator, message: *const person_pb.demo.BoolPacked };

pub fn generatedBoolPackedEncode(ctx: GeneratedBoolPackedEncodeCtx) !void {
    const bytes = try ctx.message.encode(ctx.allocator);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.allocator.free(bytes);
}

pub const GeneratedBoolPackedEncodeIntoCtx = struct { buffer: []u8, message: *const person_pb.demo.BoolPacked };

pub fn generatedBoolPackedEncodeIntoReuse(ctx: GeneratedBoolPackedEncodeIntoCtx) !void {
    const bytes = try ctx.message.encodeIntoAssumeCapacity(ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

pub const GeneratedBoolPackedSlicesCtx = struct { message: *const person_pb.demo.BoolPacked };

pub fn generatedBoolPackedBorrowedSlices(ctx: GeneratedBoolPackedSlicesCtx) !void {
    var header: [20]u8 = undefined;
    const slices = try person_pb.demo.BoolPacked.valuesPackedBoolSlices(&header, ctx.message.values);
    std.mem.doNotOptimizeAway(slices.header.ptr);
    std.mem.doNotOptimizeAway(slices.payload.ptr);
}

pub const GeneratedBoolPackedDecodeCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };

pub fn generatedBoolPackedDecode(ctx: GeneratedBoolPackedDecodeCtx) !void {
    var decoded = try person_pb.demo.BoolPacked.decode(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

pub const GeneratedBoolPackedDecodeReuseCtx = struct { allocator: std.mem.Allocator, bytes: []const u8, message: *person_pb.demo.BoolPacked };

pub fn generatedBoolPackedKnownDecodeReuse(ctx: GeneratedBoolPackedDecodeReuseCtx) !void {
    try ctx.message.decodeKnownReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

pub const GeneratedEnumPackedEncodeCtx = struct { allocator: std.mem.Allocator, message: *const person_pb.demo.EnumPacked };

pub fn generatedEnumPackedEncode(ctx: GeneratedEnumPackedEncodeCtx) !void {
    const bytes = try ctx.message.encode(ctx.allocator);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.allocator.free(bytes);
}

pub const GeneratedEnumPackedEncodeIntoCtx = struct { buffer: []u8, message: *const person_pb.demo.EnumPacked };

pub fn generatedEnumPackedEncodeIntoReuse(ctx: GeneratedEnumPackedEncodeIntoCtx) !void {
    const bytes = try ctx.message.encodeIntoAssumeCapacity(ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

pub const GeneratedEnumPackedDecodeCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };

pub fn generatedEnumPackedDecode(ctx: GeneratedEnumPackedDecodeCtx) !void {
    var decoded = try person_pb.demo.EnumPacked.decode(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

pub const GeneratedEnumPackedDecodeReuseCtx = struct { allocator: std.mem.Allocator, bytes: []const u8, message: *person_pb.demo.EnumPacked };

pub fn generatedEnumPackedDecodeReuse(ctx: GeneratedEnumPackedDecodeReuseCtx) !void {
    try ctx.message.decodeReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

pub fn generatedEnumPackedKnownDecodeReuse(ctx: GeneratedEnumPackedDecodeReuseCtx) !void {
    try ctx.message.decodeKnownReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

pub const Int32PackedIteratorCtx = struct { bytes: []const u8 };

pub fn int32PackedIteratorDecode(ctx: Int32PackedIteratorCtx) !void {
    var it = (try person_pb.demo.Packed.valuesPackedIterator(ctx.bytes)) orelse return error.InvalidWireType;
    var sum: i32 = 0;
    while (try it.next()) |value| sum +%= value;
    std.mem.doNotOptimizeAway(sum);
}

pub const UInt64PackedIteratorCtx = struct { bytes: []const u8 };

pub fn uint64PackedIteratorDecode(ctx: UInt64PackedIteratorCtx) !void {
    var it = (try person_pb.demo.UInt64Packed.valuesPackedIterator(ctx.bytes)) orelse return error.InvalidWireType;
    var sum: u64 = 0;
    while (try it.next()) |value| sum +%= value;
    std.mem.doNotOptimizeAway(sum);
}

pub const UInt32PackedIteratorCtx = struct { bytes: []const u8 };

pub fn uint32PackedIteratorDecode(ctx: UInt32PackedIteratorCtx) !void {
    var it = (try person_pb.demo.UInt32Packed.valuesPackedIterator(ctx.bytes)) orelse return error.InvalidWireType;
    var sum: u32 = 0;
    while (try it.next()) |value| sum +%= value;
    std.mem.doNotOptimizeAway(sum);
}

pub const Int64PackedIteratorCtx = struct { bytes: []const u8 };

pub fn int64PackedIteratorDecode(ctx: Int64PackedIteratorCtx) !void {
    var it = (try person_pb.demo.Int64Packed.valuesPackedIterator(ctx.bytes)) orelse return error.InvalidWireType;
    var sum: i64 = 0;
    while (try it.next()) |value| sum +%= value;
    std.mem.doNotOptimizeAway(sum);
}

pub const SInt32PackedIteratorCtx = struct { bytes: []const u8 };

pub fn sint32PackedIteratorDecode(ctx: SInt32PackedIteratorCtx) !void {
    var it = (try person_pb.demo.SInt32Packed.valuesPackedIterator(ctx.bytes)) orelse return error.InvalidWireType;
    var sum: i32 = 0;
    while (try it.next()) |value| sum +%= value;
    std.mem.doNotOptimizeAway(sum);
}

pub const SInt64PackedIteratorCtx = struct { bytes: []const u8 };

pub fn sint64PackedIteratorDecode(ctx: SInt64PackedIteratorCtx) !void {
    var it = (try person_pb.demo.SInt64Packed.valuesPackedIterator(ctx.bytes)) orelse return error.InvalidWireType;
    var sum: i64 = 0;
    while (try it.next()) |value| sum +%= value;
    std.mem.doNotOptimizeAway(sum);
}

pub const Fixed64PackedBorrowedViewCtx = struct { bytes: []const u8 };

pub fn fixed64PackedBorrowedViewDecode(ctx: Fixed64PackedBorrowedViewCtx) !void {
    const values = (try person_pb.demo.Fixed64Packed.valuesPackedFixedView(ctx.bytes)) orelse return error.InvalidWireType;
    std.mem.doNotOptimizeAway(values.ptr);
}

pub const SFixedPackedBorrowedViewCtx = struct { bytes: []const u8 };

pub fn sfixedPackedBorrowedViewDecode(ctx: SFixedPackedBorrowedViewCtx) !void {
    const values = (try person_pb.demo.SFixedPacked.valuesPackedFixedView(ctx.bytes)) orelse return error.InvalidWireType;
    std.mem.doNotOptimizeAway(values.ptr);
}

pub const SFixed64PackedBorrowedViewCtx = struct { bytes: []const u8 };

pub fn sfixed64PackedBorrowedViewDecode(ctx: SFixed64PackedBorrowedViewCtx) !void {
    const values = (try person_pb.demo.SFixed64Packed.valuesPackedFixedView(ctx.bytes)) orelse return error.InvalidWireType;
    std.mem.doNotOptimizeAway(values.ptr);
}

pub const FloatPackedBorrowedViewCtx = struct { bytes: []const u8 };

pub fn floatPackedBorrowedViewDecode(ctx: FloatPackedBorrowedViewCtx) !void {
    const values = (try person_pb.demo.FloatPacked.valuesPackedFixedView(ctx.bytes)) orelse return error.InvalidWireType;
    std.mem.doNotOptimizeAway(values.ptr);
}

pub const DoublePackedBorrowedViewCtx = struct { bytes: []const u8 };

pub fn doublePackedBorrowedViewDecode(ctx: DoublePackedBorrowedViewCtx) !void {
    const values = (try person_pb.demo.DoublePacked.valuesPackedFixedView(ctx.bytes)) orelse return error.InvalidWireType;
    std.mem.doNotOptimizeAway(values.ptr);
}

pub const DynamicPackedEncodeCtx = struct { message: *const pbz.DynamicMessage, file: *const pbz.FileDescriptor };

pub fn dynamicPackedEncode(ctx: DynamicPackedEncodeCtx) !void {
    const bytes = try ctx.message.encoded(ctx.file);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.message.allocator.free(bytes);
}

pub const DynamicPackedDecodeCtx = struct { allocator: std.mem.Allocator, descriptor: *const pbz.MessageDescriptor, file: *const pbz.FileDescriptor, bytes: []const u8 };

pub fn dynamicPackedDecode(ctx: DynamicPackedDecodeCtx) !void {
    var msg = pbz.DynamicMessage.init(ctx.allocator, ctx.descriptor);
    defer msg.deinit();
    try msg.decode(ctx.file, ctx.bytes);
    std.mem.doNotOptimizeAway(&msg);
}

pub const DynamicFixedPackedEncodeCtx = struct { message: *const pbz.DynamicMessage, file: *const pbz.FileDescriptor };

pub fn dynamicFixedPackedEncode(ctx: DynamicFixedPackedEncodeCtx) !void {
    const bytes = try ctx.message.encoded(ctx.file);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.message.allocator.free(bytes);
}

pub const DynamicFixedPackedDecodeCtx = struct { allocator: std.mem.Allocator, descriptor: *const pbz.MessageDescriptor, file: *const pbz.FileDescriptor, bytes: []const u8 };

pub fn dynamicFixedPackedDecode(ctx: DynamicFixedPackedDecodeCtx) !void {
    var msg = pbz.DynamicMessage.init(ctx.allocator, ctx.descriptor);
    defer msg.deinit();
    try msg.decode(ctx.file, ctx.bytes);
    std.mem.doNotOptimizeAway(&msg);
}

pub const DynamicFixedPackedDecodeReuseCtx = struct { message: *pbz.DynamicMessage, file: *const pbz.FileDescriptor, bytes: []const u8 };

pub fn dynamicFixedPackedDecodeReuse(ctx: DynamicFixedPackedDecodeReuseCtx) !void {
    try ctx.message.decode(ctx.file, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

pub const DynamicFixed64PackedEncodeCtx = struct { message: *const pbz.DynamicMessage, file: *const pbz.FileDescriptor };

pub fn dynamicFixed64PackedEncode(ctx: DynamicFixed64PackedEncodeCtx) !void {
    const bytes = try ctx.message.encoded(ctx.file);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.message.allocator.free(bytes);
}

pub const DynamicFixed64PackedDecodeCtx = struct { allocator: std.mem.Allocator, descriptor: *const pbz.MessageDescriptor, file: *const pbz.FileDescriptor, bytes: []const u8 };

pub fn dynamicFixed64PackedDecode(ctx: DynamicFixed64PackedDecodeCtx) !void {
    var msg = pbz.DynamicMessage.init(ctx.allocator, ctx.descriptor);
    defer msg.deinit();
    try msg.decode(ctx.file, ctx.bytes);
    std.mem.doNotOptimizeAway(&msg);
}

pub const DynamicFixed64PackedDecodeReuseCtx = struct { message: *pbz.DynamicMessage, file: *const pbz.FileDescriptor, bytes: []const u8 };

pub fn dynamicFixed64PackedDecodeReuse(ctx: DynamicFixed64PackedDecodeReuseCtx) !void {
    try ctx.message.decode(ctx.file, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

pub const DynamicSFixedPackedEncodeCtx = struct { message: *const pbz.DynamicMessage, file: *const pbz.FileDescriptor };

pub fn dynamicSFixedPackedEncode(ctx: DynamicSFixedPackedEncodeCtx) !void {
    const bytes = try ctx.message.encoded(ctx.file);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.message.allocator.free(bytes);
}

pub const DynamicSFixedPackedDecodeCtx = struct { allocator: std.mem.Allocator, descriptor: *const pbz.MessageDescriptor, file: *const pbz.FileDescriptor, bytes: []const u8 };

pub fn dynamicSFixedPackedDecode(ctx: DynamicSFixedPackedDecodeCtx) !void {
    var msg = pbz.DynamicMessage.init(ctx.allocator, ctx.descriptor);
    defer msg.deinit();
    try msg.decode(ctx.file, ctx.bytes);
    std.mem.doNotOptimizeAway(&msg);
}

pub const DynamicSFixedPackedDecodeReuseCtx = struct { message: *pbz.DynamicMessage, file: *const pbz.FileDescriptor, bytes: []const u8 };

pub fn dynamicSFixedPackedDecodeReuse(ctx: DynamicSFixedPackedDecodeReuseCtx) !void {
    try ctx.message.decode(ctx.file, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

pub const DynamicSFixed64PackedEncodeCtx = struct { message: *const pbz.DynamicMessage, file: *const pbz.FileDescriptor };

pub fn dynamicSFixed64PackedEncode(ctx: DynamicSFixed64PackedEncodeCtx) !void {
    const bytes = try ctx.message.encoded(ctx.file);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.message.allocator.free(bytes);
}

pub const DynamicSFixed64PackedDecodeCtx = struct { allocator: std.mem.Allocator, descriptor: *const pbz.MessageDescriptor, file: *const pbz.FileDescriptor, bytes: []const u8 };

pub fn dynamicSFixed64PackedDecode(ctx: DynamicSFixed64PackedDecodeCtx) !void {
    var msg = pbz.DynamicMessage.init(ctx.allocator, ctx.descriptor);
    defer msg.deinit();
    try msg.decode(ctx.file, ctx.bytes);
    std.mem.doNotOptimizeAway(&msg);
}

pub const DynamicSFixed64PackedDecodeReuseCtx = struct { message: *pbz.DynamicMessage, file: *const pbz.FileDescriptor, bytes: []const u8 };

pub fn dynamicSFixed64PackedDecodeReuse(ctx: DynamicSFixed64PackedDecodeReuseCtx) !void {
    try ctx.message.decode(ctx.file, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

pub const DynamicFloatPackedEncodeCtx = struct { message: *const pbz.DynamicMessage, file: *const pbz.FileDescriptor };

pub fn dynamicFloatPackedEncode(ctx: DynamicFloatPackedEncodeCtx) !void {
    const bytes = try ctx.message.encoded(ctx.file);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.message.allocator.free(bytes);
}

pub const DynamicFloatPackedDecodeCtx = struct { allocator: std.mem.Allocator, descriptor: *const pbz.MessageDescriptor, file: *const pbz.FileDescriptor, bytes: []const u8 };

pub fn dynamicFloatPackedDecode(ctx: DynamicFloatPackedDecodeCtx) !void {
    var msg = pbz.DynamicMessage.init(ctx.allocator, ctx.descriptor);
    defer msg.deinit();
    try msg.decode(ctx.file, ctx.bytes);
    std.mem.doNotOptimizeAway(&msg);
}

pub const DynamicFloatPackedDecodeReuseCtx = struct { message: *pbz.DynamicMessage, file: *const pbz.FileDescriptor, bytes: []const u8 };

pub fn dynamicFloatPackedDecodeReuse(ctx: DynamicFloatPackedDecodeReuseCtx) !void {
    try ctx.message.decode(ctx.file, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

pub const DynamicDoublePackedEncodeCtx = struct { message: *const pbz.DynamicMessage, file: *const pbz.FileDescriptor };

pub fn dynamicDoublePackedEncode(ctx: DynamicDoublePackedEncodeCtx) !void {
    const bytes = try ctx.message.encoded(ctx.file);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.message.allocator.free(bytes);
}

pub const DynamicDoublePackedDecodeCtx = struct { allocator: std.mem.Allocator, descriptor: *const pbz.MessageDescriptor, file: *const pbz.FileDescriptor, bytes: []const u8 };

pub fn dynamicDoublePackedDecode(ctx: DynamicDoublePackedDecodeCtx) !void {
    var msg = pbz.DynamicMessage.init(ctx.allocator, ctx.descriptor);
    defer msg.deinit();
    try msg.decode(ctx.file, ctx.bytes);
    std.mem.doNotOptimizeAway(&msg);
}

pub const DynamicDoublePackedDecodeReuseCtx = struct { message: *pbz.DynamicMessage, file: *const pbz.FileDescriptor, bytes: []const u8 };

pub fn dynamicDoublePackedDecodeReuse(ctx: DynamicDoublePackedDecodeReuseCtx) !void {
    try ctx.message.decode(ctx.file, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

pub const DynamicUInt64PackedEncodeCtx = struct { message: *const pbz.DynamicMessage, file: *const pbz.FileDescriptor };

pub fn dynamicUInt64PackedEncode(ctx: DynamicUInt64PackedEncodeCtx) !void {
    const bytes = try ctx.message.encoded(ctx.file);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.message.allocator.free(bytes);
}

pub const DynamicUInt64PackedDecodeCtx = struct { allocator: std.mem.Allocator, descriptor: *const pbz.MessageDescriptor, file: *const pbz.FileDescriptor, bytes: []const u8 };

pub fn dynamicUInt64PackedDecode(ctx: DynamicUInt64PackedDecodeCtx) !void {
    var msg = pbz.DynamicMessage.init(ctx.allocator, ctx.descriptor);
    defer msg.deinit();
    try msg.decode(ctx.file, ctx.bytes);
    std.mem.doNotOptimizeAway(&msg);
}

pub const DynamicUInt32PackedEncodeCtx = struct { message: *const pbz.DynamicMessage, file: *const pbz.FileDescriptor };

pub fn dynamicUInt32PackedEncode(ctx: DynamicUInt32PackedEncodeCtx) !void {
    const bytes = try ctx.message.encoded(ctx.file);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.message.allocator.free(bytes);
}

pub const DynamicUInt32PackedDecodeCtx = struct { allocator: std.mem.Allocator, descriptor: *const pbz.MessageDescriptor, file: *const pbz.FileDescriptor, bytes: []const u8 };

pub fn dynamicUInt32PackedDecode(ctx: DynamicUInt32PackedDecodeCtx) !void {
    var msg = pbz.DynamicMessage.init(ctx.allocator, ctx.descriptor);
    defer msg.deinit();
    try msg.decode(ctx.file, ctx.bytes);
    std.mem.doNotOptimizeAway(&msg);
}

pub const DynamicInt64PackedEncodeCtx = struct { message: *const pbz.DynamicMessage, file: *const pbz.FileDescriptor };

pub fn dynamicInt64PackedEncode(ctx: DynamicInt64PackedEncodeCtx) !void {
    const bytes = try ctx.message.encoded(ctx.file);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.message.allocator.free(bytes);
}

pub const DynamicInt64PackedDecodeCtx = struct { allocator: std.mem.Allocator, descriptor: *const pbz.MessageDescriptor, file: *const pbz.FileDescriptor, bytes: []const u8 };

pub fn dynamicInt64PackedDecode(ctx: DynamicInt64PackedDecodeCtx) !void {
    var msg = pbz.DynamicMessage.init(ctx.allocator, ctx.descriptor);
    defer msg.deinit();
    try msg.decode(ctx.file, ctx.bytes);
    std.mem.doNotOptimizeAway(&msg);
}

pub const DynamicSInt32PackedEncodeCtx = struct { message: *const pbz.DynamicMessage, file: *const pbz.FileDescriptor };

pub fn dynamicSInt32PackedEncode(ctx: DynamicSInt32PackedEncodeCtx) !void {
    const bytes = try ctx.message.encoded(ctx.file);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.message.allocator.free(bytes);
}

pub const DynamicSInt32PackedDecodeCtx = struct { allocator: std.mem.Allocator, descriptor: *const pbz.MessageDescriptor, file: *const pbz.FileDescriptor, bytes: []const u8 };

pub fn dynamicSInt32PackedDecode(ctx: DynamicSInt32PackedDecodeCtx) !void {
    var msg = pbz.DynamicMessage.init(ctx.allocator, ctx.descriptor);
    defer msg.deinit();
    try msg.decode(ctx.file, ctx.bytes);
    std.mem.doNotOptimizeAway(&msg);
}

pub const DynamicSInt64PackedEncodeCtx = struct { message: *const pbz.DynamicMessage, file: *const pbz.FileDescriptor };

pub fn dynamicSInt64PackedEncode(ctx: DynamicSInt64PackedEncodeCtx) !void {
    const bytes = try ctx.message.encoded(ctx.file);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.message.allocator.free(bytes);
}

pub const DynamicSInt64PackedDecodeCtx = struct { allocator: std.mem.Allocator, descriptor: *const pbz.MessageDescriptor, file: *const pbz.FileDescriptor, bytes: []const u8 };

pub fn dynamicSInt64PackedDecode(ctx: DynamicSInt64PackedDecodeCtx) !void {
    var msg = pbz.DynamicMessage.init(ctx.allocator, ctx.descriptor);
    defer msg.deinit();
    try msg.decode(ctx.file, ctx.bytes);
    std.mem.doNotOptimizeAway(&msg);
}

pub const DynamicBoolPackedEncodeCtx = struct { message: *const pbz.DynamicMessage, file: *const pbz.FileDescriptor };

pub fn dynamicBoolPackedEncode(ctx: DynamicBoolPackedEncodeCtx) !void {
    const bytes = try ctx.message.encoded(ctx.file);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.message.allocator.free(bytes);
}

pub const DynamicBoolPackedDecodeCtx = struct { allocator: std.mem.Allocator, descriptor: *const pbz.MessageDescriptor, file: *const pbz.FileDescriptor, bytes: []const u8 };

pub fn dynamicBoolPackedDecode(ctx: DynamicBoolPackedDecodeCtx) !void {
    var msg = pbz.DynamicMessage.init(ctx.allocator, ctx.descriptor);
    defer msg.deinit();
    try msg.decode(ctx.file, ctx.bytes);
    std.mem.doNotOptimizeAway(&msg);
}

pub const DynamicEnumPackedEncodeCtx = struct { message: *const pbz.DynamicMessage, file: *const pbz.FileDescriptor };

pub fn dynamicEnumPackedEncode(ctx: DynamicEnumPackedEncodeCtx) !void {
    const bytes = try ctx.message.encoded(ctx.file);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.message.allocator.free(bytes);
}

pub const DynamicEnumPackedDecodeCtx = struct { allocator: std.mem.Allocator, descriptor: *const pbz.MessageDescriptor, file: *const pbz.FileDescriptor, bytes: []const u8 };

pub fn dynamicEnumPackedDecode(ctx: DynamicEnumPackedDecodeCtx) !void {
    var msg = pbz.DynamicMessage.init(ctx.allocator, ctx.descriptor);
    defer msg.deinit();
    try msg.decode(ctx.file, ctx.bytes);
    std.mem.doNotOptimizeAway(&msg);
}
