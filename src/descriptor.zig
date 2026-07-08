const std = @import("std");
const wire = @import("wire.zig");
const schema = @import("schema.zig");

pub const Error = wire.Error || std.mem.Allocator.Error || error{InvalidFieldType};

pub fn encodeFileDescriptorProto(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, name: []const u8) Error![]u8 {
    var writer = wire.Writer.init(allocator);
    errdefer writer.deinit();
    try writeFileDescriptorProto(allocator, file, name, &writer);
    return try writer.toOwnedSlice();
}

pub fn writeFileDescriptorProto(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, name: []const u8, writer: *wire.Writer) Error!void {
    const file_name = if (file.name.len != 0) file.name else name;
    if (file_name.len != 0) try writer.writeString(1, file_name);
    if (file.package.len != 0) try writer.writeString(2, file.package);
    for (file.imports.items) |import| try writer.writeString(3, import.path);
    for (file.messages.items) |*message| try writeMessageDescriptor(allocator, file, message, "", 4, writer);
    for (file.enums.items) |*enumeration| try writeEnumDescriptor(allocator, enumeration, 5, writer);
    for (file.services.items) |*service| try writeServiceDescriptor(allocator, service, 6, writer);
    for (file.extensions.items) |*field| try writeFieldDescriptor(allocator, file, null, field, 7, writer);
    if (file.syntax == .editions or hasFeatureOptions(file)) try writeFileOptions(allocator, file, 8, writer);
    try writer.writeString(12, switch (file.syntax) {
        .proto2 => "proto2",
        .proto3 => "proto3",
        .editions => "editions",
    });
    if (file.syntax == .editions) try writer.writeInt32(14, @intFromEnum(file.edition));
}

pub fn encodeFileDescriptorSet(allocator: std.mem.Allocator, files: []const *const schema.FileDescriptor) Error![]u8 {
    var writer = wire.Writer.init(allocator);
    errdefer writer.deinit();
    try writeFileDescriptorSet(allocator, files, &writer);
    return try writer.toOwnedSlice();
}

pub fn writeFileDescriptorSet(allocator: std.mem.Allocator, files: []const *const schema.FileDescriptor, writer: *wire.Writer) Error!void {
    for (files) |file| {
        var file_writer = wire.Writer.init(allocator);
        defer file_writer.deinit();
        try writeFileDescriptorProto(allocator, file, file.name, &file_writer);
        try writer.writeMessage(1, file_writer.slice());
    }
}

fn writeMessageDescriptor(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    message: *const schema.MessageDescriptor,
    parent_scope: []const u8,
    field_number: wire.FieldNumber,
    writer: *wire.Writer,
) Error!void {
    var tmp = wire.Writer.init(allocator);
    defer tmp.deinit();

    try tmp.writeString(1, message.name);
    const scope = try joinScope(allocator, parent_scope, message.name);
    defer allocator.free(scope);

    for (message.fields.items) |*field| try writeFieldDescriptor(allocator, file, message, field, 2, &tmp);
    for (message.messages.items) |*nested| try writeMessageDescriptor(allocator, file, nested, scope, 3, &tmp);
    for (message.fields.items) |*field| {
        if (field.kind == .map) try writeMapEntryDescriptor(allocator, file, scope, field, 3, &tmp);
    }
    for (message.enums.items) |*enumeration| try writeEnumDescriptor(allocator, enumeration, 4, &tmp);
    for (message.extension_ranges.items) |*range| try writeExtensionRange(allocator, range, 5, &tmp);
    for (message.extensions.items) |*field| try writeFieldDescriptor(allocator, file, message, field, 6, &tmp);
    for (message.oneofs.items) |*oneof| try writeOneofDescriptor(allocator, oneof, 8, &tmp);
    for (message.reserved_ranges.items) |range| try writeReservedRange(allocator, range, 9, &tmp);
    for (message.reserved_names.items) |reserved_name| try tmp.writeString(10, reserved_name);

    try writer.writeMessage(field_number, tmp.slice());
}

fn writeMapEntryDescriptor(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    parent_scope: []const u8,
    field: *const schema.FieldDescriptor,
    field_number: wire.FieldNumber,
    writer: *wire.Writer,
) Error!void {
    const map_type = switch (field.kind) {
        .map => |map| map,
        else => return error.InvalidFieldType,
    };
    var tmp = wire.Writer.init(allocator);
    defer tmp.deinit();

    const entry_name = try mapEntryName(allocator, field.name);
    defer allocator.free(entry_name);
    try tmp.writeString(1, entry_name);

    var key_field = schema.FieldDescriptor{
        .name = "key",
        .number = 1,
        .cardinality = .optional,
        .kind = .{ .scalar = map_type.key },
    };
    try writeFieldDescriptor(allocator, file, null, &key_field, 2, &tmp);

    var value_field = schema.FieldDescriptor{
        .name = "value",
        .number = 2,
        .cardinality = .optional,
        .kind = map_type.value.*,
    };
    try writeFieldDescriptor(allocator, file, null, &value_field, 2, &tmp);

    try writeMessageOptionsMapEntry(allocator, 7, &tmp);
    _ = parent_scope;
    try writer.writeMessage(field_number, tmp.slice());
}

