const std = @import("std");
const wire = @import("wire.zig");
const schema_mod = @import("schema.zig");
const dynamic_mod = @import("dynamic.zig");
const registry_mod = @import("registry.zig");

fn ensureUtf8(value: []const u8) error{InvalidUtf8}!void {
    if (!std.unicode.utf8ValidateSlice(value)) return error.InvalidUtf8;
}

pub const Timestamp = struct {
    seconds: i64 = 0,
    nanos: i32 = 0,

    pub fn validate(self: Timestamp) !void {
        if (self.seconds < -62135596800 or self.seconds > 253402300799) return error.TimestampOutOfRange;
        if (self.nanos < 0 or self.nanos > 999_999_999) return error.InvalidNanos;
    }

    pub fn encode(self: Timestamp, allocator: std.mem.Allocator) ![]u8 {
        try self.validate();
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
        try out.validate();
        return out;
    }

    pub fn jsonStringifyAlloc(self: Timestamp, allocator: std.mem.Allocator) ![]u8 {
        var out: std.Io.Writer.Allocating = .init(allocator);
        errdefer out.deinit();
        try self.jsonStringify(&out.writer);
        return try out.toOwnedSlice();
    }

    pub fn jsonStringify(self: Timestamp, writer: *std.Io.Writer) !void {
        try self.validate();
        const day_seconds: i64 = 24 * 60 * 60;
        const days = @divFloor(self.seconds, day_seconds);
        const seconds_of_day: u32 = @intCast(@mod(self.seconds, day_seconds));
        const date = civilFromDays(days);
        const hour = seconds_of_day / 3600;
        const minute = (seconds_of_day % 3600) / 60;
        const second = seconds_of_day % 60;
        try writer.print("\"{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}", .{ @as(u32, @intCast(date.year)), date.month, date.day, hour, minute, second });
        if (self.nanos != 0) try writeCanonicalFraction(@intCast(self.nanos), writer);
        try writer.writeAll("Z\"");
    }

    pub fn jsonParse(text: []const u8) !Timestamp {
        const unquoted = if (text.len >= 2 and text[0] == '"' and text[text.len - 1] == '"') text[1 .. text.len - 1] else text;
        if (unquoted.len < 20 or unquoted[4] != '-' or unquoted[7] != '-' or
            unquoted[10] != 'T' or
            unquoted[13] != ':' or unquoted[16] != ':') return error.InvalidTimestamp;
        const year = std.fmt.parseInt(i32, unquoted[0..4], 10) catch return error.InvalidTimestamp;
        const month = std.fmt.parseInt(u8, unquoted[5..7], 10) catch return error.InvalidTimestamp;
        const day = std.fmt.parseInt(u8, unquoted[8..10], 10) catch return error.InvalidTimestamp;
        const hour = std.fmt.parseInt(u8, unquoted[11..13], 10) catch return error.InvalidTimestamp;
        const minute = std.fmt.parseInt(u8, unquoted[14..16], 10) catch return error.InvalidTimestamp;
        const second = std.fmt.parseInt(u8, unquoted[17..19], 10) catch return error.InvalidTimestamp;
        if (month < 1 or month > 12 or hour > 23 or minute > 59 or second > 59) return error.InvalidTimestamp;
        const days = daysFromCivil(year, month, day);
        const normalized = civilFromDays(days);
        if (normalized.year != year or normalized.month != month or normalized.day != day) return error.InvalidTimestamp;
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
        var offset_seconds: i64 = 0;
        if (index < unquoted.len and unquoted[index] == 'Z') {
            index += 1;
        } else if (index + 6 <= unquoted.len and (unquoted[index] == '+' or unquoted[index] == '-')) {
            const sign: i64 = if (unquoted[index] == '+') 1 else -1;
            const offset_hour = std.fmt.parseInt(u8, unquoted[index + 1 .. index + 3], 10) catch return error.InvalidTimestamp;
            if (unquoted[index + 3] != ':') return error.InvalidTimestamp;
            const offset_minute = std.fmt.parseInt(u8, unquoted[index + 4 .. index + 6], 10) catch return error.InvalidTimestamp;
            if (offset_hour > 23 or offset_minute > 59) return error.InvalidTimestamp;
            offset_seconds = sign * (@as(i64, offset_hour) * 3600 + @as(i64, offset_minute) * 60);
            index += 6;
        } else return error.InvalidTimestamp;
        if (index != unquoted.len) return error.InvalidTimestamp;
        const out = Timestamp{
            .seconds = @intCast(days * 86_400 + @as(i64, hour) * 3600 + @as(i64, minute) * 60 + @as(i64, second) - offset_seconds),
            .nanos = nanos,
        };
        try out.validate();
        return out;
    }
};

fn writeCanonicalFraction(nanos: u32, writer: *std.Io.Writer) !void {
    var frac: [9]u8 = undefined;
    _ = std.fmt.bufPrint(&frac, "{d:0>9}", .{nanos}) catch unreachable;
    var len: usize = frac.len;
    while (len > 0 and frac[len - 1] == '0') len -= 1;
    if (len <= 3) {
        len = 3;
    } else if (len <= 6) {
        len = 6;
    } else {
        len = 9;
    }
    try writer.print(".{s}", .{frac[0..len]});
}

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

test "timestamp json parses timezone offsets and rejects invalid date times" {
    const plus = try Timestamp.jsonParse("\"2020-01-01T03:00:00+03:00\"");
    try std.testing.expectEqual(@as(i64, 1_577_836_800), plus.seconds);
    const minus = try Timestamp.jsonParse("\"2019-12-31T19:30:00-04:30\"");
    try std.testing.expectEqual(@as(i64, 1_577_836_800), minus.seconds);
    try std.testing.expectError(error.InvalidTimestamp, Timestamp.jsonParse("\"2020-01-01t00:00:00z\""));
    try std.testing.expectError(error.InvalidTimestamp, Timestamp.jsonParse("\"2020-01-01t00:00:00.123Z\""));
    try std.testing.expectError(error.InvalidTimestamp, Timestamp.jsonParse("\"2020-01-01T00:00:00z\""));
    try std.testing.expectError(error.InvalidTimestamp, Timestamp.jsonParse("\"2020-13-01T00:00:00Z\""));
    try std.testing.expectError(error.InvalidTimestamp, Timestamp.jsonParse("\"2020-02-30T00:00:00Z\""));
    try std.testing.expectError(error.InvalidTimestamp, Timestamp.jsonParse("\"2020-01-01T24:00:00Z\""));
    try std.testing.expectError(error.InvalidTimestamp, Timestamp.jsonParse("\"2020-01-01T00:00:00+24:00\""));
    try std.testing.expectError(error.InvalidTimestamp, Timestamp.jsonParse("\"202x-01-01T00:00:00Z\""));
    try std.testing.expectError(error.InvalidTimestamp, Timestamp.jsonParse("\"2020-01-01T00:00:00+0x:00\""));
}

test "timestamp wire decode validates range and nanos" {
    const allocator = std.testing.allocator;
    var seconds_writer = wire.Writer.init(allocator);
    defer seconds_writer.deinit();
    try seconds_writer.writeInt64(1, 253402300800);
    try std.testing.expectError(error.TimestampOutOfRange, Timestamp.decode(seconds_writer.slice()));

    var nanos_writer = wire.Writer.init(allocator);
    defer nanos_writer.deinit();
    try nanos_writer.writeInt32(2, 1_000_000_000);
    try std.testing.expectError(error.InvalidNanos, Timestamp.decode(nanos_writer.slice()));
}

test "wkt json emits canonical fractional digits" {
    const allocator = std.testing.allocator;
    const ts_micros = try (Timestamp{ .seconds = 0, .nanos = 120_000 }).jsonStringifyAlloc(allocator);
    defer allocator.free(ts_micros);
    try std.testing.expectEqualStrings("1970-01-01T00:00:00.000120Z", ts_micros[1 .. ts_micros.len - 1]);
    const ts_nanos = try (Timestamp{ .seconds = 0, .nanos = 123_456_789 }).jsonStringifyAlloc(allocator);
    defer allocator.free(ts_nanos);
    try std.testing.expectEqualStrings("1970-01-01T00:00:00.123456789Z", ts_nanos[1 .. ts_nanos.len - 1]);
    const duration = try (Duration{ .seconds = 1, .nanos = 250_000_000 }).jsonStringifyAlloc(allocator);
    defer allocator.free(duration);
    try std.testing.expectEqualStrings("1.250s", duration[1 .. duration.len - 1]);
}

pub const Duration = struct {
    seconds: i64 = 0,
    nanos: i32 = 0,

    pub fn validate(self: Duration) !void {
        if (self.seconds < -315_576_000_000 or self.seconds > 315_576_000_000) return error.DurationOutOfRange;
        if (self.nanos <= -1_000_000_000 or self.nanos >= 1_000_000_000) return error.InvalidNanos;
        if ((self.seconds < 0 and self.nanos > 0) or (self.seconds > 0 and self.nanos < 0)) return error.DurationSignMismatch;
    }

    pub fn encode(self: Duration, allocator: std.mem.Allocator) ![]u8 {
        try self.validate();
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
        try out.validate();
        return out;
    }

    pub fn jsonStringifyAlloc(self: Duration, allocator: std.mem.Allocator) ![]u8 {
        var out: std.Io.Writer.Allocating = .init(allocator);
        errdefer out.deinit();
        try self.jsonStringify(&out.writer);
        return try out.toOwnedSlice();
    }

    pub fn jsonStringify(self: Duration, writer: *std.Io.Writer) !void {
        try self.validate();
        try writer.writeAll("\"");
        if (self.seconds < 0 or self.nanos < 0) try writer.writeAll("-");
        try writer.print("{d}", .{@abs(self.seconds)});
        if (self.nanos != 0) try writeCanonicalFraction(@intCast(@abs(self.nanos)), writer);
        try writer.writeAll("s\"");
    }

    pub fn jsonParse(text: []const u8) !Duration {
        const unquoted = if (text.len >= 2 and text[0] == '"' and text[text.len - 1] == '"') text[1 .. text.len - 1] else text;
        if (unquoted.len < 2 or unquoted[unquoted.len - 1] != 's') return error.InvalidDuration;
        var body = unquoted[0 .. unquoted.len - 1];
        var negative = false;
        if (body.len != 0 and (body[0] == '-' or body[0] == '+')) {
            negative = body[0] == '-';
            body = body[1..];
        }
        if (body.len == 0) return error.InvalidDuration;
        const dot = std.mem.indexOfScalar(u8, body, '.');
        const sec_text = if (dot) |idx| body[0..idx] else body;
        if (sec_text.len == 0) return error.InvalidDuration;
        var seconds = std.fmt.parseInt(i64, sec_text, 10) catch return error.InvalidDuration;
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
        const out = Duration{ .seconds = seconds, .nanos = nanos };
        try out.validate();
        return out;
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
    try std.testing.expectEqualSlices(u8, "\"-3.250s\"", json);
    const parsed = try Duration.jsonParse(json);
    try std.testing.expectEqual(duration.seconds, parsed.seconds);
    try std.testing.expectEqual(duration.nanos, parsed.nanos);
}

test "duration json parses plus sign and validates input" {
    const positive = try Duration.jsonParse("\"+3.250s\"");
    try std.testing.expectEqual(@as(i64, 3), positive.seconds);
    try std.testing.expectEqual(@as(i32, 250_000_000), positive.nanos);
    const negative_fraction = try (Duration{ .seconds = 0, .nanos = -250_000_000 }).jsonStringifyAlloc(std.testing.allocator);
    defer std.testing.allocator.free(negative_fraction);
    try std.testing.expectEqualSlices(u8, "\"-0.250s\"", negative_fraction);
    try std.testing.expectError(error.InvalidDuration, Duration.jsonParse("\"s\""));
    try std.testing.expectError(error.InvalidDuration, Duration.jsonParse("\".1s\""));
    try std.testing.expectError(error.InvalidDuration, Duration.jsonParse("\"1.s\""));
    try std.testing.expectError(error.InvalidDuration, Duration.jsonParse("\"1.1234567890s\""));
    try std.testing.expectError(error.DurationOutOfRange, Duration.jsonParse("\"315576000001s\""));
}

test "duration wire decode validates range and sign consistency" {
    const allocator = std.testing.allocator;
    var seconds_writer = wire.Writer.init(allocator);
    defer seconds_writer.deinit();
    try seconds_writer.writeInt64(1, 315_576_000_001);
    try std.testing.expectError(error.DurationOutOfRange, Duration.decode(seconds_writer.slice()));

    var nanos_writer = wire.Writer.init(allocator);
    defer nanos_writer.deinit();
    try nanos_writer.writeInt32(2, 1_000_000_000);
    try std.testing.expectError(error.InvalidNanos, Duration.decode(nanos_writer.slice()));

    var sign_writer = wire.Writer.init(allocator);
    defer sign_writer.deinit();
    try sign_writer.writeInt64(1, -1);
    try sign_writer.writeInt32(2, 1);
    try std.testing.expectError(error.DurationSignMismatch, Duration.decode(sign_writer.slice()));
}

pub const FieldMask = struct {
    paths: []const []const u8 = &.{},

    pub fn validate(self: FieldMask) !void {
        for (self.paths) |path| try validateFieldMaskPath(path);
    }

    pub fn encode(self: FieldMask, allocator: std.mem.Allocator) ![]u8 {
        try self.validate();
        var writer = wire.Writer.init(allocator);
        errdefer writer.deinit();
        for (self.paths) |path| try writer.writeString(1, path);
        return try writer.toOwnedSlice();
    }

    pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) ![][]const u8 {
        var paths: std.ArrayList([]const u8) = .empty;
        errdefer {
            for (paths.items) |path| allocator.free(path);
            paths.deinit(allocator);
        }
        var reader = wire.Reader.init(bytes);
        while (try reader.nextTag()) |tag| {
            if (tag.number == 1) {
                try wire.Reader.expectWireType(tag, .length_delimited);
                const path = try allocator.dupe(u8, try reader.readBytes());
                errdefer allocator.free(path);
                try paths.append(allocator, path);
            } else try reader.skipValue(tag);
        }
        return try paths.toOwnedSlice(allocator);
    }

    pub fn decodeOwned(allocator: std.mem.Allocator, bytes: []const u8) !FieldMask {
        return .{ .paths = try decode(allocator, bytes) };
    }

    pub fn deinit(self: *FieldMask, allocator: std.mem.Allocator) void {
        freeStringList(allocator, self.paths);
        self.* = undefined;
    }

    pub fn cloneOwned(self: FieldMask, allocator: std.mem.Allocator) !FieldMask {
        return .{ .paths = try cloneStringList(allocator, self.paths) };
    }

    pub fn jsonStringifyAlloc(self: FieldMask, allocator: std.mem.Allocator) ![]u8 {
        var out: std.Io.Writer.Allocating = .init(allocator);
        errdefer out.deinit();
        try self.jsonStringify(&out.writer);
        return try out.toOwnedSlice();
    }

    pub fn jsonStringify(self: FieldMask, writer: *std.Io.Writer) !void {
        try self.validate();
        try writer.writeAll("\"");
        for (self.paths, 0..) |path, index| {
            if (index != 0) try writer.writeAll(",");
            try writeLowerCamelPath(path, writer);
        }
        try writer.writeAll("\"");
    }

    pub fn jsonParse(allocator: std.mem.Allocator, text: []const u8) ![][]const u8 {
        const unquoted = if (text.len >= 2 and text[0] == '"' and text[text.len - 1] == '"') text[1 .. text.len - 1] else text;
        if (unquoted.len == 0) return try allocator.alloc([]const u8, 0);
        var paths: std.ArrayList([]const u8) = .empty;
        errdefer {
            for (paths.items) |path| allocator.free(path);
            paths.deinit(allocator);
        }
        var it = std.mem.splitScalar(u8, unquoted, ',');
        while (it.next()) |part| {
            if (part.len == 0) return error.InvalidFieldMask;
            const path = try lowerCamelToSnake(allocator, part);
            errdefer allocator.free(path);
            try validateFieldMaskPath(path);
            try paths.append(allocator, path);
        }
        return try paths.toOwnedSlice(allocator);
    }

    pub fn jsonParseOwned(allocator: std.mem.Allocator, text: []const u8) !FieldMask {
        return .{ .paths = try jsonParse(allocator, text) };
    }
};

