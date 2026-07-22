const std = @import("std");
const pbz = @import("pbz");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var file = try pbz.ProtoParser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.dynamicms;
        \\message Host { option message_set_wire_format = true; extensions 4 to max; }
        \\message Ext { optional int32 value = 1; }
        \\extend Host { optional Ext ext = 100; }
    );
    defer file.deinit();
    var registry = pbz.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);

    const host_desc = file.findMessage("Host") orelse return error.MissingDescriptor;
    const ext_desc = file.findMessage("Ext") orelse return error.MissingDescriptor;
    const ext_field = registry.findExtension("demo.dynamicms.Host", 100) orelse return error.MissingField;
    const refl = pbz.Reflection.init(allocator, &registry);
    try std.testing.expect(refl.messageIsMessageSetWireFormat(host_desc));
    try std.testing.expect(!refl.messageIsMessageSetWireFormat(ext_desc));

    const ext_msg = try allocator.create(pbz.DynamicMessage);
    ext_msg.* = pbz.DynamicMessage.init(allocator, ext_desc);
    errdefer {
        ext_msg.deinit();
        allocator.destroy(ext_msg);
    }
    try ext_msg.add(ext_desc.findField("value") orelse return error.MissingField, .{ .int32 = 7 });

    var host = pbz.DynamicMessage.init(allocator, host_desc);
    defer host.deinit();
    try host.add(ext_field, .{ .message = ext_msg });

    const encoded = try host.encodedWithRegistry(&file, &registry);
    defer allocator.free(encoded);
    try std.testing.expectEqualSlices(u8, &.{ 0x0b, 0x10, 0x64, 0x1a, 0x02, 0x08, 0x07, 0x0c }, encoded);

    var decoded = pbz.DynamicMessage.init(allocator, host_desc);
    defer decoded.deinit();
    try decoded.decodeWithRegistry(&file, &registry, encoded);
    try std.testing.expectEqual(@as(i32, 7), decoded.get("ext").?.values.items[0].message.get("value").?.values.items[0].int32);

    const json = try pbz.stringifyJsonAllocWithRegistry(allocator, &file, &registry, &decoded, .{});
    defer allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"[demo.dynamicms.ext]\":") != null);
    var json_roundtrip = try pbz.parseJsonAllocWithRegistry(allocator, &file, &registry, host_desc, json, .{});
    defer json_roundtrip.deinit();
    try std.testing.expectEqual(@as(i32, 7), json_roundtrip.get("ext").?.values.items[0].message.get("value").?.values.items[0].int32);

    const text = try pbz.formatTextAllocWithRegistry(allocator, &file, &registry, &decoded, .{});
    defer allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "[demo.dynamicms.ext] {") != null);
    var text_roundtrip = try pbz.parseTextAllocWithRegistry(allocator, &file, &registry, host_desc, text);
    defer text_roundtrip.deinit();
    try std.testing.expectEqual(@as(i32, 7), text_roundtrip.get("ext").?.values.items[0].message.get("value").?.values.items[0].int32);

    // Dynamic MessageSet decoding accepts the historical payload-before-type-id
    // ordering used by some old encoders.
    var reordered = pbz.Writer.init(allocator);
    defer reordered.deinit();
    try reordered.writeTag(1, .start_group);
    try reordered.writeMessage(3, &.{ 0x08, 0x09 });
    try reordered.writeUInt32(2, 100);
    try reordered.writeTag(1, .end_group);
    var reordered_decoded = pbz.DynamicMessage.init(allocator, host_desc);
    defer reordered_decoded.deinit();
    try reordered_decoded.decodeWithRegistry(&file, &registry, reordered.slice());
    try std.testing.expectEqual(@as(i32, 9), reordered_decoded.get("ext").?.values.items[0].message.get("value").?.values.items[0].int32);

    // Unknown MessageSet items are preserved as exact payload-bearing unknown
    // fields and re-emitted with the MessageSet item wrapper.
    var unknown = pbz.Writer.init(allocator);
    defer unknown.deinit();
    try writeMessageSetItem(&unknown, 150, &.{ 0x08, 0x2a });
    var unknown_decoded = pbz.DynamicMessage.init(allocator, host_desc);
    defer unknown_decoded.deinit();
    try unknown_decoded.decodeWithRegistry(&file, &registry, unknown.slice());
    try std.testing.expectEqual(@as(usize, 1), unknown_decoded.unknownCount());
    try std.testing.expectEqual(@as(pbz.FieldNumber, 150), unknown_decoded.unknownFields()[0].number);
    const unknown_roundtrip = try unknown_decoded.encoded(&file);
    defer allocator.free(unknown_roundtrip);
    try std.testing.expectEqualSlices(u8, unknown.slice(), unknown_roundtrip);
}

fn writeMessageSetItem(writer: *pbz.Writer, type_id: pbz.FieldNumber, payload: []const u8) !void {
    try writer.writeTag(1, .start_group);
    try writer.writeUInt32(2, @intCast(type_id));
    try writer.writeMessage(3, payload);
    try writer.writeTag(1, .end_group);
}

comptime {
    _ = pbz;
}
