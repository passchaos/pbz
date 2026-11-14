const schema = @import("schema.zig");
const std = @import("std");
const wire = @import("wire.zig");
const module = @import("registry.zig");
const Registry = module.Registry;

test "registry resolves absolute relative nested and imported types" {
    const allocator = std.testing.allocator;
    var common = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package demo.common;
        \\message User { message Profile { string name = 1; } enum Role { UNKNOWN = 0; ADMIN = 1; } }
    );
    defer common.deinit();
    var app = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package demo.app;
        \\import "common.proto";
        \\message Request { demo.common.User user = 1; .demo.common.User.Profile profile = 2; }
        \\service Requests { rpc Get (Request) returns (Request); }
    );
    defer app.deinit();

    var registry = Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);

    try std.testing.expect(registry.findMessage(".demo.common.User", null) != null);
    try std.testing.expect(registry.findMessage("User.Profile", "demo.common") != null);
    try std.testing.expect(registry.findEnum("Role", "demo.common.User") != null);
    try std.testing.expect(registry.findMessage("Request", "demo.app") != null);
    try std.testing.expect(registry.findMessage("demo.common.User", "demo.app.Request") != null);
    try std.testing.expect(registry.findService(".demo.app.Requests", null) != null);
    try std.testing.expect(registry.findService("Requests", "demo.app") != null);
    try std.testing.expect(registry.findService("Requests", "demo.common") == null);
    try std.testing.expect(registry.findService(".demo.app.Requests", null).?.findMethod("Get") != null);
}

test "registry rejects unqualified imported leaf references" {
    const allocator = std.testing.allocator;
    var common = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package common;
        \\message User { optional string name = 1; }
    );
    defer common.deinit();
    common.name = "common.proto";
    var app = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package app;
        \\import "common.proto";
        \\message Event { optional User user = 1; optional common.User qualified = 2; }
    );
    defer app.deinit();
    app.name = "app.proto";

    var registry = Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);

    try std.testing.expect(registry.findMessageVisible(&app, "common.User", "app.Event") != null);
    try std.testing.expect(registry.findMessageVisible(&app, "User", "app.Event") == null);
    try std.testing.expectError(error.InvalidFieldType, registry.validateFileReferences(&app));

    var qualified = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package app;
        \\import "common.proto";
        \\message QualifiedEvent { optional common.User relative = 1; optional .common.User absolute = 2; }
    );
    defer qualified.deinit();
    qualified.name = "qualified.proto";
    try registry.addFile(&qualified);
    try registry.validateFileReferences(&qualified);
}

test "registry resolves same-package and scoped extension extendees" {
    const allocator = std.testing.allocator;
    var host = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host { extensions 100 to max; }
        \\message Scope {
        \\  message Nested { extensions 100 to max; }
        \\}
    );
    defer host.deinit();
    host.name = "host.proto";
    var extension = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\import "host.proto";
        \\extend Host { optional string note = 100; }
        \\message ExtScope {
        \\  extend Scope.Nested { optional int32 nested_note = 100; }
        \\}
    );
    defer extension.deinit();
    extension.name = "extension.proto";

    var registry = Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&host);
    try registry.addFile(&extension);
    try registry.validateFileReferences(&extension);

    const host_desc = registry.findMessage(".demo.Host", null).?;
    try std.testing.expect(registry.findExtension(".demo.Host", 100) != null);
    try std.testing.expect(registry.findFileContainingExtension(".demo.Host", 100).? == &extension);
    try std.testing.expect(registry.findFileContainingExtensionForMessage(host_desc, 100).? == &extension);
    try std.testing.expect(registry.findExtension(".demo.Scope.Nested", 100) != null);
    try std.testing.expect(registry.findFileContainingExtension(".demo.Scope.Nested", 100).? == &extension);
    try std.testing.expect(registry.findFileContainingExtension(".demo.Host", 101) == null);
}

