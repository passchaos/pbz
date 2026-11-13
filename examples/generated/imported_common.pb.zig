const std = @import("std");
const pbz = @import("pbz");

pub const proto_package = "demo.imports.common";
pub const proto_syntax = "proto3";
const pbz_generated_file = @This();

/// Serialized google.protobuf.FileDescriptorProto for this generated file.
/// Use decodeFileDescriptor() to build registry/reflection metadata.
pub const file_descriptor_proto = [_]u8{
    0x0a, 0x15, 0x69, 0x6d, 0x70, 0x6f, 0x72, 0x74, 0x65, 0x64, 0x5f, 0x63,
    0x6f, 0x6d, 0x6d, 0x6f, 0x6e, 0x2e, 0x70, 0x72, 0x6f, 0x74, 0x6f, 0x12,
    0x13, 0x64, 0x65, 0x6d, 0x6f, 0x2e, 0x69, 0x6d, 0x70, 0x6f, 0x72, 0x74,
    0x73, 0x2e, 0x63, 0x6f, 0x6d, 0x6d, 0x6f, 0x6e, 0x22, 0x2d, 0x0a, 0x07,
    0x50, 0x72, 0x6f, 0x66, 0x69, 0x6c, 0x65, 0x12, 0x0e, 0x0a, 0x02, 0x69,
    0x64, 0x18, 0x01, 0x20, 0x01, 0x28, 0x05, 0x52, 0x02, 0x69, 0x64, 0x12,
    0x12, 0x0a, 0x04, 0x6e, 0x61, 0x6d, 0x65, 0x18, 0x02, 0x20, 0x01, 0x28,
    0x09, 0x52, 0x04, 0x6e, 0x61, 0x6d, 0x65, 0x62, 0x06, 0x70, 0x72, 0x6f,
    0x74, 0x6f, 0x33,
};
/// Decode the embedded FileDescriptorProto. The caller owns the result and
/// must call deinit() on it.
pub fn decodeFileDescriptor(allocator: std.mem.Allocator) !pbz.schema.FileDescriptor {
    return pbz.decodeFileDescriptorProto(allocator, &file_descriptor_proto);
}

