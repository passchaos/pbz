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
  - proto2/proto3/editions syntax flags and expanded FeatureSet defaults
  - proto2 required/optional/repeated cardinality plus proto3/editions required rejection, enum defaults, packed override handling, structured FeatureSet options, and FieldOptions edition default / feature support metadata
- Multi-file registry and loader
  - package/import-aware lookup for messages/enums/extensions across FileDescriptor values with duplicate type/extension conflict detection and cross-file extension declaration validation
  - in-memory and filesystem source tree loaders that recursively parse imports
- `.proto` parser
  - `syntax = "proto2"` plus package/import/option declarations
  - messages, nested messages, groups, enums, oneofs, services/rpc, extensions, reserved ranges, field-number, reserved/extension/enum range conflicts, extension extendee/range/label/duplicate checks, duplicate-field/oneof/type/service/rpc-symbol, oneof field-shape, and enum validation including allow_alias
  - proto2 MessageSet declaration validation for `message_set_wire_format`, extension ranges, and optional-message extension shape
  - extension range options for `declaration`, `verification`, and range-local `features.*`; declaration-scope `features.*` across file/message/field/oneof/enum/enum-value/service/method; plus field-level `edition_defaults` / `feature_support` aggregate parsing, with declaration/extension consistency validation
  - services/rpc declarations and custom option names including `(ext).field`
  - string/bytes literal escape decoding and adjacent literal concatenation
  - basic SourceCodeInfo path/span generation for file-level syntax/package/import, top-level and nested message/enum/service declarations, fields, oneofs, extension/reserved ranges, reserved names, enum values, and RPC methods, including adjacent/detached line leading comments plus same-line line/block trailing comments
  - proto2 field default validation for scalar/string/bytes/enum defaults, with proto3/repeated/message invalid-default rejection
  - packed field option validation for repeated packable scalar/enum fields, with editions rejecting legacy `[packed]` and `group` syntax in favor of features and validating implicit-presence default/closed-enum constraints
- Dynamic message runtime
  - scalar encoding/decoding for all protobuf scalar wire types
  - proto2 strings/bytes, required-field validation, missing required field path reporting, encode/decodeInitialized helpers, repeated packed fields
  - proto2 MessageSet wire-format encode/decode for known registry extensions plus unknown item preservation
  - proto2/closed-enum unknown numeric values are preserved as unknown fields for singular, repeated, packed repeated, and enum map entries, including imported enums resolved through Registry
  - proto3 optional fields, default-packed repeated numeric fields, and map fields
  - editions `features.repeated_field_encoding` packed/expanded behavior, `features.message_encoding` delimited/length-prefixed message wire behavior, enum-level `features.enum_type` open/closed override behavior, string UTF-8 validation via `features.utf8_validation`, and implicit/explicit/legacy-required `features.field_presence` behavior
  - descriptor encode/decode for common `FileOptions` fields, `MessageOptions.map_entry`, `FeatureSet` on file/message/field/oneof/enum/enum-value/service/method/extension-range options, `FeatureSetDefaults` with closest-edition lookup helpers, plus `FieldOptions.edition_defaults` and `FieldOptions.feature_support`, preserving protobuf edition feature metadata as structured schema fields
  - nested message and group round-trips, including protobuf merge semantics for duplicate singular message/group fields, imported message and enum decode through Registry, plus registry-aware encode helpers for imported enum scalar/repeated/map fields
  - unknown field preservation/querying, extension encoding/decoding with Registry, registry-aware initialized encode/decode helpers, deterministic encoding including map key ordering, and recursive message merging
- JSON support
  - dynamic message stringify/parse for scalars, 64-bit numeric strings, bytes/base64, repeated fields, maps, enums including editions open/closed enum numeric validation, nested messages, initialized parse helpers with recursive required validation, and registry-aware imported message/enum parsing plus imported enum-name stringify
