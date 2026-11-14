const dynamic = @import("dynamic.zig");
const registry_mod = @import("registry.zig");
const schema = @import("schema.zig");
const std = @import("std");
const module = @import("json.zig");
const Value = module.Value;
const decodeBase64 = module.decodeBase64;
const parseAlloc = module.parseAlloc;
const parseAllocWithRegistry = module.parseAllocWithRegistry;
const parseInitializedAlloc = module.parseInitializedAlloc;
const parseInitializedAllocWithRegistry = module.parseInitializedAllocWithRegistry;
const stringify = module.stringify;
const stringifyAlloc = module.stringifyAlloc;
const stringifyAllocWithRegistry = module.stringifyAllocWithRegistry;
const jsonStringNeedsEscape = module.test_helpers.jsonStringNeedsEscape;

test "json base64 accepts both alphabets and optional padding" {
    const allocator = std.testing.allocator;
    const cases = [_]struct { input: []const u8, expected: []const u8 }{
        .{ .input = "", .expected = "" },
        .{ .input = "Zg==", .expected = "f" },
        .{ .input = "Zm8=", .expected = "fo" },
        .{ .input = "Zm9v", .expected = "foo" },
        .{ .input = "Zg", .expected = "f" },
        .{ .input = "Zm8", .expected = "fo" },
        .{ .input = "Zm9vYmFy", .expected = "foobar" },
        .{ .input = "++//", .expected = &.{ 0xfb, 0xef, 0xff } },
        .{ .input = "--__", .expected = &.{ 0xfb, 0xef, 0xff } },
    };
    for (cases) |case| {
        const decoded = try decodeBase64(allocator, case.input);
        defer allocator.free(decoded);
        try std.testing.expectEqualSlices(u8, case.expected, decoded);
    }
    try std.testing.expectError(error.InvalidCharacter, decodeBase64(allocator, "Zm9v!"));
    try std.testing.expectError(error.InvalidPadding, decodeBase64(allocator, "Z"));
    try std.testing.expectError(error.InvalidPadding, decodeBase64(allocator, "Zg="));
    try std.testing.expectError(error.InvalidPadding, decodeBase64(allocator, "Zg==="));
    try std.testing.expectError(error.InvalidPadding, decodeBase64(allocator, "Zg==Zg=="));
}

test "json stringify dynamic message with scalars repeated maps enums and nested messages" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\package demo;
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message Child { string label = 1; }
        \\message Bag {
        \\  int32 id = 1;
        \\  int64 big = 2;
        \\  bytes raw = 3;
        \\  repeated string tags = 4;
        \\  map<string, int32> counts = 5;
        \\  Child child = 6;
        \\  Kind kind = 7;
        \\}
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const bag_desc = file.findMessage("Bag").?;
    const child_desc = file.findMessage("Child").?;

    var bag = dynamic.DynamicMessage.init(allocator, bag_desc);
    defer bag.deinit();
    try bag.add(bag_desc.findField("id").?, .{ .int32 = 7 });
    try bag.add(bag_desc.findField("big").?, .{ .int64 = 9007199254740993 });
    try bag.add(bag_desc.findField("raw").?, .{ .bytes = try allocator.dupe(u8, "hi") });
    try bag.add(bag_desc.findField("tags").?, .{ .string = try allocator.dupe(u8, "a") });
    try bag.add(bag_desc.findField("tags").?, .{ .string = try allocator.dupe(u8, "b") });

    const count_entry = try allocator.create(dynamic.MapEntry);
    count_entry.* = .{ .key = .{ .string = try allocator.dupe(u8, "red") }, .value = .{ .int32 = 3 } };
    try bag.add(bag_desc.findField("counts").?, .{ .map_entry = count_entry });

    const child = try allocator.create(dynamic.DynamicMessage);
    child.* = dynamic.DynamicMessage.init(allocator, child_desc);
    try child.add(child_desc.findField("label").?, .{ .string = try allocator.dupe(u8, "kid") });
    try bag.add(bag_desc.findField("child").?, .{ .message = child });
    try bag.add(bag_desc.findField("kind").?, .{ .enumeration = 1 });

    const json = try stringifyAlloc(allocator, &file, &bag, .{});
    defer allocator.free(json);
    try std.testing.expectEqualSlices(u8, "{\"id\":7,\"big\":\"9007199254740993\",\"raw\":\"aGk=\",\"tags\":[\"a\",\"b\"],\"counts\":{\"red\":3},\"child\":{\"label\":\"kid\"},\"kind\":\"ADMIN\"}", json);
}

test "json stringify rejects invalid utf8 strings" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message M {
        \\  optional string name = 1;
        \\  repeated string tags = 2;
        \\  map<string, int32> keyed = 3;
        \\}
    );
    defer file.deinit();
    const desc = file.findMessage("M").?;

    var bad_name = dynamic.DynamicMessage.init(allocator, desc);
    defer bad_name.deinit();
    try bad_name.add(desc.findField("name").?, .{ .string = try allocator.dupe(u8, &.{0xc0}) });
    try std.testing.expectError(error.InvalidUtf8, stringifyAlloc(allocator, &file, &bad_name, .{}));

    var bad_repeated = dynamic.DynamicMessage.init(allocator, desc);
    defer bad_repeated.deinit();
    try bad_repeated.add(desc.findField("tags").?, .{ .string = try allocator.dupe(u8, "ok") });
    try bad_repeated.add(desc.findField("tags").?, .{ .string = try allocator.dupe(u8, &.{0xc0}) });
    try std.testing.expectError(error.InvalidUtf8, stringifyAlloc(allocator, &file, &bad_repeated, .{}));

    var bad_key = dynamic.DynamicMessage.init(allocator, desc);
    defer bad_key.deinit();
    const entry = try allocator.create(dynamic.MapEntry);
    entry.* = .{ .key = .{ .string = try allocator.dupe(u8, &.{0xc0}) }, .value = .{ .int32 = 1 } };
    try bad_key.add(desc.findField("keyed").?, .{ .map_entry = entry });
    try std.testing.expectError(error.InvalidUtf8, stringifyAlloc(allocator, &file, &bad_key, .{}));
}

fn exerciseJsonMapParseCleanup(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, descriptor: *const schema.MessageDescriptor) !void {
    var parsed = try parseAlloc(allocator, file, descriptor, "{\"keyed\":{\"a\":\"owned\"}}", .{});
    defer parsed.deinit();

    const entry = parsed.get("keyed").?.values.items[0].map_entry;
    try std.testing.expectEqualStrings("a", entry.key.string);
    try std.testing.expectEqualStrings("owned", entry.value.string);
}

test "json map parse cleans up allocation failures" {
    var file = try @import("parser.zig").Parser.parse(std.testing.allocator,
        \\syntax = "proto3";
        \\message M { map<string, string> keyed = 1; }
    );
    defer file.deinit();
    try std.testing.checkAllAllocationFailures(std.testing.allocator, exerciseJsonMapParseCleanup, .{ &file, file.findMessage("M").? });
}

test "json parse dynamic message with scalars repeated maps enums and nested messages" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\package demo;
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message Child { string label = 1; }
        \\message Bag {
        \\  int32 id = 1;
        \\  int64 big = 2;
        \\  bytes raw = 3;
        \\  repeated string tags = 4;
        \\  map<string, int32> counts = 5;
        \\  Child child = 6;
        \\  Kind kind = 7;
        \\}
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const bag_desc = file.findMessage("Bag").?;

    var bag = try parseAlloc(allocator, &file, bag_desc,
        \\{"id":7,"big":"9007199254740993","raw":"aGk=","tags":["a","b"],"counts":{"red":3},"child":{"label":"kid"},"kind":"ADMIN"}
    , .{});
    defer bag.deinit();

    try std.testing.expectEqual(@as(i32, 7), bag.get("id").?.values.items[0].int32);
    try std.testing.expectEqual(@as(i64, 9007199254740993), bag.get("big").?.values.items[0].int64);
    try std.testing.expectEqualSlices(u8, "hi", bag.get("raw").?.values.items[0].bytes);
    try std.testing.expectEqual(@as(usize, 2), bag.get("tags").?.values.items.len);
    try std.testing.expectEqualSlices(u8, "a", bag.get("tags").?.values.items[0].string);
    try std.testing.expectEqualSlices(u8, "b", bag.get("tags").?.values.items[1].string);

    const count = bag.get("counts").?.values.items[0].map_entry;
    try std.testing.expectEqualSlices(u8, "red", count.key.string);
    try std.testing.expectEqual(@as(i32, 3), count.value.int32);

    try std.testing.expectEqualSlices(u8, "kid", bag.get("child").?.values.items[0].message.get("label").?.values.items[0].string);
    try std.testing.expectEqual(@as(i32, 1), bag.get("kind").?.values.items[0].enumeration);

    const rendered = try stringifyAlloc(allocator, &file, &bag, .{});
    defer allocator.free(rendered);
    try std.testing.expectEqualSlices(u8, "{\"id\":7,\"big\":\"9007199254740993\",\"raw\":\"aGk=\",\"tags\":[\"a\",\"b\"],\"counts\":{\"red\":3},\"child\":{\"label\":\"kid\"},\"kind\":\"ADMIN\"}", rendered);
}

