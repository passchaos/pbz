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

pub const LoadOptions = struct {
    /// Reject custom options whose `(extension)` name does not resolve to a
    /// declared extension of the matching Options message, matching protoc.
    /// Off by default because pbz deliberately preserves uninterpreted options
    /// for tooling that does not interpret them.
    validate_custom_options: bool = false,
};

pub fn loadMemory(allocator: std.mem.Allocator, tree: *const MemorySourceTree, root_path: []const u8) Error!LoadResult {
    return loadMemoryWithOptions(allocator, tree, root_path, .{});
}

pub fn loadMemoryWithOptions(allocator: std.mem.Allocator, tree: *const MemorySourceTree, root_path: []const u8, options: LoadOptions) Error!LoadResult {
    var result = LoadResult.init(allocator);
    errdefer result.deinit();
    var loading = std.StringHashMap(void).init(allocator);
    defer loading.deinit();
    var loaded = std.StringHashMap(void).init(allocator);
    defer loaded.deinit();
    try loadOne(allocator, tree, root_path, &result, &loading, &loaded);
    for (result.files.items) |*file| try result.registry.addFile(file);
    try result.registry.validateAllFileReferences();
    if (options.validate_custom_options) try result.registry.validateAllCustomOptions();
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
    var owns_file = true;
    errdefer if (owns_file) file.deinit();
    file.name = path;
    for (file.imports.items) |import| {
        loadOne(allocator, tree, import.path, result, loading, loaded) catch |err| switch (err) {
            error.FileNotFound => if (import.kind == .weak) {
                try file.missing_weak_imports.append(allocator, import.path);
                continue;
            } else return err,
            else => return err,
        };
    }
    try result.files.append(allocator, file);
    owns_file = false;
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

fn exerciseMemoryLoadCleanup(allocator: std.mem.Allocator, tree: *const MemorySourceTree) !void {
    var loaded = try loadMemory(allocator, tree, "app.proto");
    defer loaded.deinit();
    try std.testing.expectEqual(@as(usize, 2), loaded.files.items.len);
    try std.testing.expect(loaded.registry.findMessage(".demo.common.User", null) != null);
    try std.testing.expect(loaded.registry.findMessage("demo.app.Request", null) != null);
}

test "memory loader cleans up allocation failures" {
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

    try std.testing.checkAllAllocationFailures(allocator, exerciseMemoryLoadCleanup, .{&tree});
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
        \\message Root { optional MissingType weak_field = 1; }
    );

    var loaded = try loadMemory(allocator, &tree, "root.proto");
    defer loaded.deinit();
    try std.testing.expectEqual(@as(usize, 1), loaded.files.items.len);
    try std.testing.expectEqual(schema.Import.Kind.weak, loaded.files.items[0].imports.items[0].kind);
    try std.testing.expectEqual(@as(usize, 1), loaded.files.items[0].missing_weak_imports.items.len);
    try std.testing.expectEqualStrings("missing.proto", loaded.files.items[0].missing_weak_imports.items[0]);
    try std.testing.expect(loaded.registry.findMessage("Root", null) != null);
}

test "memory loader enforces editions local symbol visibility" {
    const allocator = std.testing.allocator;
    var tree = MemorySourceTree.init(allocator);
    defer tree.deinit();
    try tree.add("a.proto",
        \\edition = "2024";
        \\package v;
        \\option features.default_symbol_visibility = LOCAL_ALL;
        \\message A { int32 x = 1; }
        \\message C { A a = 1; }
    );
    try tree.add("b.proto",
        \\edition = "2024";
        \\package w;
        \\import "a.proto";
        \\message B { v.A a = 1; }
    );
    try std.testing.expectError(error.InvalidFieldType, loadMemory(allocator, &tree, "b.proto"));
    // Same-file references remain valid under LOCAL_ALL.
    var same_file = try loadMemory(allocator, &tree, "a.proto");
    defer same_file.deinit();
}

