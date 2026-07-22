const std = @import("std");
const pbz = @import("pbz");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try missingWeakImportStillLoads(allocator);
    try presentWeakImportResolvesNormally(allocator);
}

fn missingWeakImportStillLoads(allocator: std.mem.Allocator) !void {
    var tree = pbz.MemorySourceTree.init(allocator);
    defer tree.deinit();
    try tree.add("root.proto",
        \\syntax = "proto2";
        \\package demo.weakmissing;
        \\import weak "missing.proto";
        \\message Root {
        \\  optional MissingType weak_field = 1;
        \\  optional string label = 2;
        \\}
    );

    var loaded = try pbz.loadMemory(allocator, &tree, "root.proto");
    defer loaded.deinit();

    const root_file = loaded.registry.findFile("root.proto") orelse return error.MissingFile;
    const refl = pbz.Reflection.init(allocator, &loaded.registry);
    try std.testing.expectEqual(@as(usize, 1), root_file.imports.items.len);
    try std.testing.expectEqual(pbz.schema.Import.Kind.weak, root_file.imports.items[0].kind);
    const missing_import = try refl.fileImport(root_file, "missing.proto");
    try std.testing.expectEqualStrings("missing.proto", refl.importPath(missing_import));
    try std.testing.expectEqual(pbz.schema.Import.Kind.weak, refl.importKind(missing_import));
    try std.testing.expect(refl.importIsWeak(missing_import));
    try std.testing.expect(!refl.importIsPublic(missing_import));
    try std.testing.expect(!refl.importIsOption(missing_import));
    try std.testing.expectEqual(@as(usize, 1), refl.fileMissingWeakImportCount(root_file));
    try std.testing.expectEqualStrings("missing.proto", try refl.fileMissingWeakImportAt(root_file, 0));
    try std.testing.expectEqual(@as(usize, 0), try refl.fileMissingWeakImportIndex(root_file, "missing.proto"));
    try std.testing.expectError(error.UnknownFile, refl.fileMissingWeakImportAt(root_file, 1));
    try std.testing.expectError(error.UnknownFile, refl.fileMissingWeakImportIndex(root_file, "other.proto"));
    try std.testing.expect(refl.fileHasMissingWeakImport(root_file, "missing.proto"));

    const root_desc = root_file.findMessage("Root") orelse return error.MissingDescriptor;
    try std.testing.expect(root_desc.findField("weak_field") != null);

    // A missing weak import should not make the rest of the file unusable.
    // Known local fields still support dynamic binary, JSON, TextFormat, and
    // descriptor-set workflows; only callers that actually touch the unresolved
    // weak field need the missing schema.
    var msg = pbz.DynamicMessage.init(allocator, root_desc);
    defer msg.deinit();
    try msg.add(root_desc.findField("label") orelse return error.MissingField, .{ .string = try allocator.dupe(u8, "loaded") });

    const bytes = try msg.encoded(root_file);
    defer allocator.free(bytes);
    var decoded = pbz.DynamicMessage.init(allocator, root_desc);
    defer decoded.deinit();
    try decoded.decode(root_file, bytes);
    try std.testing.expectEqualStrings("loaded", decoded.get("label").?.values.items[0].string);

    const json = try pbz.stringifyJsonAlloc(allocator, root_file, &msg, .{});
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"label\":\"loaded\"") != null);
    var json_roundtrip = try pbz.parseJsonAlloc(allocator, root_file, root_desc, json, .{});
    defer json_roundtrip.deinit();
    try std.testing.expectEqualStrings("loaded", json_roundtrip.get("label").?.values.items[0].string);

    const text = try pbz.formatTextAlloc(allocator, root_file, &msg, .{});
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "label: \"loaded\"") != null);
    var text_roundtrip = try pbz.parseTextAlloc(allocator, root_file, root_desc, text);
    defer text_roundtrip.deinit();
    try std.testing.expectEqualStrings("loaded", text_roundtrip.get("label").?.values.items[0].string);

    const descriptor_set = try pbz.encodeFileDescriptorSet(allocator, &.{root_file});
    defer allocator.free(descriptor_set);
    const decoded_set = try pbz.decodeFileDescriptorSet(allocator, descriptor_set);
    defer {
        for (decoded_set) |*file| file.deinit();
        allocator.free(decoded_set);
    }
    try std.testing.expectEqual(@as(usize, 1), decoded_set.len);
    try std.testing.expectEqual(schemaImportKindWeak(), decoded_set[0].imports.items[0].kind);
    try std.testing.expectEqualStrings("missing.proto", decoded_set[0].missing_weak_imports.items[0]);
}

