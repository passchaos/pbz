pub const std = @import("std");
pub const pbz = @import("pbz");
pub const person_pb = @import("person_pb");
pub const root = @import("pbz_bench.zig");

pub fn makeGeneratedPerson(allocator: std.mem.Allocator) !person_pb.demo.Person {
    var person = person_pb.demo.Person.init();
    errdefer person.deinit(allocator);
    person.id = 7;
    person.name = "Zig";
    person.scores = try allocator.dupe(i32, &.{ 10, 20, 30, 40, 50, 60, 70, 80 });
    try person.counts.put(allocator, "red", 1);
    try person.counts.put(allocator, "green", 2);
    try person.counts.put(allocator, "blue", 3);
    return person;
}

pub fn makeUnknownFieldPayload(allocator: std.mem.Allocator, base: []const u8, count: usize) ![]u8 {
    var writer = pbz.Writer.init(allocator);
    errdefer writer.deinit();
    try writer.appendSlice(base);
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const number: pbz.FieldNumber = @intCast(root.UnknownFieldStressFirstNumber + (i % root.UnknownFieldStressNumberSpan));
        try writer.writeUInt32(number, @intCast(i + 1));
    }
    return try writer.toOwnedSlice();
}

pub fn makeDynamicPerson(allocator: std.mem.Allocator, desc: *const pbz.MessageDescriptor) !pbz.DynamicMessage {
    var msg = pbz.DynamicMessage.init(allocator, desc);
    errdefer msg.deinit();
    try msg.add(desc.findField("id").?, .{ .int32 = 7 });
    try msg.add(desc.findField("name").?, .{ .string = try allocator.dupe(u8, "Zig") });
    for ([_]i32{ 10, 20, 30, 40, 50, 60, 70, 80 }) |score| try msg.add(desc.findField("scores").?, .{ .int32 = score });
    inline for (.{ .{ "red", 1 }, .{ "green", 2 }, .{ "blue", 3 } }) |entry_data| {
        const entry = try allocator.create(pbz.dynamic.MapEntry);
        entry.* = .{ .key = .{ .string = try allocator.dupe(u8, entry_data[0]) }, .value = .{ .int32 = entry_data[1] } };
        try msg.add(desc.findField("counts").?, .{ .map_entry = entry });
    }
    return msg;
}

pub fn makeGeneratedScalarMix(allocator: std.mem.Allocator) !person_pb.demo.ScalarMix {
    var msg = person_pb.demo.ScalarMix.init();
    errdefer msg.deinit(allocator);
    msg.active = true;
    msg.count = 12345;
    msg.total = 9_876_543_210;
    msg.delta = -321;
    msg.big_delta = -9_876_543;
    msg.checksum = 0xdead_beef;
    msg.token = 0x0102_0304_0506_0708;
    msg.signed_fixed = -123456;
    msg.signed_big_fixed = -9_876_543_210;
    msg.ratio = 1.25;
    msg.score = 9.5;
    msg.kind = person_pb.demo.BenchKind.BENCH_KIND_BETA.toInt();
    msg.flags = try allocator.dupe(bool, &.{ true, false, true, true, false, true, false, false });
    msg.ids = try allocator.dupe(u64, &.{ 1, 127, 128, 16_384, 1_048_576, 9_876_543_210 });
    return msg;
}

pub fn makeGeneratedTextBytes(allocator: std.mem.Allocator) !person_pb.demo.TextBytes {
    var msg = person_pb.demo.TextBytes.init();
    errdefer msg.deinit(allocator);
    msg.title = "ASCII title for protobuf";
    msg.payload = "0123456789abcdef0123456789abcdef";
    msg.tags = try allocator.dupe([]const u8, &.{ "alpha", "beta", "gamma", "delta" });
    msg.chunks = try allocator.dupe([]const u8, &.{ "chunk-one", "chunk-two", "chunk-three", "chunk-four" });
    return msg;
}

pub fn makeGeneratedLargeBytes(allocator: std.mem.Allocator) !person_pb.demo.LargeBytes {
    var msg = person_pb.demo.LargeBytes.init();
    errdefer msg.deinit(allocator);
    const payload = try allocator.alloc(u8, root.LargeBytesPayloadLen);
    for (payload, 0..) |*byte, i| byte.* = @intCast((i * 31 + 7) & 0xff);
    msg.payload = payload;
    const chunks = try allocator.alloc([]const u8, root.LargeBytesChunkCount);
    errdefer allocator.free(chunks);
    for (chunks, 0..) |*chunk, chunk_index| {
        const data = try allocator.alloc(u8, root.LargeBytesChunkLen);
        for (data, 0..) |*byte, i| byte.* = @intCast((chunk_index * 17 + i * 13 + 3) & 0xff);
        chunk.* = data;
    }
    msg.chunks = chunks;
    return msg;
}

