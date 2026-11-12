const std = @import("std");
const pbz = @import("pbz");
const person_pb = @import("person_pb");

const default_iterations: usize = 100_000;
const default_seed: u64 = 0;
const max_input_len: usize = 8192;

const Fixtures = struct {
    file: pbz.schema.FileDescriptor,
    descriptor: *const pbz.schema.MessageDescriptor,
    binary: []const u8,
    json: []const u8,
    text: []const u8,
};

const fuzz_schema =
    \\syntax = "proto3";
    \\enum Kind { UNKNOWN = 0; ADMIN = 1; }
    \\message M {
    \\  int32 id = 1;
    \\  string name = 2;
    \\  bytes payload = 3;
    \\  repeated int32 nums = 4;
    \\  repeated fixed32 fixed = 5;
    \\  map<string, int32> counts = 6;
    \\  Kind kind = 7;
    \\  M child = 8;
    \\  oneof pick { string label = 9; int64 code = 10; }
    \\}
;

fn makeFixtures(allocator: std.mem.Allocator) !Fixtures {
    var file = try pbz.ProtoParser.parse(allocator, fuzz_schema);
    errdefer file.deinit();
    const descriptor = file.findMessage("M").?;

    var message = pbz.DynamicMessage.init(allocator, descriptor);
    defer message.deinit();
    try message.add(descriptor.findField("id").?, .{ .int32 = 7 });
    try message.add(descriptor.findField("name").?, .{ .string = try allocator.dupe(u8, "fuzz") });
    try message.add(descriptor.findField("payload").?, .{ .bytes = try allocator.dupe(u8, &.{ 1, 2, 3, 4 }) });
    for ([_]i32{ 1, 2, 3 }) |value| try message.add(descriptor.findField("nums").?, .{ .int32 = value });
    for ([_]u32{ 5, 6 }) |value| try message.add(descriptor.findField("fixed").?, .{ .fixed32 = value });
    {
        const entry = try allocator.create(pbz.dynamic.MapEntry);
        entry.* = .{ .key = .{ .string = try allocator.dupe(u8, "k") }, .value = .{ .int32 = 1 } };
        try message.add(descriptor.findField("counts").?, .{ .map_entry = entry });
    }
    try message.add(descriptor.findField("kind").?, .{ .enumeration = 1 });
    try message.add(descriptor.findField("label").?, .{ .string = try allocator.dupe(u8, "pick") });

    const binary = try message.encoded(&file);
    errdefer allocator.free(binary);
    const json = try pbz.json.stringifyAlloc(allocator, &file, &message, .{});
    errdefer allocator.free(json);
    const text = try pbz.text.formatAlloc(allocator, &file, &message, .{});
    errdefer allocator.free(text);
    return .{
        .file = file,
        .descriptor = descriptor,
        .binary = binary,
        .json = json,
        .text = text,
    };
}

fn deinitFixtures(allocator: std.mem.Allocator, fixtures: *Fixtures) void {
    allocator.free(fixtures.binary);
    allocator.free(fixtures.json);
    allocator.free(fixtures.text);
    fixtures.file.deinit();
}

const RegistryFixtures = struct {
    loaded: pbz.loader.LoadResult,
    file: *const pbz.schema.FileDescriptor,
    descriptor: *const pbz.schema.MessageDescriptor,
    json: []u8,
    text: []u8,
};

const dep_source =
    \\syntax = "proto3";
    \\package fuzzdep;
    \\message Dep { string name = 1; int32 n = 2; }
;
const any_source =
    \\syntax = "proto3";
    \\package google.protobuf;
    \\message Any { string type_url = 1; bytes value = 2; }
    \\message Timestamp { int64 seconds = 1; int32 nanos = 2; }
;
const main_source =
    \\syntax = "proto3";
    \\package fuzzmain;
    \\import "dep.proto";
    \\import "google/protobuf/any.proto";
    \\message M {
    \\  fuzzdep.Dep dep = 1;
    \\  google.protobuf.Any any = 2;
    \\  google.protobuf.Timestamp ts = 3;
    \\  repeated fuzzdep.Dep deps = 4;
    \\}
