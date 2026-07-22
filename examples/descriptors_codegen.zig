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
        \\service Audit {
        \\  option deprecated = true;
        \\  rpc Get (Event) returns (Event) {
        \\    option deprecated = true;
        \\    option idempotency_level = IDEMPOTENT;
        \\    option (demo.method_opt) = "method-value";
        \\  }
        \\}
    );
    defer file.deinit();
    file.name = "event.proto";
    var registry = pbz.Registry.init(allocator);
    defer registry.deinit();
    try registry.addFile(&file);
    const refl = pbz.Reflection.init(allocator, &registry);

    try std.testing.expect(refl.sourceLocationCount(&file) >= 3);
    try std.testing.expect(refl.sourceLocationExists(&file, &.{12}));
    try std.testing.expect(!refl.sourceLocationExists(&file, &.{ 9, 9 }));
    const first_location = try refl.sourceLocationAt(&file, 0);
    try std.testing.expect(refl.sourceLocationPath(first_location).len != 0);
    try std.testing.expectEqual(@as(usize, 0), try refl.sourceLocationIndex(&file, first_location));
    try std.testing.expectError(error.UnknownField, refl.sourceLocationAt(&file, refl.sourceLocationCount(&file)));
    const syntax_location = try refl.sourceLocation(&file, &.{12});
    try std.testing.expectEqualSlices(i32, &.{12}, refl.sourceLocationPath(syntax_location));
    try std.testing.expectEqual(@as(usize, 4), refl.sourceLocationSpan(syntax_location).len);
    try std.testing.expectEqualStrings("Syntax leading comment.\n", refl.sourceLocationLeadingComments(syntax_location).?);
    try std.testing.expect(refl.sourceLocationTrailingComments(syntax_location) == null);
    try std.testing.expectEqual(@as(usize, 0), refl.sourceLocationLeadingDetachedCommentCount(syntax_location));
    try std.testing.expectError(error.UnknownField, refl.sourceLocationLeadingDetachedCommentAt(syntax_location, 0));
    const event_location = file.source_code_info.location(&.{ 4, 0 }) orelse return error.MissingSourceInfo;
    try std.testing.expectEqualStrings("Event leading comment.\n", refl.sourceLocationLeadingComments(event_location).?);
    const id_location = try refl.sourceLocation(&file, &.{ 4, 0, 2, 0 });
    try std.testing.expectEqualSlices(i32, &.{ 4, 0, 2, 0 }, refl.sourceLocationPath(id_location));
    try std.testing.expectEqualStrings("id leading comment.\n", refl.sourceLocationLeadingComments(id_location).?);
    try std.testing.expectEqualStrings("id trailing comment.\n", refl.sourceLocationTrailingComments(id_location).?);

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
    const decoded_id_location = decoded_file.source_code_info.location(&.{ 4, 0, 2, 0 }) orelse return error.MissingSourceInfo;
    try std.testing.expectEqualStrings("id trailing comment.\n", refl.sourceLocationTrailingComments(decoded_id_location).?);
    const decoded_service = decoded_file.services.items[0];
    try std.testing.expect(optionValue(decoded_service.options.items, "deprecated").?.boolean);
    const decoded_method = decoded_service.methods.items[0];
    try std.testing.expect(optionValue(decoded_method.options.items, "deprecated").?.boolean);
    try std.testing.expectEqual(@as(i64, 2), optionValue(decoded_method.options.items, "idempotency_level").?.integer);
    try std.testing.expectEqualStrings("method-value", optionValue(decoded_method.options.items, "(demo.method_opt)").?.string);

    const descriptor_set = try pbz.encodeFileDescriptorSet(allocator, &.{&file});
    defer allocator.free(descriptor_set);

    const decoded_set = try pbz.decodeFileDescriptorSet(allocator, descriptor_set);
    defer {
        for (decoded_set) |*decoded| decoded.deinit();
        allocator.free(decoded_set);
    }
    std.debug.assert(decoded_set.len == 1);
    try std.testing.expectEqualStrings("(demo.file_opt).child", decoded_set[0].options.items[0].name);
    try std.testing.expect(optionValue(decoded_set[0].services.items[0].options.items, "deprecated").?.boolean);

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
    try expectPluginResponseMetadata(allocator, refl, response_bytes, file.name);
}

fn optionValue(options: []const pbz.schema.FieldOption, name: []const u8) ?pbz.schema.OptionValue {
    for (options) |option| {
        if (std.mem.eql(u8, option.name, name)) return option.value;
    }
    return null;
}

fn expectPluginResponseMetadata(allocator: std.mem.Allocator, refl: pbz.Reflection, response_bytes: []const u8, source_file: []const u8) !void {
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
                            const annotation_count = refl.generatedAnnotationCount(&info);
                            try std.testing.expect(annotation_count >= 3);
                            try std.testing.expect(refl.generatedAnnotationExists(&info, &.{ 4, 0, 2, 0 }));
                            try std.testing.expect(!refl.generatedAnnotationExists(&info, &.{ 9, 9 }));
                            const first_annotation = try refl.generatedAnnotationAt(&info, 0);
                            try std.testing.expectEqual(@as(usize, 0), try refl.generatedAnnotationIndex(&info, first_annotation));
                            try std.testing.expectError(error.UnknownField, refl.generatedAnnotationAt(&info, annotation_count));
                            saw_file_annotation = saw_file_annotation or generatedAnnotationMatches(refl, try refl.generatedAnnotation(&info, &.{}), &.{}, source_file);
                            saw_message_annotation = saw_message_annotation or generatedAnnotationMatches(refl, try refl.generatedAnnotation(&info, &.{ 4, 0 }), &.{ 4, 0 }, source_file);
                            saw_field_annotation = saw_field_annotation or generatedAnnotationMatches(refl, try refl.generatedAnnotation(&info, &.{ 4, 0, 2, 0 }), &.{ 4, 0, 2, 0 }, source_file);
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

fn generatedAnnotationMatches(refl: pbz.Reflection, annotation: *const pbz.GeneratedCodeInfo.Annotation, expected_path: []const i32, source_file: []const u8) bool {
    if (!std.mem.eql(i32, refl.generatedAnnotationPath(annotation), expected_path)) return false;
    if (!refl.generatedAnnotationHasSourceFile(annotation) or !refl.generatedAnnotationHasBegin(annotation) or !refl.generatedAnnotationHasEnd(annotation) or !refl.generatedAnnotationHasSemantic(annotation)) return false;
    const begin = refl.generatedAnnotationBegin(annotation) catch return false;
    const end = refl.generatedAnnotationEnd(annotation) catch return false;
    return std.mem.eql(u8, refl.generatedAnnotationSourceFile(annotation) catch return false, source_file) and
        begin >= 0 and
        end > begin and
        (refl.generatedAnnotationSemantic(annotation) catch return false) == .set;
}
