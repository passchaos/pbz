const registry_mod = @import("registry.zig");
const schema = @import("schema.zig");
const std = @import("std");
const wire = @import("wire.zig");
const module = @import("descriptor.zig");
const decodeFeatureSetDefaults = module.decodeFeatureSetDefaults;
const decodeFileDescriptorProto = module.decodeFileDescriptorProto;
const decodeFileDescriptorSet = module.decodeFileDescriptorSet;
const decodeGeneratedCodeInfo = module.decodeGeneratedCodeInfo;
const encodeFeatureSetDefaults = module.encodeFeatureSetDefaults;
const encodeFileDescriptorProto = module.encodeFileDescriptorProto;
const encodeFileDescriptorProtoWithRegistry = module.encodeFileDescriptorProtoWithRegistry;
const encodeFileDescriptorSet = module.encodeFileDescriptorSet;
const encodeGeneratedCodeInfo = module.encodeGeneratedCodeInfo;
const defaultValueText = module.test_helpers.defaultValueText;
const exactOptionBool = module.test_helpers.exactOptionBool;
const exactOptionString = module.test_helpers.exactOptionString;
const fileOptimizeMode = module.test_helpers.fileOptimizeMode;
const writePackedInt32List = module.test_helpers.writePackedInt32List;

test "descriptor encodes a minimal proto2 FileDescriptorProto" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto2";
        \\package demo;
        \\message Person {
        \\  required int32 id = 1;
        \\  optional string name = 2;
        \\}
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    file.source_code_info.deinit(allocator);
    file.source_code_info = .{};

    const bytes = try encodeFileDescriptorProto(allocator, &file, "person.proto");
    defer allocator.free(bytes);

    // protoc omits `syntax` for proto2.
    const expected = &[_]u8{
        0x0a, 0x0c, 'p',  'e',  'r',  's',  'o',  'n',  '.',  'p',  'r',  'o',  't',  'o',
        0x12, 0x04, 'd',  'e',  'm',  'o',  0x22, 0x22, 0x0a, 0x06, 'P',  'e',  'r',  's',
        'o',  'n',  0x12, 0x0a, 0x0a, 0x02, 'i',  'd',  0x18, 0x01, 0x20, 0x02, 0x28, 0x05,
        0x12, 0x0c, 0x0a, 0x04, 'n',  'a',  'm',  'e',  0x18, 0x02, 0x20, 0x01, 0x28, 0x09,
    };
    try std.testing.expectEqualSlices(u8, expected, bytes);
}

test "descriptor encodes proto3 map entry and editions feature metadata" {
    const allocator = std.testing.allocator;
    const source =
        \\edition = "2023";
        \\package demo;
        \\option features.repeated_field_encoding = EXPANDED;
        \\message Bag { map<string, int32> counts = 1; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();

    const bytes = try encodeFileDescriptorProto(allocator, &file, "bag.proto");
    defer allocator.free(bytes);

    try std.testing.expect(std.mem.indexOf(u8, bytes, "CountsEntry") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "editions") != null);

    var reader = wire.Reader.init(bytes);
    var saw_edition = false;
    while (try reader.nextTag()) |tag| {
        if (tag.number == 14) {
            saw_edition = (try reader.readInt32()) == @intFromEnum(schema.Edition.edition_2023);
        } else {
            try reader.skipValue(tag);
        }
    }
    try std.testing.expect(saw_edition);
}

test "descriptor encodes nested map entry type names with full scope" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\package demo;
        \\message Outer {
        \\  message Inner {
        \\    map<string, int32> tags = 1;
        \\  }
        \\}
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();

    const bytes = try encodeFileDescriptorProto(allocator, &file, "nested-map.proto");
    defer allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, ".demo.Outer.Inner.TagsEntry") != null);

    var decoded = try decodeFileDescriptorProto(allocator, bytes);
    defer decoded.deinit();
    const outer = decoded.findMessage("Outer").?;
    const inner = outer.findMessage("Inner").?;
    const tags = inner.findField("tags").?;
    try std.testing.expect(tags.kind == .map);
    try std.testing.expectEqual(schema.ScalarType.string, tags.kind.map.key);
    try std.testing.expect(tags.kind.map.value.* == .scalar);
    try std.testing.expectEqual(schema.ScalarType.int32, tags.kind.map.value.scalar);
}

test "descriptor encodes nested message and enum type names with full scope" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto2";
        \\package demo;
        \\message Outer {
        \\  message Child { optional int32 id = 1; }
        \\  enum Kind { UNKNOWN = 0; ACTIVE = 1; }
        \\  message Inner {
        \\    optional Child child = 1;
        \\    optional Kind kind = 2 [default = ACTIVE];
        \\    message Local { optional string name = 1; }
        \\    optional Local local = 3;
        \\  }
        \\}
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();

    const bytes = try encodeFileDescriptorProto(allocator, &file, "nested-types.proto");
    defer allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, ".demo.Outer.Child") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, ".demo.Outer.Kind") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, ".demo.Outer.Inner.Local") != null);

    var decoded = try decodeFileDescriptorProto(allocator, bytes);
    defer decoded.deinit();
    const outer = decoded.findMessage("Outer").?;
    const inner = outer.findMessage("Inner").?;
    try std.testing.expectEqualStrings("demo.Outer.Child", inner.findField("child").?.kind.message);
    try std.testing.expectEqualStrings("demo.Outer.Kind", inner.findField("kind").?.kind.enumeration);
    try std.testing.expectEqualStrings("demo.Outer.Inner.Local", inner.findField("local").?.kind.message);
    try std.testing.expectEqual(@as(i64, 1), inner.findField("kind").?.default_value.?.integer);
}

test "descriptor decodes encoded FileDescriptorProto back to schema" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\package demo;
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message Bag {
        \\  oneof pick { string name = 1; int32 id = 2; }
        \\  repeated int32 nums = 3;
        \\  map<string, int32> counts = 4;
        \\  Kind kind = 5;
        \\}
        \\service Bags { rpc Get (Bag) returns (Bag); }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    file.name = "bag.proto";

    const encoded = try encodeFileDescriptorProto(allocator, &file, file.name);
    defer allocator.free(encoded);

    var decoded = try decodeFileDescriptorProto(allocator, encoded);
    defer decoded.deinit();

    try std.testing.expectEqualStrings("bag.proto", decoded.name);
    try std.testing.expectEqualStrings("demo", decoded.package);
    try std.testing.expectEqual(schema.Syntax.proto3, decoded.syntax);
    const bag = decoded.findMessage("Bag").?;
    try std.testing.expectEqual(@as(usize, 5), bag.fields.items.len);
    try std.testing.expectEqual(@as(usize, 1), bag.oneofs.items.len);
    try std.testing.expectEqualStrings("pick", bag.findField("name").?.oneof_name.?);
    try std.testing.expect(bag.findField("counts").?.kind == .map);
    try std.testing.expect(bag.findField("kind").?.kind == .enumeration);
    try std.testing.expectEqual(@as(usize, 1), decoded.services.items.len);
}

fn exerciseFileDescriptorDecodeCleanup(allocator: std.mem.Allocator, encoded: []const u8) !void {
    var decoded = try decodeFileDescriptorProto(allocator, encoded);
    defer decoded.deinit();

    try std.testing.expectEqualStrings("bag.proto", decoded.name);
    try std.testing.expectEqual(@as(usize, 1), decoded.messages.items.len);
    try std.testing.expectEqual(@as(usize, 1), decoded.enums.items.len);
    try std.testing.expectEqual(@as(usize, 1), decoded.services.items.len);
}

test "descriptor decode cleans up allocation failures" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\package demo;
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message Bag {
        \\  oneof pick { string name = 1; int32 id = 2; }
        \\  repeated int32 nums = 3;
        \\  map<string, int32> counts = 4;
        \\  Kind kind = 5;
        \\}
        \\service Bags { rpc Get (Bag) returns (Bag); }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    file.name = "bag.proto";

    const encoded = try encodeFileDescriptorProto(allocator, &file, file.name);
    defer allocator.free(encoded);
    try std.testing.checkAllAllocationFailures(allocator, exerciseFileDescriptorDecodeCleanup, .{encoded});
}

test "descriptor rejects invalid service and method descriptors" {
    const allocator = std.testing.allocator;
    {
        var service = wire.Writer.init(allocator);
        defer service.deinit();
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-service.proto");
        try file.writeMessage(6, service.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var method = wire.Writer.init(allocator);
        defer method.deinit();
        try method.writeString(1, "Get");
        try method.writeString(3, ".demo.Res");
        var service = wire.Writer.init(allocator);
        defer service.deinit();
        try service.writeString(1, "Svc");
        try service.writeMessage(2, method.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-method.proto");
        try file.writeMessage(6, service.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var method = wire.Writer.init(allocator);
        defer method.deinit();
        try method.writeString(1, "Get");
        try method.writeString(2, ".demo.Req");
        try method.writeString(3, ".demo.Res");
        var service = wire.Writer.init(allocator);
        defer service.deinit();
        try service.writeString(1, "Svc");
        try service.writeMessage(2, method.slice());
        try service.writeMessage(2, method.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "dup-method.proto");
        try file.writeMessage(6, service.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        var kind = schema.EnumDescriptor{ .name = "Kind" };
        try kind.values.append(allocator, .{ .name = "UNKNOWN", .number = 0 });
        try file.enums.append(allocator, kind);
        var service = schema.ServiceDescriptor{ .name = "Svc" };
        try service.methods.append(allocator, .{ .name = "Get", .input_type = "Kind", .output_type = "Kind" });
        try file.services.append(allocator, service);
        const bytes = try encodeFileDescriptorProto(allocator, &file, "service-enum-type.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
}

test "descriptor decodes scalar default values with typed option values" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Defaults {
        \\  optional int32 count = 1 [default = 42];
        \\  optional bool enabled = 2 [default = true];
        \\  optional float ratio = 3 [default = 1.5];
        \\  optional string name = 4 [default = "anon"];
        \\  optional bytes raw = 5 [default = "\001\x02"];
        \\  optional double pos_inf = 6 [default = inf];
        \\  optional double neg_inf = 7 [default = -inf];
        \\  optional float quiet_nan = 8 [default = nan];
        \\  optional float neg_nan = 9 [default = -nan];
        \\  optional double pos_infinity = 10 [default = Infinity];
        \\  optional double neg_infinity = 11 [default = -INFINITY];
        \\  optional uint64 max_u64 = 12 [default = 0xFFFFFFFFFFFFFFFF];
        \\  optional fixed64 max_fixed = 13 [default = 18446744073709551615];
        \\}
    );
    defer file.deinit();

    const encoded = try encodeFileDescriptorProto(allocator, &file, "defaults.proto");
    defer allocator.free(encoded);
    try std.testing.expect(std.mem.indexOf(u8, encoded, "\\001\\002") != null);
    var decoded = try decodeFileDescriptorProto(allocator, encoded);
    defer decoded.deinit();
    const msg = decoded.findMessage("Defaults").?;
    try std.testing.expectEqual(@as(i64, 42), msg.findField("count").?.default_value.?.integer);
    try std.testing.expect(msg.findField("enabled").?.default_value.?.boolean);
    try std.testing.expectEqual(@as(f64, 1.5), msg.findField("ratio").?.default_value.?.float);
    try std.testing.expect(std.math.isPositiveInf(msg.findField("pos_inf").?.default_value.?.float));
    try std.testing.expect(std.math.isNegativeInf(msg.findField("neg_inf").?.default_value.?.float));
    try std.testing.expect(std.math.isNan(msg.findField("quiet_nan").?.default_value.?.float));
    try std.testing.expect(std.math.isNan(msg.findField("neg_nan").?.default_value.?.float));
    try std.testing.expect(std.math.isPositiveInf(msg.findField("pos_infinity").?.default_value.?.float));
    try std.testing.expect(std.math.isNegativeInf(msg.findField("neg_infinity").?.default_value.?.float));
    try std.testing.expectEqualSlices(u8, "anon", msg.findField("name").?.default_value.?.string);
    try std.testing.expectEqualSlices(u8, &.{ 0x01, 0x02 }, msg.findField("raw").?.default_value.?.string);
    try std.testing.expectEqual(@as(u64, 18446744073709551615), msg.findField("max_u64").?.default_value.?.unsigned_integer);
    try std.testing.expectEqual(@as(u64, 18446744073709551615), msg.findField("max_fixed").?.default_value.?.unsigned_integer);
}

test "descriptor decodes bytes defaults from C escapes" {
    const allocator = std.testing.allocator;
    var field = wire.Writer.init(allocator);
    defer field.deinit();
    try field.writeString(1, "raw");
    try field.writeInt32(3, 1);
    try field.writeInt32(4, 1);
    try field.writeInt32(5, 12);
    try field.writeString(7, "\\001\\x02\\n\\\\\\\"");
    var message = wire.Writer.init(allocator);
    defer message.deinit();
    try message.writeString(1, "Defaults");
    try message.writeMessage(2, field.slice());
    var file = wire.Writer.init(allocator);
    defer file.deinit();
    try file.writeString(1, "bytes-default.proto");
    try file.writeMessage(4, message.slice());

    var decoded = try decodeFileDescriptorProto(allocator, file.slice());
    defer decoded.deinit();
    const raw = decoded.findMessage("Defaults").?.findField("raw").?.default_value.?.string;
    try std.testing.expectEqualSlices(u8, &.{ 0x01, 0x02, '\n', '\\', '"' }, raw);
}

test "descriptor rejects invalid decoded field defaults" {
    const allocator = std.testing.allocator;
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "id");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 5);
        try field.writeString(7, "not-int");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-int-default.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "id");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 13);
        try field.writeString(7, "-1");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-uint-default.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "enabled");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 8);
        try field.writeString(7, "TRUE");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-bool-default.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "ids");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 3);
        try field.writeInt32(5, 5);
        try field.writeString(7, "1");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-repeated-default.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "child");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 11);
        try field.writeString(6, ".Child");
        try field.writeString(7, "x");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-message-default.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "id");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 5);
        try field.writeString(7, "1");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-proto3-default.proto");
        try file.writeString(12, "proto3");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "raw");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 12);
        try field.writeString(7, "\\x");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-bytes-default.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var value = wire.Writer.init(allocator);
        defer value.deinit();
        try value.writeString(1, "ZERO");
        try value.writeInt32(2, 0);
        var enumeration = wire.Writer.init(allocator);
        defer enumeration.deinit();
        try enumeration.writeString(1, "Kind");
        try enumeration.writeMessage(2, value.slice());
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "kind");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 14);
        try field.writeString(6, ".Kind");
        try field.writeString(7, "MISSING");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-enum-default.proto");
        try file.writeMessage(5, enumeration.slice());
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
}

test "descriptor preserves proto2 group fields and nested group messages" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Parent {
        \\  optional group Legacy = 1 { optional int32 id = 2; }
        \\  repeated group Items = 3 { optional string name = 4; }
        \\}
    );
    defer file.deinit();

    const encoded = try encodeFileDescriptorProto(allocator, &file, "groups.proto");
    defer allocator.free(encoded);
    var decoded = try decodeFileDescriptorProto(allocator, encoded);
    defer decoded.deinit();

    const parent = decoded.findMessage("Parent").?;
    const legacy = parent.findField("legacy").?;
    try std.testing.expect(legacy.kind == .group);
    try std.testing.expectEqualStrings("Legacy", legacy.kind.group);
    try std.testing.expectEqual(schema.Cardinality.optional, legacy.cardinality);
    const items = parent.findField("items").?;
    try std.testing.expect(items.kind == .group);
    try std.testing.expectEqualStrings("Items", items.kind.group);
    try std.testing.expectEqual(schema.Cardinality.repeated, items.cardinality);

    const legacy_msg = parent.findMessage("Legacy").?;
    try std.testing.expect(legacy_msg.findField("id").?.kind == .scalar);
    try std.testing.expectEqual(schema.ScalarType.int32, legacy_msg.findField("id").?.kind.scalar);
    const items_msg = parent.findMessage("Items").?;
    try std.testing.expect(items_msg.findField("name").?.kind == .scalar);
    try std.testing.expectEqual(schema.ScalarType.string, items_msg.findField("name").?.kind.scalar);
}

test "descriptor rejects group names not starting with capital letter" {
    const allocator = std.testing.allocator;
    var field = wire.Writer.init(allocator);
    defer field.deinit();
    try field.writeString(1, "legacy");
    try field.writeInt32(3, 1);
    try field.writeInt32(4, 1);
    try field.writeInt32(5, 10);
    try field.writeString(6, ".Bad.legacy");
    var nested = wire.Writer.init(allocator);
    defer nested.deinit();
    try nested.writeString(1, "legacy");
    var message = wire.Writer.init(allocator);
    defer message.deinit();
    try message.writeString(1, "Bad");
    try message.writeMessage(2, field.slice());
    try message.writeMessage(3, nested.slice());
    var file = wire.Writer.init(allocator);
    defer file.deinit();
    try file.writeString(1, "bad-group-name.proto");
    try file.writeString(12, "proto2");
    try file.writeMessage(4, message.slice());
    try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
}

test "descriptor rejects legacy group fields under editions" {
    const allocator = std.testing.allocator;
    var field = wire.Writer.init(allocator);
    defer field.deinit();
    try field.writeString(1, "Legacy");
    try field.writeInt32(3, 1);
    try field.writeInt32(4, 1);
    try field.writeInt32(5, 10);
    try field.writeString(6, ".Bad.Legacy");
    var message = wire.Writer.init(allocator);
    defer message.deinit();
    try message.writeString(1, "Bad");
    try message.writeMessage(2, field.slice());
    var file = wire.Writer.init(allocator);
    defer file.deinit();
    try file.writeString(1, "editions-group.proto");
    try file.writeString(12, "editions");
    try file.writeInt32(14, @intFromEnum(schema.Edition.edition_2023));
    try file.writeMessage(4, message.slice());
    try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
}

test "descriptor encodes enum defaults using enum value names" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\enum Kind { UNKNOWN = 0; ADMIN = 7; }
        \\message Defaults { optional Kind kind = 1 [default = ADMIN]; }
    );
    defer file.deinit();
    const field = file.findMessage("Defaults").?.findField("kind").?;
    const default_text = try defaultValueText(allocator, &file, field.kind, field.default_value.?);
    defer allocator.free(default_text);
    try std.testing.expectEqualStrings("ADMIN", default_text);

    const encoded = try encodeFileDescriptorProto(allocator, &file, "enum-default.proto");
    defer allocator.free(encoded);
    var decoded = try decodeFileDescriptorProto(allocator, encoded);
    defer decoded.deinit();
    try std.testing.expectEqual(@as(i64, 7), decoded.findMessage("Defaults").?.findField("kind").?.default_value.?.integer);
}

