const std = @import("std");
const pbz = @import("pbz");
const messageset_pb = @import("generated/messageset.pb.zig");

const ms = messageset_pb.demo.messageset;

fn note(id: i32, text: []const u8) ms.Note {
    var out = ms.Note.init();
    out.id = id;
    out.has_id = true;
    out.text = text;
    out.has_text = true;
    return out;
}

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // MessageSet is a legacy proto2 wire format still supported by C++
    // protobuf.  Generated extension helpers should hide the start-group
    // wrapper while preserving the MessageSet wire shape in unknown storage.
    std.debug.assert(ms.extensions.note.extendee_type_ref == ms.Host);
    std.debug.assert(ms.extensions.note.value_type_ref == ms.Note);

    var host = ms.Host.init();
    defer host.deinit(allocator);
    var primary = note(7, "primary");
    defer primary.deinit(allocator);
    try host.setExtensionMessage_note(allocator, primary);
    try std.testing.expect(try host.hasExtension_note());
    try std.testing.expectEqual(@as(usize, 1), try host.countExtension_note());

    const bytes = try host.encodeInitialized(allocator);
    defer allocator.free(bytes);
    try std.testing.expect(bytes.len != 0);

    var decoded = try ms.Host.decodeOwnedInitialized(allocator, bytes);
    defer decoded.deinit(allocator);
    var decoded_note = (try decoded.getExtensionMessage_note(allocator)).?;
    defer decoded_note.deinit(allocator);
    try std.testing.expectEqual(@as(i32, 7), decoded_note.id);
    try std.testing.expectEqualStrings("primary", decoded_note.text);

    try std.testing.expectEqual(@as(usize, 1), decoded.unknownFields().len);
    var raw_reader = pbz.Reader.init(decoded.unknownFields()[0]);
    const tag = (try raw_reader.nextTag()) orelse return error.MissingMessageSetTag;
    try std.testing.expectEqual(@as(pbz.FieldNumber, 1), tag.number);
    try std.testing.expectEqual(pbz.wire.WireType.start_group, tag.wire_type);

    const json = try decoded.jsonStringifyAlloc(allocator);
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"[demo.messageset.note]\":") != null);
    var json_roundtrip = try ms.Host.jsonParseInitialized(allocator, json);
    defer json_roundtrip.deinit(allocator);
    var json_note = (try json_roundtrip.getExtensionMessage_note(allocator)).?;
    defer json_note.deinit(allocator);
    try std.testing.expectEqual(@as(i32, 7), json_note.id);

    const text = try decoded.formatTextAlloc(allocator);
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "[demo.messageset.note] {") != null);
    var text_roundtrip = try ms.Host.parseTextInitialized(allocator, text);
    defer text_roundtrip.deinit(allocator);
    var text_note = (try text_roundtrip.getExtensionMessage_note(allocator)).?;
    defer text_note.deinit(allocator);
    try std.testing.expectEqualStrings("primary", text_note.text);

    var invalid_note = ms.Note.init();
    defer invalid_note.deinit(allocator);
    invalid_note.text = "missing required id";
    invalid_note.has_text = true;
    var invalid_host = ms.Host.init();
    defer invalid_host.deinit(allocator);
    try invalid_host.setExtensionMessage_note(allocator, invalid_note);
    try std.testing.expectError(error.MissingRequiredField, invalid_host.validateRequiredRecursive(allocator));
    const missing_path = (try invalid_host.missingRequiredFieldPath(allocator)) orelse return error.ExpectedMissingRequiredPath;
    defer allocator.free(missing_path);
    try std.testing.expectEqualStrings("note.id", missing_path);
}

comptime {
    _ = pbz;
}