test "memory loader optionally validates custom options" {
    const allocator = std.testing.allocator;
    var tree = MemorySourceTree.init(allocator);
    defer tree.deinit();
    try tree.add("descriptor.proto",
        \\syntax = "proto2";
        \\package google.protobuf;
        \\message FileOptions { extensions 1000 to max; }
        \\message MessageOptions { extensions 1000 to max; }
        \\message FieldOptions { extensions 1000 to max; }
        \\message FeatureSet { extensions 1000 to 9994; }
    );
    try tree.add("opts.proto",
        \\syntax = "proto2";
        \\package demo;
        \\import "descriptor.proto";
        \\extend google.protobuf.FileOptions { optional string file_note = 50000; }
        \\extend google.protobuf.FieldOptions { optional Meta meta = 50001; }
        \\message Meta {
        \\  optional string label = 1;
        \\  optional Inner inner = 2;
        \\}
        \\message Inner { optional int32 leaf = 1; }
    );
    try tree.add("features.proto",
        \\syntax = "proto2";
        \\package pb;
        \\import "descriptor.proto";
        \\extend google.protobuf.FeatureSet { optional CppFeatures cpp = 1000; }
        \\message CppFeatures { optional bool legacy_closed_enum = 1; }
    );
    try tree.add("use.proto",
        \\edition = "2023";
        \\package demo;
        \\import "opts.proto";
        \\import "features.proto";
        \\option (demo.file_note) = "x";
        \\message M {
        \\  int32 x = 1 [(demo.meta).inner.leaf = 7];
        \\  string s = 2 [features.(pb.cpp).legacy_closed_enum = true];
        \\}
    );
    var loaded = try loadMemoryWithOptions(allocator, &tree, "use.proto", .{ .validate_custom_options = true });
    defer loaded.deinit();

    // Default loaders keep uninterpreted options working.
    var permissive = try loadMemory(allocator, &tree, "use.proto");
    defer permissive.deinit();

    var unknown_tree = MemorySourceTree.init(allocator);
    defer unknown_tree.deinit();
    try unknown_tree.add("bad.proto",
        \\edition = "2023";
        \\package demo;
        \\message M { int32 x = 1 [(foo.bar) = 1]; }
    );
    try std.testing.expectError(error.UnknownOption, loadMemoryWithOptions(allocator, &unknown_tree, "bad.proto", .{ .validate_custom_options = true }));
    var permissive_bad = try loadMemory(allocator, &unknown_tree, "bad.proto");
    defer permissive_bad.deinit();

    // Unknown feature sub-fields and mismatched option targets are rejected.
    var bad_field_tree = MemorySourceTree.init(allocator);
    defer bad_field_tree.deinit();
    try bad_field_tree.add("descriptor.proto", "syntax = \"proto2\";\npackage google.protobuf;\nmessage FileOptions { extensions 1000 to max; }\nmessage FieldOptions { extensions 1000 to max; }\nmessage FeatureSet { extensions 1000 to 9994; }\n");
    try bad_field_tree.add("features.proto",
        \\syntax = "proto2";
        \\package pb;
        \\import "descriptor.proto";
        \\extend google.protobuf.FeatureSet { optional CppFeatures cpp = 1000; }
        \\extend google.protobuf.FileOptions { optional string note = 1001; }
        \\message CppFeatures { optional bool legacy_closed_enum = 1; }
    );
    try bad_field_tree.add("bad_use.proto",
        \\edition = "2023";
        \\package demo;
        \\import "features.proto";
        \\message M { string s = 1 [features.(pb.cpp).bogus = true]; }
    );
    try std.testing.expectError(error.UnknownOption, loadMemoryWithOptions(allocator, &bad_field_tree, "bad_use.proto", .{ .validate_custom_options = true }));

    var wrong_target_tree = MemorySourceTree.init(allocator);
    defer wrong_target_tree.deinit();
    try wrong_target_tree.add("descriptor.proto", "syntax = \"proto2\";\npackage google.protobuf;\nmessage FileOptions { extensions 1000 to max; }\nmessage FieldOptions { extensions 1000 to max; }\n");
    try wrong_target_tree.add("opts2.proto",
        \\syntax = "proto2";
        \\package demo;
        \\import "descriptor.proto";
        \\extend google.protobuf.FileOptions { optional string file_note = 50000; }
    );
    try wrong_target_tree.add("wrong_use.proto",
        \\edition = "2023";
        \\package demo;
        \\import "opts2.proto";
        \\message M { int32 x = 1 [(demo.file_note) = "x"]; }
    );
    try std.testing.expectError(error.UnknownOption, loadMemoryWithOptions(allocator, &wrong_target_tree, "wrong_use.proto", .{ .validate_custom_options = true }));

    // Plain option names must be built-ins; `features` and aggregate
    // sub-field assignments stay valid.
    var plain_tree = MemorySourceTree.init(allocator);
    defer plain_tree.deinit();
    try plain_tree.add("plain_bad.proto",
        \\edition = "2023";
        \\package demo;
        \\option go_api_flag = "X";
        \\message M { int32 x = 1; }
    );
    try std.testing.expectError(error.UnknownOption, loadMemoryWithOptions(allocator, &plain_tree, "plain_bad.proto", .{ .validate_custom_options = true }));
    var plain_ok = try loadMemory(allocator, &plain_tree, "plain_bad.proto");
    defer plain_ok.deinit();

    var aggregate_tree = MemorySourceTree.init(allocator);
    defer aggregate_tree.deinit();
    try aggregate_tree.add("aggregate.proto",
        \\edition = "2023";
        \\package demo;
        \\option features = { enum_type: CLOSED };
        \\message M {
        \\  int32 x = 1 [feature_support.edition_introduced = EDITION_2023];
        \\}
    );
    var aggregate = try loadMemoryWithOptions(allocator, &aggregate_tree, "aggregate.proto", .{ .validate_custom_options = true });
    defer aggregate.deinit();
}