- Well-known types
  - basic google.protobuf.Timestamp, Duration, FieldMask, Any, Empty, Struct/Value/ListValue, and wrapper wire/JSON parse/stringify helpers with validation plus dynamic JSON mapping, including Any expanded payload JSON, Timestamp timezone-offset parsing, Duration sign/range validation, wrapper null/default parsing and float special values, FieldMask path validation, and strict Empty object parsing
- Conformance helpers
  - basic ConformanceRequest decode, safe enum handling, ConformanceResponse encode, and dynamic runner with deterministic registry-aware protobuf output, registry-aware imported JSON/Text types, and missing-required path parse errors
- Protoc plugin and codegen helpers
  - CodeGeneratorRequest decode for file_to_generate, parameter, compiler_version, proto_file, and source_file_descriptors; CodeGeneratorResponse encode for error, supported_features, edition bounds, generated files, insertion points, and raw or structured generated_code_info; generated plugin responses advertise proto3 optional and editions support
  - Zig typed scalar/repeated-scalar/enum/message-payload/map skeleton with AST syntax validation generation
  - generated `proto_package`, `proto_syntax`, and import module aliases with import kind/path metadata
  - generated proto2 extension metadata structs with extension number, extendee, cardinality, protobuf value type, Zig value type strings, typed `write`/`writeAll` plus `decodeValue`/`decodeAppend` helpers, and MessageSet-aware write helpers
  - generated service metadata plus basic Handler/Client stub types for RPC payload dispatch
  - generated `encodeInitialized`/`decodeInitialized` helpers validate proto2 and editions legacy-required fields around typed encode/decode
  - generated `missingRequiredFieldName` / `missingRequiredFieldPath` helpers report direct and nested proto2 required-field failures
  - generated packed encode/decode for packable repeated scalar/enum fields, including proto2 `[packed = true]`
  - generated field declarations honor proto2 scalar/string/bytes/bool/float/enum defaults plus editions field-presence, message-encoding, and string UTF-8 validation features
  - generated typed JSON stringify/parse helpers plus basic TextFormat formatters/parsers for scalar, enum, repeated, map, message payload, proto2 group, and oneof fields; generated wire UTF-8 validation for string/map-string fields; and generated wire closed-enum validation for singular/repeated/map/oneof enum fields