;

fn makeRegistryFixtures(allocator: std.mem.Allocator) !RegistryFixtures {
    var tree = pbz.loader.MemorySourceTree.init(allocator);
    defer tree.deinit();
    try tree.add("dep.proto", dep_source);
    try tree.add("google/protobuf/any.proto", any_source);
    try tree.add("main.proto", main_source);
    var loaded = try pbz.loader.loadMemory(allocator, &tree, "main.proto");
    errdefer loaded.deinit();

    var main_file: ?*const pbz.schema.FileDescriptor = null;
    for (loaded.files.items) |*file| {
        if (std.mem.eql(u8, file.name, "main.proto")) main_file = file;
    }
    const file = main_file orelse return error.MissingMainFile;
    const descriptor = file.findMessage("M") orelse return error.MissingMessage;
    const dep_descriptor = loaded.registry.findMessage("fuzzdep.Dep", null) orelse return error.MissingMessage;

    var message = pbz.DynamicMessage.init(allocator, descriptor);
    defer message.deinit();
    {
        const dep = try allocator.create(pbz.DynamicMessage);
        dep.* = pbz.DynamicMessage.init(allocator, dep_descriptor);
        try dep.add(dep_descriptor.findField("name").?, .{ .string = try allocator.dupe(u8, "dep") });
        try dep.add(dep_descriptor.findField("n").?, .{ .int32 = 3 });
        try message.add(descriptor.findField("dep").?, .{ .message = dep });
    }
    {
        const ts_descriptor = loaded.registry.findMessage("google.protobuf.Timestamp", null) orelse return error.MissingMessage;
        const ts = try allocator.create(pbz.DynamicMessage);
        ts.* = pbz.DynamicMessage.init(allocator, ts_descriptor);
        try ts.add(ts_descriptor.findField("seconds").?, .{ .int64 = 1 });
        try ts.add(ts_descriptor.findField("nanos").?, .{ .int32 = 2 });
        try message.add(descriptor.findField("ts").?, .{ .message = ts });
    }
    const json = try pbz.json.stringifyAllocWithRegistry(allocator, file, &loaded.registry, &message, .{});
    errdefer allocator.free(json);
    const text = try pbz.text.formatAllocWithRegistry(allocator, file, &loaded.registry, &message, .{});
    errdefer allocator.free(text);
    return .{ .loaded = loaded, .file = file, .descriptor = descriptor, .json = json, .text = text };
}

fn deinitRegistryFixtures(allocator: std.mem.Allocator, fixtures: *RegistryFixtures) void {
    allocator.free(fixtures.json);
    allocator.free(fixtures.text);
    fixtures.loaded.deinit();
}

fn fuzzRegistryJson(allocator: std.mem.Allocator, fixtures: *const RegistryFixtures, bytes: []const u8) void {
    var message = pbz.json.parseAllocWithRegistry(allocator, fixtures.file, &fixtures.loaded.registry, fixtures.descriptor, bytes, .{}) catch return;
    defer message.deinit();
    const encoded = message.encodedDeterministicWithRegistry(fixtures.file, &fixtures.loaded.registry) catch return;
    allocator.free(encoded);
}

fn fuzzRegistryJsonOptions(allocator: std.mem.Allocator, fixtures: *const RegistryFixtures, bytes: []const u8) void {
    var message = pbz.json.parseAllocWithRegistry(allocator, fixtures.file, &fixtures.loaded.registry, fixtures.descriptor, bytes, .{ .ignore_unknown_fields = true }) catch return;
    defer message.deinit();
    const out = pbz.json.stringifyAllocWithRegistry(allocator, fixtures.file, &fixtures.loaded.registry, &message, .{
        .enum_as_name = false,
        .preserve_proto_field_names = true,
        .always_print_primitive_fields = true,
    }) catch return;
    allocator.free(out);
}

