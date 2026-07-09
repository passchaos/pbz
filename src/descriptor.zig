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
    for (file.messages.items) |*message| try writeMessageDescriptor(allocator, file, message, "", 4, writer);
    for (file.enums.items) |*enumeration| try writeEnumDescriptor(allocator, file, enumeration, 5, writer);
    for (file.services.items) |*service| try writeServiceDescriptor(allocator, file, service, 6, writer);
    for (file.extensions.items) |*field| try writeFieldDescriptor(allocator, file, null, "", field, 7, writer);
    if (hasFileOptions(file)) try writeFileOptions(allocator, file, 8, writer);
    if (!file.source_code_info.isEmpty()) try writeSourceCodeInfo(allocator, &file.source_code_info, 9, writer);
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

pub fn encodeFeatureSetDefaults(allocator: std.mem.Allocator, defaults: *const schema.FeatureSetDefaults) Error![]u8 {
    var writer = wire.Writer.init(allocator);
    errdefer writer.deinit();
    try writeFeatureSetDefaults(allocator, defaults, &writer);
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
    if (entry.overridable_features) |features| try writeFeatureSet(allocator, features, 4, &tmp);
    if (entry.fixed_features) |features| try writeFeatureSet(allocator, features, 5, &tmp);
    try writer.writeMessage(field_number, tmp.slice());
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

    for (message.fields.items) |*field| try writeFieldDescriptor(allocator, file, message, scope, field, 2, &tmp);
    for (message.messages.items) |*nested| try writeMessageDescriptor(allocator, file, nested, scope, 3, &tmp);
    for (message.fields.items) |*field| {
        if (field.kind == .map) try writeMapEntryDescriptor(allocator, file, scope, field, 3, &tmp);
    }
    for (message.enums.items) |*enumeration| try writeEnumDescriptor(allocator, file, enumeration, 4, &tmp);
    for (message.extension_ranges.items) |*range| try writeExtensionRange(allocator, range, 5, &tmp);
    for (message.extensions.items) |*field| try writeFieldDescriptor(allocator, file, message, scope, field, 6, &tmp);
    if (hasMessageOptions(message)) try writeMessageOptions(allocator, message, 7, &tmp);
    for (message.oneofs.items) |*oneof| try writeOneofDescriptor(allocator, file, oneof, 8, &tmp);
    for (message.fields.items) |*field| {
        if (field.proto3_optional and field.oneof_name == null) try writeSyntheticOneofDescriptor(allocator, field, 8, &tmp);
    }
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

    const entry_name = try mapEntryName(allocator, field.name);
    defer allocator.free(entry_name);
    var entry_message = schema.MessageDescriptor{ .name = entry_name, .map_entry = true };
    defer entry_message.fields.deinit(allocator);

    const key_field = schema.FieldDescriptor{
        .name = "key",
        .number = 1,
        .cardinality = .optional,
        .kind = .{ .scalar = map_type.key },
    };
    try entry_message.fields.append(allocator, key_field);

    const value_field = schema.FieldDescriptor{
        .name = "value",
        .number = 2,
        .cardinality = .optional,
        .kind = map_type.value.*,
    };
    try entry_message.fields.append(allocator, value_field);

    try writeMessageDescriptor(allocator, file, &entry_message, parent_scope, field_number, writer);
}

fn writeFieldDescriptor(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    containing_message: ?*const schema.MessageDescriptor,
    containing_scope: []const u8,
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
        .message, .group => |type_name| try writeQualifiedTypeName(allocator, file, containing_scope, type_name, .message, 6, &tmp),
        .enumeration => |type_name| try writeQualifiedTypeName(allocator, file, containing_scope, type_name, .enumeration, 6, &tmp),
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
    if (field.default_value) |value| try writeDefaultValue(allocator, file, field.kind, value, 7, &tmp);
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
    try writer.writeMessage(field_number, tmp.slice());
}

fn hasEnumValueOptions(value: *const schema.EnumValueDescriptor) bool {
    return value.options.items.len != 0 or value.features != null or value.feature_support != null;
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
    try writer.writeMessage(field_number, tmp.slice());
}

fn hasOneofOptions(oneof: *const schema.OneofDescriptor) bool {
    return oneof.options.items.len != 0 or oneof.features != null;
}

fn writeExtensionRange(allocator: std.mem.Allocator, range: *const schema.ExtensionRange, field_number: wire.FieldNumber, writer: *wire.Writer) Error!void {
    var tmp = wire.Writer.init(allocator);
    defer tmp.deinit();
    try tmp.writeInt32(1, @intCast(range.start));
    if (range.end) |end| try tmp.writeInt32(2, @intCast(end));
    if (range.options.items.len != 0 or range.declarations.items.len != 0 or range.verification != null or range.features != null) try writeExtensionRangeOptions(allocator, range, 3, &tmp);
    try writer.writeMessage(field_number, tmp.slice());
}

fn writeExtensionRangeOptions(allocator: std.mem.Allocator, range: *const schema.ExtensionRange, field_number: wire.FieldNumber, writer: *wire.Writer) Error!void {
    var tmp = wire.Writer.init(allocator);
    defer tmp.deinit();
    for (range.declarations.items) |declaration| try writeExtensionDeclaration(allocator, declaration, 2, &tmp);
    if (range.verification) |verification| try tmp.writeInt32(3, @intFromEnum(verification));
    if (range.features) |features| try writeFeatureSet(allocator, features, 50, &tmp);
    try writeUninterpretedOptions(allocator, range.options.items, &tmp, .extension_range);
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
            1 => try generated.annotations.append(allocator, try decodeGeneratedCodeInfoAnnotation(allocator, try reader.readBytes())),
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
    try writer.writeMessage(field_number, tmp.slice());
}

fn hasServiceOptions(service: *const schema.ServiceDescriptor) bool {
    return service.options.items.len != 0 or service.features != null;
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
    try writer.writeMessage(field_number, tmp.slice());
}

fn hasMethodOptions(method: *const schema.MethodDescriptor) bool {
    return method.options.items.len != 0 or method.features != null;
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
    try writer.writeMessage(field_number, tmp.slice());
}

fn hasFileOptions(file: *const schema.FileDescriptor) bool {
    return file.syntax == .editions or file.options.items.len != 0 or !file.features.eql(schema.FeatureSet.defaults(file.syntax));
}

fn writeMessageOptions(allocator: std.mem.Allocator, message: *const schema.MessageDescriptor, field_number: wire.FieldNumber, writer: *wire.Writer) Error!void {
    var tmp = wire.Writer.init(allocator);
    defer tmp.deinit();
    if (message.messageSetWireFormat()) try tmp.writeBool(1, true);
    if (exactOptionBool(message.options.items, "no_standard_descriptor_accessor")) |value| try tmp.writeBool(2, value);
    if (exactOptionBool(message.options.items, "deprecated")) |value| try tmp.writeBool(3, value);
    if (message.map_entry) try tmp.writeBool(7, true);
    if (exactOptionBool(message.options.items, "deprecated_legacy_json_field_conflicts")) |value| try tmp.writeBool(11, value);
    if (message.features) |features| try writeFeatureSet(allocator, features, 12, &tmp);
    try writeUninterpretedOptions(allocator, message.options.items, &tmp, .message);
    try writer.writeMessage(field_number, tmp.slice());
}

fn hasMessageOptions(message: *const schema.MessageDescriptor) bool {
    return message.options.items.len != 0 or message.map_entry or message.features != null;
}

fn writeEnumOptions(allocator: std.mem.Allocator, enumeration: *const schema.EnumDescriptor, field_number: wire.FieldNumber, writer: *wire.Writer) Error!void {
    var tmp = wire.Writer.init(allocator);
    defer tmp.deinit();
    if (enumAllowsAlias(enumeration)) try tmp.writeBool(2, true);
    if (exactOptionBool(enumeration.options.items, "deprecated")) |value| try tmp.writeBool(3, value);
    if (exactOptionBool(enumeration.options.items, "deprecated_legacy_json_field_conflicts")) |value| try tmp.writeBool(6, value);
    if (enumeration.features) |features| try writeFeatureSet(allocator, features, 7, &tmp);
    try writeUninterpretedOptions(allocator, enumeration.options.items, &tmp, .enumeration);
    try writer.writeMessage(field_number, tmp.slice());
}

fn hasEnumOptions(enumeration: *const schema.EnumDescriptor) bool {
    return enumeration.options.items.len != 0 or enumeration.features != null;
}

fn enumAllowsAlias(enumeration: *const schema.EnumDescriptor) bool {
    for (enumeration.options.items) |option| {
        if (std.mem.eql(u8, option.name, "allow_alias")) return schema.optionAsBool(option.value) orelse false;
    }
    return false;
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

const OptionScope = enum { file, field, message, enumeration, enum_value, oneof, service, method, extension_range };

fn writeUninterpretedOptions(allocator: std.mem.Allocator, options: []const schema.FieldOption, writer: *wire.Writer, scope: OptionScope) Error!void {
    for (options) |option| {
        if (isKnownOption(option.name, scope)) continue;
        var tmp = wire.Writer.init(allocator);
        defer tmp.deinit();
        try writeOptionName(allocator, option.name, &tmp);
        try writeOptionValue(option.value, &tmp);
        try writer.writeMessage(999, tmp.slice());
    }
}

fn isKnownOption(name: []const u8, scope: OptionScope) bool {
    const trimmed = std.mem.trim(u8, name, " \t\r\n");
    if (std.mem.startsWith(u8, trimmed, "features.")) return true;
    return switch (scope) {
        .file => isKnownFileOption(trimmed),
        .message => std.mem.eql(u8, trimmed, "message_set_wire_format") or std.mem.eql(u8, trimmed, "no_standard_descriptor_accessor") or std.mem.eql(u8, trimmed, "deprecated") or std.mem.eql(u8, trimmed, "map_entry") or std.mem.eql(u8, trimmed, "deprecated_legacy_json_field_conflicts"),
        .enumeration => std.mem.eql(u8, trimmed, "allow_alias") or std.mem.eql(u8, trimmed, "deprecated") or std.mem.eql(u8, trimmed, "deprecated_legacy_json_field_conflicts"),
        .enum_value => std.mem.eql(u8, trimmed, "deprecated") or std.mem.eql(u8, trimmed, "debug_redact") or std.mem.eql(u8, trimmed, "feature_support"),
        .oneof => false,
        .service => std.mem.eql(u8, trimmed, "deprecated"),
        .method => std.mem.eql(u8, trimmed, "deprecated") or std.mem.eql(u8, trimmed, "idempotency_level"),
        .field => std.mem.eql(u8, trimmed, "ctype") or std.mem.eql(u8, trimmed, "packed") or std.mem.eql(u8, trimmed, "default") or std.mem.eql(u8, trimmed, "json_name") or std.mem.eql(u8, trimmed, "jstype") or std.mem.eql(u8, trimmed, "lazy") or std.mem.eql(u8, trimmed, "unverified_lazy") or std.mem.eql(u8, trimmed, "deprecated") or std.mem.eql(u8, trimmed, "weak") or std.mem.eql(u8, trimmed, "debug_redact") or std.mem.eql(u8, trimmed, "retention") or std.mem.eql(u8, trimmed, "targets") or std.mem.eql(u8, trimmed, "edition_defaults") or std.mem.eql(u8, trimmed, "feature_support"),
        .extension_range => std.mem.eql(u8, schema.optionLeaf(name), "declaration") or std.mem.eql(u8, schema.optionLeaf(name), "verification"),
    };
}

fn isKnownFileOption(trimmed: []const u8) bool {
    return std.mem.eql(u8, trimmed, "java_package") or
        std.mem.eql(u8, trimmed, "java_outer_classname") or
        std.mem.eql(u8, trimmed, "java_multiple_files") or
        std.mem.eql(u8, trimmed, "java_generate_equals_and_hash") or
        std.mem.eql(u8, trimmed, "java_string_check_utf8") or
        std.mem.eql(u8, trimmed, "optimize_for") or
        std.mem.eql(u8, trimmed, "go_package") or
        std.mem.eql(u8, trimmed, "cc_generic_services") or
        std.mem.eql(u8, trimmed, "java_generic_services") or
        std.mem.eql(u8, trimmed, "py_generic_services") or
        std.mem.eql(u8, trimmed, "deprecated") or
        std.mem.eql(u8, trimmed, "cc_enable_arenas") or
        std.mem.eql(u8, trimmed, "objc_class_prefix") or
        std.mem.eql(u8, trimmed, "csharp_namespace") or
        std.mem.eql(u8, trimmed, "swift_prefix") or
        std.mem.eql(u8, trimmed, "php_class_prefix") or
        std.mem.eql(u8, trimmed, "php_namespace") or
        std.mem.eql(u8, trimmed, "php_metadata_namespace") or
        std.mem.eql(u8, trimmed, "ruby_package");
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
        .float => |v| try writer.writeDouble(6, v),
        .string => |text| try writer.writeBytes(7, text),
        .boolean => |v| try writer.writeString(3, if (v) "true" else "false"),
        .aggregate => |text| try writer.writeString(8, text),
    }
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

fn writeDefaultValue(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, kind: schema.FieldKind, value: schema.OptionValue, field_number: wire.FieldNumber, writer: *wire.Writer) Error!void {
    const text = try defaultValueText(allocator, file, kind, value);
    defer allocator.free(text);
    try writer.writeString(field_number, text);
}

fn defaultValueText(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, kind: schema.FieldKind, value: schema.OptionValue) std.mem.Allocator.Error![]u8 {
    if (kind == .enumeration) {
        if (enumDefaultName(file, kind.enumeration, value)) |name| return try allocator.dupe(u8, name);
    }
    if (kind == .scalar and kind.scalar == .bytes) {
        const bytes = switch (value) {
            .string, .identifier => |text| text,
            else => return optionValueText(allocator, value),
        };
        return try escapeBytesDefaultAlloc(allocator, bytes);
    }
    return optionValueText(allocator, value);
}

fn enumDefaultName(file: *const schema.FileDescriptor, enum_name: []const u8, value: schema.OptionValue) ?[]const u8 {
    const number: i32 = switch (value) {
        .integer => |v| if (v >= std.math.minInt(i32) and v <= std.math.maxInt(i32)) @intCast(v) else return null,
        .identifier, .string => |text| {
            if (file.findEnumDeep(enum_name)) |enumeration| {
                if (enumeration.findValue(text)) |enum_value| return enum_value.name;
            }
            return null;
        },
        else => return null,
    };
    if (file.findEnumDeep(enum_name)) |enumeration| {
        for (enumeration.values.items) |enum_value| {
            if (enum_value.number == number) return enum_value.name;
        }
    }
    return null;
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

const DescriptorTypeKind = enum { message, enumeration };

fn writeQualifiedTypeName(
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    containing_scope: []const u8,
    type_name: []const u8,
    comptime kind: DescriptorTypeKind,
    field_number: wire.FieldNumber,
    writer: *wire.Writer,
) Error!void {
    const resolved = try resolveDescriptorTypeName(allocator, file, containing_scope, type_name, kind);
    defer allocator.free(resolved);
    try writer.writeString(field_number, resolved);
}

fn qualifiedName(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, name: []const u8) std.mem.Allocator.Error![]u8 {
    if (std.mem.startsWith(u8, name, ".")) return try allocator.dupe(u8, name);
    if (file.package.len == 0) return try std.fmt.allocPrint(allocator, ".{s}", .{name});
    if (std.mem.startsWith(u8, name, file.package)) return try std.fmt.allocPrint(allocator, ".{s}", .{name});
    return try std.fmt.allocPrint(allocator, ".{s}.{s}", .{ file.package, name });
}

fn resolveDescriptorTypeName(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, containing_scope: []const u8, type_name: []const u8, comptime kind: DescriptorTypeKind) std.mem.Allocator.Error![]u8 {
    if (std.mem.startsWith(u8, type_name, ".")) return try allocator.dupe(u8, type_name);
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
    file.source_code_info.deinit(allocator);
    file.source_code_info = .{};

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

test "descriptor encodes nested map entry type names with full scope" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto3";
        \\package demo;
        \\message Outer {
        \\  message Inner {
        \\    map<string, int32> tags = 1;
        \\  }
        \\}
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();

    const bytes = try encodeFileDescriptorProto(allocator, &file, "nested-map.proto");
    defer allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, ".demo.Outer.Inner.TagsEntry") != null);

    var decoded = try decodeFileDescriptorProto(allocator, bytes);
    defer decoded.deinit();
    const outer = decoded.findMessage("Outer").?;
    const inner = outer.findMessage("Inner").?;
    const tags = inner.findField("tags").?;
    try std.testing.expect(tags.kind == .map);
    try std.testing.expectEqual(schema.ScalarType.string, tags.kind.map.key);
    try std.testing.expect(tags.kind.map.value.* == .scalar);
    try std.testing.expectEqual(schema.ScalarType.int32, tags.kind.map.value.scalar);
}

