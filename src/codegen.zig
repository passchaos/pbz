const std = @import("std");
const schema = @import("schema.zig");
const plugin = @import("plugin.zig");
const wire = @import("wire.zig");

pub const Error = std.mem.Allocator.Error || std.Io.Writer.Error || plugin.Error;

pub fn generateZigFile(allocator: std.mem.Allocator, file: *const schema.FileDescriptor) Error![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    try out.writer.writeAll("const std = @import(\"std\");\nconst pbz = @import(\"pbz\");\n\n");
    try writeFileMetadata(allocator, file, &out.writer, 0);
    for (file.enums.items) |*enumeration| try writeEnum(enumeration, &out.writer, 0);
    for (file.messages.items) |*message| try writeMessage(file, message, &out.writer, 0);
    try writeExtensionMetadata(file, &out.writer, 0);
    try writeServiceMetadata(file, &out.writer, 0);
    return try out.toOwnedSlice();
}

pub fn generatePluginResponse(allocator: std.mem.Allocator, files: []const *const schema.FileDescriptor) Error![]u8 {
    var response_files = try allocator.alloc(plugin.CodeGeneratorResponse.File, files.len);
    @memset(response_files, .{});
    defer {
        for (response_files) |file| {
            if (file.name) |name| allocator.free(name);
            if (file.content.len != 0) allocator.free(file.content);
        }
        allocator.free(response_files);
    }
    for (files, 0..) |file, i| {
        const content = try generateZigFile(allocator, file);
        errdefer allocator.free(content);
        const name = try outputName(allocator, file.name);
        response_files[i] = .{ .name = name, .content = content };
    }
    return try (plugin.CodeGeneratorResponse{
        .supported_features = plugin.CodeGeneratorResponse.featureMask(&[_]plugin.CodeGeneratorResponse.Feature{ .proto3_optional, .supports_editions }),
        .minimum_edition = .proto2,
        .maximum_edition = .edition_2026,
        .files = response_files,
    }).encode(allocator);
}

fn writeFileMetadata(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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
        for (file.imports.items) |import| try writeImportDecl(allocator, import, writer, depth + 1);
        try indent(writer, depth);
        try writer.writeAll("};\n");
    }
    try writer.writeAll("\n");
}

fn writeImportDecl(allocator: std.mem.Allocator, import: schema.Import, writer: *std.Io.Writer, depth: usize) Error!void {
    const module_path = try outputName(allocator, import.path);
    defer allocator.free(module_path);
    try indent(writer, depth);
    try writer.writeAll("pub const ");
    try writeQuotedIdent(import.path, writer);
    try writer.writeAll(" = @import(");
    try writeZigStringLiteral(module_path, writer);
    try writer.writeAll(");\n");
    try indent(writer, depth);
    try writer.writeAll("pub const ");
    try writeQuotedIdentWithSuffix(import.path, "_path", writer);
    try writer.writeAll(" = ");
    try writeZigStringLiteral(import.path, writer);
    try writer.writeAll(";\n");
    try indent(writer, depth);
    try writer.writeAll("pub const ");
    try writeQuotedIdentWithSuffix(import.path, "_kind", writer);
    try writer.writeAll(" = ");
    try writeZigStringLiteral(@tagName(import.kind), writer);
    try writer.writeAll(";\n");
}

fn writeMessage(file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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
    for (message.fields.items) |*field| {
        if (field.kind == .map) try writeMapEntryType(field, writer, depth + 1);
    }
    for (message.oneofs.items) |oneof| try writeOneofUnion(message, oneof, writer, depth + 1);
    for (message.fields.items) |*field| {
        if (field.oneof_name == null) try writeFieldDecl(file, field, writer, depth + 1);
    }
    for (message.oneofs.items) |oneof| try writeOneofField(oneof, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("@\"_json_arena\": ?*std.heap.ArenaAllocator = null,\n");
    if (message.fields.items.len != 0) try writer.writeAll("\n");
    try writeInit(writer, depth + 1);
    try writer.writeAll("\n");
    try writeDeinit(message, writer, depth + 1);
    try writer.writeAll("\n");
    try writeOwnedAllocator(writer, depth + 1);
    try writer.writeAll("\n");
    try writeMergeFrom(file, message, writer, depth + 1);
    try writer.writeAll("\n");
    try writeEncode(file, message, writer, depth + 1);
    try writer.writeAll("\n");
    try writeEncodeDeterministic(file, message, writer, depth + 1);
    try writer.writeAll("\n");
    try writeEncodeInitialized(writer, depth + 1);
    try writer.writeAll("\n");
    try writeDecode(file, message, writer, depth + 1);
    try writer.writeAll("\n");
    try writeDecodeInitialized(writer, depth + 1);
    try writer.writeAll("\n");
    try writeMissingRequiredFieldName(message, writer, depth + 1);
    try writer.writeAll("\n");
    try writeMissingRequiredFieldPath(file, message, writer, depth + 1);
    try writer.writeAll("\n");
    try writeValidateRequired(file, message, writer, depth + 1);
    try writer.writeAll("\n");
    try writeJsonMethods(file, message, writer, depth + 1);
    try writer.writeAll("\n");
    try writeTextMethods(file, message, writer, depth + 1);
    try writer.writeAll("\n");
    for (message.enums.items) |*enumeration| try writeEnum(enumeration, writer, depth + 1);
    for (message.messages.items) |*nested| try writeMessage(file, nested, writer, depth + 1);
    try indent(writer, depth);
    try writer.writeAll("};\n\n");
}

fn writeOneofUnion(message: *const schema.MessageDescriptor, oneof: schema.OneofDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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
                try writeFieldType(field.*, writer);
                try writer.writeAll(",\n");
            }
        }
    }
    try indent(writer, depth);
    try writer.writeAll("};\n\n");
}

fn writeOneofField(oneof: schema.OneofDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writeQuotedIdent(oneof.name, writer);
    try writer.writeAll(": ");
    try writeOneofTypeName(oneof.name, writer);
    try writer.writeAll(" = .none,\n");
}

fn writeOneofTypeName(name: []const u8, writer: *std.Io.Writer) Error!void {
    try writeQuotedIdentWithSuffix(name, "Oneof", writer);
}