fn fuzzRegistryTextOptions(allocator: std.mem.Allocator, fixtures: *const RegistryFixtures, bytes: []const u8) void {
    var message = pbz.text.parseAllocWithRegistry(allocator, fixtures.file, &fixtures.loaded.registry, fixtures.descriptor, bytes) catch return;
    defer message.deinit();
    const out = pbz.text.formatAllocWithRegistry(allocator, fixtures.file, &fixtures.loaded.registry, &message, .{
        .enum_as_name = false,
        .print_unknown_fields = true,
    }) catch return;
    allocator.free(out);
}

fn fuzzRegistryText(allocator: std.mem.Allocator, fixtures: *const RegistryFixtures, bytes: []const u8) void {
    var message = pbz.text.parseAllocWithRegistry(allocator, fixtures.file, &fixtures.loaded.registry, fixtures.descriptor, bytes) catch return;
    defer message.deinit();
    const encoded = message.encodedDeterministicWithRegistry(fixtures.file, &fixtures.loaded.registry) catch return;
    allocator.free(encoded);
}

const ExtensionFixtures = struct {
    loaded: pbz.loader.LoadResult,
    file: *const pbz.schema.FileDescriptor,
    message_desc: *const pbz.schema.MessageDescriptor,
    message_set_desc: *const pbz.schema.MessageDescriptor,
    binary: []u8,
    message_set_binary: []u8,
};

const extension_source =
    \\syntax = "proto2";
    \\package fuzzext;
    \\message M {
    \\  optional int32 id = 1;
    \\  extensions 100 to 200;
    \\}
    \\extend M {
    \\  optional string ext_str = 100;
    \\  optional int32 ext_num = 101;
    \\  optional M ext_msg = 102;
    \\}
    \\message MS {
    \\  option message_set_wire_format = true;
    \\  extensions 4 to max;
    \\}
    \\extend MS {
    \\  optional M ms_ext = 100;
    \\}
;

fn makeExtensionFixtures(allocator: std.mem.Allocator) !ExtensionFixtures {
    var tree = pbz.loader.MemorySourceTree.init(allocator);
    defer tree.deinit();
    try tree.add("ext.proto", extension_source);
    var loaded = try pbz.loader.loadMemory(allocator, &tree, "ext.proto");
    errdefer loaded.deinit();

    var ext_file: ?*const pbz.schema.FileDescriptor = null;
    for (loaded.files.items) |*file| {
        if (std.mem.eql(u8, file.name, "ext.proto")) ext_file = file;
    }
    const file = ext_file orelse return error.MissingMainFile;
    const message_desc = file.findMessage("M") orelse return error.MissingMessage;
    const message_set_desc = file.findMessage("MS") orelse return error.MissingMessage;

    var inner = pbz.Writer.init(allocator);
    defer inner.deinit();
    try inner.writeInt32(1, 9);

    var writer = pbz.Writer.init(allocator);
    defer writer.deinit();
    try writer.writeInt32(1, 7);
    try writer.writeString(100, "ext");
    try writer.writeInt32(101, 5);
    try writer.writeBytes(102, inner.slice());
    const binary = try allocator.dupe(u8, writer.slice());
    errdefer allocator.free(binary);

    var message_set_writer = pbz.Writer.init(allocator);
    defer message_set_writer.deinit();
    try message_set_writer.writeTag(1, .start_group);
    try message_set_writer.writeInt32(2, 100);
    try message_set_writer.writeBytes(3, inner.slice());
    try message_set_writer.writeTag(1, .end_group);
    const message_set_binary = try allocator.dupe(u8, message_set_writer.slice());
    errdefer allocator.free(message_set_binary);

    return .{
        .loaded = loaded,
        .file = file,
        .message_desc = message_desc,
        .message_set_desc = message_set_desc,
        .binary = binary,
        .message_set_binary = message_set_binary,
    };
}

fn deinitExtensionFixtures(allocator: std.mem.Allocator, fixtures: *ExtensionFixtures) void {
    allocator.free(fixtures.binary);
    allocator.free(fixtures.message_set_binary);
    fixtures.loaded.deinit();
}

