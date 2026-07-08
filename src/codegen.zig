const std = @import("std");
const schema = @import("schema.zig");
const plugin = @import("plugin.zig");

pub const Error = std.mem.Allocator.Error || std.Io.Writer.Error || plugin.Error;

pub fn generateZigFile(allocator: std.mem.Allocator, file: *const schema.FileDescriptor) Error![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    try out.writer.writeAll("const std = @import(\"std\");\nconst pbz = @import(\"pbz\");\n\n");
    for (file.enums.items) |*enumeration| try writeEnum(enumeration, &out.writer, 0);
    for (file.messages.items) |*message| try writeMessage(message, &out.writer, 0);
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

fn writeMessage(message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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
    for (message.fields.items) |*field| try writeFieldDecl(field, writer, depth + 1);
    if (message.fields.items.len != 0) try writer.writeAll("\n");
    try writeInit(writer, depth + 1);
    try writer.writeAll("\n");
    try writeDeinit(message, writer, depth + 1);
    try writer.writeAll("\n");
    try writeEncode(message, writer, depth + 1);
    try writer.writeAll("\n");
    try writeDecode(message, writer, depth + 1);
    try writer.writeAll("\n");
    for (message.enums.items) |*enumeration| try writeEnum(enumeration, writer, depth + 1);
    for (message.messages.items) |*nested| try writeMessage(nested, writer, depth + 1);
    try indent(writer, depth);
    try writer.writeAll("};\n\n");
}

fn writeFieldDecl(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(": ");
    try writeFieldType(field.*, writer);
    try writer.print(" = {s},\n", .{fieldDefault(field.*)});
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
    try writer.print(" = {s},\n", .{scalarDefault(map_type.key)});
    try indent(writer, depth + 1);
    try writer.writeAll("value: ");
    try writeFieldKindType(map_type.value.*, writer);
    try writer.print(" = {s},\n", .{fieldKindDefault(map_type.value.*)});
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

fn writeEncode(message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn encode(self: @This(), allocator: std.mem.Allocator) ![]u8 {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var w = pbz.Writer.init(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer w.deinit();\n");
    for (message.fields.items) |*field| try writeEncodeField(field, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("return try w.toOwnedSlice();\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeDeinit(message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {\n");
    var has_repeated = false;
    for (message.fields.items) |*field| {
        if (field.cardinality == .repeated and field.kind != .map) {
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
    try writer.writeAll("self.* = undefined;\n");
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

fn writeRepeatedListDecl(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.cardinality != .repeated or field.kind == .map) return;
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
    if (field.cardinality != .repeated or field.kind == .map) return;
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
        else => try writer.writeAll("void"),
    }
}

fn writeDecodeField(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    switch (field.kind) {
        .scalar => |scalar| try writeDecodeScalarField(field, scalar, writer, depth),
        .enumeration => try writeDecodeEnumField(field, writer, depth),
        .message => try writeDecodeMessageField(field, writer, depth),
        else => return,
    }
}

fn writeDecodeScalarField(field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.print("{d} => ", .{field.number});
    if (field.cardinality == .repeated) {
        try writeRepeatedAppendPrefix(field, writer);
        try writer.print("try r.{s}()),\n", .{scalarReaderName(scalar)});
    } else {
        try writer.writeAll("self.");
        try writeQuotedIdent(field.name, writer);
        try writer.print(" = try r.{s}(),\n", .{scalarReaderName(scalar)});
    }
}

fn writeDecodeEnumField(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.print("{d} => ", .{field.number});
    if (field.cardinality == .repeated) {
        try writeRepeatedAppendPrefix(field, writer);
        try writer.writeAll("try r.readInt32()),\n");
    } else {
        try writer.writeAll("self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = try r.readInt32(),\n");
    }
}

fn writeDecodeMessageField(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.print("{d} => ", .{field.number});
    if (field.cardinality == .repeated) {
        try writeRepeatedAppendPrefix(field, writer);
        try writer.writeAll("try r.readBytes()),\n");
    } else {
        try writer.writeAll("self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = try r.readBytes(),\n");
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

fn writeEncodeField(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    switch (field.kind) {
        .scalar => |scalar| try writeEncodeScalarField(field, scalar, writer, depth),
        .enumeration => try writeEncodeEnumField(field, writer, depth),
        .message => try writeEncodeMessageField(field, writer, depth),
        .map => try writeEncodeMapField(field, writer, depth),
        else => return,
    }
}

fn writeEncodeScalarField(field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        try writer.writeAll("for (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(") |item| ");
        try writeScalarWriteCall(field.number, scalar, "item", writer);
        try writer.writeAll(");\n");
    } else {
        try indent(writer, depth);
        if (shouldSkipDefault(scalar)) {
            try writer.writeAll("if (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(defaultSkipCondition(scalar));
        }
        try writeScalarWriteCall(field.number, scalar, "self.", writer);
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(");\n");
    }
}

fn writeEncodeEnumField(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        try writer.writeAll("for (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.print(") |item| try w.writeInt32({d}, item);\n", .{field.number});
    } else {
        try indent(writer, depth);
        try writer.print("try w.writeInt32({d}, self.", .{field.number});
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(");\n");
    }
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
        try writeQuotedIdent(field.name, writer);
        try writer.print(".len != 0) try w.writeMessage({d}, self.", .{field.number});
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
    return switch (scalar) {
        .string, .bytes, .bool => true,
        else => false,
    };
}

fn defaultSkipCondition(scalar: schema.ScalarType) []const u8 {
    return switch (scalar) {
        .string, .bytes => ".len != 0) ",
        .bool => ") ",
        else => "",
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

fn scalarDefault(scalar: schema.ScalarType) []const u8 {
    return switch (scalar) {
        .string, .bytes => "\"\"",
        .bool => "false",
        else => "0",
    };
}

fn fieldKindDefault(kind: schema.FieldKind) []const u8 {
    return switch (kind) {
        .scalar => |scalar| scalarDefault(scalar),
        .enumeration => "0",
        .message => "\"\"",
        else => "{}",
    };
}

fn fieldDefault(field: schema.FieldDescriptor) []const u8 {
    if (field.cardinality == .repeated) return "&.{}";
    return switch (field.kind) {
        .scalar => |scalar| switch (scalar) {
            .string, .bytes => "\"\"",
            .bool => "false",
            else => "0",
        },
        .enumeration => "0",
        .message => "\"\"",
        else => "{}",
    };
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
    try std.testing.expect(std.mem.indexOf(u8, content, "for (self.@\"roles\") |item| try w.writeInt32(2, item);") != null);
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
    try std.testing.expect(std.mem.indexOf(u8, content, "1 => self.@\"id\" = try r.readInt32()") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "2 => self.@\"name\" = try r.readBytes()") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "3 => self.@\"kind\" = try r.readInt32()") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "4 => self.@\"payload\" = try r.readBytes()") != null);
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
