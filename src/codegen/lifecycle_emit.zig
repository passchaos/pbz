const schema = @import("../schema.zig");
const std = @import("std");
const wire = @import("../wire.zig");
const cg = @import("../codegen.zig");
const CodegenContext = cg.CodegenContext;
const Error = cg.Error;
const hasPresence = cg.hasPresence;
const indent = cg.indent;
const typedMapMessageValueWithContext = cg.typedMapMessageValueWithContext;
const typedOneofMessageFieldWithContext = cg.typedOneofMessageFieldWithContext;
const typedRepeatedMessageFieldWithContext = cg.typedRepeatedMessageFieldWithContext;
const typedSingularMessageFieldWithContext = cg.typedSingularMessageFieldWithContext;
const writeMessageTypeReferenceWithContext = cg.writeMessageTypeReferenceWithContext;
const writeOneofDeinitCall = cg.writeOneofDeinitCall;
const writePresenceIdent = cg.writePresenceIdent;
const writeQuotedIdent = cg.writeQuotedIdent;
const writeQuotedIdentWithPrefix = cg.writeQuotedIdentWithPrefix;
const writeQuotedIdentWithSuffix = cg.writeQuotedIdentWithSuffix;
const writeRepeatedElementType = cg.writeRepeatedElementType;
const writeScalarSkipCondition = cg.writeScalarSkipCondition;
const oneofHasTypedMessageWithContext = cg.emit_helpers.oneofHasTypedMessageWithContext;

