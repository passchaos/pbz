const std = @import("std");
const pbz = @import("pbz");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var file = try pbz.ProtoParser.parse(allocator,
        \\// Syntax leading comment.
        \\syntax = "proto3";
        \\package demo;
        \\option (demo.file_opt).child = "file-value";
        \\
        \\// Event leading comment.
        \\message Event {
        \\  // id leading comment.
        \\  int32 id = 1 [(demo.field_opt).nested.leaf = 123]; // id trailing comment.
        \\}
    );
    defer file.deinit();
    file.name = "event.proto";

    const syntax_location = sourceLocation(&file, &.{12}) orelse return error.MissingSourceInfo;
    try std.testing.expectEqualStrings("Syntax leading comment.\n", syntax_location.leading_comments.?);
    const event_location = sourceLocation(&file, &.{ 4, 0 }) orelse return error.MissingSourceInfo;
    try std.testing.expectEqualStrings("Event leading comment.\n", event_location.leading_comments.?);
    const id_location = sourceLocation(&file, &.{ 4, 0, 2, 0 }) orelse return error.MissingSourceInfo;
    try std.testing.expectEqualStrings("id leading comment.\n", id_location.leading_comments.?);
    try std.testing.expectEqualStrings("id trailing comment.\n", id_location.trailing_comments.?);

    const descriptor_bytes = try pbz.encodeFileDescriptorProto(allocator, &file, file.name);
    defer allocator.free(descriptor_bytes);

    var decoded_file = try pbz.decodeFileDescriptorProto(allocator, descriptor_bytes);
    defer decoded_file.deinit();
    std.debug.assert(decoded_file.findMessage("Event") != null);
    try std.testing.expectEqualStrings("(demo.file_opt).child", decoded_file.options.items[0].name);
    try std.testing.expectEqualStrings("file-value", decoded_file.options.items[0].value.string);
    const decoded_field = decoded_file.findMessage("Event").?.findField("id") orelse return error.MissingField;
    try std.testing.expectEqualStrings("(demo.field_opt).nested.leaf", decoded_field.options.items[0].name);
    try std.testing.expectEqual(@as(i64, 123), decoded_field.options.items[0].value.integer);
    const decoded_id_location = sourceLocation(&decoded_file, &.{ 4, 0, 2, 0 }) orelse return error.MissingSourceInfo;
    try std.testing.expectEqualStrings("id trailing comment.\n", decoded_id_location.trailing_comments.?);

    const descriptor_set = try pbz.encodeFileDescriptorSet(allocator, &.{&file});
    defer allocator.free(descriptor_set);

    const decoded_set = try pbz.decodeFileDescriptorSet(allocator, descriptor_set);
    defer {
        for (decoded_set) |*decoded| decoded.deinit();
        allocator.free(decoded_set);
    }
    std.debug.assert(decoded_set.len == 1);
    try std.testing.expectEqualStrings("(demo.file_opt).child", decoded_set[0].options.items[0].name);

    const zig_source = try pbz.generateZigFile(allocator, &file);
    defer allocator.free(zig_source);
    std.debug.assert(std.mem.indexOf(u8, zig_source, "pub const Event") != null);

    var request = pbz.CodeGeneratorRequest.init(allocator);
    defer request.deinit();
    request.parameter = "paths=source_relative,pbz_import=pbz";
    try request.files_to_generate.append(allocator, file.name);
    try request.appendProtoFile(try pbz.ProtoParser.parse(allocator,
        \\syntax = "proto3";
        \\message Event { int32 id = 1; }
    ));
    request.proto_files.items[0].name = file.name;

    const response_bytes = try pbz.generatePluginResponseFromRequest(allocator, &request);
    defer allocator.free(response_bytes);
    std.debug.assert(response_bytes.len != 0);
    try expectPluginResponseMetadata(allocator, response_bytes, file.name);
}

fn sourceLocation(file: *const pbz.FileDescriptor, path: []const i32) ?*const pbz.SourceCodeInfo.Location {
    for (file.source_code_info.locations.items) |*location| {
        if (std.mem.eql(i32, location.path.items, path)) return location;
    }
    return null;
}

fn expectPluginResponseMetadata(allocator: std.mem.Allocator, response_bytes: []const u8, source_file: []const u8) !void {
    var reader = pbz.Reader.init(response_bytes);
    var saw_features = false;
    var saw_minimum_edition = false;
    var saw_maximum_edition = false;
    var saw_file = false;
    var saw_generated_info = false;
    var saw_file_annotation = false;
    var saw_message_annotation = false;
    var saw_field_annotation = false;

    while (try reader.nextTag()) |tag| {
        switch (tag.number) {
            2 => saw_features = (try reader.readUInt64()) != 0,
            3 => saw_minimum_edition = (try reader.readInt32()) == @intFromEnum(pbz.schema.Edition.proto2),
            4 => saw_maximum_edition = (try reader.readInt32()) == @intFromEnum(pbz.schema.Edition.edition_2026),
            15 => {
                saw_file = true;
                var file_reader = pbz.Reader.init(try reader.readBytes());
                while (try file_reader.nextTag()) |file_tag| {
                    switch (file_tag.number) {
                        1 => try std.testing.expectEqualStrings("event.pb.zig", try file_reader.readBytes()),
                        15 => try std.testing.expect(std.mem.indexOf(u8, try file_reader.readBytes(), "pub const Event") != null),
                        16 => {
                            saw_generated_info = true;
                            var info = try pbz.decodeGeneratedCodeInfo(allocator, try file_reader.readBytes());
                            defer info.deinit(allocator);
                            for (info.annotations.items) |annotation| {
                                const source_matches = std.mem.eql(u8, annotation.source_file orelse "", source_file);
                                const range_valid = annotation.begin.? >= 0 and annotation.end.? > annotation.begin.?;
                                const semantic_matches = annotation.semantic.? == .set;
                                if (annotation.path.items.len == 0) saw_file_annotation = saw_file_annotation or source_matches and range_valid and semantic_matches;
                                if (std.mem.eql(i32, annotation.path.items, &.{ 4, 0 })) saw_message_annotation = saw_message_annotation or source_matches and range_valid and semantic_matches;
                                if (std.mem.eql(i32, annotation.path.items, &.{ 4, 0, 2, 0 })) saw_field_annotation = saw_field_annotation or source_matches and range_valid and semantic_matches;
                            }
                        },
                        else => try file_reader.skipValue(file_tag),
                    }
                }
            },
            else => try reader.skipValue(tag),
        }
    }

    try std.testing.expect(saw_features);
    try std.testing.expect(saw_minimum_edition);
    try std.testing.expect(saw_maximum_edition);
    try std.testing.expect(saw_file);
    try std.testing.expect(saw_generated_info);
    try std.testing.expect(saw_file_annotation);
    try std.testing.expect(saw_message_annotation);
    try std.testing.expect(saw_field_annotation);
}
