const std = @import("std");
const schema = @import("schema.zig");
const parser = @import("parser.zig");
const registry_mod = @import("registry.zig");

pub const Error = std.mem.Allocator.Error || parser.Error || error{ FileNotFound, ImportCycle };

pub const MemorySourceTree = struct {
    allocator: std.mem.Allocator,
    files: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) MemorySourceTree {
        return .{ .allocator = allocator, .files = std.StringHashMap([]const u8).init(allocator) };
    }

    pub fn deinit(self: *MemorySourceTree) void {
        self.files.deinit();
        self.* = undefined;
    }

    pub fn add(self: *MemorySourceTree, path: []const u8, source: []const u8) std.mem.Allocator.Error!void {
        try self.files.put(path, source);
    }

    pub fn get(self: *const MemorySourceTree, path: []const u8) ?[]const u8 {
        return self.files.get(path);
    }
};

pub const LoadResult = struct {
    allocator: std.mem.Allocator,
    files: std.ArrayList(schema.FileDescriptor) = .empty,
    registry: registry_mod.Registry,

    pub fn init(allocator: std.mem.Allocator) LoadResult {
        return .{ .allocator = allocator, .registry = registry_mod.Registry.init(allocator) };
    }

    pub fn deinit(self: *LoadResult) void {
        self.registry.deinit();
        for (self.files.items) |*file| file.deinit();
        self.files.deinit(self.allocator);
        self.* = undefined;
    }
};

pub fn loadMemory(allocator: std.mem.Allocator, tree: *const MemorySourceTree, root_path: []const u8) Error!LoadResult {
    var result = LoadResult.init(allocator);
    errdefer result.deinit();
    var loading = std.StringHashMap(void).init(allocator);
    defer loading.deinit();
    var loaded = std.StringHashMap(void).init(allocator);
    defer loaded.deinit();
    try loadOne(allocator, tree, root_path, &result, &loading, &loaded);
    for (result.files.items) |*file| try result.registry.addFile(file);
    return result;
}

fn loadOne(
    allocator: std.mem.Allocator,
    tree: *const MemorySourceTree,
    path: []const u8,
    result: *LoadResult,
    loading: *std.StringHashMap(void),
    loaded: *std.StringHashMap(void),
) Error!void {
    if (loaded.contains(path)) return;
    if (loading.contains(path)) return error.ImportCycle;
    try loading.put(path, {});
    defer _ = loading.remove(path);

    const source = tree.get(path) orelse return error.FileNotFound;
    var file = try parser.Parser.parse(allocator, source);
    errdefer file.deinit();
    file.name = path;
    for (file.imports.items) |import| try loadOne(allocator, tree, import.path, result, loading, loaded);
    try result.files.append(allocator, file);
    try loaded.put(path, {});
}

test "memory loader recursively loads imports into registry" {
    const allocator = std.testing.allocator;
    var tree = MemorySourceTree.init(allocator);
    defer tree.deinit();
    try tree.add("common.proto",
        \\syntax = "proto3";
        \\package demo.common;
        \\message User { string name = 1; }
    );
    try tree.add("app.proto",
        \\syntax = "proto3";
        \\package demo.app;
        \\import "common.proto";
        \\message Request { demo.common.User user = 1; }
    );

    var loaded = try loadMemory(allocator, &tree, "app.proto");
    defer loaded.deinit();
    try std.testing.expectEqual(@as(usize, 2), loaded.files.items.len);
    try std.testing.expect(loaded.registry.findMessage(".demo.common.User", null) != null);
    try std.testing.expect(loaded.registry.findMessage("demo.app.Request", null) != null);
}

test "memory loader rejects missing imports and cycles" {
    const allocator = std.testing.allocator;
    var missing = MemorySourceTree.init(allocator);
    defer missing.deinit();
    try missing.add("root.proto",
        \\syntax = "proto3";
        \\import "missing.proto";
        \\message Root {}
    );
    try std.testing.expectError(error.FileNotFound, loadMemory(allocator, &missing, "root.proto"));

    var cycle = MemorySourceTree.init(allocator);
    defer cycle.deinit();
    try cycle.add("a.proto", "syntax = \"proto3\"; import \"b.proto\"; message A {}");
    try cycle.add("b.proto", "syntax = \"proto3\"; import \"a.proto\"; message B {}");
    try std.testing.expectError(error.ImportCycle, loadMemory(allocator, &cycle, "a.proto"));
}
