const std = @import("std");

const schema = @import("schema.zig");

const plugin = @import("plugin.zig");

const registry_mod = @import("registry.zig");

const wire = @import("wire.zig");

const plugin_emit = @import("codegen/plugin.zig");

const service_emit = @import("codegen/service.zig");

pub const enum_emit = @import("codegen/enum.zig");

const json_emit = @import("codegen/json_emit.zig");

pub const text_emit = @import("codegen/text_emit.zig");

const validate_emit = @import("codegen/validate_emit.zig");
const lifecycle_emit = @import("codegen/lifecycle_emit.zig");
const extension_emit = @import("codegen/extension_emit.zig");
const encode_emit = @import("codegen/encode_emit.zig");
const decode_emit = @import("codegen/decode_emit.zig");
const decl_emit = @import("codegen/decl_emit.zig");
const view_emit = @import("codegen/view_emit.zig");

pub const Error = std.mem.Allocator.Error || std.Io.Writer.Error || plugin.Error || registry_mod.Error;

pub const CodegenContext = struct {
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    registry: ?*const registry_mod.Registry = null,
    pbz_import: []const u8 = "pbz",
    emit_json: bool = true,
    emit_text: bool = true,
    emit_descriptor: bool = true,
    output_suffix: []const u8 = ".pb.zig",
    strip_proto_ext: bool = true,
};

pub fn generateZigFile(allocator: std.mem.Allocator, file: *const schema.FileDescriptor) Error![]u8 {
    return try generateZigFileWithContext(.{ .allocator = allocator, .file = file });
}

pub fn generateZigFileWithRegistry(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, registry: *const registry_mod.Registry) Error![]u8 {
    return try generateZigFileWithContext(.{ .allocator = allocator, .file = file, .registry = registry });
}

pub fn generateZigFileWithContext(ctx: CodegenContext) Error![]u8 {
    var arena = std.heap.ArenaAllocator.init(ctx.allocator);
    defer arena.deinit();
    var active_ctx = ctx;
    var resolved_file = try cloneFileForCodegen(arena.allocator(), ctx.file);
    normalizeSyntheticProto3OptionalOneofsForCodegen(&resolved_file);
    if (ctx.registry) |registry| {
        try resolveImportedEnumsForCodegen(arena.allocator(), &resolved_file, registry);
    }
    active_ctx.file = &resolved_file;

    var out: std.Io.Writer.Allocating = .init(ctx.allocator);
    errdefer out.deinit();
    try out.writer.writeAll("const std = @import(\"std\");\nconst pbz = @import(");
    try writeZigStringLiteral(active_ctx.pbz_import, &out.writer);
    try out.writer.writeAll(");\n\n");
    try writeFileMetadata(&active_ctx, &out.writer, 0);
    if (active_ctx.emit_descriptor) {
        var descriptor_file = try cloneFileForCodegen(arena.allocator(), ctx.file);
        descriptor_file.source_code_info = .{};
        if (active_ctx.registry) |registry| {
            try resolveImportedEnumsForCodegen(arena.allocator(), &descriptor_file, registry);
        }
        try writeGeneratedFileDescriptor(&active_ctx, &descriptor_file, &out.writer, 0);
    }
    try writePackagedFileDecls(&active_ctx, &out.writer, 0);
    try json_emit.writeFileRegistryHelper(&active_ctx, &out.writer);
    try json_emit.writeWktJsonHelpers(&active_ctx, &out.writer);
    try json_emit.writeAnyJsonHelpers(&active_ctx, &out.writer);
    return try finalizeGeneratedZig(ctx.allocator, try out.toOwnedSlice());
}

fn finalizeGeneratedZig(allocator: std.mem.Allocator, raw: []u8) Error![]u8 {
    var raw_owned: ?[]u8 = raw;
    errdefer if (raw_owned) |buf| allocator.free(buf);

    const input = trimTrailingBlankLines(raw);
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    var changed = input.len != raw.len;
    var index: usize = 0;
    while (index < input.len) {
        if (input[index] == '"') {
            index = try copyQuotedZigString(input, index, &out.writer);
        } else if (input[index] == '\'') {
            index = try copyQuotedZigChar(input, index, &out.writer);
        } else if (index + 1 < input.len and input[index] == '/' and input[index + 1] == '/') {
            index = try copyZigLineComment(input, index, &out.writer);
        } else if (quotedBareIdent(input, index)) |range| {
            changed = true;
            try out.writer.writeAll(input[range.ident_begin..range.ident_end]);
            index = range.end;
        } else {
            try out.writer.writeByte(input[index]);
            index += 1;
        }
    }

    if (changed) {
        const final = try out.toOwnedSlice();
        allocator.free(raw);
        raw_owned = null;
        return final;
    }
    out.deinit();
    return raw;
}

fn trimTrailingBlankLines(input: []const u8) []const u8 {
    var end = input.len;
    while (end >= 2 and input[end - 1] == '\n' and input[end - 2] == '\n') end -= 1;
    return input[0..end];
}

fn quotedBareIdent(input: []const u8, start: usize) ?struct { ident_begin: usize, ident_end: usize, end: usize } {
    if (start + 2 > input.len or input[start] != '@' or input[start + 1] != '"') return null;
    var index = start + 2;
    while (index < input.len) : (index += 1) {
        switch (input[index]) {
            '\\' => return null,
            '"' => {
                const ident_begin = start + 2;
                const ident_end = index;
                if (!canWriteBareIdent(input[ident_begin..ident_end])) return null;
                return .{ .ident_begin = ident_begin, .ident_end = ident_end, .end = index + 1 };
            },
            else => {},
        }
    }
    return null;
}

fn copyQuotedZigString(input: []const u8, start: usize, writer: *std.Io.Writer) Error!usize {
    var index = start;
    try writer.writeByte(input[index]);
    index += 1;
    while (index < input.len) {
        const c = input[index];
        try writer.writeByte(c);
        index += 1;
        if (c == '\\') {
            if (index < input.len) {
                try writer.writeByte(input[index]);
                index += 1;
            }
        } else if (c == '"') {
            break;
        }
    }
    return index;
}

fn copyQuotedZigChar(input: []const u8, start: usize, writer: *std.Io.Writer) Error!usize {
    var index = start;
    try writer.writeByte(input[index]);
    index += 1;
    while (index < input.len) {
        const c = input[index];
        try writer.writeByte(c);
        index += 1;
        if (c == '\\') {
            if (index < input.len) {
                try writer.writeByte(input[index]);
                index += 1;
            }
        } else if (c == '\'') {
            break;
        }
    }
    return index;
}

fn copyZigLineComment(input: []const u8, start: usize, writer: *std.Io.Writer) Error!usize {
    var index = start;
    while (index < input.len) : (index += 1) {
        const c = input[index];
        try writer.writeByte(c);
        if (c == '\n') {
            index += 1;
            break;
        }
    }
    return index;
}

fn cloneFileForCodegen(allocator: std.mem.Allocator, file: *const schema.FileDescriptor) std.mem.Allocator.Error!schema.FileDescriptor {
    var out = file.*;
    out.messages = .empty;
    out.enums = .empty;
    out.extensions = .empty;
    for (file.messages.items) |*message| try out.messages.append(allocator, try cloneMessageForCodegen(allocator, message));
    for (file.enums.items) |enumeration| try out.enums.append(allocator, enumeration);
    for (file.extensions.items) |*field| try out.extensions.append(allocator, try cloneFieldForCodegen(allocator, field));
    return out;
}

fn cloneMessageForCodegen(allocator: std.mem.Allocator, message: *const schema.MessageDescriptor) std.mem.Allocator.Error!schema.MessageDescriptor {
    var out = message.*;
    out.fields = .empty;
    out.oneofs = .empty;
    out.messages = .empty;
    out.extensions = .empty;
    for (message.fields.items) |*field| try out.fields.append(allocator, try cloneFieldForCodegen(allocator, field));
    for (message.oneofs.items) |oneof| try out.oneofs.append(allocator, oneof);
    for (message.messages.items) |*nested| try out.messages.append(allocator, try cloneMessageForCodegen(allocator, nested));
    for (message.extensions.items) |*field| try out.extensions.append(allocator, try cloneFieldForCodegen(allocator, field));
    return out;
}

fn normalizeSyntheticProto3OptionalOneofsForCodegen(file: *schema.FileDescriptor) void {
    for (file.messages.items) |*message| normalizeMessageSyntheticProto3OptionalOneofsForCodegen(message);
}

fn normalizeMessageSyntheticProto3OptionalOneofsForCodegen(message: *schema.MessageDescriptor) void {
    // protoc represents `optional` proto3 scalars as single-field synthetic
    // oneofs in FileDescriptorProto for reflection compatibility. Generated
    // Zig should expose the source-level field shape instead of leaking those
    // implementation details into public APIs, so codegen rewrites synthetic
    // oneofs back to ordinary proto3-optional fields before emitting structs.
    var write_index: usize = 0;
    for (message.oneofs.items, 0..) |oneof, read_index| {
        if (syntheticProto3OptionalFieldIndex(message, oneof.name)) |field_index| {
            message.fields.items[field_index].oneof_name = null;
            continue;
        }
        if (write_index != read_index) message.oneofs.items[write_index] = oneof;
        write_index += 1;
    }
    message.oneofs.items.len = write_index;
    for (message.messages.items) |*nested| normalizeMessageSyntheticProto3OptionalOneofsForCodegen(nested);
}

fn syntheticProto3OptionalFieldIndex(message: *const schema.MessageDescriptor, oneof_name: []const u8) ?usize {
    var found: ?usize = null;
    for (message.fields.items, 0..) |field, index| {
        const field_oneof = field.oneof_name orelse continue;
        if (!std.mem.eql(u8, field_oneof, oneof_name)) continue;
        if (found != null) return null;
        if (!field.proto3_optional) return null;
        found = index;
    }
    return found;
}

fn cloneFieldForCodegen(allocator: std.mem.Allocator, field: *const schema.FieldDescriptor) std.mem.Allocator.Error!schema.FieldDescriptor {
    var out = field.*;
    out.kind = try cloneFieldKindForCodegen(allocator, field.kind);
    return out;
}

fn cloneFieldKindForCodegen(allocator: std.mem.Allocator, kind: schema.FieldKind) std.mem.Allocator.Error!schema.FieldKind {
    return switch (kind) {
        .map => |map_type| blk: {
            const value = try allocator.create(schema.FieldKind);
            errdefer allocator.destroy(value);
            value.* = try cloneFieldKindForCodegen(allocator, map_type.value.*);
            break :blk .{ .map = .{ .key = map_type.key, .value = value } };
        },
        else => kind,
    };
}

fn resolveImportedEnumsForCodegen(allocator: std.mem.Allocator, file: *schema.FileDescriptor, registry: *const registry_mod.Registry) std.mem.Allocator.Error!void {
    for (file.messages.items) |*message| {
        const scope = try codegenQualifiedName(allocator, file.package, message.name);
        try resolveMessageImportedEnumsForCodegen(allocator, file, registry, message, scope);
    }
    const file_scope: ?[]const u8 = if (file.package.len == 0) null else file.package;
    for (file.extensions.items) |*field| try resolveFieldImportedEnumForCodegen(allocator, file, registry, field, file_scope);
}

