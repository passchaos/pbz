const std = @import("std");
const pbz = @import("pbz");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var file = try pbz.ProtoParser.parse(allocator,
        \\syntax = "proto3";
        \\package demo.reserved;
        \\message Event {
        \\  reserved 5 to 10;
        \\  reserved "reserved_field", "legacy_name";
        \\  int32 id = 1;
        \\  string label = 2;
        \\}
    );
    defer file.deinit();
    file.name = "reserved.proto";

    const event_desc = file.findMessage("Event") orelse return error.MissingDescriptor;
    try std.testing.expectEqual(@as(usize, 1), event_desc.reserved_ranges.items.len);
    try std.testing.expectEqual(@as(i64, 5), event_desc.reserved_ranges.items[0].start);
    try std.testing.expectEqual(@as(?i64, 11), event_desc.reserved_ranges.items[0].end);
    try std.testing.expectEqualStrings("reserved_field", event_desc.reserved_names.items[0]);
    try std.testing.expectEqualStrings("legacy_name", event_desc.reserved_names.items[1]);

    const descriptor_bytes = try pbz.encodeFileDescriptorProto(allocator, &file, file.name);
    defer allocator.free(descriptor_bytes);
    var decoded_file = try pbz.decodeFileDescriptorProto(allocator, descriptor_bytes);
    defer decoded_file.deinit();
    const decoded_event = decoded_file.findMessage("Event") orelse return error.MissingDescriptor;
    try std.testing.expectEqualStrings("reserved_field", decoded_event.reserved_names.items[0]);
    try std.testing.expectEqual(@as(i64, 5), decoded_event.reserved_ranges.items[0].start);

    // Protobuf TextFormat treats reserved field names as intentionally ignored
    // compatibility tombstones rather than ordinary unknown names.  pbz mirrors
    // that behavior across scalar, string, aggregate, angle-bracket, and list
    // spellings while still parsing valid fields in the same input.
    var parsed = try pbz.parseTextAlloc(allocator, &file, event_desc,
        \\reserved_field: true
        \\reserved_field: -123
        \\reserved_field: 0.123
        \\reserved_field: ENUM_VALUE
        \\reserved_field: "hello"
        \\reserved_field: { a: 123 }
        \\reserved_field: < a: 123 >
        \\reserved_field: [-123, 456]
        \\reserved_field: [0.123, 1e-10]
        \\reserved_field: ["hello", "world"]
        \\legacy_name: "old"
        \\id: 7
        \\label: "kept"
    );
    defer parsed.deinit();
    try std.testing.expectEqual(@as(i32, 7), parsed.get("id").?.values.items[0].int32);
    try std.testing.expectEqualStrings("kept", parsed.get("label").?.values.items[0].string);
    try std.testing.expectEqual(@as(usize, 0), parsed.unknownCount());
    try std.testing.expect(parsed.get("reserved_field") == null);

    const formatted = try pbz.formatTextAlloc(allocator, &file, &parsed, .{});
    defer allocator.free(formatted);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "reserved_field") == null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "legacy_name") == null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "id: 7") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "label: \"kept\"") != null);

    try std.testing.expectError(error.ReservedField, pbz.ProtoParser.parse(allocator,
        \\syntax = "proto3";
        \\message Bad { reserved 5 to 10; int32 forbidden = 7; }
    ));
    try std.testing.expectError(error.ReservedField, pbz.ProtoParser.parse(allocator,
        \\syntax = "proto3";
        \\message Bad { reserved "old"; int32 old = 1; }
    ));
}

comptime {
    _ = pbz;
}
