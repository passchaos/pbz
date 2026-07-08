const std = @import("std");
const wire = @import("wire.zig");
const schema = @import("schema.zig");

pub const Error = wire.Error || std.mem.Allocator.Error || error{ InvalidFieldType, InvalidCharacter };

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

pub fn decodeFileDescriptorProto(allocator: std.mem.Allocator, bytes: []const u8) Error!schema.FileDescriptor {
    var file = schema.FileDescriptor.init(allocator);
    errdefer file.deinit();

    var reader = wire.Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            1 => file.name = try reader.readBytes(),
            2 => file.package = try reader.readBytes(),
            3 => try file.imports.append(allocator, .{ .path = try reader.readBytes() }),
            4 => try file.messages.append(allocator, try decodeMessageDescriptor(allocator, try reader.readBytes())),
            5 => try file.enums.append(allocator, try decodeEnumDescriptor(allocator, try reader.readBytes())),
            6 => try file.services.append(allocator, try decodeServiceDescriptor(allocator, try reader.readBytes())),
            7 => try file.extensions.append(allocator, try decodeFieldDescriptor(allocator, try reader.readBytes())),
            8 => try decodeFileOptions(&file, try reader.readBytes()),
            12 => {
                const syntax = try reader.readBytes();
                if (std.mem.eql(u8, syntax, "proto2")) file.setSyntax(.proto2) else if (std.mem.eql(u8, syntax, "proto3")) file.setSyntax(.proto3) else if (std.mem.eql(u8, syntax, "editions")) file.setSyntax(.editions);
            },
            14 => {
                file.syntax = .editions;
                file.edition = @enumFromInt(try reader.readInt32());
            },
            else => try reader.skipValue(tag),
        }
    }
    try collapseMapEntryMessages(allocator, &file);
    return file;
}

pub fn decodeFileDescriptorSet(allocator: std.mem.Allocator, bytes: []const u8) Error![]schema.FileDescriptor {
    var files: std.ArrayList(schema.FileDescriptor) = .empty;
    errdefer {
        for (files.items) |*file| file.deinit();
        files.deinit(allocator);
    }
    var reader = wire.Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        if (tag.number == 1) {
            try files.append(allocator, try decodeFileDescriptorProto(allocator, try reader.readBytes()));
        } else try reader.skipValue(tag);
    }
    return try files.toOwnedSlice(allocator);
}

fn decodeMessageDescriptor(allocator: std.mem.Allocator, bytes: []const u8) Error!schema.MessageDescriptor {
    var message = schema.MessageDescriptor{ .name = "" };
    errdefer message.deinit(allocator);
    var oneof_indexes: std.ArrayList(struct { field_index: usize, oneof_index: usize }) = .empty;
    defer oneof_indexes.deinit(allocator);

    var reader = wire.Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            1 => message.name = try reader.readBytes(),
            2 => {
                var field = try decodeFieldDescriptor(allocator, try reader.readBytes());
                if (field.oneof_name) |idx_text| {
                    const idx = try std.fmt.parseInt(usize, idx_text, 10);
                    field.oneof_name = null;
                    try oneof_indexes.append(allocator, .{ .field_index = message.fields.items.len, .oneof_index = idx });
                }
                try message.fields.append(allocator, field);
            },
            3 => try message.messages.append(allocator, try decodeMessageDescriptor(allocator, try reader.readBytes())),
            4 => try message.enums.append(allocator, try decodeEnumDescriptor(allocator, try reader.readBytes())),
            5 => try message.extension_ranges.append(allocator, try decodeExtensionRange(allocator, try reader.readBytes())),
            6 => try message.extensions.append(allocator, try decodeFieldDescriptor(allocator, try reader.readBytes())),
            8 => try message.oneofs.append(allocator, try decodeOneofDescriptor(allocator, try reader.readBytes())),
            9 => try message.reserved_ranges.append(allocator, try decodeReservedRange(allocator, try reader.readBytes(), false)),
            10 => try message.reserved_names.append(allocator, try reader.readBytes()),
            else => try reader.skipValue(tag),
        }
    }

    for (oneof_indexes.items) |item| {
        if (item.oneof_index < message.oneofs.items.len) {
            message.fields.items[item.field_index].oneof_name = message.oneofs.items[item.oneof_index].name;
        }
    }
    return message;
}

