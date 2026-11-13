//! Lean JSON value tree used by pbz's protobuf JSON parser.
//!
//! `std.json.Value` is a general-purpose DOM: every object is a
//! `StringArrayHashMap`, every key and string is allocated separately, and the
//! generic scanner copies tokens into temporary buffers. Protobuf JSON parsing
//! only needs an ordered tree that can be walked once, so this module provides
//! a compatible subset (`object.iterator()`, `object.get()`, `object.count()`,
//! `array.items`) with borrowed string slices and a single append-only arena.
//!
//! The parser is a strict RFC 8259 recursive-descent parser with protobuf's
//! duplicate-key rejection. String and key slices borrow from the input text;
//! callers that return message data to users must keep the backing text alive
//! (generated `jsonParse` copies the text into its arena first).

const std = @import("std");

pub const Value = union(enum) {
    null,
    bool: bool,
    integer: i64,
    float: f64,
    number_string: []const u8,
    string: []const u8,
    array: Array,
    object: Object,

    pub const Array = struct {
        items: []Value,
    };

    pub const Entry = struct {
        key: []const u8,
        value: Value,
    };

    pub const Object = struct {
        entries: []Entry,

        pub const Iterator = struct {
            entries: []Entry,
            index: usize = 0,

            pub fn next(self: *Iterator) ?*Entry {
                if (self.index >= self.entries.len) return null;
                const entry = &self.entries[self.index];
                self.index += 1;
                return entry;
            }
        };

        pub fn iterator(self: Object) Iterator {
            return .{ .entries = self.entries };
        }

        pub fn count(self: Object) usize {
            return self.entries.len;
        }

        pub fn get(self: Object, key: []const u8) ?Value {
            for (self.entries) |entry| {
                if (std.mem.eql(u8, entry.key, key)) return entry.value;
            }
            return null;
        }
    };

    /// Mirror `std.json.Value.parseFromNumberSlice` so protobuf integer and
    /// float helpers keep the same `.integer` / `.float` / `.number_string`
    /// classification for overflow and exponent forms.
    pub fn parseFromNumberSlice(s: []const u8) Value {
        if (!isNumberFormattedLikeAnInteger(s)) {
            const f = std.fmt.parseFloat(f64, s) catch return .{ .number_string = s };
            if (std.math.isFinite(f)) {
                return .{ .float = f };
            }
            return .{ .number_string = s };
        }
        if (std.fmt.parseInt(i64, s, 10)) |i| {
            return .{ .integer = i };
        } else |_| {
            return .{ .number_string = s };
        }
    }
};

pub const ParseError = error{
    SyntaxError,
    UnexpectedEndOfInput,
    DuplicateField,
    DepthLimitExceeded,
} || std.mem.Allocator.Error;

pub const ParseOptions = struct {
    /// Maximum number of open `{}`/`[]` containers accepted before returning
    /// `error.DepthLimitExceeded`. The upstream protobuf JSON parsers use a
    /// recursion limit of 100 (`json/internal/lexer.h`), and the conformance
    /// suite requires 200-level Struct/Value/ListValue nesting to fail.
    max_depth: u32 = 100,
};

/// Parse one complete JSON document into a `Value` tree.
///
/// All string and key slices borrow from `text`; the tree itself is allocated
/// from `allocator` and is never freed by this function (it is designed for an
/// arena allocator, matching protobuf parse ownership).
pub fn parse(allocator: std.mem.Allocator, text: []const u8, options: ParseOptions) ParseError!Value {
    var parser = Parser{
        .allocator = allocator,
        .text = text,
        .max_depth = options.max_depth,
    };
    parser.skipWhitespace();
    const value = try parser.parseValue(0);
    parser.skipWhitespace();
    if (parser.index != text.len) return error.SyntaxError;
    return value;
}

