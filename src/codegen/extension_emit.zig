const schema = @import("../schema.zig");
const std = @import("std");
const cg = @import("../codegen.zig");
const CodegenContext = cg.CodegenContext;
const Error = cg.Error;
const codegenCanReferenceMessageWithContext = cg.codegenCanReferenceMessageWithContext;
const extensionAppliesToMessage = cg.extensionAppliesToMessage;
const indent = cg.indent;
const leafTypeName = cg.leafTypeName;
const resolveMessageReference = cg.resolveMessageReference;
const writeMessageTypeReferenceWithContext = cg.writeMessageTypeReferenceWithContext;
const writeQuotedIdent = cg.writeQuotedIdent;
const writeQuotedIdentWithPrefix = cg.writeQuotedIdentWithPrefix;
const writeZigStringLiteral = cg.writeZigStringLiteral;
const canReferenceEnumWithContext = cg.emit_helpers.canReferenceEnumWithContext;
const canReferenceMessageWithContext = cg.emit_helpers.canReferenceMessageWithContext;
const codegenCanReferenceEnumWithContext = cg.emit_helpers.codegenCanReferenceEnumWithContext;
const fieldType = cg.emit_helpers.fieldType;
const scalarZigType = cg.emit_helpers.scalarZigType;
const writeEntryReadExpr = cg.emit_helpers.writeEntryReadExpr;
const writeEnumTypeReferenceOrVoid = cg.emit_helpers.writeEnumTypeReferenceOrVoid;
const writeEnumTypeReferenceWithContext = cg.emit_helpers.writeEnumTypeReferenceWithContext;
const writeFieldKindDefault = cg.emit_helpers.writeFieldKindDefault;
const writeKindWriteCall = cg.emit_helpers.writeKindWriteCall;
const writeMessage = cg.emit_helpers.writeMessage;
const writeOptionValueTextLiteral = cg.emit_helpers.writeOptionValueTextLiteral;
const writePackedKindPayload = cg.emit_helpers.writePackedKindPayload;
const writeQualifiedMessageTypeReference = cg.emit_helpers.writeQualifiedMessageTypeReference;

pub fn writeMessageExtensionAccessors(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    var fields: std.ArrayList(*const schema.FieldDescriptor) = .empty;
    defer fields.deinit(ctx.allocator);
    for (file.extensions.items) |*field| {
        if (extensionAppliesToMessage(file, message, field)) try fields.append(ctx.allocator, field);
    }
    for (file.messages.items) |*scope| try collectScopedMessageExtensionFields(ctx, message, scope, &fields);
    if (fields.items.len == 0) {
        try indent(writer, depth);
        try writer.writeAll("// no same-file extension accessors\n");
        return;
    }
    const suffixes = try uniqueExtensionSuffixes(ctx.allocator, fields.items);
    defer {
        for (suffixes) |suffix| ctx.allocator.free(suffix);
        ctx.allocator.free(suffixes);
    }
    for (fields.items, suffixes) |field, suffix| try writeMessageExtensionAccessor(ctx, field, suffix, writer, depth);
}

pub fn collectScopedMessageExtensionFields(ctx: *const CodegenContext, target: *const schema.MessageDescriptor, scope: *const schema.MessageDescriptor, fields: *std.ArrayList(*const schema.FieldDescriptor)) Error!void {
    const file = ctx.file;
    for (scope.extensions.items) |*field| {
        if (extensionAppliesToMessage(file, target, field)) try fields.append(ctx.allocator, field);
    }
    for (scope.messages.items) |*nested| try collectScopedMessageExtensionFields(ctx, target, nested, fields);
}

pub fn uniqueExtensionSuffixes(allocator: std.mem.Allocator, fields: []const *const schema.FieldDescriptor) Error![][]const u8 {
    const suffixes = try allocator.alloc([]const u8, fields.len);
    errdefer allocator.free(suffixes);
    for (fields, 0..) |_, index| {
        suffixes[index] = try uniqueExtensionSuffix(allocator, fields, index);
    }
    return suffixes;
}

pub fn uniqueExtensionSuffix(allocator: std.mem.Allocator, fields: []const *const schema.FieldDescriptor, index: usize) Error![]u8 {
    var components: usize = 1;
    while (components <= 16) : (components += 1) {
        const candidate = try suffixFromComponents(allocator, schema.extensionFullName(fields[index]), components);
        var collision = false;
        for (fields, 0..) |other, other_index| {
            if (other_index == index) continue;
            const other_candidate = try suffixFromComponents(allocator, schema.extensionFullName(other), components);
            defer allocator.free(other_candidate);
            if (std.mem.eql(u8, candidate, other_candidate)) {
                collision = true;
                break;
            }
        }
        if (!collision) return candidate;
        allocator.free(candidate);
    }
    return suffixFromComponents(allocator, schema.extensionFullName(fields[index]), 16);
}

pub fn suffixFromComponents(allocator: std.mem.Allocator, full_name: []const u8, components: usize) Error![]u8 {
    const trimmed = if (std.mem.startsWith(u8, full_name, ".")) full_name[1..] else full_name;
    var starts: [32]usize = undefined;
    var count: usize = 1;
    starts[0] = 0;
    for (trimmed, 0..) |c, index| {
        if (c == '.' and count < starts.len) {
            starts[count] = index + 1;
            count += 1;
        }
    }
    const take = @min(components, count);
    const start = starts[count - take];
    const out = try allocator.alloc(u8, trimmed.len - start);
    for (trimmed[start..], out) |c, *d| d.* = if (c == '.') '_' else c;
    return out;
}

