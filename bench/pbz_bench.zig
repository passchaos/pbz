const std = @import("std");
const pbz = @import("pbz");
const person_pb = @import("person_pb");

const Iterations = struct {
    generated_binary: usize = 20_000,
    dynamic_binary: usize = 10_000,
    json: usize = 2_000,
    text: usize = 1_000,
    packed_binary: usize = 5_000,
    large_map: usize = 1_000,
};

const BenchmarkSamples: usize = 3;
const AnyWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Duration","value":"1.500s"}
;
const AnyStructWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Struct","value":{"enabled":true,"items":[null,"zig"],"meta":{"score":1.5}}}
;
const AnyValueWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Value","value":{"enabled":true,"items":[null,"zig"],"meta":{"score":1.5}}}
;
const AnyStringValueWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.StringValue","value":"hello"}
;
const AnyBytesValueWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.BytesValue","value":"aGk="}
;
const NestedAnyWktJson =
    \\{"@type":"type.googleapis.com/google.protobuf.Any","value":{"@type":"type.googleapis.com/google.protobuf.StringValue","value":"hello"}}
;
const TimestampJson = "\"2020-01-01T00:00:00.123Z\"";
const DurationJson = "\"1.500s\"";
const FieldMaskJson = "\"fooBar,nested.value\"";
const EmptyJson = "{}";
const StructJson = "{\"enabled\":true,\"items\":[null,\"zig\"],\"meta\":{\"score\":1.5}}";
const ValueJson = StructJson;
const ListValueJson = "[null,\"zig\",1.5,true,{\"nested\":\"value\"}]";
const DoubleValueJson = "3.25";
const FloatValueJson = "1.5";
const Int64ValueJson = "\"9007199254740993\"";
const UInt64ValueJson = "\"9007199254740993\"";
const Int32ValueJson = "12345";
const UInt32ValueJson = "12345";
const BoolValueJson = "true";
const StringValueJson = "\"hello\"";
const BytesValueJson = "\"aGk=\"";
const LargeBytesPayloadLen: usize = 64 * 1024;
const LargeBytesChunkCount: usize = 16;
const LargeBytesChunkLen: usize = 4 * 1024;
const LargeMapEntryCount: usize = 1024;
const LargeMapShuffleMultiplier: usize = 257;
const LargeMapShuffleIncrement: usize = 911;
const UnknownFieldStressCount: usize = 1024;
const UnknownFieldStressFirstNumber: pbz.FieldNumber = 1000;
const UnknownFieldStressNumberSpan: pbz.FieldNumber = 16;

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

fn makeUnknownFieldPayload(allocator: std.mem.Allocator, base: []const u8, count: usize) ![]u8 {
    var writer = pbz.Writer.init(allocator);
    errdefer writer.deinit();
    try writer.appendSlice(base);
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const number: pbz.FieldNumber = @intCast(UnknownFieldStressFirstNumber + (i % UnknownFieldStressNumberSpan));
        try writer.writeUInt32(number, @intCast(i + 1));
    }
    return try writer.toOwnedSlice();
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

fn makeGeneratedLargeBytes(allocator: std.mem.Allocator) !person_pb.demo.LargeBytes {
    var msg = person_pb.demo.LargeBytes.init();
    errdefer msg.deinit(allocator);
    const payload = try allocator.alloc(u8, LargeBytesPayloadLen);
    for (payload, 0..) |*byte, i| byte.* = @intCast((i * 31 + 7) & 0xff);
    msg.payload = payload;
    const chunks = try allocator.alloc([]const u8, LargeBytesChunkCount);
    errdefer allocator.free(chunks);
    for (chunks, 0..) |*chunk, chunk_index| {
        const data = try allocator.alloc(u8, LargeBytesChunkLen);
        for (data, 0..) |*byte, i| byte.* = @intCast((chunk_index * 17 + i * 13 + 3) & 0xff);
        chunk.* = data;
    }
    msg.chunks = chunks;
    return msg;
}

fn presenceChild(id: i32, label: []const u8) person_pb.demo.PresenceMix.Child {
    var child = person_pb.demo.PresenceMix.Child.init();
    child.id = id;
    child.label = label;
    return child;
}

