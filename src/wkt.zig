const std = @import("std");
const wire = @import("wire.zig");

pub const Timestamp = struct {
    seconds: i64 = 0,
    nanos: i32 = 0,

    pub fn encode(self: Timestamp, allocator: std.mem.Allocator) ![]u8 {
        var writer = wire.Writer.init(allocator);
        errdefer writer.deinit();
        if (self.seconds != 0) try writer.writeInt64(1, self.seconds);
        if (self.nanos != 0) try writer.writeInt32(2, self.nanos);
        return try writer.toOwnedSlice();
    }

    pub fn decode(bytes: []const u8) !Timestamp {
        var out = Timestamp{};
        var reader = wire.Reader.init(bytes);
        while (try reader.nextTag()) |tag| {
            switch (tag.number) {
                1 => {
                    try wire.Reader.expectWireType(tag, .varint);
                    out.seconds = try reader.readInt64();
                },
                2 => {
                    try wire.Reader.expectWireType(tag, .varint);
                    out.nanos = try reader.readInt32();
                },
                else => try reader.skipValue(tag),
            }
        }
        return out;
    }

    pub fn jsonStringifyAlloc(self: Timestamp, allocator: std.mem.Allocator) ![]u8 {
        var out: std.Io.Writer.Allocating = .init(allocator);
        errdefer out.deinit();
        try self.jsonStringify(&out.writer);
        return try out.toOwnedSlice();
    }

    pub fn jsonStringify(self: Timestamp, writer: *std.Io.Writer) !void {
        if (self.seconds < 0) return error.UnsupportedNegativeTimestamp;
        const day_seconds: i64 = 24 * 60 * 60;
        const days: u64 = @intCast(@divTrunc(self.seconds, day_seconds));
        const seconds_of_day: u32 = @intCast(@mod(self.seconds, day_seconds));
        const date = civilFromDays(days);
        const hour = seconds_of_day / 3600;
        const minute = (seconds_of_day % 3600) / 60;
        const second = seconds_of_day % 60;
        try writer.print("\"{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}", .{ @as(u32, @intCast(date.year)), date.month, date.day, hour, minute, second });
        if (self.nanos != 0) {
            var frac: [9]u8 = undefined;
            _ = std.fmt.bufPrint(&frac, "{d:0>9}", .{@abs(self.nanos)}) catch unreachable;
            var len: usize = frac.len;
            while (len > 0 and frac[len - 1] == '0') len -= 1;
            try writer.print(".{s}", .{frac[0..len]});
        }
        try writer.writeAll("Z\"");
    }

    pub fn jsonParse(text: []const u8) !Timestamp {
        const unquoted = if (text.len >= 2 and text[0] == '"' and text[text.len - 1] == '"') text[1 .. text.len - 1] else text;
        if (unquoted.len < 20 or unquoted[4] != '-' or unquoted[7] != '-' or unquoted[10] != 'T' or unquoted[13] != ':' or unquoted[16] != ':') return error.InvalidTimestamp;
        const year = try std.fmt.parseInt(i32, unquoted[0..4], 10);
        const month = try std.fmt.parseInt(u8, unquoted[5..7], 10);
        const day = try std.fmt.parseInt(u8, unquoted[8..10], 10);
        const hour = try std.fmt.parseInt(u8, unquoted[11..13], 10);
        const minute = try std.fmt.parseInt(u8, unquoted[14..16], 10);
        const second = try std.fmt.parseInt(u8, unquoted[17..19], 10);
        var index: usize = 19;
        var nanos: i32 = 0;
        if (index < unquoted.len and unquoted[index] == '.') {
            index += 1;
            const start = index;
            while (index < unquoted.len and std.ascii.isDigit(unquoted[index])) index += 1;
            if (index == start or index - start > 9) return error.InvalidTimestamp;
            var scale: i32 = 100_000_000;
            for (unquoted[start..index]) |c| {
                nanos += @as(i32, @intCast(c - '0')) * scale;
                scale = @divTrunc(scale, 10);
            }
        }
        if (index >= unquoted.len or unquoted[index] != 'Z' or index + 1 != unquoted.len) return error.InvalidTimestamp;
        return .{
            .seconds = @intCast(daysFromCivil(year, month, day) * 86_400 + @as(i64, hour) * 3600 + @as(i64, minute) * 60 + @as(i64, second)),
            .nanos = nanos,
        };
    }
};

const Date = struct { year: i32, month: u8, day: u8 };

fn civilFromDays(z_in: u64) Date {
    var z: i64 = @intCast(z_in);
    z += 719468;
    const era = @divFloor(z, 146097);
    const doe: u32 = @intCast(z - era * 146097);
    const yoe: u32 = @intCast((doe - doe / 1460 + doe / 36524 - doe / 146096) / 365);
    var y: i32 = @intCast(yoe);
    y += @intCast(era * 400);
    const doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    const mp = (5 * doy + 2) / 153;
    const d = doy - (153 * mp + 2) / 5 + 1;
    const m = if (mp < 10) mp + 3 else mp - 9;
    y += if (m <= 2) 1 else 0;
    return .{ .year = y, .month = @intCast(m), .day = @intCast(d) };
}

fn daysFromCivil(year: i32, month: u8, day: u8) i64 {
    var y = year;
    const m: i32 = month;
    y -= if (m <= 2) 1 else 0;
    const era = @divFloor(y, 400);
    const yoe: u32 = @intCast(y - era * 400);
    const adjust: i32 = if (m > 2) -3 else 9;
    const mp: i32 = m + adjust;
    const doy: u32 = @intCast(@divTrunc(153 * mp + 2, 5) + day - 1);
    const doe: u32 = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    return era * 146097 + @as(i64, doe) - 719468;
}

test "timestamp wire and json roundtrip" {
    const allocator = std.testing.allocator;
    const ts = Timestamp{ .seconds = 1_577_836_800, .nanos = 123_000_000 };
    const bytes = try ts.encode(allocator);
    defer allocator.free(bytes);
    const decoded = try Timestamp.decode(bytes);
    try std.testing.expectEqual(ts.seconds, decoded.seconds);
    try std.testing.expectEqual(ts.nanos, decoded.nanos);

    const json = try ts.jsonStringifyAlloc(allocator);
    defer allocator.free(json);
    try std.testing.expectEqualSlices(u8, "\"2020-01-01T00:00:00.123Z\"", json);
    const parsed = try Timestamp.jsonParse(json);
    try std.testing.expectEqual(ts.seconds, parsed.seconds);
    try std.testing.expectEqual(ts.nanos, parsed.nanos);
}