pub fn writeMessageExtensionAccessor(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, helper_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedIdentWithPrefix(helper_name, "hasExtension_", writer);
    try writer.writeAll("(self: @This()) !bool {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try ");
    try writeExtensionHelperReference(field, writer);
    try writer.writeAll(".hasInUnknown(self);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedIdentWithPrefix(helper_name, "countExtension_", writer);
    try writer.writeAll("(self: @This()) !usize {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try ");
    try writeExtensionHelperReference(field, writer);
    try writer.writeAll(".countInUnknown(self);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedIdentWithPrefix(helper_name, "getExtension_", writer);
    try writer.writeAll("(self: @This(), allocator: std.mem.Allocator) !");
    if (field.cardinality == .repeated) {
        try writer.writeAll("[]");
        try writer.writeAll(extensionSingleZigType(field.kind));
    } else {
        try writer.writeAll("?");
        try writer.writeAll(extensionSingleZigType(field.kind));
    }
    try writer.writeAll(" {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try ");
    try writeExtensionHelperReference(field, writer);
    if (field.cardinality == .repeated) {
        try writer.writeAll(".decodeAllFromUnknown(self, allocator);\n");
    } else {
        try writer.writeAll(".decodeFirstFromUnknown(self, allocator);\n");
    }
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    if (field.cardinality != .repeated and (field.kind == .scalar or field.kind == .enumeration)) {
        try indent(writer, depth);
        try writer.writeAll("pub fn ");
        try writeQuotedIdentWithPrefix(helper_name, "getExtensionOrDefault_", writer);
        try writer.writeAll("(self: @This(), allocator: std.mem.Allocator) !");
        try writer.writeAll(extensionSingleZigType(field.kind));
        try writer.writeAll(" {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return (try self.");
        try writeQuotedIdentWithPrefix(helper_name, "getExtension_", writer);
        try writer.writeAll("(allocator)) orelse ");
        try writeExtensionHelperReference(field, writer);
        try writer.writeAll(".default_value_zig");
        try writer.writeAll(";\n");
        try indent(writer, depth);
        try writer.writeAll("}\n\n");
    }

    if (field.kind == .enumeration and codegenCanReferenceEnumWithContext(ctx, field.kind.enumeration)) {
        try writeMessageEnumExtensionAccessor(ctx, field, helper_name, writer, depth);
    }

    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedIdentWithPrefix(helper_name, if (field.cardinality == .repeated) "appendExtension_" else "setExtension_", writer);
    try writer.writeAll("(self: *@This(), allocator: std.mem.Allocator, ");
    if (field.cardinality == .repeated) {
        try writer.writeAll("values: ");
        try writer.writeAll(fieldType(field.*));
    } else {
        try writer.writeAll("value: ");
        try writer.writeAll(extensionSingleZigType(field.kind));
    }
    try writer.writeAll(") !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try ");
    try writeExtensionHelperReference(field, writer);
    if (field.cardinality == .repeated) {
        try writer.writeAll(".appendAllToUnknown(self, allocator, values);\n");
    } else {
        try writer.writeAll(".replaceInUnknown(self, allocator, value);\n");
    }
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        try writer.writeAll("pub fn ");
        try writeQuotedIdentWithPrefix(helper_name, "addExtension_", writer);
        try writer.writeAll("(self: *@This(), allocator: std.mem.Allocator, value: ");
        try writer.writeAll(extensionSingleZigType(field.kind));
        try writer.writeAll(") !void {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try ");
        try writeExtensionHelperReference(field, writer);
        try writer.writeAll(".appendToUnknown(self, allocator, value);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n\n");

        try indent(writer, depth);
        try writer.writeAll("pub fn ");
        try writeQuotedIdentWithPrefix(helper_name, "replaceExtension_", writer);
        try writer.writeAll("(self: *@This(), allocator: std.mem.Allocator, values: ");
        try writer.writeAll(fieldType(field.*));
        try writer.writeAll(") !void {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try ");
        try writeExtensionHelperReference(field, writer);
        try writer.writeAll(".replaceAllInUnknown(self, allocator, values);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n\n");
    }

    if ((field.kind == .message or field.kind == .group) and codegenCanReferenceMessageWithContext(ctx, switch (field.kind) {
        .message => |name| name,
        .group => |name| name,
        else => unreachable,
    })) {
        try writeMessageExtensionTypedAccessor(ctx, field, helper_name, writer, depth);
    }

    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedIdentWithPrefix(helper_name, "clearExtension_", writer);
    try writer.writeAll("(self: *@This(), allocator: std.mem.Allocator) !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try ");
    try writeExtensionHelperReference(field, writer);
    try writer.writeAll(".clearFromUnknown(self, allocator);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");
}

pub fn writeMessageEnumExtensionAccessor(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, helper_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        try writer.writeAll("pub fn ");
        try writeQuotedIdentWithPrefix(helper_name, "getEnumExtensions_", writer);
        try writer.writeAll("(self: @This(), allocator: std.mem.Allocator) ![]");
        try writeEnumTypeReferenceWithContext(ctx, field.kind.enumeration, writer);
        try writer.writeAll(" {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const raw = try self.");
        try writeQuotedIdentWithPrefix(helper_name, "getExtension_", writer);
        try writer.writeAll("(allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("defer allocator.free(raw);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const out = try allocator.alloc(");
        try writeEnumTypeReferenceWithContext(ctx, field.kind.enumeration, writer);
        try writer.writeAll(", raw.len);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("errdefer allocator.free(out);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("for (raw, 0..) |value, i| out[i] = ");
        try writeEnumTypeReferenceWithContext(ctx, field.kind.enumeration, writer);
        try writer.writeAll(".fromInt(value) orelse return error.InvalidEnumValue;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return out;\n");
        try indent(writer, depth);
        try writer.writeAll("}\n\n");

        try indent(writer, depth);
        try writer.writeAll("pub fn ");
        try writeQuotedIdentWithPrefix(helper_name, "addEnumExtension_", writer);
        try writer.writeAll("(self: *@This(), allocator: std.mem.Allocator, value: ");
        try writeEnumTypeReferenceWithContext(ctx, field.kind.enumeration, writer);
        try writer.writeAll(") !void {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try self.");
        try writeQuotedIdentWithPrefix(helper_name, "addExtension_", writer);
        try writer.writeAll("(allocator, value.toInt());\n");
        try indent(writer, depth);
        try writer.writeAll("}\n\n");

        try indent(writer, depth);
        try writer.writeAll("pub fn ");
        try writeQuotedIdentWithPrefix(helper_name, "appendEnumExtensions_", writer);
        try writer.writeAll("(self: *@This(), allocator: std.mem.Allocator, values: []const ");
        try writeEnumTypeReferenceWithContext(ctx, field.kind.enumeration, writer);
        try writer.writeAll(") !void {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const raw = try allocator.alloc(i32, values.len);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("defer allocator.free(raw);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("for (values, 0..) |value, i| raw[i] = value.toInt();\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try self.");
        try writeQuotedIdentWithPrefix(helper_name, "appendExtension_", writer);
        try writer.writeAll("(allocator, raw);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n\n");

        try indent(writer, depth);
        try writer.writeAll("pub fn ");
        try writeQuotedIdentWithPrefix(helper_name, "replaceEnumExtensions_", writer);
        try writer.writeAll("(self: *@This(), allocator: std.mem.Allocator, values: []const ");
        try writeEnumTypeReferenceWithContext(ctx, field.kind.enumeration, writer);
        try writer.writeAll(") !void {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const raw = try allocator.alloc(i32, values.len);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("defer allocator.free(raw);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("for (values, 0..) |value, i| raw[i] = value.toInt();\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try self.");
        try writeQuotedIdentWithPrefix(helper_name, "replaceExtension_", writer);
        try writer.writeAll("(allocator, raw);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n\n");
        return;
    }

    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedIdentWithPrefix(helper_name, "getEnumExtension_", writer);
    try writer.writeAll("(self: @This(), allocator: std.mem.Allocator) !?");
    try writeEnumTypeReferenceWithContext(ctx, field.kind.enumeration, writer);
    try writer.writeAll(" {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const raw = (try self.");
    try writeQuotedIdentWithPrefix(helper_name, "getExtension_", writer);
    try writer.writeAll("(allocator)) orelse return null;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return ");
    try writeEnumTypeReferenceWithContext(ctx, field.kind.enumeration, writer);
    try writer.writeAll(".fromInt(raw);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedIdentWithPrefix(helper_name, "getEnumOrDefaultExtension_", writer);
    try writer.writeAll("(self: @This(), allocator: std.mem.Allocator) !");
    try writeEnumTypeReferenceWithContext(ctx, field.kind.enumeration, writer);
    try writer.writeAll(" {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return (try self.");
    try writeQuotedIdentWithPrefix(helper_name, "getEnumExtension_", writer);
    try writer.writeAll("(allocator)) orelse ");
    try writeEnumTypeReferenceWithContext(ctx, field.kind.enumeration, writer);
    try writer.writeAll(".fromInt(");
    try writeExtensionHelperReference(field, writer);
    try writer.writeAll(".default_value_zig) orelse unreachable;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedIdentWithPrefix(helper_name, "setEnumExtension_", writer);
    try writer.writeAll("(self: *@This(), allocator: std.mem.Allocator, value: ");
    try writeEnumTypeReferenceWithContext(ctx, field.kind.enumeration, writer);
    try writer.writeAll(") !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.");
    try writeQuotedIdentWithPrefix(helper_name, "setExtension_", writer);
    try writer.writeAll("(allocator, value.toInt());\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");
}

pub fn writeMessageExtensionTypedAccessor(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, helper_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    const type_name = switch (field.kind) {
        .message => |name| name,
        .group => |name| name,
        else => return,
    };
    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        try writer.writeAll("pub fn ");
        try writeQuotedIdentWithPrefix(helper_name, "addExtensionMessage_", writer);
        try writer.writeAll("(self: *@This(), allocator: std.mem.Allocator, value: ");
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
        try writer.writeAll(") !void {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const payload = try value.encode(allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("defer allocator.free(payload);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try ");
        try writeExtensionHelperReference(field, writer);
        try writer.writeAll(".appendToUnknown(self, allocator, payload);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n\n");

        try indent(writer, depth);
        try writer.writeAll("pub fn ");
        try writeQuotedIdentWithPrefix(helper_name, "appendExtensionMessages_", writer);
        try writer.writeAll("(self: *@This(), allocator: std.mem.Allocator, values: []const ");
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
        try writer.writeAll(") !void {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("for (values) |value| try self.");
        try writeQuotedIdentWithPrefix(helper_name, "addExtensionMessage_", writer);
        try writer.writeAll("(allocator, value);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n\n");

        try indent(writer, depth);
        try writer.writeAll("pub fn ");
        try writeQuotedIdentWithPrefix(helper_name, "replaceExtensionMessages_", writer);
        try writer.writeAll("(self: *@This(), allocator: std.mem.Allocator, values: []const ");
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
        try writer.writeAll(") !void {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try ");
        try writeExtensionHelperReference(field, writer);
        try writer.writeAll(".clearFromUnknown(self, allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try self.");
        try writeQuotedIdentWithPrefix(helper_name, "appendExtensionMessages_", writer);
        try writer.writeAll("(allocator, values);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n\n");

        try indent(writer, depth);
        try writer.writeAll("pub fn ");
        try writeQuotedIdentWithPrefix(helper_name, "getExtensionMessages_", writer);
        try writer.writeAll("(self: @This(), allocator: std.mem.Allocator) ![]");
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
        try writer.writeAll(" {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const payloads = try ");
        try writeExtensionHelperReference(field, writer);
        try writer.writeAll(".decodeAllFromUnknown(self, allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("defer allocator.free(payloads);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("var list: std.ArrayList(");
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
        try writer.writeAll(") = .empty;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("errdefer { for (list.items) |*item| item.deinit(allocator); list.deinit(allocator); }\n");
        try indent(writer, depth + 1);
        try writer.writeAll("for (payloads) |payload| try list.append(allocator, try ");
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
        try writer.writeAll(".decode(allocator, payload));\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return try list.toOwnedSlice(allocator);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n\n");
    } else {
        try indent(writer, depth);
        try writer.writeAll("pub fn ");
        try writeQuotedIdentWithPrefix(helper_name, "setExtensionMessage_", writer);
        try writer.writeAll("(self: *@This(), allocator: std.mem.Allocator, value: ");
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
        try writer.writeAll(") !void {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const payload = try value.encode(allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("defer allocator.free(payload);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try ");
        try writeExtensionHelperReference(field, writer);
        try writer.writeAll(".replaceInUnknown(self, allocator, payload);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n\n");

        try indent(writer, depth);
        try writer.writeAll("pub fn ");
        try writeQuotedIdentWithPrefix(helper_name, "getExtensionMessage_", writer);
        try writer.writeAll("(self: @This(), allocator: std.mem.Allocator) !");
        try writer.writeAll("?");
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
        try writer.writeAll(" {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const payload = (try ");
        try writeExtensionHelperReference(field, writer);
        try writer.writeAll(".decodeFirstFromUnknown(self, allocator)) orelse return null;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return try ");
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
        try writer.writeAll(".decode(allocator, payload);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n\n");
    }
}

pub fn writeExtensionMetadata(ctx: *const CodegenContext, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    const count = countExtensions(file);
    if (count == 0) return;
    try indent(writer, depth);
    try writer.writeAll("pub const extensions = struct {\n");
    for (file.extensions.items) |*field| try writeExtensionDecl(ctx, field, writer, depth + 1);
    for (file.messages.items) |*message| try writeMessageExtensions(ctx, message, writer, depth + 1);
    try indent(writer, depth);
    try writer.writeAll("};\n\n");
}

pub fn writeMessageExtensions(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    for (message.extensions.items) |*field| try writeExtensionDecl(ctx, field, writer, depth);
    for (message.messages.items) |*nested| try writeMessageExtensions(ctx, nested, writer, depth);
}

pub fn writeExtensionDecl(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    try indent(writer, depth);
    try writer.writeAll("pub const ");
    try writeExtensionHelperIdent(field, writer);
    try writer.writeAll(" = struct {\n");
    try indent(writer, depth + 1);
    try writer.print("pub const number = {d};\n", .{field.number});
    try indent(writer, depth + 1);
    try writer.writeAll("pub const extendee = ");
    try writeZigStringLiteral(field.extendee orelse "", writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const extendee_has_type_ref = ");
    try writer.writeAll(if (extensionExtendeeHasTypeRef(ctx, field)) "true" else "false");
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const extendee_type_ref = ");
    try writeExtensionExtendeeTypeRef(ctx, field, writer);
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
    try writer.writeAll("pub const value_has_type_ref = ");
    try writer.writeAll(if (canReferenceMessageWithContext(ctx, field.kind)) "true" else "false");
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const value_type_ref = ");
    switch (field.kind) {
        .message, .group => |type_name| {
            if (codegenCanReferenceMessageWithContext(ctx, type_name)) {
                try writeQualifiedMessageTypeReference(ctx, type_name, writer);
            } else {
                try writer.writeAll("void");
            }
        },
        else => try writer.writeAll("void"),
    }
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const value_has_enum_ref = ");
    try writer.writeAll(if (canReferenceEnumWithContext(ctx, field.kind)) "true" else "false");
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const value_enum_ref = ");
    try writeEnumTypeReferenceOrVoid(ctx, field.kind, writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const zig_type = ");
    try writeZigStringLiteral(fieldType(field.*), writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const typed_zig_type = ");
    try writeExtensionTypedZigTypeLiteral(ctx, field, writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const has_default = ");
    try writer.writeAll(if (field.default_value != null) "true" else "false");
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const default_value = ");
    try writeOptionValueTextLiteral(field.default_value, writer);
    try writer.writeAll(";\n");
    if (field.kind == .scalar or field.kind == .enumeration) {
        try indent(writer, depth + 1);
        try writer.writeAll("pub const default_value_zig: ");
        try writer.writeAll(extensionSingleZigType(field.kind));
        try writer.writeAll(" = ");
        try writeFieldKindDefault(file, field.kind, field.default_value, writer);
        try writer.writeAll(";\n");
    }
    if (extensionExtendeeHasTypeRef(ctx, field)) try writeExtensionFacadeHelpers(ctx, field, writer, depth + 1);
    try writeExtensionWriteHelpers(ctx, field, writer, depth + 1);
    try writeExtensionDecodeHelpers(ctx, field, writer, depth + 1);
    try indent(writer, depth);
    try writer.writeAll("};\n");
}

pub fn extensionExtendeeHasTypeRef(ctx: *const CodegenContext, field: *const schema.FieldDescriptor) bool {
    return codegenCanReferenceMessageWithContext(ctx, field.extendee orelse return false);
}

pub fn writeExtensionTypedZigTypeLiteral(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    const type_name = switch (field.kind) {
        .message, .group => |name| name,
        else => return try writeZigStringLiteral(fieldType(field.*), writer),
    };
    if (!codegenCanReferenceMessageWithContext(ctx, type_name)) return try writeZigStringLiteral(fieldType(field.*), writer);
    var type_buf: std.Io.Writer.Allocating = .init(ctx.allocator);
    defer type_buf.deinit();
    if (field.cardinality == .repeated) try type_buf.writer.writeAll("[]const ");
    try writeQualifiedMessageTypeReference(ctx, type_name, &type_buf.writer);
    try writeZigStringLiteral(type_buf.written(), writer);
}

pub fn writeExtensionExtendeeTypeRef(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    const extendee = field.extendee orelse return try writer.writeAll("void");
    if (codegenCanReferenceMessageWithContext(ctx, extendee)) {
        try writeQualifiedMessageTypeReference(ctx, extendee, writer);
    } else {
        try writer.writeAll("void");
    }
}

pub fn writeExtensionFacadeHelpers(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn hasOn(message: ");
    try writeExtensionExtendeeTypeRef(ctx, field, writer);
    try writer.writeAll(") !bool {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try hasInUnknown(message);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn countOn(message: ");
    try writeExtensionExtendeeTypeRef(ctx, field, writer);
    try writer.writeAll(") !usize {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try countInUnknown(message);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn clearOn(message: *");
    try writeExtensionExtendeeTypeRef(ctx, field, writer);
    try writer.writeAll(", allocator: std.mem.Allocator) !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try clearFromUnknown(message, allocator);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn getOn(message: ");
    try writeExtensionExtendeeTypeRef(ctx, field, writer);
    try writer.writeAll(", allocator: std.mem.Allocator) !");
    if (field.cardinality == .repeated) {
        try writer.writeAll("[]");
        try writer.writeAll(extensionSingleZigType(field.kind));
    } else {
        try writer.writeByte('?');
        try writer.writeAll(extensionSingleZigType(field.kind));
    }
    try writer.writeAll(" {\n");
    try indent(writer, depth + 1);
    if (field.cardinality == .repeated) {
        try writer.writeAll("return try decodeAllFromUnknown(message, allocator);\n");
    } else {
        try writer.writeAll("return try decodeFirstFromUnknown(message, allocator);\n");
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");

    if (field.cardinality != .repeated and (field.kind == .scalar or field.kind == .enumeration)) {
        try indent(writer, depth);
        try writer.writeAll("pub fn getOrDefaultOn(message: ");
        try writeExtensionExtendeeTypeRef(ctx, field, writer);
        try writer.writeAll(", allocator: std.mem.Allocator) !");
        try writer.writeAll(extensionSingleZigType(field.kind));
        try writer.writeAll(" {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return (try getOn(message, allocator)) orelse default_value_zig;\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");
    }

    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        try writer.writeAll("pub fn addOn(message: *");
        try writeExtensionExtendeeTypeRef(ctx, field, writer);
        try writer.writeAll(", allocator: std.mem.Allocator, value: ");
        try writer.writeAll(extensionSingleZigType(field.kind));
        try writer.writeAll(") !void {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try appendToUnknown(message, allocator, value);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");

        try indent(writer, depth);
        try writer.writeAll("pub fn appendAllOn(message: *");
        try writeExtensionExtendeeTypeRef(ctx, field, writer);
        try writer.writeAll(", allocator: std.mem.Allocator, values: ");
        try writer.writeAll(fieldType(field.*));
        try writer.writeAll(") !void {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try appendAllToUnknown(message, allocator, values);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");

        try indent(writer, depth);
        try writer.writeAll("pub fn replaceAllOn(message: *");
        try writeExtensionExtendeeTypeRef(ctx, field, writer);
        try writer.writeAll(", allocator: std.mem.Allocator, values: ");
        try writer.writeAll(fieldType(field.*));
        try writer.writeAll(") !void {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try replaceAllInUnknown(message, allocator, values);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");
    } else {
        try indent(writer, depth);
        try writer.writeAll("pub fn setOn(message: *");
        try writeExtensionExtendeeTypeRef(ctx, field, writer);
        try writer.writeAll(", allocator: std.mem.Allocator, value: ");
        try writer.writeAll(extensionSingleZigType(field.kind));
        try writer.writeAll(") !void {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try replaceInUnknown(message, allocator, value);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");
    }

    if (field.kind == .enumeration and canReferenceEnumWithContext(ctx, field.kind)) {
        try writeExtensionEnumFacadeHelpers(ctx, field, writer, depth);
    }
    if ((field.kind == .message or field.kind == .group) and canReferenceMessageWithContext(ctx, field.kind)) {
        try writeExtensionMessageFacadeHelpers(ctx, field, writer, depth);
    }
}

pub fn writeExtensionEnumFacadeHelpers(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        try writer.writeAll("pub fn getEnumsOn(message: ");
        try writeExtensionExtendeeTypeRef(ctx, field, writer);
        try writer.writeAll(", allocator: std.mem.Allocator) ![]");
        try writeEnumTypeReferenceWithContext(ctx, field.kind.enumeration, writer);
        try writer.writeAll(" {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const _pbz_raw = try getOn(message, allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("defer allocator.free(_pbz_raw);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const _pbz_out = try allocator.alloc(");
        try writeEnumTypeReferenceWithContext(ctx, field.kind.enumeration, writer);
        try writer.writeAll(", _pbz_raw.len);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("errdefer allocator.free(_pbz_out);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("for (_pbz_raw, 0..) |_pbz_value, _pbz_i| _pbz_out[_pbz_i] = ");
        try writeEnumTypeReferenceWithContext(ctx, field.kind.enumeration, writer);
        try writer.writeAll(".fromInt(_pbz_value) orelse return error.InvalidEnumValue;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return _pbz_out;\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");

        try indent(writer, depth);
        try writer.writeAll("pub fn addEnumOn(message: *");
        try writeExtensionExtendeeTypeRef(ctx, field, writer);
        try writer.writeAll(", allocator: std.mem.Allocator, value: ");
        try writeEnumTypeReferenceWithContext(ctx, field.kind.enumeration, writer);
        try writer.writeAll(") !void {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try addOn(message, allocator, value.toInt());\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");

        try indent(writer, depth);
        try writer.writeAll("pub fn appendAllEnumsOn(message: *");
        try writeExtensionExtendeeTypeRef(ctx, field, writer);
        try writer.writeAll(", allocator: std.mem.Allocator, values: []const ");
        try writeEnumTypeReferenceWithContext(ctx, field.kind.enumeration, writer);
        try writer.writeAll(") !void {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const _pbz_raw = try allocator.alloc(i32, values.len);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("defer allocator.free(_pbz_raw);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("for (values, 0..) |_pbz_value, _pbz_i| _pbz_raw[_pbz_i] = _pbz_value.toInt();\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try appendAllOn(message, allocator, _pbz_raw);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");

        try indent(writer, depth);
        try writer.writeAll("pub fn replaceAllEnumsOn(message: *");
        try writeExtensionExtendeeTypeRef(ctx, field, writer);
        try writer.writeAll(", allocator: std.mem.Allocator, values: []const ");
        try writeEnumTypeReferenceWithContext(ctx, field.kind.enumeration, writer);
        try writer.writeAll(") !void {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const _pbz_raw = try allocator.alloc(i32, values.len);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("defer allocator.free(_pbz_raw);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("for (values, 0..) |_pbz_value, _pbz_i| _pbz_raw[_pbz_i] = _pbz_value.toInt();\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try replaceAllOn(message, allocator, _pbz_raw);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");
        return;
    }

    try indent(writer, depth);
    try writer.writeAll("pub fn getEnumOn(message: ");
    try writeExtensionExtendeeTypeRef(ctx, field, writer);
    try writer.writeAll(", allocator: std.mem.Allocator) !?");
    try writeEnumTypeReferenceWithContext(ctx, field.kind.enumeration, writer);
    try writer.writeAll(" {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const _pbz_raw = (try getOn(message, allocator)) orelse return null;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return ");
    try writeEnumTypeReferenceWithContext(ctx, field.kind.enumeration, writer);
    try writer.writeAll(".fromInt(_pbz_raw);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn getEnumOrDefaultOn(message: ");
    try writeExtensionExtendeeTypeRef(ctx, field, writer);
    try writer.writeAll(", allocator: std.mem.Allocator) !");
    try writeEnumTypeReferenceWithContext(ctx, field.kind.enumeration, writer);
    try writer.writeAll(" {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return (try getEnumOn(message, allocator)) orelse ");
    try writeEnumTypeReferenceWithContext(ctx, field.kind.enumeration, writer);
    try writer.writeAll(".fromInt(default_value_zig) orelse unreachable;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn setEnumOn(message: *");
    try writeExtensionExtendeeTypeRef(ctx, field, writer);
    try writer.writeAll(", allocator: std.mem.Allocator, value: ");
    try writeEnumTypeReferenceWithContext(ctx, field.kind.enumeration, writer);
    try writer.writeAll(") !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try setOn(message, allocator, value.toInt());\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeExtensionMessageFacadeHelpers(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const type_name = switch (field.kind) {
        .message => |name| name,
        .group => |name| name,
        else => return,
    };
    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        try writer.writeAll("pub fn addMessageOn(message: *");
        try writeExtensionExtendeeTypeRef(ctx, field, writer);
        try writer.writeAll(", allocator: std.mem.Allocator, value: ");
        try writeQualifiedMessageTypeReference(ctx, type_name, writer);
        try writer.writeAll(") !void {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const _pbz_payload = try value.encode(allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("defer allocator.free(_pbz_payload);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try appendToUnknown(message, allocator, _pbz_payload);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");

        try indent(writer, depth);
        try writer.writeAll("pub fn getMessagesOn(message: ");
        try writeExtensionExtendeeTypeRef(ctx, field, writer);
        try writer.writeAll(", allocator: std.mem.Allocator) ![]");
        try writeQualifiedMessageTypeReference(ctx, type_name, writer);
        try writer.writeAll(" {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const _pbz_payloads = try decodeAllFromUnknown(message, allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("defer allocator.free(_pbz_payloads);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("var _pbz_list: std.ArrayList(");
        try writeQualifiedMessageTypeReference(ctx, type_name, writer);
        try writer.writeAll(") = .empty;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("errdefer { for (_pbz_list.items) |*item| item.deinit(allocator); _pbz_list.deinit(allocator); }\n");
        try indent(writer, depth + 1);
        try writer.writeAll("for (_pbz_payloads) |_pbz_payload| try _pbz_list.append(allocator, try ");
        try writeQualifiedMessageTypeReference(ctx, type_name, writer);
        try writer.writeAll(".decode(allocator, _pbz_payload));\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return try _pbz_list.toOwnedSlice(allocator);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");
    } else {
        try indent(writer, depth);
        try writer.writeAll("pub fn setMessageOn(message: *");
        try writeExtensionExtendeeTypeRef(ctx, field, writer);
        try writer.writeAll(", allocator: std.mem.Allocator, value: ");
        try writeQualifiedMessageTypeReference(ctx, type_name, writer);
        try writer.writeAll(") !void {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const _pbz_payload = try value.encode(allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("defer allocator.free(_pbz_payload);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try replaceInUnknown(message, allocator, _pbz_payload);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");

        try indent(writer, depth);
        try writer.writeAll("pub fn getMessageOn(message: ");
        try writeExtensionExtendeeTypeRef(ctx, field, writer);
        try writer.writeAll(", allocator: std.mem.Allocator) !?");
        try writeQualifiedMessageTypeReference(ctx, type_name, writer);
        try writer.writeAll(" {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const _pbz_payload = (try decodeFirstFromUnknown(message, allocator)) orelse return null;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return try ");
        try writeQualifiedMessageTypeReference(ctx, type_name, writer);
        try writer.writeAll(".decode(allocator, _pbz_payload);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");
    }
}

pub fn writeExtensionWriteHelpers(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    try indent(writer, depth);
    try writer.writeAll("pub fn write(w: *pbz.Writer, value: ");
    try writer.writeAll(extensionSingleZigType(field.kind));
    try writer.writeAll(") !void {\n");
    if (extensionUsesMessageSet(ctx, field)) {
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
        if (field.kind == .group) {
            try writer.print("try w.writeTag({d}, .start_group);\n", .{field.number});
            try indent(writer, depth + 1);
            try writer.writeAll("try w.appendSlice(value);\n");
            try indent(writer, depth + 1);
            try writer.print("try w.writeTag({d}, .end_group);\n", .{field.number});
        } else {
            try writeKindWriteCall(field.number, field.kind, "value", "w", writer);
            try writer.writeAll(");\n");
        }
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn encodeRaw(allocator: std.mem.Allocator, value: ");
    try writer.writeAll(extensionSingleZigType(field.kind));
    try writer.writeAll(") ![]u8 {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var w = pbz.Writer.init(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer w.deinit();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try write(&w, value);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try w.toOwnedSlice();\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn appendToUnknown(message: anytype, allocator: std.mem.Allocator, value: ");
    try writer.writeAll(extensionSingleZigType(field.kind));
    try writer.writeAll(") !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const _pbz_raw = try encodeRaw(allocator, value);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("defer allocator.free(_pbz_raw);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try message.appendUnknownRaw(allocator, _pbz_raw);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn hasInUnknown(message: anytype) !bool {\n");
    try indent(writer, depth + 1);
    if (extensionUsesMessageSet(ctx, field)) {
        try writer.writeAll("for (message.unknownFields()) |_pbz_raw| { if ((try decodeRaw(_pbz_raw)) != null) return true; }\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return false;\n");
    } else {
        try writer.writeAll("return try message.hasUnknownFieldNumber(number);\n");
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn countInUnknown(message: anytype) !usize {\n");
    try indent(writer, depth + 1);
    if (extensionUsesMessageSet(ctx, field)) {
        try writer.writeAll("var _pbz_count: usize = 0;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("for (message.unknownFields()) |_pbz_raw| { if ((try decodeRaw(_pbz_raw)) != null) _pbz_count += 1; }\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return _pbz_count;\n");
    } else {
        try writer.writeAll("return try message.unknownFieldCountByNumber(number);\n");
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn clearFromUnknown(message: anytype, allocator: std.mem.Allocator) !void {\n");
    try indent(writer, depth + 1);
    if (extensionUsesMessageSet(ctx, field)) {
        try writer.writeAll("const _pbz_old = message.unknownFields();\n");
        try indent(writer, depth + 1);
        try writer.writeAll("if (_pbz_old.len == 0) return;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("var _pbz_keep: std.ArrayList([]const u8) = .empty;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("errdefer _pbz_keep.deinit(allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("for (_pbz_old) |_pbz_raw| { if ((try decodeRaw(_pbz_raw)) == null) try _pbz_keep.append(allocator, _pbz_raw) else allocator.free(_pbz_raw); }\n");
        try indent(writer, depth + 1);
        try writer.writeAll("if (_pbz_keep.items.len == 0) { _pbz_keep.deinit(allocator); message._unknown_fields = &.{}; } else message._unknown_fields = try _pbz_keep.toOwnedSlice(allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("allocator.free(_pbz_old);\n");
    } else {
        try writer.writeAll("try message.clearUnknownFieldsByNumber(allocator, number);\n");
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn replaceInUnknown(message: anytype, allocator: std.mem.Allocator, value: ");
    try writer.writeAll(extensionSingleZigType(field.kind));
    try writer.writeAll(") !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try clearFromUnknown(message, allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try appendToUnknown(message, allocator, value);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");

    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        try writer.writeAll("pub fn writeAll(w: *pbz.Writer, values: ");
        try writer.writeAll(fieldType(field.*));
        try writer.writeAll(") !void {\n");
        if (field.resolvedPacked(file)) {
            try indent(writer, depth + 1);
            try writer.writeAll("if (values.len == 0) return;\n");
            try indent(writer, depth + 1);
            try writer.writeAll("var packed_writer = pbz.Writer.init(w.allocator);\n");
            try indent(writer, depth + 1);
            try writer.writeAll("defer packed_writer.deinit();\n");
            try indent(writer, depth + 1);
            try writer.writeAll("for (values) |value| ");
            try writePackedKindPayload(field.kind, "value", writer);
            try writer.writeAll(";\n");
            try indent(writer, depth + 1);
            try writer.print("try w.writeBytes({d}, packed_writer.slice());\n", .{field.number});
        } else {
            try indent(writer, depth + 1);
            try writer.writeAll("for (values) |_pbz_value| try write(w, _pbz_value);\n");
        }
        try indent(writer, depth);
        try writer.writeAll("}\n");

        try indent(writer, depth);
        try writer.writeAll("pub fn encodeAllRaw(allocator: std.mem.Allocator, values: ");
        try writer.writeAll(fieldType(field.*));
        try writer.writeAll(") ![]u8 {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("var w = pbz.Writer.init(allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("errdefer w.deinit();\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try writeAll(&w, values);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return try w.toOwnedSlice();\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");

        try indent(writer, depth);
        try writer.writeAll("pub fn appendAllToUnknown(message: anytype, allocator: std.mem.Allocator, values: ");
        try writer.writeAll(fieldType(field.*));
        try writer.writeAll(") !void {\n");
        if (field.resolvedPacked(file)) {
            try indent(writer, depth + 1);
            try writer.writeAll("if (values.len == 0) return;\n");
            try indent(writer, depth + 1);
            try writer.writeAll("const _pbz_raw = try encodeAllRaw(allocator, values);\n");
            try indent(writer, depth + 1);
            try writer.writeAll("defer allocator.free(_pbz_raw);\n");
            try indent(writer, depth + 1);
            try writer.writeAll("try message.appendUnknownRaw(allocator, _pbz_raw);\n");
        } else {
            try indent(writer, depth + 1);
            try writer.writeAll("for (values) |_pbz_value| try appendToUnknown(message, allocator, _pbz_value);\n");
        }
        try indent(writer, depth);
        try writer.writeAll("}\n");

        try indent(writer, depth);
        try writer.writeAll("pub fn replaceAllInUnknown(message: anytype, allocator: std.mem.Allocator, values: ");
        try writer.writeAll(fieldType(field.*));
        try writer.writeAll(") !void {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try clearFromUnknown(message, allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try appendAllToUnknown(message, allocator, values);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");
    }
}

pub fn extensionUsesMessageSet(ctx: *const CodegenContext, field: *const schema.FieldDescriptor) bool {
    if (field.kind != .message) return false;
    const extendee = field.extendee orelse return false;
    const ref = resolveMessageReference(ctx, extendee) orelse return false;
    return ref.message.messageSetWireFormat();
}

pub fn writeExtensionDecodeHelpers(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    try indent(writer, depth);
    try writer.writeAll("pub fn decodeValue(r: *pbz.Reader) !");
    try writer.writeAll(extensionSingleZigType(field.kind));
    try writer.writeAll(" {\n");
    try indent(writer, depth + 1);
    if (field.kind == .group) {
        try writer.writeAll("return try r.readGroupBytes(number);\n");
    } else {
        try writer.writeAll("return ");
        try writeEntryReadExpr(field.kind, "r", writer);
        try writer.writeAll(";\n");
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn decodeRaw(raw: []const u8) !?");
    try writer.writeAll(extensionSingleZigType(field.kind));
    try writer.writeAll(" {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var r = pbz.Reader.init(raw);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const _pbz_tag = (try r.nextTag()) orelse return null;\n");
    if (extensionUsesMessageSet(ctx, field)) {
        try indent(writer, depth + 1);
        try writer.writeAll("if (_pbz_tag.number == 1 and _pbz_tag.wire_type == .start_group) { const _pbz_value = try decodeMessageSetItem(&r); if (!r.eof()) return error.InvalidWireType; return _pbz_value; }\n");
        try indent(writer, depth + 1);
        try writer.print("if (_pbz_tag.number == {d} and _pbz_tag.wire_type == .length_delimited) {{ const _pbz_value = try r.readBytes(); if (!r.eof()) return error.InvalidWireType; return _pbz_value; }}\n", .{field.number});
        try indent(writer, depth + 1);
        try writer.writeAll("return null;\n");
    } else {
        try indent(writer, depth + 1);
        try writer.print("if (_pbz_tag.number != number or _pbz_tag.wire_type != .{s}) return null;\n", .{@tagName(field.kind.wireType())});
        try indent(writer, depth + 1);
        try writer.writeAll("const _pbz_value = try decodeValue(&r);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("if (!r.eof()) return error.InvalidWireType;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return _pbz_value;\n");
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");

    if (field.resolvedPacked(file)) {
        try indent(writer, depth);
        try writer.writeAll("pub fn decodePackedRaw(allocator: std.mem.Allocator, raw: []const u8) !?[]");
        try writer.writeAll(extensionSingleZigType(field.kind));
        try writer.writeAll(" {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("var r = pbz.Reader.init(raw);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const _pbz_tag = (try r.nextTag()) orelse return null;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("if (_pbz_tag.number != number or _pbz_tag.wire_type != .length_delimited) return null;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("var packed_reader = pbz.Reader.init(try r.readBytes());\n");
        try indent(writer, depth + 1);
        try writer.writeAll("if (!r.eof()) return error.InvalidWireType;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("var _pbz_list: std.ArrayList(");
        try writer.writeAll(extensionSingleZigType(field.kind));
        try writer.writeAll(") = .empty;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("errdefer _pbz_list.deinit(allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("while (!packed_reader.eof()) try _pbz_list.append(allocator, ");
        try writeEntryReadExpr(field.kind, "packed_reader", writer);
        try writer.writeAll(");\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return try _pbz_list.toOwnedSlice(allocator);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");
    }

    try indent(writer, depth);
    try writer.writeAll("pub fn decodeAllRaw(allocator: std.mem.Allocator, raw_fields: []const []const u8) ![]");
    try writer.writeAll(extensionSingleZigType(field.kind));
    try writer.writeAll(" {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var _pbz_list: std.ArrayList(");
    try writer.writeAll(extensionSingleZigType(field.kind));
    try writer.writeAll(") = .empty;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer _pbz_list.deinit(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("for (raw_fields) |_pbz_raw| {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("if (try decodeRaw(_pbz_raw)) |_pbz_value| try _pbz_list.append(allocator, _pbz_value);\n");
    if (field.resolvedPacked(file)) {
        try indent(writer, depth + 2);
        try writer.writeAll("if (try decodePackedRaw(allocator, _pbz_raw)) |_pbz_values| { defer allocator.free(_pbz_values); try _pbz_list.appendSlice(allocator, _pbz_values); }\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try _pbz_list.toOwnedSlice(allocator);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn decodeFromUnknownFieldsAlloc(message: anytype, allocator: std.mem.Allocator) ![]");
    try writer.writeAll(extensionSingleZigType(field.kind));
    try writer.writeAll(" {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try decodeAllRaw(allocator, message.unknownFields());\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn decodeAllFromUnknown(message: anytype, allocator: std.mem.Allocator) ![]");
    try writer.writeAll(extensionSingleZigType(field.kind));
    try writer.writeAll(" {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try decodeFromUnknownFieldsAlloc(message, allocator);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn decodeFirstFromUnknown(message: anytype, allocator: std.mem.Allocator) !");
    try writer.writeAll("?");
    try writer.writeAll(extensionSingleZigType(field.kind));
    try writer.writeAll(" {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const _pbz_values = try decodeFromUnknownFieldsAlloc(message, allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("defer allocator.free(_pbz_values);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return if (_pbz_values.len == 0) null else _pbz_values[_pbz_values.len - 1];\n");
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

        try indent(writer, depth);
        try writer.writeAll("pub fn decodeAppendRaw(allocator: std.mem.Allocator, list: *std.ArrayList(");
        try writer.writeAll(extensionSingleZigType(field.kind));
        try writer.writeAll("), raw: []const u8) !void {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("if (try decodeRaw(raw)) |_pbz_value| try list.append(allocator, _pbz_value);\n");
        if (field.resolvedPacked(file)) {
            try indent(writer, depth + 1);
            try writer.writeAll("if (try decodePackedRaw(allocator, raw)) |_pbz_values| { defer allocator.free(_pbz_values); try list.appendSlice(allocator, _pbz_values); }\n");
        }
        try indent(writer, depth);
        try writer.writeAll("}\n");
    }
    if (extensionUsesMessageSet(ctx, field)) {
        try indent(writer, depth);
        try writer.writeAll("pub fn decodeMessageSetItem(r: *pbz.Reader) !?[]const u8 {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("var type_id: ?u32 = null;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("var _pbz_payload: ?[]const u8 = null;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("while (try r.nextTag()) |_pbz_tag| {\n");
        try indent(writer, depth + 2);
        try writer.writeAll("if (_pbz_tag.wire_type == .end_group) {\n");
        try indent(writer, depth + 3);
        try writer.writeAll("if (_pbz_tag.number != 1) return error.InvalidFieldNumber;\n");
        try indent(writer, depth + 3);
        try writer.print("return if (type_id != null and type_id.? == {d}) _pbz_payload else null;\n", .{field.number});
        try indent(writer, depth + 2);
        try writer.writeAll("}\n");
        try indent(writer, depth + 2);
        try writer.writeAll("switch (_pbz_tag.number) {\n");
        try indent(writer, depth + 3);
        try writer.writeAll("2 => { if (_pbz_tag.wire_type != .varint) return error.InvalidWireType; const raw_type_id = try r.readUInt32(); if (raw_type_id == 0 or raw_type_id > std.math.maxInt(pbz.FieldNumber)) return error.InvalidFieldNumber; type_id = raw_type_id; },\n");
        try indent(writer, depth + 3);
        try writer.writeAll("3 => { if (_pbz_tag.wire_type != .length_delimited) return error.InvalidWireType; _pbz_payload = try r.readBytes(); },\n");
        try indent(writer, depth + 3);
        try writer.writeAll("else => try r.skipValue(_pbz_tag),\n");
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

pub fn extensionSingleZigType(kind: schema.FieldKind) []const u8 {
    return switch (kind) {
        .scalar => |scalar| scalarZigType(scalar),
        .enumeration => "i32",
        .message, .group => "[]const u8",
        else => "void",
    };
}

pub fn extensionValueTypeName(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor) []const u8 {
    _ = file;
    return switch (field.kind) {
        .scalar => |scalar| @tagName(scalar),
        .message => |name| name,
        .enumeration => |name| name,
        .group => |name| name,
        .map => "map",
    };
}

pub fn countExtensions(file: *const schema.FileDescriptor) usize {
    var count: usize = file.extensions.items.len;
    for (file.messages.items) |*message| count += countMessageExtensions(message);
    return count;
}

pub fn countMessageExtensions(message: *const schema.MessageDescriptor) usize {
    var count: usize = message.extensions.items.len;
    for (message.messages.items) |*nested| count += countMessageExtensions(nested);
    return count;
}

pub fn extensionAccessorSuffix(name: []const u8) []const u8 {
    return leafTypeName(name);
}

pub fn writeExtensionHelperReference(field: *const schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("extensions.");
    try writeExtensionHelperIdent(field, writer);
}

pub fn writeExtensionHelperIdent(field: *const schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    try writeQuotedIdent(schema.extensionFullName(field), writer);
}
