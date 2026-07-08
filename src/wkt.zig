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
        const day_seconds: i64 = 24 * 60 * 60;
        const days = @divFloor(self.seconds, day_seconds);
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

fn civilFromDays(z_in: i64) Date {
    var z: i64 = z_in;
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

test "timestamp json handles pre epoch times" {
    const allocator = std.testing.allocator;
    const ts = Timestamp{ .seconds = -1, .nanos = 0 };
    const json = try ts.jsonStringifyAlloc(allocator);
    defer allocator.free(json);
    try std.testing.expectEqualSlices(u8, "\"1969-12-31T23:59:59Z\"", json);
    const parsed = try Timestamp.jsonParse(json);
    try std.testing.expectEqual(@as(i64, -1), parsed.seconds);
    try std.testing.expectEqual(@as(i32, 0), parsed.nanos);
}

pub const Duration = struct {
    seconds: i64 = 0,
    nanos: i32 = 0,

    pub fn encode(self: Duration, allocator: std.mem.Allocator) ![]u8 {
        var writer = wire.Writer.init(allocator);
        errdefer writer.deinit();
        if (self.seconds != 0) try writer.writeInt64(1, self.seconds);
        if (self.nanos != 0) try writer.writeInt32(2, self.nanos);
        return try writer.toOwnedSlice();
    }

    pub fn decode(bytes: []const u8) !Duration {
        var out = Duration{};
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

    pub fn jsonStringifyAlloc(self: Duration, allocator: std.mem.Allocator) ![]u8 {
        var out: std.Io.Writer.Allocating = .init(allocator);
        errdefer out.deinit();
        try self.jsonStringify(&out.writer);
        return try out.toOwnedSlice();
    }

    pub fn jsonStringify(self: Duration, writer: *std.Io.Writer) !void {
        try writer.writeAll("\"");
        if (self.seconds < 0 or self.nanos < 0) try writer.writeAll("-");
        try writer.print("{d}", .{@abs(self.seconds)});
        if (self.nanos != 0) {
            var frac: [9]u8 = undefined;
            _ = std.fmt.bufPrint(&frac, "{d:0>9}", .{@abs(self.nanos)}) catch unreachable;
            var len: usize = frac.len;
            while (len > 0 and frac[len - 1] == '0') len -= 1;
            try writer.print(".{s}", .{frac[0..len]});
        }
        try writer.writeAll("s\"");
    }

    pub fn jsonParse(text: []const u8) !Duration {
        const unquoted = if (text.len >= 2 and text[0] == '"' and text[text.len - 1] == '"') text[1 .. text.len - 1] else text;
        if (unquoted.len < 2 or unquoted[unquoted.len - 1] != 's') return error.InvalidDuration;
        var body = unquoted[0 .. unquoted.len - 1];
        const negative = body.len != 0 and body[0] == '-';
        if (negative) body = body[1..];
        const dot = std.mem.indexOfScalar(u8, body, '.');
        const sec_text = if (dot) |idx| body[0..idx] else body;
        var seconds = try std.fmt.parseInt(i64, sec_text, 10);
        var nanos: i32 = 0;
        if (dot) |idx| {
            const frac = body[idx + 1 ..];
            if (frac.len == 0 or frac.len > 9) return error.InvalidDuration;
            var scale: i32 = 100_000_000;
            for (frac) |c| {
                if (!std.ascii.isDigit(c)) return error.InvalidDuration;
                nanos += @as(i32, @intCast(c - '0')) * scale;
                scale = @divTrunc(scale, 10);
            }
        }
        if (negative) {
            seconds = -seconds;
            nanos = -nanos;
        }
        return .{ .seconds = seconds, .nanos = nanos };
    }
};

test "duration wire and json roundtrip" {
    const allocator = std.testing.allocator;
    const duration = Duration{ .seconds = -3, .nanos = -250_000_000 };
    const bytes = try duration.encode(allocator);
    defer allocator.free(bytes);
    const decoded = try Duration.decode(bytes);
    try std.testing.expectEqual(duration.seconds, decoded.seconds);
    try std.testing.expectEqual(duration.nanos, decoded.nanos);

    const json = try duration.jsonStringifyAlloc(allocator);
    defer allocator.free(json);
    try std.testing.expectEqualSlices(u8, "\"-3.25s\"", json);
    const parsed = try Duration.jsonParse(json);
    try std.testing.expectEqual(duration.seconds, parsed.seconds);
    try std.testing.expectEqual(duration.nanos, parsed.nanos);
}

pub const FieldMask = struct {
    paths: []const []const u8 = &.{},

    pub fn encode(self: FieldMask, allocator: std.mem.Allocator) ![]u8 {
        var writer = wire.Writer.init(allocator);
        errdefer writer.deinit();
        for (self.paths) |path| try writer.writeString(1, path);
        return try writer.toOwnedSlice();
    }

    pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) ![][]const u8 {
        var paths: std.ArrayList([]const u8) = .empty;
        errdefer paths.deinit(allocator);
        var reader = wire.Reader.init(bytes);
        while (try reader.nextTag()) |tag| {
            if (tag.number == 1) {
                try wire.Reader.expectWireType(tag, .length_delimited);
                try paths.append(allocator, try allocator.dupe(u8, try reader.readBytes()));
            } else try reader.skipValue(tag);
        }
        return try paths.toOwnedSlice(allocator);
    }

    pub fn jsonStringifyAlloc(self: FieldMask, allocator: std.mem.Allocator) ![]u8 {
        var out: std.Io.Writer.Allocating = .init(allocator);
        errdefer out.deinit();
        try self.jsonStringify(&out.writer);
        return try out.toOwnedSlice();
    }

    pub fn jsonStringify(self: FieldMask, writer: *std.Io.Writer) !void {
        try writer.writeAll("\"");
        for (self.paths, 0..) |path, index| {
            if (index != 0) try writer.writeAll(",");
            try writeLowerCamelPath(path, writer);
        }
        try writer.writeAll("\"");
    }

    pub fn jsonParse(allocator: std.mem.Allocator, text: []const u8) ![][]const u8 {
        const unquoted = if (text.len >= 2 and text[0] == '"' and text[text.len - 1] == '"') text[1 .. text.len - 1] else text;
        var paths: std.ArrayList([]const u8) = .empty;
        errdefer {
            for (paths.items) |path| allocator.free(path);
            paths.deinit(allocator);
        }
        var it = std.mem.splitScalar(u8, unquoted, ',');
        while (it.next()) |part| {
            try paths.append(allocator, try lowerCamelToSnake(allocator, part));
        }
        return try paths.toOwnedSlice(allocator);
    }
};

fn writeLowerCamelPath(path: []const u8, writer: *std.Io.Writer) !void {
    var upper_next = false;
    for (path) |c| {
        if (c == '_') {
            upper_next = true;
        } else if (upper_next) {
            try writer.writeByte(std.ascii.toUpper(c));
            upper_next = false;
        } else try writer.writeByte(c);
    }
}

fn lowerCamelToSnake(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    for (text) |c| {
        if (std.ascii.isUpper(c)) {
            if (out.items.len != 0) try out.append(allocator, '_');
            try out.append(allocator, std.ascii.toLower(c));
        } else try out.append(allocator, c);
    }
    return try out.toOwnedSlice(allocator);
}

test "field mask wire and json helpers" {
    const allocator = std.testing.allocator;
    const paths = [_][]const u8{ "foo_bar", "baz.qux_value" };
    const mask = FieldMask{ .paths = &paths };
    const bytes = try mask.encode(allocator);
    defer allocator.free(bytes);
    const decoded = try FieldMask.decode(allocator, bytes);
    defer {
        for (decoded) |path| allocator.free(path);
        allocator.free(decoded);
    }
    try std.testing.expectEqualSlices(u8, paths[0], decoded[0]);
    try std.testing.expectEqualSlices(u8, paths[1], decoded[1]);

    const json = try mask.jsonStringifyAlloc(allocator);
    defer allocator.free(json);
    try std.testing.expectEqualSlices(u8, "\"fooBar,baz.quxValue\"", json);
    const parsed = try FieldMask.jsonParse(allocator, json);
    defer {
        for (parsed) |path| allocator.free(path);
        allocator.free(parsed);
    }
    try std.testing.expectEqualSlices(u8, paths[0], parsed[0]);
    try std.testing.expectEqualSlices(u8, paths[1], parsed[1]);
}

pub const Any = struct {
    type_url: []const u8 = "",
    value: []const u8 = "",

    pub fn encode(self: Any, allocator: std.mem.Allocator) ![]u8 {
        var writer = wire.Writer.init(allocator);
        errdefer writer.deinit();
        if (self.type_url.len != 0) try writer.writeString(1, self.type_url);
        if (self.value.len != 0) try writer.writeBytes(2, self.value);
        return try writer.toOwnedSlice();
    }

    pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) !Any {
        var out = Any{};
        var reader = wire.Reader.init(bytes);
        while (try reader.nextTag()) |tag| {
            switch (tag.number) {
                1 => {
                    try wire.Reader.expectWireType(tag, .length_delimited);
                    out.type_url = try allocator.dupe(u8, try reader.readBytes());
                },
                2 => {
                    try wire.Reader.expectWireType(tag, .length_delimited);
                    out.value = try allocator.dupe(u8, try reader.readBytes());
                },
                else => try reader.skipValue(tag),
            }
        }
        return out;
    }

    pub fn deinit(self: *Any, allocator: std.mem.Allocator) void {
        if (self.type_url.len != 0) allocator.free(self.type_url);
        if (self.value.len != 0) allocator.free(self.value);
        self.* = undefined;
    }

    pub fn jsonStringifyAlloc(self: Any, allocator: std.mem.Allocator) ![]u8 {
        var out: std.Io.Writer.Allocating = .init(allocator);
        errdefer out.deinit();
        try self.jsonStringify(&out.writer);
        return try out.toOwnedSlice();
    }

    pub fn jsonStringify(self: Any, writer: *std.Io.Writer) !void {
        try writer.writeAll("{\"@type\":");
        try std.json.Stringify.value(self.type_url, .{}, writer);
        try writer.writeAll(",\"value\":\"");
        try std.base64.standard.Encoder.encodeWriter(writer, self.value);
        try writer.writeAll("\"}");
    }
};

