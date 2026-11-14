const enum_emit = @import("enum.zig");
const json_emit = @import("json_emit.zig");
const schema = @import("../schema.zig");
const service_emit = @import("service.zig");
const std = @import("std");
const text_emit = @import("text_emit.zig");
const cg = @import("../codegen.zig");
const CodegenContext = cg.CodegenContext;
const Error = cg.Error;
const hasPresence = cg.hasPresence;
const indent = cg.indent;
const outputNameWithOptions = cg.outputNameWithOptions;
const typedMapMessageValueWithContext = cg.typedMapMessageValueWithContext;
const typedOneofMessageFieldWithContext = cg.typedOneofMessageFieldWithContext;
const typedRepeatedMessageFieldWithContext = cg.typedRepeatedMessageFieldWithContext;
const typedSingularMessageFieldWithContext = cg.typedSingularMessageFieldWithContext;
const writeFieldDefault = cg.writeFieldDefault;
const writeMessageTypeReferenceWithContext = cg.writeMessageTypeReferenceWithContext;
const writePresenceIdent = cg.writePresenceIdent;
const writeQuotedIdent = cg.writeQuotedIdent;
const writeQuotedIdentWithPrefix = cg.writeQuotedIdentWithPrefix;
const writeQuotedIdentWithSuffix = cg.writeQuotedIdentWithSuffix;
const writeTypedMessageTypeWithContext = cg.writeTypedMessageTypeWithContext;
const writeTypedRepeatedMessageTypeWithContext = cg.writeTypedRepeatedMessageTypeWithContext;
const writeZigLowerCamelStringLiteral = cg.writeZigLowerCamelStringLiteral;
const writeZigStringLiteral = cg.writeZigStringLiteral;
const canReferenceEnumWithContext = cg.emit_helpers.canReferenceEnumWithContext;
const canReferenceMessageWithContext = cg.emit_helpers.canReferenceMessageWithContext;
const canWriteBareIdent = cg.emit_helpers.canWriteBareIdent;
const fieldKindName = cg.emit_helpers.fieldKindName;
const fieldTypeName = cg.emit_helpers.fieldTypeName;
const isBareIdentChar = cg.emit_helpers.isBareIdentChar;
const messageCanDecodeKnownReuse = cg.emit_helpers.messageCanDecodeKnownReuse;
const scalarZigType = cg.emit_helpers.scalarZigType;
const writeAdoptOwned = cg.emit_helpers.writeAdoptOwned;
const writeBorrowedViewMethods = cg.emit_helpers.writeBorrowedViewMethods;
const writeClear = cg.emit_helpers.writeClear;
const writeCloneOwned = cg.emit_helpers.writeCloneOwned;
const writeDecode = cg.emit_helpers.writeDecode;
const writeDecodeInitialized = cg.emit_helpers.writeDecodeInitialized;
const writeDecodeKnownReuse = cg.emit_helpers.writeDecodeKnownReuse;
const writeDecodeOwnedReuse = cg.emit_helpers.writeDecodeOwnedReuse;
const writeDecodeReuse = cg.emit_helpers.writeDecodeReuse;
const writeDeinit = cg.emit_helpers.writeDeinit;
const writeEncode = cg.emit_helpers.writeEncode;
const writeEncodeDeterministic = cg.emit_helpers.writeEncodeDeterministic;
const writeEncodeInitialized = cg.emit_helpers.writeEncodeInitialized;
const writeEnumTypeReferenceOrVoid = cg.emit_helpers.writeEnumTypeReferenceOrVoid;
const writeExtensionMetadata = cg.emit_helpers.writeExtensionMetadata;
const writeFieldKindDefault = cg.emit_helpers.writeFieldKindDefault;
const writeFieldKindType = cg.emit_helpers.writeFieldKindType;
const writeFieldType = cg.emit_helpers.writeFieldType;
const writeMapStorageType = cg.emit_helpers.writeMapStorageType;
const writeMergeFrom = cg.emit_helpers.writeMergeFrom;
const writeMessageConformantParsers = cg.emit_helpers.writeMessageConformantParsers;
const writeMessageDescriptorLookup = cg.emit_helpers.writeMessageDescriptorLookup;
const writeMessageDynamicBridge = cg.emit_helpers.writeMessageDynamicBridge;
const writeMessageExtensionAccessors = cg.emit_helpers.writeMessageExtensionAccessors;
const writeMessageTypeReferenceOrVoid = cg.emit_helpers.writeMessageTypeReferenceOrVoid;
const writeMissingRequiredFieldName = cg.emit_helpers.writeMissingRequiredFieldName;
const writeMissingRequiredFieldPath = cg.emit_helpers.writeMissingRequiredFieldPath;
const writeOptionValueTextLiteral = cg.emit_helpers.writeOptionValueTextLiteral;
const writeQuotedFieldNumber = cg.emit_helpers.writeQuotedFieldNumber;
const writeScalarDefault = cg.emit_helpers.writeScalarDefault;
const writeUnknownFieldMethods = cg.emit_helpers.writeUnknownFieldMethods;
const writeValidateRequired = cg.emit_helpers.writeValidateRequired;

