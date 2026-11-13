const std = @import("std");
const schema = @import("../schema.zig");

const cg = @import("../codegen.zig");
const Error = cg.Error;
const CodegenContext = cg.CodegenContext;

pub fn writeServiceMetadata(ctx: *const CodegenContext, writer: *std.Io.Writer, depth: usize) Error!void {
    const file = ctx.file;
    if (file.services.items.len == 0) return;
    try cg.indent(writer, depth);
    try writer.writeAll("pub const services = struct {\n");
    for (file.services.items) |*service| try writeServiceDecl(ctx, service, writer, depth + 1);
    try cg.indent(writer, depth);
    try writer.writeAll("};\n\n");
}

pub fn writeServiceDecl(ctx: *const CodegenContext, service: *const schema.ServiceDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try cg.indent(writer, depth);
    try writer.writeAll("pub const ");
    try cg.writeQuotedIdent(service.name, writer);
    try writer.writeAll(" = struct {\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("pub const name = ");
    try cg.writeZigStringLiteral(service.name, writer);
    try writer.writeAll(";\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("pub const deprecated = ");
    try writer.writeAll(if (optionListBool(service.options.items, "deprecated") orelse false) "true" else "false");
    try writer.writeAll(";\n");
    if (ctx.emit_descriptor) {
        try cg.indent(writer, depth + 1);
        try writer.writeAll("/// Look up this service's descriptor in a decoded file descriptor.\n");
        try cg.indent(writer, depth + 1);
        try writer.writeAll("pub fn descriptor(file: *const pbz.schema.FileDescriptor) ?*const pbz.schema.ServiceDescriptor {\n");
        try cg.indent(writer, depth + 2);
        try writer.writeAll("return file.findService(");
        try cg.writeZigStringLiteral(service.name, writer);
        try writer.writeAll(");\n");
        try cg.indent(writer, depth + 1);
        try writer.writeAll("}\n");
    }
    for (service.methods.items) |*method| try writeMethodDecl(ctx, method, writer, depth + 1);
    if (serviceHasAdapters(ctx, service)) {
        try writeServiceHandlerDecl(ctx, service, writer, depth + 1);
        try writeServiceClientDecl(ctx, service, writer, depth + 1);
    }
    try cg.indent(writer, depth);
    try writer.writeAll("};\n");
}

pub fn writeMethodDecl(ctx: *const CodegenContext, method: *const schema.MethodDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try cg.indent(writer, depth);
    try writer.writeAll("pub const ");
    try cg.writeQuotedIdent(method.name, writer);
    try writer.writeAll(" = struct {\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("pub const name = ");
    try cg.writeZigStringLiteral(method.name, writer);
    try writer.writeAll(";\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("pub const deprecated = ");
    try writer.writeAll(if (optionListBool(method.options.items, "deprecated") orelse false) "true" else "false");
    try writer.writeAll(";\n");
    const idempotency_number = methodIdempotencyLevel(method.options.items) orelse 0;
    try cg.indent(writer, depth + 1);
    try writer.writeAll("pub const idempotency_level = ");
    try cg.writeZigStringLiteral(idempotencyLevelName(idempotency_number), writer);
    try writer.writeAll(";\n");
    try cg.indent(writer, depth + 1);
    try writer.print("pub const idempotency_level_number = {d};\n", .{idempotency_number});
    try cg.indent(writer, depth + 1);
    try writer.writeAll("pub const input_type = ");
    try cg.writeZigStringLiteral(method.input_type, writer);
    try writer.writeAll(";\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("pub const output_type = ");
    try cg.writeZigStringLiteral(method.output_type, writer);
    try writer.writeAll(";\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("pub const input_has_type_ref = ");
    try writer.writeAll(if (cg.codegenCanReferenceMessageWithContext(ctx, method.input_type)) "true" else "false");
    try writer.writeAll(";\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("pub const input_type_ref = ");
    try writeRpcMessageTypeReferenceOrVoid(ctx, method.input_type, writer);
    try writer.writeAll(";\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("pub const output_has_type_ref = ");
    try writer.writeAll(if (cg.codegenCanReferenceMessageWithContext(ctx, method.output_type)) "true" else "false");
    try writer.writeAll(";\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("pub const output_type_ref = ");
    try writeRpcMessageTypeReferenceOrVoid(ctx, method.output_type, writer);
    try writer.writeAll(";\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("pub const client_streaming = ");
    try writer.writeAll(if (method.client_streaming) "true" else "false");
    try writer.writeAll(";\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("pub const server_streaming = ");
    try writer.writeAll(if (method.server_streaming) "true" else "false");
    try writer.writeAll(";\n");
    if (ctx.emit_descriptor) {
        try cg.indent(writer, depth + 1);
        try writer.writeAll("/// Look up this method's descriptor in a decoded service descriptor.\n");
        try cg.indent(writer, depth + 1);
        try writer.writeAll("pub fn descriptor(service: *const pbz.schema.ServiceDescriptor) ?*const pbz.schema.MethodDescriptor {\n");
        try cg.indent(writer, depth + 2);
        try writer.writeAll("return service.findMethod(");
        try cg.writeZigStringLiteral(method.name, writer);
        try writer.writeAll(");\n");
        try cg.indent(writer, depth + 1);
        try writer.writeAll("}\n");
    }
    try cg.indent(writer, depth);
    try writer.writeAll("};\n");
}

pub fn optionListBool(options: []const schema.FieldOption, name: []const u8) ?bool {
    for (options) |option| {
        if (std.mem.eql(u8, std.mem.trim(u8, option.name, " \t\r\n"), name)) return schema.optionAsBool(option.value);
    }
    return null;
}

pub fn methodIdempotencyLevel(options: []const schema.FieldOption) ?i32 {
    for (options) |option| {
        if (!std.mem.eql(u8, std.mem.trim(u8, option.name, " \t\r\n"), "idempotency_level")) continue;
        return switch (option.value) {
            .integer => |value| std.math.cast(i32, value),
            .unsigned_integer => |value| std.math.cast(i32, value),
            .identifier, .string => |value| idempotencyLevelNumber(value),
            else => null,
        };
    }
    return null;
}

pub fn idempotencyLevelNumber(value: []const u8) ?i32 {
    if (std.mem.eql(u8, value, "IDEMPOTENCY_UNKNOWN")) return 0;
    if (std.mem.eql(u8, value, "NO_SIDE_EFFECTS")) return 1;
    if (std.mem.eql(u8, value, "IDEMPOTENT")) return 2;
    return null;
}

pub fn idempotencyLevelName(number: i32) []const u8 {
    return switch (number) {
        1 => "NO_SIDE_EFFECTS",
        2 => "IDEMPOTENT",
        else => "IDEMPOTENCY_UNKNOWN",
    };
}

pub fn serviceHasAdapters(ctx: *const CodegenContext, service: *const schema.ServiceDescriptor) bool {
    for (service.methods.items) |*method| {
        if (methodHasMessageTypes(ctx, method)) return true;
    }
    return false;
}

pub fn methodHasMessageTypes(ctx: *const CodegenContext, method: *const schema.MethodDescriptor) bool {
    return cg.codegenCanReferenceMessageWithContext(ctx, method.input_type) and cg.codegenCanReferenceMessageWithContext(ctx, method.output_type);
}

pub fn methodHasUnaryAdapter(ctx: *const CodegenContext, method: *const schema.MethodDescriptor) bool {
    return !method.client_streaming and !method.server_streaming and methodHasMessageTypes(ctx, method);
}

pub fn writeServiceHandlerDecl(ctx: *const CodegenContext, service: *const schema.ServiceDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try writer.writeAll("\n");
    try cg.indent(writer, depth);
    try writer.writeAll("pub fn Handler(comptime Impl: type) type {\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("return struct {\n");
    try cg.indent(writer, depth + 2);
    try writer.writeAll("impl: *Impl,\n\n");
    try cg.indent(writer, depth + 2);
    try writer.writeAll("pub fn init(impl: *Impl) @This() { return .{ .impl = impl }; }\n\n");
    for (service.methods.items) |*method| {
        if (methodHasMessageTypes(ctx, method)) try writeServiceHandlerMethod(ctx, method, writer, depth + 2);
    }
    try writeServiceDispatchRaw(ctx, service, writer, depth + 2);
    try cg.indent(writer, depth + 1);
    try writer.writeAll("};\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeServiceHandlerMethod(ctx: *const CodegenContext, method: *const schema.MethodDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try cg.indent(writer, depth);
    try writer.writeAll("pub fn ");
    try cg.writeQuotedIdent(method.name, writer);
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
    try cg.indent(writer, depth + 1);
    try writer.writeAll("return try self.impl.");
    try cg.writeQuotedIdent(method.name, writer);
    try writer.writeAll("(allocator, ");
    if (method.client_streaming) {
        try writer.writeAll("requests");
    } else {
        try writer.writeAll("request");
    }
    if (method.server_streaming) try writer.writeAll(", responses");
    try writer.writeAll(");\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n\n");
}

pub fn writeServiceDispatchRaw(ctx: *const CodegenContext, service: *const schema.ServiceDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try cg.indent(writer, depth);
    try writer.writeAll("pub fn dispatchRaw(self: @This(), allocator: std.mem.Allocator, method_name: []const u8, request_payload: []const u8) !?[]u8 {\n");
    var wrote_any = false;
    for (service.methods.items) |*method| {
        if (!methodHasUnaryAdapter(ctx, method)) continue;
        wrote_any = true;
        try cg.indent(writer, depth + 1);
        try writer.writeAll("if (std.mem.eql(u8, method_name, ");
        try cg.writeZigStringLiteral(method.name, writer);
        try writer.writeAll(")) {\n");
        try cg.indent(writer, depth + 2);
        try writer.writeAll("var request = try ");
        try writeRpcMessageTypeReference(ctx, method.input_type, writer);
        try writer.writeAll(".decodeOwned(allocator, request_payload);\n");
        try cg.indent(writer, depth + 2);
        try writer.writeAll("defer request.deinit(allocator);\n");
        try cg.indent(writer, depth + 2);
        try writer.writeAll("var response = try self.");
        try cg.writeQuotedIdent(method.name, writer);
        try writer.writeAll("(allocator, request);\n");
        try cg.indent(writer, depth + 2);
        try writer.writeAll("defer response.deinit(allocator);\n");
        try cg.indent(writer, depth + 2);
        try writer.writeAll("return try response.encode(allocator);\n");
        try cg.indent(writer, depth + 1);
        try writer.writeAll("}\n");
    }
    if (!wrote_any) {
        try cg.indent(writer, depth + 1);
        try writer.writeAll("_ = self; _ = allocator; _ = method_name; _ = request_payload;\n");
    }
    try cg.indent(writer, depth + 1);
    try writer.writeAll("return null;\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeServiceClientDecl(ctx: *const CodegenContext, service: *const schema.ServiceDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try writer.writeAll("\n");
    try cg.indent(writer, depth);
    try writer.writeAll("pub fn Client(comptime Transport: type) type {\n");
    try cg.indent(writer, depth + 1);
    try writer.writeAll("return struct {\n");
    try cg.indent(writer, depth + 2);
    try writer.writeAll("transport: Transport,\n\n");
    try cg.indent(writer, depth + 2);
    try writer.writeAll("pub fn init(transport: Transport) @This() { return .{ .transport = transport }; }\n\n");
    for (service.methods.items) |*method| {
        if (methodHasMessageTypes(ctx, method)) try writeServiceClientMethod(ctx, service, method, writer, depth + 2);
    }
    try cg.indent(writer, depth + 1);
    try writer.writeAll("};\n");
    try cg.indent(writer, depth);
    try writer.writeAll("}\n");
}

pub fn writeServiceClientMethod(ctx: *const CodegenContext, service: *const schema.ServiceDescriptor, method: *const schema.MethodDescriptor, writer: *std.Io.Writer, depth: usize) Error!void {
    try cg.indent(writer, depth);
    try writer.writeAll("pub fn ");
    try cg.writeQuotedIdent(method.name, writer);
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
        try cg.indent(writer, depth + 1);
        try writer.writeAll("const request_payload = try request.encode(allocator);\n");
        try cg.indent(writer, depth + 1);
        try writer.writeAll("defer allocator.free(request_payload);\n");
        try cg.indent(writer, depth + 1);
        try writer.writeAll("const response_payload = try self.transport.call(allocator, ");
        try cg.writeZigStringLiteral(service.name, writer);
        try writer.writeAll(", ");
        try cg.writeZigStringLiteral(method.name, writer);
        try writer.writeAll(", request_payload);\n");
        try cg.indent(writer, depth + 1);
        try writer.writeAll("defer allocator.free(response_payload);\n");
        try cg.indent(writer, depth + 1);
        try writer.writeAll("return try ");
        try writeRpcMessageTypeReference(ctx, method.output_type, writer);
        try writer.writeAll(".decodeOwned(allocator, response_payload);\n");
    } else if (method.client_streaming and !method.server_streaming) {
        try cg.indent(writer, depth + 1);
        try writer.writeAll("const response_payload = try self.transport.callClientStream(allocator, ");
        try cg.writeZigStringLiteral(service.name, writer);
        try writer.writeAll(", ");
        try cg.writeZigStringLiteral(method.name, writer);
        try writer.writeAll(", requests);\n");
        try cg.indent(writer, depth + 1);
        try writer.writeAll("defer allocator.free(response_payload);\n");
        try cg.indent(writer, depth + 1);
        try writer.writeAll("return try ");
        try writeRpcMessageTypeReference(ctx, method.output_type, writer);
        try writer.writeAll(".decodeOwned(allocator, response_payload);\n");
    } else if (!method.client_streaming and method.server_streaming) {
        try cg.indent(writer, depth + 1);
        try writer.writeAll("const request_payload = try request.encode(allocator);\n");
        try cg.indent(writer, depth + 1);
        try writer.writeAll("defer allocator.free(request_payload);\n");
        try cg.indent(writer, depth + 1);
        try writer.writeAll("try self.transport.callServerStream(allocator, ");
        try cg.writeZigStringLiteral(service.name, writer);
        try writer.writeAll(", ");
        try cg.writeZigStringLiteral(method.name, writer);
        try writer.writeAll(", request_payload, responses);\n");
    } else {
        try cg.indent(writer, depth + 1);
        try writer.writeAll("try self.transport.callBidiStream(allocator, ");
        try cg.writeZigStringLiteral(service.name, writer);
        try writer.writeAll(", ");
        try cg.writeZigStringLiteral(method.name, writer);
        try writer.writeAll(", requests, responses);\n");
    }
    try cg.indent(writer, depth);
    try writer.writeAll("}\n\n");
}

pub fn writeRpcMessageTypeReferenceOrVoid(ctx: *const CodegenContext, type_name: []const u8, writer: *std.Io.Writer) Error!void {
    if (cg.codegenCanReferenceMessageWithContext(ctx, type_name)) {
        try writeRpcMessageTypeReference(ctx, type_name, writer);
    } else {
        try writer.writeAll("void");
    }
}

pub fn writeRpcMessageTypeReference(ctx: *const CodegenContext, type_name: []const u8, writer: *std.Io.Writer) Error!void {
    try cg.writeMessageTypeReferenceWithContext(ctx, type_name, writer);
}