fn cloneStringList(allocator: std.mem.Allocator, values: []const []const u8) ![][]const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (list.items) |value| allocator.free(value);
        list.deinit(allocator);
    }
    for (values) |value| {
        const owned = try allocator.dupe(u8, value);
        errdefer allocator.free(owned);
        try list.append(allocator, owned);
    }
    return try list.toOwnedSlice(allocator);
}

fn freeStringList(allocator: std.mem.Allocator, values: []const []const u8) void {
    for (values) |value| allocator.free(value);
    allocator.free(values);
}

fn validateFieldMaskPath(path: []const u8) !void {
    if (path.len == 0) return error.InvalidFieldMask;
    var last_was_dot = true;
    var last_was_underscore = false;
    for (path) |c| {
        if (c == '.') {
            if (last_was_dot or last_was_underscore) return error.InvalidFieldMask;
            last_was_dot = true;
            last_was_underscore = false;
            continue;
        }
        if (c == '_') {
            if (last_was_dot or last_was_underscore) return error.InvalidFieldMask;
            last_was_underscore = true;
            continue;
        }
        if (std.ascii.isUpper(c)) return error.InvalidFieldMask;
        if (last_was_dot and !std.ascii.isLower(c)) return error.InvalidFieldMask;
        if (last_was_underscore and !std.ascii.isLower(c)) return error.InvalidFieldMask;
        if (!(std.ascii.isLower(c) or std.ascii.isDigit(c))) return error.InvalidFieldMask;
        last_was_dot = false;
        last_was_underscore = false;
    }
    if (last_was_dot or last_was_underscore) return error.InvalidFieldMask;
}

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
    var last_was_dot = true;
    for (text) |c| {
        if (c == '_') return error.InvalidFieldMask;
        if (c == '.') {
            if (last_was_dot) return error.InvalidFieldMask;
            try out.append(allocator, c);
            last_was_dot = true;
            continue;
        }
        if (std.ascii.isUpper(c)) {
            if (last_was_dot) return error.InvalidFieldMask;
            if (!last_was_dot and out.items.len != 0) try out.append(allocator, '_');
            try out.append(allocator, std.ascii.toLower(c));
        } else if (std.ascii.isLower(c) or std.ascii.isDigit(c)) {
            if (last_was_dot and !std.ascii.isLower(c)) return error.InvalidFieldMask;
            try out.append(allocator, c);
        } else return error.InvalidFieldMask;
        last_was_dot = false;
    }
    if (last_was_dot) return error.InvalidFieldMask;
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

    const empty = try FieldMask.jsonParse(allocator, "\"\"");
    defer allocator.free(empty);
    try std.testing.expectEqual(@as(usize, 0), empty.len);

    const dotted = try FieldMask.jsonParse(allocator, "\"fooBar,baz.quxValue\"");
    defer {
        for (dotted) |path| allocator.free(path);
        allocator.free(dotted);
    }
    try std.testing.expectEqualSlices(u8, "foo_bar", dotted[0]);
    try std.testing.expectEqualSlices(u8, "baz.qux_value", dotted[1]);
    try std.testing.expectError(error.InvalidFieldMask, FieldMask.jsonParse(allocator, "\"foo_bar\""));
    try std.testing.expectError(error.InvalidFieldMask, FieldMask.jsonParse(allocator, "\"foo,,bar\""));
    try std.testing.expectError(error.InvalidFieldMask, FieldMask.jsonParse(allocator, "\"foo.\""));
    try std.testing.expectError(error.InvalidFieldMask, FieldMask.jsonParse(allocator, "\"Foo\""));
    try std.testing.expectError(error.InvalidFieldMask, FieldMask.jsonParse(allocator, "\"foo-bar\""));
    try std.testing.expectError(error.InvalidFieldMask, FieldMask.jsonParse(allocator, "\"foo.1bar\""));
}

test "field mask validates proto path strings before writing" {
    const allocator = std.testing.allocator;
    try (FieldMask{ .paths = &.{ "foo_bar", "nested.value2" } }).validate();
    try std.testing.expectError(error.InvalidFieldMask, (FieldMask{ .paths = &.{""} }).validate());
    try std.testing.expectError(error.InvalidFieldMask, (FieldMask{ .paths = &.{"foo..bar"} }).validate());
    try std.testing.expectError(error.InvalidFieldMask, (FieldMask{ .paths = &.{"foo."} }).validate());
    try std.testing.expectError(error.InvalidFieldMask, (FieldMask{ .paths = &.{"Foo"} }).validate());
    try std.testing.expectError(error.InvalidFieldMask, (FieldMask{ .paths = &.{"foo-bar"} }).validate());
    try std.testing.expectError(error.InvalidFieldMask, (FieldMask{ .paths = &.{"foo_1"} }).jsonStringifyAlloc(allocator));
    try std.testing.expectError(error.InvalidFieldMask, (FieldMask{ .paths = &.{"foo_"} }).validate());
    try std.testing.expectError(error.InvalidFieldMask, (FieldMask{ .paths = &.{"foo__bar"} }).validate());
    try std.testing.expectError(error.InvalidFieldMask, (FieldMask{ .paths = &.{"1foo"} }).validate());
    try std.testing.expectError(error.InvalidFieldMask, (FieldMask{ .paths = &.{"foo._bar"} }).validate());
    try std.testing.expectError(error.InvalidFieldMask, (FieldMask{ .paths = &.{"Foo"} }).encode(allocator));
    try std.testing.expectError(error.InvalidFieldMask, (FieldMask{ .paths = &.{"foo."} }).jsonStringifyAlloc(allocator));
}

test "field mask owned helpers" {
    const allocator = std.testing.allocator;
    const paths = [_][]const u8{ "foo_bar", "nested.value" };
    const mask = FieldMask{ .paths = &paths };

    var cloned = try mask.cloneOwned(allocator);
    defer cloned.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), cloned.paths.len);
    try std.testing.expect(cloned.paths.ptr != mask.paths.ptr);
    try std.testing.expect(cloned.paths[0].ptr != mask.paths[0].ptr);
    try std.testing.expectEqualSlices(u8, "foo_bar", cloned.paths[0]);
    try std.testing.expectEqualSlices(u8, "nested.value", cloned.paths[1]);

    const bytes = try mask.encode(allocator);
    defer allocator.free(bytes);
    var decoded = try FieldMask.decodeOwned(allocator, bytes);
    defer decoded.deinit(allocator);
    try std.testing.expectEqualSlices(u8, "foo_bar", decoded.paths[0]);
    try std.testing.expectEqualSlices(u8, "nested.value", decoded.paths[1]);

    var parsed = try FieldMask.jsonParseOwned(allocator, "\"fooBar,nested.value\"");
    defer parsed.deinit(allocator);
    try std.testing.expectEqualSlices(u8, "foo_bar", parsed.paths[0]);
    try std.testing.expectEqualSlices(u8, "nested.value", parsed.paths[1]);
}

