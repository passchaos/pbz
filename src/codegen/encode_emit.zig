const schema = @import("../schema.zig");
const std = @import("std");
const wire = @import("../wire.zig");
const cg = @import("../codegen.zig");
const CodegenContext = cg.CodegenContext;
const Error = cg.Error;
const codegenCanReferenceMessageWithContext = cg.codegenCanReferenceMessageWithContext;
const fieldMessageEncoding = cg.fieldMessageEncoding;
const fieldUtf8Validation = cg.fieldUtf8Validation;
const hasPresence = cg.hasPresence;
const indent = cg.indent;
const typedMapMessageValueWithContext = cg.typedMapMessageValueWithContext;
const typedOneofMessageFieldWithContext = cg.typedOneofMessageFieldWithContext;
const typedRepeatedMessageFieldWithContext = cg.typedRepeatedMessageFieldWithContext;
const typedSingularMessageFieldWithContext = cg.typedSingularMessageFieldWithContext;
const writeMessageTypeReferenceWithContext = cg.writeMessageTypeReferenceWithContext;
const writePresenceIdent = cg.writePresenceIdent;
const writeQuotedIdent = cg.writeQuotedIdent;
const writeQuotedIdentWithSuffix = cg.writeQuotedIdentWithSuffix;
const fixedWidthViewScalarType = cg.emit_helpers.fixedWidthViewScalarType;
const rawFieldTag = cg.emit_helpers.rawFieldTag;
const rawTagValue = cg.emit_helpers.rawTagValue;
const writeMessage = cg.emit_helpers.writeMessage;