test "descriptor set encodes imported enum numeric defaults using names" {
    const allocator = std.testing.allocator;
    var common = schema.FileDescriptor.init(allocator);
    defer common.deinit();
    common.setSyntax(.proto2);
    common.name = "common.proto";
    common.package = "common";
    var kind = schema.EnumDescriptor{ .name = "Kind" };
    try kind.values.append(allocator, .{ .name = "UNKNOWN", .number = 0 });
    try kind.values.append(allocator, .{ .name = "ADMIN", .number = 7 });
    try common.enums.append(allocator, kind);

    var app = schema.FileDescriptor.init(allocator);
    defer app.deinit();
    app.setSyntax(.proto2);
    app.name = "app.proto";
    app.package = "app";
    try app.imports.append(allocator, .{ .path = "common.proto" });
    var event = schema.MessageDescriptor{ .name = "Event" };
    try event.fields.append(allocator, .{
        .name = "kind",
        .number = 1,
        .cardinality = .optional,
        .kind = .{ .enumeration = "common.Kind" },
        .default_value = .{ .integer = 7 },
    });
    try app.messages.append(allocator, event);

    const files = [_]*const schema.FileDescriptor{ &common, &app };
    const bytes = try encodeFileDescriptorSet(allocator, &files);
    defer allocator.free(bytes);

    const decoded_files = try decodeFileDescriptorSet(allocator, bytes);
    defer {
        for (decoded_files) |*file| file.deinit();
        allocator.free(decoded_files);
    }
    const decoded_default = decoded_files[1].findMessage("Event").?.findField("kind").?.default_value.?;
    try std.testing.expectEqualStrings("ADMIN", decoded_default.identifier);
}

test "descriptor set rejects extension declaration and MessageSet shape violations" {
    const allocator = std.testing.allocator;
    var host = schema.FileDescriptor.init(allocator);
    defer host.deinit();
    host.setSyntax(.proto2);
    host.name = "host.proto";
    host.package = "demo";
    var host_msg = schema.MessageDescriptor{ .name = "Host" };
    var declared_range = schema.ExtensionRange{ .start = 100, .end = 200, .verification = .declaration };
    try declared_range.declarations.append(allocator, .{ .number = 100, .full_name = ".demo.ext", .type_name = ".demo.Ext" });
    try host_msg.extension_ranges.append(allocator, declared_range);
    try host.messages.append(allocator, host_msg);
    try host.messages.append(allocator, .{ .name = "Ext" });

    var wrong = schema.FileDescriptor.init(allocator);
    defer wrong.deinit();
    wrong.setSyntax(.proto2);
    wrong.name = "wrong.proto";
    wrong.package = "demo";
    try wrong.imports.append(allocator, .{ .path = "host.proto" });
    try wrong.extensions.append(allocator, .{ .name = "wrong", .number = 100, .cardinality = .optional, .kind = .{ .message = "Ext" }, .extendee = "Host" });

    const declaration_files = [_]*const schema.FileDescriptor{ &host, &wrong };
    const declaration_bytes = try encodeFileDescriptorSet(allocator, &declaration_files);
    defer allocator.free(declaration_bytes);
    try std.testing.expectError(error.InvalidExtensionDeclaration, decodeFileDescriptorSet(allocator, declaration_bytes));

    var ms_host = schema.FileDescriptor.init(allocator);
    defer ms_host.deinit();
    ms_host.setSyntax(.proto2);
    ms_host.name = "messageset-host.proto";
    ms_host.package = "demo.ms";
    var message_set = schema.MessageDescriptor{ .name = "Host" };
    try message_set.options.append(allocator, .{ .name = "message_set_wire_format", .value = .{ .boolean = true } });
    try message_set.extension_ranges.append(allocator, .{ .start = 4, .end = null });
    try ms_host.messages.append(allocator, message_set);

    var ms_ext = schema.FileDescriptor.init(allocator);
    defer ms_ext.deinit();
    ms_ext.setSyntax(.proto2);
    ms_ext.name = "messageset-ext.proto";
    ms_ext.package = "demo.ms";
    try ms_ext.imports.append(allocator, .{ .path = "messageset-host.proto" });
    try ms_ext.extensions.append(allocator, .{ .name = "bad", .number = 100, .cardinality = .optional, .kind = .{ .scalar = .int32 }, .extendee = "Host" });

    const messageset_files = [_]*const schema.FileDescriptor{ &ms_host, &ms_ext };
    const messageset_bytes = try encodeFileDescriptorSet(allocator, &messageset_files);
    defer allocator.free(messageset_bytes);
    try std.testing.expectError(error.InvalidExtensionDeclaration, decodeFileDescriptorSet(allocator, messageset_bytes));
}

test "descriptor set encodes imported extension extendees with resolved package" {
    const allocator = std.testing.allocator;
    var host = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host { extensions 100 to max; }
    );
    defer host.deinit();
    host.name = "host.proto";

    var extension = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package other;
        \\import "host.proto";
        \\extend demo.Host { optional string note = 100; }
    );
    defer extension.deinit();
    extension.name = "extension.proto";

    const files = [_]*const schema.FileDescriptor{ &host, &extension };
    const bytes = try encodeFileDescriptorSet(allocator, &files);
    defer allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, ".demo.Host") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, ".other.demo.Host") == null);

    const decoded_files = try decodeFileDescriptorSet(allocator, bytes);
    defer {
        for (decoded_files) |*file| file.deinit();
        allocator.free(decoded_files);
    }
    try std.testing.expectEqual(@as(usize, 2), decoded_files.len);
    try std.testing.expectEqualStrings(".demo.Host", decoded_files[1].extensions.items[0].extendee.?);
}

test "descriptor set rejects duplicate file names" {
    const allocator = std.testing.allocator;
    var first = schema.FileDescriptor.init(allocator);
    defer first.deinit();
    first.setSyntax(.proto2);
    first.name = "same.proto";
    try first.messages.append(allocator, .{ .name = "First" });

    var second = schema.FileDescriptor.init(allocator);
    defer second.deinit();
    second.setSyntax(.proto2);
    second.name = "same.proto";
    try second.messages.append(allocator, .{ .name = "Second" });

    const files = [_]*const schema.FileDescriptor{ &first, &second };
    const bytes = try encodeFileDescriptorSet(allocator, &files);
    defer allocator.free(bytes);
    try std.testing.expectError(error.DuplicateSymbol, decodeFileDescriptorSet(allocator, bytes));
}

test "descriptor set rejects duplicate symbols and extension conflicts" {
    const allocator = std.testing.allocator;
    var first = schema.FileDescriptor.init(allocator);
    defer first.deinit();
    first.setSyntax(.proto2);
    first.name = "first.proto";
    first.package = "dup";
    try first.messages.append(allocator, .{ .name = "User" });

    var second = schema.FileDescriptor.init(allocator);
    defer second.deinit();
    second.setSyntax(.proto2);
    second.name = "second.proto";
    second.package = "dup";
    try second.messages.append(allocator, .{ .name = "User" });

    const duplicate_files = [_]*const schema.FileDescriptor{ &first, &second };
    const duplicate_bytes = try encodeFileDescriptorSet(allocator, &duplicate_files);
    defer allocator.free(duplicate_bytes);
    try std.testing.expectError(error.DuplicateSymbol, decodeFileDescriptorSet(allocator, duplicate_bytes));

    var host = schema.FileDescriptor.init(allocator);
    defer host.deinit();
    host.setSyntax(.proto2);
    host.name = "host.proto";
    host.package = "demo";
    var host_msg = schema.MessageDescriptor{ .name = "Host" };
    try host_msg.extension_ranges.append(allocator, .{ .start = 100, .end = 200 });
    try host.messages.append(allocator, host_msg);

    var ext_a = schema.FileDescriptor.init(allocator);
    defer ext_a.deinit();
    ext_a.setSyntax(.proto2);
    ext_a.name = "ext-a.proto";
    ext_a.package = "demo";
    try ext_a.imports.append(allocator, .{ .path = "host.proto" });
    try ext_a.extensions.append(allocator, .{ .name = "first", .number = 100, .cardinality = .optional, .kind = .{ .scalar = .int32 }, .extendee = "Host" });

    var ext_b = schema.FileDescriptor.init(allocator);
    defer ext_b.deinit();
    ext_b.setSyntax(.proto2);
    ext_b.name = "ext-b.proto";
    ext_b.package = "demo";
    try ext_b.imports.append(allocator, .{ .path = "host.proto" });
    try ext_b.extensions.append(allocator, .{ .name = "second", .number = 100, .cardinality = .optional, .kind = .{ .scalar = .int32 }, .extendee = "Host" });

    const extension_files = [_]*const schema.FileDescriptor{ &host, &ext_a, &ext_b };
    const extension_bytes = try encodeFileDescriptorSet(allocator, &extension_files);
    defer allocator.free(extension_bytes);
    try std.testing.expectError(error.DuplicateSymbol, decodeFileDescriptorSet(allocator, extension_bytes));
}

test "descriptor set allows unresolved types from missing weak imports" {
    const allocator = std.testing.allocator;
    var weak = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package weakpkg;
        \\import weak "missing.proto";
        \\message Root { optional MissingType field = 1; }
        \\service Api { rpc Get (MissingRequest) returns (Root); }
    );
    defer weak.deinit();
    weak.name = "weak.proto";

    const weak_files = [_]*const schema.FileDescriptor{&weak};
    const weak_bytes = try encodeFileDescriptorSet(allocator, &weak_files);
    defer allocator.free(weak_bytes);
    const decoded_weak = try decodeFileDescriptorSet(allocator, weak_bytes);
    defer {
        for (decoded_weak) |*file| file.deinit();
        allocator.free(decoded_weak);
    }
    try std.testing.expectEqual(@as(usize, 1), decoded_weak.len);
    try std.testing.expectEqual(@as(usize, 1), decoded_weak[0].missing_weak_imports.items.len);
    try std.testing.expectEqualStrings("missing.proto", decoded_weak[0].missing_weak_imports.items[0]);

    var normal = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package weakpkg;
        \\import "missing.proto";
        \\message Root { optional MissingType field = 1; }
    );
    defer normal.deinit();
    normal.name = "normal.proto";

    const normal_files = [_]*const schema.FileDescriptor{&normal};
    const normal_bytes = try encodeFileDescriptorSet(allocator, &normal_files);
    defer allocator.free(normal_bytes);
    try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorSet(allocator, normal_bytes));
}

test "descriptor set validates local enum defaults before imported enums" {
    const allocator = std.testing.allocator;
    var common = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\enum Kind { UNKNOWN = 0; IMPORTED = 1; }
    );
    defer common.deinit();
    common.name = "common.proto";
    var app = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\import "common.proto";
        \\message Event {
        \\  enum Kind { LOCAL = 7; }
        \\  optional Kind kind = 1 [default = LOCAL];
        \\}
    );
    defer app.deinit();
    app.name = "app.proto";

    const files = [_]*const schema.FileDescriptor{ &common, &app };
    const bytes = try encodeFileDescriptorSet(allocator, &files);
    defer allocator.free(bytes);
    const decoded = try decodeFileDescriptorSet(allocator, bytes);
    defer {
        for (decoded) |*file| file.deinit();
        allocator.free(decoded);
    }
    const decoded_app = for (decoded) |*file| {
        if (std.mem.eql(u8, file.name, "app.proto")) break file;
    } else return error.InvalidFieldType;
    const kind = decoded_app.findMessage("Event").?.findField("kind").?;
    try std.testing.expectEqualStrings("demo.Event.Kind", kind.kind.enumeration);
    try std.testing.expectEqual(@as(i64, 7), kind.default_value.?.integer);
}

test "descriptor encodes imported enum fields and defaults with registry" {
    const allocator = std.testing.allocator;
    var common = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package common;
        \\enum Kind { UNKNOWN = 0; ADMIN = 7; }
        \\message Req { optional string id = 1; }
    );
    defer common.deinit();
    common.name = "common.proto";
    var app = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package app;
        \\import "common.proto";
        \\message Event {
        \\  optional common.Kind kind = 1 [default = ADMIN];
        \\  map<string, common.Kind> keyed = 2;
        \\}
        \\service Api { rpc Get (common.Req) returns (Event); }
    );
    defer app.deinit();
    app.name = "app.proto";
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);
    try registry.validateAllFileReferences();

    try std.testing.expectError(error.InvalidFieldType, encodeFileDescriptorProto(allocator, &app, "app.proto"));

    const app_bytes = try encodeFileDescriptorProtoWithRegistry(allocator, &app, &registry, "app.proto");
    defer allocator.free(app_bytes);
    var decoded_app = try decodeFileDescriptorProto(allocator, app_bytes);
    defer decoded_app.deinit();
    const decoded_event = decoded_app.findMessage("Event").?;
    const decoded_kind = decoded_event.findField("kind").?;
    try std.testing.expectEqualStrings("common.Kind", decoded_kind.kind.enumeration);
    try std.testing.expectEqualStrings("ADMIN", decoded_kind.default_value.?.identifier);
    const decoded_keyed = decoded_event.findField("keyed").?;
    try std.testing.expectEqualStrings("common.Kind", decoded_keyed.kind.map.value.enumeration);

    const files = [_]*const schema.FileDescriptor{ &common, &app };
    const set_bytes = try encodeFileDescriptorSet(allocator, &files);
    defer allocator.free(set_bytes);
    const decoded_files = try decodeFileDescriptorSet(allocator, set_bytes);
    defer {
        for (decoded_files) |*file| file.deinit();
        allocator.free(decoded_files);
    }
    const set_app = for (decoded_files) |*file| {
        if (std.mem.eql(u8, file.name, "app.proto")) break file;
    } else return error.InvalidFieldType;
    const set_kind = set_app.findMessage("Event").?.findField("kind").?;
    try std.testing.expectEqualStrings("common.Kind", set_kind.kind.enumeration);
    try std.testing.expectEqualStrings("ADMIN", set_kind.default_value.?.identifier);
    try std.testing.expectEqualStrings("common.Req", set_app.services.items[0].methods.items[0].input_type);

    var missing_type = schema.FileDescriptor.init(allocator);
    defer missing_type.deinit();
    missing_type.setSyntax(.proto2);
    missing_type.name = "missing-type.proto";
    var missing_event = schema.MessageDescriptor{ .name = "Event" };
    try missing_event.fields.append(allocator, .{
        .name = "missing",
        .number = 1,
        .cardinality = .optional,
        .kind = .{ .message = "MissingType" },
    });
    try missing_type.messages.append(allocator, missing_event);
    const missing_files = [_]*const schema.FileDescriptor{&missing_type};
    const missing_set_bytes = try encodeFileDescriptorSet(allocator, &missing_files);
    defer allocator.free(missing_set_bytes);
    try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorSet(allocator, missing_set_bytes));

    var bad_common = schema.FileDescriptor.init(allocator);
    defer bad_common.deinit();
    bad_common.setSyntax(.proto2);
    bad_common.name = "bad-common.proto";
    bad_common.package = "common";
    var kind = schema.EnumDescriptor{ .name = "Kind" };
    try kind.values.append(allocator, .{ .name = "UNKNOWN", .number = 0 });
    try kind.values.append(allocator, .{ .name = "ADMIN", .number = 7 });
    try bad_common.enums.append(allocator, kind);

    var bad_app = schema.FileDescriptor.init(allocator);
    defer bad_app.deinit();
    bad_app.setSyntax(.proto2);
    bad_app.name = "bad-app.proto";
    bad_app.package = "app";
    try bad_app.imports.append(allocator, .{ .path = "bad-common.proto" });
    var bad_event = schema.MessageDescriptor{ .name = "Event" };
    try bad_event.fields.append(allocator, .{
        .name = "kind",
        .number = 1,
        .cardinality = .optional,
        .kind = .{ .enumeration = "common.Kind" },
        .default_value = .{ .identifier = "MISSING" },
    });
    try bad_app.messages.append(allocator, bad_event);
    const bad_files = [_]*const schema.FileDescriptor{ &bad_common, &bad_app };
    const bad_set_bytes = try encodeFileDescriptorSet(allocator, &bad_files);
    defer allocator.free(bad_set_bytes);
    try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorSet(allocator, bad_set_bytes));

    var bad_service = schema.FileDescriptor.init(allocator);
    defer bad_service.deinit();
    bad_service.setSyntax(.proto2);
    bad_service.name = "bad-service.proto";
    bad_service.package = "svc";
    var bad_service_desc = schema.ServiceDescriptor{ .name = "Bad" };
    try bad_service_desc.methods.append(allocator, .{ .name = "Get", .input_type = "MissingRequest", .output_type = "MissingResponse" });
    try bad_service.services.append(allocator, bad_service_desc);
    const bad_service_files = [_]*const schema.FileDescriptor{&bad_service};
    const bad_service_set_bytes = try encodeFileDescriptorSet(allocator, &bad_service_files);
    defer allocator.free(bad_service_set_bytes);
    try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorSet(allocator, bad_service_set_bytes));
}

test "descriptor decodes FileDescriptorSet" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto2";
        \\package demo;
        \\message A { optional string s = 1; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    file.name = "a.proto";
    const files = [_]*const schema.FileDescriptor{&file};
    const set_bytes = try encodeFileDescriptorSet(allocator, &files);
    defer allocator.free(set_bytes);

    const decoded_files = try decodeFileDescriptorSet(allocator, set_bytes);
    defer {
        for (decoded_files) |*decoded_file| decoded_file.deinit();
        allocator.free(decoded_files);
    }
    try std.testing.expectEqual(@as(usize, 1), decoded_files.len);
    try std.testing.expectEqualStrings("a.proto", decoded_files[0].name);
    try std.testing.expect(decoded_files[0].findMessage("A") != null);
}

test "descriptor encodes and decodes FeatureSetDefaults" {
    const allocator = std.testing.allocator;
    var defaults = schema.FeatureSetDefaults{};
    defer defaults.deinit(allocator);
    try defaults.defaults.append(allocator, .{
        .edition = .legacy,
        .overridable_features = schema.FeatureSet.defaults(.proto2),
        .fixed_features = .{ .enforce_naming_style = .style_legacy },
    });
    try defaults.defaults.append(allocator, .{
        .edition = .edition_2023,
        .overridable_features = schema.FeatureSet.defaults(.editions),
        .fixed_features = .{ .json_format = .allow },
    });
    defaults.minimum_edition = .legacy;
    defaults.maximum_edition = .edition_2026;

    const bytes = try encodeFeatureSetDefaults(allocator, &defaults);
    defer allocator.free(bytes);
    var decoded = try decodeFeatureSetDefaults(allocator, bytes);
    defer decoded.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), decoded.defaults.items.len);
    try std.testing.expectEqual(schema.Edition.legacy, decoded.defaults.items[0].edition);
    try std.testing.expectEqual(schema.FeatureSet.EnumType.closed, decoded.defaults.items[0].overridable_features.?.enum_type);
    try std.testing.expectEqual(schema.FeatureSet.RepeatedFieldEncoding.expanded, decoded.defaults.items[0].overridable_features.?.repeated_field_encoding);
    try std.testing.expectEqual(schema.FeatureSet.EnforceNamingStyle.style_legacy, decoded.defaults.items[0].fixed_features.?.enforce_naming_style);
    try std.testing.expectEqual(schema.Edition.edition_2023, decoded.defaults.items[1].edition);
    try std.testing.expectEqual(schema.FeatureSet.EnumType.open, decoded.defaults.items[1].overridable_features.?.enum_type);
    try std.testing.expectEqual(schema.FeatureSet.JsonFormat.allow, decoded.defaults.items[1].fixed_features.?.json_format);
    try std.testing.expectEqual(schema.Edition.legacy, decoded.minimum_edition.?);
    try std.testing.expectEqual(schema.Edition.edition_2026, decoded.maximum_edition.?);
}