fn fuzzExtensions(allocator: std.mem.Allocator, fixtures: *const ExtensionFixtures, bytes: []const u8) void {
    var message = pbz.DynamicMessage.init(allocator, fixtures.message_desc);
    defer message.deinit();
    message.decodeWithRegistry(fixtures.file, &fixtures.loaded.registry, bytes) catch return;
    const encoded = message.encodedDeterministicWithRegistry(fixtures.file, &fixtures.loaded.registry) catch return;
    allocator.free(encoded);
}

fn fuzzMessageSet(allocator: std.mem.Allocator, fixtures: *const ExtensionFixtures, bytes: []const u8) void {
    var message = pbz.DynamicMessage.init(allocator, fixtures.message_set_desc);
    defer message.deinit();
    message.decodeWithRegistry(fixtures.file, &fixtures.loaded.registry, bytes) catch return;
    const encoded = message.encodedDeterministicWithRegistry(fixtures.file, &fixtures.loaded.registry) catch return;
    allocator.free(encoded);
}

const EditionFixtures = struct {
    file: pbz.schema.FileDescriptor,
    descriptor: *const pbz.schema.MessageDescriptor,
    binary: []u8,
    json: []u8,
    text: []u8,
};

const edition_schema =
    \\edition = "2023";
    \\package fuzzed;
    \\option features.field_presence = IMPLICIT;
    \\option features.enum_type = CLOSED;
    \\enum E { E_UNKNOWN = 0; E_ONE = 1; }
    \\message M {
    \\  int32 id = 1;
    \\  repeated int32 nums = 2 [features.repeated_field_encoding = PACKED];
    \\  repeated int32 expanded = 3 [features.repeated_field_encoding = EXPANDED];
    \\  string name = 4 [features.utf8_validation = NONE];
    \\  E kind = 5 [features.field_presence = EXPLICIT];
    \\  oneof pick { string label = 6; int64 code = 7; }
    \\  M child = 8 [features.message_encoding = DELIMITED];
    \\}
;

fn makeEditionFixtures(allocator: std.mem.Allocator) !EditionFixtures {
    var file = try pbz.ProtoParser.parse(allocator, edition_schema);
    errdefer file.deinit();
    const descriptor = file.findMessage("M") orelse return error.MissingMessage;

    var message = pbz.DynamicMessage.init(allocator, descriptor);
    defer message.deinit();
    try message.add(descriptor.findField("id").?, .{ .int32 = 7 });
    for ([_]i32{ 1, 2 }) |value| try message.add(descriptor.findField("nums").?, .{ .int32 = value });
    for ([_]i32{ 3, 4 }) |value| try message.add(descriptor.findField("expanded").?, .{ .int32 = value });
    try message.add(descriptor.findField("name").?, .{ .string = try allocator.dupe(u8, "edition") });
    try message.add(descriptor.findField("kind").?, .{ .enumeration = 1 });
    try message.add(descriptor.findField("label").?, .{ .string = try allocator.dupe(u8, "pick") });
    {
        const child = try allocator.create(pbz.DynamicMessage);
        child.* = pbz.DynamicMessage.init(allocator, descriptor);
        try child.add(descriptor.findField("id").?, .{ .int32 = 9 });
        try message.add(descriptor.findField("child").?, .{ .message = child });
    }

    const binary = try message.encoded(&file);
    errdefer allocator.free(binary);
    const json = try pbz.json.stringifyAlloc(allocator, &file, &message, .{});
    errdefer allocator.free(json);
    const text = try pbz.text.formatAlloc(allocator, &file, &message, .{});
    errdefer allocator.free(text);
    return .{ .file = file, .descriptor = descriptor, .binary = binary, .json = json, .text = text };
}

fn deinitEditionFixtures(allocator: std.mem.Allocator, fixtures: *EditionFixtures) void {
    allocator.free(fixtures.binary);
    allocator.free(fixtures.json);
    allocator.free(fixtures.text);
    fixtures.file.deinit();
}

fn fuzzEditionBinary(allocator: std.mem.Allocator, fixtures: *const EditionFixtures, bytes: []const u8) void {
    var message = pbz.DynamicMessage.init(allocator, fixtures.descriptor);
    defer message.deinit();
    message.decode(&fixtures.file, bytes) catch return;
    const encoded = message.encoded(&fixtures.file) catch return;
    allocator.free(encoded);
}

