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
        \\message Child { string label = 1; int32 id = 2; }
        \\enum Role { option features.enum_type = CLOSED; ROLE_UNKNOWN = 0; ROLE_ADMIN = 1; }
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
        \\}
    );
    defer file.deinit();

    const desc = file.findMessage("Editions") orelse return error.MissingDescriptor;
    const child_desc = file.findMessage("Child") orelse return error.MissingDescriptor;

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
}

comptime {
    _ = pbz;
}
