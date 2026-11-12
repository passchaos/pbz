const std = @import("std");
const pbz = @import("pbz");
const person_pb = @import("person_pb");

const default_iterations: usize = 100_000;
const default_seed: u64 = 0;
const max_input_len: usize = 8192;

const Fixtures = struct {
    file: pbz.schema.FileDescriptor,
    descriptor: *const pbz.schema.MessageDescriptor,
    binary: []const u8,
    json: []const u8,
    text: []const u8,
};

const fuzz_schema =
    \\syntax = "proto3";
    \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
    \\message M {
    \\  int32 id = 1;
    \\  string name = 2;
    \\  bytes payload = 3;
    \\  repeated int32 nums = 4;
    \\  repeated fixed32 fixed = 5;
    \\  map<string, int32> counts = 6;
    \\  Kind kind = 7;
    \\  M child = 8;
    \\  oneof pick { string label = 9; int64 code = 10; }
    \\}
;

fn makeFixtures(allocator: std.mem.Allocator) !Fixtures {
    var file = try pbz.ProtoParser.parse(allocator, fuzz_schema);
    errdefer file.deinit();
    const descriptor = file.findMessage("M").?;

    var message = pbz.DynamicMessage.init(allocator, descriptor);
    defer message.deinit();
    try message.add(descriptor.findField("id").?, .{ .int32 = 7 });
    try message.add(descriptor.findField("name").?, .{ .string = try allocator.dupe(u8, "fuzz") });
    try message.add(descriptor.findField("payload").?, .{ .bytes = try allocator.dupe(u8, &.{ 1, 2, 3, 4 }) });
    for ([_]i32{ 1, 2, 3 }) |value| try message.add(descriptor.findField("nums").?, .{ .int32 = value });
    for ([_]u32{ 5, 6 }) |value| try message.add(descriptor.findField("fixed").?, .{ .fixed32 = value });
    {
        const entry = try allocator.create(pbz.dynamic.MapEntry);
        entry.* = .{ .key = .{ .string = try allocator.dupe(u8, "k") }, .value = .{ .int32 = 1 } };
        try message.add(descriptor.findField("counts").?, .{ .map_entry = entry });
    }
    try message.add(descriptor.findField("kind").?, .{ .enumeration = 1 });
    try message.add(descriptor.findField("label").?, .{ .string = try allocator.dupe(u8, "pick") });

    const binary = try message.encoded(&file);
    errdefer allocator.free(binary);
    const json = try pbz.json.stringifyAlloc(allocator, &file, &message, .{});
    errdefer allocator.free(json);
    const text = try pbz.text.formatAlloc(allocator, &file, &message, .{});
    errdefer allocator.free(text);
    return .{
        .file = file,
        .descriptor = descriptor,
        .binary = binary,
        .json = json,
        .text = text,
    };
}

fn deinitFixtures(allocator: std.mem.Allocator, fixtures: *Fixtures) void {
    allocator.free(fixtures.binary);
    allocator.free(fixtures.json);
    allocator.free(fixtures.text);
    fixtures.file.deinit();
}

fn generate(rng: std.Random, buffer: []u8, valid: []const u8) usize {
    if (rng.intRangeLessThan(u8, 0, 3) == 0) {
        const len = rng.intRangeAtMost(usize, 0, buffer.len);
        rng.bytes(buffer[0..len]);
        return len;
    }
    var len = @min(valid.len, buffer.len);
    @memcpy(buffer[0..len], valid[0..len]);
    const mutations = rng.intRangeAtMost(usize, 1, 8);
    var index: usize = 0;
    while (index < mutations) : (index += 1) {
        if (len != 0 and rng.boolean()) {
            buffer[rng.intRangeLessThan(usize, 0, len)] = rng.int(u8);
        } else if (len < buffer.len) {
            buffer[len] = rng.int(u8);
            len += 1;
        }
    }
    if (rng.boolean() and len != 0) len = rng.intRangeAtMost(usize, 0, len);
    return len;
}

fn fuzzWire(bytes: []const u8) void {
    var reader = pbz.wire.Reader.init(bytes);
    while (true) {
        const maybe_tag = reader.nextTag() catch break;
        const tag = maybe_tag orelse break;
        reader.skipValue(tag) catch break;
    }
}

fn fuzzDescriptor(allocator: std.mem.Allocator, bytes: []const u8) void {
    if (pbz.decodeFileDescriptorProto(allocator, bytes)) |file_value| {
        var file = file_value;
        file.deinit();
    } else |_| {}
}

fn fuzzProtoParser(allocator: std.mem.Allocator, bytes: []const u8) void {
    if (pbz.ProtoParser.parse(allocator, bytes)) |file_value| {
        var file = file_value;
        file.deinit();
    } else |_| {}
}

fn fuzzBinary(allocator: std.mem.Allocator, fixtures: *const Fixtures, bytes: []const u8) void {
    var message = pbz.DynamicMessage.init(allocator, fixtures.descriptor);
    defer message.deinit();
    message.decode(&fixtures.file, bytes) catch return;
    var writer = pbz.Writer.init(allocator);
    defer writer.deinit();
    message.encode(&fixtures.file, &writer) catch return;
}

