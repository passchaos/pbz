const std = @import("std");
const wire = @import("wire.zig");
const schema = @import("schema.zig");
const registry_mod = @import("registry.zig");
const dynamic = @import("dynamic.zig");
const json = @import("json.zig");
const text = @import("text.zig");

pub const Error = wire.Error || std.mem.Allocator.Error;

pub const WireFormat = enum(i32) {
    unspecified = 0,
    protobuf = 1,
    json = 2,
    jspb = 3,
    text_format = 4,
};

pub const TestCategory = enum(i32) {
    unspecified = 0,
    binary_test = 1,
    json_test = 2,
    json_ignore_unknown_parsing_test = 3,
    jspb_test = 4,
    text_format_test = 5,
};

pub const ConformanceRequest = struct {
    payload: Payload = .none,
    requested_output_format: WireFormat = .unspecified,
    message_type: []const u8 = "",
    test_category: TestCategory = .unspecified,
    print_unknown_fields: bool = false,

    pub const Payload = union(enum) {
        none,
        protobuf_payload: []const u8,
        json_payload: []const u8,
        text_payload: []const u8,
        jspb_payload: []const u8,
    };

    pub fn decode(bytes: []const u8) Error!ConformanceRequest {
        var out = ConformanceRequest{};
        var reader = wire.Reader.init(bytes);
        while (try reader.nextTag()) |tag| {
            switch (tag.number) {
                1 => out.payload = .{ .protobuf_payload = try reader.readBytes() },
                2 => out.payload = .{ .json_payload = try reader.readBytes() },
                3 => out.requested_output_format = std.enums.fromInt(WireFormat, try reader.readInt32()) orelse .unspecified,
                4 => out.message_type = try reader.readBytes(),
                5 => out.test_category = std.enums.fromInt(TestCategory, try reader.readInt32()) orelse .unspecified,
                7 => out.payload = .{ .jspb_payload = try reader.readBytes() },
                8 => out.payload = .{ .text_payload = try reader.readBytes() },
                9 => out.print_unknown_fields = try reader.readBool(),
                else => try reader.skipValue(tag),
            }
        }
        return out;
    }
};

pub const ConformanceResponse = struct {
    result: Result = .{ .skipped = "" },

    pub const Result = union(enum) {
        parse_error: []const u8,
        serialize_error: []const u8,
        timeout_error: []const u8,
        runtime_error: []const u8,
        protobuf_payload: []const u8,
        json_payload: []const u8,
        skipped: []const u8,
        jspb_payload: []const u8,
        text_payload: []const u8,
    };

    pub fn encode(self: ConformanceResponse, allocator: std.mem.Allocator) Error![]u8 {
        var writer = wire.Writer.init(allocator);
        errdefer writer.deinit();
        switch (self.result) {
            .parse_error => |value| try writer.writeString(1, value),
            .serialize_error => |value| try writer.writeString(6, value),
            .timeout_error => |value| try writer.writeString(9, value),
            .runtime_error => |value| try writer.writeString(2, value),
            .protobuf_payload => |value| try writer.writeBytes(3, value),
            .json_payload => |value| try writer.writeString(4, value),
            .skipped => |value| try writer.writeString(5, value),
            .jspb_payload => |value| try writer.writeString(7, value),
            .text_payload => |value| try writer.writeString(8, value),
        }
        return try writer.toOwnedSlice();
    }
};