fn fuzzEditionJson(allocator: std.mem.Allocator, fixtures: *const EditionFixtures, bytes: []const u8) void {
    var message = pbz.json.parseAlloc(allocator, &fixtures.file, fixtures.descriptor, bytes, .{}) catch return;
    defer message.deinit();
    const out = pbz.json.stringifyAlloc(allocator, &fixtures.file, &message, .{}) catch return;
    allocator.free(out);
}

fn fuzzEditionText(allocator: std.mem.Allocator, fixtures: *const EditionFixtures, bytes: []const u8) void {
    var message = pbz.text.parseAlloc(allocator, &fixtures.file, fixtures.descriptor, bytes) catch return;
    defer message.deinit();
    const out = pbz.text.formatAlloc(allocator, &fixtures.file, &message, .{}) catch return;
    allocator.free(out);
}

fn generate(rng: std.Random, buffer: []u8, valid: []const u8) usize {
    if (rng.intRangeLessThan(u8, 0, 3) == 0) {
        const len = rng.intRangeAtMost(usize, 0, buffer.len);
        rng.bytes(buffer[0..len]);
        return len;
    }
    var len = @min(valid.len, buffer.len);
    @memcpy(buffer[0..len], valid[0..len]);
    const mutations = rng.intRangeAtMost(usize, 1, 8);
    var index: usize = 0;
    while (index < mutations) : (index += 1) {
        if (len != 0 and rng.boolean()) {
            buffer[rng.intRangeLessThan(usize, 0, len)] = rng.int(u8);
        } else if (len < buffer.len) {
            buffer[len] = rng.int(u8);
            len += 1;
        }
    }
    if (rng.boolean() and len != 0) len = rng.intRangeAtMost(usize, 0, len);
    return len;
}

fn fuzzWire(bytes: []const u8) void {
    var reader = pbz.wire.Reader.init(bytes);
    while (true) {
        const maybe_tag = reader.nextTag() catch break;
        const tag = maybe_tag orelse break;
        reader.skipValue(tag) catch break;
    }
}

fn fuzzDescriptor(allocator: std.mem.Allocator, bytes: []const u8) void {
    if (pbz.decodeFileDescriptorProto(allocator, bytes)) |file_value| {
        var file = file_value;
        file.deinit();
    } else |_| {}
}

fn fuzzDescriptorSet(allocator: std.mem.Allocator, bytes: []const u8) void {
    if (pbz.decodeFileDescriptorSet(allocator, bytes)) |files_value| {
        const files = files_value;
        for (files) |*file| file.deinit();
        allocator.free(files);
    } else |_| {}
}

fn fuzzProtoParser(allocator: std.mem.Allocator, bytes: []const u8) void {
    if (pbz.ProtoParser.parse(allocator, bytes)) |file_value| {
        var file = file_value;
        file.deinit();
    } else |_| {}
}

fn fuzzBinary(allocator: std.mem.Allocator, fixtures: *const Fixtures, bytes: []const u8) void {
    var message = pbz.DynamicMessage.init(allocator, fixtures.descriptor);
    defer message.deinit();
    message.decode(&fixtures.file, bytes) catch return;
    var writer = pbz.Writer.init(allocator);
    defer writer.deinit();
    message.encode(&fixtures.file, &writer) catch return;

    const numbers = message.unknownFieldNumbersAlloc(allocator) catch return;
    defer allocator.free(numbers);
    const runs = message.unknownFieldNumberRunsAlloc(allocator) catch return;
    defer allocator.free(runs);
    if (numbers.len != 0) {
        const by_number = message.unknownByNumberAlloc(allocator, numbers[0]) catch return;
        allocator.free(by_number);
    }
}

fn fuzzJson(allocator: std.mem.Allocator, fixtures: *const Fixtures, bytes: []const u8) void {
    var message = pbz.json.parseAlloc(allocator, &fixtures.file, fixtures.descriptor, bytes, .{}) catch return;
    defer message.deinit();
    var writer = pbz.Writer.init(allocator);
    defer writer.deinit();
    message.encode(&fixtures.file, &writer) catch return;
}