test "descriptor encodes nested message and enum type names with full scope" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto2";
        \\package demo;
        \\message Outer {
        \\  message Child { optional int32 id = 1; }
        \\  enum Kind { UNKNOWN = 0; ACTIVE = 1; }
        \\  message Inner {
        \\    optional Child child = 1;
        \\    optional Kind kind = 2 [default = ACTIVE];
        \\    message Local { optional string name = 1; }
        \\    optional Local local = 3;
        \\  }
        \\}
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();

    const bytes = try encodeFileDescriptorProto(allocator, &file, "nested-types.proto");
    defer allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, ".demo.Outer.Child") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, ".demo.Outer.Kind") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, ".demo.Outer.Inner.Local") != null);

    var decoded = try decodeFileDescriptorProto(allocator, bytes);
    defer decoded.deinit();
    const outer = decoded.findMessage("Outer").?;
    const inner = outer.findMessage("Inner").?;
    try std.testing.expectEqualStrings("demo.Outer.Child", inner.findField("child").?.kind.message);
    try std.testing.expectEqualStrings("demo.Outer.Kind", inner.findField("kind").?.kind.enumeration);
    try std.testing.expectEqualStrings("demo.Outer.Inner.Local", inner.findField("local").?.kind.message);
    try std.testing.expectEqual(@as(i64, 1), inner.findField("kind").?.default_value.?.integer);
}

pub fn decodeFileDescriptorProto(allocator: std.mem.Allocator, bytes: []const u8) Error!schema.FileDescriptor {
    var file = schema.FileDescriptor.init(allocator);
    errdefer file.deinit();
    var public_deps: std.ArrayList(i32) = .empty;
    defer public_deps.deinit(allocator);
    var weak_deps: std.ArrayList(i32) = .empty;
    defer weak_deps.deinit(allocator);
    var saw_file_features = false;
    var saw_syntax: ?schema.Syntax = null;
    var saw_edition_field = false;
    const owned_bytes = try allocator.dupe(u8, bytes);
    try file.owned_strings.append(allocator, owned_bytes);

    var reader = wire.Reader.init(owned_bytes);
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            1 => file.name = try reader.readBytes(),
            2 => file.package = try reader.readBytes(),
            3 => try file.imports.append(allocator, .{ .path = try reader.readBytes() }),
            10 => try public_deps.append(allocator, try reader.readInt32()),
            11 => try weak_deps.append(allocator, try reader.readInt32()),
            15 => try file.imports.append(allocator, .{ .path = try reader.readBytes(), .kind = .option }),
            4 => try file.messages.append(allocator, try decodeMessageDescriptor(allocator, &file.owned_strings, try reader.readBytes())),
            5 => try file.enums.append(allocator, try decodeEnumDescriptor(allocator, try reader.readBytes())),
            6 => try file.services.append(allocator, try decodeServiceDescriptor(allocator, try reader.readBytes())),
            7 => try file.extensions.append(allocator, try decodeFieldDescriptor(allocator, &file.owned_strings, try reader.readBytes())),
            8 => saw_file_features = try decodeFileOptions(allocator, &file, try reader.readBytes()) or saw_file_features,
            9 => file.source_code_info = try decodeSourceCodeInfo(allocator, try reader.readBytes()),
            12 => {
                const syntax = try reader.readBytes();
                if (std.mem.eql(u8, syntax, "proto2")) {
                    saw_syntax = .proto2;
                    file.syntax = .proto2;
                    file.edition = schema.Syntax.proto2.defaultEdition();
                    if (!saw_file_features) file.features = schema.FeatureSet.defaults(.proto2);
                } else if (std.mem.eql(u8, syntax, "proto3")) {
                    saw_syntax = .proto3;
                    file.syntax = .proto3;
                    file.edition = schema.Syntax.proto3.defaultEdition();
                    if (!saw_file_features) file.features = schema.FeatureSet.defaults(.proto3);
                } else if (std.mem.eql(u8, syntax, "editions")) {
                    saw_syntax = .editions;
                    file.syntax = .editions;
                    if (!saw_edition_field) file.edition = schema.Syntax.editions.defaultEdition();
                    if (!saw_file_features) file.features = schema.FeatureSet.defaults(.editions);
                } else return error.InvalidFieldType;
            },
            14 => {
                saw_edition_field = true;
                file.syntax = .editions;
                file.edition = std.enums.fromInt(schema.Edition, try reader.readInt32()) orelse return error.InvalidFieldType;
                if (!saw_file_features) file.features = schema.FeatureSet.defaults(.editions);
            },
            else => try reader.skipValue(tag),
        }
    }
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
    try validateDecodedImportSemantics(&file);
    try collapseMapEntryMessages(allocator, &file);
    resolveDecodedEnumDefaults(&file);
    try validateDecodedFileDescriptor(&file);
    try validateDecodedPackedOptions(&file);
    try validateDecodedDefaults(&file);
    try validateDecodedFieldSyntax(&file);
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
    if (@intFromEnum(file.edition) < @intFromEnum(schema.Edition.edition_2024)) return;
    for (file.imports.items) |import| {
        if (import.kind == .weak) return error.InvalidFieldType;
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
    }
    for (file.extensions.items) |field| try validateDecodedExtensionFieldDescriptor(&field);
}

fn isIdentifier(value: []const u8) bool {
    if (value.len == 0) return false;
    if (!isIdentifierStart(value[0])) return false;
    for (value[1..]) |c| {
        if (!isIdentifierContinue(c)) return false;
    }
    return true;
}

fn isTypeNameReference(value: []const u8) bool {
    if (value.len == 0) return false;
    const normalized = if (std.mem.startsWith(u8, value, ".")) value[1..] else value;
    return isFullIdentifier(normalized);
}

fn isExtensionDeclarationTypeName(value: []const u8) bool {
    return schema.ScalarType.fromName(value) != null or isTypeNameReference(value);
}

fn isFullIdentifier(value: []const u8) bool {
    var index: usize = 0;
    var expect_start = true;
    while (index < value.len) : (index += 1) {
        const c = value[index];
        if (c == '.') {
            if (expect_start) return false;
            expect_start = true;
            continue;
        }
        if (expect_start) {
            if (!isIdentifierStart(c)) return false;
            expect_start = false;
        } else if (!isIdentifierContinue(c)) return false;
    }
    return !expect_start;
}

fn isIdentifierStart(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_';
}

fn isIdentifierContinue(c: u8) bool {
    return isIdentifierStart(c) or std.ascii.isDigit(c);
}

fn validateDecodedExtensionDeclarations(file: *const schema.FileDescriptor) Error!void {
    for (file.extensions.items) |*field| {
        try validateDecodedExtensionConflict(file, field);
        try validateDecodedExtensionDeclaration(file, field);
    }
    for (file.messages.items) |*message| try validateDecodedMessageExtensionDeclarations(file, message);
}

fn validateDecodedMessageExtensionDeclarations(file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor) Error!void {
    for (message.extensions.items) |*field| {
        try validateDecodedExtensionConflict(file, field);
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
    if (field.cardinality == .repeated or field.kind == .map or field.oneof_name != null or field.proto3_optional) return error.InvalidFieldType;
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
            .integer => {},
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
    if (field.packed_override == null) return;
    if (file.syntax == .editions) return error.InvalidFieldType;
    if (!field.isPackable()) return error.InvalidFieldType;
}

fn validateDecodedFieldSyntax(file: *const schema.FileDescriptor) Error!void {
    for (file.extensions.items) |*field| try validateDecodedFieldSyntaxOne(file, field, true);
    for (file.messages.items) |*message| try validateDecodedMessageFieldSyntax(file, message);
}

fn validateDecodedMessageFieldSyntax(file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor) Error!void {
    for (message.fields.items) |*field| try validateDecodedFieldSyntaxOne(file, field, false);
    for (message.extensions.items) |*field| try validateDecodedFieldSyntaxOne(file, field, true);
    for (message.messages.items) |*nested| try validateDecodedMessageFieldSyntax(file, nested);
}

fn validateDecodedFieldSyntaxOne(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, is_extension: bool) Error!void {
    if (field.cardinality == .required and file.syntax != .proto2) return error.InvalidFieldType;
    if (field.cardinality == .required and is_extension) return error.InvalidFieldType;
    if (field.proto3_optional and file.syntax != .proto3) return error.InvalidFieldType;
    if (file.syntax == .editions and field.kind == .group) return error.InvalidFieldType;
    try validateDecodedFieldOptionApplicability(file, field, is_extension);
}

fn validateDecodedFieldOptionApplicability(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, is_extension: bool) Error!void {
    if (@intFromEnum(file.edition) >= @intFromEnum(schema.Edition.edition_2024) and optionEnumNumber(field.options.items, "ctype") != null) return error.InvalidFieldType;
    if (optionEnumNumber(field.options.items, "jstype")) |jstype| {
        if (jstype != 0 and !fieldKindAllowsJSType(field.kind)) return error.InvalidFieldType;
    }
    const lazy = exactOptionBool(field.options.items, "lazy") orelse false;
    const unverified_lazy = exactOptionBool(field.options.items, "unverified_lazy") orelse false;
    if (lazy or unverified_lazy) {
        if (!fieldKindIsSubmessage(field.kind)) return error.InvalidFieldType;
    }
    if (unverified_lazy and is_extension) return error.InvalidFieldType;
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
        var has_message_set_range = false;
        for (message.extension_ranges.items) |range| {
            const end = range.end orelse std.math.maxInt(i64);
            if (range.start <= 4 and end > 4) has_message_set_range = true;
        }
        if (!has_message_set_range) return error.InvalidFieldType;
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

fn validateDecodedExtensionConflict(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor) Error!void {
    for (file.extensions.items) |*other| try validateDecodedExtensionConflictPair(field, other);
    for (file.messages.items) |*message| try validateDecodedExtensionConflictInMessage(field, message);
}

fn validateDecodedExtensionConflictInMessage(field: *const schema.FieldDescriptor, message: *const schema.MessageDescriptor) Error!void {
    for (message.extensions.items) |*other| try validateDecodedExtensionConflictPair(field, other);
    for (message.messages.items) |*nested| try validateDecodedExtensionConflictInMessage(field, nested);
}

fn validateDecodedExtensionConflictPair(field: *const schema.FieldDescriptor, other: *const schema.FieldDescriptor) Error!void {
    if (field == other) return;
    const extendee = field.extendee orelse return;
    const other_extendee = other.extendee orelse return;
    if (!descriptorNamesMatch(extendee, other_extendee)) return;
    if (field.number == other.number) return error.InvalidFieldType;
    if (std.mem.eql(u8, field.name, other.name)) return error.InvalidFieldType;
}

fn validateDecodedExtensionDeclaration(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor) Error!void {
    const extendee_name = field.extendee orelse return;
    const extendee = file.findMessageDeep(extendee_name) orelse return;
    for (extendee.extension_ranges.items) |range| {
        const end = range.end orelse std.math.maxInt(i64);
        if (field.number >= range.start and field.number < end) {
            return try validateDecodedExtensionFieldDeclaration(field, range);
        }
    }
    return error.InvalidFieldType;
}

fn validateDecodedExtensionFieldDeclaration(field: *const schema.FieldDescriptor, range: schema.ExtensionRange) Error!void {
    var matching_declaration: ?schema.ExtensionDeclaration = null;
    for (range.declarations.items) |declaration| {
        if (declaration.number == @as(i32, @intCast(field.number))) matching_declaration = declaration;
    }
    const declaration = matching_declaration orelse {
        if (range.verification == .declaration) return error.InvalidFieldType;
        return;
    };
    if (declaration.reserved) return error.InvalidFieldType;
    if (declaration.full_name.len != 0 and !descriptorNamesMatch(declaration.full_name, field.name)) return error.InvalidFieldType;
    if (declaration.repeated and field.cardinality != .repeated) return error.InvalidFieldType;
    if (!declaration.repeated and field.cardinality == .repeated) return error.InvalidFieldType;
    if (declaration.type_name.len != 0 and !descriptorExtensionTypeMatches(field, declaration.type_name)) return error.InvalidFieldType;
}

fn descriptorNormalizeName(name: []const u8) []const u8 {
    return if (std.mem.startsWith(u8, name, ".")) name[1..] else name;
}

fn descriptorNamesMatch(a: []const u8, b: []const u8) bool {
    const na = descriptorNormalizeName(a);
    const nb = descriptorNormalizeName(b);
    return std.mem.eql(u8, na, nb) or std.mem.endsWith(u8, na, nb) or std.mem.endsWith(u8, nb, na);
}

fn descriptorExtensionTypeMatches(field: *const schema.FieldDescriptor, declared_type: []const u8) bool {
    return switch (field.kind) {
        .message, .enumeration, .group => |type_name| descriptorNamesMatch(declared_type, type_name),
        .scalar => |scalar| std.mem.eql(u8, descriptorNormalizeName(declared_type), descriptorScalarTypeName(scalar)),
        .map => false,
    };
}

fn descriptorScalarTypeName(scalar: schema.ScalarType) []const u8 {
    return switch (scalar) {
        .double => "double",
        .float => "float",
        .int32 => "int32",
        .int64 => "int64",
        .uint32 => "uint32",
        .uint64 => "uint64",
        .sint32 => "sint32",
        .sint64 => "sint64",
        .fixed32 => "fixed32",
        .fixed64 => "fixed64",
        .sfixed32 => "sfixed32",
        .sfixed64 => "sfixed64",
        .bool => "bool",
        .string => "string",
        .bytes => "bytes",
    };
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
                if (field.oneof_name) |idx_text| {
                    const idx = try std.fmt.parseInt(usize, idx_text, 10);
                    field.oneof_name = null;
                    try oneof_indexes.append(allocator, .{ .field_index = message.fields.items.len, .oneof_index = idx });
                }
                try message.fields.append(allocator, field);
            },
            3 => try message.messages.append(allocator, try decodeMessageDescriptor(allocator, owned_strings, try reader.readBytes())),
            4 => try message.enums.append(allocator, try decodeEnumDescriptor(allocator, try reader.readBytes())),
            5 => try message.extension_ranges.append(allocator, try decodeExtensionRange(allocator, try reader.readBytes())),
            6 => try message.extensions.append(allocator, try decodeFieldDescriptor(allocator, owned_strings, try reader.readBytes())),
            7 => try decodeMessageOptions(allocator, &message, try reader.readBytes()),
            8 => try message.oneofs.append(allocator, try decodeOneofDescriptor(allocator, try reader.readBytes())),
            9 => try message.reserved_ranges.append(allocator, try decodeReservedRange(allocator, try reader.readBytes(), false)),
            10 => try message.reserved_names.append(allocator, try reader.readBytes()),
            else => try reader.skipValue(tag),
        }
    }

    try validateDecodedMessageDescriptor(&message);
    for (oneof_indexes.items) |item| {
        if (item.oneof_index >= message.oneofs.items.len) return error.InvalidFieldType;
        message.fields.items[item.field_index].oneof_name = message.oneofs.items[item.oneof_index].name;
    }
    for (message.fields.items) |field| try validateDecodedOneofFieldShape(&field);
    try validateDecodedProto3OptionalFields(&message);
    return message;
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
    for (message.fields.items, 0..) |field, i| {
        if (!isIdentifier(field.name) or field.number == 0) return error.InvalidFieldType;
        try validateDecodedFieldJsonName(&field, false);
        for (message.fields.items[i + 1 ..]) |other| {
            if (field.number == other.number or std.mem.eql(u8, field.name, other.name)) return error.InvalidFieldType;
        }
        for (message.reserved_ranges.items) |range| {
            if (rangeContains(range, field.number)) return error.InvalidFieldType;
        }
        for (message.extension_ranges.items) |range| {
            if (rangeContains(.{ .start = range.start, .end = range.end }, field.number)) return error.InvalidFieldType;
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
    }
    for (message.enums.items, 0..) |enumeration, i| {
        for (message.enums.items[i + 1 ..]) |other| {
            if (std.mem.eql(u8, enumeration.name, other.name)) return error.InvalidFieldType;
        }
    }
    try validateDecodedFieldJsonNameUniqueness(message.fields.items);
    for (message.extensions.items) |field| try validateDecodedExtensionFieldDescriptor(&field);
    try validateDecodedExtensionRanges(message.extension_ranges.items, message.reserved_ranges.items);
    try validateDecodedReservedRanges(message.reserved_ranges.items, message.reserved_names.items);
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

fn validateDecodedExtensionRanges(extension_ranges: []const schema.ExtensionRange, reserved_ranges: []const schema.ReservedRange) Error!void {
    for (extension_ranges, 0..) |range, i| {
        const as_reserved = schema.ReservedRange{ .start = range.start, .end = range.end };
        for (extension_ranges[i + 1 ..]) |other| {
            if (rangesOverlap(as_reserved, .{ .start = other.start, .end = other.end })) return error.InvalidFieldType;
        }
        for (reserved_ranges) |reserved| {
            if (rangesOverlap(as_reserved, reserved)) return error.InvalidFieldType;
        }
    }
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
    errdefer field_options.deinit(allocator);
    errdefer edition_defaults.deinit(allocator);

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
                decoded_options.options = .empty;
                decoded_options.edition_defaults = .empty;
            },
            9 => oneof_index_text = try oneofIndexText(try reader.readInt32()),
            10 => json_name = try reader.readBytes(),
            17 => proto3_optional = try reader.readBool(),
            else => try reader.skipValue(tag),
        }
    }
    if (extendee) |extendee_name| {
        if (!isTypeNameReference(extendee_name)) return error.InvalidFieldType;
    }

    const kind = try kindFromType(allocator, field_type, type_name);
    if (default_value_text != null and (cardinality == .repeated or oneof_index_text != null)) return error.InvalidFieldType;
    const field = schema.FieldDescriptor{
        .name = name,
        .number = number,
        .cardinality = cardinality,
        .kind = kind,
        .extendee = extendee,
        .default_value = if (default_value_text) |text| try decodeDefaultValue(allocator, owned_strings, kind, text) else null,
        .oneof_name = oneof_index_text,
        .json_name = json_name,
        .proto3_optional = proto3_optional,
        .packed_override = packed_override,
        .edition_defaults = edition_defaults,
        .features = features,
        .feature_support = feature_support,
        .options = field_options,
    };
    if (!isIdentifier(field.name) or field.number == 0) return error.InvalidFieldType;
    field_options = .empty;
    edition_defaults = .empty;
    return field;
}

