const std = @import("std");
const pbz = @import("pbz");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var file = try pbz.ProtoParser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.defaults;
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; USER = 2; }
        \\message Defaults {
        \\  optional int32 count = 1 [default = 42];
        \\  optional string name = 2 [default = "anon"];
        \\  optional bool enabled = 3 [default = true];
        \\  optional Kind kind = 4 [default = ADMIN];
        \\  optional bytes raw = 5 [default = "\001\002"];
        \\  optional double ratio = 6 [default = inf];
        \\  optional float quiet = 7 [default = nan];
        \\  repeated Kind roles = 8;
        \\}
    );
    defer file.deinit();
    const desc = file.findMessage("Defaults") orelse return error.MissingDescriptor;

    var msg = pbz.DynamicMessage.init(allocator, desc);
    defer msg.deinit();
    const count_field = desc.findField("count") orelse return error.MissingField;
    const name_field = desc.findField("name") orelse return error.MissingField;
    const enabled_field = desc.findField("enabled") orelse return error.MissingField;
    const kind_field = desc.findField("kind") orelse return error.MissingField;
    const raw_field = desc.findField("raw") orelse return error.MissingField;
    const ratio_field = desc.findField("ratio") orelse return error.MissingField;
    const quiet_field = desc.findField("quiet") orelse return error.MissingField;

    try std.testing.expect(!msg.has(count_field));
    try std.testing.expectEqual(@as(i32, 42), msg.getOrDefault(count_field).int32);
    try std.testing.expectEqualStrings("anon", msg.getOrDefault(name_field).string);
    try std.testing.expect(msg.getOrDefault(enabled_field).boolean);
    try std.testing.expectEqual(@as(i32, 1), msg.getOrDefault(kind_field).enumeration);
    try std.testing.expectEqualStrings("ADMIN", msg.getEnumNameOrDefaultWithFile(&file, kind_field).?);
    try std.testing.expectEqualStrings("\x01\x02", msg.getOrDefault(raw_field).bytes);
    try std.testing.expect(std.math.isPositiveInf(msg.getOrDefault(ratio_field).double));
    try std.testing.expect(std.math.isNan(msg.getOrDefault(quiet_field).float));

    try msg.add(count_field, .{ .int32 = 0 });
    try msg.add(name_field, .{ .string = try allocator.dupe(u8, "") });
    try msg.add(kind_field, .{ .enumeration = 2 });
    try msg.add(desc.findField("roles") orelse return error.MissingField, .{ .enumeration = 1 });
    try msg.add(desc.findField("roles") orelse return error.MissingField, .{ .enumeration = 2 });
    try std.testing.expect(msg.has(count_field));
    try std.testing.expectEqual(@as(i32, 0), msg.getOrDefault(count_field).int32);
    try std.testing.expectEqualStrings("USER", msg.getEnumNameOrDefaultWithFile(&file, kind_field).?);
    const role_names = try msg.getEnumNamesWithFile(allocator, &file, desc.findField("roles") orelse return error.MissingField);
    defer allocator.free(role_names);
    try std.testing.expectEqualStrings("ADMIN", role_names[0]);
    try std.testing.expectEqualStrings("USER", role_names[1]);

    const json = try pbz.stringifyJsonAlloc(allocator, &file, &msg, .{});
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"count\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"name\":\"\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"kind\":\"USER\"") != null);

    var parsed_null = try pbz.parseJsonAlloc(allocator, &file, desc, "{\"count\":null,\"kind\":null}", .{});
    defer parsed_null.deinit();
    try std.testing.expect(!parsed_null.has(count_field));
    try std.testing.expect(!parsed_null.has(kind_field));
    try std.testing.expectEqual(@as(i32, 42), parsed_null.getOrDefault(count_field).int32);
    try std.testing.expectEqualStrings("ADMIN", parsed_null.getEnumNameOrDefaultWithFile(&file, kind_field).?);

    var text_roundtrip = try pbz.parseTextAlloc(allocator, &file, desc,
        \\count: 7
        \\name: "text"
        \\kind: ADMIN
    );
    defer text_roundtrip.deinit();
    try std.testing.expectEqual(@as(i32, 7), text_roundtrip.getOrDefault(count_field).int32);
    try std.testing.expectEqualStrings("text", text_roundtrip.getOrDefault(name_field).string);
    try std.testing.expectEqualStrings("ADMIN", text_roundtrip.getEnumNameOrDefaultWithFile(&file, kind_field).?);

    try importedEnumDefaults(allocator);
}

fn importedEnumDefaults(allocator: std.mem.Allocator) !void {
    var tree = pbz.MemorySourceTree.init(allocator);
    defer tree.deinit();
    try tree.add("common.proto",
        \\syntax = "proto2";
        \\package common;
        \\enum Role { UNKNOWN = 0; ADMIN = 7; }
    );
    try tree.add("app.proto",
        \\syntax = "proto2";
        \\package app;
        \\import "common.proto";
        \\message Event { optional common.Role role = 1 [default = ADMIN]; }
    );

    var loaded = try pbz.loadMemory(allocator, &tree, "app.proto");
    defer loaded.deinit();
    const app_file = loaded.registry.findFile("app.proto") orelse return error.MissingFile;
    const event_desc = app_file.findMessage("Event") orelse return error.MissingDescriptor;
    const role_field = event_desc.findField("role") orelse return error.MissingField;

    var event = pbz.DynamicMessage.init(allocator, event_desc);
    defer event.deinit();
    try std.testing.expectEqual(pbz.dynamic.DefaultValue.none, event.getOrDefault(role_field));
    try std.testing.expectEqual(@as(i32, 7), event.getOrDefaultWithRegistry(app_file, &loaded.registry, role_field).enumeration);
    try std.testing.expectEqualStrings("ADMIN", event.getEnumNameOrDefaultWithRegistry(app_file, &loaded.registry, role_field).?);
}

comptime {
    _ = pbz;
}
