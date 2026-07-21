const std = @import("std");
const pbz = @import("pbz");

pub const proto_package = "demo.extgen";
pub const proto_syntax = "proto2";

pub const demo = struct {
    pub const extgen = struct {
        pub const Role = enum(i32) {
            ROLE_UNKNOWN = 0,
            ROLE_USER = 1,
            ROLE_ADMIN = 2,
            pub fn fromInt(value: i32) ?@This() {
                return switch (value) {
                    0 => .ROLE_UNKNOWN,
                    1 => .ROLE_USER,
                    2 => .ROLE_ADMIN,
                    else => null,
                };
            }
            pub fn toInt(self: @This()) i32 {
                return @intFromEnum(self);
            }
            pub fn protoName(self: @This()) []const u8 {
                return switch (self) {
                    .ROLE_UNKNOWN => "ROLE_UNKNOWN",
                    .ROLE_USER => "ROLE_USER",
                    .ROLE_ADMIN => "ROLE_ADMIN",
                };
            }
            pub fn fromName(name: []const u8) ?@This() {
                if (std.mem.eql(u8, name, "ROLE_UNKNOWN")) return .ROLE_UNKNOWN;
                if (std.mem.eql(u8, name, "ROLE_USER")) return .ROLE_USER;
                if (std.mem.eql(u8, name, "ROLE_ADMIN")) return .ROLE_ADMIN;
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

        pub const Host = struct {
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



            pub fn hasExtension_tag(self: @This()) !bool {
                return try extensions.tag.hasInUnknown(self);
            }

            pub fn countExtension_tag(self: @This()) !usize {
                return try extensions.tag.countInUnknown(self);
            }

            pub fn getExtension_tag(self: @This(), allocator: std.mem.Allocator) !?[]const u8 {
                return try extensions.tag.decodeFirstFromUnknown(self, allocator);
            }

            pub fn getExtensionOrDefault_tag(self: @This(), allocator: std.mem.Allocator) ![]const u8 {
                return (try self.getExtension_tag(allocator)) orelse extensions.tag.default_value_zig;
            }

            pub fn setExtension_tag(self: *@This(), allocator: std.mem.Allocator, value: []const u8) !void {
                try extensions.tag.replaceInUnknown(self, allocator, value);
            }

            pub fn clearExtension_tag(self: *@This(), allocator: std.mem.Allocator) !void {
                try extensions.tag.clearFromUnknown(self, allocator);
            }

            pub fn hasExtension_nums(self: @This()) !bool {
                return try extensions.nums.hasInUnknown(self);
            }

            pub fn countExtension_nums(self: @This()) !usize {
                return try extensions.nums.countInUnknown(self);
            }

            pub fn getExtension_nums(self: @This(), allocator: std.mem.Allocator) ![]i32 {
                return try extensions.nums.decodeAllFromUnknown(self, allocator);
            }

            pub fn appendExtension_nums(self: *@This(), allocator: std.mem.Allocator, values: []const i32) !void {
                try extensions.nums.appendAllToUnknown(self, allocator, values);
            }

            pub fn addExtension_nums(self: *@This(), allocator: std.mem.Allocator, value: i32) !void {
                try extensions.nums.appendToUnknown(self, allocator, value);
            }

            pub fn replaceExtension_nums(self: *@This(), allocator: std.mem.Allocator, values: []const i32) !void {
                try extensions.nums.replaceAllInUnknown(self, allocator, values);
            }

            pub fn clearExtension_nums(self: *@This(), allocator: std.mem.Allocator) !void {
                try extensions.nums.clearFromUnknown(self, allocator);
            }

            pub fn hasExtension_payload(self: @This()) !bool {
                return try extensions.payload.hasInUnknown(self);
            }

            pub fn countExtension_payload(self: @This()) !usize {
                return try extensions.payload.countInUnknown(self);
            }

            pub fn getExtension_payload(self: @This(), allocator: std.mem.Allocator) !?[]const u8 {
                return try extensions.payload.decodeFirstFromUnknown(self, allocator);
            }

            pub fn setExtension_payload(self: *@This(), allocator: std.mem.Allocator, value: []const u8) !void {
                try extensions.payload.replaceInUnknown(self, allocator, value);
            }

            pub fn setExtensionMessage_payload(self: *@This(), allocator: std.mem.Allocator, value: Payload) !void {
                const payload = try value.encode(allocator);
                defer allocator.free(payload);
                try extensions.payload.replaceInUnknown(self, allocator, payload);
            }

            pub fn getExtensionMessage_payload(self: @This(), allocator: std.mem.Allocator) !?Payload {
                const payload = (try extensions.payload.decodeFirstFromUnknown(self, allocator)) orelse return null;
                return try Payload.decode(allocator, payload);
            }

            pub fn clearExtension_payload(self: *@This(), allocator: std.mem.Allocator) !void {
                try extensions.payload.clearFromUnknown(self, allocator);
            }

            pub fn hasExtension_payloads(self: @This()) !bool {
                return try extensions.payloads.hasInUnknown(self);
            }

            pub fn countExtension_payloads(self: @This()) !usize {
                return try extensions.payloads.countInUnknown(self);
            }

            pub fn getExtension_payloads(self: @This(), allocator: std.mem.Allocator) ![][]const u8 {
                return try extensions.payloads.decodeAllFromUnknown(self, allocator);
            }

            pub fn appendExtension_payloads(self: *@This(), allocator: std.mem.Allocator, values: []const []const u8) !void {
                try extensions.payloads.appendAllToUnknown(self, allocator, values);
            }

            pub fn addExtension_payloads(self: *@This(), allocator: std.mem.Allocator, value: []const u8) !void {
                try extensions.payloads.appendToUnknown(self, allocator, value);
            }

            pub fn replaceExtension_payloads(self: *@This(), allocator: std.mem.Allocator, values: []const []const u8) !void {
                try extensions.payloads.replaceAllInUnknown(self, allocator, values);
            }

            pub fn addExtensionMessage_payloads(self: *@This(), allocator: std.mem.Allocator, value: Payload) !void {
                const payload = try value.encode(allocator);
                defer allocator.free(payload);
                try extensions.payloads.appendToUnknown(self, allocator, payload);
            }

            pub fn appendExtensionMessages_payloads(self: *@This(), allocator: std.mem.Allocator, values: []const Payload) !void {
                for (values) |value| try self.addExtensionMessage_payloads(allocator, value);
            }

            pub fn replaceExtensionMessages_payloads(self: *@This(), allocator: std.mem.Allocator, values: []const Payload) !void {
                try extensions.payloads.clearFromUnknown(self, allocator);
                try self.appendExtensionMessages_payloads(allocator, values);
            }

            pub fn getExtensionMessages_payloads(self: @This(), allocator: std.mem.Allocator) ![]Payload {
                const payloads = try extensions.payloads.decodeAllFromUnknown(self, allocator);
                defer allocator.free(payloads);
                var list: std.ArrayList(Payload) = .empty;
                errdefer { for (list.items) |*item| item.deinit(allocator); list.deinit(allocator); }
                for (payloads) |payload| try list.append(allocator, try Payload.decode(allocator, payload));
                return try list.toOwnedSlice(allocator);
            }

            pub fn clearExtension_payloads(self: *@This(), allocator: std.mem.Allocator) !void {
                try extensions.payloads.clearFromUnknown(self, allocator);
            }

            pub fn hasExtension_role(self: @This()) !bool {
                return try extensions.role.hasInUnknown(self);
            }

            pub fn countExtension_role(self: @This()) !usize {
                return try extensions.role.countInUnknown(self);
            }

            pub fn getExtension_role(self: @This(), allocator: std.mem.Allocator) !?i32 {
                return try extensions.role.decodeFirstFromUnknown(self, allocator);
            }

            pub fn getExtensionOrDefault_role(self: @This(), allocator: std.mem.Allocator) !i32 {
                return (try self.getExtension_role(allocator)) orelse extensions.role.default_value_zig;
            }

            pub fn getEnumExtension_role(self: @This(), allocator: std.mem.Allocator) !?Role {
                const raw = (try self.getExtension_role(allocator)) orelse return null;
                return Role.fromInt(raw);
            }

            pub fn getEnumOrDefaultExtension_role(self: @This(), allocator: std.mem.Allocator) !Role {
                return (try self.getEnumExtension_role(allocator)) orelse Role.fromInt(extensions.role.default_value_zig) orelse unreachable;
            }

            pub fn setEnumExtension_role(self: *@This(), allocator: std.mem.Allocator, value: Role) !void {
                try self.setExtension_role(allocator, value.toInt());
            }

            pub fn setExtension_role(self: *@This(), allocator: std.mem.Allocator, value: i32) !void {
                try extensions.role.replaceInUnknown(self, allocator, value);
            }

            pub fn clearExtension_role(self: *@This(), allocator: std.mem.Allocator) !void {
                try extensions.role.clearFromUnknown(self, allocator);
            }


            pub fn mergeFrom(self: *@This(), allocator: std.mem.Allocator, other: @This()) !void {
                try pbz.wire.appendRawFieldsClone(allocator, &self._unknown_fields, other._unknown_fields);
            }

            pub fn encodedSize(self: @This()) usize {
                var size: usize = 0;
                for (self._unknown_fields) |raw| size += raw.len;
                return size;
            }

            pub fn writeTo(self: @This(), w: *pbz.Writer) !void {
                for (self._unknown_fields) |raw| try w.appendSlice(raw);
            }

            pub fn writeToAssumeCapacity(self: @This(), w: *pbz.Writer) !void {
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
                try pbz.wire.writeRawFieldsDeterministic(allocator, self._unknown_fields, w);
            }

            pub fn writeDeterministicToAssumeCapacity(self: @This(), allocator: std.mem.Allocator, w: *pbz.Writer) !void {
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
                while (try r.nextTag()) |tag| {
                    switch (tag.number) {
                        else => try pbz.wire.appendSkippedRawField(allocator, &_unknown_fields_list, r, r.lastTagStart(), tag),
                    }
                }
                self._unknown_fields = try pbz.wire.rawFieldListToOwnedSlice(allocator, &_unknown_fields_list);
                return self;
            }

            pub fn decodeReuse(self: *@This(), allocator: std.mem.Allocator, bytes: []const u8) !void {
                pbz.wire.clearRawFields(allocator, &self._unknown_fields);
                if (self._json_arena) |arena| { const child_allocator = arena.child_allocator; arena.deinit(); child_allocator.destroy(arena); self._json_arena = null; }
                errdefer self.deinit(allocator);
                var _unknown_fields_list: std.ArrayList([]const u8) = .empty;
                errdefer pbz.wire.deinitRawFieldList(allocator, &_unknown_fields_list);
                var r = pbz.Reader.init(bytes);
                while (try r.nextTag()) |tag| {
                    switch (tag.number) {
                        else => try pbz.wire.appendSkippedRawField(allocator, &_unknown_fields_list, &r, r.lastTagStart(), tag),
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
                {
                    const payloads = try extensions.payload.decodeAllFromUnknown(self, allocator);
                    defer allocator.free(payloads);
                    for (payloads) |payload| {
                        var _pbz_nested = try Payload.decode(allocator, payload);
                        defer _pbz_nested.deinit(allocator);
                        if (try _pbz_nested.missingRequiredFieldPath(allocator)) |suffix| {
                            defer allocator.free(suffix);
                            return try std.fmt.allocPrint(allocator, "payload.{s}", .{suffix});
                        }
                    }
                }
                {
                    const payloads = try extensions.payloads.decodeAllFromUnknown(self, allocator);
                    defer allocator.free(payloads);
                    for (payloads) |payload| {
                        var _pbz_nested = try Payload.decode(allocator, payload);
                        defer _pbz_nested.deinit(allocator);
                        if (try _pbz_nested.missingRequiredFieldPath(allocator)) |suffix| {
                            defer allocator.free(suffix);
                            return try std.fmt.allocPrint(allocator, "payloads.{s}", .{suffix});
                        }
                    }
                }
                return null;
            }

            pub fn validateRequired(self: @This()) !void {
                if (self.missingRequiredFieldName() != null) return error.MissingRequiredField;
            }

            pub fn validateRequiredRecursive(self: @This(), allocator: std.mem.Allocator) !void {
                try self.validateRequired();
                {
                    const payloads = try extensions.payload.decodeAllFromUnknown(self, allocator);
                    defer allocator.free(payloads);
                    for (payloads) |payload| {
                        var _pbz_nested = try Payload.decode(allocator, payload);
                        defer _pbz_nested.deinit(allocator);
                        try _pbz_nested.validateRequiredRecursive(allocator);
                    }
                }
                {
                    const payloads = try extensions.payloads.decodeAllFromUnknown(self, allocator);
                    defer allocator.free(payloads);
                    for (payloads) |payload| {
                        var _pbz_nested = try Payload.decode(allocator, payload);
                        defer _pbz_nested.deinit(allocator);
                        try _pbz_nested.validateRequiredRecursive(allocator);
                    }
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
                {
                    const values = try extensions.tag.decodeAllFromUnknown(self, allocator);
                    defer allocator.free(values);
                    if (values.len != 0) {
                        try writer.writeAll(if (first) "\"[demo.extgen.tag]\":" else ",\"[demo.extgen.tag]\":"); first = false;
                        const value = values[values.len - 1];
                        try @This().jsonWriteString(writer, value);
                    }
                }
                {
                    const values = try extensions.nums.decodeAllFromUnknown(self, allocator);
                    defer allocator.free(values);
                    if (values.len != 0) {
                        try writer.writeAll(if (first) "\"[demo.extgen.nums]\":" else ",\"[demo.extgen.nums]\":"); first = false;
                        try writer.writeAll("[");
                        for (values, 0..) |value, i| { if (i != 0) try writer.writeAll(","); try writer.print("{d}", .{value}); }
                        try writer.writeAll("]");
                    }
                }
                {
                    const values = try extensions.payload.decodeAllFromUnknown(self, allocator);
                    defer allocator.free(values);
                    if (values.len != 0) {
                        try writer.writeAll(if (first) "\"[demo.extgen.payload]\":" else ",\"[demo.extgen.payload]\":"); first = false;
                        const value = values[values.len - 1];
                        try struct { fn write(allocator_: std.mem.Allocator, writer_: *std.Io.Writer, options_: anytype, payload_: []const u8) !void { var _pbz_nested = try Payload.decode(allocator_, payload_); defer _pbz_nested.deinit(allocator_); try _pbz_nested.jsonStringifyWithOptions(allocator_, writer_, .{ .enum_as_name = options_.enum_as_name, .preserve_proto_field_names = options_.preserve_proto_field_names, .always_print_primitive_fields = options_.always_print_primitive_fields }); } }.write(allocator, writer, options, value);
                    }
                }
                {
                    const values = try extensions.payloads.decodeAllFromUnknown(self, allocator);
                    defer allocator.free(values);
                    if (values.len != 0) {
                        try writer.writeAll(if (first) "\"[demo.extgen.payloads]\":" else ",\"[demo.extgen.payloads]\":"); first = false;
                        try writer.writeAll("[");
                        for (values, 0..) |value, i| { if (i != 0) try writer.writeAll(","); try struct { fn write(allocator_: std.mem.Allocator, writer_: *std.Io.Writer, options_: anytype, payload_: []const u8) !void { var _pbz_nested = try Payload.decode(allocator_, payload_); defer _pbz_nested.deinit(allocator_); try _pbz_nested.jsonStringifyWithOptions(allocator_, writer_, .{ .enum_as_name = options_.enum_as_name, .preserve_proto_field_names = options_.preserve_proto_field_names, .always_print_primitive_fields = options_.always_print_primitive_fields }); } }.write(allocator, writer, options, value); }
                        try writer.writeAll("]");
                    }
                }
                {
                    const values = try extensions.role.decodeAllFromUnknown(self, allocator);
                    defer allocator.free(values);
                    if (values.len != 0) {
                        try writer.writeAll(if (first) "\"[demo.extgen.role]\":" else ",\"[demo.extgen.role]\":"); first = false;
                        const value = values[values.len - 1];
                        try @This().jsonWriteEnum(writer, value, &.{"ROLE_UNKNOWN", "ROLE_USER", "ROLE_ADMIN"}, &.{0, 1, 2}, options.enum_as_name);
                    }
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
                const object = switch (json_value) { .object => |object| object, else => return error.TypeMismatch };
                var it = object.iterator();
                while (it.next()) |entry| {
                    const key = entry.key_ptr.*;
                    const value = entry.value_ptr.*;
                    if (value == .null) {
                        if (std.mem.eql(u8, key, "[demo.extgen.tag]") or std.mem.eql(u8, key, "[tag]")) { try self.clearUnknownFieldsByNumber(allocator, extensions.tag.number); continue; }
                        if (std.mem.eql(u8, key, "[demo.extgen.nums]") or std.mem.eql(u8, key, "[nums]")) { try self.clearUnknownFieldsByNumber(allocator, extensions.nums.number); continue; }
                        if (std.mem.eql(u8, key, "[demo.extgen.payload]") or std.mem.eql(u8, key, "[payload]")) { try self.clearUnknownFieldsByNumber(allocator, extensions.payload.number); continue; }
                        if (std.mem.eql(u8, key, "[demo.extgen.payloads]") or std.mem.eql(u8, key, "[payloads]")) { try self.clearUnknownFieldsByNumber(allocator, extensions.payloads.number); continue; }
                        if (std.mem.eql(u8, key, "[demo.extgen.role]") or std.mem.eql(u8, key, "[role]")) { try self.clearUnknownFieldsByNumber(allocator, extensions.role.number); continue; }
                        if (options.ignore_unknown_fields) continue;
                        return error.UnknownField;
                    }
                    if (std.mem.eql(u8, key, "[demo.extgen.tag]") or std.mem.eql(u8, key, "[tag]")) {
                        try extensions.tag.replaceInUnknown(self, allocator, try @This().jsonString(value));
                        continue;
                    }
                    if (std.mem.eql(u8, key, "[demo.extgen.nums]") or std.mem.eql(u8, key, "[nums]")) {
                        try self.clearUnknownFieldsByNumber(allocator, extensions.nums.number);
                        const array = switch (value) { .array => |array| array, else => return error.TypeMismatch };
                        for (array.items) |item| {
                            try extensions.nums.appendToUnknown(self, allocator, try @This().jsonInt(i32, item));
                        }
                        continue;
                    }
                    if (std.mem.eql(u8, key, "[demo.extgen.payload]") or std.mem.eql(u8, key, "[payload]")) {
                        var _pbz_nested = try Payload.jsonParseValueWithOptions(arena_allocator, arena_allocator, value, .{ .ignore_unknown_fields = options.ignore_unknown_fields });
                        defer _pbz_nested.deinit(arena_allocator);
                        try extensions.payload.replaceInUnknown(self, allocator, try _pbz_nested.encode(arena_allocator));
                        continue;
                    }
                    if (std.mem.eql(u8, key, "[demo.extgen.payloads]") or std.mem.eql(u8, key, "[payloads]")) {
                        try self.clearUnknownFieldsByNumber(allocator, extensions.payloads.number);
                        const array = switch (value) { .array => |array| array, else => return error.TypeMismatch };
                        for (array.items) |item| {
                            var _pbz_nested = try Payload.jsonParseValueWithOptions(arena_allocator, arena_allocator, item, .{ .ignore_unknown_fields = options.ignore_unknown_fields });
                            defer _pbz_nested.deinit(arena_allocator);
                            try extensions.payloads.appendToUnknown(self, allocator, try _pbz_nested.encode(arena_allocator));
                        }
                        continue;
                    }
                    if (std.mem.eql(u8, key, "[demo.extgen.role]") or std.mem.eql(u8, key, "[role]")) {
                        try extensions.role.replaceInUnknown(self, allocator, @This().jsonEnum(value, &.{"ROLE_UNKNOWN", "ROLE_USER", "ROLE_ADMIN"}, &.{0, 1, 2}, true) catch |err| { if (options.ignore_unknown_fields) continue; return err; });
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
                for (self._unknown_fields) |raw| {
                    if (extensions.tag.decodeRaw(raw) catch null) |value| {
                            try writer.writeAll("[demo.extgen.tag]: "); try @This().textWriteQuotedBytes(value, writer); try writer.writeByte('\n');
                            continue;
                    }
                    if (extensions.nums.decodeRaw(raw) catch null) |value| {
                            try writer.writeAll("[demo.extgen.nums]: "); try writer.print("{d}", .{value}); try writer.writeByte('\n');
                            continue;
                    }
                    if (extensions.nums.decodePackedRaw(allocator, raw) catch null) |values| {
                        defer allocator.free(values);
                        for (values) |value| {
                            try writer.writeAll("[demo.extgen.nums]: "); try writer.print("{d}", .{value}); try writer.writeByte('\n');
                        }
                        continue;
                    }
                    if (extensions.payload.decodeRaw(raw) catch null) |payload| {
                            try writer.writeAll("[demo.extgen.payload] {\n");
                            var _pbz_nested = try Payload.decode(allocator, payload);
                            defer _pbz_nested.deinit(allocator);
                            try _pbz_nested.formatTextWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name });
                            try writer.writeAll("}\n");
                            continue;
                    }
                    if (extensions.payloads.decodeRaw(raw) catch null) |payload| {
                            try writer.writeAll("[demo.extgen.payloads] {\n");
                            var _pbz_nested = try Payload.decode(allocator, payload);
                            defer _pbz_nested.deinit(allocator);
                            try _pbz_nested.formatTextWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name });
                            try writer.writeAll("}\n");
                            continue;
                    }
                    if (extensions.role.decodeRaw(raw) catch null) |value| {
                            try writer.writeAll("[demo.extgen.role]: "); try @This().textWriteEnum(writer, value, &.{"ROLE_UNKNOWN", "ROLE_USER", "ROLE_ADMIN"}, &.{0, 1, 2}, options.enum_as_name); try writer.writeByte('\n');
                            continue;
                    }
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
                const text_has_comments = std.mem.indexOfScalar(u8, normalized_text, '#') != null;
                var lines = std.mem.splitScalar(u8, normalized_text, '\n');
                while (lines.next()) |raw_line| {
                    const line = @This().textCleanLine(raw_line, text_has_comments);
                    if (line.len == 0) continue;
                    if (@This().textFieldValue(line, "[demo.extgen.tag]") orelse @This().textFieldValue(line, "[tag]")) |raw_value| {
                        const raw = try extensions.tag.encodeRaw(allocator, try @This().textUnquote(try self._pbzOwnedAllocator(allocator), raw_value));
                        errdefer allocator.free(raw);
                        try _unknown_fields_list.append(allocator, raw);
                        continue;
                    }
                    if (@This().textFieldValue(line, "[demo.extgen.nums]") orelse @This().textFieldValue(line, "[nums]")) |raw_value| {
                        const raw = try extensions.nums.encodeRaw(allocator, try @This().textInt(i32, raw_value));
                        errdefer allocator.free(raw);
                        try _unknown_fields_list.append(allocator, raw);
                        continue;
                    }
                    if (@This().textBlockField(line, "[demo.extgen.payload]") or @This().textBlockField(line, "[payload]")) {
                        const block = try @This().textBlock(allocator, &lines, text_has_comments);
                        defer allocator.free(block);
                        var _pbz_nested = try Payload.parseTextWithOptions(allocator, block, .{ .ignore_unknown_fields = options.ignore_unknown_fields });
                        defer _pbz_nested.deinit(allocator);
                        const owned_allocator = try self._pbzOwnedAllocator(allocator);
                        const payload = try _pbz_nested.encode(owned_allocator);
                        const raw = try extensions.payload.encodeRaw(allocator, payload);
                        errdefer allocator.free(raw);
                        try _unknown_fields_list.append(allocator, raw);
                        continue;
                    }
                    if (@This().textBlockField(line, "[demo.extgen.payloads]") or @This().textBlockField(line, "[payloads]")) {
                        const block = try @This().textBlock(allocator, &lines, text_has_comments);
                        defer allocator.free(block);
                        var _pbz_nested = try Payload.parseTextWithOptions(allocator, block, .{ .ignore_unknown_fields = options.ignore_unknown_fields });
                        defer _pbz_nested.deinit(allocator);
                        const owned_allocator = try self._pbzOwnedAllocator(allocator);
                        const payload = try _pbz_nested.encode(owned_allocator);
                        const raw = try extensions.payloads.encodeRaw(allocator, payload);
                        errdefer allocator.free(raw);
                        try _unknown_fields_list.append(allocator, raw);
                        continue;
                    }
                    if (@This().textFieldValue(line, "[demo.extgen.role]") orelse @This().textFieldValue(line, "[role]")) |raw_value| {
                        const raw = try extensions.role.encodeRaw(allocator, @This().textEnum(raw_value, &.{"ROLE_UNKNOWN", "ROLE_USER", "ROLE_ADMIN"}, &.{0, 1, 2}, true) catch |err| { if (options.ignore_unknown_fields) { continue; } return err; });
                        errdefer allocator.free(raw);
                        try _unknown_fields_list.append(allocator, raw);
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

        pub const Payload = struct {
            pub const id_number = 1;
            pub const note_number = 2;

            pub const id_field = struct {
                pub const number = 1;
                pub const name = "id";
                pub const json_name = "id";
                pub const cardinality = "required";
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
                pub const has_presence = true;
                pub const default_value = "";
                pub const is_packed = false;
            };

            id: i32 = 0,
            has_id: bool = false,
            note: []const u8 = "",
            has_note: bool = false,
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
                out.has_id = self.has_id;
                out.note = try owned_allocator.dupe(u8, self.note);
                out.has_note = self.has_note;
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


            pub fn noteFieldView(bytes: []const u8) !?[]const u8 {
                return try pbz.wire.bytesFieldView(bytes, 2);
            }

            pub fn noteFieldSlices(header: *[20]u8, value: []const u8) !pbz.wire.BorrowedFieldSlices {
                return pbz.wire.lengthDelimitedFieldSlicesAssumeValid(header, 2, value);
            }

            pub fn noteStringView(bytes: []const u8) !?[]const u8 {
                return try noteFieldView(bytes);
            }

            pub fn noteStringSlices(header: *[20]u8, value: []const u8) !pbz.wire.BorrowedFieldSlices {
                return try noteFieldSlices(header, value);
            }


            // no same-file extension accessors

            pub fn mergeFrom(self: *@This(), allocator: std.mem.Allocator, other: @This()) !void {
                if (other.has_id) { self.id = other.id; self.has_id = true; }
                if (other.has_note) { self.note = other.note; self.has_note = true; }
                try pbz.wire.appendRawFieldsClone(allocator, &self._unknown_fields, other._unknown_fields);
            }

            pub fn encodedSize(self: @This()) usize {
                var size: usize = 0;
                if (self.has_id) size += 1 + pbz.wire.encodedVarintSize(@as(u64, @bitCast(@as(i64, self.id))));
                if (self.has_note) size += 1 + pbz.wire.encodedVarintSize(self.note.len) + self.note.len;
                for (self._unknown_fields) |raw| size += raw.len;
                return size;
            }

            pub fn writeTo(self: @This(), w: *pbz.Writer) !void {
                if (self.has_id) try w.writeInt32(1, self.id);
                if (self.has_note) try w.writeString(2, self.note);
                for (self._unknown_fields) |raw| try w.appendSlice(raw);
            }

            pub fn writeToAssumeCapacity(self: @This(), w: *pbz.Writer) !void {
                if (self.has_id) w.writeInt32AssumeCapacity(1, self.id);
                if (self.has_note) w.writeStringAssumeCapacity(2, self.note);
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
                if (self.has_id) { buffer[index] = 8; index += 1; pbz.wire.writeDirectScalarVarintToSlice(buffer, &index, @as(u64, @bitCast(@as(i64, self.id)))); }
                if (self.has_note) { buffer[index] = 18; index += 1; pbz.wire.writeVarintToSlice(buffer, &index, self.note.len); @memcpy(buffer[index..][0..self.note.len], self.note); index += self.note.len; }
                for (self._unknown_fields) |raw| { @memcpy(buffer[index..][0..raw.len], raw); index += raw.len; }
                return buffer[0..index];
            }

            pub fn encodeIntoAssumeCapacityTrustedUtf8(self: @This(), buffer: []u8) ![]u8 {
                var index: usize = 0;
                if (self.has_id) { buffer[index] = 8; index += 1; pbz.wire.writeDirectScalarVarintToSlice(buffer, &index, @as(u64, @bitCast(@as(i64, self.id)))); }
                if (self.has_note) { buffer[index] = 18; index += 1; pbz.wire.writeVarintToSlice(buffer, &index, self.note.len); @memcpy(buffer[index..][0..self.note.len], self.note); index += self.note.len; }
                for (self._unknown_fields) |raw| { @memcpy(buffer[index..][0..raw.len], raw); index += raw.len; }
                return buffer[0..index];
            }

            pub fn writeDeterministicTo(self: @This(), allocator: std.mem.Allocator, w: *pbz.Writer) !void {
                if (self.has_id) try w.writeInt32(1, self.id);
                if (self.has_note) try w.writeString(2, self.note);
                try pbz.wire.writeRawFieldsDeterministic(allocator, self._unknown_fields, w);
            }

            pub fn writeDeterministicToAssumeCapacity(self: @This(), allocator: std.mem.Allocator, w: *pbz.Writer) !void {
                if (self.has_id) w.writeInt32AssumeCapacity(1, self.id);
                if (self.has_note) w.writeStringAssumeCapacity(2, self.note);
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
                        8 => { self.id = try r.readInt32(); self.has_id = true; },
                        18 => { self.note = try r.readBytes(); self.has_note = true; },
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
                self.has_id = false;
                self.note = "";
                self.has_note = false;
                errdefer self.deinit(allocator);
                var _unknown_fields_list: std.ArrayList([]const u8) = .empty;
                errdefer pbz.wire.deinitRawFieldList(allocator, &_unknown_fields_list);
                var r = pbz.Reader.init(bytes);
                while (!r.eof()) {
                    const raw_tag_start = r.position();
                    const first_tag_byte = try r.readByte();
                    const raw_tag: u64 = if (first_tag_byte < 0x80) first_tag_byte else blk: { r.index = raw_tag_start; break :blk try r.readVarint(); };
                    switch (raw_tag) {
                        8 => { self.id = try r.readInt32(); self.has_id = true; },
                        18 => { self.note = try r.readBytes(); self.has_note = true; },
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
                if (!self.has_id) return "id";
                return null;
            }

            pub fn missingRequiredFieldPath(self: @This(), allocator: std.mem.Allocator) !?[]u8 {
                if (!self.has_id) return try allocator.dupe(u8, "id");
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
                if (self.has_id) {
                    try writer.writeAll(if (first) "\"id\":" else ",\"id\":"); first = false;
                    const value = self.id;
                    try writer.print("{d}", .{value});
                }
                if (self.has_note or options.always_print_primitive_fields) {
                    try writer.writeAll(if (first) "\"note\":" else ",\"note\":"); first = false;
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
                _ = allocator;
                _ = arena_allocator;
                const object = switch (json_value) { .object => |object| object, else => return error.TypeMismatch };
                var it = object.iterator();
                while (it.next()) |entry| {
                    const key = entry.key_ptr.*;
                    const value = entry.value_ptr.*;
                    if (value == .null) {
                        if (std.mem.eql(u8, key, "id")) {
                            self.id = 0;
                            self.has_id = false;
                            continue;
                        }
                        if (std.mem.eql(u8, key, "note")) {
                            self.note = "";
                            self.has_note = false;
                            continue;
                        }
                        if (options.ignore_unknown_fields) continue;
                        return error.UnknownField;
                    }
                    if (std.mem.eql(u8, key, "id")) {
                        self.id = try @This().jsonInt(i32, value);
                        self.has_id = true;
                        continue;
                    }
                    if (std.mem.eql(u8, key, "note")) {
                        self.note = try @This().jsonString(value);
                        self.has_note = true;
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
                if (self.has_id) { try writer.writeAll("id: "); const value = self.id; try writer.print("{d}", .{value}); try writer.writeByte('\n'); }
                if (self.has_note) { try writer.writeAll("note: "); const value = self.note; try @This().textWriteQuotedBytes(value, writer); try writer.writeByte('\n'); }
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
                const text_has_comments = std.mem.indexOfScalar(u8, normalized_text, '#') != null;
                var lines = std.mem.splitScalar(u8, normalized_text, '\n');
                while (lines.next()) |raw_line| {
                    const line = @This().textCleanLine(raw_line, text_has_comments);
                    if (line.len == 0) continue;
                    if (@This().textFieldValue(line, "id")) |raw_value| {
                        self.id = try @This().textInt(i32, raw_value);
                        self.has_id = true;
                        continue;
                    }
                    if (@This().textFieldValue(line, "note")) |raw_value| {
                        self.note = try @This().textUnquote(try self._pbzOwnedAllocator(allocator), raw_value);
                        self.has_note = true;
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

        pub const extensions = struct {
            pub const tag = struct {
                pub const number = 100;
                pub const extendee = ".demo.extgen.Host";
                pub const extendee_has_type_ref = true;
                pub const extendee_type_ref = Host;
                pub const cardinality = "optional";
                pub const value_type = "string";
                pub const value_has_type_ref = false;
                pub const value_type_ref = void;
                pub const value_has_enum_ref = false;
                pub const value_enum_ref = void;
                pub const zig_type = "[]const u8";
                pub const typed_zig_type = "[]const u8";
                pub const has_default = true;
                pub const default_value = "untagged";
                pub const default_value_zig: []const u8 = "untagged";
                pub fn hasOn(message: Host) !bool {
                    return try hasInUnknown(message);
                }
                pub fn countOn(message: Host) !usize {
                    return try countInUnknown(message);
                }
                pub fn clearOn(message: *Host, allocator: std.mem.Allocator) !void {
                    try clearFromUnknown(message, allocator);
                }
                pub fn getOn(message: Host, allocator: std.mem.Allocator) !?[]const u8 {
                    return try decodeFirstFromUnknown(message, allocator);
                }
                pub fn getOrDefaultOn(message: Host, allocator: std.mem.Allocator) ![]const u8 {
                    return (try getOn(message, allocator)) orelse default_value_zig;
                }
                pub fn setOn(message: *Host, allocator: std.mem.Allocator, value: []const u8) !void {
                    try replaceInUnknown(message, allocator, value);
                }
                pub fn write(w: *pbz.Writer, value: []const u8) !void {
                    try w.writeString(100, value);
                }
                pub fn encodeRaw(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
                    var w = pbz.Writer.init(allocator);
                    errdefer w.deinit();
                    try write(&w, value);
                    return try w.toOwnedSlice();
                }
                pub fn appendToUnknown(message: anytype, allocator: std.mem.Allocator, value: []const u8) !void {
                    const _pbz_raw = try encodeRaw(allocator, value);
                    defer allocator.free(_pbz_raw);
                    try message.appendUnknownRaw(allocator, _pbz_raw);
                }
                pub fn hasInUnknown(message: anytype) !bool {
                    return try message.hasUnknownFieldNumber(number);
                }
                pub fn countInUnknown(message: anytype) !usize {
                    return try message.unknownFieldCountByNumber(number);
                }
                pub fn clearFromUnknown(message: anytype, allocator: std.mem.Allocator) !void {
                    try message.clearUnknownFieldsByNumber(allocator, number);
                }
                pub fn replaceInUnknown(message: anytype, allocator: std.mem.Allocator, value: []const u8) !void {
                    try clearFromUnknown(message, allocator);
                    try appendToUnknown(message, allocator, value);
                }
                pub fn decodeValue(r: *pbz.Reader) ![]const u8 {
                    return try r.readBytes();
                }
                pub fn decodeRaw(raw: []const u8) !?[]const u8 {
                    var r = pbz.Reader.init(raw);
                    const _pbz_tag = (try r.nextTag()) orelse return null;
                    if (_pbz_tag.number != number or _pbz_tag.wire_type != .length_delimited) return null;
                    const _pbz_value = try decodeValue(&r);
                    if (!r.eof()) return error.InvalidWireType;
                    return _pbz_value;
                }
                pub fn decodeAllRaw(allocator: std.mem.Allocator, raw_fields: []const []const u8) ![][]const u8 {
                    var _pbz_list: std.ArrayList([]const u8) = .empty;
                    errdefer _pbz_list.deinit(allocator);
                    for (raw_fields) |_pbz_raw| {
                        if (try decodeRaw(_pbz_raw)) |_pbz_value| try _pbz_list.append(allocator, _pbz_value);
                    }
                    return try _pbz_list.toOwnedSlice(allocator);
                }
                pub fn decodeFromUnknownFieldsAlloc(message: anytype, allocator: std.mem.Allocator) ![][]const u8 {
                    return try decodeAllRaw(allocator, message.unknownFields());
                }
                pub fn decodeAllFromUnknown(message: anytype, allocator: std.mem.Allocator) ![][]const u8 {
                    return try decodeFromUnknownFieldsAlloc(message, allocator);
                }
                pub fn decodeFirstFromUnknown(message: anytype, allocator: std.mem.Allocator) !?[]const u8 {
                    const _pbz_values = try decodeFromUnknownFieldsAlloc(message, allocator);
                    defer allocator.free(_pbz_values);
                    return if (_pbz_values.len == 0) null else _pbz_values[_pbz_values.len - 1];
                }
            };
            pub const nums = struct {
                pub const number = 101;
                pub const extendee = ".demo.extgen.Host";
                pub const extendee_has_type_ref = true;
                pub const extendee_type_ref = Host;
                pub const cardinality = "repeated";
                pub const value_type = "int32";
                pub const value_has_type_ref = false;
                pub const value_type_ref = void;
                pub const value_has_enum_ref = false;
                pub const value_enum_ref = void;
                pub const zig_type = "[]const i32";
                pub const typed_zig_type = "[]const i32";
                pub const has_default = false;
                pub const default_value = "";
                pub const default_value_zig: i32 = 0;
                pub fn hasOn(message: Host) !bool {
                    return try hasInUnknown(message);
                }
                pub fn countOn(message: Host) !usize {
                    return try countInUnknown(message);
                }
                pub fn clearOn(message: *Host, allocator: std.mem.Allocator) !void {
                    try clearFromUnknown(message, allocator);
                }
                pub fn getOn(message: Host, allocator: std.mem.Allocator) ![]i32 {
                    return try decodeAllFromUnknown(message, allocator);
                }
                pub fn addOn(message: *Host, allocator: std.mem.Allocator, value: i32) !void {
                    try appendToUnknown(message, allocator, value);
                }
                pub fn appendAllOn(message: *Host, allocator: std.mem.Allocator, values: []const i32) !void {
                    try appendAllToUnknown(message, allocator, values);
                }
                pub fn replaceAllOn(message: *Host, allocator: std.mem.Allocator, values: []const i32) !void {
                    try replaceAllInUnknown(message, allocator, values);
                }
                pub fn write(w: *pbz.Writer, value: i32) !void {
                    try w.writeInt32(101, value);
                }
                pub fn encodeRaw(allocator: std.mem.Allocator, value: i32) ![]u8 {
                    var w = pbz.Writer.init(allocator);
                    errdefer w.deinit();
                    try write(&w, value);
                    return try w.toOwnedSlice();
                }
                pub fn appendToUnknown(message: anytype, allocator: std.mem.Allocator, value: i32) !void {
                    const _pbz_raw = try encodeRaw(allocator, value);
                    defer allocator.free(_pbz_raw);
                    try message.appendUnknownRaw(allocator, _pbz_raw);
                }
                pub fn hasInUnknown(message: anytype) !bool {
                    return try message.hasUnknownFieldNumber(number);
                }
                pub fn countInUnknown(message: anytype) !usize {
                    return try message.unknownFieldCountByNumber(number);
                }
                pub fn clearFromUnknown(message: anytype, allocator: std.mem.Allocator) !void {
                    try message.clearUnknownFieldsByNumber(allocator, number);
                }
                pub fn replaceInUnknown(message: anytype, allocator: std.mem.Allocator, value: i32) !void {
                    try clearFromUnknown(message, allocator);
                    try appendToUnknown(message, allocator, value);
                }
                pub fn writeAll(w: *pbz.Writer, values: []const i32) !void {
                    if (values.len == 0) return;
                    var packed_writer = pbz.Writer.init(w.allocator);
                    defer packed_writer.deinit();
                    for (values) |value| try packed_writer.writeVarint(@as(u64, @bitCast(@as(i64, value))));
                    try w.writeBytes(101, packed_writer.slice());
                }
                pub fn encodeAllRaw(allocator: std.mem.Allocator, values: []const i32) ![]u8 {
                    var w = pbz.Writer.init(allocator);
                    errdefer w.deinit();
                    try writeAll(&w, values);
                    return try w.toOwnedSlice();
                }
                pub fn appendAllToUnknown(message: anytype, allocator: std.mem.Allocator, values: []const i32) !void {
                    if (values.len == 0) return;
                    const _pbz_raw = try encodeAllRaw(allocator, values);
                    defer allocator.free(_pbz_raw);
                    try message.appendUnknownRaw(allocator, _pbz_raw);
                }
                pub fn replaceAllInUnknown(message: anytype, allocator: std.mem.Allocator, values: []const i32) !void {
                    try clearFromUnknown(message, allocator);
                    try appendAllToUnknown(message, allocator, values);
                }
                pub fn decodeValue(r: *pbz.Reader) !i32 {
                    return try r.readInt32();
                }
                pub fn decodeRaw(raw: []const u8) !?i32 {
                    var r = pbz.Reader.init(raw);
                    const _pbz_tag = (try r.nextTag()) orelse return null;
                    if (_pbz_tag.number != number or _pbz_tag.wire_type != .varint) return null;
                    const _pbz_value = try decodeValue(&r);
                    if (!r.eof()) return error.InvalidWireType;
                    return _pbz_value;
                }
                pub fn decodePackedRaw(allocator: std.mem.Allocator, raw: []const u8) !?[]i32 {
                    var r = pbz.Reader.init(raw);
                    const _pbz_tag = (try r.nextTag()) orelse return null;
                    if (_pbz_tag.number != number or _pbz_tag.wire_type != .length_delimited) return null;
                    var packed_reader = pbz.Reader.init(try r.readBytes());
                    if (!r.eof()) return error.InvalidWireType;
                    var _pbz_list: std.ArrayList(i32) = .empty;
                    errdefer _pbz_list.deinit(allocator);
                    while (!packed_reader.eof()) try _pbz_list.append(allocator, try packed_reader.readInt32());
                    return try _pbz_list.toOwnedSlice(allocator);
                }
                pub fn decodeAllRaw(allocator: std.mem.Allocator, raw_fields: []const []const u8) ![]i32 {
                    var _pbz_list: std.ArrayList(i32) = .empty;
                    errdefer _pbz_list.deinit(allocator);
                    for (raw_fields) |_pbz_raw| {
                        if (try decodeRaw(_pbz_raw)) |_pbz_value| try _pbz_list.append(allocator, _pbz_value);
                        if (try decodePackedRaw(allocator, _pbz_raw)) |_pbz_values| { defer allocator.free(_pbz_values); try _pbz_list.appendSlice(allocator, _pbz_values); }
                    }
                    return try _pbz_list.toOwnedSlice(allocator);
                }
                pub fn decodeFromUnknownFieldsAlloc(message: anytype, allocator: std.mem.Allocator) ![]i32 {
                    return try decodeAllRaw(allocator, message.unknownFields());
                }
                pub fn decodeAllFromUnknown(message: anytype, allocator: std.mem.Allocator) ![]i32 {
                    return try decodeFromUnknownFieldsAlloc(message, allocator);
                }
                pub fn decodeFirstFromUnknown(message: anytype, allocator: std.mem.Allocator) !?i32 {
                    const _pbz_values = try decodeFromUnknownFieldsAlloc(message, allocator);
                    defer allocator.free(_pbz_values);
                    return if (_pbz_values.len == 0) null else _pbz_values[_pbz_values.len - 1];
                }
                pub fn decodeAppend(allocator: std.mem.Allocator, list: *std.ArrayList(i32), r: *pbz.Reader) !void {
                    try list.append(allocator, try decodeValue(r));
                }
                pub fn decodeAppendRaw(allocator: std.mem.Allocator, list: *std.ArrayList(i32), raw: []const u8) !void {
                    if (try decodeRaw(raw)) |_pbz_value| try list.append(allocator, _pbz_value);
                    if (try decodePackedRaw(allocator, raw)) |_pbz_values| { defer allocator.free(_pbz_values); try list.appendSlice(allocator, _pbz_values); }
                }
            };
            pub const payload = struct {
                pub const number = 102;
                pub const extendee = ".demo.extgen.Host";
                pub const extendee_has_type_ref = true;
                pub const extendee_type_ref = Host;
                pub const cardinality = "optional";
                pub const value_type = "demo.extgen.Payload";
                pub const value_has_type_ref = true;
                pub const value_type_ref = Payload;
                pub const value_has_enum_ref = false;
                pub const value_enum_ref = void;
                pub const zig_type = "[]const u8";
                pub const typed_zig_type = "Payload";
                pub const has_default = false;
                pub const default_value = "";
                pub fn hasOn(message: Host) !bool {
                    return try hasInUnknown(message);
                }
                pub fn countOn(message: Host) !usize {
                    return try countInUnknown(message);
                }
                pub fn clearOn(message: *Host, allocator: std.mem.Allocator) !void {
                    try clearFromUnknown(message, allocator);
                }
                pub fn getOn(message: Host, allocator: std.mem.Allocator) !?[]const u8 {
                    return try decodeFirstFromUnknown(message, allocator);
                }
                pub fn setOn(message: *Host, allocator: std.mem.Allocator, value: []const u8) !void {
                    try replaceInUnknown(message, allocator, value);
                }
                pub fn setMessageOn(message: *Host, allocator: std.mem.Allocator, value: Payload) !void {
                    const _pbz_payload = try value.encode(allocator);
                    defer allocator.free(_pbz_payload);
                    try replaceInUnknown(message, allocator, _pbz_payload);
                }
                pub fn getMessageOn(message: Host, allocator: std.mem.Allocator) !?Payload {
                    const _pbz_payload = (try decodeFirstFromUnknown(message, allocator)) orelse return null;
                    return try Payload.decode(allocator, _pbz_payload);
                }
                pub fn write(w: *pbz.Writer, value: []const u8) !void {
                    try w.writeMessage(102, value);
                }
                pub fn encodeRaw(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
                    var w = pbz.Writer.init(allocator);
                    errdefer w.deinit();
                    try write(&w, value);
                    return try w.toOwnedSlice();
                }
                pub fn appendToUnknown(message: anytype, allocator: std.mem.Allocator, value: []const u8) !void {
                    const _pbz_raw = try encodeRaw(allocator, value);
                    defer allocator.free(_pbz_raw);
                    try message.appendUnknownRaw(allocator, _pbz_raw);
                }
                pub fn hasInUnknown(message: anytype) !bool {
                    return try message.hasUnknownFieldNumber(number);
                }
                pub fn countInUnknown(message: anytype) !usize {
                    return try message.unknownFieldCountByNumber(number);
                }
                pub fn clearFromUnknown(message: anytype, allocator: std.mem.Allocator) !void {
                    try message.clearUnknownFieldsByNumber(allocator, number);
                }
                pub fn replaceInUnknown(message: anytype, allocator: std.mem.Allocator, value: []const u8) !void {
                    try clearFromUnknown(message, allocator);
                    try appendToUnknown(message, allocator, value);
                }
                pub fn decodeValue(r: *pbz.Reader) ![]const u8 {
                    return try r.readBytes();
                }
                pub fn decodeRaw(raw: []const u8) !?[]const u8 {
                    var r = pbz.Reader.init(raw);
                    const _pbz_tag = (try r.nextTag()) orelse return null;
                    if (_pbz_tag.number != number or _pbz_tag.wire_type != .length_delimited) return null;
                    const _pbz_value = try decodeValue(&r);
                    if (!r.eof()) return error.InvalidWireType;
                    return _pbz_value;
                }
                pub fn decodeAllRaw(allocator: std.mem.Allocator, raw_fields: []const []const u8) ![][]const u8 {
                    var _pbz_list: std.ArrayList([]const u8) = .empty;
                    errdefer _pbz_list.deinit(allocator);
                    for (raw_fields) |_pbz_raw| {
                        if (try decodeRaw(_pbz_raw)) |_pbz_value| try _pbz_list.append(allocator, _pbz_value);
                    }
                    return try _pbz_list.toOwnedSlice(allocator);
                }
                pub fn decodeFromUnknownFieldsAlloc(message: anytype, allocator: std.mem.Allocator) ![][]const u8 {
                    return try decodeAllRaw(allocator, message.unknownFields());
                }
                pub fn decodeAllFromUnknown(message: anytype, allocator: std.mem.Allocator) ![][]const u8 {
                    return try decodeFromUnknownFieldsAlloc(message, allocator);
                }
                pub fn decodeFirstFromUnknown(message: anytype, allocator: std.mem.Allocator) !?[]const u8 {
                    const _pbz_values = try decodeFromUnknownFieldsAlloc(message, allocator);
                    defer allocator.free(_pbz_values);
                    return if (_pbz_values.len == 0) null else _pbz_values[_pbz_values.len - 1];
                }
            };
            pub const payloads = struct {
                pub const number = 103;
                pub const extendee = ".demo.extgen.Host";
                pub const extendee_has_type_ref = true;
                pub const extendee_type_ref = Host;
                pub const cardinality = "repeated";
                pub const value_type = "demo.extgen.Payload";
                pub const value_has_type_ref = true;
                pub const value_type_ref = Payload;
                pub const value_has_enum_ref = false;
                pub const value_enum_ref = void;
                pub const zig_type = "[]const []const u8";
                pub const typed_zig_type = "[]const Payload";
                pub const has_default = false;
                pub const default_value = "";
                pub fn hasOn(message: Host) !bool {
                    return try hasInUnknown(message);
                }
                pub fn countOn(message: Host) !usize {
                    return try countInUnknown(message);
                }
                pub fn clearOn(message: *Host, allocator: std.mem.Allocator) !void {
                    try clearFromUnknown(message, allocator);
                }
                pub fn getOn(message: Host, allocator: std.mem.Allocator) ![][]const u8 {
                    return try decodeAllFromUnknown(message, allocator);
                }
                pub fn addOn(message: *Host, allocator: std.mem.Allocator, value: []const u8) !void {
                    try appendToUnknown(message, allocator, value);
                }
                pub fn appendAllOn(message: *Host, allocator: std.mem.Allocator, values: []const []const u8) !void {
                    try appendAllToUnknown(message, allocator, values);
                }
                pub fn replaceAllOn(message: *Host, allocator: std.mem.Allocator, values: []const []const u8) !void {
                    try replaceAllInUnknown(message, allocator, values);
                }
                pub fn addMessageOn(message: *Host, allocator: std.mem.Allocator, value: Payload) !void {
                    const _pbz_payload = try value.encode(allocator);
                    defer allocator.free(_pbz_payload);
                    try appendToUnknown(message, allocator, _pbz_payload);
                }
                pub fn getMessagesOn(message: Host, allocator: std.mem.Allocator) ![]Payload {
                    const _pbz_payloads = try decodeAllFromUnknown(message, allocator);
                    defer allocator.free(_pbz_payloads);
                    var _pbz_list: std.ArrayList(Payload) = .empty;
                    errdefer { for (_pbz_list.items) |*item| item.deinit(allocator); _pbz_list.deinit(allocator); }
                    for (_pbz_payloads) |_pbz_payload| try _pbz_list.append(allocator, try Payload.decode(allocator, _pbz_payload));
                    return try _pbz_list.toOwnedSlice(allocator);
                }
                pub fn write(w: *pbz.Writer, value: []const u8) !void {
                    try w.writeMessage(103, value);
                }
                pub fn encodeRaw(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
                    var w = pbz.Writer.init(allocator);
                    errdefer w.deinit();
                    try write(&w, value);
                    return try w.toOwnedSlice();
                }
                pub fn appendToUnknown(message: anytype, allocator: std.mem.Allocator, value: []const u8) !void {
                    const _pbz_raw = try encodeRaw(allocator, value);
                    defer allocator.free(_pbz_raw);
                    try message.appendUnknownRaw(allocator, _pbz_raw);
                }
                pub fn hasInUnknown(message: anytype) !bool {
                    return try message.hasUnknownFieldNumber(number);
                }
                pub fn countInUnknown(message: anytype) !usize {
                    return try message.unknownFieldCountByNumber(number);
                }
                pub fn clearFromUnknown(message: anytype, allocator: std.mem.Allocator) !void {
                    try message.clearUnknownFieldsByNumber(allocator, number);
                }
                pub fn replaceInUnknown(message: anytype, allocator: std.mem.Allocator, value: []const u8) !void {
                    try clearFromUnknown(message, allocator);
                    try appendToUnknown(message, allocator, value);
                }
                pub fn writeAll(w: *pbz.Writer, values: []const []const u8) !void {
                    for (values) |_pbz_value| try write(w, _pbz_value);
                }
                pub fn encodeAllRaw(allocator: std.mem.Allocator, values: []const []const u8) ![]u8 {
                    var w = pbz.Writer.init(allocator);
                    errdefer w.deinit();
                    try writeAll(&w, values);
                    return try w.toOwnedSlice();
                }
                pub fn appendAllToUnknown(message: anytype, allocator: std.mem.Allocator, values: []const []const u8) !void {
                    for (values) |_pbz_value| try appendToUnknown(message, allocator, _pbz_value);
                }
                pub fn replaceAllInUnknown(message: anytype, allocator: std.mem.Allocator, values: []const []const u8) !void {
                    try clearFromUnknown(message, allocator);
                    try appendAllToUnknown(message, allocator, values);
                }
                pub fn decodeValue(r: *pbz.Reader) ![]const u8 {
                    return try r.readBytes();
                }
                pub fn decodeRaw(raw: []const u8) !?[]const u8 {
                    var r = pbz.Reader.init(raw);
                    const _pbz_tag = (try r.nextTag()) orelse return null;
                    if (_pbz_tag.number != number or _pbz_tag.wire_type != .length_delimited) return null;
                    const _pbz_value = try decodeValue(&r);
                    if (!r.eof()) return error.InvalidWireType;
                    return _pbz_value;
                }
                pub fn decodeAllRaw(allocator: std.mem.Allocator, raw_fields: []const []const u8) ![][]const u8 {
                    var _pbz_list: std.ArrayList([]const u8) = .empty;
                    errdefer _pbz_list.deinit(allocator);
                    for (raw_fields) |_pbz_raw| {
                        if (try decodeRaw(_pbz_raw)) |_pbz_value| try _pbz_list.append(allocator, _pbz_value);
                    }
                    return try _pbz_list.toOwnedSlice(allocator);
                }
                pub fn decodeFromUnknownFieldsAlloc(message: anytype, allocator: std.mem.Allocator) ![][]const u8 {
                    return try decodeAllRaw(allocator, message.unknownFields());
                }
                pub fn decodeAllFromUnknown(message: anytype, allocator: std.mem.Allocator) ![][]const u8 {
                    return try decodeFromUnknownFieldsAlloc(message, allocator);
                }
                pub fn decodeFirstFromUnknown(message: anytype, allocator: std.mem.Allocator) !?[]const u8 {
                    const _pbz_values = try decodeFromUnknownFieldsAlloc(message, allocator);
                    defer allocator.free(_pbz_values);
                    return if (_pbz_values.len == 0) null else _pbz_values[_pbz_values.len - 1];
                }
                pub fn decodeAppend(allocator: std.mem.Allocator, list: *std.ArrayList([]const u8), r: *pbz.Reader) !void {
                    try list.append(allocator, try decodeValue(r));
                }
                pub fn decodeAppendRaw(allocator: std.mem.Allocator, list: *std.ArrayList([]const u8), raw: []const u8) !void {
                    if (try decodeRaw(raw)) |_pbz_value| try list.append(allocator, _pbz_value);
                }
            };
            pub const role = struct {
                pub const number = 104;
                pub const extendee = ".demo.extgen.Host";
                pub const extendee_has_type_ref = true;
                pub const extendee_type_ref = Host;
                pub const cardinality = "optional";
                pub const value_type = "demo.extgen.Role";
                pub const value_has_type_ref = false;
                pub const value_type_ref = void;
                pub const value_has_enum_ref = true;
                pub const value_enum_ref = Role;
                pub const zig_type = "i32";
                pub const typed_zig_type = "i32";
                pub const has_default = true;
                pub const default_value = "2";
                pub const default_value_zig: i32 = 2;
                pub fn hasOn(message: Host) !bool {
                    return try hasInUnknown(message);
                }
                pub fn countOn(message: Host) !usize {
                    return try countInUnknown(message);
                }
                pub fn clearOn(message: *Host, allocator: std.mem.Allocator) !void {
                    try clearFromUnknown(message, allocator);
                }
                pub fn getOn(message: Host, allocator: std.mem.Allocator) !?i32 {
                    return try decodeFirstFromUnknown(message, allocator);
                }
                pub fn getOrDefaultOn(message: Host, allocator: std.mem.Allocator) !i32 {
                    return (try getOn(message, allocator)) orelse default_value_zig;
                }
                pub fn setOn(message: *Host, allocator: std.mem.Allocator, value: i32) !void {
                    try replaceInUnknown(message, allocator, value);
                }
                pub fn getEnumOn(message: Host, allocator: std.mem.Allocator) !?Role {
                    const _pbz_raw = (try getOn(message, allocator)) orelse return null;
                    return Role.fromInt(_pbz_raw);
                }
                pub fn getEnumOrDefaultOn(message: Host, allocator: std.mem.Allocator) !Role {
                    return (try getEnumOn(message, allocator)) orelse Role.fromInt(default_value_zig) orelse unreachable;
                }
                pub fn setEnumOn(message: *Host, allocator: std.mem.Allocator, value: Role) !void {
                    try setOn(message, allocator, value.toInt());
                }
                pub fn write(w: *pbz.Writer, value: i32) !void {
                    try w.writeInt32(104, value);
                }
                pub fn encodeRaw(allocator: std.mem.Allocator, value: i32) ![]u8 {
                    var w = pbz.Writer.init(allocator);
                    errdefer w.deinit();
                    try write(&w, value);
                    return try w.toOwnedSlice();
                }
                pub fn appendToUnknown(message: anytype, allocator: std.mem.Allocator, value: i32) !void {
                    const _pbz_raw = try encodeRaw(allocator, value);
                    defer allocator.free(_pbz_raw);
                    try message.appendUnknownRaw(allocator, _pbz_raw);
                }
                pub fn hasInUnknown(message: anytype) !bool {
                    return try message.hasUnknownFieldNumber(number);
                }
                pub fn countInUnknown(message: anytype) !usize {
                    return try message.unknownFieldCountByNumber(number);
                }
                pub fn clearFromUnknown(message: anytype, allocator: std.mem.Allocator) !void {
                    try message.clearUnknownFieldsByNumber(allocator, number);
                }
                pub fn replaceInUnknown(message: anytype, allocator: std.mem.Allocator, value: i32) !void {
                    try clearFromUnknown(message, allocator);
                    try appendToUnknown(message, allocator, value);
                }
                pub fn decodeValue(r: *pbz.Reader) !i32 {
                    return try r.readInt32();
                }
                pub fn decodeRaw(raw: []const u8) !?i32 {
                    var r = pbz.Reader.init(raw);
                    const _pbz_tag = (try r.nextTag()) orelse return null;
                    if (_pbz_tag.number != number or _pbz_tag.wire_type != .varint) return null;
                    const _pbz_value = try decodeValue(&r);
                    if (!r.eof()) return error.InvalidWireType;
                    return _pbz_value;
                }
                pub fn decodeAllRaw(allocator: std.mem.Allocator, raw_fields: []const []const u8) ![]i32 {
                    var _pbz_list: std.ArrayList(i32) = .empty;
                    errdefer _pbz_list.deinit(allocator);
                    for (raw_fields) |_pbz_raw| {
                        if (try decodeRaw(_pbz_raw)) |_pbz_value| try _pbz_list.append(allocator, _pbz_value);
                    }
                    return try _pbz_list.toOwnedSlice(allocator);
                }
                pub fn decodeFromUnknownFieldsAlloc(message: anytype, allocator: std.mem.Allocator) ![]i32 {
                    return try decodeAllRaw(allocator, message.unknownFields());
                }
                pub fn decodeAllFromUnknown(message: anytype, allocator: std.mem.Allocator) ![]i32 {
                    return try decodeFromUnknownFieldsAlloc(message, allocator);
                }
                pub fn decodeFirstFromUnknown(message: anytype, allocator: std.mem.Allocator) !?i32 {
                    const _pbz_values = try decodeFromUnknownFieldsAlloc(message, allocator);
                    defer allocator.free(_pbz_values);
                    return if (_pbz_values.len == 0) null else _pbz_values[_pbz_values.len - 1];
                }
            };
        };

    };

};
