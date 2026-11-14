const parser = @import("parser.zig");
const registry_mod = @import("registry.zig");
const schema = @import("schema.zig");
const std = @import("std");
const wire = @import("wire.zig");
const module = @import("dynamic.zig");
const test_helpers = module.test_helpers;
const DefaultValue = module.DefaultValue;
const DynamicMessage = module.DynamicMessage;
const MapEntry = module.MapEntry;
const cloneValue = module.cloneValue;
const exerciseCloneValueCleanup = module.test_helpers.exerciseCloneValueCleanup;
const writeMessageSetItem = module.test_helpers.writeMessageSetItem;

test "dynamic cloneValue cleans up allocation failures" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, exerciseCloneValueCleanup, .{});
}

test "dynamic message encodes decodes scalar and preserves unknown fields" {
    const allocator = std.testing.allocator;
    var file = schema.FileDescriptor.init(allocator);
    defer file.deinit();
    file.setSyntax(.proto3);

    var msg = schema.MessageDescriptor{ .name = "Person" };
    try msg.fields.append(allocator, .{ .name = "id", .number = 1, .kind = .{ .scalar = .int32 } });
    try msg.fields.append(allocator, .{ .name = "name", .number = 2, .kind = .{ .scalar = .string } });
    try file.messages.append(allocator, msg);

    var dyn = DynamicMessage.init(allocator, &file.messages.items[0]);
    defer dyn.deinit();
    try dyn.add(file.messages.items[0].findField("id").?, .{ .int32 = 42 });

    var w = wire.Writer.init(allocator);
    defer w.deinit();
    try dyn.encode(&file, &w);
    try w.writeUInt32(99, 7);

    var decoded = DynamicMessage.init(allocator, &file.messages.items[0]);
    defer decoded.deinit();
    try decoded.decode(&file, w.slice());
    try std.testing.expectEqual(@as(i32, 42), decoded.get("id").?.values.items[0].int32);
    try std.testing.expectEqual(@as(usize, 1), decoded.unknown_fields.items.len);
}

test "dynamic proto2 round-trips required optional repeated packed message and group fields" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto2";
        \\package demo;
        \\message Child { optional string label = 1; }
        \\message Parent {
        \\  required int32 id = 1;
        \\  optional string name = 2 [default = "anon"];
        \\  optional bytes blob = 3;
        \\  repeated sint32 nums = 4 [packed = true];
        \\  optional Child child = 5;
        \\  optional group Legacy = 6 { optional bool flag = 7; }
        \\}
    ;
    var file = try parser.Parser.parse(allocator, source);
    defer file.deinit();
    const parent_desc = file.findMessage("Parent").?;
    const child_desc = file.findMessage("Child").?;
    const group_desc = parent_desc.findMessageDeep("Legacy").?;

    var message = DynamicMessage.init(allocator, parent_desc);
    defer message.deinit();
    try std.testing.expectError(error.MissingRequiredField, message.validateRequired());

    try message.add(parent_desc.findField("id").?, .{ .int32 = 123 });
    try message.add(parent_desc.findField("name").?, .{ .string = try allocator.dupe(u8, "pb2") });
    try message.add(parent_desc.findField("blob").?, .{ .bytes = try allocator.dupe(u8, "raw") });
    try message.add(parent_desc.findField("nums").?, .{ .sint32 = -1 });
    try message.add(parent_desc.findField("nums").?, .{ .sint32 = 2 });

    const child = try allocator.create(DynamicMessage);
    child.* = DynamicMessage.init(allocator, child_desc);
    try child.add(child_desc.findField("label").?, .{ .string = try allocator.dupe(u8, "kid") });
    try message.add(parent_desc.findField("child").?, .{ .message = child });

    const group = try allocator.create(DynamicMessage);
    group.* = DynamicMessage.init(allocator, group_desc);
    try group.add(group_desc.findField("flag").?, .{ .boolean = true });
    try message.add(parent_desc.findField("legacy").?, .{ .group = group });
    try message.validateRequired();

    const encoded = try message.encoded(&file);
    defer allocator.free(encoded);

    var decoded = DynamicMessage.init(allocator, parent_desc);
    defer decoded.deinit();
    try decoded.decode(&file, encoded);
    try decoded.validateRequired();
    try std.testing.expectEqual(@as(i32, 123), decoded.get("id").?.values.items[0].int32);
    try std.testing.expectEqualSlices(u8, "pb2", decoded.get("name").?.values.items[0].string);
    try std.testing.expectEqualSlices(u8, "raw", decoded.get("blob").?.values.items[0].bytes);
    try std.testing.expectEqual(@as(usize, 2), decoded.get("nums").?.values.items.len);
    try std.testing.expectEqual(@as(i32, -1), decoded.get("nums").?.values.items[0].sint32);
    try std.testing.expectEqual(@as(i32, 2), decoded.get("nums").?.values.items[1].sint32);
    try std.testing.expectEqualSlices(u8, "kid", decoded.get("child").?.values.items[0].message.get("label").?.values.items[0].string);
    try std.testing.expect(decoded.get("legacy").?.values.items[0].group.get("flag").?.values.items[0].boolean);
}

test "dynamic proto3 round-trips map fields and default packed repeated scalars" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\package demo;
        \\message Child { string label = 1; }
        \\message Bag {
        \\  repeated int32 nums = 1;
        \\  map<string, int32> counts = 2;
        \\  map<int32, string> names = 3;
        \\  map<string, Child> children = 4;
        \\}
    ;
    var file = try parser.Parser.parse(allocator, source);
    defer file.deinit();
    const bag_desc = file.findMessage("Bag").?;
    const child_desc = file.findMessage("Child").?;

    var bag = DynamicMessage.init(allocator, bag_desc);
    defer bag.deinit();
    try bag.add(bag_desc.findField("nums").?, .{ .int32 = 1 });
    try bag.add(bag_desc.findField("nums").?, .{ .int32 = 2 });

    const count_entry = try allocator.create(MapEntry);
    count_entry.* = .{
        .key = .{ .string = try allocator.dupe(u8, "red") },
        .value = .{ .int32 = 7 },
    };
    try bag.add(bag_desc.findField("counts").?, .{ .map_entry = count_entry });

    const name_entry = try allocator.create(MapEntry);
    name_entry.* = .{
        .key = .{ .int32 = 42 },
        .value = .{ .string = try allocator.dupe(u8, "forty-two") },
    };
    try bag.add(bag_desc.findField("names").?, .{ .map_entry = name_entry });

    const child = try allocator.create(DynamicMessage);
    child.* = DynamicMessage.init(allocator, child_desc);
    try child.add(child_desc.findField("label").?, .{ .string = try allocator.dupe(u8, "kid") });
    const child_entry = try allocator.create(MapEntry);
    child_entry.* = .{
        .key = .{ .string = try allocator.dupe(u8, "first") },
        .value = .{ .message = child },
    };
    try bag.add(bag_desc.findField("children").?, .{ .map_entry = child_entry });

    const encoded = try bag.encoded(&file);
    defer allocator.free(encoded);

    // Proto3 numeric repeated fields are packed by default: field 1 appears as
    // one length-delimited record containing the two varints.
    try std.testing.expectEqualSlices(u8, &.{ 0x0a, 0x02, 0x01, 0x02 }, encoded[0..4]);

    var decoded = DynamicMessage.init(allocator, bag_desc);
    defer decoded.deinit();
    try decoded.decode(&file, encoded);

    try std.testing.expectEqual(@as(usize, 2), decoded.get("nums").?.values.items.len);
    try std.testing.expectEqual(@as(i32, 1), decoded.get("nums").?.values.items[0].int32);
    try std.testing.expectEqual(@as(i32, 2), decoded.get("nums").?.values.items[1].int32);

    const decoded_count = decoded.get("counts").?.values.items[0].map_entry;
    try std.testing.expectEqualSlices(u8, "red", decoded_count.key.string);
    try std.testing.expectEqual(@as(i32, 7), decoded_count.value.int32);

    const decoded_name = decoded.get("names").?.values.items[0].map_entry;
    try std.testing.expectEqual(@as(i32, 42), decoded_name.key.int32);
    try std.testing.expectEqualSlices(u8, "forty-two", decoded_name.value.string);

    const decoded_child = decoded.get("children").?.values.items[0].map_entry;
    try std.testing.expectEqualSlices(u8, "first", decoded_child.key.string);
    try std.testing.expectEqualSlices(u8, "kid", decoded_child.value.message.get("label").?.values.items[0].string);
}

fn makeNestedNodePayload(allocator: std.mem.Allocator, depth: usize) ![]u8 {
    var current = try allocator.dupe(u8, &.{});
    errdefer allocator.free(current);
    var i: usize = 0;
    while (i < depth) : (i += 1) {
        var writer = wire.Writer.init(allocator);
        defer writer.deinit();
        try writer.writeBytes(1, current);
        const next = try writer.toOwnedSlice();
        allocator.free(current);
        current = next;
    }
    return current;
}

test "dynamic decode enforces nested message recursion limit" {
    const allocator = std.testing.allocator;
    var file = try parser.Parser.parse(allocator,
        \\syntax = "proto3";
        \\message Node { Node child = 1; }
    );
    defer file.deinit();
    const node = file.findMessage("Node").?;

    const shallow = try makeNestedNodePayload(allocator, 4);
    defer allocator.free(shallow);
    var shallow_msg = DynamicMessage.init(allocator, node);
    defer shallow_msg.deinit();
    try shallow_msg.decode(&file, shallow);

    const limit_payload = try makeNestedNodePayload(allocator, 3);
    defer allocator.free(limit_payload);
    var limited_reader = wire.Reader.init(limit_payload);
    limited_reader.recursion_limit = 2;
    var limited_msg = DynamicMessage.init(allocator, node);
    defer limited_msg.deinit();
    try std.testing.expectError(error.RecursionLimitExceeded, test_helpers.decodeStream(&limited_msg, &file, null, &limited_reader, null));
}

test "dynamic decode carries recursion limit through map message entries" {
    const allocator = std.testing.allocator;
    var file = try parser.Parser.parse(allocator,
        \\syntax = "proto3";
        \\message Node { map<string, Node> children = 1; }
    );
    defer file.deinit();
    const node = file.findMessage("Node").?;

    var entry = wire.Writer.init(allocator);
    defer entry.deinit();
    try entry.writeString(1, "child");
    try entry.writeBytes(2, &.{});

    var payload = wire.Writer.init(allocator);
    defer payload.deinit();
    try payload.writeBytes(1, entry.slice());

    var decoded = DynamicMessage.init(allocator, node);
    defer decoded.deinit();
    try decoded.decode(&file, payload.slice());
    try std.testing.expectEqual(@as(usize, 1), decoded.get("children").?.values.items.len);

    var limited_reader = wire.Reader.init(payload.slice());
    limited_reader.recursion_limit = 1;
    var limited = DynamicMessage.init(allocator, node);
    defer limited.deinit();
    try std.testing.expectError(error.RecursionLimitExceeded, test_helpers.decodeStream(&limited, &file, null, &limited_reader, null));
}

test "dynamic proto3 round-trips fixed-width packed repeated scalars" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\package demo;
        \\message PackedFixed {
        \\  repeated fixed32 a = 1;
        \\  repeated fixed64 b = 2;
        \\  repeated sfixed32 c = 3;
        \\  repeated sfixed64 d = 4;
        \\  repeated float e = 5;
        \\  repeated double f = 6;
        \\}
    ;
    var file = try parser.Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("PackedFixed").?;

    var msg = DynamicMessage.init(allocator, desc);
    defer msg.deinit();
    try msg.add(desc.findField("a").?, .{ .fixed32 = 1 });
    try msg.add(desc.findField("a").?, .{ .fixed32 = 0xdead_beef });
    try msg.add(desc.findField("b").?, .{ .fixed64 = 2 });
    try msg.add(desc.findField("b").?, .{ .fixed64 = 0x0102_0304_0506_0708 });
    try msg.add(desc.findField("c").?, .{ .sfixed32 = -3 });
    try msg.add(desc.findField("c").?, .{ .sfixed32 = 4 });
    try msg.add(desc.findField("d").?, .{ .sfixed64 = -5 });
    try msg.add(desc.findField("d").?, .{ .sfixed64 = 6 });
    try msg.add(desc.findField("e").?, .{ .float = 1.25 });
    try msg.add(desc.findField("e").?, .{ .float = -2.5 });
    try msg.add(desc.findField("f").?, .{ .double = 3.5 });
    try msg.add(desc.findField("f").?, .{ .double = -4.75 });

    const encoded = try msg.encoded(&file);
    defer allocator.free(encoded);

    var decoded = DynamicMessage.init(allocator, desc);
    defer decoded.deinit();
    try decoded.decode(&file, encoded);

    try std.testing.expectEqual(@as(u32, 1), decoded.get("a").?.values.items[0].fixed32);
    try std.testing.expectEqual(@as(u32, 0xdead_beef), decoded.get("a").?.values.items[1].fixed32);
    try std.testing.expectEqual(@as(u64, 2), decoded.get("b").?.values.items[0].fixed64);
    try std.testing.expectEqual(@as(u64, 0x0102_0304_0506_0708), decoded.get("b").?.values.items[1].fixed64);
    try std.testing.expectEqual(@as(i32, -3), decoded.get("c").?.values.items[0].sfixed32);
    try std.testing.expectEqual(@as(i32, 4), decoded.get("c").?.values.items[1].sfixed32);
    try std.testing.expectEqual(@as(i64, -5), decoded.get("d").?.values.items[0].sfixed64);
    try std.testing.expectEqual(@as(i64, 6), decoded.get("d").?.values.items[1].sfixed64);
    try std.testing.expectEqual(@as(f32, 1.25), decoded.get("e").?.values.items[0].float);
    try std.testing.expectEqual(@as(f32, -2.5), decoded.get("e").?.values.items[1].float);
    try std.testing.expectEqual(@as(f64, 3.5), decoded.get("f").?.values.items[0].double);
    try std.testing.expectEqual(@as(f64, -4.75), decoded.get("f").?.values.items[1].double);

    var invalid = DynamicMessage.init(allocator, desc);
    defer invalid.deinit();
    try std.testing.expectError(error.InvalidWireType, invalid.decode(&file, &.{ 0x0a, 0x01, 0x00 }));
}

test "dynamic map fields replace duplicate keys with last value" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\message M { map<string, int32> counts = 1; }
    ;
    var file = try parser.Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("M").?;
    const field = desc.findField("counts").?;

    var msg = DynamicMessage.init(allocator, desc);
    defer msg.deinit();
    const first = try allocator.create(MapEntry);
    first.* = .{ .key = .{ .string = try allocator.dupe(u8, "red") }, .value = .{ .int32 = 1 } };
    try msg.add(field, .{ .map_entry = first });
    const second = try allocator.create(MapEntry);
    second.* = .{ .key = .{ .string = try allocator.dupe(u8, "red") }, .value = .{ .int32 = 7 } };
    try msg.add(field, .{ .map_entry = second });
    try std.testing.expectEqual(@as(usize, 1), msg.get("counts").?.values.items.len);
    try std.testing.expectEqual(@as(i32, 7), msg.get("counts").?.values.items[0].map_entry.value.int32);
    const red_key = try allocator.dupe(u8, "red");
    defer allocator.free(red_key);
    try std.testing.expect(msg.clearMapEntry(field, .{ .string = red_key }));
    try std.testing.expect(msg.get("counts") == null);
    try std.testing.expect(!msg.clearMapEntryByName("counts", .{ .string = red_key }));

    var first_entry = wire.Writer.init(allocator);
    defer first_entry.deinit();
    try first_entry.writeString(1, "red");
    try first_entry.writeInt32(2, 3);
    var second_entry = wire.Writer.init(allocator);
    defer second_entry.deinit();
    try second_entry.writeString(1, "red");
    try second_entry.writeInt32(2, 9);
    var encoded = wire.Writer.init(allocator);
    defer encoded.deinit();
    try encoded.writeMessage(1, first_entry.slice());
    try encoded.writeMessage(1, second_entry.slice());

    var decoded = DynamicMessage.init(allocator, desc);
    defer decoded.deinit();
    try decoded.decode(&file, encoded.slice());
    try std.testing.expectEqual(@as(usize, 1), decoded.get("counts").?.values.items.len);
    const entry = decoded.get("counts").?.values.items[0].map_entry;
    try std.testing.expectEqualStrings("red", entry.key.string);
    try std.testing.expectEqual(@as(i32, 9), entry.value.int32);
}

