const std = @import("std");
const pbz = @import("pbz");
const alias_pb = @import("generated/enum_alias.pb.zig");

const alias = alias_pb.demo.alias;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Protobuf enum aliases are a C++-style compatibility feature: multiple
    // symbolic names can map to the same wire number.  Generated Zig exposes a
    // single canonical enum tag for the value while still accepting every alias
    // spelling on JSON/TextFormat input.
    std.debug.assert(alias.Status.STATUS_RUNNING == alias.Status.STATUS_STARTED);
    std.debug.assert(alias.Status.fromInt(1) == .STATUS_STARTED);
    std.debug.assert(alias.Status.fromName("STATUS_RUNNING") == .STATUS_STARTED);
    std.debug.assert(std.mem.eql(u8, alias.Status.STATUS_RUNNING.protoName(), "STATUS_STARTED"));

    var job = alias.Job.init();
    defer job.deinit(allocator);
    job.status = alias.Status.STATUS_RUNNING.toInt();
    job.history = try allocator.dupe(i32, &.{
        alias.Status.STATUS_UNKNOWN.toInt(),
        alias.Status.STATUS_RUNNING.toInt(),
        alias.Status.STATUS_DONE.toInt(),
    });

    const bytes = try job.encodeInitialized(allocator);
    defer allocator.free(bytes);
    var decoded = try alias.Job.decodeOwnedInitialized(allocator, bytes);
    defer decoded.deinit(allocator);
    try std.testing.expectEqual(alias.Status.STATUS_STARTED.toInt(), decoded.status);
    try std.testing.expectEqualSlices(i32, &.{ 0, 1, 2 }, decoded.history);

    const json = try decoded.jsonStringifyAlloc(allocator);
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"status\":\"STATUS_STARTED\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "STATUS_RUNNING") == null);

    var json_alias = try alias.Job.jsonParseInitialized(
        allocator,
        "{\"status\":\"STATUS_RUNNING\",\"history\":[\"STATUS_UNKNOWN\",\"STATUS_RUNNING\",\"STATUS_DONE\"]}",
    );
    defer json_alias.deinit(allocator);
    try std.testing.expectEqual(alias.Status.STATUS_STARTED.toInt(), json_alias.status);
    try std.testing.expectEqualSlices(i32, &.{ 0, 1, 2 }, json_alias.history);

    var json_numeric = try alias.Job.jsonParseInitialized(allocator, "{\"status\":1,\"history\":[0,1,2]}");
    defer json_numeric.deinit(allocator);
    try std.testing.expectEqual(alias.Status.STATUS_STARTED.toInt(), json_numeric.status);
    try std.testing.expectEqualSlices(i32, &.{ 0, 1, 2 }, json_numeric.history);

    const text = try json_alias.formatTextAlloc(allocator);
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "status: STATUS_STARTED") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "STATUS_RUNNING") == null);

    var text_alias = try alias.Job.parseTextInitialized(
        allocator,
        "status: STATUS_RUNNING\nhistory: STATUS_UNKNOWN\nhistory: STATUS_RUNNING\nhistory: STATUS_DONE\n",
    );
    defer text_alias.deinit(allocator);
    try std.testing.expectEqual(alias.Status.STATUS_STARTED.toInt(), text_alias.status);
    try std.testing.expectEqualSlices(i32, &.{ 0, 1, 2 }, text_alias.history);

    const enum_number_json = try text_alias.jsonStringifyAllocWithOptions(allocator, .{ .enum_as_name = false });
    defer allocator.free(enum_number_json);
    try std.testing.expect(std.mem.indexOf(u8, enum_number_json, "\"status\":1") != null);
}

comptime {
    _ = pbz;
}