pub fn runDynamic(
    allocator: std.mem.Allocator,
    registry: *const registry_mod.Registry,
    request: ConformanceRequest,
) ![]u8 {
    const descriptor = registry.findMessage(request.message_type, null) orelse
        return try (ConformanceResponse{ .result = .{ .runtime_error = "unknown message type" } }).encode(allocator);
    const file = findContainingFile(registry, descriptor) orelse
        return try (ConformanceResponse{ .result = .{ .runtime_error = "unknown file" } }).encode(allocator);

    var message = dynamic.DynamicMessage.init(allocator, descriptor);
    defer message.deinit();
    switch (request.payload) {
        .protobuf_payload => |payload| {
            message.decodeWithRegistry(file, registry, payload) catch |err| return try parseError(allocator, err);
            if (try validateRequiredResponse(allocator, &message)) |response| return response;
        },
        .json_payload => |payload| {
            var parsed = json.parseAllocWithRegistry(allocator, file, registry, descriptor, payload, .{ .ignore_unknown_fields = request.test_category == .json_ignore_unknown_parsing_test }) catch |err| return try parseError(allocator, err);
            defer parsed.deinit();
            try message.mergeFrom(&parsed);
            if (try validateRequiredResponse(allocator, &message)) |response| return response;
        },
        .text_payload => |payload| {
            var parsed = text.parseAllocWithRegistry(allocator, file, registry, descriptor, payload) catch |err| return try parseError(allocator, err);
            defer parsed.deinit();
            try message.mergeFrom(&parsed);
            if (try validateRequiredResponse(allocator, &message)) |response| return response;
        },
        else => return try (ConformanceResponse{ .result = .{ .skipped = "unsupported input format" } }).encode(allocator),
    }

    return switch (request.requested_output_format) {
        .protobuf => blk: {
            const payload = message.encodedDeterministicInitializedWithRegistry(file, registry) catch |err| return try serializeError(allocator, err);
            defer allocator.free(payload);
            break :blk try (ConformanceResponse{ .result = .{ .protobuf_payload = payload } }).encode(allocator);
        },
        .json => blk: {
            const payload = json.stringifyAllocWithRegistry(allocator, file, registry, &message, .{}) catch |err| return try serializeError(allocator, err);
            defer allocator.free(payload);
            break :blk try (ConformanceResponse{ .result = .{ .json_payload = payload } }).encode(allocator);
        },
        .text_format => blk: {
            if (request.print_unknown_fields and message.unknownCount() != 0) {
                break :blk try (ConformanceResponse{ .result = .{ .skipped = "printing unknown TextFormat fields is unsupported" } }).encode(allocator);
            }
            const payload = text.formatAllocWithRegistry(allocator, file, registry, &message, .{ .print_unknown_fields = request.print_unknown_fields }) catch |err| return try serializeError(allocator, err);
            defer allocator.free(payload);
            break :blk try (ConformanceResponse{ .result = .{ .text_payload = payload } }).encode(allocator);
        },
        else => try (ConformanceResponse{ .result = .{ .skipped = "unsupported output format" } }).encode(allocator),
    };
}

fn parseError(allocator: std.mem.Allocator, err: anyerror) ![]u8 {
    const msg = try std.fmt.allocPrint(allocator, "{t}", .{err});
    defer allocator.free(msg);
    return try parseErrorText(allocator, msg);
}

fn parseErrorText(allocator: std.mem.Allocator, msg: []const u8) ![]u8 {
    return try (ConformanceResponse{ .result = .{ .parse_error = msg } }).encode(allocator);
}

fn validateRequiredResponse(allocator: std.mem.Allocator, message: *const dynamic.DynamicMessage) !?[]u8 {
    message.validateRequired() catch |err| switch (err) {
        error.MissingRequiredField => {
            const path = try message.missingRequiredFieldPath(allocator);
            defer if (path) |p| allocator.free(p);
            const msg = if (path) |p|
                try std.fmt.allocPrint(allocator, "MissingRequiredField: {s}", .{p})
            else
                try allocator.dupe(u8, "MissingRequiredField");
            defer allocator.free(msg);
            return try parseErrorText(allocator, msg);
        },
    };
    return null;
}

fn serializeError(allocator: std.mem.Allocator, err: anyerror) ![]u8 {
    const msg = try std.fmt.allocPrint(allocator, "{t}", .{err});
    defer allocator.free(msg);
    return try (ConformanceResponse{ .result = .{ .serialize_error = msg } }).encode(allocator);
}

fn findContainingFile(registry: *const registry_mod.Registry, descriptor: *const schema.MessageDescriptor) ?*const schema.FileDescriptor {
    for (registry.files.items) |file| {
        for (file.messages.items) |*message| {
            if (message == descriptor or containsMessage(message, descriptor)) return file;
        }
    }
    return null;
}

fn containsMessage(parent: *const schema.MessageDescriptor, needle: *const schema.MessageDescriptor) bool {
    for (parent.messages.items) |*message| {
        if (message == needle or containsMessage(message, needle)) return true;
    }
    return false;
}

test "conformance request decodes and response encodes" {
    const allocator = std.testing.allocator;
    var writer = wire.Writer.init(allocator);
    defer writer.deinit();
    try writer.writeBytes(1, "\x08\x01");
    try writer.writeInt32(3, @intFromEnum(WireFormat.json));
    try writer.writeString(4, "demo.Message");
    try writer.writeInt32(5, @intFromEnum(TestCategory.binary_test));

    const request = try ConformanceRequest.decode(writer.slice());
    try std.testing.expectEqual(WireFormat.json, request.requested_output_format);
    try std.testing.expectEqual(TestCategory.binary_test, request.test_category);
    try std.testing.expectEqualSlices(u8, "demo.Message", request.message_type);
    try std.testing.expectEqualSlices(u8, "\x08\x01", request.payload.protobuf_payload);

    writer.clearRetainingCapacity();
    try writer.writeInt32(3, 3);
    const jspb_format = try ConformanceRequest.decode(writer.slice());
    try std.testing.expectEqual(WireFormat.jspb, jspb_format.requested_output_format);

    writer.clearRetainingCapacity();
    try writer.writeInt32(3, 4);
    const text_format = try ConformanceRequest.decode(writer.slice());
    try std.testing.expectEqual(WireFormat.text_format, text_format.requested_output_format);

    writer.clearRetainingCapacity();
    try writer.writeInt32(3, 99);
    try writer.writeInt32(5, 99);
    try writer.writeBool(9, true);
    const invalid_enums = try ConformanceRequest.decode(writer.slice());
    try std.testing.expectEqual(WireFormat.unspecified, invalid_enums.requested_output_format);
    try std.testing.expectEqual(TestCategory.unspecified, invalid_enums.test_category);
    try std.testing.expect(invalid_enums.print_unknown_fields);

    const response = try (ConformanceResponse{ .result = .{ .json_payload = "{}" } }).encode(allocator);
    defer allocator.free(response);
    try std.testing.expectEqualSlices(u8, &.{ 0x22, 0x02, '{', '}' }, response);
}

