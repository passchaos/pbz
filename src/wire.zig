const std = @import("std");

pub const FieldNumber = u29;

pub const Error = error{
    TruncatedInput,
    MalformedVarint,
    InvalidFieldNumber,
    InvalidWireType,
    UnsupportedWireType,
    RecursionLimitExceeded,
    Overflow,
};

pub const WireType = enum(u3) {
    varint = 0,
    fixed64 = 1,
    length_delimited = 2,
    start_group = 3,
    end_group = 4,
    fixed32 = 5,

    pub fn fromInt(value: u3) Error!WireType {
        return switch (value) {
            0 => .varint,
            1 => .fixed64,
            2 => .length_delimited,
            3 => .start_group,
            4 => .end_group,
            5 => .fixed32,
            else => error.InvalidWireType,
        };
    }
};

pub const Tag = struct {
    number: FieldNumber,
    wire_type: WireType,

    pub fn encode(self: Tag) Error!u64 {
        if (self.number == 0) return error.InvalidFieldNumber;
        return (@as(u64, self.number) << 3) | @intFromEnum(self.wire_type);
    }

    pub fn decode(value: u64) Error!Tag {
        const number = value >> 3;
        if (number == 0 or number > std.math.maxInt(FieldNumber)) return error.InvalidFieldNumber;
        return .{
            .number = @intCast(number),
            .wire_type = try WireType.fromInt(@intCast(value & 0x7)),
        };
    }
};

pub fn zigZagEncode32(value: i32) u32 {
    return @as(u32, @bitCast((value << 1) ^ (value >> 31)));
}

pub inline fn zigZagDecode32(value: u32) i32 {
    const half: i32 = @intCast(value >> 1);
    const sign: i32 = -@as(i32, @intCast(value & 1));
    return half ^ sign;
}

pub inline fn zigZagEncode64(value: i64) u64 {
    return @as(u64, @bitCast((value << 1) ^ (value >> 63)));
}

pub inline fn zigZagDecode64(value: u64) i64 {
    const half: i64 = @intCast(value >> 1);
    const sign: i64 = -@as(i64, @intCast(value & 1));
    return half ^ sign;
}

pub inline fn encodedVarintSize(value: u64) usize {
    if (value < (1 << 7)) return 1;
    if (value < (1 << 14)) return 2;
    if (value < (1 << 21)) return 3;
    return (@as(usize, 64 - @clz(value)) + 6) / 7;
}

pub inline fn bytesLessThan(lhs: []const u8, rhs: []const u8) bool {
    const common_len = @min(lhs.len, rhs.len);
    var i: usize = 0;
    while (common_len - i >= @sizeOf(u64)) : (i += @sizeOf(u64)) {
        // Reading a whole chunk as big-endian preserves lexicographic byte
        // order: the first differing byte becomes the most-significant
        // differing bits of the integer comparison. This keeps deterministic
        // string-map sorting fast for common fixed-width keys while falling
        // back to byte comparisons for the tail.
        const lhs_word = std.mem.readInt(u64, lhs[i..][0..@sizeOf(u64)], .big);
        const rhs_word = std.mem.readInt(u64, rhs[i..][0..@sizeOf(u64)], .big);
        if (lhs_word != rhs_word) return lhs_word < rhs_word;
    }
    while (i < common_len) : (i += 1) {
        if (lhs[i] != rhs[i]) return lhs[i] < rhs[i];
    }
    return lhs.len < rhs.len;
}

pub fn tagSize(number: FieldNumber, wire_type: WireType) Error!usize {
    return encodedVarintSize(try (Tag{ .number = number, .wire_type = wire_type }).encode());
}

pub inline fn rawFieldNumber(raw_field: []const u8) Error!FieldNumber {
    var index: usize = 0;
    const raw_tag = try readVarintAt(raw_field, &index);
    // Keep the same tag validation as Reader.nextTag while avoiding a full
    // Reader setup when callers only need to bucket an already-preserved raw
    // field by number.  A protobuf tag contains 29 field-number bits plus the
    // 3 wire-type bits, so any tag varint wider than five bytes is malformed
    // even if the generic varint decoder could represent its u64 value.
    if (index > 5) return error.MalformedVarint;
    return (try Tag.decode(raw_tag)).number;
}

pub fn rawFieldCountByNumber(fields: []const []const u8, number: FieldNumber) Error!usize {
    var count: usize = 0;
    for (fields) |raw| {
        if (raw.len == 0) continue;
        if ((try rawFieldNumber(raw)) == number) count += 1;
    }
    return count;
}

/// Counts already-validated raw unknown fields without re-running full tag
/// validation for every entry. Use this only for storage populated by Reader
/// decode or appendRawFieldClone(); arbitrary caller bytes should use
/// rawFieldCountByNumber instead.
pub inline fn rawFieldCountByNumberAssumeValid(fields: []const []const u8, number: FieldNumber) usize {
    const matcher = RawFieldNumberMatcher.init(number);
    var count: usize = 0;
    for (fields) |raw| {
        if (matcher.matches(raw)) count += 1;
    }
    return count;
}

/// Fast membership check for already-validated raw unknown fields.
pub inline fn rawFieldHasNumberAssumeValid(fields: []const []const u8, number: FieldNumber) bool {
    const matcher = RawFieldNumberMatcher.init(number);
    for (fields) |raw| {
        if (matcher.matches(raw)) return true;
    }
    return false;
}

const RawFieldNumberMatcher = struct {
    number: FieldNumber,
    low_start: u8,
    canonical_tag: [5]u8,
    canonical_tag_len: usize,

    inline fn init(number: FieldNumber) RawFieldNumberMatcher {
        var canonical_tag: [5]u8 = undefined;
        const tag_base = @as(u64, number) << 3;
        const canonical_tag_len = writeVarintToBuffer(&canonical_tag, tag_base);
        return .{
            .number = number,
            .low_start = @intCast(tag_base & 0x7f),
            .canonical_tag = canonical_tag,
            .canonical_tag_len = canonical_tag_len,
        };
    }

    inline fn matches(self: RawFieldNumberMatcher, raw: []const u8) bool {
        if (raw.len == 0 or self.number == 0) return false;
        if (!self.firstByteMayMatch(raw[0])) return false;
        if (self.startsWithCanonicalNumberTag(raw)) return true;
        // Generated messages and extension helpers only store raw fields that
        // were accepted by a Reader or by appendUnknownRaw() validation. The
        // fallback is therefore only for valid but non-canonical tag varints;
        // malformed data would indicate that the private unknown-field
        // invariant was broken.
        return (rawFieldNumber(raw) catch unreachable) == self.number;
    }

    inline fn firstByteMayMatch(self: RawFieldNumberMatcher, first: u8) bool {
        const low = first & 0x7f;
        if (low < self.low_start or low > self.low_start + 5) return false;
        // Tags for fields 1..15 are one-byte when canonical, but a preserved
        // unknown field may carry a non-canonical multi-byte tag whose first
        // byte has the continuation bit set. Tags for field 16 and above must
        // have the continuation bit set even in canonical form.
        return self.number < 16 or first >= 0x80;
    }

    inline fn startsWithCanonicalNumberTag(self: RawFieldNumberMatcher, raw: []const u8) bool {
        if (raw.len < self.canonical_tag_len) return false;
        if (self.canonical_tag_len == 1) return raw[0] < 0x80;
        // The wire type occupies only the low three bits of a protobuf tag.
        // Once the first byte's low seven bits have been range-checked, all
        // following canonical varint bytes must exactly match the
        // field-number-only tag.
        return raw[0] >= 0x80 and std.mem.eql(u8, raw[1..self.canonical_tag_len], self.canonical_tag[1..self.canonical_tag_len]);
    }
};

pub fn rawFieldsByNumberAlloc(allocator: std.mem.Allocator, fields: []const []const u8, number: FieldNumber) (std.mem.Allocator.Error || Error)![]const []const u8 {
    const count = try rawFieldCountByNumber(fields, number);
    if (count == 0) return &.{};

    const matched = try allocator.alloc([]const u8, count);
    errdefer allocator.free(matched);

    var index: usize = 0;
    for (fields) |raw| {
        if (raw.len == 0) continue;
        if ((try rawFieldNumber(raw)) == number) {
            matched[index] = raw;
            index += 1;
        }
    }
    std.debug.assert(index == count);
    return matched;
}

