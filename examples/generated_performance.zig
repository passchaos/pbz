const std = @import("std");
const pbz = @import("pbz");
const person_pb = @import("generated/person.pb.zig");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Caller-provided buffers avoid per-call allocation on hot encode paths.
    var person = person_pb.demo.Person.init();
    defer person.deinit(allocator);
    person.id = 7;
    person.name = "Zig";
    person.scores = try allocator.dupe(i32, &.{ 10, 20, 30 });
    try person.counts.put(allocator, "red", 1);

    const encoded_person = try person.encode(allocator);
    defer allocator.free(encoded_person);
    var person_buffer: [128]u8 = undefined;
    const fast_person = try person.encodeIntoAssumeCapacityTrustedUtf8(&person_buffer);
    std.debug.assert(std.mem.eql(u8, fast_person, encoded_person));

    // Length-delimited bytes/string fields expose borrowed views and borrowed
    // header+payload slices so callers can avoid copying large payloads.
    var large = person_pb.demo.LargeBytes.init();
    defer large.deinit(allocator);
    large.payload = "large-payload";
    large.chunks = try allocator.dupe([]const u8, &.{ "chunk-a", "chunk-b" });

    const large_bytes = try large.encode(allocator);
    defer allocator.free(large_bytes);
    const payload_view = (try person_pb.demo.LargeBytes.payloadBytesView(large_bytes)).?;
    std.debug.assert(std.mem.eql(u8, payload_view, large.payload));

    var payload_header: [20]u8 = undefined;
    const payload_slices = try person_pb.demo.LargeBytes.payloadBytesSlices(&payload_header, large.payload);
    std.debug.assert(std.mem.eql(u8, payload_slices.payload, large.payload));
    std.debug.assert(payload_slices.header.len + payload_slices.payload.len <= large_bytes.len);

    var chunk_header: [20]u8 = undefined;
    const chunk_slices = try person_pb.demo.LargeBytes.chunksBytesSlices(&chunk_header, large.chunks[0]);
    std.debug.assert(std.mem.eql(u8, chunk_slices.payload, large.chunks[0]));

    // Packed fixed-width fields can be viewed directly on little-endian targets
    // and can also be emitted as borrowed header+payload slices.
    var fixed = person_pb.demo.SFixedPacked.init();
    defer fixed.deinit(allocator);
    fixed.values = try allocator.dupe(i32, &.{ -5, 0, 42 });
    const fixed_bytes = try fixed.encode(allocator);
    defer allocator.free(fixed_bytes);
    const fixed_view = (try person_pb.demo.SFixedPacked.valuesPackedFixedView(fixed_bytes)).?;
    std.debug.assert(fixed_view.len == fixed.values.len);

    var fixed_header: [20]u8 = undefined;
    const fixed_slices = try person_pb.demo.SFixedPacked.valuesPackedFixedSlices(&fixed_header, fixed.values);
    std.debug.assert(std.mem.eql(u8, fixed_slices.payload, std.mem.sliceAsBytes(fixed.values)));

    var bools = person_pb.demo.BoolPacked.init();
    defer bools.deinit(allocator);
    bools.values = try allocator.dupe(bool, &.{ true, false, true });
    var bool_header: [20]u8 = undefined;
    const bool_slices = try person_pb.demo.BoolPacked.valuesPackedBoolSlices(&bool_header, bools.values);
    std.debug.assert(std.mem.eql(u8, bool_slices.payload, std.mem.sliceAsBytes(bools.values)));

    // Packed varint fields expose typed iterators for no-allocation scans.
    var packed_msg = person_pb.demo.Packed.init();
    defer packed_msg.deinit(allocator);
    packed_msg.values = try allocator.dupe(i32, &.{ 1, 128, -7, 4096 });
    const packed_bytes = try packed_msg.encode(allocator);
    defer allocator.free(packed_bytes);

    var it = (try person_pb.demo.Packed.valuesPackedIterator(packed_bytes)).?;
    var packed_count: usize = 0;
    while (try it.next()) |value| : (packed_count += 1) {
        std.debug.assert(value == packed_msg.values[packed_count]);
    }
    std.debug.assert(packed_count == packed_msg.values.len);

    var reusable_packed = try packed_msg.cloneOwned(allocator);
    defer reusable_packed.deinit(allocator);
    try reusable_packed.decodeKnownReuse(allocator, packed_bytes);
    std.debug.assert(std.mem.eql(i32, reusable_packed.values, packed_msg.values));

    // Known-schema decode reuse keeps previously allocated repeated buffers and
    // skips unknown-field preservation for trusted hot-loop payloads.
    var scalar = person_pb.demo.ScalarMix.init();
    defer scalar.deinit(allocator);
    scalar.active = true;
    scalar.count = 3;
    scalar.total = 9;
    scalar.delta = -2;
    scalar.big_delta = -11;
    scalar.checksum = 0xabcdef01;
    scalar.token = 0x0102030405060708;
    scalar.signed_fixed = -123;
    scalar.signed_big_fixed = -456;
    scalar.ratio = 1.25;
    scalar.score = 2.5;
    scalar.kind = person_pb.demo.BenchKind.BENCH_KIND_ALPHA.toInt();
    scalar.flags = try allocator.dupe(bool, &.{ true, false, true });
    scalar.ids = try allocator.dupe(u64, &.{ 1, 128, 4096 });

    const scalar_bytes = try scalar.encode(allocator);
    defer allocator.free(scalar_bytes);

    var reusable = try scalar.cloneOwned(allocator);
    defer reusable.deinit(allocator);
    try reusable.decodeKnownReuse(allocator, scalar_bytes);
    std.debug.assert(reusable.active);
    std.debug.assert(reusable.flags.len == scalar.flags.len);
    std.debug.assert(reusable.ids.len == scalar.ids.len);
    std.debug.assert(reusable.ids[2] == 4096);
}

comptime {
    _ = pbz;
}
