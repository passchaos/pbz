const std = @import("std");
const pbz = @import("pbz");

pub const proto_package = "demo.streaming";
pub const proto_syntax = "proto3";

pub const demo = struct {
    pub const streaming = struct {
        pub const Event = struct {
            pub const id_number = 1;
            pub const note_number = 2;

            pub const id_field = struct {
                pub const number = 1;
                pub const name = "id";
                pub const json_name = "id";
                pub const cardinality = "optional";
                pub const kind = "int32";
                pub const type_name = "int32";
                pub const zig_type = "i32";
                pub const has_type_ref = false;
                pub const type_ref = void;
                pub const has_enum_ref = false;
                pub const enum_ref = void;
                pub const has_presence = false;
                pub const default_value = "";
                pub const is_packed = false;
            };
            pub const note_field = struct {
                pub const number = 2;
                pub const name = "note";
                pub const json_name = "note";
                pub const cardinality = "optional";
                pub const kind = "string";
                pub const type_name = "string";
                pub const zig_type = "[]const u8";
                pub const has_type_ref = false;
                pub const type_ref = void;
                pub const has_enum_ref = false;
                pub const enum_ref = void;
                pub const has_presence = false;
                pub const default_value = "";
                pub const is_packed = false;
            };

            id: i32 = 0,
            note: []const u8 = "",
            _json_arena: ?*std.heap.ArenaAllocator = null,
            _unknown_fields: []const []const u8 = &.{},

            pub fn init() @This() {
                return .{};
            }

            pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
                pbz.wire.freeRawFields(allocator, self._unknown_fields);
                if (self._json_arena) |arena| { const child_allocator = arena.child_allocator; arena.deinit(); child_allocator.destroy(arena); }
                self.* = undefined;
            }

            pub fn cloneOwned(self: @This(), allocator: std.mem.Allocator) !@This() {
                var out = @This().init();
                errdefer out.deinit(allocator);
                const owned_allocator = try out._pbzOwnedAllocator(allocator);
                out.id = self.id;
                out.note = try owned_allocator.dupe(u8, self.note);
                out._unknown_fields = try pbz.wire.cloneRawFields(allocator, self._unknown_fields);
                return out;
            }

            fn _pbzOwnedAllocator(self: *@This(), allocator: std.mem.Allocator) !std.mem.Allocator {
                if (self._json_arena == null) {
                    const arena = try allocator.create(std.heap.ArenaAllocator);
                    errdefer allocator.destroy(arena);
                    arena.* = std.heap.ArenaAllocator.init(allocator);
                    self._json_arena = arena;
                }
                return self._json_arena.?.allocator();
            }

            pub fn unknownFieldCount(self: @This()) usize {
                return self._unknown_fields.len;
            }

            pub fn unknownFields(self: @This()) []const []const u8 {
                return self._unknown_fields;
            }

            pub fn unknownFieldCountByNumber(self: @This(), number: pbz.FieldNumber) !usize {
                return try pbz.wire.rawFieldCountByNumber(self._unknown_fields, number);
            }

            pub fn hasUnknownFieldNumber(self: @This(), number: pbz.FieldNumber) !bool {
                return (try self.unknownFieldCountByNumber(number)) != 0;
            }

            pub fn unknownFieldsByNumberAlloc(self: @This(), allocator: std.mem.Allocator, number: pbz.FieldNumber) ![]const []const u8 {
                return try pbz.wire.rawFieldsByNumberAlloc(allocator, self._unknown_fields, number);
            }

            pub fn appendUnknownRaw(self: *@This(), allocator: std.mem.Allocator, raw: []const u8) !void {
                try pbz.wire.appendRawFieldClone(allocator, &self._unknown_fields, raw);
            }

            pub fn clearUnknownFieldsByNumber(self: *@This(), allocator: std.mem.Allocator, number: pbz.FieldNumber) !void {
                try pbz.wire.clearRawFieldsByNumber(allocator, &self._unknown_fields, number);
            }

            pub fn clearUnknownFields(self: *@This(), allocator: std.mem.Allocator) void {
                pbz.wire.clearRawFields(allocator, &self._unknown_fields);
            }

            pub fn noteFieldView(bytes: []const u8) !?[]const u8 {
                return try pbz.wire.bytesFieldView(bytes, 2);
            }

            pub fn noteFieldSlices(header: *[20]u8, value: []const u8) !pbz.wire.BorrowedFieldSlices {
                return try pbz.wire.lengthDelimitedFieldSlices(header, 2, value);
            }

            pub fn noteStringView(bytes: []const u8) !?[]const u8 {
                return try noteFieldView(bytes);
            }

            pub fn noteStringSlices(header: *[20]u8, value: []const u8) !pbz.wire.BorrowedFieldSlices {
                return try noteFieldSlices(header, value);
            }


            // no same-file extension accessors

            pub fn mergeFrom(self: *@This(), allocator: std.mem.Allocator, other: @This()) !void {
                if (other.id != 0) self.id = other.id;
                if (other.note.len != 0) self.note = other.note;
                try pbz.wire.appendRawFieldsClone(allocator, &self._unknown_fields, other._unknown_fields);
            }

            pub fn encodedSize(self: @This()) usize {
                var size: usize = 0;
                if (self.id != 0) size += 1 + pbz.wire.encodedVarintSize(@as(u64, @bitCast(@as(i64, self.id))));
                if (self.note.len != 0) size += 1 + pbz.wire.encodedVarintSize(self.note.len) + self.note.len;
                for (self._unknown_fields) |raw| size += raw.len;
                return size;
            }

            pub fn writeTo(self: @This(), w: *pbz.Writer) !void {
                if (self.id != 0) try w.writeInt32(1, self.id);
                if (self.note.len != 0) { if (!pbz.validateUtf8(self.note)) return error.InvalidUtf8; try w.writeString(2, self.note); }
                for (self._unknown_fields) |raw| try w.appendSlice(raw);
            }

            pub fn writeToAssumeCapacity(self: @This(), w: *pbz.Writer) !void {
                if (self.id != 0) w.writeInt32AssumeCapacity(1, self.id);
                if (self.note.len != 0) { if (!pbz.validateUtf8(self.note)) return error.InvalidUtf8; w.writeStringAssumeCapacity(2, self.note); }
                for (self._unknown_fields) |raw| w.appendSliceAssumeCapacity(raw);
            }

            pub fn encode(self: @This(), allocator: std.mem.Allocator) ![]u8 {
                var w = pbz.Writer.init(allocator);
                errdefer w.deinit();
                try w.bytes.ensureTotalCapacity(allocator, self.encodedSize());
                try self.writeToAssumeCapacity(&w);
                return try w.toOwnedSlice();
            }

            pub fn encodeInto(self: @This(), buffer: []u8) ![]u8 {
                const size = self.encodedSize();
                if (buffer.len < size) return error.NoSpaceLeft;
                var w = pbz.Writer.initBuffer(std.heap.page_allocator, buffer[0..size]);
                try self.writeToAssumeCapacity(&w);
                return buffer[0..w.slice().len];
            }

            pub fn encodeIntoAssumeCapacity(self: @This(), buffer: []u8) ![]u8 {
                var index: usize = 0;
                if (self.id != 0) { buffer[index] = 8; index += 1; pbz.wire.writeVarintToSlice(buffer, &index, @as(u64, @bitCast(@as(i64, self.id)))); }
                if (self.note.len != 0) { if (!pbz.validateUtf8(self.note)) return error.InvalidUtf8; buffer[index] = 18; index += 1; pbz.wire.writeVarintToSlice(buffer, &index, self.note.len); @memcpy(buffer[index..][0..self.note.len], self.note); index += self.note.len; }
                for (self._unknown_fields) |raw| { @memcpy(buffer[index..][0..raw.len], raw); index += raw.len; }
                return buffer[0..index];
            }

            pub fn encodeIntoAssumeCapacityTrustedUtf8(self: @This(), buffer: []u8) ![]u8 {
                var index: usize = 0;
                if (self.id != 0) { buffer[index] = 8; index += 1; pbz.wire.writeVarintToSlice(buffer, &index, @as(u64, @bitCast(@as(i64, self.id)))); }
                if (self.note.len != 0) { buffer[index] = 18; index += 1; pbz.wire.writeVarintToSlice(buffer, &index, self.note.len); @memcpy(buffer[index..][0..self.note.len], self.note); index += self.note.len; }
                for (self._unknown_fields) |raw| { @memcpy(buffer[index..][0..raw.len], raw); index += raw.len; }
                return buffer[0..index];
            }

            pub fn writeDeterministicTo(self: @This(), allocator: std.mem.Allocator, w: *pbz.Writer) !void {
                if (self.id != 0) try w.writeInt32(1, self.id);
                if (self.note.len != 0) { if (!pbz.validateUtf8(self.note)) return error.InvalidUtf8; try w.writeString(2, self.note); }
                try pbz.wire.writeRawFieldsDeterministic(allocator, self._unknown_fields, w);
            }

            pub fn writeDeterministicToAssumeCapacity(self: @This(), allocator: std.mem.Allocator, w: *pbz.Writer) !void {
                if (self.id != 0) w.writeInt32AssumeCapacity(1, self.id);
                if (self.note.len != 0) { if (!pbz.validateUtf8(self.note)) return error.InvalidUtf8; w.writeStringAssumeCapacity(2, self.note); }
                try pbz.wire.writeRawFieldsDeterministicAssumeCapacity(allocator, self._unknown_fields, w);
            }

            pub fn encodeDeterministic(self: @This(), allocator: std.mem.Allocator) ![]u8 {
                var w = pbz.Writer.init(allocator);
                errdefer w.deinit();
                try w.bytes.ensureTotalCapacity(allocator, self.encodedSize());
                try self.writeDeterministicToAssumeCapacity(allocator, &w);
                return try w.toOwnedSlice();
            }

            pub fn encodeDeterministicInto(self: @This(), allocator: std.mem.Allocator, buffer: []u8) ![]u8 {
                const size = self.encodedSize();
                if (buffer.len < size) return error.NoSpaceLeft;
                var w = pbz.Writer.initBuffer(std.heap.page_allocator, buffer[0..size]);
                try self.writeDeterministicToAssumeCapacity(allocator, &w);
                return buffer[0..w.slice().len];
            }

            pub fn encodeDeterministicIntoAssumeCapacity(self: @This(), allocator: std.mem.Allocator, buffer: []u8) ![]u8 {
                var w = pbz.Writer.initBuffer(std.heap.page_allocator, buffer);
                try self.writeDeterministicToAssumeCapacity(allocator, &w);
                return buffer[0..w.slice().len];
            }

            pub fn encodeDeterministicInitialized(self: @This(), allocator: std.mem.Allocator) ![]u8 {
                try self.validateRequiredRecursive(allocator);
                return try self.encodeDeterministic(allocator);
            }

            pub fn encodeInitialized(self: @This(), allocator: std.mem.Allocator) ![]u8 {
                try self.validateRequiredRecursive(allocator);
                return try self.encode(allocator);
            }

            pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) !@This() {
                var r = pbz.Reader.init(bytes);
                return try @This().decodeFromReader(allocator, &r);
            }

            pub fn decodeFromReader(allocator: std.mem.Allocator, r: *pbz.Reader) !@This() {
                var self = @This().init();
                errdefer self.deinit(allocator);
                var _unknown_fields_list: std.ArrayList([]const u8) = .empty;
                errdefer pbz.wire.deinitRawFieldList(allocator, &_unknown_fields_list);
                while (!r.eof()) {
                    const raw_tag_start = r.position();
                    const first_tag_byte = try r.readByte();
                    const raw_tag: u64 = if (first_tag_byte < 0x80) first_tag_byte else blk: { r.index = raw_tag_start; break :blk try r.readVarint(); };
                    switch (raw_tag) {
                        8 => { self.id = try r.readInt32(); },
                        18 => { self.note = try r.readBytes(); if (!pbz.validateUtf8(self.note)) return error.InvalidUtf8; },
                        else => try pbz.wire.appendSkippedRawField(allocator, &_unknown_fields_list, r, raw_tag_start, try pbz.wire.Tag.decode(raw_tag)),
                    }
                }
                self._unknown_fields = try pbz.wire.rawFieldListToOwnedSlice(allocator, &_unknown_fields_list);
                return self;
            }

            pub fn decodeReuse(self: *@This(), allocator: std.mem.Allocator, bytes: []const u8) !void {
                pbz.wire.clearRawFields(allocator, &self._unknown_fields);
                if (self._json_arena) |arena| { const child_allocator = arena.child_allocator; arena.deinit(); child_allocator.destroy(arena); self._json_arena = null; }
                self.id = 0;
                self.note = "";
                errdefer self.deinit(allocator);
                var _unknown_fields_list: std.ArrayList([]const u8) = .empty;
                errdefer pbz.wire.deinitRawFieldList(allocator, &_unknown_fields_list);
                var r = pbz.Reader.init(bytes);
                while (!r.eof()) {
                    const raw_tag_start = r.position();
                    const first_tag_byte = try r.readByte();
                    const raw_tag: u64 = if (first_tag_byte < 0x80) first_tag_byte else blk: { r.index = raw_tag_start; break :blk try r.readVarint(); };
                    switch (raw_tag) {
                        8 => { self.id = try r.readInt32(); },
                        18 => { self.note = try r.readBytes(); if (!pbz.validateUtf8(self.note)) return error.InvalidUtf8; },
                        else => try pbz.wire.appendSkippedRawField(allocator, &_unknown_fields_list, &r, raw_tag_start, try pbz.wire.Tag.decode(raw_tag)),
                    }
                }
                self._unknown_fields = try pbz.wire.rawFieldListToOwnedSlice(allocator, &_unknown_fields_list);
            }

            pub fn decodeOwned(allocator: std.mem.Allocator, bytes: []const u8) !@This() {
                var decoded = try @This().decode(allocator, bytes);
                defer decoded.deinit(allocator);
                return try decoded.cloneOwned(allocator);
            }

            pub fn decodeInitialized(allocator: std.mem.Allocator, bytes: []const u8) !@This() {
                var self = try @This().decode(allocator, bytes);
                errdefer self.deinit(allocator);
                try self.validateRequiredRecursive(allocator);
                return self;
            }

            pub fn decodeOwnedInitialized(allocator: std.mem.Allocator, bytes: []const u8) !@This() {
                var self = try @This().decodeOwned(allocator, bytes);
                errdefer self.deinit(allocator);
                try self.validateRequiredRecursive(allocator);
                return self;
            }

            pub fn missingRequiredFieldName(self: @This()) ?[]const u8 {
                _ = self;
                return null;
            }

            pub fn missingRequiredFieldPath(self: @This(), allocator: std.mem.Allocator) !?[]u8 {
                _ = self; _ = allocator;
                return null;
            }

            pub fn validateRequired(self: @This()) !void {
                if (self.missingRequiredFieldName() != null) return error.MissingRequiredField;
            }

            pub fn validateRequiredRecursive(self: @This(), allocator: std.mem.Allocator) !void {
                try self.validateRequired();
                _ = allocator;
            }

            pub const JsonStringifyOptions = struct { enum_as_name: bool = true, preserve_proto_field_names: bool = false, always_print_primitive_fields: bool = false };

            pub fn jsonStringifyAlloc(self: @This(), allocator: std.mem.Allocator) ![]u8 {
                return try self.jsonStringifyAllocWithOptions(allocator, .{});
            }

            pub fn jsonStringifyAllocWithOptions(self: @This(), allocator: std.mem.Allocator, options: @This().JsonStringifyOptions) ![]u8 {
                var out: std.Io.Writer.Allocating = .init(allocator);
                errdefer out.deinit();
                try self.jsonStringifyWithOptions(allocator, &out.writer, options);
                return try out.toOwnedSlice();
            }

            pub fn jsonStringify(self: @This(), writer: *std.Io.Writer) !void {
                try self.jsonStringifyWithOptions(std.heap.page_allocator, writer, .{});
            }

            pub fn jsonStringifyWithAllocator(self: @This(), allocator: std.mem.Allocator, writer: *std.Io.Writer) !void {
                try self.jsonStringifyWithOptions(allocator, writer, .{});
            }

            pub fn jsonStringifyWithOptions(self: @This(), allocator: std.mem.Allocator, writer: *std.Io.Writer, options: @This().JsonStringifyOptions) !void {
                _ = allocator;
                try writer.writeAll("{");
                var first = true;
                if (self.id != 0 or options.always_print_primitive_fields) {
                    if (!first) try writer.writeAll(","); first = false;
                    try writer.writeAll(if (options.preserve_proto_field_names) "\"id\":" else "\"id\":");
                    const value = self.id;
                    try writer.print("{d}", .{value});
                }
                if (self.note.len != 0 or options.always_print_primitive_fields) {
                    if (!first) try writer.writeAll(","); first = false;
                    try writer.writeAll(if (options.preserve_proto_field_names) "\"note\":" else "\"note\":");
                    const value = self.note;
                    try @This().jsonWriteString(writer, value);
                }
                try writer.writeAll("}");
            }

            pub const JsonParseOptions = struct { ignore_unknown_fields: bool = false };

            pub fn jsonParse(allocator: std.mem.Allocator, text: []const u8) !@This() {
                return try @This().jsonParseWithOptions(allocator, text, .{});
            }

            pub fn jsonParseWithOptions(allocator: std.mem.Allocator, text: []const u8, options: @This().JsonParseOptions) !@This() {
                var arena = try allocator.create(std.heap.ArenaAllocator);
                errdefer allocator.destroy(arena);
                arena.* = std.heap.ArenaAllocator.init(allocator);
                errdefer arena.deinit();
                const parsed = try std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), text, .{});
                var self = try @This().jsonParseValueWithOptions(allocator, arena.allocator(), parsed, options);
                self._json_arena = arena;
                return self;
            }

            /// Parse a pre-parsed JSON subtree without serializing it back to text first.
            /// The caller must keep `arena_allocator` alive for borrowed string/bytes data.
            pub fn jsonParseValue(allocator: std.mem.Allocator, arena_allocator: std.mem.Allocator, json_value: std.json.Value) !@This() {
                return try @This().jsonParseValueWithOptions(allocator, arena_allocator, json_value, .{});
            }

            /// Option-bearing variant of jsonParseValue for generated nested-message parsers.
            pub fn jsonParseValueWithOptions(allocator: std.mem.Allocator, arena_allocator: std.mem.Allocator, json_value: std.json.Value, options: @This().JsonParseOptions) !@This() {
                var self = @This().init();
                errdefer self.deinit(allocator);
                try self.jsonFillFromValue(allocator, arena_allocator, json_value, options);
                return self;
            }

            pub fn jsonParseInitialized(allocator: std.mem.Allocator, text: []const u8) !@This() {
                var self = try @This().jsonParse(allocator, text);
                errdefer self.deinit(allocator);
                try self.validateRequiredRecursive(allocator);
                return self;
            }

            pub fn jsonParseInitializedWithOptions(allocator: std.mem.Allocator, text: []const u8, options: @This().JsonParseOptions) !@This() {
                var self = try @This().jsonParseWithOptions(allocator, text, options);
                errdefer self.deinit(allocator);
                try self.validateRequiredRecursive(allocator);
                return self;
            }

            fn jsonFillFromValue(self: *@This(), allocator: std.mem.Allocator, arena_allocator: std.mem.Allocator, json_value: std.json.Value, options: @This().JsonParseOptions) !void {
                _ = allocator;
                _ = arena_allocator;
                const object = switch (json_value) { .object => |object| object, else => return error.TypeMismatch };
                var it = object.iterator();
                while (it.next()) |entry| {
                    const key = entry.key_ptr.*;
                    const value = entry.value_ptr.*;
                    if (value == .null) {
                        if (std.mem.eql(u8, key, "id") or std.mem.eql(u8, key, "id")) {
                            self.id = 0;
                            continue;
                        }
                        if (std.mem.eql(u8, key, "note") or std.mem.eql(u8, key, "note")) {
                            self.note = "";
                            continue;
                        }
                        if (options.ignore_unknown_fields) continue;
                        return error.UnknownField;
                    }
                    if (std.mem.eql(u8, key, "id") or std.mem.eql(u8, key, "id")) {
                        self.id = try @This().jsonInt(i32, value);
                        continue;
                    }
                    if (std.mem.eql(u8, key, "note") or std.mem.eql(u8, key, "note")) {
                        self.note = try @This().jsonString(value);
                        continue;
                    }
                    if (options.ignore_unknown_fields) continue;
                    return error.UnknownField;
                }
            }

            fn jsonInt(comptime T: type, value: std.json.Value) !T {
    return switch (value) {
        .integer => |v| std.math.cast(T, v) orelse error.Overflow,
        .number_string, .string => |text| try std.fmt.parseInt(T, text, 10),
        else => error.TypeMismatch,
    };
}