test "json parse rejects duplicate object keys" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\message M { int32 id = 1; map<string, int32> counts = 2; }
    );
    defer file.deinit();
    const desc = file.findMessage("M").?;

    try std.testing.expectError(error.DuplicateField, parseAlloc(allocator, &file, desc,
        \\{"id":1,"id":2,"counts":{"red":1,"red":3}}
    , .{}));
}

test "json parseInitialized validates required fields recursively" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Child { required int32 id = 1; }
        \\message Parent { required Child child = 1; }
    );
    defer file.deinit();
    const parent_desc = file.findMessage("Parent").?;

    try std.testing.expectError(error.MissingRequiredField, parseInitializedAlloc(allocator, &file, parent_desc, "{}", .{}));
    try std.testing.expectError(error.MissingRequiredField, parseInitializedAlloc(allocator, &file, parent_desc, "{\"child\":{}}", .{}));

    var parsed = try parseInitializedAlloc(allocator, &file, parent_desc, "{\"child\":{\"id\":7}}", .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(i32, 7), parsed.get("child").?.values.items[0].message.get("id").?.values.items[0].int32);

    var common = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package common;
        \\message Child { required int32 id = 1; }
    );
    defer common.deinit();
    var app = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package app;
        \\message Parent { required common.Child child = 1; }
    );
    defer app.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);
    const imported_parent = app.findMessage("Parent").?;

    try std.testing.expectError(error.MissingRequiredField, parseInitializedAllocWithRegistry(allocator, &app, &registry, imported_parent, "{\"child\":{}}", .{}));
    var imported = try parseInitializedAllocWithRegistry(allocator, &app, &registry, imported_parent, "{\"child\":{\"id\":9}}", .{});
    defer imported.deinit();
    try std.testing.expectEqual(@as(i32, 9), imported.get("child").?.values.items[0].message.get("id").?.values.items[0].int32);

    var ext_file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host { extensions 100 to max; }
        \\message Ext { required int32 id = 1; }
        \\extend Host {
        \\  optional Ext ext = 100;
        \\  repeated Ext exts = 101;
        \\}
    );
    defer ext_file.deinit();
    var ext_registry = registry_mod.Registry.init(allocator);
    defer ext_registry.deinit();
    try ext_registry.addFile(&ext_file);
    const host_desc = ext_file.findMessage("Host").?;
    try std.testing.expectError(error.MissingRequiredField, parseInitializedAllocWithRegistry(allocator, &ext_file, &ext_registry, host_desc, "{\"[demo.ext]\":{}}", .{}));
    var ext_parsed = try parseInitializedAllocWithRegistry(allocator, &ext_file, &ext_registry, host_desc, "{\"[demo.ext]\":{\"id\":11}}", .{});
    defer ext_parsed.deinit();
    try std.testing.expectEqual(@as(i32, 11), ext_parsed.get("ext").?.values.items[0].message.get("id").?.values.items[0].int32);
    try std.testing.expectError(error.MissingRequiredField, parseInitializedAllocWithRegistry(allocator, &ext_file, &ext_registry, host_desc, "{\"[demo.exts]\":[{\"id\":1},{}]}", .{}));
    var repeated_ext_parsed = try parseInitializedAllocWithRegistry(allocator, &ext_file, &ext_registry, host_desc, "{\"[demo.exts]\":[{\"id\":1},{\"id\":2}]}", .{});
    defer repeated_ext_parsed.deinit();
    try std.testing.expectEqual(@as(usize, 2), repeated_ext_parsed.get("exts").?.values.items.len);

    var messageset_file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.ms;
        \\message Host { option message_set_wire_format = true; extensions 4 to max; }
        \\message Ext { required int32 id = 1; }
        \\extend Host { optional Ext ext = 100; }
    );
    defer messageset_file.deinit();
    var messageset_registry = registry_mod.Registry.init(allocator);
    defer messageset_registry.deinit();
    try messageset_registry.addFile(&messageset_file);
    const messageset_host = messageset_file.findMessage("Host").?;
    try std.testing.expectError(error.MissingRequiredField, parseInitializedAllocWithRegistry(allocator, &messageset_file, &messageset_registry, messageset_host, "{\"[demo.ms.ext]\":{}}", .{}));
    var messageset_parsed = try parseInitializedAllocWithRegistry(allocator, &messageset_file, &messageset_registry, messageset_host, "{\"[demo.ms.ext]\":{\"id\":12}}", .{});
    defer messageset_parsed.deinit();
    try std.testing.expectEqual(@as(i32, 12), messageset_parsed.get("ext").?.values.items[0].message.get("id").?.values.items[0].int32);
}

test "json registry resolves same-package imported unqualified fields" {
    const allocator = std.testing.allocator;
    var common = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message User { optional string name = 1; }
        \\enum Kind { UNKNOWN = 0; ADMIN = 7; }
    );
    defer common.deinit();
    common.name = "common.proto";
    var app = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\import "common.proto";
        \\message Event { optional User user = 1; optional Kind kind = 2 [default = ADMIN]; }
    );
    defer app.deinit();
    app.name = "app.proto";
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);
    try registry.validateFileReferences(&app);

    var parsed = try parseAllocWithRegistry(allocator, &app, &registry, app.findMessage("Event").?,
        \\{"user":{"name":"Ada"},"kind":"ADMIN"}
    , .{});
    defer parsed.deinit();

    try std.testing.expectEqualStrings("Ada", parsed.get("user").?.values.items[0].message.get("name").?.values.items[0].string);
    try std.testing.expectEqual(@as(i32, 7), parsed.get("kind").?.values.items[0].enumeration);

    const rendered = try stringifyAllocWithRegistry(allocator, &app, &registry, &parsed, .{});
    defer allocator.free(rendered);
    try std.testing.expectEqualStrings("{\"user\":{\"name\":\"Ada\"},\"kind\":\"ADMIN\"}", rendered);
}

test "json parse with registry resolves imported message and enum fields" {
    const allocator = std.testing.allocator;
    var common = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package common;
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message User { string name = 1; }
    );
    defer common.deinit();
    var app = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package app;
        \\message Event { common.User user = 1; common.Kind kind = 2; repeated common.Kind roles = 3; }
    );
    defer app.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);

    var event = try parseAllocWithRegistry(allocator, &app, &registry, app.findMessage("Event").?,
        \\{"user":{"name":"Ada"},"kind":"ADMIN","roles":["ADMIN",0]}
    , .{});
    defer event.deinit();

    try std.testing.expectEqualSlices(u8, "Ada", event.get("user").?.values.items[0].message.get("name").?.values.items[0].string);
    try std.testing.expectEqual(@as(i32, 1), event.get("kind").?.values.items[0].enumeration);
    try std.testing.expectEqual(@as(i32, 1), event.get("roles").?.values.items[0].enumeration);
    try std.testing.expectEqual(@as(i32, 0), event.get("roles").?.values.items[1].enumeration);

    const rendered = try stringifyAllocWithRegistry(allocator, &app, &registry, &event, .{});
    defer allocator.free(rendered);
    try std.testing.expectEqualSlices(u8, "{\"user\":{\"name\":\"Ada\"},\"kind\":\"ADMIN\",\"roles\":[\"ADMIN\",\"UNKNOWN\"]}", rendered);
}

test "json imported enums use owning file features" {
    const allocator = std.testing.allocator;
    var open_file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package openpkg;
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
    );
    defer open_file.deinit();
    open_file.name = "open.proto";
    var closed_file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package closedpkg;
        \\enum Kind { ADMIN = 1; }
    );
    defer closed_file.deinit();
    closed_file.name = "closed.proto";
    var proto2_app = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package app2;
        \\import "open.proto";
        \\message Event { optional openpkg.Kind kind = 1; }
    );
    defer proto2_app.deinit();
    proto2_app.name = "app2.proto";
    var proto3_app = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package app3;
        \\import "closed.proto";
        \\message Event { closedpkg.Kind kind = 1; }
    );
    defer proto3_app.deinit();
    proto3_app.name = "app3.proto";

    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&open_file);
    try registry.addFile(&closed_file);
    try registry.addFile(&proto2_app);
    try registry.addFile(&proto3_app);

    var open_in_proto2 = try parseAllocWithRegistry(allocator, &proto2_app, &registry, proto2_app.findMessage("Event").?, "{\"kind\":123}", .{});
    defer open_in_proto2.deinit();
    try std.testing.expectEqual(@as(i32, 123), open_in_proto2.get("kind").?.values.items[0].enumeration);

    try std.testing.expectError(error.InvalidEnumValue, parseAllocWithRegistry(allocator, &proto3_app, &registry, proto3_app.findMessage("Event").?, "{\"kind\":123}", .{}));
}

