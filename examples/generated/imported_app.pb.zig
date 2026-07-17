const std = @import("std");
const pbz = @import("pbz");

pub const proto_package = "demo.imports.app";
pub const proto_syntax = "proto3";
pub const imports = struct {
    pub const imported_common_proto = @import("imported_common.pb.zig");
    pub const imported_common_proto_path = "imported_common.proto";
    pub const imported_common_proto_kind = "normal";
};
const pbz_generated_file = @This();

pub const demo = struct {
    pub const imports = struct {
        pub const app = struct {
            pub const Request = struct {
                pub const primary_number = 1;
                pub const history_number = 2;
                pub const by_name_number = 3;
                pub const chosen_number = 4;
                pub const fallback_number = 5;

                pub const primary_field = struct {
                    pub const number = 1;
                    pub const name = "primary";
                    pub const json_name = "primary";
                    pub const cardinality = "optional";
                    pub const kind = "message";
                    pub const type_name = "demo.imports.common.Profile";
                    pub const zig_type = "?pbz_generated_file.imports.imported_common_proto.demo.imports.common.Profile";
                    pub const has_type_ref = true;
                    pub const type_ref = pbz_generated_file.imports.imported_common_proto.demo.imports.common.Profile;
                    pub const has_enum_ref = false;
                    pub const enum_ref = void;
                    pub const has_presence = true;
                    pub const default_value = "";
                    pub const is_packed = false;
                };
                pub const history_field = struct {
                    pub const number = 2;
                    pub const name = "history";
                    pub const json_name = "history";
                    pub const cardinality = "repeated";
                    pub const kind = "message";
                    pub const type_name = "demo.imports.common.Profile";
                    pub const zig_type = "[]const pbz_generated_file.imports.imported_common_proto.demo.imports.common.Profile";
                    pub const has_type_ref = true;
                    pub const type_ref = pbz_generated_file.imports.imported_common_proto.demo.imports.common.Profile;
                    pub const has_enum_ref = false;
                    pub const enum_ref = void;
                    pub const has_presence = true;
                    pub const default_value = "";
                    pub const is_packed = false;
                };
                pub const by_name_field = struct {
                    pub const number = 3;
                    pub const name = "by_name";
                    pub const json_name = "byName";
                    pub const cardinality = "repeated";
                    pub const kind = "map";
                    pub const type_name = "";
                    pub const zig_type = "by_nameMap";
                    pub const has_type_ref = false;
                    pub const type_ref = void;
                    pub const has_enum_ref = false;
                    pub const enum_ref = void;
                    pub const has_presence = false;
                    pub const default_value = "";
                    pub const is_packed = false;
                    pub const map_key = "string";
                    pub const map_value_kind = "message";
                    pub const map_value_type_name = "demo.imports.common.Profile";
                    pub const map_value_has_type_ref = true;
                    pub const map_value_type_ref = pbz_generated_file.imports.imported_common_proto.demo.imports.common.Profile;
                    pub const map_value_has_enum_ref = false;
                    pub const map_value_enum_ref = void;
                };
                pub const chosen_field = struct {
                    pub const number = 4;
                    pub const name = "chosen";
                    pub const json_name = "chosen";
                    pub const cardinality = "optional";
                    pub const kind = "message";
                    pub const type_name = "demo.imports.common.Profile";
                    pub const zig_type = "pbz_generated_file.imports.imported_common_proto.demo.imports.common.Profile";
                    pub const has_type_ref = true;
                    pub const type_ref = pbz_generated_file.imports.imported_common_proto.demo.imports.common.Profile;
                    pub const has_enum_ref = false;
                    pub const enum_ref = void;
                    pub const has_presence = true;
                    pub const default_value = "";
                    pub const is_packed = false;
                };
                pub const fallback_field = struct {
                    pub const number = 5;
                    pub const name = "fallback";
                    pub const json_name = "fallback";
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

                pub const by_nameMap = std.StringArrayHashMapUnmanaged(pbz_generated_file.imports.imported_common_proto.demo.imports.common.Profile);

                pub const by_nameEntry = struct {
                    key: []const u8 = "",
                    value: pbz_generated_file.imports.imported_common_proto.demo.imports.common.Profile = .{},
                };

                fn appendOrReplaceMapEntry_by_name(allocator: std.mem.Allocator, list: *std.ArrayList(by_nameEntry), entry: by_nameEntry) !void {
                    for (list.items) |*existing| {
                        if (std.mem.eql(u8, existing.key, entry.key)) { existing.value.deinit(allocator); existing.* = entry; return; }
                    }
                    try list.append(allocator, entry);
                }

                fn putMapEntry_by_name(allocator: std.mem.Allocator, map: *by_nameMap, entry: by_nameEntry) !void {
                    if (map.getEntry(entry.key)) |existing| { existing.value_ptr.deinit(allocator); existing.value_ptr.* = entry.value; return; }
                    try map.put(allocator, entry.key, entry.value);
                }

                fn deinitMap_by_name(allocator: std.mem.Allocator, map: *by_nameMap) void {
                    var it = map.iterator();
                    while (it.next()) |entry| entry.value_ptr.deinit(allocator);
                    map.deinit(allocator);
                    map.* = .empty;
                }

                pub const selectedOneof = union(enum) {
                    none,
                    chosen: pbz_generated_file.imports.imported_common_proto.demo.imports.common.Profile,
                    fallback: []const u8,
                };

                primary: ?pbz_generated_file.imports.imported_common_proto.demo.imports.common.Profile = null,
                history: []const pbz_generated_file.imports.imported_common_proto.demo.imports.common.Profile = &.{},
                by_name: by_nameMap = .empty,
                selected: selectedOneof = .none,
                _json_arena: ?*std.heap.ArenaAllocator = null,
                _unknown_fields: []const []const u8 = &.{},

                pub fn init() @This() {
                    return .{};
                }

                pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
                    if (self.primary) |*value| value.deinit(allocator);
                    for (self.history) |value| { var mutable = value; mutable.deinit(allocator); }
                    allocator.free(self.history);
                    @This().deinitMap_by_name(allocator, &self.by_name);
                    switch (self.selected) {
                        .chosen => |*value| value.deinit(allocator),
                        else => {},
                    }
                    for (self._unknown_fields) |raw| allocator.free(raw);
                    allocator.free(self._unknown_fields);
                    if (self._json_arena) |arena| { const child_allocator = arena.child_allocator; arena.deinit(); child_allocator.destroy(arena); }
                    self.* = undefined;
                }

                pub fn cloneOwned(self: @This(), allocator: std.mem.Allocator) !@This() {
                    var out = @This().init();
                    errdefer out.deinit(allocator);
                    const owned_allocator = try out._pbzOwnedAllocator(allocator);
                    if (self.primary) |value| out.primary = try value.cloneOwned(allocator);
                    if (self.history.len != 0) {
                        const cloned = try allocator.alloc(pbz_generated_file.imports.imported_common_proto.demo.imports.common.Profile, self.history.len);
                        for (self.history, 0..) |item, i| cloned[i] = try item.cloneOwned(allocator);
                        out.history = cloned;
                    }
                    if (self.by_name.count() != 0) {
                        try out.by_name.ensureUnusedCapacity(allocator, self.by_name.count());
                        var map_it = self.by_name.iterator();
                        while (map_it.next()) |entry| try @This().putMapEntry_by_name(allocator, &out.by_name, .{ .key = try owned_allocator.dupe(u8, entry.key_ptr.*), .value = try entry.value_ptr.cloneOwned(allocator) });
                    }
                    out.selected = switch (self.selected) {
                        .none => .none,
                        .chosen => |value| .{ .chosen = try value.cloneOwned(allocator) },
                        .fallback => |value| .{ .fallback = try owned_allocator.dupe(u8, value) },
                    };
                    if (self._unknown_fields.len != 0) {
                        const cloned_unknowns = try allocator.alloc([]const u8, self._unknown_fields.len);
                        for (self._unknown_fields, 0..) |raw, i| cloned_unknowns[i] = try allocator.dupe(u8, raw);
                        out._unknown_fields = cloned_unknowns;
                    }
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
                    var count: usize = 0;
                    for (self._unknown_fields) |raw| {
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
                    for (self._unknown_fields) |raw| {
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
                    const old = self._unknown_fields;
                    const next = try allocator.alloc([]const u8, old.len + 1);
                    errdefer allocator.free(next);
                    if (old.len != 0) @memcpy(next[0..old.len], old);
                    const owned = try allocator.dupe(u8, raw);
                    errdefer allocator.free(owned);
                    next[old.len] = owned;
                    self._unknown_fields = next;
                    if (old.len != 0) allocator.free(old);
                }

                pub fn clearUnknownFieldsByNumber(self: *@This(), allocator: std.mem.Allocator, number: pbz.FieldNumber) !void {
                    var kept: std.ArrayList([]const u8) = .empty;
                    errdefer kept.deinit(allocator);
                    for (self._unknown_fields) |raw| {
                        var r = pbz.Reader.init(raw);
                        const tag = (try r.nextTag()) orelse { allocator.free(raw); continue; };
                        if (tag.number == number) { allocator.free(raw); continue; }
                        try kept.append(allocator, raw);
                    }
                    if (self._unknown_fields.len != 0) allocator.free(self._unknown_fields);
                    self._unknown_fields = try kept.toOwnedSlice(allocator);
                }

                pub fn clearUnknownFields(self: *@This(), allocator: std.mem.Allocator) void {
                    for (self._unknown_fields) |raw| allocator.free(raw);
                    if (self._unknown_fields.len != 0) allocator.free(self._unknown_fields);
                    self._unknown_fields = &.{};
                }


                // no same-file extension accessors

                pub fn mergeFrom(self: *@This(), allocator: std.mem.Allocator, other: @This()) !void {
                    if (other.primary) |other_value| {
                        if (self.primary) |*self_value| { try self_value.mergeFrom(allocator, other_value); } else { self.primary = try other_value.cloneOwned(allocator); }
                    }
                    if (other.history.len != 0) {
                        const old = self.history;
                        const merged = try allocator.alloc(pbz_generated_file.imports.imported_common_proto.demo.imports.common.Profile, old.len + other.history.len);
                        @memcpy(merged[0..old.len], old);
                        for (other.history, 0..) |item, i| merged[old.len + i] = try item.cloneOwned(allocator);
                        self.history = merged;
                        if (old.len != 0) allocator.free(old);
                    }
                    if (other.by_name.count() != 0) {
                        var other_it = other.by_name.iterator();
                        while (other_it.next()) |entry| try @This().putMapEntry_by_name(allocator, &self.by_name, .{ .key = entry.key_ptr.*, .value = try entry.value_ptr.cloneOwned(allocator) });
                    }
                    switch (other.selected) {
                        .none => {},
                        .chosen => |value| self.selected = .{ .chosen = try value.cloneOwned(allocator) },
                        .fallback => |value| self.selected = .{ .fallback = value },
                    }
                    for (other._unknown_fields) |raw| try self.appendUnknownRaw(allocator, raw);
                }

                pub fn encodedSize(self: @This()) usize {
                    var size: usize = 0;
                    if (self.primary) |value| { const payload_len = value.encodedSize(); size += 1 + pbz.wire.encodedVarintSize(payload_len) + payload_len; }
                    for (self.history) |item| { const payload_len = item.encodedSize(); size += 1 + pbz.wire.encodedVarintSize(payload_len) + payload_len; }
                    { var map_it = self.by_name.iterator(); while (map_it.next()) |entry| {
                        const key = entry.key_ptr.*; const value = entry.value_ptr.*;
                        const entry_len = 1 + pbz.wire.encodedVarintSize(key.len) + key.len + blk: { const value_len = value.encodedSize(); break :blk 1 + pbz.wire.encodedVarintSize(value_len) + value_len; };
                        size += 1 + pbz.wire.encodedVarintSize(entry_len) + entry_len;
                    } }
                    switch (self.selected) {
                        .none => {},
                        .chosen => |value| { const payload_len = value.encodedSize(); size += 1 + pbz.wire.encodedVarintSize(payload_len) + payload_len; },
                        .fallback => |value| size += 1 + pbz.wire.encodedVarintSize(value.len) + value.len,
                    }
                    for (self._unknown_fields) |raw| size += raw.len;
                    return size;
                }

                pub fn writeTo(self: @This(), w: *pbz.Writer) !void {
                    if (self.primary) |value| { const payload_len = value.encodedSize(); try w.writeTag(1, .length_delimited); try w.writeVarint(payload_len); try value.writeTo(w); }
                    for (self.history) |item| { const payload_len = item.encodedSize(); try w.writeTag(2, .length_delimited); try w.writeVarint(payload_len); try item.writeTo(w); }
                    { var map_it = self.by_name.iterator(); while (map_it.next()) |map_entry| {
                        const entry = by_nameEntry{ .key = map_entry.key_ptr.*, .value = map_entry.value_ptr.* };
                        if (!pbz.validateUtf8(entry.key)) return error.InvalidUtf8;
                        const entry_len = 1 + pbz.wire.encodedVarintSize(entry.key.len) + entry.key.len + blk: { const value_len = entry.value.encodedSize(); break :blk 1 + pbz.wire.encodedVarintSize(value_len) + value_len; };
                        try w.writeTag(3, .length_delimited);
                        try w.writeVarint(entry_len);
                        try w.writeString(1, entry.key);
                        { const value_len = entry.value.encodedSize(); try w.writeTag(2, .length_delimited); try w.writeVarint(value_len); try entry.value.writeTo(w); }
                    } }
                    switch (self.selected) {
                        .none => {},
                        .chosen => |value| { const payload_len = value.encodedSize(); try w.writeTag(4, .length_delimited); try w.writeVarint(payload_len); try value.writeTo(w); },
                        .fallback => |value| { if (!pbz.validateUtf8(value)) return error.InvalidUtf8; try w.writeString(5, value); },
                    }
                    for (self._unknown_fields) |raw| try w.appendSlice(raw);
                }

                pub fn writeToAssumeCapacity(self: @This(), w: *pbz.Writer) !void {
                    if (self.primary) |value| { const payload_len = value.encodedSize(); w.writeTagAssumeCapacity(1, .length_delimited); w.writeVarintAssumeCapacity(payload_len); try value.writeToAssumeCapacity(w); }
                    for (self.history) |item| { const payload_len = item.encodedSize(); w.writeTagAssumeCapacity(2, .length_delimited); w.writeVarintAssumeCapacity(payload_len); try item.writeToAssumeCapacity(w); }
                    { var map_it = self.by_name.iterator(); while (map_it.next()) |map_entry| {
                        const entry = by_nameEntry{ .key = map_entry.key_ptr.*, .value = map_entry.value_ptr.* };
                        if (!pbz.validateUtf8(entry.key)) return error.InvalidUtf8;
                        const entry_len = 1 + pbz.wire.encodedVarintSize(entry.key.len) + entry.key.len + blk: { const value_len = entry.value.encodedSize(); break :blk 1 + pbz.wire.encodedVarintSize(value_len) + value_len; };
                        w.writeTagAssumeCapacity(3, .length_delimited);
                        w.writeVarintAssumeCapacity(entry_len);
                        w.writeStringAssumeCapacity(1, entry.key);
                        { const value_len = entry.value.encodedSize(); w.writeTagAssumeCapacity(2, .length_delimited); w.writeVarintAssumeCapacity(value_len); try entry.value.writeToAssumeCapacity(w); }
                    } }
                    switch (self.selected) {
                        .none => {},
                        .chosen => |value| { const payload_len = value.encodedSize(); w.writeTagAssumeCapacity(4, .length_delimited); w.writeVarintAssumeCapacity(payload_len); try value.writeToAssumeCapacity(w); },
                        .fallback => |value| { if (!pbz.validateUtf8(value)) return error.InvalidUtf8; w.writeStringAssumeCapacity(5, value); },
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
                    if (self.primary) |value| { const payload_len = value.encodedSize(); buffer[index] = 10; index += 1; pbz.wire.writeVarintToSlice(buffer, &index, payload_len); _ = try value.encodeIntoAssumeCapacity(buffer[index..][0..payload_len]); index += payload_len; }
                    for (self.history) |item| { const payload_len = item.encodedSize(); buffer[index] = 18; index += 1; pbz.wire.writeVarintToSlice(buffer, &index, payload_len); _ = try item.encodeIntoAssumeCapacity(buffer[index..][0..payload_len]); index += payload_len; }
                    { var map_it = self.by_name.iterator(); while (map_it.next()) |map_entry| {
                        const key = map_entry.key_ptr.*; const value = map_entry.value_ptr.*;
                        if (!pbz.validateUtf8(key)) return error.InvalidUtf8;
                        const entry_len = 1 + pbz.wire.encodedVarintSize(key.len) + key.len + blk: { const value_len = value.encodedSize(); break :blk 1 + pbz.wire.encodedVarintSize(value_len) + value_len; };
                        buffer[index] = 26; index += 1;
                        pbz.wire.writeVarintToSlice(buffer, &index, entry_len);
                        buffer[index] = 10; index += 1; pbz.wire.writeVarintToSlice(buffer, &index, key.len); @memcpy(buffer[index..][0..key.len], key); index += key.len;
                        const value_len = value.encodedSize(); buffer[index] = 18; index += 1; pbz.wire.writeVarintToSlice(buffer, &index, value_len); _ = try value.encodeIntoAssumeCapacity(buffer[index..][0..value_len]); index += value_len;
                    } }
                    switch (self.selected) {
                        .none => {},
                        .chosen => |value| { const payload_len = value.encodedSize(); buffer[index] = 34; index += 1; pbz.wire.writeVarintToSlice(buffer, &index, payload_len); _ = try value.encodeIntoAssumeCapacity(buffer[index..][0..payload_len]); index += payload_len; },
                        .fallback => |value| { if (!pbz.validateUtf8(value)) return error.InvalidUtf8; buffer[index] = 42; index += 1; pbz.wire.writeVarintToSlice(buffer, &index, value.len); @memcpy(buffer[index..][0..value.len], value); index += value.len; },
                    }
                    for (self._unknown_fields) |raw| { @memcpy(buffer[index..][0..raw.len], raw); index += raw.len; }
                    return buffer[0..index];
                }

                pub fn encodeIntoAssumeCapacityTrustedUtf8(self: @This(), buffer: []u8) ![]u8 {
                    var index: usize = 0;
                    if (self.primary) |value| { const payload_len = value.encodedSize(); buffer[index] = 10; index += 1; pbz.wire.writeVarintToSlice(buffer, &index, payload_len); _ = try value.encodeIntoAssumeCapacityTrustedUtf8(buffer[index..][0..payload_len]); index += payload_len; }
                    for (self.history) |item| { const payload_len = item.encodedSize(); buffer[index] = 18; index += 1; pbz.wire.writeVarintToSlice(buffer, &index, payload_len); _ = try item.encodeIntoAssumeCapacityTrustedUtf8(buffer[index..][0..payload_len]); index += payload_len; }
                    { var map_it = self.by_name.iterator(); while (map_it.next()) |map_entry| {
                        const key = map_entry.key_ptr.*; const value = map_entry.value_ptr.*;
                        const entry_len = 1 + pbz.wire.encodedVarintSize(key.len) + key.len + blk: { const value_len = value.encodedSize(); break :blk 1 + pbz.wire.encodedVarintSize(value_len) + value_len; };
                        buffer[index] = 26; index += 1;
                        pbz.wire.writeVarintToSlice(buffer, &index, entry_len);
                        buffer[index] = 10; index += 1; pbz.wire.writeVarintToSlice(buffer, &index, key.len); @memcpy(buffer[index..][0..key.len], key); index += key.len;
                        const value_len = value.encodedSize(); buffer[index] = 18; index += 1; pbz.wire.writeVarintToSlice(buffer, &index, value_len); _ = try value.encodeIntoAssumeCapacityTrustedUtf8(buffer[index..][0..value_len]); index += value_len;
                    } }
                    switch (self.selected) {
                        .none => {},
                        .chosen => |value| { const payload_len = value.encodedSize(); buffer[index] = 34; index += 1; pbz.wire.writeVarintToSlice(buffer, &index, payload_len); _ = try value.encodeIntoAssumeCapacityTrustedUtf8(buffer[index..][0..payload_len]); index += payload_len; },
                        .fallback => |value| { buffer[index] = 42; index += 1; pbz.wire.writeVarintToSlice(buffer, &index, value.len); @memcpy(buffer[index..][0..value.len], value); index += value.len; },
                    }
                    for (self._unknown_fields) |raw| { @memcpy(buffer[index..][0..raw.len], raw); index += raw.len; }
                    return buffer[0..index];
                }

                pub fn writeDeterministicTo(self: @This(), allocator: std.mem.Allocator, w: *pbz.Writer) !void {
                    if (self.primary) |item| { const payload_len = item.encodedSize(); try w.writeTag(1, .length_delimited); try w.writeVarint(payload_len); try item.writeDeterministicTo(allocator, w); }
                    for (self.history) |item| { const payload_len = item.encodedSize(); try w.writeTag(2, .length_delimited); try w.writeVarint(payload_len); try item.writeDeterministicTo(allocator, w); }
                    if (self.by_name.count() != 0) {
                        var stack_entries: [32]by_nameEntry = undefined;
                        const use_stack_entries = self.by_name.count() <= stack_entries.len;
                        const entries = if (use_stack_entries) blk: { var map_it = self.by_name.iterator(); var i: usize = 0; while (map_it.next()) |entry| : (i += 1) stack_entries[i] = .{ .key = entry.key_ptr.*, .value = entry.value_ptr.* }; break :blk stack_entries[0..self.by_name.count()]; } else blk: { const owned = try allocator.alloc(by_nameEntry, self.by_name.count()); var map_it = self.by_name.iterator(); var i: usize = 0; while (map_it.next()) |entry| : (i += 1) owned[i] = .{ .key = entry.key_ptr.*, .value = entry.value_ptr.* }; break :blk owned; };
                        defer if (!use_stack_entries) allocator.free(entries);
                        if (use_stack_entries) {
                            var sort_i: usize = 1;
                            while (sort_i < entries.len) : (sort_i += 1) {
                                const item = entries[sort_i];
                                var sort_j = sort_i;
                                while (sort_j > 0 and std.mem.lessThan(u8, item.key, entries[sort_j - 1].key)) : (sort_j -= 1) entries[sort_j] = entries[sort_j - 1];
                                entries[sort_j] = item;
                            }
                        } else {
                            std.mem.sort(by_nameEntry, entries, {}, struct { fn lessThan(_: void, a: by_nameEntry, b: by_nameEntry) bool { return std.mem.lessThan(u8, a.key, b.key); } }.lessThan);
                        }
                        for (entries) |entry| {
                            if (!pbz.validateUtf8(entry.key)) return error.InvalidUtf8;
                            const entry_len = 1 + pbz.wire.encodedVarintSize(entry.key.len) + entry.key.len + blk: { const value_len = entry.value.encodedSize(); break :blk 1 + pbz.wire.encodedVarintSize(value_len) + value_len; };
                            try w.writeTag(3, .length_delimited);
                            try w.writeVarint(entry_len);
                            try w.writeString(1, entry.key);
                            { const value_len = entry.value.encodedSize(); try w.writeTag(2, .length_delimited); try w.writeVarint(value_len); try entry.value.writeTo(w); }
                        }
                    }
                    switch (self.selected) {
                        .chosen => |value| { const payload_len = value.encodedSize(); try w.writeTag(4, .length_delimited); try w.writeVarint(payload_len); try value.writeDeterministicTo(allocator, w); },
                        else => {},
                    }
                    switch (self.selected) {
                        .fallback => |value| { if (!pbz.validateUtf8(value)) return error.InvalidUtf8; try w.writeString(5, value); },
                        else => {},
                    }
                    if (self._unknown_fields.len != 0) {
                        const indexes = try allocator.alloc(usize, self._unknown_fields.len);
                        defer allocator.free(indexes);
                        for (indexes, 0..) |*index, i| index.* = i;
                        std.mem.sort(usize, indexes, self._unknown_fields, struct {
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
                        for (indexes) |index| try w.appendSlice(self._unknown_fields[index]);
                    }
                }

                pub fn writeDeterministicToAssumeCapacity(self: @This(), allocator: std.mem.Allocator, w: *pbz.Writer) !void {
                    if (self.primary) |item| { const payload_len = item.encodedSize(); w.writeTagAssumeCapacity(1, .length_delimited); w.writeVarintAssumeCapacity(payload_len); try item.writeDeterministicToAssumeCapacity(allocator, w); }
                    for (self.history) |item| { const payload_len = item.encodedSize(); w.writeTagAssumeCapacity(2, .length_delimited); w.writeVarintAssumeCapacity(payload_len); try item.writeDeterministicToAssumeCapacity(allocator, w); }
                    if (self.by_name.count() != 0) {
                        var stack_entries: [32]by_nameEntry = undefined;
                        const use_stack_entries = self.by_name.count() <= stack_entries.len;
                        const entries = if (use_stack_entries) blk: { var map_it = self.by_name.iterator(); var i: usize = 0; while (map_it.next()) |entry| : (i += 1) stack_entries[i] = .{ .key = entry.key_ptr.*, .value = entry.value_ptr.* }; break :blk stack_entries[0..self.by_name.count()]; } else blk: { const owned = try allocator.alloc(by_nameEntry, self.by_name.count()); var map_it = self.by_name.iterator(); var i: usize = 0; while (map_it.next()) |entry| : (i += 1) owned[i] = .{ .key = entry.key_ptr.*, .value = entry.value_ptr.* }; break :blk owned; };
                        defer if (!use_stack_entries) allocator.free(entries);
                        if (use_stack_entries) {
                            var sort_i: usize = 1;
                            while (sort_i < entries.len) : (sort_i += 1) {
                                const item = entries[sort_i];
                                var sort_j = sort_i;
                                while (sort_j > 0 and std.mem.lessThan(u8, item.key, entries[sort_j - 1].key)) : (sort_j -= 1) entries[sort_j] = entries[sort_j - 1];
                                entries[sort_j] = item;
                            }
                        } else {
                            std.mem.sort(by_nameEntry, entries, {}, struct { fn lessThan(_: void, a: by_nameEntry, b: by_nameEntry) bool { return std.mem.lessThan(u8, a.key, b.key); } }.lessThan);
                        }
                        for (entries) |entry| {
                            if (!pbz.validateUtf8(entry.key)) return error.InvalidUtf8;
                            const entry_len = 1 + pbz.wire.encodedVarintSize(entry.key.len) + entry.key.len + blk: { const value_len = entry.value.encodedSize(); break :blk 1 + pbz.wire.encodedVarintSize(value_len) + value_len; };
                            w.writeTagAssumeCapacity(3, .length_delimited);
                            w.writeVarintAssumeCapacity(entry_len);
                            w.writeStringAssumeCapacity(1, entry.key);
                            { const value_len = entry.value.encodedSize(); w.writeTagAssumeCapacity(2, .length_delimited); w.writeVarintAssumeCapacity(value_len); try entry.value.writeToAssumeCapacity(w); }
                        }
                    }
                    switch (self.selected) {
                        .chosen => |value| { const payload_len = value.encodedSize(); w.writeTagAssumeCapacity(4, .length_delimited); w.writeVarintAssumeCapacity(payload_len); try value.writeDeterministicToAssumeCapacity(allocator, w); },
                        else => {},
                    }
                    switch (self.selected) {
                        .fallback => |value| { if (!pbz.validateUtf8(value)) return error.InvalidUtf8; w.writeStringAssumeCapacity(5, value); },
                        else => {},
                    }
                    if (self._unknown_fields.len != 0) {
                        const indexes = try allocator.alloc(usize, self._unknown_fields.len);
                        defer allocator.free(indexes);
                        for (indexes, 0..) |*index, i| index.* = i;
                        std.mem.sort(usize, indexes, self._unknown_fields, struct {
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
                        for (indexes) |index| w.appendSliceAssumeCapacity(self._unknown_fields[index]);
                    }
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
                    var history_list: std.ArrayList(pbz_generated_file.imports.imported_common_proto.demo.imports.common.Profile) = .empty;
                    defer history_list.deinit(allocator);
                    errdefer for (history_list.items) |item| { var mutable = item; mutable.deinit(allocator); };
                    var _unknown_fields_list: std.ArrayList([]const u8) = .empty;
                    errdefer { for (_unknown_fields_list.items) |raw| allocator.free(raw); _unknown_fields_list.deinit(allocator); }
                    while (try r.nextTag()) |tag| {
                        switch (tag.number) {
                            1 => { const payload = try r.readBytes(); var payload_reader = try r.nested(payload); var nested = try pbz_generated_file.imports.imported_common_proto.demo.imports.common.Profile.decodeFromReader(allocator, &payload_reader); errdefer nested.deinit(allocator); if (self.primary) |*existing| { try existing.mergeFrom(allocator, nested); nested.deinit(allocator); } else { self.primary = nested; } },
                            2 => { const payload = try r.readBytes(); var payload_reader = try r.nested(payload); var nested = try pbz_generated_file.imports.imported_common_proto.demo.imports.common.Profile.decodeFromReader(allocator, &payload_reader); errdefer nested.deinit(allocator); try history_list.append(allocator, nested); },
                            3 => {
                                var entry = by_nameEntry{};
                                errdefer entry.value.deinit(allocator);
                                const payload = try r.readBytes();
                                var entry_reader = try r.nested(payload);
                                const skip_entry = false;
                                while (try entry_reader.nextTag()) |entry_tag| {
                                    switch (entry_tag.number) {
                                        1 => { const value = try entry_reader.readBytes(); if (!pbz.validateUtf8(value)) return error.InvalidUtf8; entry.key = value; },
                                        2 => { const value_payload = try entry_reader.readBytes(); var value_reader = try entry_reader.nested(value_payload); entry.value.deinit(allocator); entry.value = try pbz_generated_file.imports.imported_common_proto.demo.imports.common.Profile.decodeFromReader(allocator, &value_reader); },
                                        else => try entry_reader.skipValue(entry_tag),
                                    }
                                }
                                if (skip_entry) { var unknown_writer = pbz.Writer.init(allocator); defer unknown_writer.deinit(); try unknown_writer.writeBytes(3, payload); const raw = try allocator.dupe(u8, unknown_writer.slice()); errdefer allocator.free(raw); try _unknown_fields_list.append(allocator, raw); } else try @This().putMapEntry_by_name(allocator, &self.by_name, entry);
                            },
                            4 => { const payload = try r.readBytes(); var payload_reader = try r.nested(payload); self.selected = .{ .chosen = try pbz_generated_file.imports.imported_common_proto.demo.imports.common.Profile.decodeFromReader(allocator, &payload_reader) }; },
                            5 => { const value = try r.readBytes(); if (!pbz.validateUtf8(value)) return error.InvalidUtf8; self.selected = .{ .fallback = value }; },
                            else => { const start = r.position() - pbz.wire.encodedVarintSize(try tag.encode()); try r.skipValue(tag); const raw = try allocator.dupe(u8, r.input[start..r.position()]); errdefer allocator.free(raw); try _unknown_fields_list.append(allocator, raw); },
                        }
                    }
                    self.history = if (history_list.items.len != 0 and history_list.items.len == history_list.capacity) history_list.toOwnedSliceAssert() else try history_list.toOwnedSlice(allocator);
                    self._unknown_fields = if (_unknown_fields_list.items.len == 0) &.{} else try _unknown_fields_list.toOwnedSlice(allocator);
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
                    if (self.primary) |nested| {
                        if (try nested.missingRequiredFieldPath(allocator)) |suffix| { defer allocator.free(suffix); return try std.fmt.allocPrint(allocator, "primary.{s}", .{suffix}); }
                    }
                    for (self.history) |nested| {
                        if (try nested.missingRequiredFieldPath(allocator)) |suffix| { defer allocator.free(suffix); return try std.fmt.allocPrint(allocator, "history.{s}", .{suffix}); }
                    }
                    { var map_it = self.by_name.iterator(); while (map_it.next()) |entry| {
                        if (try entry.value_ptr.missingRequiredFieldPath(allocator)) |suffix| { defer allocator.free(suffix); return try std.fmt.allocPrint(allocator, "by_name.{s}", .{suffix}); }
                    } }
                    switch (self.selected) {
                        .none => {},
                        .chosen => |nested| {
                            if (try nested.missingRequiredFieldPath(allocator)) |suffix| { defer allocator.free(suffix); return try std.fmt.allocPrint(allocator, "chosen.{s}", .{suffix}); }
                        },
                        else => {},
                    }
                    return null;
                }

                pub fn validateRequired(self: @This()) !void {
                    if (self.missingRequiredFieldName() != null) return error.MissingRequiredField;
                }

                pub fn validateRequiredRecursive(self: @This(), allocator: std.mem.Allocator) !void {
                    try self.validateRequired();
                    if (self.primary) |nested| try nested.validateRequiredRecursive(allocator);
                    for (self.history) |nested| try nested.validateRequiredRecursive(allocator);
                    { var map_it = self.by_name.iterator(); while (map_it.next()) |entry| {
                        try entry.value_ptr.validateRequiredRecursive(allocator);
                    } }
                    switch (self.selected) {
                        .none => {},
                        .chosen => |nested| try nested.validateRequiredRecursive(allocator),
                        else => {},
                    }
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
                    try writer.writeAll("{");
                    var first = true;
                    if (self.primary) |nested| {
                        if (!first) try writer.writeAll(","); first = false;
                        try writer.writeAll(if (options.preserve_proto_field_names) "\"primary\":" else "\"primary\":");
                        try nested.jsonStringifyWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name, .preserve_proto_field_names = options.preserve_proto_field_names, .always_print_primitive_fields = options.always_print_primitive_fields });
                    }
                    if (self.history.len != 0 or options.always_print_primitive_fields) {
                        if (!first) try writer.writeAll(","); first = false;
                        try writer.writeAll(if (options.preserve_proto_field_names) "\"history\":" else "\"history\":");
                        try writer.writeAll("[");
                        for (self.history, 0..) |item, i| {
                            if (i != 0) try writer.writeAll(",");
                            try item.jsonStringifyWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name, .preserve_proto_field_names = options.preserve_proto_field_names, .always_print_primitive_fields = options.always_print_primitive_fields });
                        }
                        try writer.writeAll("]");
                    }
                    if (self.by_name.count() != 0 or options.always_print_primitive_fields) {
                        if (!first) try writer.writeAll(","); first = false;
                        try writer.writeAll(if (options.preserve_proto_field_names) "\"by_name\":" else "\"byName\":");
                        try writer.writeAll("{");
                        var map_it = self.by_name.iterator();
                        var i: usize = 0;
                        while (map_it.next()) |map_entry| : (i += 1) {
                            const entry = by_nameEntry{ .key = map_entry.key_ptr.*, .value = map_entry.value_ptr.* };
                            if (i != 0) try writer.writeAll(",");
                            try @This().jsonWriteString(writer, entry.key);
                            try writer.writeAll(":");
                            try entry.value.jsonStringifyWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name, .preserve_proto_field_names = options.preserve_proto_field_names, .always_print_primitive_fields = options.always_print_primitive_fields });
                        }
                        try writer.writeAll("}");
                    }
                    switch (self.selected) {
                        .none => {},
                        .chosen => |value| {
                            if (!first) try writer.writeAll(","); first = false;
                            try writer.writeAll(if (options.preserve_proto_field_names) "\"chosen\":" else "\"chosen\":");
                            try value.jsonStringifyWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name, .preserve_proto_field_names = options.preserve_proto_field_names, .always_print_primitive_fields = options.always_print_primitive_fields });
                        },
                        .fallback => |value| {
                            if (!first) try writer.writeAll(","); first = false;
                            try writer.writeAll(if (options.preserve_proto_field_names) "\"fallback\":" else "\"fallback\":");
                            try @This().jsonWriteString(writer, value);
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
                    const object = switch (json_value) { .object => |object| object, else => return error.TypeMismatch };
                    var it = object.iterator();
                    while (it.next()) |entry| {
                        const key = entry.key_ptr.*;
                        const value = entry.value_ptr.*;
                        if (value == .null) {
                            if (std.mem.eql(u8, key, "primary") or std.mem.eql(u8, key, "primary")) {
                                if (self.primary) |*old_value| old_value.deinit(allocator); self.primary = null;
                                continue;
                            }
                            if (std.mem.eql(u8, key, "history") or std.mem.eql(u8, key, "history")) {
                                const old = self.history; self.history = &.{}; for (old) |item| { var mutable = item; mutable.deinit(allocator); } if (old.len != 0) allocator.free(old);
                                continue;
                            }
                            if (std.mem.eql(u8, key, "by_name") or std.mem.eql(u8, key, "byName")) {
                                @This().deinitMap_by_name(allocator, &self.by_name);
                                continue;
                            }
                            if (std.mem.eql(u8, key, "chosen") or std.mem.eql(u8, key, "chosen")) { self.selected = .none; continue; }
                            if (std.mem.eql(u8, key, "fallback") or std.mem.eql(u8, key, "fallback")) { self.selected = .none; continue; }
                            if (options.ignore_unknown_fields) continue;
                            return error.UnknownField;
                        }
                        if (std.mem.eql(u8, key, "primary") or std.mem.eql(u8, key, "primary")) {
                            var nested = try pbz_generated_file.imports.imported_common_proto.demo.imports.common.Profile.jsonParseValueWithOptions(allocator, arena_allocator, value, .{ .ignore_unknown_fields = options.ignore_unknown_fields });
                            errdefer nested.deinit(allocator);
                            if (self.primary) |*existing| { try existing.mergeFrom(allocator, nested); nested.deinit(allocator); } else { self.primary = nested; }
                            continue;
                        }
                        if (std.mem.eql(u8, key, "history") or std.mem.eql(u8, key, "history")) {
                            const array = switch (value) { .array => |array| array, else => return error.TypeMismatch };
                            var list: std.ArrayList(pbz_generated_file.imports.imported_common_proto.demo.imports.common.Profile) = .empty;
                            errdefer { for (list.items) |item| { var mutable = item; mutable.deinit(allocator); } list.deinit(allocator); }
                            for (array.items) |item| {
                                var nested = try pbz_generated_file.imports.imported_common_proto.demo.imports.common.Profile.jsonParseValueWithOptions(allocator, arena_allocator, item, .{ .ignore_unknown_fields = options.ignore_unknown_fields });
                                errdefer nested.deinit(allocator);
                                try list.append(allocator, nested);
                            }
                            { const old = self.history; self.history = try list.toOwnedSlice(allocator); for (old) |item| { var mutable = item; mutable.deinit(allocator); } if (old.len != 0) allocator.free(old); }
                            continue;
                        }
                        if (std.mem.eql(u8, key, "by_name") or std.mem.eql(u8, key, "byName")) {
                            const object_value = switch (value) { .object => |map_object| map_object, else => return error.TypeMismatch };
                            var list: std.ArrayList(by_nameEntry) = .empty;
                            defer list.deinit(allocator);
                            errdefer for (list.items) |list_entry| { var old_value = list_entry.value; old_value.deinit(allocator); };
                            var map_it = object_value.iterator();
                            while (map_it.next()) |map_entry| {
                                try @This().appendOrReplaceMapEntry_by_name(allocator, &list, .{ .key = map_entry.key_ptr.*, .value = blk: { var nested = try pbz_generated_file.imports.imported_common_proto.demo.imports.common.Profile.jsonParseValueWithOptions(allocator, arena_allocator, map_entry.value_ptr.*, .{ .ignore_unknown_fields = options.ignore_unknown_fields }); errdefer nested.deinit(allocator); break :blk nested; } });
                            }
                            @This().deinitMap_by_name(allocator, &self.by_name);
                            try self.by_name.ensureUnusedCapacity(allocator, list.items.len);
                            for (list.items) |list_entry| try @This().putMapEntry_by_name(allocator, &self.by_name, list_entry);
                            continue;
                        }
                        if (std.mem.eql(u8, key, "chosen") or std.mem.eql(u8, key, "chosen")) {
                            self.selected = .{ .chosen = blk: { var nested = try pbz_generated_file.imports.imported_common_proto.demo.imports.common.Profile.jsonParseValueWithOptions(allocator, arena_allocator, value, .{ .ignore_unknown_fields = options.ignore_unknown_fields }); errdefer nested.deinit(allocator); break :blk nested; } };
                            continue;
                        }
                        if (std.mem.eql(u8, key, "fallback") or std.mem.eql(u8, key, "fallback")) {
                            self.selected = .{ .fallback = try @This().jsonString(value) };
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
                    if (self.primary) |nested| {
                        try writer.writeAll("primary {\n");
                        try nested.formatTextWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name });
                        try writer.writeAll("}\n");
                    }
                    for (self.history) |nested| {
                        try writer.writeAll("history {\n");
                        try nested.formatTextWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name });
                        try writer.writeAll("}\n");
                    }
                    { var map_it = self.by_name.iterator(); while (map_it.next()) |map_entry| {
                        const entry = by_nameEntry{ .key = map_entry.key_ptr.*, .value = map_entry.value_ptr.* };
                        try writer.writeAll("by_name {\n");
                        try writer.writeAll("key: "); if (!pbz.validateUtf8(entry.key)) return error.InvalidUtf8; try @This().textWriteQuotedBytes(entry.key, writer); try writer.writeByte('\n');
                        try writer.writeAll("value {\n");
                        try entry.value.formatTextWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name });
                        try writer.writeAll("}\n");
                        try writer.writeAll("}\n");
                    } }
                    switch (self.selected) {
                        .none => {},
                        .chosen => |value| {
                            try writer.writeAll("chosen {\n");
                            try value.formatTextWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name });
                            try writer.writeAll("}\n");
                        },
                        .fallback => |value| {
                            try writer.writeAll("fallback: "); try @This().textWriteQuotedBytes(value, writer); try writer.writeByte('\n');
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
                    var history_list: std.ArrayList(pbz_generated_file.imports.imported_common_proto.demo.imports.common.Profile) = .empty;
                    defer history_list.deinit(allocator);
                    errdefer for (history_list.items) |item| { var mutable = item; mutable.deinit(allocator); };
                    var by_name_list: std.ArrayList(by_nameEntry) = .empty;
                    defer by_name_list.deinit(allocator);
                    errdefer for (by_name_list.items) |list_entry| { var old_value = list_entry.value; old_value.deinit(allocator); };
                    var _unknown_fields_list: std.ArrayList([]const u8) = .empty;
                    errdefer { for (_unknown_fields_list.items) |raw| allocator.free(raw); _unknown_fields_list.deinit(allocator); }
                    const normalized_text = try @This().textNormalizeSeparators(allocator, text);
                    defer allocator.free(normalized_text);
                    var lines = std.mem.splitScalar(u8, normalized_text, '\n');
                    while (lines.next()) |raw_line| {
                        const line = @This().textCleanLine(raw_line);
                        if (line.len == 0) continue;
                        if (@This().textBlockField(line, "primary")) {
                            const block = try @This().textBlock(allocator, &lines);
                            defer allocator.free(block);
                            var nested = try pbz_generated_file.imports.imported_common_proto.demo.imports.common.Profile.parseTextWithOptions(allocator, block, .{ .ignore_unknown_fields = options.ignore_unknown_fields });
                            defer nested.deinit(allocator);
                            if (self.primary) |*existing| { try existing.mergeFrom(allocator, nested); } else { self.primary = try nested.cloneOwned(allocator); }
                            continue;
                        }
                        if (@This().textBlockField(line, "history")) {
                            const block = try @This().textBlock(allocator, &lines);
                            defer allocator.free(block);
                            var nested = try pbz_generated_file.imports.imported_common_proto.demo.imports.common.Profile.parseTextWithOptions(allocator, block, .{ .ignore_unknown_fields = options.ignore_unknown_fields });
                            defer nested.deinit(allocator);
                            history_list.append(allocator, try nested.cloneOwned(allocator)) catch |err| return err;
                            continue;
                        }
                        if (@This().textBlockField(line, "by_name") or @This().textBlockField(line, "byName")) {
                            var entry = by_nameEntry{};
                            errdefer entry.value.deinit(allocator);
                            const skip_entry = false;
                            while (lines.next()) |raw_entry_line| {
                                const entry_line = @This().textCleanLine(raw_entry_line);
                                if (entry_line.len == 0) continue;
                                if (std.mem.eql(u8, entry_line, "}") or std.mem.eql(u8, entry_line, ">")) break;
                                if (@This().textFieldValue(entry_line, "key")) |raw_key| { entry.key = blk: { const decoded = try @This().textUnquote(try self._pbzOwnedAllocator(allocator), raw_key); if (!pbz.validateUtf8(decoded)) return error.InvalidUtf8; break :blk decoded; }; continue; }
                                if (@This().textBlockField(entry_line, "value")) {
                                    const block = try @This().textBlock(allocator, &lines);
                                    defer allocator.free(block);
                                    var nested = try pbz_generated_file.imports.imported_common_proto.demo.imports.common.Profile.parseTextWithOptions(allocator, block, .{ .ignore_unknown_fields = options.ignore_unknown_fields });
                                    defer nested.deinit(allocator);
                                    entry.value.deinit(allocator);
                                    entry.value = try nested.cloneOwned(allocator);
                                    continue;
                                }
                                return error.UnknownField;
                            }
                            if (skip_entry) continue;
                            try @This().appendOrReplaceMapEntry_by_name(allocator, &by_name_list, entry);
                            continue;
                        }
                        if (@This().textBlockField(line, "chosen")) {
                            const block = try @This().textBlock(allocator, &lines);
                            defer allocator.free(block);
                            var nested = try pbz_generated_file.imports.imported_common_proto.demo.imports.common.Profile.parseTextWithOptions(allocator, block, .{ .ignore_unknown_fields = options.ignore_unknown_fields });
                            defer nested.deinit(allocator);
                            self.selected = .{ .chosen = try nested.cloneOwned(allocator) };
                            continue;
                        }
                        if (@This().textFieldValue(line, "fallback")) |raw_value| { self.selected = .{ .fallback = blk: { const decoded = try @This().textUnquote(try self._pbzOwnedAllocator(allocator), raw_value); if (!pbz.validateUtf8(decoded)) return error.InvalidUtf8; break :blk decoded; } }; continue; }
                        if (try @This().textUnknownField(allocator, line)) |raw| { errdefer allocator.free(raw); try _unknown_fields_list.append(allocator, raw); continue; }
                        if (try @This().textUnknownGroup(allocator, line, &lines)) |raw| { errdefer allocator.free(raw); try _unknown_fields_list.append(allocator, raw); continue; }
                        if (options.ignore_unknown_fields) continue;
                        return error.UnknownField;
                    }
                    self.history = if (history_list.items.len != 0 and history_list.items.len == history_list.capacity) history_list.toOwnedSliceAssert() else try history_list.toOwnedSlice(allocator);
                    self.by_name = .empty;
                    try self.by_name.ensureUnusedCapacity(allocator, by_name_list.items.len);
                    for (by_name_list.items) |entry| try @This().putMapEntry_by_name(allocator, &self.by_name, entry);
                    self._unknown_fields = try _unknown_fields_list.toOwnedSlice(allocator);
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

};
