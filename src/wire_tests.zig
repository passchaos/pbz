const std = @import("std");
const module = @import("wire.zig");
const FieldNumber = module.FieldNumber;
const RawFieldNumberRun = module.RawFieldNumberRun;
const Reader = module.Reader;
const WireType = module.WireType;
const Writer = module.Writer;
const appendConsumedRawField = module.appendConsumedRawField;
const appendOwnedRawField = module.appendOwnedRawField;
const appendPackedDouble = module.appendPackedDouble;
const appendPackedFixed64 = module.appendPackedFixed64;
const appendPackedFloat = module.appendPackedFloat;
const appendPackedInt64 = module.appendPackedInt64;
const appendPackedSFixed32 = module.appendPackedSFixed32;
const appendPackedSInt32 = module.appendPackedSInt32;
const appendPackedUInt32 = module.appendPackedUInt32;
const appendRawFieldClone = module.appendRawFieldClone;
const appendRawFieldsClone = module.appendRawFieldsClone;
const appendRawVarintPayload = module.appendRawVarintPayload;
const appendSkippedRawField = module.appendSkippedRawField;
const bytesFieldView = module.bytesFieldView;
const bytesLessThan = module.bytesLessThan;
const clearRawFields = module.clearRawFields;
const clearRawFieldsByNumber = module.clearRawFieldsByNumber;
const cloneRawFields = module.cloneRawFields;
const deinitRawFieldList = module.deinitRawFieldList;
const freeRawFields = module.freeRawFields;
const lengthDelimitedFieldSlices = module.lengthDelimitedFieldSlices;
const lengthDelimitedFieldSlicesAssumeValid = module.lengthDelimitedFieldSlicesAssumeValid;
const packedBoolFieldSlices = module.packedBoolFieldSlices;
const packedFixed32FieldSlices = module.packedFixed32FieldSlices;
const packedFixed32FieldView = module.packedFixed32FieldView;
const packedFixed32View = module.packedFixed32View;
const packedInt64FieldIterator = module.packedInt64FieldIterator;
const packedSInt32FieldIterator = module.packedSInt32FieldIterator;
const packedUInt32FieldIterator = module.packedUInt32FieldIterator;
const rawFieldCountByNumber = module.rawFieldCountByNumber;
const rawFieldCountByNumberAssumeValid = module.rawFieldCountByNumberAssumeValid;
const rawFieldHasNumberAssumeValid = module.rawFieldHasNumberAssumeValid;
const rawFieldListToOwnedSlice = module.rawFieldListToOwnedSlice;
const rawFieldNumber = module.rawFieldNumber;
const rawFieldNumberCount = module.rawFieldNumberCount;
const rawFieldNumberRunCount = module.rawFieldNumberRunCount;
const rawFieldNumberRunsAlloc = module.rawFieldNumberRunsAlloc;
const rawFieldNumberRunsFromNumbersAlloc = module.rawFieldNumberRunsFromNumbersAlloc;
const rawFieldNumbersAlloc = module.rawFieldNumbersAlloc;
const rawFieldsByNumberAlloc = module.rawFieldsByNumberAlloc;
const rawFieldsByNumberAllocAssumeValid = module.rawFieldsByNumberAllocAssumeValid;
const readInt32At = module.readInt32At;
const readSInt32At = module.readSInt32At;
const readUInt32At = module.readUInt32At;
const readVarintAt = module.readVarintAt;
const writeDirectScalarVarintToSlice = module.writeDirectScalarVarintToSlice;
const writeNegativeInt64VarintToSlice = module.writeNegativeInt64VarintToSlice;
const writePackedFixedWidthPayload = module.writePackedFixedWidthPayload;
const writeRawFieldsDeterministic = module.writeRawFieldsDeterministic;
const writeRawFieldsDeterministicAssumeCapacity = module.writeRawFieldsDeterministicAssumeCapacity;
const writeUInt32VarintToSlice = module.writeUInt32VarintToSlice;
const writeVarintToSlice = module.writeVarintToSlice;
const zigZagEncode32 = module.zigZagEncode32;
const packedVarintPayloadAllSingleByte = module.test_helpers.packedVarintPayloadAllSingleByte;

test "wire encodes and decodes scalar fields" {
    const allocator = std.testing.allocator;
    var writer = Writer.init(allocator);
    defer writer.deinit();

    try writer.writeInt32(1, -2);
    try writer.writeSInt32(2, -2);
    try writer.writeString(3, "zig");
    try writer.writeFixed64(4, 0x0102030405060708);

    var reader = Reader.init(writer.slice());
    var tag = (try reader.nextTag()).?;
    try std.testing.expectEqual(@as(FieldNumber, 1), tag.number);
    try std.testing.expectEqual(WireType.varint, tag.wire_type);
    try std.testing.expectEqual(@as(i32, -2), try reader.readInt32());

    tag = (try reader.nextTag()).?;
    try std.testing.expectEqual(@as(FieldNumber, 2), tag.number);
    try std.testing.expectEqual(@as(i32, -2), try reader.readSInt32());

    tag = (try reader.nextTag()).?;
    try std.testing.expectEqual(@as(FieldNumber, 3), tag.number);
    try std.testing.expectEqualSlices(u8, "zig", try reader.readBytes());

    tag = (try reader.nextTag()).?;
    try std.testing.expectEqual(@as(FieldNumber, 4), tag.number);
    try std.testing.expectEqual(@as(u64, 0x0102030405060708), try reader.readFixed64());
    try std.testing.expect(reader.eof());
}

