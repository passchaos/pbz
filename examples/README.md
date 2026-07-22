# pbz examples

Run all examples with:

```sh
zig build examples
```

`zig build test` also runs the examples so public snippets stay in sync with the
library API.

- `wire.zig` — low-level wire writer/reader usage.
- `dynamic_message.zig` — runtime schema parsing, dynamic fields,
  repeated/map/oneof handling, field, oneof presence, and map-entry query/clear helpers,
  deterministic encode/decode, decode reuse clearing semantics, and dynamic
  unknown-field query/mutation APIs.
- `json_text.zig` — dynamic JSON and TextFormat parse/format round-trips.
- `dynamic_json_options.zig` — dynamic JSON parse/stringify options:
  ignore-unknown, proto-name fields, always-print defaults, enum-number output,
  proto-name input aliases, and duplicate-key last-wins parsing.
- `dynamic_text_options.zig` — dynamic TextFormat options: enum-number output,
  custom indentation, unknown-field printing, and numeric enum input.
- `registry_loader.zig` — `MemorySourceTree` plus filesystem `loadDir`,
  recursive imports, typed file option/import/dependency metadata and import-kind/option-dependency reflection lookup, import-chain reflection lookup/accessors, message/service/method registry lookup, and
  registry-backed dynamic JSON output. Also shows registry duplicate-symbol
  protection for descriptors assembled directly rather than parsed from text.
- `dynamic_groups.zig` — dynamic proto2 group fields, repeated groups, JSON and
  TextFormat round-trips, singular group merge semantics, and unknown group
  preservation.
- `dynamic_editions_features.zig` — dynamic protobuf editions features:
  explicit/implicit/legacy-required presence, packed/expanded repeated scalars,
  delimited message encoding, relaxed UTF-8, reflection file/message/field/oneof/enum/enum-value/service/method/extension-range feature metadata, and closed enum preservation.
- `dynamic_defaults.zig` — dynamic proto2 default values, has/getOrDefault
  behavior, enum-name helpers, JSON null reset, TextFormat parsing, and imported
  enum defaults resolved through a registry.
- `dynamic_enum_alias.zig` — dynamic enum alias parsing, reflection alias
  metadata lookup, and canonical JSON/TextFormat output for singular, repeated,
  and map enum fields.
- `dynamic_public_imports.zig` — dynamic registry public-import chain lookup plus JSON/binary round-trips.
- `dynamic_weak_imports.zig` — dynamic loader/registry behavior for present
  and missing proto2 weak imports, including reflection missing-weak lookup/enumeration metadata, descriptor-set, binary, JSON, and
  TextFormat workflows.
- `dynamic_reserved_text.zig` — reserved field names/ranges in dynamic schemas,
  descriptor round-trips, and TextFormat's reserved-name ignore semantics.
- `dynamic_messageset.zig` — dynamic proto2 MessageSet encode/decode,
  reflection MessageSet wire-format metadata, JSON/TextFormat mapping, payload-before-type-id parsing, and unknown item
  preservation.
- `descriptors_codegen.zig` — descriptor encode/decode, source-code info lookup/enumeration/accessors,
  uninterpreted custom options, service/method options, descriptor sets, direct
  codegen, plugin request generation, and generated-code info annotation lookup/accessors.
- `reflection_facade.zig` — reflection facade over registry descriptors and
  dynamic messages, including typed get/set/add/get-default/clear helpers, field-value record accessors and dynamic/default value tags,
  present-field listing, type-checked writes, typed repeated scalar access/replacement across all scalar families, repeated enum descriptor/name lookup, repeated field replacement/reordering/removal, all scalar families,
  typed singular/repeated message/group creation/access/mutation including typed repeated element access, field scalar/kind/declared-type/cpp-type-name/cpp-type/cardinality/optional-keyword/weak/lazy/debug-redact/ctype/jstype/retention/targets/wire-type/encoded-wire-type/direct-containing/containing/extendee/oneof/index metadata, lowercase/camelcase/JSON field-name lookup/output, maps, map-entry descriptor metadata, map key/value metadata, map size/key/value/entry enumeration, map key lookup, repeated/map enum-name lookup, JSON-name field lookup/output/explicitness, explicit/effective typed default metadata and enum default value/name lookup, field presence/packing/packed-override/reserved range/name lookup/enumeration/accessors
  metadata, message/enum legacy-json-conflict metadata, feature-support lifecycle metadata/accessors, ordered file/message/enum/service descriptor enumeration/index lookup, file/message-local descriptor/value lookup, descriptor name/full-name/containing-type/value-owner direct identity and placeholder metadata lookup, file metadata/import-chain lookup, enum descriptor/value lookup and enum-name writes, oneof field enumeration plus descriptor-direct oneof field access and oneof
  lookup/fields/presence/inspection/clearing plus real-vs-synthetic proto3-optional oneof/index metadata, imported message fields, descriptor option slices and typed option lookup,
  file-local service lookup, service/method owner/type/deprecation metadata, and extension descriptor lookup, dynamic merge/copy/clone, unknown-field query/mutation,
  required-field initialization checks, unknown-field record accessors, binary, and JSON round-trips.
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
- `generated_streaming.zig` — generated service/method metadata (including
  deprecated/idempotency options) plus client/handler adapters over an in-memory
  transport covering unary, client-streaming, server-streaming, and
  bidirectional-streaming RPC shapes from `proto/streaming.proto`.
- `ownership_patterns.zig` — generated and dynamic arena-style ownership,
  clone-to-long-lived allocator handoff for generated and dynamic messages, and
  generated decode reuse patterns.
- `well_known_types.zig` — Timestamp, Duration, FieldMask, Empty,
  Struct/Value/ListValue, scalar wrappers, bytes wrappers, and Any including
  embedded WKT JSON values plus descriptor well-known-type reflection.
- `any_dynamic.zig` — custom dynamic-message `Any` pack/unpack with registry lookup and required-field validation.
- `any_type_url.zig` — custom `Any` type URL prefixes, leading-dot type names, JSON parse, and type mismatch behavior.
- `proto2_extensions.zig` — proto2 extension parsing through TextFormat/JSON,
  repeated message extensions with required-field validation, extension range
  bounds/verification/declaration metadata, reflection extension/range/declaration/full-name/extendee/scope/containing-type lookup/enumeration/index and lowercase/camelcase name lookup, descriptor
  round-trips, and preserved unknown storage.
- `conformance.zig` — conformance-style JSON-to-protobuf conversion.
