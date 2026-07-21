const std = @import("std");
const pbz = @import("pbz");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var tree = pbz.MemorySourceTree.init(allocator);
    defer tree.deinit();
    try tree.add("common.proto",
        \\syntax = "proto3";
        \\package demo.reflect;
        \\enum Role { ROLE_UNKNOWN = 0; ROLE_ADMIN = 1; }
        \\message Profile { int64 created_at = 1; bytes avatar = 2; }
    );
    try tree.add("app.proto",
        \\syntax = "proto3";
        \\package demo.reflect;
        \\import "common.proto";
        \\message User {
        \\  int32 id = 1;
        \\  string name = 2;
        \\  repeated string tags = 3;
        \\  map<string, int32> counts = 4;
        \\  Role role = 5;
        \\  Profile profile = 6;
        \\  oneof contact { string email = 7; bool disabled = 8; }
        \\}
    );

    var loaded = try pbz.loadMemory(allocator, &tree, "app.proto");
    defer loaded.deinit();

    const refl = pbz.Reflection.init(allocator, &loaded.registry);
    const user_desc = try refl.message(".demo.reflect.User");
    const app_file = try refl.fileOfMessage(user_desc);
    const profile_desc = try refl.message(".demo.reflect.Profile");

    var user = try refl.newMessage("demo.reflect.User");
    defer user.deinit();

    try refl.setInt32(&user, "id", 7);
    try refl.setString(&user, "name", "Ada");
    try refl.addString(&user, "tags", "zig");
    try refl.addString(&user, "tags", "protobuf");
    try refl.putStringInt32MapEntry(&user, "counts", "red", 1);
    try refl.putStringInt32MapEntry(&user, "counts", "red", 2);
    try refl.setEnum(&user, "role", 1);
    try refl.setBytes(&user, "email", "ada@example.test");
    try std.testing.expectError(error.TypeMismatch, refl.getString(&user, "email"));
    try refl.clearField(&user, "email");
    try refl.setString(&user, "email", "ada@example.test");

    const profile = try allocator.create(pbz.DynamicMessage);
    profile.* = pbz.DynamicMessage.init(allocator, profile_desc);
    try refl.setInt64(profile, "created_at", 123456);
    try refl.setBytes(profile, "avatar", &.{ 0xde, 0xad, 0xbe, 0xef });
    try refl.set(&user, try refl.fieldByName(user_desc, "profile"), .{ .message = profile });

    try std.testing.expect(try refl.hasField(&user, "id"));
    try std.testing.expectEqual(@as(i32, 7), try refl.getInt32(&user, "id"));
    try std.testing.expectEqualStrings("Ada", try refl.getString(&user, "name"));
    try std.testing.expectEqual(@as(usize, 2), try refl.repeatedLen(&user, "tags"));
    try std.testing.expectEqualStrings("protobuf", (try refl.repeatedValue(&user, "tags", 1)).string);
    try std.testing.expectEqual(@as(i32, 1), try refl.getEnum(&user, "role"));
    try std.testing.expectEqualStrings("email", refl.whichOneof(&user, "contact").?.name);
    try std.testing.expectEqualStrings("ada@example.test", try refl.getString(&user, "email"));

    const count_field = (try refl.getField(&user, "counts")).?;
    try std.testing.expectEqual(@as(usize, 1), count_field.values.items.len);
    try std.testing.expectEqual(@as(i32, 2), count_field.values.items[0].map_entry.value.int32);

    const profile_value = (try refl.getField(&user, "profile")).?.values.items[0].message;
    try std.testing.expectEqual(@as(i64, 123456), try refl.getInt64(profile_value, "created_at"));
    try std.testing.expectEqualSlices(u8, &.{ 0xde, 0xad, 0xbe, 0xef }, try refl.getBytes(profile_value, "avatar"));

    const encoded = try user.encodedInitializedWithRegistry(app_file, &loaded.registry);
    defer allocator.free(encoded);
    var decoded = pbz.DynamicMessage.init(allocator, user_desc);
    defer decoded.deinit();
    try decoded.decodeInitializedWithRegistry(app_file, &loaded.registry, encoded);
    try std.testing.expectEqual(@as(i32, 7), try refl.getInt32(&decoded, "id"));
    try std.testing.expectEqualStrings("email", refl.whichOneof(&decoded, "contact").?.name);
    try std.testing.expectEqualStrings("ada@example.test", try refl.getString(&decoded, "email"));

    const json = try pbz.stringifyJsonAllocWithRegistry(allocator, app_file, &loaded.registry, &user, .{});
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"profile\":") != null);
    var from_json = try pbz.parseJsonAllocWithRegistry(allocator, app_file, &loaded.registry, user_desc, json, .{});
    defer from_json.deinit();
    try std.testing.expectEqual(@as(i32, 7), try refl.getInt32(&from_json, "id"));
    try std.testing.expectEqual(@as(i64, 123456), try refl.getInt64(from_json.get("profile").?.values.items[0].message, "created_at"));

    try refl.setBool(&user, "disabled", true);
    try std.testing.expectEqualStrings("disabled", refl.whichOneof(&user, "contact").?.name);
    try std.testing.expect(try refl.getBool(&user, "disabled"));

    try refl.clearField(&user, "name");
    try std.testing.expect(!(try refl.hasField(&user, "name")));
    try std.testing.expectError(error.MissingField, refl.getString(&user, "name"));
}

comptime {
    _ = pbz;
}
