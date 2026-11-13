// Differential harness used by tools/run_corpus_differential.sh.
//
// Modes:
//   parse <root> <list>      parse each .proto with pbz.ProtoParser
//   strict <root> <list>     load each .proto with validate_custom_options
//   roundtrip <in> <out>     decode a FileDescriptorSet and re-encode it
//
// The driver script compares the parse/strict results with protoc's
// accept/reject list and the round-trip output with protoc's decoded text.
const std = @import("std");
const pbz = @import("pbz");

fn readFile(allocator: std.mem.Allocator, io: std.Io, path: []const u8) ![]u8 {
    var file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);
    var buffer: [16 * 1024]u8 = undefined;
    var reader = file.reader(io, &buffer);
    return try reader.interface.allocRemaining(allocator, .limited(256 * 1024 * 1024));
}

fn writeFile(allocator: std.mem.Allocator, io: std.Io, path: []const u8, bytes: []const u8) !void {
    _ = allocator;
    var out = try std.Io.Dir.cwd().createFile(io, path, .{});
    defer out.close(io);
    var buf: [16 * 1024]u8 = undefined;
    var writer = out.writer(io, &buf);
    try writer.interface.writeAll(bytes);
    try writer.interface.flush();
}

fn treeKey(path: []const u8) []const u8 {
    return if (std.mem.startsWith(u8, path, "src/")) path["src/".len..] else path;
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;
    var args = init.minimal.args.iterate();
    _ = args.next();
    const mode = args.next() orelse return error.MissingMode;
    if (std.mem.eql(u8, mode, "roundtrip")) {
        const input = args.next() orelse return error.MissingInput;
        const output = args.next() orelse return error.MissingOutput;
        const bytes = try readFile(allocator, io, input);
        defer allocator.free(bytes);
        const files = pbz.decodeFileDescriptorSet(allocator, bytes) catch |err| {
            std.debug.print("decode failed: {s}\n", .{@errorName(err)});
            std.process.exit(2);
        };
        defer {
            for (files) |*file| file.deinit();
            allocator.free(files);
        }
        var refs = try allocator.alloc(*const pbz.schema.FileDescriptor, files.len);
        defer allocator.free(refs);
        for (files, 0..) |*file, i| refs[i] = file;
        const encoded = pbz.encodeFileDescriptorSet(allocator, refs) catch |err| {
            std.debug.print("encode failed: {s}\n", .{@errorName(err)});
            std.process.exit(3);
        };
        defer allocator.free(encoded);
        try writeFile(allocator, io, output, encoded);
        return;
    }
    const root = args.next() orelse return error.MissingRoot;
    const list_path = args.next() orelse return error.MissingList;
    const list_text = try readFile(allocator, io, list_path);
    defer allocator.free(list_text);

    var tree = pbz.MemorySourceTree.init(allocator);
    defer tree.deinit();
    var paths: std.ArrayListUnmanaged([]const u8) = .empty;
    defer paths.deinit(allocator);
    var lines = std.mem.splitScalar(u8, list_text, '\n');
    while (lines.next()) |line| {
        const rel = std.mem.trim(u8, line, " \t\r\n");
        if (rel.len == 0) continue;
        const full = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ root, rel });
        const data = readFile(allocator, io, full) catch {
            allocator.free(full);
            continue;
        };
        allocator.free(full);
        try tree.add(treeKey(rel), data);
        try paths.append(allocator, treeKey(rel));
    }

    const strict = std.mem.eql(u8, mode, "strict");
    for (paths.items) |path| {
        if (strict) {
            if (pbz.loadMemoryWithOptions(allocator, &tree, path, .{ .validate_custom_options = true })) |*loaded| {
                var l = loaded.*;
                l.deinit();
                std.debug.print("OK\t{s}\n", .{path});
            } else |err| {
                std.debug.print("ERR\t{s}\t{s}\n", .{ path, @errorName(err) });
            }
        } else {
            if (pbz.ProtoParser.parse(allocator, tree.get(path).?)) |parsed| {
                var file = parsed;
                defer file.deinit();
                std.debug.print("OK\t{s}\n", .{path});
            } else |err| {
                std.debug.print("ERR\t{s}\t{s}\n", .{ path, @errorName(err) });
            }
        }
    }
}
