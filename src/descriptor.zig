const std = @import("std");

const wire = @import("wire.zig");

const schema = @import("schema.zig");

const registry_mod = @import("registry.zig");

pub const Error = wire.Error || std.mem.Allocator.Error || registry_mod.Error || error{ InvalidFieldType, InvalidCharacter };

pub fn encodeFileDescriptorProto(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, name: []const u8) Error![]u8 {
    var writer = wire.Writer.init(allocator);
    errdefer writer.deinit();
    try writeFileDescriptorProto(allocator, file, name, &writer);
    return try writer.toOwnedSlice();
}

pub fn encodeFileDescriptorProtoWithRegistry(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, registry: *const registry_mod.Registry, name: []const u8) Error![]u8 {
    var writer = wire.Writer.init(allocator);
    errdefer writer.deinit();
    try writeFileDescriptorProtoWithRegistry(allocator, file, registry, name, &writer);
    return try writer.toOwnedSlice();
}

pub fn writeFileDescriptorProto(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, name: []const u8, writer: *wire.Writer) Error!void {
    try writeFileDescriptorProtoInner(allocator, file, null, name, writer);
}

pub fn writeFileDescriptorProtoWithRegistry(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, registry: *const registry_mod.Registry, name: []const u8, writer: *wire.Writer) Error!void {
    try writeFileDescriptorProtoInner(allocator, file, registry, name, writer);
}

fn writeFileDescriptorProtoInner(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, name: []const u8, writer: *wire.Writer) Error!void {
    const file_name = if (file.name.len != 0) file.name else name;
    if (file_name.len != 0) try writer.writeString(1, file_name);
    if (file.package.len != 0) try writer.writeString(2, file.package);
    var dependency_index: i32 = 0;
    for (file.imports.items) |import| {
        switch (import.kind) {
            .option => try writer.writeString(15, import.path),
            .public => {
                try writer.writeString(3, import.path);
                try writer.writeInt32(10, dependency_index);
                dependency_index += 1;
            },
            .weak => {
                try writer.writeString(3, import.path);
                try writer.writeInt32(11, dependency_index);
                dependency_index += 1;
            },
            .normal => {
                try writer.writeString(3, import.path);
                dependency_index += 1;
            },
        }
    }
    for (file.messages.items) |*message| try writeMessageDescriptor(allocator, file, registry, message, "", 4, writer);
    for (file.enums.items) |*enumeration| try writeEnumDescriptor(allocator, file, enumeration, 5, writer);
    for (file.services.items) |*service| try writeServiceDescriptor(allocator, file, service, 6, writer);
    for (file.extensions.items) |*field| try writeFieldDescriptor(allocator, file, registry, null, "", field, 7, writer);
    if (hasFileOptions(file)) try writeFileOptions(allocator, file, 8, writer);
    if (!file.source_code_info.isEmpty()) try writeSourceCodeInfo(allocator, &file.source_code_info, 9, writer);
    // protoc omits `syntax` for proto2, which is the field's default.
    switch (file.syntax) {
        .proto2 => {},
        .proto3 => try writer.writeString(12, "proto3"),
        .editions => try writer.writeString(12, "editions"),
    }
    if (file.syntax == .editions) try writer.writeInt32(14, @intFromEnum(file.edition));
}

pub fn encodeFileDescriptorSet(allocator: std.mem.Allocator, files: []const *const schema.FileDescriptor) Error![]u8 {
    var writer = wire.Writer.init(allocator);
    errdefer writer.deinit();
    try writeFileDescriptorSet(allocator, files, &writer);
    return try writer.toOwnedSlice();
}

pub fn encodeFileDescriptorSetWithRegistry(allocator: std.mem.Allocator, files: []const *const schema.FileDescriptor, registry: *const registry_mod.Registry) Error![]u8 {
    var writer = wire.Writer.init(allocator);
    errdefer writer.deinit();
    try writeFileDescriptorSetWithRegistry(allocator, files, registry, &writer);
    return try writer.toOwnedSlice();
}

pub fn encodeFeatureSetDefaults(allocator: std.mem.Allocator, defaults: *const schema.FeatureSetDefaults) Error![]u8 {
    var writer = wire.Writer.init(allocator);
    errdefer writer.deinit();
    try writeFeatureSetDefaults(allocator, defaults, &writer);
    return try writer.toOwnedSlice();
}

pub fn writeFileDescriptorSet(allocator: std.mem.Allocator, files: []const *const schema.FileDescriptor, writer: *wire.Writer) Error!void {
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    for (files) |file| try registry.files.append(allocator, file);
    try writeFileDescriptorSetInner(allocator, files, &registry, writer);
}

pub fn writeFileDescriptorSetWithRegistry(allocator: std.mem.Allocator, files: []const *const schema.FileDescriptor, registry: *const registry_mod.Registry, writer: *wire.Writer) Error!void {
    try writeFileDescriptorSetInner(allocator, files, registry, writer);
}

fn writeFileDescriptorSetInner(allocator: std.mem.Allocator, files: []const *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, writer: *wire.Writer) Error!void {
    for (files) |file| {
        var file_writer = wire.Writer.init(allocator);
        defer file_writer.deinit();
        try writeFileDescriptorProtoInner(allocator, file, registry, file.name, &file_writer);
        try writer.writeMessage(1, file_writer.slice());
    }
}

pub fn writeFeatureSetDefaults(allocator: std.mem.Allocator, defaults: *const schema.FeatureSetDefaults, writer: *wire.Writer) Error!void {
    try validateFeatureSetDefaults(defaults);
    for (defaults.defaults.items) |entry| try writeFeatureSetEditionDefault(allocator, entry, 1, writer);
    if (defaults.minimum_edition) |edition| try writer.writeInt32(4, @intFromEnum(edition));
    if (defaults.maximum_edition) |edition| try writer.writeInt32(5, @intFromEnum(edition));
}

fn writeFeatureSetEditionDefault(allocator: std.mem.Allocator, entry: schema.FeatureSetEditionDefault, field_number: wire.FieldNumber, writer: *wire.Writer) Error!void {
    var tmp = wire.Writer.init(allocator);
    defer tmp.deinit();
    if (entry.edition != .unknown) try tmp.writeInt32(3, @intFromEnum(entry.edition));
    if (entry.overridable_features) |features| try writeFeatureSetFull(allocator, features, 4, &tmp);
    if (entry.fixed_features) |features| try writeFeatureSetFull(allocator, features, 5, &tmp);
    try writer.writeMessage(field_number, tmp.slice());
}

fn writeMessageDescriptor(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    registry: ?*const registry_mod.Registry,
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

    for (message.fields.items) |*field| try writeFieldDescriptor(allocator, file, registry, message, scope, field, 2, &tmp);
    if (message.nested_order.items.len != 0) {
        // Decoded descriptors keep protoc's nested_type order, including
        // collapsed map-entry messages at their original positions.
        for (message.nested_order.items) |nested_name| {
            if (findNestedMessageByName(message, nested_name)) |nested| {
                try writeMessageDescriptor(allocator, file, registry, nested, scope, 3, &tmp);
                continue;
            }
            if (findMapFieldByEntryName(message, nested_name)) |field| {
                try writeMapEntryDescriptor(allocator, file, registry, scope, field, 3, &tmp);
                continue;
            }
            return error.InvalidFieldType;
        }
    } else {
        for (message.messages.items) |*nested| try writeMessageDescriptor(allocator, file, registry, nested, scope, 3, &tmp);
        for (message.fields.items) |*field| {
            if (field.kind == .map) try writeMapEntryDescriptor(allocator, file, registry, scope, field, 3, &tmp);
        }
    }
    for (message.enums.items) |*enumeration| try writeEnumDescriptor(allocator, file, enumeration, 4, &tmp);
    for (message.extension_ranges.items) |*range| try writeExtensionRange(allocator, message, range, 5, &tmp);
    for (message.extensions.items) |*field| try writeFieldDescriptor(allocator, file, registry, message, scope, field, 6, &tmp);
    if (hasMessageOptions(message)) try writeMessageOptions(allocator, message, 7, &tmp);
    for (message.oneofs.items) |*oneof| try writeOneofDescriptor(allocator, file, oneof, 8, &tmp);
    for (message.fields.items) |*field| {
        if (field.proto3_optional and field.oneof_name == null) try writeSyntheticOneofDescriptor(allocator, field, 8, &tmp);
    }
    for (message.reserved_ranges.items) |range| try writeReservedRange(allocator, message, range, 9, &tmp);
    for (message.reserved_names.items) |reserved_name| try tmp.writeString(10, reserved_name);
    if (message.visibility != .default) try tmp.writeInt32(11, symbolVisibilityNumber(message.visibility));

    try writer.writeMessage(field_number, tmp.slice());
}

fn writeMapEntryDescriptor(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    registry: ?*const registry_mod.Registry,
    parent_scope: []const u8,
    field: *const schema.FieldDescriptor,
    field_number: wire.FieldNumber,
    writer: *wire.Writer,
) Error!void {
    const map_type = switch (field.kind) {
        .map => |map| map,
        else => return error.InvalidFieldType,
    };

    const entry_name = try mapEntryName(allocator, field.name);
    defer allocator.free(entry_name);
    var entry_message = schema.MessageDescriptor{ .name = entry_name, .map_entry = true };
    defer entry_message.fields.deinit(allocator);

    const key_field = schema.FieldDescriptor{
        .name = "key",
        .number = 1,
        .cardinality = .optional,
        .json_name = "key",
        .kind = .{ .scalar = map_type.key },
    };
    try entry_message.fields.append(allocator, key_field);

    const value_field = schema.FieldDescriptor{
        .name = "value",
        .number = 2,
        .cardinality = .optional,
        .json_name = "value",
        .kind = map_type.value.*,
    };
    try entry_message.fields.append(allocator, value_field);

    try writeMessageDescriptor(allocator, file, registry, &entry_message, parent_scope, field_number, writer);
}

fn writeFieldDescriptor(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    registry: ?*const registry_mod.Registry,
    containing_message: ?*const schema.MessageDescriptor,
    containing_scope: []const u8,
    field: *const schema.FieldDescriptor,
    field_number: wire.FieldNumber,
    writer: *wire.Writer,
) Error!void {
    var tmp = wire.Writer.init(allocator);
    defer tmp.deinit();

    try tmp.writeString(1, field.name);
    if (field.extendee != null) try writeQualifiedExtendeeName(allocator, file, registry, containing_scope, field, 2, &tmp);
    try tmp.writeInt32(3, @intCast(field.number));
    try tmp.writeInt32(4, labelNumber(field.cardinality));
    const descriptor_kind = descriptorFieldKind(file, registry, containing_scope, field.kind);
    try tmp.writeInt32(5, typeNumber(descriptor_kind));
    switch (field.kind) {
        .message => |type_name| {
            if (descriptor_kind == .enumeration) {
                try writeQualifiedTypeName(allocator, file, registry, containing_scope, type_name, .enumeration, 6, &tmp);
            } else {
                try writeQualifiedTypeName(allocator, file, registry, containing_scope, type_name, .message, 6, &tmp);
            }
        },
        .group => |type_name| try writeQualifiedTypeName(allocator, file, registry, containing_scope, type_name, .message, 6, &tmp),
        .enumeration => |type_name| try writeQualifiedTypeName(allocator, file, registry, containing_scope, type_name, .enumeration, 6, &tmp),
        .map => {
            const entry_name = try mapEntryName(allocator, field.name);
            defer allocator.free(entry_name);
            const scoped = if (containing_scope.len != 0)
                try joinScope(allocator, containing_scope, entry_name)
            else
                try allocator.dupe(u8, entry_name);
            defer allocator.free(scoped);
            try writeQualifiedName(allocator, file, scoped, 6, &tmp);
        },
        else => {},
    }
    if (field.default_value_text) |text| {
        try tmp.writeString(7, text);
    } else if (field.default_value) |value| {
        try writeDefaultValue(allocator, file, registry, containing_scope, descriptor_kind, value, 7, &tmp);
    }
    if (hasFieldOptions(field)) try writeFieldOptions(allocator, field, 8, &tmp);
    if (containing_message) |message| {
        if (field.oneof_name) |oneof_name| {
            if (oneofIndex(message, oneof_name)) |index| try tmp.writeInt32(9, @intCast(index));
        } else if (field.proto3_optional) {
            if (syntheticOneofIndex(message, field)) |index| try tmp.writeInt32(9, @intCast(index));
        }
    }
    if (field.json_name) |json_name| try tmp.writeString(10, json_name);
    if (field.proto3_optional) try tmp.writeBool(17, true);

    try writer.writeMessage(field_number, tmp.slice());
}

fn hasFieldOptions(field: *const schema.FieldDescriptor) bool {
    return field.packed_override != null or
        field.options.items.len != 0 or
        field.unknown_options.items.len != 0 or
        field.edition_defaults.items.len != 0 or
        field.features != null or
        field.feature_support != null;
}

fn writeSyntheticOneofDescriptor(allocator: std.mem.Allocator, field: *const schema.FieldDescriptor, field_number: wire.FieldNumber, writer: *wire.Writer) Error!void {
    var tmp = wire.Writer.init(allocator);
    defer tmp.deinit();
    const name = try syntheticOneofName(allocator, field);
    defer allocator.free(name);
    try tmp.writeString(1, name);
    try writer.writeMessage(field_number, tmp.slice());
}

fn writeEnumDescriptor(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, enumeration: *const schema.EnumDescriptor, field_number: wire.FieldNumber, writer: *wire.Writer) Error!void {
    var tmp = wire.Writer.init(allocator);
    defer tmp.deinit();

    try tmp.writeString(1, enumeration.name);
    for (enumeration.values.items) |*value| try writeEnumValueDescriptor(allocator, file, value, 2, &tmp);
    if (hasEnumOptions(enumeration)) try writeEnumOptions(allocator, enumeration, 3, &tmp);
    for (enumeration.reserved_ranges.items) |range| try writeEnumReservedRange(allocator, range, 4, &tmp);
    for (enumeration.reserved_names.items) |reserved_name| try tmp.writeString(5, reserved_name);
    if (enumeration.visibility != .default) try tmp.writeInt32(6, symbolVisibilityNumber(enumeration.visibility));

    try writer.writeMessage(field_number, tmp.slice());
}

fn writeEnumValueDescriptor(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, value: *const schema.EnumValueDescriptor, field_number: wire.FieldNumber, writer: *wire.Writer) Error!void {
    _ = file;
    var tmp = wire.Writer.init(allocator);
    defer tmp.deinit();

    try tmp.writeString(1, value.name);
    try tmp.writeInt32(2, value.number);
    if (hasEnumValueOptions(value)) try writeEnumValueOptions(allocator, value, 3, &tmp);

    try writer.writeMessage(field_number, tmp.slice());
}

fn writeEnumValueOptions(allocator: std.mem.Allocator, value: *const schema.EnumValueDescriptor, field_number: wire.FieldNumber, writer: *wire.Writer) Error!void {
    var tmp = wire.Writer.init(allocator);
    defer tmp.deinit();
    if (exactOptionBool(value.options.items, "deprecated")) |deprecated| try tmp.writeBool(1, deprecated);
    if (value.features) |features| try writeFeatureSet(allocator, features, 2, &tmp);
    if (exactOptionBool(value.options.items, "debug_redact")) |debug_redact| try tmp.writeBool(3, debug_redact);
    if (value.feature_support) |feature_support| try writeFeatureSupport(allocator, feature_support, 4, &tmp);
    try writeUninterpretedOptions(allocator, value.options.items, &tmp, .enum_value);
    for (value.unknown_options.items) |raw| try tmp.appendSlice(raw);
    try writer.writeMessage(field_number, tmp.slice());
}

fn hasEnumValueOptions(value: *const schema.EnumValueDescriptor) bool {
    return value.options.items.len != 0 or value.unknown_options.items.len != 0 or value.features != null or value.feature_support != null;
}

fn descriptorFieldKind(file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, containing_scope: []const u8, kind: schema.FieldKind) schema.FieldKind {
    return switch (kind) {
        .message => |type_name| if (descriptorEnumVisible(file, registry, containing_scope, type_name)) |_| .{ .enumeration = type_name } else kind,
        .map => |map_type| .{ .map = .{ .key = map_type.key, .value = map_type.value } },
        else => kind,
    };
}

fn descriptorEnumVisible(file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, containing_scope: []const u8, type_name: []const u8) ?*const schema.EnumDescriptor {
    if (registry) |reg| {
        const scope = descriptorScopeName(file, containing_scope);
        if (reg.findEnumVisible(file, type_name, scope)) |enumeration| return enumeration;
    }
    return file.findEnumDeep(type_name);
}

fn descriptorScopeName(file: *const schema.FileDescriptor, containing_scope: []const u8) ?[]const u8 {
    if (containing_scope.len == 0) return if (file.package.len == 0) null else file.package;
    if (file.package.len == 0) return containing_scope;
    return containing_scope;
}

fn writeOneofDescriptor(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, oneof: *const schema.OneofDescriptor, field_number: wire.FieldNumber, writer: *wire.Writer) Error!void {
    _ = file;
    var tmp = wire.Writer.init(allocator);
    defer tmp.deinit();
    try tmp.writeString(1, oneof.name);
    if (hasOneofOptions(oneof)) try writeOneofOptions(allocator, oneof, 2, &tmp);
    try writer.writeMessage(field_number, tmp.slice());
}

fn writeOneofOptions(allocator: std.mem.Allocator, oneof: *const schema.OneofDescriptor, field_number: wire.FieldNumber, writer: *wire.Writer) Error!void {
    var tmp = wire.Writer.init(allocator);
    defer tmp.deinit();
    if (oneof.features) |features| try writeFeatureSet(allocator, features, 1, &tmp);
    try writeUninterpretedOptions(allocator, oneof.options.items, &tmp, .oneof);
    for (oneof.unknown_options.items) |raw| try tmp.appendSlice(raw);
    try writer.writeMessage(field_number, tmp.slice());
}

fn hasOneofOptions(oneof: *const schema.OneofDescriptor) bool {
    return oneof.options.items.len != 0 or oneof.unknown_options.items.len != 0 or oneof.features != null;
}

fn writeExtensionRange(allocator: std.mem.Allocator, message: *const schema.MessageDescriptor, range: *const schema.ExtensionRange, field_number: wire.FieldNumber, writer: *wire.Writer) Error!void {
    var tmp = wire.Writer.init(allocator);
    defer tmp.deinit();
    try tmp.writeInt32(1, try descriptorI32RangeBound(range.start));
    try tmp.writeInt32(2, try descriptorMessageRangeEnd(message, range.end));
    if (range.options.items.len != 0 or range.unknown_options.items.len != 0 or range.declarations.items.len != 0 or range.verification != null or range.features != null) try writeExtensionRangeOptions(allocator, range, 3, &tmp);
    try writer.writeMessage(field_number, tmp.slice());
}

fn writeExtensionRangeOptions(allocator: std.mem.Allocator, range: *const schema.ExtensionRange, field_number: wire.FieldNumber, writer: *wire.Writer) Error!void {
    var tmp = wire.Writer.init(allocator);
    defer tmp.deinit();
    for (range.declarations.items) |declaration| try writeExtensionDeclaration(allocator, declaration, 2, &tmp);
    if (range.verification) |verification| try tmp.writeInt32(3, @intFromEnum(verification));
    if (range.features) |features| try writeFeatureSet(allocator, features, 50, &tmp);
    try writeUninterpretedOptions(allocator, range.options.items, &tmp, .extension_range);
    for (range.unknown_options.items) |raw| try tmp.appendSlice(raw);
    try writer.writeMessage(field_number, tmp.slice());
}

fn writeExtensionDeclaration(allocator: std.mem.Allocator, declaration: schema.ExtensionDeclaration, field_number: wire.FieldNumber, writer: *wire.Writer) Error!void {
    var tmp = wire.Writer.init(allocator);
    defer tmp.deinit();
    if (declaration.number != 0) try tmp.writeInt32(1, declaration.number);
    if (declaration.full_name.len != 0) try tmp.writeString(2, declaration.full_name);
    if (declaration.type_name.len != 0) try tmp.writeString(3, declaration.type_name);
    if (declaration.reserved) try tmp.writeBool(5, true);
    if (declaration.repeated) try tmp.writeBool(6, true);
    try writer.writeMessage(field_number, tmp.slice());
}

fn writeSourceCodeInfo(allocator: std.mem.Allocator, source_code_info: *const schema.SourceCodeInfo, field_number: wire.FieldNumber, writer: *wire.Writer) Error!void {
    var tmp = wire.Writer.init(allocator);
    defer tmp.deinit();
    for (source_code_info.locations.items) |*location| try writeSourceCodeInfoLocation(allocator, location, 1, &tmp);
    try writer.writeMessage(field_number, tmp.slice());
}