test "conformance dynamic runner converts protobuf to json" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator, "syntax = \"proto3\"; package demo; message Msg { int32 id = 1; }");
    defer file.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);
    var payload = wire.Writer.init(allocator);
    defer payload.deinit();
    try payload.writeInt32(1, 7);
    const response_bytes = try runDynamic(allocator, &registry, .{
        .payload = .{ .protobuf_payload = payload.slice() },
        .requested_output_format = .json,
        .message_type = "demo.Msg",
        .test_category = .binary_test,
    });
    defer allocator.free(response_bytes);
    var reader = wire.Reader.init(response_bytes);
    const tag = (try reader.nextTag()).?;
    try std.testing.expectEqual(@as(wire.FieldNumber, 4), tag.number);
    try std.testing.expectEqualSlices(u8, "{\"id\":7}", try reader.readBytes());
}

test "conformance dynamic runner converts json to deterministic protobuf" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator, "syntax = \"proto3\"; package demo; message Msg { int32 id = 1; int32 count = 2; }");
    defer file.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);
    const response_bytes = try runDynamic(allocator, &registry, .{
        .payload = .{ .json_payload = "{\"count\":2,\"id\":1}" },
        .requested_output_format = .protobuf,
        .message_type = "demo.Msg",
        .test_category = .json_test,
    });
    defer allocator.free(response_bytes);
    var reader = wire.Reader.init(response_bytes);
    const tag = (try reader.nextTag()).?;
    try std.testing.expectEqual(@as(wire.FieldNumber, 3), tag.number);
    try std.testing.expectEqualSlices(u8, &.{ 0x08, 0x01, 0x10, 0x02 }, try reader.readBytes());
}

test "conformance dynamic runner handles json closed enum unknown numbers by category" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\edition = "2023";
        \\option features.enum_type = CLOSED;
        \\package demo;
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message Msg { Kind kind = 1; int32 id = 2; }
    );
    defer file.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);

    const strict_response = try runDynamic(allocator, &registry, .{
        .payload = .{ .json_payload = "{\"kind\":123,\"id\":7}" },
        .requested_output_format = .protobuf,
        .message_type = "demo.Msg",
        .test_category = .json_test,
    });
    defer allocator.free(strict_response);
    var strict_reader = wire.Reader.init(strict_response);
    const strict_tag = (try strict_reader.nextTag()).?;
    try std.testing.expectEqual(@as(wire.FieldNumber, 1), strict_tag.number);
    try std.testing.expect(std.mem.indexOf(u8, try strict_reader.readBytes(), "InvalidEnumValue") != null);

    const ignored_response = try runDynamic(allocator, &registry, .{
        .payload = .{ .json_payload = "{\"kind\":123,\"id\":7}" },
        .requested_output_format = .protobuf,
        .message_type = "demo.Msg",
        .test_category = .json_ignore_unknown_parsing_test,
    });
    defer allocator.free(ignored_response);
    var ignored_reader = wire.Reader.init(ignored_response);
    const ignored_tag = (try ignored_reader.nextTag()).?;
    try std.testing.expectEqual(@as(wire.FieldNumber, 3), ignored_tag.number);
    try std.testing.expectEqualSlices(u8, &.{ 0x10, 0x07 }, try ignored_reader.readBytes());
}

