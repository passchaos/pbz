const std = @import("std");
const schema = @import("schema.zig");
const plugin = @import("plugin.zig");

pub const Error = std.mem.Allocator.Error || std.Io.Writer.Error || plugin.Error;

pub fn generateZigFile(allocator: std.mem.Allocator, file: *const schema.FileDescriptor) Error![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    try out.writer.writeAll("const std = @import(\"std\");\nconst pbz = @import(\"pbz\");\n\n");
    for (file.enums.items) |*enumeration| try writeEnum(enumeration, &out.writer, 0);
    for (file.messages.items) |*message| try writeMessage(file, message, &out.writer, 0);
    return try out.toOwnedSlice();
}

pub fn generatePluginResponse(allocator: std.mem.Allocator, files: []const *const schema.FileDescriptor) Error![]u8 {
    var response_files = try allocator.alloc(plugin.CodeGeneratorResponse.File, files.len);
    defer {
        for (response_files) |file| allocator.free(file.content);
        allocator.free(response_files);
    }
    for (files, 0..) |file, i| {
        const content = try generateZigFile(allocator, file);
        const name = try outputName(allocator, file.name);
        defer allocator.free(name);
        response_files[i] = .{ .name = name, .content = content };
    }
    return try (plugin.CodeGeneratorResponse{ .files = response_files }).encode(allocator);
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
        if (field.oneof_name == null) try writeFieldDecl(field, writer, depth + 1);
    }
    for (message.oneofs.items) |oneof| try writeOneofField(oneof, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("@\"_json_arena\": ?*std.heap.ArenaAllocator = null,\n");
    if (message.fields.items.len != 0) try writer.writeAll("\n");
    try writeInit(writer, depth + 1);
    try writer.writeAll("\n");
    try writeDeinit(message, writer, depth + 1);
    try writer.writeAll("\n");
    try writeEncode(file, message, writer, depth + 1);
    try writer.writeAll("\n");
    try writeEncodeInitialized(writer, depth + 1);
    try writer.writeAll("\n");
    try writeDecode(message, writer, depth + 1);
    try writer.writeAll("\n");
    try writeDecodeInitialized(writer, depth + 1);
    try writer.writeAll("\n");
    try writeMissingRequiredFieldName(message, writer, depth + 1);
    try writer.writeAll("\n");
    try writeValidateRequired(writer, depth + 1);
    try writer.writeAll("\n");
    try writeJsonMethods(file, message, writer, depth + 1);
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

fn writeEncodeOneof(message: *const schema.MessageDescriptor, oneof: schema.OneofDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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
                try writeOneofValueEncode(field, "value", writer);
                try writer.writeAll(",\n");
            }
        }
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeOneofValueEncode(field: *const schema.FieldDescriptor, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    switch (field.kind) {
        .scalar => |scalar| try writeScalarWriteCall(field.number, scalar, value_expr, writer),
        .enumeration => try writer.print("try w.writeInt32({d}, {s}", .{ field.number, value_expr }),
        .message => try writer.print("try w.writeMessage({d}, {s}", .{ field.number, value_expr }),
        else => try writer.writeAll("@compileError(\"unsupported oneof field\")"),
    }
    try writer.writeAll(")");
}

