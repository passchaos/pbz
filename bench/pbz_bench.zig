const std = @import("std");
const pbz = @import("pbz");
const person_pb = @import("person_pb");

const Iterations = struct {
    generated_binary: usize = 20_000,
    dynamic_binary: usize = 10_000,
    json: usize = 2_000,
    text: usize = 1_000,
    packed_binary: usize = 5_000,
};

const BenchmarkSamples: usize = 3;

const BenchResult = struct {
    name: []const u8,
    iterations: usize,
    samples: usize,
    elapsed_ns: i96,
    bytes_per_iter: usize = 0,

    fn print(self: BenchResult) void {
        const ns_per_iter = @as(f64, @floatFromInt(self.elapsed_ns)) / @as(f64, @floatFromInt(self.iterations));
        const ops_per_sec = @as(f64, @floatFromInt(self.iterations)) * @as(f64, @floatFromInt(std.time.ns_per_s)) / @as(f64, @floatFromInt(self.elapsed_ns));
        if (self.bytes_per_iter != 0) {
            const mb_per_sec = @as(f64, @floatFromInt(self.bytes_per_iter * self.iterations)) * @as(f64, @floatFromInt(std.time.ns_per_s)) / @as(f64, @floatFromInt(self.elapsed_ns)) / (1024.0 * 1024.0);
            std.debug.print("{s}: best of {d} x {d} iters, {d} bytes/iter, {d:.2} ns/op, {d:.2} ops/s, {d:.2} MiB/s\n", .{ self.name, self.samples, self.iterations, self.bytes_per_iter, ns_per_iter, ops_per_sec, mb_per_sec });
        } else {
            std.debug.print("{s}: best of {d} x {d} iters, {d:.2} ns/op, {d:.2} ops/s\n", .{ self.name, self.samples, self.iterations, ns_per_iter, ops_per_sec });
        }
    }
};

fn nowNs(io: std.Io) i96 {
    return std.Io.Clock.awake.now(io).nanoseconds;
}

fn runTimed(io: std.Io, name: []const u8, iterations: usize, bytes_per_iter: usize, context: anytype, comptime func: anytype) !BenchResult {
    const warmup_iterations = @max(@as(usize, 1), @min(iterations / 10, @as(usize, 1_000)));
    var warmup_i: usize = 0;
    while (warmup_i < warmup_iterations) : (warmup_i += 1) try func(context);

    var best: i96 = std.math.maxInt(i96);
    var sample: usize = 0;
    while (sample < BenchmarkSamples) : (sample += 1) {
        const start = nowNs(io);
        var i: usize = 0;
        while (i < iterations) : (i += 1) try func(context);
        const elapsed = nowNs(io) - start;
        if (elapsed < best) best = elapsed;
    }
    return .{ .name = name, .iterations = iterations, .samples = BenchmarkSamples, .elapsed_ns = best, .bytes_per_iter = bytes_per_iter };
}

fn makeGeneratedPerson(allocator: std.mem.Allocator) !person_pb.demo.Person {
    var person = person_pb.demo.Person.init();
    errdefer person.deinit(allocator);
    person.id = 7;
    person.name = "Zig";
    person.scores = try allocator.dupe(i32, &.{ 10, 20, 30, 40, 50, 60, 70, 80 });
    try person.counts.put(allocator, "red", 1);
    try person.counts.put(allocator, "green", 2);
    try person.counts.put(allocator, "blue", 3);
    return person;
}

fn makeDynamicPerson(allocator: std.mem.Allocator, desc: *const pbz.MessageDescriptor) !pbz.DynamicMessage {
    var msg = pbz.DynamicMessage.init(allocator, desc);
    errdefer msg.deinit();
    try msg.add(desc.findField("id").?, .{ .int32 = 7 });
    try msg.add(desc.findField("name").?, .{ .string = try allocator.dupe(u8, "Zig") });
    for ([_]i32{ 10, 20, 30, 40, 50, 60, 70, 80 }) |score| try msg.add(desc.findField("scores").?, .{ .int32 = score });
    inline for (.{ .{ "red", 1 }, .{ "green", 2 }, .{ "blue", 3 } }) |entry_data| {
        const entry = try allocator.create(pbz.dynamic.MapEntry);
        entry.* = .{ .key = .{ .string = try allocator.dupe(u8, entry_data[0]) }, .value = .{ .int32 = entry_data[1] } };
        try msg.add(desc.findField("counts").?, .{ .map_entry = entry });
    }
    return msg;
}

fn makeGeneratedScalarMix(allocator: std.mem.Allocator) !person_pb.demo.ScalarMix {
    var msg = person_pb.demo.ScalarMix.init();
    errdefer msg.deinit(allocator);
    msg.active = true;
    msg.count = 12345;
    msg.total = 9_876_543_210;
    msg.delta = -321;
    msg.big_delta = -9_876_543;
    msg.checksum = 0xdead_beef;
    msg.token = 0x0102_0304_0506_0708;
    msg.signed_fixed = -123456;
    msg.signed_big_fixed = -9_876_543_210;
    msg.ratio = 1.25;
    msg.score = 9.5;
    msg.kind = person_pb.demo.BenchKind.BENCH_KIND_BETA.toInt();
    msg.flags = try allocator.dupe(bool, &.{ true, false, true, true, false, true, false, false });
    msg.ids = try allocator.dupe(u64, &.{ 1, 127, 128, 16_384, 1_048_576, 9_876_543_210 });
    return msg;
}

fn makeGeneratedTextBytes(allocator: std.mem.Allocator) !person_pb.demo.TextBytes {
    var msg = person_pb.demo.TextBytes.init();
    errdefer msg.deinit(allocator);
    msg.title = "ASCII title for protobuf";
    msg.payload = "0123456789abcdef0123456789abcdef";
    msg.tags = try allocator.dupe([]const u8, &.{ "alpha", "beta", "gamma", "delta" });
    msg.chunks = try allocator.dupe([]const u8, &.{ "chunk-one", "chunk-two", "chunk-three", "chunk-four" });
    return msg;
}

fn audit(actor: []const u8, at_unix: i64) person_pb.demo.Complex.Audit {
    var out = person_pb.demo.Complex.Audit.init();
    out.actor = actor;
    out.at_unix = at_unix;
    return out;
}

fn makeGeneratedComplex(allocator: std.mem.Allocator) !person_pb.demo.Complex {
    var complex = person_pb.demo.Complex.init();
    errdefer complex.deinit(allocator);
    complex.id = 42;
    complex.audit = try audit("tester", 12345).cloneOwned(allocator);
    const history = try allocator.alloc(person_pb.demo.Complex.Audit, 2);
    history[0] = try audit("creator", 12345).cloneOwned(allocator);
    history[1] = try audit("reviewer", 67890).cloneOwned(allocator);
    complex.history = history;
    try complex.audits.put(allocator, "latest", try audit("reviewer", 67890).cloneOwned(allocator));
    try complex.audits.put(allocator, "created", try audit("creator", 12345).cloneOwned(allocator));
    complex.subject = .{ .audit_subject = try audit("subject", 777).cloneOwned(allocator) };
    return complex;
}

fn makeGeneratedPacked(allocator: std.mem.Allocator) !person_pb.demo.Packed {
    var packed_msg = person_pb.demo.Packed.init();
    errdefer packed_msg.deinit(allocator);
    const values = try allocator.alloc(i32, 1024);
    for (values, 0..) |*value, i| value.* = @intCast(i % 4096);
    packed_msg.values = values;
    return packed_msg;
}

fn makeDynamicPacked(allocator: std.mem.Allocator, desc: *const pbz.MessageDescriptor) !pbz.DynamicMessage {
    var msg = pbz.DynamicMessage.init(allocator, desc);
    errdefer msg.deinit();
    var i: usize = 0;
    while (i < 1024) : (i += 1) try msg.add(desc.findField("values").?, .{ .int32 = @intCast(i % 4096) });
    return msg;
}

fn makeGeneratedFixedPacked(allocator: std.mem.Allocator) !person_pb.demo.FixedPacked {
    var packed_msg = person_pb.demo.FixedPacked.init();
    errdefer packed_msg.deinit(allocator);
    const values = try allocator.alloc(u32, 1024);
    for (values, 0..) |*value, i| value.* = @intCast(i * 3 + 1);
    packed_msg.values = values;
    return packed_msg;
}

fn makeGeneratedFixed64Packed(allocator: std.mem.Allocator) !person_pb.demo.Fixed64Packed {
    var packed_msg = person_pb.demo.Fixed64Packed.init();
    errdefer packed_msg.deinit(allocator);
    const values = try allocator.alloc(u64, 1024);
    for (values, 0..) |*value, i| value.* = @intCast(i * 5 + 1);
    packed_msg.values = values;
    return packed_msg;
}

fn makeGeneratedUInt64Packed(allocator: std.mem.Allocator) !person_pb.demo.UInt64Packed {
    var packed_msg = person_pb.demo.UInt64Packed.init();
    errdefer packed_msg.deinit(allocator);
    const values = try allocator.alloc(u64, 1024);
    for (values, 0..) |*value, i| value.* = @intCast((@as(u64, i) << 21) + i * 17 + 1);
    packed_msg.values = values;
    return packed_msg;
}

fn makeGeneratedSInt64Packed(allocator: std.mem.Allocator) !person_pb.demo.SInt64Packed {
    var packed_msg = person_pb.demo.SInt64Packed.init();
    errdefer packed_msg.deinit(allocator);
    const values = try allocator.alloc(i64, 1024);
    for (values, 0..) |*value, i| {
        const magnitude: i64 = @intCast((@as(u64, i) << 20) + i * 13 + 1);
        value.* = if ((i & 1) == 0) magnitude else -magnitude;
    }
    packed_msg.values = values;
    return packed_msg;
}