test "conformance dynamic runner handles json unknown enum names by category" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package demo;
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message Msg { Kind kind = 1; int32 id = 2; }
    );
    defer file.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);

    const strict_response = try runDynamic(allocator, &registry, .{
        .payload = .{ .json_payload = "{\"kind\":\"MISSING\",\"id\":7}" },
        .requested_output_format = .protobuf,
        .message_type = "demo.Msg",
        .test_category = .json_test,
    });
    defer allocator.free(strict_response);
    var strict_reader = wire.Reader.init(strict_response);
    const strict_tag = (try strict_reader.nextTag()).?;
    try std.testing.expectEqual(@as(wire.FieldNumber, 1), strict_tag.number);
    try std.testing.expect(std.mem.indexOf(u8, try strict_reader.readBytes(), "InvalidEnumValue") != null);

    const ignored_response = try runDynamic(allocator, &registry, .{
        .payload = .{ .json_payload = "{\"kind\":\"MISSING\",\"id\":7}" },
        .requested_output_format = .protobuf,
        .message_type = "demo.Msg",
        .test_category = .json_ignore_unknown_parsing_test,
    });
    defer allocator.free(ignored_response);
    var ignored_reader = wire.Reader.init(ignored_response);
    const ignored_tag = (try ignored_reader.nextTag()).?;
    try std.testing.expectEqual(@as(wire.FieldNumber, 3), ignored_tag.number);
    try std.testing.expectEqualSlices(u8, &.{ 0x10, 0x07 }, try ignored_reader.readBytes());
}

test "conformance dynamic runner handles json unknown fields by category" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator, "syntax = \"proto3\"; package demo; message Msg { int32 id = 1; }");
    defer file.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);

    const strict_response = try runDynamic(allocator, &registry, .{
        .payload = .{ .json_payload = "{\"id\":7,\"extra\":1}" },
        .requested_output_format = .protobuf,
        .message_type = "demo.Msg",
        .test_category = .json_test,
    });
    defer allocator.free(strict_response);
    var strict_reader = wire.Reader.init(strict_response);
    const strict_tag = (try strict_reader.nextTag()).?;
    try std.testing.expectEqual(@as(wire.FieldNumber, 1), strict_tag.number);
    try std.testing.expect(std.mem.indexOf(u8, try strict_reader.readBytes(), "UnknownField") != null);

    const ignored_response = try runDynamic(allocator, &registry, .{
        .payload = .{ .json_payload = "{\"id\":7,\"extra\":1}" },
        .requested_output_format = .protobuf,
        .message_type = "demo.Msg",
        .test_category = .json_ignore_unknown_parsing_test,
    });
    defer allocator.free(ignored_response);
    var ignored_reader = wire.Reader.init(ignored_response);
    const ignored_tag = (try ignored_reader.nextTag()).?;
    try std.testing.expectEqual(@as(wire.FieldNumber, 3), ignored_tag.number);
    try std.testing.expectEqualSlices(u8, &.{ 0x08, 0x07 }, try ignored_reader.readBytes());
}

test "conformance dynamic runner uses registry for imported json types" {
    const allocator = std.testing.allocator;
    var common = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package common;
        \\message User { string name = 1; }
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
    );
    defer common.deinit();
    var app = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package app;
        \\message Event { common.User user = 1; common.Kind kind = 2; }
    );
    defer app.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);

    const response_bytes = try runDynamic(allocator, &registry, .{
        .payload = .{ .json_payload = "{\"user\":{\"name\":\"Ada\"},\"kind\":\"ADMIN\"}" },
        .requested_output_format = .json,
        .message_type = "app.Event",
        .test_category = .json_test,
    });
    defer allocator.free(response_bytes);
    var reader = wire.Reader.init(response_bytes);
    const tag = (try reader.nextTag()).?;
    try std.testing.expectEqual(@as(wire.FieldNumber, 4), tag.number);
    try std.testing.expectEqualSlices(u8, "{\"user\":{\"name\":\"Ada\"},\"kind\":\"ADMIN\"}", try reader.readBytes());
}

test "conformance dynamic runner rejects closed enum text unknowns" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\edition = "2023";
        \\option features.enum_type = CLOSED;
        \\package demo;
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message Msg { Kind kind = 1; }
    );
    defer file.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);

    inline for (.{ "kind: MISSING", "kind: 123" }) |payload| {
        const response_bytes = try runDynamic(allocator, &registry, .{
            .payload = .{ .text_payload = payload },
            .requested_output_format = .protobuf,
            .message_type = "demo.Msg",
            .test_category = .text_format_test,
        });
        defer allocator.free(response_bytes);
        var reader = wire.Reader.init(response_bytes);
        const tag = (try reader.nextTag()).?;
        try std.testing.expectEqual(@as(wire.FieldNumber, 1), tag.number);
        try std.testing.expect(std.mem.indexOf(u8, try reader.readBytes(), "InvalidEnumValue") != null);
    }
}

test "conformance dynamic runner converts text to deterministic protobuf" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Msg { required int32 id = 1; optional string name = 2; }
    );
    defer file.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);

    const response_bytes = try runDynamic(allocator, &registry, .{
        .payload = .{ .text_payload = "name: \"Ada\" id: 7" },
        .requested_output_format = .protobuf,
        .message_type = "demo.Msg",
        .test_category = .text_format_test,
    });
    defer allocator.free(response_bytes);
    var reader = wire.Reader.init(response_bytes);
    const tag = (try reader.nextTag()).?;
    try std.testing.expectEqual(@as(wire.FieldNumber, 3), tag.number);
    try std.testing.expectEqualSlices(u8, &.{ 0x08, 0x07, 0x12, 0x03, 'A', 'd', 'a' }, try reader.readBytes());
}