test "wire varint writer covers all encoded lengths" {
    const Case = struct {
        value: u64,
        bytes: []const u8,
    };
    const cases = [_]Case{
        .{ .value = 0, .bytes = &.{0x00} },
        .{ .value = 0x7f, .bytes = &.{0x7f} },
        .{ .value = 0x80, .bytes = &.{ 0x80, 0x01 } },
        .{ .value = 0x3fff, .bytes = &.{ 0xff, 0x7f } },
        .{ .value = 0x4000, .bytes = &.{ 0x80, 0x80, 0x01 } },
        .{ .value = 0x1f_ffff, .bytes = &.{ 0xff, 0xff, 0x7f } },
        .{ .value = 0x20_0000, .bytes = &.{ 0x80, 0x80, 0x80, 0x01 } },
        .{ .value = 0x0fff_ffff, .bytes = &.{ 0xff, 0xff, 0xff, 0x7f } },
        .{ .value = 0x1000_0000, .bytes = &.{ 0x80, 0x80, 0x80, 0x80, 0x01 } },
        .{ .value = 0x0007_ffff_ffff, .bytes = &.{ 0xff, 0xff, 0xff, 0xff, 0x7f } },
        .{ .value = 0x0008_0000_0000, .bytes = &.{ 0x80, 0x80, 0x80, 0x80, 0x80, 0x01 } },
        .{ .value = 0x03ff_ffff_ffff, .bytes = &.{ 0xff, 0xff, 0xff, 0xff, 0xff, 0x7f } },
        .{ .value = 0x0400_0000_0000, .bytes = &.{ 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x01 } },
        .{ .value = 0x0001_ffff_ffff_ffff, .bytes = &.{ 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x7f } },
        .{ .value = 0x0002_0000_0000_0000, .bytes = &.{ 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x01 } },
        .{ .value = 0x00ff_ffff_ffff_ffff, .bytes = &.{ 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x7f } },
        .{ .value = 0x0100_0000_0000_0000, .bytes = &.{ 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x01 } },
        .{ .value = 0x7fff_ffff_ffff_ffff, .bytes = &.{ 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x7f } },
        .{ .value = 0x8000_0000_0000_0000, .bytes = &.{ 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x01 } },
        .{ .value = std.math.maxInt(u64), .bytes = &.{ 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01 } },
    };

    for (cases) |case| {
        var writer = Writer.init(std.testing.allocator);
        defer writer.deinit();
        try writer.writeVarint(case.value);
        try std.testing.expectEqualSlices(u8, case.bytes, writer.slice());

        var index: usize = 0;
        try std.testing.expectEqual(case.value, try readVarintAt(writer.slice(), &index));
        try std.testing.expectEqual(writer.slice().len, index);

        var buffer: [10]u8 = undefined;
        var direct_index: usize = 0;
        writeVarintToSlice(&buffer, &direct_index, case.value);
        try std.testing.expectEqualSlices(u8, case.bytes, buffer[0..direct_index]);

        var direct_scalar_index: usize = 0;
        writeDirectScalarVarintToSlice(&buffer, &direct_scalar_index, case.value);
        try std.testing.expectEqualSlices(u8, case.bytes, buffer[0..direct_scalar_index]);

        if (case.value <= std.math.maxInt(u32)) {
            var u32_index: usize = 0;
            writeUInt32VarintToSlice(&buffer, &u32_index, @intCast(case.value));
            try std.testing.expectEqualSlices(u8, case.bytes, buffer[0..u32_index]);
        }
    }
}

test "wire negative int64 varint writer matches canonical encoding" {
    const cases = [_]i64{ -1, -2, -1234567, std.math.minInt(i64) };

    for (cases) |value| {
        var canonical: [10]u8 = undefined;
        var canonical_index: usize = 0;
        writeVarintToSlice(&canonical, &canonical_index, @bitCast(value));

        var direct: [10]u8 = undefined;
        var direct_index: usize = 0;
        writeNegativeInt64VarintToSlice(&direct, &direct_index, value);

        try std.testing.expectEqual(@as(usize, 10), canonical_index);
        try std.testing.expectEqual(canonical_index, direct_index);
        try std.testing.expectEqualSlices(u8, canonical[0..canonical_index], direct[0..direct_index]);
    }
}