fn writeFieldDescriptor(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    containing_message: ?*const schema.MessageDescriptor,
    field: *const schema.FieldDescriptor,
    field_number: wire.FieldNumber,
    writer: *wire.Writer,
) Error!void {
    var tmp = wire.Writer.init(allocator);
    defer tmp.deinit();

    try tmp.writeString(1, field.name);
    if (field.extendee) |extendee| try writeQualifiedName(allocator, file, extendee, 2, &tmp);
    try tmp.writeInt32(3, @intCast(field.number));
    try tmp.writeInt32(4, labelNumber(field.cardinality));
    try tmp.writeInt32(5, typeNumber(field.kind));
    switch (field.kind) {
        .message, .enumeration, .group => |type_name| try writeQualifiedName(allocator, file, type_name, 6, &tmp),
        .map => {
            const entry_name = try mapEntryName(allocator, field.name);
            defer allocator.free(entry_name);
            const scoped = if (containing_message) |message|
                try std.fmt.allocPrint(allocator, "{s}.{s}", .{ message.name, entry_name })
            else
                try allocator.dupe(u8, entry_name);
            defer allocator.free(scoped);
            try writeQualifiedName(allocator, file, scoped, 6, &tmp);
        },
        else => {},
    }
    if (field.default_value) |value| try writeDefaultValue(allocator, value, 7, &tmp);
    if (field.packed_override != null) try writeFieldOptions(allocator, field, 8, &tmp);
    if (field.oneof_name) |oneof_name| {
        if (containing_message) |message| {
            if (oneofIndex(message, oneof_name)) |index| try tmp.writeInt32(9, @intCast(index));
        }
    }
    if (field.json_name) |json_name| try tmp.writeString(10, json_name);
    if (field.proto3_optional) try tmp.writeBool(17, true);

    try writer.writeMessage(field_number, tmp.slice());
}

fn writeEnumDescriptor(allocator: std.mem.Allocator, enumeration: *const schema.EnumDescriptor, field_number: wire.FieldNumber, writer: *wire.Writer) Error!void {
    var tmp = wire.Writer.init(allocator);
    defer tmp.deinit();

    try tmp.writeString(1, enumeration.name);
    for (enumeration.values.items) |*value| try writeEnumValueDescriptor(allocator, value, 2, &tmp);
    for (enumeration.reserved_ranges.items) |range| try writeEnumReservedRange(allocator, range, 4, &tmp);
    for (enumeration.reserved_names.items) |reserved_name| try tmp.writeString(5, reserved_name);

    try writer.writeMessage(field_number, tmp.slice());
}

fn writeEnumValueDescriptor(allocator: std.mem.Allocator, value: *const schema.EnumValueDescriptor, field_number: wire.FieldNumber, writer: *wire.Writer) Error!void {
    var tmp = wire.Writer.init(allocator);
    defer tmp.deinit();

    try tmp.writeString(1, value.name);
    try tmp.writeInt32(2, value.number);

    try writer.writeMessage(field_number, tmp.slice());
}

fn writeOneofDescriptor(allocator: std.mem.Allocator, oneof: *const schema.OneofDescriptor, field_number: wire.FieldNumber, writer: *wire.Writer) Error!void {
    var tmp = wire.Writer.init(allocator);
    defer tmp.deinit();
    try tmp.writeString(1, oneof.name);
    try writer.writeMessage(field_number, tmp.slice());
}

fn writeExtensionRange(allocator: std.mem.Allocator, range: *const schema.ExtensionRange, field_number: wire.FieldNumber, writer: *wire.Writer) Error!void {
    var tmp = wire.Writer.init(allocator);
    defer tmp.deinit();
    try tmp.writeInt32(1, @intCast(range.start));
    if (range.end) |end| try tmp.writeInt32(2, @intCast(end));
    try writer.writeMessage(field_number, tmp.slice());
}

fn writeReservedRange(allocator: std.mem.Allocator, range: schema.ReservedRange, field_number: wire.FieldNumber, writer: *wire.Writer) Error!void {
    var tmp = wire.Writer.init(allocator);
    defer tmp.deinit();
    try tmp.writeInt32(1, @intCast(range.start));
    if (range.end) |end| try tmp.writeInt32(2, @intCast(end));
    try writer.writeMessage(field_number, tmp.slice());
}