pub fn presenceChild(id: i32, label: []const u8) person_pb.demo.PresenceMix.Child {
    var child = person_pb.demo.PresenceMix.Child.init();
    child.id = id;
    child.label = label;
    return child;
}

pub fn makeGeneratedPresenceMix(allocator: std.mem.Allocator) !person_pb.demo.PresenceMix {
    var msg = person_pb.demo.PresenceMix.init();
    errdefer msg.deinit(allocator);
    msg.count = 0;
    msg.has_count = true;
    msg.note = "";
    msg.has_note = true;
    msg.raw = "presence-raw";
    msg.has_raw = true;
    msg.child = try presenceChild(7, "child").cloneOwned(allocator);
    msg.pick = .{ .nested = try presenceChild(11, "nested").cloneOwned(allocator) };
    return msg;
}

pub fn audit(actor: []const u8, at_unix: i64) person_pb.demo.Complex.Audit {
    var out = person_pb.demo.Complex.Audit.init();
    out.actor = actor;
    out.at_unix = at_unix;
    return out;
}

pub fn makeGeneratedComplex(allocator: std.mem.Allocator) !person_pb.demo.Complex {
    var complex = person_pb.demo.Complex.init();
    errdefer complex.deinit(allocator);
    complex.id = 42;
    complex.audit = try audit("tester", 12345).cloneOwned(allocator);
    const history = try allocator.alloc(person_pb.demo.Complex.Audit, 2);
    history[0] = try audit("creator", 12345).cloneOwned(allocator);
    history[1] = try audit("reviewer", 67890).cloneOwned(allocator);
    complex.history = history;
    try complex.audits.put(allocator, "latest", try audit("reviewer", 67890).cloneOwned(allocator));
    try complex.audits.put(allocator, "created", try audit("creator", 12345).cloneOwned(allocator));
    complex.subject = .{ .audit_subject = try audit("subject", 777).cloneOwned(allocator) };
    return complex;
}

pub fn makeGeneratedPacked(allocator: std.mem.Allocator) !person_pb.demo.Packed {
    var packed_msg = person_pb.demo.Packed.init();
    errdefer packed_msg.deinit(allocator);
    const values = try allocator.alloc(i32, 1024);
    for (values, 0..) |*value, i| value.* = @intCast(i % 4096);
    packed_msg.values = values;
    return packed_msg;
}

pub fn makeDynamicPacked(allocator: std.mem.Allocator, desc: *const pbz.MessageDescriptor) !pbz.DynamicMessage {
    var msg = pbz.DynamicMessage.init(allocator, desc);
    errdefer msg.deinit();
    var i: usize = 0;
    while (i < 1024) : (i += 1) try msg.add(desc.findField("values").?, .{ .int32 = @intCast(i % 4096) });
    return msg;
}

pub fn makeGeneratedFixedPacked(allocator: std.mem.Allocator) !person_pb.demo.FixedPacked {
    var packed_msg = person_pb.demo.FixedPacked.init();
    errdefer packed_msg.deinit(allocator);
    const values = try allocator.alloc(u32, 1024);
    for (values, 0..) |*value, i| value.* = @intCast(i * 3 + 1);
    packed_msg.values = values;
    return packed_msg;
}

pub fn makeGeneratedFixed64Packed(allocator: std.mem.Allocator) !person_pb.demo.Fixed64Packed {
    var packed_msg = person_pb.demo.Fixed64Packed.init();
    errdefer packed_msg.deinit(allocator);
    const values = try allocator.alloc(u64, 1024);
    for (values, 0..) |*value, i| value.* = @intCast(i * 5 + 1);
    packed_msg.values = values;
    return packed_msg;
}

pub fn makeGeneratedSFixedPacked(allocator: std.mem.Allocator) !person_pb.demo.SFixedPacked {
    var packed_msg = person_pb.demo.SFixedPacked.init();
    errdefer packed_msg.deinit(allocator);
    const values = try allocator.alloc(i32, 1024);
    for (values, 0..) |*value, i| {
        const magnitude: i32 = @intCast(i * 7 + 1);
        value.* = if ((i & 1) == 0) magnitude else -magnitude;
    }
    packed_msg.values = values;
    return packed_msg;
}

