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
  - exclusive proto2/proto3/editions syntax flags including unstable/test-only edition literals and expanded FeatureSet defaults
  - proto2 required/optional/repeated cardinality plus proto3/editions required rejection in parser and descriptor decode paths, enum defaults, packed override handling, structured FeatureSet options, and FieldOptions edition default / feature support metadata
- Multi-file registry and loader
  - package/import-aware lookup for messages/enums/extensions across FileDescriptor values, including protobuf-style scoped type resolution that rejects arbitrary unqualified imported leaf-name matches, scoped/nested proto2 extension full-name lookup, direct/public import visibility helpers and import-chain discovery, with duplicate type/extension conflict detection, unresolved/invisible field and service method type-reference plus extension-extendee rejection, and cross-file extension declaration validation including package-qualified declared names/types
  - in-memory and filesystem source tree loaders that recursively parse imports while allowing missing proto2 weak imports, validating imported enum defaults, and tracking placeholder-style weak references
- `.proto` parser
  - `syntax = "proto2"` plus package/import/option declarations
  - messages, nested messages, groups, enums, oneofs, service/rpc descriptor declarations, extensions, reserved ranges/names including editions identifier reserved names, field-number, reserved/extension/enum range conflicts and message reserved/extension range field-number bounds including `to max` plus MessageSet max handling, extension extendee/range/label/duplicate checks, duplicate-field/oneof/type/service/rpc-symbol, oneof field-shape, empty/duplicate import rejection, weak-import, option-import edition/order, and edition-value restrictions, and enum validation including non-empty enums, allow_alias misuse plus enum-value sibling-scope and prefix/case conflicts
  - JSON field-name validation for default lowerCamelCase collisions, explicit `json_name` duplicates/collisions, extension-looking names, embedded NULs, extension-field `json_name` misuse, and explicit `map_entry` misuse
  - proto2 MessageSet declaration validation for `message_set_wire_format`, extension ranges, and optional-message extension shape in parser and descriptor decode paths
  - extension range options for `declaration`, `verification`, and range-local `features.*`; declaration-scope `features.*` across file/message/field/oneof/enum/enum-value/service/method with editions-only applicability and strict feature-name/value validation; nested/scoped proto2 extension full-name tracking; plus field-level `edition_defaults` / `feature_support` aggregate parsing, with package-qualified declaration name/type consistency validation
  - service/rpc descriptor declarations and custom option names including `(ext).field`
  - string/bytes literal escape decoding and adjacent literal concatenation
  - basic SourceCodeInfo path/span generation for file-level syntax/package/import, top-level and nested message/enum/service declarations, implicit group nested messages and their fields, fields, oneofs, options, extension fields, extension/reserved ranges, reserved names, enum values, and RPC methods, including adjacent/detached line leading comments plus same-line line/block trailing comments
  - proto2 field default validation for scalar/string/bytes/enum defaults including max uint64/fixed64 values and registry-validated imported enum defaults, with proto3/repeated/message/duplicate invalid-default rejection
  - packed/lazy/unverified_lazy/weak/jstype field option validation, with editions rejecting legacy `[packed]`, `[ctype]`, and `group` syntax in favor of features and validating implicit-presence default/closed-enum constraints
- Dynamic message runtime
  - scalar encoding/decoding for all protobuf scalar wire types
  - proto2 strings/bytes, required-field validation, missing required field path reporting, schema-aware enum default number/name lookup including imported enum defaults through Registry plus repeated/map enum name helpers, encode/decodeInitialized helpers, repeated packed fields
  - proto2 MessageSet wire-format encode/decode for known registry extensions plus unknown item preservation
  - proto2/closed-enum unknown numeric values are preserved as unknown fields for singular, repeated, packed repeated, and enum map entries, including imported enums resolved through Registry using the enum descriptor's owning-file features
  - proto3 optional scalar/message fields with descriptor synthetic-oneof round-trips, default-packed repeated numeric fields, and map fields with duplicate-key last-wins replacement on add/decode
  - editions `features.repeated_field_encoding` packed/expanded behavior, `features.message_encoding` delimited/length-prefixed message wire behavior, enum-level `features.enum_type` open/closed override behavior, string UTF-8 validation via `features.utf8_validation`, and implicit/explicit/legacy-required `features.field_presence` behavior
  - descriptor encode/decode for common `FileOptions` fields, `MessageOptions.map_entry`, `FeatureSet` on file/message/field/oneof/enum/enum-value/service/method/extension-range options, `FeatureSetDefaults` with closest-edition lookup helpers and strict edition bounds, plus `FieldOptions.edition_defaults` and `FieldOptions.feature_support`, registry-aware descriptor-set encoding that resolves imported proto2 extension extendees to their owning-file fully-qualified names and emits imported enum defaults by enum value name, descriptor-set decode that preserves missing weak-import placeholders for unresolved proto2 weak references, preserving protobuf edition feature metadata as structured schema fields, rejecting malformed decoded syntax/edition combinations, symbol identifiers/type references/defaults/json names/oneof and proto3-optional shapes/proto3 enum first values/editions group fields/map-entry references/known option and FeatureSet enum values/invalid packed or field-option applicability including editions `ctype`, and using descriptor-compatible C escapes for proto2 bytes defaults
  - nested message and group round-trips, including protobuf merge semantics for duplicate singular message/group fields, imported message and enum decode through Registry including same-package unqualified imported references, registry-aware encode helpers for imported enum scalar/repeated/map fields, and nested imported-message encode/decode using the imported descriptor's owning file features (for example proto2 UTF-8/expanded repeated behavior inside proto3 parents)
  - unknown field preservation/querying/appending/clearing, extension encoding/decoding with Registry including encode-time scoped/nested extendee checks, registry-aware initialized encode/decode helpers, deterministic encoding including map key ordering, recursive deterministic nested message/group/map-message payload encoding, unknown-field number/wire/raw ordering, and recursive message merging
