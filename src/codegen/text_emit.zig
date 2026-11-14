const std = @import("std");
const schema = @import("../schema.zig");

const cg = @import("../codegen.zig");
const Error = cg.Error;
const CodegenContext = cg.CodegenContext;

pub fn writeTextParseMethods(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try cg.indent(writer, depth);
    try writer.writeAll("pub const TextParseOptions = struct { ignore_unknown_fields: bool = false };\n\n");

    try cg.indent(writer, depth);
    try writer.writeAll("pub fn parseText(allocator: std.mem.Allocator, text: []const u8) anyerror!@This() {\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("return try @This().parseTextWithOptions(allocator, text, .{});\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n\n");

    try cg.indent(writer, depth);
    try writer.writeAll("pub fn parseTextWithOptions(allocator: std.mem.Allocator, text: []const u8, options: @This().TextParseOptions) anyerror!@This() {\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("return @This().parseTextFastWithOptions(allocator, text, options) catch @This().parseTextConformantWithOptions(allocator, text, options);\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n\n");

    try cg.indent(writer, depth);
    try writer.writeAll("pub fn parseTextConformantWithOptions(allocator: std.mem.Allocator, text: []const u8, options: @This().TextParseOptions) anyerror!@This() {\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("_ = options;\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("var arena = std.heap.ArenaAllocator.init(allocator);\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("defer arena.deinit();\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("var registry: pbz.Registry = undefined;\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("const file = try _pbzFileRegistry(arena.allocator(), &registry);\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("defer registry.deinit();\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("const message_descriptor = @This().descriptor(file) orelse return error.TypeMismatch;\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("var dynamic = try pbz.text.parseAllocWithRegistry(allocator, file, &registry, message_descriptor, text);\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("defer dynamic.deinit();\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("return try @This().fromDynamic(allocator, file, &dynamic);\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n\n");

    try cg.indent(writer, depth);
    try writer.writeAll("fn parseTextFastWithOptions(allocator: std.mem.Allocator, text: []const u8, options: @This().TextParseOptions) anyerror!@This() {\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("var self = @This().init();\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("errdefer self.deinit(allocator);\n");
    for (message.fields.items) |*field| try cg.writeRepeatedListDecl(ctx, field, writer, depth + 1);
    try cg.indent(writer, depth + 1);
    try writer.writeAll("var _unknown_fields_list: std.ArrayList([]const u8) = .empty;\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("errdefer pbz.wire.deinitRawFieldList(allocator, &_unknown_fields_list);\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("const needs_normalized_text = @This().textNeedsSeparatorNormalization(text);\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("const normalized_text = if (needs_normalized_text) try @This().textNormalizeSeparators(allocator, text) else text;\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("defer if (needs_normalized_text) allocator.free(normalized_text);\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("const text_has_comments = std.mem.indexOfScalar(u8, normalized_text, '#') != null;\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("var lines = std.mem.splitScalar(u8, normalized_text, '\\n');\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("while (lines.next()) |raw_line| {\n");
    try cg.indent(writer, depth + 2);
    try writer.writeAll("const line = @This().textCleanLine(raw_line, text_has_comments);\n");
    try cg.indent(writer, depth + 2);
    try writer.writeAll("if (line.len == 0) continue;\n");
    for (message.fields.items) |*field| {
        if (field.oneof_name == null) try writeTextParseField(ctx, field, writer, depth + 2);
    }
    for (message.oneofs.items) |oneof| {
        for (message.fields.items) |*field| {
            if (field.oneof_name) |name| {
                if (std.mem.eql(u8, name, oneof.name)) try writeTextParseOneofField(ctx, oneof, field, writer, depth + 2);
            }
        }
    }
    try writeTextParseExtensions(ctx, message, writer, depth + 2);
    try cg.indent(writer, depth + 2);
    try writer.writeAll("if (try @This().textUnknownField(allocator, line)) |raw| { try pbz.wire.appendOwnedRawField(allocator, &_unknown_fields_list, raw); continue; }\n");
    try cg.indent(writer, depth + 2);
    try writer.writeAll("if (try @This().textUnknownGroup(allocator, line, &lines, text_has_comments)) |raw| { try pbz.wire.appendOwnedRawField(allocator, &_unknown_fields_list, raw); continue; }\n");
    try cg.indent(writer, depth + 2);
    try writer.writeAll("if (options.ignore_unknown_fields) continue;\n");
    try cg.indent(writer, depth + 2);
    try writer.writeAll("return error.UnknownField;\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("}\n");
    for (message.fields.items) |*field| try cg.writeRepeatedAssign(field, writer, depth + 1);
    try cg.indent(writer, depth + 1);
    try writer.writeAll("self._unknown_fields = try pbz.wire.rawFieldListToOwnedSlice(allocator, &_unknown_fields_list);\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("return self;\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n\n");

    try cg.indent(writer, depth);
    try writer.writeAll("pub fn parseTextInitialized(allocator: std.mem.Allocator, text: []const u8) !@This() {\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("var self = try @This().parseText(allocator, text);\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("errdefer self.deinit(allocator);\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("try self.validateRequiredRecursive(allocator);\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("return self;\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n\n");

    try cg.indent(writer, depth);
    try writer.writeAll("pub fn parseTextInitializedWithOptions(allocator: std.mem.Allocator, text: []const u8, options: @This().TextParseOptions) !@This() {\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("var self = try @This().parseTextWithOptions(allocator, text, options);\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("errdefer self.deinit(allocator);\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("try self.validateRequiredRecursive(allocator);\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("return self;\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeTextParseExtensions(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    for (file.extensions.items) |*field| {
        if (cg.extensionAppliesToMessage(file, message, field)) try writeTextParseExtensionField(ctx, field, writer, depth);
    }
    for (file.messages.items) |*scope| try writeTextParseMessageExtensions(ctx, message, scope, writer, depth);
}

pub fn writeTextParseMessageExtensions(ctx: *const CodegenContext, target: *const schema.MessageDescriptor, scope: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    for (scope.extensions.items) |*field| {
        if (cg.extensionAppliesToMessage(file, target, field)) try writeTextParseExtensionField(ctx, field, writer, depth);
    }
    for (scope.messages.items) |*nested| try writeTextParseMessageExtensions(ctx, target, nested, writer, depth);
}

pub fn writeTextParseExtensionField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    switch (field.kind) {
        .scalar, .enumeration => {},
        .message, .group => |type_name| {
            if (!cg.codegenCanReferenceMessageWithContext(ctx, type_name)) return;
            return try writeTextParseMessageExtensionField(ctx, field, type_name, writer, depth);
        },
        else => return,
    }
    try cg.indent(writer, depth);
    try writer.writeAll("if (");
    try writeExtensionTextValueLookup(file, field, "line", writer);
    try writer.writeAll(") |raw_value| {\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("const raw = try ");
    try cg.writeExtensionHelperReference(field, writer);
    try writer.writeAll(".encodeRaw(allocator, ");
    if (field.kind == .enumeration) {
        try writeTextParseEnumExpr(file, field.kind.enumeration, "raw_value", writer);
        try writer.writeAll(" catch |err| { if (options.ignore_unknown_fields) { continue; } return err; }");
    } else {
        try writeTextParseValueExpr(file, field, field.kind, "raw_value", writer);
    }
    try writer.writeAll(");\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("errdefer allocator.free(raw);\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("try _unknown_fields_list.append(allocator, raw);\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("continue;\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeTextParseMessageExtensionField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, type_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    try cg.indent(writer, depth);
    try writer.writeAll("if (");
    try writeExtensionTextBlockCondition(file, field, "line", writer);
    try writer.writeAll(") {\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("const block = try @This().textBlock(allocator, &lines, text_has_comments);\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("defer allocator.free(block);\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("var _pbz_nested = try ");
    try cg.writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    try writer.writeAll(".parseTextWithOptions(allocator, block, .{ .ignore_unknown_fields = options.ignore_unknown_fields });\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("defer _pbz_nested.deinit(allocator);\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("const owned_allocator = try self._pbzOwnedAllocator(allocator);\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("const payload = try _pbz_nested.encode(owned_allocator);\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("const raw = try ");
    try cg.writeExtensionHelperReference(field, writer);
    try writer.writeAll(".encodeRaw(allocator, payload);\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("errdefer allocator.free(raw);\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("try _unknown_fields_list.append(allocator, raw);\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("continue;\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeTextParseField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    switch (field.kind) {
        .scalar, .enumeration => {},
        .message, .group => |type_name| return try writeTextParseMessageField(ctx, field, type_name, writer, depth),
        .map => return try writeTextParseMapField(ctx, field, writer, depth),
    }
    try cg.indent(writer, depth);
    try writer.writeAll("if (");
    try writeTextFieldValueLookup(field, "line", writer);
    try writer.writeAll(") |raw_value| {\n");
    if (field.cardinality == .repeated) {
        try cg.indent(writer, depth + 1);
        if (field.kind == .enumeration) {
            try writer.writeAll("const parsed_enum = ");
            try writeTextParseEnumExpr(file, field.kind.enumeration, "raw_value", writer);
            try writer.writeAll(" catch |err| { if (options.ignore_unknown_fields) { continue; } return err; };\n");
            try cg.indent(writer, depth + 1);
            try writer.writeAll("try ");
            try cg.writeQuotedIdentWithSuffix(field.name, "_list", writer);
            try writer.writeAll(".append(allocator, parsed_enum);\n");
        } else {
            try writer.writeAll("try ");
            try cg.writeQuotedIdentWithSuffix(field.name, "_list", writer);
            try writer.writeAll(".append(allocator, ");
            try writeTextParseValueExpr(file, field, field.kind, "raw_value", writer);
            try writer.writeAll(");\n");
        }
    } else {
        try cg.indent(writer, depth + 1);
        try writer.writeAll("self.");
        try cg.writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = ");
        if (field.kind == .enumeration) {
            try writeTextParseEnumExpr(file, field.kind.enumeration, "raw_value", writer);
            try writer.writeAll(" catch |err| { if (options.ignore_unknown_fields) { continue; } return err; }");
        } else {
            try writeTextParseValueExpr(file, field, field.kind, "raw_value", writer);
        }
        try writer.writeAll(";\n");
        if (cg.hasPresence(file, field.*)) {
            try cg.indent(writer, depth + 1);
            try writer.writeAll("self.");
            try cg.writePresenceIdent(field.name, writer);
            try writer.writeAll(" = true;\n");
        }
    }
    try cg.indent(writer, depth + 1);
    try writer.writeAll("continue;\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeTextParseMessageField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, type_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    if (!cg.codegenCanReferenceMessageWithContext(ctx, type_name)) return;
    try cg.indent(writer, depth);
    try writer.writeAll("if (");
    try writeTextBlockCondition(field, "line", writer);
    try writer.writeAll(") {\n");
    try writeTextParseMessagePayloadAssign(ctx, field, type_name, writer, depth + 1);
    try cg.indent(writer, depth + 1);
    try writer.writeAll("continue;\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeTextParseMessagePayloadAssign(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, type_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    try cg.indent(writer, depth);
    try writer.writeAll("const block = try @This().textBlock(allocator, &lines, text_has_comments);\n");
    try cg.indent(writer, depth);
    try writer.writeAll("defer allocator.free(block);\n");
    try cg.indent(writer, depth);
    try writer.writeAll("var _pbz_nested = try ");
    try cg.writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    try writer.writeAll(".parseTextWithOptions(allocator, block, .{ .ignore_unknown_fields = options.ignore_unknown_fields });\n");
    if (cg.typedRepeatedMessageFieldWithContext(ctx, field)) |_| {
        try cg.indent(writer, depth);
        try writer.writeAll("{\n");
        try cg.indent(writer, depth + 1);
        try writer.writeAll("errdefer _pbz_nested.deinit(allocator);\n");
        try cg.indent(writer, depth + 1);
        try writer.writeAll("try ");
        try cg.writeQuotedIdentWithSuffix(field.name, "_list", writer);
        try writer.writeAll(".append(allocator, _pbz_nested);\n");
        try cg.indent(writer, depth);
        try writer.writeAll("}\n");
        return;
    }
    if (cg.typedSingularMessageFieldWithContext(ctx, field)) |_| {
        try cg.indent(writer, depth);
        try writer.writeAll("if (self.");
        try cg.writeQuotedIdent(field.name, writer);
        try writer.writeAll(") |*existing| { defer _pbz_nested.deinit(allocator); try existing.mergeFrom(allocator, _pbz_nested); } else { errdefer _pbz_nested.deinit(allocator); self.");
        try cg.writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = _pbz_nested; }\n");
        return;
    }
    if (cg.typedOneofMessageFieldWithContext(ctx, field)) |_| {
        const oneof_name = field.oneof_name orelse return;
        try cg.indent(writer, depth);
        try writer.writeAll("{\n");
        try cg.indent(writer, depth + 1);
        try writer.writeAll("errdefer _pbz_nested.deinit(allocator);\n");
        try cg.indent(writer, depth + 1);
        try cg.writeOneofDeinitCall(oneof_name, writer);
        try writer.writeAll("\n");
        try cg.indent(writer, depth + 1);
        try writer.writeAll("self.");
        try cg.writeQuotedIdent(oneof_name, writer);
        try writer.writeAll(" = .{ .");
        try cg.writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = _pbz_nested };\n");
        try cg.indent(writer, depth);
        try writer.writeAll("}\n");
        return;
    }
    try cg.indent(writer, depth);
    try writer.writeAll("defer _pbz_nested.deinit(allocator);\n");
    try cg.indent(writer, depth);
    try writer.writeAll("const owned_allocator = try self._pbzOwnedAllocator(allocator);\n");
    try cg.indent(writer, depth);
    try writer.writeAll("const payload = try _pbz_nested.encode(owned_allocator);\n");
    if (field.cardinality == .repeated) {
        try cg.indent(writer, depth);
        try writer.writeAll("try ");
        try cg.writeQuotedIdentWithSuffix(field.name, "_list", writer);
        try writer.writeAll(".append(allocator, payload);\n");
    } else {
        if (field.oneof_name) |oneof_name| {
            try cg.indent(writer, depth);
            try writer.writeAll("self.");
            try cg.writeQuotedIdent(oneof_name, writer);
            try writer.writeAll(" = .{ .");
            try cg.writeQuotedIdent(field.name, writer);
            try writer.writeAll(" = payload };\n");
        } else {
            try cg.indent(writer, depth);
            try writer.writeAll("if (self.");
            try cg.writePresenceIdent(field.name, writer);
            try writer.writeAll(" and self.");
            try cg.writeQuotedIdent(field.name, writer);
            try writer.writeAll(".len != 0 and payload.len != 0) {\n");
            try cg.indent(writer, depth + 1);
            try writer.writeAll("const merged = try owned_allocator.alloc(u8, self.");
            try cg.writeQuotedIdent(field.name, writer);
            try writer.writeAll(".len + payload.len);\n");
            try cg.indent(writer, depth + 1);
            try writer.writeAll("@memcpy(merged[0..self.");
            try cg.writeQuotedIdent(field.name, writer);
            try writer.writeAll(".len], self.");
            try cg.writeQuotedIdent(field.name, writer);
            try writer.writeAll(");\n");
            try cg.indent(writer, depth + 1);
            try writer.writeAll("@memcpy(merged[self.");
            try cg.writeQuotedIdent(field.name, writer);
            try writer.writeAll(".len..], payload);\n");
            try cg.indent(writer, depth + 1);
            try writer.writeAll("self.");
            try cg.writeQuotedIdent(field.name, writer);
            try writer.writeAll(" = merged;\n");
            try cg.indent(writer, depth);
            try writer.writeAll("} else {\n");
            try cg.indent(writer, depth + 1);
            try writer.writeAll("self.");
            try cg.writeQuotedIdent(field.name, writer);
            try writer.writeAll(" = payload;\n");
            try cg.indent(writer, depth);
            try writer.writeAll("}\n");
            if (cg.hasPresence(ctx.file, field.*)) {
                try cg.indent(writer, depth);
                try writer.writeAll("self.");
                try cg.writePresenceIdent(field.name, writer);
                try writer.writeAll(" = true;\n");
            }
        }
    }
}

pub fn writeTextParseMapField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    const map_type = switch (field.kind) {
        .map => |map_type| map_type,
        else => return,
    };
    if (!textMapValueSupported(ctx, map_type.value.*)) return;
    try cg.indent(writer, depth);
    try writer.writeAll("if (");
    try writeTextBlockCondition(field, "line", writer);
    try writer.writeAll(") {\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("var entry = ");
    try cg.writeQuotedIdentWithSuffix(field.name, "Entry", writer);
    try writer.writeAll("{};\n");
    if (cg.typedMapMessageValueWithContext(ctx, field)) |_| {
        try cg.indent(writer, depth + 1);
        try writer.writeAll("errdefer entry.value.deinit(allocator);\n");
    }
    const can_skip_entry = textMapEntryCanSkip(map_type);
    if (can_skip_entry) {
        try cg.indent(writer, depth + 1);
        try writer.writeAll("var skip_entry = false;\n");
    }
    try cg.indent(writer, depth + 1);
    try writer.writeAll("while (lines.next()) |raw_entry_line| {\n");
    try cg.indent(writer, depth + 2);
    try writer.writeAll("const entry_line = @This().textCleanLine(raw_entry_line, text_has_comments);\n");
    try cg.indent(writer, depth + 2);
    try writer.writeAll("if (entry_line.len == 0) continue;\n");
    try cg.indent(writer, depth + 2);
    try writer.writeAll("if (std.mem.eql(u8, entry_line, \"}\") or std.mem.eql(u8, entry_line, \">\")) break;\n");
    try cg.indent(writer, depth + 2);
    try writer.writeAll("if (@This().textFieldValue(entry_line, \"key\")) |raw_key| { entry.key = ");
    try writeTextParseValueExpr(file, field, .{ .scalar = map_type.key }, "raw_key", writer);
    try writer.writeAll("; continue; }\n");
    if (map_type.value.* == .message and cg.codegenCanReferenceMessageWithContext(ctx, map_type.value.message)) {
        try cg.indent(writer, depth + 2);
        try writer.writeAll("if (@This().textBlockField(entry_line, \"value\")) {\n");
        try cg.indent(writer, depth + 3);
        try writer.writeAll("const block = try @This().textBlock(allocator, &lines, text_has_comments);\n");
        try cg.indent(writer, depth + 3);
        try writer.writeAll("defer allocator.free(block);\n");
        try cg.indent(writer, depth + 3);
        try writer.writeAll("var _pbz_nested = try ");
        try cg.writeMessageTypeReferenceWithContext(ctx, map_type.value.message, writer);
        try writer.writeAll(".parseTextWithOptions(allocator, block, .{ .ignore_unknown_fields = options.ignore_unknown_fields });\n");
        if (cg.typedMapMessageValueWithContext(ctx, field)) |_| {
            try cg.indent(writer, depth + 3);
            try writer.writeAll("{\n");
            try cg.indent(writer, depth + 4);
            try writer.writeAll("errdefer _pbz_nested.deinit(allocator);\n");
            try cg.indent(writer, depth + 4);
            try writer.writeAll("entry.value.deinit(allocator);\n");
            try cg.indent(writer, depth + 4);
            try writer.writeAll("entry.value = _pbz_nested;\n");
            try cg.indent(writer, depth + 3);
            try writer.writeAll("}\n");
        } else {
            try cg.indent(writer, depth + 3);
            try writer.writeAll("defer _pbz_nested.deinit(allocator);\n");
            try cg.indent(writer, depth + 3);
            try writer.writeAll("const owned_allocator = try self._pbzOwnedAllocator(allocator);\n");
            try cg.indent(writer, depth + 3);
            try writer.writeAll("entry.value = try _pbz_nested.encode(owned_allocator);\n");
        }
        try cg.indent(writer, depth + 3);
        try writer.writeAll("continue;\n");
        try cg.indent(writer, depth + 2);
        try writer.writeAll("}\n");
    }
    if (map_type.value.* == .scalar or map_type.value.* == .enumeration) {
        try cg.indent(writer, depth + 2);
        try writer.writeAll("if (@This().textFieldValue(entry_line, \"value\")) |raw_value| { ");
        if (map_type.value.* == .enumeration) {
            try writer.writeAll("entry.value = ");
            try writeTextParseEnumExpr(file, map_type.value.enumeration, "raw_value", writer);
            try writer.writeAll(" catch |err| { if (options.ignore_unknown_fields) { skip_entry = true; continue; } return err; }; continue; }\n");
        } else {
            try writer.writeAll("entry.value = ");
            try writeTextParseValueExpr(file, field, map_type.value.*, "raw_value", writer);
            try writer.writeAll("; continue; }\n");
        }
    }
    try cg.indent(writer, depth + 2);
    try writer.writeAll("return error.UnknownField;\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("}\n");
    if (can_skip_entry) {
        try cg.indent(writer, depth + 1);
        try writer.writeAll("if (skip_entry) continue;\n");
    }
    try cg.indent(writer, depth + 1);
    try writer.writeAll("try @This().");
    try cg.writeQuotedIdentWithPrefix(field.name, "appendOrReplaceMapEntry_", writer);
    try writer.writeAll("(allocator, &");
    try cg.writeQuotedIdentWithSuffix(field.name, "_list", writer);
    try writer.writeAll(", entry);\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("continue;\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn textMapEntryCanSkip(map_type: schema.MapType) bool {
    return map_type.value.* == .enumeration;
}

pub fn writeTextParseOneofField(ctx: *const CodegenContext, oneof: schema.OneofDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    switch (field.kind) {
        .scalar, .enumeration => {},
        .message, .group => |type_name| {
            if (!cg.codegenCanReferenceMessageWithContext(ctx, type_name)) return;
            try cg.indent(writer, depth);
            try writer.writeAll("if (");
            try writeTextBlockCondition(field, "line", writer);
            try writer.writeAll(") {\n");
            try writeTextParseMessagePayloadAssign(ctx, field, type_name, writer, depth + 1);
            try cg.indent(writer, depth + 1);
            try writer.writeAll("continue;\n");
            try cg.indent(writer, depth);
            try writer.writeAll("}\n");
            return;
        },
        else => return,
    }
    try cg.indent(writer, depth);
    try writer.writeAll("if (");
    try writeTextFieldValueLookup(field, "line", writer);
    try writer.writeAll(") |raw_value| { ");
    try cg.writeOneofDeinitCall(oneof.name, writer);
    try writer.writeAll(" self.");
    try cg.writeQuotedIdent(oneof.name, writer);
    try writer.writeAll(" = .{ .");
    try cg.writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = ");
    if (field.kind == .enumeration) {
        try writeTextParseEnumExpr(file, field.kind.enumeration, "raw_value", writer);
        try writer.writeAll(" catch |err| { if (options.ignore_unknown_fields) { continue; } return err; }");
    } else {
        try writeTextParseValueExpr(file, field, field.kind, "raw_value", writer);
    }
    try writer.writeAll(" }; continue; }\n");
}

pub fn writeTextFieldValueLookup(field: *const schema.FieldDescriptor, line_expr: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("@This().textFieldValue(");
    try writer.writeAll(line_expr);
    try writer.writeAll(", ");
    try cg.writeZigStringLiteral(field.name, writer);
    try writer.writeAll(")");
    try writeTextAlternateValueLookups(field, line_expr, writer);
}

pub fn writeTextAlternateValueLookups(field: *const schema.FieldDescriptor, line_expr: []const u8, writer: *std.Io.Writer) Error!void {
    if (field.json_name) |json_name| {
        if (!std.mem.eql(u8, json_name, field.name)) {
            try writer.writeAll(" orelse @This().textFieldValue(");
            try writer.writeAll(line_expr);
            try writer.writeAll(", ");
            try cg.writeZigStringLiteral(json_name, writer);
            try writer.writeAll(")");
        }
    } else if (std.mem.indexOfScalar(u8, field.name, '_') != null) {
        try writer.writeAll(" orelse @This().textFieldValue(");
        try writer.writeAll(line_expr);
        try writer.writeAll(", ");
        try cg.writeZigLowerCamelStringLiteral(field.name, writer);
        try writer.writeAll(")");
    }
}

pub fn writeTextBlockCondition(field: *const schema.FieldDescriptor, line_expr: []const u8, writer: *std.Io.Writer) Error!void {
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

pub fn writeTextBlockNameCondition(name: []const u8, line_expr: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("@This().textBlockField(");
    try writer.writeAll(line_expr);
    try writer.writeAll(", ");
    try cg.writeZigStringLiteral(name, writer);
    try writer.writeAll(")");
}

pub fn writeTextLowerCamelBlockNameCondition(name: []const u8, line_expr: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("@This().textBlockField(");
    try writer.writeAll(line_expr);
    try writer.writeAll(", ");
    try cg.writeZigLowerCamelStringLiteral(name, writer);
    try writer.writeAll(")");
}

pub fn writeExtensionTextValueLookup(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, line_expr: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("@This().textFieldValue(");
    try writer.writeAll(line_expr);
    try writer.writeAll(", ");
    try writeExtensionTextNameLiteral(file, field, true, writer);
    try writer.writeAll(")");
    if (extensionHasLeafAlias(file, field)) {
        try writer.writeAll(" orelse @This().textFieldValue(");
        try writer.writeAll(line_expr);
        try writer.writeAll(", ");
        try writeExtensionTextNameLiteral(file, field, false, writer);
        try writer.writeAll(")");
    }
}

pub fn writeExtensionTextBlockCondition(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, line_expr: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("@This().textBlockField(");
    try writer.writeAll(line_expr);
    try writer.writeAll(", ");
    try writeExtensionTextNameLiteral(file, field, true, writer);
    try writer.writeAll(")");
    if (extensionHasLeafAlias(file, field)) {
        try writer.writeAll(" or @This().textBlockField(");
        try writer.writeAll(line_expr);
        try writer.writeAll(", ");
        try writeExtensionTextNameLiteral(file, field, false, writer);
        try writer.writeAll(")");
    }
}

pub fn extensionHasLeafAlias(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor) bool {
    const full_name = schema.extensionFullName(field);
    if (file.package.len != 0) return true;
    return std.mem.indexOfScalar(u8, full_name, '.') != null or std.mem.startsWith(u8, full_name, ".");
}

pub fn writeExtensionTextNameLiteral(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, qualified: bool, writer: *std.Io.Writer) Error!void {
    try writer.writeByte('"');
    try writer.writeByte('[');
    const full_name = schema.extensionFullName(field);
    if (qualified) {
        if (std.mem.startsWith(u8, full_name, ".")) {
            try cg.writeEscapedStringContents(full_name[1..], writer);
        } else if (std.mem.indexOfScalar(u8, full_name, '.') != null or file.package.len == 0) {
            try cg.writeEscapedStringContents(full_name, writer);
        } else {
            try cg.writeEscapedStringContents(file.package, writer);
            try writer.writeByte('.');
            try cg.writeEscapedStringContents(full_name, writer);
        }
    } else {
        try cg.writeEscapedStringContents(cg.leafTypeName(full_name), writer);
    }
    try writer.writeByte(']');
    try writer.writeByte('"');
}

pub fn writeTextParseValueExpr(file: *const schema.FileDescriptor, field: ?*const schema.FieldDescriptor, kind: schema.FieldKind, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    switch (kind) {
        .scalar => |scalar| switch (scalar) {
            .double => try writer.print("try @This().textFloat(f64, {s})", .{value_expr}),
            .float => try writer.print("try @This().textFloat(f32, {s})", .{value_expr}),
            .int32, .sint32, .sfixed32 => try writer.print("try @This().textInt(i32, {s})", .{value_expr}),
            .int64, .sint64, .sfixed64 => try writer.print("try @This().textInt(i64, {s})", .{value_expr}),
            .uint32, .fixed32 => try writer.print("try @This().textInt(u32, {s})", .{value_expr}),
            .uint64, .fixed64 => try writer.print("try @This().textInt(u64, {s})", .{value_expr}),
            .bool => try writer.print("try @This().textBool({s})", .{value_expr}),
            .string => {
                if (cg.fieldUtf8ValidationOptional(file, field) == .verify) {
                    try writer.print("blk: {{ const decoded = try @This().textUnquote(try self._pbzOwnedAllocator(allocator), {s}); if (!pbz.validateUtf8(decoded)) return error.InvalidUtf8; break :blk decoded; }}", .{value_expr});
                } else {
                    try writer.print("try @This().textUnquote(try self._pbzOwnedAllocator(allocator), {s})", .{value_expr});
                }
            },
            .bytes => try writer.print("try @This().textUnquote(try self._pbzOwnedAllocator(allocator), {s})", .{value_expr}),
        },
        .enumeration => |name| {
            try writer.print("try @This().textEnum({s}, ", .{value_expr});
            try cg.enum_emit.writeEnumNameArray(file, name, writer);
            try writer.writeAll(", ");
            try cg.enum_emit.writeEnumNumberArray(file, name, writer);
            try writer.writeAll(", ");
            try writer.writeAll(if (cg.enum_emit.enumIsClosed(file, name)) "true" else "false");
            try writer.writeAll(")");
        },
        else => try writer.writeAll("@compileError(\"unsupported TextFormat parse field kind\")"),
    }
}

pub fn writeTextParseEnumExpr(file: *const schema.FileDescriptor, enum_name: []const u8, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.print("@This().textEnum({s}, ", .{value_expr});
    try cg.enum_emit.writeEnumNameArray(file, enum_name, writer);
    try writer.writeAll(", ");
    try cg.enum_emit.writeEnumNumberArray(file, enum_name, writer);
    try writer.writeAll(", ");
    try writer.writeAll(if (cg.enum_emit.enumIsClosed(file, enum_name)) "true" else "false");
    try writer.writeAll(")");
}

pub fn writeTextMethods(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try cg.indent(writer, depth);
    try writer.writeAll("pub const TextFormatOptions = struct { enum_as_name: bool = true, print_unknown_fields: bool = false };\n\n");

    try cg.indent(writer, depth);
    try writer.writeAll("pub fn formatTextAlloc(self: @This(), allocator: std.mem.Allocator) ![]u8 {\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("return try self.formatTextAllocWithOptions(allocator, .{});\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n\n");

    try cg.indent(writer, depth);
    try writer.writeAll("pub fn formatTextAllocWithOptions(self: @This(), allocator: std.mem.Allocator, options: @This().TextFormatOptions) ![]u8 {\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("var out: std.Io.Writer.Allocating = .init(allocator);\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("errdefer out.deinit();\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("try self.formatTextWithOptions(allocator, &out.writer, options);\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("return try out.toOwnedSlice();\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n\n");

    try cg.indent(writer, depth);
    try writer.writeAll("pub fn formatText(self: @This(), writer: *std.Io.Writer) !void {\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("try self.formatTextWithOptions(std.heap.page_allocator, writer, .{});\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n\n");

    try cg.indent(writer, depth);
    try writer.writeAll("pub fn formatTextWithAllocator(self: @This(), allocator: std.mem.Allocator, writer: *std.Io.Writer) !void {\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("try self.formatTextWithOptions(allocator, writer, .{});\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n\n");

    try cg.indent(writer, depth);
    try writer.writeAll("pub fn formatTextWithOptions(self: @This(), allocator: std.mem.Allocator, writer: *std.Io.Writer, options: @This().TextFormatOptions) anyerror!void {\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("_ = &allocator;\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("_ = &options;\n");
    for (message.fields.items) |*field| {
        if (field.oneof_name == null) try writeTextField(ctx, field, writer, depth + 1);
    }
    for (message.oneofs.items) |oneof| {
        if (oneofHasTextField(ctx, message, oneof.name)) try writeTextOneof(ctx, message, oneof, writer, depth + 1);
    }
    try writeTextUnknownFields(ctx, message, writer, depth + 1);
    try cg.indent(writer, depth);
    try writer.writeAll("}\n");

    try writer.writeAll("\n");
    try writeTextParseMethods(ctx, message, writer, depth);
}

pub fn messageTextUsesAllocator(ctx: *const CodegenContext, message: *const schema.MessageDescriptor) bool {
    const file = ctx.file;
    for (message.fields.items) |field| {
        if (field.kind == .message or field.kind == .group) return true;
        if (field.kind == .map and textMapValueUsesAllocator(ctx, field.kind.map.value.*)) return true;
    }
    if (messageHasTextMessageExtension(file, message)) return true;
    return false;
}

pub fn messageTextUsesOptions(ctx: *const CodegenContext, message: *const schema.MessageDescriptor) bool {
    for (message.fields.items) |field| {
        if (field.oneof_name == null and textFieldUsesOptions(ctx, field)) return true;
    }
    for (message.oneofs.items) |oneof| {
        for (message.fields.items) |field| {
            if (field.oneof_name) |name| {
                if (std.mem.eql(u8, name, oneof.name) and textFieldUsesOptions(ctx, field)) return true;
            }
        }
    }
    return messageHasTextMessageExtension(ctx.file, message);
}

pub fn textFieldUsesOptions(ctx: *const CodegenContext, field: schema.FieldDescriptor) bool {
    return switch (field.kind) {
        .enumeration => true,
        .message, .group => |name| cg.codegenCanReferenceMessageWithContext(ctx, name),
        .map => |map_type| textMapValueUsesOptions(ctx, map_type.value.*),
        else => false,
    };
}

pub fn textMapValueUsesOptions(ctx: *const CodegenContext, kind: schema.FieldKind) bool {
    return switch (kind) {
        .enumeration => true,
        .message, .group => |name| cg.codegenCanReferenceMessageWithContext(ctx, name),
        else => false,
    };
}

pub fn messageHasTextMessageExtension(file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor) bool {
    for (file.extensions.items) |*field| {
        if (cg.extensionAppliesToMessage(file, message, field) and extensionTextUsesAllocator(file, field)) return true;
    }
    for (file.messages.items) |*scope| {
        if (messageScopeHasTextMessageExtension(file, message, scope)) return true;
    }
    return false;
}

pub fn messageScopeHasTextMessageExtension(file: *const schema.FileDescriptor, target: *const schema.MessageDescriptor, scope: *const schema.MessageDescriptor) bool {
    for (scope.extensions.items) |*field| {
        if (cg.extensionAppliesToMessage(file, target, field) and extensionTextUsesAllocator(file, field)) return true;
    }
    for (scope.messages.items) |*_pbz_nested| {
        if (messageScopeHasTextMessageExtension(file, target, _pbz_nested)) return true;
    }
    return false;
}

pub fn extensionTextUsesAllocator(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor) bool {
    return switch (field.kind) {
        .message, .group => |name| cg.codegenCanReferenceMessage(file, name),
        else => false,
    };
}

pub fn textMapValueUsesAllocator(ctx: *const CodegenContext, kind: schema.FieldKind) bool {
    return switch (kind) {
        .message, .group => |name| cg.codegenCanReferenceMessageWithContext(ctx, name),
        else => false,
    };
}

pub fn textFieldSupported(ctx: *const CodegenContext, field: schema.FieldDescriptor) bool {
    return switch (field.kind) {
        .scalar, .enumeration => true,
        .message, .group => |name| cg.codegenCanReferenceMessageWithContext(ctx, name),
        .map => |map_type| textMapValueSupported(ctx, map_type.value.*),
    };
}

pub fn textMapValueSupported(ctx: *const CodegenContext, kind: schema.FieldKind) bool {
    return switch (kind) {
        .scalar, .enumeration => true,
        .message => |name| cg.codegenCanReferenceMessageWithContext(ctx, name),
        else => false,
    };
}

pub fn oneofHasTextField(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, oneof_name: []const u8) bool {
    for (message.fields.items) |field| {
        if (field.oneof_name) |name| {
            if (std.mem.eql(u8, name, oneof_name) and textFieldSupported(ctx, field)) return true;
        }
    }
    return false;
}

pub fn writeTextField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    switch (field.kind) {
        .scalar => |scalar| try writeTextScalarField(file, field, scalar, writer, depth),
        .enumeration => try writeTextEnumField(file, field, writer, depth),
        .message, .group => |name| try writeTextMessageField(ctx, field, name, writer, depth),
        .map => try writeTextMapField(ctx, field, writer, depth),
    }
}

pub fn writeTextScalarField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.cardinality == .repeated) {
        try cg.indent(writer, depth);
        try writer.writeAll("for (self.");
        try cg.writeQuotedIdent(field.name, writer);
        try writer.writeAll(") |value| { ");
        try writeTextFieldPrefix(field, writer);
        try writeTextUtf8Check(file, field, scalar, "value", writer);
        try writeTextScalarValue(scalar, "value", writer);
        try writer.writeAll("; try writer.writeByte('\\n'); }\n");
    } else {
        try cg.indent(writer, depth);
        if (cg.hasPresence(file, field.*)) {
            try writer.writeAll("if (self.");
            try cg.writePresenceIdent(field.name, writer);
            try writer.writeAll(") { ");
        } else {
            try cg.writeScalarSkipCondition("self.", field.name, scalar, writer);
            try writer.writeAll("{ ");
        }
        try writeTextFieldPrefix(field, writer);
        try writer.writeAll("const value = self.");
        try cg.writeQuotedIdent(field.name, writer);
        try writer.writeAll("; ");
        try writeTextUtf8Check(file, field, scalar, "value", writer);
        try writeTextScalarValue(scalar, "value", writer);
        try writer.writeAll("; try writer.writeByte('\\n'); }\n");
    }
}

pub fn writeTextEnumField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const enum_name = switch (field.kind) {
        .enumeration => |name| name,
        else => return,
    };
    if (field.cardinality == .repeated) {
        try cg.indent(writer, depth);
        try writer.writeAll("for (self.");
        try cg.writeQuotedIdent(field.name, writer);
        try writer.writeAll(") |value| { ");
        try writeTextFieldPrefix(field, writer);
        try writeTextEnumValue(file, enum_name, "value", writer);
        try writer.writeAll("; try writer.writeByte('\\n'); }\n");
    } else {
        try cg.indent(writer, depth);
        if (cg.hasPresence(file, field.*)) {
            try writer.writeAll("if (self.");
            try cg.writePresenceIdent(field.name, writer);
            try writer.writeAll(") { ");
        } else {
            try writer.writeAll("if (self.");
            try cg.writeQuotedIdent(field.name, writer);
            try writer.writeAll(" != 0) { ");
        }
        try writeTextFieldPrefix(field, writer);
        try writer.writeAll("const value = self.");
        try cg.writeQuotedIdent(field.name, writer);
        try writer.writeAll("; ");
        try writeTextEnumValue(file, enum_name, "value", writer);
        try writer.writeAll("; try writer.writeByte('\\n'); }\n");
    }
}

pub fn writeTextMessageField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, type_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    if (!cg.codegenCanReferenceMessageWithContext(ctx, type_name)) return;
    if (field.cardinality == .repeated) {
        try cg.indent(writer, depth);
        if (cg.typedRepeatedMessageFieldWithContext(ctx, field)) |_| {
            try writer.writeAll("for (self.");
            try cg.writeQuotedIdent(field.name, writer);
            try writer.writeAll(") |_pbz_nested| {\n");
            try cg.indent(writer, depth + 1);
            try writer.writeAll("try writer.writeAll(\"");
            try cg.writeEscapedStringContents(field.name, writer);
            try writer.writeAll(" {\\n\");\n");
            try cg.indent(writer, depth + 1);
            try writer.writeAll("try _pbz_nested.formatTextWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name });\n");
            try cg.indent(writer, depth + 1);
            try writer.writeAll("try writer.writeAll(\"}\\n\");\n");
        } else {
            try writer.writeAll("for (self.");
            try cg.writeQuotedIdent(field.name, writer);
            try writer.writeAll(") |payload| {\n");
            try writeTextMessagePayload(ctx, field.name, type_name, "payload", writer, depth + 1);
        }
        try cg.indent(writer, depth);
        try writer.writeAll("}\n");
    } else {
        try cg.indent(writer, depth);
        if (cg.typedSingularMessageFieldWithContext(ctx, field)) |_| {
            try writer.writeAll("if (self.");
            try cg.writeQuotedIdent(field.name, writer);
            try writer.writeAll(") |_pbz_nested| {\n");
            try cg.indent(writer, depth + 1);
            try writer.writeAll("try writer.writeAll(\"");
            try cg.writeEscapedStringContents(field.name, writer);
            try writer.writeAll(" {\\n\");\n");
            try cg.indent(writer, depth + 1);
            try writer.writeAll("try _pbz_nested.formatTextWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name });\n");
            try cg.indent(writer, depth + 1);
            try writer.writeAll("try writer.writeAll(\"}\\n\");\n");
            try cg.indent(writer, depth);
            try writer.writeAll("}\n");
            return;
        }
        try writer.writeAll("if (self.");
        try cg.writeQuotedIdent(field.name, writer);
        try writer.writeAll(".len != 0) {\n");
        try writeTextMessagePayload(ctx, field.name, type_name, "self.", writer, depth + 1);
        try cg.indent(writer, depth);
        try writer.writeAll("}\n");
    }
}

pub fn writeTextMessagePayload(ctx: *const CodegenContext, field_name: []const u8, type_name: []const u8, payload_expr: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    try cg.indent(writer, depth);
    try writer.writeAll("try writer.writeAll(\"");
    try cg.writeEscapedStringContents(field_name, writer);
    try writer.writeAll(" {\\n\");\n");
    try cg.indent(writer, depth);
    try writer.writeAll("var _pbz_nested = try ");
    try cg.writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    try writer.writeAll(".decode(allocator, ");
    try writer.writeAll(payload_expr);
    if (std.mem.eql(u8, payload_expr, "self.")) try cg.writeQuotedIdent(field_name, writer);
    try writer.writeAll(");\n");
    try cg.indent(writer, depth);
    try writer.writeAll("defer _pbz_nested.deinit(allocator);\n");
    try cg.indent(writer, depth);
    try writer.writeAll("try _pbz_nested.formatTextWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name });\n");
    try cg.indent(writer, depth);
    try writer.writeAll("try writer.writeAll(\"}\\n\");\n");
}

pub fn writeTextMapField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const map_type = switch (field.kind) {
        .map => |map_type| map_type,
        else => return,
    };
    if (!textMapValueSupported(ctx, map_type.value.*)) return;
    try cg.indent(writer, depth);
    try writer.writeAll("{ var map_it = self.");
    try cg.writeQuotedIdent(field.name, writer);
    try writer.writeAll(".iterator(); while (map_it.next()) |map_entry| {\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("const entry = ");
    try cg.writeQuotedIdentWithSuffix(field.name, "Entry", writer);
    try writer.writeAll("{ .key = map_entry.key_ptr.*, .value = map_entry.value_ptr.* };\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("try writer.writeAll(\"");
    try cg.writeEscapedStringContents(field.name, writer);
    try writer.writeAll(" {\\n\");\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("try writer.writeAll(\"key: \"); ");
    try writeTextUtf8Check(ctx.file, field, map_type.key, "entry.key", writer);
    try writeTextScalarValue(map_type.key, "entry.key", writer);
    try writer.writeAll("; try writer.writeByte('\\n');\n");
    try cg.indent(writer, depth + 1);
    if (map_type.value.* == .message and cg.codegenCanReferenceMessageWithContext(ctx, map_type.value.message)) {
        try writer.writeAll("try writer.writeAll(\"value {\\n\");\n");
        if (cg.typedMapMessageValueWithContext(ctx, field)) |_| {
            try cg.indent(writer, depth + 1);
            try writer.writeAll("try entry.value.formatTextWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name });\n");
        } else {
            try cg.indent(writer, depth + 1);
            try writer.writeAll("var _pbz_nested = try ");
            try cg.writeMessageTypeReferenceWithContext(ctx, map_type.value.message, writer);
            try writer.writeAll(".decode(allocator, entry.value);\n");
            try cg.indent(writer, depth + 1);
            try writer.writeAll("defer _pbz_nested.deinit(allocator);\n");
            try cg.indent(writer, depth + 1);
            try writer.writeAll("try _pbz_nested.formatTextWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name });\n");
        }
        try cg.indent(writer, depth + 1);
        try writer.writeAll("try writer.writeAll(\"}\\n\");\n");
    } else {
        try writer.writeAll("try writer.writeAll(\"value: \"); ");
        if (map_type.value.* == .scalar) try writeTextUtf8Check(ctx.file, field, map_type.value.scalar, "entry.value", writer);
        try writeTextMapValue(ctx, map_type.value.*, "entry.value", writer);
        try writer.writeAll("; try writer.writeByte('\\n');\n");
    }
    try cg.indent(writer, depth + 1);
    try writer.writeAll("try writer.writeAll(\"}\\n\");\n");
    try cg.indent(writer, depth);
    try writer.writeAll("} }\n");
}

pub fn writeTextOneof(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, oneof: schema.OneofDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    try cg.indent(writer, depth);
    try writer.writeAll("switch (self.");
    try cg.writeQuotedIdent(oneof.name, writer);
    try writer.writeAll(") {\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll(".none => {},\n");
    for (message.fields.items) |*field| {
        if (field.oneof_name) |name| {
            if (!std.mem.eql(u8, name, oneof.name) or !textFieldSupported(ctx, field.*)) continue;
            try cg.indent(writer, depth + 1);
            try writer.writeAll(".");
            try cg.writeQuotedIdent(field.name, writer);
            try writer.writeAll(" => |value| {\n");
            switch (field.kind) {
                .scalar => |scalar| {
                    try cg.indent(writer, depth + 2);
                    try writeTextFieldPrefix(field, writer);
                    try writeTextScalarValue(scalar, "value", writer);
                    try writer.writeAll("; try writer.writeByte('\\n');\n");
                },
                .enumeration => {
                    const enum_name = field.kind.enumeration;
                    try cg.indent(writer, depth + 2);
                    try writeTextFieldPrefix(field, writer);
                    try writeTextEnumValue(file, enum_name, "value", writer);
                    try writer.writeAll("; try writer.writeByte('\\n');\n");
                },
                .message, .group => |type_name| {
                    if (cg.typedOneofMessageFieldWithContext(ctx, field)) |_| {
                        try cg.indent(writer, depth + 2);
                        try writer.writeAll("try writer.writeAll(\"");
                        try cg.writeEscapedStringContents(field.name, writer);
                        try writer.writeAll(" {\\n\");\n");
                        try cg.indent(writer, depth + 2);
                        try writer.writeAll("try value.formatTextWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name });\n");
                        try cg.indent(writer, depth + 2);
                        try writer.writeAll("try writer.writeAll(\"}\\n\");\n");
                    } else {
                        try writeTextMessagePayload(ctx, field.name, type_name, "value", writer, depth + 2);
                    }
                },
                else => {},
            }
            try cg.indent(writer, depth + 1);
            try writer.writeAll("},\n");
        }
    }
    try cg.indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeTextUnknownFields(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try cg.indent(writer, depth);
    try writer.writeAll("for (self._unknown_fields) |raw| {\n");
    try writeTextUnknownExtensionFields(ctx, message, writer, depth + 1);
    try cg.indent(writer, depth + 1);
    try writer.writeAll("if (options.print_unknown_fields) try @This().textWriteUnknownRaw(raw, writer);\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeTextUnknownExtensionFields(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    for (file.extensions.items) |*field| {
        if (cg.extensionAppliesToMessage(file, message, field)) try writeTextUnknownExtensionField(ctx, field, writer, depth);
    }
    for (file.messages.items) |*scope| try writeTextUnknownMessageExtensions(ctx, message, scope, writer, depth);
}

pub fn writeTextUnknownMessageExtensions(ctx: *const CodegenContext, target: *const schema.MessageDescriptor, scope: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    for (scope.extensions.items) |*field| {
        if (cg.extensionAppliesToMessage(file, target, field)) try writeTextUnknownExtensionField(ctx, field, writer, depth);
    }
    for (scope.messages.items) |*nested| try writeTextUnknownMessageExtensions(ctx, target, nested, writer, depth);
}

pub fn writeTextUnknownExtensionField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    switch (field.kind) {
        .scalar, .enumeration => {},
        .message, .group => |type_name| {
            if (!cg.codegenCanReferenceMessageWithContext(ctx, type_name)) return;
            return try writeTextUnknownMessageExtensionField(ctx, field, type_name, writer, depth);
        },
        else => return,
    }
    try cg.indent(writer, depth);
    try writer.writeAll("if (");
    try cg.writeExtensionHelperReference(field, writer);
    try writer.writeAll(".decodeRaw(raw) catch null) |value| {\n");
    try cg.indent(writer, depth + 2);
    try writeTextExtensionFieldPrefix(file, field, writer);
    switch (field.kind) {
        .scalar => |scalar| {
            try writeTextUtf8Check(file, field, scalar, "value", writer);
            try writeTextScalarValue(scalar, "value", writer);
        },
        .enumeration => |name| try writeTextEnumValue(file, name, "value", writer),
        else => unreachable,
    }
    try writer.writeAll("; try writer.writeByte('\\n');\n");
    try cg.indent(writer, depth + 2);
    try writer.writeAll("continue;\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n");
    if (field.resolvedPacked(file)) {
        try cg.indent(writer, depth);
        try writer.writeAll("if (");
        try cg.writeExtensionHelperReference(field, writer);
        try writer.writeAll(".decodePackedRaw(allocator, raw) catch null) |values| {\n");
        try cg.indent(writer, depth + 1);
        try writer.writeAll("defer allocator.free(values);\n");
        try cg.indent(writer, depth + 1);
        try writer.writeAll("for (values) |value| {\n");
        try cg.indent(writer, depth + 2);
        try writeTextExtensionFieldPrefix(file, field, writer);
        switch (field.kind) {
            .scalar => |scalar| {
                try writeTextUtf8Check(file, field, scalar, "value", writer);
                try writeTextScalarValue(scalar, "value", writer);
            },
            .enumeration => |name| try writeTextEnumValue(file, name, "value", writer),
            else => unreachable,
        }
        try writer.writeAll("; try writer.writeByte('\\n');\n");
        try cg.indent(writer, depth + 1);
        try writer.writeAll("}\n");
        try cg.indent(writer, depth + 1);
        try writer.writeAll("continue;\n");
        try cg.indent(writer, depth);
        try writer.writeAll("}\n");
    }
}

pub fn writeTextUnknownMessageExtensionField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, type_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    try cg.indent(writer, depth);
    try writer.writeAll("if (");
    try cg.writeExtensionHelperReference(field, writer);
    try writer.writeAll(".decodeRaw(raw) catch null) |payload| {\n");
    try cg.indent(writer, depth + 2);
    try writeTextExtensionBlockPrefix(file, field, writer);
    try cg.indent(writer, depth + 2);
    try writer.writeAll("var _pbz_nested = try ");
    try cg.writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    try writer.writeAll(".decode(allocator, payload);\n");
    try cg.indent(writer, depth + 2);
    try writer.writeAll("defer _pbz_nested.deinit(allocator);\n");
    try cg.indent(writer, depth + 2);
    try writer.writeAll("try _pbz_nested.formatTextWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name });\n");
    try cg.indent(writer, depth + 2);
    try writer.writeAll("try writer.writeAll(\"}\\n\");\n");
    try cg.indent(writer, depth + 2);
    try writer.writeAll("continue;\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeTextFieldPrefix(field: *const schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("try writer.writeAll(\"");
    try cg.writeEscapedStringContents(field.name, writer);
    try writer.writeAll(": \"); ");
}

pub fn writeTextExtensionFieldPrefix(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("try writer.writeAll(\"[");
    try writeExtensionTextNameContents(file, field, true, writer);
    try writer.writeAll("]: \"); ");
}

pub fn writeTextExtensionBlockPrefix(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("try writer.writeAll(\"[");
    try writeExtensionTextNameContents(file, field, true, writer);
    try writer.writeAll("] {\\n\");\n");
}

pub fn writeExtensionTextNameContents(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, qualified: bool, writer: *std.Io.Writer) Error!void {
    const full_name = schema.extensionFullName(field);
    if (qualified) {
        if (std.mem.startsWith(u8, full_name, ".")) {
            try cg.writeEscapedStringContents(full_name[1..], writer);
        } else if (std.mem.indexOfScalar(u8, full_name, '.') != null or file.package.len == 0) {
            try cg.writeEscapedStringContents(full_name, writer);
        } else {
            try cg.writeEscapedStringContents(file.package, writer);
            try writer.writeByte('.');
            try cg.writeEscapedStringContents(full_name, writer);
        }
    } else {
        try cg.writeEscapedStringContents(cg.leafTypeName(full_name), writer);
    }
}

pub fn writeTextUtf8Check(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, scalar: schema.ScalarType, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    if (scalar == .string and cg.fieldUtf8Validation(file, field) == .verify) {
        try writer.print("if (!pbz.validateUtf8({s})) return error.InvalidUtf8; ", .{value_expr});
    }
}

pub fn writeTextScalarValue(scalar: schema.ScalarType, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .string, .bytes => try writer.print("try @This().textWriteQuotedBytes({s}, writer)", .{value_expr}),
        .bool => try writer.print("try writer.writeAll(if ({s}) \"true\" else \"false\")", .{value_expr}),
        else => try writer.print("try writer.print(\"{{d}}\", .{{{s}}})", .{value_expr}),
    }
}

pub fn writeTextEnumValue(file: *const schema.FileDescriptor, enum_name: []const u8, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.print("try @This().textWriteEnum(writer, {s}", .{value_expr});
    try writer.writeAll(", ");
    try cg.enum_emit.writeEnumNameArray(file, enum_name, writer);
    try writer.writeAll(", ");
    try cg.enum_emit.writeEnumNumberArray(file, enum_name, writer);
    try writer.writeAll(", options.enum_as_name");
    try writer.writeAll(")");
}

pub fn writeTextMapValue(ctx: *const CodegenContext, kind: schema.FieldKind, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    const file = ctx.file;
    switch (kind) {
        .scalar => |scalar| try writeTextScalarValue(scalar, value_expr, writer),
        .enumeration => |name| try writeTextEnumValue(file, name, value_expr, writer),
        .message => |name| if (cg.codegenCanReferenceMessageWithContext(ctx, name)) {
            try writer.writeAll("var _pbz_nested = try ");
            try cg.writeMessageTypeReferenceWithContext(ctx, name, writer);
            try writer.writeAll(".decode(allocator, ");
            try writer.writeAll(value_expr);
            try writer.writeAll("); defer _pbz_nested.deinit(allocator); try _pbz_nested.formatTextWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name })");
        } else try writer.writeAll("@compileError(\"unsupported map text value\")"),
        else => try writer.writeAll("@compileError(\"unsupported map text value\")"),
    }
}