test "registry computes direct and public import chains" {
    const allocator = std.testing.allocator;
    var leaf = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.leaf;
        \\message User { optional string name = 1; }
        \\enum Kind { A = 0; }
    );
    defer leaf.deinit();
    leaf.name = "leaf.proto";
    var leaf2 = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.leaf2;
        \\message PrivateUser { optional string name = 1; }
    );
    defer leaf2.deinit();
    leaf2.name = "leaf2.proto";
    var bridge = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.bridge;
        \\import public "leaf.proto";
        \\message Bridge {}
    );
    defer bridge.deinit();
    bridge.name = "bridge.proto";
    var private_bridge = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.private_bridge;
        \\import "leaf2.proto";
        \\message PrivateBridge {}
    );
    defer private_bridge.deinit();
    private_bridge.name = "private.proto";
    var app = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.app;
        \\import "bridge.proto";
        \\import "private.proto";
        \\message App { optional demo.leaf.User user = 1; }
        \\service Api { rpc Get (demo.leaf.User) returns (App); }
    );
    defer app.deinit();
    app.name = "app.proto";

    var registry = Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&leaf);
    try registry.addFile(&leaf2);
    try registry.addFile(&bridge);
    try registry.addFile(&private_bridge);
    try registry.addFile(&app);

    const direct = registry.importChain(&app, &bridge).?;
    try std.testing.expectEqual(@as(usize, 1), direct.len);
    try std.testing.expectEqualStrings("bridge.proto", direct.paths[0]);

    const public_chain = registry.importChain(&app, &leaf).?;
    try std.testing.expectEqual(@as(usize, 2), public_chain.len);
    try std.testing.expectEqualStrings("bridge.proto", public_chain.paths[0]);
    try std.testing.expectEqualStrings("leaf.proto", public_chain.paths[1]);

    try std.testing.expect(registry.importChain(&app, &leaf2) == null);
    try registry.validateAllFileReferences();

    var bad = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.bad;
        \\import "private.proto";
        \\message Bad { optional demo.leaf2.PrivateUser user = 1; }
    );
    defer bad.deinit();
    bad.name = "bad.proto";
    try registry.addFile(&bad);
    try std.testing.expectError(error.InvalidFieldType, registry.validateFileReferences(&bad));

    var missing = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.missing;
        \\message Bad { optional MissingType field = 1; }
    );
    defer missing.deinit();
    missing.name = "missing.proto";
    try registry.addFile(&missing);
    try std.testing.expectError(error.InvalidFieldType, registry.validateFileReferences(&missing));

    var bad_service = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.badsvc;
        \\import "bridge.proto";
        \\service BadEnum { rpc Get (demo.leaf.Kind) returns (demo.leaf.User); }
    );
    defer bad_service.deinit();
    bad_service.name = "bad-service.proto";
    try registry.addFile(&bad_service);
    try std.testing.expectError(error.InvalidFieldType, registry.validateFileReferences(&bad_service));

    var missing_service = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.missingsvc;
        \\service Missing { rpc Get (MissingRequest) returns (MissingResponse); }
    );
    defer missing_service.deinit();
    missing_service.name = "missing-service.proto";
    try registry.addFile(&missing_service);
    try std.testing.expectError(error.InvalidFieldType, registry.validateFileReferences(&missing_service));
}

test "registry finds extension fields" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host { extensions 100 to max; }
        \\extend Host { optional string note = 100; }
        \\message Scope { extend Host { optional string scoped_note = 101; } }
    );
    defer file.deinit();
    var registry = Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);
    const ext = registry.findExtension(".demo.Host", 100).?;
    try std.testing.expectEqualStrings("note", ext.name);
    const scoped = registry.findExtensionByName(".demo.Host", "demo.Scope.scoped_note").?;
    try std.testing.expectEqual(@as(wire.FieldNumber, 101), scoped.number);
    try std.testing.expectEqualStrings("demo.Scope.scoped_note", scoped.full_name.?);
}

test "registry rejects duplicate type symbols across files" {
    const allocator = std.testing.allocator;
    var first = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package demo;
        \\message User { message Profile {} }
    );
    defer first.deinit();
    var duplicate_message = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package demo;
        \\message User {}
    );
    defer duplicate_message.deinit();
    var duplicate_nested = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package demo;
        \\message User { enum Profile { UNKNOWN = 0; } }
    );
    defer duplicate_nested.deinit();

    var registry = Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&first);
    try std.testing.expectError(error.DuplicateSymbol, registry.addFile(&duplicate_message));
    try std.testing.expectError(error.DuplicateSymbol, registry.addFile(&duplicate_nested));
}

test "registry rejects duplicate service symbols across files" {
    const allocator = std.testing.allocator;
    var first = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package demo;
        \\message Req {}
        \\service Same { rpc Get (Req) returns (Req); }
    );
    defer first.deinit();
    first.name = "first.proto";
    var duplicate_service = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package demo;
        \\message Res {}
        \\service Same { rpc Get (Res) returns (Res); }
    );
    defer duplicate_service.deinit();
    duplicate_service.name = "duplicate-service.proto";
    var duplicate_message = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package demo;
        \\message Same {}
    );
    defer duplicate_message.deinit();
    duplicate_message.name = "duplicate-message.proto";

    var registry = Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&first);
    try std.testing.expectError(error.DuplicateSymbol, registry.addFile(&duplicate_service));
    try std.testing.expectError(error.DuplicateSymbol, registry.addFile(&duplicate_message));
}

