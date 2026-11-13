const std = @import("std");
const pbz = @import("pbz");
const generated = @import("conformance_generated");

const default_descriptor_env = "PBZ_CONFORMANCE_DESCRIPTOR_SET";

/// Experimental audit mode: parse JSON requests through the generated message
/// parsers instead of the dynamic bridge. Used to measure generated JSON
/// conformance coverage; the default remains the dynamic bridge.
var generated_json_mode = false;
/// Experimental audit mode for generated TextFormat parse/format.
var generated_text_mode = false;

const GeneratedCase = struct {
    name: []const u8,
    message: type,
};

const generated_cases = [_]GeneratedCase{
    .{
        .name = "protobuf_test_messages.proto3.TestAllTypesProto3",
        .message = generated.proto3.protobuf_test_messages.proto3.TestAllTypesProto3,
    },
    .{
        .name = "protobuf_test_messages.proto2.TestAllTypesProto2",
        .message = generated.proto2.protobuf_test_messages.proto2.TestAllTypesProto2,
    },
    .{
        .name = "protobuf_test_messages.editions.proto3.TestAllTypesProto3",
        .message = generated.editions_proto3.protobuf_test_messages.editions.proto3.TestAllTypesProto3,
    },
    .{
        .name = "protobuf_test_messages.editions.proto2.TestAllTypesProto2",
        .message = generated.editions_proto2.protobuf_test_messages.editions.proto2.TestAllTypesProto2,
    },
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var arg_it = init.minimal.args.iterate();
    _ = arg_it.next();
    var descriptor_path: ?[]const u8 = null;
    while (arg_it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--descriptor_set") or std.mem.eql(u8, arg, "--descriptor-set")) {
            descriptor_path = arg_it.next() orelse return error.MissingDescriptorSetPath;
        } else if (std.mem.startsWith(u8, arg, "--descriptor_set=")) {
            descriptor_path = arg["--descriptor_set=".len..];
        } else if (std.mem.startsWith(u8, arg, "--descriptor-set=")) {
            descriptor_path = arg["--descriptor-set=".len..];
        } else if (std.mem.eql(u8, arg, "--help")) {
            printUsage(io);
            return;
        }
    }
    if (descriptor_path == null) descriptor_path = init.environ_map.get(default_descriptor_env);
    generated_json_mode = init.environ_map.get("PBZ_CONFORMANCE_GENERATED_JSON") != null;
    generated_text_mode = init.environ_map.get("PBZ_CONFORMANCE_GENERATED_TEXT") != null;

    const path = descriptor_path orelse {
        printUsage(io);
        return error.MissingDescriptorSetPath;
    };

    var descriptor_file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer descriptor_file.close(io);
    var file_reader_buffer: [16 * 1024]u8 = undefined;
    var file_reader = descriptor_file.reader(io, &file_reader_buffer);
    const descriptor_bytes = try file_reader.interface.allocRemaining(allocator, .limited(256 * 1024 * 1024));
    defer allocator.free(descriptor_bytes);

    const files = try pbz.decodeFileDescriptorSet(allocator, descriptor_bytes);
    defer {
        for (files) |*file| file.deinit();
        allocator.free(files);
    }

    var registry = pbz.Registry.init(allocator);
    defer registry.deinit();
    for (files) |*file| try registry.addFile(file);

    var stdin_buffer: [16 * 1024]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().readerStreaming(io, &stdin_buffer);
    var stdout_buffer: [16 * 1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writerStreaming(io, &stdout_buffer);
    defer stdout_writer.interface.flush() catch {};

    while (true) {
        const len = stdin_reader.interface.takeInt(u32, .little) catch |err| switch (err) {
            error.EndOfStream => return,
            else => return err,
        };
        const request_bytes = try stdin_reader.interface.readAlloc(allocator, len);
        defer allocator.free(request_bytes);

        const request = try pbz.ConformanceRequest.decode(request_bytes);
        const response = try runGenerated(allocator, &registry, request);
        defer allocator.free(response);

        try stdout_writer.interface.writeInt(u32, @intCast(response.len), .little);
        try stdout_writer.interface.writeAll(response);
        try stdout_writer.interface.flush();
    }
}

fn runGenerated(
    allocator: std.mem.Allocator,
    registry: *const pbz.Registry,
    request: pbz.ConformanceRequest,
) ![]u8 {
    inline for (generated_cases) |case| {
        if (std.mem.eql(u8, request.message_type, case.name)) {
            return try runTyped(allocator, registry, request, case.message);
        }
    }
    // Message types without generated code still run through the dynamic path.
    return try pbz.runConformanceDynamic(allocator, registry, request);
}

