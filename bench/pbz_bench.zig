const std = @import("std");
const pbz = @import("pbz");
const person_pb = @import("person_pb");

const Iterations = struct {
    generated_binary: usize = 20_000,
    dynamic_binary: usize = 10_000,
    json: usize = 2_000,
    text: usize = 1_000,
};

const BenchResult = struct {
    name: []const u8,
    iterations: usize,
    elapsed_ns: i96,
    bytes_per_iter: usize = 0,

    fn print(self: BenchResult) void {
        const ns_per_iter = @as(f64, @floatFromInt(self.elapsed_ns)) / @as(f64, @floatFromInt(self.iterations));
        const ops_per_sec = @as(f64, @floatFromInt(self.iterations)) * @as(f64, @floatFromInt(std.time.ns_per_s)) / @as(f64, @floatFromInt(self.elapsed_ns));
        if (self.bytes_per_iter != 0) {
            const mb_per_sec = @as(f64, @floatFromInt(self.bytes_per_iter * self.iterations)) * @as(f64, @floatFromInt(std.time.ns_per_s)) / @as(f64, @floatFromInt(self.elapsed_ns)) / (1024.0 * 1024.0);
            std.debug.print("{s}: {d} iters, {d} bytes/iter, {d:.2} ns/op, {d:.2} ops/s, {d:.2} MiB/s\n", .{ self.name, self.iterations, self.bytes_per_iter, ns_per_iter, ops_per_sec, mb_per_sec });
        } else {
            std.debug.print("{s}: {d} iters, {d:.2} ns/op, {d:.2} ops/s\n", .{ self.name, self.iterations, ns_per_iter, ops_per_sec });
        }
    }
};

fn nowNs(io: std.Io) i96 {
    return std.Io.Clock.awake.now(io).nanoseconds;
}