test "json imported messages use owning file features" {
    const allocator = std.testing.allocator;
    var common = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package common;
        \\message Payload { optional int32 id = 1; optional bytes raw = 2; }
    );
    defer common.deinit();
    common.name = "common.proto";
    var app = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package app;
        \\import "common.proto";
        \\message Event {
        \\  common.Payload payload = 1;
        \\  map<string, common.Payload> keyed = 2;
        \\}
    );
    defer app.deinit();
    app.name = "app.proto";
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);

    const desc = app.findMessage("Event").?;
    var parsed = try parseAllocWithRegistry(allocator, &app, &registry, desc,
        \\{"payload":{"id":0,"raw":"wA=="},"keyed":{"one":{"id":0,"raw":"wA=="}}}
    , .{});
    defer parsed.deinit();

    try std.testing.expect(parsed.get("payload").?.values.items[0].message.has(common.findMessage("Payload").?.findField("id").?));
    try std.testing.expectEqual(@as(i32, 0), parsed.get("payload").?.values.items[0].message.get("id").?.values.items[0].int32);
    try std.testing.expectEqualSlices(u8, &.{0xc0}, parsed.get("payload").?.values.items[0].message.get("raw").?.values.items[0].bytes);
    const entry = parsed.get("keyed").?.values.items[0].map_entry;
    try std.testing.expectEqualStrings("one", entry.key.string);
    try std.testing.expect(entry.value.message.has(common.findMessage("Payload").?.findField("id").?));
    try std.testing.expectEqual(@as(i32, 0), entry.value.message.get("id").?.values.items[0].int32);
    try std.testing.expectEqualSlices(u8, &.{0xc0}, entry.value.message.get("raw").?.values.items[0].bytes);

    const rendered = try stringifyAllocWithRegistry(allocator, &app, &registry, &parsed, .{});
    defer allocator.free(rendered);
    try std.testing.expectEqualSlices(u8, "{\"payload\":{\"id\":0,\"raw\":\"wA==\"},\"keyed\":{\"one\":{\"id\":0,\"raw\":\"wA==\"}}}", rendered);
}

test "json Any payloads use owning file features" {
    const allocator = std.testing.allocator;
    var common = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package common;
        \\message Payload { optional int32 id = 1; optional bytes raw = 2; }
    );
    defer common.deinit();
    common.name = "common.proto";
    var app = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package app;
        \\import "common.proto";
        \\message Any { optional string type_url = 1; optional bytes value = 2; }
        \\message Holder { .google.protobuf.Any any = 1; }
    );
    defer app.deinit();
    app.name = "app.proto";
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);

    const holder_desc = app.findMessage("Holder").?;
    const any_desc = app.findMessage("Any").?;
    const payload_desc = common.findMessage("Payload").?;

    var payload = dynamic.DynamicMessage.init(allocator, payload_desc);
    defer payload.deinit();
    try payload.add(payload_desc.findField("id").?, .{ .int32 = 0 });
    try payload.add(payload_desc.findField("raw").?, .{ .bytes = try allocator.dupe(u8, &.{0xc0}) });
    const payload_bytes = try payload.encodedDeterministicWithRegistry(&common, &registry);
    defer allocator.free(payload_bytes);

    var holder = dynamic.DynamicMessage.init(allocator, holder_desc);
    defer holder.deinit();
    const any_msg = try allocator.create(dynamic.DynamicMessage);
    any_msg.* = dynamic.DynamicMessage.init(allocator, any_desc);
    try any_msg.add(any_desc.findField("type_url").?, .{ .string = try allocator.dupe(u8, "type.googleapis.com/common.Payload") });
    try any_msg.add(any_desc.findField("value").?, .{ .bytes = try allocator.dupe(u8, payload_bytes) });
    try holder.add(holder_desc.findField("any").?, .{ .message = any_msg });

    const rendered = try stringifyAllocWithRegistry(allocator, &app, &registry, &holder, .{});
    defer allocator.free(rendered);
    try std.testing.expectEqualSlices(u8, "{\"any\":{\"@type\":\"type.googleapis.com/common.Payload\",\"id\":0,\"raw\":\"wA==\"}}", rendered);

    var parsed = try parseAllocWithRegistry(allocator, &app, &registry, holder_desc, "{\"any\":{\"@type\":\"type.googleapis.com/common.Payload\",\"id\":0,\"raw\":\"wA==\"}}", .{});
    defer parsed.deinit();
    const parsed_value = parsed.get("any").?.values.items[0].message.get("value").?.values.items[0].bytes;
    var decoded_payload = dynamic.DynamicMessage.init(allocator, payload_desc);
    defer decoded_payload.deinit();
    try decoded_payload.decodeWithRegistry(&common, &registry, parsed_value);
    try std.testing.expect(decoded_payload.has(payload_desc.findField("id").?));
    try std.testing.expectEqual(@as(i32, 0), decoded_payload.get("id").?.values.items[0].int32);
    try std.testing.expectEqualSlices(u8, &.{0xc0}, decoded_payload.get("raw").?.values.items[0].bytes);
}

test "json parses and prints enum numbers and unknown enum values" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message M { Kind kind = 1; repeated Kind roles = 2; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("M").?;

    var numeric = try parseAlloc(allocator, &file, desc, "{\"kind\":123,\"roles\":[\"1\",\"123\"]}", .{});
    defer numeric.deinit();
    try std.testing.expectEqual(@as(i32, 123), numeric.get("kind").?.values.items[0].enumeration);
    try std.testing.expectEqual(@as(i32, 1), numeric.get("roles").?.values.items[0].enumeration);
    try std.testing.expectEqual(@as(i32, 123), numeric.get("roles").?.values.items[1].enumeration);

    const rendered_unknown = try stringifyAlloc(allocator, &file, &numeric, .{});
    defer allocator.free(rendered_unknown);
    try std.testing.expectEqualSlices(u8, "{\"kind\":123,\"roles\":[\"ADMIN\",123]}", rendered_unknown);

    const rendered_numbers = try stringifyAlloc(allocator, &file, &numeric, .{ .enum_as_name = false });
    defer allocator.free(rendered_numbers);
    try std.testing.expectEqualSlices(u8, "{\"kind\":123,\"roles\":[1,123]}", rendered_numbers);
}

test "json honors closed enum feature for numeric values" {
    const allocator = std.testing.allocator;
    {
        var file = try @import("parser.zig").Parser.parse(allocator,
            \\edition = "2023";
            \\option features.enum_type = CLOSED;
            \\enum Kind { option features.enum_type = OPEN; UNKNOWN = 0; ADMIN = 1; }
            \\message M { Kind kind = 1; repeated Kind roles = 2; }
        );
        defer file.deinit();
        const desc = file.findMessage("M").?;
        var msg = try parseAlloc(allocator, &file, desc, "{\"kind\":123,\"roles\":[\"123\"]}", .{});
        defer msg.deinit();
        try std.testing.expectEqual(@as(i32, 123), msg.get("kind").?.values.items[0].enumeration);
        try std.testing.expectEqual(@as(i32, 123), msg.get("roles").?.values.items[0].enumeration);
    }
    {
        var file = try @import("parser.zig").Parser.parse(allocator,
            \\edition = "2023";
            \\option features.enum_type = OPEN;
            \\enum Kind { option features.enum_type = CLOSED; UNKNOWN = 0; ADMIN = 1; }
            \\message M {
            \\  Kind kind = 1;
            \\  repeated Kind roles = 2;
            \\  map<string, Kind> keyed = 3;
            \\}
        );
        defer file.deinit();
        const desc = file.findMessage("M").?;
        try std.testing.expectError(error.InvalidEnumValue, parseAlloc(allocator, &file, desc, "{\"kind\":123}", .{}));
        try std.testing.expectError(error.InvalidEnumValue, parseAlloc(allocator, &file, desc, "{\"roles\":[\"123\"]}", .{}));
        try std.testing.expectError(error.InvalidEnumValue, parseAlloc(allocator, &file, desc, "{\"keyed\":{\"bad\":123}}", .{}));

        var ignored = try parseAlloc(allocator, &file, desc, "{\"kind\":123,\"roles\":[1,123],\"keyed\":{\"ok\":1,\"bad\":123}}", .{ .ignore_unknown_fields = true });
        defer ignored.deinit();
        try std.testing.expect(ignored.get("kind") == null);
        try std.testing.expectEqual(@as(usize, 1), ignored.get("roles").?.values.items.len);
        try std.testing.expectEqual(@as(i32, 1), ignored.get("roles").?.values.items[0].enumeration);
        try std.testing.expectEqual(@as(usize, 1), ignored.get("keyed").?.values.items.len);
        try std.testing.expectEqualStrings("ok", ignored.get("keyed").?.values.items[0].map_entry.key.string);
    }
}

test "json ignore unknown fields skips unknown enum names" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message M {
        \\  Kind kind = 1;
        \\  repeated Kind roles = 2;
        \\  map<string, Kind> keyed = 3;
        \\}
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("M").?;

    try std.testing.expectError(error.InvalidEnumValue, parseAlloc(allocator, &file, desc, "{\"kind\":\"BOGUS\"}", .{}));

    var parsed = try parseAlloc(allocator, &file, desc,
        \\{"kind":"BOGUS","roles":["ADMIN","BOGUS",1],"keyed":{"ok":"ADMIN","bad":"BOGUS"}}
    , .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    try std.testing.expect(parsed.get("kind") == null);
    try std.testing.expectEqual(@as(usize, 2), parsed.get("roles").?.values.items.len);
    try std.testing.expectEqual(@as(i32, 1), parsed.get("roles").?.values.items[0].enumeration);
    try std.testing.expectEqual(@as(i32, 1), parsed.get("roles").?.values.items[1].enumeration);
    try std.testing.expectEqual(@as(usize, 1), parsed.get("keyed").?.values.items.len);
    try std.testing.expectEqualSlices(u8, "ok", parsed.get("keyed").?.values.items[0].map_entry.key.string);
}