test "wire tag writers preserve single and multi-byte tags" {
    var writer = Writer.init(std.testing.allocator);
    defer writer.deinit();

    try writer.writeTag(15, .fixed32);
    try writer.writeTag(16, .varint);
    try std.testing.expectEqualSlices(u8, &.{ 0x7d, 0x80, 0x01 }, writer.slice());

    var buffer: [3]u8 = undefined;
    var buffered = Writer.initBuffer(std.testing.allocator, &buffer);
    buffered.writeTagAssumeCapacity(15, .fixed32);
    buffered.writeTagAssumeCapacity(16, .varint);
    try std.testing.expectEqualSlices(u8, writer.slice(), buffered.slice());

    try std.testing.expectEqual(@as(FieldNumber, 15), try rawFieldNumber(writer.slice()[0..1]));
    try std.testing.expectEqual(@as(FieldNumber, 16), try rawFieldNumber(writer.slice()[1..]));
    try std.testing.expectError(error.InvalidWireType, rawFieldNumber(&.{0x0f}));
    try std.testing.expectError(error.MalformedVarint, rawFieldNumber(&.{ 0x80, 0x80, 0x80, 0x80, 0x80, 0x00 }));

    const noncanonical_field_16 = [_]u8{ 0x80, 0x81, 0x00, 0x01 };
    try std.testing.expectEqual(@as(FieldNumber, 16), try rawFieldNumber(&noncanonical_field_16));
    const noncanonical_field_31 = [_]u8{ 0x78 | 0x80, 0x01, 0x00 };
    try std.testing.expectEqual(@as(FieldNumber, 31), try rawFieldNumber(&noncanonical_field_31));

    const raw_fields = [_][]const u8{ writer.slice()[0..1], &.{}, writer.slice()[1..], &noncanonical_field_16, &noncanonical_field_31 };
    try std.testing.expectEqual(@as(usize, 1), try rawFieldCountByNumber(&raw_fields, 15));
    try std.testing.expectEqual(@as(usize, 1), rawFieldCountByNumberAssumeValid(&raw_fields, 15));
    try std.testing.expectEqual(@as(usize, 2), rawFieldCountByNumberAssumeValid(&raw_fields, 16));
    try std.testing.expectEqual(@as(usize, 1), rawFieldCountByNumberAssumeValid(&raw_fields, 31));
    const noncanonical_only = [_][]const u8{&noncanonical_field_31};
    try std.testing.expectEqual(@as(usize, 0), rawFieldCountByNumberAssumeValid(&noncanonical_only, 15));
    const raw_numbers = try rawFieldNumbersAlloc(std.testing.allocator, &raw_fields);
    defer std.testing.allocator.free(raw_numbers);
    try std.testing.expectEqualSlices(FieldNumber, &.{ 15, 0, 16, 16, 31 }, raw_numbers);
    try std.testing.expectEqual(@as(usize, 2), rawFieldNumberCount(raw_numbers, 16));
    try std.testing.expectEqual(@as(usize, 0), rawFieldNumberCount(raw_numbers, 17));
    const raw_number_runs = try rawFieldNumberRunsAlloc(std.testing.allocator, &raw_fields);
    defer std.testing.allocator.free(raw_number_runs);
    try std.testing.expectEqual(@as(usize, 3), raw_number_runs.len);
    try std.testing.expectEqual(RawFieldNumberRun{ .number = 15, .count = 1 }, raw_number_runs[0]);
    try std.testing.expectEqual(RawFieldNumberRun{ .number = 16, .count = 2 }, raw_number_runs[1]);
    try std.testing.expectEqual(RawFieldNumberRun{ .number = 31, .count = 1 }, raw_number_runs[2]);
    try std.testing.expectEqual(@as(usize, 2), rawFieldNumberRunCount(raw_number_runs, 16));
    try std.testing.expectEqual(@as(usize, 0), rawFieldNumberRunCount(raw_number_runs, 17));

    const sidecar_numbers = [_]FieldNumber{ 31, 0, 16, 16, 15 };
    const sidecar_runs = try rawFieldNumberRunsFromNumbersAlloc(std.testing.allocator, &sidecar_numbers);
    defer std.testing.allocator.free(sidecar_runs);
    try std.testing.expectEqualSlices(FieldNumber, &.{ 31, 0, 16, 16, 15 }, &sidecar_numbers);
    try std.testing.expectEqual(@as(usize, 3), sidecar_runs.len);
    try std.testing.expectEqual(RawFieldNumberRun{ .number = 15, .count = 1 }, sidecar_runs[0]);
    try std.testing.expectEqual(RawFieldNumberRun{ .number = 16, .count = 2 }, sidecar_runs[1]);
    try std.testing.expectEqual(RawFieldNumberRun{ .number = 31, .count = 1 }, sidecar_runs[2]);
    try std.testing.expect(rawFieldHasNumberAssumeValid(&raw_fields, 16));
    try std.testing.expect(!rawFieldHasNumberAssumeValid(&raw_fields, 17));
    const matched = try rawFieldsByNumberAlloc(std.testing.allocator, &raw_fields, 16);
    defer std.testing.allocator.free(matched);
    try std.testing.expectEqual(@as(usize, 2), matched.len);
    try std.testing.expectEqualSlices(u8, writer.slice()[1..], matched[0]);
    try std.testing.expectEqualSlices(u8, &noncanonical_field_16, matched[1]);

    const matched_fast = try rawFieldsByNumberAllocAssumeValid(std.testing.allocator, &raw_fields, 16);
    defer std.testing.allocator.free(matched_fast);
    try std.testing.expectEqual(@as(usize, 2), matched_fast.len);
    try std.testing.expectEqualSlices(u8, writer.slice()[1..], matched_fast[0]);
    try std.testing.expectEqualSlices(u8, &noncanonical_field_16, matched_fast[1]);
}

test "wire clears raw fields by number without reallocating on miss" {
    const allocator = std.testing.allocator;
    var first = Writer.init(allocator);
    defer first.deinit();
    try first.writeUInt32(15, 1);

    var second = Writer.init(allocator);
    defer second.deinit();
    try second.writeString(16, "zig");

    var third = Writer.init(allocator);
    defer third.deinit();
    try third.writeBool(15, false);

    const storage = try allocator.alloc([]const u8, 3);
    @memset(storage, &.{});
    var fields: []const []const u8 = storage;
    defer {
        for (fields) |raw| if (raw.len != 0) allocator.free(raw);
        if (fields.len != 0) allocator.free(fields);
    }
    storage[0] = try allocator.dupe(u8, first.slice());
    storage[1] = try allocator.dupe(u8, second.slice());
    storage[2] = try allocator.dupe(u8, third.slice());

    const before_miss = fields;
    try clearRawFieldsByNumber(allocator, &fields, 99);
    try std.testing.expectEqual(before_miss.ptr, fields.ptr);
    try std.testing.expectEqual(@as(usize, 3), fields.len);

    try clearRawFieldsByNumber(allocator, &fields, 15);
    try std.testing.expectEqual(@as(usize, 1), fields.len);
    try std.testing.expectEqual(@as(FieldNumber, 16), try rawFieldNumber(fields[0]));

    const invalid_storage = try allocator.alloc([]const u8, 1);
    invalid_storage[0] = try allocator.dupe(u8, &.{0x0f});
    var invalid_fields: []const []const u8 = invalid_storage;
    defer {
        for (invalid_fields) |raw| allocator.free(raw);
        if (invalid_fields.len != 0) allocator.free(invalid_fields);
    }
    const before_invalid = invalid_fields;
    try std.testing.expectError(error.InvalidWireType, clearRawFieldsByNumber(allocator, &invalid_fields, 15));
    try std.testing.expectEqual(before_invalid.ptr, invalid_fields.ptr);
    try std.testing.expectEqual(@as(usize, 1), invalid_fields.len);
}