- JSON support
  - dynamic message stringify/parse for scalars, 64-bit numeric strings, bytes/base64, repeated fields, maps, UTF-8 validated string output, enums including editions open/closed enum numeric validation with imported enums honoring their owning-file features, nested and Any-expanded imported messages parsed/stringified under their owning-file features including proto2 explicit default presence, proto3 optional message presence, proto2 extension bracket keys including scoped extension names, initialized parse helpers with recursive required validation, and registry-aware imported message/enum parsing including same-package unqualified imports plus imported enum-name/default stringify
- Well-known types
  - basic google.protobuf.Timestamp, Duration, FieldMask, Any, Empty, Struct/Value/ListValue, and wrapper wire/JSON parse/stringify helpers with validation plus dynamic JSON mapping, including canonical 0/3/6/9 fractional JSON output for Timestamp/Duration, lowercase `t`/`z` Timestamp parsing, wire-decode range/nanos validation, registry-aware Any expanded payload JSON plus strict standalone/dynamic Any object fields and UTF-8 type URLs, strict Timestamp timezone-offset and malformed-number parsing, Duration sign/range validation, Struct/Value non-finite number rejection, Struct map duplicate-key last-wins wire decode, WKT string/key UTF-8 validation, wrapper null/default parsing and float special values, strict FieldMask snake_case/lowerCamel JSON path validation, and strict Empty object parsing
- Conformance helpers
  - basic ConformanceRequest decode, safe enum handling, ConformanceResponse encode, and dynamic runner with deterministic registry-aware protobuf output including JSON/TextFormat input plus unknown-field/group preservation, JSON unknown omission, TextFormat unknown-field input, and TextFormat unknown-group output, registry-aware JSON/Text input, JSON ignore-unknown field/enum-name/closed-enum-number category handling, TextFormat closed-enum unknown rejection, imported JSON/Text type conversion paths, proto2 extension and MessageSet JSON/TextFormat paths, and missing-required path parse errors
- Protoc plugin and codegen helpers
  - CodeGeneratorRequest decode for file_to_generate, parameter, compiler_version, proto_file, and source_file_descriptors; CodeGeneratorResponse encode for error, supported_features, edition bounds, generated files, insertion points, and raw or structured generated_code_info; request-based generated plugin responses honor file_to_generate, parse basic generator parameters, reject unresolved type references, accept raw CodeGeneratorRequest bytes, expose writer-based plugin runners and an installed protoc-gen-pbz executable, emit file, top-level, nested message/enum, field, and enum-value GeneratedCodeInfo annotations, use all proto_file descriptors as a registry for imports, and advertise proto3 optional plus editions support
  - Zig typed scalar/repeated-scalar/enum/message-payload/map skeleton with AST syntax validation generation, including proto `allow_alias` enum values emitted as Zig enum namespace aliases and generated enum `fromInt` / `fromName` / `toInt` / `protoName` / JSON parse/stringify and TextFormat parse/format helpers
  - generated `proto_package`, `proto_syntax`, and import module aliases with import kind/path metadata plus registry-aware generation for same-package unqualified, direct, and transitive-public imported message type references and imported enum field resolution while preserving local/nested enum scope priority
  - generated proto2 extension metadata structs with extension number, registry-normalized extendee names for imported targets, cardinality, protobuf value type, Zig value type strings, typed `write`/`writeAll` plus `decodeValue`/`decodeAppend` helpers, and MessageSet-aware write helpers
  - generated service metadata with registry-aware method input/output type references; RPC transport, Handler/Client stubs, and dispatch adapters are intentionally out of scope
  - generated `encodeInitialized`/`decodeInitialized` helpers validate proto2 and editions legacy-required fields around typed encode/decode
  - generated `missingRequiredFieldName` / `missingRequiredFieldPath` helpers report direct and nested proto2 required-field failures
  - generated packed encode/decode for packable repeated scalar/enum fields, including proto2 `[packed = true]`
  - generated decoders retain unknown wire fields and preserve closed-enum unknown numeric values for singular/repeated/map/oneof enum fields; generated encoders replay retained unknowns
  - generated message structs expose unknown field count/list/filter, validated raw unknown append, clear helpers, and merge unknown fields through `mergeFrom`
  - generated field declarations honor proto2 scalar/string/bytes/bool/float/enum defaults, including imported enum defaults during registry-aware generation, plus editions field-presence, message-encoding, and string UTF-8 validation features
  - generated message structs expose field accessors for presence-aware singular fields, repeated/map append/replace/clear with map duplicate-key last-wins replacement, oneof union arms, typed enum get/set/default/repeated-batch/map-entry helpers, typed map-message append/replace/remove/get entry helpers, same-file typed message payload encode/decode helpers, decodeMessageField aliases, and `cloneOwned` / `decodeOwned` helpers for deep-copying decoded slice payloads
  - generated typed JSON stringify/parse helpers plus basic TextFormat formatters/parsers for scalar, enum, repeated, map, message payload, proto2 group, same-file proto2 extension, and oneof fields, including exact scoped/nested extension extendee matching; generated JSON helpers accept/emit bracketed same-file proto2 extension keys backed by unknown/raw storage and generated JSON/TextFormat helpers use registry-aware direct and transitive-public imported message types when available for singular, repeated, map, oneof, and proto2 extension payloads; generated wire/TextFormat UTF-8 validation for string/map-string fields; and generated wire/TextFormat closed-enum validation for singular/repeated/map/oneof enum fields