test "conformance dynamic runner converts text to json" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Msg { required int32 id = 1; optional string name = 2; }
    );
    defer file.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);

    const response_bytes = try runDynamic(allocator, &registry, .{
        .payload = .{ .text_payload = "id: 7 name: \"Ada\"" },
        .requested_output_format = .json,
        .message_type = "demo.Msg",
        .test_category = .text_format_test,
    });
    defer allocator.free(response_bytes);
    var reader = wire.Reader.init(response_bytes);
    const tag = (try reader.nextTag()).?;
    try std.testing.expectEqual(@as(wire.FieldNumber, 4), tag.number);
    try std.testing.expectEqualSlices(u8, "{\"id\":7,\"name\":\"Ada\"}", try reader.readBytes());
}

test "conformance dynamic runner converts json to text" {
    const allocator = std.testing.allocator;
    var common = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package common;
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
    );
    defer common.deinit();
    var app = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package app;
        \\message Event { common.Kind kind = 1; }
    );
    defer app.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);

    const response_bytes = try runDynamic(allocator, &registry, .{
        .payload = .{ .json_payload = "{\"kind\":\"ADMIN\"}" },
        .requested_output_format = .text_format,
        .message_type = "app.Event",
        .test_category = .json_test,
    });
    defer allocator.free(response_bytes);
    var reader = wire.Reader.init(response_bytes);
    const tag = (try reader.nextTag()).?;
    try std.testing.expectEqual(@as(wire.FieldNumber, 8), tag.number);
    try std.testing.expectEqualSlices(u8, "kind: ADMIN\n", try reader.readBytes());
}

test "conformance dynamic runner uses registry for imported text output" {
    const allocator = std.testing.allocator;
    var common = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package common;
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
    );
    defer common.deinit();
    var app = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package app;
        \\message Event { common.Kind kind = 1; }
    );
    defer app.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);

    var payload = wire.Writer.init(allocator);
    defer payload.deinit();
    try payload.writeInt32(1, 1);
    const response_bytes = try runDynamic(allocator, &registry, .{
        .payload = .{ .protobuf_payload = payload.slice() },
        .requested_output_format = .text_format,
        .message_type = "app.Event",
        .test_category = .binary_test,
    });
    defer allocator.free(response_bytes);
    var reader = wire.Reader.init(response_bytes);
    const tag = (try reader.nextTag()).?;
    try std.testing.expectEqual(@as(wire.FieldNumber, 8), tag.number);
    try std.testing.expectEqualSlices(u8, "kind: ADMIN\n", try reader.readBytes());
}

test "conformance dynamic runner uses registry for imported protobuf output" {
    const allocator = std.testing.allocator;
    var common = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package common;
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; USER = 2; }
    );
    defer common.deinit();
    var app = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto3";
        \\package app;
        \\message Event { common.Kind kind = 1; repeated common.Kind many = 2; }
    );
    defer app.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&common);
    try registry.addFile(&app);

    const response_bytes = try runDynamic(allocator, &registry, .{
        .payload = .{ .json_payload = "{\"kind\":\"ADMIN\",\"many\":[\"ADMIN\",\"USER\"]}" },
        .requested_output_format = .protobuf,
        .message_type = "app.Event",
        .test_category = .json_test,
    });
    defer allocator.free(response_bytes);
    var reader = wire.Reader.init(response_bytes);
    const tag = (try reader.nextTag()).?;
    try std.testing.expectEqual(@as(wire.FieldNumber, 3), tag.number);
    try std.testing.expectEqualSlices(u8, &.{ 0x08, 0x01, 0x12, 0x02, 0x01, 0x02 }, try reader.readBytes());
}

test "conformance dynamic runner parses MessageSet extension text input" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host { option message_set_wire_format = true; extensions 4 to max; }
        \\message Note { optional int32 id = 1; }
        \\extend Host { optional Note note = 100; }
    );
    defer file.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);

    var note_payload = wire.Writer.init(allocator);
    defer note_payload.deinit();
    try note_payload.writeInt32(1, 7);
    var expected = wire.Writer.init(allocator);
    defer expected.deinit();
    try expected.writeTag(1, .start_group);
    try expected.writeUInt32(2, 100);
    try expected.writeBytes(3, note_payload.slice());
    try expected.writeTag(1, .end_group);

    const response_bytes = try runDynamic(allocator, &registry, .{
        .payload = .{ .text_payload = "[demo.note] { id: 7 }" },
        .requested_output_format = .protobuf,
        .message_type = "demo.Host",
        .test_category = .text_format_test,
    });
    defer allocator.free(response_bytes);
    var reader = wire.Reader.init(response_bytes);
    const tag = (try reader.nextTag()).?;
    try std.testing.expectEqual(@as(wire.FieldNumber, 3), tag.number);
    try std.testing.expectEqualSlices(u8, expected.slice(), try reader.readBytes());
}