fn runTyped(
    allocator: std.mem.Allocator,
    registry: *const pbz.Registry,
    request: pbz.ConformanceRequest,
    comptime Message: type,
) ![]u8 {
    const descriptor = registry.findMessage(request.message_type, null) orelse
        return try runtimeError(allocator, "unknown message type");
    const registry_file = findContainingFile(registry, descriptor) orelse
        return try runtimeError(allocator, "unknown file");

    var parsed: ?Message = null;
    defer if (parsed) |*message| message.deinit(allocator);
    // JSON/Text output is emitted from the original dynamic message when the
    // input was JSON/Text: a wire round trip drops wrapper defaults (for
    // example `BoolValue{value:false}` encodes as an empty payload) and would
    // print `null` instead of `false`.
    var parsed_dynamic: ?pbz.DynamicMessage = null;
    defer if (parsed_dynamic) |*dynamic| dynamic.deinit();

    switch (request.payload) {
        .protobuf_payload => |payload| {
            parsed = Message.decodeOwned(allocator, payload) catch |err| return try parseError(allocator, err);
        },
        .json_payload => |payload| {
            if (generated_json_mode) {
                parsed = Message.jsonParseWithOptions(allocator, payload, .{
                    .ignore_unknown_fields = request.test_category == .json_ignore_unknown_parsing_test,
                }) catch |err| return try parseError(allocator, err);
            } else {
                parsed_dynamic = pbz.json.parseAllocWithRegistry(allocator, registry_file, registry, descriptor, payload, .{
                    .ignore_unknown_fields = request.test_category == .json_ignore_unknown_parsing_test,
                }) catch |err| return try parseError(allocator, err);
                const wire = parsed_dynamic.?.encodedDeterministicWithRegistry(registry_file, registry) catch |err| return try parseError(allocator, err);
                defer allocator.free(wire);
                parsed = Message.decodeOwned(allocator, wire) catch |err| return try parseError(allocator, err);
            }
        },
        .text_payload => |payload| {
            if (generated_text_mode) {
                parsed = Message.parseTextWithOptions(allocator, payload, .{
                    .ignore_unknown_fields = request.test_category == .json_ignore_unknown_parsing_test,
                }) catch |err| return try parseError(allocator, err);
            } else {
                parsed_dynamic = pbz.text.parseAllocWithRegistry(allocator, registry_file, registry, descriptor, payload) catch |err| return try parseError(allocator, err);
                const wire = parsed_dynamic.?.encodedDeterministicWithRegistry(registry_file, registry) catch |err| return try parseError(allocator, err);
                defer allocator.free(wire);
                parsed = Message.decodeOwned(allocator, wire) catch |err| return try parseError(allocator, err);
            }
        },
        else => return try (pbz.ConformanceResponse{ .result = .{ .skipped = "unsupported input format" } }).encode(allocator),
    }

    const message = if (parsed) |*value| value else return error.MissingPayload;
    message.validateRequiredRecursive(allocator) catch |err| return try parseError(allocator, err);

    return switch (request.requested_output_format) {
        .protobuf => blk: {
            const generated_wire = message.encode(allocator) catch |err| return try serializeError(allocator, err);
            defer allocator.free(generated_wire);
            // Normalize through the registry-aware dynamic path so cyclic raw
            // fields and unknown-field ordering match the canonical reference
            // encoding.
            var dynamic = pbz.DynamicMessage.init(allocator, descriptor);
            defer dynamic.deinit();
            dynamic.decodeWithRegistry(registry_file, registry, generated_wire) catch |err| return try serializeError(allocator, err);
            const payload = dynamic.encodedDeterministicInitializedWithRegistry(registry_file, registry) catch |err| return try serializeError(allocator, err);
            defer allocator.free(payload);
            break :blk try (pbz.ConformanceResponse{ .result = .{ .protobuf_payload = payload } }).encode(allocator);
        },
        .json => blk: {
            const payload = if (generated_json_mode)
                message.jsonStringifyAlloc(allocator) catch |err| return try serializeError(allocator, err)
            else if (parsed_dynamic) |*dynamic|
                pbz.json.stringifyAllocWithRegistry(allocator, registry_file, registry, dynamic, .{}) catch |err| return try serializeError(allocator, err)
            else blk_json: {
                const wire = message.encode(allocator) catch |err| return try serializeError(allocator, err);
                defer allocator.free(wire);
                var dynamic = pbz.DynamicMessage.init(allocator, descriptor);
                defer dynamic.deinit();
                dynamic.decodeWithRegistry(registry_file, registry, wire) catch |err| return try serializeError(allocator, err);
                break :blk_json pbz.json.stringifyAllocWithRegistry(allocator, registry_file, registry, &dynamic, .{}) catch |err| return try serializeError(allocator, err);
            };
            defer allocator.free(payload);
            break :blk try (pbz.ConformanceResponse{ .result = .{ .json_payload = payload } }).encode(allocator);
        },
        .text_format => blk: {
            const payload = if (generated_text_mode) blk_text_gen: {
                var out: std.Io.Writer.Allocating = .init(allocator);
                message.formatTextWithOptions(allocator, &out.writer, .{
                    .print_unknown_fields = request.print_unknown_fields,
                }) catch |err| return try serializeError(allocator, err);
                break :blk_text_gen try out.toOwnedSlice();
            } else if (parsed_dynamic) |*dynamic|
                pbz.text.formatAllocWithRegistry(allocator, registry_file, registry, dynamic, .{
                    .print_unknown_fields = request.print_unknown_fields,
                }) catch |err| return try serializeError(allocator, err)
            else blk_text: {
                const wire = message.encode(allocator) catch |err| return try serializeError(allocator, err);
                defer allocator.free(wire);
                var dynamic = pbz.DynamicMessage.init(allocator, descriptor);
                defer dynamic.deinit();
                dynamic.decodeWithRegistry(registry_file, registry, wire) catch |err| return try serializeError(allocator, err);
                break :blk_text pbz.text.formatAllocWithRegistry(allocator, registry_file, registry, &dynamic, .{
                    .print_unknown_fields = request.print_unknown_fields,
                }) catch |err| return try serializeError(allocator, err);
            };
            defer allocator.free(payload);
            break :blk try (pbz.ConformanceResponse{ .result = .{ .text_payload = payload } }).encode(allocator);
        },
        else => try (pbz.ConformanceResponse{ .result = .{ .skipped = "unsupported output format" } }).encode(allocator),
    };
}