fn decodeFieldDescriptor(allocator: std.mem.Allocator, bytes: []const u8) Error!schema.FieldDescriptor {
    var name: []const u8 = "";
    var number: wire.FieldNumber = 0;
    var cardinality: schema.Cardinality = .optional;
    var field_type: i32 = 0;
    var type_name: ?[]const u8 = null;
    var extendee: ?[]const u8 = null;
    var default_value: ?schema.OptionValue = null;
    var oneof_index_text: ?[]const u8 = null;
    var json_name: ?[]const u8 = null;
    var proto3_optional = false;
    var packed_override: ?bool = null;

    var reader = wire.Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            1 => name = try reader.readBytes(),
            2 => extendee = try reader.readBytes(),
            3 => number = @intCast(try reader.readInt32()),
            4 => cardinality = labelFromNumber(try reader.readInt32()),
            5 => field_type = try reader.readInt32(),
            6 => type_name = try reader.readBytes(),
            7 => default_value = .{ .string = try reader.readBytes() },
            8 => packed_override = try decodeFieldOptions(try reader.readBytes()),
            9 => oneof_index_text = try oneofIndexText(try reader.readInt32()),
            10 => json_name = try reader.readBytes(),
            17 => proto3_optional = try reader.readBool(),
            else => try reader.skipValue(tag),
        }
    }

    return .{
        .name = name,
        .number = number,
        .cardinality = cardinality,
        .kind = try kindFromType(allocator, field_type, type_name),
        .extendee = extendee,
        .default_value = default_value,
        .oneof_name = oneof_index_text,
        .json_name = json_name,
        .proto3_optional = proto3_optional,
        .packed_override = packed_override,
    };
}

fn decodeEnumDescriptor(allocator: std.mem.Allocator, bytes: []const u8) Error!schema.EnumDescriptor {
    var enumeration = schema.EnumDescriptor{ .name = "" };
    errdefer enumeration.deinit(allocator);
    var reader = wire.Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            1 => enumeration.name = try reader.readBytes(),
            2 => try enumeration.values.append(allocator, try decodeEnumValueDescriptor(allocator, try reader.readBytes())),
            4 => try enumeration.reserved_ranges.append(allocator, try decodeReservedRange(allocator, try reader.readBytes(), true)),
            5 => try enumeration.reserved_names.append(allocator, try reader.readBytes()),
            else => try reader.skipValue(tag),
        }
    }
    return enumeration;
}

fn decodeEnumValueDescriptor(allocator: std.mem.Allocator, bytes: []const u8) Error!schema.EnumValueDescriptor {
    _ = allocator;
    var value = schema.EnumValueDescriptor{ .name = "", .number = 0 };
    var reader = wire.Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            1 => value.name = try reader.readBytes(),
            2 => value.number = try reader.readInt32(),
            else => try reader.skipValue(tag),
        }
    }
    return value;
}

fn decodeOneofDescriptor(allocator: std.mem.Allocator, bytes: []const u8) Error!schema.OneofDescriptor {
    _ = allocator;
    var oneof = schema.OneofDescriptor{ .name = "" };
    var reader = wire.Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        if (tag.number == 1) oneof.name = try reader.readBytes() else try reader.skipValue(tag);
    }
    return oneof;
}

fn decodeExtensionRange(allocator: std.mem.Allocator, bytes: []const u8) Error!schema.ExtensionRange {
    var range = schema.ExtensionRange{ .start = 0, .end = null };
    _ = allocator;
    var reader = wire.Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            1 => range.start = try reader.readInt32(),
            2 => range.end = try reader.readInt32(),
            else => try reader.skipValue(tag),
        }
    }
    return range;
}

fn decodeReservedRange(allocator: std.mem.Allocator, bytes: []const u8, inclusive_end: bool) Error!schema.ReservedRange {
    var range = schema.ReservedRange{ .start = 0, .end = null };
    _ = allocator;
    var reader = wire.Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            1 => range.start = try reader.readInt32(),
            2 => {
                const end = try reader.readInt32();
                range.end = if (inclusive_end) end + 1 else end;
            },
            else => try reader.skipValue(tag),
        }
    }
    return range;
}