- TextFormat support
  - dynamic message formatting/parsing for scalars, repeated fields, maps including default key/value fill for omitted map-entry members, enums including editions open/closed enum numeric validation with imported enums honoring their owning-file features plus registry-aware imported message/enum parsing including same-package unqualified imports, local enum scope priority, and imported enum-name formatting, initialized parse helpers with recursive required validation, protobuf merge semantics for duplicate singular message/group fields, string UTF-8 validation via `features.utf8_validation` during parse and format with imported messages parsed/formatted under their owning-file features, nested messages, proto2 extension fields using `[ext.name]` including scoped extension names and MessageSet extensions, numeric unknown fields and numeric unknown groups, `{}`/`<>` delimiters with optional colon, bool aliases, decimal/hex/octal integers, common separators, # comments, common string/bytes escapes, and adjacent string literal concatenation

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

## More usage examples

The snippets below assume Zig 0.16.0, an `allocator: std.mem.Allocator`, and:

```zig
const std = @import("std");
const pbz = @import("pbz");
```

### Low-level wire writer and reader

Use `pbz.Writer` and `pbz.Reader` when you need direct protobuf wire access or
when building tests around exact wire payloads:

```zig
var writer = pbz.Writer.init(allocator);
defer writer.deinit();

try writer.writeInt32(1, 123);
try writer.writeString(2, "zig");
try writer.writeBool(3, true);

var reader = pbz.Reader.init(writer.slice());
while (try reader.nextTag()) |tag| {
    switch (tag.number) {
        1 => {
            try pbz.Reader.expectWireType(tag, .varint);
            const id = try reader.readInt32();
            _ = id;
        },
        2 => {
            try pbz.Reader.expectWireType(tag, .length_delimited);
            const name = try reader.readBytes();
            _ = name;
        },
        3 => {
            try pbz.Reader.expectWireType(tag, .varint);
            const active = try reader.readBool();
            _ = active;
        },
        else => try reader.skipValue(tag),
    }
}
```

### Dynamic messages with scalars, repeated fields, maps, and oneofs

Dynamic messages are useful when schemas are loaded or parsed at runtime:

```zig
var file = try pbz.ProtoParser.parse(allocator,
    \\syntax = "proto3";
    \\message Event {
    \\  int32 id = 1;
    \\  repeated string tags = 2;
    \\  map<string, int32> counts = 3;
    \\  oneof payload { string note = 4; bytes raw = 5; }
    \\}
);
defer file.deinit();

const event_desc = file.findMessage("Event").?;
var event = pbz.DynamicMessage.init(allocator, event_desc);
defer event.deinit();

try event.add(event_desc.findField("id").?, .{ .int32 = 7 });
try event.add(event_desc.findField("tags").?, .{ .string = try allocator.dupe(u8, "zig") });
try event.add(event_desc.findField("note").?, .{ .string = try allocator.dupe(u8, "hello") });

const count_entry = try allocator.create(pbz.dynamic.MapEntry);
count_entry.* = .{
    .key = .{ .string = try allocator.dupe(u8, "red") },
    .value = .{ .int32 = 1 },
};
try event.add(event_desc.findField("counts").?, .{ .map_entry = count_entry });

// Adding the same map key replaces the previous value (last value wins).
const replacement = try allocator.create(pbz.dynamic.MapEntry);
replacement.* = .{
    .key = .{ .string = try allocator.dupe(u8, "red") },
    .value = .{ .int32 = 9 },
};
try event.add(event_desc.findField("counts").?, .{ .map_entry = replacement });

const encoded = try event.encodedDeterministic(&file);
defer allocator.free(encoded);

var decoded = pbz.DynamicMessage.init(allocator, event_desc);
defer decoded.deinit();
try decoded.decode(&file, encoded);
```

### Required-field validation and missing-field paths

For proto2 or editions legacy-required data, use initialized helpers or inspect
the missing path yourself:

```zig
var file = try pbz.ProtoParser.parse(allocator,
    \\syntax = "proto2";
    \\message Child { required int32 id = 1; }
    \\message Parent { required Child child = 1; }
);
defer file.deinit();

const parent_desc = file.findMessage("Parent").?;
var parent = pbz.DynamicMessage.init(allocator, parent_desc);
defer parent.deinit();

if (parent.validateRequired()) |_| {
    unreachable;
} else |err| switch (err) {
    error.MissingRequiredField => {
        const path = try parent.missingRequiredFieldPath(allocator);
        defer if (path) |p| allocator.free(p);
        // path is usually "child" or a nested suffix such as "child.id".
    },
}
```

