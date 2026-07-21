const std = @import("std");
const pbz = @import("pbz");
const person_pb = @import("generated/person.pb.zig");

const demo = person_pb.demo;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // protoc stores proto3 `optional` fields in synthetic oneofs inside
    // FileDescriptorProto.  Generated pbz types intentionally expose the
    // source-level shape instead: plain fields plus has_* bits, while real
    // user-authored oneofs continue to use tagged unions.
    var msg = demo.PresenceMix.init();
    defer msg.deinit(allocator);
    try std.testing.expect(!msg.has_count);
    try std.testing.expect(!msg.has_note);
    try std.testing.expect(!msg.has_raw);
    try std.testing.expectEqualStrings("optional", demo.PresenceMix.count_field.cardinality);
    try std.testing.expect(demo.PresenceMix.count_field.has_presence);

    msg.count = 0;
    msg.has_count = true;
    msg.note = "";
    msg.has_note = true;
    msg.raw = "raw";
    msg.has_raw = true;
    msg.pick = .{ .name = "chosen" };

    const bytes = try msg.encodeInitialized(allocator);
    defer allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, &.{ 0x08, 0x00 }) != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, &.{ 0x12, 0x00 }) != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, &.{ 0x1a, 0x03, 'r', 'a', 'w' }) != null);

    var decoded = try demo.PresenceMix.decodeOwnedInitialized(allocator, bytes);
    defer decoded.deinit(allocator);
    try std.testing.expect(decoded.has_count);
    try std.testing.expectEqual(@as(i32, 0), decoded.count);
    try std.testing.expect(decoded.has_note);
    try std.testing.expectEqualStrings("", decoded.note);
    try std.testing.expect(decoded.has_raw);
    try std.testing.expectEqualStrings("raw", decoded.raw);
    switch (decoded.pick) {
        .name => |name| try std.testing.expectEqualStrings("chosen", name),
        else => return error.UnexpectedOneof,
    }

    const json = try decoded.jsonStringifyAlloc(allocator);
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"count\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"note\":\"\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"raw\":\"cmF3\"") != null);

    var parsed_nulls = try demo.PresenceMix.jsonParse(allocator,
        \\{"count":null,"note":null,"raw":null}
    );
    defer parsed_nulls.deinit(allocator);
    try std.testing.expect(!parsed_nulls.has_count);
    try std.testing.expect(!parsed_nulls.has_note);
    try std.testing.expect(!parsed_nulls.has_raw);

    var parsed_json = try demo.PresenceMix.jsonParse(allocator,
        \\{"count":0,"note":"","raw":"cmF3"}
    );
    defer parsed_json.deinit(allocator);
    try std.testing.expect(parsed_json.has_count);
    try std.testing.expect(parsed_json.has_note);
    try std.testing.expect(parsed_json.has_raw);
    try std.testing.expectEqualStrings("raw", parsed_json.raw);

    const text = try decoded.formatTextAlloc(allocator);
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "count: 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "note: \"\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "raw: \"raw\"") != null);
    var text_roundtrip = try demo.PresenceMix.parseTextInitialized(allocator, text);
    defer text_roundtrip.deinit(allocator);
    try std.testing.expect(text_roundtrip.has_count);
    try std.testing.expect(text_roundtrip.has_note);
    try std.testing.expect(text_roundtrip.has_raw);

    var replacement = demo.PresenceMix.init();
    defer replacement.deinit(allocator);
    replacement.count = 0;
    replacement.has_count = true;
    replacement.note = "merged";
    replacement.has_note = true;
    try msg.mergeFrom(allocator, replacement);
    try std.testing.expect(msg.has_count);
    try std.testing.expectEqual(@as(i32, 0), msg.count);
    try std.testing.expectEqualStrings("merged", msg.note);

    const note_view = try demo.PresenceMix.noteStringView(bytes) orelse return error.MissingNoteView;
    try std.testing.expectEqualStrings("", note_view);
    const raw_view = try demo.PresenceMix.rawBytesView(bytes) orelse return error.MissingRawView;
    try std.testing.expectEqualStrings("raw", raw_view);
}

comptime {
    _ = pbz;
}
