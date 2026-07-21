# pbz examples

Run all examples with:

```sh
zig build examples
```

`zig build test` also runs the examples so public snippets stay in sync with the
library API.

- `wire.zig` — low-level wire writer/reader usage.
- `dynamic_message.zig` — runtime schema parsing, dynamic fields, repeated/map/oneof handling, deterministic encode/decode.
- `json_text.zig` — dynamic JSON and TextFormat parse/format round-trips.
- `registry_loader.zig` — `MemorySourceTree` plus filesystem `loadDir`,
  recursive imports, registry lookup, and registry-backed dynamic JSON output.
- `dynamic_groups.zig` — dynamic proto2 group fields, repeated groups, JSON and
  TextFormat round-trips, singular group merge semantics, and unknown group
  preservation.
- `dynamic_editions_features.zig` — dynamic protobuf editions features:
  explicit/implicit/legacy-required presence, packed/expanded repeated scalars,
  delimited message encoding, relaxed UTF-8, and closed enum preservation.
- `dynamic_defaults.zig` — dynamic proto2 default values, has/getOrDefault
  behavior, enum-name helpers, JSON null reset, TextFormat parsing, and imported
  enum defaults resolved through a registry.
- `dynamic_public_imports.zig` — dynamic registry public-import chain lookup plus JSON/binary round-trips.
- `dynamic_weak_imports.zig` — dynamic loader/registry behavior for present
  and missing proto2 weak imports, including descriptor-set, binary, JSON, and
  TextFormat workflows.
- `dynamic_reserved_text.zig` — reserved field names/ranges in dynamic schemas,
  descriptor round-trips, and TextFormat's reserved-name ignore semantics.
- `dynamic_messageset.zig` — dynamic proto2 MessageSet encode/decode,
  JSON/TextFormat mapping, payload-before-type-id parsing, and unknown item
  preservation.
- `descriptors_codegen.zig` — descriptor encode/decode, source-code info,
  uninterpreted custom options, service/method options, descriptor sets, direct
  codegen, plugin request generation, and generated-code info annotations.
- `reflection_facade.zig` — reflection facade over registry descriptors and
  dynamic messages, including typed get/set/add/clear helpers, repeated fields,
  all scalar families, maps, oneof inspection, imported message fields, binary,
  and JSON round-trips.
- `build_codegen.zig` — generated module imported from the `generateProtobuf`
  build.zig helper; run with `zig build build-codegen-smoke`.
- `generated_types.zig` — C++/Rust-style use of the checked-in generated module `generated/person.pb.zig` from `proto/person.proto`, including generated JSON integer numeric-exponent parsing.
- `generated_performance.zig` — generated fastest-path APIs: trusted buffer encode, borrowed length-delimited slices/views, packed fixed-width views/slices, packed varint iterators, and known-schema decode reuse.
- `generated_advanced.zig` — generated package namespaces, enum helpers, typed nested message fields, typed map message values, oneof union storage, JSON/TextFormat round-trips, and service metadata from `proto/advanced.proto`.
- `generated_required.zig` — generated proto2 required-field initialization gates for binary, deterministic binary, JSON, and TextFormat from `proto/required.proto`.
- `generated_defaults.zig` — generated proto2 scalar/string/bytes/enum default values and has-bit behavior from `proto/defaults.proto`.
- `generated_extensions.zig` — generated proto2 extension metadata and typed extension accessors from `proto/extensions_generated.proto`.
- `generated_identifiers.zig` — generated quoting for proto names that collide with Zig keywords, primitive names, and test declarations from `proto/identifiers.proto`.
- `generated_enum_alias.zig` — generated enum alias constants, canonical output, and alias input parsing from `proto/enum_alias.proto`.
- `generated_json_names.zig` — generated explicit `json_name` stringify/parse behavior from `proto/json_names.proto`.
- `generated_messageset.zig` — generated proto2 MessageSet extension helpers from `proto/messageset.proto`.
- `generated_map_keys.zig` — generated non-string map key JSON/TextFormat behavior from `proto/map_keys.proto`.
- `generated_nested_types.zig` — generated nested message/enum type references and round-trips from `proto/nested_types.proto`.
- `generated_unpacked.zig` — generated repeated scalar `[packed = false]` encoding plus packed/unpacked merge parsing from `proto/unpacked.proto`.
- `generated_public_imports.zig` — generated public-import re-export type references from `proto/public_app.proto` / `proto/public_mid.proto` / `proto/public_leaf.proto`.
- `generated_proto3_optional.zig` — generated proto3 optional fields exposed as
  plain fields plus `has_*` presence bits instead of protoc synthetic oneofs.
- `generated_merge_semantics.zig` — generated decode merge/last-wins semantics for singular messages, repeated fields, maps, oneof, and decode reuse.
- `generated_clone_owned.zig` — generated deep-clone ownership handoff for nested messages, maps, oneof payloads, and raw unknown fields.
- `generated_unknown_mutation.zig` — generated unknown-field append/query/clear APIs over exact raw-field storage.
- `generated_closed_enum.zig` — generated proto2 closed-enum unknown numeric preservation from `proto/closed_enum.proto`.
- `generated_imports.zig` — multi-file generated modules using proto imports with typed imported singular, repeated, map value, and oneof message fields from `proto/imported_app.proto` / `proto/imported_common.proto`.
- `generated_groups.zig` — typed proto2 group fields, repeated groups, oneof group message arms, and JSON/TextFormat round-trips from `proto/groups.proto`.
- `generated_recursive.zig` — generated self-recursive message usage from `proto/recursive.proto`, including raw-payload singular recursion, typed repeated recursion, and decode recursion-limit enforcement.
- `generated_streaming.zig` — generated service client/handler adapters over an in-memory transport covering unary, client-streaming, server-streaming, and bidirectional-streaming RPC shapes from `proto/streaming.proto`.
- `ownership_patterns.zig` — generated and dynamic arena-style ownership, clone-to-long-lived allocator, and generated decode reuse patterns.
- `well_known_types.zig` — Timestamp, Duration, FieldMask, Empty,
  Struct/Value/ListValue, scalar wrappers, bytes wrappers, and Any including
  embedded WKT JSON values.
- `any_dynamic.zig` — custom dynamic-message `Any` pack/unpack with registry lookup and required-field validation.
- `any_type_url.zig` — custom `Any` type URL prefixes, leading-dot type names, JSON parse, and type mismatch behavior.
- `proto2_extensions.zig` — proto2 extension parsing through TextFormat/JSON,
  repeated message extensions with required-field validation, extension range
  declarations/verification, descriptor round-trips, and preserved unknown
  storage.
- `conformance.zig` — conformance-style JSON-to-protobuf conversion.