test "json ignore unknown fields skips imported enum names" {
    const allocator = std.testing.allocator;
    var common = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package common;
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
    );
    defer common.deinit();
    var app = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package app;
        \\message Event {
        \\  common.Kind kind = 1;
        \\  repeated common.Kind roles = 2;
        \\  map<string, common.Kind> keyed = 3;
        \\}
    );
    defer app.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);
    const desc = app.findMessage("Event").?;

    var parsed = try parseAllocWithRegistry(allocator, &app, &registry, desc,
        \\{"kind":"BOGUS","roles":["ADMIN","BOGUS"],"keyed":{"ok":"ADMIN","bad":"BOGUS"}}
    , .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    try std.testing.expect(parsed.get("kind") == null);
    try std.testing.expectEqual(@as(usize, 1), parsed.get("roles").?.values.items.len);
    try std.testing.expectEqual(@as(i32, 1), parsed.get("roles").?.values.items[0].enumeration);
    try std.testing.expectEqual(@as(usize, 1), parsed.get("keyed").?.values.items.len);
    try std.testing.expectEqualStrings("ok", parsed.get("keyed").?.values.items[0].map_entry.key.string);
}

test "json parses and stringifies repeated and enum proto2 extensions" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host { extensions 100 to 200; }
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\extend Host {
        \\  repeated int32 scores = 100;
        \\  optional Kind role = 101;
        \\}
    );
    defer file.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);
    const desc = file.findMessage("Host").?;

    var parsed = try parseAllocWithRegistry(allocator, &file, &registry, desc, "{\"[demo.scores]\":[1,2],\"[demo.role]\":\"ADMIN\"}", .{});
    defer parsed.deinit();
    const scores = registry.findExtension("demo.Host", 100).?;
    const role = registry.findExtension("demo.Host", 101).?;
    try std.testing.expectEqual(@as(i32, 1), parsed.getByNumber(scores.number).?.values.items[0].int32);
    try std.testing.expectEqual(@as(i32, 2), parsed.getByNumber(scores.number).?.values.items[1].int32);
    try std.testing.expectEqual(@as(i32, 1), parsed.getByNumber(role.number).?.values.items[0].enumeration);

    const rendered = try stringifyAllocWithRegistry(allocator, &file, &registry, &parsed, .{});
    defer allocator.free(rendered);
    try std.testing.expectEqualSlices(u8, "{\"[demo.scores]\":[1,2],\"[demo.role]\":\"ADMIN\"}", rendered);
}

test "json parses and stringifies proto2 extension fields" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host { extensions 100 to 200; }
        \\extend Host { optional int32 tag = 100; }
    );
    defer file.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);
    const desc = file.findMessage("Host").?;

    var parsed = try parseAllocWithRegistry(allocator, &file, &registry, desc, "{\"[demo.tag]\":7}", .{});
    defer parsed.deinit();
    const ext = registry.findExtension("demo.Host", 100).?;
    try std.testing.expectEqual(@as(i32, 7), parsed.getByNumber(ext.number).?.values.items[0].int32);

    const rendered = try stringifyAllocWithRegistry(allocator, &file, &registry, &parsed, .{});
    defer allocator.free(rendered);
    try std.testing.expectEqualSlices(u8, "{\"[demo.tag]\":7}", rendered);

    var leaf = try parseAllocWithRegistry(allocator, &file, &registry, desc, "{\"[tag]\":8}", .{});
    defer leaf.deinit();
    try std.testing.expectEqual(@as(i32, 8), leaf.getByNumber(ext.number).?.values.items[0].int32);
}

test "json parses and stringifies proto2 group extensions" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host {
        \\  optional int32 id = 1;
        \\  extensions 100 to max;
        \\}
        \\extend Host {
        \\  optional group Box = 100 {
        \\    optional int32 a = 101;
        \\    optional string label = 102;
        \\  }
        \\  repeated group Item = 103 {
        \\    optional int32 a = 104;
        \\  }
        \\}
    );
    defer file.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);
    const desc = file.findMessage("Host").?;
    const box = registry.findExtension("demo.Host", 100).?;
    const item = registry.findExtension("demo.Host", 103).?;

    var parsed = try parseAllocWithRegistry(allocator, &file, &registry, desc,
        \\{"id":1,"[demo.box]":{"a":7,"label":"seven"},"[demo.item]":[{"a":1},{"a":2}]}
    , .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(i32, 1), parsed.get("id").?.values.items[0].int32);
    const parsed_box = parsed.getByNumber(box.number).?.values.items[0].group;
    try std.testing.expectEqual(@as(i32, 7), parsed_box.get("a").?.values.items[0].int32);
    try std.testing.expectEqualSlices(u8, "seven", parsed_box.get("label").?.values.items[0].string);
    const parsed_items = parsed.getByNumber(item.number).?.values.items;
    try std.testing.expectEqual(@as(usize, 2), parsed_items.len);
    try std.testing.expectEqual(@as(i32, 1), parsed_items[0].group.get("a").?.values.items[0].int32);
    try std.testing.expectEqual(@as(i32, 2), parsed_items[1].group.get("a").?.values.items[0].int32);

    const rendered = try stringifyAllocWithRegistry(allocator, &file, &registry, &parsed, .{});
    defer allocator.free(rendered);
    try std.testing.expectEqualSlices(u8,
        \\{"id":1,"[demo.box]":{"a":7,"label":"seven"},"[demo.item]":[{"a":1},{"a":2}]}
    , rendered);

    var leaf = try parseAllocWithRegistry(allocator, &file, &registry, desc, "{\"[box]\":{\"a\":9}}", .{});
    defer leaf.deinit();
    try std.testing.expectEqual(@as(i32, 9), leaf.getByNumber(box.number).?.values.items[0].group.get("a").?.values.items[0].int32);
}

test "json registry extension lookup distinguishes same leaf message names" {
    const allocator = std.testing.allocator;
    var a_file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package a;
        \\message Host { extensions 100 to max; }
        \\extend Host { optional string note = 100; }
    );
    defer a_file.deinit();
    a_file.name = "a.proto";
    var b_file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package b;
        \\message Host { optional int32 id = 1; }
    );
    defer b_file.deinit();
    b_file.name = "b.proto";
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&a_file);
    try registry.addFile(&b_file);

    try std.testing.expectError(error.UnknownField, parseAllocWithRegistry(allocator, &b_file, &registry, b_file.findMessage("Host").?, "{\"[a.note]\":\"wrong-host\"}", .{}));

    var a_msg = try parseAllocWithRegistry(allocator, &a_file, &registry, a_file.findMessage("Host").?, "{\"[a.note]\":\"right-host\"}", .{});
    defer a_msg.deinit();
    try std.testing.expectEqualStrings("right-host", a_msg.get("note").?.values.items[0].string);
}

test "json parses and stringifies scoped proto2 extensions" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host { extensions 100 to 200; }
        \\message Scope { extend Host { optional string tag = 100; } }
    );
    defer file.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);
    const desc = file.findMessage("Host").?;
    const ext = registry.findExtensionByName("demo.Host", "demo.Scope.tag").?;

    var parsed = try parseAllocWithRegistry(allocator, &file, &registry, desc, "{\"[demo.Scope.tag]\":\"scoped\"}", .{});
    defer parsed.deinit();
    try std.testing.expectEqualSlices(u8, "scoped", parsed.getByNumber(ext.number).?.values.items[0].string);

    const rendered = try stringifyAllocWithRegistry(allocator, &file, &registry, &parsed, .{});
    defer allocator.free(rendered);
    try std.testing.expectEqualSlices(u8, "{\"[demo.Scope.tag]\":\"scoped\"}", rendered);
}

test "json parse ignores null fields" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\message Nulls { int32 id = 1; repeated string tags = 2; map<string, int32> counts = 3; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("Nulls").?;

    var msg = try parseAlloc(allocator, &file, desc, "{\"id\":null,\"tags\":null,\"counts\":null}", .{});
    defer msg.deinit();
    try std.testing.expect(msg.get("id") == null);
    try std.testing.expect(msg.get("tags") == null);
    try std.testing.expect(msg.get("counts") == null);
}

test "json uses default lowerCamelCase field names" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\message Names { int32 user_id = 1; string display_name = 2; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("Names").?;

    var msg = dynamic.DynamicMessage.init(allocator, desc);
    defer msg.deinit();
    try msg.add(desc.findField("user_id").?, .{ .int32 = 7 });
    try msg.add(desc.findField("display_name").?, .{ .string = try allocator.dupe(u8, "Zig") });
    const rendered = try stringifyAlloc(allocator, &file, &msg, .{});
    defer allocator.free(rendered);
    try std.testing.expectEqualSlices(u8, "{\"userId\":7,\"displayName\":\"Zig\"}", rendered);

    const preserved = try stringifyAlloc(allocator, &file, &msg, .{ .preserve_proto_field_names = true });
    defer allocator.free(preserved);
    try std.testing.expectEqualSlices(u8, "{\"user_id\":7,\"display_name\":\"Zig\"}", preserved);

    var parsed = try parseAlloc(allocator, &file, desc, "{\"userId\":8,\"displayName\":\"Trae\"}", .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(i32, 8), parsed.get("user_id").?.values.items[0].int32);
    try std.testing.expectEqualSlices(u8, "Trae", parsed.get("display_name").?.values.items[0].string);
}

