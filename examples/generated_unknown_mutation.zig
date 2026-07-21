const std = @import("std");
const pbz = @import("pbz");
const person_pb = @import("generated/person.pb.zig");

const Person = person_pb.demo.Person;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Generated messages preserve exact raw unknown fields.  They also expose a
    // small mutation/query surface for callers that need C++ UnknownFieldSet-like
    // workflows while still round-tripping the original wire bytes exactly.
    var msg = Person.init();
    defer msg.deinit(allocator);
    msg.id = 7;

    var raw_a = pbz.Writer.init(allocator);
    defer raw_a.deinit();
    try raw_a.writeUInt32(100, 1);
    var raw_b = pbz.Writer.init(allocator);
    defer raw_b.deinit();
    try raw_b.writeString(101, "diagnostic");
    var raw_c = pbz.Writer.init(allocator);
    defer raw_c.deinit();
    try raw_c.writeUInt32(100, 2);

    try msg.appendUnknownRaw(allocator, raw_a.slice());
    try msg.appendUnknownRaw(allocator, raw_b.slice());
    try msg.appendUnknownRaw(allocator, raw_c.slice());
    try std.testing.expectEqual(@as(usize, 3), msg.unknownFieldCount());
    try std.testing.expect(try msg.hasUnknownFieldNumber(100));
    try std.testing.expectEqual(@as(usize, 2), try msg.unknownFieldCountByNumber(100));

    const matched = try msg.unknownFieldsByNumberAlloc(allocator, 100);
    defer allocator.free(matched);
    try std.testing.expectEqual(@as(usize, 2), matched.len);
    try std.testing.expectEqualSlices(u8, raw_a.slice(), matched[0]);
    try std.testing.expectEqualSlices(u8, raw_c.slice(), matched[1]);

    const numbers = try msg.unknownFieldNumbersAlloc(allocator);
    defer allocator.free(numbers);
    try std.testing.expectEqualSlices(pbz.FieldNumber, &.{ 100, 101, 100 }, numbers);
    const runs = try msg.unknownFieldNumberRunsAlloc(allocator);
    defer allocator.free(runs);
    try std.testing.expectEqual(@as(usize, 2), pbz.wire.rawFieldNumberRunCount(runs, 100));

    const encoded = try msg.encode(allocator);
    defer allocator.free(encoded);
    try std.testing.expect(std.mem.indexOf(u8, encoded, raw_a.slice()) != null);
    try std.testing.expect(std.mem.indexOf(u8, encoded, raw_b.slice()) != null);
    try std.testing.expect(std.mem.indexOf(u8, encoded, raw_c.slice()) != null);

    try msg.clearUnknownFieldsByNumber(allocator, 100);
    try std.testing.expectEqual(@as(usize, 1), msg.unknownFieldCount());
    try std.testing.expect(!try msg.hasUnknownFieldNumber(100));
    try std.testing.expect(try msg.hasUnknownFieldNumber(101));

    msg.clearUnknownFields(allocator);
    try std.testing.expectEqual(@as(usize, 0), msg.unknownFieldCount());

    try std.testing.expectError(error.InvalidWireType, msg.appendUnknownRaw(allocator, &.{0x0f}));
    try std.testing.expectEqual(@as(usize, 0), msg.unknownFieldCount());
}

comptime {
    _ = pbz;
}