pub const demo = struct {
    pub const imports = struct {
        pub const common = struct {
            pub const Profile = struct {
                pub const id_number = 1;
                pub const name_number = 2;

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

                /// Look up this message's descriptor in a decoded file descriptor.
                pub fn descriptor(file: *const pbz.schema.FileDescriptor) ?*const pbz.schema.MessageDescriptor {
                    return file.findMessageDeep(".demo.imports.common.Profile");
                }

                /// Convert to a dynamic message via the wire format for reflection workflows.
                pub fn toDynamic(self: @This(), allocator: std.mem.Allocator, file: *const pbz.schema.FileDescriptor) !pbz.DynamicMessage {
                    const message_descriptor = @This().descriptor(file) orelse return error.TypeMismatch;
                    var writer = pbz.Writer.init(allocator);
                    defer writer.deinit();
                    try self.writeTo(&writer);
                    var message = pbz.DynamicMessage.init(allocator, message_descriptor);
                    errdefer message.deinit();
                    try message.decode(file, writer.slice());
                    return message;
                }

                /// Build from a dynamic message via the wire format. `file` must be the
                /// same decoded descriptor used to create `message`.
                pub fn fromDynamic(allocator: std.mem.Allocator, file: *const pbz.schema.FileDescriptor, message: *const pbz.DynamicMessage) !@This() {
                    const message_descriptor = @This().descriptor(file) orelse return error.TypeMismatch;
                    if (message.descriptor != message_descriptor) return error.TypeMismatch;
                    var writer = pbz.Writer.init(allocator);
                    defer writer.deinit();
                    try message.encode(file, &writer);
                    return try @This().decodeOwned(allocator, writer.slice());
                }

                /// Full TextFormat parser backed by the dynamic parser. parseText falls
                /// back to this parser when the fast line-oriented path cannot parse.
                pub fn parseTextConformant(allocator: std.mem.Allocator, text: []const u8) !@This() {
                    return try @This().parseTextConformantWithOptions(allocator, text, .{});
                }

                /// Full JSON parser backed by the dynamic parser.
                pub fn jsonParseConformant(allocator: std.mem.Allocator, text: []const u8) !@This() {
                    var file = try pbz_generated_file.decodeFileDescriptor(allocator);
                    defer file.deinit();
                    const message_descriptor = @This().descriptor(&file) orelse return error.TypeMismatch;
                    var dynamic = try pbz.json.parseAlloc(allocator, &file, message_descriptor, text, .{});
                    defer dynamic.deinit();
                    return try @This().fromDynamic(allocator, &file, &dynamic);
                }

                id: i32 = 0,
                name: []const u8 = "",
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

                /// Release owned storage and reset to the protobuf default value.
                pub fn clear(self: *@This(), allocator: std.mem.Allocator) void {
                    self.deinit(allocator);
                    self.* = @This().init();
                }

                pub fn cloneOwned(self: @This(), allocator: std.mem.Allocator) anyerror!@This() {
                    var out = @This().init();
                    errdefer out.deinit(allocator);
                    const owned_allocator = try out._pbzOwnedAllocator(allocator);
                    out.id = self.id;
                    out.name = try owned_allocator.dupe(u8, self.name);
                    out._unknown_fields = try pbz.wire.cloneRawFields(allocator, self._unknown_fields);
                    return out;
                }

                /// Take ownership of borrowed string/bytes payloads after decode.
                /// Owned payloads, including nested message payloads, live in this message's arena.
                pub fn adoptOwned(self: *@This(), allocator: std.mem.Allocator) anyerror!void {
                    const _pbz_owned_allocator = try self._pbzOwnedAllocator(allocator);
                    try self.adoptOwnedInto(allocator, _pbz_owned_allocator);
                }
                pub fn adoptOwnedInto(self: *@This(), allocator: std.mem.Allocator, _pbz_owned_allocator: std.mem.Allocator) anyerror!void {
                    _ = &self;
                    _ = &allocator;
                    _ = &_pbz_owned_allocator;
                    var _pbz_owned_total: usize = 0;
                    _pbz_owned_total += self.name.len;
                    var _pbz_owned_block = pbz.wire.OwnedBlock.init(if (_pbz_owned_total == 0) &.{} else try _pbz_owned_allocator.alloc(u8, _pbz_owned_total));
                    if (self.name.len != 0) self.name = _pbz_owned_block.take(self.name);
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


                pub fn nameFieldView(bytes: []const u8) !?[]const u8 {
                    return try pbz.wire.bytesFieldView(bytes, 2);
                }

                pub fn nameFieldSlices(header: *[20]u8, value: []const u8) !pbz.wire.BorrowedFieldSlices {
                    return pbz.wire.lengthDelimitedFieldSlicesAssumeValid(header, 2, value);
                }

                pub fn nameStringView(bytes: []const u8) !?[]const u8 {
                    return try nameFieldView(bytes);
                }

                pub fn nameStringSlices(header: *[20]u8, value: []const u8) !pbz.wire.BorrowedFieldSlices {
                    return try nameFieldSlices(header, value);
                }


                // no same-file extension accessors

                /// Merge other into self. String/bytes payloads, raw message payloads,
                /// and map keys/values are deep-copied, so other remains independently valid.
                pub fn mergeFrom(self: *@This(), allocator: std.mem.Allocator, other: @This()) anyerror!void {
                    const _pbz_owned_allocator = try self._pbzOwnedAllocator(allocator);
                    if (other.id != 0) self.id = other.id;
                    if (other.name.len != 0) self.name = try pbz.wire.dupeBytes(_pbz_owned_allocator,other.name);
                    try pbz.wire.appendRawFieldsClone(allocator, &self._unknown_fields, other._unknown_fields);
                }

                pub fn encodedSize(self: @This()) usize {
                    var size: usize = 0;
                    if (self.id != 0) size += 1 + pbz.wire.encodedVarintSize(@as(u64, @bitCast(@as(i64, self.id))));
                    if (self.name.len != 0) size += 1 + pbz.wire.encodedVarintSize(self.name.len) + self.name.len;
                    for (self._unknown_fields) |raw| size += raw.len;
                    return size;
                }

                pub fn writeTo(self: @This(), w: *pbz.Writer) anyerror!void {
                    if (self.id != 0) try w.writeInt32(1, self.id);
                    if (self.name.len != 0) { if (!pbz.validateUtf8(self.name)) return error.InvalidUtf8; try w.writeString(2, self.name); }
                    for (self._unknown_fields) |raw| try w.appendSlice(raw);
                }

                pub fn writeToAssumeCapacity(self: @This(), w: *pbz.Writer) anyerror!void {
                    if (self.id != 0) w.writeInt32AssumeCapacity(1, self.id);
                    if (self.name.len != 0) { if (!pbz.validateUtf8(self.name)) return error.InvalidUtf8; w.writeStringAssumeCapacity(2, self.name); }
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
                    if (self.id != 0) { buffer[index] = 8; index += 1; pbz.wire.writeDirectScalarVarintToSlice(buffer, &index, @as(u64, @bitCast(@as(i64, self.id)))); }
                    if (self.name.len != 0) { if (!pbz.validateUtf8(self.name)) return error.InvalidUtf8; buffer[index] = 18; index += 1; pbz.wire.writeVarintToSlice(buffer, &index, self.name.len); pbz.wire.copyBytes(buffer[index..][0..self.name.len], self.name); index += self.name.len; }
                    for (self._unknown_fields) |raw| { @memcpy(buffer[index..][0..raw.len], raw); index += raw.len; }
                    return buffer[0..index];
                }

                /// Like encodeIntoAssumeCapacity, but skips UTF-8 validation. The caller
                /// must guarantee that all string fields contain valid UTF-8.
                pub fn encodeIntoAssumeCapacityTrustedUtf8(self: @This(), buffer: []u8) ![]u8 {
                    var index: usize = 0;
                    if (self.id != 0) { buffer[index] = 8; index += 1; pbz.wire.writeDirectScalarVarintToSlice(buffer, &index, @as(u64, @bitCast(@as(i64, self.id)))); }
                    if (self.name.len != 0) { buffer[index] = 18; index += 1; pbz.wire.writeVarintToSlice(buffer, &index, self.name.len); pbz.wire.copyBytes(buffer[index..][0..self.name.len], self.name); index += self.name.len; }
                    for (self._unknown_fields) |raw| { @memcpy(buffer[index..][0..raw.len], raw); index += raw.len; }
                    return buffer[0..index];
                }

                pub fn writeDeterministicTo(self: @This(), allocator: std.mem.Allocator, w: *pbz.Writer) anyerror!void {
                    if (self.id != 0) try w.writeInt32(1, self.id);
                    if (self.name.len != 0) { if (!pbz.validateUtf8(self.name)) return error.InvalidUtf8; try w.writeString(2, self.name); }
                    try pbz.wire.writeRawFieldsDeterministic(allocator, self._unknown_fields, w);
                }

                pub fn writeDeterministicToAssumeCapacity(self: @This(), allocator: std.mem.Allocator, w: *pbz.Writer) anyerror!void {
                    if (self.id != 0) w.writeInt32AssumeCapacity(1, self.id);
                    if (self.name.len != 0) { if (!pbz.validateUtf8(self.name)) return error.InvalidUtf8; w.writeStringAssumeCapacity(2, self.name); }
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

                /// Decode from wire bytes. String/bytes fields borrow the input slice;
                /// use decodeOwned when the decoded message must outlive the input.
                pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) !@This() {
                    var r = pbz.Reader.init(bytes);
                    return try @This().decodeFromReader(allocator, &r);
                }

                /// Decode from an existing reader. String/bytes fields borrow the reader input.
                pub fn decodeFromReader(allocator: std.mem.Allocator, r: *pbz.Reader) anyerror!@This() {
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
                            18 => { self.name = try r.readBytes(); if (!pbz.validateUtf8(self.name)) return error.InvalidUtf8; },
                            else => try pbz.wire.appendSkippedRawField(allocator, &_unknown_fields_list, r, raw_tag_start, try pbz.wire.Tag.decode(raw_tag)),
                        }
                    }
                    self._unknown_fields = try pbz.wire.rawFieldListToOwnedSlice(allocator, &_unknown_fields_list);
                    return self;
                }

                /// Decode into an existing message, reusing repeated/map storage.
                /// String/bytes fields still borrow the input slice.
                pub fn decodeReuse(self: *@This(), allocator: std.mem.Allocator, bytes: []const u8) !void {
                    pbz.wire.clearRawFields(allocator, &self._unknown_fields);
                    if (self._json_arena) |arena| { _ = arena.reset(.retain_capacity); }
                    self.id = 0;
                    self.name = "";
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
                            18 => { self.name = try r.readBytes(); if (!pbz.validateUtf8(self.name)) return error.InvalidUtf8; },
                            else => try pbz.wire.appendSkippedRawField(allocator, &_unknown_fields_list, &r, raw_tag_start, try pbz.wire.Tag.decode(raw_tag)),
                        }
                    }
                    self._unknown_fields = try pbz.wire.rawFieldListToOwnedSlice(allocator, &_unknown_fields_list);
                }

                /// Decode into an existing message, reusing arrays/maps and retained owned string storage.
                pub fn decodeOwnedReuse(self: *@This(), allocator: std.mem.Allocator, bytes: []const u8) !void {
                    errdefer self.deinit(allocator);
                    try self.decodeReuse(allocator, bytes);
                    try self.adoptOwned(allocator);
                }

                pub fn decodeOwned(allocator: std.mem.Allocator, bytes: []const u8) !@This() {
                    var self = try @This().decode(allocator, bytes);
                    errdefer self.deinit(allocator);
                    try self.adoptOwned(allocator);
                    return self;
                }

                /// Decode and validate required fields. String/bytes fields borrow the input slice.
                pub fn decodeInitialized(allocator: std.mem.Allocator, bytes: []const u8) !@This() {
                    var self = try @This().decode(allocator, bytes);
                    errdefer self.deinit(allocator);
                    try self.validateRequiredRecursive(allocator);
                    return self;
                }

                /// Decode, deep-copy, and validate required fields.
                pub fn decodeOwnedInitialized(allocator: std.mem.Allocator, bytes: []const u8) !@This() {
                    var self = try @This().decodeOwned(allocator, bytes);
                    errdefer self.deinit(allocator);
                    try self.validateRequiredRecursive(allocator);
                    return self;
                }

                pub fn missingRequiredFieldName(self: @This()) ?[]const u8 {
                    _ = &self;
                    return null;
                }

                pub fn missingRequiredFieldPath(self: @This(), allocator: std.mem.Allocator) anyerror!?[]u8 {
                    _ = &self; _ = &allocator;
                    return null;
                }

                pub fn validateRequired(self: @This()) !void {
                    if (self.missingRequiredFieldName() != null) return error.MissingRequiredField;
                }

                pub fn validateRequiredRecursive(self: @This(), allocator: std.mem.Allocator) anyerror!void {
                    try self.validateRequired();
                    _ = &allocator;
                }

                pub const JsonStringifyOptions = struct { enum_as_name: bool = true, preserve_proto_field_names: bool = false, always_print_primitive_fields: bool = false };

                pub fn jsonStringifyAlloc(self: @This(), allocator: std.mem.Allocator) ![]u8 {
                    return try self.jsonStringifyAllocWithOptions(allocator, .{});
                }

                pub fn jsonStringifyAllocWithOptions(self: @This(), allocator: std.mem.Allocator, options: @This().JsonStringifyOptions) ![]u8 {
                    var out: std.Io.Writer.Allocating = try std.Io.Writer.Allocating.initCapacity(allocator, 512);
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

                pub fn jsonStringifyWithOptions(self: @This(), allocator: std.mem.Allocator, writer: *std.Io.Writer, options: @This().JsonStringifyOptions) anyerror!void {
                    _ = &allocator;
                    _ = &options;
                    try writer.writeAll("{");
                    var first = true;
                    if (self.id != 0 or options.always_print_primitive_fields) {
                        try writer.writeAll(if (first) "\"id\":" else ",\"id\":"); first = false;
                        const value = self.id;
                        try writer.print("{d}", .{value});
                    }
                    if (self.name.len != 0 or options.always_print_primitive_fields) {
                        try writer.writeAll(if (first) "\"name\":" else ",\"name\":"); first = false;
                        const value = self.name;
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
                    const owned_text = try arena.allocator().dupe(u8, text);
                    const parsed = try pbz.json.parseValueTree(arena.allocator(), owned_text, .{});
                    var self = try @This().jsonParseValueWithOptions(allocator, arena.allocator(), parsed, options);
                    self._json_arena = arena;
                    return self;
                }

                /// Parse a pre-parsed JSON subtree without serializing it back to text first.
                /// The caller must keep `arena_allocator` alive for decoded bytes and keep
                /// the text backing `json_value` alive for borrowed string slices.
                pub fn jsonParseValue(allocator: std.mem.Allocator, arena_allocator: std.mem.Allocator, json_value: pbz.json.Value) !@This() {
                    return try @This().jsonParseValueWithOptions(allocator, arena_allocator, json_value, .{});
                }

                /// Option-bearing variant of jsonParseValue for generated nested-message parsers.
                pub fn jsonParseValueWithOptions(allocator: std.mem.Allocator, arena_allocator: std.mem.Allocator, json_value: pbz.json.Value, options: @This().JsonParseOptions) anyerror!@This() {
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

                fn jsonFillFromValue(self: *@This(), allocator: std.mem.Allocator, arena_allocator: std.mem.Allocator, json_value: pbz.json.Value, options: @This().JsonParseOptions) !void {
                    _ = &self;
                    _ = &allocator;
                    _ = &arena_allocator;
                    const object = switch (json_value) { .object => |object| object, else => return error.TypeMismatch };
                    var _pbz_seen = std.StaticBitSet(2).initEmpty();
                    _ = &_pbz_seen;
                    var it = object.iterator();
                    while (it.next()) |entry| {
                        const key = entry.key;
                        const value = entry.value;
                        if (value == .null) {
                            if (key.len == 2 and std.mem.eql(u8, key, "id")) {
                                if (_pbz_seen.isSet(0)) return error.DuplicateField;
                                _pbz_seen.set(0);
                                self.id = 0;
                                continue;
                            }
                            if (key.len == 4 and std.mem.eql(u8, key, "name")) {
                                if (_pbz_seen.isSet(1)) return error.DuplicateField;
                                _pbz_seen.set(1);
                                self.name = "";
                                continue;
                            }
                            if (options.ignore_unknown_fields) continue;
                            return error.UnknownField;
                        }
                        if (key.len == 2 and std.mem.eql(u8, key, "id")) {
                            if (_pbz_seen.isSet(0)) return error.DuplicateField;
                            _pbz_seen.set(0);
                            self.id = try @This().jsonInt(i32, value);
                            continue;
                        }
                        if (key.len == 4 and std.mem.eql(u8, key, "name")) {
                            if (_pbz_seen.isSet(1)) return error.DuplicateField;
                            _pbz_seen.set(1);
                            self.name = try @This().jsonString(value);
                            continue;
                        }
                        if (options.ignore_unknown_fields) continue;
                        return error.UnknownField;
                    }
                }

                fn jsonInt(comptime T: type, value: pbz.json.Value) !T {
    return try pbz.json.intValue(T, value);
}

fn jsonFloat(comptime T: type, value: pbz.json.Value) !T {
    return switch (value) {
        .integer => |v| @as(T, @floatFromInt(v)),
        .float => |v| blk: {
            const out: T = @floatCast(v);
            if (!std.math.isFinite(out)) return error.InvalidNumber;
            break :blk out;
        },
        .number_string => |text| blk: {
            const out = std.fmt.parseFloat(T, text) catch return error.InvalidNumber;
            if (!std.math.isFinite(out)) return error.InvalidNumber;
            break :blk out;
        },
        .string => |text| if (std.mem.eql(u8, text, "NaN"))
            std.math.nan(T)
        else if (std.mem.eql(u8, text, "Infinity"))
            std.math.inf(T)
        else if (std.mem.eql(u8, text, "-Infinity"))
            -std.math.inf(T)
        else blk: {
            const out = std.fmt.parseFloat(T, text) catch return error.InvalidNumber;
            if (!std.math.isFinite(out)) return error.InvalidNumber;
            break :blk out;
        },
        else => error.TypeMismatch,
    };
}

fn jsonBool(value: pbz.json.Value) !bool {
    return switch (value) {
        .bool => |v| v,
        else => error.TypeMismatch,
    };
}

fn jsonString(value: pbz.json.Value) ![]const u8 {
    return switch (value) {
        .string => |v| v,
        else => error.TypeMismatch,
    };
}

fn jsonBytes(allocator: std.mem.Allocator, value: pbz.json.Value) ![]const u8 {
    return try @This().jsonDecodeBase64(allocator, try @This().jsonString(value));
}

fn jsonEnum(value: pbz.json.Value, comptime names: []const []const u8, comptime numbers: []const i32, comptime closed: bool) !i32 {
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
    var expect_field = true;
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
            expect_field = false;
            try out.append(allocator, c);
        } else if (c == ';' or c == ',') {
            if (expect_field) return error.InvalidCharacter;
            expect_field = true;
            try out.append(allocator, '\n');
        } else if (c == '{' or c == '<') {
            try out.append(allocator, c);
            try out.append(allocator, '\n');
            expect_field = true;
        } else if (c == '}' or c == '>') {
            try out.append(allocator, '\n');
            try out.append(allocator, c);
            try out.append(allocator, '\n');
            expect_field = false;
        } else {
            if (!std.ascii.isWhitespace(c)) expect_field = false;
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
    if (body.len >= 2 and body[0] == '0' and (body[1] == 'x' or body[1] == 'X')) return error.TypeMismatch;
    if (body.len > 1 and body[0] == '0' and std.ascii.isDigit(body[1]) and std.mem.indexOfAny(u8, body, ".eE") == null) return error.TypeMismatch;
    if (std.ascii.eqlIgnoreCase(body, "nan")) return std.math.nan(T);
    if (std.ascii.eqlIgnoreCase(body, "inf") or std.ascii.eqlIgnoreCase(body, "infinity")) {
        const parsed = std.math.inf(T);
        return if (negative) -parsed else parsed;
    }
    return try std.fmt.parseFloat(T, value);
}

fn textUnquote(allocator: std.mem.Allocator, raw_value: []const u8) ![]const u8 {
    var value = raw_value;
    if (value.len >= 2 and value[0] == '[' and value[value.len - 1] == ']') {
        value = std.mem.trim(u8, value[1 .. value.len - 1], " \\t\\r\\n");
    }
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
                'u', 'U' => {
                    const count: usize = if (esc == 'u') 4 else 8;
                    var codepoint: u32 = 0;
                    var digits: usize = 0;
                    while (digits < count) : (digits += 1) {
                        if (i >= value.len) return error.InvalidEscape;
                        const digit = @This().textHexDigit(value[i]) orelse return error.InvalidEscape;
                        codepoint = codepoint * 16 + digit;
                        i += 1;
                    }
                    if (codepoint > 0x10ffff or (codepoint >= 0xd800 and codepoint <= 0xdfff)) return error.InvalidEscape;
                    var buf: [4]u8 = undefined;
                    const len = std.unicode.utf8Encode(@intCast(codepoint), &buf) catch return error.InvalidEscape;
                    try out.appendSlice(allocator, buf[0..len]);
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

fn textLikelyUnknownMessage(bytes: []const u8) bool {
    if (bytes.len == 0) return false;
    var reader = pbz.Reader.init(bytes);
    while (true) {
        const tag = reader.nextTag() catch return false;
        const actual = tag orelse return reader.eof();
        reader.skipValue(actual) catch return false;
    }
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
            const bytes = try r.readBytes();
            if (@This().textLikelyUnknownMessage(bytes)) {
                try writer.print("{d} {{\n", .{tag.number});
                var _pbz_nested_reader = pbz.Reader.init(bytes);
                while (try _pbz_nested_reader.nextTag()) |inner| try @This().textWriteUnknownField(inner, &_pbz_nested_reader, writer);
                try writer.writeAll("}\n");
            } else {
                try writer.print("{d}: ", .{tag.number});
                try @This().textWriteQuotedBytes(bytes, writer);
                try writer.writeByte('\n');
            }
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
    return try pbz.json.decodeBase64(allocator, value);
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

                pub const TextFormatOptions = struct { enum_as_name: bool = true, print_unknown_fields: bool = false };

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

                pub fn formatTextWithOptions(self: @This(), allocator: std.mem.Allocator, writer: *std.Io.Writer, options: @This().TextFormatOptions) anyerror!void {
                    _ = &allocator;
                    _ = &options;
                    if (self.id != 0) { try writer.writeAll("id: "); const value = self.id; try writer.print("{d}", .{value}); try writer.writeByte('\n'); }
                    if (self.name.len != 0) { try writer.writeAll("name: "); const value = self.name; if (!pbz.validateUtf8(value)) return error.InvalidUtf8; try @This().textWriteQuotedBytes(value, writer); try writer.writeByte('\n'); }
                    for (self._unknown_fields) |raw| {
                        if (options.print_unknown_fields) try @This().textWriteUnknownRaw(raw, writer);
                    }
                }

                pub const TextParseOptions = struct { ignore_unknown_fields: bool = false };

                pub fn parseText(allocator: std.mem.Allocator, text: []const u8) anyerror!@This() {
                    return try @This().parseTextWithOptions(allocator, text, .{});
                }

                pub fn parseTextWithOptions(allocator: std.mem.Allocator, text: []const u8, options: @This().TextParseOptions) anyerror!@This() {
                    return @This().parseTextFastWithOptions(allocator, text, options) catch @This().parseTextConformantWithOptions(allocator, text, options);
                }

                pub fn parseTextConformantWithOptions(allocator: std.mem.Allocator, text: []const u8, options: @This().TextParseOptions) anyerror!@This() {
                    _ = options;
                    var arena = std.heap.ArenaAllocator.init(allocator);
                    defer arena.deinit();
                    var registry: pbz.Registry = undefined;
                    const file = try _pbzFileRegistry(arena.allocator(), &registry);
                    defer registry.deinit();
                    const message_descriptor = @This().descriptor(file) orelse return error.TypeMismatch;
                    var dynamic = try pbz.text.parseAllocWithRegistry(allocator, file, &registry, message_descriptor, text);
                    defer dynamic.deinit();
                    return try @This().fromDynamic(allocator, file, &dynamic);
                }

                fn parseTextFastWithOptions(allocator: std.mem.Allocator, text: []const u8, options: @This().TextParseOptions) anyerror!@This() {
                    var self = @This().init();
                    errdefer self.deinit(allocator);
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
                        if (@This().textFieldValue(line, "id")) |raw_value| {
                            self.id = try @This().textInt(i32, raw_value);
                            continue;
                        }
                        if (@This().textFieldValue(line, "name")) |raw_value| {
                            self.name = blk: { const decoded = try @This().textUnquote(try self._pbzOwnedAllocator(allocator), raw_value); if (!pbz.validateUtf8(decoded)) return error.InvalidUtf8; break :blk decoded; };
                            continue;
                        }
                        if (try @This().textUnknownField(allocator, line)) |raw| { try pbz.wire.appendOwnedRawField(allocator, &_unknown_fields_list, raw); continue; }
                        if (try @This().textUnknownGroup(allocator, line, &lines, text_has_comments)) |raw| { try pbz.wire.appendOwnedRawField(allocator, &_unknown_fields_list, raw); continue; }
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

        };

    };

};

fn _pbzFileRegistry(arena: std.mem.Allocator, registry_out: *pbz.Registry) !*pbz.schema.FileDescriptor {
    registry_out.* = pbz.Registry.init(arena);
    const file = try arena.create(pbz.schema.FileDescriptor);
    file.* = try pbz_generated_file.decodeFileDescriptor(arena);
    try registry_out.addFile(file);
    return file;
}