- TextFormat support
  - dynamic message formatting/parsing for scalars, repeated fields, maps, enums including editions open/closed enum numeric validation plus registry-aware imported message/enum parsing and imported enum-name formatting, initialized parse helpers with recursive required validation, protobuf merge semantics for duplicate singular message/group fields, string UTF-8 validation via `features.utf8_validation`, nested messages, proto2 extension fields using `[ext.name]` including MessageSet extensions, numeric unknown fields and numeric unknown groups, `{}`/`<>` delimiters with optional colon, bool aliases, decimal/hex/octal integers, common separators, # comments, common string/bytes escapes, and adjacent string literal concatenation

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
uses the same registry to print imported enum names, and ignore-unknown parsing
also skips unknown enum names for local and imported enum fields.
Use `parseJsonInitializedAlloc` / `parseJsonInitializedAllocWithRegistry` when
proto2 or editions legacy-required data must be validated recursively before the
parsed dynamic message is returned.

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
or structured `GeneratedCodeInfo` annotations.
`pbz.generateZigFile` emits
a starter Zig typed scalar/repeated-scalar/enum/message-payload/map skeleton with AST syntax validation with field constants, fields, init, encode with proto3 default elision, and basic decode methods including repeated scalar/enum/message payload and map storage, plus required validation and optional/required/oneof presence flags and oneof tagged union mapping for parsed descriptors.
Generated files expose `proto_package`, `proto_syntax`, and an `imports`
namespace that maps imported `.proto` paths to their generated `.pb.zig` module
aliases while preserving import kind/path metadata.
For `service` declarations, generated files include a `services` namespace with
service/method metadata, an unimplemented `Handler` stub, and a `Client` wrapper
that dispatches serialized request/response payloads through a caller-provided
function pointer.
For proto2 extension declarations, generated files also expose an `extensions`
namespace containing per-extension metadata constants (`number`, `extendee`,
`cardinality`, `value_type`, and `zig_type`) plus typed `write`/`writeAll` and
`decodeValue`/`decodeAppend` helpers so applications can encode/decode extension
values or wire them into dynamic registries and custom typed wrappers.
Extensions of `message_set_wire_format` messages emit MessageSet item groups
from their generated `write` helper and expose a `decodeMessageSetItem` helper
for extracting matching item payloads.
Generated message structs provide `encodeInitialized`, `decodeInitialized`, and
`jsonParseInitialized` wrappers that call recursive required validation before returning initialized proto2 data,
including generated message payload fields and map message values when their types are available.
They also expose `missingRequiredFieldName` and `missingRequiredFieldPath` for
callers that want direct or nested missing required field diagnostics before
handling `error.MissingRequiredField`.
Packable repeated scalar and enum fields emit packed wire format when resolved
as packed, generated decoders accept both packed and expanded input, and generated
`encodeDeterministic` emits fields by number and sorts map entries by key.
Generated message structs include a `mergeFrom` helper and generated decoders
merge duplicate singular message/group payload fields while preserving repeated
append and oneof replacement semantics.
Generated message structs also include basic `jsonStringify`, `jsonStringifyAlloc`,
and `jsonParse` methods for scalar/enum fields, repeated scalar/enum fields,
scalar/enum/message map fields, encoded message payload fields when their generated types
are available, lowerCamelCase/json_name field names, presence-aware
optional fields, bytes/base64, proto2 group payload fields, and scalar/enum/message oneof arms. Generated enum JSON
stringify emits enum names when known and falls back to numbers for unknown values.
Generated JSON parsers use protobuf JSON last-value-wins behavior for duplicate
fields or alternate spellings, treat `null` as clearing the previous value, and
replace previous repeated/map slices safely.
Generated `formatTextAlloc` / `formatTextWithAllocator` helpers emit basic
TextFormat for scalar, enum-name, repeated, map, message payload, proto2 group,
and oneof fields; generated `parseText` / `parseTextInitialized` cover basic
line-oriented scalar, enum, repeated, scalar/enum/message map, scalar/enum oneof
input, plus message/group block payloads with duplicate singular message/group
merge semantics when their generated types are available, `{}` or `<>` block
delimiters, proto/lowerCamel/`json_name` field spellings, common quoted string
escapes, decimal/hex/octal integer input, closed-enum validation, float
`nan`/`inf` spellings, line comments, and common semicolon/comma separators.
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

The current descriptor support covers core file/message/import/field/enum/service
metadata, proto2 group descriptors and nested group messages, map-entry/proto3-optional descriptors, packed field options, enum
default names on encode, typed scalar/enum default values on decode,
file/message/enum/enum-value/field/oneof/service/method uninterpreted options plus selected known options (message/enum deprecation flags, field ctype/jstype/lazy/weak/redaction/retention/targets, enum-value/service/method deprecation/idempotency), including multi-part custom option names with extension name parts, decoded file syntax/edition/dependency metadata, file/message/field number/label/type-name,
oneof index/name validation, enum allow_alias, enum descriptor validation,
service/method validation, proto2 MessageOptions.message_set_wire_format,
structured SourceCodeInfo location path/span/comments including parser-generated basic declaration/field/oneof/extension-range/reserved/enum-value/method locations plus leading/trailing/detached line and block comments, ExtensionRangeOptions
declarations/verification/features with parser-side consistency checks,
structured GeneratedCodeInfo annotations, and edition feature metadata.

## Build and test

```sh
zig build test
```

The project is formatted and validated with Zig 0.16.0.
