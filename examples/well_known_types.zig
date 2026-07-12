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
    std.debug.assert(mask.paths.len == 2);

    var title = try pbz.StringValue.jsonParseOwned(allocator, "\"hello\"");
    defer title.deinit(allocator);

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
    const object_json = try object.jsonStringifyAlloc(allocator);
    defer allocator.free(object_json);
    std.debug.assert(std.mem.indexOf(u8, object_json, "enabled") != null);

    var object_any = try pbz.Any.packEncoded(allocator, "google.protobuf.Struct", object);
    defer object_any.deinit(allocator);
    const object_any_json = try object_any.jsonStringifyAlloc(allocator);
    defer allocator.free(object_any_json);
    std.debug.assert(std.mem.indexOf(u8, object_any_json, "\"value\":{") != null);
}