test "descriptor rejects invalid FeatureSetDefaults" {
    const allocator = std.testing.allocator;
    {
        var entry = wire.Writer.init(allocator);
        defer entry.deinit();
        try entry.writeInt32(3, @intFromEnum(schema.Edition.edition_2023));
        var writer = wire.Writer.init(allocator);
        defer writer.deinit();
        try writer.writeMessage(1, entry.slice());
        try writer.writeMessage(1, entry.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFeatureSetDefaults(allocator, writer.slice()));
    }
    {
        var writer = wire.Writer.init(allocator);
        defer writer.deinit();
        try writer.writeInt32(4, @intFromEnum(schema.Edition.edition_2026));
        try writer.writeInt32(5, @intFromEnum(schema.Edition.edition_2023));
        try std.testing.expectError(error.InvalidFieldType, decodeFeatureSetDefaults(allocator, writer.slice()));
    }
    {
        var writer = wire.Writer.init(allocator);
        defer writer.deinit();
        try writer.writeInt32(4, @intFromEnum(schema.Edition.unknown));
        try std.testing.expectError(error.InvalidFieldType, decodeFeatureSetDefaults(allocator, writer.slice()));
    }
    {
        var writer = wire.Writer.init(allocator);
        defer writer.deinit();
        try writer.writeInt32(5, @intFromEnum(schema.Edition.unknown));
        try std.testing.expectError(error.InvalidFieldType, decodeFeatureSetDefaults(allocator, writer.slice()));
    }
}

test "descriptor rejects invalid decoded FeatureSet enum values" {
    const allocator = std.testing.allocator;
    inline for (.{
        .{ 1, 99, "bad-field-presence-feature.proto" },
        .{ 2, 99, "bad-enum-type-feature.proto" },
        .{ 3, 99, "bad-repeated-encoding-feature.proto" },
        .{ 4, 1, "bad-utf8-validation-feature.proto" },
        .{ 5, 99, "bad-message-encoding-feature.proto" },
        .{ 6, 99, "bad-json-format-feature.proto" },
        .{ 7, 99, "bad-naming-style-feature.proto" },
        .{ 8, 99, "bad-visibility-feature.proto" },
        .{ 9, 99, "bad-proto-limits-feature.proto" },
    }) |case| {
        var features = wire.Writer.init(allocator);
        defer features.deinit();
        try features.writeInt32(case[0], case[1]);
        var options = wire.Writer.init(allocator);
        defer options.deinit();
        try options.writeMessage(50, features.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, case[2]);
        try file.writeMessage(8, options.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
}

test "descriptor rejects FeatureSet options outside editions" {
    const allocator = std.testing.allocator;
    {
        var features = wire.Writer.init(allocator);
        defer features.deinit();
        try features.writeInt32(1, 2);
        var options = wire.Writer.init(allocator);
        defer options.deinit();
        try options.writeMessage(50, features.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "proto2-file-features.proto");
        try file.writeString(12, "proto2");
        try file.writeMessage(8, options.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var features = wire.Writer.init(allocator);
        defer features.deinit();
        try features.writeInt32(4, 1);
        var options = wire.Writer.init(allocator);
        defer options.deinit();
        try options.writeMessage(21, features.slice());
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "name");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 9);
        try field.writeMessage(8, options.slice());
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "M");
        try message.writeMessage(2, field.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "proto3-field-features.proto");
        try file.writeString(12, "proto3");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
}

test "descriptor rejects invalid synthetic map entry key type" {
    const allocator = std.testing.allocator;
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto3);
        var msg = schema.MessageDescriptor{ .name = "Bad" };
        try msg.fields.append(allocator, .{ .name = "bad", .number = 1, .cardinality = .repeated, .kind = .{ .message = "Bad.BadEntry" } });
        var entry = schema.MessageDescriptor{ .name = "BadEntry", .map_entry = true };
        try entry.fields.append(allocator, .{ .name = "key", .number = 1, .kind = .{ .scalar = .bytes } });
        try entry.fields.append(allocator, .{ .name = "value", .number = 2, .kind = .{ .scalar = .int32 } });
        try msg.messages.append(allocator, entry);
        try file.messages.append(allocator, msg);

        const bytes = try encodeFileDescriptorProto(allocator, &file, "bad.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto3);
        var msg = schema.MessageDescriptor{ .name = "Bad" };
        try msg.fields.append(allocator, .{ .name = "bad", .number = 1, .cardinality = .repeated, .kind = .{ .message = "Bad.BadEntry" } });
        var entry = schema.MessageDescriptor{ .name = "BadEntry", .map_entry = true };
        try entry.fields.append(allocator, .{ .name = "key", .number = 1, .cardinality = .repeated, .kind = .{ .scalar = .string } });
        try entry.fields.append(allocator, .{ .name = "value", .number = 2, .kind = .{ .scalar = .int32 } });
        try msg.messages.append(allocator, entry);
        try file.messages.append(allocator, msg);

        const bytes = try encodeFileDescriptorProto(allocator, &file, "bad-map-label.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto3);
        var msg = schema.MessageDescriptor{ .name = "Bad" };
        try msg.fields.append(allocator, .{ .name = "bad", .number = 1, .cardinality = .repeated, .kind = .{ .message = "Bad.BadEntry" } });
        var entry = schema.MessageDescriptor{ .name = "BadEntry", .map_entry = true };
        try entry.fields.append(allocator, .{ .name = "key", .number = 1, .kind = .{ .scalar = .string } });
        try entry.fields.append(allocator, .{ .name = "value", .number = 2, .kind = .{ .scalar = .int32 } });
        try entry.messages.append(allocator, .{ .name = "Extra" });
        try msg.messages.append(allocator, entry);
        try file.messages.append(allocator, msg);

        const bytes = try encodeFileDescriptorProto(allocator, &file, "bad-map-extra.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto3);
        var msg = schema.MessageDescriptor{ .name = "Bad" };
        try msg.fields.append(allocator, .{ .name = "wrong_name", .number = 1, .cardinality = .repeated, .kind = .{ .message = "Bad.BadEntry" } });
        var entry = schema.MessageDescriptor{ .name = "BadEntry", .map_entry = true };
        try entry.fields.append(allocator, .{ .name = "key", .number = 1, .kind = .{ .scalar = .string } });
        try entry.fields.append(allocator, .{ .name = "value", .number = 2, .kind = .{ .scalar = .int32 } });
        try msg.messages.append(allocator, entry);
        try file.messages.append(allocator, msg);

        const bytes = try encodeFileDescriptorProto(allocator, &file, "bad-map-entry-name.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto3);
        var entry = schema.MessageDescriptor{ .name = "TopEntry", .map_entry = true };
        try entry.fields.append(allocator, .{ .name = "key", .number = 1, .kind = .{ .scalar = .string } });
        try entry.fields.append(allocator, .{ .name = "value", .number = 2, .kind = .{ .scalar = .int32 } });
        try file.messages.append(allocator, entry);

        const bytes = try encodeFileDescriptorProto(allocator, &file, "top-map-entry.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
}

test "descriptor preserves non map nested Entry messages" {
    const allocator = std.testing.allocator;
    var file = schema.FileDescriptor.init(allocator);
    defer file.deinit();
    file.setSyntax(.proto3);
    var host = schema.MessageDescriptor{ .name = "Host" };
    try host.fields.append(allocator, .{ .name = "entry", .number = 1, .cardinality = .optional, .kind = .{ .message = "Host.Entry" } });
    var entry = schema.MessageDescriptor{ .name = "Entry" };
    try entry.fields.append(allocator, .{ .name = "key", .number = 1, .kind = .{ .scalar = .string } });
    try entry.fields.append(allocator, .{ .name = "value", .number = 2, .kind = .{ .scalar = .int32 } });
    try host.messages.append(allocator, entry);
    try file.messages.append(allocator, host);

    const bytes = try encodeFileDescriptorProto(allocator, &file, "entry.proto");
    defer allocator.free(bytes);
    var decoded = try decodeFileDescriptorProto(allocator, bytes);
    defer decoded.deinit();
    const decoded_host = decoded.findMessage("Host").?;
    try std.testing.expect(decoded_host.findField("entry").?.kind == .message);
    try std.testing.expect(decoded_host.findMessage("Entry") != null);
}

test "descriptor rejects invalid field labels" {
    const allocator = std.testing.allocator;
    var field = wire.Writer.init(allocator);
    defer field.deinit();
    try field.writeString(1, "bad");
    try field.writeInt32(3, 1);
    try field.writeInt32(4, 99);
    try field.writeInt32(5, 5);

    var message = wire.Writer.init(allocator);
    defer message.deinit();
    try message.writeString(1, "Bad");
    try message.writeMessage(2, field.slice());

    var file = wire.Writer.init(allocator);
    defer file.deinit();
    try file.writeString(1, "bad-label.proto");
    try file.writeMessage(4, message.slice());
    try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
}

test "descriptor rejects invalid decoded packed options" {
    const allocator = std.testing.allocator;
    inline for (.{
        .{ 1, 5, "optional-packed.proto", "proto2" },
        .{ 3, 9, "string-packed.proto", "proto2" },
        .{ 3, 5, "editions-packed.proto", "editions" },
    }) |case| {
        var options = wire.Writer.init(allocator);
        defer options.deinit();
        try options.writeBool(2, true);
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "bad");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, case[0]);
        try field.writeInt32(5, case[1]);
        try field.writeMessage(8, options.slice());

        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());

        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, case[2]);
        try file.writeString(12, case[3]);
        if (std.mem.eql(u8, case[3], "editions")) try file.writeInt32(14, @intFromEnum(schema.Edition.edition_2023));
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
}

test "descriptor rejects invalid decoded field option applicability" {
    const allocator = std.testing.allocator;
    inline for (.{ .{ 6, "bad-jstype.proto" }, .{ 5, "bad-lazy.proto" }, .{ 10, "bad-weak-scalar.proto" } }) |case| {
        var options = wire.Writer.init(allocator);
        defer options.deinit();
        if (case[0] == 6) {
            try options.writeInt32(6, 1);
        } else if (case[0] == 10) {
            try options.writeBool(10, true);
        } else {
            try options.writeBool(5, true);
        }
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "id");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 5);
        try field.writeMessage(8, options.slice());
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, case[1]);
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var options = wire.Writer.init(allocator);
        defer options.deinit();
        try options.writeBool(10, true);
        var child = wire.Writer.init(allocator);
        defer child.deinit();
        try child.writeString(1, "Child");
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "children");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 3);
        try field.writeInt32(5, 11);
        try field.writeString(6, ".Child");
        try field.writeMessage(8, options.slice());
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-weak-repeated.proto");
        try file.writeMessage(4, child.slice());
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var options = wire.Writer.init(allocator);
        defer options.deinit();
        try options.writeInt32(1, 1);
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "data");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 12);
        try field.writeMessage(8, options.slice());
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-edition-ctype.proto");
        try file.writeString(12, "editions");
        try file.writeInt32(14, @intFromEnum(schema.Edition.edition_2024));
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var options = wire.Writer.init(allocator);
        defer options.deinit();
        try options.writeBool(15, true);
        var host = wire.Writer.init(allocator);
        defer host.deinit();
        try host.writeString(1, "Host");
        var range = wire.Writer.init(allocator);
        defer range.deinit();
        try range.writeInt32(1, 100);
        try range.writeInt32(2, 200);
        try host.writeMessage(5, range.slice());
        var ext = wire.Writer.init(allocator);
        defer ext.deinit();
        try ext.writeString(1, "Ext");
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "ext");
        try field.writeString(2, ".Host");
        try field.writeInt32(3, 100);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 11);
        try field.writeString(6, ".Ext");
        try field.writeMessage(8, options.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-unverified-lazy-extension.proto");
        try file.writeMessage(4, host.slice());
        try file.writeMessage(4, ext.slice());
        try file.writeMessage(7, field.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
}

test "descriptor rejects missing type names for message enum and group fields" {
    const allocator = std.testing.allocator;
    inline for (.{ 10, 11, 14 }) |field_type| {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "bad");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, field_type);

        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());

        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-type-name.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
}

test "descriptor rejects invalid field numbers" {
    const allocator = std.testing.allocator;
    inline for (.{ 0, -1, 19000 }) |bad_number| {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "bad");
        try field.writeInt32(3, bad_number);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 5);

        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());

        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-number.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldNumber, decodeFileDescriptorProto(allocator, file.slice()));
    }
}

test "descriptor decoded schema owns descriptor bytes" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto2";
        \\package own;
        \\message Owned { optional string value = 1; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    var bytes = try encodeFileDescriptorProto(allocator, &file, "owned.proto");
    var decoded = try decodeFileDescriptorProto(allocator, bytes);
    allocator.free(bytes);
    bytes = &.{};
    defer decoded.deinit();

    try std.testing.expectEqualStrings("own", decoded.package);
    try std.testing.expectEqualStrings("Owned", decoded.findMessage("Owned").?.name);
    try std.testing.expectEqualStrings("value", decoded.findMessage("Owned").?.findField("value").?.name);
}

const ExpectedNamePart = struct {
    name: []const u8,
    is_extension: bool,
};

fn expectFirstFileOptionNameParts(file_bytes: []const u8, expected: []const ExpectedNamePart) !void {
    var file_reader = wire.Reader.init(file_bytes);
    while (try file_reader.nextTag()) |file_tag| {
        if (file_tag.number == 8) {
            var options_reader = wire.Reader.init(try file_reader.readBytes());
            while (try options_reader.nextTag()) |options_tag| {
                if (options_tag.number == 999) {
                    var option_reader = wire.Reader.init(try options_reader.readBytes());
                    var index: usize = 0;
                    while (try option_reader.nextTag()) |option_tag| {
                        if (option_tag.number == 2) {
                            try std.testing.expect(index < expected.len);
                            const actual = try readTestNamePart(try option_reader.readBytes());
                            try std.testing.expectEqualStrings(expected[index].name, actual.name);
                            try std.testing.expectEqual(expected[index].is_extension, actual.is_extension);
                            index += 1;
                        } else try option_reader.skipValue(option_tag);
                    }
                    try std.testing.expectEqual(expected.len, index);
                    return;
                } else try options_reader.skipValue(options_tag);
            }
        } else try file_reader.skipValue(file_tag);
    }
    return error.TestUnexpectedResult;
}

fn readTestNamePart(bytes: []const u8) !ExpectedNamePart {
    var part = ExpectedNamePart{ .name = "", .is_extension = false };
    var reader = wire.Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            1 => part.name = try reader.readBytes(),
            2 => part.is_extension = try reader.readBool(),
            else => try reader.skipValue(tag),
        }
    }
    return part;
}

test "descriptor preserves custom options as uninterpreted options" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\option (demo.file_opt).child = "file-value";
        \\message M { optional int32 id = 1 [(demo.field_opt).nested.leaf = 123]; }
    );
    defer file.deinit();
    const bytes = try encodeFileDescriptorProto(allocator, &file, "custom.proto");
    defer allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "demo.file_opt") != null);
    try expectFirstFileOptionNameParts(bytes, &.{
        .{ .name = "demo.file_opt", .is_extension = true },
        .{ .name = "child", .is_extension = false },
    });
    try std.testing.expect(std.mem.indexOf(u8, bytes, "file-value") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "demo.field_opt") != null);
}

test "descriptor decodes uninterpreted options" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\option (demo.file_opt).child = "file-value";
        \\message M { optional int32 id = 1 [(demo.field_opt).nested.leaf = 123]; }
    );
    defer file.deinit();
    const bytes = try encodeFileDescriptorProto(allocator, &file, "custom.proto");
    defer allocator.free(bytes);
    var decoded = try decodeFileDescriptorProto(allocator, bytes);
    defer decoded.deinit();
    try std.testing.expectEqualStrings("(demo.file_opt).child", decoded.options.items[0].name);
    try std.testing.expectEqualSlices(u8, "file-value", decoded.options.items[0].value.string);
    const field = decoded.findMessage("M").?.findField("id").?;
    try std.testing.expectEqualStrings("(demo.field_opt).nested.leaf", field.options.items[0].name);
    try std.testing.expectEqual(@as(i64, 123), field.options.items[0].value.integer);
}

test "descriptor round-trips uninterpreted option value kinds" {
    const allocator = std.testing.allocator;
    var file = schema.FileDescriptor.init(allocator);
    defer file.deinit();
    file.setSyntax(.proto2);
    try file.options.append(allocator, .{ .name = "(demo.bool_opt)", .value = .{ .boolean = true } });
    try file.options.append(allocator, .{ .name = "(demo.neg_opt)", .value = .{ .integer = -7 } });
    try file.options.append(allocator, .{ .name = "(demo.float_opt)", .value = .{ .float = 1.5 } });
    try file.options.append(allocator, .{ .name = "(demo.aggregate_opt)", .value = .{ .aggregate = "{ enabled: true count: 2 }" } });
    var message = schema.MessageDescriptor{ .name = "M" };
    try message.fields.append(allocator, .{ .name = "id", .number = 1, .cardinality = .optional, .kind = .{ .scalar = .int32 } });
    try file.messages.append(allocator, message);

    const bytes = try encodeFileDescriptorProto(allocator, &file, "option-values.proto");
    defer allocator.free(bytes);
    var decoded = try decodeFileDescriptorProto(allocator, bytes);
    defer decoded.deinit();
    try std.testing.expectEqual(@as(usize, 4), decoded.options.items.len);
    try std.testing.expectEqualStrings("(demo.bool_opt)", decoded.options.items[0].name);
    try std.testing.expectEqualStrings("true", decoded.options.items[0].value.identifier);
    try std.testing.expectEqualStrings("(demo.neg_opt)", decoded.options.items[1].name);
    try std.testing.expectEqual(@as(i64, -7), decoded.options.items[1].value.integer);
    try std.testing.expectEqualStrings("(demo.float_opt)", decoded.options.items[2].name);
    try std.testing.expectEqual(@as(f64, 1.5), decoded.options.items[2].value.float);
    try std.testing.expectEqualStrings("(demo.aggregate_opt)", decoded.options.items[3].name);
    try std.testing.expectEqualStrings("{ enabled: true count: 2 }", decoded.options.items[3].value.aggregate);
}

test "descriptor preserves import dependency kinds" {
    const allocator = std.testing.allocator;
    var proto2_file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\import public "public.proto";
        \\import weak "weak.proto";
        \\message M {}
    );
    defer proto2_file.deinit();
    const proto2_bytes = try encodeFileDescriptorProto(allocator, &proto2_file, "imports.proto");
    defer allocator.free(proto2_bytes);
    var decoded_proto2 = try decodeFileDescriptorProto(allocator, proto2_bytes);
    defer decoded_proto2.deinit();
    try std.testing.expectEqual(schema.Import.Kind.public, decoded_proto2.imports.items[0].kind);
    try std.testing.expectEqual(schema.Import.Kind.weak, decoded_proto2.imports.items[1].kind);

    var editions_file = try @import("parser.zig").Parser.parse(allocator,
        \\edition = "2024";
        \\import "data.proto";
        \\import option "options.proto";
        \\message M { int32 id = 1; }
    );
    defer editions_file.deinit();
    const editions_bytes = try encodeFileDescriptorProto(allocator, &editions_file, "edition-imports.proto");
    defer allocator.free(editions_bytes);
    var decoded_editions = try decodeFileDescriptorProto(allocator, editions_bytes);
    defer decoded_editions.deinit();
    try std.testing.expectEqual(schema.Import.Kind.normal, decoded_editions.imports.items[0].kind);
    try std.testing.expectEqual(schema.Import.Kind.option, decoded_editions.imports.items[1].kind);
}

