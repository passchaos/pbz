const std = @import("std");
const pbz = @import("pbz");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var file = try pbz.ProtoParser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.any;
        \\message Payload {
        \\  required int32 id = 1;
        \\  optional string note = 2;
        \\}
    );
    defer file.deinit();
    file.name = "any_payload.proto";

    var registry = pbz.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);

    const payload_desc = file.findMessage("Payload").?;
    var missing = pbz.DynamicMessage.init(allocator, payload_desc);
    defer missing.deinit();
    try std.testing.expectError(
        error.MissingRequiredField,
        pbz.Any.packDynamicInitializedWithRegistry(allocator, &file, &registry, "demo.any.Payload", &missing),
    );

    var payload = pbz.DynamicMessage.init(allocator, payload_desc);
    defer payload.deinit();
    try payload.add(payload_desc.findField("id").?, .{ .int32 = 42 });
    try payload.add(payload_desc.findField("note").?, .{ .string = try allocator.dupe(u8, "dynamic-any") });

    var any = try pbz.Any.packDynamicInitializedWithRegistry(
        allocator,
        &file,
        &registry,
        "demo.any.Payload",
        &payload,
    );
    defer any.deinit(allocator);
    try std.testing.expect(any.isType("demo.any.Payload"));
    try std.testing.expectEqualStrings("demo.any.Payload", any.typeName());
    try std.testing.expectEqualStrings(pbz.Any.default_type_url_prefix, any.typeUrlPrefix());

    var custom_prefix_any = try pbz.Any.packDynamicInitializedWithRegistryAndPrefix(
        allocator,
        "example.test/any",
        &file,
        &registry,
        "demo.any.Payload",
        &payload,
    );
    defer custom_prefix_any.deinit(allocator);
    try std.testing.expectEqualStrings("example.test/any/demo.any.Payload", custom_prefix_any.typeUrl());
    try std.testing.expect(custom_prefix_any.typeNameIs(".demo.any.Payload"));
    try std.testing.expect(custom_prefix_any.typeUrlPrefixIs("example.test/any/"));

    var unpacked = try any.unpackDynamicInitializedWithRegistry(
        allocator,
        &file,
        &registry,
        payload_desc,
        ".demo.any.Payload",
    );
    defer unpacked.deinit();
    try std.testing.expectEqual(@as(i32, 42), unpacked.get("id").?.values.items[0].int32);
    try std.testing.expectEqualStrings("dynamic-any", unpacked.get("note").?.values.items[0].string);
    try std.testing.expectError(
        error.TypeMismatch,
        any.unpackDynamicInitializedWithRegistry(allocator, &file, &registry, payload_desc, "demo.any.Other"),
    );

    var bad = try pbz.Any.packBytes(allocator, "demo.any.Payload", "");
    defer bad.deinit(allocator);
    try std.testing.expectError(
        error.MissingRequiredField,
        bad.unpackDynamicInitializedWithRegistry(allocator, &file, &registry, payload_desc, "demo.any.Payload"),
    );
}