fn decodeServiceDescriptor(allocator: std.mem.Allocator, bytes: []const u8) Error!schema.ServiceDescriptor {
    var service = schema.ServiceDescriptor{ .name = "" };
    errdefer service.deinit(allocator);
    var reader = wire.Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            1 => service.name = try reader.readBytes(),
            2 => try service.methods.append(allocator, try decodeMethodDescriptor(allocator, try reader.readBytes())),
            else => try reader.skipValue(tag),
        }
    }
    return service;
}

fn decodeMethodDescriptor(allocator: std.mem.Allocator, bytes: []const u8) Error!schema.MethodDescriptor {
    _ = allocator;
    var method = schema.MethodDescriptor{ .name = "", .input_type = "", .output_type = "" };
    var reader = wire.Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            1 => method.name = try reader.readBytes(),
            2 => method.input_type = try reader.readBytes(),
            3 => method.output_type = try reader.readBytes(),
            5 => method.client_streaming = try reader.readBool(),
            6 => method.server_streaming = try reader.readBool(),
            else => try reader.skipValue(tag),
        }
    }
    return method;
}

fn decodeFileOptions(file: *schema.FileDescriptor, bytes: []const u8) Error!void {
    var reader = wire.Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        if (tag.number == 50) file.features = try decodeFeatureSet(try reader.readBytes()) else try reader.skipValue(tag);
    }
}

fn decodeFieldOptions(bytes: []const u8) Error!?bool {
    var result: ?bool = null;
    var reader = wire.Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        if (tag.number == 2) result = try reader.readBool() else try reader.skipValue(tag);
    }
    return result;
}

fn decodeMessageOptionsMapEntry(bytes: []const u8) Error!bool {
    var result = false;
    var reader = wire.Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        if (tag.number == 7) result = try reader.readBool() else try reader.skipValue(tag);
    }
    return result;
}

fn decodeFeatureSet(bytes: []const u8) Error!schema.FeatureSet {
    var features = schema.FeatureSet{};
    var reader = wire.Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            1 => features.field_presence = switch (try reader.readInt32()) {
                2 => .implicit,
                3 => .legacy_required,
                else => .explicit,
            },
            2 => features.enum_type = switch (try reader.readInt32()) {
                2 => .closed,
                else => .open,
            },
            3 => features.repeated_field_encoding = switch (try reader.readInt32()) {
                2 => .expanded,
                else => .packed_encoding,
            },
            4 => features.utf8_validation = switch (try reader.readInt32()) {
                3 => .none,
                else => .verify,
            },
            else => try reader.skipValue(tag),
        }
    }
    return features;
}

fn oneofIndexText(index: i32) Error![]const u8 {
    return switch (index) {
        0 => "0",
        1 => "1",
        2 => "2",
        3 => "3",
        4 => "4",
        5 => "5",
        6 => "6",
        7 => "7",
        8 => "8",
        9 => "9",
        else => error.InvalidFieldType,
    };
}

fn labelFromNumber(value: i32) schema.Cardinality {
    return switch (value) {
        2 => .required,
        3 => .repeated,
        else => .optional,
    };
}

fn kindFromType(allocator: std.mem.Allocator, field_type: i32, type_name: ?[]const u8) Error!schema.FieldKind {
    return switch (field_type) {
        1 => .{ .scalar = .double },
        2 => .{ .scalar = .float },
        3 => .{ .scalar = .int64 },
        4 => .{ .scalar = .uint64 },
        5 => .{ .scalar = .int32 },
        6 => .{ .scalar = .fixed64 },
        7 => .{ .scalar = .fixed32 },
        8 => .{ .scalar = .bool },
        9 => .{ .scalar = .string },
        10 => .{ .group = type_name orelse "" },
        11 => .{ .message = type_name orelse "" },
        12 => .{ .scalar = .bytes },
        13 => .{ .scalar = .uint32 },
        14 => .{ .enumeration = type_name orelse "" },
        15 => .{ .scalar = .sfixed32 },
        16 => .{ .scalar = .sfixed64 },
        17 => .{ .scalar = .sint32 },
        18 => .{ .scalar = .sint64 },
        else => blk: {
            _ = allocator;
            break :blk error.InvalidFieldType;
        },
    };
}