pub const Any = struct {
    type_url: []const u8 = "",
    value: []const u8 = "",

    pub const default_type_url_prefix = "type.googleapis.com";

    pub fn encode(self: Any, allocator: std.mem.Allocator) ![]u8 {
        var writer = wire.Writer.init(allocator);
        errdefer writer.deinit();
        if (self.type_url.len != 0) {
            try ensureUtf8(self.type_url);
            try writer.writeString(1, self.type_url);
        }
        if (self.value.len != 0) try writer.writeBytes(2, self.value);
        return try writer.toOwnedSlice();
    }

    pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) !Any {
        var out = Any{};
        errdefer out.deinit(allocator);
        var reader = wire.Reader.init(bytes);
        while (try reader.nextTag()) |tag| {
            switch (tag.number) {
                1 => {
                    try wire.Reader.expectWireType(tag, .length_delimited);
                    const raw = try reader.readBytes();
                    try ensureUtf8(raw);
                    const next = try allocator.dupe(u8, raw);
                    if (out.type_url.len != 0) allocator.free(out.type_url);
                    out.type_url = next;
                },
                2 => {
                    try wire.Reader.expectWireType(tag, .length_delimited);
                    const next = try allocator.dupe(u8, try reader.readBytes());
                    if (out.value.len != 0) allocator.free(out.value);
                    out.value = next;
                },
                else => try reader.skipValue(tag),
            }
        }
        return out;
    }

    pub fn cloneOwned(self: Any, allocator: std.mem.Allocator) !Any {
        const type_url = try allocator.dupe(u8, self.type_url);
        errdefer allocator.free(type_url);
        return .{
            .type_url = type_url,
            .value = try allocator.dupe(u8, self.value),
        };
    }

    pub fn packBytes(allocator: std.mem.Allocator, full_name: []const u8, payload: []const u8) !Any {
        return try packBytesWithPrefix(allocator, default_type_url_prefix, full_name, payload);
    }

    pub fn packBytesWithPrefix(allocator: std.mem.Allocator, prefix: []const u8, full_name: []const u8, payload: []const u8) !Any {
        const type_url = try makeTypeUrl(allocator, prefix, full_name);
        errdefer allocator.free(type_url);
        return .{
            .type_url = type_url,
            .value = try allocator.dupe(u8, payload),
        };
    }

    pub fn packEncoded(allocator: std.mem.Allocator, full_name: []const u8, message: anytype) !Any {
        return try packEncodedWithPrefix(allocator, default_type_url_prefix, full_name, message);
    }

    pub fn packEncodedWithPrefix(allocator: std.mem.Allocator, prefix: []const u8, full_name: []const u8, message: anytype) !Any {
        const payload = try message.encode(allocator);
        defer allocator.free(payload);
        return try packBytesWithPrefix(allocator, prefix, full_name, payload);
    }

    pub fn packDynamic(allocator: std.mem.Allocator, file: *const schema_mod.FileDescriptor, full_name: []const u8, message: *const dynamic_mod.DynamicMessage) !Any {
        return try packDynamicWithRegistry(allocator, file, null, full_name, message);
    }

    pub fn packDynamicWithRegistry(allocator: std.mem.Allocator, file: *const schema_mod.FileDescriptor, registry: ?*const registry_mod.Registry, full_name: []const u8, message: *const dynamic_mod.DynamicMessage) !Any {
        const payload = try message.encodedWithRegistry(messageDescriptorFile(file, registry, message.descriptor), registry);
        defer message.allocator.free(payload);
        return try packBytes(allocator, full_name, payload);
    }

    pub fn packDynamicInitialized(allocator: std.mem.Allocator, file: *const schema_mod.FileDescriptor, full_name: []const u8, message: *const dynamic_mod.DynamicMessage) !Any {
        return try packDynamicInitializedWithRegistry(allocator, file, null, full_name, message);
    }

    pub fn packDynamicInitializedWithRegistry(allocator: std.mem.Allocator, file: *const schema_mod.FileDescriptor, registry: ?*const registry_mod.Registry, full_name: []const u8, message: *const dynamic_mod.DynamicMessage) !Any {
        const payload = try message.encodedInitializedWithRegistry(messageDescriptorFile(file, registry, message.descriptor), registry);
        defer message.allocator.free(payload);
        return try packBytes(allocator, full_name, payload);
    }

    pub fn typeName(self: Any) []const u8 {
        return anyTypeName(self.type_url);
    }

    pub fn isType(self: Any, full_name: []const u8) bool {
        return anyTypeMatches(self.type_url, full_name);
    }

    pub fn unpackBytes(self: Any, expected_full_name: []const u8) ![]const u8 {
        if (!self.isType(expected_full_name)) return error.TypeMismatch;
        return self.value;
    }

    pub fn unpackEncoded(self: Any, comptime T: type, allocator: std.mem.Allocator, expected_full_name: []const u8) !T {
        const payload = try self.unpackBytes(expected_full_name);
        if (@typeInfo(@TypeOf(T.decode)).@"fn".params.len == 2) return try T.decode(allocator, payload);
        return try T.decode(payload);
    }

    pub fn unpackEncodedOwned(self: Any, comptime T: type, allocator: std.mem.Allocator, expected_full_name: []const u8) !T {
        if (@hasDecl(T, "decodeOwned")) return try T.decodeOwned(allocator, try self.unpackBytes(expected_full_name));
        var decoded = try self.unpackEncoded(T, allocator, expected_full_name);
        errdefer if (@hasDecl(T, "deinit")) decoded.deinit(allocator);
        if (@hasDecl(T, "cloneOwned")) {
            const owned = try decoded.cloneOwned(allocator);
            if (@hasDecl(T, "deinit")) decoded.deinit(allocator);
            return owned;
        }
        return decoded;
    }

    pub fn unpackDynamic(self: Any, allocator: std.mem.Allocator, file: *const schema_mod.FileDescriptor, descriptor: *const schema_mod.MessageDescriptor, expected_full_name: []const u8) !dynamic_mod.DynamicMessage {
        var message = dynamic_mod.DynamicMessage.init(allocator, descriptor);
        errdefer message.deinit();
        try message.decode(file, try self.unpackBytes(expected_full_name));
        return message;
    }

    pub fn unpackDynamicWithRegistry(self: Any, allocator: std.mem.Allocator, file: *const schema_mod.FileDescriptor, registry: *const registry_mod.Registry, descriptor: *const schema_mod.MessageDescriptor, expected_full_name: []const u8) !dynamic_mod.DynamicMessage {
        var message = dynamic_mod.DynamicMessage.init(allocator, descriptor);
        errdefer message.deinit();
        try message.decodeWithRegistry(messageDescriptorFile(file, registry, descriptor), registry, try self.unpackBytes(expected_full_name));
        return message;
    }

    pub fn unpackDynamicInitialized(self: Any, allocator: std.mem.Allocator, file: *const schema_mod.FileDescriptor, descriptor: *const schema_mod.MessageDescriptor, expected_full_name: []const u8) !dynamic_mod.DynamicMessage {
        var message = dynamic_mod.DynamicMessage.init(allocator, descriptor);
        errdefer message.deinit();
        try message.decodeInitialized(file, try self.unpackBytes(expected_full_name));
        return message;
    }

    pub fn unpackDynamicInitializedWithRegistry(self: Any, allocator: std.mem.Allocator, file: *const schema_mod.FileDescriptor, registry: *const registry_mod.Registry, descriptor: *const schema_mod.MessageDescriptor, expected_full_name: []const u8) !dynamic_mod.DynamicMessage {
        var message = dynamic_mod.DynamicMessage.init(allocator, descriptor);
        errdefer message.deinit();
        try message.decodeInitializedWithRegistry(messageDescriptorFile(file, registry, descriptor), registry, try self.unpackBytes(expected_full_name));
        return message;
    }

    pub fn deinit(self: *Any, allocator: std.mem.Allocator) void {
        if (self.type_url.len != 0) allocator.free(self.type_url);
        if (self.value.len != 0) allocator.free(self.value);
        self.* = undefined;
    }

    pub fn jsonStringifyAlloc(self: Any, allocator: std.mem.Allocator) anyerror![]u8 {
        var out: std.Io.Writer.Allocating = .init(allocator);
        errdefer out.deinit();
        try self.jsonStringifyWithAllocator(allocator, &out.writer);
        return try out.toOwnedSlice();
    }

    pub fn jsonStringify(self: Any, writer: *std.Io.Writer) anyerror!void {
        try self.jsonStringifyWithAllocator(std.heap.page_allocator, writer);
    }

    pub fn jsonStringifyWithAllocator(self: Any, allocator: std.mem.Allocator, writer: *std.Io.Writer) anyerror!void {
        if (self.type_url.len == 0 or anyTypeName(self.type_url).len == 0) return error.TypeMismatch;
        try ensureUtf8(self.type_url);
        try writer.writeAll("{\"@type\":");
        try std.json.Stringify.value(self.type_url, .{}, writer);
        try writer.writeAll(",\"value\":");
        if (!(try writeAnyWellKnownJsonValue(allocator, anyTypeName(self.type_url), self.value, writer))) {
            try writer.writeAll("\"");
            try std.base64.standard.Encoder.encodeWriter(writer, self.value);
            try writer.writeAll("\"");
        }
        try writer.writeAll("}");
    }

    pub fn jsonParse(allocator: std.mem.Allocator, text: []const u8) !Any {
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, text, .{});
        defer parsed.deinit();
        return try anyFromJsonValue(allocator, parsed.value);
    }
};

fn anyFromJsonValue(allocator: std.mem.Allocator, json_value: std.json.Value) !Any {
    const object = switch (json_value) {
        .object => |object| object,
        else => return error.TypeMismatch,
    };
    var it = object.iterator();
    while (it.next()) |entry| {
        if (!std.mem.eql(u8, entry.key_ptr.*, "@type") and !std.mem.eql(u8, entry.key_ptr.*, "value")) return error.UnknownField;
    }
    const type_url_json = object.get("@type") orelse return error.TypeMismatch;
    const type_url = switch (type_url_json) {
        .string => |value| value,
        else => return error.TypeMismatch,
    };
    if (type_url.len == 0 or anyTypeName(type_url).len == 0) return error.TypeMismatch;
    const maybe_value_json = object.get("value");
    const owned_type_url = try allocator.dupe(u8, type_url);
    errdefer allocator.free(owned_type_url);
    const owned_value = if (maybe_value_json) |value_json|
        if (try anyWellKnownJsonValueToBytes(allocator, anyTypeName(type_url), value_json)) |value|
            value
        else blk: {
            const encoded = switch (value_json) {
                .string => |value| value,
                else => return error.TypeMismatch,
            };
            break :blk try decodeBase64(allocator, encoded);
        }
    else if (isAnyWellKnownType(anyTypeName(type_url)))
        return error.TypeMismatch
    else
        try allocator.dupe(u8, "");
    errdefer allocator.free(owned_value);
    return .{
        .type_url = owned_type_url,
        .value = owned_value,
    };
}

fn makeTypeUrl(allocator: std.mem.Allocator, prefix: []const u8, full_name: []const u8) ![]u8 {
    if (full_name.len == 0) return error.TypeMismatch;
    const normalized = if (std.mem.startsWith(u8, full_name, ".")) full_name[1..] else full_name;
    if (prefix.len == 0) return try allocator.dupe(u8, normalized);
    return try std.fmt.allocPrint(allocator, "{s}/{s}", .{ std.mem.trimEnd(u8, prefix, "/"), normalized });
}

fn anyTypeName(type_url: []const u8) []const u8 {
    return if (std.mem.lastIndexOfScalar(u8, type_url, '/')) |idx| type_url[idx + 1 ..] else type_url;
}

fn anyTypeMatches(type_url: []const u8, full_name: []const u8) bool {
    const expected = if (std.mem.startsWith(u8, full_name, ".")) full_name[1..] else full_name;
    const actual = anyTypeName(type_url);
    return expected.len != 0 and actual.len != 0 and std.mem.eql(u8, actual, expected);
}

fn normalizedAnyTypeName(type_name: []const u8) []const u8 {
    return if (std.mem.startsWith(u8, type_name, ".")) type_name[1..] else type_name;
}

fn anyTypeNameIs(type_name: []const u8, comptime expected: []const u8) bool {
    return std.mem.eql(u8, normalizedAnyTypeName(type_name), expected);
}

const AnyWellKnownKind = enum {
    timestamp,
    duration,
    field_mask,
    any,
    empty,
    @"struct",
    value,
    list_value,
    double_value,
    float_value,
    int64_value,
    uint64_value,
    int32_value,
    uint32_value,
    bool_value,
    string_value,
    bytes_value,
};

fn anyWellKnownKind(type_name: []const u8) ?AnyWellKnownKind {
    const normalized = normalizedAnyTypeName(type_name);
    inline for (.{
        .{ "google.protobuf.Timestamp", AnyWellKnownKind.timestamp },
        .{ "google.protobuf.Duration", AnyWellKnownKind.duration },
        .{ "google.protobuf.FieldMask", AnyWellKnownKind.field_mask },
        .{ "google.protobuf.Any", AnyWellKnownKind.any },
        .{ "google.protobuf.Empty", AnyWellKnownKind.empty },
        .{ "google.protobuf.Struct", AnyWellKnownKind.@"struct" },
        .{ "google.protobuf.Value", AnyWellKnownKind.value },
        .{ "google.protobuf.ListValue", AnyWellKnownKind.list_value },
        .{ "google.protobuf.DoubleValue", AnyWellKnownKind.double_value },
        .{ "google.protobuf.FloatValue", AnyWellKnownKind.float_value },
        .{ "google.protobuf.Int64Value", AnyWellKnownKind.int64_value },
        .{ "google.protobuf.UInt64Value", AnyWellKnownKind.uint64_value },
        .{ "google.protobuf.Int32Value", AnyWellKnownKind.int32_value },
        .{ "google.protobuf.UInt32Value", AnyWellKnownKind.uint32_value },
        .{ "google.protobuf.BoolValue", AnyWellKnownKind.bool_value },
        .{ "google.protobuf.StringValue", AnyWellKnownKind.string_value },
        .{ "google.protobuf.BytesValue", AnyWellKnownKind.bytes_value },
    }) |entry| {
        if (std.mem.eql(u8, normalized, entry[0])) return entry[1];
    }
    return null;
}

fn isAnyWellKnownType(type_name: []const u8) bool {
    return anyWellKnownKind(type_name) != null;
}

fn writeAnyWellKnownJsonValue(allocator: std.mem.Allocator, type_name: []const u8, value: []const u8, writer: *std.Io.Writer) anyerror!bool {
    const kind = anyWellKnownKind(type_name) orelse return false;
    switch (kind) {
        .timestamp => try (try Timestamp.decode(value)).jsonStringify(writer),
        .duration => try (try Duration.decode(value)).jsonStringify(writer),
        .field_mask => {
            var mask = try FieldMask.decodeOwned(allocator, value);
            defer mask.deinit(allocator);
            try mask.jsonStringify(writer);
        },
        .any => {
            var nested = try Any.decode(allocator, value);
            defer nested.deinit(allocator);
            try nested.jsonStringifyWithAllocator(allocator, writer);
        },
        .empty => {
            _ = try Empty.decode(value);
            try Empty.jsonStringify(writer);
        },
        .@"struct" => {
            var object = try Struct.decode(allocator, value);
            defer object.deinit(allocator);
            try object.jsonStringify(writer);
        },
        .value => {
            var parsed = try Value.decode(allocator, value);
            defer parsed.deinit(allocator);
            try parsed.jsonStringify(writer);
        },
        .list_value => {
            var list = try ListValue.decode(allocator, value);
            defer list.deinit(allocator);
            try list.jsonStringify(writer);
        },
        .double_value => try (try DoubleValue.decode(value)).jsonStringify(writer),
        .float_value => try (try FloatValue.decode(value)).jsonStringify(writer),
        .int64_value => try (try Int64Value.decode(value)).jsonStringify(writer),
        .uint64_value => try (try UInt64Value.decode(value)).jsonStringify(writer),
        .int32_value => try (try Int32Value.decode(value)).jsonStringify(writer),
        .uint32_value => try (try UInt32Value.decode(value)).jsonStringify(writer),
        .bool_value => try (try BoolValue.decode(value)).jsonStringify(writer),
        .string_value => try (try StringValue.decode(value)).jsonStringify(writer),
        .bytes_value => try (try BytesValue.decode(value)).jsonStringify(writer),
    }
    return true;
}

