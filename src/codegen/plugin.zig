const std = @import("std");
const schema = @import("../schema.zig");
const plugin = @import("../plugin.zig");
const registry_mod = @import("../registry.zig");

const cg = @import("../codegen.zig");
const Error = cg.Error;

const PluginParameterOptions = struct {
    include_imports: bool = false,
    generated_info: bool = true,
    pbz_import: []const u8 = "pbz",
    emit_json: bool = true,
    emit_text: bool = true,
    emit_descriptor: bool = true,
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

pub fn parsePluginParameters(parameter: []const u8) error{InvalidPluginParameter}!PluginParameterOptions {
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
        } else if (std.mem.eql(u8, key, "descriptor") or std.mem.eql(u8, key, "emit_descriptor")) {
            options.emit_descriptor = try parseParameterBool(maybe_value orelse "true");
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

pub fn splitParameter(part: []const u8) struct { []const u8, ?[]const u8 } {
    if (std.mem.indexOfScalar(u8, part, '=')) |idx| {
        return .{ std.mem.trim(u8, part[0..idx], " \t\r\n"), std.mem.trim(u8, part[idx + 1 ..], " \t\r\n") };
    }
    return .{ part, null };
}

pub fn parseParameterBool(value: []const u8) error{InvalidPluginParameter}!bool {
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

pub fn generatePluginResponseForSelected(allocator: std.mem.Allocator, files: []const *const schema.FileDescriptor, registry: *const registry_mod.Registry, options: PluginParameterOptions) Error![]u8 {
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
        const content = try cg.generateZigFileWithContext(.{ .allocator = allocator, .file = file, .registry = registry, .pbz_import = options.pbz_import, .emit_json = options.emit_json, .emit_text = options.emit_text, .output_suffix = options.output_suffix, .strip_proto_ext = options.strip_proto_ext });
        errdefer allocator.free(content);
        const name = try cg.outputNameWithOptions(allocator, file.name, options.output_suffix, options.strip_proto_ext);
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

pub fn findRequestFile(request: *const plugin.CodeGeneratorRequest, name: []const u8) ?*const schema.FileDescriptor {
    for (request.proto_files.items) |*file| {
        if (std.mem.eql(u8, file.name, name)) return file;
    }
    return null;
}

pub fn encodePluginErrorResponse(allocator: std.mem.Allocator, message: []const u8) Error![]u8 {
    return try (plugin.CodeGeneratorResponse{
        .error_message = message,
        .supported_features = generatedResponseFeatureMask(),
        .minimum_edition = .proto2,
        .maximum_edition = .edition_2026,
    }).encode(allocator);
}

pub fn generatedResponseFeatureMask() u64 {
    return plugin.CodeGeneratorResponse.featureMask(&[_]plugin.CodeGeneratorResponse.Feature{ .proto3_optional, .supports_editions });
}

pub fn populateGeneratedCodeInfo(allocator: std.mem.Allocator, file: *const schema.FileDescriptor, content: []const u8, info: *schema.GeneratedCodeInfo) Error!void {
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

pub fn appendGeneratedMessageAnnotations(allocator: std.mem.Allocator, info: *schema.GeneratedCodeInfo, source_file: []const u8, content: []const u8, path: []const i32, message: *const schema.MessageDescriptor) Error!void {
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

pub fn appendGeneratedOneofAnnotation(allocator: std.mem.Allocator, info: *schema.GeneratedCodeInfo, source_file: []const u8, content: []const u8, path: []const i32, oneof_name: []const u8) Error!void {
    const symbol = try std.fmt.allocPrint(allocator, "{s}Oneof", .{oneof_name});
    defer allocator.free(symbol);
    try appendGeneratedSymbolAnnotation(allocator, info, source_file, content, path, symbol, .set);
}

pub fn appendGeneratedEnumAnnotations(allocator: std.mem.Allocator, info: *schema.GeneratedCodeInfo, source_file: []const u8, content: []const u8, path: []const i32, enumeration: *const schema.EnumDescriptor) Error!void {
    try appendGeneratedSymbolAnnotation(allocator, info, source_file, content, path, enumeration.name, .set);
    for (enumeration.values.items, 0..) |value, i| {
        const value_path = try appendPathPair(allocator, path, 2, @intCast(i));
        defer allocator.free(value_path);
        try appendGeneratedSymbolAnnotation(allocator, info, source_file, content, value_path, value.name, .set);
    }
}

pub fn appendGeneratedServiceAnnotations(allocator: std.mem.Allocator, info: *schema.GeneratedCodeInfo, source_file: []const u8, content: []const u8, path: []const i32, service: *const schema.ServiceDescriptor) Error!void {
    try appendGeneratedSymbolAnnotation(allocator, info, source_file, content, path, service.name, .set);
    for (service.methods.items, 0..) |method, i| {
        const method_path = try appendPathPair(allocator, path, 2, @intCast(i));
        defer allocator.free(method_path);
        try appendGeneratedSymbolAnnotation(allocator, info, source_file, content, method_path, method.name, .set);
    }
}

pub fn appendPathPair(allocator: std.mem.Allocator, base: []const i32, field_number: i32, index: i32) std.mem.Allocator.Error![]i32 {
    const out = try allocator.alloc(i32, base.len + 2);
    @memcpy(out[0..base.len], base);
    out[base.len] = field_number;
    out[base.len + 1] = index;
    return out;
}

pub fn appendGeneratedSymbolAnnotation(allocator: std.mem.Allocator, info: *schema.GeneratedCodeInfo, source_file: []const u8, content: []const u8, path: []const i32, symbol: []const u8, semantic: schema.GeneratedCodeInfo.Semantic) Error!void {
    const range = findGeneratedSymbolRange(allocator, content, symbol) catch return;
    defer allocator.free(range.needle);
    try appendGeneratedAnnotation(allocator, info, source_file, path, range.begin, range.end, semantic);
}

pub fn appendGeneratedExtensionAnnotation(allocator: std.mem.Allocator, info: *schema.GeneratedCodeInfo, source_file: []const u8, content: []const u8, path: []const i32, extension_name: []const u8) Error!void {
    const extensions_idx = std.mem.indexOf(u8, content, "pub const extensions = struct") orelse return;
    const range = findGeneratedSymbolRangeFrom(allocator, content, extension_name, extensions_idx) catch return;
    defer allocator.free(range.needle);
    try appendGeneratedAnnotation(allocator, info, source_file, path, range.begin, range.end, .set);
}

const GeneratedSymbolRange = struct { begin: usize, end: usize, needle: []u8 };

pub fn findGeneratedSymbolRange(allocator: std.mem.Allocator, content: []const u8, symbol: []const u8) Error!GeneratedSymbolRange {
    return try findGeneratedSymbolRangeFrom(allocator, content, symbol, 0);
}

pub fn findGeneratedSymbolRangeFrom(allocator: std.mem.Allocator, content: []const u8, symbol: []const u8, start_index: usize) Error!GeneratedSymbolRange {
    const pub_const = try makeGeneratedNeedle(allocator, "pub const ", symbol);
    if (findGeneratedNeedleRange(content, pub_const, start_index)) |range| return .{ .begin = range.begin, .end = range.end, .needle = pub_const };
    allocator.free(pub_const);

    const quoted = try makeGeneratedNeedle(allocator, "", symbol);
    if (findGeneratedNeedleRange(content, quoted, start_index)) |range| return .{ .begin = range.begin, .end = range.end, .needle = quoted };
    allocator.free(quoted);
    return error.OutOfMemory;
}

pub fn makeGeneratedNeedle(allocator: std.mem.Allocator, prefix: []const u8, symbol: []const u8) Error![]u8 {
    var needle_writer: std.Io.Writer.Allocating = .init(allocator);
    errdefer needle_writer.deinit();
    try needle_writer.writer.writeAll(prefix);
    try cg.writeQuotedIdent(symbol, &needle_writer.writer);
    return try needle_writer.toOwnedSlice();
}

pub fn findGeneratedNeedleRange(content: []const u8, needle: []const u8, start_index: usize) ?struct { begin: usize, end: usize } {
    const begin = std.mem.indexOfPos(u8, content, start_index, needle) orelse return null;
    const next = std.mem.indexOfPos(u8, content, begin + needle.len, "\npub const ") orelse content.len;
    return .{ .begin = begin, .end = next };
}

pub fn appendGeneratedAnnotation(allocator: std.mem.Allocator, info: *schema.GeneratedCodeInfo, source_file: []const u8, path: []const i32, begin: usize, end: usize, semantic: schema.GeneratedCodeInfo.Semantic) std.mem.Allocator.Error!void {
    var annotation = schema.GeneratedCodeInfo.Annotation{};
    errdefer annotation.deinit(allocator);
    try annotation.path.appendSlice(allocator, path);
    annotation.source_file = source_file;
    annotation.begin = @intCast(begin);
    annotation.end = @intCast(end);
    annotation.semantic = semantic;
    try info.annotations.append(allocator, annotation);
}
