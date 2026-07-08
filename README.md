# pbz

`pbz` is a pure Zig Protocol Buffers toolkit targeting Zig 0.16.0.

Current milestone: **proto2 / pb2 first**.  The codebase also has early schema
surface area for proto3 and protobuf editions, but proto2 support is the first
validated feature set.

## Implemented in this snapshot

- Wire-format reader and writer
  - varint, zig-zag, fixed32/fixed64, length-delimited values, groups
  - tag parsing, unknown-field skipping, recursion guard for groups
- Schema model
  - files, messages, fields, oneofs, enums, services, imports, options
  - proto2/proto3/editions syntax flags and feature defaults
  - proto2 required/optional/repeated cardinality, enum defaults, and packed override handling
- Multi-file registry and loader
  - package/import-aware lookup for messages/enums/extensions across FileDescriptor values
  - in-memory source tree loader that recursively parses imports
- `.proto` parser
  - `syntax = "proto2"` plus package/import/option declarations
  - messages, nested messages, groups, enums, oneofs, extensions, reserved ranges, field-number, reserved, duplicate-field, and enum validation
  - services/rpc declarations and custom option names including `(ext).field`
  - string/bytes literal escape decoding and adjacent literal concatenation
- Dynamic message runtime
  - scalar encoding/decoding for all protobuf scalar wire types
  - proto2 strings/bytes, required-field validation and decodeInitialized, repeated packed fields
  - proto3 default-packed repeated numeric fields and map fields
  - editions `features.repeated_field_encoding` packed/expanded behavior
  - nested message and group round-trips
  - unknown field preservation, extension decoding with Registry, and message merging
- JSON support
  - dynamic message stringify/parse for scalars, 64-bit numeric strings, bytes/base64, repeated fields, maps, enums, and nested messages
- TextFormat support
  - dynamic message formatting/parsing for scalars, repeated fields, maps, enums, and nested messages

## Quick example

```zig
const std = @import("std");
const pbz = @import("pbz");

pub fn example(allocator: std.mem.Allocator) !void {
    const source =
        \\syntax = "proto2";
        \\message Person {
        \\  required int32 id = 1;
        \\  optional string name = 2 [default = "anonymous"];
        \\  repeated sint32 scores = 3 [packed = true];
        \\}
    ;

    var file = try pbz.ProtoParser.parse(allocator, source);
    defer file.deinit();

    const person_desc = file.findMessage("Person").?;
    var msg = pbz.DynamicMessage.init(allocator, person_desc);
    defer msg.deinit();

    try msg.add(person_desc.findField("id").?, .{ .int32 = 7 });
    try msg.add(person_desc.findField("name").?, .{ .string = try allocator.dupe(u8, "Zig") });
    try msg.add(person_desc.findField("scores").?, .{ .sint32 = -1 });
    try msg.add(person_desc.findField("scores").?, .{ .sint32 = 42 });
    try msg.validateRequired();

    const bytes = try msg.encoded(&file);
    defer allocator.free(bytes);
}
```

## Type registry

Use `pbz.Registry` to register multiple parsed files and resolve message/enum
types by absolute or scoped names:

```zig
var registry = pbz.Registry.init(allocator);
defer registry.deinit();
try registry.addFile(&common_file);
try registry.addFile(&app_file);

const user = registry.findMessage(".demo.common.User", null).?;
```

## Import loader

For tests and embedded schemas, `pbz.MemorySourceTree` can load a root `.proto`
and its imports from memory:

```zig
var tree = pbz.MemorySourceTree.init(allocator);
defer tree.deinit();
try tree.add("common.proto", common_source);
try tree.add("app.proto", app_source);

var loaded = try pbz.loadMemory(allocator, &tree, "app.proto");
defer loaded.deinit();
const request = loaded.registry.findMessage(".demo.app.Request", null).?;
```

## JSON support

Dynamic messages can be written and parsed using protobuf JSON mapping basics:

```zig
const json_bytes = try pbz.stringifyJsonAlloc(allocator, &file, &msg, .{});
defer allocator.free(json_bytes);

var parsed_msg = try pbz.parseJsonAlloc(allocator, &file, descriptor, json_bytes, .{});
defer parsed_msg.deinit();
```

The current JSON support handles present fields from dynamic messages, quoted
64-bit integers, bytes as base64, repeated fields as arrays, maps as JSON
objects, enum names/numbers, default lowerCamelCase field names, null-as-absent parsing, and nested messages recursively.

## TextFormat support

Dynamic messages can be formatted and parsed as protobuf TextFormat-style text:

```zig
const text_bytes = try pbz.formatTextAlloc(allocator, &file, &msg, .{});
defer allocator.free(text_bytes);

var parsed_text_msg = try pbz.parseTextAlloc(allocator, &file, descriptor, text_bytes);
defer parsed_text_msg.deinit();
```

## Descriptor encoding

`pbz.descriptor` can encode parsed schemas into descriptor.proto-compatible
wire bytes for `FileDescriptorProto` and `FileDescriptorSet` workflows, and decode
basic descriptor bytes back into the schema model:

```zig
const descriptor_bytes = try pbz.encodeFileDescriptorProto(allocator, &file, "schema.proto");
defer allocator.free(descriptor_bytes);

var decoded_file = try pbz.decodeFileDescriptorProto(allocator, descriptor_bytes);
defer decoded_file.deinit();
```

The current descriptor support covers core file/message/field/enum/service
metadata, map-entry descriptors, packed field options, and edition feature
metadata.

## Build and test

```sh
zig build test
```

The project is formatted and validated with Zig 0.16.0.