pub fn writeMergeFrom(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("/// Merge other into self. String/bytes payloads, raw message payloads,\n");
    try indent(writer, depth);
    try writer.writeAll("/// and map keys/values are deep-copied, so other remains independently valid.\n");
    try indent(writer, depth);
    try writer.writeAll("pub fn mergeFrom(self: *@This(), allocator: std.mem.Allocator, other: @This()) anyerror!void {\n");
    if (mergeUsesOwnedAllocator(ctx, message)) {
        try indent(writer, depth + 1);
        try writer.writeAll("const _pbz_owned_allocator = try self._pbzOwnedAllocator(allocator);\n");
    }
    for (message.fields.items) |*field| {
        if (field.oneof_name == null) try writeMergeField(ctx, field, writer, depth + 1);
    }
    for (message.oneofs.items) |oneof| try writeMergeOneof(ctx, message, oneof, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("try pbz.wire.appendRawFieldsClone(allocator, &self._unknown_fields, other._unknown_fields);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn mergeUsesOwnedAllocator(ctx: *const CodegenContext, message: *const schema.MessageDescriptor) bool {
    for (message.fields.items) |*field| {
        if (field.oneof_name == null and mergeFieldUsesOwnedAllocator(ctx, field)) return true;
    }
    for (message.oneofs.items) |oneof| {
        for (message.fields.items) |*field| {
            if (field.oneof_name) |name| {
                if (std.mem.eql(u8, name, oneof.name) and mergeFieldUsesOwnedAllocator(ctx, field)) return true;
            }
        }
    }
    return false;
}

pub fn mergeFieldUsesOwnedAllocator(ctx: *const CodegenContext, field: *const schema.FieldDescriptor) bool {
    if (field.kind == .map) {
        const map_type = field.kind.map;
        if (map_type.key == .string) return true;
        const value_kind = map_type.value.*;
        if (value_kind == .scalar and (value_kind.scalar == .string or value_kind.scalar == .bytes)) return true;
        if ((value_kind == .message or value_kind == .group) and typedMapMessageValueWithContext(ctx, field) == null) return true;
        return false;
    }
    if (field.kind == .scalar and (field.kind.scalar == .string or field.kind.scalar == .bytes)) return true;
    if (field.kind == .message or field.kind == .group) {
        const typed = if (field.cardinality == .repeated)
            typedRepeatedMessageFieldWithContext(ctx, field)
        else if (field.oneof_name != null)
            typedOneofMessageFieldWithContext(ctx, field)
        else
            typedSingularMessageFieldWithContext(ctx, field);
        return typed == null;
    }
    return false;
}

pub fn writeMergeField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    if (field.kind == .map) return try writeMergeMapField(ctx, field, writer, depth);
    if (field.cardinality == .repeated) return try writeMergeRepeatedField(ctx, field, writer, depth);
    switch (field.kind) {
        .message, .group => try writeMergeSingularMessageField(ctx, field, writer, depth),
        .scalar => |scalar| try writeMergeSingularScalarField(file, field, scalar, writer, depth),
        .enumeration => try writeMergeSingularEnumField(file, field, writer, depth),
        else => {},
    }
}

pub fn writeMergeRepeatedField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const typed_message = typedRepeatedMessageFieldWithContext(ctx, field);
    const raw_message = typed_message == null and (field.kind == .message or field.kind == .group);
    const string_or_bytes = field.kind == .scalar and (field.kind.scalar == .string or field.kind.scalar == .bytes);
    const needs_dup = raw_message or string_or_bytes;
    try indent(writer, depth);
    try writer.writeAll("if (other.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".len != 0) {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const old = self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("{\n");
    try indent(writer, depth + 2);
    try writer.writeAll("const merged = try allocator.alloc(");
    if (typed_message) |type_name| {
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    } else {
        try writeRepeatedElementType(field.*, writer);
    }
    try writer.writeAll(", old.len + other.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".len);\n");
    try indent(writer, depth + 2);
    try writer.writeAll("errdefer allocator.free(merged);\n");
    try indent(writer, depth + 2);
    try writer.writeAll("@memcpy(merged[0..old.len], old);\n");
    if (typed_message != null) {
        try indent(writer, depth + 2);
        try writer.writeAll("var _pbz_cloned: usize = 0;\n");
        try indent(writer, depth + 2);
        try writer.writeAll("errdefer for (merged[old.len..old.len + _pbz_cloned]) |*item| item.deinit(allocator);\n");
        try indent(writer, depth + 2);
        try writer.writeAll("for (other.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(", 0..) |item, i| { merged[old.len + i] = try item.cloneOwned(allocator); _pbz_cloned += 1; }\n");
    } else if (needs_dup) {
        try indent(writer, depth + 2);
        try writer.writeAll("for (other.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(", 0..) |item, i| merged[old.len + i] = try pbz.wire.dupeBytes(_pbz_owned_allocator,item);\n");
    } else {
        try indent(writer, depth + 2);
        try writer.writeAll("@memcpy(merged[old.len..], other.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(");\n");
    }
    try indent(writer, depth + 2);
    try writer.writeAll("self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = merged;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (old.len != 0) allocator.free(old);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeMergeMapField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const map_type = switch (field.kind) {
        .map => |map| map,
        else => return,
    };
    const typed_message_value = typedMapMessageValueWithContext(ctx, field);
    const raw_message_value = typed_message_value == null and (map_type.value.* == .message or map_type.value.* == .group);
    const string_key = map_type.key == .string;
    const string_value = map_type.value.* == .scalar and (map_type.value.scalar == .string or map_type.value.scalar == .bytes);
    try indent(writer, depth);
    try writer.writeAll("const ");
    try writeQuotedIdentWithSuffix(field.name, "_other_count", writer);
    try writer.writeAll(" = other.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".count();\n");
    try indent(writer, depth);
    try writer.writeAll("if (");
    try writeQuotedIdentWithSuffix(field.name, "_other_count", writer);
    try writer.writeAll(" != 0) {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".ensureUnusedCapacity(allocator, ");
    try writeQuotedIdentWithSuffix(field.name, "_other_count", writer);
    try writer.writeAll(");\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var other_it = other.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".iterator();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("while (other_it.next()) |entry| {\n");
    if (string_key) {
        try indent(writer, depth + 2);
        try writer.writeAll("const key = try pbz.wire.dupeBytes(_pbz_owned_allocator,entry.key_ptr.*);\n");
    } else {
        try indent(writer, depth + 2);
        try writer.writeAll("const key = entry.key_ptr.*;\n");
    }
    if (typed_message_value) |_| {
        try indent(writer, depth + 2);
        try writer.writeAll("const value = try entry.value_ptr.cloneOwned(allocator);\n");
    } else if (string_value or raw_message_value) {
        try indent(writer, depth + 2);
        try writer.writeAll("const value = try pbz.wire.dupeBytes(_pbz_owned_allocator,entry.value_ptr.*);\n");
    } else {
        try indent(writer, depth + 2);
        try writer.writeAll("const value = entry.value_ptr.*;\n");
    }
    try indent(writer, depth + 2);
    try writer.writeAll("const result = self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".getOrPutAssumeCapacity(key);\n");
    if (typed_message_value != null) {
        try indent(writer, depth + 2);
        try writer.writeAll("if (result.found_existing) result.value_ptr.deinit(allocator);\n");
    }
    try indent(writer, depth + 2);
    try writer.writeAll("result.value_ptr.* = value;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeMergeSingularMessageField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (typedSingularMessageFieldWithContext(ctx, field)) |_| {
        try indent(writer, depth);
        try writer.writeAll("if (other.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(") |other_value| {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("if (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(") |*self_value| { try self_value.mergeFrom(allocator, other_value); } else { self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = try other_value.cloneOwned(allocator); }\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");
        return;
    }
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
    try writer.writeAll("const owned_allocator = try self._pbzOwnedAllocator(allocator);\n");
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
    try writer.writeAll(" = try pbz.wire.dupeBytes(_pbz_owned_allocator,other.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(");\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("self.");
    try writePresenceIdent(field.name, writer);
    try writer.writeAll(" = true;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeMergeSingularScalarField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
    const needs_dup = scalar == .string or scalar == .bytes;
    try indent(writer, depth);
    if (hasPresence(file, field.*)) {
        try writer.writeAll("if (other.");
        try writePresenceIdent(field.name, writer);
        try writer.writeAll(") { self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = ");
        if (needs_dup) {
            try writer.writeAll("try pbz.wire.dupeBytes(_pbz_owned_allocator,other.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(")");
        } else {
            try writer.writeAll("other.");
            try writeQuotedIdent(field.name, writer);
        }
        try writer.writeAll("; self.");
        try writePresenceIdent(field.name, writer);
        try writer.writeAll(" = true; }\n");
    } else {
        try writeScalarSkipCondition("other.", field.name, scalar, writer);
        try writer.writeAll("self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = ");
        if (needs_dup) {
            try writer.writeAll("try pbz.wire.dupeBytes(_pbz_owned_allocator,other.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(")");
        } else {
            try writer.writeAll("other.");
            try writeQuotedIdent(field.name, writer);
        }
        try writer.writeAll(";\n");
    }
}

pub fn writeMergeSingularEnumField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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

pub fn writeMergeOneof(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, oneof: schema.OneofDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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
                if (typedOneofMessageFieldWithContext(ctx, field)) |_| {
                    try writer.writeAll(" => |value| { const owned_value = try value.cloneOwned(allocator); errdefer owned_value.deinit(allocator); ");
                    try writeOneofDeinitCall(oneof.name, writer);
                    try writer.writeAll(" self.");
                    try writeQuotedIdent(oneof.name, writer);
                    try writer.writeAll(" = .{ .");
                    try writeQuotedIdent(field.name, writer);
                    try writer.writeAll(" = owned_value }; },\n");
                } else if (field.kind == .message or field.kind == .group or (field.kind == .scalar and (field.kind.scalar == .string or field.kind.scalar == .bytes))) {
                    try writer.writeAll(" => |value| { const owned_value = try pbz.wire.dupeBytes(_pbz_owned_allocator,value); ");
                    try writeOneofDeinitCall(oneof.name, writer);
                    try writer.writeAll(" self.");
                    try writeQuotedIdent(oneof.name, writer);
                    try writer.writeAll(" = .{ .");
                    try writeQuotedIdent(field.name, writer);
                    try writer.writeAll(" = owned_value }; },\n");
                } else {
                    try writer.writeAll(" => |value| { ");
                    try writeOneofDeinitCall(oneof.name, writer);
                    try writer.writeAll(" self.");
                    try writeQuotedIdent(oneof.name, writer);
                    try writer.writeAll(" = .{ .");
                    try writeQuotedIdent(field.name, writer);
                    try writer.writeAll(" = value }; },\n");
                }
            }
        }
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeDeinit(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {\n");
    for (message.fields.items) |*field| {
        if (typedSingularMessageFieldWithContext(ctx, field)) |_| {
            try indent(writer, depth + 1);
            try writer.writeAll("if (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(") |*value| value.deinit(allocator);\n");
        } else if (typedRepeatedMessageFieldWithContext(ctx, field)) |_| {
            try indent(writer, depth + 1);
            try writer.writeAll("for (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(") |value| { var mutable = value; mutable.deinit(allocator); }\n");
            try indent(writer, depth + 1);
            try writer.writeAll("allocator.free(self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(");\n");
        } else if (field.kind == .map) {
            try indent(writer, depth + 1);
            try writer.writeAll("@This().");
            try writeQuotedIdentWithPrefix(field.name, "deinitMap_", writer);
            try writer.writeAll("(allocator, &self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(");\n");
        } else if (field.cardinality == .repeated) {
            try indent(writer, depth + 1);
            try writer.writeAll("allocator.free(self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(");\n");
        }
    }
    for (message.oneofs.items) |oneof| {
        if (!oneofHasTypedMessageWithContext(ctx, message, oneof.name)) continue;
        try indent(writer, depth + 1);
        try writeOneofDeinitCall(oneof.name, writer);
        try writer.writeAll("\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("pbz.wire.freeRawFields(allocator, self._unknown_fields);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (self._json_arena) |arena| { const child_allocator = arena.child_allocator; arena.deinit(); child_allocator.destroy(arena); }\n");
    try indent(writer, depth + 1);
    try writer.writeAll("self.* = undefined;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeClear(writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("/// Release owned storage and reset to the protobuf default value.\n");
    try indent(writer, depth);
    try writer.writeAll("pub fn clear(self: *@This(), allocator: std.mem.Allocator) void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("self.deinit(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("self.* = @This().init();\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeCloneOwned(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn cloneOwned(self: @This(), allocator: std.mem.Allocator) anyerror!@This() {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var out = @This().init();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer out.deinit(allocator);\n");
    if (cloneUsesOwnedAllocator(ctx, message)) {
        try indent(writer, depth + 1);
        try writer.writeAll("const owned_allocator = try out._pbzOwnedAllocator(allocator);\n");
    }
    for (message.fields.items) |*field| {
        if (field.oneof_name == null) try writeCloneField(ctx, field, writer, depth + 1);
    }
    for (message.oneofs.items) |oneof| try writeCloneOneof(ctx, message, oneof, writer, depth + 1);
    try writeCloneUnknownFields(writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("return out;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn cloneUsesOwnedAllocator(ctx: *const CodegenContext, message: *const schema.MessageDescriptor) bool {
    for (message.fields.items) |*field| {
        if (field.oneof_name == null and cloneFieldUsesOwnedAllocator(ctx, field)) return true;
    }
    for (message.oneofs.items) |oneof| {
        for (message.fields.items) |*field| {
            if (field.oneof_name) |name| {
                if (std.mem.eql(u8, name, oneof.name) and cloneFieldUsesOwnedAllocator(ctx, field)) return true;
            }
        }
    }
    return false;
}

pub fn cloneFieldUsesOwnedAllocator(ctx: *const CodegenContext, field: *const schema.FieldDescriptor) bool {
    if (field.kind == .map) {
        const map_type = field.kind.map;
        return cloneKindUsesOwnedAllocator(.{ .scalar = map_type.key }) or
            (typedMapMessageValueWithContext(ctx, field) == null and cloneKindUsesOwnedAllocator(map_type.value.*));
    }
    if (typedSingularMessageFieldWithContext(ctx, field) != null) return false;
    if (typedRepeatedMessageFieldWithContext(ctx, field) != null) return false;
    if (typedOneofMessageFieldWithContext(ctx, field) != null) return false;
    return cloneKindUsesOwnedAllocator(field.kind);
}

pub fn cloneKindUsesOwnedAllocator(kind: schema.FieldKind) bool {
    return switch (kind) {
        .scalar => |scalar| scalar == .string or scalar == .bytes,
        .message, .group => true,
        else => false,
    };
}

pub fn writeCloneField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    if (field.kind == .map) return try writeCloneMapField(ctx, field, writer, depth);
    if (field.cardinality == .repeated) return try writeCloneRepeatedField(ctx, field, writer, depth);
    if (typedSingularMessageFieldWithContext(ctx, field)) |_| {
        try indent(writer, depth);
        try writer.writeAll("if (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(") |value| out.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = try value.cloneOwned(allocator);\n");
        return;
    }
    try indent(writer, depth);
    try writer.writeAll("out.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = ");
    try writeCloneFieldValueExpr(field.kind, field.name, writer);
    try writer.writeAll(";\n");
    if (hasPresence(file, field.*)) {
        try indent(writer, depth);
        try writer.writeAll("out.");
        try writePresenceIdent(field.name, writer);
        try writer.writeAll(" = self.");
        try writePresenceIdent(field.name, writer);
        try writer.writeAll(";\n");
    }
}

pub fn writeCloneRepeatedField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("if (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".len != 0) {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const cloned = try allocator.alloc(");
    if (typedRepeatedMessageFieldWithContext(ctx, field)) |type_name| {
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    } else {
        try writeRepeatedElementType(field.*, writer);
    }
    try writer.writeAll(", self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".len);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("for (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(", 0..) |item, i| cloned[i] = ");
    if (typedRepeatedMessageFieldWithContext(ctx, field)) |_| {
        try writer.writeAll("try item.cloneOwned(allocator)");
    } else {
        try writeCloneValueExpr(field.kind, "item", writer);
    }
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("out.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = cloned;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeCloneMapField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const map_type = switch (field.kind) {
        .map => |map| map,
        else => return,
    };
    try indent(writer, depth);
    try writer.writeAll("if (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".count() != 0) {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try out.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".ensureUnusedCapacity(allocator, self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".count());\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var map_it = self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".iterator();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("while (map_it.next()) |entry| out.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".putAssumeCapacityNoClobber(");
    try writeCloneValueExpr(.{ .scalar = map_type.key }, "entry.key_ptr.*", writer);
    try writer.writeAll(", ");
    if (typedMapMessageValueWithContext(ctx, field)) |_| {
        try writer.writeAll("try entry.value_ptr.cloneOwned(allocator)");
    } else {
        try writeCloneValueExpr(map_type.value.*, "entry.value_ptr.*", writer);
    }
    try writer.writeAll(");\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeCloneOneof(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, oneof: schema.OneofDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("out.");
    try writeQuotedIdent(oneof.name, writer);
    try writer.writeAll(" = switch (self.");
    try writeQuotedIdent(oneof.name, writer);
    try writer.writeAll(") {\n");
    try indent(writer, depth + 1);
    try writer.writeAll(".none => .none,\n");
    for (message.fields.items) |*field| {
        if (field.oneof_name) |name| {
            if (!std.mem.eql(u8, name, oneof.name)) continue;
            try indent(writer, depth + 1);
            try writer.writeAll(".");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(" => |value| .{ .");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(" = ");
            if (typedOneofMessageFieldWithContext(ctx, field)) |_| {
                try writer.writeAll("try value.cloneOwned(allocator)");
            } else {
                try writeCloneValueExpr(field.kind, "value", writer);
            }
            try writer.writeAll(" },\n");
        }
    }
    try indent(writer, depth);
    try writer.writeAll("};\n");
}

pub fn writeCloneUnknownFields(writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("out._unknown_fields = try pbz.wire.cloneRawFields(allocator, self._unknown_fields);\n");
}

pub fn writeAdoptOwned(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("/// Take ownership of borrowed string/bytes payloads after decode.\n");
    try indent(writer, depth);
    try writer.writeAll("/// Owned payloads, including nested message payloads, live in this message's arena.\n");
    try indent(writer, depth);
    try writer.writeAll("pub fn adoptOwned(self: *@This(), allocator: std.mem.Allocator) anyerror!void {\n");
    if (adoptHasWork(ctx, message)) {
        try indent(writer, depth + 1);
        try writer.writeAll("const _pbz_owned_allocator = try self._pbzOwnedAllocator(allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try self.adoptOwnedInto(allocator, _pbz_owned_allocator);\n");
    } else {
        try indent(writer, depth + 1);
        try writer.writeAll("_ = self;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("_ = allocator;\n");
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");
    try indent(writer, depth);
    try writer.writeAll("pub fn adoptOwnedInto(self: *@This(), allocator: std.mem.Allocator, _pbz_owned_allocator: std.mem.Allocator) anyerror!void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("_ = &self;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("_ = &allocator;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("_ = &_pbz_owned_allocator;\n");
    if (mergeUsesOwnedAllocator(ctx, message)) {
        try indent(writer, depth + 1);
        try writer.writeAll("var _pbz_owned_total: usize = 0;\n");
        for (message.fields.items) |*field| {
            if (field.oneof_name == null) try writeAdoptTotalField(ctx, field, writer, depth + 1);
        }
        for (message.oneofs.items) |oneof| try writeAdoptTotalOneof(ctx, message, oneof, writer, depth + 1);
        try indent(writer, depth + 1);
        try writer.writeAll("var _pbz_owned_block = pbz.wire.OwnedBlock.init(if (_pbz_owned_total == 0) &.{} else try _pbz_owned_allocator.alloc(u8, _pbz_owned_total));\n");
    }
    for (message.fields.items) |*field| {
        if (field.oneof_name == null) try writeAdoptField(ctx, field, writer, depth + 1, "_pbz_owned_allocator");
    }
    for (message.oneofs.items) |oneof| try writeAdoptOneof(ctx, message, oneof, writer, depth + 1, "_pbz_owned_allocator");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn adoptIntoUsesAllocator(ctx: *const CodegenContext, message: *const schema.MessageDescriptor) bool {
    for (message.fields.items) |*field| {
        if (field.oneof_name != null) continue;
        if (field.kind == .map) {
            const map_type = field.kind.map;
            if (map_type.key == .string) return true;
            if (typedMapMessageValueWithContext(ctx, field) != null) return true;
            continue;
        }
        if (field.cardinality == .repeated) {
            if (typedRepeatedMessageFieldWithContext(ctx, field) != null) return true;
            continue;
        }
        if (typedSingularMessageFieldWithContext(ctx, field) != null) return true;
    }
    for (message.oneofs.items) |oneof| {
        for (message.fields.items) |*field| {
            if (field.oneof_name) |name| {
                if (std.mem.eql(u8, name, oneof.name) and typedOneofMessageFieldWithContext(ctx, field) != null) return true;
            }
        }
    }
    return false;
}

pub fn writeAdoptTotalField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    if (field.kind == .map) return try writeAdoptTotalMapField(ctx, field, writer, depth);
    if (field.cardinality == .repeated) return try writeAdoptTotalRepeatedField(ctx, field, writer, depth);
    if (typedSingularMessageFieldWithContext(ctx, field)) |_| return;
    switch (field.kind) {
        .message, .group => {
            try indent(writer, depth);
            if (hasPresence(file, field.*)) {
                try writer.writeAll("if (self.");
                try writePresenceIdent(field.name, writer);
                try writer.writeAll(") _pbz_owned_total += self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(".len;\n");
            } else {
                try writer.writeAll("_pbz_owned_total += self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(".len;\n");
            }
        },
        .scalar => |scalar| {
            if (scalar != .string and scalar != .bytes) return;
            try indent(writer, depth);
            if (hasPresence(file, field.*)) {
                try writer.writeAll("if (self.");
                try writePresenceIdent(field.name, writer);
                try writer.writeAll(") _pbz_owned_total += self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(".len;\n");
            } else {
                try writer.writeAll("_pbz_owned_total += self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(".len;\n");
            }
        },
        else => {},
    }
}

pub fn writeAdoptTotalRepeatedField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (typedRepeatedMessageFieldWithContext(ctx, field)) |_| return;
    const raw_message = field.kind == .message or field.kind == .group;
    const string_or_bytes = field.kind == .scalar and (field.kind.scalar == .string or field.kind.scalar == .bytes);
    if (!raw_message and !string_or_bytes) return;
    try indent(writer, depth);
    try writer.writeAll("for (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(") |item| _pbz_owned_total += item.len;\n");
}

pub fn writeAdoptTotalMapField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const map_type = switch (field.kind) {
        .map => |map| map,
        else => return,
    };
    const typed_message_value = typedMapMessageValueWithContext(ctx, field);
    const raw_message_value = typed_message_value == null and (map_type.value.* == .message or map_type.value.* == .group);
    const string_key = map_type.key == .string;
    const string_value = map_type.value.* == .scalar and (map_type.value.scalar == .string or map_type.value.scalar == .bytes);
    if (!string_key and !string_value and !raw_message_value) return;
    try indent(writer, depth);
    try writer.writeAll("var ");
    try writeQuotedIdentWithSuffix(field.name, "_owned_total_it", writer);
    try writer.writeAll(" = self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".iterator();\n");
    try indent(writer, depth);
    try writer.writeAll("while (");
    try writeQuotedIdentWithSuffix(field.name, "_owned_total_it", writer);
    try writer.writeAll(".next()) |entry| {\n");
    if (string_key) {
        try indent(writer, depth + 1);
        try writer.writeAll("_pbz_owned_total += entry.key_ptr.*.len;\n");
    }
    if (string_value or raw_message_value) {
        try indent(writer, depth + 1);
        try writer.writeAll("_pbz_owned_total += entry.value_ptr.*.len;\n");
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeAdoptTotalOneof(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, oneof: schema.OneofDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    var any = false;
    for (message.fields.items) |*field| {
        if (field.oneof_name) |name| {
            if (!std.mem.eql(u8, name, oneof.name)) continue;
            if (typedOneofMessageFieldWithContext(ctx, field) != null) continue;
            if (field.kind == .message or field.kind == .group or (field.kind == .scalar and (field.kind.scalar == .string or field.kind.scalar == .bytes))) {
                any = true;
            }
        }
    }
    if (!any) return;
    try indent(writer, depth);
    try writer.writeAll("switch (self.");
    try writeQuotedIdent(oneof.name, writer);
    try writer.writeAll(") {\n");
    for (message.fields.items) |*field| {
        if (field.oneof_name) |name| {
            if (!std.mem.eql(u8, name, oneof.name)) continue;
            if (typedOneofMessageFieldWithContext(ctx, field) != null) continue;
            if (field.kind == .message or field.kind == .group or (field.kind == .scalar and (field.kind.scalar == .string or field.kind.scalar == .bytes))) {
                try indent(writer, depth + 1);
                try writer.writeAll(".");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(" => |value| _pbz_owned_total += value.len,\n");
            }
        }
    }
    try indent(writer, depth + 1);
    try writer.writeAll("else => {},\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn adoptHasWork(ctx: *const CodegenContext, message: *const schema.MessageDescriptor) bool {
    if (mergeUsesOwnedAllocator(ctx, message)) return true;
    for (message.fields.items) |*field| {
        if (field.oneof_name != null) continue;
        if (typedSingularMessageFieldWithContext(ctx, field) != null) return true;
        if (field.cardinality == .repeated and typedRepeatedMessageFieldWithContext(ctx, field) != null) return true;
    }
    for (message.oneofs.items) |oneof| {
        for (message.fields.items) |*field| {
            if (field.oneof_name) |name| {
                if (std.mem.eql(u8, name, oneof.name) and typedOneofMessageFieldWithContext(ctx, field) != null) return true;
            }
        }
    }
    return false;
}

pub fn writeAdoptField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize, nested_allocator: []const u8) Error!void {
    const file = ctx.file;
    if (field.kind == .map) return try writeAdoptMapField(ctx, field, writer, depth, nested_allocator);
    if (field.cardinality == .repeated) return try writeAdoptRepeatedField(ctx, field, writer, depth, nested_allocator);
    if (typedSingularMessageFieldWithContext(ctx, field)) |_| {
        try indent(writer, depth);
        try writer.writeAll("if (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(") |*value| try value.adoptOwnedInto(allocator, ");
        try writer.writeAll(nested_allocator);
        try writer.writeAll(");\n");
        return;
    }
    switch (field.kind) {
        .message, .group => {
            try indent(writer, depth);
            if (hasPresence(file, field.*)) {
                try writer.writeAll("if (self.");
                try writePresenceIdent(field.name, writer);
                try writer.writeAll(") self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(" = _pbz_owned_block.take(self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(");\n");
            } else {
                try writer.writeAll("if (self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(".len != 0) self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(" = _pbz_owned_block.take(self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(");\n");
            }
        },
        .scalar => |scalar| {
            if (scalar != .string and scalar != .bytes) return;
            try indent(writer, depth);
            if (hasPresence(file, field.*)) {
                try writer.writeAll("if (self.");
                try writePresenceIdent(field.name, writer);
                try writer.writeAll(") self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(" = _pbz_owned_block.take(self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(");\n");
            } else {
                try writer.writeAll("if (self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(".len != 0) self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(" = _pbz_owned_block.take(self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(");\n");
            }
        },
        else => {},
    }
}

pub fn writeAdoptRepeatedField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize, nested_allocator: []const u8) Error!void {
    if (typedRepeatedMessageFieldWithContext(ctx, field)) |_| {
        try indent(writer, depth);
        try writer.writeAll("for (@constCast(self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(")) |*item| try item.adoptOwnedInto(allocator, ");
        try writer.writeAll(nested_allocator);
        try writer.writeAll(");\n");
        return;
    }
    const raw_message = field.kind == .message or field.kind == .group;
    const string_or_bytes = field.kind == .scalar and (field.kind.scalar == .string or field.kind.scalar == .bytes);
    if (!raw_message and !string_or_bytes) return;
    try indent(writer, depth);
    try writer.writeAll("for (@constCast(self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(")) |*item| item.* = _pbz_owned_block.take(item.*);\n");
}

pub fn writeAdoptMapField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize, nested_allocator: []const u8) Error!void {
    const map_type = switch (field.kind) {
        .map => |map| map,
        else => return,
    };
    const typed_message_value = typedMapMessageValueWithContext(ctx, field);
    const raw_message_value = typed_message_value == null and (map_type.value.* == .message or map_type.value.* == .group);
    const string_key = map_type.key == .string;
    const string_value = map_type.value.* == .scalar and (map_type.value.scalar == .string or map_type.value.scalar == .bytes);
    if (!string_key) {
        if (typed_message_value == null and !string_value and !raw_message_value) return;
        try indent(writer, depth);
        try writer.writeAll("var ");
        try writeQuotedIdentWithSuffix(field.name, "_map_it", writer);
        try writer.writeAll(" = self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(".iterator();\n");
        try indent(writer, depth);
        try writer.writeAll("while (");
        try writeQuotedIdentWithSuffix(field.name, "_map_it", writer);
        try writer.writeAll(".next()) |entry| {\n");
        if (typed_message_value != null) {
            try indent(writer, depth + 1);
            try writer.writeAll("try entry.value_ptr.adoptOwnedInto(allocator, ");
            try writer.writeAll(nested_allocator);
            try writer.writeAll(");\n");
        } else {
            try indent(writer, depth + 1);
            try writer.writeAll("entry.value_ptr.* = _pbz_owned_block.take(entry.value_ptr.*);\n");
        }
        try indent(writer, depth);
        try writer.writeAll("}\n");
        return;
    }

    try indent(writer, depth);
    try writer.writeAll("if (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".count() != 0) {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var ");
    try writeQuotedIdentWithSuffix(field.name, "_owned_map", writer);
    try writer.writeAll(" = ");
    try writeQuotedIdentWithSuffix(field.name, "Map", writer);
    try writer.writeAll(".empty;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer ");
    try writeQuotedIdentWithSuffix(field.name, "_owned_map", writer);
    try writer.writeAll(".deinit(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try ");
    try writeQuotedIdentWithSuffix(field.name, "_owned_map", writer);
    try writer.writeAll(".ensureUnusedCapacity(allocator, self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".count());\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var ");
    try writeQuotedIdentWithSuffix(field.name, "_map_it", writer);
    try writer.writeAll(" = self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".iterator();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("while (");
    try writeQuotedIdentWithSuffix(field.name, "_map_it", writer);
    try writer.writeAll(".next()) |entry| {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("const key = _pbz_owned_block.take(entry.key_ptr.*);\n");
    if (typed_message_value != null) {
        try indent(writer, depth + 2);
        try writer.writeAll("try entry.value_ptr.adoptOwnedInto(allocator, ");
        try writer.writeAll(nested_allocator);
        try writer.writeAll(");\n");
        try indent(writer, depth + 2);
        try writeQuotedIdentWithSuffix(field.name, "_owned_map", writer);
        try writer.writeAll(".putAssumeCapacityNoClobber(key, entry.value_ptr.*);\n");
    } else if (string_value or raw_message_value) {
        try indent(writer, depth + 2);
        try writer.writeAll("const value = _pbz_owned_block.take(entry.value_ptr.*);\n");
        try indent(writer, depth + 2);
        try writeQuotedIdentWithSuffix(field.name, "_owned_map", writer);
        try writer.writeAll(".putAssumeCapacityNoClobber(key, value);\n");
    } else {
        try indent(writer, depth + 2);
        try writeQuotedIdentWithSuffix(field.name, "_owned_map", writer);
        try writer.writeAll(".putAssumeCapacityNoClobber(key, entry.value_ptr.*);\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".deinit(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = ");
    try writeQuotedIdentWithSuffix(field.name, "_owned_map", writer);
    try writer.writeAll(";\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeAdoptOneof(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, oneof: schema.OneofDescriptor, writer: *std.Io.Writer, depth: usize, nested_allocator: []const u8) Error!void {
    var any = false;
    for (message.fields.items) |*field| {
        if (field.oneof_name) |name| {
            if (!std.mem.eql(u8, name, oneof.name)) continue;
            if (typedOneofMessageFieldWithContext(ctx, field) != null) {
                any = true;
            } else if (field.kind == .message or field.kind == .group or (field.kind == .scalar and (field.kind.scalar == .string or field.kind.scalar == .bytes))) {
                any = true;
            }
        }
    }
    if (!any) return;
    try indent(writer, depth);
    try writer.writeAll("switch (self.");
    try writeQuotedIdent(oneof.name, writer);
    try writer.writeAll(") {\n");
    for (message.fields.items) |*field| {
        if (field.oneof_name) |name| {
            if (!std.mem.eql(u8, name, oneof.name)) continue;
            if (typedOneofMessageFieldWithContext(ctx, field) != null) {
                try indent(writer, depth + 1);
                try writer.writeAll(".");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(" => |*value| try value.adoptOwnedInto(allocator, ");
                try writer.writeAll(nested_allocator);
                try writer.writeAll("),\n");
            } else if (field.kind == .message or field.kind == .group or (field.kind == .scalar and (field.kind.scalar == .string or field.kind.scalar == .bytes))) {
                try indent(writer, depth + 1);
                try writer.writeAll(".");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(" => |value| self.");
                try writeQuotedIdent(oneof.name, writer);
                try writer.writeAll(" = .{ .");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(" = _pbz_owned_block.take(value) },\n");
            }
        }
    }
    try indent(writer, depth + 1);
    try writer.writeAll("else => {},\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeCloneFieldValueExpr(kind: schema.FieldKind, field_name: []const u8, writer: *std.Io.Writer) Error!void {
    switch (kind) {
        .scalar => |scalar| switch (scalar) {
            .string, .bytes => {
                try writer.writeAll("try owned_allocator.dupe(u8, self.");
                try writeQuotedIdent(field_name, writer);
                try writer.writeAll(")");
            },
            else => {
                try writer.writeAll("self.");
                try writeQuotedIdent(field_name, writer);
            },
        },
        .message, .group => {
            try writer.writeAll("try owned_allocator.dupe(u8, self.");
            try writeQuotedIdent(field_name, writer);
            try writer.writeAll(")");
        },
        .enumeration => {
            try writer.writeAll("self.");
            try writeQuotedIdent(field_name, writer);
        },
        .map => unreachable,
    }
}

pub fn writeCloneValueExpr(kind: schema.FieldKind, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    switch (kind) {
        .scalar => |scalar| switch (scalar) {
            .string, .bytes => try writer.print("try owned_allocator.dupe(u8, {s})", .{value_expr}),
            else => try writer.writeAll(value_expr),
        },
        .message, .group => try writer.print("try pbz.wire.dupeBytes(owned_allocator, {s})", .{value_expr}),
        .enumeration => try writer.writeAll(value_expr),
        .map => try writer.writeAll(value_expr),
    }
}
