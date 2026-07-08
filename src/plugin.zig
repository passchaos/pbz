const std = @import("std");
const wire = @import("wire.zig");
const descriptor = @import("descriptor.zig");
const schema = @import("schema.zig");

pub const Error = wire.Error || std.mem.Allocator.Error || descriptor.Error;

pub const CodeGeneratorRequest = struct {
    allocator: std.mem.Allocator,
    files_to_generate: std.ArrayList([]const u8) = .empty,
    parameter: []const u8 = "",
    proto_files: std.ArrayList(schema.FileDescriptor) = .empty,

    pub fn init(allocator: std.mem.Allocator) CodeGeneratorRequest {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *CodeGeneratorRequest) void {
        self.files_to_generate.deinit(self.allocator);
        for (self.proto_files.items) |*file| file.deinit();
        self.proto_files.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) Error!CodeGeneratorRequest {
        var request = CodeGeneratorRequest.init(allocator);
        errdefer request.deinit();
        var reader = wire.Reader.init(bytes);
        while (try reader.nextTag()) |tag| {
            switch (tag.number) {
                1 => try request.files_to_generate.append(allocator, try reader.readBytes()),
                2 => request.parameter = try reader.readBytes(),
                15 => try request.proto_files.append(allocator, try descriptor.decodeFileDescriptorProto(allocator, try reader.readBytes())),
                else => try reader.skipValue(tag),
            }
        }
        return request;
    }
};

pub const CodeGeneratorResponse = struct {
    error_message: ?[]const u8 = null,
    files: []const File = &.{},

    pub const File = struct {
        name: []const u8,
        insertion_point: ?[]const u8 = null,
        content: []const u8 = "",
    };

    pub fn encode(self: CodeGeneratorResponse, allocator: std.mem.Allocator) Error![]u8 {
        var writer = wire.Writer.init(allocator);
        errdefer writer.deinit();
        if (self.error_message) |message| try writer.writeString(1, message);
        for (self.files) |file| {
            var fw = wire.Writer.init(allocator);
            defer fw.deinit();
            try fw.writeString(1, file.name);
            if (file.insertion_point) |point| try fw.writeString(2, point);
            try fw.writeString(15, file.content);
            try writer.writeMessage(15, fw.slice());
        }
        return try writer.toOwnedSlice();
    }
};

test "plugin response encodes generated files" {
    const allocator = std.testing.allocator;
    const files = [_]CodeGeneratorResponse.File{.{ .name = "out.zig", .content = "pub const ok = true;\n" }};
    const response = CodeGeneratorResponse{ .files = &files };
    const bytes = try response.encode(allocator);
    defer allocator.free(bytes);

    var reader = wire.Reader.init(bytes);
    const tag = (try reader.nextTag()).?;
    try std.testing.expectEqual(@as(wire.FieldNumber, 15), tag.number);
    const payload = try reader.readBytes();
    var file_reader = wire.Reader.init(payload);
    var saw_name = false;
    var saw_content = false;
    while (try file_reader.nextTag()) |file_tag| {
        switch (file_tag.number) {
            1 => saw_name = std.mem.eql(u8, try file_reader.readBytes(), "out.zig"),
            15 => saw_content = std.mem.eql(u8, try file_reader.readBytes(), "pub const ok = true;\n"),
            else => try file_reader.skipValue(file_tag),
        }
    }
    try std.testing.expect(saw_name);
    try std.testing.expect(saw_content);
}

test "plugin request decodes file names and descriptors" {
    const allocator = std.testing.allocator;
    var file = schema.FileDescriptor.init(allocator);
    defer file.deinit();
    file.name = "input.proto";
    file.setSyntax(.proto3);
    const fd = try descriptor.encodeFileDescriptorProto(allocator, &file, file.name);
    defer allocator.free(fd);

    var writer = wire.Writer.init(allocator);
    defer writer.deinit();
    try writer.writeString(1, "input.proto");
    try writer.writeString(2, "param=1");
    try writer.writeMessage(15, fd);

    var request = try CodeGeneratorRequest.decode(allocator, writer.slice());
    defer request.deinit();
    try std.testing.expectEqualSlices(u8, "input.proto", request.files_to_generate.items[0]);
    try std.testing.expectEqualSlices(u8, "param=1", request.parameter);
    try std.testing.expectEqualStrings("input.proto", request.proto_files.items[0].name);
}