test "memory loader honors explicit local and export visibility modifiers" {
    const allocator = std.testing.allocator;

    var hidden_tree = MemorySourceTree.init(allocator);
    defer hidden_tree.deinit();
    try hidden_tree.add("a.proto",
        \\edition = "2024";
        \\package v;
        \\local message Hidden { int32 x = 1; }
        \\message Outer { export message Inner { int32 y = 1; } }
    );
    try hidden_tree.add("b.proto",
        \\edition = "2024";
        \\package w;
        \\import "a.proto";
        \\message B { v.Hidden h = 1; }
    );
    try std.testing.expectError(error.InvalidFieldType, loadMemory(allocator, &hidden_tree, "b.proto"));

    // An exported nested type is visible even when its parent stays local.
    var export_tree = MemorySourceTree.init(allocator);
    defer export_tree.deinit();
    try export_tree.add("c.proto",
        \\edition = "2024";
        \\package v;
        \\message Outer { export message Inner { int32 y = 1; } }
    );
    try export_tree.add("d.proto",
        \\edition = "2024";
        \\package w;
        \\import "c.proto";
        \\message B { v.Outer.Inner i = 1; }
    );
    var exported = try loadMemory(allocator, &export_tree, "d.proto");
    defer exported.deinit();

    // `export` overrides LOCAL_ALL for top-level declarations.
    var override_tree = MemorySourceTree.init(allocator);
    defer override_tree.deinit();
    try override_tree.add("e.proto",
        \\edition = "2024";
        \\package v;
        \\option features.default_symbol_visibility = LOCAL_ALL;
        \\export message Visible { int32 x = 1; }
    );
    try override_tree.add("f.proto",
        \\edition = "2024";
        \\package w;
        \\import "e.proto";
        \\message B { v.Visible visible = 1; }
    );
    var overridden = try loadMemory(allocator, &override_tree, "f.proto");
    defer overridden.deinit();
}

test "memory loader enforces editions enum and strict visibility" {
    const allocator = std.testing.allocator;
    var enum_tree = MemorySourceTree.init(allocator);
    defer enum_tree.deinit();
    try enum_tree.add("a.proto",
        \\edition = "2024";
        \\package v;
        \\option features.default_symbol_visibility = LOCAL_ALL;
        \\enum E { E_UNKNOWN = 0; }
    );
    try enum_tree.add("b.proto",
        \\edition = "2024";
        \\package w;
        \\import "a.proto";
        \\message B { v.E e = 1; }
    );
    try std.testing.expectError(error.InvalidFieldType, loadMemory(allocator, &enum_tree, "b.proto"));

    var strict_tree = MemorySourceTree.init(allocator);
    defer strict_tree.deinit();
    try strict_tree.add("a.proto",
        \\edition = "2024";
        \\package v;
        \\option features.default_symbol_visibility = STRICT;
        \\message A { int32 x = 1; }
    );
    try strict_tree.add("b.proto",
        \\edition = "2024";
        \\package w;
        \\import "a.proto";
        \\message B { v.A a = 1; }
    );
    try std.testing.expectError(error.InvalidFieldType, loadMemory(allocator, &strict_tree, "b.proto"));
}

test "memory loader enforces editions top-level symbol visibility" {
    const allocator = std.testing.allocator;
    var top_tree = MemorySourceTree.init(allocator);
    defer top_tree.deinit();
    try top_tree.add("a.proto",
        \\edition = "2024";
        \\package v;
        \\option features.default_symbol_visibility = EXPORT_TOP_LEVEL;
        \\message A { message N { int32 y = 1; } int32 x = 1; }
    );
    try top_tree.add("b.proto",
        \\edition = "2024";
        \\package w;
        \\import "a.proto";
        \\message B { v.A a = 1; }
    );
    var top_loaded = try loadMemory(allocator, &top_tree, "b.proto");
    defer top_loaded.deinit();

    var nested_tree = MemorySourceTree.init(allocator);
    defer nested_tree.deinit();
    try nested_tree.add("a.proto",
        \\edition = "2024";
        \\package v;
        \\option features.default_symbol_visibility = EXPORT_TOP_LEVEL;
        \\message A { message N { int32 y = 1; } int32 x = 1; }
    );
    try nested_tree.add("b.proto",
        \\edition = "2024";
        \\package w;
        \\import "a.proto";
        \\message B { v.A.N n = 1; }
    );
    try std.testing.expectError(error.InvalidFieldType, loadMemory(allocator, &nested_tree, "b.proto"));
}