fn jsonFloat(comptime T: type, value: std.json.Value) !T {
    return switch (value) {
        .integer => |v| @as(T, @floatFromInt(v)),
        .float => |v| @floatCast(v),
        .number_string => |text| try std.fmt.parseFloat(T, text),
        .string => |text| if (std.mem.eql(u8, text, "NaN"))
            std.math.nan(T)
        else if (std.mem.eql(u8, text, "Infinity"))
            std.math.inf(T)
        else if (std.mem.eql(u8, text, "-Infinity"))
            -std.math.inf(T)
        else
            try std.fmt.parseFloat(T, text),
        else => error.TypeMismatch,
    };
}

fn jsonBool(value: std.json.Value) !bool {
    return switch (value) {
        .bool => |v| v,
        else => error.TypeMismatch,
    };
}

fn jsonString(value: std.json.Value) ![]const u8 {
    return switch (value) {
        .string => |v| v,
        else => error.TypeMismatch,
    };
}

fn jsonBytes(allocator: std.mem.Allocator, value: std.json.Value) ![]const u8 {
    return try @This().jsonDecodeBase64(allocator, try @This().jsonString(value));
}

fn jsonEnum(value: std.json.Value, comptime names: []const []const u8, comptime numbers: []const i32, comptime closed: bool) !i32 {
    return switch (value) {
        .integer => |v| try @This().jsonEnumNumber(std.math.cast(i32, v) orelse return error.Overflow, numbers, closed),
        .number_string => |text| try @This().jsonEnumNumber(try std.fmt.parseInt(i32, text, 10), numbers, closed),
        .string => |text| {
            inline for (names, 0..) |name, i| {
                if (std.mem.eql(u8, text, name)) return numbers[i];
            }
            return try @This().jsonEnumNumber(std.fmt.parseInt(i32, text, 10) catch return error.InvalidEnumValue, numbers, closed);
        },
        else => error.TypeMismatch,
    };
}