test "any wire and json helpers" {
    const allocator = std.testing.allocator;
    const any = Any{ .type_url = "type.googleapis.com/demo.Msg", .value = "abc" };
    const bytes = try any.encode(allocator);
    defer allocator.free(bytes);
    var decoded = try Any.decode(allocator, bytes);
    defer decoded.deinit(allocator);
    try std.testing.expectEqualSlices(u8, any.type_url, decoded.type_url);
    try std.testing.expectEqualSlices(u8, any.value, decoded.value);

    const json = try any.jsonStringifyAlloc(allocator);
    defer allocator.free(json);
    try std.testing.expectEqualSlices(u8, "{\"@type\":\"type.googleapis.com/demo.Msg\",\"value\":\"YWJj\"}", json);
}

pub const Empty = struct {
    pub fn encode(allocator: std.mem.Allocator) ![]u8 {
        return try allocator.dupe(u8, "");
    }

    pub fn decode(bytes: []const u8) !Empty {
        var reader = wire.Reader.init(bytes);
        while (try reader.nextTag()) |tag| try reader.skipValue(tag);
        return .{};
    }

    pub fn jsonStringify(writer: *std.Io.Writer) !void {
        try writer.writeAll("{}");
    }
};

test "empty wire and json helper" {
    const allocator = std.testing.allocator;
    const bytes = try Empty.encode(allocator);
    defer allocator.free(bytes);
    try std.testing.expectEqual(@as(usize, 0), bytes.len);
    _ = try Empty.decode(bytes);
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    try Empty.jsonStringify(&out.writer);
    try std.testing.expectEqualSlices(u8, "{}", out.written());
}