fn makeGeneratedBoolPacked(allocator: std.mem.Allocator) !person_pb.demo.BoolPacked {
    var packed_msg = person_pb.demo.BoolPacked.init();
    errdefer packed_msg.deinit(allocator);
    const values = try allocator.alloc(bool, 1024);
    for (values, 0..) |*value, i| value.* = (i % 3) != 0;
    packed_msg.values = values;
    return packed_msg;
}

fn makeGeneratedEnumPacked(allocator: std.mem.Allocator) !person_pb.demo.EnumPacked {
    var packed_msg = person_pb.demo.EnumPacked.init();
    errdefer packed_msg.deinit(allocator);
    const values = try allocator.alloc(i32, 1024);
    for (values, 0..) |*value, i| value.* = @intCast(i % 3);
    packed_msg.values = values;
    return packed_msg;
}

fn makeDynamicFixedPacked(allocator: std.mem.Allocator, desc: *const pbz.MessageDescriptor) !pbz.DynamicMessage {
    var msg = pbz.DynamicMessage.init(allocator, desc);
    errdefer msg.deinit();
    var i: usize = 0;
    while (i < 1024) : (i += 1) try msg.add(desc.findField("values").?, .{ .fixed32 = @intCast(i * 3 + 1) });
    return msg;
}

fn makeDynamicFixed64Packed(allocator: std.mem.Allocator, desc: *const pbz.MessageDescriptor) !pbz.DynamicMessage {
    var msg = pbz.DynamicMessage.init(allocator, desc);
    errdefer msg.deinit();
    var i: usize = 0;
    while (i < 1024) : (i += 1) try msg.add(desc.findField("values").?, .{ .fixed64 = @intCast(i * 5 + 1) });
    return msg;
}

fn makeDynamicUInt64Packed(allocator: std.mem.Allocator, desc: *const pbz.MessageDescriptor) !pbz.DynamicMessage {
    var msg = pbz.DynamicMessage.init(allocator, desc);
    errdefer msg.deinit();
    var i: usize = 0;
    while (i < 1024) : (i += 1) try msg.add(desc.findField("values").?, .{ .uint64 = @intCast((@as(u64, i) << 21) + i * 17 + 1) });
    return msg;
}

fn makeDynamicSInt64Packed(allocator: std.mem.Allocator, desc: *const pbz.MessageDescriptor) !pbz.DynamicMessage {
    var msg = pbz.DynamicMessage.init(allocator, desc);
    errdefer msg.deinit();
    var i: usize = 0;
    while (i < 1024) : (i += 1) {
        const magnitude: i64 = @intCast((@as(u64, i) << 20) + i * 13 + 1);
        try msg.add(desc.findField("values").?, .{ .sint64 = if ((i & 1) == 0) magnitude else -magnitude });
    }
    return msg;
}

fn makeDynamicBoolPacked(allocator: std.mem.Allocator, desc: *const pbz.MessageDescriptor) !pbz.DynamicMessage {
    var msg = pbz.DynamicMessage.init(allocator, desc);
    errdefer msg.deinit();
    var i: usize = 0;
    while (i < 1024) : (i += 1) try msg.add(desc.findField("values").?, .{ .boolean = (i % 3) != 0 });
    return msg;
}

fn makeDynamicEnumPacked(allocator: std.mem.Allocator, desc: *const pbz.MessageDescriptor) !pbz.DynamicMessage {
    var msg = pbz.DynamicMessage.init(allocator, desc);
    errdefer msg.deinit();
    var i: usize = 0;
    while (i < 1024) : (i += 1) try msg.add(desc.findField("values").?, .{ .enumeration = @intCast(i % 3) });
    return msg;
}

const GeneratedScalarMixEncodeCtx = struct { allocator: std.mem.Allocator, message: *const person_pb.demo.ScalarMix };
fn generatedScalarMixEncode(ctx: GeneratedScalarMixEncodeCtx) !void {
    const bytes = try ctx.message.encode(ctx.allocator);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.allocator.free(bytes);
}

const GeneratedScalarMixWriteToCtx = struct { writer: *pbz.Writer, message: *const person_pb.demo.ScalarMix };
fn generatedScalarMixWriteToReuse(ctx: GeneratedScalarMixWriteToCtx) !void {
    ctx.writer.clearRetainingCapacity();
    try ctx.message.writeToAssumeCapacity(ctx.writer);
    std.mem.doNotOptimizeAway(ctx.writer.slice().ptr);
}

