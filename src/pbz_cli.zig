const std = @import("std");
const pbz = @import("pbz");

const Format = enum {
    binary,
    text,
    json,
};

const Command = enum {
    encode,
    decode,
    convert,
    describe,
};

const Options = struct {
    command: Command,
    descriptor_set: []const u8,
    type_name: ?[]const u8 = null,
    from_format: ?Format = null,
    to_format: ?Format = null,
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    run(allocator, io, init.minimal.args) catch |err| {
        std.debug.print("pbz: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
}

fn run(allocator: std.mem.Allocator, io: std.Io, process_args: anytype) !void {
    const options = parseOptions(process_args) catch |err| {
        try printUsage(io);
        return err;
    };

    const descriptor_bytes = try readFile(allocator, io, options.descriptor_set);
    defer allocator.free(descriptor_bytes);

    const files = try pbz.decodeFileDescriptorSet(allocator, descriptor_bytes);
    defer {
        for (files) |*file| file.deinit();
        allocator.free(files);
    }

    var registry = pbz.Registry.init(allocator);
    defer registry.deinit();
    for (files) |*file| try registry.addFile(file);

    switch (options.command) {
        .describe => try describe(allocator, io, &registry, options.type_name),
        .encode => {
            const type_name = options.type_name orelse return error.MissingType;
            const descriptor = try findMessage(&registry, type_name);
            const file = registry.fileContainingMessage(descriptor) orelse return error.UnknownMessage;
            const from_format = options.from_format orelse .text;
            const input = try readStdin(allocator, io);
            defer allocator.free(input);
            const output = try convert(allocator, file, &registry, descriptor, input, from_format, .binary);
            defer allocator.free(output);
            try writeStdout(io, output);
        },
        .decode => {
            const type_name = options.type_name orelse return error.MissingType;
            const descriptor = try findMessage(&registry, type_name);
            const file = registry.fileContainingMessage(descriptor) orelse return error.UnknownMessage;
            const to_format = options.to_format orelse .text;
            const input = try readStdin(allocator, io);
            defer allocator.free(input);
            const output = try convert(allocator, file, &registry, descriptor, input, .binary, to_format);
            defer allocator.free(output);
            try writeStdout(io, output);
        },
        .convert => {
            const type_name = options.type_name orelse return error.MissingType;
            const descriptor = try findMessage(&registry, type_name);
            const file = registry.fileContainingMessage(descriptor) orelse return error.UnknownMessage;
            const from_format = options.from_format orelse return error.MissingFormat;
            const to_format = options.to_format orelse return error.MissingFormat;
            const input = try readStdin(allocator, io);
            defer allocator.free(input);
            const output = try convert(allocator, file, &registry, descriptor, input, from_format, to_format);
            defer allocator.free(output);
            try writeStdout(io, output);
        },
    }
}

fn parseOptions(process_args: anytype) !Options {
    var args = process_args.iterate();
    _ = args.next();
    const command_text = args.next() orelse return error.MissingCommand;
    const command = parseCommand(command_text) orelse return error.UnknownCommand;

    var descriptor_set: ?[]const u8 = null;
    var type_name: ?[]const u8 = null;
    var from_format: ?Format = null;
    var to_format: ?Format = null;
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) return error.HelpRequested;
        if (optionValue(arg, "--descriptor-set")) |value| {
            descriptor_set = value;
        } else if (std.mem.eql(u8, arg, "--descriptor-set")) {
            descriptor_set = args.next() orelse return error.MissingOptionValue;
        } else if (optionValue(arg, "--type")) |value| {
            type_name = value;
        } else if (std.mem.eql(u8, arg, "--type")) {
            type_name = args.next() orelse return error.MissingOptionValue;
        } else if (optionValue(arg, "--from")) |value| {
            from_format = try parseFormat(value);
        } else if (std.mem.eql(u8, arg, "--from")) {
            from_format = try parseFormat(args.next() orelse return error.MissingOptionValue);
        } else if (optionValue(arg, "--to")) |value| {
            to_format = try parseFormat(value);
        } else if (std.mem.eql(u8, arg, "--to")) {
            to_format = try parseFormat(args.next() orelse return error.MissingOptionValue);
        } else if (std.mem.eql(u8, arg, "--json")) {
            if (command == .encode) from_format = .json else to_format = .json;
        } else if (std.mem.eql(u8, arg, "--text")) {
            if (command == .encode) from_format = .text else to_format = .text;
        } else {
            return error.UnknownOption;
        }
    }
    return .{
        .command = command,
        .descriptor_set = descriptor_set orelse return error.MissingDescriptorSet,
        .type_name = type_name,
        .from_format = from_format,
        .to_format = to_format,
    };
}

fn optionValue(arg: []const u8, name: []const u8) ?[]const u8 {
    if (arg.len <= name.len or !std.mem.startsWith(u8, arg, name) or arg[name.len] != '=') return null;
    return arg[name.len + 1 ..];
}

fn parseCommand(text: []const u8) ?Command {
    if (std.mem.eql(u8, text, "encode")) return .encode;
    if (std.mem.eql(u8, text, "decode")) return .decode;
    if (std.mem.eql(u8, text, "convert")) return .convert;
    if (std.mem.eql(u8, text, "describe")) return .describe;
    return null;
}

fn parseFormat(text: []const u8) !Format {
    if (std.mem.eql(u8, text, "binary") or std.mem.eql(u8, text, "proto")) return .binary;
    if (std.mem.eql(u8, text, "text") or std.mem.eql(u8, text, "textproto")) return .text;
    if (std.mem.eql(u8, text, "json")) return .json;
    return error.UnknownFormat;
}

