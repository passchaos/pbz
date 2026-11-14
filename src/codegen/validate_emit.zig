const schema = @import("../schema.zig");
const std = @import("std");
const cg = @import("../codegen.zig");
const CodegenContext = cg.CodegenContext;
const Error = cg.Error;
const codegenCanReferenceMessageWithContext = cg.codegenCanReferenceMessageWithContext;
const extensionAppliesToMessage = cg.extensionAppliesToMessage;
const indent = cg.indent;
const isRequired = cg.isRequired;
const typedMapMessageValueWithContext = cg.typedMapMessageValueWithContext;
const typedOneofMessageFieldWithContext = cg.typedOneofMessageFieldWithContext;
const typedRepeatedMessageFieldWithContext = cg.typedRepeatedMessageFieldWithContext;
const typedSingularMessageFieldWithContext = cg.typedSingularMessageFieldWithContext;
const writeEscapedStringContents = cg.writeEscapedStringContents;
const writeExtensionHelperReference = cg.writeExtensionHelperReference;
const writeMessageTypeReferenceWithContext = cg.writeMessageTypeReferenceWithContext;
const writePresenceIdent = cg.writePresenceIdent;
const writeQuotedIdent = cg.writeQuotedIdent;
const writeZigStringLiteral = cg.writeZigStringLiteral;

