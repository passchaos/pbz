const std = @import("std");
const schema = @import("../schema.zig");

const cg = @import("../codegen.zig");
const Error = cg.Error;
const CodegenContext = cg.CodegenContext;

pub fn writeEnumDescriptorLookup(ctx: *const CodegenContext, enumeration: *const schema.EnumDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (!ctx.emit_descriptor) return;
    var arena = std.heap.ArenaAllocator.init(ctx.allocator);
    defer arena.deinit();
    const full_name = (try cg.enumFullNameForCodegen(arena.allocator(), ctx.file, enumeration)) orelse return;
    try cg.indent(writer, depth);
    try writer.writeAll("/// Look up this enum's descriptor in a decoded file descriptor.\n");
    try cg.indent(writer, depth);
    try writer.writeAll("pub fn descriptor(file: *const pbz.schema.FileDescriptor) ?*const pbz.schema.EnumDescriptor {\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("return file.findEnumDeep(");
    try cg.writeZigStringLiteral(full_name, writer);
    try writer.writeAll(");\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n\n");
}

pub fn writeEnum(ctx: *const CodegenContext, enumeration: *const schema.EnumDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try cg.indent(writer, depth);
    try writer.writeAll("pub const ");
    try cg.writeQuotedIdent(enumeration.name, writer);
    try writer.writeAll(" = enum(i32) {\n");
    for (enumeration.values.items, 0..) |value, index| {
        if (enumFirstValueIndexForNumber(enumeration, value.number) != index) continue;
        try cg.indent(writer, depth + 1);
        try cg.writeQuotedIdent(value.name, writer);
        try writer.print(" = {d},\n", .{value.number});
    }
    for (enumeration.values.items, 0..) |value, index| {
        const first_index = enumFirstValueIndexForNumber(enumeration, value.number) orelse continue;
        if (first_index == index) continue;
        const first = &enumeration.values.items[first_index];
        try cg.indent(writer, depth + 1);
        try writer.writeAll("pub const ");
        try cg.writeQuotedIdent(value.name, writer);
        try writer.writeAll(" = @This().");
        try cg.writeQuotedIdent(first.name, writer);
        try writer.writeAll(";\n");
    }
    try writeEnumHelpers(enumeration, writer, depth + 1);
    try writeEnumDescriptorLookup(ctx, enumeration, writer, depth + 1);
    try cg.indent(writer, depth);
    try writer.writeAll("};\n\n");
}

pub fn writeEnumHelpers(enumeration: *const schema.EnumDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try cg.indent(writer, depth);
    try writer.writeAll("pub fn fromInt(value: i32) ?@This() {\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("return switch (value) {\n");
    for (enumeration.values.items, 0..) |value, index| {
        if (enumFirstValueIndexForNumber(enumeration, value.number) != index) continue;
        try cg.indent(writer, depth + 2);
        try writer.print("{d} => .", .{value.number});
        try cg.writeQuotedIdent(value.name, writer);
        try writer.writeAll(",\n");
    }
    try cg.indent(writer, depth + 2);
    try writer.writeAll("else => null,\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("};\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n");

    try cg.indent(writer, depth);
    try writer.writeAll("pub fn toInt(self: @This()) i32 {\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("return @intFromEnum(self);\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n");

    try cg.indent(writer, depth);
    try writer.writeAll("pub fn protoName(self: @This()) []const u8 {\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("return switch (self) {\n");
    for (enumeration.values.items, 0..) |value, index| {
        if (enumFirstValueIndexForNumber(enumeration, value.number) != index) continue;
        try cg.indent(writer, depth + 2);
        try writer.writeByte('.');
        try cg.writeQuotedIdent(value.name, writer);
        try writer.writeAll(" => ");
        try cg.writeZigStringLiteral(value.name, writer);
        try writer.writeAll(",\n");
    }
    try cg.indent(writer, depth + 1);
    try writer.writeAll("};\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n");

    try cg.indent(writer, depth);
    try writer.writeAll("pub fn fromName(name: []const u8) ?@This() {\n");
    for (enumeration.values.items) |value| {
        const first_index = enumFirstValueIndexForNumber(enumeration, value.number) orelse continue;
        const first = &enumeration.values.items[first_index];
        try cg.indent(writer, depth + 1);
        try writer.writeAll("if (std.mem.eql(u8, name, ");
        try cg.writeZigStringLiteral(value.name, writer);
        try writer.writeAll(")) return .");
        try cg.writeQuotedIdent(first.name, writer);
        try writer.writeAll(";\n");
    }
    try cg.indent(writer, depth + 1);
    try writer.writeAll("return null;\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n");

    try cg.indent(writer, depth);
    try writer.writeAll("pub fn jsonParse(value: pbz.json.Value) !@This() {\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("return switch (value) {\n");
    try cg.indent(writer, depth + 2);
    try writer.writeAll(".string => |name| fromName(name) orelse error.InvalidEnumValue,\n");
    try cg.indent(writer, depth + 2);
    try writer.writeAll(".integer => |number| fromInt(std.math.cast(i32, number) orelse return error.Overflow) orelse error.InvalidEnumValue,\n");
    try cg.indent(writer, depth + 2);
    try writer.writeAll(".number_string => |text| fromInt(try std.fmt.parseInt(i32, text, 10)) orelse error.InvalidEnumValue,\n");
    try cg.indent(writer, depth + 2);
    try writer.writeAll("else => error.TypeMismatch,\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("};\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n");

    try cg.indent(writer, depth);
    try writer.writeAll("pub fn textParse(value: []const u8) !@This() {\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("if (fromName(value)) |known| return known;\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("return fromInt(try std.fmt.parseInt(i32, value, 10)) orelse error.InvalidEnumValue;\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n");

    try cg.indent(writer, depth);
    try writer.writeAll("pub fn textFormat(self: @This(), writer: *std.Io.Writer) !void {\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("try writer.writeAll(self.protoName());\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n");

    try cg.indent(writer, depth);
    try writer.writeAll("pub fn jsonStringify(self: @This(), writer: *std.Io.Writer) !void {\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("try std.json.Stringify.value(self.protoName(), .{}, writer);\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn enumFirstValueIndexForNumber(enumeration: *const schema.EnumDescriptor, number: i32) ?usize {
    for (enumeration.values.items, 0..) |value, index| {
        if (value.number == number) return index;
    }
    return null;
}