test "dynamic decode batches duplicate map key replacement" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\message M { map<string, int32> counts = 1; }
    ;
    var file = try parser.Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("M").?;

    var encoded = wire.Writer.init(allocator);
    defer encoded.deinit();
    inline for (.{
        .{ "alpha", 1 },
        .{ "beta", 2 },
        .{ "gamma", 3 },
        .{ "alpha", 4 },
        .{ "delta", 5 },
        .{ "beta", 6 },
        .{ "epsilon", 7 },
        .{ "zeta", 8 },
        .{ "eta", 9 },
        .{ "theta", 10 },
        .{ "iota", 11 },
        .{ "kappa", 12 },
        .{ "lambda", 13 },
        .{ "mu", 14 },
        .{ "nu", 15 },
        .{ "xi", 16 },
        .{ "omicron", 17 },
        .{ "alpha", 18 },
    }) |item| {
        var entry = wire.Writer.init(allocator);
        defer entry.deinit();
        try entry.writeString(1, item[0]);
        try entry.writeInt32(2, item[1]);
        try encoded.writeMessage(1, entry.slice());
    }

    var decoded = DynamicMessage.init(allocator, desc);
    defer decoded.deinit();
    try decoded.decode(&file, encoded.slice());

    const counts = decoded.get("counts").?;
    try std.testing.expectEqual(@as(usize, 15), counts.values.items.len);

    // The batched compactor keeps the first key's position stable, mirroring
    // add(), but moves ownership to the last wire value for duplicate keys.
    try std.testing.expectEqualStrings("alpha", counts.values.items[0].map_entry.key.string);
    try std.testing.expectEqual(@as(i32, 18), counts.values.items[0].map_entry.value.int32);
    try std.testing.expectEqualStrings("beta", counts.values.items[1].map_entry.key.string);
    try std.testing.expectEqual(@as(i32, 6), counts.values.items[1].map_entry.value.int32);
    try std.testing.expectEqualStrings("gamma", counts.values.items[2].map_entry.key.string);
    try std.testing.expectEqual(@as(i32, 3), counts.values.items[2].map_entry.value.int32);
}

test "dynamic nested message decode deduplicates map keys" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\message Child { map<string, int32> counts = 1; }
        \\message Parent { Child child = 1; }
    ;
    var file = try parser.Parser.parse(allocator, source);
    defer file.deinit();
    const parent_desc = file.findMessage("Parent").?;

    var first_entry = wire.Writer.init(allocator);
    defer first_entry.deinit();
    try first_entry.writeString(1, "same");
    try first_entry.writeInt32(2, 1);
    var second_entry = wire.Writer.init(allocator);
    defer second_entry.deinit();
    try second_entry.writeString(1, "same");
    try second_entry.writeInt32(2, 2);

    var child_payload = wire.Writer.init(allocator);
    defer child_payload.deinit();
    try child_payload.writeMessage(1, first_entry.slice());
    try child_payload.writeMessage(1, second_entry.slice());

    var parent_payload = wire.Writer.init(allocator);
    defer parent_payload.deinit();
    try parent_payload.writeMessage(1, child_payload.slice());

    var decoded = DynamicMessage.init(allocator, parent_desc);
    defer decoded.deinit();
    try decoded.decode(&file, parent_payload.slice());

    const child = decoded.get("child").?.values.items[0].message;
    const counts = child.get("counts").?;
    try std.testing.expectEqual(@as(usize, 1), counts.values.items.len);
    try std.testing.expectEqualStrings("same", counts.values.items[0].map_entry.key.string);
    try std.testing.expectEqual(@as(i32, 2), counts.values.items[0].map_entry.value.int32);
}

test "dynamic editions honors repeated field encoding features and accepts packed compatibility" {
    const allocator = std.testing.allocator;

    const expanded_source =
        \\edition = "2023";
        \\package demo;
        \\option features.repeated_field_encoding = EXPANDED;
        \\message Metrics { repeated int32 values = 1; }
    ;
    var expanded_file = try parser.Parser.parse(allocator, expanded_source);
    defer expanded_file.deinit();
    const expanded_desc = expanded_file.findMessage("Metrics").?;
    try std.testing.expectEqual(schema.FeatureSet.RepeatedFieldEncoding.expanded, expanded_file.features.repeated_field_encoding);
    try std.testing.expect(!expanded_desc.findField("values").?.resolvedPacked(&expanded_file));

    var expanded = DynamicMessage.init(allocator, expanded_desc);
    defer expanded.deinit();
    try expanded.add(expanded_desc.findField("values").?, .{ .int32 = 1 });
    try expanded.add(expanded_desc.findField("values").?, .{ .int32 = 2 });
    const expanded_bytes = try expanded.encoded(&expanded_file);
    defer allocator.free(expanded_bytes);
    try std.testing.expectEqualSlices(u8, &.{ 0x08, 0x01, 0x08, 0x02 }, expanded_bytes);

    var expanded_decoded_from_packed = DynamicMessage.init(allocator, expanded_desc);
    defer expanded_decoded_from_packed.deinit();
    try expanded_decoded_from_packed.decode(&expanded_file, &.{ 0x0a, 0x02, 0x01, 0x02 });
    try std.testing.expectEqual(@as(usize, 2), expanded_decoded_from_packed.get("values").?.values.items.len);
    try std.testing.expectEqual(@as(i32, 1), expanded_decoded_from_packed.get("values").?.values.items[0].int32);
    try std.testing.expectEqual(@as(i32, 2), expanded_decoded_from_packed.get("values").?.values.items[1].int32);

    const packed_source =
        \\edition = "2023";
        \\package demo;
        \\message Metrics { repeated int32 values = 1; }
    ;
    var packed_file = try parser.Parser.parse(allocator, packed_source);
    defer packed_file.deinit();
    const packed_desc = packed_file.findMessage("Metrics").?;
    try std.testing.expectEqual(schema.FeatureSet.RepeatedFieldEncoding.packed_encoding, packed_file.features.repeated_field_encoding);
    try std.testing.expect(packed_desc.findField("values").?.resolvedPacked(&packed_file));

    var packed_msg = DynamicMessage.init(allocator, packed_desc);
    defer packed_msg.deinit();
    try packed_msg.add(packed_desc.findField("values").?, .{ .int32 = 1 });
    try packed_msg.add(packed_desc.findField("values").?, .{ .int32 = 2 });
    const packed_bytes = try packed_msg.encoded(&packed_file);
    defer allocator.free(packed_bytes);
    try std.testing.expectEqualSlices(u8, &.{ 0x0a, 0x02, 0x01, 0x02 }, packed_bytes);

    var packed_decoded_from_expanded = DynamicMessage.init(allocator, packed_desc);
    defer packed_decoded_from_expanded.deinit();
    try packed_decoded_from_expanded.decode(&packed_file, &.{ 0x08, 0x01, 0x08, 0x02 });
    try std.testing.expectEqual(@as(usize, 2), packed_decoded_from_expanded.get("values").?.values.items.len);
    try std.testing.expectEqual(@as(i32, 1), packed_decoded_from_expanded.get("values").?.values.items[0].int32);
    try std.testing.expectEqual(@as(i32, 2), packed_decoded_from_expanded.get("values").?.values.items[1].int32);
}

test "dynamic decode accepts packed varint scalar families" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\message Metrics {
        \\  repeated uint32 u32s = 1;
        \\  repeated uint64 u64s = 2;
        \\  repeated sint32 s32s = 3;
        \\  repeated sint64 s64s = 4;
        \\  repeated bool flags = 5;
        \\}
    ;
    var file = try parser.Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("Metrics").?;

    var u32_payload = wire.Writer.init(allocator);
    defer u32_payload.deinit();
    try u32_payload.writeVarint(1);
    try u32_payload.writeVarint(300);
    try u32_payload.writeVarint(70_000);

    var u64_payload = wire.Writer.init(allocator);
    defer u64_payload.deinit();
    try u64_payload.writeVarint(1);
    try u64_payload.writeVarint(@as(u64, 1) << 40);

    var s32_payload = wire.Writer.init(allocator);
    defer s32_payload.deinit();
    try s32_payload.writeVarint(wire.zigZagEncode32(-1));
    try s32_payload.writeVarint(wire.zigZagEncode32(2));

    var s64_payload = wire.Writer.init(allocator);
    defer s64_payload.deinit();
    try s64_payload.writeVarint(wire.zigZagEncode64(-9_000_000_000));
    try s64_payload.writeVarint(wire.zigZagEncode64(12));

    var flags_payload = wire.Writer.init(allocator);
    defer flags_payload.deinit();
    try flags_payload.writeVarint(0);
    try flags_payload.writeVarint(1);
    // Protobuf bool values are varints; any non-zero payload decodes as true.
    try flags_payload.writeVarint(300);

    var encoded = wire.Writer.init(allocator);
    defer encoded.deinit();
    try encoded.writeMessage(1, u32_payload.slice());
    try encoded.writeMessage(2, u64_payload.slice());
    try encoded.writeMessage(3, s32_payload.slice());
    try encoded.writeMessage(4, s64_payload.slice());
    try encoded.writeMessage(5, flags_payload.slice());

    var decoded = DynamicMessage.init(allocator, desc);
    defer decoded.deinit();
    try decoded.decode(&file, encoded.slice());

    const u32s = decoded.get("u32s").?.values.items;
    try std.testing.expectEqual(@as(usize, 3), u32s.len);
    try std.testing.expectEqual(@as(u32, 1), u32s[0].uint32);
    try std.testing.expectEqual(@as(u32, 300), u32s[1].uint32);
    try std.testing.expectEqual(@as(u32, 70_000), u32s[2].uint32);

    const u64s = decoded.get("u64s").?.values.items;
    try std.testing.expectEqual(@as(usize, 2), u64s.len);
    try std.testing.expectEqual(@as(u64, 1), u64s[0].uint64);
    try std.testing.expectEqual(@as(u64, 1) << 40, u64s[1].uint64);

    const s32s = decoded.get("s32s").?.values.items;
    try std.testing.expectEqual(@as(usize, 2), s32s.len);
    try std.testing.expectEqual(@as(i32, -1), s32s[0].sint32);
    try std.testing.expectEqual(@as(i32, 2), s32s[1].sint32);

    const s64s = decoded.get("s64s").?.values.items;
    try std.testing.expectEqual(@as(usize, 2), s64s.len);
    try std.testing.expectEqual(@as(i64, -9_000_000_000), s64s[0].sint64);
    try std.testing.expectEqual(@as(i64, 12), s64s[1].sint64);

    const flags = decoded.get("flags").?.values.items;
    try std.testing.expectEqual(@as(usize, 3), flags.len);
    try std.testing.expect(!flags[0].boolean);
    try std.testing.expect(flags[1].boolean);
    try std.testing.expect(flags[2].boolean);
}

test "dynamic implicit presence skips default values while explicit presence keeps them" {
    const allocator = std.testing.allocator;

    {
        var file = try parser.Parser.parse(allocator,
            \\syntax = "proto3";
            \\message M {
            \\  enum Kind { A = 0; B = 1; }
            \\  int32 id = 1;
            \\  string name = 2;
            \\  bool ok = 3;
            \\  Kind kind = 4;
            \\  optional int32 opt = 5;
            \\  oneof pick { int32 code = 6; }
            \\}
        );
        defer file.deinit();
        const desc = file.findMessage("M").?;
        var msg = DynamicMessage.init(allocator, desc);
        defer msg.deinit();
        try msg.add(desc.findField("id").?, .{ .int32 = 0 });
        try msg.add(desc.findField("name").?, .{ .string = try allocator.dupe(u8, "") });
        try msg.add(desc.findField("ok").?, .{ .boolean = false });
        try msg.add(desc.findField("kind").?, .{ .enumeration = 0 });
        try msg.add(desc.findField("opt").?, .{ .int32 = 0 });
        try msg.add(desc.findField("code").?, .{ .int32 = 0 });

        const encoded = try msg.encoded(&file);
        defer allocator.free(encoded);
        try std.testing.expectEqualSlices(u8, &.{ 0x28, 0x00, 0x30, 0x00 }, encoded);
    }

    {
        var file = try parser.Parser.parse(allocator,
            \\edition = "2023";
            \\option features.field_presence = EXPLICIT;
            \\message M {
            \\  int32 explicit_id = 1;
            \\  int32 implicit_id = 2 [features.field_presence = IMPLICIT];
            \\}
        );
        defer file.deinit();
        const desc = file.findMessage("M").?;
        var msg = DynamicMessage.init(allocator, desc);
        defer msg.deinit();
        try msg.add(desc.findField("explicit_id").?, .{ .int32 = 0 });
        try msg.add(desc.findField("implicit_id").?, .{ .int32 = 0 });

        const encoded = try msg.encodedDeterministic(&file);
        defer allocator.free(encoded);
        try std.testing.expectEqualSlices(u8, &.{ 0x08, 0x00 }, encoded);
    }
}

test "dynamic honors message_encoding delimited for message fields" {
    const allocator = std.testing.allocator;

    {
        var file = try parser.Parser.parse(allocator,
            \\edition = "2023";
            \\message Child { int32 id = 1; }
            \\message Parent {
            \\  Child child = 1 [features.message_encoding = DELIMITED];
            \\  Child normal = 2;
            \\}
        );
        defer file.deinit();
        const child_desc = file.findMessage("Child").?;
        const parent_desc = file.findMessage("Parent").?;

        const child = try allocator.create(DynamicMessage);
        child.* = DynamicMessage.init(allocator, child_desc);
        try child.add(child_desc.findField("id").?, .{ .int32 = 7 });
        const normal = try allocator.create(DynamicMessage);
        normal.* = DynamicMessage.init(allocator, child_desc);
        try normal.add(child_desc.findField("id").?, .{ .int32 = 8 });

        var parent = DynamicMessage.init(allocator, parent_desc);
        defer parent.deinit();
        try parent.add(parent_desc.findField("child").?, .{ .message = child });
        try parent.add(parent_desc.findField("normal").?, .{ .message = normal });

        const encoded = try parent.encoded(&file);
        defer allocator.free(encoded);
        try std.testing.expectEqualSlices(u8, &.{ 0x0b, 0x08, 0x07, 0x0c, 0x12, 0x02, 0x08, 0x08 }, encoded);

        var decoded = DynamicMessage.init(allocator, parent_desc);
        defer decoded.deinit();
        try decoded.decode(&file, encoded);
        try std.testing.expectEqual(@as(i32, 7), decoded.get("child").?.values.items[0].message.get("id").?.values.items[0].int32);
        try std.testing.expectEqual(@as(i32, 8), decoded.get("normal").?.values.items[0].message.get("id").?.values.items[0].int32);

        var bad = wire.Writer.init(allocator);
        defer bad.deinit();
        var payload = wire.Writer.init(allocator);
        defer payload.deinit();
        try payload.writeInt32(1, 9);
        try bad.writeMessage(1, payload.slice());
        var bad_msg = DynamicMessage.init(allocator, parent_desc);
        defer bad_msg.deinit();
        try std.testing.expectError(error.InvalidWireType, bad_msg.decode(&file, bad.slice()));
    }

    {
        var file = try parser.Parser.parse(allocator,
            \\edition = "2023";
            \\option features.message_encoding = DELIMITED;
            \\message Child { int32 id = 1; }
            \\message Parent {
            \\  Child delimited = 1;
            \\  Child length_prefixed = 2 [features.message_encoding = LENGTH_PREFIXED];
            \\}
        );
        defer file.deinit();
        const child_desc = file.findMessage("Child").?;
        const parent_desc = file.findMessage("Parent").?;

        const delimited_child = try allocator.create(DynamicMessage);
        delimited_child.* = DynamicMessage.init(allocator, child_desc);
        try delimited_child.add(child_desc.findField("id").?, .{ .int32 = 1 });
        const length_child = try allocator.create(DynamicMessage);
        length_child.* = DynamicMessage.init(allocator, child_desc);
        try length_child.add(child_desc.findField("id").?, .{ .int32 = 2 });

        var parent = DynamicMessage.init(allocator, parent_desc);
        defer parent.deinit();
        try parent.add(parent_desc.findField("delimited").?, .{ .message = delimited_child });
        try parent.add(parent_desc.findField("length_prefixed").?, .{ .message = length_child });

        const encoded = try parent.encoded(&file);
        defer allocator.free(encoded);
        try std.testing.expectEqualSlices(u8, &.{ 0x0b, 0x08, 0x01, 0x0c, 0x12, 0x02, 0x08, 0x02 }, encoded);
    }
}