fn fieldNumberFromDescriptor(value: i32) wire.Error!wire.FieldNumber {
    if (value <= 0 or value > std.math.maxInt(wire.FieldNumber)) return error.InvalidFieldNumber;
    if (value >= 19000 and value <= 19999) return error.InvalidFieldNumber;
    return @intCast(value);
}

fn decodeDefaultValue(allocator: std.mem.Allocator, owned_strings: *std.ArrayList([]u8), kind: schema.FieldKind, text: []const u8) Error!schema.OptionValue {
    return switch (kind) {
        .scalar => |scalar| switch (scalar) {
            .double => .{ .float = try parseFloatDefault(f64, text) },
            .float => .{ .float = try parseFloatDefault(f32, text) },
            .int32, .sint32, .sfixed32 => .{ .integer = try parseSignedIntegerDefault(i32, text) },
            .int64, .sint64, .sfixed64 => .{ .integer = try parseSignedIntegerDefault(i64, text) },
            .uint32, .fixed32 => .{ .integer = try parseUnsignedIntegerDefault(u32, text) },
            .uint64, .fixed64 => .{ .integer = try parseUnsignedIntegerDefault(u64, text) },
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
    if (std.mem.eql(u8, text, "inf")) return std.math.inf(f64);
    if (std.mem.eql(u8, text, "-inf")) return -std.math.inf(f64);
    if (std.mem.eql(u8, text, "nan")) return std.math.nan(f64);
    const value = std.fmt.parseFloat(T, text) catch return error.InvalidFieldType;
    return @floatCast(value);
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
            2 => try enumeration.values.append(allocator, try decodeEnumValueDescriptor(allocator, try reader.readBytes())),
            3 => try decodeEnumOptions(allocator, &enumeration, try reader.readBytes()),
            4 => try enumeration.reserved_ranges.append(allocator, try decodeReservedRange(allocator, try reader.readBytes(), true)),
            5 => try enumeration.reserved_names.append(allocator, try reader.readBytes()),
            else => try reader.skipValue(tag),
        }
    }
    try validateEnumDescriptor(&enumeration);
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
            999 => try enumeration.options.append(allocator, try decodeUninterpretedOption(allocator, try reader.readBytes())),
            else => try reader.skipValue(tag),
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
            999 => try value.options.append(allocator, try decodeUninterpretedOption(allocator, try reader.readBytes())),
            else => try reader.skipValue(tag),
        }
    }
}

fn validateEnumDescriptor(enumeration: *const schema.EnumDescriptor) Error!void {
    if (!isIdentifier(enumeration.name) or enumeration.values.items.len == 0) return error.InvalidFieldType;
    const allow_alias = enumAllowsAlias(enumeration);
    for (enumeration.values.items, 0..) |value, i| {
        if (!isIdentifier(value.name)) return error.InvalidFieldType;
        for (enumeration.values.items[i + 1 ..]) |other| {
            if (std.mem.eql(u8, value.name, other.name)) return error.InvalidFieldType;
            if (!allow_alias and value.number == other.number) return error.InvalidFieldType;
        }
        for (enumeration.reserved_ranges.items) |range| {
            if (rangeContains(range, value.number)) return error.InvalidFieldType;
        }
        for (enumeration.reserved_names.items) |name| {
            if (std.mem.eql(u8, name, value.name)) return error.InvalidFieldType;
        }
    }
    try validateDecodedReservedRanges(enumeration.reserved_ranges.items, enumeration.reserved_names.items);
}

fn validateDecodedReservedRanges(ranges: []const schema.ReservedRange, names: []const []const u8) Error!void {
    for (ranges, 0..) |range, i| {
        const end = range.end orelse std.math.maxInt(i64);
        if (end <= range.start) return error.InvalidFieldType;
        for (ranges[i + 1 ..]) |other| {
            if (rangesOverlap(range, other)) return error.InvalidFieldType;
        }
    }
    for (names, 0..) |name, i| {
        if (name.len == 0) return error.InvalidFieldType;
        for (names[i + 1 ..]) |other| {
            if (std.mem.eql(u8, name, other)) return error.InvalidFieldType;
        }
    }
}

fn rangeContains(range: schema.ReservedRange, number: i64) bool {
    const end = range.end orelse std.math.maxInt(i64);
    return number >= range.start and number < end;
}

fn rangesOverlap(a: schema.ReservedRange, b: schema.ReservedRange) bool {
    const a_end = a.end orelse std.math.maxInt(i64);
    const b_end = b.end orelse std.math.maxInt(i64);
    return a.start < b_end and b.start < a_end;
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
    const end = range.end orelse std.math.maxInt(i64);
    if (end <= range.start) return error.InvalidFieldType;
    for (range.declarations.items, 0..) |declaration, index| {
        if (declaration.number <= 0) return error.InvalidFieldType;
        if (declaration.number < range.start or declaration.number >= end) return error.InvalidFieldType;
        if (declaration.full_name.len != 0 and !isTypeNameReference(declaration.full_name)) return error.InvalidFieldType;
        if (declaration.type_name.len != 0 and !isExtensionDeclarationTypeName(declaration.type_name)) return error.InvalidFieldType;
        for (range.declarations.items[index + 1 ..]) |other| {
            if (declaration.number == other.number) return error.InvalidFieldType;
            if (declaration.full_name.len != 0 and other.full_name.len != 0 and std.mem.eql(u8, declaration.full_name, other.full_name)) return error.InvalidFieldType;
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
            999 => try range.options.append(allocator, try decodeUninterpretedOption(allocator, try reader.readBytes())),
            else => try reader.skipValue(tag),
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
            1 => try source.locations.append(allocator, try decodeSourceCodeInfoLocation(allocator, try reader.readBytes())),
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
            2 => try service.methods.append(allocator, try decodeMethodDescriptor(allocator, try reader.readBytes())),
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
            999 => try service.options.append(allocator, try decodeUninterpretedOption(allocator, try reader.readBytes())),
            else => try reader.skipValue(tag),
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
            999 => try method.options.append(allocator, try decodeUninterpretedOption(allocator, try reader.readBytes())),
            else => try reader.skipValue(tag),
        }
    }
}

fn decodeGenericOptions(allocator: std.mem.Allocator, options: *schema.OptionList, bytes: []const u8) Error!void {
    var reader = wire.Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        if (tag.number == 999) try options.append(allocator, try decodeUninterpretedOption(allocator, try reader.readBytes())) else try reader.skipValue(tag);
    }
}

fn decodeOneofOptions(allocator: std.mem.Allocator, oneof: *schema.OneofDescriptor, bytes: []const u8) Error!void {
    var reader = wire.Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            1 => oneof.features = try decodeFeatureSet(try reader.readBytes()),
            999 => try oneof.options.append(allocator, try decodeUninterpretedOption(allocator, try reader.readBytes())),
            else => try reader.skipValue(tag),
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
            999 => try message.options.append(allocator, try decodeUninterpretedOption(allocator, try reader.readBytes())),
            else => try reader.skipValue(tag),
        }
    }
}

fn decodeFileOptions(allocator: std.mem.Allocator, file: *schema.FileDescriptor, bytes: []const u8) Error!bool {
    var saw_features = false;
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
            50 => {
                file.features = try decodeFeatureSet(try reader.readBytes());
                saw_features = true;
            },
            999 => try file.options.append(allocator, try decodeUninterpretedOption(allocator, try reader.readBytes())),
            else => try reader.skipValue(tag),
        }
    }
    return saw_features;
}

const DecodedFieldOptions = struct {
    packed_override: ?bool = null,
    options: schema.OptionList = .empty,
    edition_defaults: std.ArrayList(schema.FieldEditionDefault) = .empty,
    features: ?schema.FeatureSet = null,
    feature_support: ?schema.FeatureSupport = null,

    fn deinit(self: *DecodedFieldOptions, allocator: std.mem.Allocator) void {
        self.options.deinit(allocator);
        self.edition_defaults.deinit(allocator);
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
            999 => try result.options.append(allocator, try decodeUninterpretedOption(allocator, try reader.readBytes())),
            else => try reader.skipValue(tag),
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
                if (v > std.math.maxInt(i64)) return error.InvalidFieldType;
                value = .{ .integer = @intCast(v) };
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

fn decodeFeatureSet(bytes: []const u8) Error!schema.FeatureSet {
    var features = schema.FeatureSet{};
    var reader = wire.Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            1 => features.field_presence = switch (try reader.readInt32()) {
                0 => features.field_presence,
                1 => .explicit,
                2 => .implicit,
                3 => .legacy_required,
                else => return error.InvalidFieldType,
            },
            2 => features.enum_type = switch (try reader.readInt32()) {
                0 => features.enum_type,
                1 => .open,
                2 => .closed,
                else => return error.InvalidFieldType,
            },
            3 => features.repeated_field_encoding = switch (try reader.readInt32()) {
                0 => features.repeated_field_encoding,
                1 => .packed_encoding,
                2 => .expanded,
                else => return error.InvalidFieldType,
            },
            4 => features.utf8_validation = switch (try reader.readInt32()) {
                0 => features.utf8_validation,
                2 => .verify,
                3 => .none,
                else => return error.InvalidFieldType,
            },
            5 => features.message_encoding = switch (try reader.readInt32()) {
                0 => features.message_encoding,
                1 => .length_prefixed,
                2 => .delimited,
                else => return error.InvalidFieldType,
            },
            6 => features.json_format = switch (try reader.readInt32()) {
                0 => features.json_format,
                1 => .allow,
                2 => .legacy_best_effort,
                else => return error.InvalidFieldType,
            },
            7 => features.enforce_naming_style = switch (try reader.readInt32()) {
                0 => features.enforce_naming_style,
                1 => .style2024,
                2 => .style_legacy,
                3 => .style2026,
                else => return error.InvalidFieldType,
            },
            8 => features.default_symbol_visibility = switch (try reader.readInt32()) {
                0 => features.default_symbol_visibility,
                1 => .export_all,
                2 => .export_top_level,
                3 => .local_all,
                4 => .strict,
                else => return error.InvalidFieldType,
            },
            9 => features.enforce_proto_limits = switch (try reader.readInt32()) {
                0 => features.enforce_proto_limits,
                1 => .legacy_no_explicit_limits,
                2 => .proto_limits2026,
                else => return error.InvalidFieldType,
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

test "descriptor rejects invalid service and method descriptors" {
    const allocator = std.testing.allocator;
    {
        var service = wire.Writer.init(allocator);
        defer service.deinit();
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-service.proto");
        try file.writeMessage(6, service.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var method = wire.Writer.init(allocator);
        defer method.deinit();
        try method.writeString(1, "Get");
        try method.writeString(3, ".demo.Res");
        var service = wire.Writer.init(allocator);
        defer service.deinit();
        try service.writeString(1, "Svc");
        try service.writeMessage(2, method.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-method.proto");
        try file.writeMessage(6, service.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var method = wire.Writer.init(allocator);
        defer method.deinit();
        try method.writeString(1, "Get");
        try method.writeString(2, ".demo.Req");
        try method.writeString(3, ".demo.Res");
        var service = wire.Writer.init(allocator);
        defer service.deinit();
        try service.writeString(1, "Svc");
        try service.writeMessage(2, method.slice());
        try service.writeMessage(2, method.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "dup-method.proto");
        try file.writeMessage(6, service.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
}

test "descriptor decodes scalar default values with typed option values" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Defaults {
        \\  optional int32 count = 1 [default = 42];
        \\  optional bool enabled = 2 [default = true];
        \\  optional float ratio = 3 [default = 1.5];
        \\  optional string name = 4 [default = "anon"];
        \\  optional bytes raw = 5 [default = "\001\x02"];
        \\}
    );
    defer file.deinit();

    const encoded = try encodeFileDescriptorProto(allocator, &file, "defaults.proto");
    defer allocator.free(encoded);
    try std.testing.expect(std.mem.indexOf(u8, encoded, "\\001\\002") != null);
    var decoded = try decodeFileDescriptorProto(allocator, encoded);
    defer decoded.deinit();
    const msg = decoded.findMessage("Defaults").?;
    try std.testing.expectEqual(@as(i64, 42), msg.findField("count").?.default_value.?.integer);
    try std.testing.expect(msg.findField("enabled").?.default_value.?.boolean);
    try std.testing.expectEqual(@as(f64, 1.5), msg.findField("ratio").?.default_value.?.float);
    try std.testing.expectEqualSlices(u8, "anon", msg.findField("name").?.default_value.?.string);
    try std.testing.expectEqualSlices(u8, &.{ 0x01, 0x02 }, msg.findField("raw").?.default_value.?.string);
}

test "descriptor decodes bytes defaults from C escapes" {
    const allocator = std.testing.allocator;
    var field = wire.Writer.init(allocator);
    defer field.deinit();
    try field.writeString(1, "raw");
    try field.writeInt32(3, 1);
    try field.writeInt32(4, 1);
    try field.writeInt32(5, 12);
    try field.writeString(7, "\\001\\x02\\n\\\\\\\"");
    var message = wire.Writer.init(allocator);
    defer message.deinit();
    try message.writeString(1, "Defaults");
    try message.writeMessage(2, field.slice());
    var file = wire.Writer.init(allocator);
    defer file.deinit();
    try file.writeString(1, "bytes-default.proto");
    try file.writeMessage(4, message.slice());

    var decoded = try decodeFileDescriptorProto(allocator, file.slice());
    defer decoded.deinit();
    const raw = decoded.findMessage("Defaults").?.findField("raw").?.default_value.?.string;
    try std.testing.expectEqualSlices(u8, &.{ 0x01, 0x02, '\n', '\\', '"' }, raw);
}

test "descriptor rejects invalid decoded field defaults" {
    const allocator = std.testing.allocator;
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "id");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 5);
        try field.writeString(7, "not-int");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-int-default.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "id");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 13);
        try field.writeString(7, "-1");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-uint-default.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "enabled");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 8);
        try field.writeString(7, "TRUE");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-bool-default.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "ids");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 3);
        try field.writeInt32(5, 5);
        try field.writeString(7, "1");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-repeated-default.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "child");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 11);
        try field.writeString(6, ".Child");
        try field.writeString(7, "x");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-message-default.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "id");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 5);
        try field.writeString(7, "1");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-proto3-default.proto");
        try file.writeString(12, "proto3");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "raw");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 12);
        try field.writeString(7, "\\x");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-bytes-default.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var value = wire.Writer.init(allocator);
        defer value.deinit();
        try value.writeString(1, "ZERO");
        try value.writeInt32(2, 0);
        var enumeration = wire.Writer.init(allocator);
        defer enumeration.deinit();
        try enumeration.writeString(1, "Kind");
        try enumeration.writeMessage(2, value.slice());
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "kind");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 14);
        try field.writeString(6, ".Kind");
        try field.writeString(7, "MISSING");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-enum-default.proto");
        try file.writeMessage(5, enumeration.slice());
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
}