fn writeSourceCodeInfoLocation(allocator: std.mem.Allocator, location: *const schema.SourceCodeInfo.Location, field_number: wire.FieldNumber, writer: *wire.Writer) Error!void {
    var tmp = wire.Writer.init(allocator);
    defer tmp.deinit();
    try writePackedInt32List(allocator, 1, location.path.items, &tmp);
    try writePackedInt32List(allocator, 2, location.span.items, &tmp);
    if (location.leading_comments) |comments| try tmp.writeString(3, comments);
    if (location.trailing_comments) |comments| try tmp.writeString(4, comments);
    for (location.leading_detached_comments.items) |comments| try tmp.writeString(6, comments);
    try writer.writeMessage(field_number, tmp.slice());
}

pub fn encodeGeneratedCodeInfo(allocator: std.mem.Allocator, generated_code_info: *const schema.GeneratedCodeInfo) Error![]u8 {
    var writer = wire.Writer.init(allocator);
    errdefer writer.deinit();
    try writeGeneratedCodeInfo(allocator, generated_code_info, &writer);
    return try writer.toOwnedSlice();
}

pub fn writeGeneratedCodeInfo(allocator: std.mem.Allocator, generated_code_info: *const schema.GeneratedCodeInfo, writer: *wire.Writer) Error!void {
    for (generated_code_info.annotations.items) |*annotation| try writeGeneratedCodeInfoAnnotation(allocator, annotation, 1, writer);
}

fn writeGeneratedCodeInfoAnnotation(allocator: std.mem.Allocator, annotation: *const schema.GeneratedCodeInfo.Annotation, field_number: wire.FieldNumber, writer: *wire.Writer) Error!void {
    var tmp = wire.Writer.init(allocator);
    defer tmp.deinit();
    try writePackedInt32List(allocator, 1, annotation.path.items, &tmp);
    if (annotation.source_file) |source_file| try tmp.writeString(2, source_file);
    if (annotation.begin) |begin| try tmp.writeInt32(3, begin);
    if (annotation.end) |end| try tmp.writeInt32(4, end);
    if (annotation.semantic) |semantic| try tmp.writeInt32(5, @intFromEnum(semantic));
    try writer.writeMessage(field_number, tmp.slice());
}

pub fn decodeGeneratedCodeInfo(allocator: std.mem.Allocator, bytes: []const u8) Error!schema.GeneratedCodeInfo {
    var generated = schema.GeneratedCodeInfo{};
    errdefer generated.deinit(allocator);
    var reader = wire.Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            1 => try appendGeneratedCodeInfoAnnotation(allocator, &generated.annotations, try decodeGeneratedCodeInfoAnnotation(allocator, try reader.readBytes())),
            else => try reader.skipValue(tag),
        }
    }
    return generated;
}

fn decodeGeneratedCodeInfoAnnotation(allocator: std.mem.Allocator, bytes: []const u8) Error!schema.GeneratedCodeInfo.Annotation {
    var annotation = schema.GeneratedCodeInfo.Annotation{};
    errdefer annotation.deinit(allocator);
    var reader = wire.Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            1 => try decodeInt32ListField(allocator, tag, &reader, &annotation.path),
            2 => annotation.source_file = try reader.readBytes(),
            3 => annotation.begin = try reader.readInt32(),
            4 => annotation.end = try reader.readInt32(),
            5 => annotation.semantic = std.enums.fromInt(schema.GeneratedCodeInfo.Semantic, try reader.readInt32()) orelse return error.InvalidFieldType,
            else => try reader.skipValue(tag),
        }
    }
    return annotation;
}

fn writePackedInt32List(allocator: std.mem.Allocator, field_number: wire.FieldNumber, values: []const i32, writer: *wire.Writer) Error!void {
    if (values.len == 0) return;
    var packed_writer = wire.Writer.init(allocator);
    defer packed_writer.deinit();
    for (values) |value| try packed_writer.writeVarint(@as(u64, @bitCast(@as(i64, value))));
    try writer.writeBytes(field_number, packed_writer.slice());
}

fn writeReservedRange(allocator: std.mem.Allocator, message: *const schema.MessageDescriptor, range: schema.ReservedRange, field_number: wire.FieldNumber, writer: *wire.Writer) Error!void {
    var tmp = wire.Writer.init(allocator);
    defer tmp.deinit();
    try tmp.writeInt32(1, try descriptorI32RangeBound(range.start));
    try tmp.writeInt32(2, try descriptorMessageRangeEnd(message, range.end));
    try writer.writeMessage(field_number, tmp.slice());
}

fn writeEnumReservedRange(allocator: std.mem.Allocator, range: schema.ReservedRange, field_number: wire.FieldNumber, writer: *wire.Writer) Error!void {
    var tmp = wire.Writer.init(allocator);
    defer tmp.deinit();
    try tmp.writeInt32(1, try descriptorI32RangeBound(range.start));
    try tmp.writeInt32(2, try descriptorEnumReservedEnd(range.end));
    try writer.writeMessage(field_number, tmp.slice());
}

fn descriptorMessageRangeEnd(message: *const schema.MessageDescriptor, maybe_end: ?i64) Error!i32 {
    const end = maybe_end orelse return @intCast(message.extensionRangeMaxExclusive());
    return try descriptorI32RangeBound(end);
}

fn descriptorEnumReservedEnd(maybe_end: ?i64) Error!i32 {
    const end = maybe_end orelse return std.math.maxInt(i32);
    if (end <= std.math.minInt(i32) or end - 1 > std.math.maxInt(i32)) return error.InvalidFieldType;
    return @intCast(end - 1);
}

fn descriptorI32RangeBound(value: i64) Error!i32 {
    if (value < std.math.minInt(i32) or value > std.math.maxInt(i32)) return error.InvalidFieldType;
    return @intCast(value);
}

fn writeServiceDescriptor(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, service: *const schema.ServiceDescriptor, field_number: wire.FieldNumber, writer: *wire.Writer) Error!void {
    _ = file;
    var tmp = wire.Writer.init(allocator);
    defer tmp.deinit();
    try tmp.writeString(1, service.name);
    for (service.methods.items) |*method| try writeMethodDescriptor(allocator, method, 2, &tmp);
    if (hasServiceOptions(service)) try writeServiceOptions(allocator, service, 3, &tmp);
    try writer.writeMessage(field_number, tmp.slice());
}

fn writeServiceOptions(allocator: std.mem.Allocator, service: *const schema.ServiceDescriptor, field_number: wire.FieldNumber, writer: *wire.Writer) Error!void {
    var tmp = wire.Writer.init(allocator);
    defer tmp.deinit();
    if (service.features) |features| try writeFeatureSet(allocator, features, 34, &tmp);
    if (exactOptionBool(service.options.items, "deprecated")) |deprecated| try tmp.writeBool(33, deprecated);
    try writeUninterpretedOptions(allocator, service.options.items, &tmp, .service);
    for (service.unknown_options.items) |raw| try tmp.appendSlice(raw);
    try writer.writeMessage(field_number, tmp.slice());
}

fn hasServiceOptions(service: *const schema.ServiceDescriptor) bool {
    return service.options.items.len != 0 or service.unknown_options.items.len != 0 or service.features != null;
}

fn writeMethodDescriptor(allocator: std.mem.Allocator, method: *const schema.MethodDescriptor, field_number: wire.FieldNumber, writer: *wire.Writer) Error!void {
    var tmp = wire.Writer.init(allocator);
    defer tmp.deinit();
    try tmp.writeString(1, method.name);
    try tmp.writeString(2, method.input_type);
    try tmp.writeString(3, method.output_type);
    if (hasMethodOptions(method)) try writeMethodOptions(allocator, method, 4, &tmp);
    if (method.client_streaming) try tmp.writeBool(5, true);
    if (method.server_streaming) try tmp.writeBool(6, true);
    try writer.writeMessage(field_number, tmp.slice());
}

fn writeMethodOptions(allocator: std.mem.Allocator, method: *const schema.MethodDescriptor, field_number: wire.FieldNumber, writer: *wire.Writer) Error!void {
    var tmp = wire.Writer.init(allocator);
    defer tmp.deinit();
    if (exactOptionBool(method.options.items, "deprecated")) |deprecated| try tmp.writeBool(33, deprecated);
    if (methodIdempotencyLevel(method.options.items)) |level| try tmp.writeInt32(34, level);
    if (method.features) |features| try writeFeatureSet(allocator, features, 35, &tmp);
    try writeUninterpretedOptions(allocator, method.options.items, &tmp, .method);
    for (method.unknown_options.items) |raw| try tmp.appendSlice(raw);
    try writer.writeMessage(field_number, tmp.slice());
}

fn hasMethodOptions(method: *const schema.MethodDescriptor) bool {
    return method.options.items.len != 0 or method.unknown_options.items.len != 0 or method.features != null;
}

fn writeFileOptions(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, field_number: wire.FieldNumber, writer: *wire.Writer) Error!void {
    var tmp = wire.Writer.init(allocator);
    defer tmp.deinit();
    if (exactOptionString(file.options.items, "java_package")) |value| try tmp.writeString(1, value);
    if (exactOptionString(file.options.items, "java_outer_classname")) |value| try tmp.writeString(8, value);
    if (fileOptimizeMode(file.options.items)) |value| try tmp.writeInt32(9, value);
    if (exactOptionBool(file.options.items, "java_multiple_files")) |value| try tmp.writeBool(10, value);
    if (exactOptionString(file.options.items, "go_package")) |value| try tmp.writeString(11, value);
    if (exactOptionBool(file.options.items, "cc_generic_services")) |value| try tmp.writeBool(16, value);
    if (exactOptionBool(file.options.items, "java_generic_services")) |value| try tmp.writeBool(17, value);
    if (exactOptionBool(file.options.items, "py_generic_services")) |value| try tmp.writeBool(18, value);
    if (exactOptionBool(file.options.items, "java_generate_equals_and_hash")) |value| try tmp.writeBool(20, value);
    if (exactOptionBool(file.options.items, "deprecated")) |value| try tmp.writeBool(23, value);
    if (exactOptionBool(file.options.items, "java_string_check_utf8")) |value| try tmp.writeBool(27, value);
    if (exactOptionBool(file.options.items, "cc_enable_arenas")) |value| try tmp.writeBool(31, value);
    if (exactOptionString(file.options.items, "objc_class_prefix")) |value| try tmp.writeString(36, value);
    if (exactOptionString(file.options.items, "csharp_namespace")) |value| try tmp.writeString(37, value);
    if (exactOptionString(file.options.items, "swift_prefix")) |value| try tmp.writeString(39, value);
    if (exactOptionString(file.options.items, "php_class_prefix")) |value| try tmp.writeString(40, value);
    if (exactOptionString(file.options.items, "php_namespace")) |value| try tmp.writeString(41, value);
    if (exactOptionString(file.options.items, "php_metadata_namespace")) |value| try tmp.writeString(44, value);
    if (exactOptionString(file.options.items, "ruby_package")) |value| try tmp.writeString(45, value);
    if (file.syntax == .editions or hasFeatureOptions(file) or !file.features.eql(schema.FeatureSet.defaults(file.syntax))) try writeFeatureSet(allocator, file.features, 50, &tmp);
    try writeUninterpretedOptions(allocator, file.options.items, &tmp, .file);
    for (file.unknown_options.items) |raw| try tmp.appendSlice(raw);
    try writer.writeMessage(field_number, tmp.slice());
}

fn hasFileOptions(file: *const schema.FileDescriptor) bool {
    // Match protoc: omit an empty FileOptions message. Editions defaults are
    // resolved by the reader and only explicitly set features are serialized.
    return file.options.items.len != 0 or file.unknown_options.items.len != 0 or file.features.present != 0 or file.features.unknown.len != 0;
}

fn writeMessageOptions(allocator: std.mem.Allocator, message: *const schema.MessageDescriptor, field_number: wire.FieldNumber, writer: *wire.Writer) Error!void {
    var tmp = wire.Writer.init(allocator);
    defer tmp.deinit();
    if (exactOptionBool(message.options.items, "message_set_wire_format")) |value| try tmp.writeBool(1, value);
    if (exactOptionBool(message.options.items, "no_standard_descriptor_accessor")) |value| try tmp.writeBool(2, value);
    if (exactOptionBool(message.options.items, "deprecated")) |value| try tmp.writeBool(3, value);
    if (message.map_entry) try tmp.writeBool(7, true);
    if (exactOptionBool(message.options.items, "deprecated_legacy_json_field_conflicts")) |value| try tmp.writeBool(11, value);
    if (message.features) |features| try writeFeatureSet(allocator, features, 12, &tmp);
    try writeUninterpretedOptions(allocator, message.options.items, &tmp, .message);
    for (message.unknown_options.items) |raw| try tmp.appendSlice(raw);
    try writer.writeMessage(field_number, tmp.slice());
}

fn hasMessageOptions(message: *const schema.MessageDescriptor) bool {
    return message.options.items.len != 0 or message.unknown_options.items.len != 0 or message.map_entry or message.features != null;
}

fn writeEnumOptions(allocator: std.mem.Allocator, enumeration: *const schema.EnumDescriptor, field_number: wire.FieldNumber, writer: *wire.Writer) Error!void {
    var tmp = wire.Writer.init(allocator);
    defer tmp.deinit();
    if (enumAllowsAlias(enumeration)) try tmp.writeBool(2, true);
    if (exactOptionBool(enumeration.options.items, "deprecated")) |value| try tmp.writeBool(3, value);
    if (exactOptionBool(enumeration.options.items, "deprecated_legacy_json_field_conflicts")) |value| try tmp.writeBool(6, value);
    if (enumeration.features) |features| try writeFeatureSet(allocator, features, 7, &tmp);
    try writeUninterpretedOptions(allocator, enumeration.options.items, &tmp, .enumeration);
    for (enumeration.unknown_options.items) |raw| try tmp.appendSlice(raw);
    try writer.writeMessage(field_number, tmp.slice());
}

fn hasEnumOptions(enumeration: *const schema.EnumDescriptor) bool {
    return enumeration.options.items.len != 0 or enumeration.unknown_options.items.len != 0 or enumeration.features != null;
}

fn enumAllowsAlias(enumeration: *const schema.EnumDescriptor) bool {
    return enumAliasState(enumeration).allow_alias;
}

const EnumAliasState = struct {
    has_allow_alias: bool = false,
    allow_alias: bool = false,
};

fn enumAliasState(enumeration: *const schema.EnumDescriptor) EnumAliasState {
    for (enumeration.options.items) |option| {
        if (std.mem.eql(u8, option.name, "allow_alias")) {
            return .{ .has_allow_alias = true, .allow_alias = schema.optionAsBool(option.value) orelse false };
        }
    }
    return .{};
}

fn writeFieldOptions(allocator: std.mem.Allocator, field: *const schema.FieldDescriptor, field_number: wire.FieldNumber, writer: *wire.Writer) Error!void {
    var tmp = wire.Writer.init(allocator);
    defer tmp.deinit();
    if (optionEnumNumber(field.options.items, "ctype")) |value| try tmp.writeInt32(1, value);
    if (field.packed_override) |is_packed| {
        if (!hasFeatureOption(field.options.items, "repeated_field_encoding")) try tmp.writeBool(2, is_packed);
    }
    if (exactOptionBool(field.options.items, "deprecated")) |value| try tmp.writeBool(3, value);
    if (exactOptionBool(field.options.items, "lazy")) |value| try tmp.writeBool(5, value);
    if (optionEnumNumber(field.options.items, "jstype")) |value| try tmp.writeInt32(6, value);
    if (exactOptionBool(field.options.items, "weak")) |value| try tmp.writeBool(10, value);
    if (exactOptionBool(field.options.items, "unverified_lazy")) |value| try tmp.writeBool(15, value);
    if (exactOptionBool(field.options.items, "debug_redact")) |value| try tmp.writeBool(16, value);
    if (optionEnumNumber(field.options.items, "retention")) |value| try tmp.writeInt32(17, value);
    for (field.options.items) |option| {
        if (std.mem.eql(u8, std.mem.trim(u8, option.name, " \t\r\n"), "targets")) {
            if (optionEnumNumberValue(option.value)) |value| try tmp.writeInt32(19, value);
        }
    }
    for (field.edition_defaults.items) |edition_default| try writeFieldEditionDefault(allocator, edition_default, 20, &tmp);
    if (field.features) |features| try writeFeatureSet(allocator, features, 21, &tmp);
    if (field.feature_support) |feature_support| try writeFeatureSupport(allocator, feature_support, 22, &tmp);
    try writeUninterpretedOptions(allocator, field.options.items, &tmp, .field);
    for (field.unknown_options.items) |raw| try tmp.appendSlice(raw);
    try writer.writeMessage(field_number, tmp.slice());
}

fn writeFieldEditionDefault(allocator: std.mem.Allocator, edition_default: schema.FieldEditionDefault, field_number: wire.FieldNumber, writer: *wire.Writer) Error!void {
    var tmp = wire.Writer.init(allocator);
    defer tmp.deinit();
    if (edition_default.value.len != 0) try tmp.writeString(2, edition_default.value);
    if (edition_default.edition != .unknown) try tmp.writeInt32(3, @intFromEnum(edition_default.edition));
    try writer.writeMessage(field_number, tmp.slice());
}

fn writeFeatureSupport(allocator: std.mem.Allocator, feature_support: schema.FeatureSupport, field_number: wire.FieldNumber, writer: *wire.Writer) Error!void {
    var tmp = wire.Writer.init(allocator);
    defer tmp.deinit();
    if (feature_support.edition_introduced) |edition| try tmp.writeInt32(1, @intFromEnum(edition));
    if (feature_support.edition_deprecated) |edition| try tmp.writeInt32(2, @intFromEnum(edition));
    if (feature_support.deprecation_warning.len != 0) try tmp.writeString(3, feature_support.deprecation_warning);
    if (feature_support.edition_removed) |edition| try tmp.writeInt32(4, @intFromEnum(edition));
    if (feature_support.removal_error.len != 0) try tmp.writeString(5, feature_support.removal_error);
    try writer.writeMessage(field_number, tmp.slice());
}

fn writeUninterpretedOptions(allocator: std.mem.Allocator, options: []const schema.FieldOption, writer: *wire.Writer, scope: schema.OptionScope) Error!void {
    for (options) |option| {
        if (schema.isKnownOption(option.name, scope)) continue;
        var tmp = wire.Writer.init(allocator);
        defer tmp.deinit();
        try writeOptionName(allocator, option.name, &tmp);
        try writeOptionValue(option.value, &tmp);
        try writer.writeMessage(999, tmp.slice());
    }
}

fn exactOptionBool(options: []const schema.FieldOption, name: []const u8) ?bool {
    for (options) |option| {
        if (std.mem.eql(u8, std.mem.trim(u8, option.name, " \t\r\n"), name)) return schema.optionAsBool(option.value);
    }
    return null;
}

fn exactOptionString(options: []const schema.FieldOption, name: []const u8) ?[]const u8 {
    for (options) |option| {
        if (!std.mem.eql(u8, std.mem.trim(u8, option.name, " \t\r\n"), name)) continue;
        return switch (option.value) {
            .string, .identifier => |value| value,
            else => null,
        };
    }
    return null;
}

fn optionEnumNumber(options: []const schema.FieldOption, name: []const u8) ?i32 {
    for (options) |option| {
        if (std.mem.eql(u8, std.mem.trim(u8, option.name, " \t\r\n"), name)) return optionEnumNumberValue(option.value);
    }
    return null;
}

fn fileOptimizeMode(options: []const schema.FieldOption) ?i32 {
    for (options) |option| {
        if (!std.mem.eql(u8, std.mem.trim(u8, option.name, " \t\r\n"), "optimize_for")) continue;
        switch (option.value) {
            .integer => |value| {
                if (value < std.math.minInt(i32) or value > std.math.maxInt(i32)) return null;
                return @intCast(value);
            },
            .identifier, .string => |value| {
                if (std.mem.eql(u8, value, "SPEED")) return 1;
                if (std.mem.eql(u8, value, "CODE_SIZE")) return 2;
                if (std.mem.eql(u8, value, "LITE_RUNTIME")) return 3;
                return null;
            },
            else => return null,
        }
    }
    return null;
}

fn optionEnumNumberValue(value: schema.OptionValue) ?i32 {
    return switch (value) {
        .integer => |v| if (v >= std.math.minInt(i32) and v <= std.math.maxInt(i32)) @intCast(v) else null,
        .identifier, .string => |text| blk: {
            if (std.mem.eql(u8, text, "STRING") or std.mem.eql(u8, text, "JS_NORMAL") or std.mem.eql(u8, text, "RETENTION_UNKNOWN") or std.mem.eql(u8, text, "TARGET_TYPE_UNKNOWN")) break :blk 0;
            if (std.mem.eql(u8, text, "CORD") or std.mem.eql(u8, text, "JS_STRING") or std.mem.eql(u8, text, "RETENTION_RUNTIME") or std.mem.eql(u8, text, "TARGET_TYPE_FILE")) break :blk 1;
            if (std.mem.eql(u8, text, "STRING_PIECE") or std.mem.eql(u8, text, "JS_NUMBER") or std.mem.eql(u8, text, "RETENTION_SOURCE") or std.mem.eql(u8, text, "TARGET_TYPE_EXTENSION_RANGE")) break :blk 2;
            if (std.mem.eql(u8, text, "TARGET_TYPE_MESSAGE")) break :blk 3;
            if (std.mem.eql(u8, text, "TARGET_TYPE_FIELD")) break :blk 4;
            if (std.mem.eql(u8, text, "TARGET_TYPE_ONEOF")) break :blk 5;
            if (std.mem.eql(u8, text, "TARGET_TYPE_ENUM")) break :blk 6;
            if (std.mem.eql(u8, text, "TARGET_TYPE_ENUM_ENTRY")) break :blk 7;
            if (std.mem.eql(u8, text, "TARGET_TYPE_SERVICE")) break :blk 8;
            if (std.mem.eql(u8, text, "TARGET_TYPE_METHOD")) break :blk 9;
            break :blk null;
        },
        else => null,
    };
}

