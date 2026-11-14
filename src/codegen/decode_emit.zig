const enum_emit = @import("enum.zig");
const schema = @import("../schema.zig");
const std = @import("std");
const wire = @import("../wire.zig");
const cg = @import("../codegen.zig");
const CodegenContext = cg.CodegenContext;
const Error = cg.Error;
const fieldMessageEncoding = cg.fieldMessageEncoding;
const fieldUtf8Validation = cg.fieldUtf8Validation;
const hasPresence = cg.hasPresence;
const indent = cg.indent;
const typedMapMessageValueWithContext = cg.typedMapMessageValueWithContext;
const typedOneofMessageFieldWithContext = cg.typedOneofMessageFieldWithContext;
const typedRepeatedMessageFieldWithContext = cg.typedRepeatedMessageFieldWithContext;
const typedSingularMessageFieldWithContext = cg.typedSingularMessageFieldWithContext;
const writeFieldDefault = cg.writeFieldDefault;
const writeMessageTypeReferenceWithContext = cg.writeMessageTypeReferenceWithContext;
const writeOneofDeinitCall = cg.writeOneofDeinitCall;
const writePresenceIdent = cg.writePresenceIdent;
const writeQuotedIdent = cg.writeQuotedIdent;
const writeQuotedIdentWithPrefix = cg.writeQuotedIdentWithPrefix;
const writeQuotedIdentWithSuffix = cg.writeQuotedIdentWithSuffix;
const scalarZigType = cg.emit_helpers.scalarZigType;
const writeSetPresence = cg.emit_helpers.writeSetPresence;

