const std = @import("std");
const schema = @import("schema.zig");
const parser = @import("parser.zig");
const registry_mod = @import("registry.zig");

pub const Error = std.mem.Allocator.Error || parser.Error || registry_mod.Error || error{ FileNotFound, ImportCycle };

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
    owned_sources: std.ArrayList([]u8) = .empty,

    pub fn init(allocator: std.mem.Allocator) LoadResult {
        return .{ .allocator = allocator, .registry = registry_mod.Registry.init(allocator) };
    }

    pub fn deinit(self: *LoadResult) void {
        self.registry.deinit();
        for (self.files.items) |*file| file.deinit();
        self.files.deinit(self.allocator);
        for (self.owned_sources.items) |source| self.allocator.free(source);
        self.owned_sources.deinit(self.allocator);
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
    try result.registry.validateAllFileReferences();
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
    for (file.imports.items) |import| {
        loadOne(allocator, tree, import.path, result, loading, loaded) catch |err| switch (err) {
            error.FileNotFound => if (import.kind == .weak) continue else return err,
            else => return err,
        };
    }
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

test "memory loader allows missing weak imports" {
    const allocator = std.testing.allocator;
    var tree = MemorySourceTree.init(allocator);
    defer tree.deinit();
    try tree.add("root.proto",
        \\syntax = "proto2";
        \\import weak "missing.proto";
        \\message Root { optional int32 id = 1; }
    );

    var loaded = try loadMemory(allocator, &tree, "root.proto");
    defer loaded.deinit();
    try std.testing.expectEqual(@as(usize, 1), loaded.files.items.len);
    try std.testing.expectEqual(schema.Import.Kind.weak, loaded.files.items[0].imports.items[0].kind);
    try std.testing.expect(loaded.registry.findMessage("Root", null) != null);
}

pub fn loadPath(allocator: std.mem.Allocator, root_dir_path: []const u8, root_path: []const u8) Error!LoadResult {
    const io = std.Io.Threaded.global_single_threaded.io();
    const root_dir = std.fs.openDirAbsolute(io, root_dir_path, .{}) catch return error.FileNotFound;
    defer root_dir.close(io);
    return try loadDir(allocator, root_dir, root_path);
}

pub fn loadDir(allocator: std.mem.Allocator, root_dir: std.Io.Dir, root_path: []const u8) Error!LoadResult {
    var result = LoadResult.init(allocator);
    errdefer result.deinit();
    var loading = std.StringHashMap(void).init(allocator);
    defer loading.deinit();
    var loaded = std.StringHashMap(void).init(allocator);
    defer loaded.deinit();
    try loadDirOne(allocator, root_dir, root_path, &result, &loading, &loaded);
    for (result.files.items) |*file| try result.registry.addFile(file);
    try result.registry.validateAllFileReferences();
    return result;
}

fn loadDirOne(
    allocator: std.mem.Allocator,
    root_dir: std.Io.Dir,
    path: []const u8,
    result: *LoadResult,
    loading: *std.StringHashMap(void),
    loaded: *std.StringHashMap(void),
) Error!void {
    if (loaded.contains(path)) return;
    if (loading.contains(path)) return error.ImportCycle;
    try loading.put(path, {});
    defer _ = loading.remove(path);

    const io = std.Io.Threaded.global_single_threaded.io();
    const source = root_dir.readFileAlloc(io, path, allocator, .limited(16 * 1024 * 1024)) catch return error.FileNotFound;
    var source_owned = false;
    errdefer if (!source_owned) allocator.free(source);

    var file = try parser.Parser.parse(allocator, source);
    errdefer file.deinit();
    file.name = path;
    try result.owned_sources.append(allocator, source);
    source_owned = true;
    for (file.imports.items) |import| {
        loadDirOne(allocator, root_dir, import.path, result, loading, loaded) catch |err| switch (err) {
            error.FileNotFound => if (import.kind == .weak) continue else return err,
            else => return err,
        };
    }
    try result.files.append(allocator, file);
    try loaded.put(path, {});
}

test "filesystem loader recursively loads imports" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const io = std.Io.Threaded.global_single_threaded.io();
    try tmp.dir.writeFile(io, .{ .sub_path = "common.proto", .data =
        \\syntax = "proto3";
        \\package fs.common;
        \\message User { string name = 1; }
    });
    try tmp.dir.writeFile(io, .{ .sub_path = "app.proto", .data =
        \\syntax = "proto3";
        \\package fs.app;
        \\import "common.proto";
        \\message Request { fs.common.User user = 1; }
    });
    var loaded = try loadDir(allocator, tmp.dir, "app.proto");
    defer loaded.deinit();
    try std.testing.expectEqual(@as(usize, 2), loaded.files.items.len);
    try std.testing.expect(loaded.registry.findMessage(".fs.common.User", null) != null);
    try std.testing.expect(loaded.registry.findMessage(".fs.app.Request", null) != null);
}

test "filesystem loader allows missing weak imports" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const io = std.Io.Threaded.global_single_threaded.io();
    try tmp.dir.writeFile(io, .{ .sub_path = "root.proto", .data =
        \\syntax = "proto2";
        \\import weak "missing.proto";
        \\message Root { optional int32 id = 1; }
    });

    var loaded = try loadDir(allocator, tmp.dir, "root.proto");
    defer loaded.deinit();
    try std.testing.expectEqual(@as(usize, 1), loaded.files.items.len);
    try std.testing.expectEqual(schema.Import.Kind.weak, loaded.files.items[0].imports.items[0].kind);
    try std.testing.expect(loaded.registry.findMessage("Root", null) != null);
}
