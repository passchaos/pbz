const std = @import("std");
const pbz = @import("pbz");
const person_pb = @import("person_pb");
const fixtures = @import("fixtures.zig");
const generated = @import("generated.zig");
const packed_workloads = @import("packed.zig");
const dynamic = @import("dynamic.zig");
const json = @import("json.zig");
const unknown = @import("unknown.zig");
const maps = @import("maps.zig");

const Iterations = struct {
    generated_binary: usize = 20_000,
    dynamic_binary: usize = 10_000,
    json: usize = 2_000,
    text: usize = 1_000,
    packed_binary: usize = 5_000,
    large_map: usize = 1_000,
};

const BenchmarkSamples: usize = 3;
pub const LargeBytesPayloadLen: usize = 64 * 1024;
pub const LargeBytesChunkCount: usize = 16;
pub const LargeBytesChunkLen: usize = 4 * 1024;
pub const LargeMapEntryCount: usize = 1024;
pub const LargeMapShuffleMultiplier: usize = 257;
pub const LargeMapShuffleIncrement: usize = 911;
pub const UnknownFieldStressCount: usize = 1024;
pub const UnknownFieldStressFirstNumber: pbz.FieldNumber = 1000;
pub const UnknownFieldStressNumberSpan: pbz.FieldNumber = 16;

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