fn fuzzJson(allocator: std.mem.Allocator, fixtures: *const Fixtures, bytes: []const u8) void {
    var message = pbz.json.parseAlloc(allocator, &fixtures.file, fixtures.descriptor, bytes, .{}) catch return;
    defer message.deinit();
    var writer = pbz.Writer.init(allocator);
    defer writer.deinit();
    message.encode(&fixtures.file, &writer) catch return;
}

fn fuzzText(allocator: std.mem.Allocator, fixtures: *const Fixtures, bytes: []const u8) void {
    var message = pbz.text.parseAlloc(allocator, &fixtures.file, fixtures.descriptor, bytes) catch return;
    defer message.deinit();
    var writer = pbz.Writer.init(allocator);
    defer writer.deinit();
    message.encode(&fixtures.file, &writer) catch return;
}

fn fuzzGenerated(allocator: std.mem.Allocator, bytes: []const u8) void {
    var message = person_pb.demo.Person.decodeOwned(allocator, bytes) catch return;
    defer message.deinit(allocator);
    const encoded = message.encode(allocator) catch return;
    allocator.free(encoded);
}

/// decodeReuse/decodeOwnedReuse deinit the destination on error, so reset the
/// persistent message to a valid empty state after a failed decode.
fn fuzzGeneratedReuse(allocator: std.mem.Allocator, message: *person_pb.demo.Person, bytes: []const u8) void {
    message.decodeReuse(allocator, bytes) catch {
        message.* = person_pb.demo.Person.init();
        return;
    };
    message.decodeOwnedReuse(allocator, bytes) catch {
        message.* = person_pb.demo.Person.init();
        return;
    };
    const encoded = message.encode(allocator) catch return;
    allocator.free(encoded);
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var iterations: usize = default_iterations;
    var seed: u64 = default_seed;
    var arg_it = init.minimal.args.iterate();
    _ = arg_it.next();
    while (arg_it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--iterations")) {
            iterations = try std.fmt.parseInt(usize, arg_it.next() orelse return error.MissingIterations, 10);
        } else if (std.mem.startsWith(u8, arg, "--iterations=")) {
            iterations = try std.fmt.parseInt(usize, arg["--iterations=".len..], 10);
        } else if (std.mem.eql(u8, arg, "--seed")) {
            seed = try std.fmt.parseInt(u64, arg_it.next() orelse return error.MissingSeed, 10);
        } else if (std.mem.startsWith(u8, arg, "--seed=")) {
            seed = try std.fmt.parseInt(u64, arg["--seed=".len..], 10);
        } else if (std.mem.eql(u8, arg, "--help")) {
            try printUsage(io);
            return;
        } else {
            try printUsage(io);
            return error.UnknownArgument;
        }
    }

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    // Fixtures must outlive the per-iteration arena reset.
    var fixtures = try makeFixtures(allocator);
    defer deinitFixtures(allocator, &fixtures);

    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();

    var reuse_message = person_pb.demo.Person.init();
    defer reuse_message.deinit(allocator);

    var binary_buffer: [max_input_len]u8 = undefined;
    var json_buffer: [max_input_len]u8 = undefined;
    var text_buffer: [max_input_len]u8 = undefined;

    const start = std.Io.Clock.awake.now(io).nanoseconds;
    var iteration: usize = 0;
    while (iteration < iterations) : (iteration += 1) {
        _ = arena.reset(.retain_capacity);
        const scratch = arena.allocator();

        const binary_len = generate(rng, &binary_buffer, fixtures.binary);
        const json_len = generate(rng, &json_buffer, fixtures.json);
        const text_len = generate(rng, &text_buffer, fixtures.text);

        fuzzWire(binary_buffer[0..binary_len]);
        fuzzDescriptor(scratch, binary_buffer[0..binary_len]);
        fuzzProtoParser(scratch, binary_buffer[0..binary_len]);
        fuzzBinary(scratch, &fixtures, binary_buffer[0..binary_len]);
        fuzzJson(scratch, &fixtures, json_buffer[0..json_len]);
        fuzzText(scratch, &fixtures, text_buffer[0..text_len]);
        fuzzGenerated(scratch, binary_buffer[0..binary_len]);
        fuzzGeneratedReuse(allocator, &reuse_message, binary_buffer[0..binary_len]);
    }
    const elapsed = std.Io.Clock.awake.now(io).nanoseconds - start;

    const elapsed_ns: f64 = @floatFromInt(elapsed);
    const iterations_f: f64 = @floatFromInt(iterations);
    std.debug.print(
        "fuzz: {d} iterations, seed {d}, {d:.1} iter/s\n",
        .{ iterations, seed, iterations_f * 1_000_000_000.0 / elapsed_ns },
    );
}

fn printUsage(io: std.Io) !void {
    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writerStreaming(io, &stderr_buffer);
    try stderr_writer.interface.writeAll(
        \\usage: pbz-fuzz [--iterations N] [--seed N]
        \\
        \\Deterministic standalone fuzzer for the wire reader, descriptor decoder,
        \\.proto parser, and dynamic binary/JSON/TextFormat parsers.
        \\
    );
    try stderr_writer.interface.flush();
}