const Parser = struct {
    allocator: std.mem.Allocator,
    text: []const u8,
    index: usize = 0,
    max_depth: u32,

    fn skipWhitespace(self: *Parser) void {
        while (self.index < self.text.len) {
            switch (self.text[self.index]) {
                ' ', '\t', '\r', '\n' => self.index += 1,
                else => return,
            }
        }
    }

    fn parseValue(self: *Parser, depth: u32) ParseError!Value {
        self.skipWhitespace();
        if (self.index >= self.text.len) return error.UnexpectedEndOfInput;
        return switch (self.text[self.index]) {
            '{' => self.parseObject(depth + 1),
            '[' => self.parseArray(depth + 1),
            '"' => .{ .string = try self.parseString() },
            't' => blk: {
                try self.expectKeyword("true");
                break :blk .{ .bool = true };
            },
            'f' => blk: {
                try self.expectKeyword("false");
                break :blk .{ .bool = false };
            },
            'n' => blk: {
                try self.expectKeyword("null");
                break :blk .null;
            },
            '-', '0'...'9' => blk: {
                const token = try self.parseNumberToken();
                if (token.integer) |integer| break :blk .{ .integer = integer };
                if (token.integer_syntax) break :blk .{ .number_string = token.text };
                const f = std.fmt.parseFloat(f64, token.text) catch break :blk .{ .number_string = token.text };
                if (std.math.isFinite(f)) break :blk .{ .float = f };
                break :blk .{ .number_string = token.text };
            },
            else => error.SyntaxError,
        };
    }

    fn expectKeyword(self: *Parser, comptime keyword: []const u8) ParseError!void {
        if (self.index + keyword.len > self.text.len) return error.UnexpectedEndOfInput;
        if (!std.mem.eql(u8, self.text[self.index..][0..keyword.len], keyword)) return error.SyntaxError;
        self.index += keyword.len;
    }

    /// FNV-1a over a JSON key. Used only for duplicate detection inside one
    /// object; collisions fall back to an exact key comparison.
    fn keyHash(key: []const u8) u32 {
        var hash: u32 = 2166136261;
        for (key) |byte| {
            hash ^= byte;
            hash *%= 16777619;
        }
        return hash;
    }

    fn parseObject(self: *Parser, depth: u32) ParseError!Value {
        if (depth > self.max_depth) return error.DepthLimitExceeded;
        self.index += 1; // '{'
        self.skipWhitespace();
        var entries: std.ArrayListUnmanaged(Value.Entry) = .empty;
        if (self.index < self.text.len and self.text[self.index] == '}') {
            self.index += 1;
            return .{ .object = .{ .entries = try entries.toOwnedSlice(self.allocator) } };
        }
        // Small objects dominate protobuf messages: an open-addressing table
        // of entry indices avoids the O(n^2) exact-compare scan without
        // allocating. Larger objects migrate to the hash map.
        var small_slots: [64]u32 = @splat(0);
        var seen: std.StringHashMapUnmanaged(void) = .empty;
        var use_hash = false;
        while (true) {
            self.skipWhitespace();
            if (self.index >= self.text.len) return error.UnexpectedEndOfInput;
            if (self.text[self.index] != '"') return error.SyntaxError;
            const key = try self.parseString();

            if (!use_hash) {
                if (entries.items.len >= 32) {
                    for (entries.items) |entry| try seen.put(self.allocator, entry.key, {});
                    use_hash = true;
                } else {
                    var slot = keyHash(key) & 63;
                    while (small_slots[slot] != 0) {
                        const previous = entries.items[small_slots[slot] - 1];
                        if (std.mem.eql(u8, previous.key, key)) return error.DuplicateField;
                        slot = (slot + 1) & 63;
                    }
                    small_slots[slot] = @intCast(entries.items.len + 1);
                }
            }
            if (use_hash) {
                const result = try seen.getOrPut(self.allocator, key);
                if (result.found_existing) return error.DuplicateField;
            }

            self.skipWhitespace();
            if (self.index >= self.text.len) return error.UnexpectedEndOfInput;
            if (self.text[self.index] != ':') return error.SyntaxError;
            self.index += 1;
            const value = try self.parseValue(depth);
            try entries.append(self.allocator, .{ .key = key, .value = value });

            self.skipWhitespace();
            if (self.index >= self.text.len) return error.UnexpectedEndOfInput;
            switch (self.text[self.index]) {
                ',' => self.index += 1,
                '}' => {
                    self.index += 1;
                    return .{ .object = .{ .entries = try entries.toOwnedSlice(self.allocator) } };
                },
                else => return error.SyntaxError,
            }
        }
    }

    fn parseArray(self: *Parser, depth: u32) ParseError!Value {
        if (depth > self.max_depth) return error.DepthLimitExceeded;
        self.index += 1; // '['
        self.skipWhitespace();
        var items: std.ArrayListUnmanaged(Value) = .empty;
        if (self.index < self.text.len and self.text[self.index] == ']') {
            self.index += 1;
            return .{ .array = .{ .items = try items.toOwnedSlice(self.allocator) } };
        }
        while (true) {
            const value = try self.parseValue(depth);
            try items.append(self.allocator, value);
            self.skipWhitespace();
            if (self.index >= self.text.len) return error.UnexpectedEndOfInput;
            switch (self.text[self.index]) {
                ',' => self.index += 1,
                ']' => {
                    self.index += 1;
                    return .{ .array = .{ .items = try items.toOwnedSlice(self.allocator) } };
                },
                else => return error.SyntaxError,
            }
        }
    }

    fn parseString(self: *Parser) ParseError![]const u8 {
        self.index += 1; // opening quote
        const start = self.index;
        var has_escape = false;
        var has_non_ascii = false;
        while (self.index < self.text.len) {
            const c = self.text[self.index];
            switch (c) {
                '"' => {
                    const end = self.index;
                    self.index += 1;
                    if (!has_escape) {
                        const slice = self.text[start..end];
                        if (has_non_ascii and !std.unicode.utf8ValidateSlice(slice)) return error.SyntaxError;
                        return slice;
                    }
                    return try self.unescapeString(start, end);
                },
                '\\' => {
                    has_escape = true;
                    self.index += 1;
                    if (self.index >= self.text.len) return error.UnexpectedEndOfInput;
                    switch (self.text[self.index]) {
                        '"', '\\', '/', 'b', 'f', 'n', 'r', 't' => self.index += 1,
                        'u' => {
                            if (self.index + 4 >= self.text.len) return error.UnexpectedEndOfInput;
                            for (self.text[self.index + 1 ..][0..4]) |hex| {
                                if (!std.ascii.isHex(hex)) return error.SyntaxError;
                            }
                            self.index += 5;
                        },
                        else => return error.SyntaxError,
                    }
                },
                0...0x1f => return error.SyntaxError,
                0x80...0xff => {
                    has_non_ascii = true;
                    self.index += 1;
                },
                else => self.index += 1,
            }
        }
        return error.UnexpectedEndOfInput;
    }

    fn unescapeString(self: *Parser, start: usize, end: usize) ParseError![]const u8 {
        var out: std.ArrayListUnmanaged(u8) = .empty;
        try out.ensureTotalCapacity(self.allocator, end - start);
        var i = start;
        while (i < end) {
            const c = self.text[i];
            if (c != '\\') {
                try out.append(self.allocator, c);
                i += 1;
                continue;
            }
            i += 1;
            if (i >= end) return error.SyntaxError;
            const esc = self.text[i];
            i += 1;
            switch (esc) {
                '"' => try out.append(self.allocator, '"'),
                '\\' => try out.append(self.allocator, '\\'),
                '/' => try out.append(self.allocator, '/'),
                'b' => try out.append(self.allocator, 0x08),
                'f' => try out.append(self.allocator, 0x0c),
                'n' => try out.append(self.allocator, '\n'),
                'r' => try out.append(self.allocator, '\r'),
                't' => try out.append(self.allocator, '\t'),
                'u' => {
                    if (i + 4 > end) return error.SyntaxError;
                    var code_unit: u21 = 0;
                    for (self.text[i..][0..4]) |hex| {
                        code_unit = code_unit * 16 + (std.fmt.charToDigit(hex, 16) catch return error.SyntaxError);
                    }
                    i += 4;
                    var codepoint: u21 = code_unit;
                    if (code_unit >= 0xd800 and code_unit <= 0xdbff) {
                        if (i + 6 > end or self.text[i] != '\\' or self.text[i + 1] != 'u') return error.SyntaxError;
                        var low: u21 = 0;
                        for (self.text[i + 2 ..][0..4]) |hex| {
                            low = low * 16 + (std.fmt.charToDigit(hex, 16) catch return error.SyntaxError);
                        }
                        if (low < 0xdc00 or low > 0xdfff) return error.SyntaxError;
                        i += 6;
                        codepoint = 0x10000 + ((code_unit - 0xd800) << 10) + (low - 0xdc00);
                    } else if (code_unit >= 0xdc00 and code_unit <= 0xdfff) {
                        return error.SyntaxError;
                    }
                    var encoded: [4]u8 = undefined;
                    const len = std.unicode.utf8Encode(codepoint, &encoded) catch return error.SyntaxError;
                    try out.appendSlice(self.allocator, encoded[0..len]);
                },
                else => return error.SyntaxError,
            }
        }
        const slice = try out.toOwnedSlice(self.allocator);
        if (!std.unicode.utf8ValidateSlice(slice)) return error.SyntaxError;
        return slice;
    }

    const NumberToken = struct {
        text: []const u8,
        /// Set when the token is a plain integer (no fraction/exponent) that
        /// fits in i64, so the value tree can store it without a second scan.
        integer: ?i64 = null,
        integer_syntax: bool = false,
    };

    fn parseNumberToken(self: *Parser) ParseError!NumberToken {
        const start = self.index;
        const negative = self.text[self.index] == '-';
        if (negative) {
            self.index += 1;
            if (self.index >= self.text.len) return error.UnexpectedEndOfInput;
        }
        var magnitude: u64 = 0;
        var overflow = false;
        switch (self.text[self.index]) {
            '0' => self.index += 1,
            '1'...'9' => {
                magnitude = self.text[self.index] - '0';
                self.index += 1;
                while (self.index < self.text.len and std.ascii.isDigit(self.text[self.index])) {
                    const digit: u64 = self.text[self.index] - '0';
                    if (magnitude > (std.math.maxInt(u64) - digit) / 10) {
                        overflow = true;
                    } else {
                        magnitude = magnitude * 10 + digit;
                    }
                    self.index += 1;
                }
            },
            else => return error.SyntaxError,
        }
        var integer_syntax = true;
        if (self.index < self.text.len and self.text[self.index] == '.') {
            integer_syntax = false;
            self.index += 1;
            if (self.index >= self.text.len or !std.ascii.isDigit(self.text[self.index])) return error.SyntaxError;
            while (self.index < self.text.len and std.ascii.isDigit(self.text[self.index])) self.index += 1;
        }
        if (self.index < self.text.len and (self.text[self.index] == 'e' or self.text[self.index] == 'E')) {
            integer_syntax = false;
            self.index += 1;
            if (self.index < self.text.len and (self.text[self.index] == '+' or self.text[self.index] == '-')) self.index += 1;
            if (self.index >= self.text.len or !std.ascii.isDigit(self.text[self.index])) return error.SyntaxError;
            while (self.index < self.text.len and std.ascii.isDigit(self.text[self.index])) self.index += 1;
        }
        const text = self.text[start..self.index];
        if (!integer_syntax) return .{ .text = text, .integer_syntax = false };
        if (!overflow) {
            if (negative) {
                if (magnitude <= @as(u64, 1) << 63) {
                    const signed: i64 = if (magnitude == (@as(u64, 1) << 63))
                        std.math.minInt(i64)
                    else
                        -@as(i64, @intCast(magnitude));
                    return .{ .text = text, .integer = signed, .integer_syntax = true };
                }
            } else if (magnitude <= std.math.maxInt(i64)) {
                return .{ .text = text, .integer = @intCast(magnitude), .integer_syntax = true };
            }
        }
        return .{ .text = text, .integer_syntax = true };
    }
};