test "dynamic tracks proto3 optional message presence" {
    const allocator = std.testing.allocator;
    var file = try parser.Parser.parse(allocator,
        \\syntax = "proto3";
        \\message Child { int32 id = 1; }
        \\message Parent { optional Child child = 1; }
    );
    defer file.deinit();
    const parent_desc = file.findMessage("Parent").?;
    const child_desc = file.findMessage("Child").?;
    const child_field = parent_desc.findField("child").?;
    try std.testing.expect(child_field.proto3_optional);

    var parent = DynamicMessage.init(allocator, parent_desc);
    defer parent.deinit();
    try std.testing.expect(!parent.has(child_field));

    const child = try allocator.create(DynamicMessage);
    child.* = DynamicMessage.init(allocator, child_desc);
    try parent.add(child_field, .{ .message = child });
    try std.testing.expect(parent.has(child_field));

    const encoded = try parent.encoded(&file);
    defer allocator.free(encoded);
    var decoded = DynamicMessage.init(allocator, parent_desc);
    defer decoded.deinit();
    try decoded.decode(&file, encoded);
    try std.testing.expect(decoded.has(child_field));
}

test "dynamic validates string utf8 according to syntax and features" {
    const allocator = std.testing.allocator;

    {
        var file = try parser.Parser.parse(allocator,
            \\syntax = "proto3";
            \\message M { string name = 1; }
        );
        defer file.deinit();
        const desc = file.findMessage("M").?;
        var encoded = wire.Writer.init(allocator);
        defer encoded.deinit();
        try encoded.writeBytes(1, &.{0xc0});
        var msg = DynamicMessage.init(allocator, desc);
        defer msg.deinit();
        try std.testing.expectError(error.InvalidUtf8, msg.decode(&file, encoded.slice()));
    }

    {
        var file = try parser.Parser.parse(allocator,
            \\syntax = "proto2";
            \\message M { optional string name = 1; }
        );
        defer file.deinit();
        const desc = file.findMessage("M").?;
        var encoded = wire.Writer.init(allocator);
        defer encoded.deinit();
        try encoded.writeBytes(1, &.{0xc0});
        var msg = DynamicMessage.init(allocator, desc);
        defer msg.deinit();
        try msg.decode(&file, encoded.slice());
        try std.testing.expectEqualSlices(u8, &.{0xc0}, msg.get("name").?.values.items[0].string);
    }

    {
        var file = try parser.Parser.parse(allocator,
            \\edition = "2023";
            \\message M {
            \\  string relaxed = 1 [features.utf8_validation = NONE];
            \\  string strict = 2;
            \\}
        );
        defer file.deinit();
        const desc = file.findMessage("M").?;

        var relaxed = wire.Writer.init(allocator);
        defer relaxed.deinit();
        try relaxed.writeBytes(1, &.{0xc0});
        var relaxed_msg = DynamicMessage.init(allocator, desc);
        defer relaxed_msg.deinit();
        try relaxed_msg.decode(&file, relaxed.slice());
        try std.testing.expectEqualSlices(u8, &.{0xc0}, relaxed_msg.get("relaxed").?.values.items[0].string);

        var strict = wire.Writer.init(allocator);
        defer strict.deinit();
        try strict.writeBytes(2, &.{0xc0});
        var strict_msg = DynamicMessage.init(allocator, desc);
        defer strict_msg.deinit();
        try std.testing.expectError(error.InvalidUtf8, strict_msg.decode(&file, strict.slice()));
    }
}

test "dynamic encode validates string utf8 for fields and map entries" {
    const allocator = std.testing.allocator;
    var file = try parser.Parser.parse(allocator,
        \\syntax = "proto3";
        \\message M {
        \\  string name = 1;
        \\  map<string, string> labels = 2;
        \\}
    );
    defer file.deinit();
    const desc = file.findMessage("M").?;

    var msg = DynamicMessage.init(allocator, desc);
    defer msg.deinit();
    try msg.add(desc.findField("name").?, .{ .string = try allocator.dupe(u8, &.{0xc0}) });
    try std.testing.expectError(error.InvalidUtf8, msg.encoded(&file));

    var map_msg = DynamicMessage.init(allocator, desc);
    defer map_msg.deinit();
    const entry = try allocator.create(MapEntry);
    entry.* = .{
        .key = .{ .string = try allocator.dupe(u8, &.{0xc0}) },
        .value = .{ .string = try allocator.dupe(u8, "ok") },
    };
    try map_msg.add(desc.findField("labels").?, .{ .map_entry = entry });
    try std.testing.expectError(error.InvalidUtf8, map_msg.encoded(&file));
}

test "dynamic oneof keeps only the last selected field" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto2";
        \\package demo;
        \\message Choice {
        \\  oneof pick {
        \\    string name = 1;
        \\    int32 id = 2;
        \\  }
        \\}
    ;
    var file = try parser.Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("Choice").?;

    var message = DynamicMessage.init(allocator, desc);
    defer message.deinit();
    try message.add(desc.findField("name").?, .{ .string = try allocator.dupe(u8, "first") });
    try std.testing.expectEqualStrings("name", message.whichOneof("pick").?.name);
    try message.add(desc.findField("id").?, .{ .int32 = 99 });
    try std.testing.expect(message.get("name") == null);
    try std.testing.expectEqualStrings("id", message.whichOneof("pick").?.name);
    try std.testing.expectEqual(@as(i32, 99), message.get("id").?.values.items[0].int32);

    var writer = wire.Writer.init(allocator);
    defer writer.deinit();
    try writer.writeString(1, "wire-first");
    try writer.writeInt32(2, 7);

    var decoded = DynamicMessage.init(allocator, desc);
    defer decoded.deinit();
    try decoded.decode(&file, writer.slice());
    try std.testing.expect(decoded.get("name") == null);
    try std.testing.expectEqualStrings("id", decoded.whichOneof("pick").?.name);
    try std.testing.expectEqual(@as(i32, 7), decoded.get("id").?.values.items[0].int32);

    try std.testing.expect(decoded.clearOneof("pick"));
    try std.testing.expect(decoded.whichOneof("pick") == null);
    try std.testing.expect(decoded.get("id") == null);
    try std.testing.expect(!decoded.clearOneof("pick"));
    try std.testing.expect(!decoded.clearOneof("missing"));
}

test "dynamic unknown field API preserves queries and clears raw fields" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\message Known { int32 id = 1; }
    ;
    var file = try parser.Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("Known").?;

    var writer = wire.Writer.init(allocator);
    defer writer.deinit();
    try writer.writeInt32(1, 5);
    try writer.writeString(100, "extra");
    try writer.writeUInt32(101, 7);

    var message = DynamicMessage.init(allocator, desc);
    defer message.deinit();
    try message.decode(&file, writer.slice());

    try std.testing.expectEqual(@as(usize, 2), message.unknownCount());
    try std.testing.expectEqual(@as(usize, 2), message.unknownFields().len);
    try std.testing.expect(message.hasUnknownFieldNumber(100));
    try std.testing.expect(message.hasUnknownFieldNumber(101));
    try std.testing.expect(!message.hasUnknownFieldNumber(102));
    try std.testing.expectEqual(@as(usize, 1), message.unknownFieldCountByNumber(100));
    try std.testing.expectEqual(@as(usize, 1), message.unknownFieldCountByNumber(101));
    const unknown_numbers = try message.unknownFieldNumbersAlloc(allocator);
    defer allocator.free(unknown_numbers);
    try std.testing.expectEqualSlices(wire.FieldNumber, &.{ 100, 101 }, unknown_numbers);
    const unknown_runs = try message.unknownFieldNumberRunsAlloc(allocator);
    defer allocator.free(unknown_runs);
    try std.testing.expectEqual(@as(usize, 2), unknown_runs.len);
    try std.testing.expectEqual(wire.RawFieldNumberRun{ .number = 100, .count = 1 }, unknown_runs[0]);
    try std.testing.expectEqual(wire.RawFieldNumberRun{ .number = 101, .count = 1 }, unknown_runs[1]);
    const unknown_100 = message.unknownByNumber(100);
    try std.testing.expectEqual(@as(usize, 1), unknown_100.len);
    try std.testing.expectEqual(wire.WireType.length_delimited, unknown_100[0].wire_type);
    try std.testing.expectEqualSlices(u8, &.{ 0xa2, 0x06, 0x05, 'e', 'x', 't', 'r', 'a' }, unknown_100[0].data);

    var appended_raw = wire.Writer.init(allocator);
    defer appended_raw.deinit();
    try appended_raw.writeUInt32(102, 9);
    try message.appendUnknownRaw(appended_raw.slice());
    try std.testing.expectEqual(@as(usize, 3), message.unknownCount());
    try std.testing.expect(message.hasUnknownFieldNumber(102));
    try std.testing.expectEqual(@as(usize, 1), message.unknownFieldCountByNumber(102));

    const noncanonical_raw = [_]u8{ 0xa0, 0x86, 0x00, 0x01 };
    var exact = DynamicMessage.init(allocator, desc);
    defer exact.deinit();
    try exact.decode(&file, &noncanonical_raw);
    try std.testing.expectEqual(@as(usize, 1), exact.unknownCount());
    try std.testing.expectEqualSlices(u8, &noncanonical_raw, exact.unknownFields()[0].data);

    var invalid_raw = wire.Writer.init(allocator);
    defer invalid_raw.deinit();
    try invalid_raw.writeUInt32(103, 1);
    try invalid_raw.writeUInt32(104, 2);
    try std.testing.expectError(error.InvalidWireType, message.appendUnknownRaw(invalid_raw.slice()));

    message.clearUnknownFieldsByNumber(100);
    try std.testing.expectEqual(@as(usize, 2), message.unknownCount());
    try std.testing.expect(!message.hasUnknownFieldNumber(100));

    const encoded = try message.encoded(&file);
    defer allocator.free(encoded);
    try std.testing.expectEqualSlices(u8, &.{ 0x08, 0x05, 0xa8, 0x06, 0x07, 0xb0, 0x06, 0x09 }, encoded);

    message.clearUnknownFields();
    try std.testing.expectEqual(@as(usize, 0), message.unknownCount());
    const encoded_clean = try message.encoded(&file);
    defer allocator.free(encoded_clean);
    try std.testing.expectEqualSlices(u8, &.{ 0x08, 0x05 }, encoded_clean);
}

test "dynamic decode clears absent fields from reused messages" {
    const allocator = std.testing.allocator;
    var file = try parser.Parser.parse(allocator,
        \\syntax = "proto3";
        \\message M { int32 id = 1; string name = 2; repeated int32 nums = 3; }
    );
    defer file.deinit();
    const desc = file.findMessage("M").?;

    var first = wire.Writer.init(allocator);
    defer first.deinit();
    try first.writeInt32(1, 7);
    try first.writeString(2, "old");
    try first.writeInt32(3, 1);

    var message = DynamicMessage.init(allocator, desc);
    defer message.deinit();
    try message.decode(&file, first.slice());
    try std.testing.expect(message.get("name") != null);
    try std.testing.expect(message.get("nums") != null);

    var second = wire.Writer.init(allocator);
    defer second.deinit();
    try second.writeInt32(1, 8);
    try message.decode(&file, second.slice());

    try std.testing.expectEqual(@as(i32, 8), message.get("id").?.values.items[0].int32);
    try std.testing.expect(message.get("name") == null);
    try std.testing.expect(message.get("nums") == null);
}

test "dynamic clearField removes stored values by descriptor or name" {
    const allocator = std.testing.allocator;
    var file = try parser.Parser.parse(allocator,
        \\syntax = "proto3";
        \\message M { int32 id = 1; repeated string tags = 2; }
    );
    defer file.deinit();
    const desc = file.findMessage("M").?;

    var message = DynamicMessage.init(allocator, desc);
    defer message.deinit();
    try message.add(desc.findField("id").?, .{ .int32 = 1 });
    try message.add(desc.findField("tags").?, .{ .string = try allocator.dupe(u8, "one") });
    try message.add(desc.findField("tags").?, .{ .string = try allocator.dupe(u8, "two") });

    try std.testing.expect(message.clearField(desc.findField("id").?));
    try std.testing.expect(message.get("id") == null);
    try std.testing.expect(message.clearFieldByName("tags"));
    try std.testing.expect(message.get("tags") == null);
    try std.testing.expect(!message.clearFieldByName("missing"));
}

test "dynamic has and getOrDefault expose proto2 defaults and explicit values" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto2";
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\enum Code { OK = 5; FAIL = 6; }
        \\message Defaults {
        \\  optional int32 count = 1 [default = 42];
        \\  optional string name = 2 [default = "anon"];
        \\  optional bool enabled = 3 [default = true];
        \\  optional Kind kind = 4 [default = ADMIN];
        \\  optional bytes blob = 5;
        \\  optional Code code = 6;
        \\  repeated Code codes = 7;
        \\  map<string, Code> code_by_name = 8;
        \\  optional double pos_inf = 9 [default = inf];
        \\  optional double neg_inf = 10 [default = -inf];
        \\  optional float quiet_nan = 11 [default = nan];
        \\  optional float neg_nan = 12 [default = -nan];
        \\  optional double pos_infinity = 13 [default = Infinity];
        \\  optional double neg_infinity = 14 [default = -INFINITY];
        \\  optional uint64 max_u64 = 15 [default = 0xFFFFFFFFFFFFFFFF];
        \\  optional fixed64 max_fixed = 16 [default = 18446744073709551615];
        \\}
    ;
    var file = try parser.Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("Defaults").?;

    var message = DynamicMessage.init(allocator, desc);
    defer message.deinit();
    try std.testing.expect(!message.has(desc.findField("count").?));
    try std.testing.expectEqual(@as(i32, 42), message.getOrDefault(desc.findField("count").?).int32);
    try std.testing.expectEqualStrings("anon", message.getOrDefault(desc.findField("name").?).string);
    try std.testing.expect(message.getOrDefault(desc.findField("enabled").?).boolean);
    // Enum symbolic defaults resolve through the parser into their numeric value.
    try std.testing.expectEqual(@as(i32, 1), message.getOrDefault(desc.findField("kind").?).enumeration);
    try std.testing.expectEqual(@as(i32, 0), message.getOrDefault(desc.findField("code").?).enumeration);
    try std.testing.expectEqual(@as(i32, 5), message.getOrDefaultWithFile(&file, desc.findField("code").?).enumeration);
    try std.testing.expect(std.math.isPositiveInf(message.getOrDefault(desc.findField("pos_inf").?).double));
    try std.testing.expect(std.math.isNegativeInf(message.getOrDefault(desc.findField("neg_inf").?).double));
    try std.testing.expect(std.math.isNan(message.getOrDefault(desc.findField("quiet_nan").?).float));
    try std.testing.expect(std.math.isNan(message.getOrDefault(desc.findField("neg_nan").?).float));
    try std.testing.expect(std.math.isPositiveInf(message.getOrDefault(desc.findField("pos_infinity").?).double));
    try std.testing.expect(std.math.isNegativeInf(message.getOrDefault(desc.findField("neg_infinity").?).double));
    try std.testing.expectEqual(@as(u64, 18446744073709551615), message.getOrDefault(desc.findField("max_u64").?).uint64);
    try std.testing.expectEqual(@as(u64, 18446744073709551615), message.getOrDefault(desc.findField("max_fixed").?).fixed64);
    try std.testing.expectEqualStrings("ADMIN", message.getEnumNameOrDefaultWithFile(&file, desc.findField("kind").?).?);
    try std.testing.expectEqualStrings("OK", message.getEnumNameOrDefaultWithFile(&file, desc.findField("code").?).?);
    try std.testing.expectEqualStrings("", message.getOrDefault(desc.findField("blob").?).bytes);

    try message.add(desc.findField("count").?, .{ .int32 = 7 });
    try std.testing.expect(message.has(desc.findField("count").?));
    try std.testing.expectEqual(@as(i32, 7), message.getOrDefault(desc.findField("count").?).int32);
    try message.add(desc.findField("code").?, .{ .enumeration = 6 });
    try std.testing.expectEqualStrings("FAIL", message.getEnumNameOrDefaultWithFile(&file, desc.findField("code").?).?);
    try message.add(desc.findField("codes").?, .{ .enumeration = 5 });
    try message.add(desc.findField("codes").?, .{ .enumeration = 6 });
    const names = try message.getEnumNamesWithFile(allocator, &file, desc.findField("codes").?);
    defer allocator.free(names);
    try std.testing.expectEqualStrings("OK", names[0]);
    try std.testing.expectEqualStrings("FAIL", names[1]);

    try message.add(desc.findField("codes").?, .{ .enumeration = 123 });
    try std.testing.expectError(error.InvalidEnumValue, message.getEnumNamesWithFile(allocator, &file, desc.findField("codes").?));

    const map_field = desc.findField("code_by_name").?;
    const ok_entry = try allocator.create(MapEntry);
    ok_entry.* = .{ .key = .{ .string = try allocator.dupe(u8, "ok") }, .value = .{ .enumeration = 5 } };
    try message.add(map_field, .{ .map_entry = ok_entry });
    const ok_key = try allocator.dupe(u8, "ok");
    defer allocator.free(ok_key);
    try std.testing.expectEqualStrings("OK", (try message.getEnumMapValueNameWithFile(&file, map_field, .{ .string = ok_key })).?);
    const missing_key = try allocator.dupe(u8, "missing");
    defer allocator.free(missing_key);
    try std.testing.expectEqual(@as(?[]const u8, null), try message.getEnumMapValueNameWithFile(&file, map_field, .{ .string = missing_key }));
    const bad_entry = try allocator.create(MapEntry);
    bad_entry.* = .{ .key = .{ .string = try allocator.dupe(u8, "bad") }, .value = .{ .enumeration = 123 } };
    try message.add(map_field, .{ .map_entry = bad_entry });
    const bad_key = try allocator.dupe(u8, "bad");
    defer allocator.free(bad_key);
    try std.testing.expectError(error.InvalidEnumValue, message.getEnumMapValueNameWithFile(&file, map_field, .{ .string = bad_key }));
}

