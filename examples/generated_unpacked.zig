const std = @import("std");
const pbz = @import("pbz");
const unpacked_pb = @import("generated/unpacked.pb.zig");

const unpacked = unpacked_pb.demo.unpacked;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Even in proto3, repeated primitive fields can opt out of packed encoding.
    // Parsers must also merge packed and unpacked occurrences for compatibility
    // with C++ producers that changed packing options over time.
    std.debug.assert(!unpacked.Unpacked.values_field.is_packed);
    std.debug.assert(!unpacked.Unpacked.flags_field.is_packed);
    std.debug.assert(!unpacked.Unpacked.kinds_field.is_packed);

    var msg = unpacked.Unpacked.init();
    defer msg.deinit(allocator);
    msg.values = try allocator.dupe(i32, &.{ -1, 0, 42 });
    msg.flags = try allocator.dupe(bool, &.{ true, false, true });
    msg.kinds = try allocator.dupe(i32, &.{ unpacked.Kind.KIND_A.toInt(), unpacked.Kind.KIND_B.toInt() });

    const bytes = try msg.encodeInitialized(allocator);
    defer allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, &.{0x0a}) == null); // field 1 packed tag would be length-delimited
    try std.testing.expect(std.mem.indexOf(u8, bytes, &.{0x12}) == null); // field 2 packed tag
    try std.testing.expect(std.mem.indexOf(u8, bytes, &.{0x1a}) == null); // field 3 packed tag

    var decoded = try unpacked.Unpacked.decodeOwnedInitialized(allocator, bytes);
    defer decoded.deinit(allocator);
    try std.testing.expectEqualSlices(i32, &.{ -1, 0, 42 }, decoded.values);
    try std.testing.expectEqualSlices(bool, &.{ true, false, true }, decoded.flags);
    try std.testing.expectEqualSlices(i32, &.{ 1, 2 }, decoded.kinds);

    var writer = pbz.Writer.init(allocator);
    defer writer.deinit();
    try writer.writeInt32(1, 7);
    try writer.writeBytes(1, &.{ 8, 9 }); // packed payload for the same field must merge
    try writer.writeBool(2, true);
    try writer.writeBytes(2, &.{ 0, 1 });
    try writer.writeInt32(3, unpacked.Kind.KIND_A.toInt());
    try writer.writeBytes(3, &.{ @intCast(unpacked.Kind.KIND_B.toInt()) });
    var mixed = try unpacked.Unpacked.decodeOwnedInitialized(allocator, writer.slice());
    defer mixed.deinit(allocator);
    try std.testing.expectEqualSlices(i32, &.{ 7, 8, 9 }, mixed.values);
    try std.testing.expectEqualSlices(bool, &.{ true, false, true }, mixed.flags);
    try std.testing.expectEqualSlices(i32, &.{ 1, 2 }, mixed.kinds);

    const json = try decoded.jsonStringifyAlloc(allocator);
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"values\":[-1,0,42]") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"flags\":[true,false,true]") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "KIND_A") != null);

    var json_roundtrip = try unpacked.Unpacked.jsonParseInitialized(allocator, json);
    defer json_roundtrip.deinit(allocator);
    try std.testing.expectEqualSlices(i32, decoded.values, json_roundtrip.values);
    try std.testing.expectEqualSlices(bool, decoded.flags, json_roundtrip.flags);
    try std.testing.expectEqualSlices(i32, decoded.kinds, json_roundtrip.kinds);

    const text = try decoded.formatTextAlloc(allocator);
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "values: -1") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "flags: true") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "kinds: KIND_A") != null);
    var text_roundtrip = try unpacked.Unpacked.parseTextInitialized(allocator, text);
    defer text_roundtrip.deinit(allocator);
    try std.testing.expectEqualSlices(i32, decoded.values, text_roundtrip.values);
    try std.testing.expectEqualSlices(bool, decoded.flags, text_roundtrip.flags);
    try std.testing.expectEqualSlices(i32, decoded.kinds, text_roundtrip.kinds);
}

comptime {
    _ = pbz;
}
