# pbz C++/Rust/Go comparison coverage

This file is the working audit checklist for the goal of making pbz exceed the
commonly used C++ and Rust protobuf implementations in both generated-type
functionality and measured hot-path performance.

## Current success criteria

- Generated Zig code should be used in a C++/Rust-style workflow: compile `.proto`
  to concrete Zig message types, import the generated module, and work with
  package namespaces and plain Zig structs.
- Generated Zig should cover the protobuf feature surfaces exercised by the
  examples and benchmarks: scalar fields, strings/bytes, repeated fields, maps,
  nested messages, oneof, proto3 optional presence, proto2 groups/extensions,
  imports, enums, JSON, TextFormat, descriptors, services, and selected well
  known types.
- The fastest relevant public pbz path should beat Rust `prost`, Rust
  `quick-protobuf`, C++ protobuf, and Go protobuf for every parsed comparison row
  in `bench/summarize_compare.py`.
- Performance wins should come from public generated or runtime APIs rather than
  benchmark-only hand-written code wherever possible.
- Generated JSON parsing should avoid avoidable reserialization of nested
  `std.json.Value` subtrees; nested generated messages now parse directly from
  pre-parsed JSON values via `jsonParseValueWithOptions`.

## Completion audit against the broad project goal

The standing user goal is broader than any single benchmark increment:

> Continue optimizing pbz until it fully surpasses the C++ protobuf library; if
> the code structure is unreasonable, refactor it.

Do **not** treat this checklist as complete merely because a recent benchmark
run passed.  The project can only claim completion after each requirement below
has current, repository-verifiable evidence:

| Requirement | Current evidence | Audit status |
|---|---|---|
| Generated-code workflow is C++/Rust-style and ergonomic. | `examples/generated_types.zig`, `examples/generated_imports.zig`, `examples/generated_groups.zig`, `examples/generated_required.zig`, `examples/generated_defaults.zig`, `examples/generated_extensions.zig`, `examples/generated_identifiers.zig`, `examples/generated_enum_alias.zig`, `examples/generated_json_names.zig`, `examples/generated_messageset.zig`, `examples/generated_map_keys.zig`, `examples/generated_nested_types.zig`, `examples/generated_unpacked.zig`, `examples/generated_public_imports.zig`, `examples/generated_proto3_optional.zig`, `examples/generated_merge_semantics.zig`, `examples/generated_clone_owned.zig`, `examples/generated_unknown_mutation.zig`, `examples/generated_closed_enum.zig`, `examples/generated_recursive.zig`, `examples/generated_streaming.zig`, and `build.zig`'s `generateProtobuf` helper exercise checked-in and build-generated modules. | Covered for the examples in this repo; continue expanding when new schema shapes are added. |
| Generated/runtime functionality covers protobuf surfaces used by examples, benchmarks, and conformance. | `zig build check` runs library tests, examples, summarizer self-test, and conformance smoke; `examples/dynamic_editions_features.zig` covers dynamic protobuf editions feature interactions; `examples/dynamic_weak_imports.zig` covers present and missing proto2 weak-import loader behavior; `/tmp/pbz-upstream-conformance-after-textbytes-slices.log` records upstream Binary/JSON/TextFormat conformance with zero skips and zero unexpected failures. | Strong for current covered surfaces; not a proof of every possible protobuf edge case. |
| pbz beats C++ protobuf and other tracked baselines on every parsed row. | `/tmp/pbz-compare-current-cpu3.log` summarized by `/tmp/pbz-summary-current-cpu3.txt`; fail-on-loss summary ends with `All parsed cross-language rows are pbz wins.` | Covered for the 417 workloads currently tracked by `bench/summarize_compare.py`. |
| Performance wins come from public APIs, not benchmark-only one-offs. | `bench/summarize_compare.py` chooses public generated/runtime rows such as `encodeIntoAssumeCapacity`, `writeToAssumeCapacity`, `decodeKnownReuse`, field views/slices, packed iterators, and unknown-field sidecars; `examples/generated_performance.zig` demonstrates those APIs outside the benchmark harness. | Covered for the current matrix; new rows must keep using public APIs. |
| JSON parsing avoids avoidable nested reserialization. | Generated nested-message JSON parsers use `jsonParseValueWithOptions`; complex JSON and proto-name JSON rows are in the cross-language matrix. | Covered for generated nested-message paths exercised by the matrix. |
| Code structure remains maintainable. | Codegen/runtime helpers are grouped by generated API family; `bench/run_compare.sh` now has `PBZ_COMPARE_CPUSET` so noisy benchmark gating does not require ad-hoc command wrappers. | Ongoing.  Any newly identified awkward boundary should be refactored before claiming completion. |
| The comparison is not overclaimed beyond covered workloads. | "Remaining non-goals / open audit items" below records limits: finite workload matrix, non-vendored full conformance runner, API differences for C++ unknown-field decode, trusted `decodeKnownReuse`, and hardware-sensitive benchmark results. | Not complete.  These limits mean the broad goal remains active unless a future audit closes or explicitly scopes them. |