fn methodIdempotencyLevel(options: []const schema.FieldOption) ?i32 {
    for (options) |option| {
        if (!std.mem.eql(u8, std.mem.trim(u8, option.name, " \t\r\n"), "idempotency_level")) continue;
        switch (option.value) {
            .integer => |value| {
                if (value < std.math.minInt(i32) or value > std.math.maxInt(i32)) return null;
                return @intCast(value);
            },
            .identifier, .string => |value| {
                if (std.mem.eql(u8, value, "IDEMPOTENCY_UNKNOWN")) return 0;
                if (std.mem.eql(u8, value, "NO_SIDE_EFFECTS")) return 1;
                if (std.mem.eql(u8, value, "IDEMPOTENT")) return 2;
                return null;
            },
            else => return null,
        }
    }
    return null;
}

fn writeOptionName(allocator: std.mem.Allocator, name: []const u8, writer: *wire.Writer) Error!void {
    var index: usize = 0;
    var wrote_any = false;
    while (index < name.len) {
        if (name[index] == '.') {
            index += 1;
            continue;
        }
        if (name[index] == '(') {
            const start = index + 1;
            const end = std.mem.indexOfScalarPos(u8, name, start, ')') orelse return error.InvalidFieldType;
            try writeOptionNamePart(allocator, name[start..end], true, writer);
            wrote_any = true;
            index = end + 1;
            continue;
        }
        const start = index;
        while (index < name.len and name[index] != '.' and name[index] != '(') index += 1;
        if (index == start) return error.InvalidFieldType;
        try writeOptionNamePart(allocator, name[start..index], false, writer);
        wrote_any = true;
    }
    if (!wrote_any) return error.InvalidFieldType;
}

fn writeOptionNamePart(allocator: std.mem.Allocator, name_part: []const u8, is_extension: bool, writer: *wire.Writer) Error!void {
    var tmp = wire.Writer.init(allocator);
    defer tmp.deinit();
    try tmp.writeString(1, name_part);
    try tmp.writeBool(2, is_extension);
    try writer.writeMessage(2, tmp.slice());
}

fn writeOptionValue(value: schema.OptionValue, writer: *wire.Writer) Error!void {
    switch (value) {
        .identifier => |text| try writer.writeString(3, text),
        .integer => |v| if (v >= 0) try writer.writeUInt64(4, @intCast(v)) else try writer.writeInt64(5, v),
        .unsigned_integer => |v| try writer.writeUInt64(4, v),
        .float => |v| try writer.writeDouble(6, v),
        .string => |text| try writer.writeBytes(7, text),
        .boolean => |v| try writer.writeString(3, if (v) "true" else "false"),
        .aggregate => |text| try writer.writeString(8, text),
    }
}

fn writeFeatureSet(allocator: std.mem.Allocator, features: schema.FeatureSet, field_number: wire.FieldNumber, writer: *wire.Writer) Error!void {
    var tmp = wire.Writer.init(allocator);
    defer tmp.deinit();
    // Only explicitly set features are serialized, matching protoc's
    // FileDescriptorProto output; inherited/edition defaults are resolved by
    // the reader.
    if (features.hasPresent("field_presence")) try tmp.writeInt32(1, switch (features.field_presence) {
        .explicit => 1,
        .implicit => 2,
        .legacy_required => 3,
    });
    if (features.hasPresent("enum_type")) try tmp.writeInt32(2, switch (features.enum_type) {
        .open => 1,
        .closed => 2,
    });
    if (features.hasPresent("repeated_field_encoding")) try tmp.writeInt32(3, switch (features.repeated_field_encoding) {
        .packed_encoding => 1,
        .expanded => 2,
    });
    if (features.hasPresent("utf8_validation")) try tmp.writeInt32(4, switch (features.utf8_validation) {
        .verify => 2,
        .none => 3,
    });
    if (features.hasPresent("message_encoding")) try tmp.writeInt32(5, switch (features.message_encoding) {
        .length_prefixed => 1,
        .delimited => 2,
    });
    if (features.hasPresent("json_format")) try tmp.writeInt32(6, switch (features.json_format) {
        .allow => 1,
        .legacy_best_effort => 2,
    });
    if (features.hasPresent("enforce_naming_style")) try tmp.writeInt32(7, switch (features.enforce_naming_style) {
        .style2024 => 1,
        .style_legacy => 2,
        .style2026 => 3,
    });
    if (features.hasPresent("default_symbol_visibility")) try tmp.writeInt32(8, switch (features.default_symbol_visibility) {
        .export_all => 1,
        .export_top_level => 2,
        .local_all => 3,
        .strict => 4,
    });
    if (features.hasPresent("enforce_proto_limits")) try tmp.writeInt32(9, switch (features.enforce_proto_limits) {
        .legacy_no_explicit_limits => 1,
        .proto_limits2026 => 2,
    });
    if (features.unknown.len != 0) try tmp.appendSlice(features.unknown);
    if (tmp.slice().len == 0) return;
    try writer.writeMessage(field_number, tmp.slice());
}

/// Serializes a fully-resolved FeatureSet (FeatureSetDefaults entries carry
/// complete feature sets rather than per-scope overrides).
fn writeFeatureSetFull(allocator: std.mem.Allocator, features: schema.FeatureSet, field_number: wire.FieldNumber, writer: *wire.Writer) Error!void {
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
    try tmp.writeInt32(5, switch (features.message_encoding) {
        .length_prefixed => 1,
        .delimited => 2,
    });
    try tmp.writeInt32(6, switch (features.json_format) {
        .allow => 1,
        .legacy_best_effort => 2,
    });
    try tmp.writeInt32(7, switch (features.enforce_naming_style) {
        .style2024 => 1,
        .style_legacy => 2,
        .style2026 => 3,
    });
    try tmp.writeInt32(8, switch (features.default_symbol_visibility) {
        .export_all => 1,
        .export_top_level => 2,
        .local_all => 3,
        .strict => 4,
    });
    try tmp.writeInt32(9, switch (features.enforce_proto_limits) {
        .legacy_no_explicit_limits => 1,
        .proto_limits2026 => 2,
    });
    try writer.writeMessage(field_number, tmp.slice());
}

fn hasFeatureOptions(file: *const schema.FileDescriptor) bool {
    for (file.options.items) |option| {
        if (std.mem.startsWith(u8, option.name, "features.")) return true;
    }
    return false;
}

fn hasFeatureOption(options: []const schema.FieldOption, feature_name: []const u8) bool {
    for (options) |option| {
        const trimmed = std.mem.trim(u8, option.name, " \t\r\n");
        if (!std.mem.startsWith(u8, trimmed, "features.")) continue;
        if (std.mem.eql(u8, schema.optionLeaf(trimmed), feature_name)) return true;
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

fn syntheticOneofIndex(message: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) ?usize {
    var index = message.oneofs.items.len;
    for (message.fields.items) |*candidate| {
        if (candidate.proto3_optional and candidate.oneof_name == null) {
            if (candidate.number == field.number) return index;
            index += 1;
        }
    }
    return null;
}

fn syntheticOneofName(allocator: std.mem.Allocator, field: *const schema.FieldDescriptor) std.mem.Allocator.Error![]const u8 {
    return try std.fmt.allocPrint(allocator, "_{s}", .{field.name});
}

fn oneofIndex(message: *const schema.MessageDescriptor, name: []const u8) ?usize {
    for (message.oneofs.items, 0..) |oneof, index| {
        if (std.mem.eql(u8, oneof.name, name)) return index;
    }
    return null;
}

fn writeDefaultValue(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    registry: ?*const registry_mod.Registry,
    containing_scope: []const u8,
    kind: schema.FieldKind,
    value: schema.OptionValue,
    field_number: wire.FieldNumber,
    writer: *wire.Writer,
) Error!void {
    const text = try defaultValueTextWithRegistry(allocator, file, registry, containing_scope, kind, value);
    defer allocator.free(text);
    try writer.writeString(field_number, text);
}

fn defaultValueText(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, kind: schema.FieldKind, value: schema.OptionValue) Error![]u8 {
    return defaultValueTextWithRegistry(allocator, file, null, "", kind, value);
}

fn defaultValueTextWithRegistry(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    registry: ?*const registry_mod.Registry,
    containing_scope: []const u8,
    kind: schema.FieldKind,
    value: schema.OptionValue,
) Error![]u8 {
    if (kind == .enumeration) {
        if (enumDefaultName(file, registry, containing_scope, kind.enumeration, value)) |name| return try allocator.dupe(u8, name);
    }
    if (kind == .scalar and kind.scalar == .bytes) {
        const bytes = switch (value) {
            .string, .identifier => |text| text,
            else => return optionValueText(allocator, value),
        };
        return try escapeBytesDefaultAlloc(allocator, bytes);
    }
    return switch (kind) {
        .scalar, .enumeration => optionValueText(allocator, value),
        .message, .group, .map => error.InvalidFieldType,
    };
}

fn enumDefaultName(file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, containing_scope: []const u8, enum_name: []const u8, value: schema.OptionValue) ?[]const u8 {
    if (registry) |reg| {
        if (reg.findEnumVisible(file, enum_name, descriptorScopeName(file, containing_scope))) |enumeration| {
            if (enumDefaultNameInDescriptor(enumeration, value)) |name| return name;
        }
    }
    if (file.findEnumDeep(enum_name)) |enumeration| {
        if (enumDefaultNameInDescriptor(enumeration, value)) |name| return name;
    }
    return null;
}

fn enumDefaultNameInDescriptor(enumeration: *const schema.EnumDescriptor, value: schema.OptionValue) ?[]const u8 {
    const number: i32 = switch (value) {
        .integer => |v| if (v >= std.math.minInt(i32) and v <= std.math.maxInt(i32)) @intCast(v) else return null,
        .unsigned_integer => |v| if (v <= std.math.maxInt(i32)) @intCast(v) else return null,
        .identifier, .string => |text| {
            if (enumeration.findValue(text)) |enum_value| return enum_value.name;
            return null;
        },
        else => return null,
    };
    for (enumeration.values.items) |enum_value| {
        if (enum_value.number == number) return enum_value.name;
    }
    return null;
}

fn optionValueText(allocator: std.mem.Allocator, value: schema.OptionValue) std.mem.Allocator.Error![]u8 {
    return switch (value) {
        .identifier => |text| try allocator.dupe(u8, text),
        .string => |text| try allocator.dupe(u8, text),
        .integer => |v| try std.fmt.allocPrint(allocator, "{d}", .{v}),
        .unsigned_integer => |v| try std.fmt.allocPrint(allocator, "{d}", .{v}),
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

fn writeQualifiedExtendeeName(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    registry: ?*const registry_mod.Registry,
    containing_scope: []const u8,
    field: *const schema.FieldDescriptor,
    field_number: wire.FieldNumber,
    writer: *wire.Writer,
) Error!void {
    const extendee = field.extendee orelse return error.InvalidFieldType;
    const resolved = try resolveDescriptorExtendeeName(allocator, file, registry, containing_scope, field, extendee);
    defer allocator.free(resolved);
    try writer.writeString(field_number, resolved);
}

const DescriptorTypeKind = enum { message, enumeration };

fn writeQualifiedTypeName(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    registry: ?*const registry_mod.Registry,
    containing_scope: []const u8,
    type_name: []const u8,
    comptime kind: DescriptorTypeKind,
    field_number: wire.FieldNumber,
    writer: *wire.Writer,
) Error!void {
    const resolved = try resolveDescriptorTypeName(allocator, file, registry, containing_scope, type_name, kind);
    defer allocator.free(resolved);
    try writer.writeString(field_number, resolved);
}

fn qualifiedName(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, name: []const u8) std.mem.Allocator.Error![]u8 {
    if (std.mem.startsWith(u8, name, ".")) return try allocator.dupe(u8, name);
    if (file.package.len == 0) return try std.fmt.allocPrint(allocator, ".{s}", .{name});
    if (std.mem.startsWith(u8, name, file.package)) return try std.fmt.allocPrint(allocator, ".{s}", .{name});
    return try std.fmt.allocPrint(allocator, ".{s}.{s}", .{ file.package, name });
}

fn resolveDescriptorExtendeeName(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    registry: ?*const registry_mod.Registry,
    containing_scope: []const u8,
    field: *const schema.FieldDescriptor,
    extendee: []const u8,
) Error![]u8 {
    if (std.mem.startsWith(u8, extendee, ".")) return try allocator.dupe(u8, extendee);
    if (isCustomOptionExtendee(extendee)) return try std.fmt.allocPrint(allocator, ".{s}", .{descriptorNormalizeName(extendee)});
    if (registry) |reg| {
        var owned_scope: ?[]u8 = null;
        defer if (owned_scope) |scope| allocator.free(scope);
        const scope = try descriptorExtensionScope(allocator, file, containing_scope, field, &owned_scope);
        if (reg.findMessageVisible(file, extendee, scope)) |message| {
            if (reg.fileContainingMessage(message)) |owner| {
                if (try descriptorMessageFullName(allocator, owner, message)) |full_name| return full_name;
            }
        }
    }
    if (typeNameExistsInFile(file, extendee, .message)) return try qualifiedName(allocator, file, extendee);
    var scope = containing_scope;
    while (scope.len != 0) {
        const candidate = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ scope, extendee });
        defer allocator.free(candidate);
        if (typeNameExistsInFile(file, candidate, .message)) return try qualifiedName(allocator, file, candidate);
        if (std.mem.lastIndexOfScalar(u8, scope, '.')) |idx| {
            scope = scope[0..idx];
        } else {
            break;
        }
    }
    return try qualifiedName(allocator, file, extendee);
}

fn descriptorExtensionScope(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    containing_scope: []const u8,
    field: *const schema.FieldDescriptor,
    owned_scope: *?[]u8,
) std.mem.Allocator.Error!?[]const u8 {
    if (field.full_name) |full_name| {
        const normalized = descriptorNormalizeName(full_name);
        if (std.mem.lastIndexOfScalar(u8, normalized, '.')) |idx| return normalized[0..idx];
        return null;
    }
    if (containing_scope.len != 0) {
        if (file.package.len == 0) return containing_scope;
        const scope = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ file.package, containing_scope });
        owned_scope.* = scope;
        return scope;
    }
    return if (file.package.len == 0) null else file.package;
}

fn resolveDescriptorTypeName(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, registry: ?*const registry_mod.Registry, containing_scope: []const u8, type_name: []const u8, comptime kind: DescriptorTypeKind) Error![]u8 {
    if (std.mem.startsWith(u8, type_name, ".")) return try allocator.dupe(u8, type_name);
    if (registry) |reg| {
        const scope = descriptorScopeName(file, containing_scope);
        switch (kind) {
            .message => {
                if (reg.findMessageVisible(file, type_name, scope)) |message| {
                    if (reg.fileContainingMessage(message)) |owner| {
                        if (try descriptorMessageFullName(allocator, owner, message)) |full_name| return full_name;
                    }
                }
            },
            .enumeration => {
                if (reg.findEnumVisible(file, type_name, scope)) |enumeration| {
                    if (reg.fileContainingEnum(enumeration)) |owner| {
                        if (try descriptorEnumFullName(allocator, owner, enumeration)) |full_name| return full_name;
                    }
                }
            },
        }
    }
    if (typeNameExistsInFile(file, type_name, kind)) return try qualifiedName(allocator, file, type_name);
    var scope = containing_scope;
    while (scope.len != 0) {
        const candidate = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ scope, type_name });
        defer allocator.free(candidate);
        if (typeNameExistsInFile(file, candidate, kind)) return try qualifiedName(allocator, file, candidate);
        if (std.mem.lastIndexOfScalar(u8, scope, '.')) |idx| {
            scope = scope[0..idx];
        } else {
            break;
        }
    }
    return try qualifiedName(allocator, file, type_name);
}

fn descriptorMessageFullName(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, target: *const schema.MessageDescriptor) std.mem.Allocator.Error!?[]u8 {
    for (file.messages.items) |*message| {
        if (message == target) return try qualifiedName(allocator, file, message.name);
        if (try descriptorNestedMessagePath(allocator, file, message.name, message, target)) |path| return path;
    }
    return null;
}

fn descriptorNestedMessagePath(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, prefix: []const u8, message: *const schema.MessageDescriptor, target: *const schema.MessageDescriptor) std.mem.Allocator.Error!?[]u8 {
    for (message.messages.items) |*nested| {
        const path = try joinScope(allocator, prefix, nested.name);
        defer allocator.free(path);
        if (nested == target) return try qualifiedName(allocator, file, path);
        if (try descriptorNestedMessagePath(allocator, file, path, nested, target)) |found| return found;
    }
    return null;
}

fn descriptorEnumFullName(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, target: *const schema.EnumDescriptor) std.mem.Allocator.Error!?[]u8 {
    for (file.enums.items) |*enumeration| {
        if (enumeration == target) return try qualifiedName(allocator, file, enumeration.name);
    }
    for (file.messages.items) |*message| {
        if (try descriptorNestedEnumPath(allocator, file, message.name, message, target)) |path| return path;
    }
    return null;
}

fn descriptorNestedEnumPath(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, prefix: []const u8, message: *const schema.MessageDescriptor, target: *const schema.EnumDescriptor) std.mem.Allocator.Error!?[]u8 {
    for (message.enums.items) |*enumeration| {
        const path = try joinScope(allocator, prefix, enumeration.name);
        defer allocator.free(path);
        if (enumeration == target) return try qualifiedName(allocator, file, path);
    }
    for (message.messages.items) |*nested| {
        const path = try joinScope(allocator, prefix, nested.name);
        defer allocator.free(path);
        if (try descriptorNestedEnumPath(allocator, file, path, nested, target)) |found| return found;
    }
    return null;
}

fn typeNameExistsInFile(file: *const schema.FileDescriptor, type_name: []const u8, comptime kind: DescriptorTypeKind) bool {
    return switch (kind) {
        .message => exactMessagePathExists(file, type_name),
        .enumeration => exactEnumPathExists(file, type_name),
    };
}

fn exactMessagePathExists(file: *const schema.FileDescriptor, type_name: []const u8) bool {
    const normalized = normalizeDescriptorTypeName(file, type_name);
    if (normalized.len == 0) return false;
    const first, const rest = splitTypePath(normalized);
    for (file.messages.items) |*message| {
        if (std.mem.eql(u8, message.name, first)) {
            if (rest.len == 0) return true;
            return exactMessagePathExistsInMessage(message, rest);
        }
    }
    return false;
}

fn exactMessagePathExistsInMessage(message: *const schema.MessageDescriptor, path: []const u8) bool {
    const first, const rest = splitTypePath(path);
    for (message.messages.items) |*nested| {
        if (std.mem.eql(u8, nested.name, first)) {
            if (rest.len == 0) return true;
            return exactMessagePathExistsInMessage(nested, rest);
        }
    }
    return false;
}

fn exactEnumPathExists(file: *const schema.FileDescriptor, type_name: []const u8) bool {
    const normalized = normalizeDescriptorTypeName(file, type_name);
    if (normalized.len == 0) return false;
    const first, const rest = splitTypePath(normalized);
    if (rest.len == 0) {
        for (file.enums.items) |*enumeration| {
            if (std.mem.eql(u8, enumeration.name, first)) return true;
        }
        return false;
    }
    for (file.messages.items) |*message| {
        if (std.mem.eql(u8, message.name, first)) return exactEnumPathExistsInMessage(message, rest);
    }
    return false;
}

fn exactEnumPathExistsInMessage(message: *const schema.MessageDescriptor, path: []const u8) bool {
    const first, const rest = splitTypePath(path);
    if (rest.len == 0) {
        for (message.enums.items) |*enumeration| {
            if (std.mem.eql(u8, enumeration.name, first)) return true;
        }
        return false;
    }
    for (message.messages.items) |*nested| {
        if (std.mem.eql(u8, nested.name, first)) return exactEnumPathExistsInMessage(nested, rest);
    }
    return false;
}

fn normalizeDescriptorTypeName(file: *const schema.FileDescriptor, type_name: []const u8) []const u8 {
    var normalized = if (std.mem.startsWith(u8, type_name, ".")) type_name[1..] else type_name;
    if (file.package.len != 0 and std.mem.startsWith(u8, normalized, file.package)) {
        if (normalized.len == file.package.len) return "";
        if (normalized.len > file.package.len and normalized[file.package.len] == '.') normalized = normalized[file.package.len + 1 ..];
    }
    return normalized;
}