fn findContainingFile(registry: *const pbz.Registry, descriptor: *const pbz.schema.MessageDescriptor) ?*const pbz.schema.FileDescriptor {
    for (registry.files.items) |file| {
        for (file.messages.items) |*message| {
            if (message == descriptor or containsMessage(message, descriptor)) return file;
        }
    }
    return null;
}

fn containsMessage(parent: *const pbz.schema.MessageDescriptor, needle: *const pbz.schema.MessageDescriptor) bool {
    for (parent.messages.items) |*message| {
        if (message == needle or containsMessage(message, needle)) return true;
    }
    return false;
}

fn parseError(allocator: std.mem.Allocator, err: anyerror) ![]u8 {
    const msg = try std.fmt.allocPrint(allocator, "{t}", .{err});
    defer allocator.free(msg);
    return try parseErrorText(allocator, msg);
}

fn parseErrorText(allocator: std.mem.Allocator, msg: []const u8) ![]u8 {
    return try (pbz.ConformanceResponse{ .result = .{ .parse_error = msg } }).encode(allocator);
}

fn serializeError(allocator: std.mem.Allocator, err: anyerror) ![]u8 {
    const msg = try std.fmt.allocPrint(allocator, "{t}", .{err});
    defer allocator.free(msg);
    return try (pbz.ConformanceResponse{ .result = .{ .serialize_error = msg } }).encode(allocator);
}

fn runtimeError(allocator: std.mem.Allocator, msg: []const u8) ![]u8 {
    return try (pbz.ConformanceResponse{ .result = .{ .runtime_error = msg } }).encode(allocator);
}

fn printUsage(io: std.Io) void {
    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writerStreaming(io, &stderr_buffer);
    stderr_writer.interface.writeAll(
        \\usage: pbz-conformance-generated --descriptor_set FILE
        \\
        \\Implements the protobuf conformance subprocess protocol using generated
        \\Zig types for the protobuf_test_messages.* test messages, with the
        \\registry-aware dynamic path as the JSON/TextFormat bridge.
        \\
    ) catch {};
    stderr_writer.interface.flush() catch {};
}