fn writeEnumReservedRange(allocator: std.mem.Allocator, range: schema.ReservedRange, field_number: wire.FieldNumber, writer: *wire.Writer) Error!void {
    var tmp = wire.Writer.init(allocator);
    defer tmp.deinit();
    try tmp.writeInt32(1, @intCast(range.start));
    if (range.end) |end| try tmp.writeInt32(2, @intCast(end - 1));
    try writer.writeMessage(field_number, tmp.slice());
}

fn writeServiceDescriptor(allocator: std.mem.Allocator, service: *const schema.ServiceDescriptor, field_number: wire.FieldNumber, writer: *wire.Writer) Error!void {
    var tmp = wire.Writer.init(allocator);
    defer tmp.deinit();
    try tmp.writeString(1, service.name);
    for (service.methods.items) |*method| try writeMethodDescriptor(allocator, method, 2, &tmp);
    try writer.writeMessage(field_number, tmp.slice());
}

fn writeMethodDescriptor(allocator: std.mem.Allocator, method: *const schema.MethodDescriptor, field_number: wire.FieldNumber, writer: *wire.Writer) Error!void {
    var tmp = wire.Writer.init(allocator);
    defer tmp.deinit();
    try tmp.writeString(1, method.name);
    try tmp.writeString(2, method.input_type);
    try tmp.writeString(3, method.output_type);
    if (method.client_streaming) try tmp.writeBool(5, true);
    if (method.server_streaming) try tmp.writeBool(6, true);
    try writer.writeMessage(field_number, tmp.slice());
}

fn writeFileOptions(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, field_number: wire.FieldNumber, writer: *wire.Writer) Error!void {
    var tmp = wire.Writer.init(allocator);
    defer tmp.deinit();
    if (file.syntax == .editions or hasFeatureOptions(file)) try writeFeatureSet(allocator, file.features, 50, &tmp);
    try writer.writeMessage(field_number, tmp.slice());
}

fn writeMessageOptionsMapEntry(allocator: std.mem.Allocator, field_number: wire.FieldNumber, writer: *wire.Writer) Error!void {
    var tmp = wire.Writer.init(allocator);
    defer tmp.deinit();
    try tmp.writeBool(7, true);
    try writer.writeMessage(field_number, tmp.slice());
}

fn writeFieldOptions(allocator: std.mem.Allocator, field: *const schema.FieldDescriptor, field_number: wire.FieldNumber, writer: *wire.Writer) Error!void {
    var tmp = wire.Writer.init(allocator);
    defer tmp.deinit();
    if (field.packed_override) |is_packed| try tmp.writeBool(2, is_packed);
    try writer.writeMessage(field_number, tmp.slice());
}

fn writeFeatureSet(allocator: std.mem.Allocator, features: schema.FeatureSet, field_number: wire.FieldNumber, writer: *wire.Writer) Error!void {
    var tmp = wire.Writer.init(allocator);
    defer tmp.deinit();
    try tmp.writeInt32(1, switch (features.field_presence) {
        .explicit => 1,
        .implicit => 2,
        .legacy_required => 3,
    });
    try tmp.writeInt32(2, switch (features.enum_type) {
        .open => 1,
        .closed => 2,
    });
    try tmp.writeInt32(3, switch (features.repeated_field_encoding) {
        .packed_encoding => 1,
        .expanded => 2,
    });
    try tmp.writeInt32(4, switch (features.utf8_validation) {
        .verify => 2,
        .none => 3,
    });
    try writer.writeMessage(field_number, tmp.slice());
}

fn hasFeatureOptions(file: *const schema.FileDescriptor) bool {
    for (file.options.items) |option| {
        if (std.mem.startsWith(u8, option.name, "features.")) return true;
    }
    return false;
}

fn labelNumber(cardinality: schema.Cardinality) i32 {
    return switch (cardinality) {
        .required => 2,
        .repeated => 3,
        .optional, .implicit => 1,
    };
}

fn typeNumber(kind: schema.FieldKind) i32 {
    return switch (kind) {
        .scalar => |scalar| switch (scalar) {
            .double => 1,
            .float => 2,
            .int64 => 3,
            .uint64 => 4,
            .int32 => 5,
            .fixed64 => 6,
            .fixed32 => 7,
            .bool => 8,
            .string => 9,
            .bytes => 12,
            .uint32 => 13,
            .sfixed32 => 15,
            .sfixed64 => 16,
            .sint32 => 17,
            .sint64 => 18,
        },
        .group => 10,
        .message, .map => 11,
        .enumeration => 14,
    };
}