fn splitTypePath(path: []const u8) struct { []const u8, []const u8 } {
    if (std.mem.indexOfScalar(u8, path, '.')) |idx| return .{ path[0..idx], path[idx + 1 ..] };
    return .{ path, "" };
}

fn joinScope(allocator: std.mem.Allocator, parent: []const u8, name: []const u8) std.mem.Allocator.Error![]u8 {
    if (parent.len == 0) return try allocator.dupe(u8, name);
    return try std.fmt.allocPrint(allocator, "{s}.{s}", .{ parent, name });
}

fn findNestedMessageByName(message: *const schema.MessageDescriptor, name: []const u8) ?*const schema.MessageDescriptor {
    for (message.messages.items) |*nested| {
        if (std.mem.eql(u8, nested.name, name)) return nested;
    }
    return null;
}

fn findMapFieldByEntryName(message: *const schema.MessageDescriptor, entry_name: []const u8) ?*const schema.FieldDescriptor {
    for (message.fields.items) |*field| {
        if (field.kind != .map) continue;
        if (mapEntryNameEquals(field.name, entry_name)) return field;
    }
    return null;
}

fn mapEntryNameEquals(field_name: []const u8, entry_name: []const u8) bool {
    var index: usize = 0;
    var capitalize_next = true;
    for (field_name) |c| {
        if (c == '_') {
            capitalize_next = true;
            continue;
        }
        if (index >= entry_name.len) return false;
        const expected = if (capitalize_next) std.ascii.toUpper(c) else c;
        if (entry_name[index] != expected) return false;
        index += 1;
        capitalize_next = false;
    }
    return entry_name.len == index + "Entry".len and std.mem.eql(u8, entry_name[index..], "Entry");
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

fn appendFileDescriptor(allocator: std.mem.Allocator, list: *std.ArrayList(schema.FileDescriptor), value: schema.FileDescriptor) std.mem.Allocator.Error!void {
    var owned = value;
    errdefer owned.deinit();
    try list.append(allocator, owned);
}

fn appendMessageDescriptor(allocator: std.mem.Allocator, list: *std.ArrayList(schema.MessageDescriptor), value: schema.MessageDescriptor) std.mem.Allocator.Error!void {
    var owned = value;
    errdefer owned.deinit(allocator);
    try list.append(allocator, owned);
}

fn appendEnumDescriptor(allocator: std.mem.Allocator, list: *std.ArrayList(schema.EnumDescriptor), value: schema.EnumDescriptor) std.mem.Allocator.Error!void {
    var owned = value;
    errdefer owned.deinit(allocator);
    try list.append(allocator, owned);
}

fn appendServiceDescriptor(allocator: std.mem.Allocator, list: *std.ArrayList(schema.ServiceDescriptor), value: schema.ServiceDescriptor) std.mem.Allocator.Error!void {
    var owned = value;
    errdefer owned.deinit(allocator);
    try list.append(allocator, owned);
}

fn appendMethodDescriptor(allocator: std.mem.Allocator, list: *std.ArrayList(schema.MethodDescriptor), value: schema.MethodDescriptor) std.mem.Allocator.Error!void {
    var owned = value;
    errdefer owned.deinit(allocator);
    try list.append(allocator, owned);
}

fn appendFieldDescriptor(allocator: std.mem.Allocator, list: *std.ArrayList(schema.FieldDescriptor), value: schema.FieldDescriptor) std.mem.Allocator.Error!void {
    var owned = value;
    errdefer owned.deinit(allocator);
    try list.append(allocator, owned);
}

fn appendEnumValueDescriptor(allocator: std.mem.Allocator, list: *std.ArrayList(schema.EnumValueDescriptor), value: schema.EnumValueDescriptor) std.mem.Allocator.Error!void {
    var owned = value;
    errdefer owned.deinit(allocator);
    try list.append(allocator, owned);
}

fn appendOneofDescriptor(allocator: std.mem.Allocator, list: *std.ArrayList(schema.OneofDescriptor), value: schema.OneofDescriptor) std.mem.Allocator.Error!void {
    var owned = value;
    errdefer owned.deinit(allocator);
    try list.append(allocator, owned);
}

fn appendExtensionRange(allocator: std.mem.Allocator, list: *std.ArrayList(schema.ExtensionRange), value: schema.ExtensionRange) std.mem.Allocator.Error!void {
    var owned = value;
    errdefer owned.deinit(allocator);
    try list.append(allocator, owned);
}

fn appendSourceCodeInfoLocation(allocator: std.mem.Allocator, list: *std.ArrayList(schema.SourceCodeInfo.Location), value: schema.SourceCodeInfo.Location) std.mem.Allocator.Error!void {
    var owned = value;
    errdefer owned.deinit(allocator);
    try list.append(allocator, owned);
}

fn appendGeneratedCodeInfoAnnotation(allocator: std.mem.Allocator, list: *std.ArrayList(schema.GeneratedCodeInfo.Annotation), value: schema.GeneratedCodeInfo.Annotation) std.mem.Allocator.Error!void {
    var owned = value;
    errdefer owned.deinit(allocator);
    try list.append(allocator, owned);
}

fn appendFieldOption(allocator: std.mem.Allocator, list: *schema.OptionList, value: schema.FieldOption) std.mem.Allocator.Error!void {
    const owned = value;
    errdefer if (owned.name_owned) allocator.free(owned.name);
    try list.append(allocator, owned);
}

pub fn decodeFileDescriptorProto(allocator: std.mem.Allocator, bytes: []const u8) Error!schema.FileDescriptor {
    var file = schema.FileDescriptor.init(allocator);
    errdefer file.deinit();
    var public_deps: std.ArrayList(i32) = .empty;
    defer public_deps.deinit(allocator);
    var weak_deps: std.ArrayList(i32) = .empty;
    defer weak_deps.deinit(allocator);
    var decoded_file_features: ?schema.FeatureSet = null;
    var saw_syntax: ?schema.Syntax = null;
    var saw_edition_field = false;
    const owned_bytes = try allocator.dupe(u8, bytes);
    var owns_owned_bytes = true;
    errdefer if (owns_owned_bytes) allocator.free(owned_bytes);
    try file.owned_strings.append(allocator, owned_bytes);
    owns_owned_bytes = false;

    var reader = wire.Reader.init(owned_bytes);
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            1 => file.name = try reader.readBytes(),
            2 => file.package = try reader.readBytes(),
            3 => try file.imports.append(allocator, .{ .path = try reader.readBytes() }),
            10 => try public_deps.append(allocator, try reader.readInt32()),
            11 => try weak_deps.append(allocator, try reader.readInt32()),
            15 => try file.imports.append(allocator, .{ .path = try reader.readBytes(), .kind = .option }),
            4 => try appendMessageDescriptor(allocator, &file.messages, try decodeMessageDescriptor(allocator, &file.owned_strings, try reader.readBytes())),
            5 => try appendEnumDescriptor(allocator, &file.enums, try decodeEnumDescriptor(allocator, try reader.readBytes())),
            6 => try appendServiceDescriptor(allocator, &file.services, try decodeServiceDescriptor(allocator, try reader.readBytes())),
            7 => try appendFieldDescriptor(allocator, &file.extensions, try decodeFieldDescriptor(allocator, &file.owned_strings, try reader.readBytes())),
            8 => {
                if (try decodeFileOptions(allocator, &file, try reader.readBytes())) |features| decoded_file_features = features;
            },
            9 => {
                var source_code_info = try decodeSourceCodeInfo(allocator, try reader.readBytes());
                errdefer source_code_info.deinit(allocator);
                file.source_code_info.deinit(allocator);
                file.source_code_info = source_code_info;
            },
            12 => {
                const syntax = try reader.readBytes();
                if (std.mem.eql(u8, syntax, "proto2")) {
                    saw_syntax = .proto2;
                    file.syntax = .proto2;
                    file.edition = schema.Syntax.proto2.defaultEdition();
                    file.features = schema.FeatureSet.defaults(.proto2);
                } else if (std.mem.eql(u8, syntax, "proto3")) {
                    saw_syntax = .proto3;
                    file.syntax = .proto3;
                    file.edition = schema.Syntax.proto3.defaultEdition();
                    file.features = schema.FeatureSet.defaults(.proto3);
                } else if (std.mem.eql(u8, syntax, "editions")) {
                    saw_syntax = .editions;
                    file.syntax = .editions;
                    if (!saw_edition_field) file.edition = schema.Syntax.editions.defaultEdition();
                    file.features = schema.FeatureSet.defaultsForEdition(file.edition);
                } else return error.InvalidFieldType;
            },
            14 => {
                saw_edition_field = true;
                file.syntax = .editions;
                file.edition = std.enums.fromInt(schema.Edition, try reader.readInt32()) orelse return error.InvalidFieldType;
                file.features = schema.FeatureSet.defaultsForEdition(file.edition);
            },
            else => try reader.skipValue(tag),
        }
    }
    // File-level features in a FileDescriptorProto carry only explicitly set
    // values; resolve them over the edition defaults.
    if (decoded_file_features) |features| file.features = features.mergeInherited(file.features);
    try validateDecodedFileEdition(&file, saw_syntax, saw_edition_field);
    try validateImportList(file.imports.items);
    try validateDependencyIndexes(public_deps.items, weak_deps.items, file.imports.items.len);
    for (public_deps.items) |idx| {
        if (idx < 0 or idx >= file.imports.items.len) return error.InvalidFieldType;
        file.imports.items[@intCast(idx)].kind = .public;
    }
    for (weak_deps.items) |idx| {
        if (idx < 0 or idx >= file.imports.items.len) return error.InvalidFieldType;
        file.imports.items[@intCast(idx)].kind = .weak;
    }
    try assignDecodedExtensionFullNames(allocator, &file);
    try validateDecodedImportSemantics(&file);
    try collapseMapEntryMessages(allocator, &file);
    resolveDecodedEnumDefaults(&file);
    try validateDecodedFileDescriptor(&file);
    try validateDecodedPackedOptions(&file);
    try validateDecodedDefaults(&file);
    try validateDecodedFieldSyntax(&file);
    try validateDecodedFeatureApplicability(&file);
    try validateDecodedEnumSyntax(&file);
    try validateDecodedMessageSets(&file);
    try validateDecodedExtensionDeclarations(&file);
    return file;
}

fn validateDecodedFileEdition(file: *const schema.FileDescriptor, saw_syntax: ?schema.Syntax, saw_edition_field: bool) Error!void {
    if (saw_edition_field) {
        if (saw_syntax) |syntax| {
            if (syntax != .editions) return error.InvalidFieldType;
        }
    }
    if (file.syntax != .editions) return;
    switch (file.edition) {
        .unknown, .max => return error.InvalidFieldType,
        else => {},
    }
}

fn validateImportList(imports: []const schema.Import) Error!void {
    for (imports, 0..) |import, i| {
        if (import.path.len == 0) return error.InvalidFieldType;
        for (imports[i + 1 ..]) |other| {
            if (std.mem.eql(u8, import.path, other.path)) return error.InvalidFieldType;
        }
    }
}

fn validateDecodedImportSemantics(file: *const schema.FileDescriptor) Error!void {
    for (file.imports.items) |import| {
        if (import.kind == .option) {
            if (@intFromEnum(file.edition) < @intFromEnum(schema.Edition.edition_2024)) return error.InvalidFieldType;
            continue;
        }
        if (@intFromEnum(file.edition) >= @intFromEnum(schema.Edition.edition_2024) and import.kind == .weak) return error.InvalidFieldType;
    }
}

fn validateDependencyIndexes(public_deps: []const i32, weak_deps: []const i32, dependency_count: usize) Error!void {
    for (public_deps, 0..) |idx, i| {
        if (idx < 0 or idx >= dependency_count) return error.InvalidFieldType;
        for (public_deps[i + 1 ..]) |other| {
            if (idx == other) return error.InvalidFieldType;
        }
        for (weak_deps) |weak| {
            if (idx == weak) return error.InvalidFieldType;
        }
    }
    for (weak_deps, 0..) |idx, i| {
        if (idx < 0 or idx >= dependency_count) return error.InvalidFieldType;
        for (weak_deps[i + 1 ..]) |other| {
            if (idx == other) return error.InvalidFieldType;
        }
    }
}

fn assignDecodedExtensionFullNames(allocator: std.mem.Allocator, file: *schema.FileDescriptor) std.mem.Allocator.Error!void {
    for (file.extensions.items) |*field| field.full_name = null;
    for (file.messages.items) |*message| try assignDecodedMessageExtensionFullNames(allocator, file, message, file.package);
}

fn assignDecodedMessageExtensionFullNames(allocator: std.mem.Allocator, file: *schema.FileDescriptor, message: *schema.MessageDescriptor, parent_scope: []const u8) std.mem.Allocator.Error!void {
    const scope = try decodedQualifiedName(allocator, &file.owned_strings, parent_scope, message.name);
    for (message.extensions.items) |*field| field.full_name = try decodedQualifiedName(allocator, &file.owned_strings, scope, field.name);
    for (message.messages.items) |*nested| try assignDecodedMessageExtensionFullNames(allocator, file, nested, scope);
}

fn validateDecodedFileDescriptor(file: *const schema.FileDescriptor) Error!void {
    if (file.package.len != 0 and !isFullIdentifier(file.package)) return error.InvalidFieldType;
    for (file.messages.items, 0..) |message, i| {
        if (!isIdentifier(message.name)) return error.InvalidFieldType;
        if (message.map_entry) return error.InvalidFieldType;
        for (file.messages.items[i + 1 ..]) |other| {
            if (std.mem.eql(u8, message.name, other.name)) return error.InvalidFieldType;
        }
        for (file.enums.items) |enumeration| {
            if (std.mem.eql(u8, message.name, enumeration.name)) return error.InvalidFieldType;
        }
        for (file.services.items) |service| {
            if (std.mem.eql(u8, message.name, service.name)) return error.InvalidFieldType;
        }
    }
    for (file.enums.items, 0..) |enumeration, i| {
        if (!isIdentifier(enumeration.name)) return error.InvalidFieldType;
        for (file.enums.items[i + 1 ..]) |other| {
            if (std.mem.eql(u8, enumeration.name, other.name)) return error.InvalidFieldType;
        }
        for (file.services.items) |service| {
            if (std.mem.eql(u8, enumeration.name, service.name)) return error.InvalidFieldType;
        }
    }
    for (file.services.items, 0..) |service, i| {
        if (!isIdentifier(service.name)) return error.InvalidFieldType;
        for (file.services.items[i + 1 ..]) |other| {
            if (std.mem.eql(u8, service.name, other.name)) return error.InvalidFieldType;
        }
        for (service.methods.items) |method| {
            try validateDecodedServiceMethodType(file, method.input_type);
            try validateDecodedServiceMethodType(file, method.output_type);
        }
    }
    for (file.extensions.items, 0..) |extension, i| {
        if (!isIdentifier(extension.name)) return error.InvalidFieldType;
        for (file.messages.items) |message| {
            if (std.mem.eql(u8, extension.name, message.name)) return error.InvalidFieldType;
        }
        for (file.enums.items) |enumeration| {
            if (std.mem.eql(u8, extension.name, enumeration.name)) return error.InvalidFieldType;
        }
        for (file.services.items) |service| {
            if (std.mem.eql(u8, extension.name, service.name)) return error.InvalidFieldType;
        }
        for (file.extensions.items[i + 1 ..]) |other| {
            if (std.mem.eql(u8, extension.name, other.name)) return error.InvalidFieldType;
        }
    }
    try validateDecodedFileEnumValueSymbols(file);
    if (file.syntax == .proto3) {
        for (file.messages.items) |*message| try validateDecodedNoProto3ExtensionRanges(message);
    }
    for (file.extensions.items) |field| try validateDecodedExtensionFieldDescriptor(&field);
}

fn validateDecodedServiceMethodType(file: *const schema.FileDescriptor, type_name: []const u8) Error!void {
    if (file.findMessageDeep(type_name) != null) return;
    if (file.findEnumDeep(type_name) != null) return error.InvalidFieldType;
}

fn validateDecodedNoProto3ExtensionRanges(message: *const schema.MessageDescriptor) Error!void {
    if (message.extension_ranges.items.len != 0) return error.InvalidFieldType;
    for (message.messages.items) |*nested| try validateDecodedNoProto3ExtensionRanges(nested);
}

fn validateDecodedFileEnumValueSymbols(file: *const schema.FileDescriptor) Error!void {
    for (file.enums.items, 0..) |*enumeration, enum_index| {
        for (enumeration.values.items) |value| {
            for (file.messages.items) |message| {
                if (std.mem.eql(u8, value.name, message.name)) return error.InvalidFieldType;
            }
            for (file.enums.items) |other_enum| {
                if (std.mem.eql(u8, value.name, other_enum.name)) return error.InvalidFieldType;
            }
            for (file.services.items) |service| {
                if (std.mem.eql(u8, value.name, service.name)) return error.InvalidFieldType;
            }
            for (file.extensions.items) |extension| {
                if (std.mem.eql(u8, value.name, extension.name)) return error.InvalidFieldType;
            }
            for (file.enums.items[enum_index + 1 ..]) |other_enum| {
                for (other_enum.values.items) |other_value| {
                    if (std.mem.eql(u8, value.name, other_value.name)) return error.InvalidFieldType;
                }
            }
        }
    }
}

fn isIdentifier(value: []const u8) bool {
    return schema.isIdentifier(value);
}

fn isTypeNameReference(value: []const u8) bool {
    if (value.len == 0) return false;
    const normalized = if (std.mem.startsWith(u8, value, ".")) value[1..] else value;
    return isFullIdentifier(normalized);
}

fn isExtensionDeclarationTypeName(value: []const u8) bool {
    return schema.declarationTypeNameIsScalar(value) or schema.declarationSymbolIsQualified(value);
}

fn isFullIdentifier(value: []const u8) bool {
    return schema.isFullIdentifier(value);
}

fn validateDecodedExtensionDeclarations(file: *const schema.FileDescriptor) Error!void {
    for (file.extensions.items) |*field| {
        try validateDecodedExtensionConflict(file, file.package, field);
        try validateDecodedExtensionDeclaration(file, field);
    }
    for (file.messages.items) |*message| try validateDecodedMessageExtensionDeclarations(file, message);
}

fn validateDecodedMessageExtensionDeclarations(file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor) Error!void {
    for (message.extensions.items) |*field| {
        try validateDecodedExtensionConflict(file, file.package, field);
        try validateDecodedExtensionDeclaration(file, field);
    }
    for (message.messages.items) |*nested| try validateDecodedMessageExtensionDeclarations(file, nested);
}

fn validateDecodedExtensionFieldDescriptor(field: *const schema.FieldDescriptor) Error!void {
    const extendee = field.extendee orelse return error.InvalidFieldType;
    if (!isTypeNameReference(extendee)) return error.InvalidFieldType;
    try validateDecodedFieldJsonName(field, true);
}

fn validateDecodedDefaults(file: *const schema.FileDescriptor) Error!void {
    for (file.extensions.items) |*field| try validateDecodedFieldDefault(file, field);
    for (file.messages.items) |*message| try validateDecodedMessageDefaults(file, message);
}

fn validateDecodedMessageDefaults(file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor) Error!void {
    for (message.fields.items) |*field| try validateDecodedFieldDefault(file, field);
    for (message.extensions.items) |*field| try validateDecodedFieldDefault(file, field);
    for (message.messages.items) |*nested| try validateDecodedMessageDefaults(file, nested);
}

fn validateDecodedFieldDefault(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor) Error!void {
    const value = field.default_value orelse return;
    if (file.syntax == .proto3) return error.InvalidFieldType;
    if (field.cardinality == .repeated or field.kind == .map or field.proto3_optional) return error.InvalidFieldType;
    switch (field.kind) {
        .scalar => |scalar| try validateDecodedScalarDefault(scalar, value),
        .enumeration => |name| try validateDecodedEnumDefault(file, name, value),
        .message, .group => return error.InvalidFieldType,
        .map => return error.InvalidFieldType,
    }
}

fn validateDecodedScalarDefault(scalar: schema.ScalarType, value: schema.OptionValue) Error!void {
    switch (scalar) {
        .double, .float => switch (value) {
            .float => {},
            else => return error.InvalidFieldType,
        },
        .int32, .int64, .sint32, .sint64, .sfixed32, .sfixed64, .uint32, .uint64, .fixed32, .fixed64 => switch (value) {
            .integer, .unsigned_integer => {},
            else => return error.InvalidFieldType,
        },
        .bool => switch (value) {
            .boolean => {},
            else => return error.InvalidFieldType,
        },
        .string, .bytes => switch (value) {
            .string => {},
            else => return error.InvalidFieldType,
        },
    }
}