test "wire appends cloned raw fields in batches" {
    const allocator = std.testing.allocator;
    var first = Writer.init(allocator);
    defer first.deinit();
    try first.writeUInt32(15, 1);

    var second = Writer.init(allocator);
    defer second.deinit();
    try second.writeString(16, "zig");

    var fields: []const []const u8 = &.{};
    defer {
        for (fields) |raw| allocator.free(raw);
        if (fields.len != 0) allocator.free(fields);
    }

    try appendRawFieldClone(allocator, &fields, first.slice());
    try std.testing.expectEqual(@as(usize, 1), fields.len);
    try std.testing.expectEqualSlices(u8, first.slice(), fields[0]);

    try appendRawFieldsClone(allocator, &fields, &.{ second.slice(), first.slice() });
    try std.testing.expectEqual(@as(usize, 3), fields.len);
    try std.testing.expectEqualSlices(u8, second.slice(), fields[1]);
    try std.testing.expectEqualSlices(u8, first.slice(), fields[2]);

    const before_invalid = fields;
    try std.testing.expectError(error.InvalidWireType, appendRawFieldsClone(allocator, &fields, &.{&.{0x0f}}));
    try std.testing.expectEqual(before_invalid.ptr, fields.ptr);
    try std.testing.expectEqual(@as(usize, 3), fields.len);
}

test "wire appends consumed raw fields with exact source bytes" {
    const allocator = std.testing.allocator;

    var list: std.ArrayList([]const u8) = .empty;
    defer deinitRawFieldList(allocator, &list);

    // Field 15/varint is canonically one tag byte (0x78), but this non-canonical
    // two-byte tag is still within the five-byte protobuf tag limit. Unknown
    // preservation must copy the original bytes, not a re-encoded canonical tag.
    const noncanonical_tag = [_]u8{ 0xf8, 0x00, 0x01 };
    var reader = Reader.init(&noncanonical_tag);
    const tag = (try reader.nextTag()).?;
    try std.testing.expectEqual(@as(FieldNumber, 15), tag.number);
    try std.testing.expectEqual(@as(usize, 0), reader.lastTagStart());
    try reader.skipValue(tag);
    try appendConsumedRawField(allocator, &list, &reader, reader.lastTagStart());
    try std.testing.expectEqualSlices(u8, &noncanonical_tag, list.items[0]);
    try std.testing.expect(list.capacity >= 4);

    var skipped_reader = Reader.init(&.{ 0xa2, 0x06, 0x03, 'z', 'i', 'g' });
    const skipped = (try skipped_reader.nextTag()).?;
    try appendSkippedRawField(allocator, &list, &skipped_reader, skipped_reader.lastTagStart(), skipped);
    try std.testing.expectEqualSlices(u8, &.{ 0xa2, 0x06, 0x03, 'z', 'i', 'g' }, list.items[1]);
}

test "wire appends canonical raw varint payloads" {
    const allocator = std.testing.allocator;

    var list: std.ArrayList([]const u8) = .empty;
    defer deinitRawFieldList(allocator, &list);

    try appendRawVarintPayload(allocator, &list, 16, &.{ 0x81, 0x01 });
    try std.testing.expectEqualSlices(u8, &.{ 0x80, 0x01, 0x81, 0x01 }, list.items[0]);
}

test "wire clones and clears raw field slices" {
    const allocator = std.testing.allocator;
    var first = Writer.init(allocator);
    defer first.deinit();
    try first.writeUInt32(15, 1);

    var second = Writer.init(allocator);
    defer second.deinit();
    try second.writeString(16, "zig");

    const source = [_][]const u8{ first.slice(), second.slice() };
    var cloned = try cloneRawFields(allocator, &source);
    defer clearRawFields(allocator, &cloned);

    try std.testing.expectEqual(@as(usize, 2), cloned.len);
    try std.testing.expectEqualSlices(u8, source[0], cloned[0]);
    try std.testing.expectEqualSlices(u8, source[1], cloned[1]);
    try std.testing.expect(cloned[0].ptr != source[0].ptr);
    try std.testing.expect(cloned[1].ptr != source[1].ptr);

    clearRawFields(allocator, &cloned);
    try std.testing.expectEqual(@as(usize, 0), cloned.len);

    var list: std.ArrayList([]const u8) = .empty;
    errdefer deinitRawFieldList(allocator, &list);
    try list.append(allocator, try allocator.dupe(u8, first.slice()));
    const owned = try rawFieldListToOwnedSlice(allocator, &list);
    defer freeRawFields(allocator, owned);
    try std.testing.expectEqual(@as(usize, 1), owned.len);
    try std.testing.expectEqualSlices(u8, first.slice(), owned[0]);

    var empty_list: std.ArrayList([]const u8) = .empty;
    const empty = try rawFieldListToOwnedSlice(allocator, &empty_list);
    try std.testing.expectEqual(@as(usize, 0), empty.len);

    var appended_list: std.ArrayList([]const u8) = .empty;
    errdefer deinitRawFieldList(allocator, &appended_list);
    try appendOwnedRawField(allocator, &appended_list, try allocator.dupe(u8, second.slice()));
    const appended = try rawFieldListToOwnedSlice(allocator, &appended_list);
    defer freeRawFields(allocator, appended);
    try std.testing.expectEqual(@as(usize, 1), appended.len);
    try std.testing.expectEqualSlices(u8, second.slice(), appended[0]);
}

test "wire writes deterministic raw fields in generated order" {
    const allocator = std.testing.allocator;
    var field_50_value_2 = Writer.init(allocator);
    defer field_50_value_2.deinit();
    try field_50_value_2.writeUInt32(50, 2);

    var field_40 = Writer.init(allocator);
    defer field_40.deinit();
    try field_40.writeUInt32(40, 1);

    var field_50_bytes = Writer.init(allocator);
    defer field_50_bytes.deinit();
    try field_50_bytes.writeString(50, "a");

    var field_50_value_1 = Writer.init(allocator);
    defer field_50_value_1.deinit();
    try field_50_value_1.writeUInt32(50, 1);

    const fields = [_][]const u8{
        field_50_value_2.slice(),
        field_40.slice(),
        field_50_bytes.slice(),
        field_50_value_1.slice(),
    };

    var expected = Writer.init(allocator);
    defer expected.deinit();
    try expected.appendSlice(field_40.slice());
    try expected.appendSlice(field_50_value_1.slice());
    try expected.appendSlice(field_50_value_2.slice());
    try expected.appendSlice(field_50_bytes.slice());

    var sorted = Writer.init(allocator);
    defer sorted.deinit();
    try writeRawFieldsDeterministic(allocator, &fields, &sorted);
    try std.testing.expectEqualSlices(u8, expected.slice(), sorted.slice());

    var buffer: [64]u8 = undefined;
    var buffered = Writer.initBuffer(allocator, &buffer);
    try writeRawFieldsDeterministicAssumeCapacity(allocator, &fields, &buffered);
    try std.testing.expectEqualSlices(u8, expected.slice(), buffered.slice());
}