fn jsonEnumNumber(value: i32, comptime numbers: []const i32, comptime closed: bool) !i32 {
    if (closed) {
        inline for (numbers) |number| {
            if (value == number) return value;
        }
        return error.InvalidEnumValue;
    }
    return value;
}

fn jsonWriteEnum(writer: *std.Io.Writer, value: i32, comptime names: []const []const u8, comptime numbers: []const i32, enum_as_name: bool) !void {
    if (!enum_as_name) return try writer.print("{d}", .{value});
    inline for (numbers, 0..) |number, i| {
        if (value == number) return try std.json.Stringify.value(names[i], .{}, writer);
    }
    try writer.print("{d}", .{value});
}

fn textWriteEnum(writer: *std.Io.Writer, value: i32, comptime names: []const []const u8, comptime numbers: []const i32, enum_as_name: bool) !void {
    if (!enum_as_name) return try writer.print("{d}", .{value});
    inline for (numbers, 0..) |number, i| {
        if (value == number) return try writer.writeAll(names[i]);
    }
    try writer.print("{d}", .{value});
}

fn enumKnown(value: i32, comptime numbers: []const i32) bool {
    inline for (numbers) |number| {
        if (value == number) return true;
    }
    return false;
}

fn textFieldValue(line: []const u8, comptime name: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, line, name)) return null;
    var rest = line[name.len..];
    rest = std.mem.trimStart(u8, rest, " \t");
    if (rest.len == 0 or rest[0] != ':') return null;
    return std.mem.trim(u8, rest[1..], " \t\r");
}