pub fn makeGeneratedSFixed64Packed(allocator: std.mem.Allocator) !person_pb.demo.SFixed64Packed {
    var packed_msg = person_pb.demo.SFixed64Packed.init();
    errdefer packed_msg.deinit(allocator);
    const values = try allocator.alloc(i64, 1024);
    for (values, 0..) |*value, i| {
        const magnitude: i64 = @intCast((@as(u64, i) << 20) + i * 11 + 1);
        value.* = if ((i & 1) == 0) magnitude else -magnitude;
    }
    packed_msg.values = values;
    return packed_msg;
}

pub fn makeGeneratedFloatPacked(allocator: std.mem.Allocator) !person_pb.demo.FloatPacked {
    var packed_msg = person_pb.demo.FloatPacked.init();
    errdefer packed_msg.deinit(allocator);
    const values = try allocator.alloc(f32, 1024);
    for (values, 0..) |*value, i| value.* = @as(f32, @floatFromInt(i)) * 0.25 + 1.0;
    packed_msg.values = values;
    return packed_msg;
}

pub fn makeGeneratedDoublePacked(allocator: std.mem.Allocator) !person_pb.demo.DoublePacked {
    var packed_msg = person_pb.demo.DoublePacked.init();
    errdefer packed_msg.deinit(allocator);
    const values = try allocator.alloc(f64, 1024);
    for (values, 0..) |*value, i| value.* = @as(f64, @floatFromInt(i)) * 0.5 + 1.0;
    packed_msg.values = values;
    return packed_msg;
}

pub fn makeGeneratedUInt64Packed(allocator: std.mem.Allocator) !person_pb.demo.UInt64Packed {
    var packed_msg = person_pb.demo.UInt64Packed.init();
    errdefer packed_msg.deinit(allocator);
    const values = try allocator.alloc(u64, 1024);
    for (values, 0..) |*value, i| value.* = @intCast((@as(u64, i) << 21) + i * 17 + 1);
    packed_msg.values = values;
    return packed_msg;
}

pub fn makeGeneratedUInt32Packed(allocator: std.mem.Allocator) !person_pb.demo.UInt32Packed {
    var packed_msg = person_pb.demo.UInt32Packed.init();
    errdefer packed_msg.deinit(allocator);
    const values = try allocator.alloc(u32, 1024);
    for (values, 0..) |*value, i| value.* = @intCast((i << 12) + i * 3 + 1);
    packed_msg.values = values;
    return packed_msg;
}

pub fn makeGeneratedInt64Packed(allocator: std.mem.Allocator) !person_pb.demo.Int64Packed {
    var packed_msg = person_pb.demo.Int64Packed.init();
    errdefer packed_msg.deinit(allocator);
    const values = try allocator.alloc(i64, 1024);
    for (values, 0..) |*value, i| {
        const magnitude: i64 = @intCast((@as(u64, i) << 20) + i * 7 + 1);
        value.* = if ((i & 1) == 0) magnitude else -magnitude;
    }
    packed_msg.values = values;
    return packed_msg;
}

pub fn makeGeneratedSInt32Packed(allocator: std.mem.Allocator) !person_pb.demo.SInt32Packed {
    var packed_msg = person_pb.demo.SInt32Packed.init();
    errdefer packed_msg.deinit(allocator);
    const values = try allocator.alloc(i32, 1024);
    for (values, 0..) |*value, i| {
        const magnitude: i32 = @intCast(i * 5 + 1);
        value.* = if ((i & 1) == 0) magnitude else -magnitude;
    }
    packed_msg.values = values;
    return packed_msg;
}

pub fn makeGeneratedSInt64Packed(allocator: std.mem.Allocator) !person_pb.demo.SInt64Packed {
    var packed_msg = person_pb.demo.SInt64Packed.init();
    errdefer packed_msg.deinit(allocator);
    const values = try allocator.alloc(i64, 1024);
    for (values, 0..) |*value, i| {
        const magnitude: i64 = @intCast((@as(u64, i) << 20) + i * 13 + 1);
        value.* = if ((i & 1) == 0) magnitude else -magnitude;
    }
    packed_msg.values = values;
    return packed_msg;
}

pub fn makeGeneratedBoolPacked(allocator: std.mem.Allocator) !person_pb.demo.BoolPacked {
    var packed_msg = person_pb.demo.BoolPacked.init();
    errdefer packed_msg.deinit(allocator);
    const values = try allocator.alloc(bool, 1024);
    for (values, 0..) |*value, i| value.* = (i % 3) != 0;
    packed_msg.values = values;
    return packed_msg;
}

pub fn makeGeneratedEnumPacked(allocator: std.mem.Allocator) !person_pb.demo.EnumPacked {
    var packed_msg = person_pb.demo.EnumPacked.init();
    errdefer packed_msg.deinit(allocator);
    const values = try allocator.alloc(i32, 1024);
    for (values, 0..) |*value, i| value.* = @intCast(i % 3);
    packed_msg.values = values;
    return packed_msg;
}