test "wire bool writers use canonical one-byte values" {
    var writer = Writer.init(std.testing.allocator);
    defer writer.deinit();
    try writer.writeBool(1, true);
    try writer.writeBool(2, false);
    try std.testing.expectEqualSlices(u8, &.{ 0x08, 0x01, 0x10, 0x00 }, writer.slice());

    var buffer: [4]u8 = undefined;
    var buffered = Writer.initBuffer(std.testing.allocator, &buffer);
    buffered.writeBoolAssumeCapacity(1, true);
    buffered.writeBoolAssumeCapacity(2, false);
    try std.testing.expectEqualSlices(u8, writer.slice(), buffered.slice());
}

test "wire bytes writers preserve short and multi-byte lengths" {
    var small_writer = Writer.init(std.testing.allocator);
    defer small_writer.deinit();
    try small_writer.writeBytes(1, "abc");
    try std.testing.expectEqualSlices(u8, &.{ 0x0a, 0x03, 'a', 'b', 'c' }, small_writer.slice());

    var payload: [128]u8 = undefined;
    for (&payload, 0..) |*byte, i| byte.* = @intCast(i & 0xff);

    var expected = Writer.init(std.testing.allocator);
    defer expected.deinit();
    try expected.writeBytes(1, &payload);
    try std.testing.expectEqual(@as(u8, 0x0a), expected.slice()[0]);
    try std.testing.expectEqual(@as(u8, 0x80), expected.slice()[1]);
    try std.testing.expectEqual(@as(u8, 0x01), expected.slice()[2]);
    try std.testing.expectEqualSlices(u8, &payload, expected.slice()[3..]);

    var buffer: [131]u8 = undefined;
    var buffered = Writer.initBuffer(std.testing.allocator, &buffer);
    buffered.writeBytesAssumeCapacity(1, &payload);
    try std.testing.expectEqualSlices(u8, expected.slice(), buffered.slice());
}

test "wire byte readers preserve short and multi-byte lengths" {
    var short_reader = Reader.init(&.{ 0x03, 'a', 'b', 'c' });
    try std.testing.expectEqualSlices(u8, "abc", try short_reader.readBytes());
    try std.testing.expect(short_reader.eof());

    var payload: [128]u8 = undefined;
    for (&payload, 0..) |*byte, i| byte.* = @intCast((i * 17) & 0xff);

    var encoded: [130]u8 = undefined;
    encoded[0] = 0x80;
    encoded[1] = 0x01;
    @memcpy(encoded[2..], &payload);
    var long_reader = Reader.init(&encoded);
    try std.testing.expectEqualSlices(u8, &payload, try long_reader.readBytes());
    try std.testing.expect(long_reader.eof());
}

test "wire byte less-than helper preserves lexicographic order" {
    const cases = [_]struct {
        lhs: []const u8,
        rhs: []const u8,
    }{
        .{ .lhs = "", .rhs = "a" },
        .{ .lhs = "abc", .rhs = "abc0" },
        .{ .lhs = "abcd", .rhs = "abce" },
        .{ .lhs = "key-0009", .rhs = "key-0010" },
        .{ .lhs = "prefix-00000000-a", .rhs = "prefix-00000000-b" },
        .{ .lhs = "short", .rhs = "shorter" },
        .{ .lhs = "\x00\xff", .rhs = "\x01\x00" },
    };

    for (cases) |case| {
        try std.testing.expect(bytesLessThan(case.lhs, case.rhs));
        try std.testing.expectEqual(std.mem.lessThan(u8, case.lhs, case.rhs), bytesLessThan(case.lhs, case.rhs));
        try std.testing.expectEqual(std.mem.lessThan(u8, case.rhs, case.lhs), bytesLessThan(case.rhs, case.lhs));
        try std.testing.expect(!bytesLessThan(case.lhs, case.lhs));
    }
}

