const std = @import("std");
const pbz = @import("pbz");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var file = try pbz.ProtoParser.parse(allocator,
        \\syntax = "proto3";
        \\package demo;
        \\message Event { int32 id = 1; }
    );
    defer file.deinit();
    file.name = "event.proto";

    const descriptor_bytes = try pbz.encodeFileDescriptorProto(allocator, &file, file.name);
    defer allocator.free(descriptor_bytes);

    var decoded_file = try pbz.decodeFileDescriptorProto(allocator, descriptor_bytes);
    defer decoded_file.deinit();
    std.debug.assert(decoded_file.findMessage("Event") != null);

    const descriptor_set = try pbz.encodeFileDescriptorSet(allocator, &.{&file});
    defer allocator.free(descriptor_set);

    const decoded_set = try pbz.decodeFileDescriptorSet(allocator, descriptor_set);
    defer {
        for (decoded_set) |*decoded| decoded.deinit();
        allocator.free(decoded_set);
    }
    std.debug.assert(decoded_set.len == 1);

    const zig_source = try pbz.generateZigFile(allocator, &file);
    defer allocator.free(zig_source);
    std.debug.assert(std.mem.indexOf(u8, zig_source, "pub const Event") != null);

    var request = pbz.CodeGeneratorRequest.init(allocator);
    defer request.deinit();
    request.parameter = "paths=source_relative,pbz_import=pbz";
    try request.files_to_generate.append(allocator, file.name);
    try request.proto_files.append(allocator, try pbz.ProtoParser.parse(allocator,
        \\syntax = "proto3";
        \\message Event { int32 id = 1; }
    ));
    request.proto_files.items[0].name = file.name;

    const response_bytes = try pbz.generatePluginResponseFromRequest(allocator, &request);
    defer allocator.free(response_bytes);
    std.debug.assert(response_bytes.len != 0);
}