test "dynamic resolves imported enum defaults with registry" {
    const allocator = std.testing.allocator;
    var common = try parser.Parser.parse(allocator,
        \\syntax = "proto2";
        \\package common;
        \\enum Kind { UNKNOWN = 0; ADMIN = 7; }
    );
    defer common.deinit();
    common.name = "common.proto";
    var app = try parser.Parser.parse(allocator,
        \\syntax = "proto2";
        \\package app;
        \\import "common.proto";
        \\message Event { optional common.Kind kind = 1 [default = ADMIN]; }
    );
    defer app.deinit();
    app.name = "app.proto";
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);
    try registry.validateAllFileReferences();

    const desc = app.findMessage("Event").?;
    const field = desc.findField("kind").?;
    var message = DynamicMessage.init(allocator, desc);
    defer message.deinit();
    try std.testing.expectEqual(DefaultValue.none, message.getOrDefault(field));
    try std.testing.expectEqual(@as(i32, 7), message.getOrDefaultWithRegistry(&app, &registry, field).enumeration);
    try std.testing.expectEqualStrings("ADMIN", message.getEnumNameOrDefaultWithRegistry(&app, &registry, field).?);
}

test "dynamic decodeInitialized enforces proto2 required fields" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto2";
        \\message Required { required int32 id = 1; optional string name = 2; }
    ;
    var file = try parser.Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("Required").?;

    var writer = wire.Writer.init(allocator);
    defer writer.deinit();
    try writer.writeString(2, "missing id");

    var message = DynamicMessage.init(allocator, desc);
    defer message.deinit();
    try std.testing.expectError(error.MissingRequiredField, message.decodeInitialized(&file, writer.slice()));

    writer.clearRetainingCapacity();
    try writer.writeInt32(1, 9);
    try message.decodeInitialized(&file, writer.slice());
    try std.testing.expectEqual(@as(i32, 9), message.get("id").?.values.items[0].int32);
}

test "dynamic encodeInitialized enforces proto2 required fields" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto2";
        \\message Required { required int32 id = 1; optional string name = 2; }
    ;
    var file = try parser.Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("Required").?;

    var message = DynamicMessage.init(allocator, desc);
    defer message.deinit();
    var writer = wire.Writer.init(allocator);
    defer writer.deinit();
    try std.testing.expectError(error.MissingRequiredField, message.encodeInitialized(&file, &writer));
    try std.testing.expectError(error.MissingRequiredField, message.encodedInitialized(&file));
    try std.testing.expectError(error.MissingRequiredField, message.encodeDeterministicInitialized(&file, &writer));
    try std.testing.expectError(error.MissingRequiredField, message.encodedDeterministicInitialized(&file));

    try message.add(desc.findField("id").?, .{ .int32 = 9 });
    try message.encodeInitialized(&file, &writer);
    try std.testing.expect(writer.slice().len != 0);
    const encoded = try message.encodedInitialized(&file);
    defer allocator.free(encoded);
    try std.testing.expect(encoded.len != 0);
    const deterministic = try message.encodedDeterministicInitialized(&file);
    defer allocator.free(deterministic);
    try std.testing.expectEqualSlices(u8, encoded, deterministic);
}

test "dynamic reports missing required field path" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto2";
        \\message Child { required int32 id = 1; }
        \\message Parent { required string name = 1; optional Child child = 2; }
    ;
    var file = try parser.Parser.parse(allocator, source);
    defer file.deinit();
    const parent_desc = file.findMessage("Parent").?;
    const child_desc = file.findMessage("Child").?;

    var parent = DynamicMessage.init(allocator, parent_desc);
    defer parent.deinit();
    const missing_name = (try parent.missingRequiredFieldPath(allocator)).?;
    defer allocator.free(missing_name);
    try std.testing.expectEqualStrings("name", missing_name);

    try parent.add(parent_desc.findField("name").?, .{ .string = try allocator.dupe(u8, "p") });
    const child = try allocator.create(DynamicMessage);
    child.* = DynamicMessage.init(allocator, child_desc);
    try parent.add(parent_desc.findField("child").?, .{ .message = child });
    const missing_child = (try parent.missingRequiredFieldPath(allocator)).?;
    defer allocator.free(missing_child);
    try std.testing.expectEqualStrings("child.id", missing_child);
    try std.testing.expectError(error.MissingRequiredField, parent.validateRequired());

    try child.add(child_desc.findField("id").?, .{ .int32 = 1 });
    try parent.validateRequired();
    try std.testing.expectEqual(@as(?[]u8, null), try parent.missingRequiredFieldPath(allocator));
}

test "dynamic editions legacy_required participates in required validation" {
    const allocator = std.testing.allocator;
    var file = try parser.Parser.parse(allocator,
        \\edition = "2023";
        \\message Child { int32 id = 1 [features.field_presence = LEGACY_REQUIRED]; }
        \\message Parent { Child child = 1; }
    );
    defer file.deinit();
    const parent_desc = file.findMessage("Parent").?;
    const child_desc = file.findMessage("Child").?;

    var child = DynamicMessage.init(allocator, child_desc);
    defer child.deinit();
    try std.testing.expectError(error.MissingRequiredField, child.validateRequired());
    const missing_child_id = (try child.missingRequiredFieldPath(allocator)).?;
    defer allocator.free(missing_child_id);
    try std.testing.expectEqualStrings("id", missing_child_id);

    var parent = DynamicMessage.init(allocator, parent_desc);
    defer parent.deinit();
    const child_ptr = try allocator.create(DynamicMessage);
    child_ptr.* = DynamicMessage.init(allocator, child_desc);
    try parent.add(parent_desc.findField("child").?, .{ .message = child_ptr });
    const missing_nested = (try parent.missingRequiredFieldPath(allocator)).?;
    defer allocator.free(missing_nested);
    try std.testing.expectEqualStrings("child.id", missing_nested);
    var writer = wire.Writer.init(allocator);
    defer writer.deinit();
    try std.testing.expectError(error.MissingRequiredField, parent.encodeInitialized(&file, &writer));

    try child_ptr.add(child_desc.findField("id").?, .{ .int32 = 11 });
    try parent.validateRequired();
    const encoded = try parent.encodedInitialized(&file);
    defer allocator.free(encoded);
    try std.testing.expect(encoded.len != 0);
}

test "dynamic mergeFrom appends repeated fields overrides singular and preserves unknown" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\message Merge { int32 id = 1; repeated string tags = 2; oneof pick { string name = 3; int32 code = 4; } }
    ;
    var file = try parser.Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("Merge").?;

    var left = DynamicMessage.init(allocator, desc);
    defer left.deinit();
    try left.add(desc.findField("id").?, .{ .int32 = 1 });
    try left.add(desc.findField("tags").?, .{ .string = try allocator.dupe(u8, "a") });
    try left.add(desc.findField("name").?, .{ .string = try allocator.dupe(u8, "old") });

    var right = DynamicMessage.init(allocator, desc);
    defer right.deinit();
    try right.add(desc.findField("id").?, .{ .int32 = 2 });
    try right.add(desc.findField("tags").?, .{ .string = try allocator.dupe(u8, "b") });
    try right.add(desc.findField("code").?, .{ .int32 = 9 });
    var unknown_writer = wire.Writer.init(allocator);
    defer unknown_writer.deinit();
    try unknown_writer.writeUInt32(99, 1);
    try right.unknown_fields.append(allocator, .{ .number = 99, .wire_type = .varint, .data = try allocator.dupe(u8, unknown_writer.slice()) });

    try left.mergeFrom(&right);
    try std.testing.expectEqual(@as(i32, 2), left.get("id").?.values.items[0].int32);
    try std.testing.expectEqual(@as(usize, 2), left.get("tags").?.values.items.len);
    try std.testing.expect(left.get("name") == null);
    try std.testing.expectEqual(@as(i32, 9), left.get("code").?.values.items[0].int32);
    try std.testing.expectEqual(@as(usize, 1), left.unknownCount());
}

test "dynamic decode merges duplicate singular message and group fields" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto2";
        \\message Grand { optional int32 a = 1; optional int32 b = 2; }
        \\message Child {
        \\  optional int32 id = 1;
        \\  optional string name = 2;
        \\  repeated int32 nums = 3;
        \\  optional Grand grand = 4;
        \\  optional group Legacy = 5 { optional int32 a = 6; optional int32 b = 7; }
        \\}
        \\message Parent {
        \\  optional Child child = 1;
        \\  optional group Box = 2 { optional int32 a = 3; optional int32 b = 4; }
        \\  repeated Child children = 5;
        \\  oneof pick { Child picked = 6; }
        \\}
    ;
    var file = try parser.Parser.parse(allocator, source);
    defer file.deinit();
    const parent_desc = file.findMessage("Parent").?;

    var first_grand = wire.Writer.init(allocator);
    defer first_grand.deinit();
    try first_grand.writeInt32(1, 100);
    var first_child = wire.Writer.init(allocator);
    defer first_child.deinit();
    try first_child.writeInt32(1, 1);
    try first_child.writeInt32(3, 10);
    try first_child.writeMessage(4, first_grand.slice());
    try first_child.writeTag(5, .start_group);
    try first_child.writeInt32(6, 1000);
    try first_child.writeTag(5, .end_group);

    var second_grand = wire.Writer.init(allocator);
    defer second_grand.deinit();
    try second_grand.writeInt32(2, 200);
    var second_child = wire.Writer.init(allocator);
    defer second_child.deinit();
    try second_child.writeString(2, "two");
    try second_child.writeInt32(3, 20);
    try second_child.writeMessage(4, second_grand.slice());
    try second_child.writeTag(5, .start_group);
    try second_child.writeInt32(7, 2000);
    try second_child.writeTag(5, .end_group);

    var encoded = wire.Writer.init(allocator);
    defer encoded.deinit();
    try encoded.writeMessage(1, first_child.slice());
    try encoded.writeMessage(1, second_child.slice());
    try encoded.writeTag(2, .start_group);
    try encoded.writeInt32(3, 11);
    try encoded.writeTag(2, .end_group);
    try encoded.writeTag(2, .start_group);
    try encoded.writeInt32(4, 22);
    try encoded.writeTag(2, .end_group);
    try encoded.writeMessage(5, first_child.slice());
    try encoded.writeMessage(5, second_child.slice());
    try encoded.writeMessage(6, first_child.slice());
    try encoded.writeMessage(6, second_child.slice());

    var parent = DynamicMessage.init(allocator, parent_desc);
    defer parent.deinit();
    try parent.decode(&file, encoded.slice());

    const merged_child = parent.get("child").?.values.items[0].message;
    try std.testing.expectEqual(@as(i32, 1), merged_child.get("id").?.values.items[0].int32);
    try std.testing.expectEqualSlices(u8, "two", merged_child.get("name").?.values.items[0].string);
    try std.testing.expectEqual(@as(usize, 2), merged_child.get("nums").?.values.items.len);
    try std.testing.expectEqual(@as(i32, 10), merged_child.get("nums").?.values.items[0].int32);
    try std.testing.expectEqual(@as(i32, 20), merged_child.get("nums").?.values.items[1].int32);
    const merged_grand = merged_child.get("grand").?.values.items[0].message;
    try std.testing.expectEqual(@as(i32, 100), merged_grand.get("a").?.values.items[0].int32);
    try std.testing.expectEqual(@as(i32, 200), merged_grand.get("b").?.values.items[0].int32);
    const merged_legacy = merged_child.get("legacy").?.values.items[0].group;
    try std.testing.expectEqual(@as(i32, 1000), merged_legacy.get("a").?.values.items[0].int32);
    try std.testing.expectEqual(@as(i32, 2000), merged_legacy.get("b").?.values.items[0].int32);

    const merged_box = parent.get("box").?.values.items[0].group;
    try std.testing.expectEqual(@as(i32, 11), merged_box.get("a").?.values.items[0].int32);
    try std.testing.expectEqual(@as(i32, 22), merged_box.get("b").?.values.items[0].int32);

    try std.testing.expectEqual(@as(usize, 2), parent.get("children").?.values.items.len);
    try std.testing.expectEqual(@as(i32, 1), parent.get("children").?.values.items[0].message.get("id").?.values.items[0].int32);
    try std.testing.expectEqualSlices(u8, "two", parent.get("children").?.values.items[1].message.get("name").?.values.items[0].string);

    const picked = parent.get("picked").?.values.items[0].message;
    try std.testing.expectEqual(@as(i32, 1), picked.get("id").?.values.items[0].int32);
    try std.testing.expectEqualSlices(u8, "two", picked.get("name").?.values.items[0].string);
    try std.testing.expectEqual(@as(usize, 2), picked.get("nums").?.values.items.len);
    try std.testing.expectEqual(@as(i32, 10), picked.get("nums").?.values.items[0].int32);
    try std.testing.expectEqual(@as(i32, 20), picked.get("nums").?.values.items[1].int32);
}