fn anyWellKnownJsonValueToBytes(allocator: std.mem.Allocator, type_name: []const u8, value: std.json.Value) anyerror!?[]u8 {
    const kind = anyWellKnownKind(type_name) orelse return null;
    // `value` is already the parsed JSON subtree from the surrounding Any.
    // Convert it directly to the target WKT wire payload instead of
    // stringify-then-reparse; this avoids extra allocation/copy work on a hot
    // reflection path and keeps ownership localized to the concrete WKT value.
    return switch (kind) {
        .timestamp => try timestampJsonValueToBytes(allocator, value),
        .duration => try durationJsonValueToBytes(allocator, value),
        .field_mask => blk: {
            var mask = try fieldMaskFromJsonValue(allocator, value);
            defer mask.deinit(allocator);
            break :blk try mask.encode(allocator);
        },
        .any => blk: {
            var nested = try anyFromJsonValue(allocator, value);
            defer nested.deinit(allocator);
            break :blk try nested.encode(allocator);
        },
        .empty => blk: {
            _ = try emptyFromJsonValue(value);
            break :blk try Empty.encode(allocator);
        },
        .@"struct" => blk: {
            var object = try structFromJsonValue(allocator, value);
            defer object.deinit(allocator);
            break :blk try object.encode(allocator);
        },
        .value => blk: {
            var parsed = try valueFromJsonValue(allocator, value);
            defer parsed.deinit(allocator);
            break :blk try parsed.encode(allocator);
        },
        .list_value => blk: {
            var list = try listValueFromJsonValue(allocator, value);
            defer list.deinit(allocator);
            break :blk try list.encode(allocator);
        },
        .double_value => try wrapperJsonValueToBytes(allocator, DoubleValue, f64, .double, value),
        .float_value => try wrapperJsonValueToBytes(allocator, FloatValue, f32, .float, value),
        .int64_value => try wrapperJsonValueToBytes(allocator, Int64Value, i64, .int64, value),
        .uint64_value => try wrapperJsonValueToBytes(allocator, UInt64Value, u64, .uint64, value),
        .int32_value => try wrapperJsonValueToBytes(allocator, Int32Value, i32, .int32, value),
        .uint32_value => try wrapperJsonValueToBytes(allocator, UInt32Value, u32, .uint32, value),
        .bool_value => try wrapperJsonValueToBytes(allocator, BoolValue, bool, .bool, value),
        .string_value => try wrapperJsonValueToBytes(allocator, StringValue, []const u8, .string, value),
        .bytes_value => try wrapperJsonValueToBytes(allocator, BytesValue, []const u8, .bytes, value),
    };
}

fn timestampJsonValueToBytes(allocator: std.mem.Allocator, value: std.json.Value) ![]u8 {
    const text = switch (value) {
        .string => |text| text,
        else => return error.TypeMismatch,
    };
    return try (try Timestamp.jsonParse(text)).encode(allocator);
}

fn durationJsonValueToBytes(allocator: std.mem.Allocator, value: std.json.Value) ![]u8 {
    const text = switch (value) {
        .string => |text| text,
        else => return error.TypeMismatch,
    };
    return try (try Duration.jsonParse(text)).encode(allocator);
}

fn fieldMaskFromJsonValue(allocator: std.mem.Allocator, value: std.json.Value) !FieldMask {
    const text = switch (value) {
        .string => |text| text,
        else => return error.TypeMismatch,
    };
    return .{ .paths = try FieldMask.jsonParse(allocator, text) };
}

fn emptyFromJsonValue(value: std.json.Value) !Empty {
    const object = switch (value) {
        .object => |object| object,
        else => return error.TypeMismatch,
    };
    if (object.count() != 0) return error.UnknownField;
    return .{};
}

fn wrapperJsonValueToBytes(allocator: std.mem.Allocator, comptime WrapperType: type, comptime T: type, comptime scalar: WrapperScalar, value: std.json.Value) ![]u8 {
    var parsed = try wrapperFromJsonValue(allocator, WrapperType, T, scalar, value);
    defer parsed.deinit(allocator);
    return try parsed.encode(allocator);
}

fn wrapperFromJsonValue(allocator: std.mem.Allocator, comptime WrapperType: type, comptime T: type, comptime scalar: WrapperScalar, value: std.json.Value) !WrapperType {
    if (value == .null) return .{ .value = defaultWrapperValue(T) };
    return .{ .value = try parseWrapperJsonValue(allocator, T, scalar, value), .owns_value = wrapperValueUsesAllocator(scalar) };
}

fn messageDescriptorFile(default_file: *const schema_mod.FileDescriptor, registry: ?*const registry_mod.Registry, descriptor: *const schema_mod.MessageDescriptor) *const schema_mod.FileDescriptor {
    const reg = registry orelse return default_file;
    return reg.fileContainingMessage(descriptor) orelse default_file;
}

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
    try std.testing.expectError(error.TypeMismatch, (Any{ .type_url = "", .value = "abc" }).jsonStringifyAlloc(allocator));
    try std.testing.expectError(error.TypeMismatch, (Any{ .type_url = "type.googleapis.com/", .value = "abc" }).jsonStringifyAlloc(allocator));

    var parsed = try Any.jsonParse(allocator, "{\"@type\":\"type.googleapis.com/demo.Msg\",\"value\":\"YWJj\"}");
    defer parsed.deinit(allocator);
    try std.testing.expectEqualSlices(u8, any.type_url, parsed.type_url);
    try std.testing.expectEqualSlices(u8, any.value, parsed.value);

    var parsed_url_safe = try Any.jsonParse(allocator, "{\"@type\":\"type.googleapis.com/demo.Msg\",\"value\":\"-_8\"}");
    defer parsed_url_safe.deinit(allocator);
    try std.testing.expectEqualSlices(u8, &.{ 0xfb, 0xff }, parsed_url_safe.value);
    try std.testing.expectError(error.TypeMismatch, Any.jsonParse(allocator, "{\"value\":\"YWJj\"}"));
    try std.testing.expectError(error.TypeMismatch, Any.jsonParse(allocator, "{\"@type\":\"\",\"value\":\"YWJj\"}"));
    try std.testing.expectError(error.TypeMismatch, Any.jsonParse(allocator, "{\"@type\":\"type.googleapis.com/\",\"value\":\"YWJj\"}"));
    try std.testing.expectError(error.UnknownField, Any.jsonParse(allocator, "{\"@type\":\"type.googleapis.com/demo.Msg\",\"value\":\"YWJj\",\"extra\":1}"));
}

test "any json maps embedded well known value field" {
    const allocator = std.testing.allocator;

    const title = StringValue{ .value = "hello" };
    var title_any = try Any.packEncoded(allocator, "google.protobuf.StringValue", title);
    defer title_any.deinit(allocator);
    const title_json = try title_any.jsonStringifyAlloc(allocator);
    defer allocator.free(title_json);
    try std.testing.expectEqualSlices(u8, "{\"@type\":\"type.googleapis.com/google.protobuf.StringValue\",\"value\":\"hello\"}", title_json);
    var parsed_title_any = try Any.jsonParse(allocator, title_json);
    defer parsed_title_any.deinit(allocator);
    var parsed_title = try parsed_title_any.unpackEncodedOwned(StringValue, allocator, "google.protobuf.StringValue");
    defer parsed_title.deinit(allocator);
    try std.testing.expectEqualSlices(u8, "hello", parsed_title.value);

    const ts = Timestamp{ .seconds = 1_577_836_800, .nanos = 123_000_000 };
    var ts_any = try Any.packEncoded(allocator, "google.protobuf.Timestamp", ts);
    defer ts_any.deinit(allocator);
    const ts_json = try ts_any.jsonStringifyAlloc(allocator);
    defer allocator.free(ts_json);
    try std.testing.expectEqualSlices(u8, "{\"@type\":\"type.googleapis.com/google.protobuf.Timestamp\",\"value\":\"2020-01-01T00:00:00.123Z\"}", ts_json);
    var parsed_ts_any = try Any.jsonParse(allocator, ts_json);
    defer parsed_ts_any.deinit(allocator);
    const parsed_ts = try parsed_ts_any.unpackEncoded(Timestamp, allocator, "google.protobuf.Timestamp");
    try std.testing.expectEqual(ts.seconds, parsed_ts.seconds);
    try std.testing.expectEqual(ts.nanos, parsed_ts.nanos);

    const mask = FieldMask{ .paths = &.{ "foo_bar", "nested.value" } };
    var mask_any = try Any.packEncoded(allocator, "google.protobuf.FieldMask", mask);
    defer mask_any.deinit(allocator);
    const mask_json = try mask_any.jsonStringifyAlloc(allocator);
    defer allocator.free(mask_json);
    try std.testing.expectEqualSlices(u8, "{\"@type\":\"type.googleapis.com/google.protobuf.FieldMask\",\"value\":\"fooBar,nested.value\"}", mask_json);
    var parsed_mask_any = try Any.jsonParse(allocator, mask_json);
    defer parsed_mask_any.deinit(allocator);
    var parsed_mask = try parsed_mask_any.unpackEncodedOwned(FieldMask, allocator, "google.protobuf.FieldMask");
    defer parsed_mask.deinit(allocator);
    try std.testing.expectEqualSlices(u8, "foo_bar", parsed_mask.paths[0]);
    try std.testing.expectEqualSlices(u8, "nested.value", parsed_mask.paths[1]);

    var object = try Struct.jsonParse(allocator, "{\"enabled\":true,\"items\":[null,\"zig\"]}");
    defer object.deinit(allocator);
    var object_any = try Any.packEncoded(allocator, "google.protobuf.Struct", object);
    defer object_any.deinit(allocator);
    const object_json = try object_any.jsonStringifyAlloc(allocator);
    defer allocator.free(object_json);
    try std.testing.expect(std.mem.indexOf(u8, object_json, "\"value\":{\"enabled\":true") != null);
    var parsed_object_any = try Any.jsonParse(allocator, object_json);
    defer parsed_object_any.deinit(allocator);
    var parsed_object = try parsed_object_any.unpackEncodedOwned(Struct, allocator, "google.protobuf.Struct");
    defer parsed_object.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), parsed_object.fields.len);

    try std.testing.expectError(error.TypeMismatch, Any.jsonParse(allocator, "{\"@type\":\"type.googleapis.com/google.protobuf.StringValue\"}"));
    try std.testing.expectError(error.TypeMismatch, Any.jsonParse(allocator, "{\"@type\":\"type.googleapis.com/google.protobuf.StringValue\",\"value\":{\"bad\":true}}"));
}

test "any json parses embedded well known variants from parsed values" {
    const allocator = std.testing.allocator;

    var duration_any = try Any.jsonParse(allocator, "{\"@type\":\"type.googleapis.com/google.protobuf.Duration\",\"value\":\"1.500s\"}");
    defer duration_any.deinit(allocator);
    const duration = try duration_any.unpackEncoded(Duration, allocator, "google.protobuf.Duration");
    try std.testing.expectEqual(@as(i64, 1), duration.seconds);
    try std.testing.expectEqual(@as(i32, 500_000_000), duration.nanos);

    var empty_any = try Any.jsonParse(allocator, "{\"@type\":\"type.googleapis.com/google.protobuf.Empty\",\"value\":{}}");
    defer empty_any.deinit(allocator);
    _ = try empty_any.unpackEncoded(Empty, allocator, "google.protobuf.Empty");

    var int64_any = try Any.jsonParse(allocator, "{\"@type\":\"type.googleapis.com/google.protobuf.Int64Value\",\"value\":\"9007199254740993\"}");
    defer int64_any.deinit(allocator);
    const int64_value = try int64_any.unpackEncoded(Int64Value, allocator, "google.protobuf.Int64Value");
    try std.testing.expectEqual(@as(i64, 9007199254740993), int64_value.value);

    var bytes_any = try Any.jsonParse(allocator, "{\"@type\":\"type.googleapis.com/google.protobuf.BytesValue\",\"value\":\"aGk=\"}");
    defer bytes_any.deinit(allocator);
    var bytes_value = try bytes_any.unpackEncodedOwned(BytesValue, allocator, "google.protobuf.BytesValue");
    defer bytes_value.deinit(allocator);
    try std.testing.expectEqualSlices(u8, "hi", bytes_value.value);

    var list_any = try Any.jsonParse(allocator, "{\"@type\":\"type.googleapis.com/google.protobuf.ListValue\",\"value\":[null,\"zig\"]}");
    defer list_any.deinit(allocator);
    var list_value = try list_any.unpackEncodedOwned(ListValue, allocator, "google.protobuf.ListValue");
    defer list_value.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), list_value.values.len);
    try std.testing.expectEqual(Value.null_value, list_value.values[0]);
    try std.testing.expectEqualSlices(u8, "zig", list_value.values[1].string_value);

    var value_any = try Any.jsonParse(allocator, "{\"@type\":\"type.googleapis.com/google.protobuf.Value\",\"value\":{\"flag\":true}}");
    defer value_any.deinit(allocator);
    var value = try value_any.unpackEncodedOwned(Value, allocator, "google.protobuf.Value");
    defer value.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), value.struct_value.fields.len);
    try std.testing.expectEqualSlices(u8, "flag", value.struct_value.fields[0].key);

    var nested_any = try Any.jsonParse(allocator, "{\"@type\":\"type.googleapis.com/google.protobuf.Any\",\"value\":{\"@type\":\"type.googleapis.com/google.protobuf.StringValue\",\"value\":\"nested\"}}");
    defer nested_any.deinit(allocator);
    var nested = try nested_any.unpackEncodedOwned(Any, allocator, "google.protobuf.Any");
    defer nested.deinit(allocator);
    var nested_string = try nested.unpackEncodedOwned(StringValue, allocator, "google.protobuf.StringValue");
    defer nested_string.deinit(allocator);
    try std.testing.expectEqualSlices(u8, "nested", nested_string.value);
}

