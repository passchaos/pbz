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
  - proto2 required/optional/repeated cardinality plus proto3/editions required rejection, enum defaults, and packed override handling
- Multi-file registry and loader
  - package/import-aware lookup for messages/enums/extensions across FileDescriptor values
  - in-memory and filesystem source tree loaders that recursively parse imports
- `.proto` parser
  - `syntax = "proto2"` plus package/import/option declarations
  - messages, nested messages, groups, enums, oneofs, extensions, reserved ranges, field-number, reserved/extension range, duplicate-field, and enum validation including allow_alias
  - services/rpc declarations and custom option names including `(ext).field`
  - string/bytes literal escape decoding and adjacent literal concatenation
- Dynamic message runtime
  - scalar encoding/decoding for all protobuf scalar wire types
  - proto2 strings/bytes, required-field validation and decodeInitialized, repeated packed fields
  - proto3 optional fields, default-packed repeated numeric fields, and map fields
  - editions `features.repeated_field_encoding` packed/expanded behavior
  - nested message and group round-trips
  - unknown field preservation/querying, extension encoding/decoding with Registry, deterministic encoding including map key ordering, and message merging
- JSON support
  - dynamic message stringify/parse for scalars, 64-bit numeric strings, bytes/base64, repeated fields, maps, enums, and nested messages
- Well-known types
  - basic google.protobuf.Timestamp, Duration, FieldMask, Any, Empty, Struct/Value/ListValue, and wrapper wire/JSON helpers with validation plus dynamic JSON mapping
- Conformance helpers
  - basic ConformanceRequest decode, ConformanceResponse encode, and dynamic runner
- Protoc plugin and codegen helpers
  - basic CodeGeneratorRequest decode, CodeGeneratorResponse encode, and Zig typed scalar/repeated-scalar/enum/message-payload/map skeleton generation
- TextFormat support
  - dynamic message formatting/parsing for scalars, repeated fields, maps, enums, nested messages, and common separators and # comments

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
and its imports from memory. For filesystem projects, use `pbz.loadPath` or
`pbz.loadDir` to recursively parse imports from disk:

```zig
var tree = pbz.MemorySourceTree.init(allocator);
defer tree.deinit();
try tree.add("common.proto", common_source);
try tree.add("app.proto", app_source);

var loaded = try pbz.loadMemory(allocator, &tree, "app.proto");
defer loaded.deinit();
const request = loaded.registry.findMessage(".demo.app.Request", null).?;


var loaded_from_disk = try pbz.loadPath(allocator, "/path/to/protos", "app.proto");
defer loaded_from_disk.deinit();
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
64-bit integers, bytes as standard/URL-safe base64, repeated fields as arrays, maps as JSON
objects, enum names/numbers, default lowerCamelCase field names, null-as-absent parsing, and nested messages recursively.

## Well-known types

`pbz.Timestamp` provides basic `google.protobuf.Timestamp` wire and JSON helpers:

```zig
const ts = pbz.Timestamp{ .seconds = 1_577_836_800, .nanos = 123_000_000 };
const json_ts = try ts.jsonStringifyAlloc(allocator);
defer allocator.free(json_ts);

const d = pbz.Duration{ .seconds = -3, .nanos = -250_000_000 };
const mask = pbz.FieldMask{ .paths = &.{"foo_bar"} };
```

## TextFormat support

Dynamic messages can be formatted and parsed as protobuf TextFormat-style text:

```zig
const text_bytes = try pbz.formatTextAlloc(allocator, &file, &msg, .{});
defer allocator.free(text_bytes);

var parsed_text_msg = try pbz.parseTextAlloc(allocator, &file, descriptor, text_bytes);
defer parsed_text_msg.deinit();
```

## Conformance helpers

`pbz.ConformanceRequest` and `pbz.ConformanceResponse` provide basic wire
structures and a dynamic-message runner for integrating with protobuf conformance-style runners.

## Protoc plugin helpers

`pbz.CodeGeneratorRequest` and `pbz.CodeGeneratorResponse` provide the basic
wire types needed to build protoc-style generators; `pbz.generateZigFile` emits
a starter Zig typed scalar/repeated-scalar/enum/message-payload/map skeleton with field constants, fields, init, encode, and basic decode methods including repeated scalar/enum/message payload and map storage for parsed descriptors.

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

The current descriptor support covers core file/message/import/field/enum/service
metadata, map-entry/proto3-optional descriptors, packed field options, file/message/enum/field uninterpreted
options, and edition feature metadata.

## Build and test

```sh
zig build test
```

The project is formatted and validated with Zig 0.16.0.
