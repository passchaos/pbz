const std = @import("std");
const schema = @import("schema.zig");
const plugin = @import("plugin.zig");
const registry_mod = @import("registry.zig");
const wire = @import("wire.zig");

pub const Error = std.mem.Allocator.Error || std.Io.Writer.Error || plugin.Error || registry_mod.Error;

const CodegenContext = struct {
    allocator: std.mem.Allocator,
    file: *const schema.FileDescriptor,
    registry: ?*const registry_mod.Registry = null,
    pbz_import: []const u8 = "pbz",
    emit_json: bool = true,
    emit_text: bool = true,
    output_suffix: []const u8 = ".pb.zig",
    strip_proto_ext: bool = true,
};

pub fn generateZigFile(allocator: std.mem.Allocator, file: *const schema.FileDescriptor) Error![]u8 {
    return try generateZigFileWithContext(.{ .allocator = allocator, .file = file });
}

pub fn generateZigFileWithRegistry(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, registry: *const registry_mod.Registry) Error![]u8 {
    return try generateZigFileWithContext(.{ .allocator = allocator, .file = file, .registry = registry });
}

fn generateZigFileWithContext(ctx: CodegenContext) Error![]u8 {
    var arena = std.heap.ArenaAllocator.init(ctx.allocator);
    defer arena.deinit();
    var active_ctx = ctx;
    var resolved_file: schema.FileDescriptor = undefined;
    if (ctx.registry) |registry| {
        resolved_file = try cloneFileForCodegen(arena.allocator(), ctx.file);
        try resolveImportedEnumsForCodegen(arena.allocator(), &resolved_file, registry);
        active_ctx.file = &resolved_file;
    }

    var out: std.Io.Writer.Allocating = .init(ctx.allocator);
    errdefer out.deinit();
    try out.writer.writeAll("const std = @import(\"std\");\nconst pbz = @import(");
    try writeZigStringLiteral(active_ctx.pbz_import, &out.writer);
    try out.writer.writeAll(");\n\n");
    try writeFileMetadata(&active_ctx, &out.writer, 0);
    try writePackagedFileDecls(&active_ctx, &out.writer, 0);
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

fn writePackagedFileDecls(ctx: *const CodegenContext, writer: *std.Io.Writer, depth: usize) Error!void {
    if (ctx.file.package.len == 0) return try writeFileDecls(ctx, writer, depth);
    try writePackageNamespace(ctx, ctx.file.package, writer, depth);
}

fn writePackageNamespace(ctx: *const CodegenContext, package: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    const dot = std.mem.indexOfScalar(u8, package, '.');
    const segment = if (dot) |idx| package[0..idx] else package;
    if (segment.len == 0) {
        if (dot) |idx| return try writePackageNamespace(ctx, package[idx + 1 ..], writer, depth);
        return try writeFileDecls(ctx, writer, depth);
    }

    try indent(writer, depth);
    try writer.writeAll("pub const ");
    try writeQuotedIdent(segment, writer);
    try writer.writeAll(" = struct {\n");
    if (dot) |idx| {
        try writePackageNamespace(ctx, package[idx + 1 ..], writer, depth + 1);
    } else {
        try writeFileDecls(ctx, writer, depth + 1);
    }
    try indent(writer, depth);
    try writer.writeAll("};\n\n");
}

fn writeFileDecls(ctx: *const CodegenContext, writer: *std.Io.Writer, depth: usize) Error!void {
    for (ctx.file.enums.items) |*enumeration| try writeEnum(enumeration, writer, depth);
    for (ctx.file.messages.items) |*message| try writeMessage(ctx, message, writer, depth);
    try writeExtensionMetadata(ctx, writer, depth);
    try writeServiceMetadata(ctx, writer, depth);
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
    out.messages = .empty;
    out.extensions = .empty;
    for (message.fields.items) |*field| try out.fields.append(allocator, try cloneFieldForCodegen(allocator, field));
    for (message.messages.items) |*nested| try out.messages.append(allocator, try cloneMessageForCodegen(allocator, nested));
    for (message.extensions.items) |*field| try out.extensions.append(allocator, try cloneFieldForCodegen(allocator, field));
    return out;
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

fn extensionScopeForCodegen(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor) ?[]const u8 {
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

const PluginParameterOptions = struct {
    include_imports: bool = false,
    generated_info: bool = true,
    pbz_import: []const u8 = "pbz",
    emit_json: bool = true,
    emit_text: bool = true,
    output_suffix: []const u8 = ".pb.zig",
    strip_proto_ext: bool = true,
};

pub fn generatePluginResponseFromRequestBytes(allocator: std.mem.Allocator, bytes: []const u8) Error![]u8 {
    var request = try plugin.CodeGeneratorRequest.decode(allocator, bytes);
    defer request.deinit();
    return try generatePluginResponseFromRequest(allocator, &request);
}

pub fn runPluginRequestBytes(allocator: std.mem.Allocator, bytes: []const u8, writer: *std.Io.Writer) Error!void {
    const response = try generatePluginResponseFromRequestBytes(allocator, bytes);
    defer allocator.free(response);
    try writer.writeAll(response);
}

pub fn runPluginRequest(allocator: std.mem.Allocator, request: *const plugin.CodeGeneratorRequest, writer: *std.Io.Writer) Error!void {
    const response = try generatePluginResponseFromRequest(allocator, request);
    defer allocator.free(response);
    try writer.writeAll(response);
}

pub fn generatePluginResponseFromRequest(allocator: std.mem.Allocator, request: *const plugin.CodeGeneratorRequest) Error![]u8 {
    const options = parsePluginParameters(request.parameter) catch {
        return try encodePluginErrorResponse(allocator, "invalid generator parameter");
    };

    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    for (request.proto_files.items) |*file| try registry.addFile(file);
    registry.validateAllFileReferences() catch {
        return try encodePluginErrorResponse(allocator, "invalid or unresolved type reference");
    };

    var selected: std.ArrayList(*const schema.FileDescriptor) = .empty;
    defer selected.deinit(allocator);
    if (options.include_imports or request.files_to_generate.items.len == 0) {
        for (request.proto_files.items) |*file| try selected.append(allocator, file);
    } else {
        for (request.files_to_generate.items) |name| {
            const file = findRequestFile(request, name) orelse {
                const message = try std.fmt.allocPrint(allocator, "file_to_generate not found: {s}", .{name});
                defer allocator.free(message);
                return try encodePluginErrorResponse(allocator, message);
            };
            try selected.append(allocator, file);
        }
    }

    return try generatePluginResponseForSelected(allocator, selected.items, &registry, options);
}

fn parsePluginParameters(parameter: []const u8) error{InvalidPluginParameter}!PluginParameterOptions {
    var options = PluginParameterOptions{};
    var parts = std.mem.splitScalar(u8, parameter, ',');
    while (parts.next()) |raw_part| {
        const part = std.mem.trim(u8, raw_part, " \t\r\n");
        if (part.len == 0) continue;
        const key, const maybe_value = splitParameter(part);
        if (std.mem.eql(u8, key, "include_imports") or std.mem.eql(u8, key, "emit_imports")) {
            options.include_imports = try parseParameterBool(maybe_value orelse "true");
        } else if (std.mem.eql(u8, key, "generated_info") or std.mem.eql(u8, key, "annotate_code")) {
            options.generated_info = try parseParameterBool(maybe_value orelse "true");
        } else if (std.mem.eql(u8, key, "pbz_import") or std.mem.eql(u8, key, "runtime_import")) {
            options.pbz_import = maybe_value orelse return error.InvalidPluginParameter;
            if (options.pbz_import.len == 0) return error.InvalidPluginParameter;
        } else if (std.mem.eql(u8, key, "json") or std.mem.eql(u8, key, "emit_json")) {
            options.emit_json = try parseParameterBool(maybe_value orelse "true");
        } else if (std.mem.eql(u8, key, "text") or std.mem.eql(u8, key, "text_format") or std.mem.eql(u8, key, "emit_text")) {
            options.emit_text = try parseParameterBool(maybe_value orelse "true");
        } else if (std.mem.eql(u8, key, "output_suffix")) {
            options.output_suffix = maybe_value orelse return error.InvalidPluginParameter;
            if (options.output_suffix.len == 0) return error.InvalidPluginParameter;
        } else if (std.mem.eql(u8, key, "strip_proto_ext")) {
            options.strip_proto_ext = try parseParameterBool(maybe_value orelse "true");
        } else if (std.mem.eql(u8, key, "paths")) {
            const value = maybe_value orelse return error.InvalidPluginParameter;
            if (!std.mem.eql(u8, value, "source_relative")) return error.InvalidPluginParameter;
        } else {
            return error.InvalidPluginParameter;
        }
    }
    return options;
}

fn splitParameter(part: []const u8) struct { []const u8, ?[]const u8 } {
    if (std.mem.indexOfScalar(u8, part, '=')) |idx| {
        return .{ std.mem.trim(u8, part[0..idx], " \t\r\n"), std.mem.trim(u8, part[idx + 1 ..], " \t\r\n") };
    }
    return .{ part, null };
}

fn parseParameterBool(value: []const u8) error{InvalidPluginParameter}!bool {
    if (std.ascii.eqlIgnoreCase(value, "true") or std.mem.eql(u8, value, "1")) return true;
    if (std.ascii.eqlIgnoreCase(value, "false") or std.mem.eql(u8, value, "0")) return false;
    return error.InvalidPluginParameter;
}

pub fn generatePluginResponse(allocator: std.mem.Allocator, files: []const *const schema.FileDescriptor) Error![]u8 {
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    for (files) |file| try registry.addFile(file);
    try registry.validateAllFileReferences();

    return try generatePluginResponseForSelected(allocator, files, &registry, .{});
}

fn generatePluginResponseForSelected(allocator: std.mem.Allocator, files: []const *const schema.FileDescriptor, registry: *const registry_mod.Registry, options: PluginParameterOptions) Error![]u8 {
    var response_files = try allocator.alloc(plugin.CodeGeneratorResponse.File, files.len);
    @memset(response_files, .{});
    var generated_infos = try allocator.alloc(schema.GeneratedCodeInfo, files.len);
    @memset(generated_infos, .{});
    defer {
        for (response_files) |file| {
            if (file.name) |name| allocator.free(name);
            if (file.content.len != 0) allocator.free(file.content);
        }
        for (generated_infos) |*info| info.deinit(allocator);
        allocator.free(generated_infos);
        allocator.free(response_files);
    }
    for (files, 0..) |file, i| {
        const content = try generateZigFileWithContext(.{ .allocator = allocator, .file = file, .registry = registry, .pbz_import = options.pbz_import, .emit_json = options.emit_json, .emit_text = options.emit_text, .output_suffix = options.output_suffix, .strip_proto_ext = options.strip_proto_ext });
        errdefer allocator.free(content);
        const name = try outputNameWithOptions(allocator, file.name, options.output_suffix, options.strip_proto_ext);
        if (options.generated_info) {
            try populateGeneratedCodeInfo(allocator, file, content, &generated_infos[i]);
            response_files[i] = .{ .name = name, .content = content, .generated_code_info_value = &generated_infos[i] };
        } else {
            response_files[i] = .{ .name = name, .content = content };
        }
    }
    return try (plugin.CodeGeneratorResponse{
        .supported_features = generatedResponseFeatureMask(),
        .minimum_edition = .proto2,
        .maximum_edition = .edition_2026,
        .files = response_files,
    }).encode(allocator);
}

fn findRequestFile(request: *const plugin.CodeGeneratorRequest, name: []const u8) ?*const schema.FileDescriptor {
    for (request.proto_files.items) |*file| {
        if (std.mem.eql(u8, file.name, name)) return file;
    }
    return null;
}

fn encodePluginErrorResponse(allocator: std.mem.Allocator, message: []const u8) Error![]u8 {
    return try (plugin.CodeGeneratorResponse{
        .error_message = message,
        .supported_features = generatedResponseFeatureMask(),
        .minimum_edition = .proto2,
        .maximum_edition = .edition_2026,
    }).encode(allocator);
}

fn generatedResponseFeatureMask() u64 {
    return plugin.CodeGeneratorResponse.featureMask(&[_]plugin.CodeGeneratorResponse.Feature{ .proto3_optional, .supports_editions });
}

fn populateGeneratedCodeInfo(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, content: []const u8, info: *schema.GeneratedCodeInfo) Error!void {
    try appendGeneratedAnnotation(allocator, info, file.name, &.{}, 0, content.len, .set);
    for (file.messages.items, 0..) |message, i| {
        try appendGeneratedMessageAnnotations(allocator, info, file.name, content, &.{ 4, @intCast(i) }, &message);
    }
    for (file.enums.items, 0..) |enumeration, i| {
        try appendGeneratedEnumAnnotations(allocator, info, file.name, content, &.{ 5, @intCast(i) }, &enumeration);
    }
    for (file.services.items, 0..) |service, i| {
        try appendGeneratedServiceAnnotations(allocator, info, file.name, content, &.{ 6, @intCast(i) }, &service);
    }
    for (file.extensions.items, 0..) |field, i| {
        try appendGeneratedExtensionAnnotation(allocator, info, file.name, content, &.{ 7, @intCast(i) }, field.name);
    }
}

fn appendGeneratedMessageAnnotations(allocator: std.mem.Allocator, info: *schema.GeneratedCodeInfo, source_file: []const u8, content: []const u8, path: []const i32, message: *const schema.MessageDescriptor) Error!void {
    try appendGeneratedSymbolAnnotation(allocator, info, source_file, content, path, message.name, .set);
    for (message.fields.items, 0..) |field, i| {
        const field_path = try appendPathPair(allocator, path, 2, @intCast(i));
        defer allocator.free(field_path);
        try appendGeneratedSymbolAnnotation(allocator, info, source_file, content, field_path, field.name, .set);
    }
    for (message.extensions.items, 0..) |field, i| {
        const extension_path = try appendPathPair(allocator, path, 6, @intCast(i));
        defer allocator.free(extension_path);
        try appendGeneratedExtensionAnnotation(allocator, info, source_file, content, extension_path, field.name);
    }
    for (message.oneofs.items, 0..) |oneof, i| {
        const oneof_path = try appendPathPair(allocator, path, 8, @intCast(i));
        defer allocator.free(oneof_path);
        try appendGeneratedOneofAnnotation(allocator, info, source_file, content, oneof_path, oneof.name);
    }
    for (message.messages.items, 0..) |nested, i| {
        const nested_path = try appendPathPair(allocator, path, 3, @intCast(i));
        defer allocator.free(nested_path);
        try appendGeneratedMessageAnnotations(allocator, info, source_file, content, nested_path, &nested);
    }
    for (message.enums.items, 0..) |enumeration, i| {
        const enum_path = try appendPathPair(allocator, path, 4, @intCast(i));
        defer allocator.free(enum_path);
        try appendGeneratedEnumAnnotations(allocator, info, source_file, content, enum_path, &enumeration);
    }
}

fn appendGeneratedOneofAnnotation(allocator: std.mem.Allocator, info: *schema.GeneratedCodeInfo, source_file: []const u8, content: []const u8, path: []const i32, oneof_name: []const u8) Error!void {
    const symbol = try std.fmt.allocPrint(allocator, "{s}Oneof", .{oneof_name});
    defer allocator.free(symbol);
    try appendGeneratedSymbolAnnotation(allocator, info, source_file, content, path, symbol, .set);
}

fn appendGeneratedEnumAnnotations(allocator: std.mem.Allocator, info: *schema.GeneratedCodeInfo, source_file: []const u8, content: []const u8, path: []const i32, enumeration: *const schema.EnumDescriptor) Error!void {
    try appendGeneratedSymbolAnnotation(allocator, info, source_file, content, path, enumeration.name, .set);
    for (enumeration.values.items, 0..) |value, i| {
        const value_path = try appendPathPair(allocator, path, 2, @intCast(i));
        defer allocator.free(value_path);
        try appendGeneratedSymbolAnnotation(allocator, info, source_file, content, value_path, value.name, .set);
    }
}

fn appendGeneratedServiceAnnotations(allocator: std.mem.Allocator, info: *schema.GeneratedCodeInfo, source_file: []const u8, content: []const u8, path: []const i32, service: *const schema.ServiceDescriptor) Error!void {
    try appendGeneratedSymbolAnnotation(allocator, info, source_file, content, path, service.name, .set);
    for (service.methods.items, 0..) |method, i| {
        const method_path = try appendPathPair(allocator, path, 2, @intCast(i));
        defer allocator.free(method_path);
        try appendGeneratedSymbolAnnotation(allocator, info, source_file, content, method_path, method.name, .set);
    }
}

fn appendPathPair(allocator: std.mem.Allocator, base: []const i32, field_number: i32, index: i32) std.mem.Allocator.Error![]i32 {
    const out = try allocator.alloc(i32, base.len + 2);
    @memcpy(out[0..base.len], base);
    out[base.len] = field_number;
    out[base.len + 1] = index;
    return out;
}

fn appendGeneratedSymbolAnnotation(allocator: std.mem.Allocator, info: *schema.GeneratedCodeInfo, source_file: []const u8, content: []const u8, path: []const i32, symbol: []const u8, semantic: schema.GeneratedCodeInfo.Semantic) Error!void {
    const range = findGeneratedSymbolRange(allocator, content, symbol) catch return;
    defer allocator.free(range.needle);
    try appendGeneratedAnnotation(allocator, info, source_file, path, range.begin, range.end, semantic);
}

fn appendGeneratedExtensionAnnotation(allocator: std.mem.Allocator, info: *schema.GeneratedCodeInfo, source_file: []const u8, content: []const u8, path: []const i32, extension_name: []const u8) Error!void {
    const extensions_idx = std.mem.indexOf(u8, content, "pub const extensions = struct") orelse return;
    const range = findGeneratedSymbolRangeFrom(allocator, content, extension_name, extensions_idx) catch return;
    defer allocator.free(range.needle);
    try appendGeneratedAnnotation(allocator, info, source_file, path, range.begin, range.end, .set);
}

const GeneratedSymbolRange = struct { begin: usize, end: usize, needle: []u8 };

fn findGeneratedSymbolRange(allocator: std.mem.Allocator, content: []const u8, symbol: []const u8) Error!GeneratedSymbolRange {
    return try findGeneratedSymbolRangeFrom(allocator, content, symbol, 0);
}

fn findGeneratedSymbolRangeFrom(allocator: std.mem.Allocator, content: []const u8, symbol: []const u8, start_index: usize) Error!GeneratedSymbolRange {
    const pub_const = try makeGeneratedNeedle(allocator, "pub const ", symbol);
    if (findGeneratedNeedleRange(content, pub_const, start_index)) |range| return .{ .begin = range.begin, .end = range.end, .needle = pub_const };
    allocator.free(pub_const);

    const quoted = try makeGeneratedNeedle(allocator, "", symbol);
    if (findGeneratedNeedleRange(content, quoted, start_index)) |range| return .{ .begin = range.begin, .end = range.end, .needle = quoted };
    allocator.free(quoted);
    return error.OutOfMemory;
}

fn makeGeneratedNeedle(allocator: std.mem.Allocator, prefix: []const u8, symbol: []const u8) Error![]u8 {
    var needle_writer: std.Io.Writer.Allocating = .init(allocator);
    errdefer needle_writer.deinit();
    try needle_writer.writer.writeAll(prefix);
    try writeQuotedIdent(symbol, &needle_writer.writer);
    return try needle_writer.toOwnedSlice();
}

fn findGeneratedNeedleRange(content: []const u8, needle: []const u8, start_index: usize) ?struct { begin: usize, end: usize } {
    const begin = std.mem.indexOfPos(u8, content, start_index, needle) orelse return null;
    const next = std.mem.indexOfPos(u8, content, begin + needle.len, "\npub const ") orelse content.len;
    return .{ .begin = begin, .end = next };
}

fn appendGeneratedAnnotation(allocator: std.mem.Allocator, info: *schema.GeneratedCodeInfo, source_file: []const u8, path: []const i32, begin: usize, end: usize, semantic: schema.GeneratedCodeInfo.Semantic) std.mem.Allocator.Error!void {
    var annotation = schema.GeneratedCodeInfo.Annotation{};
    errdefer annotation.deinit(allocator);
    try annotation.path.appendSlice(allocator, path);
    annotation.source_file = source_file;
    annotation.begin = @intCast(begin);
    annotation.end = @intCast(end);
    annotation.semantic = semantic;
    try info.annotations.append(allocator, annotation);
}

fn writeFileMetadata(ctx: *const CodegenContext, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    try indent(writer, depth);
    try writer.writeAll("pub const proto_package = ");
    try writeZigStringLiteral(file.package, writer);
    try writer.writeAll(";\n");
    try indent(writer, depth);
    try writer.writeAll("pub const proto_syntax = ");
    try writeZigStringLiteral(switch (file.syntax) {
        .proto2 => "proto2",
        .proto3 => "proto3",
        .editions => "editions",
    }, writer);
    try writer.writeAll(";\n");
    if (file.imports.items.len != 0) {
        try indent(writer, depth);
        try writer.writeAll("pub const imports = struct {\n");
        for (file.imports.items) |import| try writeImportDecl(ctx, import, writer, depth + 1);
        try indent(writer, depth);
        try writer.writeAll("};\n");
        try indent(writer, depth);
        try writer.writeAll("const pbz_generated_file = @This();\n");
    }
    try writer.writeAll("\n");
}

fn writeImportDecl(ctx: *const CodegenContext, import: schema.Import, writer: *std.Io.Writer, depth: usize) Error!void {
    const allocator = ctx.allocator;
    const module_path = try outputNameWithOptions(allocator, import.path, ctx.output_suffix, ctx.strip_proto_ext);
    defer allocator.free(module_path);
    const import_alias = try makeImportAlias(allocator, import.path);
    defer allocator.free(import_alias);
    try indent(writer, depth);
    try writer.writeAll("pub const ");
    try writer.writeAll(import_alias);
    try writer.writeAll(" = @import(");
    try writeZigStringLiteral(module_path, writer);
    try writer.writeAll(");\n");
    try indent(writer, depth);
    try writer.writeAll("pub const ");
    try writer.writeAll(import_alias);
    try writer.writeAll("_path");
    try writer.writeAll(" = ");
    try writeZigStringLiteral(import.path, writer);
    try writer.writeAll(";\n");
    try indent(writer, depth);
    try writer.writeAll("pub const ");
    try writer.writeAll(import_alias);
    try writer.writeAll("_kind");
    try writer.writeAll(" = ");
    try writeZigStringLiteral(@tagName(import.kind), writer);
    try writer.writeAll(";\n");
}

fn makeImportAlias(allocator: std.mem.Allocator, path: []const u8) Error![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();

    const source = if (path.len == 0) "import" else path;
    for (source) |c| {
        if (isBareIdentChar(c, out.written().len == 0)) {
            try out.writer.writeByte(c);
        } else if (out.written().len == 0 or out.written()[out.written().len - 1] != '_') {
            try out.writer.writeByte('_');
        }
    }

    if (out.written().len == 0 or std.mem.eql(u8, out.written(), "_") or !canWriteBareIdent(out.written())) {
        try out.writer.writeAll("_pb");
    }
    return try out.toOwnedSlice();
}

fn writeMessage(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
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
    for (message.fields.items) |*field| try writeFieldMetadataDecl(ctx, field, writer, depth + 1);
    if (message.fields.items.len != 0) try writer.writeAll("\n");
    for (message.fields.items) |*field| {
        if (field.kind == .map) {
            try writeMapEntryType(ctx, field, writer, depth + 1);
            try writeMapEntryHelpers(ctx, field, writer, depth + 1);
        }
    }
    for (message.oneofs.items) |oneof| try writeOneofUnion(ctx, message, oneof, writer, depth + 1);
    for (message.fields.items) |*field| {
        if (field.oneof_name == null) try writeFieldDecl(ctx, field, writer, depth + 1);
    }
    for (message.oneofs.items) |oneof| try writeOneofField(oneof, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("_json_arena: ?*std.heap.ArenaAllocator = null,\n");
    try indent(writer, depth + 1);
    try writer.writeAll("_unknown_fields: []const []const u8 = &.{},\n");
    if (message.fields.items.len != 0) try writer.writeAll("\n");
    try writeInit(writer, depth + 1);
    try writer.writeAll("\n");
    try writeDeinit(ctx, message, writer, depth + 1);
    try writer.writeAll("\n");
    try writeCloneOwned(ctx, message, writer, depth + 1);
    try writer.writeAll("\n");
    try writeOwnedAllocator(writer, depth + 1);
    try writer.writeAll("\n");
    try writeUnknownFieldMethods(writer, depth + 1);
    try writer.writeAll("\n");
    try writeBorrowedViewMethods(file, message, writer, depth + 1);
    try writer.writeAll("\n");
    try writeMessageExtensionAccessors(ctx, message, writer, depth + 1);
    try writer.writeAll("\n");
    try writeMergeFrom(ctx, message, writer, depth + 1);
    try writer.writeAll("\n");
    try writeEncode(ctx, message, writer, depth + 1);
    try writer.writeAll("\n");
    try writeEncodeDeterministic(ctx, message, writer, depth + 1);
    try writer.writeAll("\n");
    try writeEncodeInitialized(writer, depth + 1);
    try writer.writeAll("\n");
    try writeDecode(ctx, message, writer, depth + 1);
    try writer.writeAll("\n");
    if (messageCanDecodeReuseFast(ctx, message)) {
        try writeDecodeReuse(ctx, message, writer, depth + 1);
        try writer.writeAll("\n");
        if (messageCanDecodeKnownReuse(ctx.file, message)) {
            try writeDecodeKnownReuse(ctx, message, writer, depth + 1);
            try writer.writeAll("\n");
        }
    }
    try writeDecodeInitialized(writer, depth + 1);
    try writer.writeAll("\n");
    try writeMissingRequiredFieldName(message, writer, depth + 1);
    try writer.writeAll("\n");
    try writeMissingRequiredFieldPath(ctx, message, writer, depth + 1);
    try writer.writeAll("\n");
    try writeValidateRequired(ctx, message, writer, depth + 1);
    try writer.writeAll("\n");
    if (ctx.emit_json) {
        try writeJsonMethods(ctx, message, writer, depth + 1);
        try writer.writeAll("\n");
    }
    if (ctx.emit_text) {
        try writeTextMethods(ctx, message, writer, depth + 1);
        try writer.writeAll("\n");
    }
    for (message.enums.items) |*enumeration| try writeEnum(enumeration, writer, depth + 1);
    for (message.messages.items) |*nested| try writeMessage(ctx, nested, writer, depth + 1);
    try indent(writer, depth);
    try writer.writeAll("};\n\n");
}

fn writeOneofUnion(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, oneof: schema.OneofDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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
                if (typedOneofMessageFieldWithContext(ctx, field)) |type_name| {
                    try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
                } else {
                    try writeFieldType(field.*, writer);
                }
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

fn writeFieldMetadataDecl(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    try indent(writer, depth);
    try writer.writeAll("pub const ");
    try writeQuotedIdentWithSuffix(field.name, "_field", writer);
    try writer.writeAll(" = struct {\n");
    try indent(writer, depth + 1);
    try writer.print("pub const number = {d};\n", .{field.number});
    try indent(writer, depth + 1);
    try writer.writeAll("pub const name = ");
    try writeZigStringLiteral(field.name, writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const json_name = ");
    if (field.json_name) |json_name| {
        try writeZigStringLiteral(json_name, writer);
    } else {
        try writeZigLowerCamelStringLiteral(field.name, writer);
    }
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const cardinality = ");
    try writeZigStringLiteral(@tagName(field.cardinality), writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const kind = ");
    try writeZigStringLiteral(fieldKindName(field.kind), writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const type_name = ");
    try writeZigStringLiteral(fieldTypeName(field.kind), writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const zig_type = ");
    if (typedSingularMessageFieldWithContext(ctx, field)) |type_name| {
        var type_buf: std.Io.Writer.Allocating = .init(ctx.allocator);
        defer type_buf.deinit();
        try type_buf.writer.writeByte('?');
        try writeMessageTypeReferenceWithContext(ctx, type_name, &type_buf.writer);
        try writeZigStringLiteral(type_buf.written(), writer);
    } else if (typedRepeatedMessageFieldWithContext(ctx, field)) |type_name| {
        var type_buf: std.Io.Writer.Allocating = .init(ctx.allocator);
        defer type_buf.deinit();
        try type_buf.writer.writeAll("[]const ");
        try writeMessageTypeReferenceWithContext(ctx, type_name, &type_buf.writer);
        try writeZigStringLiteral(type_buf.written(), writer);
    } else if (typedOneofMessageFieldWithContext(ctx, field)) |type_name| {
        var type_buf: std.Io.Writer.Allocating = .init(ctx.allocator);
        defer type_buf.deinit();
        try writeMessageTypeReferenceWithContext(ctx, type_name, &type_buf.writer);
        try writeZigStringLiteral(type_buf.written(), writer);
    } else {
        var type_buf: std.Io.Writer.Allocating = .init(ctx.allocator);
        defer type_buf.deinit();
        try writeFieldType(field.*, &type_buf.writer);
        try writeZigStringLiteral(type_buf.written(), writer);
    }
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const has_type_ref = ");
    try writer.writeAll(if (canReferenceMessageWithContext(ctx, field.kind)) "true" else "false");
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const type_ref = ");
    try writeMessageTypeReferenceOrVoid(ctx, field.kind, writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const has_enum_ref = ");
    try writer.writeAll(if (canReferenceEnumWithContext(ctx, field.kind)) "true" else "false");
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const enum_ref = ");
    try writeEnumTypeReferenceOrVoid(ctx, field.kind, writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const has_presence = ");
    try writer.writeAll(if (hasPresence(file, field.*)) "true" else "false");
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const default_value = ");
    try writeOptionValueTextLiteral(field.default_value, writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const is_packed = ");
    try writer.writeAll(if (field.resolvedPacked(file)) "true" else "false");
    try writer.writeAll(";\n");
    if (field.kind == .map) {
        try indent(writer, depth + 1);
        try writer.writeAll("pub const map_key = ");
        try writeZigStringLiteral(@tagName(field.kind.map.key), writer);
        try writer.writeAll(";\n");
        try indent(writer, depth + 1);
        try writer.writeAll("pub const map_value_kind = ");
        try writeZigStringLiteral(fieldKindName(field.kind.map.value.*), writer);
        try writer.writeAll(";\n");
        try indent(writer, depth + 1);
        try writer.writeAll("pub const map_value_type_name = ");
        try writeZigStringLiteral(fieldTypeName(field.kind.map.value.*), writer);
        try writer.writeAll(";\n");
        try indent(writer, depth + 1);
        try writer.writeAll("pub const map_value_has_type_ref = ");
        try writer.writeAll(if (canReferenceMessageWithContext(ctx, field.kind.map.value.*)) "true" else "false");
        try writer.writeAll(";\n");
        try indent(writer, depth + 1);
        try writer.writeAll("pub const map_value_type_ref = ");
        try writeMessageTypeReferenceOrVoid(ctx, field.kind.map.value.*, writer);
        try writer.writeAll(";\n");
        try indent(writer, depth + 1);
        try writer.writeAll("pub const map_value_has_enum_ref = ");
        try writer.writeAll(if (canReferenceEnumWithContext(ctx, field.kind.map.value.*)) "true" else "false");
        try writer.writeAll(";\n");
        try indent(writer, depth + 1);
        try writer.writeAll("pub const map_value_enum_ref = ");
        try writeEnumTypeReferenceOrVoid(ctx, field.kind.map.value.*, writer);
        try writer.writeAll(";\n");
    }
    try indent(writer, depth);
    try writer.writeAll("};\n");
}

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

fn writeEncodeOneof(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, oneof: schema.OneofDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeEncodeOneofAssumeCapacity(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, oneof: schema.OneofDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeTextParseMethods(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub const TextParseOptions = struct { ignore_unknown_fields: bool = false };\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn parseText(allocator: std.mem.Allocator, text: []const u8) !@This() {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try @This().parseTextWithOptions(allocator, text, .{});\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn parseTextWithOptions(allocator: std.mem.Allocator, text: []const u8, options: @This().TextParseOptions) !@This() {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var self = @This().init();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer self.deinit(allocator);\n");
    for (message.fields.items) |*field| try writeRepeatedListDecl(ctx, field, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("var _unknown_fields_list: std.ArrayList([]const u8) = .empty;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer { for (_unknown_fields_list.items) |raw| allocator.free(raw); _unknown_fields_list.deinit(allocator); }\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const needs_normalized_text = @This().textNeedsSeparatorNormalization(text);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const normalized_text = if (needs_normalized_text) try @This().textNormalizeSeparators(allocator, text) else text;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("defer if (needs_normalized_text) allocator.free(normalized_text);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var lines = std.mem.splitScalar(u8, normalized_text, '\\n');\n");
    try indent(writer, depth + 1);
    try writer.writeAll("while (lines.next()) |raw_line| {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("const line = @This().textCleanLine(raw_line);\n");
    try indent(writer, depth + 2);
    try writer.writeAll("if (line.len == 0) continue;\n");
    for (message.fields.items) |*field| {
        if (field.oneof_name == null) try writeTextParseField(ctx, field, writer, depth + 2);
    }
    for (message.oneofs.items) |oneof| {
        for (message.fields.items) |*field| {
            if (field.oneof_name) |name| {
                if (std.mem.eql(u8, name, oneof.name)) try writeTextParseOneofField(ctx, oneof, field, writer, depth + 2);
            }
        }
    }
    try writeTextParseExtensions(ctx, message, writer, depth + 2);
    try indent(writer, depth + 2);
    try writer.writeAll("if (try @This().textUnknownField(allocator, line)) |raw| { errdefer allocator.free(raw); try _unknown_fields_list.append(allocator, raw); continue; }\n");
    try indent(writer, depth + 2);
    try writer.writeAll("if (try @This().textUnknownGroup(allocator, line, &lines)) |raw| { errdefer allocator.free(raw); try _unknown_fields_list.append(allocator, raw); continue; }\n");
    try indent(writer, depth + 2);
    try writer.writeAll("if (options.ignore_unknown_fields) continue;\n");
    try indent(writer, depth + 2);
    try writer.writeAll("return error.UnknownField;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    for (message.fields.items) |*field| try writeRepeatedAssign(field, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("self._unknown_fields = try _unknown_fields_list.toOwnedSlice(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return self;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn parseTextInitialized(allocator: std.mem.Allocator, text: []const u8) !@This() {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var self = try @This().parseText(allocator, text);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer self.deinit(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.validateRequiredRecursive(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return self;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn parseTextInitializedWithOptions(allocator: std.mem.Allocator, text: []const u8, options: @This().TextParseOptions) !@This() {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var self = try @This().parseTextWithOptions(allocator, text, options);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer self.deinit(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.validateRequiredRecursive(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return self;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn messageTextParseUsesAllocator(message: *const schema.MessageDescriptor) bool {
    for (message.fields.items) |field| {
        if (field.cardinality == .repeated or field.kind == .map) return true;
        if (field.kind == .message or field.kind == .group) return true;
    }
    return false;
}

fn writeTextParseExtensions(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    for (file.extensions.items) |*field| {
        if (extensionAppliesToMessage(file, message, field)) try writeTextParseExtensionField(ctx, field, writer, depth);
    }
    for (file.messages.items) |*scope| try writeTextParseMessageExtensions(ctx, message, scope, writer, depth);
}

fn writeTextParseMessageExtensions(ctx: *const CodegenContext, target: *const schema.MessageDescriptor, scope: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    for (scope.extensions.items) |*field| {
        if (extensionAppliesToMessage(file, target, field)) try writeTextParseExtensionField(ctx, field, writer, depth);
    }
    for (scope.messages.items) |*nested| try writeTextParseMessageExtensions(ctx, target, nested, writer, depth);
}

fn extensionAppliesToMessage(file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) bool {
    const extendee = field.extendee orelse return false;
    if (findExtensionExtendeeInFile(file, field)) |resolved| return resolved == message;
    const trimmed = if (std.mem.startsWith(u8, extendee, ".")) extendee[1..] else extendee;
    const leaf = if (std.mem.lastIndexOfScalar(u8, trimmed, '.')) |idx| trimmed[idx + 1 ..] else trimmed;
    return std.mem.eql(u8, message.name, trimmed) or std.mem.eql(u8, message.name, leaf);
}

fn findExtensionExtendeeInFile(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor) ?*const schema.MessageDescriptor {
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

fn findMessageByQualifiedName(file: *const schema.FileDescriptor, name: []const u8) ?*const schema.MessageDescriptor {
    var normalized = if (std.mem.startsWith(u8, name, ".")) name[1..] else name;
    if (file.package.len != 0 and std.mem.startsWith(u8, normalized, file.package)) {
        if (normalized.len == file.package.len) return null;
        if (normalized.len > file.package.len and normalized[file.package.len] == '.') normalized = normalized[file.package.len + 1 ..];
    }
    return findMessageByPath(file.messages.items, normalized);
}

fn findMessageByPath(messages: []const schema.MessageDescriptor, path: []const u8) ?*const schema.MessageDescriptor {
    if (path.len == 0) return null;
    const head, const tail = splitFirst(path);
    for (messages) |*message| {
        if (!std.mem.eql(u8, message.name, head)) continue;
        if (tail.len == 0) return message;
        return findMessageByPath(message.messages.items, tail);
    }
    return null;
}

fn splitFirst(name: []const u8) struct { []const u8, []const u8 } {
    if (std.mem.indexOfScalar(u8, name, '.')) |idx| return .{ name[0..idx], name[idx + 1 ..] };
    return .{ name, "" };
}

fn writeTextParseExtensionField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    switch (field.kind) {
        .scalar, .enumeration => {},
        .message, .group => |type_name| {
            if (!codegenCanReferenceMessageWithContext(ctx, type_name)) return;
            return try writeTextParseMessageExtensionField(ctx, field, type_name, writer, depth);
        },
        else => return,
    }
    try indent(writer, depth);
    try writer.writeAll("if (");
    try writeExtensionTextValueLookup(file, field, "line", writer);
    try writer.writeAll(") |raw_value| {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const raw = try ");
    try writeExtensionHelperReference(field, writer);
    try writer.writeAll(".encodeRaw(allocator, ");
    if (field.kind == .enumeration) {
        try writeTextParseEnumExpr(file, field.kind.enumeration, "raw_value", writer);
        try writer.writeAll(" catch |err| { if (options.ignore_unknown_fields) { continue; } return err; }");
    } else {
        try writeTextParseValueExpr(file, field, field.kind, "raw_value", writer);
    }
    try writer.writeAll(");\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer allocator.free(raw);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try _unknown_fields_list.append(allocator, raw);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("continue;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeTextParseMessageExtensionField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, type_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    try indent(writer, depth);
    try writer.writeAll("if (");
    try writeExtensionTextBlockCondition(file, field, "line", writer);
    try writer.writeAll(") {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const block = try @This().textBlock(allocator, &lines);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("defer allocator.free(block);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var nested = try ");
    try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    try writer.writeAll(".parseTextWithOptions(allocator, block, .{ .ignore_unknown_fields = options.ignore_unknown_fields });\n");
    try indent(writer, depth + 1);
    try writer.writeAll("defer nested.deinit(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const owned_allocator = try self._pbzOwnedAllocator(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const payload = try nested.encode(owned_allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const raw = try ");
    try writeExtensionHelperReference(field, writer);
    try writer.writeAll(".encodeRaw(allocator, payload);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer allocator.free(raw);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try _unknown_fields_list.append(allocator, raw);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("continue;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeTextParseField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    switch (field.kind) {
        .scalar, .enumeration => {},
        .message, .group => |type_name| return try writeTextParseMessageField(ctx, field, type_name, writer, depth),
        .map => return try writeTextParseMapField(ctx, field, writer, depth),
    }
    try indent(writer, depth);
    try writer.writeAll("if (");
    try writeTextFieldValueLookup(field, "line", writer);
    try writer.writeAll(") |raw_value| {\n");
    if (field.cardinality == .repeated) {
        try indent(writer, depth + 1);
        if (field.kind == .enumeration) {
            try writer.writeAll("const parsed_enum = ");
            try writeTextParseEnumExpr(file, field.kind.enumeration, "raw_value", writer);
            try writer.writeAll(" catch |err| { if (options.ignore_unknown_fields) { continue; } return err; };\n");
            try indent(writer, depth + 1);
            try writeQuotedIdentWithSuffix(field.name, "_list", writer);
            try writer.writeAll(".append(allocator, parsed_enum) catch |err| return err;\n");
        } else {
            try writeQuotedIdentWithSuffix(field.name, "_list", writer);
            try writer.writeAll(".append(allocator, ");
            try writeTextParseValueExpr(file, field, field.kind, "raw_value", writer);
            try writer.writeAll(") catch |err| return err;\n");
        }
    } else {
        try indent(writer, depth + 1);
        try writer.writeAll("self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = ");
        if (field.kind == .enumeration) {
            try writeTextParseEnumExpr(file, field.kind.enumeration, "raw_value", writer);
            try writer.writeAll(" catch |err| { if (options.ignore_unknown_fields) { continue; } return err; }");
        } else {
            try writeTextParseValueExpr(file, field, field.kind, "raw_value", writer);
        }
        try writer.writeAll(";\n");
        if (hasPresence(file, field.*)) {
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

fn writeTextParseMessageField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, type_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    if (!codegenCanReferenceMessageWithContext(ctx, type_name)) return;
    try indent(writer, depth);
    try writer.writeAll("if (");
    try writeTextBlockCondition(field, "line", writer);
    try writer.writeAll(") {\n");
    try writeTextParseMessagePayloadAssign(ctx, field, type_name, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("continue;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeTextParseMessagePayloadAssign(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, type_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("const block = try @This().textBlock(allocator, &lines);\n");
    try indent(writer, depth);
    try writer.writeAll("defer allocator.free(block);\n");
    try indent(writer, depth);
    try writer.writeAll("var nested = try ");
    try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    try writer.writeAll(".parseTextWithOptions(allocator, block, .{ .ignore_unknown_fields = options.ignore_unknown_fields });\n");
    try indent(writer, depth);
    try writer.writeAll("defer nested.deinit(allocator);\n");
    if (typedRepeatedMessageFieldWithContext(ctx, field)) |_| {
        try indent(writer, depth);
        try writeQuotedIdentWithSuffix(field.name, "_list", writer);
        try writer.writeAll(".append(allocator, try nested.cloneOwned(allocator)) catch |err| return err;\n");
        return;
    }
    if (typedSingularMessageFieldWithContext(ctx, field)) |_| {
        try indent(writer, depth);
        try writer.writeAll("if (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(") |*existing| { try existing.mergeFrom(allocator, nested); } else { self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = try nested.cloneOwned(allocator); }\n");
        return;
    }
    if (typedOneofMessageFieldWithContext(ctx, field)) |_| {
        const oneof_name = field.oneof_name orelse return;
        try indent(writer, depth);
        try writer.writeAll("self.");
        try writeQuotedIdent(oneof_name, writer);
        try writer.writeAll(" = .{ .");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = try nested.cloneOwned(allocator) };\n");
        return;
    }
    try indent(writer, depth);
    try writer.writeAll("const owned_allocator = try self._pbzOwnedAllocator(allocator);\n");
    try indent(writer, depth);
    try writer.writeAll("const payload = try nested.encode(owned_allocator);\n");
    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        try writeQuotedIdentWithSuffix(field.name, "_list", writer);
        try writer.writeAll(".append(allocator, payload) catch |err| return err;\n");
    } else {
        if (field.oneof_name) |oneof_name| {
            try indent(writer, depth);
            try writer.writeAll("self.");
            try writeQuotedIdent(oneof_name, writer);
            try writer.writeAll(" = .{ .");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(" = payload };\n");
        } else {
            try indent(writer, depth);
            try writer.writeAll("if (self.");
            try writePresenceIdent(field.name, writer);
            try writer.writeAll(" and self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(".len != 0 and payload.len != 0) {\n");
            try indent(writer, depth + 1);
            try writer.writeAll("const merged = try owned_allocator.alloc(u8, self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(".len + payload.len);\n");
            try indent(writer, depth + 1);
            try writer.writeAll("@memcpy(merged[0..self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(".len], self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(");\n");
            try indent(writer, depth + 1);
            try writer.writeAll("@memcpy(merged[self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(".len..], payload);\n");
            try indent(writer, depth + 1);
            try writer.writeAll("self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(" = merged;\n");
            try indent(writer, depth);
            try writer.writeAll("} else {\n");
            try indent(writer, depth + 1);
            try writer.writeAll("self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(" = payload;\n");
            try indent(writer, depth);
            try writer.writeAll("}\n");
            if (hasPresenceForTextParseMessage(field.*)) {
                try indent(writer, depth);
                try writer.writeAll("self.");
                try writePresenceIdent(field.name, writer);
                try writer.writeAll(" = true;\n");
            }
        }
    }
}

fn writeTextParseMapField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    const map_type = switch (field.kind) {
        .map => |map_type| map_type,
        else => return,
    };
    if (!textMapValueSupported(ctx, map_type.value.*)) return;
    try indent(writer, depth);
    try writer.writeAll("if (");
    try writeTextBlockCondition(field, "line", writer);
    try writer.writeAll(") {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var entry = ");
    try writeQuotedIdentWithSuffix(field.name, "Entry", writer);
    try writer.writeAll("{};\n");
    if (typedMapMessageValueWithContext(ctx, field)) |_| {
        try indent(writer, depth + 1);
        try writer.writeAll("errdefer entry.value.deinit(allocator);\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll(if (textMapEntryCanSkip(map_type)) "var skip_entry = false;\n" else "const skip_entry = false;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("while (lines.next()) |raw_entry_line| {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("const entry_line = @This().textCleanLine(raw_entry_line);\n");
    try indent(writer, depth + 2);
    try writer.writeAll("if (entry_line.len == 0) continue;\n");
    try indent(writer, depth + 2);
    try writer.writeAll("if (std.mem.eql(u8, entry_line, \"}\") or std.mem.eql(u8, entry_line, \">\")) break;\n");
    try indent(writer, depth + 2);
    try writer.writeAll("if (@This().textFieldValue(entry_line, \"key\")) |raw_key| { entry.key = ");
    try writeTextParseValueExpr(file, field, .{ .scalar = map_type.key }, "raw_key", writer);
    try writer.writeAll("; continue; }\n");
    if (map_type.value.* == .message and codegenCanReferenceMessageWithContext(ctx, map_type.value.message)) {
        try indent(writer, depth + 2);
        try writer.writeAll("if (@This().textBlockField(entry_line, \"value\")) {\n");
        try indent(writer, depth + 3);
        try writer.writeAll("const block = try @This().textBlock(allocator, &lines);\n");
        try indent(writer, depth + 3);
        try writer.writeAll("defer allocator.free(block);\n");
        try indent(writer, depth + 3);
        try writer.writeAll("var nested = try ");
        try writeMessageTypeReferenceWithContext(ctx, map_type.value.message, writer);
        try writer.writeAll(".parseTextWithOptions(allocator, block, .{ .ignore_unknown_fields = options.ignore_unknown_fields });\n");
        try indent(writer, depth + 3);
        try writer.writeAll("defer nested.deinit(allocator);\n");
        if (typedMapMessageValueWithContext(ctx, field)) |_| {
            try indent(writer, depth + 3);
            try writer.writeAll("entry.value.deinit(allocator);\n");
            try indent(writer, depth + 3);
            try writer.writeAll("entry.value = try nested.cloneOwned(allocator);\n");
        } else {
            try indent(writer, depth + 3);
            try writer.writeAll("const owned_allocator = try self._pbzOwnedAllocator(allocator);\n");
            try indent(writer, depth + 3);
            try writer.writeAll("entry.value = try nested.encode(owned_allocator);\n");
        }
        try indent(writer, depth + 3);
        try writer.writeAll("continue;\n");
        try indent(writer, depth + 2);
        try writer.writeAll("}\n");
    }
    if (map_type.value.* == .scalar or map_type.value.* == .enumeration) {
        try indent(writer, depth + 2);
        try writer.writeAll("if (@This().textFieldValue(entry_line, \"value\")) |raw_value| { ");
        if (map_type.value.* == .enumeration) {
            try writer.writeAll("entry.value = ");
            try writeTextParseEnumExpr(file, map_type.value.enumeration, "raw_value", writer);
            try writer.writeAll(" catch |err| { if (options.ignore_unknown_fields) { skip_entry = true; continue; } return err; }; continue; }\n");
        } else {
            try writer.writeAll("entry.value = ");
            try writeTextParseValueExpr(file, field, map_type.value.*, "raw_value", writer);
            try writer.writeAll("; continue; }\n");
        }
    }
    try indent(writer, depth + 2);
    try writer.writeAll("return error.UnknownField;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (skip_entry) continue;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try @This().");
    try writeQuotedIdentWithPrefix(field.name, "appendOrReplaceMapEntry_", writer);
    try writer.writeAll("(allocator, &");
    try writeQuotedIdentWithSuffix(field.name, "_list", writer);
    try writer.writeAll(", entry);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("continue;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn textMapEntryCanSkip(map_type: schema.MapType) bool {
    return map_type.value.* == .enumeration;
}

fn writeTextParseOneofField(ctx: *const CodegenContext, oneof: schema.OneofDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    switch (field.kind) {
        .scalar, .enumeration => {},
        .message, .group => |type_name| {
            if (!codegenCanReferenceMessageWithContext(ctx, type_name)) return;
            try indent(writer, depth);
            try writer.writeAll("if (");
            try writeTextBlockCondition(field, "line", writer);
            try writer.writeAll(") {\n");
            try writeTextParseMessagePayloadAssign(ctx, field, type_name, writer, depth + 1);
            try indent(writer, depth + 1);
            try writer.writeAll("continue;\n");
            try indent(writer, depth);
            try writer.writeAll("}\n");
            return;
        },
        else => return,
    }
    try indent(writer, depth);
    try writer.writeAll("if (");
    try writeTextFieldValueLookup(field, "line", writer);
    try writer.writeAll(") |raw_value| { self.");
    try writeQuotedIdent(oneof.name, writer);
    try writer.writeAll(" = .{ .");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = ");
    if (field.kind == .enumeration) {
        try writeTextParseEnumExpr(file, field.kind.enumeration, "raw_value", writer);
        try writer.writeAll(" catch |err| { if (options.ignore_unknown_fields) { continue; } return err; }");
    } else {
        try writeTextParseValueExpr(file, field, field.kind, "raw_value", writer);
    }
    try writer.writeAll(" }; continue; }\n");
}

fn writeTextFieldValueLookup(field: *const schema.FieldDescriptor, line_expr: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("@This().textFieldValue(");
    try writer.writeAll(line_expr);
    try writer.writeAll(", ");
    try writeZigStringLiteral(field.name, writer);
    try writer.writeAll(")");
    try writeTextAlternateValueLookups(field, line_expr, writer);
}

fn writeTextAlternateValueLookups(field: *const schema.FieldDescriptor, line_expr: []const u8, writer: *std.Io.Writer) Error!void {
    if (field.json_name) |json_name| {
        if (!std.mem.eql(u8, json_name, field.name)) {
            try writer.writeAll(" orelse @This().textFieldValue(");
            try writer.writeAll(line_expr);
            try writer.writeAll(", ");
            try writeZigStringLiteral(json_name, writer);
            try writer.writeAll(")");
        }
    } else if (std.mem.indexOfScalar(u8, field.name, '_') != null) {
        try writer.writeAll(" orelse @This().textFieldValue(");
        try writer.writeAll(line_expr);
        try writer.writeAll(", ");
        try writeZigLowerCamelStringLiteral(field.name, writer);
        try writer.writeAll(")");
    }
}

fn writeTextBlockCondition(field: *const schema.FieldDescriptor, line_expr: []const u8, writer: *std.Io.Writer) Error!void {
    try writeTextBlockNameCondition(field.name, line_expr, writer);
    if (field.json_name) |json_name| {
        if (!std.mem.eql(u8, json_name, field.name)) {
            try writer.writeAll(" or ");
            try writeTextBlockNameCondition(json_name, line_expr, writer);
        }
    } else if (std.mem.indexOfScalar(u8, field.name, '_') != null) {
        try writer.writeAll(" or ");
        try writeTextLowerCamelBlockNameCondition(field.name, line_expr, writer);
    }
}

fn writeTextBlockNameCondition(name: []const u8, line_expr: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("@This().textBlockField(");
    try writer.writeAll(line_expr);
    try writer.writeAll(", ");
    try writeZigStringLiteral(name, writer);
    try writer.writeAll(")");
}

fn writeTextLowerCamelBlockNameCondition(name: []const u8, line_expr: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("@This().textBlockField(");
    try writer.writeAll(line_expr);
    try writer.writeAll(", ");
    try writeZigLowerCamelStringLiteral(name, writer);
    try writer.writeAll(")");
}

fn writeExtensionTextValueLookup(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, line_expr: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("@This().textFieldValue(");
    try writer.writeAll(line_expr);
    try writer.writeAll(", ");
    try writeExtensionTextNameLiteral(file, field, true, writer);
    try writer.writeAll(")");
    if (extensionHasLeafAlias(file, field)) {
        try writer.writeAll(" orelse @This().textFieldValue(");
        try writer.writeAll(line_expr);
        try writer.writeAll(", ");
        try writeExtensionTextNameLiteral(file, field, false, writer);
        try writer.writeAll(")");
    }
}

fn writeExtensionTextBlockCondition(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, line_expr: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("@This().textBlockField(");
    try writer.writeAll(line_expr);
    try writer.writeAll(", ");
    try writeExtensionTextNameLiteral(file, field, true, writer);
    try writer.writeAll(")");
    if (extensionHasLeafAlias(file, field)) {
        try writer.writeAll(" or @This().textBlockField(");
        try writer.writeAll(line_expr);
        try writer.writeAll(", ");
        try writeExtensionTextNameLiteral(file, field, false, writer);
        try writer.writeAll(")");
    }
}

fn extensionHasLeafAlias(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor) bool {
    const full_name = schema.extensionFullName(field);
    if (file.package.len != 0) return true;
    return std.mem.indexOfScalar(u8, full_name, '.') != null or std.mem.startsWith(u8, full_name, ".");
}

fn writeExtensionTextNameLiteral(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, qualified: bool, writer: *std.Io.Writer) Error!void {
    try writer.writeByte('"');
    try writer.writeByte('[');
    const full_name = schema.extensionFullName(field);
    if (qualified) {
        if (std.mem.startsWith(u8, full_name, ".")) {
            try writeEscapedStringContents(full_name[1..], writer);
        } else if (std.mem.indexOfScalar(u8, full_name, '.') != null or file.package.len == 0) {
            try writeEscapedStringContents(full_name, writer);
        } else {
            try writeEscapedStringContents(file.package, writer);
            try writer.writeByte('.');
            try writeEscapedStringContents(full_name, writer);
        }
    } else {
        try writeEscapedStringContents(leafTypeName(full_name), writer);
    }
    try writer.writeByte(']');
    try writer.writeByte('"');
}

fn leafTypeName(name: []const u8) []const u8 {
    const trimmed = if (std.mem.startsWith(u8, name, ".")) name[1..] else name;
    return if (std.mem.lastIndexOfScalar(u8, trimmed, '.')) |idx| trimmed[idx + 1 ..] else trimmed;
}

fn writeExtensionHelperReference(field: *const schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("extensions.");
    try writeExtensionHelperIdent(field, writer);
}

fn writeExtensionHelperIdent(field: *const schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    try writeQuotedIdent(schema.extensionFullName(field), writer);
}

fn hasPresenceForTextParseMessage(field: schema.FieldDescriptor) bool {
    return field.cardinality == .required or field.proto3_optional or field.kind == .message or field.kind == .group or if (field.features) |features| features.field_presence != .implicit else false;
}

fn writeTextParseValueExpr(file: *const schema.FileDescriptor, field: ?*const schema.FieldDescriptor, kind: schema.FieldKind, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    switch (kind) {
        .scalar => |scalar| switch (scalar) {
            .double => try writer.print("try @This().textFloat(f64, {s})", .{value_expr}),
            .float => try writer.print("try @This().textFloat(f32, {s})", .{value_expr}),
            .int32, .sint32, .sfixed32 => try writer.print("try @This().textInt(i32, {s})", .{value_expr}),
            .int64, .sint64, .sfixed64 => try writer.print("try @This().textInt(i64, {s})", .{value_expr}),
            .uint32, .fixed32 => try writer.print("try @This().textInt(u32, {s})", .{value_expr}),
            .uint64, .fixed64 => try writer.print("try @This().textInt(u64, {s})", .{value_expr}),
            .bool => try writer.print("try @This().textBool({s})", .{value_expr}),
            .string => {
                if (fieldUtf8ValidationOptional(file, field) == .verify) {
                    try writer.print("blk: {{ const decoded = try @This().textUnquote(try self._pbzOwnedAllocator(allocator), {s}); if (!pbz.validateUtf8(decoded)) return error.InvalidUtf8; break :blk decoded; }}", .{value_expr});
                } else {
                    try writer.print("try @This().textUnquote(try self._pbzOwnedAllocator(allocator), {s})", .{value_expr});
                }
            },
            .bytes => try writer.print("try @This().textUnquote(try self._pbzOwnedAllocator(allocator), {s})", .{value_expr}),
        },
        .enumeration => |name| {
            try writer.print("try @This().textEnum({s}, ", .{value_expr});
            try writeEnumNameArray(file, name, writer);
            try writer.writeAll(", ");
            try writeEnumNumberArray(file, name, writer);
            try writer.writeAll(", ");
            try writer.writeAll(if (enumIsClosed(file, name)) "true" else "false");
            try writer.writeAll(")");
        },
        else => try writer.writeAll("@compileError(\"unsupported TextFormat parse field kind\")"),
    }
}

fn writeTextParseEnumExpr(file: *const schema.FileDescriptor, enum_name: []const u8, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.print("@This().textEnum({s}, ", .{value_expr});
    try writeEnumNameArray(file, enum_name, writer);
    try writer.writeAll(", ");
    try writeEnumNumberArray(file, enum_name, writer);
    try writer.writeAll(", ");
    try writer.writeAll(if (enumIsClosed(file, enum_name)) "true" else "false");
    try writer.writeAll(")");
}

fn writeOneofValueEncode(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
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

fn writeOneofValueEncodeAssumeCapacity(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
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

fn typedSingularMessageField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor) ?[]const u8 {
    if (field.oneof_name != null or field.cardinality == .repeated) return null;
    if (field.kind != .message) return null;
    if (fieldMessageEncoding(file, field) != .length_prefixed) return null;
    return if (codegenCanReferenceMessage(file, field.kind.message)) field.kind.message else null;
}

fn typedSingularMessageFieldWithContext(ctx: *const CodegenContext, field: *const schema.FieldDescriptor) ?[]const u8 {
    if (field.oneof_name != null or field.cardinality == .repeated) return null;
    return typedLengthPrefixedOrGroupFieldWithContext(ctx, field);
}

fn typedRepeatedMessageField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor) ?[]const u8 {
    if (field.oneof_name != null or field.cardinality != .repeated) return null;
    if (field.kind != .message) return null;
    if (fieldMessageEncoding(file, field) != .length_prefixed) return null;
    return if (codegenCanReferenceMessage(file, field.kind.message)) field.kind.message else null;
}

fn typedRepeatedMessageFieldWithContext(ctx: *const CodegenContext, field: *const schema.FieldDescriptor) ?[]const u8 {
    if (field.oneof_name != null or field.cardinality != .repeated) return null;
    return typedLengthPrefixedOrGroupFieldWithContext(ctx, field);
}

fn typedOneofMessageFieldWithContext(ctx: *const CodegenContext, field: *const schema.FieldDescriptor) ?[]const u8 {
    if (field.oneof_name == null) return null;
    return typedLengthPrefixedOrGroupFieldWithContext(ctx, field);
}

fn typedLengthPrefixedOrGroupFieldWithContext(ctx: *const CodegenContext, field: *const schema.FieldDescriptor) ?[]const u8 {
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

fn typedMapMessageValueWithContext(ctx: *const CodegenContext, field: *const schema.FieldDescriptor) ?[]const u8 {
    const map_type = switch (field.kind) {
        .map => |map| map,
        else => return null,
    };
    return switch (map_type.value.*) {
        .message => |name| if (codegenCanReferenceMessageWithContext(ctx, name)) name else null,
        else => null,
    };
}

fn fieldCreatesValueDependencyCycle(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, type_name: []const u8) bool {
    const current = containingMessageForField(ctx.file, field) orelse return false;
    const target_ref = resolveMessageReference(ctx, type_name) orelse return false;
    if (!sameFileForCodegen(target_ref.file, ctx.file)) return false;
    return messageHasValuePathTo(ctx, target_ref.message, current, 0);
}

fn containingMessageForField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor) ?*const schema.MessageDescriptor {
    for (file.messages.items) |*message| {
        if (messageContainsField(message, field)) |owner| return owner;
    }
    return null;
}

fn messageContainsField(message: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor) ?*const schema.MessageDescriptor {
    for (message.fields.items) |*candidate| {
        if (candidate == field) return message;
    }
    for (message.messages.items) |*nested| {
        if (messageContainsField(nested, field)) |owner| return owner;
    }
    return null;
}

fn messageHasValuePathTo(ctx: *const CodegenContext, from: *const schema.MessageDescriptor, target: *const schema.MessageDescriptor, depth: usize) bool {
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

fn writeTypedMessageType(type_name: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeByte('?');
    try writeMessageTypeReference(type_name, writer);
}

fn writeTypedMessageTypeWithContext(ctx: *const CodegenContext, type_name: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeByte('?');
    try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
}

fn writeTypedRepeatedMessageType(type_name: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("[]const ");
    try writeMessageTypeReference(type_name, writer);
}

fn writeTypedRepeatedMessageTypeWithContext(ctx: *const CodegenContext, type_name: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("[]const ");
    try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
}

fn writeFieldDecl(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    try indent(writer, depth);
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(": ");
    if (typedSingularMessageFieldWithContext(ctx, field)) |type_name| {
        try writeTypedMessageTypeWithContext(ctx, type_name, writer);
        try writer.writeAll(" = null,\n");
        return;
    }
    if (typedRepeatedMessageFieldWithContext(ctx, field)) |type_name| {
        try writeTypedRepeatedMessageTypeWithContext(ctx, type_name, writer);
        try writer.writeAll(" = &.{},\n");
        return;
    }
    try writeFieldType(field.*, writer);
    try writer.writeAll(" = ");
    try writeFieldDefault(file, field.*, writer);
    try writer.writeAll(",\n");
    if (hasPresence(file, field.*)) {
        try indent(writer, depth);
        try writePresenceIdent(field.name, writer);
        try writer.writeAll(": bool = false,\n");
    }
}

fn writeMapEntryType(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    const map_type = switch (field.kind) {
        .map => |map| map,
        else => return,
    };
    try indent(writer, depth);
    try writer.writeAll("pub const ");
    try writeQuotedIdentWithSuffix(field.name, "Map", writer);
    try writer.writeAll(" = ");
    try writeMapStorageType(ctx, field, writer);
    try writer.writeAll(";\n\n");
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
    if (typedMapMessageValueWithContext(ctx, field)) |type_name| {
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    } else {
        try writeFieldKindType(map_type.value.*, writer);
    }
    try writer.writeAll(" = ");
    if (typedMapMessageValueWithContext(ctx, field)) |_| {
        try writer.writeAll(".{}");
    } else {
        try writeFieldKindDefault(file, map_type.value.*, null, writer);
    }
    try writer.writeAll(",\n");
    try indent(writer, depth);
    try writer.writeAll("};\n\n");
}

fn writeMapEntryHelpers(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const map_type = switch (field.kind) {
        .map => |map| map,
        else => return,
    };
    try indent(writer, depth);
    try writer.writeAll("fn ");
    try writeQuotedIdentWithPrefix(field.name, "appendOrReplaceMapEntry_", writer);
    try writer.writeAll("(allocator: std.mem.Allocator, list: *std.ArrayList(");
    try writeQuotedIdentWithSuffix(field.name, "Entry", writer);
    try writer.writeAll("), entry: ");
    try writeQuotedIdentWithSuffix(field.name, "Entry", writer);
    try writer.writeAll(") !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("for (list.items) |*existing| {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("if (");
    try writeMapKeyEqualExpr(map_type.key, "existing.key", "entry.key", writer);
    try writer.writeAll(") { ");
    if (typedMapMessageValueWithContext(ctx, field)) |_| {
        try writer.writeAll("existing.value.deinit(allocator); ");
    }
    try writer.writeAll("existing.* = entry; return; }\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try list.append(allocator, entry);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("fn ");
    try writeQuotedIdentWithPrefix(field.name, "putMapEntry_", writer);
    try writer.writeAll("(allocator: std.mem.Allocator, map: *");
    try writeQuotedIdentWithSuffix(field.name, "Map", writer);
    try writer.writeAll(", entry: ");
    try writeQuotedIdentWithSuffix(field.name, "Entry", writer);
    try writer.writeAll(") !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (map.getEntry(entry.key)) |existing| { ");
    if (typedMapMessageValueWithContext(ctx, field)) |_| {
        try writer.writeAll("existing.value_ptr.deinit(allocator); ");
    }
    try writer.writeAll("existing.value_ptr.* = entry.value; return; }\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try map.put(allocator, entry.key, entry.value);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("fn ");
    try writeQuotedIdentWithPrefix(field.name, "deinitMap_", writer);
    try writer.writeAll("(allocator: std.mem.Allocator, map: *");
    try writeQuotedIdentWithSuffix(field.name, "Map", writer);
    try writer.writeAll(") void {\n");
    if (typedMapMessageValueWithContext(ctx, field)) |_| {
        try indent(writer, depth + 1);
        try writer.writeAll("var it = map.iterator();\n");
        try indent(writer, depth + 1);
        try writer.writeAll("while (it.next()) |entry| entry.value_ptr.deinit(allocator);\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("map.deinit(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("map.* = .empty;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");
}

fn writeFieldAccessors(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    for (message.fields.items) |*field| {
        if (field.oneof_name == null) try writeFieldAccessor(ctx, field, writer, depth);
    }
    for (message.oneofs.items) |oneof| {
        for (message.fields.items) |*field| {
            if (field.oneof_name) |name| {
                if (std.mem.eql(u8, name, oneof.name)) try writeOneofFieldAccessor(ctx, field, oneof, writer, depth);
            }
        }
    }
}

fn writeFieldAccessor(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.cardinality == .repeated or field.kind == .map) return try writeRepeatedFieldAccessor(ctx, field, writer, depth);
    try writeSingularFieldAccessor(ctx, field, writer, depth);
}

fn writeSingularFieldAccessor(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    const presence = hasPresence(file, field.*);

    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedAccessorIdent("has", field.name, writer);
    try writer.writeAll("(self: @This()) bool {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return ");
    if (presence) {
        try writer.writeAll("self.");
        try writePresenceIdent(field.name, writer);
    } else {
        try writeFieldNonDefaultExpression(field, writer);
    }
    try writer.writeAll(";\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedAccessorIdent("get", field.name, writer);
    try writer.writeAll("(self: @This()) ");
    if (presence) try writer.writeByte('?');
    try writeFieldType(field.*, writer);
    try writer.writeAll(" {\n");
    try indent(writer, depth + 1);
    if (presence) {
        try writer.writeAll("return if (self.");
        try writePresenceIdent(field.name, writer);
        try writer.writeAll(") self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" else null;\n");
    } else {
        try writer.writeAll("return self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(";\n");
    }
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedAccessorIdent("getOrDefault", field.name, writer);
    try writer.writeAll("(self: @This()) ");
    try writeFieldType(field.*, writer);
    try writer.writeAll(" {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(";\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedAccessorIdent("set", field.name, writer);
    try writer.writeAll("(self: *@This(), value: ");
    try writeFieldType(field.*, writer);
    try writer.writeAll(") void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = value;\n");
    if (presence) {
        try indent(writer, depth + 1);
        try writer.writeAll("self.");
        try writePresenceIdent(field.name, writer);
        try writer.writeAll(" = true;\n");
    }
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedAccessorIdent("clear", field.name, writer);
    try writer.writeAll("(self: *@This()) void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = ");
    try writeFieldDefault(file, field.*, writer);
    try writer.writeAll(";\n");
    if (presence) {
        try indent(writer, depth + 1);
        try writer.writeAll("self.");
        try writePresenceIdent(field.name, writer);
        try writer.writeAll(" = false;\n");
    }
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    if (fieldMessageTypeName(field)) |type_name| {
        if (codegenCanReferenceMessageWithContext(ctx, type_name)) try writeSingularMessageFieldAccessor(ctx, field, type_name, writer, depth);
    }
    if (field.kind == .enumeration and codegenCanReferenceEnumWithContext(ctx, field.kind.enumeration)) {
        try writeSingularEnumFieldAccessor(ctx, field, field.kind.enumeration, presence, writer, depth);
    }
}

fn writeSingularEnumFieldAccessor(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, enum_name: []const u8, presence: bool, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedAccessorIdent("getEnum", field.name, writer);
    try writer.writeAll("(self: @This()) ?");
    try writeEnumTypeReferenceWithContext(ctx, enum_name, writer);
    try writer.writeAll(" {\n");
    try indent(writer, depth + 1);
    if (presence) {
        try writer.writeAll("const raw = self.");
        try writeQuotedAccessorIdent("get", field.name, writer);
        try writer.writeAll("() orelse return null;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return ");
        try writeEnumTypeReferenceWithContext(ctx, enum_name, writer);
        try writer.writeAll(".fromInt(raw);\n");
    } else {
        try writer.writeAll("return ");
        try writeEnumTypeReferenceWithContext(ctx, enum_name, writer);
        try writer.writeAll(".fromInt(self.");
        try writeQuotedAccessorIdent("get", field.name, writer);
        try writer.writeAll("());\n");
    }
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedAccessorIdent("getEnumOrDefault", field.name, writer);
    try writer.writeAll("(self: @This()) ");
    try writeEnumTypeReferenceWithContext(ctx, enum_name, writer);
    try writer.writeAll(" {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return self.");
    try writeQuotedAccessorIdent("getEnum", field.name, writer);
    try writer.writeAll("() orelse ");
    try writeEnumTypeReferenceWithContext(ctx, enum_name, writer);
    try writer.writeAll(".fromInt(self.");
    try writeQuotedAccessorIdent("getOrDefault", field.name, writer);
    try writer.writeAll("()) orelse unreachable;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedAccessorIdent("setEnum", field.name, writer);
    try writer.writeAll("(self: *@This(), value: ");
    try writeEnumTypeReferenceWithContext(ctx, enum_name, writer);
    try writer.writeAll(") void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("self.");
    try writeQuotedAccessorIdent("set", field.name, writer);
    try writer.writeAll("(value.toInt());\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");
}

fn writeSingularMessageFieldAccessor(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, type_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedAccessorIdent("setMessage", field.name, writer);
    try writer.writeAll("(self: *@This(), allocator: std.mem.Allocator, value: ");
    try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    try writer.writeAll(") !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const owned_allocator = try self._pbzOwnedAllocator(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("self.");
    try writeQuotedAccessorIdent("set", field.name, writer);
    try writer.writeAll("(try value.encode(owned_allocator));\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedAccessorIdent("getMessage", field.name, writer);
    try writer.writeAll("(self: @This(), allocator: std.mem.Allocator) !?");
    try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    try writer.writeAll(" {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const payload = self.");
    try writeQuotedAccessorIdent("get", field.name, writer);
    try writer.writeAll("() orelse return null;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try ");
    try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    try writer.writeAll(".decode(allocator, payload);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedAccessorIdent("decodeMessage", field.name, writer);
    try writer.writeAll("(self: @This(), allocator: std.mem.Allocator) !?");
    try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    try writer.writeAll(" {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try self.");
    try writeQuotedAccessorIdent("getMessage", field.name, writer);
    try writer.writeAll("(allocator);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");
}

fn writeRepeatedFieldAccessor(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedAccessorIdent("has", field.name, writer);
    try writer.writeAll("(self: @This()) bool {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".len != 0;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedAccessorIdent("get", field.name, writer);
    try writer.writeAll("(self: @This()) ");
    try writeFieldType(field.*, writer);
    try writer.writeAll(" {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(";\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedAccessorIdent("append", field.name, writer);
    try writer.writeAll("(self: *@This(), allocator: std.mem.Allocator, value: ");
    try writeRepeatedElementType(field.*, writer);
    try writer.writeAll(") !void {\n");
    if (field.kind == .map) {
        try indent(writer, depth + 1);
        try writer.writeAll("var list: std.ArrayList(");
        try writeRepeatedElementType(field.*, writer);
        try writer.writeAll(") = .empty;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("defer list.deinit(allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("if (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(".len != 0) try list.appendSlice(allocator, self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(");\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try @This().");
        try writeQuotedIdentWithPrefix(field.name, "appendOrReplaceMapEntry_", writer);
        try writer.writeAll("(allocator, &list, value);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const old = self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(";\n");
        try indent(writer, depth + 1);
        try writer.writeAll("self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = try list.toOwnedSlice(allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("if (old.len != 0) allocator.free(old);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n\n");
        try writeRepeatedAppendAllReplaceClear(ctx, field, writer, depth);
        try writeRepeatedSpecialFieldAccessors(ctx, field, writer, depth);
        return;
    }
    try indent(writer, depth + 1);
    try writer.writeAll("const old = self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const merged = try allocator.alloc(");
    try writeRepeatedElementType(field.*, writer);
    try writer.writeAll(", old.len + 1);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (old.len != 0) @memcpy(merged[0..old.len], old);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("merged[old.len] = value;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = merged;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (old.len != 0) allocator.free(old);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try writeRepeatedAppendAllReplaceClear(ctx, field, writer, depth);
    try writeRepeatedSpecialFieldAccessors(ctx, field, writer, depth);
}

fn writeRepeatedAppendAllReplaceClear(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedAccessorIdent("appendAll", field.name, writer);
    try writer.writeAll("(self: *@This(), allocator: std.mem.Allocator, values: ");
    try writeFieldType(field.*, writer);
    try writer.writeAll(") !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (values.len == 0) return;\n");
    if (field.kind == .map) {
        try indent(writer, depth + 1);
        try writer.writeAll("var list: std.ArrayList(");
        try writeRepeatedElementType(field.*, writer);
        try writer.writeAll(") = .empty;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("defer list.deinit(allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("if (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(".len != 0) try list.appendSlice(allocator, self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(");\n");
        try indent(writer, depth + 1);
        try writer.writeAll("for (values) |value| try @This().");
        try writeQuotedIdentWithPrefix(field.name, "appendOrReplaceMapEntry_", writer);
        try writer.writeAll("(allocator, &list, value);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const old = self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(";\n");
        try indent(writer, depth + 1);
        try writer.writeAll("self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = try list.toOwnedSlice(allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("if (old.len != 0) allocator.free(old);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n\n");
        try writeRepeatedReplaceClear(ctx, field, writer, depth);
        return;
    }
    try indent(writer, depth + 1);
    try writer.writeAll("const old = self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const merged = try allocator.alloc(");
    try writeRepeatedElementType(field.*, writer);
    try writer.writeAll(", old.len + values.len);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (old.len != 0) @memcpy(merged[0..old.len], old);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("@memcpy(merged[old.len..], values);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = merged;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (old.len != 0) allocator.free(old);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try writeRepeatedReplaceClear(ctx, field, writer, depth);
}

fn writeRepeatedReplaceClear(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedAccessorIdent("replace", field.name, writer);
    try writer.writeAll("(self: *@This(), allocator: std.mem.Allocator, values: ");
    try writeFieldType(field.*, writer);
    try writer.writeAll(") !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const old = self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (values.len == 0) {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = &.{};\n");
    if (typedMapMessageValueWithContext(ctx, field)) |_| {
        try indent(writer, depth + 2);
        try writer.writeAll("for (old) |old_entry| { var old_value = old_entry.value; old_value.deinit(allocator); }\n");
    }
    try indent(writer, depth + 2);
    try writer.writeAll("if (old.len != 0) allocator.free(old);\n");
    try indent(writer, depth + 2);
    try writer.writeAll("return;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    if (field.kind == .map) {
        try indent(writer, depth + 1);
        try writer.writeAll("var list: std.ArrayList(");
        try writeRepeatedElementType(field.*, writer);
        try writer.writeAll(") = .empty;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("defer list.deinit(allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("for (values) |value| try @This().");
        try writeQuotedIdentWithPrefix(field.name, "appendOrReplaceMapEntry_", writer);
        try writer.writeAll("(allocator, &list, value);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = try list.toOwnedSlice(allocator);\n");
        if (typedMapMessageValueWithContext(ctx, field)) |_| {
            try indent(writer, depth + 1);
            try writer.writeAll("for (old) |old_entry| { var old_value = old_entry.value; old_value.deinit(allocator); }\n");
        }
        try indent(writer, depth + 1);
        try writer.writeAll("if (old.len != 0) allocator.free(old);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n\n");
        try writeRepeatedClear(ctx, field, writer, depth);
        return;
    }
    try indent(writer, depth + 1);
    try writer.writeAll("const owned = try allocator.dupe(");
    try writeRepeatedElementType(field.*, writer);
    try writer.writeAll(", values);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = owned;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (old.len != 0) allocator.free(old);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try writeRepeatedClear(ctx, field, writer, depth);
}

fn writeRepeatedClear(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedAccessorIdent("clear", field.name, writer);
    try writer.writeAll("(self: *@This(), allocator: std.mem.Allocator) void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const old = self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = &.{};\n");
    if (typedMapMessageValueWithContext(ctx, field)) |_| {
        try indent(writer, depth + 1);
        try writer.writeAll("for (old) |old_entry| { var old_value = old_entry.value; old_value.deinit(allocator); }\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("if (old.len != 0) allocator.free(old);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");
}

fn writeRepeatedSpecialFieldAccessors(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (fieldMessageTypeName(field)) |type_name| {
        if (codegenCanReferenceMessageWithContext(ctx, type_name)) try writeRepeatedMessageFieldAccessor(ctx, field, type_name, writer, depth);
    }
    if (field.kind == .enumeration and codegenCanReferenceEnumWithContext(ctx, field.kind.enumeration)) {
        try writeRepeatedEnumFieldAccessor(ctx, field, field.kind.enumeration, writer, depth);
    }
    if (field.kind == .map and field.kind.map.value.* == .enumeration and codegenCanReferenceEnumWithContext(ctx, field.kind.map.value.enumeration)) {
        try writeMapEnumFieldAccessor(ctx, field, field.kind.map, field.kind.map.value.enumeration, writer, depth);
    }
    if (field.kind == .map and field.kind.map.value.* == .message and codegenCanReferenceMessageWithContext(ctx, field.kind.map.value.message)) {
        try writeMapMessageFieldAccessor(ctx, field, field.kind.map, field.kind.map.value.message, writer, depth);
    }
}

fn writeMapMessageFieldAccessor(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, map_type: schema.MapType, type_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    const typed_value = typedMapMessageValueWithContext(ctx, field) != null;
    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedAccessorIdent("appendMessageEntry", field.name, writer);
    try writer.writeAll("(self: *@This(), allocator: std.mem.Allocator, key: ");
    try writer.writeAll(scalarZigType(map_type.key));
    try writer.writeAll(", value: ");
    try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    try writer.writeAll(") !void {\n");
    try indent(writer, depth + 1);
    if (typed_value) {
        try writer.writeAll("var cloned_value = try value.cloneOwned(allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("errdefer cloned_value.deinit(allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try self.");
        try writeQuotedAccessorIdent("append", field.name, writer);
        try writer.writeAll("(allocator, .{ .key = key, .value = cloned_value });\n");
    } else {
        try writer.writeAll("try self.");
        try writeQuotedAccessorIdent("append", field.name, writer);
        try writer.writeAll("(allocator, .{ .key = key, .value = try value.encode(try self._pbzOwnedAllocator(allocator)) });\n");
    }
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedAccessorIdent("replaceMessageEntry", field.name, writer);
    try writer.writeAll("(self: *@This(), allocator: std.mem.Allocator, key: ");
    try writer.writeAll(scalarZigType(map_type.key));
    try writer.writeAll(", value: ");
    try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    try writer.writeAll(") !void {\n");
    try indent(writer, depth + 1);
    if (typed_value) {
        try writer.writeAll("const owned_value = try value.cloneOwned(allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("errdefer owned_value.deinit(allocator);\n");
    } else {
        try writer.writeAll("const payload = try value.encode(try self._pbzOwnedAllocator(allocator));\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("for (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(", 0..) |entry, i| {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("if (");
    try writeMapKeyEqualExpr(map_type.key, "entry.key", "key", writer);
    try writer.writeAll(") { self.");
    try writeQuotedIdent(field.name, writer);
    if (typed_value) {
        try writer.writeAll("[i].value.deinit(allocator); self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll("[i] = .{ .key = key, .value = owned_value }; return; }\n");
    } else {
        try writer.writeAll("[i] = .{ .key = key, .value = payload }; return; }\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.");
    try writeQuotedAccessorIdent("append", field.name, writer);
    if (typed_value) {
        try writer.writeAll("(allocator, .{ .key = key, .value = owned_value });\n");
    } else {
        try writer.writeAll("(allocator, .{ .key = key, .value = payload });\n");
    }
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedAccessorIdent("removeMessageEntry", field.name, writer);
    try writer.writeAll("(self: *@This(), allocator: std.mem.Allocator, key: ");
    try writer.writeAll(scalarZigType(map_type.key));
    try writer.writeAll(") !bool {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("for (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(", 0..) |entry, i| {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("if (");
    try writeMapKeyEqualExpr(map_type.key, "entry.key", "key", writer);
    try writer.writeAll(") {\n");
    if (typed_value) {
        try indent(writer, depth + 3);
        try writer.writeAll("self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll("[i].value.deinit(allocator);\n");
    }
    try indent(writer, depth + 3);
    try writer.writeAll("const old = self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 3);
    try writer.writeAll("if (old.len == 1) { self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = &.{}; allocator.free(old); return true; }\n");
    try indent(writer, depth + 3);
    try writer.writeAll("const replacement = try allocator.alloc(");
    try writeQuotedIdentWithSuffix(field.name, "Entry", writer);
    try writer.writeAll(", old.len - 1);\n");
    try indent(writer, depth + 3);
    try writer.writeAll("if (i != 0) @memcpy(replacement[0..i], old[0..i]);\n");
    try indent(writer, depth + 3);
    try writer.writeAll("if (i + 1 < old.len) @memcpy(replacement[i..], old[i + 1 ..]);\n");
    try indent(writer, depth + 3);
    try writer.writeAll("self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = replacement;\n");
    try indent(writer, depth + 3);
    try writer.writeAll("allocator.free(old);\n");
    try indent(writer, depth + 3);
    try writer.writeAll("return true;\n");
    try indent(writer, depth + 2);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return false;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedAccessorIdent("getMessageEntry", field.name, writer);
    try writer.writeAll("(self: @This(), allocator: std.mem.Allocator, key: ");
    try writer.writeAll(scalarZigType(map_type.key));
    try writer.writeAll(") !");
    try writer.writeByte('?');
    try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    try writer.writeAll(" {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("for (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(") |entry| {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("if (");
    try writeMapKeyEqualExpr(map_type.key, "entry.key", "key", writer);
    if (typed_value) {
        try writer.writeAll(") return try entry.value.cloneOwned(allocator);\n");
    } else {
        try writer.writeAll(") return try ");
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
        try writer.writeAll(".decode(allocator, entry.value);\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return null;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");
}

fn writeMapEnumFieldAccessor(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, map_type: schema.MapType, enum_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedAccessorIdent("appendEnumEntry", field.name, writer);
    try writer.writeAll("(self: *@This(), allocator: std.mem.Allocator, key: ");
    try writer.writeAll(scalarZigType(map_type.key));
    try writer.writeAll(", value: ");
    try writeEnumTypeReferenceWithContext(ctx, enum_name, writer);
    try writer.writeAll(") !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.");
    try writeQuotedAccessorIdent("append", field.name, writer);
    try writer.writeAll("(allocator, .{ .key = key, .value = value.toInt() });\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedAccessorIdent("replaceEnumEntry", field.name, writer);
    try writer.writeAll("(self: *@This(), allocator: std.mem.Allocator, key: ");
    try writer.writeAll(scalarZigType(map_type.key));
    try writer.writeAll(", value: ");
    try writeEnumTypeReferenceWithContext(ctx, enum_name, writer);
    try writer.writeAll(") !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("for (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(", 0..) |entry, i| {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("if (");
    try writeMapKeyEqualExpr(map_type.key, "entry.key", "key", writer);
    try writer.writeAll(") { self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll("[i] = .{ .key = key, .value = value.toInt() }; return; }\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.");
    try writeQuotedAccessorIdent("append", field.name, writer);
    try writer.writeAll("(allocator, .{ .key = key, .value = value.toInt() });\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedAccessorIdent("removeEnumEntry", field.name, writer);
    try writer.writeAll("(self: *@This(), allocator: std.mem.Allocator, key: ");
    try writer.writeAll(scalarZigType(map_type.key));
    try writer.writeAll(") !bool {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("for (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(", 0..) |entry, i| {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("if (");
    try writeMapKeyEqualExpr(map_type.key, "entry.key", "key", writer);
    try writer.writeAll(") {\n");
    try indent(writer, depth + 3);
    try writer.writeAll("const old = self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 3);
    try writer.writeAll("if (old.len == 1) { self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = &.{}; allocator.free(old); return true; }\n");
    try indent(writer, depth + 3);
    try writer.writeAll("const replacement = try allocator.alloc(");
    try writeQuotedIdentWithSuffix(field.name, "Entry", writer);
    try writer.writeAll(", old.len - 1);\n");
    try indent(writer, depth + 3);
    try writer.writeAll("if (i != 0) @memcpy(replacement[0..i], old[0..i]);\n");
    try indent(writer, depth + 3);
    try writer.writeAll("if (i + 1 < old.len) @memcpy(replacement[i..], old[i + 1 ..]);\n");
    try indent(writer, depth + 3);
    try writer.writeAll("self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = replacement;\n");
    try indent(writer, depth + 3);
    try writer.writeAll("allocator.free(old);\n");
    try indent(writer, depth + 3);
    try writer.writeAll("return true;\n");
    try indent(writer, depth + 2);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return false;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedAccessorIdent("getEnumEntry", field.name, writer);
    try writer.writeAll("(self: @This(), key: ");
    try writer.writeAll(scalarZigType(map_type.key));
    try writer.writeAll(") ?");
    try writeEnumTypeReferenceWithContext(ctx, enum_name, writer);
    try writer.writeAll(" {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("for (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(") |entry| {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("if (");
    try writeMapKeyEqualExpr(map_type.key, "entry.key", "key", writer);
    try writer.writeAll(") return ");
    try writeEnumTypeReferenceWithContext(ctx, enum_name, writer);
    try writer.writeAll(".fromInt(entry.value);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return null;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");
}

fn writeMapKeyEqualExpr(scalar: schema.ScalarType, lhs: []const u8, rhs: []const u8, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .string => try writer.print("std.mem.eql(u8, {s}, {s})", .{ lhs, rhs }),
        else => try writer.print("{s} == {s}", .{ lhs, rhs }),
    }
}

fn writeRepeatedEnumFieldAccessor(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, enum_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedAccessorIdent("appendEnum", field.name, writer);
    try writer.writeAll("(self: *@This(), allocator: std.mem.Allocator, value: ");
    try writeEnumTypeReferenceWithContext(ctx, enum_name, writer);
    try writer.writeAll(") !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.");
    try writeQuotedAccessorIdent("append", field.name, writer);
    try writer.writeAll("(allocator, value.toInt());\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedAccessorIdent("appendAllEnums", field.name, writer);
    try writer.writeAll("(self: *@This(), allocator: std.mem.Allocator, values: []const ");
    try writeEnumTypeReferenceWithContext(ctx, enum_name, writer);
    try writer.writeAll(") !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (values.len == 0) return;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const raw = try allocator.alloc(i32, values.len);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("defer allocator.free(raw);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("for (values, 0..) |value, i| raw[i] = value.toInt();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.");
    try writeQuotedAccessorIdent("appendAll", field.name, writer);
    try writer.writeAll("(allocator, raw);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedAccessorIdent("replaceEnums", field.name, writer);
    try writer.writeAll("(self: *@This(), allocator: std.mem.Allocator, values: []const ");
    try writeEnumTypeReferenceWithContext(ctx, enum_name, writer);
    try writer.writeAll(") !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const raw = try allocator.alloc(i32, values.len);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("defer allocator.free(raw);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("for (values, 0..) |value, i| raw[i] = value.toInt();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.");
    try writeQuotedAccessorIdent("replace", field.name, writer);
    try writer.writeAll("(allocator, raw);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedAccessorIdent("getEnums", field.name, writer);
    try writer.writeAll("(self: @This(), allocator: std.mem.Allocator) !");
    try writer.writeAll("[]");
    try writeEnumTypeReferenceWithContext(ctx, enum_name, writer);
    try writer.writeAll(" {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const raw = self.");
    try writeQuotedAccessorIdent("get", field.name, writer);
    try writer.writeAll("();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const out = try allocator.alloc(");
    try writeEnumTypeReferenceWithContext(ctx, enum_name, writer);
    try writer.writeAll(", raw.len);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer allocator.free(out);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("for (raw, 0..) |value, i| out[i] = ");
    try writeEnumTypeReferenceWithContext(ctx, enum_name, writer);
    try writer.writeAll(".fromInt(value) orelse return error.InvalidEnumValue;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return out;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");
}

fn writeRepeatedMessageFieldAccessor(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, type_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedAccessorIdent("appendMessage", field.name, writer);
    try writer.writeAll("(self: *@This(), allocator: std.mem.Allocator, value: ");
    try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    try writer.writeAll(") !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const owned_allocator = try self._pbzOwnedAllocator(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.");
    try writeQuotedAccessorIdent("append", field.name, writer);
    try writer.writeAll("(allocator, try value.encode(owned_allocator));\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedAccessorIdent("appendMessages", field.name, writer);
    try writer.writeAll("(self: *@This(), allocator: std.mem.Allocator, values: []const ");
    try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    try writer.writeAll(") !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("for (values) |value| try self.");
    try writeQuotedAccessorIdent("appendMessage", field.name, writer);
    try writer.writeAll("(allocator, value);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedAccessorIdent("replaceMessages", field.name, writer);
    try writer.writeAll("(self: *@This(), allocator: std.mem.Allocator, values: []const ");
    try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    try writer.writeAll(") !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const old = self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (values.len == 0) {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = &.{};\n");
    try indent(writer, depth + 2);
    try writer.writeAll("if (old.len != 0) allocator.free(old);\n");
    try indent(writer, depth + 2);
    try writer.writeAll("return;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const owned_allocator = try self._pbzOwnedAllocator(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const owned = try allocator.alloc([]const u8, values.len);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer allocator.free(owned);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("for (values, 0..) |value, i| owned[i] = try value.encode(owned_allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = owned;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (old.len != 0) allocator.free(old);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedAccessorIdent("getMessages", field.name, writer);
    try writer.writeAll("(self: @This(), allocator: std.mem.Allocator) ![]");
    try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    try writer.writeAll(" {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var list: std.ArrayList(");
    try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    try writer.writeAll(") = .empty;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer { for (list.items) |*item| item.deinit(allocator); list.deinit(allocator); }\n");
    try indent(writer, depth + 1);
    try writer.writeAll("for (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(") |payload| try list.append(allocator, try ");
    try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    try writer.writeAll(".decode(allocator, payload));\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try list.toOwnedSlice(allocator);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedAccessorIdent("decodeMessages", field.name, writer);
    try writer.writeAll("(self: @This(), allocator: std.mem.Allocator) ![]");
    try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    try writer.writeAll(" {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try self.");
    try writeQuotedAccessorIdent("getMessages", field.name, writer);
    try writer.writeAll("(allocator);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");
}

fn writeOneofFieldAccessor(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, oneof: schema.OneofDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedAccessorIdent("has", field.name, writer);
    try writer.writeAll("(self: @This()) bool {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return switch (self.");
    try writeQuotedIdent(oneof.name, writer);
    try writer.writeAll(") { .");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" => true, else => false };\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedAccessorIdent("get", field.name, writer);
    try writer.writeAll("(self: @This()) ?");
    try writeFieldType(field.*, writer);
    try writer.writeAll(" {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return switch (self.");
    try writeQuotedIdent(oneof.name, writer);
    try writer.writeAll(") { .");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" => |value| value, else => null };\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedAccessorIdent("set", field.name, writer);
    try writer.writeAll("(self: *@This(), value: ");
    try writeFieldType(field.*, writer);
    try writer.writeAll(") void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("self.");
    try writeQuotedIdent(oneof.name, writer);
    try writer.writeAll(" = .{ .");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = value };\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedAccessorIdent("clear", field.name, writer);
    try writer.writeAll("(self: *@This()) void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (self.");
    try writeQuotedAccessorIdent("has", field.name, writer);
    try writer.writeAll("()) self.");
    try writeQuotedIdent(oneof.name, writer);
    try writer.writeAll(" = .none;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    if (fieldMessageTypeName(field)) |type_name| {
        if (codegenCanReferenceMessageWithContext(ctx, type_name)) try writeOneofMessageFieldAccessor(ctx, field, oneof, type_name, writer, depth);
    }
    if (field.kind == .enumeration and codegenCanReferenceEnumWithContext(ctx, field.kind.enumeration)) {
        try writeOneofEnumFieldAccessor(ctx, field, field.kind.enumeration, writer, depth);
    }
}

fn writeOneofEnumFieldAccessor(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, enum_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedAccessorIdent("getEnum", field.name, writer);
    try writer.writeAll("(self: @This()) ?");
    try writeEnumTypeReferenceWithContext(ctx, enum_name, writer);
    try writer.writeAll(" {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const raw = self.");
    try writeQuotedAccessorIdent("get", field.name, writer);
    try writer.writeAll("() orelse return null;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return ");
    try writeEnumTypeReferenceWithContext(ctx, enum_name, writer);
    try writer.writeAll(".fromInt(raw);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedAccessorIdent("setEnum", field.name, writer);
    try writer.writeAll("(self: *@This(), value: ");
    try writeEnumTypeReferenceWithContext(ctx, enum_name, writer);
    try writer.writeAll(") void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("self.");
    try writeQuotedAccessorIdent("set", field.name, writer);
    try writer.writeAll("(value.toInt());\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");
}

fn writeOneofMessageFieldAccessor(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, oneof: schema.OneofDescriptor, type_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedAccessorIdent("setMessage", field.name, writer);
    try writer.writeAll("(self: *@This(), allocator: std.mem.Allocator, value: ");
    try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    try writer.writeAll(") !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const owned_allocator = try self._pbzOwnedAllocator(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("self.");
    try writeQuotedIdent(oneof.name, writer);
    try writer.writeAll(" = .{ .");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = try value.encode(owned_allocator) };\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedAccessorIdent("getMessage", field.name, writer);
    try writer.writeAll("(self: @This(), allocator: std.mem.Allocator) !?");
    try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    try writer.writeAll(" {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const payload = self.");
    try writeQuotedAccessorIdent("get", field.name, writer);
    try writer.writeAll("() orelse return null;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try ");
    try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    try writer.writeAll(".decode(allocator, payload);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedAccessorIdent("decodeMessage", field.name, writer);
    try writer.writeAll("(self: @This(), allocator: std.mem.Allocator) !?");
    try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    try writer.writeAll(" {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try self.");
    try writeQuotedAccessorIdent("getMessage", field.name, writer);
    try writer.writeAll("(allocator);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");
}

fn fieldMessageTypeName(field: *const schema.FieldDescriptor) ?[]const u8 {
    return switch (field.kind) {
        .message, .group => |type_name| type_name,
        else => null,
    };
}

fn writeFieldNonDefaultExpression(field: *const schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    switch (field.kind) {
        .scalar => |scalar| {
            try writer.writeAll("self.");
            try writeQuotedIdent(field.name, writer);
            switch (scalar) {
                .string, .bytes => try writer.writeAll(".len != 0"),
                .bool => {},
                else => try writer.writeAll(" != 0"),
            }
        },
        .enumeration => {
            try writer.writeAll("self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(" != 0");
        },
        .message, .group => {
            try writer.writeAll("self.");
            try writePresenceIdent(field.name, writer);
        },
        .map => {
            try writer.writeAll("self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(".len != 0");
        },
    }
}

fn writeInit(writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn init() @This() {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return .{};\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeEncode(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try writeEncodedSize(ctx, message, writer, depth);
    try writer.writeAll("\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn writeTo(self: @This(), w: *pbz.Writer) !void {\n");
    for (message.fields.items) |*field| {
        if (field.oneof_name == null) try writeEncodeField(ctx, field, writer, depth + 1);
    }
    for (message.oneofs.items) |oneof| try writeEncodeOneof(ctx, message, oneof, writer, depth + 1);
    try writeEncodeUnknownFields(writer, depth + 1);
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn writeToAssumeCapacity(self: @This(), w: *pbz.Writer) !void {\n");
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

fn messageCanFastDirectEncode(ctx: *const CodegenContext, message: *const schema.MessageDescriptor) bool {
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

fn mapCanFastDirectEncode(ctx: *const CodegenContext, field: *const schema.FieldDescriptor) bool {
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

fn writeFastDirectEncodeIntoAssumeCapacity(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, validate_utf8: bool, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeFastDirectScalarEncode(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, scalar: schema.ScalarType, validate_utf8: bool, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("if (");
    if (hasPresence(file, field.*)) {
        try writer.writeAll("self.");
        try writePresenceIdent(field.name, writer);
        try writer.writeAll(") ");
    } else {
        try writer.writeAll("self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(defaultSkipCondition(scalar));
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

fn writeFastDirectEnumEncode(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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
    try writer.writeAll(" pbz.wire.writeVarintToSlice(buffer, &index, @as(u64, @bitCast(@as(i64, self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(")))); }\n");
}

fn writeFastDirectRepeatedScalarEncode(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, scalar: schema.ScalarType, validate_utf8: bool, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeFastDirectSingularMessageEncode(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, validate_utf8: bool, writer: *std.Io.Writer, depth: usize) Error!void {
    if (typedSingularMessageFieldWithContext(ctx, field) == null) return;
    try indent(writer, depth);
    try writer.writeAll("if (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(") |value| { ");
    try writeFastDirectMessagePayload(field, "value", validate_utf8, writer);
    try writer.writeAll(" }\n");
}

fn writeFastDirectRepeatedMessageEncode(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, validate_utf8: bool, writer: *std.Io.Writer, depth: usize) Error!void {
    if (typedRepeatedMessageFieldWithContext(ctx, field) == null) return;
    try indent(writer, depth);
    try writer.writeAll("for (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(") |item| { ");
    try writeFastDirectMessagePayload(field, "item", validate_utf8, writer);
    try writer.writeAll(" }\n");
}

fn writeFastDirectMapEncode(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, validate_utf8: bool, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeFastDirectMapUtf8Validation(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, value_expr: []const u8, kind: schema.FieldKind, writer: *std.Io.Writer, depth: usize) Error!void {
    if (kind == .scalar and kind.scalar == .string and fieldUtf8Validation(file, field) == .verify) {
        try indent(writer, depth);
        try writer.print("if (!pbz.validateUtf8({s})) return error.InvalidUtf8;\n", .{value_expr});
    }
}

fn writeFastDirectMapValuePayload(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, map_type: schema.MapType, validate_utf8: bool, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeFastDirectMapScalarPayload(number: u29, scalar: schema.ScalarType, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    try writeFastDirectTag(number, .{ .scalar = scalar }, writer);
    try writer.writeByte(' ');
    if (scalar == .string or scalar == .bytes) {
        try writeFastDirectLengthDelimitedPayload("", value_expr, writer);
    } else {
        try writeFastDirectScalarPayload(value_expr, "", scalar, writer);
    }
}

fn writeFastDirectOneofEncode(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, oneof: schema.OneofDescriptor, validate_utf8: bool, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeFastDirectMessagePayload(field: *const schema.FieldDescriptor, value_expr: []const u8, validate_utf8: bool, writer: *std.Io.Writer) Error!void {
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

fn writeFastDirectLengthDelimitedValidation(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, validate_utf8: bool, prefix: []const u8, value_name: []const u8, writer: *std.Io.Writer) Error!void {
    if (!validate_utf8 or field.kind != .scalar or field.kind.scalar != .string or fieldUtf8Validation(file, field) != .verify) return;
    try writer.writeAll("if (!pbz.validateUtf8(");
    try writer.writeAll(prefix);
    if (value_name.len != 0) try writeQuotedIdent(value_name, writer);
    try writer.writeAll(")) return error.InvalidUtf8; ");
}

fn writeFastDirectLengthDelimitedPayload(prefix: []const u8, value_name: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("pbz.wire.writeVarintToSlice(buffer, &index, ");
    try writer.writeAll(prefix);
    if (value_name.len != 0) try writeQuotedIdent(value_name, writer);
    try writer.writeAll(".len); @memcpy(buffer[index..][0..");
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

fn writeFastDirectRepeatedEnumEncode(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("for (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(") |item| { ");
    try writeFastDirectTag(field.number, .{ .enumeration = "" }, writer);
    try writer.writeAll(" pbz.wire.writeVarintToSlice(buffer, &index, @as(u64, @bitCast(@as(i64, item)))); }\n");
}

fn writeFastDirectPackedScalarEncode(field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
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
                try writer.writeAll("); @memcpy(buffer[index..][0..payload.len], payload); index += payload.len; } else { for (self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(") |item| pbz.wire.writeRawLittleToSlice(u64, buffer, &index, @bitCast(item)); }\n");
            } else if (scalar == .float) {
                try writer.writeAll("if (comptime @import(\"builtin\").target.cpu.arch.endian() == .little) { const payload = std.mem.sliceAsBytes(self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll("); @memcpy(buffer[index..][0..payload.len], payload); index += payload.len; } else { for (self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(") |item| pbz.wire.writeRawLittleToSlice(u32, buffer, &index, @bitCast(item)); }\n");
            } else {
                try writer.writeAll("const payload = std.mem.sliceAsBytes(self.");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll("); @memcpy(buffer[index..][0..payload.len], payload); index += payload.len;\n");
            }
        } else if (scalar == .bool) {
            try indent(writer, depth + 1);
            try writer.writeAll("const payload = std.mem.sliceAsBytes(self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll("); @memcpy(buffer[index..][0..payload.len], payload); index += payload.len;\n");
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

fn writeFastDirectPackedEnumEncode(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeFastDirectTag(number: u29, kind: schema.FieldKind, writer: *std.Io.Writer) Error!void {
    const tag = rawFieldTag(number, kind);
    try writeFastDirectTagValue(tag, writer);
}

fn writeFastDirectRawTag(number: u29, wire_type: wire.WireType, writer: *std.Io.Writer) Error!void {
    const tag = rawTagValue(number, wire_type);
    try writeFastDirectTagValue(tag, writer);
}

fn writeFastDirectTagValue(tag: u64, writer: *std.Io.Writer) Error!void {
    if (tag <= std.math.maxInt(u8)) {
        try writer.print("buffer[index] = {d}; index += 1;", .{tag});
    } else {
        try writer.print("pbz.wire.writeVarintToSlice(buffer, &index, {d});", .{tag});
    }
}

fn writeFastDirectScalarPayload(prefix: []const u8, field_name: []const u8, scalar: schema.ScalarType, writer: *std.Io.Writer) Error!void {
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
        .bool => try writeFastDirectVarintFieldPayload(prefix, field_name, "@as(u64, if (", ") 1 else 0)", writer),
        .string, .bytes => try writer.writeAll("@compileError(\"unsupported direct payload\")"),
    }
}

fn writeFastDirectRawFieldPayload(prefix: []const u8, field_name: []const u8, zig_type: []const u8, bitcast_value: bool, writer: *std.Io.Writer) Error!void {
    try writer.print("pbz.wire.writeRawLittleToSlice({s}, buffer, &index, ", .{zig_type});
    if (bitcast_value) try writer.writeAll("@bitCast(");
    try writer.writeAll(prefix);
    if (field_name.len != 0) try writeQuotedIdent(field_name, writer);
    if (bitcast_value) try writer.writeAll(")");
    try writer.writeAll(");");
}

fn writeFastDirectVarintFieldPayload(prefix: []const u8, field_name: []const u8, before: []const u8, after: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("pbz.wire.writeVarintToSlice(buffer, &index, ");
    try writer.writeAll(before);
    try writer.writeAll(prefix);
    if (field_name.len != 0) try writeQuotedIdent(field_name, writer);
    try writer.writeAll(after);
    try writer.writeAll(");");
}

fn writeFastDirectPackedScalarPayload(value_expr: []const u8, scalar: schema.ScalarType, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .int32 => try writer.print("pbz.wire.writeVarintToSlice(buffer, &index, @as(u64, @bitCast(@as(i64, {s}))));", .{value_expr}),
        .int64 => try writer.print("pbz.wire.writeVarintToSlice(buffer, &index, @as(u64, @bitCast({s})));", .{value_expr}),
        .uint32, .uint64 => try writer.print("pbz.wire.writeVarintToSlice(buffer, &index, {s});", .{value_expr}),
        .sint32 => try writer.print("pbz.wire.writeVarintToSlice(buffer, &index, pbz.wire.zigZagEncode32({s}));", .{value_expr}),
        .sint64 => try writer.print("pbz.wire.writeVarintToSlice(buffer, &index, pbz.wire.zigZagEncode64({s}));", .{value_expr}),
        .bool => try writer.print("{{ buffer[index] = if ({s}) 1 else 0; index += 1; }}", .{value_expr}),
        else => try writer.writeAll("@compileError(\"unsupported packed direct payload\")"),
    }
}

fn maxPackedScalarWidth(scalar: schema.ScalarType) usize {
    return switch (scalar) {
        .bool => 1,
        .uint32, .sint32 => 5,
        .int32, .int64, .uint64, .sint64 => 10,
        .double, .fixed64, .sfixed64 => 8,
        .float, .fixed32, .sfixed32 => 4,
        .string, .bytes => unreachable,
    };
}

fn writeEncodedSize(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeEncodedSizeField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, receiver: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
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
                try writer.writeAll("if (");
                try writer.writeAll(receiver);
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(defaultSkipCondition(scalar));
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

fn writeEncodedSizeRepeatedField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, receiver: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
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
    try writer.writeAll(") |item| size += ");
    try writeSingleFieldEncodedSizeExprForValue(field.number, field.kind, "item", writer);
    try writer.writeAll(";\n");
}

fn writeEncodedSizeMapField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, receiver: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    const map_type = field.kind.map;
    try indent(writer, depth);
    try writer.writeAll("{ var map_it = ");
    try writer.writeAll(receiver);
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".iterator(); while (map_it.next()) |entry| {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const key = entry.key_ptr.*; const value = entry.value_ptr.*;\n");
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

fn writeEncodedSizeOneof(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, oneof: schema.OneofDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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
                try writer.writeAll(" => |value| size += ");
                try writeSingleFieldEncodedSizeExprForValue(field.number, field.kind, "value", writer);
                try writer.writeAll(",\n");
            }
        }
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeSingleFieldEncodedSizeExpr(number: u29, kind: schema.FieldKind, receiver: []const u8, field_name: []const u8, writer: *std.Io.Writer) Error!void {
    try writeSingleFieldEncodedSizePrefix(number, kind, writer);
    try writer.writeAll(" + ");
    try writeKindPayloadSizeExprForField(kind, receiver, field_name, writer);
}

fn writeSingleFieldEncodedSizeExprForValue(number: u29, kind: schema.FieldKind, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    try writeSingleFieldEncodedSizePrefix(number, kind, writer);
    try writer.writeAll(" + ");
    try writeKindPayloadSizeExpr(kind, value_expr, writer);
}

fn writeSingleFieldEncodedSizePrefix(number: u29, kind: schema.FieldKind, writer: *std.Io.Writer) Error!void {
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

fn writeKindPayloadSizeExprForField(kind: schema.FieldKind, receiver: []const u8, field_name: []const u8, writer: *std.Io.Writer) Error!void {
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

fn writeScalarPayloadSizeExprForField(scalar: schema.ScalarType, receiver: []const u8, field_name: []const u8, writer: *std.Io.Writer) Error!void {
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
        .bool => try writer.writeAll("1"),
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

fn writeEncodeDeterministic(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn writeDeterministicTo(self: @This(), allocator: std.mem.Allocator, w: *pbz.Writer) !void {\n");
    try writeEncodeFieldsByNumber(ctx, message, writer, depth + 1);
    try writeEncodeUnknownFieldsDeterministic(writer, depth + 1);
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn writeDeterministicToAssumeCapacity(self: @This(), allocator: std.mem.Allocator, w: *pbz.Writer) !void {\n");
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

fn writeEncodeUnknownFields(writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("for (self._unknown_fields) |raw| try w.appendSlice(raw);\n");
}

fn writeEncodeUnknownFieldsDeterministic(writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("if (self._unknown_fields.len != 0) {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const indexes = try allocator.alloc(usize, self._unknown_fields.len);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("defer allocator.free(indexes);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("for (indexes, 0..) |*index, i| index.* = i;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("std.mem.sort(usize, indexes, self._unknown_fields, struct {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("fn firstTag(raw: []const u8) ?pbz.wire.Tag {\n");
    try indent(writer, depth + 3);
    try writer.writeAll("var r = pbz.Reader.init(raw);\n");
    try indent(writer, depth + 3);
    try writer.writeAll("return (r.nextTag() catch null) orelse null;\n");
    try indent(writer, depth + 2);
    try writer.writeAll("}\n");
    try indent(writer, depth + 2);
    try writer.writeAll("fn lessThan(raws: []const []const u8, a: usize, b: usize) bool {\n");
    try indent(writer, depth + 3);
    try writer.writeAll("const tag_a = firstTag(raws[a]);\n");
    try indent(writer, depth + 3);
    try writer.writeAll("const tag_b = firstTag(raws[b]);\n");
    try indent(writer, depth + 3);
    try writer.writeAll("if (tag_a == null or tag_b == null) return std.mem.lessThan(u8, raws[a], raws[b]);\n");
    try indent(writer, depth + 3);
    try writer.writeAll("if (tag_a.?.number != tag_b.?.number) return tag_a.?.number < tag_b.?.number;\n");
    try indent(writer, depth + 3);
    try writer.writeAll("if (tag_a.?.wire_type != tag_b.?.wire_type) return @intFromEnum(tag_a.?.wire_type) < @intFromEnum(tag_b.?.wire_type);\n");
    try indent(writer, depth + 3);
    try writer.writeAll("return std.mem.lessThan(u8, raws[a], raws[b]);\n");
    try indent(writer, depth + 2);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}.lessThan);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("for (indexes) |index| try w.appendSlice(self._unknown_fields[index]);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeEncodeUnknownFieldsDeterministicAssumeCapacity(writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("if (self._unknown_fields.len != 0) {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const indexes = try allocator.alloc(usize, self._unknown_fields.len);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("defer allocator.free(indexes);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("for (indexes, 0..) |*index, i| index.* = i;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("std.mem.sort(usize, indexes, self._unknown_fields, struct {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("fn firstTag(raw: []const u8) ?pbz.wire.Tag {\n");
    try indent(writer, depth + 3);
    try writer.writeAll("var r = pbz.Reader.init(raw);\n");
    try indent(writer, depth + 3);
    try writer.writeAll("return (r.nextTag() catch null) orelse null;\n");
    try indent(writer, depth + 2);
    try writer.writeAll("}\n");
    try indent(writer, depth + 2);
    try writer.writeAll("fn lessThan(raws: []const []const u8, a: usize, b: usize) bool {\n");
    try indent(writer, depth + 3);
    try writer.writeAll("const tag_a = firstTag(raws[a]);\n");
    try indent(writer, depth + 3);
    try writer.writeAll("const tag_b = firstTag(raws[b]);\n");
    try indent(writer, depth + 3);
    try writer.writeAll("if (tag_a == null or tag_b == null) return std.mem.lessThan(u8, raws[a], raws[b]);\n");
    try indent(writer, depth + 3);
    try writer.writeAll("if (tag_a.?.number != tag_b.?.number) return tag_a.?.number < tag_b.?.number;\n");
    try indent(writer, depth + 3);
    try writer.writeAll("if (tag_a.?.wire_type != tag_b.?.wire_type) return @intFromEnum(tag_a.?.wire_type) < @intFromEnum(tag_b.?.wire_type);\n");
    try indent(writer, depth + 3);
    try writer.writeAll("return std.mem.lessThan(u8, raws[a], raws[b]);\n");
    try indent(writer, depth + 2);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}.lessThan);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("for (indexes) |index| w.appendSliceAssumeCapacity(self._unknown_fields[index]);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeEncodeFieldsByNumber(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeEncodeFieldsByNumberAssumeCapacity(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeEncodeOneofSingleField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, oneof_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeEncodeOneofSingleFieldDeterministicAssumeCapacity(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, oneof_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeOneofValueEncodeDeterministic(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
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

fn writeOneofValueEncodeDeterministicAssumeCapacity(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
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

fn writeEncodeInitialized(writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn encodeInitialized(self: @This(), allocator: std.mem.Allocator) ![]u8 {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.validateRequiredRecursive(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try self.encode(allocator);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeOwnedAllocator(writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("fn _pbzOwnedAllocator(self: *@This(), allocator: std.mem.Allocator) !std.mem.Allocator {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (self._json_arena == null) {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("const arena = try allocator.create(std.heap.ArenaAllocator);\n");
    try indent(writer, depth + 2);
    try writer.writeAll("errdefer allocator.destroy(arena);\n");
    try indent(writer, depth + 2);
    try writer.writeAll("arena.* = std.heap.ArenaAllocator.init(allocator);\n");
    try indent(writer, depth + 2);
    try writer.writeAll("self._json_arena = arena;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return self._json_arena.?.allocator();\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeUnknownFieldMethods(writer: *std.Io.Writer, depth: usize) Error!void {
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
    try writer.writeAll("var count: usize = 0;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("for (self._unknown_fields) |raw| {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("var r = pbz.Reader.init(raw);\n");
    try indent(writer, depth + 2);
    try writer.writeAll("if (try r.nextTag()) |tag| {\n");
    try indent(writer, depth + 3);
    try writer.writeAll("if (tag.number == number) count += 1;\n");
    try indent(writer, depth + 2);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return count;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn hasUnknownFieldNumber(self: @This(), number: pbz.FieldNumber) !bool {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return (try self.unknownFieldCountByNumber(number)) != 0;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn unknownFieldsByNumberAlloc(self: @This(), allocator: std.mem.Allocator, number: pbz.FieldNumber) ![]const []const u8 {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var list: std.ArrayList([]const u8) = .empty;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer list.deinit(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("for (self._unknown_fields) |raw| {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("var r = pbz.Reader.init(raw);\n");
    try indent(writer, depth + 2);
    try writer.writeAll("if (try r.nextTag()) |tag| {\n");
    try indent(writer, depth + 3);
    try writer.writeAll("if (tag.number == number) try list.append(allocator, raw);\n");
    try indent(writer, depth + 2);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try list.toOwnedSlice(allocator);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn appendUnknownRaw(self: *@This(), allocator: std.mem.Allocator, raw: []const u8) !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var r = pbz.Reader.init(raw);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const tag = (try r.nextTag()) orelse return error.InvalidWireType;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try r.skipValue(tag);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (!r.eof()) return error.InvalidWireType;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const old = self._unknown_fields;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const next = try allocator.alloc([]const u8, old.len + 1);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer allocator.free(next);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (old.len != 0) @memcpy(next[0..old.len], old);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const owned = try allocator.dupe(u8, raw);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer allocator.free(owned);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("next[old.len] = owned;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("self._unknown_fields = next;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (old.len != 0) allocator.free(old);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn clearUnknownFieldsByNumber(self: *@This(), allocator: std.mem.Allocator, number: pbz.FieldNumber) !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var kept: std.ArrayList([]const u8) = .empty;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer kept.deinit(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("for (self._unknown_fields) |raw| {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("var r = pbz.Reader.init(raw);\n");
    try indent(writer, depth + 2);
    try writer.writeAll("const tag = (try r.nextTag()) orelse { allocator.free(raw); continue; };\n");
    try indent(writer, depth + 2);
    try writer.writeAll("if (tag.number == number) { allocator.free(raw); continue; }\n");
    try indent(writer, depth + 2);
    try writer.writeAll("try kept.append(allocator, raw);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (self._unknown_fields.len != 0) allocator.free(self._unknown_fields);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("self._unknown_fields = try kept.toOwnedSlice(allocator);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn clearUnknownFields(self: *@This(), allocator: std.mem.Allocator) void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("for (self._unknown_fields) |raw| allocator.free(raw);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (self._unknown_fields.len != 0) allocator.free(self._unknown_fields);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("self._unknown_fields = &.{};\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeBorrowedViewMethods(file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writePackedBoolSlicesMethod(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedIdentWithSuffix(field.name, "PackedBoolSlices", writer);
    try writer.writeAll("(header: *[20]u8, values: []const bool) !pbz.wire.BorrowedFieldSlices {\n");
    try indent(writer, depth + 1);
    try writer.print("return try pbz.wire.packedBoolFieldSlices(header, {d}, values);\n", .{field.number});
    try indent(writer, depth);
    try writer.writeAll("}\n\n");
}

fn writePackedVarintIteratorMethod(field: *const schema.FieldDescriptor, iterator_type: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn packedVarintIteratorType(scalar: schema.ScalarType) ?[]const u8 {
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

fn packedVarintIteratorFunction(scalar: schema.ScalarType) ?[]const u8 {
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

fn writeLengthDelimitedBorrowedSlicesMethod(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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
    try writer.print("return try pbz.wire.lengthDelimitedFieldSlices(header, {d}, value);\n", .{field.number});
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

fn fixedWidthViewScalarType(scalar: schema.ScalarType) ?[]const u8 {
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

fn writeMessageExtensionAccessors(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    var wrote_any = false;
    for (file.extensions.items) |*field| {
        if (extensionAppliesToMessage(file, message, field)) {
            try writeMessageExtensionAccessor(ctx, field, writer, depth);
            wrote_any = true;
        }
    }
    for (file.messages.items) |*scope| {
        if (try writeScopedMessageExtensionAccessors(ctx, message, scope, writer, depth)) wrote_any = true;
    }
    if (!wrote_any) {
        try indent(writer, depth);
        try writer.writeAll("// no same-file extension accessors\n");
    }
}

fn writeScopedMessageExtensionAccessors(ctx: *const CodegenContext, target: *const schema.MessageDescriptor, scope: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!bool {
    const file = ctx.file;
    var wrote_any = false;
    for (scope.extensions.items) |*field| {
        if (extensionAppliesToMessage(file, target, field)) {
            try writeMessageExtensionAccessor(ctx, field, writer, depth);
            wrote_any = true;
        }
    }
    for (scope.messages.items) |*nested| {
        if (try writeScopedMessageExtensionAccessors(ctx, target, nested, writer, depth)) wrote_any = true;
    }
    return wrote_any;
}

fn writeMessageExtensionAccessor(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const helper_name = extensionAccessorSuffix(schema.extensionFullName(field));

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

fn writeMessageEnumExtensionAccessor(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, helper_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeMessageExtensionTypedAccessor(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, helper_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeMergeFrom(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn mergeFrom(self: *@This(), allocator: std.mem.Allocator, other: @This()) !void {\n");
    for (message.fields.items) |*field| {
        if (field.oneof_name == null) try writeMergeField(ctx, field, writer, depth + 1);
    }
    for (message.oneofs.items) |oneof| try writeMergeOneof(ctx, message, oneof, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("for (other._unknown_fields) |raw| try self.appendUnknownRaw(allocator, raw);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn mergeUsesAllocator(message: *const schema.MessageDescriptor) bool {
    for (message.fields.items) |field| {
        if (field.oneof_name != null) continue;
        if (field.cardinality == .repeated or field.kind == .map or field.kind == .message or field.kind == .group) return true;
    }
    return false;
}

fn writeMergeField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeMergeRepeatedField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("if (other.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".len != 0) {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const old = self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const merged = try allocator.alloc(");
    if (typedRepeatedMessageFieldWithContext(ctx, field)) |type_name| {
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    } else {
        try writeRepeatedElementType(field.*, writer);
    }
    try writer.writeAll(", old.len + other.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".len);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("@memcpy(merged[0..old.len], old);\n");
    try indent(writer, depth + 1);
    if (typedRepeatedMessageFieldWithContext(ctx, field)) |_| {
        try writer.writeAll("for (other.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(", 0..) |item, i| merged[old.len + i] = try item.cloneOwned(allocator);\n");
    } else {
        try writer.writeAll("@memcpy(merged[old.len..], other.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(");\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = merged;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (old.len != 0) allocator.free(old);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeMergeMapField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("if (other.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".count() != 0) {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var other_it = other.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".iterator();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("while (other_it.next()) |entry| try @This().");
    try writeQuotedIdentWithPrefix(field.name, "putMapEntry_", writer);
    try writer.writeAll("(allocator, &self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(", .{ .key = entry.key_ptr.*, .value = ");
    if (typedMapMessageValueWithContext(ctx, field)) |_| {
        try writer.writeAll("try entry.value_ptr.cloneOwned(allocator)");
    } else {
        try writer.writeAll("entry.value_ptr.*");
    }
    try writer.writeAll(" });\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeMergeSingularMessageField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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
    try writer.writeAll(" = other.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("self.");
    try writePresenceIdent(field.name, writer);
    try writer.writeAll(" = true;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeMergeSingularScalarField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
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
        try writer.writeAll(defaultSkipCondition(scalar));
        try writer.writeAll("self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = other.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(";\n");
    }
}

fn writeMergeSingularEnumField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeMergeOneof(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, oneof: schema.OneofDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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
                try writer.writeAll(" => |value| self.");
                try writeQuotedIdent(oneof.name, writer);
                try writer.writeAll(" = .{ .");
                try writeQuotedIdent(field.name, writer);
                try writer.writeAll(" = ");
                if (typedOneofMessageFieldWithContext(ctx, field)) |_| {
                    try writer.writeAll("try value.cloneOwned(allocator)");
                } else {
                    try writer.writeAll("value");
                }
                try writer.writeAll(" },\n");
            }
        }
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeDeinit(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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
        var wrote_switch = false;
        for (message.fields.items) |*field| {
            if (field.oneof_name) |name| {
                if (std.mem.eql(u8, name, oneof.name) and typedOneofMessageFieldWithContext(ctx, field) != null) {
                    if (!wrote_switch) {
                        try indent(writer, depth + 1);
                        try writer.writeAll("switch (self.");
                        try writeQuotedIdent(oneof.name, writer);
                        try writer.writeAll(") {\n");
                        wrote_switch = true;
                    }
                    try indent(writer, depth + 2);
                    try writer.writeAll(".");
                    try writeQuotedIdent(field.name, writer);
                    try writer.writeAll(" => |*value| value.deinit(allocator),\n");
                }
            }
        }
        if (wrote_switch) {
            try indent(writer, depth + 2);
            try writer.writeAll("else => {},\n");
            try indent(writer, depth + 1);
            try writer.writeAll("}\n");
        }
    }
    try indent(writer, depth + 1);
    try writer.writeAll("for (self._unknown_fields) |raw| allocator.free(raw);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("allocator.free(self._unknown_fields);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (self._json_arena) |arena| { const child_allocator = arena.child_allocator; arena.deinit(); child_allocator.destroy(arena); }\n");
    try indent(writer, depth + 1);
    try writer.writeAll("self.* = undefined;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeCloneOwned(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn cloneOwned(self: @This(), allocator: std.mem.Allocator) !@This() {\n");
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

fn cloneUsesOwnedAllocator(ctx: *const CodegenContext, message: *const schema.MessageDescriptor) bool {
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

fn cloneFieldUsesOwnedAllocator(ctx: *const CodegenContext, field: *const schema.FieldDescriptor) bool {
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

fn cloneKindUsesOwnedAllocator(kind: schema.FieldKind) bool {
    return switch (kind) {
        .scalar => |scalar| scalar == .string or scalar == .bytes,
        .message, .group => true,
        else => false,
    };
}

fn writeCloneField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeCloneRepeatedField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeCloneMapField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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
    try writer.writeAll("while (map_it.next()) |entry| try @This().");
    try writeQuotedIdentWithPrefix(field.name, "putMapEntry_", writer);
    try writer.writeAll("(allocator, &out.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(", .{ .key = ");
    try writeCloneValueExpr(.{ .scalar = map_type.key }, "entry.key_ptr.*", writer);
    try writer.writeAll(", .value = ");
    if (typedMapMessageValueWithContext(ctx, field)) |_| {
        try writer.writeAll("try entry.value_ptr.cloneOwned(allocator)");
    } else {
        try writeCloneValueExpr(map_type.value.*, "entry.value_ptr.*", writer);
    }
    try writer.writeAll(" });\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeCloneOneof(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, oneof: schema.OneofDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeCloneUnknownFields(writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("if (self._unknown_fields.len != 0) {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const cloned_unknowns = try allocator.alloc([]const u8, self._unknown_fields.len);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("for (self._unknown_fields, 0..) |raw, i| cloned_unknowns[i] = try allocator.dupe(u8, raw);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("out._unknown_fields = cloned_unknowns;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeCloneFieldValueExpr(kind: schema.FieldKind, field_name: []const u8, writer: *std.Io.Writer) Error!void {
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

fn writeCloneValueExpr(kind: schema.FieldKind, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    switch (kind) {
        .scalar => |scalar| switch (scalar) {
            .string, .bytes => try writer.print("try owned_allocator.dupe(u8, {s})", .{value_expr}),
            else => try writer.writeAll(value_expr),
        },
        .message, .group => try writer.print("try owned_allocator.dupe(u8, {s})", .{value_expr}),
        .enumeration => try writer.writeAll(value_expr),
        .map => try writer.writeAll(value_expr),
    }
}

fn writeMissingRequiredFieldName(message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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
        try writer.writeAll("_ = self;\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("return null;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeMissingRequiredFieldPath(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn missingRequiredFieldPath(self: @This(), allocator: std.mem.Allocator) !?[]u8 {\n");
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
        try writer.writeAll("_ = self; _ = allocator;\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("return null;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeMissingRequiredPathExtensionPayloads(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!bool {
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

fn writeMissingRequiredPathScopedExtensionPayloads(ctx: *const CodegenContext, target: *const schema.MessageDescriptor, scope: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!bool {
    var wrote_any = false;
    for (scope.extensions.items) |*field| {
        if (try writeMissingRequiredPathExtensionPayload(ctx, target, field, writer, depth)) wrote_any = true;
    }
    for (scope.messages.items) |*nested| {
        if (try writeMissingRequiredPathScopedExtensionPayloads(ctx, target, nested, writer, depth)) wrote_any = true;
    }
    return wrote_any;
}

fn writeMissingRequiredPathExtensionPayload(ctx: *const CodegenContext, target: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!bool {
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

fn writeMissingRequiredPathField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!bool {
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
            try writer.writeAll(") |nested| {\n");
            try indent(writer, depth + 1);
            try writer.writeAll("if (try nested.missingRequiredFieldPath(allocator)) |suffix| { defer allocator.free(suffix); return try std.fmt.allocPrint(allocator, \"");
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
            try writer.writeAll(") |nested| {\n");
            try indent(writer, depth + 1);
            try writer.writeAll("if (try nested.missingRequiredFieldPath(allocator)) |suffix| { defer allocator.free(suffix); return try std.fmt.allocPrint(allocator, \"");
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

fn writeMissingRequiredPathMapField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!bool {
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

fn writeMissingRequiredPathOneof(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, oneof: schema.OneofDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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
                    try writer.writeAll("nested| {\n");
                    try indent(writer, depth + 2);
                    try writer.writeAll("if (try nested.missingRequiredFieldPath(allocator)) |suffix| { defer allocator.free(suffix); return try std.fmt.allocPrint(allocator, \"");
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

fn writeMissingRequiredPathPayload(ctx: *const CodegenContext, type_name: []const u8, field_name: []const u8, payload_expr: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("var nested = try ");
    try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    try writer.writeAll(".decode(allocator, ");
    try writer.writeAll(payload_expr);
    if (std.mem.eql(u8, payload_expr, "self.")) try writeQuotedIdent(field_name, writer);
    try writer.writeAll(");\n");
    try indent(writer, depth);
    try writer.writeAll("defer nested.deinit(allocator);\n");
    try indent(writer, depth);
    try writer.writeAll("if (try nested.missingRequiredFieldPath(allocator)) |suffix| {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("defer allocator.free(suffix);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try std.fmt.allocPrint(allocator, \"");
    try writeEscapedStringContents(field_name, writer);
    try writer.writeAll(".{s}\", .{suffix});\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeValidateRequired(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn validateRequired(self: @This()) !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (self.missingRequiredFieldName() != null) return error.MissingRequiredField;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try writer.writeAll("\n");
    try indent(writer, depth);
    try writer.writeAll("pub fn validateRequiredRecursive(self: @This(), allocator: std.mem.Allocator) !void {\n");
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
        try writer.writeAll("_ = allocator;\n");
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeValidateMessageExtensionPayloads(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!bool {
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

fn writeValidateScopedMessageExtensionPayloads(ctx: *const CodegenContext, target: *const schema.MessageDescriptor, scope: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!bool {
    var wrote_any = false;
    for (scope.extensions.items) |*field| {
        if (try writeValidateMessageExtensionPayload(ctx, target, field, writer, depth)) wrote_any = true;
    }
    for (scope.messages.items) |*nested| {
        if (try writeValidateScopedMessageExtensionPayloads(ctx, target, nested, writer, depth)) wrote_any = true;
    }
    return wrote_any;
}

fn writeValidateMessageExtensionPayload(ctx: *const CodegenContext, target: *const schema.MessageDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!bool {
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

fn writeValidateMessagePayloadField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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
            try writer.writeAll(") |nested| try nested.validateRequiredRecursive(allocator);\n");
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
            try writer.writeAll(") |nested| try nested.validateRequiredRecursive(allocator);\n");
            return;
        }
        try indent(writer, depth);
        try writer.writeAll("if (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(".len != 0) {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("var nested = try ");
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
        try writer.writeAll(".decode(allocator, self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(");\n");
        try indent(writer, depth + 1);
        try writer.writeAll("defer nested.deinit(allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try nested.validateRequiredRecursive(allocator);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");
    }
}

fn writeValidateMapMessagePayloadField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn fieldHasMessageMapValue(field: *const schema.FieldDescriptor) bool {
    const map_type = switch (field.kind) {
        .map => |map_type| map_type,
        else => return false,
    };
    return map_type.value.* == .message;
}

fn writeValidateMessagePayloadOneof(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, oneof: schema.OneofDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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
                    try writer.writeAll("nested| try nested.validateRequiredRecursive(allocator),\n");
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

fn writeDecodeAndValidatePayload(ctx: *const CodegenContext, type_name: []const u8, payload_expr: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("var nested = try ");
    try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    try writer.writeAll(".decode(allocator, ");
    try writer.writeAll(payload_expr);
    try writer.writeAll(");\n");
    try indent(writer, depth);
    try writer.writeAll("defer nested.deinit(allocator);\n");
    try indent(writer, depth);
    try writer.writeAll("try nested.validateRequiredRecursive(allocator);\n");
}

fn oneofHasMessageField(message: *const schema.MessageDescriptor, oneof_name: []const u8) bool {
    for (message.fields.items) |*field| {
        if (field.oneof_name) |name| {
            if (std.mem.eql(u8, name, oneof_name) and (field.kind == .message or field.kind == .group)) return true;
        }
    }
    return false;
}

fn codegenCanReferenceMessage(file: *const schema.FileDescriptor, type_name: []const u8) bool {
    return resolveSameFileMessageReference(file, type_name) != null;
}

fn writeMessageTypeReference(type_name: []const u8, writer: *std.Io.Writer) Error!void {
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

fn codegenCanReferenceMessageWithContext(ctx: *const CodegenContext, type_name: []const u8) bool {
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

fn writeMessageTypeReferenceWithContext(ctx: *const CodegenContext, type_name: []const u8, writer: *std.Io.Writer) Error!void {
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

fn writeEnumTypeReferenceWithContext(ctx: *const CodegenContext, type_name: []const u8, writer: *std.Io.Writer) Error!void {
    const reference = resolveEnumReference(ctx, type_name) orelse {
        return try writeMessageTypeReference(type_name, writer);
    };
    if (!(try writeEnumPathInFile(reference.file, reference.enumeration, writer))) try writeMessageTypeReference(type_name, writer);
}

fn resolveMessageReference(ctx: *const CodegenContext, type_name: []const u8) ?MessageReference {
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

fn sameFileForCodegen(a: *const schema.FileDescriptor, b: *const schema.FileDescriptor) bool {
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

fn writeDecode(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (messageCanFastRawTagDecode(ctx.file, message)) return try writeDecodeFastRawTag(ctx, message, writer, depth);

    try indent(writer, depth);
    try writer.writeAll("pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) !@This() {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var r = pbz.Reader.init(bytes);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try @This().decodeFromReader(allocator, &r);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn decodeFromReader(allocator: std.mem.Allocator, r: *pbz.Reader) !@This() {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var self = @This().init();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer self.deinit(allocator);\n");
    for (message.fields.items) |*field| try writeRepeatedListDeclForDecode(ctx, field, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("var _unknown_fields_list: std.ArrayList([]const u8) = .empty;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer { for (_unknown_fields_list.items) |raw| allocator.free(raw); _unknown_fields_list.deinit(allocator); }\n");
    try indent(writer, depth + 1);
    try writer.writeAll("while (try r.nextTag()) |tag| {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("switch (tag.number) {\n");
    for (message.fields.items) |*field| try writeDecodeField(ctx, field, writer, depth + 3);
    try indent(writer, depth + 3);
    try writer.writeAll("else => { const start = r.position() - pbz.wire.encodedVarintSize(try tag.encode()); try r.skipValue(tag); const raw = try allocator.dupe(u8, r.input[start..r.position()]); errdefer allocator.free(raw); try _unknown_fields_list.append(allocator, raw); },\n");
    try indent(writer, depth + 2);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    for (message.fields.items) |*field| try writeRepeatedAssignForDecode(field, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("self._unknown_fields = if (_unknown_fields_list.items.len == 0) &.{} else try _unknown_fields_list.toOwnedSlice(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return self;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn messageCanFastRawTagDecode(file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor) bool {
    if (message.oneofs.items.len != 0) return false;
    var has_length_delimited_scalar = false;
    for (message.fields.items) |field| {
        switch (field.kind) {
            .scalar => |scalar| switch (scalar) {
                .string, .bytes => has_length_delimited_scalar = true,
                else => {},
            },
            .enumeration => |name| if (enumIsClosed(file, name)) return false,
            .message, .group, .map => return false,
        }
    }
    return has_length_delimited_scalar or message.fields.items.len >= 8;
}

fn writeDecodeFastRawTag(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) !@This() {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var r = pbz.Reader.init(bytes);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try @This().decodeFromReader(allocator, &r);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn decodeFromReader(allocator: std.mem.Allocator, r: *pbz.Reader) !@This() {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var self = @This().init();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer self.deinit(allocator);\n");
    for (message.fields.items) |*field| try writeRepeatedListDeclForDecode(ctx, field, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("var _unknown_fields_list: std.ArrayList([]const u8) = .empty;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer { for (_unknown_fields_list.items) |raw| allocator.free(raw); _unknown_fields_list.deinit(allocator); }\n");
    try writeRawTagDecodeLoop(ctx, message, writer, depth + 1);
    for (message.fields.items) |*field| try writeRepeatedAssignForDecode(field, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("self._unknown_fields = if (_unknown_fields_list.items.len == 0) &.{} else try _unknown_fields_list.toOwnedSlice(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return self;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeRawTagDecodeLoop(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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
    try writer.writeAll("else => { const tag = try pbz.wire.Tag.decode(raw_tag); try r.skipValue(tag); const raw = try allocator.dupe(u8, r.input[raw_tag_start..r.position()]); errdefer allocator.free(raw); try _unknown_fields_list.append(allocator, raw); },\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeRawTagDecodeFieldCases(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeRawTagDecodeSingularScalarCase(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeRawTagDecodeUnpackedScalarCase(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeRawTagDecodePackedScalarCase(field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.print("{d} => {{\n", .{rawTagValue(field.number, .length_delimited)});
    try writeDecodePackedScalarPayload(field, scalar, writer, depth + 1);
    try indent(writer, depth);
    try writer.writeAll("},\n");
}

fn writeRawTagDecodeSingularEnumCase(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.print("{d} => {{ const value = try r.readInt32(); self.", .{rawTagValue(field.number, .varint)});
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = value;");
    try writeSetPresence(file, field, writer);
    try writer.writeAll(" },\n");
}

fn writeRawTagDecodeUnpackedEnumCase(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.print("{d} => ", .{rawTagValue(field.number, .varint)});
    try writeRepeatedAppendPrefix(field, writer);
    try writer.writeAll("try r.readInt32()),\n");
}

fn writeRawTagDecodePackedEnumCase(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.print("{d} => {{\n", .{rawTagValue(field.number, .length_delimited)});
    try indent(writer, depth + 1);
    try writer.writeAll("const payload = try r.readBytes();\n");
    if (field.kind == .enumeration and !enumIsClosed(file, field.kind.enumeration)) {
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

fn rawFieldTag(number: u29, kind: schema.FieldKind) u64 {
    return rawTagValue(number, kind.wireType());
}

fn rawTagValue(number: u29, wire_type: wire.WireType) u64 {
    return (@as(u64, number) << 3) | @intFromEnum(wire_type);
}

fn messageCanDecodeReuseFast(ctx: *const CodegenContext, message: *const schema.MessageDescriptor) bool {
    for (message.fields.items) |field| {
        switch (field.kind) {
            .scalar => {},
            .enumeration => {},
            .map => {},
            .message, .group => |name| {
                if (!codegenCanReferenceMessageWithContext(ctx, name) and field.cardinality != .repeated and field.oneof_name == null) {}
            },
        }
    }
    return true;
}

fn messageCanDecodeKnownReuse(file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor) bool {
    if (message.oneofs.items.len != 0) return false;
    var has_repeated = false;
    for (message.fields.items) |field| {
        if (field.cardinality == .repeated) {
            has_repeated = true;
            switch (field.kind) {
                .scalar => |scalar| if (knownReuseRepeatedScalarSupported(scalar) == false) return false,
                .enumeration => |name| if (enumIsClosed(file, name)) return false,
                else => return false,
            }
            continue;
        }
        switch (field.kind) {
            .scalar => {},
            .enumeration => |name| if (enumIsClosed(file, name)) return false,
            .message, .group, .map => return false,
        }
    }
    return has_repeated;
}

fn knownReuseRepeatedScalarSupported(scalar: schema.ScalarType) bool {
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

fn writeDecodeReuse(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn decodeReuse(self: *@This(), allocator: std.mem.Allocator, bytes: []const u8) !void {\n");
    for (message.fields.items) |*field| try writeRepeatedReuseListDecl(ctx, field, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("for (self._unknown_fields) |raw| allocator.free(raw);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (self._unknown_fields.len != 0) allocator.free(self._unknown_fields);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("self._unknown_fields = &.{};\n");
    for (message.fields.items) |*field| try writeDecodeReuseClearMap(ctx, field, writer, depth + 1);
    for (message.oneofs.items) |oneof| try writeDecodeReuseClearOneof(ctx, message, oneof, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("if (self._json_arena) |arena| { const child_allocator = arena.child_allocator; arena.deinit(); child_allocator.destroy(arena); self._json_arena = null; }\n");
    for (message.fields.items) |*field| try writeDecodeReuseResetField(ctx, field, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer self.deinit(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var _unknown_fields_list: std.ArrayList([]const u8) = .empty;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer { for (_unknown_fields_list.items) |raw| allocator.free(raw); _unknown_fields_list.deinit(allocator); }\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var r = pbz.Reader.init(bytes);\n");
    if (messageCanFastRawTagDecode(ctx.file, message)) {
        try writeRawTagDecodeLoop(ctx, message, writer, depth + 1);
    } else {
        try indent(writer, depth + 1);
        try writer.writeAll("while (try r.nextTag()) |tag| {\n");
        try indent(writer, depth + 2);
        try writer.writeAll("switch (tag.number) {\n");
        for (message.fields.items) |*field| try writeDecodeField(ctx, field, writer, depth + 3);
        try indent(writer, depth + 3);
        try writer.writeAll("else => { const start = r.position() - pbz.wire.encodedVarintSize(try tag.encode()); try r.skipValue(tag); const raw = try allocator.dupe(u8, r.input[start..r.position()]); errdefer allocator.free(raw); try _unknown_fields_list.append(allocator, raw); },\n");
        try indent(writer, depth + 2);
        try writer.writeAll("}\n");
        try indent(writer, depth + 1);
        try writer.writeAll("}\n");
    }
    for (message.fields.items) |*field| try writeRepeatedAssignForDecode(field, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("self._unknown_fields = if (_unknown_fields_list.items.len == 0) &.{} else try _unknown_fields_list.toOwnedSlice(allocator);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeDecodeKnownReuse(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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
    try writer.writeAll("for (self._unknown_fields) |raw| allocator.free(raw);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (self._unknown_fields.len != 0) allocator.free(self._unknown_fields);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("self._unknown_fields = &.{};\n");
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
            .scalar => |scalar| try writeRawTagDecodeSingularScalarCase(ctx.file, field, scalar, writer, depth + 3),
            .enumeration => try writeRawTagDecodeSingularEnumCase(ctx.file, field, writer, depth + 3),
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

fn writeKnownReuseRepeatedScalarCases(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeKnownReuseRepeatedEnumCases(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeKnownReuseRepeatedScalarPayload(field: *const schema.FieldDescriptor, scalar: schema.ScalarType, payload_expr: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    if (scalar == .bool) {
        try indent(writer, depth);
        try writer.print("for ({s}) |byte| {{\n", .{payload_expr});
        try indent(writer, depth + 1);
        try writeQuotedIdentWithSuffix(field.name, "_buffer", writer);
        try writer.writeAll("[");
        try writeQuotedIdentWithSuffix(field.name, "_len", writer);
        try writer.writeAll("] = byte != 0;\n");
        try indent(writer, depth + 1);
        try writeQuotedIdentWithSuffix(field.name, "_len", writer);
        try writer.writeAll(" += 1;\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");
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
        try writer.print("@memcpy(std.mem.sliceAsBytes(out), {s});\n", .{payload_expr});
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

fn writeKnownReuseRepeatedScalarDecodeExpr(scalar: schema.ScalarType, payload_expr: []const u8, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .uint64 => try writer.print("try pbz.wire.readVarintAt({s}, &payload_index)", .{payload_expr}),
        .uint32 => try writer.print("@as(u32, @truncate(try pbz.wire.readVarintAt({s}, &payload_index)))", .{payload_expr}),
        .int32 => try writer.print("@truncate(@as(i64, @bitCast(try pbz.wire.readVarintAt({s}, &payload_index))))", .{payload_expr}),
        .int64 => try writer.print("@bitCast(try pbz.wire.readVarintAt({s}, &payload_index))", .{payload_expr}),
        .sint32 => try writer.print("pbz.wire.zigZagDecode32(@as(u32, @truncate(try pbz.wire.readVarintAt({s}, &payload_index))))", .{payload_expr}),
        .sint64 => try writer.print("pbz.wire.zigZagDecode64(try pbz.wire.readVarintAt({s}, &payload_index))", .{payload_expr}),
        else => try writer.writeAll("@compileError(\"unsupported known reuse scalar\")"),
    }
}

fn fixedWidthPackedScalarSizeForCodegen(scalar: schema.ScalarType) ?usize {
    return switch (scalar) {
        .fixed32, .sfixed32, .float => 4,
        .fixed64, .sfixed64, .double => 8,
        else => null,
    };
}

fn writeKnownReuseFixedWidthScalarDecodeExpr(scalar: schema.ScalarType, payload_expr: []const u8, index_expr: []const u8, width: usize, writer: *std.Io.Writer) Error!void {
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

fn writeRepeatedReuseListDecl(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeDecodeReuseResetField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeDecodeReuseClearMap(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeDecodeReuseClearOneof(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, oneof: schema.OneofDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    var has_typed_message = false;
    for (message.fields.items) |*field| {
        const name = field.oneof_name orelse continue;
        if (!std.mem.eql(u8, name, oneof.name)) continue;
        if (typedOneofMessageFieldWithContext(ctx, field) != null) {
            has_typed_message = true;
            break;
        }
    }
    if (has_typed_message) {
        try indent(writer, depth);
        try writer.writeAll("switch (self.");
        try writeQuotedIdent(oneof.name, writer);
        try writer.writeAll(") {\n");
        for (message.fields.items) |*field| {
            const name = field.oneof_name orelse continue;
            if (!std.mem.eql(u8, name, oneof.name)) continue;
            if (typedOneofMessageFieldWithContext(ctx, field) == null) continue;
            try indent(writer, depth + 1);
            try writer.writeAll(".");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(" => |*value| value.deinit(allocator),\n");
        }
        try indent(writer, depth + 1);
        try writer.writeAll("else => {},\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");
    }
    try indent(writer, depth);
    try writer.writeAll("self.");
    try writeQuotedIdent(oneof.name, writer);
    try writer.writeAll(" = .none;\n");
}

fn messageHasRepeatedOrMap(message: *const schema.MessageDescriptor) bool {
    for (message.fields.items) |field| {
        if (field.cardinality == .repeated or field.kind == .map) return true;
    }
    return false;
}

fn messageDecodeUsesAllocator(message: *const schema.MessageDescriptor) bool {
    if (messageHasRepeatedOrMap(message)) return true;
    for (message.fields.items) |field| {
        if (field.oneof_name == null and field.cardinality != .repeated and (field.kind == .message or field.kind == .group)) return true;
    }
    return false;
}

fn writeDecodeInitialized(writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn decodeOwned(allocator: std.mem.Allocator, bytes: []const u8) !@This() {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var decoded = try @This().decode(allocator, bytes);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("defer decoded.deinit(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try decoded.cloneOwned(allocator);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

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

fn writeRepeatedListDecl(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeRepeatedListDeclForDecode(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.kind == .map) return;
    try writeRepeatedListDecl(ctx, field, writer, depth);
}

fn writeRepeatedAssign(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeRepeatedAssignForDecode(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.kind == .map) return;
    try writeRepeatedAssign(field, writer, depth);
}

fn writeMapAssign(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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
    try writer.writeAll(".items) |entry| try @This().");
    try writeQuotedIdentWithPrefix(field.name, "putMapEntry_", writer);
    try writer.writeAll("(allocator, &self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(", entry);\n");
}

fn writeRepeatedElementType(field: schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    switch (field.kind) {
        .scalar => |scalar| try writer.writeAll(scalarZigType(scalar)),
        .enumeration => try writer.writeAll("i32"),
        .message, .group => try writer.writeAll("[]const u8"),
        .map => try writeQuotedIdentWithSuffix(field.name, "Entry", writer),
    }
}

fn writeDecodeField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    switch (field.kind) {
        .scalar => |scalar| try writeDecodeScalarField(file, field, scalar, writer, depth),
        .enumeration => try writeDecodeEnumField(file, field, writer, depth),
        .message, .group => try writeDecodeMessageField(ctx, field, writer, depth),
        .map => try writeDecodeMapField(ctx, field, writer, depth),
    }
}

fn writeDecodeScalarField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeDecodeEnumField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.print("{d} => ", .{field.number});
    if (field.cardinality == .repeated) {
        try writeDecodePackedEnumField(file, field, writer, depth);
    } else if (field.oneof_name != null) {
        try writeOneofEnumDecodeAssign(file, field, writer);
    } else if (field.kind == .enumeration and enumIsClosed(file, field.kind.enumeration)) {
        try writer.writeAll("{ const value = try r.readInt32(); if (!@This().enumKnown(value, ");
        try writeEnumNumberArray(file, field.kind.enumeration, writer);
        try writer.writeAll(")) { const start = r.position() - pbz.wire.encodedVarintSize(try tag.encode()); const raw = try allocator.dupe(u8, r.input[start..r.position()]); errdefer allocator.free(raw); try _unknown_fields_list.append(allocator, raw); } else { self.");
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

fn writeDecodeMessageField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    try indent(writer, depth);
    try writer.print("{d} => ", .{field.number});
    if (field.cardinality == .repeated) {
        if (typedRepeatedMessageFieldWithContext(ctx, field)) |type_name| {
            try writer.writeAll("{ const payload = ");
            try writeMessagePayloadRead(file, field, "r", writer);
            try writer.writeAll("; var payload_reader = try r.nested(payload); var nested = try ");
            try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
            try writer.writeAll(".decodeFromReader(allocator, &payload_reader); errdefer nested.deinit(allocator); try ");
            try writeQuotedIdentWithSuffix(field.name, "_list", writer);
            try writer.writeAll(".append(allocator, nested); },\n");
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
        try writer.writeAll("; var payload_reader = try r.nested(payload); var nested = try ");
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
        try writer.writeAll(".decodeFromReader(allocator, &payload_reader); errdefer nested.deinit(allocator); if (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(") |*existing| { try existing.mergeFrom(allocator, nested); nested.deinit(allocator); } else { self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = nested; } },\n");
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

fn writeDecodePackedScalarField(field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeDecodePackedScalarPayload(field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn packedScalarAppendHelperName(scalar: schema.ScalarType) ?[]const u8 {
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

fn writePackedScalarDecodeCapacityExpr(scalar: schema.ScalarType, payload_expr: []const u8, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .double, .fixed64, .sfixed64 => try writer.print("{s}.len / 8", .{payload_expr}),
        .float, .fixed32, .sfixed32 => try writer.print("{s}.len / 4", .{payload_expr}),
        .int32, .int64, .uint32, .uint64, .sint32, .sint64, .bool => try writer.print("{s}.len", .{payload_expr}),
        .string, .bytes => try writer.writeAll("@compileError(\"non-packable scalar\")"),
    }
}

fn writeDecodePackedEnumField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try writer.writeAll("{\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (tag.wire_type == .length_delimited) {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("const payload = try r.readBytes();\n");
    if (field.kind == .enumeration and !enumIsClosed(file, field.kind.enumeration)) {
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
        try writeEnumNumberArray(file, field.kind.enumeration, writer);
        try writer.writeAll(")) { var unknown_writer = pbz.Writer.init(allocator); defer unknown_writer.deinit(); try unknown_writer.writeTag(");
        try writer.print("{d}", .{field.number});
        try writer.writeAll(", .varint); try unknown_writer.appendSlice(payload[value_start..value_end]); const raw = try allocator.dupe(u8, unknown_writer.slice()); errdefer allocator.free(raw); try _unknown_fields_list.append(allocator, raw); continue; }");
        try writer.writeAll(" try ");
        try writeQuotedIdentWithSuffix(field.name, "_list", writer);
        try writer.writeAll(".append(allocator, value); }\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("} else {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("{ const value = try r.readInt32();");
    if (field.kind == .enumeration and enumIsClosed(file, field.kind.enumeration)) {
        try writer.writeAll(" if (!@This().enumKnown(value, ");
        try writeEnumNumberArray(file, field.kind.enumeration, writer);
        try writer.writeAll(")) { const start = r.position() - pbz.wire.encodedVarintSize(try tag.encode()); const raw = try allocator.dupe(u8, r.input[start..r.position()]); errdefer allocator.free(raw); try _unknown_fields_list.append(allocator, raw); } else { try ");
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

fn writeDecodeMapField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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
    try indent(writer, depth + 1);
    try writer.writeAll(if (wireMapEntryCanSkip(file, map_type)) "var skip_entry = false;\n" else "const skip_entry = false;\n");
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
    try writer.writeAll("if (skip_entry) { var unknown_writer = pbz.Writer.init(allocator); defer unknown_writer.deinit(); try unknown_writer.writeBytes(");
    try writer.print("{d}", .{field.number});
    try writer.writeAll(", payload); const raw = try allocator.dupe(u8, unknown_writer.slice()); errdefer allocator.free(raw); try _unknown_fields_list.append(allocator, raw); } else try @This().");
    try writeQuotedIdentWithPrefix(field.name, "putMapEntry_", writer);
    try writer.writeAll("(allocator, &self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(", entry);\n");
    try indent(writer, depth);
    try writer.writeAll("},\n");
}

fn wireMapEntryCanSkip(file: *const schema.FileDescriptor, map_type: schema.MapType) bool {
    return map_type.value.* == .enumeration and enumIsClosed(file, map_type.value.enumeration);
}

fn writeMapEntryDecodeAssign(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, target: []const u8, number: u29, kind: schema.FieldKind, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    try indent(writer, depth);
    if (kind == .scalar and kind.scalar == .string and fieldUtf8Validation(file, field) == .verify) {
        try writer.print("{d} => {{ const value = ", .{number});
        try writeEntryReadExpr(kind, "entry_reader", writer);
        try writer.writeAll("; if (!pbz.validateUtf8(value)) return error.InvalidUtf8; ");
        try writer.writeAll(target);
        try writer.writeAll(" = value; },\n");
    } else if (kind == .enumeration and enumIsClosed(file, kind.enumeration)) {
        try writer.print("{d} => {{ const value = ", .{number});
        try writeEntryReadExpr(kind, "entry_reader", writer);
        try writer.writeAll("; if (!@This().enumKnown(value, ");
        try writeEnumNumberArray(file, kind.enumeration, writer);
        try writer.writeAll(")) { skip_entry = true; } else { ");
        try writer.writeAll(target);
        try writer.writeAll(" = value; } },\n");
    } else {
        try writer.print("{d} => ", .{number});
        if (number == 2) {
            if (typedMapMessageValueWithContext(ctx, field)) |type_name| {
                try writer.writeAll("{ const value_payload = try entry_reader.readBytes(); var value_reader = try entry_reader.nested(value_payload); ");
                try writer.writeAll(target);
                try writer.writeAll(".deinit(allocator); ");
                try writer.writeAll(target);
                try writer.writeAll(" = try ");
                try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
                try writer.writeAll(".decodeFromReader(allocator, &value_reader); },\n");
                return;
            }
        }
        try writer.writeAll(target);
        try writer.writeAll(" = ");
        try writeEntryReadExpr(kind, "entry_reader", writer);
        try writer.writeAll(",\n");
    }
}

fn writeOneofDecodeAssign(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, reader_method: []const u8, writer: *std.Io.Writer) Error!void {
    const oneof_name = field.oneof_name orelse return;
    if (field.kind == .scalar and field.kind.scalar == .string and fieldUtf8Validation(file, field) == .verify) {
        try writer.writeAll("{ const value = try r.");
        try writer.writeAll(reader_method);
        try writer.writeAll("(); if (!pbz.validateUtf8(value)) return error.InvalidUtf8; self.");
        try writeQuotedIdent(oneof_name, writer);
        try writer.writeAll(" = .{ .");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = value }; },\n");
        return;
    }
    try writer.writeAll("self.");
    try writeQuotedIdent(oneof_name, writer);
    try writer.writeAll(" = .{ .");
    try writeQuotedIdent(field.name, writer);
    try writer.print(" = try r.{s}() }},\n", .{reader_method});
}

fn writeOneofMessageDecodeAssign(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    const file = ctx.file;
    const oneof_name = field.oneof_name orelse return;
    if (typedOneofMessageFieldWithContext(ctx, field)) |type_name| {
        try writer.writeAll("{ const payload = ");
        try writeMessagePayloadRead(file, field, "r", writer);
        try writer.writeAll("; var payload_reader = try r.nested(payload); self.");
        try writeQuotedIdent(oneof_name, writer);
        try writer.writeAll(" = .{ .");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = try ");
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
        try writer.writeAll(".decodeFromReader(allocator, &payload_reader) }; },\n");
        return;
    }
    try writer.writeAll("self.");
    try writeQuotedIdent(oneof_name, writer);
    try writer.writeAll(" = .{ .");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = ");
    try writeMessagePayloadRead(file, field, "r", writer);
    try writer.writeAll(" },\n");
}

fn writeOneofEnumDecodeAssign(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    const oneof_name = field.oneof_name orelse return;
    try writer.writeAll("{ const value = try r.readInt32();");
    if (field.kind == .enumeration and enumIsClosed(file, field.kind.enumeration)) {
        try writer.writeAll(" if (!@This().enumKnown(value, ");
        try writeEnumNumberArray(file, field.kind.enumeration, writer);
        try writer.writeAll(")) { const start = r.position() - pbz.wire.encodedVarintSize(try tag.encode()); const raw = try allocator.dupe(u8, r.input[start..r.position()]); errdefer allocator.free(raw); try _unknown_fields_list.append(allocator, raw); } else {");
    } else {
        try writeEnumClosedCheck(file, field, "value", writer);
    }
    try writer.writeAll(" self.");
    try writeQuotedIdent(oneof_name, writer);
    try writer.writeAll(" = .{ .");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(" = value };");
    if (field.kind == .enumeration and enumIsClosed(file, field.kind.enumeration)) try writer.writeAll(" }");
    try writer.writeAll(" },\n");
}

fn writeEnumClosedCheck(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    const enum_name = switch (field.kind) {
        .enumeration => |name| name,
        else => return,
    };
    try writeEnumClosedCheckByName(file, enum_name, value_expr, writer);
}

fn writeEnumClosedCheckByName(file: *const schema.FileDescriptor, enum_name: []const u8, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    if (!enumIsClosed(file, enum_name)) return;
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

fn writeEncodeField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    switch (field.kind) {
        .scalar => |scalar| try writeEncodeScalarField(file, field, scalar, writer, depth),
        .enumeration => try writeEncodeEnumField(file, field, writer, depth),
        .message => try writeEncodeMessageField(ctx, field, writer, depth),
        .group => try writeEncodeGroupField(ctx, field, writer, depth),
        .map => try writeEncodeMapField(ctx, field, writer, depth),
    }
}

fn writeEncodeFieldAssumeCapacity(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    switch (field.kind) {
        .scalar => |scalar| try writeEncodeScalarFieldAssumeCapacity(file, field, scalar, writer, depth),
        .enumeration => try writeEncodeEnumFieldAssumeCapacity(file, field, writer, depth),
        .message => try writeEncodeMessageFieldAssumeCapacity(ctx, field, writer, depth),
        .group => try writeEncodeGroupFieldAssumeCapacity(ctx, field, writer, depth),
        .map => try writeEncodeMapFieldAssumeCapacity(ctx, field, writer, depth),
    }
}

fn writeEncodeFieldDeterministic(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeEncodeFieldDeterministicAssumeCapacity(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeEncodeScalarField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
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
            try writer.writeAll("if (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(defaultSkipCondition(scalar));
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

fn writeEncodeScalarFieldAssumeCapacity(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
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
            try writer.writeAll("if (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(defaultSkipCondition(scalar));
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

fn writeEncodeEnumFieldAssumeCapacity(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeEncodePackedScalarField(field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeEncodePackedEnumField(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeEncodePackedScalarFieldAssumeCapacity(field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeEncodePackedEnumFieldAssumeCapacity(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeEncodePackedPrefix(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("if (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".len != 0) {\n");
}

fn writeEncodePackedLength(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth + 1);
    try writer.print("try w.writeTag({d}, .length_delimited);\n", .{field.number});
    try indent(writer, depth + 1);
    try writer.writeAll("try w.writeVarint(packed_len);\n");
}

fn writeEncodePackedLengthAssumeCapacity(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth + 1);
    try writer.print("w.writeTagAssumeCapacity({d}, .length_delimited);\n", .{field.number});
    try indent(writer, depth + 1);
    try writer.writeAll("w.writeVarintAssumeCapacity(packed_len);\n");
}

fn writeEncodePackedSuffix(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    _ = field;
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn fixedPackedScalarWidth(scalar: schema.ScalarType) ?usize {
    return switch (scalar) {
        .double, .fixed64, .sfixed64 => 8,
        .float, .fixed32, .sfixed32 => 4,
        .bool => 1,
        else => null,
    };
}

fn writePackedScalarSizeExpr(scalar: schema.ScalarType, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .double, .fixed64, .sfixed64 => try writer.writeAll("8"),
        .float, .fixed32, .sfixed32 => try writer.writeAll("4"),
        .int32 => try writer.print("pbz.wire.encodedVarintSize(@as(u64, @bitCast(@as(i64, {s}))))", .{value_expr}),
        .int64 => try writer.print("pbz.wire.encodedVarintSize(@as(u64, @bitCast({s})))", .{value_expr}),
        .uint32, .uint64 => try writer.print("pbz.wire.encodedVarintSize({s})", .{value_expr}),
        .sint32 => try writer.print("pbz.wire.encodedVarintSize(pbz.wire.zigZagEncode32({s}))", .{value_expr}),
        .sint64 => try writer.print("pbz.wire.encodedVarintSize(pbz.wire.zigZagEncode64({s}))", .{value_expr}),
        .bool => try writer.writeAll("1"),
        .string, .bytes => try writer.writeAll("@compileError(\"non-packable scalar\")"),
    }
}

fn writePackedScalarPayload(scalar: schema.ScalarType, value_expr: []const u8, writer_name: []const u8, writer: *std.Io.Writer) Error!void {
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

fn writePackedEnumPayload(value_expr: []const u8, writer_name: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.print("try {s}.writeVarint(@as(u64, @bitCast(@as(i64, {s}))))", .{ writer_name, value_expr });
}

fn writePackedScalarPayloadAssumeCapacity(scalar: schema.ScalarType, value_expr: []const u8, writer_name: []const u8, writer: *std.Io.Writer) Error!void {
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

fn writePackedEnumPayloadAssumeCapacity(value_expr: []const u8, writer_name: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.print("{s}.writeVarintAssumeCapacity(@as(u64, @bitCast(@as(i64, {s}))))", .{ writer_name, value_expr });
}

fn writePackedKindPayload(kind: schema.FieldKind, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    switch (kind) {
        .scalar => |scalar| try writePackedScalarPayload(scalar, value_expr, "packed_writer", writer),
        .enumeration => try writePackedEnumPayload(value_expr, "packed_writer", writer),
        else => try writer.writeAll("@compileError(\"non-packable extension\")"),
    }
}

fn writeEncodeMessageField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeEncodeMessageFieldAssumeCapacity(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeEncodeMessageFieldDeterministic(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, type_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeEncodeMessageFieldDeterministicAssumeCapacity(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, type_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeEncodeGroupFieldDeterministic(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, type_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeEncodeGroupFieldDeterministicAssumeCapacity(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, type_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeEncodeGroupFieldAssumeCapacity(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeEncodeMessagePayloadDeterministic(ctx: *const CodegenContext, number: u29, delimited: bool, type_name: []const u8, payload_expr: []const u8, writer_name: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("var nested = try ");
    try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    try writer.writeAll(".decode(allocator, ");
    try writer.writeAll(payload_expr);
    try writer.writeAll("); defer nested.deinit(allocator); const payload = try nested.encodeDeterministic(allocator); defer allocator.free(payload); ");
    if (delimited) {
        try writer.print("try {s}.writeTag({d}, .start_group); try {s}.appendSlice(payload); try {s}.writeTag({d}, .end_group);", .{ writer_name, number, writer_name, writer_name, number });
    } else {
        try writer.print("try {s}.writeMessage({d}, payload);", .{ writer_name, number });
    }
}

fn writeEncodeGroupField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeEncodeMapField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try writeEncodeMapEntries(ctx, field, "w", false, writer, depth);
}

fn writeEncodeMapFieldAssumeCapacity(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try writeEncodeMapEntries(ctx, field, "w", true, writer, depth);
}

fn writeEncodeMapEntries(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer_name: []const u8, assume_capacity: bool, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeEncodeMapFieldDeterministic(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try writeEncodeMapFieldDeterministicCommon(ctx, field, "w", false, writer, depth);
}

fn writeEncodeMapFieldDeterministicAssumeCapacity(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try writeEncodeMapFieldDeterministicCommon(ctx, field, "w", true, writer, depth);
}

fn writeEncodeMapFieldDeterministicCommon(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer_name: []const u8, assume_capacity: bool, writer: *std.Io.Writer, depth: usize) Error!void {
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
    try writer.writeAll("const entries_already_sorted = sorted: {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("var check_i: usize = 1;\n");
    try indent(writer, depth + 2);
    try writer.writeAll("while (check_i < entries.len) : (check_i += 1) {\n");
    try indent(writer, depth + 3);
    try writer.writeAll("if (");
    try writeMapKeyLessExpr(map_type.key, "entries[check_i].key", "entries[check_i - 1].key", writer);
    try writer.writeAll(") break :sorted false;\n");
    try indent(writer, depth + 2);
    try writer.writeAll("}\n");
    try indent(writer, depth + 2);
    try writer.writeAll("break :sorted true;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("};\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (!entries_already_sorted) {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("if (entries.len <= insertion_sort_limit) {\n");
    try indent(writer, depth + 3);
    try writer.writeAll("var sort_i: usize = 1;\n");
    try indent(writer, depth + 3);
    try writer.writeAll("while (sort_i < entries.len) : (sort_i += 1) {\n");
    try indent(writer, depth + 4);
    try writer.writeAll("const item = entries[sort_i];\n");
    try indent(writer, depth + 4);
    try writer.writeAll("var sort_j = sort_i;\n");
    try indent(writer, depth + 4);
    try writer.writeAll("while (sort_j > 0 and ");
    try writeMapKeyLessExpr(map_type.key, "item.key", "entries[sort_j - 1].key", writer);
    try writer.writeAll(") : (sort_j -= 1) entries[sort_j] = entries[sort_j - 1];\n");
    try indent(writer, depth + 4);
    try writer.writeAll("entries[sort_j] = item;\n");
    try indent(writer, depth + 3);
    try writer.writeAll("}\n");
    try indent(writer, depth + 2);
    try writer.writeAll("} else {\n");
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

fn writeEncodeMapEntryBody(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, map_type: schema.MapType, writer_name: []const u8, assume_capacity: bool, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeMapEntryEncodeUtf8Check(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, value_expr: []const u8, kind: schema.FieldKind, writer: *std.Io.Writer, depth: usize) Error!void {
    if (kind == .scalar and kind.scalar == .string and fieldUtf8Validation(file, field) == .verify) {
        try indent(writer, depth);
        try writer.print("if (!pbz.validateUtf8({s})) return error.InvalidUtf8;\n", .{value_expr});
    }
}

fn writeMapKeyLessExpr(scalar: schema.ScalarType, a: []const u8, b: []const u8, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .string => try writer.print("std.mem.lessThan(u8, {s}, {s})", .{ a, b }),
        .bool => try writer.print("!{s} and {s}", .{ a, b }),
        .int32, .int64, .uint32, .uint64, .sint32, .sint64, .fixed32, .fixed64, .sfixed32, .sfixed64 => try writer.print("{s} < {s}", .{ a, b }),
        .double, .float, .bytes => try writer.writeAll("false"),
    }
}

fn mapEntryValueIsTypedMessage(ctx: *const CodegenContext, field: *const schema.FieldDescriptor) bool {
    return typedMapMessageValueWithContext(ctx, field) != null;
}

fn writeMapEntryValueFieldSizeExprUsingLen(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, value_expr: []const u8, value_len_expr: []const u8, writer: *std.Io.Writer) Error!void {
    const map_type = field.kind.map;
    if (mapEntryValueIsTypedMessage(ctx, field)) {
        try writer.print("1 + pbz.wire.encodedVarintSize({s}) + {s}", .{ value_len_expr, value_len_expr });
    } else {
        try writeMapEntryFieldSizeExpr(2, map_type.value.*, value_expr, writer);
    }
}

fn writeMapEntryValueFieldSizeExpr(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    const map_type = field.kind.map;
    if (typedMapMessageValueWithContext(ctx, field)) |_| {
        try writer.print("blk: {{ const value_len = {s}.encodedSize(); break :blk 1 + pbz.wire.encodedVarintSize(value_len) + value_len; }}", .{value_expr});
    } else {
        try writeMapEntryFieldSizeExpr(2, map_type.value.*, value_expr, writer);
    }
}

fn writeMapEntryValueWriteCall(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, value_expr: []const u8, writer_name: []const u8, assume_capacity: bool, writer: *std.Io.Writer) Error!void {
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

fn writeMapEntryFieldSizeExpr(number: u29, kind: schema.FieldKind, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    const tag_size = wire.tagSize(number, kind.wireType()) catch unreachable;
    try writer.print("{d} + ", .{tag_size});
    try writeKindPayloadSizeExpr(kind, value_expr, writer);
}

fn writeKindPayloadSizeExpr(kind: schema.FieldKind, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    switch (kind) {
        .scalar => |scalar| try writeScalarPayloadSizeExpr(scalar, value_expr, writer),
        .enumeration => try writer.print("pbz.wire.encodedVarintSize(@as(u64, @bitCast(@as(i64, {s}))))", .{value_expr}),
        .message => try writer.print("pbz.wire.encodedVarintSize({s}.len) + {s}.len", .{ value_expr, value_expr }),
        else => try writer.writeAll("@compileError(\"unsupported map field kind\")"),
    }
}

fn writeScalarPayloadSizeExpr(scalar: schema.ScalarType, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .double, .fixed64, .sfixed64 => try writer.writeAll("8"),
        .float, .fixed32, .sfixed32 => try writer.writeAll("4"),
        .int32 => try writer.print("pbz.wire.encodedVarintSize(@as(u64, @bitCast(@as(i64, {s}))))", .{value_expr}),
        .int64 => try writer.print("pbz.wire.encodedVarintSize(@as(u64, @bitCast({s})))", .{value_expr}),
        .uint32, .uint64 => try writer.print("pbz.wire.encodedVarintSize({s})", .{value_expr}),
        .sint32 => try writer.print("pbz.wire.encodedVarintSize(pbz.wire.zigZagEncode32({s}))", .{value_expr}),
        .sint64 => try writer.print("pbz.wire.encodedVarintSize(pbz.wire.zigZagEncode64({s}))", .{value_expr}),
        .bool => try writer.writeAll("1"),
        .string, .bytes => try writer.print("pbz.wire.encodedVarintSize({s}.len) + {s}.len", .{ value_expr, value_expr }),
    }
}

fn writeKindWriteCall(number: u29, kind: schema.FieldKind, value_expr: []const u8, writer_name: []const u8, writer: *std.Io.Writer) Error!void {
    switch (kind) {
        .scalar => |scalar| try writer.print("try {s}.{s}({d}, {s}", .{ writer_name, scalarWriterName(scalar), number, value_expr }),
        .enumeration => try writer.print("try {s}.writeInt32({d}, {s}", .{ writer_name, number, value_expr }),
        .message => try writer.print("try {s}.writeMessage({d}, {s}", .{ writer_name, number, value_expr }),
        else => try writer.writeAll("@compileError(\"unsupported map field kind\")"),
    }
}

fn writeKindWriteCallAssumeCapacity(number: u29, kind: schema.FieldKind, value_expr: []const u8, writer_name: []const u8, writer: *std.Io.Writer) Error!void {
    switch (kind) {
        .scalar => |scalar| try writer.print("{s}.{s}AssumeCapacity({d}, {s})", .{ writer_name, scalarWriterName(scalar), number, value_expr }),
        .enumeration => try writer.print("{s}.writeInt32AssumeCapacity({d}, {s})", .{ writer_name, number, value_expr }),
        .message => try writer.print("{s}.writeMessageAssumeCapacity({d}, {s})", .{ writer_name, number, value_expr }),
        else => try writer.writeAll("@compileError(\"unsupported map field kind\")"),
    }
}

fn writeMessagePayloadRead(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, reader_name: []const u8, writer: *std.Io.Writer) Error!void {
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

fn fieldMessageEncoding(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor) schema.FeatureSet.MessageEncoding {
    if (field.features) |features| return features.message_encoding;
    return file.features.message_encoding;
}

fn fieldUtf8Validation(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor) schema.FeatureSet.Utf8Validation {
    if (field.features) |features| return features.utf8_validation;
    return file.features.utf8_validation;
}

fn fieldUtf8ValidationOptional(file: *const schema.FileDescriptor, field: ?*const schema.FieldDescriptor) schema.FeatureSet.Utf8Validation {
    if (field) |descriptor| return fieldUtf8Validation(file, descriptor);
    return file.features.utf8_validation;
}

fn writeScalarWriteCall(number: u29, scalar: schema.ScalarType, prefix: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.print("try w.{s}({d}, {s}", .{ scalarWriterName(scalar), number, prefix });
}

fn writeScalarWriteCallAssumeCapacity(number: u29, scalar: schema.ScalarType, prefix: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.print("w.{s}AssumeCapacity({d}, {s}", .{ scalarWriterName(scalar), number, prefix });
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

fn defaultSkipConditionWithOptions(scalar: schema.ScalarType) []const u8 {
    return switch (scalar) {
        .string, .bytes => ".len != 0 or options.always_print_primitive_fields) ",
        .bool => " or options.always_print_primitive_fields) ",
        else => " != 0 or options.always_print_primitive_fields) ",
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

fn writeFieldDefault(file: *const schema.FileDescriptor, field: schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
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

fn writeZigLowerCamelStringLiteral(value: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.writeByte('"');
    try writeLowerCamelEscaped(value, writer);
    try writer.writeByte('"');
}

fn writeJsonFieldNameLiteralContents(field: *const schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
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

fn writeEscapedStringContents(value: []const u8, writer: *std.Io.Writer) Error!void {
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

fn writeTextMethods(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub const TextFormatOptions = struct { enum_as_name: bool = true };\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn formatTextAlloc(self: @This(), allocator: std.mem.Allocator) ![]u8 {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try self.formatTextAllocWithOptions(allocator, .{});\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn formatTextAllocWithOptions(self: @This(), allocator: std.mem.Allocator, options: @This().TextFormatOptions) ![]u8 {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var out: std.Io.Writer.Allocating = .init(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer out.deinit();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.formatTextWithOptions(allocator, &out.writer, options);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try out.toOwnedSlice();\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn formatText(self: @This(), writer: *std.Io.Writer) !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.formatTextWithOptions(std.heap.page_allocator, writer, .{});\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn formatTextWithAllocator(self: @This(), allocator: std.mem.Allocator, writer: *std.Io.Writer) !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.formatTextWithOptions(allocator, writer, .{});\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn formatTextWithOptions(self: @This(), allocator: std.mem.Allocator, writer: *std.Io.Writer, options: @This().TextFormatOptions) !void {\n");
    if (!messageTextUsesAllocator(ctx, message)) {
        try indent(writer, depth + 1);
        try writer.writeAll("_ = allocator;\n");
    }
    if (!messageTextUsesOptions(ctx, message)) {
        try indent(writer, depth + 1);
        try writer.writeAll("_ = options;\n");
    }
    for (message.fields.items) |*field| {
        if (field.oneof_name == null) try writeTextField(ctx, field, writer, depth + 1);
    }
    for (message.oneofs.items) |oneof| {
        if (oneofHasTextField(ctx, message, oneof.name)) try writeTextOneof(ctx, message, oneof, writer, depth + 1);
    }
    try writeTextUnknownFields(ctx, message, writer, depth + 1);
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try writer.writeAll("\n");
    try writeTextParseMethods(ctx, message, writer, depth);
}

fn messageTextHasFields(ctx: *const CodegenContext, message: *const schema.MessageDescriptor) bool {
    for (message.fields.items) |field| {
        if (field.oneof_name == null and textFieldSupported(ctx, field)) return true;
    }
    for (message.oneofs.items) |oneof| {
        if (oneofHasTextField(ctx, message, oneof.name)) return true;
    }
    return false;
}

fn messageTextUsesAllocator(ctx: *const CodegenContext, message: *const schema.MessageDescriptor) bool {
    const file = ctx.file;
    for (message.fields.items) |field| {
        if (field.kind == .message or field.kind == .group) return true;
        if (field.kind == .map and textMapValueUsesAllocator(ctx, field.kind.map.value.*)) return true;
    }
    if (messageHasTextMessageExtension(file, message)) return true;
    return false;
}

fn messageTextUsesOptions(ctx: *const CodegenContext, message: *const schema.MessageDescriptor) bool {
    for (message.fields.items) |field| {
        if (field.oneof_name == null and textFieldUsesOptions(ctx, field)) return true;
    }
    for (message.oneofs.items) |oneof| {
        for (message.fields.items) |field| {
            if (field.oneof_name) |name| {
                if (std.mem.eql(u8, name, oneof.name) and textFieldUsesOptions(ctx, field)) return true;
            }
        }
    }
    return messageHasTextMessageExtension(ctx.file, message);
}

fn textFieldUsesOptions(ctx: *const CodegenContext, field: schema.FieldDescriptor) bool {
    return switch (field.kind) {
        .enumeration => true,
        .message, .group => |name| codegenCanReferenceMessageWithContext(ctx, name),
        .map => |map_type| textMapValueUsesOptions(ctx, map_type.value.*),
        else => false,
    };
}

fn textMapValueUsesOptions(ctx: *const CodegenContext, kind: schema.FieldKind) bool {
    return switch (kind) {
        .enumeration => true,
        .message, .group => |name| codegenCanReferenceMessageWithContext(ctx, name),
        else => false,
    };
}

fn messageHasTextMessageExtension(file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor) bool {
    for (file.extensions.items) |*field| {
        if (extensionAppliesToMessage(file, message, field) and extensionTextUsesAllocator(file, field)) return true;
    }
    for (file.messages.items) |*scope| {
        if (messageScopeHasTextMessageExtension(file, message, scope)) return true;
    }
    return false;
}

fn messageScopeHasTextMessageExtension(file: *const schema.FileDescriptor, target: *const schema.MessageDescriptor, scope: *const schema.MessageDescriptor) bool {
    for (scope.extensions.items) |*field| {
        if (extensionAppliesToMessage(file, target, field) and extensionTextUsesAllocator(file, field)) return true;
    }
    for (scope.messages.items) |*nested| {
        if (messageScopeHasTextMessageExtension(file, target, nested)) return true;
    }
    return false;
}

fn extensionTextUsesAllocator(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor) bool {
    return switch (field.kind) {
        .message, .group => |name| codegenCanReferenceMessage(file, name),
        else => false,
    };
}

fn textMapValueUsesAllocator(ctx: *const CodegenContext, kind: schema.FieldKind) bool {
    return switch (kind) {
        .message, .group => |name| codegenCanReferenceMessageWithContext(ctx, name),
        else => false,
    };
}

fn textFieldSupported(ctx: *const CodegenContext, field: schema.FieldDescriptor) bool {
    return switch (field.kind) {
        .scalar, .enumeration => true,
        .message, .group => |name| codegenCanReferenceMessageWithContext(ctx, name),
        .map => |map_type| textMapValueSupported(ctx, map_type.value.*),
    };
}

fn textMapValueSupported(ctx: *const CodegenContext, kind: schema.FieldKind) bool {
    return switch (kind) {
        .scalar, .enumeration => true,
        .message => |name| codegenCanReferenceMessageWithContext(ctx, name),
        else => false,
    };
}

fn oneofHasTextField(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, oneof_name: []const u8) bool {
    for (message.fields.items) |field| {
        if (field.oneof_name) |name| {
            if (std.mem.eql(u8, name, oneof_name) and textFieldSupported(ctx, field)) return true;
        }
    }
    return false;
}

fn writeTextField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    switch (field.kind) {
        .scalar => |scalar| try writeTextScalarField(file, field, scalar, writer, depth),
        .enumeration => try writeTextEnumField(file, field, writer, depth),
        .message, .group => |name| try writeTextMessageField(ctx, field, name, writer, depth),
        .map => try writeTextMapField(ctx, field, writer, depth),
    }
}

fn writeTextScalarField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        try writer.writeAll("for (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(") |value| { ");
        try writeTextFieldPrefix(field, writer);
        try writeTextUtf8Check(file, field, scalar, "value", writer);
        try writeTextScalarValue(scalar, "value", writer);
        try writer.writeAll("; try writer.writeByte('\\n'); }\n");
    } else {
        try indent(writer, depth);
        if (hasPresence(file, field.*)) {
            try writer.writeAll("if (self.");
            try writePresenceIdent(field.name, writer);
            try writer.writeAll(") { ");
        } else {
            try writer.writeAll("if (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(defaultSkipCondition(scalar));
            try writer.writeAll("{ ");
        }
        try writeTextFieldPrefix(field, writer);
        try writer.writeAll("const value = self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll("; ");
        try writeTextUtf8Check(file, field, scalar, "value", writer);
        try writeTextScalarValue(scalar, "value", writer);
        try writer.writeAll("; try writer.writeByte('\\n'); }\n");
    }
}

fn writeTextEnumField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const enum_name = switch (field.kind) {
        .enumeration => |name| name,
        else => return,
    };
    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        try writer.writeAll("for (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(") |value| { ");
        try writeTextFieldPrefix(field, writer);
        try writeTextEnumValue(file, enum_name, "value", writer);
        try writer.writeAll("; try writer.writeByte('\\n'); }\n");
    } else {
        try indent(writer, depth);
        if (hasPresence(file, field.*)) {
            try writer.writeAll("if (self.");
            try writePresenceIdent(field.name, writer);
            try writer.writeAll(") { ");
        } else {
            try writer.writeAll("if (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(" != 0) { ");
        }
        try writeTextFieldPrefix(field, writer);
        try writer.writeAll("const value = self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll("; ");
        try writeTextEnumValue(file, enum_name, "value", writer);
        try writer.writeAll("; try writer.writeByte('\\n'); }\n");
    }
}

fn writeTextMessageField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, type_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    if (!codegenCanReferenceMessageWithContext(ctx, type_name)) return;
    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        if (typedRepeatedMessageFieldWithContext(ctx, field)) |_| {
            try writer.writeAll("for (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(") |nested| {\n");
            try indent(writer, depth + 1);
            try writer.writeAll("try writer.writeAll(\"");
            try writeEscapedStringContents(field.name, writer);
            try writer.writeAll(" {\\n\");\n");
            try indent(writer, depth + 1);
            try writer.writeAll("try nested.formatTextWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name });\n");
            try indent(writer, depth + 1);
            try writer.writeAll("try writer.writeAll(\"}\\n\");\n");
        } else {
            try writer.writeAll("for (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(") |payload| {\n");
            try writeTextMessagePayload(ctx, field.name, type_name, "payload", writer, depth + 1);
        }
        try indent(writer, depth);
        try writer.writeAll("}\n");
    } else {
        try indent(writer, depth);
        if (typedSingularMessageFieldWithContext(ctx, field)) |_| {
            try writer.writeAll("if (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(") |nested| {\n");
            try indent(writer, depth + 1);
            try writer.writeAll("try writer.writeAll(\"");
            try writeEscapedStringContents(field.name, writer);
            try writer.writeAll(" {\\n\");\n");
            try indent(writer, depth + 1);
            try writer.writeAll("try nested.formatTextWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name });\n");
            try indent(writer, depth + 1);
            try writer.writeAll("try writer.writeAll(\"}\\n\");\n");
            try indent(writer, depth);
            try writer.writeAll("}\n");
            return;
        }
        try writer.writeAll("if (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(".len != 0) {\n");
        try writeTextMessagePayload(ctx, field.name, type_name, "self.", writer, depth + 1);
        try indent(writer, depth);
        try writer.writeAll("}\n");
    }
}

fn writeTextMessagePayload(ctx: *const CodegenContext, field_name: []const u8, type_name: []const u8, payload_expr: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("try writer.writeAll(\"");
    try writeEscapedStringContents(field_name, writer);
    try writer.writeAll(" {\\n\");\n");
    try indent(writer, depth);
    try writer.writeAll("var nested = try ");
    try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    try writer.writeAll(".decode(allocator, ");
    try writer.writeAll(payload_expr);
    if (std.mem.eql(u8, payload_expr, "self.")) try writeQuotedIdent(field_name, writer);
    try writer.writeAll(");\n");
    try indent(writer, depth);
    try writer.writeAll("defer nested.deinit(allocator);\n");
    try indent(writer, depth);
    try writer.writeAll("try nested.formatTextWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name });\n");
    try indent(writer, depth);
    try writer.writeAll("try writer.writeAll(\"}\\n\");\n");
}

fn writeTextMapField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const map_type = switch (field.kind) {
        .map => |map_type| map_type,
        else => return,
    };
    if (!textMapValueSupported(ctx, map_type.value.*)) return;
    try indent(writer, depth);
    try writer.writeAll("{ var map_it = self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".iterator(); while (map_it.next()) |map_entry| {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const entry = ");
    try writeQuotedIdentWithSuffix(field.name, "Entry", writer);
    try writer.writeAll("{ .key = map_entry.key_ptr.*, .value = map_entry.value_ptr.* };\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try writer.writeAll(\"");
    try writeEscapedStringContents(field.name, writer);
    try writer.writeAll(" {\\n\");\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try writer.writeAll(\"key: \"); ");
    try writeTextUtf8Check(ctx.file, field, map_type.key, "entry.key", writer);
    try writeTextScalarValue(map_type.key, "entry.key", writer);
    try writer.writeAll("; try writer.writeByte('\\n');\n");
    try indent(writer, depth + 1);
    if (map_type.value.* == .message and codegenCanReferenceMessageWithContext(ctx, map_type.value.message)) {
        try writer.writeAll("try writer.writeAll(\"value {\\n\");\n");
        if (typedMapMessageValueWithContext(ctx, field)) |_| {
            try indent(writer, depth + 1);
            try writer.writeAll("try entry.value.formatTextWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name });\n");
        } else {
            try indent(writer, depth + 1);
            try writer.writeAll("var nested = try ");
            try writeMessageTypeReferenceWithContext(ctx, map_type.value.message, writer);
            try writer.writeAll(".decode(allocator, entry.value);\n");
            try indent(writer, depth + 1);
            try writer.writeAll("defer nested.deinit(allocator);\n");
            try indent(writer, depth + 1);
            try writer.writeAll("try nested.formatTextWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name });\n");
        }
        try indent(writer, depth + 1);
        try writer.writeAll("try writer.writeAll(\"}\\n\");\n");
    } else {
        try writer.writeAll("try writer.writeAll(\"value: \"); ");
        if (map_type.value.* == .scalar) try writeTextUtf8Check(ctx.file, field, map_type.value.scalar, "entry.value", writer);
        try writeTextMapValue(ctx, map_type.value.*, "entry.value", writer);
        try writer.writeAll("; try writer.writeByte('\\n');\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("try writer.writeAll(\"}\\n\");\n");
    try indent(writer, depth);
    try writer.writeAll("} }\n");
}

fn writeTextOneof(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, oneof: schema.OneofDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    try indent(writer, depth);
    try writer.writeAll("switch (self.");
    try writeQuotedIdent(oneof.name, writer);
    try writer.writeAll(") {\n");
    try indent(writer, depth + 1);
    try writer.writeAll(".none => {},\n");
    for (message.fields.items) |*field| {
        if (field.oneof_name) |name| {
            if (!std.mem.eql(u8, name, oneof.name) or !textFieldSupported(ctx, field.*)) continue;
            try indent(writer, depth + 1);
            try writer.writeAll(".");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(" => |value| {\n");
            switch (field.kind) {
                .scalar => |scalar| {
                    try indent(writer, depth + 2);
                    try writeTextFieldPrefix(field, writer);
                    try writeTextScalarValue(scalar, "value", writer);
                    try writer.writeAll("; try writer.writeByte('\\n');\n");
                },
                .enumeration => {
                    const enum_name = field.kind.enumeration;
                    try indent(writer, depth + 2);
                    try writeTextFieldPrefix(field, writer);
                    try writeTextEnumValue(file, enum_name, "value", writer);
                    try writer.writeAll("; try writer.writeByte('\\n');\n");
                },
                .message, .group => |type_name| {
                    if (typedOneofMessageFieldWithContext(ctx, field)) |_| {
                        try indent(writer, depth + 2);
                        try writer.writeAll("try writer.writeAll(\"");
                        try writeEscapedStringContents(field.name, writer);
                        try writer.writeAll(" {\\n\");\n");
                        try indent(writer, depth + 2);
                        try writer.writeAll("try value.formatTextWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name });\n");
                        try indent(writer, depth + 2);
                        try writer.writeAll("try writer.writeAll(\"}\\n\");\n");
                    } else {
                        try writeTextMessagePayload(ctx, field.name, type_name, "value", writer, depth + 2);
                    }
                },
                else => {},
            }
            try indent(writer, depth + 1);
            try writer.writeAll("},\n");
        }
    }
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeTextUnknownFields(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("for (self._unknown_fields) |raw| {\n");
    try writeTextUnknownExtensionFields(ctx, message, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("try @This().textWriteUnknownRaw(raw, writer);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeTextUnknownExtensionFields(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    for (file.extensions.items) |*field| {
        if (extensionAppliesToMessage(file, message, field)) try writeTextUnknownExtensionField(ctx, field, writer, depth);
    }
    for (file.messages.items) |*scope| try writeTextUnknownMessageExtensions(ctx, message, scope, writer, depth);
}

fn writeTextUnknownMessageExtensions(ctx: *const CodegenContext, target: *const schema.MessageDescriptor, scope: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    for (scope.extensions.items) |*field| {
        if (extensionAppliesToMessage(file, target, field)) try writeTextUnknownExtensionField(ctx, field, writer, depth);
    }
    for (scope.messages.items) |*nested| try writeTextUnknownMessageExtensions(ctx, target, nested, writer, depth);
}

fn writeTextUnknownExtensionField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    switch (field.kind) {
        .scalar, .enumeration => {},
        .message, .group => |type_name| {
            if (!codegenCanReferenceMessageWithContext(ctx, type_name)) return;
            return try writeTextUnknownMessageExtensionField(ctx, field, type_name, writer, depth);
        },
        else => return,
    }
    try indent(writer, depth);
    try writer.writeAll("if (");
    try writeExtensionHelperReference(field, writer);
    try writer.writeAll(".decodeRaw(raw) catch null) |value| {\n");
    try indent(writer, depth + 2);
    try writeTextExtensionFieldPrefix(file, field, writer);
    switch (field.kind) {
        .scalar => |scalar| {
            try writeTextUtf8Check(file, field, scalar, "value", writer);
            try writeTextScalarValue(scalar, "value", writer);
        },
        .enumeration => |name| try writeTextEnumValue(file, name, "value", writer),
        else => unreachable,
    }
    try writer.writeAll("; try writer.writeByte('\\n');\n");
    try indent(writer, depth + 2);
    try writer.writeAll("continue;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
    if (field.resolvedPacked(file)) {
        try indent(writer, depth);
        try writer.writeAll("if (");
        try writeExtensionHelperReference(field, writer);
        try writer.writeAll(".decodePackedRaw(allocator, raw) catch null) |values| {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("defer allocator.free(values);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("for (values) |value| {\n");
        try indent(writer, depth + 2);
        try writeTextExtensionFieldPrefix(file, field, writer);
        switch (field.kind) {
            .scalar => |scalar| {
                try writeTextUtf8Check(file, field, scalar, "value", writer);
                try writeTextScalarValue(scalar, "value", writer);
            },
            .enumeration => |name| try writeTextEnumValue(file, name, "value", writer),
            else => unreachable,
        }
        try writer.writeAll("; try writer.writeByte('\\n');\n");
        try indent(writer, depth + 1);
        try writer.writeAll("}\n");
        try indent(writer, depth + 1);
        try writer.writeAll("continue;\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");
    }
}

fn writeTextUnknownMessageExtensionField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, type_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    try indent(writer, depth);
    try writer.writeAll("if (");
    try writeExtensionHelperReference(field, writer);
    try writer.writeAll(".decodeRaw(raw) catch null) |payload| {\n");
    try indent(writer, depth + 2);
    try writeTextExtensionBlockPrefix(file, field, writer);
    try indent(writer, depth + 2);
    try writer.writeAll("var nested = try ");
    try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    try writer.writeAll(".decode(allocator, payload);\n");
    try indent(writer, depth + 2);
    try writer.writeAll("defer nested.deinit(allocator);\n");
    try indent(writer, depth + 2);
    try writer.writeAll("try nested.formatTextWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name });\n");
    try indent(writer, depth + 2);
    try writer.writeAll("try writer.writeAll(\"}\\n\");\n");
    try indent(writer, depth + 2);
    try writer.writeAll("continue;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeTextFieldPrefix(field: *const schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("try writer.writeAll(\"");
    try writeEscapedStringContents(field.name, writer);
    try writer.writeAll(": \"); ");
}

fn writeTextExtensionFieldPrefix(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("try writer.writeAll(\"[");
    try writeExtensionTextNameContents(file, field, true, writer);
    try writer.writeAll("]: \"); ");
}

fn writeTextExtensionBlockPrefix(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("try writer.writeAll(\"[");
    try writeExtensionTextNameContents(file, field, true, writer);
    try writer.writeAll("] {\\n\");\n");
}

fn writeExtensionTextNameContents(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, qualified: bool, writer: *std.Io.Writer) Error!void {
    const full_name = schema.extensionFullName(field);
    if (qualified) {
        if (std.mem.startsWith(u8, full_name, ".")) {
            try writeEscapedStringContents(full_name[1..], writer);
        } else if (std.mem.indexOfScalar(u8, full_name, '.') != null or file.package.len == 0) {
            try writeEscapedStringContents(full_name, writer);
        } else {
            try writeEscapedStringContents(file.package, writer);
            try writer.writeByte('.');
            try writeEscapedStringContents(full_name, writer);
        }
    } else {
        try writeEscapedStringContents(leafTypeName(full_name), writer);
    }
}

fn writeTextUtf8Check(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, scalar: schema.ScalarType, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    if (scalar == .string and fieldUtf8Validation(file, field) == .verify) {
        try writer.print("if (!pbz.validateUtf8({s})) return error.InvalidUtf8; ", .{value_expr});
    }
}

fn writeTextScalarValue(scalar: schema.ScalarType, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .string, .bytes => try writer.print("try @This().textWriteQuotedBytes({s}, writer)", .{value_expr}),
        .bool => try writer.print("try writer.writeAll(if ({s}) \"true\" else \"false\")", .{value_expr}),
        else => try writer.print("try writer.print(\"{{d}}\", .{{{s}}})", .{value_expr}),
    }
}

fn writeTextEnumValue(file: *const schema.FileDescriptor, enum_name: []const u8, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.print("try @This().textWriteEnum(writer, {s}", .{value_expr});
    try writer.writeAll(", ");
    try writeEnumNameArray(file, enum_name, writer);
    try writer.writeAll(", ");
    try writeEnumNumberArray(file, enum_name, writer);
    try writer.writeAll(", options.enum_as_name");
    try writer.writeAll(")");
}

fn writeTextMapValue(ctx: *const CodegenContext, kind: schema.FieldKind, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    const file = ctx.file;
    switch (kind) {
        .scalar => |scalar| try writeTextScalarValue(scalar, value_expr, writer),
        .enumeration => |name| try writeTextEnumValue(file, name, value_expr, writer),
        .message => |name| if (codegenCanReferenceMessageWithContext(ctx, name)) {
            try writer.writeAll("var nested = try ");
            try writeMessageTypeReferenceWithContext(ctx, name, writer);
            try writer.writeAll(".decode(allocator, ");
            try writer.writeAll(value_expr);
            try writer.writeAll("); defer nested.deinit(allocator); try nested.formatTextWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name })");
        } else try writer.writeAll("@compileError(\"unsupported map text value\")"),
        else => try writer.writeAll("@compileError(\"unsupported map text value\")"),
    }
}

fn writeJsonMethods(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub const JsonStringifyOptions = struct { enum_as_name: bool = true, preserve_proto_field_names: bool = false, always_print_primitive_fields: bool = false };\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn jsonStringifyAlloc(self: @This(), allocator: std.mem.Allocator) ![]u8 {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try self.jsonStringifyAllocWithOptions(allocator, .{});\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn jsonStringifyAllocWithOptions(self: @This(), allocator: std.mem.Allocator, options: @This().JsonStringifyOptions) ![]u8 {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var out: std.Io.Writer.Allocating = .init(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer out.deinit();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.jsonStringifyWithOptions(allocator, &out.writer, options);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try out.toOwnedSlice();\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn jsonStringify(self: @This(), writer: *std.Io.Writer) !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.jsonStringifyWithOptions(std.heap.page_allocator, writer, .{});\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn jsonStringifyWithAllocator(self: @This(), allocator: std.mem.Allocator, writer: *std.Io.Writer) !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.jsonStringifyWithOptions(allocator, writer, .{});\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn jsonStringifyWithOptions(self: @This(), allocator: std.mem.Allocator, writer: *std.Io.Writer, options: @This().JsonStringifyOptions) !void {\n");
    if (!messageJsonStringifyUsesAllocator(ctx, message)) {
        try indent(writer, depth + 1);
        try writer.writeAll("_ = allocator;\n");
    }
    if (!messageJsonStringifyUsesOptions(ctx, message)) {
        try indent(writer, depth + 1);
        try writer.writeAll("_ = options;\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("try writer.writeAll(\"{\");\n");
    if (messageJsonStringifyHasFields(ctx, message)) {
        try indent(writer, depth + 1);
        try writer.writeAll("var first = true;\n");
        for (message.fields.items) |*field| {
            if (field.oneof_name == null) try writeJsonField(ctx, field, writer, depth + 1);
        }
        for (message.oneofs.items) |oneof| {
            if (oneofHasJsonField(ctx, message, oneof.name)) try writeJsonOneof(ctx, message, oneof, writer, depth + 1);
        }
        try writeJsonExtensionFields(ctx, message, writer, depth + 1);
    } else {
        try indent(writer, depth + 1);
        try writer.writeAll("_ = self;\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("try writer.writeAll(\"}\");\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try writer.writeAll("\n");
    try writeJsonParseMethods(ctx, message, writer, depth);
}

fn writeJsonParseMethods(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    try indent(writer, depth);
    try writer.writeAll("pub const JsonParseOptions = struct { ignore_unknown_fields: bool = false };\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn jsonParse(allocator: std.mem.Allocator, text: []const u8) !@This() {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try @This().jsonParseWithOptions(allocator, text, .{});\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn jsonParseWithOptions(allocator: std.mem.Allocator, text: []const u8, options: @This().JsonParseOptions) !@This() {\n");
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
    try writer.writeAll("var self = try @This().jsonParseValueWithOptions(allocator, arena.allocator(), parsed, options);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("self._json_arena = arena;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return self;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("/// Parse a pre-parsed JSON subtree without serializing it back to text first.\n");
    try indent(writer, depth);
    try writer.writeAll("/// The caller must keep `arena_allocator` alive for borrowed string/bytes data.\n");
    try indent(writer, depth);
    try writer.writeAll("pub fn jsonParseValue(allocator: std.mem.Allocator, arena_allocator: std.mem.Allocator, json_value: std.json.Value) !@This() {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try @This().jsonParseValueWithOptions(allocator, arena_allocator, json_value, .{});\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("/// Option-bearing variant of jsonParseValue for generated nested-message parsers.\n");
    try indent(writer, depth);
    try writer.writeAll("pub fn jsonParseValueWithOptions(allocator: std.mem.Allocator, arena_allocator: std.mem.Allocator, json_value: std.json.Value, options: @This().JsonParseOptions) !@This() {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var self = @This().init();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer self.deinit(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.jsonFillFromValue(allocator, arena_allocator, json_value, options);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return self;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn jsonParseInitialized(allocator: std.mem.Allocator, text: []const u8) !@This() {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var self = try @This().jsonParse(allocator, text);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer self.deinit(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.validateRequiredRecursive(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return self;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn jsonParseInitializedWithOptions(allocator: std.mem.Allocator, text: []const u8, options: @This().JsonParseOptions) !@This() {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var self = try @This().jsonParseWithOptions(allocator, text, options);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer self.deinit(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.validateRequiredRecursive(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return self;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try indent(writer, depth);
    try writer.writeAll("fn jsonFillFromValue(self: *@This(), allocator: std.mem.Allocator, arena_allocator: std.mem.Allocator, json_value: std.json.Value, options: @This().JsonParseOptions) !void {\n");
    const has_parse_fields = messageJsonParseHasFields(ctx, message);
    if (!has_parse_fields) {
        try indent(writer, depth + 1);
        try writer.writeAll("_ = self;\n");
    }
    if (!messageJsonParseUsesAllocator(ctx, message)) {
        try indent(writer, depth + 1);
        try writer.writeAll("_ = allocator;\n");
    }
    if (!messageJsonParseUsesArenaAllocator(ctx, message)) {
        try indent(writer, depth + 1);
        try writer.writeAll("_ = arena_allocator;\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("const object = switch (json_value) { .object => |object| object, else => return error.TypeMismatch };\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var it = object.iterator();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("while (it.next()) |entry| {\n");
    if (has_parse_fields) {
        try indent(writer, depth + 2);
        try writer.writeAll("const key = entry.key_ptr.*;\n");
        try indent(writer, depth + 2);
        try writer.writeAll("const value = entry.value_ptr.*;\n");
        try indent(writer, depth + 2);
        try writer.writeAll("if (value == .null) {\n");
        for (message.fields.items) |*field| {
            if (field.oneof_name == null) try writeJsonClearField(ctx, field, writer, depth + 3);
        }
        for (message.oneofs.items) |oneof| {
            for (message.fields.items) |*field| {
                if (field.oneof_name) |name| {
                    if (std.mem.eql(u8, name, oneof.name)) try writeJsonClearOneofField(oneof, field, writer, depth + 3);
                }
            }
        }
        try writeJsonClearExtensions(file, message, writer, depth + 3);
        try indent(writer, depth + 3);
        try writer.writeAll("if (options.ignore_unknown_fields) continue;\n");
        try indent(writer, depth + 3);
        try writer.writeAll("return error.UnknownField;\n");
        try indent(writer, depth + 2);
        try writer.writeAll("}\n");
        for (message.fields.items) |*field| {
            if (field.oneof_name == null) try writeJsonParseField(ctx, field, writer, depth + 2);
        }
        for (message.oneofs.items) |oneof| {
            for (message.fields.items) |*field| {
                if (field.oneof_name) |name| {
                    if (std.mem.eql(u8, name, oneof.name)) try writeJsonParseOneofField(ctx, oneof, field, writer, depth + 2);
                }
            }
        }
        try writeJsonParseExtensions(ctx, message, writer, depth + 2);
    }
    try indent(writer, depth + 2);
    try writer.writeAll("if (options.ignore_unknown_fields) continue;\n");
    try indent(writer, depth + 2);
    try writer.writeAll("return error.UnknownField;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");

    try writeJsonParseHelpers(writer, depth);
}

fn messageJsonParseUsesAllocator(ctx: *const CodegenContext, message: *const schema.MessageDescriptor) bool {
    for (message.fields.items) |field| {
        if (field.oneof_name == null and fieldJsonParseUsesAllocator(field)) return true;
    }
    if (messageHasJsonExtensions(ctx, message)) return true;
    return false;
}

fn messageJsonParseHasFields(ctx: *const CodegenContext, message: *const schema.MessageDescriptor) bool {
    for (message.fields.items) |field| {
        if (field.kind == .scalar or field.kind == .enumeration or field.kind == .map or field.kind == .message or field.kind == .group) return true;
    }
    if (messageHasJsonExtensions(ctx, message)) return true;
    return false;
}

fn messageJsonStringifyHasFields(ctx: *const CodegenContext, message: *const schema.MessageDescriptor) bool {
    for (message.fields.items) |field| {
        if (field.oneof_name == null and fieldJsonStringifySupported(ctx, field)) return true;
    }
    for (message.oneofs.items) |oneof| {
        if (oneofHasJsonField(ctx, message, oneof.name)) return true;
    }
    if (messageHasJsonExtensions(ctx, message)) return true;
    return false;
}

fn messageJsonStringifyUsesAllocator(ctx: *const CodegenContext, message: *const schema.MessageDescriptor) bool {
    for (message.fields.items) |field| {
        if (field.kind == .message or field.kind == .group) return true;
        if (field.kind == .map and jsonMapStringifyValueUsesAllocator(ctx, field.kind.map.value.*)) return true;
    }
    if (messageHasJsonExtensions(ctx, message)) return true;
    return false;
}

fn jsonMapStringifyValueUsesAllocator(ctx: *const CodegenContext, kind: schema.FieldKind) bool {
    return switch (kind) {
        .message, .group => |name| codegenCanReferenceMessageWithContext(ctx, name),
        else => false,
    };
}

fn messageJsonStringifyUsesOptions(ctx: *const CodegenContext, message: *const schema.MessageDescriptor) bool {
    for (message.fields.items) |field| {
        if (field.oneof_name == null and fieldJsonStringifySupported(ctx, field)) return true;
    }
    for (message.oneofs.items) |oneof| {
        if (oneofHasJsonField(ctx, message, oneof.name)) return true;
    }
    if (messageHasJsonOptionUsingExtensions(ctx, message)) return true;
    return false;
}

fn fieldJsonStringifySupported(ctx: *const CodegenContext, field: schema.FieldDescriptor) bool {
    return switch (field.kind) {
        .scalar, .enumeration => true,
        .message, .group => |name| codegenCanReferenceMessageWithContext(ctx, name),
        .map => |map_type| jsonMapValueSupported(ctx, map_type.value.*),
    };
}

fn oneofHasJsonField(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, oneof_name: []const u8) bool {
    for (message.fields.items) |field| {
        if (field.oneof_name) |name| {
            if (std.mem.eql(u8, name, oneof_name) and fieldJsonStringifySupported(ctx, field)) return true;
        }
    }
    return false;
}

fn messageJsonParseUsesArenaAllocator(ctx: *const CodegenContext, message: *const schema.MessageDescriptor) bool {
    for (message.fields.items) |field| {
        switch (field.kind) {
            .scalar => |scalar| if (scalar == .bytes) return true,
            .message, .group => return true,
            .map => |map_type| switch (map_type.value.*) {
                .scalar => |scalar| if (scalar == .bytes) return true,
                .message, .group => return true,
                else => {},
            },
            else => {},
        }
    }
    if (messageHasJsonMessageExtension(ctx, message)) return true;
    return false;
}

fn fieldJsonParseUsesAllocator(field: schema.FieldDescriptor) bool {
    return field.kind == .map or field.kind == .message or field.kind == .group or (field.cardinality == .repeated and (field.kind == .scalar or field.kind == .enumeration));
}

fn messageHasJsonExtensions(ctx: *const CodegenContext, message: *const schema.MessageDescriptor) bool {
    const file = ctx.file;
    for (file.extensions.items) |*field| {
        if (extensionAppliesToMessage(file, message, field) and jsonExtensionSupportedWithContext(ctx, field)) return true;
    }
    for (file.messages.items) |*scope| {
        if (messageScopeHasJsonExtensions(ctx, message, scope)) return true;
    }
    return false;
}

fn messageScopeHasJsonExtensions(ctx: *const CodegenContext, target: *const schema.MessageDescriptor, scope: *const schema.MessageDescriptor) bool {
    const file = ctx.file;
    for (scope.extensions.items) |*field| {
        if (extensionAppliesToMessage(file, target, field) and jsonExtensionSupportedWithContext(ctx, field)) return true;
    }
    for (scope.messages.items) |*nested| {
        if (messageScopeHasJsonExtensions(ctx, target, nested)) return true;
    }
    return false;
}

fn messageHasJsonOptionUsingExtensions(ctx: *const CodegenContext, message: *const schema.MessageDescriptor) bool {
    const file = ctx.file;
    for (file.extensions.items) |*field| {
        if (extensionAppliesToMessage(file, message, field) and jsonExtensionUsesOptions(ctx, field)) return true;
    }
    for (file.messages.items) |*scope| {
        if (messageScopeHasJsonOptionUsingExtensions(ctx, message, scope)) return true;
    }
    return false;
}

fn messageScopeHasJsonOptionUsingExtensions(ctx: *const CodegenContext, target: *const schema.MessageDescriptor, scope: *const schema.MessageDescriptor) bool {
    const file = ctx.file;
    for (scope.extensions.items) |*field| {
        if (extensionAppliesToMessage(file, target, field) and jsonExtensionUsesOptions(ctx, field)) return true;
    }
    for (scope.messages.items) |*nested| {
        if (messageScopeHasJsonOptionUsingExtensions(ctx, target, nested)) return true;
    }
    return false;
}

fn messageHasJsonMessageExtension(ctx: *const CodegenContext, message: *const schema.MessageDescriptor) bool {
    const file = ctx.file;
    for (file.extensions.items) |*field| {
        if (extensionAppliesToMessage(file, message, field) and jsonExtensionUsesArenaWithContext(ctx, field)) return true;
    }
    for (file.messages.items) |*scope| {
        if (messageScopeHasJsonMessageExtension(ctx, message, scope)) return true;
    }
    return false;
}

fn messageScopeHasJsonMessageExtension(ctx: *const CodegenContext, target: *const schema.MessageDescriptor, scope: *const schema.MessageDescriptor) bool {
    const file = ctx.file;
    for (scope.extensions.items) |*field| {
        if (extensionAppliesToMessage(file, target, field) and jsonExtensionUsesArenaWithContext(ctx, field)) return true;
    }
    for (scope.messages.items) |*nested| {
        if (messageScopeHasJsonMessageExtension(ctx, target, nested)) return true;
    }
    return false;
}

fn jsonExtensionSupported(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor) bool {
    return switch (field.kind) {
        .scalar, .enumeration => true,
        .message, .group => |name| codegenCanReferenceMessage(file, name),
        else => false,
    };
}

fn jsonExtensionSupportedWithContext(ctx: *const CodegenContext, field: *const schema.FieldDescriptor) bool {
    return switch (field.kind) {
        .scalar, .enumeration => true,
        .message, .group => |name| codegenCanReferenceMessageWithContext(ctx, name),
        else => false,
    };
}

fn jsonExtensionUsesOptions(ctx: *const CodegenContext, field: *const schema.FieldDescriptor) bool {
    return switch (field.kind) {
        .enumeration => true,
        .message, .group => |name| codegenCanReferenceMessageWithContext(ctx, name),
        else => false,
    };
}

fn jsonExtensionUsesArenaWithContext(ctx: *const CodegenContext, field: *const schema.FieldDescriptor) bool {
    return switch (field.kind) {
        .scalar => |scalar| scalar == .bytes,
        .message, .group => |name| codegenCanReferenceMessageWithContext(ctx, name),
        else => false,
    };
}

fn jsonExtensionUsesArena(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor) bool {
    return switch (field.kind) {
        .scalar => |scalar| scalar == .bytes,
        .message, .group => |name| codegenCanReferenceMessage(file, name),
        else => false,
    };
}

fn writeJsonClearField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    try indent(writer, depth);
    try writer.writeAll("if (");
    try writeJsonKeyCondition(field, writer);
    try writer.writeAll(") {\n");
    if (field.kind == .map) {
        try indent(writer, depth + 1);
        try writer.writeAll("@This().");
        try writeQuotedIdentWithPrefix(field.name, "deinitMap_", writer);
        try writer.writeAll("(allocator, &self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(");\n");
    } else if (typedSingularMessageFieldWithContext(ctx, field)) |_| {
        try indent(writer, depth + 1);
        try writer.writeAll("if (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(") |*old_value| old_value.deinit(allocator); self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = null;\n");
    } else if (typedRepeatedMessageFieldWithContext(ctx, field)) |_| {
        try indent(writer, depth + 1);
        try writer.writeAll("const old = self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll("; self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = &.{}; for (old) |item| { var mutable = item; mutable.deinit(allocator); } if (old.len != 0) allocator.free(old);\n");
    } else if (field.cardinality == .repeated) {
        try indent(writer, depth + 1);
        try writer.writeAll("const old = self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll("; self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = &.{}; if (old.len != 0) allocator.free(old);\n");
    } else {
        try indent(writer, depth + 1);
        try writer.writeAll("self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = ");
        try writeFieldDefault(file, field.*, writer);
        try writer.writeAll(";\n");
        if (hasPresence(file, field.*)) {
            try indent(writer, depth + 1);
            try writer.writeAll("self.");
            try writePresenceIdent(field.name, writer);
            try writer.writeAll(" = false;\n");
        }
    }
    try indent(writer, depth + 1);
    try writer.writeAll("continue;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeJsonClearOneofField(oneof: schema.OneofDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("if (");
    try writeJsonKeyCondition(field, writer);
    try writer.writeAll(") { self.");
    try writeQuotedIdent(oneof.name, writer);
    try writer.writeAll(" = .none; continue; }\n");
}

fn writeJsonClearExtensions(file: *const schema.FileDescriptor, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    for (file.extensions.items) |*field| {
        if (extensionAppliesToMessage(file, message, field) and jsonExtensionSupported(file, field)) try writeJsonClearExtension(file, field, writer, depth);
    }
    for (file.messages.items) |*scope| try writeJsonClearScopedExtensions(file, message, scope, writer, depth);
}

fn writeJsonClearScopedExtensions(file: *const schema.FileDescriptor, target: *const schema.MessageDescriptor, scope: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    for (scope.extensions.items) |*field| {
        if (extensionAppliesToMessage(file, target, field) and jsonExtensionSupported(file, field)) try writeJsonClearExtension(file, field, writer, depth);
    }
    for (scope.messages.items) |*nested| try writeJsonClearScopedExtensions(file, target, nested, writer, depth);
}

fn writeJsonClearExtension(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("if (");
    try writeExtensionJsonKeyCondition(file, field, writer);
    try writer.writeAll(") { try self.clearUnknownFieldsByNumber(allocator, ");
    try writeExtensionHelperReference(field, writer);
    try writer.writeAll(".number); continue; }\n");
}

fn writeJsonParseField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    switch (field.kind) {
        .scalar, .enumeration => {},
        .message, .group => |name| return try writeJsonParseMessageField(ctx, field, name, writer, depth),
        .map => return try writeJsonParseMapField(ctx, field, writer, depth),
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
        if (field.kind == .enumeration) {
            try indent(writer, depth + 1);
            try writer.writeAll("for (array.items) |item| {\n");
            try indent(writer, depth + 2);
            try writer.writeAll("const parsed_enum = ");
            try writeJsonParseEnumExpr(file, field.kind.enumeration, "item", writer);
            try writer.writeAll(" catch |err| { if (options.ignore_unknown_fields) continue; return err; };\n");
            try indent(writer, depth + 2);
            try writer.writeAll("try list.append(allocator, parsed_enum);\n");
            try indent(writer, depth + 1);
            try writer.writeAll("}\n");
        } else {
            try indent(writer, depth + 1);
            try writer.writeAll("for (array.items) |item| try list.append(allocator, ");
            try writeJsonParseValueExpr(file, field.kind, "item", "arena_allocator", writer);
            try writer.writeAll(");\n");
        }
        try indent(writer, depth + 1);
        try writer.writeAll("self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = blk: { const old = self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll("; const owned = try list.toOwnedSlice(allocator); if (old.len != 0) allocator.free(old); break :blk owned; };\n");
    } else {
        try indent(writer, depth + 1);
        try writer.writeAll("self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = ");
        if (field.kind == .enumeration) {
            try writeJsonParseEnumExpr(file, field.kind.enumeration, "value", writer);
            try writer.writeAll(" catch |err| { if (options.ignore_unknown_fields) continue; return err; }");
        } else {
            try writeJsonParseValueExpr(file, field.kind, "value", "arena_allocator", writer);
        }
        try writer.writeAll(";\n");
        if (hasPresence(file, field.*)) {
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

fn writeJsonParseMessageField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, type_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    if (!codegenCanReferenceMessageWithContext(ctx, type_name)) return;
    try indent(writer, depth);
    try writer.writeAll("if (");
    try writeJsonKeyCondition(field, writer);
    try writer.writeAll(") {\n");
    if (field.cardinality == .repeated) {
        if (typedRepeatedMessageFieldWithContext(ctx, field)) |_| {
            try indent(writer, depth + 1);
            try writer.writeAll("const array = switch (value) { .array => |array| array, else => return error.TypeMismatch };\n");
            try indent(writer, depth + 1);
            try writer.writeAll("var list: std.ArrayList(");
            try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
            try writer.writeAll(") = .empty;\n");
            try indent(writer, depth + 1);
            try writer.writeAll("errdefer { for (list.items) |item| { var mutable = item; mutable.deinit(allocator); } list.deinit(allocator); }\n");
            try indent(writer, depth + 1);
            try writer.writeAll("for (array.items) |item| {\n");
            try indent(writer, depth + 2);
            try writer.writeAll("var nested = try ");
            try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
            try writer.writeAll(".jsonParseValueWithOptions(allocator, arena_allocator, item, .{ .ignore_unknown_fields = options.ignore_unknown_fields });\n");
            try indent(writer, depth + 2);
            try writer.writeAll("errdefer nested.deinit(allocator);\n");
            try indent(writer, depth + 2);
            try writer.writeAll("try list.append(allocator, nested);\n");
            try indent(writer, depth + 1);
            try writer.writeAll("}\n");
            try indent(writer, depth + 1);
            try writer.writeAll("{ const old = self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll("; self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(" = try list.toOwnedSlice(allocator); for (old) |item| { var mutable = item; mutable.deinit(allocator); } if (old.len != 0) allocator.free(old); }\n");
            try indent(writer, depth + 1);
            try writer.writeAll("continue;\n");
            try indent(writer, depth);
            try writer.writeAll("}\n");
            return;
        }
        try indent(writer, depth + 1);
        try writer.writeAll("const array = switch (value) { .array => |array| array, else => return error.TypeMismatch };\n");
        try indent(writer, depth + 1);
        try writer.writeAll("var list: std.ArrayList([]const u8) = .empty;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("errdefer list.deinit(allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("for (array.items) |item| {\n");
        try indent(writer, depth + 2);
        try writer.writeAll("var nested = try ");
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
        try writer.writeAll(".jsonParseValueWithOptions(arena_allocator, arena_allocator, item, .{ .ignore_unknown_fields = options.ignore_unknown_fields });\n");
        try indent(writer, depth + 2);
        try writer.writeAll("defer nested.deinit(arena_allocator);\n");
        try indent(writer, depth + 2);
        try writer.writeAll("try list.append(allocator, try nested.encode(arena_allocator));\n");
        try indent(writer, depth + 1);
        try writer.writeAll("}\n");
        try indent(writer, depth + 1);
        try writer.writeAll("self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = blk: { const old = self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll("; const owned = try list.toOwnedSlice(allocator); if (old.len != 0) allocator.free(old); break :blk owned; };\n");
    } else {
        if (typedOneofMessageFieldWithContext(ctx, field)) |_| {
            const oneof_name = field.oneof_name orelse return;
            try indent(writer, depth + 1);
            try writer.writeAll("var nested = try ");
            try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
            try writer.writeAll(".jsonParseValueWithOptions(allocator, arena_allocator, value, .{ .ignore_unknown_fields = options.ignore_unknown_fields });\n");
            try indent(writer, depth + 1);
            try writer.writeAll("errdefer nested.deinit(allocator);\n");
            try indent(writer, depth + 1);
            try writer.writeAll("self.");
            try writeQuotedIdent(oneof_name, writer);
            try writer.writeAll(" = .{ .");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(" = nested };\n");
            try indent(writer, depth + 1);
            try writer.writeAll("continue;\n");
            try indent(writer, depth);
            try writer.writeAll("}\n");
            return;
        }
        if (typedSingularMessageFieldWithContext(ctx, field)) |_| {
            try indent(writer, depth + 1);
            try writer.writeAll("var nested = try ");
            try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
            try writer.writeAll(".jsonParseValueWithOptions(allocator, arena_allocator, value, .{ .ignore_unknown_fields = options.ignore_unknown_fields });\n");
            try indent(writer, depth + 1);
            try writer.writeAll("errdefer nested.deinit(allocator);\n");
            try indent(writer, depth + 1);
            try writer.writeAll("if (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(") |*existing| { try existing.mergeFrom(allocator, nested); nested.deinit(allocator); } else { self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(" = nested; }\n");
            try indent(writer, depth + 1);
            try writer.writeAll("continue;\n");
            try indent(writer, depth);
            try writer.writeAll("}\n");
            return;
        }
        try indent(writer, depth + 1);
        try writer.writeAll("var nested = try ");
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
        try writer.writeAll(".jsonParseValueWithOptions(arena_allocator, arena_allocator, value, .{ .ignore_unknown_fields = options.ignore_unknown_fields });\n");
        try indent(writer, depth + 1);
        try writer.writeAll("defer nested.deinit(arena_allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(" = try nested.encode(arena_allocator);\n");
        if (hasPresence(file, field.*)) {
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

fn writeJsonParseExtensions(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    for (file.extensions.items) |*field| {
        if (extensionAppliesToMessage(file, message, field) and jsonExtensionSupportedWithContext(ctx, field)) try writeJsonParseExtensionField(ctx, field, writer, depth);
    }
    for (file.messages.items) |*scope| try writeJsonParseScopedExtensions(ctx, message, scope, writer, depth);
}

fn writeJsonParseScopedExtensions(ctx: *const CodegenContext, target: *const schema.MessageDescriptor, scope: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    for (scope.extensions.items) |*field| {
        if (extensionAppliesToMessage(file, target, field) and jsonExtensionSupportedWithContext(ctx, field)) try writeJsonParseExtensionField(ctx, field, writer, depth);
    }
    for (scope.messages.items) |*nested| try writeJsonParseScopedExtensions(ctx, target, nested, writer, depth);
}

fn writeJsonParseExtensionField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    switch (field.kind) {
        .scalar, .enumeration => return try writeJsonParseScalarExtensionField(file, field, writer, depth),
        .message, .group => |type_name| return try writeJsonParseMessageExtensionField(ctx, field, type_name, writer, depth),
        else => return,
    }
}

fn writeJsonParseScalarExtensionField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("if (");
    try writeExtensionJsonKeyCondition(file, field, writer);
    try writer.writeAll(") {\n");
    if (field.cardinality == .repeated) {
        try indent(writer, depth + 1);
        try writer.writeAll("try self.clearUnknownFieldsByNumber(allocator, ");
        try writeExtensionHelperReference(field, writer);
        try writer.writeAll(".number);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const array = switch (value) { .array => |array| array, else => return error.TypeMismatch };\n");
        try indent(writer, depth + 1);
        try writer.writeAll("for (array.items) |item| {\n");
        try indent(writer, depth + 2);
        if (field.kind == .enumeration) {
            try writer.writeAll("const parsed_enum = ");
            try writeJsonParseEnumExpr(file, field.kind.enumeration, "item", writer);
            try writer.writeAll(" catch |err| { if (options.ignore_unknown_fields) continue; return err; };\n");
            try indent(writer, depth + 2);
            try writer.writeAll("try ");
            try writeExtensionHelperReference(field, writer);
            try writer.writeAll(".appendToUnknown(self, allocator, parsed_enum);\n");
        } else {
            try writer.writeAll("try ");
            try writeExtensionHelperReference(field, writer);
            try writer.writeAll(".appendToUnknown(self, allocator, ");
            try writeJsonParseValueExpr(file, field.kind, "item", "arena_allocator", writer);
            try writer.writeAll(");\n");
        }
        try indent(writer, depth + 1);
        try writer.writeAll("}\n");
    } else {
        try indent(writer, depth + 1);
        try writer.writeAll("try ");
        try writeExtensionHelperReference(field, writer);
        try writer.writeAll(".replaceInUnknown(self, allocator, ");
        if (field.kind == .enumeration) {
            try writeJsonParseEnumExpr(file, field.kind.enumeration, "value", writer);
            try writer.writeAll(" catch |err| { if (options.ignore_unknown_fields) continue; return err; }");
        } else {
            try writeJsonParseValueExpr(file, field.kind, "value", "arena_allocator", writer);
        }
        try writer.writeAll(");\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("continue;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeJsonParseMessageExtensionField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, type_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    if (!codegenCanReferenceMessageWithContext(ctx, type_name)) return;
    try indent(writer, depth);
    try writer.writeAll("if (");
    try writeExtensionJsonKeyCondition(file, field, writer);
    try writer.writeAll(") {\n");
    if (field.cardinality == .repeated) {
        try indent(writer, depth + 1);
        try writer.writeAll("try self.clearUnknownFieldsByNumber(allocator, ");
        try writeExtensionHelperReference(field, writer);
        try writer.writeAll(".number);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const array = switch (value) { .array => |array| array, else => return error.TypeMismatch };\n");
        try indent(writer, depth + 1);
        try writer.writeAll("for (array.items) |item| {\n");
        try indent(writer, depth + 2);
        try writer.writeAll("var nested = try ");
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
        try writer.writeAll(".jsonParseValueWithOptions(arena_allocator, arena_allocator, item, .{ .ignore_unknown_fields = options.ignore_unknown_fields });\n");
        try indent(writer, depth + 2);
        try writer.writeAll("defer nested.deinit(arena_allocator);\n");
        try indent(writer, depth + 2);
        try writer.writeAll("try ");
        try writeExtensionHelperReference(field, writer);
        try writer.writeAll(".appendToUnknown(self, allocator, try nested.encode(arena_allocator));\n");
        try indent(writer, depth + 1);
        try writer.writeAll("}\n");
    } else {
        try indent(writer, depth + 1);
        try writer.writeAll("var nested = try ");
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
        try writer.writeAll(".jsonParseValueWithOptions(arena_allocator, arena_allocator, value, .{ .ignore_unknown_fields = options.ignore_unknown_fields });\n");
        try indent(writer, depth + 1);
        try writer.writeAll("defer nested.deinit(arena_allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try ");
        try writeExtensionHelperReference(field, writer);
        try writer.writeAll(".replaceInUnknown(self, allocator, try nested.encode(arena_allocator));\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("continue;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeJsonParseMapField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    const map_type = switch (field.kind) {
        .map => |map| map,
        else => return,
    };
    if (!jsonMapValueSupported(ctx, map_type.value.*)) return;
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
    if (typedMapMessageValueWithContext(ctx, field)) |_| {
        try writer.writeAll("defer list.deinit(allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("errdefer for (list.items) |list_entry| { var old_value = list_entry.value; old_value.deinit(allocator); };\n");
    } else {
        try writer.writeAll("defer list.deinit(allocator);\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("var map_it = object_value.iterator();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("while (map_it.next()) |map_entry| {\n");
    try indent(writer, depth + 2);
    if (map_type.value.* == .enumeration) {
        try writer.writeAll("const parsed_value = ");
        try writeJsonParseEnumExpr(file, map_type.value.enumeration, "map_entry.value_ptr.*", writer);
        try writer.writeAll(" catch |err| { if (options.ignore_unknown_fields) continue; return err; };\n");
        try indent(writer, depth + 2);
        try writer.writeAll("try @This().");
        try writeQuotedIdentWithPrefix(field.name, "appendOrReplaceMapEntry_", writer);
        try writer.writeAll("(allocator, &list, .{ .key = ");
        try writeJsonParseMapKeyExpr(map_type.key, "map_entry.key_ptr.*", writer);
        try writer.writeAll(", .value = parsed_value });\n");
    } else {
        try writer.writeAll("try @This().");
        try writeQuotedIdentWithPrefix(field.name, "appendOrReplaceMapEntry_", writer);
        try writer.writeAll("(allocator, &list, .{ .key = ");
        try writeJsonParseMapKeyExpr(map_type.key, "map_entry.key_ptr.*", writer);
        try writer.writeAll(", .value = ");
        try writeJsonParseMapValueExpr(ctx, field, map_type.value.*, "map_entry.value_ptr.*", "arena_allocator", writer);
        try writer.writeAll(" });\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("@This().");
    try writeQuotedIdentWithPrefix(field.name, "deinitMap_", writer);
    try writer.writeAll("(allocator, &self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(");\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".ensureUnusedCapacity(allocator, list.items.len);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("for (list.items) |list_entry| try @This().");
    try writeQuotedIdentWithPrefix(field.name, "putMapEntry_", writer);
    try writer.writeAll("(allocator, &self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(", list_entry);\n");
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

fn writeJsonParseOneofField(ctx: *const CodegenContext, oneof: schema.OneofDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    switch (field.kind) {
        .scalar, .enumeration, .message, .group => {},
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
    const maybe_message_type = switch (field.kind) {
        .message, .group => |type_name| type_name,
        else => null,
    };
    if (maybe_message_type) |type_name| {
        if (codegenCanReferenceMessageWithContext(ctx, type_name)) {
            if (typedOneofMessageFieldWithContext(ctx, field)) |_| {
                try writer.writeAll("blk: { var nested = try ");
                try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
                try writer.writeAll(".jsonParseValueWithOptions(allocator, arena_allocator, value, .{ .ignore_unknown_fields = options.ignore_unknown_fields }); errdefer nested.deinit(allocator); break :blk nested; }");
            } else {
                try writer.writeAll("blk: { var nested = try ");
                try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
                try writer.writeAll(".jsonParseValueWithOptions(arena_allocator, arena_allocator, value, .{ .ignore_unknown_fields = options.ignore_unknown_fields }); defer nested.deinit(arena_allocator); break :blk try nested.encode(arena_allocator); }");
            }
        } else {
            try writeJsonParseValueExpr(file, field.kind, "value", "arena_allocator", writer);
        }
    } else if (field.kind == .enumeration) {
        try writeJsonParseEnumExpr(file, field.kind.enumeration, "value", writer);
        try writer.writeAll(" catch |err| { if (options.ignore_unknown_fields) continue; return err; }");
    } else {
        try writeJsonParseValueExpr(file, field.kind, "value", "arena_allocator", writer);
    }
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
    } else {
        try writer.writeAll(" or std.mem.eql(u8, key, ");
        try writeZigLowerCamelStringLiteral(field.name, writer);
        try writer.writeAll(")");
    }
}

fn writeExtensionJsonKeyCondition(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    try writer.writeAll("std.mem.eql(u8, key, ");
    try writeExtensionTextNameLiteral(file, field, true, writer);
    try writer.writeAll(")");
    if (extensionHasLeafAlias(file, field)) {
        try writer.writeAll(" or std.mem.eql(u8, key, ");
        try writeExtensionTextNameLiteral(file, field, false, writer);
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
            try writer.writeAll(", ");
            try writer.writeAll(if (enumIsClosed(file, name)) "true" else "false");
            try writer.writeAll(")");
        },
        else => try writer.writeAll("@compileError(\"unsupported JSON parse field kind\")"),
    }
}

fn writeJsonParseEnumExpr(file: *const schema.FileDescriptor, enum_name: []const u8, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.print("@This().jsonEnum({s}, ", .{value_expr});
    try writeEnumNameArray(file, enum_name, writer);
    try writer.writeAll(", ");
    try writeEnumNumberArray(file, enum_name, writer);
    try writer.writeAll(", ");
    try writer.writeAll(if (enumIsClosed(file, enum_name)) "true" else "false");
    try writer.writeAll(")");
}

fn writeJsonParseMapValueExpr(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, kind: schema.FieldKind, value_expr: []const u8, arena_expr: []const u8, writer: *std.Io.Writer) Error!void {
    const file = ctx.file;
    switch (kind) {
        .message => |name| if (codegenCanReferenceMessageWithContext(ctx, name)) {
            if (typedMapMessageValueWithContext(ctx, field)) |_| {
                try writer.writeAll("blk: { var nested = try ");
                try writeMessageTypeReferenceWithContext(ctx, name, writer);
                try writer.writeAll(".jsonParseValueWithOptions(allocator, ");
                try writer.writeAll(arena_expr);
                try writer.writeAll(", ");
                try writer.writeAll(value_expr);
                try writer.writeAll(", .{ .ignore_unknown_fields = options.ignore_unknown_fields }); errdefer nested.deinit(allocator");
                try writer.writeAll("); break :blk nested; }");
            } else {
                try writer.writeAll("blk: { var nested = try ");
                try writeMessageTypeReferenceWithContext(ctx, name, writer);
                try writer.writeAll(".jsonParseValueWithOptions(");
                try writer.writeAll(arena_expr);
                try writer.writeAll(", ");
                try writer.writeAll(arena_expr);
                try writer.writeAll(", ");
                try writer.writeAll(value_expr);
                try writer.writeAll(", .{ .ignore_unknown_fields = options.ignore_unknown_fields }); defer nested.deinit(");
                try writer.writeAll(arena_expr);
                try writer.writeAll("); break :blk try nested.encode(");
                try writer.writeAll(arena_expr);
                try writer.writeAll("); }");
            }
        } else try writer.writeAll("@compileError(\"unsupported JSON parse field kind\")"),
        else => try writeJsonParseValueExpr(file, kind, value_expr, arena_expr, writer),
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

fn enumIsClosed(file: *const schema.FileDescriptor, name: []const u8) bool {
    if (file.findEnumDeep(name)) |enumeration| {
        if (enumeration.features) |features| return features.enum_type == .closed;
    }
    return file.features.enum_type == .closed;
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
        \\        .number_string => |text| try std.fmt.parseFloat(T, text),
        \\        .string => |text| if (std.mem.eql(u8, text, "NaN"))
        \\            std.math.nan(T)
        \\        else if (std.mem.eql(u8, text, "Infinity"))
        \\            std.math.inf(T)
        \\        else if (std.mem.eql(u8, text, "-Infinity"))
        \\            -std.math.inf(T)
        \\        else
        \\            try std.fmt.parseFloat(T, text),
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
        \\    return try @This().jsonDecodeBase64(allocator, try @This().jsonString(value));
        \\}
        \\
        \\fn jsonEnum(value: std.json.Value, comptime names: []const []const u8, comptime numbers: []const i32, comptime closed: bool) !i32 {
        \\    return switch (value) {
        \\        .integer => |v| try @This().jsonEnumNumber(std.math.cast(i32, v) orelse return error.Overflow, numbers, closed),
        \\        .number_string => |text| try @This().jsonEnumNumber(try std.fmt.parseInt(i32, text, 10), numbers, closed),
        \\        .string => |text| {
        \\            inline for (names, 0..) |name, i| {
        \\                if (std.mem.eql(u8, text, name)) return numbers[i];
        \\            }
        \\            return try @This().jsonEnumNumber(std.fmt.parseInt(i32, text, 10) catch return error.InvalidEnumValue, numbers, closed);
        \\        },
        \\        else => error.TypeMismatch,
        \\    };
        \\}
        \\
        \\fn jsonEnumNumber(value: i32, comptime numbers: []const i32, comptime closed: bool) !i32 {
        \\    if (closed) {
        \\        inline for (numbers) |number| {
        \\            if (value == number) return value;
        \\        }
        \\        return error.InvalidEnumValue;
        \\    }
        \\    return value;
        \\}
        \\
        \\fn jsonWriteEnum(writer: *std.Io.Writer, value: i32, comptime names: []const []const u8, comptime numbers: []const i32, enum_as_name: bool) !void {
        \\    if (!enum_as_name) return try writer.print("{d}", .{value});
        \\    inline for (numbers, 0..) |number, i| {
        \\        if (value == number) return try std.json.Stringify.value(names[i], .{}, writer);
        \\    }
        \\    try writer.print("{d}", .{value});
        \\}
        \\
        \\fn textWriteEnum(writer: *std.Io.Writer, value: i32, comptime names: []const []const u8, comptime numbers: []const i32, enum_as_name: bool) !void {
        \\    if (!enum_as_name) return try writer.print("{d}", .{value});
        \\    inline for (numbers, 0..) |number, i| {
        \\        if (value == number) return try writer.writeAll(names[i]);
        \\    }
        \\    try writer.print("{d}", .{value});
        \\}
        \\
        \\fn enumKnown(value: i32, comptime numbers: []const i32) bool {
        \\    inline for (numbers) |number| {
        \\        if (value == number) return true;
        \\    }
        \\    return false;
        \\}
        \\
        \\fn textFieldValue(line: []const u8, comptime name: []const u8) ?[]const u8 {
        \\    if (!std.mem.startsWith(u8, line, name)) return null;
        \\    var rest = line[name.len..];
        \\    rest = std.mem.trimStart(u8, rest, " \t");
        \\    if (rest.len == 0 or rest[0] != ':') return null;
        \\    return std.mem.trim(u8, rest[1..], " \t\r");
        \\}
        \\
        \\fn textBlockField(line: []const u8, comptime name: []const u8) bool {
        \\    if (!std.mem.startsWith(u8, line, name)) return false;
        \\    var rest = std.mem.trimStart(u8, line[name.len..], " \t");
        \\    if (rest.len != 0 and rest[0] == ':') {
        \\        rest = std.mem.trimStart(u8, rest[1..], " \t");
        \\    }
        \\    return std.mem.eql(u8, rest, "{") or std.mem.eql(u8, rest, "<");
        \\}
        \\
        \\fn textNormalizeSeparators(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
        \\    var out: std.ArrayList(u8) = .empty;
        \\    errdefer out.deinit(allocator);
        \\    var quote: ?u8 = null;
        \\    var escaped = false;
        \\    for (text) |c| {
        \\        if (escaped) {
        \\            escaped = false;
        \\            try out.append(allocator, c);
        \\            continue;
        \\        }
        \\        if (quote) |q| {
        \\            if (c == '\\') {
        \\                escaped = true;
        \\            } else if (c == q) {
        \\                quote = null;
        \\            }
        \\            try out.append(allocator, c);
        \\            continue;
        \\        }
        \\        if (c == '"' or c == '\'') {
        \\            quote = c;
        \\            try out.append(allocator, c);
        \\        } else if (c == ';' or c == ',') {
        \\            try out.append(allocator, '\n');
        \\        } else if (c == '{' or c == '<') {
        \\            try out.append(allocator, c);
        \\            try out.append(allocator, '\n');
        \\        } else if (c == '}' or c == '>') {
        \\            try out.append(allocator, '\n');
        \\            try out.append(allocator, c);
        \\            try out.append(allocator, '\n');
        \\        } else {
        \\            try out.append(allocator, c);
        \\        }
        \\    }
        \\    return try out.toOwnedSlice(allocator);
        \\}
        \\
        \\fn textNeedsSeparatorNormalization(text: []const u8) bool {
        \\    var quote: ?u8 = null;
        \\    var escaped = false;
        \\    for (text, 0..) |c, index| {
        \\        if (escaped) {
        \\            escaped = false;
        \\            continue;
        \\        }
        \\        if (quote) |q| {
        \\            if (c == '\\') {
        \\                escaped = true;
        \\            } else if (c == q) {
        \\                quote = null;
        \\            }
        \\            continue;
        \\        }
        \\        if (c == '"' or c == '\'') {
        \\            quote = c;
        \\        } else if (c == ';' or c == ',') {
        \\            return true;
        \\        } else if ((c == '{' or c == '<') and !@This().textSeparatorHasLineAfter(text, index)) {
        \\            return true;
        \\        } else if ((c == '}' or c == '>') and !@This().textSeparatorHasLineBefore(text, index)) {
        \\            return true;
        \\        }
        \\    }
        \\    return false;
        \\}
        \\
        \\fn textSeparatorHasLineAfter(text: []const u8, index: usize) bool {
        \\    var i = index + 1;
        \\    while (i < text.len and (text[i] == ' ' or text[i] == '\t' or text[i] == '\r')) : (i += 1) {}
        \\    return i >= text.len or text[i] == '\n';
        \\}
        \\
        \\fn textSeparatorHasLineBefore(text: []const u8, index: usize) bool {
        \\    var i = index;
        \\    while (i > 0 and (text[i - 1] == ' ' or text[i - 1] == '\t' or text[i - 1] == '\r')) : (i -= 1) {}
        \\    return i == 0 or text[i - 1] == '\n';
        \\}
        \\
        \\fn textCleanLine(raw_line: []const u8) []const u8 {
        \\    var end = raw_line.len;
        \\    var quote: ?u8 = null;
        \\    var escaped = false;
        \\    for (raw_line, 0..) |c, i| {
        \\        if (escaped) {
        \\            escaped = false;
        \\            continue;
        \\        }
        \\        if (quote) |q| {
        \\            if (c == '\\') {
        \\                escaped = true;
        \\            } else if (c == q) {
        \\                quote = null;
        \\            }
        \\            continue;
        \\        }
        \\        if (c == '"' or c == '\'') {
        \\            quote = c;
        \\        } else if (c == '#') {
        \\            end = i;
        \\            break;
        \\        }
        \\    }
        \\    var line = std.mem.trim(u8, raw_line[0..end], " \t\r");
        \\    while (line.len != 0 and (line[line.len - 1] == ';' or line[line.len - 1] == ',')) {
        \\        line = std.mem.trim(u8, line[0 .. line.len - 1], " \t\r");
        \\    }
        \\    return line;
        \\}
        \\
        \\fn textBool(value: []const u8) !bool {
        \\    if (std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "t") or std.mem.eql(u8, value, "1")) return true;
        \\    if (std.mem.eql(u8, value, "false") or std.mem.eql(u8, value, "f") or std.mem.eql(u8, value, "0")) return false;
        \\    return error.TypeMismatch;
        \\}
        \\
        \\fn textInt(comptime T: type, value: []const u8) !T {
        \\    return try std.fmt.parseInt(T, value, 0);
        \\}
        \\
        \\fn textFloat(comptime T: type, value: []const u8) !T {
        \\    var body = value;
        \\    var negative = false;
        \\    if (body.len != 0 and (body[0] == '-' or body[0] == '+')) {
        \\        negative = body[0] == '-';
        \\        body = body[1..];
        \\    }
        \\    if (std.ascii.eqlIgnoreCase(body, "nan")) return std.math.nan(T);
        \\    if (std.ascii.eqlIgnoreCase(body, "inf") or std.ascii.eqlIgnoreCase(body, "infinity")) {
        \\        const parsed = std.math.inf(T);
        \\        return if (negative) -parsed else parsed;
        \\    }
        \\    return try std.fmt.parseFloat(T, value);
        \\}
        \\
        \\fn textUnquote(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
        \\    var out: std.ArrayList(u8) = .empty;
        \\    errdefer out.deinit(allocator);
        \\    var i: usize = 0;
        \\    var read_quoted = false;
        \\    while (true) {
        \\        while (i < value.len and std.ascii.isWhitespace(value[i])) : (i += 1) {}
        \\        if (i >= value.len) break;
        \\        const quote = value[i];
        \\        if (quote != '"' and quote != '\'') {
        \\            if (read_quoted) return error.InvalidEscape;
        \\            try out.appendSlice(allocator, value[i..]);
        \\            break;
        \\        }
        \\        read_quoted = true;
        \\        i += 1;
        \\        var closed = false;
        \\        while (i < value.len) {
        \\            const c = value[i];
        \\            i += 1;
        \\            if (c == quote) {
        \\                closed = true;
        \\                break;
        \\            }
        \\            if (c != '\\') {
        \\                try out.append(allocator, c);
        \\                continue;
        \\            }
        \\            if (i >= value.len) return error.InvalidEscape;
        \\            const esc = value[i];
        \\            i += 1;
        \\            switch (esc) {
        \\                'n' => try out.append(allocator, '\n'),
        \\                'r' => try out.append(allocator, '\r'),
        \\                't' => try out.append(allocator, '\t'),
        \\                'a' => try out.append(allocator, 0x07),
        \\                'b' => try out.append(allocator, 0x08),
        \\                'f' => try out.append(allocator, 0x0c),
        \\                'v' => try out.append(allocator, 0x0b),
        \\                '\\' => try out.append(allocator, '\\'),
        \\                '"' => try out.append(allocator, '"'),
        \\                '\'' => try out.append(allocator, '\''),
        \\                '?' => try out.append(allocator, '?'),
        \\                'x', 'X' => {
        \\                    const start = i;
        \\                    var end = i;
        \\                    while (end < value.len and end < start + 2 and @This().textHexDigit(value[end]) != null) : (end += 1) {}
        \\                    if (end == start) return error.InvalidEscape;
        \\                    try out.append(allocator, try std.fmt.parseInt(u8, value[start..end], 16));
        \\                    i = end;
        \\                },
        \\                '0'...'7' => {
        \\                    const start = i - 1;
        \\                    var end = i;
        \\                    while (end < value.len and end < start + 3 and value[end] >= '0' and value[end] <= '7') : (end += 1) {}
        \\                    try out.append(allocator, try std.fmt.parseInt(u8, value[start..end], 8));
        \\                    i = end;
        \\                },
        \\                else => |unknown| try out.append(allocator, unknown),
        \\            }
        \\        }
        \\        if (!closed) return error.InvalidEscape;
        \\    }
        \\    return try out.toOwnedSlice(allocator);
        \\}
        \\
        \\fn textHexDigit(c: u8) ?u8 {
        \\    return switch (c) {
        \\        '0'...'9' => c - '0',
        \\        'a'...'f' => c - 'a' + 10,
        \\        'A'...'F' => c - 'A' + 10,
        \\        else => null,
        \\    };
        \\}
        \\
        \\fn textEnum(value: []const u8, comptime names: []const []const u8, comptime numbers: []const i32, comptime closed: bool) !i32 {
        \\    inline for (names, 0..) |name, i| {
        \\        if (std.mem.eql(u8, value, name)) return numbers[i];
        \\    }
        \\    const number = try std.fmt.parseInt(i32, value, 10);
        \\    if (closed) {
        \\        inline for (numbers) |known| {
        \\            if (number == known) return number;
        \\        }
        \\        return error.InvalidEnumValue;
        \\    }
        \\    return number;
        \\}
        \\
        \\fn textUnknownField(allocator: std.mem.Allocator, line: []const u8) !?[]const u8 {
        \\    var colon_index: ?usize = null;
        \\    for (line, 0..) |c, i| {
        \\        if (c == ':') { colon_index = i; break; }
        \\        if (i == 0 and !std.ascii.isDigit(c)) return null;
        \\        if (i != 0 and !std.ascii.isDigit(c)) return null;
        \\    }
        \\    const idx = colon_index orelse return null;
        \\    const number = try std.fmt.parseInt(pbz.FieldNumber, std.mem.trim(u8, line[0..idx], " \t\r"), 10);
        \\    const value = std.mem.trim(u8, line[idx + 1 ..], " \t\r");
        \\    var raw = pbz.Writer.init(allocator);
        \\    defer raw.deinit();
        \\    if (value.len >= 2 and ((value[0] == '"' and value[value.len - 1] == '"') or (value[0] == '\'' and value[value.len - 1] == '\''))) {
        \\        const bytes = try @This().textUnquote(allocator, value);
        \\        defer allocator.free(bytes);
        \\        try raw.writeBytes(number, bytes);
        \\    } else {
        \\        try raw.writeUInt64(number, try std.fmt.parseInt(u64, value, 0));
        \\    }
        \\    return try raw.toOwnedSlice();
        \\}
        \\
        \\fn textUnknownGroup(allocator: std.mem.Allocator, line: []const u8, lines: anytype) !?[]const u8 {
        \\    var end: usize = 0;
        \\    while (end < line.len and std.ascii.isDigit(line[end])) : (end += 1) {}
        \\    if (end == 0) return null;
        \\    const rest = std.mem.trim(u8, line[end..], " \t\r");
        \\    if (!std.mem.eql(u8, rest, "{") and !std.mem.eql(u8, rest, "<")) return null;
        \\    const number = try std.fmt.parseInt(pbz.FieldNumber, line[0..end], 10);
        \\    var raw = pbz.Writer.init(allocator);
        \\    defer raw.deinit();
        \\    try raw.writeTag(number, .start_group);
        \\    while (lines.next()) |raw_line| {
        \\        const child = @This().textCleanLine(raw_line);
        \\        if (child.len == 0) continue;
        \\        if (std.mem.eql(u8, child, "}") or std.mem.eql(u8, child, ">")) {
        \\            try raw.writeTag(number, .end_group);
        \\            return try raw.toOwnedSlice();
        \\        }
        \\        if (try @This().textUnknownField(allocator, child)) |field_raw| {
        \\            defer allocator.free(field_raw);
        \\            try raw.appendSlice(field_raw);
        \\            continue;
        \\        }
        \\        if (try @This().textUnknownGroup(allocator, child, lines)) |group_raw| {
        \\            defer allocator.free(group_raw);
        \\            try raw.appendSlice(group_raw);
        \\            continue;
        \\        }
        \\        return error.UnknownField;
        \\    }
        \\    return error.UnexpectedEof;
        \\}
        \\
        \\fn textWriteUnknownRaw(raw: []const u8, writer: *std.Io.Writer) !void {
        \\    var r = pbz.Reader.init(raw);
        \\    while (try r.nextTag()) |tag| try @This().textWriteUnknownField(tag, &r, writer);
        \\}
        \\
        \\fn textWriteQuotedBytes(bytes: []const u8, writer: *std.Io.Writer) !void {
        \\    try writer.writeByte('"');
        \\    for (bytes) |c| {
        \\        if (c == '\\') try writer.writeAll("\\\\") else if (c == '"') try writer.writeAll("\\\"") else if (c == '\n') try writer.writeAll("\\n") else if (c == '\r') try writer.writeAll("\\r") else if (c == '\t') try writer.writeAll("\\t") else if (c >= 0x20 and c <= 0x7e) try writer.writeByte(c) else try writer.print("\\{o:0>3}", .{c});
        \\    }
        \\    try writer.writeByte('"');
        \\}
        \\
        \\fn textWriteUnknownField(tag: pbz.wire.Tag, r: *pbz.Reader, writer: *std.Io.Writer) !void {
        \\    switch (tag.wire_type) {
        \\        .varint => try writer.print("{d}: {d}\n", .{ tag.number, try r.readVarint() }),
        \\        .fixed32 => try writer.print("{d}: {d}\n", .{ tag.number, try r.readFixed32() }),
        \\        .fixed64 => try writer.print("{d}: {d}\n", .{ tag.number, try r.readFixed64() }),
        \\        .length_delimited => {
        \\            try writer.print("{d}: ", .{tag.number});
        \\            try @This().textWriteQuotedBytes(try r.readBytes(), writer);
        \\            try writer.writeByte('\n');
        \\        },
        \\        .start_group => {
        \\            try writer.print("{d} {{\n", .{tag.number});
        \\            while (try r.nextTag()) |inner| {
        \\                if (inner.wire_type == .end_group) {
        \\                    if (inner.number != tag.number) return error.InvalidFieldNumber;
        \\                    try writer.writeAll("}\n");
        \\                    return;
        \\                }
        \\                try @This().textWriteUnknownField(inner, r, writer);
        \\            }
        \\            return error.TruncatedInput;
        \\        },
        \\        .end_group => return error.InvalidWireType,
        \\    }
        \\}
        \\
        \\fn textBlock(allocator: std.mem.Allocator, lines: anytype) ![]u8 {
        \\    var out: std.Io.Writer.Allocating = .init(allocator);
        \\    errdefer out.deinit();
        \\    var depth: usize = 1;
        \\    while (lines.next()) |raw_line| {
        \\        const line = @This().textCleanLine(raw_line);
        \\        if (line.len == 0) continue;
        \\        if (std.mem.eql(u8, line, "}") or std.mem.eql(u8, line, ">")) {
        \\            depth -= 1;
        \\            if (depth == 0) return try out.toOwnedSlice();
        \\        }
        \\        if (std.mem.endsWith(u8, line, "{") or std.mem.endsWith(u8, line, "<")) depth += 1;
        \\        try out.writer.writeAll(line);
        \\        try out.writer.writeByte('\n');
        \\    }
        \\    return error.UnexpectedEof;
        \\}
        \\
        \\fn jsonDecodeBase64(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
        \\    return @This().jsonDecodeBase64With(allocator, &std.base64.standard.Decoder, value) catch
        \\        @This().jsonDecodeBase64With(allocator, &std.base64.url_safe.Decoder, value) catch
        \\        @This().jsonDecodeBase64With(allocator, &std.base64.standard_no_pad.Decoder, value) catch
        \\        @This().jsonDecodeBase64With(allocator, &std.base64.url_safe_no_pad.Decoder, value);
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
        \\fn jsonWriteString(writer: *std.Io.Writer, value: []const u8) !void {
        \\    if (!pbz.validateUtf8(value)) return error.InvalidUtf8;
        \\    try std.json.Stringify.value(value, .{}, writer);
        \\}
        \\
    );
}

fn writeJsonField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    switch (field.kind) {
        .scalar => |scalar| try writeJsonScalarField(file, field, scalar, writer, depth),
        .enumeration => |name| try writeJsonEnumField(file, field, name, writer, depth),
        .map => try writeJsonMapField(ctx, field, writer, depth),
        .message, .group => |name| try writeJsonMessageField(ctx, field, name, writer, depth),
    }
}

fn writeJsonPrefix(field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("if (!first) try writer.writeAll(\",\"); first = false;\n");
    try indent(writer, depth);
    try writer.writeAll("try writer.writeAll(if (options.preserve_proto_field_names) \"\\\"");
    try writeEscapedStringContents(field.name, writer);
    try writer.writeAll("\\\":\" else \"\\\"");
    try writeJsonFieldNameLiteralContents(field, writer);
    try writer.writeAll("\\\":\");\n");
}

fn writeJsonScalarField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, scalar: schema.ScalarType, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        try writer.writeAll("if (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(".len != 0 or options.always_print_primitive_fields) {\n");
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
        if (hasPresence(file, field.*)) {
            try writer.writeAll("if (self.");
            try writePresenceIdent(field.name, writer);
            if (isRequired(field.*)) {
                try writer.writeAll(") {\n");
            } else {
                try writer.writeAll(" or options.always_print_primitive_fields) {\n");
            }
        } else {
            try writer.writeAll("if (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(defaultSkipConditionWithOptions(scalar));
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

fn writeJsonEnumField(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, enum_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        try writer.writeAll("if (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(".len != 0 or options.always_print_primitive_fields) {\n");
        try writeJsonPrefix(field, writer, depth + 1);
        try indent(writer, depth + 1);
        try writer.writeAll("try writer.writeAll(\"[\");\n");
        try indent(writer, depth + 1);
        try writer.writeAll("for (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(", 0..) |item, i| { if (i != 0) try writer.writeAll(\",\"); ");
        try writeJsonEnumValue(file, enum_name, "item", writer);
        try writer.writeAll("; }\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try writer.writeAll(\"]\");\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");
    } else {
        try indent(writer, depth);
        if (hasPresence(file, field.*)) {
            try writer.writeAll("if (self.");
            try writePresenceIdent(field.name, writer);
            if (isRequired(field.*)) {
                try writer.writeAll(") {\n");
            } else {
                try writer.writeAll(" or options.always_print_primitive_fields) {\n");
            }
        } else {
            try writer.writeAll("if (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(" != 0 or options.always_print_primitive_fields) {\n");
        }
        try writeJsonPrefix(field, writer, depth + 1);
        try indent(writer, depth + 1);
        try writer.writeAll("const value = self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(";\n");
        try indent(writer, depth + 1);
        try writeJsonEnumValue(file, enum_name, "value", writer);
        try writer.writeAll(";\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");
    }
}

fn writeJsonMapField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const map_type = switch (field.kind) {
        .map => |map| map,
        else => return,
    };
    if (!jsonMapValueSupported(ctx, map_type.value.*)) return;
    try indent(writer, depth);
    try writer.writeAll("if (self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".count() != 0 or options.always_print_primitive_fields) {\n");
    try writeJsonPrefix(field, writer, depth + 1);
    try indent(writer, depth + 1);
    try writer.writeAll("try writer.writeAll(\"{\");\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var map_it = self.");
    try writeQuotedIdent(field.name, writer);
    try writer.writeAll(".iterator();\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var i: usize = 0;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("while (map_it.next()) |map_entry| : (i += 1) {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("const entry = ");
    try writeQuotedIdentWithSuffix(field.name, "Entry", writer);
    try writer.writeAll("{ .key = map_entry.key_ptr.*, .value = map_entry.value_ptr.* };\n");
    try indent(writer, depth + 2);
    try writer.writeAll("if (i != 0) try writer.writeAll(\",\");\n");
    try indent(writer, depth + 2);
    try writeJsonMapKeyValue(map_type.key, "entry.key", writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 2);
    try writer.writeAll("try writer.writeAll(\":\");\n");
    try indent(writer, depth + 2);
    try writeJsonMapEntryValue(ctx, field, map_type.value.*, "entry.value", writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try writer.writeAll(\"}\");\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeJsonMessageField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, type_name: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    if (!codegenCanReferenceMessageWithContext(ctx, type_name)) return;
    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        try writer.writeAll("if (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(".len != 0 or options.always_print_primitive_fields) {\n");
        try writeJsonPrefix(field, writer, depth + 1);
        try indent(writer, depth + 1);
        try writer.writeAll("try writer.writeAll(\"[\");\n");
        try indent(writer, depth + 1);
        try writer.writeAll("for (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(", 0..) |item, i| {\n");
        try indent(writer, depth + 2);
        try writer.writeAll("if (i != 0) try writer.writeAll(\",\");\n");
        if (typedRepeatedMessageFieldWithContext(ctx, field)) |_| {
            try indent(writer, depth + 2);
            try writer.writeAll("try item.jsonStringifyWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name, .preserve_proto_field_names = options.preserve_proto_field_names, .always_print_primitive_fields = options.always_print_primitive_fields });\n");
        } else {
            try writeDecodeAndStringifyPayload(ctx, type_name, "item", writer, depth + 2);
        }
        try indent(writer, depth + 1);
        try writer.writeAll("}\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try writer.writeAll(\"]\");\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");
    } else {
        try indent(writer, depth);
        if (typedSingularMessageFieldWithContext(ctx, field)) |_| {
            try writer.writeAll("if (self.");
            try writeQuotedIdent(field.name, writer);
            try writer.writeAll(") |nested| {\n");
            try writeJsonPrefix(field, writer, depth + 1);
            try indent(writer, depth + 1);
            try writer.writeAll("try nested.jsonStringifyWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name, .preserve_proto_field_names = options.preserve_proto_field_names, .always_print_primitive_fields = options.always_print_primitive_fields });\n");
            try indent(writer, depth);
            try writer.writeAll("}\n");
            return;
        }
        try writer.writeAll("if (self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(".len != 0) {\n");
        try writeJsonPrefix(field, writer, depth + 1);
        try indent(writer, depth + 1);
        try writer.writeAll("var nested = try ");
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
        try writer.writeAll(".decode(allocator, self.");
        try writeQuotedIdent(field.name, writer);
        try writer.writeAll(");\n");
        try indent(writer, depth + 1);
        try writer.writeAll("defer nested.deinit(allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try nested.jsonStringifyWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name, .preserve_proto_field_names = options.preserve_proto_field_names, .always_print_primitive_fields = options.always_print_primitive_fields });\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");
    }
}

fn writeDecodeAndStringifyPayload(ctx: *const CodegenContext, type_name: []const u8, payload_expr: []const u8, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("var nested = try ");
    try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
    try writer.writeAll(".decode(allocator, ");
    try writer.writeAll(payload_expr);
    try writer.writeAll(");\n");
    try indent(writer, depth);
    try writer.writeAll("defer nested.deinit(allocator);\n");
    try indent(writer, depth);
    try writer.writeAll("try nested.jsonStringifyWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name, .preserve_proto_field_names = options.preserve_proto_field_names, .always_print_primitive_fields = options.always_print_primitive_fields });\n");
}

fn jsonMapValueSupported(ctx: *const CodegenContext, kind: schema.FieldKind) bool {
    return switch (kind) {
        .scalar, .enumeration => true,
        .message => |name| codegenCanReferenceMessageWithContext(ctx, name),
        else => false,
    };
}

fn writeJsonMapKeyValue(scalar: schema.ScalarType, key_expr: []const u8, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .string => try writer.print("try @This().jsonWriteString(writer, {s})", .{key_expr}),
        .bool => try writer.print("try writer.writeAll(if ({s}) \"\\\"true\\\"\" else \"\\\"false\\\"\")", .{key_expr}),
        .int32, .int64, .uint32, .uint64, .sint32, .sint64, .fixed32, .fixed64, .sfixed32, .sfixed64 => try writer.print("try writer.print(\"\\\"{{d}}\\\"\", .{{{s}}})", .{key_expr}),
        .double, .float, .bytes => try writer.writeAll("@compileError(\"invalid map key\")"),
    }
}

fn writeJsonMapEntryValue(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, kind: schema.FieldKind, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    const file = ctx.file;
    switch (kind) {
        .scalar => |scalar| try writeJsonScalarValue(scalar, value_expr, writer),
        .enumeration => |name| try writeJsonEnumValue(file, name, value_expr, writer),
        .message => |name| if (codegenCanReferenceMessageWithContext(ctx, name)) {
            if (typedMapMessageValueWithContext(ctx, field)) |_| {
                try writer.print("try {s}.jsonStringifyWithOptions(allocator, writer, .{{ .enum_as_name = options.enum_as_name, .preserve_proto_field_names = options.preserve_proto_field_names, .always_print_primitive_fields = options.always_print_primitive_fields }})", .{value_expr});
            } else {
                try writer.writeAll("var nested = try ");
                try writeMessageTypeReferenceWithContext(ctx, name, writer);
                try writer.writeAll(".decode(allocator, ");
                try writer.writeAll(value_expr);
                try writer.writeAll("); defer nested.deinit(allocator); try nested.jsonStringifyWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name, .preserve_proto_field_names = options.preserve_proto_field_names, .always_print_primitive_fields = options.always_print_primitive_fields })");
            }
        } else try writer.writeAll("@compileError(\"unsupported map JSON value\")"),
        else => try writer.writeAll("@compileError(\"unsupported map JSON value\")"),
    }
}

fn writeJsonOneof(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, oneof: schema.OneofDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
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
                    .enumeration => |enum_name| {
                        try writeJsonPrefix(field, writer, depth + 2);
                        try indent(writer, depth + 2);
                        try writeJsonEnumValue(file, enum_name, "value", writer);
                        try writer.writeAll(";\n");
                    },
                    .message, .group => |type_name| {
                        if (codegenCanReferenceMessageWithContext(ctx, type_name)) {
                            try writeJsonPrefix(field, writer, depth + 2);
                            if (typedOneofMessageFieldWithContext(ctx, field)) |_| {
                                try indent(writer, depth + 2);
                                try writer.writeAll("try value.jsonStringifyWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name, .preserve_proto_field_names = options.preserve_proto_field_names, .always_print_primitive_fields = options.always_print_primitive_fields });\n");
                            } else {
                                try writeDecodeAndStringifyPayload(ctx, type_name, "value", writer, depth + 2);
                            }
                        } else {
                            try indent(writer, depth + 2);
                            try writer.writeAll("_ = value;\n");
                        }
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

fn writeJsonExtensionFields(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    for (file.extensions.items) |*field| {
        if (extensionAppliesToMessage(file, message, field) and jsonExtensionSupportedWithContext(ctx, field)) try writeJsonExtensionField(ctx, field, writer, depth);
    }
    for (file.messages.items) |*scope| try writeJsonScopedExtensionFields(ctx, message, scope, writer, depth);
}

fn writeJsonScopedExtensionFields(ctx: *const CodegenContext, target: *const schema.MessageDescriptor, scope: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    for (scope.extensions.items) |*field| {
        if (extensionAppliesToMessage(file, target, field) and jsonExtensionSupportedWithContext(ctx, field)) try writeJsonExtensionField(ctx, field, writer, depth);
    }
    for (scope.messages.items) |*nested| try writeJsonScopedExtensionFields(ctx, target, nested, writer, depth);
}

fn writeJsonExtensionField(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    switch (field.kind) {
        .scalar, .enumeration => {},
        .message => |type_name| {
            if (!codegenCanReferenceMessageWithContext(ctx, type_name)) return;
        },
        else => return,
    }
    try indent(writer, depth);
    try writer.writeAll("{\n");
    try indent(writer, depth + 1);
    try writer.writeAll("const values = try ");
    try writeExtensionHelperReference(field, writer);
    try writer.writeAll(".decodeAllFromUnknown(self, allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("defer allocator.free(values);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (values.len != 0) {\n");
    try writeJsonExtensionPrefix(file, field, writer, depth + 2);
    if (field.cardinality == .repeated) {
        try indent(writer, depth + 2);
        try writer.writeAll("try writer.writeAll(\"[\");\n");
        try indent(writer, depth + 2);
        try writer.writeAll("for (values, 0..) |value, i| { if (i != 0) try writer.writeAll(\",\"); ");
        try writeJsonExtensionValue(ctx, field.kind, "value", writer);
        try writer.writeAll("; }\n");
        try indent(writer, depth + 2);
        try writer.writeAll("try writer.writeAll(\"]\");\n");
    } else {
        try indent(writer, depth + 2);
        try writer.writeAll("const value = values[values.len - 1];\n");
        try indent(writer, depth + 2);
        try writeJsonExtensionValue(ctx, field.kind, "value", writer);
        try writer.writeAll(";\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeJsonExtensionValue(ctx: *const CodegenContext, kind: schema.FieldKind, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    const file = ctx.file;
    switch (kind) {
        .scalar => |scalar| try writeJsonScalarValue(scalar, value_expr, writer),
        .enumeration => |name| try writeJsonEnumValue(file, name, value_expr, writer),
        .message, .group => |type_name| {
            try writer.writeAll("try struct { fn write(allocator_: std.mem.Allocator, writer_: *std.Io.Writer, options_: anytype, payload_: []const u8) !void { var nested = try ");
            try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
            try writer.writeAll(".decode(allocator_, payload_); defer nested.deinit(allocator_); try nested.jsonStringifyWithOptions(allocator_, writer_, .{ .enum_as_name = options_.enum_as_name, .preserve_proto_field_names = options_.preserve_proto_field_names, .always_print_primitive_fields = options_.always_print_primitive_fields }); } }.write(allocator, writer, options, ");
            try writer.writeAll(value_expr);
            try writer.writeAll(")");
        },
        else => try writer.writeAll("@compileError(\"unsupported JSON extension value\")"),
    }
}

fn writeJsonExtensionPrefix(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("if (!first) try writer.writeAll(\",\"); first = false;\n");
    try indent(writer, depth);
    try writer.writeAll("try writer.writeAll(\"\\\"[");
    try writeExtensionTextNameContents(file, field, true, writer);
    try writer.writeAll("]\\\":\");\n");
}

fn writeJsonScalarValue(scalar: schema.ScalarType, prefix: []const u8, writer: *std.Io.Writer) Error!void {
    switch (scalar) {
        .string => try writer.print("try @This().jsonWriteString(writer, {s})", .{prefix}),
        .bytes => try writer.print("try writer.writeByte('\"'); try std.base64.standard.Encoder.encodeWriter(writer, {s}); try writer.writeByte('\"')", .{prefix}),
        .int64, .uint64, .sint64, .fixed64, .sfixed64 => try writer.print("try writer.print(\"\\\"{{d}}\\\"\", .{{{s}}})", .{prefix}),
        .bool => try writer.print("try writer.writeAll(if ({s}) \"true\" else \"false\")", .{prefix}),
        .double, .float => try writer.print("if (std.math.isNan({s})) try writer.writeAll(\"\\\"NaN\\\"\") else if (std.math.isPositiveInf({s})) try writer.writeAll(\"\\\"Infinity\\\"\") else if (std.math.isNegativeInf({s})) try writer.writeAll(\"\\\"-Infinity\\\"\") else try writer.print(\"{{d}}\", .{{{s}}})", .{ prefix, prefix, prefix, prefix }),
        else => try writer.print("try writer.print(\"{{d}}\", .{{{s}}})", .{prefix}),
    }
}

fn writeJsonEnumValue(file: *const schema.FileDescriptor, enum_name: []const u8, value_expr: []const u8, writer: *std.Io.Writer) Error!void {
    try writer.print("try @This().jsonWriteEnum(writer, {s}, ", .{value_expr});
    try writeEnumNameArray(file, enum_name, writer);
    try writer.writeAll(", ");
    try writeEnumNumberArray(file, enum_name, writer);
    try writer.writeAll(", options.enum_as_name");
    try writer.writeAll(")");
}

fn writeEnum(enumeration: *const schema.EnumDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub const ");
    try writeQuotedIdent(enumeration.name, writer);
    try writer.writeAll(" = enum(i32) {\n");
    for (enumeration.values.items, 0..) |value, index| {
        if (enumFirstValueIndexForNumber(enumeration, value.number) != index) continue;
        try indent(writer, depth + 1);
        try writeQuotedIdent(value.name, writer);
        try writer.print(" = {d},\n", .{value.number});
    }
    for (enumeration.values.items, 0..) |value, index| {
        const first_index = enumFirstValueIndexForNumber(enumeration, value.number) orelse continue;
        if (first_index == index) continue;
        const first = &enumeration.values.items[first_index];
        try indent(writer, depth + 1);
        try writer.writeAll("pub const ");
        try writeQuotedIdent(value.name, writer);
        try writer.writeAll(" = @This().");
        try writeQuotedIdent(first.name, writer);
        try writer.writeAll(";\n");
    }
    try writeEnumHelpers(enumeration, writer, depth + 1);
    try indent(writer, depth);
    try writer.writeAll("};\n\n");
}

fn writeEnumHelpers(enumeration: *const schema.EnumDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn fromInt(value: i32) ?@This() {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return switch (value) {\n");
    for (enumeration.values.items, 0..) |value, index| {
        if (enumFirstValueIndexForNumber(enumeration, value.number) != index) continue;
        try indent(writer, depth + 2);
        try writer.print("{d} => .", .{value.number});
        try writeQuotedIdent(value.name, writer);
        try writer.writeAll(",\n");
    }
    try indent(writer, depth + 2);
    try writer.writeAll("else => null,\n");
    try indent(writer, depth + 1);
    try writer.writeAll("};\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn toInt(self: @This()) i32 {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return @intFromEnum(self);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn protoName(self: @This()) []const u8 {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return switch (self) {\n");
    for (enumeration.values.items, 0..) |value, index| {
        if (enumFirstValueIndexForNumber(enumeration, value.number) != index) continue;
        try indent(writer, depth + 2);
        try writer.writeByte('.');
        try writeQuotedIdent(value.name, writer);
        try writer.writeAll(" => ");
        try writeZigStringLiteral(value.name, writer);
        try writer.writeAll(",\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("};\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn fromName(name: []const u8) ?@This() {\n");
    for (enumeration.values.items) |value| {
        const first_index = enumFirstValueIndexForNumber(enumeration, value.number) orelse continue;
        const first = &enumeration.values.items[first_index];
        try indent(writer, depth + 1);
        try writer.writeAll("if (std.mem.eql(u8, name, ");
        try writeZigStringLiteral(value.name, writer);
        try writer.writeAll(")) return .");
        try writeQuotedIdent(first.name, writer);
        try writer.writeAll(";\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("return null;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn jsonParse(value: std.json.Value) !@This() {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return switch (value) {\n");
    try indent(writer, depth + 2);
    try writer.writeAll(".string => |name| fromName(name) orelse error.InvalidEnumValue,\n");
    try indent(writer, depth + 2);
    try writer.writeAll(".integer => |number| fromInt(std.math.cast(i32, number) orelse return error.Overflow) orelse error.InvalidEnumValue,\n");
    try indent(writer, depth + 2);
    try writer.writeAll(".number_string => |text| fromInt(try std.fmt.parseInt(i32, text, 10)) orelse error.InvalidEnumValue,\n");
    try indent(writer, depth + 2);
    try writer.writeAll("else => error.TypeMismatch,\n");
    try indent(writer, depth + 1);
    try writer.writeAll("};\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn textParse(value: []const u8) !@This() {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("if (fromName(value)) |known| return known;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return fromInt(try std.fmt.parseInt(i32, value, 10)) orelse error.InvalidEnumValue;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn textFormat(self: @This(), writer: *std.Io.Writer) !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try writer.writeAll(self.protoName());\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn jsonStringify(self: @This(), writer: *std.Io.Writer) !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try std.json.Stringify.value(self.protoName(), .{}, writer);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn enumFirstValueIndexForNumber(enumeration: *const schema.EnumDescriptor, number: i32) ?usize {
    for (enumeration.values.items, 0..) |value, index| {
        if (value.number == number) return index;
    }
    return null;
}

fn writeExtensionMetadata(ctx: *const CodegenContext, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeMessageExtensions(ctx: *const CodegenContext, message: *const schema.MessageDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    for (message.extensions.items) |*field| try writeExtensionDecl(ctx, field, writer, depth);
    for (message.messages.items) |*nested| try writeMessageExtensions(ctx, nested, writer, depth);
}

fn writeExtensionDecl(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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
    try writeMessageTypeReferenceOrVoid(ctx, field.kind, writer);
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

fn extensionExtendeeHasTypeRef(ctx: *const CodegenContext, field: *const schema.FieldDescriptor) bool {
    return codegenCanReferenceMessageWithContext(ctx, field.extendee orelse return false);
}

fn writeExtensionTypedZigTypeLiteral(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    const type_name = switch (field.kind) {
        .message, .group => |name| name,
        else => return try writeZigStringLiteral(fieldType(field.*), writer),
    };
    if (!codegenCanReferenceMessageWithContext(ctx, type_name)) return try writeZigStringLiteral(fieldType(field.*), writer);
    var type_buf: std.Io.Writer.Allocating = .init(ctx.allocator);
    defer type_buf.deinit();
    if (field.cardinality == .repeated) try type_buf.writer.writeAll("[]const ");
    try writeMessageTypeReferenceWithContext(ctx, type_name, &type_buf.writer);
    try writeZigStringLiteral(type_buf.written(), writer);
}

fn writeExtensionExtendeeTypeRef(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer) Error!void {
    const extendee = field.extendee orelse return try writer.writeAll("void");
    if (codegenCanReferenceMessageWithContext(ctx, extendee)) {
        try writeMessageTypeReferenceWithContext(ctx, extendee, writer);
    } else {
        try writer.writeAll("void");
    }
}

fn writeExtensionFacadeHelpers(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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

fn writeExtensionEnumFacadeHelpers(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    if (field.cardinality == .repeated) {
        try indent(writer, depth);
        try writer.writeAll("pub fn getEnumsOn(message: ");
        try writeExtensionExtendeeTypeRef(ctx, field, writer);
        try writer.writeAll(", allocator: std.mem.Allocator) ![]");
        try writeEnumTypeReferenceWithContext(ctx, field.kind.enumeration, writer);
        try writer.writeAll(" {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const raw = try getOn(message, allocator);\n");
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
        try writer.writeAll("const raw = try allocator.alloc(i32, values.len);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("defer allocator.free(raw);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("for (values, 0..) |value, i| raw[i] = value.toInt();\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try appendAllOn(message, allocator, raw);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");

        try indent(writer, depth);
        try writer.writeAll("pub fn replaceAllEnumsOn(message: *");
        try writeExtensionExtendeeTypeRef(ctx, field, writer);
        try writer.writeAll(", allocator: std.mem.Allocator, values: []const ");
        try writeEnumTypeReferenceWithContext(ctx, field.kind.enumeration, writer);
        try writer.writeAll(") !void {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const raw = try allocator.alloc(i32, values.len);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("defer allocator.free(raw);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("for (values, 0..) |value, i| raw[i] = value.toInt();\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try replaceAllOn(message, allocator, raw);\n");
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
    try writer.writeAll("const raw = (try getOn(message, allocator)) orelse return null;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return ");
    try writeEnumTypeReferenceWithContext(ctx, field.kind.enumeration, writer);
    try writer.writeAll(".fromInt(raw);\n");
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

fn writeExtensionMessageFacadeHelpers(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
        try writer.writeAll(") !void {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const payload = try value.encode(allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("defer allocator.free(payload);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try appendToUnknown(message, allocator, payload);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");

        try indent(writer, depth);
        try writer.writeAll("pub fn getMessagesOn(message: ");
        try writeExtensionExtendeeTypeRef(ctx, field, writer);
        try writer.writeAll(", allocator: std.mem.Allocator) ![]");
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
        try writer.writeAll(" {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const payloads = try decodeAllFromUnknown(message, allocator);\n");
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
        try writer.writeAll("}\n");
    } else {
        try indent(writer, depth);
        try writer.writeAll("pub fn setMessageOn(message: *");
        try writeExtensionExtendeeTypeRef(ctx, field, writer);
        try writer.writeAll(", allocator: std.mem.Allocator, value: ");
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
        try writer.writeAll(") !void {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const payload = try value.encode(allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("defer allocator.free(payload);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try replaceInUnknown(message, allocator, payload);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");

        try indent(writer, depth);
        try writer.writeAll("pub fn getMessageOn(message: ");
        try writeExtensionExtendeeTypeRef(ctx, field, writer);
        try writer.writeAll(", allocator: std.mem.Allocator) !?");
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
        try writer.writeAll(" {\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const payload = (try decodeFirstFromUnknown(message, allocator)) orelse return null;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return try ");
        try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
        try writer.writeAll(".decode(allocator, payload);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");
    }
}

fn writeExtensionWriteHelpers(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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
    try writer.writeAll("const raw = try encodeRaw(allocator, value);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("defer allocator.free(raw);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try message.appendUnknownRaw(allocator, raw);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn hasInUnknown(message: anytype) !bool {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try message.hasUnknownFieldNumber(number);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn countInUnknown(message: anytype) !usize {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try message.unknownFieldCountByNumber(number);\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");

    try indent(writer, depth);
    try writer.writeAll("pub fn clearFromUnknown(message: anytype, allocator: std.mem.Allocator) !void {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("try message.clearUnknownFieldsByNumber(allocator, number);\n");
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
            try writer.writeAll("for (values) |value| try write(w, value);\n");
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
            try writer.writeAll("const raw = try encodeAllRaw(allocator, values);\n");
            try indent(writer, depth + 1);
            try writer.writeAll("defer allocator.free(raw);\n");
            try indent(writer, depth + 1);
            try writer.writeAll("try message.appendUnknownRaw(allocator, raw);\n");
        } else {
            try indent(writer, depth + 1);
            try writer.writeAll("for (values) |value| try appendToUnknown(message, allocator, value);\n");
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

fn extensionUsesMessageSet(ctx: *const CodegenContext, field: *const schema.FieldDescriptor) bool {
    if (field.kind != .message) return false;
    const extendee = field.extendee orelse return false;
    const ref = resolveMessageReference(ctx, extendee) orelse return false;
    return ref.message.messageSetWireFormat();
}

fn writeExtensionDecodeHelpers(ctx: *const CodegenContext, field: *const schema.FieldDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
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
    try writer.writeAll("const tag = (try r.nextTag()) orelse return null;\n");
    if (extensionUsesMessageSet(ctx, field)) {
        try indent(writer, depth + 1);
        try writer.writeAll("if (tag.number == 1 and tag.wire_type == .start_group) { const value = try decodeMessageSetItem(&r); if (!r.eof()) return error.InvalidWireType; return value; }\n");
        try indent(writer, depth + 1);
        try writer.print("if (tag.number == {d} and tag.wire_type == .length_delimited) {{ const value = try r.readBytes(); if (!r.eof()) return error.InvalidWireType; return value; }}\n", .{field.number});
        try indent(writer, depth + 1);
        try writer.writeAll("return null;\n");
    } else {
        try indent(writer, depth + 1);
        try writer.print("if (tag.number != number or tag.wire_type != .{s}) return null;\n", .{@tagName(field.kind.wireType())});
        try indent(writer, depth + 1);
        try writer.writeAll("const value = try decodeValue(&r);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("if (!r.eof()) return error.InvalidWireType;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return value;\n");
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
        try writer.writeAll("const tag = (try r.nextTag()) orelse return null;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("if (tag.number != number or tag.wire_type != .length_delimited) return null;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("var packed_reader = pbz.Reader.init(try r.readBytes());\n");
        try indent(writer, depth + 1);
        try writer.writeAll("if (!r.eof()) return error.InvalidWireType;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("var list: std.ArrayList(");
        try writer.writeAll(extensionSingleZigType(field.kind));
        try writer.writeAll(") = .empty;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("errdefer list.deinit(allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("while (!packed_reader.eof()) try list.append(allocator, ");
        try writeEntryReadExpr(field.kind, "packed_reader", writer);
        try writer.writeAll(");\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return try list.toOwnedSlice(allocator);\n");
        try indent(writer, depth);
        try writer.writeAll("}\n");
    }

    try indent(writer, depth);
    try writer.writeAll("pub fn decodeAllRaw(allocator: std.mem.Allocator, raw_fields: []const []const u8) ![]");
    try writer.writeAll(extensionSingleZigType(field.kind));
    try writer.writeAll(" {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("var list: std.ArrayList(");
    try writer.writeAll(extensionSingleZigType(field.kind));
    try writer.writeAll(") = .empty;\n");
    try indent(writer, depth + 1);
    try writer.writeAll("errdefer list.deinit(allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("for (raw_fields) |raw| {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("if (try decodeRaw(raw)) |value| try list.append(allocator, value);\n");
    if (field.resolvedPacked(file)) {
        try indent(writer, depth + 2);
        try writer.writeAll("if (try decodePackedRaw(allocator, raw)) |values| { defer allocator.free(values); try list.appendSlice(allocator, values); }\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("}\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try list.toOwnedSlice(allocator);\n");
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
    try writer.writeAll("const values = try decodeFromUnknownFieldsAlloc(message, allocator);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("defer allocator.free(values);\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return if (values.len == 0) null else values[values.len - 1];\n");
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
        try writer.writeAll("if (try decodeRaw(raw)) |value| try list.append(allocator, value);\n");
        if (field.resolvedPacked(file)) {
            try indent(writer, depth + 1);
            try writer.writeAll("if (try decodePackedRaw(allocator, raw)) |values| { defer allocator.free(values); try list.appendSlice(allocator, values); }\n");
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
        try writer.writeAll("var payload: ?[]const u8 = null;\n");
        try indent(writer, depth + 1);
        try writer.writeAll("while (try r.nextTag()) |tag| {\n");
        try indent(writer, depth + 2);
        try writer.writeAll("if (tag.wire_type == .end_group) {\n");
        try indent(writer, depth + 3);
        try writer.writeAll("if (tag.number != 1) return error.InvalidFieldNumber;\n");
        try indent(writer, depth + 3);
        try writer.print("return if (type_id != null and type_id.? == {d}) payload else null;\n", .{field.number});
        try indent(writer, depth + 2);
        try writer.writeAll("}\n");
        try indent(writer, depth + 2);
        try writer.writeAll("switch (tag.number) {\n");
        try indent(writer, depth + 3);
        try writer.writeAll("2 => { if (tag.wire_type != .varint) return error.InvalidWireType; const raw_type_id = try r.readUInt32(); if (raw_type_id == 0 or raw_type_id > std.math.maxInt(pbz.FieldNumber)) return error.InvalidFieldNumber; type_id = raw_type_id; },\n");
        try indent(writer, depth + 3);
        try writer.writeAll("3 => { if (tag.wire_type != .length_delimited) return error.InvalidWireType; payload = try r.readBytes(); },\n");
        try indent(writer, depth + 3);
        try writer.writeAll("else => try r.skipValue(tag),\n");
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

fn extensionSingleZigType(kind: schema.FieldKind) []const u8 {
    return switch (kind) {
        .scalar => |scalar| scalarZigType(scalar),
        .enumeration => "i32",
        .message, .group => "[]const u8",
        else => "void",
    };
}

fn extensionValueTypeName(file: *const schema.FileDescriptor, field: *const schema.FieldDescriptor) []const u8 {
    _ = file;
    return switch (field.kind) {
        .scalar => |scalar| @tagName(scalar),
        .message => |name| name,
        .enumeration => |name| name,
        .group => |name| name,
        .map => "map",
    };
}

fn countExtensions(file: *const schema.FileDescriptor) usize {
    var count: usize = file.extensions.items.len;
    for (file.messages.items) |*message| count += countMessageExtensions(message);
    return count;
}

fn countMessageExtensions(message: *const schema.MessageDescriptor) usize {
    var count: usize = message.extensions.items.len;
    for (message.messages.items) |*nested| count += countMessageExtensions(nested);
    return count;
}

fn writeIdent(name: []const u8, writer: *std.Io.Writer) Error!void {
    if (canWriteBareIdent(name)) return try writer.writeAll(name);
    return try writeQuotedIdent(name, writer);
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

fn writeQuotedIdent(name: []const u8, writer: *std.Io.Writer) Error!void {
    if (canWriteBareIdent(name)) return try writer.writeAll(name);
    try writer.writeAll("@\"");
    for (name) |c| {
        if (c == '\\' or c == '"') try writer.writeByte('\\');
        try writer.writeByte(c);
    }
    try writer.writeAll("\"");
}

fn writeQuotedIdentWithSuffix(name: []const u8, suffix: []const u8, writer: *std.Io.Writer) Error!void {
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

fn writeQuotedIdentWithPrefix(name: []const u8, prefix: []const u8, writer: *std.Io.Writer) Error!void {
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

fn writeQuotedAccessorIdent(prefix: []const u8, name: []const u8, writer: *std.Io.Writer) Error!void {
    if (canWriteBareIdentParts(prefix, name, "")) {
        try writer.writeAll(prefix);
        try writer.writeAll("Field_");
        return try writer.writeAll(name);
    }
    try writer.writeAll("@\"");
    try writer.writeAll(prefix);
    try writer.writeAll("Field");
    try writer.writeByte('_');
    for (name) |c| {
        if (c == '\\' or c == '"') try writer.writeByte('\\');
        try writer.writeByte(c);
    }
    try writer.writeAll("\"");
}

fn extensionAccessorSuffix(name: []const u8) []const u8 {
    return leafTypeName(name);
}

fn hasPresence(file: *const schema.FileDescriptor, field: schema.FieldDescriptor) bool {
    if (field.cardinality == .required or field.proto3_optional or field.oneof_name != null or field.kind == .message or field.kind == .group) return true;
    if (field.cardinality == .repeated or field.kind == .map) return false;
    if (field.features) |features| return features.field_presence != .implicit;
    return file.features.field_presence != .implicit;
}

fn isRequired(field: schema.FieldDescriptor) bool {
    if (field.cardinality == .required) return true;
    if (field.features) |features| return features.field_presence == .legacy_required;
    return false;
}

fn writePresenceIdent(name: []const u8, writer: *std.Io.Writer) Error!void {
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

fn indent(writer: *std.Io.Writer, depth: usize) Error!void {
    var i: usize = 0;
    while (i < depth) : (i += 1) try writer.writeAll("    ");
}

fn writeServiceMetadata(ctx: *const CodegenContext, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    if (file.services.items.len == 0) return;
    try indent(writer, depth);
    try writer.writeAll("pub const services = struct {\n");
    for (file.services.items) |*service| try writeServiceDecl(ctx, service, writer, depth + 1);
    try indent(writer, depth);
    try writer.writeAll("};\n\n");
}

fn writeServiceDecl(ctx: *const CodegenContext, service: *const schema.ServiceDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub const ");
    try writeQuotedIdent(service.name, writer);
    try writer.writeAll(" = struct {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const name = ");
    try writeZigStringLiteral(service.name, writer);
    try writer.writeAll(";\n");
    for (service.methods.items) |*method| try writeMethodDecl(ctx, method, writer, depth + 1);
    if (serviceHasAdapters(ctx, service)) {
        try writeServiceHandlerDecl(ctx, service, writer, depth + 1);
        try writeServiceClientDecl(ctx, service, writer, depth + 1);
    }
    try indent(writer, depth);
    try writer.writeAll("};\n");
}

fn writeMethodDecl(ctx: *const CodegenContext, method: *const schema.MethodDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub const ");
    try writeQuotedIdent(method.name, writer);
    try writer.writeAll(" = struct {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const name = ");
    try writeZigStringLiteral(method.name, writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const input_type = ");
    try writeZigStringLiteral(method.input_type, writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const output_type = ");
    try writeZigStringLiteral(method.output_type, writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const input_has_type_ref = ");
    try writer.writeAll(if (codegenCanReferenceMessageWithContext(ctx, method.input_type)) "true" else "false");
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const input_type_ref = ");
    try writeRpcMessageTypeReferenceOrVoid(ctx, method.input_type, writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const output_has_type_ref = ");
    try writer.writeAll(if (codegenCanReferenceMessageWithContext(ctx, method.output_type)) "true" else "false");
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const output_type_ref = ");
    try writeRpcMessageTypeReferenceOrVoid(ctx, method.output_type, writer);
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const client_streaming = ");
    try writer.writeAll(if (method.client_streaming) "true" else "false");
    try writer.writeAll(";\n");
    try indent(writer, depth + 1);
    try writer.writeAll("pub const server_streaming = ");
    try writer.writeAll(if (method.server_streaming) "true" else "false");
    try writer.writeAll(";\n");
    try indent(writer, depth);
    try writer.writeAll("};\n");
}

fn serviceHasAdapters(ctx: *const CodegenContext, service: *const schema.ServiceDescriptor) bool {
    for (service.methods.items) |*method| {
        if (methodHasMessageTypes(ctx, method)) return true;
    }
    return false;
}

fn methodHasMessageTypes(ctx: *const CodegenContext, method: *const schema.MethodDescriptor) bool {
    return codegenCanReferenceMessageWithContext(ctx, method.input_type) and codegenCanReferenceMessageWithContext(ctx, method.output_type);
}

fn methodHasUnaryAdapter(ctx: *const CodegenContext, method: *const schema.MethodDescriptor) bool {
    return !method.client_streaming and !method.server_streaming and methodHasMessageTypes(ctx, method);
}

fn writeServiceHandlerDecl(ctx: *const CodegenContext, service: *const schema.ServiceDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try writer.writeAll("\n");
    try indent(writer, depth);
    try writer.writeAll("pub fn Handler(comptime Impl: type) type {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return struct {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("impl: *Impl,\n\n");
    try indent(writer, depth + 2);
    try writer.writeAll("pub fn init(impl: *Impl) @This() { return .{ .impl = impl }; }\n\n");
    for (service.methods.items) |*method| {
        if (methodHasMessageTypes(ctx, method)) try writeServiceHandlerMethod(ctx, method, writer, depth + 2);
    }
    try writeServiceDispatchRaw(ctx, service, writer, depth + 2);
    try indent(writer, depth + 1);
    try writer.writeAll("};\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeServiceHandlerMethod(ctx: *const CodegenContext, method: *const schema.MethodDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedIdent(method.name, writer);
    try writer.writeAll("(self: @This(), allocator: std.mem.Allocator, ");
    if (method.client_streaming) {
        try writer.writeAll("requests: anytype");
    } else {
        try writer.writeAll("request: ");
        try writeRpcMessageTypeReference(ctx, method.input_type, writer);
    }
    if (method.server_streaming) try writer.writeAll(", responses: anytype");
    try writer.writeAll(") !");
    if (method.server_streaming) {
        try writer.writeAll("void");
    } else {
        try writeRpcMessageTypeReference(ctx, method.output_type, writer);
    }
    try writer.writeAll(" {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return try self.impl.");
    try writeQuotedIdent(method.name, writer);
    try writer.writeAll("(allocator, ");
    if (method.client_streaming) {
        try writer.writeAll("requests");
    } else {
        try writer.writeAll("request");
    }
    if (method.server_streaming) try writer.writeAll(", responses");
    try writer.writeAll(");\n");
    try indent(writer, depth);
    try writer.writeAll("}\n\n");
}

fn writeServiceDispatchRaw(ctx: *const CodegenContext, service: *const schema.ServiceDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn dispatchRaw(self: @This(), allocator: std.mem.Allocator, method_name: []const u8, request_payload: []const u8) !?[]u8 {\n");
    var wrote_any = false;
    for (service.methods.items) |*method| {
        if (!methodHasUnaryAdapter(ctx, method)) continue;
        wrote_any = true;
        try indent(writer, depth + 1);
        try writer.writeAll("if (std.mem.eql(u8, method_name, ");
        try writeZigStringLiteral(method.name, writer);
        try writer.writeAll(")) {\n");
        try indent(writer, depth + 2);
        try writer.writeAll("var request = try ");
        try writeRpcMessageTypeReference(ctx, method.input_type, writer);
        try writer.writeAll(".decodeOwned(allocator, request_payload);\n");
        try indent(writer, depth + 2);
        try writer.writeAll("defer request.deinit(allocator);\n");
        try indent(writer, depth + 2);
        try writer.writeAll("var response = try self.");
        try writeQuotedIdent(method.name, writer);
        try writer.writeAll("(allocator, request);\n");
        try indent(writer, depth + 2);
        try writer.writeAll("defer response.deinit(allocator);\n");
        try indent(writer, depth + 2);
        try writer.writeAll("return try response.encode(allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("}\n");
    }
    if (!wrote_any) {
        try indent(writer, depth + 1);
        try writer.writeAll("_ = self; _ = allocator; _ = method_name; _ = request_payload;\n");
    }
    try indent(writer, depth + 1);
    try writer.writeAll("return null;\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeServiceClientDecl(ctx: *const CodegenContext, service: *const schema.ServiceDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try writer.writeAll("\n");
    try indent(writer, depth);
    try writer.writeAll("pub fn Client(comptime Transport: type) type {\n");
    try indent(writer, depth + 1);
    try writer.writeAll("return struct {\n");
    try indent(writer, depth + 2);
    try writer.writeAll("transport: Transport,\n\n");
    try indent(writer, depth + 2);
    try writer.writeAll("pub fn init(transport: Transport) @This() { return .{ .transport = transport }; }\n\n");
    for (service.methods.items) |*method| {
        if (methodHasMessageTypes(ctx, method)) try writeServiceClientMethod(ctx, service, method, writer, depth + 2);
    }
    try indent(writer, depth + 1);
    try writer.writeAll("};\n");
    try indent(writer, depth);
    try writer.writeAll("}\n");
}

fn writeServiceClientMethod(ctx: *const CodegenContext, service: *const schema.ServiceDescriptor, method: *const schema.MethodDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try indent(writer, depth);
    try writer.writeAll("pub fn ");
    try writeQuotedIdent(method.name, writer);
    try writer.writeAll("(self: *@This(), allocator: std.mem.Allocator, ");
    if (method.client_streaming) {
        try writer.writeAll("requests: anytype");
    } else {
        try writer.writeAll("request: ");
        try writeRpcMessageTypeReference(ctx, method.input_type, writer);
    }
    if (method.server_streaming) try writer.writeAll(", responses: anytype");
    try writer.writeAll(") !");
    if (method.server_streaming) {
        try writer.writeAll("void");
    } else {
        try writeRpcMessageTypeReference(ctx, method.output_type, writer);
    }
    try writer.writeAll(" {\n");
    if (!method.client_streaming and !method.server_streaming) {
        try indent(writer, depth + 1);
        try writer.writeAll("const request_payload = try request.encode(allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("defer allocator.free(request_payload);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("const response_payload = try self.transport.call(allocator, ");
        try writeZigStringLiteral(service.name, writer);
        try writer.writeAll(", ");
        try writeZigStringLiteral(method.name, writer);
        try writer.writeAll(", request_payload);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("defer allocator.free(response_payload);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return try ");
        try writeRpcMessageTypeReference(ctx, method.output_type, writer);
        try writer.writeAll(".decodeOwned(allocator, response_payload);\n");
    } else if (method.client_streaming and !method.server_streaming) {
        try indent(writer, depth + 1);
        try writer.writeAll("const response_payload = try self.transport.callClientStream(allocator, ");
        try writeZigStringLiteral(service.name, writer);
        try writer.writeAll(", ");
        try writeZigStringLiteral(method.name, writer);
        try writer.writeAll(", requests);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("defer allocator.free(response_payload);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("return try ");
        try writeRpcMessageTypeReference(ctx, method.output_type, writer);
        try writer.writeAll(".decodeOwned(allocator, response_payload);\n");
    } else if (!method.client_streaming and method.server_streaming) {
        try indent(writer, depth + 1);
        try writer.writeAll("const request_payload = try request.encode(allocator);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("defer allocator.free(request_payload);\n");
        try indent(writer, depth + 1);
        try writer.writeAll("try self.transport.callServerStream(allocator, ");
        try writeZigStringLiteral(service.name, writer);
        try writer.writeAll(", ");
        try writeZigStringLiteral(method.name, writer);
        try writer.writeAll(", request_payload, responses);\n");
    } else {
        try indent(writer, depth + 1);
        try writer.writeAll("try self.transport.callBidiStream(allocator, ");
        try writeZigStringLiteral(service.name, writer);
        try writer.writeAll(", ");
        try writeZigStringLiteral(method.name, writer);
        try writer.writeAll(", requests, responses);\n");
    }
    try indent(writer, depth);
    try writer.writeAll("}\n\n");
}

fn writeRpcMessageTypeReferenceOrVoid(ctx: *const CodegenContext, type_name: []const u8, writer: *std.Io.Writer) Error!void {
    if (codegenCanReferenceMessageWithContext(ctx, type_name)) {
        try writeRpcMessageTypeReference(ctx, type_name, writer);
    } else {
        try writer.writeAll("void");
    }
}

fn writeRpcMessageTypeReference(ctx: *const CodegenContext, type_name: []const u8, writer: *std.Io.Writer) Error!void {
    try writeMessageTypeReferenceWithContext(ctx, type_name, writer);
}

fn outputName(allocator: std.mem.Allocator, input: []const u8) std.mem.Allocator.Error![]u8 {
    return try outputNameWithOptions(allocator, input, ".pb.zig", true);
}

fn outputNameWithOptions(allocator: std.mem.Allocator, input: []const u8, suffix: []const u8, strip_proto_ext: bool) std.mem.Allocator.Error![]u8 {
    const base = if (input.len == 0) "schema.proto" else input;
    const stem = if (strip_proto_ext and std.mem.endsWith(u8, base, ".proto")) base[0 .. base.len - 6] else base;
    return try std.fmt.allocPrint(allocator, "{s}{s}", .{ stem, suffix });
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
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const Kind = enum(i32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn fromInt(value: i32) ?@This()") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "0 => .UNKNOWN,") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn toInt(self: @This()) i32") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn protoName(self: @This()) []const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, ".ADMIN => \"ADMIN\",") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn fromName(name: []const u8) ?@This()") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (std.mem.eql(u8, name, \"ADMIN\")) return .ADMIN;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn jsonParse(value: std.json.Value) !@This()") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, ".string => |name| fromName(name) orelse error.InvalidEnumValue,") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn textParse(value: []const u8) !@This()") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (fromName(value)) |known| return known;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn textFormat(self: @This(), writer: *std.Io.Writer) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn jsonStringify(self: @This(), writer: *std.Io.Writer) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const User = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const name_number = 1") != null);
}

test "codegen emits Zig enum aliases for proto allow_alias" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\enum Alias {
        \\  option allow_alias = true;
        \\  UNKNOWN = 0;
        \\  STARTED = 1;
        \\  RUNNING = 1;
        \\  ACTIVE = 1;
        \\}
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const Alias = enum(i32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "STARTED = 1,") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const RUNNING = @This().STARTED;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const ACTIVE = @This().STARTED;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "1 => .STARTED,") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, ".STARTED => \"STARTED\",") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, ".RUNNING =>") == null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (std.mem.eql(u8, name, \"RUNNING\")) return .STARTED;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (std.mem.eql(u8, name, \"ACTIVE\")) return .STARTED;") != null);
    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen emits package and import module metadata" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.app;
        \\import "common.proto";
        \\import public "public/common.proto";
        \\message A {}
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const proto_package = \"demo.app\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const proto_syntax = \"proto2\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const imports = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const common_proto = @import(\"common.pb.zig\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const common_proto_kind = \"normal\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const public_common_proto = @import(\"public/common.pb.zig\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const public_common_proto_kind = \"public\";") != null);
    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen emits field metadata including imported type names" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.app;
        \\import "common.proto";
        \\message M {
        \\  optional .demo.common.User user = 1;
        \\  repeated int32 nums = 2 [packed = true];
        \\  optional string display_name = 3 [json_name = "shownName"];
        \\  map<string, .demo.common.Role> roles = 4;
        \\}
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "pub const user_field = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const number = 1;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const cardinality = \"optional\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const kind = \"message\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const type_name = \".demo.common.User\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const has_presence = true;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const nums_field = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const is_packed = true;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const display_name_field = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const json_name = \"shownName\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const roles_field = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const kind = \"map\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const zig_type = \"rolesMap\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const map_key = \"string\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const map_value_kind = \"message\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const map_value_type_name = \".demo.common.Role\";") != null);

    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen emits direct fields for presence repeated map message and oneof fields" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Child { optional int32 id = 1; }
        \\message Parent {
        \\  required int32 id = 1;
        \\  optional string name = 2 [default = "anon"];
        \\  repeated int32 nums = 3;
        \\  optional Child child = 4;
        \\  repeated Child children = 5;
        \\  map<string, Child> keyed = 6;
        \\  oneof pick { string alias = 7; Child picked = 8; }
        \\}
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "id: i32 = 0,") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "has_id: bool = false,") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "name: []const u8 = \"anon\",") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "nums: []const i32 = &.{},") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "child: ?Child = null,") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "children: []const Child = &.{},") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "keyed: keyedMap = .empty,") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pick: pickOneof = .none,") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn hasField_id") == null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn getField_id") == null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn setField_name") == null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn appendField_nums") == null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn setMessageField_child") == null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn getMessageField_child") == null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn setField_alias") == null);

    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen emits typed enum metadata without field accessor wrappers" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message User {
        \\  optional Kind role = 1;
        \\  repeated Kind roles = 2;
        \\  oneof pick { Kind selected = 3; }
        \\  map<string, Kind> keyed = 4;
        \\}
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const has_enum_ref = true;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const enum_ref = Kind;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const map_value_has_enum_ref = true;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const map_value_enum_ref = Kind;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "role: i32 = 0,") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "has_role: bool = false,") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "roles: []const i32 = &.{},") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pick: pickOneof = .none,") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "keyed: keyedMap = .empty,") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn getEnumField_role") == null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn setEnumField_role") == null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn appendEnumField_roles") == null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn appendEnumEntryField_keyed") == null);

    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen emits owned clone helper" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Child { optional int32 id = 1; }
        \\message Parent {
        \\  optional string name = 1;
        \\  optional bytes raw = 2;
        \\  repeated string tags = 3;
        \\  optional Child child = 4;
        \\  repeated Child children = 5;
        \\  map<string, bytes> blobs = 6;
        \\  oneof pick { string alias = 7; Child picked = 8; int32 id = 9; }
        \\}
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn cloneOwned(self: @This(), allocator: std.mem.Allocator) !@This()") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn decodeOwned(allocator: std.mem.Allocator, bytes: []const u8) !@This()") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try decoded.cloneOwned(allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn decodeOwnedInitialized(allocator: std.mem.Allocator, bytes: []const u8) !@This()") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const owned_allocator = try out._pbzOwnedAllocator(allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "out.name = try owned_allocator.dupe(u8, self.name);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "out.raw = try owned_allocator.dupe(u8, self.raw);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const cloned = try allocator.alloc([]const u8, self.tags.len);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (self.tags, 0..) |item, i| cloned[i] = try owned_allocator.dupe(u8, item);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "out.tags = cloned;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.child) |value| out.child = try value.cloneOwned(allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (self.children, 0..) |item, i| cloned[i] = try item.cloneOwned(allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try @This().putMapEntry_blobs(allocator, &out.blobs, .{ .key = try owned_allocator.dupe(u8, entry.key_ptr.*), .value = try owned_allocator.dupe(u8, entry.value_ptr.*) });") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, ".alias => |value| .{ .alias = try owned_allocator.dupe(u8, value) },") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, ".picked => |value| .{ .picked = try value.cloneOwned(allocator) },") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, ".id => |value| .{ .id = value },") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const cloned_unknowns = try allocator.alloc([]const u8, self._unknown_fields.len);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (self._unknown_fields, 0..) |raw, i| cloned_unknowns[i] = try allocator.dupe(u8, raw);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "out._unknown_fields = cloned_unknowns;") != null);

    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen with registry emits imported message type refs and accessors" {
    const allocator = std.testing.allocator;
    var common = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.common;
        \\message User {
        \\  optional int32 id = 1;
        \\  message Profile { optional string name = 1; }
        \\}
    );
    defer common.deinit();
    common.name = "common.proto";
    var app = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.app;
        \\import "common.proto";
        \\message Request {
        \\  optional .demo.common.User user = 1;
        \\  repeated .demo.common.User.Profile profiles = 2;
        \\  map<string, .demo.common.User.Profile> keyed = 3;
        \\  oneof pick { .demo.common.User picked = 4; }
        \\  extensions 100 to max;
        \\}
        \\extend Request {
        \\  optional .demo.common.User ext_user = 100;
        \\  repeated .demo.common.User ext_users = 101;
        \\}
    );
    defer app.deinit();
    app.name = "app.proto";
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);

    const content = try generateZigFileWithRegistry(allocator, &app, &registry);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "pub const type_ref = imports.common_proto.demo.common.User;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const type_ref = imports.common_proto.demo.common.User.Profile;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const map_value_type_ref = imports.common_proto.demo.common.User.Profile;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "user: ?imports.common_proto.demo.common.User = null") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "profiles: []const imports.common_proto.demo.common.User.Profile = &.{}") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const zig_type = \"keyedMap\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "value: imports.common_proto.demo.common.User.Profile = .{}") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "picked: imports.common_proto.demo.common.User,") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try profiles_list.append(allocator, nested);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var value_reader = try entry_reader.nested(value_payload); entry.value.deinit(allocator); entry.value = try imports.common_proto.demo.common.User.Profile.decodeFromReader(allocator, &value_reader);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "4 => { const payload = try r.readBytes(); var payload_reader = try r.nested(payload); self.pick = .{ .picked = try imports.common_proto.demo.common.User.decodeFromReader(allocator, &payload_reader) }; },") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try entry.value.writeTo(w);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, ".picked => |value| { const payload_len = value.encodedSize(); try w.writeTag(4, .length_delimited); try w.writeVarint(payload_len); try value.writeTo(w); },") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, ".picked => |value| { const payload_len = value.encodedSize(); try w.writeTag(4, .length_delimited); try w.writeVarint(payload_len); try value.writeDeterministicTo(allocator, w); },") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try entry.value_ptr.validateRequiredRecursive(allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, ".picked => |nested| try nested.validateRequiredRecursive(allocator),") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var nested = try imports.common_proto.demo.common.User.jsonParseValueWithOptions(allocator, arena_allocator, value, .{ .ignore_unknown_fields = options.ignore_unknown_fields })") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var nested = try imports.common_proto.demo.common.User.Profile.jsonParseValueWithOptions(allocator, arena_allocator, item, .{ .ignore_unknown_fields = options.ignore_unknown_fields })") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, ".{ .key = map_entry.key_ptr.*, .value = blk: { var nested = try imports.common_proto.demo.common.User.Profile.jsonParseValueWithOptions(allocator, arena_allocator, map_entry.value_ptr.*, .{ .ignore_unknown_fields = options.ignore_unknown_fields }); errdefer nested.deinit(allocator); break :blk nested; } }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.pick = .{ .picked = blk: { var nested = try imports.common_proto.demo.common.User.jsonParseValueWithOptions(allocator, arena_allocator, value, .{ .ignore_unknown_fields = options.ignore_unknown_fields }); errdefer nested.deinit(allocator); break :blk nested; } };") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.user) |nested|") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try entry.value.jsonStringifyWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name, .preserve_proto_field_names = options.preserve_proto_field_names, .always_print_primitive_fields = options.always_print_primitive_fields })") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try value.jsonStringifyWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name, .preserve_proto_field_names = options.preserve_proto_field_names, .always_print_primitive_fields = options.always_print_primitive_fields });") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var nested = try imports.common_proto.demo.common.User.parseTextWithOptions(allocator, block, .{ .ignore_unknown_fields = options.ignore_unknown_fields })") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var nested = try imports.common_proto.demo.common.User.Profile.parseTextWithOptions(allocator, block, .{ .ignore_unknown_fields = options.ignore_unknown_fields })") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.pick = .{ .picked = try nested.cloneOwned(allocator) };") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try entry.value.formatTextWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name });") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try value.formatTextWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name });") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try imports.common_proto.demo.common.User.decode(allocator, payload);") != null);

    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen with registry keeps local enum priority over imported enum" {
    const allocator = std.testing.allocator;
    var common = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\enum Kind { UNKNOWN = 0; IMPORTED = 1; }
    );
    defer common.deinit();
    common.name = "common.proto";
    var app = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\import "common.proto";
        \\message Event {
        \\  enum Kind { LOCAL = 7; }
        \\  optional Kind kind = 1 [default = LOCAL];
        \\  map<string, Kind> keyed = 2;
        \\}
    );
    defer app.deinit();
    app.name = "app.proto";
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);
    try registry.validateFileReferences(&app);

    const content = try generateZigFileWithRegistry(allocator, &app, &registry);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "pub const Kind = enum(i32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "LOCAL = 7") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "kind: i32 = 7") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const enum_ref = Event.Kind;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const map_value_enum_ref = Event.Kind;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn getEnumField_kind") == null);

    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen with registry resolves same-package imported unqualified refs" {
    const allocator = std.testing.allocator;
    var common = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message User { optional int32 id = 1; }
        \\enum Kind { UNKNOWN = 0; ADMIN = 7; }
    );
    defer common.deinit();
    common.name = "common.proto";
    var app = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\import "common.proto";
        \\message Event {
        \\  optional User user = 1;
        \\  optional Kind kind = 2 [default = ADMIN];
        \\  map<string, User> keyed = 3;
        \\}
    );
    defer app.deinit();
    app.name = "app.proto";
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);
    try registry.validateFileReferences(&app);

    const content = try generateZigFileWithRegistry(allocator, &app, &registry);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "pub const type_ref = imports.common_proto.demo.User;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const enum_ref = Kind;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const map_value_type_ref = imports.common_proto.demo.User;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const zig_type = \"keyedMap\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "kind: i32 = 7") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const default_value = \"7\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "user: ?imports.common_proto.demo.User = null") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "value: imports.common_proto.demo.User = .{}") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var value_reader = try entry_reader.nested(value_payload); entry.value.deinit(allocator); entry.value = try imports.common_proto.demo.User.decodeFromReader(allocator, &value_reader);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try entry.value_ptr.validateRequiredRecursive(allocator);") != null);

    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen with registry follows public import chains for message refs" {
    const allocator = std.testing.allocator;
    var leaf = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.leaf;
        \\message User { optional int32 id = 1; }
    );
    defer leaf.deinit();
    leaf.name = "leaf.proto";
    var bridge = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.bridge;
        \\import public "leaf.proto";
        \\message Bridge {}
    );
    defer bridge.deinit();
    bridge.name = "bridge.proto";
    var app = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.app;
        \\import "bridge.proto";
        \\message Request { optional .demo.leaf.User user = 1; }
    );
    defer app.deinit();
    app.name = "app.proto";

    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&leaf);
    try registry.addFile(&bridge);
    try registry.addFile(&app);

    const content = try generateZigFileWithRegistry(allocator, &app, &registry);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "pub const type_ref = imports.bridge_proto.imports.leaf_proto.demo.leaf.User;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "user: ?imports.bridge_proto.imports.leaf_proto.demo.leaf.User = null") != null);

    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen with registry resolves imported enum fields" {
    const allocator = std.testing.allocator;
    var common = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.common;
        \\enum Role { UNKNOWN = 0; ADMIN = 1; GUEST = 2; }
    );
    defer common.deinit();
    common.name = "common.proto";
    var app = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.app;
        \\import "common.proto";
        \\message Request {
        \\  optional .demo.common.Role role = 1 [default = GUEST];
        \\  repeated .demo.common.Role roles = 2;
        \\  map<string, .demo.common.Role> keyed = 3;
        \\  oneof pick { .demo.common.Role picked = 4; }
        \\}
    );
    defer app.deinit();
    app.name = "app.proto";
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);

    const content = try generateZigFileWithRegistry(allocator, &app, &registry);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "pub const @\"demo.common.Role\" = enum(i32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const kind = \"enum\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const type_name = \".demo.common.Role\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "role: i32 = 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const default_value = \"2\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "roles: []const i32 = &.{}") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "value: i32 = 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "picked: i32,") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeInt32(1, self.role)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeMessage(1, self.role)") == null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (!@This().enumKnown(value, &.{0, 1, 2}))") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "&.{\"UNKNOWN\", \"ADMIN\", \"GUEST\"}, &.{0, 1, 2}, true") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn setMessageField_role") == null);

    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen validates imported extension required payloads" {
    const allocator = std.testing.allocator;
    var common = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package common;
        \\message Host { extensions 100 to max; }
        \\message Payload { required int32 id = 1; }
    );
    defer common.deinit();
    common.name = "common.proto";
    var app = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package app;
        \\import "common.proto";
        \\message LocalHost { extensions 100 to max; }
        \\extend LocalHost { optional common.Payload payload = 100; }
    );
    defer app.deinit();
    app.name = "app.proto";
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);

    const content = try generateZigFileWithRegistry(allocator, &app, &registry);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "const payloads = try extensions.payload.decodeAllFromUnknown(self, allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var nested = try imports.common_proto.common.Payload.decode(allocator, payload);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try nested.validateRequiredRecursive(allocator);") != null);

    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen with registry emits extension type refs" {
    const allocator = std.testing.allocator;
    var common = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.common;
        \\enum Role { UNKNOWN = 0; ADMIN = 1; }
        \\message Host { extensions 100 to max; }
        \\message Note { optional int32 id = 1; }
    );
    defer common.deinit();
    common.name = "common.proto";
    var app = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.app;
        \\import "common.proto";
        \\message LocalHost { extensions 200 to max; }
        \\extend .demo.common.Host {
        \\  optional .demo.common.Note note = 100;
        \\  optional .demo.common.Role role = 101;
        \\  repeated .demo.common.Role roles = 102;
        \\}
        \\extend LocalHost { optional .demo.common.Note local_note = 200; }
    );
    defer app.deinit();
    app.name = "app.proto";
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);

    const content = try generateZigFileWithRegistry(allocator, &app, &registry);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "pub const extendee = \".demo.common.Host\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const extendee_has_type_ref = true;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const extendee_type_ref = imports.common_proto.demo.common.Host;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const value_type = \".demo.common.Note\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const value_has_type_ref = true;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const value_type_ref = imports.common_proto.demo.common.Note;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const typed_zig_type = \"imports.common_proto.demo.common.Note\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn hasOn(message: imports.common_proto.demo.common.Host) !bool") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn getOn(message: imports.common_proto.demo.common.Host, allocator: std.mem.Allocator) !?[]const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn setOn(message: *imports.common_proto.demo.common.Host, allocator: std.mem.Allocator, value: []const u8) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn setMessageOn(message: *imports.common_proto.demo.common.Host, allocator: std.mem.Allocator, value: imports.common_proto.demo.common.Note) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn getMessageOn(message: imports.common_proto.demo.common.Host, allocator: std.mem.Allocator) !?imports.common_proto.demo.common.Note") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const value_enum_ref = @\"demo.common.Role\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn getEnumOn(message: imports.common_proto.demo.common.Host, allocator: std.mem.Allocator) !?@\"demo.common.Role\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return @\"demo.common.Role\".fromInt(raw);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn getEnumOrDefaultOn(message: imports.common_proto.demo.common.Host, allocator: std.mem.Allocator) !@\"demo.common.Role\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return (try getEnumOn(message, allocator)) orelse @\"demo.common.Role\".fromInt(default_value_zig) orelse unreachable;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn setEnumOn(message: *imports.common_proto.demo.common.Host, allocator: std.mem.Allocator, value: @\"demo.common.Role\") !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try setOn(message, allocator, value.toInt());") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn getEnumsOn(message: imports.common_proto.demo.common.Host, allocator: std.mem.Allocator) ![]@\"demo.common.Role\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn addEnumOn(message: *imports.common_proto.demo.common.Host, allocator: std.mem.Allocator, value: @\"demo.common.Role\") !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn appendAllEnumsOn(message: *imports.common_proto.demo.common.Host, allocator: std.mem.Allocator, values: []const @\"demo.common.Role\") !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try appendAllOn(message, allocator, raw);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn replaceAllEnumsOn(message: *imports.common_proto.demo.common.Host, allocator: std.mem.Allocator, values: []const @\"demo.common.Role\") !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try replaceAllOn(message, allocator, raw);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var nested = try imports.common_proto.demo.common.Note.parseTextWithOptions(allocator, block, .{ .ignore_unknown_fields = options.ignore_unknown_fields });") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var nested = try imports.common_proto.demo.common.Note.decode(allocator, payload);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var nested = try imports.common_proto.demo.common.Note.jsonParseValueWithOptions(arena_allocator, arena_allocator") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var nested = try imports.common_proto.demo.common.Note.decode(allocator_, payload_);") != null);

    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen emits protoc response" {
    const allocator = std.testing.allocator;
    var common = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.common;
        \\message User { optional int32 id = 1; }
    );
    defer common.deinit();
    common.name = "common.proto";
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.app;
        \\import "common.proto";
        \\enum Kind { UNKNOWN = 0; STARTED = 1; }
        \\message A { optional .demo.common.User user = 1; oneof pick { int32 id = 2; } }
        \\service Api { rpc Get (A) returns (A); }
    );
    defer file.deinit();
    file.name = "a.proto";
    const files = [_]*const schema.FileDescriptor{ &common, &file };
    const response = try generatePluginResponse(allocator, &files);
    defer allocator.free(response);
    try std.testing.expect(response.len != 0);

    var reader = wire.Reader.init(response);
    var saw_supported_features = false;
    var saw_minimum_edition = false;
    var saw_maximum_edition = false;
    var saw_file_name = false;
    var saw_registry_import_ref = false;
    var saw_generated_info = false;
    var saw_message_annotation = false;
    var saw_field_annotation = false;
    var saw_oneof_annotation = false;
    var saw_enum_value_annotation = false;
    var saw_method_annotation = false;
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            2 => saw_supported_features = (try reader.readUInt64()) == generatedResponseFeatureMask(),
            3 => saw_minimum_edition = (try reader.readInt32()) == @intFromEnum(schema.Edition.proto2),
            4 => saw_maximum_edition = (try reader.readInt32()) == @intFromEnum(schema.Edition.edition_2026),
            15 => {
                var file_reader = wire.Reader.init(try reader.readBytes());
                while (try file_reader.nextTag()) |file_tag| {
                    switch (file_tag.number) {
                        1 => saw_file_name = std.mem.eql(u8, try file_reader.readBytes(), "a.pb.zig"),
                        15 => {
                            const content = try file_reader.readBytes();
                            saw_registry_import_ref = saw_registry_import_ref or std.mem.indexOf(u8, content, "pub const type_ref = imports.common_proto.demo.common.User;") != null;
                        },
                        16 => {
                            var info = try @import("descriptor.zig").decodeGeneratedCodeInfo(allocator, try file_reader.readBytes());
                            defer info.deinit(allocator);
                            for (info.annotations.items) |*annotation| {
                                const source_matches = std.mem.eql(u8, annotation.source_file orelse "", "a.proto");
                                const range_valid = annotation.begin.? >= 0 and annotation.end.? > annotation.begin.?;
                                const semantic_matches = annotation.semantic.? == .set;
                                if (annotation.path.items.len == 0) {
                                    saw_generated_info = saw_generated_info or source_matches and annotation.begin.? == 0 and range_valid and semantic_matches;
                                }
                                if (std.mem.eql(i32, annotation.path.items, &.{ 4, 0 })) {
                                    saw_message_annotation = saw_message_annotation or source_matches and range_valid and semantic_matches;
                                }
                                if (std.mem.eql(i32, annotation.path.items, &.{ 4, 0, 2, 0 })) {
                                    saw_field_annotation = saw_field_annotation or source_matches and range_valid and semantic_matches;
                                }
                                if (std.mem.eql(i32, annotation.path.items, &.{ 4, 0, 8, 0 })) {
                                    saw_oneof_annotation = saw_oneof_annotation or source_matches and range_valid and semantic_matches;
                                }
                                if (std.mem.eql(i32, annotation.path.items, &.{ 5, 0, 2, 0 })) {
                                    saw_enum_value_annotation = saw_enum_value_annotation or source_matches and range_valid and semantic_matches;
                                }
                                if (std.mem.eql(i32, annotation.path.items, &.{ 6, 0, 2, 0 })) {
                                    saw_method_annotation = saw_method_annotation or source_matches and range_valid and semantic_matches;
                                }
                            }
                        },
                        else => try file_reader.skipValue(file_tag),
                    }
                }
            },
            else => try reader.skipValue(tag),
        }
    }
    try std.testing.expect(saw_supported_features);
    try std.testing.expect(saw_minimum_edition);
    try std.testing.expect(saw_maximum_edition);
    try std.testing.expect(saw_file_name);
    try std.testing.expect(saw_registry_import_ref);
    try std.testing.expect(saw_generated_info);
    try std.testing.expect(saw_message_annotation);
    try std.testing.expect(saw_field_annotation);
    try std.testing.expect(saw_oneof_annotation);
    try std.testing.expect(saw_enum_value_annotation);
    try std.testing.expect(saw_method_annotation);
}

test "codegen emits protoc response from request file_to_generate" {
    const allocator = std.testing.allocator;
    var request = plugin.CodeGeneratorRequest.init(allocator);
    defer request.deinit();
    try request.files_to_generate.append(allocator, "app.proto");
    try request.proto_files.append(allocator, try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.common;
        \\message User { optional int32 id = 1; }
    ));
    request.proto_files.items[0].name = "common.proto";
    try request.proto_files.append(allocator, try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.app;
        \\import "common.proto";
        \\message App { optional .demo.common.User user = 1; }
    ));
    request.proto_files.items[1].name = "app.proto";

    const response = try generatePluginResponseFromRequest(allocator, &request);
    defer allocator.free(response);

    var reader = wire.Reader.init(response);
    var response_file_count: usize = 0;
    var saw_app_name = false;
    var saw_common_name = false;
    var saw_import_type_ref = false;
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            15 => {
                response_file_count += 1;
                var file_reader = wire.Reader.init(try reader.readBytes());
                while (try file_reader.nextTag()) |file_tag| {
                    switch (file_tag.number) {
                        1 => {
                            const name = try file_reader.readBytes();
                            saw_app_name = saw_app_name or std.mem.eql(u8, name, "app.pb.zig");
                            saw_common_name = saw_common_name or std.mem.eql(u8, name, "common.pb.zig");
                        },
                        15 => {
                            const content = try file_reader.readBytes();
                            saw_import_type_ref = saw_import_type_ref or std.mem.indexOf(u8, content, "pub const type_ref = imports.common_proto.demo.common.User;") != null;
                        },
                        else => try file_reader.skipValue(file_tag),
                    }
                }
            },
            else => try reader.skipValue(tag),
        }
    }
    try std.testing.expectEqual(@as(usize, 1), response_file_count);
    try std.testing.expect(saw_app_name);
    try std.testing.expect(!saw_common_name);
    try std.testing.expect(saw_import_type_ref);

    var missing_request = plugin.CodeGeneratorRequest.init(allocator);
    defer missing_request.deinit();
    try missing_request.files_to_generate.append(allocator, "missing.proto");
    try missing_request.proto_files.append(allocator, try @import("parser.zig").Parser.parse(allocator, "syntax = \"proto2\"; message A {}"));
    missing_request.proto_files.items[0].name = "a.proto";

    const missing_response = try generatePluginResponseFromRequest(allocator, &missing_request);
    defer allocator.free(missing_response);
    var missing_reader = wire.Reader.init(missing_response);
    var saw_error = false;
    while (try missing_reader.nextTag()) |tag| {
        switch (tag.number) {
            1 => saw_error = std.mem.indexOf(u8, try missing_reader.readBytes(), "missing.proto") != null,
            else => try missing_reader.skipValue(tag),
        }
    }
    try std.testing.expect(saw_error);

    var unresolved_request = plugin.CodeGeneratorRequest.init(allocator);
    defer unresolved_request.deinit();
    try unresolved_request.files_to_generate.append(allocator, "bad.proto");
    try unresolved_request.proto_files.append(allocator, try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Bad { optional MissingType field = 1; }
    ));
    unresolved_request.proto_files.items[0].name = "bad.proto";
    const unresolved_response = try generatePluginResponseFromRequest(allocator, &unresolved_request);
    defer allocator.free(unresolved_response);
    var unresolved_reader = wire.Reader.init(unresolved_response);
    var saw_unresolved_error = false;
    while (try unresolved_reader.nextTag()) |tag| {
        switch (tag.number) {
            1 => saw_unresolved_error = std.mem.indexOf(u8, try unresolved_reader.readBytes(), "unresolved type") != null,
            else => try unresolved_reader.skipValue(tag),
        }
    }
    try std.testing.expect(saw_unresolved_error);
}

test "codegen request plugin options include imports and raw bytes entrypoint" {
    const allocator = std.testing.allocator;
    var request = plugin.CodeGeneratorRequest.init(allocator);
    defer request.deinit();
    request.parameter = "paths=source_relative,include_imports=true";
    try request.files_to_generate.append(allocator, "app.proto");
    try request.proto_files.append(allocator, try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.common;
        \\message User { optional int32 id = 1; }
    ));
    request.proto_files.items[0].name = "common.proto";
    try request.proto_files.append(allocator, try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.app;
        \\import "common.proto";
        \\message App { optional .demo.common.User user = 1; }
    ));
    request.proto_files.items[1].name = "app.proto";

    const include_response = try generatePluginResponseFromRequest(allocator, &request);
    defer allocator.free(include_response);
    var include_reader = wire.Reader.init(include_response);
    var include_file_count: usize = 0;
    while (try include_reader.nextTag()) |tag| {
        switch (tag.number) {
            15 => {
                include_file_count += 1;
                try include_reader.skipValue(tag);
            },
            else => try include_reader.skipValue(tag),
        }
    }
    try std.testing.expectEqual(@as(usize, 2), include_file_count);

    var no_info_request = plugin.CodeGeneratorRequest.init(allocator);
    defer no_info_request.deinit();
    no_info_request.parameter = "generated_info=false";
    try no_info_request.files_to_generate.append(allocator, "app.proto");
    try no_info_request.proto_files.append(allocator, try @import("parser.zig").Parser.parse(allocator, "syntax = \"proto2\"; message App {}"));
    no_info_request.proto_files.items[0].name = "app.proto";
    const no_info_response = try generatePluginResponseFromRequest(allocator, &no_info_request);
    defer allocator.free(no_info_response);
    var no_info_reader = wire.Reader.init(no_info_response);
    var saw_no_info_file = false;
    var saw_generated_info_field = false;
    while (try no_info_reader.nextTag()) |tag| {
        switch (tag.number) {
            15 => {
                saw_no_info_file = true;
                var file_reader = wire.Reader.init(try no_info_reader.readBytes());
                while (try file_reader.nextTag()) |file_tag| {
                    switch (file_tag.number) {
                        16 => {
                            saw_generated_info_field = true;
                            try file_reader.skipValue(file_tag);
                        },
                        else => try file_reader.skipValue(file_tag),
                    }
                }
            },
            else => try no_info_reader.skipValue(tag),
        }
    }
    try std.testing.expect(saw_no_info_file);
    try std.testing.expect(!saw_generated_info_field);

    var import_name_request = plugin.CodeGeneratorRequest.init(allocator);
    defer import_name_request.deinit();
    import_name_request.parameter = "pbz_import=custom_runtime";
    try import_name_request.files_to_generate.append(allocator, "app.proto");
    try import_name_request.proto_files.append(allocator, try @import("parser.zig").Parser.parse(allocator, "syntax = \"proto2\"; message App {}"));
    import_name_request.proto_files.items[0].name = "app.proto";
    const import_name_response = try generatePluginResponseFromRequest(allocator, &import_name_request);
    defer allocator.free(import_name_response);
    var import_name_reader = wire.Reader.init(import_name_response);
    var saw_custom_runtime = false;
    while (try import_name_reader.nextTag()) |tag| {
        switch (tag.number) {
            15 => {
                var file_reader = wire.Reader.init(try import_name_reader.readBytes());
                while (try file_reader.nextTag()) |file_tag| {
                    switch (file_tag.number) {
                        15 => saw_custom_runtime = std.mem.indexOf(u8, try file_reader.readBytes(), "const pbz = @import(\"custom_runtime\");") != null,
                        else => try file_reader.skipValue(file_tag),
                    }
                }
            },
            else => try import_name_reader.skipValue(tag),
        }
    }
    try std.testing.expect(saw_custom_runtime);

    var output_name_request = plugin.CodeGeneratorRequest.init(allocator);
    defer output_name_request.deinit();
    output_name_request.parameter = "output_suffix=.pbz.zig";
    try output_name_request.files_to_generate.append(allocator, "app.proto");
    try output_name_request.proto_files.append(allocator, try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.common;
        \\message User {}
    ));
    output_name_request.proto_files.items[0].name = "common.proto";
    try output_name_request.proto_files.append(allocator, try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo.app;
        \\import "common.proto";
        \\message App { optional .demo.common.User user = 1; }
    ));
    output_name_request.proto_files.items[1].name = "app.proto";
    const output_name_response = try generatePluginResponseFromRequest(allocator, &output_name_request);
    defer allocator.free(output_name_response);
    var output_name_reader = wire.Reader.init(output_name_response);
    var saw_custom_output_name = false;
    var saw_custom_import_name = false;
    while (try output_name_reader.nextTag()) |tag| {
        switch (tag.number) {
            15 => {
                var file_reader = wire.Reader.init(try output_name_reader.readBytes());
                while (try file_reader.nextTag()) |file_tag| {
                    switch (file_tag.number) {
                        1 => saw_custom_output_name = saw_custom_output_name or std.mem.eql(u8, try file_reader.readBytes(), "app.pbz.zig"),
                        15 => saw_custom_import_name = saw_custom_import_name or std.mem.indexOf(u8, try file_reader.readBytes(), "@import(\"common.pbz.zig\")") != null,
                        else => try file_reader.skipValue(file_tag),
                    }
                }
            },
            else => try output_name_reader.skipValue(tag),
        }
    }
    try std.testing.expect(saw_custom_output_name);
    try std.testing.expect(saw_custom_import_name);

    var keep_ext_request = plugin.CodeGeneratorRequest.init(allocator);
    defer keep_ext_request.deinit();
    keep_ext_request.parameter = "strip_proto_ext=false";
    try keep_ext_request.files_to_generate.append(allocator, "app.proto");
    try keep_ext_request.proto_files.append(allocator, try @import("parser.zig").Parser.parse(allocator, "syntax = \"proto2\"; message App {}"));
    keep_ext_request.proto_files.items[0].name = "app.proto";
    const keep_ext_response = try generatePluginResponseFromRequest(allocator, &keep_ext_request);
    defer allocator.free(keep_ext_response);
    var keep_ext_reader = wire.Reader.init(keep_ext_response);
    var saw_kept_ext_name = false;
    while (try keep_ext_reader.nextTag()) |tag| {
        switch (tag.number) {
            15 => {
                var file_reader = wire.Reader.init(try keep_ext_reader.readBytes());
                while (try file_reader.nextTag()) |file_tag| {
                    switch (file_tag.number) {
                        1 => saw_kept_ext_name = saw_kept_ext_name or std.mem.eql(u8, try file_reader.readBytes(), "app.proto.pb.zig"),
                        else => try file_reader.skipValue(file_tag),
                    }
                }
            },
            else => try keep_ext_reader.skipValue(tag),
        }
    }
    try std.testing.expect(saw_kept_ext_name);

    var no_helpers_request = plugin.CodeGeneratorRequest.init(allocator);
    defer no_helpers_request.deinit();
    no_helpers_request.parameter = "json=false,text_format=false";
    try no_helpers_request.files_to_generate.append(allocator, "app.proto");
    try no_helpers_request.proto_files.append(allocator, try @import("parser.zig").Parser.parse(allocator, "syntax = \"proto2\"; message App { optional int32 id = 1; }"));
    no_helpers_request.proto_files.items[0].name = "app.proto";
    const no_helpers_response = try generatePluginResponseFromRequest(allocator, &no_helpers_request);
    defer allocator.free(no_helpers_response);
    var no_helpers_reader = wire.Reader.init(no_helpers_response);
    var saw_no_helper_content = false;
    while (try no_helpers_reader.nextTag()) |tag| {
        switch (tag.number) {
            15 => {
                var file_reader = wire.Reader.init(try no_helpers_reader.readBytes());
                while (try file_reader.nextTag()) |file_tag| {
                    switch (file_tag.number) {
                        15 => {
                            const content = try file_reader.readBytes();
                            saw_no_helper_content = std.mem.indexOf(u8, content, "jsonStringify") == null and std.mem.indexOf(u8, content, "formatText") == null;
                        },
                        else => try file_reader.skipValue(file_tag),
                    }
                }
            },
            else => try no_helpers_reader.skipValue(tag),
        }
    }
    try std.testing.expect(saw_no_helper_content);

    var invalid_request = plugin.CodeGeneratorRequest.init(allocator);
    defer invalid_request.deinit();
    invalid_request.parameter = "unknown_option=true";
    try invalid_request.proto_files.append(allocator, try @import("parser.zig").Parser.parse(allocator, "syntax = \"proto2\"; message A {}"));
    invalid_request.proto_files.items[0].name = "a.proto";
    const invalid_response = try generatePluginResponseFromRequest(allocator, &invalid_request);
    defer allocator.free(invalid_response);
    var invalid_reader = wire.Reader.init(invalid_response);
    var saw_invalid_parameter = false;
    while (try invalid_reader.nextTag()) |tag| {
        switch (tag.number) {
            1 => saw_invalid_parameter = std.mem.indexOf(u8, try invalid_reader.readBytes(), "invalid generator parameter") != null,
            else => try invalid_reader.skipValue(tag),
        }
    }
    try std.testing.expect(saw_invalid_parameter);

    const common_fd = try @import("descriptor.zig").encodeFileDescriptorProto(allocator, &request.proto_files.items[0], request.proto_files.items[0].name);
    defer allocator.free(common_fd);
    const fd = try @import("descriptor.zig").encodeFileDescriptorProto(allocator, &request.proto_files.items[1], request.proto_files.items[1].name);
    defer allocator.free(fd);
    var raw_writer = wire.Writer.init(allocator);
    defer raw_writer.deinit();
    try raw_writer.writeString(1, "app.proto");
    try raw_writer.writeString(2, "paths=source_relative");
    try raw_writer.writeMessage(15, common_fd);
    try raw_writer.writeMessage(15, fd);
    const raw_response = try generatePluginResponseFromRequestBytes(allocator, raw_writer.slice());
    defer allocator.free(raw_response);
    var raw_reader = wire.Reader.init(raw_response);
    var saw_raw_app = false;
    while (try raw_reader.nextTag()) |tag| {
        switch (tag.number) {
            15 => {
                var file_reader = wire.Reader.init(try raw_reader.readBytes());
                while (try file_reader.nextTag()) |file_tag| {
                    switch (file_tag.number) {
                        1 => saw_raw_app = saw_raw_app or std.mem.eql(u8, try file_reader.readBytes(), "app.pb.zig"),
                        else => try file_reader.skipValue(file_tag),
                    }
                }
            },
            else => try raw_reader.skipValue(tag),
        }
    }
    try std.testing.expect(saw_raw_app);
}

test "codegen runs plugin requests to writers" {
    const allocator = std.testing.allocator;
    var request = plugin.CodeGeneratorRequest.init(allocator);
    defer request.deinit();
    try request.files_to_generate.append(allocator, "app.proto");
    try request.proto_files.append(allocator, try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message App { optional int32 id = 1; }
    ));
    request.proto_files.items[0].name = "app.proto";

    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();
    try runPluginRequest(allocator, &request, &out.writer);
    try std.testing.expect(out.written().len != 0);

    const fd = try @import("descriptor.zig").encodeFileDescriptorProto(allocator, &request.proto_files.items[0], request.proto_files.items[0].name);
    defer allocator.free(fd);
    var raw = wire.Writer.init(allocator);
    defer raw.deinit();
    try raw.writeString(1, "app.proto");
    try raw.writeMessage(15, fd);
    var raw_out: std.Io.Writer.Allocating = .init(allocator);
    defer raw_out.deinit();
    try runPluginRequestBytes(allocator, raw.slice(), &raw_out.writer);
    try std.testing.expect(raw_out.written().len != 0);

    var reader = wire.Reader.init(raw_out.written());
    var saw_file = false;
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            15 => {
                saw_file = true;
                try reader.skipValue(tag);
            },
            else => try reader.skipValue(tag),
        }
    }
    try std.testing.expect(saw_file);
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
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const fn_number = 1") != null);
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
    try std.testing.expect(std.mem.indexOf(u8, content, "id: i32 = 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "name: []const u8 = \"\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn writeTo(self: @This(), w: *pbz.Writer) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn encode(self: @This(), allocator: std.mem.Allocator) ![]u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn encodeInto(self: @This(), buffer: []u8) ![]u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn encodeIntoAssumeCapacity(self: @This(), buffer: []u8) ![]u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeInt32(1, self.id)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.name.len != 0) { if (!pbz.validateUtf8(self.name)) return error.InvalidUtf8; try w.writeString(2, self.name); }") != null);
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
    try std.testing.expect(std.mem.indexOf(u8, content, "ids: []const i32 = &.{}") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "names: []const []const u8 = &.{}") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "flags: []const bool = &.{}") != null);
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
    try std.testing.expect(std.mem.indexOf(u8, content, "kind: i32 = 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "roles: []const i32 = &.{}") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeInt32(1, self.kind)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeTag(2, .length_delimited);") != null);
}

test "codegen encodes and decodes packed repeated scalar and enum fields" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message M {
        \\  repeated int32 ids = 1 [packed = true];
        \\  repeated Kind kinds = 2 [packed = true];
        \\  repeated fixed64 big_values = 3 [packed = true];
        \\}
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "var packed_len: usize = 0;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "packed_len += pbz.wire.encodedVarintSize(@as(u64, @bitCast(@as(i64, item))))") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeTag(1, .length_delimited);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeVarint(packed_len);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeTag(2, .length_delimited);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (tag.wire_type == .length_delimited)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const payload = try r.readBytes();") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try pbz.wire.appendPackedInt32(allocator, &ids_list, payload);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try pbz.wire.appendPackedFixed64(allocator, &big_values_list, payload);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "while (!packed_reader.eof()) { const value_start = packed_reader.position(); const value = try packed_reader.readInt32(); const value_end = packed_reader.position();") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try unknown_writer.writeTag(2, .varint); try unknown_writer.appendSlice(payload[value_start..value_end]);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try ids_list.append(allocator, try r.readInt32())") != null);
    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen emits known-schema decode reuse for packed-only scalar and enum messages" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\enum Kind { UNKNOWN = 0; HOT = 1; }
        \\message M {
        \\  bool active = 1;
        \\  repeated int32 ids = 2;
        \\  repeated sint32 deltas = 3;
        \\  repeated Kind kinds = 4;
        \\  repeated fixed32 words = 5;
        \\  repeated double ratios = 6;
        \\}
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn decodeKnownReuse(self: *@This(), allocator: std.mem.Allocator, bytes: []const u8) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "/// The caller must pre-size those buffers for the decoded element counts.") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const ids_buffer = @constCast(self.ids);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const deltas_buffer = @constCast(self.deltas);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "ids_buffer[ids_len] = @truncate(@as(i64, @bitCast(try pbz.wire.readVarintAt(payload, &payload_index))))") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "deltas_buffer[deltas_len] = pbz.wire.zigZagDecode32(@as(u32, @truncate(try pbz.wire.readVarintAt(payload, &payload_index))))") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const kinds_buffer = @constCast(self.kinds);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "kinds_buffer[kinds_len] = @truncate(@as(i64, @bitCast(try pbz.wire.readVarintAt(payload, &payload_index))))") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const words_buffer = @constCast(self.words);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (payload.len % 4 != 0) return error.InvalidWireType;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "@memcpy(std.mem.sliceAsBytes(out), payload);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const ratios_buffer = @constCast(self.ratios);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (payload.len % 8 != 0) return error.InvalidWireType;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "value.* = @bitCast(std.mem.readInt(u64, payload[payload_index..][0..8], .little));") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (ids_len != ids_buffer.len) return error.InvalidWireType;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (deltas_len != deltas_buffer.len) return error.InvalidWireType;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (kinds_len != kinds_buffer.len) return error.InvalidWireType;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (words_len != words_buffer.len) return error.InvalidWireType;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (ratios_len != ratios_buffer.len) return error.InvalidWireType;") != null);

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
        \\message Parent {
        \\  Child child = 1;
        \\  repeated Child children = 2;
        \\  oneof pick { Child picked = 3; }
        \\}
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "child: ?Child = null") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "children: []const Child = &.{}") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "has_child: bool") == null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.child) |value| { const payload_len = value.encodedSize(); try w.writeTag(1, .length_delimited); try w.writeVarint(payload_len); try value.writeTo(w); }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (self.children) |item| { const payload_len = item.encodedSize(); try w.writeTag(2, .length_delimited); try w.writeVarint(payload_len); try item.writeTo(w); }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn jsonStringifyWithAllocator(self: @This(), allocator: std.mem.Allocator, writer: *std.Io.Writer) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.child) |nested|") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try nested.jsonStringifyWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name, .preserve_proto_field_names = options.preserve_proto_field_names, .always_print_primitive_fields = options.always_print_primitive_fields })") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.children.len != 0 or options.always_print_primitive_fields)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (self.children, 0..) |item, i|") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, ".picked => |value|") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var nested = try Child.jsonParseValueWithOptions(allocator, arena_allocator") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.pick = .{ .picked = blk:") != null);
}

test "codegen emits JSON helpers for proto2 group payload fields" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Parent {
        \\  optional group Box = 1 { optional int32 id = 2; }
        \\  repeated group Item = 3 { optional string name = 4; }
        \\}
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "box: ?Box = null") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "item: []const Item = &.{}") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.box) |nested|") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (self.item, 0..) |item, i|") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var nested = try Box.jsonParseValueWithOptions(allocator, arena_allocator") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var nested = try Item.jsonParseValueWithOptions(allocator, arena_allocator") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "{ const old = self.item; self.item = try list.toOwnedSlice(allocator); for (old) |item| { var mutable = item; mutable.deinit(allocator); } if (old.len != 0) allocator.free(old); }") != null);

    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen emits basic TextFormat formatters" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message Child { int32 id = 1; }
        \\message M {
        \\  int32 id = 1;
        \\  string name = 2;
        \\  repeated string tags = 3;
        \\  Kind kind = 4;
        \\  Child child = 5;
        \\  map<string, Child> kids = 6;
        \\  map<string, int32> counts = 7;
        \\  double ratio = 8;
        \\  oneof pick { string alias = 9; Kind picked = 10; Child picked_msg = 11; }
        \\}
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn formatTextAlloc(self: @This(), allocator: std.mem.Allocator) ![]u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn formatTextWithAllocator(self: @This(), allocator: std.mem.Allocator, writer: *std.Io.Writer) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const TextFormatOptions = struct { enum_as_name: bool = true };") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn formatTextAllocWithOptions(self: @This(), allocator: std.mem.Allocator, options: @This().TextFormatOptions) ![]u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn formatTextWithOptions(self: @This(), allocator: std.mem.Allocator, writer: *std.Io.Writer, options: @This().TextFormatOptions) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.writeAll(\"id: \"); const value = self.id; try writer.print(\"{d}\", .{value});") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.writeAll(\"tags: \"); if (!pbz.validateUtf8(value)) return error.InvalidUtf8; try @This().textWriteQuotedBytes(value, writer);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try @This().textWriteEnum(writer, value, &.{\"UNKNOWN\", \"ADMIN\"}, &.{0, 1}, options.enum_as_name);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn textWriteEnum(writer: *std.Io.Writer, value: i32, comptime names: []const []const u8, comptime numbers: []const i32, enum_as_name: bool) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.writeAll(\"child {\\n\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try nested.formatTextWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name });") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.writeAll(\"kids {\\n\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.writeAll(\"value {\\n\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.writeAll(\"alias: \"); try @This().textWriteQuotedBytes(value, writer);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.writeAll(\"picked: \"); try @This().textWriteEnum(writer, value, &.{\"UNKNOWN\", \"ADMIN\"}, &.{0, 1}, options.enum_as_name);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn parseText(allocator: std.mem.Allocator, text: []const u8) !@This()") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const TextParseOptions = struct { ignore_unknown_fields: bool = false };") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn parseTextWithOptions(allocator: std.mem.Allocator, text: []const u8, options: @This().TextParseOptions) !@This()") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn parseTextInitializedWithOptions(allocator: std.mem.Allocator, text: []const u8, options: @This().TextParseOptions) !@This()") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (options.ignore_unknown_fields) continue;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const needs_normalized_text = @This().textNeedsSeparatorNormalization(text);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var lines = std.mem.splitScalar(u8, normalized_text, '\\n');") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (try @This().textUnknownField(allocator, line)) |raw| { errdefer allocator.free(raw); try _unknown_fields_list.append(allocator, raw); continue; }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (try @This().textUnknownGroup(allocator, line, &lines)) |raw| { errdefer allocator.free(raw); try _unknown_fields_list.append(allocator, raw); continue; }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (self._unknown_fields) |raw| {") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try @This().textWriteUnknownRaw(raw, writer);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn textWriteUnknownRaw(raw: []const u8, writer: *std.Io.Writer) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn textWriteQuotedBytes(bytes: []const u8, writer: *std.Io.Writer) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn textWriteUnknownField(tag: pbz.wire.Tag, r: *pbz.Reader, writer: *std.Io.Writer) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try @This().textWriteQuotedBytes(try r.readBytes(), writer);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.print(\"\\\\{o:0>3}\", .{c});") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.print(\"{d} {{\\n\", .{tag.number});") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn textUnknownField(allocator: std.mem.Allocator, line: []const u8) !?[]const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn textUnknownGroup(allocator: std.mem.Allocator, line: []const u8, lines: anytype) !?[]const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try raw.writeTag(number, .start_group);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try raw.writeTag(number, .end_group);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try raw.writeBytes(number, bytes);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try raw.writeUInt64(number, try std.fmt.parseInt(u64, value, 0));") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const line = @This().textCleanLine(raw_line);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (@This().textFieldValue(line, \"id\")) |raw_value|") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.ratio = try @This().textFloat(f64, raw_value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "tags_list.append(allocator, blk: { const decoded = try @This().textUnquote(try self._pbzOwnedAllocator(allocator), raw_value); if (!pbz.validateUtf8(decoded)) return error.InvalidUtf8; break :blk decoded; })") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.kind = @This().textEnum(raw_value, &.{\"UNKNOWN\", \"ADMIN\"}, &.{0, 1}, false) catch |err| { if (options.ignore_unknown_fields) { continue; } return err; };") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (@This().textBlockField(line, \"counts\"))") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (@This().textFieldValue(entry_line, \"value\")) |raw_value| { entry.value = try @This().textInt(i32, raw_value); continue; }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (@This().textBlockField(entry_line, \"value\"))") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "entry.value = try nested.cloneOwned(allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.pick = .{ .alias = blk: { const decoded = try @This().textUnquote(try self._pbzOwnedAllocator(allocator), raw_value); if (!pbz.validateUtf8(decoded)) return error.InvalidUtf8; break :blk decoded; } };") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.pick = .{ .picked = @This().textEnum(raw_value, &.{\"UNKNOWN\", \"ADMIN\"}, &.{0, 1}, false) catch |err| { if (options.ignore_unknown_fields) { continue; } return err; } };") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn textFieldValue(line: []const u8, comptime name: []const u8) ?[]const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn textNormalizeSeparators(allocator: std.mem.Allocator, text: []const u8) ![]u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "else if (c == ';' or c == ',')") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "else if (c == '{' or c == '<')") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "else if (c == '}' or c == '>')") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn textBlockField(line: []const u8, comptime name: []const u8) bool") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn textCleanLine(raw_line: []const u8) []const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "line[line.len - 1] == ';' or line[line.len - 1] == ','") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn textInt(comptime T: type, value: []const u8) !T") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn textFloat(comptime T: type, value: []const u8) !T") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "negative = body[0] == '-'") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (std.ascii.eqlIgnoreCase(body, \"nan\")) return std.math.nan(T);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return if (negative) -parsed else parsed;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn textUnquote(allocator: std.mem.Allocator, value: []const u8) ![]const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "while (i < value.len and std.ascii.isWhitespace(value[i])) : (i += 1) {}") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try std.fmt.parseInt(u8, value[start..end], 16)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try std.fmt.parseInt(u8, value[start..end], 8)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn textHexDigit(c: u8) ?u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var quote: ?u8 = null;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn textEnum(value: []const u8, comptime names: []const []const u8, comptime numbers: []const i32, comptime closed: bool) !i32") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (@This().textBlockField(line, \"child\"))") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const block = try @This().textBlock(allocator, &lines);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var nested = try Child.parseTextWithOptions(allocator, block, .{ .ignore_unknown_fields = options.ignore_unknown_fields });") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.child) |*existing| { try existing.mergeFrom(allocator, nested); } else { self.child = try nested.cloneOwned(allocator); }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.child) |*existing| { try existing.mergeFrom(allocator, nested); } else { self.child = try nested.cloneOwned(allocator); }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try existing.mergeFrom(allocator, nested)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (@This().textBlockField(line, \"picked_msg\") or @This().textBlockField(line, \"pickedMsg\"))") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn textBlock(allocator: std.mem.Allocator, lines: anytype) ![]u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "std.mem.eql(u8, line, \">\")") != null);

    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen emits map entry types and encoders" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\enum Kind { FIRST = 7; SECOND = 8; }
        \\message Child {}
        \\message M {
        \\  map<string, int32> counts = 1;
        \\  map<string, Kind> keyed = 2;
        \\  map<string, Child> kids = 3;
        \\}
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const countsEntry = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "counts: countsMap = .empty") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "value: i32 = 7") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "value: Child = .{}") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn writeDeterministicTo(self: @This(), allocator: std.mem.Allocator, w: *pbz.Writer) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn encodeDeterministic(self: @This(), allocator: std.mem.Allocator) ![]u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn encodeDeterministicIntoAssumeCapacity(self: @This(), allocator: std.mem.Allocator, buffer: []u8) ![]u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "std.mem.sort(countsEntry, entries") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "std.mem.lessThan(u8, a.key, b.key)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const insertion_sort_limit: usize = 32;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const stack_entry_count: usize = @max(insertion_sort_limit, (32 * 1024) / @max(@sizeOf(countsEntry), 1));") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var stack_entries: [stack_entry_count]countsEntry = undefined;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const entries_already_sorted = sorted:") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (entries.len <= insertion_sort_limit)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeVarint(entry_len);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeString(1, entry.key);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeInt32(2, entry.value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var entry_writer = pbz.Writer.init(allocator);") == null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn encodeDeterministicInitialized(self: @This(), allocator: std.mem.Allocator) ![]u8") != null);
}

test "codegen emits packed fixed-width borrowed field helpers" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\message M {
        \\  repeated fixed32 values = 1;
        \\  repeated fixed64 big_values = 2;
        \\}
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "try pbz.wire.writePackedFixedWidthPayload(u32, w, self.values);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pbz.wire.writePackedFixedWidthPayloadAssumeCapacity(u32, w, self.values);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try pbz.wire.writePackedFixedWidthPayload(u64, w, self.big_values);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pbz.wire.writePackedFixedWidthPayloadAssumeCapacity(u64, w, self.big_values);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn valuesPackedFixedView(bytes: []const u8) !?[]align(1) const u32") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try pbz.wire.packedFixedWidthFieldView(u32, bytes, 1);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn valuesPackedFixedSlices(header: *[20]u8, values: []const u32) !pbz.wire.BorrowedFieldSlices") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try pbz.wire.packedFixedWidthFieldSlices(u32, header, 1, values);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn valuesPackedFixed32View(bytes: []const u8) !?[]align(1) const u32") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try valuesPackedFixedView(bytes);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn valuesPackedFixed32Slices(header: *[20]u8, values: []const u32) !pbz.wire.BorrowedFieldSlices") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try valuesPackedFixedSlices(header, values);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn big_valuesPackedFixedView(bytes: []const u8) !?[]align(1) const u64") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try pbz.wire.packedFixedWidthFieldView(u64, bytes, 2);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn big_valuesPackedFixedSlices(header: *[20]u8, values: []const u64) !pbz.wire.BorrowedFieldSlices") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try pbz.wire.packedFixedWidthFieldSlices(u64, header, 2, values);") != null);
}

test "codegen emits borrowed packed bool slices helper" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\message M { repeated bool values = 1; }
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn valuesPackedBoolSlices(header: *[20]u8, values: []const bool) !pbz.wire.BorrowedFieldSlices") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try pbz.wire.packedBoolFieldSlices(header, 1, values);") != null);

    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen emits map duplicate-key last-wins helpers" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message M {
        \\  map<string, int32> counts = 1;
        \\  map<bool, Kind> flags = 2;
        \\}
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "fn appendOrReplaceMapEntry_counts(allocator: std.mem.Allocator, list: *std.ArrayList(countsEntry), entry: countsEntry) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (std.mem.eql(u8, existing.key, entry.key)) { existing.* = entry; return; }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn appendOrReplaceMapEntry_flags(allocator: std.mem.Allocator, list: *std.ArrayList(flagsEntry), entry: flagsEntry) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (existing.key == entry.key) { existing.* = entry; return; }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "while (other_it.next()) |entry| try @This().putMapEntry_counts(allocator, &self.counts, .{ .key = entry.key_ptr.*, .value = entry.value_ptr.* });") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn decodeReuse(self: *@This(), allocator: std.mem.Allocator, bytes: []const u8) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.counts.clearRetainingCapacity();") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "else try @This().putMapEntry_counts(allocator, &self.counts, entry);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try @This().appendOrReplaceMapEntry_counts(allocator, &list, .{ .key = map_entry.key_ptr.*, .value = try @This().jsonInt(i32, map_entry.value_ptr.*) })") != null);

    const text_start = std.mem.indexOf(u8, content, "pub fn parseText").?;
    try std.testing.expect(std.mem.indexOf(u8, content[text_start..], "try @This().appendOrReplaceMapEntry_counts(allocator, &counts_list, entry);") != null);

    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen deterministic encoder emits fields by number" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\message M {
        \\  int32 later = 10;
        \\  oneof pick { int32 mid = 3; }
        \\  int32 first = 1;
        \\}
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);
    const deterministic_start = std.mem.indexOf(u8, content, "pub fn writeDeterministicTo").?;
    const deterministic_end = std.mem.indexOfPos(u8, content, deterministic_start, "pub fn encodeDeterministic").?;
    const deterministic = content[deterministic_start..deterministic_end];
    const first_pos = std.mem.indexOf(u8, deterministic, "try w.writeInt32(1, self.first)").?;
    const mid_pos = std.mem.indexOf(u8, deterministic, ".mid => |value| try w.writeInt32(3, value)").?;
    const later_pos = std.mem.indexOf(u8, deterministic, "try w.writeInt32(10, self.later)").?;
    try std.testing.expect(first_pos < mid_pos);
    try std.testing.expect(mid_pos < later_pos);
}

test "codegen deterministic encoder recurses into available message payloads" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Child { optional int32 a = 1; optional int32 b = 2; }
        \\message Parent {
        \\  optional Child child = 1;
        \\  repeated Child children = 2;
        \\  optional group Legacy = 3 { optional int32 a = 4; optional int32 b = 5; }
        \\  map<string, Child> keyed = 6;
        \\  oneof pick { Child picked = 7; }
        \\}
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);
    const parent_start = std.mem.indexOf(u8, content, "pub const Parent = struct").?;
    const deterministic_start = std.mem.indexOfPos(u8, content, parent_start, "pub fn writeDeterministicTo").?;
    const deterministic_end = std.mem.indexOfPos(u8, content, deterministic_start, "pub fn encodeDeterministic").?;
    const deterministic = content[deterministic_start..deterministic_end];

    try std.testing.expect(std.mem.indexOf(u8, deterministic, "for (self.children) |item| { const payload_len = item.encodedSize(); try w.writeTag(2, .length_delimited); try w.writeVarint(payload_len); try item.writeDeterministicTo(allocator, w); }") != null);
    try std.testing.expect(std.mem.indexOf(u8, deterministic, "try w.writeTag(1, .length_delimited); try w.writeVarint(payload_len); try item.writeDeterministicTo(allocator, w);") != null);
    try std.testing.expect(std.mem.indexOf(u8, deterministic, "try w.writeTag(2, .length_delimited); try w.writeVarint(payload_len); try item.writeDeterministicTo(allocator, w);") != null);
    try std.testing.expect(std.mem.indexOf(u8, deterministic, "if (self.legacy) |item| { try w.writeTag(3, .start_group); try item.writeDeterministicTo(allocator, w); try w.writeTag(3, .end_group); }") != null);
    try std.testing.expect(std.mem.indexOf(u8, deterministic, "std.mem.sort(keyedEntry, entries") != null);
    try std.testing.expect(std.mem.indexOf(u8, deterministic, "entry.value.writeTo(w)") != null);
    try std.testing.expect(std.mem.indexOf(u8, deterministic, ".picked => |value| { const payload_len = value.encodedSize(); try w.writeTag(7, .length_delimited); try w.writeVarint(payload_len); try value.writeDeterministicTo(allocator, w); }") != null);
}

test "codegen emits map JSON stringify and parse helpers" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message Child { int32 id = 1; }
        \\message M {
        \\  map<string, int32> counts = 1;
        \\  map<int32, string> names = 2;
        \\  map<bool, Kind> flags = 3;
        \\  map<string, Child> kids = 4;
        \\}
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.counts.count() != 0)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "while (map_it.next()) |map_entry| : (i += 1)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try @This().jsonWriteString(writer, entry.key)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.print(\"{d}\", .{entry.value})") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.print(\"\\\"{d}\\\"\", .{entry.key})") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try @This().jsonWriteString(writer, entry.value)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.writeAll(if (entry.key) \"\\\"true\\\"\" else \"\\\"false\\\"\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try @This().jsonWriteEnum(writer, entry.value, &.{\"UNKNOWN\", \"ADMIN\"}, &.{0, 1}, options.enum_as_name)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try entry.value.jsonStringifyWithOptions(allocator, writer, .{ .enum_as_name = options.enum_as_name, .preserve_proto_field_names = options.preserve_proto_field_names, .always_print_primitive_fields = options.always_print_primitive_fields })") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const object_value = switch (value) { .object => |map_object| map_object, else => return error.TypeMismatch }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try @This().appendOrReplaceMapEntry_counts(allocator, &list, .{ .key = map_entry.key_ptr.*, .value = try @This().jsonInt(i32, map_entry.value_ptr.*) })") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try self.counts.ensureUnusedCapacity(allocator, list.items.len);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "@This().deinitMap_counts(allocator, &self.counts);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try std.fmt.parseInt(i32, map_entry.key_ptr.*, 10)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try @This().jsonMapKeyBool(map_entry.key_ptr.*)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const parsed_value = @This().jsonEnum(map_entry.value_ptr.*, &.{\"UNKNOWN\", \"ADMIN\"}, &.{0, 1}, false) catch |err| { if (options.ignore_unknown_fields) continue; return err; };") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try @This().appendOrReplaceMapEntry_flags(allocator, &list, .{ .key = try @This().jsonMapKeyBool(map_entry.key_ptr.*), .value = parsed_value });") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try @This().appendOrReplaceMapEntry_kids(allocator, &list, .{ .key = map_entry.key_ptr.*, .value = blk: { var nested = try Child.jsonParseValueWithOptions(allocator, arena_allocator") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try self.kids.ensureUnusedCapacity(allocator, list.items.len);") != null);
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
    try std.testing.expect(std.mem.indexOf(u8, content, "_ = allocator;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "8 => { self.id = try r.readInt32(); }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "18 => { self.name = try r.readBytes(); if (!pbz.validateUtf8(self.name)) return error.InvalidUtf8; }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "24 => { const value = try r.readInt32(); self.kind = value; }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "34 => { self.payload = try r.readBytes(); }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "_unknown_fields: []const []const u8 = &.{}") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn unknownFieldCount(self: @This()) usize") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn unknownFields(self: @This()) []const []const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn unknownFieldCountByNumber(self: @This(), number: pbz.FieldNumber) !usize") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (try r.nextTag()) |tag| {\n                if (tag.number == number) count += 1;\n            }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn hasUnknownFieldNumber(self: @This(), number: pbz.FieldNumber) !bool") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return (try self.unknownFieldCountByNumber(number)) != 0;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn unknownFieldsByNumberAlloc(self: @This(), allocator: std.mem.Allocator, number: pbz.FieldNumber) ![]const []const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var r = pbz.Reader.init(raw);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (tag.number == number) try list.append(allocator, raw);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn clearUnknownFieldsByNumber(self: *@This(), allocator: std.mem.Allocator, number: pbz.FieldNumber) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const tag = (try r.nextTag()) orelse { allocator.free(raw); continue; };") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (tag.number == number) { allocator.free(raw); continue; }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self._unknown_fields = try kept.toOwnedSlice(allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn appendUnknownRaw(self: *@This(), allocator: std.mem.Allocator, raw: []const u8) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const tag = (try r.nextTag()) orelse return error.InvalidWireType;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try r.skipValue(tag);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (!r.eof()) return error.InvalidWireType;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const owned = try allocator.dupe(u8, raw);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn clearUnknownFields(self: *@This(), allocator: std.mem.Allocator) void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "else => { const tag = try pbz.wire.Tag.decode(raw_tag); try r.skipValue(tag); const raw = try allocator.dupe(u8, r.input[raw_tag_start..r.position()]); errdefer allocator.free(raw); try _unknown_fields_list.append(allocator, raw); }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (self._unknown_fields) |raw| try w.appendSlice(raw);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self._unknown_fields.len != 0)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const indexes = try allocator.alloc(usize, self._unknown_fields.len);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn firstTag(raw: []const u8) ?pbz.wire.Tag") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (tag_a.?.number != tag_b.?.number) return tag_a.?.number < tag_b.?.number;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (tag_a.?.wire_type != tag_b.?.wire_type) return @intFromEnum(tag_a.?.wire_type) < @intFromEnum(tag_b.?.wire_type);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (indexes) |index| try w.appendSlice(self._unknown_fields[index]);") != null);
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
    try std.testing.expect(std.mem.indexOf(u8, content, "var ids_list: std.ArrayList(i32) = .empty") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try ids_list.append(allocator, try r.readInt32())") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "{ const value = try r.readInt32(); try kinds_list.append(allocator, value); }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var payload_reader = try r.nested(payload); var nested = try Child.decodeFromReader(allocator, &payload_reader); errdefer nested.deinit(allocator); try children_list.append(allocator, nested);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.ids = if (ids_list.items.len != 0 and ids_list.items.len == ids_list.capacity) ids_list.toOwnedSliceAssert() else try ids_list.toOwnedSlice(allocator)") != null);
}

test "codegen supports self-recursive generated schemas" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\message Node {
        \\  Node child = 1;
        \\  repeated Node children = 2;
        \\}
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "child: []const u8 = \"\",") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "has_child: bool = false,") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "children: []const Node = &.{},") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn decodeFromReader(allocator: std.mem.Allocator, r: *pbz.Reader) !@This()") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "2 => { const payload = try r.readBytes(); var payload_reader = try r.nested(payload); var nested = try Node.decodeFromReader(allocator, &payload_reader);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "child: ?Node") == null);

    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
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
    try std.testing.expect(std.mem.indexOf(u8, content, "var counts_list: std.ArrayList(countsEntry) = .empty") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var entry = countsEntry{}") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "1 => { const value = try entry_reader.readBytes(); if (!pbz.validateUtf8(value)) return error.InvalidUtf8; entry.key = value; }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "2 => entry.value = try entry_reader.readInt32()") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try @This().appendOrReplaceMapEntry_counts(allocator, &counts_list, entry)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try self.counts.ensureUnusedCapacity(allocator, counts_list.items.len)") != null);
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
    try std.testing.expect(std.mem.indexOf(u8, content, "has_a: bool = false") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "has_b: bool = false") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.has_a) try w.writeInt32(1, self.a)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.a = try r.readInt32(); self.has_a = true") != null);

    var file3 = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\message M { optional int32 a = 1; int32 b = 2; }
    );
    defer file3.deinit();
    const content3 = try generateZigFile(allocator, &file3);
    defer allocator.free(content3);
    try std.testing.expect(std.mem.indexOf(u8, content3, "has_a: bool = false") != null);
    try std.testing.expect(std.mem.indexOf(u8, content3, "has_b: bool = false") == null);
}

test "codegen emits proto2 scalar and enum defaults" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\enum Kind { UNKNOWN = 0; ADMIN = 7; }
        \\enum Code { OK = 5; FAIL = 6; }
        \\message Defaults {
        \\  optional int32 count = 1 [default = 42];
        \\  optional string name = 2 [default = "hello\nworld"];
        \\  optional bool enabled = 3 [default = true];
        \\  optional Kind kind = 4 [default = ADMIN];
        \\  optional bytes raw = 5 [default = "\001\x02"];
        \\  optional float ratio = 6 [default = inf];
        \\  optional Code code = 7;
        \\  optional double neg_ratio = 8 [default = -inf];
        \\  optional float quiet = 9 [default = nan];
        \\  optional float neg_quiet = 10 [default = -nan];
        \\  optional double infinity = 11 [default = Infinity];
        \\  optional double neg_infinity = 12 [default = -INFINITY];
        \\  optional uint64 max_u64 = 13 [default = 0xFFFFFFFFFFFFFFFF];
        \\}
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "count: i32 = 42") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "name: []const u8 = \"hello\\nworld\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "enabled: bool = true") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "kind: i32 = 7") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "raw: []const u8 = \"\\x01\\x02\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "ratio: f32 = std.math.inf(f32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "code: i32 = 5") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "neg_ratio: f64 = -std.math.inf(f64)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "quiet: f32 = std.math.nan(f32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "neg_quiet: f32 = std.math.nan(f32)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "infinity: f64 = std.math.inf(f64)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "neg_infinity: f64 = -std.math.inf(f64)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "max_u64: u64 = 18446744073709551615") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "has_count: bool = false") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.has_count or options.always_print_primitive_fields)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.has_kind or options.always_print_primitive_fields)") != null);
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
        \\  int32 user_id = 10;
        \\  string display_name = 11 [json_name = "shownName"];
        \\  oneof choice {
        \\    string alias = 8;
        \\    int32 code = 9;
        \\    string alt_name = 12;
        \\    Kind pick_kind = 13;
        \\  }
        \\}
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn jsonStringifyAlloc(self: @This(), allocator: std.mem.Allocator) ![]u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn jsonStringify(self: @This(), writer: *std.Io.Writer) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const JsonStringifyOptions = struct { enum_as_name: bool = true, preserve_proto_field_names: bool = false, always_print_primitive_fields: bool = false };") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (options.preserve_proto_field_names) \"\\\"id\\\":\" else \"\\\"id\\\":\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (options.preserve_proto_field_names) \"\\\"user_id\\\":\" else \"\\\"userId\\\":\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (options.preserve_proto_field_names) \"\\\"display_name\\\":\" else \"\\\"shownName\\\":\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.id != 0 or options.always_print_primitive_fields)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.kind != 0 or options.always_print_primitive_fields)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.tags.len != 0 or options.always_print_primitive_fields)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try @This().jsonWriteEnum(writer, value, &.{\"UNKNOWN\", \"ADMIN\"}, &.{0, 1}, options.enum_as_name);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try @This().jsonWriteString(writer, value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.print(\"\\\"{d}\\\"\", .{value});") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try std.base64.standard.Encoder.encodeWriter(writer, value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (self.tags, 0..) |item, i|") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.has_active)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "switch (self.choice)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, ".alias => |value|") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn jsonParse(allocator: std.mem.Allocator, text: []const u8) !@This()") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), text, .{})") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const JsonParseOptions = struct { ignore_unknown_fields: bool = false };") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn jsonParseWithOptions(allocator: std.mem.Allocator, text: []const u8, options: @This().JsonParseOptions) !@This()") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var self = try @This().jsonParseValueWithOptions(allocator, arena.allocator(), parsed, options)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self._json_arena = arena") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn jsonParseInitialized(allocator: std.mem.Allocator, text: []const u8) !@This()") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var self = try @This().jsonParse(allocator, text);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn jsonParseInitializedWithOptions(allocator: std.mem.Allocator, text: []const u8, options: @This().JsonParseOptions) !@This()") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try self.validateRequiredRecursive(allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn jsonFillFromValue(self: *@This(), allocator: std.mem.Allocator, arena_allocator: std.mem.Allocator, json_value: std.json.Value, options: @This().JsonParseOptions) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn jsonFloat(comptime T: type, value: std.json.Value) !T") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (std.mem.eql(u8, text, \"NaN\"))") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "else if (std.mem.eql(u8, text, \"Infinity\"))") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "else if (std.mem.eql(u8, text, \"-Infinity\"))") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (options.ignore_unknown_fields) continue;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (value == .null)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.id = try @This().jsonInt(i32, value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "std.mem.eql(u8, key, \"user_id\") or std.mem.eql(u8, key, \"userId\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "std.mem.eql(u8, key, \"display_name\") or std.mem.eql(u8, key, \"shownName\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.raw = try @This().jsonBytes(arena_allocator, value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.kind = @This().jsonEnum(value, &.{\"UNKNOWN\", \"ADMIN\"}, &.{0, 1}, false) catch |err| { if (options.ignore_unknown_fields) continue; return err; };") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (array.items) |item| try list.append(allocator, try @This().jsonString(item));") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.tags = blk: { const old = self.tags; const owned = try list.toOwnedSlice(allocator); if (old.len != 0) allocator.free(old); break :blk owned; };") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.tags = &.{}; if (old.len != 0) allocator.free(old);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.choice = .{ .alias = try @This().jsonString(value) };") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.choice = .none; continue;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "std.mem.eql(u8, key, \"alt_name\") or std.mem.eql(u8, key, \"altName\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.choice = .{ .pick_kind = @This().jsonEnum(value, &.{\"UNKNOWN\", \"ADMIN\"}, &.{0, 1}, false) catch |err| { if (options.ignore_unknown_fields) continue; return err; } };") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn jsonEnum(value: std.json.Value, comptime names: []const []const u8, comptime numbers: []const i32, comptime closed: bool) !i32") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn jsonEnumNumber(value: i32, comptime numbers: []const i32, comptime closed: bool) !i32") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn jsonWriteEnum(writer: *std.Io.Writer, value: i32, comptime names: []const []const u8, comptime numbers: []const i32, enum_as_name: bool) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn jsonWriteString(writer: *std.Io.Writer, value: []const u8) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (!pbz.validateUtf8(value)) return error.InvalidUtf8;") != null);
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
    try std.testing.expect(std.mem.indexOf(u8, content, "if (!self.has_id) return \"id\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn validateRequired(self: @This()) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.missingRequiredFieldName() != null) return error.MissingRequiredField") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "has_name") != null);
    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen emits recursive required validation for message payloads" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Child { required int32 id = 1; }
        \\message Parent {
        \\  optional Child child = 1;
        \\  repeated Child children = 2;
        \\  oneof pick { Child picked = 3; }
        \\  map<string, Child> keyed = 4;
        \\  extensions 100 to max;
        \\}
        \\extend Parent { optional Child child_ext = 100; }
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn validateRequiredRecursive(self: @This(), allocator: std.mem.Allocator) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn missingRequiredFieldPath(self: @This(), allocator: std.mem.Allocator) !?[]u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.child) |nested|") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (self.children) |nested|") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, ".picked => |nested|") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var map_it = self.keyed.iterator(); while (map_it.next()) |entry|") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try entry.value_ptr.validateRequiredRecursive(allocator)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const payloads = try extensions.child_ext.decodeAllFromUnknown(self, allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (payloads) |payload|") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try nested.validateRequiredRecursive(allocator)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try std.fmt.allocPrint(allocator, \"child_ext.{s}\", .{suffix});") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try std.fmt.allocPrint(allocator, \"child.{s}\", .{suffix});") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try std.fmt.allocPrint(allocator, \"children.{s}\", .{suffix});") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try std.fmt.allocPrint(allocator, \"keyed.{s}\", .{suffix});") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try std.fmt.allocPrint(allocator, \"picked.{s}\", .{suffix});") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try self.validateRequiredRecursive(allocator);") != null);
    const json_initialized_start = std.mem.indexOf(u8, content, "pub fn jsonParseInitialized").?;
    const json_initialized = content[json_initialized_start..];
    try std.testing.expect(std.mem.indexOf(u8, json_initialized, "try self.validateRequiredRecursive(allocator);") != null);
    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen emits mergeFrom for singular message payloads and groups" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Child { optional int32 id = 1; optional string name = 2; }
        \\message Parent {
        \\  optional int32 id = 1;
        \\  repeated int32 nums = 2;
        \\  optional Child child = 3;
        \\  optional group Box = 4 { optional int32 a = 5; optional int32 b = 6; }
        \\  oneof pick { string name = 7; Child picked = 8; }
        \\}
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "fn _pbzOwnedAllocator(self: *@This(), allocator: std.mem.Allocator) !std.mem.Allocator") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn mergeFrom(self: *@This(), allocator: std.mem.Allocator, other: @This()) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (other.nums.len != 0)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const merged = try allocator.alloc(i32, old.len + other.nums.len)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (other.child) |other_value|") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.child) |*self_value| { try self_value.mergeFrom(allocator, other_value); } else { self.child = try other_value.cloneOwned(allocator); }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (other.box) |other_value|") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.box) |*self_value| { try self_value.mergeFrom(allocator, other_value); } else { self.box = try other_value.cloneOwned(allocator); }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try existing.mergeFrom(allocator, nested)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "switch (other.pick)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, ".picked => |value| self.pick = .{ .picked = try value.cloneOwned(allocator) }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (other._unknown_fields) |raw| try self.appendUnknownRaw(allocator, raw);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "3 => { const payload = try r.readBytes(); var payload_reader = try r.nested(payload); var nested = try Child.decodeFromReader(allocator, &payload_reader);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "4 => { const payload = try r.readGroupBytes(4); var payload_reader = try r.nested(payload); var nested = try Box.decodeFromReader(allocator, &payload_reader);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.box) |value| { try w.writeTag(4, .start_group); try value.writeTo(w); try w.writeTag(4, .end_group); }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.box) |nested|") != null);

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
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const pickOneof = union(enum)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "name: []const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pick: pickOneof = .none") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "switch (self.pick)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, ".name => |value| { if (!pbz.validateUtf8(value)) return error.InvalidUtf8; try w.writeString(1, value); }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "1 => { const value = try r.readBytes(); if (!pbz.validateUtf8(value)) return error.InvalidUtf8; self.pick = .{ .name = value }; }") != null);
}

test "codegen emits proto2 extension metadata" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\enum Kind { UNKNOWN = 0; ADMIN = 7; }
        \\message Host { extensions 100 to max; }
        \\message Note {}
        \\extend Host {
        \\  optional string tag = 100 [default = "untagged"];
        \\  repeated int32 nums = 101;
        \\  optional Note note = 102;
        \\  repeated int32 packed_nums = 103 [packed = true];
        \\  repeated Note notes = 104;
        \\  optional Kind role = 105 [default = ADMIN];
        \\  repeated Kind roles = 106;
        \\}
    );
    defer file.deinit();
    try file.extensions.append(allocator, .{ .name = "legacy", .number = 107, .cardinality = .optional, .kind = .{ .group = "Note" }, .extendee = "Host" });
    try file.extensions.append(allocator, .{ .name = "legacies", .number = 108, .cardinality = .repeated, .kind = .{ .group = "Note" }, .extendee = "Host" });
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const extensions = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const tag = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const number = 100") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const extendee = \"Host\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const cardinality = \"optional\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const value_type = \"string\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const zig_type = \"[]const u8\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const typed_zig_type = \"[]const u8\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const has_default = true;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const default_value = \"untagged\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const default_value_zig: []const u8 = \"untagged\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn write(w: *pbz.Writer, value: []const u8) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeString(100, value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn encodeRaw(allocator: std.mem.Allocator, value: []const u8) ![]u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try write(&w, value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn appendToUnknown(message: anytype, allocator: std.mem.Allocator, value: []const u8) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try message.appendUnknownRaw(allocator, raw);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn hasInUnknown(message: anytype) !bool") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try message.hasUnknownFieldNumber(number);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn countInUnknown(message: anytype) !usize") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try message.unknownFieldCountByNumber(number);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn clearFromUnknown(message: anytype, allocator: std.mem.Allocator) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try message.clearUnknownFieldsByNumber(allocator, number);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn replaceInUnknown(message: anytype, allocator: std.mem.Allocator, value: []const u8) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try clearFromUnknown(message, allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try appendToUnknown(message, allocator, value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn decodeValue(r: *pbz.Reader) ![]const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try r.readBytes();") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn decodeRaw(raw: []const u8) !?[]const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (tag.number != number or tag.wire_type != .length_delimited) return null;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const value = try decodeValue(&r);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (!r.eof()) return error.InvalidWireType;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return value;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn decodeAllRaw(allocator: std.mem.Allocator, raw_fields: []const []const u8) ![][]const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (raw_fields) |raw| {") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (try decodeRaw(raw)) |value| try list.append(allocator, value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn decodeFromUnknownFieldsAlloc(message: anytype, allocator: std.mem.Allocator) ![][]const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try decodeAllRaw(allocator, message.unknownFields());") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn decodeAllFromUnknown(message: anytype, allocator: std.mem.Allocator) ![][]const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try decodeFromUnknownFieldsAlloc(message, allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn decodeFirstFromUnknown(message: anytype, allocator: std.mem.Allocator) !?[]const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return if (values.len == 0) null else values[values.len - 1];") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const nums = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const cardinality = \"repeated\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn writeAll(w: *pbz.Writer, values: []const i32) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (values) |value| try write(w, value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn encodeAllRaw(allocator: std.mem.Allocator, values: []const i32) ![]u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn appendAllToUnknown(message: anytype, allocator: std.mem.Allocator, values: []const i32) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (values) |value| try appendToUnknown(message, allocator, value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn replaceAllInUnknown(message: anytype, allocator: std.mem.Allocator, values: []const i32) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try appendAllToUnknown(message, allocator, values);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn decodeAppend(allocator: std.mem.Allocator, list: *std.ArrayList(i32), r: *pbz.Reader) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try list.append(allocator, try decodeValue(r));") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn decodeAppendRaw(allocator: std.mem.Allocator, list: *std.ArrayList(i32), raw: []const u8) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const packed_nums = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var packed_writer = pbz.Writer.init(w.allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (values) |value| try packed_writer.writeVarint(@as(u64, @bitCast(@as(i64, value))));") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeBytes(103, packed_writer.slice());") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn decodePackedRaw(allocator: std.mem.Allocator, raw: []const u8) !?[]i32") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (values.len == 0) return;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const raw = try encodeAllRaw(allocator, values);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "while (!packed_reader.eof()) try list.append(allocator, try packed_reader.readInt32());") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (try decodePackedRaw(allocator, raw)) |values| { defer allocator.free(values); try list.appendSlice(allocator, values); }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (extensions.packed_nums.decodePackedRaw(allocator, raw) catch null) |values| {") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (values) |value| {") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.writeAll(\"[demo.packed_nums]: \"); try writer.print(\"{d}\", .{value});") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const value_type = \"Note\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (@This().textFieldValue(line, \"[demo.tag]\") orelse @This().textFieldValue(line, \"[tag]\")) |raw_value|") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const raw = try extensions.tag.encodeRaw(allocator, try @This().textUnquote(try self._pbzOwnedAllocator(allocator), raw_value));") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const raw = try extensions.nums.encodeRaw(allocator, try @This().textInt(i32, raw_value));") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (@This().textBlockField(line, \"[demo.note]\") or @This().textBlockField(line, \"[note]\"))") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var nested = try Note.parseTextWithOptions(allocator, block, .{ .ignore_unknown_fields = options.ignore_unknown_fields });") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const raw = try extensions.note.encodeRaw(allocator, payload);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (std.mem.eql(u8, key, \"[demo.tag]\") or std.mem.eql(u8, key, \"[tag]\")) {") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try self.clearUnknownFieldsByNumber(allocator, extensions.tag.number); continue;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try extensions.tag.replaceInUnknown(self, allocator, try @This().jsonString(value));") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try extensions.nums.appendToUnknown(self, allocator, try @This().jsonInt(i32, item));") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var nested = try Note.jsonParseValueWithOptions(arena_allocator, arena_allocator") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try extensions.note.replaceInUnknown(self, allocator, try nested.encode(arena_allocator));") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const values = try extensions.tag.decodeAllFromUnknown(self, allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.writeAll(\"\\\"[demo.tag]\\\":\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const value = values[values.len - 1];") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try @This().jsonWriteString(writer, value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const values = try extensions.nums.decodeAllFromUnknown(self, allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.writeAll(\"\\\"[demo.nums]\\\":\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.writeAll(\"[\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try struct { fn write(allocator_: std.mem.Allocator, writer_: *std.Io.Writer, options_: anytype, payload_: []const u8) !void { var nested = try Note.decode(allocator_, payload_);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (extensions.tag.decodeRaw(raw) catch null) |value| {") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.writeAll(\"[demo.tag]: \"); try @This().textWriteQuotedBytes(value, writer);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (extensions.note.decodeRaw(raw) catch null) |payload| {") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.writeAll(\"[demo.note] {\\n\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var nested = try Note.decode(allocator, payload);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn hasExtension_tag(self: @This()) !bool") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try extensions.tag.hasInUnknown(self);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn countExtension_tag(self: @This()) !usize") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn getExtension_tag(self: @This(), allocator: std.mem.Allocator) !?[]const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try extensions.tag.decodeFirstFromUnknown(self, allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn getExtensionOrDefault_tag(self: @This(), allocator: std.mem.Allocator) ![]const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return (try self.getExtension_tag(allocator)) orelse extensions.tag.default_value_zig;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn setExtension_tag(self: *@This(), allocator: std.mem.Allocator, value: []const u8) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try extensions.tag.replaceInUnknown(self, allocator, value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn clearExtension_tag(self: *@This(), allocator: std.mem.Allocator) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try extensions.tag.clearFromUnknown(self, allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn setExtensionMessage_note(self: *@This(), allocator: std.mem.Allocator, value: Note) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const payload = try value.encode(allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try extensions.note.replaceInUnknown(self, allocator, payload);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn getExtensionMessage_note(self: @This(), allocator: std.mem.Allocator) !?Note") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const payload = (try extensions.note.decodeFirstFromUnknown(self, allocator)) orelse return null;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try Note.decode(allocator, payload);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn addExtensionMessage_notes(self: *@This(), allocator: std.mem.Allocator, value: Note) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try extensions.notes.appendToUnknown(self, allocator, payload);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn appendExtensionMessages_notes(self: *@This(), allocator: std.mem.Allocator, values: []const Note) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (values) |value| try self.addExtensionMessage_notes(allocator, value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn replaceExtensionMessages_notes(self: *@This(), allocator: std.mem.Allocator, values: []const Note) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try self.appendExtensionMessages_notes(allocator, values);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn getExtensionMessages_notes(self: @This(), allocator: std.mem.Allocator) ![]Note") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (payloads) |payload| try list.append(allocator, try Note.decode(allocator, payload));") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn getExtension_nums(self: @This(), allocator: std.mem.Allocator) ![]i32") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try extensions.nums.decodeAllFromUnknown(self, allocator);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn appendExtension_nums(self: *@This(), allocator: std.mem.Allocator, values: []const i32) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try extensions.nums.appendAllToUnknown(self, allocator, values);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn addExtension_nums(self: *@This(), allocator: std.mem.Allocator, value: i32) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try extensions.nums.appendToUnknown(self, allocator, value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn replaceExtension_nums(self: *@This(), allocator: std.mem.Allocator, values: []const i32) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try extensions.nums.replaceAllInUnknown(self, allocator, values);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const role = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const value_has_enum_ref = true;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const value_enum_ref = Kind;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const default_value = \"7\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const default_value_zig: i32 = 7;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return (try self.getExtension_role(allocator)) orelse extensions.role.default_value_zig;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn getEnumExtension_role(self: @This(), allocator: std.mem.Allocator) !?Kind") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return Kind.fromInt(raw);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn getEnumOrDefaultExtension_role(self: @This(), allocator: std.mem.Allocator) !Kind") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return (try self.getEnumExtension_role(allocator)) orelse Kind.fromInt(extensions.role.default_value_zig) orelse unreachable;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn setEnumExtension_role(self: *@This(), allocator: std.mem.Allocator, value: Kind) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try self.setExtension_role(allocator, value.toInt());") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn getEnumExtensions_roles(self: @This(), allocator: std.mem.Allocator) ![]Kind") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn appendEnumExtensions_roles(self: *@This(), allocator: std.mem.Allocator, values: []const Kind) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try self.appendExtension_roles(allocator, raw);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn replaceEnumExtensions_roles(self: *@This(), allocator: std.mem.Allocator, values: []const Kind) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try self.replaceExtension_roles(allocator, raw);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const legacy = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const value_type = \"Note\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn write(w: *pbz.Writer, value: []const u8) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeTag(107, .start_group);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.appendSlice(value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeTag(107, .end_group);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try r.readGroupBytes(number);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (@This().textBlockField(line, \"[demo.legacy]\") or @This().textBlockField(line, \"[legacy]\"))") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const raw = try extensions.legacy.encodeRaw(allocator, payload);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (std.mem.eql(u8, key, \"[demo.legacy]\") or std.mem.eql(u8, key, \"[legacy]\")) {") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try extensions.legacy.replaceInUnknown(self, allocator, try nested.encode(arena_allocator));") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (extensions.legacy.decodeRaw(raw) catch null) |payload| {") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.writeAll(\"[demo.legacy] {\\n\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn setExtensionMessage_legacy(self: *@This(), allocator: std.mem.Allocator, value: Note) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try extensions.legacy.replaceInUnknown(self, allocator, payload);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn getExtensionMessage_legacy(self: @This(), allocator: std.mem.Allocator) !?Note") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const payload = (try extensions.legacy.decodeFirstFromUnknown(self, allocator)) orelse return null;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const legacies = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeTag(108, .start_group);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn addExtensionMessage_legacies(self: *@This(), allocator: std.mem.Allocator, value: Note) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try extensions.legacies.appendToUnknown(self, allocator, payload);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn appendExtensionMessages_legacies(self: *@This(), allocator: std.mem.Allocator, values: []const Note) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn getExtensionMessages_legacies(self: @This(), allocator: std.mem.Allocator) ![]Note") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (payloads) |payload| try list.append(allocator, try Note.decode(allocator, payload));") != null);
    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen scopes qualified extensions to exact nested extendee" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host { extensions 100 to max; }
        \\message Outer {
        \\  message Host { extensions 100 to max; }
        \\  extend Host { optional int32 nested_ext = 100; }
        \\}
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);

    var count: usize = 0;
    var index: usize = 0;
    const needle = "pub fn hasExtension_nested_ext";
    while (std.mem.indexOfPos(u8, content, index, needle)) |found| {
        count += 1;
        index = found + needle.len;
    }
    try std.testing.expectEqual(@as(usize, 1), count);
}

test "codegen emits MessageSet extension write helper" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Host { option message_set_wire_format = true; extensions 4 to max; }
        \\message Note { optional int32 id = 1; }
        \\extend Host { optional Note note = 100; }
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeTag(1, .start_group);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeUInt32(2, 100);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeMessage(3, value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeTag(1, .end_group);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn encodeRaw(allocator: std.mem.Allocator, value: []const u8) ![]u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn appendToUnknown(message: anytype, allocator: std.mem.Allocator, value: []const u8) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (tag.number == 1 and tag.wire_type == .start_group) { const value = try decodeMessageSetItem(&r); if (!r.eof()) return error.InvalidWireType; return value; }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (tag.number == 100 and tag.wire_type == .length_delimited) { const value = try r.readBytes(); if (!r.eof()) return error.InvalidWireType; return value; }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn decodeMessageSetItem(r: *pbz.Reader) !?[]const u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const raw_type_id = try r.readUInt32(); if (raw_type_id == 0 or raw_type_id > std.math.maxInt(pbz.FieldNumber)) return error.InvalidFieldNumber; type_id = raw_type_id;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return if (type_id != null and type_id.? == 100) payload else null;") != null);
    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen with registry normalizes imported extension extendee names" {
    const allocator = std.testing.allocator;
    var common = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package common;
        \\message Host { extensions 100 to max; }
    );
    defer common.deinit();
    common.name = "common.proto";
    var app = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package app;
        \\import "common.proto";
        \\extend common.Host { optional string note = 100; }
    );
    defer app.deinit();
    app.name = "app.proto";
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);

    const content = try generateZigFileWithRegistry(allocator, &app, &registry);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "pub const extendee = \".common.Host\";") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const extendee = \"common.Host\";") == null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const extendee_type_ref = imports.common_proto.common.Host;") != null);

    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen detects imported MessageSet extension extendees" {
    const allocator = std.testing.allocator;
    var host = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package common;
        \\message Host { option message_set_wire_format = true; extensions 4 to max; }
    );
    defer host.deinit();
    host.name = "host.proto";
    var ext = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package app;
        \\import "host.proto";
        \\message Note { optional int32 id = 1; }
        \\extend common.Host { optional Note note = 100; }
    );
    defer ext.deinit();
    ext.name = "ext.proto";
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&host);
    try registry.addFile(&ext);

    const content = try generateZigFileWithRegistry(allocator, &ext, &registry);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeTag(1, .start_group);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeUInt32(2, 100);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeMessage(3, value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (tag.number == 1 and tag.wire_type == .start_group) { const value = try decodeMessageSetItem(&r); if (!r.eof()) return error.InvalidWireType; return value; }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn decodeMessageSetItem(r: *pbz.Reader) !?[]const u8") != null);
}

test "codegen emits service metadata and unary adapters" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\message Req {}
        \\message Res {}
        \\service Directory {
        \\  rpc Get (Req) returns (Res);
        \\  rpc Stream (stream Req) returns (stream Res);
        \\}
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const services = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const Directory = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const name = \"Directory\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const Get = struct") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const input_type = \"Req\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const output_type = \"Res\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const input_has_type_ref = true") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const input_type_ref = Req;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const output_has_type_ref = true") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const output_type_ref = Res;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const client_streaming = true") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const server_streaming = true") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn Handler(comptime Impl: type) type") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn Client(comptime Transport: type) type") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn Get(self: @This(), allocator: std.mem.Allocator, request: Req) !Res") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try self.impl.Get(allocator, request);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn dispatchRaw(self: @This(), allocator: std.mem.Allocator, method_name: []const u8, request_payload: []const u8) !?[]u8") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var request = try Req.decodeOwned(allocator, request_payload);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var response = try self.Get(allocator, request);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const response_payload = try self.transport.call(allocator, \"Directory\", \"Get\", request_payload);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn Stream(self: @This(), allocator: std.mem.Allocator, requests: anytype, responses: anytype) !void") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try self.impl.Stream(allocator, requests, responses);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try self.transport.callBidiStream(allocator, \"Directory\", \"Stream\", requests, responses);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "dispatchTyped") == null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return error.Unimplemented;") == null);
    try std.testing.expect(std.mem.indexOf(u8, content, "@\"_pbzDispatchTyped_Get\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn GetTyped") == null);
    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen emits registry-aware service metadata type references" {
    const allocator = std.testing.allocator;
    var common = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package common;
        \\message Req { optional string q = 1; }
        \\message Res { optional string value = 1; }
    );
    defer common.deinit();
    common.name = "common.proto";
    var app = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package app;
        \\import "common.proto";
        \\service Directory {
        \\  rpc Get (common.Req) returns (common.Res);
        \\}
    );
    defer app.deinit();
    app.name = "app.proto";
    var reg = registry_mod.Registry.init(allocator);
    defer reg.deinit();
    try reg.addFile(&common);
    try reg.addFile(&app);

    const content = try generateZigFileWithRegistry(allocator, &app, &reg);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const input_type = \"common.Req\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const input_has_type_ref = true") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const input_type_ref = imports.common_proto.common.Req;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const output_has_type_ref = true") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub const output_type_ref = imports.common_proto.common.Res;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn Get(self: @This(), allocator: std.mem.Allocator, request: imports.common_proto.common.Req) !imports.common_proto.common.Res") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var request = try imports.common_proto.common.Req.decodeOwned(allocator, request_payload);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "return try imports.common_proto.common.Res.decodeOwned(allocator, response_payload);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "pub fn GetTyped") == null);
    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
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
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.id != 0) try w.writeInt32(1, self.id)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.active) try w.writeBool(2, self.active)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.kind != 0) try w.writeInt32(3, self.kind)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.has_opt) try w.writeInt32(4, self.opt)") != null);
}

test "codegen honors editions field presence features" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\edition = "2023";
        \\option features.field_presence = EXPLICIT;
        \\message M {
        \\  int32 explicit_id = 1;
        \\  int32 implicit_id = 2 [features.field_presence = IMPLICIT];
        \\  int32 required_id = 3 [features.field_presence = LEGACY_REQUIRED];
        \\}
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "has_explicit_id: bool = false") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "has_implicit_id: bool = false") == null);
    try std.testing.expect(std.mem.indexOf(u8, content, "has_required_id: bool = false") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.has_explicit_id) try w.writeInt32(1, self.explicit_id)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.implicit_id != 0) try w.writeInt32(2, self.implicit_id)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.has_required_id) try w.writeInt32(3, self.required_id)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.explicit_id = try r.readInt32(); self.has_explicit_id = true") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.required_id = try r.readInt32(); self.has_required_id = true") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (!self.has_required_id) return \"required_id\";") != null);
}

test "codegen honors editions message encoding features" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\edition = "2023";
        \\option features.message_encoding = DELIMITED;
        \\message Child { int32 id = 1; }
        \\message Parent {
        \\  Child delimited = 1;
        \\  Child length_prefixed = 2 [features.message_encoding = LENGTH_PREFIXED];
        \\  oneof pick { Child picked = 3 [features.message_encoding = DELIMITED]; }
        \\}
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeTag(1, .start_group); try w.appendSlice(self.delimited); try w.writeTag(1, .end_group);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.length_prefixed) |value| { const payload_len = value.encodedSize(); try w.writeTag(2, .length_delimited); try w.writeVarint(payload_len); try value.writeTo(w); }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try w.writeTag(3, .start_group); try w.appendSlice(value); try w.writeTag(3, .end_group)") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const payload = try r.readGroupBytes(1); if (self.has_delimited") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.has_delimited = true;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "var nested = try Child.decode(allocator, payload);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.length_prefixed = nested;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.pick = .{ .picked = try r.readGroupBytes(3) }") != null);

    const source = try allocator.dupeZ(u8, content);
    defer allocator.free(source);
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.errors.len);
}

test "codegen honors utf8 validation features for wire strings" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\edition = "2023";
        \\message M {
        \\  string strict = 1;
        \\  string relaxed = 2 [features.utf8_validation = NONE];
        \\  repeated string tags = 3;
        \\  oneof pick { string alias = 4; }
        \\  map<string, string> labels = 5;
        \\  map<string, string> relaxed_labels = 6 [features.utf8_validation = NONE];
        \\}
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.has_strict) { if (!pbz.validateUtf8(self.strict)) return error.InvalidUtf8; try w.writeString(1, self.strict); }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (self.has_relaxed) try w.writeString(2, self.relaxed);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "for (self.tags) |item| { if (!pbz.validateUtf8(item)) return error.InvalidUtf8; try w.writeString(3, item); }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, ".alias => |value| { if (!pbz.validateUtf8(value)) return error.InvalidUtf8; try w.writeString(4, value); }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "1 => { self.strict = try r.readBytes(); if (!pbz.validateUtf8(self.strict)) return error.InvalidUtf8; self.has_strict = true; }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "2 => { self.relaxed = try r.readBytes(); self.has_relaxed = true; }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "3 => { const value = try r.readBytes(); if (!pbz.validateUtf8(value)) return error.InvalidUtf8; try tags_list.append(allocator, value); },") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "4 => { const value = try r.readBytes(); if (!pbz.validateUtf8(value)) return error.InvalidUtf8; self.pick = .{ .alias = value }; }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (!pbz.validateUtf8(entry.key)) return error.InvalidUtf8;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (!pbz.validateUtf8(entry.value)) return error.InvalidUtf8;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "1 => { const value = try entry_reader.readBytes(); if (!pbz.validateUtf8(value)) return error.InvalidUtf8; entry.key = value; }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "2 => { const value = try entry_reader.readBytes(); if (!pbz.validateUtf8(value)) return error.InvalidUtf8; entry.value = value; }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.writeAll(\"strict: \"); const value = self.strict; if (!pbz.validateUtf8(value)) return error.InvalidUtf8; try @This().textWriteQuotedBytes(value, writer);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.writeAll(\"key: \"); if (!pbz.validateUtf8(entry.key)) return error.InvalidUtf8; try @This().textWriteQuotedBytes(entry.key, writer);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try writer.writeAll(\"value: \"); if (!pbz.validateUtf8(entry.value)) return error.InvalidUtf8; try @This().textWriteQuotedBytes(entry.value, writer);") != null);

    const text_start = std.mem.indexOf(u8, content, "pub fn parseText").?;
    const text_content = content[text_start..];
    try std.testing.expect(std.mem.indexOf(u8, text_content, "self.strict = blk: { const decoded = try @This().textUnquote(try self._pbzOwnedAllocator(allocator), raw_value); if (!pbz.validateUtf8(decoded)) return error.InvalidUtf8; break :blk decoded; };") != null);
    try std.testing.expect(std.mem.indexOf(u8, text_content, "self.relaxed = try @This().textUnquote(try self._pbzOwnedAllocator(allocator), raw_value);") != null);
    try std.testing.expect(std.mem.indexOf(u8, text_content, "tags_list.append(allocator, blk: { const decoded = try @This().textUnquote(try self._pbzOwnedAllocator(allocator), raw_value); if (!pbz.validateUtf8(decoded)) return error.InvalidUtf8; break :blk decoded; })") != null);
    try std.testing.expect(std.mem.indexOf(u8, text_content, "entry.key = blk: { const decoded = try @This().textUnquote(try self._pbzOwnedAllocator(allocator), raw_key); if (!pbz.validateUtf8(decoded)) return error.InvalidUtf8; break :blk decoded; };") != null);
    try std.testing.expect(std.mem.indexOf(u8, text_content, "entry.value = blk: { const decoded = try @This().textUnquote(try self._pbzOwnedAllocator(allocator), raw_value); if (!pbz.validateUtf8(decoded)) return error.InvalidUtf8; break :blk decoded; };") != null);
    try std.testing.expect(std.mem.indexOf(u8, text_content, "self.pick = .{ .alias = blk: { const decoded = try @This().textUnquote(try self._pbzOwnedAllocator(allocator), raw_value); if (!pbz.validateUtf8(decoded)) return error.InvalidUtf8; break :blk decoded; } };") != null);
}

test "codegen honors editions enum type features in JSON parse" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\edition = "2023";
        \\option features.enum_type = OPEN;
        \\enum ClosedKind { option features.enum_type = CLOSED; UNKNOWN = 0; ADMIN = 1; }
        \\enum OpenKind { option features.enum_type = OPEN; NONE = 0; USER = 1; }
        \\message M {
        \\  ClosedKind closed = 1;
        \\  OpenKind open = 2;
        \\}
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "self.closed = @This().jsonEnum(value, &.{\"UNKNOWN\", \"ADMIN\"}, &.{0, 1}, true) catch |err| { if (options.ignore_unknown_fields) continue; return err; };") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.open = @This().jsonEnum(value, &.{\"NONE\", \"USER\"}, &.{0, 1}, false) catch |err| { if (options.ignore_unknown_fields) continue; return err; };") != null);
}

test "codegen validates closed enum values in wire decode" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\edition = "2023";
        \\option features.enum_type = OPEN;
        \\enum ClosedKind { option features.enum_type = CLOSED; UNKNOWN = 0; ADMIN = 1; }
        \\message M {
        \\  ClosedKind single = 1;
        \\  repeated ClosedKind many = 2;
        \\  oneof pick { ClosedKind choice = 3; }
        \\}
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "1 => { const value = try r.readInt32(); if (!@This().enumKnown(value, &.{0, 1})) { const start = r.position() - pbz.wire.encodedVarintSize(try tag.encode()); const raw = try allocator.dupe(u8, r.input[start..r.position()]); errdefer allocator.free(raw); try _unknown_fields_list.append(allocator, raw); } else { self.single = value; self.has_single = true; } }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (!@This().enumKnown(value, &.{0, 1})) { var unknown_writer = pbz.Writer.init(allocator); defer unknown_writer.deinit(); try unknown_writer.writeTag(2, .varint);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try unknown_writer.appendSlice(payload[value_start..value_end]); const raw = try allocator.dupe(u8, unknown_writer.slice());") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "{ const value = try r.readInt32(); if (!@This().enumKnown(value, &.{0, 1})) { const start = r.position() - pbz.wire.encodedVarintSize(try tag.encode()); const raw = try allocator.dupe(u8, r.input[start..r.position()]); errdefer allocator.free(raw); try _unknown_fields_list.append(allocator, raw); } else { try many_list.append(allocator, value); } }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "3 => { const value = try r.readInt32(); if (!@This().enumKnown(value, &.{0, 1})) { const start = r.position() - pbz.wire.encodedVarintSize(try tag.encode()); const raw = try allocator.dupe(u8, r.input[start..r.position()]); errdefer allocator.free(raw); try _unknown_fields_list.append(allocator, raw); } else { self.pick = .{ .choice = value }; } }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "fn enumKnown(value: i32, comptime numbers: []const i32) bool") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.single = @This().textEnum(raw_value, &.{\"UNKNOWN\", \"ADMIN\"}, &.{0, 1}, true) catch |err| { if (options.ignore_unknown_fields) { continue; } return err; };") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "const parsed_enum = @This().textEnum(raw_value, &.{\"UNKNOWN\", \"ADMIN\"}, &.{0, 1}, true) catch |err| { if (options.ignore_unknown_fields) { continue; } return err; };") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "self.pick = .{ .choice = @This().textEnum(raw_value, &.{\"UNKNOWN\", \"ADMIN\"}, &.{0, 1}, true) catch |err| { if (options.ignore_unknown_fields) { continue; } return err; } };") != null);
}

test "codegen validates closed enum map values in wire decode" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\edition = "2023";
        \\option features.enum_type = OPEN;
        \\enum ClosedKind { option features.enum_type = CLOSED; UNKNOWN = 0; ADMIN = 1; }
        \\message M { map<string, ClosedKind> keyed = 1; }
    );
    defer file.deinit();
    const content = try generateZigFile(allocator, &file);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "var skip_entry = false;") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "2 => { const value = try entry_reader.readInt32(); if (!@This().enumKnown(value, &.{0, 1})) { skip_entry = true; } else { entry.value = value; } }") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "if (skip_entry) { var unknown_writer = pbz.Writer.init(allocator); defer unknown_writer.deinit(); try unknown_writer.writeBytes(1, payload);") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "try _unknown_fields_list.append(allocator, raw); } else try @This().putMapEntry_keyed(allocator, &self.keyed, entry);") != null);
}