test "memory loader rejects unresolved type references" {
    const allocator = std.testing.allocator;
    var tree = MemorySourceTree.init(allocator);
    defer tree.deinit();
    try tree.add("root.proto",
        \\syntax = "proto2";
        \\message Root { optional MissingType field = 1; }
    );
    try std.testing.expectError(error.InvalidFieldType, loadMemory(allocator, &tree, "root.proto"));
}

test "memory loader does not resolve unqualified imported leaf types" {
    const allocator = std.testing.allocator;
    var tree = MemorySourceTree.init(allocator);
    defer tree.deinit();
    try tree.add("common.proto",
        \\syntax = "proto2";
        \\package common;
        \\message User { optional string name = 1; }
    );
    try tree.add("app.proto",
        \\syntax = "proto2";
        \\package app;
        \\import "common.proto";
        \\message Event { optional User user = 1; }
    );
    try std.testing.expectError(error.InvalidFieldType, loadMemory(allocator, &tree, "app.proto"));
}

test "memory loader resolves qualified imported type references" {
    const allocator = std.testing.allocator;
    var tree = MemorySourceTree.init(allocator);
    defer tree.deinit();
    try tree.add("common.proto",
        \\syntax = "proto2";
        \\package common;
        \\message User { optional string name = 1; }
    );
    try tree.add("app.proto",
        \\syntax = "proto2";
        \\package app;
        \\import "common.proto";
        \\message Event {
        \\  optional common.User relative = 1;
        \\  optional .common.User absolute = 2;
        \\}
    );

    var loaded = try loadMemory(allocator, &tree, "app.proto");
    defer loaded.deinit();
    const app = loaded.registry.findFile("app.proto").?;
    try std.testing.expect(loaded.registry.findMessageVisible(app, "common.User", "app.Event") != null);
    try std.testing.expect(loaded.registry.findMessageVisible(app, ".common.User", "app.Event") != null);
}

test "memory loader resolves same-package extension extendees" {
    const allocator = std.testing.allocator;
    var tree = MemorySourceTree.init(allocator);
    defer tree.deinit();
    try tree.add("host.proto",
        \\syntax = "proto2";
        \\package demo;
        \\message Host { extensions 100 to max; }
        \\message Scope { message Nested { extensions 100 to max; } }
    );
    try tree.add("extension.proto",
        \\syntax = "proto2";
        \\package demo;
        \\import "host.proto";
        \\extend Host { optional string note = 100; }
        \\message ExtScope { extend Scope.Nested { optional int32 nested_note = 100; } }
    );

    var loaded = try loadMemory(allocator, &tree, "extension.proto");
    defer loaded.deinit();
    try std.testing.expect(loaded.registry.findExtension(".demo.Host", 100) != null);
    try std.testing.expect(loaded.registry.findExtension(".demo.Scope.Nested", 100) != null);
}

test "memory loader rejects unresolved service method types" {
    const allocator = std.testing.allocator;
    var tree = MemorySourceTree.init(allocator);
    defer tree.deinit();
    try tree.add("root.proto",
        \\syntax = "proto2";
        \\message Root {}
        \\service Api { rpc Get (MissingRequest) returns (Root); }
    );
    try std.testing.expectError(error.InvalidFieldType, loadMemory(allocator, &tree, "root.proto"));
}

test "memory loader resolves imported enum defaults" {
    const allocator = std.testing.allocator;
    var tree = MemorySourceTree.init(allocator);
    defer tree.deinit();
    try tree.add("common.proto",
        \\syntax = "proto2";
        \\package common;
        \\enum Kind { UNKNOWN = 0; ADMIN = 7; }
    );
    try tree.add("app.proto",
        \\syntax = "proto2";
        \\package app;
        \\import "common.proto";
        \\message Event {
        \\  optional common.Kind kind = 1 [default = ADMIN];
        \\}
    );

    var loaded = try loadMemory(allocator, &tree, "app.proto");
    defer loaded.deinit();
    const app = loaded.registry.findFile("app.proto").?;
    const event = app.findMessage("Event").?;
    const field = event.findField("kind").?;
    try std.testing.expectEqualStrings("ADMIN", field.default_value.?.identifier);

    try tree.add("bad.proto",
        \\syntax = "proto2";
        \\package app;
        \\import "common.proto";
        \\message Bad {
        \\  optional common.Kind kind = 1 [default = MISSING];
        \\}
    );
    try std.testing.expectError(error.InvalidFieldType, loadMemory(allocator, &tree, "bad.proto"));
}

