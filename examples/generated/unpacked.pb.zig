const std = @import("std");
const pbz = @import("pbz");

pub const proto_package = "demo.unpacked";
pub const proto_syntax = "proto3";

pub const demo = struct {
    pub const unpacked = struct {
        pub const Kind = enum(i32) {
            KIND_UNKNOWN = 0,
            KIND_A = 1,
            KIND_B = 2,
            pub fn fromInt(value: i32) ?@This() {
                return switch (value) {
                    0 => .KIND_UNKNOWN,
                    1 => .KIND_A,
                    2 => .KIND_B,
                    else => null,
                };
            }
            pub fn toInt(self: @This()) i32 {
                return @intFromEnum(self);
            }
            pub fn protoName(self: @This()) []const u8 {
                return switch (self) {
                    .KIND_UNKNOWN => "KIND_UNKNOWN",
                    .KIND_A => "KIND_A",
                    .KIND_B => "KIND_B",
                };
            }
            pub fn fromName(name: []const u8) ?@This() {
                if (std.mem.eql(u8, name, "KIND_UNKNOWN")) return .KIND_UNKNOWN;
                if (std.mem.eql(u8, name, "KIND_A")) return .KIND_A;
                if (std.mem.eql(u8, name, "KIND_B")) return .KIND_B;
                return null;
            }
            pub fn jsonParse(value: std.json.Value) !@This() {
                return switch (value) {
                    .string => |name| fromName(name) orelse error.InvalidEnumValue,
                    .integer => |number| fromInt(std.math.cast(i32, number) orelse return error.Overflow) orelse error.InvalidEnumValue,
                    .number_string => |text| fromInt(try std.fmt.parseInt(i32, text, 10)) orelse error.InvalidEnumValue,
                    else => error.TypeMismatch,
                };
            }
            pub fn textParse(value: []const u8) !@This() {
                if (fromName(value)) |known| return known;
                return fromInt(try std.fmt.parseInt(i32, value, 10)) orelse error.InvalidEnumValue;
            }
            pub fn textFormat(self: @This(), writer: *std.Io.Writer) !void {
                try writer.writeAll(self.protoName());
            }
            pub fn jsonStringify(self: @This(), writer: *std.Io.Writer) !void {
                try std.json.Stringify.value(self.protoName(), .{}, writer);
            }
        };

        pub const Unpacked = struct {
            pub const values_number = 1;
            pub const flags_number = 2;
            pub const kinds_number = 3;

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
                pub const is_packed = false;
            };
            pub const flags_field = struct {
                pub const number = 2;
                pub const name = "flags";
                pub const json_name = "flags";
                pub const cardinality = "repeated";
                pub const kind = "bool";
                pub const type_name = "bool";
                pub const zig_type = "[]const bool";
                pub const has_type_ref = false;
                pub const type_ref = void;
                pub const has_enum_ref = false;
                pub const enum_ref = void;
                pub const has_presence = false;
                pub const default_value = "";
                pub const is_packed = false;
            };
            pub const kinds_field = struct {
                pub const number = 3;
                pub const name = "kinds";
                pub const json_name = "kinds";
                pub const cardinality = "repeated";
                pub const kind = "enum";
                pub const type_name = "demo.unpacked.Kind";
                pub const zig_type = "[]const i32";
                pub const has_type_ref = false;
                pub const type_ref = void;
                pub const has_enum_ref = true;
                pub const enum_ref = Kind;
                pub const has_presence = false;
                pub const default_value = "";
                pub const is_packed = false;
            };

            values: []const i32 = &.{},
            flags: []const bool = &.{},
            kinds: []const i32 = &.{},
            _json_arena: ?*std.heap.ArenaAllocator = null,
            _unknown_fields: []const []const u8 = &.{},

            pub fn init() @This() {
                return .{};
            }

            pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
                allocator.free(self.values);
                allocator.free(self.flags);
                allocator.free(self.kinds);
                pbz.wire.freeRawFields(allocator, self._unknown_fields);
                if (self._json_arena) |arena| { const child_allocator = arena.child_allocator; arena.deinit(); child_allocator.destroy(arena); }
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
                if (self.flags.len != 0) {
                    const cloned = try allocator.alloc(bool, self.flags.len);
                    for (self.flags, 0..) |item, i| cloned[i] = item;
                    out.flags = cloned;
                }
                if (self.kinds.len != 0) {
                    const cloned = try allocator.alloc(i32, self.kinds.len);
                    for (self.kinds, 0..) |item, i| cloned[i] = item;
                    out.kinds = cloned;
                }
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
                if (other.flags.len != 0) {
                    const old = self.flags;
                    const merged = try allocator.alloc(bool, old.len + other.flags.len);
                    @memcpy(merged[0..old.len], old);
                    @memcpy(merged[old.len..], other.flags);
                    self.flags = merged;
                    if (old.len != 0) allocator.free(old);
                }
                if (other.kinds.len != 0) {
                    const old = self.kinds;
                    const merged = try allocator.alloc(i32, old.len + other.kinds.len);
                    @memcpy(merged[0..old.len], old);
                    @memcpy(merged[old.len..], other.kinds);
                    self.kinds = merged;
                    if (old.len != 0) allocator.free(old);
                }
                try pbz.wire.appendRawFieldsClone(allocator, &self._unknown_fields, other._unknown_fields);
            }

            pub fn encodedSize(self: @This()) usize {
                var size: usize = 0;
                for (self.values) |item| size += 1 + pbz.wire.encodedVarintSize(@as(u64, @bitCast(@as(i64, item))));
                for (self.flags) |item| size += 1 + (if (item) @as(usize, 1) else @as(usize, 1));
                for (self.kinds) |item| size += 1 + pbz.wire.encodedVarintSize(@as(u64, @bitCast(@as(i64, item))));
                for (self._unknown_fields) |raw| size += raw.len;
                return size;
            }

            pub fn writeTo(self: @This(), w: *pbz.Writer) !void {
                for (self.values) |item| try w.writeInt32(1, item);
                for (self.flags) |item| try w.writeBool(2, item);
                for (self.kinds) |item| try w.writeInt32(3, item);
                for (self._unknown_fields) |raw| try w.appendSlice(raw);
            }

            pub fn writeToAssumeCapacity(self: @This(), w: *pbz.Writer) !void {
                for (self.values) |item| w.writeInt32AssumeCapacity(1, item);
                for (self.flags) |item| w.writeBoolAssumeCapacity(2, item);
                for (self.kinds) |item| w.writeInt32AssumeCapacity(3, item);
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
                var w = pbz.Writer.initBuffer(std.heap.page_allocator, buffer);
                try self.writeToAssumeCapacity(&w);
                return buffer[0..w.slice().len];
            }

            pub fn encodeIntoAssumeCapacityTrustedUtf8(self: @This(), buffer: []u8) ![]u8 {
                return try self.encodeIntoAssumeCapacity(buffer);
            }

            pub fn writeDeterministicTo(self: @This(), allocator: std.mem.Allocator, w: *pbz.Writer) !void {
                for (self.values) |item| try w.writeInt32(1, item);
                for (self.flags) |item| try w.writeBool(2, item);
                for (self.kinds) |item| try w.writeInt32(3, item);
                try pbz.wire.writeRawFieldsDeterministic(allocator, self._unknown_fields, w);
            }

            pub fn writeDeterministicToAssumeCapacity(self: @This(), allocator: std.mem.Allocator, w: *pbz.Writer) !void {
                for (self.values) |item| w.writeInt32AssumeCapacity(1, item);
                for (self.flags) |item| w.writeBoolAssumeCapacity(2, item);
                for (self.kinds) |item| w.writeInt32AssumeCapacity(3, item);
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
                var values_list: std.ArrayList(i32) = .empty;
                defer values_list.deinit(allocator);
                var flags_list: std.ArrayList(bool) = .empty;
                defer flags_list.deinit(allocator);
                var kinds_list: std.ArrayList(i32) = .empty;
                defer kinds_list.deinit(allocator);
                var _unknown_fields_list: std.ArrayList([]const u8) = .empty;
                errdefer pbz.wire.deinitRawFieldList(allocator, &_unknown_fields_list);
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
                        2 => {
                            if (tag.wire_type == .length_delimited) {
                                const payload = try r.readBytes();
                                try pbz.wire.appendPackedBool(allocator, &flags_list, payload);
                            } else {
                                try flags_list.append(allocator, try r.readBool());
                            }
                        },
                        3 => {
                            if (tag.wire_type == .length_delimited) {
                                const payload = try r.readBytes();
                                try pbz.wire.appendPackedInt32(allocator, &kinds_list, payload);
                            } else {
                                { const value = try r.readInt32(); try kinds_list.append(allocator, value); }
                            }
                        },
                        else => try pbz.wire.appendSkippedRawField(allocator, &_unknown_fields_list, r, r.lastTagStart(), tag),
                    }
                }
                self.values = if (values_list.items.len != 0 and values_list.items.len == values_list.capacity) values_list.toOwnedSliceAssert() else try values_list.toOwnedSlice(allocator);
                self.flags = if (flags_list.items.len != 0 and flags_list.items.len == flags_list.capacity) flags_list.toOwnedSliceAssert() else try flags_list.toOwnedSlice(allocator);
                self.kinds = if (kinds_list.items.len != 0 and kinds_list.items.len == kinds_list.capacity) kinds_list.toOwnedSliceAssert() else try kinds_list.toOwnedSlice(allocator);
                self._unknown_fields = try pbz.wire.rawFieldListToOwnedSlice(allocator, &_unknown_fields_list);
                return self;
            }

            pub fn decodeReuse(self: *@This(), allocator: std.mem.Allocator, bytes: []const u8) !void {
                var values_list: std.ArrayList(i32) = std.ArrayList(i32).fromOwnedSlice(@constCast(self.values));
                values_list.clearRetainingCapacity();
                self.values = &.{};
                errdefer values_list.deinit(allocator);
                var flags_list: std.ArrayList(bool) = std.ArrayList(bool).fromOwnedSlice(@constCast(self.flags));
                flags_list.clearRetainingCapacity();
                self.flags = &.{};
                errdefer flags_list.deinit(allocator);
                var kinds_list: std.ArrayList(i32) = std.ArrayList(i32).fromOwnedSlice(@constCast(self.kinds));
                kinds_list.clearRetainingCapacity();
                self.kinds = &.{};
                errdefer kinds_list.deinit(allocator);
                pbz.wire.clearRawFields(allocator, &self._unknown_fields);
                if (self._json_arena) |arena| { const child_allocator = arena.child_allocator; arena.deinit(); child_allocator.destroy(arena); self._json_arena = null; }
                errdefer self.deinit(allocator);
                var _unknown_fields_list: std.ArrayList([]const u8) = .empty;
                errdefer pbz.wire.deinitRawFieldList(allocator, &_unknown_fields_list);
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
                        2 => {
                            if (tag.wire_type == .length_delimited) {
                                const payload = try r.readBytes();
                                try pbz.wire.appendPackedBool(allocator, &flags_list, payload);
                            } else {
                                try flags_list.append(allocator, try r.readBool());
                            }
                        },
                        3 => {
                            if (tag.wire_type == .length_delimited) {
                                const payload = try r.readBytes();
                                try pbz.wire.appendPackedInt32(allocator, &kinds_list, payload);
                            } else {
                                { const value = try r.readInt32(); try kinds_list.append(allocator, value); }
                            }
                        },
                        else => try pbz.wire.appendSkippedRawField(allocator, &_unknown_fields_list, &r, r.lastTagStart(), tag),
                    }
                }
                self.values = if (values_list.items.len != 0 and values_list.items.len == values_list.capacity) values_list.toOwnedSliceAssert() else try values_list.toOwnedSlice(allocator);
                self.flags = if (flags_list.items.len != 0 and flags_list.items.len == flags_list.capacity) flags_list.toOwnedSliceAssert() else try flags_list.toOwnedSlice(allocator);
                self.kinds = if (kinds_list.items.len != 0 and kinds_list.items.len == kinds_list.capacity) kinds_list.toOwnedSliceAssert() else try kinds_list.toOwnedSlice(allocator);
                self._unknown_fields = try pbz.wire.rawFieldListToOwnedSlice(allocator, &_unknown_fields_list);
            }

            /// Trusted same-schema hot path that reuses existing repeated buffers.
            /// The caller must pre-size those buffers for the decoded element counts.
            /// Unknown or schema-mismatched fields are rejected instead of preserved.
            pub fn decodeKnownReuse(self: *@This(), allocator: std.mem.Allocator, bytes: []const u8) !void {
                const values_buffer = @constCast(self.values);
                var values_len: usize = 0;
                const flags_buffer = @constCast(self.flags);
                var flags_len: usize = 0;
                const kinds_buffer = @constCast(self.kinds);
                var kinds_len: usize = 0;
                pbz.wire.clearRawFields(allocator, &self._unknown_fields);
                if (self._json_arena) |arena| { const child_allocator = arena.child_allocator; arena.deinit(); child_allocator.destroy(arena); self._json_arena = null; }
                var r = pbz.Reader.init(bytes);
                while (!r.eof()) {
                    const raw_tag_start = r.position();
                    const first_tag_byte = try r.readByte();
                    const raw_tag: u64 = if (first_tag_byte < 0x80) first_tag_byte else blk: { r.index = raw_tag_start; break :blk try r.readVarint(); };
                    switch (raw_tag) {
                        10 => {
                            const payload = try r.readBytes();
                            var payload_index: usize = 0;
                            while (payload_index < payload.len) {
                                values_buffer[values_len] = try pbz.wire.readInt32At(payload, &payload_index);
                                values_len += 1;
                            }
                        },
                        8 => {
                            values_buffer[values_len] = try r.readInt32();
                            values_len += 1;
                        },
                        18 => {
                            const payload = try r.readBytes();
                            for (payload) |byte| {
                                flags_buffer[flags_len] = byte != 0;
                                flags_len += 1;
                            }
                        },
                        16 => {
                            flags_buffer[flags_len] = try r.readBool();
                            flags_len += 1;
                        },
                        26 => {
                            const payload = try r.readBytes();
                            if (pbz.wire.packedEnumAllSingleByte(payload)) {
                                for (payload) |byte| {
                                    kinds_buffer[kinds_len] = @intCast(byte);
                                    kinds_len += 1;
                                }
                            } else {
                            var payload_index: usize = 0;
                            while (payload_index < payload.len) {
                                kinds_buffer[kinds_len] = @truncate(@as(i64, @bitCast(try pbz.wire.readVarintAt(payload, &payload_index))));
                                kinds_len += 1;
                            }
                            }
                        },
                        24 => {
                            kinds_buffer[kinds_len] = try r.readInt32();
                            kinds_len += 1;
                        },
                        else => return error.InvalidWireType,
                    }
                }
                if (values_len != values_buffer.len) return error.InvalidWireType;
                self.values = values_buffer;
                if (flags_len != flags_buffer.len) return error.InvalidWireType;
                self.flags = flags_buffer;
                if (kinds_len != kinds_buffer.len) return error.InvalidWireType;
                self.kinds = kinds_buffer;
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
                    try writer.writeAll(if (first) "\"values\":" else ",\"values\":"); first = false;
                    try writer.writeAll("[");
                    for (self.values, 0..) |item, i| { if (i != 0) try writer.writeAll(","); try writer.print("{d}", .{item}); }
                    try writer.writeAll("]");
                }
                if (self.flags.len != 0 or options.always_print_primitive_fields) {
                    try writer.writeAll(if (first) "\"flags\":" else ",\"flags\":"); first = false;
                    try writer.writeAll("[");
                    for (self.flags, 0..) |item, i| { if (i != 0) try writer.writeAll(","); try writer.writeAll(if (item) "true" else "false"); }
                    try writer.writeAll("]");
                }
                if (self.kinds.len != 0 or options.always_print_primitive_fields) {
                    try writer.writeAll(if (first) "\"kinds\":" else ",\"kinds\":"); first = false;
                    try writer.writeAll("[");
                    for (self.kinds, 0..) |item, i| { if (i != 0) try writer.writeAll(","); try @This().jsonWriteEnum(writer, item, &.{"KIND_UNKNOWN", "KIND_A", "KIND_B"}, &.{0, 1, 2}, options.enum_as_name); }
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
                        if (std.mem.eql(u8, key, "values")) {
                            const old = self.values; self.values = &.{}; if (old.len != 0) allocator.free(old);
                            continue;
                        }
                        if (std.mem.eql(u8, key, "flags")) {
                            const old = self.flags; self.flags = &.{}; if (old.len != 0) allocator.free(old);
                            continue;
                        }
                        if (std.mem.eql(u8, key, "kinds")) {
                            const old = self.kinds; self.kinds = &.{}; if (old.len != 0) allocator.free(old);
                            continue;
                        }
                        if (options.ignore_unknown_fields) continue;
                        return error.UnknownField;
                    }
                    if (std.mem.eql(u8, key, "values")) {
                        const array = switch (value) { .array => |array| array, else => return error.TypeMismatch };
                        var list: std.ArrayList(i32) = .empty;
                        errdefer list.deinit(allocator);
                        for (array.items) |item| try list.append(allocator, try @This().jsonInt(i32, item));
                        self.values = blk: { const old = self.values; const owned = try list.toOwnedSlice(allocator); if (old.len != 0) allocator.free(old); break :blk owned; };
                        continue;
                    }
                    if (std.mem.eql(u8, key, "flags")) {
                        const array = switch (value) { .array => |array| array, else => return error.TypeMismatch };
                        var list: std.ArrayList(bool) = .empty;
                        errdefer list.deinit(allocator);
                        for (array.items) |item| try list.append(allocator, try @This().jsonBool(item));
                        self.flags = blk: { const old = self.flags; const owned = try list.toOwnedSlice(allocator); if (old.len != 0) allocator.free(old); break :blk owned; };
                        continue;
                    }
                    if (std.mem.eql(u8, key, "kinds")) {
                        const array = switch (value) { .array => |array| array, else => return error.TypeMismatch };
                        var list: std.ArrayList(i32) = .empty;
                        errdefer list.deinit(allocator);
                        for (array.items) |item| {
                            const parsed_enum = @This().jsonEnum(item, &.{"KIND_UNKNOWN", "KIND_A", "KIND_B"}, &.{0, 1, 2}, false) catch |err| { if (options.ignore_unknown_fields) continue; return err; };
                            try list.append(allocator, parsed_enum);
                        }
                        self.kinds = blk: { const old = self.kinds; const owned = try list.toOwnedSlice(allocator); if (old.len != 0) allocator.free(old); break :blk owned; };
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
                for (self.values) |value| { try writer.writeAll("values: "); try writer.print("{d}", .{value}); try writer.writeByte('\n'); }
                for (self.flags) |value| { try writer.writeAll("flags: "); try writer.writeAll(if (value) "true" else "false"); try writer.writeByte('\n'); }
                for (self.kinds) |value| { try writer.writeAll("kinds: "); try @This().textWriteEnum(writer, value, &.{"KIND_UNKNOWN", "KIND_A", "KIND_B"}, &.{0, 1, 2}, options.enum_as_name); try writer.writeByte('\n'); }
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
                var values_list: std.ArrayList(i32) = .empty;
                defer values_list.deinit(allocator);
                var flags_list: std.ArrayList(bool) = .empty;
                defer flags_list.deinit(allocator);
                var kinds_list: std.ArrayList(i32) = .empty;
                defer kinds_list.deinit(allocator);
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
                    if (@This().textFieldValue(line, "values")) |raw_value| {
                        try values_list.append(allocator, try @This().textInt(i32, raw_value));
                        continue;
                    }
                    if (@This().textFieldValue(line, "flags")) |raw_value| {
                        try flags_list.append(allocator, try @This().textBool(raw_value));
                        continue;
                    }
                    if (@This().textFieldValue(line, "kinds")) |raw_value| {
                        const parsed_enum = @This().textEnum(raw_value, &.{"KIND_UNKNOWN", "KIND_A", "KIND_B"}, &.{0, 1, 2}, false) catch |err| { if (options.ignore_unknown_fields) { continue; } return err; };
                        try kinds_list.append(allocator, parsed_enum);
                        continue;
                    }
                    if (try @This().textUnknownField(allocator, line)) |raw| { try pbz.wire.appendOwnedRawField(allocator, &_unknown_fields_list, raw); continue; }
                    if (try @This().textUnknownGroup(allocator, line, &lines, text_has_comments)) |raw| { try pbz.wire.appendOwnedRawField(allocator, &_unknown_fields_list, raw); continue; }
                    if (options.ignore_unknown_fields) continue;
                    return error.UnknownField;
                }
                self.values = if (values_list.items.len != 0 and values_list.items.len == values_list.capacity) values_list.toOwnedSliceAssert() else try values_list.toOwnedSlice(allocator);
                self.flags = if (flags_list.items.len != 0 and flags_list.items.len == flags_list.capacity) flags_list.toOwnedSliceAssert() else try flags_list.toOwnedSlice(allocator);
                self.kinds = if (kinds_list.items.len != 0 and kinds_list.items.len == kinds_list.capacity) kinds_list.toOwnedSliceAssert() else try kinds_list.toOwnedSlice(allocator);
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
