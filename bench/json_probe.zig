// Focused JSON parse probe for fast iteration. Not part of the shipped
// cross-language matrix; it builds the same generated message fixtures used by
// bench/pbz_bench.zig, stringifies them once, and times `jsonParse` for each
// shape so JSON parser changes can be measured without a full ReleaseFast
// benchmark rebuild.
const std = @import("std");
const person_pb = @import("person_pb");

const LargeMapEntryCount = 1024;

fn run(comptime label: []const u8, comptime Message: type, allocator: std.mem.Allocator, io: std.Io, text: []const u8, iterations: usize) !void {
    for (0..200) |_| {
        var msg = try Message.jsonParse(allocator, text);
        msg.deinit(allocator);
    }
    var best: i96 = std.math.maxInt(i96);
    for (0..5) |_| {
        const start = std.Io.Clock.awake.now(io).nanoseconds;
        for (0..iterations) |_| {
            var msg = try Message.jsonParse(allocator, text);
            msg.deinit(allocator);
            std.mem.doNotOptimizeAway(&msg);
        }
        best = @min(best, std.Io.Clock.awake.now(io).nanoseconds - start);
    }
    std.debug.print("{s}: {d:.1} ns/op ({d} bytes)\n", .{
        label,
        @as(f64, @floatFromInt(best)) / @as(f64, @floatFromInt(iterations)),
        text.len,
    });
}

fn makePerson(allocator: std.mem.Allocator) !person_pb.demo.Person {
    var msg = person_pb.demo.Person.init();
    errdefer msg.deinit(allocator);
    msg.id = 7;
    msg.name = "Zig";
    msg.scores = try allocator.dupe(i32, &.{ 10, 20, 30, 40, 50, 60, 70, 80 });
    try msg.counts.put(allocator, "red", 1);
    try msg.counts.put(allocator, "green", 2);
    try msg.counts.put(allocator, "blue", 3);
    return msg;
}

fn makeScalarMix(allocator: std.mem.Allocator) !person_pb.demo.ScalarMix {
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

fn makeTextBytes(allocator: std.mem.Allocator) !person_pb.demo.TextBytes {
    var msg = person_pb.demo.TextBytes.init();
    errdefer msg.deinit(allocator);
    msg.title = "ASCII title for protobuf";
    msg.payload = "0123456789abcdef0123456789abcdef";
    msg.tags = try allocator.dupe([]const u8, &.{ "alpha", "beta", "gamma", "delta" });
    msg.chunks = try allocator.dupe([]const u8, &.{ "chunk-one", "chunk-two", "chunk-three", "chunk-four" });
    return msg;
}

fn presenceChild(id: i32, label: []const u8) person_pb.demo.PresenceMix.Child {
    var child = person_pb.demo.PresenceMix.Child.init();
    child.id = id;
    child.label = label;
    return child;
}

fn makePresenceMix(allocator: std.mem.Allocator) !person_pb.demo.PresenceMix {
    var msg = person_pb.demo.PresenceMix.init();
    errdefer msg.deinit(allocator);
    msg.count = 0;
    msg.has_count = true;
    msg.note = "";
    msg.has_note = true;
    msg.raw = "presence-raw";
    msg.has_raw = true;
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

fn makeComplex(allocator: std.mem.Allocator) !person_pb.demo.Complex {
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

fn makeLargeMap(allocator: std.mem.Allocator) !person_pb.demo.LargeMap {
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

pub fn main() !void {
    const allocator = std.heap.c_allocator;
    const io = std.Io.Threaded.global_single_threaded.io();

    var person = try makePerson(allocator);
    defer person.deinit(allocator);
    const person_json = try person.jsonStringifyAlloc(allocator);
    defer allocator.free(person_json);
    try run("Person JSON parse", person_pb.demo.Person, allocator, io, person_json, 20000);

    var scalarmix = try makeScalarMix(allocator);
    defer scalarmix.deinit(allocator);
    const scalarmix_json = try scalarmix.jsonStringifyAlloc(allocator);
    defer allocator.free(scalarmix_json);
    try run("ScalarMix JSON parse", person_pb.demo.ScalarMix, allocator, io, scalarmix_json, 2000);

    var textbytes = try makeTextBytes(allocator);
    defer textbytes.deinit(allocator);
    const textbytes_json = try textbytes.jsonStringifyAlloc(allocator);
    defer allocator.free(textbytes_json);
    try run("TextBytes JSON parse", person_pb.demo.TextBytes, allocator, io, textbytes_json, 20000);

    var presencemix = try makePresenceMix(allocator);
    defer presencemix.deinit(allocator);
    const presencemix_json = try presencemix.jsonStringifyAlloc(allocator);
    defer allocator.free(presencemix_json);
    try run("PresenceMix JSON parse", person_pb.demo.PresenceMix, allocator, io, presencemix_json, 20000);

    var complex = try makeComplex(allocator);
    defer complex.deinit(allocator);
    const complex_json = try complex.jsonStringifyAlloc(allocator);
    defer allocator.free(complex_json);
    try run("Complex JSON parse", person_pb.demo.Complex, allocator, io, complex_json, 20000);

    var large_map = try makeLargeMap(allocator);
    defer large_map.deinit(allocator);
    const large_map_json = try large_map.jsonStringifyAlloc(allocator);
    defer allocator.free(large_map_json);
    try run("LargeMap JSON parse", person_pb.demo.LargeMap, allocator, io, large_map_json, 2000);
}
