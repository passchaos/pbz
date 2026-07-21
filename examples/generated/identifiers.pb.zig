const std = @import("std");
const pbz = @import("pbz");

pub const proto_package = "demo.identifiers";
pub const proto_syntax = "proto3";

pub const demo = struct {
    pub const identifiers = struct {
        pub const @"type" = struct {
            pub const type_number = 1;
            pub const error_number = 2;
            pub const test_number = 3;
            pub const align_number = 4;
            pub const await_number = 5;
            pub const opaque_number = 6;
            pub const null_number = 7;

            pub const type_field = struct {
                pub const number = 1;
                pub const name = "type";
                pub const json_name = "type";
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
            pub const error_field = struct {
                pub const number = 2;
                pub const name = "error";
                pub const json_name = "error";
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
            pub const test_field = struct {
                pub const number = 3;
                pub const name = "test";
                pub const json_name = "test";
                pub const cardinality = "repeated";
                pub const kind = "string";
                pub const type_name = "string";
                pub const zig_type = "[]const []const u8";
                pub const has_type_ref = false;
                pub const type_ref = void;
                pub const has_enum_ref = false;
                pub const enum_ref = void;
                pub const has_presence = false;
                pub const default_value = "";
                pub const is_packed = false;
            };
            pub const align_field = struct {
                pub const number = 4;
                pub const name = "align";
                pub const json_name = "align";
                pub const cardinality = "repeated";
                pub const kind = "map";
                pub const type_name = "";
                pub const zig_type = "alignMap";
                pub const has_type_ref = false;
                pub const type_ref = void;
                pub const has_enum_ref = false;
                pub const enum_ref = void;
                pub const has_presence = false;
                pub const default_value = "";
                pub const is_packed = false;
                pub const map_key = "string";
                pub const map_value_kind = "int32";
                pub const map_value_type_name = "int32";
                pub const map_value_has_type_ref = false;
                pub const map_value_type_ref = void;
                pub const map_value_has_enum_ref = false;
                pub const map_value_enum_ref = void;
            };
            pub const await_field = struct {
                pub const number = 5;
                pub const name = "await";
                pub const json_name = "await";
                pub const cardinality = "optional";
                pub const kind = "string";
                pub const type_name = "string";
                pub const zig_type = "[]const u8";
                pub const has_type_ref = false;
                pub const type_ref = void;
                pub const has_enum_ref = false;
                pub const enum_ref = void;
                pub const has_presence = true;
                pub const default_value = "";
                pub const is_packed = false;
            };
            pub const opaque_field = struct {
                pub const number = 6;
                pub const name = "opaque";
                pub const json_name = "opaque";
                pub const cardinality = "optional";
                pub const kind = "int32";
                pub const type_name = "int32";
                pub const zig_type = "i32";
                pub const has_type_ref = false;
                pub const type_ref = void;
                pub const has_enum_ref = false;
                pub const enum_ref = void;
                pub const has_presence = true;
                pub const default_value = "";
                pub const is_packed = false;
            };
            pub const null_field = struct {
                pub const number = 7;
                pub const name = "null";
                pub const json_name = "null";
                pub const cardinality = "optional";
                pub const kind = "bool";
                pub const type_name = "bool";
                pub const zig_type = "bool";
                pub const has_type_ref = false;
                pub const type_ref = void;
                pub const has_enum_ref = false;
                pub const enum_ref = void;
                pub const has_presence = false;
                pub const default_value = "";
                pub const is_packed = false;
            };

            pub const alignMap = std.StringArrayHashMapUnmanaged(i32);

            pub const alignEntry = struct {
                key: []const u8 = "",
                value: i32 = 0,
            };

            fn appendOrReplaceMapEntry_align(allocator: std.mem.Allocator, list: *std.ArrayList(alignEntry), entry: alignEntry) !void {
                for (list.items) |*existing| {
                    if (std.mem.eql(u8, existing.key, entry.key)) { existing.* = entry; return; }
                }
                try list.append(allocator, entry);
            }

            fn putMapEntry_align(allocator: std.mem.Allocator, map: *alignMap, entry: alignEntry) !void {
                const result = try map.getOrPut(allocator, entry.key);
                result.value_ptr.* = entry.value;
            }

            fn deinitMap_align(allocator: std.mem.Allocator, map: *alignMap) void {
                map.deinit(allocator);
                map.* = .empty;
            }

            pub const asyncOneof = union(enum) {
                none,
                await: []const u8,
                @"opaque": i32,
            };

            @"type": i32 = 0,
            @"error": []const u8 = "",
            @"test": []const []const u8 = &.{},
            @"align": alignMap = .empty,
            @"null": bool = false,
            async: asyncOneof = .none,
            _json_arena: ?*std.heap.ArenaAllocator = null,
            _unknown_fields: []const []const u8 = &.{},

            pub fn init() @This() {
                return .{};
            }

            pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
                allocator.free(self.@"test");
                @This().deinitMap_align(allocator, &self.@"align");
                pbz.wire.freeRawFields(allocator, self._unknown_fields);
                if (self._json_arena) |arena| { const child_allocator = arena.child_allocator; arena.deinit(); child_allocator.destroy(arena); }
                self.* = undefined;
            }

            pub fn cloneOwned(self: @This(), allocator: std.mem.Allocator) !@This() {
                var out = @This().init();
                errdefer out.deinit(allocator);
                const owned_allocator = try out._pbzOwnedAllocator(allocator);
                out.@"type" = self.@"type";
                out.@"error" = try owned_allocator.dupe(u8, self.@"error");
                if (self.@"test".len != 0) {
                    const cloned = try allocator.alloc([]const u8, self.@"test".len);
                    for (self.@"test", 0..) |item, i| cloned[i] = try owned_allocator.dupe(u8, item);
                    out.@"test" = cloned;
                }
                if (self.@"align".count() != 0) {
                    try out.@"align".ensureUnusedCapacity(allocator, self.@"align".count());
                    var map_it = self.@"align".iterator();
                    while (map_it.next()) |entry| out.@"align".putAssumeCapacityNoClobber(try owned_allocator.dupe(u8, entry.key_ptr.*), entry.value_ptr.*);
                }
                out.@"null" = self.@"null";
                out.async = switch (self.async) {
                    .none => .none,
                    .await => |value| .{ .await = try owned_allocator.dupe(u8, value) },
                    .@"opaque" => |value| .{ .@"opaque" = value },
                };
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
                return pbz.wire.rawFieldCountByNumberAssumeValid(self._unknown_fields, number);
            }

            pub fn hasUnknownFieldNumber(self: @This(), number: pbz.FieldNumber) !bool {
                return pbz.wire.rawFieldHasNumberAssumeValid(self._unknown_fields, number);
            }

            pub fn unknownFieldNumbersAlloc(self: @This(), allocator: std.mem.Allocator) ![]pbz.FieldNumber {
                return try pbz.wire.rawFieldNumbersAlloc(allocator, self._unknown_fields);
            }

            pub fn unknownFieldNumberRunsAlloc(self: @This(), allocator: std.mem.Allocator) ![]pbz.wire.RawFieldNumberRun {
                return try pbz.wire.rawFieldNumberRunsAlloc(allocator, self._unknown_fields);
            }

            pub fn unknownFieldsByNumberAlloc(self: @This(), allocator: std.mem.Allocator, number: pbz.FieldNumber) ![]const []const u8 {
                return try pbz.wire.rawFieldsByNumberAllocAssumeValid(allocator, self._unknown_fields, number);
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

            fn _pbzDeinitOneof_async(self: *@This(), allocator: std.mem.Allocator) void {
                _ = allocator;
                self.async = .none;
            }


            pub fn errorFieldView(bytes: []const u8) !?[]const u8 {
                return try pbz.wire.bytesFieldView(bytes, 2);
            }

            pub fn errorFieldSlices(header: *[20]u8, value: []const u8) !pbz.wire.BorrowedFieldSlices {
                return pbz.wire.lengthDelimitedFieldSlicesAssumeValid(header, 2, value);
            }

            pub fn errorStringView(bytes: []const u8) !?[]const u8 {
                return try errorFieldView(bytes);
            }

            pub fn errorStringSlices(header: *[20]u8, value: []const u8) !pbz.wire.BorrowedFieldSlices {
                return try errorFieldSlices(header, value);
            }

            pub fn testFieldView(bytes: []const u8) !?[]const u8 {
                return try pbz.wire.bytesFieldView(bytes, 3);
            }

            pub fn testFieldSlices(header: *[20]u8, value: []const u8) !pbz.wire.BorrowedFieldSlices {
                return pbz.wire.lengthDelimitedFieldSlicesAssumeValid(header, 3, value);
            }

            pub fn testStringView(bytes: []const u8) !?[]const u8 {
                return try testFieldView(bytes);
            }

            pub fn testStringSlices(header: *[20]u8, value: []const u8) !pbz.wire.BorrowedFieldSlices {
                return try testFieldSlices(header, value);
            }


            // no same-file extension accessors

            pub fn mergeFrom(self: *@This(), allocator: std.mem.Allocator, other: @This()) !void {
                if (other.@"type" != 0) self.@"type" = other.@"type";
                if (other.@"error".len != 0) self.@"error" = other.@"error";
                if (other.@"test".len != 0) {
                    const old = self.@"test";
                    const merged = try allocator.alloc([]const u8, old.len + other.@"test".len);
                    @memcpy(merged[0..old.len], old);
                    @memcpy(merged[old.len..], other.@"test");
                    self.@"test" = merged;
                    if (old.len != 0) allocator.free(old);
                }
                const align_other_count = other.@"align".count();
                if (align_other_count != 0) {
                    try self.@"align".ensureUnusedCapacity(allocator, align_other_count);
                    var other_it = other.@"align".iterator();
                    while (other_it.next()) |entry| {
                        const result = self.@"align".getOrPutAssumeCapacity(entry.key_ptr.*);
                        result.value_ptr.* = entry.value_ptr.*;
                    }
                }
                if (other.@"null") self.@"null" = other.@"null";
                switch (other.async) {
                    .none => {},
                    .await => |value| { self._pbzDeinitOneof_async(allocator); self.async = .{ .await = value }; },
                    .@"opaque" => |value| { self._pbzDeinitOneof_async(allocator); self.async = .{ .@"opaque" = value }; },
                }
                try pbz.wire.appendRawFieldsClone(allocator, &self._unknown_fields, other._unknown_fields);
            }

            pub fn encodedSize(self: @This()) usize {
                var size: usize = 0;
                if (self.@"type" != 0) size += 1 + pbz.wire.encodedVarintSize(@as(u64, @bitCast(@as(i64, self.@"type"))));
                if (self.@"error".len != 0) size += 1 + pbz.wire.encodedVarintSize(self.@"error".len) + self.@"error".len;
                for (self.@"test") |item| size += 1 + pbz.wire.encodedVarintSize(item.len) + item.len;
                { var map_it = self.@"align".iterator(); while (map_it.next()) |entry| {
                    const key = entry.key_ptr.*; const value = entry.value_ptr.*;
                    const entry_len = 1 + pbz.wire.encodedVarintSize(key.len) + key.len + 1 + pbz.wire.encodedVarintSize(@as(u64, @bitCast(@as(i64, value))));
                    size += 1 + pbz.wire.encodedVarintSize(entry_len) + entry_len;
                } }
                if (self.@"null") size += 1 + 1;
                switch (self.async) {
                    .none => {},
                    .await => |value| size += 1 + pbz.wire.encodedVarintSize(value.len) + value.len,
                    .@"opaque" => |value| size += 1 + pbz.wire.encodedVarintSize(@as(u64, @bitCast(@as(i64, value)))),
                }
                for (self._unknown_fields) |raw| size += raw.len;
                return size;
            }

            pub fn writeTo(self: @This(), w: *pbz.Writer) !void {
                if (self.@"type" != 0) try w.writeInt32(1, self.@"type");
                if (self.@"error".len != 0) { if (!pbz.validateUtf8(self.@"error")) return error.InvalidUtf8; try w.writeString(2, self.@"error"); }
                for (self.@"test") |item| { if (!pbz.validateUtf8(item)) return error.InvalidUtf8; try w.writeString(3, item); }
                { var map_it = self.@"align".iterator(); while (map_it.next()) |map_entry| {
                    const entry = alignEntry{ .key = map_entry.key_ptr.*, .value = map_entry.value_ptr.* };
                    if (!pbz.validateUtf8(entry.key)) return error.InvalidUtf8;
                    const entry_len = 1 + pbz.wire.encodedVarintSize(entry.key.len) + entry.key.len + 1 + pbz.wire.encodedVarintSize(@as(u64, @bitCast(@as(i64, entry.value))));
                    try w.writeTag(4, .length_delimited);
                    try w.writeVarint(entry_len);
                    try w.writeString(1, entry.key);
                    try w.writeInt32(2, entry.value);
                } }
                if (self.@"null") try w.writeBool(7, self.@"null");
                switch (self.async) {
                    .none => {},
                    .await => |value| { if (!pbz.validateUtf8(value)) return error.InvalidUtf8; try w.writeString(5, value); },
                    .@"opaque" => |value| try w.writeInt32(6, value),
                }
                for (self._unknown_fields) |raw| try w.appendSlice(raw);
            }

            pub fn writeToAssumeCapacity(self: @This(), w: *pbz.Writer) !void {
                if (self.@"type" != 0) w.writeInt32AssumeCapacity(1, self.@"type");
                if (self.@"error".len != 0) { if (!pbz.validateUtf8(self.@"error")) return error.InvalidUtf8; w.writeStringAssumeCapacity(2, self.@"error"); }
                for (self.@"test") |item| { if (!pbz.validateUtf8(item)) return error.InvalidUtf8; w.writeStringAssumeCapacity(3, item); }
                { var map_it = self.@"align".iterator(); while (map_it.next()) |map_entry| {
                    const entry = alignEntry{ .key = map_entry.key_ptr.*, .value = map_entry.value_ptr.* };
                    if (!pbz.validateUtf8(entry.key)) return error.InvalidUtf8;
                    const entry_len = 1 + pbz.wire.encodedVarintSize(entry.key.len) + entry.key.len + 1 + pbz.wire.encodedVarintSize(@as(u64, @bitCast(@as(i64, entry.value))));
                    w.writeTagAssumeCapacity(4, .length_delimited);
                    w.writeVarintAssumeCapacity(entry_len);
                    w.writeStringAssumeCapacity(1, entry.key);
                    w.writeInt32AssumeCapacity(2, entry.value);
                } }
                if (self.@"null") w.writeBoolAssumeCapacity(7, self.@"null");
                switch (self.async) {
                    .none => {},
                    .await => |value| { if (!pbz.validateUtf8(value)) return error.InvalidUtf8; w.writeStringAssumeCapacity(5, value); },
                    .@"opaque" => |value| w.writeInt32AssumeCapacity(6, value),
                }
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
                if (self.@"type" != 0) { buffer[index] = 8; index += 1; pbz.wire.writeDirectScalarVarintToSlice(buffer, &index, @as(u64, @bitCast(@as(i64, self.@"type")))); }
                if (self.@"error".len != 0) { if (!pbz.validateUtf8(self.@"error")) return error.InvalidUtf8; buffer[index] = 18; index += 1; pbz.wire.writeVarintToSlice(buffer, &index, self.@"error".len); @memcpy(buffer[index..][0..self.@"error".len], self.@"error"); index += self.@"error".len; }
                for (self.@"test") |item| { if (!pbz.validateUtf8(item)) return error.InvalidUtf8; buffer[index] = 26; index += 1; pbz.wire.writeVarintToSlice(buffer, &index, item.len); @memcpy(buffer[index..][0..item.len], item); index += item.len; }
                { var map_it = self.@"align".iterator(); while (map_it.next()) |map_entry| {
                    const key = map_entry.key_ptr.*; const value = map_entry.value_ptr.*;
                    if (!pbz.validateUtf8(key)) return error.InvalidUtf8;
                    const entry_len = 1 + pbz.wire.encodedVarintSize(key.len) + key.len + 1 + pbz.wire.encodedVarintSize(@as(u64, @bitCast(@as(i64, value))));
                    buffer[index] = 34; index += 1;
                    pbz.wire.writeVarintToSlice(buffer, &index, entry_len);
                    buffer[index] = 10; index += 1; pbz.wire.writeVarintToSlice(buffer, &index, key.len); @memcpy(buffer[index..][0..key.len], key); index += key.len;
                    buffer[index] = 16; index += 1; pbz.wire.writeDirectScalarVarintToSlice(buffer, &index, @as(u64, @bitCast(@as(i64, value))));
                } }
                if (self.@"null") { buffer[index] = 56; index += 1; buffer[index] = if (self.@"null") 1 else 0; index += 1; }
                switch (self.async) {
                    .none => {},
                    .await => |value| { if (!pbz.validateUtf8(value)) return error.InvalidUtf8; buffer[index] = 42; index += 1; pbz.wire.writeVarintToSlice(buffer, &index, value.len); @memcpy(buffer[index..][0..value.len], value); index += value.len; },
                    .@"opaque" => |value| { buffer[index] = 48; index += 1; pbz.wire.writeDirectScalarVarintToSlice(buffer, &index, @as(u64, @bitCast(@as(i64, value)))); },
                }
                for (self._unknown_fields) |raw| { @memcpy(buffer[index..][0..raw.len], raw); index += raw.len; }
                return buffer[0..index];
            }

            pub fn encodeIntoAssumeCapacityTrustedUtf8(self: @This(), buffer: []u8) ![]u8 {
                var index: usize = 0;
                if (self.@"type" != 0) { buffer[index] = 8; index += 1; pbz.wire.writeDirectScalarVarintToSlice(buffer, &index, @as(u64, @bitCast(@as(i64, self.@"type")))); }
                if (self.@"error".len != 0) { buffer[index] = 18; index += 1; pbz.wire.writeVarintToSlice(buffer, &index, self.@"error".len); @memcpy(buffer[index..][0..self.@"error".len], self.@"error"); index += self.@"error".len; }
                for (self.@"test") |item| { buffer[index] = 26; index += 1; pbz.wire.writeVarintToSlice(buffer, &index, item.len); @memcpy(buffer[index..][0..item.len], item); index += item.len; }
                { var map_it = self.@"align".iterator(); while (map_it.next()) |map_entry| {
                    const key = map_entry.key_ptr.*; const value = map_entry.value_ptr.*;
                    const entry_len = 1 + pbz.wire.encodedVarintSize(key.len) + key.len + 1 + pbz.wire.encodedVarintSize(@as(u64, @bitCast(@as(i64, value))));
                    buffer[index] = 34; index += 1;
                    pbz.wire.writeVarintToSlice(buffer, &index, entry_len);
                    buffer[index] = 10; index += 1; pbz.wire.writeVarintToSlice(buffer, &index, key.len); @memcpy(buffer[index..][0..key.len], key); index += key.len;
                    buffer[index] = 16; index += 1; pbz.wire.writeDirectScalarVarintToSlice(buffer, &index, @as(u64, @bitCast(@as(i64, value))));
                } }
                if (self.@"null") { buffer[index] = 56; index += 1; buffer[index] = if (self.@"null") 1 else 0; index += 1; }
                switch (self.async) {
                    .none => {},
                    .await => |value| { buffer[index] = 42; index += 1; pbz.wire.writeVarintToSlice(buffer, &index, value.len); @memcpy(buffer[index..][0..value.len], value); index += value.len; },
                    .@"opaque" => |value| { buffer[index] = 48; index += 1; pbz.wire.writeDirectScalarVarintToSlice(buffer, &index, @as(u64, @bitCast(@as(i64, value)))); },
                }
                for (self._unknown_fields) |raw| { @memcpy(buffer[index..][0..raw.len], raw); index += raw.len; }
                return buffer[0..index];
            }

            pub fn writeDeterministicTo(self: @This(), allocator: std.mem.Allocator, w: *pbz.Writer) !void {
                if (self.@"type" != 0) try w.writeInt32(1, self.@"type");
                if (self.@"error".len != 0) { if (!pbz.validateUtf8(self.@"error")) return error.InvalidUtf8; try w.writeString(2, self.@"error"); }
                for (self.@"test") |item| { if (!pbz.validateUtf8(item)) return error.InvalidUtf8; try w.writeString(3, item); }
                if (self.@"align".count() != 0) {
                    const insertion_sort_limit: usize = 32;
                    const stack_entry_count: usize = @max(insertion_sort_limit, (32 * 1024) / @max(@sizeOf(alignEntry), 1));
                    var stack_entries: [stack_entry_count]alignEntry = undefined;
                    const use_stack_entries = self.@"align".count() <= stack_entries.len;
                    const entries = if (use_stack_entries) blk: { var map_it = self.@"align".iterator(); var i: usize = 0; while (map_it.next()) |entry| : (i += 1) stack_entries[i] = .{ .key = entry.key_ptr.*, .value = entry.value_ptr.* }; break :blk stack_entries[0..self.@"align".count()]; } else blk: { const owned = try allocator.alloc(alignEntry, self.@"align".count()); var map_it = self.@"align".iterator(); var i: usize = 0; while (map_it.next()) |entry| : (i += 1) owned[i] = .{ .key = entry.key_ptr.*, .value = entry.value_ptr.* }; break :blk owned; };
                    defer if (!use_stack_entries) allocator.free(entries);
                    if (entries.len <= insertion_sort_limit) {
                        var sort_i: usize = 1;
                        while (sort_i < entries.len) : (sort_i += 1) {
                            const item = entries[sort_i];
                            var sort_j = sort_i;
                            while (sort_j > 0 and pbz.wire.bytesLessThan(item.key, entries[sort_j - 1].key)) : (sort_j -= 1) entries[sort_j] = entries[sort_j - 1];
                            entries[sort_j] = item;
                        }
                    } else {
                        const entries_already_sorted = sorted: {
                            var check_i: usize = 1;
                            while (check_i < entries.len) : (check_i += 1) {
                                if (pbz.wire.bytesLessThan(entries[check_i].key, entries[check_i - 1].key)) break :sorted false;
                            }
                            break :sorted true;
                        };
                        if (!entries_already_sorted) {
                            std.mem.sort(alignEntry, entries, {}, struct { fn lessThan(_: void, a: alignEntry, b: alignEntry) bool { return pbz.wire.bytesLessThan(a.key, b.key); } }.lessThan);
                        }
                    }
                    for (entries) |entry| {
                        if (!pbz.validateUtf8(entry.key)) return error.InvalidUtf8;
                        const entry_len = 1 + pbz.wire.encodedVarintSize(entry.key.len) + entry.key.len + 1 + pbz.wire.encodedVarintSize(@as(u64, @bitCast(@as(i64, entry.value))));
                        try w.writeTag(4, .length_delimited);
                        try w.writeVarint(entry_len);
                        try w.writeString(1, entry.key);
                        try w.writeInt32(2, entry.value);
                    }
                }
                switch (self.async) {
                    .await => |value| { if (!pbz.validateUtf8(value)) return error.InvalidUtf8; try w.writeString(5, value); },
                    else => {},
                }
                switch (self.async) {
                    .@"opaque" => |value| try w.writeInt32(6, value),
                    else => {},
                }
                if (self.@"null") try w.writeBool(7, self.@"null");
                try pbz.wire.writeRawFieldsDeterministic(allocator, self._unknown_fields, w);
            }

            pub fn writeDeterministicToAssumeCapacity(self: @This(), allocator: std.mem.Allocator, w: *pbz.Writer) !void {
                if (self.@"type" != 0) w.writeInt32AssumeCapacity(1, self.@"type");
                if (self.@"error".len != 0) { if (!pbz.validateUtf8(self.@"error")) return error.InvalidUtf8; w.writeStringAssumeCapacity(2, self.@"error"); }
                for (self.@"test") |item| { if (!pbz.validateUtf8(item)) return error.InvalidUtf8; w.writeStringAssumeCapacity(3, item); }
                if (self.@"align".count() != 0) {
                    const insertion_sort_limit: usize = 32;
                    const stack_entry_count: usize = @max(insertion_sort_limit, (32 * 1024) / @max(@sizeOf(alignEntry), 1));
                    var stack_entries: [stack_entry_count]alignEntry = undefined;
                    const use_stack_entries = self.@"align".count() <= stack_entries.len;
                    const entries = if (use_stack_entries) blk: { var map_it = self.@"align".iterator(); var i: usize = 0; while (map_it.next()) |entry| : (i += 1) stack_entries[i] = .{ .key = entry.key_ptr.*, .value = entry.value_ptr.* }; break :blk stack_entries[0..self.@"align".count()]; } else blk: { const owned = try allocator.alloc(alignEntry, self.@"align".count()); var map_it = self.@"align".iterator(); var i: usize = 0; while (map_it.next()) |entry| : (i += 1) owned[i] = .{ .key = entry.key_ptr.*, .value = entry.value_ptr.* }; break :blk owned; };
                    defer if (!use_stack_entries) allocator.free(entries);
                    if (entries.len <= insertion_sort_limit) {
                        var sort_i: usize = 1;
                        while (sort_i < entries.len) : (sort_i += 1) {
                            const item = entries[sort_i];
                            var sort_j = sort_i;
                            while (sort_j > 0 and pbz.wire.bytesLessThan(item.key, entries[sort_j - 1].key)) : (sort_j -= 1) entries[sort_j] = entries[sort_j - 1];
                            entries[sort_j] = item;
                        }
                    } else {
                        const entries_already_sorted = sorted: {
                            var check_i: usize = 1;
                            while (check_i < entries.len) : (check_i += 1) {
                                if (pbz.wire.bytesLessThan(entries[check_i].key, entries[check_i - 1].key)) break :sorted false;
                            }
                            break :sorted true;
                        };
                        if (!entries_already_sorted) {
                            std.mem.sort(alignEntry, entries, {}, struct { fn lessThan(_: void, a: alignEntry, b: alignEntry) bool { return pbz.wire.bytesLessThan(a.key, b.key); } }.lessThan);
                        }
                    }
                    for (entries) |entry| {
                        if (!pbz.validateUtf8(entry.key)) return error.InvalidUtf8;
                        const entry_len = 1 + pbz.wire.encodedVarintSize(entry.key.len) + entry.key.len + 1 + pbz.wire.encodedVarintSize(@as(u64, @bitCast(@as(i64, entry.value))));
                        w.writeTagAssumeCapacity(4, .length_delimited);
                        w.writeVarintAssumeCapacity(entry_len);
                        w.writeStringAssumeCapacity(1, entry.key);
                        w.writeInt32AssumeCapacity(2, entry.value);
                    }
                }
                switch (self.async) {
                    .await => |value| { if (!pbz.validateUtf8(value)) return error.InvalidUtf8; w.writeStringAssumeCapacity(5, value); },
                    else => {},
                }
                switch (self.async) {
                    .@"opaque" => |value| w.writeInt32AssumeCapacity(6, value),
                    else => {},
                }
                if (self.@"null") w.writeBoolAssumeCapacity(7, self.@"null");
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
                var test_list: std.ArrayList([]const u8) = .empty;
                defer test_list.deinit(allocator);
                var _unknown_fields_list: std.ArrayList([]const u8) = .empty;
                errdefer pbz.wire.deinitRawFieldList(allocator, &_unknown_fields_list);
                while (try r.nextTag()) |tag| {
                    switch (tag.number) {
                        1 => { self.@"type" = try r.readInt32(); },
                        2 => { self.@"error" = try r.readBytes(); if (!pbz.validateUtf8(self.@"error")) return error.InvalidUtf8; },
                        3 => { const value = try r.readBytes(); if (!pbz.validateUtf8(value)) return error.InvalidUtf8; try test_list.append(allocator, value); },
                        4 => {
                            var entry = alignEntry{};
                            const payload = try r.readBytes();
                            var entry_reader = try r.nested(payload);
                            while (try entry_reader.nextTag()) |entry_tag| {
                                switch (entry_tag.number) {
                                    1 => { const value = try entry_reader.readBytes(); if (!pbz.validateUtf8(value)) return error.InvalidUtf8; entry.key = value; },
                                    2 => entry.value = try entry_reader.readInt32(),
                                    else => try entry_reader.skipValue(entry_tag),
                                }
                            }
                            try @This().putMapEntry_align(allocator, &self.@"align", entry);
                        },
                        5 => { const value = try r.readBytes(); if (!pbz.validateUtf8(value)) return error.InvalidUtf8; self._pbzDeinitOneof_async(allocator); self.async = .{ .await = value }; },
                        6 => { const value = try r.readInt32(); self._pbzDeinitOneof_async(allocator); self.async = .{ .@"opaque" = value }; },
                        7 => { self.@"null" = try r.readBool(); },
                        else => try pbz.wire.appendSkippedRawField(allocator, &_unknown_fields_list, r, r.lastTagStart(), tag),
                    }
                }
                self.@"test" = if (test_list.items.len != 0 and test_list.items.len == test_list.capacity) test_list.toOwnedSliceAssert() else try test_list.toOwnedSlice(allocator);
                self._unknown_fields = try pbz.wire.rawFieldListToOwnedSlice(allocator, &_unknown_fields_list);
                return self;
            }

            pub fn decodeReuse(self: *@This(), allocator: std.mem.Allocator, bytes: []const u8) !void {
                var test_list: std.ArrayList([]const u8) = std.ArrayList([]const u8).fromOwnedSlice(@constCast(self.@"test"));
                test_list.clearRetainingCapacity();
                self.@"test" = &.{};
                errdefer test_list.deinit(allocator);
                pbz.wire.clearRawFields(allocator, &self._unknown_fields);
                self.@"align".clearRetainingCapacity();
                self._pbzDeinitOneof_async(allocator);
                if (self._json_arena) |arena| { const child_allocator = arena.child_allocator; arena.deinit(); child_allocator.destroy(arena); self._json_arena = null; }
                self.@"type" = 0;
                self.@"error" = "";
                self.@"null" = false;
                errdefer self.deinit(allocator);
                var _unknown_fields_list: std.ArrayList([]const u8) = .empty;
                errdefer pbz.wire.deinitRawFieldList(allocator, &_unknown_fields_list);
                var r = pbz.Reader.init(bytes);
                while (try r.nextTag()) |tag| {
                    switch (tag.number) {
                        1 => { self.@"type" = try r.readInt32(); },
                        2 => { self.@"error" = try r.readBytes(); if (!pbz.validateUtf8(self.@"error")) return error.InvalidUtf8; },
                        3 => { const value = try r.readBytes(); if (!pbz.validateUtf8(value)) return error.InvalidUtf8; try test_list.append(allocator, value); },
                        4 => {
                            var entry = alignEntry{};
                            const payload = try r.readBytes();
                            var entry_reader = try r.nested(payload);
                            while (try entry_reader.nextTag()) |entry_tag| {
                                switch (entry_tag.number) {
                                    1 => { const value = try entry_reader.readBytes(); if (!pbz.validateUtf8(value)) return error.InvalidUtf8; entry.key = value; },
                                    2 => entry.value = try entry_reader.readInt32(),
                                    else => try entry_reader.skipValue(entry_tag),
                                }
                            }
                            try @This().putMapEntry_align(allocator, &self.@"align", entry);
                        },
                        5 => { const value = try r.readBytes(); if (!pbz.validateUtf8(value)) return error.InvalidUtf8; self._pbzDeinitOneof_async(allocator); self.async = .{ .await = value }; },
                        6 => { const value = try r.readInt32(); self._pbzDeinitOneof_async(allocator); self.async = .{ .@"opaque" = value }; },
                        7 => { self.@"null" = try r.readBool(); },
                        else => try pbz.wire.appendSkippedRawField(allocator, &_unknown_fields_list, &r, r.lastTagStart(), tag),
                    }
                }
                self.@"test" = if (test_list.items.len != 0 and test_list.items.len == test_list.capacity) test_list.toOwnedSliceAssert() else try test_list.toOwnedSlice(allocator);
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
                if (self.@"type" != 0 or options.always_print_primitive_fields) {
                    try writer.writeAll(if (first) "\"type\":" else ",\"type\":"); first = false;
                    const value = self.@"type";
                    try writer.print("{d}", .{value});
                }
                if (self.@"error".len != 0 or options.always_print_primitive_fields) {
                    try writer.writeAll(if (first) "\"error\":" else ",\"error\":"); first = false;
                    const value = self.@"error";
                    try @This().jsonWriteString(writer, value);
                }
                if (self.@"test".len != 0 or options.always_print_primitive_fields) {
                    try writer.writeAll(if (first) "\"test\":" else ",\"test\":"); first = false;
                    try writer.writeAll("[");
                    for (self.@"test", 0..) |item, i| { if (i != 0) try writer.writeAll(","); try @This().jsonWriteString(writer, item); }
                    try writer.writeAll("]");
                }
                if (self.@"align".count() != 0 or options.always_print_primitive_fields) {
                    try writer.writeAll(if (first) "\"align\":" else ",\"align\":"); first = false;
                    try writer.writeAll("{");
                    var map_it = self.@"align".iterator();
                    var i: usize = 0;
                    while (map_it.next()) |map_entry| : (i += 1) {
                        const entry = alignEntry{ .key = map_entry.key_ptr.*, .value = map_entry.value_ptr.* };
                        if (i != 0) try writer.writeAll(",");
                        try @This().jsonWriteString(writer, entry.key);
                        try writer.writeAll(":");
                        try writer.print("{d}", .{entry.value});
                    }
                    try writer.writeAll("}");
                }
                if (self.@"null" or options.always_print_primitive_fields) {
                    try writer.writeAll(if (first) "\"null\":" else ",\"null\":"); first = false;
                    const value = self.@"null";
                    try writer.writeAll(if (value) "true" else "false");
                }
                switch (self.async) {
                    .none => {},
                    .await => |value| {
                        try writer.writeAll(if (first) "\"await\":" else ",\"await\":"); first = false;
                        try @This().jsonWriteString(writer, value);
                    },
                    .@"opaque" => |value| {
                        try writer.writeAll(if (first) "\"opaque\":" else ",\"opaque\":"); first = false;
                        try writer.print("{d}", .{value});
                    },
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
                const parsed = try std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), text, .{ .duplicate_field_behavior = .use_last });
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
                _ = arena_allocator;
                const object = switch (json_value) { .object => |object| object, else => return error.TypeMismatch };
                var it = object.iterator();
                while (it.next()) |entry| {
                    const key = entry.key_ptr.*;
                    const value = entry.value_ptr.*;
                    if (value == .null) {
                        if (std.mem.eql(u8, key, "type")) {
                            self.@"type" = 0;
                            continue;
                        }
                        if (std.mem.eql(u8, key, "error")) {
                            self.@"error" = "";
                            continue;
                        }
                        if (std.mem.eql(u8, key, "test")) {
                            const old = self.@"test"; self.@"test" = &.{}; if (old.len != 0) allocator.free(old);
                            continue;
                        }
                        if (std.mem.eql(u8, key, "align")) {
                            @This().deinitMap_align(allocator, &self.@"align");
                            continue;
                        }
                        if (std.mem.eql(u8, key, "null")) {
                            self.@"null" = false;
                            continue;
                        }
                        if (std.mem.eql(u8, key, "await")) { self._pbzDeinitOneof_async(allocator); continue; }
                        if (std.mem.eql(u8, key, "opaque")) { self._pbzDeinitOneof_async(allocator); continue; }
                        if (options.ignore_unknown_fields) continue;
                        return error.UnknownField;
                    }
                    if (std.mem.eql(u8, key, "type")) {
                        self.@"type" = try @This().jsonInt(i32, value);
                        continue;
                    }
                    if (std.mem.eql(u8, key, "error")) {
                        self.@"error" = try @This().jsonString(value);
                        continue;
                    }
                    if (std.mem.eql(u8, key, "test")) {
                        const array = switch (value) { .array => |array| array, else => return error.TypeMismatch };
                        var list: std.ArrayList([]const u8) = .empty;
                        errdefer list.deinit(allocator);
                        for (array.items) |item| try list.append(allocator, try @This().jsonString(item));
                        self.@"test" = blk: { const old = self.@"test"; const owned = try list.toOwnedSlice(allocator); if (old.len != 0) allocator.free(old); break :blk owned; };
                        continue;
                    }
                    if (std.mem.eql(u8, key, "align")) {
                        const object_value = switch (value) { .object => |map_object| map_object, else => return error.TypeMismatch };
                        @This().deinitMap_align(allocator, &self.@"align");
                        try self.@"align".ensureUnusedCapacity(allocator, object_value.count());
                        var map_it = object_value.iterator();
                        while (map_it.next()) |map_entry| {
                            try @This().putMapEntry_align(allocator, &self.@"align", .{ .key = map_entry.key_ptr.*, .value = try @This().jsonInt(i32, map_entry.value_ptr.*) });
                        }
                        continue;
                    }
                    if (std.mem.eql(u8, key, "null")) {
                        self.@"null" = try @This().jsonBool(value);
                        continue;
                    }
                    if (std.mem.eql(u8, key, "await")) {
                        self._pbzDeinitOneof_async(allocator); self.async = .{ .await = try @This().jsonString(value) };
                        continue;
                    }
                    if (std.mem.eql(u8, key, "opaque")) {
                        self._pbzDeinitOneof_async(allocator); self.async = .{ .@"opaque" = try @This().jsonInt(i32, value) };
                        continue;
                    }
                    if (options.ignore_unknown_fields) continue;
                    return error.UnknownField;
                }
            }

            fn jsonInt(comptime T: type, value: std.json.Value) !T {
    return try pbz.json.intValue(T, value);
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
    const rest = line[name.len..];
    if (rest.len != 0 and rest[0] == ':') {
        const value = rest[1..];
        if (value.len == 0) return value;
        if (value[0] == ' ') {
            const body = value[1..];
            if (body.len == 0 or (body[0] != ' ' and body[0] != '\t' and body[0] != '\r' and body[body.len - 1] != ' ' and body[body.len - 1] != '\t' and body[body.len - 1] != '\r')) return body;
        } else if (value[0] != '\t' and value[0] != '\r' and value[value.len - 1] != ' ' and value[value.len - 1] != '\t' and value[value.len - 1] != '\r') return value;
    }
    const trimmed = std.mem.trimStart(u8, rest, " \t");
    if (trimmed.len == 0 or trimmed[0] != ':') return null;
    return std.mem.trim(u8, trimmed[1..], " \t\r");
}

fn textBlockField(line: []const u8, comptime name: []const u8) bool {
    if (!std.mem.startsWith(u8, line, name)) return false;
    const rest = line[name.len..];
    if (rest.len == 1 and (rest[0] == '{' or rest[0] == '<')) return true;
    if (rest.len == 2 and rest[0] == ' ' and (rest[1] == '{' or rest[1] == '<')) return true;
    var trimmed = std.mem.trimStart(u8, rest, " \t");
    if (trimmed.len != 0 and trimmed[0] == ':') {
        trimmed = std.mem.trimStart(u8, trimmed[1..], " \t");
    }
    return std.mem.eql(u8, trimmed, "{") or std.mem.eql(u8, trimmed, "<");
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

fn textCleanLine(raw_line: []const u8, text_has_comments: bool) []const u8 {
    var end = raw_line.len;
    if (!text_has_comments) return @This().textTrimLine(raw_line);
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
    return @This().textTrimLine(raw_line[0..end]);
}

fn textTrimLine(raw_line: []const u8) []const u8 {
    if (raw_line.len == 0) return raw_line;
    const first = raw_line[0];
    const last = raw_line[raw_line.len - 1];
    if (first != ' ' and first != '\t' and first != '\r' and last != ' ' and last != '\t' and last != '\r' and last != ';' and last != ',') return raw_line;
    var line = std.mem.trim(u8, raw_line, " \t\r");
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
    if (value.len >= 2) {
        const quote = value[0];
        if ((quote == '"' or quote == '\'') and value[value.len - 1] == quote) {
            const body = value[1 .. value.len - 1];
            const escaped_or_closed = if (quote == '"') std.mem.indexOfAny(u8, body, "\\\"") else std.mem.indexOfAny(u8, body, "\\'");
            if (escaped_or_closed == null) return try allocator.dupe(u8, body);
        }
    }
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
                    var decoded: u8 = 0;
                    while (end < value.len and end < start + 2) : (end += 1) {
                        const digit = @This().textHexDigit(value[end]) orelse break;
                        decoded = decoded * 16 + digit;
                    }
                    if (end == start) return error.InvalidEscape;
                    try out.append(allocator, decoded);
                    i = end;
                },
                '0'...'7' => {
                    const start = i - 1;
                    var end = i;
                    var decoded: u16 = esc - '0';
                    while (end < value.len and end < start + 3 and value[end] >= '0' and value[end] <= '7') : (end += 1) {
                        decoded = decoded * 8 + (value[end] - '0');
                    }
                    if (decoded > std.math.maxInt(u8)) return error.Overflow;
                    try out.append(allocator, @intCast(decoded));
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

fn textUnknownGroup(allocator: std.mem.Allocator, line: []const u8, lines: anytype, text_has_comments: bool) !?[]const u8 {
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
        const child = @This().textCleanLine(raw_line, text_has_comments);
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
        if (try @This().textUnknownGroup(allocator, child, lines, text_has_comments)) |group_raw| {
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

fn textBlock(allocator: std.mem.Allocator, lines: anytype, text_has_comments: bool) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    var depth: usize = 1;
    while (lines.next()) |raw_line| {
        const line = @This().textCleanLine(raw_line, text_has_comments);
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
                if (self.@"type" != 0) { try writer.writeAll("type: "); const value = self.@"type"; try writer.print("{d}", .{value}); try writer.writeByte('\n'); }
                if (self.@"error".len != 0) { try writer.writeAll("error: "); const value = self.@"error"; if (!pbz.validateUtf8(value)) return error.InvalidUtf8; try @This().textWriteQuotedBytes(value, writer); try writer.writeByte('\n'); }
                for (self.@"test") |value| { try writer.writeAll("test: "); if (!pbz.validateUtf8(value)) return error.InvalidUtf8; try @This().textWriteQuotedBytes(value, writer); try writer.writeByte('\n'); }
                { var map_it = self.@"align".iterator(); while (map_it.next()) |map_entry| {
                    const entry = alignEntry{ .key = map_entry.key_ptr.*, .value = map_entry.value_ptr.* };
                    try writer.writeAll("align {\n");
                    try writer.writeAll("key: "); if (!pbz.validateUtf8(entry.key)) return error.InvalidUtf8; try @This().textWriteQuotedBytes(entry.key, writer); try writer.writeByte('\n');
                    try writer.writeAll("value: "); try writer.print("{d}", .{entry.value}); try writer.writeByte('\n');
                    try writer.writeAll("}\n");
                } }
                if (self.@"null") { try writer.writeAll("null: "); const value = self.@"null"; try writer.writeAll(if (value) "true" else "false"); try writer.writeByte('\n'); }
                switch (self.async) {
                    .none => {},
                    .await => |value| {
                        try writer.writeAll("await: "); try @This().textWriteQuotedBytes(value, writer); try writer.writeByte('\n');
                    },
                    .@"opaque" => |value| {
                        try writer.writeAll("opaque: "); try writer.print("{d}", .{value}); try writer.writeByte('\n');
                    },
                }
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
                var test_list: std.ArrayList([]const u8) = .empty;
                defer test_list.deinit(allocator);
                var align_list: std.ArrayList(alignEntry) = .empty;
                defer align_list.deinit(allocator);
                var _unknown_fields_list: std.ArrayList([]const u8) = .empty;
                errdefer pbz.wire.deinitRawFieldList(allocator, &_unknown_fields_list);
                const needs_normalized_text = @This().textNeedsSeparatorNormalization(text);
                const normalized_text = if (needs_normalized_text) try @This().textNormalizeSeparators(allocator, text) else text;
                defer if (needs_normalized_text) allocator.free(normalized_text);
                const text_has_comments = std.mem.indexOfScalar(u8, normalized_text, '#') != null;
                var lines = std.mem.splitScalar(u8, normalized_text, '\n');
                while (lines.next()) |raw_line| {
                    const line = @This().textCleanLine(raw_line, text_has_comments);
                    if (line.len == 0) continue;
                    if (@This().textFieldValue(line, "type")) |raw_value| {
                        self.@"type" = try @This().textInt(i32, raw_value);
                        continue;
                    }
                    if (@This().textFieldValue(line, "error")) |raw_value| {
                        self.@"error" = blk: { const decoded = try @This().textUnquote(try self._pbzOwnedAllocator(allocator), raw_value); if (!pbz.validateUtf8(decoded)) return error.InvalidUtf8; break :blk decoded; };
                        continue;
                    }
                    if (@This().textFieldValue(line, "test")) |raw_value| {
                        try test_list.append(allocator, blk: { const decoded = try @This().textUnquote(try self._pbzOwnedAllocator(allocator), raw_value); if (!pbz.validateUtf8(decoded)) return error.InvalidUtf8; break :blk decoded; });
                        continue;
                    }
                    if (@This().textBlockField(line, "align")) {
                        var entry = alignEntry{};
                        while (lines.next()) |raw_entry_line| {
                            const entry_line = @This().textCleanLine(raw_entry_line, text_has_comments);
                            if (entry_line.len == 0) continue;
                            if (std.mem.eql(u8, entry_line, "}") or std.mem.eql(u8, entry_line, ">")) break;
                            if (@This().textFieldValue(entry_line, "key")) |raw_key| { entry.key = blk: { const decoded = try @This().textUnquote(try self._pbzOwnedAllocator(allocator), raw_key); if (!pbz.validateUtf8(decoded)) return error.InvalidUtf8; break :blk decoded; }; continue; }
                            if (@This().textFieldValue(entry_line, "value")) |raw_value| { entry.value = try @This().textInt(i32, raw_value); continue; }
                            return error.UnknownField;
                        }
                        try @This().appendOrReplaceMapEntry_align(allocator, &align_list, entry);
                        continue;
                    }
                    if (@This().textFieldValue(line, "null")) |raw_value| {
                        self.@"null" = try @This().textBool(raw_value);
                        continue;
                    }
                    if (@This().textFieldValue(line, "await")) |raw_value| { self._pbzDeinitOneof_async(allocator); self.async = .{ .await = blk: { const decoded = try @This().textUnquote(try self._pbzOwnedAllocator(allocator), raw_value); if (!pbz.validateUtf8(decoded)) return error.InvalidUtf8; break :blk decoded; } }; continue; }
                    if (@This().textFieldValue(line, "opaque")) |raw_value| { self._pbzDeinitOneof_async(allocator); self.async = .{ .@"opaque" = try @This().textInt(i32, raw_value) }; continue; }
                    if (try @This().textUnknownField(allocator, line)) |raw| { try pbz.wire.appendOwnedRawField(allocator, &_unknown_fields_list, raw); continue; }
                    if (try @This().textUnknownGroup(allocator, line, &lines, text_has_comments)) |raw| { try pbz.wire.appendOwnedRawField(allocator, &_unknown_fields_list, raw); continue; }
                    if (options.ignore_unknown_fields) continue;
                    return error.UnknownField;
                }
                self.@"test" = if (test_list.items.len != 0 and test_list.items.len == test_list.capacity) test_list.toOwnedSliceAssert() else try test_list.toOwnedSlice(allocator);
                self.@"align" = .empty;
                try self.@"align".ensureUnusedCapacity(allocator, align_list.items.len);
                for (align_list.items) |entry| self.@"align".putAssumeCapacityNoClobber(entry.key, entry.value);
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

    };

};