pub fn freeRawFields(allocator: std.mem.Allocator, fields: []const []const u8) void {
    for (fields) |raw| allocator.free(raw);
    if (fields.len != 0) allocator.free(fields);
}

pub fn clearRawFields(allocator: std.mem.Allocator, fields: *[]const []const u8) void {
    freeRawFields(allocator, fields.*);
    fields.* = &.{};
}

pub fn cloneRawFields(allocator: std.mem.Allocator, fields: []const []const u8) std.mem.Allocator.Error![]const []const u8 {
    if (fields.len == 0) return &.{};

    const cloned = try allocator.alloc([]const u8, fields.len);
    var cloned_count: usize = 0;
    errdefer {
        for (cloned[0..cloned_count]) |raw| allocator.free(raw);
        allocator.free(cloned);
    }
    for (fields, 0..) |raw, i| {
        cloned[i] = try allocator.dupe(u8, raw);
        cloned_count += 1;
    }
    return cloned;
}

pub fn deinitRawFieldList(allocator: std.mem.Allocator, list: *std.ArrayList([]const u8)) void {
    for (list.items) |raw| allocator.free(raw);
    list.deinit(allocator);
}

pub fn rawFieldListToOwnedSlice(allocator: std.mem.Allocator, list: *std.ArrayList([]const u8)) std.mem.Allocator.Error![]const []const u8 {
    if (list.items.len == 0) {
        list.deinit(allocator);
        return &.{};
    }
    return try list.toOwnedSlice(allocator);
}

pub fn appendOwnedRawField(allocator: std.mem.Allocator, list: *std.ArrayList([]const u8), raw: []const u8) std.mem.Allocator.Error!void {
    errdefer allocator.free(raw);
    try list.append(allocator, raw);
}

pub fn appendConsumedRawField(allocator: std.mem.Allocator, list: *std.ArrayList([]const u8), reader: anytype, raw_start: usize) (std.mem.Allocator.Error || Error)!void {
    const raw_end = reader.position();
    if (raw_start > raw_end or raw_end > reader.input.len) return error.InvalidWireType;

    // Raw unknown fields must preserve the exact source bytes, including
    // non-canonical-but-accepted tag or length varints. Callers therefore pass
    // the position captured before tag decoding instead of recomputing a tag
    // length from the canonical numeric value.
    const raw = try allocator.dupe(u8, reader.input[raw_start..raw_end]);
    try appendOwnedRawField(allocator, list, raw);
}

pub fn appendSkippedRawField(allocator: std.mem.Allocator, list: *std.ArrayList([]const u8), reader: *Reader, raw_start: usize, tag: Tag) (std.mem.Allocator.Error || Error)!void {
    try reader.skipValue(tag);
    try appendConsumedRawField(allocator, list, reader, raw_start);
}

pub fn appendRawVarintPayload(allocator: std.mem.Allocator, list: *std.ArrayList([]const u8), number: FieldNumber, payload: []const u8) (std.mem.Allocator.Error || Error)!void {
    const raw_tag = try (Tag{ .number = number, .wire_type = .varint }).encode();
    const tag_len = encodedVarintSize(raw_tag);
    const raw = try allocator.alloc(u8, tag_len + payload.len);
    const written = writeVarintToBuffer(raw[0..tag_len], raw_tag);
    std.debug.assert(written == tag_len);
    @memcpy(raw[tag_len..], payload);
    try appendOwnedRawField(allocator, list, raw);
}

pub fn validateRawField(raw: []const u8) Error!void {
    var reader = Reader.init(raw);
    const tag = (try reader.nextTag()) orelse return error.InvalidWireType;
    try reader.skipValue(tag);
    if (!reader.eof()) return error.InvalidWireType;
}

pub fn appendRawFieldClone(allocator: std.mem.Allocator, fields: *[]const []const u8, raw: []const u8) (std.mem.Allocator.Error || Error)!void {
    try appendRawFieldsClone(allocator, fields, &.{raw});
}

pub fn appendRawFieldsClone(allocator: std.mem.Allocator, fields: *[]const []const u8, raws: []const []const u8) (std.mem.Allocator.Error || Error)!void {
    if (raws.len == 0) return;
    // Validate the full batch before cloning or replacing the slice header.  A
    // failed append must leave the caller's existing unknown-field ownership
    // unchanged so generated mergeFrom keeps the same all-or-error contract as
    // repeatedly calling appendUnknownRaw.
    for (raws) |raw| try validateRawField(raw);
    try appendRawFieldsCloneUnchecked(allocator, fields, raws);
}

fn appendRawFieldsCloneUnchecked(allocator: std.mem.Allocator, fields: *[]const []const u8, raws: []const []const u8) std.mem.Allocator.Error!void {
    const old = fields.*;
    const next = try allocator.alloc([]const u8, old.len + raws.len);
    var cloned_count: usize = 0;
    errdefer {
        for (next[old.len..][0..cloned_count]) |owned| allocator.free(owned);
        allocator.free(next);
    }
    if (old.len != 0) @memcpy(next[0..old.len], old);
    for (raws, 0..) |raw, i| {
        next[old.len + i] = try allocator.dupe(u8, raw);
        cloned_count += 1;
    }

    fields.* = next;
    if (old.len != 0) allocator.free(old);
}

pub fn writeRawFieldsDeterministic(allocator: std.mem.Allocator, fields: []const []const u8, w: *Writer) std.mem.Allocator.Error!void {
    if (fields.len == 0) return;
    if (fields.len == 1) {
        try w.appendSlice(fields[0]);
        return;
    }

    const indexes = try deterministicRawFieldIndexes(allocator, fields);
    defer allocator.free(indexes);
    for (indexes) |index| try w.appendSlice(fields[index]);
}

pub fn writeRawFieldsDeterministicAssumeCapacity(allocator: std.mem.Allocator, fields: []const []const u8, w: *Writer) std.mem.Allocator.Error!void {
    if (fields.len == 0) return;
    if (fields.len == 1) {
        w.appendSliceAssumeCapacity(fields[0]);
        return;
    }

    const indexes = try deterministicRawFieldIndexes(allocator, fields);
    defer allocator.free(indexes);
    for (indexes) |index| w.appendSliceAssumeCapacity(fields[index]);
}

fn deterministicRawFieldIndexes(allocator: std.mem.Allocator, fields: []const []const u8) std.mem.Allocator.Error![]usize {
    const indexes = try allocator.alloc(usize, fields.len);
    for (indexes, 0..) |*index, i| index.* = i;
    std.mem.sort(usize, indexes, fields, deterministicRawFieldIndexLessThan);
    return indexes;
}

fn rawFieldFirstTag(raw: []const u8) ?Tag {
    var reader = Reader.init(raw);
    return (reader.nextTag() catch null) orelse null;
}

fn deterministicRawFieldIndexLessThan(fields: []const []const u8, a: usize, b: usize) bool {
    const tag_a = rawFieldFirstTag(fields[a]);
    const tag_b = rawFieldFirstTag(fields[b]);
    if (tag_a == null or tag_b == null) return std.mem.lessThan(u8, fields[a], fields[b]);
    if (tag_a.?.number != tag_b.?.number) return tag_a.?.number < tag_b.?.number;
    if (tag_a.?.wire_type != tag_b.?.wire_type) return @intFromEnum(tag_a.?.wire_type) < @intFromEnum(tag_b.?.wire_type);
    return std.mem.lessThan(u8, fields[a], fields[b]);
}

pub fn clearRawFieldsByNumber(allocator: std.mem.Allocator, fields: *[]const []const u8, number: FieldNumber) (std.mem.Allocator.Error || Error)!void {
    var keep_count: usize = 0;
    var remove_count: usize = 0;
    for (fields.*) |raw| {
        if (raw.len == 0) {
            remove_count += 1;
            continue;
        }
        if ((try rawFieldNumber(raw)) == number) remove_count += 1 else keep_count += 1;
    }
    if (remove_count == 0) return;

    const old = fields.*;
    var kept: [][]const u8 = &.{};
    if (keep_count != 0) kept = try allocator.alloc([]const u8, keep_count);
    errdefer if (keep_count != 0) allocator.free(kept);

    var kept_index: usize = 0;
    for (old) |raw| {
        if (raw.len == 0) {
            allocator.free(raw);
            continue;
        }
        // The first pass already validated every non-empty raw field. Avoid a
        // second fallible exit after ownership transfer has begun; generated
        // messages do not expose mutable aliases to raw field bytes here.
        if ((rawFieldNumber(raw) catch unreachable) == number) {
            allocator.free(raw);
            continue;
        }
        kept[kept_index] = raw;
        kept_index += 1;
    }
    std.debug.assert(kept_index == keep_count);
    if (old.len != 0) allocator.free(old);
    fields.* = kept;
}

