const std = @import("std");
const wire = @import("wire.zig");
const schema = @import("schema.zig");
const parser = @import("parser.zig");

pub const DecodeError = wire.Error || std.mem.Allocator.Error || error{TypeMismatch};
pub const EncodeError = wire.Error || std.mem.Allocator.Error || error{TypeMismatch};
pub const ValidationError = error{MissingRequiredField};

pub const Value = union(enum) {
    double: f64,
    float: f32,
    int32: i32,
    int64: i64,
    uint32: u32,
    uint64: u64,
    sint32: i32,
    sint64: i64,
    fixed32: u32,
    fixed64: u64,
    sfixed32: i32,
    sfixed64: i64,
    boolean: bool,
    string: []u8,
    bytes: []u8,
    enumeration: i32,
    message: *DynamicMessage,
    group: *DynamicMessage,
};

pub const FieldValue = struct {
    descriptor: *const schema.FieldDescriptor,
    values: std.ArrayList(Value) = .empty,

    pub fn deinit(self: *FieldValue, allocator: std.mem.Allocator) void {
        for (self.values.items) |*value| deinitValue(value, allocator);
        self.values.deinit(allocator);
        self.* = undefined;
    }
};

pub const UnknownField = struct {
    number: wire.FieldNumber,
    wire_type: wire.WireType,
    data: []u8,

    pub fn deinit(self: *UnknownField, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
        self.* = undefined;
    }
};

