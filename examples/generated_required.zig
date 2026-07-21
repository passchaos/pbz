const std = @import("std");
const pbz = @import("pbz");
const required_pb = @import("generated/required.pb.zig");

const required = required_pb.demo.required;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Proto2 required fields are easy to accidentally skip in perf-oriented
    // generated structs because the plain `encode`/`decode` APIs intentionally
    // mirror protobuf's low-level partial-message behavior.  The `*Initialized`
    // entry points provide the C++-style safety gate: they reject missing local
    // required fields and recurse through optional/repeated message children.
    var missing_parent = required.Parent.init();
    defer missing_parent.deinit(allocator);
    try std.testing.expectError(error.MissingRequiredField, missing_parent.encodeInitialized(allocator));

    var child_without_id = required.Child.init();
    defer child_without_id.deinit(allocator);
    child_without_id.label = "missing-id";
    child_without_id.has_label = true;
    try std.testing.expectError(error.MissingRequiredField, child_without_id.encodeInitialized(allocator));

    var parent = required.Parent.init();
    defer parent.deinit(allocator);
    parent.name = "root";
    parent.has_name = true;

    var child = required.Child.init();
    defer child.deinit(allocator);
    child.id = 7;
    child.has_id = true;
    child.label = "primary";
    child.has_label = true;
    parent.child = try child.cloneOwned(allocator);

    const history = try allocator.alloc(required.Child, 2);
    history[0] = try child.cloneOwned(allocator);
    history[1] = required.Child.init();
    history[1].id = 8;
    history[1].has_id = true;
    history[1].label = "history";
    history[1].has_label = true;
    parent.history = history;

    const bytes = try parent.encodeInitialized(allocator);
    defer allocator.free(bytes);

    var decoded = try required.Parent.decodeOwnedInitialized(allocator, bytes);
    defer decoded.deinit(allocator);
    try std.testing.expectEqualStrings("root", decoded.name);
    try std.testing.expectEqual(@as(i32, 7), decoded.child.?.id);
    try std.testing.expectEqual(@as(usize, 2), decoded.history.len);
    try std.testing.expectEqual(@as(i32, 8), decoded.history[1].id);

    const deterministic = try decoded.encodeDeterministicInitialized(allocator);
    defer allocator.free(deterministic);
    try std.testing.expectEqualSlices(u8, bytes, deterministic);

    const json = try decoded.jsonStringifyAlloc(allocator);
    defer allocator.free(json);
    var json_roundtrip = try required.Parent.jsonParseInitialized(allocator, json);
    defer json_roundtrip.deinit(allocator);
    try std.testing.expectEqual(@as(i32, 7), json_roundtrip.child.?.id);
    try std.testing.expectError(error.MissingRequiredField, required.Parent.jsonParseInitialized(allocator, "{}"));
    try std.testing.expectError(error.MissingRequiredField, required.Parent.jsonParseInitialized(allocator, "{\"name\":\"root\",\"child\":{}}"));
    try std.testing.expectError(error.MissingRequiredField, required.Parent.jsonParseInitialized(allocator, "{\"name\":\"root\",\"history\":[{}]}"));

    const text = try decoded.formatTextAlloc(allocator);
    defer allocator.free(text);
    var text_roundtrip = try required.Parent.parseTextInitialized(allocator, text);
    defer text_roundtrip.deinit(allocator);
    try std.testing.expectEqual(@as(i32, 8), text_roundtrip.history[1].id);
    try std.testing.expectError(error.MissingRequiredField, required.Parent.parseTextInitialized(allocator, ""));
    try std.testing.expectError(error.MissingRequiredField, required.Parent.parseTextInitialized(allocator, "name: \"root\"\nchild {\n}\n"));

    if (try json_roundtrip.missingRequiredFieldPath(allocator)) |path| {
        defer allocator.free(path);
        return error.UnexpectedMissingRequiredField;
    }

    var invalid_nested = required.Parent.init();
    defer invalid_nested.deinit(allocator);
    invalid_nested.name = "root";
    invalid_nested.has_name = true;
    invalid_nested.child = required.Child.init();
    const missing_path = (try invalid_nested.missingRequiredFieldPath(allocator)) orelse return error.ExpectedMissingRequiredField;
    defer allocator.free(missing_path);
    try std.testing.expectEqualStrings("child.id", missing_path);
}

comptime {
    _ = pbz;
}