## Verification commands

Run the local generated/dynamic baseline:

```sh
zig build bench -Doptimize=ReleaseFast
```

Run the full cross-language comparison and fail on any parsed loss:

```sh
bench/run_compare.sh 2>&1 | tee /tmp/pbz-compare.log
python3 bench/summarize_compare.py /tmp/pbz-compare.log --fail-on-loss
```

If unrelated machine load makes per-row timings unstable, set
`PBZ_COMPARE_CPUSET` so every compared implementation runs on the same CPU set.
If `GOMAXPROCS` is unset, `bench/run_compare.sh` derives it from that CPU set
for the Go baseline:

```sh
PBZ_COMPARE_CPUSET=3 bench/run_compare.sh 2>&1 | tee /tmp/pbz-compare.log
```

The latest accepted full-gate evidence at the time this checklist was updated
is `/tmp/pbz-compare-current-cpu3.log` summarized by
`/tmp/pbz-summary-current-cpu3.txt`. The fail-on-loss summary gate:

```sh
python3 bench/summarize_compare.py /tmp/pbz-compare-current-cpu3.log --fail-on-loss
```

ended with:

```text
All parsed cross-language rows are pbz wins.
```

The same audit pass also kept these functional coverage gates green:

```sh
zig build check
zig build test
zig build examples
zig build check-generated-examples
zig build conformance-smoke
python3 bench/summarize_compare.py --self-test
git diff --check
```

## Cross-language benchmark matrix

`bench/summarize_compare.py` currently tracks 417 workloads. The parsed baselines
include:

- Rust `prost`
- Rust `quick-protobuf`
- C++ protobuf generated binary encode/decode plus JSON/TextFormat util paths
- Go protobuf generated binary encode/decode plus protojson/prototext paths

The matrix includes:

- binary encode/decode
- deterministic binary encode
- unknown-field count-by-number against C++ `UnknownFieldSet` count
- scalar mix encode/decode plus generated ScalarMix JSON stringify/parse
- string/bytes and repeated string/bytes encode/decode, including borrowed
  length-delimited output slices, plus generated TextBytes JSON stringify/parse
  coverage for string fields, bytes base64, repeated string, and repeated bytes
  base64 roundtrips