pub fn writePackedFixedWidthPayload(comptime T: type, w: *Writer, values: []const T) std.mem.Allocator.Error!void {
    if (T != u32 and T != i32 and T != f32 and T != u64 and T != i64 and T != f64) {
        @compileError("writePackedFixedWidthPayload requires u32, i32, f32, u64, i64, or f64");
    }
    if (comptime @import("builtin").target.cpu.arch.endian() == .little) {
        try w.appendSlice(std.mem.sliceAsBytes(values));
    } else {
        for (values) |value| {
            if (T == f32) {
                try w.writeRawLittle(u32, @bitCast(value));
            } else if (T == f64) {
                try w.writeRawLittle(u64, @bitCast(value));
            } else {
                try w.writeRawLittle(T, value);
            }
        }
    }
}

pub fn writePackedFixedWidthPayloadAssumeCapacity(comptime T: type, w: *Writer, values: []const T) void {
    if (T != u32 and T != i32 and T != f32 and T != u64 and T != i64 and T != f64) {
        @compileError("writePackedFixedWidthPayloadAssumeCapacity requires u32, i32, f32, u64, i64, or f64");
    }
    if (comptime @import("builtin").target.cpu.arch.endian() == .little) {
        w.appendSliceAssumeCapacity(std.mem.sliceAsBytes(values));
    } else {
        for (values) |value| {
            if (T == f32) {
                w.writeRawLittleAssumeCapacity(u32, @bitCast(value));
            } else if (T == f64) {
                w.writeRawLittleAssumeCapacity(u64, @bitCast(value));
            } else {
                w.writeRawLittleAssumeCapacity(T, value);
            }
        }
    }
}

pub fn writePackedFixed32Payload(w: *Writer, values: []const u32) std.mem.Allocator.Error!void {
    try writePackedFixedWidthPayload(u32, w, values);
}

pub fn writePackedFixed32PayloadAssumeCapacity(w: *Writer, values: []const u32) void {
    writePackedFixedWidthPayloadAssumeCapacity(u32, w, values);
}

pub const BorrowedFieldSlices = struct {
    header: []const u8,
    payload: []const u8,
};

pub inline fn writeVarintToBuffer(buffer: []u8, value: u64) usize {
    var v = value;
    if (v < 0x80) {
        buffer[0] = @truncate(v);
        return 1;
    }
    buffer[0] = @truncate(v | 0x80);
    v >>= 7;
    if (v < 0x80) {
        buffer[1] = @truncate(v);
        return 2;
    }
    buffer[1] = @truncate(v | 0x80);
    v >>= 7;
    if (v < 0x80) {
        buffer[2] = @truncate(v);
        return 3;
    }
    buffer[2] = @truncate(v | 0x80);
    v >>= 7;
    if (v < 0x80) {
        buffer[3] = @truncate(v);
        return 4;
    }
    buffer[3] = @truncate(v | 0x80);
    v >>= 7;
    if (v < 0x80) {
        buffer[4] = @truncate(v);
        return 5;
    }
    buffer[4] = @truncate(v | 0x80);
    v >>= 7;
    if (v < 0x80) {
        buffer[5] = @truncate(v);
        return 6;
    }
    buffer[5] = @truncate(v | 0x80);
    v >>= 7;
    if (v < 0x80) {
        buffer[6] = @truncate(v);
        return 7;
    }
    buffer[6] = @truncate(v | 0x80);
    v >>= 7;
    if (v < 0x80) {
        buffer[7] = @truncate(v);
        return 8;
    }
    buffer[7] = @truncate(v | 0x80);
    v >>= 7;
    if (v < 0x80) {
        buffer[8] = @truncate(v);
        return 9;
    }
    buffer[8] = @truncate(v | 0x80);
    v >>= 7;
    buffer[9] = @truncate(v);
    return 10;
}

pub inline fn writeVarintToSlice(buffer: []u8, index: *usize, value: u64) void {
    index.* += writeVarintToBuffer(buffer[index.*..], value);
}

pub inline fn writeNegativeInt64VarintToSlice(buffer: []u8, index: *usize, value: i64) void {
    std.debug.assert(value < 0);

    // Protobuf encodes negative int64 values as the full ten-byte varint of
    // their two's-complement representation.  This is the same sequence as the
    // generic writer, but specialized for callers that already know the value
    // is negative so they can avoid repeated termination checks.
    var v: u64 = @bitCast(value);
    const start = index.*;
    var out = buffer[start..][0..10];
    inline for (0..9) |i| {
        out[i] = @truncate(v | 0x80);
        v >>= 7;
    }
    out[9] = @truncate(v);
    index.* = start + 10;
}

pub inline fn writeRawLittleToSlice(comptime T: type, buffer: []u8, index: *usize, value: T) void {
    const start = index.*;
    index.* = start + @sizeOf(T);
    std.mem.writeInt(T, buffer[start..][0..@sizeOf(T)], value, .little);
}

pub fn lengthDelimitedFieldSlices(header: *[20]u8, number: FieldNumber, payload: []const u8) Error!BorrowedFieldSlices {
    const tag = try (Tag{ .number = number, .wire_type = .length_delimited }).encode();
    var header_len: usize = 0;
    header_len += writeVarintToBuffer(header[header_len..], tag);
    header_len += writeVarintToBuffer(header[header_len..], @intCast(payload.len));
    return .{ .header = header[0..header_len], .payload = payload };
}

pub fn packedFixedWidthFieldSlices(comptime T: type, header: *[20]u8, number: FieldNumber, values: []const T) Error!BorrowedFieldSlices {
    if (T != u32 and T != i32 and T != f32 and T != u64 and T != i64 and T != f64) {
        @compileError("packedFixedWidthFieldSlices requires u32, i32, f32, u64, i64, or f64");
    }
    if (comptime @import("builtin").target.cpu.arch.endian() != .little) return error.UnsupportedWireType;
    const tag = try (Tag{ .number = number, .wire_type = .length_delimited }).encode();
    const payload = std.mem.sliceAsBytes(values);
    var header_len: usize = 0;
    header_len += writeVarintToBuffer(header[header_len..], tag);
    header_len += writeVarintToBuffer(header[header_len..], @intCast(payload.len));
    return .{ .header = header[0..header_len], .payload = payload };
}

pub fn packedFixed32FieldSlices(header: *[20]u8, number: FieldNumber, values: []const u32) Error!BorrowedFieldSlices {
    return try packedFixedWidthFieldSlices(u32, header, number, values);
}

pub fn packedBoolFieldSlices(header: *[20]u8, number: FieldNumber, values: []const bool) Error!BorrowedFieldSlices {
    // Zig stores bool slices as one byte per element, and pbz's normal packed
    // bool encoder already emits that byte representation. Exposing the same
    // header+payload split lets callers feed trusted generated values to vectored
    // I/O without copying the payload into a temporary writer first.
    return try lengthDelimitedFieldSlices(header, number, std.mem.sliceAsBytes(values));
}

pub fn packedFixedWidthView(comptime T: type, payload: []const u8) Error![]align(1) const T {
    if (T != u32 and T != i32 and T != f32 and T != u64 and T != i64 and T != f64) {
        @compileError("packedFixedWidthView requires u32, i32, f32, u64, i64, or f64");
    }
    if (payload.len % @sizeOf(T) != 0) return error.InvalidWireType;
    if (comptime @import("builtin").target.cpu.arch.endian() != .little) return error.UnsupportedWireType;
    return std.mem.bytesAsSlice(T, payload);
}

pub fn packedFixedWidthFieldView(comptime T: type, bytes: []const u8, number: FieldNumber) Error!?[]align(1) const T {
    var reader = Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        if (tag.number == number) {
            if (tag.wire_type != .length_delimited) return error.InvalidWireType;
            return try packedFixedWidthView(T, try reader.readBytes());
        }
        try reader.skipValue(tag);
    }
    return null;
}

pub fn packedFixed32View(payload: []const u8) Error![]align(1) const u32 {
    return try packedFixedWidthView(u32, payload);
}

pub fn packedFixed32FieldView(bytes: []const u8, number: FieldNumber) Error!?[]align(1) const u32 {
    return try packedFixedWidthFieldView(u32, bytes, number);
}