fn isNumberFormattedLikeAnInteger(s: []const u8) bool {
    if (s.len == 0) return false;
    var i: usize = 0;
    if (s[0] == '-') {
        if (s.len == 1) return false;
        i = 1;
    }
    if (s[i] == '0') return s.len == i + 1;
    if (s[i] < '1' or s[i] > '9') return false;
    i += 1;
    while (i < s.len) : (i += 1) {
        if (s[i] < '0' or s[i] > '9') return false;
    }
    return true;
}

test "parse object, array, scalars" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const value = try parse(arena.allocator(),
        \\ {"a":1,"b":[true,false,null],"c":"x\n\u00e9","d":-1.5e2}
    , .{});
    const object = value.object;
    try std.testing.expectEqual(@as(usize, 4), object.count());
    try std.testing.expectEqual(@as(i64, 1), object.get("a").?.integer);
    try std.testing.expectEqual(@as(usize, 3), object.get("b").?.array.items.len);
    try std.testing.expectEqualStrings("x\n\xc3\xa9", object.get("c").?.string);
    try std.testing.expectEqual(@as(f64, -150.0), object.get("d").?.float);
}

test "reject duplicate keys and malformed input" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectError(error.DuplicateField, parse(arena.allocator(), "{\"a\":1,\"a\":2}", .{}));
    try std.testing.expectError(error.SyntaxError, parse(arena.allocator(), "{\"a\":01}", .{}));
    try std.testing.expectError(error.SyntaxError, parse(arena.allocator(), "[1,]", .{}));
    try std.testing.expectError(error.UnexpectedEndOfInput, parse(arena.allocator(), "{\"a\":", .{}));
    try std.testing.expectError(error.SyntaxError, parse(arena.allocator(), "\"\\ud800\"", .{}));
    try std.testing.expectError(error.DepthLimitExceeded, parse(arena.allocator(), "[[[0]]]", .{ .max_depth = 2 }));
}

test "default nesting limit matches upstream protobuf JSON parsers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const ok = try allocator.alloc(u8, 201);
    @memset(ok[0..100], '[');
    ok[100] = '0';
    @memset(ok[101..], ']');
    _ = try parse(allocator, ok, .{});

    const bad = try allocator.alloc(u8, 203);
    @memset(bad[0..101], '[');
    bad[101] = '0';
    @memset(bad[102..], ']');
    try std.testing.expectError(error.DepthLimitExceeded, parse(allocator, bad, .{}));
}