fn validateDecodedEnumDefault(file: *const schema.FileDescriptor, enum_name: []const u8, value: schema.OptionValue) Error!void {
    switch (value) {
        .integer => return,
        .identifier => |default_name| {
            if (!isIdentifier(default_name)) return error.InvalidFieldType;
            const enumeration = file.findEnumDeep(enum_name) orelse return;
            if (enumeration.findValue(default_name) == null) return error.InvalidFieldType;
        },
        else => return error.InvalidFieldType,
    }
}

fn validateDecodedPackedOptions(file: *const schema.FileDescriptor) Error!void {
    for (file.extensions.items) |*field| try validateDecodedPackedOption(file, field);
    for (file.messages.items) |*message| try validateDecodedMessagePackedOptions(file, message);
}

fn validateDecodedMessagePackedOptions(file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor) Error!void {
    for (message.fields.items) |*field| try validateDecodedPackedOption(file, field);
    for (message.extensions.items) |*field| try validateDecodedPackedOption(file, field);
    for (message.messages.items) |*nested| try validateDecodedMessagePackedOptions(file, nested);
}

fn validateDecodedPackedOption(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor) Error!void {
    const is_packed = field.packed_override orelse return;
    if (file.syntax == .editions) return error.InvalidFieldType;
    // protoc only rejects `packed = true` on non-packable fields; an explicit
    // `packed = false` is a legal no-op and is emitted in descriptor sets.
    if (is_packed and !field.isPackable()) return error.InvalidFieldType;
}

fn validateDecodedFieldSyntax(file: *const schema.FileDescriptor) Error!void {
    for (file.extensions.items) |*field| try validateDecodedFieldSyntaxOne(file, field, true);
    for (file.messages.items) |*message| try validateDecodedMessageFieldSyntax(file, message);
}

fn validateDecodedFeatureApplicability(file: *const schema.FileDescriptor) Error!void {
    if (file.syntax == .editions) return;
    if (!file.features.eql(schema.FeatureSet.defaults(file.syntax))) return error.InvalidFieldType;
    for (file.messages.items) |*message| try validateDecodedMessageFeaturesAbsent(message);
    for (file.enums.items) |*enumeration| try validateDecodedEnumFeaturesAbsent(enumeration);
    for (file.services.items) |*service| try validateDecodedServiceFeaturesAbsent(service);
    for (file.extensions.items) |*field| {
        if (field.features != null) return error.InvalidFieldType;
    }
}

fn validateDecodedMessageFeaturesAbsent(message: *const schema.MessageDescriptor) Error!void {
    if (message.features != null) return error.InvalidFieldType;
    for (message.fields.items) |*field| {
        if (field.features != null) return error.InvalidFieldType;
    }
    for (message.oneofs.items) |*oneof| {
        if (oneof.features != null) return error.InvalidFieldType;
    }
    for (message.extension_ranges.items) |*range| {
        if (range.features != null) return error.InvalidFieldType;
    }
    for (message.extensions.items) |*field| {
        if (field.features != null) return error.InvalidFieldType;
    }
    for (message.messages.items) |*nested| try validateDecodedMessageFeaturesAbsent(nested);
    for (message.enums.items) |*enumeration| try validateDecodedEnumFeaturesAbsent(enumeration);
}

fn validateDecodedEnumFeaturesAbsent(enumeration: *const schema.EnumDescriptor) Error!void {
    if (enumeration.features != null) return error.InvalidFieldType;
    for (enumeration.values.items) |*value| {
        if (value.features != null) return error.InvalidFieldType;
    }
}

fn validateDecodedServiceFeaturesAbsent(service: *const schema.ServiceDescriptor) Error!void {
    if (service.features != null) return error.InvalidFieldType;
    for (service.methods.items) |*method| {
        if (method.features != null) return error.InvalidFieldType;
    }
}

fn validateDecodedMessageFieldSyntax(file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor) Error!void {
    for (message.fields.items) |*field| try validateDecodedFieldSyntaxOne(file, field, false);
    for (message.extensions.items) |*field| try validateDecodedFieldSyntaxOne(file, field, true);
    for (message.messages.items) |*nested| try validateDecodedMessageFieldSyntax(file, nested);
}

fn validateDecodedFieldSyntaxOne(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, is_extension: bool) Error!void {
    if (is_extension) {
        if (field.extendee == null or field.oneof_name != null) return error.InvalidFieldType;
        // protoc keeps proto3_optional on `optional` extensions of options
        // messages even though they have no synthetic oneof.
    } else if (field.extendee != null) return error.InvalidFieldType;
    if (field.cardinality == .required and file.syntax != .proto2) return error.InvalidFieldType;
    if (field.cardinality == .required and is_extension) return error.InvalidFieldType;
    if (file.syntax == .proto3 and is_extension and !isCustomOptionExtendee(field.extendee orelse "")) return error.InvalidFieldType;
    if (field.proto3_optional and file.syntax != .proto3) return error.InvalidFieldType;
    if (file.syntax == .editions and field.kind == .group) return error.InvalidFieldType;
    if (field.kind == .group and !groupTypeNameStartsWithCapital(field.kind.group)) return error.InvalidFieldType;
    try validateDecodedFieldOptionApplicability(file, field, is_extension);
}

fn groupTypeNameStartsWithCapital(type_name: []const u8) bool {
    const leaf = leafTypeName(type_name);
    return leaf.len != 0 and leaf[0] >= 'A' and leaf[0] <= 'Z';
}

fn isCustomOptionExtendee(name: []const u8) bool {
    const normalized = descriptorNormalizeName(name);
    inline for (.{
        "google.protobuf.FileOptions",
        "google.protobuf.MessageOptions",
        "google.protobuf.FieldOptions",
        "google.protobuf.OneofOptions",
        "google.protobuf.EnumOptions",
        "google.protobuf.EnumValueOptions",
        "google.protobuf.ServiceOptions",
        "google.protobuf.MethodOptions",
        "google.protobuf.ExtensionRangeOptions",
    }) |option_name| {
        if (std.mem.eql(u8, normalized, option_name)) return true;
    }
    return false;
}

fn validateDecodedFieldOptionApplicability(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, is_extension: bool) Error!void {
    if (@intFromEnum(file.edition) >= @intFromEnum(schema.Edition.edition_2024) and optionEnumNumber(field.options.items, "ctype") != null) return error.InvalidFieldType;
    if (optionEnumNumber(field.options.items, "jstype")) |jstype| {
        if (jstype != 0 and !fieldKindAllowsJSType(field.kind)) return error.InvalidFieldType;
    }
    const lazy = exactOptionBool(field.options.items, "lazy") orelse false;
    const unverified_lazy = exactOptionBool(field.options.items, "unverified_lazy") orelse false;
    const weak = exactOptionBool(field.options.items, "weak") orelse false;
    if (lazy or unverified_lazy) {
        if (!fieldKindIsSubmessage(field.kind)) return error.InvalidFieldType;
    }
    if (unverified_lazy and is_extension) return error.InvalidFieldType;
    if (weak) {
        if (field.kind != .message or is_extension or field.oneof_name != null or field.cardinality == .repeated) return error.InvalidFieldType;
    }
}

fn fieldKindAllowsJSType(kind: schema.FieldKind) bool {
    return switch (kind) {
        .scalar => |scalar| switch (scalar) {
            .int64, .uint64, .sint64, .fixed64, .sfixed64 => true,
            else => false,
        },
        else => false,
    };
}

fn fieldKindIsSubmessage(kind: schema.FieldKind) bool {
    return switch (kind) {
        .message, .group => true,
        else => false,
    };
}

fn validateDecodedMessageSets(file: *const schema.FileDescriptor) Error!void {
    for (file.messages.items) |*message| try validateDecodedMessageSetMessage(file, message);
}

fn validateDecodedMessageSetMessage(file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor) Error!void {
    if (message.messageSetWireFormat()) {
        if (file.syntax == .proto3) return error.InvalidFieldType;
        if (message.fields.items.len != 0) return error.InvalidFieldType;
    }
    for (file.extensions.items) |*field| try validateDecodedMessageSetExtension(file, message, field);
    for (file.messages.items) |*scope| try validateDecodedMessageSetExtensionsInMessage(file, message, scope);
    for (message.messages.items) |*nested| try validateDecodedMessageSetMessage(file, nested);
}

fn validateDecodedMessageSetExtensionsInMessage(file: *const schema.FileDescriptor, message_set: *const schema.MessageDescriptor, scope: *const schema.MessageDescriptor) Error!void {
    for (scope.extensions.items) |*field| try validateDecodedMessageSetExtension(file, message_set, field);
    for (scope.messages.items) |*nested| try validateDecodedMessageSetExtensionsInMessage(file, message_set, nested);
}

fn validateDecodedMessageSetExtension(file: *const schema.FileDescriptor, message_set: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) Error!void {
    if (!message_set.messageSetWireFormat()) return;
    const extendee = field.extendee orelse return;
    const extendee_message = file.findMessageDeep(extendee) orelse return;
    if (extendee_message != message_set) return;
    if (field.cardinality == .repeated or field.cardinality == .required) return error.InvalidFieldType;
    switch (field.kind) {
        .message => {},
        else => return error.InvalidFieldType,
    }
}

fn validateDecodedEnumSyntax(file: *const schema.FileDescriptor) Error!void {
    if (file.syntax != .proto3) return;
    for (file.enums.items) |*enumeration| try validateDecodedProto3Enum(enumeration);
    for (file.messages.items) |*message| try validateDecodedMessageEnumSyntax(message);
}

fn validateDecodedMessageEnumSyntax(message: *const schema.MessageDescriptor) Error!void {
    for (message.enums.items) |*enumeration| try validateDecodedProto3Enum(enumeration);
    for (message.messages.items) |*nested| try validateDecodedMessageEnumSyntax(nested);
}

fn validateDecodedProto3Enum(enumeration: *const schema.EnumDescriptor) Error!void {
    if (enumeration.values.items.len == 0 or enumeration.values.items[0].number != 0) return error.InvalidFieldType;
}

fn validateDecodedExtensionConflict(file: *const schema.FileDescriptor, package: []const u8, field: *const schema.FieldDescriptor) Error!void {
    for (file.extensions.items) |*other| try validateDecodedExtensionConflictPair(package, field, package, other);
    for (file.messages.items) |*message| try validateDecodedExtensionConflictInMessage(package, field, package, message);
}

fn validateDecodedExtensionConflictInMessage(field_package: []const u8, field: *const schema.FieldDescriptor, message_package: []const u8, message: *const schema.MessageDescriptor) Error!void {
    for (message.extensions.items) |*other| try validateDecodedExtensionConflictPair(field_package, field, message_package, other);
    for (message.messages.items) |*nested| try validateDecodedExtensionConflictInMessage(field_package, field, message_package, nested);
}

fn validateDecodedExtensionConflictPair(field_package: []const u8, field: *const schema.FieldDescriptor, other_package: []const u8, other: *const schema.FieldDescriptor) Error!void {
    if (field == other) return;
    const extendee = field.extendee orelse return;
    const other_extendee = other.extendee orelse return;
    if (!descriptorNamesMatch(extendee, other_extendee)) return;
    if (field.number == other.number) return error.InvalidFieldType;
    if (schema.extensionSymbolsEqualWithPackages(field_package, field, other_package, other)) return error.InvalidFieldType;
}

fn validateDecodedExtensionDeclaration(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor) Error!void {
    const extendee_name = field.extendee orelse return;
    const extendee = file.findMessageDeep(extendee_name) orelse return;
    for (extendee.extension_ranges.items) |range| {
        if (range.containsInMessage(extendee, field.number)) {
            return try validateDecodedExtensionFieldDeclaration(file.package, field, extendee, range);
        }
    }
    return error.InvalidFieldType;
}

fn validateDecodedExtensionFieldDeclaration(package: []const u8, field: *const schema.FieldDescriptor, extendee: *const schema.MessageDescriptor, range: schema.ExtensionRange) Error!void {
    var matching_declaration: ?schema.ExtensionDeclaration = null;
    const end = range.effectiveEnd(extendee);
    for (range.declarations.items) |declaration| {
        if (declaration.number <= 0) return error.InvalidFieldType;
        if (declaration.number < range.start or declaration.number >= end) return error.InvalidFieldType;
        if (declaration.number == @as(i32, @intCast(field.number))) matching_declaration = declaration;
    }
    const declaration = matching_declaration orelse {
        if (range.verification == .declaration or range.declarations.items.len != 0) return error.InvalidFieldType;
        return;
    };
    if (declaration.reserved) return error.InvalidFieldType;
    if (declaration.full_name.len != 0 and !schema.extensionDeclarationNameMatches(package, declaration.full_name, field)) return error.InvalidFieldType;
    if (declaration.repeated and field.cardinality != .repeated) return error.InvalidFieldType;
    if (!declaration.repeated and field.cardinality == .repeated) return error.InvalidFieldType;
    if (declaration.type_name.len != 0 and !descriptorExtensionTypeMatches(package, field, declaration.type_name)) return error.InvalidFieldType;
}

fn descriptorNormalizeName(name: []const u8) []const u8 {
    return if (std.mem.startsWith(u8, name, ".")) name[1..] else name;
}

fn descriptorNamesMatch(a: []const u8, b: []const u8) bool {
    const na = descriptorNormalizeName(a);
    const nb = descriptorNormalizeName(b);
    return std.mem.eql(u8, na, nb) or std.mem.endsWith(u8, na, nb) or std.mem.endsWith(u8, nb, na);
}

fn descriptorExtensionTypeMatches(package: []const u8, field: *const schema.FieldDescriptor, declared_type: []const u8) bool {
    return switch (field.kind) {
        .message, .enumeration, .group => |type_name| descriptorDeclarationTypeMatches(package, field, declared_type, type_name),
        .scalar => |scalar| std.mem.eql(u8, declared_type, schema.scalarTypeName(scalar)),
        .map => false,
    };
}

fn descriptorDeclarationTypeMatches(package: []const u8, field: *const schema.FieldDescriptor, declaration: []const u8, type_name: []const u8) bool {
    const declared = descriptorNormalizeName(declaration);
    const actual = descriptorNormalizeName(type_name);
    if (std.mem.eql(u8, declared, actual)) return true;
    if (package.len == 0 or std.mem.startsWith(u8, type_name, ".")) return false;
    if (declared.len == package.len + 1 + actual.len and
        std.mem.eql(u8, declared[0..package.len], package) and
        declared[package.len] == '.' and
        std.mem.eql(u8, declared[package.len + 1 ..], actual)) return true;
    const full_name = schema.extensionFullName(field);
    const scope = if (std.mem.lastIndexOfScalar(u8, full_name, '.')) |idx| full_name[0..idx] else return false;
    if (declared.len == scope.len + 1 + actual.len and
        std.mem.eql(u8, declared[0..scope.len], scope) and
        declared[scope.len] == '.' and
        std.mem.eql(u8, declared[scope.len + 1 ..], actual)) return true;
    return package.len != 0 and declared.len == package.len + 1 + scope.len + 1 + actual.len and
        std.mem.eql(u8, declared[0..package.len], package) and
        declared[package.len] == '.' and
        std.mem.eql(u8, declared[package.len + 1 ..][0..scope.len], scope) and
        declared[package.len + 1 + scope.len] == '.' and
        std.mem.eql(u8, declared[package.len + 1 + scope.len + 1 ..], actual);
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
            try appendFileDescriptor(allocator, &files, try decodeFileDescriptorProto(allocator, try reader.readBytes()));
        } else try reader.skipValue(tag);
    }
    try validateDecodedFileDescriptorSetReferences(allocator, files.items);
    return try files.toOwnedSlice(allocator);
}

fn validateDecodedFileDescriptorSetReferences(allocator: std.mem.Allocator, files: []schema.FileDescriptor) Error!void {
    try markMissingWeakImports(allocator, files);
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    // FileDescriptorSet loses source-retention visibility features; protoc's
    // descriptor pool does not enforce symbol visibility for descriptor-only
    // inputs, so neither does pbz.
    registry.enforce_symbol_visibility = false;
    for (files) |*file| try registry.files.append(allocator, file);
    try registry.validateLoadedFiles();
    for (files) |*file| {
        for (file.extensions.items) |*field| try validateDecodedSetFieldEnumDefault(&registry, file, field, if (file.package.len == 0) null else file.package);
        for (file.messages.items) |*message| {
            const scope = try descriptorMessageScopeName(allocator, file, message.name);
            defer allocator.free(scope);
            try validateDecodedSetMessageEnumDefaults(allocator, &registry, file, message, scope);
        }
    }
}

fn markMissingWeakImports(allocator: std.mem.Allocator, files: []schema.FileDescriptor) std.mem.Allocator.Error!void {
    for (files) |*file| {
        for (file.imports.items) |import| {
            if (import.kind != .weak) continue;
            if (decodedSetContainsFile(files, import.path)) continue;
            try file.missing_weak_imports.append(allocator, import.path);
        }
    }
}

fn decodedSetContainsFile(files: []const schema.FileDescriptor, path: []const u8) bool {
    for (files) |*file| {
        if (std.mem.eql(u8, file.name, path)) return true;
    }
    return false;
}

fn validateDecodedSetMessageEnumDefaults(allocator: std.mem.Allocator, registry: *const registry_mod.Registry, file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor, scope: []const u8) Error!void {
    for (message.fields.items) |*field| try validateDecodedSetFieldEnumDefault(registry, file, field, scope);
    for (message.extensions.items) |*field| try validateDecodedSetFieldEnumDefault(registry, file, field, scope);
    for (message.messages.items) |*nested| {
        const full_scope = try joinScope(allocator, scope, nested.name);
        defer allocator.free(full_scope);
        try validateDecodedSetMessageEnumDefaults(allocator, registry, file, nested, full_scope);
    }
}

fn validateDecodedSetFieldEnumDefault(registry: *const registry_mod.Registry, file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, scope: ?[]const u8) Error!void {
    const value = field.default_value orelse return;
    const enum_name = switch (field.kind) {
        .enumeration => |name| name,
        else => return,
    };
    const enumeration = registry.findEnumVisible(file, enum_name, scope) orelse return;
    if (!decodedEnumDefaultMatches(enumeration, value)) return error.InvalidFieldType;
}

fn decodedEnumDefaultMatches(enumeration: *const schema.EnumDescriptor, value: schema.OptionValue) bool {
    return switch (value) {
        .integer => |number| number >= std.math.minInt(i32) and number <= std.math.maxInt(i32) and decodedEnumHasNumber(enumeration, @intCast(number)),
        .unsigned_integer => |number| number <= std.math.maxInt(i32) and decodedEnumHasNumber(enumeration, @intCast(number)),
        .identifier, .string => |name| enumeration.findValue(name) != null,
        else => false,
    };
}

fn decodedEnumHasNumber(enumeration: *const schema.EnumDescriptor, number: i32) bool {
    for (enumeration.values.items) |value| {
        if (value.number == number) return true;
    }
    return false;
}

fn descriptorMessageScopeName(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, name: []const u8) std.mem.Allocator.Error![]const u8 {
    if (file.package.len == 0) return try allocator.dupe(u8, name);
    return try std.fmt.allocPrint(allocator, "{s}.{s}", .{ file.package, name });
}

pub fn decodeFeatureSetDefaults(allocator: std.mem.Allocator, bytes: []const u8) Error!schema.FeatureSetDefaults {
    var defaults = schema.FeatureSetDefaults{};
    errdefer defaults.deinit(allocator);
    var reader = wire.Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            1 => try defaults.defaults.append(allocator, try decodeFeatureSetEditionDefault(try reader.readBytes())),
            4 => defaults.minimum_edition = std.enums.fromInt(schema.Edition, try reader.readInt32()) orelse return error.InvalidFieldType,
            5 => defaults.maximum_edition = std.enums.fromInt(schema.Edition, try reader.readInt32()) orelse return error.InvalidFieldType,
            else => try reader.skipValue(tag),
        }
    }
    try validateFeatureSetDefaults(&defaults);
    return defaults;
}

fn decodeFeatureSetEditionDefault(bytes: []const u8) Error!schema.FeatureSetEditionDefault {
    var entry = schema.FeatureSetEditionDefault{};
    var reader = wire.Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            3 => entry.edition = std.enums.fromInt(schema.Edition, try reader.readInt32()) orelse return error.InvalidFieldType,
            4 => entry.overridable_features = try decodeFeatureSet(try reader.readBytes()),
            5 => entry.fixed_features = try decodeFeatureSet(try reader.readBytes()),
            else => try reader.skipValue(tag),
        }
    }
    if (entry.edition == .unknown) return error.InvalidFieldType;
    return entry;
}

fn validateFeatureSetDefaults(defaults: *const schema.FeatureSetDefaults) Error!void {
    var previous: ?schema.Edition = null;
    for (defaults.defaults.items) |entry| {
        if (entry.edition == .unknown) return error.InvalidFieldType;
        if (previous) |prev| {
            if (@intFromEnum(entry.edition) <= @intFromEnum(prev)) return error.InvalidFieldType;
        }
        previous = entry.edition;
    }
    if (defaults.minimum_edition) |minimum| {
        if (minimum == .unknown) return error.InvalidFieldType;
        if (defaults.maximum_edition) |maximum| {
            if (maximum == .unknown) return error.InvalidFieldType;
            if (@intFromEnum(minimum) > @intFromEnum(maximum)) return error.InvalidFieldType;
        }
    } else if (defaults.maximum_edition) |maximum| {
        if (maximum == .unknown) return error.InvalidFieldType;
    }
}