test "descriptor encodes proto3 optional synthetic oneof" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\message Child {}
        \\message M { optional int32 value = 1; optional Child child = 2; }
    );
    defer file.deinit();
    const bytes = try encodeFileDescriptorProto(allocator, &file, "optional.proto");
    defer allocator.free(bytes);
    var decoded = try decodeFileDescriptorProto(allocator, bytes);
    defer decoded.deinit();
    const msg = decoded.findMessage("M").?;
    try std.testing.expectEqual(@as(usize, 2), msg.oneofs.items.len);
    try std.testing.expectEqualStrings("_value", msg.oneofs.items[0].name);
    try std.testing.expectEqualStrings("_value", msg.findField("value").?.oneof_name.?);
    try std.testing.expect(msg.findField("value").?.proto3_optional);
    try std.testing.expectEqualStrings("_child", msg.oneofs.items[1].name);
    try std.testing.expectEqualStrings("_child", msg.findField("child").?.oneof_name.?);
    try std.testing.expect(msg.findField("child").?.proto3_optional);
    try std.testing.expect(msg.findField("child").?.kind == .message);
}

test "descriptor rejects invalid oneof descriptors and indexes" {
    const allocator = std.testing.allocator;
    {
        var oneof = wire.Writer.init(allocator);
        defer oneof.deinit();
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(8, oneof.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-oneof.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var oneof = wire.Writer.init(allocator);
        defer oneof.deinit();
        try oneof.writeString(1, "pick");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(8, oneof.slice());
        try message.writeMessage(8, oneof.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "dup-oneof.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var oneof = wire.Writer.init(allocator);
        defer oneof.deinit();
        try oneof.writeString(1, "empty");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(8, oneof.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "empty-oneof.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "value");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 5);
        try field.writeInt32(9, -1);
        var oneof = wire.Writer.init(allocator);
        defer oneof.deinit();
        try oneof.writeString(1, "pick");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        try message.writeMessage(8, oneof.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "negative-oneof-index.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "name");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 9);
        try field.writeInt32(9, 1);
        var oneof = wire.Writer.init(allocator);
        defer oneof.deinit();
        try oneof.writeString(1, "pick");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        try message.writeMessage(8, oneof.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-oneof-index.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Many");
        var i: usize = 0;
        while (i < 13) : (i += 1) {
            var field = wire.Writer.init(allocator);
            defer field.deinit();
            const field_name = try std.fmt.allocPrint(allocator, "value_{d}", .{i});
            defer allocator.free(field_name);
            try field.writeString(1, field_name);
            try field.writeInt32(3, @intCast(i + 1));
            try field.writeInt32(4, 1);
            try field.writeInt32(5, 5);
            try field.writeInt32(9, @intCast(i));
            try message.writeMessage(2, field.slice());
        }
        i = 0;
        while (i < 13) : (i += 1) {
            var oneof = wire.Writer.init(allocator);
            defer oneof.deinit();
            const name = try std.fmt.allocPrint(allocator, "pick_{d}", .{i});
            defer allocator.free(name);
            try oneof.writeString(1, name);
            try message.writeMessage(8, oneof.slice());
        }
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "large-oneof-index.proto");
        try file.writeMessage(4, message.slice());
        var decoded = try decodeFileDescriptorProto(allocator, file.slice());
        defer decoded.deinit();
        const msg = decoded.findMessage("Many").?;
        try std.testing.expectEqual(@as(usize, 13), msg.oneofs.items.len);
        try std.testing.expectEqualStrings("pick_12", msg.findField("value_12").?.oneof_name.?);
    }
    {
        var first = wire.Writer.init(allocator);
        defer first.deinit();
        try first.writeString(1, "first");
        try first.writeInt32(3, 1);
        try first.writeInt32(4, 1);
        try first.writeInt32(5, 5);
        try first.writeInt32(9, 0);
        var middle = wire.Writer.init(allocator);
        defer middle.deinit();
        try middle.writeString(1, "middle");
        try middle.writeInt32(3, 2);
        try middle.writeInt32(4, 1);
        try middle.writeInt32(5, 5);
        var second = wire.Writer.init(allocator);
        defer second.deinit();
        try second.writeString(1, "second");
        try second.writeInt32(3, 3);
        try second.writeInt32(4, 1);
        try second.writeInt32(5, 5);
        try second.writeInt32(9, 0);
        var oneof = wire.Writer.init(allocator);
        defer oneof.deinit();
        try oneof.writeString(1, "pick");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, first.slice());
        try message.writeMessage(2, middle.slice());
        try message.writeMessage(2, second.slice());
        try message.writeMessage(8, oneof.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "non-contiguous-oneof.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var foo1 = wire.Writer.init(allocator);
        defer foo1.deinit();
        try foo1.writeString(1, "foo1");
        try foo1.writeInt32(3, 1);
        try foo1.writeInt32(4, 1);
        try foo1.writeInt32(5, 5);
        try foo1.writeInt32(9, 0);
        var bar1 = wire.Writer.init(allocator);
        defer bar1.deinit();
        try bar1.writeString(1, "bar1");
        try bar1.writeInt32(3, 2);
        try bar1.writeInt32(4, 1);
        try bar1.writeInt32(5, 5);
        try bar1.writeInt32(9, 1);
        var foo2 = wire.Writer.init(allocator);
        defer foo2.deinit();
        try foo2.writeString(1, "foo2");
        try foo2.writeInt32(3, 3);
        try foo2.writeInt32(4, 1);
        try foo2.writeInt32(5, 5);
        try foo2.writeInt32(9, 0);
        var foos = wire.Writer.init(allocator);
        defer foos.deinit();
        try foos.writeString(1, "foos");
        var bars = wire.Writer.init(allocator);
        defer bars.deinit();
        try bars.writeString(1, "bars");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, foo1.slice());
        try message.writeMessage(2, bar1.slice());
        try message.writeMessage(2, foo2.slice());
        try message.writeMessage(8, foos.slice());
        try message.writeMessage(8, bars.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "interleaved-oneof.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "value");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 5);
        try field.writeBool(17, true);
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-proto3-optional.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var optional_field = wire.Writer.init(allocator);
        defer optional_field.deinit();
        try optional_field.writeString(1, "value");
        try optional_field.writeInt32(3, 1);
        try optional_field.writeInt32(4, 1);
        try optional_field.writeInt32(5, 5);
        try optional_field.writeInt32(9, 0);
        try optional_field.writeBool(17, true);
        var other_field = wire.Writer.init(allocator);
        defer other_field.deinit();
        try other_field.writeString(1, "other");
        try other_field.writeInt32(3, 2);
        try other_field.writeInt32(4, 1);
        try other_field.writeInt32(5, 5);
        try other_field.writeInt32(9, 0);
        var oneof = wire.Writer.init(allocator);
        defer oneof.deinit();
        try oneof.writeString(1, "_value");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, optional_field.slice());
        try message.writeMessage(2, other_field.slice());
        try message.writeMessage(8, oneof.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-proto3-optional-oneof.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "value");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 2);
        try field.writeInt32(5, 5);
        try field.writeInt32(9, 0);
        try field.writeBool(17, true);
        var oneof = wire.Writer.init(allocator);
        defer oneof.deinit();
        try oneof.writeString(1, "_value");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        try message.writeMessage(8, oneof.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-proto3-optional-required.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "ids");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 3);
        try field.writeInt32(5, 5);
        try field.writeInt32(9, 0);
        var oneof = wire.Writer.init(allocator);
        defer oneof.deinit();
        try oneof.writeString(1, "pick");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        try message.writeMessage(8, oneof.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-oneof-repeated.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "Legacy");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 10);
        try field.writeString(6, ".Bad.Legacy");
        try field.writeInt32(9, 0);
        var oneof = wire.Writer.init(allocator);
        defer oneof.deinit();
        try oneof.writeString(1, "pick");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        try message.writeMessage(8, oneof.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-oneof-group.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "child");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 11);
        try field.writeString(6, ".Child");
        try field.writeInt32(9, 0);
        try field.writeBool(17, true);
        var oneof = wire.Writer.init(allocator);
        defer oneof.deinit();
        try oneof.writeString(1, "_child");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        try message.writeMessage(8, oneof.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-proto2-proto3-optional-message.proto");
        try file.writeString(12, "proto2");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "value");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 5);
        try field.writeInt32(9, 0);
        try field.writeBool(17, true);
        var oneof = wire.Writer.init(allocator);
        defer oneof.deinit();
        try oneof.writeString(1, "_value");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        try message.writeMessage(8, oneof.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-proto2-proto3-optional.proto");
        try file.writeString(12, "proto2");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var optional_field = wire.Writer.init(allocator);
        defer optional_field.deinit();
        try optional_field.writeString(1, "value");
        try optional_field.writeInt32(3, 1);
        try optional_field.writeInt32(4, 1);
        try optional_field.writeInt32(5, 5);
        try optional_field.writeInt32(9, 0);
        try optional_field.writeBool(17, true);
        var real_field = wire.Writer.init(allocator);
        defer real_field.deinit();
        try real_field.writeString(1, "name");
        try real_field.writeInt32(3, 2);
        try real_field.writeInt32(4, 1);
        try real_field.writeInt32(5, 9);
        try real_field.writeInt32(9, 1);
        var synthetic = wire.Writer.init(allocator);
        defer synthetic.deinit();
        try synthetic.writeString(1, "_value");
        var real_oneof = wire.Writer.init(allocator);
        defer real_oneof.deinit();
        try real_oneof.writeString(1, "pick");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, optional_field.slice());
        try message.writeMessage(2, real_field.slice());
        try message.writeMessage(8, synthetic.slice());
        try message.writeMessage(8, real_oneof.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-synthetic-oneof-order.proto");
        try file.writeString(12, "proto3");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
}

test "descriptor rejects invalid message descriptors" {
    const allocator = std.testing.allocator;
    {
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-message.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "same");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 5);
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        try message.writeMessage(2, field.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "dup-field.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var nested = wire.Writer.init(allocator);
        defer nested.deinit();
        try nested.writeString(1, "Item");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(3, nested.slice());
        try message.writeMessage(3, nested.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "dup-nested.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "Item");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 5);
        var nested = wire.Writer.init(allocator);
        defer nested.deinit();
        try nested.writeString(1, "Item");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        try message.writeMessage(3, nested.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "field-nested-conflict.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var oneof = wire.Writer.init(allocator);
        defer oneof.deinit();
        try oneof.writeString(1, "Kind");
        var enum_value = wire.Writer.init(allocator);
        defer enum_value.deinit();
        try enum_value.writeString(1, "UNKNOWN");
        try enum_value.writeInt32(2, 0);
        var enumeration = wire.Writer.init(allocator);
        defer enumeration.deinit();
        try enumeration.writeString(1, "Kind");
        try enumeration.writeMessage(2, enum_value.slice());
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "value");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 5);
        try field.writeInt32(9, 0);
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        try message.writeMessage(4, enumeration.slice());
        try message.writeMessage(8, oneof.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "oneof-enum-conflict.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
}

test "descriptor rejects invalid decoded json names" {
    const allocator = std.testing.allocator;
    {
        var first = wire.Writer.init(allocator);
        defer first.deinit();
        try first.writeString(1, "foo_bar");
        try first.writeInt32(3, 1);
        try first.writeInt32(4, 1);
        try first.writeInt32(5, 5);
        var second = wire.Writer.init(allocator);
        defer second.deinit();
        try second.writeString(1, "fooBar");
        try second.writeInt32(3, 2);
        try second.writeInt32(4, 1);
        try second.writeInt32(5, 5);
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, first.slice());
        try message.writeMessage(2, second.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "default-json-name-conflict.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var first = wire.Writer.init(allocator);
        defer first.deinit();
        try first.writeString(1, "foo");
        try first.writeInt32(3, 1);
        try first.writeInt32(4, 1);
        try first.writeInt32(5, 5);
        try first.writeString(10, "sameName");
        var second = wire.Writer.init(allocator);
        defer second.deinit();
        try second.writeString(1, "bar");
        try second.writeInt32(3, 2);
        try second.writeInt32(4, 1);
        try second.writeInt32(5, 5);
        try second.writeString(10, "sameName");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, first.slice());
        try message.writeMessage(2, second.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "custom-json-name-conflict.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var first = wire.Writer.init(allocator);
        defer first.deinit();
        try first.writeString(1, "foo");
        try first.writeInt32(3, 1);
        try first.writeInt32(4, 1);
        try first.writeInt32(5, 5);
        try first.writeString(10, "barBaz");
        var second = wire.Writer.init(allocator);
        defer second.deinit();
        try second.writeString(1, "bar_baz");
        try second.writeInt32(3, 2);
        try second.writeInt32(4, 1);
        try second.writeInt32(5, 5);
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, first.slice());
        try message.writeMessage(2, second.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "custom-default-json-name-conflict.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "foo");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 5);
        try field.writeString(10, "[demo.ext]");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "extension-looking-json-name.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "foo");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 5);
        try field.writeString(10, "has\x00nul");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "nul-json-name.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "ext");
        try field.writeInt32(3, 100);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 5);
        try field.writeString(2, ".Host");
        try field.writeString(10, "customExt");
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "extension-json-name.proto");
        try file.writeMessage(7, field.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
}

test "descriptor rejects duplicate top-level file symbols" {
    const allocator = std.testing.allocator;
    {
        var msg = wire.Writer.init(allocator);
        defer msg.deinit();
        try msg.writeString(1, "Thing");
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "dup-message.proto");
        try file.writeMessage(4, msg.slice());
        try file.writeMessage(4, msg.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var msg = wire.Writer.init(allocator);
        defer msg.deinit();
        try msg.writeString(1, "Thing");
        var enum_value = wire.Writer.init(allocator);
        defer enum_value.deinit();
        try enum_value.writeString(1, "UNKNOWN");
        try enum_value.writeInt32(2, 0);
        var enumeration = wire.Writer.init(allocator);
        defer enumeration.deinit();
        try enumeration.writeString(1, "Thing");
        try enumeration.writeMessage(2, enum_value.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "message-enum-conflict.proto");
        try file.writeMessage(4, msg.slice());
        try file.writeMessage(5, enumeration.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var service = wire.Writer.init(allocator);
        defer service.deinit();
        try service.writeString(1, "Api");
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "dup-service.proto");
        try file.writeMessage(6, service.slice());
        try file.writeMessage(6, service.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
}

test "descriptor rejects invalid reserved ranges" {
    const allocator = std.testing.allocator;
    {
        var range = wire.Writer.init(allocator);
        defer range.deinit();
        try range.writeInt32(1, 10);
        try range.writeInt32(2, 5);
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(9, range.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-reserved.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var value = wire.Writer.init(allocator);
        defer value.deinit();
        try value.writeString(1, "A");
        try value.writeInt32(2, 0);
        var range = wire.Writer.init(allocator);
        defer range.deinit();
        try range.writeInt32(1, 5);
        try range.writeInt32(2, 3);
        var enumeration = wire.Writer.init(allocator);
        defer enumeration.deinit();
        try enumeration.writeString(1, "Bad");
        try enumeration.writeMessage(2, value.slice());
        try enumeration.writeMessage(4, range.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-enum-reserved.proto");
        try file.writeMessage(5, enumeration.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var message = schema.MessageDescriptor{ .name = "Bad" };
        try message.reserved_ranges.append(allocator, .{ .start = -10, .end = -9 });
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        try file.messages.append(allocator, message);
        const bytes = try encodeFileDescriptorProto(allocator, &file, "negative-message-reserved.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        var message = schema.MessageDescriptor{ .name = "Bad" };
        try message.reserved_ranges.append(allocator, .{ .start = @as(i64, std.math.maxInt(wire.FieldNumber)) + 1, .end = @as(i64, std.math.maxInt(wire.FieldNumber)) + 2 });
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        try file.messages.append(allocator, message);
        const bytes = try encodeFileDescriptorProto(allocator, &file, "huge-message-reserved.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        var enumeration = schema.EnumDescriptor{ .name = "Ok" };
        try enumeration.values.append(allocator, .{ .name = "A", .number = 0 });
        try enumeration.reserved_ranges.append(allocator, .{ .start = -10, .end = -9 });
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        try file.enums.append(allocator, enumeration);
        const bytes = try encodeFileDescriptorProto(allocator, &file, "negative-enum-reserved.proto");
        defer allocator.free(bytes);
        var decoded = try decodeFileDescriptorProto(allocator, bytes);
        defer decoded.deinit();
        try std.testing.expectEqual(@as(i64, -10), decoded.findEnum("Ok").?.reserved_ranges.items[0].start);
    }
}

test "descriptor rejects declarations that use reserved fields or enum values" {
    const allocator = std.testing.allocator;
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        var message = schema.MessageDescriptor{ .name = "Bad" };
        try message.reserved_ranges.append(allocator, .{ .start = 1, .end = 3 });
        try message.fields.append(allocator, .{ .name = "hit", .number = 2, .cardinality = .optional, .kind = .{ .scalar = .int32 } });
        try file.messages.append(allocator, message);
        const bytes = try encodeFileDescriptorProto(allocator, &file, "reserved-field.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        var message = schema.MessageDescriptor{ .name = "Bad" };
        try message.reserved_names.append(allocator, "old");
        try message.reserved_names.append(allocator, "old");
        try file.messages.append(allocator, message);
        const bytes = try encodeFileDescriptorProto(allocator, &file, "reserved-name.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        var enumeration = schema.EnumDescriptor{ .name = "Bad" };
        try enumeration.reserved_ranges.append(allocator, .{ .start = 1, .end = 3 });
        try enumeration.values.append(allocator, .{ .name = "HIT", .number = 2 });
        try file.enums.append(allocator, enumeration);
        const bytes = try encodeFileDescriptorProto(allocator, &file, "reserved-enum.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        var enumeration = schema.EnumDescriptor{ .name = "Bad" };
        try enumeration.reserved_names.append(allocator, "OLD");
        try enumeration.values.append(allocator, .{ .name = "OLD", .number = 1 });
        try file.enums.append(allocator, enumeration);
        const bytes = try encodeFileDescriptorProto(allocator, &file, "reserved-enum-name.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
}

test "descriptor rejects extension ranges in proto3" {
    const allocator = std.testing.allocator;
    var range = wire.Writer.init(allocator);
    defer range.deinit();
    try range.writeInt32(1, 100);
    try range.writeInt32(2, 200);
    var message = wire.Writer.init(allocator);
    defer message.deinit();
    try message.writeString(1, "Bad");
    try message.writeMessage(5, range.slice());
    var file = wire.Writer.init(allocator);
    defer file.deinit();
    try file.writeString(1, "proto3-ext-range.proto");
    try file.writeString(12, "proto3");
    try file.writeMessage(4, message.slice());
    try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
}

test "descriptor rejects invalid extension ranges" {
    const allocator = std.testing.allocator;
    const field_max_end: i32 = @intCast(@as(i64, std.math.maxInt(wire.FieldNumber)) + 1);
    const beyond_field_max_end = field_max_end + 1;
    {
        const bytes = try testFileWithExtensionRange(allocator, 100, 50, null);
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        const bytes = try testFileWithExtensionRange(allocator, 100, 200, .{ .number = 10, .full_name = ".demo.bad", .type_name = ".demo.Bad" });
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        const bytes = try testFileWithExtensionRange(allocator, 100, 200, .{ .number = 100, .full_name = ".demo.ext", .type_name = ".demo.Ext" });
        defer allocator.free(bytes);
        var decoded = try decodeFileDescriptorProto(allocator, bytes);
        defer decoded.deinit();
        try std.testing.expectEqual(@as(i64, 100), decoded.findMessage("Host").?.extension_ranges.items[0].start);
    }
    {
        const bytes = try testFileWithExtensionRange(allocator, field_max_end, beyond_field_max_end, null);
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        const bytes = try testFileWithExtensionRange(allocator, std.math.maxInt(wire.FieldNumber), beyond_field_max_end, null);
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        var low_range = wire.Writer.init(allocator);
        defer low_range.deinit();
        try low_range.writeInt32(1, 4);
        try low_range.writeInt32(2, 5);
        var high_range = wire.Writer.init(allocator);
        defer high_range.deinit();
        try high_range.writeInt32(1, field_max_end);
        try high_range.writeInt32(2, beyond_field_max_end);
        var options = wire.Writer.init(allocator);
        defer options.deinit();
        try options.writeBool(1, true);
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "MessageSetHost");
        try message.writeMessage(5, low_range.slice());
        try message.writeMessage(5, high_range.slice());
        try message.writeMessage(7, options.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "messageset-high-extension-range.proto");
        try file.writeString(12, "proto2");
        try file.writeMessage(4, message.slice());
        var decoded = try decodeFileDescriptorProto(allocator, file.slice());
        defer decoded.deinit();
        const decoded_host = decoded.findMessage("MessageSetHost").?;
        try std.testing.expectEqual(@as(i64, field_max_end), decoded_host.extension_ranges.items[1].start);
        try std.testing.expectEqual(@as(?i64, beyond_field_max_end), decoded_host.extension_ranges.items[1].end);
    }
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        var message = schema.MessageDescriptor{ .name = "Bad" };
        try message.extension_ranges.append(allocator, .{ .start = 100, .end = 200 });
        try message.fields.append(allocator, .{ .name = "hit", .number = 150, .cardinality = .optional, .kind = .{ .scalar = .int32 } });
        try file.messages.append(allocator, message);
        const bytes = try encodeFileDescriptorProto(allocator, &file, "field-in-extension-range.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        var message = schema.MessageDescriptor{ .name = "Bad" };
        try message.extension_ranges.append(allocator, .{ .start = 100, .end = 200 });
        try message.extension_ranges.append(allocator, .{ .start = 150, .end = 250 });
        try file.messages.append(allocator, message);
        const bytes = try encodeFileDescriptorProto(allocator, &file, "overlap-extension-range.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        var message = schema.MessageDescriptor{ .name = "Bad" };
        try message.extension_ranges.append(allocator, .{ .start = 100, .end = 200 });
        try message.reserved_ranges.append(allocator, .{ .start = 150, .end = 160 });
        try file.messages.append(allocator, message);
        const bytes = try encodeFileDescriptorProto(allocator, &file, "extension-reserved-overlap.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
}

fn testFileWithExtensionRange(allocator: std.mem.Allocator, start: i32, end: i32, declaration: ?schema.ExtensionDeclaration) ![]u8 {
    var range = wire.Writer.init(allocator);
    defer range.deinit();
    try range.writeInt32(1, start);
    try range.writeInt32(2, end);
    if (declaration) |decl| {
        var decl_writer = wire.Writer.init(allocator);
        defer decl_writer.deinit();
        try decl_writer.writeInt32(1, decl.number);
        try decl_writer.writeString(2, decl.full_name);
        try decl_writer.writeString(3, decl.type_name);
        var options = wire.Writer.init(allocator);
        defer options.deinit();
        try options.writeMessage(2, decl_writer.slice());
        try range.writeMessage(3, options.slice());
    }

    var message = wire.Writer.init(allocator);
    defer message.deinit();
    try message.writeString(1, "Host");
    try message.writeMessage(5, range.slice());

    var file = wire.Writer.init(allocator);
    errdefer file.deinit();
    try file.writeString(1, "ext-range-invalid.proto");
    try file.writeString(12, "proto2");
    try file.writeMessage(4, message.slice());
    return try file.toOwnedSlice();
}

test "descriptor rejects invalid file syntax edition and dependency indexes" {
    const allocator = std.testing.allocator;
    {
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-syntax.proto");
        try file.writeString(12, "proto4");
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-edition.proto");
        try file.writeInt32(14, 123456);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "unknown-edition.proto");
        try file.writeInt32(14, @intFromEnum(schema.Edition.unknown));
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "max-edition.proto");
        try file.writeInt32(14, @intFromEnum(schema.Edition.max));
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "proto3-with-edition.proto");
        try file.writeString(12, "proto3");
        try file.writeInt32(14, @intFromEnum(schema.Edition.edition_2023));
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "edition-before-proto3.proto");
        try file.writeInt32(14, @intFromEnum(schema.Edition.edition_2023));
        try file.writeString(12, "proto3");
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "edition-before-syntax.proto");
        try file.writeInt32(14, @intFromEnum(schema.Edition.edition_2024));
        try file.writeString(12, "editions");
        var decoded = try decodeFileDescriptorProto(allocator, file.slice());
        defer decoded.deinit();
        try std.testing.expectEqual(schema.Syntax.editions, decoded.syntax);
        try std.testing.expectEqual(schema.Edition.edition_2024, decoded.edition);
    }
    {
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-public-dep.proto");
        try file.writeString(3, "dep.proto");
        try file.writeInt32(10, 1);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-weak-dep.proto");
        try file.writeString(3, "dep.proto");
        try file.writeInt32(11, -1);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "dup-public-dep.proto");
        try file.writeString(3, "dep.proto");
        try file.writeInt32(10, 0);
        try file.writeInt32(10, 0);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "conflicting-dep-kind.proto");
        try file.writeString(3, "dep.proto");
        try file.writeInt32(10, 0);
        try file.writeInt32(11, 0);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "edition-weak-import.proto");
        try file.writeString(3, "dep.proto");
        try file.writeInt32(11, 0);
        try file.writeString(12, "editions");
        try file.writeInt32(14, @intFromEnum(schema.Edition.edition_2024));
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "proto2-option-import.proto");
        try file.writeString(15, "options.proto");
        try file.writeString(12, "proto2");
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "edition-2023-option-import.proto");
        try file.writeString(15, "options.proto");
        try file.writeString(12, "editions");
        try file.writeInt32(14, @intFromEnum(schema.Edition.edition_2023));
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "empty-import.proto");
        try file.writeString(3, "");
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "dup-import.proto");
        try file.writeString(3, "dep.proto");
        try file.writeString(3, "dep.proto");
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "dup-option-import.proto");
        try file.writeString(3, "dep.proto");
        try file.writeString(15, "dep.proto");
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    inline for (.{ "1bad", "bad..pkg", "bad.", "bad-pkg" }) |bad_package| {
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-package.proto");
        try file.writeString(2, bad_package);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
}

test "descriptor rejects non-option extensions in proto3" {
    const allocator = std.testing.allocator;
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "ext");
        try field.writeString(2, ".Host");
        try field.writeInt32(3, 100);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 5);
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "proto3-extension.proto");
        try file.writeString(12, "proto3");
        try file.writeMessage(7, field.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "note");
        try field.writeString(2, ".google.protobuf.MessageOptions");
        try field.writeInt32(3, 1000);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 9);
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "proto3-option-extension.proto");
        try file.writeString(12, "proto3");
        try file.writeMessage(7, field.slice());
        var decoded = try decodeFileDescriptorProto(allocator, file.slice());
        defer decoded.deinit();
        try std.testing.expectEqual(@as(usize, 1), decoded.extensions.items.len);
    }
}

