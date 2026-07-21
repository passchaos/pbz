const std = @import("std");
const pbz = @import("pbz");
const extensions_pb = @import("generated/extensions_generated.pb.zig");

const ext = extensions_pb.demo.extgen;

fn makePayload(id: i32, note: []const u8) ext.Payload {
    var payload = ext.Payload.init();
    payload.id = id;
    payload.has_id = true;
    payload.note = note;
    payload.has_note = true;
    return payload;
}

fn deinitPayloadSlice(allocator: std.mem.Allocator, values: []ext.Payload) void {
    for (values) |*value| value.deinit(allocator);
    allocator.free(values);
}

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Generated proto2 extension accessors intentionally store extension data
    // in the same raw unknown-field sidecar used by protobuf runtimes.  That
    // keeps exact wire preservation for unknown extensions while still giving
    // callers typed helpers similar to C++ generated extension APIs.
    std.debug.assert(ext.extensions.tag.extendee_has_type_ref);
    std.debug.assert(ext.extensions.tag.extendee_type_ref == ext.Host);
    std.debug.assert(ext.extensions.payload.value_has_type_ref);
    std.debug.assert(ext.extensions.payload.value_type_ref == ext.Payload);
    std.debug.assert(ext.extensions.role.value_has_enum_ref);
    std.debug.assert(ext.extensions.role.value_enum_ref == ext.Role);

    var host = ext.Host.init();
    defer host.deinit(allocator);
    try std.testing.expect(!try host.hasExtension_tag());
    try std.testing.expectEqualStrings("untagged", try host.getExtensionOrDefault_tag(allocator));
    try std.testing.expectEqual(ext.Role.ROLE_ADMIN, try host.getEnumOrDefaultExtension_role(allocator));

    try ext.extensions.tag.setOn(&host, allocator, "alpha");
    try std.testing.expect(try host.hasExtension_tag());
    try std.testing.expectEqual(@as(usize, 1), try host.countExtension_tag());
    try std.testing.expectEqualStrings("alpha", (try host.getExtension_tag(allocator)).?);

    try host.appendExtension_nums(allocator, &.{ 1, 2, 3 });
    try host.addExtension_nums(allocator, 4);
    {
        const nums = try host.getExtension_nums(allocator);
        defer allocator.free(nums);
        try std.testing.expectEqualSlices(i32, &.{ 1, 2, 3, 4 }, nums);
    }
    try host.replaceExtension_nums(allocator, &.{ 8, 13 });
    {
        const nums = try ext.extensions.nums.getOn(host, allocator);
        defer allocator.free(nums);
        try std.testing.expectEqualSlices(i32, &.{ 8, 13 }, nums);
    }

    var payload = makePayload(7, "primary");
    defer payload.deinit(allocator);
    try host.setExtensionMessage_payload(allocator, payload);
    {
        var decoded_payload = (try host.getExtensionMessage_payload(allocator)).?;
        defer decoded_payload.deinit(allocator);
        try std.testing.expectEqual(@as(i32, 7), decoded_payload.id);
        try std.testing.expectEqualStrings("primary", decoded_payload.note);
    }

    const history = [_]ext.Payload{ makePayload(8, "history-a"), makePayload(9, "history-b") };
    try host.appendExtensionMessages_payloads(allocator, &history);
    {
        const decoded_history = try host.getExtensionMessages_payloads(allocator);
        defer deinitPayloadSlice(allocator, decoded_history);
        try std.testing.expectEqual(@as(usize, 2), decoded_history.len);
        try std.testing.expectEqual(@as(i32, 8), decoded_history[0].id);
        try std.testing.expectEqualStrings("history-b", decoded_history[1].note);
    }

    try host.setEnumExtension_role(allocator, .ROLE_USER);
    try std.testing.expectEqual(ext.Role.ROLE_USER, (try host.getEnumExtension_role(allocator)).?);
    try std.testing.expectEqual(@as(i32, ext.Role.ROLE_USER.toInt()), (try host.getExtension_role(allocator)).?);

    const bytes = try host.encodeInitialized(allocator);
    defer allocator.free(bytes);
    var decoded = try ext.Host.decodeOwnedInitialized(allocator, bytes);
    defer decoded.deinit(allocator);
    try std.testing.expectEqualStrings("alpha", (try decoded.getExtension_tag(allocator)).?);
    try std.testing.expectEqual(ext.Role.ROLE_USER, (try decoded.getEnumExtension_role(allocator)).?);
    {
        const nums = try decoded.getExtension_nums(allocator);
        defer allocator.free(nums);
        try std.testing.expectEqualSlices(i32, &.{ 8, 13 }, nums);
    }

    const json = try decoded.jsonStringifyAlloc(allocator);
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"[demo.extgen.tag]\":\"alpha\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"[demo.extgen.nums]\":[8,13]") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"[demo.extgen.role]\":\"ROLE_USER\"") != null);
    var json_roundtrip = try ext.Host.jsonParseInitialized(allocator, json);
    defer json_roundtrip.deinit(allocator);
    try std.testing.expectEqualStrings("alpha", (try json_roundtrip.getExtension_tag(allocator)).?);
    try std.testing.expectEqual(ext.Role.ROLE_USER, (try json_roundtrip.getEnumExtension_role(allocator)).?);

    const text = try decoded.formatTextAlloc(allocator);
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "[demo.extgen.tag]: \"alpha\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "[demo.extgen.payload] {") != null);
    var text_roundtrip = try ext.Host.parseTextInitialized(allocator, text);
    defer text_roundtrip.deinit(allocator);
    try std.testing.expectEqualStrings("alpha", (try text_roundtrip.getExtension_tag(allocator)).?);
    {
        var decoded_payload = (try text_roundtrip.getExtensionMessage_payload(allocator)).?;
        defer decoded_payload.deinit(allocator);
        try std.testing.expectEqual(@as(i32, 7), decoded_payload.id);
    }

    var invalid_payload = ext.Payload.init();
    defer invalid_payload.deinit(allocator);
    invalid_payload.note = "missing required id";
    invalid_payload.has_note = true;
    var invalid_host = ext.Host.init();
    defer invalid_host.deinit(allocator);
    try invalid_host.setExtensionMessage_payload(allocator, invalid_payload);
    try std.testing.expectError(error.MissingRequiredField, invalid_host.validateRequiredRecursive(allocator));
    const missing_path = (try invalid_host.missingRequiredFieldPath(allocator)) orelse return error.ExpectedMissingRequiredPath;
    defer allocator.free(missing_path);
    try std.testing.expectEqualStrings("payload.id", missing_path);
}

comptime {
    _ = pbz;
}