test "descriptor preserves proto2 group fields and nested group messages" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Parent {
        \\  optional group Legacy = 1 { optional int32 id = 2; }
        \\  repeated group Items = 3 { optional string name = 4; }
        \\}
    );
    defer file.deinit();

    const encoded = try encodeFileDescriptorProto(allocator, &file, "groups.proto");
    defer allocator.free(encoded);
    var decoded = try decodeFileDescriptorProto(allocator, encoded);
    defer decoded.deinit();

    const parent = decoded.findMessage("Parent").?;
    const legacy = parent.findField("Legacy").?;
    try std.testing.expect(legacy.kind == .group);
    try std.testing.expectEqualStrings("Legacy", legacy.kind.group);
    try std.testing.expectEqual(schema.Cardinality.optional, legacy.cardinality);
    const items = parent.findField("Items").?;
    try std.testing.expect(items.kind == .group);
    try std.testing.expectEqualStrings("Items", items.kind.group);
    try std.testing.expectEqual(schema.Cardinality.repeated, items.cardinality);

    const legacy_msg = parent.findMessage("Legacy").?;
    try std.testing.expect(legacy_msg.findField("id").?.kind == .scalar);
    try std.testing.expectEqual(schema.ScalarType.int32, legacy_msg.findField("id").?.kind.scalar);
    const items_msg = parent.findMessage("Items").?;
    try std.testing.expect(items_msg.findField("name").?.kind == .scalar);
    try std.testing.expectEqual(schema.ScalarType.string, items_msg.findField("name").?.kind.scalar);
}

test "descriptor rejects legacy group fields under editions" {
    const allocator = std.testing.allocator;
    var field = wire.Writer.init(allocator);
    defer field.deinit();
    try field.writeString(1, "Legacy");
    try field.writeInt32(3, 1);
    try field.writeInt32(4, 1);
    try field.writeInt32(5, 10);
    try field.writeString(6, ".Bad.Legacy");
    var message = wire.Writer.init(allocator);
    defer message.deinit();
    try message.writeString(1, "Bad");
    try message.writeMessage(2, field.slice());
    var file = wire.Writer.init(allocator);
    defer file.deinit();
    try file.writeString(1, "editions-group.proto");
    try file.writeString(12, "editions");
    try file.writeInt32(14, @intFromEnum(schema.Edition.edition_2023));
    try file.writeMessage(4, message.slice());
    try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
}

test "descriptor encodes enum defaults using enum value names" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\enum Kind { UNKNOWN = 0; ADMIN = 7; }
        \\message Defaults { optional Kind kind = 1 [default = ADMIN]; }
    );
    defer file.deinit();
    const field = file.findMessage("Defaults").?.findField("kind").?;
    const default_text = try defaultValueText(allocator, &file, field.kind, field.default_value.?);
    defer allocator.free(default_text);
    try std.testing.expectEqualStrings("ADMIN", default_text);

    const encoded = try encodeFileDescriptorProto(allocator, &file, "enum-default.proto");
    defer allocator.free(encoded);
    var decoded = try decodeFileDescriptorProto(allocator, encoded);
    defer decoded.deinit();
    try std.testing.expectEqual(@as(i64, 7), decoded.findMessage("Defaults").?.findField("kind").?.default_value.?.integer);
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

test "descriptor encodes and decodes FeatureSetDefaults" {
    const allocator = std.testing.allocator;
    var defaults = schema.FeatureSetDefaults{};
    defer defaults.deinit(allocator);
    try defaults.defaults.append(allocator, .{
        .edition = .legacy,
        .overridable_features = schema.FeatureSet.defaults(.proto2),
        .fixed_features = .{ .enforce_naming_style = .style_legacy },
    });
    try defaults.defaults.append(allocator, .{
        .edition = .edition_2023,
        .overridable_features = schema.FeatureSet.defaults(.editions),
        .fixed_features = .{ .json_format = .allow },
    });
    defaults.minimum_edition = .legacy;
    defaults.maximum_edition = .edition_2026;

    const bytes = try encodeFeatureSetDefaults(allocator, &defaults);
    defer allocator.free(bytes);
    var decoded = try decodeFeatureSetDefaults(allocator, bytes);
    defer decoded.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), decoded.defaults.items.len);
    try std.testing.expectEqual(schema.Edition.legacy, decoded.defaults.items[0].edition);
    try std.testing.expectEqual(schema.FeatureSet.EnumType.closed, decoded.defaults.items[0].overridable_features.?.enum_type);
    try std.testing.expectEqual(schema.FeatureSet.RepeatedFieldEncoding.expanded, decoded.defaults.items[0].overridable_features.?.repeated_field_encoding);
    try std.testing.expectEqual(schema.FeatureSet.EnforceNamingStyle.style_legacy, decoded.defaults.items[0].fixed_features.?.enforce_naming_style);
    try std.testing.expectEqual(schema.Edition.edition_2023, decoded.defaults.items[1].edition);
    try std.testing.expectEqual(schema.FeatureSet.EnumType.open, decoded.defaults.items[1].overridable_features.?.enum_type);
    try std.testing.expectEqual(schema.FeatureSet.JsonFormat.allow, decoded.defaults.items[1].fixed_features.?.json_format);
    try std.testing.expectEqual(schema.Edition.legacy, decoded.minimum_edition.?);
    try std.testing.expectEqual(schema.Edition.edition_2026, decoded.maximum_edition.?);
}

test "descriptor rejects invalid FeatureSetDefaults" {
    const allocator = std.testing.allocator;
    {
        var entry = wire.Writer.init(allocator);
        defer entry.deinit();
        try entry.writeInt32(3, @intFromEnum(schema.Edition.edition_2023));
        var writer = wire.Writer.init(allocator);
        defer writer.deinit();
        try writer.writeMessage(1, entry.slice());
        try writer.writeMessage(1, entry.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFeatureSetDefaults(allocator, writer.slice()));
    }
    {
        var writer = wire.Writer.init(allocator);
        defer writer.deinit();
        try writer.writeInt32(4, @intFromEnum(schema.Edition.edition_2026));
        try writer.writeInt32(5, @intFromEnum(schema.Edition.edition_2023));
        try std.testing.expectError(error.InvalidFieldType, decodeFeatureSetDefaults(allocator, writer.slice()));
    }
    {
        var writer = wire.Writer.init(allocator);
        defer writer.deinit();
        try writer.writeInt32(4, @intFromEnum(schema.Edition.unknown));
        try std.testing.expectError(error.InvalidFieldType, decodeFeatureSetDefaults(allocator, writer.slice()));
    }
    {
        var writer = wire.Writer.init(allocator);
        defer writer.deinit();
        try writer.writeInt32(5, @intFromEnum(schema.Edition.unknown));
        try std.testing.expectError(error.InvalidFieldType, decodeFeatureSetDefaults(allocator, writer.slice()));
    }
}

test "descriptor rejects invalid decoded FeatureSet enum values" {
    const allocator = std.testing.allocator;
    inline for (.{
        .{ 1, 99, "bad-field-presence-feature.proto" },
        .{ 2, 99, "bad-enum-type-feature.proto" },
        .{ 3, 99, "bad-repeated-encoding-feature.proto" },
        .{ 4, 1, "bad-utf8-validation-feature.proto" },
        .{ 5, 99, "bad-message-encoding-feature.proto" },
        .{ 6, 99, "bad-json-format-feature.proto" },
        .{ 7, 99, "bad-naming-style-feature.proto" },
        .{ 8, 99, "bad-visibility-feature.proto" },
        .{ 9, 99, "bad-proto-limits-feature.proto" },
    }) |case| {
        var features = wire.Writer.init(allocator);
        defer features.deinit();
        try features.writeInt32(case[0], case[1]);
        var options = wire.Writer.init(allocator);
        defer options.deinit();
        try options.writeMessage(50, features.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, case[2]);
        try file.writeMessage(8, options.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
}

test "descriptor rejects invalid synthetic map entry key type" {
    const allocator = std.testing.allocator;
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto3);
        var msg = schema.MessageDescriptor{ .name = "Bad" };
        try msg.fields.append(allocator, .{ .name = "bad", .number = 1, .cardinality = .repeated, .kind = .{ .message = "Bad.BadEntry" } });
        var entry = schema.MessageDescriptor{ .name = "BadEntry", .map_entry = true };
        try entry.fields.append(allocator, .{ .name = "key", .number = 1, .kind = .{ .scalar = .bytes } });
        try entry.fields.append(allocator, .{ .name = "value", .number = 2, .kind = .{ .scalar = .int32 } });
        try msg.messages.append(allocator, entry);
        try file.messages.append(allocator, msg);

        const bytes = try encodeFileDescriptorProto(allocator, &file, "bad.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto3);
        var msg = schema.MessageDescriptor{ .name = "Bad" };
        try msg.fields.append(allocator, .{ .name = "bad", .number = 1, .cardinality = .repeated, .kind = .{ .message = "Bad.BadEntry" } });
        var entry = schema.MessageDescriptor{ .name = "BadEntry", .map_entry = true };
        try entry.fields.append(allocator, .{ .name = "key", .number = 1, .cardinality = .repeated, .kind = .{ .scalar = .string } });
        try entry.fields.append(allocator, .{ .name = "value", .number = 2, .kind = .{ .scalar = .int32 } });
        try msg.messages.append(allocator, entry);
        try file.messages.append(allocator, msg);

        const bytes = try encodeFileDescriptorProto(allocator, &file, "bad-map-label.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto3);
        var msg = schema.MessageDescriptor{ .name = "Bad" };
        try msg.fields.append(allocator, .{ .name = "bad", .number = 1, .cardinality = .repeated, .kind = .{ .message = "Bad.BadEntry" } });
        var entry = schema.MessageDescriptor{ .name = "BadEntry", .map_entry = true };
        try entry.fields.append(allocator, .{ .name = "key", .number = 1, .kind = .{ .scalar = .string } });
        try entry.fields.append(allocator, .{ .name = "value", .number = 2, .kind = .{ .scalar = .int32 } });
        try entry.messages.append(allocator, .{ .name = "Extra" });
        try msg.messages.append(allocator, entry);
        try file.messages.append(allocator, msg);

        const bytes = try encodeFileDescriptorProto(allocator, &file, "bad-map-extra.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto3);
        var msg = schema.MessageDescriptor{ .name = "Bad" };
        try msg.fields.append(allocator, .{ .name = "wrong_name", .number = 1, .cardinality = .repeated, .kind = .{ .message = "Bad.BadEntry" } });
        var entry = schema.MessageDescriptor{ .name = "BadEntry", .map_entry = true };
        try entry.fields.append(allocator, .{ .name = "key", .number = 1, .kind = .{ .scalar = .string } });
        try entry.fields.append(allocator, .{ .name = "value", .number = 2, .kind = .{ .scalar = .int32 } });
        try msg.messages.append(allocator, entry);
        try file.messages.append(allocator, msg);

        const bytes = try encodeFileDescriptorProto(allocator, &file, "bad-map-entry-name.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto3);
        var entry = schema.MessageDescriptor{ .name = "TopEntry", .map_entry = true };
        try entry.fields.append(allocator, .{ .name = "key", .number = 1, .kind = .{ .scalar = .string } });
        try entry.fields.append(allocator, .{ .name = "value", .number = 2, .kind = .{ .scalar = .int32 } });
        try file.messages.append(allocator, entry);

        const bytes = try encodeFileDescriptorProto(allocator, &file, "top-map-entry.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
}

test "descriptor preserves non map nested Entry messages" {
    const allocator = std.testing.allocator;
    var file = schema.FileDescriptor.init(allocator);
    defer file.deinit();
    file.setSyntax(.proto3);
    var host = schema.MessageDescriptor{ .name = "Host" };
    try host.fields.append(allocator, .{ .name = "entry", .number = 1, .cardinality = .optional, .kind = .{ .message = "Host.Entry" } });
    var entry = schema.MessageDescriptor{ .name = "Entry" };
    try entry.fields.append(allocator, .{ .name = "key", .number = 1, .kind = .{ .scalar = .string } });
    try entry.fields.append(allocator, .{ .name = "value", .number = 2, .kind = .{ .scalar = .int32 } });
    try host.messages.append(allocator, entry);
    try file.messages.append(allocator, host);

    const bytes = try encodeFileDescriptorProto(allocator, &file, "entry.proto");
    defer allocator.free(bytes);
    var decoded = try decodeFileDescriptorProto(allocator, bytes);
    defer decoded.deinit();
    const decoded_host = decoded.findMessage("Host").?;
    try std.testing.expect(decoded_host.findField("entry").?.kind == .message);
    try std.testing.expect(decoded_host.findMessage("Entry") != null);
}

test "descriptor rejects invalid field labels" {
    const allocator = std.testing.allocator;
    var field = wire.Writer.init(allocator);
    defer field.deinit();
    try field.writeString(1, "bad");
    try field.writeInt32(3, 1);
    try field.writeInt32(4, 99);
    try field.writeInt32(5, 5);

    var message = wire.Writer.init(allocator);
    defer message.deinit();
    try message.writeString(1, "Bad");
    try message.writeMessage(2, field.slice());

    var file = wire.Writer.init(allocator);
    defer file.deinit();
    try file.writeString(1, "bad-label.proto");
    try file.writeMessage(4, message.slice());
    try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
}

test "descriptor rejects invalid decoded packed options" {
    const allocator = std.testing.allocator;
    inline for (.{
        .{ 1, 5, "optional-packed.proto", "proto2" },
        .{ 3, 9, "string-packed.proto", "proto2" },
        .{ 3, 5, "editions-packed.proto", "editions" },
    }) |case| {
        var options = wire.Writer.init(allocator);
        defer options.deinit();
        try options.writeBool(2, true);
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "bad");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, case[0]);
        try field.writeInt32(5, case[1]);
        try field.writeMessage(8, options.slice());

        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());

        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, case[2]);
        try file.writeString(12, case[3]);
        if (std.mem.eql(u8, case[3], "editions")) try file.writeInt32(14, @intFromEnum(schema.Edition.edition_2023));
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
}

test "descriptor rejects invalid decoded field option applicability" {
    const allocator = std.testing.allocator;
    inline for (.{ .{ 6, "bad-jstype.proto" }, .{ 5, "bad-lazy.proto" } }) |case| {
        var options = wire.Writer.init(allocator);
        defer options.deinit();
        if (case[0] == 6) {
            try options.writeInt32(6, 1);
        } else {
            try options.writeBool(5, true);
        }
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "id");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 5);
        try field.writeMessage(8, options.slice());
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, case[1]);
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var options = wire.Writer.init(allocator);
        defer options.deinit();
        try options.writeInt32(1, 1);
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "data");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 12);
        try field.writeMessage(8, options.slice());
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-edition-ctype.proto");
        try file.writeString(12, "editions");
        try file.writeInt32(14, @intFromEnum(schema.Edition.edition_2024));
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var options = wire.Writer.init(allocator);
        defer options.deinit();
        try options.writeBool(15, true);
        var host = wire.Writer.init(allocator);
        defer host.deinit();
        try host.writeString(1, "Host");
        var range = wire.Writer.init(allocator);
        defer range.deinit();
        try range.writeInt32(1, 100);
        try range.writeInt32(2, 200);
        try host.writeMessage(5, range.slice());
        var ext = wire.Writer.init(allocator);
        defer ext.deinit();
        try ext.writeString(1, "Ext");
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "ext");
        try field.writeString(2, ".Host");
        try field.writeInt32(3, 100);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 11);
        try field.writeString(6, ".Ext");
        try field.writeMessage(8, options.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-unverified-lazy-extension.proto");
        try file.writeMessage(4, host.slice());
        try file.writeMessage(4, ext.slice());
        try file.writeMessage(7, field.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
}

test "descriptor rejects missing type names for message enum and group fields" {
    const allocator = std.testing.allocator;
    inline for (.{ 10, 11, 14 }) |field_type| {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "bad");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, field_type);

        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());

        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-type-name.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
}