pub const DynamicMessage = struct {
    allocator: std.mem.Allocator,
    descriptor: *const schema.MessageDescriptor,
    fields: std.ArrayList(FieldValue) = .empty,
    unknown_fields: std.ArrayList(UnknownField) = .empty,

    pub fn init(allocator: std.mem.Allocator, descriptor: *const schema.MessageDescriptor) DynamicMessage {
        return .{ .allocator = allocator, .descriptor = descriptor };
    }

    pub fn deinit(self: *DynamicMessage) void {
        for (self.fields.items) |*field| field.deinit(self.allocator);
        self.fields.deinit(self.allocator);
        for (self.unknown_fields.items) |*field| field.deinit(self.allocator);
        self.unknown_fields.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn clear(self: *DynamicMessage) void {
        for (self.fields.items) |*field| field.deinit(self.allocator);
        self.fields.clearRetainingCapacity();
        for (self.unknown_fields.items) |*field| field.deinit(self.allocator);
        self.unknown_fields.clearRetainingCapacity();
    }

    pub fn get(self: *const DynamicMessage, name: []const u8) ?*const FieldValue {
        for (self.fields.items) |*field| {
            if (std.mem.eql(u8, field.descriptor.name, name)) return field;
        }
        return null;
    }

    pub fn getByNumber(self: *const DynamicMessage, number: wire.FieldNumber) ?*const FieldValue {
        for (self.fields.items) |*field| {
            if (field.descriptor.number == number) return field;
        }
        return null;
    }

    pub fn add(self: *DynamicMessage, field: *const schema.FieldDescriptor, value: Value) std.mem.Allocator.Error!void {
        var entry = try self.getOrCreateMutable(field);
        if (field.cardinality != .repeated and entry.values.items.len != 0) {
            deinitValue(&entry.values.items[0], self.allocator);
            entry.values.items.len = 0;
        }
        try entry.values.append(self.allocator, value);
    }

    pub fn addClone(self: *DynamicMessage, field: *const schema.FieldDescriptor, value: Value) std.mem.Allocator.Error!void {
        try self.add(field, try cloneValue(self.allocator, value));
    }

    pub fn validateRequired(self: *const DynamicMessage) ValidationError!void {
        for (self.descriptor.fields.items) |*field| {
            if (field.cardinality == .required and self.getByNumber(field.number) == null) return error.MissingRequiredField;
        }
        for (self.fields.items) |*entry| {
            for (entry.values.items) |value| switch (value) {
                .message => |message| try message.validateRequired(),
                .group => |message| try message.validateRequired(),
                else => {},
            };
        }
    }

    fn getOrCreateMutable(self: *DynamicMessage, field: *const schema.FieldDescriptor) std.mem.Allocator.Error!*FieldValue {
        for (self.fields.items) |*entry| {
            if (entry.descriptor.number == field.number) return entry;
        }
        try self.fields.append(self.allocator, .{ .descriptor = field });
        return &self.fields.items[self.fields.items.len - 1];
    }

    pub fn encode(self: *const DynamicMessage, file: *const schema.FileDescriptor, writer: *wire.Writer) EncodeError!void {
        for (self.fields.items) |*entry| {
            if (entry.descriptor.resolvedPacked(file)) {
                try encodePacked(entry.descriptor, entry.values.items, writer);
            } else {
                for (entry.values.items) |value| try encodeField(entry.descriptor, value, file, writer);
            }
        }
        for (self.unknown_fields.items) |unknown| try writer.appendSlice(unknown.data);
    }

    pub fn encoded(self: *const DynamicMessage, file: *const schema.FileDescriptor) EncodeError![]u8 {
        var writer = wire.Writer.init(self.allocator);
        errdefer writer.deinit();
        try self.encode(file, &writer);
        return try writer.toOwnedSlice();
    }

    pub fn decode(self: *DynamicMessage, file: *const schema.FileDescriptor, bytes: []const u8) DecodeError!void {
        self.clear();
        var reader = wire.Reader.init(bytes);
        try self.decodeStream(file, &reader, null);
    }

    fn decodeStream(self: *DynamicMessage, file: *const schema.FileDescriptor, reader: *wire.Reader, end_group: ?wire.FieldNumber) DecodeError!void {
        while (try reader.nextTag()) |tag| {
            if (tag.wire_type == .end_group) {
                if (end_group) |expected| {
                    if (tag.number != expected) return error.InvalidFieldNumber;
                    return;
                }
                return error.InvalidWireType;
            }

            const start = reader.position() - wire.encodedVarintSize(try tag.encode());
            const field = self.descriptor.findFieldByNumber(tag.number) orelse {
                try reader.skipValue(tag);
                const raw = try self.allocator.dupe(u8, reader.input[start..reader.position()]);
                self.unknown_fields.append(self.allocator, .{
                    .number = tag.number,
                    .wire_type = tag.wire_type,
                    .data = raw,
                }) catch |err| {
                    self.allocator.free(raw);
                    return err;
                };
                continue;
            };

            if (field.kind == .group) {
                if (tag.wire_type != .start_group) return error.InvalidWireType;
                var value = try decodeGroupValue(self.allocator, file, self.descriptor, field, reader);
                self.add(field, value) catch |err| {
                    deinitValue(&value, self.allocator);
                    return err;
                };
                continue;
            }

            if (tag.wire_type == .length_delimited and field.resolvedPacked(file) and field.kind.packable()) {
                const payload = try reader.readBytes();
                var packed_reader = wire.Reader.init(payload);
                while (!packed_reader.eof()) {
                    const value = try decodeScalarLike(field.kind, &packed_reader);
                    try self.add(field, value);
                }
                continue;
            }

            if (tag.wire_type != field.kind.wireType()) return error.InvalidWireType;
            var value = try decodeValue(self.allocator, file, self.descriptor, field.kind, reader);
            self.add(field, value) catch |err| {
                deinitValue(&value, self.allocator);
                return err;
            };
        }
        if (end_group != null) return error.TruncatedInput;
    }
};

fn encodeField(field: *const schema.FieldDescriptor, value: Value, file: *const schema.FileDescriptor, writer: *wire.Writer) EncodeError!void {
    switch (field.kind) {
        .scalar => |scalar| try encodeScalar(field.number, scalar, value, writer),
        .enumeration => switch (value) {
            .enumeration => |v| {
                try writer.writeTag(field.number, .varint);
                try writer.writeVarint(@as(u64, @bitCast(@as(i64, v))));
            },
            else => return error.TypeMismatch,
        },
        .message => switch (value) {
            .message => |message| {
                var nested_writer = wire.Writer.init(writer.allocator);
                defer nested_writer.deinit();
                // Nested message packing depends on its own file-level features only for repeated scalar fields.
                try message.encode(file, &nested_writer);
                try writer.writeMessage(field.number, nested_writer.slice());
            },
            else => return error.TypeMismatch,
        },
        .group => switch (value) {
            .group => |message| {
                try writer.writeTag(field.number, .start_group);
                try message.encode(file, writer);
                try writer.writeTag(field.number, .end_group);
            },
            else => return error.TypeMismatch,
        },
        .map => return error.TypeMismatch,
    }
}

fn encodePacked(field: *const schema.FieldDescriptor, values: []const Value, writer: *wire.Writer) EncodeError!void {
    var packed_writer = wire.Writer.init(writer.allocator);
    defer packed_writer.deinit();
    for (values) |value| try encodeScalarPayload(field.kind, value, &packed_writer);
    try writer.writeBytes(field.number, packed_writer.slice());
}

fn encodeScalar(number: wire.FieldNumber, scalar: schema.ScalarType, value: Value, writer: *wire.Writer) EncodeError!void {
    try writer.writeTag(number, scalar.wireType());
    try encodeScalarPayload(.{ .scalar = scalar }, value, writer);
}

fn encodeScalarPayload(kind: schema.FieldKind, value: Value, writer: *wire.Writer) EncodeError!void {
    switch (kind) {
        .scalar => |scalar| switch (scalar) {
            .double => if (value == .double) try writer.writeRawLittle(u64, @bitCast(value.double)) else return error.TypeMismatch,
            .float => if (value == .float) try writer.writeRawLittle(u32, @bitCast(value.float)) else return error.TypeMismatch,
            .int32 => if (value == .int32) try writer.writeVarint(@as(u64, @bitCast(@as(i64, value.int32)))) else return error.TypeMismatch,
            .int64 => if (value == .int64) try writer.writeVarint(@as(u64, @bitCast(value.int64))) else return error.TypeMismatch,
            .uint32 => if (value == .uint32) try writer.writeVarint(value.uint32) else return error.TypeMismatch,
            .uint64 => if (value == .uint64) try writer.writeVarint(value.uint64) else return error.TypeMismatch,
            .sint32 => if (value == .sint32) try writer.writeVarint(wire.zigZagEncode32(value.sint32)) else return error.TypeMismatch,
            .sint64 => if (value == .sint64) try writer.writeVarint(wire.zigZagEncode64(value.sint64)) else return error.TypeMismatch,
            .fixed32 => if (value == .fixed32) try writer.writeRawLittle(u32, value.fixed32) else return error.TypeMismatch,
            .fixed64 => if (value == .fixed64) try writer.writeRawLittle(u64, value.fixed64) else return error.TypeMismatch,
            .sfixed32 => if (value == .sfixed32) try writer.writeRawLittle(i32, value.sfixed32) else return error.TypeMismatch,
            .sfixed64 => if (value == .sfixed64) try writer.writeRawLittle(i64, value.sfixed64) else return error.TypeMismatch,
            .bool => if (value == .boolean) try writer.writeVarint(if (value.boolean) 1 else 0) else return error.TypeMismatch,
            .string => if (value == .string) {
                try writer.writeVarint(value.string.len);
                try writer.appendSlice(value.string);
            } else return error.TypeMismatch,
            .bytes => if (value == .bytes) {
                try writer.writeVarint(value.bytes.len);
                try writer.appendSlice(value.bytes);
            } else return error.TypeMismatch,
        },
        .enumeration => if (value == .enumeration) try writer.writeVarint(@as(u64, @bitCast(@as(i64, value.enumeration)))) else return error.TypeMismatch,
        else => return error.TypeMismatch,
    }
}

fn decodeValue(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    current: *const schema.MessageDescriptor,
    kind: schema.FieldKind,
    reader: *wire.Reader,
) DecodeError!Value {
    return switch (kind) {
        .scalar => |scalar| switch (scalar) {
            .string => .{ .string = try allocator.dupe(u8, try reader.readBytes()) },
            .bytes => .{ .bytes = try allocator.dupe(u8, try reader.readBytes()) },
            else => try decodeScalarLike(kind, reader),
        },
        .enumeration => try decodeScalarLike(kind, reader),
        .message => |name| blk: {
            const payload = try reader.readBytes();
            const descriptor = resolveMessageDescriptor(file, current, name) orelse return error.TypeMismatch;
            const message = try allocator.create(DynamicMessage);
            message.* = DynamicMessage.init(allocator, descriptor);
            errdefer {
                message.deinit();
                allocator.destroy(message);
            }
            try message.decode(file, payload);
            break :blk .{ .message = message };
        },
        .group => error.TypeMismatch,
        .map => error.TypeMismatch,
    };
}

fn decodeGroupValue(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    current: *const schema.MessageDescriptor,
    field: *const schema.FieldDescriptor,
    reader: *wire.Reader,
) DecodeError!Value {
    const name = switch (field.kind) {
        .group => |group_name| group_name,
        else => return error.TypeMismatch,
    };
    const descriptor = resolveMessageDescriptor(file, current, name) orelse return error.TypeMismatch;
    const message = try allocator.create(DynamicMessage);
    message.* = DynamicMessage.init(allocator, descriptor);
    errdefer {
        message.deinit();
        allocator.destroy(message);
    }
    try message.decodeStream(file, reader, field.number);
    return .{ .group = message };
}

fn resolveMessageDescriptor(file: *const schema.FileDescriptor, current: *const schema.MessageDescriptor, name: []const u8) ?*const schema.MessageDescriptor {
    const trimmed = if (std.mem.startsWith(u8, name, ".")) name[1..] else name;
    const leaf = if (std.mem.lastIndexOfScalar(u8, trimmed, '.')) |idx| trimmed[idx + 1 ..] else trimmed;
    if (std.mem.eql(u8, current.name, trimmed) or std.mem.eql(u8, current.name, leaf)) return current;
    if (current.findMessageDeep(trimmed)) |message| return message;
    return file.findMessageDeep(trimmed);
}

fn decodeScalarLike(kind: schema.FieldKind, reader: *wire.Reader) DecodeError!Value {
    return switch (kind) {
        .scalar => |scalar| switch (scalar) {
            .double => .{ .double = try reader.readDouble() },
            .float => .{ .float = try reader.readFloat() },
            .int32 => .{ .int32 = try reader.readInt32() },
            .int64 => .{ .int64 = try reader.readInt64() },
            .uint32 => .{ .uint32 = try reader.readUInt32() },
            .uint64 => .{ .uint64 = try reader.readUInt64() },
            .sint32 => .{ .sint32 = try reader.readSInt32() },
            .sint64 => .{ .sint64 = try reader.readSInt64() },
            .fixed32 => .{ .fixed32 = try reader.readFixed32() },
            .fixed64 => .{ .fixed64 = try reader.readFixed64() },
            .sfixed32 => .{ .sfixed32 = try reader.readSFixed32() },
            .sfixed64 => .{ .sfixed64 = try reader.readSFixed64() },
            .bool => .{ .boolean = try reader.readBool() },
            .string => return error.TypeMismatch,
            .bytes => return error.TypeMismatch,
        },
        .enumeration => .{ .enumeration = try reader.readInt32() },
        else => return error.TypeMismatch,
    };
}

pub fn decodeBytesValue(allocator: std.mem.Allocator, scalar: schema.ScalarType, reader: *wire.Reader) DecodeError!Value {
    switch (scalar) {
        .string => return .{ .string = try allocator.dupe(u8, try reader.readBytes()) },
        .bytes => return .{ .bytes = try allocator.dupe(u8, try reader.readBytes()) },
        else => return decodeScalarLike(.{ .scalar = scalar }, reader),
    }
}

pub fn deinitValue(value: *Value, allocator: std.mem.Allocator) void {
    switch (value.*) {
        .string => |bytes| allocator.free(bytes),
        .bytes => |bytes| allocator.free(bytes),
        .message => |message| {
            message.deinit();
            allocator.destroy(message);
        },
        .group => |message| {
            message.deinit();
            allocator.destroy(message);
        },
        else => {},
    }
    value.* = undefined;
}

pub fn cloneValue(allocator: std.mem.Allocator, value: Value) std.mem.Allocator.Error!Value {
    return switch (value) {
        .string => |bytes| .{ .string = try allocator.dupe(u8, bytes) },
        .bytes => |bytes| .{ .bytes = try allocator.dupe(u8, bytes) },
        .message => |message| blk: {
            const cloned = try allocator.create(DynamicMessage);
            cloned.* = DynamicMessage.init(allocator, message.descriptor);
            errdefer {
                cloned.deinit();
                allocator.destroy(cloned);
            }
            for (message.fields.items) |*field| {
                for (field.values.items) |item| try cloned.add(field.descriptor, try cloneValue(allocator, item));
            }
            for (message.unknown_fields.items) |unknown| try cloned.unknown_fields.append(allocator, .{
                .number = unknown.number,
                .wire_type = unknown.wire_type,
                .data = try allocator.dupe(u8, unknown.data),
            });
            break :blk .{ .message = cloned };
        },
        .group => |message| blk: {
            const cloned = try allocator.create(DynamicMessage);
            cloned.* = DynamicMessage.init(allocator, message.descriptor);
            errdefer {
                cloned.deinit();
                allocator.destroy(cloned);
            }
            for (message.fields.items) |*field| {
                for (field.values.items) |item| try cloned.add(field.descriptor, try cloneValue(allocator, item));
            }
            break :blk .{ .group = cloned };
        },
        else => value,
    };
}

test "dynamic message encodes decodes scalar and preserves unknown fields" {
    const allocator = std.testing.allocator;
    var file = schema.FileDescriptor.init(allocator);
    defer file.deinit();
    file.setSyntax(.proto3);

    var msg = schema.MessageDescriptor{ .name = "Person" };
    try msg.fields.append(allocator, .{ .name = "id", .number = 1, .kind = .{ .scalar = .int32 } });
    try msg.fields.append(allocator, .{ .name = "name", .number = 2, .kind = .{ .scalar = .string } });
    try file.messages.append(allocator, msg);

    var dyn = DynamicMessage.init(allocator, &file.messages.items[0]);
    defer dyn.deinit();
    try dyn.add(file.messages.items[0].findField("id").?, .{ .int32 = 42 });

    var w = wire.Writer.init(allocator);
    defer w.deinit();
    try dyn.encode(&file, &w);
    try w.writeUInt32(99, 7);

    var decoded = DynamicMessage.init(allocator, &file.messages.items[0]);
    defer decoded.deinit();
    try decoded.decode(&file, w.slice());
    try std.testing.expectEqual(@as(i32, 42), decoded.get("id").?.values.items[0].int32);
    try std.testing.expectEqual(@as(usize, 1), decoded.unknown_fields.items.len);
}

test "dynamic proto2 round-trips required optional repeated packed message and group fields" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto2";
        \\package demo;
        \\message Child { optional string label = 1; }
        \\message Parent {
        \\  required int32 id = 1;
        \\  optional string name = 2 [default = "anon"];
        \\  optional bytes blob = 3;
        \\  repeated sint32 nums = 4 [packed = true];
        \\  optional Child child = 5;
        \\  optional group Legacy = 6 { optional bool flag = 7; }
        \\}
    ;
    var file = try parser.Parser.parse(allocator, source);
    defer file.deinit();
    const parent_desc = file.findMessage("Parent").?;
    const child_desc = file.findMessage("Child").?;
    const group_desc = parent_desc.findMessageDeep("Legacy").?;

    var message = DynamicMessage.init(allocator, parent_desc);
    defer message.deinit();
    try std.testing.expectError(error.MissingRequiredField, message.validateRequired());

    try message.add(parent_desc.findField("id").?, .{ .int32 = 123 });
    try message.add(parent_desc.findField("name").?, .{ .string = try allocator.dupe(u8, "pb2") });
    try message.add(parent_desc.findField("blob").?, .{ .bytes = try allocator.dupe(u8, "raw") });
    try message.add(parent_desc.findField("nums").?, .{ .sint32 = -1 });
    try message.add(parent_desc.findField("nums").?, .{ .sint32 = 2 });

    const child = try allocator.create(DynamicMessage);
    child.* = DynamicMessage.init(allocator, child_desc);
    try child.add(child_desc.findField("label").?, .{ .string = try allocator.dupe(u8, "kid") });
    try message.add(parent_desc.findField("child").?, .{ .message = child });

    const group = try allocator.create(DynamicMessage);
    group.* = DynamicMessage.init(allocator, group_desc);
    try group.add(group_desc.findField("flag").?, .{ .boolean = true });
    try message.add(parent_desc.findField("Legacy").?, .{ .group = group });
    try message.validateRequired();

    const encoded = try message.encoded(&file);
    defer allocator.free(encoded);

    var decoded = DynamicMessage.init(allocator, parent_desc);
    defer decoded.deinit();
    try decoded.decode(&file, encoded);
    try decoded.validateRequired();
    try std.testing.expectEqual(@as(i32, 123), decoded.get("id").?.values.items[0].int32);
    try std.testing.expectEqualSlices(u8, "pb2", decoded.get("name").?.values.items[0].string);
    try std.testing.expectEqualSlices(u8, "raw", decoded.get("blob").?.values.items[0].bytes);
    try std.testing.expectEqual(@as(usize, 2), decoded.get("nums").?.values.items.len);
    try std.testing.expectEqual(@as(i32, -1), decoded.get("nums").?.values.items[0].sint32);
    try std.testing.expectEqual(@as(i32, 2), decoded.get("nums").?.values.items[1].sint32);
    try std.testing.expectEqualSlices(u8, "kid", decoded.get("child").?.values.items[0].message.get("label").?.values.items[0].string);
    try std.testing.expect(decoded.get("Legacy").?.values.items[0].group.get("flag").?.values.items[0].boolean);
}