fn presentWeakImportResolvesNormally(allocator: std.mem.Allocator) !void {
    var tree = pbz.MemorySourceTree.init(allocator);
    defer tree.deinit();
    try tree.add("payload.proto",
        \\syntax = "proto2";
        \\package demo.weakpresent;
        \\message Payload { optional int32 id = 1; }
    );
    try tree.add("root.proto",
        \\syntax = "proto2";
        \\package demo.weakpresent;
        \\import weak "payload.proto";
        \\message Root {
        \\  optional Payload payload = 1;
        \\  optional string label = 2;
        \\}
    );

    var loaded = try pbz.loadMemory(allocator, &tree, "root.proto");
    defer loaded.deinit();

    const root_file = loaded.registry.findFile("root.proto") orelse return error.MissingFile;
    const refl = pbz.Reflection.init(allocator, &loaded.registry);
    try std.testing.expectEqual(schemaImportKindWeak(), root_file.imports.items[0].kind);
    try std.testing.expectEqual(@as(usize, 0), refl.fileMissingWeakImportCount(root_file));
    try std.testing.expectError(error.UnknownFile, refl.fileMissingWeakImportAt(root_file, 0));

    const root_desc = root_file.findMessage("Root") orelse return error.MissingDescriptor;
    const payload_desc = loaded.registry.findMessage(".demo.weakpresent.Payload", null) orelse return error.MissingDescriptor;

    const payload = try allocator.create(pbz.DynamicMessage);
    payload.* = pbz.DynamicMessage.init(allocator, payload_desc);
    try payload.add(payload_desc.findField("id") orelse return error.MissingField, .{ .int32 = 7 });

    var root = pbz.DynamicMessage.init(allocator, root_desc);
    defer root.deinit();
    try root.add(root_desc.findField("payload") orelse return error.MissingField, .{ .message = payload });
    try root.add(root_desc.findField("label") orelse return error.MissingField, .{ .string = try allocator.dupe(u8, "present") });

    const bytes = try root.encodedInitializedWithRegistry(root_file, &loaded.registry);
    defer allocator.free(bytes);
    var decoded = pbz.DynamicMessage.init(allocator, root_desc);
    defer decoded.deinit();
    try decoded.decodeInitializedWithRegistry(root_file, &loaded.registry, bytes);
    try std.testing.expectEqual(@as(i32, 7), decoded.get("payload").?.values.items[0].message.get("id").?.values.items[0].int32);
    try std.testing.expectEqualStrings("present", decoded.get("label").?.values.items[0].string);

    const json = try pbz.stringifyJsonAllocWithRegistry(allocator, root_file, &loaded.registry, &root, .{});
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"payload\":") != null);
    var json_roundtrip = try pbz.parseJsonAllocWithRegistry(allocator, root_file, &loaded.registry, root_desc, json, .{});
    defer json_roundtrip.deinit();
    try std.testing.expectEqual(@as(i32, 7), json_roundtrip.get("payload").?.values.items[0].message.get("id").?.values.items[0].int32);

    const text = try pbz.formatTextAllocWithRegistry(allocator, root_file, &loaded.registry, &root, .{});
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "payload {") != null);
    var text_roundtrip = try pbz.parseTextAllocWithRegistry(allocator, root_file, &loaded.registry, root_desc, text);
    defer text_roundtrip.deinit();
    try std.testing.expectEqual(@as(i32, 7), text_roundtrip.get("payload").?.values.items[0].message.get("id").?.values.items[0].int32);
}

fn schemaImportKindWeak() pbz.schema.Import.Kind {
    return .weak;
}

comptime {
    _ = pbz;
}