test "descriptor rejects invalid field numbers" {
    const allocator = std.testing.allocator;
    inline for (.{ 0, -1, 19000 }) |bad_number| {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "bad");
        try field.writeInt32(3, bad_number);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 5);

        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());

        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-number.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldNumber, decodeFileDescriptorProto(allocator, file.slice()));
    }
}

test "descriptor decoded schema owns descriptor bytes" {
    const allocator = std.testing.allocator;
    const source =
        \\syntax = "proto2";
        \\package own;
        \\message Owned { optional string value = 1; }
    ;
    var file = try @import("parser.zig").Parser.parse(allocator, source);
    defer file.deinit();
    var bytes = try encodeFileDescriptorProto(allocator, &file, "owned.proto");
    var decoded = try decodeFileDescriptorProto(allocator, bytes);
    allocator.free(bytes);
    bytes = &.{};
    defer decoded.deinit();

    try std.testing.expectEqualStrings("own", decoded.package);
    try std.testing.expectEqualStrings("Owned", decoded.findMessage("Owned").?.name);
    try std.testing.expectEqualStrings("value", decoded.findMessage("Owned").?.findField("value").?.name);
}

const ExpectedNamePart = struct {
    name: []const u8,
    is_extension: bool,
};

fn expectFirstFileOptionNameParts(file_bytes: []const u8, expected: []const ExpectedNamePart) !void {
    var file_reader = wire.Reader.init(file_bytes);
    while (try file_reader.nextTag()) |file_tag| {
        if (file_tag.number == 8) {
            var options_reader = wire.Reader.init(try file_reader.readBytes());
            while (try options_reader.nextTag()) |options_tag| {
                if (options_tag.number == 999) {
                    var option_reader = wire.Reader.init(try options_reader.readBytes());
                    var index: usize = 0;
                    while (try option_reader.nextTag()) |option_tag| {
                        if (option_tag.number == 2) {
                            try std.testing.expect(index < expected.len);
                            const actual = try readTestNamePart(try option_reader.readBytes());
                            try std.testing.expectEqualStrings(expected[index].name, actual.name);
                            try std.testing.expectEqual(expected[index].is_extension, actual.is_extension);
                            index += 1;
                        } else try option_reader.skipValue(option_tag);
                    }
                    try std.testing.expectEqual(expected.len, index);
                    return;
                } else try options_reader.skipValue(options_tag);
            }
        } else try file_reader.skipValue(file_tag);
    }
    return error.TestUnexpectedResult;
}

fn readTestNamePart(bytes: []const u8) !ExpectedNamePart {
    var part = ExpectedNamePart{ .name = "", .is_extension = false };
    var reader = wire.Reader.init(bytes);
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            1 => part.name = try reader.readBytes(),
            2 => part.is_extension = try reader.readBool(),
            else => try reader.skipValue(tag),
        }
    }
    return part;
}

test "descriptor preserves custom options as uninterpreted options" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\option (demo.file_opt).child = "file-value";
        \\message M { optional int32 id = 1 [(demo.field_opt).nested.leaf = 123]; }
    );
    defer file.deinit();
    const bytes = try encodeFileDescriptorProto(allocator, &file, "custom.proto");
    defer allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "demo.file_opt") != null);
    try expectFirstFileOptionNameParts(bytes, &.{
        .{ .name = "demo.file_opt", .is_extension = true },
        .{ .name = "child", .is_extension = false },
    });
    try std.testing.expect(std.mem.indexOf(u8, bytes, "file-value") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "demo.field_opt") != null);
}

test "descriptor decodes uninterpreted options" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\option (demo.file_opt).child = "file-value";
        \\message M { optional int32 id = 1 [(demo.field_opt).nested.leaf = 123]; }
    );
    defer file.deinit();
    const bytes = try encodeFileDescriptorProto(allocator, &file, "custom.proto");
    defer allocator.free(bytes);
    var decoded = try decodeFileDescriptorProto(allocator, bytes);
    defer decoded.deinit();
    try std.testing.expectEqualStrings("(demo.file_opt).child", decoded.options.items[0].name);
    try std.testing.expectEqualSlices(u8, "file-value", decoded.options.items[0].value.string);
    const field = decoded.findMessage("M").?.findField("id").?;
    try std.testing.expectEqualStrings("(demo.field_opt).nested.leaf", field.options.items[0].name);
    try std.testing.expectEqual(@as(i64, 123), field.options.items[0].value.integer);
}

test "descriptor round-trips uninterpreted option value kinds" {
    const allocator = std.testing.allocator;
    var file = schema.FileDescriptor.init(allocator);
    defer file.deinit();
    file.setSyntax(.proto2);
    try file.options.append(allocator, .{ .name = "(demo.bool_opt)", .value = .{ .boolean = true } });
    try file.options.append(allocator, .{ .name = "(demo.neg_opt)", .value = .{ .integer = -7 } });
    try file.options.append(allocator, .{ .name = "(demo.float_opt)", .value = .{ .float = 1.5 } });
    try file.options.append(allocator, .{ .name = "(demo.aggregate_opt)", .value = .{ .aggregate = "{ enabled: true count: 2 }" } });
    var message = schema.MessageDescriptor{ .name = "M" };
    try message.fields.append(allocator, .{ .name = "id", .number = 1, .cardinality = .optional, .kind = .{ .scalar = .int32 } });
    try file.messages.append(allocator, message);

    const bytes = try encodeFileDescriptorProto(allocator, &file, "option-values.proto");
    defer allocator.free(bytes);
    var decoded = try decodeFileDescriptorProto(allocator, bytes);
    defer decoded.deinit();
    try std.testing.expectEqual(@as(usize, 4), decoded.options.items.len);
    try std.testing.expectEqualStrings("(demo.bool_opt)", decoded.options.items[0].name);
    try std.testing.expectEqualStrings("true", decoded.options.items[0].value.identifier);
    try std.testing.expectEqualStrings("(demo.neg_opt)", decoded.options.items[1].name);
    try std.testing.expectEqual(@as(i64, -7), decoded.options.items[1].value.integer);
    try std.testing.expectEqualStrings("(demo.float_opt)", decoded.options.items[2].name);
    try std.testing.expectEqual(@as(f64, 1.5), decoded.options.items[2].value.float);
    try std.testing.expectEqualStrings("(demo.aggregate_opt)", decoded.options.items[3].name);
    try std.testing.expectEqualStrings("{ enabled: true count: 2 }", decoded.options.items[3].value.aggregate);
}

test "descriptor preserves import dependency kinds" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\import public "public.proto";
        \\import weak "weak.proto";
        \\import option "options.proto";
        \\message M {}
    );
    defer file.deinit();
    const bytes = try encodeFileDescriptorProto(allocator, &file, "imports.proto");
    defer allocator.free(bytes);
    var decoded = try decodeFileDescriptorProto(allocator, bytes);
    defer decoded.deinit();
    try std.testing.expectEqual(schema.Import.Kind.public, decoded.imports.items[0].kind);
    try std.testing.expectEqual(schema.Import.Kind.weak, decoded.imports.items[1].kind);
    try std.testing.expectEqual(schema.Import.Kind.option, decoded.imports.items[2].kind);
}

test "descriptor encodes proto3 optional synthetic oneof" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\message Child {}
        \\message M { optional int32 value = 1; optional Child child = 2; }
    );
    defer file.deinit();
    const bytes = try encodeFileDescriptorProto(allocator, &file, "optional.proto");
    defer allocator.free(bytes);
    var decoded = try decodeFileDescriptorProto(allocator, bytes);
    defer decoded.deinit();
    const msg = decoded.findMessage("M").?;
    try std.testing.expectEqual(@as(usize, 2), msg.oneofs.items.len);
    try std.testing.expectEqualStrings("_value", msg.oneofs.items[0].name);
    try std.testing.expectEqualStrings("_value", msg.findField("value").?.oneof_name.?);
    try std.testing.expect(msg.findField("value").?.proto3_optional);
    try std.testing.expectEqualStrings("_child", msg.oneofs.items[1].name);
    try std.testing.expectEqualStrings("_child", msg.findField("child").?.oneof_name.?);
    try std.testing.expect(msg.findField("child").?.proto3_optional);
    try std.testing.expect(msg.findField("child").?.kind == .message);
}

test "descriptor rejects invalid oneof descriptors and indexes" {
    const allocator = std.testing.allocator;
    {
        var oneof = wire.Writer.init(allocator);
        defer oneof.deinit();
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(8, oneof.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-oneof.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var oneof = wire.Writer.init(allocator);
        defer oneof.deinit();
        try oneof.writeString(1, "pick");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(8, oneof.slice());
        try message.writeMessage(8, oneof.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "dup-oneof.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var oneof = wire.Writer.init(allocator);
        defer oneof.deinit();
        try oneof.writeString(1, "empty");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(8, oneof.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "empty-oneof.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "name");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 9);
        try field.writeInt32(9, 1);
        var oneof = wire.Writer.init(allocator);
        defer oneof.deinit();
        try oneof.writeString(1, "pick");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        try message.writeMessage(8, oneof.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-oneof-index.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "value");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 5);
        try field.writeBool(17, true);
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-proto3-optional.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var optional_field = wire.Writer.init(allocator);
        defer optional_field.deinit();
        try optional_field.writeString(1, "value");
        try optional_field.writeInt32(3, 1);
        try optional_field.writeInt32(4, 1);
        try optional_field.writeInt32(5, 5);
        try optional_field.writeInt32(9, 0);
        try optional_field.writeBool(17, true);
        var other_field = wire.Writer.init(allocator);
        defer other_field.deinit();
        try other_field.writeString(1, "other");
        try other_field.writeInt32(3, 2);
        try other_field.writeInt32(4, 1);
        try other_field.writeInt32(5, 5);
        try other_field.writeInt32(9, 0);
        var oneof = wire.Writer.init(allocator);
        defer oneof.deinit();
        try oneof.writeString(1, "_value");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, optional_field.slice());
        try message.writeMessage(2, other_field.slice());
        try message.writeMessage(8, oneof.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-proto3-optional-oneof.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "value");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 2);
        try field.writeInt32(5, 5);
        try field.writeInt32(9, 0);
        try field.writeBool(17, true);
        var oneof = wire.Writer.init(allocator);
        defer oneof.deinit();
        try oneof.writeString(1, "_value");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        try message.writeMessage(8, oneof.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-proto3-optional-required.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "ids");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 3);
        try field.writeInt32(5, 5);
        try field.writeInt32(9, 0);
        var oneof = wire.Writer.init(allocator);
        defer oneof.deinit();
        try oneof.writeString(1, "pick");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        try message.writeMessage(8, oneof.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-oneof-repeated.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "Legacy");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 10);
        try field.writeString(6, ".Bad.Legacy");
        try field.writeInt32(9, 0);
        var oneof = wire.Writer.init(allocator);
        defer oneof.deinit();
        try oneof.writeString(1, "pick");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        try message.writeMessage(8, oneof.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-oneof-group.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "child");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 11);
        try field.writeString(6, ".Child");
        try field.writeInt32(9, 0);
        try field.writeBool(17, true);
        var oneof = wire.Writer.init(allocator);
        defer oneof.deinit();
        try oneof.writeString(1, "_child");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        try message.writeMessage(8, oneof.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-proto2-proto3-optional-message.proto");
        try file.writeString(12, "proto2");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "value");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 5);
        try field.writeInt32(9, 0);
        try field.writeBool(17, true);
        var oneof = wire.Writer.init(allocator);
        defer oneof.deinit();
        try oneof.writeString(1, "_value");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        try message.writeMessage(8, oneof.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-proto2-proto3-optional.proto");
        try file.writeString(12, "proto2");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var optional_field = wire.Writer.init(allocator);
        defer optional_field.deinit();
        try optional_field.writeString(1, "value");
        try optional_field.writeInt32(3, 1);
        try optional_field.writeInt32(4, 1);
        try optional_field.writeInt32(5, 5);
        try optional_field.writeInt32(9, 0);
        try optional_field.writeBool(17, true);
        var real_field = wire.Writer.init(allocator);
        defer real_field.deinit();
        try real_field.writeString(1, "name");
        try real_field.writeInt32(3, 2);
        try real_field.writeInt32(4, 1);
        try real_field.writeInt32(5, 9);
        try real_field.writeInt32(9, 1);
        var synthetic = wire.Writer.init(allocator);
        defer synthetic.deinit();
        try synthetic.writeString(1, "_value");
        var real_oneof = wire.Writer.init(allocator);
        defer real_oneof.deinit();
        try real_oneof.writeString(1, "pick");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, optional_field.slice());
        try message.writeMessage(2, real_field.slice());
        try message.writeMessage(8, synthetic.slice());
        try message.writeMessage(8, real_oneof.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-synthetic-oneof-order.proto");
        try file.writeString(12, "proto3");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
}