fn textBlockField(line: []const u8, comptime name: []const u8) bool {
    if (!std.mem.startsWith(u8, line, name)) return false;
    var rest = std.mem.trimStart(u8, line[name.len..], " \t");
    if (rest.len != 0 and rest[0] == ':') {
        rest = std.mem.trimStart(u8, rest[1..], " \t");
    }
    return std.mem.eql(u8, rest, "{") or std.mem.eql(u8, rest, "<");
}

fn textNormalizeSeparators(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    var quote: ?u8 = null;
    var escaped = false;
    for (text) |c| {
        if (escaped) {
            escaped = false;
            try out.append(allocator, c);
            continue;
        }
        if (quote) |q| {
            if (c == '\\') {
                escaped = true;
            } else if (c == q) {
                quote = null;
            }
            try out.append(allocator, c);
            continue;
        }
        if (c == '"' or c == '\'') {
            quote = c;
            try out.append(allocator, c);
        } else if (c == ';' or c == ',') {
            try out.append(allocator, '\n');
        } else if (c == '{' or c == '<') {
            try out.append(allocator, c);
            try out.append(allocator, '\n');
        } else if (c == '}' or c == '>') {
            try out.append(allocator, '\n');
            try out.append(allocator, c);
            try out.append(allocator, '\n');
        } else {
            try out.append(allocator, c);
        }
    }
    return try out.toOwnedSlice(allocator);
}