- large bytes and repeated large bytes encode/decode
- proto3 optional presence plus oneof encode/decode and JSON stringify/parse
- complex nested message / oneof / map-message encode/decode
- complex JSON stringify/parse, including proto-name field-name output/input
- `google.protobuf.Any` containing a well-known-type JSON value stringify/parse,
  including embedded zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound `Duration`, non-empty/escaped-input parse/number-exponent parse/surrogate-pair value parse/surrogate-pair key parse and empty `Struct`, object/escaped-object parse/object-number-exponent/object-surrogate-pair value parse/object-surrogate-pair key parse/list/escaped-list/surrogate-list/string-scalar/escaped-string-scalar/surrogate-string-scalar/number-exponent/negative-number `Value` (including default-like scalar and empty object/list kinds), camel-case, escaped JSON parse input, and empty `FieldMask`, escaped-input parse/short-fraction parse/micro/nano/offset/min/pre/post/max-bound `Timestamp`, canonical `Empty`, 64-bit min/zero/positive/number-input parse/numeric-exponent parse/negative/max `Int64Value`, negative/zero/positive finite/string-input parse/numeric-exponent parse `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), negative/zero/positive finite/string-input parse/numeric-exponent parse `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), min/zero/positive/string-input parse/numeric-exponent parse/negative/max `Int32Value`, zero/normal/string-input parse/numeric-exponent parse/max unsigned `UInt32Value`, zero/normal/number-input parse/numeric-exponent parse/max unsigned `UInt64Value`, true/false `BoolValue`, non-empty/escape-input parse/surrogate-pair parse/empty `StringValue`, padded-standard/base64url/unpadded-base64 parse/empty `BytesValue`, and recursive nested `Any` payloads
- direct zero, escaped-input parse, explicit-plus parse, short-fraction parse, positive, micro, nano, integer-negative, fractional-negative, min-bound, and max-bound `google.protobuf.Duration` JSON stringify/parse
- direct non-empty, escaped-input parse, and empty `google.protobuf.FieldMask` JSON stringify/parse
- direct escaped-input parse, short-fraction parse, micro, nano, timezone-offset parse, min-bound, pre-epoch, post-epoch, and max-bound `google.protobuf.Timestamp` JSON stringify/parse
- direct `google.protobuf.Empty`, non-empty/escaped-input parse/number-exponent parse/surrogate-pair value parse/surrogate-pair key parse/empty `Struct`, object/escaped-object parse/object-number-exponent/object-surrogate-pair value parse/object-surrogate-pair key parse/list/escaped-list/surrogate-list/string-scalar/escaped-string-scalar/surrogate-string-scalar/number-exponent/negative-number `Value` (including default-like scalar and empty object/list kinds), and escaped/surrogate-pair/non-empty/empty `ListValue` JSON stringify/parse
- direct scalar wrapper JSON stringify/parse for `DoubleValue`, `FloatValue`,
  min/zero/positive/number-input parse/numeric-exponent parse/negative/max `Int64Value`, zero/normal/number-input parse/numeric-exponent parse/max `UInt64Value`, min/zero/positive/string-input parse/numeric-exponent parse/negative/max `Int32Value`, zero/normal/string-input parse/numeric-exponent parse/max `UInt32Value`, true/false `BoolValue`, plus negative/zero/positive finite, finite string-input parse, numeric-exponent parse, and non-finite `DoubleValue` and `FloatValue` (`NaN`, `Infinity`, `-Infinity`),
  non-empty/escape-input parse/surrogate-pair parse/empty `StringValue`, and padded-standard/base64url/unpadded-base64 parse/empty `BytesValue`
- complex TextFormat format/parse
- simple JSON stringify/parse, including generated `map<string, int32>` surrogate-pair key parse, generated null-field parse, generated ignore-unknown parse, generated enum-name parse, generated ScalarMix JSON stringify/parse, generated always-print default-value stringify, generated enum-number stringify, generated proto-name stringify, generated proto-name parse, generated open-enum numeric parse, generated integer numeric-exponent token parse, generated quoted numeric string parse, and generated TextBytes JSON stringify/parse for bytes base64 and repeated string/bytes fields
- simple TextFormat format/parse
- packed int32 encode/decode
- packed fixed32/fixed64/sfixed32/sfixed64/float/double encode/decode
- packed uint64/uint32/int64/sint32/sint64/bool/enum encode/decode
- large `map<string, int32>` encode/decode and generated LargeMap JSON
  stringify/parse
- shuffled large `map<string, int32>` deterministic encode against C++/Go

The local `zig build bench` output also includes generated/dynamic
unknown-field stress decode and count-by-number query rows, plus generated and
dynamic raw-field-number / compact run sidecar count rows for callers that
repeatedly query preserved unknown fields by number. `bench/run_compare.sh` now emits
C++ `UnknownFieldSet` stress decode/count rows; the count-by-number row is in
the fail-on-loss matrix against pbz's compact run sidecar, while the decode row
remains manual context because C++ exposes parsed unknown fields and pbz
preserves exact raw-field byte slices.

