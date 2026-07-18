const std = @import("std");
const wire = @import("wire.zig");
const descriptor = @import("descriptor.zig");
const schema = @import("schema.zig");

pub const Error = wire.Error || std.mem.Allocator.Error || descriptor.Error || error{InvalidInsertionPoint};

pub const CodeGeneratorRequest = struct {
    allocator: std.mem.Allocator,
    files_to_generate: std.ArrayList([]const u8) = .empty,
    parameter: []const u8 = "",
    compiler_version: ?Version = null,
    proto_files: std.ArrayList(schema.FileDescriptor) = .empty,
    source_file_descriptors: std.ArrayList(schema.FileDescriptor) = .empty,

    pub const Version = struct {
        major: i32 = 0,
        minor: i32 = 0,
        patch: i32 = 0,
        suffix: []const u8 = "",
    };

    pub fn init(allocator: std.mem.Allocator) CodeGeneratorRequest {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *CodeGeneratorRequest) void {
        self.files_to_generate.deinit(self.allocator);
        for (self.proto_files.items) |*file| file.deinit();
        self.proto_files.deinit(self.allocator);
        for (self.source_file_descriptors.items) |*file| file.deinit();
        self.source_file_descriptors.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn appendProtoFile(self: *CodeGeneratorRequest, file: schema.FileDescriptor) std.mem.Allocator.Error!void {
        var owned = file;
        errdefer owned.deinit();
        try self.proto_files.append(self.allocator, owned);
    }

    pub fn appendSourceFileDescriptor(self: *CodeGeneratorRequest, file: schema.FileDescriptor) std.mem.Allocator.Error!void {
        var owned = file;
        errdefer owned.deinit();
        try self.source_file_descriptors.append(self.allocator, owned);
    }

    pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) Error!CodeGeneratorRequest {
        var request = CodeGeneratorRequest.init(allocator);
        errdefer request.deinit();
        var reader = wire.Reader.init(bytes);
        while (try reader.nextTag()) |tag| {
            switch (tag.number) {
                1 => try request.files_to_generate.append(allocator, try reader.readBytes()),
                2 => request.parameter = try reader.readBytes(),
                3 => request.compiler_version = try decodeVersion(try reader.readBytes()),
                15 => try request.appendProtoFile(try descriptor.decodeFileDescriptorProto(allocator, try reader.readBytes())),
                17 => try request.appendSourceFileDescriptor(try descriptor.decodeFileDescriptorProto(allocator, try reader.readBytes())),
                else => try reader.skipValue(tag),
            }
        }
        return request;
    }

    fn decodeVersion(bytes: []const u8) wire.Error!Version {
        var version = Version{};
        var reader = wire.Reader.init(bytes);
        while (try reader.nextTag()) |tag| {
            switch (tag.number) {
                1 => version.major = try reader.readInt32(),
                2 => version.minor = try reader.readInt32(),
                3 => version.patch = try reader.readInt32(),
                4 => version.suffix = try reader.readBytes(),
                else => try reader.skipValue(tag),
            }
        }
        return version;
    }
};