pub const PackedUInt64Iterator = struct {
    payload: []const u8,
    index: usize = 0,
    remaining_fields: []const u8 = &.{},
    field_number: FieldNumber = 0,

    pub inline fn next(self: *PackedUInt64Iterator) Error!?u64 {
        return try nextPackedVarint(self);
    }
};

pub const PackedInt32Iterator = struct {
    payload: []const u8,
    index: usize = 0,
    remaining_fields: []const u8 = &.{},
    field_number: FieldNumber = 0,

    pub inline fn next(self: *PackedInt32Iterator) Error!?i32 {
        const value = (try nextPackedVarint32Hot(self)) orelse return null;
        return @bitCast(value);
    }
};

pub const PackedUInt32Iterator = struct {
    payload: []const u8,
    index: usize = 0,
    remaining_fields: []const u8 = &.{},
    field_number: FieldNumber = 0,

    pub inline fn next(self: *PackedUInt32Iterator) Error!?u32 {
        const value = (try nextPackedVarint(self)) orelse return null;
        return @as(u32, @truncate(value));
    }
};

pub const PackedInt64Iterator = struct {
    payload: []const u8,
    index: usize = 0,
    remaining_fields: []const u8 = &.{},
    field_number: FieldNumber = 0,

    pub inline fn next(self: *PackedInt64Iterator) Error!?i64 {
        const value = (try nextPackedVarint(self)) orelse return null;
        return @bitCast(value);
    }
};

pub const PackedSInt32Iterator = struct {
    payload: []const u8,
    index: usize = 0,
    remaining_fields: []const u8 = &.{},
    field_number: FieldNumber = 0,

    pub inline fn next(self: *PackedSInt32Iterator) Error!?i32 {
        const value = (try nextPackedVarint32Hot(self)) orelse return null;
        return zigZagDecode32(value);
    }
};

pub const PackedSInt64Iterator = struct {
    payload: []const u8,
    index: usize = 0,
    remaining_fields: []const u8 = &.{},
    field_number: FieldNumber = 0,

    pub inline fn next(self: *PackedSInt64Iterator) Error!?i64 {
        const value = (try nextPackedVarint(self)) orelse return null;
        return zigZagDecode64(value);
    }
};

const PackedVarintSegment = struct {
    payload: []const u8,
    remaining_fields: []const u8,
};

/// Finds the next occurrence of a repeated varint field without allocating.
///
/// Protobuf merges every occurrence of a repeated primitive field, and parsers
/// must accept packed and unpacked representations even when the schema's
/// preferred encoding is packed. Keeping the unvisited wire bytes in the
/// iterator lets the public packed iterators preserve that behavior rather
/// than silently stopping after the first occurrence.
fn nextPackedVarintSegment(bytes: []const u8, number: FieldNumber) Error!?PackedVarintSegment {
    var reader = Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        if (tag.number == number) {
            const payload = switch (tag.wire_type) {
                .length_delimited => try reader.readBytes(),
                .varint => payload: {
                    const start = reader.position();
                    _ = try reader.readVarint();
                    break :payload bytes[start..reader.position()];
                },
                else => return error.InvalidWireType,
            };
            return .{ .payload = payload, .remaining_fields = reader.remaining() };
        }
        try reader.skipValue(tag);
    }
    return null;
}

inline fn nextPackedVarint(iterator: anytype) Error!?u64 {
    while (true) {
        if (iterator.index < iterator.payload.len) {
            @branchHint(.likely);
            return try readVarintAt(iterator.payload, &iterator.index);
        }

        // A zero field number is the sentinel used by callers that construct an
        // iterator directly over a raw packed payload. Such iterators retain
        // the original one-segment behavior.
        if (iterator.field_number == 0) return null;
        const segment = (try nextPackedVarintSegment(iterator.remaining_fields, iterator.field_number)) orelse return null;
        iterator.payload = segment.payload;
        iterator.index = 0;
        iterator.remaining_fields = segment.remaining_fields;
    }
}

inline fn nextPackedVarint32Hot(iterator: anytype) Error!?u32 {
    while (true) {
        if (iterator.index < iterator.payload.len) {
            @branchHint(.likely);
            const start = iterator.index;
            const payload = iterator.payload;
            var index = start;

            // Int32/SInt32-heavy payloads in generated code usually encode in
            // one or two bytes. Decode that common case in u32 form and fall
            // back to the fully general varint reader only for longer or
            // deliberately non-canonical encodings. Keeping the fallback
            // preserves protobuf's accepted 64-bit varint truncation behavior
            // for 32-bit scalar readers.
            const first = payload[index];
            index += 1;
            var raw: u32 = first & 0x7f;
            if (first < 0x80) {
                iterator.index = index;
                return raw;
            }

            if (index >= payload.len) {
                iterator.index = index;
                return error.TruncatedInput;
            }
            const second = payload[index];
            index += 1;
            raw |= @as(u32, second & 0x7f) << 7;
            if (second < 0x80) {
                iterator.index = index;
                return raw;
            }

            iterator.index = start;
            return @truncate(try readVarintAt(payload, &iterator.index));
        }

        // A zero field number is the sentinel used by callers that construct an
        // iterator directly over a raw packed payload. Such iterators retain
        // the original one-segment behavior.
        if (iterator.field_number == 0) return null;
        const segment = (try nextPackedVarintSegment(iterator.remaining_fields, iterator.field_number)) orelse return null;
        iterator.payload = segment.payload;
        iterator.index = 0;
        iterator.remaining_fields = segment.remaining_fields;
    }
}

pub fn packedUInt64FieldIterator(bytes: []const u8, number: FieldNumber) Error!?PackedUInt64Iterator {
    const segment = (try nextPackedVarintSegment(bytes, number)) orelse return null;
    return .{ .payload = segment.payload, .remaining_fields = segment.remaining_fields, .field_number = number };
}

pub fn packedInt32FieldIterator(bytes: []const u8, number: FieldNumber) Error!?PackedInt32Iterator {
    const segment = (try nextPackedVarintSegment(bytes, number)) orelse return null;
    return .{ .payload = segment.payload, .remaining_fields = segment.remaining_fields, .field_number = number };
}

pub fn packedUInt32FieldIterator(bytes: []const u8, number: FieldNumber) Error!?PackedUInt32Iterator {
    const segment = (try nextPackedVarintSegment(bytes, number)) orelse return null;
    return .{ .payload = segment.payload, .remaining_fields = segment.remaining_fields, .field_number = number };
}

pub fn packedInt64FieldIterator(bytes: []const u8, number: FieldNumber) Error!?PackedInt64Iterator {
    const segment = (try nextPackedVarintSegment(bytes, number)) orelse return null;
    return .{ .payload = segment.payload, .remaining_fields = segment.remaining_fields, .field_number = number };
}

pub fn packedSInt32FieldIterator(bytes: []const u8, number: FieldNumber) Error!?PackedSInt32Iterator {
    const segment = (try nextPackedVarintSegment(bytes, number)) orelse return null;
    return .{ .payload = segment.payload, .remaining_fields = segment.remaining_fields, .field_number = number };
}

pub fn packedSInt64FieldIterator(bytes: []const u8, number: FieldNumber) Error!?PackedSInt64Iterator {
    const segment = (try nextPackedVarintSegment(bytes, number)) orelse return null;
    return .{ .payload = segment.payload, .remaining_fields = segment.remaining_fields, .field_number = number };
}

pub fn bytesFieldView(bytes: []const u8, number: FieldNumber) Error!?[]const u8 {
    var reader = Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        if (tag.number == number) {
            if (tag.wire_type != .length_delimited) return error.InvalidWireType;
            return try reader.readBytes();
        }
        try reader.skipValue(tag);
    }
    return null;
}

pub fn appendPackedFixedWidth(comptime T: type, allocator: std.mem.Allocator, list: *std.ArrayList(T), payload: []const u8) (std.mem.Allocator.Error || Error)!void {
    if (T != u32 and T != i32 and T != f32 and T != u64 and T != i64 and T != f64) {
        @compileError("appendPackedFixedWidth requires u32, i32, f32, u64, i64, or f64");
    }
    if (payload.len % @sizeOf(T) != 0) return error.InvalidWireType;
    const count = payload.len / @sizeOf(T);
    if (count == 0) return;
    if (list.items.len == 0 and list.capacity == 0) {
        const out = try allocator.alloc(T, count);
        list.* = std.ArrayList(T).fromOwnedSlice(out);
        if (comptime @import("builtin").target.cpu.arch.endian() == .little) {
            @memcpy(std.mem.sliceAsBytes(out), payload);
        } else {
            readFixedWidthPayload(T, out, payload);
        }
        return;
    }
    try list.ensureTotalCapacityPrecise(allocator, list.items.len + count);
    const out = list.addManyAsSliceAssumeCapacity(count);
    if (comptime @import("builtin").target.cpu.arch.endian() == .little) {
        @memcpy(std.mem.sliceAsBytes(out), payload);
    } else {
        readFixedWidthPayload(T, out, payload);
    }
}

