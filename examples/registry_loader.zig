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
        \\package demo.common;
        \\message User { int32 id = 1; }
    );
    try tree.add("custom_options.proto",
        \\syntax = "proto2";
        \\package demo.options;
    );
    try tree.add("app.proto",
        \\edition = "2024";
        \\package demo.app;
        \\option optimize_for = CODE_SIZE;
        \\option java_package = "com.example.demo";
        \\option java_multiple_files = true;
        \\option go_package = "example.com/demo;demopb";
        \\option cc_enable_arenas = true;
        \\option cc_generic_services = true;
        \\option java_generic_services = true;
        \\option py_generic_services = true;
        \\import public "common.proto";
        \\import option "custom_options.proto";
        \\message Event { demo.common.User user = 1; }
        \\service Events { rpc Get (Event) returns (Event); }
    );

    var loaded = try pbz.loadMemory(allocator, &tree, "app.proto");
    defer loaded.deinit();

    const event_desc = loaded.registry.findMessage(".demo.app.Event", null).?;
    const user_desc = loaded.registry.findMessage(".demo.common.User", null).?;
    const events_service = loaded.registry.findService(".demo.app.Events", null).?;
    const refl = pbz.Reflection.init(allocator, &loaded.registry);
    const app_file = try refl.file("app.proto");
    const common_file = try refl.file("common.proto");
    const options_file = try refl.file("custom_options.proto");
    std.debug.assert(refl.fileOptimizeFor(app_file).? == .code_size);
    std.debug.assert(std.mem.eql(u8, refl.fileJavaPackage(app_file).?, "com.example.demo"));
    std.debug.assert(refl.fileJavaMultipleFiles(app_file));
    std.debug.assert(std.mem.eql(u8, refl.fileGoPackage(app_file).?, "example.com/demo;demopb"));
    std.debug.assert(refl.fileCcEnableArenas(app_file));
    std.debug.assert(refl.fileCcGenericServices(app_file));
    std.debug.assert(refl.fileJavaGenericServices(app_file));
    std.debug.assert(refl.filePyGenericServices(app_file));
    const common_import = try refl.fileImport(app_file, "common.proto");
    std.debug.assert(std.mem.eql(u8, refl.importPath(common_import), "common.proto"));
    std.debug.assert(refl.importKind(common_import) == .public);
    std.debug.assert(refl.importIsPublic(common_import));
    std.debug.assert(!refl.importIsWeak(common_import));
    std.debug.assert(!refl.importIsOption(common_import));
    const options_import = try refl.fileImport(app_file, "custom_options.proto");
    std.debug.assert(refl.importIsOption(options_import));
    std.debug.assert(refl.fileDependencyCount(app_file) == 2);
    std.debug.assert((try refl.fileDependency(app_file, 0)) == common_file);
    std.debug.assert((try refl.fileDependency(app_file, 1)) == options_file);
    try std.testing.expectError(error.UnknownFile, refl.fileDependency(app_file, 9));
    std.debug.assert(refl.filePublicDependencyCount(app_file) == 1);
    std.debug.assert((try refl.filePublicDependency(app_file, 0)) == common_file);
    try std.testing.expectError(error.UnknownFile, refl.filePublicDependency(app_file, 9));
    std.debug.assert(refl.fileOptionDependencyCount(app_file) == 1);
    std.debug.assert((try refl.fileOptionDependency(app_file, 0)) == options_file);
    try std.testing.expectError(error.UnknownFile, refl.fileOptionDependency(app_file, 9));
    std.debug.assert(refl.fileWeakDependencyCount(app_file) == 0);
    try std.testing.expectError(error.UnknownFile, refl.fileWeakDependency(app_file, 0));
    std.debug.assert(!refl.fileHasMissingWeakImport(app_file, "common.proto"));
    std.debug.assert(refl.fileCanSee(app_file, common_file));
    const chain = (try refl.importChainByPath("app.proto", "common.proto")).?;
    std.debug.assert(refl.importChainLength(chain) == 1);
    std.debug.assert(std.mem.eql(u8, try refl.importChainPathAt(chain, 0), "common.proto"));
    std.debug.assert(std.mem.eql(u8, refl.importChainPaths(chain)[0], "common.proto"));
    try std.testing.expectError(error.UnknownFile, refl.importChainPathAt(chain, 1));
    std.debug.assert(std.mem.eql(u8, event_desc.name, "Event"));
    std.debug.assert(std.mem.eql(u8, user_desc.name, "User"));
    std.debug.assert(std.mem.eql(u8, events_service.findMethod("Get").?.name, "Get"));

    // The filesystem loader follows the same recursive import and registry
    // validation path as MemorySourceTree, but exercises the public loadDir API
    // used by build tools that already have an open source directory handle.
    const io = std.Io.Threaded.global_single_threaded.io();
    const tmp_name = ".pbz-registry-loader-example";
    const cwd = std.Io.Dir.cwd();
    cwd.deleteTree(io, tmp_name) catch {};
    var tmp_dir = try cwd.createDirPathOpen(io, tmp_name, .{});
    defer {
        tmp_dir.close(io);
        cwd.deleteTree(io, tmp_name) catch {};
    }
    try tmp_dir.writeFile(io, .{ .sub_path = "shared.proto", .data =
        \\syntax = "proto3";
        \\package fs.shared;
        \\message Payload { string label = 1; }
    });
    try tmp_dir.writeFile(io, .{ .sub_path = "root.proto", .data =
        \\syntax = "proto3";
        \\package fs.root;
        \\import "shared.proto";
        \\message Envelope { fs.shared.Payload payload = 1; }
    });

    var fs_loaded = try pbz.loadDir(allocator, tmp_dir, "root.proto");
    defer fs_loaded.deinit();
    const envelope_desc = fs_loaded.registry.findMessage(".fs.root.Envelope", null).?;
    const payload_desc = fs_loaded.registry.findMessage(".fs.shared.Payload", null).?;
    std.debug.assert(envelope_desc.findField("payload").?.kind.message.len != 0);

    const payload_ptr = try allocator.create(pbz.DynamicMessage);
    payload_ptr.* = pbz.DynamicMessage.init(allocator, payload_desc);
    errdefer {
        payload_ptr.deinit();
        allocator.destroy(payload_ptr);
    }
    try payload_ptr.add(payload_desc.findField("label").?, .{ .string = try allocator.dupe(u8, "from-dir") });
    var envelope = pbz.DynamicMessage.init(allocator, envelope_desc);
    defer envelope.deinit();
    try envelope.add(envelope_desc.findField("payload").?, .{ .message = payload_ptr });

    const root_file = fs_loaded.registry.findFile("root.proto").?;
    const json = try pbz.stringifyJsonAllocWithRegistry(allocator, root_file, &fs_loaded.registry, &envelope, .{});
    defer allocator.free(json);
    std.debug.assert(std.mem.indexOf(u8, json, "\"from-dir\"") != null);

    var generated_file = pbz.FileDescriptor.init(allocator);
    defer generated_file.deinit();
    generated_file.setSyntax(.proto3);
    generated_file.package = "generated";
    try generated_file.enums.append(allocator, .{ .name = "Status" });
    try generated_file.enums.items[0].values.append(allocator, .{ .name = "Payload", .number = 0 });

    var conflicting_file = pbz.FileDescriptor.init(allocator);
    defer conflicting_file.deinit();
    conflicting_file.setSyntax(.proto3);
    conflicting_file.package = "generated";
    try conflicting_file.messages.append(allocator, .{ .name = "Payload" });

    var checked_registry = pbz.Registry.init(allocator);
    defer checked_registry.deinit();
    try checked_registry.addFile(&generated_file);
    // The registry is also the safety net for descriptors assembled directly in
    // Zig (or decoded from descriptor sets), where the text parser's local
    // duplicate-symbol checks did not run.  C++ DescriptorPool rejects this
    // file-level collision because enum values share their parent scope.
    try std.testing.expectError(error.DuplicateSymbol, checked_registry.addFile(&conflicting_file));
}
