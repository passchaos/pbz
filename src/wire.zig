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

pub inline fn encodedVarintSize(value: u64) usize {
    if (value < (1 << 7)) return 1;
    if (value < (1 << 14)) return 2;
    if (value < (1 << 21)) return 3;
    return (@as(usize, 64 - @clz(value)) + 6) / 7;
}

pub fn tagSize(number: FieldNumber, wire_type: WireType) Error!usize {
    return encodedVarintSize(try (Tag{ .number = number, .wire_type = wire_type }).encode());
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

inline fn writeVarintToBuffer(buffer: []u8, value: u64) usize {
    var v = value;
    var len: usize = 0;
    while (v >= 0x80) {
        buffer[len] = @as(u8, @intCast(v & 0x7f)) | 0x80;
        len += 1;
        v >>= 7;
    }
    buffer[len] = @intCast(v);
    return len + 1;
}

pub inline fn writeVarintToSlice(buffer: []u8, index: *usize, value: u64) void {
    index.* += writeVarintToBuffer(buffer[index.*..], value);
}

pub inline fn writeRawLittleToSlice(comptime T: type, buffer: []u8, index: *usize, value: T) void {
    const start = index.*;
    index.* = start + @sizeOf(T);
    std.mem.writeInt(T, buffer[start..][0..@sizeOf(T)], value, .little);
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

    pub fn next(self: *PackedUInt64Iterator) Error!?u64 {
        if (self.index >= self.payload.len) return null;
        return try readVarintAt(self.payload, &self.index);
    }
};

pub fn packedUInt64FieldIterator(bytes: []const u8, number: FieldNumber) Error!?PackedUInt64Iterator {
    var reader = Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        if (tag.number == number) {
            if (tag.wire_type == .length_delimited) return .{ .payload = try reader.readBytes() };
            if (tag.wire_type == .varint) {
                const payload_start = reader.position();
                _ = try reader.readUInt64();
                return .{ .payload = bytes[payload_start..reader.position()] };
            }
            return error.InvalidWireType;
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
        var v = value;
        if (v < 0x80) return try self.appendByte(@intCast(v));
        var buf: [10]u8 = undefined;
        var len: usize = 0;
        while (v >= 0x80) {
            buf[len] = @as(u8, @intCast(v & 0x7f)) | 0x80;
            len += 1;
            v >>= 7;
        }
        buf[len] = @intCast(v);
        len += 1;
        try self.appendSlice(buf[0..len]);
    }

    pub fn writeVarintAssumeCapacity(self: *Writer, value: u64) void {
        var v = value;
        while (v >= 0x80) {
            self.appendByteAssumeCapacity(@as(u8, @intCast(v & 0x7f)) | 0x80);
            v >>= 7;
        }
        self.appendByteAssumeCapacity(@intCast(v));
    }

    pub fn writeTag(self: *Writer, number: FieldNumber, wire_type: WireType) (std.mem.Allocator.Error || Error)!void {
        try self.writeVarint(try (Tag{ .number = number, .wire_type = wire_type }).encode());
    }

    pub fn writeTagAssumeCapacity(self: *Writer, number: FieldNumber, wire_type: WireType) void {
        self.writeVarintAssumeCapacity((@as(u64, number) << 3) | @intFromEnum(wire_type));
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
        try self.writeVarint(if (value) 1 else 0);
    }

    pub fn writeBoolAssumeCapacity(self: *Writer, number: FieldNumber, value: bool) void {
        self.writeTagAssumeCapacity(number, .varint);
        self.writeVarintAssumeCapacity(if (value) 1 else 0);
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
        try self.writeVarint(value.len);
        try self.appendSlice(value);
    }

    pub fn writeBytesAssumeCapacity(self: *Writer, number: FieldNumber, value: []const u8) void {
        self.writeTagAssumeCapacity(number, .length_delimited);
        self.writeVarintAssumeCapacity(value.len);
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
        return try readVarintAt(self.input, &self.index);
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

pub inline fn readVarintAt(input: []const u8, index_ptr: *usize) Error!u64 {
    var index = index_ptr.*;

    if (index >= input.len) return error.TruncatedInput;
    const first = input[index];
    index += 1;
    if (first < 0x80) {
        index_ptr.* = index;
        return first;
    }

    if (index >= input.len) {
        index_ptr.* = index;
        return error.TruncatedInput;
    }
    const second = input[index];
    index += 1;
    var result = @as(u64, first & 0x7f) | (@as(u64, second & 0x7f) << 7);
    if (second < 0x80) {
        index_ptr.* = index;
        return result;
    }

    var shift: u6 = 14;
    var count: usize = 2;
    while (count < 10) : (count += 1) {
        if (index >= input.len) {
            index_ptr.* = index;
            return error.TruncatedInput;
        }
        const byte = input[index];
        index += 1;
        result |= (@as(u64, byte & 0x7f) << shift);
        if ((byte & 0x80) == 0) {
            index_ptr.* = index;
            return result;
        }
        if (shift == 63) {
            index_ptr.* = index;
            return error.MalformedVarint;
        }
        shift += 7;
    }
    index_ptr.* = index;
    return error.MalformedVarint;
}

pub inline fn appendPackedInt32(allocator: std.mem.Allocator, list: *std.ArrayList(i32), payload: []const u8) (std.mem.Allocator.Error || Error)!void {
    const required = if (list.capacity != 0 and list.capacity - list.items.len < payload.len) try countPackedVarints(payload) else payload.len;
    try list.ensureUnusedCapacity(allocator, required);
    var index: usize = 0;
    while (index < payload.len) {
        const value = try readVarintAt(payload, &index);
        list.appendAssumeCapacity(@truncate(@as(i64, @bitCast(value))));
    }
}

inline fn countPackedVarints(payload: []const u8) Error!usize {
    var index: usize = 0;
    var count: usize = 0;
    while (index < payload.len) : (count += 1) _ = try readVarintAt(payload, &index);
    return count;
}

pub inline fn appendPackedBool(allocator: std.mem.Allocator, list: *std.ArrayList(bool), payload: []const u8) (std.mem.Allocator.Error || Error)!void {
    if (payload.len == 0) return;
    var all_single_byte = true;
    for (payload) |byte| {
        if (byte >= 0x80) {
            all_single_byte = false;
            break;
        }
    }
    if (all_single_byte) {
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

pub inline fn appendPackedUInt32(allocator: std.mem.Allocator, list: *std.ArrayList(u32), payload: []const u8) (std.mem.Allocator.Error || Error)!void {
    if (payload.len == 0) return;
    if (list.items.len == 0 and list.capacity == 0) {
        const count = try countPackedVarints(payload);
        const out = try allocator.alloc(u32, count);
        errdefer allocator.free(out);
        var index: usize = 0;
        for (out) |*value| {
            const raw = try readVarintAt(payload, &index);
            if (raw > std.math.maxInt(u32)) return error.Overflow;
            value.* = @intCast(raw);
        }
        list.* = std.ArrayList(u32).fromOwnedSlice(out);
        return;
    }

    const required = if (list.capacity != 0 and list.capacity - list.items.len < payload.len) try countPackedVarints(payload) else payload.len;
    try list.ensureUnusedCapacity(allocator, required);
    var index: usize = 0;
    while (index < payload.len) {
        const raw = try readVarintAt(payload, &index);
        if (raw > std.math.maxInt(u32)) return error.Overflow;
        list.appendAssumeCapacity(@intCast(raw));
    }
}

pub inline fn appendPackedUInt64(allocator: std.mem.Allocator, list: *std.ArrayList(u64), payload: []const u8) (std.mem.Allocator.Error || Error)!void {
    if (payload.len == 0) return;
    try list.ensureUnusedCapacity(allocator, payload.len);
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
        for (out) |*value| {
            const raw = try readVarintAt(payload, &index);
            if (raw > std.math.maxInt(u32)) return error.Overflow;
            value.* = zigZagDecode32(@intCast(raw));
        }
        list.* = std.ArrayList(i32).fromOwnedSlice(out);
        return;
    }

    const required = if (list.capacity != 0 and list.capacity - list.items.len < payload.len) try countPackedVarints(payload) else payload.len;
    try list.ensureUnusedCapacity(allocator, required);
    var index: usize = 0;
    while (index < payload.len) {
        const raw = try readVarintAt(payload, &index);
        if (raw > std.math.maxInt(u32)) return error.Overflow;
        list.appendAssumeCapacity(zigZagDecode32(@intCast(raw)));
    }
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