fn readFixedWidthPayload(comptime T: type, out: []T, payload: []const u8) void {
    const width = @sizeOf(T);
    for (out, 0..) |*value, i| {
        const raw = payload[i * width ..][0..width];
        if (T == f32) {
            value.* = @bitCast(std.mem.readInt(u32, raw, .little));
        } else if (T == f64) {
            value.* = @bitCast(std.mem.readInt(u64, raw, .little));
        } else {
            value.* = std.mem.readInt(T, raw, .little);
        }
    }
}

pub fn appendPackedFixed32(allocator: std.mem.Allocator, list: *std.ArrayList(u32), payload: []const u8) (std.mem.Allocator.Error || Error)!void {
    try appendPackedFixedWidth(u32, allocator, list, payload);
}

pub fn appendPackedFixed64(allocator: std.mem.Allocator, list: *std.ArrayList(u64), payload: []const u8) (std.mem.Allocator.Error || Error)!void {
    try appendPackedFixedWidth(u64, allocator, list, payload);
}

pub fn appendPackedSFixed32(allocator: std.mem.Allocator, list: *std.ArrayList(i32), payload: []const u8) (std.mem.Allocator.Error || Error)!void {
    try appendPackedFixedWidth(i32, allocator, list, payload);
}

pub fn appendPackedSFixed64(allocator: std.mem.Allocator, list: *std.ArrayList(i64), payload: []const u8) (std.mem.Allocator.Error || Error)!void {
    try appendPackedFixedWidth(i64, allocator, list, payload);
}

pub fn appendPackedFloat(allocator: std.mem.Allocator, list: *std.ArrayList(f32), payload: []const u8) (std.mem.Allocator.Error || Error)!void {
    try appendPackedFixedWidth(f32, allocator, list, payload);
}

pub fn appendPackedDouble(allocator: std.mem.Allocator, list: *std.ArrayList(f64), payload: []const u8) (std.mem.Allocator.Error || Error)!void {
    try appendPackedFixedWidth(f64, allocator, list, payload);
}