fn findMessage(registry: *const pbz.Registry, name: []const u8) !*const pbz.schema.MessageDescriptor {
    return registry.findMessage(name, null) orelse error.UnknownMessage;
}

fn convert(
    allocator: std.mem.Allocator,
    file: *const pbz.schema.FileDescriptor,
    registry: *const pbz.Registry,
    descriptor: *const pbz.schema.MessageDescriptor,
    input: []const u8,
    from_format: Format,
    to_format: Format,
) ![]u8 {
    if (from_format == .binary) {
        var message = pbz.DynamicMessage.init(allocator, descriptor);
        defer message.deinit();
        try message.decodeWithRegistry(file, registry, input);
        return try formatMessage(allocator, file, registry, &message, to_format);
    }

    var message = if (from_format == .json)
        try pbz.json.parseAllocWithRegistry(allocator, file, registry, descriptor, input, .{})
    else
        try pbz.text.parseAllocWithRegistry(allocator, file, registry, descriptor, input);
    defer message.deinit();
    if (to_format == .binary) return try message.encodedWithRegistry(file, registry);
    return try formatMessage(allocator, file, registry, &message, to_format);
}

fn formatMessage(
    allocator: std.mem.Allocator,
    file: *const pbz.schema.FileDescriptor,
    registry: *const pbz.Registry,
    message: *const pbz.DynamicMessage,
    format: Format,
) ![]u8 {
    return switch (format) {
        .binary => error.InvalidOutputFormat,
        .json => try pbz.json.stringifyAllocWithRegistry(allocator, file, registry, message, .{}),
        .text => try pbz.text.formatAllocWithRegistry(allocator, file, registry, message, .{}),
    };
}

fn describe(allocator: std.mem.Allocator, io: std.Io, registry: *const pbz.Registry, type_name: ?[]const u8) !void {
    var out: std.Io.Writer.Allocating = .init(allocator);
    defer out.deinit();

    if (type_name) |name| {
        const descriptor = try findMessage(registry, name);
        const file = registry.fileContainingMessage(descriptor) orelse return error.UnknownMessage;
        try out.writer.print("message {s}.{s}\n", .{ file.package, descriptor.name });
        for (descriptor.fields.items) |*field| {
            try out.writer.print("  {d} {s} ", .{ field.number, field.name });
            if (field.kind == .map) {
                const map = field.kind.map;
                try out.writer.print("map<{s}, ", .{pbz.scalarTypeName(map.key)});
                try writeFieldValueType(&out.writer, map.value.*);
                try out.writer.writeAll(">\n");
            } else {
                if (field.cardinality == .repeated) try out.writer.writeAll("repeated ");
                try writeFieldValueType(&out.writer, field.kind);
                try out.writer.writeAll("\n");
            }
        }
    } else {
        for (registry.files.items) |file| {
            try out.writer.print("file {s}\n", .{file.name});
            for (file.messages.items) |*message| try out.writer.print("  message {s}\n", .{message.name});
            for (file.enums.items) |*enumeration| try out.writer.print("  enum {s}\n", .{enumeration.name});
            for (file.services.items) |*service| try out.writer.print("  service {s}\n", .{service.name});
        }
    }
    try writeStdout(io, out.written());
}

fn writeFieldValueType(writer: *std.Io.Writer, kind: pbz.schema.FieldKind) !void {
    switch (kind) {
        .scalar => |scalar| try writer.writeAll(pbz.scalarTypeName(scalar)),
        .enumeration => |name| try writer.writeAll(name),
        .message => |name| try writer.writeAll(name),
        .group => |name| try writer.writeAll(name),
        .map => |map| {
            try writer.print("map<{s}, ", .{pbz.scalarTypeName(map.key)});
            try writeFieldValueType(writer, map.value.*);
            try writer.writeByte('>');
        },
    }
}

fn readFile(allocator: std.mem.Allocator, io: std.Io, path: []const u8) ![]u8 {
    var file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);
    var buffer: [16 * 1024]u8 = undefined;
    var reader = file.reader(io, &buffer);
    return try reader.interface.allocRemaining(allocator, .limited(256 * 1024 * 1024));
}

fn readStdin(allocator: std.mem.Allocator, io: std.Io) ![]u8 {
    var buffer: [16 * 1024]u8 = undefined;
    var reader = std.Io.File.stdin().readerStreaming(io, &buffer);
    return try reader.interface.allocRemaining(allocator, .limited(256 * 1024 * 1024));
}

fn writeStdout(io: std.Io, bytes: []const u8) !void {
    var buffer: [16 * 1024]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(io, &buffer);
    try writer.interface.writeAll(bytes);
    try writer.interface.flush();
}

fn printUsage(io: std.Io) !void {
    var buffer: [4096]u8 = undefined;
    var writer = std.Io.File.stderr().writerStreaming(io, &buffer);
    try writer.interface.writeAll(
        \\usage: pbz <command> [options]
        \\
        \\commands:
        \\  encode   --descriptor-set FILE --type NAME [--from text|json]
        \\  decode   --descriptor-set FILE --type NAME [--to text|json]
        \\  convert  --descriptor-set FILE --type NAME --from text|json|binary --to text|json|binary
        \\  describe --descriptor-set FILE [--type NAME]
        \\
        \\Input is read from stdin and output is written to stdout.
        \\Use --json or --text as a shorthand for the relevant direction.
        \\
    );
    try writer.interface.flush();
}
