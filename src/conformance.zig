const std = @import("std");
const wire = @import("wire.zig");

pub const Error = wire.Error || std.mem.Allocator.Error;

pub const WireFormat = enum(i32) {
    unspecified = 0,
    protobuf = 1,
    json = 2,
    text_format = 3,
    jspb = 4,
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
                3 => out.requested_output_format = @enumFromInt(try reader.readInt32()),
                4 => out.message_type = try reader.readBytes(),
                5 => out.test_category = @enumFromInt(try reader.readInt32()),
                7 => out.payload = .{ .jspb_payload = try reader.readBytes() },
                8 => out.payload = .{ .text_payload = try reader.readBytes() },
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

    const response = try (ConformanceResponse{ .result = .{ .json_payload = "{}" } }).encode(allocator);
    defer allocator.free(response);
    try std.testing.expectEqualSlices(u8, &.{ 0x22, 0x02, '{', '}' }, response);
}