pub fn main() !void {
    // Use the libc allocator so allocation-heavy owning paths are compared
    // against malloc-based C++/Go/Rust baselines without smp_allocator's
    // page-return overhead dominating large decode/clone workloads.
    const allocator = std.heap.c_allocator;
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

    var generated_person = try fixtures.makeGeneratedPerson(allocator);
    defer generated_person.deinit(allocator);
    var dynamic_person = try fixtures.makeDynamicPerson(allocator, desc);
    defer dynamic_person.deinit();
    var generated_scalar_mix = try fixtures.makeGeneratedScalarMix(allocator);
    defer generated_scalar_mix.deinit(allocator);
    var generated_text_bytes = try fixtures.makeGeneratedTextBytes(allocator);
    defer generated_text_bytes.deinit(allocator);
    var generated_large_bytes = try fixtures.makeGeneratedLargeBytes(allocator);
    defer generated_large_bytes.deinit(allocator);
    var generated_presence_mix = try fixtures.makeGeneratedPresenceMix(allocator);
    defer generated_presence_mix.deinit(allocator);
    var generated_complex = try fixtures.makeGeneratedComplex(allocator);
    defer generated_complex.deinit(allocator);
    var generated_packed = try fixtures.makeGeneratedPacked(allocator);
    defer generated_packed.deinit(allocator);
    var dynamic_packed = try fixtures.makeDynamicPacked(allocator, packed_desc);
    defer dynamic_packed.deinit();
    var generated_fixed_packed = try fixtures.makeGeneratedFixedPacked(allocator);
    defer generated_fixed_packed.deinit(allocator);
    var dynamic_fixed_packed = try fixtures.makeDynamicFixedPacked(allocator, fixed_packed_desc);
    defer dynamic_fixed_packed.deinit();
    var dynamic_fixed_packed_decode_reuse = pbz.DynamicMessage.init(allocator, fixed_packed_desc);
    defer dynamic_fixed_packed_decode_reuse.deinit();
    var generated_fixed64_packed = try fixtures.makeGeneratedFixed64Packed(allocator);
    defer generated_fixed64_packed.deinit(allocator);
    var dynamic_fixed64_packed = try fixtures.makeDynamicFixed64Packed(allocator, fixed64_packed_desc);
    defer dynamic_fixed64_packed.deinit();
    var dynamic_fixed64_packed_decode_reuse = pbz.DynamicMessage.init(allocator, fixed64_packed_desc);
    defer dynamic_fixed64_packed_decode_reuse.deinit();
    var generated_sfixed_packed = try fixtures.makeGeneratedSFixedPacked(allocator);
    defer generated_sfixed_packed.deinit(allocator);
    var dynamic_sfixed_packed = try fixtures.makeDynamicSFixedPacked(allocator, sfixed_packed_desc);
    defer dynamic_sfixed_packed.deinit();
    var dynamic_sfixed_packed_decode_reuse = pbz.DynamicMessage.init(allocator, sfixed_packed_desc);
    defer dynamic_sfixed_packed_decode_reuse.deinit();
    var generated_sfixed64_packed = try fixtures.makeGeneratedSFixed64Packed(allocator);
    defer generated_sfixed64_packed.deinit(allocator);
    var dynamic_sfixed64_packed = try fixtures.makeDynamicSFixed64Packed(allocator, sfixed64_packed_desc);
    defer dynamic_sfixed64_packed.deinit();
    var dynamic_sfixed64_packed_decode_reuse = pbz.DynamicMessage.init(allocator, sfixed64_packed_desc);
    defer dynamic_sfixed64_packed_decode_reuse.deinit();
    var generated_float_packed = try fixtures.makeGeneratedFloatPacked(allocator);
    defer generated_float_packed.deinit(allocator);
    var dynamic_float_packed = try fixtures.makeDynamicFloatPacked(allocator, float_packed_desc);
    defer dynamic_float_packed.deinit();
    var dynamic_float_packed_decode_reuse = pbz.DynamicMessage.init(allocator, float_packed_desc);
    defer dynamic_float_packed_decode_reuse.deinit();
    var generated_double_packed = try fixtures.makeGeneratedDoublePacked(allocator);
    defer generated_double_packed.deinit(allocator);
    var dynamic_double_packed = try fixtures.makeDynamicDoublePacked(allocator, double_packed_desc);
    defer dynamic_double_packed.deinit();
    var dynamic_double_packed_decode_reuse = pbz.DynamicMessage.init(allocator, double_packed_desc);
    defer dynamic_double_packed_decode_reuse.deinit();
    var generated_uint64_packed = try fixtures.makeGeneratedUInt64Packed(allocator);
    defer generated_uint64_packed.deinit(allocator);
    var dynamic_uint64_packed = try fixtures.makeDynamicUInt64Packed(allocator, uint64_packed_desc);
    defer dynamic_uint64_packed.deinit();
    var generated_uint32_packed = try fixtures.makeGeneratedUInt32Packed(allocator);
    defer generated_uint32_packed.deinit(allocator);
    var dynamic_uint32_packed = try fixtures.makeDynamicUInt32Packed(allocator, uint32_packed_desc);
    defer dynamic_uint32_packed.deinit();
    var generated_int64_packed = try fixtures.makeGeneratedInt64Packed(allocator);
    defer generated_int64_packed.deinit(allocator);
    var dynamic_int64_packed = try fixtures.makeDynamicInt64Packed(allocator, int64_packed_desc);
    defer dynamic_int64_packed.deinit();
    var generated_sint32_packed = try fixtures.makeGeneratedSInt32Packed(allocator);
    defer generated_sint32_packed.deinit(allocator);
    var dynamic_sint32_packed = try fixtures.makeDynamicSInt32Packed(allocator, sint32_packed_desc);
    defer dynamic_sint32_packed.deinit();
    var generated_sint64_packed = try fixtures.makeGeneratedSInt64Packed(allocator);
    defer generated_sint64_packed.deinit(allocator);
    var dynamic_sint64_packed = try fixtures.makeDynamicSInt64Packed(allocator, sint64_packed_desc);
    defer dynamic_sint64_packed.deinit();
    var generated_bool_packed = try fixtures.makeGeneratedBoolPacked(allocator);
    defer generated_bool_packed.deinit(allocator);
    var dynamic_bool_packed = try fixtures.makeDynamicBoolPacked(allocator, bool_packed_desc);
    defer dynamic_bool_packed.deinit();
    var generated_enum_packed = try fixtures.makeGeneratedEnumPacked(allocator);
    defer generated_enum_packed.deinit(allocator);
    var dynamic_enum_packed = try fixtures.makeDynamicEnumPacked(allocator, enum_packed_desc);
    defer dynamic_enum_packed.deinit();
    var generated_large_map = try fixtures.makeGeneratedLargeMap(allocator);
    defer generated_large_map.deinit(allocator);
    var generated_shuffled_large_map = try fixtures.makeGeneratedShuffledLargeMap(allocator);
    defer generated_shuffled_large_map.deinit(allocator);
    var dynamic_large_map = try fixtures.makeDynamicLargeMap(allocator, large_map_desc);
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
    const generated_unknown_bytes = try fixtures.makeUnknownFieldPayload(allocator, generated_bytes, UnknownFieldStressCount);
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
    const generated_text_bytes_json = try generated_text_bytes.jsonStringifyAlloc(allocator);
    defer allocator.free(generated_text_bytes_json);
    std.debug.assert(std.mem.indexOf(u8, generated_text_bytes_json, "\"title\":\"ASCII title for protobuf\"") != null);
    std.debug.assert(std.mem.indexOf(u8, generated_text_bytes_json, "\"payload\":\"MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY=\"") != null);
    std.debug.assert(std.mem.indexOf(u8, generated_text_bytes_json, "\"tags\":[\"alpha\",\"beta\",\"gamma\",\"delta\"]") != null);
    std.debug.assert(std.mem.indexOf(u8, generated_text_bytes_json, "\"chunks\":[\"Y2h1bmstb25l\",\"Y2h1bmstdHdv\",\"Y2h1bmstdGhyZWU=\",\"Y2h1bmstZm91cg==\"]") != null);
    var generated_text_bytes_from_json = try person_pb.demo.TextBytes.jsonParse(allocator, generated_text_bytes_json);
    defer generated_text_bytes_from_json.deinit(allocator);
    std.debug.assert(std.mem.eql(u8, generated_text_bytes_from_json.title, generated_text_bytes.title));
    std.debug.assert(std.mem.eql(u8, generated_text_bytes_from_json.payload, generated_text_bytes.payload));
    std.debug.assert(generated_text_bytes_from_json.tags.len == generated_text_bytes.tags.len);
    std.debug.assert(generated_text_bytes_from_json.chunks.len == generated_text_bytes.chunks.len);
    for (generated_text_bytes.tags, generated_text_bytes_from_json.tags) |expected, actual| std.debug.assert(std.mem.eql(u8, expected, actual));
    for (generated_text_bytes.chunks, generated_text_bytes_from_json.chunks) |expected, actual| std.debug.assert(std.mem.eql(u8, expected, actual));
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
    const generated_presence_mix_json = try generated_presence_mix.jsonStringifyAlloc(allocator);
    defer allocator.free(generated_presence_mix_json);
    std.debug.assert(std.mem.indexOf(u8, generated_presence_mix_json, "\"count\":0") != null);
    std.debug.assert(std.mem.indexOf(u8, generated_presence_mix_json, "\"note\":\"\"") != null);
    std.debug.assert(std.mem.indexOf(u8, generated_presence_mix_json, "\"raw\":\"cHJlc2VuY2UtcmF3\"") != null);
    std.debug.assert(std.mem.indexOf(u8, generated_presence_mix_json, "\"child\":") != null);
    std.debug.assert(std.mem.indexOf(u8, generated_presence_mix_json, "\"nested\":") != null);
    std.debug.assert(std.mem.indexOf(u8, generated_presence_mix_json, "\"name\":") == null);
    var generated_presence_mix_from_json = try person_pb.demo.PresenceMix.jsonParse(allocator, generated_presence_mix_json);
    defer generated_presence_mix_from_json.deinit(allocator);
    std.debug.assert(generated_presence_mix_from_json.has_count and generated_presence_mix_from_json.count == 0);
    std.debug.assert(generated_presence_mix_from_json.has_note and generated_presence_mix_from_json.note.len == 0);
    std.debug.assert(generated_presence_mix_from_json.has_raw and std.mem.eql(u8, generated_presence_mix_from_json.raw, "presence-raw"));
    std.debug.assert(generated_presence_mix_from_json.child != null);
    std.debug.assert(generated_presence_mix_from_json.child.?.id == 7);
    std.debug.assert(std.mem.eql(u8, generated_presence_mix_from_json.child.?.label, "child"));
    std.debug.assert(generated_presence_mix_from_json.pick == .nested);
    std.debug.assert(generated_presence_mix_from_json.pick.nested.id == 11);
    std.debug.assert(std.mem.eql(u8, generated_presence_mix_from_json.pick.nested.label, "nested"));
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
    const generated_complex_proto_name_json = try generated_complex.jsonStringifyAllocWithOptions(allocator, .{ .preserve_proto_field_names = true });
    defer allocator.free(generated_complex_proto_name_json);
    std.debug.assert(std.mem.indexOf(u8, generated_complex_proto_name_json, "\"audit_subject\":") != null);
    std.debug.assert(std.mem.indexOf(u8, generated_complex_proto_name_json, "\"at_unix\":") != null);
    std.debug.assert(std.mem.indexOf(u8, generated_complex_proto_name_json, "\"auditSubject\":") == null);
    std.debug.assert(std.mem.indexOf(u8, generated_complex_proto_name_json, "\"atUnix\":") == null);
    var generated_complex_proto_name_from_json = try person_pb.demo.Complex.jsonParse(allocator, generated_complex_proto_name_json);
    defer generated_complex_proto_name_from_json.deinit(allocator);
    std.debug.assert(generated_complex_proto_name_from_json.subject == .audit_subject);
    std.debug.assert(generated_complex_proto_name_from_json.subject.audit_subject.at_unix == 777);
    std.debug.assert(std.mem.eql(u8, generated_complex_proto_name_from_json.subject.audit_subject.actor, "subject"));
    std.debug.assert(generated_complex_proto_name_from_json.audit != null);
    std.debug.assert(generated_complex_proto_name_from_json.audit.?.at_unix == 12345);
    std.debug.assert((generated_complex_proto_name_from_json.audits.get("latest") orelse return error.MissingAudit).at_unix == 67890);
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
    const generated_large_map_json = try generated_large_map.jsonStringifyAlloc(allocator);
    defer allocator.free(generated_large_map_json);
    std.debug.assert(std.mem.indexOf(u8, generated_large_map_json, "\"key-0000\":1") != null);
    std.debug.assert(std.mem.indexOf(u8, generated_large_map_json, "\"key-1023\":1024") != null);
    var generated_large_map_from_json = try person_pb.demo.LargeMap.jsonParse(allocator, generated_large_map_json);
    defer generated_large_map_from_json.deinit(allocator);
    std.debug.assert(generated_large_map_from_json.counts.count() == generated_large_map.counts.count());
    std.debug.assert(generated_large_map_from_json.counts.get("key-0000").? == 1);
    std.debug.assert(generated_large_map_from_json.counts.get("key-1023").? == 1024);
    const generated_json = try generated_person.jsonStringifyAlloc(allocator);
    defer allocator.free(generated_json);
    var generated_empty_person = person_pb.demo.Person.init();
    defer generated_empty_person.deinit(allocator);
    const generated_always_print_json = try generated_empty_person.jsonStringifyAllocWithOptions(allocator, .{ .always_print_primitive_fields = true });
    defer allocator.free(generated_always_print_json);
    std.debug.assert(std.mem.indexOf(u8, generated_always_print_json, "\"id\":0") != null);
    std.debug.assert(std.mem.indexOf(u8, generated_always_print_json, "\"name\":\"\"") != null);
    std.debug.assert(std.mem.indexOf(u8, generated_always_print_json, "\"scores\":[]") != null);
    std.debug.assert(std.mem.indexOf(u8, generated_always_print_json, "\"counts\":{}") != null);
    const generated_scalar_mix_json = try generated_scalar_mix.jsonStringifyAlloc(allocator);
    defer allocator.free(generated_scalar_mix_json);
    std.debug.assert(std.mem.indexOf(u8, generated_scalar_mix_json, "\"bigDelta\":\"-9876543\"") != null);
    std.debug.assert(std.mem.indexOf(u8, generated_scalar_mix_json, "\"kind\":\"BENCH_KIND_BETA\"") != null);
    var generated_scalar_mix_roundtrip = try person_pb.demo.ScalarMix.jsonParse(allocator, generated_scalar_mix_json);
    defer generated_scalar_mix_roundtrip.deinit(allocator);
    std.debug.assert(generated_scalar_mix_roundtrip.count == generated_scalar_mix.count);
    std.debug.assert(generated_scalar_mix_roundtrip.total == generated_scalar_mix.total);
    std.debug.assert(generated_scalar_mix_roundtrip.big_delta == generated_scalar_mix.big_delta);
    std.debug.assert(generated_scalar_mix_roundtrip.kind == generated_scalar_mix.kind);
    std.debug.assert(std.mem.eql(u64, generated_scalar_mix_roundtrip.ids, generated_scalar_mix.ids));
    const generated_proto_name_json = try generated_scalar_mix.jsonStringifyAllocWithOptions(allocator, .{ .preserve_proto_field_names = true });
    defer allocator.free(generated_proto_name_json);
    std.debug.assert(std.mem.indexOf(u8, generated_proto_name_json, "\"big_delta\":") != null);
    std.debug.assert(std.mem.indexOf(u8, generated_proto_name_json, "\"signed_fixed\":") != null);
    std.debug.assert(std.mem.indexOf(u8, generated_proto_name_json, "\"signed_big_fixed\":") != null);
    std.debug.assert(std.mem.indexOf(u8, generated_proto_name_json, "\"bigDelta\":") == null);
    const generated_enum_number_json = try generated_scalar_mix.jsonStringifyAllocWithOptions(allocator, .{ .enum_as_name = false });
    defer allocator.free(generated_enum_number_json);
    std.debug.assert(std.mem.indexOf(u8, generated_enum_number_json, "\"kind\":2") != null);
    std.debug.assert(std.mem.indexOf(u8, generated_enum_number_json, "BENCH_KIND_BETA") == null);
    var generated_map_key_surrogate = try person_pb.demo.Person.jsonParse(allocator, json.GeneratedMapKeySurrogateJson);
    defer generated_map_key_surrogate.deinit(allocator);
    std.debug.assert(generated_map_key_surrogate.counts.get("😀").? == 9);
    var generated_null_fields = try person_pb.demo.Person.jsonParse(allocator, json.GeneratedNullFieldsJson);
    defer generated_null_fields.deinit(allocator);
    std.debug.assert(generated_null_fields.id == 0);
    std.debug.assert(generated_null_fields.name.len == 0);
    std.debug.assert(generated_null_fields.scores.len == 0);
    std.debug.assert(generated_null_fields.counts.count() == 0);
    var generated_ignore_unknown = try person_pb.demo.Person.jsonParseWithOptions(allocator, json.GeneratedIgnoreUnknownJson, .{ .ignore_unknown_fields = true });
    defer generated_ignore_unknown.deinit(allocator);
    std.debug.assert(generated_ignore_unknown.id == 7);
    std.debug.assert(std.mem.eql(u8, generated_ignore_unknown.name, "zig"));
    std.debug.assert(std.mem.eql(i32, generated_ignore_unknown.scores, &.{3}));
    std.debug.assert(generated_ignore_unknown.counts.get("red").? == 4);
    var generated_open_enum = try person_pb.demo.ScalarMix.jsonParse(allocator, json.GeneratedOpenEnumJson);
    defer generated_open_enum.deinit(allocator);
    std.debug.assert(generated_open_enum.kind == 123);
    var generated_enum_name = try person_pb.demo.ScalarMix.jsonParse(allocator, json.GeneratedEnumNameJson);
    defer generated_enum_name.deinit(allocator);
    std.debug.assert(generated_enum_name.kind == person_pb.demo.BenchKind.BENCH_KIND_BETA.toInt());
    var generated_proto_name = try person_pb.demo.ScalarMix.jsonParse(allocator, json.GeneratedProtoNameJson);
    defer generated_proto_name.deinit(allocator);
    std.debug.assert(generated_proto_name.big_delta == -321);
    std.debug.assert(generated_proto_name.signed_fixed == -123);
    std.debug.assert(generated_proto_name.signed_big_fixed == -456);
    var generated_int_exponent = try person_pb.demo.ScalarMix.jsonParse(allocator, json.GeneratedIntExponentJson);
    defer generated_int_exponent.deinit(allocator);
    std.debug.assert(generated_int_exponent.count == 12345);
    std.debug.assert(generated_int_exponent.total == 9_876_543_210);
    std.debug.assert(generated_int_exponent.delta == -321);
    std.debug.assert(generated_int_exponent.big_delta == -9_876_543);
    std.debug.assert(generated_int_exponent.checksum == 321);
    std.debug.assert(generated_int_exponent.token == 4096);
    std.debug.assert(generated_int_exponent.signed_fixed == -123456);
    std.debug.assert(generated_int_exponent.signed_big_fixed == -9_876_543);
    std.debug.assert(std.mem.eql(u64, generated_int_exponent.ids, &.{ 1, 127, 128 }));
    var generated_string_number = try person_pb.demo.ScalarMix.jsonParse(allocator, json.GeneratedStringNumberJson);
    defer generated_string_number.deinit(allocator);
    std.debug.assert(generated_string_number.count == 12345);
    std.debug.assert(generated_string_number.total == 9_876_543_210);
    std.debug.assert(generated_string_number.delta == -321);
    std.debug.assert(generated_string_number.big_delta == -9_876_543);
    std.debug.assert(generated_string_number.checksum == 321);
    std.debug.assert(generated_string_number.token == 4096);
    std.debug.assert(generated_string_number.signed_fixed == -123456);
    std.debug.assert(generated_string_number.signed_big_fixed == -9_876_543);
    std.debug.assert(std.mem.eql(u64, generated_string_number.ids, &.{ 1, 127, 128 }));
    const dynamic_json = try pbz.stringifyJsonAlloc(allocator, &file, &dynamic_person, .{});
    defer allocator.free(dynamic_json);
    var any_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.Duration", pbz.Duration{ .seconds = 1, .nanos = 500_000_000 });
    defer any_wkt.deinit(allocator);
    const any_wkt_json = try any_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_wkt_json, json.AnyWktJson));
    const duration_value = pbz.Duration{ .seconds = 1, .nanos = 500_000_000 };
    const duration_json = try duration_value.jsonStringifyAlloc(allocator);
    defer allocator.free(duration_json);
    std.debug.assert(std.mem.eql(u8, duration_json, json.DurationJson));
    const duration_escape_value = try pbz.Duration.jsonParse(json.DurationEscapeJson);
    std.debug.assert(duration_escape_value.seconds == duration_value.seconds);
    std.debug.assert(duration_escape_value.nanos == duration_value.nanos);
    var any_duration_escape_wkt = try pbz.Any.jsonParse(allocator, json.AnyDurationEscapeWktJson);
    defer any_duration_escape_wkt.deinit(allocator);
    const any_duration_escape_value = try any_duration_escape_wkt.unpackEncoded(pbz.Duration, allocator, "google.protobuf.Duration");
    std.debug.assert(any_duration_escape_value.seconds == duration_value.seconds);
    std.debug.assert(any_duration_escape_value.nanos == duration_value.nanos);
    const plus_duration_value = try pbz.Duration.jsonParse(json.PlusDurationJson);
    std.debug.assert(plus_duration_value.seconds == duration_value.seconds);
    std.debug.assert(plus_duration_value.nanos == duration_value.nanos);
    var any_plus_duration_wkt = try pbz.Any.jsonParse(allocator, json.AnyPlusDurationWktJson);
    defer any_plus_duration_wkt.deinit(allocator);
    const short_fraction_duration_value = try pbz.Duration.jsonParse(json.ShortFractionDurationJson);
    std.debug.assert(short_fraction_duration_value.seconds == duration_value.seconds);
    std.debug.assert(short_fraction_duration_value.nanos == duration_value.nanos);
    var any_short_fraction_duration_wkt = try pbz.Any.jsonParse(allocator, json.AnyShortFractionDurationWktJson);
    defer any_short_fraction_duration_wkt.deinit(allocator);
    var any_micro_duration_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.Duration", pbz.Duration{ .seconds = 1, .nanos = 120_000 });
    defer any_micro_duration_wkt.deinit(allocator);
    const any_micro_duration_wkt_json = try any_micro_duration_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_micro_duration_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_micro_duration_wkt_json, json.AnyMicroDurationWktJson));
    const micro_duration_value = pbz.Duration{ .seconds = 1, .nanos = 120_000 };
    const micro_duration_json = try micro_duration_value.jsonStringifyAlloc(allocator);
    defer allocator.free(micro_duration_json);
    std.debug.assert(std.mem.eql(u8, micro_duration_json, json.MicroDurationJson));
    var any_nano_duration_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.Duration", pbz.Duration{ .seconds = 1, .nanos = 123_456_789 });
    defer any_nano_duration_wkt.deinit(allocator);
    const any_nano_duration_wkt_json = try any_nano_duration_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_nano_duration_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_nano_duration_wkt_json, json.AnyNanoDurationWktJson));
    const nano_duration_value = pbz.Duration{ .seconds = 1, .nanos = 123_456_789 };
    const nano_duration_json = try nano_duration_value.jsonStringifyAlloc(allocator);
    defer allocator.free(nano_duration_json);
    std.debug.assert(std.mem.eql(u8, nano_duration_json, json.NanoDurationJson));
    var any_negative_duration_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.Duration", pbz.Duration{ .seconds = -1, .nanos = -500_000_000 });
    defer any_negative_duration_wkt.deinit(allocator);
    const any_negative_duration_wkt_json = try any_negative_duration_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_negative_duration_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_negative_duration_wkt_json, json.AnyNegativeDurationWktJson));
    const negative_duration_value = pbz.Duration{ .seconds = -1, .nanos = -500_000_000 };
    const negative_duration_json = try negative_duration_value.jsonStringifyAlloc(allocator);
    defer allocator.free(negative_duration_json);
    std.debug.assert(std.mem.eql(u8, negative_duration_json, json.NegativeDurationJson));
    var any_fractional_negative_duration_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.Duration", pbz.Duration{ .nanos = -250_000_000 });
    defer any_fractional_negative_duration_wkt.deinit(allocator);
    const any_fractional_negative_duration_wkt_json = try any_fractional_negative_duration_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_fractional_negative_duration_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_fractional_negative_duration_wkt_json, json.AnyFractionalNegativeDurationWktJson));
    const fractional_negative_duration_value = pbz.Duration{ .nanos = -250_000_000 };
    const fractional_negative_duration_json = try fractional_negative_duration_value.jsonStringifyAlloc(allocator);
    defer allocator.free(fractional_negative_duration_json);
    std.debug.assert(std.mem.eql(u8, fractional_negative_duration_json, json.FractionalNegativeDurationJson));
    var any_max_duration_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.Duration", pbz.Duration{ .seconds = 315_576_000_000 });
    defer any_max_duration_wkt.deinit(allocator);
    const any_max_duration_wkt_json = try any_max_duration_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_max_duration_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_max_duration_wkt_json, json.AnyMaxDurationWktJson));
    const max_duration_value = pbz.Duration{ .seconds = 315_576_000_000 };
    const max_duration_json = try max_duration_value.jsonStringifyAlloc(allocator);
    defer allocator.free(max_duration_json);
    std.debug.assert(std.mem.eql(u8, max_duration_json, json.MaxDurationJson));
    var any_min_duration_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.Duration", pbz.Duration{ .seconds = -315_576_000_000 });
    defer any_min_duration_wkt.deinit(allocator);
    const any_min_duration_wkt_json = try any_min_duration_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_min_duration_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_min_duration_wkt_json, json.AnyMinDurationWktJson));
    const min_duration_value = pbz.Duration{ .seconds = -315_576_000_000 };
    const min_duration_json = try min_duration_value.jsonStringifyAlloc(allocator);
    defer allocator.free(min_duration_json);
    std.debug.assert(std.mem.eql(u8, min_duration_json, json.MinDurationJson));
    var any_zero_duration_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.Duration", pbz.Duration{});
    defer any_zero_duration_wkt.deinit(allocator);
    const any_zero_duration_wkt_json = try any_zero_duration_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_zero_duration_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_zero_duration_wkt_json, json.AnyZeroDurationWktJson));
    const zero_duration_value = pbz.Duration{};
    const zero_duration_json = try zero_duration_value.jsonStringifyAlloc(allocator);
    defer allocator.free(zero_duration_json);
    std.debug.assert(std.mem.eql(u8, zero_duration_json, json.ZeroDurationJson));
    const field_mask_paths = [_][]const u8{ "foo_bar", "nested.value" };
    const field_mask_value = pbz.FieldMask{ .paths = &field_mask_paths };
    const field_mask_json = try field_mask_value.jsonStringifyAlloc(allocator);
    defer allocator.free(field_mask_json);
    std.debug.assert(std.mem.eql(u8, field_mask_json, json.FieldMaskJson));
    var any_field_mask_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.FieldMask", field_mask_value);
    defer any_field_mask_wkt.deinit(allocator);
    const any_field_mask_wkt_json = try any_field_mask_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_field_mask_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_field_mask_wkt_json, json.AnyFieldMaskWktJson));
    const field_mask_escape_paths = try pbz.FieldMask.jsonParse(allocator, json.FieldMaskEscapeJson);
    defer {
        for (field_mask_escape_paths) |path| allocator.free(path);
        allocator.free(field_mask_escape_paths);
    }
    std.debug.assert(field_mask_escape_paths.len == 2);
    std.debug.assert(std.mem.eql(u8, field_mask_escape_paths[0], "foo_bar"));
    std.debug.assert(std.mem.eql(u8, field_mask_escape_paths[1], "nested.value"));
    var any_field_mask_escape_wkt = try pbz.Any.jsonParse(allocator, json.AnyFieldMaskEscapeWktJson);
    defer any_field_mask_escape_wkt.deinit(allocator);
    var any_field_mask_escape_value = try any_field_mask_escape_wkt.unpackEncodedOwned(pbz.FieldMask, allocator, "google.protobuf.FieldMask");
    defer any_field_mask_escape_value.deinit(allocator);
    std.debug.assert(any_field_mask_escape_value.paths.len == 2);
    std.debug.assert(std.mem.eql(u8, any_field_mask_escape_value.paths[0], "foo_bar"));
    std.debug.assert(std.mem.eql(u8, any_field_mask_escape_value.paths[1], "nested.value"));
    const empty_field_mask_value = pbz.FieldMask{ .paths = &.{} };
    const empty_field_mask_json = try empty_field_mask_value.jsonStringifyAlloc(allocator);
    defer allocator.free(empty_field_mask_json);
    std.debug.assert(std.mem.eql(u8, empty_field_mask_json, json.EmptyFieldMaskJson));
    var any_empty_field_mask_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.FieldMask", empty_field_mask_value);
    defer any_empty_field_mask_wkt.deinit(allocator);
    const any_empty_field_mask_wkt_json = try any_empty_field_mask_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_empty_field_mask_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_empty_field_mask_wkt_json, json.AnyEmptyFieldMaskWktJson));
    const timestamp_value = pbz.Timestamp{ .seconds = 1_577_836_800, .nanos = 123_000_000 };
    const timestamp_json = try timestamp_value.jsonStringifyAlloc(allocator);
    defer allocator.free(timestamp_json);
    std.debug.assert(std.mem.eql(u8, timestamp_json, json.TimestampJson));
    var any_timestamp_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.Timestamp", timestamp_value);
    defer any_timestamp_wkt.deinit(allocator);
    const any_timestamp_wkt_json = try any_timestamp_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_timestamp_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_timestamp_wkt_json, json.AnyTimestampWktJson));
    const timestamp_escape_value = try pbz.Timestamp.jsonParse(json.TimestampEscapeJson);
    std.debug.assert(timestamp_escape_value.seconds == timestamp_value.seconds);
    std.debug.assert(timestamp_escape_value.nanos == timestamp_value.nanos);
    var any_timestamp_escape_wkt = try pbz.Any.jsonParse(allocator, json.AnyTimestampEscapeWktJson);
    defer any_timestamp_escape_wkt.deinit(allocator);
    const any_timestamp_escape_value = try any_timestamp_escape_wkt.unpackEncoded(pbz.Timestamp, allocator, "google.protobuf.Timestamp");
    std.debug.assert(any_timestamp_escape_value.seconds == timestamp_value.seconds);
    std.debug.assert(any_timestamp_escape_value.nanos == timestamp_value.nanos);
    const short_fraction_timestamp_value = try pbz.Timestamp.jsonParse(json.ShortFractionTimestampJson);
    std.debug.assert(short_fraction_timestamp_value.seconds == timestamp_value.seconds);
    std.debug.assert(short_fraction_timestamp_value.nanos == 100_000_000);
    var any_short_fraction_timestamp_wkt = try pbz.Any.jsonParse(allocator, json.AnyShortFractionTimestampWktJson);
    defer any_short_fraction_timestamp_wkt.deinit(allocator);
    const micro_timestamp_value = pbz.Timestamp{ .seconds = 1_577_836_800, .nanos = 123_456_000 };
    const micro_timestamp_json = try micro_timestamp_value.jsonStringifyAlloc(allocator);
    defer allocator.free(micro_timestamp_json);
    std.debug.assert(std.mem.eql(u8, micro_timestamp_json, json.MicroTimestampJson));
    var any_micro_timestamp_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.Timestamp", micro_timestamp_value);
    defer any_micro_timestamp_wkt.deinit(allocator);
    const any_micro_timestamp_wkt_json = try any_micro_timestamp_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_micro_timestamp_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_micro_timestamp_wkt_json, json.AnyMicroTimestampWktJson));
    const nano_timestamp_value = pbz.Timestamp{ .seconds = 1_577_836_800, .nanos = 123_456_789 };
    const nano_timestamp_json = try nano_timestamp_value.jsonStringifyAlloc(allocator);
    defer allocator.free(nano_timestamp_json);
    std.debug.assert(std.mem.eql(u8, nano_timestamp_json, json.NanoTimestampJson));
    var any_nano_timestamp_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.Timestamp", nano_timestamp_value);
    defer any_nano_timestamp_wkt.deinit(allocator);
    const any_nano_timestamp_wkt_json = try any_nano_timestamp_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_nano_timestamp_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_nano_timestamp_wkt_json, json.AnyNanoTimestampWktJson));
    const offset_timestamp_value = try pbz.Timestamp.jsonParse(json.OffsetTimestampJson);
    std.debug.assert(offset_timestamp_value.seconds == micro_timestamp_value.seconds);
    std.debug.assert(offset_timestamp_value.nanos == micro_timestamp_value.nanos);
    var any_offset_timestamp_wkt = try pbz.Any.jsonParse(allocator, json.AnyOffsetTimestampWktJson);
    defer any_offset_timestamp_wkt.deinit(allocator);
    const pre_epoch_timestamp_value = pbz.Timestamp{ .seconds = -1 };
    const pre_epoch_timestamp_json = try pre_epoch_timestamp_value.jsonStringifyAlloc(allocator);
    defer allocator.free(pre_epoch_timestamp_json);
    std.debug.assert(std.mem.eql(u8, pre_epoch_timestamp_json, json.PreEpochTimestampJson));
    var any_pre_epoch_timestamp_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.Timestamp", pre_epoch_timestamp_value);
    defer any_pre_epoch_timestamp_wkt.deinit(allocator);
    const any_pre_epoch_timestamp_wkt_json = try any_pre_epoch_timestamp_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_pre_epoch_timestamp_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_pre_epoch_timestamp_wkt_json, json.AnyPreEpochTimestampWktJson));
    const max_timestamp_value = pbz.Timestamp{ .seconds = 253_402_300_799, .nanos = 999_999_999 };
    const max_timestamp_json = try max_timestamp_value.jsonStringifyAlloc(allocator);
    defer allocator.free(max_timestamp_json);
    std.debug.assert(std.mem.eql(u8, max_timestamp_json, json.MaxTimestampJson));
    var any_max_timestamp_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.Timestamp", max_timestamp_value);
    defer any_max_timestamp_wkt.deinit(allocator);
    const any_max_timestamp_wkt_json = try any_max_timestamp_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_max_timestamp_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_max_timestamp_wkt_json, json.AnyMaxTimestampWktJson));
    const min_timestamp_value = pbz.Timestamp{ .seconds = -62_135_596_800 };
    const min_timestamp_json = try min_timestamp_value.jsonStringifyAlloc(allocator);
    defer allocator.free(min_timestamp_json);
    std.debug.assert(std.mem.eql(u8, min_timestamp_json, json.MinTimestampJson));
    var any_min_timestamp_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.Timestamp", min_timestamp_value);
    defer any_min_timestamp_wkt.deinit(allocator);
    const any_min_timestamp_wkt_json = try any_min_timestamp_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_min_timestamp_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_min_timestamp_wkt_json, json.AnyMinTimestampWktJson));
    var empty_json_out: std.Io.Writer.Allocating = .init(allocator);
    defer empty_json_out.deinit();
    try pbz.Empty.jsonStringify(&empty_json_out.writer);
    const empty_json = empty_json_out.written();
    std.debug.assert(std.mem.eql(u8, empty_json, json.EmptyJson));
    var any_empty_wkt = try pbz.Any.packBytes(allocator, "google.protobuf.Empty", "");
    defer any_empty_wkt.deinit(allocator);
    const any_empty_wkt_json = try any_empty_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_empty_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_empty_wkt_json, json.AnyEmptyWktJson));
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
    std.debug.assert(std.mem.eql(u8, struct_json, json.StructJson));
    var any_struct_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.Struct", struct_value);
    defer any_struct_wkt.deinit(allocator);
    const any_struct_wkt_json = try any_struct_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_struct_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_struct_wkt_json, json.AnyStructWktJson));
    var struct_escape_value = try pbz.Struct.jsonParse(allocator, json.StructEscapeJson);
    defer struct_escape_value.deinit(allocator);
    const struct_escape_json = try struct_escape_value.jsonStringifyAlloc(allocator);
    defer allocator.free(struct_escape_json);
    std.debug.assert(std.mem.eql(u8, struct_escape_json, json.StructJson));
    var any_struct_escape_wkt = try pbz.Any.jsonParse(allocator, json.AnyStructEscapeWktJson);
    defer any_struct_escape_wkt.deinit(allocator);
    var any_struct_escape_value = try any_struct_escape_wkt.unpackEncodedOwned(pbz.Struct, allocator, "google.protobuf.Struct");
    defer any_struct_escape_value.deinit(allocator);
    const any_struct_escape_json = try any_struct_escape_value.jsonStringifyAlloc(allocator);
    defer allocator.free(any_struct_escape_json);
    std.debug.assert(std.mem.eql(u8, any_struct_escape_json, json.StructJson));
    var struct_number_exponent_value = try pbz.Struct.jsonParse(allocator, json.StructNumberExponentJson);
    defer struct_number_exponent_value.deinit(allocator);
    const struct_number_exponent_json = try struct_number_exponent_value.jsonStringifyAlloc(allocator);
    defer allocator.free(struct_number_exponent_json);
    std.debug.assert(std.mem.eql(u8, struct_number_exponent_json, json.StructJson));
    var any_struct_number_exponent_wkt = try pbz.Any.jsonParse(allocator, json.AnyStructNumberExponentWktJson);
    defer any_struct_number_exponent_wkt.deinit(allocator);
    var any_struct_number_exponent_value = try any_struct_number_exponent_wkt.unpackEncodedOwned(pbz.Struct, allocator, "google.protobuf.Struct");
    defer any_struct_number_exponent_value.deinit(allocator);
    const any_struct_number_exponent_json = try any_struct_number_exponent_value.jsonStringifyAlloc(allocator);
    defer allocator.free(any_struct_number_exponent_json);
    std.debug.assert(std.mem.eql(u8, any_struct_number_exponent_json, json.StructJson));
    var struct_surrogate_value = try pbz.Struct.jsonParse(allocator, json.StructSurrogateJson);
    defer struct_surrogate_value.deinit(allocator);
    var any_struct_surrogate_wkt = try pbz.Any.jsonParse(allocator, json.AnyStructSurrogateWktJson);
    defer any_struct_surrogate_wkt.deinit(allocator);
    var struct_key_surrogate_value = try pbz.Struct.jsonParse(allocator, json.StructKeySurrogateJson);
    defer struct_key_surrogate_value.deinit(allocator);
    std.debug.assert(struct_key_surrogate_value.fields.len == 1);
    std.debug.assert(std.mem.eql(u8, struct_key_surrogate_value.fields[0].key, "😀"));
    std.debug.assert(struct_key_surrogate_value.fields[0].value == .string_value);
    std.debug.assert(std.mem.eql(u8, struct_key_surrogate_value.fields[0].value.string_value, "ok"));
    var any_struct_key_surrogate_wkt = try pbz.Any.jsonParse(allocator, json.AnyStructKeySurrogateWktJson);
    defer any_struct_key_surrogate_wkt.deinit(allocator);
    var any_struct_key_surrogate = try any_struct_key_surrogate_wkt.unpackEncodedOwned(pbz.Struct, allocator, "google.protobuf.Struct");
    defer any_struct_key_surrogate.deinit(allocator);
    std.debug.assert(any_struct_key_surrogate.fields.len == 1);
    std.debug.assert(std.mem.eql(u8, any_struct_key_surrogate.fields[0].key, "😀"));
    std.debug.assert(any_struct_key_surrogate.fields[0].value == .string_value);
    std.debug.assert(std.mem.eql(u8, any_struct_key_surrogate.fields[0].value.string_value, "ok"));
    var empty_struct_value = pbz.Struct{ .fields = &.{} };
    const empty_struct_json = try empty_struct_value.jsonStringifyAlloc(allocator);
    defer allocator.free(empty_struct_json);
    std.debug.assert(std.mem.eql(u8, empty_struct_json, json.EmptyStructJson));
    var any_empty_struct_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.Struct", empty_struct_value);
    defer any_empty_struct_wkt.deinit(allocator);
    const any_empty_struct_wkt_json = try any_empty_struct_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_empty_struct_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_empty_struct_wkt_json, json.AnyEmptyStructWktJson));
    const value_value = pbz.Value{ .struct_value = &struct_value };
    const value_json = try value_value.jsonStringifyAlloc(allocator);
    defer allocator.free(value_json);
    std.debug.assert(std.mem.eql(u8, value_json, json.ValueJson));
    var any_value_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.Value", value_value);
    defer any_value_wkt.deinit(allocator);
    const any_value_wkt_json = try any_value_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_value_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_value_wkt_json, json.AnyValueWktJson));
    var value_escape_value = try pbz.Value.jsonParse(allocator, json.ValueEscapeJson);
    defer value_escape_value.deinit(allocator);
    const value_escape_json = try value_escape_value.jsonStringifyAlloc(allocator);
    defer allocator.free(value_escape_json);
    std.debug.assert(std.mem.eql(u8, value_escape_json, json.ValueJson));
    var any_value_escape_wkt = try pbz.Any.jsonParse(allocator, json.AnyValueEscapeWktJson);
    defer any_value_escape_wkt.deinit(allocator);
    var any_value_escape_value = try any_value_escape_wkt.unpackEncodedOwned(pbz.Value, allocator, "google.protobuf.Value");
    defer any_value_escape_value.deinit(allocator);
    const any_value_escape_json = try any_value_escape_value.jsonStringifyAlloc(allocator);
    defer allocator.free(any_value_escape_json);
    std.debug.assert(std.mem.eql(u8, any_value_escape_json, json.ValueJson));
    var value_number_exponent_value = try pbz.Value.jsonParse(allocator, json.ValueNumberExponentJson);
    defer value_number_exponent_value.deinit(allocator);
    const value_number_exponent_json = try value_number_exponent_value.jsonStringifyAlloc(allocator);
    defer allocator.free(value_number_exponent_json);
    std.debug.assert(std.mem.eql(u8, value_number_exponent_json, json.ValueJson));
    var any_value_number_exponent_wkt = try pbz.Any.jsonParse(allocator, json.AnyValueNumberExponentWktJson);
    defer any_value_number_exponent_wkt.deinit(allocator);
    var any_value_number_exponent = try any_value_number_exponent_wkt.unpackEncodedOwned(pbz.Value, allocator, "google.protobuf.Value");
    defer any_value_number_exponent.deinit(allocator);
    const any_value_number_exponent_json = try any_value_number_exponent.jsonStringifyAlloc(allocator);
    defer allocator.free(any_value_number_exponent_json);
    std.debug.assert(std.mem.eql(u8, any_value_number_exponent_json, json.ValueJson));
    var value_surrogate_value = try pbz.Value.jsonParse(allocator, json.ValueSurrogateJson);
    defer value_surrogate_value.deinit(allocator);
    var any_value_surrogate_wkt = try pbz.Any.jsonParse(allocator, json.AnyValueSurrogateWktJson);
    defer any_value_surrogate_wkt.deinit(allocator);
    var value_key_surrogate_value = try pbz.Value.jsonParse(allocator, json.ValueKeySurrogateJson);
    defer value_key_surrogate_value.deinit(allocator);
    std.debug.assert(value_key_surrogate_value == .struct_value);
    std.debug.assert(value_key_surrogate_value.struct_value.fields.len == 1);
    std.debug.assert(std.mem.eql(u8, value_key_surrogate_value.struct_value.fields[0].key, "😀"));
    std.debug.assert(value_key_surrogate_value.struct_value.fields[0].value == .string_value);
    std.debug.assert(std.mem.eql(u8, value_key_surrogate_value.struct_value.fields[0].value.string_value, "ok"));
    var any_value_key_surrogate_wkt = try pbz.Any.jsonParse(allocator, json.AnyValueKeySurrogateWktJson);
    defer any_value_key_surrogate_wkt.deinit(allocator);
    var any_value_key_surrogate = try any_value_key_surrogate_wkt.unpackEncodedOwned(pbz.Value, allocator, "google.protobuf.Value");
    defer any_value_key_surrogate.deinit(allocator);
    std.debug.assert(any_value_key_surrogate == .struct_value);
    std.debug.assert(any_value_key_surrogate.struct_value.fields.len == 1);
    std.debug.assert(std.mem.eql(u8, any_value_key_surrogate.struct_value.fields[0].key, "😀"));
    std.debug.assert(any_value_key_surrogate.struct_value.fields[0].value == .string_value);
    std.debug.assert(std.mem.eql(u8, any_value_key_surrogate.struct_value.fields[0].value.string_value, "ok"));
    const null_value_value = pbz.Value{ .null_value = {} };
    const null_value_json = try null_value_value.jsonStringifyAlloc(allocator);
    defer allocator.free(null_value_json);
    std.debug.assert(std.mem.eql(u8, null_value_json, json.NullValueJson));
    var any_null_value_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.Value", null_value_value);
    defer any_null_value_wkt.deinit(allocator);
    const any_null_value_wkt_json = try any_null_value_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_null_value_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_null_value_wkt_json, json.AnyNullValueWktJson));
    const string_scalar_value = pbz.Value{ .string_value = "zig" };
    const string_scalar_value_json = try string_scalar_value.jsonStringifyAlloc(allocator);
    defer allocator.free(string_scalar_value_json);
    std.debug.assert(std.mem.eql(u8, string_scalar_value_json, json.StringScalarValueJson));
    var any_string_scalar_value_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.Value", string_scalar_value);
    defer any_string_scalar_value_wkt.deinit(allocator);
    const any_string_scalar_value_wkt_json = try any_string_scalar_value_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_string_scalar_value_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_string_scalar_value_wkt_json, json.AnyStringScalarValueWktJson));
    var string_scalar_value_escape = try pbz.Value.jsonParse(allocator, json.StringScalarValueEscapeJson);
    defer string_scalar_value_escape.deinit(allocator);
    std.debug.assert(string_scalar_value_escape == .string_value);
    std.debug.assert(std.mem.eql(u8, string_scalar_value_escape.string_value, "zig"));
    var any_string_scalar_value_escape_wkt = try pbz.Any.jsonParse(allocator, json.AnyStringScalarValueEscapeWktJson);
    defer any_string_scalar_value_escape_wkt.deinit(allocator);
    var any_string_scalar_value_escape = try any_string_scalar_value_escape_wkt.unpackEncodedOwned(pbz.Value, allocator, "google.protobuf.Value");
    defer any_string_scalar_value_escape.deinit(allocator);
    std.debug.assert(any_string_scalar_value_escape == .string_value);
    std.debug.assert(std.mem.eql(u8, any_string_scalar_value_escape.string_value, "zig"));
    var string_scalar_value_surrogate = try pbz.Value.jsonParse(allocator, json.StringScalarValueSurrogateJson);
    defer string_scalar_value_surrogate.deinit(allocator);
    std.debug.assert(string_scalar_value_surrogate == .string_value);
    std.debug.assert(std.mem.eql(u8, string_scalar_value_surrogate.string_value, "😀"));
    var any_string_scalar_value_surrogate_wkt = try pbz.Any.jsonParse(allocator, json.AnyStringScalarValueSurrogateWktJson);
    defer any_string_scalar_value_surrogate_wkt.deinit(allocator);
    const empty_string_scalar_value = pbz.Value{ .string_value = "" };
    const empty_string_scalar_value_json = try empty_string_scalar_value.jsonStringifyAlloc(allocator);
    defer allocator.free(empty_string_scalar_value_json);
    std.debug.assert(std.mem.eql(u8, empty_string_scalar_value_json, json.EmptyStringScalarValueJson));
    var any_empty_string_scalar_value_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.Value", empty_string_scalar_value);
    defer any_empty_string_scalar_value_wkt.deinit(allocator);
    const any_empty_string_scalar_value_wkt_json = try any_empty_string_scalar_value_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_empty_string_scalar_value_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_empty_string_scalar_value_wkt_json, json.AnyEmptyStringScalarValueWktJson));
    const number_value = pbz.Value{ .number_value = 1.5 };
    const number_value_json = try number_value.jsonStringifyAlloc(allocator);
    defer allocator.free(number_value_json);
    std.debug.assert(std.mem.eql(u8, number_value_json, json.NumberValueJson));
    var any_number_value_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.Value", number_value);
    defer any_number_value_wkt.deinit(allocator);
    const any_number_value_wkt_json = try any_number_value_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_number_value_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_number_value_wkt_json, json.AnyNumberValueWktJson));
    var number_value_exponent = try pbz.Value.jsonParse(allocator, json.NumberValueExponentJson);
    defer number_value_exponent.deinit(allocator);
    std.debug.assert(number_value_exponent == .number_value);
    std.debug.assert(number_value_exponent.number_value == 1.5);
    var any_number_value_exponent_wkt = try pbz.Any.jsonParse(allocator, json.AnyNumberValueExponentWktJson);
    defer any_number_value_exponent_wkt.deinit(allocator);
    var any_number_value_exponent = try any_number_value_exponent_wkt.unpackEncodedOwned(pbz.Value, allocator, "google.protobuf.Value");
    defer any_number_value_exponent.deinit(allocator);
    std.debug.assert(any_number_value_exponent == .number_value);
    std.debug.assert(any_number_value_exponent.number_value == 1.5);
    const negative_number_value = pbz.Value{ .number_value = -1.5 };
    const negative_number_value_json = try negative_number_value.jsonStringifyAlloc(allocator);
    defer allocator.free(negative_number_value_json);
    std.debug.assert(std.mem.eql(u8, negative_number_value_json, json.NegativeNumberValueJson));
    var any_negative_number_value_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.Value", negative_number_value);
    defer any_negative_number_value_wkt.deinit(allocator);
    const any_negative_number_value_wkt_json = try any_negative_number_value_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_negative_number_value_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_negative_number_value_wkt_json, json.AnyNegativeNumberValueWktJson));
    const zero_number_value = pbz.Value{ .number_value = 0 };
    const zero_number_value_json = try zero_number_value.jsonStringifyAlloc(allocator);
    defer allocator.free(zero_number_value_json);
    std.debug.assert(std.mem.eql(u8, zero_number_value_json, json.ZeroNumberValueJson));
    var any_zero_number_value_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.Value", zero_number_value);
    defer any_zero_number_value_wkt.deinit(allocator);
    const any_zero_number_value_wkt_json = try any_zero_number_value_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_zero_number_value_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_zero_number_value_wkt_json, json.AnyZeroNumberValueWktJson));
    const bool_scalar_value = pbz.Value{ .bool_value = true };
    const bool_scalar_value_json = try bool_scalar_value.jsonStringifyAlloc(allocator);
    defer allocator.free(bool_scalar_value_json);
    std.debug.assert(std.mem.eql(u8, bool_scalar_value_json, json.BoolScalarValueJson));
    var any_bool_scalar_value_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.Value", bool_scalar_value);
    defer any_bool_scalar_value_wkt.deinit(allocator);
    const any_bool_scalar_value_wkt_json = try any_bool_scalar_value_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_bool_scalar_value_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_bool_scalar_value_wkt_json, json.AnyBoolScalarValueWktJson));
    const false_bool_scalar_value = pbz.Value{ .bool_value = false };
    const false_bool_scalar_value_json = try false_bool_scalar_value.jsonStringifyAlloc(allocator);
    defer allocator.free(false_bool_scalar_value_json);
    std.debug.assert(std.mem.eql(u8, false_bool_scalar_value_json, json.FalseBoolScalarValueJson));
    var any_false_bool_scalar_value_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.Value", false_bool_scalar_value);
    defer any_false_bool_scalar_value_wkt.deinit(allocator);
    const any_false_bool_scalar_value_wkt_json = try any_false_bool_scalar_value_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_false_bool_scalar_value_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_false_bool_scalar_value_wkt_json, json.AnyFalseBoolScalarValueWktJson));
    const list_nested_fields = [_]pbz.Struct.Field{.{ .key = "nested", .value = .{ .string_value = "value" } }};
    var list_nested = pbz.Struct{ .fields = &list_nested_fields };
    const list_values = [_]pbz.Value{
        .null_value,
        .{ .string_value = "zig" },
        .{ .number_value = 1.5 },
        .{ .bool_value = true },
        .{ .struct_value = &list_nested },
    };
    var list_value = pbz.ListValue{ .values = &list_values };
    const list_value_json = try list_value.jsonStringifyAlloc(allocator);
    defer allocator.free(list_value_json);
    std.debug.assert(std.mem.eql(u8, list_value_json, json.ListValueJson));
    const list_kind_value = pbz.Value{ .list_value = &list_value };
    const list_kind_value_json = try list_kind_value.jsonStringifyAlloc(allocator);
    defer allocator.free(list_kind_value_json);
    std.debug.assert(std.mem.eql(u8, list_kind_value_json, json.ListKindValueJson));
    var any_list_kind_value_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.Value", list_kind_value);
    defer any_list_kind_value_wkt.deinit(allocator);
    const any_list_kind_value_wkt_json = try any_list_kind_value_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_list_kind_value_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_list_kind_value_wkt_json, json.AnyListKindValueWktJson));
    var list_value_escape = try pbz.ListValue.jsonParse(allocator, json.ListValueEscapeJson);
    defer list_value_escape.deinit(allocator);
    const list_value_escape_json = try list_value_escape.jsonStringifyAlloc(allocator);
    defer allocator.free(list_value_escape_json);
    std.debug.assert(std.mem.eql(u8, list_value_escape_json, json.ListValueJson));
    var list_kind_value_escape = try pbz.Value.jsonParse(allocator, json.ListKindValueEscapeJson);
    defer list_kind_value_escape.deinit(allocator);
    const list_kind_value_escape_json = try list_kind_value_escape.jsonStringifyAlloc(allocator);
    defer allocator.free(list_kind_value_escape_json);
    std.debug.assert(std.mem.eql(u8, list_kind_value_escape_json, json.ListKindValueJson));
    var any_list_kind_value_escape_wkt = try pbz.Any.jsonParse(allocator, json.AnyListKindValueEscapeWktJson);
    defer any_list_kind_value_escape_wkt.deinit(allocator);
    var any_list_kind_value_escape = try any_list_kind_value_escape_wkt.unpackEncodedOwned(pbz.Value, allocator, "google.protobuf.Value");
    defer any_list_kind_value_escape.deinit(allocator);
    const any_list_kind_value_escape_json = try any_list_kind_value_escape.jsonStringifyAlloc(allocator);
    defer allocator.free(any_list_kind_value_escape_json);
    std.debug.assert(std.mem.eql(u8, any_list_kind_value_escape_json, json.ListKindValueJson));
    var list_value_surrogate = try pbz.ListValue.jsonParse(allocator, json.ListValueSurrogateJson);
    defer list_value_surrogate.deinit(allocator);
    std.debug.assert(list_value_surrogate.values.len == 1);
    std.debug.assert(list_value_surrogate.values[0] == .string_value);
    std.debug.assert(std.mem.eql(u8, list_value_surrogate.values[0].string_value, "😀"));
    var list_kind_value_surrogate = try pbz.Value.jsonParse(allocator, json.ListKindValueSurrogateJson);
    defer list_kind_value_surrogate.deinit(allocator);
    std.debug.assert(list_kind_value_surrogate == .list_value);
    std.debug.assert(list_kind_value_surrogate.list_value.values.len == 1);
    std.debug.assert(list_kind_value_surrogate.list_value.values[0] == .string_value);
    std.debug.assert(std.mem.eql(u8, list_kind_value_surrogate.list_value.values[0].string_value, "😀"));
    var any_list_kind_value_surrogate_wkt = try pbz.Any.jsonParse(allocator, json.AnyListKindValueSurrogateWktJson);
    defer any_list_kind_value_surrogate_wkt.deinit(allocator);
    var any_list_kind_value_surrogate = try any_list_kind_value_surrogate_wkt.unpackEncodedOwned(pbz.Value, allocator, "google.protobuf.Value");
    defer any_list_kind_value_surrogate.deinit(allocator);
    std.debug.assert(any_list_kind_value_surrogate == .list_value);
    std.debug.assert(any_list_kind_value_surrogate.list_value.values.len == 1);
    std.debug.assert(any_list_kind_value_surrogate.list_value.values[0] == .string_value);
    std.debug.assert(std.mem.eql(u8, any_list_kind_value_surrogate.list_value.values[0].string_value, "😀"));
    const empty_struct_kind_value = pbz.Value{ .struct_value = &empty_struct_value };
    const empty_struct_kind_value_json = try empty_struct_kind_value.jsonStringifyAlloc(allocator);
    defer allocator.free(empty_struct_kind_value_json);
    std.debug.assert(std.mem.eql(u8, empty_struct_kind_value_json, json.EmptyStructKindValueJson));
    var any_empty_struct_kind_value_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.Value", empty_struct_kind_value);
    defer any_empty_struct_kind_value_wkt.deinit(allocator);
    const any_empty_struct_kind_value_wkt_json = try any_empty_struct_kind_value_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_empty_struct_kind_value_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_empty_struct_kind_value_wkt_json, json.AnyEmptyStructKindValueWktJson));
    var empty_list_value = pbz.ListValue{ .values = &.{} };
    const empty_list_value_json = try empty_list_value.jsonStringifyAlloc(allocator);
    defer allocator.free(empty_list_value_json);
    std.debug.assert(std.mem.eql(u8, empty_list_value_json, json.EmptyListValueJson));
    const empty_list_kind_value = pbz.Value{ .list_value = &empty_list_value };
    const empty_list_kind_value_json = try empty_list_kind_value.jsonStringifyAlloc(allocator);
    defer allocator.free(empty_list_kind_value_json);
    std.debug.assert(std.mem.eql(u8, empty_list_kind_value_json, json.EmptyListKindValueJson));
    var any_empty_list_kind_value_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.Value", empty_list_kind_value);
    defer any_empty_list_kind_value_wkt.deinit(allocator);
    const any_empty_list_kind_value_wkt_json = try any_empty_list_kind_value_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_empty_list_kind_value_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_empty_list_kind_value_wkt_json, json.AnyEmptyListKindValueWktJson));
    const double_value = pbz.DoubleValue{ .value = 3.25 };
    const double_value_json = try double_value.jsonStringifyAlloc(allocator);
    defer allocator.free(double_value_json);
    std.debug.assert(std.mem.eql(u8, double_value_json, json.DoubleValueJson));
    var any_double_value_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.DoubleValue", double_value);
    defer any_double_value_wkt.deinit(allocator);
    const any_double_value_wkt_json = try any_double_value_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_double_value_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_double_value_wkt_json, json.AnyDoubleValueWktJson));
    const double_value_string = try pbz.DoubleValue.jsonParse(allocator, json.DoubleValueStringJson);
    std.debug.assert(double_value_string.value == double_value.value);
    var any_double_value_string_wkt = try pbz.Any.jsonParse(allocator, json.AnyDoubleValueStringWktJson);
    defer any_double_value_string_wkt.deinit(allocator);
    const double_value_exponent = try pbz.DoubleValue.jsonParse(allocator, json.DoubleValueExponentJson);
    std.debug.assert(double_value_exponent.value == double_value.value);
    var any_double_value_exponent_wkt = try pbz.Any.jsonParse(allocator, json.AnyDoubleValueExponentWktJson);
    defer any_double_value_exponent_wkt.deinit(allocator);
    const negative_double_value = pbz.DoubleValue{ .value = -3.25 };
    const negative_double_value_json = try negative_double_value.jsonStringifyAlloc(allocator);
    defer allocator.free(negative_double_value_json);
    std.debug.assert(std.mem.eql(u8, negative_double_value_json, json.NegativeDoubleValueJson));
    var any_negative_double_value_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.DoubleValue", negative_double_value);
    defer any_negative_double_value_wkt.deinit(allocator);
    const any_negative_double_value_wkt_json = try any_negative_double_value_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_negative_double_value_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_negative_double_value_wkt_json, json.AnyNegativeDoubleValueWktJson));
    const zero_double_value = pbz.DoubleValue{ .value = 0 };
    const zero_double_value_json = try zero_double_value.jsonStringifyAlloc(allocator);
    defer allocator.free(zero_double_value_json);
    std.debug.assert(std.mem.eql(u8, zero_double_value_json, json.ZeroDoubleValueJson));
    var any_zero_double_value_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.DoubleValue", zero_double_value);
    defer any_zero_double_value_wkt.deinit(allocator);
    const any_zero_double_value_wkt_json = try any_zero_double_value_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_zero_double_value_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_zero_double_value_wkt_json, json.AnyZeroDoubleValueWktJson));
    const double_value_nan = pbz.DoubleValue{ .value = std.math.nan(f64) };
    const double_value_nan_json = try double_value_nan.jsonStringifyAlloc(allocator);
    defer allocator.free(double_value_nan_json);
    std.debug.assert(std.mem.eql(u8, double_value_nan_json, json.DoubleValueNanJson));
    var any_double_value_nan_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.DoubleValue", double_value_nan);
    defer any_double_value_nan_wkt.deinit(allocator);
    const any_double_value_nan_wkt_json = try any_double_value_nan_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_double_value_nan_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_double_value_nan_wkt_json, json.AnyDoubleValueNanWktJson));
    const double_value_inf = pbz.DoubleValue{ .value = std.math.inf(f64) };
    const double_value_inf_json = try double_value_inf.jsonStringifyAlloc(allocator);
    defer allocator.free(double_value_inf_json);
    std.debug.assert(std.mem.eql(u8, double_value_inf_json, json.DoubleValueInfJson));
    var any_double_value_inf_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.DoubleValue", double_value_inf);
    defer any_double_value_inf_wkt.deinit(allocator);
    const any_double_value_inf_wkt_json = try any_double_value_inf_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_double_value_inf_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_double_value_inf_wkt_json, json.AnyDoubleValueInfWktJson));
    const double_value_neg_inf = pbz.DoubleValue{ .value = -std.math.inf(f64) };
    const double_value_neg_inf_json = try double_value_neg_inf.jsonStringifyAlloc(allocator);
    defer allocator.free(double_value_neg_inf_json);
    std.debug.assert(std.mem.eql(u8, double_value_neg_inf_json, json.DoubleValueNegInfJson));
    var any_double_value_neg_inf_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.DoubleValue", double_value_neg_inf);
    defer any_double_value_neg_inf_wkt.deinit(allocator);
    const any_double_value_neg_inf_wkt_json = try any_double_value_neg_inf_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_double_value_neg_inf_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_double_value_neg_inf_wkt_json, json.AnyDoubleValueNegInfWktJson));
    const float_value = pbz.FloatValue{ .value = 1.5 };
    const float_value_json = try float_value.jsonStringifyAlloc(allocator);
    defer allocator.free(float_value_json);
    std.debug.assert(std.mem.eql(u8, float_value_json, json.FloatValueJson));
    var any_float_value_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.FloatValue", float_value);
    defer any_float_value_wkt.deinit(allocator);
    const any_float_value_wkt_json = try any_float_value_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_float_value_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_float_value_wkt_json, json.AnyFloatValueWktJson));
    const float_value_string = try pbz.FloatValue.jsonParse(allocator, json.FloatValueStringJson);
    std.debug.assert(float_value_string.value == float_value.value);
    var any_float_value_string_wkt = try pbz.Any.jsonParse(allocator, json.AnyFloatValueStringWktJson);
    defer any_float_value_string_wkt.deinit(allocator);
    const float_value_exponent = try pbz.FloatValue.jsonParse(allocator, json.FloatValueExponentJson);
    std.debug.assert(float_value_exponent.value == float_value.value);
    var any_float_value_exponent_wkt = try pbz.Any.jsonParse(allocator, json.AnyFloatValueExponentWktJson);
    defer any_float_value_exponent_wkt.deinit(allocator);
    const negative_float_value = pbz.FloatValue{ .value = -1.5 };
    const negative_float_value_json = try negative_float_value.jsonStringifyAlloc(allocator);
    defer allocator.free(negative_float_value_json);
    std.debug.assert(std.mem.eql(u8, negative_float_value_json, json.NegativeFloatValueJson));
    var any_negative_float_value_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.FloatValue", negative_float_value);
    defer any_negative_float_value_wkt.deinit(allocator);
    const any_negative_float_value_wkt_json = try any_negative_float_value_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_negative_float_value_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_negative_float_value_wkt_json, json.AnyNegativeFloatValueWktJson));
    const zero_float_value = pbz.FloatValue{ .value = 0 };
    const zero_float_value_json = try zero_float_value.jsonStringifyAlloc(allocator);
    defer allocator.free(zero_float_value_json);
    std.debug.assert(std.mem.eql(u8, zero_float_value_json, json.ZeroFloatValueJson));
    var any_zero_float_value_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.FloatValue", zero_float_value);
    defer any_zero_float_value_wkt.deinit(allocator);
    const any_zero_float_value_wkt_json = try any_zero_float_value_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_zero_float_value_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_zero_float_value_wkt_json, json.AnyZeroFloatValueWktJson));
    const float_value_nan = pbz.FloatValue{ .value = std.math.nan(f32) };
    const float_value_nan_json = try float_value_nan.jsonStringifyAlloc(allocator);
    defer allocator.free(float_value_nan_json);
    std.debug.assert(std.mem.eql(u8, float_value_nan_json, json.FloatValueNanJson));
    var any_float_value_nan_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.FloatValue", float_value_nan);
    defer any_float_value_nan_wkt.deinit(allocator);
    const any_float_value_nan_wkt_json = try any_float_value_nan_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_float_value_nan_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_float_value_nan_wkt_json, json.AnyFloatValueNanWktJson));
    const float_value_inf = pbz.FloatValue{ .value = std.math.inf(f32) };
    const float_value_inf_json = try float_value_inf.jsonStringifyAlloc(allocator);
    defer allocator.free(float_value_inf_json);
    std.debug.assert(std.mem.eql(u8, float_value_inf_json, json.FloatValueInfJson));
    var any_float_value_inf_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.FloatValue", float_value_inf);
    defer any_float_value_inf_wkt.deinit(allocator);
    const any_float_value_inf_wkt_json = try any_float_value_inf_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_float_value_inf_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_float_value_inf_wkt_json, json.AnyFloatValueInfWktJson));
    const float_value_neg_inf = pbz.FloatValue{ .value = -std.math.inf(f32) };
    const float_value_neg_inf_json = try float_value_neg_inf.jsonStringifyAlloc(allocator);
    defer allocator.free(float_value_neg_inf_json);
    std.debug.assert(std.mem.eql(u8, float_value_neg_inf_json, json.FloatValueNegInfJson));
    var any_float_value_neg_inf_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.FloatValue", float_value_neg_inf);
    defer any_float_value_neg_inf_wkt.deinit(allocator);
    const any_float_value_neg_inf_wkt_json = try any_float_value_neg_inf_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_float_value_neg_inf_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_float_value_neg_inf_wkt_json, json.AnyFloatValueNegInfWktJson));
    const int64_value = pbz.Int64Value{ .value = 9007199254740993 };
    const int64_value_json = try int64_value.jsonStringifyAlloc(allocator);
    defer allocator.free(int64_value_json);
    std.debug.assert(std.mem.eql(u8, int64_value_json, json.Int64ValueJson));
    var any_int64_value_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.Int64Value", int64_value);
    defer any_int64_value_wkt.deinit(allocator);
    const any_int64_value_wkt_json = try any_int64_value_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_int64_value_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_int64_value_wkt_json, json.AnyInt64ValueWktJson));
    const int64_value_number = try pbz.Int64Value.jsonParse(allocator, json.Int64ValueNumberJson);
    std.debug.assert(int64_value_number.value == int64_value.value);
    var any_int64_value_number_wkt = try pbz.Any.jsonParse(allocator, json.AnyInt64ValueNumberWktJson);
    defer any_int64_value_number_wkt.deinit(allocator);
    const int64_value_exponent = try pbz.Int64Value.jsonParse(allocator, json.Int64ValueExponentJson);
    std.debug.assert(int64_value_exponent.value == 12345);
    var any_int64_value_exponent_wkt = try pbz.Any.jsonParse(allocator, json.AnyInt64ValueExponentWktJson);
    defer any_int64_value_exponent_wkt.deinit(allocator);
    const zero_int64_value = pbz.Int64Value{ .value = 0 };
    const zero_int64_value_json = try zero_int64_value.jsonStringifyAlloc(allocator);
    defer allocator.free(zero_int64_value_json);
    std.debug.assert(std.mem.eql(u8, zero_int64_value_json, json.ZeroInt64ValueJson));
    var any_zero_int64_value_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.Int64Value", zero_int64_value);
    defer any_zero_int64_value_wkt.deinit(allocator);
    const any_zero_int64_value_wkt_json = try any_zero_int64_value_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_zero_int64_value_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_zero_int64_value_wkt_json, json.AnyZeroInt64ValueWktJson));
    const negative_int64_value = pbz.Int64Value{ .value = -9007199254740993 };
    const negative_int64_value_json = try negative_int64_value.jsonStringifyAlloc(allocator);
    defer allocator.free(negative_int64_value_json);
    std.debug.assert(std.mem.eql(u8, negative_int64_value_json, json.NegativeInt64ValueJson));
    var any_negative_int64_value_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.Int64Value", negative_int64_value);
    defer any_negative_int64_value_wkt.deinit(allocator);
    const any_negative_int64_value_wkt_json = try any_negative_int64_value_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_negative_int64_value_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_negative_int64_value_wkt_json, json.AnyNegativeInt64ValueWktJson));
    const min_int64_value = pbz.Int64Value{ .value = std.math.minInt(i64) };
    const min_int64_value_json = try min_int64_value.jsonStringifyAlloc(allocator);
    defer allocator.free(min_int64_value_json);
    std.debug.assert(std.mem.eql(u8, min_int64_value_json, json.MinInt64ValueJson));
    var any_min_int64_value_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.Int64Value", min_int64_value);
    defer any_min_int64_value_wkt.deinit(allocator);
    const any_min_int64_value_wkt_json = try any_min_int64_value_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_min_int64_value_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_min_int64_value_wkt_json, json.AnyMinInt64ValueWktJson));
    const max_int64_value = pbz.Int64Value{ .value = std.math.maxInt(i64) };
    const max_int64_value_json = try max_int64_value.jsonStringifyAlloc(allocator);
    defer allocator.free(max_int64_value_json);
    std.debug.assert(std.mem.eql(u8, max_int64_value_json, json.MaxInt64ValueJson));
    var any_max_int64_value_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.Int64Value", max_int64_value);
    defer any_max_int64_value_wkt.deinit(allocator);
    const any_max_int64_value_wkt_json = try any_max_int64_value_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_max_int64_value_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_max_int64_value_wkt_json, json.AnyMaxInt64ValueWktJson));
    const uint64_value = pbz.UInt64Value{ .value = 9007199254740993 };
    const uint64_value_json = try uint64_value.jsonStringifyAlloc(allocator);
    defer allocator.free(uint64_value_json);
    std.debug.assert(std.mem.eql(u8, uint64_value_json, json.UInt64ValueJson));
    var any_uint64_value_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.UInt64Value", uint64_value);
    defer any_uint64_value_wkt.deinit(allocator);
    const any_uint64_value_wkt_json = try any_uint64_value_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_uint64_value_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_uint64_value_wkt_json, json.AnyUInt64ValueWktJson));
    const uint64_value_number = try pbz.UInt64Value.jsonParse(allocator, json.UInt64ValueNumberJson);
    std.debug.assert(uint64_value_number.value == uint64_value.value);
    var any_uint64_value_number_wkt = try pbz.Any.jsonParse(allocator, json.AnyUInt64ValueNumberWktJson);
    defer any_uint64_value_number_wkt.deinit(allocator);
    const uint64_value_exponent = try pbz.UInt64Value.jsonParse(allocator, json.UInt64ValueExponentJson);
    std.debug.assert(uint64_value_exponent.value == 12345);
    var any_uint64_value_exponent_wkt = try pbz.Any.jsonParse(allocator, json.AnyUInt64ValueExponentWktJson);
    defer any_uint64_value_exponent_wkt.deinit(allocator);
    const zero_uint64_value = pbz.UInt64Value{ .value = 0 };
    const zero_uint64_value_json = try zero_uint64_value.jsonStringifyAlloc(allocator);
    defer allocator.free(zero_uint64_value_json);
    std.debug.assert(std.mem.eql(u8, zero_uint64_value_json, json.ZeroUInt64ValueJson));
    var any_zero_uint64_value_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.UInt64Value", zero_uint64_value);
    defer any_zero_uint64_value_wkt.deinit(allocator);
    const any_zero_uint64_value_wkt_json = try any_zero_uint64_value_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_zero_uint64_value_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_zero_uint64_value_wkt_json, json.AnyZeroUInt64ValueWktJson));
    const max_uint64_value = pbz.UInt64Value{ .value = std.math.maxInt(u64) };
    const max_uint64_value_json = try max_uint64_value.jsonStringifyAlloc(allocator);
    defer allocator.free(max_uint64_value_json);
    std.debug.assert(std.mem.eql(u8, max_uint64_value_json, json.MaxUInt64ValueJson));
    var any_max_uint64_value_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.UInt64Value", max_uint64_value);
    defer any_max_uint64_value_wkt.deinit(allocator);
    const any_max_uint64_value_wkt_json = try any_max_uint64_value_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_max_uint64_value_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_max_uint64_value_wkt_json, json.AnyMaxUInt64ValueWktJson));
    const int32_value = pbz.Int32Value{ .value = 12345 };
    const int32_value_json = try int32_value.jsonStringifyAlloc(allocator);
    defer allocator.free(int32_value_json);
    std.debug.assert(std.mem.eql(u8, int32_value_json, json.Int32ValueJson));
    var any_int32_value_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.Int32Value", int32_value);
    defer any_int32_value_wkt.deinit(allocator);
    const any_int32_value_wkt_json = try any_int32_value_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_int32_value_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_int32_value_wkt_json, json.AnyInt32ValueWktJson));
    const int32_value_string = try pbz.Int32Value.jsonParse(allocator, json.Int32ValueStringJson);
    std.debug.assert(int32_value_string.value == int32_value.value);
    var any_int32_value_string_wkt = try pbz.Any.jsonParse(allocator, json.AnyInt32ValueStringWktJson);
    defer any_int32_value_string_wkt.deinit(allocator);
    const int32_value_exponent = try pbz.Int32Value.jsonParse(allocator, json.Int32ValueExponentJson);
    std.debug.assert(int32_value_exponent.value == int32_value.value);
    var any_int32_value_exponent_wkt = try pbz.Any.jsonParse(allocator, json.AnyInt32ValueExponentWktJson);
    defer any_int32_value_exponent_wkt.deinit(allocator);
    const zero_int32_value = pbz.Int32Value{ .value = 0 };
    const zero_int32_value_json = try zero_int32_value.jsonStringifyAlloc(allocator);
    defer allocator.free(zero_int32_value_json);
    std.debug.assert(std.mem.eql(u8, zero_int32_value_json, json.ZeroInt32ValueJson));
    var any_zero_int32_value_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.Int32Value", zero_int32_value);
    defer any_zero_int32_value_wkt.deinit(allocator);
    const any_zero_int32_value_wkt_json = try any_zero_int32_value_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_zero_int32_value_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_zero_int32_value_wkt_json, json.AnyZeroInt32ValueWktJson));
    const negative_int32_value = pbz.Int32Value{ .value = -12345 };
    const negative_int32_value_json = try negative_int32_value.jsonStringifyAlloc(allocator);
    defer allocator.free(negative_int32_value_json);
    std.debug.assert(std.mem.eql(u8, negative_int32_value_json, json.NegativeInt32ValueJson));
    var any_negative_int32_value_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.Int32Value", negative_int32_value);
    defer any_negative_int32_value_wkt.deinit(allocator);
    const any_negative_int32_value_wkt_json = try any_negative_int32_value_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_negative_int32_value_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_negative_int32_value_wkt_json, json.AnyNegativeInt32ValueWktJson));
    const min_int32_value = pbz.Int32Value{ .value = std.math.minInt(i32) };
    const min_int32_value_json = try min_int32_value.jsonStringifyAlloc(allocator);
    defer allocator.free(min_int32_value_json);
    std.debug.assert(std.mem.eql(u8, min_int32_value_json, json.MinInt32ValueJson));
    var any_min_int32_value_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.Int32Value", min_int32_value);
    defer any_min_int32_value_wkt.deinit(allocator);
    const any_min_int32_value_wkt_json = try any_min_int32_value_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_min_int32_value_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_min_int32_value_wkt_json, json.AnyMinInt32ValueWktJson));
    const max_int32_value = pbz.Int32Value{ .value = std.math.maxInt(i32) };
    const max_int32_value_json = try max_int32_value.jsonStringifyAlloc(allocator);
    defer allocator.free(max_int32_value_json);
    std.debug.assert(std.mem.eql(u8, max_int32_value_json, json.MaxInt32ValueJson));
    var any_max_int32_value_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.Int32Value", max_int32_value);
    defer any_max_int32_value_wkt.deinit(allocator);
    const any_max_int32_value_wkt_json = try any_max_int32_value_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_max_int32_value_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_max_int32_value_wkt_json, json.AnyMaxInt32ValueWktJson));
    const uint32_value = pbz.UInt32Value{ .value = 12345 };
    const uint32_value_json = try uint32_value.jsonStringifyAlloc(allocator);
    defer allocator.free(uint32_value_json);
    std.debug.assert(std.mem.eql(u8, uint32_value_json, json.UInt32ValueJson));
    var any_uint32_value_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.UInt32Value", uint32_value);
    defer any_uint32_value_wkt.deinit(allocator);
    const any_uint32_value_wkt_json = try any_uint32_value_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_uint32_value_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_uint32_value_wkt_json, json.AnyUInt32ValueWktJson));
    const uint32_value_string = try pbz.UInt32Value.jsonParse(allocator, json.UInt32ValueStringJson);
    std.debug.assert(uint32_value_string.value == uint32_value.value);
    var any_uint32_value_string_wkt = try pbz.Any.jsonParse(allocator, json.AnyUInt32ValueStringWktJson);
    defer any_uint32_value_string_wkt.deinit(allocator);
    const uint32_value_exponent = try pbz.UInt32Value.jsonParse(allocator, json.UInt32ValueExponentJson);
    std.debug.assert(uint32_value_exponent.value == uint32_value.value);
    var any_uint32_value_exponent_wkt = try pbz.Any.jsonParse(allocator, json.AnyUInt32ValueExponentWktJson);
    defer any_uint32_value_exponent_wkt.deinit(allocator);
    const zero_uint32_value = pbz.UInt32Value{ .value = 0 };
    const zero_uint32_value_json = try zero_uint32_value.jsonStringifyAlloc(allocator);
    defer allocator.free(zero_uint32_value_json);
    std.debug.assert(std.mem.eql(u8, zero_uint32_value_json, json.ZeroUInt32ValueJson));
    var any_zero_uint32_value_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.UInt32Value", zero_uint32_value);
    defer any_zero_uint32_value_wkt.deinit(allocator);
    const any_zero_uint32_value_wkt_json = try any_zero_uint32_value_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_zero_uint32_value_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_zero_uint32_value_wkt_json, json.AnyZeroUInt32ValueWktJson));
    const max_uint32_value = pbz.UInt32Value{ .value = std.math.maxInt(u32) };
    const max_uint32_value_json = try max_uint32_value.jsonStringifyAlloc(allocator);
    defer allocator.free(max_uint32_value_json);
    std.debug.assert(std.mem.eql(u8, max_uint32_value_json, json.MaxUInt32ValueJson));
    var any_max_uint32_value_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.UInt32Value", max_uint32_value);
    defer any_max_uint32_value_wkt.deinit(allocator);
    const any_max_uint32_value_wkt_json = try any_max_uint32_value_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_max_uint32_value_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_max_uint32_value_wkt_json, json.AnyMaxUInt32ValueWktJson));
    const bool_value = pbz.BoolValue{ .value = true };
    const bool_value_json = try bool_value.jsonStringifyAlloc(allocator);
    defer allocator.free(bool_value_json);
    std.debug.assert(std.mem.eql(u8, bool_value_json, json.BoolValueJson));
    var any_bool_value_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.BoolValue", bool_value);
    defer any_bool_value_wkt.deinit(allocator);
    const any_bool_value_wkt_json = try any_bool_value_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_bool_value_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_bool_value_wkt_json, json.AnyBoolValueWktJson));
    const false_bool_value = pbz.BoolValue{ .value = false };
    const false_bool_value_json = try false_bool_value.jsonStringifyAlloc(allocator);
    defer allocator.free(false_bool_value_json);
    std.debug.assert(std.mem.eql(u8, false_bool_value_json, json.FalseBoolValueJson));
    var any_false_bool_value_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.BoolValue", false_bool_value);
    defer any_false_bool_value_wkt.deinit(allocator);
    const any_false_bool_value_wkt_json = try any_false_bool_value_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_false_bool_value_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_false_bool_value_wkt_json, json.AnyFalseBoolValueWktJson));
    const string_value = pbz.StringValue{ .value = "hello" };
    const string_value_json = try string_value.jsonStringifyAlloc(allocator);
    defer allocator.free(string_value_json);
    std.debug.assert(std.mem.eql(u8, string_value_json, json.StringValueJson));
    var any_string_value_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.StringValue", string_value);
    defer any_string_value_wkt.deinit(allocator);
    const any_string_value_wkt_json = try any_string_value_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_string_value_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_string_value_wkt_json, json.AnyStringValueWktJson));
    var string_value_escape = try pbz.StringValue.jsonParse(allocator, json.StringValueEscapeJson);
    defer string_value_escape.deinit(allocator);
    std.debug.assert(std.mem.eql(u8, string_value_escape.value, string_value.value));
    var any_string_value_escape_wkt = try pbz.Any.jsonParse(allocator, json.AnyStringValueEscapeWktJson);
    defer any_string_value_escape_wkt.deinit(allocator);
    var string_value_surrogate = try pbz.StringValue.jsonParse(allocator, json.StringValueSurrogateJson);
    defer string_value_surrogate.deinit(allocator);
    std.debug.assert(std.mem.eql(u8, string_value_surrogate.value, "😀"));
    var any_string_value_surrogate_wkt = try pbz.Any.jsonParse(allocator, json.AnyStringValueSurrogateWktJson);
    defer any_string_value_surrogate_wkt.deinit(allocator);
    const empty_string_value = pbz.StringValue{ .value = "" };
    const empty_string_value_json = try empty_string_value.jsonStringifyAlloc(allocator);
    defer allocator.free(empty_string_value_json);
    std.debug.assert(std.mem.eql(u8, empty_string_value_json, json.EmptyStringValueJson));
    var any_empty_string_value_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.StringValue", empty_string_value);
    defer any_empty_string_value_wkt.deinit(allocator);
    const any_empty_string_value_wkt_json = try any_empty_string_value_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_empty_string_value_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_empty_string_value_wkt_json, json.AnyEmptyStringValueWktJson));
    var nested_any_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.Any", any_string_value_wkt);
    defer nested_any_wkt.deinit(allocator);
    const nested_any_wkt_json = try nested_any_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(nested_any_wkt_json);
    std.debug.assert(std.mem.eql(u8, nested_any_wkt_json, json.NestedAnyWktJson));
    const bytes_value = pbz.BytesValue{ .value = "hi" };
    const bytes_value_json = try bytes_value.jsonStringifyAlloc(allocator);
    defer allocator.free(bytes_value_json);
    std.debug.assert(std.mem.eql(u8, bytes_value_json, json.BytesValueJson));
    var any_bytes_value_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.BytesValue", bytes_value);
    defer any_bytes_value_wkt.deinit(allocator);
    const any_bytes_value_wkt_json = try any_bytes_value_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_bytes_value_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_bytes_value_wkt_json, json.AnyBytesValueWktJson));
    var bytes_value_url = try pbz.BytesValue.jsonParse(allocator, json.BytesValueUrlJson);
    defer bytes_value_url.deinit(allocator);
    std.debug.assert(std.mem.eql(u8, bytes_value_url.value, &.{ 0xfb, 0xff }));
    var any_bytes_value_url_wkt = try pbz.Any.jsonParse(allocator, json.AnyBytesValueUrlWktJson);
    defer any_bytes_value_url_wkt.deinit(allocator);
    var bytes_value_standard_base64 = try pbz.BytesValue.jsonParse(allocator, json.BytesValueStandardBase64Json);
    defer bytes_value_standard_base64.deinit(allocator);
    std.debug.assert(std.mem.eql(u8, bytes_value_standard_base64.value, &.{ 0xfb, 0xff }));
    var any_bytes_value_standard_base64_wkt = try pbz.Any.jsonParse(allocator, json.AnyBytesValueStandardBase64WktJson);
    defer any_bytes_value_standard_base64_wkt.deinit(allocator);
    var bytes_value_unpadded = try pbz.BytesValue.jsonParse(allocator, json.BytesValueUnpaddedJson);
    defer bytes_value_unpadded.deinit(allocator);
    std.debug.assert(std.mem.eql(u8, bytes_value_unpadded.value, "hi"));
    var any_bytes_value_unpadded_wkt = try pbz.Any.jsonParse(allocator, json.AnyBytesValueUnpaddedWktJson);
    defer any_bytes_value_unpadded_wkt.deinit(allocator);
    const empty_bytes_value = pbz.BytesValue{ .value = "" };
    const empty_bytes_value_json = try empty_bytes_value.jsonStringifyAlloc(allocator);
    defer allocator.free(empty_bytes_value_json);
    std.debug.assert(std.mem.eql(u8, empty_bytes_value_json, json.EmptyBytesValueJson));
    var any_empty_bytes_value_wkt = try pbz.Any.packEncoded(allocator, "google.protobuf.BytesValue", empty_bytes_value);
    defer any_empty_bytes_value_wkt.deinit(allocator);
    const any_empty_bytes_value_wkt_json = try any_empty_bytes_value_wkt.jsonStringifyAlloc(allocator);
    defer allocator.free(any_empty_bytes_value_wkt_json);
    std.debug.assert(std.mem.eql(u8, any_empty_bytes_value_wkt_json, json.AnyEmptyBytesValueWktJson));
    const generated_text = try generated_person.formatTextAlloc(allocator);
    defer allocator.free(generated_text);
    const dynamic_text = try pbz.formatTextAlloc(allocator, &file, &dynamic_person, .{});
    defer allocator.free(dynamic_text);

    std.debug.print("pbz benchmark baseline (Zig {s})\n", .{@import("builtin").zig_version_string});
    std.debug.print("payload sizes: person_generated={d} person_dynamic={d} packed_generated={d} packed_dynamic={d} fixed_packed_generated={d} fixed_packed_dynamic={d} fixed64_packed_generated={d} fixed64_packed_dynamic={d} sfixed_packed_generated={d} sfixed_packed_dynamic={d} sfixed64_packed_generated={d} sfixed64_packed_dynamic={d} float_packed_generated={d} float_packed_dynamic={d} double_packed_generated={d} double_packed_dynamic={d} uint64_packed_generated={d} uint64_packed_dynamic={d} uint32_packed_generated={d} uint32_packed_dynamic={d} int64_packed_generated={d} int64_packed_dynamic={d} sint32_packed_generated={d} sint32_packed_dynamic={d} sint64_packed_generated={d} sint64_packed_dynamic={d} bool_packed_generated={d} bool_packed_dynamic={d} enum_packed_generated={d} enum_packed_dynamic={d}\n", .{ generated_bytes.len, dynamic_bytes.len, generated_packed_bytes.len, dynamic_packed_bytes.len, generated_fixed_packed_bytes.len, dynamic_fixed_packed_bytes.len, generated_fixed64_packed_bytes.len, dynamic_fixed64_packed_bytes.len, generated_sfixed_packed_bytes.len, dynamic_sfixed_packed_bytes.len, generated_sfixed64_packed_bytes.len, dynamic_sfixed64_packed_bytes.len, generated_float_packed_bytes.len, dynamic_float_packed_bytes.len, generated_double_packed_bytes.len, dynamic_double_packed_bytes.len, generated_uint64_packed_bytes.len, dynamic_uint64_packed_bytes.len, generated_uint32_packed_bytes.len, dynamic_uint32_packed_bytes.len, generated_int64_packed_bytes.len, dynamic_int64_packed_bytes.len, generated_sint32_packed_bytes.len, dynamic_sint32_packed_bytes.len, generated_sint64_packed_bytes.len, dynamic_sint64_packed_bytes.len, generated_bool_packed_bytes.len, dynamic_bool_packed_bytes.len, generated_enum_packed_bytes.len, dynamic_enum_packed_bytes.len });
    std.debug.print("payload sizes large map: large_map_generated={d} large_map_dynamic={d} large_map_json={d}\n", .{ generated_large_map_bytes.len, dynamic_large_map_bytes.len, generated_large_map_json.len });
    // std.Io.Writer format calls are capped at 32 arguments; keep the payload
    // inventory split into thematic groups so adding future WKT edge-case rows
    // does not silently push any single diagnostic over the compiler-enforced
    // limit again.
    std.debug.print("payload sizes detail: scalar_mix={d} text_bytes={d} large_bytes={d} presence_mix={d} complex={d} complex_json={d} complex_text={d} unknown_fields={d} shuffled_large_map={d} json={d} map_key_surrogate_json={d} timestamp_json={d} short_fraction_timestamp_json={d} micro_timestamp_json={d} nano_timestamp_json={d} offset_timestamp_json={d} pre_epoch_timestamp_json={d} max_timestamp_json={d} min_timestamp_json={d} duration_json={d} plus_duration_json={d} short_fraction_duration_json={d} micro_duration_json={d} nano_duration_json={d} negative_duration_json={d} fractional_negative_duration_json={d} max_duration_json={d} min_duration_json={d} zero_duration_json={d} field_mask_json={d} field_mask_escape_json={d} empty_field_mask_json={d}\n", .{ generated_scalar_mix_bytes.len, generated_text_bytes_bytes.len, generated_large_bytes_bytes.len, generated_presence_mix_bytes.len, generated_complex_bytes.len, generated_complex_json.len, generated_complex_text.len, generated_unknown_bytes.len, generated_shuffled_large_map_bytes.len, generated_json.len, json.GeneratedMapKeySurrogateJson.len, timestamp_json.len, json.ShortFractionTimestampJson.len, micro_timestamp_json.len, nano_timestamp_json.len, json.OffsetTimestampJson.len, pre_epoch_timestamp_json.len, max_timestamp_json.len, min_timestamp_json.len, duration_json.len, json.PlusDurationJson.len, json.ShortFractionDurationJson.len, micro_duration_json.len, nano_duration_json.len, negative_duration_json.len, fractional_negative_duration_json.len, max_duration_json.len, min_duration_json.len, zero_duration_json.len, field_mask_json.len, json.FieldMaskEscapeJson.len, empty_field_mask_json.len });
    std.debug.print("payload sizes generated JSON extras: text_bytes_json={d} presence_mix_json={d} complex_proto_name_json={d} scalarmix_json={d} null_fields_json={d} ignore_unknown_json={d} open_enum_json={d} enum_name_json={d} proto_name_parse_json={d} proto_name_stringify_json={d} enum_number_stringify_json={d} always_print_stringify_json={d} int_exponent_json={d} string_number_json={d}\n", .{ generated_text_bytes_json.len, generated_presence_mix_json.len, generated_complex_proto_name_json.len, generated_scalar_mix_json.len, json.GeneratedNullFieldsJson.len, json.GeneratedIgnoreUnknownJson.len, json.GeneratedOpenEnumJson.len, json.GeneratedEnumNameJson.len, json.GeneratedProtoNameJson.len, generated_proto_name_json.len, generated_enum_number_json.len, generated_always_print_json.len, json.GeneratedIntExponentJson.len, json.GeneratedStringNumberJson.len });
    std.debug.print("payload sizes escaped temporal WKT JSON: duration_escape_json={d} timestamp_escape_json={d} any_duration_escape_wkt_json={d} any_timestamp_escape_wkt_json={d}\n", .{ json.DurationEscapeJson.len, json.TimestampEscapeJson.len, json.AnyDurationEscapeWktJson.len, json.AnyTimestampEscapeWktJson.len });
    std.debug.print("payload sizes direct object/value WKTs: empty_json={d} struct_json={d} struct_escape_json={d} struct_number_exponent_json={d} struct_surrogate_json={d} struct_key_surrogate_json={d} empty_struct_json={d} value_json={d} value_escape_json={d} value_number_exponent_json={d} value_surrogate_json={d} value_key_surrogate_json={d} null_value_json={d} string_scalar_value_json={d} string_scalar_value_escape_json={d} string_scalar_value_surrogate_json={d} empty_string_scalar_value_json={d} number_value_json={d} number_value_exponent_json={d} negative_number_value_json={d} zero_number_value_json={d} bool_scalar_value_json={d} false_bool_scalar_value_json={d} list_kind_value_json={d} list_kind_value_escape_json={d} list_kind_value_surrogate_json={d} empty_struct_kind_value_json={d} empty_list_kind_value_json={d} list_value_json={d} list_value_escape_json={d} list_value_surrogate_json={d} empty_list_value_json={d}\n", .{ empty_json.len, struct_json.len, json.StructEscapeJson.len, json.StructNumberExponentJson.len, json.StructSurrogateJson.len, json.StructKeySurrogateJson.len, empty_struct_json.len, value_json.len, json.ValueEscapeJson.len, json.ValueNumberExponentJson.len, json.ValueSurrogateJson.len, json.ValueKeySurrogateJson.len, null_value_json.len, string_scalar_value_json.len, json.StringScalarValueEscapeJson.len, json.StringScalarValueSurrogateJson.len, empty_string_scalar_value_json.len, number_value_json.len, json.NumberValueExponentJson.len, negative_number_value_json.len, zero_number_value_json.len, bool_scalar_value_json.len, false_bool_scalar_value_json.len, list_kind_value_json.len, json.ListKindValueEscapeJson.len, json.ListKindValueSurrogateJson.len, empty_struct_kind_value_json.len, empty_list_kind_value_json.len, list_value_json.len, json.ListValueEscapeJson.len, json.ListValueSurrogateJson.len, empty_list_value_json.len });
    std.debug.print("payload sizes direct float WKT wrappers: double_value_json={d} double_value_string_json={d} double_value_exponent_json={d} negative_double_value_json={d} zero_double_value_json={d} double_value_nan_json={d} double_value_inf_json={d} double_value_neg_inf_json={d} float_value_json={d} float_value_string_json={d} float_value_exponent_json={d} negative_float_value_json={d} zero_float_value_json={d} float_value_nan_json={d} float_value_inf_json={d} float_value_neg_inf_json={d}\n", .{ double_value_json.len, json.DoubleValueStringJson.len, json.DoubleValueExponentJson.len, negative_double_value_json.len, zero_double_value_json.len, double_value_nan_json.len, double_value_inf_json.len, double_value_neg_inf_json.len, float_value_json.len, json.FloatValueStringJson.len, json.FloatValueExponentJson.len, negative_float_value_json.len, zero_float_value_json.len, float_value_nan_json.len, float_value_inf_json.len, float_value_neg_inf_json.len });
    std.debug.print("payload sizes direct integer WKT wrappers: int64_value_json={d} int64_value_number_json={d} int64_value_exponent_json={d} zero_int64_value_json={d} negative_int64_value_json={d} min_int64_value_json={d} max_int64_value_json={d} uint64_value_json={d} uint64_value_number_json={d} uint64_value_exponent_json={d} zero_uint64_value_json={d} max_uint64_value_json={d} int32_value_json={d} int32_value_string_json={d} int32_value_exponent_json={d} zero_int32_value_json={d} negative_int32_value_json={d} min_int32_value_json={d} max_int32_value_json={d} uint32_value_json={d} uint32_value_string_json={d} uint32_value_exponent_json={d} zero_uint32_value_json={d} max_uint32_value_json={d}\n", .{ int64_value_json.len, json.Int64ValueNumberJson.len, json.Int64ValueExponentJson.len, zero_int64_value_json.len, negative_int64_value_json.len, min_int64_value_json.len, max_int64_value_json.len, uint64_value_json.len, json.UInt64ValueNumberJson.len, json.UInt64ValueExponentJson.len, zero_uint64_value_json.len, max_uint64_value_json.len, int32_value_json.len, json.Int32ValueStringJson.len, json.Int32ValueExponentJson.len, zero_int32_value_json.len, negative_int32_value_json.len, min_int32_value_json.len, max_int32_value_json.len, uint32_value_json.len, json.UInt32ValueStringJson.len, json.UInt32ValueExponentJson.len, zero_uint32_value_json.len, max_uint32_value_json.len });
    std.debug.print("payload sizes direct text/bool WKT wrappers: bool_value_json={d} false_bool_value_json={d} string_value_json={d} string_value_escape_json={d} string_value_surrogate_json={d} empty_string_value_json={d} bytes_value_json={d} bytes_value_url_json={d} bytes_value_standard_base64_json={d} bytes_value_unpadded_json={d} empty_bytes_value_json={d} text={d}\n", .{ bool_value_json.len, false_bool_value_json.len, string_value_json.len, json.StringValueEscapeJson.len, json.StringValueSurrogateJson.len, empty_string_value_json.len, bytes_value_json.len, json.BytesValueUrlJson.len, json.BytesValueStandardBase64Json.len, json.BytesValueUnpaddedJson.len, empty_bytes_value_json.len, generated_text.len });
    std.debug.print("payload sizes Any WKT temporal wrappers: any_wkt_json={d} any_duration_escape_wkt_json={d} any_plus_duration_wkt_json={d} any_short_fraction_duration_wkt_json={d} any_micro_duration_wkt_json={d} any_nano_duration_wkt_json={d} any_negative_duration_wkt_json={d} any_fractional_negative_duration_wkt_json={d} any_max_duration_wkt_json={d} any_min_duration_wkt_json={d} any_zero_duration_wkt_json={d} any_field_mask_wkt_json={d} any_empty_field_mask_wkt_json={d} any_timestamp_wkt_json={d} any_timestamp_escape_wkt_json={d} any_short_fraction_timestamp_wkt_json={d} any_micro_timestamp_wkt_json={d} any_nano_timestamp_wkt_json={d} any_offset_timestamp_wkt_json={d} any_pre_epoch_timestamp_wkt_json={d} any_max_timestamp_wkt_json={d} any_min_timestamp_wkt_json={d} any_empty_wkt_json={d}\n", .{ any_wkt_json.len, json.AnyDurationEscapeWktJson.len, json.AnyPlusDurationWktJson.len, json.AnyShortFractionDurationWktJson.len, any_micro_duration_wkt_json.len, any_nano_duration_wkt_json.len, any_negative_duration_wkt_json.len, any_fractional_negative_duration_wkt_json.len, any_max_duration_wkt_json.len, any_min_duration_wkt_json.len, any_zero_duration_wkt_json.len, any_field_mask_wkt_json.len, any_empty_field_mask_wkt_json.len, any_timestamp_wkt_json.len, json.AnyTimestampEscapeWktJson.len, json.AnyShortFractionTimestampWktJson.len, any_micro_timestamp_wkt_json.len, any_nano_timestamp_wkt_json.len, json.AnyOffsetTimestampWktJson.len, any_pre_epoch_timestamp_wkt_json.len, any_max_timestamp_wkt_json.len, any_min_timestamp_wkt_json.len, any_empty_wkt_json.len });
    std.debug.print("payload sizes Any WKT object/value wrappers: any_struct_wkt_json={d} any_struct_escape_wkt_json={d} any_struct_number_exponent_wkt_json={d} any_struct_surrogate_wkt_json={d} any_struct_key_surrogate_wkt_json={d} any_empty_struct_wkt_json={d} any_value_wkt_json={d} any_value_escape_wkt_json={d} any_value_number_exponent_wkt_json={d} any_value_surrogate_wkt_json={d} any_value_key_surrogate_wkt_json={d} any_null_value_wkt_json={d} any_string_scalar_value_wkt_json={d} any_string_scalar_value_escape_wkt_json={d} any_string_scalar_value_surrogate_wkt_json={d} any_empty_string_scalar_value_wkt_json={d} any_number_value_wkt_json={d} any_number_value_exponent_wkt_json={d} any_negative_number_value_wkt_json={d} any_zero_number_value_wkt_json={d} any_bool_scalar_value_wkt_json={d} any_false_bool_scalar_value_wkt_json={d} any_list_kind_value_wkt_json={d} any_list_kind_value_escape_wkt_json={d} any_list_kind_value_surrogate_wkt_json={d} any_empty_struct_kind_value_wkt_json={d} any_empty_list_kind_value_wkt_json={d} nested_any_wkt_json={d}\n", .{ any_struct_wkt_json.len, json.AnyStructEscapeWktJson.len, json.AnyStructNumberExponentWktJson.len, json.AnyStructSurrogateWktJson.len, json.AnyStructKeySurrogateWktJson.len, any_empty_struct_wkt_json.len, any_value_wkt_json.len, json.AnyValueEscapeWktJson.len, json.AnyValueNumberExponentWktJson.len, json.AnyValueSurrogateWktJson.len, json.AnyValueKeySurrogateWktJson.len, any_null_value_wkt_json.len, any_string_scalar_value_wkt_json.len, json.AnyStringScalarValueEscapeWktJson.len, json.AnyStringScalarValueSurrogateWktJson.len, any_empty_string_scalar_value_wkt_json.len, any_number_value_wkt_json.len, json.AnyNumberValueExponentWktJson.len, any_negative_number_value_wkt_json.len, any_zero_number_value_wkt_json.len, any_bool_scalar_value_wkt_json.len, any_false_bool_scalar_value_wkt_json.len, any_list_kind_value_wkt_json.len, json.AnyListKindValueEscapeWktJson.len, json.AnyListKindValueSurrogateWktJson.len, any_empty_struct_kind_value_wkt_json.len, any_empty_list_kind_value_wkt_json.len, nested_any_wkt_json.len });
    std.debug.print("payload sizes Any WKT floating wrappers: any_double_value_wkt_json={d} any_double_value_string_wkt_json={d} any_double_value_exponent_wkt_json={d} any_negative_double_value_wkt_json={d} any_zero_double_value_wkt_json={d} any_double_value_nan_wkt_json={d} any_double_value_inf_wkt_json={d} any_double_value_neg_inf_wkt_json={d} any_float_value_wkt_json={d} any_float_value_string_wkt_json={d} any_float_value_exponent_wkt_json={d} any_negative_float_value_wkt_json={d} any_zero_float_value_wkt_json={d} any_float_value_nan_wkt_json={d} any_float_value_inf_wkt_json={d} any_float_value_neg_inf_wkt_json={d}\n", .{ any_double_value_wkt_json.len, json.AnyDoubleValueStringWktJson.len, json.AnyDoubleValueExponentWktJson.len, any_negative_double_value_wkt_json.len, any_zero_double_value_wkt_json.len, any_double_value_nan_wkt_json.len, any_double_value_inf_wkt_json.len, any_double_value_neg_inf_wkt_json.len, any_float_value_wkt_json.len, json.AnyFloatValueStringWktJson.len, json.AnyFloatValueExponentWktJson.len, any_negative_float_value_wkt_json.len, any_zero_float_value_wkt_json.len, any_float_value_nan_wkt_json.len, any_float_value_inf_wkt_json.len, any_float_value_neg_inf_wkt_json.len });
    std.debug.print("payload sizes Any WKT integer wrappers: any_int64_value_wkt_json={d} any_int64_value_number_wkt_json={d} any_int64_value_exponent_wkt_json={d} any_zero_int64_value_wkt_json={d} any_negative_int64_value_wkt_json={d} any_min_int64_value_wkt_json={d} any_max_int64_value_wkt_json={d} any_uint64_value_wkt_json={d} any_uint64_value_number_wkt_json={d} any_uint64_value_exponent_wkt_json={d} any_zero_uint64_value_wkt_json={d} any_max_uint64_value_wkt_json={d} any_int32_value_wkt_json={d} any_int32_value_string_wkt_json={d} any_int32_value_exponent_wkt_json={d} any_zero_int32_value_wkt_json={d} any_negative_int32_value_wkt_json={d} any_min_int32_value_wkt_json={d} any_max_int32_value_wkt_json={d} any_uint32_value_wkt_json={d} any_uint32_value_string_wkt_json={d} any_uint32_value_exponent_wkt_json={d} any_zero_uint32_value_wkt_json={d} any_max_uint32_value_wkt_json={d}\n", .{ any_int64_value_wkt_json.len, json.AnyInt64ValueNumberWktJson.len, json.AnyInt64ValueExponentWktJson.len, any_zero_int64_value_wkt_json.len, any_negative_int64_value_wkt_json.len, any_min_int64_value_wkt_json.len, any_max_int64_value_wkt_json.len, any_uint64_value_wkt_json.len, json.AnyUInt64ValueNumberWktJson.len, json.AnyUInt64ValueExponentWktJson.len, any_zero_uint64_value_wkt_json.len, any_max_uint64_value_wkt_json.len, any_int32_value_wkt_json.len, json.AnyInt32ValueStringWktJson.len, json.AnyInt32ValueExponentWktJson.len, any_zero_int32_value_wkt_json.len, any_negative_int32_value_wkt_json.len, any_min_int32_value_wkt_json.len, any_max_int32_value_wkt_json.len, any_uint32_value_wkt_json.len, json.AnyUInt32ValueStringWktJson.len, json.AnyUInt32ValueExponentWktJson.len, any_zero_uint32_value_wkt_json.len, any_max_uint32_value_wkt_json.len });
    std.debug.print("payload sizes Any WKT text/bool wrappers: any_bool_value_wkt_json={d} any_false_bool_value_wkt_json={d} any_string_value_wkt_json={d} any_string_value_surrogate_wkt_json={d} any_empty_string_value_wkt_json={d} any_bytes_value_wkt_json={d} any_bytes_value_standard_base64_wkt_json={d} any_bytes_value_unpadded_wkt_json={d} any_empty_bytes_value_wkt_json={d}\n", .{ any_bool_value_wkt_json.len, any_false_bool_value_wkt_json.len, any_string_value_wkt_json.len, json.AnyStringValueSurrogateWktJson.len, any_empty_string_value_wkt_json.len, any_bytes_value_wkt_json.len, json.AnyBytesValueStandardBase64WktJson.len, json.AnyBytesValueUnpaddedWktJson.len, any_empty_bytes_value_wkt_json.len });

    const results = [_]BenchResult{
        try runTimed(io, "generated binary encode", iters.generated_binary, generated_bytes.len, generated.GeneratedEncodeCtx{ .allocator = allocator, .person = &generated_person }, generated.generatedEncode),
        try runTimed(io, "generated binary writeToAssumeCapacity reuse", iters.generated_binary, generated_bytes.len, generated.GeneratedWriteToCtx{ .writer = &reusable_writer, .person = &generated_person }, generated.generatedWriteToReuse),
        try runTimed(io, "generated binary encodeIntoAssumeCapacity buffer reuse", iters.generated_binary, generated_bytes.len, generated.GeneratedEncodeIntoCtx{ .buffer = generated_buffer, .person = &generated_person }, generated.generatedEncodeIntoReuse),
        try runTimed(io, "generated binary trusted UTF-8 encodeIntoAssumeCapacity buffer reuse", iters.generated_binary, generated_bytes.len, generated.GeneratedPersonFastEncodeIntoCtx{ .buffer = generated_buffer, .person = &generated_person }, generated.generatedPersonTrustedUtf8EncodeIntoReuse),
        try runTimed(io, "generated deterministic binary encode", iters.generated_binary, generated_bytes.len, generated.GeneratedDeterministicEncodeCtx{ .allocator = allocator, .person = &generated_person }, generated.generatedDeterministicEncode),
        try runTimed(io, "generated deterministic binary encodeIntoAssumeCapacity buffer reuse", iters.generated_binary, generated_bytes.len, generated.GeneratedDeterministicEncodeIntoCtx{ .allocator = allocator, .buffer = generated_buffer, .person = &generated_person }, generated.generatedDeterministicEncodeIntoReuse),
        try runTimed(io, "generated binary decode", iters.generated_binary, generated_bytes.len, generated.GeneratedDecodeCtx{ .allocator = allocator, .bytes = generated_bytes }, generated.generatedDecode),
        try runTimed(io, "generated binary decode owned", iters.generated_binary, generated_bytes.len, generated.GeneratedDecodeOwnedCtx{ .allocator = allocator, .bytes = generated_bytes }, generated.generatedDecodeOwned),
        try runTimed(io, "generated binary decode reuse", iters.generated_binary, generated_bytes.len, generated.GeneratedDecodeReuseCtx{ .allocator = allocator, .bytes = generated_bytes, .message = &generated_person_decode_reuse }, generated.generatedDecodeReuse),
        try runTimed(io, "generated binary decode owned reuse", iters.generated_binary, generated_bytes.len, generated.GeneratedDecodeOwnedReuseCtx{ .allocator = allocator, .bytes = generated_bytes, .message = &generated_person_decode_reuse }, generated.generatedDecodeOwnedReuse),
        try runTimed(io, "generated unknown fields decode", iters.large_map, generated_unknown_bytes.len, unknown.GeneratedUnknownDecodeCtx{ .allocator = allocator, .bytes = generated_unknown_bytes }, unknown.generatedUnknownDecode),
        try runTimed(io, "generated unknown fields count by number", iters.generated_binary, generated_unknown_bytes.len, unknown.GeneratedUnknownQueryCtx{ .message = &generated_unknown_person, .number = UnknownFieldStressFirstNumber }, unknown.generatedUnknownCountByNumber),
        try runTimed(io, "generated unknown field number sidecar count", iters.generated_binary, generated_unknown_bytes.len, unknown.GeneratedUnknownNumberQueryCtx{ .numbers = generated_unknown_numbers, .number = UnknownFieldStressFirstNumber }, unknown.generatedUnknownNumberCountByNumber),
        try runTimed(io, "generated unknown field number run sidecar count", iters.generated_binary, generated_unknown_bytes.len, unknown.GeneratedUnknownRunQueryCtx{ .runs = generated_unknown_number_runs, .number = UnknownFieldStressFirstNumber }, unknown.generatedUnknownNumberRunCountByNumber),
        try runTimed(io, "generated scalarmix encode", iters.generated_binary, generated_scalar_mix_bytes.len, generated.GeneratedScalarMixEncodeCtx{ .allocator = allocator, .message = &generated_scalar_mix }, generated.generatedScalarMixEncode),
        try runTimed(io, "generated scalarmix writeToAssumeCapacity reuse", iters.generated_binary, generated_scalar_mix_bytes.len, generated.GeneratedScalarMixWriteToCtx{ .writer = &reusable_scalar_mix_writer, .message = &generated_scalar_mix }, generated.generatedScalarMixWriteToReuse),
        try runTimed(io, "generated scalarmix encodeIntoAssumeCapacity buffer reuse", iters.generated_binary, generated_scalar_mix_bytes.len, generated.GeneratedScalarMixEncodeIntoCtx{ .buffer = generated_scalar_mix_buffer, .message = &generated_scalar_mix }, generated.generatedScalarMixEncodeIntoReuse),
        try runTimed(io, "generated scalarmix decode", iters.generated_binary, generated_scalar_mix_bytes.len, generated.GeneratedScalarMixDecodeCtx{ .allocator = allocator, .bytes = generated_scalar_mix_bytes }, generated.generatedScalarMixDecode),
        try runTimed(io, "generated scalarmix decode reuse", iters.generated_binary, generated_scalar_mix_bytes.len, generated.GeneratedScalarMixDecodeReuseCtx{ .allocator = allocator, .bytes = generated_scalar_mix_bytes, .message = &generated_scalar_mix_decode_reuse }, generated.generatedScalarMixDecodeReuse),
        try runTimed(io, "generated scalarmix fast known-schema decode reuse", iters.generated_binary, generated_scalar_mix_bytes.len, generated.GeneratedScalarMixDecodeReuseCtx{ .allocator = allocator, .bytes = generated_scalar_mix_bytes, .message = &generated_scalar_mix_decode_reuse }, generated.generatedScalarMixKnownDecodeReuse),
        try runTimed(io, "generated textbytes encode", iters.generated_binary, generated_text_bytes_bytes.len, generated.GeneratedTextBytesEncodeCtx{ .allocator = allocator, .message = &generated_text_bytes }, generated.generatedTextBytesEncode),
        try runTimed(io, "generated textbytes writeToAssumeCapacity reuse", iters.generated_binary, generated_text_bytes_bytes.len, generated.GeneratedTextBytesWriteToCtx{ .writer = &reusable_text_bytes_writer, .message = &generated_text_bytes }, generated.generatedTextBytesWriteToReuse),
        try runTimed(io, "generated textbytes trusted UTF-8 writeToAssumeCapacity reuse", iters.generated_binary, generated_text_bytes_bytes.len, generated.GeneratedTextBytesWriteToCtx{ .writer = &reusable_text_bytes_writer, .message = &generated_text_bytes }, generated.generatedTextBytesTrustedUtf8WriteToReuse),
        try runTimed(io, "generated textbytes encodeIntoAssumeCapacity buffer reuse", iters.generated_binary, generated_text_bytes_bytes.len, generated.GeneratedTextBytesEncodeIntoCtx{ .buffer = generated_text_bytes_buffer, .message = &generated_text_bytes }, generated.generatedTextBytesEncodeIntoReuse),
        try runTimed(io, "generated textbytes trusted UTF-8 encodeIntoAssumeCapacity buffer reuse", iters.generated_binary, generated_text_bytes_bytes.len, generated.GeneratedTextBytesEncodeIntoCtx{ .buffer = generated_text_bytes_buffer, .message = &generated_text_bytes }, generated.generatedTextBytesTrustedUtf8EncodeIntoReuse),
        try runTimed(io, "generated textbytes borrowed slices encode", iters.generated_binary, generated_text_bytes_bytes.len, generated.GeneratedTextBytesBorrowedSlicesCtx{ .message = &generated_text_bytes }, generated.generatedTextBytesBorrowedSlices),
        try runTimed(io, "generated textbytes decode", iters.generated_binary, generated_text_bytes_bytes.len, generated.GeneratedTextBytesDecodeCtx{ .allocator = allocator, .bytes = generated_text_bytes_bytes }, generated.generatedTextBytesDecode),
        try runTimed(io, "generated textbytes decode owned", iters.generated_binary, generated_text_bytes_bytes.len, generated.GeneratedTextBytesDecodeOwnedCtx{ .allocator = allocator, .bytes = generated_text_bytes_bytes }, generated.generatedTextBytesDecodeOwned),
        try runTimed(io, "generated textbytes decode reuse", iters.generated_binary, generated_text_bytes_bytes.len, generated.GeneratedTextBytesDecodeReuseCtx{ .allocator = allocator, .bytes = generated_text_bytes_bytes, .message = &generated_text_bytes_decode_reuse }, generated.generatedTextBytesDecodeReuse),
        try runTimed(io, "generated textbytes decode owned reuse", iters.generated_binary, generated_text_bytes_bytes.len, generated.GeneratedTextBytesDecodeOwnedReuseCtx{ .allocator = allocator, .bytes = generated_text_bytes_bytes, .message = &generated_text_bytes_decode_reuse }, generated.generatedTextBytesDecodeOwnedReuse),
        try runTimed(io, "generated TextBytes JSON stringify", iters.json, generated_text_bytes_json.len, json.GeneratedTextBytesJsonStringifyCtx{ .allocator = allocator, .message = &generated_text_bytes }, json.generatedTextBytesJsonStringify),
        try runTimed(io, "generated TextBytes JSON parse", iters.json, generated_text_bytes_json.len, json.GeneratedTextBytesJsonParseCtx{ .allocator = allocator, .json = generated_text_bytes_json }, json.generatedTextBytesJsonParse),
        try runTimed(io, "generated largebytes encode", iters.generated_binary, generated_large_bytes_bytes.len, generated.GeneratedLargeBytesEncodeCtx{ .allocator = allocator, .message = &generated_large_bytes }, generated.generatedLargeBytesEncode),
        try runTimed(io, "generated largebytes writeToAssumeCapacity reuse", iters.generated_binary, generated_large_bytes_bytes.len, generated.GeneratedLargeBytesWriteToCtx{ .writer = &reusable_large_bytes_writer, .message = &generated_large_bytes }, generated.generatedLargeBytesWriteToReuse),
        try runTimed(io, "generated largebytes encodeIntoAssumeCapacity buffer reuse", iters.generated_binary, generated_large_bytes_bytes.len, generated.GeneratedLargeBytesEncodeIntoCtx{ .buffer = generated_large_bytes_buffer, .message = &generated_large_bytes }, generated.generatedLargeBytesEncodeIntoReuse),
        try runTimed(io, "generated largebytes borrowed slices encode", iters.generated_binary, generated_large_bytes_bytes.len, generated.GeneratedLargeBytesBorrowedSlicesCtx{ .message = &generated_large_bytes }, generated.generatedLargeBytesBorrowedSlices),
        try runTimed(io, "generated largebytes decode", iters.generated_binary, generated_large_bytes_bytes.len, generated.GeneratedLargeBytesDecodeCtx{ .allocator = allocator, .bytes = generated_large_bytes_bytes }, generated.generatedLargeBytesDecode),
        try runTimed(io, "generated largebytes decode owned", iters.generated_binary, generated_large_bytes_bytes.len, generated.GeneratedLargeBytesDecodeOwnedCtx{ .allocator = allocator, .bytes = generated_large_bytes_bytes }, generated.generatedLargeBytesDecodeOwned),
        try runTimed(io, "generated largebytes decode reuse", iters.generated_binary, generated_large_bytes_bytes.len, generated.GeneratedLargeBytesDecodeReuseCtx{ .allocator = allocator, .bytes = generated_large_bytes_bytes, .message = &generated_large_bytes_decode_reuse }, generated.generatedLargeBytesDecodeReuse),
        try runTimed(io, "generated largebytes decode owned reuse", iters.generated_binary, generated_large_bytes_bytes.len, generated.GeneratedLargeBytesDecodeOwnedReuseCtx{ .allocator = allocator, .bytes = generated_large_bytes_bytes, .message = &generated_large_bytes_decode_reuse }, generated.generatedLargeBytesDecodeOwnedReuse),
        try runTimed(io, "generated largebytes borrowed view decode", iters.generated_binary, generated_large_bytes_bytes.len, LargeBytesBorrowedViewCtx{ .bytes = generated_large_bytes_bytes }, largeBytesBorrowedViewDecode),
        try runTimed(io, "generated presencemix encode", iters.generated_binary, generated_presence_mix_bytes.len, generated.GeneratedPresenceMixEncodeCtx{ .allocator = allocator, .message = &generated_presence_mix }, generated.generatedPresenceMixEncode),
        try runTimed(io, "generated presencemix writeToAssumeCapacity reuse", iters.generated_binary, generated_presence_mix_bytes.len, generated.GeneratedPresenceMixWriteToCtx{ .writer = &reusable_presence_mix_writer, .message = &generated_presence_mix }, generated.generatedPresenceMixWriteToReuse),
        try runTimed(io, "generated presencemix encodeIntoAssumeCapacity buffer reuse", iters.generated_binary, generated_presence_mix_bytes.len, generated.GeneratedPresenceMixEncodeIntoCtx{ .buffer = generated_presence_mix_buffer, .message = &generated_presence_mix }, generated.generatedPresenceMixEncodeIntoReuse),
        try runTimed(io, "generated presencemix trusted UTF-8 encodeIntoAssumeCapacity buffer reuse", iters.generated_binary, generated_presence_mix_bytes.len, generated.GeneratedPresenceMixEncodeIntoCtx{ .buffer = generated_presence_mix_buffer, .message = &generated_presence_mix }, generated.generatedPresenceMixTrustedUtf8EncodeIntoReuse),
        try runTimed(io, "generated presencemix decode", iters.generated_binary, generated_presence_mix_bytes.len, generated.GeneratedPresenceMixDecodeCtx{ .allocator = allocator, .bytes = generated_presence_mix_bytes }, generated.generatedPresenceMixDecode),
        try runTimed(io, "generated presencemix decode owned", iters.generated_binary, generated_presence_mix_bytes.len, generated.GeneratedPresenceMixDecodeOwnedCtx{ .allocator = allocator, .bytes = generated_presence_mix_bytes }, generated.generatedPresenceMixDecodeOwned),
        try runTimed(io, "generated presencemix decode reuse", iters.generated_binary, generated_presence_mix_bytes.len, generated.GeneratedPresenceMixDecodeReuseCtx{ .allocator = allocator, .bytes = generated_presence_mix_bytes, .message = &generated_presence_mix_decode_reuse }, generated.generatedPresenceMixDecodeReuse),
        try runTimed(io, "generated presencemix decode owned reuse", iters.generated_binary, generated_presence_mix_bytes.len, generated.GeneratedPresenceMixDecodeOwnedReuseCtx{ .allocator = allocator, .bytes = generated_presence_mix_bytes, .message = &generated_presence_mix_decode_reuse }, generated.generatedPresenceMixDecodeOwnedReuse),
        try runTimed(io, "generated PresenceMix JSON stringify", iters.json, generated_presence_mix_json.len, json.GeneratedPresenceMixJsonStringifyCtx{ .allocator = allocator, .message = &generated_presence_mix }, json.generatedPresenceMixJsonStringify),
        try runTimed(io, "generated PresenceMix JSON parse", iters.json, generated_presence_mix_json.len, json.GeneratedPresenceMixJsonParseCtx{ .allocator = allocator, .json = generated_presence_mix_json }, json.generatedPresenceMixJsonParse),
        try runTimed(io, "generated complex encode", iters.generated_binary, generated_complex_bytes.len, generated.GeneratedComplexEncodeCtx{ .allocator = allocator, .message = &generated_complex }, generated.generatedComplexEncode),
        try runTimed(io, "generated complex writeToAssumeCapacity reuse", iters.generated_binary, generated_complex_bytes.len, generated.GeneratedComplexWriteToCtx{ .writer = &reusable_complex_writer, .message = &generated_complex }, generated.generatedComplexWriteToReuse),
        try runTimed(io, "generated complex encodeIntoAssumeCapacity buffer reuse", iters.generated_binary, generated_complex_bytes.len, generated.GeneratedComplexEncodeIntoCtx{ .buffer = generated_complex_buffer, .message = &generated_complex }, generated.generatedComplexEncodeIntoReuse),
        try runTimed(io, "generated complex trusted UTF-8 encodeIntoAssumeCapacity buffer reuse", iters.generated_binary, generated_complex_bytes.len, generated.GeneratedComplexManualEncodeIntoCtx{ .buffer = generated_complex_buffer, .message = &generated_complex }, generated.generatedComplexManualEncodeIntoReuse),
        try runTimed(io, "generated complex decode", iters.generated_binary, generated_complex_bytes.len, generated.GeneratedComplexDecodeCtx{ .allocator = allocator, .bytes = generated_complex_bytes }, generated.generatedComplexDecode),
        try runTimed(io, "generated complex decode owned", iters.generated_binary, generated_complex_bytes.len, generated.GeneratedComplexDecodeOwnedCtx{ .allocator = allocator, .bytes = generated_complex_bytes }, generated.generatedComplexDecodeOwned),
        try runTimed(io, "generated complex decode reuse", iters.generated_binary, generated_complex_bytes.len, generated.GeneratedComplexDecodeReuseCtx{ .allocator = allocator, .bytes = generated_complex_bytes, .message = &generated_complex_decode_reuse }, generated.generatedComplexDecodeReuse),
        try runTimed(io, "generated complex decode owned reuse", iters.generated_binary, generated_complex_bytes.len, generated.GeneratedComplexDecodeOwnedReuseCtx{ .allocator = allocator, .bytes = generated_complex_bytes, .message = &generated_complex_decode_reuse }, generated.generatedComplexDecodeOwnedReuse),
        try runTimed(io, "generated complex JSON stringify", iters.json, generated_complex_json.len, json.GeneratedComplexJsonStringifyCtx{ .allocator = allocator, .message = &generated_complex }, json.generatedComplexJsonStringify),
        try runTimed(io, "generated complex JSON parse", iters.json, generated_complex_json.len, json.GeneratedComplexJsonParseCtx{ .allocator = allocator, .json = generated_complex_json }, json.generatedComplexJsonParse),
        try runTimed(io, "generated Complex ProtoName JSON stringify", iters.json, generated_complex_proto_name_json.len, json.GeneratedComplexJsonStringifyCtx{ .allocator = allocator, .message = &generated_complex }, json.generatedComplexProtoNameJsonStringify),
        try runTimed(io, "generated Complex ProtoName JSON parse", iters.json, generated_complex_proto_name_json.len, json.GeneratedComplexJsonParseCtx{ .allocator = allocator, .json = generated_complex_proto_name_json }, json.generatedComplexJsonParse),
        try runTimed(io, "generated complex TextFormat format", iters.text, generated_complex_text.len, json.GeneratedComplexTextFormatCtx{ .allocator = allocator, .message = &generated_complex }, json.generatedComplexTextFormat),
        try runTimed(io, "generated complex TextFormat parse", iters.text, generated_complex_text.len, json.GeneratedComplexTextParseCtx{ .allocator = allocator, .text = generated_complex_text }, json.generatedComplexTextParse),
        try runTimed(io, "generated complex deterministic binary encode", iters.generated_binary, generated_complex_bytes.len, generated.GeneratedComplexDeterministicEncodeCtx{ .allocator = allocator, .message = &generated_complex }, generated.generatedComplexDeterministicEncode),
        try runTimed(io, "generated complex deterministic binary encodeIntoAssumeCapacity buffer reuse", iters.generated_binary, generated_complex_bytes.len, generated.GeneratedComplexDeterministicEncodeIntoCtx{ .allocator = allocator, .buffer = generated_complex_buffer, .message = &generated_complex }, generated.generatedComplexDeterministicEncodeIntoReuse),
        try runTimed(io, "dynamic binary encode", iters.dynamic_binary, dynamic_bytes.len, dynamic.DynamicEncodeCtx{ .message = &dynamic_person, .file = &file }, dynamic.dynamicEncode),
        try runTimed(io, "dynamic binary decode", iters.dynamic_binary, dynamic_bytes.len, dynamic.DynamicDecodeCtx{ .allocator = allocator, .descriptor = desc, .file = &file, .bytes = dynamic_bytes }, dynamic.dynamicDecode),
        try runTimed(io, "dynamic unknown fields decode", iters.large_map, generated_unknown_bytes.len, unknown.DynamicUnknownDecodeCtx{ .allocator = allocator, .descriptor = desc, .file = &file, .bytes = generated_unknown_bytes }, unknown.dynamicUnknownDecode),
        try runTimed(io, "dynamic unknown fields count by number", iters.generated_binary, generated_unknown_bytes.len, unknown.DynamicUnknownQueryCtx{ .message = &dynamic_unknown_person, .number = UnknownFieldStressFirstNumber }, unknown.dynamicUnknownCountByNumber),
        try runTimed(io, "dynamic unknown field number sidecar count", iters.generated_binary, generated_unknown_bytes.len, unknown.DynamicUnknownNumberQueryCtx{ .numbers = dynamic_unknown_numbers, .number = UnknownFieldStressFirstNumber }, unknown.dynamicUnknownNumberCountByNumber),
        try runTimed(io, "dynamic unknown field number run sidecar count", iters.generated_binary, generated_unknown_bytes.len, unknown.DynamicUnknownRunQueryCtx{ .runs = dynamic_unknown_number_runs, .number = UnknownFieldStressFirstNumber }, unknown.dynamicUnknownNumberRunCountByNumber),
        try runTimed(io, "generated packed encode", iters.packed_binary, generated_packed_bytes.len, packed_workloads.GeneratedPackedEncodeCtx{ .allocator = allocator, .message = &generated_packed }, packed_workloads.generatedPackedEncode),
        try runTimed(io, "generated packed writeToAssumeCapacity reuse", iters.packed_binary, generated_packed_bytes.len, packed_workloads.GeneratedPackedWriteToCtx{ .writer = &reusable_packed_writer, .message = &generated_packed }, packed_workloads.generatedPackedWriteToReuse),
        try runTimed(io, "generated packed encodeIntoAssumeCapacity buffer reuse", iters.packed_binary, generated_packed_bytes.len, packed_workloads.GeneratedPackedEncodeIntoCtx{ .buffer = generated_packed_buffer, .message = &generated_packed }, packed_workloads.generatedPackedEncodeIntoReuse),
        try runTimed(io, "generated packed decode", iters.packed_binary, generated_packed_bytes.len, packed_workloads.GeneratedPackedDecodeCtx{ .allocator = allocator, .bytes = generated_packed_bytes }, packed_workloads.generatedPackedDecode),
        try runTimed(io, "generated packed fast known-schema decode reuse", iters.packed_binary, generated_packed_bytes.len, packed_workloads.GeneratedPackedDecodeReuseCtx{ .allocator = allocator, .bytes = generated_packed_bytes, .message = &generated_packed_decode_reuse }, packed_workloads.generatedPackedKnownDecodeReuse),
        try runTimed(io, "generated int32 packed iterator decode", iters.packed_binary, generated_packed_bytes.len, packed_workloads.Int32PackedIteratorCtx{ .bytes = generated_packed_bytes }, packed_workloads.int32PackedIteratorDecode),
        try runTimed(io, "dynamic packed encode", iters.packed_binary, dynamic_packed_bytes.len, packed_workloads.DynamicPackedEncodeCtx{ .message = &dynamic_packed, .file = &file }, packed_workloads.dynamicPackedEncode),
        try runTimed(io, "dynamic packed decode", iters.packed_binary, dynamic_packed_bytes.len, packed_workloads.DynamicPackedDecodeCtx{ .allocator = allocator, .descriptor = packed_desc, .file = &file, .bytes = dynamic_packed_bytes }, packed_workloads.dynamicPackedDecode),
        try runTimed(io, "generated fixed32 packed encode", iters.packed_binary, generated_fixed_packed_bytes.len, packed_workloads.GeneratedFixedPackedEncodeCtx{ .allocator = allocator, .message = &generated_fixed_packed }, packed_workloads.generatedFixedPackedEncode),
        try runTimed(io, "generated fixed32 packed encodeIntoAssumeCapacity buffer reuse", iters.packed_binary, generated_fixed_packed_bytes.len, packed_workloads.GeneratedFixedPackedEncodeIntoCtx{ .buffer = generated_fixed_packed_buffer, .message = &generated_fixed_packed }, packed_workloads.generatedFixedPackedEncodeIntoReuse),
        try runTimed(io, "generated fixed32 packed borrowed slices encode", iters.packed_binary, generated_fixed_packed_bytes.len, packed_workloads.GeneratedFixedPackedSlicesCtx{ .message = &generated_fixed_packed }, packed_workloads.generatedFixedPackedBorrowedSlices),
        try runTimed(io, "generated fixed32 packed decode", iters.packed_binary, generated_fixed_packed_bytes.len, packed_workloads.GeneratedFixedPackedDecodeCtx{ .allocator = allocator, .bytes = generated_fixed_packed_bytes }, packed_workloads.generatedFixedPackedDecode),
        try runTimed(io, "generated fixed32 packed fast known-schema decode reuse", iters.packed_binary, generated_fixed_packed_bytes.len, packed_workloads.GeneratedFixedPackedDecodeReuseCtx{ .allocator = allocator, .bytes = generated_fixed_packed_bytes, .message = &generated_fixed_packed_decode_reuse }, packed_workloads.generatedFixedPackedKnownDecodeReuse),
        try runTimed(io, "generated fixed32 packed borrowed view decode", iters.packed_binary, generated_fixed_packed_bytes.len, packed_workloads.FixedPackedBorrowedViewCtx{ .bytes = generated_fixed_packed_bytes }, packed_workloads.fixedPackedBorrowedViewDecode),
        try runTimed(io, "dynamic fixed32 packed encode", iters.packed_binary, dynamic_fixed_packed_bytes.len, packed_workloads.DynamicFixedPackedEncodeCtx{ .message = &dynamic_fixed_packed, .file = &file }, packed_workloads.dynamicFixedPackedEncode),
        try runTimed(io, "dynamic fixed32 packed decode", iters.packed_binary, dynamic_fixed_packed_bytes.len, packed_workloads.DynamicFixedPackedDecodeCtx{ .allocator = allocator, .descriptor = fixed_packed_desc, .file = &file, .bytes = dynamic_fixed_packed_bytes }, packed_workloads.dynamicFixedPackedDecode),
        try runTimed(io, "dynamic fixed32 packed decode reuse", iters.packed_binary, dynamic_fixed_packed_bytes.len, packed_workloads.DynamicFixedPackedDecodeReuseCtx{ .message = &dynamic_fixed_packed_decode_reuse, .file = &file, .bytes = dynamic_fixed_packed_bytes }, packed_workloads.dynamicFixedPackedDecodeReuse),
        try runTimed(io, "generated fixed64 packed encode", iters.packed_binary, generated_fixed64_packed_bytes.len, packed_workloads.GeneratedFixed64PackedEncodeCtx{ .allocator = allocator, .message = &generated_fixed64_packed }, packed_workloads.generatedFixed64PackedEncode),
        try runTimed(io, "generated fixed64 packed encodeIntoAssumeCapacity buffer reuse", iters.packed_binary, generated_fixed64_packed_bytes.len, packed_workloads.GeneratedFixed64PackedEncodeIntoCtx{ .buffer = generated_fixed64_packed_buffer, .message = &generated_fixed64_packed }, packed_workloads.generatedFixed64PackedEncodeIntoReuse),
        try runTimed(io, "generated fixed64 packed borrowed slices encode", iters.packed_binary, generated_fixed64_packed_bytes.len, packed_workloads.GeneratedFixed64PackedSlicesCtx{ .message = &generated_fixed64_packed }, packed_workloads.generatedFixed64PackedBorrowedSlices),
        try runTimed(io, "generated fixed64 packed decode", iters.packed_binary, generated_fixed64_packed_bytes.len, packed_workloads.GeneratedFixed64PackedDecodeCtx{ .allocator = allocator, .bytes = generated_fixed64_packed_bytes }, packed_workloads.generatedFixed64PackedDecode),
        try runTimed(io, "generated fixed64 packed fast known-schema decode reuse", iters.packed_binary, generated_fixed64_packed_bytes.len, packed_workloads.GeneratedFixed64PackedDecodeReuseCtx{ .allocator = allocator, .bytes = generated_fixed64_packed_bytes, .message = &generated_fixed64_packed_decode_reuse }, packed_workloads.generatedFixed64PackedKnownDecodeReuse),
        try runTimed(io, "generated fixed64 packed borrowed view decode", iters.packed_binary, generated_fixed64_packed_bytes.len, packed_workloads.Fixed64PackedBorrowedViewCtx{ .bytes = generated_fixed64_packed_bytes }, packed_workloads.fixed64PackedBorrowedViewDecode),
        try runTimed(io, "dynamic fixed64 packed encode", iters.packed_binary, dynamic_fixed64_packed_bytes.len, packed_workloads.DynamicFixed64PackedEncodeCtx{ .message = &dynamic_fixed64_packed, .file = &file }, packed_workloads.dynamicFixed64PackedEncode),
        try runTimed(io, "dynamic fixed64 packed decode", iters.packed_binary, dynamic_fixed64_packed_bytes.len, packed_workloads.DynamicFixed64PackedDecodeCtx{ .allocator = allocator, .descriptor = fixed64_packed_desc, .file = &file, .bytes = dynamic_fixed64_packed_bytes }, packed_workloads.dynamicFixed64PackedDecode),
        try runTimed(io, "dynamic fixed64 packed decode reuse", iters.packed_binary, dynamic_fixed64_packed_bytes.len, packed_workloads.DynamicFixed64PackedDecodeReuseCtx{ .message = &dynamic_fixed64_packed_decode_reuse, .file = &file, .bytes = dynamic_fixed64_packed_bytes }, packed_workloads.dynamicFixed64PackedDecodeReuse),
        try runTimed(io, "generated sfixed32 packed encode", iters.packed_binary, generated_sfixed_packed_bytes.len, packed_workloads.GeneratedSFixedPackedEncodeCtx{ .allocator = allocator, .message = &generated_sfixed_packed }, packed_workloads.generatedSFixedPackedEncode),
        try runTimed(io, "generated sfixed32 packed encodeIntoAssumeCapacity buffer reuse", iters.packed_binary, generated_sfixed_packed_bytes.len, packed_workloads.GeneratedSFixedPackedEncodeIntoCtx{ .buffer = generated_sfixed_packed_buffer, .message = &generated_sfixed_packed }, packed_workloads.generatedSFixedPackedEncodeIntoReuse),
        try runTimed(io, "generated sfixed32 packed borrowed slices encode", iters.packed_binary, generated_sfixed_packed_bytes.len, packed_workloads.GeneratedSFixedPackedSlicesCtx{ .message = &generated_sfixed_packed }, packed_workloads.generatedSFixedPackedBorrowedSlices),
        try runTimed(io, "generated sfixed32 packed decode", iters.packed_binary, generated_sfixed_packed_bytes.len, packed_workloads.GeneratedSFixedPackedDecodeCtx{ .allocator = allocator, .bytes = generated_sfixed_packed_bytes }, packed_workloads.generatedSFixedPackedDecode),
        try runTimed(io, "generated sfixed32 packed fast known-schema decode reuse", iters.packed_binary, generated_sfixed_packed_bytes.len, packed_workloads.GeneratedSFixedPackedDecodeReuseCtx{ .allocator = allocator, .bytes = generated_sfixed_packed_bytes, .message = &generated_sfixed_packed_decode_reuse }, packed_workloads.generatedSFixedPackedKnownDecodeReuse),
        try runTimed(io, "generated sfixed32 packed borrowed view decode", iters.packed_binary, generated_sfixed_packed_bytes.len, packed_workloads.SFixedPackedBorrowedViewCtx{ .bytes = generated_sfixed_packed_bytes }, packed_workloads.sfixedPackedBorrowedViewDecode),
        try runTimed(io, "dynamic sfixed32 packed encode", iters.packed_binary, dynamic_sfixed_packed_bytes.len, packed_workloads.DynamicSFixedPackedEncodeCtx{ .message = &dynamic_sfixed_packed, .file = &file }, packed_workloads.dynamicSFixedPackedEncode),
        try runTimed(io, "dynamic sfixed32 packed decode", iters.packed_binary, dynamic_sfixed_packed_bytes.len, packed_workloads.DynamicSFixedPackedDecodeCtx{ .allocator = allocator, .descriptor = sfixed_packed_desc, .file = &file, .bytes = dynamic_sfixed_packed_bytes }, packed_workloads.dynamicSFixedPackedDecode),
        try runTimed(io, "dynamic sfixed32 packed decode reuse", iters.packed_binary, dynamic_sfixed_packed_bytes.len, packed_workloads.DynamicSFixedPackedDecodeReuseCtx{ .message = &dynamic_sfixed_packed_decode_reuse, .file = &file, .bytes = dynamic_sfixed_packed_bytes }, packed_workloads.dynamicSFixedPackedDecodeReuse),
        try runTimed(io, "generated sfixed64 packed encode", iters.packed_binary, generated_sfixed64_packed_bytes.len, packed_workloads.GeneratedSFixed64PackedEncodeCtx{ .allocator = allocator, .message = &generated_sfixed64_packed }, packed_workloads.generatedSFixed64PackedEncode),
        try runTimed(io, "generated sfixed64 packed encodeIntoAssumeCapacity buffer reuse", iters.packed_binary, generated_sfixed64_packed_bytes.len, packed_workloads.GeneratedSFixed64PackedEncodeIntoCtx{ .buffer = generated_sfixed64_packed_buffer, .message = &generated_sfixed64_packed }, packed_workloads.generatedSFixed64PackedEncodeIntoReuse),
        try runTimed(io, "generated sfixed64 packed borrowed slices encode", iters.packed_binary, generated_sfixed64_packed_bytes.len, packed_workloads.GeneratedSFixed64PackedSlicesCtx{ .message = &generated_sfixed64_packed }, packed_workloads.generatedSFixed64PackedBorrowedSlices),
        try runTimed(io, "generated sfixed64 packed decode", iters.packed_binary, generated_sfixed64_packed_bytes.len, packed_workloads.GeneratedSFixed64PackedDecodeCtx{ .allocator = allocator, .bytes = generated_sfixed64_packed_bytes }, packed_workloads.generatedSFixed64PackedDecode),
        try runTimed(io, "generated sfixed64 packed fast known-schema decode reuse", iters.packed_binary, generated_sfixed64_packed_bytes.len, packed_workloads.GeneratedSFixed64PackedDecodeReuseCtx{ .allocator = allocator, .bytes = generated_sfixed64_packed_bytes, .message = &generated_sfixed64_packed_decode_reuse }, packed_workloads.generatedSFixed64PackedKnownDecodeReuse),
        try runTimed(io, "generated sfixed64 packed borrowed view decode", iters.packed_binary, generated_sfixed64_packed_bytes.len, packed_workloads.SFixed64PackedBorrowedViewCtx{ .bytes = generated_sfixed64_packed_bytes }, packed_workloads.sfixed64PackedBorrowedViewDecode),
        try runTimed(io, "dynamic sfixed64 packed encode", iters.packed_binary, dynamic_sfixed64_packed_bytes.len, packed_workloads.DynamicSFixed64PackedEncodeCtx{ .message = &dynamic_sfixed64_packed, .file = &file }, packed_workloads.dynamicSFixed64PackedEncode),
        try runTimed(io, "dynamic sfixed64 packed decode", iters.packed_binary, dynamic_sfixed64_packed_bytes.len, packed_workloads.DynamicSFixed64PackedDecodeCtx{ .allocator = allocator, .descriptor = sfixed64_packed_desc, .file = &file, .bytes = dynamic_sfixed64_packed_bytes }, packed_workloads.dynamicSFixed64PackedDecode),
        try runTimed(io, "dynamic sfixed64 packed decode reuse", iters.packed_binary, dynamic_sfixed64_packed_bytes.len, packed_workloads.DynamicSFixed64PackedDecodeReuseCtx{ .message = &dynamic_sfixed64_packed_decode_reuse, .file = &file, .bytes = dynamic_sfixed64_packed_bytes }, packed_workloads.dynamicSFixed64PackedDecodeReuse),
        try runTimed(io, "generated float packed encode", iters.packed_binary, generated_float_packed_bytes.len, packed_workloads.GeneratedFloatPackedEncodeCtx{ .allocator = allocator, .message = &generated_float_packed }, packed_workloads.generatedFloatPackedEncode),
        try runTimed(io, "generated float packed encodeIntoAssumeCapacity buffer reuse", iters.packed_binary, generated_float_packed_bytes.len, packed_workloads.GeneratedFloatPackedEncodeIntoCtx{ .buffer = generated_float_packed_buffer, .message = &generated_float_packed }, packed_workloads.generatedFloatPackedEncodeIntoReuse),
        try runTimed(io, "generated float packed borrowed slices encode", iters.packed_binary, generated_float_packed_bytes.len, packed_workloads.GeneratedFloatPackedSlicesCtx{ .message = &generated_float_packed }, packed_workloads.generatedFloatPackedBorrowedSlices),
        try runTimed(io, "generated float packed decode", iters.packed_binary, generated_float_packed_bytes.len, packed_workloads.GeneratedFloatPackedDecodeCtx{ .allocator = allocator, .bytes = generated_float_packed_bytes }, packed_workloads.generatedFloatPackedDecode),
        try runTimed(io, "generated float packed fast known-schema decode reuse", iters.packed_binary, generated_float_packed_bytes.len, packed_workloads.GeneratedFloatPackedDecodeReuseCtx{ .allocator = allocator, .bytes = generated_float_packed_bytes, .message = &generated_float_packed_decode_reuse }, packed_workloads.generatedFloatPackedKnownDecodeReuse),
        try runTimed(io, "generated float packed borrowed view decode", iters.packed_binary, generated_float_packed_bytes.len, packed_workloads.FloatPackedBorrowedViewCtx{ .bytes = generated_float_packed_bytes }, packed_workloads.floatPackedBorrowedViewDecode),
        try runTimed(io, "dynamic float packed encode", iters.packed_binary, dynamic_float_packed_bytes.len, packed_workloads.DynamicFloatPackedEncodeCtx{ .message = &dynamic_float_packed, .file = &file }, packed_workloads.dynamicFloatPackedEncode),
        try runTimed(io, "dynamic float packed decode", iters.packed_binary, dynamic_float_packed_bytes.len, packed_workloads.DynamicFloatPackedDecodeCtx{ .allocator = allocator, .descriptor = float_packed_desc, .file = &file, .bytes = dynamic_float_packed_bytes }, packed_workloads.dynamicFloatPackedDecode),
        try runTimed(io, "dynamic float packed decode reuse", iters.packed_binary, dynamic_float_packed_bytes.len, packed_workloads.DynamicFloatPackedDecodeReuseCtx{ .message = &dynamic_float_packed_decode_reuse, .file = &file, .bytes = dynamic_float_packed_bytes }, packed_workloads.dynamicFloatPackedDecodeReuse),
        try runTimed(io, "generated double packed encode", iters.packed_binary, generated_double_packed_bytes.len, packed_workloads.GeneratedDoublePackedEncodeCtx{ .allocator = allocator, .message = &generated_double_packed }, packed_workloads.generatedDoublePackedEncode),
        try runTimed(io, "generated double packed encodeIntoAssumeCapacity buffer reuse", iters.packed_binary, generated_double_packed_bytes.len, packed_workloads.GeneratedDoublePackedEncodeIntoCtx{ .buffer = generated_double_packed_buffer, .message = &generated_double_packed }, packed_workloads.generatedDoublePackedEncodeIntoReuse),
        try runTimed(io, "generated double packed borrowed slices encode", iters.packed_binary, generated_double_packed_bytes.len, packed_workloads.GeneratedDoublePackedSlicesCtx{ .message = &generated_double_packed }, packed_workloads.generatedDoublePackedBorrowedSlices),
        try runTimed(io, "generated double packed decode", iters.packed_binary, generated_double_packed_bytes.len, packed_workloads.GeneratedDoublePackedDecodeCtx{ .allocator = allocator, .bytes = generated_double_packed_bytes }, packed_workloads.generatedDoublePackedDecode),
        try runTimed(io, "generated double packed fast known-schema decode reuse", iters.packed_binary, generated_double_packed_bytes.len, packed_workloads.GeneratedDoublePackedDecodeReuseCtx{ .allocator = allocator, .bytes = generated_double_packed_bytes, .message = &generated_double_packed_decode_reuse }, packed_workloads.generatedDoublePackedKnownDecodeReuse),
        try runTimed(io, "generated double packed borrowed view decode", iters.packed_binary, generated_double_packed_bytes.len, packed_workloads.DoublePackedBorrowedViewCtx{ .bytes = generated_double_packed_bytes }, packed_workloads.doublePackedBorrowedViewDecode),
        try runTimed(io, "dynamic double packed encode", iters.packed_binary, dynamic_double_packed_bytes.len, packed_workloads.DynamicDoublePackedEncodeCtx{ .message = &dynamic_double_packed, .file = &file }, packed_workloads.dynamicDoublePackedEncode),
        try runTimed(io, "dynamic double packed decode", iters.packed_binary, dynamic_double_packed_bytes.len, packed_workloads.DynamicDoublePackedDecodeCtx{ .allocator = allocator, .descriptor = double_packed_desc, .file = &file, .bytes = dynamic_double_packed_bytes }, packed_workloads.dynamicDoublePackedDecode),
        try runTimed(io, "dynamic double packed decode reuse", iters.packed_binary, dynamic_double_packed_bytes.len, packed_workloads.DynamicDoublePackedDecodeReuseCtx{ .message = &dynamic_double_packed_decode_reuse, .file = &file, .bytes = dynamic_double_packed_bytes }, packed_workloads.dynamicDoublePackedDecodeReuse),
        try runTimed(io, "generated uint64 packed encode", iters.packed_binary, generated_uint64_packed_bytes.len, packed_workloads.GeneratedUInt64PackedEncodeCtx{ .allocator = allocator, .message = &generated_uint64_packed }, packed_workloads.generatedUInt64PackedEncode),
        try runTimed(io, "generated uint64 packed encodeIntoAssumeCapacity buffer reuse", iters.packed_binary, generated_uint64_packed_bytes.len, packed_workloads.GeneratedUInt64PackedEncodeIntoCtx{ .buffer = generated_uint64_packed_buffer, .message = &generated_uint64_packed }, packed_workloads.generatedUInt64PackedEncodeIntoReuse),
        try runTimed(io, "generated uint64 packed decode", iters.packed_binary, generated_uint64_packed_bytes.len, packed_workloads.GeneratedUInt64PackedDecodeCtx{ .allocator = allocator, .bytes = generated_uint64_packed_bytes }, packed_workloads.generatedUInt64PackedDecode),
        try runTimed(io, "generated uint64 packed decode reuse", iters.packed_binary, generated_uint64_packed_bytes.len, packed_workloads.GeneratedUInt64PackedDecodeReuseCtx{ .allocator = allocator, .bytes = generated_uint64_packed_bytes, .message = &generated_uint64_packed_decode_reuse }, packed_workloads.generatedUInt64PackedDecodeReuse),
        try runTimed(io, "generated uint64 packed fast known-schema decode reuse", iters.packed_binary, generated_uint64_packed_bytes.len, packed_workloads.GeneratedUInt64PackedDecodeReuseCtx{ .allocator = allocator, .bytes = generated_uint64_packed_bytes, .message = &generated_uint64_packed_decode_reuse }, packed_workloads.generatedUInt64PackedKnownDecodeReuse),
        try runTimed(io, "generated uint64 packed iterator decode", iters.packed_binary, generated_uint64_packed_bytes.len, packed_workloads.UInt64PackedIteratorCtx{ .bytes = generated_uint64_packed_bytes }, packed_workloads.uint64PackedIteratorDecode),
        try runTimed(io, "dynamic uint64 packed encode", iters.packed_binary, dynamic_uint64_packed_bytes.len, packed_workloads.DynamicUInt64PackedEncodeCtx{ .message = &dynamic_uint64_packed, .file = &file }, packed_workloads.dynamicUInt64PackedEncode),
        try runTimed(io, "dynamic uint64 packed decode", iters.packed_binary, dynamic_uint64_packed_bytes.len, packed_workloads.DynamicUInt64PackedDecodeCtx{ .allocator = allocator, .descriptor = uint64_packed_desc, .file = &file, .bytes = dynamic_uint64_packed_bytes }, packed_workloads.dynamicUInt64PackedDecode),
        try runTimed(io, "generated uint32 packed encode", iters.packed_binary, generated_uint32_packed_bytes.len, packed_workloads.GeneratedUInt32PackedEncodeCtx{ .allocator = allocator, .message = &generated_uint32_packed }, packed_workloads.generatedUInt32PackedEncode),
        try runTimed(io, "generated uint32 packed encodeIntoAssumeCapacity buffer reuse", iters.packed_binary, generated_uint32_packed_bytes.len, packed_workloads.GeneratedUInt32PackedEncodeIntoCtx{ .buffer = generated_uint32_packed_buffer, .message = &generated_uint32_packed }, packed_workloads.generatedUInt32PackedEncodeIntoReuse),
        try runTimed(io, "generated uint32 packed decode", iters.packed_binary, generated_uint32_packed_bytes.len, packed_workloads.GeneratedUInt32PackedDecodeCtx{ .allocator = allocator, .bytes = generated_uint32_packed_bytes }, packed_workloads.generatedUInt32PackedDecode),
        try runTimed(io, "generated uint32 packed decode reuse", iters.packed_binary, generated_uint32_packed_bytes.len, packed_workloads.GeneratedUInt32PackedDecodeReuseCtx{ .allocator = allocator, .bytes = generated_uint32_packed_bytes, .message = &generated_uint32_packed_decode_reuse }, packed_workloads.generatedUInt32PackedDecodeReuse),
        try runTimed(io, "generated uint32 packed fast known-schema decode reuse", iters.packed_binary, generated_uint32_packed_bytes.len, packed_workloads.GeneratedUInt32PackedDecodeReuseCtx{ .allocator = allocator, .bytes = generated_uint32_packed_bytes, .message = &generated_uint32_packed_decode_reuse }, packed_workloads.generatedUInt32PackedKnownDecodeReuse),
        try runTimed(io, "generated uint32 packed iterator decode", iters.packed_binary, generated_uint32_packed_bytes.len, packed_workloads.UInt32PackedIteratorCtx{ .bytes = generated_uint32_packed_bytes }, packed_workloads.uint32PackedIteratorDecode),
        try runTimed(io, "dynamic uint32 packed encode", iters.packed_binary, dynamic_uint32_packed_bytes.len, packed_workloads.DynamicUInt32PackedEncodeCtx{ .message = &dynamic_uint32_packed, .file = &file }, packed_workloads.dynamicUInt32PackedEncode),
        try runTimed(io, "dynamic uint32 packed decode", iters.packed_binary, dynamic_uint32_packed_bytes.len, packed_workloads.DynamicUInt32PackedDecodeCtx{ .allocator = allocator, .descriptor = uint32_packed_desc, .file = &file, .bytes = dynamic_uint32_packed_bytes }, packed_workloads.dynamicUInt32PackedDecode),
        try runTimed(io, "generated int64 packed encode", iters.packed_binary, generated_int64_packed_bytes.len, packed_workloads.GeneratedInt64PackedEncodeCtx{ .allocator = allocator, .message = &generated_int64_packed }, packed_workloads.generatedInt64PackedEncode),
        try runTimed(io, "generated int64 packed encodeIntoAssumeCapacity buffer reuse", iters.packed_binary, generated_int64_packed_bytes.len, packed_workloads.GeneratedInt64PackedEncodeIntoCtx{ .buffer = generated_int64_packed_buffer, .message = &generated_int64_packed }, packed_workloads.generatedInt64PackedEncodeIntoReuse),
        try runTimed(io, "generated int64 packed decode", iters.packed_binary, generated_int64_packed_bytes.len, packed_workloads.GeneratedInt64PackedDecodeCtx{ .allocator = allocator, .bytes = generated_int64_packed_bytes }, packed_workloads.generatedInt64PackedDecode),
        try runTimed(io, "generated int64 packed fast known-schema decode reuse", iters.packed_binary, generated_int64_packed_bytes.len, packed_workloads.GeneratedInt64PackedDecodeReuseCtx{ .allocator = allocator, .bytes = generated_int64_packed_bytes, .message = &generated_int64_packed_decode_reuse }, packed_workloads.generatedInt64PackedKnownDecodeReuse),
        try runTimed(io, "generated int64 packed iterator decode", iters.packed_binary, generated_int64_packed_bytes.len, packed_workloads.Int64PackedIteratorCtx{ .bytes = generated_int64_packed_bytes }, packed_workloads.int64PackedIteratorDecode),
        try runTimed(io, "dynamic int64 packed encode", iters.packed_binary, dynamic_int64_packed_bytes.len, packed_workloads.DynamicInt64PackedEncodeCtx{ .message = &dynamic_int64_packed, .file = &file }, packed_workloads.dynamicInt64PackedEncode),
        try runTimed(io, "dynamic int64 packed decode", iters.packed_binary, dynamic_int64_packed_bytes.len, packed_workloads.DynamicInt64PackedDecodeCtx{ .allocator = allocator, .descriptor = int64_packed_desc, .file = &file, .bytes = dynamic_int64_packed_bytes }, packed_workloads.dynamicInt64PackedDecode),
        try runTimed(io, "generated sint32 packed encode", iters.packed_binary, generated_sint32_packed_bytes.len, packed_workloads.GeneratedSInt32PackedEncodeCtx{ .allocator = allocator, .message = &generated_sint32_packed }, packed_workloads.generatedSInt32PackedEncode),
        try runTimed(io, "generated sint32 packed encodeIntoAssumeCapacity buffer reuse", iters.packed_binary, generated_sint32_packed_bytes.len, packed_workloads.GeneratedSInt32PackedEncodeIntoCtx{ .buffer = generated_sint32_packed_buffer, .message = &generated_sint32_packed }, packed_workloads.generatedSInt32PackedEncodeIntoReuse),
        try runTimed(io, "generated sint32 packed decode", iters.packed_binary, generated_sint32_packed_bytes.len, packed_workloads.GeneratedSInt32PackedDecodeCtx{ .allocator = allocator, .bytes = generated_sint32_packed_bytes }, packed_workloads.generatedSInt32PackedDecode),
        try runTimed(io, "generated sint32 packed fast known-schema decode reuse", iters.packed_binary, generated_sint32_packed_bytes.len, packed_workloads.GeneratedSInt32PackedDecodeReuseCtx{ .allocator = allocator, .bytes = generated_sint32_packed_bytes, .message = &generated_sint32_packed_decode_reuse }, packed_workloads.generatedSInt32PackedKnownDecodeReuse),
        try runTimed(io, "generated sint32 packed iterator decode", iters.packed_binary, generated_sint32_packed_bytes.len, packed_workloads.SInt32PackedIteratorCtx{ .bytes = generated_sint32_packed_bytes }, packed_workloads.sint32PackedIteratorDecode),
        try runTimed(io, "dynamic sint32 packed encode", iters.packed_binary, dynamic_sint32_packed_bytes.len, packed_workloads.DynamicSInt32PackedEncodeCtx{ .message = &dynamic_sint32_packed, .file = &file }, packed_workloads.dynamicSInt32PackedEncode),
        try runTimed(io, "dynamic sint32 packed decode", iters.packed_binary, dynamic_sint32_packed_bytes.len, packed_workloads.DynamicSInt32PackedDecodeCtx{ .allocator = allocator, .descriptor = sint32_packed_desc, .file = &file, .bytes = dynamic_sint32_packed_bytes }, packed_workloads.dynamicSInt32PackedDecode),
        try runTimed(io, "generated sint64 packed encode", iters.packed_binary, generated_sint64_packed_bytes.len, packed_workloads.GeneratedSInt64PackedEncodeCtx{ .allocator = allocator, .message = &generated_sint64_packed }, packed_workloads.generatedSInt64PackedEncode),
        try runTimed(io, "generated sint64 packed encodeIntoAssumeCapacity buffer reuse", iters.packed_binary, generated_sint64_packed_bytes.len, packed_workloads.GeneratedSInt64PackedEncodeIntoCtx{ .buffer = generated_sint64_packed_buffer, .message = &generated_sint64_packed }, packed_workloads.generatedSInt64PackedEncodeIntoReuse),
        try runTimed(io, "generated sint64 packed decode", iters.packed_binary, generated_sint64_packed_bytes.len, packed_workloads.GeneratedSInt64PackedDecodeCtx{ .allocator = allocator, .bytes = generated_sint64_packed_bytes }, packed_workloads.generatedSInt64PackedDecode),
        try runTimed(io, "generated sint64 packed fast known-schema decode reuse", iters.packed_binary, generated_sint64_packed_bytes.len, packed_workloads.GeneratedSInt64PackedDecodeReuseCtx{ .allocator = allocator, .bytes = generated_sint64_packed_bytes, .message = &generated_sint64_packed_decode_reuse }, packed_workloads.generatedSInt64PackedKnownDecodeReuse),
        try runTimed(io, "generated sint64 packed iterator decode", iters.packed_binary, generated_sint64_packed_bytes.len, packed_workloads.SInt64PackedIteratorCtx{ .bytes = generated_sint64_packed_bytes }, packed_workloads.sint64PackedIteratorDecode),
        try runTimed(io, "dynamic sint64 packed encode", iters.packed_binary, dynamic_sint64_packed_bytes.len, packed_workloads.DynamicSInt64PackedEncodeCtx{ .message = &dynamic_sint64_packed, .file = &file }, packed_workloads.dynamicSInt64PackedEncode),
        try runTimed(io, "dynamic sint64 packed decode", iters.packed_binary, dynamic_sint64_packed_bytes.len, packed_workloads.DynamicSInt64PackedDecodeCtx{ .allocator = allocator, .descriptor = sint64_packed_desc, .file = &file, .bytes = dynamic_sint64_packed_bytes }, packed_workloads.dynamicSInt64PackedDecode),
        try runTimed(io, "generated bool packed encode", iters.packed_binary, generated_bool_packed_bytes.len, packed_workloads.GeneratedBoolPackedEncodeCtx{ .allocator = allocator, .message = &generated_bool_packed }, packed_workloads.generatedBoolPackedEncode),
        try runTimed(io, "generated bool packed encodeIntoAssumeCapacity buffer reuse", iters.packed_binary, generated_bool_packed_bytes.len, packed_workloads.GeneratedBoolPackedEncodeIntoCtx{ .buffer = generated_bool_packed_buffer, .message = &generated_bool_packed }, packed_workloads.generatedBoolPackedEncodeIntoReuse),
        try runTimed(io, "generated bool packed borrowed slices encode", iters.packed_binary, generated_bool_packed_bytes.len, packed_workloads.GeneratedBoolPackedSlicesCtx{ .message = &generated_bool_packed }, packed_workloads.generatedBoolPackedBorrowedSlices),
        try runTimed(io, "generated bool packed decode", iters.packed_binary, generated_bool_packed_bytes.len, packed_workloads.GeneratedBoolPackedDecodeCtx{ .allocator = allocator, .bytes = generated_bool_packed_bytes }, packed_workloads.generatedBoolPackedDecode),
        try runTimed(io, "generated bool packed fast known-schema decode reuse", iters.packed_binary, generated_bool_packed_bytes.len, packed_workloads.GeneratedBoolPackedDecodeReuseCtx{ .allocator = allocator, .bytes = generated_bool_packed_bytes, .message = &generated_bool_packed_decode_reuse }, packed_workloads.generatedBoolPackedKnownDecodeReuse),
        try runTimed(io, "dynamic bool packed encode", iters.packed_binary, dynamic_bool_packed_bytes.len, packed_workloads.DynamicBoolPackedEncodeCtx{ .message = &dynamic_bool_packed, .file = &file }, packed_workloads.dynamicBoolPackedEncode),
        try runTimed(io, "dynamic bool packed decode", iters.packed_binary, dynamic_bool_packed_bytes.len, packed_workloads.DynamicBoolPackedDecodeCtx{ .allocator = allocator, .descriptor = bool_packed_desc, .file = &file, .bytes = dynamic_bool_packed_bytes }, packed_workloads.dynamicBoolPackedDecode),
        try runTimed(io, "generated enum packed encode", iters.packed_binary, generated_enum_packed_bytes.len, packed_workloads.GeneratedEnumPackedEncodeCtx{ .allocator = allocator, .message = &generated_enum_packed }, packed_workloads.generatedEnumPackedEncode),
        try runTimed(io, "generated enum packed encodeIntoAssumeCapacity buffer reuse", iters.packed_binary, generated_enum_packed_bytes.len, packed_workloads.GeneratedEnumPackedEncodeIntoCtx{ .buffer = generated_enum_packed_buffer, .message = &generated_enum_packed }, packed_workloads.generatedEnumPackedEncodeIntoReuse),
        try runTimed(io, "generated enum packed decode", iters.packed_binary, generated_enum_packed_bytes.len, packed_workloads.GeneratedEnumPackedDecodeCtx{ .allocator = allocator, .bytes = generated_enum_packed_bytes }, packed_workloads.generatedEnumPackedDecode),
        try runTimed(io, "generated enum packed decode reuse", iters.packed_binary, generated_enum_packed_bytes.len, packed_workloads.GeneratedEnumPackedDecodeReuseCtx{ .allocator = allocator, .bytes = generated_enum_packed_bytes, .message = &generated_enum_packed_decode_reuse }, packed_workloads.generatedEnumPackedDecodeReuse),
        try runTimed(io, "generated enum packed fast known-schema decode reuse", iters.packed_binary, generated_enum_packed_bytes.len, packed_workloads.GeneratedEnumPackedDecodeReuseCtx{ .allocator = allocator, .bytes = generated_enum_packed_bytes, .message = &generated_enum_packed_decode_reuse }, packed_workloads.generatedEnumPackedKnownDecodeReuse),
        try runTimed(io, "dynamic enum packed encode", iters.packed_binary, dynamic_enum_packed_bytes.len, packed_workloads.DynamicEnumPackedEncodeCtx{ .message = &dynamic_enum_packed, .file = &file }, packed_workloads.dynamicEnumPackedEncode),
        try runTimed(io, "dynamic enum packed decode", iters.packed_binary, dynamic_enum_packed_bytes.len, packed_workloads.DynamicEnumPackedDecodeCtx{ .allocator = allocator, .descriptor = enum_packed_desc, .file = &file, .bytes = dynamic_enum_packed_bytes }, packed_workloads.dynamicEnumPackedDecode),
        try runTimed(io, "generated large map encode", iters.large_map, generated_large_map_bytes.len, maps.GeneratedLargeMapEncodeCtx{ .allocator = allocator, .message = &generated_large_map }, maps.generatedLargeMapEncode),
        try runTimed(io, "generated large map writeToAssumeCapacity reuse", iters.large_map, generated_large_map_bytes.len, maps.GeneratedLargeMapWriteToCtx{ .writer = &reusable_large_map_writer, .message = &generated_large_map }, maps.generatedLargeMapWriteToReuse),
        try runTimed(io, "generated large map encodeIntoAssumeCapacity buffer reuse", iters.large_map, generated_large_map_bytes.len, maps.GeneratedLargeMapEncodeIntoCtx{ .buffer = generated_large_map_buffer, .message = &generated_large_map }, maps.generatedLargeMapEncodeIntoReuse),
        try runTimed(io, "generated large map deterministic encodeIntoAssumeCapacity buffer reuse", iters.large_map, generated_large_map_bytes.len, maps.GeneratedLargeMapDeterministicEncodeIntoCtx{ .allocator = allocator, .buffer = generated_large_map_buffer, .message = &generated_large_map }, maps.generatedLargeMapDeterministicEncodeIntoReuse),
        try runTimed(io, "generated shuffled large map deterministic encodeIntoAssumeCapacity buffer reuse", iters.large_map, generated_shuffled_large_map_bytes.len, maps.GeneratedLargeMapDeterministicEncodeIntoCtx{ .allocator = allocator, .buffer = generated_shuffled_large_map_buffer, .message = &generated_shuffled_large_map }, maps.generatedLargeMapDeterministicEncodeIntoReuse),
        try runTimed(io, "generated large map decode", iters.large_map, generated_large_map_bytes.len, maps.GeneratedLargeMapDecodeCtx{ .allocator = allocator, .bytes = generated_large_map_bytes }, maps.generatedLargeMapDecode),
        try runTimed(io, "generated large map decode owned", iters.large_map, generated_large_map_bytes.len, maps.GeneratedLargeMapDecodeOwnedCtx{ .allocator = allocator, .bytes = generated_large_map_bytes }, maps.generatedLargeMapDecodeOwned),
        try runTimed(io, "generated large map decode reuse", iters.large_map, generated_large_map_bytes.len, maps.GeneratedLargeMapDecodeReuseCtx{ .allocator = allocator, .bytes = generated_large_map_bytes, .message = &generated_large_map_decode_reuse }, maps.generatedLargeMapDecodeReuse),
        try runTimed(io, "generated large map decode owned reuse", iters.large_map, generated_large_map_bytes.len, maps.GeneratedLargeMapDecodeOwnedReuseCtx{ .allocator = allocator, .bytes = generated_large_map_bytes, .message = &generated_large_map_decode_reuse }, maps.generatedLargeMapDecodeOwnedReuse),
        try runTimed(io, "generated LargeMap JSON stringify", iters.large_map, generated_large_map_json.len, json.GeneratedLargeMapJsonStringifyCtx{ .allocator = allocator, .message = &generated_large_map }, json.generatedLargeMapJsonStringify),
        try runTimed(io, "generated LargeMap JSON parse", iters.large_map, generated_large_map_json.len, json.GeneratedLargeMapJsonParseCtx{ .allocator = allocator, .json = generated_large_map_json }, json.generatedLargeMapJsonParse),
        try runTimed(io, "dynamic large map encode", iters.large_map, dynamic_large_map_bytes.len, dynamic.DynamicLargeMapEncodeCtx{ .message = &dynamic_large_map, .file = &file }, dynamic.dynamicLargeMapEncode),
        try runTimed(io, "dynamic large map decode", iters.large_map, dynamic_large_map_bytes.len, dynamic.DynamicLargeMapDecodeCtx{ .allocator = allocator, .descriptor = large_map_desc, .file = &file, .bytes = dynamic_large_map_bytes }, dynamic.dynamicLargeMapDecode),
        try runTimed(io, "generated JSON stringify", iters.json, generated_json.len, json.GeneratedJsonStringifyCtx{ .allocator = allocator, .person = &generated_person }, json.generatedJsonStringify),
        try runTimed(io, "generated AlwaysPrint JSON stringify", iters.json, generated_always_print_json.len, json.GeneratedJsonStringifyCtx{ .allocator = allocator, .person = &generated_empty_person }, json.generatedAlwaysPrintJsonStringify),
        try runTimed(io, "generated ScalarMix JSON stringify", iters.json, generated_scalar_mix_json.len, json.GeneratedScalarMixJsonStringifyCtx{ .allocator = allocator, .message = &generated_scalar_mix }, json.generatedScalarMixJsonStringify),
        try runTimed(io, "generated ProtoName JSON stringify", iters.json, generated_proto_name_json.len, json.GeneratedScalarMixJsonStringifyCtx{ .allocator = allocator, .message = &generated_scalar_mix }, json.generatedScalarMixProtoNameJsonStringify),
        try runTimed(io, "generated EnumNumber JSON stringify", iters.json, generated_enum_number_json.len, json.GeneratedScalarMixJsonStringifyCtx{ .allocator = allocator, .message = &generated_scalar_mix }, json.generatedScalarMixEnumNumberJsonStringify),
        try runTimed(io, "generated JSON parse", iters.json, generated_json.len, json.GeneratedJsonParseCtx{ .allocator = allocator, .json = generated_json }, json.generatedJsonParse),
        try runTimed(io, "generated MapKeySurrogate JSON parse", iters.json, json.GeneratedMapKeySurrogateJson.len, json.GeneratedJsonParseCtx{ .allocator = allocator, .json = json.GeneratedMapKeySurrogateJson }, json.generatedJsonParse),
        try runTimed(io, "generated NullFields JSON parse", iters.json, json.GeneratedNullFieldsJson.len, json.GeneratedJsonParseCtx{ .allocator = allocator, .json = json.GeneratedNullFieldsJson }, json.generatedJsonParse),
        try runTimed(io, "generated IgnoreUnknown JSON parse", iters.json, json.GeneratedIgnoreUnknownJson.len, json.GeneratedJsonParseCtx{ .allocator = allocator, .json = json.GeneratedIgnoreUnknownJson }, json.generatedIgnoreUnknownJsonParse),
        try runTimed(io, "generated OpenEnum JSON parse", iters.json, json.GeneratedOpenEnumJson.len, json.GeneratedScalarMixJsonParseCtx{ .allocator = allocator, .json = json.GeneratedOpenEnumJson }, json.generatedScalarMixJsonParse),
        try runTimed(io, "generated EnumName JSON parse", iters.json, json.GeneratedEnumNameJson.len, json.GeneratedScalarMixJsonParseCtx{ .allocator = allocator, .json = json.GeneratedEnumNameJson }, json.generatedScalarMixJsonParse),
        try runTimed(io, "generated ScalarMix JSON parse", iters.json, generated_scalar_mix_json.len, json.GeneratedScalarMixJsonParseCtx{ .allocator = allocator, .json = generated_scalar_mix_json }, json.generatedScalarMixJsonParse),
        try runTimed(io, "generated ProtoName JSON parse", iters.json, json.GeneratedProtoNameJson.len, json.GeneratedScalarMixJsonParseCtx{ .allocator = allocator, .json = json.GeneratedProtoNameJson }, json.generatedScalarMixJsonParse),
        try runTimed(io, "generated IntExponent JSON parse", iters.json, json.GeneratedIntExponentJson.len, json.GeneratedScalarMixJsonParseCtx{ .allocator = allocator, .json = json.GeneratedIntExponentJson }, json.generatedScalarMixJsonParse),
        try runTimed(io, "generated StringNumber JSON parse", iters.json, json.GeneratedStringNumberJson.len, json.GeneratedScalarMixJsonParseCtx{ .allocator = allocator, .json = json.GeneratedStringNumberJson }, json.generatedScalarMixJsonParse),
        try runTimed(io, "dynamic JSON stringify", iters.json, dynamic_json.len, json.DynamicJsonStringifyCtx{ .allocator = allocator, .file = &file, .message = &dynamic_person }, json.dynamicJsonStringify),
        try runTimed(io, "dynamic JSON parse", iters.json, dynamic_json.len, json.DynamicJsonParseCtx{ .allocator = allocator, .file = &file, .descriptor = desc, .json = dynamic_json }, json.dynamicJsonParse),
        try runTimed(io, "pbz Any WKT JSON stringify", iters.json, any_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any WKT JSON parse", iters.json, any_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any Duration Escape WKT JSON parse", iters.json, json.AnyDurationEscapeWktJson.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = json.AnyDurationEscapeWktJson }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any PlusDuration WKT JSON parse", iters.json, json.AnyPlusDurationWktJson.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = json.AnyPlusDurationWktJson }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any ShortFractionDuration WKT JSON parse", iters.json, json.AnyShortFractionDurationWktJson.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = json.AnyShortFractionDurationWktJson }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any MicroDuration WKT JSON stringify", iters.json, any_micro_duration_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_micro_duration_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any MicroDuration WKT JSON parse", iters.json, any_micro_duration_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_micro_duration_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any NanoDuration WKT JSON stringify", iters.json, any_nano_duration_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_nano_duration_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any NanoDuration WKT JSON parse", iters.json, any_nano_duration_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_nano_duration_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any NegativeDuration WKT JSON stringify", iters.json, any_negative_duration_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_negative_duration_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any NegativeDuration WKT JSON parse", iters.json, any_negative_duration_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_negative_duration_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any FractionalNegativeDuration WKT JSON stringify", iters.json, any_fractional_negative_duration_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_fractional_negative_duration_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any FractionalNegativeDuration WKT JSON parse", iters.json, any_fractional_negative_duration_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_fractional_negative_duration_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any MaxDuration WKT JSON stringify", iters.json, any_max_duration_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_max_duration_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any MaxDuration WKT JSON parse", iters.json, any_max_duration_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_max_duration_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any MinDuration WKT JSON stringify", iters.json, any_min_duration_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_min_duration_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any MinDuration WKT JSON parse", iters.json, any_min_duration_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_min_duration_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any ZeroDuration WKT JSON stringify", iters.json, any_zero_duration_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_zero_duration_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any ZeroDuration WKT JSON parse", iters.json, any_zero_duration_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_zero_duration_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any FieldMask WKT JSON stringify", iters.json, any_field_mask_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_field_mask_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any FieldMask WKT JSON parse", iters.json, any_field_mask_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_field_mask_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any FieldMask Escape WKT JSON parse", iters.json, json.AnyFieldMaskEscapeWktJson.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = json.AnyFieldMaskEscapeWktJson }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any EmptyFieldMask WKT JSON stringify", iters.json, any_empty_field_mask_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_empty_field_mask_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any EmptyFieldMask WKT JSON parse", iters.json, any_empty_field_mask_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_empty_field_mask_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any Timestamp WKT JSON stringify", iters.json, any_timestamp_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_timestamp_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any Timestamp WKT JSON parse", iters.json, any_timestamp_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_timestamp_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any Timestamp Escape WKT JSON parse", iters.json, json.AnyTimestampEscapeWktJson.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = json.AnyTimestampEscapeWktJson }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any ShortFraction Timestamp WKT JSON parse", iters.json, json.AnyShortFractionTimestampWktJson.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = json.AnyShortFractionTimestampWktJson }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any Micro Timestamp WKT JSON stringify", iters.json, any_micro_timestamp_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_micro_timestamp_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any Micro Timestamp WKT JSON parse", iters.json, any_micro_timestamp_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_micro_timestamp_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any Nano Timestamp WKT JSON stringify", iters.json, any_nano_timestamp_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_nano_timestamp_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any Nano Timestamp WKT JSON parse", iters.json, any_nano_timestamp_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_nano_timestamp_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any Offset Timestamp WKT JSON parse", iters.json, json.AnyOffsetTimestampWktJson.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = json.AnyOffsetTimestampWktJson }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any PreEpoch Timestamp WKT JSON stringify", iters.json, any_pre_epoch_timestamp_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_pre_epoch_timestamp_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any PreEpoch Timestamp WKT JSON parse", iters.json, any_pre_epoch_timestamp_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_pre_epoch_timestamp_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any Max Timestamp WKT JSON stringify", iters.json, any_max_timestamp_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_max_timestamp_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any Max Timestamp WKT JSON parse", iters.json, any_max_timestamp_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_max_timestamp_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any Min Timestamp WKT JSON stringify", iters.json, any_min_timestamp_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_min_timestamp_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any Min Timestamp WKT JSON parse", iters.json, any_min_timestamp_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_min_timestamp_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any Empty WKT JSON stringify", iters.json, any_empty_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_empty_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any Empty WKT JSON parse", iters.json, any_empty_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_empty_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any Struct WKT JSON stringify", iters.json, any_struct_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_struct_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any Struct WKT JSON parse", iters.json, any_struct_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_struct_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any Struct Escape WKT JSON parse", iters.json, json.AnyStructEscapeWktJson.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = json.AnyStructEscapeWktJson }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any Struct NumberExponent WKT JSON parse", iters.json, json.AnyStructNumberExponentWktJson.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = json.AnyStructNumberExponentWktJson }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any Struct Surrogate WKT JSON parse", iters.json, json.AnyStructSurrogateWktJson.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = json.AnyStructSurrogateWktJson }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any Struct KeySurrogate WKT JSON parse", iters.json, json.AnyStructKeySurrogateWktJson.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = json.AnyStructKeySurrogateWktJson }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any EmptyStruct WKT JSON stringify", iters.json, any_empty_struct_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_empty_struct_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any EmptyStruct WKT JSON parse", iters.json, any_empty_struct_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_empty_struct_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any Value WKT JSON stringify", iters.json, any_value_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_value_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any Value WKT JSON parse", iters.json, any_value_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_value_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any Value Escape WKT JSON parse", iters.json, json.AnyValueEscapeWktJson.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = json.AnyValueEscapeWktJson }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any Value NumberExponent WKT JSON parse", iters.json, json.AnyValueNumberExponentWktJson.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = json.AnyValueNumberExponentWktJson }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any Value Surrogate WKT JSON parse", iters.json, json.AnyValueSurrogateWktJson.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = json.AnyValueSurrogateWktJson }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any Value KeySurrogate WKT JSON parse", iters.json, json.AnyValueKeySurrogateWktJson.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = json.AnyValueKeySurrogateWktJson }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any NullValue WKT JSON stringify", iters.json, any_null_value_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_null_value_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any NullValue WKT JSON parse", iters.json, any_null_value_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_null_value_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any StringScalarValue WKT JSON stringify", iters.json, any_string_scalar_value_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_string_scalar_value_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any StringScalarValue WKT JSON parse", iters.json, any_string_scalar_value_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_string_scalar_value_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any StringScalarValue Escape WKT JSON parse", iters.json, json.AnyStringScalarValueEscapeWktJson.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = json.AnyStringScalarValueEscapeWktJson }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any StringScalarValue Surrogate WKT JSON parse", iters.json, json.AnyStringScalarValueSurrogateWktJson.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = json.AnyStringScalarValueSurrogateWktJson }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any EmptyStringScalarValue WKT JSON stringify", iters.json, any_empty_string_scalar_value_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_empty_string_scalar_value_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any EmptyStringScalarValue WKT JSON parse", iters.json, any_empty_string_scalar_value_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_empty_string_scalar_value_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any NumberValue WKT JSON stringify", iters.json, any_number_value_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_number_value_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any NumberValue WKT JSON parse", iters.json, any_number_value_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_number_value_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any NumberValue Exponent WKT JSON parse", iters.json, json.AnyNumberValueExponentWktJson.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = json.AnyNumberValueExponentWktJson }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any NegativeNumberValue WKT JSON stringify", iters.json, any_negative_number_value_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_negative_number_value_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any NegativeNumberValue WKT JSON parse", iters.json, any_negative_number_value_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_negative_number_value_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any ZeroNumberValue WKT JSON stringify", iters.json, any_zero_number_value_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_zero_number_value_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any ZeroNumberValue WKT JSON parse", iters.json, any_zero_number_value_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_zero_number_value_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any BoolScalarValue WKT JSON stringify", iters.json, any_bool_scalar_value_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_bool_scalar_value_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any BoolScalarValue WKT JSON parse", iters.json, any_bool_scalar_value_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_bool_scalar_value_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any FalseBoolScalarValue WKT JSON stringify", iters.json, any_false_bool_scalar_value_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_false_bool_scalar_value_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any FalseBoolScalarValue WKT JSON parse", iters.json, any_false_bool_scalar_value_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_false_bool_scalar_value_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any ListKindValue WKT JSON stringify", iters.json, any_list_kind_value_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_list_kind_value_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any ListKindValue WKT JSON parse", iters.json, any_list_kind_value_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_list_kind_value_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any ListKindValue Escape WKT JSON parse", iters.json, json.AnyListKindValueEscapeWktJson.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = json.AnyListKindValueEscapeWktJson }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any ListKindValue Surrogate WKT JSON parse", iters.json, json.AnyListKindValueSurrogateWktJson.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = json.AnyListKindValueSurrogateWktJson }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any EmptyStructKindValue WKT JSON stringify", iters.json, any_empty_struct_kind_value_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_empty_struct_kind_value_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any EmptyStructKindValue WKT JSON parse", iters.json, any_empty_struct_kind_value_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_empty_struct_kind_value_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any EmptyListKindValue WKT JSON stringify", iters.json, any_empty_list_kind_value_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_empty_list_kind_value_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any EmptyListKindValue WKT JSON parse", iters.json, any_empty_list_kind_value_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_empty_list_kind_value_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any DoubleValue WKT JSON stringify", iters.json, any_double_value_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_double_value_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any DoubleValue WKT JSON parse", iters.json, any_double_value_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_double_value_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any DoubleValue String WKT JSON parse", iters.json, json.AnyDoubleValueStringWktJson.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = json.AnyDoubleValueStringWktJson }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any DoubleValue Exponent WKT JSON parse", iters.json, json.AnyDoubleValueExponentWktJson.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = json.AnyDoubleValueExponentWktJson }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any NegativeDoubleValue WKT JSON stringify", iters.json, any_negative_double_value_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_negative_double_value_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any NegativeDoubleValue WKT JSON parse", iters.json, any_negative_double_value_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_negative_double_value_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any ZeroDoubleValue WKT JSON stringify", iters.json, any_zero_double_value_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_zero_double_value_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any ZeroDoubleValue WKT JSON parse", iters.json, any_zero_double_value_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_zero_double_value_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any DoubleValue NaN WKT JSON stringify", iters.json, any_double_value_nan_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_double_value_nan_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any DoubleValue NaN WKT JSON parse", iters.json, any_double_value_nan_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_double_value_nan_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any DoubleValue Infinity WKT JSON stringify", iters.json, any_double_value_inf_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_double_value_inf_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any DoubleValue Infinity WKT JSON parse", iters.json, any_double_value_inf_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_double_value_inf_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any DoubleValue NegativeInfinity WKT JSON stringify", iters.json, any_double_value_neg_inf_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_double_value_neg_inf_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any DoubleValue NegativeInfinity WKT JSON parse", iters.json, any_double_value_neg_inf_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_double_value_neg_inf_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any FloatValue WKT JSON stringify", iters.json, any_float_value_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_float_value_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any FloatValue WKT JSON parse", iters.json, any_float_value_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_float_value_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any FloatValue String WKT JSON parse", iters.json, json.AnyFloatValueStringWktJson.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = json.AnyFloatValueStringWktJson }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any FloatValue Exponent WKT JSON parse", iters.json, json.AnyFloatValueExponentWktJson.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = json.AnyFloatValueExponentWktJson }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any NegativeFloatValue WKT JSON stringify", iters.json, any_negative_float_value_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_negative_float_value_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any NegativeFloatValue WKT JSON parse", iters.json, any_negative_float_value_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_negative_float_value_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any ZeroFloatValue WKT JSON stringify", iters.json, any_zero_float_value_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_zero_float_value_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any ZeroFloatValue WKT JSON parse", iters.json, any_zero_float_value_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_zero_float_value_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any FloatValue NaN WKT JSON stringify", iters.json, any_float_value_nan_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_float_value_nan_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any FloatValue NaN WKT JSON parse", iters.json, any_float_value_nan_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_float_value_nan_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any FloatValue Infinity WKT JSON stringify", iters.json, any_float_value_inf_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_float_value_inf_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any FloatValue Infinity WKT JSON parse", iters.json, any_float_value_inf_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_float_value_inf_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any FloatValue NegativeInfinity WKT JSON stringify", iters.json, any_float_value_neg_inf_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_float_value_neg_inf_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any FloatValue NegativeInfinity WKT JSON parse", iters.json, any_float_value_neg_inf_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_float_value_neg_inf_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any Int64Value WKT JSON stringify", iters.json, any_int64_value_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_int64_value_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any Int64Value WKT JSON parse", iters.json, any_int64_value_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_int64_value_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any Int64Value Number WKT JSON parse", iters.json, json.AnyInt64ValueNumberWktJson.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = json.AnyInt64ValueNumberWktJson }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any Int64Value Exponent WKT JSON parse", iters.json, json.AnyInt64ValueExponentWktJson.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = json.AnyInt64ValueExponentWktJson }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any ZeroInt64Value WKT JSON stringify", iters.json, any_zero_int64_value_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_zero_int64_value_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any ZeroInt64Value WKT JSON parse", iters.json, any_zero_int64_value_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_zero_int64_value_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any NegativeInt64Value WKT JSON stringify", iters.json, any_negative_int64_value_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_negative_int64_value_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any NegativeInt64Value WKT JSON parse", iters.json, any_negative_int64_value_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_negative_int64_value_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any MinInt64Value WKT JSON stringify", iters.json, any_min_int64_value_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_min_int64_value_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any MinInt64Value WKT JSON parse", iters.json, any_min_int64_value_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_min_int64_value_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any MaxInt64Value WKT JSON stringify", iters.json, any_max_int64_value_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_max_int64_value_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any MaxInt64Value WKT JSON parse", iters.json, any_max_int64_value_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_max_int64_value_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any UInt64Value WKT JSON stringify", iters.json, any_uint64_value_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_uint64_value_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any UInt64Value WKT JSON parse", iters.json, any_uint64_value_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_uint64_value_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any UInt64Value Number WKT JSON parse", iters.json, json.AnyUInt64ValueNumberWktJson.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = json.AnyUInt64ValueNumberWktJson }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any UInt64Value Exponent WKT JSON parse", iters.json, json.AnyUInt64ValueExponentWktJson.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = json.AnyUInt64ValueExponentWktJson }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any ZeroUInt64Value WKT JSON stringify", iters.json, any_zero_uint64_value_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_zero_uint64_value_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any ZeroUInt64Value WKT JSON parse", iters.json, any_zero_uint64_value_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_zero_uint64_value_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any MaxUInt64Value WKT JSON stringify", iters.json, any_max_uint64_value_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_max_uint64_value_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any MaxUInt64Value WKT JSON parse", iters.json, any_max_uint64_value_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_max_uint64_value_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any Int32Value WKT JSON stringify", iters.json, any_int32_value_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_int32_value_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any Int32Value WKT JSON parse", iters.json, any_int32_value_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_int32_value_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any Int32Value String WKT JSON parse", iters.json, json.AnyInt32ValueStringWktJson.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = json.AnyInt32ValueStringWktJson }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any Int32Value Exponent WKT JSON parse", iters.json, json.AnyInt32ValueExponentWktJson.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = json.AnyInt32ValueExponentWktJson }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any ZeroInt32Value WKT JSON stringify", iters.json, any_zero_int32_value_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_zero_int32_value_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any ZeroInt32Value WKT JSON parse", iters.json, any_zero_int32_value_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_zero_int32_value_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any NegativeInt32Value WKT JSON stringify", iters.json, any_negative_int32_value_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_negative_int32_value_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any NegativeInt32Value WKT JSON parse", iters.json, any_negative_int32_value_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_negative_int32_value_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any MinInt32Value WKT JSON stringify", iters.json, any_min_int32_value_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_min_int32_value_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any MinInt32Value WKT JSON parse", iters.json, any_min_int32_value_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_min_int32_value_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any MaxInt32Value WKT JSON stringify", iters.json, any_max_int32_value_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_max_int32_value_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any MaxInt32Value WKT JSON parse", iters.json, any_max_int32_value_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_max_int32_value_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any UInt32Value WKT JSON stringify", iters.json, any_uint32_value_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_uint32_value_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any UInt32Value WKT JSON parse", iters.json, any_uint32_value_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_uint32_value_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any UInt32Value String WKT JSON parse", iters.json, json.AnyUInt32ValueStringWktJson.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = json.AnyUInt32ValueStringWktJson }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any UInt32Value Exponent WKT JSON parse", iters.json, json.AnyUInt32ValueExponentWktJson.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = json.AnyUInt32ValueExponentWktJson }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any ZeroUInt32Value WKT JSON stringify", iters.json, any_zero_uint32_value_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_zero_uint32_value_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any ZeroUInt32Value WKT JSON parse", iters.json, any_zero_uint32_value_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_zero_uint32_value_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any MaxUInt32Value WKT JSON stringify", iters.json, any_max_uint32_value_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_max_uint32_value_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any MaxUInt32Value WKT JSON parse", iters.json, any_max_uint32_value_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_max_uint32_value_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any BoolValue WKT JSON stringify", iters.json, any_bool_value_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_bool_value_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any BoolValue WKT JSON parse", iters.json, any_bool_value_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_bool_value_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any FalseBoolValue WKT JSON stringify", iters.json, any_false_bool_value_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_false_bool_value_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any FalseBoolValue WKT JSON parse", iters.json, any_false_bool_value_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_false_bool_value_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any StringValue WKT JSON stringify", iters.json, any_string_value_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_string_value_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any StringValue WKT JSON parse", iters.json, any_string_value_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_string_value_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any StringValue Escape WKT JSON parse", iters.json, json.AnyStringValueEscapeWktJson.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = json.AnyStringValueEscapeWktJson }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any StringValue Surrogate WKT JSON parse", iters.json, json.AnyStringValueSurrogateWktJson.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = json.AnyStringValueSurrogateWktJson }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any EmptyStringValue WKT JSON stringify", iters.json, any_empty_string_value_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_empty_string_value_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any EmptyStringValue WKT JSON parse", iters.json, any_empty_string_value_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_empty_string_value_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any BytesValue WKT JSON stringify", iters.json, any_bytes_value_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_bytes_value_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any BytesValue WKT JSON parse", iters.json, any_bytes_value_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_bytes_value_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any BytesValue URL WKT JSON parse", iters.json, json.AnyBytesValueUrlWktJson.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = json.AnyBytesValueUrlWktJson }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any BytesValue StandardBase64 WKT JSON parse", iters.json, json.AnyBytesValueStandardBase64WktJson.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = json.AnyBytesValueStandardBase64WktJson }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any BytesValue Unpadded WKT JSON parse", iters.json, json.AnyBytesValueUnpaddedWktJson.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = json.AnyBytesValueUnpaddedWktJson }, json.anyWktJsonParse),
        try runTimed(io, "pbz Any EmptyBytesValue WKT JSON stringify", iters.json, any_empty_bytes_value_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &any_empty_bytes_value_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Any EmptyBytesValue WKT JSON parse", iters.json, any_empty_bytes_value_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = any_empty_bytes_value_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Nested Any WKT JSON stringify", iters.json, nested_any_wkt_json.len, json.AnyWktJsonStringifyCtx{ .allocator = allocator, .any = &nested_any_wkt }, json.anyWktJsonStringify),
        try runTimed(io, "pbz Nested Any WKT JSON parse", iters.json, nested_any_wkt_json.len, json.AnyWktJsonParseCtx{ .allocator = allocator, .json = nested_any_wkt_json }, json.anyWktJsonParse),
        try runTimed(io, "pbz Duration JSON stringify", iters.json, duration_json.len, json.DurationJsonStringifyCtx{ .allocator = allocator, .duration = duration_value }, json.durationJsonStringify),
        try runTimed(io, "pbz Duration JSON parse", iters.json, duration_json.len, json.DurationJsonParseCtx{ .json = duration_json }, json.durationJsonParse),
        try runTimed(io, "pbz Duration Escape JSON parse", iters.json, json.DurationEscapeJson.len, json.DurationJsonParseCtx{ .json = json.DurationEscapeJson }, json.durationJsonParse),
        try runTimed(io, "pbz PlusDuration JSON parse", iters.json, json.PlusDurationJson.len, json.DurationJsonParseCtx{ .json = json.PlusDurationJson }, json.durationJsonParse),
        try runTimed(io, "pbz ShortFractionDuration JSON parse", iters.json, json.ShortFractionDurationJson.len, json.DurationJsonParseCtx{ .json = json.ShortFractionDurationJson }, json.durationJsonParse),
        try runTimed(io, "pbz MicroDuration JSON stringify", iters.json, micro_duration_json.len, json.DurationJsonStringifyCtx{ .allocator = allocator, .duration = micro_duration_value }, json.durationJsonStringify),
        try runTimed(io, "pbz MicroDuration JSON parse", iters.json, micro_duration_json.len, json.DurationJsonParseCtx{ .json = micro_duration_json }, json.durationJsonParse),
        try runTimed(io, "pbz NanoDuration JSON stringify", iters.json, nano_duration_json.len, json.DurationJsonStringifyCtx{ .allocator = allocator, .duration = nano_duration_value }, json.durationJsonStringify),
        try runTimed(io, "pbz NanoDuration JSON parse", iters.json, nano_duration_json.len, json.DurationJsonParseCtx{ .json = nano_duration_json }, json.durationJsonParse),
        try runTimed(io, "pbz NegativeDuration JSON stringify", iters.json, negative_duration_json.len, json.DurationJsonStringifyCtx{ .allocator = allocator, .duration = negative_duration_value }, json.durationJsonStringify),
        try runTimed(io, "pbz NegativeDuration JSON parse", iters.json, negative_duration_json.len, json.DurationJsonParseCtx{ .json = negative_duration_json }, json.durationJsonParse),
        try runTimed(io, "pbz FractionalNegativeDuration JSON stringify", iters.json, fractional_negative_duration_json.len, json.DurationJsonStringifyCtx{ .allocator = allocator, .duration = fractional_negative_duration_value }, json.durationJsonStringify),
        try runTimed(io, "pbz FractionalNegativeDuration JSON parse", iters.json, fractional_negative_duration_json.len, json.DurationJsonParseCtx{ .json = fractional_negative_duration_json }, json.durationJsonParse),
        try runTimed(io, "pbz MaxDuration JSON stringify", iters.json, max_duration_json.len, json.DurationJsonStringifyCtx{ .allocator = allocator, .duration = max_duration_value }, json.durationJsonStringify),
        try runTimed(io, "pbz MaxDuration JSON parse", iters.json, max_duration_json.len, json.DurationJsonParseCtx{ .json = max_duration_json }, json.durationJsonParse),
        try runTimed(io, "pbz MinDuration JSON stringify", iters.json, min_duration_json.len, json.DurationJsonStringifyCtx{ .allocator = allocator, .duration = min_duration_value }, json.durationJsonStringify),
        try runTimed(io, "pbz MinDuration JSON parse", iters.json, min_duration_json.len, json.DurationJsonParseCtx{ .json = min_duration_json }, json.durationJsonParse),
        try runTimed(io, "pbz ZeroDuration JSON stringify", iters.json, zero_duration_json.len, json.DurationJsonStringifyCtx{ .allocator = allocator, .duration = zero_duration_value }, json.durationJsonStringify),
        try runTimed(io, "pbz ZeroDuration JSON parse", iters.json, zero_duration_json.len, json.DurationJsonParseCtx{ .json = zero_duration_json }, json.durationJsonParse),
        try runTimed(io, "pbz FieldMask JSON stringify", iters.json, field_mask_json.len, json.FieldMaskJsonStringifyCtx{ .allocator = allocator, .mask = &field_mask_value }, json.fieldMaskJsonStringify),
        try runTimed(io, "pbz FieldMask JSON parse", iters.json, field_mask_json.len, json.FieldMaskJsonParseCtx{ .allocator = allocator, .json = field_mask_json }, json.fieldMaskJsonParse),
        try runTimed(io, "pbz FieldMask Escape JSON parse", iters.json, json.FieldMaskEscapeJson.len, json.FieldMaskJsonParseCtx{ .allocator = allocator, .json = json.FieldMaskEscapeJson }, json.fieldMaskJsonParse),
        try runTimed(io, "pbz EmptyFieldMask JSON stringify", iters.json, empty_field_mask_json.len, json.FieldMaskJsonStringifyCtx{ .allocator = allocator, .mask = &empty_field_mask_value }, json.fieldMaskJsonStringify),
        try runTimed(io, "pbz EmptyFieldMask JSON parse", iters.json, empty_field_mask_json.len, json.FieldMaskJsonParseCtx{ .allocator = allocator, .json = empty_field_mask_json }, json.fieldMaskJsonParse),
        try runTimed(io, "pbz Timestamp JSON stringify", iters.json, timestamp_json.len, json.TimestampJsonStringifyCtx{ .allocator = allocator, .timestamp = timestamp_value }, json.timestampJsonStringify),
        try runTimed(io, "pbz Timestamp JSON parse", iters.json, timestamp_json.len, json.TimestampJsonParseCtx{ .json = timestamp_json }, json.timestampJsonParse),
        try runTimed(io, "pbz Timestamp Escape JSON parse", iters.json, json.TimestampEscapeJson.len, json.TimestampJsonParseCtx{ .json = json.TimestampEscapeJson }, json.timestampJsonParse),
        try runTimed(io, "pbz ShortFraction Timestamp JSON parse", iters.json, json.ShortFractionTimestampJson.len, json.TimestampJsonParseCtx{ .json = json.ShortFractionTimestampJson }, json.timestampJsonParse),
        try runTimed(io, "pbz Micro Timestamp JSON stringify", iters.json, micro_timestamp_json.len, json.TimestampJsonStringifyCtx{ .allocator = allocator, .timestamp = micro_timestamp_value }, json.timestampJsonStringify),
        try runTimed(io, "pbz Micro Timestamp JSON parse", iters.json, micro_timestamp_json.len, json.TimestampJsonParseCtx{ .json = micro_timestamp_json }, json.timestampJsonParse),
        try runTimed(io, "pbz Nano Timestamp JSON stringify", iters.json, nano_timestamp_json.len, json.TimestampJsonStringifyCtx{ .allocator = allocator, .timestamp = nano_timestamp_value }, json.timestampJsonStringify),
        try runTimed(io, "pbz Nano Timestamp JSON parse", iters.json, nano_timestamp_json.len, json.TimestampJsonParseCtx{ .json = nano_timestamp_json }, json.timestampJsonParse),
        try runTimed(io, "pbz Offset Timestamp JSON parse", iters.json, json.OffsetTimestampJson.len, json.TimestampJsonParseCtx{ .json = json.OffsetTimestampJson }, json.timestampJsonParse),
        try runTimed(io, "pbz PreEpoch Timestamp JSON stringify", iters.json, pre_epoch_timestamp_json.len, json.TimestampJsonStringifyCtx{ .allocator = allocator, .timestamp = pre_epoch_timestamp_value }, json.timestampJsonStringify),
        try runTimed(io, "pbz PreEpoch Timestamp JSON parse", iters.json, pre_epoch_timestamp_json.len, json.TimestampJsonParseCtx{ .json = pre_epoch_timestamp_json }, json.timestampJsonParse),
        try runTimed(io, "pbz Max Timestamp JSON stringify", iters.json, max_timestamp_json.len, json.TimestampJsonStringifyCtx{ .allocator = allocator, .timestamp = max_timestamp_value }, json.timestampJsonStringify),
        try runTimed(io, "pbz Max Timestamp JSON parse", iters.json, max_timestamp_json.len, json.TimestampJsonParseCtx{ .json = max_timestamp_json }, json.timestampJsonParse),
        try runTimed(io, "pbz Min Timestamp JSON stringify", iters.json, min_timestamp_json.len, json.TimestampJsonStringifyCtx{ .allocator = allocator, .timestamp = min_timestamp_value }, json.timestampJsonStringify),
        try runTimed(io, "pbz Min Timestamp JSON parse", iters.json, min_timestamp_json.len, json.TimestampJsonParseCtx{ .json = min_timestamp_json }, json.timestampJsonParse),
        try runTimed(io, "pbz Empty JSON stringify", iters.json, empty_json.len, json.EmptyJsonStringifyCtx{ .allocator = allocator }, json.emptyJsonStringify),
        try runTimed(io, "pbz Empty JSON parse", iters.json, empty_json.len, json.EmptyJsonParseCtx{ .allocator = allocator, .json = empty_json }, json.emptyJsonParse),
        try runTimed(io, "pbz Struct JSON stringify", iters.json, struct_json.len, json.WktJsonStringifyCtx(pbz.Struct){ .allocator = allocator, .value = struct_value }, json.wktJsonStringify),
        try runTimed(io, "pbz Struct JSON parse", iters.json, struct_json.len, json.WktJsonParseCtx(pbz.Struct){ .allocator = allocator, .json = struct_json }, json.wktJsonParse),
        try runTimed(io, "pbz Struct Escape JSON parse", iters.json, json.StructEscapeJson.len, json.WktJsonParseCtx(pbz.Struct){ .allocator = allocator, .json = json.StructEscapeJson }, json.wktJsonParse),
        try runTimed(io, "pbz Struct NumberExponent JSON parse", iters.json, json.StructNumberExponentJson.len, json.WktJsonParseCtx(pbz.Struct){ .allocator = allocator, .json = json.StructNumberExponentJson }, json.wktJsonParse),
        try runTimed(io, "pbz Struct Surrogate JSON parse", iters.json, json.StructSurrogateJson.len, json.WktJsonParseCtx(pbz.Struct){ .allocator = allocator, .json = json.StructSurrogateJson }, json.wktJsonParse),
        try runTimed(io, "pbz Struct KeySurrogate JSON parse", iters.json, json.StructKeySurrogateJson.len, json.WktJsonParseCtx(pbz.Struct){ .allocator = allocator, .json = json.StructKeySurrogateJson }, json.wktJsonParse),
        try runTimed(io, "pbz EmptyStruct JSON stringify", iters.json, empty_struct_json.len, json.WktJsonStringifyCtx(pbz.Struct){ .allocator = allocator, .value = empty_struct_value }, json.wktJsonStringify),
        try runTimed(io, "pbz EmptyStruct JSON parse", iters.json, empty_struct_json.len, json.WktJsonParseCtx(pbz.Struct){ .allocator = allocator, .json = empty_struct_json }, json.wktJsonParse),
        try runTimed(io, "pbz Value JSON stringify", iters.json, value_json.len, json.WktJsonStringifyCtx(pbz.Value){ .allocator = allocator, .value = value_value }, json.wktJsonStringify),
        try runTimed(io, "pbz Value JSON parse", iters.json, value_json.len, json.WktJsonParseCtx(pbz.Value){ .allocator = allocator, .json = value_json }, json.wktJsonParse),
        try runTimed(io, "pbz Value Escape JSON parse", iters.json, json.ValueEscapeJson.len, json.WktJsonParseCtx(pbz.Value){ .allocator = allocator, .json = json.ValueEscapeJson }, json.wktJsonParse),
        try runTimed(io, "pbz Value NumberExponent JSON parse", iters.json, json.ValueNumberExponentJson.len, json.WktJsonParseCtx(pbz.Value){ .allocator = allocator, .json = json.ValueNumberExponentJson }, json.wktJsonParse),
        try runTimed(io, "pbz Value Surrogate JSON parse", iters.json, json.ValueSurrogateJson.len, json.WktJsonParseCtx(pbz.Value){ .allocator = allocator, .json = json.ValueSurrogateJson }, json.wktJsonParse),
        try runTimed(io, "pbz Value KeySurrogate JSON parse", iters.json, json.ValueKeySurrogateJson.len, json.WktJsonParseCtx(pbz.Value){ .allocator = allocator, .json = json.ValueKeySurrogateJson }, json.wktJsonParse),
        try runTimed(io, "pbz NullValue JSON stringify", iters.json, null_value_json.len, json.WktJsonStringifyCtx(pbz.Value){ .allocator = allocator, .value = null_value_value }, json.wktJsonStringify),
        try runTimed(io, "pbz NullValue JSON parse", iters.json, null_value_json.len, json.WktJsonParseCtx(pbz.Value){ .allocator = allocator, .json = null_value_json }, json.wktJsonParse),
        try runTimed(io, "pbz StringScalarValue JSON stringify", iters.json, string_scalar_value_json.len, json.WktJsonStringifyCtx(pbz.Value){ .allocator = allocator, .value = string_scalar_value }, json.wktJsonStringify),
        try runTimed(io, "pbz StringScalarValue JSON parse", iters.json, string_scalar_value_json.len, json.WktJsonParseCtx(pbz.Value){ .allocator = allocator, .json = string_scalar_value_json }, json.wktJsonParse),
        try runTimed(io, "pbz StringScalarValue Escape JSON parse", iters.json, json.StringScalarValueEscapeJson.len, json.WktJsonParseCtx(pbz.Value){ .allocator = allocator, .json = json.StringScalarValueEscapeJson }, json.wktJsonParse),
        try runTimed(io, "pbz StringScalarValue Surrogate JSON parse", iters.json, json.StringScalarValueSurrogateJson.len, json.WktJsonParseCtx(pbz.Value){ .allocator = allocator, .json = json.StringScalarValueSurrogateJson }, json.wktJsonParse),
        try runTimed(io, "pbz EmptyStringScalarValue JSON stringify", iters.json, empty_string_scalar_value_json.len, json.WktJsonStringifyCtx(pbz.Value){ .allocator = allocator, .value = empty_string_scalar_value }, json.wktJsonStringify),
        try runTimed(io, "pbz EmptyStringScalarValue JSON parse", iters.json, empty_string_scalar_value_json.len, json.WktJsonParseCtx(pbz.Value){ .allocator = allocator, .json = empty_string_scalar_value_json }, json.wktJsonParse),
        try runTimed(io, "pbz NumberValue JSON stringify", iters.json, number_value_json.len, json.WktJsonStringifyCtx(pbz.Value){ .allocator = allocator, .value = number_value }, json.wktJsonStringify),
        try runTimed(io, "pbz NumberValue JSON parse", iters.json, number_value_json.len, json.WktJsonParseCtx(pbz.Value){ .allocator = allocator, .json = number_value_json }, json.wktJsonParse),
        try runTimed(io, "pbz NumberValue Exponent JSON parse", iters.json, json.NumberValueExponentJson.len, json.WktJsonParseCtx(pbz.Value){ .allocator = allocator, .json = json.NumberValueExponentJson }, json.wktJsonParse),
        try runTimed(io, "pbz NegativeNumberValue JSON stringify", iters.json, negative_number_value_json.len, json.WktJsonStringifyCtx(pbz.Value){ .allocator = allocator, .value = negative_number_value }, json.wktJsonStringify),
        try runTimed(io, "pbz NegativeNumberValue JSON parse", iters.json, negative_number_value_json.len, json.WktJsonParseCtx(pbz.Value){ .allocator = allocator, .json = negative_number_value_json }, json.wktJsonParse),
        try runTimed(io, "pbz ZeroNumberValue JSON stringify", iters.json, zero_number_value_json.len, json.WktJsonStringifyCtx(pbz.Value){ .allocator = allocator, .value = zero_number_value }, json.wktJsonStringify),
        try runTimed(io, "pbz ZeroNumberValue JSON parse", iters.json, zero_number_value_json.len, json.WktJsonParseCtx(pbz.Value){ .allocator = allocator, .json = zero_number_value_json }, json.wktJsonParse),
        try runTimed(io, "pbz BoolScalarValue JSON stringify", iters.json, bool_scalar_value_json.len, json.WktJsonStringifyCtx(pbz.Value){ .allocator = allocator, .value = bool_scalar_value }, json.wktJsonStringify),
        try runTimed(io, "pbz BoolScalarValue JSON parse", iters.json, bool_scalar_value_json.len, json.WktJsonParseCtx(pbz.Value){ .allocator = allocator, .json = bool_scalar_value_json }, json.wktJsonParse),
        try runTimed(io, "pbz FalseBoolScalarValue JSON stringify", iters.json, false_bool_scalar_value_json.len, json.WktJsonStringifyCtx(pbz.Value){ .allocator = allocator, .value = false_bool_scalar_value }, json.wktJsonStringify),
        try runTimed(io, "pbz FalseBoolScalarValue JSON parse", iters.json, false_bool_scalar_value_json.len, json.WktJsonParseCtx(pbz.Value){ .allocator = allocator, .json = false_bool_scalar_value_json }, json.wktJsonParse),
        try runTimed(io, "pbz ListKindValue JSON stringify", iters.json, list_kind_value_json.len, json.WktJsonStringifyCtx(pbz.Value){ .allocator = allocator, .value = list_kind_value }, json.wktJsonStringify),
        try runTimed(io, "pbz ListKindValue JSON parse", iters.json, list_kind_value_json.len, json.WktJsonParseCtx(pbz.Value){ .allocator = allocator, .json = list_kind_value_json }, json.wktJsonParse),
        try runTimed(io, "pbz ListKindValue Escape JSON parse", iters.json, json.ListKindValueEscapeJson.len, json.WktJsonParseCtx(pbz.Value){ .allocator = allocator, .json = json.ListKindValueEscapeJson }, json.wktJsonParse),
        try runTimed(io, "pbz ListKindValue Surrogate JSON parse", iters.json, json.ListKindValueSurrogateJson.len, json.WktJsonParseCtx(pbz.Value){ .allocator = allocator, .json = json.ListKindValueSurrogateJson }, json.wktJsonParse),
        try runTimed(io, "pbz EmptyStructKindValue JSON stringify", iters.json, empty_struct_kind_value_json.len, json.WktJsonStringifyCtx(pbz.Value){ .allocator = allocator, .value = empty_struct_kind_value }, json.wktJsonStringify),
        try runTimed(io, "pbz EmptyStructKindValue JSON parse", iters.json, empty_struct_kind_value_json.len, json.WktJsonParseCtx(pbz.Value){ .allocator = allocator, .json = empty_struct_kind_value_json }, json.wktJsonParse),
        try runTimed(io, "pbz EmptyListKindValue JSON stringify", iters.json, empty_list_kind_value_json.len, json.WktJsonStringifyCtx(pbz.Value){ .allocator = allocator, .value = empty_list_kind_value }, json.wktJsonStringify),
        try runTimed(io, "pbz EmptyListKindValue JSON parse", iters.json, empty_list_kind_value_json.len, json.WktJsonParseCtx(pbz.Value){ .allocator = allocator, .json = empty_list_kind_value_json }, json.wktJsonParse),
        try runTimed(io, "pbz ListValue JSON stringify", iters.json, list_value_json.len, json.WktJsonStringifyCtx(pbz.ListValue){ .allocator = allocator, .value = list_value }, json.wktJsonStringify),
        try runTimed(io, "pbz ListValue JSON parse", iters.json, list_value_json.len, json.WktJsonParseCtx(pbz.ListValue){ .allocator = allocator, .json = list_value_json }, json.wktJsonParse),
        try runTimed(io, "pbz ListValue Escape JSON parse", iters.json, json.ListValueEscapeJson.len, json.WktJsonParseCtx(pbz.ListValue){ .allocator = allocator, .json = json.ListValueEscapeJson }, json.wktJsonParse),
        try runTimed(io, "pbz ListValue Surrogate JSON parse", iters.json, json.ListValueSurrogateJson.len, json.WktJsonParseCtx(pbz.ListValue){ .allocator = allocator, .json = json.ListValueSurrogateJson }, json.wktJsonParse),
        try runTimed(io, "pbz EmptyListValue JSON stringify", iters.json, empty_list_value_json.len, json.WktJsonStringifyCtx(pbz.ListValue){ .allocator = allocator, .value = empty_list_value }, json.wktJsonStringify),
        try runTimed(io, "pbz EmptyListValue JSON parse", iters.json, empty_list_value_json.len, json.WktJsonParseCtx(pbz.ListValue){ .allocator = allocator, .json = empty_list_value_json }, json.wktJsonParse),
        try runTimed(io, "pbz DoubleValue JSON stringify", iters.json, double_value_json.len, json.WktJsonStringifyCtx(pbz.DoubleValue){ .allocator = allocator, .value = double_value }, json.wktJsonStringify),
        try runTimed(io, "pbz DoubleValue JSON parse", iters.json, double_value_json.len, json.WktJsonParseCtx(pbz.DoubleValue){ .allocator = allocator, .json = double_value_json }, json.wktJsonParse),
        try runTimed(io, "pbz DoubleValue String JSON parse", iters.json, json.DoubleValueStringJson.len, json.WktJsonParseCtx(pbz.DoubleValue){ .allocator = allocator, .json = json.DoubleValueStringJson }, json.wktJsonParse),
        try runTimed(io, "pbz DoubleValue Exponent JSON parse", iters.json, json.DoubleValueExponentJson.len, json.WktJsonParseCtx(pbz.DoubleValue){ .allocator = allocator, .json = json.DoubleValueExponentJson }, json.wktJsonParse),
        try runTimed(io, "pbz NegativeDoubleValue JSON stringify", iters.json, negative_double_value_json.len, json.WktJsonStringifyCtx(pbz.DoubleValue){ .allocator = allocator, .value = negative_double_value }, json.wktJsonStringify),
        try runTimed(io, "pbz NegativeDoubleValue JSON parse", iters.json, negative_double_value_json.len, json.WktJsonParseCtx(pbz.DoubleValue){ .allocator = allocator, .json = negative_double_value_json }, json.wktJsonParse),
        try runTimed(io, "pbz ZeroDoubleValue JSON stringify", iters.json, zero_double_value_json.len, json.WktJsonStringifyCtx(pbz.DoubleValue){ .allocator = allocator, .value = zero_double_value }, json.wktJsonStringify),
        try runTimed(io, "pbz ZeroDoubleValue JSON parse", iters.json, zero_double_value_json.len, json.WktJsonParseCtx(pbz.DoubleValue){ .allocator = allocator, .json = zero_double_value_json }, json.wktJsonParse),
        try runTimed(io, "pbz DoubleValue NaN JSON stringify", iters.json, double_value_nan_json.len, json.WktJsonStringifyCtx(pbz.DoubleValue){ .allocator = allocator, .value = double_value_nan }, json.wktJsonStringify),
        try runTimed(io, "pbz DoubleValue NaN JSON parse", iters.json, double_value_nan_json.len, json.WktJsonParseCtx(pbz.DoubleValue){ .allocator = allocator, .json = double_value_nan_json }, json.wktJsonParse),
        try runTimed(io, "pbz DoubleValue Infinity JSON stringify", iters.json, double_value_inf_json.len, json.WktJsonStringifyCtx(pbz.DoubleValue){ .allocator = allocator, .value = double_value_inf }, json.wktJsonStringify),
        try runTimed(io, "pbz DoubleValue Infinity JSON parse", iters.json, double_value_inf_json.len, json.WktJsonParseCtx(pbz.DoubleValue){ .allocator = allocator, .json = double_value_inf_json }, json.wktJsonParse),
        try runTimed(io, "pbz DoubleValue NegativeInfinity JSON stringify", iters.json, double_value_neg_inf_json.len, json.WktJsonStringifyCtx(pbz.DoubleValue){ .allocator = allocator, .value = double_value_neg_inf }, json.wktJsonStringify),
        try runTimed(io, "pbz DoubleValue NegativeInfinity JSON parse", iters.json, double_value_neg_inf_json.len, json.WktJsonParseCtx(pbz.DoubleValue){ .allocator = allocator, .json = double_value_neg_inf_json }, json.wktJsonParse),
        try runTimed(io, "pbz FloatValue JSON stringify", iters.json, float_value_json.len, json.WktJsonStringifyCtx(pbz.FloatValue){ .allocator = allocator, .value = float_value }, json.wktJsonStringify),
        try runTimed(io, "pbz FloatValue JSON parse", iters.json, float_value_json.len, json.WktJsonParseCtx(pbz.FloatValue){ .allocator = allocator, .json = float_value_json }, json.wktJsonParse),
        try runTimed(io, "pbz FloatValue String JSON parse", iters.json, json.FloatValueStringJson.len, json.WktJsonParseCtx(pbz.FloatValue){ .allocator = allocator, .json = json.FloatValueStringJson }, json.wktJsonParse),
        try runTimed(io, "pbz FloatValue Exponent JSON parse", iters.json, json.FloatValueExponentJson.len, json.WktJsonParseCtx(pbz.FloatValue){ .allocator = allocator, .json = json.FloatValueExponentJson }, json.wktJsonParse),
        try runTimed(io, "pbz NegativeFloatValue JSON stringify", iters.json, negative_float_value_json.len, json.WktJsonStringifyCtx(pbz.FloatValue){ .allocator = allocator, .value = negative_float_value }, json.wktJsonStringify),
        try runTimed(io, "pbz NegativeFloatValue JSON parse", iters.json, negative_float_value_json.len, json.WktJsonParseCtx(pbz.FloatValue){ .allocator = allocator, .json = negative_float_value_json }, json.wktJsonParse),
        try runTimed(io, "pbz ZeroFloatValue JSON stringify", iters.json, zero_float_value_json.len, json.WktJsonStringifyCtx(pbz.FloatValue){ .allocator = allocator, .value = zero_float_value }, json.wktJsonStringify),
        try runTimed(io, "pbz ZeroFloatValue JSON parse", iters.json, zero_float_value_json.len, json.WktJsonParseCtx(pbz.FloatValue){ .allocator = allocator, .json = zero_float_value_json }, json.wktJsonParse),
        try runTimed(io, "pbz FloatValue NaN JSON stringify", iters.json, float_value_nan_json.len, json.WktJsonStringifyCtx(pbz.FloatValue){ .allocator = allocator, .value = float_value_nan }, json.wktJsonStringify),
        try runTimed(io, "pbz FloatValue NaN JSON parse", iters.json, float_value_nan_json.len, json.WktJsonParseCtx(pbz.FloatValue){ .allocator = allocator, .json = float_value_nan_json }, json.wktJsonParse),
        try runTimed(io, "pbz FloatValue Infinity JSON stringify", iters.json, float_value_inf_json.len, json.WktJsonStringifyCtx(pbz.FloatValue){ .allocator = allocator, .value = float_value_inf }, json.wktJsonStringify),
        try runTimed(io, "pbz FloatValue Infinity JSON parse", iters.json, float_value_inf_json.len, json.WktJsonParseCtx(pbz.FloatValue){ .allocator = allocator, .json = float_value_inf_json }, json.wktJsonParse),
        try runTimed(io, "pbz FloatValue NegativeInfinity JSON stringify", iters.json, float_value_neg_inf_json.len, json.WktJsonStringifyCtx(pbz.FloatValue){ .allocator = allocator, .value = float_value_neg_inf }, json.wktJsonStringify),
        try runTimed(io, "pbz FloatValue NegativeInfinity JSON parse", iters.json, float_value_neg_inf_json.len, json.WktJsonParseCtx(pbz.FloatValue){ .allocator = allocator, .json = float_value_neg_inf_json }, json.wktJsonParse),
        try runTimed(io, "pbz Int64Value JSON stringify", iters.json, int64_value_json.len, json.WktJsonStringifyCtx(pbz.Int64Value){ .allocator = allocator, .value = int64_value }, json.wktJsonStringify),
        try runTimed(io, "pbz Int64Value JSON parse", iters.json, int64_value_json.len, json.WktJsonParseCtx(pbz.Int64Value){ .allocator = allocator, .json = int64_value_json }, json.wktJsonParse),
        try runTimed(io, "pbz Int64Value Number JSON parse", iters.json, json.Int64ValueNumberJson.len, json.WktJsonParseCtx(pbz.Int64Value){ .allocator = allocator, .json = json.Int64ValueNumberJson }, json.wktJsonParse),
        try runTimed(io, "pbz Int64Value Exponent JSON parse", iters.json, json.Int64ValueExponentJson.len, json.WktJsonParseCtx(pbz.Int64Value){ .allocator = allocator, .json = json.Int64ValueExponentJson }, json.wktJsonParse),
        try runTimed(io, "pbz ZeroInt64Value JSON stringify", iters.json, zero_int64_value_json.len, json.WktJsonStringifyCtx(pbz.Int64Value){ .allocator = allocator, .value = zero_int64_value }, json.wktJsonStringify),
        try runTimed(io, "pbz ZeroInt64Value JSON parse", iters.json, zero_int64_value_json.len, json.WktJsonParseCtx(pbz.Int64Value){ .allocator = allocator, .json = zero_int64_value_json }, json.wktJsonParse),
        try runTimed(io, "pbz NegativeInt64Value JSON stringify", iters.json, negative_int64_value_json.len, json.WktJsonStringifyCtx(pbz.Int64Value){ .allocator = allocator, .value = negative_int64_value }, json.wktJsonStringify),
        try runTimed(io, "pbz NegativeInt64Value JSON parse", iters.json, negative_int64_value_json.len, json.WktJsonParseCtx(pbz.Int64Value){ .allocator = allocator, .json = negative_int64_value_json }, json.wktJsonParse),
        try runTimed(io, "pbz MinInt64Value JSON stringify", iters.json, min_int64_value_json.len, json.WktJsonStringifyCtx(pbz.Int64Value){ .allocator = allocator, .value = min_int64_value }, json.wktJsonStringify),
        try runTimed(io, "pbz MinInt64Value JSON parse", iters.json, min_int64_value_json.len, json.WktJsonParseCtx(pbz.Int64Value){ .allocator = allocator, .json = min_int64_value_json }, json.wktJsonParse),
        try runTimed(io, "pbz MaxInt64Value JSON stringify", iters.json, max_int64_value_json.len, json.WktJsonStringifyCtx(pbz.Int64Value){ .allocator = allocator, .value = max_int64_value }, json.wktJsonStringify),
        try runTimed(io, "pbz MaxInt64Value JSON parse", iters.json, max_int64_value_json.len, json.WktJsonParseCtx(pbz.Int64Value){ .allocator = allocator, .json = max_int64_value_json }, json.wktJsonParse),
        try runTimed(io, "pbz UInt64Value JSON stringify", iters.json, uint64_value_json.len, json.WktJsonStringifyCtx(pbz.UInt64Value){ .allocator = allocator, .value = uint64_value }, json.wktJsonStringify),
        try runTimed(io, "pbz UInt64Value JSON parse", iters.json, uint64_value_json.len, json.WktJsonParseCtx(pbz.UInt64Value){ .allocator = allocator, .json = uint64_value_json }, json.wktJsonParse),
        try runTimed(io, "pbz UInt64Value Number JSON parse", iters.json, json.UInt64ValueNumberJson.len, json.WktJsonParseCtx(pbz.UInt64Value){ .allocator = allocator, .json = json.UInt64ValueNumberJson }, json.wktJsonParse),
        try runTimed(io, "pbz UInt64Value Exponent JSON parse", iters.json, json.UInt64ValueExponentJson.len, json.WktJsonParseCtx(pbz.UInt64Value){ .allocator = allocator, .json = json.UInt64ValueExponentJson }, json.wktJsonParse),
        try runTimed(io, "pbz ZeroUInt64Value JSON stringify", iters.json, zero_uint64_value_json.len, json.WktJsonStringifyCtx(pbz.UInt64Value){ .allocator = allocator, .value = zero_uint64_value }, json.wktJsonStringify),
        try runTimed(io, "pbz ZeroUInt64Value JSON parse", iters.json, zero_uint64_value_json.len, json.WktJsonParseCtx(pbz.UInt64Value){ .allocator = allocator, .json = zero_uint64_value_json }, json.wktJsonParse),
        try runTimed(io, "pbz MaxUInt64Value JSON stringify", iters.json, max_uint64_value_json.len, json.WktJsonStringifyCtx(pbz.UInt64Value){ .allocator = allocator, .value = max_uint64_value }, json.wktJsonStringify),
        try runTimed(io, "pbz MaxUInt64Value JSON parse", iters.json, max_uint64_value_json.len, json.WktJsonParseCtx(pbz.UInt64Value){ .allocator = allocator, .json = max_uint64_value_json }, json.wktJsonParse),
        try runTimed(io, "pbz Int32Value JSON stringify", iters.json, int32_value_json.len, json.WktJsonStringifyCtx(pbz.Int32Value){ .allocator = allocator, .value = int32_value }, json.wktJsonStringify),
        try runTimed(io, "pbz Int32Value JSON parse", iters.json, int32_value_json.len, json.WktJsonParseCtx(pbz.Int32Value){ .allocator = allocator, .json = int32_value_json }, json.wktJsonParse),
        try runTimed(io, "pbz Int32Value String JSON parse", iters.json, json.Int32ValueStringJson.len, json.WktJsonParseCtx(pbz.Int32Value){ .allocator = allocator, .json = json.Int32ValueStringJson }, json.wktJsonParse),
        try runTimed(io, "pbz Int32Value Exponent JSON parse", iters.json, json.Int32ValueExponentJson.len, json.WktJsonParseCtx(pbz.Int32Value){ .allocator = allocator, .json = json.Int32ValueExponentJson }, json.wktJsonParse),
        try runTimed(io, "pbz ZeroInt32Value JSON stringify", iters.json, zero_int32_value_json.len, json.WktJsonStringifyCtx(pbz.Int32Value){ .allocator = allocator, .value = zero_int32_value }, json.wktJsonStringify),
        try runTimed(io, "pbz ZeroInt32Value JSON parse", iters.json, zero_int32_value_json.len, json.WktJsonParseCtx(pbz.Int32Value){ .allocator = allocator, .json = zero_int32_value_json }, json.wktJsonParse),
        try runTimed(io, "pbz NegativeInt32Value JSON stringify", iters.json, negative_int32_value_json.len, json.WktJsonStringifyCtx(pbz.Int32Value){ .allocator = allocator, .value = negative_int32_value }, json.wktJsonStringify),
        try runTimed(io, "pbz NegativeInt32Value JSON parse", iters.json, negative_int32_value_json.len, json.WktJsonParseCtx(pbz.Int32Value){ .allocator = allocator, .json = negative_int32_value_json }, json.wktJsonParse),
        try runTimed(io, "pbz MinInt32Value JSON stringify", iters.json, min_int32_value_json.len, json.WktJsonStringifyCtx(pbz.Int32Value){ .allocator = allocator, .value = min_int32_value }, json.wktJsonStringify),
        try runTimed(io, "pbz MinInt32Value JSON parse", iters.json, min_int32_value_json.len, json.WktJsonParseCtx(pbz.Int32Value){ .allocator = allocator, .json = min_int32_value_json }, json.wktJsonParse),
        try runTimed(io, "pbz MaxInt32Value JSON stringify", iters.json, max_int32_value_json.len, json.WktJsonStringifyCtx(pbz.Int32Value){ .allocator = allocator, .value = max_int32_value }, json.wktJsonStringify),
        try runTimed(io, "pbz MaxInt32Value JSON parse", iters.json, max_int32_value_json.len, json.WktJsonParseCtx(pbz.Int32Value){ .allocator = allocator, .json = max_int32_value_json }, json.wktJsonParse),
        try runTimed(io, "pbz UInt32Value JSON stringify", iters.json, uint32_value_json.len, json.WktJsonStringifyCtx(pbz.UInt32Value){ .allocator = allocator, .value = uint32_value }, json.wktJsonStringify),
        try runTimed(io, "pbz UInt32Value JSON parse", iters.json, uint32_value_json.len, json.WktJsonParseCtx(pbz.UInt32Value){ .allocator = allocator, .json = uint32_value_json }, json.wktJsonParse),
        try runTimed(io, "pbz UInt32Value String JSON parse", iters.json, json.UInt32ValueStringJson.len, json.WktJsonParseCtx(pbz.UInt32Value){ .allocator = allocator, .json = json.UInt32ValueStringJson }, json.wktJsonParse),
        try runTimed(io, "pbz UInt32Value Exponent JSON parse", iters.json, json.UInt32ValueExponentJson.len, json.WktJsonParseCtx(pbz.UInt32Value){ .allocator = allocator, .json = json.UInt32ValueExponentJson }, json.wktJsonParse),
        try runTimed(io, "pbz ZeroUInt32Value JSON stringify", iters.json, zero_uint32_value_json.len, json.WktJsonStringifyCtx(pbz.UInt32Value){ .allocator = allocator, .value = zero_uint32_value }, json.wktJsonStringify),
        try runTimed(io, "pbz ZeroUInt32Value JSON parse", iters.json, zero_uint32_value_json.len, json.WktJsonParseCtx(pbz.UInt32Value){ .allocator = allocator, .json = zero_uint32_value_json }, json.wktJsonParse),
        try runTimed(io, "pbz MaxUInt32Value JSON stringify", iters.json, max_uint32_value_json.len, json.WktJsonStringifyCtx(pbz.UInt32Value){ .allocator = allocator, .value = max_uint32_value }, json.wktJsonStringify),
        try runTimed(io, "pbz MaxUInt32Value JSON parse", iters.json, max_uint32_value_json.len, json.WktJsonParseCtx(pbz.UInt32Value){ .allocator = allocator, .json = max_uint32_value_json }, json.wktJsonParse),
        try runTimed(io, "pbz BoolValue JSON stringify", iters.json, bool_value_json.len, json.WktJsonStringifyCtx(pbz.BoolValue){ .allocator = allocator, .value = bool_value }, json.wktJsonStringify),
        try runTimed(io, "pbz BoolValue JSON parse", iters.json, bool_value_json.len, json.WktJsonParseCtx(pbz.BoolValue){ .allocator = allocator, .json = bool_value_json }, json.wktJsonParse),
        try runTimed(io, "pbz FalseBoolValue JSON stringify", iters.json, false_bool_value_json.len, json.WktJsonStringifyCtx(pbz.BoolValue){ .allocator = allocator, .value = false_bool_value }, json.wktJsonStringify),
        try runTimed(io, "pbz FalseBoolValue JSON parse", iters.json, false_bool_value_json.len, json.WktJsonParseCtx(pbz.BoolValue){ .allocator = allocator, .json = false_bool_value_json }, json.wktJsonParse),
        try runTimed(io, "pbz StringValue JSON stringify", iters.json, string_value_json.len, json.WktJsonStringifyCtx(pbz.StringValue){ .allocator = allocator, .value = string_value }, json.wktJsonStringify),
        try runTimed(io, "pbz StringValue JSON parse", iters.json, string_value_json.len, json.WktJsonParseCtx(pbz.StringValue){ .allocator = allocator, .json = string_value_json }, json.wktJsonParse),
        try runTimed(io, "pbz StringValue Escape JSON parse", iters.json, json.StringValueEscapeJson.len, json.WktJsonParseCtx(pbz.StringValue){ .allocator = allocator, .json = json.StringValueEscapeJson }, json.wktJsonParse),
        try runTimed(io, "pbz StringValue Surrogate JSON parse", iters.json, json.StringValueSurrogateJson.len, json.WktJsonParseCtx(pbz.StringValue){ .allocator = allocator, .json = json.StringValueSurrogateJson }, json.wktJsonParse),
        try runTimed(io, "pbz EmptyStringValue JSON stringify", iters.json, empty_string_value_json.len, json.WktJsonStringifyCtx(pbz.StringValue){ .allocator = allocator, .value = empty_string_value }, json.wktJsonStringify),
        try runTimed(io, "pbz EmptyStringValue JSON parse", iters.json, empty_string_value_json.len, json.WktJsonParseCtx(pbz.StringValue){ .allocator = allocator, .json = empty_string_value_json }, json.wktJsonParse),
        try runTimed(io, "pbz BytesValue JSON stringify", iters.json, bytes_value_json.len, json.WktJsonStringifyCtx(pbz.BytesValue){ .allocator = allocator, .value = bytes_value }, json.wktJsonStringify),
        try runTimed(io, "pbz BytesValue JSON parse", iters.json, bytes_value_json.len, json.WktJsonParseCtx(pbz.BytesValue){ .allocator = allocator, .json = bytes_value_json }, json.wktJsonParse),
        try runTimed(io, "pbz BytesValue URL JSON parse", iters.json, json.BytesValueUrlJson.len, json.WktJsonParseCtx(pbz.BytesValue){ .allocator = allocator, .json = json.BytesValueUrlJson }, json.wktJsonParse),
        try runTimed(io, "pbz BytesValue StandardBase64 JSON parse", iters.json, json.BytesValueStandardBase64Json.len, json.WktJsonParseCtx(pbz.BytesValue){ .allocator = allocator, .json = json.BytesValueStandardBase64Json }, json.wktJsonParse),
        try runTimed(io, "pbz BytesValue Unpadded JSON parse", iters.json, json.BytesValueUnpaddedJson.len, json.WktJsonParseCtx(pbz.BytesValue){ .allocator = allocator, .json = json.BytesValueUnpaddedJson }, json.wktJsonParse),
        try runTimed(io, "pbz EmptyBytesValue JSON stringify", iters.json, empty_bytes_value_json.len, json.WktJsonStringifyCtx(pbz.BytesValue){ .allocator = allocator, .value = empty_bytes_value }, json.wktJsonStringify),
        try runTimed(io, "pbz EmptyBytesValue JSON parse", iters.json, empty_bytes_value_json.len, json.WktJsonParseCtx(pbz.BytesValue){ .allocator = allocator, .json = empty_bytes_value_json }, json.wktJsonParse),
        try runTimed(io, "generated TextFormat format", iters.text, generated_text.len, json.GeneratedTextFormatCtx{ .allocator = allocator, .person = &generated_person }, json.generatedTextFormat),
        try runTimed(io, "generated TextFormat parse", iters.text, generated_text.len, json.GeneratedTextParseCtx{ .allocator = allocator, .text = generated_text }, json.generatedTextParse),
        try runTimed(io, "dynamic TextFormat format", iters.text, dynamic_text.len, json.DynamicTextFormatCtx{ .allocator = allocator, .file = &file, .message = &dynamic_person }, json.dynamicTextFormat),
        try runTimed(io, "dynamic TextFormat parse", iters.text, dynamic_text.len, json.DynamicTextParseCtx{ .allocator = allocator, .file = &file, .descriptor = desc, .text = dynamic_text }, json.dynamicTextParse),
    };

    for (results) |result| result.print();
}
