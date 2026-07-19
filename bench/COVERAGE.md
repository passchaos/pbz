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

The latest accepted full-gate evidence at the time this checklist was updated
is `/tmp/pbz-compare-zero-numeric-wrapper-json-isolated.log` summarized by
`/tmp/pbz-summary-zero-numeric-wrapper-json-isolated.txt`. The fail-on-loss summary gate:

```sh
python3 bench/summarize_compare.py /tmp/pbz-compare-zero-numeric-wrapper-json-isolated.log --fail-on-loss
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
zig build conformance-smoke
python3 bench/summarize_compare.py --self-test
git diff --check
```

## Cross-language benchmark matrix

`bench/summarize_compare.py` currently tracks 226 workloads. The parsed baselines
include:

- Rust `prost`
- Rust `quick-protobuf`
- C++ protobuf generated binary encode/decode plus JSON/TextFormat util paths
- Go protobuf generated binary encode/decode plus protojson/prototext paths

The matrix includes:

- binary encode/decode
- deterministic binary encode
- unknown-field count-by-number against C++ `UnknownFieldSet` count
- scalar mix encode/decode
- string/bytes and repeated string/bytes encode/decode, including borrowed
  length-delimited output slices
- large bytes and repeated large bytes encode/decode
- proto3 optional presence plus oneof encode/decode
- complex nested message / oneof / map-message encode/decode
- complex JSON stringify/parse
- `google.protobuf.Any` containing a well-known-type JSON value stringify/parse,
  including embedded zero/positive/integer-negative/fractional-negative/min-max-bound `Duration`, `Struct`, `Value`, camel-case `FieldMask`, min/pre/post/max-bound `Timestamp`, canonical `Empty`, 64-bit zero/positive/negative `Int64Value`, zero/finite `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), zero/finite `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), zero/positive/negative `Int32Value`, zero/normal/max unsigned `UInt32Value`, zero/normal/max unsigned `UInt64Value`, true/false `BoolValue`, non-empty/empty `StringValue`, base64/empty `BytesValue`, and recursive nested `Any` payloads
- direct zero, positive, integer-negative, fractional-negative, min-bound, and max-bound `google.protobuf.Duration` JSON stringify/parse
- direct `google.protobuf.FieldMask` JSON stringify/parse
- direct min-bound, pre-epoch, post-epoch, and max-bound `google.protobuf.Timestamp` JSON stringify/parse
- direct `google.protobuf.Empty`, `Struct`, `Value`, and `ListValue` JSON stringify/parse
- direct scalar wrapper JSON stringify/parse for `DoubleValue`, `FloatValue`,
  zero/positive/negative `Int64Value`, zero/normal/max `UInt64Value`, zero/positive/negative `Int32Value`, zero/normal/max `UInt32Value`, true/false `BoolValue`, plus zero and non-finite `DoubleValue` and `FloatValue` (`NaN`, `Infinity`, `-Infinity`),
  non-empty/empty `StringValue`, and base64/empty `BytesValue`
- complex TextFormat format/parse
- simple JSON stringify/parse
- simple TextFormat format/parse
- packed int32 encode/decode
- packed fixed32/fixed64/sfixed32/sfixed64/float/double encode/decode
- packed uint64/uint32/int64/sint32/sint64/bool/enum encode/decode
- large `map<string, int32>` encode/decode
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
- `examples/generated_recursive.zig` covers generated self-recursive schemas,
  including raw-payload singular recursion, typed repeated recursion, and
  generated decode recursion-limit propagation.
- `examples/generated_streaming.zig` covers generated service client/handler
  adapters over a transport abstraction for unary, client-streaming,
  server-streaming, and bidirectional-streaming RPC shapes.
- `examples/ownership_patterns.zig` covers arena-style ownership patterns for
  generated and dynamic messages, clone-to-long-lived-allocator handoff, and
  generated decode reuse.
- `examples/proto2_extensions.zig` covers proto2 extension parsing and unknown
  preservation.
- `examples/well_known_types.zig` covers selected well known types, including
  standalone `Any` JSON mapping for embedded WKT payload values.
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