pub fn writePackagedFileDecls(ctx: *const CodegenContext, writer: *std.Io.Writer, depth: usize) Error!void {
    if (ctx.file.package.len == 0) return try writeFileDecls(ctx, writer, depth);
    try writePackageNamespace(ctx, ctx.file.package, writer, depth);
}

pub fn writePackageNamespace(ctx: *const CodegenContext, package: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    const dot = std.mem.indexOfScalar(u8, package, '.');
    const segment = if (dot) |idx| package[0..idx] else package;
    if (segment.len == 0) {
        if (dot) |idx| return try writePackageNamespace(ctx, package[idx + 1 ..], writer, depth);
        return try writeFileDecls(ctx, writer, depth);
    }

    try indent(writer, depth);
    try writer.writeAll("pub const ");
    try writeQuotedIdent(segment, writer);
    try writer.writeAll(" = struct {\n");
    if (dot) |idx| {
        try writePackageNamespace(ctx, package[idx + 1 ..], writer, depth + 1);
    } else {
        try writeFileDecls(ctx, writer, depth + 1);
    }
    try indent(writer, depth);
    try writer.writeAll("};\n\n");
}

pub fn writeFileDecls(ctx: *const CodegenContext, writer: *std.Io.Writer, depth: usize) Error!void {
    for (ctx.file.enums.items) |*enumeration| try enum_emit.writeEnum(ctx, enumeration, writer, depth);
    for (ctx.file.messages.items) |*message| try writeMessage(ctx, message, writer, depth);
    try writeExtensionMetadata(ctx, writer, depth);
    try service_emit.writeServiceMetadata(ctx, writer, depth);
}

pub fn writeFileMetadata(ctx: *const CodegenContext, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    try indent(writer, depth);
    try writer.writeAll("pub const proto_package = ");
    try writeZigStringLiteral(file.package, writer);
    try writer.writeAll(";\n");
    try indent(writer, depth);
    try writer.writeAll("pub const proto_syntax = ");
    try writeZigStringLiteral(switch (file.syntax) {
        .proto2 => "proto2",
        .proto3 => "proto3",
        .editions => "editions",
    }, writer);
    try writer.writeAll(";\n");
    if (file.imports.items.len != 0) {
        try indent(writer, depth);
        try writer.writeAll("pub const imports = struct {\n");
        for (file.imports.items) |import| try writeImportDecl(ctx, import, writer, depth + 1);
        try indent(writer, depth);
        try writer.writeAll("};\n");
    }
    if (file.imports.items.len != 0 or ctx.emit_descriptor) {
        try indent(writer, depth);
        try writer.writeAll("const pbz_generated_file = @This();\n");
    }
    try writer.writeAll("\n");
}