fn decodeMessageDescriptor(allocator: std.mem.Allocator, owned_strings: *std.ArrayList([]u8), bytes: []const u8) Error!schema.MessageDescriptor {
    var message = schema.MessageDescriptor{ .name = "" };
    errdefer message.deinit(allocator);
    var oneof_indexes: std.ArrayList(struct { field_index: usize, oneof_index: usize }) = .empty;
    defer oneof_indexes.deinit(allocator);

    var reader = wire.Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            1 => message.name = try reader.readBytes(),
            2 => {
                var field = try decodeFieldDescriptor(allocator, owned_strings, try reader.readBytes());
                var owns_field = true;
                errdefer if (owns_field) field.deinit(allocator);
                if (field.oneof_name) |idx_text| {
                    const idx = try std.fmt.parseInt(usize, idx_text, 10);
                    field.oneof_name = null;
                    try oneof_indexes.append(allocator, .{ .field_index = message.fields.items.len, .oneof_index = idx });
                }
                owns_field = false;
                try appendFieldDescriptor(allocator, &message.fields, field);
            },
            3 => try appendMessageDescriptor(allocator, &message.messages, try decodeMessageDescriptor(allocator, owned_strings, try reader.readBytes())),
            4 => try appendEnumDescriptor(allocator, &message.enums, try decodeEnumDescriptor(allocator, try reader.readBytes())),
            5 => try appendExtensionRange(allocator, &message.extension_ranges, try decodeExtensionRange(allocator, try reader.readBytes())),
            6 => try appendFieldDescriptor(allocator, &message.extensions, try decodeFieldDescriptor(allocator, owned_strings, try reader.readBytes())),
            7 => try decodeMessageOptions(allocator, &message, try reader.readBytes()),
            8 => try appendOneofDescriptor(allocator, &message.oneofs, try decodeOneofDescriptor(allocator, try reader.readBytes())),
            9 => try message.reserved_ranges.append(allocator, try decodeReservedRange(allocator, try reader.readBytes(), false)),
            10 => try message.reserved_names.append(allocator, try reader.readBytes()),
            11 => message.visibility = try decodeSymbolVisibility(try reader.readInt32()),
            else => try reader.skipValue(tag),
        }
    }

    try validateDecodedMessageDescriptor(&message);
    for (oneof_indexes.items) |item| {
        if (item.oneof_index >= message.oneofs.items.len) return error.InvalidFieldType;
        message.fields.items[item.field_index].oneof_name = message.oneofs.items[item.oneof_index].name;
    }
    try validateDecodedOneofFieldContiguity(&message);
    for (message.fields.items) |field| try validateDecodedOneofFieldShape(&field);
    try validateDecodedProto3OptionalFields(&message);
    return message;
}

fn validateDecodedOneofFieldContiguity(message: *const schema.MessageDescriptor) Error!void {
    for (message.oneofs.items) |oneof| {
        var first: ?usize = null;
        var last: ?usize = null;
        for (message.fields.items, 0..) |field, index| {
            if (field.oneof_name) |name| {
                if (std.mem.eql(u8, name, oneof.name)) {
                    if (first == null) first = index;
                    last = index;
                }
            }
        }
        const start = first orelse continue;
        const end = last orelse continue;
        for (message.fields.items[start .. end + 1]) |field| {
            const field_oneof = field.oneof_name orelse return error.InvalidFieldType;
            if (!std.mem.eql(u8, field_oneof, oneof.name)) return error.InvalidFieldType;
        }
    }
}

fn validateDecodedProto3OptionalFields(message: *const schema.MessageDescriptor) Error!void {
    var saw_synthetic = false;
    for (message.oneofs.items) |oneof| {
        var field_count: usize = 0;
        var oneof_is_synthetic = false;
        for (message.fields.items) |field| {
            if (field.oneof_name) |field_oneof| {
                if (!std.mem.eql(u8, field_oneof, oneof.name)) continue;
                field_count += 1;
                oneof_is_synthetic = field.proto3_optional;
            }
        }
        if (field_count == 0) return error.InvalidFieldType;
        oneof_is_synthetic = field_count == 1 and oneof_is_synthetic;
        if (oneof_is_synthetic) {
            saw_synthetic = true;
        } else if (saw_synthetic) {
            return error.InvalidFieldType;
        }
    }
    for (message.fields.items) |field| {
        if (!field.proto3_optional) continue;
        const oneof_name = field.oneof_name orelse return error.InvalidFieldType;
        if (field.cardinality != .optional or field.kind == .map or field.kind == .group) return error.InvalidFieldType;
        var count: usize = 0;
        for (message.fields.items) |candidate| {
            if (candidate.oneof_name) |candidate_oneof| {
                if (std.mem.eql(u8, candidate_oneof, oneof_name)) count += 1;
            }
        }
        if (count != 1) return error.InvalidFieldType;
    }
}

fn validateDecodedMessageDescriptor(message: *const schema.MessageDescriptor) Error!void {
    if (!isIdentifier(message.name)) return error.InvalidFieldType;
    const message_range_max = message.extensionRangeMaxExclusive();
    for (message.fields.items, 0..) |field, i| {
        if (!isIdentifier(field.name) or field.number == 0) return error.InvalidFieldType;
        try validateDecodedFieldJsonName(&field, false);
        for (message.fields.items[i + 1 ..]) |other| {
            if (field.number == other.number or std.mem.eql(u8, field.name, other.name)) return error.InvalidFieldType;
        }
        for (message.reserved_ranges.items) |range| {
            if (range.containsWithMax(field.number, message_range_max)) return error.InvalidFieldType;
        }
        for (message.extension_ranges.items) |range| {
            if (range.containsInMessage(message, field.number)) return error.InvalidFieldType;
        }
        for (message.reserved_names.items) |name| {
            if (std.mem.eql(u8, name, field.name)) return error.InvalidFieldType;
        }
    }
    for (message.oneofs.items, 0..) |oneof, i| {
        if (!isIdentifier(oneof.name)) return error.InvalidFieldType;
        for (message.oneofs.items[i + 1 ..]) |other| {
            if (std.mem.eql(u8, oneof.name, other.name)) return error.InvalidFieldType;
        }
        for (message.fields.items) |field| {
            if (std.mem.eql(u8, oneof.name, field.name)) return error.InvalidFieldType;
        }
    }
    for (message.messages.items, 0..) |nested, i| {
        for (message.messages.items[i + 1 ..]) |other| {
            if (std.mem.eql(u8, nested.name, other.name)) return error.InvalidFieldType;
        }
        for (message.enums.items) |enumeration| {
            if (std.mem.eql(u8, nested.name, enumeration.name)) return error.InvalidFieldType;
        }
        for (message.fields.items) |field| {
            if (std.mem.eql(u8, nested.name, field.name)) return error.InvalidFieldType;
        }
        for (message.oneofs.items) |oneof| {
            if (std.mem.eql(u8, nested.name, oneof.name)) return error.InvalidFieldType;
        }
    }
    for (message.enums.items, 0..) |enumeration, i| {
        for (message.enums.items[i + 1 ..]) |other| {
            if (std.mem.eql(u8, enumeration.name, other.name)) return error.InvalidFieldType;
        }
        for (message.fields.items) |field| {
            if (std.mem.eql(u8, enumeration.name, field.name)) return error.InvalidFieldType;
        }
        for (message.oneofs.items) |oneof| {
            if (std.mem.eql(u8, enumeration.name, oneof.name)) return error.InvalidFieldType;
        }
    }
    for (message.extensions.items, 0..) |extension, i| {
        if (!isIdentifier(extension.name)) return error.InvalidFieldType;
        for (message.fields.items) |field| {
            if (std.mem.eql(u8, extension.name, field.name)) return error.InvalidFieldType;
        }
        for (message.oneofs.items) |oneof| {
            if (std.mem.eql(u8, extension.name, oneof.name)) return error.InvalidFieldType;
        }
        for (message.messages.items) |nested| {
            if (std.mem.eql(u8, extension.name, nested.name)) return error.InvalidFieldType;
        }
        for (message.enums.items) |enumeration| {
            if (std.mem.eql(u8, extension.name, enumeration.name)) return error.InvalidFieldType;
        }
        for (message.extensions.items[i + 1 ..]) |other| {
            if (std.mem.eql(u8, extension.name, other.name)) return error.InvalidFieldType;
        }
    }
    try validateDecodedMessageEnumValueSymbols(message);
    try validateDecodedFieldJsonNameUniqueness(message.fields.items);
    for (message.extensions.items) |field| try validateDecodedExtensionFieldDescriptor(&field);
    try validateDecodedExtensionRanges(message, message.extension_ranges.items, message.reserved_ranges.items);
    try validateDecodedExtensionDeclarationNames(message.extension_ranges.items);
    try validateDecodedReservedRanges(message.reserved_ranges.items, message.reserved_names.items, false, message.extensionRangeMaxExclusive());
}

fn validateDecodedMessageEnumValueSymbols(message: *const schema.MessageDescriptor) Error!void {
    for (message.enums.items, 0..) |*enumeration, enum_index| {
        for (enumeration.values.items) |value| {
            for (message.fields.items) |field| {
                if (std.mem.eql(u8, value.name, field.name)) return error.InvalidFieldType;
            }
            for (message.oneofs.items) |oneof| {
                if (std.mem.eql(u8, value.name, oneof.name)) return error.InvalidFieldType;
            }
            for (message.messages.items) |nested| {
                if (std.mem.eql(u8, value.name, nested.name)) return error.InvalidFieldType;
            }
            for (message.enums.items) |other_enum| {
                if (std.mem.eql(u8, value.name, other_enum.name)) return error.InvalidFieldType;
            }
            for (message.extensions.items) |extension| {
                if (std.mem.eql(u8, value.name, extension.name)) return error.InvalidFieldType;
            }
            for (message.enums.items[enum_index + 1 ..]) |other_enum| {
                for (other_enum.values.items) |other_value| {
                    if (std.mem.eql(u8, value.name, other_value.name)) return error.InvalidFieldType;
                }
            }
        }
    }
}

fn validateDecodedOneofFieldShape(field: *const schema.FieldDescriptor) Error!void {
    if (field.oneof_name == null) return;
    if (field.extendee != null) return error.InvalidFieldType;
    if (field.cardinality != .optional) return error.InvalidFieldType;
    if (field.kind == .map or field.kind == .group) return error.InvalidFieldType;
}

fn validateDecodedFieldJsonName(field: *const schema.FieldDescriptor, is_extension: bool) Error!void {
    const json_name = field.json_name orelse return;
    if (std.mem.indexOfScalar(u8, json_name, 0) != null) return error.InvalidFieldType;
    const is_custom = !schema.eqlDefaultJsonName(field.name, json_name);
    if (is_extension and is_custom) return error.InvalidFieldType;
    if (is_custom and schema.jsonNameLooksLikeExtension(json_name)) return error.InvalidFieldType;
}

fn validateDecodedFieldJsonNameUniqueness(fields: []const schema.FieldDescriptor) Error!void {
    for (fields, 0..) |field, i| {
        for (fields[i + 1 ..]) |other| {
            if (schema.defaultJsonNamesEqual(field.name, other.name)) return error.InvalidFieldType;
        }
    }
    for (fields, 0..) |field, i| {
        for (fields[i + 1 ..]) |other| {
            if (effectiveJsonNamesEqual(&field, &other)) return error.InvalidFieldType;
        }
    }
}

fn effectiveJsonNamesEqual(a: *const schema.FieldDescriptor, b: *const schema.FieldDescriptor) bool {
    const a_custom = customJsonName(a);
    const b_custom = customJsonName(b);
    if (a_custom) |a_json| {
        if (b_custom) |b_json| return std.mem.eql(u8, a_json, b_json);
        return schema.eqlDefaultJsonName(b.name, a_json);
    }
    if (b_custom) |b_json| return schema.eqlDefaultJsonName(a.name, b_json);
    return schema.defaultJsonNamesEqual(a.name, b.name);
}

fn customJsonName(field: *const schema.FieldDescriptor) ?[]const u8 {
    const json_name = field.json_name orelse return null;
    return if (schema.eqlDefaultJsonName(field.name, json_name)) null else json_name;
}

fn validateDecodedExtensionRanges(message: *const schema.MessageDescriptor, extension_ranges: []const schema.ExtensionRange, reserved_ranges: []const schema.ReservedRange) Error!void {
    const max_end = message.extensionRangeMaxExclusive();
    for (extension_ranges, 0..) |range, i| {
        try validateDecodedExtensionRangeBounds(message, range);
        const as_reserved = schema.ReservedRange{ .start = range.start, .end = range.end };
        for (extension_ranges[i + 1 ..]) |other| {
            try validateDecodedExtensionRangeBounds(message, other);
            if (range.overlapsInMessage(message, other)) return error.InvalidFieldType;
        }
        for (reserved_ranges) |reserved| {
            if (as_reserved.overlapsWithMax(reserved, max_end)) return error.InvalidFieldType;
        }
    }
}

fn validateDecodedExtensionRangeBounds(message: *const schema.MessageDescriptor, range: schema.ExtensionRange) Error!void {
    const max_end = message.extensionRangeMaxExclusive();
    const end = range.effectiveEnd(message);
    if (range.start <= 0 or range.start >= max_end) return error.InvalidFieldType;
    if (range.end != null and end > max_end) return error.InvalidFieldType;
    if (end <= range.start) return error.InvalidFieldType;
}

fn decodeFieldDescriptor(allocator: std.mem.Allocator, owned_strings: *std.ArrayList([]u8), bytes: []const u8) Error!schema.FieldDescriptor {
    var name: []const u8 = "";
    var number: wire.FieldNumber = 0;
    var cardinality: schema.Cardinality = .optional;
    var field_type: i32 = 0;
    var type_name: ?[]const u8 = null;
    var extendee: ?[]const u8 = null;
    var default_value_text: ?[]const u8 = null;
    var oneof_index_text: ?[]const u8 = null;
    var json_name: ?[]const u8 = null;
    var proto3_optional = false;
    var packed_override: ?bool = null;
    var field_options: schema.OptionList = .empty;
    var edition_defaults: std.ArrayList(schema.FieldEditionDefault) = .empty;
    var features: ?schema.FeatureSet = null;
    var feature_support: ?schema.FeatureSupport = null;
    var unknown_options: std.ArrayList([]const u8) = .empty;
    errdefer field_options.deinit(allocator);
    errdefer edition_defaults.deinit(allocator);
    errdefer unknown_options.deinit(allocator);

    var reader = wire.Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            1 => name = try reader.readBytes(),
            2 => extendee = try reader.readBytes(),
            3 => number = try fieldNumberFromDescriptor(try reader.readInt32()),
            4 => cardinality = try labelFromNumber(try reader.readInt32()),
            5 => field_type = try reader.readInt32(),
            6 => type_name = try reader.readBytes(),
            7 => default_value_text = try reader.readBytes(),
            8 => {
                var decoded_options = try decodeFieldOptions(allocator, try reader.readBytes());
                errdefer decoded_options.deinit(allocator);
                if (field_options.items.len != 0) field_options.deinit(allocator);
                if (edition_defaults.items.len != 0) edition_defaults.deinit(allocator);
                packed_override = decoded_options.packed_override;
                field_options = decoded_options.options;
                edition_defaults = decoded_options.edition_defaults;
                features = decoded_options.features;
                feature_support = decoded_options.feature_support;
                if (unknown_options.items.len != 0) unknown_options.deinit(allocator);
                unknown_options = decoded_options.unknown_options;
                decoded_options.options = .empty;
                decoded_options.edition_defaults = .empty;
                decoded_options.unknown_options = .empty;
            },
            9 => oneof_index_text = try decodeOneofIndexText(allocator, owned_strings, try reader.readInt32()),
            10 => json_name = try reader.readBytes(),
            17 => proto3_optional = try reader.readBool(),
            else => try reader.skipValue(tag),
        }
    }
    if (extendee) |extendee_name| {
        if (!isTypeNameReference(extendee_name)) return error.InvalidFieldType;
    }

    const kind = try kindFromType(allocator, field_type, type_name);
    if (default_value_text != null and cardinality == .repeated) return error.InvalidFieldType;
    const field = schema.FieldDescriptor{
        .name = name,
        .number = number,
        .cardinality = cardinality,
        .kind = kind,
        .extendee = extendee,
        .default_value = if (default_value_text) |text| try decodeDefaultValue(allocator, owned_strings, kind, text) else null,
        .default_value_text = default_value_text,
        .oneof_name = oneof_index_text,
        .json_name = json_name,
        .proto3_optional = proto3_optional,
        .packed_override = packed_override,
        .edition_defaults = edition_defaults,
        .features = features,
        .feature_support = feature_support,
        .options = field_options,
        .unknown_options = unknown_options,
    };
    if (!isIdentifier(field.name) or field.number == 0) return error.InvalidFieldType;
    field_options = .empty;
    edition_defaults = .empty;
    unknown_options = .empty;
    return field;
}

fn fieldNumberFromDescriptor(value: i32) wire.Error!wire.FieldNumber {
    if (value <= 0 or value > std.math.maxInt(wire.FieldNumber)) return error.InvalidFieldNumber;
    if (value >= 19000 and value <= 19999) return error.InvalidFieldNumber;
    return @intCast(value);
}

fn decodedQualifiedName(allocator: std.mem.Allocator, owned_strings: *std.ArrayList([]u8), scope: []const u8, name: []const u8) std.mem.Allocator.Error![]const u8 {
    if (scope.len == 0 or std.mem.startsWith(u8, name, ".") or std.mem.indexOfScalar(u8, name, '.') != null) return name;
    const full_name = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ scope, name });
    errdefer allocator.free(full_name);
    try owned_strings.append(allocator, full_name);
    return full_name;
}

fn decodeDefaultValue(allocator: std.mem.Allocator, owned_strings: *std.ArrayList([]u8), kind: schema.FieldKind, text: []const u8) Error!schema.OptionValue {
    return switch (kind) {
        .scalar => |scalar| switch (scalar) {
            .double => .{ .float = try parseFloatDefault(f64, text) },
            .float => .{ .float = try parseFloatDefault(f32, text) },
            .int32, .sint32, .sfixed32 => .{ .integer = try parseSignedIntegerDefault(i32, text) },
            .int64, .sint64, .sfixed64 => .{ .integer = try parseSignedIntegerDefault(i64, text) },
            .uint32, .fixed32 => .{ .integer = try parseUnsignedIntegerDefault(u32, text) },
            .uint64, .fixed64 => unsignedDefaultOption(try parseIntegerDefault(u64, text)),
            .bool => .{ .boolean = try parseBoolDefault(text) },
            .string => .{ .string = text },
            .bytes => blk: {
                const decoded = try decodeBytesDefaultAlloc(allocator, text);
                errdefer allocator.free(decoded);
                try owned_strings.append(allocator, decoded);
                break :blk .{ .string = decoded };
            },
        },
        .enumeration => blk: {
            if (!isIdentifier(text)) return error.InvalidFieldType;
            break :blk .{ .identifier = text };
        },
        .message, .group, .map => error.InvalidFieldType,
    };
}

fn parseSignedIntegerDefault(comptime T: type, text: []const u8) Error!i64 {
    const value = parseIntegerDefault(T, text) catch return error.InvalidFieldType;
    return @intCast(value);
}

fn parseUnsignedIntegerDefault(comptime T: type, text: []const u8) Error!i64 {
    const value = parseIntegerDefault(T, text) catch return error.InvalidFieldType;
    if (value > std.math.maxInt(i64)) return error.InvalidFieldType;
    return @intCast(value);
}

fn unsignedDefaultOption(value: u64) schema.OptionValue {
    if (value <= std.math.maxInt(i64)) return .{ .integer = @intCast(value) };
    return .{ .unsigned_integer = value };
}

fn parseIntegerDefault(comptime T: type, text: []const u8) !T {
    if (text.len == 0) return error.InvalidCharacter;
    var body = text;
    if (body[0] == '+' or body[0] == '-') {
        body = body[1..];
        if (body.len == 0) return error.InvalidCharacter;
    }
    if (body.len > 1 and body[0] == '0') {
        switch (body[1]) {
            'x', 'X', 'o', 'O', 'b', 'B' => return std.fmt.parseInt(T, text, 0),
            else => return std.fmt.parseInt(T, text, 8),
        }
    }
    return std.fmt.parseInt(T, text, 0);
}

fn parseFloatDefault(comptime T: type, text: []const u8) Error!f64 {
    if (parseSpecialFloatDefault(text)) |value| return value;
    const value = std.fmt.parseFloat(T, text) catch return error.InvalidFieldType;
    return @floatCast(value);
}