pub const Writer = struct {
    allocator: std.mem.Allocator,
    bytes: std.ArrayList(u8) = .empty,

    pub fn init(allocator: std.mem.Allocator) Writer {
        return .{ .allocator = allocator };
    }

    pub fn initBuffer(allocator: std.mem.Allocator, buffer: []u8) Writer {
        return .{ .allocator = allocator, .bytes = std.ArrayList(u8).initBuffer(buffer) };
    }

    pub fn deinit(self: *Writer) void {
        self.bytes.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn clearRetainingCapacity(self: *Writer) void {
        self.bytes.clearRetainingCapacity();
    }

    pub fn slice(self: *const Writer) []const u8 {
        return self.bytes.items;
    }

    pub fn toOwnedSlice(self: *Writer) std.mem.Allocator.Error![]u8 {
        return self.bytes.toOwnedSlice(self.allocator);
    }

    pub fn appendByte(self: *Writer, byte: u8) std.mem.Allocator.Error!void {
        try self.bytes.append(self.allocator, byte);
    }

    pub fn appendByteAssumeCapacity(self: *Writer, byte: u8) void {
        self.bytes.appendAssumeCapacity(byte);
    }

    pub fn appendSlice(self: *Writer, data: []const u8) std.mem.Allocator.Error!void {
        try self.bytes.appendSlice(self.allocator, data);
    }

    pub fn appendSliceAssumeCapacity(self: *Writer, data: []const u8) void {
        const out = self.bytes.addManyAsSliceAssumeCapacity(data.len);
        @memcpy(out, data);
    }

    pub fn writeVarint(self: *Writer, value: u64) std.mem.Allocator.Error!void {
        const len = encodedVarintSize(value);
        try self.bytes.ensureUnusedCapacity(self.allocator, len);
        const out = self.bytes.addManyAsSliceAssumeCapacity(len);
        _ = writeVarintToBuffer(out, value);
    }

    pub fn writeVarintAssumeCapacity(self: *Writer, value: u64) void {
        const out = self.bytes.addManyAsSliceAssumeCapacity(encodedVarintSize(value));
        _ = writeVarintToBuffer(out, value);
    }

    pub fn writeTag(self: *Writer, number: FieldNumber, wire_type: WireType) (std.mem.Allocator.Error || Error)!void {
        const raw = try (Tag{ .number = number, .wire_type = wire_type }).encode();
        if (raw < 0x80) {
            try self.appendByte(@intCast(raw));
        } else {
            try self.writeVarint(raw);
        }
    }

    pub fn writeTagAssumeCapacity(self: *Writer, number: FieldNumber, wire_type: WireType) void {
        const raw = (@as(u64, number) << 3) | @intFromEnum(wire_type);
        if (raw < 0x80) {
            self.appendByteAssumeCapacity(@intCast(raw));
        } else {
            self.writeVarintAssumeCapacity(raw);
        }
    }

    pub fn writeUInt32(self: *Writer, number: FieldNumber, value: u32) !void {
        try self.writeTag(number, .varint);
        try self.writeVarint(value);
    }

    pub fn writeUInt32AssumeCapacity(self: *Writer, number: FieldNumber, value: u32) void {
        self.writeTagAssumeCapacity(number, .varint);
        self.writeVarintAssumeCapacity(value);
    }

    pub fn writeUInt64(self: *Writer, number: FieldNumber, value: u64) !void {
        try self.writeTag(number, .varint);
        try self.writeVarint(value);
    }

    pub fn writeUInt64AssumeCapacity(self: *Writer, number: FieldNumber, value: u64) void {
        self.writeTagAssumeCapacity(number, .varint);
        self.writeVarintAssumeCapacity(value);
    }

    pub fn writeInt32(self: *Writer, number: FieldNumber, value: i32) !void {
        try self.writeTag(number, .varint);
        try self.writeVarint(@as(u64, @bitCast(@as(i64, value))));
    }

    pub fn writeInt32AssumeCapacity(self: *Writer, number: FieldNumber, value: i32) void {
        self.writeTagAssumeCapacity(number, .varint);
        self.writeVarintAssumeCapacity(@as(u64, @bitCast(@as(i64, value))));
    }

    pub fn writeInt64(self: *Writer, number: FieldNumber, value: i64) !void {
        try self.writeTag(number, .varint);
        try self.writeVarint(@as(u64, @bitCast(value)));
    }

    pub fn writeInt64AssumeCapacity(self: *Writer, number: FieldNumber, value: i64) void {
        self.writeTagAssumeCapacity(number, .varint);
        self.writeVarintAssumeCapacity(@as(u64, @bitCast(value)));
    }

    pub fn writeSInt32(self: *Writer, number: FieldNumber, value: i32) !void {
        try self.writeTag(number, .varint);
        try self.writeVarint(zigZagEncode32(value));
    }

    pub fn writeSInt32AssumeCapacity(self: *Writer, number: FieldNumber, value: i32) void {
        self.writeTagAssumeCapacity(number, .varint);
        self.writeVarintAssumeCapacity(zigZagEncode32(value));
    }

    pub fn writeSInt64(self: *Writer, number: FieldNumber, value: i64) !void {
        try self.writeTag(number, .varint);
        try self.writeVarint(zigZagEncode64(value));
    }

    pub fn writeSInt64AssumeCapacity(self: *Writer, number: FieldNumber, value: i64) void {
        self.writeTagAssumeCapacity(number, .varint);
        self.writeVarintAssumeCapacity(zigZagEncode64(value));
    }

    pub fn writeBool(self: *Writer, number: FieldNumber, value: bool) !void {
        try self.writeTag(number, .varint);
        try self.appendByte(if (value) 1 else 0);
    }

    pub fn writeBoolAssumeCapacity(self: *Writer, number: FieldNumber, value: bool) void {
        self.writeTagAssumeCapacity(number, .varint);
        self.appendByteAssumeCapacity(if (value) 1 else 0);
    }

    pub fn writeFixed32(self: *Writer, number: FieldNumber, value: u32) !void {
        try self.writeTag(number, .fixed32);
        try self.writeRawLittle(u32, value);
    }

    pub fn writeFixed32AssumeCapacity(self: *Writer, number: FieldNumber, value: u32) void {
        self.writeTagAssumeCapacity(number, .fixed32);
        self.writeRawLittleAssumeCapacity(u32, value);
    }

    pub fn writeSFixed32(self: *Writer, number: FieldNumber, value: i32) !void {
        try self.writeFixed32(number, @bitCast(value));
    }

    pub fn writeSFixed32AssumeCapacity(self: *Writer, number: FieldNumber, value: i32) void {
        self.writeFixed32AssumeCapacity(number, @bitCast(value));
    }

    pub fn writeFixed64(self: *Writer, number: FieldNumber, value: u64) !void {
        try self.writeTag(number, .fixed64);
        try self.writeRawLittle(u64, value);
    }

    pub fn writeFixed64AssumeCapacity(self: *Writer, number: FieldNumber, value: u64) void {
        self.writeTagAssumeCapacity(number, .fixed64);
        self.writeRawLittleAssumeCapacity(u64, value);
    }

    pub fn writeSFixed64(self: *Writer, number: FieldNumber, value: i64) !void {
        try self.writeFixed64(number, @bitCast(value));
    }

    pub fn writeSFixed64AssumeCapacity(self: *Writer, number: FieldNumber, value: i64) void {
        self.writeFixed64AssumeCapacity(number, @bitCast(value));
    }

    pub fn writeFloat(self: *Writer, number: FieldNumber, value: f32) !void {
        try self.writeFixed32(number, @bitCast(value));
    }

    pub fn writeFloatAssumeCapacity(self: *Writer, number: FieldNumber, value: f32) void {
        self.writeFixed32AssumeCapacity(number, @bitCast(value));
    }

    pub fn writeDouble(self: *Writer, number: FieldNumber, value: f64) !void {
        try self.writeFixed64(number, @bitCast(value));
    }

    pub fn writeDoubleAssumeCapacity(self: *Writer, number: FieldNumber, value: f64) void {
        self.writeFixed64AssumeCapacity(number, @bitCast(value));
    }

    pub fn writeBytes(self: *Writer, number: FieldNumber, value: []const u8) !void {
        try self.writeTag(number, .length_delimited);
        if (value.len < 0x80) {
            try self.appendByte(@intCast(value.len));
        } else {
            try self.writeVarint(value.len);
        }
        try self.appendSlice(value);
    }

    pub fn writeBytesAssumeCapacity(self: *Writer, number: FieldNumber, value: []const u8) void {
        self.writeTagAssumeCapacity(number, .length_delimited);
        if (value.len < 0x80) {
            self.appendByteAssumeCapacity(@intCast(value.len));
        } else {
            self.writeVarintAssumeCapacity(value.len);
        }
        self.appendSliceAssumeCapacity(value);
    }

    pub fn writeString(self: *Writer, number: FieldNumber, value: []const u8) !void {
        try self.writeBytes(number, value);
    }

    pub fn writeStringAssumeCapacity(self: *Writer, number: FieldNumber, value: []const u8) void {
        self.writeBytesAssumeCapacity(number, value);
    }

    pub fn writeMessage(self: *Writer, number: FieldNumber, encoded_message: []const u8) !void {
        try self.writeBytes(number, encoded_message);
    }

    pub fn writeMessageAssumeCapacity(self: *Writer, number: FieldNumber, encoded_message: []const u8) void {
        self.writeBytesAssumeCapacity(number, encoded_message);
    }

    pub fn writePackedVarints(self: *Writer, number: FieldNumber, values: []const u64) !void {
        var packed_writer = Writer.init(self.allocator);
        defer packed_writer.deinit();
        for (values) |value| try packed_writer.writeVarint(value);
        try self.writeBytes(number, packed_writer.slice());
    }

    pub fn writeRawLittle(self: *Writer, comptime T: type, value: T) std.mem.Allocator.Error!void {
        const out = try self.bytes.addManyAsSlice(self.allocator, @sizeOf(T));
        std.mem.writeInt(T, out[0..@sizeOf(T)], value, .little);
    }

    pub fn writeRawLittleAssumeCapacity(self: *Writer, comptime T: type, value: T) void {
        const out = self.bytes.addManyAsSliceAssumeCapacity(@sizeOf(T));
        std.mem.writeInt(T, out[0..@sizeOf(T)], value, .little);
    }
};

pub const Reader = struct {
    input: []const u8,
    index: usize = 0,
    /// Start offset of the most recent successfully-started tag read. This is
    /// intentionally tracked separately from `position()` so unknown-field
    /// preservation can copy the exact original tag bytes rather than a
    /// canonicalized re-encoding of the numeric tag.
    last_tag_start: usize = 0,
    recursion_depth: u32 = 0,
    recursion_limit: u32 = 100,

    pub fn init(input: []const u8) Reader {
        return .{ .input = input };
    }

    pub fn eof(self: *const Reader) bool {
        return self.index >= self.input.len;
    }

    pub fn remaining(self: *const Reader) []const u8 {
        return self.input[self.index..];
    }

    pub fn position(self: *const Reader) usize {
        return self.index;
    }

    pub fn lastTagStart(self: *const Reader) usize {
        return self.last_tag_start;
    }

    pub fn nested(self: *const Reader, input: []const u8) Error!Reader {
        if (self.recursion_depth >= self.recursion_limit) return error.RecursionLimitExceeded;
        return .{
            .input = input,
            .recursion_depth = self.recursion_depth + 1,
            .recursion_limit = self.recursion_limit,
        };
    }

    pub fn enterRecursion(self: *Reader) Error!void {
        if (self.recursion_depth >= self.recursion_limit) return error.RecursionLimitExceeded;
        self.recursion_depth += 1;
    }

    pub fn leaveRecursion(self: *Reader) void {
        std.debug.assert(self.recursion_depth != 0);
        self.recursion_depth -= 1;
    }

    pub fn readByte(self: *Reader) Error!u8 {
        if (self.index >= self.input.len) return error.TruncatedInput;
        const b = self.input[self.index];
        self.index += 1;
        return b;
    }

    pub fn readVarint(self: *Reader) Error!u64 {
        return try readVarintAt(self.input, &self.index);
    }

    pub fn nextTag(self: *Reader) Error!?Tag {
        if (self.eof()) return null;
        const tag_start = self.index;
        self.last_tag_start = tag_start;
        const raw = try self.readVarint();
        if (self.index - tag_start > 5) return error.MalformedVarint;
        return try Tag.decode(raw);
    }

    pub fn expectWireType(tag: Tag, expected: WireType) Error!void {
        if (tag.wire_type != expected) return error.InvalidWireType;
    }

    pub fn readUInt32(self: *Reader) Error!u32 {
        return @as(u32, @truncate(try self.readVarint()));
    }

    pub fn readUInt64(self: *Reader) Error!u64 {
        return try self.readVarint();
    }

    pub fn readInt32(self: *Reader) Error!i32 {
        const value = try self.readVarint();
        return @truncate(@as(i64, @bitCast(value)));
    }

    pub fn readInt64(self: *Reader) Error!i64 {
        return @bitCast(try self.readVarint());
    }

    pub fn readSInt32(self: *Reader) Error!i32 {
        return zigZagDecode32(@as(u32, @truncate(try self.readVarint())));
    }

    pub fn readSInt64(self: *Reader) Error!i64 {
        return zigZagDecode64(try self.readUInt64());
    }

    pub fn readBool(self: *Reader) Error!bool {
        return (try self.readVarint()) != 0;
    }

    pub fn readFixed32(self: *Reader) Error!u32 {
        return try self.readRawLittle(u32);
    }

    pub fn readSFixed32(self: *Reader) Error!i32 {
        return @bitCast(try self.readFixed32());
    }

    pub fn readFixed64(self: *Reader) Error!u64 {
        return try self.readRawLittle(u64);
    }

    pub fn readSFixed64(self: *Reader) Error!i64 {
        return @bitCast(try self.readFixed64());
    }

    pub fn readFloat(self: *Reader) Error!f32 {
        return @bitCast(try self.readFixed32());
    }

    pub fn readDouble(self: *Reader) Error!f64 {
        return @bitCast(try self.readFixed64());
    }

    pub fn readBytes(self: *Reader) Error![]const u8 {
        if (self.index >= self.input.len) return error.TruncatedInput;
        const first_len_byte = self.input[self.index];
        // Most generated string/bytes/message fields in the hot benchmarks
        // have sub-128-byte payloads.  Decode that dominant one-byte length
        // locally, but leave multi-byte lengths on the canonical varint reader
        // so truncation, overflow, and malformed-varint behavior stays shared.
        const len: usize = if (first_len_byte < 0x80) blk: {
            self.index += 1;
            break :blk first_len_byte;
        } else blk: {
            const len64 = try self.readVarint();
            if (len64 > std.math.maxInt(usize)) return error.Overflow;
            break :blk @intCast(len64);
        };
        if (self.input.len - self.index < len) return error.TruncatedInput;
        const start = self.index;
        self.index += len;
        return self.input[start..self.index];
    }

    pub fn readRawLittle(self: *Reader, comptime T: type) Error!T {
        const n = @sizeOf(T);
        if (self.input.len - self.index < n) return error.TruncatedInput;
        const start = self.index;
        self.index += n;
        return std.mem.readInt(T, self.input[start..][0..n], .little);
    }

    pub fn skipValue(self: *Reader, tag: Tag) Error!void {
        switch (tag.wire_type) {
            .varint => _ = try self.readVarint(),
            .fixed64 => self.index += try self.checkedAvailable(8),
            .length_delimited => _ = try self.readBytes(),
            .fixed32 => self.index += try self.checkedAvailable(4),
            .start_group => try self.skipGroup(tag.number),
            .end_group => return error.UnsupportedWireType,
        }
    }

    pub fn readGroupBytes(self: *Reader, number: FieldNumber) Error![]const u8 {
        try self.enterRecursion();
        defer self.leaveRecursion();

        const start = self.index;
        while (true) {
            const tag = (try self.nextTag()) orelse return error.TruncatedInput;
            if (tag.wire_type == .end_group) {
                if (tag.number != number) return error.InvalidFieldNumber;
                const end = self.index - try tagSize(tag.number, tag.wire_type);
                return self.input[start..end];
            }
            try self.skipValue(tag);
        }
    }

    fn checkedAvailable(self: *Reader, len: usize) Error!usize {
        if (self.input.len - self.index < len) return error.TruncatedInput;
        return len;
    }

    fn skipGroup(self: *Reader, number: FieldNumber) Error!void {
        try self.enterRecursion();
        defer self.leaveRecursion();

        while (true) {
            const tag = (try self.nextTag()) orelse return error.TruncatedInput;
            if (tag.wire_type == .end_group) {
                if (tag.number != number) return error.InvalidFieldNumber;
                return;
            }
            try self.skipValue(tag);
        }
    }
};

pub inline fn readVarintAt(input: []const u8, index_ptr: *usize) Error!u64 {
    var index = index_ptr.*;

    if (index >= input.len) return error.TruncatedInput;
    var byte = input[index];
    index += 1;
    var result: u64 = byte & 0x7f;
    if (byte < 0x80) {
        index_ptr.* = index;
        return result;
    }

    if (index >= input.len) {
        index_ptr.* = index;
        return error.TruncatedInput;
    }
    byte = input[index];
    index += 1;
    result |= @as(u64, byte & 0x7f) << 7;
    if (byte < 0x80) {
        index_ptr.* = index;
        return result;
    }

    inline for (.{ 14, 21, 28, 35, 42, 49, 56 }) |shift| {
        if (index >= input.len) {
            index_ptr.* = index;
            return error.TruncatedInput;
        }
        byte = input[index];
        index += 1;
        result |= @as(u64, byte & 0x7f) << shift;
        if (byte < 0x80) {
            index_ptr.* = index;
            return result;
        }
    }

    if (index >= input.len) {
        index_ptr.* = index;
        return error.TruncatedInput;
    }
    byte = input[index];
    index += 1;
    result |= @as(u64, byte & 0x7f) << 63;
    if (byte < 0x80) {
        if (byte > 1) {
            index_ptr.* = index;
            return error.MalformedVarint;
        }
        index_ptr.* = index;
        return result;
    }

    index_ptr.* = index;
    return error.MalformedVarint;
}

pub inline fn readRawLittleAt(comptime T: type, input: []const u8, index_ptr: *usize) Error!T {
    const start = index_ptr.*;
    if (start > input.len or input.len - start < @sizeOf(T)) return error.TruncatedInput;
    const end = start + @sizeOf(T);
    index_ptr.* = end;
    return std.mem.readInt(T, input[start..][0..@sizeOf(T)], .little);
}

pub inline fn readBoolAt(input: []const u8, index_ptr: *usize) Error!bool {
    const start = index_ptr.*;
    if (start >= input.len) return error.TruncatedInput;
    const first = input[start];
    if (first < 0x80) {
        index_ptr.* = start + 1;
        return first != 0;
    }
    return (try readVarintAt(input, index_ptr)) != 0;
}

pub inline fn readUInt32At(input: []const u8, index_ptr: *usize) Error!u32 {
    const start = index_ptr.*;
    var index = start;

    // Generated hot paths often decode small uint32 counters.  Handle the
    // dominant one- and two-byte varints locally, but still fall back to the
    // canonical 64-bit reader for wider encodings so non-canonical payloads
    // keep the same truncation and malformed-varint behavior as Reader.readUInt32.
    if (index >= input.len) return error.TruncatedInput;
    const first = input[index];
    index += 1;
    var raw: u32 = first & 0x7f;
    if (first < 0x80) {
        index_ptr.* = index;
        return raw;
    }

    if (index >= input.len) {
        index_ptr.* = index;
        return error.TruncatedInput;
    }
    const second = input[index];
    index += 1;
    raw |= @as(u32, second & 0x7f) << 7;
    if (second < 0x80) {
        index_ptr.* = index;
        return raw;
    }

    index_ptr.* = start;
    return @truncate(try readVarintAt(input, index_ptr));
}

pub inline fn readInt32At(input: []const u8, index_ptr: *usize) Error!i32 {
    const start = index_ptr.*;
    var index = start;

    // Packed int32 streams in generated code commonly contain small positive
    // values.  Decode the one- and two-byte cases directly while delegating
    // wider encodings to the generic reader so negative int32 values, truncated
    // payloads, malformed ten-byte varints, and protobuf's 64-bit-to-32-bit
    // truncation behavior stay exactly aligned with Reader.readInt32.
    if (index >= input.len) return error.TruncatedInput;
    const first = input[index];
    index += 1;
    var raw: u32 = first & 0x7f;
    if (first < 0x80) {
        index_ptr.* = index;
        return @intCast(raw);
    }

    if (index >= input.len) {
        index_ptr.* = index;
        return error.TruncatedInput;
    }
    const second = input[index];
    index += 1;
    raw |= @as(u32, second & 0x7f) << 7;
    if (second < 0x80) {
        index_ptr.* = index;
        return @intCast(raw);
    }

    index_ptr.* = start;
    const value = try readVarintAt(input, index_ptr);
    return @truncate(@as(i64, @bitCast(value)));
}

pub inline fn readSInt32At(input: []const u8, index_ptr: *usize) Error!i32 {
    const start = index_ptr.*;
    var index = start;

    // Packed sint32 streams in generated code overwhelmingly contain small
    // deltas, which zig-zag encode to one or two bytes.  Keep those cases in
    // the caller's loop body while falling back to readVarintAt for wider or
    // malformed values so truncation, overflow, and index-advance semantics
    // remain identical to the generic varint reader.
    if (index >= input.len) return error.TruncatedInput;
    const first = input[index];
    index += 1;
    var raw: u32 = first & 0x7f;
    if (first < 0x80) {
        index_ptr.* = index;
        return zigZagDecode32(raw);
    }

    if (index >= input.len) {
        index_ptr.* = index;
        return error.TruncatedInput;
    }
    const second = input[index];
    index += 1;
    raw |= @as(u32, second & 0x7f) << 7;
    if (second < 0x80) {
        index_ptr.* = index;
        return zigZagDecode32(raw);
    }

    index_ptr.* = start;
    const value = try readVarintAt(input, index_ptr);
    return zigZagDecode32(@as(u32, @truncate(value)));
}

pub inline fn appendPackedInt32(allocator: std.mem.Allocator, list: *std.ArrayList(i32), payload: []const u8) (std.mem.Allocator.Error || Error)!void {
    const required = if (list.capacity != 0 and list.capacity - list.items.len < payload.len) try countPackedVarints(payload) else payload.len;
    try list.ensureUnusedCapacity(allocator, required);
    var index: usize = 0;
    while (index < payload.len) list.appendAssumeCapacity(try readInt32At(payload, &index));
}

pub inline fn appendPackedInt64(allocator: std.mem.Allocator, list: *std.ArrayList(i64), payload: []const u8) (std.mem.Allocator.Error || Error)!void {
    if (payload.len == 0) return;
    if (list.items.len == 0 and list.capacity == 0) {
        const count = try countPackedVarints(payload);
        const out = try allocator.alloc(i64, count);
        errdefer allocator.free(out);
        var index: usize = 0;
        for (out) |*value| value.* = @bitCast(try readVarintAt(payload, &index));
        list.* = std.ArrayList(i64).fromOwnedSlice(out);
        return;
    }

    const required = if (list.capacity != 0 and list.capacity - list.items.len < payload.len) try countPackedVarints(payload) else payload.len;
    try list.ensureUnusedCapacity(allocator, required);
    var index: usize = 0;
    while (index < payload.len) list.appendAssumeCapacity(@bitCast(try readVarintAt(payload, &index)));
}

inline fn countPackedVarints(payload: []const u8) Error!usize {
    var index: usize = 0;
    var count: usize = 0;
    while (index < payload.len) : (count += 1) _ = try readVarintAt(payload, &index);
    return count;
}

pub inline fn appendPackedBool(allocator: std.mem.Allocator, list: *std.ArrayList(bool), payload: []const u8) (std.mem.Allocator.Error || Error)!void {
    if (payload.len == 0) return;
    if (packedVarintPayloadAllSingleByte(payload)) {
        try list.ensureUnusedCapacity(allocator, payload.len);
        const out = list.addManyAsSliceAssumeCapacity(payload.len);
        for (payload, out) |byte, *value| value.* = byte != 0;
        return;
    }

    if (list.items.len == 0 and list.capacity == 0) {
        const count = try countPackedVarints(payload);
        const out = try allocator.alloc(bool, count);
        errdefer allocator.free(out);
        var index: usize = 0;
        for (out) |*value| value.* = (try readVarintAt(payload, &index)) != 0;
        list.* = std.ArrayList(bool).fromOwnedSlice(out);
        return;
    }

    try list.ensureUnusedCapacity(allocator, payload.len);
    var index: usize = 0;
    while (index < payload.len) list.appendAssumeCapacity((try readVarintAt(payload, &index)) != 0);
}

fn packedVarintPayloadAllSingleByte(payload: []const u8) bool {
    const vector_len = std.simd.suggestVectorLength(u8) orelse 0;
    if (vector_len >= 8) {
        const V = @Vector(vector_len, u8);
        var index: usize = 0;
        const continuation_bit: V = @splat(0x80);
        while (index + vector_len <= payload.len) : (index += vector_len) {
            const chunk: V = payload[index..][0..vector_len].*;
            if (@reduce(.Or, chunk >= continuation_bit)) return false;
        }
        for (payload[index..]) |byte| {
            if (byte >= 0x80) return false;
        }
        return true;
    }
    for (payload) |byte| {
        if (byte >= 0x80) return false;
    }
    return true;
}

pub inline fn packedEnumAllSingleByte(payload: []const u8) bool {
    return packedVarintPayloadAllSingleByte(payload);
}

pub inline fn appendPackedUInt32(allocator: std.mem.Allocator, list: *std.ArrayList(u32), payload: []const u8) (std.mem.Allocator.Error || Error)!void {
    if (payload.len == 0) return;
    if (list.items.len == 0 and list.capacity == 0) {
        const count = try countPackedVarints(payload);
        const out = try allocator.alloc(u32, count);
        errdefer allocator.free(out);
        var index: usize = 0;
        for (out) |*value| value.* = @as(u32, @truncate(try readVarintAt(payload, &index)));
        list.* = std.ArrayList(u32).fromOwnedSlice(out);
        return;
    }

    const required = if (list.capacity != 0 and list.capacity - list.items.len < payload.len) try countPackedVarints(payload) else payload.len;
    try list.ensureUnusedCapacity(allocator, required);
    var index: usize = 0;
    while (index < payload.len) list.appendAssumeCapacity(@as(u32, @truncate(try readVarintAt(payload, &index))));
}

pub inline fn appendPackedUInt64(allocator: std.mem.Allocator, list: *std.ArrayList(u64), payload: []const u8) (std.mem.Allocator.Error || Error)!void {
    if (payload.len == 0) return;
    if (list.items.len == 0 and list.capacity == 0) {
        const count = try countPackedVarints(payload);
        const out = try allocator.alloc(u64, count);
        errdefer allocator.free(out);
        var index: usize = 0;
        for (out) |*value| value.* = try readVarintAt(payload, &index);
        list.* = std.ArrayList(u64).fromOwnedSlice(out);
        return;
    }

    const required = if (list.capacity != 0 and list.capacity - list.items.len < payload.len) try countPackedVarints(payload) else payload.len;
    try list.ensureUnusedCapacity(allocator, required);
    var index: usize = 0;
    while (index < payload.len) list.appendAssumeCapacity(try readVarintAt(payload, &index));
}

pub inline fn appendPackedSInt32(allocator: std.mem.Allocator, list: *std.ArrayList(i32), payload: []const u8) (std.mem.Allocator.Error || Error)!void {
    if (payload.len == 0) return;
    if (list.items.len == 0 and list.capacity == 0) {
        const count = try countPackedVarints(payload);
        const out = try allocator.alloc(i32, count);
        errdefer allocator.free(out);
        var index: usize = 0;
        for (out) |*value| value.* = zigZagDecode32(@as(u32, @truncate(try readVarintAt(payload, &index))));
        list.* = std.ArrayList(i32).fromOwnedSlice(out);
        return;
    }

    const required = if (list.capacity != 0 and list.capacity - list.items.len < payload.len) try countPackedVarints(payload) else payload.len;
    try list.ensureUnusedCapacity(allocator, required);
    var index: usize = 0;
    while (index < payload.len) list.appendAssumeCapacity(zigZagDecode32(@as(u32, @truncate(try readVarintAt(payload, &index)))));
}

pub inline fn appendPackedSInt64(allocator: std.mem.Allocator, list: *std.ArrayList(i64), payload: []const u8) (std.mem.Allocator.Error || Error)!void {
    if (payload.len == 0) return;
    if (list.items.len == 0 and list.capacity == 0) {
        const count = try countPackedVarints(payload);
        const out = try allocator.alloc(i64, count);
        errdefer allocator.free(out);
        var index: usize = 0;
        for (out) |*value| value.* = zigZagDecode64(try readVarintAt(payload, &index));
        list.* = std.ArrayList(i64).fromOwnedSlice(out);
        return;
    }

    const required = if (list.capacity != 0 and list.capacity - list.items.len < payload.len) try countPackedVarints(payload) else payload.len;
    try list.ensureUnusedCapacity(allocator, required);
    var index: usize = 0;
    while (index < payload.len) list.appendAssumeCapacity(zigZagDecode64(try readVarintAt(payload, &index)));
}

pub fn fieldRawSlice(input: []const u8, start: usize, reader_after_value: *const Reader) []const u8 {
    return input[start..reader_after_value.index];
}

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

    const raw_fields = [_][]const u8{ writer.slice()[0..1], &.{}, writer.slice()[1..], &noncanonical_field_16 };
    try std.testing.expectEqual(@as(usize, 1), try rawFieldCountByNumber(&raw_fields, 15));
    try std.testing.expectEqual(@as(usize, 1), rawFieldCountByNumberAssumeValid(&raw_fields, 15));
    try std.testing.expectEqual(@as(usize, 2), rawFieldCountByNumberAssumeValid(&raw_fields, 16));
    try std.testing.expect(rawFieldHasNumberAssumeValid(&raw_fields, 16));
    try std.testing.expect(!rawFieldHasNumberAssumeValid(&raw_fields, 17));
    const matched = try rawFieldsByNumberAlloc(std.testing.allocator, &raw_fields, 16);
    defer std.testing.allocator.free(matched);
    try std.testing.expectEqual(@as(usize, 2), matched.len);
    try std.testing.expectEqualSlices(u8, writer.slice()[1..], matched[0]);
    try std.testing.expectEqualSlices(u8, &noncanonical_field_16, matched[1]);
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