test "conformance dynamic runner parses MessageSet extension json input" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host { option message_set_wire_format = true; extensions 4 to max; }
        \\message Note { optional int32 id = 1; }
        \\extend Host { optional Note note = 100; }
    );
    defer file.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);

    var note_payload = wire.Writer.init(allocator);
    defer note_payload.deinit();
    try note_payload.writeInt32(1, 7);
    var expected = wire.Writer.init(allocator);
    defer expected.deinit();
    try expected.writeTag(1, .start_group);
    try expected.writeUInt32(2, 100);
    try expected.writeBytes(3, note_payload.slice());
    try expected.writeTag(1, .end_group);

    const response_bytes = try runDynamic(allocator, &registry, .{
        .payload = .{ .json_payload = "{\"[demo.note]\":{\"id\":7}}" },
        .requested_output_format = .protobuf,
        .message_type = "demo.Host",
        .test_category = .json_test,
    });
    defer allocator.free(response_bytes);
    var reader = wire.Reader.init(response_bytes);
    const tag = (try reader.nextTag()).?;
    try std.testing.expectEqual(@as(wire.FieldNumber, 3), tag.number);
    try std.testing.expectEqualSlices(u8, expected.slice(), try reader.readBytes());
}

test "conformance dynamic runner formats MessageSet extensions as json" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host { option message_set_wire_format = true; extensions 4 to max; }
        \\message Note { optional int32 id = 1; }
        \\extend Host { optional Note note = 100; }
    );
    defer file.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);

    var note_payload = wire.Writer.init(allocator);
    defer note_payload.deinit();
    try note_payload.writeInt32(1, 7);
    var payload = wire.Writer.init(allocator);
    defer payload.deinit();
    try payload.writeTag(1, .start_group);
    try payload.writeUInt32(2, 100);
    try payload.writeBytes(3, note_payload.slice());
    try payload.writeTag(1, .end_group);

    const response_bytes = try runDynamic(allocator, &registry, .{
        .payload = .{ .protobuf_payload = payload.slice() },
        .requested_output_format = .json,
        .message_type = "demo.Host",
        .test_category = .binary_test,
    });
    defer allocator.free(response_bytes);
    var reader = wire.Reader.init(response_bytes);
    const tag = (try reader.nextTag()).?;
    try std.testing.expectEqual(@as(wire.FieldNumber, 4), tag.number);
    try std.testing.expectEqualSlices(u8, "{\"[demo.note]\":{\"id\":7}}", try reader.readBytes());
}

test "conformance dynamic runner converts proto2 extension json to text" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host { extensions 100 to 200; }
        \\extend Host { optional int32 tag = 100; }
    );
    defer file.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);

    const response_bytes = try runDynamic(allocator, &registry, .{
        .payload = .{ .json_payload = "{\"[demo.tag]\":7}" },
        .requested_output_format = .text_format,
        .message_type = "demo.Host",
        .test_category = .json_test,
    });
    defer allocator.free(response_bytes);
    var reader = wire.Reader.init(response_bytes);
    const tag = (try reader.nextTag()).?;
    try std.testing.expectEqual(@as(wire.FieldNumber, 8), tag.number);
    try std.testing.expectEqualSlices(u8, "[demo.tag]: 7\n", try reader.readBytes());
}

test "conformance dynamic runner handles message extension json payloads" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host { extensions 100 to 200; }
        \\message Note { optional int32 id = 1; }
        \\extend Host { optional Note note = 100; }
    );
    defer file.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);

    const parsed_response = try runDynamic(allocator, &registry, .{
        .payload = .{ .json_payload = "{\"[demo.note]\":{\"id\":7}}" },
        .requested_output_format = .protobuf,
        .message_type = "demo.Host",
        .test_category = .json_test,
    });
    defer allocator.free(parsed_response);
    var parsed_reader = wire.Reader.init(parsed_response);
    const parsed_tag = (try parsed_reader.nextTag()).?;
    try std.testing.expectEqual(@as(wire.FieldNumber, 3), parsed_tag.number);
    try std.testing.expectEqualSlices(u8, &.{ 0xa2, 0x06, 0x02, 0x08, 0x07 }, try parsed_reader.readBytes());

    var payload = wire.Writer.init(allocator);
    defer payload.deinit();
    try payload.writeBytes(100, &.{ 0x08, 0x07 });
    const rendered_response = try runDynamic(allocator, &registry, .{
        .payload = .{ .protobuf_payload = payload.slice() },
        .requested_output_format = .json,
        .message_type = "demo.Host",
        .test_category = .binary_test,
    });
    defer allocator.free(rendered_response);
    var rendered_reader = wire.Reader.init(rendered_response);
    const rendered_tag = (try rendered_reader.nextTag()).?;
    try std.testing.expectEqual(@as(wire.FieldNumber, 4), rendered_tag.number);
    try std.testing.expectEqualSlices(u8, "{\"[demo.note]\":{\"id\":7}}", try rendered_reader.readBytes());
}