test "descriptor rejects invalid message descriptors" {
    const allocator = std.testing.allocator;
    {
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-message.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "same");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 5);
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        try message.writeMessage(2, field.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "dup-field.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var nested = wire.Writer.init(allocator);
        defer nested.deinit();
        try nested.writeString(1, "Item");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(3, nested.slice());
        try message.writeMessage(3, nested.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "dup-nested.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
}

test "descriptor rejects invalid decoded json names" {
    const allocator = std.testing.allocator;
    {
        var first = wire.Writer.init(allocator);
        defer first.deinit();
        try first.writeString(1, "foo_bar");
        try first.writeInt32(3, 1);
        try first.writeInt32(4, 1);
        try first.writeInt32(5, 5);
        var second = wire.Writer.init(allocator);
        defer second.deinit();
        try second.writeString(1, "fooBar");
        try second.writeInt32(3, 2);
        try second.writeInt32(4, 1);
        try second.writeInt32(5, 5);
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, first.slice());
        try message.writeMessage(2, second.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "default-json-name-conflict.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var first = wire.Writer.init(allocator);
        defer first.deinit();
        try first.writeString(1, "foo");
        try first.writeInt32(3, 1);
        try first.writeInt32(4, 1);
        try first.writeInt32(5, 5);
        try first.writeString(10, "sameName");
        var second = wire.Writer.init(allocator);
        defer second.deinit();
        try second.writeString(1, "bar");
        try second.writeInt32(3, 2);
        try second.writeInt32(4, 1);
        try second.writeInt32(5, 5);
        try second.writeString(10, "sameName");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, first.slice());
        try message.writeMessage(2, second.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "custom-json-name-conflict.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var first = wire.Writer.init(allocator);
        defer first.deinit();
        try first.writeString(1, "foo");
        try first.writeInt32(3, 1);
        try first.writeInt32(4, 1);
        try first.writeInt32(5, 5);
        try first.writeString(10, "barBaz");
        var second = wire.Writer.init(allocator);
        defer second.deinit();
        try second.writeString(1, "bar_baz");
        try second.writeInt32(3, 2);
        try second.writeInt32(4, 1);
        try second.writeInt32(5, 5);
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, first.slice());
        try message.writeMessage(2, second.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "custom-default-json-name-conflict.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "foo");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 5);
        try field.writeString(10, "[demo.ext]");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "extension-looking-json-name.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "foo");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 5);
        try field.writeString(10, "has\x00nul");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "nul-json-name.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "ext");
        try field.writeInt32(3, 100);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 5);
        try field.writeString(2, ".Host");
        try field.writeString(10, "customExt");
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "extension-json-name.proto");
        try file.writeMessage(7, field.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
}

test "descriptor rejects duplicate top-level file symbols" {
    const allocator = std.testing.allocator;
    {
        var msg = wire.Writer.init(allocator);
        defer msg.deinit();
        try msg.writeString(1, "Thing");
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "dup-message.proto");
        try file.writeMessage(4, msg.slice());
        try file.writeMessage(4, msg.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var msg = wire.Writer.init(allocator);
        defer msg.deinit();
        try msg.writeString(1, "Thing");
        var enum_value = wire.Writer.init(allocator);
        defer enum_value.deinit();
        try enum_value.writeString(1, "UNKNOWN");
        try enum_value.writeInt32(2, 0);
        var enumeration = wire.Writer.init(allocator);
        defer enumeration.deinit();
        try enumeration.writeString(1, "Thing");
        try enumeration.writeMessage(2, enum_value.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "message-enum-conflict.proto");
        try file.writeMessage(4, msg.slice());
        try file.writeMessage(5, enumeration.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var service = wire.Writer.init(allocator);
        defer service.deinit();
        try service.writeString(1, "Api");
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "dup-service.proto");
        try file.writeMessage(6, service.slice());
        try file.writeMessage(6, service.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
}

test "descriptor rejects invalid reserved ranges" {
    const allocator = std.testing.allocator;
    {
        var range = wire.Writer.init(allocator);
        defer range.deinit();
        try range.writeInt32(1, 10);
        try range.writeInt32(2, 5);
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(9, range.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-reserved.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var value = wire.Writer.init(allocator);
        defer value.deinit();
        try value.writeString(1, "A");
        try value.writeInt32(2, 0);
        var range = wire.Writer.init(allocator);
        defer range.deinit();
        try range.writeInt32(1, 5);
        try range.writeInt32(2, 3);
        var enumeration = wire.Writer.init(allocator);
        defer enumeration.deinit();
        try enumeration.writeString(1, "Bad");
        try enumeration.writeMessage(2, value.slice());
        try enumeration.writeMessage(4, range.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-enum-reserved.proto");
        try file.writeMessage(5, enumeration.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
}

test "descriptor rejects declarations that use reserved fields or enum values" {
    const allocator = std.testing.allocator;
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        var message = schema.MessageDescriptor{ .name = "Bad" };
        try message.reserved_ranges.append(allocator, .{ .start = 1, .end = 3 });
        try message.fields.append(allocator, .{ .name = "hit", .number = 2, .cardinality = .optional, .kind = .{ .scalar = .int32 } });
        try file.messages.append(allocator, message);
        const bytes = try encodeFileDescriptorProto(allocator, &file, "reserved-field.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        var message = schema.MessageDescriptor{ .name = "Bad" };
        try message.reserved_names.append(allocator, "old");
        try message.reserved_names.append(allocator, "old");
        try file.messages.append(allocator, message);
        const bytes = try encodeFileDescriptorProto(allocator, &file, "reserved-name.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        var enumeration = schema.EnumDescriptor{ .name = "Bad" };
        try enumeration.reserved_ranges.append(allocator, .{ .start = 1, .end = 3 });
        try enumeration.values.append(allocator, .{ .name = "HIT", .number = 2 });
        try file.enums.append(allocator, enumeration);
        const bytes = try encodeFileDescriptorProto(allocator, &file, "reserved-enum.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        var enumeration = schema.EnumDescriptor{ .name = "Bad" };
        try enumeration.reserved_names.append(allocator, "OLD");
        try enumeration.values.append(allocator, .{ .name = "OLD", .number = 1 });
        try file.enums.append(allocator, enumeration);
        const bytes = try encodeFileDescriptorProto(allocator, &file, "reserved-enum-name.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
}

test "descriptor rejects invalid extension ranges" {
    const allocator = std.testing.allocator;
    {
        const bytes = try testFileWithExtensionRange(allocator, 100, 50, null);
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        const bytes = try testFileWithExtensionRange(allocator, 100, 200, .{ .number = 10, .full_name = ".demo.bad", .type_name = ".demo.Bad" });
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        const bytes = try testFileWithExtensionRange(allocator, 100, 200, .{ .number = 100, .full_name = ".demo.ext", .type_name = ".demo.Ext" });
        defer allocator.free(bytes);
        var decoded = try decodeFileDescriptorProto(allocator, bytes);
        defer decoded.deinit();
        try std.testing.expectEqual(@as(i64, 100), decoded.findMessage("Host").?.extension_ranges.items[0].start);
    }
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        var message = schema.MessageDescriptor{ .name = "Bad" };
        try message.extension_ranges.append(allocator, .{ .start = 100, .end = 200 });
        try message.fields.append(allocator, .{ .name = "hit", .number = 150, .cardinality = .optional, .kind = .{ .scalar = .int32 } });
        try file.messages.append(allocator, message);
        const bytes = try encodeFileDescriptorProto(allocator, &file, "field-in-extension-range.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        var message = schema.MessageDescriptor{ .name = "Bad" };
        try message.extension_ranges.append(allocator, .{ .start = 100, .end = 200 });
        try message.extension_ranges.append(allocator, .{ .start = 150, .end = 250 });
        try file.messages.append(allocator, message);
        const bytes = try encodeFileDescriptorProto(allocator, &file, "overlap-extension-range.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        var message = schema.MessageDescriptor{ .name = "Bad" };
        try message.extension_ranges.append(allocator, .{ .start = 100, .end = 200 });
        try message.reserved_ranges.append(allocator, .{ .start = 150, .end = 160 });
        try file.messages.append(allocator, message);
        const bytes = try encodeFileDescriptorProto(allocator, &file, "extension-reserved-overlap.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
}

fn testFileWithExtensionRange(allocator: std.mem.Allocator, start: i32, end: i32, declaration: ?schema.ExtensionDeclaration) ![]u8 {
    var range = wire.Writer.init(allocator);
    defer range.deinit();
    try range.writeInt32(1, start);
    try range.writeInt32(2, end);
    if (declaration) |decl| {
        var decl_writer = wire.Writer.init(allocator);
        defer decl_writer.deinit();
        try decl_writer.writeInt32(1, decl.number);
        try decl_writer.writeString(2, decl.full_name);
        try decl_writer.writeString(3, decl.type_name);
        var options = wire.Writer.init(allocator);
        defer options.deinit();
        try options.writeMessage(2, decl_writer.slice());
        try range.writeMessage(3, options.slice());
    }

    var message = wire.Writer.init(allocator);
    defer message.deinit();
    try message.writeString(1, "Host");
    try message.writeMessage(5, range.slice());

    var file = wire.Writer.init(allocator);
    errdefer file.deinit();
    try file.writeString(1, "ext-range-invalid.proto");
    try file.writeString(12, "proto2");
    try file.writeMessage(4, message.slice());
    return try file.toOwnedSlice();
}

test "descriptor rejects invalid file syntax edition and dependency indexes" {
    const allocator = std.testing.allocator;
    {
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-syntax.proto");
        try file.writeString(12, "proto4");
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-edition.proto");
        try file.writeInt32(14, 123456);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "unknown-edition.proto");
        try file.writeInt32(14, @intFromEnum(schema.Edition.unknown));
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "max-edition.proto");
        try file.writeInt32(14, @intFromEnum(schema.Edition.max));
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "proto3-with-edition.proto");
        try file.writeString(12, "proto3");
        try file.writeInt32(14, @intFromEnum(schema.Edition.edition_2023));
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "edition-before-proto3.proto");
        try file.writeInt32(14, @intFromEnum(schema.Edition.edition_2023));
        try file.writeString(12, "proto3");
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "edition-before-syntax.proto");
        try file.writeInt32(14, @intFromEnum(schema.Edition.edition_2024));
        try file.writeString(12, "editions");
        var decoded = try decodeFileDescriptorProto(allocator, file.slice());
        defer decoded.deinit();
        try std.testing.expectEqual(schema.Syntax.editions, decoded.syntax);
        try std.testing.expectEqual(schema.Edition.edition_2024, decoded.edition);
    }
    {
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-public-dep.proto");
        try file.writeString(3, "dep.proto");
        try file.writeInt32(10, 1);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-weak-dep.proto");
        try file.writeString(3, "dep.proto");
        try file.writeInt32(11, -1);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "dup-public-dep.proto");
        try file.writeString(3, "dep.proto");
        try file.writeInt32(10, 0);
        try file.writeInt32(10, 0);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "conflicting-dep-kind.proto");
        try file.writeString(3, "dep.proto");
        try file.writeInt32(10, 0);
        try file.writeInt32(11, 0);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "edition-weak-import.proto");
        try file.writeString(3, "dep.proto");
        try file.writeInt32(11, 0);
        try file.writeString(12, "editions");
        try file.writeInt32(14, @intFromEnum(schema.Edition.edition_2024));
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "empty-import.proto");
        try file.writeString(3, "");
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "dup-import.proto");
        try file.writeString(3, "dep.proto");
        try file.writeString(3, "dep.proto");
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "dup-option-import.proto");
        try file.writeString(3, "dep.proto");
        try file.writeString(15, "dep.proto");
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    inline for (.{ "1bad", "bad..pkg", "bad.", "bad-pkg" }) |bad_package| {
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-package.proto");
        try file.writeString(2, bad_package);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
}

test "descriptor rejects required labels outside proto2 and on extensions" {
    const allocator = std.testing.allocator;
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "id");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 2);
        try field.writeInt32(5, 5);
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "proto3-required.proto");
        try file.writeString(12, "proto3");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "id");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 2);
        try field.writeInt32(5, 5);
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "editions-required.proto");
        try file.writeString(12, "editions");
        try file.writeInt32(14, @intFromEnum(schema.Edition.edition_2023));
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var host = wire.Writer.init(allocator);
        defer host.deinit();
        try host.writeString(1, "Host");
        var range = wire.Writer.init(allocator);
        defer range.deinit();
        try range.writeInt32(1, 100);
        try range.writeInt32(2, 200);
        try host.writeMessage(5, range.slice());
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "bad_ext");
        try field.writeString(2, ".Host");
        try field.writeInt32(3, 100);
        try field.writeInt32(4, 2);
        try field.writeInt32(5, 5);
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "required-extension.proto");
        try file.writeMessage(4, host.slice());
        try file.writeMessage(7, field.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
}

