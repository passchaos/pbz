const std = @import("std");
const helpers = @import("helpers.zig");
const parser = @import("../parser.zig");

test "valueMatchesScalar accepts only matching scalar tags" {
    try std.testing.expect(helpers.valueMatchesScalar(.int32, .{ .int32 = 7 }));
    try std.testing.expect(helpers.valueMatchesScalar(.string, .{ .string = @constCast("x") }));
    try std.testing.expect(helpers.valueMatchesScalar(.bool, .{ .boolean = true }));
    try std.testing.expect(!helpers.valueMatchesScalar(.int32, .{ .int64 = 7 }));
    try std.testing.expect(!helpers.valueMatchesScalar(.bool, .{ .int32 = 1 }));
}

test "import helpers count and index by kind" {
    const allocator = std.testing.allocator;
    var file = try parser.Parser.parse(allocator,
        \\syntax = "proto3";
        \\package demo;
        \\import public "common.proto";
        \\import "other.proto";
        \\import weak "weak.proto";
        \\message Empty {}
    );
    defer file.deinit();

    try std.testing.expectEqual(@as(usize, 1), helpers.importKindCount(&file, .public));
    try std.testing.expectEqual(@as(usize, 1), helpers.importKindCount(&file, .weak));
    try std.testing.expectEqual(@as(usize, 1), helpers.importKindCount(&file, .normal));
    try std.testing.expectEqualStrings("common.proto", helpers.importOfKindAt(&file, .public, 0).?.path);
    try std.testing.expect(helpers.importOfKindAt(&file, .public, 1) == null);
}

test "message scope and full name include the package path" {
    const allocator = std.testing.allocator;
    var file = try parser.Parser.parse(allocator,
        \\syntax = "proto3";
        \\package demo;
        \\message Outer { message Inner { int32 id = 1; } Inner inner = 1; }
    );
    defer file.deinit();

    const outer = file.findMessage("Outer").?;
    const inner = outer.findMessageDeep("Inner").?;
    var buf: [512]u8 = undefined;
    try std.testing.expectEqualStrings("demo.Outer.Inner", helpers.messageScope(&file, inner, &buf).?);
    const full = (try helpers.messageFullNameInFileAlloc(allocator, &file, inner)).?;
    defer allocator.free(full);
    try std.testing.expectEqualStrings("demo.Outer.Inner", full);
}