pub fn writeMissingRequiredFieldName(message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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
        try writer.writeAll("_ = &self;\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("return null;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeMissingRequiredFieldPath(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn missingRequiredFieldPath(self: @This(), allocator: std.mem.Allocator) anyerror!?[]u8 {\n");
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
            if (try writeMissingRequiredPathField(ctx, field, writer, depth + 1)) uses_allocator = true;
        }
    }
    for (message.oneofs.items) |oneof| {
        if (oneofHasMessageField(message, oneof.name)) {
            uses_allocator = true;
            try writeMissingRequiredPathOneof(ctx, message, oneof, writer, depth + 1);
        }
    }
    if (try writeMissingRequiredPathExtensionPayloads(ctx, message, writer, depth + 1)) uses_allocator = true;
    if (!uses_allocator) {
        try indent(writer, depth + 1);
        try writer.writeAll("_ = &self; _ = &allocator;\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("return null;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeMissingRequiredPathExtensionPayloads(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!bool {
    const file = ctx.file;
    var wrote_any = false;
    for (file.extensions.items) |*field| {
        if (try writeMissingRequiredPathExtensionPayload(ctx, message, field, writer, depth)) wrote_any = true;
    }
    for (file.messages.items) |*scope| {
        if (try writeMissingRequiredPathScopedExtensionPayloads(ctx, message, scope, writer, depth)) wrote_any = true;
    }
    return wrote_any;
}

pub fn writeMissingRequiredPathScopedExtensionPayloads(ctx: *const CodegenContext, target: *const schema.MessageDescriptor, scope: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!bool {
    var wrote_any = false;
    for (scope.extensions.items) |*field| {
        if (try writeMissingRequiredPathExtensionPayload(ctx, target, field, writer, depth)) wrote_any = true;
    }
    for (scope.messages.items) |*nested| {
        if (try writeMissingRequiredPathScopedExtensionPayloads(ctx, target, nested, writer, depth)) wrote_any = true;
    }
    return wrote_any;
}

pub fn writeMissingRequiredPathExtensionPayload(ctx: *const CodegenContext, target: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!bool {
    const file = ctx.file;
    if (!extensionAppliesToMessage(file, target, field)) return false;
    const type_name = switch (field.kind) {
        .message => |name| name,
        .group => |name| name,
        else => return false,
    };
    if (!codegenCanReferenceMessageWithContext(ctx, type_name)) return false;

    try indent(writer, depth);
    try writer.writeAll("{\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const payloads = try ");
    try writeExtensionHelperReference(field, writer);
    try writer.writeAll(".decodeAllFromUnknown(self, allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("defer allocator.free(payloads);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("for (payloads) |payload| {\n");
    try writeMissingRequiredPathPayload(ctx, type_name, field.name, "payload", writer, depth + 2);
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
    return true;
}

pub fn writeMissingRequiredPathField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!bool {
    if (field.kind == .map) return try writeMissingRequiredPathMapField(ctx, field, writer, depth);
    const type_name = switch (field.kind) {
        .message => |name| name,
        .group => |name| name,
        else => return false,
    };
    if (!codegenCanReferenceMessageWithContext(ctx, type_name)) return false;
    if (field.oneof_name != null) return false;
    if (field.cardinality == .repeated) {
        if (typedRepeatedMessageFieldWithContext(ctx, field)) |_| {
            try indent(writer, depth);
            try writer.writeAll("for (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(") |_pbz_nested| {\n");
            try indent(writer, depth + 1);
            try writer.writeAll("if (try _pbz_nested.missingRequiredFieldPath(allocator)) |suffix| { defer allocator.free(suffix); return try std.fmt.allocPrint(allocator, \"");
            try writeEscapedStringContents(field.name, writer);
            try writer.writeAll(".{s}\", .{suffix}); }\n");
            try indent(writer, depth);
            try writer.writeAll("}\n");
        } else {
            try indent(writer, depth);
            try writer.writeAll("for (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(") |payload| {\n");
            try writeMissingRequiredPathPayload(ctx, type_name, field.name, "payload", writer, depth + 1);
            try indent(writer, depth);
            try writer.writeAll("}\n");
        }
    } else {
        if (typedSingularMessageFieldWithContext(ctx, field)) |_| {
            try indent(writer, depth);
            try writer.writeAll("if (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(") |_pbz_nested| {\n");
            try indent(writer, depth + 1);
            try writer.writeAll("if (try _pbz_nested.missingRequiredFieldPath(allocator)) |suffix| { defer allocator.free(suffix); return try std.fmt.allocPrint(allocator, \"");
            try writeEscapedStringContents(field.name, writer);
            try writer.writeAll(".{s}\", .{suffix}); }\n");
            try indent(writer, depth);
            try writer.writeAll("}\n");
            return true;
        }
        try indent(writer, depth);
        try writer.writeAll("if (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(".len != 0) {\n");
        try writeMissingRequiredPathPayload(ctx, type_name, field.name, "self.", writer, depth + 1);
        try indent(writer, depth);
        try writer.writeAll("}\n");
    }
    return true;
}

pub fn writeMissingRequiredPathMapField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!bool {
    const map_type = switch (field.kind) {
        .map => |map_type| map_type,
        else => return false,
    };
    const type_name = switch (map_type.value.*) {
        .message => |name| name,
        else => return false,
    };
    if (!codegenCanReferenceMessageWithContext(ctx, type_name)) return false;
    try indent(writer, depth);
    try writer.writeAll("{ var map_it = self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".iterator(); while (map_it.next()) |entry| {\n");
    if (typedMapMessageValueWithContext(ctx, field)) |_| {
        try indent(writer, depth + 1);
        try writer.writeAll("if (try entry.value_ptr.missingRequiredFieldPath(allocator)) |suffix| { defer allocator.free(suffix); return try std.fmt.allocPrint(allocator, \"");
        try writeEscapedStringContents(field.name, writer);
        try writer.writeAll(".{s}\", .{suffix}); }\n");
    } else {
        try writeMissingRequiredPathPayload(ctx, type_name, field.name, "entry.value_ptr.*", writer, depth + 1);
    }
    try indent(writer, depth);
    try writer.writeAll("} }\n");
    return true;
}

pub fn writeMissingRequiredPathOneof(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, oneof: schema.OneofDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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
            if (std.mem.eql(u8, name, oneof.name) and codegenCanReferenceMessageWithContext(ctx, type_name)) {
                try indent(writer, depth + 1);
                try writer.writeAll(".");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(" => |");
                if (typedOneofMessageFieldWithContext(ctx, field)) |_| {
                    try writer.writeAll("_pbz_nested| {\n");
                    try indent(writer, depth + 2);
                    try writer.writeAll("if (try _pbz_nested.missingRequiredFieldPath(allocator)) |suffix| { defer allocator.free(suffix); return try std.fmt.allocPrint(allocator, \"");
                    try writeEscapedStringContents(field.name, writer);
                    try writer.writeAll(".{s}\", .{suffix}); }\n");
                } else {
                    try writer.writeAll("payload| {\n");
                    try writeMissingRequiredPathPayload(ctx, type_name, field.name, "payload", writer, depth + 2);
                }
                try indent(writer, depth + 1);
                try writer.writeAll("},\n");
            }
        }
    }
    try indent(writer, depth + 1);
    try writer.writeAll("else => {},\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeMissingRequiredPathPayload(ctx: *const CodegenContext, type_name: []const u8, field_name: []const u8, payload_expr: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("var _pbz_nested = try ");
    try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    try writer.writeAll(".decode(allocator, ");
    try writer.writeAll(payload_expr);
    if (std.mem.eql(u8, payload_expr, "self.")) try writeQuotedIdent(field_name, writer);
    try writer.writeAll(");\n");
    try indent(writer, depth);
    try writer.writeAll("defer _pbz_nested.deinit(allocator);\n");
    try indent(writer, depth);
    try writer.writeAll("if (try _pbz_nested.missingRequiredFieldPath(allocator)) |suffix| {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("defer allocator.free(suffix);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try std.fmt.allocPrint(allocator, \"");
    try writeEscapedStringContents(field_name, writer);
    try writer.writeAll(".{s}\", .{suffix});\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeValidateRequired(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn validateRequired(self: @This()) !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (self.missingRequiredFieldName() != null) return error.MissingRequiredField;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try writer.writeAll("\n");
    try indent(writer, depth);
    try writer.writeAll("pub fn validateRequiredRecursive(self: @This(), allocator: std.mem.Allocator) anyerror!void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.validateRequired();\n");
    var uses_allocator = false;
    for (message.fields.items) |*field| {
        if (field.kind == .message or field.kind == .group or fieldHasMessageMapValue(field)) {
            uses_allocator = true;
            try writeValidateMessagePayloadField(ctx, field, writer, depth + 1);
        }
    }
    for (message.oneofs.items) |oneof| {
        if (oneofHasMessageField(message, oneof.name)) {
            uses_allocator = true;
            try writeValidateMessagePayloadOneof(ctx, message, oneof, writer, depth + 1);
        }
    }
    if (try writeValidateMessageExtensionPayloads(ctx, message, writer, depth + 1)) uses_allocator = true;
    if (!uses_allocator) {
        try indent(writer, depth + 1);
        try writer.writeAll("_ = &allocator;\n");
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeValidateMessageExtensionPayloads(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!bool {
    const file = ctx.file;
    var wrote_any = false;
    for (file.extensions.items) |*field| {
        if (try writeValidateMessageExtensionPayload(ctx, message, field, writer, depth)) wrote_any = true;
    }
    for (file.messages.items) |*scope| {
        if (try writeValidateScopedMessageExtensionPayloads(ctx, message, scope, writer, depth)) wrote_any = true;
    }
    return wrote_any;
}

pub fn writeValidateScopedMessageExtensionPayloads(ctx: *const CodegenContext, target: *const schema.MessageDescriptor, scope: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!bool {
    var wrote_any = false;
    for (scope.extensions.items) |*field| {
        if (try writeValidateMessageExtensionPayload(ctx, target, field, writer, depth)) wrote_any = true;
    }
    for (scope.messages.items) |*nested| {
        if (try writeValidateScopedMessageExtensionPayloads(ctx, target, nested, writer, depth)) wrote_any = true;
    }
    return wrote_any;
}

pub fn writeValidateMessageExtensionPayload(ctx: *const CodegenContext, target: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!bool {
    const file = ctx.file;
    if (!extensionAppliesToMessage(file, target, field)) return false;
    const type_name = switch (field.kind) {
        .message => |name| name,
        .group => |name| name,
        else => return false,
    };
    if (!codegenCanReferenceMessageWithContext(ctx, type_name)) return false;

    try indent(writer, depth);
    try writer.writeAll("{\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const payloads = try ");
    try writeExtensionHelperReference(field, writer);
    try writer.writeAll(".decodeAllFromUnknown(self, allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("defer allocator.free(payloads);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("for (payloads) |payload| {\n");
    try writeDecodeAndValidatePayload(ctx, type_name, "payload", writer, depth + 2);
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
    return true;
}

pub fn writeValidateMessagePayloadField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.kind == .map) return try writeValidateMapMessagePayloadField(ctx, field, writer, depth);
    const type_name = switch (field.kind) {
        .message => |name| name,
        .group => |name| name,
        else => return,
    };
    if (!codegenCanReferenceMessageWithContext(ctx, type_name)) return;
    if (field.oneof_name != null) return;
    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        try writer.writeAll("for (self.");
        try writeQuotedIdent(field.name, writer);
        if (typedRepeatedMessageFieldWithContext(ctx, field)) |_| {
            try writer.writeAll(") |_pbz_nested| try _pbz_nested.validateRequiredRecursive(allocator);\n");
        } else {
            try writer.writeAll(") |payload| {\n");
            try writeDecodeAndValidatePayload(ctx, type_name, "payload", writer, depth + 1);
            try indent(writer, depth);
            try writer.writeAll("}\n");
        }
    } else {
        if (typedSingularMessageFieldWithContext(ctx, field)) |_| {
            try indent(writer, depth);
            try writer.writeAll("if (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(") |_pbz_nested| try _pbz_nested.validateRequiredRecursive(allocator);\n");
            return;
        }
        try indent(writer, depth);
        try writer.writeAll("if (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(".len != 0) {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("var _pbz_nested = try ");
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
        try writer.writeAll(".decode(allocator, self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(");\n");
        try indent(writer, depth + 1);
        try writer.writeAll("defer _pbz_nested.deinit(allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try _pbz_nested.validateRequiredRecursive(allocator);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");
    }
}

pub fn writeValidateMapMessagePayloadField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const map_type = switch (field.kind) {
        .map => |map_type| map_type,
        else => return,
    };
    const type_name = switch (map_type.value.*) {
        .message => |name| name,
        else => return,
    };
    if (!codegenCanReferenceMessageWithContext(ctx, type_name)) return;
    try indent(writer, depth);
    try writer.writeAll("{ var map_it = self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".iterator(); while (map_it.next()) |entry| {\n");
    if (typedMapMessageValueWithContext(ctx, field)) |_| {
        try indent(writer, depth + 1);
        try writer.writeAll("try entry.value_ptr.validateRequiredRecursive(allocator);\n");
    } else {
        try writeDecodeAndValidatePayload(ctx, type_name, "entry.value_ptr.*", writer, depth + 1);
    }
    try indent(writer, depth);
    try writer.writeAll("} }\n");
}

pub fn fieldHasMessageMapValue(field: *const schema.FieldDescriptor) bool {
    const map_type = switch (field.kind) {
        .map => |map_type| map_type,
        else => return false,
    };
    return map_type.value.* == .message;
}

pub fn writeValidateMessagePayloadOneof(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, oneof: schema.OneofDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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
            if (std.mem.eql(u8, name, oneof.name) and codegenCanReferenceMessageWithContext(ctx, type_name)) {
                try indent(writer, depth + 1);
                try writer.writeAll(".");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(" => |");
                if (typedOneofMessageFieldWithContext(ctx, field)) |_| {
                    try writer.writeAll("_pbz_nested| try _pbz_nested.validateRequiredRecursive(allocator),\n");
                    continue;
                } else {
                    try writer.writeAll("payload| {\n");
                    try writeDecodeAndValidatePayload(ctx, type_name, "payload", writer, depth + 2);
                }
                try indent(writer, depth + 1);
                try writer.writeAll("},\n");
            }
        }
    }
    try indent(writer, depth + 1);
    try writer.writeAll("else => {},\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeDecodeAndValidatePayload(ctx: *const CodegenContext, type_name: []const u8, payload_expr: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("var _pbz_nested = try ");
    try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    try writer.writeAll(".decode(allocator, ");
    try writer.writeAll(payload_expr);
    try writer.writeAll(");\n");
    try indent(writer, depth);
    try writer.writeAll("defer _pbz_nested.deinit(allocator);\n");
    try indent(writer, depth);
    try writer.writeAll("try _pbz_nested.validateRequiredRecursive(allocator);\n");
}

pub fn oneofHasMessageField(message: *const schema.MessageDescriptor, oneof_name: []const u8) bool {
    for (message.fields.items) |*field| {
        if (field.oneof_name) |name| {
            if (std.mem.eql(u8, name, oneof_name) and (field.kind == .message or field.kind == .group)) return true;
        }
    }
    return false;
}