test "wire int32 hot varint readers preserve generic semantics" {
    const IntCase = struct {
        bytes: []const u8,
        value: i32,
    };
    const int_cases = [_]IntCase{
        .{ .bytes = &.{0x00}, .value = 0 },
        .{ .bytes = &.{0x7f}, .value = 127 },
        .{ .bytes = &.{ 0x80, 0x01 }, .value = 128 },
        .{ .bytes = &.{ 0xff, 0x7f }, .value = 16383 },
        .{ .bytes = &.{ 0x80, 0x80, 0x01 }, .value = 16384 },
        // int32 stores negative values in the full 64-bit varint form; the hot
        // reader must still fall back and truncate exactly like Reader.readInt32.
        .{ .bytes = &.{ 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01 }, .value = -1 },
    };

    for (int_cases) |case| {
        var index: usize = 0;
        try std.testing.expectEqual(case.value, try readInt32At(case.bytes, &index));
        try std.testing.expectEqual(case.bytes.len, index);
    }

    const UIntCase = struct {
        bytes: []const u8,
        value: u32,
    };
    const uint_cases = [_]UIntCase{
        .{ .bytes = &.{0x00}, .value = 0 },
        .{ .bytes = &.{0x7f}, .value = 127 },
        .{ .bytes = &.{ 0x80, 0x01 }, .value = 128 },
        .{ .bytes = &.{ 0xff, 0x7f }, .value = 16383 },
        .{ .bytes = &.{ 0x80, 0x80, 0x01 }, .value = 16384 },
        // Wider accepted varints are truncated to the 32-bit field width.
        .{ .bytes = &.{ 0x80, 0x80, 0x80, 0x80, 0x20 }, .value = 0 },
    };

    for (uint_cases) |case| {
        var index: usize = 0;
        try std.testing.expectEqual(case.value, try readUInt32At(case.bytes, &index));
        try std.testing.expectEqual(case.bytes.len, index);
    }

    const SIntCase = struct {
        bytes: []const u8,
        value: i32,
    };
    const sint_cases = [_]SIntCase{
        .{ .bytes = &.{0x00}, .value = 0 },
        .{ .bytes = &.{0x01}, .value = -1 },
        .{ .bytes = &.{ 0x81, 0x01 }, .value = -65 },
        .{ .bytes = &.{ 0x80, 0x80, 0x01 }, .value = 8192 },
        // Protobuf's 32-bit varint readers accept wider varints and truncate
        // to the field width before zig-zag decoding, matching Reader.readSInt32.
        .{ .bytes = &.{ 0x82, 0x80, 0x80, 0x80, 0x10 }, .value = 1 },
    };

    for (sint_cases) |case| {
        var index: usize = 0;
        try std.testing.expectEqual(case.value, try readSInt32At(case.bytes, &index));
        try std.testing.expectEqual(case.bytes.len, index);
    }

    var int_truncated_one_byte_index: usize = 0;
    try std.testing.expectError(error.TruncatedInput, readInt32At(&.{0x80}, &int_truncated_one_byte_index));
    try std.testing.expectEqual(@as(usize, 1), int_truncated_one_byte_index);

    var int_truncated_fallback_index: usize = 0;
    try std.testing.expectError(error.TruncatedInput, readInt32At(&.{ 0x80, 0x80 }, &int_truncated_fallback_index));
    try std.testing.expectEqual(@as(usize, 2), int_truncated_fallback_index);

    var uint_truncated_one_byte_index: usize = 0;
    try std.testing.expectError(error.TruncatedInput, readUInt32At(&.{0x80}, &uint_truncated_one_byte_index));
    try std.testing.expectEqual(@as(usize, 1), uint_truncated_one_byte_index);

    var uint_truncated_fallback_index: usize = 0;
    try std.testing.expectError(error.TruncatedInput, readUInt32At(&.{ 0x80, 0x80 }, &uint_truncated_fallback_index));
    try std.testing.expectEqual(@as(usize, 2), uint_truncated_fallback_index);

    var truncated_one_byte_index: usize = 0;
    try std.testing.expectError(error.TruncatedInput, readSInt32At(&.{0x80}, &truncated_one_byte_index));
    try std.testing.expectEqual(@as(usize, 1), truncated_one_byte_index);

    var truncated_fallback_index: usize = 0;
    try std.testing.expectError(error.TruncatedInput, readSInt32At(&.{ 0x80, 0x80 }, &truncated_fallback_index));
    try std.testing.expectEqual(@as(usize, 2), truncated_fallback_index);
}

test "wire exposes borrowed packed fixed32 view" {
    const payload = &[_]u8{ 1, 0, 0, 0, 4, 3, 2, 1 };
    const values = try packedFixed32View(payload);
    try std.testing.expectEqual(@as(usize, 2), values.len);
    try std.testing.expectEqual(@as(u32, 1), values[0]);
    try std.testing.expectEqual(@as(u32, 0x01020304), values[1]);
    try std.testing.expectEqual(@intFromPtr(payload.ptr), @intFromPtr(std.mem.sliceAsBytes(values).ptr));
    try std.testing.expectError(error.InvalidWireType, packedFixed32View(payload[0..7]));

    var writer = Writer.init(std.testing.allocator);
    defer writer.deinit();
    try writer.writeUInt32(9, 7);
    try writer.writeBytes(1, payload);
    const field_values = (try packedFixed32FieldView(writer.slice(), 1)).?;
    try std.testing.expectEqual(@as(u32, 0x01020304), field_values[1]);
    try std.testing.expect(try packedFixed32FieldView(writer.slice(), 2) == null);

    const aligned_values = [_]u32{ 1, 0x01020304 };
    var header: [20]u8 = undefined;
    const bytes_slices = try lengthDelimitedFieldSlices(&header, 3, "zig");
    try std.testing.expectEqualSlices(u8, &.{ 0x1a, 0x03 }, bytes_slices.header);
    try std.testing.expectEqualSlices(u8, "zig", bytes_slices.payload);

    const trusted_bytes_slices = lengthDelimitedFieldSlicesAssumeValid(&header, 3, "zig");
    try std.testing.expectEqualSlices(u8, bytes_slices.header, trusted_bytes_slices.header);
    try std.testing.expectEqualSlices(u8, bytes_slices.payload, trusted_bytes_slices.payload);

    const slices = try packedFixed32FieldSlices(&header, 1, &aligned_values);
    try std.testing.expectEqualSlices(u8, &.{ 0x0a, 0x08 }, slices.header);
    try std.testing.expectEqual(@intFromPtr(std.mem.sliceAsBytes(&aligned_values).ptr), @intFromPtr(slices.payload.ptr));

    var packed_writer = Writer.init(std.testing.allocator);
    defer packed_writer.deinit();
    try writePackedFixedWidthPayload(u64, &packed_writer, &.{ 1, 0x0102030405060708 });
    try std.testing.expectEqualSlices(u8, &.{ 1, 0, 0, 0, 0, 0, 0, 0, 8, 7, 6, 5, 4, 3, 2, 1 }, packed_writer.slice());

    const bool_values = [_]bool{ true, false, true };
    const bool_slices = try packedBoolFieldSlices(&header, 2, &bool_values);
    try std.testing.expectEqualSlices(u8, &.{ 0x12, 0x03 }, bool_slices.header);
    try std.testing.expectEqual(@intFromPtr(std.mem.sliceAsBytes(&bool_values).ptr), @intFromPtr(bool_slices.payload.ptr));
}