fn textNeedsSeparatorNormalization(text: []const u8) bool {
    var quote: ?u8 = null;
    var escaped = false;
    for (text, 0..) |c, index| {
        if (escaped) {
            escaped = false;
            continue;
        }
        if (quote) |q| {
            if (c == '\\') {
                escaped = true;
            } else if (c == q) {
                quote = null;
            }
            continue;
        }
        if (c == '"' or c == '\'') {
            quote = c;
        } else if (c == ';' or c == ',') {
            return true;
        } else if ((c == '{' or c == '<') and !@This().textSeparatorHasLineAfter(text, index)) {
            return true;
        } else if ((c == '}' or c == '>') and !@This().textSeparatorHasLineBefore(text, index)) {
            return true;
        }
    }
    return false;
}

fn textSeparatorHasLineAfter(text: []const u8, index: usize) bool {
    var i = index + 1;
    while (i < text.len and (text[i] == ' ' or text[i] == '\t' or text[i] == '\r')) : (i += 1) {}
    return i >= text.len or text[i] == '\n';
}

fn textSeparatorHasLineBefore(text: []const u8, index: usize) bool {
    var i = index;
    while (i > 0 and (text[i - 1] == ' ' or text[i - 1] == '\t' or text[i - 1] == '\r')) : (i -= 1) {}
    return i == 0 or text[i - 1] == '\n';
}

fn textCleanLine(raw_line: []const u8) []const u8 {
    var end = raw_line.len;
    var quote: ?u8 = null;
    var escaped = false;
    for (raw_line, 0..) |c, i| {
        if (escaped) {
            escaped = false;
            continue;
        }
        if (quote) |q| {
            if (c == '\\') {
                escaped = true;
            } else if (c == q) {
                quote = null;
            }
            continue;
        }
        if (c == '"' or c == '\'') {
            quote = c;
        } else if (c == '#') {
            end = i;
            break;
        }
    }
    var line = std.mem.trim(u8, raw_line[0..end], " \t\r");
    while (line.len != 0 and (line[line.len - 1] == ';' or line[line.len - 1] == ',')) {
        line = std.mem.trim(u8, line[0 .. line.len - 1], " \t\r");
    }
    return line;
}

fn textBool(value: []const u8) !bool {
    if (std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "t") or std.mem.eql(u8, value, "1")) return true;
    if (std.mem.eql(u8, value, "false") or std.mem.eql(u8, value, "f") or std.mem.eql(u8, value, "0")) return false;
    return error.TypeMismatch;
}

fn textInt(comptime T: type, value: []const u8) !T {
    return try std.fmt.parseInt(T, value, 0);
}

fn textFloat(comptime T: type, value: []const u8) !T {
    var body = value;
    var negative = false;
    if (body.len != 0 and (body[0] == '-' or body[0] == '+')) {
        negative = body[0] == '-';
        body = body[1..];
    }
    if (std.ascii.eqlIgnoreCase(body, "nan")) return std.math.nan(T);
    if (std.ascii.eqlIgnoreCase(body, "inf") or std.ascii.eqlIgnoreCase(body, "infinity")) {
        const parsed = std.math.inf(T);
        return if (negative) -parsed else parsed;
    }
    return try std.fmt.parseFloat(T, value);
}

