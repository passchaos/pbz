const std = @import("std");
const pbz = @import("pbz");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var file = try pbz.ProtoParser.parse(allocator,
        \\syntax = "proto3";
        \\package demo.jsonopts;
        \\enum Kind { KIND_UNKNOWN = 0; KIND_ADMIN = 1; }
        \\message Settings {
        \\  int32 user_id = 1;
        \\  string display_name = 2;
        \\  Kind kind = 3;
        \\  bool enabled = 4;
        \\}
    );
    defer file.deinit();
    const desc = file.findMessage("Settings") orelse return error.MissingDescriptor;

    try std.testing.expectError(error.UnknownField, pbz.parseJsonAlloc(allocator, &file, desc,
        \\{"userId":7,"extra":true}
    , .{}));

    var parsed = try pbz.parseJsonAlloc(allocator, &file, desc,
        \\{"userId":7,"displayName":"Ada","kind":"KIND_ADMIN","extra":true}
    , .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    try std.testing.expectEqual(@as(i32, 7), parsed.get("user_id").?.values.items[0].int32);
    try std.testing.expectEqualStrings("Ada", parsed.get("display_name").?.values.items[0].string);
    try std.testing.expectEqual(@as(i32, 1), parsed.get("kind").?.values.items[0].enumeration);

    var duplicate_keys = try pbz.parseJsonAlloc(allocator, &file, desc,
        \\{"userId":1,"userId":2,"displayName":"first","displayName":"last"}
    , .{});
    defer duplicate_keys.deinit();
    try std.testing.expectEqual(@as(i32, 2), duplicate_keys.get("user_id").?.values.items[0].int32);
    try std.testing.expectEqualStrings("last", duplicate_keys.get("display_name").?.values.items[0].string);

    const camel_json = try pbz.stringifyJsonAlloc(allocator, &file, &parsed, .{});
    defer allocator.free(camel_json);
    try std.testing.expect(std.mem.indexOf(u8, camel_json, "\"userId\":7") != null);
    try std.testing.expect(std.mem.indexOf(u8, camel_json, "\"displayName\":\"Ada\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, camel_json, "\"enabled\"") == null);

    const proto_name_json = try pbz.stringifyJsonAlloc(allocator, &file, &parsed, .{ .preserve_proto_field_names = true });
    defer allocator.free(proto_name_json);
    try std.testing.expect(std.mem.indexOf(u8, proto_name_json, "\"user_id\":7") != null);
    try std.testing.expect(std.mem.indexOf(u8, proto_name_json, "\"display_name\":\"Ada\"") != null);

    const always_print_json = try pbz.stringifyJsonAlloc(allocator, &file, &parsed, .{ .always_print_primitive_fields = true });
    defer allocator.free(always_print_json);
    try std.testing.expect(std.mem.indexOf(u8, always_print_json, "\"enabled\":false") != null);

    const enum_number_json = try pbz.stringifyJsonAlloc(allocator, &file, &parsed, .{ .enum_as_name = false });
    defer allocator.free(enum_number_json);
    try std.testing.expect(std.mem.indexOf(u8, enum_number_json, "\"kind\":1") != null);

    var proto_name_input = try pbz.parseJsonAlloc(allocator, &file, desc,
        \\{"user_id":8,"display_name":"Proto","kind":1}
    , .{});
    defer proto_name_input.deinit();
    try std.testing.expectEqual(@as(i32, 8), proto_name_input.get("user_id").?.values.items[0].int32);
    try std.testing.expectEqualStrings("Proto", proto_name_input.get("display_name").?.values.items[0].string);
}

comptime {
    _ = pbz;
}