## Generated performance APIs now used by the matrix

The benchmark’s fastest pbz paths are intentionally backed by generated/runtime
APIs:

- `encodeIntoAssumeCapacity(buffer)`
- `encodeIntoAssumeCapacityTrustedUtf8(buffer)`
- `writeToAssumeCapacity(writer)`
- `writeDeterministicToAssumeCapacity(allocator, writer)`
- `decodeReuse(allocator, bytes)`
- `decodeKnownReuse(allocator, bytes)` for trusted same-schema hot paths
  including packed-only repeated scalar and open-enum messages where the caller
  reuses a correctly-sized destination buffer
- `*FieldView` / `*BytesView` / `*StringView` for length-delimited views
- `*FieldSlices` / `*BytesSlices` / `*StringSlices` for borrowed
  length-delimited output
- `valuesPackedFixedView(bytes)` / `valuesPackedFixed32View(bytes)` for
  fixed-width packed zero-copy views
- `valuesPackedFixedSlices(header, values)` / `valuesPackedFixed32Slices(...)`
  for borrowed fixed-width packed output
- `valuesPackedBoolSlices(header, values)` for borrowed packed bool output
- `valuesPackedIterator(bytes)` for zero-allocation varint scans across every
  packed or unpacked occurrence of the repeated field
- `pbz.wire.rawFieldNumbersAlloc(fields)` plus
  `pbz.wire.rawFieldNumberCount(numbers, number)` for repeated by-number
  queries over exact raw unknown-field storage without re-decoding every tag
- `pbz.wire.rawFieldNumberRunsAlloc(fields)` plus
  `pbz.wire.rawFieldNumberRunCount(runs, number)` for compact, sorted run
  sidecars when repeated unknown fields contain many duplicate numbers
- `DynamicMessage.unknownFieldNumbersAlloc(allocator)` and
  `DynamicMessage.unknownFieldNumberRunsAlloc(allocator)` for the same repeated
  by-number query pattern over dynamic messages without re-decoding raw tags

`examples/generated_performance.zig` demonstrates these APIs outside the
benchmark harness.

## Functional coverage evidence

- `examples/generated_types.zig` shows C++/Rust-style concrete generated type
  usage and package namespace access.
- `examples/generated_performance.zig` shows generated fastest-path APIs.
- `examples/generated_advanced.zig` covers package namespaces, enums, nested
  messages, oneof, maps with message values, JSON/TextFormat, and service
  metadata.
- `examples/generated_imports.zig` covers generated imports and typed imported
  singular/repeated/map/oneof message fields.
- `examples/generated_groups.zig` covers proto2 group fields.
- `examples/generated_required.zig` covers generated proto2 required-field
  initialization gates for binary, deterministic binary, JSON, and TextFormat.
- `examples/generated_defaults.zig` covers generated proto2 default values,
  explicit has-bit behavior, JSON null reset semantics, and TextFormat
  round-trips.
- `examples/generated_extensions.zig` covers generated proto2 extension metadata,
  typed scalar/message/enum accessors, packed repeated extension values,
  JSON/TextFormat extension names, and recursive required-field validation
  through extension payloads.
- `examples/generated_identifiers.zig` covers generated quoting for proto names
  that collide with Zig keywords, primitive type names, and top-level test
  declarations while preserving protobuf JSON/TextFormat names.
- `examples/generated_enum_alias.zig` covers generated enum aliases, including
  alias constants, canonical JSON/TextFormat output, alias JSON/TextFormat input,
  and enum-number JSON output.
- `examples/generated_json_names.zig` covers generated explicit `json_name`
  metadata, default JSON spelling, proto-name JSON output, JSON input aliases,
  null reset semantics, and TextFormat proto-name behavior.