test "descriptor rejects required labels outside proto2 and on extensions" {
    const allocator = std.testing.allocator;
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "id");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 2);
        try field.writeInt32(5, 5);
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "proto3-required.proto");
        try file.writeString(12, "proto3");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "id");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 2);
        try field.writeInt32(5, 5);
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "editions-required.proto");
        try file.writeString(12, "editions");
        try file.writeInt32(14, @intFromEnum(schema.Edition.edition_2023));
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var host = wire.Writer.init(allocator);
        defer host.deinit();
        try host.writeString(1, "Host");
        var range = wire.Writer.init(allocator);
        defer range.deinit();
        try range.writeInt32(1, 100);
        try range.writeInt32(2, 200);
        try host.writeMessage(5, range.slice());
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "bad_ext");
        try field.writeString(2, ".Host");
        try field.writeInt32(3, 100);
        try field.writeInt32(4, 2);
        try field.writeInt32(5, 5);
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "required-extension.proto");
        try file.writeMessage(4, host.slice());
        try file.writeMessage(7, field.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "bad_ext");
        try field.writeString(2, ".google.protobuf.MessageOptions");
        try field.writeInt32(3, 100);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 5);
        try field.writeBool(17, true);
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "extension-with-proto3-optional.proto");
        try file.writeString(12, "proto3");
        try file.writeMessage(7, field.slice());
        // protoc keeps proto3_optional on `optional` extensions of options
        // messages, so this shape is accepted.
        var decoded = try decodeFileDescriptorProto(allocator, file.slice());
        defer decoded.deinit();
        try std.testing.expect(decoded.extensions.items[0].proto3_optional);
    }
}

test "descriptor rejects invalid field ownership markers" {
    const allocator = std.testing.allocator;
    {
        var host = wire.Writer.init(allocator);
        defer host.deinit();
        try host.writeString(1, "Host");
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "bad");
        try field.writeString(2, ".Host");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 5);
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "normal-field-with-extendee.proto");
        try file.writeMessage(4, host.slice());
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var host = wire.Writer.init(allocator);
        defer host.deinit();
        try host.writeString(1, "Host");
        var range = wire.Writer.init(allocator);
        defer range.deinit();
        try range.writeInt32(1, 100);
        try range.writeInt32(2, 200);
        try host.writeMessage(5, range.slice());
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "bad_ext");
        try field.writeString(2, ".Host");
        try field.writeInt32(3, 100);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 5);
        try field.writeInt32(9, 0);
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "extension-with-oneof-index.proto");
        try file.writeMessage(4, host.slice());
        try file.writeMessage(7, field.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
}

