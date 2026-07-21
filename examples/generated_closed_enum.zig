const std = @import("std");
const pbz = @import("pbz");
const closed_pb = @import("generated/closed_enum.pb.zig");

const closed = closed_pb.demo.closedenum;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Proto2 enums are closed. Unknown numeric enum values must be preserved as
    // raw unknown fields instead of being assigned to the typed enum field,
    // matching C++ protobuf's closed-enum behavior.
    var writer = pbz.Writer.init(allocator);
    defer writer.deinit();
    try writer.writeInt32(1, closed.Kind.KIND_OK.toInt());
    try writer.writeInt32(1, 123); // unknown singular enum value
    try writer.writeInt32(2, closed.Kind.KIND_OK.toInt());
    try writer.writeInt32(2, 124); // unknown repeated enum value
    try writer.writeBytes(2, &.{ @intCast(closed.Kind.KIND_OK.toInt()), 125 }); // packed mixed known+unknown

    var decoded = try closed.ClosedEnum.decodeOwnedInitialized(allocator, writer.slice());
    defer decoded.deinit(allocator);
    try std.testing.expect(decoded.has_kind);
    try std.testing.expectEqual(closed.Kind.KIND_OK.toInt(), decoded.kind);
    try std.testing.expectEqualSlices(i32, &.{ closed.Kind.KIND_OK.toInt(), closed.Kind.KIND_OK.toInt() }, decoded.history);
    try std.testing.expectEqual(@as(usize, 3), decoded.unknownFieldCount());
    try std.testing.expectEqual(@as(usize, 1), try decoded.unknownFieldCountByNumber(1));
    try std.testing.expectEqual(@as(usize, 2), try decoded.unknownFieldCountByNumber(2));

    const encoded = try decoded.encodeInitialized(allocator);
    defer allocator.free(encoded);
    try std.testing.expect(std.mem.indexOf(u8, encoded, &.{ 0x08, 0x7b }) != null); // field 1 value 123
    try std.testing.expect(std.mem.indexOf(u8, encoded, &.{ 0x10, 0x7c }) != null); // field 2 value 124
    try std.testing.expect(std.mem.indexOf(u8, encoded, &.{ 0x10, 0x7d }) != null); // field 2 value 125 from packed payload

    try std.testing.expectError(error.InvalidEnumValue, closed.ClosedEnum.jsonParseInitialized(allocator, "{\"kind\":123}"));
    try std.testing.expectError(error.InvalidEnumValue, closed.ClosedEnum.parseTextInitialized(allocator, "kind: 123\n"));

    const json = try decoded.jsonStringifyAlloc(allocator);
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "KIND_OK") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "123") == null);

    const text = try decoded.formatTextAlloc(allocator);
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "kind: KIND_OK") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "history: KIND_OK") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "1: 123") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "2: 124") != null);
}

comptime {
    _ = pbz;
}