test "dynamic mergeFrom recursively merges singular messages and groups" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto2";
        \\message Grand { optional int32 a = 1; optional int32 b = 2; }
        \\message Child {
        \\  optional int32 id = 1;
        \\  optional string name = 2;
        \\  repeated int32 nums = 3;
        \\  optional Grand grand = 4;
        \\  optional group Legacy = 5 { optional int32 a = 6; optional int32 b = 7; }
        \\}
        \\message Parent {
        \\  optional Child child = 1;
        \\  optional group Box = 2 { optional int32 a = 3; optional int32 b = 4; }
        \\  repeated Child children = 5;
        \\  oneof pick { Child picked = 6; }
        \\}
    ;
    var file = try parser.Parser.parse(allocator, source);
    defer file.deinit();
    const parent_desc = file.findMessage("Parent").?;
    const child_desc = file.findMessage("Child").?;
    const grand_desc = file.findMessage("Grand").?;
    const legacy_desc = child_desc.findMessageDeep("Legacy").?;
    const box_desc = parent_desc.findMessageDeep("Box").?;

    var left = DynamicMessage.init(allocator, parent_desc);
    defer left.deinit();
    const left_child = try allocator.create(DynamicMessage);
    left_child.* = DynamicMessage.init(allocator, child_desc);
    try left_child.add(child_desc.findField("id").?, .{ .int32 = 1 });
    try left_child.add(child_desc.findField("nums").?, .{ .int32 = 10 });
    const left_grand = try allocator.create(DynamicMessage);
    left_grand.* = DynamicMessage.init(allocator, grand_desc);
    try left_grand.add(grand_desc.findField("a").?, .{ .int32 = 100 });
    try left_child.add(child_desc.findField("grand").?, .{ .message = left_grand });
    const left_legacy = try allocator.create(DynamicMessage);
    left_legacy.* = DynamicMessage.init(allocator, legacy_desc);
    try left_legacy.add(legacy_desc.findField("a").?, .{ .int32 = 1000 });
    try left_child.add(child_desc.findField("legacy").?, .{ .group = left_legacy });
    try left.add(parent_desc.findField("child").?, .{ .message = left_child });
    const left_box = try allocator.create(DynamicMessage);
    left_box.* = DynamicMessage.init(allocator, box_desc);
    try left_box.add(box_desc.findField("a").?, .{ .int32 = 11 });
    try left.add(parent_desc.findField("box").?, .{ .group = left_box });

    var right = DynamicMessage.init(allocator, parent_desc);
    defer right.deinit();
    const right_child = try allocator.create(DynamicMessage);
    right_child.* = DynamicMessage.init(allocator, child_desc);
    try right_child.add(child_desc.findField("name").?, .{ .string = try allocator.dupe(u8, "two") });
    try right_child.add(child_desc.findField("nums").?, .{ .int32 = 20 });
    const right_grand = try allocator.create(DynamicMessage);
    right_grand.* = DynamicMessage.init(allocator, grand_desc);
    try right_grand.add(grand_desc.findField("b").?, .{ .int32 = 200 });
    try right_child.add(child_desc.findField("grand").?, .{ .message = right_grand });
    const right_legacy = try allocator.create(DynamicMessage);
    right_legacy.* = DynamicMessage.init(allocator, legacy_desc);
    try right_legacy.add(legacy_desc.findField("b").?, .{ .int32 = 2000 });
    try right_child.add(child_desc.findField("legacy").?, .{ .group = right_legacy });
    try right.add(parent_desc.findField("child").?, .{ .message = right_child });
    const right_box = try allocator.create(DynamicMessage);
    right_box.* = DynamicMessage.init(allocator, box_desc);
    try right_box.add(box_desc.findField("b").?, .{ .int32 = 22 });
    try right.add(parent_desc.findField("box").?, .{ .group = right_box });

    const repeated_child = try allocator.create(DynamicMessage);
    repeated_child.* = DynamicMessage.init(allocator, child_desc);
    try repeated_child.add(child_desc.findField("name").?, .{ .string = try allocator.dupe(u8, "repeat") });
    try right.add(parent_desc.findField("children").?, .{ .message = repeated_child });
    const picked = try allocator.create(DynamicMessage);
    picked.* = DynamicMessage.init(allocator, child_desc);
    try picked.add(child_desc.findField("name").?, .{ .string = try allocator.dupe(u8, "picked") });
    try right.add(parent_desc.findField("picked").?, .{ .message = picked });

    try left.mergeFrom(&right);

    const merged_child = left.get("child").?.values.items[0].message;
    try std.testing.expectEqual(@as(i32, 1), merged_child.get("id").?.values.items[0].int32);
    try std.testing.expectEqualSlices(u8, "two", merged_child.get("name").?.values.items[0].string);
    try std.testing.expectEqual(@as(usize, 2), merged_child.get("nums").?.values.items.len);
    const merged_grand = merged_child.get("grand").?.values.items[0].message;
    try std.testing.expectEqual(@as(i32, 100), merged_grand.get("a").?.values.items[0].int32);
    try std.testing.expectEqual(@as(i32, 200), merged_grand.get("b").?.values.items[0].int32);
    const merged_legacy = merged_child.get("legacy").?.values.items[0].group;
    try std.testing.expectEqual(@as(i32, 1000), merged_legacy.get("a").?.values.items[0].int32);
    try std.testing.expectEqual(@as(i32, 2000), merged_legacy.get("b").?.values.items[0].int32);
    const merged_box = left.get("box").?.values.items[0].group;
    try std.testing.expectEqual(@as(i32, 11), merged_box.get("a").?.values.items[0].int32);
    try std.testing.expectEqual(@as(i32, 22), merged_box.get("b").?.values.items[0].int32);
    try std.testing.expectEqual(@as(usize, 1), left.get("children").?.values.items.len);
    try std.testing.expectEqualSlices(u8, "repeat", left.get("children").?.values.items[0].message.get("name").?.values.items[0].string);
    try std.testing.expectEqualSlices(u8, "picked", left.get("picked").?.values.items[0].message.get("name").?.values.items[0].string);
}

test "dynamic decodeWithRegistry decodes proto2 extensions" {
    const allocator = std.testing.allocator;
    var file = try parser.Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host { optional int32 id = 1; extensions 100 to max; }
        \\extend Host { optional string note = 100; }
    );
    defer file.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);
    const host = file.findMessage("Host").?;

    var writer = wire.Writer.init(allocator);
    defer writer.deinit();
    try writer.writeInt32(1, 7);
    try writer.writeString(100, "hello");

    var msg = DynamicMessage.init(allocator, host);
    defer msg.deinit();
    try msg.decodeWithRegistry(&file, &registry, writer.slice());
    try std.testing.expectEqual(@as(usize, 0), msg.unknownCount());
    try std.testing.expectEqualSlices(u8, "hello", msg.get("note").?.values.items[0].string);
}

test "dynamic decodes and encodes proto2 group extensions" {
    const allocator = std.testing.allocator;
    var file = try parser.Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host { extensions 100 to max; }
        \\extend Host { optional group Legacy = 100 { optional int32 id = 1; } }
    );
    defer file.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);
    const host = file.findMessage("Host").?;
    const legacy = registry.findExtension("demo.Host", 100).?;

    var encoded = wire.Writer.init(allocator);
    defer encoded.deinit();
    try encoded.writeTag(100, .start_group);
    try encoded.writeInt32(1, 7);
    try encoded.writeTag(100, .end_group);

    var msg = DynamicMessage.init(allocator, host);
    defer msg.deinit();
    try msg.decodeWithRegistry(&file, &registry, encoded.slice());
    const decoded_legacy = msg.get("legacy").?.values.items[0].group;
    try std.testing.expectEqual(@as(i32, 7), decoded_legacy.get("id").?.values.items[0].int32);

    const roundtrip = try msg.encodedWithRegistry(&file, &registry);
    defer allocator.free(roundtrip);
    try std.testing.expectEqualSlices(u8, encoded.slice(), roundtrip);

    const group = try allocator.create(DynamicMessage);
    group.* = DynamicMessage.init(allocator, file.findMessage("Legacy").?);
    try group.add(group.descriptor.findField("id").?, .{ .int32 = 9 });
    var built = DynamicMessage.init(allocator, host);
    defer built.deinit();
    try built.add(legacy, .{ .group = group });
    const built_bytes = try built.encodedWithRegistry(&file, &registry);
    defer allocator.free(built_bytes);
    try std.testing.expectEqualSlices(u8, &.{ 0xa3, 0x06, 0x08, 0x09, 0xa4, 0x06 }, built_bytes);
}

test "dynamic registry extension lookup distinguishes same leaf message names" {
    const allocator = std.testing.allocator;
    var a_file = try parser.Parser.parse(allocator,
        \\syntax = "proto2";
        \\package a;
        \\message Host { extensions 100 to max; }
        \\extend Host { optional string note = 100; }
    );
    defer a_file.deinit();
    a_file.name = "a.proto";
    var b_file = try parser.Parser.parse(allocator,
        \\syntax = "proto2";
        \\package b;
        \\message Host { optional int32 id = 1; }
    );
    defer b_file.deinit();
    b_file.name = "b.proto";
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&a_file);
    try registry.addFile(&b_file);

    var writer = wire.Writer.init(allocator);
    defer writer.deinit();
    try writer.writeString(100, "wrong-host");

    var b_msg = DynamicMessage.init(allocator, b_file.findMessage("Host").?);
    defer b_msg.deinit();
    try b_msg.decodeWithRegistry(&b_file, &registry, writer.slice());
    try std.testing.expect(b_msg.get("note") == null);
    try std.testing.expectEqual(@as(usize, 1), b_msg.unknownCount());

    var a_msg = DynamicMessage.init(allocator, a_file.findMessage("Host").?);
    defer a_msg.deinit();
    try a_msg.decodeWithRegistry(&a_file, &registry, writer.slice());
    try std.testing.expectEqualStrings("wrong-host", a_msg.get("note").?.values.items[0].string);
    try std.testing.expectEqual(@as(usize, 0), a_msg.unknownCount());
}

test "dynamic decodeWithRegistry resolves imported message fields" {
    const allocator = std.testing.allocator;
    var common = try parser.Parser.parse(allocator,
        \\syntax = "proto2";
        \\package common;
        \\message User { optional string name = 1; }
    );
    defer common.deinit();
    var app = try parser.Parser.parse(allocator,
        \\syntax = "proto2";
        \\package app;
        \\message Request { optional common.User user = 1; }
    );
    defer app.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);

    const user_desc = common.findMessage("User").?;
    var user_msg = DynamicMessage.init(allocator, user_desc);
    defer user_msg.deinit();
    try user_msg.add(user_desc.findField("name").?, .{ .string = try allocator.dupe(u8, "Ada") });
    const user_bytes = try user_msg.encoded(&common);
    defer allocator.free(user_bytes);

    var writer = wire.Writer.init(allocator);
    defer writer.deinit();
    try writer.writeMessage(1, user_bytes);

    const request_desc = app.findMessage("Request").?;
    var request = DynamicMessage.init(allocator, request_desc);
    defer request.deinit();
    try request.decodeWithRegistry(&app, &registry, writer.slice());
    const decoded_user = request.get("user").?.values.items[0].message;
    try std.testing.expectEqualStrings("User", decoded_user.descriptor.name);
    try std.testing.expectEqualSlices(u8, "Ada", decoded_user.get("name").?.values.items[0].string);
}

test "dynamic registry resolves same-package imported unqualified fields" {
    const allocator = std.testing.allocator;
    var common = try parser.Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message User { optional string name = 1; }
        \\enum Kind { UNKNOWN = 0; ADMIN = 7; }
    );
    defer common.deinit();
    common.name = "common.proto";
    var app = try parser.Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\import "common.proto";
        \\message Event {
        \\  optional User user = 1;
        \\  optional Kind kind = 2 [default = ADMIN];
        \\}
    );
    defer app.deinit();
    app.name = "app.proto";
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);
    try registry.validateFileReferences(&app);

    const user_desc = common.findMessage("User").?;
    const event_desc = app.findMessage("Event").?;
    const user_field = event_desc.findField("user").?;
    const kind_field = event_desc.findField("kind").?;

    const user = try allocator.create(DynamicMessage);
    user.* = DynamicMessage.init(allocator, user_desc);
    try user.add(user_desc.findField("name").?, .{ .string = try allocator.dupe(u8, "Ada") });

    var event = DynamicMessage.init(allocator, event_desc);
    defer event.deinit();
    try event.add(user_field, .{ .message = user });
    try event.add(kind_field, .{ .enumeration = 7 });

    const encoded = try event.encodedWithRegistry(&app, &registry);
    defer allocator.free(encoded);
    try std.testing.expectEqualSlices(u8, &.{ 0x0a, 0x05, 0x0a, 0x03, 'A', 'd', 'a', 0x10, 0x07 }, encoded);

    var decoded = DynamicMessage.init(allocator, event_desc);
    defer decoded.deinit();
    try decoded.decodeWithRegistry(&app, &registry, encoded);
    try std.testing.expectEqualStrings("Ada", decoded.get("user").?.values.items[0].message.get("name").?.values.items[0].string);
    try std.testing.expectEqual(@as(i32, 7), decoded.get("kind").?.values.items[0].enumeration);
    try std.testing.expectEqualStrings("ADMIN", decoded.getEnumNameOrDefaultWithRegistry(&app, &registry, kind_field).?);
}

test "dynamic registry nested messages use owning file features" {
    const allocator = std.testing.allocator;
    var proto2_common = try parser.Parser.parse(allocator,
        \\syntax = "proto2";
        \\package common.pb2;
        \\message Payload {
        \\  optional string raw = 1;
        \\  repeated int32 nums = 2;
        \\}
    );
    defer proto2_common.deinit();
    proto2_common.name = "pb2.proto";
    var proto3_common = try parser.Parser.parse(allocator,
        \\syntax = "proto3";
        \\package common.pb3;
        \\message Payload {
        \\  repeated int32 nums = 1;
        \\}
    );
    defer proto3_common.deinit();
    proto3_common.name = "pb3.proto";
    var proto3_app = try parser.Parser.parse(allocator,
        \\syntax = "proto3";
        \\package app3;
        \\import "pb2.proto";
        \\message Envelope { common.pb2.Payload payload = 1; }
    );
    defer proto3_app.deinit();
    proto3_app.name = "app3.proto";
    var proto2_app = try parser.Parser.parse(allocator,
        \\syntax = "proto2";
        \\package app2;
        \\import "pb3.proto";
        \\message Envelope { optional common.pb3.Payload payload = 1; }
    );
    defer proto2_app.deinit();
    proto2_app.name = "app2.proto";

    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&proto2_common);
    try registry.addFile(&proto3_common);
    try registry.addFile(&proto3_app);
    try registry.addFile(&proto2_app);

    const pb2_payload_desc = proto2_common.findMessage("Payload").?;
    const app3_envelope_desc = proto3_app.findMessage("Envelope").?;
    var pb2_payload = try allocator.create(DynamicMessage);
    var pb2_payload_transferred = false;
    errdefer if (!pb2_payload_transferred) allocator.destroy(pb2_payload);
    pb2_payload.* = DynamicMessage.init(allocator, pb2_payload_desc);
    errdefer if (!pb2_payload_transferred) pb2_payload.deinit();
    try pb2_payload.add(pb2_payload_desc.findField("raw").?, .{ .string = try allocator.dupe(u8, &.{0xc0}) });
    try pb2_payload.add(pb2_payload_desc.findField("nums").?, .{ .int32 = 1 });
    try pb2_payload.add(pb2_payload_desc.findField("nums").?, .{ .int32 = 2 });
    var app3_envelope = DynamicMessage.init(allocator, app3_envelope_desc);
    defer app3_envelope.deinit();
    try app3_envelope.add(app3_envelope_desc.findField("payload").?, .{ .message = pb2_payload });
    pb2_payload_transferred = true;
    const app3_encoded = try app3_envelope.encodedWithRegistry(&proto3_app, &registry);
    defer allocator.free(app3_encoded);
    try std.testing.expectEqualSlices(u8, &.{ 0x0a, 0x07, 0x0a, 0x01, 0xc0, 0x10, 0x01, 0x10, 0x02 }, app3_encoded);

    var app3_decoded = DynamicMessage.init(allocator, app3_envelope_desc);
    defer app3_decoded.deinit();
    try app3_decoded.decodeWithRegistry(&proto3_app, &registry, app3_encoded);
    const decoded_pb2_payload = app3_decoded.get("payload").?.values.items[0].message;
    try std.testing.expectEqualSlices(u8, &.{0xc0}, decoded_pb2_payload.get("raw").?.values.items[0].string);
    try std.testing.expectEqual(@as(i32, 1), decoded_pb2_payload.get("nums").?.values.items[0].int32);
    try std.testing.expectEqual(@as(i32, 2), decoded_pb2_payload.get("nums").?.values.items[1].int32);

    const pb3_payload_desc = proto3_common.findMessage("Payload").?;
    const app2_envelope_desc = proto2_app.findMessage("Envelope").?;
    var pb3_payload = try allocator.create(DynamicMessage);
    var pb3_payload_transferred = false;
    errdefer if (!pb3_payload_transferred) allocator.destroy(pb3_payload);
    pb3_payload.* = DynamicMessage.init(allocator, pb3_payload_desc);
    errdefer if (!pb3_payload_transferred) pb3_payload.deinit();
    try pb3_payload.add(pb3_payload_desc.findField("nums").?, .{ .int32 = 1 });
    try pb3_payload.add(pb3_payload_desc.findField("nums").?, .{ .int32 = 2 });
    var app2_envelope = DynamicMessage.init(allocator, app2_envelope_desc);
    defer app2_envelope.deinit();
    try app2_envelope.add(app2_envelope_desc.findField("payload").?, .{ .message = pb3_payload });
    pb3_payload_transferred = true;
    const app2_encoded = try app2_envelope.encodedWithRegistry(&proto2_app, &registry);
    defer allocator.free(app2_encoded);
    try std.testing.expectEqualSlices(u8, &.{ 0x0a, 0x04, 0x0a, 0x02, 0x01, 0x02 }, app2_encoded);
}

test "dynamic decodeWithRegistry resolves imported enum fields" {
    const allocator = std.testing.allocator;
    var common = try parser.Parser.parse(allocator,
        \\syntax = "proto2";
        \\package common;
        \\enum Kind { A = 1; B = 2; }
    );
    defer common.deinit();
    var app = try parser.Parser.parse(allocator,
        \\syntax = "proto2";
        \\package app;
        \\message Event { optional common.Kind kind = 1; repeated common.Kind many = 2; }
    );
    defer app.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);

    var writer = wire.Writer.init(allocator);
    defer writer.deinit();
    try writer.writeInt32(1, 2);
    try writer.writeInt32(2, 1);
    try writer.writeInt32(2, 123);

    const event_desc = app.findMessage("Event").?;
    var event = DynamicMessage.init(allocator, event_desc);
    defer event.deinit();
    try event.decodeWithRegistry(&app, &registry, writer.slice());
    try std.testing.expectEqual(@as(i32, 2), event.get("kind").?.values.items[0].enumeration);
    try std.testing.expectEqual(@as(i32, 1), event.get("many").?.values.items[0].enumeration);
    try std.testing.expectEqual(@as(usize, 1), event.get("many").?.values.items.len);
    try std.testing.expectEqualStrings("B", event.getEnumNameOrDefaultWithRegistry(&app, &registry, event_desc.findField("kind").?).?);
    const names = try event.getEnumNamesWithRegistry(allocator, &app, &registry, event_desc.findField("many").?);
    defer allocator.free(names);
    try std.testing.expectEqual(@as(usize, 1), names.len);
    try std.testing.expectEqualStrings("A", names[0]);
    try std.testing.expectEqual(@as(usize, 1), event.unknownCount());
}