fn parseSpecialFloatDefault(text: []const u8) ?f64 {
    var body = text;
    var negative = false;
    if (body.len != 0 and (body[0] == '-' or body[0] == '+')) {
        negative = body[0] == '-';
        body = body[1..];
    }
    if (std.ascii.eqlIgnoreCase(body, "inf") or std.ascii.eqlIgnoreCase(body, "infinity")) {
        const value = std.math.inf(f64);
        return if (negative) -value else value;
    }
    if (std.ascii.eqlIgnoreCase(body, "nan")) return std.math.nan(f64);
    return null;
}

fn parseBoolDefault(text: []const u8) Error!bool {
    if (std.mem.eql(u8, text, "true")) return true;
    if (std.mem.eql(u8, text, "false")) return false;
    return error.InvalidFieldType;
}

fn escapeBytesDefaultAlloc(allocator: std.mem.Allocator, bytes: []const u8) std.mem.Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    for (bytes) |byte| {
        switch (byte) {
            0x07 => try out.appendSlice(allocator, "\\a"),
            0x08 => try out.appendSlice(allocator, "\\b"),
            0x0c => try out.appendSlice(allocator, "\\f"),
            '\n' => try out.appendSlice(allocator, "\\n"),
            '\r' => try out.appendSlice(allocator, "\\r"),
            '\t' => try out.appendSlice(allocator, "\\t"),
            0x0b => try out.appendSlice(allocator, "\\v"),
            '\\' => try out.appendSlice(allocator, "\\\\"),
            '\'' => try out.appendSlice(allocator, "\\'"),
            '"' => try out.appendSlice(allocator, "\\\""),
            '?' => try out.appendSlice(allocator, "\\?"),
            0x20...0x21, 0x23...0x26, 0x28...0x3e, 0x40...0x5b, 0x5d...0x7e => try out.append(allocator, byte),
            else => try appendOctalEscape(allocator, &out, byte),
        }
    }
    return try out.toOwnedSlice(allocator);
}

fn appendOctalEscape(allocator: std.mem.Allocator, out: *std.ArrayList(u8), byte: u8) std.mem.Allocator.Error!void {
    try out.append(allocator, '\\');
    try out.append(allocator, '0' + @as(u8, @intCast((byte >> 6) & 0x7)));
    try out.append(allocator, '0' + @as(u8, @intCast((byte >> 3) & 0x7)));
    try out.append(allocator, '0' + @as(u8, @intCast(byte & 0x7)));
}

fn decodeBytesDefaultAlloc(allocator: std.mem.Allocator, text: []const u8) Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    var i: usize = 0;
    while (i < text.len) {
        const c = text[i];
        if (c != '\\') {
            try out.append(allocator, c);
            i += 1;
            continue;
        }
        i += 1;
        if (i >= text.len) return error.InvalidFieldType;
        const esc = text[i];
        i += 1;
        switch (esc) {
            'a' => try out.append(allocator, 0x07),
            'b' => try out.append(allocator, 0x08),
            'f' => try out.append(allocator, 0x0c),
            'n' => try out.append(allocator, '\n'),
            'r' => try out.append(allocator, '\r'),
            't' => try out.append(allocator, '\t'),
            'v' => try out.append(allocator, 0x0b),
            '\\' => try out.append(allocator, '\\'),
            '\'' => try out.append(allocator, '\''),
            '"' => try out.append(allocator, '"'),
            '?' => try out.append(allocator, '?'),
            'x', 'X' => {
                var value: u8 = 0;
                var digits: usize = 0;
                while (i < text.len and digits < 2) : (digits += 1) {
                    const digit = hexValue(text[i]) orelse break;
                    value = value * 16 + digit;
                    i += 1;
                }
                if (digits == 0) return error.InvalidFieldType;
                try out.append(allocator, value);
            },
            '0'...'7' => {
                var value: u16 = esc - '0';
                var digits: usize = 1;
                while (i < text.len and digits < 3 and text[i] >= '0' and text[i] <= '7') : (digits += 1) {
                    value = value * 8 + (text[i] - '0');
                    i += 1;
                }
                if (value > std.math.maxInt(u8)) return error.InvalidFieldType;
                try out.append(allocator, @intCast(value));
            },
            else => return error.InvalidFieldType,
        }
    }
    return try out.toOwnedSlice(allocator);
}

fn hexValue(c: u8) ?u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => null,
    };
}

fn resolveDecodedEnumDefaults(file: *schema.FileDescriptor) void {
    for (file.messages.items) |*message| resolveMessageEnumDefaults(file, message);
    for (file.extensions.items) |*field| resolveFieldEnumDefault(file, field);
}

fn resolveMessageEnumDefaults(file: *schema.FileDescriptor, message: *schema.MessageDescriptor) void {
    for (message.fields.items) |*field| resolveFieldEnumDefault(file, field);
    for (message.extensions.items) |*field| resolveFieldEnumDefault(file, field);
    for (message.messages.items) |*nested| resolveMessageEnumDefaults(file, nested);
}

fn resolveFieldEnumDefault(file: *schema.FileDescriptor, field: *schema.FieldDescriptor) void {
    const enum_name = switch (field.kind) {
        .enumeration => |name| name,
        else => return,
    };
    const default_name = switch (field.default_value orelse return) {
        .identifier, .string => |text| text,
        else => return,
    };
    const enumeration = file.findEnumDeep(enum_name) orelse return;
    if (enumeration.findValue(default_name)) |value| field.default_value = .{ .integer = value.number };
}

fn decodeEnumDescriptor(allocator: std.mem.Allocator, bytes: []const u8) Error!schema.EnumDescriptor {
    var enumeration = schema.EnumDescriptor{ .name = "" };
    errdefer enumeration.deinit(allocator);
    var reader = wire.Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            1 => enumeration.name = try reader.readBytes(),
            2 => try appendEnumValueDescriptor(allocator, &enumeration.values, try decodeEnumValueDescriptor(allocator, try reader.readBytes())),
            3 => try decodeEnumOptions(allocator, &enumeration, try reader.readBytes()),
            4 => try enumeration.reserved_ranges.append(allocator, try decodeReservedRange(allocator, try reader.readBytes(), true)),
            5 => try enumeration.reserved_names.append(allocator, try reader.readBytes()),
            6 => enumeration.visibility = try decodeSymbolVisibility(try reader.readInt32()),
            else => try reader.skipValue(tag),
        }
    }
    try validateEnumDescriptor(allocator, &enumeration);
    return enumeration;
}

fn decodeEnumValueDescriptor(allocator: std.mem.Allocator, bytes: []const u8) Error!schema.EnumValueDescriptor {
    var value = schema.EnumValueDescriptor{ .name = "", .number = 0 };
    errdefer value.deinit(allocator);
    var reader = wire.Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            1 => value.name = try reader.readBytes(),
            2 => value.number = try reader.readInt32(),
            3 => try decodeEnumValueOptions(allocator, &value, try reader.readBytes()),
            else => try reader.skipValue(tag),
        }
    }
    return value;
}

fn decodeEnumOptions(allocator: std.mem.Allocator, enumeration: *schema.EnumDescriptor, bytes: []const u8) Error!void {
    var reader = wire.Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            2 => try enumeration.options.append(allocator, .{ .name = "allow_alias", .value = .{ .boolean = try reader.readBool() } }),
            3 => try enumeration.options.append(allocator, .{ .name = "deprecated", .value = .{ .boolean = try reader.readBool() } }),
            6 => try enumeration.options.append(allocator, .{ .name = "deprecated_legacy_json_field_conflicts", .value = .{ .boolean = try reader.readBool() } }),
            7 => enumeration.features = try decodeFeatureSet(try reader.readBytes()),
            999 => try appendFieldOption(allocator, &enumeration.options, try decodeUninterpretedOption(allocator, try reader.readBytes())),
            else => {
                const raw_start = reader.lastTagStart();
                try reader.skipValue(tag);
                try enumeration.unknown_options.append(allocator, bytes[raw_start..reader.position()]);
            },
        }
    }
}

fn decodeEnumValueOptions(allocator: std.mem.Allocator, value: *schema.EnumValueDescriptor, bytes: []const u8) Error!void {
    var reader = wire.Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            1 => try value.options.append(allocator, .{ .name = "deprecated", .value = .{ .boolean = try reader.readBool() } }),
            2 => value.features = try decodeFeatureSet(try reader.readBytes()),
            3 => try value.options.append(allocator, .{ .name = "debug_redact", .value = .{ .boolean = try reader.readBool() } }),
            4 => value.feature_support = try decodeFeatureSupport(try reader.readBytes()),
            999 => try appendFieldOption(allocator, &value.options, try decodeUninterpretedOption(allocator, try reader.readBytes())),
            else => {
                const raw_start = reader.lastTagStart();
                try reader.skipValue(tag);
                try value.unknown_options.append(allocator, bytes[raw_start..reader.position()]);
            },
        }
    }
}

fn validateEnumDescriptor(allocator: std.mem.Allocator, enumeration: *const schema.EnumDescriptor) Error!void {
    if (!isIdentifier(enumeration.name) or enumeration.values.items.len == 0) return error.InvalidFieldType;
    const alias_state = enumAliasState(enumeration);
    if (alias_state.has_allow_alias and !alias_state.allow_alias) return error.InvalidFieldType;
    var has_duplicate_numbers = false;
    const enum_range_max = std.math.maxInt(i64);
    for (enumeration.values.items, 0..) |value, i| {
        if (!isIdentifier(value.name)) return error.InvalidFieldType;
        for (enumeration.values.items[i + 1 ..]) |other| {
            if (std.mem.eql(u8, value.name, other.name)) return error.InvalidFieldType;
            if (value.number == other.number) {
                has_duplicate_numbers = true;
                if (!alias_state.allow_alias) return error.InvalidFieldType;
            }
        }
        for (enumeration.reserved_ranges.items) |range| {
            if (range.containsWithMax(value.number, enum_range_max)) return error.InvalidFieldType;
        }
        for (enumeration.reserved_names.items) |name| {
            if (std.mem.eql(u8, name, value.name)) return error.InvalidFieldType;
        }
    }
    if (alias_state.allow_alias and !has_duplicate_numbers) return error.InvalidFieldType;
    try validateEnumValueCanonicalNames(allocator, enumeration);
    try validateDecodedReservedRanges(enumeration.reserved_ranges.items, enumeration.reserved_names.items, true, enum_range_max);
}

fn validateEnumValueCanonicalNames(allocator: std.mem.Allocator, enumeration: *const schema.EnumDescriptor) Error!void {
    for (enumeration.values.items, 0..) |value, i| {
        const key = try schema.enumValueCanonicalKey(allocator, enumeration.name, value.name);
        defer allocator.free(key);
        for (enumeration.values.items[i + 1 ..]) |other| {
            const other_key = try schema.enumValueCanonicalKey(allocator, enumeration.name, other.name);
            defer allocator.free(other_key);
            if (std.mem.eql(u8, key, other_key) and !std.mem.eql(u8, value.name, other.name) and value.number != other.number) return error.InvalidFieldType;
        }
    }
}

fn validateDecodedReservedRanges(ranges: []const schema.ReservedRange, names: []const []const u8, is_enum: bool, max_end: i64) Error!void {
    for (ranges, 0..) |range, i| {
        const end = range.effectiveEnd(max_end);
        if (!is_enum) {
            if (range.start <= 0 or range.start >= max_end) return error.InvalidFieldType;
            if (range.end != null and end > max_end) return error.InvalidFieldType;
        }
        if (end <= range.start) return error.InvalidFieldType;
        for (ranges[i + 1 ..]) |other| {
            const other_end = other.effectiveEnd(max_end);
            if (!is_enum) {
                if (other.start <= 0 or other.start >= max_end) return error.InvalidFieldType;
                if (other.end != null and other_end > max_end) return error.InvalidFieldType;
            }
            if (range.overlapsWithMax(other, max_end)) return error.InvalidFieldType;
        }
    }
    for (names, 0..) |name, i| {
        if (name.len == 0) return error.InvalidFieldType;
        for (names[i + 1 ..]) |other| {
            if (std.mem.eql(u8, name, other)) return error.InvalidFieldType;
        }
    }
}

fn decodeOneofDescriptor(allocator: std.mem.Allocator, bytes: []const u8) Error!schema.OneofDescriptor {
    var oneof = schema.OneofDescriptor{ .name = "" };
    errdefer oneof.deinit(allocator);
    var reader = wire.Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            1 => oneof.name = try reader.readBytes(),
            2 => try decodeOneofOptions(allocator, &oneof, try reader.readBytes()),
            else => try reader.skipValue(tag),
        }
    }
    if (!isIdentifier(oneof.name)) return error.InvalidFieldType;
    return oneof;
}

fn decodeExtensionRange(allocator: std.mem.Allocator, bytes: []const u8) Error!schema.ExtensionRange {
    var range = schema.ExtensionRange{ .start = 0, .end = null };
    errdefer range.deinit(allocator);
    var reader = wire.Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            1 => range.start = try reader.readInt32(),
            2 => range.end = try reader.readInt32(),
            3 => try decodeExtensionRangeOptions(allocator, &range, try reader.readBytes()),
            else => try reader.skipValue(tag),
        }
    }
    try validateDecodedExtensionRange(&range);
    return range;
}

fn validateDecodedExtensionRange(range: *const schema.ExtensionRange) Error!void {
    if (range.start <= 0) return error.InvalidFieldType;
    if (range.declarations.items.len != 0 and range.verification == .unverified) return error.InvalidFieldType;
    const end = range.effectiveEndWithMax(std.math.maxInt(i64));
    if (end <= range.start) return error.InvalidFieldType;
    for (range.declarations.items, 0..) |declaration, index| {
        if (declaration.number <= 0) return error.InvalidFieldType;
        if (declaration.number < range.start or declaration.number >= end) return error.InvalidFieldType;
        try validateDecodedExtensionDeclarationShape(declaration);
        for (range.declarations.items[index + 1 ..]) |other| {
            if (declaration.number == other.number) return error.InvalidFieldType;
            if (declaration.full_name.len != 0 and other.full_name.len != 0 and std.mem.eql(u8, declaration.full_name, other.full_name)) return error.InvalidFieldType;
        }
    }
}

fn validateDecodedExtensionDeclarationShape(declaration: schema.ExtensionDeclaration) Error!void {
    const has_full_name = declaration.full_name.len != 0;
    const has_type = declaration.type_name.len != 0;
    if (!has_full_name or !has_type) {
        if (has_full_name != has_type or !declaration.reserved) return error.InvalidFieldType;
        return;
    }
    if (!schema.declarationSymbolIsQualified(declaration.full_name)) return error.InvalidFieldType;
    if (!isExtensionDeclarationTypeName(declaration.type_name)) return error.InvalidFieldType;
}

fn validateDecodedExtensionDeclarationNames(extension_ranges: []const schema.ExtensionRange) Error!void {
    for (extension_ranges, 0..) |range, range_index| {
        for (range.declarations.items) |declaration| {
            if (declaration.full_name.len == 0) continue;
            for (extension_ranges[range_index + 1 ..]) |other_range| {
                for (other_range.declarations.items) |other| {
                    if (std.mem.eql(u8, declaration.full_name, other.full_name)) return error.InvalidFieldType;
                }
            }
        }
    }
}

fn decodeExtensionRangeOptions(allocator: std.mem.Allocator, range: *schema.ExtensionRange, bytes: []const u8) Error!void {
    var reader = wire.Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            2 => try range.declarations.append(allocator, try decodeExtensionDeclaration(try reader.readBytes())),
            3 => range.verification = std.enums.fromInt(schema.ExtensionRangeVerification, try reader.readInt32()) orelse return error.InvalidFieldType,
            50 => range.features = try decodeFeatureSet(try reader.readBytes()),
            999 => try appendFieldOption(allocator, &range.options, try decodeUninterpretedOption(allocator, try reader.readBytes())),
            else => {
                const raw_start = reader.lastTagStart();
                try reader.skipValue(tag);
                try range.unknown_options.append(allocator, bytes[raw_start..reader.position()]);
            },
        }
    }
}

fn decodeExtensionDeclaration(bytes: []const u8) Error!schema.ExtensionDeclaration {
    var declaration = schema.ExtensionDeclaration{};
    var reader = wire.Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            1 => declaration.number = try reader.readInt32(),
            2 => declaration.full_name = try reader.readBytes(),
            3 => declaration.type_name = try reader.readBytes(),
            5 => declaration.reserved = try reader.readBool(),
            6 => declaration.repeated = try reader.readBool(),
            else => try reader.skipValue(tag),
        }
    }
    return declaration;
}

fn decodeSourceCodeInfo(allocator: std.mem.Allocator, bytes: []const u8) Error!schema.SourceCodeInfo {
    var source = schema.SourceCodeInfo{};
    errdefer source.deinit(allocator);
    var reader = wire.Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            1 => try appendSourceCodeInfoLocation(allocator, &source.locations, try decodeSourceCodeInfoLocation(allocator, try reader.readBytes())),
            else => try reader.skipValue(tag),
        }
    }
    return source;
}

fn decodeSourceCodeInfoLocation(allocator: std.mem.Allocator, bytes: []const u8) Error!schema.SourceCodeInfo.Location {
    var location = schema.SourceCodeInfo.Location{};
    errdefer location.deinit(allocator);
    var reader = wire.Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            1 => try decodeInt32ListField(allocator, tag, &reader, &location.path),
            2 => try decodeInt32ListField(allocator, tag, &reader, &location.span),
            3 => location.leading_comments = try reader.readBytes(),
            4 => location.trailing_comments = try reader.readBytes(),
            6 => try location.leading_detached_comments.append(allocator, try reader.readBytes()),
            else => try reader.skipValue(tag),
        }
    }
    if (location.span.items.len != 0 and location.span.items.len != 3 and location.span.items.len != 4) return error.InvalidFieldType;
    for (location.path.items) |part| {
        if (part < 0) return error.InvalidFieldType;
    }
    for (location.span.items) |part| {
        if (part < 0) return error.InvalidFieldType;
    }
    if (location.span.items.len == 4) {
        const start_line = location.span.items[0];
        const start_col = location.span.items[1];
        const end_line = location.span.items[2];
        const end_col = location.span.items[3];
        if (end_line < start_line or (end_line == start_line and end_col < start_col)) return error.InvalidFieldType;
    }
    return location;
}

fn decodeInt32ListField(allocator: std.mem.Allocator, tag: wire.Tag, reader: *wire.Reader, output: *std.ArrayList(i32)) Error!void {
    switch (tag.wire_type) {
        .length_delimited => {
            var packed_reader = wire.Reader.init(try reader.readBytes());
            while (!packed_reader.eof()) try output.append(allocator, try packed_reader.readInt32());
        },
        .varint => try output.append(allocator, try reader.readInt32()),
        else => return error.InvalidWireType,
    }
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
                range.end = if (inclusive_end) @as(i64, end) + 1 else end;
            },
            else => try reader.skipValue(tag),
        }
    }
    if (range.end) |end| {
        if (end <= range.start) return error.InvalidFieldType;
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
            2 => try appendMethodDescriptor(allocator, &service.methods, try decodeMethodDescriptor(allocator, try reader.readBytes())),
            3 => try decodeServiceOptions(allocator, &service, try reader.readBytes()),
            else => try reader.skipValue(tag),
        }
    }
    if (!isIdentifier(service.name)) return error.InvalidFieldType;
    for (service.methods.items, 0..) |method, i| {
        for (service.methods.items[i + 1 ..]) |other| {
            if (std.mem.eql(u8, method.name, other.name)) return error.InvalidFieldType;
        }
    }
    return service;
}

fn decodeMethodDescriptor(allocator: std.mem.Allocator, bytes: []const u8) Error!schema.MethodDescriptor {
    var method = schema.MethodDescriptor{ .name = "", .input_type = "", .output_type = "" };
    errdefer method.deinit(allocator);
    var reader = wire.Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            1 => method.name = try reader.readBytes(),
            2 => method.input_type = try reader.readBytes(),
            3 => method.output_type = try reader.readBytes(),
            4 => try decodeMethodOptions(allocator, &method, try reader.readBytes()),
            5 => method.client_streaming = try reader.readBool(),
            6 => method.server_streaming = try reader.readBool(),
            else => try reader.skipValue(tag),
        }
    }
    if (!isIdentifier(method.name) or !isTypeNameReference(method.input_type) or !isTypeNameReference(method.output_type)) return error.InvalidFieldType;
    return method;
}

fn decodeServiceOptions(allocator: std.mem.Allocator, service: *schema.ServiceDescriptor, bytes: []const u8) Error!void {
    var reader = wire.Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            33 => try service.options.append(allocator, .{ .name = "deprecated", .value = .{ .boolean = try reader.readBool() } }),
            34 => service.features = try decodeFeatureSet(try reader.readBytes()),
            999 => try appendFieldOption(allocator, &service.options, try decodeUninterpretedOption(allocator, try reader.readBytes())),
            else => {
                const raw_start = reader.lastTagStart();
                try reader.skipValue(tag);
                try service.unknown_options.append(allocator, bytes[raw_start..reader.position()]);
            },
        }
    }
}