pub fn writeDecode(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (messageCanFastRawTagDecode(ctx.file, message)) return try writeDecodeFastRawTag(ctx, message, writer, depth);

    try indent(writer, depth);
    try writer.writeAll("/// Decode from wire bytes. String/bytes fields borrow the input slice;\n");
    try indent(writer, depth);
    try writer.writeAll("/// use decodeOwned when the decoded message must outlive the input.\n");
    try indent(writer, depth);
    try writer.writeAll("pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) !@This() {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var r = pbz.Reader.init(bytes);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try @This().decodeFromReader(allocator, &r);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("/// Decode from an existing reader. String/bytes fields borrow the reader input.\n");
    try indent(writer, depth);
    try writer.writeAll("pub fn decodeFromReader(allocator: std.mem.Allocator, r: *pbz.Reader) anyerror!@This() {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var self = @This().init();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer self.deinit(allocator);\n");
    for (message.fields.items) |*field| try writeRepeatedListDeclForDecode(ctx, field, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("var _unknown_fields_list: std.ArrayList([]const u8) = .empty;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer pbz.wire.deinitRawFieldList(allocator, &_unknown_fields_list);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("while (try r.nextTag()) |tag| {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("if (!@This().decodeAcceptsTag(tag)) {\n");
    try writeUnknownFieldFallback(writer, depth + 3, true);
    try indent(writer, depth + 2);
    try writer.writeAll("continue;\n");
    try indent(writer, depth + 2);
    try writer.writeAll("}\n");
    try indent(writer, depth + 2);
    try writer.writeAll("switch (tag.number) {\n");
    for (message.fields.items) |*field| try writeDecodeField(ctx, field, writer, depth + 3);
    try indent(writer, depth + 3);
    try writer.writeAll("else => try pbz.wire.appendSkippedRawField(allocator, &_unknown_fields_list, r, r.lastTagStart(), tag),\n");
    try indent(writer, depth + 2);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    for (message.fields.items) |*field| try writeRepeatedAssignForDecode(field, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("self._unknown_fields = try pbz.wire.rawFieldListToOwnedSlice(allocator, &_unknown_fields_list);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return self;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");
    try writeDecodeAcceptsTag(ctx, message, writer, depth);
}

pub fn writeUnknownFieldFallback(writer: *std.Io.Writer, depth: usize, reader_is_pointer: bool) Error!void {
    try indent(writer, depth);
    try writer.writeAll("try pbz.wire.appendSkippedRawField(allocator, &_unknown_fields_list, ");
    try writer.writeAll(if (reader_is_pointer) "r" else "&r");
    try writer.writeAll(", r.lastTagStart(), tag);\n");
}

pub fn writeDecodeAcceptsTag(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("fn decodeAcceptsTag(tag: pbz.wire.Tag) bool {\n");
    if (message.fields.items.len == 0) {
        try indent(writer, depth + 1);
        try writer.writeAll("_ = tag;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return true;\n");
    } else {
        try indent(writer, depth + 1);
        try writer.writeAll("return switch (tag.number) {\n");
        for (message.fields.items) |*field| {
            try indent(writer, depth + 2);
            try writer.print("{d} => ", .{field.number});
            try writeDecodeAcceptedWireType(ctx.file, field, writer);
            try writer.writeAll(",\n");
        }
        try indent(writer, depth + 2);
        try writer.writeAll("else => true,\n");
        try indent(writer, depth + 1);
        try writer.writeAll("};\n");
    }
    try indent(writer, depth);
    try writer.writeAll("}\n\n");
}

pub fn writeDecodeAcceptedWireType(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    if (field.cardinality == .repeated and field.kind.packable()) {
        try writer.writeAll("tag.wire_type == .");
        try writer.writeAll(@tagName(field.kind.wireType()));
        try writer.writeAll(" or tag.wire_type == .length_delimited");
        return;
    }
    if (field.kind == .message) {
        if (fieldMessageEncoding(file, field) == .delimited) {
            try writer.writeAll("tag.wire_type == .start_group");
        } else {
            try writer.writeAll("tag.wire_type == .length_delimited");
        }
        return;
    }
    try writer.writeAll("tag.wire_type == .");
    try writer.writeAll(@tagName(field.kind.wireType()));
}

pub fn messageCanFastRawTagDecode(file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor) bool {
    if (message.oneofs.items.len != 0) return false;
    var has_length_delimited_scalar = false;
    for (message.fields.items) |field| {
        switch (field.kind) {
            .scalar => |scalar| switch (scalar) {
                .string, .bytes => has_length_delimited_scalar = true,
                else => {},
            },
            .enumeration => |name| if (enum_emit.enumIsClosed(file, name)) return false,
            .message, .group, .map => return false,
        }
    }
    return has_length_delimited_scalar or message.fields.items.len >= 8;
}

pub fn writeDecodeFastRawTag(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("/// Decode from wire bytes. String/bytes fields borrow the input slice;\n");
    try indent(writer, depth);
    try writer.writeAll("/// use decodeOwned when the decoded message must outlive the input.\n");
    try indent(writer, depth);
    try writer.writeAll("pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) !@This() {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var r = pbz.Reader.init(bytes);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try @This().decodeFromReader(allocator, &r);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("/// Decode from an existing reader. String/bytes fields borrow the reader input.\n");
    try indent(writer, depth);
    try writer.writeAll("pub fn decodeFromReader(allocator: std.mem.Allocator, r: *pbz.Reader) anyerror!@This() {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var self = @This().init();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer self.deinit(allocator);\n");
    for (message.fields.items) |*field| try writeRepeatedListDeclForDecode(ctx, field, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("var _unknown_fields_list: std.ArrayList([]const u8) = .empty;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer pbz.wire.deinitRawFieldList(allocator, &_unknown_fields_list);\n");
    try writeRawTagDecodeLoop(ctx, message, writer, depth + 1, true);
    for (message.fields.items) |*field| try writeRepeatedAssignForDecode(field, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("self._unknown_fields = try pbz.wire.rawFieldListToOwnedSlice(allocator, &_unknown_fields_list);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return self;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeRawTagDecodeLoop(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize, r_is_pointer: bool) Error!void {
    try indent(writer, depth);
    try writer.writeAll("while (!r.eof()) {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const raw_tag_start = r.position();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const first_tag_byte = try r.readByte();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const raw_tag: u64 = if (first_tag_byte < 0x80) first_tag_byte else blk: { r.index = raw_tag_start; break :blk try r.readVarint(); };\n");
    try indent(writer, depth + 1);
    try writer.writeAll("switch (raw_tag) {\n");
    for (message.fields.items) |*field| try writeRawTagDecodeFieldCases(ctx, field, writer, depth + 2);
    try indent(writer, depth + 2);
    try writer.writeAll("else => try pbz.wire.appendSkippedRawField(allocator, &_unknown_fields_list, ");
    try writer.writeAll(if (r_is_pointer) "r" else "&r");
    try writer.writeAll(", raw_tag_start, try pbz.wire.Tag.decode(raw_tag)),\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeRawTagDecodeFieldCases(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    switch (field.kind) {
        .scalar => |scalar| {
            if (field.cardinality == .repeated and scalar.packable()) {
                try writeRawTagDecodePackedScalarCase(field, scalar, writer, depth);
                try writeRawTagDecodeUnpackedScalarCase(ctx.file, field, scalar, writer, depth);
            } else if (field.cardinality == .repeated) {
                try writeRawTagDecodeUnpackedScalarCase(ctx.file, field, scalar, writer, depth);
            } else {
                try writeRawTagDecodeSingularScalarCase(ctx.file, field, scalar, writer, depth);
            }
        },
        .enumeration => {
            if (field.cardinality == .repeated) {
                if (field.resolvedPacked(ctx.file)) try writeRawTagDecodePackedEnumCase(ctx.file, field, writer, depth);
                try writeRawTagDecodeUnpackedEnumCase(field, writer, depth);
            } else {
                try writeRawTagDecodeSingularEnumCase(ctx.file, field, writer, depth);
            }
        },
        else => unreachable,
    }
}

pub fn writeRawTagDecodeSingularScalarCase(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.print("{d} => {{ self.", .{rawFieldTag(field.number, .{ .scalar = scalar })});
    try writeQuotedIdent(field.name, writer);
    try writer.print(" = try r.{s}();", .{scalarReaderName(scalar)});
    if (scalar == .string and fieldUtf8Validation(file, field) == .verify) {
        try writer.writeAll(" if (!pbz.validateUtf8(self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(")) return error.InvalidUtf8;");
    }
    try writeSetPresence(file, field, writer);
    try writer.writeAll(" },\n");
}

pub fn writeRawTagDecodeUnpackedScalarCase(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.print("{d} => ", .{rawFieldTag(field.number, .{ .scalar = scalar })});
    if (scalar == .string and fieldUtf8Validation(file, field) == .verify) {
        try writer.writeAll("{ const value = try r.readBytes(); if (!pbz.validateUtf8(value)) return error.InvalidUtf8; ");
        try writeRepeatedAppendPrefix(field, writer);
        try writer.writeAll("value); },\n");
        return;
    }
    try writeRepeatedAppendPrefix(field, writer);
    try writer.print("try r.{s}()),\n", .{scalarReaderName(scalar)});
}

pub fn writeRawTagDecodePackedScalarCase(field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.print("{d} => {{\n", .{rawTagValue(field.number, .length_delimited)});
    try writeDecodePackedScalarPayload(field, scalar, writer, depth + 1);
    try indent(writer, depth);
    try writer.writeAll("},\n");
}

pub fn writeRawTagDecodeSingularEnumCase(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.print("{d} => {{ const value = try r.readInt32(); self.", .{rawTagValue(field.number, .varint)});
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = value;");
    try writeSetPresence(file, field, writer);
    try writer.writeAll(" },\n");
}

pub fn writeRawTagDecodeUnpackedEnumCase(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.print("{d} => ", .{rawTagValue(field.number, .varint)});
    try writeRepeatedAppendPrefix(field, writer);
    try writer.writeAll("try r.readInt32()),\n");
}

pub fn writeRawTagDecodePackedEnumCase(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.print("{d} => {{\n", .{rawTagValue(field.number, .length_delimited)});
    try indent(writer, depth + 1);
    try writer.writeAll("const payload = try r.readBytes();\n");
    if (field.kind == .enumeration and !enum_emit.enumIsClosed(file, field.kind.enumeration)) {
        try indent(writer, depth + 1);
        try writer.writeAll("try pbz.wire.appendPackedInt32(allocator, &");
        try writeQuotedIdentWithSuffix(field.name, "_list", writer);
        try writer.writeAll(", payload);\n");
    } else {
        try indent(writer, depth + 1);
        try writer.writeAll("try ");
        try writeQuotedIdentWithSuffix(field.name, "_list", writer);
        try writer.writeAll(".ensureUnusedCapacity(allocator, payload.len);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("var packed_reader = pbz.Reader.init(payload);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("while (!packed_reader.eof()) ");
        try writeQuotedIdentWithSuffix(field.name, "_list", writer);
        try writer.writeAll(".appendAssumeCapacity(try packed_reader.readInt32());\n");
    }
    try indent(writer, depth);
    try writer.writeAll("},\n");
}

pub fn rawFieldTag(number: u29, kind: schema.FieldKind) u64 {
    return rawTagValue(number, kind.wireType());
}

pub fn rawTagValue(number: u29, wire_type: wire.WireType) u64 {
    return (@as(u64, number) << 3) | @intFromEnum(wire_type);
}

pub fn messageCanDecodeKnownReuse(file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor) bool {
    if (message.oneofs.items.len != 0) return false;
    var has_repeated = false;
    for (message.fields.items) |field| {
        if (field.cardinality == .repeated) {
            has_repeated = true;
            switch (field.kind) {
                .scalar => |scalar| if (knownReuseRepeatedScalarSupported(scalar) == false) return false,
                .enumeration => |name| if (enum_emit.enumIsClosed(file, name)) return false,
                else => return false,
            }
            continue;
        }
        switch (field.kind) {
            .scalar => {},
            .enumeration => |name| if (enum_emit.enumIsClosed(file, name)) return false,
            .message, .group, .map => return false,
        }
    }
    return has_repeated;
}

pub fn knownReuseRepeatedScalarSupported(scalar: schema.ScalarType) bool {
    return switch (scalar) {
        .bool,
        .uint64,
        .uint32,
        .int32,
        .int64,
        .sint32,
        .sint64,
        .fixed32,
        .fixed64,
        .sfixed32,
        .sfixed64,
        .float,
        .double,
        => true,
        else => false,
    };
}

pub fn writeDecodeReuse(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("/// Decode into an existing message, reusing repeated/map storage.\n");
    try indent(writer, depth);
    try writer.writeAll("/// String/bytes fields still borrow the input slice.\n");
    try indent(writer, depth);
    try writer.writeAll("pub fn decodeReuse(self: *@This(), allocator: std.mem.Allocator, bytes: []const u8) !void {\n");
    for (message.fields.items) |*field| try writeRepeatedReuseListDecl(ctx, field, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("pbz.wire.clearRawFields(allocator, &self._unknown_fields);\n");
    for (message.fields.items) |*field| try writeDecodeReuseClearMap(ctx, field, writer, depth + 1);
    for (message.oneofs.items) |oneof| try writeDecodeReuseClearOneof(oneof, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("if (self._json_arena) |arena| { _ = arena.reset(.retain_capacity); }\n");
    for (message.fields.items) |*field| try writeDecodeReuseResetField(ctx, field, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer self.deinit(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var _unknown_fields_list: std.ArrayList([]const u8) = .empty;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer pbz.wire.deinitRawFieldList(allocator, &_unknown_fields_list);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var r = pbz.Reader.init(bytes);\n");
    if (messageCanFastRawTagDecode(ctx.file, message)) {
        try writeRawTagDecodeLoop(ctx, message, writer, depth + 1, false);
    } else {
        try indent(writer, depth + 1);
        try writer.writeAll("while (try r.nextTag()) |tag| {\n");
        try indent(writer, depth + 2);
        try writer.writeAll("if (!@This().decodeAcceptsTag(tag)) {\n");
        try writeUnknownFieldFallback(writer, depth + 3, false);
        try indent(writer, depth + 2);
        try writer.writeAll("continue;\n");
        try indent(writer, depth + 2);
        try writer.writeAll("}\n");
        try indent(writer, depth + 2);
        try writer.writeAll("switch (tag.number) {\n");
        for (message.fields.items) |*field| try writeDecodeField(ctx, field, writer, depth + 3);
        try indent(writer, depth + 3);
        try writer.writeAll("else => try pbz.wire.appendSkippedRawField(allocator, &_unknown_fields_list, &r, r.lastTagStart(), tag),\n");
        try indent(writer, depth + 2);
        try writer.writeAll("}\n");
        try indent(writer, depth + 1);
        try writer.writeAll("}\n");
    }
    for (message.fields.items) |*field| try writeRepeatedAssignForDecode(field, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("self._unknown_fields = try pbz.wire.rawFieldListToOwnedSlice(allocator, &_unknown_fields_list);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeDecodeOwnedReuse(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    _ = ctx;
    _ = message;
    try indent(writer, depth);
    try writer.writeAll("/// Decode into an existing message, reusing arrays/maps and retained owned string storage.\n");
    try indent(writer, depth);
    try writer.writeAll("pub fn decodeOwnedReuse(self: *@This(), allocator: std.mem.Allocator, bytes: []const u8) !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer self.deinit(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.decodeReuse(allocator, bytes);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.adoptOwned(allocator);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeDecodeKnownReuse(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("/// Trusted same-schema hot path that reuses existing repeated buffers.\n");
    try indent(writer, depth);
    try writer.writeAll("/// The caller must pre-size those buffers for the decoded element counts.\n");
    try indent(writer, depth);
    try writer.writeAll("/// Unknown or schema-mismatched fields are rejected instead of preserved.\n");
    try indent(writer, depth);
    try writer.writeAll("pub fn decodeKnownReuse(self: *@This(), allocator: std.mem.Allocator, bytes: []const u8) !void {\n");
    for (message.fields.items) |*field| {
        if (field.cardinality != .repeated) continue;
        try indent(writer, depth + 1);
        try writer.writeAll("const ");
        try writeQuotedIdentWithSuffix(field.name, "_buffer", writer);
        try writer.writeAll(" = @constCast(self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(");\n");
        try indent(writer, depth + 1);
        try writer.writeAll("var ");
        try writeQuotedIdentWithSuffix(field.name, "_len", writer);
        try writer.writeAll(": usize = 0;\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("pbz.wire.clearRawFields(allocator, &self._unknown_fields);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (self._json_arena) |arena| { const child_allocator = arena.child_allocator; arena.deinit(); child_allocator.destroy(arena); self._json_arena = null; }\n");
    for (message.fields.items) |*field| try writeDecodeReuseResetField(ctx, field, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("var r = pbz.Reader.init(bytes);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("while (!r.eof()) {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("const raw_tag_start = r.position();\n");
    try indent(writer, depth + 2);
    try writer.writeAll("const first_tag_byte = try r.readByte();\n");
    try indent(writer, depth + 2);
    try writer.writeAll("const raw_tag: u64 = if (first_tag_byte < 0x80) first_tag_byte else blk: { r.index = raw_tag_start; break :blk try r.readVarint(); };\n");
    try indent(writer, depth + 2);
    try writer.writeAll("switch (raw_tag) {\n");
    for (message.fields.items) |*field| {
        if (field.cardinality == .repeated) {
            switch (field.kind) {
                .scalar => |scalar| try writeKnownReuseRepeatedScalarCases(ctx.file, field, scalar, writer, depth + 3),
                .enumeration => try writeKnownReuseRepeatedEnumCases(field, writer, depth + 3),
                else => {},
            }
            continue;
        }
        switch (field.kind) {
            .scalar => |scalar| try writeKnownReuseSingularScalarCase(ctx.file, field, scalar, writer, depth + 3),
            .enumeration => try writeKnownReuseSingularEnumCase(ctx.file, field, writer, depth + 3),
            else => {},
        }
    }
    try indent(writer, depth + 3);
    try writer.writeAll("else => return error.InvalidWireType,\n");
    try indent(writer, depth + 2);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    for (message.fields.items) |*field| {
        if (field.cardinality != .repeated) continue;
        try indent(writer, depth + 1);
        try writer.writeAll("if (");
        try writeQuotedIdentWithSuffix(field.name, "_len", writer);
        try writer.writeAll(" != ");
        try writeQuotedIdentWithSuffix(field.name, "_buffer", writer);
        try writer.writeAll(".len) return error.InvalidWireType;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = ");
        try writeQuotedIdentWithSuffix(field.name, "_buffer", writer);
        try writer.writeAll(";\n");
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeKnownReuseRepeatedScalarCases(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
    _ = file;
    try indent(writer, depth);
    try writer.print("{d} => {{\n", .{rawTagValue(field.number, .length_delimited)});
    try indent(writer, depth + 1);
    try writer.writeAll("const payload = try r.readBytes();\n");
    try writeKnownReuseRepeatedScalarPayload(field, scalar, "payload", writer, depth + 1);
    try indent(writer, depth);
    try writer.writeAll("},\n");

    try indent(writer, depth);
    try writer.print("{d} => {{\n", .{rawTagValue(field.number, scalar.wireType())});
    try indent(writer, depth + 1);
    try writeQuotedIdentWithSuffix(field.name, "_buffer", writer);
    try writer.writeAll("[");
    try writeQuotedIdentWithSuffix(field.name, "_len", writer);
    try writer.writeAll("] = try r.");
    try writer.writeAll(scalarReaderName(scalar));
    try writer.writeAll("();\n");
    try indent(writer, depth + 1);
    try writeQuotedIdentWithSuffix(field.name, "_len", writer);
    try writer.writeAll(" += 1;\n");
    try indent(writer, depth);
    try writer.writeAll("},\n");
}

pub fn writeKnownReuseRepeatedEnumCases(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.print("{d} => {{\n", .{rawTagValue(field.number, .length_delimited)});
    try indent(writer, depth + 1);
    try writer.writeAll("const payload = try r.readBytes();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (pbz.wire.packedEnumAllSingleByte(payload)) {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("for (payload) |byte| {\n");
    try indent(writer, depth + 3);
    try writeQuotedIdentWithSuffix(field.name, "_buffer", writer);
    try writer.writeAll("[");
    try writeQuotedIdentWithSuffix(field.name, "_len", writer);
    try writer.writeAll("] = @intCast(byte);\n");
    try indent(writer, depth + 3);
    try writeQuotedIdentWithSuffix(field.name, "_len", writer);
    try writer.writeAll(" += 1;\n");
    try indent(writer, depth + 2);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("} else {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var payload_index: usize = 0;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("while (payload_index < payload.len) {\n");
    try indent(writer, depth + 2);
    try writeQuotedIdentWithSuffix(field.name, "_buffer", writer);
    try writer.writeAll("[");
    try writeQuotedIdentWithSuffix(field.name, "_len", writer);
    try writer.writeAll("] = @truncate(@as(i64, @bitCast(try pbz.wire.readVarintAt(payload, &payload_index))));\n");
    try indent(writer, depth + 2);
    try writeQuotedIdentWithSuffix(field.name, "_len", writer);
    try writer.writeAll(" += 1;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth);
    try writer.writeAll("},\n");

    try indent(writer, depth);
    try writer.print("{d} => {{\n", .{rawTagValue(field.number, .varint)});
    try indent(writer, depth + 1);
    try writeQuotedIdentWithSuffix(field.name, "_buffer", writer);
    try writer.writeAll("[");
    try writeQuotedIdentWithSuffix(field.name, "_len", writer);
    try writer.writeAll("] = try r.readInt32();\n");
    try indent(writer, depth + 1);
    try writeQuotedIdentWithSuffix(field.name, "_len", writer);
    try writer.writeAll(" += 1;\n");
    try indent(writer, depth);
    try writer.writeAll("},\n");
}

pub fn writeKnownReuseSingularScalarCase(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.print("{d} => {{ self.", .{rawFieldTag(field.number, .{ .scalar = scalar })});
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = ");
    try writeKnownReuseSingularScalarDecodeExpr(scalar, "r.input", "r.index", writer);
    try writer.writeAll(";");
    if (scalar == .string and fieldUtf8Validation(file, field) == .verify) {
        try writer.writeAll(" if (!pbz.validateUtf8(self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(")) return error.InvalidUtf8;");
    }
    try writeSetPresence(file, field, writer);
    try writer.writeAll(" },\n");
}

pub fn writeKnownReuseSingularEnumCase(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.print("{d} => {{ const value = try pbz.wire.readInt32At(r.input, &r.index); self.", .{rawTagValue(field.number, .varint)});
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = value;");
    try writeSetPresence(file, field, writer);
    try writer.writeAll(" },\n");
}

pub fn writeKnownReuseRepeatedScalarPayload(field: *const schema.FieldDescriptor, scalar: schema.ScalarType, payload_expr: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    if (scalar == .bool) {
        try indent(writer, depth);
        try writer.writeAll("try pbz.wire.decodePackedBoolInto(");
        try writeQuotedIdentWithSuffix(field.name, "_buffer", writer);
        try writer.writeAll(", &");
        try writeQuotedIdentWithSuffix(field.name, "_len", writer);
        try writer.writeAll(", ");
        try writer.writeAll(payload_expr);
        try writer.writeAll(");\n");
        return;
    }

    if (fixedWidthPackedScalarSizeForCodegen(scalar)) |width| {
        try indent(writer, depth);
        try writer.print("if ({s}.len % {d} != 0) return error.InvalidWireType;\n", .{ payload_expr, width });
        try indent(writer, depth);
        try writer.print("const value_count = {s}.len / {d};\n", .{ payload_expr, width });
        try indent(writer, depth);
        try writer.writeAll("if (");
        try writeQuotedIdentWithSuffix(field.name, "_len", writer);
        try writer.writeAll(" + value_count > ");
        try writeQuotedIdentWithSuffix(field.name, "_buffer", writer);
        try writer.writeAll(".len) return error.InvalidWireType;\n");
        try indent(writer, depth);
        try writer.writeAll("{\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const out = ");
        try writeQuotedIdentWithSuffix(field.name, "_buffer", writer);
        try writer.writeAll("[");
        try writeQuotedIdentWithSuffix(field.name, "_len", writer);
        try writer.writeAll("..][0..value_count];\n");
        try indent(writer, depth + 1);
        try writer.writeAll("if (comptime @import(\"builtin\").target.cpu.arch.endian() == .little) {\n");
        try indent(writer, depth + 2);
        try writer.print("pbz.wire.copyBytes(std.mem.sliceAsBytes(out), {s});\n", .{payload_expr});
        try indent(writer, depth + 1);
        try writer.writeAll("} else {\n");
        try indent(writer, depth + 2);
        try writer.writeAll("var payload_index: usize = 0;\n");
        try indent(writer, depth + 2);
        try writer.writeAll("for (out) |*value| {\n");
        try indent(writer, depth + 3);
        try writer.writeAll("value.* = ");
        try writeKnownReuseFixedWidthScalarDecodeExpr(scalar, payload_expr, "payload_index", width, writer);
        try writer.writeAll(";\n");
        try indent(writer, depth + 3);
        try writer.print("payload_index += {d};\n", .{width});
        try indent(writer, depth + 2);
        try writer.writeAll("}\n");
        try indent(writer, depth + 1);
        try writer.writeAll("}\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");
        try indent(writer, depth);
        try writeQuotedIdentWithSuffix(field.name, "_len", writer);
        try writer.writeAll(" += value_count;\n");
        return;
    }

    try indent(writer, depth);
    try writer.writeAll("var payload_index: usize = 0;\n");
    try indent(writer, depth);
    try writer.print("while (payload_index < {s}.len) {{\n", .{payload_expr});
    try indent(writer, depth + 1);
    try writeQuotedIdentWithSuffix(field.name, "_buffer", writer);
    try writer.writeAll("[");
    try writeQuotedIdentWithSuffix(field.name, "_len", writer);
    try writer.writeAll("] = ");
    try writeKnownReuseRepeatedScalarDecodeExpr(scalar, payload_expr, writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writeQuotedIdentWithSuffix(field.name, "_len", writer);
    try writer.writeAll(" += 1;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeKnownReuseSingularScalarDecodeExpr(scalar: schema.ScalarType, input_expr: []const u8, index_expr: []const u8, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .double => try writer.print("@bitCast(try pbz.wire.readRawLittleAt(u64, {s}, &{s}))", .{ input_expr, index_expr }),
        .float => try writer.print("@bitCast(try pbz.wire.readRawLittleAt(u32, {s}, &{s}))", .{ input_expr, index_expr }),
        .int32 => try writer.print("try pbz.wire.readInt32At({s}, &{s})", .{ input_expr, index_expr }),
        .int64 => try writer.print("@bitCast(try pbz.wire.readVarintAt({s}, &{s}))", .{ input_expr, index_expr }),
        .uint32 => try writer.print("try pbz.wire.readUInt32At({s}, &{s})", .{ input_expr, index_expr }),
        .uint64 => try writer.print("try pbz.wire.readVarintAt({s}, &{s})", .{ input_expr, index_expr }),
        .sint32 => try writer.print("try pbz.wire.readSInt32At({s}, &{s})", .{ input_expr, index_expr }),
        .sint64 => try writer.print("pbz.wire.zigZagDecode64(try pbz.wire.readVarintAt({s}, &{s}))", .{ input_expr, index_expr }),
        .fixed32 => try writer.print("try pbz.wire.readRawLittleAt(u32, {s}, &{s})", .{ input_expr, index_expr }),
        .fixed64 => try writer.print("try pbz.wire.readRawLittleAt(u64, {s}, &{s})", .{ input_expr, index_expr }),
        .sfixed32 => try writer.print("@bitCast(try pbz.wire.readRawLittleAt(u32, {s}, &{s}))", .{ input_expr, index_expr }),
        .sfixed64 => try writer.print("@bitCast(try pbz.wire.readRawLittleAt(u64, {s}, &{s}))", .{ input_expr, index_expr }),
        .bool => try writer.print("try pbz.wire.readBoolAt({s}, &{s})", .{ input_expr, index_expr }),
        .string, .bytes => try writer.writeAll("try r.readBytes()"),
    }
}

pub fn writeKnownReuseRepeatedScalarDecodeExpr(scalar: schema.ScalarType, payload_expr: []const u8, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .uint64 => try writer.print("try pbz.wire.readVarintAt({s}, &payload_index)", .{payload_expr}),
        .uint32 => try writer.print("@as(u32, @truncate(try pbz.wire.readVarintAt({s}, &payload_index)))", .{payload_expr}),
        .int32 => try writer.print("try pbz.wire.readInt32At({s}, &payload_index)", .{payload_expr}),
        .int64 => try writer.print("@bitCast(try pbz.wire.readVarintAt({s}, &payload_index))", .{payload_expr}),
        .sint32 => try writer.print("try pbz.wire.readSInt32At({s}, &payload_index)", .{payload_expr}),
        .sint64 => try writer.print("pbz.wire.zigZagDecode64(try pbz.wire.readVarintAt({s}, &payload_index))", .{payload_expr}),
        else => try writer.writeAll("@compileError(\"unsupported known reuse scalar\")"),
    }
}

pub fn fixedWidthPackedScalarSizeForCodegen(scalar: schema.ScalarType) ?usize {
    return switch (scalar) {
        .fixed32, .sfixed32, .float => 4,
        .fixed64, .sfixed64, .double => 8,
        else => null,
    };
}

pub fn writeKnownReuseFixedWidthScalarDecodeExpr(scalar: schema.ScalarType, payload_expr: []const u8, index_expr: []const u8, width: usize, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .fixed32 => try writer.print("std.mem.readInt(u32, {s}[{s}..][0..{d}], .little)", .{ payload_expr, index_expr, width }),
        .fixed64 => try writer.print("std.mem.readInt(u64, {s}[{s}..][0..{d}], .little)", .{ payload_expr, index_expr, width }),
        .sfixed32 => try writer.print("std.mem.readInt(i32, {s}[{s}..][0..{d}], .little)", .{ payload_expr, index_expr, width }),
        .sfixed64 => try writer.print("std.mem.readInt(i64, {s}[{s}..][0..{d}], .little)", .{ payload_expr, index_expr, width }),
        .float => try writer.print("@bitCast(std.mem.readInt(u32, {s}[{s}..][0..{d}], .little))", .{ payload_expr, index_expr, width }),
        .double => try writer.print("@bitCast(std.mem.readInt(u64, {s}[{s}..][0..{d}], .little))", .{ payload_expr, index_expr, width }),
        else => try writer.writeAll("@compileError(\"unsupported fixed-width known reuse scalar\")"),
    }
}

pub fn writeRepeatedReuseListDecl(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.kind == .map) return;
    if (field.cardinality != .repeated) return;
    try indent(writer, depth);
    try writer.writeAll("var ");
    try writeQuotedIdentWithSuffix(field.name, "_list", writer);
    try writer.writeAll(": std.ArrayList(");
    if (typedRepeatedMessageFieldWithContext(ctx, field)) |type_name| {
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    } else {
        try writeRepeatedElementType(field.*, writer);
    }
    try writer.writeAll(") = std.ArrayList(");
    if (typedRepeatedMessageFieldWithContext(ctx, field)) |type_name| {
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    } else {
        try writeRepeatedElementType(field.*, writer);
    }
    try writer.writeAll(").fromOwnedSlice(@constCast(self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll("));\n");
    if (typedRepeatedMessageFieldWithContext(ctx, field) != null) {
        try indent(writer, depth);
        try writer.writeAll("for (");
        try writeQuotedIdentWithSuffix(field.name, "_list", writer);
        try writer.writeAll(".items) |*item| item.deinit(allocator);\n");
    }
    try indent(writer, depth);
    try writeQuotedIdentWithSuffix(field.name, "_list", writer);
    try writer.writeAll(".clearRetainingCapacity();\n");
    try indent(writer, depth);
    try writer.writeAll("self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = &.{};\n");
    try indent(writer, depth);
    try writer.writeAll("errdefer ");
    try writeQuotedIdentWithSuffix(field.name, "_list", writer);
    try writer.writeAll(".deinit(allocator);\n");
}

pub fn writeDecodeReuseResetField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.oneof_name != null) return;
    if (field.kind == .map) return;
    if (field.cardinality == .repeated) return;
    if (typedSingularMessageFieldWithContext(ctx, field) != null) {
        try indent(writer, depth);
        try writer.writeAll("if (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(") |*value| value.deinit(allocator);\n");
        try indent(writer, depth);
        try writer.writeAll("self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = null;\n");
        return;
    }
    try indent(writer, depth);
    try writer.writeAll("self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = ");
    try writeFieldDefault(ctx.file, field.*, writer);
    try writer.writeAll(";\n");
    if (hasPresence(ctx.file, field.*)) {
        try indent(writer, depth);
        try writer.writeAll("self.");
        try writePresenceIdent(field.name, writer);
        try writer.writeAll(" = false;\n");
    }
}

pub fn writeDecodeReuseClearMap(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.kind != .map) return;
    if (typedMapMessageValueWithContext(ctx, field)) |_| {
        try indent(writer, depth);
        try writer.writeAll("{ var map_it = self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(".iterator(); while (map_it.next()) |entry| entry.value_ptr.deinit(allocator); }\n");
    }
    try indent(writer, depth);
    try writer.writeAll("self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".clearRetainingCapacity();\n");
}

pub fn writeDecodeReuseClearOneof(oneof: schema.OneofDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writeOneofDeinitCall(oneof.name, writer);
    try writer.writeAll("\n");
}

pub fn writeDecodeInitialized(writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn decodeOwned(allocator: std.mem.Allocator, bytes: []const u8) !@This() {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var self = try @This().decode(allocator, bytes);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer self.deinit(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.adoptOwned(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return self;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("/// Decode and validate required fields. String/bytes fields borrow the input slice.\n");
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

    try writer.writeAll("\n");
    try indent(writer, depth);
    try writer.writeAll("/// Decode, deep-copy, and validate required fields.\n");
    try indent(writer, depth);
    try writer.writeAll("pub fn decodeOwnedInitialized(allocator: std.mem.Allocator, bytes: []const u8) !@This() {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var self = try @This().decodeOwned(allocator, bytes);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer self.deinit(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.validateRequiredRecursive(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return self;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeRepeatedListDecl(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.cardinality != .repeated and field.kind != .map) return;
    try indent(writer, depth);
    try writer.writeAll("var ");
    try writeQuotedIdentWithSuffix(field.name, "_list", writer);
    try writer.writeAll(": std.ArrayList(");
    if (typedRepeatedMessageFieldWithContext(ctx, field)) |type_name| {
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    } else {
        try writeRepeatedElementType(field.*, writer);
    }
    try writer.writeAll(") = .empty;\n");
    try indent(writer, depth);
    try writer.writeAll("defer ");
    try writeQuotedIdentWithSuffix(field.name, "_list", writer);
    try writer.writeAll(".deinit(allocator);\n");
    if (typedRepeatedMessageFieldWithContext(ctx, field)) |_| {
        try indent(writer, depth);
        try writer.writeAll("errdefer for (");
        try writeQuotedIdentWithSuffix(field.name, "_list", writer);
        try writer.writeAll(".items) |item| { var mutable = item; mutable.deinit(allocator); };\n");
    } else if (typedMapMessageValueWithContext(ctx, field)) |_| {
        try indent(writer, depth);
        try writer.writeAll("errdefer for (");
        try writeQuotedIdentWithSuffix(field.name, "_list", writer);
        try writer.writeAll(".items) |list_entry| { var old_value = list_entry.value; old_value.deinit(allocator); };\n");
    }
}

pub fn writeRepeatedListDeclForDecode(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.kind == .map) return;
    try writeRepeatedListDecl(ctx, field, writer, depth);
}

pub fn writeRepeatedAssign(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.cardinality != .repeated and field.kind != .map) return;
    if (field.kind == .map) return try writeMapAssign(field, writer, depth);
    try indent(writer, depth);
    try writer.writeAll("self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = if (");
    try writeQuotedIdentWithSuffix(field.name, "_list", writer);
    try writer.writeAll(".items.len != 0 and ");
    try writeQuotedIdentWithSuffix(field.name, "_list", writer);
    try writer.writeAll(".items.len == ");
    try writeQuotedIdentWithSuffix(field.name, "_list", writer);
    try writer.writeAll(".capacity) ");
    try writeQuotedIdentWithSuffix(field.name, "_list", writer);
    try writer.writeAll(".toOwnedSliceAssert() else try ");
    try writeQuotedIdentWithSuffix(field.name, "_list", writer);
    try writer.writeAll(".toOwnedSlice(allocator);\n");
}

pub fn writeRepeatedAssignForDecode(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.kind == .map) return;
    try writeRepeatedAssign(field, writer, depth);
}

pub fn writeMapAssign(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = .empty;\n");
    try indent(writer, depth);
    try writer.writeAll("try self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".ensureUnusedCapacity(allocator, ");
    try writeQuotedIdentWithSuffix(field.name, "_list", writer);
    try writer.writeAll(".items.len);\n");
    try indent(writer, depth);
    try writer.writeAll("for (");
    try writeQuotedIdentWithSuffix(field.name, "_list", writer);
    try writer.writeAll(".items) |entry| self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".putAssumeCapacityNoClobber(entry.key, entry.value);\n");
}

pub fn writeRepeatedElementType(field: schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    switch (field.kind) {
        .scalar => |scalar| try writer.writeAll(scalarZigType(scalar)),
        .enumeration => try writer.writeAll("i32"),
        .message, .group => try writer.writeAll("[]const u8"),
        .map => try writeQuotedIdentWithSuffix(field.name, "Entry", writer),
    }
}

pub fn writeDecodeField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    switch (field.kind) {
        .scalar => |scalar| try writeDecodeScalarField(file, field, scalar, writer, depth),
        .enumeration => try writeDecodeEnumField(file, field, writer, depth),
        .message, .group => try writeDecodeMessageField(ctx, field, writer, depth),
        .map => try writeDecodeMapField(ctx, field, writer, depth),
    }
}

pub fn writeDecodeScalarField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.print("{d} => ", .{field.number});
    if (field.cardinality == .repeated) {
        if (scalar.packable()) {
            try writeDecodePackedScalarField(field, scalar, writer, depth);
        } else {
            if (scalar == .string and fieldUtf8Validation(file, field) == .verify) {
                try writer.writeAll("{ const value = try r.readBytes(); if (!pbz.validateUtf8(value)) return error.InvalidUtf8; ");
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
            try writer.writeAll(" if (!pbz.validateUtf8(self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(")) return error.InvalidUtf8;");
        }
        try writeSetPresence(file, field, writer);
        try writer.writeAll(" },\n");
    }
}

pub fn writeDecodeEnumField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.print("{d} => ", .{field.number});
    if (field.cardinality == .repeated) {
        try writeDecodePackedEnumField(file, field, writer, depth);
    } else if (field.oneof_name != null) {
        try writeOneofEnumDecodeAssign(file, field, writer);
    } else if (field.kind == .enumeration and enum_emit.enumIsClosed(file, field.kind.enumeration)) {
        try writer.writeAll("{ const value = try r.readInt32(); if (!@This().enumKnown(value, ");
        try enum_emit.writeEnumNumberArray(file, field.kind.enumeration, writer);
        try writer.writeAll(")) { try pbz.wire.appendConsumedRawField(allocator, &_unknown_fields_list, r, r.lastTagStart()); } else { self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = value;");
        try writeSetPresence(file, field, writer);
        try writer.writeAll(" } },\n");
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

pub fn writeDecodeMessageField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    try indent(writer, depth);
    try writer.print("{d} => ", .{field.number});
    if (field.cardinality == .repeated) {
        if (typedRepeatedMessageFieldWithContext(ctx, field)) |type_name| {
            try writer.writeAll("{ const payload = ");
            try writeMessagePayloadRead(file, field, "r", writer);
            try writer.writeAll("; var payload_reader = try r.nested(payload); var _pbz_nested = try ");
            try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
            try writer.writeAll(".decodeFromReader(allocator, &payload_reader); errdefer _pbz_nested.deinit(allocator); try ");
            try writeQuotedIdentWithSuffix(field.name, "_list", writer);
            try writer.writeAll(".append(allocator, _pbz_nested); },\n");
        } else {
            try writeRepeatedAppendPrefix(field, writer);
            try writeMessagePayloadRead(file, field, "r", writer);
            try writer.writeAll("),\n");
        }
    } else if (field.oneof_name != null) {
        try writeOneofMessageDecodeAssign(ctx, field, writer);
    } else if (typedSingularMessageFieldWithContext(ctx, field)) |type_name| {
        try writer.writeAll("{ const payload = ");
        try writeMessagePayloadRead(file, field, "r", writer);
        try writer.writeAll("; var payload_reader = try r.nested(payload); var _pbz_nested = try ");
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
        try writer.writeAll(".decodeFromReader(allocator, &payload_reader); errdefer _pbz_nested.deinit(allocator); if (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(") |*existing| { try existing.mergeFrom(allocator, _pbz_nested); _pbz_nested.deinit(allocator); } else { self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = _pbz_nested; } },\n");
    } else {
        try writer.writeAll("{ const payload = ");
        try writeMessagePayloadRead(file, field, "r", writer);
        try writer.writeAll("; if (self.");
        try writePresenceIdent(field.name, writer);
        try writer.writeAll(" and self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(".len != 0 and payload.len != 0) { const owned_allocator = try self._pbzOwnedAllocator(allocator); const merged = try owned_allocator.alloc(u8, self.");
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

pub fn writeDecodePackedScalarField(field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
    try writer.writeAll("{\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (tag.wire_type == .length_delimited) {\n");
    try writeDecodePackedScalarPayload(field, scalar, writer, depth + 2);
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

pub fn writeDecodePackedScalarPayload(field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("const payload = try r.readBytes();\n");
    if (packedScalarAppendHelperName(scalar)) |helper_name| {
        try indent(writer, depth);
        try writer.writeAll("try pbz.wire.");
        try writer.writeAll(helper_name);
        try writer.writeAll("(allocator, &");
        try writeQuotedIdentWithSuffix(field.name, "_list", writer);
        try writer.writeAll(", payload);\n");
    } else {
        try indent(writer, depth);
        try writer.writeAll("try ");
        try writeQuotedIdentWithSuffix(field.name, "_list", writer);
        try writer.writeAll(".ensureUnusedCapacity(allocator, ");
        try writePackedScalarDecodeCapacityExpr(scalar, "payload", writer);
        try writer.writeAll(");\n");
        try indent(writer, depth);
        try writer.writeAll("var packed_reader = pbz.Reader.init(payload);\n");
        try indent(writer, depth);
        try writer.writeAll("while (!packed_reader.eof()) ");
        try writeQuotedIdentWithSuffix(field.name, "_list", writer);
        try writer.print(".appendAssumeCapacity(try packed_reader.{s}());\n", .{scalarReaderName(scalar)});
    }
}

pub fn packedScalarAppendHelperName(scalar: schema.ScalarType) ?[]const u8 {
    return switch (scalar) {
        .int32 => "appendPackedInt32",
        .int64 => "appendPackedInt64",
        .uint32 => "appendPackedUInt32",
        .uint64 => "appendPackedUInt64",
        .sint32 => "appendPackedSInt32",
        .sint64 => "appendPackedSInt64",
        .bool => "appendPackedBool",
        .fixed32 => "appendPackedFixed32",
        .fixed64 => "appendPackedFixed64",
        .sfixed32 => "appendPackedSFixed32",
        .sfixed64 => "appendPackedSFixed64",
        .float => "appendPackedFloat",
        .double => "appendPackedDouble",
        else => null,
    };
}

pub fn writePackedScalarDecodeCapacityExpr(scalar: schema.ScalarType, payload_expr: []const u8, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .double, .fixed64, .sfixed64 => try writer.print("{s}.len / 8", .{payload_expr}),
        .float, .fixed32, .sfixed32 => try writer.print("{s}.len / 4", .{payload_expr}),
        .int32, .int64, .uint32, .uint64, .sint32, .sint64, .bool => try writer.print("{s}.len", .{payload_expr}),
        .string, .bytes => try writer.writeAll("@compileError(\"non-packable scalar\")"),
    }
}

pub fn writeDecodePackedEnumField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try writer.writeAll("{\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (tag.wire_type == .length_delimited) {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("const payload = try r.readBytes();\n");
    if (field.kind == .enumeration and !enum_emit.enumIsClosed(file, field.kind.enumeration)) {
        try indent(writer, depth + 2);
        try writer.writeAll("try pbz.wire.appendPackedInt32(allocator, &");
        try writeQuotedIdentWithSuffix(field.name, "_list", writer);
        try writer.writeAll(", payload);\n");
    } else {
        try indent(writer, depth + 2);
        try writer.writeAll("var packed_reader = pbz.Reader.init(payload);\n");
        try indent(writer, depth + 2);
        try writer.writeAll("while (!packed_reader.eof()) { const value_start = packed_reader.position(); const value = try packed_reader.readInt32(); const value_end = packed_reader.position();");
        try writer.writeAll(" if (!@This().enumKnown(value, ");
        try enum_emit.writeEnumNumberArray(file, field.kind.enumeration, writer);
        try writer.writeAll(")) { try pbz.wire.appendRawVarintPayload(allocator, &_unknown_fields_list, ");
        try writer.print("{d}", .{field.number});
        try writer.writeAll(", payload[value_start..value_end]); continue; }");
        try writer.writeAll(" try ");
        try writeQuotedIdentWithSuffix(field.name, "_list", writer);
        try writer.writeAll(".append(allocator, value); }\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("} else {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("{ const value = try r.readInt32();");
    if (field.kind == .enumeration and enum_emit.enumIsClosed(file, field.kind.enumeration)) {
        try writer.writeAll(" if (!@This().enumKnown(value, ");
        try enum_emit.writeEnumNumberArray(file, field.kind.enumeration, writer);
        try writer.writeAll(")) { try pbz.wire.appendConsumedRawField(allocator, &_unknown_fields_list, r, r.lastTagStart()); } else { try ");
        try writeQuotedIdentWithSuffix(field.name, "_list", writer);
        try writer.writeAll(".append(allocator, value); } }\n");
    } else {
        try writeEnumClosedCheck(file, field, "value", writer);
        try writer.writeAll(" try ");
        try writeQuotedIdentWithSuffix(field.name, "_list", writer);
        try writer.writeAll(".append(allocator, value); }\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth);
    try writer.writeAll("},\n");
}

pub fn writeDecodeMapField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
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
    if (typedMapMessageValueWithContext(ctx, field)) |_| {
        try indent(writer, depth + 1);
        try writer.writeAll("errdefer entry.value.deinit(allocator);\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("const payload = try r.readBytes();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var entry_reader = try r.nested(payload);\n");
    const can_skip_entry = wireMapEntryCanSkip(file, map_type);
    if (can_skip_entry) {
        try indent(writer, depth + 1);
        try writer.writeAll("var skip_entry = false;\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("while (try entry_reader.nextTag()) |entry_tag| {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("switch (entry_tag.number) {\n");
    try writeMapEntryDecodeAssign(ctx, field, "entry.key", 1, .{ .scalar = map_type.key }, writer, depth + 3);
    try writeMapEntryDecodeAssign(ctx, field, "entry.value", 2, map_type.value.*, writer, depth + 3);
    try indent(writer, depth + 3);
    try writer.writeAll("else => try entry_reader.skipValue(entry_tag),\n");
    try indent(writer, depth + 2);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    if (can_skip_entry) {
        try writer.writeAll("if (skip_entry) { try pbz.wire.appendConsumedRawField(allocator, &_unknown_fields_list, r, r.lastTagStart()); } else ");
    }
    try writer.writeAll("try @This().");
    try writeQuotedIdentWithPrefix(field.name, "putMapEntry_", writer);
    try writer.writeAll("(allocator, &self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(", entry);\n");
    try indent(writer, depth);
    try writer.writeAll("},\n");
}

pub fn wireMapEntryCanSkip(file: *const schema.FileDescriptor, map_type: schema.MapType) bool {
    return map_type.value.* == .enumeration and enum_emit.enumIsClosed(file, map_type.value.enumeration);
}

pub fn writeMapEntryDecodeAssign(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, target: []const u8, number: u29, kind: schema.FieldKind, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    const typed_message_value = if (number == 2) typedMapMessageValueWithContext(ctx, field) else null;
    try indent(writer, depth);
    try writer.print("{d} => {{\n", .{number});
    try indent(writer, depth + 1);
    try writer.print("if (entry_tag.wire_type != .{s}) {{\n", .{@tagName(kind.wireType())});
    try indent(writer, depth + 2);
    try writer.writeAll("try entry_reader.skipValue(entry_tag);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("} else {\n");
    if (kind == .scalar and kind.scalar == .string and fieldUtf8Validation(file, field) == .verify) {
        try indent(writer, depth + 2);
        try writer.writeAll("const value = ");
        try writeEntryReadExpr(kind, "entry_reader", writer);
        try writer.writeAll(";\n");
        try indent(writer, depth + 2);
        try writer.writeAll("if (!pbz.validateUtf8(value)) return error.InvalidUtf8;\n");
        try indent(writer, depth + 2);
        try writer.writeAll(target);
        try writer.writeAll(" = value;\n");
    } else if (kind == .enumeration and enum_emit.enumIsClosed(file, kind.enumeration)) {
        try indent(writer, depth + 2);
        try writer.writeAll("const value = ");
        try writeEntryReadExpr(kind, "entry_reader", writer);
        try writer.writeAll(";\n");
        try indent(writer, depth + 2);
        try writer.writeAll("if (!@This().enumKnown(value, ");
        try enum_emit.writeEnumNumberArray(file, kind.enumeration, writer);
        try writer.writeAll(")) {\n");
        try indent(writer, depth + 3);
        try writer.writeAll("skip_entry = true;\n");
        try indent(writer, depth + 2);
        try writer.writeAll("} else {\n");
        try indent(writer, depth + 3);
        try writer.writeAll(target);
        try writer.writeAll(" = value;\n");
        try indent(writer, depth + 2);
        try writer.writeAll("}\n");
    } else if (typed_message_value) |type_name| {
        try indent(writer, depth + 2);
        try writer.writeAll("const value_payload = try entry_reader.readBytes();\n");
        try indent(writer, depth + 2);
        try writer.writeAll("var value_reader = try entry_reader.nested(value_payload);\n");
        try indent(writer, depth + 2);
        try writer.writeAll(target);
        try writer.writeAll(".deinit(allocator);\n");
        try indent(writer, depth + 2);
        try writer.writeAll(target);
        try writer.writeAll(" = try ");
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
        try writer.writeAll(".decodeFromReader(allocator, &value_reader);\n");
    } else {
        try indent(writer, depth + 2);
        try writer.writeAll(target);
        try writer.writeAll(" = ");
        try writeEntryReadExpr(kind, "entry_reader", writer);
        try writer.writeAll(";\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth);
    try writer.writeAll("},\n");
}

pub fn writeOneofDecodeAssign(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, reader_method: []const u8, writer: *std.Io.Writer) Error!void {
    const oneof_name = field.oneof_name orelse return;
    if (field.kind == .scalar and field.kind.scalar == .string and fieldUtf8Validation(file, field) == .verify) {
        try writer.writeAll("{ const value = try r.");
        try writer.writeAll(reader_method);
        try writer.writeAll("(); if (!pbz.validateUtf8(value)) return error.InvalidUtf8; ");
        try writeOneofDeinitCall(oneof_name, writer);
        try writer.writeAll(" self.");
        try writeQuotedIdent(oneof_name, writer);
        try writer.writeAll(" = .{ .");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = value }; },\n");
        return;
    }
    try writer.writeAll("{ const value = try r.");
    try writer.writeAll(reader_method);
    try writer.writeAll("(); ");
    try writeOneofDeinitCall(oneof_name, writer);
    try writer.writeAll(" self.");
    try writeQuotedIdent(oneof_name, writer);
    try writer.writeAll(" = .{ .");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = value }; },\n");
}

pub fn writeOneofMessageDecodeAssign(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    const file = ctx.file;
    const oneof_name = field.oneof_name orelse return;
    if (typedOneofMessageFieldWithContext(ctx, field)) |type_name| {
        try writer.writeAll("{ const payload = ");
        try writeMessagePayloadRead(file, field, "r", writer);
        try writer.writeAll("; var payload_reader = try r.nested(payload); var _pbz_nested = try ");
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
        try writer.writeAll(".decodeFromReader(allocator, &payload_reader); errdefer _pbz_nested.deinit(allocator); ");
        try writeOneofDeinitCall(oneof_name, writer);
        try writer.writeAll(" self.");
        try writeQuotedIdent(oneof_name, writer);
        try writer.writeAll(" = .{ .");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = _pbz_nested }; },\n");
        return;
    }
    try writer.writeAll("{ const value = ");
    try writeMessagePayloadRead(file, field, "r", writer);
    try writer.writeAll("; switch (self.");
    try writeQuotedIdent(oneof_name, writer);
    try writer.writeAll(") { .");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" => |existing| { const owned_allocator = try self._pbzOwnedAllocator(allocator); const merged = try owned_allocator.alloc(u8, existing.len + value.len); @memcpy(merged[0..existing.len], existing); @memcpy(merged[existing.len..], value); self.");
    try writeQuotedIdent(oneof_name, writer);
    try writer.writeAll(" = .{ .");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = merged }; }, else => { ");
    try writeOneofDeinitCall(oneof_name, writer);
    try writer.writeAll(" self.");
    try writeQuotedIdent(oneof_name, writer);
    try writer.writeAll(" = .{ .");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = value }; } } },\n");
}

pub fn writeOneofEnumDecodeAssign(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    const oneof_name = field.oneof_name orelse return;
    try writer.writeAll("{ const value = try r.readInt32();");
    if (field.kind == .enumeration and enum_emit.enumIsClosed(file, field.kind.enumeration)) {
        try writer.writeAll(" if (!@This().enumKnown(value, ");
        try enum_emit.writeEnumNumberArray(file, field.kind.enumeration, writer);
        try writer.writeAll(")) { try pbz.wire.appendConsumedRawField(allocator, &_unknown_fields_list, r, r.lastTagStart()); } else {");
    } else {
        try writeEnumClosedCheck(file, field, "value", writer);
    }
    try writer.writeAll(" ");
    try writeOneofDeinitCall(oneof_name, writer);
    try writer.writeAll(" self.");
    try writeQuotedIdent(oneof_name, writer);
    try writer.writeAll(" = .{ .");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = value };");
    if (field.kind == .enumeration and enum_emit.enumIsClosed(file, field.kind.enumeration)) try writer.writeAll(" }");
    try writer.writeAll(" },\n");
}

pub fn writeEnumClosedCheck(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    const enum_name = switch (field.kind) {
        .enumeration => |name| name,
        else => return,
    };
    try writeEnumClosedCheckByName(file, enum_name, value_expr, writer);
}

pub fn writeEnumClosedCheckByName(file: *const schema.FileDescriptor, enum_name: []const u8, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    if (!enum_emit.enumIsClosed(file, enum_name)) return;
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

pub fn writeEntryReadExpr(kind: schema.FieldKind, reader_name: []const u8, writer: *std.Io.Writer) Error!void {
    switch (kind) {
        .scalar => |scalar| try writer.print("try {s}.{s}()", .{ reader_name, scalarReaderName(scalar) }),
        .enumeration => try writer.print("try {s}.readInt32()", .{reader_name}),
        .message => try writer.print("try {s}.readBytes()", .{reader_name}),
        else => try writer.writeAll("@compileError(\"unsupported map decode kind\")"),
    }
}

pub fn writeRepeatedAppendPrefix(field: *const schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("try ");
    try writeQuotedIdentWithSuffix(field.name, "_list", writer);
    try writer.writeAll(".append(allocator, ");
}

pub fn scalarReaderName(scalar: schema.ScalarType) []const u8 {
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

pub fn writeMessagePayloadRead(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, reader_name: []const u8, writer: *std.Io.Writer) Error!void {
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