fn textUnquote(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    var i: usize = 0;
    var read_quoted = false;
    while (true) {
        while (i < value.len and std.ascii.isWhitespace(value[i])) : (i += 1) {}
        if (i >= value.len) break;
        const quote = value[i];
        if (quote != '"' and quote != '\'') {
            if (read_quoted) return error.InvalidEscape;
            try out.appendSlice(allocator, value[i..]);
            break;
        }
        read_quoted = true;
        i += 1;
        var closed = false;
        while (i < value.len) {
            const c = value[i];
            i += 1;
            if (c == quote) {
                closed = true;
                break;
            }
            if (c != '\\') {
                try out.append(allocator, c);
                continue;
            }
            if (i >= value.len) return error.InvalidEscape;
            const esc = value[i];
            i += 1;
            switch (esc) {
                'n' => try out.append(allocator, '\n'),
                'r' => try out.append(allocator, '\r'),
                't' => try out.append(allocator, '\t'),
                'a' => try out.append(allocator, 0x07),
                'b' => try out.append(allocator, 0x08),
                'f' => try out.append(allocator, 0x0c),
                'v' => try out.append(allocator, 0x0b),
                '\\' => try out.append(allocator, '\\'),
                '"' => try out.append(allocator, '"'),
                '\'' => try out.append(allocator, '\''),
                '?' => try out.append(allocator, '?'),
                'x', 'X' => {
                    const start = i;
                    var end = i;
                    while (end < value.len and end < start + 2 and @This().textHexDigit(value[end]) != null) : (end += 1) {}
                    if (end == start) return error.InvalidEscape;
                    try out.append(allocator, try std.fmt.parseInt(u8, value[start..end], 16));
                    i = end;
                },
                '0'...'7' => {
                    const start = i - 1;
                    var end = i;
                    while (end < value.len and end < start + 3 and value[end] >= '0' and value[end] <= '7') : (end += 1) {}
                    try out.append(allocator, try std.fmt.parseInt(u8, value[start..end], 8));
                    i = end;
                },
                else => |unknown| try out.append(allocator, unknown),
            }
        }
        if (!closed) return error.InvalidEscape;
    }
    return try out.toOwnedSlice(allocator);
}

fn textHexDigit(c: u8) ?u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => null,
    };
}

fn textEnum(value: []const u8, comptime names: []const []const u8, comptime numbers: []const i32, comptime closed: bool) !i32 {
    inline for (names, 0..) |name, i| {
        if (std.mem.eql(u8, value, name)) return numbers[i];
    }
    const number = try std.fmt.parseInt(i32, value, 10);
    if (closed) {
        inline for (numbers) |known| {
            if (number == known) return number;
        }
        return error.InvalidEnumValue;
    }
    return number;
}

fn textUnknownField(allocator: std.mem.Allocator, line: []const u8) !?[]const u8 {
    var colon_index: ?usize = null;
    for (line, 0..) |c, i| {
        if (c == ':') { colon_index = i; break; }
        if (i == 0 and !std.ascii.isDigit(c)) return null;
        if (i != 0 and !std.ascii.isDigit(c)) return null;
    }
    const idx = colon_index orelse return null;
    const number = try std.fmt.parseInt(pbz.FieldNumber, std.mem.trim(u8, line[0..idx], " \t\r"), 10);
    const value = std.mem.trim(u8, line[idx + 1 ..], " \t\r");
    var raw = pbz.Writer.init(allocator);
    defer raw.deinit();
    if (value.len >= 2 and ((value[0] == '"' and value[value.len - 1] == '"') or (value[0] == '\'' and value[value.len - 1] == '\''))) {
        const bytes = try @This().textUnquote(allocator, value);
        defer allocator.free(bytes);
        try raw.writeBytes(number, bytes);
    } else {
        try raw.writeUInt64(number, try std.fmt.parseInt(u64, value, 0));
    }
    return try raw.toOwnedSlice();
}

fn textUnknownGroup(allocator: std.mem.Allocator, line: []const u8, lines: anytype) !?[]const u8 {
    var end: usize = 0;
    while (end < line.len and std.ascii.isDigit(line[end])) : (end += 1) {}
    if (end == 0) return null;
    const rest = std.mem.trim(u8, line[end..], " \t\r");
    if (!std.mem.eql(u8, rest, "{") and !std.mem.eql(u8, rest, "<")) return null;
    const number = try std.fmt.parseInt(pbz.FieldNumber, line[0..end], 10);
    var raw = pbz.Writer.init(allocator);
    defer raw.deinit();
    try raw.writeTag(number, .start_group);
    while (lines.next()) |raw_line| {
        const child = @This().textCleanLine(raw_line);
        if (child.len == 0) continue;
        if (std.mem.eql(u8, child, "}") or std.mem.eql(u8, child, ">")) {
            try raw.writeTag(number, .end_group);
            return try raw.toOwnedSlice();
        }
        if (try @This().textUnknownField(allocator, child)) |field_raw| {
            defer allocator.free(field_raw);
            try raw.appendSlice(field_raw);
            continue;
        }
        if (try @This().textUnknownGroup(allocator, child, lines)) |group_raw| {
            defer allocator.free(group_raw);
            try raw.appendSlice(group_raw);
            continue;
        }
        return error.UnknownField;
    }
    return error.UnexpectedEof;
}

fn textWriteUnknownRaw(raw: []const u8, writer: *std.Io.Writer) !void {
    var r = pbz.Reader.init(raw);
    while (try r.nextTag()) |tag| try @This().textWriteUnknownField(tag, &r, writer);
}

fn textWriteQuotedBytes(bytes: []const u8, writer: *std.Io.Writer) !void {
    try writer.writeByte('"');
    for (bytes) |c| {
        if (c == '\\') try writer.writeAll("\\\\") else if (c == '"') try writer.writeAll("\\\"") else if (c == '\n') try writer.writeAll("\\n") else if (c == '\r') try writer.writeAll("\\r") else if (c == '\t') try writer.writeAll("\\t") else if (c >= 0x20 and c <= 0x7e) try writer.writeByte(c) else try writer.print("\\{o:0>3}", .{c});
    }
    try writer.writeByte('"');
}