pub fn writeGeneratedFileDescriptor(ctx: *const CodegenContext, file: *const schema.FileDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const descriptor_mod = @import("../descriptor.zig");
    // Imported enum references are materialized into `file.enums` with their
    // fully qualified names so generated code can spell them. Those aliases are
    // not part of the original FileDescriptorProto (whose enum names are simple
    // identifiers), so filter them out before serializing the embedded
    // descriptor; otherwise decodeFileDescriptor rejects the dotted names.
    var descriptor_file = file.*;
    var filtered_enums: std.ArrayList(schema.EnumDescriptor) = .empty;
    defer filtered_enums.deinit(ctx.allocator);
    for (file.enums.items) |enumeration| {
        if (std.mem.indexOfScalar(u8, enumeration.name, '.') == null) try filtered_enums.append(ctx.allocator, enumeration);
    }
    descriptor_file.enums = .{ .items = filtered_enums.items, .capacity = filtered_enums.items.len };
    const descriptor_bytes = if (ctx.registry) |registry|
        try descriptor_mod.encodeFileDescriptorProtoWithRegistry(ctx.allocator, &descriptor_file, registry, file.name)
    else
        try descriptor_mod.encodeFileDescriptorProto(ctx.allocator, &descriptor_file, file.name);
    defer ctx.allocator.free(descriptor_bytes);

    try indent(writer, depth);
    try writer.writeAll("/// Serialized google.protobuf.FileDescriptorProto for this generated file.\n");
    try indent(writer, depth);
    try writer.writeAll("/// Use decodeFileDescriptor() to build registry/reflection metadata.\n");
    try indent(writer, depth);
    try writer.writeAll("pub const file_descriptor_proto = [_]u8{");
    for (descriptor_bytes, 0..) |byte, i| {
        if (i % 12 == 0) {
            try writer.writeAll("\n");
            try indent(writer, depth + 1);
        } else {
            try writer.writeAll(" ");
        }
        try writer.print("0x{x:0>2},", .{byte});
    }
    if (descriptor_bytes.len != 0) {
        try writer.writeAll("\n");
        try indent(writer, depth);
    }
    try writer.writeAll("};\n");
    try indent(writer, depth);
    try writer.writeAll("/// Decode the embedded FileDescriptorProto. The caller owns the result and\n");
    try indent(writer, depth);
    try writer.writeAll("/// must call deinit() on it.\n");
    try indent(writer, depth);
    try writer.writeAll("pub fn decodeFileDescriptor(allocator: std.mem.Allocator) !pbz.schema.FileDescriptor {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return pbz.decodeFileDescriptorProto(allocator, &file_descriptor_proto);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");
}

pub fn writeImportDecl(ctx: *const CodegenContext, import: schema.Import, writer: *std.Io.Writer, depth: usize) Error!void {
    const allocator = ctx.allocator;
    const module_path = try outputNameWithOptions(allocator, import.path, ctx.output_suffix, ctx.strip_proto_ext);
    defer allocator.free(module_path);
    const relative_path = try relativeModulePath(allocator, ctx.file.name, module_path);
    defer allocator.free(relative_path);
    const import_alias = try makeImportAlias(allocator, import.path);
    defer allocator.free(import_alias);
    try indent(writer, depth);
    try writer.writeAll("pub const ");
    try writer.writeAll(import_alias);
    try writer.writeAll(" = @import(");
    try writeZigStringLiteral(relative_path, writer);
    try writer.writeAll(");\n");
    try indent(writer, depth);
    try writer.writeAll("pub const ");
    try writer.writeAll(import_alias);
    try writer.writeAll("_path");
    try writer.writeAll(" = ");
    try writeZigStringLiteral(import.path, writer);
    try writer.writeAll(";\n");
    try indent(writer, depth);
    try writer.writeAll("pub const ");
    try writer.writeAll(import_alias);
    try writer.writeAll("_kind");
    try writer.writeAll(" = ");
    try writeZigStringLiteral(@tagName(import.kind), writer);
    try writer.writeAll(";\n");
}