const GeneratedScalarMixEncodeIntoCtx = struct { buffer: []u8, message: *const person_pb.demo.ScalarMix };
fn generatedScalarMixEncodeIntoReuse(ctx: GeneratedScalarMixEncodeIntoCtx) !void {
    const bytes = try ctx.message.encodeIntoAssumeCapacity(ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

const GeneratedScalarMixDecodeCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };
fn generatedScalarMixDecode(ctx: GeneratedScalarMixDecodeCtx) !void {
    var decoded = try person_pb.demo.ScalarMix.decode(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

const GeneratedScalarMixDecodeReuseCtx = struct { allocator: std.mem.Allocator, bytes: []const u8, message: *person_pb.demo.ScalarMix };
fn generatedScalarMixDecodeReuse(ctx: GeneratedScalarMixDecodeReuseCtx) !void {
    try ctx.message.decodeReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

const GeneratedTextBytesEncodeCtx = struct { allocator: std.mem.Allocator, message: *const person_pb.demo.TextBytes };
fn generatedTextBytesEncode(ctx: GeneratedTextBytesEncodeCtx) !void {
    const bytes = try ctx.message.encode(ctx.allocator);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.allocator.free(bytes);
}

const GeneratedTextBytesWriteToCtx = struct { writer: *pbz.Writer, message: *const person_pb.demo.TextBytes };
fn generatedTextBytesWriteToReuse(ctx: GeneratedTextBytesWriteToCtx) !void {
    ctx.writer.clearRetainingCapacity();
    try ctx.message.writeToAssumeCapacity(ctx.writer);
    std.mem.doNotOptimizeAway(ctx.writer.slice().ptr);
}

fn generatedTextBytesTrustedUtf8WriteToReuse(ctx: GeneratedTextBytesWriteToCtx) !void {
    ctx.writer.clearRetainingCapacity();
    const msg = ctx.message;
    if (msg.title.len != 0) ctx.writer.writeStringAssumeCapacity(1, msg.title);
    if (msg.payload.len != 0) ctx.writer.writeBytesAssumeCapacity(2, msg.payload);
    for (msg.tags) |tag| ctx.writer.writeStringAssumeCapacity(3, tag);
    for (msg.chunks) |chunk| ctx.writer.writeBytesAssumeCapacity(4, chunk);
    std.mem.doNotOptimizeAway(ctx.writer.slice().ptr);
}

const GeneratedTextBytesEncodeIntoCtx = struct { buffer: []u8, message: *const person_pb.demo.TextBytes };
fn generatedTextBytesEncodeIntoReuse(ctx: GeneratedTextBytesEncodeIntoCtx) !void {
    const bytes = try ctx.message.encodeIntoAssumeCapacity(ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

const GeneratedTextBytesDecodeCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };
fn generatedTextBytesDecode(ctx: GeneratedTextBytesDecodeCtx) !void {
    var decoded = try person_pb.demo.TextBytes.decode(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

const GeneratedComplexEncodeCtx = struct { allocator: std.mem.Allocator, message: *const person_pb.demo.Complex };
fn generatedComplexEncode(ctx: GeneratedComplexEncodeCtx) !void {
    const bytes = try ctx.message.encode(ctx.allocator);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.allocator.free(bytes);
}

const GeneratedComplexWriteToCtx = struct { writer: *pbz.Writer, message: *const person_pb.demo.Complex };
fn generatedComplexWriteToReuse(ctx: GeneratedComplexWriteToCtx) !void {
    ctx.writer.clearRetainingCapacity();
    try ctx.message.writeToAssumeCapacity(ctx.writer);
    std.mem.doNotOptimizeAway(ctx.writer.slice().ptr);
}

const GeneratedComplexEncodeIntoCtx = struct { buffer: []u8, message: *const person_pb.demo.Complex };
fn generatedComplexEncodeIntoReuse(ctx: GeneratedComplexEncodeIntoCtx) !void {
    const bytes = try ctx.message.encodeIntoAssumeCapacity(ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

const GeneratedComplexDecodeCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };
fn generatedComplexDecode(ctx: GeneratedComplexDecodeCtx) !void {
    var decoded = try person_pb.demo.Complex.decode(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

const GeneratedComplexJsonStringifyCtx = struct { allocator: std.mem.Allocator, message: *const person_pb.demo.Complex };
fn generatedComplexJsonStringify(ctx: GeneratedComplexJsonStringifyCtx) !void {
    const json = try ctx.message.jsonStringifyAlloc(ctx.allocator);
    std.mem.doNotOptimizeAway(json.ptr);
    ctx.allocator.free(json);
}

const GeneratedComplexJsonParseCtx = struct { allocator: std.mem.Allocator, json: []const u8 };
fn generatedComplexJsonParse(ctx: GeneratedComplexJsonParseCtx) !void {
    var decoded = try person_pb.demo.Complex.jsonParse(ctx.allocator, ctx.json);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

const GeneratedComplexTextFormatCtx = struct { allocator: std.mem.Allocator, message: *const person_pb.demo.Complex };
fn generatedComplexTextFormat(ctx: GeneratedComplexTextFormatCtx) !void {
    const text = try ctx.message.formatTextAlloc(ctx.allocator);
    std.mem.doNotOptimizeAway(text.ptr);
    ctx.allocator.free(text);
}

const GeneratedComplexTextParseCtx = struct { allocator: std.mem.Allocator, text: []const u8 };
fn generatedComplexTextParse(ctx: GeneratedComplexTextParseCtx) !void {
    var decoded = try person_pb.demo.Complex.parseText(ctx.allocator, ctx.text);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

const GeneratedComplexDeterministicEncodeCtx = struct { allocator: std.mem.Allocator, message: *const person_pb.demo.Complex };
fn generatedComplexDeterministicEncode(ctx: GeneratedComplexDeterministicEncodeCtx) !void {
    const bytes = try ctx.message.encodeDeterministic(ctx.allocator);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.allocator.free(bytes);
}

const GeneratedComplexDeterministicEncodeIntoCtx = struct { allocator: std.mem.Allocator, buffer: []u8, message: *const person_pb.demo.Complex };
fn generatedComplexDeterministicEncodeIntoReuse(ctx: GeneratedComplexDeterministicEncodeIntoCtx) !void {
    const bytes = try ctx.message.encodeDeterministicIntoAssumeCapacity(ctx.allocator, ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

const GeneratedPackedEncodeCtx = struct { allocator: std.mem.Allocator, message: *const person_pb.demo.Packed };
fn generatedPackedEncode(ctx: GeneratedPackedEncodeCtx) !void {
    const bytes = try ctx.message.encode(ctx.allocator);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.allocator.free(bytes);
}

const GeneratedPackedWriteToCtx = struct { writer: *pbz.Writer, message: *const person_pb.demo.Packed };
fn generatedPackedWriteToReuse(ctx: GeneratedPackedWriteToCtx) !void {
    ctx.writer.clearRetainingCapacity();
    try ctx.message.writeToAssumeCapacity(ctx.writer);
    std.mem.doNotOptimizeAway(ctx.writer.slice().ptr);
}

const GeneratedPackedEncodeIntoCtx = struct { buffer: []u8, message: *const person_pb.demo.Packed };
fn generatedPackedEncodeIntoReuse(ctx: GeneratedPackedEncodeIntoCtx) !void {
    const bytes = try ctx.message.encodeIntoAssumeCapacity(ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

const GeneratedPackedDecodeCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };
fn generatedPackedDecode(ctx: GeneratedPackedDecodeCtx) !void {
    var decoded = try person_pb.demo.Packed.decode(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

const GeneratedFixedPackedEncodeCtx = struct { allocator: std.mem.Allocator, message: *const person_pb.demo.FixedPacked };
fn generatedFixedPackedEncode(ctx: GeneratedFixedPackedEncodeCtx) !void {
    const bytes = try ctx.message.encode(ctx.allocator);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.allocator.free(bytes);
}

const GeneratedFixedPackedEncodeIntoCtx = struct { buffer: []u8, message: *const person_pb.demo.FixedPacked };
fn generatedFixedPackedEncodeIntoReuse(ctx: GeneratedFixedPackedEncodeIntoCtx) !void {
    const bytes = try ctx.message.encodeIntoAssumeCapacity(ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

const GeneratedFixedPackedSlicesCtx = struct { message: *const person_pb.demo.FixedPacked };
fn generatedFixedPackedBorrowedSlices(ctx: GeneratedFixedPackedSlicesCtx) !void {
    var header: [20]u8 = undefined;
    const slices = try person_pb.demo.FixedPacked.valuesPackedFixed32Slices(&header, ctx.message.values);
    std.mem.doNotOptimizeAway(slices.header.ptr);
    std.mem.doNotOptimizeAway(slices.payload.ptr);
}

const GeneratedFixedPackedDecodeCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };
fn generatedFixedPackedDecode(ctx: GeneratedFixedPackedDecodeCtx) !void {
    var decoded = try person_pb.demo.FixedPacked.decode(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

const FixedPackedBorrowedViewCtx = struct { bytes: []const u8 };
fn fixedPackedBorrowedViewDecode(ctx: FixedPackedBorrowedViewCtx) !void {
    const values = (try person_pb.demo.FixedPacked.valuesPackedFixed32View(ctx.bytes)) orelse return error.InvalidWireType;
    std.mem.doNotOptimizeAway(values.ptr);
}

const GeneratedFixed64PackedEncodeCtx = struct { allocator: std.mem.Allocator, message: *const person_pb.demo.Fixed64Packed };
fn generatedFixed64PackedEncode(ctx: GeneratedFixed64PackedEncodeCtx) !void {
    const bytes = try ctx.message.encode(ctx.allocator);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.allocator.free(bytes);
}

const GeneratedFixed64PackedEncodeIntoCtx = struct { buffer: []u8, message: *const person_pb.demo.Fixed64Packed };
fn generatedFixed64PackedEncodeIntoReuse(ctx: GeneratedFixed64PackedEncodeIntoCtx) !void {
    const bytes = try ctx.message.encodeIntoAssumeCapacity(ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

const GeneratedFixed64PackedSlicesCtx = struct { message: *const person_pb.demo.Fixed64Packed };
fn generatedFixed64PackedBorrowedSlices(ctx: GeneratedFixed64PackedSlicesCtx) !void {
    var header: [20]u8 = undefined;
    const slices = try person_pb.demo.Fixed64Packed.valuesPackedFixedSlices(&header, ctx.message.values);
    std.mem.doNotOptimizeAway(slices.header.ptr);
    std.mem.doNotOptimizeAway(slices.payload.ptr);
}

const GeneratedFixed64PackedDecodeCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };
fn generatedFixed64PackedDecode(ctx: GeneratedFixed64PackedDecodeCtx) !void {
    var decoded = try person_pb.demo.Fixed64Packed.decode(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

const GeneratedUInt64PackedEncodeCtx = struct { allocator: std.mem.Allocator, message: *const person_pb.demo.UInt64Packed };
fn generatedUInt64PackedEncode(ctx: GeneratedUInt64PackedEncodeCtx) !void {
    const bytes = try ctx.message.encode(ctx.allocator);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.allocator.free(bytes);
}

const GeneratedUInt64PackedEncodeIntoCtx = struct { buffer: []u8, message: *const person_pb.demo.UInt64Packed };
fn generatedUInt64PackedEncodeIntoReuse(ctx: GeneratedUInt64PackedEncodeIntoCtx) !void {
    const bytes = try ctx.message.encodeIntoAssumeCapacity(ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

const GeneratedUInt64PackedDecodeCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };
fn generatedUInt64PackedDecode(ctx: GeneratedUInt64PackedDecodeCtx) !void {
    var decoded = try person_pb.demo.UInt64Packed.decode(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

const GeneratedUInt64PackedDecodeReuseCtx = struct { allocator: std.mem.Allocator, bytes: []const u8, message: *person_pb.demo.UInt64Packed };
fn generatedUInt64PackedDecodeReuse(ctx: GeneratedUInt64PackedDecodeReuseCtx) !void {
    try ctx.message.decodeReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

const GeneratedSInt64PackedEncodeCtx = struct { allocator: std.mem.Allocator, message: *const person_pb.demo.SInt64Packed };
fn generatedSInt64PackedEncode(ctx: GeneratedSInt64PackedEncodeCtx) !void {
    const bytes = try ctx.message.encode(ctx.allocator);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.allocator.free(bytes);
}

const GeneratedSInt64PackedEncodeIntoCtx = struct { buffer: []u8, message: *const person_pb.demo.SInt64Packed };
fn generatedSInt64PackedEncodeIntoReuse(ctx: GeneratedSInt64PackedEncodeIntoCtx) !void {
    const bytes = try ctx.message.encodeIntoAssumeCapacity(ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

const GeneratedSInt64PackedDecodeCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };
fn generatedSInt64PackedDecode(ctx: GeneratedSInt64PackedDecodeCtx) !void {
    var decoded = try person_pb.demo.SInt64Packed.decode(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

const GeneratedBoolPackedEncodeCtx = struct { allocator: std.mem.Allocator, message: *const person_pb.demo.BoolPacked };
fn generatedBoolPackedEncode(ctx: GeneratedBoolPackedEncodeCtx) !void {
    const bytes = try ctx.message.encode(ctx.allocator);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.allocator.free(bytes);
}

const GeneratedBoolPackedEncodeIntoCtx = struct { buffer: []u8, message: *const person_pb.demo.BoolPacked };
fn generatedBoolPackedEncodeIntoReuse(ctx: GeneratedBoolPackedEncodeIntoCtx) !void {
    const bytes = try ctx.message.encodeIntoAssumeCapacity(ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

const GeneratedBoolPackedDecodeCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };
fn generatedBoolPackedDecode(ctx: GeneratedBoolPackedDecodeCtx) !void {
    var decoded = try person_pb.demo.BoolPacked.decode(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

const GeneratedEnumPackedEncodeCtx = struct { allocator: std.mem.Allocator, message: *const person_pb.demo.EnumPacked };
fn generatedEnumPackedEncode(ctx: GeneratedEnumPackedEncodeCtx) !void {
    const bytes = try ctx.message.encode(ctx.allocator);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.allocator.free(bytes);
}

const GeneratedEnumPackedEncodeIntoCtx = struct { buffer: []u8, message: *const person_pb.demo.EnumPacked };
fn generatedEnumPackedEncodeIntoReuse(ctx: GeneratedEnumPackedEncodeIntoCtx) !void {
    const bytes = try ctx.message.encodeIntoAssumeCapacity(ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

const GeneratedEnumPackedDecodeCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };
fn generatedEnumPackedDecode(ctx: GeneratedEnumPackedDecodeCtx) !void {
    var decoded = try person_pb.demo.EnumPacked.decode(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

const GeneratedEnumPackedDecodeReuseCtx = struct { allocator: std.mem.Allocator, bytes: []const u8, message: *person_pb.demo.EnumPacked };
fn generatedEnumPackedDecodeReuse(ctx: GeneratedEnumPackedDecodeReuseCtx) !void {
    try ctx.message.decodeReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

const UInt64PackedIteratorCtx = struct { bytes: []const u8 };
fn uint64PackedIteratorDecode(ctx: UInt64PackedIteratorCtx) !void {
    var it = (try pbz.wire.packedUInt64FieldIterator(ctx.bytes, 1)) orelse return error.InvalidWireType;
    var sum: u64 = 0;
    while (try it.next()) |value| sum +%= value;
    std.mem.doNotOptimizeAway(sum);
}

const SInt64PackedIteratorCtx = struct { bytes: []const u8 };
fn sint64PackedIteratorDecode(ctx: SInt64PackedIteratorCtx) !void {
    var it = (try pbz.wire.packedSInt64FieldIterator(ctx.bytes, 1)) orelse return error.InvalidWireType;
    var sum: i64 = 0;
    while (try it.next()) |value| sum +%= value;
    std.mem.doNotOptimizeAway(sum);
}

const Fixed64PackedBorrowedViewCtx = struct { bytes: []const u8 };
fn fixed64PackedBorrowedViewDecode(ctx: Fixed64PackedBorrowedViewCtx) !void {
    const values = (try person_pb.demo.Fixed64Packed.valuesPackedFixedView(ctx.bytes)) orelse return error.InvalidWireType;
    std.mem.doNotOptimizeAway(values.ptr);
}

const DynamicPackedEncodeCtx = struct { message: *const pbz.DynamicMessage, file: *const pbz.FileDescriptor };
fn dynamicPackedEncode(ctx: DynamicPackedEncodeCtx) !void {
    const bytes = try ctx.message.encoded(ctx.file);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.message.allocator.free(bytes);
}

const DynamicPackedDecodeCtx = struct { allocator: std.mem.Allocator, descriptor: *const pbz.MessageDescriptor, file: *const pbz.FileDescriptor, bytes: []const u8 };
fn dynamicPackedDecode(ctx: DynamicPackedDecodeCtx) !void {
    var msg = pbz.DynamicMessage.init(ctx.allocator, ctx.descriptor);
    defer msg.deinit();
    try msg.decode(ctx.file, ctx.bytes);
    std.mem.doNotOptimizeAway(&msg);
}

const DynamicFixedPackedEncodeCtx = struct { message: *const pbz.DynamicMessage, file: *const pbz.FileDescriptor };
fn dynamicFixedPackedEncode(ctx: DynamicFixedPackedEncodeCtx) !void {
    const bytes = try ctx.message.encoded(ctx.file);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.message.allocator.free(bytes);
}

const DynamicFixedPackedDecodeCtx = struct { allocator: std.mem.Allocator, descriptor: *const pbz.MessageDescriptor, file: *const pbz.FileDescriptor, bytes: []const u8 };
fn dynamicFixedPackedDecode(ctx: DynamicFixedPackedDecodeCtx) !void {
    var msg = pbz.DynamicMessage.init(ctx.allocator, ctx.descriptor);
    defer msg.deinit();
    try msg.decode(ctx.file, ctx.bytes);
    std.mem.doNotOptimizeAway(&msg);
}

const DynamicFixedPackedDecodeReuseCtx = struct { message: *pbz.DynamicMessage, file: *const pbz.FileDescriptor, bytes: []const u8 };
fn dynamicFixedPackedDecodeReuse(ctx: DynamicFixedPackedDecodeReuseCtx) !void {
    try ctx.message.decode(ctx.file, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

const DynamicFixed64PackedEncodeCtx = struct { message: *const pbz.DynamicMessage, file: *const pbz.FileDescriptor };
fn dynamicFixed64PackedEncode(ctx: DynamicFixed64PackedEncodeCtx) !void {
    const bytes = try ctx.message.encoded(ctx.file);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.message.allocator.free(bytes);
}

const DynamicFixed64PackedDecodeCtx = struct { allocator: std.mem.Allocator, descriptor: *const pbz.MessageDescriptor, file: *const pbz.FileDescriptor, bytes: []const u8 };
fn dynamicFixed64PackedDecode(ctx: DynamicFixed64PackedDecodeCtx) !void {
    var msg = pbz.DynamicMessage.init(ctx.allocator, ctx.descriptor);
    defer msg.deinit();
    try msg.decode(ctx.file, ctx.bytes);
    std.mem.doNotOptimizeAway(&msg);
}

const DynamicFixed64PackedDecodeReuseCtx = struct { message: *pbz.DynamicMessage, file: *const pbz.FileDescriptor, bytes: []const u8 };
fn dynamicFixed64PackedDecodeReuse(ctx: DynamicFixed64PackedDecodeReuseCtx) !void {
    try ctx.message.decode(ctx.file, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

const DynamicUInt64PackedEncodeCtx = struct { message: *const pbz.DynamicMessage, file: *const pbz.FileDescriptor };
fn dynamicUInt64PackedEncode(ctx: DynamicUInt64PackedEncodeCtx) !void {
    const bytes = try ctx.message.encoded(ctx.file);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.message.allocator.free(bytes);
}

const DynamicUInt64PackedDecodeCtx = struct { allocator: std.mem.Allocator, descriptor: *const pbz.MessageDescriptor, file: *const pbz.FileDescriptor, bytes: []const u8 };
fn dynamicUInt64PackedDecode(ctx: DynamicUInt64PackedDecodeCtx) !void {
    var msg = pbz.DynamicMessage.init(ctx.allocator, ctx.descriptor);
    defer msg.deinit();
    try msg.decode(ctx.file, ctx.bytes);
    std.mem.doNotOptimizeAway(&msg);
}

const DynamicSInt64PackedEncodeCtx = struct { message: *const pbz.DynamicMessage, file: *const pbz.FileDescriptor };
fn dynamicSInt64PackedEncode(ctx: DynamicSInt64PackedEncodeCtx) !void {
    const bytes = try ctx.message.encoded(ctx.file);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.message.allocator.free(bytes);
}

const DynamicSInt64PackedDecodeCtx = struct { allocator: std.mem.Allocator, descriptor: *const pbz.MessageDescriptor, file: *const pbz.FileDescriptor, bytes: []const u8 };
fn dynamicSInt64PackedDecode(ctx: DynamicSInt64PackedDecodeCtx) !void {
    var msg = pbz.DynamicMessage.init(ctx.allocator, ctx.descriptor);
    defer msg.deinit();
    try msg.decode(ctx.file, ctx.bytes);
    std.mem.doNotOptimizeAway(&msg);
}

const DynamicBoolPackedEncodeCtx = struct { message: *const pbz.DynamicMessage, file: *const pbz.FileDescriptor };
fn dynamicBoolPackedEncode(ctx: DynamicBoolPackedEncodeCtx) !void {
    const bytes = try ctx.message.encoded(ctx.file);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.message.allocator.free(bytes);
}

const DynamicBoolPackedDecodeCtx = struct { allocator: std.mem.Allocator, descriptor: *const pbz.MessageDescriptor, file: *const pbz.FileDescriptor, bytes: []const u8 };
fn dynamicBoolPackedDecode(ctx: DynamicBoolPackedDecodeCtx) !void {
    var msg = pbz.DynamicMessage.init(ctx.allocator, ctx.descriptor);
    defer msg.deinit();
    try msg.decode(ctx.file, ctx.bytes);
    std.mem.doNotOptimizeAway(&msg);
}

const DynamicEnumPackedEncodeCtx = struct { message: *const pbz.DynamicMessage, file: *const pbz.FileDescriptor };
fn dynamicEnumPackedEncode(ctx: DynamicEnumPackedEncodeCtx) !void {
    const bytes = try ctx.message.encoded(ctx.file);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.message.allocator.free(bytes);
}

const DynamicEnumPackedDecodeCtx = struct { allocator: std.mem.Allocator, descriptor: *const pbz.MessageDescriptor, file: *const pbz.FileDescriptor, bytes: []const u8 };
fn dynamicEnumPackedDecode(ctx: DynamicEnumPackedDecodeCtx) !void {
    var msg = pbz.DynamicMessage.init(ctx.allocator, ctx.descriptor);
    defer msg.deinit();
    try msg.decode(ctx.file, ctx.bytes);
    std.mem.doNotOptimizeAway(&msg);
}

const GeneratedEncodeCtx = struct { allocator: std.mem.Allocator, person: *const person_pb.demo.Person };
fn generatedEncode(ctx: GeneratedEncodeCtx) !void {
    const bytes = try ctx.person.encode(ctx.allocator);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.allocator.free(bytes);
}

const GeneratedWriteToCtx = struct { writer: *pbz.Writer, person: *const person_pb.demo.Person };
fn generatedWriteToReuse(ctx: GeneratedWriteToCtx) !void {
    ctx.writer.clearRetainingCapacity();
    try ctx.person.writeToAssumeCapacity(ctx.writer);
    std.mem.doNotOptimizeAway(ctx.writer.slice().ptr);
}

const GeneratedEncodeIntoCtx = struct { buffer: []u8, person: *const person_pb.demo.Person };
fn generatedEncodeIntoReuse(ctx: GeneratedEncodeIntoCtx) !void {
    const bytes = try ctx.person.encodeIntoAssumeCapacity(ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

const GeneratedDeterministicEncodeCtx = struct { allocator: std.mem.Allocator, person: *const person_pb.demo.Person };
fn generatedDeterministicEncode(ctx: GeneratedDeterministicEncodeCtx) !void {
    const bytes = try ctx.person.encodeDeterministic(ctx.allocator);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.allocator.free(bytes);
}

const GeneratedDeterministicEncodeIntoCtx = struct { allocator: std.mem.Allocator, buffer: []u8, person: *const person_pb.demo.Person };
fn generatedDeterministicEncodeIntoReuse(ctx: GeneratedDeterministicEncodeIntoCtx) !void {
    const bytes = try ctx.person.encodeDeterministicIntoAssumeCapacity(ctx.allocator, ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

const GeneratedDecodeCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };
fn generatedDecode(ctx: GeneratedDecodeCtx) !void {
    var decoded = try person_pb.demo.Person.decode(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

const DynamicEncodeCtx = struct { message: *const pbz.DynamicMessage, file: *const pbz.FileDescriptor };
fn dynamicEncode(ctx: DynamicEncodeCtx) !void {
    const bytes = try ctx.message.encoded(ctx.file);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.message.allocator.free(bytes);
}

const DynamicDecodeCtx = struct { allocator: std.mem.Allocator, descriptor: *const pbz.MessageDescriptor, file: *const pbz.FileDescriptor, bytes: []const u8 };
fn dynamicDecode(ctx: DynamicDecodeCtx) !void {
    var msg = pbz.DynamicMessage.init(ctx.allocator, ctx.descriptor);
    defer msg.deinit();
    try msg.decode(ctx.file, ctx.bytes);
    std.mem.doNotOptimizeAway(&msg);
}

const GeneratedJsonStringifyCtx = struct { allocator: std.mem.Allocator, person: *const person_pb.demo.Person };
fn generatedJsonStringify(ctx: GeneratedJsonStringifyCtx) !void {
    const json = try ctx.person.jsonStringifyAlloc(ctx.allocator);
    std.mem.doNotOptimizeAway(json.ptr);
    ctx.allocator.free(json);
}

const GeneratedJsonParseCtx = struct { allocator: std.mem.Allocator, json: []const u8 };
fn generatedJsonParse(ctx: GeneratedJsonParseCtx) !void {
    var decoded = try person_pb.demo.Person.jsonParse(ctx.allocator, ctx.json);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

const DynamicJsonStringifyCtx = struct { allocator: std.mem.Allocator, file: *const pbz.FileDescriptor, message: *const pbz.DynamicMessage };
fn dynamicJsonStringify(ctx: DynamicJsonStringifyCtx) !void {
    const json = try pbz.stringifyJsonAlloc(ctx.allocator, ctx.file, ctx.message, .{});
    std.mem.doNotOptimizeAway(json.ptr);
    ctx.allocator.free(json);
}

const DynamicJsonParseCtx = struct { allocator: std.mem.Allocator, file: *const pbz.FileDescriptor, descriptor: *const pbz.MessageDescriptor, json: []const u8 };
fn dynamicJsonParse(ctx: DynamicJsonParseCtx) !void {
    var msg = try pbz.parseJsonAlloc(ctx.allocator, ctx.file, ctx.descriptor, ctx.json, .{});
    std.mem.doNotOptimizeAway(&msg);
    msg.deinit();
}

const GeneratedTextFormatCtx = struct { allocator: std.mem.Allocator, person: *const person_pb.demo.Person };
fn generatedTextFormat(ctx: GeneratedTextFormatCtx) !void {
    const text = try ctx.person.formatTextAlloc(ctx.allocator);
    std.mem.doNotOptimizeAway(text.ptr);
    ctx.allocator.free(text);
}

const GeneratedTextParseCtx = struct { allocator: std.mem.Allocator, text: []const u8 };
fn generatedTextParse(ctx: GeneratedTextParseCtx) !void {
    var decoded = try person_pb.demo.Person.parseText(ctx.allocator, ctx.text);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

const DynamicTextFormatCtx = struct { allocator: std.mem.Allocator, file: *const pbz.FileDescriptor, message: *const pbz.DynamicMessage };
fn dynamicTextFormat(ctx: DynamicTextFormatCtx) !void {
    const text = try pbz.formatTextAlloc(ctx.allocator, ctx.file, ctx.message, .{});
    std.mem.doNotOptimizeAway(text.ptr);
    ctx.allocator.free(text);
}

const DynamicTextParseCtx = struct { allocator: std.mem.Allocator, file: *const pbz.FileDescriptor, descriptor: *const pbz.MessageDescriptor, text: []const u8 };
fn dynamicTextParse(ctx: DynamicTextParseCtx) !void {
    var msg = try pbz.parseTextAlloc(ctx.allocator, ctx.file, ctx.descriptor, ctx.text);
    std.mem.doNotOptimizeAway(&msg);
    msg.deinit();
}

pub fn main() !void {
    const allocator = std.heap.smp_allocator;
    const io = std.Io.Threaded.global_single_threaded.io();
    const iters = Iterations{};

    var file = try pbz.ProtoParser.parse(allocator,
        \\syntax = "proto3";
        \\package demo;
        \\enum BenchKind {
        \\  BENCH_KIND_UNKNOWN = 0;
        \\  BENCH_KIND_ALPHA = 1;
        \\  BENCH_KIND_BETA = 2;
        \\}
        \\message Person {
        \\  int32 id = 1;
        \\  string name = 2;
        \\  repeated int32 scores = 3;
        \\  map<string, int32> counts = 4;
        \\}
        \\message Complex {
        \\  message Audit {
        \\    string actor = 1;
        \\    int64 at_unix = 2;
        \\  }
        \\  int32 id = 1;
        \\  Audit audit = 2;
        \\  repeated Audit history = 3;
        \\  map<string, Audit> audits = 4;
        \\  oneof subject {
        \\    string user_name = 5;
        \\    bytes organization_id = 6;
        \\    Audit audit_subject = 7;
        \\  }
        \\}
        \\message Packed {
        \\  repeated int32 values = 1;
        \\}
        \\message FixedPacked {
        \\  repeated fixed32 values = 1;
        \\}
        \\message Fixed64Packed {
        \\  repeated fixed64 values = 1;
        \\}
        \\message UInt64Packed {
        \\  repeated uint64 values = 1;
        \\}
        \\message SInt64Packed {
        \\  repeated sint64 values = 1;
        \\}
        \\message BoolPacked {
        \\  repeated bool values = 1;
        \\}
        \\message EnumPacked {
        \\  repeated BenchKind values = 1;
        \\}
    );
    defer file.deinit();
    const desc = file.findMessage("Person").?;
    const packed_desc = file.findMessage("Packed").?;
    const fixed_packed_desc = file.findMessage("FixedPacked").?;
    const fixed64_packed_desc = file.findMessage("Fixed64Packed").?;
    const uint64_packed_desc = file.findMessage("UInt64Packed").?;
    const sint64_packed_desc = file.findMessage("SInt64Packed").?;
    const bool_packed_desc = file.findMessage("BoolPacked").?;
    const enum_packed_desc = file.findMessage("EnumPacked").?;

    var generated_person = try makeGeneratedPerson(allocator);
    defer generated_person.deinit(allocator);
    var dynamic_person = try makeDynamicPerson(allocator, desc);
    defer dynamic_person.deinit();
    var generated_scalar_mix = try makeGeneratedScalarMix(allocator);
    defer generated_scalar_mix.deinit(allocator);
    var generated_text_bytes = try makeGeneratedTextBytes(allocator);
    defer generated_text_bytes.deinit(allocator);
    var generated_complex = try makeGeneratedComplex(allocator);
    defer generated_complex.deinit(allocator);
    var generated_packed = try makeGeneratedPacked(allocator);
    defer generated_packed.deinit(allocator);
    var dynamic_packed = try makeDynamicPacked(allocator, packed_desc);
    defer dynamic_packed.deinit();
    var generated_fixed_packed = try makeGeneratedFixedPacked(allocator);
    defer generated_fixed_packed.deinit(allocator);
    var dynamic_fixed_packed = try makeDynamicFixedPacked(allocator, fixed_packed_desc);
    defer dynamic_fixed_packed.deinit();
    var dynamic_fixed_packed_decode_reuse = pbz.DynamicMessage.init(allocator, fixed_packed_desc);
    defer dynamic_fixed_packed_decode_reuse.deinit();
    var generated_fixed64_packed = try makeGeneratedFixed64Packed(allocator);
    defer generated_fixed64_packed.deinit(allocator);
    var dynamic_fixed64_packed = try makeDynamicFixed64Packed(allocator, fixed64_packed_desc);
    defer dynamic_fixed64_packed.deinit();
    var dynamic_fixed64_packed_decode_reuse = pbz.DynamicMessage.init(allocator, fixed64_packed_desc);
    defer dynamic_fixed64_packed_decode_reuse.deinit();
    var generated_uint64_packed = try makeGeneratedUInt64Packed(allocator);
    defer generated_uint64_packed.deinit(allocator);
    var dynamic_uint64_packed = try makeDynamicUInt64Packed(allocator, uint64_packed_desc);
    defer dynamic_uint64_packed.deinit();
    var generated_sint64_packed = try makeGeneratedSInt64Packed(allocator);
    defer generated_sint64_packed.deinit(allocator);
    var dynamic_sint64_packed = try makeDynamicSInt64Packed(allocator, sint64_packed_desc);
    defer dynamic_sint64_packed.deinit();
    var generated_bool_packed = try makeGeneratedBoolPacked(allocator);
    defer generated_bool_packed.deinit(allocator);
    var dynamic_bool_packed = try makeDynamicBoolPacked(allocator, bool_packed_desc);
    defer dynamic_bool_packed.deinit();
    var generated_enum_packed = try makeGeneratedEnumPacked(allocator);
    defer generated_enum_packed.deinit(allocator);
    var dynamic_enum_packed = try makeDynamicEnumPacked(allocator, enum_packed_desc);
    defer dynamic_enum_packed.deinit();

    const generated_bytes = try generated_person.encode(allocator);
    defer allocator.free(generated_bytes);
    var reusable_writer = pbz.Writer.init(allocator);
    defer reusable_writer.deinit();
    try reusable_writer.bytes.ensureTotalCapacity(allocator, generated_bytes.len);
    const generated_buffer = try allocator.alloc(u8, generated_bytes.len);
    defer allocator.free(generated_buffer);
    const dynamic_bytes = try dynamic_person.encoded(&file);
    defer allocator.free(dynamic_bytes);
    const generated_scalar_mix_bytes = try generated_scalar_mix.encode(allocator);
    defer allocator.free(generated_scalar_mix_bytes);
    var reusable_scalar_mix_writer = pbz.Writer.init(allocator);
    defer reusable_scalar_mix_writer.deinit();
    try reusable_scalar_mix_writer.bytes.ensureTotalCapacity(allocator, generated_scalar_mix_bytes.len);
    const generated_scalar_mix_buffer = try allocator.alloc(u8, generated_scalar_mix_bytes.len);
    defer allocator.free(generated_scalar_mix_buffer);
    var generated_scalar_mix_decode_reuse = person_pb.demo.ScalarMix.init();
    defer generated_scalar_mix_decode_reuse.deinit(allocator);
    const generated_text_bytes_bytes = try generated_text_bytes.encode(allocator);
    defer allocator.free(generated_text_bytes_bytes);
    var reusable_text_bytes_writer = pbz.Writer.init(allocator);
    defer reusable_text_bytes_writer.deinit();
    try reusable_text_bytes_writer.bytes.ensureTotalCapacity(allocator, generated_text_bytes_bytes.len);
    const generated_text_bytes_buffer = try allocator.alloc(u8, generated_text_bytes_bytes.len);
    defer allocator.free(generated_text_bytes_buffer);
    const generated_complex_bytes = try generated_complex.encode(allocator);
    defer allocator.free(generated_complex_bytes);
    var reusable_complex_writer = pbz.Writer.init(allocator);
    defer reusable_complex_writer.deinit();
    try reusable_complex_writer.bytes.ensureTotalCapacity(allocator, generated_complex_bytes.len);
    const generated_complex_buffer = try allocator.alloc(u8, generated_complex_bytes.len);
    defer allocator.free(generated_complex_buffer);
    const generated_complex_json = try generated_complex.jsonStringifyAlloc(allocator);
    defer allocator.free(generated_complex_json);
    const generated_complex_text = try generated_complex.formatTextAlloc(allocator);
    defer allocator.free(generated_complex_text);
    const generated_packed_bytes = try generated_packed.encode(allocator);
    defer allocator.free(generated_packed_bytes);
    var reusable_packed_writer = pbz.Writer.init(allocator);
    defer reusable_packed_writer.deinit();
    try reusable_packed_writer.bytes.ensureTotalCapacity(allocator, generated_packed_bytes.len);
    const generated_packed_buffer = try allocator.alloc(u8, generated_packed_bytes.len);
    defer allocator.free(generated_packed_buffer);
    const dynamic_packed_bytes = try dynamic_packed.encoded(&file);
    defer allocator.free(dynamic_packed_bytes);
    const generated_fixed_packed_bytes = try generated_fixed_packed.encode(allocator);
    defer allocator.free(generated_fixed_packed_bytes);
    const generated_fixed_packed_buffer = try allocator.alloc(u8, generated_fixed_packed_bytes.len);
    defer allocator.free(generated_fixed_packed_buffer);
    const dynamic_fixed_packed_bytes = try dynamic_fixed_packed.encoded(&file);
    defer allocator.free(dynamic_fixed_packed_bytes);
    const generated_fixed64_packed_bytes = try generated_fixed64_packed.encode(allocator);
    defer allocator.free(generated_fixed64_packed_bytes);
    const generated_fixed64_packed_buffer = try allocator.alloc(u8, generated_fixed64_packed_bytes.len);
    defer allocator.free(generated_fixed64_packed_buffer);
    const dynamic_fixed64_packed_bytes = try dynamic_fixed64_packed.encoded(&file);
    defer allocator.free(dynamic_fixed64_packed_bytes);
    const generated_uint64_packed_bytes = try generated_uint64_packed.encode(allocator);
    defer allocator.free(generated_uint64_packed_bytes);
    const generated_uint64_packed_buffer = try allocator.alloc(u8, generated_uint64_packed_bytes.len);
    defer allocator.free(generated_uint64_packed_buffer);
    var generated_uint64_packed_decode_reuse = person_pb.demo.UInt64Packed.init();
    defer generated_uint64_packed_decode_reuse.deinit(allocator);
    const dynamic_uint64_packed_bytes = try dynamic_uint64_packed.encoded(&file);
    defer allocator.free(dynamic_uint64_packed_bytes);
    const generated_sint64_packed_bytes = try generated_sint64_packed.encode(allocator);
    defer allocator.free(generated_sint64_packed_bytes);
    const generated_sint64_packed_buffer = try allocator.alloc(u8, generated_sint64_packed_bytes.len);
    defer allocator.free(generated_sint64_packed_buffer);
    const dynamic_sint64_packed_bytes = try dynamic_sint64_packed.encoded(&file);
    defer allocator.free(dynamic_sint64_packed_bytes);
    const generated_bool_packed_bytes = try generated_bool_packed.encode(allocator);
    defer allocator.free(generated_bool_packed_bytes);
    const generated_bool_packed_buffer = try allocator.alloc(u8, generated_bool_packed_bytes.len);
    defer allocator.free(generated_bool_packed_buffer);
    const dynamic_bool_packed_bytes = try dynamic_bool_packed.encoded(&file);
    defer allocator.free(dynamic_bool_packed_bytes);
    const generated_enum_packed_bytes = try generated_enum_packed.encode(allocator);
    defer allocator.free(generated_enum_packed_bytes);
    const generated_enum_packed_buffer = try allocator.alloc(u8, generated_enum_packed_bytes.len);
    defer allocator.free(generated_enum_packed_buffer);
    var generated_enum_packed_decode_reuse = person_pb.demo.EnumPacked.init();
    defer generated_enum_packed_decode_reuse.deinit(allocator);
    const dynamic_enum_packed_bytes = try dynamic_enum_packed.encoded(&file);
    defer allocator.free(dynamic_enum_packed_bytes);
    const generated_json = try generated_person.jsonStringifyAlloc(allocator);
    defer allocator.free(generated_json);
    const dynamic_json = try pbz.stringifyJsonAlloc(allocator, &file, &dynamic_person, .{});
    defer allocator.free(dynamic_json);
    const generated_text = try generated_person.formatTextAlloc(allocator);
    defer allocator.free(generated_text);
    const dynamic_text = try pbz.formatTextAlloc(allocator, &file, &dynamic_person, .{});
    defer allocator.free(dynamic_text);

    std.debug.print("pbz benchmark baseline (Zig {s})\n", .{@import("builtin").zig_version_string});
    std.debug.print("payload sizes: person_generated={d} person_dynamic={d} packed_generated={d} packed_dynamic={d} fixed_packed_generated={d} fixed_packed_dynamic={d} fixed64_packed_generated={d} fixed64_packed_dynamic={d} uint64_packed_generated={d} uint64_packed_dynamic={d} sint64_packed_generated={d} sint64_packed_dynamic={d} bool_packed_generated={d} bool_packed_dynamic={d} enum_packed_generated={d} enum_packed_dynamic={d} scalar_mix={d} text_bytes={d} complex={d} complex_json={d} complex_text={d} json={d} text={d}\n", .{ generated_bytes.len, dynamic_bytes.len, generated_packed_bytes.len, dynamic_packed_bytes.len, generated_fixed_packed_bytes.len, dynamic_fixed_packed_bytes.len, generated_fixed64_packed_bytes.len, dynamic_fixed64_packed_bytes.len, generated_uint64_packed_bytes.len, dynamic_uint64_packed_bytes.len, generated_sint64_packed_bytes.len, dynamic_sint64_packed_bytes.len, generated_bool_packed_bytes.len, dynamic_bool_packed_bytes.len, generated_enum_packed_bytes.len, dynamic_enum_packed_bytes.len, generated_scalar_mix_bytes.len, generated_text_bytes_bytes.len, generated_complex_bytes.len, generated_complex_json.len, generated_complex_text.len, generated_json.len, generated_text.len });

    const results = [_]BenchResult{
        try runTimed(io, "generated binary encode", iters.generated_binary, generated_bytes.len, GeneratedEncodeCtx{ .allocator = allocator, .person = &generated_person }, generatedEncode),
        try runTimed(io, "generated binary writeToAssumeCapacity reuse", iters.generated_binary, generated_bytes.len, GeneratedWriteToCtx{ .writer = &reusable_writer, .person = &generated_person }, generatedWriteToReuse),
        try runTimed(io, "generated binary encodeIntoAssumeCapacity buffer reuse", iters.generated_binary, generated_bytes.len, GeneratedEncodeIntoCtx{ .buffer = generated_buffer, .person = &generated_person }, generatedEncodeIntoReuse),
        try runTimed(io, "generated deterministic binary encode", iters.generated_binary, generated_bytes.len, GeneratedDeterministicEncodeCtx{ .allocator = allocator, .person = &generated_person }, generatedDeterministicEncode),
        try runTimed(io, "generated deterministic binary encodeIntoAssumeCapacity buffer reuse", iters.generated_binary, generated_bytes.len, GeneratedDeterministicEncodeIntoCtx{ .allocator = allocator, .buffer = generated_buffer, .person = &generated_person }, generatedDeterministicEncodeIntoReuse),
        try runTimed(io, "generated binary decode", iters.generated_binary, generated_bytes.len, GeneratedDecodeCtx{ .allocator = allocator, .bytes = generated_bytes }, generatedDecode),
        try runTimed(io, "generated scalarmix encode", iters.generated_binary, generated_scalar_mix_bytes.len, GeneratedScalarMixEncodeCtx{ .allocator = allocator, .message = &generated_scalar_mix }, generatedScalarMixEncode),
        try runTimed(io, "generated scalarmix writeToAssumeCapacity reuse", iters.generated_binary, generated_scalar_mix_bytes.len, GeneratedScalarMixWriteToCtx{ .writer = &reusable_scalar_mix_writer, .message = &generated_scalar_mix }, generatedScalarMixWriteToReuse),
        try runTimed(io, "generated scalarmix encodeIntoAssumeCapacity buffer reuse", iters.generated_binary, generated_scalar_mix_bytes.len, GeneratedScalarMixEncodeIntoCtx{ .buffer = generated_scalar_mix_buffer, .message = &generated_scalar_mix }, generatedScalarMixEncodeIntoReuse),
        try runTimed(io, "generated scalarmix decode", iters.generated_binary, generated_scalar_mix_bytes.len, GeneratedScalarMixDecodeCtx{ .allocator = allocator, .bytes = generated_scalar_mix_bytes }, generatedScalarMixDecode),
        try runTimed(io, "generated scalarmix decode reuse", iters.generated_binary, generated_scalar_mix_bytes.len, GeneratedScalarMixDecodeReuseCtx{ .allocator = allocator, .bytes = generated_scalar_mix_bytes, .message = &generated_scalar_mix_decode_reuse }, generatedScalarMixDecodeReuse),
        try runTimed(io, "generated textbytes encode", iters.generated_binary, generated_text_bytes_bytes.len, GeneratedTextBytesEncodeCtx{ .allocator = allocator, .message = &generated_text_bytes }, generatedTextBytesEncode),
        try runTimed(io, "generated textbytes writeToAssumeCapacity reuse", iters.generated_binary, generated_text_bytes_bytes.len, GeneratedTextBytesWriteToCtx{ .writer = &reusable_text_bytes_writer, .message = &generated_text_bytes }, generatedTextBytesWriteToReuse),
        try runTimed(io, "generated textbytes trusted UTF-8 writeToAssumeCapacity reuse", iters.generated_binary, generated_text_bytes_bytes.len, GeneratedTextBytesWriteToCtx{ .writer = &reusable_text_bytes_writer, .message = &generated_text_bytes }, generatedTextBytesTrustedUtf8WriteToReuse),
        try runTimed(io, "generated textbytes encodeIntoAssumeCapacity buffer reuse", iters.generated_binary, generated_text_bytes_bytes.len, GeneratedTextBytesEncodeIntoCtx{ .buffer = generated_text_bytes_buffer, .message = &generated_text_bytes }, generatedTextBytesEncodeIntoReuse),
        try runTimed(io, "generated textbytes decode", iters.generated_binary, generated_text_bytes_bytes.len, GeneratedTextBytesDecodeCtx{ .allocator = allocator, .bytes = generated_text_bytes_bytes }, generatedTextBytesDecode),
        try runTimed(io, "generated complex encode", iters.generated_binary, generated_complex_bytes.len, GeneratedComplexEncodeCtx{ .allocator = allocator, .message = &generated_complex }, generatedComplexEncode),
        try runTimed(io, "generated complex writeToAssumeCapacity reuse", iters.generated_binary, generated_complex_bytes.len, GeneratedComplexWriteToCtx{ .writer = &reusable_complex_writer, .message = &generated_complex }, generatedComplexWriteToReuse),
        try runTimed(io, "generated complex encodeIntoAssumeCapacity buffer reuse", iters.generated_binary, generated_complex_bytes.len, GeneratedComplexEncodeIntoCtx{ .buffer = generated_complex_buffer, .message = &generated_complex }, generatedComplexEncodeIntoReuse),
        try runTimed(io, "generated complex decode", iters.generated_binary, generated_complex_bytes.len, GeneratedComplexDecodeCtx{ .allocator = allocator, .bytes = generated_complex_bytes }, generatedComplexDecode),
        try runTimed(io, "generated complex JSON stringify", iters.json, generated_complex_json.len, GeneratedComplexJsonStringifyCtx{ .allocator = allocator, .message = &generated_complex }, generatedComplexJsonStringify),
        try runTimed(io, "generated complex JSON parse", iters.json, generated_complex_json.len, GeneratedComplexJsonParseCtx{ .allocator = allocator, .json = generated_complex_json }, generatedComplexJsonParse),
        try runTimed(io, "generated complex TextFormat format", iters.text, generated_complex_text.len, GeneratedComplexTextFormatCtx{ .allocator = allocator, .message = &generated_complex }, generatedComplexTextFormat),
        try runTimed(io, "generated complex TextFormat parse", iters.text, generated_complex_text.len, GeneratedComplexTextParseCtx{ .allocator = allocator, .text = generated_complex_text }, generatedComplexTextParse),
        try runTimed(io, "generated complex deterministic binary encode", iters.generated_binary, generated_complex_bytes.len, GeneratedComplexDeterministicEncodeCtx{ .allocator = allocator, .message = &generated_complex }, generatedComplexDeterministicEncode),
        try runTimed(io, "generated complex deterministic binary encodeIntoAssumeCapacity buffer reuse", iters.generated_binary, generated_complex_bytes.len, GeneratedComplexDeterministicEncodeIntoCtx{ .allocator = allocator, .buffer = generated_complex_buffer, .message = &generated_complex }, generatedComplexDeterministicEncodeIntoReuse),
        try runTimed(io, "dynamic binary encode", iters.dynamic_binary, dynamic_bytes.len, DynamicEncodeCtx{ .message = &dynamic_person, .file = &file }, dynamicEncode),
        try runTimed(io, "dynamic binary decode", iters.dynamic_binary, dynamic_bytes.len, DynamicDecodeCtx{ .allocator = allocator, .descriptor = desc, .file = &file, .bytes = dynamic_bytes }, dynamicDecode),
        try runTimed(io, "generated packed encode", iters.packed_binary, generated_packed_bytes.len, GeneratedPackedEncodeCtx{ .allocator = allocator, .message = &generated_packed }, generatedPackedEncode),
        try runTimed(io, "generated packed writeToAssumeCapacity reuse", iters.packed_binary, generated_packed_bytes.len, GeneratedPackedWriteToCtx{ .writer = &reusable_packed_writer, .message = &generated_packed }, generatedPackedWriteToReuse),
        try runTimed(io, "generated packed encodeIntoAssumeCapacity buffer reuse", iters.packed_binary, generated_packed_bytes.len, GeneratedPackedEncodeIntoCtx{ .buffer = generated_packed_buffer, .message = &generated_packed }, generatedPackedEncodeIntoReuse),
        try runTimed(io, "generated packed decode", iters.packed_binary, generated_packed_bytes.len, GeneratedPackedDecodeCtx{ .allocator = allocator, .bytes = generated_packed_bytes }, generatedPackedDecode),
        try runTimed(io, "dynamic packed encode", iters.packed_binary, dynamic_packed_bytes.len, DynamicPackedEncodeCtx{ .message = &dynamic_packed, .file = &file }, dynamicPackedEncode),
        try runTimed(io, "dynamic packed decode", iters.packed_binary, dynamic_packed_bytes.len, DynamicPackedDecodeCtx{ .allocator = allocator, .descriptor = packed_desc, .file = &file, .bytes = dynamic_packed_bytes }, dynamicPackedDecode),
        try runTimed(io, "generated fixed32 packed encode", iters.packed_binary, generated_fixed_packed_bytes.len, GeneratedFixedPackedEncodeCtx{ .allocator = allocator, .message = &generated_fixed_packed }, generatedFixedPackedEncode),
        try runTimed(io, "generated fixed32 packed encodeIntoAssumeCapacity buffer reuse", iters.packed_binary, generated_fixed_packed_bytes.len, GeneratedFixedPackedEncodeIntoCtx{ .buffer = generated_fixed_packed_buffer, .message = &generated_fixed_packed }, generatedFixedPackedEncodeIntoReuse),
        try runTimed(io, "generated fixed32 packed borrowed slices encode", iters.packed_binary, generated_fixed_packed_bytes.len, GeneratedFixedPackedSlicesCtx{ .message = &generated_fixed_packed }, generatedFixedPackedBorrowedSlices),
        try runTimed(io, "generated fixed32 packed decode", iters.packed_binary, generated_fixed_packed_bytes.len, GeneratedFixedPackedDecodeCtx{ .allocator = allocator, .bytes = generated_fixed_packed_bytes }, generatedFixedPackedDecode),
        try runTimed(io, "wire fixed32 packed borrowed view decode", iters.packed_binary, generated_fixed_packed_bytes.len, FixedPackedBorrowedViewCtx{ .bytes = generated_fixed_packed_bytes }, fixedPackedBorrowedViewDecode),
        try runTimed(io, "dynamic fixed32 packed encode", iters.packed_binary, dynamic_fixed_packed_bytes.len, DynamicFixedPackedEncodeCtx{ .message = &dynamic_fixed_packed, .file = &file }, dynamicFixedPackedEncode),
        try runTimed(io, "dynamic fixed32 packed decode", iters.packed_binary, dynamic_fixed_packed_bytes.len, DynamicFixedPackedDecodeCtx{ .allocator = allocator, .descriptor = fixed_packed_desc, .file = &file, .bytes = dynamic_fixed_packed_bytes }, dynamicFixedPackedDecode),
        try runTimed(io, "dynamic fixed32 packed decode reuse", iters.packed_binary, dynamic_fixed_packed_bytes.len, DynamicFixedPackedDecodeReuseCtx{ .message = &dynamic_fixed_packed_decode_reuse, .file = &file, .bytes = dynamic_fixed_packed_bytes }, dynamicFixedPackedDecodeReuse),
        try runTimed(io, "generated fixed64 packed encode", iters.packed_binary, generated_fixed64_packed_bytes.len, GeneratedFixed64PackedEncodeCtx{ .allocator = allocator, .message = &generated_fixed64_packed }, generatedFixed64PackedEncode),
        try runTimed(io, "generated fixed64 packed encodeIntoAssumeCapacity buffer reuse", iters.packed_binary, generated_fixed64_packed_bytes.len, GeneratedFixed64PackedEncodeIntoCtx{ .buffer = generated_fixed64_packed_buffer, .message = &generated_fixed64_packed }, generatedFixed64PackedEncodeIntoReuse),
        try runTimed(io, "generated fixed64 packed borrowed slices encode", iters.packed_binary, generated_fixed64_packed_bytes.len, GeneratedFixed64PackedSlicesCtx{ .message = &generated_fixed64_packed }, generatedFixed64PackedBorrowedSlices),
        try runTimed(io, "generated fixed64 packed decode", iters.packed_binary, generated_fixed64_packed_bytes.len, GeneratedFixed64PackedDecodeCtx{ .allocator = allocator, .bytes = generated_fixed64_packed_bytes }, generatedFixed64PackedDecode),
        try runTimed(io, "wire fixed64 packed borrowed view decode", iters.packed_binary, generated_fixed64_packed_bytes.len, Fixed64PackedBorrowedViewCtx{ .bytes = generated_fixed64_packed_bytes }, fixed64PackedBorrowedViewDecode),
        try runTimed(io, "dynamic fixed64 packed encode", iters.packed_binary, dynamic_fixed64_packed_bytes.len, DynamicFixed64PackedEncodeCtx{ .message = &dynamic_fixed64_packed, .file = &file }, dynamicFixed64PackedEncode),
        try runTimed(io, "dynamic fixed64 packed decode", iters.packed_binary, dynamic_fixed64_packed_bytes.len, DynamicFixed64PackedDecodeCtx{ .allocator = allocator, .descriptor = fixed64_packed_desc, .file = &file, .bytes = dynamic_fixed64_packed_bytes }, dynamicFixed64PackedDecode),
        try runTimed(io, "dynamic fixed64 packed decode reuse", iters.packed_binary, dynamic_fixed64_packed_bytes.len, DynamicFixed64PackedDecodeReuseCtx{ .message = &dynamic_fixed64_packed_decode_reuse, .file = &file, .bytes = dynamic_fixed64_packed_bytes }, dynamicFixed64PackedDecodeReuse),
        try runTimed(io, "generated uint64 packed encode", iters.packed_binary, generated_uint64_packed_bytes.len, GeneratedUInt64PackedEncodeCtx{ .allocator = allocator, .message = &generated_uint64_packed }, generatedUInt64PackedEncode),
        try runTimed(io, "generated uint64 packed encodeIntoAssumeCapacity buffer reuse", iters.packed_binary, generated_uint64_packed_bytes.len, GeneratedUInt64PackedEncodeIntoCtx{ .buffer = generated_uint64_packed_buffer, .message = &generated_uint64_packed }, generatedUInt64PackedEncodeIntoReuse),
        try runTimed(io, "generated uint64 packed decode", iters.packed_binary, generated_uint64_packed_bytes.len, GeneratedUInt64PackedDecodeCtx{ .allocator = allocator, .bytes = generated_uint64_packed_bytes }, generatedUInt64PackedDecode),
        try runTimed(io, "generated uint64 packed decode reuse", iters.packed_binary, generated_uint64_packed_bytes.len, GeneratedUInt64PackedDecodeReuseCtx{ .allocator = allocator, .bytes = generated_uint64_packed_bytes, .message = &generated_uint64_packed_decode_reuse }, generatedUInt64PackedDecodeReuse),
        try runTimed(io, "wire uint64 packed iterator decode", iters.packed_binary, generated_uint64_packed_bytes.len, UInt64PackedIteratorCtx{ .bytes = generated_uint64_packed_bytes }, uint64PackedIteratorDecode),
        try runTimed(io, "dynamic uint64 packed encode", iters.packed_binary, dynamic_uint64_packed_bytes.len, DynamicUInt64PackedEncodeCtx{ .message = &dynamic_uint64_packed, .file = &file }, dynamicUInt64PackedEncode),
        try runTimed(io, "dynamic uint64 packed decode", iters.packed_binary, dynamic_uint64_packed_bytes.len, DynamicUInt64PackedDecodeCtx{ .allocator = allocator, .descriptor = uint64_packed_desc, .file = &file, .bytes = dynamic_uint64_packed_bytes }, dynamicUInt64PackedDecode),
        try runTimed(io, "generated sint64 packed encode", iters.packed_binary, generated_sint64_packed_bytes.len, GeneratedSInt64PackedEncodeCtx{ .allocator = allocator, .message = &generated_sint64_packed }, generatedSInt64PackedEncode),
        try runTimed(io, "generated sint64 packed encodeIntoAssumeCapacity buffer reuse", iters.packed_binary, generated_sint64_packed_bytes.len, GeneratedSInt64PackedEncodeIntoCtx{ .buffer = generated_sint64_packed_buffer, .message = &generated_sint64_packed }, generatedSInt64PackedEncodeIntoReuse),
        try runTimed(io, "generated sint64 packed decode", iters.packed_binary, generated_sint64_packed_bytes.len, GeneratedSInt64PackedDecodeCtx{ .allocator = allocator, .bytes = generated_sint64_packed_bytes }, generatedSInt64PackedDecode),
        try runTimed(io, "wire sint64 packed iterator decode", iters.packed_binary, generated_sint64_packed_bytes.len, SInt64PackedIteratorCtx{ .bytes = generated_sint64_packed_bytes }, sint64PackedIteratorDecode),
        try runTimed(io, "dynamic sint64 packed encode", iters.packed_binary, dynamic_sint64_packed_bytes.len, DynamicSInt64PackedEncodeCtx{ .message = &dynamic_sint64_packed, .file = &file }, dynamicSInt64PackedEncode),
        try runTimed(io, "dynamic sint64 packed decode", iters.packed_binary, dynamic_sint64_packed_bytes.len, DynamicSInt64PackedDecodeCtx{ .allocator = allocator, .descriptor = sint64_packed_desc, .file = &file, .bytes = dynamic_sint64_packed_bytes }, dynamicSInt64PackedDecode),
        try runTimed(io, "generated bool packed encode", iters.packed_binary, generated_bool_packed_bytes.len, GeneratedBoolPackedEncodeCtx{ .allocator = allocator, .message = &generated_bool_packed }, generatedBoolPackedEncode),
        try runTimed(io, "generated bool packed encodeIntoAssumeCapacity buffer reuse", iters.packed_binary, generated_bool_packed_bytes.len, GeneratedBoolPackedEncodeIntoCtx{ .buffer = generated_bool_packed_buffer, .message = &generated_bool_packed }, generatedBoolPackedEncodeIntoReuse),
        try runTimed(io, "generated bool packed decode", iters.packed_binary, generated_bool_packed_bytes.len, GeneratedBoolPackedDecodeCtx{ .allocator = allocator, .bytes = generated_bool_packed_bytes }, generatedBoolPackedDecode),
        try runTimed(io, "dynamic bool packed encode", iters.packed_binary, dynamic_bool_packed_bytes.len, DynamicBoolPackedEncodeCtx{ .message = &dynamic_bool_packed, .file = &file }, dynamicBoolPackedEncode),
        try runTimed(io, "dynamic bool packed decode", iters.packed_binary, dynamic_bool_packed_bytes.len, DynamicBoolPackedDecodeCtx{ .allocator = allocator, .descriptor = bool_packed_desc, .file = &file, .bytes = dynamic_bool_packed_bytes }, dynamicBoolPackedDecode),
        try runTimed(io, "generated enum packed encode", iters.packed_binary, generated_enum_packed_bytes.len, GeneratedEnumPackedEncodeCtx{ .allocator = allocator, .message = &generated_enum_packed }, generatedEnumPackedEncode),
        try runTimed(io, "generated enum packed encodeIntoAssumeCapacity buffer reuse", iters.packed_binary, generated_enum_packed_bytes.len, GeneratedEnumPackedEncodeIntoCtx{ .buffer = generated_enum_packed_buffer, .message = &generated_enum_packed }, generatedEnumPackedEncodeIntoReuse),
        try runTimed(io, "generated enum packed decode", iters.packed_binary, generated_enum_packed_bytes.len, GeneratedEnumPackedDecodeCtx{ .allocator = allocator, .bytes = generated_enum_packed_bytes }, generatedEnumPackedDecode),
        try runTimed(io, "generated enum packed decode reuse", iters.packed_binary, generated_enum_packed_bytes.len, GeneratedEnumPackedDecodeReuseCtx{ .allocator = allocator, .bytes = generated_enum_packed_bytes, .message = &generated_enum_packed_decode_reuse }, generatedEnumPackedDecodeReuse),
        try runTimed(io, "dynamic enum packed encode", iters.packed_binary, dynamic_enum_packed_bytes.len, DynamicEnumPackedEncodeCtx{ .message = &dynamic_enum_packed, .file = &file }, dynamicEnumPackedEncode),
        try runTimed(io, "dynamic enum packed decode", iters.packed_binary, dynamic_enum_packed_bytes.len, DynamicEnumPackedDecodeCtx{ .allocator = allocator, .descriptor = enum_packed_desc, .file = &file, .bytes = dynamic_enum_packed_bytes }, dynamicEnumPackedDecode),
        try runTimed(io, "generated JSON stringify", iters.json, generated_json.len, GeneratedJsonStringifyCtx{ .allocator = allocator, .person = &generated_person }, generatedJsonStringify),
        try runTimed(io, "generated JSON parse", iters.json, generated_json.len, GeneratedJsonParseCtx{ .allocator = allocator, .json = generated_json }, generatedJsonParse),
        try runTimed(io, "dynamic JSON stringify", iters.json, dynamic_json.len, DynamicJsonStringifyCtx{ .allocator = allocator, .file = &file, .message = &dynamic_person }, dynamicJsonStringify),
        try runTimed(io, "dynamic JSON parse", iters.json, dynamic_json.len, DynamicJsonParseCtx{ .allocator = allocator, .file = &file, .descriptor = desc, .json = dynamic_json }, dynamicJsonParse),
        try runTimed(io, "generated TextFormat format", iters.text, generated_text.len, GeneratedTextFormatCtx{ .allocator = allocator, .person = &generated_person }, generatedTextFormat),
        try runTimed(io, "generated TextFormat parse", iters.text, generated_text.len, GeneratedTextParseCtx{ .allocator = allocator, .text = generated_text }, generatedTextParse),
        try runTimed(io, "dynamic TextFormat format", iters.text, dynamic_text.len, DynamicTextFormatCtx{ .allocator = allocator, .file = &file, .message = &dynamic_person }, dynamicTextFormat),
        try runTimed(io, "dynamic TextFormat parse", iters.text, dynamic_text.len, DynamicTextParseCtx{ .allocator = allocator, .file = &file, .descriptor = desc, .text = dynamic_text }, dynamicTextParse),
    };

    for (results) |result| result.print();
}
