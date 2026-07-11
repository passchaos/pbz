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
    person.counts = try allocator.dupe(person_pb.demo.Person.countsEntry, &.{
        .{ .key = "red", .value = 1 },
        .{ .key = "green", .value = 2 },
        .{ .key = "blue", .value = 3 },
    });
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
        \\message Person {
        \\  int32 id = 1;
        \\  string name = 2;
        \\  repeated int32 scores = 3;
        \\  map<string, int32> counts = 4;
        \\}
        \\message Packed {
        \\  repeated int32 values = 1;
        \\}
    );
    defer file.deinit();
    const desc = file.findMessage("Person").?;
    const packed_desc = file.findMessage("Packed").?;

    var generated_person = try makeGeneratedPerson(allocator);
    defer generated_person.deinit(allocator);
    var dynamic_person = try makeDynamicPerson(allocator, desc);
    defer dynamic_person.deinit();
    var generated_packed = try makeGeneratedPacked(allocator);
    defer generated_packed.deinit(allocator);
    var dynamic_packed = try makeDynamicPacked(allocator, packed_desc);
    defer dynamic_packed.deinit();

    const generated_bytes = try generated_person.encode(allocator);
    defer allocator.free(generated_bytes);
    var reusable_writer = pbz.Writer.init(allocator);
    defer reusable_writer.deinit();
    try reusable_writer.bytes.ensureTotalCapacity(allocator, generated_bytes.len);
    const generated_buffer = try allocator.alloc(u8, generated_bytes.len);
    defer allocator.free(generated_buffer);
    const dynamic_bytes = try dynamic_person.encoded(&file);
    defer allocator.free(dynamic_bytes);
    const generated_packed_bytes = try generated_packed.encode(allocator);
    defer allocator.free(generated_packed_bytes);
    var reusable_packed_writer = pbz.Writer.init(allocator);
    defer reusable_packed_writer.deinit();
    try reusable_packed_writer.bytes.ensureTotalCapacity(allocator, generated_packed_bytes.len);
    const generated_packed_buffer = try allocator.alloc(u8, generated_packed_bytes.len);
    defer allocator.free(generated_packed_buffer);
    const dynamic_packed_bytes = try dynamic_packed.encoded(&file);
    defer allocator.free(dynamic_packed_bytes);
    const generated_json = try generated_person.jsonStringifyAlloc(allocator);
    defer allocator.free(generated_json);
    const dynamic_json = try pbz.stringifyJsonAlloc(allocator, &file, &dynamic_person, .{});
    defer allocator.free(dynamic_json);
    const generated_text = try generated_person.formatTextAlloc(allocator);
    defer allocator.free(generated_text);
    const dynamic_text = try pbz.formatTextAlloc(allocator, &file, &dynamic_person, .{});
    defer allocator.free(dynamic_text);

    std.debug.print("pbz benchmark baseline (Zig {s})\n", .{@import("builtin").zig_version_string});
    std.debug.print("payload sizes: person_generated={d} person_dynamic={d} packed_generated={d} packed_dynamic={d} json={d} text={d}\n", .{ generated_bytes.len, dynamic_bytes.len, generated_packed_bytes.len, dynamic_packed_bytes.len, generated_json.len, generated_text.len });

    const results = [_]BenchResult{
        try runTimed(io, "generated binary encode", iters.generated_binary, generated_bytes.len, GeneratedEncodeCtx{ .allocator = allocator, .person = &generated_person }, generatedEncode),
        try runTimed(io, "generated binary writeToAssumeCapacity reuse", iters.generated_binary, generated_bytes.len, GeneratedWriteToCtx{ .writer = &reusable_writer, .person = &generated_person }, generatedWriteToReuse),
        try runTimed(io, "generated binary encodeIntoAssumeCapacity buffer reuse", iters.generated_binary, generated_bytes.len, GeneratedEncodeIntoCtx{ .buffer = generated_buffer, .person = &generated_person }, generatedEncodeIntoReuse),
        try runTimed(io, "generated binary decode", iters.generated_binary, generated_bytes.len, GeneratedDecodeCtx{ .allocator = allocator, .bytes = generated_bytes }, generatedDecode),
        try runTimed(io, "dynamic binary encode", iters.dynamic_binary, dynamic_bytes.len, DynamicEncodeCtx{ .message = &dynamic_person, .file = &file }, dynamicEncode),
        try runTimed(io, "dynamic binary decode", iters.dynamic_binary, dynamic_bytes.len, DynamicDecodeCtx{ .allocator = allocator, .descriptor = desc, .file = &file, .bytes = dynamic_bytes }, dynamicDecode),
        try runTimed(io, "generated packed encode", iters.packed_binary, generated_packed_bytes.len, GeneratedPackedEncodeCtx{ .allocator = allocator, .message = &generated_packed }, generatedPackedEncode),
        try runTimed(io, "generated packed writeToAssumeCapacity reuse", iters.packed_binary, generated_packed_bytes.len, GeneratedPackedWriteToCtx{ .writer = &reusable_packed_writer, .message = &generated_packed }, generatedPackedWriteToReuse),
        try runTimed(io, "generated packed encodeIntoAssumeCapacity buffer reuse", iters.packed_binary, generated_packed_bytes.len, GeneratedPackedEncodeIntoCtx{ .buffer = generated_packed_buffer, .message = &generated_packed }, generatedPackedEncodeIntoReuse),
        try runTimed(io, "generated packed decode", iters.packed_binary, generated_packed_bytes.len, GeneratedPackedDecodeCtx{ .allocator = allocator, .bytes = generated_packed_bytes }, generatedPackedDecode),
        try runTimed(io, "dynamic packed encode", iters.packed_binary, dynamic_packed_bytes.len, DynamicPackedEncodeCtx{ .message = &dynamic_packed, .file = &file }, dynamicPackedEncode),
        try runTimed(io, "dynamic packed decode", iters.packed_binary, dynamic_packed_bytes.len, DynamicPackedDecodeCtx{ .allocator = allocator, .descriptor = packed_desc, .file = &file, .bytes = dynamic_packed_bytes }, dynamicPackedDecode),
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