test "conformance dynamic runner formats proto2 extension json output" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host { extensions 100 to 200; }
        \\extend Host { optional int32 tag = 100; }
    );
    defer file.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);

    var payload = wire.Writer.init(allocator);
    defer payload.deinit();
    try payload.writeInt32(100, 7);
    const response_bytes = try runDynamic(allocator, &registry, .{
        .payload = .{ .protobuf_payload = payload.slice() },
        .requested_output_format = .json,
        .message_type = "demo.Host",
        .test_category = .binary_test,
    });
    defer allocator.free(response_bytes);
    var reader = wire.Reader.init(response_bytes);
    const tag = (try reader.nextTag()).?;
    try std.testing.expectEqual(@as(wire.FieldNumber, 4), tag.number);
    try std.testing.expectEqualSlices(u8, "{\"[demo.tag]\":7}", try reader.readBytes());
}

test "conformance dynamic runner parses proto2 extension json input" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host { extensions 100 to 200; }
        \\extend Host { optional int32 tag = 100; }
    );
    defer file.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);

    const response_bytes = try runDynamic(allocator, &registry, .{
        .payload = .{ .json_payload = "{\"[demo.tag]\":7}" },
        .requested_output_format = .protobuf,
        .message_type = "demo.Host",
        .test_category = .json_test,
    });
    defer allocator.free(response_bytes);
    var reader = wire.Reader.init(response_bytes);
    const tag = (try reader.nextTag()).?;
    try std.testing.expectEqual(@as(wire.FieldNumber, 3), tag.number);
    try std.testing.expectEqualSlices(u8, &.{ 0xa0, 0x06, 0x07 }, try reader.readBytes());
}

test "conformance dynamic runner parses proto2 extension text input" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host { extensions 100 to 200; }
        \\extend Host { optional int32 tag = 100; }
    );
    defer file.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);

    const response_bytes = try runDynamic(allocator, &registry, .{
        .payload = .{ .text_payload = "[demo.tag]: 7" },
        .requested_output_format = .protobuf,
        .message_type = "demo.Host",
        .test_category = .text_format_test,
    });
    defer allocator.free(response_bytes);
    var reader = wire.Reader.init(response_bytes);
    const tag = (try reader.nextTag()).?;
    try std.testing.expectEqual(@as(wire.FieldNumber, 3), tag.number);
    try std.testing.expectEqualSlices(u8, &.{ 0xa0, 0x06, 0x07 }, try reader.readBytes());
}

test "conformance dynamic runner formats proto2 extensions as text" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator,
        \\syntax = "proto2";
        \\package demo;
        \\message Host { extensions 100 to 200; }
        \\extend Host { optional int32 tag = 100; }
    );
    defer file.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);

    var payload = wire.Writer.init(allocator);
    defer payload.deinit();
    try payload.writeInt32(100, 7);
    const response_bytes = try runDynamic(allocator, &registry, .{
        .payload = .{ .protobuf_payload = payload.slice() },
        .requested_output_format = .text_format,
        .message_type = "demo.Host",
        .test_category = .binary_test,
    });
    defer allocator.free(response_bytes);
    var reader = wire.Reader.init(response_bytes);
    const tag = (try reader.nextTag()).?;
    try std.testing.expectEqual(@as(wire.FieldNumber, 8), tag.number);
    try std.testing.expectEqualSlices(u8, "[demo.tag]: 7\n", try reader.readBytes());
}

test "conformance dynamic runner preserves text unknown fields as protobuf" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator, "syntax = \"proto2\"; package demo; message Msg { optional int32 id = 1; }");
    defer file.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);

    const response_bytes = try runDynamic(allocator, &registry, .{
        .payload = .{ .text_payload = "100: 7" },
        .requested_output_format = .protobuf,
        .message_type = "demo.Msg",
        .test_category = .text_format_test,
    });
    defer allocator.free(response_bytes);
    var reader = wire.Reader.init(response_bytes);
    const tag = (try reader.nextTag()).?;
    try std.testing.expectEqual(@as(wire.FieldNumber, 3), tag.number);
    try std.testing.expectEqualSlices(u8, &.{ 0xa0, 0x06, 0x07 }, try reader.readBytes());
}