### Unknown fields and extension-like payload storage

Unknown fields are preserved during dynamic decode and can also be appended from
raw wire bytes:

```zig
var unknown_raw = pbz.Writer.init(allocator);
defer unknown_raw.deinit();
try unknown_raw.writeUInt32(100, 999);

try event.appendUnknownRaw(unknown_raw.slice());
if (event.hasUnknownFieldNumber(100)) {
    const fields = event.unknownByNumber(100);
    _ = fields;
}
event.clearUnknownFieldsByNumber(100);
```

### Registry-aware imports and memory loading

Use `MemorySourceTree` for tests, embedded schemas, and generated fixtures that
need imports:

```zig
var tree = pbz.MemorySourceTree.init(allocator);
defer tree.deinit();
try tree.add("common.proto",
    \\syntax = "proto3";
    \\package demo.common;
    \\message User { int32 id = 1; }
);
try tree.add("app.proto",
    \\syntax = "proto3";
    \\package demo.app;
    \\import "common.proto";
    \\message Event { demo.common.User user = 1; }
);

var loaded = try pbz.loadMemory(allocator, &tree, "app.proto");
defer loaded.deinit();

const event_desc = loaded.registry.findMessage(".demo.app.Event", null).?;
const user_desc = loaded.registry.findMessage(".demo.common.User", null).?;
_ = event_desc;
_ = user_desc;
```

### Dynamic JSON round-trip

JSON helpers support protobuf JSON mapping basics, registry-aware imported
message/enum fields, and initialized parsing for required-field checks:

```zig
const json_bytes = try pbz.stringifyJsonAlloc(allocator, &file, &event, .{
    .enum_as_name = true,
    .always_print_primitive_fields = true,
});
defer allocator.free(json_bytes);

var from_json = try pbz.parseJsonAlloc(allocator, &file, event_desc, json_bytes, .{
    .ignore_unknown_fields = false,
});
defer from_json.deinit();

var checked = try pbz.parseJsonInitializedAlloc(allocator, &file, event_desc, json_bytes, .{});
defer checked.deinit();
```

### Dynamic TextFormat round-trip

TextFormat helpers are useful for human-readable fixtures and conformance-style
conversion tests:

```zig
const text_bytes = try pbz.formatTextAlloc(allocator, &file, &event, .{
    .indent = "  ",
    .enum_as_name = true,
});
defer allocator.free(text_bytes);

var from_text = try pbz.parseTextAlloc(allocator, &file, event_desc, text_bytes);
defer from_text.deinit();

var checked_text = try pbz.parseTextInitializedAlloc(allocator, &file, event_desc, text_bytes);
defer checked_text.deinit();
```

### Descriptor encode/decode and descriptor sets

Descriptor helpers let you convert parsed schemas to descriptor.proto-compatible
wire bytes and back:

```zig
const file_bytes = try pbz.encodeFileDescriptorProto(allocator, &file, "event.proto");
defer allocator.free(file_bytes);

var decoded_file = try pbz.decodeFileDescriptorProto(allocator, file_bytes);
defer decoded_file.deinit();

const set_bytes = try pbz.encodeFileDescriptorSet(allocator, &.{&file});
defer allocator.free(set_bytes);

const decoded_set = try pbz.decodeFileDescriptorSet(allocator, set_bytes);
defer {
    for (decoded_set) |*decoded| decoded.deinit();
    allocator.free(decoded_set);
}
```

### Well-known type helpers

Well-known type helpers provide wire and JSON routines with protobuf validation:

```zig
const ts = try pbz.Timestamp.jsonParse("\"2020-01-02T03:04:05.123Z\"");
const ts_json = try ts.jsonStringifyAlloc(allocator);
defer allocator.free(ts_json);

const duration = try pbz.Duration.jsonParse("\"-3.250s\"");
const duration_wire = try duration.encode(allocator);
defer allocator.free(duration_wire);

var mask = try pbz.FieldMask.jsonParseOwned(allocator, "\"fooBar,baz\"");
defer mask.deinit(allocator);

var title = try pbz.StringValue.jsonParseOwned(allocator, "\"hello\"");
defer title.deinit(allocator);

var any_title = try pbz.Any.packEncoded(allocator, "google.protobuf.StringValue", title);
defer any_title.deinit(allocator);

var unpacked = try any_title.unpackEncodedOwned(
    pbz.StringValue,
    allocator,
    "google.protobuf.StringValue",
);
defer unpacked.deinit(allocator);
```

### Proto2 extensions through JSON/TextFormat and unknown storage

Proto2 extension fields are represented through descriptors and preserved unknown
field storage. Registry-aware JSON/TextFormat helpers can parse and print known
extension names:

```zig
var file = try pbz.ProtoParser.parse(allocator,
    \\syntax = "proto2";
    \\package demo;
    \\message Host { extensions 100 to max; }
    \\extend Host { optional int32 priority = 100; }
);
defer file.deinit();

var registry = pbz.Registry.init(allocator);
defer registry.deinit();
try registry.addFile(&file);

const host_desc = file.findMessage("Host").?;
var host = try pbz.parseTextAllocWithRegistry(
    allocator,
    &file,
    &registry,
    host_desc,
    "[demo.priority]: 5\n",
);
defer host.deinit();

if (!host.hasUnknownFieldNumber(100)) return error.MissingExtensionPayload;

const host_json = try pbz.stringifyJsonAllocWithRegistry(
    allocator,
    &file,
    &registry,
    &host,
    .{},
);
defer allocator.free(host_json);
```

### Generated typed Zig API

After generating `person.pb.zig` with `protoc-gen-pbz` for a schema like
`message Person { required int32 id = 1; repeated int32 scores = 2;
map<string, int32> counts = 3; }`, import it like any other Zig module and use
the generated accessors:

```zig
const person_pb = @import("person.pb.zig");

var person = person_pb.@"Person".init();
defer person.deinit(allocator);

person.@"setField_id"(7);
try person.@"appendField_scores"(allocator, 10);
try person.@"appendField_scores"(allocator, 20);

try person.@"appendField_counts"(allocator, .{ .key = "red", .value = 1 });
try person.@"appendField_counts"(allocator, .{ .key = "red", .value = 2 }); // replaces red

const person_bytes = try person.encodeInitialized(allocator);
defer allocator.free(person_bytes);

var owned_person = try person_pb.@"Person".decodeOwnedInitialized(allocator, person_bytes);
defer owned_person.deinit(allocator);

const person_json = try owned_person.jsonStringifyAllocWithOptions(allocator, .{
    .preserve_proto_field_names = true,
    .always_print_primitive_fields = true,
});
defer allocator.free(person_json);

var parsed_person = try person_pb.@"Person".parseText(allocator,
    \\id: 7
    \\scores: 10
    \\counts { key: "red" value: 2 }
);
defer parsed_person.deinit(allocator);
```

### Generating Zig from descriptors or plugin requests

Use `generateZigFile` directly for in-process codegen, or build a protoc-style
request when testing generator integrations:

```zig
const zig_source = try pbz.generateZigFile(allocator, &file);
defer allocator.free(zig_source);

var request = pbz.CodeGeneratorRequest.init(allocator);
defer request.deinit();
request.parameter = "paths=source_relative,pbz_import=pbz";
try request.files_to_generate.append(allocator, "event.proto");
try request.proto_files.append(allocator, try pbz.ProtoParser.parse(allocator,
    \\syntax = "proto3";
    \\message Event { int32 id = 1; }
));
request.proto_files.items[0].name = "event.proto";

const response_bytes = try pbz.generatePluginResponseFromRequest(allocator, &request);
defer allocator.free(response_bytes);
```

Command-line protoc integration uses the installed plugin executable:

```sh
zig build
protoc --plugin=protoc-gen-pbz=zig-out/bin/protoc-gen-pbz \
  --pbz_out=paths=source_relative:. \
  person.proto
```

### Conformance-style conversion

The conformance runner converts between protobuf, JSON, and TextFormat using a
registered descriptor:

```zig
var registry = pbz.Registry.init(allocator);
defer registry.deinit();
try registry.addFile(&file);

const response = try pbz.runConformanceDynamic(allocator, &registry, .{
    .payload = .{ .json_payload = "{\"id\":7}" },
    .requested_output_format = .protobuf,
    .message_type = "Event",
    .test_category = .json_test,
});
defer allocator.free(response);
```

## Type registry

Use `pbz.Registry` to register multiple parsed files and resolve message/enum
types by absolute or scoped names. Registration rejects duplicate fully-qualified
type symbols, conflicting extension names/numbers for the same extendee, and
extension definitions that violate imported `ExtensionRangeOptions.declaration`
metadata:

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

The current JSON support handles present fields from dynamic messages, optional
always-print primitive/repeated/map defaults, quoted 64-bit integers, bytes as
standard/URL-safe base64, repeated fields as arrays, maps as JSON objects, enum
names/numbers including unknown numeric enum values, default lowerCamelCase field names, null-as-absent parsing, and
nested messages recursively. Duplicate field appearances, including proto field
name plus lowerCamelCase/`json_name` alternate spellings, use protobuf JSON's
last-value-wins parsing behavior; `parseJsonAllocWithRegistry` resolves imported
message and enum field types through a `Registry`, `stringifyJsonAllocWithRegistry`
uses the same registry to print imported enum names/defaults, and ignore-unknown parsing
also skips unknown enum names for local and imported enum fields.
Use `parseJsonInitializedAlloc` / `parseJsonInitializedAllocWithRegistry` when
proto2 or editions legacy-required data must be validated recursively before the
parsed dynamic message is returned, including expanded `Any` payloads.

## Well-known types

`pbz.Timestamp` provides basic `google.protobuf.Timestamp` wire and JSON helpers:

```zig
const ts = pbz.Timestamp{ .seconds = 1_577_836_800, .nanos = 123_000_000 };
const json_ts = try ts.jsonStringifyAlloc(allocator);
defer allocator.free(json_ts);

const d = pbz.Duration{ .seconds = -3, .nanos = -250_000_000 };
const mask = pbz.FieldMask{ .paths = &.{"foo_bar"} };
var owned_mask = try mask.cloneOwned(allocator);
defer owned_mask.deinit(allocator);

var object = try pbz.Struct.jsonParse(allocator,
    \\{"enabled":true,"items":[null,"zig"]}
);
defer object.deinit(allocator);
var owned_object = try object.cloneOwned(allocator);
defer owned_object.deinit(allocator);
const object_wire = try object.encode(allocator);
defer allocator.free(object_wire);

var packed = try pbz.Any.packBytes(allocator, "demo.Payload", object_wire);
defer packed.deinit(allocator);
if (!packed.isType("demo.Payload")) return error.TypeMismatch;

var string_wrapper = try pbz.StringValue.jsonParseOwned(allocator, "\"zig\"");
defer string_wrapper.deinit(allocator);
var packed_string = try pbz.Any.packEncoded(allocator, "google.protobuf.StringValue", string_wrapper);
defer packed_string.deinit(allocator);
var unpacked_string = try packed_string.unpackEncodedOwned(pbz.StringValue, allocator, "google.protobuf.StringValue");
defer unpacked_string.deinit(allocator);
```

`pbz.Any` also provides `packDynamic` / `unpackDynamic` helpers, including
initialized variants, for reflection workflows backed by `DynamicMessage`; registry-aware
variants use the dynamic message descriptor's owning-file features when packing or unpacking imported payloads.

## TextFormat support

Dynamic messages can be formatted and parsed as protobuf TextFormat-style text:

```zig
const text_bytes = try pbz.formatTextAlloc(allocator, &file, &msg, .{});
defer allocator.free(text_bytes);

var parsed_text_msg = try pbz.parseTextAlloc(allocator, &file, descriptor, text_bytes);
defer parsed_text_msg.deinit();
```

Use `parseTextAllocWithRegistry` when parsing TextFormat that contains proto2
extension references such as `[demo.ext_field]` or imported message/enum
fields; use `formatTextAllocWithRegistry` / `formatTextWithRegistry` when
formatting imported enum names. Duplicate singular message/group fields are
merged using protobuf message merge semantics, while repeated fields append and
oneof fields replace the selected arm. Formatting dynamic messages with
extension values emits the same bracketed field-name form. Numeric unknown
fields are formatted and parsed using their field number, for example
`100: 123`, `101: "raw-bytes"`, or `102 { 103: 1 }`.
Use `parseTextInitializedAlloc` / `parseTextInitializedAllocWithRegistry` for
the same parsing behavior plus recursive required-field validation.

## Conformance helpers

`pbz.ConformanceRequest` and `pbz.ConformanceResponse` provide basic wire
structures and a dynamic-message runner for integrating with protobuf conformance-style runners,
including safe handling for unknown request enum values, deterministic registry-aware protobuf output,
registry-aware parsing/printing for imported JSON/Text message and enum types, and parse errors that identify missing proto2 required field paths when available.

## Protoc plugin helpers

