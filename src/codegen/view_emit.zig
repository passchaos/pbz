const schema = @import("../schema.zig");
const std = @import("std");
const wire = @import("../wire.zig");
const cg = @import("../codegen.zig");
const CodegenContext = cg.CodegenContext;
const Error = cg.Error;
const indent = cg.indent;
const writeQuotedIdentWithSuffix = cg.writeQuotedIdentWithSuffix;
const writeZigStringLiteral = cg.writeZigStringLiteral;
const messageFullNameForCodegen = cg.emit_helpers.messageFullNameForCodegen;

pub fn writeUnknownFieldMethods(writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn unknownFieldCount(self: @This()) usize {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return self._unknown_fields.len;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn unknownFields(self: @This()) []const []const u8 {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return self._unknown_fields;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn unknownFieldCountByNumber(self: @This(), number: pbz.FieldNumber) !usize {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return pbz.wire.rawFieldCountByNumberAssumeValid(self._unknown_fields, number);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn hasUnknownFieldNumber(self: @This(), number: pbz.FieldNumber) !bool {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return pbz.wire.rawFieldHasNumberAssumeValid(self._unknown_fields, number);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn unknownFieldNumbersAlloc(self: @This(), allocator: std.mem.Allocator) ![]pbz.FieldNumber {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try pbz.wire.rawFieldNumbersAlloc(allocator, self._unknown_fields);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn unknownFieldNumberRunsAlloc(self: @This(), allocator: std.mem.Allocator) ![]pbz.wire.RawFieldNumberRun {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try pbz.wire.rawFieldNumberRunsAlloc(allocator, self._unknown_fields);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn unknownFieldsByNumberAlloc(self: @This(), allocator: std.mem.Allocator, number: pbz.FieldNumber) ![]const []const u8 {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try pbz.wire.rawFieldsByNumberAllocAssumeValid(allocator, self._unknown_fields, number);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn appendUnknownRaw(self: *@This(), allocator: std.mem.Allocator, raw: []const u8) !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try pbz.wire.appendRawFieldClone(allocator, &self._unknown_fields, raw);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn clearUnknownFieldsByNumber(self: *@This(), allocator: std.mem.Allocator, number: pbz.FieldNumber) !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try pbz.wire.clearRawFieldsByNumber(allocator, &self._unknown_fields, number);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn clearUnknownFields(self: *@This(), allocator: std.mem.Allocator) void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pbz.wire.clearRawFields(allocator, &self._unknown_fields);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeBorrowedViewMethods(file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    for (message.fields.items) |*field| {
        if (field.oneof_name != null) continue;
        if (field.kind != .scalar) continue;
        if (field.kind.scalar == .string or field.kind.scalar == .bytes) {
            try writeLengthDelimitedBorrowedSlicesMethod(field, writer, depth);
            continue;
        }
        if (field.cardinality != .repeated) continue;
        if (!field.resolvedPacked(file)) continue;
        if (field.kind.scalar == .bool) {
            try writePackedBoolSlicesMethod(field, writer, depth);
            continue;
        }
        if (packedVarintIteratorType(field.kind.scalar)) |iterator_type| {
            try writePackedVarintIteratorMethod(field, iterator_type, writer, depth);
            continue;
        }
        if (fixedWidthViewScalarType(field.kind.scalar) == null) continue;
        const view_type = fixedWidthViewScalarType(field.kind.scalar).?;
        try indent(writer, depth);
        try writer.writeAll("pub fn ");
        try writeQuotedIdentWithSuffix(field.name, "PackedFixedView", writer);
        try writer.writeAll("(bytes: []const u8) !?[]align(1) const ");
        try writer.writeAll(view_type);
        try writer.writeAll(" {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return try pbz.wire.packedFixedWidthFieldView(");
        try writer.writeAll(view_type);
        try writer.print(", bytes, {d});\n", .{field.number});
        try indent(writer, depth);
        try writer.writeAll("}\n\n");
        try indent(writer, depth);
        try writer.writeAll("pub fn ");
        try writeQuotedIdentWithSuffix(field.name, "PackedFixedSlices", writer);
        try writer.writeAll("(header: *[20]u8, values: []const ");
        try writer.writeAll(view_type);
        try writer.writeAll(") !pbz.wire.BorrowedFieldSlices {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return try pbz.wire.packedFixedWidthFieldSlices(");
        try writer.writeAll(view_type);
        try writer.print(", header, {d}, values);\n", .{field.number});
        try indent(writer, depth);
        try writer.writeAll("}\n\n");
        if (field.kind.scalar == .fixed32) {
            try indent(writer, depth);
            try writer.writeAll("pub fn ");
            try writeQuotedIdentWithSuffix(field.name, "PackedFixed32View", writer);
            try writer.writeAll("(bytes: []const u8) !?[]align(1) const u32 {\n");
            try indent(writer, depth + 1);
            try writer.writeAll("return try ");
            try writeQuotedIdentWithSuffix(field.name, "PackedFixedView", writer);
            try writer.writeAll("(bytes);\n");
            try indent(writer, depth);
            try writer.writeAll("}\n\n");
            try indent(writer, depth);
            try writer.writeAll("pub fn ");
            try writeQuotedIdentWithSuffix(field.name, "PackedFixed32Slices", writer);
            try writer.writeAll("(header: *[20]u8, values: []const u32) !pbz.wire.BorrowedFieldSlices {\n");
            try indent(writer, depth + 1);
            try writer.writeAll("return try ");
            try writeQuotedIdentWithSuffix(field.name, "PackedFixedSlices", writer);
            try writer.writeAll("(header, values);\n");
            try indent(writer, depth);
            try writer.writeAll("}\n\n");
        }
    }
}

pub fn writePackedBoolSlicesMethod(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedIdentWithSuffix(field.name, "PackedBoolSlices", writer);
    try writer.writeAll("(header: *[20]u8, values: []const bool) !pbz.wire.BorrowedFieldSlices {\n");
    try indent(writer, depth + 1);
    try writer.print("return try pbz.wire.packedBoolFieldSlices(header, {d}, values);\n", .{field.number});
    try indent(writer, depth);
    try writer.writeAll("}\n\n");
}

pub fn writePackedVarintIteratorMethod(field: *const schema.FieldDescriptor, iterator_type: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedIdentWithSuffix(field.name, "PackedIterator", writer);
    try writer.writeAll("(bytes: []const u8) !?");
    try writer.writeAll(iterator_type);
    try writer.writeAll(" {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try pbz.wire.");
    try writer.writeAll(packedVarintIteratorFunction(field.kind.scalar).?);
    try writer.print("(bytes, {d});\n", .{field.number});
    try indent(writer, depth);
    try writer.writeAll("}\n\n");
}

pub fn packedVarintIteratorType(scalar: schema.ScalarType) ?[]const u8 {
    return switch (scalar) {
        .uint64 => "pbz.wire.PackedUInt64Iterator",
        .int32 => "pbz.wire.PackedInt32Iterator",
        .uint32 => "pbz.wire.PackedUInt32Iterator",
        .int64 => "pbz.wire.PackedInt64Iterator",
        .sint32 => "pbz.wire.PackedSInt32Iterator",
        .sint64 => "pbz.wire.PackedSInt64Iterator",
        else => null,
    };
}

pub fn packedVarintIteratorFunction(scalar: schema.ScalarType) ?[]const u8 {
    return switch (scalar) {
        .uint64 => "packedUInt64FieldIterator",
        .int32 => "packedInt32FieldIterator",
        .uint32 => "packedUInt32FieldIterator",
        .int64 => "packedInt64FieldIterator",
        .sint32 => "packedSInt32FieldIterator",
        .sint64 => "packedSInt64FieldIterator",
        else => null,
    };
}

pub fn writeLengthDelimitedBorrowedSlicesMethod(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedIdentWithSuffix(field.name, "FieldView", writer);
    try writer.writeAll("(bytes: []const u8) !?[]const u8 {\n");
    try indent(writer, depth + 1);
    try writer.print("return try pbz.wire.bytesFieldView(bytes, {d});\n", .{field.number});
    try indent(writer, depth);
    try writer.writeAll("}\n\n");
    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedIdentWithSuffix(field.name, "FieldSlices", writer);
    try writer.writeAll("(header: *[20]u8, value: []const u8) !pbz.wire.BorrowedFieldSlices {\n");
    try indent(writer, depth + 1);
    try writer.print("return pbz.wire.lengthDelimitedFieldSlicesAssumeValid(header, {d}, value);\n", .{field.number});
    try indent(writer, depth);
    try writer.writeAll("}\n\n");
    if (field.kind.scalar == .bytes) {
        try indent(writer, depth);
        try writer.writeAll("pub fn ");
        try writeQuotedIdentWithSuffix(field.name, "BytesView", writer);
        try writer.writeAll("(bytes: []const u8) !?[]const u8 {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return try ");
        try writeQuotedIdentWithSuffix(field.name, "FieldView", writer);
        try writer.writeAll("(bytes);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n\n");
        try indent(writer, depth);
        try writer.writeAll("pub fn ");
        try writeQuotedIdentWithSuffix(field.name, "BytesSlices", writer);
        try writer.writeAll("(header: *[20]u8, value: []const u8) !pbz.wire.BorrowedFieldSlices {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return try ");
        try writeQuotedIdentWithSuffix(field.name, "FieldSlices", writer);
        try writer.writeAll("(header, value);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n\n");
    } else if (field.kind.scalar == .string) {
        try indent(writer, depth);
        try writer.writeAll("pub fn ");
        try writeQuotedIdentWithSuffix(field.name, "StringView", writer);
        try writer.writeAll("(bytes: []const u8) !?[]const u8 {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return try ");
        try writeQuotedIdentWithSuffix(field.name, "FieldView", writer);
        try writer.writeAll("(bytes);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n\n");
        try indent(writer, depth);
        try writer.writeAll("pub fn ");
        try writeQuotedIdentWithSuffix(field.name, "StringSlices", writer);
        try writer.writeAll("(header: *[20]u8, value: []const u8) !pbz.wire.BorrowedFieldSlices {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return try ");
        try writeQuotedIdentWithSuffix(field.name, "FieldSlices", writer);
        try writer.writeAll("(header, value);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n\n");
    }
}

pub fn fixedWidthViewScalarType(scalar: schema.ScalarType) ?[]const u8 {
    return switch (scalar) {
        .double => "f64",
        .float => "f32",
        .fixed32 => "u32",
        .fixed64 => "u64",
        .sfixed32 => "i32",
        .sfixed64 => "i64",
        else => null,
    };
}

pub fn writeMessageDescriptorLookup(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (!ctx.emit_descriptor) return;
    var arena = std.heap.ArenaAllocator.init(ctx.allocator);
    defer arena.deinit();
    const full_name = (try messageFullNameForCodegen(arena.allocator(), ctx.file, message)) orelse return;
    try indent(writer, depth);
    try writer.writeAll("/// Look up this message's descriptor in a decoded file descriptor.\n");
    try indent(writer, depth);
    try writer.writeAll("pub fn descriptor(file: *const pbz.schema.FileDescriptor) ?*const pbz.schema.MessageDescriptor {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return file.findMessageDeep(");
    try writeZigStringLiteral(full_name, writer);
    try writer.writeAll(");\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");
}

pub fn writeMessageDynamicBridge(ctx: *const CodegenContext, writer: *std.Io.Writer, depth: usize) Error!void {
    if (!ctx.emit_descriptor) return;
    try indent(writer, depth);
    try writer.writeAll("/// Convert to a dynamic message via the wire format for reflection workflows.\n");
    try indent(writer, depth);
    try writer.writeAll("pub fn toDynamic(self: @This(), allocator: std.mem.Allocator, file: *const pbz.schema.FileDescriptor) !pbz.DynamicMessage {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const message_descriptor = @This().descriptor(file) orelse return error.TypeMismatch;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var writer = pbz.Writer.init(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("defer writer.deinit();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.writeTo(&writer);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var message = pbz.DynamicMessage.init(allocator, message_descriptor);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer message.deinit();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try message.decode(file, writer.slice());\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return message;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");
    try indent(writer, depth);
    try writer.writeAll("/// Build from a dynamic message via the wire format. `file` must be the\n");
    try indent(writer, depth);
    try writer.writeAll("/// same decoded descriptor used to create `message`.\n");
    try indent(writer, depth);
    try writer.writeAll("pub fn fromDynamic(allocator: std.mem.Allocator, file: *const pbz.schema.FileDescriptor, message: *const pbz.DynamicMessage) !@This() {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const message_descriptor = @This().descriptor(file) orelse return error.TypeMismatch;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (message.descriptor != message_descriptor) return error.TypeMismatch;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var writer = pbz.Writer.init(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("defer writer.deinit();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try message.encode(file, &writer);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try @This().decodeOwned(allocator, writer.slice());\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");
}

pub fn writeMessageConformantParsers(ctx: *const CodegenContext, writer: *std.Io.Writer, depth: usize) Error!void {
    if (!ctx.emit_descriptor) return;
    if (ctx.emit_text) {
        try indent(writer, depth);
        try writer.writeAll("/// Full TextFormat parser backed by the dynamic parser. parseText falls\n");
        try indent(writer, depth);
        try writer.writeAll("/// back to this parser when the fast line-oriented path cannot parse.\n");
        try indent(writer, depth);
        try writer.writeAll("pub fn parseTextConformant(allocator: std.mem.Allocator, text: []const u8) !@This() {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return try @This().parseTextConformantWithOptions(allocator, text, .{});\n");
        try indent(writer, depth);
        try writer.writeAll("}\n\n");
    }
    if (ctx.emit_json) {
        try indent(writer, depth);
        try writer.writeAll("/// Full JSON parser backed by the dynamic parser.\n");
        try indent(writer, depth);
        try writer.writeAll("pub fn jsonParseConformant(allocator: std.mem.Allocator, text: []const u8) !@This() {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("var file = try pbz_generated_file.decodeFileDescriptor(allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("defer file.deinit();\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const message_descriptor = @This().descriptor(&file) orelse return error.TypeMismatch;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("var dynamic = try pbz.json.parseAlloc(allocator, &file, message_descriptor, text, .{});\n");
        try indent(writer, depth + 1);
        try writer.writeAll("defer dynamic.deinit();\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return try @This().fromDynamic(allocator, &file, &dynamic);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n\n");
    }
}