test "any clone and duplicate field decode helpers" {
    const allocator = std.testing.allocator;
    const any = Any{ .type_url = "type.googleapis.com/old.Msg", .value = "old" };
    var cloned = try any.cloneOwned(allocator);
    defer cloned.deinit(allocator);
    try std.testing.expect(cloned.type_url.ptr != any.type_url.ptr);
    try std.testing.expect(cloned.value.ptr != any.value.ptr);
    try std.testing.expectEqualSlices(u8, any.type_url, cloned.type_url);
    try std.testing.expectEqualSlices(u8, any.value, cloned.value);

    var writer = wire.Writer.init(allocator);
    defer writer.deinit();
    try writer.writeString(1, "type.googleapis.com/old.Msg");
    try writer.writeBytes(2, "old");
    try writer.writeString(1, "type.googleapis.com/new.Msg");
    try writer.writeBytes(2, "new");
    var decoded = try Any.decode(allocator, writer.slice());
    defer decoded.deinit(allocator);
    try std.testing.expectEqualSlices(u8, "type.googleapis.com/new.Msg", decoded.type_url);
    try std.testing.expectEqualSlices(u8, "new", decoded.value);
}

test "any validates type_url utf8" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidUtf8, (Any{ .type_url = &.{0xc0}, .value = "" }).encode(allocator));
    try std.testing.expectError(error.InvalidUtf8, (Any{ .type_url = &.{0xc0}, .value = "" }).jsonStringifyAlloc(allocator));

    var writer = wire.Writer.init(allocator);
    defer writer.deinit();
    try writer.writeString(1, &.{0xc0});
    try std.testing.expectError(error.InvalidUtf8, Any.decode(allocator, writer.slice()));
}

test "any pack and type matching helpers" {
    const allocator = std.testing.allocator;
    var any = try Any.packBytes(allocator, ".demo.Msg", "payload");
    defer any.deinit(allocator);
    try std.testing.expectEqualStrings("type.googleapis.com/demo.Msg", any.type_url);
    try std.testing.expectEqualStrings("demo.Msg", any.typeName());
    try std.testing.expect(any.isType("demo.Msg"));
    try std.testing.expect(any.isType(".demo.Msg"));
    try std.testing.expect(!any.isType("demo.Other"));
    try std.testing.expectEqualSlices(u8, "payload", try any.unpackBytes("demo.Msg"));
    try std.testing.expectError(error.TypeMismatch, any.unpackBytes("demo.Other"));
    try std.testing.expect(!any.isType(""));
    try std.testing.expect(!(Any{ .type_url = "type.googleapis.com/", .value = "" }).isType(""));
    try std.testing.expectError(error.TypeMismatch, (Any{ .type_url = "type.googleapis.com/", .value = "" }).unpackBytes(""));

    var custom = try Any.packBytesWithPrefix(allocator, "example.test/prefix/", "demo.Msg", "abc");
    defer custom.deinit(allocator);
    try std.testing.expectEqualStrings("example.test/prefix/demo.Msg", custom.type_url);
    try std.testing.expect(custom.isType("demo.Msg"));

    const message = StringValue{ .value = "zig" };
    var packed_message = try Any.packEncoded(allocator, "google.protobuf.StringValue", message);
    defer packed_message.deinit(allocator);
    try std.testing.expect(packed_message.isType("google.protobuf.StringValue"));
    const decoded = try StringValue.decode(packed_message.value);
    try std.testing.expectEqualSlices(u8, "zig", decoded.value);
    const unpacked = try packed_message.unpackEncoded(StringValue, allocator, "google.protobuf.StringValue");
    try std.testing.expectEqualSlices(u8, "zig", unpacked.value);
    var unpacked_owned = try packed_message.unpackEncodedOwned(StringValue, allocator, "google.protobuf.StringValue");
    defer unpacked_owned.deinit(allocator);
    try std.testing.expectEqualSlices(u8, "zig", unpacked_owned.value);
    try std.testing.expect(unpacked_owned.value.ptr != packed_message.value.ptr);
    try std.testing.expectError(error.TypeMismatch, packed_message.unpackEncoded(StringValue, allocator, "google.protobuf.Int32Value"));
}

test "any packs and unpacks dynamic messages" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package demo;
        \\message Payload { int32 id = 1; }
    );
    defer file.deinit();
    const descriptor = file.findMessage("Payload").?;
    var message = dynamic_mod.DynamicMessage.init(allocator, descriptor);
    defer message.deinit();
    try message.add(descriptor.findField("id").?, .{ .int32 = 7 });

    var any = try Any.packDynamic(allocator, &file, "demo.Payload", &message);
    defer any.deinit(allocator);
    try std.testing.expectEqualStrings("type.googleapis.com/demo.Payload", any.type_url);
    try std.testing.expect(any.isType(".demo.Payload"));

    var unpacked = try any.unpackDynamic(allocator, &file, descriptor, "demo.Payload");
    defer unpacked.deinit();
    const id = unpacked.get("id").?.values.items[0].int32;
    try std.testing.expectEqual(@as(i32, 7), id);
    try std.testing.expectError(error.TypeMismatch, any.unpackDynamic(allocator, &file, descriptor, "demo.Other"));
}

test "any registry dynamic helpers use owning file features" {
    const allocator = std.testing.allocator;
    var common = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package common;
        \\message Payload { optional int32 id = 1; optional bytes raw = 2; }
    );
    defer common.deinit();
    common.name = "common.proto";
    var app = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package app;
        \\import "common.proto";
        \\message Holder { common.Payload payload = 1; }
    );
    defer app.deinit();
    app.name = "app.proto";

    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);

    const payload_desc = common.findMessage("Payload").?;
    var payload = dynamic_mod.DynamicMessage.init(allocator, payload_desc);
    defer payload.deinit();
    try payload.add(payload_desc.findField("id").?, .{ .int32 = 0 });
    try payload.add(payload_desc.findField("raw").?, .{ .bytes = try allocator.dupe(u8, &.{0xc0}) });

    var any = try Any.packDynamicWithRegistry(allocator, &app, &registry, "common.Payload", &payload);
    defer any.deinit(allocator);
    try std.testing.expectEqualSlices(u8, &.{ 0x08, 0x00, 0x12, 0x01, 0xc0 }, any.value);

    var unpacked = try any.unpackDynamicWithRegistry(allocator, &app, &registry, payload_desc, "common.Payload");
    defer unpacked.deinit();
    try std.testing.expect(unpacked.has(payload_desc.findField("id").?));
    try std.testing.expectEqual(@as(i32, 0), unpacked.get("id").?.values.items[0].int32);
    try std.testing.expectEqualSlices(u8, &.{0xc0}, unpacked.get("raw").?.values.items[0].bytes);

    var initialized = try any.unpackDynamicInitializedWithRegistry(allocator, &app, &registry, payload_desc, "common.Payload");
    defer initialized.deinit();
    try std.testing.expect(initialized.has(payload_desc.findField("id").?));
}

test "any initialized dynamic helpers validate required fields" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Payload { required int32 id = 1; }
    );
    defer file.deinit();
    const descriptor = file.findMessage("Payload").?;
    var missing = dynamic_mod.DynamicMessage.init(allocator, descriptor);
    defer missing.deinit();
    try std.testing.expectError(error.MissingRequiredField, Any.packDynamicInitialized(allocator, &file, "demo.Payload", &missing));

    var message = dynamic_mod.DynamicMessage.init(allocator, descriptor);
    defer message.deinit();
    try message.add(descriptor.findField("id").?, .{ .int32 = 9 });
    var any = try Any.packDynamicInitialized(allocator, &file, "demo.Payload", &message);
    defer any.deinit(allocator);
    var decoded = try any.unpackDynamicInitialized(allocator, &file, descriptor, "demo.Payload");
    defer decoded.deinit();
    try std.testing.expectEqual(@as(i32, 9), decoded.get("id").?.values.items[0].int32);

    var bad = try Any.packBytes(allocator, "demo.Payload", "");
    defer bad.deinit(allocator);
    try std.testing.expectError(error.MissingRequiredField, bad.unpackDynamicInitialized(allocator, &file, descriptor, "demo.Payload"));
}

pub const NullValue = enum(i32) {
    NULL_VALUE = 0,
};

pub const Struct = struct {
    fields: []const Field = &.{},

    pub const Field = struct {
        key: []const u8,
        value: Value,
    };

    pub fn encode(self: Struct, allocator: std.mem.Allocator) anyerror![]u8 {
        var writer = wire.Writer.init(allocator);
        errdefer writer.deinit();
        for (self.fields) |field| {
            try ensureUtf8(field.key);
            var entry_writer = wire.Writer.init(allocator);
            defer entry_writer.deinit();
            try entry_writer.writeString(1, field.key);
            const value_bytes = try field.value.encode(allocator);
            defer allocator.free(value_bytes);
            try entry_writer.writeMessage(2, value_bytes);
            try writer.writeMessage(1, entry_writer.slice());
        }
        return try writer.toOwnedSlice();
    }

    pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) anyerror!Struct {
        var fields: std.ArrayList(Field) = .empty;
        errdefer {
            for (fields.items) |*field| deinitStructField(field, allocator);
            fields.deinit(allocator);
        }
        var reader = wire.Reader.init(bytes);
        while (try reader.nextTag()) |tag| {
            switch (tag.number) {
                1 => {
                    try wire.Reader.expectWireType(tag, .length_delimited);
                    const field = try decodeStructField(allocator, try reader.readBytes());
                    try appendOrReplaceStructField(allocator, &fields, field);
                },
                else => try reader.skipValue(tag),
            }
        }
        return .{ .fields = try fields.toOwnedSlice(allocator) };
    }

    pub fn deinit(self: *Struct, allocator: std.mem.Allocator) void {
        for (self.fields) |field| {
            var owned = field;
            deinitStructField(&owned, allocator);
        }
        allocator.free(self.fields);
        self.* = undefined;
    }

    pub fn cloneOwned(self: Struct, allocator: std.mem.Allocator) anyerror!Struct {
        var fields: std.ArrayList(Field) = .empty;
        errdefer {
            for (fields.items) |*field| deinitStructField(field, allocator);
            fields.deinit(allocator);
        }
        for (self.fields) |field| {
            const key = try allocator.dupe(u8, field.key);
            var owns_key = true;
            errdefer if (owns_key) allocator.free(key);
            var value = try field.value.cloneOwned(allocator);
            var owns_value = true;
            errdefer if (owns_value) value.deinit(allocator);
            try fields.append(allocator, .{ .key = key, .value = value });
            owns_key = false;
            owns_value = false;
        }
        return .{ .fields = try fields.toOwnedSlice(allocator) };
    }

    pub fn jsonStringifyAlloc(self: Struct, allocator: std.mem.Allocator) anyerror![]u8 {
        var out: std.Io.Writer.Allocating = .init(allocator);
        errdefer out.deinit();
        try self.jsonStringify(&out.writer);
        return try out.toOwnedSlice();
    }

    pub fn jsonStringify(self: Struct, writer: *std.Io.Writer) anyerror!void {
        try writer.writeAll("{");
        for (self.fields, 0..) |field, index| {
            try ensureUtf8(field.key);
            if (index != 0) try writer.writeAll(",");
            try std.json.Stringify.value(field.key, .{}, writer);
            try writer.writeAll(":");
            try field.value.jsonStringify(writer);
        }
        try writer.writeAll("}");
    }

    pub fn jsonParse(allocator: std.mem.Allocator, text: []const u8) anyerror!Struct {
        var parsed = try parseJsonValueForStruct(allocator, text);
        defer parsed.deinit();
        return try structFromJsonValue(allocator, parsed.value);
    }
};