fn oneofIndex(message: *const schema.MessageDescriptor, name: []const u8) ?usize {
    for (message.oneofs.items, 0..) |oneof, index| {
        if (std.mem.eql(u8, oneof.name, name)) return index;
    }
    return null;
}

fn writeDefaultValue(allocator: std.mem.Allocator, value: schema.OptionValue, field_number: wire.FieldNumber, writer: *wire.Writer) Error!void {
    const text = try optionValueText(allocator, value);
    defer allocator.free(text);
    try writer.writeString(field_number, text);
}

fn optionValueText(allocator: std.mem.Allocator, value: schema.OptionValue) std.mem.Allocator.Error![]u8 {
    return switch (value) {
        .identifier => |text| try allocator.dupe(u8, text),
        .string => |text| try allocator.dupe(u8, text),
        .integer => |v| try std.fmt.allocPrint(allocator, "{d}", .{v}),
        .float => |v| try std.fmt.allocPrint(allocator, "{d}", .{v}),
        .boolean => |v| try allocator.dupe(u8, if (v) "true" else "false"),
        .aggregate => |text| try allocator.dupe(u8, text),
    };
}

fn writeQualifiedName(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, name: []const u8, field_number: wire.FieldNumber, writer: *wire.Writer) Error!void {
    const qualified = try qualifiedName(allocator, file, name);
    defer allocator.free(qualified);
    try writer.writeString(field_number, qualified);
}

fn qualifiedName(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, name: []const u8) std.mem.Allocator.Error![]u8 {
    if (std.mem.startsWith(u8, name, ".")) return try allocator.dupe(u8, name);
    if (file.package.len == 0) return try std.fmt.allocPrint(allocator, ".{s}", .{name});
    if (std.mem.startsWith(u8, name, file.package)) return try std.fmt.allocPrint(allocator, ".{s}", .{name});
    return try std.fmt.allocPrint(allocator, ".{s}.{s}", .{ file.package, name });
}

fn joinScope(allocator: std.mem.Allocator, parent: []const u8, name: []const u8) std.mem.Allocator.Error![]u8 {
    if (parent.len == 0) return try allocator.dupe(u8, name);
    return try std.fmt.allocPrint(allocator, "{s}.{s}", .{ parent, name });
}

fn mapEntryName(allocator: std.mem.Allocator, field_name: []const u8) std.mem.Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    var capitalize_next = true;
    for (field_name) |c| {
        if (c == '_') {
            capitalize_next = true;
            continue;
        }
        if (capitalize_next) {
            try out.append(allocator, std.ascii.toUpper(c));
            capitalize_next = false;
        } else {
            try out.append(allocator, c);
        }
    }
    try out.appendSlice(allocator, "Entry");
    return try out.toOwnedSlice(allocator);
}

test "descriptor encodes a minimal proto2 FileDescriptorProto" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto2";
        \\package demo;
        \\message Person {
        \\  required int32 id = 1;
        \\  optional string name = 2;
        \\}
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();

    const bytes = try encodeFileDescriptorProto(allocator, &file, "person.proto");
    defer allocator.free(bytes);

    const expected = &[_]u8{
        0x0a, 0x0c, 'p',  'e',  'r',  's',  'o',  'n',  '.',  'p',  'r',  'o',  't',  'o',
        0x12, 0x04, 'd',  'e',  'm',  'o',  0x22, 0x22, 0x0a, 0x06, 'P',  'e',  'r',  's',
        'o',  'n',  0x12, 0x0a, 0x0a, 0x02, 'i',  'd',  0x18, 0x01, 0x20, 0x02, 0x28, 0x05,
        0x12, 0x0c, 0x0a, 0x04, 'n',  'a',  'm',  'e',  0x18, 0x02, 0x20, 0x01, 0x28, 0x09,
        0x62, 0x06, 'p',  'r',  'o',  't',  'o',  '2',
    };
    try std.testing.expectEqualSlices(u8, expected, bytes);
}

test "descriptor encodes proto3 map entry and editions feature metadata" {
    const allocator = std.testing.allocator;
    const source =
        \\edition = "2023";
        \\package demo;
        \\option features.repeated_field_encoding = EXPANDED;
        \\message Bag { map<string, int32> counts = 1; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();

    const bytes = try encodeFileDescriptorProto(allocator, &file, "bag.proto");
    defer allocator.free(bytes);

    try std.testing.expect(std.mem.indexOf(u8, bytes, "CountsEntry") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "editions") != null);

    var reader = wire.Reader.init(bytes);
    var saw_edition = false;
    while (try reader.nextTag()) |tag| {
        if (tag.number == 14) {
            saw_edition = (try reader.readInt32()) == @intFromEnum(schema.Edition.edition_2023);
        } else {
            try reader.skipValue(tag);
        }
    }
    try std.testing.expect(saw_edition);
}
