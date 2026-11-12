const std = @import("std");
const descriptor = @import("descriptor.zig");
const dynamic = @import("dynamic.zig");
const json = @import("json.zig");
const parser = @import("parser.zig");
const schema = @import("schema.zig");
const text = @import("text.zig");
const wire = @import("wire.zig");

const max_input_len = 512;

test "fuzz wire reader" {
    try std.testing.fuzz({}, struct {
        fn one(_: void, smith: *std.testing.Smith) !void {
            var buffer: [max_input_len]u8 = undefined;
            const len: usize = smith.slice(&buffer);
            var reader = wire.Reader.init(buffer[0..len]);
            while (true) {
                const maybe_tag = reader.nextTag() catch break;
                const tag = maybe_tag orelse break;
                reader.skipValue(tag) catch break;
            }
        }
    }.one, .{});
}

test "fuzz descriptor decoder" {
    try std.testing.fuzz({}, struct {
        fn one(_: void, smith: *std.testing.Smith) !void {
            var buffer: [max_input_len]u8 = undefined;
            const len: usize = smith.slice(&buffer);
            var file = descriptor.decodeFileDescriptorProto(std.testing.allocator, buffer[0..len]) catch return;
            file.deinit();
        }
    }.one, .{});
}

test "fuzz proto parser" {
    try std.testing.fuzz({}, struct {
        fn one(_: void, smith: *std.testing.Smith) !void {
            var buffer: [max_input_len]u8 = undefined;
            const len: usize = smith.slice(&buffer);
            var file = parser.Parser.parse(std.testing.allocator, buffer[0..len]) catch return;
            file.deinit();
        }
    }.one, .{});
}

const MessageFuzzContext = struct {
    file: *const schema.FileDescriptor,
    descriptor: *const schema.MessageDescriptor,
};

test "fuzz dynamic JSON parser" {
    const allocator = std.testing.allocator;
    var file = try parser.Parser.parse(allocator,
        \\syntax = "proto3";
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message M {
        \\  int32 id = 1;
        \\  string name = 2;
        \\  repeated int32 nums = 3;
        \\  map<string, int32> counts = 4;
        \\  Kind kind = 5;
        \\  M child = 6;
        \\}
    );
    defer file.deinit();
    const desc = file.findMessage("M").?;
    try std.testing.fuzz(MessageFuzzContext{ .file = &file, .descriptor = desc }, struct {
        fn one(ctx: MessageFuzzContext, smith: *std.testing.Smith) !void {
            var buffer: [max_input_len]u8 = undefined;
            const len: usize = smith.slice(&buffer);
            var message = json.parseAlloc(std.testing.allocator, ctx.file, ctx.descriptor, buffer[0..len], .{}) catch return;
            message.deinit();
        }
    }.one, .{});
}

test "fuzz dynamic text parser" {
    const allocator = std.testing.allocator;
    var file = try parser.Parser.parse(allocator,
        \\syntax = "proto3";
        \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
        \\message M {
        \\  int32 id = 1;
        \\  string name = 2;
        \\  repeated int32 nums = 3;
        \\  map<string, int32> counts = 4;
        \\  Kind kind = 5;
        \\  M child = 6;
        \\}
    );
    defer file.deinit();
    const desc = file.findMessage("M").?;
    try std.testing.fuzz(MessageFuzzContext{ .file = &file, .descriptor = desc }, struct {
        fn one(ctx: MessageFuzzContext, smith: *std.testing.Smith) !void {
            var buffer: [max_input_len]u8 = undefined;
            const len: usize = smith.slice(&buffer);
            var message = text.parseAlloc(std.testing.allocator, ctx.file, ctx.descriptor, buffer[0..len]) catch return;
            message.deinit();
        }
    }.one, .{});
}