fn fuzzText(allocator: std.mem.Allocator, fixtures: *const Fixtures, bytes: []const u8) void {
    var message = pbz.text.parseAlloc(allocator, &fixtures.file, fixtures.descriptor, bytes) catch return;
    defer message.deinit();
    var writer = pbz.Writer.init(allocator);
    defer writer.deinit();
    message.encode(&fixtures.file, &writer) catch return;
}

fn fuzzGenerated(allocator: std.mem.Allocator, bytes: []const u8) void {
    var message = person_pb.demo.Person.decodeOwned(allocator, bytes) catch return;
    defer message.deinit(allocator);
    const encoded = message.encode(allocator) catch return;
    allocator.free(encoded);
}

/// decodeReuse/decodeOwnedReuse deinit the destination on error, so reset the
/// persistent message to a valid empty state after a failed decode.
fn fuzzGeneratedJson(allocator: std.mem.Allocator, bytes: []const u8) void {
    var message = person_pb.demo.Person.jsonParse(allocator, bytes) catch return;
    defer message.deinit(allocator);
    const encoded = message.encode(allocator) catch return;
    allocator.free(encoded);
}

fn fuzzGeneratedText(allocator: std.mem.Allocator, bytes: []const u8) void {
    var message = person_pb.demo.Person.parseText(allocator, bytes) catch return;
    defer message.deinit(allocator);
    const encoded = message.encode(allocator) catch return;
    allocator.free(encoded);
}