test "dynamic imported enums use owning file features" {
    const allocator = std.testing.allocator;
    var open_file = try parser.Parser.parse(allocator,
        \\syntax = "proto3";
        \\package openpkg;
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
    );
    defer open_file.deinit();
    open_file.name = "open.proto";
    var closed_file = try parser.Parser.parse(allocator,
        \\syntax = "proto2";
        \\package closedpkg;
        \\enum Kind { ADMIN = 1; }
    );
    defer closed_file.deinit();
    closed_file.name = "closed.proto";
    var proto2_app = try parser.Parser.parse(allocator,
        \\syntax = "proto2";
        \\package app2;
        \\import "open.proto";
        \\message Event { optional openpkg.Kind kind = 1; }
    );
    defer proto2_app.deinit();
    proto2_app.name = "app2.proto";
    var proto3_app = try parser.Parser.parse(allocator,
        \\syntax = "proto3";
        \\package app3;
        \\import "closed.proto";
        \\message Event { closedpkg.Kind kind = 1; }
    );
    defer proto3_app.deinit();
    proto3_app.name = "app3.proto";

    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&open_file);
    try registry.addFile(&closed_file);
    try registry.addFile(&proto2_app);
    try registry.addFile(&proto3_app);

    var encoded = wire.Writer.init(allocator);
    defer encoded.deinit();
    try encoded.writeInt32(1, 123);

    var open_in_proto2 = DynamicMessage.init(allocator, proto2_app.findMessage("Event").?);
    defer open_in_proto2.deinit();
    try open_in_proto2.decodeWithRegistry(&proto2_app, &registry, encoded.slice());
    try std.testing.expectEqual(@as(i32, 123), open_in_proto2.get("kind").?.values.items[0].enumeration);
    try std.testing.expectEqual(@as(usize, 0), open_in_proto2.unknownCount());

    var closed_in_proto3 = DynamicMessage.init(allocator, proto3_app.findMessage("Event").?);
    defer closed_in_proto3.deinit();
    try closed_in_proto3.decodeWithRegistry(&proto3_app, &registry, encoded.slice());
    try std.testing.expect(closed_in_proto3.get("kind") == null);
    try std.testing.expectEqual(@as(usize, 1), closed_in_proto3.unknownCount());
}

test "dynamic decodeWithRegistry resolves imported enum map entries" {
    const allocator = std.testing.allocator;
    var common = try parser.Parser.parse(allocator,
        \\syntax = "proto2";
        \\package common;
        \\enum Kind { A = 1; B = 2; }
    );
    defer common.deinit();
    var app = try parser.Parser.parse(allocator,
        \\syntax = "proto2";
        \\package app;
        \\message Event { map<string, common.Kind> kinds = 1; }
    );
    defer app.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);

    var bad_entry = wire.Writer.init(allocator);
    defer bad_entry.deinit();
    try bad_entry.writeString(1, "bad");
    try bad_entry.writeInt32(2, 123);

    var good_entry = wire.Writer.init(allocator);
    defer good_entry.deinit();
    try good_entry.writeString(1, "ok");
    try good_entry.writeInt32(2, 2);

    var encoded = wire.Writer.init(allocator);
    defer encoded.deinit();
    try encoded.writeMessage(1, bad_entry.slice());
    const bad_raw = try allocator.dupe(u8, encoded.slice());
    defer allocator.free(bad_raw);
    try encoded.writeMessage(1, good_entry.slice());

    const event_desc = app.findMessage("Event").?;
    var event = DynamicMessage.init(allocator, event_desc);
    defer event.deinit();
    try event.decodeWithRegistry(&app, &registry, encoded.slice());
    try std.testing.expectEqual(@as(usize, 1), event.get("kinds").?.values.items.len);
    const entry = event.get("kinds").?.values.items[0].map_entry;
    try std.testing.expectEqualStrings("ok", entry.key.string);
    try std.testing.expectEqual(@as(i32, 2), entry.value.enumeration);
    const ok_key = try allocator.dupe(u8, "ok");
    defer allocator.free(ok_key);
    try std.testing.expectEqualStrings("B", (try event.getEnumMapValueNameWithRegistry(&app, &registry, event_desc.findField("kinds").?, .{ .string = ok_key })).?);
    try std.testing.expectEqual(@as(usize, 1), event.unknownCount());
    try std.testing.expectEqualSlices(u8, bad_raw, event.unknown_fields.items[0].data);
}

test "dynamic encodeWithRegistry resolves imported enum fields" {
    const allocator = std.testing.allocator;
    var common = try parser.Parser.parse(allocator,
        \\syntax = "proto2";
        \\package common;
        \\enum Kind { A = 1; B = 2; }
    );
    defer common.deinit();
    var app = try parser.Parser.parse(allocator,
        \\syntax = "proto2";
        \\package app;
        \\message Event { optional common.Kind kind = 1; repeated common.Kind many = 2; }
    );
    defer app.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);

    const event_desc = app.findMessage("Event").?;
    var event = DynamicMessage.init(allocator, event_desc);
    defer event.deinit();
    try event.add(event_desc.findField("kind").?, .{ .enumeration = 2 });
    try event.add(event_desc.findField("many").?, .{ .enumeration = 1 });
    try event.add(event_desc.findField("many").?, .{ .enumeration = 2 });

    try std.testing.expectError(error.TypeMismatch, event.encoded(&app));

    const encoded = try event.encodedWithRegistry(&app, &registry);
    defer allocator.free(encoded);
    try std.testing.expectEqualSlices(u8, &.{ 0x08, 0x02, 0x10, 0x01, 0x10, 0x02 }, encoded);

    const deterministic = try event.encodedDeterministicWithRegistry(&app, &registry);
    defer allocator.free(deterministic);
    try std.testing.expectEqualSlices(u8, encoded, deterministic);

    var decoded = DynamicMessage.init(allocator, event_desc);
    defer decoded.deinit();
    try decoded.decodeWithRegistry(&app, &registry, encoded);
    try std.testing.expectEqual(@as(i32, 2), decoded.get("kind").?.values.items[0].enumeration);
    try std.testing.expectEqual(@as(i32, 1), decoded.get("many").?.values.items[0].enumeration);
    try std.testing.expectEqual(@as(i32, 2), decoded.get("many").?.values.items[1].enumeration);
}

test "dynamic encodeWithRegistry rejects message values for imported enum fields" {
    const allocator = std.testing.allocator;
    var common = try parser.Parser.parse(allocator,
        \\syntax = "proto2";
        \\package common;
        \\enum Kind { A = 1; B = 2; }
    );
    defer common.deinit();
    var app = try parser.Parser.parse(allocator,
        \\syntax = "proto2";
        \\package app;
        \\message Event { optional common.Kind kind = 1; }
    );
    defer app.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);

    const event_desc = app.findMessage("Event").?;
    const bogus = try allocator.create(DynamicMessage);
    bogus.* = DynamicMessage.init(allocator, event_desc);
    var event = DynamicMessage.init(allocator, event_desc);
    defer event.deinit();
    try event.add(event_desc.findField("kind").?, .{ .message = bogus });

    try std.testing.expectError(error.TypeMismatch, event.encodedWithRegistry(&app, &registry));
}

test "dynamic encodeWithRegistry packs imported proto3 enum fields" {
    const allocator = std.testing.allocator;
    var common = try parser.Parser.parse(allocator,
        \\syntax = "proto3";
        \\package common;
        \\enum Kind { A = 0; B = 1; C = 2; }
    );
    defer common.deinit();
    var app = try parser.Parser.parse(allocator,
        \\syntax = "proto3";
        \\package app;
        \\message Event { common.Kind kind = 1; repeated common.Kind many = 2; }
    );
    defer app.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);

    const event_desc = app.findMessage("Event").?;
    var event = DynamicMessage.init(allocator, event_desc);
    defer event.deinit();
    try event.add(event_desc.findField("kind").?, .{ .enumeration = 0 });
    try event.add(event_desc.findField("many").?, .{ .enumeration = 1 });
    try event.add(event_desc.findField("many").?, .{ .enumeration = 2 });

    try std.testing.expectError(error.TypeMismatch, event.encoded(&app));

    const encoded = try event.encodedWithRegistry(&app, &registry);
    defer allocator.free(encoded);
    try std.testing.expectEqualSlices(u8, &.{ 0x12, 0x02, 0x01, 0x02 }, encoded);

    const deterministic = try event.encodedDeterministicWithRegistry(&app, &registry);
    defer allocator.free(deterministic);
    try std.testing.expectEqualSlices(u8, encoded, deterministic);

    var decoded = DynamicMessage.init(allocator, event_desc);
    defer decoded.deinit();
    try decoded.decodeWithRegistry(&app, &registry, encoded);
    try std.testing.expect(decoded.get("kind") == null);
    try std.testing.expectEqual(@as(i32, 1), decoded.get("many").?.values.items[0].enumeration);
    try std.testing.expectEqual(@as(i32, 2), decoded.get("many").?.values.items[1].enumeration);
}

test "dynamic encodeWithRegistry resolves imported enum map entries" {
    const allocator = std.testing.allocator;
    var common = try parser.Parser.parse(allocator,
        \\syntax = "proto3";
        \\package common;
        \\enum Kind { A = 0; B = 1; C = 2; }
    );
    defer common.deinit();
    var app = try parser.Parser.parse(allocator,
        \\syntax = "proto3";
        \\package app;
        \\message Event { map<string, common.Kind> kinds = 1; }
    );
    defer app.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);

    const event_desc = app.findMessage("Event").?;
    const field = event_desc.findField("kinds").?;
    var event = DynamicMessage.init(allocator, event_desc);
    defer event.deinit();
    const b = try allocator.create(MapEntry);
    b.* = .{ .key = .{ .string = try allocator.dupe(u8, "b") }, .value = .{ .enumeration = 2 } };
    try event.add(field, .{ .map_entry = b });
    const a = try allocator.create(MapEntry);
    a.* = .{ .key = .{ .string = try allocator.dupe(u8, "a") }, .value = .{ .enumeration = 1 } };
    try event.add(field, .{ .map_entry = a });

    try std.testing.expectError(error.TypeMismatch, event.encodedDeterministic(&app));

    const encoded = try event.encodedWithRegistry(&app, &registry);
    defer allocator.free(encoded);
    var normal_decoded = DynamicMessage.init(allocator, event_desc);
    defer normal_decoded.deinit();
    try normal_decoded.decodeWithRegistry(&app, &registry, encoded);
    try std.testing.expectEqual(@as(usize, 2), normal_decoded.get("kinds").?.values.items.len);

    const deterministic = try event.encodedDeterministicWithRegistry(&app, &registry);
    defer allocator.free(deterministic);
    try std.testing.expectEqualSlices(u8, &.{ 0x0a, 0x05, 0x0a, 0x01, 'a', 0x10, 0x01, 0x0a, 0x05, 0x0a, 0x01, 'b', 0x10, 0x02 }, deterministic);

    var decoded = DynamicMessage.init(allocator, event_desc);
    defer decoded.deinit();
    try decoded.decodeWithRegistry(&app, &registry, deterministic);
    const entries = decoded.get("kinds").?.values.items;
    try std.testing.expectEqual(@as(usize, 2), entries.len);
    try std.testing.expectEqualStrings("a", entries[0].map_entry.key.string);
    try std.testing.expectEqual(@as(i32, 1), entries[0].map_entry.value.enumeration);
    try std.testing.expectEqualStrings("b", entries[1].map_entry.key.string);
    try std.testing.expectEqual(@as(i32, 2), entries[1].map_entry.value.enumeration);
}

test "dynamic initialized registry helpers resolve imported message fields" {
    const allocator = std.testing.allocator;
    var common = try parser.Parser.parse(allocator,
        \\syntax = "proto2";
        \\package common;
        \\message Child { required int32 id = 1; }
    );
    defer common.deinit();
    var app = try parser.Parser.parse(allocator,
        \\syntax = "proto2";
        \\package app;
        \\message Parent { required common.Child child = 1; }
    );
    defer app.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);

    const child_desc = common.findMessage("Child").?;
    const parent_desc = app.findMessage("Parent").?;
    const child_field = parent_desc.findField("child").?;

    const child = try allocator.create(DynamicMessage);
    child.* = DynamicMessage.init(allocator, child_desc);

    var parent = DynamicMessage.init(allocator, parent_desc);
    defer parent.deinit();
    try parent.add(child_field, .{ .message = child });

    try std.testing.expectError(error.MissingRequiredField, parent.encodedInitializedWithRegistry(&app, &registry));

    try child.add(child_desc.findField("id").?, .{ .int32 = 7 });
    const encoded = try parent.encodedInitializedWithRegistry(&app, &registry);
    defer allocator.free(encoded);
    try std.testing.expectEqualSlices(u8, &.{ 0x0a, 0x02, 0x08, 0x07 }, encoded);

    var decoded = DynamicMessage.init(allocator, parent_desc);
    defer decoded.deinit();
    try decoded.decodeInitializedWithRegistry(&app, &registry, encoded);
    const decoded_child = decoded.get("child").?.values.items[0].message;
    try std.testing.expectEqual(@as(i32, 7), decoded_child.get("id").?.values.items[0].int32);

    var missing_payload = wire.Writer.init(allocator);
    defer missing_payload.deinit();
    try missing_payload.writeMessage(1, &.{});
    var invalid = DynamicMessage.init(allocator, parent_desc);
    defer invalid.deinit();
    try std.testing.expectError(error.MissingRequiredField, invalid.decodeInitializedWithRegistry(&app, &registry, missing_payload.slice()));
}

test "dynamic encodes extension fields using extension descriptors" {
    const allocator = std.testing.allocator;
    var file = try parser.Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host { extensions 100 to max; }
        \\extend Host { optional int32 score = 100; }
    );
    defer file.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);
    const host = file.findMessage("Host").?;
    const score = registry.findExtension("demo.Host", 100).?;

    var msg = DynamicMessage.init(allocator, host);
    defer msg.deinit();
    try msg.add(score, .{ .int32 = 123 });
    const encoded = try msg.encoded(&file);
    defer allocator.free(encoded);
    try std.testing.expectEqualSlices(u8, &.{ 0xa0, 0x06, 0x7b }, encoded);

    var decoded = DynamicMessage.init(allocator, host);
    defer decoded.deinit();
    try decoded.decodeWithRegistry(&file, &registry, encoded);
    try std.testing.expectEqual(@as(i32, 123), decoded.get("score").?.values.items[0].int32);
}

test "dynamic encodes scoped extension extendees with registry" {
    const allocator = std.testing.allocator;
    var file = try parser.Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Scope {
        \\  message Nested { extensions 100 to max; }
        \\  extend Nested { optional int32 nested_note = 100; }
        \\}
    );
    defer file.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);

    const nested = file.findMessage("Scope").?.findMessage("Nested").?;
    const field = registry.findExtension(".demo.Scope.Nested", 100).?;

    var msg = DynamicMessage.init(allocator, nested);
    defer msg.deinit();
    try msg.add(field, .{ .int32 = 123 });

    const encoded = try msg.encodedWithRegistry(&file, &registry);
    defer allocator.free(encoded);
    try std.testing.expectEqualSlices(u8, &.{ 0xa0, 0x06, 0x7b }, encoded);

    var decoded = DynamicMessage.init(allocator, nested);
    defer decoded.deinit();
    try decoded.decodeWithRegistry(&file, &registry, encoded);
    try std.testing.expectEqual(@as(i32, 123), decoded.get("nested_note").?.values.items[0].int32);
}