pub fn makeGeneratedLargeMap(allocator: std.mem.Allocator) !person_pb.demo.LargeMap {
    var msg = person_pb.demo.LargeMap.init();
    errdefer msg.deinit(allocator);
    try msg.counts.ensureTotalCapacity(allocator, root.LargeMapEntryCount);
    var key_buf: [32]u8 = undefined;
    var i: usize = 0;
    while (i < root.LargeMapEntryCount) : (i += 1) {
        const key = try std.fmt.bufPrint(&key_buf, "key-{d:0>4}", .{i});
        try msg.counts.put(allocator, try allocator.dupe(u8, key), @intCast((i % 4096) + 1));
    }
    return msg;
}

pub fn shuffledLargeMapIndex(i: usize) usize {
    return (i * root.LargeMapShuffleMultiplier + root.LargeMapShuffleIncrement) % root.LargeMapEntryCount;
}

pub fn makeGeneratedShuffledLargeMap(allocator: std.mem.Allocator) !person_pb.demo.LargeMap {
    var msg = person_pb.demo.LargeMap.init();
    errdefer msg.deinit(allocator);
    try msg.counts.ensureTotalCapacity(allocator, root.LargeMapEntryCount);
    var key_buf: [32]u8 = undefined;
    var i: usize = 0;
    while (i < root.LargeMapEntryCount) : (i += 1) {
        const key_index = shuffledLargeMapIndex(i);
        const key = try std.fmt.bufPrint(&key_buf, "key-{d:0>4}", .{key_index});
        try msg.counts.put(allocator, try allocator.dupe(u8, key), @intCast((key_index % 4096) + 1));
    }
    return msg;
}

pub fn makeDynamicFixedPacked(allocator: std.mem.Allocator, desc: *const pbz.MessageDescriptor) !pbz.DynamicMessage {
    var msg = pbz.DynamicMessage.init(allocator, desc);
    errdefer msg.deinit();
    var i: usize = 0;
    while (i < 1024) : (i += 1) try msg.add(desc.findField("values").?, .{ .fixed32 = @intCast(i * 3 + 1) });
    return msg;
}

pub fn makeDynamicFixed64Packed(allocator: std.mem.Allocator, desc: *const pbz.MessageDescriptor) !pbz.DynamicMessage {
    var msg = pbz.DynamicMessage.init(allocator, desc);
    errdefer msg.deinit();
    var i: usize = 0;
    while (i < 1024) : (i += 1) try msg.add(desc.findField("values").?, .{ .fixed64 = @intCast(i * 5 + 1) });
    return msg;
}

pub fn makeDynamicSFixedPacked(allocator: std.mem.Allocator, desc: *const pbz.MessageDescriptor) !pbz.DynamicMessage {
    var msg = pbz.DynamicMessage.init(allocator, desc);
    errdefer msg.deinit();
    var i: usize = 0;
    while (i < 1024) : (i += 1) {
        const magnitude: i32 = @intCast(i * 7 + 1);
        try msg.add(desc.findField("values").?, .{ .sfixed32 = if ((i & 1) == 0) magnitude else -magnitude });
    }
    return msg;
}

pub fn makeDynamicSFixed64Packed(allocator: std.mem.Allocator, desc: *const pbz.MessageDescriptor) !pbz.DynamicMessage {
    var msg = pbz.DynamicMessage.init(allocator, desc);
    errdefer msg.deinit();
    var i: usize = 0;
    while (i < 1024) : (i += 1) {
        const magnitude: i64 = @intCast((@as(u64, i) << 20) + i * 11 + 1);
        try msg.add(desc.findField("values").?, .{ .sfixed64 = if ((i & 1) == 0) magnitude else -magnitude });
    }
    return msg;
}

pub fn makeDynamicFloatPacked(allocator: std.mem.Allocator, desc: *const pbz.MessageDescriptor) !pbz.DynamicMessage {
    var msg = pbz.DynamicMessage.init(allocator, desc);
    errdefer msg.deinit();
    var i: usize = 0;
    while (i < 1024) : (i += 1) try msg.add(desc.findField("values").?, .{ .float = @as(f32, @floatFromInt(i)) * 0.25 + 1.0 });
    return msg;
}

pub fn makeDynamicDoublePacked(allocator: std.mem.Allocator, desc: *const pbz.MessageDescriptor) !pbz.DynamicMessage {
    var msg = pbz.DynamicMessage.init(allocator, desc);
    errdefer msg.deinit();
    var i: usize = 0;
    while (i < 1024) : (i += 1) try msg.add(desc.findField("values").?, .{ .double = @as(f64, @floatFromInt(i)) * 0.5 + 1.0 });
    return msg;
}