test "json parser rejects alternate spelling and oneof duplicate fields" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\message Child { int32 id = 1; string name = 2; }
        \\message Names {
        \\  int32 user_id = 1;
        \\  repeated string tag_list = 2;
        \\  map<string, int32> count_map = 3;
        \\  Child child_msg = 4;
        \\  oneof choice { int32 choice_id = 5; string choice_text = 7; }
        \\  string explicit_name = 6 [json_name = "shownName"];
        \\}
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("Names").?;

    try std.testing.expectError(error.DuplicateField, parseAlloc(allocator, &file, desc, "{\"user_id\":1,\"userId\":2}", .{}));
    try std.testing.expectError(error.DuplicateField, parseAlloc(allocator, &file, desc, "{\"tag_list\":[\"a\"],\"tagList\":[\"b\"]}", .{}));
    try std.testing.expectError(error.DuplicateField, parseAlloc(allocator, &file, desc, "{\"count_map\":{\"a\":1},\"countMap\":{\"b\":2}}", .{}));
    try std.testing.expectError(error.DuplicateField, parseAlloc(allocator, &file, desc, "{\"child_msg\":{\"id\":1},\"childMsg\":{\"name\":\"two\"}}", .{}));
    try std.testing.expectError(error.DuplicateField, parseAlloc(allocator, &file, desc, "{\"choice_id\":7,\"choiceId\":8}", .{}));
    try std.testing.expectError(error.DuplicateField, parseAlloc(allocator, &file, desc, "{\"choiceId\":7,\"choiceText\":\"text\"}", .{}));
    try std.testing.expectError(error.DuplicateField, parseAlloc(allocator, &file, desc, "{\"choice_id\":7,\"shownName\":\"json\",\"explicit_name\":\"proto\"}", .{}));
}

test "json round-trips proto3 optional message fields" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\message Child { int32 id = 1; }
        \\message Parent { optional Child child = 1; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const parent_desc = file.findMessage("Parent").?;
    const child_desc = file.findMessage("Child").?;
    const child_field = parent_desc.findField("child").?;

    var absent = dynamic.DynamicMessage.init(allocator, parent_desc);
    defer absent.deinit();
    const absent_json = try stringifyAlloc(allocator, &file, &absent, .{});
    defer allocator.free(absent_json);
    try std.testing.expectEqualSlices(u8, "{}", absent_json);

    var present = dynamic.DynamicMessage.init(allocator, parent_desc);
    defer present.deinit();
    const child = try allocator.create(dynamic.DynamicMessage);
    child.* = dynamic.DynamicMessage.init(allocator, child_desc);
    try child.add(child_desc.findField("id").?, .{ .int32 = 7 });
    try present.add(child_field, .{ .message = child });
    const present_json = try stringifyAlloc(allocator, &file, &present, .{});
    defer allocator.free(present_json);
    try std.testing.expectEqualSlices(u8, "{\"child\":{\"id\":7}}", present_json);

    var parsed = try parseAlloc(allocator, &file, parent_desc, "{\"child\":{}}", .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.has(child_field));
}

test "json stringify can always print absent primitive repeated and map fields" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto2";
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message Defaults {
        \\  optional int32 count = 1 [default = 42];
        \\  optional string name = 2 [default = "anon"];
        \\  optional bool enabled = 3 [default = true];
        \\  optional Kind kind = 4 [default = ADMIN];
        \\  repeated string tags = 5;
        \\  map<string, int32> counts = 6;
        \\  optional bytes raw = 7 [default = "hi"];
        \\  optional int64 big = 8 [default = 9007199254740993];
        \\  optional double pos_inf = 9 [default = inf];
        \\  optional double neg_inf = 10 [default = -inf];
        \\  optional float quiet_nan = 11 [default = nan];
        \\  optional float neg_nan = 12 [default = -nan];
        \\  optional double pos_infinity = 13 [default = Infinity];
        \\  optional double neg_infinity = 14 [default = -INFINITY];
        \\  optional uint64 max_u64 = 15 [default = 0xFFFFFFFFFFFFFFFF];
        \\}
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("Defaults").?;

    var msg = dynamic.DynamicMessage.init(allocator, desc);
    defer msg.deinit();
    const rendered = try stringifyAlloc(allocator, &file, &msg, .{ .always_print_primitive_fields = true });
    defer allocator.free(rendered);
    try std.testing.expectEqualSlices(u8, "{\"count\":42,\"name\":\"anon\",\"enabled\":true,\"kind\":\"ADMIN\",\"tags\":[],\"counts\":{},\"raw\":\"aGk=\",\"big\":\"9007199254740993\",\"posInf\":\"Infinity\",\"negInf\":\"-Infinity\",\"quietNan\":\"NaN\",\"negNan\":\"NaN\",\"posInfinity\":\"Infinity\",\"negInfinity\":\"-Infinity\",\"maxU64\":\"18446744073709551615\"}", rendered);
}

test "json stringify prints imported enum defaults with registry" {
    const allocator = std.testing.allocator;
    var common = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package common;
        \\enum Kind { UNKNOWN = 0; ADMIN = 7; }
    );
    defer common.deinit();
    common.name = "common.proto";
    var app = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package app;
        \\import "common.proto";
        \\message Event {
        \\  optional common.Kind kind = 1 [default = ADMIN];
        \\}
    );
    defer app.deinit();
    app.name = "app.proto";
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);
    try registry.validateAllFileReferences();

    var msg = dynamic.DynamicMessage.init(allocator, app.findMessage("Event").?);
    defer msg.deinit();
    const rendered = try stringifyAllocWithRegistry(allocator, &app, &registry, &msg, .{ .always_print_primitive_fields = true });
    defer allocator.free(rendered);
    try std.testing.expectEqualSlices(u8, "{\"kind\":\"ADMIN\"}", rendered);

    const rendered_number = try stringifyAllocWithRegistry(allocator, &app, &registry, &msg, .{ .always_print_primitive_fields = true, .enum_as_name = false });
    defer allocator.free(rendered_number);
    try std.testing.expectEqualSlices(u8, "{\"kind\":7}", rendered_number);
}

test "json parses bytes from base64 variants" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\message Bytes { bytes raw = 1; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("Bytes").?;

    var standard = try parseAlloc(allocator, &file, desc, "{\"raw\":\"++8=\"}", .{});
    defer standard.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0xfb, 0xef }, standard.get("raw").?.values.items[0].bytes);

    var url_safe_no_pad = try parseAlloc(allocator, &file, desc, "{\"raw\":\"--8\"}", .{});
    defer url_safe_no_pad.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 0xfb, 0xef }, url_safe_no_pad.get("raw").?.values.items[0].bytes);

    var url_safe_short = try parseAlloc(allocator, &file, desc, "{\"raw\":\"-_\"}", .{});
    defer url_safe_short.deinit();
    try std.testing.expectEqualSlices(u8, &.{0xfb}, url_safe_short.get("raw").?.values.items[0].bytes);
}

test "json string escape scanner distinguishes fast and escaped paths" {
    try std.testing.expect(!jsonStringNeedsEscape("plain ascii and 世界"));
    try std.testing.expect(jsonStringNeedsEscape("quote\""));
    try std.testing.expect(jsonStringNeedsEscape("slash\\"));
    try std.testing.expect(jsonStringNeedsEscape("line\n"));
}

test "json accepts unquoted integral float spellings for 32-bit integers" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\message Numbers { int32 i32 = 1; uint32 u32 = 2; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("Numbers").?;

    var parsed = try parseAlloc(allocator, &file, desc, "{\"i32\":1e5,\"u32\":4.294967295e9}", .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(i32, 100000), parsed.get("i32").?.values.items[0].int32);
    try std.testing.expectEqual(@as(u32, 4294967295), parsed.get("u32").?.values.items[0].uint32);

    // Quoted integer spellings may also use an exponent when the represented
    // value is integral and in range, matching C++/Go protobuf JSON.
    var quoted = try parseAlloc(allocator, &file, desc, "{\"i32\":\"1e5\"}", .{});
    defer quoted.deinit();
    try std.testing.expectEqual(@as(i32, 100000), quoted.get("i32").?.values.items[0].int32);

    try std.testing.expectError(error.TypeMismatch, parseAlloc(allocator, &file, desc, "{\"i32\":1.5}", .{}));
}