test "dynamic rejects extension descriptors for different extendees" {
    const allocator = std.testing.allocator;
    var file = try parser.Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message First { extensions 100 to max; }
        \\message Second { extensions 100 to max; }
        \\message FirstPayload { optional int32 id = 1; }
        \\message SecondPayload { optional int32 id = 1; }
        \\message MsFirst { option message_set_wire_format = true; extensions 4 to max; }
        \\message MsSecond { option message_set_wire_format = true; extensions 4 to max; }
        \\extend First { optional int32 first_score = 100; }
        \\extend Second { optional int32 second_score = 100; }
        \\extend First { optional FirstPayload first_payload = 101; }
        \\extend Second { optional SecondPayload second_payload = 101; }
        \\extend MsFirst { optional FirstPayload ms_first_payload = 100; }
        \\extend MsSecond { optional SecondPayload ms_second_payload = 100; }
    );
    defer file.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);
    const first = file.findMessage("First").?;
    const ms_first = file.findMessage("MsFirst").?;
    const second_score = registry.findExtensionByName("demo.Second", "demo.second_score").?;
    const first_payload_ext = registry.findExtensionByName("demo.First", "demo.first_payload").?;
    const second_payload_ext = registry.findExtensionByName("demo.Second", "demo.second_payload").?;
    const ms_first_payload_ext = registry.findExtensionByName("demo.MsFirst", "demo.ms_first_payload").?;
    const ms_second_payload_ext = registry.findExtensionByName("demo.MsSecond", "demo.ms_second_payload").?;
    const second_payload_desc = file.findMessage("SecondPayload").?;

    var wrong_scalar = DynamicMessage.init(allocator, first);
    defer wrong_scalar.deinit();
    try wrong_scalar.add(second_score, .{ .int32 = 7 });
    try std.testing.expectError(error.TypeMismatch, wrong_scalar.encodedWithRegistry(&file, &registry));
    try std.testing.expectError(error.TypeMismatch, wrong_scalar.encodedDeterministicWithRegistry(&file, &registry));

    const wrong_payload = try allocator.create(DynamicMessage);
    wrong_payload.* = DynamicMessage.init(allocator, second_payload_desc);
    var wrong_message = DynamicMessage.init(allocator, first);
    defer wrong_message.deinit();
    try wrong_message.add(second_payload_ext, .{ .message = wrong_payload });
    try std.testing.expectError(error.TypeMismatch, wrong_message.encodedWithRegistry(&file, &registry));
    try std.testing.expectError(error.TypeMismatch, wrong_message.encodedDeterministicWithRegistry(&file, &registry));

    const ok_payload = try allocator.create(DynamicMessage);
    ok_payload.* = DynamicMessage.init(allocator, file.findMessage("FirstPayload").?);
    var ok = DynamicMessage.init(allocator, first);
    defer ok.deinit();
    try ok.add(first_payload_ext, .{ .message = ok_payload });
    const encoded = try ok.encodedWithRegistry(&file, &registry);
    defer allocator.free(encoded);
    try std.testing.expect(std.mem.indexOf(u8, encoded, &.{ 0xaa, 0x06, 0x00 }) != null);

    const wrong_ms_payload = try allocator.create(DynamicMessage);
    wrong_ms_payload.* = DynamicMessage.init(allocator, second_payload_desc);
    var wrong_message_set = DynamicMessage.init(allocator, ms_first);
    defer wrong_message_set.deinit();
    try wrong_message_set.add(ms_second_payload_ext, .{ .message = wrong_ms_payload });
    try std.testing.expectError(error.TypeMismatch, wrong_message_set.encodedWithRegistry(&file, &registry));
    try std.testing.expectError(error.TypeMismatch, wrong_message_set.encodedDeterministicWithRegistry(&file, &registry));

    const ok_ms_payload = try allocator.create(DynamicMessage);
    ok_ms_payload.* = DynamicMessage.init(allocator, file.findMessage("FirstPayload").?);
    var ok_message_set = DynamicMessage.init(allocator, ms_first);
    defer ok_message_set.deinit();
    try ok_message_set.add(ms_first_payload_ext, .{ .message = ok_ms_payload });
    const encoded_message_set = try ok_message_set.encodedWithRegistry(&file, &registry);
    defer allocator.free(encoded_message_set);
    try std.testing.expectEqualSlices(u8, &.{ 0x0b, 0x10, 0x64, 0x1a, 0x00, 0x0c }, encoded_message_set);
}

test "dynamic initialized helpers validate proto2 extension message payloads" {
    const allocator = std.testing.allocator;
    var file = try parser.Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host { extensions 100 to max; }
        \\message Ext { required int32 id = 1; }
        \\extend Host { optional Ext ext = 100; }
    );
    defer file.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);
    const host = file.findMessage("Host").?;
    const ext_desc = file.findMessage("Ext").?;
    const ext_field = registry.findExtension("demo.Host", 100).?;

    const missing_ext = try allocator.create(DynamicMessage);
    missing_ext.* = DynamicMessage.init(allocator, ext_desc);
    var missing_msg = DynamicMessage.init(allocator, host);
    defer missing_msg.deinit();
    try missing_msg.add(ext_field, .{ .message = missing_ext });
    try std.testing.expectError(error.MissingRequiredField, missing_msg.encodedInitializedWithRegistry(&file, &registry));
    const missing_path = (try missing_msg.missingRequiredFieldPath(allocator)).?;
    defer allocator.free(missing_path);
    try std.testing.expectEqualStrings("ext.id", missing_path);

    const ok_ext = try allocator.create(DynamicMessage);
    ok_ext.* = DynamicMessage.init(allocator, ext_desc);
    try ok_ext.add(ext_desc.findField("id").?, .{ .int32 = 7 });
    var ok_msg = DynamicMessage.init(allocator, host);
    defer ok_msg.deinit();
    try ok_msg.add(ext_field, .{ .message = ok_ext });
    const encoded = try ok_msg.encodedInitializedWithRegistry(&file, &registry);
    defer allocator.free(encoded);

    var decoded = DynamicMessage.init(allocator, host);
    defer decoded.deinit();
    try decoded.decodeInitializedWithRegistry(&file, &registry, encoded);

    var bad_writer = wire.Writer.init(allocator);
    defer bad_writer.deinit();
    try bad_writer.writeMessage(100, &.{});
    var invalid = DynamicMessage.init(allocator, host);
    defer invalid.deinit();
    try std.testing.expectError(error.MissingRequiredField, invalid.decodeInitializedWithRegistry(&file, &registry, bad_writer.slice()));
    const invalid_path = (try invalid.missingRequiredFieldPath(allocator)).?;
    defer allocator.free(invalid_path);
    try std.testing.expectEqualStrings("ext.id", invalid_path);
}

test "dynamic encodes and decodes proto2 MessageSet items" {
    const allocator = std.testing.allocator;
    var file = try parser.Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host { option message_set_wire_format = true; extensions 4 to max; }
        \\message Ext { optional int32 value = 1; }
        \\extend Host { optional Ext ext = 100; }
    );
    defer file.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);
    const host = file.findMessage("Host").?;
    const ext_desc = file.findMessage("Ext").?;
    const ext_field = registry.findExtension("demo.Host", 100).?;

    const ext_msg = try allocator.create(DynamicMessage);
    ext_msg.* = DynamicMessage.init(allocator, ext_desc);
    try ext_msg.add(ext_desc.findField("value").?, .{ .int32 = 7 });

    var msg = DynamicMessage.init(allocator, host);
    defer msg.deinit();
    try msg.add(ext_field, .{ .message = ext_msg });

    const encoded = try msg.encoded(&file);
    defer allocator.free(encoded);
    try std.testing.expectEqualSlices(u8, &.{ 0x0b, 0x10, 0x64, 0x1a, 0x02, 0x08, 0x07, 0x0c }, encoded);

    const deterministic = try msg.encodedDeterministic(&file);
    defer allocator.free(deterministic);
    try std.testing.expectEqualSlices(u8, encoded, deterministic);

    var decoded = DynamicMessage.init(allocator, host);
    defer decoded.deinit();
    try decoded.decodeWithRegistry(&file, &registry, encoded);
    const decoded_ext = decoded.get("ext").?.values.items[0].message;
    try std.testing.expectEqual(@as(i32, 7), decoded_ext.get("value").?.values.items[0].int32);
}

test "dynamic initialized helpers validate MessageSet extension payloads" {
    const allocator = std.testing.allocator;
    var file = try parser.Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host { option message_set_wire_format = true; extensions 4 to max; }
        \\message Ext { required int32 id = 1; }
        \\extend Host { optional Ext ext = 100; }
    );
    defer file.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);
    const host = file.findMessage("Host").?;
    const ext_desc = file.findMessage("Ext").?;
    const ext_field = registry.findExtension("demo.Host", 100).?;

    const missing_ext = try allocator.create(DynamicMessage);
    missing_ext.* = DynamicMessage.init(allocator, ext_desc);
    var missing_msg = DynamicMessage.init(allocator, host);
    defer missing_msg.deinit();
    try missing_msg.add(ext_field, .{ .message = missing_ext });
    try std.testing.expectError(error.MissingRequiredField, missing_msg.encodedInitializedWithRegistry(&file, &registry));
    const missing_path = (try missing_msg.missingRequiredFieldPath(allocator)).?;
    defer allocator.free(missing_path);
    try std.testing.expectEqualStrings("ext.id", missing_path);

    var bad_writer = wire.Writer.init(allocator);
    defer bad_writer.deinit();
    try bad_writer.writeTag(1, .start_group);
    try bad_writer.writeUInt32(2, 100);
    try bad_writer.writeMessage(3, &.{});
    try bad_writer.writeTag(1, .end_group);
    var invalid = DynamicMessage.init(allocator, host);
    defer invalid.deinit();
    try std.testing.expectError(error.MissingRequiredField, invalid.decodeInitializedWithRegistry(&file, &registry, bad_writer.slice()));
    const invalid_path = (try invalid.missingRequiredFieldPath(allocator)).?;
    defer allocator.free(invalid_path);
    try std.testing.expectEqualStrings("ext.id", invalid_path);

    const ok_ext = try allocator.create(DynamicMessage);
    ok_ext.* = DynamicMessage.init(allocator, ext_desc);
    try ok_ext.add(ext_desc.findField("id").?, .{ .int32 = 9 });
    var ok_msg = DynamicMessage.init(allocator, host);
    defer ok_msg.deinit();
    try ok_msg.add(ext_field, .{ .message = ok_ext });
    const encoded = try ok_msg.encodedInitializedWithRegistry(&file, &registry);
    defer allocator.free(encoded);
    var decoded = DynamicMessage.init(allocator, host);
    defer decoded.deinit();
    try decoded.decodeInitializedWithRegistry(&file, &registry, encoded);
}

test "dynamic MessageSet accepts payload before type id and preserves unknown items" {
    const allocator = std.testing.allocator;
    var file = try parser.Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host { option message_set_wire_format = true; extensions 4 to max; }
        \\message Ext { optional int32 value = 1; }
        \\extend Host { optional Ext ext = 100; }
    );
    defer file.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);
    const host = file.findMessage("Host").?;

    var reordered = wire.Writer.init(allocator);
    defer reordered.deinit();
    try reordered.writeTag(1, .start_group);
    try reordered.writeMessage(3, &.{ 0x08, 0x09 });
    try reordered.writeUInt32(2, 100);
    try reordered.writeTag(1, .end_group);

    var decoded = DynamicMessage.init(allocator, host);
    defer decoded.deinit();
    try decoded.decodeWithRegistry(&file, &registry, reordered.slice());
    try std.testing.expectEqual(@as(i32, 9), decoded.get("ext").?.values.items[0].message.get("value").?.values.items[0].int32);

    var unknown = wire.Writer.init(allocator);
    defer unknown.deinit();
    try unknown.writeTag(1, .start_group);
    try unknown.writeUInt32(2, 150);
    try unknown.writeMessage(3, &.{ 0x08, 0x2a });
    try unknown.writeTag(1, .end_group);

    var unknown_msg = DynamicMessage.init(allocator, host);
    defer unknown_msg.deinit();
    try unknown_msg.decodeWithRegistry(&file, &registry, unknown.slice());
    try std.testing.expectEqual(@as(usize, 1), unknown_msg.unknownCount());
    try std.testing.expectEqual(@as(wire.FieldNumber, 150), unknown_msg.unknown_fields.items[0].number);
    try std.testing.expectEqual(wire.WireType.length_delimited, unknown_msg.unknown_fields.items[0].wire_type);

    const unknown_roundtrip = try unknown_msg.encoded(&file);
    defer allocator.free(unknown_roundtrip);
    try std.testing.expectEqualSlices(u8, unknown.slice(), unknown_roundtrip);

    var later = wire.Writer.init(allocator);
    defer later.deinit();
    try later.writeBytes(160, &.{ 0x08, 0x02 });
    var earlier = wire.Writer.init(allocator);
    defer earlier.deinit();
    try earlier.writeBytes(150, &.{ 0x08, 0x01 });
    var same_later = wire.Writer.init(allocator);
    defer same_later.deinit();
    try same_later.writeBytes(150, &.{ 0x08, 0x03 });

    var deterministic_unknown = DynamicMessage.init(allocator, host);
    defer deterministic_unknown.deinit();
    try deterministic_unknown.unknown_fields.append(allocator, .{ .number = 160, .wire_type = .length_delimited, .data = try allocator.dupe(u8, later.slice()) });
    try deterministic_unknown.unknown_fields.append(allocator, .{ .number = 150, .wire_type = .length_delimited, .data = try allocator.dupe(u8, same_later.slice()) });
    try deterministic_unknown.unknown_fields.append(allocator, .{ .number = 150, .wire_type = .length_delimited, .data = try allocator.dupe(u8, earlier.slice()) });

    const deterministic = try deterministic_unknown.encodedDeterministic(&file);
    defer allocator.free(deterministic);
    var expected = wire.Writer.init(allocator);
    defer expected.deinit();
    try writeMessageSetItem(&expected, 150, &.{ 0x08, 0x03 });
    try writeMessageSetItem(&expected, 150, &.{ 0x08, 0x01 });
    try writeMessageSetItem(&expected, 160, &.{ 0x08, 0x02 });
    try std.testing.expectEqualSlices(u8, expected.slice(), deterministic);
}

test "dynamic MessageSet rejects invalid type ids" {
    const allocator = std.testing.allocator;
    var file = try parser.Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Host { option message_set_wire_format = true; extensions 4 to max; }
    );
    defer file.deinit();
    const host = file.findMessage("Host").?;

    var zero = wire.Writer.init(allocator);
    defer zero.deinit();
    try zero.writeTag(1, .start_group);
    try zero.writeUInt32(2, 0);
    try zero.writeMessage(3, &.{});
    try zero.writeTag(1, .end_group);
    var zero_msg = DynamicMessage.init(allocator, host);
    defer zero_msg.deinit();
    try std.testing.expectError(error.InvalidFieldNumber, zero_msg.decode(&file, zero.slice()));

    var too_large = wire.Writer.init(allocator);
    defer too_large.deinit();
    try too_large.writeTag(1, .start_group);
    try too_large.writeUInt32(2, @as(u32, std.math.maxInt(wire.FieldNumber)) + 1);
    try too_large.writeMessage(3, &.{});
    try too_large.writeTag(1, .end_group);
    var too_large_msg = DynamicMessage.init(allocator, host);
    defer too_large_msg.deinit();
    try std.testing.expectError(error.InvalidFieldNumber, too_large_msg.decode(&file, too_large.slice()));
}

test "dynamic closed enum unknown values are preserved as unknown fields" {
    const allocator = std.testing.allocator;
    var file = try parser.Parser.parse(allocator,
        \\syntax = "proto2";
        \\enum Kind { A = 1; B = 2; }
        \\message M {
        \\  optional Kind single = 1;
        \\  repeated Kind many = 2;
        \\  repeated Kind packed = 3 [packed = true];
        \\}
    );
    defer file.deinit();
    const desc = file.findMessage("M").?;

    var packed_payload = wire.Writer.init(allocator);
    defer packed_payload.deinit();
    try packed_payload.writeVarint(2);
    try packed_payload.writeVarint(123);

    var encoded = wire.Writer.init(allocator);
    defer encoded.deinit();
    try encoded.writeInt32(1, 123);
    try encoded.writeInt32(2, 1);
    try encoded.writeInt32(2, 123);
    try encoded.writeBytes(3, packed_payload.slice());

    var msg = DynamicMessage.init(allocator, desc);
    defer msg.deinit();
    try msg.decode(&file, encoded.slice());

    try std.testing.expect(msg.get("single") == null);
    try std.testing.expectEqual(@as(i32, 1), msg.get("many").?.values.items[0].enumeration);
    try std.testing.expectEqual(@as(usize, 1), msg.get("many").?.values.items.len);
    try std.testing.expectEqual(@as(i32, 2), msg.get("packed").?.values.items[0].enumeration);
    try std.testing.expectEqual(@as(usize, 1), msg.get("packed").?.values.items.len);
    try std.testing.expectEqual(@as(usize, 3), msg.unknownCount());

    const unknown_single = try msg.unknownByNumberAlloc(allocator, 1);
    defer allocator.free(unknown_single);
    try std.testing.expectEqual(@as(usize, 1), unknown_single.len);
    try std.testing.expectEqualSlices(u8, &.{ 0x08, 0x7b }, unknown_single[0].data);

    const unknown_many = try msg.unknownByNumberAlloc(allocator, 2);
    defer allocator.free(unknown_many);
    try std.testing.expectEqual(@as(usize, 1), unknown_many.len);
    try std.testing.expectEqualSlices(u8, &.{ 0x10, 0x7b }, unknown_many[0].data);

    const unknown_packed = try msg.unknownByNumberAlloc(allocator, 3);
    defer allocator.free(unknown_packed);
    try std.testing.expectEqual(@as(usize, 1), unknown_packed.len);
    try std.testing.expectEqualSlices(u8, &.{ 0x18, 0x7b }, unknown_packed[0].data);
}

