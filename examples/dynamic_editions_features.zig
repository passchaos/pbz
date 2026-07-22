const std = @import("std");
const pbz = @import("pbz");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var file = try pbz.ProtoParser.parse(allocator,
        \\edition = "2023";
        \\package demo.editions;
        \\option features.field_presence = EXPLICIT;
        \\option features.repeated_field_encoding = EXPANDED;
        \\option features.enum_type = OPEN;
        \\message Child {
        \\  option features.message_encoding = DELIMITED;
        \\  string label = 1;
        \\  int32 id = 2;
        \\}
        \\enum Role {
        \\  option features.enum_type = CLOSED;
        \\  ROLE_UNKNOWN = 0;
        \\  ROLE_ADMIN = 1 [features.enforce_naming_style = STYLE2026];
        \\}
        \\message Editions {
        \\  int32 explicit_zero = 1;
        \\  int32 implicit_zero = 2 [features.field_presence = IMPLICIT];
        \\  repeated int32 expanded = 3;
        \\  repeated int32 packed = 4 [features.repeated_field_encoding = PACKED];
        \\  Child delimited_child = 5 [features.message_encoding = DELIMITED];
        \\  Child normal_child = 6 [features.message_encoding = LENGTH_PREFIXED];
        \\  string relaxed = 7 [features.utf8_validation = NONE];
        \\  Role role = 8;
        \\  int32 required_id = 9 [features.field_presence = LEGACY_REQUIRED];
        \\  oneof choice {
        \\    option features.field_presence = EXPLICIT;
        \\    int32 picked = 10;
        \\  }
        \\}
        \\service EditionsApi {
        \\  option features.enforce_naming_style = STYLE2024;
        \\  rpc Get (Editions) returns (Editions) {
        \\    option features.enforce_proto_limits = PROTO_LIMITS2026;
        \\  }
        \\}
        \\message FeatureHost {
        \\  extensions 100 to max [features.repeated_field_encoding = PACKED];
        \\}
    );
    defer file.deinit();

    const desc = file.findMessage("Editions") orelse return error.MissingDescriptor;
    const child_desc = file.findMessage("Child") orelse return error.MissingDescriptor;
    var registry = pbz.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);
    const refl = pbz.Reflection.init(allocator, &registry);
    const choice_oneof = desc.findOneof("choice") orelse return error.MissingDescriptor;
    const service_desc = try refl.fileService(&file, "EditionsApi");
    const get_method = try refl.methodByName(service_desc, "Get");
    const feature_range = try refl.messageExtensionRangeAt(try refl.fileMessage(&file, "FeatureHost"), 0);
    try std.testing.expectEqual(pbz.schema.FeatureSet.FieldPresence.explicit, refl.fileFieldPresence(&file));
    try std.testing.expectEqual(pbz.schema.FeatureSet.RepeatedFieldEncoding.expanded, refl.fileRepeatedFieldEncoding(&file));
    try std.testing.expectEqual(pbz.schema.FeatureSet.EnumType.open, refl.fileEnumType(&file));
    try std.testing.expectEqual(pbz.schema.FeatureSet.Utf8Validation.verify, refl.fileUtf8Validation(&file));
    try std.testing.expectEqual(pbz.schema.FeatureSet.MessageEncoding.length_prefixed, refl.fileMessageEncoding(&file));
    try std.testing.expectEqual(pbz.schema.FeatureSet.JsonFormat.allow, refl.fileJsonFormat(&file));
    try std.testing.expectEqual(pbz.schema.FeatureSet.EnforceNamingStyle.style_legacy, refl.fileEnforceNamingStyle(&file));
    try std.testing.expectEqual(pbz.schema.FeatureSet.DefaultSymbolVisibility.export_all, refl.fileDefaultSymbolVisibility(&file));
    try std.testing.expectEqual(pbz.schema.FeatureSet.EnforceProtoLimits.legacy_no_explicit_limits, refl.fileEnforceProtoLimits(&file));
    const file_features = refl.fileFeatures(&file);
    try std.testing.expect(refl.featureSetEqual(file_features, file.features));
    try std.testing.expectEqual(pbz.schema.FeatureSet.FieldPresence.explicit, refl.featureSetFieldPresence(file_features));
    try std.testing.expectEqual(pbz.schema.FeatureSet.RepeatedFieldEncoding.expanded, refl.featureSetRepeatedFieldEncoding(file_features));
    try std.testing.expectEqual(pbz.schema.FeatureSet.EnumType.open, refl.featureSetEnumType(file_features));
    try std.testing.expectEqual(pbz.schema.FeatureSet.Utf8Validation.verify, refl.featureSetUtf8Validation(file_features));
    try std.testing.expectEqual(pbz.schema.FeatureSet.MessageEncoding.length_prefixed, refl.featureSetMessageEncoding(file_features));
    try std.testing.expectEqual(pbz.schema.FeatureSet.JsonFormat.allow, refl.featureSetJsonFormat(file_features));
    try std.testing.expectEqual(pbz.schema.FeatureSet.EnforceNamingStyle.style_legacy, refl.featureSetEnforceNamingStyle(file_features));
    try std.testing.expectEqual(pbz.schema.FeatureSet.DefaultSymbolVisibility.export_all, refl.featureSetDefaultSymbolVisibility(file_features));
    try std.testing.expectEqual(pbz.schema.FeatureSet.EnforceProtoLimits.legacy_no_explicit_limits, refl.featureSetEnforceProtoLimits(file_features));
    try std.testing.expect(refl.messageHasExplicitFeatures(child_desc));
    try std.testing.expectEqual(pbz.schema.FeatureSet.MessageEncoding.delimited, (try refl.messageExplicitFeatures(child_desc)).message_encoding);
    try std.testing.expect(!refl.messageHasExplicitFeatures(desc));
    try std.testing.expectError(error.MissingField, refl.messageExplicitFeatures(desc));
    try std.testing.expect(refl.oneofHasExplicitFeatures(choice_oneof));
    try std.testing.expectEqual(pbz.schema.FeatureSet.FieldPresence.explicit, (try refl.oneofExplicitFeatures(choice_oneof)).field_presence);
    try std.testing.expect(refl.serviceHasExplicitFeatures(service_desc));
    try std.testing.expectEqual(pbz.schema.FeatureSet.EnforceNamingStyle.style2024, (try refl.serviceExplicitFeatures(service_desc)).enforce_naming_style);
    try std.testing.expect(refl.methodHasExplicitFeatures(get_method));
    try std.testing.expectEqual(pbz.schema.FeatureSet.EnforceProtoLimits.proto_limits2026, (try refl.methodExplicitFeatures(get_method)).enforce_proto_limits);
    try std.testing.expect(refl.extensionRangeHasExplicitFeatures(feature_range));
    try std.testing.expectEqual(pbz.schema.FeatureSet.RepeatedFieldEncoding.packed_encoding, (try refl.extensionRangeExplicitFeatures(feature_range)).repeated_field_encoding);
    try std.testing.expectEqual(pbz.schema.FeatureSet.EnumType.closed, try refl.enumType(file.findEnum("Role") orelse return error.MissingDescriptor));
    const role_desc = file.findEnum("Role") orelse return error.MissingDescriptor;
    try std.testing.expect(refl.enumHasExplicitFeatures(role_desc));
    try std.testing.expectEqual(pbz.schema.FeatureSet.EnumType.closed, (try refl.enumExplicitFeatures(role_desc)).enum_type);
    const role_admin = try refl.enumValueByName(role_desc, "ROLE_ADMIN");
    try std.testing.expect(refl.enumValueHasExplicitFeatures(role_admin));
    try std.testing.expectEqual(pbz.schema.FeatureSet.EnforceNamingStyle.style2026, (try refl.enumValueExplicitFeatures(role_admin)).enforce_naming_style);
    try std.testing.expect(!refl.enumValueHasExplicitFeatures(try refl.enumValueByName(role_desc, "ROLE_UNKNOWN")));
    try std.testing.expectEqual(pbz.schema.FeatureSet.RepeatedFieldEncoding.packed_encoding, (desc.findField("packed") orelse return error.MissingField).features.?.repeated_field_encoding);
    try std.testing.expect(refl.fieldHasExplicitFeatures(desc.findField("packed") orelse return error.MissingField));
    try std.testing.expectEqual(pbz.schema.FeatureSet.RepeatedFieldEncoding.packed_encoding, (try refl.fieldExplicitFeatures(desc.findField("packed") orelse return error.MissingField)).repeated_field_encoding);
    try std.testing.expect(!refl.fieldHasExplicitFeatures(desc.findField("expanded") orelse return error.MissingField));
    try std.testing.expectError(error.MissingField, refl.fieldExplicitFeatures(desc.findField("expanded") orelse return error.MissingField));
    try std.testing.expectEqual(pbz.schema.FeatureSet.FieldPresence.explicit, try refl.fieldPresence(desc, desc.findField("explicit_zero") orelse return error.MissingField));
    try std.testing.expectEqual(pbz.schema.FeatureSet.FieldPresence.implicit, try refl.fieldPresence(desc, desc.findField("implicit_zero") orelse return error.MissingField));
    try std.testing.expectEqual(pbz.schema.FeatureSet.FieldPresence.legacy_required, try refl.fieldPresence(desc, desc.findField("required_id") orelse return error.MissingField));
    try std.testing.expect(try refl.fieldIsPacked(desc, desc.findField("packed") orelse return error.MissingField));
    try std.testing.expectEqual(pbz.schema.FeatureSet.MessageEncoding.delimited, try refl.fieldMessageEncoding(desc, desc.findField("delimited_child") orelse return error.MissingField));
    try std.testing.expectEqual(pbz.schema.FeatureSet.Utf8Validation.none, try refl.fieldUtf8Validation(desc, desc.findField("relaxed") orelse return error.MissingField));

    var msg = pbz.DynamicMessage.init(allocator, desc);
    defer msg.deinit();

    // Editions LEGACY_REQUIRED participates in the same initialized-message
    // safety gates as proto2 required fields.
    try std.testing.expectError(error.MissingRequiredField, msg.encodedInitialized(&file));
    try std.testing.expectError(error.MissingRequiredField, msg.validateRequired());

    try msg.add(desc.findField("explicit_zero") orelse return error.MissingField, .{ .int32 = 0 });
    try msg.add(desc.findField("implicit_zero") orelse return error.MissingField, .{ .int32 = 0 });
    try msg.add(desc.findField("expanded") orelse return error.MissingField, .{ .int32 = 1 });
    try msg.add(desc.findField("expanded") orelse return error.MissingField, .{ .int32 = 2 });
    try msg.add(desc.findField("packed") orelse return error.MissingField, .{ .int32 = 3 });
    try msg.add(desc.findField("packed") orelse return error.MissingField, .{ .int32 = 4 });

    const delimited = try allocator.create(pbz.DynamicMessage);
    delimited.* = pbz.DynamicMessage.init(allocator, child_desc);
    try delimited.add(child_desc.findField("label") orelse return error.MissingField, .{ .string = try allocator.dupe(u8, "groupy") });
    try delimited.add(child_desc.findField("id") orelse return error.MissingField, .{ .int32 = 7 });
    try msg.add(desc.findField("delimited_child") orelse return error.MissingField, .{ .message = delimited });

    const normal = try allocator.create(pbz.DynamicMessage);
    normal.* = pbz.DynamicMessage.init(allocator, child_desc);
    try normal.add(child_desc.findField("label") orelse return error.MissingField, .{ .string = try allocator.dupe(u8, "normal") });
    try normal.add(child_desc.findField("id") orelse return error.MissingField, .{ .int32 = 8 });
    try msg.add(desc.findField("normal_child") orelse return error.MissingField, .{ .message = normal });

    // The relaxed string intentionally contains invalid UTF-8.  Editions
    // utf8_validation=NONE must preserve and re-emit those bytes, while strict
    // fields in the same schema would reject them.
    try msg.add(desc.findField("relaxed") orelse return error.MissingField, .{ .string = try allocator.dupe(u8, &.{0xc0}) });
    try msg.add(desc.findField("role") orelse return error.MissingField, .{ .enumeration = 1 });
    try msg.add(desc.findField("required_id") orelse return error.MissingField, .{ .int32 = 5 });

    const encoded = try msg.encodedInitialized(&file);
    defer allocator.free(encoded);
    try std.testing.expect(std.mem.indexOf(u8, encoded, &.{ 0x08, 0x00 }) != null); // explicit zero is present.
    try std.testing.expect(std.mem.indexOf(u8, encoded, &.{ 0x10, 0x00 }) == null); // implicit default is elided.
    try std.testing.expect(std.mem.indexOf(u8, encoded, &.{ 0x18, 0x01, 0x18, 0x02 }) != null); // expanded repeated.
    try std.testing.expect(std.mem.indexOf(u8, encoded, &.{ 0x22, 0x02, 0x03, 0x04 }) != null); // packed override.
    try std.testing.expect(std.mem.indexOf(u8, encoded, &.{0x2b}) != null); // start_group for delimited child.
    try std.testing.expect(std.mem.indexOf(u8, encoded, &.{0x2c}) != null); // end_group for delimited child.
    try std.testing.expect(std.mem.indexOf(u8, encoded, &.{0x32}) != null); // length-delimited normal child.
    try std.testing.expect(std.mem.indexOf(u8, encoded, &.{ 0x3a, 0x01, 0xc0 }) != null); // invalid UTF-8 preserved.

    var decoded = pbz.DynamicMessage.init(allocator, desc);
    defer decoded.deinit();
    try decoded.decodeInitialized(&file, encoded);
    try std.testing.expect(decoded.has(desc.findField("explicit_zero") orelse return error.MissingField));
    try std.testing.expect(!decoded.has(desc.findField("implicit_zero") orelse return error.MissingField));
    try std.testing.expectEqual(@as(usize, 2), decoded.get("expanded").?.values.items.len);
    try std.testing.expectEqual(@as(usize, 2), decoded.get("packed").?.values.items.len);
    try std.testing.expectEqualStrings(&.{0xc0}, decoded.get("relaxed").?.values.items[0].string);

    // Closed enum unknowns are preserved as unknown raw fields under editions
    // enum_type=CLOSED, while known values remain typed.
    var with_unknown_role = pbz.Writer.init(allocator);
    defer with_unknown_role.deinit();
    try with_unknown_role.appendSlice(encoded);
    try with_unknown_role.writeInt32(8, 123);
    var decoded_unknown = pbz.DynamicMessage.init(allocator, desc);
    defer decoded_unknown.deinit();
    try decoded_unknown.decodeInitialized(&file, with_unknown_role.slice());
    try std.testing.expectEqual(@as(i32, 1), decoded_unknown.get("role").?.values.items[0].enumeration);
    try std.testing.expectEqual(@as(usize, 1), decoded_unknown.unknownFieldCountByNumber(8));
    const raw_role = decoded_unknown.unknownByNumber(8);
    try std.testing.expectEqualSlices(u8, &.{ 0x40, 0x7b }, raw_role[0].data);

    const text = try pbz.formatTextAlloc(allocator, &file, &msg, .{});
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "explicit_zero: 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "implicit_zero: 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "delimited_child {") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "relaxed: \"\\300\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "role: ROLE_ADMIN") != null);

    var from_text = try pbz.parseTextInitializedAlloc(allocator, &file, desc, text);
    defer from_text.deinit();
    try std.testing.expect(from_text.has(desc.findField("required_id") orelse return error.MissingField));
    try std.testing.expectEqualStrings(&.{0xc0}, from_text.get("relaxed").?.values.items[0].string);

    var extension_tree = pbz.MemorySourceTree.init(allocator);
    defer extension_tree.deinit();
    try extension_tree.add("host.proto",
        \\edition = "2023";
        \\package demo.editions_ext;
        \\option features.field_presence = IMPLICIT;
        \\message Host { extensions 100 to max; }
    );
    try extension_tree.add("ext.proto",
        \\edition = "2023";
        \\package demo.editions_ext;
        \\import "host.proto";
        \\option features.utf8_validation = NONE;
        \\option features.message_encoding = DELIMITED;
        \\message Payload { string label = 1; }
        \\extend Host {
        \\  repeated int32 samples = 100;
        \\  string relaxed = 101;
        \\  Payload delimited = 102;
        \\  int32 explicit_zero = 103;
        \\}
    );
    var extension_loaded = try pbz.loadMemory(allocator, &extension_tree, "ext.proto");
    defer extension_loaded.deinit();
    const host_file = extension_loaded.registry.findFile("host.proto") orelse return error.MissingDescriptor;
    const ext_file = extension_loaded.registry.findFile("ext.proto") orelse return error.MissingDescriptor;
    const host_desc = extension_loaded.registry.findMessage(".demo.editions_ext.Host", null) orelse return error.MissingDescriptor;
    const payload_desc = extension_loaded.registry.findMessage(".demo.editions_ext.Payload", null) orelse return error.MissingDescriptor;
    const samples_ext = extension_loaded.registry.findExtensionForMessage(host_desc, 100) orelse return error.MissingDescriptor;
    const relaxed_ext = extension_loaded.registry.findExtensionForMessage(host_desc, 101) orelse return error.MissingDescriptor;
    const delimited_ext = extension_loaded.registry.findExtensionForMessage(host_desc, 102) orelse return error.MissingDescriptor;
    const explicit_zero_ext = extension_loaded.registry.findExtensionForMessage(host_desc, 103) orelse return error.MissingDescriptor;
    const extension_refl = pbz.Reflection.init(allocator, &extension_loaded.registry);
    try std.testing.expect((try extension_refl.fileOfExtension(samples_ext)) == ext_file);
    try std.testing.expect(try extension_refl.fieldIsPacked(host_desc, samples_ext));
    try std.testing.expectEqual(pbz.WireType.length_delimited, try extension_refl.fieldEncodedWireType(host_desc, samples_ext));
    try std.testing.expectEqual(pbz.schema.FeatureSet.Utf8Validation.none, try extension_refl.fieldUtf8Validation(host_desc, relaxed_ext));
    try std.testing.expectEqual(pbz.schema.FeatureSet.MessageEncoding.delimited, try extension_refl.fieldMessageEncoding(host_desc, delimited_ext));
    try std.testing.expectEqual(pbz.schema.FeatureSet.FieldPresence.explicit, try extension_refl.fieldPresence(host_desc, explicit_zero_ext));

    var extension_host = pbz.DynamicMessage.init(allocator, host_desc);
    defer extension_host.deinit();
    try extension_host.add(samples_ext, .{ .int32 = 3 });
    try extension_host.add(samples_ext, .{ .int32 = 4 });
    try extension_host.add(relaxed_ext, .{ .string = try allocator.dupe(u8, &.{0xc0}) });
    const extension_payload = try allocator.create(pbz.DynamicMessage);
    extension_payload.* = pbz.DynamicMessage.init(allocator, payload_desc);
    try extension_payload.add(payload_desc.findField("label") orelse return error.MissingField, .{ .string = try allocator.dupe(u8, "owned") });
    try extension_host.add(delimited_ext, .{ .message = extension_payload });
    try extension_host.add(explicit_zero_ext, .{ .int32 = 0 });

    const extension_encoded = try extension_host.encodedWithRegistry(host_file, &extension_loaded.registry);
    defer allocator.free(extension_encoded);
    try std.testing.expect(std.mem.indexOf(u8, extension_encoded, &.{ 0xa2, 0x06, 0x02, 0x03, 0x04 }) != null);
    try std.testing.expect(std.mem.indexOf(u8, extension_encoded, &.{ 0xaa, 0x06, 0x01, 0xc0 }) != null);
    try std.testing.expect(std.mem.indexOf(u8, extension_encoded, &.{ 0xb3, 0x06 }) != null);
    try std.testing.expect(std.mem.indexOf(u8, extension_encoded, &.{ 0xb4, 0x06 }) != null);
    try std.testing.expect(std.mem.indexOf(u8, extension_encoded, &.{ 0xb8, 0x06, 0x00 }) != null);

    var decoded_extension_host = pbz.DynamicMessage.init(allocator, host_desc);
    defer decoded_extension_host.deinit();
    try decoded_extension_host.decodeWithRegistry(host_file, &extension_loaded.registry, extension_encoded);
    try std.testing.expectEqual(@as(usize, 2), decoded_extension_host.get("samples").?.values.items.len);
    try std.testing.expectEqualStrings(&.{0xc0}, decoded_extension_host.get("relaxed").?.values.items[0].string);
    try std.testing.expectEqualStrings("owned", decoded_extension_host.get("delimited").?.values.items[0].message.get("label").?.values.items[0].string);
    try std.testing.expectEqual(@as(i32, 0), decoded_extension_host.get("explicit_zero").?.values.items[0].int32);

    var json_extension_host = pbz.DynamicMessage.init(allocator, host_desc);
    defer json_extension_host.deinit();
    try json_extension_host.add(explicit_zero_ext, .{ .int32 = 0 });
    const extension_json = try pbz.stringifyJsonAllocWithRegistry(allocator, host_file, &extension_loaded.registry, &json_extension_host, .{});
    defer allocator.free(extension_json);
    try std.testing.expect(std.mem.indexOf(u8, extension_json, "\"[demo.editions_ext.explicit_zero]\":0") != null);
    var extension_from_json = try pbz.parseJsonAllocWithRegistry(allocator, host_file, &extension_loaded.registry, host_desc, extension_json, .{});
    defer extension_from_json.deinit();
    try std.testing.expectEqual(@as(i32, 0), extension_from_json.get("explicit_zero").?.values.items[0].int32);

    const extension_text = try pbz.formatTextAllocWithRegistry(allocator, host_file, &extension_loaded.registry, &extension_host, .{});
    defer allocator.free(extension_text);
    try std.testing.expect(std.mem.indexOf(u8, extension_text, "[demo.editions_ext.samples]: 3") != null);
    try std.testing.expect(std.mem.indexOf(u8, extension_text, "[demo.editions_ext.relaxed]: \"\\300\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, extension_text, "[demo.editions_ext.delimited] {") != null);

    var extension_from_text = try pbz.parseTextAllocWithRegistry(allocator, host_file, &extension_loaded.registry, host_desc, extension_text);
    defer extension_from_text.deinit();
    try std.testing.expectEqual(@as(usize, 2), extension_from_text.get("samples").?.values.items.len);
    try std.testing.expectEqualStrings(&.{0xc0}, extension_from_text.get("relaxed").?.values.items[0].string);
    try std.testing.expectEqualStrings("owned", extension_from_text.get("delimited").?.values.items[0].message.get("label").?.values.items[0].string);
    try std.testing.expectEqual(@as(i32, 0), extension_from_text.get("explicit_zero").?.values.items[0].int32);
}

comptime {
    _ = pbz;
}