fn textWriteUnknownField(tag: pbz.wire.Tag, r: *pbz.Reader, writer: *std.Io.Writer) !void {
    switch (tag.wire_type) {
        .varint => try writer.print("{d}: {d}\n", .{ tag.number, try r.readVarint() }),
        .fixed32 => try writer.print("{d}: {d}\n", .{ tag.number, try r.readFixed32() }),
        .fixed64 => try writer.print("{d}: {d}\n", .{ tag.number, try r.readFixed64() }),
        .length_delimited => {
            try writer.print("{d}: ", .{tag.number});
            try @This().textWriteQuotedBytes(try r.readBytes(), writer);
            try writer.writeByte('\n');
        },
        .start_group => {
            try writer.print("{d} {{\n", .{tag.number});
            while (try r.nextTag()) |inner| {
                if (inner.wire_type == .end_group) {
                    if (inner.number != tag.number) return error.InvalidFieldNumber;
                    try writer.writeAll("}\n");
                    return;
                }
                try @This().textWriteUnknownField(inner, r, writer);
            }
            return error.TruncatedInput;
        },
        .end_group => return error.InvalidWireType,
    }
}

fn textBlock(allocator: std.mem.Allocator, lines: anytype) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    var depth: usize = 1;
    while (lines.next()) |raw_line| {
        const line = @This().textCleanLine(raw_line);
        if (line.len == 0) continue;
        if (std.mem.eql(u8, line, "}") or std.mem.eql(u8, line, ">")) {
            depth -= 1;
            if (depth == 0) return try out.toOwnedSlice();
        }
        if (std.mem.endsWith(u8, line, "{") or std.mem.endsWith(u8, line, "<")) depth += 1;
        try out.writer.writeAll(line);
        try out.writer.writeByte('\n');
    }
    return error.UnexpectedEof;
}

fn jsonDecodeBase64(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    return @This().jsonDecodeBase64With(allocator, &std.base64.standard.Decoder, value) catch
        @This().jsonDecodeBase64With(allocator, &std.base64.url_safe.Decoder, value) catch
        @This().jsonDecodeBase64With(allocator, &std.base64.standard_no_pad.Decoder, value) catch
        @This().jsonDecodeBase64With(allocator, &std.base64.url_safe_no_pad.Decoder, value);
}

fn jsonDecodeBase64With(allocator: std.mem.Allocator, decoder: *const std.base64.Base64Decoder, value: []const u8) ![]u8 {
    const size = try decoder.calcSizeForSlice(value);
    const out = try allocator.alloc(u8, size);
    errdefer allocator.free(out);
    try decoder.decode(out, value);
    return out;
}

fn jsonMapKeyBool(key: []const u8) !bool {
    if (std.mem.eql(u8, key, "true")) return true;
    if (std.mem.eql(u8, key, "false")) return false;
    return error.TypeMismatch;
}