test "conformance dynamic runner omits unknown protobuf fields from json" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator, "syntax = \"proto2\"; package demo; message Msg { optional int32 id = 1; }");
    defer file.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);

    var payload = wire.Writer.init(allocator);
    defer payload.deinit();
    try payload.writeInt32(100, 7);
    try payload.writeTag(101, .start_group);
    try payload.writeInt32(102, 8);
    try payload.writeTag(101, .end_group);
    const response_bytes = try runDynamic(allocator, &registry, .{
        .payload = .{ .protobuf_payload = payload.slice() },
        .requested_output_format = .json,
        .message_type = "demo.Msg",
        .test_category = .binary_test,
    });
    defer allocator.free(response_bytes);
    var reader = wire.Reader.init(response_bytes);
    const tag = (try reader.nextTag()).?;
    try std.testing.expectEqual(@as(wire.FieldNumber, 4), tag.number);
    try std.testing.expectEqualSlices(u8, "{}", try reader.readBytes());
}

test "conformance dynamic runner skips requested unknown TextFormat printing" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator, "syntax = \"proto2\"; package demo; message Msg { optional int32 id = 1; }");
    defer file.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);

    var payload = wire.Writer.init(allocator);
    defer payload.deinit();
    try payload.writeTag(100, .start_group);
    try payload.writeInt32(101, 7);
    try payload.writeTag(100, .end_group);
    const response_bytes = try runDynamic(allocator, &registry, .{
        .payload = .{ .protobuf_payload = payload.slice() },
        .requested_output_format = .text_format,
        .message_type = "demo.Msg",
        .test_category = .binary_test,
        .print_unknown_fields = true,
    });
    defer allocator.free(response_bytes);
    var reader = wire.Reader.init(response_bytes);
    const tag = (try reader.nextTag()).?;
    try std.testing.expectEqual(@as(wire.FieldNumber, 5), tag.number);
    try std.testing.expectEqualSlices(u8, "printing unknown TextFormat fields is unsupported", try reader.readBytes());
}

test "conformance dynamic runner preserves unknown protobuf groups" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator, "syntax = \"proto2\"; package demo; message Msg { optional int32 id = 1; }");
    defer file.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);

    var payload = wire.Writer.init(allocator);
    defer payload.deinit();
    try payload.writeTag(100, .start_group);
    try payload.writeInt32(101, 7);
    try payload.writeTag(100, .end_group);
    const response_bytes = try runDynamic(allocator, &registry, .{
        .payload = .{ .protobuf_payload = payload.slice() },
        .requested_output_format = .protobuf,
        .message_type = "demo.Msg",
        .test_category = .binary_test,
    });
    defer allocator.free(response_bytes);
    var reader = wire.Reader.init(response_bytes);
    const tag = (try reader.nextTag()).?;
    try std.testing.expectEqual(@as(wire.FieldNumber, 3), tag.number);
    try std.testing.expectEqualSlices(u8, payload.slice(), try reader.readBytes());
}

test "conformance dynamic runner preserves unknown protobuf fields" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator, "syntax = \"proto2\"; package demo; message Msg { optional int32 id = 1; }");
    defer file.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);

    var payload = wire.Writer.init(allocator);
    defer payload.deinit();
    try payload.writeInt32(100, 7);
    const response_bytes = try runDynamic(allocator, &registry, .{
        .payload = .{ .protobuf_payload = payload.slice() },
        .requested_output_format = .protobuf,
        .message_type = "demo.Msg",
        .test_category = .binary_test,
    });
    defer allocator.free(response_bytes);
    var reader = wire.Reader.init(response_bytes);
    const tag = (try reader.nextTag()).?;
    try std.testing.expectEqual(@as(wire.FieldNumber, 3), tag.number);
    try std.testing.expectEqualSlices(u8, payload.slice(), try reader.readBytes());
}

test "conformance dynamic runner reports missing required fields" {
    const allocator = std.testing.allocator;
    var file = try @import("parser.zig").Parser.parse(allocator, "syntax = \"proto2\"; package demo; message Msg { required int32 id = 1; }");
    defer file.deinit();
    var registry = registry_mod.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);
    const response_bytes = try runDynamic(allocator, &registry, .{
        .payload = .{ .protobuf_payload = "" },
        .requested_output_format = .json,
        .message_type = "demo.Msg",
        .test_category = .binary_test,
    });
    defer allocator.free(response_bytes);
    var reader = wire.Reader.init(response_bytes);
    const tag = (try reader.nextTag()).?;
    try std.testing.expectEqual(@as(wire.FieldNumber, 1), tag.number);
    const message = try reader.readBytes();
    try std.testing.expect(std.mem.indexOf(u8, message, "MissingRequiredField") != null);
    try std.testing.expect(std.mem.indexOf(u8, message, "id") != null);
}