pub fn makeDynamicUInt64Packed(allocator: std.mem.Allocator, desc: *const pbz.MessageDescriptor) !pbz.DynamicMessage {
    var msg = pbz.DynamicMessage.init(allocator, desc);
    errdefer msg.deinit();
    var i: usize = 0;
    while (i < 1024) : (i += 1) try msg.add(desc.findField("values").?, .{ .uint64 = @intCast((@as(u64, i) << 21) + i * 17 + 1) });
    return msg;
}

pub fn makeDynamicUInt32Packed(allocator: std.mem.Allocator, desc: *const pbz.MessageDescriptor) !pbz.DynamicMessage {
    var msg = pbz.DynamicMessage.init(allocator, desc);
    errdefer msg.deinit();
    var i: usize = 0;
    while (i < 1024) : (i += 1) try msg.add(desc.findField("values").?, .{ .uint32 = @intCast((i << 12) + i * 3 + 1) });
    return msg;
}

pub fn makeDynamicInt64Packed(allocator: std.mem.Allocator, desc: *const pbz.MessageDescriptor) !pbz.DynamicMessage {
    var msg = pbz.DynamicMessage.init(allocator, desc);
    errdefer msg.deinit();
    var i: usize = 0;
    while (i < 1024) : (i += 1) {
        const magnitude: i64 = @intCast((@as(u64, i) << 20) + i * 7 + 1);
        try msg.add(desc.findField("values").?, .{ .int64 = if ((i & 1) == 0) magnitude else -magnitude });
    }
    return msg;
}

pub fn makeDynamicSInt32Packed(allocator: std.mem.Allocator, desc: *const pbz.MessageDescriptor) !pbz.DynamicMessage {
    var msg = pbz.DynamicMessage.init(allocator, desc);
    errdefer msg.deinit();
    var i: usize = 0;
    while (i < 1024) : (i += 1) {
        const magnitude: i32 = @intCast(i * 5 + 1);
        try msg.add(desc.findField("values").?, .{ .sint32 = if ((i & 1) == 0) magnitude else -magnitude });
    }
    return msg;
}

pub fn makeDynamicSInt64Packed(allocator: std.mem.Allocator, desc: *const pbz.MessageDescriptor) !pbz.DynamicMessage {
    var msg = pbz.DynamicMessage.init(allocator, desc);
    errdefer msg.deinit();
    var i: usize = 0;
    while (i < 1024) : (i += 1) {
        const magnitude: i64 = @intCast((@as(u64, i) << 20) + i * 13 + 1);
        try msg.add(desc.findField("values").?, .{ .sint64 = if ((i & 1) == 0) magnitude else -magnitude });
    }
    return msg;
}

pub fn makeDynamicBoolPacked(allocator: std.mem.Allocator, desc: *const pbz.MessageDescriptor) !pbz.DynamicMessage {
    var msg = pbz.DynamicMessage.init(allocator, desc);
    errdefer msg.deinit();
    var i: usize = 0;
    while (i < 1024) : (i += 1) try msg.add(desc.findField("values").?, .{ .boolean = (i % 3) != 0 });
    return msg;
}

pub fn makeDynamicEnumPacked(allocator: std.mem.Allocator, desc: *const pbz.MessageDescriptor) !pbz.DynamicMessage {
    var msg = pbz.DynamicMessage.init(allocator, desc);
    errdefer msg.deinit();
    var i: usize = 0;
    while (i < 1024) : (i += 1) try msg.add(desc.findField("values").?, .{ .enumeration = @intCast(i % 3) });
    return msg;
}

pub fn makeDynamicLargeMap(allocator: std.mem.Allocator, desc: *const pbz.MessageDescriptor) !pbz.DynamicMessage {
    var msg = pbz.DynamicMessage.init(allocator, desc);
    errdefer msg.deinit();
    var key_buf: [32]u8 = undefined;
    var i: usize = 0;
    while (i < root.LargeMapEntryCount) : (i += 1) {
        const key = try std.fmt.bufPrint(&key_buf, "key-{d:0>4}", .{i});
        const entry = try allocator.create(pbz.dynamic.MapEntry);
        entry.* = .{ .key = .{ .string = try allocator.dupe(u8, key) }, .value = .{ .int32 = @intCast((i % 4096) + 1) } };
        try msg.add(desc.findField("counts").?, .{ .map_entry = entry });
    }
    return msg;
}
