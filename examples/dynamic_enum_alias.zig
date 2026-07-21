const std = @import("std");
const pbz = @import("pbz");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var file = try pbz.ProtoParser.parse(allocator,
        \\syntax = "proto3";
        \\package demo.dynalias;
        \\enum Status {
        \\  option allow_alias = true;
        \\  STATUS_UNKNOWN = 0;
        \\  STATUS_STARTED = 1;
        \\  STATUS_RUNNING = 1;
        \\  STATUS_DONE = 2;
        \\}
        \\message Job {
        \\  Status status = 1;
        \\  repeated Status history = 2;
        \\  map<string, Status> by_name = 3;
        \\}
    );
    defer file.deinit();

    const desc = file.findMessage("Job") orelse return error.MissingDescriptor;
    const status_field = desc.findField("status") orelse return error.MissingField;
    const history_field = desc.findField("history") orelse return error.MissingField;
    const map_field = desc.findField("by_name") orelse return error.MissingField;

    var from_json = try pbz.parseJsonAlloc(allocator, &file, desc,
        \\{"status":"STATUS_RUNNING","history":["STATUS_UNKNOWN","STATUS_RUNNING","STATUS_DONE"],"byName":{"current":"STATUS_RUNNING"}}
    , .{});
    defer from_json.deinit();
    try std.testing.expectEqual(@as(i32, 1), from_json.get("status").?.values.items[0].enumeration);
    try std.testing.expectEqualStrings("STATUS_STARTED", from_json.getEnumNameOrDefaultWithFile(&file, status_field).?);
    const names = try from_json.getEnumNamesWithFile(allocator, &file, history_field);
    defer allocator.free(names);
    try std.testing.expectEqualStrings("STATUS_STARTED", names[1]);

    const current_key = try allocator.dupe(u8, "current");
    defer allocator.free(current_key);
    try std.testing.expectEqualStrings("STATUS_STARTED", (try from_json.getEnumMapValueNameWithFile(&file, map_field, .{ .string = current_key })).?);

    const rendered = try pbz.stringifyJsonAlloc(allocator, &file, &from_json, .{});
    defer allocator.free(rendered);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "STATUS_STARTED") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "STATUS_RUNNING") == null);

    var from_text = try pbz.parseTextAlloc(allocator, &file, desc,
        \\status: STATUS_RUNNING
        \\history: STATUS_UNKNOWN
        \\history: STATUS_RUNNING
        \\history: STATUS_DONE
        \\by_name { key: "current" value: STATUS_RUNNING }
    );
    defer from_text.deinit();
    try std.testing.expectEqual(@as(i32, 1), from_text.get("status").?.values.items[0].enumeration);
    const text = try pbz.formatTextAlloc(allocator, &file, &from_text, .{});
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "STATUS_STARTED") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "STATUS_RUNNING") == null);

    var numeric = try pbz.parseJsonAlloc(allocator, &file, desc, "{\"status\":1,\"history\":[0,1,2]}", .{});
    defer numeric.deinit();
    try std.testing.expectEqual(@as(i32, 1), numeric.get("status").?.values.items[0].enumeration);

    try std.testing.expectError(error.InvalidEnumValue, pbz.parseJsonAlloc(allocator, &file, desc, "{\"status\":\"MISSING\"}", .{}));
}

comptime {
    _ = pbz;
}