test "descriptor rejects invalid decoded symbol identifiers" {
    const allocator = std.testing.allocator;
    {
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "1Bad");
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-message-name.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "bad-name");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 5);
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-field-name.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "bad.member");
        try field.writeInt32(3, 100);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 5);
        try field.writeString(2, ".pkg.Host");
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-extension-name.proto");
        try file.writeMessage(7, field.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var oneof = wire.Writer.init(allocator);
        defer oneof.deinit();
        try oneof.writeString(1, "bad.oneof");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(8, oneof.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-oneof-name.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var value = wire.Writer.init(allocator);
        defer value.deinit();
        try value.writeString(1, "OK");
        try value.writeInt32(2, 0);
        var enumeration = wire.Writer.init(allocator);
        defer enumeration.deinit();
        try enumeration.writeString(1, "-Bad");
        try enumeration.writeMessage(2, value.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-enum-name.proto");
        try file.writeMessage(5, enumeration.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var value = wire.Writer.init(allocator);
        defer value.deinit();
        try value.writeString(1, "0_VALUE");
        try value.writeInt32(2, 0);
        var enumeration = wire.Writer.init(allocator);
        defer enumeration.deinit();
        try enumeration.writeString(1, "Bad");
        try enumeration.writeMessage(2, value.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-enum-value-name.proto");
        try file.writeMessage(5, enumeration.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var service = wire.Writer.init(allocator);
        defer service.deinit();
        try service.writeString(1, "bad.service");
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-service-name.proto");
        try file.writeMessage(6, service.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var method = wire.Writer.init(allocator);
        defer method.deinit();
        try method.writeString(1, "bad-method");
        try method.writeString(2, ".demo.Req");
        try method.writeString(3, ".demo.Res");
        var service = wire.Writer.init(allocator);
        defer service.deinit();
        try service.writeString(1, "Svc");
        try service.writeMessage(2, method.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-method-name.proto");
        try file.writeMessage(6, service.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
}

test "descriptor rejects invalid decoded type references" {
    const allocator = std.testing.allocator;
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "child");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 11);
        try field.writeString(6, ".demo.Bad-Type");
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-message-type-name.proto");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "ext");
        try field.writeInt32(3, 100);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 5);
        try field.writeString(2, ".demo.Bad-Type");
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-extendee-name.proto");
        try file.writeMessage(7, field.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "ext");
        try field.writeInt32(3, 100);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 5);
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "missing-extendee.proto");
        try file.writeMessage(7, field.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        const bytes = try testFileWithExtensionRange(allocator, 100, 200, .{ .number = 100, .full_name = ".demo.bad-name", .type_name = "int32" });
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        const bytes = try testFileWithExtensionRange(allocator, 100, 200, .{ .number = 100, .full_name = ".demo.good_name", .type_name = ".demo.Bad-Type" });
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        var method = wire.Writer.init(allocator);
        defer method.deinit();
        try method.writeString(1, "Get");
        try method.writeString(2, ".demo.Bad-Type");
        try method.writeString(3, ".demo.Res");
        var service = wire.Writer.init(allocator);
        defer service.deinit();
        try service.writeString(1, "Svc");
        try service.writeMessage(2, method.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-method-input-type.proto");
        try file.writeMessage(6, service.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
}

test "descriptor preserves message and enum custom options" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message M { option (demo.msg_opt) = "m"; optional int32 id = 1; }
        \\enum E { option (demo.enum_opt) = "e"; A = 0; }
    );
    defer file.deinit();
    const bytes = try encodeFileDescriptorProto(allocator, &file, "opts.proto");
    defer allocator.free(bytes);
    var decoded = try decodeFileDescriptorProto(allocator, bytes);
    defer decoded.deinit();
    try std.testing.expectEqualStrings("(demo.msg_opt)", decoded.findMessage("M").?.options.items[0].name);
    try std.testing.expectEqualSlices(u8, "m", decoded.findMessage("M").?.options.items[0].value.string);
    try std.testing.expectEqualStrings("(demo.enum_opt)", decoded.findEnum("E").?.options.items[0].name);
    try std.testing.expectEqualSlices(u8, "e", decoded.findEnum("E").?.options.items[0].value.string);
}

test "descriptor preserves known file options" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\option java_package = "com.example.demo";
        \\option java_outer_classname = "DemoProto";
        \\option optimize_for = CODE_SIZE;
        \\option java_multiple_files = true;
        \\option go_package = "example.com/demo;demopb";
        \\option cc_generic_services = true;
        \\option java_generic_services = true;
        \\option py_generic_services = true;
        \\option java_generate_equals_and_hash = true;
        \\option deprecated = true;
        \\option java_string_check_utf8 = true;
        \\option cc_enable_arenas = true;
        \\option objc_class_prefix = "DEM";
        \\option csharp_namespace = "Example.Demo";
        \\option swift_prefix = "Demo";
        \\option php_class_prefix = "Demo";
        \\option php_namespace = "Example\\Demo";
        \\option php_metadata_namespace = "Example\\Demo\\Metadata";
        \\option ruby_package = "Example::Demo";
        \\message M { optional int32 id = 1; }
    );
    defer file.deinit();
    const bytes = try encodeFileDescriptorProto(allocator, &file, "file-options.proto");
    defer allocator.free(bytes);
    var decoded = try decodeFileDescriptorProto(allocator, bytes);
    defer decoded.deinit();

    try std.testing.expectEqualStrings("com.example.demo", exactOptionString(decoded.options.items, "java_package").?);
    try std.testing.expectEqualStrings("DemoProto", exactOptionString(decoded.options.items, "java_outer_classname").?);
    try std.testing.expectEqual(@as(i32, 2), fileOptimizeMode(decoded.options.items).?);
    try std.testing.expect(exactOptionBool(decoded.options.items, "java_multiple_files").?);
    try std.testing.expectEqualStrings("example.com/demo;demopb", exactOptionString(decoded.options.items, "go_package").?);
    try std.testing.expect(exactOptionBool(decoded.options.items, "cc_generic_services").?);
    try std.testing.expect(exactOptionBool(decoded.options.items, "java_generic_services").?);
    try std.testing.expect(exactOptionBool(decoded.options.items, "py_generic_services").?);
    try std.testing.expect(exactOptionBool(decoded.options.items, "java_generate_equals_and_hash").?);
    try std.testing.expect(exactOptionBool(decoded.options.items, "deprecated").?);
    try std.testing.expect(exactOptionBool(decoded.options.items, "java_string_check_utf8").?);
    try std.testing.expect(exactOptionBool(decoded.options.items, "cc_enable_arenas").?);
    try std.testing.expectEqualStrings("DEM", exactOptionString(decoded.options.items, "objc_class_prefix").?);
    try std.testing.expectEqualStrings("Example.Demo", exactOptionString(decoded.options.items, "csharp_namespace").?);
    try std.testing.expectEqualStrings("Demo", exactOptionString(decoded.options.items, "swift_prefix").?);
    try std.testing.expectEqualStrings("Demo", exactOptionString(decoded.options.items, "php_class_prefix").?);
    try std.testing.expectEqualStrings("Example\\Demo", exactOptionString(decoded.options.items, "php_namespace").?);
    try std.testing.expectEqualStrings("Example\\Demo\\Metadata", exactOptionString(decoded.options.items, "php_metadata_namespace").?);
    try std.testing.expectEqualStrings("Example::Demo", exactOptionString(decoded.options.items, "ruby_package").?);
    try std.testing.expectEqual(@as(usize, 19), decoded.options.items.len);
}

test "descriptor rejects invalid known option enum values" {
    const allocator = std.testing.allocator;
    {
        var options = wire.Writer.init(allocator);
        defer options.deinit();
        try options.writeInt32(9, 99);
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-optimize.proto");
        try file.writeMessage(8, options.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    inline for (.{ .{ 1, "bad-ctype.proto" }, .{ 6, "bad-jstype.proto" }, .{ 17, "bad-retention.proto" }, .{ 19, "bad-target.proto" } }) |case| {
        var options = wire.Writer.init(allocator);
        defer options.deinit();
        try options.writeInt32(case[0], 99);
        var field = wire.Writer.init(allocator);
        defer field.deinit();
        try field.writeString(1, "id");
        try field.writeInt32(3, 1);
        try field.writeInt32(4, 1);
        try field.writeInt32(5, 5);
        try field.writeMessage(8, options.slice());
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Bad");
        try message.writeMessage(2, field.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, case[1]);
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var method_options = wire.Writer.init(allocator);
        defer method_options.deinit();
        try method_options.writeInt32(34, 99);
        var method = wire.Writer.init(allocator);
        defer method.deinit();
        try method.writeString(1, "Do");
        try method.writeString(2, ".Req");
        try method.writeString(3, ".Res");
        try method.writeMessage(4, method_options.slice());
        var service = wire.Writer.init(allocator);
        defer service.deinit();
        try service.writeString(1, "Svc");
        try service.writeMessage(2, method.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-idempotency.proto");
        try file.writeMessage(6, service.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
}

test "descriptor preserves message field and enum known options" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message M {
        \\  option no_standard_descriptor_accessor = true;
        \\  option deprecated = true;
        \\  option deprecated_legacy_json_field_conflicts = true;
        \\  message Child {}
        \\  optional bytes data = 1 [
        \\    ctype = CORD,
        \\    deprecated = true,
        \\    debug_redact = true,
        \\    retention = RETENTION_SOURCE,
        \\    targets = TARGET_TYPE_FIELD,
        \\    targets = TARGET_TYPE_MESSAGE
        \\  ];
        \\  optional Child child = 2 [lazy = true, weak = true, unverified_lazy = true];
        \\  optional int64 big = 3 [jstype = JS_STRING];
        \\}
        \\enum E {
        \\  option allow_alias = true;
        \\  option deprecated = true;
        \\  option deprecated_legacy_json_field_conflicts = true;
        \\  A = 0;
        \\  B = 0;
        \\}
    );
    defer file.deinit();
    const bytes = try encodeFileDescriptorProto(allocator, &file, "known-options.proto");
    defer allocator.free(bytes);
    var decoded = try decodeFileDescriptorProto(allocator, bytes);
    defer decoded.deinit();

    const message_options = decoded.findMessage("M").?.options.items;
    try std.testing.expectEqualStrings("no_standard_descriptor_accessor", message_options[0].name);
    try std.testing.expect(message_options[0].value.boolean);
    try std.testing.expectEqualStrings("deprecated", message_options[1].name);
    try std.testing.expect(message_options[1].value.boolean);
    try std.testing.expectEqualStrings("deprecated_legacy_json_field_conflicts", message_options[2].name);
    try std.testing.expect(message_options[2].value.boolean);

    const field_options = decoded.findMessage("M").?.findField("data").?.options.items;
    try std.testing.expectEqualStrings("ctype", field_options[0].name);
    try std.testing.expectEqual(@as(i64, 1), field_options[0].value.integer);
    try std.testing.expectEqualStrings("deprecated", field_options[1].name);
    try std.testing.expect(field_options[1].value.boolean);
    try std.testing.expectEqualStrings("debug_redact", field_options[2].name);
    try std.testing.expect(field_options[2].value.boolean);
    try std.testing.expectEqualStrings("retention", field_options[3].name);
    try std.testing.expectEqual(@as(i64, 2), field_options[3].value.integer);
    try std.testing.expectEqualStrings("targets", field_options[4].name);
    try std.testing.expectEqual(@as(i64, 4), field_options[4].value.integer);
    try std.testing.expectEqualStrings("targets", field_options[5].name);
    try std.testing.expectEqual(@as(i64, 3), field_options[5].value.integer);

    const child_options = decoded.findMessage("M").?.findField("child").?.options.items;
    try std.testing.expectEqualStrings("lazy", child_options[0].name);
    try std.testing.expect(child_options[0].value.boolean);
    try std.testing.expectEqualStrings("weak", child_options[1].name);
    try std.testing.expect(child_options[1].value.boolean);
    try std.testing.expectEqualStrings("unverified_lazy", child_options[2].name);
    try std.testing.expect(child_options[2].value.boolean);

    const big_options = decoded.findMessage("M").?.findField("big").?.options.items;
    try std.testing.expectEqualStrings("jstype", big_options[0].name);
    try std.testing.expectEqual(@as(i64, 1), big_options[0].value.integer);

    const enum_options = decoded.findEnum("E").?.options.items;
    try std.testing.expectEqualStrings("allow_alias", enum_options[0].name);
    try std.testing.expect(enum_options[0].value.boolean);
    try std.testing.expectEqualStrings("deprecated", enum_options[1].name);
    try std.testing.expect(enum_options[1].value.boolean);
    try std.testing.expectEqualStrings("deprecated_legacy_json_field_conflicts", enum_options[2].name);
    try std.testing.expect(enum_options[2].value.boolean);
}

test "descriptor preserves field edition defaults and feature support" {
    const allocator = std.testing.allocator;
    var file = schema.FileDescriptor.init(allocator);
    defer file.deinit();
    file.name = "features.proto";

    var message = schema.MessageDescriptor{ .name = "FeatureSetLike" };
    var field = schema.FieldDescriptor{
        .name = "field_presence",
        .number = 1,
        .cardinality = .optional,
        .kind = .{ .scalar = .int32 },
        .feature_support = .{
            .edition_introduced = .edition_2023,
            .edition_deprecated = .edition_2024,
            .deprecation_warning = "prefer explicit presence",
            .edition_removed = .edition_2026,
            .removal_error = "field_presence override removed",
        },
    };
    try field.edition_defaults.append(allocator, .{ .edition = .legacy, .value = "EXPLICIT" });
    try field.edition_defaults.append(allocator, .{ .edition = .proto3, .value = "IMPLICIT" });
    try field.edition_defaults.append(allocator, .{ .edition = .edition_2023, .value = "EXPLICIT" });
    try message.fields.append(allocator, field);
    try file.messages.append(allocator, message);

    const bytes = try encodeFileDescriptorProto(allocator, &file, file.name);
    defer allocator.free(bytes);
    var decoded = try decodeFileDescriptorProto(allocator, bytes);
    defer decoded.deinit();

    const decoded_field = decoded.findMessage("FeatureSetLike").?.findField("field_presence").?;
    try std.testing.expectEqual(@as(usize, 3), decoded_field.edition_defaults.items.len);
    try std.testing.expectEqual(schema.Edition.legacy, decoded_field.edition_defaults.items[0].edition);
    try std.testing.expectEqualStrings("EXPLICIT", decoded_field.edition_defaults.items[0].value);
    try std.testing.expectEqual(schema.Edition.proto3, decoded_field.edition_defaults.items[1].edition);
    try std.testing.expectEqualStrings("IMPLICIT", decoded_field.edition_defaults.items[1].value);
    try std.testing.expectEqual(schema.Edition.edition_2023, decoded_field.edition_defaults.items[2].edition);
    try std.testing.expectEqualStrings("EXPLICIT", decoded_field.edition_defaults.items[2].value);
    try std.testing.expectEqual(@as(usize, 0), decoded_field.options.items.len);
    try std.testing.expectEqual(schema.Edition.edition_2023, decoded_field.feature_support.?.edition_introduced.?);
    try std.testing.expectEqual(schema.Edition.edition_2024, decoded_field.feature_support.?.edition_deprecated.?);
    try std.testing.expectEqualStrings("prefer explicit presence", decoded_field.feature_support.?.deprecation_warning);
    try std.testing.expectEqual(schema.Edition.edition_2026, decoded_field.feature_support.?.edition_removed.?);
    try std.testing.expectEqualStrings("field_presence override removed", decoded_field.feature_support.?.removal_error);
}

test "descriptor preserves FeatureSet options across declaration scopes" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\edition = "2023";
        \\option features.json_format = LEGACY_BEST_EFFORT;
        \\message M {
        \\  option features.message_encoding = DELIMITED;
        \\  repeated int32 values = 1 [features.repeated_field_encoding = EXPANDED];
        \\  oneof pick {
        \\    option features.field_presence = EXPLICIT;
        \\    string name = 2;
        \\  }
        \\}
        \\enum E {
        \\  option features.enum_type = CLOSED;
        \\  A = 0 [
        \\    features.enforce_naming_style = STYLE2026,
        \\    feature_support = { edition_removed: EDITION_2026 removal_error: "removed enum value" }
        \\  ];
        \\}
        \\service S {
        \\  option features.enforce_naming_style = STYLE2024;
        \\  rpc Do (M) returns (M) {
        \\    option features.enforce_proto_limits = PROTO_LIMITS2026;
        \\  }
        \\}
    );
    defer file.deinit();

    const bytes = try encodeFileDescriptorProto(allocator, &file, "features-all.proto");
    defer allocator.free(bytes);
    var decoded = try decodeFileDescriptorProto(allocator, bytes);
    defer decoded.deinit();

    try std.testing.expectEqual(schema.Syntax.editions, decoded.syntax);
    try std.testing.expectEqual(schema.FeatureSet.JsonFormat.legacy_best_effort, decoded.features.json_format);
    try std.testing.expectEqual(@as(usize, 0), decoded.options.items.len);

    const message = decoded.findMessage("M").?;
    try std.testing.expectEqual(schema.FeatureSet.MessageEncoding.delimited, message.features.?.message_encoding);
    try std.testing.expectEqual(@as(usize, 0), message.options.items.len);
    const field = message.findField("values").?;
    try std.testing.expectEqual(schema.FeatureSet.RepeatedFieldEncoding.expanded, field.features.?.repeated_field_encoding);
    try std.testing.expect(!field.resolvedPacked(&decoded));
    try std.testing.expectEqual(@as(usize, 0), field.options.items.len);
    try std.testing.expectEqual(schema.FeatureSet.FieldPresence.explicit, message.oneofs.items[0].features.?.field_presence);
    try std.testing.expectEqual(@as(usize, 0), message.oneofs.items[0].options.items.len);

    const enumeration = decoded.findEnum("E").?;
    try std.testing.expectEqual(schema.FeatureSet.EnumType.closed, enumeration.features.?.enum_type);
    try std.testing.expectEqual(@as(usize, 0), enumeration.options.items.len);
    const enum_value = enumeration.values.items[0];
    try std.testing.expectEqual(schema.FeatureSet.EnforceNamingStyle.style2026, enum_value.features.?.enforce_naming_style);
    try std.testing.expectEqual(schema.Edition.edition_2026, enum_value.feature_support.?.edition_removed.?);
    try std.testing.expectEqualStrings("removed enum value", enum_value.feature_support.?.removal_error);
    try std.testing.expectEqual(@as(usize, 0), enum_value.options.items.len);

    const service = decoded.services.items[0];
    try std.testing.expectEqual(schema.FeatureSet.EnforceNamingStyle.style2024, service.features.?.enforce_naming_style);
    try std.testing.expectEqual(@as(usize, 0), service.options.items.len);
    const method = service.methods.items[0];
    try std.testing.expectEqual(schema.FeatureSet.EnforceProtoLimits.proto_limits2026, method.features.?.enforce_proto_limits);
    try std.testing.expectEqual(@as(usize, 0), method.options.items.len);
}

test "descriptor preserves oneof enum value service and method options" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message M {
        \\  oneof pick {
        \\    option (demo.oneof_opt) = "one";
        \\    string name = 1;
        \\  }
        \\}
        \\enum E { A = 0 [deprecated = true, debug_redact = true, (demo.value_opt) = "value"]; }
        \\message Req {}
        \\message Res {}
        \\service S {
        \\  option deprecated = true;
        \\  option (demo.service_opt) = "svc";
        \\  rpc Do (Req) returns (Res) {
        \\    option deprecated = true;
        \\    option idempotency_level = IDEMPOTENT;
        \\    option (demo.method_opt) = "method";
        \\  }
        \\}
    );
    defer file.deinit();
    const bytes = try encodeFileDescriptorProto(allocator, &file, "opts-all.proto");
    defer allocator.free(bytes);
    var decoded = try decodeFileDescriptorProto(allocator, bytes);
    defer decoded.deinit();

    const oneof = decoded.findMessage("M").?.oneofs.items[0];
    try std.testing.expectEqualStrings("(demo.oneof_opt)", oneof.options.items[0].name);
    try std.testing.expectEqualSlices(u8, "one", oneof.options.items[0].value.string);

    const enum_value = decoded.findEnum("E").?.values.items[0];
    try std.testing.expectEqualStrings("deprecated", enum_value.options.items[0].name);
    try std.testing.expect(enum_value.options.items[0].value.boolean);
    try std.testing.expectEqualStrings("debug_redact", enum_value.options.items[1].name);
    try std.testing.expect(enum_value.options.items[1].value.boolean);
    try std.testing.expectEqualStrings("(demo.value_opt)", enum_value.options.items[2].name);
    try std.testing.expectEqualSlices(u8, "value", enum_value.options.items[2].value.string);

    const service = decoded.services.items[0];
    try std.testing.expectEqualStrings("deprecated", service.options.items[0].name);
    try std.testing.expect(service.options.items[0].value.boolean);
    try std.testing.expectEqualStrings("(demo.service_opt)", service.options.items[1].name);
    try std.testing.expectEqualSlices(u8, "svc", service.options.items[1].value.string);

    const method = service.methods.items[0];
    try std.testing.expectEqualStrings("deprecated", method.options.items[0].name);
    try std.testing.expect(method.options.items[0].value.boolean);
    try std.testing.expectEqualStrings("idempotency_level", method.options.items[1].name);
    try std.testing.expectEqual(@as(i64, 2), method.options.items[1].value.integer);
    try std.testing.expectEqualStrings("(demo.method_opt)", method.options.items[2].name);
    try std.testing.expectEqualSlices(u8, "method", method.options.items[2].value.string);
}

test "descriptor preserves enum allow_alias option" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\enum Alias { option allow_alias = true; A = 0; B = 0; }
    );
    defer file.deinit();
    const bytes = try encodeFileDescriptorProto(allocator, &file, "alias.proto");
    defer allocator.free(bytes);
    var decoded = try decodeFileDescriptorProto(allocator, bytes);
    defer decoded.deinit();
    const enumeration = decoded.findEnum("Alias").?;
    try std.testing.expectEqualStrings("allow_alias", enumeration.options.items[0].name);
    try std.testing.expect(enumeration.options.items[0].value.boolean);
    try std.testing.expectEqual(@as(i32, 0), enumeration.findValue("B").?.number);
}