test "wire appends fixed-width packed payloads in bulk" {
    const allocator = std.testing.allocator;

    var u64_list: std.ArrayList(u64) = .empty;
    defer u64_list.deinit(allocator);
    try appendPackedFixed64(allocator, &u64_list, &.{ 1, 0, 0, 0, 0, 0, 0, 0, 8, 7, 6, 5, 4, 3, 2, 1 });
    try std.testing.expectEqualSlices(u64, &.{ 1, 0x0102030405060708 }, u64_list.items);

    var i32_list: std.ArrayList(i32) = .empty;
    defer i32_list.deinit(allocator);
    try appendPackedSFixed32(allocator, &i32_list, &.{ 0xfe, 0xff, 0xff, 0xff, 0x04, 0x03, 0x02, 0x01 });
    try std.testing.expectEqualSlices(i32, &.{ -2, 0x01020304 }, i32_list.items);

    var f32_list: std.ArrayList(f32) = .empty;
    defer f32_list.deinit(allocator);
    try appendPackedFloat(allocator, &f32_list, std.mem.asBytes(&[_]u32{ @bitCast(@as(f32, 1.5)), @bitCast(@as(f32, -2.25)) }));
    try std.testing.expectEqual(@as(f32, 1.5), f32_list.items[0]);
    try std.testing.expectEqual(@as(f32, -2.25), f32_list.items[1]);

    var f64_list: std.ArrayList(f64) = .empty;
    defer f64_list.deinit(allocator);
    try std.testing.expectError(error.InvalidWireType, appendPackedDouble(allocator, &f64_list, &.{ 1, 2, 3 }));
}

test "wire appends and iterates varint packed payloads" {
    const allocator = std.testing.allocator;

    var uint32_payload = Writer.init(allocator);
    defer uint32_payload.deinit();
    try uint32_payload.writeVarint(1);
    try uint32_payload.writeVarint(128);
    try uint32_payload.writeVarint(4097);
    try uint32_payload.writeVarint(@as(u64, 1) << 33);
    try uint32_payload.writeVarint((@as(u64, 1) << 33) + 1);
    try uint32_payload.writeVarint(std.math.maxInt(u64));
    var uint32_list: std.ArrayList(u32) = .empty;
    defer uint32_list.deinit(allocator);
    try appendPackedUInt32(allocator, &uint32_list, uint32_payload.slice());
    try std.testing.expectEqualSlices(u32, &.{ 1, 128, 4097, 0, 1, std.math.maxInt(u32) }, uint32_list.items);

    var int64_payload = Writer.init(allocator);
    defer int64_payload.deinit();
    try int64_payload.writeVarint(@as(u64, @bitCast(@as(i64, -1))));
    try int64_payload.writeVarint(@as(u64, @bitCast(@as(i64, 2))));
    var int64_list: std.ArrayList(i64) = .empty;
    defer int64_list.deinit(allocator);
    try appendPackedInt64(allocator, &int64_list, int64_payload.slice());
    try std.testing.expectEqualSlices(i64, &.{ -1, 2 }, int64_list.items);

    var sint32_payload = Writer.init(allocator);
    defer sint32_payload.deinit();
    try sint32_payload.writeVarint(zigZagEncode32(-3));
    try sint32_payload.writeVarint(zigZagEncode32(4));
    try sint32_payload.writeVarint((@as(u64, 1) << 32) | 2);
    var sint32_list: std.ArrayList(i32) = .empty;
    defer sint32_list.deinit(allocator);
    try appendPackedSInt32(allocator, &sint32_list, sint32_payload.slice());
    try std.testing.expectEqualSlices(i32, &.{ -3, 4, 1 }, sint32_list.items);

    var fields = Writer.init(allocator);
    defer fields.deinit();
    try fields.writeBytes(1, uint32_payload.slice());
    try fields.writeBytes(2, int64_payload.slice());
    try fields.writeBytes(3, sint32_payload.slice());

    var uint32_it = (try packedUInt32FieldIterator(fields.slice(), 1)).?;
    try std.testing.expectEqual(@as(u32, 1), (try uint32_it.next()).?);
    try std.testing.expectEqual(@as(u32, 128), (try uint32_it.next()).?);
    try std.testing.expectEqual(@as(u32, 4097), (try uint32_it.next()).?);
    try std.testing.expectEqual(@as(u32, 0), (try uint32_it.next()).?);
    try std.testing.expectEqual(@as(u32, 1), (try uint32_it.next()).?);
    try std.testing.expectEqual(@as(u32, std.math.maxInt(u32)), (try uint32_it.next()).?);
    try std.testing.expect((try uint32_it.next()) == null);

    var int64_it = (try packedInt64FieldIterator(fields.slice(), 2)).?;
    try std.testing.expectEqual(@as(i64, -1), (try int64_it.next()).?);
    try std.testing.expectEqual(@as(i64, 2), (try int64_it.next()).?);
    try std.testing.expect((try int64_it.next()) == null);

    var sint32_it = (try packedSInt32FieldIterator(fields.slice(), 3)).?;
    try std.testing.expectEqual(@as(i32, -3), (try sint32_it.next()).?);
    try std.testing.expectEqual(@as(i32, 4), (try sint32_it.next()).?);
    try std.testing.expectEqual(@as(i32, 1), (try sint32_it.next()).?);
    try std.testing.expect((try sint32_it.next()) == null);

    try std.testing.expect(packedVarintPayloadAllSingleByte(&.{ 0, 1, 2, 127 }));
    try std.testing.expect(!packedVarintPayloadAllSingleByte(&.{ 0, 0x80, 1 }));
}