pub fn writeEncodeOneof(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, oneof: schema.OneofDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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
                try writeOneofValueEncode(ctx, field, "value", writer);
                try writer.writeAll(",\n");
            }
        }
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeEncodeOneofAssumeCapacity(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, oneof: schema.OneofDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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
                try writeOneofValueEncodeAssumeCapacity(ctx, field, "value", writer);
                try writer.writeAll(",\n");
            }
        }
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeEncode(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try writeEncodedSize(ctx, message, writer, depth);
    try writer.writeAll("\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn writeTo(self: @This(), w: *pbz.Writer) anyerror!void {\n");
    for (message.fields.items) |*field| {
        if (field.oneof_name == null) try writeEncodeField(ctx, field, writer, depth + 1);
    }
    for (message.oneofs.items) |oneof| try writeEncodeOneof(ctx, message, oneof, writer, depth + 1);
    try writeEncodeUnknownFields(writer, depth + 1);
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn writeToAssumeCapacity(self: @This(), w: *pbz.Writer) anyerror!void {\n");
    for (message.fields.items) |*field| {
        if (field.oneof_name == null) try writeEncodeFieldAssumeCapacity(ctx, field, writer, depth + 1);
    }
    for (message.oneofs.items) |oneof| try writeEncodeOneofAssumeCapacity(ctx, message, oneof, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("for (self._unknown_fields) |raw| w.appendSliceAssumeCapacity(raw);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn encode(self: @This(), allocator: std.mem.Allocator) ![]u8 {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var w = pbz.Writer.init(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer w.deinit();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try w.bytes.ensureTotalCapacity(allocator, self.encodedSize());\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.writeToAssumeCapacity(&w);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try w.toOwnedSlice();\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try writer.writeAll("\n");
    try indent(writer, depth);
    try writer.writeAll("pub fn encodeInto(self: @This(), buffer: []u8) ![]u8 {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const size = self.encodedSize();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (buffer.len < size) return error.NoSpaceLeft;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var w = pbz.Writer.initBuffer(std.heap.page_allocator, buffer[0..size]);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.writeToAssumeCapacity(&w);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return buffer[0..w.slice().len];\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try writer.writeAll("\n");
    try indent(writer, depth);
    try writer.writeAll("pub fn encodeIntoAssumeCapacity(self: @This(), buffer: []u8) ![]u8 {\n");
    if (messageCanFastDirectEncode(ctx, message)) {
        try writeFastDirectEncodeIntoAssumeCapacity(ctx, message, true, writer, depth + 1);
    } else {
        try indent(writer, depth + 1);
        try writer.writeAll("var w = pbz.Writer.initBuffer(std.heap.page_allocator, buffer);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try self.writeToAssumeCapacity(&w);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return buffer[0..w.slice().len];\n");
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try writer.writeAll("\n");
    try indent(writer, depth);
    try writer.writeAll("/// Like encodeIntoAssumeCapacity, but skips UTF-8 validation. The caller\n");
    try indent(writer, depth);
    try writer.writeAll("/// must guarantee that all string fields contain valid UTF-8.\n");
    try indent(writer, depth);
    try writer.writeAll("pub fn encodeIntoAssumeCapacityTrustedUtf8(self: @This(), buffer: []u8) ![]u8 {\n");
    if (messageCanFastDirectEncode(ctx, message)) {
        try writeFastDirectEncodeIntoAssumeCapacity(ctx, message, false, writer, depth + 1);
    } else {
        try indent(writer, depth + 1);
        try writer.writeAll("return try self.encodeIntoAssumeCapacity(buffer);\n");
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn messageCanFastDirectEncode(ctx: *const CodegenContext, message: *const schema.MessageDescriptor) bool {
    const file = ctx.file;
    var has_packed_repeated = false;
    var has_length_delimited_scalar = false;
    var has_typed_message = false;
    const has_oneof = message.oneofs.items.len != 0;
    var has_presence = false;
    var has_map = false;
    for (message.fields.items) |*field| {
        if (field.oneof_name == null and hasPresence(file, field.*)) has_presence = true;
        switch (field.kind) {
            .scalar => |scalar| switch (scalar) {
                .string, .bytes => has_length_delimited_scalar = true,
                else => {
                    if (field.cardinality == .repeated and field.resolvedPacked(file)) has_packed_repeated = true;
                },
            },
            .enumeration => {
                if (field.cardinality == .repeated and field.resolvedPacked(file)) has_packed_repeated = true;
            },
            .message, .group => {
                if (field.oneof_name != null) {
                    if (typedOneofMessageFieldWithContext(ctx, field) == null) return false;
                } else if (field.cardinality == .repeated) {
                    if (typedRepeatedMessageFieldWithContext(ctx, field) == null) return false;
                } else {
                    if (typedSingularMessageFieldWithContext(ctx, field) == null) return false;
                }
                has_typed_message = true;
            },
            .map => {
                if (!mapCanFastDirectEncode(ctx, field)) return false;
                has_map = true;
            },
        }
    }
    return has_packed_repeated or has_length_delimited_scalar or has_typed_message or has_oneof or has_presence or has_map or message.fields.items.len >= 8;
}

pub fn mapCanFastDirectEncode(ctx: *const CodegenContext, field: *const schema.FieldDescriptor) bool {
    _ = ctx;
    const map_type = switch (field.kind) {
        .map => |map| map,
        else => return false,
    };
    _ = map_type.key;
    return switch (map_type.value.*) {
        .scalar, .enumeration => true,
        .message => true,
        .group, .map => false,
    };
}

pub fn writeFastDirectEncodeIntoAssumeCapacity(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, validate_utf8: bool, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    try indent(writer, depth);
    try writer.writeAll("var index: usize = 0;\n");
    for (message.fields.items) |*field| {
        if (field.oneof_name != null) continue;
        if (field.kind == .map) {
            try writeFastDirectMapEncode(ctx, field, validate_utf8, writer, depth);
            continue;
        }
        if (field.cardinality == .repeated) {
            if (field.kind == .scalar and field.resolvedPacked(file)) {
                try writeFastDirectPackedScalarEncode(field, field.kind.scalar, writer, depth);
            } else if (field.kind == .enumeration and field.resolvedPacked(file)) {
                try writeFastDirectPackedEnumEncode(field, writer, depth);
            } else if (field.kind == .scalar) {
                try writeFastDirectRepeatedScalarEncode(ctx.file, field, field.kind.scalar, validate_utf8, writer, depth);
            } else if (field.kind == .enumeration) {
                try writeFastDirectRepeatedEnumEncode(field, writer, depth);
            } else if (field.kind == .message or field.kind == .group) {
                try writeFastDirectRepeatedMessageEncode(ctx, field, validate_utf8, writer, depth);
            }
            continue;
        }
        switch (field.kind) {
            .scalar => |scalar| try writeFastDirectScalarEncode(ctx.file, field, scalar, validate_utf8, writer, depth),
            .enumeration => try writeFastDirectEnumEncode(ctx.file, field, writer, depth),
            .message, .group => try writeFastDirectSingularMessageEncode(ctx, field, validate_utf8, writer, depth),
            .map => unreachable,
        }
    }
    for (message.oneofs.items) |oneof| try writeFastDirectOneofEncode(ctx, message, oneof, validate_utf8, writer, depth);
    try indent(writer, depth);
    try writer.writeAll("for (self._unknown_fields) |raw| { @memcpy(buffer[index..][0..raw.len], raw); index += raw.len; }\n");
    try indent(writer, depth);
    try writer.writeAll("return buffer[0..index];\n");
}

pub fn writeFastDirectScalarEncode(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, scalar: schema.ScalarType, validate_utf8: bool, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    if (hasPresence(file, field.*)) {
        try writer.writeAll("if (self.");
        try writePresenceIdent(field.name, writer);
        try writer.writeAll(") ");
    } else {
        try writeScalarSkipCondition("self.", field.name, scalar, writer);
    }
    try writer.writeAll("{ ");
    if (scalar == .string or scalar == .bytes) {
        try writeFastDirectLengthDelimitedValidation(file, field, validate_utf8, "self.", field.name, writer);
        try writeFastDirectTag(field.number, .{ .scalar = scalar }, writer);
        try writer.writeAll(" ");
        try writeFastDirectLengthDelimitedPayload("self.", field.name, writer);
        try writer.writeAll(" }\n");
        return;
    }
    try writeFastDirectTag(field.number, .{ .scalar = scalar }, writer);
    try writer.writeAll(" ");
    try writeFastDirectScalarPayload("self.", field.name, scalar, writer);
    try writer.writeAll(" }\n");
}

pub fn writeFastDirectEnumEncode(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("if (");
    if (hasPresence(file, field.*)) {
        try writer.writeAll("self.");
        try writePresenceIdent(field.name, writer);
        try writer.writeAll(") ");
    } else {
        try writer.writeAll("self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" != 0) ");
    }
    try writer.writeAll("{ ");
    try writeFastDirectTag(field.number, .{ .enumeration = "" }, writer);
    try writer.writeAll(" if (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" > 0 and self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" < 0x80) { buffer[index] = @intCast(self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll("); index += 1; } else pbz.wire.writeVarintToSlice(buffer, &index, @as(u64, @bitCast(@as(i64, self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(")))); }\n");
}

pub fn writeFastDirectRepeatedScalarEncode(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, scalar: schema.ScalarType, validate_utf8: bool, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("for (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(") |item| { ");
    if (scalar == .string or scalar == .bytes) {
        try writeFastDirectLengthDelimitedValidation(file, field, validate_utf8, "", "item", writer);
        try writeFastDirectTag(field.number, .{ .scalar = scalar }, writer);
        try writer.writeAll(" ");
        try writeFastDirectLengthDelimitedPayload("", "item", writer);
        try writer.writeAll(" }\n");
        return;
    }
    try writeFastDirectTag(field.number, .{ .scalar = scalar }, writer);
    try writer.writeAll(" ");
    try writeFastDirectScalarPayload("item", "", scalar, writer);
    try writer.writeAll(" }\n");
}

pub fn writeFastDirectSingularMessageEncode(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, validate_utf8: bool, writer: *std.Io.Writer, depth: usize) Error!void {
    if (typedSingularMessageFieldWithContext(ctx, field) == null) return;
    try indent(writer, depth);
    try writer.writeAll("if (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(") |value| { ");
    try writeFastDirectMessagePayload(field, "value", validate_utf8, writer);
    try writer.writeAll(" }\n");
}

pub fn writeFastDirectRepeatedMessageEncode(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, validate_utf8: bool, writer: *std.Io.Writer, depth: usize) Error!void {
    if (typedRepeatedMessageFieldWithContext(ctx, field) == null) return;
    try indent(writer, depth);
    try writer.writeAll("for (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(") |item| { ");
    try writeFastDirectMessagePayload(field, "item", validate_utf8, writer);
    try writer.writeAll(" }\n");
}

pub fn writeFastDirectMapEncode(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, validate_utf8: bool, writer: *std.Io.Writer, depth: usize) Error!void {
    const map_type = switch (field.kind) {
        .map => |map| map,
        else => return,
    };
    try indent(writer, depth);
    try writer.writeAll("{ var map_it = self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".iterator(); while (map_it.next()) |map_entry| {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const key = map_entry.key_ptr.*; const value = map_entry.value_ptr.*;\n");
    if (validate_utf8) {
        try writeFastDirectMapUtf8Validation(ctx.file, field, "key", .{ .scalar = map_type.key }, writer, depth + 1);
        try writeFastDirectMapUtf8Validation(ctx.file, field, "value", map_type.value.*, writer, depth + 1);
    }
    try indent(writer, depth + 1);
    try writer.writeAll("const entry_len = ");
    try writeMapEntryFieldSizeExpr(1, .{ .scalar = map_type.key }, "key", writer);
    try writer.writeAll(" + ");
    try writeMapEntryValueFieldSizeExpr(ctx, field, "value", writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writeFastDirectTag(field.number, .{ .scalar = .bytes }, writer);
    try writer.writeAll("\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pbz.wire.writeVarintToSlice(buffer, &index, entry_len);\n");
    try indent(writer, depth + 1);
    try writeFastDirectMapScalarPayload(1, map_type.key, "key", writer);
    try writer.writeAll("\n");
    try writeFastDirectMapValuePayload(ctx, field, map_type, validate_utf8, writer, depth + 1);
    try indent(writer, depth);
    try writer.writeAll("} }\n");
}

pub fn writeFastDirectMapUtf8Validation(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, value_expr: []const u8, kind: schema.FieldKind, writer: *std.Io.Writer, depth: usize) Error!void {
    if (kind == .scalar and kind.scalar == .string and fieldUtf8Validation(file, field) == .verify) {
        try indent(writer, depth);
        try writer.print("if (!pbz.validateUtf8({s})) return error.InvalidUtf8;\n", .{value_expr});
    }
}

pub fn writeFastDirectMapValuePayload(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, map_type: schema.MapType, validate_utf8: bool, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    switch (map_type.value.*) {
        .scalar => |scalar| try writeFastDirectMapScalarPayload(2, scalar, "value", writer),
        .enumeration => {
            try writeFastDirectTag(2, .{ .enumeration = "" }, writer);
            try writer.writeAll(" pbz.wire.writeVarintToSlice(buffer, &index, @as(u64, @bitCast(@as(i64, value))));");
        },
        .message => {
            if (typedMapMessageValueWithContext(ctx, field)) |_| {
                try writer.writeAll("const value_len = value.encodedSize(); ");
                try writeFastDirectTag(2, .{ .scalar = .bytes }, writer);
                try writer.writeAll(" pbz.wire.writeVarintToSlice(buffer, &index, value_len); _ = try value.");
                try writer.writeAll(if (validate_utf8) "encodeIntoAssumeCapacity" else "encodeIntoAssumeCapacityTrustedUtf8");
                try writer.writeAll("(buffer[index..][0..value_len]); index += value_len;");
            } else {
                try writeFastDirectTag(2, .{ .scalar = .bytes }, writer);
                try writer.writeAll(" ");
                try writeFastDirectLengthDelimitedPayload("", "value", writer);
            }
        },
        .group, .map => try writer.writeAll("@compileError(\"unsupported map value\")"),
    }
    try writer.writeAll("\n");
}

pub fn writeFastDirectMapScalarPayload(number: u29, scalar: schema.ScalarType, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    try writeFastDirectTag(number, .{ .scalar = scalar }, writer);
    try writer.writeByte(' ');
    if (scalar == .string or scalar == .bytes) {
        try writeFastDirectLengthDelimitedPayload("", value_expr, writer);
    } else {
        try writeFastDirectScalarPayload(value_expr, "", scalar, writer);
    }
}

pub fn writeFastDirectOneofEncode(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, oneof: schema.OneofDescriptor, validate_utf8: bool, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("switch (self.");
    try writeQuotedIdent(oneof.name, writer);
    try writer.writeAll(") {\n");
    try indent(writer, depth + 1);
    try writer.writeAll(".none => {},\n");
    for (message.fields.items) |*field| {
        const oneof_name = field.oneof_name orelse continue;
        if (!std.mem.eql(u8, oneof_name, oneof.name)) continue;
        try indent(writer, depth + 1);
        try writer.writeAll(".");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" => |value| { ");
        switch (field.kind) {
            .scalar => |scalar| {
                if (scalar == .string or scalar == .bytes) {
                    try writeFastDirectLengthDelimitedValidation(ctx.file, field, validate_utf8, "", "value", writer);
                    try writeFastDirectTag(field.number, .{ .scalar = scalar }, writer);
                    try writer.writeAll(" ");
                    try writeFastDirectLengthDelimitedPayload("", "value", writer);
                } else {
                    try writeFastDirectTag(field.number, .{ .scalar = scalar }, writer);
                    try writer.writeAll(" ");
                    try writeFastDirectScalarPayload("value", "", scalar, writer);
                }
            },
            .enumeration => {
                try writeFastDirectTag(field.number, .{ .enumeration = "" }, writer);
                try writer.writeAll(" pbz.wire.writeVarintToSlice(buffer, &index, @as(u64, @bitCast(@as(i64, value))));");
            },
            .message, .group => try writeFastDirectMessagePayload(field, "value", validate_utf8, writer),
            .map => try writer.writeAll("@compileError(\"unsupported oneof map\")"),
        }
        try writer.writeAll(" },\n");
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeFastDirectMessagePayload(field: *const schema.FieldDescriptor, value_expr: []const u8, validate_utf8: bool, writer: *std.Io.Writer) Error!void {
    if (field.kind == .group) {
        try writeFastDirectRawTag(field.number, .start_group, writer);
        try writer.writeAll(" _ = try ");
        try writer.writeAll(value_expr);
        try writer.writeAll(if (validate_utf8) ".encodeIntoAssumeCapacity(buffer[index..]);" else ".encodeIntoAssumeCapacityTrustedUtf8(buffer[index..]);");
        try writer.writeAll(" index += ");
        try writer.writeAll(value_expr);
        try writer.writeAll(".encodedSize(); ");
        try writeFastDirectRawTag(field.number, .end_group, writer);
        return;
    }
    try writer.writeAll("const payload_len = ");
    try writer.writeAll(value_expr);
    try writer.writeAll(".encodedSize(); ");
    try writeFastDirectTag(field.number, .{ .scalar = .bytes }, writer);
    try writer.writeAll(" pbz.wire.writeVarintToSlice(buffer, &index, payload_len); ");
    try writer.writeAll("_ = try ");
    try writer.writeAll(value_expr);
    try writer.writeAll(if (validate_utf8) ".encodeIntoAssumeCapacity(buffer[index..][0..payload_len]);" else ".encodeIntoAssumeCapacityTrustedUtf8(buffer[index..][0..payload_len]);");
    try writer.writeAll(" index += payload_len;");
}

pub fn writeFastDirectLengthDelimitedValidation(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, validate_utf8: bool, prefix: []const u8, value_name: []const u8, writer: *std.Io.Writer) Error!void {
    if (!validate_utf8 or field.kind != .scalar or field.kind.scalar != .string or fieldUtf8Validation(file, field) != .verify) return;
    try writer.writeAll("if (!pbz.validateUtf8(");
    try writer.writeAll(prefix);
    if (value_name.len != 0) try writeQuotedIdent(value_name, writer);
    try writer.writeAll(")) return error.InvalidUtf8; ");
}

pub fn writeFastDirectLengthDelimitedPayload(prefix: []const u8, value_name: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("pbz.wire.writeVarintToSlice(buffer, &index, ");
    try writer.writeAll(prefix);
    if (value_name.len != 0) try writeQuotedIdent(value_name, writer);
    try writer.writeAll(".len); pbz.wire.copyBytes(buffer[index..][0..");
    try writer.writeAll(prefix);
    if (value_name.len != 0) try writeQuotedIdent(value_name, writer);
    try writer.writeAll(".len], ");
    try writer.writeAll(prefix);
    if (value_name.len != 0) try writeQuotedIdent(value_name, writer);
    try writer.writeAll("); index += ");
    try writer.writeAll(prefix);
    if (value_name.len != 0) try writeQuotedIdent(value_name, writer);
    try writer.writeAll(".len;");
}

pub fn writeFastDirectRepeatedEnumEncode(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("for (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(") |item| { ");
    try writeFastDirectTag(field.number, .{ .enumeration = "" }, writer);
    try writer.writeAll(" pbz.wire.writeVarintToSlice(buffer, &index, @as(u64, @bitCast(@as(i64, item)))); }\n");
}

pub fn writeFastDirectPackedScalarEncode(field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("if (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".len != 0) {\n");
    if (fixedPackedScalarWidth(scalar)) |width| {
        try indent(writer, depth + 1);
        try writer.writeAll("const packed_len = self.");
        try writeQuotedIdent(field.name, writer);
        try writer.print(".len * {d};\n", .{width});
        try indent(writer, depth + 1);
        try writeFastDirectTag(field.number, .{ .scalar = .bytes }, writer);
        try writer.writeAll("\n");
        try indent(writer, depth + 1);
        try writer.writeAll("pbz.wire.writeVarintToSlice(buffer, &index, packed_len);\n");
        if (fixedWidthViewScalarType(scalar)) |_| {
            try indent(writer, depth + 1);
            if (scalar == .double) {
                try writer.writeAll("if (comptime @import(\"builtin\").target.cpu.arch.endian() == .little) { const payload = std.mem.sliceAsBytes(self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll("); pbz.wire.copyBytes(buffer[index..][0..payload.len], payload); index += payload.len; } else { for (self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(") |item| pbz.wire.writeRawLittleToSlice(u64, buffer, &index, @bitCast(item)); }\n");
            } else if (scalar == .float) {
                try writer.writeAll("if (comptime @import(\"builtin\").target.cpu.arch.endian() == .little) { const payload = std.mem.sliceAsBytes(self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll("); pbz.wire.copyBytes(buffer[index..][0..payload.len], payload); index += payload.len; } else { for (self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(") |item| pbz.wire.writeRawLittleToSlice(u32, buffer, &index, @bitCast(item)); }\n");
            } else {
                try writer.writeAll("const payload = std.mem.sliceAsBytes(self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll("); pbz.wire.copyBytes(buffer[index..][0..payload.len], payload); index += payload.len;\n");
            }
        } else if (scalar == .bool) {
            try indent(writer, depth + 1);
            try writer.writeAll("const payload = std.mem.sliceAsBytes(self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll("); pbz.wire.copyBytes(buffer[index..][0..payload.len], payload); index += payload.len;\n");
        } else {
            try indent(writer, depth + 1);
            try writer.writeAll("for (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(") |item| ");
            try writeFastDirectPackedScalarPayload("item", scalar, writer);
            try writer.writeAll("\n");
        }
    } else {
        try indent(writer, depth + 1);
        try writeFastDirectTag(field.number, .{ .scalar = .bytes }, writer);
        try writer.writeAll("\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const packed_len_reserved = pbz.wire.encodedVarintSize(self.");
        try writeQuotedIdent(field.name, writer);
        try writer.print(".len * {d});\n", .{maxPackedScalarWidth(scalar)});
        try indent(writer, depth + 1);
        try writer.writeAll("const packed_len_index = index; index += packed_len_reserved;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const payload_start = index;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("for (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(") |item| ");
        try writeFastDirectPackedScalarPayload("item", scalar, writer);
        try writer.writeAll("\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const packed_len = index - payload_start;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const packed_len_size = pbz.wire.encodedVarintSize(packed_len);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("if (packed_len_size != packed_len_reserved) {\n");
        try indent(writer, depth + 2);
        try writer.writeAll("if (packed_len_size > packed_len_reserved) { std.mem.copyBackwards(u8, buffer[payload_start + (packed_len_size - packed_len_reserved) .. index + (packed_len_size - packed_len_reserved)], buffer[payload_start..index]); index += packed_len_size - packed_len_reserved; }\n");
        try indent(writer, depth + 2);
        try writer.writeAll("else { std.mem.copyForwards(u8, buffer[payload_start - (packed_len_reserved - packed_len_size) .. index - (packed_len_reserved - packed_len_size)], buffer[payload_start..index]); index -= packed_len_reserved - packed_len_size; }\n");
        try indent(writer, depth + 1);
        try writer.writeAll("}\n");
        try indent(writer, depth + 1);
        try writer.writeAll("var packed_len_write_index = packed_len_index; pbz.wire.writeVarintToSlice(buffer, &packed_len_write_index, packed_len);\n");
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeFastDirectPackedEnumEncode(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("if (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".len != 0) {\n");
    try indent(writer, depth + 1);
    try writeFastDirectTag(field.number, .{ .scalar = .bytes }, writer);
    try writer.writeAll("\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const packed_len_reserved = pbz.wire.encodedVarintSize(self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".len * 10);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const packed_len_index = index; index += packed_len_reserved;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const payload_start = index;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("for (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(") |item| { if (item >= 0 and item < 0x80) { buffer[index] = @intCast(item); index += 1; } else pbz.wire.writeVarintToSlice(buffer, &index, @as(u64, @bitCast(@as(i64, item)))); }\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const packed_len = index - payload_start;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const packed_len_size = pbz.wire.encodedVarintSize(packed_len);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (packed_len_size != packed_len_reserved) {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("if (packed_len_size > packed_len_reserved) { std.mem.copyBackwards(u8, buffer[payload_start + (packed_len_size - packed_len_reserved) .. index + (packed_len_size - packed_len_reserved)], buffer[payload_start..index]); index += packed_len_size - packed_len_reserved; }\n");
    try indent(writer, depth + 2);
    try writer.writeAll("else { std.mem.copyForwards(u8, buffer[payload_start - (packed_len_reserved - packed_len_size) .. index - (packed_len_reserved - packed_len_size)], buffer[payload_start..index]); index -= packed_len_reserved - packed_len_size; }\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var packed_len_write_index = packed_len_index; pbz.wire.writeVarintToSlice(buffer, &packed_len_write_index, packed_len);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeFastDirectTag(number: u29, kind: schema.FieldKind, writer: *std.Io.Writer) Error!void {
    const tag = rawFieldTag(number, kind);
    try writeFastDirectTagValue(tag, writer);
}

pub fn writeFastDirectRawTag(number: u29, wire_type: wire.WireType, writer: *std.Io.Writer) Error!void {
    const tag = rawTagValue(number, wire_type);
    try writeFastDirectTagValue(tag, writer);
}

pub fn writeFastDirectTagValue(tag: u64, writer: *std.Io.Writer) Error!void {
    if (tag <= std.math.maxInt(u8)) {
        try writer.print("buffer[index] = {d}; index += 1;", .{tag});
    } else {
        try writer.print("pbz.wire.writeVarintToSlice(buffer, &index, {d});", .{tag});
    }
}

pub fn writeFastDirectScalarPayload(prefix: []const u8, field_name: []const u8, scalar: schema.ScalarType, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .double => try writeFastDirectRawFieldPayload(prefix, field_name, "u64", true, writer),
        .float => try writeFastDirectRawFieldPayload(prefix, field_name, "u32", true, writer),
        .fixed32 => try writeFastDirectRawFieldPayload(prefix, field_name, "u32", false, writer),
        .fixed64 => try writeFastDirectRawFieldPayload(prefix, field_name, "u64", false, writer),
        .sfixed32 => try writeFastDirectRawFieldPayload(prefix, field_name, "i32", false, writer),
        .sfixed64 => try writeFastDirectRawFieldPayload(prefix, field_name, "i64", false, writer),
        .int32 => try writeFastDirectVarintFieldPayload(prefix, field_name, "@as(u64, @bitCast(@as(i64, ", ")))", writer),
        .int64 => try writeFastDirectVarintFieldPayload(prefix, field_name, "@as(u64, @bitCast(", "))", writer),
        .uint32, .uint64 => try writeFastDirectVarintFieldPayload(prefix, field_name, "", "", writer),
        .sint32 => try writeFastDirectVarintFieldPayload(prefix, field_name, "pbz.wire.zigZagEncode32(", ")", writer),
        .sint64 => try writeFastDirectVarintFieldPayload(prefix, field_name, "pbz.wire.zigZagEncode64(", ")", writer),
        .bool => try writeFastDirectBoolFieldPayload(prefix, field_name, writer),
        .string, .bytes => try writer.writeAll("@compileError(\"unsupported direct payload\")"),
    }
}

pub fn writeFastDirectRawFieldPayload(prefix: []const u8, field_name: []const u8, zig_type: []const u8, bitcast_value: bool, writer: *std.Io.Writer) Error!void {
    try writer.print("pbz.wire.writeRawLittleToSlice({s}, buffer, &index, ", .{zig_type});
    if (bitcast_value) try writer.writeAll("@bitCast(");
    try writer.writeAll(prefix);
    if (field_name.len != 0) try writeQuotedIdent(field_name, writer);
    if (bitcast_value) try writer.writeAll(")");
    try writer.writeAll(");");
}

pub fn writeFastDirectVarintFieldPayload(prefix: []const u8, field_name: []const u8, before: []const u8, after: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("pbz.wire.writeDirectScalarVarintToSlice(buffer, &index, ");
    try writer.writeAll(before);
    try writer.writeAll(prefix);
    if (field_name.len != 0) try writeQuotedIdent(field_name, writer);
    try writer.writeAll(after);
    try writer.writeAll(");");
}

pub fn writeFastDirectBoolFieldPayload(prefix: []const u8, field_name: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("buffer[index] = if (");
    try writer.writeAll(prefix);
    if (field_name.len != 0) try writeQuotedIdent(field_name, writer);
    try writer.writeAll(") 1 else 0; index += 1;");
}

pub fn writeFastDirectPackedScalarPayload(value_expr: []const u8, scalar: schema.ScalarType, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .int32 => try writer.print("pbz.wire.writeVarintToSlice(buffer, &index, @as(u64, @bitCast(@as(i64, {s}))));", .{value_expr}),
        .int64 => try writer.print("if ({s} < 0) pbz.wire.writeNegativeInt64VarintToSlice(buffer, &index, {s}) else pbz.wire.writeVarintToSlice(buffer, &index, @intCast({s}));", .{ value_expr, value_expr, value_expr }),
        .uint32 => try writer.print("pbz.wire.writeUInt32VarintToSlice(buffer, &index, {s});", .{value_expr}),
        .uint64 => try writer.print("pbz.wire.writeVarintToSlice(buffer, &index, {s});", .{value_expr}),
        .sint32 => try writer.print("pbz.wire.writeVarintToSlice(buffer, &index, pbz.wire.zigZagEncode32({s}));", .{value_expr}),
        .sint64 => try writer.print("pbz.wire.writeVarintToSlice(buffer, &index, pbz.wire.zigZagEncode64({s}));", .{value_expr}),
        .bool => try writer.print("{{ buffer[index] = if ({s}) 1 else 0; index += 1; }}", .{value_expr}),
        else => try writer.writeAll("@compileError(\"unsupported packed direct payload\")"),
    }
}

pub fn maxPackedScalarWidth(scalar: schema.ScalarType) usize {
    return switch (scalar) {
        .bool => 1,
        .uint32, .sint32 => 5,
        .int32, .int64, .uint64, .sint64 => 10,
        .double, .fixed64, .sfixed64 => 8,
        .float, .fixed32, .sfixed32 => 4,
        .string, .bytes => unreachable,
    };
}

pub fn writeEncodedSize(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn encodedSize(self: @This()) usize {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var size: usize = 0;\n");
    for (message.fields.items) |*field| {
        if (field.oneof_name == null) try writeEncodedSizeField(ctx, field, "self.", writer, depth + 1);
    }
    for (message.oneofs.items) |oneof| try writeEncodedSizeOneof(ctx, message, oneof, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("for (self._unknown_fields) |raw| size += raw.len;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return size;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeEncodedSizeField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, receiver: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    if (field.kind == .map) return try writeEncodedSizeMapField(ctx, field, receiver, writer, depth);
    if (field.cardinality == .repeated) return try writeEncodedSizeRepeatedField(ctx, field, receiver, writer, depth);
    try indent(writer, depth);
    if (typedSingularMessageFieldWithContext(ctx, field)) |_| {
        try writer.writeAll("if (");
        try writer.writeAll(receiver);
        try writeQuotedIdent(field.name, writer);
        if (field.kind == .group) {
            try writer.writeAll(") |value| size += ");
            try writer.print("{d}", .{(wire.tagSize(field.number, .start_group) catch unreachable) + (wire.tagSize(field.number, .end_group) catch unreachable)});
            try writer.writeAll(" + value.encodedSize();\n");
        } else {
            try writer.writeAll(") |value| { const payload_len = value.encodedSize(); size += ");
            try writer.print("{d}", .{wire.tagSize(field.number, .length_delimited) catch unreachable});
            try writer.writeAll(" + pbz.wire.encodedVarintSize(payload_len) + payload_len; }\n");
        }
        return;
    }
    if (hasPresence(file, field.*)) {
        try writer.writeAll("if (");
        try writer.writeAll(receiver);
        try writePresenceIdent(field.name, writer);
        try writer.writeAll(") size += ");
        try writeSingleFieldEncodedSizeExpr(field.number, field.kind, receiver, field.name, writer);
        try writer.writeAll(";\n");
    } else {
        switch (field.kind) {
            .scalar => |scalar| {
                try writeScalarSkipCondition(receiver, field.name, scalar, writer);
                try writer.writeAll("size += ");
                try writeSingleFieldEncodedSizeExpr(field.number, field.kind, receiver, field.name, writer);
                try writer.writeAll(";\n");
            },
            .enumeration => {
                try writer.writeAll("if (");
                try writer.writeAll(receiver);
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(" != 0) size += ");
                try writeSingleFieldEncodedSizeExpr(field.number, field.kind, receiver, field.name, writer);
                try writer.writeAll(";\n");
            },
            .message, .group => {
                try writer.writeAll("if (");
                try writer.writeAll(receiver);
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(".len != 0) size += ");
                try writeSingleFieldEncodedSizeExpr(field.number, field.kind, receiver, field.name, writer);
                try writer.writeAll(";\n");
            },
            .map => unreachable,
        }
    }
}

pub fn writeEncodedSizeRepeatedField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, receiver: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    if (typedRepeatedMessageFieldWithContext(ctx, field)) |_| {
        try indent(writer, depth);
        try writer.writeAll("for (");
        try writer.writeAll(receiver);
        try writeQuotedIdent(field.name, writer);
        if (field.kind == .group) {
            try writer.writeAll(") |item| size += ");
            try writer.print("{d}", .{(wire.tagSize(field.number, .start_group) catch unreachable) + (wire.tagSize(field.number, .end_group) catch unreachable)});
            try writer.writeAll(" + item.encodedSize();\n");
        } else {
            try writer.writeAll(") |item| { const payload_len = item.encodedSize(); size += ");
            try writer.print("{d}", .{wire.tagSize(field.number, .length_delimited) catch unreachable});
            try writer.writeAll(" + pbz.wire.encodedVarintSize(payload_len) + payload_len; }\n");
        }
        return;
    }
    if ((field.kind == .scalar or field.kind == .enumeration) and field.resolvedPacked(file)) {
        try indent(writer, depth);
        try writer.writeAll("if (");
        try writer.writeAll(receiver);
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(".len != 0) {\n");
        try indent(writer, depth + 1);
        const fixed_width = if (field.kind == .scalar) fixedPackedScalarWidth(field.kind.scalar) else null;
        if (fixed_width) |width| {
            try writer.writeAll("const packed_len = ");
            try writer.writeAll(receiver);
            try writeQuotedIdent(field.name, writer);
            try writer.print(".len * {d};\n", .{width});
        } else {
            try writer.writeAll("var packed_len: usize = 0;\n");
            try indent(writer, depth + 1);
            try writer.writeAll("for (");
            try writer.writeAll(receiver);
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(") |item| packed_len += ");
            if (field.kind == .scalar) {
                try writeScalarPayloadSizeExpr(field.kind.scalar, "item", writer);
            } else {
                try writer.writeAll("pbz.wire.encodedVarintSize(@as(u64, @bitCast(@as(i64, item))))");
            }
            try writer.writeAll(";\n");
        }
        try indent(writer, depth + 1);
        try writer.print("size += {d} + pbz.wire.encodedVarintSize(packed_len) + packed_len;\n", .{wire.tagSize(field.number, .length_delimited) catch unreachable});
        try indent(writer, depth);
        try writer.writeAll("}\n");
        return;
    }

    try indent(writer, depth);
    try writer.writeAll("for (");
    try writer.writeAll(receiver);
    try writeQuotedIdent(field.name, writer);
    if (field.kind == .scalar and scalarPayloadSizeIsConstant(field.kind.scalar)) {
        try writer.writeAll(") |_| size += ");
    } else {
        try writer.writeAll(") |item| size += ");
    }
    try writeSingleFieldEncodedSizeExprForValue(field.number, field.kind, "item", writer);
    try writer.writeAll(";\n");
}

pub fn writeEncodedSizeMapField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, receiver: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    const map_type = field.kind.map;
    const key_constant = scalarPayloadSizeIsConstant(map_type.key);
    const value_kind = map_type.value.*;
    const value_constant = value_kind == .scalar and scalarPayloadSizeIsConstant(value_kind.scalar);
    try indent(writer, depth);
    try writer.writeAll("{ var map_it = ");
    try writer.writeAll(receiver);
    try writeQuotedIdent(field.name, writer);
    if (key_constant and value_constant) {
        try writer.writeAll(".iterator(); while (map_it.next()) |_| {\n");
    } else {
        try writer.writeAll(".iterator(); while (map_it.next()) |entry| {\n");
    }
    if (!key_constant or !value_constant) {
        try indent(writer, depth + 1);
        if (!key_constant) try writer.writeAll("const key = entry.key_ptr.*; ");
        if (!value_constant) try writer.writeAll("const value = entry.value_ptr.*;");
        try writer.writeAll("\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("const entry_len = ");
    try writeMapEntryFieldSizeExpr(1, .{ .scalar = map_type.key }, "key", writer);
    try writer.writeAll(" + ");
    try writeMapEntryValueFieldSizeExpr(ctx, field, "value", writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.print("size += {d} + pbz.wire.encodedVarintSize(entry_len) + entry_len;\n", .{wire.tagSize(field.number, .length_delimited) catch unreachable});
    try indent(writer, depth);
    try writer.writeAll("} }\n");
}

pub fn writeEncodedSizeOneof(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, oneof: schema.OneofDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("switch (self.");
    try writeQuotedIdent(oneof.name, writer);
    try writer.writeAll(") {\n");
    try indent(writer, depth + 1);
    try writer.writeAll(".none => {},\n");
    for (message.fields.items) |*field| {
        if (field.oneof_name) |name| {
            if (!std.mem.eql(u8, name, oneof.name)) continue;
            try indent(writer, depth + 1);
            try writer.writeAll(".");
            try writeQuotedIdent(field.name, writer);
            if (typedOneofMessageFieldWithContext(ctx, field)) |_| {
                if (field.kind == .group) {
                    try writer.writeAll(" => |value| size += ");
                    try writer.print("{d}", .{(wire.tagSize(field.number, .start_group) catch unreachable) + (wire.tagSize(field.number, .end_group) catch unreachable)});
                    try writer.writeAll(" + value.encodedSize(),\n");
                } else {
                    try writer.writeAll(" => |value| { const payload_len = value.encodedSize(); size += ");
                    try writer.print("{d}", .{wire.tagSize(field.number, .length_delimited) catch unreachable});
                    try writer.writeAll(" + pbz.wire.encodedVarintSize(payload_len) + payload_len; },\n");
                }
            } else {
                if (field.kind == .scalar and scalarPayloadSizeIsConstant(field.kind.scalar)) {
                    try writer.writeAll(" => size += ");
                } else {
                    try writer.writeAll(" => |value| size += ");
                }
                try writeSingleFieldEncodedSizeExprForValue(field.number, field.kind, "value", writer);
                try writer.writeAll(",\n");
            }
        }
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeSingleFieldEncodedSizeExpr(number: u29, kind: schema.FieldKind, receiver: []const u8, field_name: []const u8, writer: *std.Io.Writer) Error!void {
    try writeSingleFieldEncodedSizePrefix(number, kind, writer);
    try writer.writeAll(" + ");
    try writeKindPayloadSizeExprForField(kind, receiver, field_name, writer);
}

pub fn writeSingleFieldEncodedSizeExprForValue(number: u29, kind: schema.FieldKind, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    try writeSingleFieldEncodedSizePrefix(number, kind, writer);
    try writer.writeAll(" + ");
    try writeKindPayloadSizeExpr(kind, value_expr, writer);
}

pub fn writeSingleFieldEncodedSizePrefix(number: u29, kind: schema.FieldKind, writer: *std.Io.Writer) Error!void {
    switch (kind) {
        .group => {
            const start = wire.tagSize(number, .start_group) catch unreachable;
            const end = wire.tagSize(number, .end_group) catch unreachable;
            try writer.print("{d} + {d}", .{ start, end });
        },
        else => {
            const tag = wire.tagSize(number, kind.wireType()) catch unreachable;
            try writer.print("{d}", .{tag});
        },
    }
}

pub fn writeKindPayloadSizeExprForField(kind: schema.FieldKind, receiver: []const u8, field_name: []const u8, writer: *std.Io.Writer) Error!void {
    switch (kind) {
        .scalar => |scalar| try writeScalarPayloadSizeExprForField(scalar, receiver, field_name, writer),
        .enumeration => {
            try writer.writeAll("pbz.wire.encodedVarintSize(@as(u64, @bitCast(@as(i64, ");
            try writer.writeAll(receiver);
            try writeQuotedIdent(field_name, writer);
            try writer.writeAll("))))");
        },
        .message => {
            try writer.writeAll("pbz.wire.encodedVarintSize(");
            try writer.writeAll(receiver);
            try writeQuotedIdent(field_name, writer);
            try writer.writeAll(".len) + ");
            try writer.writeAll(receiver);
            try writeQuotedIdent(field_name, writer);
            try writer.writeAll(".len");
        },
        .group => {
            try writer.writeAll(receiver);
            try writeQuotedIdent(field_name, writer);
            try writer.writeAll(".len");
        },
        .map => unreachable,
    }
}

pub fn writeScalarPayloadSizeExprForField(scalar: schema.ScalarType, receiver: []const u8, field_name: []const u8, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .double, .fixed64, .sfixed64 => try writer.writeAll("8"),
        .float, .fixed32, .sfixed32 => try writer.writeAll("4"),
        .int32 => {
            try writer.writeAll("pbz.wire.encodedVarintSize(@as(u64, @bitCast(@as(i64, ");
            try writer.writeAll(receiver);
            try writeQuotedIdent(field_name, writer);
            try writer.writeAll("))))");
        },
        .int64 => {
            try writer.writeAll("pbz.wire.encodedVarintSize(@as(u64, @bitCast(");
            try writer.writeAll(receiver);
            try writeQuotedIdent(field_name, writer);
            try writer.writeAll(")))");
        },
        .uint32, .uint64 => {
            try writer.writeAll("pbz.wire.encodedVarintSize(");
            try writer.writeAll(receiver);
            try writeQuotedIdent(field_name, writer);
            try writer.writeAll(")");
        },
        .sint32 => {
            try writer.writeAll("pbz.wire.encodedVarintSize(pbz.wire.zigZagEncode32(");
            try writer.writeAll(receiver);
            try writeQuotedIdent(field_name, writer);
            try writer.writeAll("))");
        },
        .sint64 => {
            try writer.writeAll("pbz.wire.encodedVarintSize(pbz.wire.zigZagEncode64(");
            try writer.writeAll(receiver);
            try writeQuotedIdent(field_name, writer);
            try writer.writeAll("))");
        },
        .bool => {
            try writer.writeAll("(if (");
            try writer.writeAll(receiver);
            try writeQuotedIdent(field_name, writer);
            try writer.writeAll(") @as(usize, 1) else @as(usize, 1))");
        },
        .string, .bytes => {
            try writer.writeAll("pbz.wire.encodedVarintSize(");
            try writer.writeAll(receiver);
            try writeQuotedIdent(field_name, writer);
            try writer.writeAll(".len) + ");
            try writer.writeAll(receiver);
            try writeQuotedIdent(field_name, writer);
            try writer.writeAll(".len");
        },
    }
}

pub fn writeEncodeDeterministic(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn writeDeterministicTo(self: @This(), allocator: std.mem.Allocator, w: *pbz.Writer) anyerror!void {\n");
    try writeEncodeFieldsByNumber(ctx, message, writer, depth + 1);
    try writeEncodeUnknownFieldsDeterministic(writer, depth + 1);
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn writeDeterministicToAssumeCapacity(self: @This(), allocator: std.mem.Allocator, w: *pbz.Writer) anyerror!void {\n");
    try writeEncodeFieldsByNumberAssumeCapacity(ctx, message, writer, depth + 1);
    try writeEncodeUnknownFieldsDeterministicAssumeCapacity(writer, depth + 1);
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn encodeDeterministic(self: @This(), allocator: std.mem.Allocator) ![]u8 {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var w = pbz.Writer.init(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer w.deinit();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try w.bytes.ensureTotalCapacity(allocator, self.encodedSize());\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.writeDeterministicToAssumeCapacity(allocator, &w);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try w.toOwnedSlice();\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn encodeDeterministicInto(self: @This(), allocator: std.mem.Allocator, buffer: []u8) ![]u8 {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const size = self.encodedSize();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (buffer.len < size) return error.NoSpaceLeft;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var w = pbz.Writer.initBuffer(std.heap.page_allocator, buffer[0..size]);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.writeDeterministicToAssumeCapacity(allocator, &w);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return buffer[0..w.slice().len];\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn encodeDeterministicIntoAssumeCapacity(self: @This(), allocator: std.mem.Allocator, buffer: []u8) ![]u8 {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var w = pbz.Writer.initBuffer(std.heap.page_allocator, buffer);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.writeDeterministicToAssumeCapacity(allocator, &w);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return buffer[0..w.slice().len];\n");
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

pub fn writeEncodeUnknownFields(writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("for (self._unknown_fields) |raw| try w.appendSlice(raw);\n");
}

pub fn writeEncodeUnknownFieldsDeterministic(writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("try pbz.wire.writeRawFieldsDeterministic(allocator, self._unknown_fields, w);\n");
}

pub fn writeEncodeUnknownFieldsDeterministicAssumeCapacity(writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("try pbz.wire.writeRawFieldsDeterministicAssumeCapacity(allocator, self._unknown_fields, w);\n");
}

pub fn writeEncodeFieldsByNumber(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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
            try writeEncodeOneofSingleField(ctx, field, oneof_name, writer, depth);
        } else if (field.kind == .map) {
            try writeEncodeMapFieldDeterministic(ctx, field, writer, depth);
        } else {
            try writeEncodeFieldDeterministic(ctx, field, writer, depth);
        }
    }
}

pub fn writeEncodeFieldsByNumberAssumeCapacity(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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
            try writeEncodeOneofSingleFieldDeterministicAssumeCapacity(ctx, field, oneof_name, writer, depth);
        } else if (field.kind == .map) {
            try writeEncodeMapFieldDeterministicAssumeCapacity(ctx, field, writer, depth);
        } else {
            try writeEncodeFieldDeterministicAssumeCapacity(ctx, field, writer, depth);
        }
    }
}

pub fn writeEncodeOneofSingleField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, oneof_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("switch (self.");
    try writeQuotedIdent(oneof_name, writer);
    try writer.writeAll(") {\n");
    try indent(writer, depth + 1);
    try writer.writeAll(".");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" => |value| ");
    try writeOneofValueEncodeDeterministic(ctx, field, "value", writer);
    try writer.writeAll(",\n");
    try indent(writer, depth + 1);
    try writer.writeAll("else => {},\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeEncodeOneofSingleFieldDeterministicAssumeCapacity(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, oneof_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("switch (self.");
    try writeQuotedIdent(oneof_name, writer);
    try writer.writeAll(") {\n");
    try indent(writer, depth + 1);
    try writer.writeAll(".");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" => |value| ");
    try writeOneofValueEncodeDeterministicAssumeCapacity(ctx, field, "value", writer);
    try writer.writeAll(",\n");
    try indent(writer, depth + 1);
    try writer.writeAll("else => {},\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeOneofValueEncodeDeterministic(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    const file = ctx.file;
    switch (field.kind) {
        .message => |type_name| {
            if (codegenCanReferenceMessageWithContext(ctx, type_name)) {
                if (typedOneofMessageFieldWithContext(ctx, field)) |_| {
                    try writer.print("{{ const payload_len = {s}.encodedSize(); try w.writeTag({d}, .length_delimited); try w.writeVarint(payload_len); try {s}.writeDeterministicTo(allocator, w); }}", .{ value_expr, field.number, value_expr });
                } else {
                    try writer.writeAll("{ ");
                    try writeEncodeMessagePayloadDeterministic(ctx, field.number, fieldMessageEncoding(file, field) == .delimited, type_name, value_expr, "w", writer);
                    try writer.writeAll(" }");
                }
            } else try writeOneofValueEncode(ctx, field, value_expr, writer);
        },
        .group => |type_name| {
            if (codegenCanReferenceMessageWithContext(ctx, type_name)) {
                if (typedOneofMessageFieldWithContext(ctx, field)) |_| {
                    try writer.print("{{ try w.writeTag({d}, .start_group); try {s}.writeDeterministicTo(allocator, w); try w.writeTag({d}, .end_group); }}", .{ field.number, value_expr, field.number });
                } else {
                    try writer.writeAll("{ ");
                    try writeEncodeMessagePayloadDeterministic(ctx, field.number, true, type_name, value_expr, "w", writer);
                    try writer.writeAll(" }");
                }
            } else try writeOneofValueEncode(ctx, field, value_expr, writer);
        },
        else => try writeOneofValueEncode(ctx, field, value_expr, writer),
    }
}

pub fn writeOneofValueEncodeDeterministicAssumeCapacity(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    const file = ctx.file;
    switch (field.kind) {
        .message => |type_name| {
            if (codegenCanReferenceMessageWithContext(ctx, type_name)) {
                if (typedOneofMessageFieldWithContext(ctx, field)) |_| {
                    try writer.print("{{ const payload_len = {s}.encodedSize(); w.writeTagAssumeCapacity({d}, .length_delimited); w.writeVarintAssumeCapacity(payload_len); try {s}.writeDeterministicToAssumeCapacity(allocator, w); }}", .{ value_expr, field.number, value_expr });
                } else {
                    try writer.writeAll("{ ");
                    try writeEncodeMessagePayloadDeterministic(ctx, field.number, fieldMessageEncoding(file, field) == .delimited, type_name, value_expr, "w", writer);
                    try writer.writeAll(" }");
                }
            } else try writeOneofValueEncodeAssumeCapacity(ctx, field, value_expr, writer);
        },
        .group => |type_name| {
            if (codegenCanReferenceMessageWithContext(ctx, type_name)) {
                if (typedOneofMessageFieldWithContext(ctx, field)) |_| {
                    try writer.print("{{ w.writeTagAssumeCapacity({d}, .start_group); try {s}.writeDeterministicToAssumeCapacity(allocator, w); w.writeTagAssumeCapacity({d}, .end_group); }}", .{ field.number, value_expr, field.number });
                } else {
                    try writer.writeAll("{ ");
                    try writeEncodeMessagePayloadDeterministic(ctx, field.number, true, type_name, value_expr, "w", writer);
                    try writer.writeAll(" }");
                }
            } else try writeOneofValueEncodeAssumeCapacity(ctx, field, value_expr, writer);
        },
        else => try writeOneofValueEncodeAssumeCapacity(ctx, field, value_expr, writer),
    }
}

pub fn writeEncodeInitialized(writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn encodeInitialized(self: @This(), allocator: std.mem.Allocator) ![]u8 {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.validateRequiredRecursive(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try self.encode(allocator);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeEncodeField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    switch (field.kind) {
        .scalar => |scalar| try writeEncodeScalarField(file, field, scalar, writer, depth),
        .enumeration => try writeEncodeEnumField(file, field, writer, depth),
        .message => try writeEncodeMessageField(ctx, field, writer, depth),
        .group => try writeEncodeGroupField(ctx, field, writer, depth),
        .map => try writeEncodeMapField(ctx, field, writer, depth),
    }
}

pub fn writeEncodeFieldAssumeCapacity(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    switch (field.kind) {
        .scalar => |scalar| try writeEncodeScalarFieldAssumeCapacity(file, field, scalar, writer, depth),
        .enumeration => try writeEncodeEnumFieldAssumeCapacity(file, field, writer, depth),
        .message => try writeEncodeMessageFieldAssumeCapacity(ctx, field, writer, depth),
        .group => try writeEncodeGroupFieldAssumeCapacity(ctx, field, writer, depth),
        .map => try writeEncodeMapFieldAssumeCapacity(ctx, field, writer, depth),
    }
}

pub fn writeEncodeFieldDeterministic(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    switch (field.kind) {
        .scalar => |scalar| try writeEncodeScalarField(file, field, scalar, writer, depth),
        .enumeration => try writeEncodeEnumField(file, field, writer, depth),
        .message => |type_name| if (codegenCanReferenceMessageWithContext(ctx, type_name)) {
            try writeEncodeMessageFieldDeterministic(ctx, field, type_name, writer, depth);
        } else try writeEncodeMessageField(ctx, field, writer, depth),
        .group => |type_name| if (codegenCanReferenceMessageWithContext(ctx, type_name)) {
            try writeEncodeGroupFieldDeterministic(ctx, field, type_name, writer, depth);
        } else try writeEncodeGroupField(ctx, field, writer, depth),
        .map => try writeEncodeMapFieldDeterministic(ctx, field, writer, depth),
    }
}

pub fn writeEncodeFieldDeterministicAssumeCapacity(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    switch (field.kind) {
        .scalar => |scalar| try writeEncodeScalarFieldAssumeCapacity(file, field, scalar, writer, depth),
        .enumeration => try writeEncodeEnumFieldAssumeCapacity(file, field, writer, depth),
        .message => |type_name| if (codegenCanReferenceMessageWithContext(ctx, type_name)) {
            try writeEncodeMessageFieldDeterministicAssumeCapacity(ctx, field, type_name, writer, depth);
        } else try writeEncodeMessageFieldAssumeCapacity(ctx, field, writer, depth),
        .group => |type_name| if (codegenCanReferenceMessageWithContext(ctx, type_name)) {
            try writeEncodeGroupFieldDeterministicAssumeCapacity(ctx, field, type_name, writer, depth);
        } else try writeEncodeGroupFieldAssumeCapacity(ctx, field, writer, depth),
        .map => try writeEncodeMapFieldDeterministicAssumeCapacity(ctx, field, writer, depth),
    }
}

pub fn writeEncodeScalarField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.cardinality == .repeated) {
        if (field.resolvedPacked(file)) {
            try writeEncodePackedScalarField(field, scalar, writer, depth);
        } else {
            try indent(writer, depth);
            if (scalar == .string and fieldUtf8Validation(file, field) == .verify) {
                try writer.writeAll("for (self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(") |item| { if (!pbz.validateUtf8(item)) return error.InvalidUtf8; ");
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
            try writeScalarSkipCondition("self.", field.name, scalar, writer);
        }
        if (scalar == .string and fieldUtf8Validation(file, field) == .verify) {
            try writer.writeAll("{ if (!pbz.validateUtf8(self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(")) return error.InvalidUtf8; ");
        }
        try writeScalarWriteCall(field.number, scalar, "self.", writer);
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(")");
        if (scalar == .string and fieldUtf8Validation(file, field) == .verify) try writer.writeAll("; }\n") else try writer.writeAll(";\n");
    }
}

pub fn writeEncodeEnumField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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

pub fn writeEncodeScalarFieldAssumeCapacity(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.cardinality == .repeated) {
        if (field.resolvedPacked(file)) {
            try writeEncodePackedScalarFieldAssumeCapacity(field, scalar, writer, depth);
        } else {
            try indent(writer, depth);
            if (scalar == .string and fieldUtf8Validation(file, field) == .verify) {
                try writer.writeAll("for (self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(") |item| { if (!pbz.validateUtf8(item)) return error.InvalidUtf8; ");
                try writeScalarWriteCallAssumeCapacity(field.number, scalar, "item", writer);
                try writer.writeAll("); }\n");
            } else {
                try writer.writeAll("for (self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(") |item| ");
                try writeScalarWriteCallAssumeCapacity(field.number, scalar, "item", writer);
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
            try writeScalarSkipCondition("self.", field.name, scalar, writer);
        }
        if (scalar == .string and fieldUtf8Validation(file, field) == .verify) {
            try writer.writeAll("{ if (!pbz.validateUtf8(self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(")) return error.InvalidUtf8; ");
        }
        try writeScalarWriteCallAssumeCapacity(field.number, scalar, "self.", writer);
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(")");
        if (scalar == .string and fieldUtf8Validation(file, field) == .verify) try writer.writeAll("; }\n") else try writer.writeAll(";\n");
    }
}

pub fn writeEncodeEnumFieldAssumeCapacity(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.cardinality == .repeated) {
        if (field.resolvedPacked(file)) {
            try writeEncodePackedEnumFieldAssumeCapacity(field, writer, depth);
        } else {
            try indent(writer, depth);
            try writer.writeAll("for (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.print(") |item| w.writeInt32AssumeCapacity({d}, item);\n", .{field.number});
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
        try writer.print("w.writeInt32AssumeCapacity({d}, self.", .{field.number});
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(");\n");
    }
}

pub fn writeEncodePackedScalarField(field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
    try writeEncodePackedPrefix(field, writer, depth);
    try indent(writer, depth + 1);
    if (fixedPackedScalarWidth(scalar)) |width| {
        try writer.writeAll("const packed_len = self.");
        try writeQuotedIdent(field.name, writer);
        try writer.print(".len * {d};\n", .{width});
    } else {
        try writer.writeAll("var packed_len: usize = 0;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("for (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(") |item| packed_len += ");
        try writePackedScalarSizeExpr(scalar, "item", writer);
        try writer.writeAll(";\n");
    }
    try writeEncodePackedLength(field, writer, depth);
    try indent(writer, depth + 1);
    if (fixedWidthViewScalarType(scalar)) |payload_type| {
        try writer.writeAll("try pbz.wire.writePackedFixedWidthPayload(");
        try writer.writeAll(payload_type);
        try writer.writeAll(", w, self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(");\n");
    } else if (scalar == .bool) {
        try writer.writeAll("try w.appendSlice(std.mem.sliceAsBytes(self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll("));\n");
    } else {
        try writer.writeAll("for (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(") |item| ");
        try writePackedScalarPayload(scalar, "item", "w", writer);
        try writer.writeAll(";\n");
    }
    try writeEncodePackedSuffix(field, writer, depth);
}

pub fn writeEncodePackedEnumField(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try writeEncodePackedPrefix(field, writer, depth);
    try indent(writer, depth + 1);
    try writer.writeAll("var packed_len: usize = 0;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("for (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(") |item| packed_len += pbz.wire.encodedVarintSize(@as(u64, @bitCast(@as(i64, item))));\n");
    try writeEncodePackedLength(field, writer, depth);
    try indent(writer, depth + 1);
    try writer.writeAll("for (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(") |item| ");
    try writePackedEnumPayload("item", "w", writer);
    try writer.writeAll(";\n");
    try writeEncodePackedSuffix(field, writer, depth);
}

pub fn writeEncodePackedScalarFieldAssumeCapacity(field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
    try writeEncodePackedPrefix(field, writer, depth);
    try indent(writer, depth + 1);
    if (fixedPackedScalarWidth(scalar)) |width| {
        try writer.writeAll("const packed_len = self.");
        try writeQuotedIdent(field.name, writer);
        try writer.print(".len * {d};\n", .{width});
    } else {
        try writer.writeAll("var packed_len: usize = 0;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("for (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(") |item| packed_len += ");
        try writePackedScalarSizeExpr(scalar, "item", writer);
        try writer.writeAll(";\n");
    }
    try writeEncodePackedLengthAssumeCapacity(field, writer, depth);
    try indent(writer, depth + 1);
    if (fixedWidthViewScalarType(scalar)) |payload_type| {
        try writer.writeAll("pbz.wire.writePackedFixedWidthPayloadAssumeCapacity(");
        try writer.writeAll(payload_type);
        try writer.writeAll(", w, self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(");\n");
    } else if (scalar == .bool) {
        try writer.writeAll("w.appendSliceAssumeCapacity(std.mem.sliceAsBytes(self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll("));\n");
    } else {
        try writer.writeAll("for (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(") |item| ");
        try writePackedScalarPayloadAssumeCapacity(scalar, "item", "w", writer);
        try writer.writeAll(";\n");
    }
    try writeEncodePackedSuffix(field, writer, depth);
}

pub fn writeEncodePackedEnumFieldAssumeCapacity(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try writeEncodePackedPrefix(field, writer, depth);
    try indent(writer, depth + 1);
    try writer.writeAll("var packed_len: usize = 0;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("for (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(") |item| packed_len += pbz.wire.encodedVarintSize(@as(u64, @bitCast(@as(i64, item))));\n");
    try writeEncodePackedLengthAssumeCapacity(field, writer, depth);
    try indent(writer, depth + 1);
    try writer.writeAll("for (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(") |item| ");
    try writePackedEnumPayloadAssumeCapacity("item", "w", writer);
    try writer.writeAll(";\n");
    try writeEncodePackedSuffix(field, writer, depth);
}

pub fn writeEncodePackedPrefix(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("if (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".len != 0) {\n");
}

pub fn writeEncodePackedLength(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth + 1);
    try writer.print("try w.writeTag({d}, .length_delimited);\n", .{field.number});
    try indent(writer, depth + 1);
    try writer.writeAll("try w.writeVarint(packed_len);\n");
}

pub fn writeEncodePackedLengthAssumeCapacity(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth + 1);
    try writer.print("w.writeTagAssumeCapacity({d}, .length_delimited);\n", .{field.number});
    try indent(writer, depth + 1);
    try writer.writeAll("w.writeVarintAssumeCapacity(packed_len);\n");
}

pub fn writeEncodePackedSuffix(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    _ = field;
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn scalarPayloadSizeIsConstant(scalar: schema.ScalarType) bool {
    return switch (scalar) {
        .double, .fixed64, .sfixed64, .float, .fixed32, .sfixed32 => true,
        else => false,
    };
}

pub fn fixedPackedScalarWidth(scalar: schema.ScalarType) ?usize {
    return switch (scalar) {
        .double, .fixed64, .sfixed64 => 8,
        .float, .fixed32, .sfixed32 => 4,
        .bool => 1,
        else => null,
    };
}

pub fn writePackedScalarSizeExpr(scalar: schema.ScalarType, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .double, .fixed64, .sfixed64 => try writer.writeAll("8"),
        .float, .fixed32, .sfixed32 => try writer.writeAll("4"),
        .int32 => try writer.print("pbz.wire.encodedVarintSize(@as(u64, @bitCast(@as(i64, {s}))))", .{value_expr}),
        .int64 => try writer.print("pbz.wire.encodedVarintSize(@as(u64, @bitCast({s})))", .{value_expr}),
        .uint32, .uint64 => try writer.print("pbz.wire.encodedVarintSize({s})", .{value_expr}),
        .sint32 => try writer.print("pbz.wire.encodedVarintSize(pbz.wire.zigZagEncode32({s}))", .{value_expr}),
        .sint64 => try writer.print("pbz.wire.encodedVarintSize(pbz.wire.zigZagEncode64({s}))", .{value_expr}),
        .bool => try writer.print("(if ({s}) @as(usize, 1) else @as(usize, 1))", .{value_expr}),
        .string, .bytes => try writer.writeAll("@compileError(\"non-packable scalar\")"),
    }
}

pub fn writePackedScalarPayload(scalar: schema.ScalarType, value_expr: []const u8, writer_name: []const u8, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .double => try writer.print("try {s}.writeRawLittle(u64, @bitCast({s}))", .{ writer_name, value_expr }),
        .float => try writer.print("try {s}.writeRawLittle(u32, @bitCast({s}))", .{ writer_name, value_expr }),
        .int32 => try writer.print("try {s}.writeVarint(@as(u64, @bitCast(@as(i64, {s}))))", .{ writer_name, value_expr }),
        .int64 => try writer.print("try {s}.writeVarint(@as(u64, @bitCast({s})))", .{ writer_name, value_expr }),
        .uint32 => try writer.print("try {s}.writeVarint({s})", .{ writer_name, value_expr }),
        .uint64 => try writer.print("try {s}.writeVarint({s})", .{ writer_name, value_expr }),
        .sint32 => try writer.print("try {s}.writeVarint(pbz.wire.zigZagEncode32({s}))", .{ writer_name, value_expr }),
        .sint64 => try writer.print("try {s}.writeVarint(pbz.wire.zigZagEncode64({s}))", .{ writer_name, value_expr }),
        .fixed32 => try writer.print("try {s}.writeRawLittle(u32, {s})", .{ writer_name, value_expr }),
        .fixed64 => try writer.print("try {s}.writeRawLittle(u64, {s})", .{ writer_name, value_expr }),
        .sfixed32 => try writer.print("try {s}.writeRawLittle(i32, {s})", .{ writer_name, value_expr }),
        .sfixed64 => try writer.print("try {s}.writeRawLittle(i64, {s})", .{ writer_name, value_expr }),
        .bool => try writer.print("try {s}.writeVarint(@as(u64, if ({s}) 1 else 0))", .{ writer_name, value_expr }),
        .string, .bytes => try writer.writeAll("@compileError(\"non-packable scalar\")"),
    }
}

pub fn writePackedEnumPayload(value_expr: []const u8, writer_name: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.print("try {s}.writeVarint(@as(u64, @bitCast(@as(i64, {s}))))", .{ writer_name, value_expr });
}

pub fn writePackedScalarPayloadAssumeCapacity(scalar: schema.ScalarType, value_expr: []const u8, writer_name: []const u8, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .double => try writer.print("{s}.writeRawLittleAssumeCapacity(u64, @bitCast({s}))", .{ writer_name, value_expr }),
        .float => try writer.print("{s}.writeRawLittleAssumeCapacity(u32, @bitCast({s}))", .{ writer_name, value_expr }),
        .int32 => try writer.print("{s}.writeVarintAssumeCapacity(@as(u64, @bitCast(@as(i64, {s}))))", .{ writer_name, value_expr }),
        .int64 => try writer.print("{s}.writeVarintAssumeCapacity(@as(u64, @bitCast({s})))", .{ writer_name, value_expr }),
        .uint32 => try writer.print("{s}.writeVarintAssumeCapacity({s})", .{ writer_name, value_expr }),
        .uint64 => try writer.print("{s}.writeVarintAssumeCapacity({s})", .{ writer_name, value_expr }),
        .sint32 => try writer.print("{s}.writeVarintAssumeCapacity(pbz.wire.zigZagEncode32({s}))", .{ writer_name, value_expr }),
        .sint64 => try writer.print("{s}.writeVarintAssumeCapacity(pbz.wire.zigZagEncode64({s}))", .{ writer_name, value_expr }),
        .fixed32 => try writer.print("{s}.writeRawLittleAssumeCapacity(u32, {s})", .{ writer_name, value_expr }),
        .fixed64 => try writer.print("{s}.writeRawLittleAssumeCapacity(u64, {s})", .{ writer_name, value_expr }),
        .sfixed32 => try writer.print("{s}.writeRawLittleAssumeCapacity(i32, {s})", .{ writer_name, value_expr }),
        .sfixed64 => try writer.print("{s}.writeRawLittleAssumeCapacity(i64, {s})", .{ writer_name, value_expr }),
        .bool => try writer.print("{s}.appendByteAssumeCapacity(if ({s}) 1 else 0)", .{ writer_name, value_expr }),
        .string, .bytes => try writer.writeAll("@compileError(\"non-packable scalar\")"),
    }
}

pub fn writePackedEnumPayloadAssumeCapacity(value_expr: []const u8, writer_name: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.print("{s}.writeVarintAssumeCapacity(@as(u64, @bitCast(@as(i64, {s}))))", .{ writer_name, value_expr });
}

pub fn writePackedKindPayload(kind: schema.FieldKind, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    switch (kind) {
        .scalar => |scalar| try writePackedScalarPayload(scalar, value_expr, "packed_writer", writer),
        .enumeration => try writePackedEnumPayload(value_expr, "packed_writer", writer),
        else => try writer.writeAll("@compileError(\"non-packable extension\")"),
    }
}

pub fn writeEncodeMessageField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        if (typedRepeatedMessageFieldWithContext(ctx, field)) |_| {
            try writer.writeAll("for (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.print(") |item| {{ const payload_len = item.encodedSize(); try w.writeTag({d}, .length_delimited); try w.writeVarint(payload_len); try item.writeTo(w); }}\n", .{field.number});
            return;
        }
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
        if (typedSingularMessageFieldWithContext(ctx, field)) |_| {
            try writer.writeAll("if (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(") |value| { const payload_len = value.encodedSize(); try w.writeTag(");
            try writer.print("{d}", .{field.number});
            try writer.writeAll(", .length_delimited); try w.writeVarint(payload_len); try value.writeTo(w); }\n");
            return;
        }
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

pub fn writeEncodeMessageFieldAssumeCapacity(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        if (typedRepeatedMessageFieldWithContext(ctx, field)) |_| {
            try writer.writeAll("for (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.print(") |item| {{ const payload_len = item.encodedSize(); w.writeTagAssumeCapacity({d}, .length_delimited); w.writeVarintAssumeCapacity(payload_len); try item.writeToAssumeCapacity(w); }}\n", .{field.number});
            return;
        }
        try writeEncodeMessageField(ctx, field, writer, depth);
    } else {
        try indent(writer, depth);
        if (typedSingularMessageFieldWithContext(ctx, field)) |_| {
            try writer.writeAll("if (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(") |value| { const payload_len = value.encodedSize(); ");
            if (fieldMessageEncoding(file, field) == .delimited) {
                try writer.print("w.writeTagAssumeCapacity({d}, .start_group); try value.writeToAssumeCapacity(w); w.writeTagAssumeCapacity({d}, .end_group);", .{ field.number, field.number });
            } else {
                try writer.print("w.writeTagAssumeCapacity({d}, .length_delimited); w.writeVarintAssumeCapacity(payload_len); try value.writeToAssumeCapacity(w);", .{field.number});
            }
            try writer.writeAll(" }\n");
            return;
        }
        try writeEncodeMessageField(ctx, field, writer, depth);
    }
}

pub fn writeEncodeMessageFieldDeterministic(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, type_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        if (typedRepeatedMessageFieldWithContext(ctx, field)) |_| {
            try writer.writeAll("for (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.print(") |item| {{ const payload_len = item.encodedSize(); try w.writeTag({d}, .length_delimited); try w.writeVarint(payload_len); try item.writeDeterministicTo(allocator, w); }}\n", .{field.number});
            return;
        }
        try writer.writeAll("for (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(") |item| { ");
        try writeEncodeMessagePayloadDeterministic(ctx, field.number, fieldMessageEncoding(file, field) == .delimited, type_name, "item", "w", writer);
        try writer.writeAll(" }\n");
    } else {
        try indent(writer, depth);
        if (typedSingularMessageFieldWithContext(ctx, field)) |_| {
            try writer.writeAll("if (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(") |item| { const payload_len = item.encodedSize(); ");
            if (fieldMessageEncoding(file, field) == .delimited) {
                try writer.print("try w.writeTag({d}, .start_group); try item.writeDeterministicTo(allocator, w); try w.writeTag({d}, .end_group);", .{ field.number, field.number });
            } else {
                try writer.print("try w.writeTag({d}, .length_delimited); try w.writeVarint(payload_len); try item.writeDeterministicTo(allocator, w);", .{field.number});
            }
            try writer.writeAll(" }\n");
            return;
        }
        try writer.writeAll("if (self.");
        if (hasPresence(file, field.*)) {
            try writePresenceIdent(field.name, writer);
            try writer.writeAll(") { ");
        } else {
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(".len != 0) { ");
        }
        try writer.writeAll("const item = self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll("; ");
        try writeEncodeMessagePayloadDeterministic(ctx, field.number, fieldMessageEncoding(file, field) == .delimited, type_name, "item", "w", writer);
        try writer.writeAll(" }\n");
    }
}

pub fn writeEncodeMessageFieldDeterministicAssumeCapacity(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, type_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        if (typedRepeatedMessageFieldWithContext(ctx, field)) |_| {
            try writer.writeAll("for (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.print(") |item| {{ const payload_len = item.encodedSize(); w.writeTagAssumeCapacity({d}, .length_delimited); w.writeVarintAssumeCapacity(payload_len); try item.writeDeterministicToAssumeCapacity(allocator, w); }}\n", .{field.number});
            return;
        }
        try writeEncodeMessageFieldDeterministic(ctx, field, type_name, writer, depth);
    } else {
        try indent(writer, depth);
        if (typedSingularMessageFieldWithContext(ctx, field)) |_| {
            try writer.writeAll("if (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(") |item| { const payload_len = item.encodedSize(); ");
            if (fieldMessageEncoding(file, field) == .delimited) {
                try writer.print("w.writeTagAssumeCapacity({d}, .start_group); try item.writeDeterministicToAssumeCapacity(allocator, w); w.writeTagAssumeCapacity({d}, .end_group);", .{ field.number, field.number });
            } else {
                try writer.print("w.writeTagAssumeCapacity({d}, .length_delimited); w.writeVarintAssumeCapacity(payload_len); try item.writeDeterministicToAssumeCapacity(allocator, w);", .{field.number});
            }
            try writer.writeAll(" }\n");
            return;
        }
        try writeEncodeMessageFieldDeterministic(ctx, field, type_name, writer, depth);
    }
}

pub fn writeEncodeGroupFieldDeterministic(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, type_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        if (typedRepeatedMessageFieldWithContext(ctx, field)) |_| {
            try writer.writeAll("for (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.print(") |item| {{ try w.writeTag({d}, .start_group); try item.writeDeterministicTo(allocator, w); try w.writeTag({d}, .end_group); }}\n", .{ field.number, field.number });
        } else {
            try writer.writeAll("for (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(") |item| { ");
            try writeEncodeMessagePayloadDeterministic(ctx, field.number, true, type_name, "item", "w", writer);
            try writer.writeAll(" }\n");
        }
    } else {
        try indent(writer, depth);
        if (typedSingularMessageFieldWithContext(ctx, field)) |_| {
            try writer.writeAll("if (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.print(") |item| {{ try w.writeTag({d}, .start_group); try item.writeDeterministicTo(allocator, w); try w.writeTag({d}, .end_group); }}\n", .{ field.number, field.number });
        } else {
            try writer.writeAll("if (self.");
            try writePresenceIdent(field.name, writer);
            try writer.writeAll(") { const item = self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll("; ");
            try writeEncodeMessagePayloadDeterministic(ctx, field.number, true, type_name, "item", "w", writer);
            try writer.writeAll(" }\n");
        }
    }
}

pub fn writeEncodeGroupFieldDeterministicAssumeCapacity(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, type_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        if (typedRepeatedMessageFieldWithContext(ctx, field)) |_| {
            try writer.writeAll("for (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.print(") |item| {{ w.writeTagAssumeCapacity({d}, .start_group); try item.writeDeterministicToAssumeCapacity(allocator, w); w.writeTagAssumeCapacity({d}, .end_group); }}\n", .{ field.number, field.number });
            return;
        }
        try writeEncodeGroupFieldDeterministic(ctx, field, type_name, writer, depth);
    } else {
        try indent(writer, depth);
        if (typedSingularMessageFieldWithContext(ctx, field)) |_| {
            try writer.writeAll("if (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.print(") |item| {{ w.writeTagAssumeCapacity({d}, .start_group); try item.writeDeterministicToAssumeCapacity(allocator, w); w.writeTagAssumeCapacity({d}, .end_group); }}\n", .{ field.number, field.number });
            return;
        }
        try writeEncodeGroupFieldDeterministic(ctx, field, type_name, writer, depth);
    }
}

pub fn writeEncodeGroupFieldAssumeCapacity(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        if (typedRepeatedMessageFieldWithContext(ctx, field)) |_| {
            try writer.writeAll("for (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.print(") |item| {{ w.writeTagAssumeCapacity({d}, .start_group); try item.writeToAssumeCapacity(w); w.writeTagAssumeCapacity({d}, .end_group); }}\n", .{ field.number, field.number });
            return;
        }
        try writeEncodeGroupField(ctx, field, writer, depth);
    } else {
        try indent(writer, depth);
        if (typedSingularMessageFieldWithContext(ctx, field)) |_| {
            try writer.writeAll("if (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.print(") |value| {{ w.writeTagAssumeCapacity({d}, .start_group); try value.writeToAssumeCapacity(w); w.writeTagAssumeCapacity({d}, .end_group); }}\n", .{ field.number, field.number });
            return;
        }
        try writeEncodeGroupField(ctx, field, writer, depth);
    }
}

pub fn writeEncodeMessagePayloadDeterministic(ctx: *const CodegenContext, number: u29, delimited: bool, type_name: []const u8, payload_expr: []const u8, writer_name: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("var _pbz_nested = try ");
    try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    try writer.writeAll(".decode(allocator, ");
    try writer.writeAll(payload_expr);
    try writer.writeAll("); defer _pbz_nested.deinit(allocator); const payload = try _pbz_nested.encodeDeterministic(allocator); defer allocator.free(payload); ");
    if (delimited) {
        try writer.print("try {s}.writeTag({d}, .start_group); try {s}.appendSlice(payload); try {s}.writeTag({d}, .end_group);", .{ writer_name, number, writer_name, writer_name, number });
    } else {
        try writer.print("try {s}.writeMessage({d}, payload);", .{ writer_name, number });
    }
}

pub fn writeEncodeGroupField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        if (typedRepeatedMessageFieldWithContext(ctx, field)) |_| {
            try writer.writeAll("for (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.print(") |item| {{ try w.writeTag({d}, .start_group); try item.writeTo(w); try w.writeTag({d}, .end_group); }}\n", .{ field.number, field.number });
        } else {
            try writer.writeAll("for (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.print(") |item| {{ try w.writeTag({d}, .start_group); try w.appendSlice(item); try w.writeTag({d}, .end_group); }}\n", .{ field.number, field.number });
        }
    } else {
        try indent(writer, depth);
        if (typedSingularMessageFieldWithContext(ctx, field)) |_| {
            try writer.writeAll("if (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.print(") |value| {{ try w.writeTag({d}, .start_group); try value.writeTo(w); try w.writeTag({d}, .end_group); }}\n", .{ field.number, field.number });
        } else {
            try writer.writeAll("if (self.");
            try writePresenceIdent(field.name, writer);
            try writer.print(") {{ try w.writeTag({d}, .start_group); try w.appendSlice(self.", .{field.number});
            try writeQuotedIdent(field.name, writer);
            try writer.print("); try w.writeTag({d}, .end_group); }}\n", .{field.number});
        }
    }
}

pub fn writeEncodeMapField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try writeEncodeMapEntries(ctx, field, "w", false, writer, depth);
}

pub fn writeEncodeMapFieldAssumeCapacity(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try writeEncodeMapEntries(ctx, field, "w", true, writer, depth);
}

pub fn writeEncodeMapEntries(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer_name: []const u8, assume_capacity: bool, writer: *std.Io.Writer, depth: usize) Error!void {
    const map_type = switch (field.kind) {
        .map => |map| map,
        else => return,
    };
    try indent(writer, depth);
    try writer.writeAll("{ var map_it = self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".iterator(); while (map_it.next()) |map_entry| {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const entry = ");
    try writeQuotedIdentWithSuffix(field.name, "Entry", writer);
    try writer.writeAll("{ .key = map_entry.key_ptr.*, .value = map_entry.value_ptr.* };\n");
    try writeEncodeMapEntryBody(ctx, field, map_type, writer_name, assume_capacity, writer, depth + 1);
    try indent(writer, depth);
    try writer.writeAll("} }\n");
}

pub fn writeEncodeMapFieldDeterministic(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try writeEncodeMapFieldDeterministicCommon(ctx, field, "w", false, writer, depth);
}

pub fn writeEncodeMapFieldDeterministicAssumeCapacity(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try writeEncodeMapFieldDeterministicCommon(ctx, field, "w", true, writer, depth);
}

pub fn writeEncodeMapFieldDeterministicCommon(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer_name: []const u8, assume_capacity: bool, writer: *std.Io.Writer, depth: usize) Error!void {
    const map_type = switch (field.kind) {
        .map => |map| map,
        else => return,
    };
    try indent(writer, depth);
    try writer.writeAll("if (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".count() != 0) {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const insertion_sort_limit: usize = 32;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const stack_entry_count: usize = @max(insertion_sort_limit, (32 * 1024) / @max(@sizeOf(");
    try writeQuotedIdentWithSuffix(field.name, "Entry", writer);
    try writer.writeAll("), 1));\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var stack_entries: [stack_entry_count]");
    try writeQuotedIdentWithSuffix(field.name, "Entry", writer);
    try writer.writeAll(" = undefined;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const use_stack_entries = self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".count() <= stack_entries.len;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const entries = if (use_stack_entries) blk: { var map_it = self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".iterator(); var i: usize = 0; while (map_it.next()) |entry| : (i += 1) stack_entries[i] = .{ .key = entry.key_ptr.*, .value = entry.value_ptr.* }; break :blk stack_entries[0..self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".count()]; } else blk: { const owned = try allocator.alloc(");
    try writeQuotedIdentWithSuffix(field.name, "Entry", writer);
    try writer.writeAll(", self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".count()); var map_it = self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".iterator(); var i: usize = 0; while (map_it.next()) |entry| : (i += 1) owned[i] = .{ .key = entry.key_ptr.*, .value = entry.value_ptr.* }; break :blk owned; };\n");
    try indent(writer, depth + 1);
    try writer.writeAll("defer if (!use_stack_entries) allocator.free(entries);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (entries.len <= insertion_sort_limit) {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("var sort_i: usize = 1;\n");
    try indent(writer, depth + 2);
    try writer.writeAll("while (sort_i < entries.len) : (sort_i += 1) {\n");
    try indent(writer, depth + 3);
    try writer.writeAll("const item = entries[sort_i];\n");
    try indent(writer, depth + 3);
    try writer.writeAll("var sort_j = sort_i;\n");
    try indent(writer, depth + 3);
    try writer.writeAll("while (sort_j > 0 and ");
    try writeMapKeyLessExpr(map_type.key, "item.key", "entries[sort_j - 1].key", writer);
    try writer.writeAll(") : (sort_j -= 1) entries[sort_j] = entries[sort_j - 1];\n");
    try indent(writer, depth + 3);
    try writer.writeAll("entries[sort_j] = item;\n");
    try indent(writer, depth + 2);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("} else {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("const entries_already_sorted = sorted: {\n");
    try indent(writer, depth + 3);
    try writer.writeAll("var check_i: usize = 1;\n");
    try indent(writer, depth + 3);
    try writer.writeAll("while (check_i < entries.len) : (check_i += 1) {\n");
    try indent(writer, depth + 4);
    try writer.writeAll("if (");
    try writeMapKeyLessExpr(map_type.key, "entries[check_i].key", "entries[check_i - 1].key", writer);
    try writer.writeAll(") break :sorted false;\n");
    try indent(writer, depth + 3);
    try writer.writeAll("}\n");
    try indent(writer, depth + 3);
    try writer.writeAll("break :sorted true;\n");
    try indent(writer, depth + 2);
    try writer.writeAll("};\n");
    try indent(writer, depth + 2);
    try writer.writeAll("if (!entries_already_sorted) {\n");
    try indent(writer, depth + 3);
    // Keep tiny maps on an unrolled allocation-free insertion sort, but sort
    // larger stack-backed maps with the std stable sort. The stack buffer only
    // avoids allocator traffic; it should not force O(n^2) behavior for the
    // large deterministic-map benchmark.
    try writer.writeAll("std.mem.sort(");
    try writeQuotedIdentWithSuffix(field.name, "Entry", writer);
    try writer.writeAll(", entries, {}, struct { fn lessThan(_: void, a: ");
    try writeQuotedIdentWithSuffix(field.name, "Entry", writer);
    try writer.writeAll(", b: ");
    try writeQuotedIdentWithSuffix(field.name, "Entry", writer);
    try writer.writeAll(") bool { return ");
    try writeMapKeyLessExpr(map_type.key, "a.key", "b.key", writer);
    try writer.writeAll("; } }.lessThan);\n");
    try indent(writer, depth + 2);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("for (entries) |entry| {\n");
    try writeEncodeMapEntryBody(ctx, field, map_type, writer_name, assume_capacity, writer, depth + 2);
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeEncodeMapEntryBody(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, map_type: schema.MapType, writer_name: []const u8, assume_capacity: bool, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    try writeMapEntryEncodeUtf8Check(file, field, "entry.key", .{ .scalar = map_type.key }, writer, depth);
    try writeMapEntryEncodeUtf8Check(file, field, "entry.value", map_type.value.*, writer, depth);
    try indent(writer, depth);
    try writer.writeAll("const entry_len = ");
    try writeMapEntryFieldSizeExpr(1, .{ .scalar = map_type.key }, "entry.key", writer);
    try writer.writeAll(" + ");
    try writeMapEntryValueFieldSizeExpr(ctx, field, "entry.value", writer);
    try writer.writeAll(";\n");
    try indent(writer, depth);
    if (assume_capacity) {
        try writer.print("{s}.writeTagAssumeCapacity({d}, .length_delimited);\n", .{ writer_name, field.number });
        try indent(writer, depth);
        try writer.print("{s}.writeVarintAssumeCapacity(entry_len);\n", .{writer_name});
        try indent(writer, depth);
        try writeKindWriteCallAssumeCapacity(1, .{ .scalar = map_type.key }, "entry.key", writer_name, writer);
        try writer.writeAll(";\n");
    } else {
        try writer.print("try {s}.writeTag({d}, .length_delimited);\n", .{ writer_name, field.number });
        try indent(writer, depth);
        try writer.print("try {s}.writeVarint(entry_len);\n", .{writer_name});
        try indent(writer, depth);
        try writeKindWriteCall(1, .{ .scalar = map_type.key }, "entry.key", writer_name, writer);
        try writer.writeAll(");\n");
    }
    try indent(writer, depth);
    try writeMapEntryValueWriteCall(ctx, field, "entry.value", writer_name, assume_capacity, writer);
}

pub fn writeMapEntryEncodeUtf8Check(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, value_expr: []const u8, kind: schema.FieldKind, writer: *std.Io.Writer, depth: usize) Error!void {
    if (kind == .scalar and kind.scalar == .string and fieldUtf8Validation(file, field) == .verify) {
        try indent(writer, depth);
        try writer.print("if (!pbz.validateUtf8({s})) return error.InvalidUtf8;\n", .{value_expr});
    }
}

pub fn writeMapKeyLessExpr(scalar: schema.ScalarType, a: []const u8, b: []const u8, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .string => try writer.print("pbz.wire.bytesLessThan({s}, {s})", .{ a, b }),
        .bool => try writer.print("!{s} and {s}", .{ a, b }),
        .int32, .int64, .uint32, .uint64, .sint32, .sint64, .fixed32, .fixed64, .sfixed32, .sfixed64 => try writer.print("{s} < {s}", .{ a, b }),
        .double, .float, .bytes => try writer.writeAll("false"),
    }
}

pub fn writeMapEntryValueFieldSizeExpr(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    const map_type = field.kind.map;
    if (typedMapMessageValueWithContext(ctx, field)) |_| {
        try writer.print("blk: {{ const value_len = {s}.encodedSize(); break :blk 1 + pbz.wire.encodedVarintSize(value_len) + value_len; }}", .{value_expr});
    } else {
        try writeMapEntryFieldSizeExpr(2, map_type.value.*, value_expr, writer);
    }
}

pub fn writeMapEntryValueWriteCall(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, value_expr: []const u8, writer_name: []const u8, assume_capacity: bool, writer: *std.Io.Writer) Error!void {
    const map_type = field.kind.map;
    if (typedMapMessageValueWithContext(ctx, field)) |_| {
        if (assume_capacity) {
            try writer.print("{{ const value_len = {s}.encodedSize(); {s}.writeTagAssumeCapacity(2, .length_delimited); {s}.writeVarintAssumeCapacity(value_len); try {s}.writeToAssumeCapacity({s}); }}\n", .{ value_expr, writer_name, writer_name, value_expr, writer_name });
        } else {
            try writer.print("{{ const value_len = {s}.encodedSize(); try {s}.writeTag(2, .length_delimited); try {s}.writeVarint(value_len); try {s}.writeTo({s}); }}\n", .{ value_expr, writer_name, writer_name, value_expr, writer_name });
        }
    } else {
        if (assume_capacity) {
            try writeKindWriteCallAssumeCapacity(2, map_type.value.*, value_expr, writer_name, writer);
            try writer.writeAll(";\n");
        } else {
            try writeKindWriteCall(2, map_type.value.*, value_expr, writer_name, writer);
            try writer.writeAll(");\n");
        }
    }
}

pub fn writeMapEntryFieldSizeExpr(number: u29, kind: schema.FieldKind, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    const tag_size = wire.tagSize(number, kind.wireType()) catch unreachable;
    try writer.print("{d} + ", .{tag_size});
    if (kind == .scalar and kind.scalar == .bool) {
        // Map-entry encoded-size loops bind both key and value once so the
        // generated shape remains uniform across scalar key/value kinds.  Bool
        // payload size is always one byte, but mention the expression so Zig's
        // unused-local analysis does not reject `map<bool, ...>` entries.
        return try writer.print("(if ({s}) @as(usize, 1) else @as(usize, 1))", .{value_expr});
    }
    try writeKindPayloadSizeExpr(kind, value_expr, writer);
}

pub fn writeKindPayloadSizeExpr(kind: schema.FieldKind, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    switch (kind) {
        .scalar => |scalar| try writeScalarPayloadSizeExpr(scalar, value_expr, writer),
        .enumeration => try writer.print("pbz.wire.encodedVarintSize(@as(u64, @bitCast(@as(i64, {s}))))", .{value_expr}),
        .message => try writer.print("pbz.wire.encodedVarintSize({s}.len) + {s}.len", .{ value_expr, value_expr }),
        else => try writer.writeAll("@compileError(\"unsupported map field kind\")"),
    }
}

pub fn writeScalarPayloadSizeExpr(scalar: schema.ScalarType, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .double, .fixed64, .sfixed64 => try writer.writeAll("8"),
        .float, .fixed32, .sfixed32 => try writer.writeAll("4"),
        .int32 => try writer.print("pbz.wire.encodedVarintSize(@as(u64, @bitCast(@as(i64, {s}))))", .{value_expr}),
        .int64 => try writer.print("pbz.wire.encodedVarintSize(@as(u64, @bitCast({s})))", .{value_expr}),
        .uint32, .uint64 => try writer.print("pbz.wire.encodedVarintSize({s})", .{value_expr}),
        .sint32 => try writer.print("pbz.wire.encodedVarintSize(pbz.wire.zigZagEncode32({s}))", .{value_expr}),
        .sint64 => try writer.print("pbz.wire.encodedVarintSize(pbz.wire.zigZagEncode64({s}))", .{value_expr}),
        .bool => try writer.print("(if ({s}) @as(usize, 1) else @as(usize, 1))", .{value_expr}),
        .string, .bytes => try writer.print("pbz.wire.encodedVarintSize({s}.len) + {s}.len", .{ value_expr, value_expr }),
    }
}

pub fn writeKindWriteCall(number: u29, kind: schema.FieldKind, value_expr: []const u8, writer_name: []const u8, writer: *std.Io.Writer) Error!void {
    switch (kind) {
        .scalar => |scalar| try writer.print("try {s}.{s}({d}, {s}", .{ writer_name, scalarWriterName(scalar), number, value_expr }),
        .enumeration => try writer.print("try {s}.writeInt32({d}, {s}", .{ writer_name, number, value_expr }),
        .message => try writer.print("try {s}.writeMessage({d}, {s}", .{ writer_name, number, value_expr }),
        else => try writer.writeAll("@compileError(\"unsupported map field kind\")"),
    }
}

pub fn writeKindWriteCallAssumeCapacity(number: u29, kind: schema.FieldKind, value_expr: []const u8, writer_name: []const u8, writer: *std.Io.Writer) Error!void {
    switch (kind) {
        .scalar => |scalar| try writer.print("{s}.{s}AssumeCapacity({d}, {s})", .{ writer_name, scalarWriterName(scalar), number, value_expr }),
        .enumeration => try writer.print("{s}.writeInt32AssumeCapacity({d}, {s})", .{ writer_name, number, value_expr }),
        .message => try writer.print("{s}.writeMessageAssumeCapacity({d}, {s})", .{ writer_name, number, value_expr }),
        else => try writer.writeAll("@compileError(\"unsupported map field kind\")"),
    }
}

pub fn writeScalarWriteCall(number: u29, scalar: schema.ScalarType, prefix: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.print("try w.{s}({d}, {s}", .{ scalarWriterName(scalar), number, prefix });
}

pub fn writeScalarWriteCallAssumeCapacity(number: u29, scalar: schema.ScalarType, prefix: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.print("w.{s}AssumeCapacity({d}, {s}", .{ scalarWriterName(scalar), number, prefix });
}

/// Emit a default-skip condition for implicit-presence scalar fields. Floats
/// compare their bit pattern so `-0.0` is serialized instead of being treated
/// as the zero default.
pub fn writeScalarSkipCondition(receiver: []const u8, field_name: []const u8, scalar: schema.ScalarType, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .string, .bytes => {
            try writer.writeAll("if (");
            try writer.writeAll(receiver);
            try writeQuotedIdent(field_name, writer);
            try writer.writeAll(".len != 0) ");
        },
        .bool => {
            try writer.writeAll("if (");
            try writer.writeAll(receiver);
            try writeQuotedIdent(field_name, writer);
            try writer.writeAll(") ");
        },
        .float => {
            try writer.writeAll("if (@as(u32, @bitCast(");
            try writer.writeAll(receiver);
            try writeQuotedIdent(field_name, writer);
            try writer.writeAll(")) != 0) ");
        },
        .double => {
            try writer.writeAll("if (@as(u64, @bitCast(");
            try writer.writeAll(receiver);
            try writeQuotedIdent(field_name, writer);
            try writer.writeAll(")) != 0) ");
        },
        else => {
            try writer.writeAll("if (");
            try writer.writeAll(receiver);
            try writeQuotedIdent(field_name, writer);
            try writer.writeAll(" != 0) ");
        },
    }
}

pub fn writeScalarSkipConditionWithOptions(receiver: []const u8, field_name: []const u8, scalar: schema.ScalarType, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .string, .bytes => {
            try writer.writeAll("if (");
            try writer.writeAll(receiver);
            try writeQuotedIdent(field_name, writer);
            try writer.writeAll(".len != 0 or options.always_print_primitive_fields) ");
        },
        .bool => {
            try writer.writeAll("if (");
            try writer.writeAll(receiver);
            try writeQuotedIdent(field_name, writer);
            try writer.writeAll(" or options.always_print_primitive_fields) ");
        },
        .float => {
            try writer.writeAll("if (@as(u32, @bitCast(");
            try writer.writeAll(receiver);
            try writeQuotedIdent(field_name, writer);
            try writer.writeAll(")) != 0 or options.always_print_primitive_fields) ");
        },
        .double => {
            try writer.writeAll("if (@as(u64, @bitCast(");
            try writer.writeAll(receiver);
            try writeQuotedIdent(field_name, writer);
            try writer.writeAll(")) != 0 or options.always_print_primitive_fields) ");
        },
        else => {
            try writer.writeAll("if (");
            try writer.writeAll(receiver);
            try writeQuotedIdent(field_name, writer);
            try writer.writeAll(" != 0 or options.always_print_primitive_fields) ");
        },
    }
}

pub fn shouldSkipDefault(scalar: schema.ScalarType) bool {
    _ = scalar;
    return true;
}

pub fn scalarWriterName(scalar: schema.ScalarType) []const u8 {
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

pub fn writeOneofValueEncode(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    const file = ctx.file;
    switch (field.kind) {
        .scalar => |scalar| {
            if (scalar == .string and fieldUtf8Validation(file, field) == .verify) {
                try writer.writeAll("{ if (!pbz.validateUtf8(");
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
            if (typedOneofMessageFieldWithContext(ctx, field)) |_| {
                try writer.print("{{ const payload_len = {s}.encodedSize(); try w.writeTag({d}, .length_delimited); try w.writeVarint(payload_len); try {s}.writeTo(w); }}", .{ value_expr, field.number, value_expr });
            } else if (fieldMessageEncoding(file, field) == .delimited) {
                try writer.print("{{ try w.writeTag({d}, .start_group); try w.appendSlice({s}); try w.writeTag({d}, .end_group); }}", .{ field.number, value_expr, field.number });
            } else {
                try writer.print("try w.writeMessage({d}, {s})", .{ field.number, value_expr });
            }
        },
        .group => {
            if (typedOneofMessageFieldWithContext(ctx, field)) |_| {
                try writer.print("{{ try w.writeTag({d}, .start_group); try {s}.writeTo(w); try w.writeTag({d}, .end_group); }}", .{ field.number, value_expr, field.number });
            } else {
                try writer.print("{{ try w.writeTag({d}, .start_group); try w.appendSlice({s}); try w.writeTag({d}, .end_group); }}", .{ field.number, value_expr, field.number });
            }
        },
        else => try writer.writeAll("@compileError(\"unsupported oneof field\")"),
    }
}

pub fn writeOneofValueEncodeAssumeCapacity(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    const file = ctx.file;
    switch (field.kind) {
        .scalar => |scalar| {
            if (scalar == .string and fieldUtf8Validation(file, field) == .verify) {
                try writer.writeAll("{ if (!pbz.validateUtf8(");
                try writer.writeAll(value_expr);
                try writer.writeAll(")) return error.InvalidUtf8; ");
                try writeScalarWriteCallAssumeCapacity(field.number, scalar, value_expr, writer);
                try writer.writeAll("); }");
            } else {
                try writeScalarWriteCallAssumeCapacity(field.number, scalar, value_expr, writer);
                try writer.writeAll(")");
            }
        },
        .enumeration => try writer.print("w.writeInt32AssumeCapacity({d}, {s})", .{ field.number, value_expr }),
        .message => {
            if (typedOneofMessageFieldWithContext(ctx, field)) |_| {
                try writer.print("{{ const payload_len = {s}.encodedSize(); w.writeTagAssumeCapacity({d}, .length_delimited); w.writeVarintAssumeCapacity(payload_len); try {s}.writeToAssumeCapacity(w); }}", .{ value_expr, field.number, value_expr });
            } else if (fieldMessageEncoding(file, field) == .delimited) {
                try writer.print("{{ w.writeTagAssumeCapacity({d}, .start_group); w.appendSliceAssumeCapacity({s}); w.writeTagAssumeCapacity({d}, .end_group); }}", .{ field.number, value_expr, field.number });
            } else {
                try writer.print("w.writeMessageAssumeCapacity({d}, {s})", .{ field.number, value_expr });
            }
        },
        .group => {
            if (typedOneofMessageFieldWithContext(ctx, field)) |_| {
                try writer.print("{{ w.writeTagAssumeCapacity({d}, .start_group); try {s}.writeToAssumeCapacity(w); w.writeTagAssumeCapacity({d}, .end_group); }}", .{ field.number, value_expr, field.number });
            } else {
                try writer.print("{{ w.writeTagAssumeCapacity({d}, .start_group); w.appendSliceAssumeCapacity({s}); w.writeTagAssumeCapacity({d}, .end_group); }}", .{ field.number, value_expr, field.number });
            }
        },
        else => try writer.writeAll("@compileError(\"unsupported oneof field\")"),
    }
}