pub const ListValue = struct {
    values: []const Value = &.{},

    pub fn encode(self: ListValue, allocator: std.mem.Allocator) anyerror![]u8 {
        var writer = wire.Writer.init(allocator);
        errdefer writer.deinit();
        for (self.values) |value| {
            const value_bytes = try value.encode(allocator);
            defer allocator.free(value_bytes);
            try writer.writeMessage(1, value_bytes);
        }
        return try writer.toOwnedSlice();
    }

    pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) anyerror!ListValue {
        var values: std.ArrayList(Value) = .empty;
        errdefer {
            for (values.items) |*value| value.deinit(allocator);
            values.deinit(allocator);
        }
        var reader = wire.Reader.init(bytes);
        while (try reader.nextTag()) |tag| {
            switch (tag.number) {
                1 => {
                    try wire.Reader.expectWireType(tag, .length_delimited);
                    var value = try Value.decode(allocator, try reader.readBytes());
                    errdefer value.deinit(allocator);
                    try values.append(allocator, value);
                },
                else => try reader.skipValue(tag),
            }
        }
        return .{ .values = try values.toOwnedSlice(allocator) };
    }

    pub fn deinit(self: *ListValue, allocator: std.mem.Allocator) void {
        for (self.values) |value| {
            var owned = value;
            owned.deinit(allocator);
        }
        allocator.free(self.values);
        self.* = undefined;
    }

    pub fn cloneOwned(self: ListValue, allocator: std.mem.Allocator) anyerror!ListValue {
        var values: std.ArrayList(Value) = .empty;
        errdefer {
            for (values.items) |*value| value.deinit(allocator);
            values.deinit(allocator);
        }
        for (self.values) |value| {
            var owned = try value.cloneOwned(allocator);
            errdefer owned.deinit(allocator);
            try values.append(allocator, owned);
        }
        return .{ .values = try values.toOwnedSlice(allocator) };
    }

    pub fn jsonStringifyAlloc(self: ListValue, allocator: std.mem.Allocator) anyerror![]u8 {
        var out: std.Io.Writer.Allocating = .init(allocator);
        errdefer out.deinit();
        try self.jsonStringify(&out.writer);
        return try out.toOwnedSlice();
    }

    pub fn jsonStringify(self: ListValue, writer: *std.Io.Writer) anyerror!void {
        try writer.writeAll("[");
        for (self.values, 0..) |value, index| {
            if (index != 0) try writer.writeAll(",");
            try value.jsonStringify(writer);
        }
        try writer.writeAll("]");
    }

    pub fn jsonParse(allocator: std.mem.Allocator, text: []const u8) anyerror!ListValue {
        var parsed = try parseJsonValueForStruct(allocator, text);
        defer parsed.deinit();
        return try listValueFromJsonValue(allocator, parsed.value);
    }
};

pub const Value = union(enum) {
    null_value,
    number_value: f64,
    string_value: []const u8,
    bool_value: bool,
    struct_value: *Struct,
    list_value: *ListValue,

    pub fn encode(self: Value, allocator: std.mem.Allocator) anyerror![]u8 {
        var writer = wire.Writer.init(allocator);
        errdefer writer.deinit();
        switch (self) {
            .null_value => try writer.writeInt32(1, @intFromEnum(NullValue.NULL_VALUE)),
            .number_value => |value| {
                if (std.math.isNan(value) or std.math.isPositiveInf(value) or std.math.isNegativeInf(value)) return error.InvalidNumber;
                try writer.writeDouble(2, value);
            },
            .string_value => |value| {
                try ensureUtf8(value);
                try writer.writeString(3, value);
            },
            .bool_value => |value| try writer.writeBool(4, value),
            .struct_value => |value| {
                const payload = try value.encode(allocator);
                defer allocator.free(payload);
                try writer.writeMessage(5, payload);
            },
            .list_value => |value| {
                const payload = try value.encode(allocator);
                defer allocator.free(payload);
                try writer.writeMessage(6, payload);
            },
        }
        return try writer.toOwnedSlice();
    }

    pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) anyerror!Value {
        var out: Value = .null_value;
        var has_value = false;
        errdefer if (has_value) out.deinit(allocator);
        var reader = wire.Reader.init(bytes);
        while (try reader.nextTag()) |tag| {
            switch (tag.number) {
                1 => {
                    try wire.Reader.expectWireType(tag, .varint);
                    if (try reader.readInt32() != @intFromEnum(NullValue.NULL_VALUE)) return error.InvalidNullValue;
                    replaceDecodedValue(&out, &has_value, allocator, .null_value);
                },
                2 => {
                    try wire.Reader.expectWireType(tag, .fixed64);
                    const number_value = try reader.readDouble();
                    if (std.math.isNan(number_value) or std.math.isPositiveInf(number_value) or std.math.isNegativeInf(number_value)) return error.InvalidNumber;
                    replaceDecodedValue(&out, &has_value, allocator, .{ .number_value = number_value });
                },
                3 => {
                    try wire.Reader.expectWireType(tag, .length_delimited);
                    const raw = try reader.readBytes();
                    try ensureUtf8(raw);
                    const string_value = try allocator.dupe(u8, raw);
                    replaceDecodedValue(&out, &has_value, allocator, .{ .string_value = string_value });
                },
                4 => {
                    try wire.Reader.expectWireType(tag, .varint);
                    replaceDecodedValue(&out, &has_value, allocator, .{ .bool_value = try reader.readBool() });
                },
                5 => {
                    try wire.Reader.expectWireType(tag, .length_delimited);
                    const nested = try allocator.create(Struct);
                    var owns_nested = true;
                    errdefer if (owns_nested) allocator.destroy(nested);
                    nested.* = try Struct.decode(allocator, try reader.readBytes());
                    errdefer if (owns_nested) nested.deinit(allocator);
                    replaceDecodedValue(&out, &has_value, allocator, .{ .struct_value = nested });
                    owns_nested = false;
                },
                6 => {
                    try wire.Reader.expectWireType(tag, .length_delimited);
                    const nested = try allocator.create(ListValue);
                    var owns_nested = true;
                    errdefer if (owns_nested) allocator.destroy(nested);
                    nested.* = try ListValue.decode(allocator, try reader.readBytes());
                    errdefer if (owns_nested) nested.deinit(allocator);
                    replaceDecodedValue(&out, &has_value, allocator, .{ .list_value = nested });
                    owns_nested = false;
                },
                else => try reader.skipValue(tag),
            }
        }
        return out;
    }

    pub fn deinit(self: *Value, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .null_value, .number_value, .bool_value => {},
            .string_value => |value| allocator.free(value),
            .struct_value => |value| {
                value.deinit(allocator);
                allocator.destroy(value);
            },
            .list_value => |value| {
                value.deinit(allocator);
                allocator.destroy(value);
            },
        }
        self.* = undefined;
    }

    pub fn cloneOwned(self: Value, allocator: std.mem.Allocator) anyerror!Value {
        return switch (self) {
            .null_value => .null_value,
            .number_value => |value| .{ .number_value = value },
            .string_value => |value| .{ .string_value = try allocator.dupe(u8, value) },
            .bool_value => |value| .{ .bool_value = value },
            .struct_value => |value| blk: {
                const nested = try allocator.create(Struct);
                errdefer allocator.destroy(nested);
                nested.* = try value.cloneOwned(allocator);
                break :blk .{ .struct_value = nested };
            },
            .list_value => |value| blk: {
                const nested = try allocator.create(ListValue);
                errdefer allocator.destroy(nested);
                nested.* = try value.cloneOwned(allocator);
                break :blk .{ .list_value = nested };
            },
        };
    }

    pub fn jsonStringifyAlloc(self: Value, allocator: std.mem.Allocator) anyerror![]u8 {
        var out: std.Io.Writer.Allocating = .init(allocator);
        errdefer out.deinit();
        try self.jsonStringify(&out.writer);
        return try out.toOwnedSlice();
    }

    pub fn jsonStringify(self: Value, writer: *std.Io.Writer) anyerror!void {
        switch (self) {
            .null_value => try writer.writeAll("null"),
            .number_value => |value| {
                if (std.math.isNan(value) or std.math.isPositiveInf(value) or std.math.isNegativeInf(value)) return error.InvalidNumber;
                try std.json.Stringify.value(value, .{}, writer);
            },
            .string_value => |value| {
                try ensureUtf8(value);
                try std.json.Stringify.value(value, .{}, writer);
            },
            .bool_value => |value| try writer.writeAll(if (value) "true" else "false"),
            .struct_value => |value| try value.jsonStringify(writer),
            .list_value => |value| try value.jsonStringify(writer),
        }
    }

    pub fn jsonParse(allocator: std.mem.Allocator, text: []const u8) anyerror!Value {
        var parsed = try parseJsonValueForStruct(allocator, text);
        defer parsed.deinit();
        return try valueFromJsonValue(allocator, parsed.value);
    }
};

fn parseJsonValueForStruct(allocator: std.mem.Allocator, text: []const u8) !std.json.Parsed(std.json.Value) {
    return try std.json.parseFromSlice(std.json.Value, allocator, text, .{ .duplicate_field_behavior = .use_last });
}

fn replaceDecodedValue(out: *Value, has_value: *bool, allocator: std.mem.Allocator, next: Value) void {
    if (has_value.*) out.deinit(allocator);
    out.* = next;
    has_value.* = true;
}

fn decodeStructField(allocator: std.mem.Allocator, bytes: []const u8) anyerror!Struct.Field {
    var key = try allocator.dupe(u8, "");
    errdefer allocator.free(key);
    var value: Value = .null_value;
    var has_value = false;
    errdefer if (has_value) value.deinit(allocator);
    var reader = wire.Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            1 => {
                try wire.Reader.expectWireType(tag, .length_delimited);
                const raw = try reader.readBytes();
                try ensureUtf8(raw);
                const new_key = try allocator.dupe(u8, raw);
                allocator.free(key);
                key = new_key;
            },
            2 => {
                try wire.Reader.expectWireType(tag, .length_delimited);
                replaceDecodedValue(&value, &has_value, allocator, try Value.decode(allocator, try reader.readBytes()));
            },
            else => try reader.skipValue(tag),
        }
    }
    return .{ .key = key, .value = value };
}

fn appendOrReplaceStructField(allocator: std.mem.Allocator, fields: *std.ArrayList(Struct.Field), field: Struct.Field) !void {
    errdefer {
        var owned = field;
        deinitStructField(&owned, allocator);
    }
    for (fields.items) |*existing| {
        if (std.mem.eql(u8, existing.key, field.key)) {
            deinitStructField(existing, allocator);
            existing.* = field;
            return;
        }
    }
    try fields.append(allocator, field);
}

fn deinitStructField(field: *Struct.Field, allocator: std.mem.Allocator) void {
    allocator.free(field.key);
    field.value.deinit(allocator);
    field.* = undefined;
}

fn structFromJsonValue(allocator: std.mem.Allocator, json_value: std.json.Value) anyerror!Struct {
    const object = switch (json_value) {
        .object => |object| object,
        else => return error.TypeMismatch,
    };
    var fields: std.ArrayList(Struct.Field) = .empty;
    errdefer {
        for (fields.items) |*field| deinitStructField(field, allocator);
        fields.deinit(allocator);
    }
    var it = object.iterator();
    while (it.next()) |entry| {
        const key = try allocator.dupe(u8, entry.key_ptr.*);
        var owns_key = true;
        errdefer if (owns_key) allocator.free(key);
        var value = try valueFromJsonValue(allocator, entry.value_ptr.*);
        var owns_value = true;
        errdefer if (owns_value) value.deinit(allocator);
        try fields.append(allocator, .{ .key = key, .value = value });
        owns_key = false;
        owns_value = false;
    }
    return .{ .fields = try fields.toOwnedSlice(allocator) };
}

fn listValueFromJsonValue(allocator: std.mem.Allocator, json_value: std.json.Value) anyerror!ListValue {
    const array = switch (json_value) {
        .array => |array| array,
        else => return error.TypeMismatch,
    };
    var values: std.ArrayList(Value) = .empty;
    errdefer {
        for (values.items) |*value| value.deinit(allocator);
        values.deinit(allocator);
    }
    for (array.items) |item| {
        var value = try valueFromJsonValue(allocator, item);
        errdefer value.deinit(allocator);
        try values.append(allocator, value);
    }
    return .{ .values = try values.toOwnedSlice(allocator) };
}

fn valueFromJsonValue(allocator: std.mem.Allocator, json_value: std.json.Value) anyerror!Value {
    switch (json_value) {
        .null => return .null_value,
        .bool => |value| return .{ .bool_value = value },
        .integer => |value| return .{ .number_value = @floatFromInt(value) },
        .float => |value| {
            if (!std.math.isFinite(value)) return error.InvalidNumber;
            return .{ .number_value = value };
        },
        .number_string => |value| {
            const parsed = try std.fmt.parseFloat(f64, value);
            if (!std.math.isFinite(parsed)) return error.InvalidNumber;
            return .{ .number_value = parsed };
        },
        .string => |value| return .{ .string_value = try allocator.dupe(u8, value) },
        .object => {
            const nested = try allocator.create(Struct);
            errdefer allocator.destroy(nested);
            nested.* = try structFromJsonValue(allocator, json_value);
            return .{ .struct_value = nested };
        },
        .array => {
            const nested = try allocator.create(ListValue);
            errdefer allocator.destroy(nested);
            nested.* = try listValueFromJsonValue(allocator, json_value);
            return .{ .list_value = nested };
        },
    }
}