fn fuzzGeneratedReuse(allocator: std.mem.Allocator, message: *person_pb.demo.Person, bytes: []const u8) void {
    message.decodeReuse(allocator, bytes) catch {
        message.* = person_pb.demo.Person.init();
        return;
    };
    message.decodeOwnedReuse(allocator, bytes) catch {
        message.* = person_pb.demo.Person.init();
        return;
    };
    const encoded = message.encode(allocator) catch return;
    allocator.free(encoded);
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var iterations: usize = default_iterations;
    var seed: u64 = default_seed;
    var arg_it = init.minimal.args.iterate();
    _ = arg_it.next();
    while (arg_it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--iterations")) {
            iterations = try std.fmt.parseInt(usize, arg_it.next() orelse return error.MissingIterations, 10);
        } else if (std.mem.startsWith(u8, arg, "--iterations=")) {
            iterations = try std.fmt.parseInt(usize, arg["--iterations=".len..], 10);
        } else if (std.mem.eql(u8, arg, "--seed")) {
            seed = try std.fmt.parseInt(u64, arg_it.next() orelse return error.MissingSeed, 10);
        } else if (std.mem.startsWith(u8, arg, "--seed=")) {
            seed = try std.fmt.parseInt(u64, arg["--seed=".len..], 10);
        } else if (std.mem.eql(u8, arg, "--help")) {
            try printUsage(io);
            return;
        } else {
            try printUsage(io);
            return error.UnknownArgument;
        }
    }

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    // Fixtures must outlive the per-iteration arena reset.
    var fixtures = try makeFixtures(allocator);
    defer deinitFixtures(allocator, &fixtures);
    var registry_fixtures = try makeRegistryFixtures(allocator);
    defer deinitRegistryFixtures(allocator, &registry_fixtures);
    var extension_fixtures = try makeExtensionFixtures(allocator);
    defer deinitExtensionFixtures(allocator, &extension_fixtures);
    var edition_fixtures = try makeEditionFixtures(allocator);
    defer deinitEditionFixtures(allocator, &edition_fixtures);

    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();

    var reuse_message = person_pb.demo.Person.init();
    defer reuse_message.deinit(allocator);

    var binary_buffer: [max_input_len]u8 = undefined;
    var json_buffer: [max_input_len]u8 = undefined;
    var text_buffer: [max_input_len]u8 = undefined;
    var registry_json_buffer: [max_input_len]u8 = undefined;
    var registry_text_buffer: [max_input_len]u8 = undefined;
    var extension_buffer: [max_input_len]u8 = undefined;
    var message_set_buffer: [max_input_len]u8 = undefined;
    var edition_binary_buffer: [max_input_len]u8 = undefined;
    var edition_json_buffer: [max_input_len]u8 = undefined;
    var edition_text_buffer: [max_input_len]u8 = undefined;

    const start = std.Io.Clock.awake.now(io).nanoseconds;
    var iteration: usize = 0;
    while (iteration < iterations) : (iteration += 1) {
        _ = arena.reset(.retain_capacity);
        const scratch = arena.allocator();

        const binary_len = generate(rng, &binary_buffer, fixtures.binary);
        const json_len = generate(rng, &json_buffer, fixtures.json);
        const text_len = generate(rng, &text_buffer, fixtures.text);
        const registry_json_len = generate(rng, &registry_json_buffer, registry_fixtures.json);
        const registry_text_len = generate(rng, &registry_text_buffer, registry_fixtures.text);
        const extension_len = generate(rng, &extension_buffer, extension_fixtures.binary);
        const message_set_len = generate(rng, &message_set_buffer, extension_fixtures.message_set_binary);
        const edition_binary_len = generate(rng, &edition_binary_buffer, edition_fixtures.binary);
        const edition_json_len = generate(rng, &edition_json_buffer, edition_fixtures.json);
        const edition_text_len = generate(rng, &edition_text_buffer, edition_fixtures.text);

        fuzzWire(binary_buffer[0..binary_len]);
        fuzzDescriptor(scratch, binary_buffer[0..binary_len]);
        fuzzDescriptorSet(scratch, binary_buffer[0..binary_len]);
        fuzzProtoParser(scratch, binary_buffer[0..binary_len]);
        fuzzBinary(scratch, &fixtures, binary_buffer[0..binary_len]);
        fuzzJson(scratch, &fixtures, json_buffer[0..json_len]);
        fuzzText(scratch, &fixtures, text_buffer[0..text_len]);
        fuzzGenerated(scratch, binary_buffer[0..binary_len]);
        fuzzGeneratedReuse(allocator, &reuse_message, binary_buffer[0..binary_len]);
        fuzzGeneratedJson(scratch, json_buffer[0..json_len]);
        fuzzGeneratedText(scratch, text_buffer[0..text_len]);
        fuzzRegistryJson(scratch, &registry_fixtures, registry_json_buffer[0..registry_json_len]);
        fuzzRegistryText(scratch, &registry_fixtures, registry_text_buffer[0..registry_text_len]);
        fuzzRegistryJsonOptions(scratch, &registry_fixtures, registry_json_buffer[0..registry_json_len]);
        fuzzRegistryTextOptions(scratch, &registry_fixtures, registry_text_buffer[0..registry_text_len]);
        fuzzExtensions(scratch, &extension_fixtures, extension_buffer[0..extension_len]);
        fuzzMessageSet(scratch, &extension_fixtures, message_set_buffer[0..message_set_len]);
        fuzzEditionBinary(scratch, &edition_fixtures, edition_binary_buffer[0..edition_binary_len]);
        fuzzEditionJson(scratch, &edition_fixtures, edition_json_buffer[0..edition_json_len]);
        fuzzEditionText(scratch, &edition_fixtures, edition_text_buffer[0..edition_text_len]);
    }
    const elapsed = std.Io.Clock.awake.now(io).nanoseconds - start;

    const elapsed_ns: f64 = @floatFromInt(elapsed);
    const iterations_f: f64 = @floatFromInt(iterations);
    std.debug.print(
        "fuzz: {d} iterations, seed {d}, {d:.1} iter/s\n",
        .{ iterations, seed, iterations_f * 1_000_000_000.0 / elapsed_ns },
    );
}

fn printUsage(io: std.Io) !void {
    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writerStreaming(io, &stderr_buffer);
    try stderr_writer.interface.writeAll(
        \\usage: pbz-fuzz [--iterations N] [--seed N]
        \\
        \\Deterministic standalone fuzzer for the wire reader, descriptor decoder,
        \\.proto parser, and dynamic binary/JSON/TextFormat parsers.
        \\
    );
    try stderr_writer.interface.flush();
}