test "json omits proto3 implicit default scalar fields" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\message Defaults {
        \\  int32 count = 1;
        \\  string name = 2;
        \\  bool enabled = 3;
        \\  optional int32 present = 4;
        \\}
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("Defaults").?;

    var parsed = try parseAlloc(allocator, &file, desc, "{\"count\":0,\"name\":\"\",\"enabled\":false,\"present\":0}", .{});
    defer parsed.deinit();
    const rendered = try stringifyAlloc(allocator, &file, &parsed, .{});
    defer allocator.free(rendered);
    try std.testing.expectEqualSlices(u8, "{\"present\":0}", rendered);
}

test "json maps Timestamp and Duration messages as well-known strings" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\package demo;
        \\message Timestamp { int64 seconds = 1; int32 nanos = 2; }
        \\message Duration { int64 seconds = 1; int32 nanos = 2; }
        \\message Event { google.protobuf.Timestamp at = 1; google.protobuf.Duration span = 2; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const event_desc = file.findMessage("Event").?;
    const ts_desc = file.findMessage("Timestamp").?;
    const dur_desc = file.findMessage("Duration").?;

    var event = dynamic.DynamicMessage.init(allocator, event_desc);
    defer event.deinit();
    const ts = try allocator.create(dynamic.DynamicMessage);
    ts.* = dynamic.DynamicMessage.init(allocator, ts_desc);
    try ts.add(ts_desc.findField("seconds").?, .{ .int64 = 1_577_836_800 });
    try ts.add(ts_desc.findField("nanos").?, .{ .int32 = 123_000_000 });
    try event.add(event_desc.findField("at").?, .{ .message = ts });
    const dur = try allocator.create(dynamic.DynamicMessage);
    dur.* = dynamic.DynamicMessage.init(allocator, dur_desc);
    try dur.add(dur_desc.findField("seconds").?, .{ .int64 = -3 });
    try dur.add(dur_desc.findField("nanos").?, .{ .int32 = -250_000_000 });
    try event.add(event_desc.findField("span").?, .{ .message = dur });

    const rendered = try stringifyAlloc(allocator, &file, &event, .{});
    defer allocator.free(rendered);
    try std.testing.expectEqualSlices(u8, "{\"at\":\"2020-01-01T00:00:00.123Z\",\"span\":\"-3.250s\"}", rendered);

    var parsed = try parseAlloc(allocator, &file, event_desc, rendered, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(i64, 1_577_836_800), parsed.get("at").?.values.items[0].message.get("seconds").?.values.items[0].int64);
    try std.testing.expectEqual(@as(i32, 123_000_000), parsed.get("at").?.values.items[0].message.get("nanos").?.values.items[0].int32);
    try std.testing.expectEqual(@as(i64, -3), parsed.get("span").?.values.items[0].message.get("seconds").?.values.items[0].int64);
    try std.testing.expectEqual(@as(i32, -250_000_000), parsed.get("span").?.values.items[0].message.get("nanos").?.values.items[0].int32);
}

test "json maps wrapper messages as their value field" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\package google.protobuf;
        \\message StringValue { string value = 1; }
        \\message Int32Value { int32 value = 1; }
        \\message Event { .google.protobuf.StringValue name = 1; .google.protobuf.Int32Value count = 2; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const event_desc = file.findMessage("Event").?;
    const string_desc = file.findMessage("StringValue").?;
    const int_desc = file.findMessage("Int32Value").?;

    var event = dynamic.DynamicMessage.init(allocator, event_desc);
    defer event.deinit();
    const name = try allocator.create(dynamic.DynamicMessage);
    name.* = dynamic.DynamicMessage.init(allocator, string_desc);
    try name.add(string_desc.findField("value").?, .{ .string = try allocator.dupe(u8, "zig") });
    try event.add(event_desc.findField("name").?, .{ .message = name });
    const count = try allocator.create(dynamic.DynamicMessage);
    count.* = dynamic.DynamicMessage.init(allocator, int_desc);
    try count.add(int_desc.findField("value").?, .{ .int32 = 42 });
    try event.add(event_desc.findField("count").?, .{ .message = count });

    const rendered = try stringifyAlloc(allocator, &file, &event, .{});
    defer allocator.free(rendered);
    try std.testing.expectEqualSlices(u8, "{\"name\":\"zig\",\"count\":42}", rendered);

    var parsed = try parseAlloc(allocator, &file, event_desc, rendered, .{});
    defer parsed.deinit();
    try std.testing.expectEqualSlices(u8, "zig", parsed.get("name").?.values.items[0].message.get("value").?.values.items[0].string);
    try std.testing.expectEqual(@as(i32, 42), parsed.get("count").?.values.items[0].message.get("value").?.values.items[0].int32);
}

test "json maps Any message with type and base64 value" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\package google.protobuf;
        \\message Any { optional string type_url = 1; optional bytes value = 2; }
        \\message Holder { .google.protobuf.Any any = 1; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const holder_desc = file.findMessage("Holder").?;
    const any_desc = file.findMessage("Any").?;
    var holder = dynamic.DynamicMessage.init(allocator, holder_desc);
    defer holder.deinit();
    const any_msg = try allocator.create(dynamic.DynamicMessage);
    any_msg.* = dynamic.DynamicMessage.init(allocator, any_desc);
    try any_msg.add(any_desc.findField("type_url").?, .{ .string = try allocator.dupe(u8, "type.googleapis.com/demo.Msg") });
    try any_msg.add(any_desc.findField("value").?, .{ .bytes = try allocator.dupe(u8, "abc") });
    try holder.add(holder_desc.findField("any").?, .{ .message = any_msg });

    const rendered = try stringifyAlloc(allocator, &file, &holder, .{});
    defer allocator.free(rendered);
    try std.testing.expectEqualSlices(u8, "{\"any\":{\"@type\":\"type.googleapis.com/demo.Msg\",\"value\":\"YWJj\"}}", rendered);

    const bad_any = try allocator.create(dynamic.DynamicMessage);
    bad_any.* = dynamic.DynamicMessage.init(allocator, any_desc);
    try bad_any.add(any_desc.findField("value").?, .{ .bytes = try allocator.dupe(u8, "abc") });
    var bad_holder = dynamic.DynamicMessage.init(allocator, holder_desc);
    defer bad_holder.deinit();
    try bad_holder.add(holder_desc.findField("any").?, .{ .message = bad_any });
    try std.testing.expectError(error.TypeMismatch, stringifyAlloc(allocator, &file, &bad_holder, .{}));
}

test "json maps FieldMask message as comma-separated string" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\package google.protobuf;
        \\message FieldMask { repeated string paths = 1; }
        \\message Holder { .google.protobuf.FieldMask mask = 1; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const holder_desc = file.findMessage("Holder").?;
    const mask_desc = file.findMessage("FieldMask").?;

    var holder = dynamic.DynamicMessage.init(allocator, holder_desc);
    defer holder.deinit();
    const mask = try allocator.create(dynamic.DynamicMessage);
    mask.* = dynamic.DynamicMessage.init(allocator, mask_desc);
    try mask.add(mask_desc.findField("paths").?, .{ .string = try allocator.dupe(u8, "foo_bar") });
    try mask.add(mask_desc.findField("paths").?, .{ .string = try allocator.dupe(u8, "baz.qux_value") });
    try holder.add(holder_desc.findField("mask").?, .{ .message = mask });

    const rendered = try stringifyAlloc(allocator, &file, &holder, .{});
    defer allocator.free(rendered);
    try std.testing.expectEqualSlices(u8, "{\"mask\":\"fooBar,baz.quxValue\"}", rendered);

    var parsed = try parseAlloc(allocator, &file, holder_desc, rendered, .{});
    defer parsed.deinit();
    const parsed_mask = parsed.get("mask").?.values.items[0].message;
    try std.testing.expectEqualSlices(u8, "foo_bar", parsed_mask.get("paths").?.values.items[0].string);
    try std.testing.expectEqualSlices(u8, "baz.qux_value", parsed_mask.get("paths").?.values.items[1].string);

    const bad_mask = try allocator.create(dynamic.DynamicMessage);
    bad_mask.* = dynamic.DynamicMessage.init(allocator, mask_desc);
    try bad_mask.add(mask_desc.findField("paths").?, .{ .string = try allocator.dupe(u8, "foo_1") });
    var bad_holder = dynamic.DynamicMessage.init(allocator, holder_desc);
    defer bad_holder.deinit();
    try bad_holder.add(holder_desc.findField("mask").?, .{ .message = bad_mask });
    try std.testing.expectError(error.InvalidFieldMask, stringifyAlloc(allocator, &file, &bad_holder, .{}));
}

test "json maps Empty message as empty object" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\package google.protobuf;
        \\message Empty {}
        \\message Holder { .google.protobuf.Empty empty = 1; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const holder_desc = file.findMessage("Holder").?;
    const empty_desc = file.findMessage("Empty").?;
    var holder = dynamic.DynamicMessage.init(allocator, holder_desc);
    defer holder.deinit();
    const empty = try allocator.create(dynamic.DynamicMessage);
    empty.* = dynamic.DynamicMessage.init(allocator, empty_desc);
    try holder.add(holder_desc.findField("empty").?, .{ .message = empty });
    const rendered = try stringifyAlloc(allocator, &file, &holder, .{});
    defer allocator.free(rendered);
    try std.testing.expectEqualSlices(u8, "{\"empty\":{}}", rendered);
    var parsed = try parseAlloc(allocator, &file, holder_desc, rendered, .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.get("empty") != null);
    try std.testing.expectError(error.UnknownField, parseAlloc(allocator, &file, holder_desc, "{\"empty\":{\"x\":1}}", .{}));
}