test "descriptor rejects invalid decoded symbol identifiers" {
    const allocator = std.testing.allocator;
    {
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "1Bad");
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-message-name.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "bad-name");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 5);
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-field-name.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "bad.member");
        try field.writeInt32(3, 100);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 5);
        try field.writeString(2, ".pkg.Host");
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-extension-name.proto");
        try file.writeMessage(7, field.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var oneof = wire.Writer.init(allocator);
        defer oneof.deinit();
        try oneof.writeString(1, "bad.oneof");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(8, oneof.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-oneof-name.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var value = wire.Writer.init(allocator);
        defer value.deinit();
        try value.writeString(1, "OK");
        try value.writeInt32(2, 0);
        var enumeration = wire.Writer.init(allocator);
        defer enumeration.deinit();
        try enumeration.writeString(1, "-Bad");
        try enumeration.writeMessage(2, value.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-enum-name.proto");
        try file.writeMessage(5, enumeration.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var value = wire.Writer.init(allocator);
        defer value.deinit();
        try value.writeString(1, "0_VALUE");
        try value.writeInt32(2, 0);
        var enumeration = wire.Writer.init(allocator);
        defer enumeration.deinit();
        try enumeration.writeString(1, "Bad");
        try enumeration.writeMessage(2, value.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-enum-value-name.proto");
        try file.writeMessage(5, enumeration.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var service = wire.Writer.init(allocator);
        defer service.deinit();
        try service.writeString(1, "bad.service");
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-service-name.proto");
        try file.writeMessage(6, service.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var method = wire.Writer.init(allocator);
        defer method.deinit();
        try method.writeString(1, "bad-method");
        try method.writeString(2, ".demo.Req");
        try method.writeString(3, ".demo.Res");
        var service = wire.Writer.init(allocator);
        defer service.deinit();
        try service.writeString(1, "Svc");
        try service.writeMessage(2, method.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-method-name.proto");
        try file.writeMessage(6, service.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
}

test "descriptor rejects invalid decoded type references" {
    const allocator = std.testing.allocator;
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "child");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 11);
        try field.writeString(6, ".demo.Bad-Type");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-message-type-name.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "ext");
        try field.writeInt32(3, 100);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 5);
        try field.writeString(2, ".demo.Bad-Type");
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-extendee-name.proto");
        try file.writeMessage(7, field.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "ext");
        try field.writeInt32(3, 100);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 5);
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "missing-extendee.proto");
        try file.writeMessage(7, field.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        const bytes = try testFileWithExtensionRange(allocator, 100, 200, .{ .number = 100, .full_name = ".demo.bad-name", .type_name = "int32" });
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        const bytes = try testFileWithExtensionRange(allocator, 100, 200, .{ .number = 100, .full_name = ".demo.good_name", .type_name = ".demo.Bad-Type" });
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        var method = wire.Writer.init(allocator);
        defer method.deinit();
        try method.writeString(1, "Get");
        try method.writeString(2, ".demo.Bad-Type");
        try method.writeString(3, ".demo.Res");
        var service = wire.Writer.init(allocator);
        defer service.deinit();
        try service.writeString(1, "Svc");
        try service.writeMessage(2, method.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-method-input-type.proto");
        try file.writeMessage(6, service.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
}

test "descriptor preserves message and enum custom options" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message M { option (demo.msg_opt) = "m"; optional int32 id = 1; }
        \\enum E { option (demo.enum_opt) = "e"; A = 0; }
    );
    defer file.deinit();
    const bytes = try encodeFileDescriptorProto(allocator, &file, "opts.proto");
    defer allocator.free(bytes);
    var decoded = try decodeFileDescriptorProto(allocator, bytes);
    defer decoded.deinit();
    try std.testing.expectEqualStrings("(demo.msg_opt)", decoded.findMessage("M").?.options.items[0].name);
    try std.testing.expectEqualSlices(u8, "m", decoded.findMessage("M").?.options.items[0].value.string);
    try std.testing.expectEqualStrings("(demo.enum_opt)", decoded.findEnum("E").?.options.items[0].name);
    try std.testing.expectEqualSlices(u8, "e", decoded.findEnum("E").?.options.items[0].value.string);
}

test "descriptor preserves known file options" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\option java_package = "com.example.demo";
        \\option java_outer_classname = "DemoProto";
        \\option optimize_for = CODE_SIZE;
        \\option java_multiple_files = true;
        \\option go_package = "example.com/demo;demopb";
        \\option cc_generic_services = true;
        \\option java_generic_services = true;
        \\option py_generic_services = true;
        \\option java_generate_equals_and_hash = true;
        \\option deprecated = true;
        \\option java_string_check_utf8 = true;
        \\option cc_enable_arenas = true;
        \\option objc_class_prefix = "DEM";
        \\option csharp_namespace = "Example.Demo";
        \\option swift_prefix = "Demo";
        \\option php_class_prefix = "Demo";
        \\option php_namespace = "Example\\Demo";
        \\option php_metadata_namespace = "Example\\Demo\\Metadata";
        \\option ruby_package = "Example::Demo";
        \\message M { optional int32 id = 1; }
    );
    defer file.deinit();
    const bytes = try encodeFileDescriptorProto(allocator, &file, "file-options.proto");
    defer allocator.free(bytes);
    var decoded = try decodeFileDescriptorProto(allocator, bytes);
    defer decoded.deinit();

    try std.testing.expectEqualStrings("com.example.demo", exactOptionString(decoded.options.items, "java_package").?);
    try std.testing.expectEqualStrings("DemoProto", exactOptionString(decoded.options.items, "java_outer_classname").?);
    try std.testing.expectEqual(@as(i32, 2), fileOptimizeMode(decoded.options.items).?);
    try std.testing.expect(exactOptionBool(decoded.options.items, "java_multiple_files").?);
    try std.testing.expectEqualStrings("example.com/demo;demopb", exactOptionString(decoded.options.items, "go_package").?);
    try std.testing.expect(exactOptionBool(decoded.options.items, "cc_generic_services").?);
    try std.testing.expect(exactOptionBool(decoded.options.items, "java_generic_services").?);
    try std.testing.expect(exactOptionBool(decoded.options.items, "py_generic_services").?);
    try std.testing.expect(exactOptionBool(decoded.options.items, "java_generate_equals_and_hash").?);
    try std.testing.expect(exactOptionBool(decoded.options.items, "deprecated").?);
    try std.testing.expect(exactOptionBool(decoded.options.items, "java_string_check_utf8").?);
    try std.testing.expect(exactOptionBool(decoded.options.items, "cc_enable_arenas").?);
    try std.testing.expectEqualStrings("DEM", exactOptionString(decoded.options.items, "objc_class_prefix").?);
    try std.testing.expectEqualStrings("Example.Demo", exactOptionString(decoded.options.items, "csharp_namespace").?);
    try std.testing.expectEqualStrings("Demo", exactOptionString(decoded.options.items, "swift_prefix").?);
    try std.testing.expectEqualStrings("Demo", exactOptionString(decoded.options.items, "php_class_prefix").?);
    try std.testing.expectEqualStrings("Example\\Demo", exactOptionString(decoded.options.items, "php_namespace").?);
    try std.testing.expectEqualStrings("Example\\Demo\\Metadata", exactOptionString(decoded.options.items, "php_metadata_namespace").?);
    try std.testing.expectEqualStrings("Example::Demo", exactOptionString(decoded.options.items, "ruby_package").?);
    try std.testing.expectEqual(@as(usize, 19), decoded.options.items.len);
}

test "descriptor rejects invalid known option enum values" {
    const allocator = std.testing.allocator;
    {
        var options = wire.Writer.init(allocator);
        defer options.deinit();
        try options.writeInt32(9, 99);
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-optimize.proto");
        try file.writeMessage(8, options.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    inline for (.{ .{ 1, "bad-ctype.proto" }, .{ 6, "bad-jstype.proto" }, .{ 17, "bad-retention.proto" }, .{ 19, "bad-target.proto" } }) |case| {
        var options = wire.Writer.init(allocator);
        defer options.deinit();
        try options.writeInt32(case[0], 99);
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "id");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 5);
        try field.writeMessage(8, options.slice());
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, case[1]);
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var method_options = wire.Writer.init(allocator);
        defer method_options.deinit();
        try method_options.writeInt32(34, 99);
        var method = wire.Writer.init(allocator);
        defer method.deinit();
        try method.writeString(1, "Do");
        try method.writeString(2, ".Req");
        try method.writeString(3, ".Res");
        try method.writeMessage(4, method_options.slice());
        var service = wire.Writer.init(allocator);
        defer service.deinit();
        try service.writeString(1, "Svc");
        try service.writeMessage(2, method.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-idempotency.proto");
        try file.writeMessage(6, service.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
}

test "descriptor preserves message field and enum known options" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message M {
        \\  option no_standard_descriptor_accessor = true;
        \\  option deprecated = true;
        \\  option deprecated_legacy_json_field_conflicts = true;
        \\  message Child {}
        \\  optional bytes data = 1 [
        \\    ctype = CORD,
        \\    deprecated = true,
        \\    debug_redact = true,
        \\    retention = RETENTION_SOURCE,
        \\    targets = TARGET_TYPE_FIELD,
        \\    targets = TARGET_TYPE_MESSAGE
        \\  ];
        \\  optional Child child = 2 [lazy = true, weak = true, unverified_lazy = true];
        \\  optional int64 big = 3 [jstype = JS_STRING];
        \\}
        \\enum E {
        \\  option allow_alias = true;
        \\  option deprecated = true;
        \\  option deprecated_legacy_json_field_conflicts = true;
        \\  A = 0;
        \\  B = 0;
        \\}
    );
    defer file.deinit();
    const bytes = try encodeFileDescriptorProto(allocator, &file, "known-options.proto");
    defer allocator.free(bytes);
    var decoded = try decodeFileDescriptorProto(allocator, bytes);
    defer decoded.deinit();

    const message_options = decoded.findMessage("M").?.options.items;
    try std.testing.expectEqualStrings("no_standard_descriptor_accessor", message_options[0].name);
    try std.testing.expect(message_options[0].value.boolean);
    try std.testing.expectEqualStrings("deprecated", message_options[1].name);
    try std.testing.expect(message_options[1].value.boolean);
    try std.testing.expectEqualStrings("deprecated_legacy_json_field_conflicts", message_options[2].name);
    try std.testing.expect(message_options[2].value.boolean);

    const field_options = decoded.findMessage("M").?.findField("data").?.options.items;
    try std.testing.expectEqualStrings("ctype", field_options[0].name);
    try std.testing.expectEqual(@as(i64, 1), field_options[0].value.integer);
    try std.testing.expectEqualStrings("deprecated", field_options[1].name);
    try std.testing.expect(field_options[1].value.boolean);
    try std.testing.expectEqualStrings("debug_redact", field_options[2].name);
    try std.testing.expect(field_options[2].value.boolean);
    try std.testing.expectEqualStrings("retention", field_options[3].name);
    try std.testing.expectEqual(@as(i64, 2), field_options[3].value.integer);
    try std.testing.expectEqualStrings("targets", field_options[4].name);
    try std.testing.expectEqual(@as(i64, 4), field_options[4].value.integer);
    try std.testing.expectEqualStrings("targets", field_options[5].name);
    try std.testing.expectEqual(@as(i64, 3), field_options[5].value.integer);

    const child_options = decoded.findMessage("M").?.findField("child").?.options.items;
    try std.testing.expectEqualStrings("lazy", child_options[0].name);
    try std.testing.expect(child_options[0].value.boolean);
    try std.testing.expectEqualStrings("weak", child_options[1].name);
    try std.testing.expect(child_options[1].value.boolean);
    try std.testing.expectEqualStrings("unverified_lazy", child_options[2].name);
    try std.testing.expect(child_options[2].value.boolean);

    const big_options = decoded.findMessage("M").?.findField("big").?.options.items;
    try std.testing.expectEqualStrings("jstype", big_options[0].name);
    try std.testing.expectEqual(@as(i64, 1), big_options[0].value.integer);

    const enum_options = decoded.findEnum("E").?.options.items;
    try std.testing.expectEqualStrings("allow_alias", enum_options[0].name);
    try std.testing.expect(enum_options[0].value.boolean);
    try std.testing.expectEqualStrings("deprecated", enum_options[1].name);
    try std.testing.expect(enum_options[1].value.boolean);
    try std.testing.expectEqualStrings("deprecated_legacy_json_field_conflicts", enum_options[2].name);
    try std.testing.expect(enum_options[2].value.boolean);
}

test "descriptor preserves field edition defaults and feature support" {
    const allocator = std.testing.allocator;
    var file = schema.FileDescriptor.init(allocator);
    defer file.deinit();
    file.name = "features.proto";

    var message = schema.MessageDescriptor{ .name = "FeatureSetLike" };
    var field = schema.FieldDescriptor{
        .name = "field_presence",
        .number = 1,
        .cardinality = .optional,
        .kind = .{ .scalar = .int32 },
        .feature_support = .{
            .edition_introduced = .edition_2023,
            .edition_deprecated = .edition_2024,
            .deprecation_warning = "prefer explicit presence",
            .edition_removed = .edition_2026,
            .removal_error = "field_presence override removed",
        },
    };
    try field.edition_defaults.append(allocator, .{ .edition = .legacy, .value = "EXPLICIT" });
    try field.edition_defaults.append(allocator, .{ .edition = .proto3, .value = "IMPLICIT" });
    try field.edition_defaults.append(allocator, .{ .edition = .edition_2023, .value = "EXPLICIT" });
    try message.fields.append(allocator, field);
    try file.messages.append(allocator, message);

    const bytes = try encodeFileDescriptorProto(allocator, &file, file.name);
    defer allocator.free(bytes);
    var decoded = try decodeFileDescriptorProto(allocator, bytes);
    defer decoded.deinit();

    const decoded_field = decoded.findMessage("FeatureSetLike").?.findField("field_presence").?;
    try std.testing.expectEqual(@as(usize, 3), decoded_field.edition_defaults.items.len);
    try std.testing.expectEqual(schema.Edition.legacy, decoded_field.edition_defaults.items[0].edition);
    try std.testing.expectEqualStrings("EXPLICIT", decoded_field.edition_defaults.items[0].value);
    try std.testing.expectEqual(schema.Edition.proto3, decoded_field.edition_defaults.items[1].edition);
    try std.testing.expectEqualStrings("IMPLICIT", decoded_field.edition_defaults.items[1].value);
    try std.testing.expectEqual(schema.Edition.edition_2023, decoded_field.edition_defaults.items[2].edition);
    try std.testing.expectEqualStrings("EXPLICIT", decoded_field.edition_defaults.items[2].value);
    try std.testing.expectEqual(@as(usize, 0), decoded_field.options.items.len);
    try std.testing.expectEqual(schema.Edition.edition_2023, decoded_field.feature_support.?.edition_introduced.?);
    try std.testing.expectEqual(schema.Edition.edition_2024, decoded_field.feature_support.?.edition_deprecated.?);
    try std.testing.expectEqualStrings("prefer explicit presence", decoded_field.feature_support.?.deprecation_warning);
    try std.testing.expectEqual(schema.Edition.edition_2026, decoded_field.feature_support.?.edition_removed.?);
    try std.testing.expectEqualStrings("field_presence override removed", decoded_field.feature_support.?.removal_error);
}

test "descriptor rejects invalid field feature support" {
    const allocator = std.testing.allocator;
    inline for (.{
        .{ @intFromEnum(schema.Edition.edition_2023), @intFromEnum(schema.Edition.edition_2024), 0, false, "missing-warning-feature-support.proto" },
        .{ @intFromEnum(schema.Edition.edition_2024), @intFromEnum(schema.Edition.edition_2023), 0, true, "deprecated-before-introduced-feature-support.proto" },
        .{ @intFromEnum(schema.Edition.edition_2024), 0, @intFromEnum(schema.Edition.edition_2023), false, "removed-before-introduced-feature-support.proto" },
    }) |case| {
        var support = wire.Writer.init(allocator);
        defer support.deinit();
        if (case[0] != 0) try support.writeInt32(1, case[0]);
        if (case[1] != 0) try support.writeInt32(2, case[1]);
        if (case[3]) try support.writeString(3, "warning");
        if (case[2] != 0) try support.writeInt32(4, case[2]);

        var options = wire.Writer.init(allocator);
        defer options.deinit();
        try options.writeMessage(22, support.slice());

        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "field");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 5);
        try field.writeMessage(8, options.slice());

        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());

        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, case[4]);
        try file.writeString(12, "proto2");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
}

test "descriptor preserves unknown option payloads across round-trip" {
    const allocator = std.testing.allocator;
    var unknown = wire.Writer.init(allocator);
    defer unknown.deinit();
    try unknown.writeInt32(50000, 7);

    var field = wire.Writer.init(allocator);
    defer field.deinit();
    try field.writeString(1, "x");
    try field.writeInt32(3, 1);
    try field.writeInt32(4, 1);
    try field.writeInt32(5, 5);
    try field.writeMessage(8, unknown.slice());

    var message = wire.Writer.init(allocator);
    defer message.deinit();
    try message.writeString(1, "M");
    try message.writeMessage(2, field.slice());

    var file = wire.Writer.init(allocator);
    defer file.deinit();
    try file.writeString(1, "unknown-options.proto");
    try file.writeString(12, "proto3");
    try file.writeMessage(4, message.slice());

    var decoded = try decodeFileDescriptorProto(allocator, file.slice());
    defer decoded.deinit();
    const decoded_field = decoded.findMessage("M").?.findField("x").?;
    try std.testing.expectEqual(@as(usize, 1), decoded_field.unknown_options.items.len);
    try std.testing.expectEqualSlices(u8, unknown.slice(), decoded_field.unknown_options.items[0]);

    const encoded = try encodeFileDescriptorProto(allocator, &decoded, "unknown-options.proto");
    defer allocator.free(encoded);
    var decoded_again = try decodeFileDescriptorProto(allocator, encoded);
    defer decoded_again.deinit();
    const round_field = decoded_again.findMessage("M").?.findField("x").?;
    try std.testing.expectEqual(@as(usize, 1), round_field.unknown_options.items.len);
    try std.testing.expectEqualSlices(u8, unknown.slice(), round_field.unknown_options.items[0]);
}

test "descriptor preserves unknown custom feature payloads" {
    const allocator = std.testing.allocator;
    var custom = wire.Writer.init(allocator);
    defer custom.deinit();
    try custom.writeInt32(1000, 1);
    var features = wire.Writer.init(allocator);
    defer features.deinit();
    try features.writeMessage(1000, custom.slice());
    var options = wire.Writer.init(allocator);
    defer options.deinit();
    try options.writeMessage(12, features.slice());
    var message = wire.Writer.init(allocator);
    defer message.deinit();
    try message.writeString(1, "M");
    try message.writeMessage(7, options.slice());
    var file = wire.Writer.init(allocator);
    defer file.deinit();
    try file.writeString(1, "feature-unknown.proto");
    try file.writeString(12, "editions");
    try file.writeInt32(14, @intFromEnum(schema.Edition.edition_2023));
    try file.writeMessage(4, message.slice());

    var decoded = try decodeFileDescriptorProto(allocator, file.slice());
    defer decoded.deinit();
    const decoded_features = decoded.findMessage("M").?.features.?;
    try std.testing.expect(decoded_features.unknown.len != 0);

    const encoded = try encodeFileDescriptorProto(allocator, &decoded, "feature-unknown.proto");
    defer allocator.free(encoded);
    var decoded_again = try decodeFileDescriptorProto(allocator, encoded);
    defer decoded_again.deinit();
    const round_features = decoded_again.findMessage("M").?.features.?;
    try std.testing.expect(round_features.unknown.len != 0);
}

test "descriptor decodes protoc-compatible packed false and oneof defaults" {
    const allocator = std.testing.allocator;

    // packed=false on a non-packable field is legal and appears in protoc
    // descriptor sets.
    var field = wire.Writer.init(allocator);
    defer field.deinit();
    try field.writeString(1, "s");
    try field.writeInt32(3, 1);
    try field.writeInt32(4, 3);
    try field.writeInt32(5, 9);
    var packed_options = wire.Writer.init(allocator);
    defer packed_options.deinit();
    try packed_options.writeBool(2, false);
    try field.writeMessage(8, packed_options.slice());
    var message = wire.Writer.init(allocator);
    defer message.deinit();
    try message.writeString(1, "M");
    try message.writeMessage(2, field.slice());
    var file = wire.Writer.init(allocator);
    defer file.deinit();
    try file.writeString(1, "packed-false.proto");
    try file.writeString(12, "proto3");
    try file.writeMessage(4, message.slice());
    var decoded = try decodeFileDescriptorProto(allocator, file.slice());
    defer decoded.deinit();
    try std.testing.expectEqual(false, decoded.findMessage("M").?.findField("s").?.packed_override.?);

    // proto2 oneof members may carry defaults.
    var oneof_field = wire.Writer.init(allocator);
    defer oneof_field.deinit();
    try oneof_field.writeString(1, "x");
    try oneof_field.writeInt32(3, 1);
    try oneof_field.writeInt32(4, 1);
    try oneof_field.writeInt32(5, 5);
    try oneof_field.writeString(7, "5");
    try oneof_field.writeInt32(9, 0);
    var oneof = wire.Writer.init(allocator);
    defer oneof.deinit();
    try oneof.writeString(1, "pick");
    var oneof_message = wire.Writer.init(allocator);
    defer oneof_message.deinit();
    try oneof_message.writeString(1, "M");
    try oneof_message.writeMessage(2, oneof_field.slice());
    try oneof_message.writeMessage(8, oneof.slice());
    var oneof_file = wire.Writer.init(allocator);
    defer oneof_file.deinit();
    try oneof_file.writeString(1, "oneof-default.proto");
    try oneof_file.writeMessage(4, oneof_message.slice());
    var oneof_decoded = try decodeFileDescriptorProto(allocator, oneof_file.slice());
    defer oneof_decoded.deinit();
    const decoded_field = oneof_decoded.findMessage("M").?.findField("x").?;
    try std.testing.expectEqualStrings("pick", decoded_field.oneof_name.?);
    try std.testing.expectEqual(@as(i64, 5), decoded_field.default_value.?.integer);
}

test "descriptor round-trips explicit symbol visibility" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\edition = "2024";
        \\package demo;
        \\local message LocalMessage { int32 x = 1; }
        \\export enum ExportedEnum { EXPORTED_ENUM_UNKNOWN = 0; }
    );
    defer file.deinit();

    const bytes = try encodeFileDescriptorProto(allocator, &file, "visibility.proto");
    defer allocator.free(bytes);
    var decoded = try decodeFileDescriptorProto(allocator, bytes);
    defer decoded.deinit();
    try std.testing.expectEqual(schema.SymbolVisibility.local, decoded.findMessage("LocalMessage").?.visibility);
    try std.testing.expectEqual(schema.SymbolVisibility.exported, decoded.findEnum("ExportedEnum").?.visibility);
}

test "descriptor round-trips inherited feature values" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\edition = "2023";
        \\package demo;
        \\option features.repeated_field_encoding = EXPANDED;
        \\message M {
        \\  repeated int32 values = 1 [features.field_presence = IMPLICIT];
        \\}
    );
    defer file.deinit();

    const bytes = try encodeFileDescriptorProto(allocator, &file, "feature-inheritance.proto");
    defer allocator.free(bytes);
    var decoded = try decodeFileDescriptorProto(allocator, bytes);
    defer decoded.deinit();

    try std.testing.expectEqual(schema.FeatureSet.RepeatedFieldEncoding.expanded, decoded.features.repeated_field_encoding);
    const field = decoded.findMessage("M").?.findField("values").?;
    try std.testing.expectEqual(schema.FeatureSet.FieldPresence.implicit, field.fieldPresence(&decoded));
    try std.testing.expect(!field.resolvedPacked(&decoded));
    try std.testing.expect(field.features.?.hasPresent("field_presence"));
    try std.testing.expect(!field.features.?.hasPresent("repeated_field_encoding"));
}

test "descriptor preserves FeatureSet options across declaration scopes" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\edition = "2026";
        \\option features.json_format = LEGACY_BEST_EFFORT;
        \\message M {
        \\  option features.enforce_naming_style = STYLE_LEGACY;
        \\  repeated int32 values = 1 [features.repeated_field_encoding = EXPANDED];
        \\  oneof pick {
        \\    option features.enforce_naming_style = STYLE2024;
        \\    string name = 2;
        \\  }
        \\}
        \\enum E {
        \\  option features.enum_type = CLOSED;
        \\  A = 0 [
        \\    features.enforce_naming_style = STYLE2026,
        \\    feature_support = { edition_removed: EDITION_2026 removal_error: "removed enum value" }
        \\  ];
        \\}
        \\service S {
        \\  option features.enforce_naming_style = STYLE2024;
        \\  rpc Do (M) returns (M) {
        \\    option features.enforce_naming_style = STYLE_LEGACY;
        \\  }
        \\}
    );
    defer file.deinit();

    const bytes = try encodeFileDescriptorProto(allocator, &file, "features-all.proto");
    defer allocator.free(bytes);
    var decoded = try decodeFileDescriptorProto(allocator, bytes);
    defer decoded.deinit();

    try std.testing.expectEqual(schema.Syntax.editions, decoded.syntax);
    try std.testing.expectEqual(schema.FeatureSet.JsonFormat.legacy_best_effort, decoded.features.json_format);
    try std.testing.expectEqual(@as(usize, 0), decoded.options.items.len);

    const message = decoded.findMessage("M").?;
    try std.testing.expectEqual(schema.FeatureSet.EnforceNamingStyle.style_legacy, message.features.?.enforce_naming_style);
    try std.testing.expectEqual(@as(usize, 0), message.options.items.len);
    const field = message.findField("values").?;
    try std.testing.expectEqual(schema.FeatureSet.RepeatedFieldEncoding.expanded, field.features.?.repeated_field_encoding);
    try std.testing.expect(!field.resolvedPacked(&decoded));
    try std.testing.expectEqual(@as(usize, 0), field.options.items.len);
    try std.testing.expectEqual(schema.FeatureSet.EnforceNamingStyle.style2024, message.oneofs.items[0].features.?.enforce_naming_style);
    try std.testing.expectEqual(@as(usize, 0), message.oneofs.items[0].options.items.len);

    const enumeration = decoded.findEnum("E").?;
    try std.testing.expectEqual(schema.FeatureSet.EnumType.closed, enumeration.features.?.enum_type);
    try std.testing.expectEqual(@as(usize, 0), enumeration.options.items.len);
    const enum_value = enumeration.values.items[0];
    try std.testing.expectEqual(schema.FeatureSet.EnforceNamingStyle.style2026, enum_value.features.?.enforce_naming_style);
    try std.testing.expectEqual(schema.Edition.edition_2026, enum_value.feature_support.?.edition_removed.?);
    try std.testing.expectEqualStrings("removed enum value", enum_value.feature_support.?.removal_error);
    try std.testing.expectEqual(@as(usize, 0), enum_value.options.items.len);

    const service = decoded.services.items[0];
    try std.testing.expectEqual(schema.FeatureSet.EnforceNamingStyle.style2024, service.features.?.enforce_naming_style);
    try std.testing.expectEqual(@as(usize, 0), service.options.items.len);
    const method = service.methods.items[0];
    try std.testing.expectEqual(schema.FeatureSet.EnforceNamingStyle.style_legacy, method.features.?.enforce_naming_style);
    try std.testing.expectEqual(@as(usize, 0), method.options.items.len);
}