/// Zig resolves `@import("...")` relative to the importing file, so generated
/// files in subdirectories need `../` prefixes to reach modules that live
/// elsewhere in the same generation root.
pub fn relativeModulePath(allocator: std.mem.Allocator, from_file: []const u8, to_module: []const u8) Error![]u8 {
    const from_dir = std.fs.path.dirname(from_file) orelse "";
    if (from_dir.len == 0) return allocator.dupe(u8, to_module);
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    var components = std.mem.tokenizeScalar(u8, from_dir, '/');
    while (components.next()) |_| try out.writer.writeAll("../");
    try out.writer.writeAll(to_module);
    return out.toOwnedSlice();
}

pub fn makeImportAlias(allocator: std.mem.Allocator, path: []const u8) Error![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();

    const source = if (path.len == 0) "import" else path;
    for (source) |c| {
        if (isBareIdentChar(c, out.written().len == 0)) {
            try out.writer.writeByte(c);
        } else if (out.written().len == 0 or out.written()[out.written().len - 1] != '_') {
            try out.writer.writeByte('_');
        }
    }

    if (out.written().len == 0 or std.mem.eql(u8, out.written(), "_") or !canWriteBareIdent(out.written())) {
        try out.writer.writeAll("_pb");
    }
    return try out.toOwnedSlice();
}