test "json parses Any message with type and base64 value" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\package google.protobuf;
        \\message Any { optional string type_url = 1; optional bytes value = 2; }
        \\message Holder { .google.protobuf.Any any = 1; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const holder_desc = file.findMessage("Holder").?;
    var parsed = try parseAlloc(allocator, &file, holder_desc, "{\"any\":{\"@type\":\"type.googleapis.com/demo.Msg\",\"value\":\"YWJj\"}}", .{});
    defer parsed.deinit();
    const any_msg = parsed.get("any").?.values.items[0].message;
    try std.testing.expectEqualSlices(u8, "type.googleapis.com/demo.Msg", any_msg.get("type_url").?.values.items[0].string);
    try std.testing.expectEqualSlices(u8, "abc", any_msg.get("value").?.values.items[0].bytes);

    var empty_any = try parseAlloc(allocator, &file, holder_desc, "{\"any\":{\"value\":\"YWJj\"}}", .{});
    defer empty_any.deinit();
    try std.testing.expectEqualSlices(u8, "abc", empty_any.get("any").?.values.items[0].message.get("value").?.values.items[0].bytes);
    try std.testing.expectError(error.TypeMismatch, parseAlloc(allocator, &file, holder_desc, "{\"any\":{\"@type\":\"\",\"value\":\"YWJj\"}}", .{}));
    try std.testing.expectError(error.TypeMismatch, parseAlloc(allocator, &file, holder_desc, "{\"any\":{\"@type\":\"type.googleapis.com/\",\"value\":\"YWJj\"}}", .{}));
    try std.testing.expectError(error.TypeMismatch, parseAlloc(allocator, &file, holder_desc, "{\"any\":{\"@type\":\"type.googleapis.com/unknown.Msg\"}}", .{}));
}

test "json expands Any message payloads when type is known" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\package demo;
        \\message Msg { int32 id = 1; string label = 2; }
        \\message Any { optional string type_url = 1; optional bytes value = 2; }
        \\message Holder { .google.protobuf.Any any = 1; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const holder_desc = file.findMessage("Holder").?;
    const any_desc = file.findMessage("Any").?;
    const msg_desc = file.findMessage("Msg").?;

    var payload = dynamic.DynamicMessage.init(allocator, msg_desc);
    defer payload.deinit();
    try payload.add(msg_desc.findField("id").?, .{ .int32 = 7 });
    try payload.add(msg_desc.findField("label").?, .{ .string = try allocator.dupe(u8, "known") });
    const payload_bytes = try payload.encodedDeterministic(&file);
    defer allocator.free(payload_bytes);

    var holder = dynamic.DynamicMessage.init(allocator, holder_desc);
    defer holder.deinit();
    const any_msg = try allocator.create(dynamic.DynamicMessage);
    any_msg.* = dynamic.DynamicMessage.init(allocator, any_desc);
    try any_msg.add(any_desc.findField("type_url").?, .{ .string = try allocator.dupe(u8, "type.googleapis.com/demo.Msg") });
    try any_msg.add(any_desc.findField("value").?, .{ .bytes = try allocator.dupe(u8, payload_bytes) });
    try holder.add(holder_desc.findField("any").?, .{ .message = any_msg });

    const rendered = try stringifyAlloc(allocator, &file, &holder, .{});
    defer allocator.free(rendered);
    try std.testing.expectEqualSlices(u8, "{\"any\":{\"@type\":\"type.googleapis.com/demo.Msg\",\"id\":7,\"label\":\"known\"}}", rendered);

    try std.testing.expectError(error.UnknownField, parseAlloc(allocator, &file, holder_desc, "{\"any\":{\"@type\":\"type.googleapis.com/demo.Msg\",\"value\":\"AA==\",\"id\":8}}", .{}));

    var parsed = try parseAlloc(allocator, &file, holder_desc, "{\"any\":{\"@type\":\"type.googleapis.com/demo.Msg\",\"id\":8,\"label\":\"parsed\"}}", .{});
    defer parsed.deinit();
    const parsed_any = parsed.get("any").?.values.items[0].message;
    const parsed_value = parsed_any.get("value").?.values.items[0].bytes;
    var decoded_payload = dynamic.DynamicMessage.init(allocator, msg_desc);
    defer decoded_payload.deinit();
    try decoded_payload.decode(&file, parsed_value);
    try std.testing.expectEqual(@as(i32, 8), decoded_payload.get("id").?.values.items[0].int32);
    try std.testing.expectEqualSlices(u8, "parsed", decoded_payload.get("label").?.values.items[0].string);

    var empty_any = try parseAlloc(allocator, &file, holder_desc, "{\"any\":{}}", .{});
    defer empty_any.deinit();
    const empty_rendered = try stringifyAlloc(allocator, &file, &empty_any, .{});
    defer allocator.free(empty_rendered);
    try std.testing.expectEqualSlices(u8, "{\"any\":{}}", empty_rendered);
}

test "json parses Any value envelopes for well-known payloads" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\package google.protobuf;
        \\enum NullValue { NULL_VALUE = 0; }
        \\message Any { string type_url = 1; bytes value = 2; }
        \\message Int32Value { int32 value = 1; }
        \\message Timestamp { int64 seconds = 1; int32 nanos = 2; }
        \\message Struct { map<string, Value> fields = 1; }
        \\message ListValue { repeated Value values = 1; }
        \\message Value {
        \\  oneof kind {
        \\    NullValue null_value = 1;
        \\    double number_value = 2;
        \\    string string_value = 3;
        \\    bool bool_value = 4;
        \\    Struct struct_value = 5;
        \\    ListValue list_value = 6;
        \\  }
        \\}
        \\message Holder { .google.protobuf.Any any = 1; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const holder_desc = file.findMessage("Holder").?;
    const int_desc = file.findMessage("Int32Value").?;
    const ts_desc = file.findMessage("Timestamp").?;
    const struct_desc = file.findMessage("Struct").?;

    var parsed_int = try parseAlloc(allocator, &file, holder_desc, "{\"any\":{\"@type\":\"type.googleapis.com/google.protobuf.Int32Value\",\"value\":12345}}", .{});
    defer parsed_int.deinit();
    var decoded_int = dynamic.DynamicMessage.init(allocator, int_desc);
    defer decoded_int.deinit();
    try decoded_int.decode(&file, parsed_int.get("any").?.values.items[0].message.get("value").?.values.items[0].bytes);
    try std.testing.expectEqual(@as(i32, 12345), decoded_int.get("value").?.values.items[0].int32);
    const rendered_int = try stringifyAlloc(allocator, &file, &parsed_int, .{});
    defer allocator.free(rendered_int);
    try std.testing.expectEqualSlices(u8, "{\"any\":{\"@type\":\"type.googleapis.com/google.protobuf.Int32Value\",\"value\":12345}}", rendered_int);

    var parsed_ts = try parseAlloc(allocator, &file, holder_desc, "{\"any\":{\"@type\":\"type.googleapis.com/google.protobuf.Timestamp\",\"value\":\"1970-01-01T00:00:00Z\"}}", .{});
    defer parsed_ts.deinit();
    var decoded_ts = dynamic.DynamicMessage.init(allocator, ts_desc);
    defer decoded_ts.deinit();
    try decoded_ts.decode(&file, parsed_ts.get("any").?.values.items[0].message.get("value").?.values.items[0].bytes);
    try std.testing.expect(decoded_ts.get("seconds") == null);
    const rendered_ts = try stringifyAlloc(allocator, &file, &parsed_ts, .{});
    defer allocator.free(rendered_ts);
    try std.testing.expectEqualSlices(u8, "{\"any\":{\"@type\":\"type.googleapis.com/google.protobuf.Timestamp\",\"value\":\"1970-01-01T00:00:00Z\"}}", rendered_ts);

    var parsed_struct = try parseAlloc(allocator, &file, holder_desc, "{\"any\":{\"@type\":\"type.googleapis.com/google.protobuf.Struct\",\"value\":{\"foo\":1}}}", .{});
    defer parsed_struct.deinit();
    var decoded_struct = dynamic.DynamicMessage.init(allocator, struct_desc);
    defer decoded_struct.deinit();
    try decoded_struct.decode(&file, parsed_struct.get("any").?.values.items[0].message.get("value").?.values.items[0].bytes);
    try std.testing.expectEqual(@as(usize, 1), decoded_struct.get("fields").?.values.items.len);
    const rendered_struct = try stringifyAlloc(allocator, &file, &parsed_struct, .{});
    defer allocator.free(rendered_struct);
    try std.testing.expectEqualSlices(u8, "{\"any\":{\"@type\":\"type.googleapis.com/google.protobuf.Struct\",\"value\":{\"foo\":1}}}", rendered_struct);

    try std.testing.expectError(error.TypeMismatch, parseAlloc(allocator, &file, holder_desc, "{\"any\":{\"@type\":\"not_a_url\",\"value\":\"\"}}", .{}));
}