test "dynamic open enums keep unknown numeric values" {
    const allocator = std.testing.allocator;
    var file = try parser.Parser.parse(allocator,
        \\syntax = "proto3";
        \\enum Kind { A = 0; B = 1; }
        \\message M { Kind single = 1; repeated Kind many = 2; repeated Kind packed = 3; }
    );
    defer file.deinit();
    const desc = file.findMessage("M").?;

    var packed_payload = wire.Writer.init(allocator);
    defer packed_payload.deinit();
    try packed_payload.writeVarint(123);
    try packed_payload.writeVarint(1);

    var encoded = wire.Writer.init(allocator);
    defer encoded.deinit();
    try encoded.writeInt32(1, 123);
    try encoded.writeInt32(2, 123);
    try encoded.writeBytes(3, packed_payload.slice());

    var msg = DynamicMessage.init(allocator, desc);
    defer msg.deinit();
    try msg.decode(&file, encoded.slice());
    try std.testing.expectEqual(@as(i32, 123), msg.get("single").?.values.items[0].enumeration);
    try std.testing.expectEqual(@as(i32, 123), msg.get("many").?.values.items[0].enumeration);
    try std.testing.expectEqual(@as(i32, 123), msg.get("packed").?.values.items[0].enumeration);
    try std.testing.expectEqual(@as(i32, 1), msg.get("packed").?.values.items[1].enumeration);
    try std.testing.expectEqual(@as(usize, 0), msg.unknownCount());
}

test "dynamic enum-level features override file enum openness" {
    const allocator = std.testing.allocator;
    {
        var file = try parser.Parser.parse(allocator,
            \\edition = "2023";
            \\option features.enum_type = CLOSED;
            \\enum Kind { option features.enum_type = OPEN; A = 0; B = 1; }
            \\message M { Kind single = 1; repeated Kind many = 2; }
        );
        defer file.deinit();
        const desc = file.findMessage("M").?;

        var encoded = wire.Writer.init(allocator);
        defer encoded.deinit();
        try encoded.writeInt32(1, 123);
        try encoded.writeInt32(2, 123);

        var msg = DynamicMessage.init(allocator, desc);
        defer msg.deinit();
        try msg.decode(&file, encoded.slice());
        try std.testing.expectEqual(@as(i32, 123), msg.get("single").?.values.items[0].enumeration);
        try std.testing.expectEqual(@as(i32, 123), msg.get("many").?.values.items[0].enumeration);
        try std.testing.expectEqual(@as(usize, 0), msg.unknownCount());
    }
    {
        var file = try parser.Parser.parse(allocator,
            \\edition = "2023";
            \\option features.enum_type = OPEN;
            \\enum Kind { option features.enum_type = CLOSED; A = 0; B = 1; }
            \\message M { Kind single = 1; repeated Kind many = 2; }
        );
        defer file.deinit();
        const desc = file.findMessage("M").?;

        var encoded = wire.Writer.init(allocator);
        defer encoded.deinit();
        try encoded.writeInt32(1, 123);
        try encoded.writeInt32(2, 1);
        try encoded.writeInt32(2, 123);

        var msg = DynamicMessage.init(allocator, desc);
        defer msg.deinit();
        try msg.decode(&file, encoded.slice());
        try std.testing.expect(msg.get("single") == null);
        try std.testing.expectEqual(@as(i32, 1), msg.get("many").?.values.items[0].enumeration);
        try std.testing.expectEqual(@as(usize, 1), msg.get("many").?.values.items.len);
        try std.testing.expectEqual(@as(usize, 2), msg.unknownCount());
    }
}

test "dynamic closed enum map entries with unknown values are preserved whole" {
    const allocator = std.testing.allocator;
    var file = try parser.Parser.parse(allocator,
        \\edition = "2023";
        \\option features.enum_type = CLOSED;
        \\enum Kind { A = 0; B = 1; }
        \\message M { map<string, Kind> vals = 1; }
    );
    defer file.deinit();
    const desc = file.findMessage("M").?;

    var bad_entry = wire.Writer.init(allocator);
    defer bad_entry.deinit();
    try bad_entry.writeString(1, "bad");
    try bad_entry.writeInt32(2, 123);

    var good_entry = wire.Writer.init(allocator);
    defer good_entry.deinit();
    try good_entry.writeString(1, "ok");
    try good_entry.writeInt32(2, 1);

    var encoded = wire.Writer.init(allocator);
    defer encoded.deinit();
    try encoded.writeMessage(1, bad_entry.slice());
    const bad_raw = try allocator.dupe(u8, encoded.slice());
    defer allocator.free(bad_raw);
    try encoded.writeMessage(1, good_entry.slice());

    var msg = DynamicMessage.init(allocator, desc);
    defer msg.deinit();
    try msg.decode(&file, encoded.slice());
    try std.testing.expectEqual(@as(usize, 1), msg.get("vals").?.values.items.len);
    const entry = msg.get("vals").?.values.items[0].map_entry;
    try std.testing.expectEqualStrings("ok", entry.key.string);
    try std.testing.expectEqual(@as(i32, 1), entry.value.enumeration);
    try std.testing.expectEqual(@as(usize, 1), msg.unknownCount());
    try std.testing.expectEqualSlices(u8, bad_raw, msg.unknown_fields.items[0].data);
}

test "dynamic deterministic encoding sorts fields and unknowns stably" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\message Order { int32 a = 1; int32 b = 2; repeated int32 c = 3; }
    ;
    var file = try parser.Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("Order").?;

    var msg = DynamicMessage.init(allocator, desc);
    defer msg.deinit();
    try msg.add(desc.findField("b").?, .{ .int32 = 2 });
    try msg.add(desc.findField("a").?, .{ .int32 = 1 });
    try msg.add(desc.findField("c").?, .{ .int32 = 3 });
    try msg.unknown_fields.append(allocator, .{ .number = 50, .wire_type = .varint, .data = try allocator.dupe(u8, &.{ 0x90, 0x03, 0x02 }) });
    try msg.unknown_fields.append(allocator, .{ .number = 40, .wire_type = .varint, .data = try allocator.dupe(u8, &.{ 0xc0, 0x02, 0x01 }) });
    try msg.unknown_fields.append(allocator, .{ .number = 50, .wire_type = .length_delimited, .data = try allocator.dupe(u8, &.{ 0x92, 0x03, 0x01, 0x61 }) });
    try msg.unknown_fields.append(allocator, .{ .number = 50, .wire_type = .varint, .data = try allocator.dupe(u8, &.{ 0x90, 0x03, 0x01 }) });

    const normal = try msg.encoded(&file);
    defer allocator.free(normal);
    try std.testing.expectEqualSlices(u8, &.{ 0x10, 0x02, 0x08, 0x01, 0x1a, 0x01, 0x03, 0x90, 0x03, 0x02, 0xc0, 0x02, 0x01, 0x92, 0x03, 0x01, 0x61, 0x90, 0x03, 0x01 }, normal);

    const deterministic = try msg.encodedDeterministic(&file);
    defer allocator.free(deterministic);
    try std.testing.expectEqualSlices(u8, &.{ 0x08, 0x01, 0x10, 0x02, 0x1a, 0x01, 0x03, 0xc0, 0x02, 0x01, 0x90, 0x03, 0x02, 0x92, 0x03, 0x01, 0x61, 0x90, 0x03, 0x01 }, deterministic);
}

test "dynamic deterministic encoding sorts map entries by key" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\message M { map<string, int32> counts = 1; }
    ;
    var file = try parser.Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("M").?;
    const field = desc.findField("counts").?;

    var msg = DynamicMessage.init(allocator, desc);
    defer msg.deinit();
    const b = try allocator.create(MapEntry);
    b.* = .{ .key = .{ .string = try allocator.dupe(u8, "b") }, .value = .{ .int32 = 2 } };
    try msg.add(field, .{ .map_entry = b });
    const a = try allocator.create(MapEntry);
    a.* = .{ .key = .{ .string = try allocator.dupe(u8, "a") }, .value = .{ .int32 = 1 } };
    try msg.add(field, .{ .map_entry = a });

    const deterministic = try msg.encodedDeterministic(&file);
    defer allocator.free(deterministic);
    try std.testing.expect(std.mem.indexOf(u8, deterministic, &.{ 'a', 0x10, 0x01 }).? < std.mem.indexOf(u8, deterministic, &.{ 'b', 0x10, 0x02 }).?);
}

test "dynamic deterministic encoding recurses into messages groups and map values" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto2";
        \\message Child {
        \\  optional int32 a = 1;
        \\  optional int32 b = 2;
        \\}
        \\message Parent {
        \\  optional Child child = 1;
        \\  optional group Legacy = 2 {
        \\    optional int32 a = 3;
        \\    optional int32 b = 4;
        \\  }
        \\  map<string, Child> keyed = 5;
        \\}
    ;
    var file = try parser.Parser.parse(allocator, source);
    defer file.deinit();
    const child_desc = file.findMessage("Child").?;
    const parent_desc = file.findMessage("Parent").?;
    const legacy_desc = parent_desc.findMessage("Legacy").?;

    var msg = DynamicMessage.init(allocator, parent_desc);
    defer msg.deinit();

    var child = try allocator.create(DynamicMessage);
    var child_transferred = false;
    errdefer if (!child_transferred) allocator.destroy(child);
    child.* = DynamicMessage.init(allocator, child_desc);
    errdefer if (!child_transferred) child.deinit();
    try child.add(child_desc.findField("b").?, .{ .int32 = 2 });
    try child.add(child_desc.findField("a").?, .{ .int32 = 1 });
    try msg.add(parent_desc.findField("child").?, .{ .message = child });
    child_transferred = true;

    var legacy = try allocator.create(DynamicMessage);
    var legacy_transferred = false;
    errdefer if (!legacy_transferred) allocator.destroy(legacy);
    legacy.* = DynamicMessage.init(allocator, legacy_desc);
    errdefer if (!legacy_transferred) legacy.deinit();
    try legacy.add(legacy_desc.findField("b").?, .{ .int32 = 4 });
    try legacy.add(legacy_desc.findField("a").?, .{ .int32 = 3 });
    try msg.add(parent_desc.findField("legacy").?, .{ .group = legacy });
    legacy_transferred = true;

    const keyed = parent_desc.findField("keyed").?;
    const b_entry = try allocator.create(MapEntry);
    var b_entry_transferred = false;
    errdefer if (!b_entry_transferred) allocator.destroy(b_entry);
    b_entry.* = .{
        .key = .{ .string = try allocator.dupe(u8, "b") },
        .value = .{ .message = try allocator.create(DynamicMessage) },
    };
    errdefer if (!b_entry_transferred) b_entry.deinit(allocator);
    b_entry.value.message.* = DynamicMessage.init(allocator, child_desc);
    try b_entry.value.message.add(child_desc.findField("b").?, .{ .int32 = 20 });
    try b_entry.value.message.add(child_desc.findField("a").?, .{ .int32 = 10 });
    try msg.add(keyed, .{ .map_entry = b_entry });
    b_entry_transferred = true;

    const a_entry = try allocator.create(MapEntry);
    var a_entry_transferred = false;
    errdefer if (!a_entry_transferred) allocator.destroy(a_entry);
    a_entry.* = .{
        .key = .{ .string = try allocator.dupe(u8, "a") },
        .value = .{ .message = try allocator.create(DynamicMessage) },
    };
    errdefer if (!a_entry_transferred) a_entry.deinit(allocator);
    a_entry.value.message.* = DynamicMessage.init(allocator, child_desc);
    try a_entry.value.message.add(child_desc.findField("b").?, .{ .int32 = 2 });
    try a_entry.value.message.add(child_desc.findField("a").?, .{ .int32 = 1 });
    try msg.add(keyed, .{ .map_entry = a_entry });
    a_entry_transferred = true;

    const normal = try msg.encoded(&file);
    defer allocator.free(normal);
    const deterministic = try msg.encodedDeterministic(&file);
    defer allocator.free(deterministic);

    try std.testing.expect(!std.mem.eql(u8, normal, deterministic));
    try std.testing.expectEqualSlices(u8, &.{
        0x0a, 0x04, 0x08, 0x01, 0x10, 0x02,
        0x13, 0x18, 0x03, 0x20, 0x04, 0x14,
        0x2a, 0x09, 0x0a, 0x01, 'a',  0x12,
        0x04, 0x08, 0x01, 0x10, 0x02, 0x2a,
        0x09, 0x0a, 0x01, 'b',  0x12, 0x04,
        0x08, 0x0a, 0x10, 0x14,
    }, deterministic);
}

test "dynamic unknownByNumberAlloc returns non-contiguous unknown fields" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\message Empty {}
    ;
    var file = try parser.Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("Empty").?;

    var writer = wire.Writer.init(allocator);
    defer writer.deinit();
    try writer.writeUInt32(100, 1);
    try writer.writeUInt32(101, 2);
    try writer.writeUInt32(100, 3);

    var msg = DynamicMessage.init(allocator, desc);
    defer msg.deinit();
    try msg.decode(&file, writer.slice());
    const fields = try msg.unknownByNumberAlloc(allocator, 100);
    defer allocator.free(fields);
    try std.testing.expectEqual(@as(usize, 2), fields.len);
    try std.testing.expectEqual(@as(wire.FieldNumber, 100), fields[0].number);
    try std.testing.expectEqual(@as(wire.FieldNumber, 100), fields[1].number);

    const numbers = try msg.unknownFieldNumbersAlloc(allocator);
    defer allocator.free(numbers);
    try std.testing.expectEqualSlices(wire.FieldNumber, &.{ 100, 101, 100 }, numbers);

    const runs = try msg.unknownFieldNumberRunsAlloc(allocator);
    defer allocator.free(runs);
    try std.testing.expectEqual(@as(usize, 2), runs.len);
    try std.testing.expectEqual(wire.RawFieldNumberRun{ .number = 100, .count = 2 }, runs[0]);
    try std.testing.expectEqual(wire.RawFieldNumberRun{ .number = 101, .count = 1 }, runs[1]);
    try std.testing.expectEqual(@as(usize, 2), wire.rawFieldNumberRunCount(runs, 100));
    try std.testing.expectEqual(@as(usize, 0), wire.rawFieldNumberRunCount(runs, 102));
}

test "dynamic deterministic encoding preserves same-number unknown ordering" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\message Empty {}
    ;
    var file = try parser.Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("Empty").?;

    var payload = wire.Writer.init(allocator);
    defer payload.deinit();
    try payload.writeBytes(666, "abc");
    try payload.writeUInt64(666, 123);
    try payload.writeBytes(666, "def");
    try payload.writeUInt64(666, 456);

    var msg = DynamicMessage.init(allocator, desc);
    defer msg.deinit();
    try msg.decode(&file, payload.slice());

    const deterministic = try msg.encodedDeterministic(&file);
    defer allocator.free(deterministic);
    try std.testing.expectEqualSlices(u8, payload.slice(), deterministic);
}

test "dynamic proto3 encoding preserves negative zero presence" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\message Floats { float f = 1; double d = 2; }
    ;
    var file = try parser.Parser.parse(allocator, source);
    defer file.deinit();
    const desc = file.findMessage("Floats").?;

    var msg = DynamicMessage.init(allocator, desc);
    defer msg.deinit();
    try msg.add(desc.findField("f").?, .{ .float = -0.0 });
    try msg.add(desc.findField("d").?, .{ .double = -0.0 });

    const encoded = try msg.encodedDeterministic(&file);
    defer allocator.free(encoded);
    try std.testing.expectEqualSlices(u8, &.{ 0x0d, 0x00, 0x00, 0x00, 0x80, 0x11, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80 }, encoded);
}