pub fn writeMessage(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    try indent(writer, depth);
    try writer.writeAll("pub const ");
    try writeQuotedIdent(message.name, writer);
    try writer.writeAll(" = struct {\n");
    for (message.fields.items) |*field| {
        try indent(writer, depth + 1);
        try writer.writeAll("pub const ");
        try writeQuotedFieldNumber(field.name, writer);
        try writer.print(" = {d};\n", .{field.number});
    }
    if (message.fields.items.len != 0) try writer.writeAll("\n");
    for (message.fields.items) |*field| try writeFieldMetadataDecl(ctx, field, writer, depth + 1);
    if (message.fields.items.len != 0) try writer.writeAll("\n");
    try writeMessageDescriptorLookup(ctx, message, writer, depth + 1);
    try writeMessageDynamicBridge(ctx, writer, depth + 1);
    try writeMessageConformantParsers(ctx, writer, depth + 1);
    for (message.fields.items) |*field| {
        if (field.kind == .map) {
            try writeMapEntryType(ctx, field, writer, depth + 1);
            try writeMapEntryHelpers(ctx, field, writer, depth + 1);
        }
    }
    for (message.oneofs.items) |oneof| try writeOneofUnion(ctx, message, oneof, writer, depth + 1);
    for (message.fields.items) |*field| {
        if (field.oneof_name == null) try writeFieldDecl(ctx, field, writer, depth + 1);
    }
    for (message.oneofs.items) |oneof| try writeOneofField(oneof, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("_json_arena: ?*std.heap.ArenaAllocator = null,\n");
    try indent(writer, depth + 1);
    try writer.writeAll("_unknown_fields: []const []const u8 = &.{},\n");
    if (message.fields.items.len != 0) try writer.writeAll("\n");
    try writeInit(writer, depth + 1);
    try writer.writeAll("\n");
    try writeDeinit(ctx, message, writer, depth + 1);
    try writer.writeAll("\n");
    try writeClear(writer, depth + 1);
    try writer.writeAll("\n");
    try writeCloneOwned(ctx, message, writer, depth + 1);
    try writer.writeAll("\n");
    try writeAdoptOwned(ctx, message, writer, depth + 1);
    try writer.writeAll("\n");
    try writeOwnedAllocator(writer, depth + 1);
    try writer.writeAll("\n");
    try writeUnknownFieldMethods(writer, depth + 1);
    try writer.writeAll("\n");
    try writeOneofDeinitHelpers(ctx, message, writer, depth + 1);
    try writer.writeAll("\n");
    try writeBorrowedViewMethods(file, message, writer, depth + 1);
    try writer.writeAll("\n");
    try writeMessageExtensionAccessors(ctx, message, writer, depth + 1);
    try writer.writeAll("\n");
    try writeMergeFrom(ctx, message, writer, depth + 1);
    try writer.writeAll("\n");
    try writeEncode(ctx, message, writer, depth + 1);
    try writer.writeAll("\n");
    try writeEncodeDeterministic(ctx, message, writer, depth + 1);
    try writer.writeAll("\n");
    try writeEncodeInitialized(writer, depth + 1);
    try writer.writeAll("\n");
    try writeDecode(ctx, message, writer, depth + 1);
    try writer.writeAll("\n");
    try writeDecodeReuse(ctx, message, writer, depth + 1);
    try writer.writeAll("\n");
    try writeDecodeOwnedReuse(ctx, message, writer, depth + 1);
    try writer.writeAll("\n");
    if (messageCanDecodeKnownReuse(ctx.file, message)) {
        try writeDecodeKnownReuse(ctx, message, writer, depth + 1);
        try writer.writeAll("\n");
    }
    try writeDecodeInitialized(writer, depth + 1);
    try writer.writeAll("\n");
    try writeMissingRequiredFieldName(message, writer, depth + 1);
    try writer.writeAll("\n");
    try writeMissingRequiredFieldPath(ctx, message, writer, depth + 1);
    try writer.writeAll("\n");
    try writeValidateRequired(ctx, message, writer, depth + 1);
    try writer.writeAll("\n");
    if (ctx.emit_json) {
        try json_emit.writeJsonMethods(ctx, message, writer, depth + 1);
        try writer.writeAll("\n");
    }
    if (ctx.emit_text) {
        try text_emit.writeTextMethods(ctx, message, writer, depth + 1);
        try writer.writeAll("\n");
    }
    for (message.enums.items) |*enumeration| try enum_emit.writeEnum(ctx, enumeration, writer, depth + 1);
    for (message.messages.items) |*nested| try writeMessage(ctx, nested, writer, depth + 1);
    try indent(writer, depth);
    try writer.writeAll("};\n\n");
}

pub fn writeOneofUnion(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, oneof: schema.OneofDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub const ");
    try writeOneofTypeName(oneof.name, writer);
    try writer.writeAll(" = union(enum) {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("none,\n");
    for (message.fields.items) |*field| {
        if (field.oneof_name) |name| {
            if (std.mem.eql(u8, name, oneof.name)) {
                try indent(writer, depth + 1);
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(": ");
                if (typedOneofMessageFieldWithContext(ctx, field)) |type_name| {
                    try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
                } else {
                    try writeFieldType(field.*, writer);
                }
                try writer.writeAll(",\n");
            }
        }
    }
    try indent(writer, depth);
    try writer.writeAll("};\n\n");
}

pub fn writeOneofField(oneof: schema.OneofDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writeQuotedIdent(oneof.name, writer);
    try writer.writeAll(": @This().");
    try writeOneofTypeName(oneof.name, writer);
    try writer.writeAll(" = .none,\n");
}

pub fn writeOneofTypeName(name: []const u8, writer: *std.Io.Writer) Error!void {
    try writeQuotedIdentWithSuffix(name, "Oneof", writer);
}

pub fn writeOneofDeinitHelpers(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    for (message.oneofs.items) |oneof| {
        const has_typed_message = oneofHasTypedMessageWithContext(ctx, message, oneof.name);
        try indent(writer, depth);
        try writer.writeAll("fn ");
        try writeQuotedIdentWithPrefix(oneof.name, "_pbzDeinitOneof_", writer);
        try writer.writeAll("(self: *@This(), allocator: std.mem.Allocator) void {\n");
        if (!has_typed_message) {
            try indent(writer, depth + 1);
            try writer.writeAll("_ = allocator;\n");
        } else {
            try indent(writer, depth + 1);
            try writer.writeAll("switch (self.");
            try writeQuotedIdent(oneof.name, writer);
            try writer.writeAll(") {\n");
            for (message.fields.items) |*field| {
                const field_oneof = field.oneof_name orelse continue;
                if (!std.mem.eql(u8, field_oneof, oneof.name)) continue;
                if (typedOneofMessageFieldWithContext(ctx, field) == null) continue;
                try indent(writer, depth + 2);
                try writer.writeAll(".");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(" => |*value| value.deinit(allocator),\n");
            }
            try indent(writer, depth + 2);
            try writer.writeAll("else => {},\n");
            try indent(writer, depth + 1);
            try writer.writeAll("}\n");
        }
        try indent(writer, depth + 1);
        try writer.writeAll("self.");
        try writeQuotedIdent(oneof.name, writer);
        try writer.writeAll(" = .none;\n");
        try indent(writer, depth);
        try writer.writeAll("}\n\n");
    }
}

pub fn oneofHasTypedMessageWithContext(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, oneof_name: []const u8) bool {
    for (message.fields.items) |*field| {
        const name = field.oneof_name orelse continue;
        if (std.mem.eql(u8, name, oneof_name) and typedOneofMessageFieldWithContext(ctx, field) != null) return true;
    }
    return false;
}

pub fn writeOneofDeinitCall(oneof_name: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("self.");
    try writeQuotedIdentWithPrefix(oneof_name, "_pbzDeinitOneof_", writer);
    try writer.writeAll("(allocator);");
}

pub fn writeFieldMetadataDecl(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    try indent(writer, depth);
    try writer.writeAll("pub const ");
    try writeQuotedIdentWithSuffix(field.name, "_field", writer);
    try writer.writeAll(" = struct {\n");
    try indent(writer, depth + 1);
    try writer.print("pub const number = {d};\n", .{field.number});
    try indent(writer, depth + 1);
    try writer.writeAll("pub const name = ");
    try writeZigStringLiteral(field.name, writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const json_name = ");
    if (field.json_name) |json_name| {
        try writeZigStringLiteral(json_name, writer);
    } else {
        try writeZigLowerCamelStringLiteral(field.name, writer);
    }
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const cardinality = ");
    try writeZigStringLiteral(@tagName(field.cardinality), writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const kind = ");
    try writeZigStringLiteral(fieldKindName(field.kind), writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const type_name = ");
    try writeZigStringLiteral(fieldTypeName(field.kind), writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const zig_type = ");
    if (typedSingularMessageFieldWithContext(ctx, field)) |type_name| {
        var type_buf: std.Io.Writer.Allocating = .init(ctx.allocator);
        defer type_buf.deinit();
        try type_buf.writer.writeByte('?');
        try writeMessageTypeReferenceWithContext(ctx, type_name, &type_buf.writer);
        try writeZigStringLiteral(type_buf.written(), writer);
    } else if (typedRepeatedMessageFieldWithContext(ctx, field)) |type_name| {
        var type_buf: std.Io.Writer.Allocating = .init(ctx.allocator);
        defer type_buf.deinit();
        try type_buf.writer.writeAll("[]const ");
        try writeMessageTypeReferenceWithContext(ctx, type_name, &type_buf.writer);
        try writeZigStringLiteral(type_buf.written(), writer);
    } else if (typedOneofMessageFieldWithContext(ctx, field)) |type_name| {
        var type_buf: std.Io.Writer.Allocating = .init(ctx.allocator);
        defer type_buf.deinit();
        try writeMessageTypeReferenceWithContext(ctx, type_name, &type_buf.writer);
        try writeZigStringLiteral(type_buf.written(), writer);
    } else {
        var type_buf: std.Io.Writer.Allocating = .init(ctx.allocator);
        defer type_buf.deinit();
        try writeFieldType(field.*, &type_buf.writer);
        try writeZigStringLiteral(type_buf.written(), writer);
    }
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const has_type_ref = ");
    try writer.writeAll(if (canReferenceMessageWithContext(ctx, field.kind)) "true" else "false");
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const type_ref = ");
    try writeMessageTypeReferenceOrVoid(ctx, field.kind, writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const has_enum_ref = ");
    try writer.writeAll(if (canReferenceEnumWithContext(ctx, field.kind)) "true" else "false");
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const enum_ref = ");
    try writeEnumTypeReferenceOrVoid(ctx, field.kind, writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const has_presence = ");
    try writer.writeAll(if (hasPresence(file, field.*)) "true" else "false");
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const default_value = ");
    try writeOptionValueTextLiteral(field.default_value, writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const is_packed = ");
    try writer.writeAll(if (field.resolvedPacked(file)) "true" else "false");
    try writer.writeAll(";\n");
    if (field.kind == .map) {
        try indent(writer, depth + 1);
        try writer.writeAll("pub const map_key = ");
        try writeZigStringLiteral(@tagName(field.kind.map.key), writer);
        try writer.writeAll(";\n");
        try indent(writer, depth + 1);
        try writer.writeAll("pub const map_value_kind = ");
        try writeZigStringLiteral(fieldKindName(field.kind.map.value.*), writer);
        try writer.writeAll(";\n");
        try indent(writer, depth + 1);
        try writer.writeAll("pub const map_value_type_name = ");
        try writeZigStringLiteral(fieldTypeName(field.kind.map.value.*), writer);
        try writer.writeAll(";\n");
        try indent(writer, depth + 1);
        try writer.writeAll("pub const map_value_has_type_ref = ");
        try writer.writeAll(if (canReferenceMessageWithContext(ctx, field.kind.map.value.*)) "true" else "false");
        try writer.writeAll(";\n");
        try indent(writer, depth + 1);
        try writer.writeAll("pub const map_value_type_ref = ");
        try writeMessageTypeReferenceOrVoid(ctx, field.kind.map.value.*, writer);
        try writer.writeAll(";\n");
        try indent(writer, depth + 1);
        try writer.writeAll("pub const map_value_has_enum_ref = ");
        try writer.writeAll(if (canReferenceEnumWithContext(ctx, field.kind.map.value.*)) "true" else "false");
        try writer.writeAll(";\n");
        try indent(writer, depth + 1);
        try writer.writeAll("pub const map_value_enum_ref = ");
        try writeEnumTypeReferenceOrVoid(ctx, field.kind.map.value.*, writer);
        try writer.writeAll(";\n");
    }
    try indent(writer, depth);
    try writer.writeAll("};\n");
}

pub fn writeFieldDecl(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    try indent(writer, depth);
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(": ");
    if (typedSingularMessageFieldWithContext(ctx, field)) |type_name| {
        try writeTypedMessageTypeWithContext(ctx, type_name, writer);
        try writer.writeAll(" = null,\n");
        return;
    }
    if (typedRepeatedMessageFieldWithContext(ctx, field)) |type_name| {
        try writeTypedRepeatedMessageTypeWithContext(ctx, type_name, writer);
        try writer.writeAll(" = &.{},\n");
        return;
    }
    try writeFieldType(field.*, writer);
    try writer.writeAll(" = ");
    try writeFieldDefault(file, field.*, writer);
    try writer.writeAll(",\n");
    if (hasPresence(file, field.*)) {
        try indent(writer, depth);
        try writePresenceIdent(field.name, writer);
        try writer.writeAll(": bool = false,\n");
    }
}

pub fn writeMapEntryType(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    const map_type = switch (field.kind) {
        .map => |map| map,
        else => return,
    };
    try indent(writer, depth);
    try writer.writeAll("pub const ");
    try writeQuotedIdentWithSuffix(field.name, "Map", writer);
    try writer.writeAll(" = ");
    try writeMapStorageType(ctx, field, writer);
    try writer.writeAll(";\n\n");
    try indent(writer, depth);
    try writer.writeAll("pub const ");
    try writeQuotedIdentWithSuffix(field.name, "Entry", writer);
    try writer.writeAll(" = struct {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("key: ");
    try writer.writeAll(scalarZigType(map_type.key));
    try writer.writeAll(" = ");
    try writeScalarDefault(map_type.key, null, writer);
    try writer.writeAll(",\n");
    try indent(writer, depth + 1);
    try writer.writeAll("value: ");
    if (typedMapMessageValueWithContext(ctx, field)) |type_name| {
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    } else {
        try writeFieldKindType(map_type.value.*, writer);
    }
    try writer.writeAll(" = ");
    if (typedMapMessageValueWithContext(ctx, field)) |_| {
        try writer.writeAll(".{}");
    } else {
        try writeFieldKindDefault(file, map_type.value.*, null, writer);
    }
    try writer.writeAll(",\n");
    try indent(writer, depth);
    try writer.writeAll("};\n\n");
}

pub fn writeMapEntryHelpers(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const map_type = switch (field.kind) {
        .map => |map| map,
        else => return,
    };
    try indent(writer, depth);
    try writer.writeAll("fn ");
    try writeQuotedIdentWithPrefix(field.name, "appendOrReplaceMapEntry_", writer);
    try writer.writeAll("(allocator: std.mem.Allocator, list: *std.ArrayList(");
    try writeQuotedIdentWithSuffix(field.name, "Entry", writer);
    try writer.writeAll("), entry: ");
    try writeQuotedIdentWithSuffix(field.name, "Entry", writer);
    try writer.writeAll(") !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("for (list.items) |*existing| {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("if (");
    try writeMapKeyEqualExpr(map_type.key, "existing.key", "entry.key", writer);
    try writer.writeAll(") { ");
    if (typedMapMessageValueWithContext(ctx, field)) |_| {
        try writer.writeAll("existing.value.deinit(allocator); ");
    }
    try writer.writeAll("existing.* = entry; return; }\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try list.append(allocator, entry);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("fn ");
    try writeQuotedIdentWithPrefix(field.name, "putMapEntry_", writer);
    try writer.writeAll("(allocator: std.mem.Allocator, map: *");
    try writeQuotedIdentWithSuffix(field.name, "Map", writer);
    try writer.writeAll(", entry: ");
    try writeQuotedIdentWithSuffix(field.name, "Entry", writer);
    try writer.writeAll(") !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const result = try map.getOrPut(allocator, entry.key);\n");
    if (typedMapMessageValueWithContext(ctx, field)) |_| {
        try indent(writer, depth + 1);
        try writer.writeAll("if (result.found_existing) result.value_ptr.deinit(allocator);\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("result.value_ptr.* = entry.value;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("fn ");
    try writeQuotedIdentWithPrefix(field.name, "deinitMap_", writer);
    try writer.writeAll("(allocator: std.mem.Allocator, map: *");
    try writeQuotedIdentWithSuffix(field.name, "Map", writer);
    try writer.writeAll(") void {\n");
    if (typedMapMessageValueWithContext(ctx, field)) |_| {
        try indent(writer, depth + 1);
        try writer.writeAll("var it = map.iterator();\n");
        try indent(writer, depth + 1);
        try writer.writeAll("while (it.next()) |entry| entry.value_ptr.deinit(allocator);\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("map.deinit(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("map.* = .empty;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");
}

pub fn writeMapKeyEqualExpr(scalar: schema.ScalarType, lhs: []const u8, rhs: []const u8, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .string => try writer.print("std.mem.eql(u8, {s}, {s})", .{ lhs, rhs }),
        else => try writer.print("{s} == {s}", .{ lhs, rhs }),
    }
}

pub fn writeInit(writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn init() @This() {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return .{};\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeOwnedAllocator(writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("fn _pbzOwnedAllocator(self: *@This(), allocator: std.mem.Allocator) !std.mem.Allocator {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (self._json_arena == null) {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("const arena = try allocator.create(std.heap.ArenaAllocator);\n");
    try indent(writer, depth + 2);
    try writer.writeAll("errdefer allocator.destroy(arena);\n");
    try indent(writer, depth + 2);
    try writer.writeAll("arena.* = std.heap.ArenaAllocator.init(allocator);\n");
    try indent(writer, depth + 2);
    try writer.writeAll("self._json_arena = arena;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return self._json_arena.?.allocator();\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}