test "json initialized parse validates expanded Any payloads" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto2";
        \\package demo;
        \\message Msg { required int32 id = 1; }
        \\message Any { optional string type_url = 1; optional bytes value = 2; }
        \\message Holder { optional .google.protobuf.Any any = 1; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const holder_desc = file.findMessage("Holder").?;

    var parsed = try parseAlloc(allocator, &file, holder_desc, "{\"any\":{\"@type\":\"type.googleapis.com/demo.Msg\"}}", .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.get("any").?.values.items[0].message.get("value") != null);

    try std.testing.expectError(error.MissingRequiredField, parseInitializedAlloc(allocator, &file, holder_desc, "{\"any\":{\"@type\":\"type.googleapis.com/demo.Msg\"}}", .{}));
    var initialized = try parseInitializedAlloc(allocator, &file, holder_desc, "{\"any\":{\"@type\":\"type.googleapis.com/demo.Msg\",\"id\":7}}", .{});
    defer initialized.deinit();
    const any_msg = initialized.get("any").?.values.items[0].message;
    const payload = any_msg.get("value").?.values.items[0].bytes;
    var decoded = dynamic.DynamicMessage.init(allocator, file.findMessage("Msg").?);
    defer decoded.deinit();
    try decoded.decodeInitialized(&file, payload);
    try std.testing.expectEqual(@as(i32, 7), decoded.get("id").?.values.items[0].int32);
}

test "json expands Any payloads using registry imports" {
    const allocator = std.testing.allocator;
    var common = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package common;
        \\message Payload { int32 id = 1; string label = 2; }
    );
    defer common.deinit();
    var app = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package app;
        \\import "common.proto";
        \\message Any { optional string type_url = 1; optional bytes value = 2; }
        \\message Holder { .google.protobuf.Any any = 1; }
    );
    defer app.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    common.name = "common.proto";
    app.name = "app.proto";
    try registry.addFile(&common);
    try registry.addFile(&app);

    const holder_desc = app.findMessage("Holder").?;
    const any_desc = app.findMessage("Any").?;
    const payload_desc = common.findMessage("Payload").?;

    var payload = dynamic.DynamicMessage.init(allocator, payload_desc);
    defer payload.deinit();
    try payload.add(payload_desc.findField("id").?, .{ .int32 = 7 });
    try payload.add(payload_desc.findField("label").?, .{ .string = try allocator.dupe(u8, "known") });
    const payload_bytes = try payload.encodedDeterministic(&common);
    defer allocator.free(payload_bytes);

    var holder = dynamic.DynamicMessage.init(allocator, holder_desc);
    defer holder.deinit();
    const any_msg = try allocator.create(dynamic.DynamicMessage);
    any_msg.* = dynamic.DynamicMessage.init(allocator, any_desc);
    try any_msg.add(any_desc.findField("type_url").?, .{ .string = try allocator.dupe(u8, "type.googleapis.com/common.Payload") });
    try any_msg.add(any_desc.findField("value").?, .{ .bytes = try allocator.dupe(u8, payload_bytes) });
    try holder.add(holder_desc.findField("any").?, .{ .message = any_msg });

    const rendered = try stringifyAllocWithRegistry(allocator, &app, &registry, &holder, .{});
    defer allocator.free(rendered);
    try std.testing.expectEqualSlices(u8, "{\"any\":{\"@type\":\"type.googleapis.com/common.Payload\",\"id\":7,\"label\":\"known\"}}", rendered);

    var parsed = try parseAllocWithRegistry(allocator, &app, &registry, holder_desc, "{\"any\":{\"@type\":\"type.googleapis.com/common.Payload\",\"id\":8,\"label\":\"parsed\"}}", .{});
    defer parsed.deinit();
    const parsed_any = parsed.get("any").?.values.items[0].message;
    const parsed_value = parsed_any.get("value").?.values.items[0].bytes;
    var decoded_payload = dynamic.DynamicMessage.init(allocator, payload_desc);
    defer decoded_payload.deinit();
    try decoded_payload.decodeWithRegistry(&common, &registry, parsed_value);
    try std.testing.expectEqual(@as(i32, 8), decoded_payload.get("id").?.values.items[0].int32);
    try std.testing.expectEqualSlices(u8, "parsed", decoded_payload.get("label").?.values.items[0].string);
}

test "json maps Struct Value and ListValue messages" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\package google.protobuf;
        \\enum NullValue { NULL_VALUE = 0; }
        \\message Struct { map<string, Value> fields = 1; }
        \\message ListValue { repeated Value values = 1; }
        \\message Value {
        \\  oneof kind {
        \\    NullValue null_value = 1;
        \\    double number_value = 2;
        \\    string string_value = 3;
        \\    bool bool_value = 4;
        \\    Struct struct_value = 5;
        \\    ListValue list_value = 6;
        \\  }
        \\}
        \\message Holder { .google.protobuf.Struct data = 1; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    const holder_desc = file.findMessage("Holder").?;
    const struct_desc = file.findMessage("Struct").?;
    const value_desc = file.findMessage("Value").?;
    const list_desc = file.findMessage("ListValue").?;

    var holder = dynamic.DynamicMessage.init(allocator, holder_desc);
    defer holder.deinit();
    const st = try allocator.create(dynamic.DynamicMessage);
    st.* = dynamic.DynamicMessage.init(allocator, struct_desc);
    const fields = struct_desc.findField("fields").?;

    const name_value = try allocator.create(dynamic.DynamicMessage);
    name_value.* = dynamic.DynamicMessage.init(allocator, value_desc);
    try name_value.add(value_desc.findField("string_value").?, .{ .string = try allocator.dupe(u8, "zig") });
    const name_entry = try allocator.create(dynamic.MapEntry);
    name_entry.* = .{ .key = .{ .string = try allocator.dupe(u8, "name") }, .value = .{ .message = name_value } };
    try st.add(fields, .{ .map_entry = name_entry });

    const list = try allocator.create(dynamic.DynamicMessage);
    list.* = dynamic.DynamicMessage.init(allocator, list_desc);
    const list_item = try allocator.create(dynamic.DynamicMessage);
    list_item.* = dynamic.DynamicMessage.init(allocator, value_desc);
    try list_item.add(value_desc.findField("number_value").?, .{ .double = 1.5 });
    try list.add(list_desc.findField("values").?, .{ .message = list_item });
    const list_value = try allocator.create(dynamic.DynamicMessage);
    list_value.* = dynamic.DynamicMessage.init(allocator, value_desc);
    try list_value.add(value_desc.findField("list_value").?, .{ .message = list });
    const list_entry = try allocator.create(dynamic.MapEntry);
    list_entry.* = .{ .key = .{ .string = try allocator.dupe(u8, "items") }, .value = .{ .message = list_value } };
    try st.add(fields, .{ .map_entry = list_entry });

    try holder.add(holder_desc.findField("data").?, .{ .message = st });
    const rendered = try stringifyAlloc(allocator, &file, &holder, .{});
    defer allocator.free(rendered);
    try std.testing.expectEqualSlices(u8, "{\"data\":{\"name\":\"zig\",\"items\":[1.5]}}", rendered);

    var parsed = try parseAlloc(allocator, &file, holder_desc, rendered, .{});
    defer parsed.deinit();
    const parsed_struct = parsed.get("data").?.values.items[0].message;
    try std.testing.expectEqual(@as(usize, 2), parsed_struct.get("fields").?.values.items.len);

    const holder_value_source =
        \\syntax = "proto3";
        \\package google.protobuf;
        \\enum NullValue { NULL_VALUE = 0; }
        \\message Struct { map<string, Value> fields = 1; }
        \\message ListValue { repeated Value values = 1; }
        \\message Value {
        \\  oneof kind {
        \\    NullValue null_value = 1;
        \\    double number_value = 2;
        \\    string string_value = 3;
        \\    bool bool_value = 4;
        \\    Struct struct_value = 5;
        \\    ListValue list_value = 6;
        \\  }
        \\}
        \\message HolderValue { .google.protobuf.Value value = 1; }
    ;
    var value_file = try @import("parser.zig").Parser.parse(allocator, holder_value_source);
    defer value_file.deinit();
    const holder_value_desc = value_file.findMessage("HolderValue").?;
    var parsed_null = try parseAlloc(allocator, &value_file, holder_value_desc, "{\"value\":null}", .{});
    defer parsed_null.deinit();
    const value_msg = parsed_null.get("value").?.values.items[0].message;
    try std.testing.expect(value_msg.get("null_value") != null);

    var bad_holder = dynamic.DynamicMessage.init(allocator, holder_value_desc);
    defer bad_holder.deinit();
    const bad_value = try allocator.create(dynamic.DynamicMessage);
    bad_value.* = dynamic.DynamicMessage.init(allocator, value_file.findMessage("Value").?);
    try bad_value.add(value_file.findMessage("Value").?.findField("number_value").?, .{ .double = std.math.inf(f64) });
    try bad_holder.add(holder_value_desc.findField("value").?, .{ .message = bad_value });
    try std.testing.expectError(error.InvalidNumber, stringifyAlloc(allocator, &value_file, &bad_holder, .{}));
}
