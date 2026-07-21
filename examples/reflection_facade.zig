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
        \\  uint32 quota = 9;
        \\  uint64 total = 10;
        \\  sint32 delta = 11;
        \\  sint64 big_delta = 12;
        \\  fixed32 checksum = 13;
        \\  fixed64 token = 14;
        \\  sfixed32 signed_fixed = 15;
        \\  sfixed64 signed_big_fixed = 16;
        \\  float ratio = 17;
        \\  double score = 18;
        \\  repeated bool flags = 19;
        \\  repeated bytes blobs = 20;
        \\  repeated Role roles = 21;
        \\  repeated uint32 samples = 22;
        \\  repeated sint64 deltas = 23;
        \\  string display_name = 24 [json_name = "shownName"];
        \\}
        \\service Users { rpc Get (User) returns (User); }
    );

    var loaded = try pbz.loadMemory(allocator, &tree, "app.proto");
    defer loaded.deinit();

    const refl = pbz.Reflection.init(allocator, &loaded.registry);
    const user_desc = try refl.message(".demo.reflect.User");
    const app_file = try refl.fileOfMessage(user_desc);
    const profile_desc = try refl.message(".demo.reflect.Profile");
    const role_desc = try refl.enumeration(".demo.reflect.Role");
    const role_file = try refl.fileOfEnum(role_desc);
    try std.testing.expectEqualStrings("common.proto", role_file.name);
    try std.testing.expectEqualStrings("ROLE_ADMIN", (try refl.enumValueByNumber(role_desc, 1)).name);
    try std.testing.expectEqual(@as(i32, 0), (try refl.enumValueByName(role_desc, "ROLE_UNKNOWN")).number);
    try std.testing.expectEqualStrings("display_name", (try refl.fieldByJsonName(user_desc, "shownName")).name);
    try std.testing.expectEqualStrings("big_delta", (try refl.fieldByJsonName(user_desc, "bigDelta")).name);
    const explicit_json_name = try refl.fieldJsonName(try refl.fieldByName(user_desc, "display_name"));
    defer allocator.free(explicit_json_name);
    try std.testing.expectEqualStrings("shownName", explicit_json_name);
    const default_json_name = try refl.fieldJsonName(try refl.fieldByName(user_desc, "big_delta"));
    defer allocator.free(default_json_name);
    try std.testing.expectEqualStrings("bigDelta", default_json_name);
    const id_field = try refl.fieldByName(user_desc, "id");
    const tags_field = try refl.fieldByName(user_desc, "tags");
    const samples_field = try refl.fieldByName(user_desc, "samples");
    const counts_desc_field = try refl.fieldByName(user_desc, "counts");
    try std.testing.expect(!(try refl.fieldHasPresence(user_desc, id_field)));
    try std.testing.expect(!(refl.fieldIsRequired(id_field)));
    try std.testing.expect(refl.fieldIsRepeatedLike(tags_field));
    try std.testing.expect(!(refl.fieldIsMap(tags_field)));
    try std.testing.expect(!refl.fieldIsPackable(tags_field));
    try std.testing.expect(refl.fieldIsPackable(samples_field));
    try std.testing.expect(try refl.fieldIsPacked(user_desc, samples_field));
    try std.testing.expect(refl.fieldIsMap(counts_desc_field));
    try std.testing.expect(refl.fieldIsRepeatedLike(counts_desc_field));
    try std.testing.expect(!refl.fieldIsPackable(counts_desc_field));
    try std.testing.expectError(error.UnknownField, refl.fieldByJsonName(user_desc, "display_name"));
    const users_service = try refl.service(".demo.reflect.Users");
    const service_file = try refl.fileOfService(users_service);
    try std.testing.expect(service_file == app_file);
    const get_method = users_service.findMethod("Get") orelse return error.MissingMethod;
    try std.testing.expectEqualStrings("Get", get_method.name);

    var user = try refl.newMessage("demo.reflect.User");
    defer user.deinit();

    try std.testing.expectEqual(@as(i32, 0), try refl.getInt32OrDefault(&user, "id"));
    try std.testing.expectEqualStrings("", try refl.getStringOrDefault(&user, "name"));
    try std.testing.expectEqual(@as(i32, 0), try refl.getEnumOrDefault(&user, "role"));
    try std.testing.expectEqualStrings("ROLE_UNKNOWN", (try refl.getEnumValueOrDefault(&user, "role")).name);
    try std.testing.expectEqualStrings("ROLE_UNKNOWN", (try refl.getEnumNameOrDefault(&user, "role")).?);

    try refl.setInt32(&user, "id", 7);
    try refl.setString(&user, "name", "Ada");
    try refl.addString(&user, "tags", "zig");
    try refl.addString(&user, "tags", "protobuf");
    try refl.putStringInt32MapEntry(&user, "counts", "red", 1);
    try refl.putStringInt32MapEntry(&user, "counts", "red", 2);
    try refl.setEnum(&user, "role", 1);
    try std.testing.expectError(error.TypeMismatch, refl.setBytes(&user, "email", "ada@example.test"));
    try refl.setString(&user, "email", "ada@example.test");
    try refl.setUInt32(&user, "quota", 42);
    try refl.setUInt64(&user, "total", 9_000_000_000);
    try refl.setSInt32(&user, "delta", -12);
    try refl.setSInt64(&user, "big_delta", -9_000_000_000);
    try refl.setFixed32(&user, "checksum", 0xdead_beef);
    try refl.setFixed64(&user, "token", 0x0102_0304_0506_0708);
    try refl.setSFixed32(&user, "signed_fixed", -123);
    try refl.setSFixed64(&user, "signed_big_fixed", -456);
    try refl.setFloat(&user, "ratio", 1.5);
    try refl.setDouble(&user, "score", 9.25);
    try refl.addBool(&user, "flags", false);
    try refl.addBool(&user, "flags", true);
    try refl.addBytes(&user, "blobs", &.{ 1, 2 });
    try refl.addBytes(&user, "blobs", &.{ 3, 4 });
    try refl.addEnum(&user, "roles", 0);
    try refl.addEnum(&user, "roles", 1);
    try refl.addUInt32(&user, "samples", 10);
    try refl.addUInt32(&user, "samples", 20);
    try refl.addSInt64(&user, "deltas", -1);
    try refl.addSInt64(&user, "deltas", -2);

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
    try std.testing.expectEqual(@as(i32, 1), try refl.getEnumOrDefault(&user, "role"));
    try std.testing.expect(role_desc == try refl.enumForField(user_desc, try refl.fieldByName(user_desc, "role")));
    try std.testing.expectEqualStrings("ROLE_ADMIN", (try refl.getEnumValue(&user, "role")).name);
    try std.testing.expectEqualStrings("ROLE_ADMIN", (try refl.getEnumValueOrDefault(&user, "role")).name);
    try std.testing.expectEqual(@as(u32, 42), try refl.getUInt32(&user, "quota"));
    try std.testing.expectEqual(@as(u64, 9_000_000_000), try refl.getUInt64(&user, "total"));
    try std.testing.expectEqual(@as(i32, -12), try refl.getSInt32(&user, "delta"));
    try std.testing.expectEqual(@as(i64, -9_000_000_000), try refl.getSInt64(&user, "big_delta"));
    try std.testing.expectEqual(@as(u32, 0xdead_beef), try refl.getFixed32(&user, "checksum"));
    try std.testing.expectEqual(@as(u64, 0x0102_0304_0506_0708), try refl.getFixed64(&user, "token"));
    try std.testing.expectEqual(@as(i32, -123), try refl.getSFixed32(&user, "signed_fixed"));
    try std.testing.expectEqual(@as(i64, -456), try refl.getSFixed64(&user, "signed_big_fixed"));
    try std.testing.expectEqual(@as(f32, 1.5), try refl.getFloat(&user, "ratio"));
    try std.testing.expectEqual(@as(f64, 9.25), try refl.getDouble(&user, "score"));
    try std.testing.expect(try refl.getBool(&user, "flags"));
    try std.testing.expectEqualSlices(u8, &.{ 3, 4 }, try refl.getBytes(&user, "blobs"));
    try std.testing.expectEqual(@as(i32, 1), try refl.getEnum(&user, "roles"));
    try std.testing.expectEqual(@as(u32, 20), (try refl.repeatedValue(&user, "samples", 1)).uint32);
    try std.testing.expectEqual(@as(i64, -2), (try refl.repeatedValue(&user, "deltas", 1)).sint64);
    try std.testing.expectEqualStrings("email", refl.whichOneof(&user, "contact").?.name);
    try std.testing.expectEqualStrings("ada@example.test", try refl.getString(&user, "email"));

    const count_field = (try refl.getField(&user, "counts")).?;
    try std.testing.expectEqual(@as(usize, 1), count_field.values.items.len);
    try std.testing.expectEqual(@as(i32, 2), count_field.values.items[0].map_entry.value.int32);
    try std.testing.expectEqual(@as(i32, 2), (try refl.stringMapValue(&user, "counts", "red")).?.int32);
    const red_lookup = try allocator.dupe(u8, "red");
    defer allocator.free(red_lookup);
    try std.testing.expectEqual(@as(i32, 2), (try refl.mapValue(&user, "counts", .{ .string = red_lookup })).?.int32);
    try std.testing.expect((try refl.stringMapEntry(&user, "counts", "missing")) == null);
    try std.testing.expectError(error.TypeMismatch, refl.mapValue(&user, "counts", .{ .int32 = 1 }));
    try std.testing.expect(try refl.clearStringMapEntry(&user, "counts", "red"));
    try std.testing.expect((try refl.getField(&user, "counts")) == null);
    try refl.putStringInt32MapEntry(&user, "counts", "red", 2);

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

    var raw_unknown = pbz.Writer.init(allocator);
    defer raw_unknown.deinit();
    try raw_unknown.writeUInt32(100, 1);
    try refl.appendUnknownRaw(&decoded, raw_unknown.slice());
    try std.testing.expectEqual(@as(usize, 1), refl.unknownCount(&decoded));
    try std.testing.expect(refl.hasUnknownFieldNumber(&decoded, 100));
    try std.testing.expectEqual(@as(usize, 1), refl.unknownFieldCountByNumber(&decoded, 100));
    const unknown_numbers = try refl.unknownFieldNumbers(&decoded);
    defer allocator.free(unknown_numbers);
    try std.testing.expectEqualSlices(pbz.FieldNumber, &.{100}, unknown_numbers);
    const unknown_runs = try refl.unknownFieldNumberRuns(&decoded);
    defer allocator.free(unknown_runs);
    try std.testing.expectEqual(@as(usize, 1), unknown_runs.len);
    try std.testing.expectEqual(@as(pbz.FieldNumber, 100), unknown_runs[0].number);
    try std.testing.expectEqual(@as(usize, 1), unknown_runs[0].count);
    try std.testing.expectEqualSlices(u8, raw_unknown.slice(), refl.unknownByNumber(&decoded, 100)[0].data);
    const owned_unknown = try refl.unknownByNumberAlloc(&decoded, 100);
    defer allocator.free(owned_unknown);
    try std.testing.expectEqual(@as(usize, 1), owned_unknown.len);
    refl.clearUnknownFieldsByNumber(&decoded, 100);
    try std.testing.expectEqual(@as(usize, 0), refl.unknownCount(&decoded));
    try refl.appendUnknownRaw(&decoded, raw_unknown.slice());
    refl.clearUnknownFields(&decoded);
    try std.testing.expectEqual(@as(usize, 0), refl.unknownFields(&decoded).len);

    const json = try pbz.stringifyJsonAllocWithRegistry(allocator, app_file, &loaded.registry, &user, .{});
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"profile\":") != null);
    var from_json = try pbz.parseJsonAllocWithRegistry(allocator, app_file, &loaded.registry, user_desc, json, .{});
    defer from_json.deinit();
    try std.testing.expectEqual(@as(i32, 7), try refl.getInt32(&from_json, "id"));
    try std.testing.expectEqual(@as(i64, 123456), try refl.getInt64(from_json.get("profile").?.values.items[0].message, "created_at"));

    try refl.setBool(&user, "disabled", true);
    try std.testing.expect(try refl.hasOneof(&user, "contact"));
    try std.testing.expectEqualStrings("disabled", refl.whichOneof(&user, "contact").?.name);
    try std.testing.expect(try refl.getBool(&user, "disabled"));
    try std.testing.expectEqualStrings("contact", (try refl.oneofByName(user_desc, "contact")).name);
    try std.testing.expect(try refl.clearOneof(&user, "contact"));
    try std.testing.expect(!(try refl.hasOneof(&user, "contact")));
    try std.testing.expect(refl.whichOneof(&user, "contact") == null);
    try std.testing.expectError(error.MissingField, refl.getBool(&user, "disabled"));
    try refl.setBool(&user, "disabled", true);

    try refl.clearField(&user, "name");
    try std.testing.expect(!(try refl.hasField(&user, "name")));
    try std.testing.expectError(error.MissingField, refl.getString(&user, "name"));

    var required_file = try pbz.ProtoParser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.required_reflect;
        \\message Child { required int32 id = 1; }
        \\message Parent { required string name = 1; optional Child child = 2; }
    );
    defer required_file.deinit();
    required_file.name = "required-reflect.proto";
    var required_registry = pbz.Registry.init(allocator);
    defer required_registry.deinit();
    try required_registry.addFile(&required_file);

    const required_refl = pbz.Reflection.init(allocator, &required_registry);
    var parent = try required_refl.newMessage(".demo.required_reflect.Parent");
    defer parent.deinit();
    try std.testing.expect(!required_refl.isInitialized(&parent));
    try std.testing.expectError(error.MissingRequiredField, required_refl.validateInitialized(&parent));
    const missing_name = (try required_refl.missingRequiredFieldPath(&parent)).?;
    defer allocator.free(missing_name);
    try std.testing.expectEqualStrings("name", missing_name);

    try required_refl.setString(&parent, "name", "root");
    const child_desc = try required_refl.message(".demo.required_reflect.Child");
    const child = try allocator.create(pbz.DynamicMessage);
    child.* = pbz.DynamicMessage.init(allocator, child_desc);
    try required_refl.set(&parent, try required_refl.fieldByName(parent.descriptor, "child"), .{ .message = child });
    const missing_child = (try required_refl.missingRequiredFieldPath(&parent)).?;
    defer allocator.free(missing_child);
    try std.testing.expectEqualStrings("child.id", missing_child);

    try required_refl.setInt32(parent.get("child").?.values.items[0].message, "id", 1);
    try required_refl.validateInitialized(&parent);
    try std.testing.expect(required_refl.isInitialized(&parent));
    try std.testing.expect((try required_refl.missingRequiredFieldPath(&parent)) == null);
}

comptime {
    _ = pbz;
}