test "struct value and listvalue wire and json helpers" {
    const allocator = std.testing.allocator;
    const list_values = [_]Value{ .{ .string_value = "zig" }, .null_value };
    const list = try allocator.create(ListValue);
    defer allocator.destroy(list);
    list.* = .{ .values = &list_values };
    const fields = [_]Struct.Field{
        .{ .key = "name", .value = .{ .string_value = "pbz" } },
        .{ .key = "ok", .value = .{ .bool_value = true } },
        .{ .key = "list", .value = .{ .list_value = list } },
    };
    const st = Struct{ .fields = &fields };

    const json = try st.jsonStringifyAlloc(allocator);
    defer allocator.free(json);
    try std.testing.expectEqualSlices(u8, "{\"name\":\"pbz\",\"ok\":true,\"list\":[\"zig\",null]}", json);

    const bytes = try st.encode(allocator);
    defer allocator.free(bytes);
    var decoded = try Struct.decode(allocator, bytes);
    defer decoded.deinit(allocator);
    const decoded_json = try decoded.jsonStringifyAlloc(allocator);
    defer allocator.free(decoded_json);
    try std.testing.expectEqualSlices(u8, json, decoded_json);

    var parsed = try Struct.jsonParse(allocator, "{\"n\":1.5,\"child\":{\"flag\":false},\"items\":[null,\"x\"]}");
    defer parsed.deinit(allocator);
    const parsed_json = try parsed.jsonStringifyAlloc(allocator);
    defer allocator.free(parsed_json);
    try std.testing.expectEqualSlices(u8, "{\"n\":1.5,\"child\":{\"flag\":false},\"items\":[null,\"x\"]}", parsed_json);
}

test "struct wire decode applies map last key wins" {
    const allocator = std.testing.allocator;
    var first_value = Value{ .string_value = "first" };
    const first_value_bytes = try first_value.encode(allocator);
    defer allocator.free(first_value_bytes);
    var first_entry = wire.Writer.init(allocator);
    defer first_entry.deinit();
    try first_entry.writeString(1, "name");
    try first_entry.writeMessage(2, first_value_bytes);

    var second_value = Value{ .string_value = "second" };
    const second_value_bytes = try second_value.encode(allocator);
    defer allocator.free(second_value_bytes);
    var second_entry = wire.Writer.init(allocator);
    defer second_entry.deinit();
    try second_entry.writeString(1, "name");
    try second_entry.writeMessage(2, second_value_bytes);

    var encoded = wire.Writer.init(allocator);
    defer encoded.deinit();
    try encoded.writeMessage(1, first_entry.slice());
    try encoded.writeMessage(1, second_entry.slice());

    var decoded = try Struct.decode(allocator, encoded.slice());
    defer decoded.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), decoded.fields.len);
    try std.testing.expectEqualStrings("name", decoded.fields[0].key);
    try std.testing.expect(decoded.fields[0].value == .string_value);
    try std.testing.expectEqualStrings("second", decoded.fields[0].value.string_value);
}

test "struct json parse applies object duplicate key last wins" {
    const allocator = std.testing.allocator;
    var parsed = try Struct.jsonParse(allocator,
        \\{"name":"first","name":"second","nested":{"x":1,"x":2},"items":[{"k":"old","k":"new"}]}
    );
    defer parsed.deinit(allocator);

    const json = try parsed.jsonStringifyAlloc(allocator);
    defer allocator.free(json);
    try std.testing.expectEqualStrings("{\"name\":\"second\",\"nested\":{\"x\":2},\"items\":[{\"k\":\"new\"}]}", json);

    var value = try Value.jsonParse(allocator, "{\"dup\":false,\"dup\":true}");
    defer value.deinit(allocator);
    const value_json = try value.jsonStringifyAlloc(allocator);
    defer allocator.free(value_json);
    try std.testing.expectEqualStrings("{\"dup\":true}", value_json);

    var list = try ListValue.jsonParse(allocator, "[{\"dup\":1,\"dup\":3}]");
    defer list.deinit(allocator);
    const list_json = try list.jsonStringifyAlloc(allocator);
    defer allocator.free(list_json);
    try std.testing.expectEqualStrings("[{\"dup\":3}]", list_json);
}

test "struct value and listvalue clone owned helpers" {
    const allocator = std.testing.allocator;
    var parsed = try Struct.jsonParse(allocator, "{\"name\":\"pbz\",\"items\":[\"zig\",null],\"child\":{\"ok\":true}}");
    defer parsed.deinit(allocator);

    var cloned = try parsed.cloneOwned(allocator);
    defer cloned.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 3), cloned.fields.len);
    try std.testing.expect(cloned.fields.ptr != parsed.fields.ptr);
    try std.testing.expect(cloned.fields[0].key.ptr != parsed.fields[0].key.ptr);
    try std.testing.expectEqualSlices(u8, parsed.fields[0].key, cloned.fields[0].key);

    const cloned_json = try cloned.jsonStringifyAlloc(allocator);
    defer allocator.free(cloned_json);
    try std.testing.expectEqualSlices(u8, "{\"name\":\"pbz\",\"items\":[\"zig\",null],\"child\":{\"ok\":true}}", cloned_json);

    var value = try Value.jsonParse(allocator, "{\"nested\":[\"owned\"]}");
    defer value.deinit(allocator);
    var cloned_value = try value.cloneOwned(allocator);
    defer cloned_value.deinit(allocator);
    try std.testing.expect(cloned_value == .struct_value);
    try std.testing.expect(cloned_value.struct_value != value.struct_value);
    const value_json = try cloned_value.jsonStringifyAlloc(allocator);
    defer allocator.free(value_json);
    try std.testing.expectEqualSlices(u8, "{\"nested\":[\"owned\"]}", value_json);
}

test "value json and wire reject invalid null enum and non-finite numbers" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidNumber, (Value{ .number_value = std.math.inf(f64) }).encode(allocator));
    try std.testing.expectError(error.InvalidNumber, (Value{ .number_value = std.math.nan(f64) }).jsonStringifyAlloc(allocator));
    var string_nan = try Value.jsonParse(allocator, "\"NaN\"");
    defer string_nan.deinit(allocator);
    try std.testing.expectEqualSlices(u8, "NaN", string_nan.string_value);
    var string_inf = try Value.jsonParse(allocator, "\"Infinity\"");
    defer string_inf.deinit(allocator);
    try std.testing.expectEqualSlices(u8, "Infinity", string_inf.string_value);
    try std.testing.expectError(error.InvalidNumber, Value.jsonParse(allocator, "1e9999"));
    try std.testing.expectError(error.InvalidNumber, Struct.jsonParse(allocator, "{\"tooBig\":1e9999}"));
    try std.testing.expectError(error.InvalidNumber, ListValue.jsonParse(allocator, "[1e9999]"));

    var writer = wire.Writer.init(allocator);
    defer writer.deinit();
    try writer.writeInt32(1, 1);
    try std.testing.expectError(error.InvalidNullValue, Value.decode(allocator, writer.slice()));

    var nan_writer = wire.Writer.init(allocator);
    defer nan_writer.deinit();
    try nan_writer.writeDouble(2, std.math.nan(f64));
    try std.testing.expectError(error.InvalidNumber, Value.decode(allocator, nan_writer.slice()));
}

test "struct and value validate utf8 strings" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidUtf8, (Value{ .string_value = &.{0xc0} }).encode(allocator));
    try std.testing.expectError(error.InvalidUtf8, (Value{ .string_value = &.{0xc0} }).jsonStringifyAlloc(allocator));
    try std.testing.expectError(error.InvalidUtf8, (Struct{ .fields = &.{.{ .key = &.{0xc0}, .value = .null_value }} }).encode(allocator));
    try std.testing.expectError(error.InvalidUtf8, (Struct{ .fields = &.{.{ .key = &.{0xc0}, .value = .null_value }} }).jsonStringifyAlloc(allocator));

    var value_writer = wire.Writer.init(allocator);
    defer value_writer.deinit();
    try value_writer.writeString(3, &.{0xc0});
    try std.testing.expectError(error.InvalidUtf8, Value.decode(allocator, value_writer.slice()));

    var entry_writer = wire.Writer.init(allocator);
    defer entry_writer.deinit();
    try entry_writer.writeString(1, &.{0xc0});
    var struct_writer = wire.Writer.init(allocator);
    defer struct_writer.deinit();
    try struct_writer.writeMessage(1, entry_writer.slice());
    try std.testing.expectError(error.InvalidUtf8, Struct.decode(allocator, struct_writer.slice()));
}

test "value decode uses last oneof arm and parser cleans up on OOM" {
    const allocator = std.testing.allocator;

    var encoded = wire.Writer.init(allocator);
    defer encoded.deinit();
    try encoded.writeString(3, "old");
    try encoded.writeBool(4, true);
    var decoded = try Value.decode(allocator, encoded.slice());
    defer decoded.deinit(allocator);
    try std.testing.expect(decoded == .bool_value);
    try std.testing.expect(decoded.bool_value);

    var backing = std.heap.DebugAllocator(.{}){};
    defer {
        const status = backing.deinit();
        std.debug.assert(status == .ok);
    }
    var failing = std.testing.FailingAllocator.init(backing.allocator(), .{ .fail_index = 4 });
    try std.testing.expectError(error.OutOfMemory, Struct.jsonParse(failing.allocator(), "{\"a\":\"owned\",\"b\":[\"nested\"]}"));
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

    pub fn jsonParse(allocator: std.mem.Allocator, text: []const u8) !Empty {
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, text, .{});
        defer parsed.deinit();
        return try emptyFromJsonValue(parsed.value);
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
    _ = try Empty.jsonParse(allocator, "{}");
    try std.testing.expectError(error.UnknownField, Empty.jsonParse(allocator, "{\"x\":1}"));
}

const WrapperScalar = enum { double, float, int64, uint64, int32, uint32, bool, string, bytes };

pub fn Wrapper(comptime T: type, comptime scalar: WrapperScalar) type {
    return struct {
        value: T,
        // String/bytes wrappers may either borrow from an input wire buffer
        // (`decode`) or own heap storage (`decodeOwned`, JSON parse, clone).
        // Scalars never allocate and leave this false.
        owns_value: bool = false,

        const Self = @This();

        pub fn encode(self: Self, allocator: std.mem.Allocator) ![]u8 {
            var writer = wire.Writer.init(allocator);
            errdefer writer.deinit();
            switch (scalar) {
                .double => try writer.writeDouble(1, self.value),
                .float => try writer.writeFloat(1, self.value),
                .int64 => try writer.writeInt64(1, self.value),
                .uint64 => try writer.writeUInt64(1, self.value),
                .int32 => try writer.writeInt32(1, self.value),
                .uint32 => try writer.writeUInt32(1, self.value),
                .bool => try writer.writeBool(1, self.value),
                .string => {
                    try ensureUtf8(self.value);
                    try writer.writeString(1, self.value);
                },
                .bytes => try writer.writeBytes(1, self.value),
            }
            return try writer.toOwnedSlice();
        }

        pub fn decode(bytes: []const u8) !Self {
            var out = Self{ .value = defaultWrapperValue(T) };
            var reader = wire.Reader.init(bytes);
            while (try reader.nextTag()) |tag| {
                if (tag.number != 1) {
                    try reader.skipValue(tag);
                    continue;
                }
                out.value = switch (scalar) {
                    .double => blk: {
                        try wire.Reader.expectWireType(tag, .fixed64);
                        break :blk try reader.readDouble();
                    },
                    .float => blk: {
                        try wire.Reader.expectWireType(tag, .fixed32);
                        break :blk try reader.readFloat();
                    },
                    .int64 => blk: {
                        try wire.Reader.expectWireType(tag, .varint);
                        break :blk try reader.readInt64();
                    },
                    .uint64 => blk: {
                        try wire.Reader.expectWireType(tag, .varint);
                        break :blk try reader.readUInt64();
                    },
                    .int32 => blk: {
                        try wire.Reader.expectWireType(tag, .varint);
                        break :blk try reader.readInt32();
                    },
                    .uint32 => blk: {
                        try wire.Reader.expectWireType(tag, .varint);
                        break :blk try reader.readUInt32();
                    },
                    .bool => blk: {
                        try wire.Reader.expectWireType(tag, .varint);
                        break :blk try reader.readBool();
                    },
                    .string => blk: {
                        try wire.Reader.expectWireType(tag, .length_delimited);
                        const value = try reader.readBytes();
                        try ensureUtf8(value);
                        break :blk value;
                    },
                    .bytes => blk: {
                        try wire.Reader.expectWireType(tag, .length_delimited);
                        break :blk try reader.readBytes();
                    },
                };
            }
            return out;
        }

        pub fn decodeOwned(allocator: std.mem.Allocator, bytes: []const u8) !Self {
            const decoded = try Self.decode(bytes);
            return try decoded.cloneOwned(allocator);
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            switch (scalar) {
                .string, .bytes => if (self.owns_value and self.value.len != 0) allocator.free(self.value),
                else => {},
            }
            self.* = undefined;
        }

        pub fn cloneOwned(self: Self, allocator: std.mem.Allocator) !Self {
            return switch (scalar) {
                .string, .bytes => .{ .value = try allocator.dupe(u8, self.value), .owns_value = true },
                else => self,
            };
        }

        pub fn jsonStringifyAlloc(self: Self, allocator: std.mem.Allocator) ![]u8 {
            var out: std.Io.Writer.Allocating = .init(allocator);
            errdefer out.deinit();
            try self.jsonStringify(&out.writer);
            return try out.toOwnedSlice();
        }

        pub fn jsonStringify(self: Self, writer: *std.Io.Writer) !void {
            switch (scalar) {
                .double, .float => {
                    if (std.math.isNan(self.value)) return try std.json.Stringify.value("NaN", .{}, writer);
                    if (std.math.isPositiveInf(self.value)) return try std.json.Stringify.value("Infinity", .{}, writer);
                    if (std.math.isNegativeInf(self.value)) return try std.json.Stringify.value("-Infinity", .{}, writer);
                    try std.json.Stringify.value(self.value, .{}, writer);
                },
                .int64, .uint64 => {
                    try writer.writeAll("\"");
                    try writer.print("{d}", .{self.value});
                    try writer.writeAll("\"");
                },
                .bytes => {
                    try writer.writeAll("\"");
                    try std.base64.standard.Encoder.encodeWriter(writer, self.value);
                    try writer.writeAll("\"");
                },
                .string => {
                    try ensureUtf8(self.value);
                    try std.json.Stringify.value(self.value, .{}, writer);
                },
                else => try std.json.Stringify.value(self.value, .{}, writer),
            }
        }

        pub fn jsonParse(allocator: std.mem.Allocator, text: []const u8) !Self {
            var parsed = try std.json.parseFromSlice(std.json.Value, allocator, text, .{});
            defer parsed.deinit();
            return try wrapperFromJsonValue(allocator, Self, T, scalar, parsed.value);
        }

        pub fn jsonParseOwned(allocator: std.mem.Allocator, text: []const u8) !Self {
            return try jsonParse(allocator, text);
        }
    };
}