test "descriptor preserves proto2 MessageSet message option" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Host { option message_set_wire_format = true; extensions 4 to max; }
        \\message Ext {}
        \\extend Host { optional Ext ext = 100; }
    );
    defer file.deinit();
    const bytes = try encodeFileDescriptorProto(allocator, &file, "mset.proto");
    defer allocator.free(bytes);
    var decoded = try decodeFileDescriptorProto(allocator, bytes);
    defer decoded.deinit();
    const host = decoded.findMessage("Host").?;
    try std.testing.expect(host.messageSetWireFormat());
    try std.testing.expectEqual(@as(usize, 1), host.options.items.len);
    try std.testing.expectEqualStrings("message_set_wire_format", host.options.items[0].name);
    try std.testing.expect(host.options.items[0].value.boolean);
}

test "descriptor preserves source code info locations" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Person { optional string name = 1; }
    );
    defer file.deinit();
    file.source_code_info.deinit(allocator);
    file.source_code_info = .{};

    var file_location = schema.SourceCodeInfo.Location{};
    try file_location.path.appendSlice(allocator, &.{});
    try file_location.span.appendSlice(allocator, &.{ 0, 0, 2, 1 });
    file_location.leading_comments = "file leading\n";
    try file_location.leading_detached_comments.append(allocator, "detached paragraph\n");
    try file.source_code_info.locations.append(allocator, file_location);

    var field_location = schema.SourceCodeInfo.Location{};
    try field_location.path.appendSlice(allocator, &.{ 4, 0, 2, 0 });
    try field_location.span.appendSlice(allocator, &.{ 2, 2, 2, 35 });
    field_location.trailing_comments = "field trailing\n";
    try file.source_code_info.locations.append(allocator, field_location);

    const bytes = try encodeFileDescriptorProto(allocator, &file, "person.proto");
    defer allocator.free(bytes);
    var decoded = try decodeFileDescriptorProto(allocator, bytes);
    defer decoded.deinit();

    try std.testing.expectEqual(@as(usize, 2), decoded.source_code_info.locations.items.len);
    try std.testing.expectEqualSlices(i32, &.{}, decoded.source_code_info.locations.items[0].path.items);
    try std.testing.expectEqualSlices(i32, &.{ 0, 0, 2, 1 }, decoded.source_code_info.locations.items[0].span.items);
    try std.testing.expectEqualStrings("file leading\n", decoded.source_code_info.locations.items[0].leading_comments.?);
    try std.testing.expectEqualStrings("detached paragraph\n", decoded.source_code_info.locations.items[0].leading_detached_comments.items[0]);
    try std.testing.expectEqualSlices(i32, &.{ 4, 0, 2, 0 }, decoded.source_code_info.locations.items[1].path.items);
    try std.testing.expectEqualSlices(i32, &.{ 2, 2, 2, 35 }, decoded.source_code_info.locations.items[1].span.items);
    try std.testing.expectEqualStrings("field trailing\n", decoded.source_code_info.locations.items[1].trailing_comments.?);
}

test "descriptor round-trips parser source code info comments and nested paths" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\// Outer leading
        \\message Outer {
        \\  // Child leading
        \\  message Child { optional int32 id = 1; }
        \\  // child field leading
        \\  optional Child child = 1; // child field trailing
        \\}
    );
    defer file.deinit();

    const bytes = try encodeFileDescriptorProto(allocator, &file, "source-comments.proto");
    defer allocator.free(bytes);
    var decoded = try decodeFileDescriptorProto(allocator, bytes);
    defer decoded.deinit();

    const outer_location = findSourceLocation(&decoded, &.{ 4, 0 }).?;
    try std.testing.expectEqualStrings("Outer leading\n", outer_location.leading_comments.?);
    const nested_location = findSourceLocation(&decoded, &.{ 4, 0, 3, 0 }).?;
    try std.testing.expectEqualStrings("Child leading\n", nested_location.leading_comments.?);
    const field_location = findSourceLocation(&decoded, &.{ 4, 0, 2, 0 }).?;
    try std.testing.expectEqualStrings("child field leading\n", field_location.leading_comments.?);
    try std.testing.expectEqualStrings("child field trailing\n", field_location.trailing_comments.?);
    const nested_field_location = findSourceLocation(&decoded, &.{ 4, 0, 3, 0, 2, 0 }).?;
    try std.testing.expectEqual(@as(usize, 4), nested_field_location.span.items.len);
}

test "descriptor rejects invalid source code info locations" {
    const allocator = std.testing.allocator;
    {
        const bytes = try testFileWithSourceLocation(allocator, &.{-1}, &.{ 0, 0, 0, 1 });
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        const bytes = try testFileWithSourceLocation(allocator, &.{}, &.{ -1, 0, 0, 1 });
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        const bytes = try testFileWithSourceLocation(allocator, &.{}, &.{ 2, 5, 1, 0 });
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
}

fn testFileWithSourceLocation(allocator: std.mem.Allocator, path: []const i32, span: []const i32) ![]u8 {
    var location = wire.Writer.init(allocator);
    defer location.deinit();
    try writePackedInt32List(allocator, 1, path, &location);
    try writePackedInt32List(allocator, 2, span, &location);

    var source = wire.Writer.init(allocator);
    defer source.deinit();
    try source.writeMessage(1, location.slice());

    var file = wire.Writer.init(allocator);
    errdefer file.deinit();
    try file.writeString(12, "proto2");
    try file.writeMessage(9, source.slice());
    return try file.toOwnedSlice();
}

fn findSourceLocation(file: *const schema.FileDescriptor, path: []const i32) ?*const schema.SourceCodeInfo.Location {
    for (file.source_code_info.locations.items) |*location| {
        if (std.mem.eql(i32, location.path.items, path)) return location;
    }
    return null;
}

test "descriptor preserves extension range options" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host {
        \\  extensions 100 to max [
        \\    declaration = { number: 100 full_name: ".demo.ext" type: ".demo.Ext" reserved: true },
        \\    verification = DECLARATION,
        \\    features.enum_type = CLOSED
        \\  ];
        \\}
        \\message Ext {}
    );
    defer file.deinit();

    const bytes = try encodeFileDescriptorProto(allocator, &file, "ext-range.proto");
    defer allocator.free(bytes);
    var decoded = try decodeFileDescriptorProto(allocator, bytes);
    defer decoded.deinit();

    const range = &decoded.findMessage("Host").?.extension_ranges.items[0];
    try std.testing.expectEqual(@as(i64, 100), range.start);
    try std.testing.expectEqual(@as(?i64, null), range.end);
    try std.testing.expectEqual(@as(usize, 1), range.declarations.items.len);
    try std.testing.expectEqual(@as(i32, 100), range.declarations.items[0].number);
    try std.testing.expectEqualStrings(".demo.ext", range.declarations.items[0].full_name);
    try std.testing.expectEqualStrings(".demo.Ext", range.declarations.items[0].type_name);
    try std.testing.expect(range.declarations.items[0].reserved);
    try std.testing.expectEqual(schema.ExtensionRangeVerification.declaration, range.verification.?);
    try std.testing.expectEqual(schema.FeatureSet.EnumType.closed, range.features.?.enum_type);
}

test "descriptor rejects extensions that violate decoded declarations" {
    const allocator = std.testing.allocator;
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        var host = schema.MessageDescriptor{ .name = "Host" };
        var range = schema.ExtensionRange{ .start = 100, .end = 200 };
        try range.declarations.append(allocator, .{ .number = 100, .full_name = ".demo.tag", .type_name = "int32" });
        try host.extension_ranges.append(allocator, range);
        try file.messages.append(allocator, host);
        try file.extensions.append(allocator, .{ .name = "tag", .number = 100, .cardinality = .optional, .kind = .{ .scalar = .string }, .extendee = "Host" });
        const bytes = try encodeFileDescriptorProto(allocator, &file, "bad-ext-decl.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        var host = schema.MessageDescriptor{ .name = "Host" };
        var range = schema.ExtensionRange{ .start = 100, .end = 200 };
        try range.declarations.append(allocator, .{ .number = 100, .full_name = ".demo.tag", .type_name = "int32", .reserved = true });
        try host.extension_ranges.append(allocator, range);
        try file.messages.append(allocator, host);
        try file.extensions.append(allocator, .{ .name = "tag", .number = 100, .cardinality = .optional, .kind = .{ .scalar = .int32 }, .extendee = "Host" });
        const bytes = try encodeFileDescriptorProto(allocator, &file, "reserved-ext-decl.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        var host = schema.MessageDescriptor{ .name = "Host" };
        var range = schema.ExtensionRange{ .start = 100, .end = 200 };
        try range.declarations.append(allocator, .{ .number = 100, .full_name = ".demo.other", .type_name = "int32" });
        try host.extension_ranges.append(allocator, range);
        try file.messages.append(allocator, host);
        try file.extensions.append(allocator, .{ .name = "tag", .number = 100, .cardinality = .optional, .kind = .{ .scalar = .int32 }, .extendee = "Host" });
        const bytes = try encodeFileDescriptorProto(allocator, &file, "name-ext-decl.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        var host = schema.MessageDescriptor{ .name = "Host" };
        var range = schema.ExtensionRange{ .start = 100, .end = 200 };
        try range.declarations.append(allocator, .{ .number = 100, .full_name = ".demo.tags", .type_name = "int32" });
        try host.extension_ranges.append(allocator, range);
        try file.messages.append(allocator, host);
        try file.extensions.append(allocator, .{ .name = "tags", .number = 100, .cardinality = .repeated, .kind = .{ .scalar = .int32 }, .extendee = "Host" });
        const bytes = try encodeFileDescriptorProto(allocator, &file, "repeated-ext-decl.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        var host = schema.MessageDescriptor{ .name = "Host" };
        var range = schema.ExtensionRange{ .start = 100, .end = 200 };
        try range.declarations.append(allocator, .{ .number = 100, .full_name = ".demo.tag", .type_name = "int32", .repeated = true });
        try host.extension_ranges.append(allocator, range);
        try file.messages.append(allocator, host);
        try file.extensions.append(allocator, .{ .name = "tag", .number = 100, .cardinality = .optional, .kind = .{ .scalar = .int32 }, .extendee = "Host" });
        const bytes = try encodeFileDescriptorProto(allocator, &file, "singular-ext-decl.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        var host = schema.MessageDescriptor{ .name = "Host" };
        const range = schema.ExtensionRange{ .start = 100, .end = 200, .verification = .declaration };
        try host.extension_ranges.append(allocator, range);
        try file.messages.append(allocator, host);
        try file.extensions.append(allocator, .{ .name = "tag", .number = 100, .cardinality = .optional, .kind = .{ .scalar = .int32 }, .extendee = "Host" });
        const bytes = try encodeFileDescriptorProto(allocator, &file, "missing-ext-decl.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
}

test "descriptor rejects duplicate decoded extensions" {
    const allocator = std.testing.allocator;
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        var host = schema.MessageDescriptor{ .name = "Host" };
        try host.extension_ranges.append(allocator, .{ .start = 100, .end = 200 });
        try file.messages.append(allocator, host);
        try file.extensions.append(allocator, .{ .name = "first", .number = 100, .cardinality = .optional, .kind = .{ .scalar = .int32 }, .extendee = "Host" });
        try file.extensions.append(allocator, .{ .name = "second", .number = 100, .cardinality = .optional, .kind = .{ .scalar = .int32 }, .extendee = "Host" });
        const bytes = try encodeFileDescriptorProto(allocator, &file, "dup-ext-number.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
    {
        var file = schema.FileDescriptor.init(allocator);
        defer file.deinit();
        file.setSyntax(.proto2);
        var host = schema.MessageDescriptor{ .name = "Host" };
        try host.extension_ranges.append(allocator, .{ .start = 100, .end = 200 });
        var scope = schema.MessageDescriptor{ .name = "Scope" };
        try scope.extensions.append(allocator, .{ .name = "tag", .number = 101, .cardinality = .optional, .kind = .{ .scalar = .string }, .extendee = "Host" });
        try file.messages.append(allocator, host);
        try file.messages.append(allocator, scope);
        try file.extensions.append(allocator, .{ .name = "tag", .number = 100, .cardinality = .optional, .kind = .{ .scalar = .string }, .extendee = "Host" });
        const bytes = try encodeFileDescriptorProto(allocator, &file, "dup-ext-name.proto");
        defer allocator.free(bytes);
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, bytes));
    }
}

test "descriptor encodes and decodes generated code info" {
    const allocator = std.testing.allocator;
    var generated = schema.GeneratedCodeInfo{};
    defer generated.deinit(allocator);
    var annotation = schema.GeneratedCodeInfo.Annotation{};
    try annotation.path.appendSlice(allocator, &.{ 4, 0, 2, 0 });
    annotation.source_file = "demo.proto";
    annotation.begin = 10;
    annotation.end = 20;
    annotation.semantic = .set;
    try generated.annotations.append(allocator, annotation);

    const bytes = try encodeGeneratedCodeInfo(allocator, &generated);
    defer allocator.free(bytes);
    var decoded = try decodeGeneratedCodeInfo(allocator, bytes);
    defer decoded.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), decoded.annotations.items.len);
    try std.testing.expectEqualSlices(i32, &.{ 4, 0, 2, 0 }, decoded.annotations.items[0].path.items);
    try std.testing.expectEqualStrings("demo.proto", decoded.annotations.items[0].source_file.?);
    try std.testing.expectEqual(@as(i32, 10), decoded.annotations.items[0].begin.?);
    try std.testing.expectEqual(@as(i32, 20), decoded.annotations.items[0].end.?);
    try std.testing.expectEqual(schema.GeneratedCodeInfo.Semantic.set, decoded.annotations.items[0].semantic.?);
}

test "descriptor rejects invalid enum descriptors" {
    const allocator = std.testing.allocator;
    {
        var enum_writer = wire.Writer.init(allocator);
        defer enum_writer.deinit();
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-enum.proto");
        try file.writeMessage(5, enum_writer.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var value = wire.Writer.init(allocator);
        defer value.deinit();
        try value.writeInt32(2, 0);
        var enum_writer = wire.Writer.init(allocator);
        defer enum_writer.deinit();
        try enum_writer.writeString(1, "Bad");
        try enum_writer.writeMessage(2, value.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "bad-value.proto");
        try file.writeMessage(5, enum_writer.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var value = wire.Writer.init(allocator);
        defer value.deinit();
        try value.writeString(1, "A");
        try value.writeInt32(2, 0);
        var enum_writer = wire.Writer.init(allocator);
        defer enum_writer.deinit();
        try enum_writer.writeString(1, "Bad");
        try enum_writer.writeMessage(2, value.slice());
        try enum_writer.writeMessage(2, value.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "dup-value.proto");
        try file.writeMessage(5, enum_writer.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var first = wire.Writer.init(allocator);
        defer first.deinit();
        try first.writeString(1, "A");
        try first.writeInt32(2, 0);
        var second = wire.Writer.init(allocator);
        defer second.deinit();
        try second.writeString(1, "B");
        try second.writeInt32(2, 0);
        var enum_writer = wire.Writer.init(allocator);
        defer enum_writer.deinit();
        try enum_writer.writeString(1, "Bad");
        try enum_writer.writeMessage(2, first.slice());
        try enum_writer.writeMessage(2, second.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "dup-number.proto");
        try file.writeMessage(5, enum_writer.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var value = wire.Writer.init(allocator);
        defer value.deinit();
        try value.writeString(1, "ONE");
        try value.writeInt32(2, 1);
        var enum_writer = wire.Writer.init(allocator);
        defer enum_writer.deinit();
        try enum_writer.writeString(1, "Bad");
        try enum_writer.writeMessage(2, value.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "proto3-enum-first-nonzero.proto");
        try file.writeString(12, "proto3");
        try file.writeMessage(5, enum_writer.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
    {
        var value = wire.Writer.init(allocator);
        defer value.deinit();
        try value.writeString(1, "ONE");
        try value.writeInt32(2, 1);
        var enum_writer = wire.Writer.init(allocator);
        defer enum_writer.deinit();
        try enum_writer.writeString(1, "Bad");
        try enum_writer.writeMessage(2, value.slice());
        var message = wire.Writer.init(allocator);
        defer message.deinit();
        try message.writeString(1, "Container");
        try message.writeMessage(4, enum_writer.slice());
        var file = wire.Writer.init(allocator);
        defer file.deinit();
        try file.writeString(1, "proto3-nested-enum-first-nonzero.proto");
        try file.writeString(12, "proto3");
        try file.writeMessage(4, message.slice());
        try std.testing.expectError(error.InvalidFieldType, decodeFileDescriptorProto(allocator, file.slice()));
    }
}