pub const CodeGeneratorResponse = struct {
    error_message: ?[]const u8 = null,
    supported_features: ?u64 = null,
    minimum_edition: ?schema.Edition = null,
    maximum_edition: ?schema.Edition = null,
    files: []const File = &.{},

    pub const Feature = enum(u64) {
        none = 0,
        proto3_optional = 1,
        supports_editions = 2,
    };

    pub fn featureMask(features: []const Feature) u64 {
        var mask: u64 = 0;
        for (features) |feature| mask |= @intFromEnum(feature);
        return mask;
    }

    pub const File = struct {
        name: ?[]const u8 = null,
        insertion_point: ?[]const u8 = null,
        content: []const u8 = "",
        generated_code_info: ?[]const u8 = null,
        generated_code_info_value: ?*const schema.GeneratedCodeInfo = null,
    };

    pub fn encode(self: CodeGeneratorResponse, allocator: std.mem.Allocator) Error![]u8 {
        var writer = wire.Writer.init(allocator);
        errdefer writer.deinit();
        if (self.error_message) |message| try writer.writeString(1, message);
        if (self.supported_features) |features| try writer.writeUInt64(2, features);
        if (self.minimum_edition) |edition| try writer.writeInt32(3, @intFromEnum(edition));
        if (self.maximum_edition) |edition| try writer.writeInt32(4, @intFromEnum(edition));
        for (self.files) |file| {
            if (file.insertion_point != null and file.name == null) return error.InvalidInsertionPoint;
            var fw = wire.Writer.init(allocator);
            defer fw.deinit();
            if (file.name) |name| try fw.writeString(1, name);
            if (file.insertion_point) |point| try fw.writeString(2, point);
            try fw.writeString(15, file.content);
            if (file.generated_code_info_value) |info| {
                var info_writer = wire.Writer.init(allocator);
                defer info_writer.deinit();
                try descriptor.writeGeneratedCodeInfo(allocator, info, &info_writer);
                try fw.writeMessage(16, info_writer.slice());
            } else if (file.generated_code_info) |info| {
                try fw.writeMessage(16, info);
            }
            try writer.writeMessage(15, fw.slice());
        }
        return try writer.toOwnedSlice();
    }
};

test "plugin response encodes metadata and generated files" {
    const allocator = std.testing.allocator;
    const info = [_]u8{ 0x08, 0x01 };
    const files = [_]CodeGeneratorResponse.File{.{ .name = "out.zig", .insertion_point = "namespace_scope", .content = "pub const ok = true;\n", .generated_code_info = &info }};
    const features = CodeGeneratorResponse.featureMask(&[_]CodeGeneratorResponse.Feature{ .proto3_optional, .supports_editions });
    const response = CodeGeneratorResponse{
        .supported_features = features,
        .minimum_edition = .proto2,
        .maximum_edition = .edition_2026,
        .files = &files,
    };
    const bytes = try response.encode(allocator);
    defer allocator.free(bytes);

    var reader = wire.Reader.init(bytes);
    var saw_features = false;
    var saw_min_edition = false;
    var saw_max_edition = false;
    var saw_file = false;
    var saw_name = false;
    var saw_insertion_point = false;
    var saw_content = false;
    var saw_generated_code_info = false;
    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            2 => {
                saw_features = (try reader.readUInt64()) == features;
            },
            3 => {
                saw_min_edition = (try reader.readInt32()) == @intFromEnum(schema.Edition.proto2);
            },
            4 => {
                saw_max_edition = (try reader.readInt32()) == @intFromEnum(schema.Edition.edition_2026);
            },
            15 => {
                saw_file = true;
                const payload = try reader.readBytes();
                var file_reader = wire.Reader.init(payload);
                while (try file_reader.nextTag()) |file_tag| {
                    switch (file_tag.number) {
                        1 => saw_name = std.mem.eql(u8, try file_reader.readBytes(), "out.zig"),
                        2 => saw_insertion_point = std.mem.eql(u8, try file_reader.readBytes(), "namespace_scope"),
                        15 => saw_content = std.mem.eql(u8, try file_reader.readBytes(), "pub const ok = true;\n"),
                        16 => saw_generated_code_info = std.mem.eql(u8, try file_reader.readBytes(), &info),
                        else => try file_reader.skipValue(file_tag),
                    }
                }
            },
            else => try reader.skipValue(tag),
        }
    }
    try std.testing.expect(saw_features);
    try std.testing.expect(saw_min_edition);
    try std.testing.expect(saw_max_edition);
    try std.testing.expect(saw_file);
    try std.testing.expect(saw_name);
    try std.testing.expect(saw_insertion_point);
    try std.testing.expect(saw_content);
    try std.testing.expect(saw_generated_code_info);
}

test "plugin response rejects insertion points without file names" {
    const allocator = std.testing.allocator;
    const files = [_]CodeGeneratorResponse.File{.{ .insertion_point = "scope", .content = "const x = 1;\n" }};
    const response = CodeGeneratorResponse{ .files = &files };
    try std.testing.expectError(error.InvalidInsertionPoint, response.encode(allocator));
}