test "registry rejects descriptor symbols not produced by parser validation" {
    const allocator = std.testing.allocator;
    var enum_file = schema.FileDescriptor.init(allocator);
    defer enum_file.deinit();
    enum_file.setSyntax(.proto3);
    enum_file.package = "demo";
    try enum_file.enums.append(allocator, .{ .name = "Status" });
    try enum_file.enums.items[0].values.append(allocator, .{ .name = "Payload", .number = 0 });

    var message_file = schema.FileDescriptor.init(allocator);
    defer message_file.deinit();
    message_file.setSyntax(.proto3);
    message_file.package = "demo";
    try message_file.messages.append(allocator, .{ .name = "Payload" });

    var registry = Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&enum_file);
    // File-level enum values share the package scope in protobuf, so
    // ".demo.Payload" is already occupied even though the enum type is named
    // ".demo.Status".  This mirrors C++ DescriptorPool for descriptor sets or
    // programmatically-built descriptors that bypass the .proto parser.
    try std.testing.expectError(error.DuplicateSymbol, registry.addFile(&message_file));

    var message_scope_file = schema.FileDescriptor.init(allocator);
    defer message_scope_file.deinit();
    message_scope_file.setSyntax(.proto3);
    message_scope_file.package = "manual";
    try message_scope_file.messages.append(allocator, .{ .name = "Scope" });
    const scope = &message_scope_file.messages.items[0];
    try scope.fields.append(allocator, .{ .name = "STATE_UNSPECIFIED", .number = 1, .kind = .{ .scalar = .int32 } });
    try scope.enums.append(allocator, .{ .name = "State" });
    try scope.enums.items[0].values.append(allocator, .{ .name = "STATE_UNSPECIFIED", .number = 0 });

    var scoped_registry = Registry.init(allocator);
    defer scoped_registry.deinit();
    // Message fields, oneofs, nested types, extensions, and nested enum values
    // share the message scope; the registry must enforce that invariant even
    // when a descriptor is assembled directly in Zig.
    try std.testing.expectError(error.DuplicateSymbol, scoped_registry.addFile(&message_scope_file));
}

test "registry rejects duplicate extension symbols across files" {
    const allocator = std.testing.allocator;
    var first = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host { extensions 100 to max; }
        \\extend Host { optional string note = 100; }
    );
    defer first.deinit();
    first.name = "host.proto";
    var duplicate_number = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\import "host.proto";
        \\extend Host { optional int32 other = 100; }
    );
    defer duplicate_number.deinit();
    var duplicate_name = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\import "host.proto";
        \\extend Host { optional int32 note = 101; }
    );
    defer duplicate_name.deinit();

    var registry = Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&first);
    try std.testing.expectError(error.DuplicateSymbol, registry.addFile(&duplicate_number));
    try std.testing.expectError(error.DuplicateSymbol, registry.addFile(&duplicate_name));
}

test "registry rejects duplicate extension symbols within one file descriptor" {
    const allocator = std.testing.allocator;
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        file.package = "demo";
        var host = schema.MessageDescriptor{ .name = "Host" };
        try host.extension_ranges.append(allocator, .{ .start = 100, .end = 200 });
        try file.messages.append(allocator, host);
        try file.extensions.append(allocator, .{ .name = "first", .number = 100, .cardinality = .optional, .kind = .{ .scalar = .int32 }, .extendee = "Host" });
        try file.extensions.append(allocator, .{ .name = "second", .number = 100, .cardinality = .optional, .kind = .{ .scalar = .int32 }, .extendee = "Host" });
        var registry = Registry.init(allocator);
        defer registry.deinit();
        try std.testing.expectError(error.DuplicateSymbol, registry.addFile(&file));
    }
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        file.package = "demo";
        var host = schema.MessageDescriptor{ .name = "Host" };
        try host.extension_ranges.append(allocator, .{ .start = 100, .end = 200 });
        try file.messages.append(allocator, host);
        try file.extensions.append(allocator, .{ .name = "tag", .number = 100, .cardinality = .optional, .kind = .{ .scalar = .int32 }, .extendee = "Host" });
        try file.extensions.append(allocator, .{ .name = "tag", .number = 101, .cardinality = .optional, .kind = .{ .scalar = .int32 }, .extendee = "Host" });
        var registry = Registry.init(allocator);
        defer registry.deinit();
        try std.testing.expectError(error.DuplicateSymbol, registry.addFile(&file));
    }
}