fn jsonWriteString(writer: *std.Io.Writer, value: []const u8) !void {
    if (!pbz.validateUtf8(value)) return error.InvalidUtf8;
    try std.json.Stringify.value(value, .{}, writer);
}

            pub const TextFormatOptions = struct { enum_as_name: bool = true };

            pub fn formatTextAlloc(self: @This(), allocator: std.mem.Allocator) ![]u8 {
                return try self.formatTextAllocWithOptions(allocator, .{});
            }

            pub fn formatTextAllocWithOptions(self: @This(), allocator: std.mem.Allocator, options: @This().TextFormatOptions) ![]u8 {
                var out: std.Io.Writer.Allocating = .init(allocator);
                errdefer out.deinit();
                try self.formatTextWithOptions(allocator, &out.writer, options);
                return try out.toOwnedSlice();
            }

            pub fn formatText(self: @This(), writer: *std.Io.Writer) !void {
                try self.formatTextWithOptions(std.heap.page_allocator, writer, .{});
            }

            pub fn formatTextWithAllocator(self: @This(), allocator: std.mem.Allocator, writer: *std.Io.Writer) !void {
                try self.formatTextWithOptions(allocator, writer, .{});
            }

            pub fn formatTextWithOptions(self: @This(), allocator: std.mem.Allocator, writer: *std.Io.Writer, options: @This().TextFormatOptions) !void {
                _ = allocator;
                _ = options;
                if (self.id != 0) { try writer.writeAll("id: "); const value = self.id; try writer.print("{d}", .{value}); try writer.writeByte('\n'); }
                if (self.note.len != 0) { try writer.writeAll("note: "); const value = self.note; if (!pbz.validateUtf8(value)) return error.InvalidUtf8; try @This().textWriteQuotedBytes(value, writer); try writer.writeByte('\n'); }
                for (self._unknown_fields) |raw| {
                    try @This().textWriteUnknownRaw(raw, writer);
                }
            }

            pub const TextParseOptions = struct { ignore_unknown_fields: bool = false };

            pub fn parseText(allocator: std.mem.Allocator, text: []const u8) !@This() {
                return try @This().parseTextWithOptions(allocator, text, .{});
            }

            pub fn parseTextWithOptions(allocator: std.mem.Allocator, text: []const u8, options: @This().TextParseOptions) !@This() {
                var self = @This().init();
                errdefer self.deinit(allocator);
                var _unknown_fields_list: std.ArrayList([]const u8) = .empty;
                errdefer pbz.wire.deinitRawFieldList(allocator, &_unknown_fields_list);
                const needs_normalized_text = @This().textNeedsSeparatorNormalization(text);
                const normalized_text = if (needs_normalized_text) try @This().textNormalizeSeparators(allocator, text) else text;
                defer if (needs_normalized_text) allocator.free(normalized_text);
                var lines = std.mem.splitScalar(u8, normalized_text, '\n');
                while (lines.next()) |raw_line| {
                    const line = @This().textCleanLine(raw_line);
                    if (line.len == 0) continue;
                    if (@This().textFieldValue(line, "id")) |raw_value| {
                        self.id = try @This().textInt(i32, raw_value);
                        continue;
                    }
                    if (@This().textFieldValue(line, "note")) |raw_value| {
                        self.note = blk: { const decoded = try @This().textUnquote(try self._pbzOwnedAllocator(allocator), raw_value); if (!pbz.validateUtf8(decoded)) return error.InvalidUtf8; break :blk decoded; };
                        continue;
                    }
                    if (try @This().textUnknownField(allocator, line)) |raw| { try pbz.wire.appendOwnedRawField(allocator, &_unknown_fields_list, raw); continue; }
                    if (try @This().textUnknownGroup(allocator, line, &lines)) |raw| { try pbz.wire.appendOwnedRawField(allocator, &_unknown_fields_list, raw); continue; }
                    if (options.ignore_unknown_fields) continue;
                    return error.UnknownField;
                }
                self._unknown_fields = try pbz.wire.rawFieldListToOwnedSlice(allocator, &_unknown_fields_list);
                return self;
            }

            pub fn parseTextInitialized(allocator: std.mem.Allocator, text: []const u8) !@This() {
                var self = try @This().parseText(allocator, text);
                errdefer self.deinit(allocator);
                try self.validateRequiredRecursive(allocator);
                return self;
            }

            pub fn parseTextInitializedWithOptions(allocator: std.mem.Allocator, text: []const u8, options: @This().TextParseOptions) !@This() {
                var self = try @This().parseTextWithOptions(allocator, text, options);
                errdefer self.deinit(allocator);
                try self.validateRequiredRecursive(allocator);
                return self;
            }

        };

        pub const services = struct {
            pub const Pipe = struct {
                pub const name = "Pipe";
                pub const Get = struct {
                    pub const name = "Get";
                    pub const input_type = ".demo.streaming.Event";
                    pub const output_type = ".demo.streaming.Event";
                    pub const input_has_type_ref = true;
                    pub const input_type_ref = Event;
                    pub const output_has_type_ref = true;
                    pub const output_type_ref = Event;
                    pub const client_streaming = false;
                    pub const server_streaming = false;
                };
                pub const Upload = struct {
                    pub const name = "Upload";
                    pub const input_type = ".demo.streaming.Event";
                    pub const output_type = ".demo.streaming.Event";
                    pub const input_has_type_ref = true;
                    pub const input_type_ref = Event;
                    pub const output_has_type_ref = true;
                    pub const output_type_ref = Event;
                    pub const client_streaming = true;
                    pub const server_streaming = false;
                };
                pub const Watch = struct {
                    pub const name = "Watch";
                    pub const input_type = ".demo.streaming.Event";
                    pub const output_type = ".demo.streaming.Event";
                    pub const input_has_type_ref = true;
                    pub const input_type_ref = Event;
                    pub const output_has_type_ref = true;
                    pub const output_type_ref = Event;
                    pub const client_streaming = false;
                    pub const server_streaming = true;
                };
                pub const Chat = struct {
                    pub const name = "Chat";
                    pub const input_type = ".demo.streaming.Event";
                    pub const output_type = ".demo.streaming.Event";
                    pub const input_has_type_ref = true;
                    pub const input_type_ref = Event;
                    pub const output_has_type_ref = true;
                    pub const output_type_ref = Event;
                    pub const client_streaming = true;
                    pub const server_streaming = true;
                };

                pub fn Handler(comptime Impl: type) type {
                    return struct {
                        impl: *Impl,

                        pub fn init(impl: *Impl) @This() { return .{ .impl = impl }; }

                        pub fn Get(self: @This(), allocator: std.mem.Allocator, request: Event) !Event {
                            return try self.impl.Get(allocator, request);
                        }

                        pub fn Upload(self: @This(), allocator: std.mem.Allocator, requests: anytype) !Event {
                            return try self.impl.Upload(allocator, requests);
                        }

                        pub fn Watch(self: @This(), allocator: std.mem.Allocator, request: Event, responses: anytype) !void {
                            return try self.impl.Watch(allocator, request, responses);
                        }

                        pub fn Chat(self: @This(), allocator: std.mem.Allocator, requests: anytype, responses: anytype) !void {
                            return try self.impl.Chat(allocator, requests, responses);
                        }

                        pub fn dispatchRaw(self: @This(), allocator: std.mem.Allocator, method_name: []const u8, request_payload: []const u8) !?[]u8 {
                            if (std.mem.eql(u8, method_name, "Get")) {
                                var request = try Event.decodeOwned(allocator, request_payload);
                                defer request.deinit(allocator);
                                var response = try self.Get(allocator, request);
                                defer response.deinit(allocator);
                                return try response.encode(allocator);
                            }
                            return null;
                        }
                    };
                }

                pub fn Client(comptime Transport: type) type {
                    return struct {
                        transport: Transport,

                        pub fn init(transport: Transport) @This() { return .{ .transport = transport }; }

                        pub fn Get(self: *@This(), allocator: std.mem.Allocator, request: Event) !Event {
                            const request_payload = try request.encode(allocator);
                            defer allocator.free(request_payload);
                            const response_payload = try self.transport.call(allocator, "Pipe", "Get", request_payload);
                            defer allocator.free(response_payload);
                            return try Event.decodeOwned(allocator, response_payload);
                        }

                        pub fn Upload(self: *@This(), allocator: std.mem.Allocator, requests: anytype) !Event {
                            const response_payload = try self.transport.callClientStream(allocator, "Pipe", "Upload", requests);
                            defer allocator.free(response_payload);
                            return try Event.decodeOwned(allocator, response_payload);
                        }

                        pub fn Watch(self: *@This(), allocator: std.mem.Allocator, request: Event, responses: anytype) !void {
                            const request_payload = try request.encode(allocator);
                            defer allocator.free(request_payload);
                            try self.transport.callServerStream(allocator, "Pipe", "Watch", request_payload, responses);
                        }

                        pub fn Chat(self: *@This(), allocator: std.mem.Allocator, requests: anytype, responses: anytype) !void {
                            try self.transport.callBidiStream(allocator, "Pipe", "Chat", requests, responses);
                        }

                    };
                }
            };
        };

    };

};
