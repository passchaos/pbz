const std = @import("std");
const pbz = @import("pbz");

pub const proto_package = "demo";
pub const proto_syntax = "proto3";

pub const demo = struct {
    pub const Person = struct {
        pub const id_number = 1;
        pub const name_number = 2;
        pub const scores_number = 3;
        pub const counts_number = 4;

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
        pub const name_field = struct {
            pub const number = 2;
            pub const name = "name";
            pub const json_name = "name";
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
        pub const scores_field = struct {
            pub const number = 3;
            pub const name = "scores";
            pub const json_name = "scores";
            pub const cardinality = "repeated";
            pub const kind = "int32";
            pub const type_name = "int32";
            pub const zig_type = "[]const i32";
            pub const has_type_ref = false;
            pub const type_ref = void;
            pub const has_enum_ref = false;
            pub const enum_ref = void;
            pub const has_presence = false;
            pub const default_value = "";
            pub const is_packed = true;
        };
        pub const counts_field = struct {
            pub const number = 4;
            pub const name = "counts";
            pub const json_name = "counts";
            pub const cardinality = "repeated";
            pub const kind = "map";
            pub const type_name = "";
            pub const zig_type = "[]const countsEntry";
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

        pub const countsEntry = struct {
            key: []const u8 = "",
            value: i32 = 0,
        };

        fn appendOrReplaceMapEntry_counts(allocator: std.mem.Allocator, list: *std.ArrayList(countsEntry), entry: countsEntry) !void {
            for (list.items) |*existing| {
                if (std.mem.eql(u8, existing.key, entry.key)) { existing.* = entry; return; }
            }
            try list.append(allocator, entry);
        }

        id: i32 = 0,
        name: []const u8 = "",
        scores: []const i32 = &.{},
        counts: []const countsEntry = &.{},
        @"_json_arena": ?*std.heap.ArenaAllocator = null,
        @"_unknown_fields": []const []const u8 = &.{},

        pub fn init() @This() {
            return .{};
        }

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            allocator.free(self.scores);
            allocator.free(self.counts);
            for (self.@"_unknown_fields") |raw| allocator.free(raw);
            allocator.free(self.@"_unknown_fields");
            if (self.@"_json_arena") |arena| { const child_allocator = arena.child_allocator; arena.deinit(); child_allocator.destroy(arena); }
            self.* = undefined;
        }

        pub fn cloneOwned(self: @This(), allocator: std.mem.Allocator) !@This() {
            var out = @This().init();
            errdefer out.deinit(allocator);
            const owned_allocator = try out.@"_pbzOwnedAllocator"(allocator);
            out.id = self.id;
            out.name = try owned_allocator.dupe(u8, self.name);
            if (self.scores.len != 0) {
                const cloned = try allocator.alloc(i32, self.scores.len);
                for (self.scores, 0..) |item, i| cloned[i] = item;
                out.scores = cloned;
            }
            if (self.counts.len != 0) {
                const cloned = try allocator.alloc(countsEntry, self.counts.len);
                for (self.counts, 0..) |entry, i| cloned[i] = .{ .key = try owned_allocator.dupe(u8, entry.key), .value = entry.value };
                out.counts = cloned;
            }
            if (self.@"_unknown_fields".len != 0) {
                const cloned_unknowns = try allocator.alloc([]const u8, self.@"_unknown_fields".len);
                for (self.@"_unknown_fields", 0..) |raw, i| cloned_unknowns[i] = try allocator.dupe(u8, raw);
                out.@"_unknown_fields" = cloned_unknowns;
            }
            return out;
        }

        fn @"_pbzOwnedAllocator"(self: *@This(), allocator: std.mem.Allocator) !std.mem.Allocator {
            if (self.@"_json_arena" == null) {
                const arena = try allocator.create(std.heap.ArenaAllocator);
                errdefer allocator.destroy(arena);
                arena.* = std.heap.ArenaAllocator.init(allocator);
                self.@"_json_arena" = arena;
            }
            return self.@"_json_arena".?.allocator();
        }

        pub fn unknownFieldCount(self: @This()) usize {
            return self.@"_unknown_fields".len;
        }

        pub fn unknownFields(self: @This()) []const []const u8 {
            return self.@"_unknown_fields";
        }

        pub fn unknownFieldCountByNumber(self: @This(), number: pbz.FieldNumber) !usize {
            var count: usize = 0;
            for (self.@"_unknown_fields") |raw| {
                var r = pbz.Reader.init(raw);
                if (try r.nextTag()) |tag| {
                    if (tag.number == number) count += 1;
                }
            }
            return count;
        }

        pub fn hasUnknownFieldNumber(self: @This(), number: pbz.FieldNumber) !bool {
            return (try self.unknownFieldCountByNumber(number)) != 0;
        }

        pub fn unknownFieldsByNumberAlloc(self: @This(), allocator: std.mem.Allocator, number: pbz.FieldNumber) ![]const []const u8 {
            var list: std.ArrayList([]const u8) = .empty;
            errdefer list.deinit(allocator);
            for (self.@"_unknown_fields") |raw| {
                var r = pbz.Reader.init(raw);
                if (try r.nextTag()) |tag| {
                    if (tag.number == number) try list.append(allocator, raw);
                }
            }
            return try list.toOwnedSlice(allocator);
        }

        pub fn appendUnknownRaw(self: *@This(), allocator: std.mem.Allocator, raw: []const u8) !void {
            var r = pbz.Reader.init(raw);
            const tag = (try r.nextTag()) orelse return error.InvalidWireType;
            try r.skipValue(tag);
            if (!r.eof()) return error.InvalidWireType;
            const old = self.@"_unknown_fields";
            const next = try allocator.alloc([]const u8, old.len + 1);
            errdefer allocator.free(next);
            if (old.len != 0) @memcpy(next[0..old.len], old);
            const owned = try allocator.dupe(u8, raw);
            errdefer allocator.free(owned);
            next[old.len] = owned;
            self.@"_unknown_fields" = next;
            if (old.len != 0) allocator.free(old);
        }

        pub fn clearUnknownFieldsByNumber(self: *@This(), allocator: std.mem.Allocator, number: pbz.FieldNumber) !void {
            var kept: std.ArrayList([]const u8) = .empty;
            errdefer kept.deinit(allocator);
            for (self.@"_unknown_fields") |raw| {
                var r = pbz.Reader.init(raw);
                const tag = (try r.nextTag()) orelse { allocator.free(raw); continue; };
                if (tag.number == number) { allocator.free(raw); continue; }
                try kept.append(allocator, raw);
            }
            if (self.@"_unknown_fields".len != 0) allocator.free(self.@"_unknown_fields");
            self.@"_unknown_fields" = try kept.toOwnedSlice(allocator);
        }

        pub fn clearUnknownFields(self: *@This(), allocator: std.mem.Allocator) void {
            for (self.@"_unknown_fields") |raw| allocator.free(raw);
            if (self.@"_unknown_fields".len != 0) allocator.free(self.@"_unknown_fields");
            self.@"_unknown_fields" = &.{};
        }


        // no same-file extension accessors

        pub fn mergeFrom(self: *@This(), allocator: std.mem.Allocator, other: @This()) !void {
            if (other.id != 0) self.id = other.id;
            if (other.name.len != 0) self.name = other.name;
            if (other.scores.len != 0) {
                const old = self.scores;
                const merged = try allocator.alloc(i32, old.len + other.scores.len);
                @memcpy(merged[0..old.len], old);
                @memcpy(merged[old.len..], other.scores);
                self.scores = merged;
                if (old.len != 0) allocator.free(old);
            }
            if (other.counts.len != 0) {
                var list: std.ArrayList(countsEntry) = .empty;
                defer list.deinit(allocator);
                if (self.counts.len != 0) try list.appendSlice(allocator, self.counts);
                for (other.counts) |entry| try @This().appendOrReplaceMapEntry_counts(allocator, &list, entry);
                const old = self.counts;
                self.counts = try list.toOwnedSlice(allocator);
                if (old.len != 0) allocator.free(old);
            }
            for (other.@"_unknown_fields") |raw| try self.appendUnknownRaw(allocator, raw);
        }

        pub fn encodedSize(self: @This()) usize {
            var size: usize = 0;
            if (self.id != 0) size += 1 + pbz.wire.encodedVarintSize(@as(u64, @bitCast(@as(i64, self.id))));
            if (self.name.len != 0) size += 1 + pbz.wire.encodedVarintSize(self.name.len) + self.name.len;
            if (self.scores.len != 0) {
                var packed_len: usize = 0;
                for (self.scores) |item| packed_len += pbz.wire.encodedVarintSize(@as(u64, @bitCast(@as(i64, item))));
                size += 1 + pbz.wire.encodedVarintSize(packed_len) + packed_len;
            }
            for (self.counts) |entry| {
                const entry_len = 1 + pbz.wire.encodedVarintSize(entry.key.len) + entry.key.len + 1 + pbz.wire.encodedVarintSize(@as(u64, @bitCast(@as(i64, entry.value))));
                size += 1 + pbz.wire.encodedVarintSize(entry_len) + entry_len;
            }
            for (self.@"_unknown_fields") |raw| size += raw.len;
            return size;
        }

        pub fn writeTo(self: @This(), w: *pbz.Writer) !void {
            if (self.id != 0) try w.writeInt32(1, self.id);
            if (self.name.len != 0) { if (!std.unicode.utf8ValidateSlice(self.name)) return error.InvalidUtf8; try w.writeString(2, self.name); }
            if (self.scores.len != 0) {
                var packed_len: usize = 0;
                for (self.scores) |item| packed_len += pbz.wire.encodedVarintSize(@as(u64, @bitCast(@as(i64, item))));
                try w.writeTag(3, .length_delimited);
                try w.writeVarint(packed_len);
                for (self.scores) |item| try w.writeVarint(@as(u64, @bitCast(@as(i64, item))));
            }
            for (self.counts) |entry| {
                if (!std.unicode.utf8ValidateSlice(entry.key)) return error.InvalidUtf8;
                const entry_len = 1 + pbz.wire.encodedVarintSize(entry.key.len) + entry.key.len + 1 + pbz.wire.encodedVarintSize(@as(u64, @bitCast(@as(i64, entry.value))));
                try w.writeTag(4, .length_delimited);
                try w.writeVarint(entry_len);
                try w.writeString(1, entry.key);
                try w.writeInt32(2, entry.value);
            }
            for (self.@"_unknown_fields") |raw| try w.appendSlice(raw);
        }

        pub fn writeToAssumeCapacity(self: @This(), w: *pbz.Writer) !void {
            if (self.id != 0) w.writeInt32AssumeCapacity(1, self.id);
            if (self.name.len != 0) { if (!std.unicode.utf8ValidateSlice(self.name)) return error.InvalidUtf8; w.writeStringAssumeCapacity(2, self.name); }
            if (self.scores.len != 0) {
                var packed_len: usize = 0;
                for (self.scores) |item| packed_len += pbz.wire.encodedVarintSize(@as(u64, @bitCast(@as(i64, item))));
                w.writeTagAssumeCapacity(3, .length_delimited);
                w.writeVarintAssumeCapacity(packed_len);
                for (self.scores) |item| w.writeVarintAssumeCapacity(@as(u64, @bitCast(@as(i64, item))));
            }
            for (self.counts) |entry| {
                if (!std.unicode.utf8ValidateSlice(entry.key)) return error.InvalidUtf8;
                const entry_len = 1 + pbz.wire.encodedVarintSize(entry.key.len) + entry.key.len + 1 + pbz.wire.encodedVarintSize(@as(u64, @bitCast(@as(i64, entry.value))));
                w.writeTagAssumeCapacity(4, .length_delimited);
                w.writeVarintAssumeCapacity(entry_len);
                w.writeStringAssumeCapacity(1, entry.key);
                w.writeInt32AssumeCapacity(2, entry.value);
            }
            for (self.@"_unknown_fields") |raw| w.appendSliceAssumeCapacity(raw);
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
            var w = pbz.Writer.initBuffer(std.heap.page_allocator, buffer);
            try self.writeToAssumeCapacity(&w);
            return buffer[0..w.slice().len];
        }

        pub fn encodeDeterministic(self: @This(), allocator: std.mem.Allocator) ![]u8 {
            var w = pbz.Writer.init(allocator);
            errdefer w.deinit();
            if (self.id != 0) try w.writeInt32(1, self.id);
            if (self.name.len != 0) { if (!std.unicode.utf8ValidateSlice(self.name)) return error.InvalidUtf8; try w.writeString(2, self.name); }
            if (self.scores.len != 0) {
                var packed_len: usize = 0;
                for (self.scores) |item| packed_len += pbz.wire.encodedVarintSize(@as(u64, @bitCast(@as(i64, item))));
                try w.writeTag(3, .length_delimited);
                try w.writeVarint(packed_len);
                for (self.scores) |item| try w.writeVarint(@as(u64, @bitCast(@as(i64, item))));
            }
            if (self.counts.len != 0) {
                const entries = try allocator.dupe(countsEntry, self.counts);
                defer allocator.free(entries);
                std.mem.sort(countsEntry, entries, {}, struct { fn lessThan(_: void, a: countsEntry, b: countsEntry) bool { return std.mem.lessThan(u8, a.key, b.key); } }.lessThan);
                for (entries) |entry| {
                    var entry_writer = pbz.Writer.init(allocator);
                    defer entry_writer.deinit();
                    if (!std.unicode.utf8ValidateSlice(entry.key)) return error.InvalidUtf8;
                    try entry_writer.writeString(1, entry.key);
                    try entry_writer.writeInt32(2, entry.value);
                    try w.writeMessage(4, entry_writer.slice());
                }
            }
            if (self.@"_unknown_fields".len != 0) {
                const indexes = try allocator.alloc(usize, self.@"_unknown_fields".len);
                defer allocator.free(indexes);
                for (indexes, 0..) |*index, i| index.* = i;
                std.mem.sort(usize, indexes, self.@"_unknown_fields", struct {
                    fn firstTag(raw: []const u8) ?pbz.wire.Tag {
                        var r = pbz.Reader.init(raw);
                        return (r.nextTag() catch null) orelse null;
                    }
                    fn lessThan(raws: []const []const u8, a: usize, b: usize) bool {
                        const tag_a = firstTag(raws[a]);
                        const tag_b = firstTag(raws[b]);
                        if (tag_a == null or tag_b == null) return std.mem.lessThan(u8, raws[a], raws[b]);
                        if (tag_a.?.number != tag_b.?.number) return tag_a.?.number < tag_b.?.number;
                        if (tag_a.?.wire_type != tag_b.?.wire_type) return @intFromEnum(tag_a.?.wire_type) < @intFromEnum(tag_b.?.wire_type);
                        return std.mem.lessThan(u8, raws[a], raws[b]);
                    }
                }.lessThan);
                for (indexes) |index| try w.appendSlice(self.@"_unknown_fields"[index]);
            }
            return try w.toOwnedSlice();
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
            var self = @This().init();
            errdefer self.deinit(allocator);
            var scores_list: std.ArrayList(i32) = .empty;
            defer scores_list.deinit(allocator);
            var counts_list: std.ArrayList(countsEntry) = .empty;
            defer counts_list.deinit(allocator);
            var @"_unknown_fields_list": std.ArrayList([]const u8) = .empty;
            errdefer { for (@"_unknown_fields_list".items) |raw| allocator.free(raw); @"_unknown_fields_list".deinit(allocator); }
            var r = pbz.Reader.init(bytes);
            while (try r.nextTag()) |tag| {
                switch (tag.number) {
                    1 => { self.id = try r.readInt32(); },
                    2 => { self.name = try r.readBytes(); if (!std.unicode.utf8ValidateSlice(self.name)) return error.InvalidUtf8; },
                    3 => {
                        if (tag.wire_type == .length_delimited) {
                            const payload = try r.readBytes();
                            try pbz.wire.appendPackedInt32(allocator, &scores_list, payload);
                        } else {
                            try scores_list.append(allocator, try r.readInt32());
                        }
                    },
                    4 => {
                        var entry = countsEntry{};
                        const payload = try r.readBytes();
                        var entry_reader = pbz.Reader.init(payload);
                        const skip_entry = false;
                        while (try entry_reader.nextTag()) |entry_tag| {
                            switch (entry_tag.number) {
                                1 => { const value = try entry_reader.readBytes(); if (!std.unicode.utf8ValidateSlice(value)) return error.InvalidUtf8; entry.key = value; },
                                2 => entry.value = try entry_reader.readInt32(),
                                else => try entry_reader.skipValue(entry_tag),
                            }
                        }
                        if (skip_entry) { var unknown_writer = pbz.Writer.init(allocator); defer unknown_writer.deinit(); try unknown_writer.writeBytes(4, payload); const raw = try allocator.dupe(u8, unknown_writer.slice()); errdefer allocator.free(raw); try @"_unknown_fields_list".append(allocator, raw); } else try @This().appendOrReplaceMapEntry_counts(allocator, &counts_list, entry);
                    },
                    else => { const start = r.position() - pbz.wire.encodedVarintSize(try tag.encode()); try r.skipValue(tag); const raw = try allocator.dupe(u8, r.input[start..r.position()]); errdefer allocator.free(raw); try @"_unknown_fields_list".append(allocator, raw); },
                }
            }
            self.scores = if (scores_list.items.len != 0 and scores_list.items.len == scores_list.capacity) scores_list.toOwnedSliceAssert() else try scores_list.toOwnedSlice(allocator);
            self.counts = if (counts_list.items.len != 0 and counts_list.items.len == counts_list.capacity) counts_list.toOwnedSliceAssert() else try counts_list.toOwnedSlice(allocator);
            self.@"_unknown_fields" = try @"_unknown_fields_list".toOwnedSlice(allocator);
            return self;
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
            if (self.name.len != 0 or options.always_print_primitive_fields) {
                if (!first) try writer.writeAll(","); first = false;
                try writer.writeAll(if (options.preserve_proto_field_names) "\"name\":" else "\"name\":");
                const value = self.name;
                try @This().jsonWriteString(writer, value);
            }
            if (self.scores.len != 0 or options.always_print_primitive_fields) {
                if (!first) try writer.writeAll(","); first = false;
                try writer.writeAll(if (options.preserve_proto_field_names) "\"scores\":" else "\"scores\":");
                try writer.writeAll("[");
                for (self.scores, 0..) |item, i| { if (i != 0) try writer.writeAll(","); try writer.print("{d}", .{item}); }
                try writer.writeAll("]");
            }
            if (self.counts.len != 0 or options.always_print_primitive_fields) {
                if (!first) try writer.writeAll(","); first = false;
                try writer.writeAll(if (options.preserve_proto_field_names) "\"counts\":" else "\"counts\":");
                try writer.writeAll("{");
                for (self.counts, 0..) |entry, i| {
                    if (i != 0) try writer.writeAll(",");
                    try @This().jsonWriteString(writer, entry.key);
                    try writer.writeAll(":");
                    try writer.print("{d}", .{entry.value});
                }
                try writer.writeAll("}");
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
            var self = @This().init();
            errdefer self.deinit(allocator);
            try self.jsonFillFromValue(allocator, arena.allocator(), parsed, options);
            self.@"_json_arena" = arena;
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
                    if (std.mem.eql(u8, key, "id") or std.mem.eql(u8, key, "id")) {
                        self.id = 0;
                        continue;
                    }
                    if (std.mem.eql(u8, key, "name") or std.mem.eql(u8, key, "name")) {
                        self.name = "";
                        continue;
                    }
                    if (std.mem.eql(u8, key, "scores") or std.mem.eql(u8, key, "scores")) {
                        const old = self.scores; self.scores = &.{}; if (old.len != 0) allocator.free(old);
                        continue;
                    }
                    if (std.mem.eql(u8, key, "counts") or std.mem.eql(u8, key, "counts")) {
                        const old = self.counts; self.counts = &.{}; if (old.len != 0) allocator.free(old);
                        continue;
                    }
                    if (options.ignore_unknown_fields) continue;
                    return error.UnknownField;
                }
                if (std.mem.eql(u8, key, "id") or std.mem.eql(u8, key, "id")) {
                    self.id = try @This().jsonInt(i32, value);
                    continue;
                }
                if (std.mem.eql(u8, key, "name") or std.mem.eql(u8, key, "name")) {
                    self.name = try @This().jsonString(value);
                    continue;
                }
                if (std.mem.eql(u8, key, "scores") or std.mem.eql(u8, key, "scores")) {
                    const array = switch (value) { .array => |array| array, else => return error.TypeMismatch };
                    var list: std.ArrayList(i32) = .empty;
                    errdefer list.deinit(allocator);
                    for (array.items) |item| try list.append(allocator, try @This().jsonInt(i32, item));
                    self.scores = blk: { const old = self.scores; const owned = try list.toOwnedSlice(allocator); if (old.len != 0) allocator.free(old); break :blk owned; };
                    continue;
                }
                if (std.mem.eql(u8, key, "counts") or std.mem.eql(u8, key, "counts")) {
                    const object_value = switch (value) { .object => |map_object| map_object, else => return error.TypeMismatch };
                    var list: std.ArrayList(countsEntry) = .empty;
                    errdefer list.deinit(allocator);
                    var map_it = object_value.iterator();
                    while (map_it.next()) |map_entry| {
                        try @This().appendOrReplaceMapEntry_counts(allocator, &list, .{ .key = map_entry.key_ptr.*, .value = try @This().jsonInt(i32, map_entry.value_ptr.*) });
                    }
                    self.counts = blk: { const old = self.counts; const owned = try list.toOwnedSlice(allocator); if (old.len != 0) allocator.free(old); break :blk owned; };
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
    if (!std.unicode.utf8ValidateSlice(value)) return error.InvalidUtf8;
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
            if (self.name.len != 0) { try writer.writeAll("name: "); const value = self.name; if (!std.unicode.utf8ValidateSlice(value)) return error.InvalidUtf8; try @This().textWriteQuotedBytes(value, writer); try writer.writeByte('\n'); }
            for (self.scores) |value| { try writer.writeAll("scores: "); try writer.print("{d}", .{value}); try writer.writeByte('\n'); }
            for (self.counts) |entry| {
                try writer.writeAll("counts {\n");
                try writer.writeAll("key: "); if (!std.unicode.utf8ValidateSlice(entry.key)) return error.InvalidUtf8; try @This().textWriteQuotedBytes(entry.key, writer); try writer.writeByte('\n');
                try writer.writeAll("value: "); try writer.print("{d}", .{entry.value}); try writer.writeByte('\n');
                try writer.writeAll("}\n");
            }
            for (self.@"_unknown_fields") |raw| {
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
            var scores_list: std.ArrayList(i32) = .empty;
            defer scores_list.deinit(allocator);
            var counts_list: std.ArrayList(countsEntry) = .empty;
            defer counts_list.deinit(allocator);
            var @"_unknown_fields_list": std.ArrayList([]const u8) = .empty;
            errdefer { for (@"_unknown_fields_list".items) |raw| allocator.free(raw); @"_unknown_fields_list".deinit(allocator); }
            const normalized_text = try @This().textNormalizeSeparators(allocator, text);
            defer allocator.free(normalized_text);
            var lines = std.mem.splitScalar(u8, normalized_text, '\n');
            while (lines.next()) |raw_line| {
                const line = @This().textCleanLine(raw_line);
                if (line.len == 0) continue;
                if (@This().textFieldValue(line, "id")) |raw_value| {
                    self.id = try @This().textInt(i32, raw_value);
                    continue;
                }
                if (@This().textFieldValue(line, "name")) |raw_value| {
                    self.name = blk: { const decoded = try @This().textUnquote(try self.@"_pbzOwnedAllocator"(allocator), raw_value); if (!std.unicode.utf8ValidateSlice(decoded)) return error.InvalidUtf8; break :blk decoded; };
                    continue;
                }
                if (@This().textFieldValue(line, "scores")) |raw_value| {
                    scores_list.append(allocator, try @This().textInt(i32, raw_value)) catch |err| return err;
                    continue;
                }
                if (@This().textBlockField(line, "counts")) {
                    var entry = countsEntry{};
                    const skip_entry = false;
                    while (lines.next()) |raw_entry_line| {
                        const entry_line = @This().textCleanLine(raw_entry_line);
                        if (entry_line.len == 0) continue;
                        if (std.mem.eql(u8, entry_line, "}") or std.mem.eql(u8, entry_line, ">")) break;
                        if (@This().textFieldValue(entry_line, "key")) |raw_key| { entry.key = blk: { const decoded = try @This().textUnquote(try self.@"_pbzOwnedAllocator"(allocator), raw_key); if (!std.unicode.utf8ValidateSlice(decoded)) return error.InvalidUtf8; break :blk decoded; }; continue; }
                        if (@This().textFieldValue(entry_line, "value")) |raw_value| { entry.value = try @This().textInt(i32, raw_value); continue; }
                        return error.UnknownField;
                    }
                    if (skip_entry) continue;
                    try @This().appendOrReplaceMapEntry_counts(allocator, &counts_list, entry);
                    continue;
                }
                if (try @This().textUnknownField(allocator, line)) |raw| { errdefer allocator.free(raw); try @"_unknown_fields_list".append(allocator, raw); continue; }
                if (try @This().textUnknownGroup(allocator, line, &lines)) |raw| { errdefer allocator.free(raw); try @"_unknown_fields_list".append(allocator, raw); continue; }
                if (options.ignore_unknown_fields) continue;
                return error.UnknownField;
            }
            self.scores = if (scores_list.items.len != 0 and scores_list.items.len == scores_list.capacity) scores_list.toOwnedSliceAssert() else try scores_list.toOwnedSlice(allocator);
            self.counts = if (counts_list.items.len != 0 and counts_list.items.len == counts_list.capacity) counts_list.toOwnedSliceAssert() else try counts_list.toOwnedSlice(allocator);
            self.@"_unknown_fields" = try @"_unknown_fields_list".toOwnedSlice(allocator);
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

    pub const Packed = struct {
        pub const values_number = 1;

        pub const values_field = struct {
            pub const number = 1;
            pub const name = "values";
            pub const json_name = "values";
            pub const cardinality = "repeated";
            pub const kind = "int32";
            pub const type_name = "int32";
            pub const zig_type = "[]const i32";
            pub const has_type_ref = false;
            pub const type_ref = void;
            pub const has_enum_ref = false;
            pub const enum_ref = void;
            pub const has_presence = false;
            pub const default_value = "";
            pub const is_packed = true;
        };

        values: []const i32 = &.{},
        @"_json_arena": ?*std.heap.ArenaAllocator = null,
        @"_unknown_fields": []const []const u8 = &.{},

        pub fn init() @This() {
            return .{};
        }

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            allocator.free(self.values);
            for (self.@"_unknown_fields") |raw| allocator.free(raw);
            allocator.free(self.@"_unknown_fields");
            if (self.@"_json_arena") |arena| { const child_allocator = arena.child_allocator; arena.deinit(); child_allocator.destroy(arena); }
            self.* = undefined;
        }

        pub fn cloneOwned(self: @This(), allocator: std.mem.Allocator) !@This() {
            var out = @This().init();
            errdefer out.deinit(allocator);
            if (self.values.len != 0) {
                const cloned = try allocator.alloc(i32, self.values.len);
                for (self.values, 0..) |item, i| cloned[i] = item;
                out.values = cloned;
            }
            if (self.@"_unknown_fields".len != 0) {
                const cloned_unknowns = try allocator.alloc([]const u8, self.@"_unknown_fields".len);
                for (self.@"_unknown_fields", 0..) |raw, i| cloned_unknowns[i] = try allocator.dupe(u8, raw);
                out.@"_unknown_fields" = cloned_unknowns;
            }
            return out;
        }

        fn @"_pbzOwnedAllocator"(self: *@This(), allocator: std.mem.Allocator) !std.mem.Allocator {
            if (self.@"_json_arena" == null) {
                const arena = try allocator.create(std.heap.ArenaAllocator);
                errdefer allocator.destroy(arena);
                arena.* = std.heap.ArenaAllocator.init(allocator);
                self.@"_json_arena" = arena;
            }
            return self.@"_json_arena".?.allocator();
        }

        pub fn unknownFieldCount(self: @This()) usize {
            return self.@"_unknown_fields".len;
        }

        pub fn unknownFields(self: @This()) []const []const u8 {
            return self.@"_unknown_fields";
        }

        pub fn unknownFieldCountByNumber(self: @This(), number: pbz.FieldNumber) !usize {
            var count: usize = 0;
            for (self.@"_unknown_fields") |raw| {
                var r = pbz.Reader.init(raw);
                if (try r.nextTag()) |tag| {
                    if (tag.number == number) count += 1;
                }
            }
            return count;
        }

        pub fn hasUnknownFieldNumber(self: @This(), number: pbz.FieldNumber) !bool {
            return (try self.unknownFieldCountByNumber(number)) != 0;
        }

        pub fn unknownFieldsByNumberAlloc(self: @This(), allocator: std.mem.Allocator, number: pbz.FieldNumber) ![]const []const u8 {
            var list: std.ArrayList([]const u8) = .empty;
            errdefer list.deinit(allocator);
            for (self.@"_unknown_fields") |raw| {
                var r = pbz.Reader.init(raw);
                if (try r.nextTag()) |tag| {
                    if (tag.number == number) try list.append(allocator, raw);
                }
            }
            return try list.toOwnedSlice(allocator);
        }

        pub fn appendUnknownRaw(self: *@This(), allocator: std.mem.Allocator, raw: []const u8) !void {
            var r = pbz.Reader.init(raw);
            const tag = (try r.nextTag()) orelse return error.InvalidWireType;
            try r.skipValue(tag);
            if (!r.eof()) return error.InvalidWireType;
            const old = self.@"_unknown_fields";
            const next = try allocator.alloc([]const u8, old.len + 1);
            errdefer allocator.free(next);
            if (old.len != 0) @memcpy(next[0..old.len], old);
            const owned = try allocator.dupe(u8, raw);
            errdefer allocator.free(owned);
            next[old.len] = owned;
            self.@"_unknown_fields" = next;
            if (old.len != 0) allocator.free(old);
        }

        pub fn clearUnknownFieldsByNumber(self: *@This(), allocator: std.mem.Allocator, number: pbz.FieldNumber) !void {
            var kept: std.ArrayList([]const u8) = .empty;
            errdefer kept.deinit(allocator);
            for (self.@"_unknown_fields") |raw| {
                var r = pbz.Reader.init(raw);
                const tag = (try r.nextTag()) orelse { allocator.free(raw); continue; };
                if (tag.number == number) { allocator.free(raw); continue; }
                try kept.append(allocator, raw);
            }
            if (self.@"_unknown_fields".len != 0) allocator.free(self.@"_unknown_fields");
            self.@"_unknown_fields" = try kept.toOwnedSlice(allocator);
        }

        pub fn clearUnknownFields(self: *@This(), allocator: std.mem.Allocator) void {
            for (self.@"_unknown_fields") |raw| allocator.free(raw);
            if (self.@"_unknown_fields".len != 0) allocator.free(self.@"_unknown_fields");
            self.@"_unknown_fields" = &.{};
        }


        // no same-file extension accessors

        pub fn mergeFrom(self: *@This(), allocator: std.mem.Allocator, other: @This()) !void {
            if (other.values.len != 0) {
                const old = self.values;
                const merged = try allocator.alloc(i32, old.len + other.values.len);
                @memcpy(merged[0..old.len], old);
                @memcpy(merged[old.len..], other.values);
                self.values = merged;
                if (old.len != 0) allocator.free(old);
            }
            for (other.@"_unknown_fields") |raw| try self.appendUnknownRaw(allocator, raw);
        }

        pub fn encodedSize(self: @This()) usize {
            var size: usize = 0;
            if (self.values.len != 0) {
                var packed_len: usize = 0;
                for (self.values) |item| packed_len += pbz.wire.encodedVarintSize(@as(u64, @bitCast(@as(i64, item))));
                size += 1 + pbz.wire.encodedVarintSize(packed_len) + packed_len;
            }
            for (self.@"_unknown_fields") |raw| size += raw.len;
            return size;
        }

        pub fn writeTo(self: @This(), w: *pbz.Writer) !void {
            if (self.values.len != 0) {
                var packed_len: usize = 0;
                for (self.values) |item| packed_len += pbz.wire.encodedVarintSize(@as(u64, @bitCast(@as(i64, item))));
                try w.writeTag(1, .length_delimited);
                try w.writeVarint(packed_len);
                for (self.values) |item| try w.writeVarint(@as(u64, @bitCast(@as(i64, item))));
            }
            for (self.@"_unknown_fields") |raw| try w.appendSlice(raw);
        }

        pub fn writeToAssumeCapacity(self: @This(), w: *pbz.Writer) !void {
            if (self.values.len != 0) {
                var packed_len: usize = 0;
                for (self.values) |item| packed_len += pbz.wire.encodedVarintSize(@as(u64, @bitCast(@as(i64, item))));
                w.writeTagAssumeCapacity(1, .length_delimited);
                w.writeVarintAssumeCapacity(packed_len);
                for (self.values) |item| w.writeVarintAssumeCapacity(@as(u64, @bitCast(@as(i64, item))));
            }
            for (self.@"_unknown_fields") |raw| w.appendSliceAssumeCapacity(raw);
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
            var w = pbz.Writer.initBuffer(std.heap.page_allocator, buffer);
            try self.writeToAssumeCapacity(&w);
            return buffer[0..w.slice().len];
        }

        pub fn encodeDeterministic(self: @This(), allocator: std.mem.Allocator) ![]u8 {
            var w = pbz.Writer.init(allocator);
            errdefer w.deinit();
            if (self.values.len != 0) {
                var packed_len: usize = 0;
                for (self.values) |item| packed_len += pbz.wire.encodedVarintSize(@as(u64, @bitCast(@as(i64, item))));
                try w.writeTag(1, .length_delimited);
                try w.writeVarint(packed_len);
                for (self.values) |item| try w.writeVarint(@as(u64, @bitCast(@as(i64, item))));
            }
            if (self.@"_unknown_fields".len != 0) {
                const indexes = try allocator.alloc(usize, self.@"_unknown_fields".len);
                defer allocator.free(indexes);
                for (indexes, 0..) |*index, i| index.* = i;
                std.mem.sort(usize, indexes, self.@"_unknown_fields", struct {
                    fn firstTag(raw: []const u8) ?pbz.wire.Tag {
                        var r = pbz.Reader.init(raw);
                        return (r.nextTag() catch null) orelse null;
                    }
                    fn lessThan(raws: []const []const u8, a: usize, b: usize) bool {
                        const tag_a = firstTag(raws[a]);
                        const tag_b = firstTag(raws[b]);
                        if (tag_a == null or tag_b == null) return std.mem.lessThan(u8, raws[a], raws[b]);
                        if (tag_a.?.number != tag_b.?.number) return tag_a.?.number < tag_b.?.number;
                        if (tag_a.?.wire_type != tag_b.?.wire_type) return @intFromEnum(tag_a.?.wire_type) < @intFromEnum(tag_b.?.wire_type);
                        return std.mem.lessThan(u8, raws[a], raws[b]);
                    }
                }.lessThan);
                for (indexes) |index| try w.appendSlice(self.@"_unknown_fields"[index]);
            }
            return try w.toOwnedSlice();
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
            var self = @This().init();
            errdefer self.deinit(allocator);
            var values_list: std.ArrayList(i32) = .empty;
            defer values_list.deinit(allocator);
            var @"_unknown_fields_list": std.ArrayList([]const u8) = .empty;
            errdefer { for (@"_unknown_fields_list".items) |raw| allocator.free(raw); @"_unknown_fields_list".deinit(allocator); }
            var r = pbz.Reader.init(bytes);
            while (try r.nextTag()) |tag| {
                switch (tag.number) {
                    1 => {
                        if (tag.wire_type == .length_delimited) {
                            const payload = try r.readBytes();
                            try pbz.wire.appendPackedInt32(allocator, &values_list, payload);
                        } else {
                            try values_list.append(allocator, try r.readInt32());
                        }
                    },
                    else => { const start = r.position() - pbz.wire.encodedVarintSize(try tag.encode()); try r.skipValue(tag); const raw = try allocator.dupe(u8, r.input[start..r.position()]); errdefer allocator.free(raw); try @"_unknown_fields_list".append(allocator, raw); },
                }
            }
            self.values = if (values_list.items.len != 0 and values_list.items.len == values_list.capacity) values_list.toOwnedSliceAssert() else try values_list.toOwnedSlice(allocator);
            self.@"_unknown_fields" = try @"_unknown_fields_list".toOwnedSlice(allocator);
            return self;
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
            if (self.values.len != 0 or options.always_print_primitive_fields) {
                if (!first) try writer.writeAll(","); first = false;
                try writer.writeAll(if (options.preserve_proto_field_names) "\"values\":" else "\"values\":");
                try writer.writeAll("[");
                for (self.values, 0..) |item, i| { if (i != 0) try writer.writeAll(","); try writer.print("{d}", .{item}); }
                try writer.writeAll("]");
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
            var self = @This().init();
            errdefer self.deinit(allocator);
            try self.jsonFillFromValue(allocator, arena.allocator(), parsed, options);
            self.@"_json_arena" = arena;
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
                    if (std.mem.eql(u8, key, "values") or std.mem.eql(u8, key, "values")) {
                        const old = self.values; self.values = &.{}; if (old.len != 0) allocator.free(old);
                        continue;
                    }
                    if (options.ignore_unknown_fields) continue;
                    return error.UnknownField;
                }
                if (std.mem.eql(u8, key, "values") or std.mem.eql(u8, key, "values")) {
                    const array = switch (value) { .array => |array| array, else => return error.TypeMismatch };
                    var list: std.ArrayList(i32) = .empty;
                    errdefer list.deinit(allocator);
                    for (array.items) |item| try list.append(allocator, try @This().jsonInt(i32, item));
                    self.values = blk: { const old = self.values; const owned = try list.toOwnedSlice(allocator); if (old.len != 0) allocator.free(old); break :blk owned; };
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
    if (!std.unicode.utf8ValidateSlice(value)) return error.InvalidUtf8;
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
            for (self.values) |value| { try writer.writeAll("values: "); try writer.print("{d}", .{value}); try writer.writeByte('\n'); }
            for (self.@"_unknown_fields") |raw| {
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
            var values_list: std.ArrayList(i32) = .empty;
            defer values_list.deinit(allocator);
            var @"_unknown_fields_list": std.ArrayList([]const u8) = .empty;
            errdefer { for (@"_unknown_fields_list".items) |raw| allocator.free(raw); @"_unknown_fields_list".deinit(allocator); }
            const normalized_text = try @This().textNormalizeSeparators(allocator, text);
            defer allocator.free(normalized_text);
            var lines = std.mem.splitScalar(u8, normalized_text, '\n');
            while (lines.next()) |raw_line| {
                const line = @This().textCleanLine(raw_line);
                if (line.len == 0) continue;
                if (@This().textFieldValue(line, "values")) |raw_value| {
                    values_list.append(allocator, try @This().textInt(i32, raw_value)) catch |err| return err;
                    continue;
                }
                if (try @This().textUnknownField(allocator, line)) |raw| { errdefer allocator.free(raw); try @"_unknown_fields_list".append(allocator, raw); continue; }
                if (try @This().textUnknownGroup(allocator, line, &lines)) |raw| { errdefer allocator.free(raw); try @"_unknown_fields_list".append(allocator, raw); continue; }
                if (options.ignore_unknown_fields) continue;
                return error.UnknownField;
            }
            self.values = if (values_list.items.len != 0 and values_list.items.len == values_list.capacity) values_list.toOwnedSliceAssert() else try values_list.toOwnedSlice(allocator);
            self.@"_unknown_fields" = try @"_unknown_fields_list".toOwnedSlice(allocator);
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

    pub const FixedPacked = struct {
        pub const values_number = 1;

        pub const values_field = struct {
            pub const number = 1;
            pub const name = "values";
            pub const json_name = "values";
            pub const cardinality = "repeated";
            pub const kind = "fixed32";
            pub const type_name = "fixed32";
            pub const zig_type = "[]const u32";
            pub const has_type_ref = false;
            pub const type_ref = void;
            pub const has_enum_ref = false;
            pub const enum_ref = void;
            pub const has_presence = false;
            pub const default_value = "";
            pub const is_packed = true;
        };

        values: []const u32 = &.{},
        @"_json_arena": ?*std.heap.ArenaAllocator = null,
        @"_unknown_fields": []const []const u8 = &.{},

        pub fn init() @This() {
            return .{};
        }

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            allocator.free(self.values);
            for (self.@"_unknown_fields") |raw| allocator.free(raw);
            allocator.free(self.@"_unknown_fields");
            if (self.@"_json_arena") |arena| { const child_allocator = arena.child_allocator; arena.deinit(); child_allocator.destroy(arena); }
            self.* = undefined;
        }

        pub fn cloneOwned(self: @This(), allocator: std.mem.Allocator) !@This() {
            var out = @This().init();
            errdefer out.deinit(allocator);
            if (self.values.len != 0) {
                const cloned = try allocator.alloc(u32, self.values.len);
                for (self.values, 0..) |item, i| cloned[i] = item;
                out.values = cloned;
            }
            if (self.@"_unknown_fields".len != 0) {
                const cloned_unknowns = try allocator.alloc([]const u8, self.@"_unknown_fields".len);
                for (self.@"_unknown_fields", 0..) |raw, i| cloned_unknowns[i] = try allocator.dupe(u8, raw);
                out.@"_unknown_fields" = cloned_unknowns;
            }
            return out;
        }

        fn @"_pbzOwnedAllocator"(self: *@This(), allocator: std.mem.Allocator) !std.mem.Allocator {
            if (self.@"_json_arena" == null) {
                const arena = try allocator.create(std.heap.ArenaAllocator);
                errdefer allocator.destroy(arena);
                arena.* = std.heap.ArenaAllocator.init(allocator);
                self.@"_json_arena" = arena;
            }
            return self.@"_json_arena".?.allocator();
        }

        pub fn unknownFieldCount(self: @This()) usize {
            return self.@"_unknown_fields".len;
        }

        pub fn unknownFields(self: @This()) []const []const u8 {
            return self.@"_unknown_fields";
        }

        pub fn unknownFieldCountByNumber(self: @This(), number: pbz.FieldNumber) !usize {
            var count: usize = 0;
            for (self.@"_unknown_fields") |raw| {
                var r = pbz.Reader.init(raw);
                if (try r.nextTag()) |tag| {
                    if (tag.number == number) count += 1;
                }
            }
            return count;
        }

        pub fn hasUnknownFieldNumber(self: @This(), number: pbz.FieldNumber) !bool {
            return (try self.unknownFieldCountByNumber(number)) != 0;
        }

        pub fn unknownFieldsByNumberAlloc(self: @This(), allocator: std.mem.Allocator, number: pbz.FieldNumber) ![]const []const u8 {
            var list: std.ArrayList([]const u8) = .empty;
            errdefer list.deinit(allocator);
            for (self.@"_unknown_fields") |raw| {
                var r = pbz.Reader.init(raw);
                if (try r.nextTag()) |tag| {
                    if (tag.number == number) try list.append(allocator, raw);
                }
            }
            return try list.toOwnedSlice(allocator);
        }

        pub fn appendUnknownRaw(self: *@This(), allocator: std.mem.Allocator, raw: []const u8) !void {
            var r = pbz.Reader.init(raw);
            const tag = (try r.nextTag()) orelse return error.InvalidWireType;
            try r.skipValue(tag);
            if (!r.eof()) return error.InvalidWireType;
            const old = self.@"_unknown_fields";
            const next = try allocator.alloc([]const u8, old.len + 1);
            errdefer allocator.free(next);
            if (old.len != 0) @memcpy(next[0..old.len], old);
            const owned = try allocator.dupe(u8, raw);
            errdefer allocator.free(owned);
            next[old.len] = owned;
            self.@"_unknown_fields" = next;
            if (old.len != 0) allocator.free(old);
        }

        pub fn clearUnknownFieldsByNumber(self: *@This(), allocator: std.mem.Allocator, number: pbz.FieldNumber) !void {
            var kept: std.ArrayList([]const u8) = .empty;
            errdefer kept.deinit(allocator);
            for (self.@"_unknown_fields") |raw| {
                var r = pbz.Reader.init(raw);
                const tag = (try r.nextTag()) orelse { allocator.free(raw); continue; };
                if (tag.number == number) { allocator.free(raw); continue; }
                try kept.append(allocator, raw);
            }
            if (self.@"_unknown_fields".len != 0) allocator.free(self.@"_unknown_fields");
            self.@"_unknown_fields" = try kept.toOwnedSlice(allocator);
        }

        pub fn clearUnknownFields(self: *@This(), allocator: std.mem.Allocator) void {
            for (self.@"_unknown_fields") |raw| allocator.free(raw);
            if (self.@"_unknown_fields".len != 0) allocator.free(self.@"_unknown_fields");
            self.@"_unknown_fields" = &.{};
        }

        pub fn valuesPackedFixedView(bytes: []const u8) !?[]align(1) const u32 {
            return try pbz.wire.packedFixedWidthFieldView(u32, bytes, 1);
        }

        pub fn valuesPackedFixedSlices(header: *[20]u8, values: []const u32) !pbz.wire.BorrowedFieldSlices {
            return try pbz.wire.packedFixedWidthFieldSlices(u32, header, 1, values);
        }

        pub fn valuesPackedFixed32View(bytes: []const u8) !?[]align(1) const u32 {
            return try valuesPackedFixedView(bytes);
        }

        pub fn valuesPackedFixed32Slices(header: *[20]u8, values: []const u32) !pbz.wire.BorrowedFieldSlices {
            return try valuesPackedFixedSlices(header, values);
        }


        // no same-file extension accessors

        pub fn mergeFrom(self: *@This(), allocator: std.mem.Allocator, other: @This()) !void {
            if (other.values.len != 0) {
                const old = self.values;
                const merged = try allocator.alloc(u32, old.len + other.values.len);
                @memcpy(merged[0..old.len], old);
                @memcpy(merged[old.len..], other.values);
                self.values = merged;
                if (old.len != 0) allocator.free(old);
            }
            for (other.@"_unknown_fields") |raw| try self.appendUnknownRaw(allocator, raw);
        }

        pub fn encodedSize(self: @This()) usize {
            var size: usize = 0;
            if (self.values.len != 0) {
                const packed_len = self.values.len * 4;
                size += 1 + pbz.wire.encodedVarintSize(packed_len) + packed_len;
            }
            for (self.@"_unknown_fields") |raw| size += raw.len;
            return size;
        }

        pub fn writeTo(self: @This(), w: *pbz.Writer) !void {
            if (self.values.len != 0) {
                const packed_len = self.values.len * 4;
                try w.writeTag(1, .length_delimited);
                try w.writeVarint(packed_len);
                try pbz.wire.writePackedFixedWidthPayload(u32, w, self.values);
            }
            for (self.@"_unknown_fields") |raw| try w.appendSlice(raw);
        }

        pub fn writeToAssumeCapacity(self: @This(), w: *pbz.Writer) !void {
            if (self.values.len != 0) {
                const packed_len = self.values.len * 4;
                w.writeTagAssumeCapacity(1, .length_delimited);
                w.writeVarintAssumeCapacity(packed_len);
                pbz.wire.writePackedFixedWidthPayloadAssumeCapacity(u32, w, self.values);
            }
            for (self.@"_unknown_fields") |raw| w.appendSliceAssumeCapacity(raw);
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
            var w = pbz.Writer.initBuffer(std.heap.page_allocator, buffer);
            try self.writeToAssumeCapacity(&w);
            return buffer[0..w.slice().len];
        }

        pub fn encodeDeterministic(self: @This(), allocator: std.mem.Allocator) ![]u8 {
            var w = pbz.Writer.init(allocator);
            errdefer w.deinit();
            if (self.values.len != 0) {
                const packed_len = self.values.len * 4;
                try w.writeTag(1, .length_delimited);
                try w.writeVarint(packed_len);
                try pbz.wire.writePackedFixedWidthPayload(u32, w, self.values);
            }
            if (self.@"_unknown_fields".len != 0) {
                const indexes = try allocator.alloc(usize, self.@"_unknown_fields".len);
                defer allocator.free(indexes);
                for (indexes, 0..) |*index, i| index.* = i;
                std.mem.sort(usize, indexes, self.@"_unknown_fields", struct {
                    fn firstTag(raw: []const u8) ?pbz.wire.Tag {
                        var r = pbz.Reader.init(raw);
                        return (r.nextTag() catch null) orelse null;
                    }
                    fn lessThan(raws: []const []const u8, a: usize, b: usize) bool {
                        const tag_a = firstTag(raws[a]);
                        const tag_b = firstTag(raws[b]);
                        if (tag_a == null or tag_b == null) return std.mem.lessThan(u8, raws[a], raws[b]);
                        if (tag_a.?.number != tag_b.?.number) return tag_a.?.number < tag_b.?.number;
                        if (tag_a.?.wire_type != tag_b.?.wire_type) return @intFromEnum(tag_a.?.wire_type) < @intFromEnum(tag_b.?.wire_type);
                        return std.mem.lessThan(u8, raws[a], raws[b]);
                    }
                }.lessThan);
                for (indexes) |index| try w.appendSlice(self.@"_unknown_fields"[index]);
            }
            return try w.toOwnedSlice();
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
            var self = @This().init();
            errdefer self.deinit(allocator);
            var values_list: std.ArrayList(u32) = .empty;
            defer values_list.deinit(allocator);
            var @"_unknown_fields_list": std.ArrayList([]const u8) = .empty;
            errdefer { for (@"_unknown_fields_list".items) |raw| allocator.free(raw); @"_unknown_fields_list".deinit(allocator); }
            var r = pbz.Reader.init(bytes);
            while (try r.nextTag()) |tag| {
                switch (tag.number) {
                    1 => {
                        if (tag.wire_type == .length_delimited) {
                            const payload = try r.readBytes();
                            try pbz.wire.appendPackedFixed32(allocator, &values_list, payload);
                        } else {
                            try values_list.append(allocator, try r.readFixed32());
                        }
                    },
                    else => { const start = r.position() - pbz.wire.encodedVarintSize(try tag.encode()); try r.skipValue(tag); const raw = try allocator.dupe(u8, r.input[start..r.position()]); errdefer allocator.free(raw); try @"_unknown_fields_list".append(allocator, raw); },
                }
            }
            self.values = if (values_list.items.len != 0 and values_list.items.len == values_list.capacity) values_list.toOwnedSliceAssert() else try values_list.toOwnedSlice(allocator);
            self.@"_unknown_fields" = try @"_unknown_fields_list".toOwnedSlice(allocator);
            return self;
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
            if (self.values.len != 0 or options.always_print_primitive_fields) {
                if (!first) try writer.writeAll(","); first = false;
                try writer.writeAll(if (options.preserve_proto_field_names) "\"values\":" else "\"values\":");
                try writer.writeAll("[");
                for (self.values, 0..) |item, i| { if (i != 0) try writer.writeAll(","); try writer.print("{d}", .{item}); }
                try writer.writeAll("]");
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
            var self = @This().init();
            errdefer self.deinit(allocator);
            try self.jsonFillFromValue(allocator, arena.allocator(), parsed, options);
            self.@"_json_arena" = arena;
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
                    if (std.mem.eql(u8, key, "values") or std.mem.eql(u8, key, "values")) {
                        const old = self.values; self.values = &.{}; if (old.len != 0) allocator.free(old);
                        continue;
                    }
                    if (options.ignore_unknown_fields) continue;
                    return error.UnknownField;
                }
                if (std.mem.eql(u8, key, "values") or std.mem.eql(u8, key, "values")) {
                    const array = switch (value) { .array => |array| array, else => return error.TypeMismatch };
                    var list: std.ArrayList(u32) = .empty;
                    errdefer list.deinit(allocator);
                    for (array.items) |item| try list.append(allocator, try @This().jsonInt(u32, item));
                    self.values = blk: { const old = self.values; const owned = try list.toOwnedSlice(allocator); if (old.len != 0) allocator.free(old); break :blk owned; };
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
    if (!std.unicode.utf8ValidateSlice(value)) return error.InvalidUtf8;
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
            for (self.values) |value| { try writer.writeAll("values: "); try writer.print("{d}", .{value}); try writer.writeByte('\n'); }
            for (self.@"_unknown_fields") |raw| {
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
            var values_list: std.ArrayList(u32) = .empty;
            defer values_list.deinit(allocator);
            var @"_unknown_fields_list": std.ArrayList([]const u8) = .empty;
            errdefer { for (@"_unknown_fields_list".items) |raw| allocator.free(raw); @"_unknown_fields_list".deinit(allocator); }
            const normalized_text = try @This().textNormalizeSeparators(allocator, text);
            defer allocator.free(normalized_text);
            var lines = std.mem.splitScalar(u8, normalized_text, '\n');
            while (lines.next()) |raw_line| {
                const line = @This().textCleanLine(raw_line);
                if (line.len == 0) continue;
                if (@This().textFieldValue(line, "values")) |raw_value| {
                    values_list.append(allocator, try @This().textInt(u32, raw_value)) catch |err| return err;
                    continue;
                }
                if (try @This().textUnknownField(allocator, line)) |raw| { errdefer allocator.free(raw); try @"_unknown_fields_list".append(allocator, raw); continue; }
                if (try @This().textUnknownGroup(allocator, line, &lines)) |raw| { errdefer allocator.free(raw); try @"_unknown_fields_list".append(allocator, raw); continue; }
                if (options.ignore_unknown_fields) continue;
                return error.UnknownField;
            }
            self.values = if (values_list.items.len != 0 and values_list.items.len == values_list.capacity) values_list.toOwnedSliceAssert() else try values_list.toOwnedSlice(allocator);
            self.@"_unknown_fields" = try @"_unknown_fields_list".toOwnedSlice(allocator);
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

    pub const Fixed64Packed = struct {
        pub const values_number = 1;

        pub const values_field = struct {
            pub const number = 1;
            pub const name = "values";
            pub const json_name = "values";
            pub const cardinality = "repeated";
            pub const kind = "fixed64";
            pub const type_name = "fixed64";
            pub const zig_type = "[]const u64";
            pub const has_type_ref = false;
            pub const type_ref = void;
            pub const has_enum_ref = false;
            pub const enum_ref = void;
            pub const has_presence = false;
            pub const default_value = "";
            pub const is_packed = true;
        };

        values: []const u64 = &.{},
        @"_json_arena": ?*std.heap.ArenaAllocator = null,
        @"_unknown_fields": []const []const u8 = &.{},

        pub fn init() @This() {
            return .{};
        }

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            allocator.free(self.values);
            for (self.@"_unknown_fields") |raw| allocator.free(raw);
            allocator.free(self.@"_unknown_fields");
            if (self.@"_json_arena") |arena| { const child_allocator = arena.child_allocator; arena.deinit(); child_allocator.destroy(arena); }
            self.* = undefined;
        }

        pub fn cloneOwned(self: @This(), allocator: std.mem.Allocator) !@This() {
            var out = @This().init();
            errdefer out.deinit(allocator);
            if (self.values.len != 0) {
                const cloned = try allocator.alloc(u64, self.values.len);
                for (self.values, 0..) |item, i| cloned[i] = item;
                out.values = cloned;
            }
            if (self.@"_unknown_fields".len != 0) {
                const cloned_unknowns = try allocator.alloc([]const u8, self.@"_unknown_fields".len);
                for (self.@"_unknown_fields", 0..) |raw, i| cloned_unknowns[i] = try allocator.dupe(u8, raw);
                out.@"_unknown_fields" = cloned_unknowns;
            }
            return out;
        }

        fn @"_pbzOwnedAllocator"(self: *@This(), allocator: std.mem.Allocator) !std.mem.Allocator {
            if (self.@"_json_arena" == null) {
                const arena = try allocator.create(std.heap.ArenaAllocator);
                errdefer allocator.destroy(arena);
                arena.* = std.heap.ArenaAllocator.init(allocator);
                self.@"_json_arena" = arena;
            }
            return self.@"_json_arena".?.allocator();
        }

        pub fn unknownFieldCount(self: @This()) usize {
            return self.@"_unknown_fields".len;
        }

        pub fn unknownFields(self: @This()) []const []const u8 {
            return self.@"_unknown_fields";
        }

        pub fn unknownFieldCountByNumber(self: @This(), number: pbz.FieldNumber) !usize {
            var count: usize = 0;
            for (self.@"_unknown_fields") |raw| {
                var r = pbz.Reader.init(raw);
                if (try r.nextTag()) |tag| {
                    if (tag.number == number) count += 1;
                }
            }
            return count;
        }

        pub fn hasUnknownFieldNumber(self: @This(), number: pbz.FieldNumber) !bool {
            return (try self.unknownFieldCountByNumber(number)) != 0;
        }

        pub fn unknownFieldsByNumberAlloc(self: @This(), allocator: std.mem.Allocator, number: pbz.FieldNumber) ![]const []const u8 {
            var list: std.ArrayList([]const u8) = .empty;
            errdefer list.deinit(allocator);
            for (self.@"_unknown_fields") |raw| {
                var r = pbz.Reader.init(raw);
                if (try r.nextTag()) |tag| {
                    if (tag.number == number) try list.append(allocator, raw);
                }
            }
            return try list.toOwnedSlice(allocator);
        }

        pub fn appendUnknownRaw(self: *@This(), allocator: std.mem.Allocator, raw: []const u8) !void {
            var r = pbz.Reader.init(raw);
            const tag = (try r.nextTag()) orelse return error.InvalidWireType;
            try r.skipValue(tag);
            if (!r.eof()) return error.InvalidWireType;
            const old = self.@"_unknown_fields";
            const next = try allocator.alloc([]const u8, old.len + 1);
            errdefer allocator.free(next);
            if (old.len != 0) @memcpy(next[0..old.len], old);
            const owned = try allocator.dupe(u8, raw);
            errdefer allocator.free(owned);
            next[old.len] = owned;
            self.@"_unknown_fields" = next;
            if (old.len != 0) allocator.free(old);
        }

        pub fn clearUnknownFieldsByNumber(self: *@This(), allocator: std.mem.Allocator, number: pbz.FieldNumber) !void {
            var kept: std.ArrayList([]const u8) = .empty;
            errdefer kept.deinit(allocator);
            for (self.@"_unknown_fields") |raw| {
                var r = pbz.Reader.init(raw);
                const tag = (try r.nextTag()) orelse { allocator.free(raw); continue; };
                if (tag.number == number) { allocator.free(raw); continue; }
                try kept.append(allocator, raw);
            }
            if (self.@"_unknown_fields".len != 0) allocator.free(self.@"_unknown_fields");
            self.@"_unknown_fields" = try kept.toOwnedSlice(allocator);
        }

        pub fn clearUnknownFields(self: *@This(), allocator: std.mem.Allocator) void {
            for (self.@"_unknown_fields") |raw| allocator.free(raw);
            if (self.@"_unknown_fields".len != 0) allocator.free(self.@"_unknown_fields");
            self.@"_unknown_fields" = &.{};
        }

        pub fn valuesPackedFixedView(bytes: []const u8) !?[]align(1) const u64 {
            return try pbz.wire.packedFixedWidthFieldView(u64, bytes, 1);
        }

        pub fn valuesPackedFixedSlices(header: *[20]u8, values: []const u64) !pbz.wire.BorrowedFieldSlices {
            return try pbz.wire.packedFixedWidthFieldSlices(u64, header, 1, values);
        }


        // no same-file extension accessors

        pub fn mergeFrom(self: *@This(), allocator: std.mem.Allocator, other: @This()) !void {
            if (other.values.len != 0) {
                const old = self.values;
                const merged = try allocator.alloc(u64, old.len + other.values.len);
                @memcpy(merged[0..old.len], old);
                @memcpy(merged[old.len..], other.values);
                self.values = merged;
                if (old.len != 0) allocator.free(old);
            }
            for (other.@"_unknown_fields") |raw| try self.appendUnknownRaw(allocator, raw);
        }

        pub fn encodedSize(self: @This()) usize {
            var size: usize = 0;
            if (self.values.len != 0) {
                const packed_len = self.values.len * 8;
                size += 1 + pbz.wire.encodedVarintSize(packed_len) + packed_len;
            }
            for (self.@"_unknown_fields") |raw| size += raw.len;
            return size;
        }

        pub fn writeTo(self: @This(), w: *pbz.Writer) !void {
            if (self.values.len != 0) {
                const packed_len = self.values.len * 8;
                try w.writeTag(1, .length_delimited);
                try w.writeVarint(packed_len);
                try pbz.wire.writePackedFixedWidthPayload(u64, w, self.values);
            }
            for (self.@"_unknown_fields") |raw| try w.appendSlice(raw);
        }

        pub fn writeToAssumeCapacity(self: @This(), w: *pbz.Writer) !void {
            if (self.values.len != 0) {
                const packed_len = self.values.len * 8;
                w.writeTagAssumeCapacity(1, .length_delimited);
                w.writeVarintAssumeCapacity(packed_len);
                pbz.wire.writePackedFixedWidthPayloadAssumeCapacity(u64, w, self.values);
            }
            for (self.@"_unknown_fields") |raw| w.appendSliceAssumeCapacity(raw);
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
            var w = pbz.Writer.initBuffer(std.heap.page_allocator, buffer);
            try self.writeToAssumeCapacity(&w);
            return buffer[0..w.slice().len];
        }

        pub fn encodeDeterministic(self: @This(), allocator: std.mem.Allocator) ![]u8 {
            var w = pbz.Writer.init(allocator);
            errdefer w.deinit();
            if (self.values.len != 0) {
                const packed_len = self.values.len * 8;
                try w.writeTag(1, .length_delimited);
                try w.writeVarint(packed_len);
                try pbz.wire.writePackedFixedWidthPayload(u64, w, self.values);
            }
            if (self.@"_unknown_fields".len != 0) {
                const indexes = try allocator.alloc(usize, self.@"_unknown_fields".len);
                defer allocator.free(indexes);
                for (indexes, 0..) |*index, i| index.* = i;
                std.mem.sort(usize, indexes, self.@"_unknown_fields", struct {
                    fn firstTag(raw: []const u8) ?pbz.wire.Tag {
                        var r = pbz.Reader.init(raw);
                        return (r.nextTag() catch null) orelse null;
                    }
                    fn lessThan(raws: []const []const u8, a: usize, b: usize) bool {
                        const tag_a = firstTag(raws[a]);
                        const tag_b = firstTag(raws[b]);
                        if (tag_a == null or tag_b == null) return std.mem.lessThan(u8, raws[a], raws[b]);
                        if (tag_a.?.number != tag_b.?.number) return tag_a.?.number < tag_b.?.number;
                        if (tag_a.?.wire_type != tag_b.?.wire_type) return @intFromEnum(tag_a.?.wire_type) < @intFromEnum(tag_b.?.wire_type);
                        return std.mem.lessThan(u8, raws[a], raws[b]);
                    }
                }.lessThan);
                for (indexes) |index| try w.appendSlice(self.@"_unknown_fields"[index]);
            }
            return try w.toOwnedSlice();
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
            var self = @This().init();
            errdefer self.deinit(allocator);
            var values_list: std.ArrayList(u64) = .empty;
            defer values_list.deinit(allocator);
            var @"_unknown_fields_list": std.ArrayList([]const u8) = .empty;
            errdefer { for (@"_unknown_fields_list".items) |raw| allocator.free(raw); @"_unknown_fields_list".deinit(allocator); }
            var r = pbz.Reader.init(bytes);
            while (try r.nextTag()) |tag| {
                switch (tag.number) {
                    1 => {
                        if (tag.wire_type == .length_delimited) {
                            const payload = try r.readBytes();
                            try pbz.wire.appendPackedFixed64(allocator, &values_list, payload);
                        } else {
                            try values_list.append(allocator, try r.readFixed64());
                        }
                    },
                    else => { const start = r.position() - pbz.wire.encodedVarintSize(try tag.encode()); try r.skipValue(tag); const raw = try allocator.dupe(u8, r.input[start..r.position()]); errdefer allocator.free(raw); try @"_unknown_fields_list".append(allocator, raw); },
                }
            }
            self.values = if (values_list.items.len != 0 and values_list.items.len == values_list.capacity) values_list.toOwnedSliceAssert() else try values_list.toOwnedSlice(allocator);
            self.@"_unknown_fields" = try @"_unknown_fields_list".toOwnedSlice(allocator);
            return self;
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
            if (self.values.len != 0 or options.always_print_primitive_fields) {
                if (!first) try writer.writeAll(","); first = false;
                try writer.writeAll(if (options.preserve_proto_field_names) "\"values\":" else "\"values\":");
                try writer.writeAll("[");
                for (self.values, 0..) |item, i| { if (i != 0) try writer.writeAll(","); try writer.print("\"{d}\"", .{item}); }
                try writer.writeAll("]");
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
            var self = @This().init();
            errdefer self.deinit(allocator);
            try self.jsonFillFromValue(allocator, arena.allocator(), parsed, options);
            self.@"_json_arena" = arena;
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
                    if (std.mem.eql(u8, key, "values") or std.mem.eql(u8, key, "values")) {
                        const old = self.values; self.values = &.{}; if (old.len != 0) allocator.free(old);
                        continue;
                    }
                    if (options.ignore_unknown_fields) continue;
                    return error.UnknownField;
                }
                if (std.mem.eql(u8, key, "values") or std.mem.eql(u8, key, "values")) {
                    const array = switch (value) { .array => |array| array, else => return error.TypeMismatch };
                    var list: std.ArrayList(u64) = .empty;
                    errdefer list.deinit(allocator);
                    for (array.items) |item| try list.append(allocator, try @This().jsonInt(u64, item));
                    self.values = blk: { const old = self.values; const owned = try list.toOwnedSlice(allocator); if (old.len != 0) allocator.free(old); break :blk owned; };
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
    if (!std.unicode.utf8ValidateSlice(value)) return error.InvalidUtf8;
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
            for (self.values) |value| { try writer.writeAll("values: "); try writer.print("{d}", .{value}); try writer.writeByte('\n'); }
            for (self.@"_unknown_fields") |raw| {
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
            var values_list: std.ArrayList(u64) = .empty;
            defer values_list.deinit(allocator);
            var @"_unknown_fields_list": std.ArrayList([]const u8) = .empty;
            errdefer { for (@"_unknown_fields_list".items) |raw| allocator.free(raw); @"_unknown_fields_list".deinit(allocator); }
            const normalized_text = try @This().textNormalizeSeparators(allocator, text);
            defer allocator.free(normalized_text);
            var lines = std.mem.splitScalar(u8, normalized_text, '\n');
            while (lines.next()) |raw_line| {
                const line = @This().textCleanLine(raw_line);
                if (line.len == 0) continue;
                if (@This().textFieldValue(line, "values")) |raw_value| {
                    values_list.append(allocator, try @This().textInt(u64, raw_value)) catch |err| return err;
                    continue;
                }
                if (try @This().textUnknownField(allocator, line)) |raw| { errdefer allocator.free(raw); try @"_unknown_fields_list".append(allocator, raw); continue; }
                if (try @This().textUnknownGroup(allocator, line, &lines)) |raw| { errdefer allocator.free(raw); try @"_unknown_fields_list".append(allocator, raw); continue; }
                if (options.ignore_unknown_fields) continue;
                return error.UnknownField;
            }
            self.values = if (values_list.items.len != 0 and values_list.items.len == values_list.capacity) values_list.toOwnedSliceAssert() else try values_list.toOwnedSlice(allocator);
            self.@"_unknown_fields" = try @"_unknown_fields_list".toOwnedSlice(allocator);
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