test "registry allows same extension numbers on different package extendees" {
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
        \\message Host { extensions 100 to max; }
        \\extend Host { optional int32 note = 100; }
    );
    defer b_file.deinit();
    b_file.name = "b.proto";

    var registry = Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&a_file);
    try registry.addFile(&b_file);

    try std.testing.expectEqualStrings("note", registry.findExtension(".a.Host", 100).?.name);
    try std.testing.expectEqual(schema.ScalarType.string, registry.findExtension(".a.Host", 100).?.kind.scalar);
    try std.testing.expectEqual(schema.ScalarType.int32, registry.findExtension(".b.Host", 100).?.kind.scalar);
    try std.testing.expectEqual(schema.ScalarType.string, registry.findExtensionByName(".a.Host", "a.note").?.kind.scalar);
    try std.testing.expectEqual(schema.ScalarType.int32, registry.findExtensionByName(".b.Host", "b.note").?.kind.scalar);
}

test "registry validates extension extendee visibility" {
    const allocator = std.testing.allocator;
    var host = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host { extensions 100 to max; }
        \\enum TargetEnum { UNKNOWN = 0; }
    );
    defer host.deinit();
    host.name = "host.proto";

    var missing_extendee = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\extend Missing { optional int32 tag = 100; }
    );
    defer missing_extendee.deinit();
    missing_extendee.name = "missing.proto";

    var enum_extendee = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\extend TargetEnum { optional int32 tag = 100; }
    );
    defer enum_extendee.deinit();
    enum_extendee.name = "enum.proto";

    var option_only = try @import("parser.zig").Parser.parse(allocator,
        \\edition = "2024";
        \\package option_only;
        \\import option "host.proto";
        \\extend demo.Host { int32 tag = 100; }
    );
    defer option_only.deinit();
    option_only.name = "option-only.proto";

    var custom_option = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package demo;
        \\extend google.protobuf.MessageOptions { optional string note = 1000; }
    );
    defer custom_option.deinit();
    custom_option.name = "custom-option.proto";

    var registry = Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&host);
    try std.testing.expectError(error.InvalidExtensionDeclaration, registry.addFile(&missing_extendee));
    try std.testing.expectError(error.InvalidExtensionDeclaration, registry.addFile(&enum_extendee));
    try std.testing.expectError(error.InvalidExtensionDeclaration, registry.addFile(&option_only));
    try registry.addFile(&custom_option);
}

test "registry validates cross-file MessageSet extension shapes" {
    const allocator = std.testing.allocator;
    var host = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host {
        \\  option message_set_wire_format = true;
        \\  extensions 4 to max;
        \\}
    );
    defer host.deinit();
    host.name = "host.proto";
    var valid = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\import "host.proto";
        \\message Ext {}
        \\extend Host { optional Ext ext = 100; }
    );
    defer valid.deinit();
    valid.name = "valid.proto";
    var scalar = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\import "host.proto";
        \\extend Host { optional int32 bad = 101; }
    );
    defer scalar.deinit();
    scalar.name = "scalar.proto";
    var repeated = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\import "host.proto";
        \\message ExtRepeated {}
        \\extend Host { repeated ExtRepeated bad = 102; }
    );
    defer repeated.deinit();
    repeated.name = "repeated.proto";

    var registry = Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&host);
    try registry.addFile(&valid);
    try std.testing.expectError(error.InvalidExtensionDeclaration, registry.addFile(&scalar));
    try std.testing.expectError(error.InvalidExtensionDeclaration, registry.addFile(&repeated));
}

test "registry validates cross-file extension declarations" {
    const allocator = std.testing.allocator;
    var host = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host {
        \\  extensions 100 to max [
        \\    declaration = { number: 100 full_name: ".demo.ext" type: ".demo.Ext" },
        \\    verification = DECLARATION
        \\  ];
        \\}
        \\message Ext {}
    );
    defer host.deinit();
    host.name = "host.proto";
    var extension = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\import "host.proto";
        \\extend Host { optional Ext ext = 100; }
    );
    defer extension.deinit();
    extension.name = "extension.proto";

    var registry = Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&host);
    try registry.addFile(&extension);

    var missing_declaration = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\import "host.proto";
        \\extend Host { optional Ext other = 101; }
    );
    defer missing_declaration.deinit();
    missing_declaration.name = "missing-declaration.proto";
    try std.testing.expectError(error.InvalidExtensionDeclaration, registry.addFile(&missing_declaration));
}