fn resolveMessageImportedEnumsForCodegen(allocator: std.mem.Allocator, file: *schema.FileDescriptor, registry: *const registry_mod.Registry, message: *schema.MessageDescriptor, scope: []const u8) std.mem.Allocator.Error!void {
    for (message.fields.items) |*field| try resolveFieldImportedEnumForCodegen(allocator, file, registry, field, scope);
    for (message.extensions.items) |*field| try resolveFieldImportedEnumForCodegen(allocator, file, registry, field, scope);
    for (message.messages.items) |*nested| {
        const nested_scope = try codegenQualifiedName(allocator, scope, nested.name);
        try resolveMessageImportedEnumsForCodegen(allocator, file, registry, nested, nested_scope);
    }
}

fn resolveFieldImportedEnumForCodegen(allocator: std.mem.Allocator, file: *schema.FileDescriptor, registry: *const registry_mod.Registry, field: *schema.FieldDescriptor, scope: ?[]const u8) std.mem.Allocator.Error!void {
    try resolveFieldExtendeeForCodegen(allocator, file, registry, field);
    switch (field.kind) {
        .message => |name| {
            if (registry.findEnumVisible(file, name, scope)) |enumeration| {
                try resolveEnumDefaultAndAliasForCodegen(allocator, file, registry, field, enumeration, name);
                field.kind = .{ .enumeration = name };
            }
        },
        .enumeration => |name| {
            if (registry.findEnumVisible(file, name, scope)) |enumeration| {
                try resolveEnumDefaultAndAliasForCodegen(allocator, file, registry, field, enumeration, name);
            }
        },
        .map => |map_type| switch (map_type.value.*) {
            .message => |name| {
                if (registry.findEnumVisible(file, name, scope)) |enumeration| {
                    try ensureImportedEnumAliasForCodegen(allocator, file, registry, enumeration, name);
                    map_type.value.* = .{ .enumeration = name };
                }
            },
            .enumeration => |name| {
                if (registry.findEnumVisible(file, name, scope)) |enumeration| {
                    try ensureImportedEnumAliasForCodegen(allocator, file, registry, enumeration, name);
                }
            },
            else => {},
        },
        else => {},
    }
}

fn resolveEnumDefaultAndAliasForCodegen(allocator: std.mem.Allocator, file: *schema.FileDescriptor, registry: *const registry_mod.Registry, field: *schema.FieldDescriptor, enumeration: *const schema.EnumDescriptor, type_name: []const u8) std.mem.Allocator.Error!void {
    try resolveImportedEnumDefaultForCodegen(field, enumeration);
    try ensureImportedEnumAliasForCodegen(allocator, file, registry, enumeration, type_name);
}

fn ensureImportedEnumAliasForCodegen(allocator: std.mem.Allocator, file: *schema.FileDescriptor, registry: *const registry_mod.Registry, enumeration: *const schema.EnumDescriptor, type_name: []const u8) std.mem.Allocator.Error!void {
    const owner = registry.fileContainingEnum(enumeration) orelse return;
    if (sameFileForCodegen(owner, file)) return;
    try ensureEnumAliasForCodegen(allocator, file, registry, enumeration, type_name);
}

fn codegenQualifiedName(allocator: std.mem.Allocator, prefix: []const u8, name: []const u8) std.mem.Allocator.Error![]const u8 {
    if (prefix.len == 0) return try allocator.dupe(u8, name);
    return try std.fmt.allocPrint(allocator, "{s}.{s}", .{ prefix, name });
}

fn resolveFieldExtendeeForCodegen(allocator: std.mem.Allocator, file: *schema.FileDescriptor, registry: *const registry_mod.Registry, field: *schema.FieldDescriptor) std.mem.Allocator.Error!void {
    const extendee = field.extendee orelse return;
    const message = registry.findMessageVisible(file, extendee, extensionScopeForCodegen(file, field)) orelse return;
    const owner = registry.fileContainingMessage(message) orelse return;
    if (try messageFullNameForCodegen(allocator, owner, message)) |full_name| field.extendee = full_name;
}

fn resolveImportedEnumDefaultForCodegen(field: *schema.FieldDescriptor, enumeration: *const schema.EnumDescriptor) std.mem.Allocator.Error!void {
    const default_name = switch (field.default_value orelse return) {
        .identifier, .string => |text| text,
        else => return,
    };
    if (enumeration.findValue(default_name)) |value| field.default_value = .{ .integer = value.number };
}

fn ensureEnumAliasForCodegen(allocator: std.mem.Allocator, file: *schema.FileDescriptor, registry: *const registry_mod.Registry, enumeration: *const schema.EnumDescriptor, type_name: []const u8) std.mem.Allocator.Error!void {
    const alias = normalizedTypeName(type_name);
    for (file.enums.items) |existing| {
        if (std.mem.eql(u8, existing.name, alias)) return;
    }
    var copy = enumeration.*;
    copy.name = alias;
    if (copy.features == null) {
        if (registry.fileContainingEnum(enumeration)) |owner| copy.features = owner.features;
    }
    try file.enums.append(allocator, copy);
}

fn normalizedTypeName(type_name: []const u8) []const u8 {
    return if (std.mem.startsWith(u8, type_name, ".")) type_name[1..] else type_name;
}

pub fn extensionScopeForCodegen(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor) ?[]const u8 {
    if (field.full_name) |full_name| {
        const normalized = normalizedTypeName(full_name);
        if (std.mem.lastIndexOfScalar(u8, normalized, '.')) |idx| return normalized[0..idx];
        if (std.mem.startsWith(u8, full_name, ".")) return null;
    }
    return if (file.package.len != 0) file.package else null;
}

fn messageFullNameForCodegen(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, target: *const schema.MessageDescriptor) std.mem.Allocator.Error!?[]const u8 {
    for (file.messages.items) |*message| {
        if (message == target) return try joinFullProtoName(allocator, file.package, message.name);
        if (try nestedMessageFullNameForCodegen(allocator, file.package, message.name, message, target)) |full_name| return full_name;
    }
    return null;
}

fn nestedMessageFullNameForCodegen(allocator: std.mem.Allocator, package: []const u8, prefix: []const u8, message: *const schema.MessageDescriptor, target: *const schema.MessageDescriptor) std.mem.Allocator.Error!?[]const u8 {
    for (message.messages.items) |*nested| {
        const path = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ prefix, nested.name });
        if (nested == target) return try joinFullProtoName(allocator, package, path);
        if (try nestedMessageFullNameForCodegen(allocator, package, path, nested, target)) |full_name| return full_name;
    }
    return null;
}

fn joinFullProtoName(allocator: std.mem.Allocator, package: []const u8, relative: []const u8) std.mem.Allocator.Error![]const u8 {
    if (package.len == 0) return try std.fmt.allocPrint(allocator, ".{s}", .{relative});
    return try std.fmt.allocPrint(allocator, ".{s}.{s}", .{ package, relative });
}

pub fn enumFullNameForCodegen(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, target: *const schema.EnumDescriptor) std.mem.Allocator.Error!?[]const u8 {
    for (file.enums.items) |*enumeration| {
        if (enumeration == target) return try joinFullProtoName(allocator, file.package, enumeration.name);
    }
    for (file.messages.items) |*message| {
        if (try nestedEnumFullNameForCodegen(allocator, file.package, message.name, message, target)) |full_name| return full_name;
    }
    return null;
}

fn nestedEnumFullNameForCodegen(allocator: std.mem.Allocator, package: []const u8, prefix: []const u8, message: *const schema.MessageDescriptor, target: *const schema.EnumDescriptor) std.mem.Allocator.Error!?[]const u8 {
    for (message.enums.items) |*enumeration| {
        if (enumeration == target) {
            const path = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ prefix, enumeration.name });
            return try joinFullProtoName(allocator, package, path);
        }
    }
    for (message.messages.items) |*nested| {
        const path = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ prefix, nested.name });
        if (try nestedEnumFullNameForCodegen(allocator, package, path, nested, target)) |full_name| return full_name;
    }
    return null;
}

// Plugin protocol and GeneratedCodeInfo emission live in a submodule; these
// re-exports keep the existing public API stable.
pub const generatePluginResponseFromRequestBytes = plugin_emit.generatePluginResponseFromRequestBytes;

pub const runPluginRequestBytes = plugin_emit.runPluginRequestBytes;

pub const runPluginRequest = plugin_emit.runPluginRequest;

pub const generatePluginResponseFromRequest = plugin_emit.generatePluginResponseFromRequest;

pub const generatePluginResponse = plugin_emit.generatePluginResponse;

pub const generatedResponseFeatureMask = plugin_emit.generatedResponseFeatureMask;

fn fieldKindName(kind: schema.FieldKind) []const u8 {
    return switch (kind) {
        .scalar => |scalar| @tagName(scalar),
        .message => "message",
        .enumeration => "enum",
        .group => "group",
        .map => "map",
    };
}

fn fieldTypeName(kind: schema.FieldKind) []const u8 {
    return switch (kind) {
        .scalar => |scalar| @tagName(scalar),
        .message => |name| name,
        .enumeration => |name| name,
        .group => |name| name,
        .map => "",
    };
}

pub fn codegenCanReferenceMessage(file: *const schema.FileDescriptor, type_name: []const u8) bool {
    return resolveSameFileMessageReference(file, type_name) != null;
}

pub fn writeMessageTypeReference(type_name: []const u8, writer: *std.Io.Writer) Error!void {
    const trimmed = if (std.mem.startsWith(u8, type_name, ".")) type_name[1..] else type_name;
    const leaf = if (std.mem.lastIndexOfScalar(u8, trimmed, '.')) |idx| trimmed[idx + 1 ..] else trimmed;
    try writeQuotedIdent(leaf, writer);
}

const MessageReference = struct {
    message: *const schema.MessageDescriptor,
    file: *const schema.FileDescriptor,
    import_chain: ?registry_mod.ImportChain = null,
};

const EnumReference = struct {
    enumeration: *const schema.EnumDescriptor,
    file: *const schema.FileDescriptor,
};

fn canReferenceMessageWithContext(ctx: *const CodegenContext, kind: schema.FieldKind) bool {
    const type_name = switch (kind) {
        .message, .group => |name| name,
        else => return false,
    };
    return codegenCanReferenceMessageWithContext(ctx, type_name);
}

fn canReferenceEnumWithContext(ctx: *const CodegenContext, kind: schema.FieldKind) bool {
    const type_name = switch (kind) {
        .enumeration => |name| name,
        else => return false,
    };
    return codegenCanReferenceEnumWithContext(ctx, type_name);
}

pub fn codegenCanReferenceMessageWithContext(ctx: *const CodegenContext, type_name: []const u8) bool {
    return resolveMessageReference(ctx, type_name) != null;
}

fn codegenCanReferenceEnumWithContext(ctx: *const CodegenContext, type_name: []const u8) bool {
    return resolveEnumReference(ctx, type_name) != null;
}