`pbz.CodeGeneratorRequest` and `pbz.CodeGeneratorResponse` provide the basic
wire types needed to build protoc-style generators, including compiler version,
source-retention descriptor request fields, response feature masks, edition
support bounds, insertion points, and generated-code metadata payload passthrough
or structured `GeneratedCodeInfo` annotations. The installed `protoc-gen-pbz` executable reads a raw `CodeGeneratorRequest`
from stdin and writes a `CodeGeneratorResponse` to stdout.
`pbz.generatePluginResponseFromRequest`, `pbz.generatePluginResponseFromRequestBytes`,
`pbz.runPluginRequest`, and `pbz.runPluginRequestBytes` honor `file_to_generate`, emit only
requested files by default, parse `paths=source_relative`,
`include_imports`/`emit_imports`, `generated_info`/`annotate_code`, `pbz_import`/`runtime_import`, `output_suffix`/`strip_proto_ext`, and `json`/`text_format` parameters, report encoded plugin errors for
missing requested names or invalid parameters, emit structured
`GeneratedCodeInfo` annotations for generated files, top-level symbols, nested messages/enums, fields, and enum values, and still build a registry
from every `proto_file` descriptor so generated imports can resolve cross-file
message/enum references.
`pbz.generateZigFile` emits
a starter Zig typed scalar/repeated-scalar/enum/message-payload/map skeleton with AST syntax validation with field constants, fields, init, encode with proto3 default elision, and basic decode methods including repeated scalar/enum/message payload and map storage, plus required validation and optional/required/oneof presence flags and oneof tagged union mapping for parsed descriptors.
Generated files expose `proto_package`, `proto_syntax`, and an `imports`
namespace that maps imported `.proto` paths to their generated `.pb.zig` module
aliases while preserving import kind/path metadata.
Generated message structs also expose per-field metadata structs (`*_field`)
with protobuf field number, name/json_name, cardinality, kind, raw type_name
including imported message/enum names, Zig storage type, presence, default text,
packed status, map key/value metadata, generated `type_ref` aliases for same-file, direct-imported,
or transitive-public imported message fields, and generated `enum_ref` aliases for enum
fields/map enum values when `generateZigFileWithRegistry` is used. They include generated field accessors (`hasField_*`,
`getField_*`, `getOrDefaultField_*`, `setField_*`, `clearField_*`, repeated/map
`appendField_*` / `appendAllField_*` / `replaceField_*` helpers, oneof-arm accessors, and `cloneOwned` / `decodeOwned` / `decodeOwnedInitialized` for deep-copying strings/bytes/message payloads/maps/unknowns into owned storage) while keeping oneof storage as a
Zig `union(enum)`. Same-file message/group payload fields additionally expose
`setMessageField_*` / `getMessageField_*` / `decodeMessageField_*` and repeated message batch helpers that
encode/decode the underlying payload bytes through same-file, direct-imported, or transitive-public imported generated message types.
`pbz.generateZigFileWithRegistry` additionally resolves message and enum fields
through a `Registry`: direct and transitive-public imported message fields get module type refs/accessors,
direct and transitive-public imported message fields participate in generated JSON and TextFormat stringify/parse for singular, repeated, map, and oneof payloads; and direct or transitive-public imported enum fields are treated as enum scalars for generated wire, JSON/TextFormat, metadata, closed-enum checks, and map/oneof handling.
For `service` declarations, generated files include only a `services` namespace
with service/method metadata, streaming flags, and registry-aware
`input_type_ref` / `output_type_ref` aliases where request/response messages can
be resolved. RPC transport, `Handler`/`Client` stubs, dispatch adapters, and
client/server call helpers are intentionally out of scope for this library.
For proto2 extension declarations, generated files also expose an `extensions`
namespace containing per-extension metadata constants (`number`, `extendee`,
`cardinality`, `value_type`, `zig_type`, `has_default`, and `default_value`)
plus registry-aware `extendee_type_ref` / `value_type_ref` aliases, generated
`value_enum_ref` aliases for enum extension values, typed `default_value_zig`,
`write`/`writeAll`, `decodeValue` / `decodeAppend`, and
typed enum extension get/set/default/repeated-batch facades including cross-file `*On` variants plus
`hasOn` / `getOn` / `setOn` / `clearOn` style facades so applications can
encode/decode extension values or wire them into dynamic registries and custom
typed wrappers. Extension metadata
also emits `encodeRaw`, `appendToUnknown`, `decodeRaw`,
`decodeAllRaw`, `decodeFromUnknownFieldsAlloc` / `decodeAllFromUnknown`, and
`decodeFirstFromUnknown` helpers with strict trailing-data checks so typed message wrappers can shuttle proto2
extension payloads through their preserved unknown field storage; repeated
extensions additionally expose `encodeAllRaw` and `decodeAppendRaw`; batch unknown append stores expanded values one field at a time unless the extension is packed, skips empty packed batches, and repeated packable extensions honor resolved packed encoding with `decodePackedRaw` support
for packed raw payloads.
Extensions of `message_set_wire_format` messages emit MessageSet item groups
from their generated `write` helper and expose a `decodeMessageSetItem` helper
with type-id validation for extracting matching item payloads.
Generated message structs provide `encodeInitialized`, `decodeInitialized`, and
`jsonParseInitialized` wrappers that call recursive required validation before returning initialized proto2 data,
including generated message payload fields and map message values when their types are available.
They also expose `missingRequiredFieldName` and `missingRequiredFieldPath` for
callers that want direct or nested missing required field diagnostics before
handling `error.MissingRequiredField`.
Packable repeated scalar and enum fields emit packed wire format when resolved
as packed, generated decoders accept both packed and expanded input, and generated
`encodeDeterministic` emits fields by number, sorts map entries by key, recursively re-encodes available generated message/group/map-message payloads deterministically, and
orders preserved unknown fields by field number/wire type/raw bytes for stable
deterministic output.
Generated message structs include a `mergeFrom` helper and generated decoders
merge duplicate singular message/group payload fields while preserving repeated
append, oneof replacement semantics, and unknown fields. They also expose
`unknownFieldCount`, `unknownFields`, `unknownFieldCountByNumber`,
`hasUnknownFieldNumber`, `unknownFieldsByNumberAlloc`,
`appendUnknownRaw`, `clearUnknownFieldsByNumber`, and `clearUnknownFields`
helpers for callers that need to inspect, replace, delete, or carry forward
proto2 extensions/unknown data in typed wrappers. Generated extension metadata
also exposes `hasInUnknown`, `countInUnknown`, `clearFromUnknown`, and
`replaceInUnknown` for checking, counting, removing, or replacing that extension
number in a typed message's unknown storage; repeated extensions additionally
provide `appendAllToUnknown` / `replaceAllInUnknown` batch helpers.
For same-file proto2 extensions, extendee generated message structs also expose
message-level `hasExtension_*`, `countExtension_*`, `getExtension_*`,
`getExtensionOrDefault_*` for scalar/enum defaults,
`setExtension_*`/`addExtension_*`/`appendExtension_*`, `replaceExtension_*`, and
`clearExtension_*` facades over the same unknown/raw extension storage; when an
extension value type is a same-file generated message, additional
`setExtensionMessage_*` / `getExtensionMessage_*` helpers encode/decode the
message payload for callers, with repeated message extensions also exposing
`addExtensionMessage_*`, `appendExtensionMessages_*`, `replaceExtensionMessages_*`,
and `getExtensionMessages_*` helpers.
Generated message structs also include basic `jsonStringify`, `jsonStringifyAlloc`,
and `jsonParse` methods for scalar/enum fields, repeated scalar/enum fields,
scalar/enum/message map fields, encoded message payload fields when their generated types
are available, lowerCamelCase/json_name field names, presence-aware
optional fields, bytes/base64, proto2 group payload fields, and scalar/enum/message oneof arms. Generated enum JSON
stringify emits enum names when known and falls back to numbers for unknown values.
Generated JSON parsers use protobuf JSON last-value-wins behavior for duplicate
fields or alternate spellings, treat `null` as clearing the previous value,
validate string/map-string output as UTF-8, and replace previous repeated/map slices safely. Generated JSON stringify/parse also
handles same-file proto2 extension keys such as `"[demo.ext]"` or `"[ext]"`,
storing parsed scalar, enum, message, and repeated extension values in preserved
unknown/raw extension storage and emitting known same-file extension values back
as qualified bracketed JSON keys. Generated messages expose
`JsonStringifyOptions` / `jsonStringify*WithOptions` for enum-name versus
numeric enum output, proto field-name preservation, and always-printing
primitive/repeated-message/repeated-scalar/map defaults including absent
non-required explicit-presence scalar/enum defaults, plus `JsonParseOptions` /
`jsonParseWithOptions` / `jsonParseInitializedWithOptions`, with JSON
stringify/parse options propagated into nested generated message handling;
`ignore_unknown_fields` also skips unknown enum JSON values for scalar,
repeated, map value, oneof, and same-file extension enum fields.
Generated `formatTextAlloc` / `formatTextWithAllocator` helpers emit basic
TextFormat for scalar, enum-name, repeated, map, message payload, proto2 group,
same-file proto2 extension values recovered from preserved unknown/raw fields,
protobuf-escaped string/bytes values with UTF-8 validation for generated string/map-string formatting, numeric unknown varint/bytes-escaped string/group/fixed fields, and oneof fields; generated
messages expose `TextFormatOptions` plus `formatText*WithOptions` for enum-name
versus numeric enum output, with options propagated into nested generated message
formatting; generated messages also expose `TextParseOptions` plus
`parseTextWithOptions` / `parseTextInitializedWithOptions`, with
`ignore_unknown_fields` propagated into nested generated message parsing and
unknown enum TextFormat values skipped for scalar, repeated, map value, oneof,
and same-file extension enum fields;
generated
`parseText` / `parseTextInitialized` cover basic line-oriented scalar, enum,
repeated, scalar/enum/message map with default key/value fill for omitted map-entry members, scalar/enum oneof input, plus same-file proto2
extension references such as `[demo.ext]` or `[ext]` stored as preserved
unknown/raw extension fields, message/group block payloads with duplicate
singular message/group merge semantics when their generated types are available,
`{}` or `<>` block delimiters with optional colon, proto/lowerCamel/`json_name`
field spellings, adjacent quoted string literal concatenation, common quoted
string escapes including C-style control, hex/octal bytes, decimal/hex/octal
integer input, closed-enum validation, numeric unknown varint/string/group
preservation, float `nan`/`inf` spellings, `#` line comments outside quoted
strings including nested blocks, common semicolon/comma separators including
multiple simple fields and inline `{}` / `<>` block payloads on one physical
line, and `features.utf8_validation` enforcement for string/map-string values.
For proto2 schemas, generated scalar and enum fields are initialized with explicit
`[default = ...]` option values while retaining separate presence flags.

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