fn writeEncodeOneof(file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor, oneof: schema.OneofDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("switch (self.");
    try writeQuotedIdent(oneof.name, writer);
    try writer.writeAll(") {\n");
    try indent(writer, depth + 1);
    try writer.writeAll(".none => {},\n");
    for (message.fields.items) |*field| {
        if (field.oneof_name) |name| {
            if (std.mem.eql(u8, name, oneof.name)) {
                try indent(writer, depth + 1);
                try writer.writeAll(".");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(" => |value| ");
                try writeOneofValueEncode(file, field, "value", writer);
                try writer.writeAll(",\n");
            }
        }
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeTextParseMethods(file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn parseText(allocator: std.mem.Allocator, text: []const u8) !@This() {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var self = @This().init();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer self.deinit(allocator);\n");
    for (message.fields.items) |*field| try writeRepeatedListDecl(field, writer, depth + 1);
    if (!messageTextParseUsesAllocator(message)) {
        try indent(writer, depth + 1);
        try writer.writeAll("_ = allocator;\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("var lines = std.mem.splitScalar(u8, text, '\\n');\n");
    try indent(writer, depth + 1);
    try writer.writeAll("while (lines.next()) |raw_line| {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("const line = @This().textCleanLine(raw_line);\n");
    try indent(writer, depth + 2);
    try writer.writeAll("if (line.len == 0) continue;\n");
    for (message.fields.items) |*field| {
        if (field.oneof_name == null) try writeTextParseField(file, field, writer, depth + 2);
    }
    for (message.oneofs.items) |oneof| {
        for (message.fields.items) |*field| {
            if (field.oneof_name) |name| {
                if (std.mem.eql(u8, name, oneof.name)) try writeTextParseOneofField(file, oneof, field, writer, depth + 2);
            }
        }
    }
    try indent(writer, depth + 2);
    try writer.writeAll("return error.UnknownField;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    for (message.fields.items) |*field| try writeRepeatedAssign(field, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("return self;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn parseTextInitialized(allocator: std.mem.Allocator, text: []const u8) !@This() {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var self = try @This().parseText(allocator, text);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer self.deinit(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.validateRequiredRecursive(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return self;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn messageTextParseUsesAllocator(message: *const schema.MessageDescriptor) bool {
    for (message.fields.items) |field| {
        if (field.cardinality == .repeated or field.kind == .map) return true;
        if (field.kind == .message or field.kind == .group) return true;
    }
    return false;
}

fn writeTextParseField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    switch (field.kind) {
        .scalar, .enumeration => {},
        .message, .group => |type_name| return try writeTextParseMessageField(file, field, type_name, writer, depth),
        .map => return try writeTextParseMapField(file, field, writer, depth),
    }
    try indent(writer, depth);
    try writer.writeAll("if (");
    try writeTextFieldValueLookup(field, "line", writer);
    try writer.writeAll(") |raw_value| {\n");
    if (field.cardinality == .repeated) {
        try indent(writer, depth + 1);
        try writeQuotedIdentWithSuffix(field.name, "_list", writer);
        try writer.writeAll(".append(allocator, ");
        try writeTextParseValueExpr(file, field.kind, "raw_value", writer);
        try writer.writeAll(") catch |err| return err;\n");
    } else {
        try indent(writer, depth + 1);
        try writer.writeAll("self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = ");
        try writeTextParseValueExpr(file, field.kind, "raw_value", writer);
        try writer.writeAll(";\n");
        if (hasPresence(file, field.*)) {
            try indent(writer, depth + 1);
            try writer.writeAll("self.");
            try writePresenceIdent(field.name, writer);
            try writer.writeAll(" = true;\n");
        }
    }
    try indent(writer, depth + 1);
    try writer.writeAll("continue;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeTextParseMessageField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, type_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    if (!codegenCanReferenceMessage(file, type_name)) return;
    try indent(writer, depth);
    try writer.writeAll("if (");
    try writeTextBlockCondition(field, "line", writer);
    try writer.writeAll(") {\n");
    try writeTextParseMessagePayloadAssign(field, type_name, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("continue;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeTextParseMessagePayloadAssign(field: *const schema.FieldDescriptor, type_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("const block = try @This().textBlock(allocator, &lines);\n");
    try indent(writer, depth);
    try writer.writeAll("defer allocator.free(block);\n");
    try indent(writer, depth);
    try writer.writeAll("var nested = try ");
    try writeMessageTypeReference(type_name, writer);
    try writer.writeAll(".parseText(allocator, block);\n");
    try indent(writer, depth);
    try writer.writeAll("defer nested.deinit(allocator);\n");
    try indent(writer, depth);
    try writer.writeAll("const owned_allocator = try self.@\"_pbzOwnedAllocator\"(allocator);\n");
    try indent(writer, depth);
    try writer.writeAll("const payload = try nested.encode(owned_allocator);\n");
    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        try writeQuotedIdentWithSuffix(field.name, "_list", writer);
        try writer.writeAll(".append(allocator, payload) catch |err| return err;\n");
    } else {
        if (field.oneof_name) |oneof_name| {
            try indent(writer, depth);
            try writer.writeAll("self.");
            try writeQuotedIdent(oneof_name, writer);
            try writer.writeAll(" = .{ .");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(" = payload };\n");
        } else {
            try indent(writer, depth);
            try writer.writeAll("if (self.");
            try writePresenceIdent(field.name, writer);
            try writer.writeAll(" and self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(".len != 0 and payload.len != 0) {\n");
            try indent(writer, depth + 1);
            try writer.writeAll("const merged = try owned_allocator.alloc(u8, self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(".len + payload.len);\n");
            try indent(writer, depth + 1);
            try writer.writeAll("@memcpy(merged[0..self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(".len], self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(");\n");
            try indent(writer, depth + 1);
            try writer.writeAll("@memcpy(merged[self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(".len..], payload);\n");
            try indent(writer, depth + 1);
            try writer.writeAll("self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(" = merged;\n");
            try indent(writer, depth);
            try writer.writeAll("} else {\n");
            try indent(writer, depth + 1);
            try writer.writeAll("self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(" = payload;\n");
            try indent(writer, depth);
            try writer.writeAll("}\n");
            if (hasPresenceForTextParseMessage(field.*)) {
                try indent(writer, depth);
                try writer.writeAll("self.");
                try writePresenceIdent(field.name, writer);
                try writer.writeAll(" = true;\n");
            }
        }
    }
}

fn writeTextParseMapField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const map_type = switch (field.kind) {
        .map => |map_type| map_type,
        else => return,
    };
    if (!textMapValueSupported(file, map_type.value.*)) return;
    try indent(writer, depth);
    try writer.writeAll("if (");
    try writeTextBlockCondition(field, "line", writer);
    try writer.writeAll(") {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var entry = ");
    try writeQuotedIdentWithSuffix(field.name, "Entry", writer);
    try writer.writeAll("{};\n");
    try indent(writer, depth + 1);
    try writer.writeAll("while (lines.next()) |raw_entry_line| {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("const entry_line = @This().textCleanLine(raw_entry_line);\n");
    try indent(writer, depth + 2);
    try writer.writeAll("if (std.mem.eql(u8, entry_line, \"}\") or std.mem.eql(u8, entry_line, \">\")) break;\n");
    try indent(writer, depth + 2);
    try writer.writeAll("if (@This().textFieldValue(entry_line, \"key\")) |raw_key| { entry.key = ");
    try writeTextParseValueExpr(file, .{ .scalar = map_type.key }, "raw_key", writer);
    try writer.writeAll("; continue; }\n");
    if (map_type.value.* == .message and codegenCanReferenceMessage(file, map_type.value.message)) {
        try indent(writer, depth + 2);
        try writer.writeAll("if (std.mem.eql(u8, entry_line, \"value {\") or std.mem.eql(u8, entry_line, \"value <\")) {\n");
        try indent(writer, depth + 3);
        try writer.writeAll("const block = try @This().textBlock(allocator, &lines);\n");
        try indent(writer, depth + 3);
        try writer.writeAll("defer allocator.free(block);\n");
        try indent(writer, depth + 3);
        try writer.writeAll("var nested = try ");
        try writeMessageTypeReference(map_type.value.message, writer);
        try writer.writeAll(".parseText(allocator, block);\n");
        try indent(writer, depth + 3);
        try writer.writeAll("defer nested.deinit(allocator);\n");
        try indent(writer, depth + 3);
        try writer.writeAll("const owned_allocator = try self.@\"_pbzOwnedAllocator\"(allocator);\n");
        try indent(writer, depth + 3);
        try writer.writeAll("entry.value = try nested.encode(owned_allocator);\n");
        try indent(writer, depth + 3);
        try writer.writeAll("continue;\n");
        try indent(writer, depth + 2);
        try writer.writeAll("}\n");
    }
    if (map_type.value.* == .scalar or map_type.value.* == .enumeration) {
        try indent(writer, depth + 2);
        try writer.writeAll("if (@This().textFieldValue(entry_line, \"value\")) |raw_value| { entry.value = ");
        try writeTextParseValueExpr(file, map_type.value.*, "raw_value", writer);
        try writer.writeAll("; continue; }\n");
    }
    try indent(writer, depth + 2);
    try writer.writeAll("return error.UnknownField;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writeQuotedIdentWithSuffix(field.name, "_list", writer);
    try writer.writeAll(".append(allocator, entry) catch |err| return err;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("continue;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeTextParseOneofField(file: *const schema.FileDescriptor, oneof: schema.OneofDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    switch (field.kind) {
        .scalar, .enumeration => {},
        .message, .group => |type_name| {
            if (!codegenCanReferenceMessage(file, type_name)) return;
            try indent(writer, depth);
            try writer.writeAll("if (");
            try writeTextBlockCondition(field, "line", writer);
            try writer.writeAll(") {\n");
            try writeTextParseMessagePayloadAssign(field, type_name, writer, depth + 1);
            try indent(writer, depth + 1);
            try writer.writeAll("continue;\n");
            try indent(writer, depth);
            try writer.writeAll("}\n");
            return;
        },
        else => return,
    }
    try indent(writer, depth);
    try writer.writeAll("if (");
    try writeTextFieldValueLookup(field, "line", writer);
    try writer.writeAll(") |raw_value| { self.");
    try writeQuotedIdent(oneof.name, writer);
    try writer.writeAll(" = .{ .");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = ");
    try writeTextParseValueExpr(file, field.kind, "raw_value", writer);
    try writer.writeAll(" }; continue; }\n");
}

fn writeTextFieldValueLookup(field: *const schema.FieldDescriptor, line_expr: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("@This().textFieldValue(");
    try writer.writeAll(line_expr);
    try writer.writeAll(", ");
    try writeZigStringLiteral(field.name, writer);
    try writer.writeAll(")");
    try writeTextAlternateValueLookups(field, line_expr, writer);
}

fn writeTextAlternateValueLookups(field: *const schema.FieldDescriptor, line_expr: []const u8, writer: *std.Io.Writer) Error!void {
    if (field.json_name) |json_name| {
        if (!std.mem.eql(u8, json_name, field.name)) {
            try writer.writeAll(" orelse @This().textFieldValue(");
            try writer.writeAll(line_expr);
            try writer.writeAll(", ");
            try writeZigStringLiteral(json_name, writer);
            try writer.writeAll(")");
        }
    } else if (std.mem.indexOfScalar(u8, field.name, '_') != null) {
        try writer.writeAll(" orelse @This().textFieldValue(");
        try writer.writeAll(line_expr);
        try writer.writeAll(", ");
        try writeZigLowerCamelStringLiteral(field.name, writer);
        try writer.writeAll(")");
    }
}

fn writeTextBlockCondition(field: *const schema.FieldDescriptor, line_expr: []const u8, writer: *std.Io.Writer) Error!void {
    try writeTextBlockNameCondition(field.name, line_expr, writer);
    if (field.json_name) |json_name| {
        if (!std.mem.eql(u8, json_name, field.name)) {
            try writer.writeAll(" or ");
            try writeTextBlockNameCondition(json_name, line_expr, writer);
        }
    } else if (std.mem.indexOfScalar(u8, field.name, '_') != null) {
        try writer.writeAll(" or ");
        try writeTextLowerCamelBlockNameCondition(field.name, line_expr, writer);
    }
}

fn writeTextBlockNameCondition(name: []const u8, line_expr: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("std.mem.eql(u8, ");
    try writer.writeAll(line_expr);
    try writer.writeAll(", \"");
    try writeEscapedStringContents(name, writer);
    try writer.writeAll(" {\") or std.mem.eql(u8, ");
    try writer.writeAll(line_expr);
    try writer.writeAll(", \"");
    try writeEscapedStringContents(name, writer);
    try writer.writeAll(" <\")");
}

fn writeTextLowerCamelBlockNameCondition(name: []const u8, line_expr: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("std.mem.eql(u8, ");
    try writer.writeAll(line_expr);
    try writer.writeAll(", \"");
    try writeLowerCamelEscaped(name, writer);
    try writer.writeAll(" {\") or std.mem.eql(u8, ");
    try writer.writeAll(line_expr);
    try writer.writeAll(", \"");
    try writeLowerCamelEscaped(name, writer);
    try writer.writeAll(" <\")");
}

fn hasPresenceForTextParseMessage(field: schema.FieldDescriptor) bool {
    return field.cardinality == .required or field.proto3_optional or field.kind == .message or field.kind == .group or if (field.features) |features| features.field_presence != .implicit else false;
}

fn writeTextParseValueExpr(file: *const schema.FileDescriptor, kind: schema.FieldKind, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    switch (kind) {
        .scalar => |scalar| switch (scalar) {
            .double => try writer.print("try @This().textFloat(f64, {s})", .{value_expr}),
            .float => try writer.print("try @This().textFloat(f32, {s})", .{value_expr}),
            .int32, .sint32, .sfixed32 => try writer.print("try @This().textInt(i32, {s})", .{value_expr}),
            .int64, .sint64, .sfixed64 => try writer.print("try @This().textInt(i64, {s})", .{value_expr}),
            .uint32, .fixed32 => try writer.print("try @This().textInt(u32, {s})", .{value_expr}),
            .uint64, .fixed64 => try writer.print("try @This().textInt(u64, {s})", .{value_expr}),
            .bool => try writer.print("try @This().textBool({s})", .{value_expr}),
            .string, .bytes => try writer.print("try @This().textUnquote(try self.@\"_pbzOwnedAllocator\"(allocator), {s})", .{value_expr}),
        },
        .enumeration => |name| {
            try writer.print("try @This().textEnum({s}, ", .{value_expr});
            try writeEnumNameArray(file, name, writer);
            try writer.writeAll(", ");
            try writeEnumNumberArray(file, name, writer);
            try writer.writeAll(", ");
            try writer.writeAll(if (enumIsClosed(file, name)) "true" else "false");
            try writer.writeAll(")");
        },
        else => try writer.writeAll("@compileError(\"unsupported TextFormat parse field kind\")"),
    }
}

fn writeOneofValueEncode(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    switch (field.kind) {
        .scalar => |scalar| {
            if (scalar == .string and fieldUtf8Validation(file, field) == .verify) {
                try writer.writeAll("{ if (!std.unicode.utf8ValidateSlice(");
                try writer.writeAll(value_expr);
                try writer.writeAll(")) return error.InvalidUtf8; ");
                try writeScalarWriteCall(field.number, scalar, value_expr, writer);
                try writer.writeAll("); }");
            } else {
                try writeScalarWriteCall(field.number, scalar, value_expr, writer);
                try writer.writeAll(")");
            }
        },
        .enumeration => try writer.print("try w.writeInt32({d}, {s})", .{ field.number, value_expr }),
        .message => {
            if (fieldMessageEncoding(file, field) == .delimited) {
                try writer.print("{{ try w.writeTag({d}, .start_group); try w.appendSlice({s}); try w.writeTag({d}, .end_group); }}", .{ field.number, value_expr, field.number });
            } else {
                try writer.print("try w.writeMessage({d}, {s})", .{ field.number, value_expr });
            }
        },
        .group => try writer.print("{{ try w.writeTag({d}, .start_group); try w.appendSlice({s}); try w.writeTag({d}, .end_group); }}", .{ field.number, value_expr, field.number }),
        else => try writer.writeAll("@compileError(\"unsupported oneof field\")"),
    }
}

fn writeFieldDecl(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(": ");
    try writeFieldType(field.*, writer);
    try writer.writeAll(" = ");
    try writeFieldDefault(field.*, writer);
    try writer.writeAll(",\n");
    if (hasPresence(file, field.*)) {
        try indent(writer, depth);
        try writePresenceIdent(field.name, writer);
        try writer.writeAll(": bool = false,\n");
    }
}

fn writeMapEntryType(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const map_type = switch (field.kind) {
        .map => |map| map,
        else => return,
    };
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
    try writeFieldKindType(map_type.value.*, writer);
    try writer.writeAll(" = ");
    try writeFieldKindDefault(map_type.value.*, null, writer);
    try writer.writeAll(",\n");
    try indent(writer, depth);
    try writer.writeAll("};\n\n");
}

fn writeInit(writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn init() @This() {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return .{};\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeEncode(file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn encode(self: @This(), allocator: std.mem.Allocator) ![]u8 {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var w = pbz.Writer.init(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer w.deinit();\n");
    for (message.fields.items) |*field| {
        if (field.oneof_name == null) try writeEncodeField(file, field, writer, depth + 1);
    }
    for (message.oneofs.items) |oneof| try writeEncodeOneof(file, message, oneof, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("return try w.toOwnedSlice();\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeEncodeDeterministic(file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn encodeDeterministic(self: @This(), allocator: std.mem.Allocator) ![]u8 {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var w = pbz.Writer.init(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer w.deinit();\n");
    try writeEncodeFieldsByNumber(file, message, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("return try w.toOwnedSlice();\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn encodeDeterministicInitialized(self: @This(), allocator: std.mem.Allocator) ![]u8 {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.validateRequiredRecursive(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try self.encodeDeterministic(allocator);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeEncodeFieldsByNumber(file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    var emitted: usize = 0;
    var previous: u29 = 0;
    while (emitted < message.fields.items.len) : (emitted += 1) {
        var next: ?*const schema.FieldDescriptor = null;
        for (message.fields.items) |*field| {
            if (field.number <= previous) continue;
            if (next == null or field.number < next.?.number) next = field;
        }
        const field = next orelse break;
        previous = field.number;
        if (field.oneof_name) |oneof_name| {
            try writeEncodeOneofSingleField(file, field, oneof_name, writer, depth);
        } else if (field.kind == .map) {
            try writeEncodeMapFieldDeterministic(file, field, writer, depth);
        } else {
            try writeEncodeField(file, field, writer, depth);
        }
    }
}

fn writeEncodeOneofSingleField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, oneof_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("switch (self.");
    try writeQuotedIdent(oneof_name, writer);
    try writer.writeAll(") {\n");
    try indent(writer, depth + 1);
    try writer.writeAll(".");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" => |value| ");
    try writeOneofValueEncode(file, field, "value", writer);
    try writer.writeAll(",\n");
    try indent(writer, depth + 1);
    try writer.writeAll("else => {},\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeEncodeInitialized(writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn encodeInitialized(self: @This(), allocator: std.mem.Allocator) ![]u8 {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.validateRequiredRecursive(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try self.encode(allocator);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeOwnedAllocator(writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("fn @\"_pbzOwnedAllocator\"(self: *@This(), allocator: std.mem.Allocator) !std.mem.Allocator {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (self.@\"_json_arena\" == null) {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("const arena = try allocator.create(std.heap.ArenaAllocator);\n");
    try indent(writer, depth + 2);
    try writer.writeAll("errdefer allocator.destroy(arena);\n");
    try indent(writer, depth + 2);
    try writer.writeAll("arena.* = std.heap.ArenaAllocator.init(allocator);\n");
    try indent(writer, depth + 2);
    try writer.writeAll("self.@\"_json_arena\" = arena;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return self.@\"_json_arena\".?.allocator();\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeMergeFrom(file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn mergeFrom(self: *@This(), allocator: std.mem.Allocator, other: @This()) !void {\n");
    if (!mergeUsesAllocator(message)) {
        try indent(writer, depth + 1);
        try writer.writeAll("_ = allocator;\n");
    }
    for (message.fields.items) |*field| {
        if (field.oneof_name == null) try writeMergeField(file, field, writer, depth + 1);
    }
    for (message.oneofs.items) |oneof| try writeMergeOneof(message, oneof, writer, depth + 1);
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn mergeUsesAllocator(message: *const schema.MessageDescriptor) bool {
    for (message.fields.items) |field| {
        if (field.oneof_name != null) continue;
        if (field.cardinality == .repeated or field.kind == .map or field.kind == .message or field.kind == .group) return true;
    }
    return false;
}

fn writeMergeField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.cardinality == .repeated or field.kind == .map) return try writeMergeRepeatedField(field, writer, depth);
    switch (field.kind) {
        .message, .group => try writeMergeSingularMessageField(field, writer, depth),
        .scalar => |scalar| try writeMergeSingularScalarField(file, field, scalar, writer, depth),
        .enumeration => try writeMergeSingularEnumField(file, field, writer, depth),
        else => {},
    }
}

fn writeMergeRepeatedField(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("if (other.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".len != 0) {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const old = self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const merged = try allocator.alloc(");
    try writeRepeatedElementType(field.*, writer);
    try writer.writeAll(", old.len + other.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".len);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("@memcpy(merged[0..old.len], old);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("@memcpy(merged[old.len..], other.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(");\n");
    try indent(writer, depth + 1);
    try writer.writeAll("self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = merged;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (old.len != 0) allocator.free(old);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeMergeSingularMessageField(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("if (other.");
    try writePresenceIdent(field.name, writer);
    try writer.writeAll(") {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (self.");
    try writePresenceIdent(field.name, writer);
    try writer.writeAll(" and self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".len != 0 and other.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".len != 0) {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("const owned_allocator = try self.@\"_pbzOwnedAllocator\"(allocator);\n");
    try indent(writer, depth + 2);
    try writer.writeAll("const merged = try owned_allocator.alloc(u8, self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".len + other.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".len);\n");
    try indent(writer, depth + 2);
    try writer.writeAll("@memcpy(merged[0..self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".len], self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(");\n");
    try indent(writer, depth + 2);
    try writer.writeAll("@memcpy(merged[self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".len..], other.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(");\n");
    try indent(writer, depth + 2);
    try writer.writeAll("self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = merged;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("} else if (!self.");
    try writePresenceIdent(field.name, writer);
    try writer.writeAll(" or self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".len == 0) {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = other.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("self.");
    try writePresenceIdent(field.name, writer);
    try writer.writeAll(" = true;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeMergeSingularScalarField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    if (hasPresence(file, field.*)) {
        try writer.writeAll("if (other.");
        try writePresenceIdent(field.name, writer);
        try writer.writeAll(") { self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = other.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll("; self.");
        try writePresenceIdent(field.name, writer);
        try writer.writeAll(" = true; }\n");
    } else {
        try writer.writeAll("if (other.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(defaultSkipCondition(scalar));
        try writer.writeAll("self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = other.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(";\n");
    }
}

fn writeMergeSingularEnumField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    if (hasPresence(file, field.*)) {
        try writer.writeAll("if (other.");
        try writePresenceIdent(field.name, writer);
        try writer.writeAll(") { self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = other.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll("; self.");
        try writePresenceIdent(field.name, writer);
        try writer.writeAll(" = true; }\n");
    } else {
        try writer.writeAll("if (other.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" != 0) self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = other.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(";\n");
    }
}

fn writeMergeOneof(message: *const schema.MessageDescriptor, oneof: schema.OneofDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("switch (other.");
    try writeQuotedIdent(oneof.name, writer);
    try writer.writeAll(") {\n");
    try indent(writer, depth + 1);
    try writer.writeAll(".none => {},\n");
    for (message.fields.items) |*field| {
        if (field.oneof_name) |name| {
            if (std.mem.eql(u8, name, oneof.name)) {
                try indent(writer, depth + 1);
                try writer.writeAll(".");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(" => |value| self.");
                try writeQuotedIdent(oneof.name, writer);
                try writer.writeAll(" = .{ .");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(" = value },\n");
            }
        }
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeDeinit(message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {\n");
    var has_repeated = false;
    for (message.fields.items) |*field| {
        if (field.cardinality == .repeated or field.kind == .map) {
            has_repeated = true;
            try indent(writer, depth + 1);
            try writer.writeAll("allocator.free(self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(");\n");
        }
    }
    if (!has_repeated) {
        try indent(writer, depth + 1);
        try writer.writeAll("_ = allocator;\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("if (self.@\"_json_arena\") |arena| { const child_allocator = arena.child_allocator; arena.deinit(); child_allocator.destroy(arena); }\n");
    try indent(writer, depth + 1);
    try writer.writeAll("self.* = undefined;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeMissingRequiredFieldName(message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn missingRequiredFieldName(self: @This()) ?[]const u8 {\n");
    var has_required = false;
    for (message.fields.items) |*field| {
        if (isRequired(field.*)) {
            has_required = true;
            try indent(writer, depth + 1);
            try writer.writeAll("if (!self.");
            try writePresenceIdent(field.name, writer);
            try writer.writeAll(") return ");
            try writeZigStringLiteral(field.name, writer);
            try writer.writeAll(";\n");
        }
    }
    if (!has_required) {
        try indent(writer, depth + 1);
        try writer.writeAll("_ = self;\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("return null;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeMissingRequiredFieldPath(file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn missingRequiredFieldPath(self: @This(), allocator: std.mem.Allocator) !?[]u8 {\n");
    var uses_allocator = false;
    for (message.fields.items) |*field| {
        if (isRequired(field.*)) {
            uses_allocator = true;
            try indent(writer, depth + 1);
            try writer.writeAll("if (!self.");
            try writePresenceIdent(field.name, writer);
            try writer.writeAll(") return try allocator.dupe(u8, ");
            try writeZigStringLiteral(field.name, writer);
            try writer.writeAll(");\n");
        }
    }
    for (message.fields.items) |*field| {
        if (field.kind == .message or field.kind == .group or fieldHasMessageMapValue(field)) {
            if (try writeMissingRequiredPathField(file, field, writer, depth + 1)) uses_allocator = true;
        }
    }
    for (message.oneofs.items) |oneof| {
        if (oneofHasMessageField(message, oneof.name)) {
            uses_allocator = true;
            try writeMissingRequiredPathOneof(file, message, oneof, writer, depth + 1);
        }
    }
    if (!uses_allocator) {
        try indent(writer, depth + 1);
        try writer.writeAll("_ = self; _ = allocator;\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("return null;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeMissingRequiredPathField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!bool {
    if (field.kind == .map) return try writeMissingRequiredPathMapField(file, field, writer, depth);
    const type_name = switch (field.kind) {
        .message => |name| name,
        .group => |name| name,
        else => return false,
    };
    if (!codegenCanReferenceMessage(file, type_name)) return false;
    if (field.oneof_name != null) return false;
    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        try writer.writeAll("for (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(") |payload| {\n");
        try writeMissingRequiredPathPayload(type_name, field.name, "payload", writer, depth + 1);
        try indent(writer, depth);
        try writer.writeAll("}\n");
    } else {
        try indent(writer, depth);
        try writer.writeAll("if (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(".len != 0) {\n");
        try writeMissingRequiredPathPayload(type_name, field.name, "self.", writer, depth + 1);
        try indent(writer, depth);
        try writer.writeAll("}\n");
    }
    return true;
}

fn writeMissingRequiredPathMapField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!bool {
    const map_type = switch (field.kind) {
        .map => |map_type| map_type,
        else => return false,
    };
    const type_name = switch (map_type.value.*) {
        .message => |name| name,
        else => return false,
    };
    if (!codegenCanReferenceMessage(file, type_name)) return false;
    try indent(writer, depth);
    try writer.writeAll("for (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(") |entry| {\n");
    try writeMissingRequiredPathPayload(type_name, field.name, "entry.value", writer, depth + 1);
    try indent(writer, depth);
    try writer.writeAll("}\n");
    return true;
}

fn writeMissingRequiredPathOneof(file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor, oneof: schema.OneofDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("switch (self.");
    try writeQuotedIdent(oneof.name, writer);
    try writer.writeAll(") {\n");
    try indent(writer, depth + 1);
    try writer.writeAll(".none => {},\n");
    for (message.fields.items) |*field| {
        if (field.oneof_name) |name| {
            const type_name = switch (field.kind) {
                .message => |message_name| message_name,
                .group => |group_name| group_name,
                else => continue,
            };
            if (std.mem.eql(u8, name, oneof.name) and codegenCanReferenceMessage(file, type_name)) {
                try indent(writer, depth + 1);
                try writer.writeAll(".");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(" => |payload| {\n");
                try writeMissingRequiredPathPayload(type_name, field.name, "payload", writer, depth + 2);
                try indent(writer, depth + 1);
                try writer.writeAll("},\n");
            }
        }
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeMissingRequiredPathPayload(type_name: []const u8, field_name: []const u8, payload_expr: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("var nested = try ");
    try writeMessageTypeReference(type_name, writer);
    try writer.writeAll(".decode(allocator, ");
    try writer.writeAll(payload_expr);
    if (std.mem.eql(u8, payload_expr, "self.")) try writeQuotedIdent(field_name, writer);
    try writer.writeAll(");\n");
    try indent(writer, depth);
    try writer.writeAll("defer nested.deinit(allocator);\n");
    try indent(writer, depth);
    try writer.writeAll("if (try nested.missingRequiredFieldPath(allocator)) |suffix| {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("defer allocator.free(suffix);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try std.fmt.allocPrint(allocator, \"");
    try writeEscapedStringContents(field_name, writer);
    try writer.writeAll(".{s}\", .{suffix});\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeValidateRequired(file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn validateRequired(self: @This()) !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (self.missingRequiredFieldName() != null) return error.MissingRequiredField;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try writer.writeAll("\n");
    try indent(writer, depth);
    try writer.writeAll("pub fn validateRequiredRecursive(self: @This(), allocator: std.mem.Allocator) !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.validateRequired();\n");
    var uses_allocator = false;
    for (message.fields.items) |*field| {
        if (field.kind == .message or field.kind == .group or fieldHasMessageMapValue(field)) {
            uses_allocator = true;
            try writeValidateMessagePayloadField(file, field, writer, depth + 1);
        }
    }
    for (message.oneofs.items) |oneof| {
        if (oneofHasMessageField(message, oneof.name)) {
            uses_allocator = true;
            try writeValidateMessagePayloadOneof(file, message, oneof, writer, depth + 1);
        }
    }
    if (!uses_allocator) {
        try indent(writer, depth + 1);
        try writer.writeAll("_ = allocator;\n");
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeValidateMessagePayloadField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.kind == .map) return try writeValidateMapMessagePayloadField(file, field, writer, depth);
    const type_name = switch (field.kind) {
        .message => |name| name,
        .group => |name| name,
        else => return,
    };
    if (!codegenCanReferenceMessage(file, type_name)) return;
    if (field.oneof_name != null) return;
    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        try writer.writeAll("for (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(") |payload| {\n");
        try writeDecodeAndValidatePayload(type_name, "payload", writer, depth + 1);
        try indent(writer, depth);
        try writer.writeAll("}\n");
    } else {
        try indent(writer, depth);
        try writer.writeAll("if (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(".len != 0) {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("var nested = try ");
        try writeMessageTypeReference(type_name, writer);
        try writer.writeAll(".decode(allocator, self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(");\n");
        try indent(writer, depth + 1);
        try writer.writeAll("defer nested.deinit(allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try nested.validateRequiredRecursive(allocator);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");
    }
}

fn writeValidateMapMessagePayloadField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const map_type = switch (field.kind) {
        .map => |map_type| map_type,
        else => return,
    };
    const type_name = switch (map_type.value.*) {
        .message => |name| name,
        else => return,
    };
    if (!codegenCanReferenceMessage(file, type_name)) return;
    try indent(writer, depth);
    try writer.writeAll("for (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(") |entry| {\n");
    try writeDecodeAndValidatePayload(type_name, "entry.value", writer, depth + 1);
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn fieldHasMessageMapValue(field: *const schema.FieldDescriptor) bool {
    const map_type = switch (field.kind) {
        .map => |map_type| map_type,
        else => return false,
    };
    return map_type.value.* == .message;
}

fn writeValidateMessagePayloadOneof(file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor, oneof: schema.OneofDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("switch (self.");
    try writeQuotedIdent(oneof.name, writer);
    try writer.writeAll(") {\n");
    try indent(writer, depth + 1);
    try writer.writeAll(".none => {},\n");
    for (message.fields.items) |*field| {
        if (field.oneof_name) |name| {
            const type_name = switch (field.kind) {
                .message => |message_name| message_name,
                .group => |group_name| group_name,
                else => continue,
            };
            if (std.mem.eql(u8, name, oneof.name) and codegenCanReferenceMessage(file, type_name)) {
                try indent(writer, depth + 1);
                try writer.writeAll(".");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(" => |payload| {\n");
                try writeDecodeAndValidatePayload(type_name, "payload", writer, depth + 2);
                try indent(writer, depth + 1);
                try writer.writeAll("},\n");
            }
        }
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeDecodeAndValidatePayload(type_name: []const u8, payload_expr: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("var nested = try ");
    try writeMessageTypeReference(type_name, writer);
    try writer.writeAll(".decode(allocator, ");
    try writer.writeAll(payload_expr);
    try writer.writeAll(");\n");
    try indent(writer, depth);
    try writer.writeAll("defer nested.deinit(allocator);\n");
    try indent(writer, depth);
    try writer.writeAll("try nested.validateRequiredRecursive(allocator);\n");
}

fn oneofHasMessageField(message: *const schema.MessageDescriptor, oneof_name: []const u8) bool {
    for (message.fields.items) |*field| {
        if (field.oneof_name) |name| {
            if (std.mem.eql(u8, name, oneof_name) and (field.kind == .message or field.kind == .group)) return true;
        }
    }
    return false;
}

fn codegenCanReferenceMessage(file: *const schema.FileDescriptor, type_name: []const u8) bool {
    return file.findMessageDeep(type_name) != null;
}

fn writeMessageTypeReference(type_name: []const u8, writer: *std.Io.Writer) Error!void {
    const trimmed = if (std.mem.startsWith(u8, type_name, ".")) type_name[1..] else type_name;
    const leaf = if (std.mem.lastIndexOfScalar(u8, trimmed, '.')) |idx| trimmed[idx + 1 ..] else trimmed;
    try writeQuotedIdent(leaf, writer);
}

fn writeDecode(file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) !@This() {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var self = @This().init();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer self.deinit(allocator);\n");
    for (message.fields.items) |*field| try writeRepeatedListDecl(field, writer, depth + 1);
    if (!messageDecodeUsesAllocator(message)) {
        try indent(writer, depth + 1);
        try writer.writeAll("_ = allocator;\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("var r = pbz.Reader.init(bytes);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("while (try r.nextTag()) |tag| {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("switch (tag.number) {\n");
    for (message.fields.items) |*field| try writeDecodeField(file, field, writer, depth + 3);
    try indent(writer, depth + 3);
    try writer.writeAll("else => try r.skipValue(tag),\n");
    try indent(writer, depth + 2);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    for (message.fields.items) |*field| try writeRepeatedAssign(field, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("return self;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn messageHasRepeatedOrMap(message: *const schema.MessageDescriptor) bool {
    for (message.fields.items) |field| {
        if (field.cardinality == .repeated or field.kind == .map) return true;
    }
    return false;
}

fn messageDecodeUsesAllocator(message: *const schema.MessageDescriptor) bool {
    if (messageHasRepeatedOrMap(message)) return true;
    for (message.fields.items) |field| {
        if (field.oneof_name == null and field.cardinality != .repeated and (field.kind == .message or field.kind == .group)) return true;
    }
    return false;
}

fn writeDecodeInitialized(writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn decodeInitialized(allocator: std.mem.Allocator, bytes: []const u8) !@This() {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var self = try @This().decode(allocator, bytes);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer self.deinit(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.validateRequiredRecursive(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return self;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeRepeatedListDecl(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.cardinality != .repeated and field.kind != .map) return;
    try indent(writer, depth);
    try writer.writeAll("var ");
    try writeQuotedIdentWithSuffix(field.name, "_list", writer);
    try writer.writeAll(": std.ArrayList(");
    try writeRepeatedElementType(field.*, writer);
    try writer.writeAll(") = .empty;\n");
    try indent(writer, depth);
    try writer.writeAll("defer ");
    try writeQuotedIdentWithSuffix(field.name, "_list", writer);
    try writer.writeAll(".deinit(allocator);\n");
}

fn writeRepeatedAssign(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.cardinality != .repeated and field.kind != .map) return;
    try indent(writer, depth);
    try writer.writeAll("self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = try ");
    try writeQuotedIdentWithSuffix(field.name, "_list", writer);
    try writer.writeAll(".toOwnedSlice(allocator);\n");
}

fn writeRepeatedElementType(field: schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    switch (field.kind) {
        .scalar => |scalar| try writer.writeAll(scalarZigType(scalar)),
        .enumeration => try writer.writeAll("i32"),
        .message, .group => try writer.writeAll("[]const u8"),
        .map => try writeQuotedIdentWithSuffix(field.name, "Entry", writer),
    }
}

fn writeDecodeField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    switch (field.kind) {
        .scalar => |scalar| try writeDecodeScalarField(file, field, scalar, writer, depth),
        .enumeration => try writeDecodeEnumField(file, field, writer, depth),
        .message, .group => try writeDecodeMessageField(file, field, writer, depth),
        .map => try writeDecodeMapField(file, field, writer, depth),
    }
}

fn writeDecodeScalarField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.print("{d} => ", .{field.number});
    if (field.cardinality == .repeated) {
        if (scalar.packable()) {
            try writeDecodePackedScalarField(field, scalar, writer, depth);
        } else {
            if (scalar == .string and fieldUtf8Validation(file, field) == .verify) {
                try writer.writeAll("{ const value = try r.readBytes(); if (!std.unicode.utf8ValidateSlice(value)) return error.InvalidUtf8; ");
                try writeRepeatedAppendPrefix(field, writer);
                try writer.writeAll("value); },\n");
            } else {
                try writeRepeatedAppendPrefix(field, writer);
                try writer.print("try r.{s}()),\n", .{scalarReaderName(scalar)});
            }
        }
    } else if (field.oneof_name != null) {
        try writeOneofDecodeAssign(file, field, scalarReaderName(scalar), writer);
    } else {
        try writer.writeAll("{ self.");
        try writeQuotedIdent(field.name, writer);
        try writer.print(" = try r.{s}();", .{scalarReaderName(scalar)});
        if (scalar == .string and fieldUtf8Validation(file, field) == .verify) {
            try writer.writeAll(" if (!std.unicode.utf8ValidateSlice(self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(")) return error.InvalidUtf8;");
        }
        try writeSetPresence(file, field, writer);
        try writer.writeAll(" },\n");
    }
}

fn writeDecodeEnumField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.print("{d} => ", .{field.number});
    if (field.cardinality == .repeated) {
        try writeDecodePackedEnumField(file, field, writer, depth);
    } else if (field.oneof_name != null) {
        try writeOneofEnumDecodeAssign(file, field, writer);
    } else {
        try writer.writeAll("{ const value = try r.readInt32();");
        try writeEnumClosedCheck(file, field, "value", writer);
        try writer.writeAll(" self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = value;");
        try writeSetPresence(file, field, writer);
        try writer.writeAll(" },\n");
    }
}

fn writeDecodeMessageField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.print("{d} => ", .{field.number});
    if (field.cardinality == .repeated) {
        try writeRepeatedAppendPrefix(field, writer);
        try writeMessagePayloadRead(file, field, "r", writer);
        try writer.writeAll("),\n");
    } else if (field.oneof_name != null) {
        try writeOneofMessageDecodeAssign(file, field, writer);
    } else {
        try writer.writeAll("{ const payload = ");
        try writeMessagePayloadRead(file, field, "r", writer);
        try writer.writeAll("; if (self.");
        try writePresenceIdent(field.name, writer);
        try writer.writeAll(" and self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(".len != 0 and payload.len != 0) { const owned_allocator = try self.@\"_pbzOwnedAllocator\"(allocator); const merged = try owned_allocator.alloc(u8, self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(".len + payload.len); @memcpy(merged[0..self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(".len], self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll("); @memcpy(merged[self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(".len..], payload); self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = merged; } else if (!self.");
        try writePresenceIdent(field.name, writer);
        try writer.writeAll(" or self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(".len == 0) { self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = payload; }");
        try writer.writeAll(" self.");
        try writePresenceIdent(field.name, writer);
        try writer.writeAll(" = true;");
        try writer.writeAll(" },\n");
    }
}

fn writeDecodePackedScalarField(field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
    try writer.writeAll("{\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (tag.wire_type == .length_delimited) {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("var packed_reader = pbz.Reader.init(try r.readBytes());\n");
    try indent(writer, depth + 2);
    try writer.writeAll("while (!packed_reader.eof()) try ");
    try writeQuotedIdentWithSuffix(field.name, "_list", writer);
    try writer.print(".append(allocator, try packed_reader.{s}());\n", .{scalarReaderName(scalar)});
    try indent(writer, depth + 1);
    try writer.writeAll("} else {\n");
    try indent(writer, depth + 2);
    try writeRepeatedAppendPrefix(field, writer);
    try writer.print("try r.{s}());\n", .{scalarReaderName(scalar)});
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth);
    try writer.writeAll("},\n");
}

fn writeDecodePackedEnumField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try writer.writeAll("{\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (tag.wire_type == .length_delimited) {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("var packed_reader = pbz.Reader.init(try r.readBytes());\n");
    try indent(writer, depth + 2);
    try writer.writeAll("while (!packed_reader.eof()) { const value = try packed_reader.readInt32();");
    try writeEnumClosedCheck(file, field, "value", writer);
    try writer.writeAll(" try ");
    try writeQuotedIdentWithSuffix(field.name, "_list", writer);
    try writer.writeAll(".append(allocator, value); }\n");
    try indent(writer, depth + 1);
    try writer.writeAll("} else {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("{ const value = try r.readInt32();");
    try writeEnumClosedCheck(file, field, "value", writer);
    try writer.writeAll(" try ");
    try writeQuotedIdentWithSuffix(field.name, "_list", writer);
    try writer.writeAll(".append(allocator, value); }\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth);
    try writer.writeAll("},\n");
}

fn writeDecodeMapField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const map_type = switch (field.kind) {
        .map => |map| map,
        else => return,
    };
    try indent(writer, depth);
    try writer.print("{d} => {{\n", .{field.number});
    try indent(writer, depth + 1);
    try writer.writeAll("var entry = ");
    try writeQuotedIdentWithSuffix(field.name, "Entry", writer);
    try writer.writeAll("{};\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var entry_reader = pbz.Reader.init(try r.readBytes());\n");
    try indent(writer, depth + 1);
    try writer.writeAll("while (try entry_reader.nextTag()) |entry_tag| {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("switch (entry_tag.number) {\n");
    try writeMapEntryDecodeAssign(file, field, "entry.key", 1, .{ .scalar = map_type.key }, writer, depth + 3);
    try writeMapEntryDecodeAssign(file, field, "entry.value", 2, map_type.value.*, writer, depth + 3);
    try indent(writer, depth + 3);
    try writer.writeAll("else => try entry_reader.skipValue(entry_tag),\n");
    try indent(writer, depth + 2);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try ");
    try writeQuotedIdentWithSuffix(field.name, "_list", writer);
    try writer.writeAll(".append(allocator, entry);\n");
    try indent(writer, depth);
    try writer.writeAll("},\n");
}

fn writeMapEntryDecodeAssign(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, target: []const u8, number: u29, kind: schema.FieldKind, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    if (kind == .scalar and kind.scalar == .string and fieldUtf8Validation(file, field) == .verify) {
        try writer.print("{d} => {{ const value = ", .{number});
        try writeEntryReadExpr(kind, "entry_reader", writer);
        try writer.writeAll("; if (!std.unicode.utf8ValidateSlice(value)) return error.InvalidUtf8; ");
        try writer.writeAll(target);
        try writer.writeAll(" = value; },\n");
    } else if (kind == .enumeration and enumIsClosed(file, kind.enumeration)) {
        try writer.print("{d} => {{ const value = ", .{number});
        try writeEntryReadExpr(kind, "entry_reader", writer);
        try writer.writeAll(";");
        try writeEnumClosedCheckByName(file, kind.enumeration, "value", writer);
        try writer.writeByte(' ');
        try writer.writeAll(target);
        try writer.writeAll(" = value; },\n");
    } else {
        try writer.print("{d} => {s} = ", .{ number, target });
        try writeEntryReadExpr(kind, "entry_reader", writer);
        try writer.writeAll(",\n");
    }
}

fn writeOneofDecodeAssign(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, reader_method: []const u8, writer: *std.Io.Writer) Error!void {
    const oneof_name = field.oneof_name orelse return;
    if (field.kind == .scalar and field.kind.scalar == .string and fieldUtf8Validation(file, field) == .verify) {
        try writer.writeAll("{ const value = try r.");
        try writer.writeAll(reader_method);
        try writer.writeAll("(); if (!std.unicode.utf8ValidateSlice(value)) return error.InvalidUtf8; self.");
        try writeQuotedIdent(oneof_name, writer);
        try writer.writeAll(" = .{ .");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = value }; },\n");
        return;
    }
    try writer.writeAll("self.");
    try writeQuotedIdent(oneof_name, writer);
    try writer.writeAll(" = .{ .");
    try writeQuotedIdent(field.name, writer);
    try writer.print(" = try r.{s}() }},\n", .{reader_method});
}

fn writeOneofMessageDecodeAssign(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    const oneof_name = field.oneof_name orelse return;
    try writer.writeAll("self.");
    try writeQuotedIdent(oneof_name, writer);
    try writer.writeAll(" = .{ .");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = ");
    try writeMessagePayloadRead(file, field, "r", writer);
    try writer.writeAll(" },\n");
}

fn writeOneofEnumDecodeAssign(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    const oneof_name = field.oneof_name orelse return;
    try writer.writeAll("{ const value = try r.readInt32();");
    try writeEnumClosedCheck(file, field, "value", writer);
    try writer.writeAll(" self.");
    try writeQuotedIdent(oneof_name, writer);
    try writer.writeAll(" = .{ .");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = value }; },\n");
}

fn writeEnumClosedCheck(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    const enum_name = switch (field.kind) {
        .enumeration => |name| name,
        else => return,
    };
    try writeEnumClosedCheckByName(file, enum_name, value_expr, writer);
}

fn writeEnumClosedCheckByName(file: *const schema.FileDescriptor, enum_name: []const u8, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    if (!enumIsClosed(file, enum_name)) return;
    try writer.writeAll(" if (");
    if (file.findEnumDeep(enum_name)) |enumeration| {
        for (enumeration.values.items, 0..) |value, i| {
            if (i != 0) try writer.writeAll(" and ");
            try writer.print("{s} != {d}", .{ value_expr, value.number });
        }
    } else {
        try writer.writeAll("true");
    }
    try writer.writeAll(") return error.InvalidEnumValue;");
}

fn writeEntryReadExpr(kind: schema.FieldKind, reader_name: []const u8, writer: *std.Io.Writer) Error!void {
    switch (kind) {
        .scalar => |scalar| try writer.print("try {s}.{s}()", .{ reader_name, scalarReaderName(scalar) }),
        .enumeration => try writer.print("try {s}.readInt32()", .{reader_name}),
        .message => try writer.print("try {s}.readBytes()", .{reader_name}),
        else => try writer.writeAll("@compileError(\"unsupported map decode kind\")"),
    }
}

fn writeRepeatedAppendPrefix(field: *const schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("try ");
    try writeQuotedIdentWithSuffix(field.name, "_list", writer);
    try writer.writeAll(".append(allocator, ");
}

fn scalarReaderName(scalar: schema.ScalarType) []const u8 {
    return switch (scalar) {
        .double => "readDouble",
        .float => "readFloat",
        .int32 => "readInt32",
        .int64 => "readInt64",
        .uint32 => "readUInt32",
        .uint64 => "readUInt64",
        .sint32 => "readSInt32",
        .sint64 => "readSInt64",
        .fixed32 => "readFixed32",
        .fixed64 => "readFixed64",
        .sfixed32 => "readSFixed32",
        .sfixed64 => "readSFixed64",
        .bool => "readBool",
        .string, .bytes => "readBytes",
    };
}

fn writeEncodeField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    switch (field.kind) {
        .scalar => |scalar| try writeEncodeScalarField(file, field, scalar, writer, depth),
        .enumeration => try writeEncodeEnumField(file, field, writer, depth),
        .message => try writeEncodeMessageField(file, field, writer, depth),
        .group => try writeEncodeGroupField(field, writer, depth),
        .map => try writeEncodeMapField(file, field, writer, depth),
    }
}

fn writeEncodeScalarField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.cardinality == .repeated) {
        if (field.resolvedPacked(file)) {
            try writeEncodePackedScalarField(field, scalar, writer, depth);
        } else {
            try indent(writer, depth);
            if (scalar == .string and fieldUtf8Validation(file, field) == .verify) {
                try writer.writeAll("for (self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(") |item| { if (!std.unicode.utf8ValidateSlice(item)) return error.InvalidUtf8; ");
                try writeScalarWriteCall(field.number, scalar, "item", writer);
                try writer.writeAll("); }\n");
            } else {
                try writer.writeAll("for (self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(") |item| ");
                try writeScalarWriteCall(field.number, scalar, "item", writer);
                try writer.writeAll(");\n");
            }
        }
    } else {
        try indent(writer, depth);
        if (hasPresence(file, field.*)) {
            try writer.writeAll("if (self.");
            try writePresenceIdent(field.name, writer);
            try writer.writeAll(") ");
        } else if (shouldSkipDefault(scalar)) {
            try writer.writeAll("if (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(defaultSkipCondition(scalar));
        }
        if (scalar == .string and fieldUtf8Validation(file, field) == .verify) {
            try writer.writeAll("{ if (!std.unicode.utf8ValidateSlice(self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(")) return error.InvalidUtf8; ");
        }
        try writeScalarWriteCall(field.number, scalar, "self.", writer);
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(")");
        if (scalar == .string and fieldUtf8Validation(file, field) == .verify) try writer.writeAll("; }\n") else try writer.writeAll(";\n");
    }
}

fn writeEncodeEnumField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.cardinality == .repeated) {
        if (field.resolvedPacked(file)) {
            try writeEncodePackedEnumField(field, writer, depth);
        } else {
            try indent(writer, depth);
            try writer.writeAll("for (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.print(") |item| try w.writeInt32({d}, item);\n", .{field.number});
        }
    } else {
        try indent(writer, depth);
        if (hasPresence(file, field.*)) {
            try writer.writeAll("if (self.");
            try writePresenceIdent(field.name, writer);
            try writer.writeAll(") ");
        } else {
            try writer.writeAll("if (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(" != 0) ");
        }
        try writer.print("try w.writeInt32({d}, self.", .{field.number});
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(");\n");
    }
}

fn writeEncodePackedScalarField(field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
    try writeEncodePackedPrefix(field, writer, depth);
    try indent(writer, depth + 1);
    try writer.writeAll("for (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(") |item| ");
    try writePackedScalarPayload(scalar, "item", writer);
    try writer.writeAll(";\n");
    try writeEncodePackedSuffix(field, writer, depth);
}

fn writeEncodePackedEnumField(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try writeEncodePackedPrefix(field, writer, depth);
    try indent(writer, depth + 1);
    try writer.writeAll("for (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(") |item| ");
    try writePackedEnumPayload("item", writer);
    try writer.writeAll(";\n");
    try writeEncodePackedSuffix(field, writer, depth);
}

fn writeEncodePackedPrefix(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("if (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".len != 0) {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var packed_writer = pbz.Writer.init(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("defer packed_writer.deinit();\n");
}

fn writeEncodePackedSuffix(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth + 1);
    try writer.print("try w.writeBytes({d}, packed_writer.slice());\n", .{field.number});
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writePackedScalarPayload(scalar: schema.ScalarType, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .double => try writer.print("try packed_writer.writeRawLittle(u64, @bitCast({s}))", .{value_expr}),
        .float => try writer.print("try packed_writer.writeRawLittle(u32, @bitCast({s}))", .{value_expr}),
        .int32 => try writer.print("try packed_writer.writeVarint(@as(u64, @bitCast(@as(i64, {s}))))", .{value_expr}),
        .int64 => try writer.print("try packed_writer.writeVarint(@as(u64, @bitCast({s})))", .{value_expr}),
        .uint32 => try writer.print("try packed_writer.writeVarint({s})", .{value_expr}),
        .uint64 => try writer.print("try packed_writer.writeVarint({s})", .{value_expr}),
        .sint32 => try writer.print("try packed_writer.writeVarint(pbz.wire.zigZagEncode32({s}))", .{value_expr}),
        .sint64 => try writer.print("try packed_writer.writeVarint(pbz.wire.zigZagEncode64({s}))", .{value_expr}),
        .fixed32 => try writer.print("try packed_writer.writeRawLittle(u32, {s})", .{value_expr}),
        .fixed64 => try writer.print("try packed_writer.writeRawLittle(u64, {s})", .{value_expr}),
        .sfixed32 => try writer.print("try packed_writer.writeRawLittle(i32, {s})", .{value_expr}),
        .sfixed64 => try writer.print("try packed_writer.writeRawLittle(i64, {s})", .{value_expr}),
        .bool => try writer.print("try packed_writer.writeVarint(@as(u64, if ({s}) 1 else 0))", .{value_expr}),
        .string, .bytes => try writer.writeAll("@compileError(\"non-packable scalar\")"),
    }
}

fn writePackedEnumPayload(value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.print("try packed_writer.writeVarint(@as(u64, @bitCast(@as(i64, {s}))))", .{value_expr});
}

fn writeEncodeMessageField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        if (fieldMessageEncoding(file, field) == .delimited) {
            try writer.writeAll("for (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.print(") |item| {{ try w.writeTag({d}, .start_group); try w.appendSlice(item); try w.writeTag({d}, .end_group); }}\n", .{ field.number, field.number });
        } else {
            try writer.writeAll("for (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.print(") |item| try w.writeMessage({d}, item);\n", .{field.number});
        }
    } else {
        try indent(writer, depth);
        if (fieldMessageEncoding(file, field) == .delimited) {
            try writer.writeAll("if (self.");
            if (hasPresence(file, field.*)) {
                try writePresenceIdent(field.name, writer);
                try writer.writeAll(") { ");
            } else {
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(".len != 0) { ");
            }
            try writer.print("try w.writeTag({d}, .start_group); try w.appendSlice(self.", .{field.number});
            try writeQuotedIdent(field.name, writer);
            try writer.print("); try w.writeTag({d}, .end_group); }}\n", .{field.number});
        } else {
            try writer.writeAll("if (self.");
            if (hasPresence(file, field.*)) {
                try writePresenceIdent(field.name, writer);
                try writer.writeAll(") ");
            } else {
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(".len != 0) ");
            }
            try writer.print("try w.writeMessage({d}, self.", .{field.number});
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(");\n");
        }
    }
}

fn writeEncodeGroupField(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        try writer.writeAll("for (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.print(") |item| {{ try w.writeTag({d}, .start_group); try w.appendSlice(item); try w.writeTag({d}, .end_group); }}\n", .{ field.number, field.number });
    } else {
        try indent(writer, depth);
        try writer.writeAll("if (self.");
        try writePresenceIdent(field.name, writer);
        try writer.print(") {{ try w.writeTag({d}, .start_group); try w.appendSlice(self.", .{field.number});
        try writeQuotedIdent(field.name, writer);
        try writer.print("); try w.writeTag({d}, .end_group); }}\n", .{field.number});
    }
}

fn writeEncodeMapField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const map_type = switch (field.kind) {
        .map => |map| map,
        else => return,
    };
    try indent(writer, depth);
    try writer.writeAll("for (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(") |entry| {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var entry_writer = pbz.Writer.init(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("defer entry_writer.deinit();\n");
    try writeMapEntryEncodeUtf8Check(file, field, "entry.key", .{ .scalar = map_type.key }, writer, depth + 1);
    try indent(writer, depth + 1);
    try writeKindWriteCall(1, .{ .scalar = map_type.key }, "entry.key", "entry_writer", writer);
    try writer.writeAll(");\n");
    try writeMapEntryEncodeUtf8Check(file, field, "entry.value", map_type.value.*, writer, depth + 1);
    try indent(writer, depth + 1);
    try writeKindWriteCall(2, map_type.value.*, "entry.value", "entry_writer", writer);
    try writer.writeAll(");\n");
    try indent(writer, depth + 1);
    try writer.print("try w.writeMessage({d}, entry_writer.slice());\n", .{field.number});
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeEncodeMapFieldDeterministic(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const map_type = switch (field.kind) {
        .map => |map| map,
        else => return,
    };
    try indent(writer, depth);
    try writer.writeAll("if (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".len != 0) {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const entries = try allocator.dupe(");
    try writeQuotedIdentWithSuffix(field.name, "Entry", writer);
    try writer.writeAll(", self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(");\n");
    try indent(writer, depth + 1);
    try writer.writeAll("defer allocator.free(entries);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("std.mem.sort(");
    try writeQuotedIdentWithSuffix(field.name, "Entry", writer);
    try writer.writeAll(", entries, {}, struct { fn lessThan(_: void, a: ");
    try writeQuotedIdentWithSuffix(field.name, "Entry", writer);
    try writer.writeAll(", b: ");
    try writeQuotedIdentWithSuffix(field.name, "Entry", writer);
    try writer.writeAll(") bool { return ");
    try writeMapKeyLessExpr(map_type.key, "a.key", "b.key", writer);
    try writer.writeAll("; } }.lessThan);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("for (entries) |entry| {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("var entry_writer = pbz.Writer.init(allocator);\n");
    try indent(writer, depth + 2);
    try writer.writeAll("defer entry_writer.deinit();\n");
    try writeMapEntryEncodeUtf8Check(file, field, "entry.key", .{ .scalar = map_type.key }, writer, depth + 2);
    try indent(writer, depth + 2);
    try writeKindWriteCall(1, .{ .scalar = map_type.key }, "entry.key", "entry_writer", writer);
    try writer.writeAll(");\n");
    try writeMapEntryEncodeUtf8Check(file, field, "entry.value", map_type.value.*, writer, depth + 2);
    try indent(writer, depth + 2);
    try writeKindWriteCall(2, map_type.value.*, "entry.value", "entry_writer", writer);
    try writer.writeAll(");\n");
    try indent(writer, depth + 2);
    try writer.print("try w.writeMessage({d}, entry_writer.slice());\n", .{field.number});
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeMapEntryEncodeUtf8Check(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, value_expr: []const u8, kind: schema.FieldKind, writer: *std.Io.Writer, depth: usize) Error!void {
    if (kind == .scalar and kind.scalar == .string and fieldUtf8Validation(file, field) == .verify) {
        try indent(writer, depth);
        try writer.print("if (!std.unicode.utf8ValidateSlice({s})) return error.InvalidUtf8;\n", .{value_expr});
    }
}

fn writeMapKeyLessExpr(scalar: schema.ScalarType, a: []const u8, b: []const u8, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .string => try writer.print("std.mem.lessThan(u8, {s}, {s})", .{ a, b }),
        .bool => try writer.print("!{s} and {s}", .{ a, b }),
        .int32, .int64, .uint32, .uint64, .sint32, .sint64, .fixed32, .fixed64, .sfixed32, .sfixed64 => try writer.print("{s} < {s}", .{ a, b }),
        .double, .float, .bytes => try writer.writeAll("false"),
    }
}

fn writeKindWriteCall(number: u29, kind: schema.FieldKind, value_expr: []const u8, writer_name: []const u8, writer: *std.Io.Writer) Error!void {
    switch (kind) {
        .scalar => |scalar| try writer.print("try {s}.{s}({d}, {s}", .{ writer_name, scalarWriterName(scalar), number, value_expr }),
        .enumeration => try writer.print("try {s}.writeInt32({d}, {s}", .{ writer_name, number, value_expr }),
        .message => try writer.print("try {s}.writeMessage({d}, {s}", .{ writer_name, number, value_expr }),
        else => try writer.writeAll("@compileError(\"unsupported map field kind\")"),
    }
}

fn writeMessagePayloadRead(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, reader_name: []const u8, writer: *std.Io.Writer) Error!void {
    if (field.kind == .group) {
        try writer.print("try {s}.readGroupBytes({d})", .{ reader_name, field.number });
        return;
    }
    if (fieldMessageEncoding(file, field) == .delimited) {
        try writer.print("try {s}.readGroupBytes({d})", .{ reader_name, field.number });
    } else {
        try writer.print("try {s}.readBytes()", .{reader_name});
    }
}

fn fieldMessageEncoding(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor) schema.FeatureSet.MessageEncoding {
    if (field.features) |features| return features.message_encoding;
    return file.features.message_encoding;
}

fn fieldUtf8Validation(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor) schema.FeatureSet.Utf8Validation {
    if (field.features) |features| return features.utf8_validation;
    return file.features.utf8_validation;
}

fn writeScalarWriteCall(number: u29, scalar: schema.ScalarType, prefix: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.print("try w.{s}({d}, {s}", .{ scalarWriterName(scalar), number, prefix });
}

fn shouldSkipDefault(scalar: schema.ScalarType) bool {
    _ = scalar;
    return true;
}

fn defaultSkipCondition(scalar: schema.ScalarType) []const u8 {
    return switch (scalar) {
        .string, .bytes => ".len != 0) ",
        .bool => ") ",
        else => " != 0) ",
    };
}

fn scalarWriterName(scalar: schema.ScalarType) []const u8 {
    return switch (scalar) {
        .double => "writeDouble",
        .float => "writeFloat",
        .int32 => "writeInt32",
        .int64 => "writeInt64",
        .uint32 => "writeUInt32",
        .uint64 => "writeUInt64",
        .sint32 => "writeSInt32",
        .sint64 => "writeSInt64",
        .fixed32 => "writeFixed32",
        .fixed64 => "writeFixed64",
        .sfixed32 => "writeSFixed32",
        .sfixed64 => "writeSFixed64",
        .bool => "writeBool",
        .string => "writeString",
        .bytes => "writeBytes",
    };
}

fn writeFieldType(field: schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    if (field.kind == .map) {
        try writer.writeAll("[]const ");
        try writeQuotedIdentWithSuffix(field.name, "Entry", writer);
        return;
    }
    try writer.writeAll(fieldType(field));
}

fn writeFieldKindType(kind: schema.FieldKind, writer: *std.Io.Writer) Error!void {
    switch (kind) {
        .scalar => |scalar| try writer.writeAll(scalarZigType(scalar)),
        .enumeration => try writer.writeAll("i32"),
        .message, .group => try writer.writeAll("[]const u8"),
        else => try writer.writeAll("void"),
    }
}

fn fieldType(field: schema.FieldDescriptor) []const u8 {
    const base = switch (field.kind) {
        .scalar => |scalar| scalarZigType(scalar),
        .enumeration => "i32",
        .message, .group => "[]const u8",
        else => "void",
    };
    if (field.cardinality != .repeated) return base;
    return switch (field.kind) {
        .scalar => |scalar| repeatedScalarZigType(scalar),
        .enumeration => "[]const i32",
        .message, .group => "[]const []const u8",
        else => "[]const void",
    };
}

fn repeatedScalarZigType(scalar: schema.ScalarType) []const u8 {
    return switch (scalar) {
        .string, .bytes => "[]const []const u8",
        else => repeatedPrefix(scalarZigType(scalar)),
    };
}

fn repeatedPrefix(base: []const u8) []const u8 {
    if (std.mem.eql(u8, base, "f64")) return "[]const f64";
    if (std.mem.eql(u8, base, "f32")) return "[]const f32";
    if (std.mem.eql(u8, base, "i32")) return "[]const i32";
    if (std.mem.eql(u8, base, "i64")) return "[]const i64";
    if (std.mem.eql(u8, base, "u32")) return "[]const u32";
    if (std.mem.eql(u8, base, "u64")) return "[]const u64";
    if (std.mem.eql(u8, base, "bool")) return "[]const bool";
    return "[]const void";
}

fn scalarZigType(scalar: schema.ScalarType) []const u8 {
    return switch (scalar) {
        .double => "f64",
        .float => "f32",
        .int32, .sint32, .sfixed32 => "i32",
        .int64, .sint64, .sfixed64 => "i64",
        .uint32, .fixed32 => "u32",
        .uint64, .fixed64 => "u64",
        .bool => "bool",
        .string, .bytes => "[]const u8",
    };
}

fn writeFieldDefault(field: schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    if (field.cardinality == .repeated or field.kind == .map) return writer.writeAll("&.{}");
    try writeFieldKindDefault(field.kind, field.default_value, writer);
}

fn writeFieldKindDefault(kind: schema.FieldKind, default_value: ?schema.OptionValue, writer: *std.Io.Writer) Error!void {
    switch (kind) {
        .scalar => |scalar| try writeScalarDefault(scalar, default_value, writer),
        .enumeration => try writeIntDefault(i32, default_value, writer),
        .message, .group => try writer.writeAll("\"\""),
        else => try writer.writeAll("{}"),
    }
}

fn writeScalarDefault(scalar: schema.ScalarType, default_value: ?schema.OptionValue, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .double => try writeFloatDefault(f64, default_value, writer),
        .float => try writeFloatDefault(f32, default_value, writer),
        .int32, .sint32, .sfixed32 => try writeIntDefault(i32, default_value, writer),
        .int64, .sint64, .sfixed64 => try writeIntDefault(i64, default_value, writer),
        .uint32, .fixed32 => try writeIntDefault(u32, default_value, writer),
        .uint64, .fixed64 => try writeIntDefault(u64, default_value, writer),
        .bool => try writeBoolDefault(default_value, writer),
        .string, .bytes => try writeBytesDefault(default_value, writer),
    }
}

fn writeIntDefault(comptime T: type, default_value: ?schema.OptionValue, writer: *std.Io.Writer) Error!void {
    const value = optionInt(T, default_value) orelse 0;
    try writer.print("{d}", .{value});
}

fn writeFloatDefault(comptime T: type, default_value: ?schema.OptionValue, writer: *std.Io.Writer) Error!void {
    const value = optionFloat(T, default_value) orelse 0;
    if (std.math.isNan(value)) {
        try writer.print("std.math.nan({s})", .{scalarZigTypeName(T)});
    } else if (std.math.isPositiveInf(value)) {
        try writer.print("std.math.inf({s})", .{scalarZigTypeName(T)});
    } else if (std.math.isNegativeInf(value)) {
        try writer.print("-std.math.inf({s})", .{scalarZigTypeName(T)});
    } else {
        try writer.print("{d}", .{value});
    }
}

fn scalarZigTypeName(comptime T: type) []const u8 {
    return if (T == f32) "f32" else "f64";
}

fn writeBoolDefault(default_value: ?schema.OptionValue, writer: *std.Io.Writer) Error!void {
    const value = optionBool(default_value) orelse false;
    try writer.writeAll(if (value) "true" else "false");
}

fn writeBytesDefault(default_value: ?schema.OptionValue, writer: *std.Io.Writer) Error!void {
    const value = optionText(default_value) orelse "";
    try writeZigStringLiteral(value, writer);
}

fn optionText(default_value: ?schema.OptionValue) ?[]const u8 {
    const value = default_value orelse return null;
    return switch (value) {
        .string, .identifier => |text| text,
        else => null,
    };
}

fn optionBool(default_value: ?schema.OptionValue) ?bool {
    const value = default_value orelse return null;
    return schema.optionAsBool(value);
}

fn optionInt(comptime T: type, default_value: ?schema.OptionValue) ?T {
    const value = default_value orelse return null;
    return switch (value) {
        .integer => |v| if (v >= std.math.minInt(T) and v <= std.math.maxInt(T)) @intCast(v) else null,
        .identifier, .string => |text| std.fmt.parseInt(T, text, 10) catch null,
        else => null,
    };
}

fn optionFloat(comptime T: type, default_value: ?schema.OptionValue) ?T {
    const value = default_value orelse return null;
    return switch (value) {
        .float => |v| @floatCast(v),
        .integer => |v| @floatFromInt(v),
        .identifier, .string => |text| std.fmt.parseFloat(T, text) catch null,
        else => null,
    };
}

fn writeZigStringLiteral(value: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeByte('"');
    for (value) |c| {
        switch (c) {
            '\\' => try writer.writeAll("\\\\"),
            '"' => try writer.writeAll("\\\""),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            0 => try writer.writeAll("\\x00"),
            0x01...0x08, 0x0b, 0x0c, 0x0e...0x1f, 0x7f...0xff => try writer.print("\\x{x:0>2}", .{c}),
            else => try writer.writeByte(c),
        }
    }
    try writer.writeByte('"');
}

fn writeZigLowerCamelStringLiteral(value: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeByte('"');
    try writeLowerCamelEscaped(value, writer);
    try writer.writeByte('"');
}

fn writeJsonFieldNameLiteralContents(field: *const schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    if (field.json_name) |json_name| {
        try writeEscapedStringContents(json_name, writer);
    } else {
        try writeLowerCamelEscaped(field.name, writer);
    }
}

fn writeLowerCamelEscaped(value: []const u8, writer: *std.Io.Writer) Error!void {
    var upper_next = false;
    for (value) |c| {
        if (c == '_') {
            upper_next = true;
            continue;
        }
        const out = if (upper_next) std.ascii.toUpper(c) else c;
        upper_next = false;
        try writeEscapedStringChar(out, writer);
    }
}

fn writeEscapedStringContents(value: []const u8, writer: *std.Io.Writer) Error!void {
    for (value) |c| try writeEscapedStringChar(c, writer);
}

fn writeEscapedStringChar(c: u8, writer: *std.Io.Writer) Error!void {
    switch (c) {
        '\\' => try writer.writeAll("\\\\"),
        '"' => try writer.writeAll("\\\""),
        '\n' => try writer.writeAll("\\n"),
        '\r' => try writer.writeAll("\\r"),
        '\t' => try writer.writeAll("\\t"),
        0 => try writer.writeAll("\\x00"),
        0x01...0x08, 0x0b, 0x0c, 0x0e...0x1f, 0x7f...0xff => try writer.print("\\x{x:0>2}", .{c}),
        else => try writer.writeByte(c),
    }
}

fn writeTextMethods(file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn formatTextAlloc(self: @This(), allocator: std.mem.Allocator) ![]u8 {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var out: std.Io.Writer.Allocating = .init(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer out.deinit();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.formatTextWithAllocator(allocator, &out.writer);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try out.toOwnedSlice();\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn formatText(self: @This(), writer: *std.Io.Writer) !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.formatTextWithAllocator(std.heap.page_allocator, writer);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn formatTextWithAllocator(self: @This(), allocator: std.mem.Allocator, writer: *std.Io.Writer) !void {\n");
    if (!messageTextUsesAllocator(file, message)) {
        try indent(writer, depth + 1);
        try writer.writeAll("_ = allocator;\n");
    }
    if (!messageTextHasFields(file, message)) {
        try indent(writer, depth + 1);
        try writer.writeAll("_ = self; _ = writer;\n");
    } else {
        for (message.fields.items) |*field| {
            if (field.oneof_name == null) try writeTextField(file, field, writer, depth + 1);
        }
        for (message.oneofs.items) |oneof| {
            if (oneofHasTextField(file, message, oneof.name)) try writeTextOneof(file, message, oneof, writer, depth + 1);
        }
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try writer.writeAll("\n");
    try writeTextParseMethods(file, message, writer, depth);
}

fn messageTextHasFields(file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor) bool {
    for (message.fields.items) |field| {
        if (field.oneof_name == null and textFieldSupported(file, field)) return true;
    }
    for (message.oneofs.items) |oneof| {
        if (oneofHasTextField(file, message, oneof.name)) return true;
    }
    return false;
}

fn messageTextUsesAllocator(file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor) bool {
    for (message.fields.items) |field| {
        if (field.kind == .message or field.kind == .group) return true;
        if (field.kind == .map and textMapValueUsesAllocator(file, field.kind.map.value.*)) return true;
    }
    return false;
}

fn textMapValueUsesAllocator(file: *const schema.FileDescriptor, kind: schema.FieldKind) bool {
    return switch (kind) {
        .message, .group => |name| codegenCanReferenceMessage(file, name),
        else => false,
    };
}

fn textFieldSupported(file: *const schema.FileDescriptor, field: schema.FieldDescriptor) bool {
    return switch (field.kind) {
        .scalar, .enumeration => true,
        .message, .group => |name| codegenCanReferenceMessage(file, name),
        .map => |map_type| textMapValueSupported(file, map_type.value.*),
    };
}

fn textMapValueSupported(file: *const schema.FileDescriptor, kind: schema.FieldKind) bool {
    return switch (kind) {
        .scalar, .enumeration => true,
        .message => |name| codegenCanReferenceMessage(file, name),
        else => false,
    };
}

fn oneofHasTextField(file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor, oneof_name: []const u8) bool {
    for (message.fields.items) |field| {
        if (field.oneof_name) |name| {
            if (std.mem.eql(u8, name, oneof_name) and textFieldSupported(file, field)) return true;
        }
    }
    return false;
}

fn writeTextField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    switch (field.kind) {
        .scalar => |scalar| try writeTextScalarField(file, field, scalar, writer, depth),
        .enumeration => try writeTextEnumField(file, field, writer, depth),
        .message, .group => |name| try writeTextMessageField(file, field, name, writer, depth),
        .map => try writeTextMapField(file, field, writer, depth),
    }
}

fn writeTextScalarField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        try writer.writeAll("for (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(") |value| { ");
        try writeTextFieldPrefix(field, writer);
        try writeTextScalarValue(scalar, "value", writer);
        try writer.writeAll("; try writer.writeByte('\\n'); }\n");
    } else {
        try indent(writer, depth);
        if (hasPresence(file, field.*)) {
            try writer.writeAll("if (self.");
            try writePresenceIdent(field.name, writer);
            try writer.writeAll(") { ");
        } else {
            try writer.writeAll("if (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(defaultSkipCondition(scalar));
            try writer.writeAll("{ ");
        }
        try writeTextFieldPrefix(field, writer);
        try writer.writeAll("const value = self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll("; ");
        try writeTextScalarValue(scalar, "value", writer);
        try writer.writeAll("; try writer.writeByte('\\n'); }\n");
    }
}

fn writeTextEnumField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const enum_name = switch (field.kind) {
        .enumeration => |name| name,
        else => return,
    };
    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        try writer.writeAll("for (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(") |value| { ");
        try writeTextFieldPrefix(field, writer);
        try writeTextEnumValue(file, enum_name, "value", writer);
        try writer.writeAll("; try writer.writeByte('\\n'); }\n");
    } else {
        try indent(writer, depth);
        if (hasPresence(file, field.*)) {
            try writer.writeAll("if (self.");
            try writePresenceIdent(field.name, writer);
            try writer.writeAll(") { ");
        } else {
            try writer.writeAll("if (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(" != 0) { ");
        }
        try writeTextFieldPrefix(field, writer);
        try writer.writeAll("const value = self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll("; ");
        try writeTextEnumValue(file, enum_name, "value", writer);
        try writer.writeAll("; try writer.writeByte('\\n'); }\n");
    }
}

fn writeTextMessageField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, type_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    if (!codegenCanReferenceMessage(file, type_name)) return;
    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        try writer.writeAll("for (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(") |payload| {\n");
        try writeTextMessagePayload(field.name, type_name, "payload", writer, depth + 1);
        try indent(writer, depth);
        try writer.writeAll("}\n");
    } else {
        try indent(writer, depth);
        try writer.writeAll("if (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(".len != 0) {\n");
        try writeTextMessagePayload(field.name, type_name, "self.", writer, depth + 1);
        try indent(writer, depth);
        try writer.writeAll("}\n");
    }
}

fn writeTextMessagePayload(field_name: []const u8, type_name: []const u8, payload_expr: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("try writer.writeAll(\"");
    try writeEscapedStringContents(field_name, writer);
    try writer.writeAll(" {\\n\");\n");
    try indent(writer, depth);
    try writer.writeAll("var nested = try ");
    try writeMessageTypeReference(type_name, writer);
    try writer.writeAll(".decode(allocator, ");
    try writer.writeAll(payload_expr);
    if (std.mem.eql(u8, payload_expr, "self.")) try writeQuotedIdent(field_name, writer);
    try writer.writeAll(");\n");
    try indent(writer, depth);
    try writer.writeAll("defer nested.deinit(allocator);\n");
    try indent(writer, depth);
    try writer.writeAll("try nested.formatTextWithAllocator(allocator, writer);\n");
    try indent(writer, depth);
    try writer.writeAll("try writer.writeAll(\"}\\n\");\n");
}

fn writeTextMapField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const map_type = switch (field.kind) {
        .map => |map_type| map_type,
        else => return,
    };
    if (!textMapValueSupported(file, map_type.value.*)) return;
    try indent(writer, depth);
    try writer.writeAll("for (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(") |entry| {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try writer.writeAll(\"");
    try writeEscapedStringContents(field.name, writer);
    try writer.writeAll(" {\\n\");\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try writer.writeAll(\"key: \"); ");
    try writeTextScalarValue(map_type.key, "entry.key", writer);
    try writer.writeAll("; try writer.writeByte('\\n');\n");
    try indent(writer, depth + 1);
    if (map_type.value.* == .message and codegenCanReferenceMessage(file, map_type.value.message)) {
        try writer.writeAll("try writer.writeAll(\"value {\\n\");\n");
        try indent(writer, depth + 1);
        try writer.writeAll("var nested = try ");
        try writeMessageTypeReference(map_type.value.message, writer);
        try writer.writeAll(".decode(allocator, entry.value);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("defer nested.deinit(allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try nested.formatTextWithAllocator(allocator, writer);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try writer.writeAll(\"}\\n\");\n");
    } else {
        try writer.writeAll("try writer.writeAll(\"value: \"); ");
        try writeTextMapValue(file, map_type.value.*, "entry.value", writer);
        try writer.writeAll("; try writer.writeByte('\\n');\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("try writer.writeAll(\"}\\n\");\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeTextOneof(file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor, oneof: schema.OneofDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("switch (self.");
    try writeQuotedIdent(oneof.name, writer);
    try writer.writeAll(") {\n");
    try indent(writer, depth + 1);
    try writer.writeAll(".none => {},\n");
    for (message.fields.items) |*field| {
        if (field.oneof_name) |name| {
            if (!std.mem.eql(u8, name, oneof.name) or !textFieldSupported(file, field.*)) continue;
            try indent(writer, depth + 1);
            try writer.writeAll(".");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(" => |value| {\n");
            switch (field.kind) {
                .scalar => |scalar| {
                    try indent(writer, depth + 2);
                    try writeTextFieldPrefix(field, writer);
                    try writeTextScalarValue(scalar, "value", writer);
                    try writer.writeAll("; try writer.writeByte('\\n');\n");
                },
                .enumeration => {
                    const enum_name = field.kind.enumeration;
                    try indent(writer, depth + 2);
                    try writeTextFieldPrefix(field, writer);
                    try writeTextEnumValue(file, enum_name, "value", writer);
                    try writer.writeAll("; try writer.writeByte('\\n');\n");
                },
                .message, .group => |type_name| try writeTextMessagePayload(field.name, type_name, "value", writer, depth + 2),
                else => {},
            }
            try indent(writer, depth + 1);
            try writer.writeAll("},\n");
        }
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeTextFieldPrefix(field: *const schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("try writer.writeAll(\"");
    try writeEscapedStringContents(field.name, writer);
    try writer.writeAll(": \"); ");
}

fn writeTextScalarValue(scalar: schema.ScalarType, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .string, .bytes => try writer.print("try std.json.Stringify.value({s}, .{{}}, writer)", .{value_expr}),
        .bool => try writer.print("try writer.writeAll(if ({s}) \"true\" else \"false\")", .{value_expr}),
        else => try writer.print("try writer.print(\"{{d}}\", .{{{s}}})", .{value_expr}),
    }
}

fn writeTextEnumValue(file: *const schema.FileDescriptor, enum_name: []const u8, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.print("try @This().textWriteEnum(writer, {s}", .{value_expr});
    try writer.writeAll(", ");
    try writeEnumNameArray(file, enum_name, writer);
    try writer.writeAll(", ");
    try writeEnumNumberArray(file, enum_name, writer);
    try writer.writeAll(")");
}

fn writeTextMapValue(file: *const schema.FileDescriptor, kind: schema.FieldKind, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    switch (kind) {
        .scalar => |scalar| try writeTextScalarValue(scalar, value_expr, writer),
        .enumeration => |name| try writeTextEnumValue(file, name, value_expr, writer),
        .message => |name| if (codegenCanReferenceMessage(file, name)) {
            try writer.writeAll("var nested = try ");
            try writeMessageTypeReference(name, writer);
            try writer.writeAll(".decode(allocator, ");
            try writer.writeAll(value_expr);
            try writer.writeAll("); defer nested.deinit(allocator); try nested.formatTextWithAllocator(allocator, writer)");
        } else try writer.writeAll("@compileError(\"unsupported map text value\")"),
        else => try writer.writeAll("@compileError(\"unsupported map text value\")"),
    }
}

fn writeJsonMethods(file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn jsonStringifyAlloc(self: @This(), allocator: std.mem.Allocator) ![]u8 {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var out: std.Io.Writer.Allocating = .init(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer out.deinit();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.jsonStringifyWithAllocator(allocator, &out.writer);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try out.toOwnedSlice();\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn jsonStringify(self: @This(), writer: *std.Io.Writer) !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.jsonStringifyWithAllocator(std.heap.page_allocator, writer);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn jsonStringifyWithAllocator(self: @This(), allocator: std.mem.Allocator, writer: *std.Io.Writer) !void {\n");
    if (!messageJsonStringifyUsesAllocator(message)) {
        try indent(writer, depth + 1);
        try writer.writeAll("_ = allocator;\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("try writer.writeAll(\"{\");\n");
    if (messageJsonStringifyHasFields(file, message)) {
        try indent(writer, depth + 1);
        try writer.writeAll("var first = true;\n");
        for (message.fields.items) |*field| {
            if (field.oneof_name == null) try writeJsonField(file, field, writer, depth + 1);
        }
        for (message.oneofs.items) |oneof| {
            if (oneofHasJsonField(file, message, oneof.name)) try writeJsonOneof(file, message, oneof, writer, depth + 1);
        }
    } else {
        try indent(writer, depth + 1);
        try writer.writeAll("_ = self;\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("try writer.writeAll(\"}\");\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try writer.writeAll("\n");
    try writeJsonParseMethods(file, message, writer, depth);
}

fn writeJsonParseMethods(file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn jsonParse(allocator: std.mem.Allocator, text: []const u8) !@This() {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var arena = try allocator.create(std.heap.ArenaAllocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer allocator.destroy(arena);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("arena.* = std.heap.ArenaAllocator.init(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer arena.deinit();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const parsed = try std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), text, .{});\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var self = @This().init();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer self.deinit(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.jsonFillFromValue(allocator, arena.allocator(), parsed);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("self.@\"_json_arena\" = arena;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return self;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn jsonParseInitialized(allocator: std.mem.Allocator, text: []const u8) !@This() {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var self = try @This().jsonParse(allocator, text);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer self.deinit(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.validateRequiredRecursive(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return self;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("fn jsonFillFromValue(self: *@This(), allocator: std.mem.Allocator, arena_allocator: std.mem.Allocator, json_value: std.json.Value) !void {\n");
    const has_parse_fields = messageJsonParseHasFields(message);
    if (!has_parse_fields) {
        try indent(writer, depth + 1);
        try writer.writeAll("_ = self;\n");
    }
    if (!messageJsonParseUsesAllocator(message)) {
        try indent(writer, depth + 1);
        try writer.writeAll("_ = allocator;\n");
    }
    if (!messageJsonParseUsesArenaAllocator(message)) {
        try indent(writer, depth + 1);
        try writer.writeAll("_ = arena_allocator;\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("const object = switch (json_value) { .object => |object| object, else => return error.TypeMismatch };\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var it = object.iterator();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("while (it.next()) |entry| {\n");
    if (has_parse_fields) {
        try indent(writer, depth + 2);
        try writer.writeAll("const key = entry.key_ptr.*;\n");
        try indent(writer, depth + 2);
        try writer.writeAll("const value = entry.value_ptr.*;\n");
        try indent(writer, depth + 2);
        try writer.writeAll("if (value == .null) {\n");
        for (message.fields.items) |*field| {
            if (field.oneof_name == null) try writeJsonClearField(file, field, writer, depth + 3);
        }
        for (message.oneofs.items) |oneof| {
            for (message.fields.items) |*field| {
                if (field.oneof_name) |name| {
                    if (std.mem.eql(u8, name, oneof.name)) try writeJsonClearOneofField(oneof, field, writer, depth + 3);
                }
            }
        }
        try indent(writer, depth + 3);
        try writer.writeAll("return error.UnknownField;\n");
        try indent(writer, depth + 2);
        try writer.writeAll("}\n");
        for (message.fields.items) |*field| {
            if (field.oneof_name == null) try writeJsonParseField(file, field, writer, depth + 2);
        }
        for (message.oneofs.items) |oneof| {
            for (message.fields.items) |*field| {
                if (field.oneof_name) |name| {
                    if (std.mem.eql(u8, name, oneof.name)) try writeJsonParseOneofField(file, oneof, field, writer, depth + 2);
                }
            }
        }
    }
    try indent(writer, depth + 2);
    try writer.writeAll("return error.UnknownField;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try writeJsonParseHelpers(writer, depth);
}

fn messageJsonParseUsesAllocator(message: *const schema.MessageDescriptor) bool {
    for (message.fields.items) |field| {
        if (field.oneof_name == null and fieldJsonParseUsesAllocator(field)) return true;
    }
    return false;
}

fn messageJsonParseHasFields(message: *const schema.MessageDescriptor) bool {
    for (message.fields.items) |field| {
        if (field.kind == .scalar or field.kind == .enumeration or field.kind == .map or field.kind == .message or field.kind == .group) return true;
    }
    return false;
}

fn messageJsonStringifyHasFields(file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor) bool {
    for (message.fields.items) |field| {
        if (field.oneof_name == null and fieldJsonStringifySupported(file, field)) return true;
    }
    for (message.oneofs.items) |oneof| {
        if (oneofHasJsonField(file, message, oneof.name)) return true;
    }
    return false;
}

fn messageJsonStringifyUsesAllocator(message: *const schema.MessageDescriptor) bool {
    for (message.fields.items) |field| {
        if (field.kind == .message or field.kind == .group) return true;
    }
    return false;
}

fn fieldJsonStringifySupported(file: *const schema.FileDescriptor, field: schema.FieldDescriptor) bool {
    return switch (field.kind) {
        .scalar, .enumeration => true,
        .message, .group => |name| codegenCanReferenceMessage(file, name),
        .map => |map_type| jsonMapValueSupported(file, map_type.value.*),
    };
}

fn oneofHasJsonField(file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor, oneof_name: []const u8) bool {
    for (message.fields.items) |field| {
        if (field.oneof_name) |name| {
            if (std.mem.eql(u8, name, oneof_name) and fieldJsonStringifySupported(file, field)) return true;
        }
    }
    return false;
}

fn messageJsonParseUsesArenaAllocator(message: *const schema.MessageDescriptor) bool {
    for (message.fields.items) |field| {
        switch (field.kind) {
            .scalar => |scalar| if (scalar == .bytes) return true,
            .message, .group => return true,
            .map => |map_type| switch (map_type.value.*) {
                .scalar => |scalar| if (scalar == .bytes) return true,
                else => {},
            },
            else => {},
        }
    }
    return false;
}

fn fieldJsonParseUsesAllocator(field: schema.FieldDescriptor) bool {
    return field.kind == .map or (field.cardinality == .repeated and (field.kind == .scalar or field.kind == .enumeration or field.kind == .message or field.kind == .group));
}

fn writeJsonClearField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("if (");
    try writeJsonKeyCondition(field, writer);
    try writer.writeAll(") {\n");
    if (field.cardinality == .repeated or field.kind == .map) {
        try indent(writer, depth + 1);
        try writer.writeAll("const old = self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll("; self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = &.{}; if (old.len != 0) allocator.free(old);\n");
    } else {
        try indent(writer, depth + 1);
        try writer.writeAll("self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = ");
        try writeFieldDefault(field.*, writer);
        try writer.writeAll(";\n");
        if (hasPresence(file, field.*)) {
            try indent(writer, depth + 1);
            try writer.writeAll("self.");
            try writePresenceIdent(field.name, writer);
            try writer.writeAll(" = false;\n");
        }
    }
    try indent(writer, depth + 1);
    try writer.writeAll("continue;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeJsonClearOneofField(oneof: schema.OneofDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("if (");
    try writeJsonKeyCondition(field, writer);
    try writer.writeAll(") { self.");
    try writeQuotedIdent(oneof.name, writer);
    try writer.writeAll(" = .none; continue; }\n");
}

fn writeJsonParseField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    switch (field.kind) {
        .scalar, .enumeration => {},
        .message, .group => |name| return try writeJsonParseMessageField(file, field, name, writer, depth),
        .map => return try writeJsonParseMapField(file, field, writer, depth),
    }
    try indent(writer, depth);
    try writer.writeAll("if (");
    try writeJsonKeyCondition(field, writer);
    try writer.writeAll(") {\n");
    if (field.cardinality == .repeated) {
        try indent(writer, depth + 1);
        try writer.writeAll("const array = switch (value) { .array => |array| array, else => return error.TypeMismatch };\n");
        try indent(writer, depth + 1);
        try writer.writeAll("var list: std.ArrayList(");
        try writeRepeatedElementType(field.*, writer);
        try writer.writeAll(") = .empty;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("errdefer list.deinit(allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("for (array.items) |item| try list.append(allocator, ");
        try writeJsonParseValueExpr(file, field.kind, "item", "arena_allocator", writer);
        try writer.writeAll(");\n");
        try indent(writer, depth + 1);
        try writer.writeAll("self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = blk: { const old = self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll("; const owned = try list.toOwnedSlice(allocator); if (old.len != 0) allocator.free(old); break :blk owned; };\n");
    } else {
        try indent(writer, depth + 1);
        try writer.writeAll("self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = ");
        try writeJsonParseValueExpr(file, field.kind, "value", "arena_allocator", writer);
        try writer.writeAll(";\n");
        if (hasPresence(file, field.*)) {
            try indent(writer, depth + 1);
            try writer.writeAll("self.");
            try writePresenceIdent(field.name, writer);
            try writer.writeAll(" = true;\n");
        }
    }
    try indent(writer, depth + 1);
    try writer.writeAll("continue;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeJsonParseMessageField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, type_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    if (!codegenCanReferenceMessage(file, type_name)) return;
    try indent(writer, depth);
    try writer.writeAll("if (");
    try writeJsonKeyCondition(field, writer);
    try writer.writeAll(") {\n");
    if (field.cardinality == .repeated) {
        try indent(writer, depth + 1);
        try writer.writeAll("const array = switch (value) { .array => |array| array, else => return error.TypeMismatch };\n");
        try indent(writer, depth + 1);
        try writer.writeAll("var list: std.ArrayList([]const u8) = .empty;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("errdefer list.deinit(allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("for (array.items) |item| {\n");
        try indent(writer, depth + 2);
        try writer.writeAll("var nested = try ");
        try writeMessageTypeReference(type_name, writer);
        try writer.writeAll(".jsonParse(arena_allocator, try std.json.Stringify.valueAlloc(arena_allocator, item, .{}));\n");
        try indent(writer, depth + 2);
        try writer.writeAll("defer nested.deinit(arena_allocator);\n");
        try indent(writer, depth + 2);
        try writer.writeAll("try list.append(allocator, try nested.encode(arena_allocator));\n");
        try indent(writer, depth + 1);
        try writer.writeAll("}\n");
        try indent(writer, depth + 1);
        try writer.writeAll("self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = blk: { const old = self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll("; const owned = try list.toOwnedSlice(allocator); if (old.len != 0) allocator.free(old); break :blk owned; };\n");
    } else {
        try indent(writer, depth + 1);
        try writer.writeAll("var nested = try ");
        try writeMessageTypeReference(type_name, writer);
        try writer.writeAll(".jsonParse(arena_allocator, try std.json.Stringify.valueAlloc(arena_allocator, value, .{}));\n");
        try indent(writer, depth + 1);
        try writer.writeAll("defer nested.deinit(arena_allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = try nested.encode(arena_allocator);\n");
        if (hasPresence(file, field.*)) {
            try indent(writer, depth + 1);
            try writer.writeAll("self.");
            try writePresenceIdent(field.name, writer);
            try writer.writeAll(" = true;\n");
        }
    }
    try indent(writer, depth + 1);
    try writer.writeAll("continue;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeJsonParseMapField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const map_type = switch (field.kind) {
        .map => |map| map,
        else => return,
    };
    if (!jsonMapValueSupported(file, map_type.value.*)) return;
    try indent(writer, depth);
    try writer.writeAll("if (");
    try writeJsonKeyCondition(field, writer);
    try writer.writeAll(") {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const object_value = switch (value) { .object => |map_object| map_object, else => return error.TypeMismatch };\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var list: std.ArrayList(");
    try writeQuotedIdentWithSuffix(field.name, "Entry", writer);
    try writer.writeAll(") = .empty;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer list.deinit(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var map_it = object_value.iterator();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("while (map_it.next()) |map_entry| {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("try list.append(allocator, .{ .key = ");
    try writeJsonParseMapKeyExpr(map_type.key, "map_entry.key_ptr.*", writer);
    try writer.writeAll(", .value = ");
    try writeJsonParseMapValueExpr(file, map_type.value.*, "map_entry.value_ptr.*", "arena_allocator", writer);
    try writer.writeAll(" });\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = blk: { const old = self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll("; const owned = try list.toOwnedSlice(allocator); if (old.len != 0) allocator.free(old); break :blk owned; };\n");
    try indent(writer, depth + 1);
    try writer.writeAll("continue;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeJsonParseMapKeyExpr(scalar: schema.ScalarType, key_expr: []const u8, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .string => try writer.writeAll(key_expr),
        .bool => try writer.print("try @This().jsonMapKeyBool({s})", .{key_expr}),
        .int32, .sint32, .sfixed32 => try writer.print("try std.fmt.parseInt(i32, {s}, 10)", .{key_expr}),
        .int64, .sint64, .sfixed64 => try writer.print("try std.fmt.parseInt(i64, {s}, 10)", .{key_expr}),
        .uint32, .fixed32 => try writer.print("try std.fmt.parseInt(u32, {s}, 10)", .{key_expr}),
        .uint64, .fixed64 => try writer.print("try std.fmt.parseInt(u64, {s}, 10)", .{key_expr}),
        .double, .float, .bytes => try writer.writeAll("@compileError(\"invalid map key\")"),
    }
}

fn writeJsonParseOneofField(file: *const schema.FileDescriptor, oneof: schema.OneofDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    switch (field.kind) {
        .scalar, .enumeration, .message, .group => {},
        else => return,
    }
    try indent(writer, depth);
    try writer.writeAll("if (");
    try writeJsonKeyCondition(field, writer);
    try writer.writeAll(") {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("self.");
    try writeQuotedIdent(oneof.name, writer);
    try writer.writeAll(" = .{ .");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = ");
    const maybe_message_type = switch (field.kind) {
        .message, .group => |type_name| type_name,
        else => null,
    };
    if (maybe_message_type) |type_name| {
        if (codegenCanReferenceMessage(file, type_name)) {
            try writer.writeAll("blk: { var nested = try ");
            try writeMessageTypeReference(type_name, writer);
            try writer.writeAll(".jsonParse(arena_allocator, try std.json.Stringify.valueAlloc(arena_allocator, value, .{})); defer nested.deinit(arena_allocator); break :blk try nested.encode(arena_allocator); }");
        } else {
            try writeJsonParseValueExpr(file, field.kind, "value", "arena_allocator", writer);
        }
    } else {
        try writeJsonParseValueExpr(file, field.kind, "value", "arena_allocator", writer);
    }
    try writer.writeAll(" };\n");
    try indent(writer, depth + 1);
    try writer.writeAll("continue;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeJsonKeyCondition(field: *const schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("std.mem.eql(u8, key, ");
    try writeZigStringLiteral(field.name, writer);
    try writer.writeAll(")");
    if (field.json_name) |json_name| {
        try writer.writeAll(" or std.mem.eql(u8, key, ");
        try writeZigStringLiteral(json_name, writer);
        try writer.writeAll(")");
    } else {
        try writer.writeAll(" or std.mem.eql(u8, key, ");
        try writeZigLowerCamelStringLiteral(field.name, writer);
        try writer.writeAll(")");
    }
}

fn writeJsonParseValueExpr(file: *const schema.FileDescriptor, kind: schema.FieldKind, value_expr: []const u8, arena_expr: []const u8, writer: *std.Io.Writer) Error!void {
    switch (kind) {
        .scalar => |scalar| switch (scalar) {
            .double => try writer.print("try @This().jsonFloat(f64, {s})", .{value_expr}),
            .float => try writer.print("try @This().jsonFloat(f32, {s})", .{value_expr}),
            .int32, .sint32, .sfixed32 => try writer.print("try @This().jsonInt(i32, {s})", .{value_expr}),
            .int64, .sint64, .sfixed64 => try writer.print("try @This().jsonInt(i64, {s})", .{value_expr}),
            .uint32, .fixed32 => try writer.print("try @This().jsonInt(u32, {s})", .{value_expr}),
            .uint64, .fixed64 => try writer.print("try @This().jsonInt(u64, {s})", .{value_expr}),
            .bool => try writer.print("try @This().jsonBool({s})", .{value_expr}),
            .string => try writer.print("try @This().jsonString({s})", .{value_expr}),
            .bytes => try writer.print("try @This().jsonBytes({s}, {s})", .{ arena_expr, value_expr }),
        },
        .enumeration => |name| {
            try writer.print("try @This().jsonEnum({s}, ", .{value_expr});
            try writeEnumNameArray(file, name, writer);
            try writer.writeAll(", ");
            try writeEnumNumberArray(file, name, writer);
            try writer.writeAll(", ");
            try writer.writeAll(if (enumIsClosed(file, name)) "true" else "false");
            try writer.writeAll(")");
        },
        else => try writer.writeAll("@compileError(\"unsupported JSON parse field kind\")"),
    }
}

fn writeJsonParseMapValueExpr(file: *const schema.FileDescriptor, kind: schema.FieldKind, value_expr: []const u8, arena_expr: []const u8, writer: *std.Io.Writer) Error!void {
    switch (kind) {
        .message => |name| if (codegenCanReferenceMessage(file, name)) {
            try writer.writeAll("blk: { var nested = try ");
            try writeMessageTypeReference(name, writer);
            try writer.writeAll(".jsonParse(");
            try writer.writeAll(arena_expr);
            try writer.writeAll(", try std.json.Stringify.valueAlloc(");
            try writer.writeAll(arena_expr);
            try writer.writeAll(", ");
            try writer.writeAll(value_expr);
            try writer.writeAll(", .{})); defer nested.deinit(");
            try writer.writeAll(arena_expr);
            try writer.writeAll("); break :blk try nested.encode(");
            try writer.writeAll(arena_expr);
            try writer.writeAll("); }");
        } else try writer.writeAll("@compileError(\"unsupported JSON parse field kind\")"),
        else => try writeJsonParseValueExpr(file, kind, value_expr, arena_expr, writer),
    }
}

fn writeEnumNameArray(file: *const schema.FileDescriptor, name: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("&.{");
    if (file.findEnumDeep(name)) |enumeration| {
        for (enumeration.values.items, 0..) |value, i| {
            if (i != 0) try writer.writeAll(", ");
            try writeZigStringLiteral(value.name, writer);
        }
    }
    try writer.writeAll("}");
}

fn writeEnumNumberArray(file: *const schema.FileDescriptor, name: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("&.{");
    if (file.findEnumDeep(name)) |enumeration| {
        for (enumeration.values.items, 0..) |value, i| {
            if (i != 0) try writer.writeAll(", ");
            try writer.print("{d}", .{value.number});
        }
    }
    try writer.writeAll("}");
}

fn enumIsClosed(file: *const schema.FileDescriptor, name: []const u8) bool {
    if (file.findEnumDeep(name)) |enumeration| {
        if (enumeration.features) |features| return features.enum_type == .closed;
    }
    return file.features.enum_type == .closed;
}

fn writeJsonParseHelpers(writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll(
        \\fn jsonInt(comptime T: type, value: std.json.Value) !T {
        \\    return switch (value) {
        \\        .integer => |v| std.math.cast(T, v) orelse error.Overflow,
        \\        .number_string, .string => |text| try std.fmt.parseInt(T, text, 10),
        \\        else => error.TypeMismatch,
        \\    };
        \\}
        \\
        \\fn jsonFloat(comptime T: type, value: std.json.Value) !T {
        \\    return switch (value) {
        \\        .integer => |v| @as(T, @floatFromInt(v)),
        \\        .float => |v| @floatCast(v),
        \\        .number_string, .string => |text| try std.fmt.parseFloat(T, text),
        \\        else => error.TypeMismatch,
        \\    };
        \\}
        \\
        \\fn jsonBool(value: std.json.Value) !bool {
        \\    return switch (value) {
        \\        .bool => |v| v,
        \\        else => error.TypeMismatch,
        \\    };
        \\}
        \\
        \\fn jsonString(value: std.json.Value) ![]const u8 {
        \\    return switch (value) {
        \\        .string => |v| v,
        \\        else => error.TypeMismatch,
        \\    };
        \\}
        \\
        \\fn jsonBytes(allocator: std.mem.Allocator, value: std.json.Value) ![]const u8 {
        \\    return try jsonDecodeBase64(allocator, try jsonString(value));
        \\}
        \\
        \\fn jsonEnum(value: std.json.Value, comptime names: []const []const u8, comptime numbers: []const i32, comptime closed: bool) !i32 {
        \\    return switch (value) {
        \\        .integer => |v| try jsonEnumNumber(std.math.cast(i32, v) orelse error.Overflow, numbers, closed),
        \\        .number_string => |text| try jsonEnumNumber(try std.fmt.parseInt(i32, text, 10), numbers, closed),
        \\        .string => |text| {
        \\            inline for (names, 0..) |name, i| {
        \\                if (std.mem.eql(u8, text, name)) return numbers[i];
        \\            }
        \\            return try jsonEnumNumber(std.fmt.parseInt(i32, text, 10) catch return error.InvalidEnumValue, numbers, closed);
        \\        },
        \\        else => error.TypeMismatch,
        \\    };
        \\}
        \\
        \\fn jsonEnumNumber(value: i32, comptime numbers: []const i32, comptime closed: bool) !i32 {
        \\    if (closed) {
        \\        inline for (numbers) |number| {
        \\            if (value == number) return value;
        \\        }
        \\        return error.InvalidEnumValue;
        \\    }
        \\    return value;
        \\}
        \\
        \\fn jsonWriteEnum(writer: *std.Io.Writer, value: i32, comptime names: []const []const u8, comptime numbers: []const i32) !void {
        \\    inline for (numbers, 0..) |number, i| {
        \\        if (value == number) return try std.json.Stringify.value(names[i], .{}, writer);
        \\    }
        \\    try writer.print("{d}", .{value});
        \\}
        \\
        \\fn textWriteEnum(writer: *std.Io.Writer, value: i32, comptime names: []const []const u8, comptime numbers: []const i32) !void {
        \\    inline for (numbers, 0..) |number, i| {
        \\        if (value == number) return try writer.writeAll(names[i]);
        \\    }
        \\    try writer.print("{d}", .{value});
        \\}
        \\
        \\fn textFieldValue(line: []const u8, comptime name: []const u8) ?[]const u8 {
        \\    if (!std.mem.startsWith(u8, line, name)) return null;
        \\    var rest = line[name.len..];
        \\    rest = std.mem.trimLeft(u8, rest, " \t");
        \\    if (rest.len == 0 or rest[0] != ':') return null;
        \\    return std.mem.trim(u8, rest[1..], " \t\r");
        \\}
        \\
        \\fn textCleanLine(raw_line: []const u8) []const u8 {
        \\    var line = std.mem.trim(u8, raw_line, " \t\r");
        \\    if (std.mem.indexOfScalar(u8, line, '#')) |idx| line = std.mem.trim(u8, line[0..idx], " \t\r");
        \\    while (line.len != 0 and (line[line.len - 1] == ';' or line[line.len - 1] == ',')) {
        \\        line = std.mem.trim(u8, line[0 .. line.len - 1], " \t\r");
        \\    }
        \\    return line;
        \\}
        \\
        \\fn textBool(value: []const u8) !bool {
        \\    if (std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "t") or std.mem.eql(u8, value, "1")) return true;
        \\    if (std.mem.eql(u8, value, "false") or std.mem.eql(u8, value, "f") or std.mem.eql(u8, value, "0")) return false;
        \\    return error.TypeMismatch;
        \\}
        \\
        \\fn textInt(comptime T: type, value: []const u8) !T {
        \\    return try std.fmt.parseInt(T, value, 0);
        \\}
        \\
        \\fn textFloat(comptime T: type, value: []const u8) !T {
        \\    if (std.ascii.eqlIgnoreCase(value, "nan")) return std.math.nan(T);
        \\    if (std.ascii.eqlIgnoreCase(value, "inf") or std.ascii.eqlIgnoreCase(value, "infinity")) return std.math.inf(T);
        \\    if (std.ascii.eqlIgnoreCase(value, "-inf") or std.ascii.eqlIgnoreCase(value, "-infinity")) return -std.math.inf(T);
        \\    return try std.fmt.parseFloat(T, value);
        \\}
        \\
        \\fn textUnquote(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
        \\    const body = if (value.len >= 2 and ((value[0] == '"' and value[value.len - 1] == '"') or (value[0] == '\'' and value[value.len - 1] == '\''))) value[1 .. value.len - 1] else value;
        \\    var out: std.ArrayList(u8) = .empty;
        \\    errdefer out.deinit(allocator);
        \\    var i: usize = 0;
        \\    while (i < body.len) : (i += 1) {
        \\        if (body[i] != '\\') {
        \\            try out.append(allocator, body[i]);
        \\            continue;
        \\        }
        \\        i += 1;
        \\        if (i >= body.len) return error.InvalidEscape;
        \\        switch (body[i]) {
        \\            'n' => try out.append(allocator, '\n'),
        \\            'r' => try out.append(allocator, '\r'),
        \\            't' => try out.append(allocator, '\t'),
        \\            '\\' => try out.append(allocator, '\\'),
        \\            '"' => try out.append(allocator, '"'),
        \\            '\'' => try out.append(allocator, '\''),
        \\            'x' => {
        \\                if (i + 2 >= body.len) return error.InvalidEscape;
        \\                try out.append(allocator, try std.fmt.parseInt(u8, body[i + 1 .. i + 3], 16));
        \\                i += 2;
        \\            },
        \\            else => |c| try out.append(allocator, c),
        \\        }
        \\    }
        \\    return try out.toOwnedSlice(allocator);
        \\}
        \\
        \\fn textEnum(value: []const u8, comptime names: []const []const u8, comptime numbers: []const i32, comptime closed: bool) !i32 {
        \\    inline for (names, 0..) |name, i| {
        \\        if (std.mem.eql(u8, value, name)) return numbers[i];
        \\    }
        \\    const number = try std.fmt.parseInt(i32, value, 10);
        \\    if (closed) {
        \\        inline for (numbers) |known| {
        \\            if (number == known) return number;
        \\        }
        \\        return error.InvalidEnumValue;
        \\    }
        \\    return number;
        \\}
        \\
        \\fn textBlock(allocator: std.mem.Allocator, lines: anytype) ![]u8 {
        \\    var out: std.Io.Writer.Allocating = .init(allocator);
        \\    errdefer out.deinit();
        \\    var depth: usize = 1;
        \\    while (lines.next()) |raw_line| {
        \\        const line = std.mem.trim(u8, raw_line, " \t\r");
        \\        if (std.mem.eql(u8, line, "}") or std.mem.eql(u8, line, ">")) {
        \\            depth -= 1;
        \\            if (depth == 0) return try out.toOwnedSlice();
        \\        }
        \\        if (std.mem.endsWith(u8, line, "{") or std.mem.endsWith(u8, line, "<")) depth += 1;
        \\        try out.writer.writeAll(line);
        \\        try out.writer.writeByte('\n');
        \\    }
        \\    return error.UnexpectedEof;
        \\}
        \\
        \\fn jsonDecodeBase64(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
        \\    return jsonDecodeBase64With(allocator, &std.base64.standard.Decoder, value) catch
        \\        jsonDecodeBase64With(allocator, &std.base64.url_safe.Decoder, value) catch
        \\        jsonDecodeBase64With(allocator, &std.base64.standard_no_pad.Decoder, value) catch
        \\        jsonDecodeBase64With(allocator, &std.base64.url_safe_no_pad.Decoder, value);
        \\}
        \\
        \\fn jsonDecodeBase64With(allocator: std.mem.Allocator, decoder: *const std.base64.Base64Decoder, value: []const u8) ![]u8 {
        \\    const size = try decoder.calcSizeForSlice(value);
        \\    const out = try allocator.alloc(u8, size);
        \\    errdefer allocator.free(out);
        \\    try decoder.decode(out, value);
        \\    return out;
        \\}
        \\
        \\fn jsonMapKeyBool(key: []const u8) !bool {
        \\    if (std.mem.eql(u8, key, "true")) return true;
        \\    if (std.mem.eql(u8, key, "false")) return false;
        \\    return error.TypeMismatch;
        \\}
        \\
    );
}

fn writeJsonField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    switch (field.kind) {
        .scalar => |scalar| try writeJsonScalarField(file, field, scalar, writer, depth),
        .enumeration => |name| try writeJsonEnumField(file, field, name, writer, depth),
        .map => try writeJsonMapField(file, field, writer, depth),
        .message, .group => |name| try writeJsonMessageField(file, field, name, writer, depth),
    }
}

fn writeJsonPrefix(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("if (!first) try writer.writeAll(\",\"); first = false;\n");
    try indent(writer, depth);
    try writer.writeAll("try writer.writeAll(\"\\\"");
    try writeJsonFieldNameLiteralContents(field, writer);
    try writer.writeAll("\\\":\");\n");
}

fn writeJsonScalarField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        try writer.writeAll("if (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(".len != 0) {\n");
        try writeJsonPrefix(field, writer, depth + 1);
        try indent(writer, depth + 1);
        try writer.writeAll("try writer.writeAll(\"[\");\n");
        try indent(writer, depth + 1);
        try writer.writeAll("for (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(", 0..) |item, i| { if (i != 0) try writer.writeAll(\",\"); ");
        try writeJsonScalarValue(scalar, "item", writer);
        try writer.writeAll("; }\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try writer.writeAll(\"]\");\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");
    } else {
        try indent(writer, depth);
        if (hasPresence(file, field.*)) {
            try writer.writeAll("if (self.");
            try writePresenceIdent(field.name, writer);
            try writer.writeAll(") {\n");
        } else {
            try writer.writeAll("if (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(defaultSkipCondition(scalar));
            try writer.writeAll("{\n");
        }
        try writeJsonPrefix(field, writer, depth + 1);
        try indent(writer, depth + 1);
        try writer.writeAll("const value = self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(";\n");
        try indent(writer, depth + 1);
        try writeJsonScalarValue(scalar, "value", writer);
        try writer.writeAll(";\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");
    }
}

fn writeJsonEnumField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, enum_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        try writer.writeAll("if (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(".len != 0) {\n");
        try writeJsonPrefix(field, writer, depth + 1);
        try indent(writer, depth + 1);
        try writer.writeAll("try writer.writeAll(\"[\");\n");
        try indent(writer, depth + 1);
        try writer.writeAll("for (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(", 0..) |item, i| { if (i != 0) try writer.writeAll(\",\"); ");
        try writeJsonEnumValue(file, enum_name, "item", writer);
        try writer.writeAll("; }\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try writer.writeAll(\"]\");\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");
    } else {
        try indent(writer, depth);
        if (hasPresence(file, field.*)) {
            try writer.writeAll("if (self.");
            try writePresenceIdent(field.name, writer);
            try writer.writeAll(") {\n");
        } else {
            try writer.writeAll("if (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(" != 0) {\n");
        }
        try writeJsonPrefix(field, writer, depth + 1);
        try indent(writer, depth + 1);
        try writer.writeAll("const value = self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(";\n");
        try indent(writer, depth + 1);
        try writeJsonEnumValue(file, enum_name, "value", writer);
        try writer.writeAll(";\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");
    }
}

fn writeJsonMapField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const map_type = switch (field.kind) {
        .map => |map| map,
        else => return,
    };
    if (!jsonMapValueSupported(file, map_type.value.*)) return;
    try indent(writer, depth);
    try writer.writeAll("if (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".len != 0) {\n");
    try writeJsonPrefix(field, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("try writer.writeAll(\"{\");\n");
    try indent(writer, depth + 1);
    try writer.writeAll("for (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(", 0..) |entry, i| {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("if (i != 0) try writer.writeAll(\",\");\n");
    try indent(writer, depth + 2);
    try writeJsonMapKeyValue(map_type.key, "entry.key", writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 2);
    try writer.writeAll("try writer.writeAll(\":\");\n");
    try indent(writer, depth + 2);
    try writeJsonMapEntryValue(file, map_type.value.*, "entry.value", writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try writer.writeAll(\"}\");\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeJsonMessageField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, type_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    if (!codegenCanReferenceMessage(file, type_name)) return;
    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        try writer.writeAll("if (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(".len != 0) {\n");
        try writeJsonPrefix(field, writer, depth + 1);
        try indent(writer, depth + 1);
        try writer.writeAll("try writer.writeAll(\"[\");\n");
        try indent(writer, depth + 1);
        try writer.writeAll("for (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(", 0..) |payload, i| {\n");
        try indent(writer, depth + 2);
        try writer.writeAll("if (i != 0) try writer.writeAll(\",\");\n");
        try writeDecodeAndStringifyPayload(type_name, "payload", writer, depth + 2);
        try indent(writer, depth + 1);
        try writer.writeAll("}\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try writer.writeAll(\"]\");\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");
    } else {
        try indent(writer, depth);
        try writer.writeAll("if (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(".len != 0) {\n");
        try writeJsonPrefix(field, writer, depth + 1);
        try indent(writer, depth + 1);
        try writer.writeAll("var nested = try ");
        try writeMessageTypeReference(type_name, writer);
        try writer.writeAll(".decode(allocator, self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(");\n");
        try indent(writer, depth + 1);
        try writer.writeAll("defer nested.deinit(allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try nested.jsonStringifyWithAllocator(allocator, writer);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");
    }
}

fn writeDecodeAndStringifyPayload(type_name: []const u8, payload_expr: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("var nested = try ");
    try writeMessageTypeReference(type_name, writer);
    try writer.writeAll(".decode(allocator, ");
    try writer.writeAll(payload_expr);
    try writer.writeAll(");\n");
    try indent(writer, depth);
    try writer.writeAll("defer nested.deinit(allocator);\n");
    try indent(writer, depth);
    try writer.writeAll("try nested.jsonStringifyWithAllocator(allocator, writer);\n");
}

fn jsonMapValueSupported(file: *const schema.FileDescriptor, kind: schema.FieldKind) bool {
    return switch (kind) {
        .scalar, .enumeration => true,
        .message => |name| codegenCanReferenceMessage(file, name),
        else => false,
    };
}

fn writeJsonMapKeyValue(scalar: schema.ScalarType, key_expr: []const u8, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .string => try writer.print("try std.json.Stringify.value({s}, .{{}}, writer)", .{key_expr}),
        .bool => try writer.print("try writer.writeAll(if ({s}) \"\\\"true\\\"\" else \"\\\"false\\\"\")", .{key_expr}),
        .int32, .int64, .uint32, .uint64, .sint32, .sint64, .fixed32, .fixed64, .sfixed32, .sfixed64 => try writer.print("try writer.print(\"\\\"{{d}}\\\"\", .{{{s}}})", .{key_expr}),
        .double, .float, .bytes => try writer.writeAll("@compileError(\"invalid map key\")"),
    }
}

fn writeJsonMapEntryValue(file: *const schema.FileDescriptor, kind: schema.FieldKind, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    switch (kind) {
        .scalar => |scalar| try writeJsonScalarValue(scalar, value_expr, writer),
        .enumeration => |name| try writeJsonEnumValue(file, name, value_expr, writer),
        .message => |name| if (codegenCanReferenceMessage(file, name)) {
            try writer.writeAll("var nested = try ");
            try writeMessageTypeReference(name, writer);
            try writer.writeAll(".decode(allocator, ");
            try writer.writeAll(value_expr);
            try writer.writeAll("); defer nested.deinit(allocator); try nested.jsonStringifyWithAllocator(allocator, writer)");
        } else try writer.writeAll("@compileError(\"unsupported map JSON value\")"),
        else => try writer.writeAll("@compileError(\"unsupported map JSON value\")"),
    }
}

fn writeJsonOneof(file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor, oneof: schema.OneofDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("switch (self.");
    try writeQuotedIdent(oneof.name, writer);
    try writer.writeAll(") {\n");
    try indent(writer, depth + 1);
    try writer.writeAll(".none => {},\n");
    for (message.fields.items) |*field| {
        if (field.oneof_name) |name| {
            if (std.mem.eql(u8, name, oneof.name)) {
                try indent(writer, depth + 1);
                try writer.writeAll(".");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(" => |value| {\n");
                switch (field.kind) {
                    .scalar => |scalar| {
                        try writeJsonPrefix(field, writer, depth + 2);
                        try indent(writer, depth + 2);
                        try writeJsonScalarValue(scalar, "value", writer);
                        try writer.writeAll(";\n");
                    },
                    .enumeration => |enum_name| {
                        try writeJsonPrefix(field, writer, depth + 2);
                        try indent(writer, depth + 2);
                        try writeJsonEnumValue(file, enum_name, "value", writer);
                        try writer.writeAll(";\n");
                    },
                    .message, .group => |type_name| {
                        if (codegenCanReferenceMessage(file, type_name)) {
                            try writeJsonPrefix(field, writer, depth + 2);
                            try writeDecodeAndStringifyPayload(type_name, "value", writer, depth + 2);
                        } else {
                            try indent(writer, depth + 2);
                            try writer.writeAll("_ = value;\n");
                        }
                    },
                    else => {
                        try indent(writer, depth + 2);
                        try writer.writeAll("_ = value;\n");
                    },
                }
                try indent(writer, depth + 1);
                try writer.writeAll("},\n");
            }
        }
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeJsonScalarValue(scalar: schema.ScalarType, prefix: []const u8, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .string => try writer.print("try std.json.Stringify.value({s}, .{{}}, writer)", .{prefix}),
        .bytes => try writer.print("try writer.writeByte('\"'); try std.base64.standard.Encoder.encodeWriter(writer, {s}); try writer.writeByte('\"')", .{prefix}),
        .int64, .uint64, .sint64, .fixed64, .sfixed64 => try writer.print("try writer.print(\"\\\"{{d}}\\\"\", .{{{s}}})", .{prefix}),
        .bool => try writer.print("try writer.writeAll(if ({s}) \"true\" else \"false\")", .{prefix}),
        .double, .float => try writer.print("if (std.math.isNan({s})) try writer.writeAll(\"\\\"NaN\\\"\") else if (std.math.isPositiveInf({s})) try writer.writeAll(\"\\\"Infinity\\\"\") else if (std.math.isNegativeInf({s})) try writer.writeAll(\"\\\"-Infinity\\\"\") else try writer.print(\"{{d}}\", .{{{s}}})", .{ prefix, prefix, prefix, prefix }),
        else => try writer.print("try writer.print(\"{{d}}\", .{{{s}}})", .{prefix}),
    }
}

fn writeJsonEnumValue(file: *const schema.FileDescriptor, enum_name: []const u8, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.print("try @This().jsonWriteEnum(writer, {s}, ", .{value_expr});
    try writeEnumNameArray(file, enum_name, writer);
    try writer.writeAll(", ");
    try writeEnumNumberArray(file, enum_name, writer);
    try writer.writeAll(")");
}

fn writeEnum(enumeration: *const schema.EnumDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub const ");
    try writeQuotedIdent(enumeration.name, writer);
    try writer.writeAll(" = enum(i32) {\n");
    for (enumeration.values.items) |value| {
        try indent(writer, depth + 1);
        try writeQuotedIdent(value.name, writer);
        try writer.print(" = {d},\n", .{value.number});
    }
    try indent(writer, depth);
    try writer.writeAll("};\n\n");
}

fn writeExtensionMetadata(file: *const schema.FileDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const count = countExtensions(file);
    if (count == 0) return;
    try indent(writer, depth);
    try writer.writeAll("pub const extensions = struct {\n");
    for (file.extensions.items) |*field| try writeExtensionDecl(file, field, writer, depth + 1);
    for (file.messages.items) |*message| try writeMessageExtensions(file, message, writer, depth + 1);
    try indent(writer, depth);
    try writer.writeAll("};\n\n");
}

fn writeMessageExtensions(file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    for (message.extensions.items) |*field| try writeExtensionDecl(file, field, writer, depth);
    for (message.messages.items) |*nested| try writeMessageExtensions(file, nested, writer, depth);
}

fn writeExtensionDecl(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub const ");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = struct {\n");
    try indent(writer, depth + 1);
    try writer.print("pub const number = {d};\n", .{field.number});
    try indent(writer, depth + 1);
    try writer.writeAll("pub const extendee = ");
    try writeZigStringLiteral(field.extendee orelse "", writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const cardinality = ");
    try writeZigStringLiteral(@tagName(field.cardinality), writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const value_type = ");
    try writeZigStringLiteral(extensionValueTypeName(file, field), writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const zig_type = ");
    try writeZigStringLiteral(fieldType(field.*), writer);
    try writer.writeAll(";\n");
    try writeExtensionWriteHelpers(file, field, writer, depth + 1);
    try writeExtensionDecodeHelpers(file, field, writer, depth + 1);
    try indent(writer, depth);
    try writer.writeAll("};\n");
}

fn writeExtensionWriteHelpers(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn write(w: *pbz.Writer, value: ");
    try writer.writeAll(extensionSingleZigType(field.kind));
    try writer.writeAll(") !void {\n");
    if (extensionUsesMessageSet(file, field)) {
        try indent(writer, depth + 1);
        try writer.writeAll("try w.writeTag(1, .start_group);\n");
        try indent(writer, depth + 1);
        try writer.print("try w.writeUInt32(2, {d});\n", .{field.number});
        try indent(writer, depth + 1);
        try writer.writeAll("try w.writeMessage(3, value);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try w.writeTag(1, .end_group);\n");
    } else {
        try indent(writer, depth + 1);
        try writeKindWriteCall(field.number, field.kind, "value", "w", writer);
        try writer.writeAll(");\n");
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");
    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        try writer.writeAll("pub fn writeAll(w: *pbz.Writer, values: ");
        try writer.writeAll(fieldType(field.*));
        try writer.writeAll(") !void {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("for (values) |value| try write(w, value);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");
    }
}

fn extensionUsesMessageSet(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor) bool {
    if (field.kind != .message) return false;
    const extendee = field.extendee orelse return false;
    const message = file.findMessageDeep(extendee) orelse return false;
    return message.messageSetWireFormat();
}

fn writeExtensionDecodeHelpers(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn decodeValue(r: *pbz.Reader) !");
    try writer.writeAll(extensionSingleZigType(field.kind));
    try writer.writeAll(" {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return ");
    try writeEntryReadExpr(field.kind, "r", writer);
    try writer.writeAll(";\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        try writer.writeAll("pub fn decodeAppend(allocator: std.mem.Allocator, list: *std.ArrayList(");
        try writer.writeAll(extensionSingleZigType(field.kind));
        try writer.writeAll("), r: *pbz.Reader) !void {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try list.append(allocator, try decodeValue(r));\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");
    }
    if (extensionUsesMessageSet(file, field)) {
        try indent(writer, depth);
        try writer.writeAll("pub fn decodeMessageSetItem(r: *pbz.Reader) !?[]const u8 {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("var type_id: ?u32 = null;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("var payload: ?[]const u8 = null;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("while (try r.nextTag()) |tag| {\n");
        try indent(writer, depth + 2);
        try writer.writeAll("if (tag.wire_type == .end_group) {\n");
        try indent(writer, depth + 3);
        try writer.writeAll("if (tag.number != 1) return error.InvalidFieldNumber;\n");
        try indent(writer, depth + 3);
        try writer.print("return if (type_id != null and type_id.? == {d}) payload else null;\n", .{field.number});
        try indent(writer, depth + 2);
        try writer.writeAll("}\n");
        try indent(writer, depth + 2);
        try writer.writeAll("switch (tag.number) {\n");
        try indent(writer, depth + 3);
        try writer.writeAll("2 => { if (tag.wire_type != .varint) return error.InvalidWireType; type_id = try r.readUInt32(); },\n");
        try indent(writer, depth + 3);
        try writer.writeAll("3 => { if (tag.wire_type != .length_delimited) return error.InvalidWireType; payload = try r.readBytes(); },\n");
        try indent(writer, depth + 3);
        try writer.writeAll("else => try r.skipValue(tag),\n");
        try indent(writer, depth + 2);
        try writer.writeAll("}\n");
        try indent(writer, depth + 1);
        try writer.writeAll("}\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return error.TruncatedInput;\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");
    }
}

fn extensionSingleZigType(kind: schema.FieldKind) []const u8 {
    return switch (kind) {
        .scalar => |scalar| scalarZigType(scalar),
        .enumeration => "i32",
        .message => "[]const u8",
        else => "void",
    };
}

fn extensionValueTypeName(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor) []const u8 {
    _ = file;
    return switch (field.kind) {
        .scalar => |scalar| @tagName(scalar),
        .message => |name| name,
        .enumeration => |name| name,
        .group => |name| name,
        .map => "map",
    };
}

fn countExtensions(file: *const schema.FileDescriptor) usize {
    var count: usize = file.extensions.items.len;
    for (file.messages.items) |*message| count += countMessageExtensions(message);
    return count;
}

fn countMessageExtensions(message: *const schema.MessageDescriptor) usize {
    var count: usize = message.extensions.items.len;
    for (message.messages.items) |*nested| count += countMessageExtensions(nested);
    return count;
}

fn writeQuotedIdent(name: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("@\"");
    for (name) |c| {
        if (c == '\\' or c == '"') try writer.writeByte('\\');
        try writer.writeByte(c);
    }
    try writer.writeAll("\"");
}

fn writeQuotedIdentWithSuffix(name: []const u8, suffix: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("@\"");
    for (name) |c| {
        if (c == '\\' or c == '"') try writer.writeByte('\\');
        try writer.writeByte(c);
    }
    try writer.writeAll(suffix);
    try writer.writeAll("\"");
}

fn hasPresence(file: *const schema.FileDescriptor, field: schema.FieldDescriptor) bool {
    if (field.cardinality == .required or field.proto3_optional or field.oneof_name != null or field.kind == .message or field.kind == .group) return true;
    if (field.cardinality == .repeated or field.kind == .map) return false;
    if (field.features) |features| return features.field_presence != .implicit;
    return file.features.field_presence != .implicit;
}

fn isRequired(field: schema.FieldDescriptor) bool {
    if (field.cardinality == .required) return true;
    if (field.features) |features| return features.field_presence == .legacy_required;
    return false;
}

fn writePresenceIdent(name: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("@\"has_");
    for (name) |c| {
        if (c == '\\' or c == '"') try writer.writeByte('\\');
        try writer.writeByte(c);
    }
    try writer.writeAll("\"");
}

fn writeSetPresence(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    if (hasPresence(file, field.*)) {
        try writer.writeAll(" self.");
        try writePresenceIdent(field.name, writer);
        try writer.writeAll(" = true;");
    }
}

fn writeQuotedFieldNumber(name: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("@\"");
    for (name) |c| {
        if (c == '\\' or c == '"') try writer.writeByte('\\');
        try writer.writeByte(c);
    }
    try writer.writeAll("_number\"");
}

fn indent(writer: *std.Io.Writer, depth: usize) Error!void {
    var i: usize = 0;
    while (i < depth) : (i += 1) try writer.writeAll("    ");
}

fn writeServiceMetadata(file: *const schema.FileDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (file.services.items.len == 0) return;
    try indent(writer, depth);
    try writer.writeAll("pub const services = struct {\n");
    for (file.services.items) |*service| try writeServiceDecl(service, writer, depth + 1);
    try indent(writer, depth);
    try writer.writeAll("};\n\n");
}

fn writeServiceDecl(service: *const schema.ServiceDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub const ");
    try writeQuotedIdent(service.name, writer);
    try writer.writeAll(" = struct {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const name = ");
    try writeZigStringLiteral(service.name, writer);
    try writer.writeAll(";\n");
    for (service.methods.items) |*method| try writeMethodDecl(method, writer, depth + 1);
    try writeServiceHandler(service, writer, depth + 1);
    try writeServiceClient(service, writer, depth + 1);
    try indent(writer, depth);
    try writer.writeAll("};\n");
}

fn writeMethodDecl(method: *const schema.MethodDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub const ");
    try writeQuotedIdent(method.name, writer);
    try writer.writeAll(" = struct {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const name = ");
    try writeZigStringLiteral(method.name, writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const input_type = ");
    try writeZigStringLiteral(method.input_type, writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const output_type = ");
    try writeZigStringLiteral(method.output_type, writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const client_streaming = ");
    try writer.writeAll(if (method.client_streaming) "true" else "false");
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const server_streaming = ");
    try writer.writeAll(if (method.server_streaming) "true" else "false");
    try writer.writeAll(";\n");
    try indent(writer, depth);
    try writer.writeAll("};\n");
}

fn writeServiceHandler(service: *const schema.ServiceDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub const Handler = struct {\n");
    for (service.methods.items) |*method| {
        try indent(writer, depth + 1);
        try writer.writeAll("pub fn ");
        try writeQuotedIdent(method.name, writer);
        try writer.writeAll("(self: *@This(), request: []const u8, allocator: std.mem.Allocator) ![]u8 {\n");
        try indent(writer, depth + 2);
        try writer.writeAll("_ = self; _ = request; _ = allocator;\n");
        try indent(writer, depth + 2);
        try writer.writeAll("return error.Unimplemented;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("}\n");
    }
    try indent(writer, depth);
    try writer.writeAll("};\n");
}

fn writeServiceClient(service: *const schema.ServiceDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub const Client = struct {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("context: *anyopaque,\n");
    try indent(writer, depth + 1);
    try writer.writeAll("call: *const fn (context: *anyopaque, service: []const u8, method: []const u8, request: []const u8, allocator: std.mem.Allocator) anyerror![]u8,\n");
    for (service.methods.items) |*method| {
        try indent(writer, depth + 1);
        try writer.writeAll("pub fn ");
        try writeQuotedIdent(method.name, writer);
        try writer.writeAll("(self: @This(), request: []const u8, allocator: std.mem.Allocator) ![]u8 {\n");
        try indent(writer, depth + 2);
        try writer.writeAll("return try self.call(self.context, ");
        try writeZigStringLiteral(service.name, writer);
        try writer.writeAll(", ");
        try writeZigStringLiteral(method.name, writer);
        try writer.writeAll(", request, allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("}\n");
    }
    try indent(writer, depth);
    try writer.writeAll("};\n");
}

fn outputName(allocator: std.mem.Allocator, input: []const u8) std.mem.Allocator.Error![]u8 {
    const base = if (input.len == 0) "schema.proto" else input;
    const stem = if (std.mem.endsWith(u8, base, ".proto")) base[0 .. base.len - 6] else base;
    return try std.fmt.allocPrint(allocator, "{s}.pb.zig", .{stem});
}

test "codegen emits zig message and enum skeletons" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message User { string name = 1; Kind kind = 2; }
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const @\"Kind\" = enum(i32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const @\"User\" = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const @\"name_number\" = 1") != null);
}

test "codegen emits package and import module metadata" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.app;
        \\import "common.proto";
        \\import public "public/common.proto";
        \\message A {}
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const proto_package = \"demo.app\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const proto_syntax = \"proto2\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const imports = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const @\"common.proto\" = @import(\"common.pb.zig\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const @\"common.proto_kind\" = \"normal\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const @\"public/common.proto\" = @import(\"public/common.pb.zig\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const @\"public/common.proto_kind\" = \"public\";") != null);
    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen emits protoc response" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator, "syntax = \"proto3\"; message A { int32 id = 1; }");
    defer file.deinit();
    file.name = "a.proto";
    const files = [_]*const schema.FileDescriptor{&file};
    const response = try generatePluginResponse(allocator, &files);
    defer allocator.free(response);
    try std.testing.expect(response.len != 0);

    var reader = wire.Reader.init(response);
    var saw_supported_features = false;
    var saw_minimum_edition = false;
    var saw_maximum_edition = false;
    var saw_file_name = false;
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            2 => saw_supported_features = (try reader.readUInt64()) == plugin.CodeGeneratorResponse.featureMask(&[_]plugin.CodeGeneratorResponse.Feature{ .proto3_optional, .supports_editions }),
            3 => saw_minimum_edition = (try reader.readInt32()) == @intFromEnum(schema.Edition.proto2),
            4 => saw_maximum_edition = (try reader.readInt32()) == @intFromEnum(schema.Edition.edition_2026),
            15 => {
                var file_reader = wire.Reader.init(try reader.readBytes());
                while (try file_reader.nextTag()) |file_tag| {
                    switch (file_tag.number) {
                        1 => saw_file_name = std.mem.eql(u8, try file_reader.readBytes(), "a.pb.zig"),
                        else => try file_reader.skipValue(file_tag),
                    }
                }
            },
            else => try reader.skipValue(tag),
        }
    }
    try std.testing.expect(saw_supported_features);
    try std.testing.expect(saw_minimum_edition);
    try std.testing.expect(saw_maximum_edition);
    try std.testing.expect(saw_file_name);
}

test "codegen quotes zig identifiers" {
    const allocator = std.testing.allocator;
    var file = schema.FileDescriptor.init(allocator);
    defer file.deinit();
    file.setSyntax(.proto3);
    var msg = schema.MessageDescriptor{ .name = "struct" };
    try msg.fields.append(allocator, .{ .name = "fn", .number = 1, .kind = .{ .scalar = .int32 } });
    try file.messages.append(allocator, msg);

    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const @\"struct\" = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const @\"fn_number\" = 1") != null);
}

test "codegen emits typed scalar fields and encode method" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\message Person { int32 id = 1; string name = 2; bool active = 3; }
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "@\"id\": i32 = 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "@\"name\": []const u8 = \"\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn encode(self: @This(), allocator: std.mem.Allocator) ![]u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeInt32(1, self.@\"id\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.@\"name\".len != 0) { if (!std.unicode.utf8ValidateSlice(self.@\"name\")) return error.InvalidUtf8; try w.writeString(2, self.@\"name\"); }") != null);
}

test "codegen emits repeated scalar slice types" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\message Repeated { repeated int32 ids = 1; repeated string names = 2; repeated bool flags = 3; }
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "@\"ids\": []const i32 = &.{}") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "@\"names\": []const []const u8 = &.{}") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "@\"flags\": []const bool = &.{}") != null);
}

test "codegen encodes enum fields" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message User { Kind kind = 1; repeated Kind roles = 2; }
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "@\"kind\": i32 = 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "@\"roles\": []const i32 = &.{}") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeInt32(1, self.@\"kind\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeBytes(2, packed_writer.slice())") != null);
}

test "codegen encodes and decodes packed repeated scalar and enum fields" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message M {
        \\  repeated int32 ids = 1 [packed = true];
        \\  repeated Kind kinds = 2 [packed = true];
        \\}
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "var packed_writer = pbz.Writer.init(allocator)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try packed_writer.writeVarint(@as(u64, @bitCast(@as(i64, item))))") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeBytes(1, packed_writer.slice())") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeBytes(2, packed_writer.slice())") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (tag.wire_type == .length_delimited)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var packed_reader = pbz.Reader.init(try r.readBytes())") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "while (!packed_reader.eof()) try @\"ids_list\".append(allocator, try packed_reader.readInt32())") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "while (!packed_reader.eof()) { const value = try packed_reader.readInt32(); if (value != 0 and value != 1) return error.InvalidEnumValue; try @\"kinds_list\".append(allocator, value); }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try @\"ids_list\".append(allocator, try r.readInt32())") != null);
    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen emits message payload fields and encoders" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\message Child { int32 id = 1; }
        \\message Parent {
        \\  Child child = 1;
        \\  repeated Child children = 2;
        \\  oneof pick { Child picked = 3; }
        \\}
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "@\"child\": []const u8 = \"\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "@\"children\": []const []const u8 = &.{}") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "@\"has_child\": bool = false") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.@\"has_child\") try w.writeMessage(1, self.@\"child\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (self.@\"children\") |item| try w.writeMessage(2, item);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn jsonStringifyWithAllocator(self: @This(), allocator: std.mem.Allocator, writer: *std.Io.Writer) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var nested = try @\"Child\".decode(allocator, self.@\"child\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try nested.jsonStringifyWithAllocator(allocator, writer)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (self.@\"children\", 0..) |payload, i|") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, ".@\"picked\" => |value|") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var nested = try @\"Child\".jsonParse(arena_allocator") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.@\"pick\" = .{ .@\"picked\" = blk:") != null);
}

test "codegen emits JSON helpers for proto2 group payload fields" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Parent {
        \\  optional group Box = 1 { optional int32 id = 2; }
        \\  repeated group Item = 3 { optional string name = 4; }
        \\}
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "@\"Box\": []const u8 = \"\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "@\"Item\": []const []const u8 = &.{}") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var nested = try @\"Box\".decode(allocator, self.@\"Box\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (self.@\"Item\", 0..) |payload, i|") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var nested = try @\"Box\".jsonParse(arena_allocator") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var nested = try @\"Item\".jsonParse(arena_allocator") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.@\"Item\" = blk: { const old = self.@\"Item\"; const owned = try list.toOwnedSlice(allocator); if (old.len != 0) allocator.free(old); break :blk owned; };") != null);

    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen emits basic TextFormat formatters" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message Child { int32 id = 1; }
        \\message M {
        \\  int32 id = 1;
        \\  string name = 2;
        \\  repeated string tags = 3;
        \\  Kind kind = 4;
        \\  Child child = 5;
        \\  map<string, Child> kids = 6;
        \\  map<string, int32> counts = 7;
        \\  double ratio = 8;
        \\  oneof pick { string alias = 9; Kind picked = 10; Child picked_msg = 11; }
        \\}
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn formatTextAlloc(self: @This(), allocator: std.mem.Allocator) ![]u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn formatTextWithAllocator(self: @This(), allocator: std.mem.Allocator, writer: *std.Io.Writer) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.writeAll(\"id: \"); const value = self.@\"id\"; try writer.print(\"{d}\", .{value});") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.writeAll(\"tags: \"); try std.json.Stringify.value(value, .{}, writer);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try @This().textWriteEnum(writer, value, &.{\"UNKNOWN\", \"ADMIN\"}, &.{0, 1});") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn textWriteEnum(writer: *std.Io.Writer, value: i32, comptime names: []const []const u8, comptime numbers: []const i32) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.writeAll(\"child {\\n\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try nested.formatTextWithAllocator(allocator, writer);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.writeAll(\"kids {\\n\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.writeAll(\"value {\\n\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.writeAll(\"alias: \"); try std.json.Stringify.value(value, .{}, writer);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.writeAll(\"picked: \"); try @This().textWriteEnum(writer, value, &.{\"UNKNOWN\", \"ADMIN\"}, &.{0, 1});") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn parseText(allocator: std.mem.Allocator, text: []const u8) !@This()") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const line = @This().textCleanLine(raw_line);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (@This().textFieldValue(line, \"id\")) |raw_value|") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.@\"ratio\" = try @This().textFloat(f64, raw_value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "@\"tags_list\".append(allocator, try @This().textUnquote(try self.@\"_pbzOwnedAllocator\"(allocator), raw_value))") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.@\"kind\" = try @This().textEnum(raw_value, &.{\"UNKNOWN\", \"ADMIN\"}, &.{0, 1}, false);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (std.mem.eql(u8, line, \"counts {\") or std.mem.eql(u8, line, \"counts <\"))") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (@This().textFieldValue(entry_line, \"value\")) |raw_value| { entry.value = try @This().textInt(i32, raw_value); continue; }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (std.mem.eql(u8, entry_line, \"value {\") or std.mem.eql(u8, entry_line, \"value <\"))") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "entry.value = try nested.encode(owned_allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.@\"pick\" = .{ .@\"alias\" = try @This().textUnquote(try self.@\"_pbzOwnedAllocator\"(allocator), raw_value) };") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.@\"pick\" = .{ .@\"picked\" = try @This().textEnum(raw_value, &.{\"UNKNOWN\", \"ADMIN\"}, &.{0, 1}, false) };") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn textFieldValue(line: []const u8, comptime name: []const u8) ?[]const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn textCleanLine(raw_line: []const u8) []const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "line[line.len - 1] == ';' or line[line.len - 1] == ','") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn textInt(comptime T: type, value: []const u8) !T") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn textFloat(comptime T: type, value: []const u8) !T") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "std.ascii.eqlIgnoreCase(value, \"-inf\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn textUnquote(allocator: std.mem.Allocator, value: []const u8) ![]const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try std.fmt.parseInt(u8, body[i + 1 .. i + 3], 16)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn textEnum(value: []const u8, comptime names: []const []const u8, comptime numbers: []const i32, comptime closed: bool) !i32") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (std.mem.eql(u8, line, \"child {\") or std.mem.eql(u8, line, \"child <\"))") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const block = try @This().textBlock(allocator, &lines);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var nested = try @\"Child\".parseText(allocator, block);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const owned_allocator = try self.@\"_pbzOwnedAllocator\"(allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.@\"has_child\" and self.@\"child\".len != 0 and payload.len != 0)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "@memcpy(merged[0..self.@\"child\".len], self.@\"child\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (std.mem.eql(u8, line, \"picked_msg {\") or std.mem.eql(u8, line, \"picked_msg <\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "std.mem.eql(u8, line, \"pickedMsg {\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn textBlock(allocator: std.mem.Allocator, lines: anytype) ![]u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "std.mem.eql(u8, line, \">\")") != null);

    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen emits map entry types and encoders" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\message M { map<string, int32> counts = 1; }
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const @\"countsEntry\" = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "@\"counts\": []const @\"countsEntry\" = &.{}") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try entry_writer.writeString(1, entry.key)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try entry_writer.writeInt32(2, entry.value)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeMessage(1, entry_writer.slice())") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn encodeDeterministic(self: @This(), allocator: std.mem.Allocator) ![]u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "std.mem.sort(@\"countsEntry\", entries") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "std.mem.lessThan(u8, a.key, b.key)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn encodeDeterministicInitialized(self: @This(), allocator: std.mem.Allocator) ![]u8") != null);
}

test "codegen deterministic encoder emits fields by number" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\message M {
        \\  int32 later = 10;
        \\  oneof pick { int32 mid = 3; }
        \\  int32 first = 1;
        \\}
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);
    const deterministic_start = std.mem.indexOf(u8, content, "pub fn encodeDeterministic").?;
    const deterministic = content[deterministic_start..];
    const first_pos = std.mem.indexOf(u8, deterministic, "try w.writeInt32(1, self.@\"first\")").?;
    const mid_pos = std.mem.indexOf(u8, deterministic, ".@\"mid\" => |value| try w.writeInt32(3, value)").?;
    const later_pos = std.mem.indexOf(u8, deterministic, "try w.writeInt32(10, self.@\"later\")").?;
    try std.testing.expect(first_pos < mid_pos);
    try std.testing.expect(mid_pos < later_pos);
}

test "codegen emits map JSON stringify and parse helpers" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message Child { int32 id = 1; }
        \\message M {
        \\  map<string, int32> counts = 1;
        \\  map<int32, string> names = 2;
        \\  map<bool, Kind> flags = 3;
        \\  map<string, Child> kids = 4;
        \\}
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.@\"counts\".len != 0)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (self.@\"counts\", 0..) |entry, i|") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try std.json.Stringify.value(entry.key, .{}, writer)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.print(\"{d}\", .{entry.value})") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.print(\"\\\"{d}\\\"\", .{entry.key})") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try std.json.Stringify.value(entry.value, .{}, writer)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.writeAll(if (entry.key) \"\\\"true\\\"\" else \"\\\"false\\\"\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try @This().jsonWriteEnum(writer, entry.value, &.{\"UNKNOWN\", \"ADMIN\"}, &.{0, 1})") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var nested = try @\"Child\".decode(allocator, entry.value); defer nested.deinit(allocator); try nested.jsonStringifyWithAllocator(allocator, writer);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const object_value = switch (value) { .object => |map_object| map_object, else => return error.TypeMismatch }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try list.append(allocator, .{ .key = map_entry.key_ptr.*, .value = try @This().jsonInt(i32, map_entry.value_ptr.*) })") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.@\"counts\" = blk: { const old = self.@\"counts\"; const owned = try list.toOwnedSlice(allocator); if (old.len != 0) allocator.free(old); break :blk owned; };") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.@\"counts\" = &.{}; if (old.len != 0) allocator.free(old);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try std.fmt.parseInt(i32, map_entry.key_ptr.*, 10)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try @This().jsonMapKeyBool(map_entry.key_ptr.*)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try @This().jsonEnum(map_entry.value_ptr.*, &.{\"UNKNOWN\", \"ADMIN\"}, &.{0, 1}, false)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try list.append(allocator, .{ .key = map_entry.key_ptr.*, .value = blk: { var nested = try @\"Child\".jsonParse(arena_allocator") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.@\"kids\" = blk: { const old = self.@\"kids\"; const owned = try list.toOwnedSlice(allocator); if (old.len != 0) allocator.free(old); break :blk owned; };") != null);
    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen emits basic decode method" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message Person { int32 id = 1; string name = 2; Kind kind = 3; bytes payload = 4; }
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) !@This()") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "_ = allocator;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "1 => { self.@\"id\" = try r.readInt32(); }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "2 => { self.@\"name\" = try r.readBytes(); if (!std.unicode.utf8ValidateSlice(self.@\"name\")) return error.InvalidUtf8; }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "3 => { const value = try r.readInt32(); self.@\"kind\" = value; }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "4 => { self.@\"payload\" = try r.readBytes(); }") != null);
}

test "codegen decodes repeated scalar enum and message payload fields" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message Child { int32 id = 1; }
        \\message M { repeated int32 ids = 1; repeated Kind kinds = 2; repeated Child children = 3; }
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "var @\"ids_list\": std.ArrayList(i32) = .empty") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try @\"ids_list\".append(allocator, try r.readInt32())") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "{ const value = try r.readInt32(); try @\"kinds_list\".append(allocator, value); }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try @\"children_list\".append(allocator, try r.readBytes())") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.@\"ids\" = try @\"ids_list\".toOwnedSlice(allocator)") != null);
}

test "codegen decodes map fields into entry slices" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\message M { map<string, int32> counts = 1; }
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "var @\"counts_list\": std.ArrayList(@\"countsEntry\") = .empty") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var entry = @\"countsEntry\"{}") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "1 => { const value = try entry_reader.readBytes(); if (!std.unicode.utf8ValidateSlice(value)) return error.InvalidUtf8; entry.key = value; }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "2 => entry.value = try entry_reader.readInt32()") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "@\"counts_list\".append(allocator, entry)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.@\"counts\" = try @\"counts_list\".toOwnedSlice(allocator)") != null);
}

test "codegen emits presence flags for optional required and proto3 optional fields" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message M { optional int32 a = 1; required string b = 2; }
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "@\"has_a\": bool = false") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "@\"has_b\": bool = false") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.@\"has_a\") try w.writeInt32(1, self.@\"a\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.@\"a\" = try r.readInt32(); self.@\"has_a\" = true") != null);

    var file3 = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\message M { optional int32 a = 1; int32 b = 2; }
    );
    defer file3.deinit();
    const content3 = try generateZigFile(allocator, &file3);
    defer allocator.free(content3);
    try std.testing.expect(std.mem.indexOf(u8, content3, "@\"has_a\": bool = false") != null);
    try std.testing.expect(std.mem.indexOf(u8, content3, "@\"has_b\": bool = false") == null);
}

test "codegen emits proto2 scalar and enum defaults" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\enum Kind { UNKNOWN = 0; ADMIN = 7; }
        \\message Defaults {
        \\  optional int32 count = 1 [default = 42];
        \\  optional string name = 2 [default = "hello\nworld"];
        \\  optional bool enabled = 3 [default = true];
        \\  optional Kind kind = 4 [default = ADMIN];
        \\  optional bytes raw = 5 [default = "\001\x02"];
        \\  optional float ratio = 6 [default = inf];
        \\}
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "@\"count\": i32 = 42") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "@\"name\": []const u8 = \"hello\\nworld\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "@\"enabled\": bool = true") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "@\"kind\": i32 = 7") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "@\"raw\": []const u8 = \"\\x01\\x02\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "@\"ratio\": f32 = std.math.inf(f32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "@\"has_count\": bool = false") != null);
    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen output parses as Zig source" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message Child { int32 id = 1; }
        \\message Person {
        \\  optional int32 id = 1;
        \\  string name = 2;
        \\  repeated string tags = 3;
        \\  Kind kind = 4;
        \\  Child child = 5;
        \\  map<string, int32> counts = 6;
        \\  bytes raw = 7;
        \\  repeated int64 nums = 8;
        \\  double ratio = 9;
        \\  oneof pick {
        \\    bool active = 10;
        \\    string alias = 11;
        \\  }
        \\}
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);
    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen emits typed json stringify and parse methods" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message M {
        \\  int32 id = 1;
        \\  string name = 2;
        \\  int64 big = 3;
        \\  bytes raw = 4;
        \\  repeated string tags = 5;
        \\  optional bool active = 6;
        \\  Kind kind = 7;
        \\  int32 user_id = 10;
        \\  string display_name = 11 [json_name = "shownName"];
        \\  oneof choice {
        \\    string alias = 8;
        \\    int32 code = 9;
        \\    string alt_name = 12;
        \\    Kind pick_kind = 13;
        \\  }
        \\}
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn jsonStringifyAlloc(self: @This(), allocator: std.mem.Allocator) ![]u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn jsonStringify(self: @This(), writer: *std.Io.Writer) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.writeAll(\"\\\"id\\\":\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.writeAll(\"\\\"userId\\\":\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.writeAll(\"\\\"shownName\\\":\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try @This().jsonWriteEnum(writer, value, &.{\"UNKNOWN\", \"ADMIN\"}, &.{0, 1});") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try std.json.Stringify.value(value, .{}, writer);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.print(\"\\\"{d}\\\"\", .{value});") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try std.base64.standard.Encoder.encodeWriter(writer, value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (self.@\"tags\", 0..) |item, i|") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.@\"has_active\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "switch (self.@\"choice\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, ".@\"alias\" => |value|") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn jsonParse(allocator: std.mem.Allocator, text: []const u8) !@This()") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), text, .{})") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try self.jsonFillFromValue(allocator, arena.allocator(), parsed)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.@\"_json_arena\" = arena") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn jsonParseInitialized(allocator: std.mem.Allocator, text: []const u8) !@This()") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var self = try @This().jsonParse(allocator, text);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try self.validateRequiredRecursive(allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn jsonFillFromValue(self: *@This(), allocator: std.mem.Allocator, arena_allocator: std.mem.Allocator, json_value: std.json.Value) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (value == .null)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.@\"id\" = try @This().jsonInt(i32, value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "std.mem.eql(u8, key, \"user_id\") or std.mem.eql(u8, key, \"userId\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "std.mem.eql(u8, key, \"display_name\") or std.mem.eql(u8, key, \"shownName\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.@\"raw\" = try @This().jsonBytes(arena_allocator, value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.@\"kind\" = try @This().jsonEnum(value, &.{\"UNKNOWN\", \"ADMIN\"}, &.{0, 1}, false);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (array.items) |item| try list.append(allocator, try @This().jsonString(item));") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.@\"tags\" = blk: { const old = self.@\"tags\"; const owned = try list.toOwnedSlice(allocator); if (old.len != 0) allocator.free(old); break :blk owned; };") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.@\"tags\" = &.{}; if (old.len != 0) allocator.free(old);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.@\"choice\" = .{ .@\"alias\" = try @This().jsonString(value) };") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.@\"choice\" = .none; continue;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "std.mem.eql(u8, key, \"alt_name\") or std.mem.eql(u8, key, \"altName\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.@\"choice\" = .{ .@\"pick_kind\" = try @This().jsonEnum(value, &.{\"UNKNOWN\", \"ADMIN\"}, &.{0, 1}, false) };") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn jsonEnum(value: std.json.Value, comptime names: []const []const u8, comptime numbers: []const i32, comptime closed: bool) !i32") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn jsonEnumNumber(value: i32, comptime numbers: []const i32, comptime closed: bool) !i32") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn jsonWriteEnum(writer: *std.Io.Writer, value: i32, comptime names: []const []const u8, comptime numbers: []const i32) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn jsonDecodeBase64(allocator: std.mem.Allocator, value: []const u8) ![]u8") != null);
}

test "codegen emits required validation" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message M { required int32 id = 1; optional string name = 2; }
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn encodeInitialized(self: @This(), allocator: std.mem.Allocator) ![]u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try self.validateRequired();") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try self.encode(allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn decodeInitialized(allocator: std.mem.Allocator, bytes: []const u8) !@This()") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var self = try @This().decode(allocator, bytes);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "errdefer self.deinit(allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn missingRequiredFieldName(self: @This()) ?[]const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (!self.@\"has_id\") return \"id\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn validateRequired(self: @This()) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.missingRequiredFieldName() != null) return error.MissingRequiredField") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "has_name") != null);
    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen emits recursive required validation for message payloads" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Child { required int32 id = 1; }
        \\message Parent {
        \\  optional Child child = 1;
        \\  repeated Child children = 2;
        \\  oneof pick { Child picked = 3; }
        \\  map<string, Child> keyed = 4;
        \\}
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn validateRequiredRecursive(self: @This(), allocator: std.mem.Allocator) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn missingRequiredFieldPath(self: @This(), allocator: std.mem.Allocator) !?[]u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var nested = try @\"Child\".decode(allocator, self.@\"child\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (self.@\"children\") |payload|") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, ".@\"picked\" => |payload|") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (self.@\"keyed\") |entry|") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var nested = try @\"Child\".decode(allocator, entry.value)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try nested.validateRequiredRecursive(allocator)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try std.fmt.allocPrint(allocator, \"child.{s}\", .{suffix});") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try std.fmt.allocPrint(allocator, \"children.{s}\", .{suffix});") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try std.fmt.allocPrint(allocator, \"keyed.{s}\", .{suffix});") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try std.fmt.allocPrint(allocator, \"picked.{s}\", .{suffix});") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try self.validateRequiredRecursive(allocator);") != null);
    const json_initialized_start = std.mem.indexOf(u8, content, "pub fn jsonParseInitialized").?;
    const json_initialized = content[json_initialized_start..];
    try std.testing.expect(std.mem.indexOf(u8, json_initialized, "try self.validateRequiredRecursive(allocator);") != null);
    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen emits mergeFrom for singular message payloads and groups" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Child { optional int32 id = 1; optional string name = 2; }
        \\message Parent {
        \\  optional int32 id = 1;
        \\  repeated int32 nums = 2;
        \\  optional Child child = 3;
        \\  optional group Box = 4 { optional int32 a = 5; optional int32 b = 6; }
        \\  oneof pick { string name = 7; Child picked = 8; }
        \\}
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "fn @\"_pbzOwnedAllocator\"(self: *@This(), allocator: std.mem.Allocator) !std.mem.Allocator") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn mergeFrom(self: *@This(), allocator: std.mem.Allocator, other: @This()) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (other.@\"nums\".len != 0)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const merged = try allocator.alloc(i32, old.len + other.@\"nums\".len)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (other.@\"has_child\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const owned_allocator = try self.@\"_pbzOwnedAllocator\"(allocator)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const merged = try owned_allocator.alloc(u8, self.@\"child\".len + other.@\"child\".len)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "@memcpy(merged[0..self.@\"child\".len], self.@\"child\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (other.@\"has_Box\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const merged = try owned_allocator.alloc(u8, self.@\"Box\".len + other.@\"Box\".len)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "switch (other.@\"pick\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, ".@\"picked\" => |value| self.@\"pick\" = .{ .@\"picked\" = value }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "3 => { const payload = try r.readBytes(); if (self.@\"has_child\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "4 => { const payload = try r.readGroupBytes(4); if (self.@\"has_Box\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.@\"has_Box\") { try w.writeTag(4, .start_group); try w.appendSlice(self.@\"Box\"); try w.writeTag(4, .end_group); }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var nested = try @\"Box\".decode(allocator, self.@\"Box\")") != null);

    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen maps oneof to tagged union" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\message Choice { oneof pick { string name = 1; int32 id = 2; } }
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const @\"pickOneof\" = union(enum)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "@\"name\": []const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "@\"pick\": @\"pickOneof\" = .none") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "switch (self.@\"pick\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, ".@\"name\" => |value| { if (!std.unicode.utf8ValidateSlice(value)) return error.InvalidUtf8; try w.writeString(1, value); }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "1 => { const value = try r.readBytes(); if (!std.unicode.utf8ValidateSlice(value)) return error.InvalidUtf8; self.@\"pick\" = .{ .@\"name\" = value }; }") != null);
}

test "codegen emits proto2 extension metadata" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host { extensions 100 to max; }
        \\message Note {}
        \\extend Host {
        \\  optional string tag = 100;
        \\  repeated int32 nums = 101;
        \\  optional Note note = 102;
        \\}
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const extensions = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const @\"tag\" = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const number = 100") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const extendee = \"Host\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const cardinality = \"optional\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const value_type = \"string\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const zig_type = \"[]const u8\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn write(w: *pbz.Writer, value: []const u8) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeString(100, value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn decodeValue(r: *pbz.Reader) ![]const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try r.readBytes();") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const @\"nums\" = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const cardinality = \"repeated\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn writeAll(w: *pbz.Writer, values: []const i32) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (values) |value| try write(w, value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn decodeAppend(allocator: std.mem.Allocator, list: *std.ArrayList(i32), r: *pbz.Reader) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try list.append(allocator, try decodeValue(r));") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const value_type = \"Note\"") != null);
    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen emits MessageSet extension write helper" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Host { option message_set_wire_format = true; extensions 4 to max; }
        \\message Note { optional int32 id = 1; }
        \\extend Host { optional Note note = 100; }
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeTag(1, .start_group);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeUInt32(2, 100);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeMessage(3, value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeTag(1, .end_group);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn decodeMessageSetItem(r: *pbz.Reader) !?[]const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return if (type_id != null and type_id.? == 100) payload else null;") != null);
    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen emits service metadata and stubs" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Req {}
        \\message Res {}
        \\service Directory {
        \\  rpc Get (Req) returns (Res);
        \\  rpc Stream (stream Req) returns (stream Res);
        \\}
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const services = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const @\"Directory\" = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const name = \"Directory\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const @\"Get\" = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const input_type = \"Req\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const output_type = \"Res\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const client_streaming = true") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const server_streaming = true") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const Handler = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return error.Unimplemented;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const Client = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try self.call(self.context, \"Directory\", \"Get\", request, allocator);") != null);
    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen skips proto3 implicit default scalar and enum values" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message M { int32 id = 1; bool active = 2; Kind kind = 3; optional int32 opt = 4; }
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.@\"id\" != 0) try w.writeInt32(1, self.@\"id\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.@\"active\") try w.writeBool(2, self.@\"active\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.@\"kind\" != 0) try w.writeInt32(3, self.@\"kind\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.@\"has_opt\") try w.writeInt32(4, self.@\"opt\")") != null);
}

test "codegen honors editions field presence features" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\edition = "2023";
        \\option features.field_presence = EXPLICIT;
        \\message M {
        \\  int32 explicit_id = 1;
        \\  int32 implicit_id = 2 [features.field_presence = IMPLICIT];
        \\  int32 required_id = 3 [features.field_presence = LEGACY_REQUIRED];
        \\}
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "@\"has_explicit_id\": bool = false") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "@\"has_implicit_id\": bool = false") == null);
    try std.testing.expect(std.mem.indexOf(u8, content, "@\"has_required_id\": bool = false") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.@\"has_explicit_id\") try w.writeInt32(1, self.@\"explicit_id\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.@\"implicit_id\" != 0) try w.writeInt32(2, self.@\"implicit_id\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.@\"has_required_id\") try w.writeInt32(3, self.@\"required_id\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.@\"explicit_id\" = try r.readInt32(); self.@\"has_explicit_id\" = true") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.@\"required_id\" = try r.readInt32(); self.@\"has_required_id\" = true") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (!self.@\"has_required_id\") return \"required_id\";") != null);
}

test "codegen honors editions message encoding features" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\edition = "2023";
        \\option features.message_encoding = DELIMITED;
        \\message Child { int32 id = 1; }
        \\message Parent {
        \\  Child delimited = 1;
        \\  Child length_prefixed = 2 [features.message_encoding = LENGTH_PREFIXED];
        \\  oneof pick { Child picked = 3 [features.message_encoding = DELIMITED]; }
        \\}
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeTag(1, .start_group); try w.appendSlice(self.@\"delimited\"); try w.writeTag(1, .end_group);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeMessage(2, self.@\"length_prefixed\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeTag(3, .start_group); try w.appendSlice(value); try w.writeTag(3, .end_group)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const payload = try r.readGroupBytes(1); if (self.@\"has_delimited\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.@\"has_delimited\" = true;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const payload = try r.readBytes(); if (self.@\"has_length_prefixed\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.@\"has_length_prefixed\" = true;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.@\"pick\" = .{ .@\"picked\" = try r.readGroupBytes(3) }") != null);

    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen honors utf8 validation features for wire strings" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\message M {
        \\  string strict = 1;
        \\  string relaxed = 2 [features.utf8_validation = NONE];
        \\  repeated string tags = 3;
        \\  oneof pick { string alias = 4; }
        \\  map<string, string> labels = 5;
        \\  map<string, string> relaxed_labels = 6 [features.utf8_validation = NONE];
        \\}
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.@\"strict\".len != 0) { if (!std.unicode.utf8ValidateSlice(self.@\"strict\")) return error.InvalidUtf8; try w.writeString(1, self.@\"strict\"); }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.@\"relaxed\".len != 0) try w.writeString(2, self.@\"relaxed\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (self.@\"tags\") |item| { if (!std.unicode.utf8ValidateSlice(item)) return error.InvalidUtf8; try w.writeString(3, item); }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, ".@\"alias\" => |value| { if (!std.unicode.utf8ValidateSlice(value)) return error.InvalidUtf8; try w.writeString(4, value); }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "1 => { self.@\"strict\" = try r.readBytes(); if (!std.unicode.utf8ValidateSlice(self.@\"strict\")) return error.InvalidUtf8; }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "2 => { self.@\"relaxed\" = try r.readBytes(); }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "3 => { const value = try r.readBytes(); if (!std.unicode.utf8ValidateSlice(value)) return error.InvalidUtf8; try @\"tags_list\".append(allocator, value); },") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "4 => { const value = try r.readBytes(); if (!std.unicode.utf8ValidateSlice(value)) return error.InvalidUtf8; self.@\"pick\" = .{ .@\"alias\" = value }; }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (!std.unicode.utf8ValidateSlice(entry.key)) return error.InvalidUtf8;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (!std.unicode.utf8ValidateSlice(entry.value)) return error.InvalidUtf8;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "1 => { const value = try entry_reader.readBytes(); if (!std.unicode.utf8ValidateSlice(value)) return error.InvalidUtf8; entry.key = value; }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "2 => { const value = try entry_reader.readBytes(); if (!std.unicode.utf8ValidateSlice(value)) return error.InvalidUtf8; entry.value = value; }") != null);
}

test "codegen honors editions enum type features in JSON parse" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\edition = "2023";
        \\option features.enum_type = OPEN;
        \\enum ClosedKind { option features.enum_type = CLOSED; UNKNOWN = 0; ADMIN = 1; }
        \\enum OpenKind { option features.enum_type = OPEN; NONE = 0; USER = 1; }
        \\message M {
        \\  ClosedKind closed = 1;
        \\  OpenKind open = 2;
        \\}
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "self.@\"closed\" = try @This().jsonEnum(value, &.{\"UNKNOWN\", \"ADMIN\"}, &.{0, 1}, true);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.@\"open\" = try @This().jsonEnum(value, &.{\"NONE\", \"USER\"}, &.{0, 1}, false);") != null);
}

test "codegen validates closed enum values in wire decode" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\edition = "2023";
        \\option features.enum_type = OPEN;
        \\enum ClosedKind { option features.enum_type = CLOSED; UNKNOWN = 0; ADMIN = 1; }
        \\message M {
        \\  ClosedKind single = 1;
        \\  repeated ClosedKind many = 2;
        \\  oneof pick { ClosedKind choice = 3; }
        \\}
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "1 => { const value = try r.readInt32(); if (value != 0 and value != 1) return error.InvalidEnumValue; self.@\"single\" = value; self.@\"has_single\" = true; }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "while (!packed_reader.eof()) { const value = try packed_reader.readInt32(); if (value != 0 and value != 1) return error.InvalidEnumValue; try @\"many_list\".append(allocator, value); }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "{ const value = try r.readInt32(); if (value != 0 and value != 1) return error.InvalidEnumValue; try @\"many_list\".append(allocator, value); }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "3 => { const value = try r.readInt32(); if (value != 0 and value != 1) return error.InvalidEnumValue; self.@\"pick\" = .{ .@\"choice\" = value }; }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.@\"single\" = try @This().textEnum(raw_value, &.{\"UNKNOWN\", \"ADMIN\"}, &.{0, 1}, true);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "@\"many_list\".append(allocator, try @This().textEnum(raw_value, &.{\"UNKNOWN\", \"ADMIN\"}, &.{0, 1}, true))") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.@\"pick\" = .{ .@\"choice\" = try @This().textEnum(raw_value, &.{\"UNKNOWN\", \"ADMIN\"}, &.{0, 1}, true) };") != null);
}

test "codegen validates closed enum map values in wire decode" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\edition = "2023";
        \\option features.enum_type = OPEN;
        \\enum ClosedKind { option features.enum_type = CLOSED; UNKNOWN = 0; ADMIN = 1; }
        \\message M { map<string, ClosedKind> keyed = 1; }
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "2 => { const value = try entry_reader.readInt32(); if (value != 0 and value != 1) return error.InvalidEnumValue; entry.value = value; }") != null);
}