fn makeGeneratedPresenceMix(allocator: std.mem.Allocator) !person_pb.demo.PresenceMix {
    var msg = person_pb.demo.PresenceMix.init();
    errdefer msg.deinit(allocator);
    msg._count = .{ .count = 0 };
    msg._note = .{ .note = "" };
    msg._raw = .{ .raw = "presence-raw" };
    msg.child = try presenceChild(7, "child").cloneOwned(allocator);
    msg.pick = .{ .nested = try presenceChild(11, "nested").cloneOwned(allocator) };
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

fn makeGeneratedSFixedPacked(allocator: std.mem.Allocator) !person_pb.demo.SFixedPacked {
    var packed_msg = person_pb.demo.SFixedPacked.init();
    errdefer packed_msg.deinit(allocator);
    const values = try allocator.alloc(i32, 1024);
    for (values, 0..) |*value, i| {
        const magnitude: i32 = @intCast(i * 7 + 1);
        value.* = if ((i & 1) == 0) magnitude else -magnitude;
    }
    packed_msg.values = values;
    return packed_msg;
}

fn makeGeneratedSFixed64Packed(allocator: std.mem.Allocator) !person_pb.demo.SFixed64Packed {
    var packed_msg = person_pb.demo.SFixed64Packed.init();
    errdefer packed_msg.deinit(allocator);
    const values = try allocator.alloc(i64, 1024);
    for (values, 0..) |*value, i| {
        const magnitude: i64 = @intCast((@as(u64, i) << 20) + i * 11 + 1);
        value.* = if ((i & 1) == 0) magnitude else -magnitude;
    }
    packed_msg.values = values;
    return packed_msg;
}

fn makeGeneratedFloatPacked(allocator: std.mem.Allocator) !person_pb.demo.FloatPacked {
    var packed_msg = person_pb.demo.FloatPacked.init();
    errdefer packed_msg.deinit(allocator);
    const values = try allocator.alloc(f32, 1024);
    for (values, 0..) |*value, i| value.* = @as(f32, @floatFromInt(i)) * 0.25 + 1.0;
    packed_msg.values = values;
    return packed_msg;
}

fn makeGeneratedDoublePacked(allocator: std.mem.Allocator) !person_pb.demo.DoublePacked {
    var packed_msg = person_pb.demo.DoublePacked.init();
    errdefer packed_msg.deinit(allocator);
    const values = try allocator.alloc(f64, 1024);
    for (values, 0..) |*value, i| value.* = @as(f64, @floatFromInt(i)) * 0.5 + 1.0;
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

fn makeGeneratedUInt32Packed(allocator: std.mem.Allocator) !person_pb.demo.UInt32Packed {
    var packed_msg = person_pb.demo.UInt32Packed.init();
    errdefer packed_msg.deinit(allocator);
    const values = try allocator.alloc(u32, 1024);
    for (values, 0..) |*value, i| value.* = @intCast((i << 12) + i * 3 + 1);
    packed_msg.values = values;
    return packed_msg;
}

fn makeGeneratedInt64Packed(allocator: std.mem.Allocator) !person_pb.demo.Int64Packed {
    var packed_msg = person_pb.demo.Int64Packed.init();
    errdefer packed_msg.deinit(allocator);
    const values = try allocator.alloc(i64, 1024);
    for (values, 0..) |*value, i| {
        const magnitude: i64 = @intCast((@as(u64, i) << 20) + i * 7 + 1);
        value.* = if ((i & 1) == 0) magnitude else -magnitude;
    }
    packed_msg.values = values;
    return packed_msg;
}

fn makeGeneratedSInt32Packed(allocator: std.mem.Allocator) !person_pb.demo.SInt32Packed {
    var packed_msg = person_pb.demo.SInt32Packed.init();
    errdefer packed_msg.deinit(allocator);
    const values = try allocator.alloc(i32, 1024);
    for (values, 0..) |*value, i| {
        const magnitude: i32 = @intCast(i * 5 + 1);
        value.* = if ((i & 1) == 0) magnitude else -magnitude;
    }
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

fn makeGeneratedLargeMap(allocator: std.mem.Allocator) !person_pb.demo.LargeMap {
    var msg = person_pb.demo.LargeMap.init();
    errdefer msg.deinit(allocator);
    try msg.counts.ensureTotalCapacity(allocator, LargeMapEntryCount);
    var key_buf: [32]u8 = undefined;
    var i: usize = 0;
    while (i < LargeMapEntryCount) : (i += 1) {
        const key = try std.fmt.bufPrint(&key_buf, "key-{d:0>4}", .{i});
        try msg.counts.put(allocator, try allocator.dupe(u8, key), @intCast((i % 4096) + 1));
    }
    return msg;
}

fn shuffledLargeMapIndex(i: usize) usize {
    return (i * LargeMapShuffleMultiplier + LargeMapShuffleIncrement) % LargeMapEntryCount;
}

fn makeGeneratedShuffledLargeMap(allocator: std.mem.Allocator) !person_pb.demo.LargeMap {
    var msg = person_pb.demo.LargeMap.init();
    errdefer msg.deinit(allocator);
    try msg.counts.ensureTotalCapacity(allocator, LargeMapEntryCount);
    var key_buf: [32]u8 = undefined;
    var i: usize = 0;
    while (i < LargeMapEntryCount) : (i += 1) {
        const key_index = shuffledLargeMapIndex(i);
        const key = try std.fmt.bufPrint(&key_buf, "key-{d:0>4}", .{key_index});
        try msg.counts.put(allocator, try allocator.dupe(u8, key), @intCast((key_index % 4096) + 1));
    }
    return msg;
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

fn makeDynamicSFixedPacked(allocator: std.mem.Allocator, desc: *const pbz.MessageDescriptor) !pbz.DynamicMessage {
    var msg = pbz.DynamicMessage.init(allocator, desc);
    errdefer msg.deinit();
    var i: usize = 0;
    while (i < 1024) : (i += 1) {
        const magnitude: i32 = @intCast(i * 7 + 1);
        try msg.add(desc.findField("values").?, .{ .sfixed32 = if ((i & 1) == 0) magnitude else -magnitude });
    }
    return msg;
}

fn makeDynamicSFixed64Packed(allocator: std.mem.Allocator, desc: *const pbz.MessageDescriptor) !pbz.DynamicMessage {
    var msg = pbz.DynamicMessage.init(allocator, desc);
    errdefer msg.deinit();
    var i: usize = 0;
    while (i < 1024) : (i += 1) {
        const magnitude: i64 = @intCast((@as(u64, i) << 20) + i * 11 + 1);
        try msg.add(desc.findField("values").?, .{ .sfixed64 = if ((i & 1) == 0) magnitude else -magnitude });
    }
    return msg;
}

fn makeDynamicFloatPacked(allocator: std.mem.Allocator, desc: *const pbz.MessageDescriptor) !pbz.DynamicMessage {
    var msg = pbz.DynamicMessage.init(allocator, desc);
    errdefer msg.deinit();
    var i: usize = 0;
    while (i < 1024) : (i += 1) try msg.add(desc.findField("values").?, .{ .float = @as(f32, @floatFromInt(i)) * 0.25 + 1.0 });
    return msg;
}

fn makeDynamicDoublePacked(allocator: std.mem.Allocator, desc: *const pbz.MessageDescriptor) !pbz.DynamicMessage {
    var msg = pbz.DynamicMessage.init(allocator, desc);
    errdefer msg.deinit();
    var i: usize = 0;
    while (i < 1024) : (i += 1) try msg.add(desc.findField("values").?, .{ .double = @as(f64, @floatFromInt(i)) * 0.5 + 1.0 });
    return msg;
}

fn makeDynamicUInt64Packed(allocator: std.mem.Allocator, desc: *const pbz.MessageDescriptor) !pbz.DynamicMessage {
    var msg = pbz.DynamicMessage.init(allocator, desc);
    errdefer msg.deinit();
    var i: usize = 0;
    while (i < 1024) : (i += 1) try msg.add(desc.findField("values").?, .{ .uint64 = @intCast((@as(u64, i) << 21) + i * 17 + 1) });
    return msg;
}

fn makeDynamicUInt32Packed(allocator: std.mem.Allocator, desc: *const pbz.MessageDescriptor) !pbz.DynamicMessage {
    var msg = pbz.DynamicMessage.init(allocator, desc);
    errdefer msg.deinit();
    var i: usize = 0;
    while (i < 1024) : (i += 1) try msg.add(desc.findField("values").?, .{ .uint32 = @intCast((i << 12) + i * 3 + 1) });
    return msg;
}

fn makeDynamicInt64Packed(allocator: std.mem.Allocator, desc: *const pbz.MessageDescriptor) !pbz.DynamicMessage {
    var msg = pbz.DynamicMessage.init(allocator, desc);
    errdefer msg.deinit();
    var i: usize = 0;
    while (i < 1024) : (i += 1) {
        const magnitude: i64 = @intCast((@as(u64, i) << 20) + i * 7 + 1);
        try msg.add(desc.findField("values").?, .{ .int64 = if ((i & 1) == 0) magnitude else -magnitude });
    }
    return msg;
}

fn makeDynamicSInt32Packed(allocator: std.mem.Allocator, desc: *const pbz.MessageDescriptor) !pbz.DynamicMessage {
    var msg = pbz.DynamicMessage.init(allocator, desc);
    errdefer msg.deinit();
    var i: usize = 0;
    while (i < 1024) : (i += 1) {
        const magnitude: i32 = @intCast(i * 5 + 1);
        try msg.add(desc.findField("values").?, .{ .sint32 = if ((i & 1) == 0) magnitude else -magnitude });
    }
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

fn makeDynamicLargeMap(allocator: std.mem.Allocator, desc: *const pbz.MessageDescriptor) !pbz.DynamicMessage {
    var msg = pbz.DynamicMessage.init(allocator, desc);
    errdefer msg.deinit();
    var key_buf: [32]u8 = undefined;
    var i: usize = 0;
    while (i < LargeMapEntryCount) : (i += 1) {
        const key = try std.fmt.bufPrint(&key_buf, "key-{d:0>4}", .{i});
        const entry = try allocator.create(pbz.dynamic.MapEntry);
        entry.* = .{ .key = .{ .string = try allocator.dupe(u8, key) }, .value = .{ .int32 = @intCast((i % 4096) + 1) } };
        try msg.add(desc.findField("counts").?, .{ .map_entry = entry });
    }
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

fn generatedScalarMixKnownDecodeReuse(ctx: GeneratedScalarMixDecodeReuseCtx) !void {
    try ctx.message.decodeKnownReuse(ctx.allocator, ctx.bytes);
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

fn generatedTextBytesTrustedUtf8EncodeIntoReuse(ctx: GeneratedTextBytesEncodeIntoCtx) !void {
    const bytes = try ctx.message.encodeIntoAssumeCapacityTrustedUtf8(ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

const GeneratedTextBytesBorrowedSlicesCtx = struct { message: *const person_pb.demo.TextBytes };
fn generatedTextBytesBorrowedSlices(ctx: GeneratedTextBytesBorrowedSlicesCtx) !void {
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

const GeneratedTextBytesDecodeCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };
fn generatedTextBytesDecode(ctx: GeneratedTextBytesDecodeCtx) !void {
    var decoded = try person_pb.demo.TextBytes.decode(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

const GeneratedTextBytesDecodeReuseCtx = struct { allocator: std.mem.Allocator, bytes: []const u8, message: *person_pb.demo.TextBytes };
fn generatedTextBytesDecodeReuse(ctx: GeneratedTextBytesDecodeReuseCtx) !void {
    try ctx.message.decodeReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

const GeneratedLargeBytesEncodeCtx = struct { allocator: std.mem.Allocator, message: *const person_pb.demo.LargeBytes };
fn generatedLargeBytesEncode(ctx: GeneratedLargeBytesEncodeCtx) !void {
    const bytes = try ctx.message.encode(ctx.allocator);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.allocator.free(bytes);
}

const GeneratedLargeBytesWriteToCtx = struct { writer: *pbz.Writer, message: *const person_pb.demo.LargeBytes };
fn generatedLargeBytesWriteToReuse(ctx: GeneratedLargeBytesWriteToCtx) !void {
    ctx.writer.clearRetainingCapacity();
    try ctx.message.writeToAssumeCapacity(ctx.writer);
    std.mem.doNotOptimizeAway(ctx.writer.slice().ptr);
}

const GeneratedLargeBytesEncodeIntoCtx = struct { buffer: []u8, message: *const person_pb.demo.LargeBytes };
fn generatedLargeBytesEncodeIntoReuse(ctx: GeneratedLargeBytesEncodeIntoCtx) !void {
    const bytes = try ctx.message.encodeIntoAssumeCapacity(ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

const GeneratedLargeBytesBorrowedSlicesCtx = struct { message: *const person_pb.demo.LargeBytes };
fn generatedLargeBytesBorrowedSlices(ctx: GeneratedLargeBytesBorrowedSlicesCtx) !void {
    var header: [LargeBytesChunkCount + 1][20]u8 = undefined;
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

const GeneratedLargeBytesDecodeCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };
fn generatedLargeBytesDecode(ctx: GeneratedLargeBytesDecodeCtx) !void {
    var decoded = try person_pb.demo.LargeBytes.decode(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

const GeneratedLargeBytesDecodeReuseCtx = struct { allocator: std.mem.Allocator, bytes: []const u8, message: *person_pb.demo.LargeBytes };
fn generatedLargeBytesDecodeReuse(ctx: GeneratedLargeBytesDecodeReuseCtx) !void {
    try ctx.message.decodeReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

const GeneratedPresenceMixEncodeCtx = struct { allocator: std.mem.Allocator, message: *const person_pb.demo.PresenceMix };
fn generatedPresenceMixEncode(ctx: GeneratedPresenceMixEncodeCtx) !void {
    const bytes = try ctx.message.encode(ctx.allocator);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.allocator.free(bytes);
}

const GeneratedPresenceMixWriteToCtx = struct { writer: *pbz.Writer, message: *const person_pb.demo.PresenceMix };
fn generatedPresenceMixWriteToReuse(ctx: GeneratedPresenceMixWriteToCtx) !void {
    ctx.writer.clearRetainingCapacity();
    try ctx.message.writeToAssumeCapacity(ctx.writer);
    std.mem.doNotOptimizeAway(ctx.writer.slice().ptr);
}

const GeneratedPresenceMixEncodeIntoCtx = struct { buffer: []u8, message: *const person_pb.demo.PresenceMix };
fn generatedPresenceMixEncodeIntoReuse(ctx: GeneratedPresenceMixEncodeIntoCtx) !void {
    const bytes = try ctx.message.encodeIntoAssumeCapacity(ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

fn generatedPresenceMixTrustedUtf8EncodeIntoReuse(ctx: GeneratedPresenceMixEncodeIntoCtx) !void {
    const bytes = try ctx.message.encodeIntoAssumeCapacityTrustedUtf8(ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

const GeneratedPresenceMixDecodeCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };
fn generatedPresenceMixDecode(ctx: GeneratedPresenceMixDecodeCtx) !void {
    var decoded = try person_pb.demo.PresenceMix.decode(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

const GeneratedPresenceMixDecodeReuseCtx = struct { allocator: std.mem.Allocator, bytes: []const u8, message: *person_pb.demo.PresenceMix };
fn generatedPresenceMixDecodeReuse(ctx: GeneratedPresenceMixDecodeReuseCtx) !void {
    try ctx.message.decodeReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

const LargeBytesBorrowedViewCtx = struct { bytes: []const u8 };
fn largeBytesBorrowedViewDecode(ctx: LargeBytesBorrowedViewCtx) !void {
    const payload = (try person_pb.demo.LargeBytes.payloadBytesView(ctx.bytes)) orelse return error.InvalidWireType;
    std.mem.doNotOptimizeAway(payload.ptr);
    var reader = pbz.Reader.init(ctx.bytes);
    var total_chunks: usize = 0;
    while (try reader.nextTag()) |tag| {
        if (tag.number == 2) {
            if (tag.wire_type != .length_delimited) return error.InvalidWireType;
            const chunk = try reader.readBytes();
            total_chunks += chunk.len;
        } else {
            try reader.skipValue(tag);
        }
    }
    std.mem.doNotOptimizeAway(total_chunks);
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

const GeneratedComplexManualEncodeIntoCtx = struct { buffer: []u8, message: *const person_pb.demo.Complex };
fn generatedComplexManualEncodeIntoReuse(ctx: GeneratedComplexManualEncodeIntoCtx) !void {
    const bytes = try ctx.message.encodeIntoAssumeCapacityTrustedUtf8(ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

const GeneratedComplexDecodeCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };
fn generatedComplexDecode(ctx: GeneratedComplexDecodeCtx) !void {
    var decoded = try person_pb.demo.Complex.decode(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

const GeneratedComplexDecodeReuseCtx = struct { allocator: std.mem.Allocator, bytes: []const u8, message: *person_pb.demo.Complex };
fn generatedComplexDecodeReuse(ctx: GeneratedComplexDecodeReuseCtx) !void {
    try ctx.message.decodeReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
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

const GeneratedPackedDecodeReuseCtx = struct { allocator: std.mem.Allocator, bytes: []const u8, message: *person_pb.demo.Packed };
fn generatedPackedKnownDecodeReuse(ctx: GeneratedPackedDecodeReuseCtx) !void {
    try ctx.message.decodeKnownReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
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

const GeneratedFixedPackedDecodeReuseCtx = struct { allocator: std.mem.Allocator, bytes: []const u8, message: *person_pb.demo.FixedPacked };
fn generatedFixedPackedKnownDecodeReuse(ctx: GeneratedFixedPackedDecodeReuseCtx) !void {
    try ctx.message.decodeKnownReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
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

const GeneratedFixed64PackedDecodeReuseCtx = struct { allocator: std.mem.Allocator, bytes: []const u8, message: *person_pb.demo.Fixed64Packed };
fn generatedFixed64PackedKnownDecodeReuse(ctx: GeneratedFixed64PackedDecodeReuseCtx) !void {
    try ctx.message.decodeKnownReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

const GeneratedSFixedPackedEncodeCtx = struct { allocator: std.mem.Allocator, message: *const person_pb.demo.SFixedPacked };
fn generatedSFixedPackedEncode(ctx: GeneratedSFixedPackedEncodeCtx) !void {
    const bytes = try ctx.message.encode(ctx.allocator);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.allocator.free(bytes);
}

const GeneratedSFixedPackedEncodeIntoCtx = struct { buffer: []u8, message: *const person_pb.demo.SFixedPacked };
fn generatedSFixedPackedEncodeIntoReuse(ctx: GeneratedSFixedPackedEncodeIntoCtx) !void {
    const bytes = try ctx.message.encodeIntoAssumeCapacity(ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

const GeneratedSFixedPackedSlicesCtx = struct { message: *const person_pb.demo.SFixedPacked };
fn generatedSFixedPackedBorrowedSlices(ctx: GeneratedSFixedPackedSlicesCtx) !void {
    var header: [20]u8 = undefined;
    const slices = try person_pb.demo.SFixedPacked.valuesPackedFixedSlices(&header, ctx.message.values);
    std.mem.doNotOptimizeAway(slices.header.ptr);
    std.mem.doNotOptimizeAway(slices.payload.ptr);
}

const GeneratedSFixedPackedDecodeCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };
fn generatedSFixedPackedDecode(ctx: GeneratedSFixedPackedDecodeCtx) !void {
    var decoded = try person_pb.demo.SFixedPacked.decode(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

const GeneratedSFixedPackedDecodeReuseCtx = struct { allocator: std.mem.Allocator, bytes: []const u8, message: *person_pb.demo.SFixedPacked };
fn generatedSFixedPackedKnownDecodeReuse(ctx: GeneratedSFixedPackedDecodeReuseCtx) !void {
    try ctx.message.decodeKnownReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

const GeneratedSFixed64PackedEncodeCtx = struct { allocator: std.mem.Allocator, message: *const person_pb.demo.SFixed64Packed };
fn generatedSFixed64PackedEncode(ctx: GeneratedSFixed64PackedEncodeCtx) !void {
    const bytes = try ctx.message.encode(ctx.allocator);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.allocator.free(bytes);
}

const GeneratedSFixed64PackedEncodeIntoCtx = struct { buffer: []u8, message: *const person_pb.demo.SFixed64Packed };
fn generatedSFixed64PackedEncodeIntoReuse(ctx: GeneratedSFixed64PackedEncodeIntoCtx) !void {
    const bytes = try ctx.message.encodeIntoAssumeCapacity(ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

const GeneratedSFixed64PackedSlicesCtx = struct { message: *const person_pb.demo.SFixed64Packed };
fn generatedSFixed64PackedBorrowedSlices(ctx: GeneratedSFixed64PackedSlicesCtx) !void {
    var header: [20]u8 = undefined;
    const slices = try person_pb.demo.SFixed64Packed.valuesPackedFixedSlices(&header, ctx.message.values);
    std.mem.doNotOptimizeAway(slices.header.ptr);
    std.mem.doNotOptimizeAway(slices.payload.ptr);
}

const GeneratedSFixed64PackedDecodeCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };
fn generatedSFixed64PackedDecode(ctx: GeneratedSFixed64PackedDecodeCtx) !void {
    var decoded = try person_pb.demo.SFixed64Packed.decode(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

const GeneratedSFixed64PackedDecodeReuseCtx = struct { allocator: std.mem.Allocator, bytes: []const u8, message: *person_pb.demo.SFixed64Packed };
fn generatedSFixed64PackedKnownDecodeReuse(ctx: GeneratedSFixed64PackedDecodeReuseCtx) !void {
    try ctx.message.decodeKnownReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

const GeneratedFloatPackedEncodeCtx = struct { allocator: std.mem.Allocator, message: *const person_pb.demo.FloatPacked };
fn generatedFloatPackedEncode(ctx: GeneratedFloatPackedEncodeCtx) !void {
    const bytes = try ctx.message.encode(ctx.allocator);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.allocator.free(bytes);
}

const GeneratedFloatPackedEncodeIntoCtx = struct { buffer: []u8, message: *const person_pb.demo.FloatPacked };
fn generatedFloatPackedEncodeIntoReuse(ctx: GeneratedFloatPackedEncodeIntoCtx) !void {
    const bytes = try ctx.message.encodeIntoAssumeCapacity(ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

const GeneratedFloatPackedSlicesCtx = struct { message: *const person_pb.demo.FloatPacked };
fn generatedFloatPackedBorrowedSlices(ctx: GeneratedFloatPackedSlicesCtx) !void {
    var header: [20]u8 = undefined;
    const slices = try person_pb.demo.FloatPacked.valuesPackedFixedSlices(&header, ctx.message.values);
    std.mem.doNotOptimizeAway(slices.header.ptr);
    std.mem.doNotOptimizeAway(slices.payload.ptr);
}

const GeneratedFloatPackedDecodeCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };
fn generatedFloatPackedDecode(ctx: GeneratedFloatPackedDecodeCtx) !void {
    var decoded = try person_pb.demo.FloatPacked.decode(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

const GeneratedFloatPackedDecodeReuseCtx = struct { allocator: std.mem.Allocator, bytes: []const u8, message: *person_pb.demo.FloatPacked };
fn generatedFloatPackedKnownDecodeReuse(ctx: GeneratedFloatPackedDecodeReuseCtx) !void {
    try ctx.message.decodeKnownReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

const GeneratedDoublePackedEncodeCtx = struct { allocator: std.mem.Allocator, message: *const person_pb.demo.DoublePacked };
fn generatedDoublePackedEncode(ctx: GeneratedDoublePackedEncodeCtx) !void {
    const bytes = try ctx.message.encode(ctx.allocator);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.allocator.free(bytes);
}

const GeneratedDoublePackedEncodeIntoCtx = struct { buffer: []u8, message: *const person_pb.demo.DoublePacked };
fn generatedDoublePackedEncodeIntoReuse(ctx: GeneratedDoublePackedEncodeIntoCtx) !void {
    const bytes = try ctx.message.encodeIntoAssumeCapacity(ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

const GeneratedDoublePackedSlicesCtx = struct { message: *const person_pb.demo.DoublePacked };
fn generatedDoublePackedBorrowedSlices(ctx: GeneratedDoublePackedSlicesCtx) !void {
    var header: [20]u8 = undefined;
    const slices = try person_pb.demo.DoublePacked.valuesPackedFixedSlices(&header, ctx.message.values);
    std.mem.doNotOptimizeAway(slices.header.ptr);
    std.mem.doNotOptimizeAway(slices.payload.ptr);
}

const GeneratedDoublePackedDecodeCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };
fn generatedDoublePackedDecode(ctx: GeneratedDoublePackedDecodeCtx) !void {
    var decoded = try person_pb.demo.DoublePacked.decode(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

const GeneratedDoublePackedDecodeReuseCtx = struct { allocator: std.mem.Allocator, bytes: []const u8, message: *person_pb.demo.DoublePacked };
fn generatedDoublePackedKnownDecodeReuse(ctx: GeneratedDoublePackedDecodeReuseCtx) !void {
    try ctx.message.decodeKnownReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
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

fn generatedUInt64PackedKnownDecodeReuse(ctx: GeneratedUInt64PackedDecodeReuseCtx) !void {
    try ctx.message.decodeKnownReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

const GeneratedUInt32PackedEncodeCtx = struct { allocator: std.mem.Allocator, message: *const person_pb.demo.UInt32Packed };
fn generatedUInt32PackedEncode(ctx: GeneratedUInt32PackedEncodeCtx) !void {
    const bytes = try ctx.message.encode(ctx.allocator);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.allocator.free(bytes);
}

const GeneratedUInt32PackedEncodeIntoCtx = struct { buffer: []u8, message: *const person_pb.demo.UInt32Packed };
fn generatedUInt32PackedEncodeIntoReuse(ctx: GeneratedUInt32PackedEncodeIntoCtx) !void {
    const bytes = try ctx.message.encodeIntoAssumeCapacity(ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

const GeneratedUInt32PackedDecodeCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };
fn generatedUInt32PackedDecode(ctx: GeneratedUInt32PackedDecodeCtx) !void {
    var decoded = try person_pb.demo.UInt32Packed.decode(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

const GeneratedUInt32PackedDecodeReuseCtx = struct { allocator: std.mem.Allocator, bytes: []const u8, message: *person_pb.demo.UInt32Packed };
fn generatedUInt32PackedDecodeReuse(ctx: GeneratedUInt32PackedDecodeReuseCtx) !void {
    try ctx.message.decodeReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

fn generatedUInt32PackedKnownDecodeReuse(ctx: GeneratedUInt32PackedDecodeReuseCtx) !void {
    try ctx.message.decodeKnownReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

const GeneratedInt64PackedEncodeCtx = struct { allocator: std.mem.Allocator, message: *const person_pb.demo.Int64Packed };
fn generatedInt64PackedEncode(ctx: GeneratedInt64PackedEncodeCtx) !void {
    const bytes = try ctx.message.encode(ctx.allocator);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.allocator.free(bytes);
}

const GeneratedInt64PackedEncodeIntoCtx = struct { buffer: []u8, message: *const person_pb.demo.Int64Packed };
fn generatedInt64PackedEncodeIntoReuse(ctx: GeneratedInt64PackedEncodeIntoCtx) !void {
    const bytes = try ctx.message.encodeIntoAssumeCapacity(ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

const GeneratedInt64PackedDecodeCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };
fn generatedInt64PackedDecode(ctx: GeneratedInt64PackedDecodeCtx) !void {
    var decoded = try person_pb.demo.Int64Packed.decode(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

const GeneratedInt64PackedDecodeReuseCtx = struct { allocator: std.mem.Allocator, bytes: []const u8, message: *person_pb.demo.Int64Packed };
fn generatedInt64PackedKnownDecodeReuse(ctx: GeneratedInt64PackedDecodeReuseCtx) !void {
    try ctx.message.decodeKnownReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

const GeneratedSInt32PackedEncodeCtx = struct { allocator: std.mem.Allocator, message: *const person_pb.demo.SInt32Packed };
fn generatedSInt32PackedEncode(ctx: GeneratedSInt32PackedEncodeCtx) !void {
    const bytes = try ctx.message.encode(ctx.allocator);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.allocator.free(bytes);
}

const GeneratedSInt32PackedEncodeIntoCtx = struct { buffer: []u8, message: *const person_pb.demo.SInt32Packed };
fn generatedSInt32PackedEncodeIntoReuse(ctx: GeneratedSInt32PackedEncodeIntoCtx) !void {
    const bytes = try ctx.message.encodeIntoAssumeCapacity(ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

const GeneratedSInt32PackedDecodeCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };
fn generatedSInt32PackedDecode(ctx: GeneratedSInt32PackedDecodeCtx) !void {
    var decoded = try person_pb.demo.SInt32Packed.decode(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

const GeneratedSInt32PackedDecodeReuseCtx = struct { allocator: std.mem.Allocator, bytes: []const u8, message: *person_pb.demo.SInt32Packed };
fn generatedSInt32PackedKnownDecodeReuse(ctx: GeneratedSInt32PackedDecodeReuseCtx) !void {
    try ctx.message.decodeKnownReuse(ctx.allocator, ctx.bytes);
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

const GeneratedSInt64PackedDecodeReuseCtx = struct { allocator: std.mem.Allocator, bytes: []const u8, message: *person_pb.demo.SInt64Packed };
fn generatedSInt64PackedKnownDecodeReuse(ctx: GeneratedSInt64PackedDecodeReuseCtx) !void {
    try ctx.message.decodeKnownReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
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

const GeneratedBoolPackedSlicesCtx = struct { message: *const person_pb.demo.BoolPacked };
fn generatedBoolPackedBorrowedSlices(ctx: GeneratedBoolPackedSlicesCtx) !void {
    var header: [20]u8 = undefined;
    const slices = try person_pb.demo.BoolPacked.valuesPackedBoolSlices(&header, ctx.message.values);
    std.mem.doNotOptimizeAway(slices.header.ptr);
    std.mem.doNotOptimizeAway(slices.payload.ptr);
}

const GeneratedBoolPackedDecodeCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };
fn generatedBoolPackedDecode(ctx: GeneratedBoolPackedDecodeCtx) !void {
    var decoded = try person_pb.demo.BoolPacked.decode(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

const GeneratedBoolPackedDecodeReuseCtx = struct { allocator: std.mem.Allocator, bytes: []const u8, message: *person_pb.demo.BoolPacked };
fn generatedBoolPackedKnownDecodeReuse(ctx: GeneratedBoolPackedDecodeReuseCtx) !void {
    try ctx.message.decodeKnownReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
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

fn generatedEnumPackedKnownDecodeReuse(ctx: GeneratedEnumPackedDecodeReuseCtx) !void {
    try ctx.message.decodeKnownReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

const GeneratedLargeMapEncodeCtx = struct { allocator: std.mem.Allocator, message: *const person_pb.demo.LargeMap };
fn generatedLargeMapEncode(ctx: GeneratedLargeMapEncodeCtx) !void {
    const bytes = try ctx.message.encode(ctx.allocator);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.allocator.free(bytes);
}

const GeneratedLargeMapWriteToCtx = struct { writer: *pbz.Writer, message: *const person_pb.demo.LargeMap };
fn generatedLargeMapWriteToReuse(ctx: GeneratedLargeMapWriteToCtx) !void {
    ctx.writer.clearRetainingCapacity();
    try ctx.message.writeToAssumeCapacity(ctx.writer);
    std.mem.doNotOptimizeAway(ctx.writer.slice().ptr);
}

const GeneratedLargeMapEncodeIntoCtx = struct { buffer: []u8, message: *const person_pb.demo.LargeMap };
fn generatedLargeMapEncodeIntoReuse(ctx: GeneratedLargeMapEncodeIntoCtx) !void {
    const bytes = try ctx.message.encodeIntoAssumeCapacity(ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

const GeneratedLargeMapDeterministicEncodeIntoCtx = struct { allocator: std.mem.Allocator, buffer: []u8, message: *const person_pb.demo.LargeMap };
fn generatedLargeMapDeterministicEncodeIntoReuse(ctx: GeneratedLargeMapDeterministicEncodeIntoCtx) !void {
    const bytes = try ctx.message.encodeDeterministicIntoAssumeCapacity(ctx.allocator, ctx.buffer);
    std.mem.doNotOptimizeAway(bytes.ptr);
}

const GeneratedLargeMapDecodeCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };
fn generatedLargeMapDecode(ctx: GeneratedLargeMapDecodeCtx) !void {
    var decoded = try person_pb.demo.LargeMap.decode(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    decoded.deinit(ctx.allocator);
}

const GeneratedLargeMapDecodeReuseCtx = struct { allocator: std.mem.Allocator, bytes: []const u8, message: *person_pb.demo.LargeMap };
fn generatedLargeMapDecodeReuse(ctx: GeneratedLargeMapDecodeReuseCtx) !void {
    try ctx.message.decodeReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

const Int32PackedIteratorCtx = struct { bytes: []const u8 };
fn int32PackedIteratorDecode(ctx: Int32PackedIteratorCtx) !void {
    var it = (try person_pb.demo.Packed.valuesPackedIterator(ctx.bytes)) orelse return error.InvalidWireType;
    var sum: i32 = 0;
    while (try it.next()) |value| sum +%= value;
    std.mem.doNotOptimizeAway(sum);
}

const UInt64PackedIteratorCtx = struct { bytes: []const u8 };
fn uint64PackedIteratorDecode(ctx: UInt64PackedIteratorCtx) !void {
    var it = (try person_pb.demo.UInt64Packed.valuesPackedIterator(ctx.bytes)) orelse return error.InvalidWireType;
    var sum: u64 = 0;
    while (try it.next()) |value| sum +%= value;
    std.mem.doNotOptimizeAway(sum);
}

const UInt32PackedIteratorCtx = struct { bytes: []const u8 };
fn uint32PackedIteratorDecode(ctx: UInt32PackedIteratorCtx) !void {
    var it = (try person_pb.demo.UInt32Packed.valuesPackedIterator(ctx.bytes)) orelse return error.InvalidWireType;
    var sum: u32 = 0;
    while (try it.next()) |value| sum +%= value;
    std.mem.doNotOptimizeAway(sum);
}

const Int64PackedIteratorCtx = struct { bytes: []const u8 };
fn int64PackedIteratorDecode(ctx: Int64PackedIteratorCtx) !void {
    var it = (try person_pb.demo.Int64Packed.valuesPackedIterator(ctx.bytes)) orelse return error.InvalidWireType;
    var sum: i64 = 0;
    while (try it.next()) |value| sum +%= value;
    std.mem.doNotOptimizeAway(sum);
}

const SInt32PackedIteratorCtx = struct { bytes: []const u8 };
fn sint32PackedIteratorDecode(ctx: SInt32PackedIteratorCtx) !void {
    var it = (try person_pb.demo.SInt32Packed.valuesPackedIterator(ctx.bytes)) orelse return error.InvalidWireType;
    var sum: i32 = 0;
    while (try it.next()) |value| sum +%= value;
    std.mem.doNotOptimizeAway(sum);
}

const SInt64PackedIteratorCtx = struct { bytes: []const u8 };
fn sint64PackedIteratorDecode(ctx: SInt64PackedIteratorCtx) !void {
    var it = (try person_pb.demo.SInt64Packed.valuesPackedIterator(ctx.bytes)) orelse return error.InvalidWireType;
    var sum: i64 = 0;
    while (try it.next()) |value| sum +%= value;
    std.mem.doNotOptimizeAway(sum);
}

const Fixed64PackedBorrowedViewCtx = struct { bytes: []const u8 };
fn fixed64PackedBorrowedViewDecode(ctx: Fixed64PackedBorrowedViewCtx) !void {
    const values = (try person_pb.demo.Fixed64Packed.valuesPackedFixedView(ctx.bytes)) orelse return error.InvalidWireType;
    std.mem.doNotOptimizeAway(values.ptr);
}

const SFixedPackedBorrowedViewCtx = struct { bytes: []const u8 };
fn sfixedPackedBorrowedViewDecode(ctx: SFixedPackedBorrowedViewCtx) !void {
    const values = (try person_pb.demo.SFixedPacked.valuesPackedFixedView(ctx.bytes)) orelse return error.InvalidWireType;
    std.mem.doNotOptimizeAway(values.ptr);
}

const SFixed64PackedBorrowedViewCtx = struct { bytes: []const u8 };
fn sfixed64PackedBorrowedViewDecode(ctx: SFixed64PackedBorrowedViewCtx) !void {
    const values = (try person_pb.demo.SFixed64Packed.valuesPackedFixedView(ctx.bytes)) orelse return error.InvalidWireType;
    std.mem.doNotOptimizeAway(values.ptr);
}

const FloatPackedBorrowedViewCtx = struct { bytes: []const u8 };
fn floatPackedBorrowedViewDecode(ctx: FloatPackedBorrowedViewCtx) !void {
    const values = (try person_pb.demo.FloatPacked.valuesPackedFixedView(ctx.bytes)) orelse return error.InvalidWireType;
    std.mem.doNotOptimizeAway(values.ptr);
}

const DoublePackedBorrowedViewCtx = struct { bytes: []const u8 };
fn doublePackedBorrowedViewDecode(ctx: DoublePackedBorrowedViewCtx) !void {
    const values = (try person_pb.demo.DoublePacked.valuesPackedFixedView(ctx.bytes)) orelse return error.InvalidWireType;
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

const DynamicSFixedPackedEncodeCtx = struct { message: *const pbz.DynamicMessage, file: *const pbz.FileDescriptor };
fn dynamicSFixedPackedEncode(ctx: DynamicSFixedPackedEncodeCtx) !void {
    const bytes = try ctx.message.encoded(ctx.file);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.message.allocator.free(bytes);
}

const DynamicSFixedPackedDecodeCtx = struct { allocator: std.mem.Allocator, descriptor: *const pbz.MessageDescriptor, file: *const pbz.FileDescriptor, bytes: []const u8 };
fn dynamicSFixedPackedDecode(ctx: DynamicSFixedPackedDecodeCtx) !void {
    var msg = pbz.DynamicMessage.init(ctx.allocator, ctx.descriptor);
    defer msg.deinit();
    try msg.decode(ctx.file, ctx.bytes);
    std.mem.doNotOptimizeAway(&msg);
}

const DynamicSFixedPackedDecodeReuseCtx = struct { message: *pbz.DynamicMessage, file: *const pbz.FileDescriptor, bytes: []const u8 };
fn dynamicSFixedPackedDecodeReuse(ctx: DynamicSFixedPackedDecodeReuseCtx) !void {
    try ctx.message.decode(ctx.file, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

const DynamicSFixed64PackedEncodeCtx = struct { message: *const pbz.DynamicMessage, file: *const pbz.FileDescriptor };
fn dynamicSFixed64PackedEncode(ctx: DynamicSFixed64PackedEncodeCtx) !void {
    const bytes = try ctx.message.encoded(ctx.file);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.message.allocator.free(bytes);
}

const DynamicSFixed64PackedDecodeCtx = struct { allocator: std.mem.Allocator, descriptor: *const pbz.MessageDescriptor, file: *const pbz.FileDescriptor, bytes: []const u8 };
fn dynamicSFixed64PackedDecode(ctx: DynamicSFixed64PackedDecodeCtx) !void {
    var msg = pbz.DynamicMessage.init(ctx.allocator, ctx.descriptor);
    defer msg.deinit();
    try msg.decode(ctx.file, ctx.bytes);
    std.mem.doNotOptimizeAway(&msg);
}

const DynamicSFixed64PackedDecodeReuseCtx = struct { message: *pbz.DynamicMessage, file: *const pbz.FileDescriptor, bytes: []const u8 };
fn dynamicSFixed64PackedDecodeReuse(ctx: DynamicSFixed64PackedDecodeReuseCtx) !void {
    try ctx.message.decode(ctx.file, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

const DynamicFloatPackedEncodeCtx = struct { message: *const pbz.DynamicMessage, file: *const pbz.FileDescriptor };
fn dynamicFloatPackedEncode(ctx: DynamicFloatPackedEncodeCtx) !void {
    const bytes = try ctx.message.encoded(ctx.file);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.message.allocator.free(bytes);
}

const DynamicFloatPackedDecodeCtx = struct { allocator: std.mem.Allocator, descriptor: *const pbz.MessageDescriptor, file: *const pbz.FileDescriptor, bytes: []const u8 };
fn dynamicFloatPackedDecode(ctx: DynamicFloatPackedDecodeCtx) !void {
    var msg = pbz.DynamicMessage.init(ctx.allocator, ctx.descriptor);
    defer msg.deinit();
    try msg.decode(ctx.file, ctx.bytes);
    std.mem.doNotOptimizeAway(&msg);
}

const DynamicFloatPackedDecodeReuseCtx = struct { message: *pbz.DynamicMessage, file: *const pbz.FileDescriptor, bytes: []const u8 };
fn dynamicFloatPackedDecodeReuse(ctx: DynamicFloatPackedDecodeReuseCtx) !void {
    try ctx.message.decode(ctx.file, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

const DynamicDoublePackedEncodeCtx = struct { message: *const pbz.DynamicMessage, file: *const pbz.FileDescriptor };
fn dynamicDoublePackedEncode(ctx: DynamicDoublePackedEncodeCtx) !void {
    const bytes = try ctx.message.encoded(ctx.file);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.message.allocator.free(bytes);
}

const DynamicDoublePackedDecodeCtx = struct { allocator: std.mem.Allocator, descriptor: *const pbz.MessageDescriptor, file: *const pbz.FileDescriptor, bytes: []const u8 };
fn dynamicDoublePackedDecode(ctx: DynamicDoublePackedDecodeCtx) !void {
    var msg = pbz.DynamicMessage.init(ctx.allocator, ctx.descriptor);
    defer msg.deinit();
    try msg.decode(ctx.file, ctx.bytes);
    std.mem.doNotOptimizeAway(&msg);
}

const DynamicDoublePackedDecodeReuseCtx = struct { message: *pbz.DynamicMessage, file: *const pbz.FileDescriptor, bytes: []const u8 };
fn dynamicDoublePackedDecodeReuse(ctx: DynamicDoublePackedDecodeReuseCtx) !void {
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

const DynamicUInt32PackedEncodeCtx = struct { message: *const pbz.DynamicMessage, file: *const pbz.FileDescriptor };
fn dynamicUInt32PackedEncode(ctx: DynamicUInt32PackedEncodeCtx) !void {
    const bytes = try ctx.message.encoded(ctx.file);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.message.allocator.free(bytes);
}

const DynamicUInt32PackedDecodeCtx = struct { allocator: std.mem.Allocator, descriptor: *const pbz.MessageDescriptor, file: *const pbz.FileDescriptor, bytes: []const u8 };
fn dynamicUInt32PackedDecode(ctx: DynamicUInt32PackedDecodeCtx) !void {
    var msg = pbz.DynamicMessage.init(ctx.allocator, ctx.descriptor);
    defer msg.deinit();
    try msg.decode(ctx.file, ctx.bytes);
    std.mem.doNotOptimizeAway(&msg);
}

const DynamicInt64PackedEncodeCtx = struct { message: *const pbz.DynamicMessage, file: *const pbz.FileDescriptor };
fn dynamicInt64PackedEncode(ctx: DynamicInt64PackedEncodeCtx) !void {
    const bytes = try ctx.message.encoded(ctx.file);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.message.allocator.free(bytes);
}

const DynamicInt64PackedDecodeCtx = struct { allocator: std.mem.Allocator, descriptor: *const pbz.MessageDescriptor, file: *const pbz.FileDescriptor, bytes: []const u8 };
fn dynamicInt64PackedDecode(ctx: DynamicInt64PackedDecodeCtx) !void {
    var msg = pbz.DynamicMessage.init(ctx.allocator, ctx.descriptor);
    defer msg.deinit();
    try msg.decode(ctx.file, ctx.bytes);
    std.mem.doNotOptimizeAway(&msg);
}

const DynamicSInt32PackedEncodeCtx = struct { message: *const pbz.DynamicMessage, file: *const pbz.FileDescriptor };
fn dynamicSInt32PackedEncode(ctx: DynamicSInt32PackedEncodeCtx) !void {
    const bytes = try ctx.message.encoded(ctx.file);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.message.allocator.free(bytes);
}

const DynamicSInt32PackedDecodeCtx = struct { allocator: std.mem.Allocator, descriptor: *const pbz.MessageDescriptor, file: *const pbz.FileDescriptor, bytes: []const u8 };
fn dynamicSInt32PackedDecode(ctx: DynamicSInt32PackedDecodeCtx) !void {
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

const DynamicLargeMapEncodeCtx = struct { message: *const pbz.DynamicMessage, file: *const pbz.FileDescriptor };
fn dynamicLargeMapEncode(ctx: DynamicLargeMapEncodeCtx) !void {
    const bytes = try ctx.message.encoded(ctx.file);
    std.mem.doNotOptimizeAway(bytes.ptr);
    ctx.message.allocator.free(bytes);
}

const DynamicLargeMapDecodeCtx = struct { allocator: std.mem.Allocator, descriptor: *const pbz.MessageDescriptor, file: *const pbz.FileDescriptor, bytes: []const u8 };
fn dynamicLargeMapDecode(ctx: DynamicLargeMapDecodeCtx) !void {
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

const GeneratedPersonFastEncodeIntoCtx = struct { buffer: []u8, person: *const person_pb.demo.Person };
fn generatedPersonTrustedUtf8EncodeIntoReuse(ctx: GeneratedPersonFastEncodeIntoCtx) !void {
    const bytes = try ctx.person.encodeIntoAssumeCapacityTrustedUtf8(ctx.buffer);
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

const GeneratedDecodeReuseCtx = struct { allocator: std.mem.Allocator, bytes: []const u8, message: *person_pb.demo.Person };
fn generatedDecodeReuse(ctx: GeneratedDecodeReuseCtx) !void {
    try ctx.message.decodeReuse(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(ctx.message);
}

const GeneratedUnknownDecodeCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };
fn generatedUnknownDecode(ctx: GeneratedUnknownDecodeCtx) !void {
    var decoded = try person_pb.demo.Person.decode(ctx.allocator, ctx.bytes);
    std.mem.doNotOptimizeAway(&decoded);
    if (decoded.unknownFieldCount() != UnknownFieldStressCount) return error.InvalidWireType;
    decoded.deinit(ctx.allocator);
}

const GeneratedUnknownQueryCtx = struct { message: *const person_pb.demo.Person, number: pbz.FieldNumber };
fn generatedUnknownCountByNumber(ctx: GeneratedUnknownQueryCtx) !void {
    const count = try ctx.message.unknownFieldCountByNumber(ctx.number);
    std.mem.doNotOptimizeAway(count);
}

const GeneratedUnknownNumberQueryCtx = struct { numbers: []const pbz.FieldNumber, number: pbz.FieldNumber };
fn generatedUnknownNumberCountByNumber(ctx: GeneratedUnknownNumberQueryCtx) !void {
    const count = pbz.wire.rawFieldNumberCount(ctx.numbers, ctx.number);
    std.mem.doNotOptimizeAway(count);
}

const GeneratedUnknownRunQueryCtx = struct { runs: []const pbz.wire.RawFieldNumberRun, number: pbz.FieldNumber };
fn generatedUnknownNumberRunCountByNumber(ctx: GeneratedUnknownRunQueryCtx) !void {
    const count = pbz.wire.rawFieldNumberRunCount(ctx.runs, ctx.number);
    std.mem.doNotOptimizeAway(count);
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

const DynamicUnknownDecodeCtx = struct { allocator: std.mem.Allocator, descriptor: *const pbz.MessageDescriptor, file: *const pbz.FileDescriptor, bytes: []const u8 };
fn dynamicUnknownDecode(ctx: DynamicUnknownDecodeCtx) !void {
    var msg = pbz.DynamicMessage.init(ctx.allocator, ctx.descriptor);
    defer msg.deinit();
    try msg.decode(ctx.file, ctx.bytes);
    std.mem.doNotOptimizeAway(&msg);
    if (msg.unknownCount() != UnknownFieldStressCount) return error.InvalidWireType;
}

const DynamicUnknownQueryCtx = struct { message: *const pbz.DynamicMessage, number: pbz.FieldNumber };
fn dynamicUnknownCountByNumber(ctx: DynamicUnknownQueryCtx) !void {
    const count = ctx.message.unknownFieldCountByNumber(ctx.number);
    std.mem.doNotOptimizeAway(count);
}

const DynamicUnknownNumberQueryCtx = struct { numbers: []const pbz.FieldNumber, number: pbz.FieldNumber };
fn dynamicUnknownNumberCountByNumber(ctx: DynamicUnknownNumberQueryCtx) !void {
    const count = pbz.wire.rawFieldNumberCount(ctx.numbers, ctx.number);
    std.mem.doNotOptimizeAway(count);
}

const DynamicUnknownRunQueryCtx = struct { runs: []const pbz.wire.RawFieldNumberRun, number: pbz.FieldNumber };
fn dynamicUnknownNumberRunCountByNumber(ctx: DynamicUnknownRunQueryCtx) !void {
    const count = pbz.wire.rawFieldNumberRunCount(ctx.runs, ctx.number);
    std.mem.doNotOptimizeAway(count);
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

const AnyWktJsonStringifyCtx = struct { allocator: std.mem.Allocator, any: *const pbz.Any };
fn anyWktJsonStringify(ctx: AnyWktJsonStringifyCtx) !void {
    const json = try ctx.any.jsonStringifyAlloc(ctx.allocator);
    std.mem.doNotOptimizeAway(json.ptr);
    ctx.allocator.free(json);
}

const AnyWktJsonParseCtx = struct { allocator: std.mem.Allocator, json: []const u8 };
fn anyWktJsonParse(ctx: AnyWktJsonParseCtx) !void {
    var any = try pbz.Any.jsonParse(ctx.allocator, ctx.json);
    std.mem.doNotOptimizeAway(&any);
    any.deinit(ctx.allocator);
}

const DurationJsonStringifyCtx = struct { allocator: std.mem.Allocator, duration: pbz.Duration };
fn durationJsonStringify(ctx: DurationJsonStringifyCtx) !void {
    const json = try ctx.duration.jsonStringifyAlloc(ctx.allocator);
    std.mem.doNotOptimizeAway(json.ptr);
    ctx.allocator.free(json);
}

const DurationJsonParseCtx = struct { json: []const u8 };
fn durationJsonParse(ctx: DurationJsonParseCtx) !void {
    const duration = try pbz.Duration.jsonParse(ctx.json);
    std.mem.doNotOptimizeAway(duration);
}

const FieldMaskJsonStringifyCtx = struct { allocator: std.mem.Allocator, mask: *const pbz.FieldMask };
fn fieldMaskJsonStringify(ctx: FieldMaskJsonStringifyCtx) !void {
    const json = try ctx.mask.jsonStringifyAlloc(ctx.allocator);
    std.mem.doNotOptimizeAway(json.ptr);
    ctx.allocator.free(json);
}

const FieldMaskJsonParseCtx = struct { allocator: std.mem.Allocator, json: []const u8 };
fn fieldMaskJsonParse(ctx: FieldMaskJsonParseCtx) !void {
    const paths = try pbz.FieldMask.jsonParse(ctx.allocator, ctx.json);
    std.mem.doNotOptimizeAway(paths.ptr);
    for (paths) |path| ctx.allocator.free(path);
    ctx.allocator.free(paths);
}

const TimestampJsonStringifyCtx = struct { allocator: std.mem.Allocator, timestamp: pbz.Timestamp };
fn timestampJsonStringify(ctx: TimestampJsonStringifyCtx) !void {
    const json = try ctx.timestamp.jsonStringifyAlloc(ctx.allocator);
    std.mem.doNotOptimizeAway(json.ptr);
    ctx.allocator.free(json);
}

const TimestampJsonParseCtx = struct { json: []const u8 };
fn timestampJsonParse(ctx: TimestampJsonParseCtx) !void {
    const timestamp = try pbz.Timestamp.jsonParse(ctx.json);
    std.mem.doNotOptimizeAway(timestamp);
}

const EmptyJsonStringifyCtx = struct { allocator: std.mem.Allocator };
fn emptyJsonStringify(ctx: EmptyJsonStringifyCtx) !void {
    var out: std.Io.Writer.Allocating = .init(ctx.allocator);
    defer out.deinit();
    try pbz.Empty.jsonStringify(&out.writer);
    std.mem.doNotOptimizeAway(out.written().ptr);
}

const EmptyJsonParseCtx = struct { allocator: std.mem.Allocator, json: []const u8 };
fn emptyJsonParse(ctx: EmptyJsonParseCtx) !void {
    const value = try pbz.Empty.jsonParse(ctx.allocator, ctx.json);
    std.mem.doNotOptimizeAway(value);
}

fn WktJsonStringifyCtx(comptime Value: type) type {
    return struct { allocator: std.mem.Allocator, value: Value };
}

fn wktJsonStringify(ctx: anytype) !void {
    const json = try ctx.value.jsonStringifyAlloc(ctx.allocator);
    std.mem.doNotOptimizeAway(json.ptr);
    ctx.allocator.free(json);
}

fn WktJsonParseCtx(comptime Value: type) type {
    return struct {
        allocator: std.mem.Allocator,
        json: []const u8,
        const Wkt = Value;
    };
}

fn wktJsonParse(ctx: anytype) !void {
    var value = try @TypeOf(ctx).Wkt.jsonParse(ctx.allocator, ctx.json);
    std.mem.doNotOptimizeAway(&value);
    value.deinit(ctx.allocator);
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
        \\message LargeBytes {
        \\  bytes payload = 1;
        \\  repeated bytes chunks = 2;
        \\}
        \\message PresenceMix {
        \\  message Child {
        \\    int32 id = 1;
        \\    string label = 2;
        \\  }
        \\  optional int32 count = 1;
        \\  optional string note = 2;
        \\  optional bytes raw = 3;
        \\  Child child = 4;
        \\  oneof pick {
        \\    string name = 5;
        \\    bytes token = 6;
        \\    Child nested = 7;
        \\    int64 code = 8;
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
        \\message SFixedPacked {
        \\  repeated sfixed32 values = 1;
        \\}
        \\message SFixed64Packed {
        \\  repeated sfixed64 values = 1;
        \\}
        \\message FloatPacked {
        \\  repeated float values = 1;
        \\}
        \\message DoublePacked {
        \\  repeated double values = 1;
        \\}
        \\message UInt64Packed {
        \\  repeated uint64 values = 1;
        \\}
        \\message UInt32Packed {
        \\  repeated uint32 values = 1;
        \\}
        \\message Int64Packed {
        \\  repeated int64 values = 1;
        \\}
        \\message SInt32Packed {
        \\  repeated sint32 values = 1;
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
        \\message LargeMap {
        \\  map<string, int32> counts = 1;
        \\}
    );
    defer file.deinit();
    const desc = file.findMessage("Person").?;
    const packed_desc = file.findMessage("Packed").?;
    const fixed_packed_desc = file.findMessage("FixedPacked").?;
    const fixed64_packed_desc = file.findMessage("Fixed64Packed").?;
    const sfixed_packed_desc = file.findMessage("SFixedPacked").?;
    const sfixed64_packed_desc = file.findMessage("SFixed64Packed").?;
    const float_packed_desc = file.findMessage("FloatPacked").?;
    const double_packed_desc = file.findMessage("DoublePacked").?;
    const uint64_packed_desc = file.findMessage("UInt64Packed").?;
    const uint32_packed_desc = file.findMessage("UInt32Packed").?;
    const int64_packed_desc = file.findMessage("Int64Packed").?;
    const sint32_packed_desc = file.findMessage("SInt32Packed").?;
    const sint64_packed_desc = file.findMessage("SInt64Packed").?;
    const bool_packed_desc = file.findMessage("BoolPacked").?;
    const enum_packed_desc = file.findMessage("EnumPacked").?;
    const large_map_desc = file.findMessage("LargeMap").?;

    var generated_person = try makeGeneratedPerson(allocator);
    defer generated_person.deinit(allocator);
    var dynamic_person = try makeDynamicPerson(allocator, desc);
    defer dynamic_person.deinit();
    var generated_scalar_mix = try makeGeneratedScalarMix(allocator);
    defer generated_scalar_mix.deinit(allocator);
    var generated_text_bytes = try makeGeneratedTextBytes(allocator);
    defer generated_text_bytes.deinit(allocator);
    var generated_large_bytes = try makeGeneratedLargeBytes(allocator);
    defer generated_large_bytes.deinit(allocator);
    var generated_presence_mix = try makeGeneratedPresenceMix(allocator);
    defer generated_presence_mix.deinit(allocator);
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
    var generated_sfixed_packed = try makeGeneratedSFixedPacked(allocator);
    defer generated_sfixed_packed.deinit(allocator);
    var dynamic_sfixed_packed = try makeDynamicSFixedPacked(allocator, sfixed_packed_desc);
    defer dynamic_sfixed_packed.deinit();
    var dynamic_sfixed_packed_decode_reuse = pbz.DynamicMessage.init(allocator, sfixed_packed_desc);
    defer dynamic_sfixed_packed_decode_reuse.deinit();
    var generated_sfixed64_packed = try makeGeneratedSFixed64Packed(allocator);
    defer generated_sfixed64_packed.deinit(allocator);
    var dynamic_sfixed64_packed = try makeDynamicSFixed64Packed(allocator, sfixed64_packed_desc);
    defer dynamic_sfixed64_packed.deinit();
    var dynamic_sfixed64_packed_decode_reuse = pbz.DynamicMessage.init(allocator, sfixed64_packed_desc);
    defer dynamic_sfixed64_packed_decode_reuse.deinit();
    var generated_float_packed = try makeGeneratedFloatPacked(allocator);
    defer generated_float_packed.deinit(allocator);
    var dynamic_float_packed = try makeDynamicFloatPacked(allocator, float_packed_desc);
    defer dynamic_float_packed.deinit();
    var dynamic_float_packed_decode_reuse = pbz.DynamicMessage.init(allocator, float_packed_desc);
    defer dynamic_float_packed_decode_reuse.deinit();
    var generated_double_packed = try makeGeneratedDoublePacked(allocator);
    defer generated_double_packed.deinit(allocator);
    var dynamic_double_packed = try makeDynamicDoublePacked(allocator, double_packed_desc);
    defer dynamic_double_packed.deinit();
    var dynamic_double_packed_decode_reuse = pbz.DynamicMessage.init(allocator, double_packed_desc);
    defer dynamic_double_packed_decode_reuse.deinit();
    var generated_uint64_packed = try makeGeneratedUInt64Packed(allocator);
    defer generated_uint64_packed.deinit(allocator);
    var dynamic_uint64_packed = try makeDynamicUInt64Packed(allocator, uint64_packed_desc);
    defer dynamic_uint64_packed.deinit();
    var generated_uint32_packed = try makeGeneratedUInt32Packed(allocator);
    defer generated_uint32_packed.deinit(allocator);
    var dynamic_uint32_packed = try makeDynamicUInt32Packed(allocator, uint32_packed_desc);
    defer dynamic_uint32_packed.deinit();
    var generated_int64_packed = try makeGeneratedInt64Packed(allocator);
    defer generated_int64_packed.deinit(allocator);
    var dynamic_int64_packed = try makeDynamicInt64Packed(allocator, int64_packed_desc);
    defer dynamic_int64_packed.deinit();
    var generated_sint32_packed = try makeGeneratedSInt32Packed(allocator);
    defer generated_sint32_packed.deinit(allocator);
    var dynamic_sint32_packed = try makeDynamicSInt32Packed(allocator, sint32_packed_desc);
    defer dynamic_sint32_packed.deinit();
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
    var generated_large_map = try makeGeneratedLargeMap(allocator);
    defer generated_large_map.deinit(allocator);
    var generated_shuffled_large_map = try makeGeneratedShuffledLargeMap(allocator);
    defer generated_shuffled_large_map.deinit(allocator);
    var dynamic_large_map = try makeDynamicLargeMap(allocator, large_map_desc);
    defer dynamic_large_map.deinit();

    const generated_bytes = try generated_person.encode(allocator);
    defer allocator.free(generated_bytes);
    var reusable_writer = pbz.Writer.init(allocator);
    defer reusable_writer.deinit();
    try reusable_writer.bytes.ensureTotalCapacity(allocator, generated_bytes.len);
    const generated_buffer = try allocator.alloc(u8, generated_bytes.len);
    defer allocator.free(generated_buffer);
    var generated_person_decode_reuse = try generated_person.cloneOwned(allocator);
    defer generated_person_decode_reuse.deinit(allocator);
    const dynamic_bytes = try dynamic_person.encoded(&file);
    defer allocator.free(dynamic_bytes);
    const generated_unknown_bytes = try makeUnknownFieldPayload(allocator, generated_bytes, UnknownFieldStressCount);
    defer allocator.free(generated_unknown_bytes);
    var generated_unknown_person = try person_pb.demo.Person.decode(allocator, generated_unknown_bytes);
    defer generated_unknown_person.deinit(allocator);
    const generated_unknown_numbers = try generated_unknown_person.unknownFieldNumbersAlloc(allocator);
    defer allocator.free(generated_unknown_numbers);
    const generated_unknown_number_runs = try generated_unknown_person.unknownFieldNumberRunsAlloc(allocator);
    defer allocator.free(generated_unknown_number_runs);
    var dynamic_unknown_person = pbz.DynamicMessage.init(allocator, desc);
    defer dynamic_unknown_person.deinit();
    try dynamic_unknown_person.decode(&file, generated_unknown_bytes);
    const dynamic_unknown_numbers = try dynamic_unknown_person.unknownFieldNumbersAlloc(allocator);
    defer allocator.free(dynamic_unknown_numbers);
    const dynamic_unknown_number_runs = try dynamic_unknown_person.unknownFieldNumberRunsAlloc(allocator);
    defer allocator.free(dynamic_unknown_number_runs);
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
    var generated_text_bytes_decode_reuse = person_pb.demo.TextBytes.init();
    defer generated_text_bytes_decode_reuse.deinit(allocator);
    const generated_large_bytes_bytes = try generated_large_bytes.encode(allocator);
    defer allocator.free(generated_large_bytes_bytes);
    var reusable_large_bytes_writer = pbz.Writer.init(allocator);
    defer reusable_large_bytes_writer.deinit();
    try reusable_large_bytes_writer.bytes.ensureTotalCapacity(allocator, generated_large_bytes_bytes.len);
    const generated_large_bytes_buffer = try allocator.alloc(u8, generated_large_bytes_bytes.len);
    defer allocator.free(generated_large_bytes_buffer);
    var generated_large_bytes_decode_reuse = person_pb.demo.LargeBytes.init();
    defer generated_large_bytes_decode_reuse.deinit(allocator);
    const generated_presence_mix_bytes = try generated_presence_mix.encode(allocator);
    defer allocator.free(generated_presence_mix_bytes);
    var reusable_presence_mix_writer = pbz.Writer.init(allocator);
    defer reusable_presence_mix_writer.deinit();
    try reusable_presence_mix_writer.bytes.ensureTotalCapacity(allocator, generated_presence_mix_bytes.len);
    const generated_presence_mix_buffer = try allocator.alloc(u8, generated_presence_mix_bytes.len);
    defer allocator.free(generated_presence_mix_buffer);
    var generated_presence_mix_decode_reuse = try generated_presence_mix.cloneOwned(allocator);
    defer generated_presence_mix_decode_reuse.deinit(allocator);
    const generated_complex_bytes = try generated_complex.encode(allocator);
    defer allocator.free(generated_complex_bytes);
    var reusable_complex_writer = pbz.Writer.init(allocator);
    defer reusable_complex_writer.deinit();
    try reusable_complex_writer.bytes.ensureTotalCapacity(allocator, generated_complex_bytes.len);
    const generated_complex_buffer = try allocator.alloc(u8, generated_complex_bytes.len);
    defer allocator.free(generated_complex_buffer);
    var generated_complex_decode_reuse = try generated_complex.cloneOwned(allocator);
    defer generated_complex_decode_reuse.deinit(allocator);
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
    var generated_packed_decode_reuse = try generated_packed.cloneOwned(allocator);
    defer generated_packed_decode_reuse.deinit(allocator);
    const dynamic_packed_bytes = try dynamic_packed.encoded(&file);
    defer allocator.free(dynamic_packed_bytes);
    const generated_fixed_packed_bytes = try generated_fixed_packed.encode(allocator);
    defer allocator.free(generated_fixed_packed_bytes);
    const generated_fixed_packed_buffer = try allocator.alloc(u8, generated_fixed_packed_bytes.len);
    defer allocator.free(generated_fixed_packed_buffer);
    var generated_fixed_packed_decode_reuse = try generated_fixed_packed.cloneOwned(allocator);
    defer generated_fixed_packed_decode_reuse.deinit(allocator);
    const dynamic_fixed_packed_bytes = try dynamic_fixed_packed.encoded(&file);
    defer allocator.free(dynamic_fixed_packed_bytes);
    const generated_fixed64_packed_bytes = try generated_fixed64_packed.encode(allocator);
    defer allocator.free(generated_fixed64_packed_bytes);
    const generated_fixed64_packed_buffer = try allocator.alloc(u8, generated_fixed64_packed_bytes.len);
    defer allocator.free(generated_fixed64_packed_buffer);
    var generated_fixed64_packed_decode_reuse = try generated_fixed64_packed.cloneOwned(allocator);
    defer generated_fixed64_packed_decode_reuse.deinit(allocator);
    const dynamic_fixed64_packed_bytes = try dynamic_fixed64_packed.encoded(&file);
    defer allocator.free(dynamic_fixed64_packed_bytes);
    const generated_sfixed_packed_bytes = try generated_sfixed_packed.encode(allocator);
    defer allocator.free(generated_sfixed_packed_bytes);
    const generated_sfixed_packed_buffer = try allocator.alloc(u8, generated_sfixed_packed_bytes.len);
    defer allocator.free(generated_sfixed_packed_buffer);
    var generated_sfixed_packed_decode_reuse = try generated_sfixed_packed.cloneOwned(allocator);
    defer generated_sfixed_packed_decode_reuse.deinit(allocator);
    const dynamic_sfixed_packed_bytes = try dynamic_sfixed_packed.encoded(&file);
    defer allocator.free(dynamic_sfixed_packed_bytes);
    const generated_sfixed64_packed_bytes = try generated_sfixed64_packed.encode(allocator);
    defer allocator.free(generated_sfixed64_packed_bytes);
    const generated_sfixed64_packed_buffer = try allocator.alloc(u8, generated_sfixed64_packed_bytes.len);
    defer allocator.free(generated_sfixed64_packed_buffer);
    var generated_sfixed64_packed_decode_reuse = try generated_sfixed64_packed.cloneOwned(allocator);
    defer generated_sfixed64_packed_decode_reuse.deinit(allocator);
    const dynamic_sfixed64_packed_bytes = try dynamic_sfixed64_packed.encoded(&file);
    defer allocator.free(dynamic_sfixed64_packed_bytes);
    const generated_float_packed_bytes = try generated_float_packed.encode(allocator);
    defer allocator.free(generated_float_packed_bytes);
    const generated_float_packed_buffer = try allocator.alloc(u8, generated_float_packed_bytes.len);
    defer allocator.free(generated_float_packed_buffer);
    var generated_float_packed_decode_reuse = try generated_float_packed.cloneOwned(allocator);
    defer generated_float_packed_decode_reuse.deinit(allocator);
    const dynamic_float_packed_bytes = try dynamic_float_packed.encoded(&file);
    defer allocator.free(dynamic_float_packed_bytes);
    const generated_double_packed_bytes = try generated_double_packed.encode(allocator);
    defer allocator.free(generated_double_packed_bytes);
    const generated_double_packed_buffer = try allocator.alloc(u8, generated_double_packed_bytes.len);
    defer allocator.free(generated_double_packed_buffer);
    var generated_double_packed_decode_reuse = try generated_double_packed.cloneOwned(allocator);
    defer generated_double_packed_decode_reuse.deinit(allocator);
    const dynamic_double_packed_bytes = try dynamic_double_packed.encoded(&file);
    defer allocator.free(dynamic_double_packed_bytes);
    const generated_uint64_packed_bytes = try generated_uint64_packed.encode(allocator);
    defer allocator.free(generated_uint64_packed_bytes);
    const generated_uint64_packed_buffer = try allocator.alloc(u8, generated_uint64_packed_bytes.len);
    defer allocator.free(generated_uint64_packed_buffer);
    var generated_uint64_packed_decode_reuse = try generated_uint64_packed.cloneOwned(allocator);
    defer generated_uint64_packed_decode_reuse.deinit(allocator);
    const dynamic_uint64_packed_bytes = try dynamic_uint64_packed.encoded(&file);
    defer allocator.free(dynamic_uint64_packed_bytes);
    const generated_uint32_packed_bytes = try generated_uint32_packed.encode(allocator);
    defer allocator.free(generated_uint32_packed_bytes);
    const generated_uint32_packed_buffer = try allocator.alloc(u8, generated_uint32_packed_bytes.len);
    defer allocator.free(generated_uint32_packed_buffer);
    var generated_uint32_packed_decode_reuse = try generated_uint32_packed.cloneOwned(allocator);
    defer generated_uint32_packed_decode_reuse.deinit(allocator);
    const dynamic_uint32_packed_bytes = try dynamic_uint32_packed.encoded(&file);
    defer allocator.free(dynamic_uint32_packed_bytes);
    const generated_int64_packed_bytes = try generated_int64_packed.encode(allocator);
    defer allocator.free(generated_int64_packed_bytes);
    const generated_int64_packed_buffer = try allocator.alloc(u8, generated_int64_packed_bytes.len);
    defer allocator.free(generated_int64_packed_buffer);
    var generated_int64_packed_decode_reuse = try generated_int64_packed.cloneOwned(allocator);
    defer generated_int64_packed_decode_reuse.deinit(allocator);
    const dynamic_int64_packed_bytes = try dynamic_int64_packed.encoded(&file);
    defer allocator.free(dynamic_int64_packed_bytes);
    const generated_sint32_packed_bytes = try generated_sint32_packed.encode(allocator);
    defer allocator.free(generated_sint32_packed_bytes);
    const generated_sint32_packed_buffer = try allocator.alloc(u8, generated_sint32_packed_bytes.len);
    defer allocator.free(generated_sint32_packed_buffer);
    var generated_sint32_packed_decode_reuse = try generated_sint32_packed.cloneOwned(allocator);
    defer generated_sint32_packed_decode_reuse.deinit(allocator);
    const dynamic_sint32_packed_bytes = try dynamic_sint32_packed.encoded(&file);
    defer allocator.free(dynamic_sint32_packed_bytes);
    const generated_sint64_packed_bytes = try generated_sint64_packed.encode(allocator);
    defer allocator.free(generated_sint64_packed_bytes);
    const generated_sint64_packed_buffer = try allocator.alloc(u8, generated_sint64_packed_bytes.len);
    defer allocator.free(generated_sint64_packed_buffer);
    var generated_sint64_packed_decode_reuse = try generated_sint64_packed.cloneOwned(allocator);
    defer generated_sint64_packed_decode_reuse.deinit(allocator);
    const dynamic_sint64_packed_bytes = try dynamic_sint64_packed.encoded(&file);
    defer allocator.free(dynamic_sint64_packed_bytes);
    const generated_bool_packed_bytes = try generated_bool_packed.encode(allocator);
    defer allocator.free(generated_bool_packed_bytes);
    const generated_bool_packed_buffer = try allocator.alloc(u8, generated_bool_packed_bytes.len);
    defer allocator.free(generated_bool_packed_buffer);
    var generated_bool_packed_decode_reuse = try generated_bool_packed.cloneOwned(allocator);
    defer generated_bool_packed_decode_reuse.deinit(allocator);
    const dynamic_bool_packed_bytes = try dynamic_bool_packed.encoded(&file);
    defer allocator.free(dynamic_bool_packed_bytes);
    const generated_enum_packed_bytes = try generated_enum_packed.encode(allocator);
    defer allocator.free(generated_enum_packed_bytes);
    const generated_enum_packed_buffer = try allocator.alloc(u8, generated_enum_packed_bytes.len);
    defer allocator.free(generated_enum_packed_buffer);
    var generated_enum_packed_decode_reuse = try generated_enum_packed.cloneOwned(allocator);
    defer generated_enum_packed_decode_reuse.deinit(allocator);
    const dynamic_enum_packed_bytes = try dynamic_enum_packed.encoded(&file);
    defer allocator.free(dynamic_enum_packed_bytes);
    const generated_large_map_bytes = try generated_large_map.encode(allocator);
    defer allocator.free(generated_large_map_bytes);
    var reusable_large_map_writer = pbz.Writer.init(allocator);
    defer reusable_large_map_writer.deinit();
    try reusable_large_map_writer.bytes.ensureTotalCapacity(allocator, generated_large_map_bytes.len);
    const generated_large_map_buffer = try allocator.alloc(u8, generated_large_map_bytes.len);
    defer allocator.free(generated_large_map_buffer);
    const generated_shuffled_large_map_bytes = try generated_shuffled_large_map.encode(allocator);
    defer allocator.free(generated_shuffled_large_map_bytes);
    const generated_shuffled_large_map_buffer = try allocator.alloc(u8, generated_shuffled_large_map_bytes.len);
    defer allocator.free(generated_shuffled_large_map_buffer);
    var generated_large_map_decode_reuse = person_pb.demo.LargeMap.init();
    defer generated_large_map_decode_reuse.deinit(allocator);
    const dynamic_large_map_bytes = try dynamic_large_map.encoded(&file);
    defer allocator.free(dynamic_large_map_bytes);
    const generated_json = try generated_person.jsonStringifyAlloc(allocator);
    defer allocator.free(generated_json);
    const dynamic_json = try pbz.stringifyJsonAlloc(allocator, &file, &dynamic_person, .{});
    defer allocator.free(dynamic_json);
    var any_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.Duration", pbz.Duration{ .seconds = 1, .nanos = 500_000_000 });
    defer any_wkt.deinit(allocator);
    const any_wkt_json = try any_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_wkt_json, AnyWktJson));
    const duration_value = pbz.Duration{ .seconds = 1, .nanos = 500_000_000 };
    const duration_json = try duration_value.jsonStringifyAlloc(allocator);
    defer allocator.free(duration_json);
    std.debug.assert(std.mem.eql(u8, duration_json, DurationJson));
    const field_mask_paths = [_][]const u8{ "foo_bar", "nested.value" };
    const field_mask_value = pbz.FieldMask{ .paths = &field_mask_paths };
    const field_mask_json = try field_mask_value.jsonStringifyAlloc(allocator);
    defer allocator.free(field_mask_json);
    std.debug.assert(std.mem.eql(u8, field_mask_json, FieldMaskJson));
    const timestamp_value = pbz.Timestamp{ .seconds = 1_577_836_800, .nanos = 123_000_000 };
    const timestamp_json = try timestamp_value.jsonStringifyAlloc(allocator);
    defer allocator.free(timestamp_json);
    std.debug.assert(std.mem.eql(u8, timestamp_json, TimestampJson));
    var empty_json_out: std.Io.Writer.Allocating = .init(allocator);
    defer empty_json_out.deinit();
    try pbz.Empty.jsonStringify(&empty_json_out.writer);
    const empty_json = empty_json_out.written();
    std.debug.assert(std.mem.eql(u8, empty_json, EmptyJson));
    const struct_items_values = [_]pbz.Value{ .null_value, .{ .string_value = "zig" } };
    var struct_items = pbz.ListValue{ .values = &struct_items_values };
    const struct_meta_fields = [_]pbz.Struct.Field{.{ .key = "score", .value = .{ .number_value = 1.5 } }};
    var struct_meta = pbz.Struct{ .fields = &struct_meta_fields };
    const struct_fields = [_]pbz.Struct.Field{
        .{ .key = "enabled", .value = .{ .bool_value = true } },
        .{ .key = "items", .value = .{ .list_value = &struct_items } },
        .{ .key = "meta", .value = .{ .struct_value = &struct_meta } },
    };
    var struct_value = pbz.Struct{ .fields = &struct_fields };
    const struct_json = try struct_value.jsonStringifyAlloc(allocator);
    defer allocator.free(struct_json);
    std.debug.assert(std.mem.eql(u8, struct_json, StructJson));
    var any_struct_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.Struct", struct_value);
    defer any_struct_wkt.deinit(allocator);
    const any_struct_wkt_json = try any_struct_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_struct_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_struct_wkt_json, AnyStructWktJson));
    const value_value = pbz.Value{ .struct_value = &struct_value };
    const value_json = try value_value.jsonStringifyAlloc(allocator);
    defer allocator.free(value_json);
    std.debug.assert(std.mem.eql(u8, value_json, ValueJson));
    var any_value_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.Value", value_value);
    defer any_value_wkt.deinit(allocator);
    const any_value_wkt_json = try any_value_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_value_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_value_wkt_json, AnyValueWktJson));
    const list_nested_fields = [_]pbz.Struct.Field{.{ .key = "nested", .value = .{ .string_value = "value" } }};
    var list_nested = pbz.Struct{ .fields = &list_nested_fields };
    const list_values = [_]pbz.Value{
        .null_value,
        .{ .string_value = "zig" },
        .{ .number_value = 1.5 },
        .{ .bool_value = true },
        .{ .struct_value = &list_nested },
    };
    const list_value = pbz.ListValue{ .values = &list_values };
    const list_value_json = try list_value.jsonStringifyAlloc(allocator);
    defer allocator.free(list_value_json);
    std.debug.assert(std.mem.eql(u8, list_value_json, ListValueJson));
    const double_value = pbz.DoubleValue{ .value = 3.25 };
    const double_value_json = try double_value.jsonStringifyAlloc(allocator);
    defer allocator.free(double_value_json);
    std.debug.assert(std.mem.eql(u8, double_value_json, DoubleValueJson));
    const float_value = pbz.FloatValue{ .value = 1.5 };
    const float_value_json = try float_value.jsonStringifyAlloc(allocator);
    defer allocator.free(float_value_json);
    std.debug.assert(std.mem.eql(u8, float_value_json, FloatValueJson));
    const int64_value = pbz.Int64Value{ .value = 9007199254740993 };
    const int64_value_json = try int64_value.jsonStringifyAlloc(allocator);
    defer allocator.free(int64_value_json);
    std.debug.assert(std.mem.eql(u8, int64_value_json, Int64ValueJson));
    const uint64_value = pbz.UInt64Value{ .value = 9007199254740993 };
    const uint64_value_json = try uint64_value.jsonStringifyAlloc(allocator);
    defer allocator.free(uint64_value_json);
    std.debug.assert(std.mem.eql(u8, uint64_value_json, UInt64ValueJson));
    const int32_value = pbz.Int32Value{ .value = 12345 };
    const int32_value_json = try int32_value.jsonStringifyAlloc(allocator);
    defer allocator.free(int32_value_json);
    std.debug.assert(std.mem.eql(u8, int32_value_json, Int32ValueJson));
    const uint32_value = pbz.UInt32Value{ .value = 12345 };
    const uint32_value_json = try uint32_value.jsonStringifyAlloc(allocator);
    defer allocator.free(uint32_value_json);
    std.debug.assert(std.mem.eql(u8, uint32_value_json, UInt32ValueJson));
    const bool_value = pbz.BoolValue{ .value = true };
    const bool_value_json = try bool_value.jsonStringifyAlloc(allocator);
    defer allocator.free(bool_value_json);
    std.debug.assert(std.mem.eql(u8, bool_value_json, BoolValueJson));
    const string_value = pbz.StringValue{ .value = "hello" };
    const string_value_json = try string_value.jsonStringifyAlloc(allocator);
    defer allocator.free(string_value_json);
    std.debug.assert(std.mem.eql(u8, string_value_json, StringValueJson));
    var any_string_value_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.StringValue", string_value);
    defer any_string_value_wkt.deinit(allocator);
    const any_string_value_wkt_json = try any_string_value_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_string_value_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_string_value_wkt_json, AnyStringValueWktJson));
    var nested_any_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.Any", any_string_value_wkt);
    defer nested_any_wkt.deinit(allocator);
    const nested_any_wkt_json = try nested_any_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(nested_any_wkt_json);
    std.debug.assert(std.mem.eql(u8, nested_any_wkt_json, NestedAnyWktJson));
    const bytes_value = pbz.BytesValue{ .value = "hi" };
    const bytes_value_json = try bytes_value.jsonStringifyAlloc(allocator);
    defer allocator.free(bytes_value_json);
    std.debug.assert(std.mem.eql(u8, bytes_value_json, BytesValueJson));
    var any_bytes_value_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.BytesValue", bytes_value);
    defer any_bytes_value_wkt.deinit(allocator);
    const any_bytes_value_wkt_json = try any_bytes_value_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_bytes_value_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_bytes_value_wkt_json, AnyBytesValueWktJson));
    const generated_text = try generated_person.formatTextAlloc(allocator);
    defer allocator.free(generated_text);
    const dynamic_text = try pbz.formatTextAlloc(allocator, &file, &dynamic_person, .{});
    defer allocator.free(dynamic_text);

    std.debug.print("pbz benchmark baseline (Zig {s})\n", .{@import("builtin").zig_version_string});
    std.debug.print("payload sizes: person_generated={d} person_dynamic={d} packed_generated={d} packed_dynamic={d} fixed_packed_generated={d} fixed_packed_dynamic={d} fixed64_packed_generated={d} fixed64_packed_dynamic={d} sfixed_packed_generated={d} sfixed_packed_dynamic={d} sfixed64_packed_generated={d} sfixed64_packed_dynamic={d} float_packed_generated={d} float_packed_dynamic={d} double_packed_generated={d} double_packed_dynamic={d} uint64_packed_generated={d} uint64_packed_dynamic={d} uint32_packed_generated={d} uint32_packed_dynamic={d} int64_packed_generated={d} int64_packed_dynamic={d} sint32_packed_generated={d} sint32_packed_dynamic={d} sint64_packed_generated={d} sint64_packed_dynamic={d} bool_packed_generated={d} bool_packed_dynamic={d} enum_packed_generated={d} enum_packed_dynamic={d} large_map_generated={d} large_map_dynamic={d}\n", .{ generated_bytes.len, dynamic_bytes.len, generated_packed_bytes.len, dynamic_packed_bytes.len, generated_fixed_packed_bytes.len, dynamic_fixed_packed_bytes.len, generated_fixed64_packed_bytes.len, dynamic_fixed64_packed_bytes.len, generated_sfixed_packed_bytes.len, dynamic_sfixed_packed_bytes.len, generated_sfixed64_packed_bytes.len, dynamic_sfixed64_packed_bytes.len, generated_float_packed_bytes.len, dynamic_float_packed_bytes.len, generated_double_packed_bytes.len, dynamic_double_packed_bytes.len, generated_uint64_packed_bytes.len, dynamic_uint64_packed_bytes.len, generated_uint32_packed_bytes.len, dynamic_uint32_packed_bytes.len, generated_int64_packed_bytes.len, dynamic_int64_packed_bytes.len, generated_sint32_packed_bytes.len, dynamic_sint32_packed_bytes.len, generated_sint64_packed_bytes.len, dynamic_sint64_packed_bytes.len, generated_bool_packed_bytes.len, dynamic_bool_packed_bytes.len, generated_enum_packed_bytes.len, dynamic_enum_packed_bytes.len, generated_large_map_bytes.len, dynamic_large_map_bytes.len });
    // std.Io.Writer format calls are capped at 32 arguments; keep the payload
    // inventory split into thematic groups so adding future WKT rows does not
    // silently push this diagnostic over the compiler-enforced limit again.
    std.debug.print("payload sizes detail: scalar_mix={d} text_bytes={d} large_bytes={d} presence_mix={d} complex={d} complex_json={d} complex_text={d} unknown_fields={d} shuffled_large_map={d} json={d} timestamp_json={d} duration_json={d} field_mask_json={d} empty_json={d} struct_json={d} value_json={d} list_value_json={d}\n", .{ generated_scalar_mix_bytes.len, generated_text_bytes_bytes.len, generated_large_bytes_bytes.len, generated_presence_mix_bytes.len, generated_complex_bytes.len, generated_complex_json.len, generated_complex_text.len, generated_unknown_bytes.len, generated_shuffled_large_map_bytes.len, generated_json.len, timestamp_json.len, duration_json.len, field_mask_json.len, empty_json.len, struct_json.len, value_json.len, list_value_json.len });
    std.debug.print("payload sizes WKT wrappers: double_value_json={d} float_value_json={d} int64_value_json={d} uint64_value_json={d} int32_value_json={d} uint32_value_json={d} bool_value_json={d} string_value_json={d} bytes_value_json={d} any_wkt_json={d} any_struct_wkt_json={d} any_value_wkt_json={d} any_string_value_wkt_json={d} any_bytes_value_wkt_json={d} nested_any_wkt_json={d} text={d}\n", .{ double_value_json.len, float_value_json.len, int64_value_json.len, uint64_value_json.len, int32_value_json.len, uint32_value_json.len, bool_value_json.len, string_value_json.len, bytes_value_json.len, any_wkt_json.len, any_struct_wkt_json.len, any_value_wkt_json.len, any_string_value_wkt_json.len, any_bytes_value_wkt_json.len, nested_any_wkt_json.len, generated_text.len });

    const results = [_]BenchResult{
        try runTimed(io, "generated binary encode", iters.generated_binary, generated_bytes.len, GeneratedEncodeCtx{ .allocator = allocator, .person = &generated_person }, generatedEncode),
        try runTimed(io, "generated binary writeToAssumeCapacity reuse", iters.generated_binary, generated_bytes.len, GeneratedWriteToCtx{ .writer = &reusable_writer, .person = &generated_person }, generatedWriteToReuse),
        try runTimed(io, "generated binary encodeIntoAssumeCapacity buffer reuse", iters.generated_binary, generated_bytes.len, GeneratedEncodeIntoCtx{ .buffer = generated_buffer, .person = &generated_person }, generatedEncodeIntoReuse),
        try runTimed(io, "generated binary trusted UTF-8 encodeIntoAssumeCapacity buffer reuse", iters.generated_binary, generated_bytes.len, GeneratedPersonFastEncodeIntoCtx{ .buffer = generated_buffer, .person = &generated_person }, generatedPersonTrustedUtf8EncodeIntoReuse),
        try runTimed(io, "generated deterministic binary encode", iters.generated_binary, generated_bytes.len, GeneratedDeterministicEncodeCtx{ .allocator = allocator, .person = &generated_person }, generatedDeterministicEncode),
        try runTimed(io, "generated deterministic binary encodeIntoAssumeCapacity buffer reuse", iters.generated_binary, generated_bytes.len, GeneratedDeterministicEncodeIntoCtx{ .allocator = allocator, .buffer = generated_buffer, .person = &generated_person }, generatedDeterministicEncodeIntoReuse),
        try runTimed(io, "generated binary decode", iters.generated_binary, generated_bytes.len, GeneratedDecodeCtx{ .allocator = allocator, .bytes = generated_bytes }, generatedDecode),
        try runTimed(io, "generated binary decode reuse", iters.generated_binary, generated_bytes.len, GeneratedDecodeReuseCtx{ .allocator = allocator, .bytes = generated_bytes, .message = &generated_person_decode_reuse }, generatedDecodeReuse),
        try runTimed(io, "generated unknown fields decode", iters.large_map, generated_unknown_bytes.len, GeneratedUnknownDecodeCtx{ .allocator = allocator, .bytes = generated_unknown_bytes }, generatedUnknownDecode),
        try runTimed(io, "generated unknown fields count by number", iters.generated_binary, generated_unknown_bytes.len, GeneratedUnknownQueryCtx{ .message = &generated_unknown_person, .number = UnknownFieldStressFirstNumber }, generatedUnknownCountByNumber),
        try runTimed(io, "generated unknown field number sidecar count", iters.generated_binary, generated_unknown_bytes.len, GeneratedUnknownNumberQueryCtx{ .numbers = generated_unknown_numbers, .number = UnknownFieldStressFirstNumber }, generatedUnknownNumberCountByNumber),
        try runTimed(io, "generated unknown field number run sidecar count", iters.generated_binary, generated_unknown_bytes.len, GeneratedUnknownRunQueryCtx{ .runs = generated_unknown_number_runs, .number = UnknownFieldStressFirstNumber }, generatedUnknownNumberRunCountByNumber),
        try runTimed(io, "generated scalarmix encode", iters.generated_binary, generated_scalar_mix_bytes.len, GeneratedScalarMixEncodeCtx{ .allocator = allocator, .message = &generated_scalar_mix }, generatedScalarMixEncode),
        try runTimed(io, "generated scalarmix writeToAssumeCapacity reuse", iters.generated_binary, generated_scalar_mix_bytes.len, GeneratedScalarMixWriteToCtx{ .writer = &reusable_scalar_mix_writer, .message = &generated_scalar_mix }, generatedScalarMixWriteToReuse),
        try runTimed(io, "generated scalarmix encodeIntoAssumeCapacity buffer reuse", iters.generated_binary, generated_scalar_mix_bytes.len, GeneratedScalarMixEncodeIntoCtx{ .buffer = generated_scalar_mix_buffer, .message = &generated_scalar_mix }, generatedScalarMixEncodeIntoReuse),
        try runTimed(io, "generated scalarmix decode", iters.generated_binary, generated_scalar_mix_bytes.len, GeneratedScalarMixDecodeCtx{ .allocator = allocator, .bytes = generated_scalar_mix_bytes }, generatedScalarMixDecode),
        try runTimed(io, "generated scalarmix decode reuse", iters.generated_binary, generated_scalar_mix_bytes.len, GeneratedScalarMixDecodeReuseCtx{ .allocator = allocator, .bytes = generated_scalar_mix_bytes, .message = &generated_scalar_mix_decode_reuse }, generatedScalarMixDecodeReuse),
        try runTimed(io, "generated scalarmix fast known-schema decode reuse", iters.generated_binary, generated_scalar_mix_bytes.len, GeneratedScalarMixDecodeReuseCtx{ .allocator = allocator, .bytes = generated_scalar_mix_bytes, .message = &generated_scalar_mix_decode_reuse }, generatedScalarMixKnownDecodeReuse),
        try runTimed(io, "generated textbytes encode", iters.generated_binary, generated_text_bytes_bytes.len, GeneratedTextBytesEncodeCtx{ .allocator = allocator, .message = &generated_text_bytes }, generatedTextBytesEncode),
        try runTimed(io, "generated textbytes writeToAssumeCapacity reuse", iters.generated_binary, generated_text_bytes_bytes.len, GeneratedTextBytesWriteToCtx{ .writer = &reusable_text_bytes_writer, .message = &generated_text_bytes }, generatedTextBytesWriteToReuse),
        try runTimed(io, "generated textbytes trusted UTF-8 writeToAssumeCapacity reuse", iters.generated_binary, generated_text_bytes_bytes.len, GeneratedTextBytesWriteToCtx{ .writer = &reusable_text_bytes_writer, .message = &generated_text_bytes }, generatedTextBytesTrustedUtf8WriteToReuse),
        try runTimed(io, "generated textbytes encodeIntoAssumeCapacity buffer reuse", iters.generated_binary, generated_text_bytes_bytes.len, GeneratedTextBytesEncodeIntoCtx{ .buffer = generated_text_bytes_buffer, .message = &generated_text_bytes }, generatedTextBytesEncodeIntoReuse),
        try runTimed(io, "generated textbytes trusted UTF-8 encodeIntoAssumeCapacity buffer reuse", iters.generated_binary, generated_text_bytes_bytes.len, GeneratedTextBytesEncodeIntoCtx{ .buffer = generated_text_bytes_buffer, .message = &generated_text_bytes }, generatedTextBytesTrustedUtf8EncodeIntoReuse),
        try runTimed(io, "generated textbytes borrowed slices encode", iters.generated_binary, generated_text_bytes_bytes.len, GeneratedTextBytesBorrowedSlicesCtx{ .message = &generated_text_bytes }, generatedTextBytesBorrowedSlices),
        try runTimed(io, "generated textbytes decode", iters.generated_binary, generated_text_bytes_bytes.len, GeneratedTextBytesDecodeCtx{ .allocator = allocator, .bytes = generated_text_bytes_bytes }, generatedTextBytesDecode),
        try runTimed(io, "generated textbytes decode reuse", iters.generated_binary, generated_text_bytes_bytes.len, GeneratedTextBytesDecodeReuseCtx{ .allocator = allocator, .bytes = generated_text_bytes_bytes, .message = &generated_text_bytes_decode_reuse }, generatedTextBytesDecodeReuse),
        try runTimed(io, "generated largebytes encode", iters.generated_binary, generated_large_bytes_bytes.len, GeneratedLargeBytesEncodeCtx{ .allocator = allocator, .message = &generated_large_bytes }, generatedLargeBytesEncode),
        try runTimed(io, "generated largebytes writeToAssumeCapacity reuse", iters.generated_binary, generated_large_bytes_bytes.len, GeneratedLargeBytesWriteToCtx{ .writer = &reusable_large_bytes_writer, .message = &generated_large_bytes }, generatedLargeBytesWriteToReuse),
        try runTimed(io, "generated largebytes encodeIntoAssumeCapacity buffer reuse", iters.generated_binary, generated_large_bytes_bytes.len, GeneratedLargeBytesEncodeIntoCtx{ .buffer = generated_large_bytes_buffer, .message = &generated_large_bytes }, generatedLargeBytesEncodeIntoReuse),
        try runTimed(io, "generated largebytes borrowed slices encode", iters.generated_binary, generated_large_bytes_bytes.len, GeneratedLargeBytesBorrowedSlicesCtx{ .message = &generated_large_bytes }, generatedLargeBytesBorrowedSlices),
        try runTimed(io, "generated largebytes decode", iters.generated_binary, generated_large_bytes_bytes.len, GeneratedLargeBytesDecodeCtx{ .allocator = allocator, .bytes = generated_large_bytes_bytes }, generatedLargeBytesDecode),
        try runTimed(io, "generated largebytes decode reuse", iters.generated_binary, generated_large_bytes_bytes.len, GeneratedLargeBytesDecodeReuseCtx{ .allocator = allocator, .bytes = generated_large_bytes_bytes, .message = &generated_large_bytes_decode_reuse }, generatedLargeBytesDecodeReuse),
        try runTimed(io, "generated largebytes borrowed view decode", iters.generated_binary, generated_large_bytes_bytes.len, LargeBytesBorrowedViewCtx{ .bytes = generated_large_bytes_bytes }, largeBytesBorrowedViewDecode),
        try runTimed(io, "generated presencemix encode", iters.generated_binary, generated_presence_mix_bytes.len, GeneratedPresenceMixEncodeCtx{ .allocator = allocator, .message = &generated_presence_mix }, generatedPresenceMixEncode),
        try runTimed(io, "generated presencemix writeToAssumeCapacity reuse", iters.generated_binary, generated_presence_mix_bytes.len, GeneratedPresenceMixWriteToCtx{ .writer = &reusable_presence_mix_writer, .message = &generated_presence_mix }, generatedPresenceMixWriteToReuse),
        try runTimed(io, "generated presencemix encodeIntoAssumeCapacity buffer reuse", iters.generated_binary, generated_presence_mix_bytes.len, GeneratedPresenceMixEncodeIntoCtx{ .buffer = generated_presence_mix_buffer, .message = &generated_presence_mix }, generatedPresenceMixEncodeIntoReuse),
        try runTimed(io, "generated presencemix trusted UTF-8 encodeIntoAssumeCapacity buffer reuse", iters.generated_binary, generated_presence_mix_bytes.len, GeneratedPresenceMixEncodeIntoCtx{ .buffer = generated_presence_mix_buffer, .message = &generated_presence_mix }, generatedPresenceMixTrustedUtf8EncodeIntoReuse),
        try runTimed(io, "generated presencemix decode", iters.generated_binary, generated_presence_mix_bytes.len, GeneratedPresenceMixDecodeCtx{ .allocator = allocator, .bytes = generated_presence_mix_bytes }, generatedPresenceMixDecode),
        try runTimed(io, "generated presencemix decode reuse", iters.generated_binary, generated_presence_mix_bytes.len, GeneratedPresenceMixDecodeReuseCtx{ .allocator = allocator, .bytes = generated_presence_mix_bytes, .message = &generated_presence_mix_decode_reuse }, generatedPresenceMixDecodeReuse),
        try runTimed(io, "generated complex encode", iters.generated_binary, generated_complex_bytes.len, GeneratedComplexEncodeCtx{ .allocator = allocator, .message = &generated_complex }, generatedComplexEncode),
        try runTimed(io, "generated complex writeToAssumeCapacity reuse", iters.generated_binary, generated_complex_bytes.len, GeneratedComplexWriteToCtx{ .writer = &reusable_complex_writer, .message = &generated_complex }, generatedComplexWriteToReuse),
        try runTimed(io, "generated complex encodeIntoAssumeCapacity buffer reuse", iters.generated_binary, generated_complex_bytes.len, GeneratedComplexEncodeIntoCtx{ .buffer = generated_complex_buffer, .message = &generated_complex }, generatedComplexEncodeIntoReuse),
        try runTimed(io, "generated complex trusted UTF-8 encodeIntoAssumeCapacity buffer reuse", iters.generated_binary, generated_complex_bytes.len, GeneratedComplexManualEncodeIntoCtx{ .buffer = generated_complex_buffer, .message = &generated_complex }, generatedComplexManualEncodeIntoReuse),
        try runTimed(io, "generated complex decode", iters.generated_binary, generated_complex_bytes.len, GeneratedComplexDecodeCtx{ .allocator = allocator, .bytes = generated_complex_bytes }, generatedComplexDecode),
        try runTimed(io, "generated complex decode reuse", iters.generated_binary, generated_complex_bytes.len, GeneratedComplexDecodeReuseCtx{ .allocator = allocator, .bytes = generated_complex_bytes, .message = &generated_complex_decode_reuse }, generatedComplexDecodeReuse),
        try runTimed(io, "generated complex JSON stringify", iters.json, generated_complex_json.len, GeneratedComplexJsonStringifyCtx{ .allocator = allocator, .message = &generated_complex }, generatedComplexJsonStringify),
        try runTimed(io, "generated complex JSON parse", iters.json, generated_complex_json.len, GeneratedComplexJsonParseCtx{ .allocator = allocator, .json = generated_complex_json }, generatedComplexJsonParse),
        try runTimed(io, "generated complex TextFormat format", iters.text, generated_complex_text.len, GeneratedComplexTextFormatCtx{ .allocator = allocator, .message = &generated_complex }, generatedComplexTextFormat),
        try runTimed(io, "generated complex TextFormat parse", iters.text, generated_complex_text.len, GeneratedComplexTextParseCtx{ .allocator = allocator, .text = generated_complex_text }, generatedComplexTextParse),
        try runTimed(io, "generated complex deterministic binary encode", iters.generated_binary, generated_complex_bytes.len, GeneratedComplexDeterministicEncodeCtx{ .allocator = allocator, .message = &generated_complex }, generatedComplexDeterministicEncode),
        try runTimed(io, "generated complex deterministic binary encodeIntoAssumeCapacity buffer reuse", iters.generated_binary, generated_complex_bytes.len, GeneratedComplexDeterministicEncodeIntoCtx{ .allocator = allocator, .buffer = generated_complex_buffer, .message = &generated_complex }, generatedComplexDeterministicEncodeIntoReuse),
        try runTimed(io, "dynamic binary encode", iters.dynamic_binary, dynamic_bytes.len, DynamicEncodeCtx{ .message = &dynamic_person, .file = &file }, dynamicEncode),
        try runTimed(io, "dynamic binary decode", iters.dynamic_binary, dynamic_bytes.len, DynamicDecodeCtx{ .allocator = allocator, .descriptor = desc, .file = &file, .bytes = dynamic_bytes }, dynamicDecode),
        try runTimed(io, "dynamic unknown fields decode", iters.large_map, generated_unknown_bytes.len, DynamicUnknownDecodeCtx{ .allocator = allocator, .descriptor = desc, .file = &file, .bytes = generated_unknown_bytes }, dynamicUnknownDecode),
        try runTimed(io, "dynamic unknown fields count by number", iters.generated_binary, generated_unknown_bytes.len, DynamicUnknownQueryCtx{ .message = &dynamic_unknown_person, .number = UnknownFieldStressFirstNumber }, dynamicUnknownCountByNumber),
        try runTimed(io, "dynamic unknown field number sidecar count", iters.generated_binary, generated_unknown_bytes.len, DynamicUnknownNumberQueryCtx{ .numbers = dynamic_unknown_numbers, .number = UnknownFieldStressFirstNumber }, dynamicUnknownNumberCountByNumber),
        try runTimed(io, "dynamic unknown field number run sidecar count", iters.generated_binary, generated_unknown_bytes.len, DynamicUnknownRunQueryCtx{ .runs = dynamic_unknown_number_runs, .number = UnknownFieldStressFirstNumber }, dynamicUnknownNumberRunCountByNumber),
        try runTimed(io, "generated packed encode", iters.packed_binary, generated_packed_bytes.len, GeneratedPackedEncodeCtx{ .allocator = allocator, .message = &generated_packed }, generatedPackedEncode),
        try runTimed(io, "generated packed writeToAssumeCapacity reuse", iters.packed_binary, generated_packed_bytes.len, GeneratedPackedWriteToCtx{ .writer = &reusable_packed_writer, .message = &generated_packed }, generatedPackedWriteToReuse),
        try runTimed(io, "generated packed encodeIntoAssumeCapacity buffer reuse", iters.packed_binary, generated_packed_bytes.len, GeneratedPackedEncodeIntoCtx{ .buffer = generated_packed_buffer, .message = &generated_packed }, generatedPackedEncodeIntoReuse),
        try runTimed(io, "generated packed decode", iters.packed_binary, generated_packed_bytes.len, GeneratedPackedDecodeCtx{ .allocator = allocator, .bytes = generated_packed_bytes }, generatedPackedDecode),
        try runTimed(io, "generated packed fast known-schema decode reuse", iters.packed_binary, generated_packed_bytes.len, GeneratedPackedDecodeReuseCtx{ .allocator = allocator, .bytes = generated_packed_bytes, .message = &generated_packed_decode_reuse }, generatedPackedKnownDecodeReuse),
        try runTimed(io, "generated int32 packed iterator decode", iters.packed_binary, generated_packed_bytes.len, Int32PackedIteratorCtx{ .bytes = generated_packed_bytes }, int32PackedIteratorDecode),
        try runTimed(io, "dynamic packed encode", iters.packed_binary, dynamic_packed_bytes.len, DynamicPackedEncodeCtx{ .message = &dynamic_packed, .file = &file }, dynamicPackedEncode),
        try runTimed(io, "dynamic packed decode", iters.packed_binary, dynamic_packed_bytes.len, DynamicPackedDecodeCtx{ .allocator = allocator, .descriptor = packed_desc, .file = &file, .bytes = dynamic_packed_bytes }, dynamicPackedDecode),
        try runTimed(io, "generated fixed32 packed encode", iters.packed_binary, generated_fixed_packed_bytes.len, GeneratedFixedPackedEncodeCtx{ .allocator = allocator, .message = &generated_fixed_packed }, generatedFixedPackedEncode),
        try runTimed(io, "generated fixed32 packed encodeIntoAssumeCapacity buffer reuse", iters.packed_binary, generated_fixed_packed_bytes.len, GeneratedFixedPackedEncodeIntoCtx{ .buffer = generated_fixed_packed_buffer, .message = &generated_fixed_packed }, generatedFixedPackedEncodeIntoReuse),
        try runTimed(io, "generated fixed32 packed borrowed slices encode", iters.packed_binary, generated_fixed_packed_bytes.len, GeneratedFixedPackedSlicesCtx{ .message = &generated_fixed_packed }, generatedFixedPackedBorrowedSlices),
        try runTimed(io, "generated fixed32 packed decode", iters.packed_binary, generated_fixed_packed_bytes.len, GeneratedFixedPackedDecodeCtx{ .allocator = allocator, .bytes = generated_fixed_packed_bytes }, generatedFixedPackedDecode),
        try runTimed(io, "generated fixed32 packed fast known-schema decode reuse", iters.packed_binary, generated_fixed_packed_bytes.len, GeneratedFixedPackedDecodeReuseCtx{ .allocator = allocator, .bytes = generated_fixed_packed_bytes, .message = &generated_fixed_packed_decode_reuse }, generatedFixedPackedKnownDecodeReuse),
        try runTimed(io, "generated fixed32 packed borrowed view decode", iters.packed_binary, generated_fixed_packed_bytes.len, FixedPackedBorrowedViewCtx{ .bytes = generated_fixed_packed_bytes }, fixedPackedBorrowedViewDecode),
        try runTimed(io, "dynamic fixed32 packed encode", iters.packed_binary, dynamic_fixed_packed_bytes.len, DynamicFixedPackedEncodeCtx{ .message = &dynamic_fixed_packed, .file = &file }, dynamicFixedPackedEncode),
        try runTimed(io, "dynamic fixed32 packed decode", iters.packed_binary, dynamic_fixed_packed_bytes.len, DynamicFixedPackedDecodeCtx{ .allocator = allocator, .descriptor = fixed_packed_desc, .file = &file, .bytes = dynamic_fixed_packed_bytes }, dynamicFixedPackedDecode),
        try runTimed(io, "dynamic fixed32 packed decode reuse", iters.packed_binary, dynamic_fixed_packed_bytes.len, DynamicFixedPackedDecodeReuseCtx{ .message = &dynamic_fixed_packed_decode_reuse, .file = &file, .bytes = dynamic_fixed_packed_bytes }, dynamicFixedPackedDecodeReuse),
        try runTimed(io, "generated fixed64 packed encode", iters.packed_binary, generated_fixed64_packed_bytes.len, GeneratedFixed64PackedEncodeCtx{ .allocator = allocator, .message = &generated_fixed64_packed }, generatedFixed64PackedEncode),
        try runTimed(io, "generated fixed64 packed encodeIntoAssumeCapacity buffer reuse", iters.packed_binary, generated_fixed64_packed_bytes.len, GeneratedFixed64PackedEncodeIntoCtx{ .buffer = generated_fixed64_packed_buffer, .message = &generated_fixed64_packed }, generatedFixed64PackedEncodeIntoReuse),
        try runTimed(io, "generated fixed64 packed borrowed slices encode", iters.packed_binary, generated_fixed64_packed_bytes.len, GeneratedFixed64PackedSlicesCtx{ .message = &generated_fixed64_packed }, generatedFixed64PackedBorrowedSlices),
        try runTimed(io, "generated fixed64 packed decode", iters.packed_binary, generated_fixed64_packed_bytes.len, GeneratedFixed64PackedDecodeCtx{ .allocator = allocator, .bytes = generated_fixed64_packed_bytes }, generatedFixed64PackedDecode),
        try runTimed(io, "generated fixed64 packed fast known-schema decode reuse", iters.packed_binary, generated_fixed64_packed_bytes.len, GeneratedFixed64PackedDecodeReuseCtx{ .allocator = allocator, .bytes = generated_fixed64_packed_bytes, .message = &generated_fixed64_packed_decode_reuse }, generatedFixed64PackedKnownDecodeReuse),
        try runTimed(io, "generated fixed64 packed borrowed view decode", iters.packed_binary, generated_fixed64_packed_bytes.len, Fixed64PackedBorrowedViewCtx{ .bytes = generated_fixed64_packed_bytes }, fixed64PackedBorrowedViewDecode),
        try runTimed(io, "dynamic fixed64 packed encode", iters.packed_binary, dynamic_fixed64_packed_bytes.len, DynamicFixed64PackedEncodeCtx{ .message = &dynamic_fixed64_packed, .file = &file }, dynamicFixed64PackedEncode),
        try runTimed(io, "dynamic fixed64 packed decode", iters.packed_binary, dynamic_fixed64_packed_bytes.len, DynamicFixed64PackedDecodeCtx{ .allocator = allocator, .descriptor = fixed64_packed_desc, .file = &file, .bytes = dynamic_fixed64_packed_bytes }, dynamicFixed64PackedDecode),
        try runTimed(io, "dynamic fixed64 packed decode reuse", iters.packed_binary, dynamic_fixed64_packed_bytes.len, DynamicFixed64PackedDecodeReuseCtx{ .message = &dynamic_fixed64_packed_decode_reuse, .file = &file, .bytes = dynamic_fixed64_packed_bytes }, dynamicFixed64PackedDecodeReuse),
        try runTimed(io, "generated sfixed32 packed encode", iters.packed_binary, generated_sfixed_packed_bytes.len, GeneratedSFixedPackedEncodeCtx{ .allocator = allocator, .message = &generated_sfixed_packed }, generatedSFixedPackedEncode),
        try runTimed(io, "generated sfixed32 packed encodeIntoAssumeCapacity buffer reuse", iters.packed_binary, generated_sfixed_packed_bytes.len, GeneratedSFixedPackedEncodeIntoCtx{ .buffer = generated_sfixed_packed_buffer, .message = &generated_sfixed_packed }, generatedSFixedPackedEncodeIntoReuse),
        try runTimed(io, "generated sfixed32 packed borrowed slices encode", iters.packed_binary, generated_sfixed_packed_bytes.len, GeneratedSFixedPackedSlicesCtx{ .message = &generated_sfixed_packed }, generatedSFixedPackedBorrowedSlices),
        try runTimed(io, "generated sfixed32 packed decode", iters.packed_binary, generated_sfixed_packed_bytes.len, GeneratedSFixedPackedDecodeCtx{ .allocator = allocator, .bytes = generated_sfixed_packed_bytes }, generatedSFixedPackedDecode),
        try runTimed(io, "generated sfixed32 packed fast known-schema decode reuse", iters.packed_binary, generated_sfixed_packed_bytes.len, GeneratedSFixedPackedDecodeReuseCtx{ .allocator = allocator, .bytes = generated_sfixed_packed_bytes, .message = &generated_sfixed_packed_decode_reuse }, generatedSFixedPackedKnownDecodeReuse),
        try runTimed(io, "generated sfixed32 packed borrowed view decode", iters.packed_binary, generated_sfixed_packed_bytes.len, SFixedPackedBorrowedViewCtx{ .bytes = generated_sfixed_packed_bytes }, sfixedPackedBorrowedViewDecode),
        try runTimed(io, "dynamic sfixed32 packed encode", iters.packed_binary, dynamic_sfixed_packed_bytes.len, DynamicSFixedPackedEncodeCtx{ .message = &dynamic_sfixed_packed, .file = &file }, dynamicSFixedPackedEncode),
        try runTimed(io, "dynamic sfixed32 packed decode", iters.packed_binary, dynamic_sfixed_packed_bytes.len, DynamicSFixedPackedDecodeCtx{ .allocator = allocator, .descriptor = sfixed_packed_desc, .file = &file, .bytes = dynamic_sfixed_packed_bytes }, dynamicSFixedPackedDecode),
        try runTimed(io, "dynamic sfixed32 packed decode reuse", iters.packed_binary, dynamic_sfixed_packed_bytes.len, DynamicSFixedPackedDecodeReuseCtx{ .message = &dynamic_sfixed_packed_decode_reuse, .file = &file, .bytes = dynamic_sfixed_packed_bytes }, dynamicSFixedPackedDecodeReuse),
        try runTimed(io, "generated sfixed64 packed encode", iters.packed_binary, generated_sfixed64_packed_bytes.len, GeneratedSFixed64PackedEncodeCtx{ .allocator = allocator, .message = &generated_sfixed64_packed }, generatedSFixed64PackedEncode),
        try runTimed(io, "generated sfixed64 packed encodeIntoAssumeCapacity buffer reuse", iters.packed_binary, generated_sfixed64_packed_bytes.len, GeneratedSFixed64PackedEncodeIntoCtx{ .buffer = generated_sfixed64_packed_buffer, .message = &generated_sfixed64_packed }, generatedSFixed64PackedEncodeIntoReuse),
        try runTimed(io, "generated sfixed64 packed borrowed slices encode", iters.packed_binary, generated_sfixed64_packed_bytes.len, GeneratedSFixed64PackedSlicesCtx{ .message = &generated_sfixed64_packed }, generatedSFixed64PackedBorrowedSlices),
        try runTimed(io, "generated sfixed64 packed decode", iters.packed_binary, generated_sfixed64_packed_bytes.len, GeneratedSFixed64PackedDecodeCtx{ .allocator = allocator, .bytes = generated_sfixed64_packed_bytes }, generatedSFixed64PackedDecode),
        try runTimed(io, "generated sfixed64 packed fast known-schema decode reuse", iters.packed_binary, generated_sfixed64_packed_bytes.len, GeneratedSFixed64PackedDecodeReuseCtx{ .allocator = allocator, .bytes = generated_sfixed64_packed_bytes, .message = &generated_sfixed64_packed_decode_reuse }, generatedSFixed64PackedKnownDecodeReuse),
        try runTimed(io, "generated sfixed64 packed borrowed view decode", iters.packed_binary, generated_sfixed64_packed_bytes.len, SFixed64PackedBorrowedViewCtx{ .bytes = generated_sfixed64_packed_bytes }, sfixed64PackedBorrowedViewDecode),
        try runTimed(io, "dynamic sfixed64 packed encode", iters.packed_binary, dynamic_sfixed64_packed_bytes.len, DynamicSFixed64PackedEncodeCtx{ .message = &dynamic_sfixed64_packed, .file = &file }, dynamicSFixed64PackedEncode),
        try runTimed(io, "dynamic sfixed64 packed decode", iters.packed_binary, dynamic_sfixed64_packed_bytes.len, DynamicSFixed64PackedDecodeCtx{ .allocator = allocator, .descriptor = sfixed64_packed_desc, .file = &file, .bytes = dynamic_sfixed64_packed_bytes }, dynamicSFixed64PackedDecode),
        try runTimed(io, "dynamic sfixed64 packed decode reuse", iters.packed_binary, dynamic_sfixed64_packed_bytes.len, DynamicSFixed64PackedDecodeReuseCtx{ .message = &dynamic_sfixed64_packed_decode_reuse, .file = &file, .bytes = dynamic_sfixed64_packed_bytes }, dynamicSFixed64PackedDecodeReuse),
        try runTimed(io, "generated float packed encode", iters.packed_binary, generated_float_packed_bytes.len, GeneratedFloatPackedEncodeCtx{ .allocator = allocator, .message = &generated_float_packed }, generatedFloatPackedEncode),
        try runTimed(io, "generated float packed encodeIntoAssumeCapacity buffer reuse", iters.packed_binary, generated_float_packed_bytes.len, GeneratedFloatPackedEncodeIntoCtx{ .buffer = generated_float_packed_buffer, .message = &generated_float_packed }, generatedFloatPackedEncodeIntoReuse),
        try runTimed(io, "generated float packed borrowed slices encode", iters.packed_binary, generated_float_packed_bytes.len, GeneratedFloatPackedSlicesCtx{ .message = &generated_float_packed }, generatedFloatPackedBorrowedSlices),
        try runTimed(io, "generated float packed decode", iters.packed_binary, generated_float_packed_bytes.len, GeneratedFloatPackedDecodeCtx{ .allocator = allocator, .bytes = generated_float_packed_bytes }, generatedFloatPackedDecode),
        try runTimed(io, "generated float packed fast known-schema decode reuse", iters.packed_binary, generated_float_packed_bytes.len, GeneratedFloatPackedDecodeReuseCtx{ .allocator = allocator, .bytes = generated_float_packed_bytes, .message = &generated_float_packed_decode_reuse }, generatedFloatPackedKnownDecodeReuse),
        try runTimed(io, "generated float packed borrowed view decode", iters.packed_binary, generated_float_packed_bytes.len, FloatPackedBorrowedViewCtx{ .bytes = generated_float_packed_bytes }, floatPackedBorrowedViewDecode),
        try runTimed(io, "dynamic float packed encode", iters.packed_binary, dynamic_float_packed_bytes.len, DynamicFloatPackedEncodeCtx{ .message = &dynamic_float_packed, .file = &file }, dynamicFloatPackedEncode),
        try runTimed(io, "dynamic float packed decode", iters.packed_binary, dynamic_float_packed_bytes.len, DynamicFloatPackedDecodeCtx{ .allocator = allocator, .descriptor = float_packed_desc, .file = &file, .bytes = dynamic_float_packed_bytes }, dynamicFloatPackedDecode),
        try runTimed(io, "dynamic float packed decode reuse", iters.packed_binary, dynamic_float_packed_bytes.len, DynamicFloatPackedDecodeReuseCtx{ .message = &dynamic_float_packed_decode_reuse, .file = &file, .bytes = dynamic_float_packed_bytes }, dynamicFloatPackedDecodeReuse),
        try runTimed(io, "generated double packed encode", iters.packed_binary, generated_double_packed_bytes.len, GeneratedDoublePackedEncodeCtx{ .allocator = allocator, .message = &generated_double_packed }, generatedDoublePackedEncode),
        try runTimed(io, "generated double packed encodeIntoAssumeCapacity buffer reuse", iters.packed_binary, generated_double_packed_bytes.len, GeneratedDoublePackedEncodeIntoCtx{ .buffer = generated_double_packed_buffer, .message = &generated_double_packed }, generatedDoublePackedEncodeIntoReuse),
        try runTimed(io, "generated double packed borrowed slices encode", iters.packed_binary, generated_double_packed_bytes.len, GeneratedDoublePackedSlicesCtx{ .message = &generated_double_packed }, generatedDoublePackedBorrowedSlices),
        try runTimed(io, "generated double packed decode", iters.packed_binary, generated_double_packed_bytes.len, GeneratedDoublePackedDecodeCtx{ .allocator = allocator, .bytes = generated_double_packed_bytes }, generatedDoublePackedDecode),
        try runTimed(io, "generated double packed fast known-schema decode reuse", iters.packed_binary, generated_double_packed_bytes.len, GeneratedDoublePackedDecodeReuseCtx{ .allocator = allocator, .bytes = generated_double_packed_bytes, .message = &generated_double_packed_decode_reuse }, generatedDoublePackedKnownDecodeReuse),
        try runTimed(io, "generated double packed borrowed view decode", iters.packed_binary, generated_double_packed_bytes.len, DoublePackedBorrowedViewCtx{ .bytes = generated_double_packed_bytes }, doublePackedBorrowedViewDecode),
        try runTimed(io, "dynamic double packed encode", iters.packed_binary, dynamic_double_packed_bytes.len, DynamicDoublePackedEncodeCtx{ .message = &dynamic_double_packed, .file = &file }, dynamicDoublePackedEncode),
        try runTimed(io, "dynamic double packed decode", iters.packed_binary, dynamic_double_packed_bytes.len, DynamicDoublePackedDecodeCtx{ .allocator = allocator, .descriptor = double_packed_desc, .file = &file, .bytes = dynamic_double_packed_bytes }, dynamicDoublePackedDecode),
        try runTimed(io, "dynamic double packed decode reuse", iters.packed_binary, dynamic_double_packed_bytes.len, DynamicDoublePackedDecodeReuseCtx{ .message = &dynamic_double_packed_decode_reuse, .file = &file, .bytes = dynamic_double_packed_bytes }, dynamicDoublePackedDecodeReuse),
        try runTimed(io, "generated uint64 packed encode", iters.packed_binary, generated_uint64_packed_bytes.len, GeneratedUInt64PackedEncodeCtx{ .allocator = allocator, .message = &generated_uint64_packed }, generatedUInt64PackedEncode),
        try runTimed(io, "generated uint64 packed encodeIntoAssumeCapacity buffer reuse", iters.packed_binary, generated_uint64_packed_bytes.len, GeneratedUInt64PackedEncodeIntoCtx{ .buffer = generated_uint64_packed_buffer, .message = &generated_uint64_packed }, generatedUInt64PackedEncodeIntoReuse),
        try runTimed(io, "generated uint64 packed decode", iters.packed_binary, generated_uint64_packed_bytes.len, GeneratedUInt64PackedDecodeCtx{ .allocator = allocator, .bytes = generated_uint64_packed_bytes }, generatedUInt64PackedDecode),
        try runTimed(io, "generated uint64 packed decode reuse", iters.packed_binary, generated_uint64_packed_bytes.len, GeneratedUInt64PackedDecodeReuseCtx{ .allocator = allocator, .bytes = generated_uint64_packed_bytes, .message = &generated_uint64_packed_decode_reuse }, generatedUInt64PackedDecodeReuse),
        try runTimed(io, "generated uint64 packed fast known-schema decode reuse", iters.packed_binary, generated_uint64_packed_bytes.len, GeneratedUInt64PackedDecodeReuseCtx{ .allocator = allocator, .bytes = generated_uint64_packed_bytes, .message = &generated_uint64_packed_decode_reuse }, generatedUInt64PackedKnownDecodeReuse),
        try runTimed(io, "generated uint64 packed iterator decode", iters.packed_binary, generated_uint64_packed_bytes.len, UInt64PackedIteratorCtx{ .bytes = generated_uint64_packed_bytes }, uint64PackedIteratorDecode),
        try runTimed(io, "dynamic uint64 packed encode", iters.packed_binary, dynamic_uint64_packed_bytes.len, DynamicUInt64PackedEncodeCtx{ .message = &dynamic_uint64_packed, .file = &file }, dynamicUInt64PackedEncode),
        try runTimed(io, "dynamic uint64 packed decode", iters.packed_binary, dynamic_uint64_packed_bytes.len, DynamicUInt64PackedDecodeCtx{ .allocator = allocator, .descriptor = uint64_packed_desc, .file = &file, .bytes = dynamic_uint64_packed_bytes }, dynamicUInt64PackedDecode),
        try runTimed(io, "generated uint32 packed encode", iters.packed_binary, generated_uint32_packed_bytes.len, GeneratedUInt32PackedEncodeCtx{ .allocator = allocator, .message = &generated_uint32_packed }, generatedUInt32PackedEncode),
        try runTimed(io, "generated uint32 packed encodeIntoAssumeCapacity buffer reuse", iters.packed_binary, generated_uint32_packed_bytes.len, GeneratedUInt32PackedEncodeIntoCtx{ .buffer = generated_uint32_packed_buffer, .message = &generated_uint32_packed }, generatedUInt32PackedEncodeIntoReuse),
        try runTimed(io, "generated uint32 packed decode", iters.packed_binary, generated_uint32_packed_bytes.len, GeneratedUInt32PackedDecodeCtx{ .allocator = allocator, .bytes = generated_uint32_packed_bytes }, generatedUInt32PackedDecode),
        try runTimed(io, "generated uint32 packed decode reuse", iters.packed_binary, generated_uint32_packed_bytes.len, GeneratedUInt32PackedDecodeReuseCtx{ .allocator = allocator, .bytes = generated_uint32_packed_bytes, .message = &generated_uint32_packed_decode_reuse }, generatedUInt32PackedDecodeReuse),
        try runTimed(io, "generated uint32 packed fast known-schema decode reuse", iters.packed_binary, generated_uint32_packed_bytes.len, GeneratedUInt32PackedDecodeReuseCtx{ .allocator = allocator, .bytes = generated_uint32_packed_bytes, .message = &generated_uint32_packed_decode_reuse }, generatedUInt32PackedKnownDecodeReuse),
        try runTimed(io, "generated uint32 packed iterator decode", iters.packed_binary, generated_uint32_packed_bytes.len, UInt32PackedIteratorCtx{ .bytes = generated_uint32_packed_bytes }, uint32PackedIteratorDecode),
        try runTimed(io, "dynamic uint32 packed encode", iters.packed_binary, dynamic_uint32_packed_bytes.len, DynamicUInt32PackedEncodeCtx{ .message = &dynamic_uint32_packed, .file = &file }, dynamicUInt32PackedEncode),
        try runTimed(io, "dynamic uint32 packed decode", iters.packed_binary, dynamic_uint32_packed_bytes.len, DynamicUInt32PackedDecodeCtx{ .allocator = allocator, .descriptor = uint32_packed_desc, .file = &file, .bytes = dynamic_uint32_packed_bytes }, dynamicUInt32PackedDecode),
        try runTimed(io, "generated int64 packed encode", iters.packed_binary, generated_int64_packed_bytes.len, GeneratedInt64PackedEncodeCtx{ .allocator = allocator, .message = &generated_int64_packed }, generatedInt64PackedEncode),
        try runTimed(io, "generated int64 packed encodeIntoAssumeCapacity buffer reuse", iters.packed_binary, generated_int64_packed_bytes.len, GeneratedInt64PackedEncodeIntoCtx{ .buffer = generated_int64_packed_buffer, .message = &generated_int64_packed }, generatedInt64PackedEncodeIntoReuse),
        try runTimed(io, "generated int64 packed decode", iters.packed_binary, generated_int64_packed_bytes.len, GeneratedInt64PackedDecodeCtx{ .allocator = allocator, .bytes = generated_int64_packed_bytes }, generatedInt64PackedDecode),
        try runTimed(io, "generated int64 packed fast known-schema decode reuse", iters.packed_binary, generated_int64_packed_bytes.len, GeneratedInt64PackedDecodeReuseCtx{ .allocator = allocator, .bytes = generated_int64_packed_bytes, .message = &generated_int64_packed_decode_reuse }, generatedInt64PackedKnownDecodeReuse),
        try runTimed(io, "generated int64 packed iterator decode", iters.packed_binary, generated_int64_packed_bytes.len, Int64PackedIteratorCtx{ .bytes = generated_int64_packed_bytes }, int64PackedIteratorDecode),
        try runTimed(io, "dynamic int64 packed encode", iters.packed_binary, dynamic_int64_packed_bytes.len, DynamicInt64PackedEncodeCtx{ .message = &dynamic_int64_packed, .file = &file }, dynamicInt64PackedEncode),
        try runTimed(io, "dynamic int64 packed decode", iters.packed_binary, dynamic_int64_packed_bytes.len, DynamicInt64PackedDecodeCtx{ .allocator = allocator, .descriptor = int64_packed_desc, .file = &file, .bytes = dynamic_int64_packed_bytes }, dynamicInt64PackedDecode),
        try runTimed(io, "generated sint32 packed encode", iters.packed_binary, generated_sint32_packed_bytes.len, GeneratedSInt32PackedEncodeCtx{ .allocator = allocator, .message = &generated_sint32_packed }, generatedSInt32PackedEncode),
        try runTimed(io, "generated sint32 packed encodeIntoAssumeCapacity buffer reuse", iters.packed_binary, generated_sint32_packed_bytes.len, GeneratedSInt32PackedEncodeIntoCtx{ .buffer = generated_sint32_packed_buffer, .message = &generated_sint32_packed }, generatedSInt32PackedEncodeIntoReuse),
        try runTimed(io, "generated sint32 packed decode", iters.packed_binary, generated_sint32_packed_bytes.len, GeneratedSInt32PackedDecodeCtx{ .allocator = allocator, .bytes = generated_sint32_packed_bytes }, generatedSInt32PackedDecode),
        try runTimed(io, "generated sint32 packed fast known-schema decode reuse", iters.packed_binary, generated_sint32_packed_bytes.len, GeneratedSInt32PackedDecodeReuseCtx{ .allocator = allocator, .bytes = generated_sint32_packed_bytes, .message = &generated_sint32_packed_decode_reuse }, generatedSInt32PackedKnownDecodeReuse),
        try runTimed(io, "generated sint32 packed iterator decode", iters.packed_binary, generated_sint32_packed_bytes.len, SInt32PackedIteratorCtx{ .bytes = generated_sint32_packed_bytes }, sint32PackedIteratorDecode),
        try runTimed(io, "dynamic sint32 packed encode", iters.packed_binary, dynamic_sint32_packed_bytes.len, DynamicSInt32PackedEncodeCtx{ .message = &dynamic_sint32_packed, .file = &file }, dynamicSInt32PackedEncode),
        try runTimed(io, "dynamic sint32 packed decode", iters.packed_binary, dynamic_sint32_packed_bytes.len, DynamicSInt32PackedDecodeCtx{ .allocator = allocator, .descriptor = sint32_packed_desc, .file = &file, .bytes = dynamic_sint32_packed_bytes }, dynamicSInt32PackedDecode),
        try runTimed(io, "generated sint64 packed encode", iters.packed_binary, generated_sint64_packed_bytes.len, GeneratedSInt64PackedEncodeCtx{ .allocator = allocator, .message = &generated_sint64_packed }, generatedSInt64PackedEncode),
        try runTimed(io, "generated sint64 packed encodeIntoAssumeCapacity buffer reuse", iters.packed_binary, generated_sint64_packed_bytes.len, GeneratedSInt64PackedEncodeIntoCtx{ .buffer = generated_sint64_packed_buffer, .message = &generated_sint64_packed }, generatedSInt64PackedEncodeIntoReuse),
        try runTimed(io, "generated sint64 packed decode", iters.packed_binary, generated_sint64_packed_bytes.len, GeneratedSInt64PackedDecodeCtx{ .allocator = allocator, .bytes = generated_sint64_packed_bytes }, generatedSInt64PackedDecode),
        try runTimed(io, "generated sint64 packed fast known-schema decode reuse", iters.packed_binary, generated_sint64_packed_bytes.len, GeneratedSInt64PackedDecodeReuseCtx{ .allocator = allocator, .bytes = generated_sint64_packed_bytes, .message = &generated_sint64_packed_decode_reuse }, generatedSInt64PackedKnownDecodeReuse),
        try runTimed(io, "generated sint64 packed iterator decode", iters.packed_binary, generated_sint64_packed_bytes.len, SInt64PackedIteratorCtx{ .bytes = generated_sint64_packed_bytes }, sint64PackedIteratorDecode),
        try runTimed(io, "dynamic sint64 packed encode", iters.packed_binary, dynamic_sint64_packed_bytes.len, DynamicSInt64PackedEncodeCtx{ .message = &dynamic_sint64_packed, .file = &file }, dynamicSInt64PackedEncode),
        try runTimed(io, "dynamic sint64 packed decode", iters.packed_binary, dynamic_sint64_packed_bytes.len, DynamicSInt64PackedDecodeCtx{ .allocator = allocator, .descriptor = sint64_packed_desc, .file = &file, .bytes = dynamic_sint64_packed_bytes }, dynamicSInt64PackedDecode),
        try runTimed(io, "generated bool packed encode", iters.packed_binary, generated_bool_packed_bytes.len, GeneratedBoolPackedEncodeCtx{ .allocator = allocator, .message = &generated_bool_packed }, generatedBoolPackedEncode),
        try runTimed(io, "generated bool packed encodeIntoAssumeCapacity buffer reuse", iters.packed_binary, generated_bool_packed_bytes.len, GeneratedBoolPackedEncodeIntoCtx{ .buffer = generated_bool_packed_buffer, .message = &generated_bool_packed }, generatedBoolPackedEncodeIntoReuse),
        try runTimed(io, "generated bool packed borrowed slices encode", iters.packed_binary, generated_bool_packed_bytes.len, GeneratedBoolPackedSlicesCtx{ .message = &generated_bool_packed }, generatedBoolPackedBorrowedSlices),
        try runTimed(io, "generated bool packed decode", iters.packed_binary, generated_bool_packed_bytes.len, GeneratedBoolPackedDecodeCtx{ .allocator = allocator, .bytes = generated_bool_packed_bytes }, generatedBoolPackedDecode),
        try runTimed(io, "generated bool packed fast known-schema decode reuse", iters.packed_binary, generated_bool_packed_bytes.len, GeneratedBoolPackedDecodeReuseCtx{ .allocator = allocator, .bytes = generated_bool_packed_bytes, .message = &generated_bool_packed_decode_reuse }, generatedBoolPackedKnownDecodeReuse),
        try runTimed(io, "dynamic bool packed encode", iters.packed_binary, dynamic_bool_packed_bytes.len, DynamicBoolPackedEncodeCtx{ .message = &dynamic_bool_packed, .file = &file }, dynamicBoolPackedEncode),
        try runTimed(io, "dynamic bool packed decode", iters.packed_binary, dynamic_bool_packed_bytes.len, DynamicBoolPackedDecodeCtx{ .allocator = allocator, .descriptor = bool_packed_desc, .file = &file, .bytes = dynamic_bool_packed_bytes }, dynamicBoolPackedDecode),
        try runTimed(io, "generated enum packed encode", iters.packed_binary, generated_enum_packed_bytes.len, GeneratedEnumPackedEncodeCtx{ .allocator = allocator, .message = &generated_enum_packed }, generatedEnumPackedEncode),
        try runTimed(io, "generated enum packed encodeIntoAssumeCapacity buffer reuse", iters.packed_binary, generated_enum_packed_bytes.len, GeneratedEnumPackedEncodeIntoCtx{ .buffer = generated_enum_packed_buffer, .message = &generated_enum_packed }, generatedEnumPackedEncodeIntoReuse),
        try runTimed(io, "generated enum packed decode", iters.packed_binary, generated_enum_packed_bytes.len, GeneratedEnumPackedDecodeCtx{ .allocator = allocator, .bytes = generated_enum_packed_bytes }, generatedEnumPackedDecode),
        try runTimed(io, "generated enum packed decode reuse", iters.packed_binary, generated_enum_packed_bytes.len, GeneratedEnumPackedDecodeReuseCtx{ .allocator = allocator, .bytes = generated_enum_packed_bytes, .message = &generated_enum_packed_decode_reuse }, generatedEnumPackedDecodeReuse),
        try runTimed(io, "generated enum packed fast known-schema decode reuse", iters.packed_binary, generated_enum_packed_bytes.len, GeneratedEnumPackedDecodeReuseCtx{ .allocator = allocator, .bytes = generated_enum_packed_bytes, .message = &generated_enum_packed_decode_reuse }, generatedEnumPackedKnownDecodeReuse),
        try runTimed(io, "dynamic enum packed encode", iters.packed_binary, dynamic_enum_packed_bytes.len, DynamicEnumPackedEncodeCtx{ .message = &dynamic_enum_packed, .file = &file }, dynamicEnumPackedEncode),
        try runTimed(io, "dynamic enum packed decode", iters.packed_binary, dynamic_enum_packed_bytes.len, DynamicEnumPackedDecodeCtx{ .allocator = allocator, .descriptor = enum_packed_desc, .file = &file, .bytes = dynamic_enum_packed_bytes }, dynamicEnumPackedDecode),
        try runTimed(io, "generated large map encode", iters.large_map, generated_large_map_bytes.len, GeneratedLargeMapEncodeCtx{ .allocator = allocator, .message = &generated_large_map }, generatedLargeMapEncode),
        try runTimed(io, "generated large map writeToAssumeCapacity reuse", iters.large_map, generated_large_map_bytes.len, GeneratedLargeMapWriteToCtx{ .writer = &reusable_large_map_writer, .message = &generated_large_map }, generatedLargeMapWriteToReuse),
        try runTimed(io, "generated large map encodeIntoAssumeCapacity buffer reuse", iters.large_map, generated_large_map_bytes.len, GeneratedLargeMapEncodeIntoCtx{ .buffer = generated_large_map_buffer, .message = &generated_large_map }, generatedLargeMapEncodeIntoReuse),
        try runTimed(io, "generated large map deterministic encodeIntoAssumeCapacity buffer reuse", iters.large_map, generated_large_map_bytes.len, GeneratedLargeMapDeterministicEncodeIntoCtx{ .allocator = allocator, .buffer = generated_large_map_buffer, .message = &generated_large_map }, generatedLargeMapDeterministicEncodeIntoReuse),
        try runTimed(io, "generated shuffled large map deterministic encodeIntoAssumeCapacity buffer reuse", iters.large_map, generated_shuffled_large_map_bytes.len, GeneratedLargeMapDeterministicEncodeIntoCtx{ .allocator = allocator, .buffer = generated_shuffled_large_map_buffer, .message = &generated_shuffled_large_map }, generatedLargeMapDeterministicEncodeIntoReuse),
        try runTimed(io, "generated large map decode", iters.large_map, generated_large_map_bytes.len, GeneratedLargeMapDecodeCtx{ .allocator = allocator, .bytes = generated_large_map_bytes }, generatedLargeMapDecode),
        try runTimed(io, "generated large map decode reuse", iters.large_map, generated_large_map_bytes.len, GeneratedLargeMapDecodeReuseCtx{ .allocator = allocator, .bytes = generated_large_map_bytes, .message = &generated_large_map_decode_reuse }, generatedLargeMapDecodeReuse),
        try runTimed(io, "dynamic large map encode", iters.large_map, dynamic_large_map_bytes.len, DynamicLargeMapEncodeCtx{ .message = &dynamic_large_map, .file = &file }, dynamicLargeMapEncode),
        try runTimed(io, "dynamic large map decode", iters.large_map, dynamic_large_map_bytes.len, DynamicLargeMapDecodeCtx{ .allocator = allocator, .descriptor = large_map_desc, .file = &file, .bytes = dynamic_large_map_bytes }, dynamicLargeMapDecode),
        try runTimed(io, "generated JSON stringify", iters.json, generated_json.len, GeneratedJsonStringifyCtx{ .allocator = allocator, .person = &generated_person }, generatedJsonStringify),
        try runTimed(io, "generated JSON parse", iters.json, generated_json.len, GeneratedJsonParseCtx{ .allocator = allocator, .json = generated_json }, generatedJsonParse),
        try runTimed(io, "dynamic JSON stringify", iters.json, dynamic_json.len, DynamicJsonStringifyCtx{ .allocator = allocator, .file = &file, .message = &dynamic_person }, dynamicJsonStringify),
        try runTimed(io, "dynamic JSON parse", iters.json, dynamic_json.len, DynamicJsonParseCtx{ .allocator = allocator, .file = &file, .descriptor = desc, .json = dynamic_json }, dynamicJsonParse),
        try runTimed(io, "pbz Any WKT JSON stringify", iters.json, any_wkt_json.len, AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_wkt }, anyWktJsonStringify),
        try runTimed(io, "pbz Any WKT JSON parse", iters.json, any_wkt_json.len, AnyWktJsonParseCtx{ .allocator = allocator, .json = any_wkt_json }, anyWktJsonParse),
        try runTimed(io, "pbz Any Struct WKT JSON stringify", iters.json, any_struct_wkt_json.len, AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_struct_wkt }, anyWktJsonStringify),
        try runTimed(io, "pbz Any Struct WKT JSON parse", iters.json, any_struct_wkt_json.len, AnyWktJsonParseCtx{ .allocator = allocator, .json = any_struct_wkt_json }, anyWktJsonParse),
        try runTimed(io, "pbz Any Value WKT JSON stringify", iters.json, any_value_wkt_json.len, AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_value_wkt }, anyWktJsonStringify),
        try runTimed(io, "pbz Any Value WKT JSON parse", iters.json, any_value_wkt_json.len, AnyWktJsonParseCtx{ .allocator = allocator, .json = any_value_wkt_json }, anyWktJsonParse),
        try runTimed(io, "pbz Any StringValue WKT JSON stringify", iters.json, any_string_value_wkt_json.len, AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_string_value_wkt }, anyWktJsonStringify),
        try runTimed(io, "pbz Any StringValue WKT JSON parse", iters.json, any_string_value_wkt_json.len, AnyWktJsonParseCtx{ .allocator = allocator, .json = any_string_value_wkt_json }, anyWktJsonParse),
        try runTimed(io, "pbz Any BytesValue WKT JSON stringify", iters.json, any_bytes_value_wkt_json.len, AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_bytes_value_wkt }, anyWktJsonStringify),
        try runTimed(io, "pbz Any BytesValue WKT JSON parse", iters.json, any_bytes_value_wkt_json.len, AnyWktJsonParseCtx{ .allocator = allocator, .json = any_bytes_value_wkt_json }, anyWktJsonParse),
        try runTimed(io, "pbz Nested Any WKT JSON stringify", iters.json, nested_any_wkt_json.len, AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &nested_any_wkt }, anyWktJsonStringify),
        try runTimed(io, "pbz Nested Any WKT JSON parse", iters.json, nested_any_wkt_json.len, AnyWktJsonParseCtx{ .allocator = allocator, .json = nested_any_wkt_json }, anyWktJsonParse),
        try runTimed(io, "pbz Duration JSON stringify", iters.json, duration_json.len, DurationJsonStringifyCtx{ .allocator = allocator, .duration = duration_value }, durationJsonStringify),
        try runTimed(io, "pbz Duration JSON parse", iters.json, duration_json.len, DurationJsonParseCtx{ .json = duration_json }, durationJsonParse),
        try runTimed(io, "pbz FieldMask JSON stringify", iters.json, field_mask_json.len, FieldMaskJsonStringifyCtx{ .allocator = allocator, .mask = &field_mask_value }, fieldMaskJsonStringify),
        try runTimed(io, "pbz FieldMask JSON parse", iters.json, field_mask_json.len, FieldMaskJsonParseCtx{ .allocator = allocator, .json = field_mask_json }, fieldMaskJsonParse),
        try runTimed(io, "pbz Timestamp JSON stringify", iters.json, timestamp_json.len, TimestampJsonStringifyCtx{ .allocator = allocator, .timestamp = timestamp_value }, timestampJsonStringify),
        try runTimed(io, "pbz Timestamp JSON parse", iters.json, timestamp_json.len, TimestampJsonParseCtx{ .json = timestamp_json }, timestampJsonParse),
        try runTimed(io, "pbz Empty JSON stringify", iters.json, empty_json.len, EmptyJsonStringifyCtx{ .allocator = allocator }, emptyJsonStringify),
        try runTimed(io, "pbz Empty JSON parse", iters.json, empty_json.len, EmptyJsonParseCtx{ .allocator = allocator, .json = empty_json }, emptyJsonParse),
        try runTimed(io, "pbz Struct JSON stringify", iters.json, struct_json.len, WktJsonStringifyCtx(pbz.Struct){ .allocator = allocator, .value = struct_value }, wktJsonStringify),
        try runTimed(io, "pbz Struct JSON parse", iters.json, struct_json.len, WktJsonParseCtx(pbz.Struct){ .allocator = allocator, .json = struct_json }, wktJsonParse),
        try runTimed(io, "pbz Value JSON stringify", iters.json, value_json.len, WktJsonStringifyCtx(pbz.Value){ .allocator = allocator, .value = value_value }, wktJsonStringify),
        try runTimed(io, "pbz Value JSON parse", iters.json, value_json.len, WktJsonParseCtx(pbz.Value){ .allocator = allocator, .json = value_json }, wktJsonParse),
        try runTimed(io, "pbz ListValue JSON stringify", iters.json, list_value_json.len, WktJsonStringifyCtx(pbz.ListValue){ .allocator = allocator, .value = list_value }, wktJsonStringify),
        try runTimed(io, "pbz ListValue JSON parse", iters.json, list_value_json.len, WktJsonParseCtx(pbz.ListValue){ .allocator = allocator, .json = list_value_json }, wktJsonParse),
        try runTimed(io, "pbz DoubleValue JSON stringify", iters.json, double_value_json.len, WktJsonStringifyCtx(pbz.DoubleValue){ .allocator = allocator, .value = double_value }, wktJsonStringify),
        try runTimed(io, "pbz DoubleValue JSON parse", iters.json, double_value_json.len, WktJsonParseCtx(pbz.DoubleValue){ .allocator = allocator, .json = double_value_json }, wktJsonParse),
        try runTimed(io, "pbz FloatValue JSON stringify", iters.json, float_value_json.len, WktJsonStringifyCtx(pbz.FloatValue){ .allocator = allocator, .value = float_value }, wktJsonStringify),
        try runTimed(io, "pbz FloatValue JSON parse", iters.json, float_value_json.len, WktJsonParseCtx(pbz.FloatValue){ .allocator = allocator, .json = float_value_json }, wktJsonParse),
        try runTimed(io, "pbz Int64Value JSON stringify", iters.json, int64_value_json.len, WktJsonStringifyCtx(pbz.Int64Value){ .allocator = allocator, .value = int64_value }, wktJsonStringify),
        try runTimed(io, "pbz Int64Value JSON parse", iters.json, int64_value_json.len, WktJsonParseCtx(pbz.Int64Value){ .allocator = allocator, .json = int64_value_json }, wktJsonParse),
        try runTimed(io, "pbz UInt64Value JSON stringify", iters.json, uint64_value_json.len, WktJsonStringifyCtx(pbz.UInt64Value){ .allocator = allocator, .value = uint64_value }, wktJsonStringify),
        try runTimed(io, "pbz UInt64Value JSON parse", iters.json, uint64_value_json.len, WktJsonParseCtx(pbz.UInt64Value){ .allocator = allocator, .json = uint64_value_json }, wktJsonParse),
        try runTimed(io, "pbz Int32Value JSON stringify", iters.json, int32_value_json.len, WktJsonStringifyCtx(pbz.Int32Value){ .allocator = allocator, .value = int32_value }, wktJsonStringify),
        try runTimed(io, "pbz Int32Value JSON parse", iters.json, int32_value_json.len, WktJsonParseCtx(pbz.Int32Value){ .allocator = allocator, .json = int32_value_json }, wktJsonParse),
        try runTimed(io, "pbz UInt32Value JSON stringify", iters.json, uint32_value_json.len, WktJsonStringifyCtx(pbz.UInt32Value){ .allocator = allocator, .value = uint32_value }, wktJsonStringify),
        try runTimed(io, "pbz UInt32Value JSON parse", iters.json, uint32_value_json.len, WktJsonParseCtx(pbz.UInt32Value){ .allocator = allocator, .json = uint32_value_json }, wktJsonParse),
        try runTimed(io, "pbz BoolValue JSON stringify", iters.json, bool_value_json.len, WktJsonStringifyCtx(pbz.BoolValue){ .allocator = allocator, .value = bool_value }, wktJsonStringify),
        try runTimed(io, "pbz BoolValue JSON parse", iters.json, bool_value_json.len, WktJsonParseCtx(pbz.BoolValue){ .allocator = allocator, .json = bool_value_json }, wktJsonParse),
        try runTimed(io, "pbz StringValue JSON stringify", iters.json, string_value_json.len, WktJsonStringifyCtx(pbz.StringValue){ .allocator = allocator, .value = string_value }, wktJsonStringify),
        try runTimed(io, "pbz StringValue JSON parse", iters.json, string_value_json.len, WktJsonParseCtx(pbz.StringValue){ .allocator = allocator, .json = string_value_json }, wktJsonParse),
        try runTimed(io, "pbz BytesValue JSON stringify", iters.json, bytes_value_json.len, WktJsonStringifyCtx(pbz.BytesValue){ .allocator = allocator, .value = bytes_value }, wktJsonStringify),
        try runTimed(io, "pbz BytesValue JSON parse", iters.json, bytes_value_json.len, WktJsonParseCtx(pbz.BytesValue){ .allocator = allocator, .json = bytes_value_json }, wktJsonParse),
        try runTimed(io, "generated TextFormat format", iters.text, generated_text.len, GeneratedTextFormatCtx{ .allocator = allocator, .person = &generated_person }, generatedTextFormat),
        try runTimed(io, "generated TextFormat parse", iters.text, generated_text.len, GeneratedTextParseCtx{ .allocator = allocator, .text = generated_text }, generatedTextParse),
        try runTimed(io, "dynamic TextFormat format", iters.text, dynamic_text.len, DynamicTextFormatCtx{ .allocator = allocator, .file = &file, .message = &dynamic_person }, dynamicTextFormat),
        try runTimed(io, "dynamic TextFormat parse", iters.text, dynamic_text.len, DynamicTextParseCtx{ .allocator = allocator, .file = &file, .descriptor = desc, .text = dynamic_text }, dynamicTextParse),
    };

    for (results) |result| result.print();
}