For schemas that still hold imported enum fields as unresolved message-looking
type names, use `encodeFileDescriptorProtoWithRegistry` or
`encodeFileDescriptorSetWithRegistry` so descriptor output can emit enum field
types and enum default names with cross-file visibility.

The current descriptor support covers core file/message/import/field/enum/service
metadata, proto2 group descriptors and nested group messages, map-entry/proto3-optional descriptors, packed field options, enum
default names on encode including registry-aware imported enum fields/defaults, typed scalar/enum default values on decode including unsigned 64-bit maxima, message reserved/extension upper-bound validation including MessageSet ranges, and FileDescriptorSet-level duplicate file-name, cross-file symbol, extension-conflict/declaration, type-reference, and imported-enum-default validation,
file/message/enum/enum-value/field/oneof/service/method uninterpreted options plus selected known options (message/enum deprecation flags, field ctype/jstype/lazy/weak/redaction/retention/targets, enum-value/service/method deprecation/idempotency), including multi-part custom option names with extension name parts, decoded file syntax/edition/dependency metadata, file/message/field number/label/type-name,
oneof index/name/field-contiguity validation, enum allow_alias misuse, enum descriptor validation,
service/method validation, proto2 MessageOptions.message_set_wire_format,
structured SourceCodeInfo location path/span/comments including parser-generated basic declaration/option/field/field-option/extension-field/oneof/extension-range/extension-range-option/reserved/enum-value/method locations plus leading/trailing/detached line and block comments, ExtensionRangeOptions
declarations/verification/features with parser-side consistency checks,
structured GeneratedCodeInfo annotations, and edition feature metadata.

## Build and test

```sh
zig build test
```

The project is formatted and validated with Zig 0.16.0.