fn decodeMethodOptions(allocator: std.mem.Allocator, method: *schema.MethodDescriptor, bytes: []const u8) Error!void {
    var reader = wire.Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            33 => try method.options.append(allocator, .{ .name = "deprecated", .value = .{ .boolean = try reader.readBool() } }),
            34 => try method.options.append(allocator, .{ .name = "idempotency_level", .value = .{ .integer = try readKnownEnumNumber(&reader, 0, 2) } }),
            35 => method.features = try decodeFeatureSet(try reader.readBytes()),
            999 => try appendFieldOption(allocator, &method.options, try decodeUninterpretedOption(allocator, try reader.readBytes())),
            else => {
                const raw_start = reader.lastTagStart();
                try reader.skipValue(tag);
                try method.unknown_options.append(allocator, bytes[raw_start..reader.position()]);
            },
        }
    }
}

fn decodeOneofOptions(allocator: std.mem.Allocator, oneof: *schema.OneofDescriptor, bytes: []const u8) Error!void {
    var reader = wire.Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            1 => oneof.features = try decodeFeatureSet(try reader.readBytes()),
            999 => try appendFieldOption(allocator, &oneof.options, try decodeUninterpretedOption(allocator, try reader.readBytes())),
            else => {
                const raw_start = reader.lastTagStart();
                try reader.skipValue(tag);
                try oneof.unknown_options.append(allocator, bytes[raw_start..reader.position()]);
            },
        }
    }
}

fn decodeMessageOptions(allocator: std.mem.Allocator, message: *schema.MessageDescriptor, bytes: []const u8) Error!void {
    var reader = wire.Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            1 => try message.options.append(allocator, .{ .name = "message_set_wire_format", .value = .{ .boolean = try reader.readBool() } }),
            2 => try message.options.append(allocator, .{ .name = "no_standard_descriptor_accessor", .value = .{ .boolean = try reader.readBool() } }),
            3 => try message.options.append(allocator, .{ .name = "deprecated", .value = .{ .boolean = try reader.readBool() } }),
            7 => message.map_entry = try reader.readBool(),
            11 => try message.options.append(allocator, .{ .name = "deprecated_legacy_json_field_conflicts", .value = .{ .boolean = try reader.readBool() } }),
            12 => message.features = try decodeFeatureSet(try reader.readBytes()),
            999 => try appendFieldOption(allocator, &message.options, try decodeUninterpretedOption(allocator, try reader.readBytes())),
            else => {
                const raw_start = reader.lastTagStart();
                try reader.skipValue(tag);
                try message.unknown_options.append(allocator, bytes[raw_start..reader.position()]);
            },
        }
    }
}

fn decodeFileOptions(allocator: std.mem.Allocator, file: *schema.FileDescriptor, bytes: []const u8) Error!?schema.FeatureSet {
    var decoded_features: ?schema.FeatureSet = null;
    var reader = wire.Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            1 => try file.options.append(allocator, .{ .name = "java_package", .value = .{ .string = try reader.readBytes() } }),
            8 => try file.options.append(allocator, .{ .name = "java_outer_classname", .value = .{ .string = try reader.readBytes() } }),
            9 => try file.options.append(allocator, .{ .name = "optimize_for", .value = .{ .integer = try readKnownEnumNumber(&reader, 1, 3) } }),
            10 => try file.options.append(allocator, .{ .name = "java_multiple_files", .value = .{ .boolean = try reader.readBool() } }),
            11 => try file.options.append(allocator, .{ .name = "go_package", .value = .{ .string = try reader.readBytes() } }),
            16 => try file.options.append(allocator, .{ .name = "cc_generic_services", .value = .{ .boolean = try reader.readBool() } }),
            17 => try file.options.append(allocator, .{ .name = "java_generic_services", .value = .{ .boolean = try reader.readBool() } }),
            18 => try file.options.append(allocator, .{ .name = "py_generic_services", .value = .{ .boolean = try reader.readBool() } }),
            20 => try file.options.append(allocator, .{ .name = "java_generate_equals_and_hash", .value = .{ .boolean = try reader.readBool() } }),
            23 => try file.options.append(allocator, .{ .name = "deprecated", .value = .{ .boolean = try reader.readBool() } }),
            27 => try file.options.append(allocator, .{ .name = "java_string_check_utf8", .value = .{ .boolean = try reader.readBool() } }),
            31 => try file.options.append(allocator, .{ .name = "cc_enable_arenas", .value = .{ .boolean = try reader.readBool() } }),
            36 => try file.options.append(allocator, .{ .name = "objc_class_prefix", .value = .{ .string = try reader.readBytes() } }),
            37 => try file.options.append(allocator, .{ .name = "csharp_namespace", .value = .{ .string = try reader.readBytes() } }),
            39 => try file.options.append(allocator, .{ .name = "swift_prefix", .value = .{ .string = try reader.readBytes() } }),
            40 => try file.options.append(allocator, .{ .name = "php_class_prefix", .value = .{ .string = try reader.readBytes() } }),
            41 => try file.options.append(allocator, .{ .name = "php_namespace", .value = .{ .string = try reader.readBytes() } }),
            44 => try file.options.append(allocator, .{ .name = "php_metadata_namespace", .value = .{ .string = try reader.readBytes() } }),
            45 => try file.options.append(allocator, .{ .name = "ruby_package", .value = .{ .string = try reader.readBytes() } }),
            50 => decoded_features = try decodeFeatureSet(try reader.readBytes()),
            999 => try appendFieldOption(allocator, &file.options, try decodeUninterpretedOption(allocator, try reader.readBytes())),
            else => {
                const raw_start = reader.lastTagStart();
                try reader.skipValue(tag);
                try file.unknown_options.append(allocator, bytes[raw_start..reader.position()]);
            },
        }
    }
    return decoded_features;
}

const DecodedFieldOptions = struct {
    packed_override: ?bool = null,
    options: schema.OptionList = .empty,
    edition_defaults: std.ArrayList(schema.FieldEditionDefault) = .empty,
    features: ?schema.FeatureSet = null,
    feature_support: ?schema.FeatureSupport = null,
    unknown_options: std.ArrayList([]const u8) = .empty,

    fn deinit(self: *DecodedFieldOptions, allocator: std.mem.Allocator) void {
        self.options.deinit(allocator);
        self.edition_defaults.deinit(allocator);
        self.unknown_options.deinit(allocator);
    }
};

fn decodeFieldOptions(allocator: std.mem.Allocator, bytes: []const u8) Error!DecodedFieldOptions {
    var result = DecodedFieldOptions{};
    errdefer result.deinit(allocator);
    var reader = wire.Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            1 => try result.options.append(allocator, .{ .name = "ctype", .value = .{ .integer = try readKnownEnumNumber(&reader, 0, 2) } }),
            2 => result.packed_override = try reader.readBool(),
            3 => try result.options.append(allocator, .{ .name = "deprecated", .value = .{ .boolean = try reader.readBool() } }),
            5 => try result.options.append(allocator, .{ .name = "lazy", .value = .{ .boolean = try reader.readBool() } }),
            6 => try result.options.append(allocator, .{ .name = "jstype", .value = .{ .integer = try readKnownEnumNumber(&reader, 0, 2) } }),
            10 => try result.options.append(allocator, .{ .name = "weak", .value = .{ .boolean = try reader.readBool() } }),
            15 => try result.options.append(allocator, .{ .name = "unverified_lazy", .value = .{ .boolean = try reader.readBool() } }),
            16 => try result.options.append(allocator, .{ .name = "debug_redact", .value = .{ .boolean = try reader.readBool() } }),
            17 => try result.options.append(allocator, .{ .name = "retention", .value = .{ .integer = try readKnownEnumNumber(&reader, 0, 2) } }),
            19 => try result.options.append(allocator, .{ .name = "targets", .value = .{ .integer = try readKnownEnumNumber(&reader, 0, 9) } }),
            20 => try result.edition_defaults.append(allocator, try decodeFieldEditionDefault(try reader.readBytes())),
            21 => result.features = try decodeFeatureSet(try reader.readBytes()),
            22 => result.feature_support = try decodeFeatureSupport(try reader.readBytes()),
            999 => try appendFieldOption(allocator, &result.options, try decodeUninterpretedOption(allocator, try reader.readBytes())),
            else => {
                const raw_start = reader.lastTagStart();
                try reader.skipValue(tag);
                try result.unknown_options.append(allocator, bytes[raw_start..reader.position()]);
            },
        }
    }
    return result;
}

fn readKnownEnumNumber(reader: *wire.Reader, min: i32, max: i32) Error!i32 {
    const value = try reader.readInt32();
    if (value < min or value > max) return error.InvalidFieldType;
    return value;
}

fn decodeFieldEditionDefault(bytes: []const u8) Error!schema.FieldEditionDefault {
    var result = schema.FieldEditionDefault{};
    var reader = wire.Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            2 => result.value = try reader.readBytes(),
            3 => result.edition = std.enums.fromInt(schema.Edition, try reader.readInt32()) orelse return error.InvalidFieldType,
            else => try reader.skipValue(tag),
        }
    }
    return result;
}

fn decodeFeatureSupport(bytes: []const u8) Error!schema.FeatureSupport {
    var result = schema.FeatureSupport{};
    var reader = wire.Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            1 => result.edition_introduced = std.enums.fromInt(schema.Edition, try reader.readInt32()) orelse return error.InvalidFieldType,
            2 => result.edition_deprecated = std.enums.fromInt(schema.Edition, try reader.readInt32()) orelse return error.InvalidFieldType,
            3 => result.deprecation_warning = try reader.readBytes(),
            4 => result.edition_removed = std.enums.fromInt(schema.Edition, try reader.readInt32()) orelse return error.InvalidFieldType,
            5 => result.removal_error = try reader.readBytes(),
            else => try reader.skipValue(tag),
        }
    }
    try schema.validateFeatureSupport(result);
    return result;
}

fn decodeUninterpretedOption(allocator: std.mem.Allocator, bytes: []const u8) Error!schema.FieldOption {
    var name_bytes: std.ArrayList(u8) = .empty;
    errdefer name_bytes.deinit(allocator);
    var saw_name = false;
    var value: schema.OptionValue = .{ .identifier = "" };
    var reader = wire.Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            2 => {
                if (saw_name) try name_bytes.append(allocator, '.');
                const part = try decodeUninterpretedNamePart(try reader.readBytes());
                if (part.is_extension and !(std.mem.startsWith(u8, part.name, "(") and std.mem.endsWith(u8, part.name, ")"))) {
                    try name_bytes.append(allocator, '(');
                    try name_bytes.appendSlice(allocator, part.name);
                    try name_bytes.append(allocator, ')');
                } else {
                    try name_bytes.appendSlice(allocator, part.name);
                }
                saw_name = true;
            },
            3 => value = .{ .identifier = try reader.readBytes() },
            4 => {
                const v = try reader.readUInt64();
                value = unsignedDefaultOption(v);
            },
            5 => value = .{ .integer = try reader.readInt64() },
            6 => value = .{ .float = try reader.readDouble() },
            7 => value = .{ .string = try reader.readBytes() },
            8 => value = .{ .aggregate = try reader.readBytes() },
            else => try reader.skipValue(tag),
        }
    }
    const name = try name_bytes.toOwnedSlice(allocator);
    return .{ .name = name, .value = value, .name_owned = true };
}

fn decodeUninterpretedNamePart(bytes: []const u8) Error!struct { name: []const u8, is_extension: bool } {
    var name: []const u8 = "";
    var is_extension = false;
    var reader = wire.Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            1 => name = try reader.readBytes(),
            2 => is_extension = try reader.readBool(),
            else => try reader.skipValue(tag),
        }
    }
    return .{ .name = name, .is_extension = is_extension };
}

fn symbolVisibilityNumber(visibility: schema.SymbolVisibility) i32 {
    return switch (visibility) {
        .default => 0,
        .local => 1,
        .exported => 2,
    };
}

fn decodeSymbolVisibility(value: i32) Error!schema.SymbolVisibility {
    return switch (value) {
        0 => .default,
        1 => .local,
        2 => .exported,
        else => error.InvalidFieldType,
    };
}

fn decodeFeatureSet(bytes: []const u8) Error!schema.FeatureSet {
    var features = schema.FeatureSet{};
    var unknown_start: ?usize = null;
    var unknown_end: usize = 0;
    var unknown_bytes: usize = 0;
    var reader = wire.Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            1 => {
                const value = try reader.readInt32();
                features.field_presence = switch (value) {
                    0 => features.field_presence,
                    1 => .explicit,
                    2 => .implicit,
                    3 => .legacy_required,
                    else => return error.InvalidFieldType,
                };
                if (value != 0) features.markPresent("field_presence");
            },
            2 => {
                const value = try reader.readInt32();
                features.enum_type = switch (value) {
                    0 => features.enum_type,
                    1 => .open,
                    2 => .closed,
                    else => return error.InvalidFieldType,
                };
                if (value != 0) features.markPresent("enum_type");
            },
            3 => {
                const value = try reader.readInt32();
                features.repeated_field_encoding = switch (value) {
                    0 => features.repeated_field_encoding,
                    1 => .packed_encoding,
                    2 => .expanded,
                    else => return error.InvalidFieldType,
                };
                if (value != 0) features.markPresent("repeated_field_encoding");
            },
            4 => {
                const value = try reader.readInt32();
                features.utf8_validation = switch (value) {
                    0 => features.utf8_validation,
                    2 => .verify,
                    3 => .none,
                    else => return error.InvalidFieldType,
                };
                if (value != 0) features.markPresent("utf8_validation");
            },
            5 => {
                const value = try reader.readInt32();
                features.message_encoding = switch (value) {
                    0 => features.message_encoding,
                    1 => .length_prefixed,
                    2 => .delimited,
                    else => return error.InvalidFieldType,
                };
                if (value != 0) features.markPresent("message_encoding");
            },
            6 => {
                const value = try reader.readInt32();
                features.json_format = switch (value) {
                    0 => features.json_format,
                    1 => .allow,
                    2 => .legacy_best_effort,
                    else => return error.InvalidFieldType,
                };
                if (value != 0) features.markPresent("json_format");
            },
            7 => {
                const value = try reader.readInt32();
                features.enforce_naming_style = switch (value) {
                    0 => features.enforce_naming_style,
                    1 => .style2024,
                    2 => .style_legacy,
                    3 => .style2026,
                    else => return error.InvalidFieldType,
                };
                if (value != 0) features.markPresent("enforce_naming_style");
            },
            8 => {
                const value = try reader.readInt32();
                features.default_symbol_visibility = switch (value) {
                    0 => features.default_symbol_visibility,
                    1 => .export_all,
                    2 => .export_top_level,
                    3 => .local_all,
                    4 => .strict,
                    else => return error.InvalidFieldType,
                };
                if (value != 0) features.markPresent("default_symbol_visibility");
            },
            9 => {
                const value = try reader.readInt32();
                features.enforce_proto_limits = switch (value) {
                    0 => features.enforce_proto_limits,
                    1 => .legacy_no_explicit_limits,
                    2 => .proto_limits2026,
                    else => return error.InvalidFieldType,
                };
                if (value != 0) features.markPresent("enforce_proto_limits");
            },
            else => {
                const raw_start = reader.lastTagStart();
                try reader.skipValue(tag);
                const raw_end = reader.position();
                if (unknown_start == null) unknown_start = raw_start;
                unknown_end = raw_end;
                unknown_bytes += raw_end - raw_start;
            },
        }
    }
    // Custom feature extensions are unknown fields of FeatureSet. Preserve
    // them when they form one contiguous run, which covers protoc's output.
    if (unknown_start) |start| {
        if (unknown_bytes == unknown_end - start) features.unknown = bytes[start..unknown_end];
    }
    return features;
}

fn decodeOneofIndexText(allocator: std.mem.Allocator, owned_strings: *std.ArrayList([]u8), index: i32) Error![]const u8 {
    if (index < 0) return error.InvalidFieldType;
    const text = try std.fmt.allocPrint(allocator, "{d}", .{index});
    errdefer allocator.free(text);
    try owned_strings.append(allocator, text);
    return text;
}

fn labelFromNumber(value: i32) Error!schema.Cardinality {
    return switch (value) {
        1 => .optional,
        2 => .required,
        3 => .repeated,
        else => error.InvalidFieldType,
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
        10 => .{ .group = leafTypeName(try requireTypeName(type_name)) },
        11 => .{ .message = try requireTypeName(type_name) },
        12 => .{ .scalar = .bytes },
        13 => .{ .scalar = .uint32 },
        14 => .{ .enumeration = try requireTypeName(type_name) },
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

fn requireTypeName(type_name: ?[]const u8) Error![]const u8 {
    const name = type_name orelse return error.InvalidFieldType;
    if (!isTypeNameReference(name)) return error.InvalidFieldType;
    return if (std.mem.startsWith(u8, name, ".")) name[1..] else name;
}

fn leafTypeName(type_name: []const u8) []const u8 {
    return if (std.mem.lastIndexOfScalar(u8, type_name, '.')) |idx| type_name[idx + 1 ..] else type_name;
}

fn collapseMapEntryMessages(allocator: std.mem.Allocator, file: *schema.FileDescriptor) Error!void {
    for (file.messages.items) |*message| try collapseMapEntriesInMessage(allocator, message);
}

fn collapseMapEntriesInMessage(allocator: std.mem.Allocator, message: *schema.MessageDescriptor) Error!void {
    if (message.messages.items.len != 0) {
        try message.nested_order.ensureTotalCapacity(allocator, message.messages.items.len);
        for (message.messages.items) |*nested| try message.nested_order.append(allocator, nested.name);
    }
    var index: usize = 0;
    while (index < message.messages.items.len) {
        if (try isMapEntryMessage(message.messages.items[index])) {
            const entry = &message.messages.items[index];
            if (entry.fields.items.len != 2) return error.InvalidFieldType;
            const key_field = entry.findField("key") orelse return error.InvalidFieldType;
            const value_field = entry.findField("value") orelse return error.InvalidFieldType;
            if (key_field.number != 1 or value_field.number != 2) return error.InvalidFieldType;
            if (key_field.cardinality != .optional or value_field.cardinality != .optional) return error.InvalidFieldType;
            if (entry.oneofs.items.len != 0 or entry.messages.items.len != 0 or entry.enums.items.len != 0 or entry.extensions.items.len != 0 or entry.extension_ranges.items.len != 0 or entry.reserved_ranges.items.len != 0 or entry.reserved_names.items.len != 0) return error.InvalidFieldType;
            const key_scalar = switch (key_field.kind) {
                .scalar => |scalar| scalar,
                else => return error.InvalidFieldType,
            };
            if (!key_scalar.validMapKey()) return error.InvalidFieldType;
            if (value_field.kind == .map or value_field.kind == .group) return error.InvalidFieldType;
            var matched = false;
            for (message.fields.items) |*field| {
                if (field.kind == .message and typeNameMatches(field.kind.message, entry.name)) {
                    if (field.cardinality != .repeated) return error.InvalidFieldType;
                    const expected_entry_name = try mapEntryName(allocator, field.name);
                    defer allocator.free(expected_entry_name);
                    if (!std.mem.eql(u8, entry.name, expected_entry_name)) return error.InvalidFieldType;
                    const value_kind = try allocator.create(schema.FieldKind);
                    value_kind.* = value_field.kind;
                    field.kind = .{ .map = .{ .key = key_scalar, .value = value_kind } };
                    matched = true;
                }
            }
            if (!matched) return error.InvalidFieldType;
            var removed = message.messages.swapRemove(index);
            removed.deinit(allocator);
            continue;
        }
        try collapseMapEntriesInMessage(allocator, &message.messages.items[index]);
        index += 1;
    }
}

fn isMapEntryMessage(message: schema.MessageDescriptor) Error!bool {
    return message.map_entry;
}

fn typeNameMatches(encoded_type_name: []const u8, entry_name: []const u8) bool {
    const leaf = if (std.mem.lastIndexOfScalar(u8, encoded_type_name, '.')) |idx| encoded_type_name[idx + 1 ..] else encoded_type_name;
    return std.mem.eql(u8, leaf, entry_name);
}

/// Internal declarations exposed for the externalized test suite.
const __pbz_test_defaultValueText = defaultValueText;
const __pbz_test_exactOptionBool = exactOptionBool;
const __pbz_test_exactOptionString = exactOptionString;
const __pbz_test_fileOptimizeMode = fileOptimizeMode;
const __pbz_test_writePackedInt32List = writePackedInt32List;
pub const test_helpers = struct {
    pub const defaultValueText = __pbz_test_defaultValueText;
    pub const exactOptionBool = __pbz_test_exactOptionBool;
    pub const exactOptionString = __pbz_test_exactOptionString;
    pub const fileOptimizeMode = __pbz_test_fileOptimizeMode;
    pub const writePackedInt32List = __pbz_test_writePackedInt32List;
};

test {
    _ = @import("descriptor_tests.zig");
}