- `examples/generated_messageset.zig` covers generated proto2 MessageSet
  extension helpers, start-group wire preservation, JSON/TextFormat extension
  mapping, and required-field validation through MessageSet payloads.
- `examples/generated_map_keys.zig` covers generated map fields with non-string
  keys (`int32`, `bool`, `int64`, `uint64`), protobuf JSON string-key
  conversion, deterministic binary round-trip, and TextFormat round-trip.
- `examples/generated_nested_types.zig` covers generated nested message/enum
  type references, repeated nested messages, map values, oneof nested-message
  arms, JSON proto-name input, and TextFormat round-trip.
- `examples/generated_unpacked.zig` covers generated repeated scalar
  `[packed = false]` encoding, parser merging of packed and unpacked
  occurrences, JSON round-trip, and TextFormat round-trip.
- `examples/generated_public_imports.zig` covers generated public-import chains,
  re-exported type references, binary round-trip, JSON round-trip, proto-name
  JSON input, and TextFormat round-trip.
- `examples/generated_proto3_optional.zig` covers generated proto3 optional
  fields as source-level plain fields plus `has_*` bits instead of leaking
  protoc's descriptor-only synthetic oneofs, including binary, JSON null,
  TextFormat, merge, and borrowed view helpers.
- `examples/dynamic_public_imports.zig` covers dynamic registry public-import
  chain lookup and binary/JSON round-trips through public re-exported types.
- `examples/dynamic_editions_features.zig` covers dynamic protobuf editions
  feature interactions: explicit/implicit/legacy-required presence,
  packed-vs-expanded repeated scalar encoding, delimited message encoding,
  relaxed UTF-8 strings, closed enum unknown preservation, and TextFormat
  round-trip.
- `examples/dynamic_groups.zig` covers dynamic proto2 group fields, repeated
  groups, JSON/TextFormat round-trips, singular group merge semantics, and
  unknown group preservation.
- `examples/dynamic_weak_imports.zig` covers dynamic loader/registry behavior
  for present and missing proto2 weak imports, including descriptor-set
  preservation, usable local fields when a weak import is absent, and
  registry-backed binary/JSON/TextFormat round-trips when the weak import is
  present.
- `examples/registry_loader.zig` covers public in-memory and filesystem schema
  loading (`MemorySourceTree` and `loadDir`), recursive imports, registry lookup,
  and registry-backed dynamic JSON output.
- `examples/dynamic_reserved_text.zig` covers reserved field names/ranges in
  dynamic schemas, descriptor round-trips, parser rejection of reserved
  declarations, and TextFormat's protobuf-compatible reserved-name ignore
  semantics.
- `examples/dynamic_messageset.zig` covers dynamic proto2 MessageSet
  encode/decode, JSON/TextFormat extension mapping, payload-before-type-id
  parsing, and unknown MessageSet item preservation.
- `examples/generated_merge_semantics.zig` covers generated binary decode merge
  semantics for repeated singular messages, repeated fields, map last-wins,
  oneof last-wins, and decode reuse.
- `examples/generated_clone_owned.zig` covers generated deep-clone ownership
  handoff for nested messages, repeated message slices, map values, oneof
  payloads, and exact raw unknown fields.
- `examples/generated_unknown_mutation.zig` covers generated unknown-field
  append/query/clear APIs, by-number extraction, sidecar counts, exact raw-byte
  round-trip, and invalid raw-field rejection.
- `examples/generated_closed_enum.zig` covers generated proto2 closed-enum
  unknown numeric preservation into raw unknown fields, including singular,
  repeated, and packed repeated inputs.
- `examples/generated_recursive.zig` covers generated self-recursive schemas,
  including raw-payload singular recursion, typed repeated recursion, and
  generated decode recursion-limit propagation.
- `tools/check_generated_examples.py` and `zig build check-generated-examples`
  regenerate every checked-in `examples/generated/*.pb.zig` module from
  `examples/proto/*.proto` and fail on drift.
- `examples/generated_streaming.zig` covers generated service client/handler
  adapters over a transport abstraction for unary, client-streaming,
  server-streaming, and bidirectional-streaming RPC shapes.