fn runTimed(io: std.Io, name: []const u8, iterations: usize, bytes_per_iter: usize, context: anytype, comptime func: anytype) !BenchResult {
    const start = nowNs(io);
    var i: usize = 0;
    while (i < iterations) : (i += 1) try func(context);
    const elapsed = nowNs(io) - start;
    return .{ .name = name, .iterations = iterations, .elapsed_ns = elapsed, .bytes_per_iter = bytes_per_iter };
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

const GeneratedEncodeCtx = struct { allocator: std.mem.Allocator, person: *const person_pb.demo.Person };
fn generatedEncode(ctx: GeneratedEncodeCtx) !void {
    const bytes = try ctx.person.encode(ctx.allocator);
    ctx.allocator.free(bytes);
}

const GeneratedDecodeCtx = struct { allocator: std.mem.Allocator, bytes: []const u8 };
fn generatedDecode(ctx: GeneratedDecodeCtx) !void {
    var decoded = try person_pb.demo.Person.decode(ctx.allocator, ctx.bytes);
    decoded.deinit(ctx.allocator);
}

const DynamicEncodeCtx = struct { message: *const pbz.DynamicMessage, file: *const pbz.FileDescriptor };
fn dynamicEncode(ctx: DynamicEncodeCtx) !void {
    const bytes = try ctx.message.encoded(ctx.file);
    ctx.message.allocator.free(bytes);
}

const DynamicDecodeCtx = struct { allocator: std.mem.Allocator, descriptor: *const pbz.MessageDescriptor, file: *const pbz.FileDescriptor, bytes: []const u8 };
fn dynamicDecode(ctx: DynamicDecodeCtx) !void {
    var msg = pbz.DynamicMessage.init(ctx.allocator, ctx.descriptor);
    defer msg.deinit();
    try msg.decode(ctx.file, ctx.bytes);
}

const GeneratedJsonStringifyCtx = struct { allocator: std.mem.Allocator, person: *const person_pb.demo.Person };
fn generatedJsonStringify(ctx: GeneratedJsonStringifyCtx) !void {
    const json = try ctx.person.jsonStringifyAlloc(ctx.allocator);
    ctx.allocator.free(json);
}

const GeneratedJsonParseCtx = struct { allocator: std.mem.Allocator, json: []const u8 };
fn generatedJsonParse(ctx: GeneratedJsonParseCtx) !void {
    var decoded = try person_pb.demo.Person.jsonParse(ctx.allocator, ctx.json);
    decoded.deinit(ctx.allocator);
}

const DynamicJsonStringifyCtx = struct { allocator: std.mem.Allocator, file: *const pbz.FileDescriptor, message: *const pbz.DynamicMessage };
fn dynamicJsonStringify(ctx: DynamicJsonStringifyCtx) !void {
    const json = try pbz.stringifyJsonAlloc(ctx.allocator, ctx.file, ctx.message, .{});
    ctx.allocator.free(json);
}

const DynamicJsonParseCtx = struct { allocator: std.mem.Allocator, file: *const pbz.FileDescriptor, descriptor: *const pbz.MessageDescriptor, json: []const u8 };
fn dynamicJsonParse(ctx: DynamicJsonParseCtx) !void {
    var msg = try pbz.parseJsonAlloc(ctx.allocator, ctx.file, ctx.descriptor, ctx.json, .{});
    msg.deinit();
}

const GeneratedTextFormatCtx = struct { allocator: std.mem.Allocator, person: *const person_pb.demo.Person };
fn generatedTextFormat(ctx: GeneratedTextFormatCtx) !void {
    const text = try ctx.person.formatTextAlloc(ctx.allocator);
    ctx.allocator.free(text);
}

const GeneratedTextParseCtx = struct { allocator: std.mem.Allocator, text: []const u8 };
fn generatedTextParse(ctx: GeneratedTextParseCtx) !void {
    var decoded = try person_pb.demo.Person.parseText(ctx.allocator, ctx.text);
    decoded.deinit(ctx.allocator);
}

const DynamicTextFormatCtx = struct { allocator: std.mem.Allocator, file: *const pbz.FileDescriptor, message: *const pbz.DynamicMessage };
fn dynamicTextFormat(ctx: DynamicTextFormatCtx) !void {
    const text = try pbz.formatTextAlloc(ctx.allocator, ctx.file, ctx.message, .{});
    ctx.allocator.free(text);
}

const DynamicTextParseCtx = struct { allocator: std.mem.Allocator, file: *const pbz.FileDescriptor, descriptor: *const pbz.MessageDescriptor, text: []const u8 };
fn dynamicTextParse(ctx: DynamicTextParseCtx) !void {
    var msg = try pbz.parseTextAlloc(ctx.allocator, ctx.file, ctx.descriptor, ctx.text);
    msg.deinit();
}

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
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
    );
    defer file.deinit();
    const desc = file.findMessage("Person").?;

    var generated_person = try makeGeneratedPerson(allocator);
    defer generated_person.deinit(allocator);
    var dynamic_person = try makeDynamicPerson(allocator, desc);
    defer dynamic_person.deinit();

    const generated_bytes = try generated_person.encode(allocator);
    defer allocator.free(generated_bytes);
    const dynamic_bytes = try dynamic_person.encoded(&file);
    defer allocator.free(dynamic_bytes);
    const generated_json = try generated_person.jsonStringifyAlloc(allocator);
    defer allocator.free(generated_json);
    const dynamic_json = try pbz.stringifyJsonAlloc(allocator, &file, &dynamic_person, .{});
    defer allocator.free(dynamic_json);
    const generated_text = try generated_person.formatTextAlloc(allocator);
    defer allocator.free(generated_text);
    const dynamic_text = try pbz.formatTextAlloc(allocator, &file, &dynamic_person, .{});
    defer allocator.free(dynamic_text);

    std.debug.print("pbz benchmark baseline (Zig {s})\n", .{@import("builtin").zig_version_string});
    std.debug.print("payload sizes: generated={d} dynamic={d} json={d} text={d}\n", .{ generated_bytes.len, dynamic_bytes.len, generated_json.len, generated_text.len });

    const results = [_]BenchResult{
        try runTimed(io, "generated binary encode", iters.generated_binary, generated_bytes.len, GeneratedEncodeCtx{ .allocator = allocator, .person = &generated_person }, generatedEncode),
        try runTimed(io, "generated binary decode", iters.generated_binary, generated_bytes.len, GeneratedDecodeCtx{ .allocator = allocator, .bytes = generated_bytes }, generatedDecode),
        try runTimed(io, "dynamic binary encode", iters.dynamic_binary, dynamic_bytes.len, DynamicEncodeCtx{ .message = &dynamic_person, .file = &file }, dynamicEncode),
        try runTimed(io, "dynamic binary decode", iters.dynamic_binary, dynamic_bytes.len, DynamicDecodeCtx{ .allocator = allocator, .descriptor = desc, .file = &file, .bytes = dynamic_bytes }, dynamicDecode),
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