test "descriptor preserves oneof enum value service and method options" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message M {
        \\  oneof pick {
        \\    option (demo.oneof_opt) = "one";
        \\    string name = 1;
        \\  }
        \\}
        \\enum E { A = 0 [deprecated = true, debug_redact = true, (demo.value_opt) = "value"]; }
        \\message Req {}
        \\message Res {}
        \\service S {
        \\  option deprecated = true;
        \\  option (demo.service_opt) = "svc";
        \\  rpc Do (Req) returns (Res) {
        \\    option deprecated = true;
        \\    option idempotency_level = IDEMPOTENT;
        \\    option (demo.method_opt) = "method";
        \\  }
        \\}
    );
    defer file.deinit();
    const bytes = try encodeFileDescriptorProto(allocator, &file, "opts-all.proto");
    defer allocator.free(bytes);
    var decoded = try decodeFileDescriptorProto(allocator, bytes);
    defer decoded.deinit();

    const oneof = decoded.findMessage("M").?.oneofs.items[0];
    try std.testing.expectEqualStrings("(demo.oneof_opt)", oneof.options.items[0].name);
    try std.testing.expectEqualSlices(u8, "one", oneof.options.items[0].value.string);

    const enum_value = decoded.findEnum("E").?.values.items[0];
    try std.testing.expectEqualStrings("deprecated", enum_value.options.items[0].name);
    try std.testing.expect(enum_value.options.items[0].value.boolean);
    try std.testing.expectEqualStrings("debug_redact", enum_value.options.items[1].name);
    try std.testing.expect(enum_value.options.items[1].value.boolean);
    try std.testing.expectEqualStrings("(demo.value_opt)", enum_value.options.items[2].name);
    try std.testing.expectEqualSlices(u8, "value", enum_value.options.items[2].value.string);

    const service = decoded.services.items[0];
    try std.testing.expectEqualStrings("deprecated", service.options.items[0].name);
    try std.testing.expect(service.options.items[0].value.boolean);
    try std.testing.expectEqualStrings("(demo.service_opt)", service.options.items[1].name);
    try std.testing.expectEqualSlices(u8, "svc", service.options.items[1].value.string);

    const method = service.methods.items[0];
    try std.testing.expectEqualStrings("deprecated", method.options.items[0].name);
    try std.testing.expect(method.options.items[0].value.boolean);
    try std.testing.expectEqualStrings("idempotency_level", method.options.items[1].name);
    try std.testing.expectEqual(@as(i64, 2), method.options.items[1].value.integer);
    try std.testing.expectEqualStrings("(demo.method_opt)", method.options.items[2].name);
    try std.testing.expectEqualSlices(u8, "method", method.options.items[2].value.string);
}

test "descriptor preserves enum allow_alias option" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\enum Alias { option allow_alias = true; A = 0; B = 0; }
    );
    defer file.deinit();
    const bytes = try encodeFileDescriptorProto(allocator, &file, "alias.proto");
    defer allocator.free(bytes);
    var decoded = try decodeFileDescriptorProto(allocator, bytes);
    defer decoded.deinit();
    const enumeration = decoded.findEnum("Alias").?;
    try std.testing.expectEqualStrings("allow_alias", enumeration.options.items[0].name);
    try std.testing.expect(enumeration.options.items[0].value.boolean);
    try std.testing.expectEqual(@as(i32, 0), enumeration.findValue("B").?.number);
}

test "descriptor preserves proto2 MessageSet message option" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Host { option message_set_wire_format = true; extensions 4 to max; }
        \\message Ext {}
        \\extend Host { optional Ext ext = 100; }
    );
    defer file.deinit();
    const bytes = try encodeFileDescriptorProto(allocator, &file, "mset.proto");
    defer allocator.free(bytes);
    var decoded = try decodeFileDescriptorProto(allocator, bytes);
    defer decoded.deinit();
    const host = decoded.findMessage("Host").?;
    try std.testing.expect(host.messageSetWireFormat());
    try std.testing.expectEqual(@as(usize, 1), host.options.items.len);
    try std.testing.expectEqualStrings("message_set_wire_format", host.options.items[0].name);
    try std.testing.expect(host.options.items[0].value.boolean);
}

test "descriptor preserves source code info locations" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Person { optional string name = 1; }
    );
    defer file.deinit();
    file.source_code_info.deinit(allocator);
    file.source_code_info = .{};

    var file_location = schema.SourceCodeInfo.Location{};
    try file_location.path.appendSlice(allocator, &.{});
    try file_location.span.appendSlice(allocator, &.{ 0, 0, 2, 1 });
    file_location.leading_comments = "file leading\n";
    try file_location.leading_detached_comments.append(allocator, "detached paragraph\n");
    try file.source_code_info.locations.append(allocator, file_location);

    var field_location = schema.SourceCodeInfo.Location{};
    try field_location.path.appendSlice(allocator, &.{ 4, 0, 2, 0 });
    try field_location.span.appendSlice(allocator, &.{ 2, 2, 2, 35 });
    field_location.trailing_comments = "field trailing\n";
    try file.source_code_info.locations.append(allocator, field_location);

    const bytes = try encodeFileDescriptorProto(allocator, &file, "person.proto");
    defer allocator.free(bytes);
    var decoded = try decodeFileDescriptorProto(allocator, bytes);
    defer decoded.deinit();

    try std.testing.expectEqual(@as(usize, 2), decoded.source_code_info.locations.items.len);
    try std.testing.expectEqualSlices(i32, &.{}, decoded.source_code_info.locations.items[0].path.items);
    try std.testing.expectEqualSlices(i32, &.{ 0, 0, 2, 1 }, decoded.source_code_info.locations.items[0].span.items);
    try std.testing.expectEqualStrings("file leading\n", decoded.source_code_info.locations.items[0].leading_comments.?);
    try std.testing.expectEqualStrings("detached paragraph\n", decoded.source_code_info.locations.items[0].leading_detached_comments.items[0]);
    try std.testing.expectEqualSlices(i32, &.{ 4, 0, 2, 0 }, decoded.source_code_info.locations.items[1].path.items);
    try std.testing.expectEqualSlices(i32, &.{ 2, 2, 2, 35 }, decoded.source_code_info.locations.items[1].span.items);
    try std.testing.expectEqualStrings("field trailing\n", decoded.source_code_info.locations.items[1].trailing_comments.?);
}

test "descriptor round-trips parser source code info comments and nested paths" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\// Outer leading
        \\message Outer {
        \\  // Child leading
        \\  message Child { optional int32 id = 1; }
        \\  // child field leading
        \\  optional Child child = 1; // child field trailing
        \\}
    );
    defer file.deinit();

    const bytes = try encodeFileDescriptorProto(allocator, &file, "source-comments.proto");
    defer allocator.free(bytes);
    var decoded = try decodeFileDescriptorProto(allocator, bytes);
    defer decoded.deinit();

    const outer_location = findSourceLocation(&decoded, &.{ 4, 0 }).?;
    try std.testing.expectEqualStrings("Outer leading\n", outer_location.leading_comments.?);
    const nested_location = findSourceLocation(&decoded, &.{ 4, 0, 3, 0 }).?;
    try std.testing.expectEqualStrings("Child leading\n", nested_location.leading_comments.?);
    const field_location = findSourceLocation(&decoded, &.{ 4, 0, 2, 0 }).?;
    try std.testing.expectEqualStrings("child field leading\n", field_location.leading_comments.?);
    try std.testing.expectEqualStrings("child field trailing\n", field_location.trailing_comments.?);
    const nested_field_location = findSourceLocation(&decoded, &.{ 4, 0, 3, 0, 2, 0 }).?;
    try std.testing.expectEqual(@as(usize, 4), nested_field_location.span.items.len);
}

test "descriptor round-trips group field source info" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Parent {
        \\  optional group Box = 1 {
        \\    optional int32 id = 2 [deprecated = true];
        \\  }
        \\}
    );
    defer file.deinit();

    const bytes = try encodeFileDescriptorProto(allocator, &file, "group-source.proto");
    defer allocator.free(bytes);
    var decoded = try decodeFileDescriptorProto(allocator, bytes);
    defer decoded.deinit();

    const group_location = findSourceLocation(&decoded, &.{ 4, 0, 3, 0 }).?;
    const group_field_location = findSourceLocation(&decoded, &.{ 4, 0, 3, 0, 2, 0 }).?;
    const group_field_option_location = findSourceLocation(&decoded, &.{ 4, 0, 3, 0, 2, 0, 8 }).?;
    try std.testing.expectEqual(@as(usize, 4), group_location.span.items.len);
    try std.testing.expectEqual(@as(usize, 4), group_field_location.span.items.len);
    try std.testing.expectEqual(@as(usize, 4), group_field_option_location.span.items.len);
}

test "descriptor round-trips reserved source info" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message M {
        \\  reserved 5 to 10;
        \\  reserved "old_name";
        \\}
        \\enum E {
        \\  A = 0;
        \\  reserved 2 to 4;
        \\  reserved "OLD";
        \\}
    );
    defer file.deinit();

    const bytes = try encodeFileDescriptorProto(allocator, &file, "reserved-source.proto");
    defer allocator.free(bytes);
    var decoded = try decodeFileDescriptorProto(allocator, bytes);
    defer decoded.deinit();

    inline for (.{ &.{ 4, 0, 9, 0 }, &.{ 4, 0, 10, 0 }, &.{ 5, 0, 4, 0 }, &.{ 5, 0, 5, 0 } }) |path| {
        const location = findSourceLocation(&decoded, path).?;
        try std.testing.expectEqual(@as(usize, 4), location.span.items.len);
    }
}

test "descriptor round-trips field option source info" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message M {
        \\  optional string name = 1 [deprecated = true, default = "anon"];
        \\}
    );
    defer file.deinit();

    const bytes = try encodeFileDescriptorProto(allocator, &file, "field-options-source.proto");
    defer allocator.free(bytes);
    var decoded = try decodeFileDescriptorProto(allocator, bytes);
    defer decoded.deinit();

    const field_location = findSourceLocation(&decoded, &.{ 4, 0, 2, 0 }).?;
    const option_location = findSourceLocation(&decoded, &.{ 4, 0, 2, 0, 8 }).?;
    try std.testing.expectEqual(@as(usize, 4), field_location.span.items.len);
    try std.testing.expectEqual(@as(usize, 4), option_location.span.items.len);
    try std.testing.expect(option_location.span.items[0] >= field_location.span.items[0]);
}

test "descriptor round-trips extension field option source info" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Host { extensions 100 to max; }
        \\extend Host {
        \\  optional string tag = 100 [deprecated = true, default = "x"];
        \\}
    );
    defer file.deinit();

    const bytes = try encodeFileDescriptorProto(allocator, &file, "extension-field-options-source.proto");
    defer allocator.free(bytes);
    var decoded = try decodeFileDescriptorProto(allocator, bytes);
    defer decoded.deinit();

    const extension_location = findSourceLocation(&decoded, &.{ 7, 0 }).?;
    const option_location = findSourceLocation(&decoded, &.{ 7, 0, 8 }).?;
    try std.testing.expectEqual(@as(usize, 4), extension_location.span.items.len);
    try std.testing.expectEqual(@as(usize, 4), option_location.span.items.len);
    try std.testing.expect(option_location.span.items[0] >= extension_location.span.items[0]);
}

test "descriptor round-trips oneof option source info" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message M {
        \\  oneof choice {
        \\    option (demo.oneof_opt) = true;
        \\    string name = 1;
        \\  }
        \\}
    );
    defer file.deinit();

    const bytes = try encodeFileDescriptorProto(allocator, &file, "oneof-options-source.proto");
    defer allocator.free(bytes);
    var decoded = try decodeFileDescriptorProto(allocator, bytes);
    defer decoded.deinit();

    const oneof_location = findSourceLocation(&decoded, &.{ 4, 0, 8, 0 }).?;
    const option_location = findSourceLocation(&decoded, &.{ 4, 0, 8, 0, 2 }).?;
    try std.testing.expectEqual(@as(usize, 4), oneof_location.span.items.len);
    try std.testing.expectEqual(@as(usize, 4), option_location.span.items.len);
    try std.testing.expect(option_location.span.items[0] >= oneof_location.span.items[0]);
}

test "descriptor round-trips extension range option source info" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\edition = "2024";
        \\message Host {
        \\  extensions 100 to 101, 200 to 201 [
        \\    verification = UNVERIFIED,
        \\    features.enforce_naming_style = STYLE_LEGACY
        \\  ];
        \\}
    );
    defer file.deinit();

    const bytes = try encodeFileDescriptorProto(allocator, &file, "extension-range-options-source.proto");
    defer allocator.free(bytes);
    var decoded = try decodeFileDescriptorProto(allocator, bytes);
    defer decoded.deinit();

    const first_range_options = findSourceLocation(&decoded, &.{ 4, 0, 5, 0, 3 }).?;
    const second_range_options = findSourceLocation(&decoded, &.{ 4, 0, 5, 1, 3 }).?;
    try std.testing.expectEqual(@as(usize, 4), first_range_options.span.items.len);
    try std.testing.expectEqual(@as(usize, 4), second_range_options.span.items.len);
    try std.testing.expectEqualSlices(i32, first_range_options.span.items, second_range_options.span.items);
}

test "descriptor round-trips enum value option source info" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\enum Kind {
        \\  UNKNOWN = 0;
        \\  ACTIVE = 1 [deprecated = true];
        \\}
    );
    defer file.deinit();

    const bytes = try encodeFileDescriptorProto(allocator, &file, "enum-value-options-source.proto");
    defer allocator.free(bytes);
    var decoded = try decodeFileDescriptorProto(allocator, bytes);
    defer decoded.deinit();

    const value_location = findSourceLocation(&decoded, &.{ 5, 0, 2, 1 }).?;
    const option_location = findSourceLocation(&decoded, &.{ 5, 0, 2, 1, 3 }).?;
    try std.testing.expectEqual(@as(usize, 4), value_location.span.items.len);
    try std.testing.expectEqual(@as(usize, 4), option_location.span.items.len);
    try std.testing.expect(option_location.span.items[0] >= value_location.span.items[0]);
}

test "descriptor rejects invalid source code info locations" {
    const allocator = std.testing.allocator;
    {
        const bytes = try testFileWithSourceLocation(allocator, &.{-1}, &.{ 0, 0, 0, 1 });
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        const bytes = try testFileWithSourceLocation(allocator, &.{}, &.{ -1, 0, 0, 1 });
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        const bytes = try testFileWithSourceLocation(allocator, &.{}, &.{ 2, 5, 1, 0 });
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
}

fn testFileWithSourceLocation(allocator: std.mem.Allocator, path: []const i32, span: []const i32) ![]u8 {
    var location = wire.Writer.init(allocator);
    defer location.deinit();
    try writePackedInt32List(allocator, 1, path, &location);
    try writePackedInt32List(allocator, 2, span, &location);

    var source = wire.Writer.init(allocator);
    defer source.deinit();
    try source.writeMessage(1, location.slice());

    var file = wire.Writer.init(allocator);
    errdefer file.deinit();
    try file.writeString(12, "proto2");
    try file.writeMessage(9, source.slice());
    return try file.toOwnedSlice();
}

fn findSourceLocation(file: *const schema.FileDescriptor, path: []const i32) ?*const schema.SourceCodeInfo.Location {
    for (file.source_code_info.locations.items) |*location| {
        if (std.mem.eql(i32, location.path.items, path)) return location;
    }
    return null;
}

test "descriptor preserves extension range options" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\edition = "2024";
        \\package demo;
        \\message Host {
        \\  extensions 100 to max [
        \\    declaration = { number: 100 full_name: ".demo.ext" type: ".demo.Ext" reserved: true },
        \\    verification = DECLARATION,
        \\    features.enforce_naming_style = STYLE_LEGACY
        \\  ];
        \\}
        \\message Ext {}
    );
    defer file.deinit();

    const bytes = try encodeFileDescriptorProto(allocator, &file, "ext-range.proto");
    defer allocator.free(bytes);
    var decoded = try decodeFileDescriptorProto(allocator, bytes);
    defer decoded.deinit();

    const range = &decoded.findMessage("Host").?.extension_ranges.items[0];
    try std.testing.expectEqual(@as(i64, 100), range.start);
    try std.testing.expectEqual(@as(?i64, @as(i64, std.math.maxInt(wire.FieldNumber)) + 1), range.end);
    try std.testing.expectEqual(@as(usize, 1), range.declarations.items.len);
    try std.testing.expectEqual(@as(i32, 100), range.declarations.items[0].number);
    try std.testing.expectEqualStrings(".demo.ext", range.declarations.items[0].full_name);
    try std.testing.expectEqualStrings(".demo.Ext", range.declarations.items[0].type_name);
    try std.testing.expect(range.declarations.items[0].reserved);
    try std.testing.expectEqual(schema.ExtensionRangeVerification.declaration, range.verification.?);
    try std.testing.expectEqual(schema.FeatureSet.EnforceNamingStyle.style_legacy, range.features.?.enforce_naming_style);
}

test "descriptor encodes max range ends" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message HostExt { extensions 100 to max; }
        \\message HostReserved { reserved 200 to max; }
        \\message MsExt { option message_set_wire_format = true; extensions 4 to max; }
        \\message MsReserved { option message_set_wire_format = true; extensions 4 to 4; reserved 5 to max; }
        \\enum E { A = 0; reserved 10 to max; }
    );
    defer file.deinit();

    const bytes = try encodeFileDescriptorProto(allocator, &file, "max-ranges.proto");
    defer allocator.free(bytes);
    var decoded = try decodeFileDescriptorProto(allocator, bytes);
    defer decoded.deinit();

    const field_max_end: i64 = @as(i64, std.math.maxInt(wire.FieldNumber)) + 1;
    const host_ext = decoded.findMessage("HostExt").?;
    try std.testing.expectEqual(@as(?i64, field_max_end), host_ext.extension_ranges.items[0].end);
    const host_reserved = decoded.findMessage("HostReserved").?;
    try std.testing.expectEqual(@as(?i64, field_max_end), host_reserved.reserved_ranges.items[0].end);
    const ms_ext = decoded.findMessage("MsExt").?;
    try std.testing.expectEqual(@as(?i64, std.math.maxInt(i32)), ms_ext.extension_ranges.items[0].end);
    const ms_reserved = decoded.findMessage("MsReserved").?;
    try std.testing.expectEqual(@as(?i64, 5), ms_reserved.extension_ranges.items[0].end);
    try std.testing.expectEqual(@as(?i64, std.math.maxInt(i32)), ms_reserved.reserved_ranges.items[0].end);
    try std.testing.expectEqual(@as(?i64, @as(i64, std.math.maxInt(i32)) + 1), decoded.findEnum("E").?.reserved_ranges.items[0].end);
}

