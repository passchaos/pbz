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

pub fn zigZagDecode32(value: u32) i32 {
    const half: i32 = @intCast(value >> 1);
    const sign: i32 = -@as(i32, @intCast(value & 1));
    return half ^ sign;
}

pub fn zigZagEncode64(value: i64) u64 {
    return @as(u64, @bitCast((value << 1) ^ (value >> 63)));
}

pub fn zigZagDecode64(value: u64) i64 {
    const half: i64 = @intCast(value >> 1);
    const sign: i64 = -@as(i64, @intCast(value & 1));
    return half ^ sign;
}

pub fn encodedVarintSize(value: u64) usize {
    var v = value;
    var n: usize = 1;
    while (v >= 0x80) : (n += 1) v >>= 7;
    return n;
}

pub fn tagSize(number: FieldNumber, wire_type: WireType) Error!usize {
    return encodedVarintSize(try (Tag{ .number = number, .wire_type = wire_type }).encode());
}

pub const Writer = struct {
    allocator: std.mem.Allocator,
    bytes: std.ArrayList(u8) = .empty,

    pub fn init(allocator: std.mem.Allocator) Writer {
        return .{ .allocator = allocator };
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

    pub fn appendSlice(self: *Writer, data: []const u8) std.mem.Allocator.Error!void {
        try self.bytes.appendSlice(self.allocator, data);
    }

    pub fn writeVarint(self: *Writer, value: u64) std.mem.Allocator.Error!void {
        var v = value;
        while (v >= 0x80) {
            try self.appendByte(@as(u8, @intCast(v & 0x7f)) | 0x80);
            v >>= 7;
        }
        try self.appendByte(@intCast(v));
    }

    pub fn writeTag(self: *Writer, number: FieldNumber, wire_type: WireType) (std.mem.Allocator.Error || Error)!void {
        try self.writeVarint(try (Tag{ .number = number, .wire_type = wire_type }).encode());
    }

    pub fn writeUInt32(self: *Writer, number: FieldNumber, value: u32) !void {
        try self.writeTag(number, .varint);
        try self.writeVarint(value);
    }

    pub fn writeUInt64(self: *Writer, number: FieldNumber, value: u64) !void {
        try self.writeTag(number, .varint);
        try self.writeVarint(value);
    }

    pub fn writeInt32(self: *Writer, number: FieldNumber, value: i32) !void {
        try self.writeTag(number, .varint);
        try self.writeVarint(@as(u64, @bitCast(@as(i64, value))));
    }

    pub fn writeInt64(self: *Writer, number: FieldNumber, value: i64) !void {
        try self.writeTag(number, .varint);
        try self.writeVarint(@as(u64, @bitCast(value)));
    }

    pub fn writeSInt32(self: *Writer, number: FieldNumber, value: i32) !void {
        try self.writeTag(number, .varint);
        try self.writeVarint(zigZagEncode32(value));
    }

    pub fn writeSInt64(self: *Writer, number: FieldNumber, value: i64) !void {
        try self.writeTag(number, .varint);
        try self.writeVarint(zigZagEncode64(value));
    }

    pub fn writeBool(self: *Writer, number: FieldNumber, value: bool) !void {
        try self.writeTag(number, .varint);
        try self.writeVarint(if (value) 1 else 0);
    }

    pub fn writeFixed32(self: *Writer, number: FieldNumber, value: u32) !void {
        try self.writeTag(number, .fixed32);
        try self.writeRawLittle(u32, value);
    }

    pub fn writeSFixed32(self: *Writer, number: FieldNumber, value: i32) !void {
        try self.writeFixed32(number, @bitCast(value));
    }

    pub fn writeFixed64(self: *Writer, number: FieldNumber, value: u64) !void {
        try self.writeTag(number, .fixed64);
        try self.writeRawLittle(u64, value);
    }

    pub fn writeSFixed64(self: *Writer, number: FieldNumber, value: i64) !void {
        try self.writeFixed64(number, @bitCast(value));
    }

    pub fn writeFloat(self: *Writer, number: FieldNumber, value: f32) !void {
        try self.writeFixed32(number, @bitCast(value));
    }

    pub fn writeDouble(self: *Writer, number: FieldNumber, value: f64) !void {
        try self.writeFixed64(number, @bitCast(value));
    }

    pub fn writeBytes(self: *Writer, number: FieldNumber, value: []const u8) !void {
        try self.writeTag(number, .length_delimited);
        try self.writeVarint(value.len);
        try self.appendSlice(value);
    }

    pub fn writeString(self: *Writer, number: FieldNumber, value: []const u8) !void {
        try self.writeBytes(number, value);
    }

    pub fn writeMessage(self: *Writer, number: FieldNumber, encoded_message: []const u8) !void {
        try self.writeBytes(number, encoded_message);
    }

    pub fn writePackedVarints(self: *Writer, number: FieldNumber, values: []const u64) !void {
        var packed_writer = Writer.init(self.allocator);
        defer packed_writer.deinit();
        for (values) |value| try packed_writer.writeVarint(value);
        try self.writeBytes(number, packed_writer.slice());
    }

    pub fn writeRawLittle(self: *Writer, comptime T: type, value: T) std.mem.Allocator.Error!void {
        var buf: [@sizeOf(T)]u8 = undefined;
        std.mem.writeInt(T, &buf, value, .little);
        try self.appendSlice(&buf);
    }
};

pub const Reader = struct {
    input: []const u8,
    index: usize = 0,
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

    pub fn readByte(self: *Reader) Error!u8 {
        if (self.index >= self.input.len) return error.TruncatedInput;
        const b = self.input[self.index];
        self.index += 1;
        return b;
    }

    pub fn readVarint(self: *Reader) Error!u64 {
        var result: u64 = 0;
        var shift: u6 = 0;
        var count: usize = 0;
        while (count < 10) : (count += 1) {
            const byte = try self.readByte();
            result |= (@as(u64, byte & 0x7f) << shift);
            if ((byte & 0x80) == 0) return result;
            if (shift == 63) return error.MalformedVarint;
            shift += 7;
        }
        return error.MalformedVarint;
    }

    pub fn nextTag(self: *Reader) Error!?Tag {
        if (self.eof()) return null;
        return try Tag.decode(try self.readVarint());
    }

    pub fn expectWireType(tag: Tag, expected: WireType) Error!void {
        if (tag.wire_type != expected) return error.InvalidWireType;
    }

    pub fn readUInt32(self: *Reader) Error!u32 {
        const value = try self.readVarint();
        if (value > std.math.maxInt(u32)) return error.Overflow;
        return @intCast(value);
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
        return zigZagDecode32(try self.readUInt32());
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
        const len64 = try self.readVarint();
        if (len64 > std.math.maxInt(usize)) return error.Overflow;
        const len: usize = @intCast(len64);
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
        if (self.recursion_depth >= self.recursion_limit) return error.RecursionLimitExceeded;
        self.recursion_depth += 1;
        defer self.recursion_depth -= 1;

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
        if (self.recursion_depth >= self.recursion_limit) return error.RecursionLimitExceeded;
        self.recursion_depth += 1;
        defer self.recursion_depth -= 1;

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