fn writeMessageTypeReferenceOrVoid(ctx: *const CodegenContext, kind: schema.FieldKind, writer: *std.Io.Writer) Error!void {
    const type_name = switch (kind) {
        .message, .group => |name| name,
        else => return try writer.writeAll("void"),
    };
    if (codegenCanReferenceMessageWithContext(ctx, type_name)) {
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    } else {
        try writer.writeAll("void");
    }
}

fn writeEnumTypeReferenceOrVoid(ctx: *const CodegenContext, kind: schema.FieldKind, writer: *std.Io.Writer) Error!void {
    const type_name = switch (kind) {
        .enumeration => |name| name,
        else => return try writer.writeAll("void"),
    };
    if (codegenCanReferenceEnumWithContext(ctx, type_name)) {
        try writeEnumTypeReferenceWithContext(ctx, type_name, writer);
    } else {
        try writer.writeAll("void");
    }
}

pub fn writeMessageTypeReferenceWithContext(ctx: *const CodegenContext, type_name: []const u8, writer: *std.Io.Writer) Error!void {
    const reference = resolveMessageReference(ctx, type_name) orelse {
        return try writeMessageTypeReference(type_name, writer);
    };
    if (reference.import_chain) |chain| {
        try writeImportChainPrefix(ctx, chain.slice(), writer);
        try writePackagePath(reference.file.package, writer);
        if (!(try writeMessagePathInFile(reference.file, reference.message, writer))) try writeMessageTypeReference(type_name, writer);
    } else {
        try writeMessageTypeReference(type_name, writer);
    }
}

/// Like writeMessageTypeReferenceWithContext, but always qualifies same-file
/// references with their message path. Use this from file-scope namespaces such
/// as `extensions`, where a nested type's leaf name is not in scope.
/// Reference a message from file scope (outside the package structs), where
/// same-file leaf names are not in scope.
pub fn writeFileScopeMessageReference(ctx: *const CodegenContext, type_name: []const u8, writer: *std.Io.Writer) Error!void {
    const reference = resolveMessageReference(ctx, type_name) orelse {
        return try writeMessageTypeReference(type_name, writer);
    };
    if (reference.import_chain) |chain| {
        try writeImportChainPrefix(ctx, chain.slice(), writer);
        try writePackagePath(reference.file.package, writer);
        _ = try writeMessagePathInFile(reference.file, reference.message, writer);
    } else {
        try writePackagePath(ctx.file.package, writer);
        _ = try writeMessagePathInFile(ctx.file, reference.message, writer);
    }
}

fn writeQualifiedMessageTypeReference(ctx: *const CodegenContext, type_name: []const u8, writer: *std.Io.Writer) Error!void {
    const reference = resolveMessageReference(ctx, type_name) orelse {
        return try writeMessageTypeReference(type_name, writer);
    };
    if (reference.import_chain) |chain| {
        try writeImportChainPrefix(ctx, chain.slice(), writer);
        try writePackagePath(reference.file.package, writer);
        if (!(try writeMessagePathInFile(reference.file, reference.message, writer))) try writeMessageTypeReference(type_name, writer);
    } else {
        if (!(try writeMessagePathInFile(ctx.file, reference.message, writer))) try writeMessageTypeReference(type_name, writer);
    }
}

fn writeEnumTypeReferenceWithContext(ctx: *const CodegenContext, type_name: []const u8, writer: *std.Io.Writer) Error!void {
    const reference = resolveEnumReference(ctx, type_name) orelse {
        return try writeMessageTypeReference(type_name, writer);
    };
    if (!(try writeEnumPathInFile(reference.file, reference.enumeration, writer))) try writeMessageTypeReference(type_name, writer);
}

pub fn resolveMessageReference(ctx: *const CodegenContext, type_name: []const u8) ?MessageReference {
    if (ctx.registry) |registry| {
        if (registry.findMessageVisible(ctx.file, type_name, ctx.file.package)) |message| {
            if (registry.fileContainingMessage(message)) |owner| {
                if (sameFileForCodegen(owner, ctx.file)) return .{ .message = message, .file = owner };
                if (registry.importChain(ctx.file, owner)) |chain| {
                    if (chain.len == 0) return .{ .message = message, .file = owner };
                    return .{ .message = message, .file = owner, .import_chain = chain };
                }
            }
        }
    }
    if (resolveSameFileMessageReference(ctx.file, type_name)) |message| return .{ .message = message, .file = ctx.file };
    return null;
}

fn resolveSameFileMessageReference(file: *const schema.FileDescriptor, type_name: []const u8) ?*const schema.MessageDescriptor {
    return findMessageByQualifiedName(file, type_name) orelse file.findMessageDeep(type_name);
}

fn resolveEnumReference(ctx: *const CodegenContext, type_name: []const u8) ?EnumReference {
    if (ctx.file.findEnumDeep(type_name)) |enumeration| return .{ .enumeration = enumeration, .file = ctx.file };
    if (ctx.registry) |registry| {
        if (registry.findEnumVisible(ctx.file, type_name, ctx.file.package)) |enumeration| {
            if (registry.fileContainingEnum(enumeration)) |owner| {
                if (sameFileForCodegen(owner, ctx.file)) return .{ .enumeration = enumeration, .file = owner };
            }
        }
    }
    return null;
}

pub fn sameFileForCodegen(a: *const schema.FileDescriptor, b: *const schema.FileDescriptor) bool {
    if (a == b) return true;
    if (a.name.len != 0 and b.name.len != 0 and std.mem.eql(u8, a.name, b.name)) return true;
    return false;
}

fn writeImportChainPrefix(ctx: *const CodegenContext, paths: []const []const u8, writer: *std.Io.Writer) Error!void {
    if (packageHasSegment(ctx.file.package, "imports")) try writer.writeAll("pbz_generated_file.");
    try writer.writeAll("imports.");
    for (paths, 0..) |path, index| {
        if (index != 0) {
            try writer.writeAll(".imports.");
        }
        const import_alias = try makeImportAlias(ctx.allocator, path);
        defer ctx.allocator.free(import_alias);
        try writer.writeAll(import_alias);
    }
    try writer.writeByte('.');
}

fn packageHasSegment(package: []const u8, needle: []const u8) bool {
    var parts = std.mem.splitScalar(u8, package, '.');
    while (parts.next()) |part| {
        if (std.mem.eql(u8, part, needle)) return true;
    }
    return false;
}

fn writePackagePath(package: []const u8, writer: *std.Io.Writer) Error!void {
    if (package.len == 0) return;
    var parts = std.mem.splitScalar(u8, package, '.');
    while (parts.next()) |part| {
        if (part.len == 0) continue;
        try writeQuotedIdent(part, writer);
        try writer.writeByte('.');
    }
}

fn writeMessagePathInFile(file: *const schema.FileDescriptor, target: *const schema.MessageDescriptor, writer: *std.Io.Writer) Error!bool {
    for (file.messages.items) |*message| {
        if (try writeMessagePathInMessage(message, target, writer)) return true;
    }
    return false;
}

fn writeMessagePathInMessage(message: *const schema.MessageDescriptor, target: *const schema.MessageDescriptor, writer: *std.Io.Writer) Error!bool {
    if (message == target) {
        try writeQuotedIdent(message.name, writer);
        return true;
    }
    for (message.messages.items) |*nested| {
        if (messageContainsMessage(nested, target) or nested == target) {
            try writeQuotedIdent(message.name, writer);
            try writer.writeByte('.');
            return try writeMessagePathInMessage(nested, target, writer);
        }
    }
    return false;
}

fn messageContainsMessage(message: *const schema.MessageDescriptor, target: *const schema.MessageDescriptor) bool {
    for (message.messages.items) |*nested| {
        if (nested == target or messageContainsMessage(nested, target)) return true;
    }
    return false;
}

fn writeEnumPathInFile(file: *const schema.FileDescriptor, target: *const schema.EnumDescriptor, writer: *std.Io.Writer) Error!bool {
    for (file.enums.items) |*enumeration| {
        if (enumeration == target) {
            try writeQuotedIdent(enumeration.name, writer);
            return true;
        }
    }
    for (file.messages.items) |*message| {
        if (try writeEnumPathInMessage(message, target, writer)) return true;
    }
    return false;
}

fn writeEnumPathInMessage(message: *const schema.MessageDescriptor, target: *const schema.EnumDescriptor, writer: *std.Io.Writer) Error!bool {
    for (message.enums.items) |*enumeration| {
        if (enumeration == target) {
            try writeQuotedIdent(message.name, writer);
            try writer.writeByte('.');
            try writeQuotedIdent(enumeration.name, writer);
            return true;
        }
    }
    for (message.messages.items) |*nested| {
        if (messageContainsEnumDescriptor(nested, target)) {
            try writeQuotedIdent(message.name, writer);
            try writer.writeByte('.');
            return try writeEnumPathInMessage(nested, target, writer);
        }
    }
    return false;
}

fn messageContainsEnumDescriptor(message: *const schema.MessageDescriptor, target: *const schema.EnumDescriptor) bool {
    for (message.enums.items) |*enumeration| {
        if (enumeration == target) return true;
    }
    for (message.messages.items) |*nested| {
        if (messageContainsEnumDescriptor(nested, target)) return true;
    }
    return false;
}

pub fn fieldMessageEncoding(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor) schema.FeatureSet.MessageEncoding {
    return schema.FeatureSet.effective(field.features, file.features).message_encoding;
}

pub fn fieldUtf8Validation(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor) schema.FeatureSet.Utf8Validation {
    return schema.FeatureSet.effective(field.features, file.features).utf8_validation;
}

pub fn fieldUtf8ValidationOptional(file: *const schema.FileDescriptor, field: ?*const schema.FieldDescriptor) schema.FeatureSet.Utf8Validation {
    if (field) |descriptor| return fieldUtf8Validation(file, descriptor);
    return file.features.utf8_validation;
}

fn writeFieldType(field: schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    if (field.kind == .map) {
        try writeQuotedIdentWithSuffix(field.name, "Map", writer);
        return;
    }
    try writer.writeAll(fieldType(field));
}

fn writeMapStorageType(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    const map_type = switch (field.kind) {
        .map => |map| map,
        else => return,
    };
    if (map_type.key == .string) {
        try writer.writeAll("std.StringArrayHashMapUnmanaged(");
    } else {
        try writer.writeAll("std.AutoArrayHashMapUnmanaged(");
        try writer.writeAll(scalarZigType(map_type.key));
        try writer.writeAll(", ");
    }
    try writeMapValueType(ctx, field, writer);
    try writer.writeAll(")");
}

fn writeMapValueType(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    const map_type = switch (field.kind) {
        .map => |map| map,
        else => return,
    };
    if (typedMapMessageValueWithContext(ctx, field)) |type_name| {
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    } else {
        try writeFieldKindType(map_type.value.*, writer);
    }
}

fn writeFieldKindType(kind: schema.FieldKind, writer: *std.Io.Writer) Error!void {
    switch (kind) {
        .scalar => |scalar| try writer.writeAll(scalarZigType(scalar)),
        .enumeration => try writer.writeAll("i32"),
        .message, .group => try writer.writeAll("[]const u8"),
        else => try writer.writeAll("void"),
    }
}