test "plugin response encodes structured generated code info" {
    const allocator = std.testing.allocator;
    var generated = schema.GeneratedCodeInfo{};
    defer generated.deinit(allocator);
    var annotation = schema.GeneratedCodeInfo.Annotation{};
    try annotation.path.appendSlice(allocator, &.{ 4, 0 });
    annotation.source_file = "input.proto";
    annotation.begin = 0;
    annotation.end = 12;
    annotation.semantic = .alias;
    try generated.annotations.append(allocator, annotation);

    const files = [_]CodeGeneratorResponse.File{.{ .name = "out.zig", .content = "pub const x = 1;\n", .generated_code_info_value = &generated }};
    const response = CodeGeneratorResponse{ .files = &files };
    const bytes = try response.encode(allocator);
    defer allocator.free(bytes);

    var reader = wire.Reader.init(bytes);
    var decoded_info = schema.GeneratedCodeInfo{};
    defer decoded_info.deinit(allocator);
    while (try reader.nextTag()) |tag| {
        if (tag.number != 15) {
            try reader.skipValue(tag);
            continue;
        }
        var file_reader = wire.Reader.init(try reader.readBytes());
        while (try file_reader.nextTag()) |file_tag| {
            if (file_tag.number == 16) {
                decoded_info = try descriptor.decodeGeneratedCodeInfo(allocator, try file_reader.readBytes());
            } else {
                try file_reader.skipValue(file_tag);
            }
        }
    }

    try std.testing.expectEqual(@as(usize, 1), decoded_info.annotations.items.len);
    try std.testing.expectEqualSlices(i32, &.{ 4, 0 }, decoded_info.annotations.items[0].path.items);
    try std.testing.expectEqualStrings("input.proto", decoded_info.annotations.items[0].source_file.?);
    try std.testing.expectEqual(@as(i32, 0), decoded_info.annotations.items[0].begin.?);
    try std.testing.expectEqual(@as(i32, 12), decoded_info.annotations.items[0].end.?);
    try std.testing.expectEqual(schema.GeneratedCodeInfo.Semantic.alias, decoded_info.annotations.items[0].semantic.?);
}

test "plugin request decodes file names descriptors compiler version and source descriptors" {
    const allocator = std.testing.allocator;
    var file = schema.FileDescriptor.init(allocator);
    defer file.deinit();
    file.name = "input.proto";
    file.setSyntax(.proto3);
    const fd = try descriptor.encodeFileDescriptorProto(allocator, &file, file.name);
    defer allocator.free(fd);

    var source_file = schema.FileDescriptor.init(allocator);
    defer source_file.deinit();
    source_file.name = "source.proto";
    source_file.setSyntax(.proto2);
    const source_fd = try descriptor.encodeFileDescriptorProto(allocator, &source_file, source_file.name);
    defer allocator.free(source_fd);

    var version_writer = wire.Writer.init(allocator);
    defer version_writer.deinit();
    try version_writer.writeInt32(1, 27);
    try version_writer.writeInt32(2, 3);
    try version_writer.writeInt32(3, 1);
    try version_writer.writeString(4, "rc2");

    var writer = wire.Writer.init(allocator);
    defer writer.deinit();
    try writer.writeString(1, "input.proto");
    try writer.writeString(2, "param=1");
    try writer.writeMessage(3, version_writer.slice());
    try writer.writeMessage(15, fd);
    try writer.writeMessage(17, source_fd);

    var request = try CodeGeneratorRequest.decode(allocator, writer.slice());
    defer request.deinit();
    try std.testing.expectEqualSlices(u8, "input.proto", request.files_to_generate.items[0]);
    try std.testing.expectEqualSlices(u8, "param=1", request.parameter);
    try std.testing.expect(request.compiler_version != null);
    try std.testing.expectEqual(@as(i32, 27), request.compiler_version.?.major);
    try std.testing.expectEqual(@as(i32, 3), request.compiler_version.?.minor);
    try std.testing.expectEqual(@as(i32, 1), request.compiler_version.?.patch);
    try std.testing.expectEqualSlices(u8, "rc2", request.compiler_version.?.suffix);
    try std.testing.expectEqualStrings("input.proto", request.proto_files.items[0].name);
    try std.testing.expectEqualStrings("source.proto", request.source_file_descriptors.items[0].name);
}