fn parseWrapperJsonValue(allocator: std.mem.Allocator, comptime T: type, comptime scalar: WrapperScalar, value: std.json.Value) !T {
    return switch (scalar) {
        .double => try parseWrapperFloat(T, value),
        .float => try parseWrapperFloat(T, value),
        .int64, .uint64, .int32, .uint32 => try parseWrapperInt(T, value),
        .bool => switch (value) {
            .bool => |v| v,
            else => error.TypeMismatch,
        },
        .string => switch (value) {
            .string => |v| try allocator.dupe(u8, v),
            else => error.TypeMismatch,
        },
        .bytes => switch (value) {
            .string => |v| try decodeBase64ForWrapper(allocator, v),
            else => error.TypeMismatch,
        },
    };
}

fn wrapperValueUsesAllocator(comptime scalar: WrapperScalar) bool {
    return scalar == .string or scalar == .bytes;
}

fn parseWrapperInt(comptime T: type, value: std.json.Value) !T {
    return switch (value) {
        .integer => |v| std.math.cast(T, v) orelse error.Overflow,
        .number_string, .string => |v| try std.fmt.parseInt(T, v, 10),
        else => error.TypeMismatch,
    };
}

fn parseWrapperFloat(comptime T: type, value: std.json.Value) !T {
    return switch (value) {
        .float => |v| @floatCast(v),
        .integer => |v| @floatFromInt(v),
        .number_string, .string => |v| parseWrapperSpecialFloat(T, v) orelse try std.fmt.parseFloat(T, v),
        else => error.TypeMismatch,
    };
}

fn parseWrapperSpecialFloat(comptime T: type, value: []const u8) ?T {
    if (std.mem.eql(u8, value, "NaN")) return std.math.nan(T);
    if (std.mem.eql(u8, value, "Infinity")) return std.math.inf(T);
    if (std.mem.eql(u8, value, "-Infinity")) return -std.math.inf(T);
    return null;
}

fn decodeBase64ForWrapper(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    return try decodeBase64(allocator, value);
}

fn decodeBase64(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    return decodeBase64With(allocator, &std.base64.standard.Decoder, value) catch
        decodeBase64With(allocator, &std.base64.url_safe.Decoder, value) catch
        decodeBase64With(allocator, &std.base64.standard_no_pad.Decoder, value) catch
        decodeBase64With(allocator, &std.base64.url_safe_no_pad.Decoder, value);
}

fn decodeBase64With(allocator: std.mem.Allocator, decoder: *const std.base64.Base64Decoder, value: []const u8) ![]u8 {
    const size = try decoder.calcSizeForSlice(value);
    const out = try allocator.alloc(u8, size);
    errdefer allocator.free(out);
    try decoder.decode(out, value);
    return out;
}

fn defaultWrapperValue(comptime T: type) T {
    return switch (@typeInfo(T)) {
        .bool => false,
        .int => 0,
        .float => 0,
        .pointer => "",
        else => @compileError("unsupported wrapper type"),
    };
}

pub const DoubleValue = Wrapper(f64, .double);
pub const FloatValue = Wrapper(f32, .float);
pub const Int64Value = Wrapper(i64, .int64);
pub const UInt64Value = Wrapper(u64, .uint64);
pub const Int32Value = Wrapper(i32, .int32);
pub const UInt32Value = Wrapper(u32, .uint32);
pub const BoolValue = Wrapper(bool, .bool);
pub const StringValue = Wrapper([]const u8, .string);
pub const BytesValue = Wrapper([]const u8, .bytes);

test "wrapper wire and json helpers" {
    const allocator = std.testing.allocator;
    const int_value = Int32Value{ .value = 42 };
    const int_bytes = try int_value.encode(allocator);
    defer allocator.free(int_bytes);
    try std.testing.expectEqual(@as(i32, 42), (try Int32Value.decode(int_bytes)).value);
    const int_json = try int_value.jsonStringifyAlloc(allocator);
    defer allocator.free(int_json);
    try std.testing.expectEqualSlices(u8, "42", int_json);

    const str_value = StringValue{ .value = "zig" };
    const str_bytes = try str_value.encode(allocator);
    defer allocator.free(str_bytes);
    var decoded_str = try StringValue.decode(str_bytes);
    try std.testing.expectEqualSlices(u8, "zig", decoded_str.value);
    try std.testing.expect(!decoded_str.owns_value);
    // Borrowed wire decodes must be safe to deinit; ownership-aware wrappers
    // only free values created by clone/owned/JSON helpers.
    decoded_str.deinit(allocator);
    const str_json = try str_value.jsonStringifyAlloc(allocator);
    defer allocator.free(str_json);
    try std.testing.expectEqualSlices(u8, "\"zig\"", str_json);

    const bytes_value = BytesValue{ .value = "hi" };
    const bytes_json = try bytes_value.jsonStringifyAlloc(allocator);
    defer allocator.free(bytes_json);
    try std.testing.expectEqualSlices(u8, "\"aGk=\"", bytes_json);
}

test "string wrapper validates utf8" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidUtf8, (StringValue{ .value = &.{0xc0} }).encode(allocator));
    try std.testing.expectError(error.InvalidUtf8, (StringValue{ .value = &.{0xc0} }).jsonStringifyAlloc(allocator));

    var writer = wire.Writer.init(allocator);
    defer writer.deinit();
    try writer.writeString(1, &.{0xc0});
    try std.testing.expectError(error.InvalidUtf8, StringValue.decode(writer.slice()));
}

test "wrapper json parse helpers" {
    const allocator = std.testing.allocator;
    try std.testing.expectEqual(@as(i64, 9007199254740993), (try Int64Value.jsonParse(allocator, "\"9007199254740993\"")).value);
    try std.testing.expectEqual(@as(u64, 9007199254740993), (try UInt64Value.jsonParse(allocator, "\"9007199254740993\"")).value);
    try std.testing.expectError(error.Overflow, Int32Value.jsonParse(allocator, "2147483648"));
    try std.testing.expectError(error.Overflow, UInt32Value.jsonParse(allocator, "-1"));
    try std.testing.expectError(error.Overflow, UInt64Value.jsonParse(allocator, "-1"));
    try std.testing.expectEqual(true, (try BoolValue.jsonParse(allocator, "true")).value);
    try std.testing.expectEqual(false, (try BoolValue.jsonParse(allocator, "null")).value);
    try std.testing.expect(std.math.isNan((try DoubleValue.jsonParse(allocator, "\"NaN\"")).value));
    try std.testing.expect(std.math.isPositiveInf((try FloatValue.jsonParse(allocator, "\"Infinity\"")).value));
    try std.testing.expect(std.math.isNegativeInf((try DoubleValue.jsonParse(allocator, "\"-Infinity\"")).value));
    const nan_json = try (DoubleValue{ .value = std.math.nan(f64) }).jsonStringifyAlloc(allocator);
    defer allocator.free(nan_json);
    try std.testing.expectEqualSlices(u8, "\"NaN\"", nan_json);
    const inf_json = try (FloatValue{ .value = std.math.inf(f32) }).jsonStringifyAlloc(allocator);
    defer allocator.free(inf_json);
    try std.testing.expectEqualSlices(u8, "\"Infinity\"", inf_json);
    const neg_inf_json = try (DoubleValue{ .value = -std.math.inf(f64) }).jsonStringifyAlloc(allocator);
    defer allocator.free(neg_inf_json);
    try std.testing.expectEqualSlices(u8, "\"-Infinity\"", neg_inf_json);
    var parsed_string = try StringValue.jsonParse(allocator, "\"zig\"");
    defer parsed_string.deinit(allocator);
    try std.testing.expect(parsed_string.owns_value);
    try std.testing.expectEqualSlices(u8, "zig", parsed_string.value);
    const null_string = try StringValue.jsonParse(allocator, "null");
    try std.testing.expectEqualSlices(u8, "", null_string.value);
    var bytes = try BytesValue.jsonParse(allocator, "\"aGk=\"");
    defer bytes.deinit(allocator);
    try std.testing.expect(bytes.owns_value);
    try std.testing.expectEqualSlices(u8, "hi", bytes.value);
    const null_bytes = try BytesValue.jsonParse(allocator, "null");
    try std.testing.expectEqualSlices(u8, "", null_bytes.value);
}

test "wrapper owned helpers" {
    const allocator = std.testing.allocator;

    const borrowed_string = StringValue{ .value = "zig" };
    var cloned_string = try borrowed_string.cloneOwned(allocator);
    defer cloned_string.deinit(allocator);
    try std.testing.expect(cloned_string.owns_value);
    try std.testing.expect(cloned_string.value.ptr != borrowed_string.value.ptr);
    try std.testing.expectEqualSlices(u8, "zig", cloned_string.value);

    const string_bytes = try borrowed_string.encode(allocator);
    defer allocator.free(string_bytes);
    var decoded_string = try StringValue.decodeOwned(allocator, string_bytes);
    defer decoded_string.deinit(allocator);
    try std.testing.expect(decoded_string.owns_value);
    try std.testing.expectEqualSlices(u8, "zig", decoded_string.value);
    try std.testing.expect(decoded_string.value.ptr != string_bytes.ptr);

    var parsed_bytes = try BytesValue.jsonParseOwned(allocator, "\"aGk=\"");
    defer parsed_bytes.deinit(allocator);
    try std.testing.expect(parsed_bytes.owns_value);
    try std.testing.expectEqualSlices(u8, "hi", parsed_bytes.value);

    const scalar = Int32Value{ .value = 7 };
    const cloned_scalar = try scalar.cloneOwned(allocator);
    try std.testing.expectEqual(@as(i32, 7), cloned_scalar.value);
}

test "timestamp and duration validate ranges" {
    try std.testing.expectError(error.InvalidNanos, (Timestamp{ .seconds = 0, .nanos = -1 }).validate());
    try std.testing.expectError(error.TimestampOutOfRange, (Timestamp{ .seconds = 253402300800 }).validate());
    try (Timestamp{ .seconds = -62135596800, .nanos = 0 }).validate();

    try std.testing.expectError(error.InvalidNanos, (Duration{ .seconds = 0, .nanos = 1_000_000_000 }).validate());
    try std.testing.expectError(error.DurationSignMismatch, (Duration{ .seconds = 1, .nanos = -1 }).validate());
    try std.testing.expectError(error.DurationOutOfRange, (Duration{ .seconds = 315_576_000_001 }).validate());
    try (Duration{ .seconds = -3, .nanos = -1 }).validate();
}