fn writeFieldDecl(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(": ");
    try writeFieldType(field.*, writer);
    try writer.writeAll(" = ");
    try writeFieldDefault(field.*, writer);
    try writer.writeAll(",\n");
    if (hasPresence(field.*)) {
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
    for (message.oneofs.items) |oneof| try writeEncodeOneof(message, oneof, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("return try w.toOwnedSlice();\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeEncodeInitialized(writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn encodeInitialized(self: @This(), allocator: std.mem.Allocator) ![]u8 {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.validateRequired();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try self.encode(allocator);\n");
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
        if (field.cardinality == .required) {
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

fn writeValidateRequired(writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn validateRequired(self: @This()) !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (self.missingRequiredFieldName() != null) return error.MissingRequiredField;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeDecode(message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) !@This() {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var self = @This().init();\n");
    for (message.fields.items) |*field| try writeRepeatedListDecl(field, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("var r = pbz.Reader.init(bytes);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("while (try r.nextTag()) |tag| {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("switch (tag.number) {\n");
    for (message.fields.items) |*field| try writeDecodeField(field, writer, depth + 3);
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

fn writeDecodeInitialized(writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn decodeInitialized(allocator: std.mem.Allocator, bytes: []const u8) !@This() {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var self = try @This().decode(allocator, bytes);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer self.deinit(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.validateRequired();\n");
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
        .message => try writer.writeAll("[]const u8"),
        .map => try writeQuotedIdentWithSuffix(field.name, "Entry", writer),
        else => try writer.writeAll("void"),
    }
}

fn writeDecodeField(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    switch (field.kind) {
        .scalar => |scalar| try writeDecodeScalarField(field, scalar, writer, depth),
        .enumeration => try writeDecodeEnumField(field, writer, depth),
        .message => try writeDecodeMessageField(field, writer, depth),
        .map => try writeDecodeMapField(field, writer, depth),
        else => return,
    }
}

fn writeDecodeScalarField(field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.print("{d} => ", .{field.number});
    if (field.cardinality == .repeated) {
        if (scalar.packable()) {
            try writeDecodePackedScalarField(field, scalar, writer, depth);
        } else {
            try writeRepeatedAppendPrefix(field, writer);
            try writer.print("try r.{s}()),\n", .{scalarReaderName(scalar)});
        }
    } else if (field.oneof_name != null) {
        try writeOneofDecodeAssign(field, scalarReaderName(scalar), writer);
    } else {
        try writer.writeAll("{ self.");
        try writeQuotedIdent(field.name, writer);
        try writer.print(" = try r.{s}();", .{scalarReaderName(scalar)});
        try writeSetPresence(field, writer);
        try writer.writeAll(" },\n");
    }
}

fn writeDecodeEnumField(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.print("{d} => ", .{field.number});
    if (field.cardinality == .repeated) {
        try writeDecodePackedEnumField(field, writer, depth);
    } else if (field.oneof_name != null) {
        try writeOneofDecodeAssign(field, "readInt32", writer);
    } else {
        try writer.writeAll("{ self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = try r.readInt32();");
        try writeSetPresence(field, writer);
        try writer.writeAll(" },\n");
    }
}

fn writeDecodeMessageField(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.print("{d} => ", .{field.number});
    if (field.cardinality == .repeated) {
        try writeRepeatedAppendPrefix(field, writer);
        try writer.writeAll("try r.readBytes()),\n");
    } else if (field.oneof_name != null) {
        try writeOneofDecodeAssign(field, "readBytes", writer);
    } else {
        try writer.writeAll("{ self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = try r.readBytes();");
        try writeSetPresence(field, writer);
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

fn writeDecodePackedEnumField(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try writer.writeAll("{\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (tag.wire_type == .length_delimited) {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("var packed_reader = pbz.Reader.init(try r.readBytes());\n");
    try indent(writer, depth + 2);
    try writer.writeAll("while (!packed_reader.eof()) try ");
    try writeQuotedIdentWithSuffix(field.name, "_list", writer);
    try writer.writeAll(".append(allocator, try packed_reader.readInt32());\n");
    try indent(writer, depth + 1);
    try writer.writeAll("} else {\n");
    try indent(writer, depth + 2);
    try writeRepeatedAppendPrefix(field, writer);
    try writer.writeAll("try r.readInt32());\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth);
    try writer.writeAll("},\n");
}

fn writeDecodeMapField(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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
    try indent(writer, depth + 3);
    try writer.writeAll("1 => entry.key = ");
    try writeEntryReadExpr(.{ .scalar = map_type.key }, "entry_reader", writer);
    try writer.writeAll(",\n");
    try indent(writer, depth + 3);
    try writer.writeAll("2 => entry.value = ");
    try writeEntryReadExpr(map_type.value.*, "entry_reader", writer);
    try writer.writeAll(",\n");
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

fn writeOneofDecodeAssign(field: *const schema.FieldDescriptor, reader_method: []const u8, writer: *std.Io.Writer) Error!void {
    const oneof_name = field.oneof_name orelse return;
    try writer.writeAll("self.");
    try writeQuotedIdent(oneof_name, writer);
    try writer.writeAll(" = .{ .");
    try writeQuotedIdent(field.name, writer);
    try writer.print(" = try r.{s}() }},\n", .{reader_method});
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
        .message => try writeEncodeMessageField(field, writer, depth),
        .map => try writeEncodeMapField(field, writer, depth),
        else => return,
    }
}

fn writeEncodeScalarField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.cardinality == .repeated) {
        if (field.resolvedPacked(file)) {
            try writeEncodePackedScalarField(field, scalar, writer, depth);
        } else {
            try indent(writer, depth);
            try writer.writeAll("for (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(") |item| ");
            try writeScalarWriteCall(field.number, scalar, "item", writer);
            try writer.writeAll(");\n");
        }
    } else {
        try indent(writer, depth);
        if (hasPresence(field.*)) {
            try writer.writeAll("if (self.");
            try writePresenceIdent(field.name, writer);
            try writer.writeAll(") ");
        } else if (shouldSkipDefault(scalar)) {
            try writer.writeAll("if (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(defaultSkipCondition(scalar));
        }
        try writeScalarWriteCall(field.number, scalar, "self.", writer);
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(");\n");
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
        if (hasPresence(field.*)) {
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

fn writeEncodeMessageField(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        try writer.writeAll("for (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.print(") |item| try w.writeMessage({d}, item);\n", .{field.number});
    } else {
        try indent(writer, depth);
        try writer.writeAll("if (self.");
        if (hasPresence(field.*)) {
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

fn writeEncodeMapField(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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
    try indent(writer, depth + 1);
    try writeKindWriteCall(1, .{ .scalar = map_type.key }, "entry.key", "entry_writer", writer);
    try writer.writeAll(");\n");
    try indent(writer, depth + 1);
    try writeKindWriteCall(2, map_type.value.*, "entry.value", "entry_writer", writer);
    try writer.writeAll(");\n");
    try indent(writer, depth + 1);
    try writer.print("try w.writeMessage({d}, entry_writer.slice());\n", .{field.number});
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeKindWriteCall(number: u29, kind: schema.FieldKind, value_expr: []const u8, writer_name: []const u8, writer: *std.Io.Writer) Error!void {
    switch (kind) {
        .scalar => |scalar| try writer.print("try {s}.{s}({d}, {s}", .{ writer_name, scalarWriterName(scalar), number, value_expr }),
        .enumeration => try writer.print("try {s}.writeInt32({d}, {s}", .{ writer_name, number, value_expr }),
        .message => try writer.print("try {s}.writeMessage({d}, {s}", .{ writer_name, number, value_expr }),
        else => try writer.writeAll("@compileError(\"unsupported map field kind\")"),
    }
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
        .message => try writer.writeAll("[]const u8"),
        else => try writer.writeAll("void"),
    }
}

fn fieldType(field: schema.FieldDescriptor) []const u8 {
    const base = switch (field.kind) {
        .scalar => |scalar| scalarZigType(scalar),
        .enumeration => "i32",
        .message => "[]const u8",
        else => "void",
    };
    if (field.cardinality != .repeated) return base;
    return switch (field.kind) {
        .scalar => |scalar| repeatedScalarZigType(scalar),
        .enumeration => "[]const i32",
        .message => "[]const []const u8",
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
        .message => try writer.writeAll("\"\""),
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

fn writeJsonMethods(file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn jsonStringifyAlloc(self: @This(), allocator: std.mem.Allocator) ![]u8 {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var out: std.Io.Writer.Allocating = .init(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer out.deinit();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.jsonStringify(&out.writer);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try out.toOwnedSlice();\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn jsonStringify(self: @This(), writer: *std.Io.Writer) !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try writer.writeAll(\"{\");\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var first = true;\n");
    for (message.fields.items) |*field| {
        if (field.oneof_name == null) try writeJsonField(field, writer, depth + 1);
    }
    for (message.oneofs.items) |oneof| try writeJsonOneof(message, oneof, writer, depth + 1);
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
    try writer.writeAll("fn jsonFillFromValue(self: *@This(), allocator: std.mem.Allocator, arena_allocator: std.mem.Allocator, json_value: std.json.Value) !void {\n");
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
    try indent(writer, depth + 2);
    try writer.writeAll("if (entry.value_ptr.* == .null) continue;\n");
    try indent(writer, depth + 2);
    try writer.writeAll("const key = entry.key_ptr.*;\n");
    try indent(writer, depth + 2);
    try writer.writeAll("const value = entry.value_ptr.*;\n");
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

fn messageJsonParseUsesArenaAllocator(message: *const schema.MessageDescriptor) bool {
    for (message.fields.items) |field| {
        switch (field.kind) {
            .scalar => |scalar| if (scalar == .bytes) return true,
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
    return field.kind == .map or (field.cardinality == .repeated and (field.kind == .scalar or field.kind == .enumeration));
}

fn writeJsonParseField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    switch (field.kind) {
        .scalar, .enumeration => {},
        .map => return try writeJsonParseMapField(file, field, writer, depth),
        else => return,
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
        try writer.writeAll(" = try list.toOwnedSlice(allocator);\n");
    } else {
        try indent(writer, depth + 1);
        try writer.writeAll("self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = ");
        try writeJsonParseValueExpr(file, field.kind, "value", "arena_allocator", writer);
        try writer.writeAll(";\n");
        if (hasPresence(field.*)) {
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
    if (!jsonMapValueSupported(map_type.value.*)) return;
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
    try writeJsonParseValueExpr(file, map_type.value.*, "map_entry.value_ptr.*", "arena_allocator", writer);
    try writer.writeAll(" });\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = try list.toOwnedSlice(allocator);\n");
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
        .scalar, .enumeration => {},
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
    try writeJsonParseValueExpr(file, field.kind, "value", "arena_allocator", writer);
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
            try writer.writeAll(")");
        },
        else => try writer.writeAll("@compileError(\"unsupported JSON parse field kind\")"),
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
        \\fn jsonEnum(value: std.json.Value, comptime names: []const []const u8, comptime numbers: []const i32) !i32 {
        \\    return switch (value) {
        \\        .integer => |v| std.math.cast(i32, v) orelse error.Overflow,
        \\        .number_string => |text| try std.fmt.parseInt(i32, text, 10),
        \\        .string => |text| {
        \\            inline for (names, 0..) |name, i| {
        \\                if (std.mem.eql(u8, text, name)) return numbers[i];
        \\            }
        \\            return std.fmt.parseInt(i32, text, 10) catch error.InvalidEnumValue;
        \\        },
        \\        else => error.TypeMismatch,
        \\    };
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

fn writeJsonField(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    switch (field.kind) {
        .scalar => |scalar| try writeJsonScalarField(field, scalar, writer, depth),
        .enumeration => try writeJsonEnumField(field, writer, depth),
        .map => try writeJsonMapField(field, writer, depth),
        else => return,
    }
}

fn writeJsonPrefix(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("if (!first) try writer.writeAll(\",\"); first = false;\n");
    try indent(writer, depth);
    try writer.print("try writer.writeAll(\"\\\"{s}\\\":\");\n", .{field.name});
}

fn writeJsonScalarField(field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
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
        if (hasPresence(field.*)) {
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

fn writeJsonEnumField(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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
        try writer.writeAll(", 0..) |item, i| { if (i != 0) try writer.writeAll(\",\"); try writer.print(\"{d}\", .{item}); }\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try writer.writeAll(\"]\");\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");
    } else {
        try indent(writer, depth);
        if (hasPresence(field.*)) {
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
        try writer.writeAll("try writer.print(\"{d}\", .{self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll("});\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");
    }
}

fn writeJsonMapField(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const map_type = switch (field.kind) {
        .map => |map| map,
        else => return,
    };
    if (!jsonMapValueSupported(map_type.value.*)) return;
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
    try writeJsonMapEntryValue(map_type.value.*, "entry.value", writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try writer.writeAll(\"}\");\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn jsonMapValueSupported(kind: schema.FieldKind) bool {
    return kind == .scalar or kind == .enumeration;
}

fn writeJsonMapKeyValue(scalar: schema.ScalarType, key_expr: []const u8, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .string => try writer.print("try std.json.Stringify.value({s}, .{{}}, writer)", .{key_expr}),
        .bool => try writer.print("try writer.writeAll(if ({s}) \"\\\"true\\\"\" else \"\\\"false\\\"\")", .{key_expr}),
        .int32, .int64, .uint32, .uint64, .sint32, .sint64, .fixed32, .fixed64, .sfixed32, .sfixed64 => try writer.print("try writer.print(\"\\\"{{d}}\\\"\", .{{{s}}})", .{key_expr}),
        .double, .float, .bytes => try writer.writeAll("@compileError(\"invalid map key\")"),
    }
}

fn writeJsonMapEntryValue(kind: schema.FieldKind, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    switch (kind) {
        .scalar => |scalar| try writeJsonScalarValue(scalar, value_expr, writer),
        .enumeration => try writer.print("try writer.print(\"{{d}}\", .{{{s}}})", .{value_expr}),
        else => try writer.writeAll("@compileError(\"unsupported map JSON value\")"),
    }
}

fn writeJsonOneof(message: *const schema.MessageDescriptor, oneof: schema.OneofDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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
                    .enumeration => {
                        try writeJsonPrefix(field, writer, depth + 2);
                        try indent(writer, depth + 2);
                        try writer.writeAll("try writer.print(\"{d}\", .{value});\n");
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

fn hasPresence(field: schema.FieldDescriptor) bool {
    return field.cardinality == .optional or field.cardinality == .required or field.proto3_optional;
}

fn writePresenceIdent(name: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("@\"has_");
    for (name) |c| {
        if (c == '\\' or c == '"') try writer.writeByte('\\');
        try writer.writeByte(c);
    }
    try writer.writeAll("\"");
}

fn writeSetPresence(field: *const schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    if (hasPresence(field.*)) {
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

test "codegen emits protoc response" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator, "syntax = \"proto3\"; message A { int32 id = 1; }");
    defer file.deinit();
    file.name = "a.proto";
    const files = [_]*const schema.FileDescriptor{&file};
    const response = try generatePluginResponse(allocator, &files);
    defer allocator.free(response);
    try std.testing.expect(response.len != 0);
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
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.@\"name\".len != 0) try w.writeString(2, self.@\"name\")") != null);
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
    try std.testing.expect(std.mem.indexOf(u8, content, "while (!packed_reader.eof()) try @\"kinds_list\".append(allocator, try packed_reader.readInt32())") != null);
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
        \\message Parent { Child child = 1; repeated Child children = 2; }
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "@\"child\": []const u8 = \"\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "@\"children\": []const []const u8 = &.{}") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.@\"child\".len != 0) try w.writeMessage(1, self.@\"child\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (self.@\"children\") |item| try w.writeMessage(2, item);") != null);
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
}

test "codegen emits map JSON stringify and parse helpers" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message M {
        \\  map<string, int32> counts = 1;
        \\  map<int32, string> names = 2;
        \\  map<bool, Kind> flags = 3;
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
    try std.testing.expect(std.mem.indexOf(u8, content, "const object_value = switch (value) { .object => |map_object| map_object, else => return error.TypeMismatch }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try list.append(allocator, .{ .key = map_entry.key_ptr.*, .value = try @This().jsonInt(i32, map_entry.value_ptr.*) })") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try std.fmt.parseInt(i32, map_entry.key_ptr.*, 10)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try @This().jsonMapKeyBool(map_entry.key_ptr.*)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try @This().jsonEnum(map_entry.value_ptr.*, &.{\"UNKNOWN\", \"ADMIN\"}, &.{0, 1})") != null);
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
    try std.testing.expect(std.mem.indexOf(u8, content, "1 => { self.@\"id\" = try r.readInt32(); }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "2 => { self.@\"name\" = try r.readBytes(); }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "3 => { self.@\"kind\" = try r.readInt32(); }") != null);
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
    try std.testing.expect(std.mem.indexOf(u8, content, "try @\"kinds_list\".append(allocator, try r.readInt32())") != null);
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
    try std.testing.expect(std.mem.indexOf(u8, content, "1 => entry.key = try entry_reader.readBytes()") != null);
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
        \\  oneof choice {
        \\    string alias = 8;
        \\    int32 code = 9;
        \\  }
        \\}
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn jsonStringifyAlloc(self: @This(), allocator: std.mem.Allocator) ![]u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn jsonStringify(self: @This(), writer: *std.Io.Writer) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.writeAll(\"\\\"id\\\":\");") != null);
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
    try std.testing.expect(std.mem.indexOf(u8, content, "fn jsonFillFromValue(self: *@This(), allocator: std.mem.Allocator, arena_allocator: std.mem.Allocator, json_value: std.json.Value) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.@\"id\" = try @This().jsonInt(i32, value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.@\"raw\" = try @This().jsonBytes(arena_allocator, value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.@\"kind\" = try @This().jsonEnum(value, &.{\"UNKNOWN\", \"ADMIN\"}, &.{0, 1});") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (array.items) |item| try list.append(allocator, try @This().jsonString(item));") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.@\"choice\" = .{ .@\"alias\" = try @This().jsonString(value) };") != null);
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
    try std.testing.expect(std.mem.indexOf(u8, content, ".@\"name\" => |value| try w.writeString(1, value)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "1 => self.@\"pick\" = .{ .@\"name\" = try r.readBytes() }") != null);
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
