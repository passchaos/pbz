const std = @import("std");
const pbz = @import("pbz");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var file = try pbz.ProtoParser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host { extensions 100 to max; }
        \\message DeclaredHost {
        \\  extensions 200 to 249 [
        \\    declaration = { number: 200 full_name: ".demo.declared_priority" type: "int32" },
        \\    declaration = { number: 201 reserved: true },
        \\    declaration = { number: 202 full_name: ".demo.declared_tags" type: "int32" repeated: true },
        \\    verification = DECLARATION
        \\  ];
        \\}
        \\message MessageSetHost { option message_set_wire_format = true; extensions 4 to max; }
        \\message Payload {
        \\  required int32 id = 1;
        \\  optional string label = 2;
        \\}
        \\extend Host {
        \\  optional int32 priority = 100;
        \\  repeated Payload payloads = 101;
        \\}
        \\message Scope { extend Host { optional string scoped_value = 102; } }
        \\extend DeclaredHost {
        \\  optional int32 declared_priority = 200;
        \\  repeated int32 declared_tags = 202;
        \\}
    );
    defer file.deinit();
    file.name = "extensions.proto";

    var registry = pbz.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);

    const refl = pbz.Reflection.init(allocator, &registry);
    const host_desc = try refl.message(".demo.Host");
    const priority_ext = try refl.extensionForMessage(host_desc, 100);
    std.debug.assert(priority_ext == try refl.extension("demo.Host", 100));
    std.debug.assert(priority_ext == try refl.extensionByName("demo.Host", ".demo.priority"));
    std.debug.assert(priority_ext == try refl.extensionByNameForMessage(host_desc, "priority"));
    std.debug.assert(priority_ext == try refl.extensionByPrintableNameForMessage(host_desc, "[demo.priority]"));
    try std.testing.expectError(error.UnknownField, refl.extensionByPrintableNameForMessage(host_desc, "demo.priority"));
    const priority_full_name = try refl.extensionFullName(priority_ext);
    defer allocator.free(priority_full_name);
    std.debug.assert(std.mem.eql(u8, priority_full_name, "demo.priority"));
    const priority_direct_full_name = try refl.fieldDirectFullName(priority_ext);
    defer allocator.free(priority_direct_full_name);
    std.debug.assert(std.mem.eql(u8, priority_direct_full_name, "demo.priority"));
    std.debug.assert(refl.fieldIsExtension(priority_ext));
    std.debug.assert(std.mem.eql(u8, try refl.fieldExtendeeName(priority_ext), "Host"));
    std.debug.assert((try refl.fieldExtendeeType(priority_ext)) == host_desc);
    std.debug.assert((try refl.fieldContainingType(host_desc, priority_ext)) == host_desc);
    std.debug.assert((try refl.fieldDirectContainingType(priority_ext)) == host_desc);
    std.debug.assert((try refl.fieldDirectContainingFile(priority_ext)).name.len != 0);
    std.debug.assert((try refl.fieldExtensionScope(priority_ext)) == null);
    std.debug.assert(!(try refl.fieldHasExtensionScope(priority_ext)));
    std.debug.assert(std.mem.eql(u8, (try refl.fileOfExtension(priority_ext)).name, "extensions.proto"));
    const scoped_ext = try refl.extensionForMessage(host_desc, 102);
    const host_extensions = try refl.extensionsForMessage(host_desc);
    defer allocator.free(host_extensions);
    std.debug.assert(host_extensions.len == 3);
    std.debug.assert(host_extensions[0] == priority_ext);
    std.debug.assert(host_extensions[1] == registry.findExtension("demo.Host", 101).?);
    std.debug.assert(host_extensions[2] == scoped_ext);
    const scope_desc = try refl.message(".demo.Scope");
    std.debug.assert((try refl.fieldExtensionScope(scoped_ext)).? == scope_desc);
    std.debug.assert(try refl.fieldHasExtensionScope(scoped_ext));
    std.debug.assert(scoped_ext == try refl.messageExtension(scope_desc, "scoped_value"));
    std.debug.assert(scoped_ext == try refl.messageExtensionByLowercaseName(scope_desc, "scoped_value"));
    std.debug.assert(scoped_ext == try refl.messageExtensionByCamelcaseName(scope_desc, "scopedValue"));
    try std.testing.expectError(error.UnknownField, refl.messageExtension(scope_desc, ".demo.Scope.scoped_value"));

    var host = try pbz.parseTextAllocWithRegistry(
        allocator,
        &file,
        &registry,
        host_desc,
        "[demo.priority]: 5\n",
    );
    defer host.deinit();

    std.debug.assert(host.getByNumber(priority_ext.number).?.values.items[0].int32 == 5);

    const host_json = try pbz.stringifyJsonAllocWithRegistry(allocator, &file, &registry, &host, .{});
    defer allocator.free(host_json);
    std.debug.assert(std.mem.indexOf(u8, host_json, "[demo.priority]") != null);

    var host_payloads = try pbz.parseTextInitializedAllocWithRegistry(allocator, &file, &registry, host_desc,
        \\[demo.payloads] { id: 1 label: "one" }
        \\[demo.payloads] < id: 2 label: "two" >
    );
    defer host_payloads.deinit();
    const payloads_ext = registry.findExtension("demo.Host", 101).?;
    const payload_values = host_payloads.getByNumber(payloads_ext.number).?.values.items;
    std.debug.assert(payload_values.len == 2);
    std.debug.assert(payload_values[1].message.get("id").?.values.items[0].int32 == 2);

    var host_payloads_json = try pbz.parseJsonInitializedAllocWithRegistry(
        allocator,
        &file,
        &registry,
        host_desc,
        "{\"[demo.payloads]\":[{\"id\":3},{\"id\":4,\"label\":\"four\"}]}",
        .{},
    );
    defer host_payloads_json.deinit();
    const json_payload_values = host_payloads_json.getByNumber(payloads_ext.number).?.values.items;
    std.debug.assert(json_payload_values.len == 2);
    std.debug.assert(json_payload_values[1].message.get("label").?.values.items[0].string.len == 4);

    try std.testing.expectError(error.MissingRequiredField, pbz.parseTextInitializedAllocWithRegistry(
        allocator,
        &file,
        &registry,
        host_desc,
        "[demo.payloads] { label: \"missing id\" }",
    ));
    try std.testing.expectError(error.MissingRequiredField, pbz.parseJsonInitializedAllocWithRegistry(
        allocator,
        &file,
        &registry,
        host_desc,
        "{\"[demo.payloads]\":[{}]}",
        .{},
    ));

    const declared_desc = file.findMessage("DeclaredHost").?;
    const range = declared_desc.extension_ranges.items[0];
    std.debug.assert(refl.messageIsExtensionNumber(declared_desc, 200));
    std.debug.assert(!refl.messageIsExtensionNumber(declared_desc, 199));
    std.debug.assert(refl.messageExtensionRangeCount(declared_desc) == 1);
    const reflected_range = refl.messageExtensionRange(declared_desc, 200) orelse return error.MissingExtensionRange;
    std.debug.assert(reflected_range == try refl.messageExtensionRangeAt(declared_desc, 0));
    std.debug.assert(try refl.messageExtensionRangeIndex(declared_desc, reflected_range) == 0);
    std.debug.assert(try refl.extensionRangeContainingType(declared_desc, reflected_range) == declared_desc);
    try std.testing.expectError(error.UnknownField, refl.messageExtensionRangeAt(declared_desc, 9));
    std.debug.assert(refl.extensionRangeStart(reflected_range) == 200);
    std.debug.assert(try refl.extensionRangeEnd(declared_desc, reflected_range) == 250);
    std.debug.assert(try refl.extensionRangeContains(declared_desc, reflected_range, 200));
    std.debug.assert(refl.messageIsExtensionNumber(declared_desc, 249));
    std.debug.assert(!(try refl.extensionRangeContains(declared_desc, reflected_range, 250)));
    std.debug.assert(!refl.messageIsExtensionNumber(declared_desc, 250));
    std.debug.assert(refl.extensionRangeHasVerification(reflected_range));
    std.debug.assert(try refl.extensionRangeVerification(reflected_range) == .declaration);
    std.debug.assert(std.mem.eql(u8, refl.optionIdentifier(refl.extensionRangeOptions(reflected_range), "verification").?, "DECLARATION"));
    const host_open_range = try refl.messageExtensionRangeAt(host_desc, 0);
    std.debug.assert(try refl.extensionRangeEnd(host_desc, host_open_range) == @as(i64, std.math.maxInt(pbz.FieldNumber)) + 1);
    const message_set_desc = try refl.message(".demo.MessageSetHost");
    const message_set_open_range = try refl.messageExtensionRangeAt(message_set_desc, 0);
    std.debug.assert(try refl.extensionRangeEnd(message_set_desc, message_set_open_range) == std.math.maxInt(i32));
    std.debug.assert(refl.messageExtensionRangeMaxExclusive(message_set_desc) == std.math.maxInt(i32));
    std.debug.assert(refl.messageIsExtensionNumber(message_set_desc, std.math.maxInt(i32) - 1));
    std.debug.assert(!refl.messageIsExtensionNumber(message_set_desc, std.math.maxInt(i32)));
    std.debug.assert(range.verification.? == .declaration);
    std.debug.assert(refl.extensionDeclarationCount(reflected_range) == 3);
    const priority_decl = try refl.extensionDeclarationAt(reflected_range, 0);
    std.debug.assert(refl.extensionDeclarationNumber(priority_decl) == 200);
    std.debug.assert(std.mem.eql(u8, refl.extensionDeclarationFullName(priority_decl), ".demo.declared_priority"));
    std.debug.assert(std.mem.eql(u8, refl.extensionDeclarationTypeName(priority_decl), "int32"));
    std.debug.assert(!refl.extensionDeclarationIsReserved(priority_decl));
    std.debug.assert(!refl.extensionDeclarationIsRepeated(priority_decl));
    try std.testing.expectError(error.UnknownField, refl.extensionDeclarationAt(reflected_range, 9));
    const found_priority_decl = refl.extensionDeclaration(reflected_range, 200) orelse return error.MissingExtensionDeclaration;
    std.debug.assert(std.mem.eql(u8, refl.extensionDeclarationFullName(found_priority_decl), ".demo.declared_priority"));
    const reserved_decl = refl.extensionDeclaration(reflected_range, 201) orelse return error.MissingExtensionDeclaration;
    std.debug.assert(refl.extensionDeclarationIsReserved(reserved_decl));
    const repeated_decl = refl.extensionDeclaration(reflected_range, 202) orelse return error.MissingExtensionDeclaration;
    std.debug.assert(refl.extensionDeclarationIsRepeated(repeated_decl));
    std.debug.assert(refl.extensionDeclaration(reflected_range, 203) == null);
    std.debug.assert(range.declarations.items.len == 3);
    std.debug.assert(std.mem.eql(u8, range.declarations.items[0].full_name, ".demo.declared_priority"));
    std.debug.assert(range.declarations.items[1].reserved);

    const descriptor_bytes = try pbz.encodeFileDescriptorProto(allocator, &file, "extensions.proto");
    defer allocator.free(descriptor_bytes);
    var decoded_file = try pbz.decodeFileDescriptorProto(allocator, descriptor_bytes);
    defer decoded_file.deinit();
    const decoded_range = decoded_file.findMessage("DeclaredHost").?.extension_ranges.items[0];
    std.debug.assert(decoded_range.verification.? == .declaration);
    std.debug.assert(std.mem.eql(u8, decoded_range.declarations.items[0].type_name, "int32"));

    var declared = try pbz.parseTextAllocWithRegistry(
        allocator,
        &file,
        &registry,
        declared_desc,
        "[demo.declared_priority]: 11\n",
    );
    defer declared.deinit();

    const declared_ext = registry.findExtension("demo.DeclaredHost", 200).?;
    std.debug.assert(declared_ext == try refl.fileExtension(&file, "declared_priority"));
    std.debug.assert(declared_ext == try refl.fileExtensionByLowercaseName(&file, "declared_priority"));
    std.debug.assert(declared_ext == try refl.fileExtensionByCamelcaseName(&file, "declaredPriority"));
    try std.testing.expectError(error.UnknownField, refl.fileExtension(&file, ".demo.declared_priority"));
    const declared_full_name = try refl.extensionFullName(declared_ext);
    defer allocator.free(declared_full_name);
    std.debug.assert(std.mem.eql(u8, declared_full_name, "demo.declared_priority"));
    std.debug.assert((try refl.fieldExtendeeType(declared_ext)) == declared_desc);
    std.debug.assert(declared.getByNumber(declared_ext.number).?.values.items[0].int32 == 11);
    const declared_json = try pbz.stringifyJsonAllocWithRegistry(allocator, &file, &registry, &declared, .{});
    defer allocator.free(declared_json);
    std.debug.assert(std.mem.indexOf(u8, declared_json, "[demo.declared_priority]") != null);

    try std.testing.expectError(error.ReservedField, pbz.ProtoParser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host {
        \\  extensions 200 to max [
        \\    declaration = { number: 201 reserved: true },
        \\    verification = DECLARATION
        \\  ];
        \\}
        \\extend Host { optional int32 forbidden = 201; }
    ));
}