fn collapseMapEntryMessages(allocator: std.mem.Allocator, file: *schema.FileDescriptor) Error!void {
    for (file.messages.items) |*message| try collapseMapEntriesInMessage(allocator, message);
}

fn collapseMapEntriesInMessage(allocator: std.mem.Allocator, message: *schema.MessageDescriptor) Error!void {
    var index: usize = 0;
    while (index < message.messages.items.len) {
        if (try isMapEntryMessage(message.messages.items[index])) {
            const entry = &message.messages.items[index];
            if (entry.fields.items.len >= 2) {
                const key_field = entry.findField("key").?;
                const value_field = entry.findField("value").?;
                for (message.fields.items) |*field| {
                    if (field.kind == .message and typeNameMatches(field.kind.message, entry.name)) {
                        const value_kind = try allocator.create(schema.FieldKind);
                        value_kind.* = value_field.kind;
                        field.kind = .{ .map = .{ .key = key_field.kind.scalar, .value = value_kind } };
                    }
                }
            }
            var removed = message.messages.swapRemove(index);
            removed.deinit(allocator);
            continue;
        }
        try collapseMapEntriesInMessage(allocator, &message.messages.items[index]);
        index += 1;
    }
}

fn isMapEntryMessage(message: schema.MessageDescriptor) Error!bool {
    for (message.options.items) |_| {}
    // The encoder emits MessageOptions.map_entry=true as field 7, but this
    // lightweight schema model does not store MessageOptions yet. Use the
    // canonical synthetic shape as a fallback.
    return std.mem.endsWith(u8, message.name, "Entry") and message.fields.items.len == 2 and message.findField("key") != null and message.findField("value") != null;
}

fn typeNameMatches(encoded_type_name: []const u8, entry_name: []const u8) bool {
    const leaf = if (std.mem.lastIndexOfScalar(u8, encoded_type_name, '.')) |idx| encoded_type_name[idx + 1 ..] else encoded_type_name;
    return std.mem.eql(u8, leaf, entry_name);
}

test "descriptor decodes encoded FileDescriptorProto back to schema" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\package demo;
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message Bag {
        \\  oneof pick { string name = 1; int32 id = 2; }
        \\  repeated int32 nums = 3;
        \\  map<string, int32> counts = 4;
        \\  Kind kind = 5;
        \\}
        \\service Bags { rpc Get (Bag) returns (Bag); }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    file.name = "bag.proto";

    const encoded = try encodeFileDescriptorProto(allocator, &file, file.name);
    defer allocator.free(encoded);

    var decoded = try decodeFileDescriptorProto(allocator, encoded);
    defer decoded.deinit();

    try std.testing.expectEqualStrings("bag.proto", decoded.name);
    try std.testing.expectEqualStrings("demo", decoded.package);
    try std.testing.expectEqual(schema.Syntax.proto3, decoded.syntax);
    const bag = decoded.findMessage("Bag").?;
    try std.testing.expectEqual(@as(usize, 5), bag.fields.items.len);
    try std.testing.expectEqual(@as(usize, 1), bag.oneofs.items.len);
    try std.testing.expectEqualStrings("pick", bag.findField("name").?.oneof_name.?);
    try std.testing.expect(bag.findField("counts").?.kind == .map);
    try std.testing.expect(bag.findField("kind").?.kind == .enumeration);
    try std.testing.expectEqual(@as(usize, 1), decoded.services.items.len);
}

test "descriptor decodes FileDescriptorSet" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto2";
        \\package demo;
        \\message A { optional string s = 1; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    file.name = "a.proto";
    const files = [_]*const schema.FileDescriptor{&file};
    const set_bytes = try encodeFileDescriptorSet(allocator, &files);
    defer allocator.free(set_bytes);

    const decoded_files = try decodeFileDescriptorSet(allocator, set_bytes);
    defer {
        for (decoded_files) |*decoded_file| decoded_file.deinit();
        allocator.free(decoded_files);
    }
    try std.testing.expectEqual(@as(usize, 1), decoded_files.len);
    try std.testing.expectEqualStrings("a.proto", decoded_files[0].name);
    try std.testing.expect(decoded_files[0].findMessage("A") != null);
}
