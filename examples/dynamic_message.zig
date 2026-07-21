const std = @import("std");
const pbz = @import("pbz");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var file = try pbz.ProtoParser.parse(allocator,
        \\syntax = "proto3";
        \\message Event {
        \\  int32 id = 1;
        \\  repeated string tags = 2;
        \\  map<string, int32> counts = 3;
        \\  oneof payload { string note = 4; bytes raw = 5; }
        \\}
    );
    defer file.deinit();

    const event_desc = file.findMessage("Event").?;
    var event = pbz.DynamicMessage.init(allocator, event_desc);
    defer event.deinit();

    try event.add(event_desc.findField("id").?, .{ .int32 = 7 });
    try event.add(event_desc.findField("tags").?, .{ .string = try allocator.dupe(u8, "zig") });
    try event.add(event_desc.findField("note").?, .{ .string = try allocator.dupe(u8, "hello") });

    const first_count = try allocator.create(pbz.dynamic.MapEntry);
    first_count.* = .{
        .key = .{ .string = try allocator.dupe(u8, "red") },
        .value = .{ .int32 = 1 },
    };
    try event.add(event_desc.findField("counts").?, .{ .map_entry = first_count });

    // Adding the same key replaces the previous value (last value wins).
    const replacement_count = try allocator.create(pbz.dynamic.MapEntry);
    replacement_count.* = .{
        .key = .{ .string = try allocator.dupe(u8, "red") },
        .value = .{ .int32 = 9 },
    };
    try event.add(event_desc.findField("counts").?, .{ .map_entry = replacement_count });
    std.debug.assert(event.get("counts").?.values.items.len == 1);
    std.debug.assert(event.get("counts").?.values.items[0].map_entry.value.int32 == 9);
    const red_key = try allocator.dupe(u8, "red");
    defer allocator.free(red_key);
    std.debug.assert(event.getMapValueByName("counts", .{ .string = red_key }).?.int32 == 9);
    std.debug.assert(event.clearMapEntryByName("counts", .{ .string = red_key }));
    std.debug.assert(event.get("counts") == null);
    const restored_count = try allocator.create(pbz.dynamic.MapEntry);
    restored_count.* = .{
        .key = .{ .string = try allocator.dupe(u8, "red") },
        .value = .{ .int32 = 9 },
    };
    try event.add(event_desc.findField("counts").?, .{ .map_entry = restored_count });
    std.debug.assert(event.clearFieldByName("tags"));
    std.debug.assert(event.get("tags") == null);
    try event.add(event_desc.findField("tags").?, .{ .string = try allocator.dupe(u8, "zig") });
    std.debug.assert(event.clearField(event_desc.findField("id").?));
    std.debug.assert(!event.has(event_desc.findField("id").?));
    try event.add(event_desc.findField("id").?, .{ .int32 = 7 });
    std.debug.assert(!event.clearFieldByName("missing"));
    std.debug.assert(event.hasOneof("payload"));
    std.debug.assert(event.clearOneof("payload"));
    std.debug.assert(!event.hasOneof("payload"));
    std.debug.assert(event.whichOneof("payload") == null);
    try event.add(event_desc.findField("note").?, .{ .string = try allocator.dupe(u8, "hello") });
    std.debug.assert(!event.clearOneof("missing"));

    const encoded = try event.encodedDeterministic(&file);
    defer allocator.free(encoded);

    var decoded = pbz.DynamicMessage.init(allocator, event_desc);
    defer decoded.deinit();
    try decoded.decode(&file, encoded);
    std.debug.assert(decoded.has(event_desc.findField("id").?));

    // decode() is a reuse-friendly entry point, but semantically it clears the
    // destination first: fields absent from the new payload should disappear
    // rather than lingering as empty FieldValue entries.
    var id_only = pbz.Writer.init(allocator);
    defer id_only.deinit();
    try id_only.writeInt32(1, 8);
    try decoded.decode(&file, id_only.slice());
    std.debug.assert(decoded.get("id").?.values.items[0].int32 == 8);
    std.debug.assert(decoded.get("tags") == null);
    std.debug.assert(decoded.get("counts") == null);
    std.debug.assert(decoded.get("note") == null);

    var with_unknown = pbz.Writer.init(allocator);
    defer with_unknown.deinit();
    try with_unknown.appendSlice(encoded);
    try with_unknown.writeUInt32(100, 1);
    try with_unknown.writeString(101, "diagnostic");
    try with_unknown.writeUInt32(100, 2);

    var decoded_with_unknown = pbz.DynamicMessage.init(allocator, event_desc);
    defer decoded_with_unknown.deinit();
    try decoded_with_unknown.decode(&file, with_unknown.slice());

    // Dynamic messages already store parsed unknown-field numbers, so callers
    // that repeatedly inspect telemetry/diagnostic extensions can build compact
    // query sidecars without re-decoding raw tags.
    const unknown_numbers = try decoded_with_unknown.unknownFieldNumbersAlloc(allocator);
    defer allocator.free(unknown_numbers);
    std.debug.assert(pbz.wire.rawFieldNumberCount(unknown_numbers, 100) == 2);
    const unknown_runs = try decoded_with_unknown.unknownFieldNumberRunsAlloc(allocator);
    defer allocator.free(unknown_runs);
    std.debug.assert(pbz.wire.rawFieldNumberRunCount(unknown_runs, 100) == 2);

    // Dynamic messages also expose mutation helpers over exact raw unknown
    // fields. This mirrors generated-message unknown APIs while keeping the
    // dynamic representation's parsed number/wire-type sidecar available for
    // fast by-number queries.
    var appended = pbz.Writer.init(allocator);
    defer appended.deinit();
    try appended.writeUInt32(102, 9);
    try decoded_with_unknown.appendUnknownRaw(appended.slice());
    std.debug.assert(decoded_with_unknown.hasUnknownFieldNumber(102));
    std.debug.assert(decoded_with_unknown.unknownFieldCountByNumber(102) == 1);
    const unknown_102 = decoded_with_unknown.unknownByNumber(102);
    std.debug.assert(unknown_102.len == 1);
    std.debug.assert(std.mem.eql(u8, unknown_102[0].data, appended.slice()));
    const unknown_100_owned = try decoded_with_unknown.unknownByNumberAlloc(allocator, 100);
    defer allocator.free(unknown_100_owned);
    std.debug.assert(unknown_100_owned.len == 2);

    decoded_with_unknown.clearUnknownFieldsByNumber(100);
    std.debug.assert(!decoded_with_unknown.hasUnknownFieldNumber(100));
    std.debug.assert(decoded_with_unknown.hasUnknownFieldNumber(101));
    decoded_with_unknown.clearUnknownFields();
    std.debug.assert(decoded_with_unknown.unknownCount() == 0);

    var invalid_raw = pbz.Writer.init(allocator);
    defer invalid_raw.deinit();
    try invalid_raw.writeTag(1, .end_group);
    try std.testing.expectError(error.UnsupportedWireType, decoded_with_unknown.appendUnknownRaw(invalid_raw.slice()));
}