- `examples/descriptors_codegen.zig` covers descriptor encode/decode,
  descriptor sets, source-code info, uninterpreted custom options,
  service/method options including idempotency levels, direct codegen, plugin
  request generation, and generated-code info annotations.
- `examples/reflection_facade.zig` covers the public reflection facade over
  registry descriptors and dynamic messages, including typed get/set/add/clear
  helpers across all scalar families, repeated fields, map last-wins mutation,
  oneof inspection, imported message fields, binary, and JSON round-trips.
- `examples/ownership_patterns.zig` covers arena-style ownership patterns for
  generated and dynamic messages, clone-to-long-lived-allocator handoff, and
  generated decode reuse.
- `examples/proto2_extensions.zig` covers proto2 extension parsing, extension
  range declarations/verification, repeated message extensions with recursive
  required-field validation, descriptor round-trips, JSON/TextFormat extension
  mappings, and unknown preservation.
- `examples/well_known_types.zig` covers selected well known types, including
  Timestamp, Duration, FieldMask, Empty, Struct/Value/ListValue, scalar and
  bytes wrappers, standalone `Any` JSON mapping for embedded WKT payload
  values, and WKT wire round-trips.
- `examples/any_dynamic.zig` covers custom dynamic-message `Any`
  pack/unpack with registry lookup, type-url matching, required-field
  validation on pack and unpack, and type mismatch errors.
- `examples/any_type_url.zig` covers custom `Any` type URL prefixes, leading-dot
  protobuf type names, JSON parse for custom prefixes, default prefix
  canonicalization, and type mismatch errors.
- `src/pbz_conformance.zig`, `tools/smoke_conformance.py`,
  `tools/fetch_conformance_runner.sh`, and `tools/run_conformance.sh` provide a
  conformance-test-runner-compatible subprocess executable, descriptor-set
  smoke test, reproducible fetch/build path for the upstream runner, and a
  passing upstream conformance run. The latest accepted upstream run is recorded
  in `/tmp/pbz-upstream-conformance-after-textbytes-slices.log`: Binary/JSON reported `2808
  successes, 0 skipped, 0 expected failures, 0 unexpected failures`, and
  TextFormat reported `445 successes, 0 skipped, 0 expected failures, 0
  unexpected failures`.
- `src/dynamic.zig` and `src/wire.zig` tests cover dynamic decode recursion
  limits for nested length-delimited messages, maps, MessageSet payloads, and
  groups.
- `zig build test` runs unit tests across parser, descriptor, dynamic,
  generated-code helpers, JSON, TextFormat, registry, WKT, codegen, and
  conformance helpers.

## Remaining non-goals / open audit items

These are not current full-gate blockers, but they should be revisited before
claiming broad superiority beyond the covered workloads:

- The full Protobuf conformance test suite is not vendored here; use
  `tools/run_conformance.sh` to fetch/build and run the upstream runner. The
  current upstream audit is a passing gate with zero skips and zero unexpected
  failures.
- The comparison matrix is intentionally broad but not infinite: additional
  workloads such as remaining well-known-type edge cases may deserve separate
  rows.
- The local pbz benchmark includes unknown-field stress decode and
  count-by-number rows. The C++ `UnknownFieldSet` count-by-number row is parsed
  into the fail-on-loss matrix against pbz's compact run sidecar; the C++
  unknown-field decode row remains manual context because the APIs differ: C++
  exposes parsed unknown fields, while pbz preserves exact raw-field slice
  bytes.
- `decodeKnownReuse` is a trusted same-schema hot path and intentionally rejects
  unknown fields instead of preserving them. Use `decode` / `decodeReuse` when
  unknown-field preservation is required.
- `jsonParseValue` / `jsonParseValueWithOptions` are intended for callers that
  already have a parsed `std.json.Value` and can keep the provided arena alive
  for borrowed string/bytes storage; `jsonParse` remains the owning text entry
  point.
- Benchmark results are hardware- and compiler-sensitive; keep using
  `--fail-on-loss` on the same machine before making performance claims.