test "descriptor rejects extensions that violate decoded declarations" {
    const allocator = std.testing.allocator;
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        var host = schema.MessageDescriptor{ .name = "Host" };
        var range = schema.ExtensionRange{ .start = 100, .end = 200 };
        try range.declarations.append(allocator, .{ .number = 100, .full_name = ".demo.tag", .type_name = "int32" });
        try host.extension_ranges.append(allocator, range);
        try file.messages.append(allocator, host);
        try file.extensions.append(allocator, .{ .name = "tag", .number = 100, .cardinality = .optional, .kind = .{ .scalar = .string }, .extendee = "Host" });
        const bytes = try encodeFileDescriptorProto(allocator, &file, "bad-ext-decl.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        var host = schema.MessageDescriptor{ .name = "Host" };
        var range = schema.ExtensionRange{ .start = 100, .end = 200 };
        try range.declarations.append(allocator, .{ .number = 100, .full_name = ".demo.tag", .type_name = "int32" });
        try host.extension_ranges.append(allocator, range);
        try file.messages.append(allocator, host);
        try file.extensions.append(allocator, .{ .name = "other", .number = 101, .cardinality = .optional, .kind = .{ .scalar = .int32 }, .extendee = "Host" });
        const bytes = try encodeFileDescriptorProto(allocator, &file, "undeclared-ext-in-declared-range.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        var host = schema.MessageDescriptor{ .name = "Host" };
        var range = schema.ExtensionRange{ .start = 100, .end = 200 };
        try range.declarations.append(allocator, .{ .number = 100, .full_name = ".demo.tag", .type_name = "int32", .reserved = true });
        try host.extension_ranges.append(allocator, range);
        try file.messages.append(allocator, host);
        try file.extensions.append(allocator, .{ .name = "tag", .number = 100, .cardinality = .optional, .kind = .{ .scalar = .int32 }, .extendee = "Host" });
        const bytes = try encodeFileDescriptorProto(allocator, &file, "reserved-ext-decl.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        var host = schema.MessageDescriptor{ .name = "Host" };
        var range = schema.ExtensionRange{ .start = 100, .end = 200 };
        try range.declarations.append(allocator, .{ .number = 100, .full_name = ".demo.other", .type_name = "int32" });
        try host.extension_ranges.append(allocator, range);
        try file.messages.append(allocator, host);
        try file.extensions.append(allocator, .{ .name = "tag", .number = 100, .cardinality = .optional, .kind = .{ .scalar = .int32 }, .extendee = "Host" });
        const bytes = try encodeFileDescriptorProto(allocator, &file, "name-ext-decl.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        var host = schema.MessageDescriptor{ .name = "Host" };
        var range = schema.ExtensionRange{ .start = 100, .end = 200 };
        try range.declarations.append(allocator, .{ .number = 100, .full_name = ".demo.tags", .type_name = "int32" });
        try host.extension_ranges.append(allocator, range);
        try file.messages.append(allocator, host);
        try file.extensions.append(allocator, .{ .name = "tags", .number = 100, .cardinality = .repeated, .kind = .{ .scalar = .int32 }, .extendee = "Host" });
        const bytes = try encodeFileDescriptorProto(allocator, &file, "repeated-ext-decl.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        var host = schema.MessageDescriptor{ .name = "Host" };
        var range = schema.ExtensionRange{ .start = 100, .end = 200 };
        try range.declarations.append(allocator, .{ .number = 100, .full_name = ".demo.tag", .type_name = "int32", .repeated = true });
        try host.extension_ranges.append(allocator, range);
        try file.messages.append(allocator, host);
        try file.extensions.append(allocator, .{ .name = "tag", .number = 100, .cardinality = .optional, .kind = .{ .scalar = .int32 }, .extendee = "Host" });
        const bytes = try encodeFileDescriptorProto(allocator, &file, "singular-ext-decl.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        file.package = "other";
        var host = schema.MessageDescriptor{ .name = "Host" };
        var range = schema.ExtensionRange{ .start = 100, .end = 200 };
        try range.declarations.append(allocator, .{ .number = 100, .full_name = ".demo.tag", .type_name = "int32" });
        try host.extension_ranges.append(allocator, range);
        try file.messages.append(allocator, host);
        try file.extensions.append(allocator, .{ .name = "tag", .number = 100, .cardinality = .optional, .kind = .{ .scalar = .int32 }, .extendee = "Host" });
        const bytes = try encodeFileDescriptorProto(allocator, &file, "wrong-package-ext-decl.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        file.package = "other";
        var host = schema.MessageDescriptor{ .name = "Host" };
        var range = schema.ExtensionRange{ .start = 100, .end = 200 };
        try range.declarations.append(allocator, .{ .number = 100, .full_name = ".other.tag", .type_name = ".demo.Ext" });
        try host.extension_ranges.append(allocator, range);
        try file.messages.append(allocator, host);
        try file.messages.append(allocator, .{ .name = "Ext" });
        try file.extensions.append(allocator, .{ .name = "tag", .number = 100, .cardinality = .optional, .kind = .{ .message = "Ext" }, .extendee = "Host" });
        const bytes = try encodeFileDescriptorProto(allocator, &file, "wrong-package-ext-type-decl.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        var host = schema.MessageDescriptor{ .name = "Host" };
        var range = schema.ExtensionRange{ .start = 100, .end = 200 };
        try range.declarations.append(allocator, .{ .number = 100, .full_name = ".missing.type" });
        try host.extension_ranges.append(allocator, range);
        try file.messages.append(allocator, host);
        const bytes = try encodeFileDescriptorProto(allocator, &file, "missing-decl-type.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        var host = schema.MessageDescriptor{ .name = "Host" };
        var range = schema.ExtensionRange{ .start = 100, .end = 200, .verification = .unverified };
        try range.declarations.append(allocator, .{ .number = 100, .full_name = ".bad.verification", .type_name = "int32" });
        try host.extension_ranges.append(allocator, range);
        try file.messages.append(allocator, host);
        const bytes = try encodeFileDescriptorProto(allocator, &file, "unverified-decl.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        var host = schema.MessageDescriptor{ .name = "Host" };
        var range = schema.ExtensionRange{ .start = 100, .end = 200 };
        try range.declarations.append(allocator, .{ .number = 100, .full_name = "missing.dot", .type_name = "int32" });
        try host.extension_ranges.append(allocator, range);
        try file.messages.append(allocator, host);
        const bytes = try encodeFileDescriptorProto(allocator, &file, "decl-name-missing-dot.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        var host = schema.MessageDescriptor{ .name = "Host" };
        var range = schema.ExtensionRange{ .start = 100, .end = 200 };
        try range.declarations.append(allocator, .{ .number = 100, .full_name = ".bad.type", .type_name = ".b#az" });
        try host.extension_ranges.append(allocator, range);
        try file.messages.append(allocator, host);
        const bytes = try encodeFileDescriptorProto(allocator, &file, "bad-decl-type.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        var host = schema.MessageDescriptor{ .name = "Host" };
        var first = schema.ExtensionRange{ .start = 100, .end = 101 };
        try first.declarations.append(allocator, .{ .number = 100, .full_name = ".dup", .type_name = "int32" });
        try host.extension_ranges.append(allocator, first);
        var second = schema.ExtensionRange{ .start = 101, .end = 102 };
        try second.declarations.append(allocator, .{ .number = 101, .full_name = ".dup", .type_name = "int32" });
        try host.extension_ranges.append(allocator, second);
        try file.messages.append(allocator, host);
        const bytes = try encodeFileDescriptorProto(allocator, &file, "duplicate-decl-name.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        var host = schema.MessageDescriptor{ .name = "Host" };
        const range = schema.ExtensionRange{ .start = 100, .end = 200, .verification = .declaration };
        try host.extension_ranges.append(allocator, range);
        try file.messages.append(allocator, host);
        try file.extensions.append(allocator, .{ .name = "tag", .number = 100, .cardinality = .optional, .kind = .{ .scalar = .int32 }, .extendee = "Host" });
        const bytes = try encodeFileDescriptorProto(allocator, &file, "missing-ext-decl.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
}

test "descriptor rejects duplicate decoded extensions" {
    const allocator = std.testing.allocator;
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        var host = schema.MessageDescriptor{ .name = "Host" };
        try host.extension_ranges.append(allocator, .{ .start = 100, .end = 200 });
        try file.messages.append(allocator, host);
        try file.extensions.append(allocator, .{ .name = "first", .number = 100, .cardinality = .optional, .kind = .{ .scalar = .int32 }, .extendee = "Host" });
        try file.extensions.append(allocator, .{ .name = "second", .number = 100, .cardinality = .optional, .kind = .{ .scalar = .int32 }, .extendee = "Host" });
        const bytes = try encodeFileDescriptorProto(allocator, &file, "dup-ext-number.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        var host = schema.MessageDescriptor{ .name = "Host" };
        try host.extension_ranges.append(allocator, .{ .start = 100, .end = 200 });
        try file.messages.append(allocator, host);
        try file.extensions.append(allocator, .{ .name = "Host", .number = 100, .cardinality = .optional, .kind = .{ .scalar = .int32 }, .extendee = "Host" });
        const bytes = try encodeFileDescriptorProto(allocator, &file, "ext-type-name-conflict.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        var host = schema.MessageDescriptor{ .name = "Host" };
        try host.extension_ranges.append(allocator, .{ .start = 100, .end = 200 });
        var enumeration = schema.EnumDescriptor{ .name = "E" };
        try enumeration.values.append(allocator, .{ .name = "tag", .number = 0 });
        try file.messages.append(allocator, host);
        try file.enums.append(allocator, enumeration);
        try file.extensions.append(allocator, .{ .name = "tag", .number = 100, .cardinality = .optional, .kind = .{ .scalar = .int32 }, .extendee = "Host" });
        const bytes = try encodeFileDescriptorProto(allocator, &file, "ext-enum-value-name-conflict.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        var host = schema.MessageDescriptor{ .name = "Host" };
        try host.extension_ranges.append(allocator, .{ .start = 100, .end = 200 });
        var scope = schema.MessageDescriptor{ .name = "Scope" };
        try scope.fields.append(allocator, .{ .name = "tag", .number = 1, .cardinality = .optional, .kind = .{ .scalar = .int32 } });
        try scope.extensions.append(allocator, .{ .name = "tag", .number = 101, .cardinality = .optional, .kind = .{ .scalar = .string }, .extendee = "Host" });
        try file.messages.append(allocator, host);
        try file.messages.append(allocator, scope);
        const bytes = try encodeFileDescriptorProto(allocator, &file, "nested-ext-field-name-conflict.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        var host = schema.MessageDescriptor{ .name = "Host" };
        try host.extension_ranges.append(allocator, .{ .start = 100, .end = 200 });
        var scope = schema.MessageDescriptor{ .name = "Scope" };
        try scope.extensions.append(allocator, .{ .name = "tag", .number = 101, .cardinality = .optional, .kind = .{ .scalar = .string }, .extendee = "Host" });
        try file.messages.append(allocator, host);
        try file.messages.append(allocator, scope);
        try file.extensions.append(allocator, .{ .name = "tag", .number = 100, .cardinality = .optional, .kind = .{ .scalar = .string }, .extendee = "Host" });
        const bytes = try encodeFileDescriptorProto(allocator, &file, "scoped-ext-name.proto");
        defer allocator.free(bytes);
        var decoded = try decodeFileDescriptorProto(allocator, bytes);
        defer decoded.deinit();
        try std.testing.expect(decoded.extensions.items[0].full_name == null);
        try std.testing.expectEqualStrings("tag", decoded.extensions.items[0].name);
        try std.testing.expectEqualStrings("Scope.tag", decoded.findMessage("Scope").?.extensions.items[0].full_name.?);
    }
}

test "descriptor encodes and decodes generated code info" {
    const allocator = std.testing.allocator;
    var generated = schema.GeneratedCodeInfo{};
    defer generated.deinit(allocator);
    var annotation = schema.GeneratedCodeInfo.Annotation{};
    try annotation.path.appendSlice(allocator, &.{ 4, 0, 2, 0 });
    annotation.source_file = "demo.proto";
    annotation.begin = 10;
    annotation.end = 20;
    annotation.semantic = .set;
    try generated.annotations.append(allocator, annotation);

    const bytes = try encodeGeneratedCodeInfo(allocator, &generated);
    defer allocator.free(bytes);
    var decoded = try decodeGeneratedCodeInfo(allocator, bytes);
    defer decoded.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), decoded.annotations.items.len);
    try std.testing.expectEqualSlices(i32, &.{ 4, 0, 2, 0 }, decoded.annotations.items[0].path.items);
    try std.testing.expectEqualStrings("demo.proto", decoded.annotations.items[0].source_file.?);
    try std.testing.expectEqual(@as(i32, 10), decoded.annotations.items[0].begin.?);
    try std.testing.expectEqual(@as(i32, 20), decoded.annotations.items[0].end.?);
    try std.testing.expectEqual(schema.GeneratedCodeInfo.Semantic.set, decoded.annotations.items[0].semantic.?);
}

test "descriptor rejects invalid enum descriptors" {
    const allocator = std.testing.allocator;
    {
        var enum_writer = wire.Writer.init(allocator);
        defer enum_writer.deinit();
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-enum.proto");
        try file.writeMessage(5, enum_writer.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var value = wire.Writer.init(allocator);
        defer value.deinit();
        try value.writeInt32(2, 0);
        var enum_writer = wire.Writer.init(allocator);
        defer enum_writer.deinit();
        try enum_writer.writeString(1, "Bad");
        try enum_writer.writeMessage(2, value.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-value.proto");
        try file.writeMessage(5, enum_writer.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var value = wire.Writer.init(allocator);
        defer value.deinit();
        try value.writeString(1, "A");
        try value.writeInt32(2, 0);
        var enum_writer = wire.Writer.init(allocator);
        defer enum_writer.deinit();
        try enum_writer.writeString(1, "Bad");
        try enum_writer.writeMessage(2, value.slice());
        try enum_writer.writeMessage(2, value.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "dup-value.proto");
        try file.writeMessage(5, enum_writer.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var first = wire.Writer.init(allocator);
        defer first.deinit();
        try first.writeString(1, "A");
        try first.writeInt32(2, 0);
        var second = wire.Writer.init(allocator);
        defer second.deinit();
        try second.writeString(1, "B");
        try second.writeInt32(2, 0);
        var enum_writer = wire.Writer.init(allocator);
        defer enum_writer.deinit();
        try enum_writer.writeString(1, "Bad");
        try enum_writer.writeMessage(2, first.slice());
        try enum_writer.writeMessage(2, second.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "dup-number.proto");
        try file.writeMessage(5, enum_writer.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var value = wire.Writer.init(allocator);
        defer value.deinit();
        try value.writeString(1, "A");
        try value.writeInt32(2, 0);
        var options = wire.Writer.init(allocator);
        defer options.deinit();
        try options.writeBool(2, false);
        var enum_writer = wire.Writer.init(allocator);
        defer enum_writer.deinit();
        try enum_writer.writeString(1, "Bad");
        try enum_writer.writeMessage(2, value.slice());
        try enum_writer.writeMessage(3, options.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "allow-alias-false.proto");
        try file.writeMessage(5, enum_writer.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var first = wire.Writer.init(allocator);
        defer first.deinit();
        try first.writeString(1, "A");
        try first.writeInt32(2, 0);
        var second = wire.Writer.init(allocator);
        defer second.deinit();
        try second.writeString(1, "B");
        try second.writeInt32(2, 1);
        var options = wire.Writer.init(allocator);
        defer options.deinit();
        try options.writeBool(2, true);
        var enum_writer = wire.Writer.init(allocator);
        defer enum_writer.deinit();
        try enum_writer.writeString(1, "Bad");
        try enum_writer.writeMessage(2, first.slice());
        try enum_writer.writeMessage(2, second.slice());
        try enum_writer.writeMessage(3, options.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "unused-allow-alias.proto");
        try file.writeMessage(5, enum_writer.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var first = wire.Writer.init(allocator);
        defer first.deinit();
        try first.writeString(1, "MY_ENUM_FOO");
        try first.writeInt32(2, 1);
        var second = wire.Writer.init(allocator);
        defer second.deinit();
        try second.writeString(1, "FOO");
        try second.writeInt32(2, 2);
        var enum_writer = wire.Writer.init(allocator);
        defer enum_writer.deinit();
        try enum_writer.writeString(1, "MyEnum");
        try enum_writer.writeMessage(2, first.slice());
        try enum_writer.writeMessage(2, second.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "enum-prefix-conflict.proto");
        try file.writeMessage(5, enum_writer.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        var enumeration = schema.EnumDescriptor{ .name = "Alias" };
        try enumeration.options.append(allocator, .{ .name = "allow_alias", .value = .{ .boolean = true } });
        try enumeration.values.append(allocator, .{ .name = "ALIAS_FOO", .number = 1 });
        try enumeration.values.append(allocator, .{ .name = "FOO", .number = 1 });
        try file.enums.append(allocator, enumeration);
        const bytes = try encodeFileDescriptorProto(allocator, &file, "enum-prefix-alias.proto");
        defer allocator.free(bytes);
        var decoded = try decodeFileDescriptorProto(allocator, bytes);
        defer decoded.deinit();
        try std.testing.expect(decoded.findEnum("Alias") != null);
    }
    {
        var value = wire.Writer.init(allocator);
        defer value.deinit();
        try value.writeString(1, "ONE");
        try value.writeInt32(2, 1);
        var enum_writer = wire.Writer.init(allocator);
        defer enum_writer.deinit();
        try enum_writer.writeString(1, "Bad");
        try enum_writer.writeMessage(2, value.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "proto3-enum-first-nonzero.proto");
        try file.writeString(12, "proto3");
        try file.writeMessage(5, enum_writer.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var value = wire.Writer.init(allocator);
        defer value.deinit();
        try value.writeString(1, "ONE");
        try value.writeInt32(2, 1);
        var enum_writer = wire.Writer.init(allocator);
        defer enum_writer.deinit();
        try enum_writer.writeString(1, "Bad");
        try enum_writer.writeMessage(2, value.slice());
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Container");
        try message.writeMessage(4, enum_writer.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "proto3-nested-enum-first-nonzero.proto");
        try file.writeString(12, "proto3");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        var first = schema.EnumDescriptor{ .name = "First" };
        try first.values.append(allocator, .{ .name = "SHARED", .number = 0 });
        var second = schema.EnumDescriptor{ .name = "Second" };
        try second.values.append(allocator, .{ .name = "SHARED", .number = 0 });
        try file.enums.append(allocator, first);
        try file.enums.append(allocator, second);
        const bytes = try encodeFileDescriptorProto(allocator, &file, "enum-value-conflict.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        var msg = schema.MessageDescriptor{ .name = "M" };
        try msg.fields.append(allocator, .{ .name = "hit", .number = 1, .cardinality = .optional, .kind = .{ .scalar = .int32 } });
        var enumeration = schema.EnumDescriptor{ .name = "Bad" };
        try enumeration.values.append(allocator, .{ .name = "hit", .number = 0 });
        try msg.enums.append(allocator, enumeration);
        try file.messages.append(allocator, msg);
        const bytes = try encodeFileDescriptorProto(allocator, &file, "nested-enum-value-conflict.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
}