test "registry enforces declaration coverage when any declaration exists" {
    const allocator = std.testing.allocator;
    var host = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host {
        \\  extensions 100 to max [
        \\    declaration = { number: 100 full_name: ".demo.ext" type: ".demo.Ext" }
        \\  ];
        \\}
        \\message Ext {}
    );
    defer host.deinit();
    host.name = "host.proto";
    var extension = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\import "host.proto";
        \\extend Host { optional Ext other = 101; }
    );
    defer extension.deinit();
    extension.name = "extension.proto";

    var registry = Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&host);
    try std.testing.expectError(error.InvalidExtensionDeclaration, registry.addFile(&extension));

    var wrong_package = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package other;
        \\import "host-type.proto";
        \\message Ext {}
        \\extend demo.Host { optional Ext ext = 100; }
    );
    defer wrong_package.deinit();
    wrong_package.name = "wrong-package.proto";
    try std.testing.expectError(error.InvalidExtensionDeclaration, registry.addFile(&wrong_package));

    var wrong_type_package = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package other;
        \\import "host.proto";
        \\message Ext {}
        \\extend demo.Host { optional Ext ext = 100; }
    );
    defer wrong_type_package.deinit();
    wrong_type_package.name = "wrong-type-package.proto";
    var host_for_type = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host {
        \\  extensions 100 to max [
        \\    declaration = { number: 100 full_name: ".other.ext" type: ".demo.Ext" }
        \\  ];
        \\}
        \\message Ext {}
    );
    defer host_for_type.deinit();
    host_for_type.name = "host-type.proto";
    // The declaration name matches .other.ext, but the extension's relative
    // Ext resolves under package other rather than demo.
    var registry_for_type = Registry.init(allocator);
    defer registry_for_type.deinit();
    try registry_for_type.addFile(&host_for_type);
    try std.testing.expectError(error.InvalidExtensionDeclaration, registry_for_type.addFile(&wrong_type_package));
}

test "registry rejects cross-file extension declaration mismatches" {
    const allocator = std.testing.allocator;
    var host = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host {
        \\  extensions 100 to max [
        \\    declaration = { number: 100 full_name: ".demo.ext" type: ".demo.Ext" repeated: true }
        \\  ];
        \\}
        \\message Ext {}
    );
    defer host.deinit();
    host.name = "host.proto";
    var extension = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\import "host.proto";
        \\extend Host { optional Ext ext = 100; }
    );
    defer extension.deinit();
    extension.name = "extension.proto";

    var registry = Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&host);
    try std.testing.expectError(error.InvalidExtensionDeclaration, registry.addFile(&extension));
}

test "registry rejects invalid extension declarations" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidFieldType, @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Host { extensions 100 to max [declaration = { number: 100 full_name: ".missing.type" }]; }
    ));
}

test "parser rejects duplicate default JSON names in proto3" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.DuplicateField, @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\message M {
        \\  int32 foo_bar = 1;
        \\  int32 fooBar = 2;
        \\}
    ));
}

test "registry allows legacy proto2 default JSON name conflicts" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message M {
        \\  optional int32 foo_bar = 1;
        \\  optional int32 fooBar = 2;
        \\}
    );
    defer file.deinit();
    var registry = Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);
}

test "parser rejects duplicate custom JSON names" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.DuplicateField, @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\message M {
        \\  int32 foo = 1 [json_name = "bar"];
        \\  int32 baz = 2 [json_name = "bar"];
        \\}
    ));
}

test "parser rejects custom JSON name colliding with default name" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.DuplicateField, @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\message M {
        \\  int32 foo = 1 [json_name = "bar"];
        \\  int32 bar = 2;
        \\}
    ));
}

test "registry rejects duplicate JSON names from decoded descriptors" {
    const allocator = std.testing.allocator;
    var file = schema.FileDescriptor{
        .allocator = allocator,
        .name = "m.proto",
        .syntax = .proto3,
        .features = schema.FeatureSet.defaults(.proto3),
    };
    defer file.deinit();
    var message = schema.MessageDescriptor{ .name = "M" };
    try message.fields.append(allocator, .{ .name = "foo_bar", .number = 1, .kind = .{ .scalar = .int32 } });
    try message.fields.append(allocator, .{ .name = "fooBar", .number = 2, .kind = .{ .scalar = .int32 } });
    try file.messages.append(allocator, message);

    var registry = Registry.init(allocator);
    defer registry.deinit();
    try std.testing.expectError(error.DuplicateJsonName, registry.addFile(&file));
}