fn fieldType(field: schema.FieldDescriptor) []const u8 {
    const base = switch (field.kind) {
        .scalar => |scalar| scalarZigType(scalar),
        .enumeration => "i32",
        .message, .group => "[]const u8",
        else => "void",
    };
    if (field.cardinality != .repeated) return base;
    return switch (field.kind) {
        .scalar => |scalar| repeatedScalarZigType(scalar),
        .enumeration => "[]const i32",
        .message, .group => "[]const []const u8",
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

pub fn writeFieldDefault(file: *const schema.FileDescriptor, field: schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    if (field.kind == .map) return writer.writeAll(".empty");
    if (field.cardinality == .repeated) return writer.writeAll("&.{}");
    try writeFieldKindDefault(file, field.kind, field.default_value, writer);
}

fn writeFieldKindDefault(file: ?*const schema.FileDescriptor, kind: schema.FieldKind, default_value: ?schema.OptionValue, writer: *std.Io.Writer) Error!void {
    switch (kind) {
        .scalar => |scalar| try writeScalarDefault(scalar, default_value, writer),
        .enumeration => |name| try writeEnumDefault(file, name, default_value, writer),
        .message, .group => try writer.writeAll("\"\""),
        else => try writer.writeAll("{}"),
    }
}

fn writeEnumDefault(file: ?*const schema.FileDescriptor, enum_name: []const u8, default_value: ?schema.OptionValue, writer: *std.Io.Writer) Error!void {
    if (optionInt(i32, default_value)) |value| return try writer.print("{d}", .{value});
    if (file) |schema_file| {
        if (schema_file.findEnumDeep(enum_name)) |enumeration| {
            if (enumeration.values.items.len != 0) return try writer.print("{d}", .{enumeration.values.items[0].number});
        }
    }
    try writer.writeAll("0");
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
        // Use scientific notation so integer-valued defaults (for example 9e9)
        // stay float literals instead of invalid `f32 = 9000000000` text.
        try writer.print("{e}", .{value});
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

fn writeOptionValueTextLiteral(default_value: ?schema.OptionValue, writer: *std.Io.Writer) Error!void {
    const value = default_value orelse return try writer.writeAll("\"\"");
    switch (value) {
        .string, .identifier => |text| try writeZigStringLiteral(text, writer),
        .integer => |v| try writer.print("\"{d}\"", .{v}),
        .unsigned_integer => |v| try writer.print("\"{d}\"", .{v}),
        .float => |v| try writer.print("\"{d}\"", .{v}),
        .boolean => |v| try writer.writeAll(if (v) "\"true\"" else "\"false\""),
        .aggregate => |text| try writeZigStringLiteral(text, writer),
    }
}

fn optionBool(default_value: ?schema.OptionValue) ?bool {
    const value = default_value orelse return null;
    return schema.optionAsBool(value);
}

fn optionInt(comptime T: type, default_value: ?schema.OptionValue) ?T {
    const value = default_value orelse return null;
    return switch (value) {
        .integer => |v| if (v >= std.math.minInt(T) and v <= std.math.maxInt(T)) @intCast(v) else null,
        .unsigned_integer => |v| if (v <= std.math.maxInt(T)) @intCast(v) else null,
        .identifier, .string => |text| parseIntegerDefault(T, text) catch null,
        else => null,
    };
}

fn optionFloat(comptime T: type, default_value: ?schema.OptionValue) ?T {
    const value = default_value orelse return null;
    return switch (value) {
        .float => |v| @floatCast(v),
        .integer => |v| @floatFromInt(v),
        .unsigned_integer => |v| @floatFromInt(v),
        .identifier, .string => |text| parseSpecialFloatDefault(T, text) orelse (std.fmt.parseFloat(T, text) catch null),
        else => null,
    };
}

fn parseSpecialFloatDefault(comptime T: type, text: []const u8) ?T {
    var body = text;
    var negative = false;
    if (body.len != 0 and (body[0] == '-' or body[0] == '+')) {
        negative = body[0] == '-';
        body = body[1..];
    }
    if (std.ascii.eqlIgnoreCase(body, "inf") or std.ascii.eqlIgnoreCase(body, "infinity")) {
        const value = std.math.inf(T);
        return if (negative) -value else value;
    }
    if (std.ascii.eqlIgnoreCase(body, "nan")) return std.math.nan(T);
    return null;
}

fn parseIntegerDefault(comptime T: type, text: []const u8) !T {
    if (text.len == 0) return error.InvalidCharacter;
    var body = text;
    if (body[0] == '+' or body[0] == '-') {
        body = body[1..];
        if (body.len == 0) return error.InvalidCharacter;
    }
    if (body.len > 1 and body[0] == '0') {
        switch (body[1]) {
            'x', 'X', 'o', 'O', 'b', 'B' => return std.fmt.parseInt(T, text, 0),
            else => return std.fmt.parseInt(T, text, 8),
        }
    }
    return std.fmt.parseInt(T, text, 10);
}

pub fn writeZigStringLiteral(value: []const u8, writer: *std.Io.Writer) Error!void {
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

pub fn writeZigLowerCamelStringLiteral(value: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeByte('"');
    try writeLowerCamelEscaped(value, writer);
    try writer.writeByte('"');
}

pub fn writeJsonFieldNameLiteralContents(field: *const schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    if (field.json_name) |json_name| {
        try writeEscapedStringContents(json_name, writer);
    } else {
        try writeLowerCamelEscaped(field.name, writer);
    }
}

fn writeLowerCamelEscaped(value: []const u8, writer: *std.Io.Writer) Error!void {
    var upper_next = false;
    for (value) |c| {
        if (c == '_') {
            upper_next = true;
            continue;
        }
        const out = if (upper_next) std.ascii.toUpper(c) else c;
        upper_next = false;
        try writeEscapedStringChar(out, writer);
    }
}

pub fn writeEscapedStringContents(value: []const u8, writer: *std.Io.Writer) Error!void {
    for (value) |c| try writeEscapedStringChar(c, writer);
}

fn writeEscapedStringChar(c: u8, writer: *std.Io.Writer) Error!void {
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

fn writeIdentWithSuffix(name: []const u8, suffix: []const u8, writer: *std.Io.Writer) Error!void {
    if (canWriteBareIdentParts("", name, suffix)) {
        try writer.writeAll(name);
        return try writer.writeAll(suffix);
    }
    return try writeQuotedIdentWithSuffix(name, suffix, writer);
}

fn writeIdentWithPrefix(name: []const u8, prefix: []const u8, writer: *std.Io.Writer) Error!void {
    if (canWriteBareIdentParts(prefix, name, "")) {
        try writer.writeAll(prefix);
        return try writer.writeAll(name);
    }
    return try writeQuotedIdentWithPrefix(name, prefix, writer);
}

fn canWriteBareIdent(name: []const u8) bool {
    if (std.mem.eql(u8, name, "_")) return false;
    if (!canWriteBareIdentParts("", name, "")) return false;
    if (std.zig.Token.getKeyword(name) != null) return false;
    if (isPrimitiveIdent(name)) return false;
    return true;
}

fn canWriteBareIdentParts(prefix: []const u8, name: []const u8, suffix: []const u8) bool {
    const total_len = prefix.len + name.len + suffix.len;
    if (total_len == 0) return false;
    var index: usize = 0;
    for (prefix) |c| {
        if (!isBareIdentChar(c, index == 0)) return false;
        index += 1;
    }
    for (name) |c| {
        if (!isBareIdentChar(c, index == 0)) return false;
        index += 1;
    }
    for (suffix) |c| {
        if (!isBareIdentChar(c, index == 0)) return false;
        index += 1;
    }
    return true;
}

fn isBareIdentChar(c: u8, first: bool) bool {
    return switch (c) {
        'a'...'z', 'A'...'Z', '_' => true,
        '0'...'9' => !first,
        else => false,
    };
}

fn isPrimitiveIdent(name: []const u8) bool {
    if (std.mem.eql(u8, name, "bool") or
        std.mem.eql(u8, name, "void") or
        std.mem.eql(u8, name, "noreturn") or
        std.mem.eql(u8, name, "type") or
        std.mem.eql(u8, name, "anyerror") or
        std.mem.eql(u8, name, "anyopaque") or
        std.mem.eql(u8, name, "comptime_int") or
        std.mem.eql(u8, name, "comptime_float") or
        std.mem.eql(u8, name, "isize") or
        std.mem.eql(u8, name, "usize") or
        std.mem.eql(u8, name, "true") or
        std.mem.eql(u8, name, "false") or
        std.mem.eql(u8, name, "null") or
        std.mem.eql(u8, name, "undefined") or
        std.mem.eql(u8, name, "c_char") or
        std.mem.eql(u8, name, "c_short") or
        std.mem.eql(u8, name, "c_ushort") or
        std.mem.eql(u8, name, "c_int") or
        std.mem.eql(u8, name, "c_uint") or
        std.mem.eql(u8, name, "c_long") or
        std.mem.eql(u8, name, "c_ulong") or
        std.mem.eql(u8, name, "c_longlong") or
        std.mem.eql(u8, name, "c_ulonglong") or
        std.mem.eql(u8, name, "c_longdouble") or
        std.mem.eql(u8, name, "f16") or
        std.mem.eql(u8, name, "f32") or
        std.mem.eql(u8, name, "f64") or
        std.mem.eql(u8, name, "f80") or
        std.mem.eql(u8, name, "f128"))
    {
        return true;
    }
    if (name.len >= 2 and (name[0] == 'i' or name[0] == 'u')) {
        for (name[1..]) |c| if (c < '0' or c > '9') return false;
        return true;
    }
    return false;
}

pub fn writeQuotedIdent(name: []const u8, writer: *std.Io.Writer) Error!void {
    if (canWriteBareIdent(name)) return try writer.writeAll(name);
    try writer.writeAll("@\"");
    for (name) |c| {
        if (c == '\\' or c == '"') try writer.writeByte('\\');
        try writer.writeByte(c);
    }
    try writer.writeAll("\"");
}

pub fn writeQuotedIdentWithSuffix(name: []const u8, suffix: []const u8, writer: *std.Io.Writer) Error!void {
    if (canWriteBareIdentParts("", name, suffix)) {
        try writer.writeAll(name);
        return try writer.writeAll(suffix);
    }
    try writer.writeAll("@\"");
    for (name) |c| {
        if (c == '\\' or c == '"') try writer.writeByte('\\');
        try writer.writeByte(c);
    }
    try writer.writeAll(suffix);
    try writer.writeAll("\"");
}

pub fn writeQuotedIdentWithPrefix(name: []const u8, prefix: []const u8, writer: *std.Io.Writer) Error!void {
    if (canWriteBareIdentParts(prefix, name, "")) {
        try writer.writeAll(prefix);
        return try writer.writeAll(name);
    }
    try writer.writeAll("@\"");
    try writer.writeAll(prefix);
    for (name) |c| {
        if (c == '\\' or c == '"') try writer.writeByte('\\');
        try writer.writeByte(c);
    }
    try writer.writeAll("\"");
}

pub fn hasPresence(file: *const schema.FileDescriptor, field: schema.FieldDescriptor) bool {
    if (field.cardinality == .required or field.proto3_optional or field.oneof_name != null or field.kind == .message or field.kind == .group) return true;
    if (field.cardinality == .repeated or field.kind == .map) return false;
    return schema.FeatureSet.effective(field.features, file.features).field_presence != .implicit;
}

pub fn isRequired(field: schema.FieldDescriptor) bool {
    if (field.cardinality == .required) return true;
    if (field.features) |features| return features.field_presence == .legacy_required;
    return false;
}

pub fn writePresenceIdent(name: []const u8, writer: *std.Io.Writer) Error!void {
    try writeIdentWithPrefix(name, "has_", writer);
}

fn writeSetPresence(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    if (hasPresence(file, field.*)) {
        try writer.writeAll(" self.");
        try writePresenceIdent(field.name, writer);
        try writer.writeAll(" = true;");
    }
}

fn writeQuotedFieldNumber(name: []const u8, writer: *std.Io.Writer) Error!void {
    try writeIdentWithSuffix(name, "_number", writer);
}

pub fn indent(writer: *std.Io.Writer, depth: usize) Error!void {
    var i: usize = 0;
    while (i < depth) : (i += 1) try writer.writeAll("    ");
}

pub fn outputNameWithOptions(allocator: std.mem.Allocator, input: []const u8, suffix: []const u8, strip_proto_ext: bool) std.mem.Allocator.Error![]u8 {
    const base = if (input.len == 0) "schema.proto" else input;
    const stem = if (strip_proto_ext and std.mem.endsWith(u8, base, ".proto")) base[0 .. base.len - 6] else base;
    return try std.fmt.allocPrint(allocator, "{s}{s}", .{ stem, suffix });
}

pub fn extensionAppliesToMessage(file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) bool {
    const extendee = field.extendee orelse return false;
    if (findExtensionExtendeeInFile(file, field)) |resolved| return resolved == message;
    const trimmed = if (std.mem.startsWith(u8, extendee, ".")) extendee[1..] else extendee;
    const leaf = if (std.mem.lastIndexOfScalar(u8, trimmed, '.')) |idx| trimmed[idx + 1 ..] else trimmed;
    return std.mem.eql(u8, message.name, trimmed) or std.mem.eql(u8, message.name, leaf);
}

pub fn findMessageByQualifiedName(file: *const schema.FileDescriptor, name: []const u8) ?*const schema.MessageDescriptor {
    var normalized = if (std.mem.startsWith(u8, name, ".")) name[1..] else name;
    if (file.package.len != 0 and std.mem.startsWith(u8, normalized, file.package)) {
        if (normalized.len == file.package.len) return null;
        if (normalized.len > file.package.len and normalized[file.package.len] == '.') normalized = normalized[file.package.len + 1 ..];
    }
    return findMessageByPath(file.messages.items, normalized);
}

pub fn leafTypeName(name: []const u8) []const u8 {
    const trimmed = if (std.mem.startsWith(u8, name, ".")) name[1..] else name;
    return if (std.mem.lastIndexOfScalar(u8, trimmed, '.')) |idx| trimmed[idx + 1 ..] else trimmed;
}

pub fn typedSingularMessageFieldWithContext(ctx: *const CodegenContext, field: *const schema.FieldDescriptor) ?[]const u8 {
    if (field.oneof_name != null or field.cardinality == .repeated) return null;
    return typedLengthPrefixedOrGroupFieldWithContext(ctx, field);
}

pub fn typedRepeatedMessageFieldWithContext(ctx: *const CodegenContext, field: *const schema.FieldDescriptor) ?[]const u8 {
    if (field.oneof_name != null or field.cardinality != .repeated) return null;
    return typedLengthPrefixedOrGroupFieldWithContext(ctx, field);
}

pub fn typedOneofMessageFieldWithContext(ctx: *const CodegenContext, field: *const schema.FieldDescriptor) ?[]const u8 {
    if (field.oneof_name == null) return null;
    return typedLengthPrefixedOrGroupFieldWithContext(ctx, field);
}

pub fn typedMapMessageValueWithContext(ctx: *const CodegenContext, field: *const schema.FieldDescriptor) ?[]const u8 {
    const map_type = switch (field.kind) {
        .map => |map| map,
        else => return null,
    };
    return switch (map_type.value.*) {
        .message => |name| if (codegenCanReferenceMessageWithContext(ctx, name)) name else null,
        else => null,
    };
}

pub fn findExtensionExtendeeInFile(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor) ?*const schema.MessageDescriptor {
    const extendee = field.extendee orelse return null;
    if (std.mem.startsWith(u8, extendee, ".")) return findMessageByQualifiedName(file, extendee);
    if (extensionScopeForCodegen(file, field)) |scope| {
        var current = scope;
        while (true) {
            var buf: [512]u8 = undefined;
            if (current.len + 1 + extendee.len <= buf.len) {
                const candidate = std.fmt.bufPrint(&buf, "{s}.{s}", .{ current, extendee }) catch unreachable;
                if (findMessageByQualifiedName(file, candidate)) |message| return message;
            }
            if (std.mem.lastIndexOfScalar(u8, current, '.')) |idx| {
                current = current[0..idx];
            } else break;
        }
    }
    if (std.mem.indexOfScalar(u8, extendee, '.') != null) return findMessageByQualifiedName(file, extendee);
    return null;
}

pub fn findMessageByPath(messages: []const schema.MessageDescriptor, path: []const u8) ?*const schema.MessageDescriptor {
    if (path.len == 0) return null;
    const head, const tail = splitFirst(path);
    for (messages) |*message| {
        if (!std.mem.eql(u8, message.name, head)) continue;
        if (tail.len == 0) return message;
        return findMessageByPath(message.messages.items, tail);
    }
    return null;
}

pub fn typedLengthPrefixedOrGroupFieldWithContext(ctx: *const CodegenContext, field: *const schema.FieldDescriptor) ?[]const u8 {
    const type_name = switch (field.kind) {
        .message => |name| blk: {
            if (fieldMessageEncoding(ctx.file, field) != .length_prefixed) return null;
            break :blk name;
        },
        .group => |name| name,
        else => return null,
    };
    if (!codegenCanReferenceMessageWithContext(ctx, type_name)) return null;
    if (field.cardinality != .repeated and fieldCreatesValueDependencyCycle(ctx, field, type_name)) return null;
    return type_name;
}

pub fn writeTypedMessageTypeWithContext(ctx: *const CodegenContext, type_name: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeByte('?');
    try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
}

pub fn splitFirst(name: []const u8) struct { []const u8, []const u8 } {
    if (std.mem.indexOfScalar(u8, name, '.')) |idx| return .{ name[0..idx], name[idx + 1 ..] };
    return .{ name, "" };
}

pub fn fieldCreatesValueDependencyCycle(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, type_name: []const u8) bool {
    const current = containingMessageForField(ctx.file, field) orelse return false;
    const target_ref = resolveMessageReference(ctx, type_name) orelse return false;
    if (!sameFileForCodegen(target_ref.file, ctx.file)) return false;
    return messageHasValuePathTo(ctx, target_ref.message, current, 0);
}

pub fn writeTypedRepeatedMessageTypeWithContext(ctx: *const CodegenContext, type_name: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("[]const ");
    try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
}

pub fn containingMessageForField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor) ?*const schema.MessageDescriptor {
    for (file.messages.items) |*message| {
        if (messageContainsField(message, field)) |owner| return owner;
    }
    return null;
}

pub fn messageContainsField(message: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) ?*const schema.MessageDescriptor {
    for (message.fields.items) |*candidate| {
        if (candidate == field) return message;
    }
    for (message.messages.items) |*nested| {
        if (messageContainsField(nested, field)) |owner| return owner;
    }
    return null;
}

pub fn messageHasValuePathTo(ctx: *const CodegenContext, from: *const schema.MessageDescriptor, target: *const schema.MessageDescriptor, depth: usize) bool {
    if (from == target) return true;
    if (depth >= 64) return true;
    for (from.fields.items) |*field| {
        if (field.cardinality == .repeated or field.kind == .map) continue;
        const type_name = switch (field.kind) {
            .message => |name| blk: {
                if (fieldMessageEncoding(ctx.file, field) != .length_prefixed) continue;
                break :blk name;
            },
            .group => |name| name,
            else => continue,
        };
        const ref = resolveMessageReference(ctx, type_name) orelse continue;
        if (!sameFileForCodegen(ref.file, ctx.file)) continue;
        if (messageHasValuePathTo(ctx, ref.message, target, depth + 1)) return true;
    }
    return false;
}

test {
    _ = @import("codegen/tests.zig");
}

/// Internal emit helpers exposed to the phase modules.
const __pbz_emit_canReferenceEnumWithContext = canReferenceEnumWithContext;
const __pbz_emit_canReferenceMessageWithContext = canReferenceMessageWithContext;
const __pbz_emit_canWriteBareIdent = canWriteBareIdent;
const __pbz_emit_codegenCanReferenceEnumWithContext = codegenCanReferenceEnumWithContext;
const __pbz_emit_fieldKindName = fieldKindName;
const __pbz_emit_fieldType = fieldType;
const __pbz_emit_fieldTypeName = fieldTypeName;
const __pbz_emit_fixedWidthViewScalarType = fixedWidthViewScalarType;
const __pbz_emit_isBareIdentChar = isBareIdentChar;
const __pbz_emit_messageCanDecodeKnownReuse = messageCanDecodeKnownReuse;
const __pbz_emit_messageFullNameForCodegen = messageFullNameForCodegen;
const __pbz_emit_oneofHasTypedMessageWithContext = oneofHasTypedMessageWithContext;
const __pbz_emit_rawFieldTag = rawFieldTag;
const __pbz_emit_rawTagValue = rawTagValue;
const __pbz_emit_scalarZigType = scalarZigType;
const __pbz_emit_writeAdoptOwned = writeAdoptOwned;
const __pbz_emit_writeBorrowedViewMethods = writeBorrowedViewMethods;
const __pbz_emit_writeClear = writeClear;
const __pbz_emit_writeCloneOwned = writeCloneOwned;
const __pbz_emit_writeDecode = writeDecode;
const __pbz_emit_writeDecodeInitialized = writeDecodeInitialized;
const __pbz_emit_writeDecodeKnownReuse = writeDecodeKnownReuse;
const __pbz_emit_writeDecodeOwnedReuse = writeDecodeOwnedReuse;
const __pbz_emit_writeDecodeReuse = writeDecodeReuse;
const __pbz_emit_writeDeinit = writeDeinit;
const __pbz_emit_writeEncode = writeEncode;
const __pbz_emit_writeEncodeDeterministic = writeEncodeDeterministic;
const __pbz_emit_writeEncodeInitialized = writeEncodeInitialized;
const __pbz_emit_writeEntryReadExpr = writeEntryReadExpr;
const __pbz_emit_writeEnumTypeReferenceOrVoid = writeEnumTypeReferenceOrVoid;
const __pbz_emit_writeEnumTypeReferenceWithContext = writeEnumTypeReferenceWithContext;
const __pbz_emit_writeExtensionMetadata = writeExtensionMetadata;
const __pbz_emit_writeFieldKindDefault = writeFieldKindDefault;
const __pbz_emit_writeFieldKindType = writeFieldKindType;
const __pbz_emit_writeFieldType = writeFieldType;
const __pbz_emit_writeKindWriteCall = writeKindWriteCall;
const __pbz_emit_writeMapStorageType = writeMapStorageType;
const __pbz_emit_writeMergeFrom = writeMergeFrom;
const __pbz_emit_writeMessage = writeMessage;
const __pbz_emit_writeMessageConformantParsers = writeMessageConformantParsers;
const __pbz_emit_writeMessageDescriptorLookup = writeMessageDescriptorLookup;
const __pbz_emit_writeMessageDynamicBridge = writeMessageDynamicBridge;
const __pbz_emit_writeMessageExtensionAccessors = writeMessageExtensionAccessors;
const __pbz_emit_writeMessageTypeReferenceOrVoid = writeMessageTypeReferenceOrVoid;
const __pbz_emit_writeMissingRequiredFieldName = writeMissingRequiredFieldName;
const __pbz_emit_writeMissingRequiredFieldPath = writeMissingRequiredFieldPath;
const __pbz_emit_writeOptionValueTextLiteral = writeOptionValueTextLiteral;
const __pbz_emit_writePackedKindPayload = writePackedKindPayload;
const __pbz_emit_writeQualifiedMessageTypeReference = writeQualifiedMessageTypeReference;
const __pbz_emit_writeQuotedFieldNumber = writeQuotedFieldNumber;
const __pbz_emit_writeScalarDefault = writeScalarDefault;
const __pbz_emit_writeSetPresence = writeSetPresence;
const __pbz_emit_writeUnknownFieldMethods = writeUnknownFieldMethods;
const __pbz_emit_writeValidateRequired = writeValidateRequired;
pub const emit_helpers = struct {
    pub const canReferenceEnumWithContext = __pbz_emit_canReferenceEnumWithContext;
    pub const canReferenceMessageWithContext = __pbz_emit_canReferenceMessageWithContext;
    pub const canWriteBareIdent = __pbz_emit_canWriteBareIdent;
    pub const codegenCanReferenceEnumWithContext = __pbz_emit_codegenCanReferenceEnumWithContext;
    pub const fieldKindName = __pbz_emit_fieldKindName;
    pub const fieldType = __pbz_emit_fieldType;
    pub const fieldTypeName = __pbz_emit_fieldTypeName;
    pub const fixedWidthViewScalarType = __pbz_emit_fixedWidthViewScalarType;
    pub const isBareIdentChar = __pbz_emit_isBareIdentChar;
    pub const messageCanDecodeKnownReuse = __pbz_emit_messageCanDecodeKnownReuse;
    pub const messageFullNameForCodegen = __pbz_emit_messageFullNameForCodegen;
    pub const oneofHasTypedMessageWithContext = __pbz_emit_oneofHasTypedMessageWithContext;
    pub const rawFieldTag = __pbz_emit_rawFieldTag;
    pub const rawTagValue = __pbz_emit_rawTagValue;
    pub const scalarZigType = __pbz_emit_scalarZigType;
    pub const writeAdoptOwned = __pbz_emit_writeAdoptOwned;
    pub const writeBorrowedViewMethods = __pbz_emit_writeBorrowedViewMethods;
    pub const writeClear = __pbz_emit_writeClear;
    pub const writeCloneOwned = __pbz_emit_writeCloneOwned;
    pub const writeDecode = __pbz_emit_writeDecode;
    pub const writeDecodeInitialized = __pbz_emit_writeDecodeInitialized;
    pub const writeDecodeKnownReuse = __pbz_emit_writeDecodeKnownReuse;
    pub const writeDecodeOwnedReuse = __pbz_emit_writeDecodeOwnedReuse;
    pub const writeDecodeReuse = __pbz_emit_writeDecodeReuse;
    pub const writeDeinit = __pbz_emit_writeDeinit;
    pub const writeEncode = __pbz_emit_writeEncode;
    pub const writeEncodeDeterministic = __pbz_emit_writeEncodeDeterministic;
    pub const writeEncodeInitialized = __pbz_emit_writeEncodeInitialized;
    pub const writeEntryReadExpr = __pbz_emit_writeEntryReadExpr;
    pub const writeEnumTypeReferenceOrVoid = __pbz_emit_writeEnumTypeReferenceOrVoid;
    pub const writeEnumTypeReferenceWithContext = __pbz_emit_writeEnumTypeReferenceWithContext;
    pub const writeExtensionMetadata = __pbz_emit_writeExtensionMetadata;
    pub const writeFieldKindDefault = __pbz_emit_writeFieldKindDefault;
    pub const writeFieldKindType = __pbz_emit_writeFieldKindType;
    pub const writeFieldType = __pbz_emit_writeFieldType;
    pub const writeKindWriteCall = __pbz_emit_writeKindWriteCall;
    pub const writeMapStorageType = __pbz_emit_writeMapStorageType;
    pub const writeMergeFrom = __pbz_emit_writeMergeFrom;
    pub const writeMessage = __pbz_emit_writeMessage;
    pub const writeMessageConformantParsers = __pbz_emit_writeMessageConformantParsers;
    pub const writeMessageDescriptorLookup = __pbz_emit_writeMessageDescriptorLookup;
    pub const writeMessageDynamicBridge = __pbz_emit_writeMessageDynamicBridge;
    pub const writeMessageExtensionAccessors = __pbz_emit_writeMessageExtensionAccessors;
    pub const writeMessageTypeReferenceOrVoid = __pbz_emit_writeMessageTypeReferenceOrVoid;
    pub const writeMissingRequiredFieldName = __pbz_emit_writeMissingRequiredFieldName;
    pub const writeMissingRequiredFieldPath = __pbz_emit_writeMissingRequiredFieldPath;
    pub const writeOptionValueTextLiteral = __pbz_emit_writeOptionValueTextLiteral;
    pub const writePackedKindPayload = __pbz_emit_writePackedKindPayload;
    pub const writeQualifiedMessageTypeReference = __pbz_emit_writeQualifiedMessageTypeReference;
    pub const writeQuotedFieldNumber = __pbz_emit_writeQuotedFieldNumber;
    pub const writeScalarDefault = __pbz_emit_writeScalarDefault;
    pub const writeSetPresence = __pbz_emit_writeSetPresence;
    pub const writeUnknownFieldMethods = __pbz_emit_writeUnknownFieldMethods;
    pub const writeValidateRequired = __pbz_emit_writeValidateRequired;
};

pub const writeMissingRequiredFieldName = validate_emit.writeMissingRequiredFieldName;
pub const writeMissingRequiredFieldPath = validate_emit.writeMissingRequiredFieldPath;
pub const writeMissingRequiredPathExtensionPayloads = validate_emit.writeMissingRequiredPathExtensionPayloads;
pub const writeMissingRequiredPathScopedExtensionPayloads = validate_emit.writeMissingRequiredPathScopedExtensionPayloads;
pub const writeMissingRequiredPathExtensionPayload = validate_emit.writeMissingRequiredPathExtensionPayload;
pub const writeMissingRequiredPathField = validate_emit.writeMissingRequiredPathField;
pub const writeMissingRequiredPathMapField = validate_emit.writeMissingRequiredPathMapField;
pub const writeMissingRequiredPathOneof = validate_emit.writeMissingRequiredPathOneof;
pub const writeMissingRequiredPathPayload = validate_emit.writeMissingRequiredPathPayload;
pub const writeValidateRequired = validate_emit.writeValidateRequired;
pub const writeValidateMessageExtensionPayloads = validate_emit.writeValidateMessageExtensionPayloads;
pub const writeValidateScopedMessageExtensionPayloads = validate_emit.writeValidateScopedMessageExtensionPayloads;
pub const writeValidateMessageExtensionPayload = validate_emit.writeValidateMessageExtensionPayload;
pub const writeValidateMessagePayloadField = validate_emit.writeValidateMessagePayloadField;
pub const writeValidateMapMessagePayloadField = validate_emit.writeValidateMapMessagePayloadField;
pub const fieldHasMessageMapValue = validate_emit.fieldHasMessageMapValue;
pub const writeValidateMessagePayloadOneof = validate_emit.writeValidateMessagePayloadOneof;
pub const writeDecodeAndValidatePayload = validate_emit.writeDecodeAndValidatePayload;
pub const oneofHasMessageField = validate_emit.oneofHasMessageField;
pub const writeMergeFrom = lifecycle_emit.writeMergeFrom;
pub const mergeUsesOwnedAllocator = lifecycle_emit.mergeUsesOwnedAllocator;
pub const mergeFieldUsesOwnedAllocator = lifecycle_emit.mergeFieldUsesOwnedAllocator;
pub const writeMergeField = lifecycle_emit.writeMergeField;
pub const writeMergeRepeatedField = lifecycle_emit.writeMergeRepeatedField;
pub const writeMergeMapField = lifecycle_emit.writeMergeMapField;
pub const writeMergeSingularMessageField = lifecycle_emit.writeMergeSingularMessageField;
pub const writeMergeSingularScalarField = lifecycle_emit.writeMergeSingularScalarField;
pub const writeMergeSingularEnumField = lifecycle_emit.writeMergeSingularEnumField;
pub const writeMergeOneof = lifecycle_emit.writeMergeOneof;
pub const writeDeinit = lifecycle_emit.writeDeinit;
pub const writeClear = lifecycle_emit.writeClear;
pub const writeCloneOwned = lifecycle_emit.writeCloneOwned;
pub const cloneUsesOwnedAllocator = lifecycle_emit.cloneUsesOwnedAllocator;
pub const cloneFieldUsesOwnedAllocator = lifecycle_emit.cloneFieldUsesOwnedAllocator;
pub const cloneKindUsesOwnedAllocator = lifecycle_emit.cloneKindUsesOwnedAllocator;
pub const writeCloneField = lifecycle_emit.writeCloneField;
pub const writeCloneRepeatedField = lifecycle_emit.writeCloneRepeatedField;
pub const writeCloneMapField = lifecycle_emit.writeCloneMapField;
pub const writeCloneOneof = lifecycle_emit.writeCloneOneof;
pub const writeCloneUnknownFields = lifecycle_emit.writeCloneUnknownFields;
pub const writeAdoptOwned = lifecycle_emit.writeAdoptOwned;
pub const adoptIntoUsesAllocator = lifecycle_emit.adoptIntoUsesAllocator;
pub const writeAdoptTotalField = lifecycle_emit.writeAdoptTotalField;
pub const writeAdoptTotalRepeatedField = lifecycle_emit.writeAdoptTotalRepeatedField;
pub const writeAdoptTotalMapField = lifecycle_emit.writeAdoptTotalMapField;
pub const writeAdoptTotalOneof = lifecycle_emit.writeAdoptTotalOneof;
pub const adoptHasWork = lifecycle_emit.adoptHasWork;
pub const writeAdoptField = lifecycle_emit.writeAdoptField;
pub const writeAdoptRepeatedField = lifecycle_emit.writeAdoptRepeatedField;
pub const writeAdoptMapField = lifecycle_emit.writeAdoptMapField;
pub const writeAdoptOneof = lifecycle_emit.writeAdoptOneof;
pub const writeCloneFieldValueExpr = lifecycle_emit.writeCloneFieldValueExpr;
pub const writeCloneValueExpr = lifecycle_emit.writeCloneValueExpr;
pub const writeMessageExtensionAccessors = extension_emit.writeMessageExtensionAccessors;
pub const collectScopedMessageExtensionFields = extension_emit.collectScopedMessageExtensionFields;
pub const uniqueExtensionSuffixes = extension_emit.uniqueExtensionSuffixes;
pub const uniqueExtensionSuffix = extension_emit.uniqueExtensionSuffix;
pub const suffixFromComponents = extension_emit.suffixFromComponents;
pub const writeMessageExtensionAccessor = extension_emit.writeMessageExtensionAccessor;
pub const writeMessageEnumExtensionAccessor = extension_emit.writeMessageEnumExtensionAccessor;
pub const writeMessageExtensionTypedAccessor = extension_emit.writeMessageExtensionTypedAccessor;
pub const writeExtensionMetadata = extension_emit.writeExtensionMetadata;
pub const writeMessageExtensions = extension_emit.writeMessageExtensions;
pub const writeExtensionDecl = extension_emit.writeExtensionDecl;
pub const extensionExtendeeHasTypeRef = extension_emit.extensionExtendeeHasTypeRef;
pub const writeExtensionTypedZigTypeLiteral = extension_emit.writeExtensionTypedZigTypeLiteral;
pub const writeExtensionExtendeeTypeRef = extension_emit.writeExtensionExtendeeTypeRef;
pub const writeExtensionFacadeHelpers = extension_emit.writeExtensionFacadeHelpers;
pub const writeExtensionEnumFacadeHelpers = extension_emit.writeExtensionEnumFacadeHelpers;
pub const writeExtensionMessageFacadeHelpers = extension_emit.writeExtensionMessageFacadeHelpers;
pub const writeExtensionWriteHelpers = extension_emit.writeExtensionWriteHelpers;
pub const extensionUsesMessageSet = extension_emit.extensionUsesMessageSet;
pub const writeExtensionDecodeHelpers = extension_emit.writeExtensionDecodeHelpers;
pub const extensionSingleZigType = extension_emit.extensionSingleZigType;
pub const extensionValueTypeName = extension_emit.extensionValueTypeName;
pub const countExtensions = extension_emit.countExtensions;
pub const countMessageExtensions = extension_emit.countMessageExtensions;
pub const extensionAccessorSuffix = extension_emit.extensionAccessorSuffix;
pub const writeExtensionHelperReference = extension_emit.writeExtensionHelperReference;
pub const writeExtensionHelperIdent = extension_emit.writeExtensionHelperIdent;
pub const writeEncodeOneof = encode_emit.writeEncodeOneof;
pub const writeEncodeOneofAssumeCapacity = encode_emit.writeEncodeOneofAssumeCapacity;
pub const writeEncode = encode_emit.writeEncode;
pub const messageCanFastDirectEncode = encode_emit.messageCanFastDirectEncode;
pub const mapCanFastDirectEncode = encode_emit.mapCanFastDirectEncode;
pub const writeFastDirectEncodeIntoAssumeCapacity = encode_emit.writeFastDirectEncodeIntoAssumeCapacity;
pub const writeFastDirectScalarEncode = encode_emit.writeFastDirectScalarEncode;
pub const writeFastDirectEnumEncode = encode_emit.writeFastDirectEnumEncode;
pub const writeFastDirectRepeatedScalarEncode = encode_emit.writeFastDirectRepeatedScalarEncode;
pub const writeFastDirectSingularMessageEncode = encode_emit.writeFastDirectSingularMessageEncode;
pub const writeFastDirectRepeatedMessageEncode = encode_emit.writeFastDirectRepeatedMessageEncode;
pub const writeFastDirectMapEncode = encode_emit.writeFastDirectMapEncode;
pub const writeFastDirectMapUtf8Validation = encode_emit.writeFastDirectMapUtf8Validation;
pub const writeFastDirectMapValuePayload = encode_emit.writeFastDirectMapValuePayload;
pub const writeFastDirectMapScalarPayload = encode_emit.writeFastDirectMapScalarPayload;
pub const writeFastDirectOneofEncode = encode_emit.writeFastDirectOneofEncode;
pub const writeFastDirectMessagePayload = encode_emit.writeFastDirectMessagePayload;
pub const writeFastDirectLengthDelimitedValidation = encode_emit.writeFastDirectLengthDelimitedValidation;
pub const writeFastDirectLengthDelimitedPayload = encode_emit.writeFastDirectLengthDelimitedPayload;
pub const writeFastDirectRepeatedEnumEncode = encode_emit.writeFastDirectRepeatedEnumEncode;
pub const writeFastDirectPackedScalarEncode = encode_emit.writeFastDirectPackedScalarEncode;
pub const writeFastDirectPackedEnumEncode = encode_emit.writeFastDirectPackedEnumEncode;
pub const writeFastDirectTag = encode_emit.writeFastDirectTag;
pub const writeFastDirectRawTag = encode_emit.writeFastDirectRawTag;
pub const writeFastDirectTagValue = encode_emit.writeFastDirectTagValue;
pub const writeFastDirectScalarPayload = encode_emit.writeFastDirectScalarPayload;
pub const writeFastDirectRawFieldPayload = encode_emit.writeFastDirectRawFieldPayload;
pub const writeFastDirectVarintFieldPayload = encode_emit.writeFastDirectVarintFieldPayload;
pub const writeFastDirectBoolFieldPayload = encode_emit.writeFastDirectBoolFieldPayload;
pub const writeFastDirectPackedScalarPayload = encode_emit.writeFastDirectPackedScalarPayload;
pub const maxPackedScalarWidth = encode_emit.maxPackedScalarWidth;
pub const writeEncodedSize = encode_emit.writeEncodedSize;
pub const writeEncodedSizeField = encode_emit.writeEncodedSizeField;
pub const writeEncodedSizeRepeatedField = encode_emit.writeEncodedSizeRepeatedField;
pub const writeEncodedSizeMapField = encode_emit.writeEncodedSizeMapField;
pub const writeEncodedSizeOneof = encode_emit.writeEncodedSizeOneof;
pub const writeSingleFieldEncodedSizeExpr = encode_emit.writeSingleFieldEncodedSizeExpr;
pub const writeSingleFieldEncodedSizeExprForValue = encode_emit.writeSingleFieldEncodedSizeExprForValue;
pub const writeSingleFieldEncodedSizePrefix = encode_emit.writeSingleFieldEncodedSizePrefix;
pub const writeKindPayloadSizeExprForField = encode_emit.writeKindPayloadSizeExprForField;
pub const writeScalarPayloadSizeExprForField = encode_emit.writeScalarPayloadSizeExprForField;
pub const writeEncodeDeterministic = encode_emit.writeEncodeDeterministic;
pub const writeEncodeUnknownFields = encode_emit.writeEncodeUnknownFields;
pub const writeEncodeUnknownFieldsDeterministic = encode_emit.writeEncodeUnknownFieldsDeterministic;
pub const writeEncodeUnknownFieldsDeterministicAssumeCapacity = encode_emit.writeEncodeUnknownFieldsDeterministicAssumeCapacity;
pub const writeEncodeFieldsByNumber = encode_emit.writeEncodeFieldsByNumber;
pub const writeEncodeFieldsByNumberAssumeCapacity = encode_emit.writeEncodeFieldsByNumberAssumeCapacity;
pub const writeEncodeOneofSingleField = encode_emit.writeEncodeOneofSingleField;
pub const writeEncodeOneofSingleFieldDeterministicAssumeCapacity = encode_emit.writeEncodeOneofSingleFieldDeterministicAssumeCapacity;
pub const writeOneofValueEncodeDeterministic = encode_emit.writeOneofValueEncodeDeterministic;
pub const writeOneofValueEncodeDeterministicAssumeCapacity = encode_emit.writeOneofValueEncodeDeterministicAssumeCapacity;
pub const writeEncodeInitialized = encode_emit.writeEncodeInitialized;
pub const writeEncodeField = encode_emit.writeEncodeField;
pub const writeEncodeFieldAssumeCapacity = encode_emit.writeEncodeFieldAssumeCapacity;
pub const writeEncodeFieldDeterministic = encode_emit.writeEncodeFieldDeterministic;
pub const writeEncodeFieldDeterministicAssumeCapacity = encode_emit.writeEncodeFieldDeterministicAssumeCapacity;
pub const writeEncodeScalarField = encode_emit.writeEncodeScalarField;
pub const writeEncodeEnumField = encode_emit.writeEncodeEnumField;
pub const writeEncodeScalarFieldAssumeCapacity = encode_emit.writeEncodeScalarFieldAssumeCapacity;
pub const writeEncodeEnumFieldAssumeCapacity = encode_emit.writeEncodeEnumFieldAssumeCapacity;
pub const writeEncodePackedScalarField = encode_emit.writeEncodePackedScalarField;
pub const writeEncodePackedEnumField = encode_emit.writeEncodePackedEnumField;
pub const writeEncodePackedScalarFieldAssumeCapacity = encode_emit.writeEncodePackedScalarFieldAssumeCapacity;
pub const writeEncodePackedEnumFieldAssumeCapacity = encode_emit.writeEncodePackedEnumFieldAssumeCapacity;
pub const writeEncodePackedPrefix = encode_emit.writeEncodePackedPrefix;
pub const writeEncodePackedLength = encode_emit.writeEncodePackedLength;
pub const writeEncodePackedLengthAssumeCapacity = encode_emit.writeEncodePackedLengthAssumeCapacity;
pub const writeEncodePackedSuffix = encode_emit.writeEncodePackedSuffix;
pub const scalarPayloadSizeIsConstant = encode_emit.scalarPayloadSizeIsConstant;
pub const fixedPackedScalarWidth = encode_emit.fixedPackedScalarWidth;
pub const writePackedScalarSizeExpr = encode_emit.writePackedScalarSizeExpr;
pub const writePackedScalarPayload = encode_emit.writePackedScalarPayload;
pub const writePackedEnumPayload = encode_emit.writePackedEnumPayload;
pub const writePackedScalarPayloadAssumeCapacity = encode_emit.writePackedScalarPayloadAssumeCapacity;
pub const writePackedEnumPayloadAssumeCapacity = encode_emit.writePackedEnumPayloadAssumeCapacity;
pub const writePackedKindPayload = encode_emit.writePackedKindPayload;
pub const writeEncodeMessageField = encode_emit.writeEncodeMessageField;
pub const writeEncodeMessageFieldAssumeCapacity = encode_emit.writeEncodeMessageFieldAssumeCapacity;
pub const writeEncodeMessageFieldDeterministic = encode_emit.writeEncodeMessageFieldDeterministic;
pub const writeEncodeMessageFieldDeterministicAssumeCapacity = encode_emit.writeEncodeMessageFieldDeterministicAssumeCapacity;
pub const writeEncodeGroupFieldDeterministic = encode_emit.writeEncodeGroupFieldDeterministic;
pub const writeEncodeGroupFieldDeterministicAssumeCapacity = encode_emit.writeEncodeGroupFieldDeterministicAssumeCapacity;
pub const writeEncodeGroupFieldAssumeCapacity = encode_emit.writeEncodeGroupFieldAssumeCapacity;
pub const writeEncodeMessagePayloadDeterministic = encode_emit.writeEncodeMessagePayloadDeterministic;
pub const writeEncodeGroupField = encode_emit.writeEncodeGroupField;
pub const writeEncodeMapField = encode_emit.writeEncodeMapField;
pub const writeEncodeMapFieldAssumeCapacity = encode_emit.writeEncodeMapFieldAssumeCapacity;
pub const writeEncodeMapEntries = encode_emit.writeEncodeMapEntries;
pub const writeEncodeMapFieldDeterministic = encode_emit.writeEncodeMapFieldDeterministic;
pub const writeEncodeMapFieldDeterministicAssumeCapacity = encode_emit.writeEncodeMapFieldDeterministicAssumeCapacity;
pub const writeEncodeMapFieldDeterministicCommon = encode_emit.writeEncodeMapFieldDeterministicCommon;
pub const writeEncodeMapEntryBody = encode_emit.writeEncodeMapEntryBody;
pub const writeMapEntryEncodeUtf8Check = encode_emit.writeMapEntryEncodeUtf8Check;
pub const writeMapKeyLessExpr = encode_emit.writeMapKeyLessExpr;
pub const writeMapEntryValueFieldSizeExpr = encode_emit.writeMapEntryValueFieldSizeExpr;
pub const writeMapEntryValueWriteCall = encode_emit.writeMapEntryValueWriteCall;
pub const writeMapEntryFieldSizeExpr = encode_emit.writeMapEntryFieldSizeExpr;
pub const writeKindPayloadSizeExpr = encode_emit.writeKindPayloadSizeExpr;
pub const writeScalarPayloadSizeExpr = encode_emit.writeScalarPayloadSizeExpr;
pub const writeKindWriteCall = encode_emit.writeKindWriteCall;
pub const writeKindWriteCallAssumeCapacity = encode_emit.writeKindWriteCallAssumeCapacity;
pub const writeScalarWriteCall = encode_emit.writeScalarWriteCall;
pub const writeScalarWriteCallAssumeCapacity = encode_emit.writeScalarWriteCallAssumeCapacity;
pub const writeScalarSkipCondition = encode_emit.writeScalarSkipCondition;
pub const writeScalarSkipConditionWithOptions = encode_emit.writeScalarSkipConditionWithOptions;
pub const shouldSkipDefault = encode_emit.shouldSkipDefault;
pub const scalarWriterName = encode_emit.scalarWriterName;
pub const writeOneofValueEncode = encode_emit.writeOneofValueEncode;
pub const writeOneofValueEncodeAssumeCapacity = encode_emit.writeOneofValueEncodeAssumeCapacity;
pub const writeDecode = decode_emit.writeDecode;
pub const writeUnknownFieldFallback = decode_emit.writeUnknownFieldFallback;
pub const writeDecodeAcceptsTag = decode_emit.writeDecodeAcceptsTag;
pub const writeDecodeAcceptedWireType = decode_emit.writeDecodeAcceptedWireType;
pub const messageCanFastRawTagDecode = decode_emit.messageCanFastRawTagDecode;
pub const writeDecodeFastRawTag = decode_emit.writeDecodeFastRawTag;
pub const writeRawTagDecodeLoop = decode_emit.writeRawTagDecodeLoop;
pub const writeRawTagDecodeFieldCases = decode_emit.writeRawTagDecodeFieldCases;
pub const writeRawTagDecodeSingularScalarCase = decode_emit.writeRawTagDecodeSingularScalarCase;
pub const writeRawTagDecodeUnpackedScalarCase = decode_emit.writeRawTagDecodeUnpackedScalarCase;
pub const writeRawTagDecodePackedScalarCase = decode_emit.writeRawTagDecodePackedScalarCase;
pub const writeRawTagDecodeSingularEnumCase = decode_emit.writeRawTagDecodeSingularEnumCase;
pub const writeRawTagDecodeUnpackedEnumCase = decode_emit.writeRawTagDecodeUnpackedEnumCase;
pub const writeRawTagDecodePackedEnumCase = decode_emit.writeRawTagDecodePackedEnumCase;
pub const rawFieldTag = decode_emit.rawFieldTag;
pub const rawTagValue = decode_emit.rawTagValue;
pub const messageCanDecodeKnownReuse = decode_emit.messageCanDecodeKnownReuse;
pub const knownReuseRepeatedScalarSupported = decode_emit.knownReuseRepeatedScalarSupported;
pub const writeDecodeReuse = decode_emit.writeDecodeReuse;
pub const writeDecodeOwnedReuse = decode_emit.writeDecodeOwnedReuse;
pub const writeDecodeKnownReuse = decode_emit.writeDecodeKnownReuse;
pub const writeKnownReuseRepeatedScalarCases = decode_emit.writeKnownReuseRepeatedScalarCases;
pub const writeKnownReuseRepeatedEnumCases = decode_emit.writeKnownReuseRepeatedEnumCases;
pub const writeKnownReuseSingularScalarCase = decode_emit.writeKnownReuseSingularScalarCase;
pub const writeKnownReuseSingularEnumCase = decode_emit.writeKnownReuseSingularEnumCase;
pub const writeKnownReuseRepeatedScalarPayload = decode_emit.writeKnownReuseRepeatedScalarPayload;
pub const writeKnownReuseSingularScalarDecodeExpr = decode_emit.writeKnownReuseSingularScalarDecodeExpr;
pub const writeKnownReuseRepeatedScalarDecodeExpr = decode_emit.writeKnownReuseRepeatedScalarDecodeExpr;
pub const fixedWidthPackedScalarSizeForCodegen = decode_emit.fixedWidthPackedScalarSizeForCodegen;
pub const writeKnownReuseFixedWidthScalarDecodeExpr = decode_emit.writeKnownReuseFixedWidthScalarDecodeExpr;
pub const writeRepeatedReuseListDecl = decode_emit.writeRepeatedReuseListDecl;
pub const writeDecodeReuseResetField = decode_emit.writeDecodeReuseResetField;
pub const writeDecodeReuseClearMap = decode_emit.writeDecodeReuseClearMap;
pub const writeDecodeReuseClearOneof = decode_emit.writeDecodeReuseClearOneof;
pub const writeDecodeInitialized = decode_emit.writeDecodeInitialized;
pub const writeRepeatedListDecl = decode_emit.writeRepeatedListDecl;
pub const writeRepeatedListDeclForDecode = decode_emit.writeRepeatedListDeclForDecode;
pub const writeRepeatedAssign = decode_emit.writeRepeatedAssign;
pub const writeRepeatedAssignForDecode = decode_emit.writeRepeatedAssignForDecode;
pub const writeMapAssign = decode_emit.writeMapAssign;
pub const writeRepeatedElementType = decode_emit.writeRepeatedElementType;
pub const writeDecodeField = decode_emit.writeDecodeField;
pub const writeDecodeScalarField = decode_emit.writeDecodeScalarField;
pub const writeDecodeEnumField = decode_emit.writeDecodeEnumField;
pub const writeDecodeMessageField = decode_emit.writeDecodeMessageField;
pub const writeDecodePackedScalarField = decode_emit.writeDecodePackedScalarField;
pub const writeDecodePackedScalarPayload = decode_emit.writeDecodePackedScalarPayload;
pub const packedScalarAppendHelperName = decode_emit.packedScalarAppendHelperName;
pub const writePackedScalarDecodeCapacityExpr = decode_emit.writePackedScalarDecodeCapacityExpr;
pub const writeDecodePackedEnumField = decode_emit.writeDecodePackedEnumField;
pub const writeDecodeMapField = decode_emit.writeDecodeMapField;
pub const wireMapEntryCanSkip = decode_emit.wireMapEntryCanSkip;
pub const writeMapEntryDecodeAssign = decode_emit.writeMapEntryDecodeAssign;
pub const writeOneofDecodeAssign = decode_emit.writeOneofDecodeAssign;
pub const writeOneofMessageDecodeAssign = decode_emit.writeOneofMessageDecodeAssign;
pub const writeOneofEnumDecodeAssign = decode_emit.writeOneofEnumDecodeAssign;
pub const writeEnumClosedCheck = decode_emit.writeEnumClosedCheck;
pub const writeEnumClosedCheckByName = decode_emit.writeEnumClosedCheckByName;
pub const writeEntryReadExpr = decode_emit.writeEntryReadExpr;
pub const writeRepeatedAppendPrefix = decode_emit.writeRepeatedAppendPrefix;
pub const scalarReaderName = decode_emit.scalarReaderName;
pub const writeMessagePayloadRead = decode_emit.writeMessagePayloadRead;
pub const writePackagedFileDecls = decl_emit.writePackagedFileDecls;
pub const writePackageNamespace = decl_emit.writePackageNamespace;
pub const writeFileDecls = decl_emit.writeFileDecls;
pub const writeFileMetadata = decl_emit.writeFileMetadata;
pub const writeGeneratedFileDescriptor = decl_emit.writeGeneratedFileDescriptor;
pub const writeImportDecl = decl_emit.writeImportDecl;
pub const relativeModulePath = decl_emit.relativeModulePath;
pub const makeImportAlias = decl_emit.makeImportAlias;
pub const writeMessage = decl_emit.writeMessage;
pub const writeOneofUnion = decl_emit.writeOneofUnion;
pub const writeOneofField = decl_emit.writeOneofField;
pub const writeOneofTypeName = decl_emit.writeOneofTypeName;
pub const writeOneofDeinitHelpers = decl_emit.writeOneofDeinitHelpers;
pub const oneofHasTypedMessageWithContext = decl_emit.oneofHasTypedMessageWithContext;
pub const writeOneofDeinitCall = decl_emit.writeOneofDeinitCall;
pub const writeFieldMetadataDecl = decl_emit.writeFieldMetadataDecl;
pub const writeFieldDecl = decl_emit.writeFieldDecl;
pub const writeMapEntryType = decl_emit.writeMapEntryType;
pub const writeMapEntryHelpers = decl_emit.writeMapEntryHelpers;
pub const writeMapKeyEqualExpr = decl_emit.writeMapKeyEqualExpr;
pub const writeInit = decl_emit.writeInit;
pub const writeOwnedAllocator = decl_emit.writeOwnedAllocator;
pub const writeUnknownFieldMethods = view_emit.writeUnknownFieldMethods;
pub const writeBorrowedViewMethods = view_emit.writeBorrowedViewMethods;
pub const writePackedBoolSlicesMethod = view_emit.writePackedBoolSlicesMethod;
pub const writePackedVarintIteratorMethod = view_emit.writePackedVarintIteratorMethod;
pub const packedVarintIteratorType = view_emit.packedVarintIteratorType;
pub const packedVarintIteratorFunction = view_emit.packedVarintIteratorFunction;
pub const writeLengthDelimitedBorrowedSlicesMethod = view_emit.writeLengthDelimitedBorrowedSlicesMethod;
pub const fixedWidthViewScalarType = view_emit.fixedWidthViewScalarType;
pub const writeMessageDescriptorLookup = view_emit.writeMessageDescriptorLookup;
pub const writeMessageDynamicBridge = view_emit.writeMessageDynamicBridge;
pub const writeMessageConformantParsers = view_emit.writeMessageConformantParsers;
