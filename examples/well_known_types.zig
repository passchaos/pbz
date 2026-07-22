const std = @import("std");
const pbz = @import("pbz");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const ts = try pbz.Timestamp.jsonParse("\"2020-01-02T03:04:05.123Z\"");
    const ts_json = try ts.jsonStringifyAlloc(allocator);
    defer allocator.free(ts_json);
    std.debug.assert(std.mem.eql(u8, ts_json, "\"2020-01-02T03:04:05.123Z\""));

    const duration = try pbz.Duration.jsonParse("\"-3.250s\"");
    const duration_wire = try duration.encode(allocator);
    defer allocator.free(duration_wire);
    _ = try pbz.Duration.decode(duration_wire);

    var mask = try pbz.FieldMask.jsonParseOwned(allocator, "\"fooBar,baz\"");
    defer mask.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), mask.pathCount());
    try std.testing.expectEqualStrings("foo_bar", try mask.pathAt(0));
    try std.testing.expectEqualStrings("baz", try mask.pathAt(1));
    try std.testing.expectEqual(@as(usize, 0), try mask.pathIndex("foo_bar"));
    try std.testing.expectError(error.UnknownField, mask.pathAt(2));
    try std.testing.expectError(error.UnknownField, mask.pathIndex("missing"));

    const empty_bytes = try pbz.Empty.encode(allocator);
    defer allocator.free(empty_bytes);
    std.debug.assert(empty_bytes.len == 0);
    _ = try pbz.Empty.decode(empty_bytes);
    try std.testing.expectError(error.UnknownField, pbz.Empty.jsonParse(allocator, "{\"unexpected\":true}"));

    var title = try pbz.StringValue.jsonParseOwned(allocator, "\"hello\"");
    defer title.deinit(allocator);

    var big_int = try pbz.Int64Value.jsonParse(allocator, "\"9007199254740993\"");
    std.debug.assert(big_int.value == 9_007_199_254_740_993);
    const big_int_json = try big_int.jsonStringifyAlloc(allocator);
    defer allocator.free(big_int_json);
    std.debug.assert(std.mem.eql(u8, big_int_json, "\"9007199254740993\""));

    var bytes_value = try pbz.BytesValue.jsonParseOwned(allocator, "\"aGk\"");
    defer bytes_value.deinit(allocator);
    std.debug.assert(std.mem.eql(u8, bytes_value.value, "hi"));
    const bytes_value_json = try bytes_value.jsonStringifyAlloc(allocator);
    defer allocator.free(bytes_value_json);
    std.debug.assert(std.mem.eql(u8, bytes_value_json, "\"aGk=\""));

    const nan_double = try pbz.DoubleValue.jsonParse(allocator, "\"NaN\"");
    std.debug.assert(std.math.isNan(nan_double.value));
    const nan_json = try nan_double.jsonStringifyAlloc(allocator);
    defer allocator.free(nan_json);
    std.debug.assert(std.mem.eql(u8, nan_json, "\"NaN\""));

    var any_title = try pbz.Any.packEncoded(allocator, "google.protobuf.StringValue", title);
    defer any_title.deinit(allocator);
    std.debug.assert(any_title.isType("google.protobuf.StringValue"));
    const any_title_json = try any_title.jsonStringifyAlloc(allocator);
    defer allocator.free(any_title_json);
    std.debug.assert(std.mem.eql(u8, any_title_json, "{\"@type\":\"type.googleapis.com/google.protobuf.StringValue\",\"value\":\"hello\"}"));

    var parsed_any_title = try pbz.Any.jsonParse(allocator, any_title_json);
    defer parsed_any_title.deinit(allocator);
    var unpacked = try parsed_any_title.unpackEncodedOwned(pbz.StringValue, allocator, "google.protobuf.StringValue");
    defer unpacked.deinit(allocator);
    std.debug.assert(std.mem.eql(u8, unpacked.value, "hello"));

    var object = try pbz.Struct.jsonParse(allocator,
        \\{"enabled":true,"items":[null,"zig"]}
    );
    defer object.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), object.fieldCount());
    try std.testing.expectEqualStrings("enabled", (try object.fieldAt(0)).key);
    try std.testing.expectEqual(@as(usize, 0), try object.fieldIndex("enabled"));
    switch (try object.fieldValue("enabled")) {
        .bool_value => |value| try std.testing.expect(value),
        else => return error.UnexpectedValueKind,
    }
    try std.testing.expectError(error.UnknownField, object.fieldAt(2));
    try std.testing.expectError(error.UnknownField, object.fieldIndex("missing"));
    const object_json = try object.jsonStringifyAlloc(allocator);
    defer allocator.free(object_json);
    std.debug.assert(std.mem.indexOf(u8, object_json, "enabled") != null);

    var scalar_value = try pbz.Value.jsonParse(allocator, "\"standalone\"");
    defer scalar_value.deinit(allocator);
    const scalar_value_wire = try scalar_value.encode(allocator);
    defer allocator.free(scalar_value_wire);
    var scalar_value_roundtrip = try pbz.Value.decode(allocator, scalar_value_wire);
    defer scalar_value_roundtrip.deinit(allocator);
    switch (scalar_value_roundtrip) {
        .string_value => |value| std.debug.assert(std.mem.eql(u8, value, "standalone")),
        else => return error.UnexpectedValueKind,
    }

    var list = try pbz.ListValue.jsonParse(allocator,
        \\[null,true,{"nested":["owned"]}]
    );
    defer list.deinit(allocator);
    const list_json = try list.jsonStringifyAlloc(allocator);
    defer allocator.free(list_json);
    std.debug.assert(std.mem.indexOf(u8, list_json, "\"owned\"") != null);
    const list_wire = try list.encode(allocator);
    defer allocator.free(list_wire);
    var list_roundtrip = try pbz.ListValue.decode(allocator, list_wire);
    defer list_roundtrip.deinit(allocator);
    std.debug.assert(list_roundtrip.values.len == 3);

    var object_any = try pbz.Any.packEncoded(allocator, "google.protobuf.Struct", object);
    defer object_any.deinit(allocator);
    const object_any_json = try object_any.jsonStringifyAlloc(allocator);
    defer allocator.free(object_any_json);
    std.debug.assert(std.mem.indexOf(u8, object_any_json, "\"value\":{") != null);

    var empty_any = try pbz.Any.jsonParse(allocator, "{\"@type\":\"type.googleapis.com/google.protobuf.Empty\",\"value\":{}}");
    defer empty_any.deinit(allocator);
    std.debug.assert(empty_any.isType("google.protobuf.Empty"));
    _ = try pbz.Empty.decode(empty_any.value);

    var descriptor_file = try pbz.ProtoParser.parse(allocator,
        \\syntax = "proto3";
        \\package google.protobuf;
        \\message Any {}
        \\message Timestamp {}
        \\message Empty {}
        \\message Custom {}
    );
    defer descriptor_file.deinit();
    var registry = pbz.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&descriptor_file);
    const refl = pbz.Reflection.init(allocator, &registry);
    try std.testing.expectEqual(pbz.WellKnownType.any, try refl.messageWellKnownType(try refl.message(".google.protobuf.Any")));
    try std.testing.expectEqual(pbz.WellKnownType.timestamp, try refl.messageWellKnownType(try refl.message(".google.protobuf.Timestamp")));
    try std.testing.expectEqual(pbz.WellKnownType.unspecified, try refl.messageWellKnownType(try refl.message(".google.protobuf.Custom")));
    // Match C++ Descriptor::WellKnownType exactly: Empty has special JSON
    // handling in Any, but it is not part of descriptor.h's WellKnownType enum.
    try std.testing.expectEqual(pbz.WellKnownType.unspecified, try refl.messageWellKnownType(try refl.message(".google.protobuf.Empty")));
    try std.testing.expect(try refl.messageIsWellKnownType(try refl.message(".google.protobuf.Any")));
    try std.testing.expect(!(try refl.messageIsWellKnownType(try refl.message(".google.protobuf.Empty"))));
}
