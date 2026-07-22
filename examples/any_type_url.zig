const std = @import("std");
const pbz = @import("pbz");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Any type URLs compare by the final type-name segment, regardless of the
    // URL prefix and regardless of a leading '.' in the requested protobuf type
    // name. This mirrors C++ protobuf Any::Is/Unpack compatibility behavior.
    var custom = try pbz.Any.packBytesWithPrefix(
        allocator,
        "example.test/custom/prefix/",
        ".demo.CustomPayload",
        "payload",
    );
    defer custom.deinit(allocator);
    try std.testing.expectEqualStrings("example.test/custom/prefix/demo.CustomPayload", custom.type_url);
    try std.testing.expectEqualStrings("example.test/custom/prefix/demo.CustomPayload", custom.typeUrl());
    try std.testing.expectEqualStrings("example.test/custom/prefix", custom.typeUrlPrefix());
    try std.testing.expectEqualStrings("demo.CustomPayload", custom.typeName());
    try std.testing.expect(custom.hasValue());
    try std.testing.expectEqualStrings("payload", custom.valueBytes());
    try std.testing.expect(custom.isType("demo.CustomPayload"));
    try std.testing.expect(custom.isType(".demo.CustomPayload"));
    try std.testing.expect(!custom.isType("demo.OtherPayload"));
    try std.testing.expectEqualStrings("payload", try custom.unpackBytes("demo.CustomPayload"));
    try std.testing.expectEqualStrings("payload", try custom.unpackBytes(".demo.CustomPayload"));
    try std.testing.expectError(error.TypeMismatch, custom.unpackBytes("demo.OtherPayload"));

    var parsed = try pbz.Any.jsonParse(
        allocator,
        "{\"@type\":\"example.test/custom/prefix/demo.CustomPayload\",\"value\":\"cGF5bG9hZA==\"}",
    );
    defer parsed.deinit(allocator);
    try std.testing.expect(parsed.isType("demo.CustomPayload"));
    try std.testing.expectEqualStrings("payload", try parsed.unpackBytes(".demo.CustomPayload"));

    var default_prefix = try pbz.Any.packBytes(allocator, ".demo.CustomPayload", "abc");
    defer default_prefix.deinit(allocator);
    try std.testing.expectEqualStrings("type.googleapis.com/demo.CustomPayload", default_prefix.typeUrl());
    try std.testing.expectEqualStrings(pbz.Any.default_type_url_prefix, default_prefix.typeUrlPrefix());
}