test "packed varint iterators merge split packed and unpacked occurrences" {
    const allocator = std.testing.allocator;

    var first_payload = Writer.init(allocator);
    defer first_payload.deinit();
    try first_payload.writeVarint(1);
    try first_payload.writeVarint(128);

    var second_payload = Writer.init(allocator);
    defer second_payload.deinit();
    try second_payload.writeVarint(4097);
    try second_payload.writeVarint(std.math.maxInt(u32));

    var first_sint_payload = Writer.init(allocator);
    defer first_sint_payload.deinit();
    try first_sint_payload.writeVarint(zigZagEncode32(-3));
    try first_sint_payload.writeVarint(zigZagEncode32(4));

    var second_sint_payload = Writer.init(allocator);
    defer second_sint_payload.deinit();
    try second_sint_payload.writeVarint((@as(u64, 1) << 32) | 2);

    var fields = Writer.init(allocator);
    defer fields.deinit();
    try fields.writeUInt32(9, 99);
    try fields.writeBytes(1, first_payload.slice());
    try fields.writeBytes(3, first_sint_payload.slice());
    try fields.writeBytes(1, &.{});
    try fields.writeUInt32(8, 88);
    try fields.writeUInt32(1, 7);
    try fields.writeSInt32(3, -5);
    try fields.writeBytes(1, second_payload.slice());
    try fields.writeBytes(3, second_sint_payload.slice());

    var it = (try packedUInt32FieldIterator(fields.slice(), 1)).?;
    try std.testing.expectEqual(@as(u32, 1), (try it.next()).?);
    try std.testing.expectEqual(@as(u32, 128), (try it.next()).?);
    try std.testing.expectEqual(@as(u32, 7), (try it.next()).?);
    try std.testing.expectEqual(@as(u32, 4097), (try it.next()).?);
    try std.testing.expectEqual(@as(u32, std.math.maxInt(u32)), (try it.next()).?);
    try std.testing.expect((try it.next()) == null);

    var sint_it = (try packedSInt32FieldIterator(fields.slice(), 3)).?;
    try std.testing.expectEqual(@as(i32, -3), (try sint_it.next()).?);
    try std.testing.expectEqual(@as(i32, 4), (try sint_it.next()).?);
    try std.testing.expectEqual(@as(i32, -5), (try sint_it.next()).?);
    try std.testing.expectEqual(@as(i32, 1), (try sint_it.next()).?);
    try std.testing.expect((try sint_it.next()) == null);

    // Errors in later occurrences must not be hidden merely because the first
    // packed segment was valid.
    var invalid_fields = Writer.init(allocator);
    defer invalid_fields.deinit();
    try invalid_fields.writeBytes(1, &.{1});
    try invalid_fields.writeFixed32(1, 2);
    var invalid_it = (try packedUInt32FieldIterator(invalid_fields.slice(), 1)).?;
    try std.testing.expectEqual(@as(u32, 1), (try invalid_it.next()).?);
    try std.testing.expectError(error.InvalidWireType, invalid_it.next());
}

test "wire 32-bit varint readers truncate non-canonical 64-bit payloads" {
    var uint_reader = Reader.init(&.{ 0x80, 0x80, 0x80, 0x80, 0x20 });
    try std.testing.expectEqual(@as(u32, 0), try uint_reader.readUInt32());

    var sint_reader = Reader.init(&.{ 0x82, 0x80, 0x80, 0x80, 0x10 });
    try std.testing.expectEqual(@as(i32, 1), try sint_reader.readSInt32());

    var tag_reader = Reader.init(&.{ 0x88, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x00, 0xd2, 0x09 });
    try std.testing.expectError(error.MalformedVarint, tag_reader.nextTag());
}

test "wire exposes borrowed bytes field view" {
    var writer = Writer.init(std.testing.allocator);
    defer writer.deinit();
    try writer.writeUInt32(9, 7);
    try writer.writeBytes(1, "payload");
    try writer.writeBytes(2, "other");

    const payload = (try bytesFieldView(writer.slice(), 1)).?;
    try std.testing.expectEqualStrings("payload", payload);
    try std.testing.expectEqual(@intFromPtr(writer.slice().ptr) + 4, @intFromPtr(payload.ptr));
    try std.testing.expect(try bytesFieldView(writer.slice(), 3) == null);
}

test "wire skips nested groups and length-delimited values" {
    const bytes = &[_]u8{
        0x0b, // field 1 start group
        0x12,
        0x03,
        'a',
        'b',
        'c',
        0x0c, // field 1 end group
        0x18,
        0x01,
    };
    var reader = Reader.init(bytes);
    const first = (try reader.nextTag()).?;
    try reader.skipValue(first);
    const second = (try reader.nextTag()).?;
    try std.testing.expectEqual(@as(FieldNumber, 3), second.number);
    try std.testing.expect(try reader.readBool());
}

test "wire nested readers carry recursion limit" {
    var reader = Reader.init(&.{});
    reader.recursion_limit = 1;
    var child = try reader.nested(&.{});
    try std.testing.expectEqual(@as(u32, 1), child.recursion_depth);
    try std.testing.expectEqual(@as(u32, 1), child.recursion_limit);
    try std.testing.expectError(error.RecursionLimitExceeded, child.nested(&.{}));
}

test "wire reads group payload bytes" {
    var writer = Writer.init(std.testing.allocator);
    defer writer.deinit();
    try writer.writeTag(3, .start_group);
    try writer.writeInt32(1, 7);
    try writer.writeTag(3, .end_group);
    try writer.writeString(4, "tail");

    var reader = Reader.init(writer.slice());
    const group_tag = (try reader.nextTag()).?;
    try std.testing.expectEqual(@as(FieldNumber, 3), group_tag.number);
    try std.testing.expectEqual(WireType.start_group, group_tag.wire_type);
    try std.testing.expectEqualSlices(u8, &.{ 0x08, 0x07 }, try reader.readGroupBytes(3));
    const tail_tag = (try reader.nextTag()).?;
    try std.testing.expectEqual(@as(FieldNumber, 4), tail_tag.number);
    try std.testing.expectEqualStrings("tail", try reader.readBytes());
}