pub fn loadPath(allocator: std.mem.Allocator, root_dir_path: []const u8, root_path: []const u8) Error!LoadResult {
    return loadPathWithOptions(allocator, root_dir_path, root_path, .{});
}

pub fn loadPathWithOptions(allocator: std.mem.Allocator, root_dir_path: []const u8, root_path: []const u8, options: LoadOptions) Error!LoadResult {
    const io = std.Io.Threaded.global_single_threaded.io();
    const root_dir = std.fs.openDirAbsolute(io, root_dir_path, .{}) catch return error.FileNotFound;
    defer root_dir.close(io);
    return try loadDirWithOptions(allocator, root_dir, root_path, options);
}

pub fn loadDir(allocator: std.mem.Allocator, root_dir: std.Io.Dir, root_path: []const u8) Error!LoadResult {
    return loadDirWithOptions(allocator, root_dir, root_path, .{});
}

pub fn loadDirWithOptions(allocator: std.mem.Allocator, root_dir: std.Io.Dir, root_path: []const u8, options: LoadOptions) Error!LoadResult {
    var result = LoadResult.init(allocator);
    errdefer result.deinit();
    var loading = std.StringHashMap(void).init(allocator);
    defer loading.deinit();
    var loaded = std.StringHashMap(void).init(allocator);
    defer loaded.deinit();
    try loadDirOne(allocator, root_dir, root_path, &result, &loading, &loaded);
    for (result.files.items) |*file| try result.registry.addFile(file);
    try result.registry.validateAllFileReferences();
    if (options.validate_custom_options) try result.registry.validateAllCustomOptions();
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
    const source = root_dir.readFileAlloc(io, path, allocator, .limited(16 * 1024 * 1024)) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.FileNotFound,
    };
    var source_owned = false;
    errdefer if (!source_owned) allocator.free(source);

    var file = try parser.Parser.parse(allocator, source);
    var owns_file = true;
    errdefer if (owns_file) file.deinit();
    file.name = path;
    try result.owned_sources.append(allocator, source);
    source_owned = true;
    for (file.imports.items) |import| {
        loadDirOne(allocator, root_dir, import.path, result, loading, loaded) catch |err| switch (err) {
            error.FileNotFound => if (import.kind == .weak) {
                try file.missing_weak_imports.append(allocator, import.path);
                continue;
            } else return err,
            else => return err,
        };
    }
    try result.files.append(allocator, file);
    owns_file = false;
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

fn exerciseDirLoadCleanup(allocator: std.mem.Allocator, root_dir: std.Io.Dir) !void {
    var loaded = try loadDir(allocator, root_dir, "app.proto");
    defer loaded.deinit();
    try std.testing.expectEqual(@as(usize, 2), loaded.files.items.len);
    try std.testing.expect(loaded.registry.findMessage(".fs.common.User", null) != null);
    try std.testing.expect(loaded.registry.findMessage(".fs.app.Request", null) != null);
}

test "filesystem loader cleans up allocation failures" {
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
    try std.testing.checkAllAllocationFailures(allocator, exerciseDirLoadCleanup, .{tmp.dir});
}

test "filesystem loader allows missing weak imports" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const io = std.Io.Threaded.global_single_threaded.io();
    try tmp.dir.writeFile(io, .{ .sub_path = "root.proto", .data =
        \\syntax = "proto2";
        \\import weak "missing.proto";
        \\message Root { optional MissingType weak_field = 1; }
    });

    var loaded = try loadDir(allocator, tmp.dir, "root.proto");
    defer loaded.deinit();
    try std.testing.expectEqual(@as(usize, 1), loaded.files.items.len);
    try std.testing.expectEqual(schema.Import.Kind.weak, loaded.files.items[0].imports.items[0].kind);
    try std.testing.expectEqual(@as(usize, 1), loaded.files.items[0].missing_weak_imports.items.len);
    try std.testing.expectEqualStrings("missing.proto", loaded.files.items[0].missing_weak_imports.items[0]);
    try std.testing.expect(loaded.registry.findMessage("Root", null) != null);
}
