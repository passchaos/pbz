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
- The fastest relevant pbz generated path should beat Rust `prost`, Rust
  `quick-protobuf`, C++ protobuf, and Go protobuf for every parsed comparison row
  in `bench/summarize_compare.py`.
- Performance wins should come from public generated or runtime APIs rather than
  benchmark-only hand-written code wherever possible.

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
ended with:

```text
All parsed cross-language rows are pbz wins.
```

Also keep these green for functional coverage:

```sh
zig build test
zig build examples
git diff --check
```

## Cross-language benchmark matrix

`bench/summarize_compare.py` currently tracks 52 workloads. The parsed baselines
include:

- Rust `prost`
- Rust `quick-protobuf`
- C++ protobuf generated binary encode/decode plus JSON/TextFormat util paths
- Go protobuf generated binary encode/decode plus protojson/prototext paths

The matrix includes:

- binary encode/decode
- deterministic binary encode
- scalar mix encode/decode
- string/bytes and repeated string/bytes encode/decode
- large bytes and repeated large bytes encode/decode
- proto3 optional presence plus oneof encode/decode
- complex nested message / oneof / map-message encode/decode
- complex JSON stringify/parse
- complex TextFormat format/parse
- simple JSON stringify/parse
- simple TextFormat format/parse
- packed int32 encode/decode
- packed fixed32/fixed64/sfixed32/sfixed64/float/double encode/decode
- packed uint64/uint32/int64/sint32/sint64/bool/enum encode/decode
- large `map<string, int32>` encode/decode

## Generated performance APIs now used by the matrix

The benchmark’s fastest pbz paths are intentionally backed by generated/runtime
APIs:

- `encodeIntoAssumeCapacity(buffer)`
- `encodeIntoAssumeCapacityTrustedUtf8(buffer)`
- `writeToAssumeCapacity(writer)`
- `writeDeterministicToAssumeCapacity(allocator, writer)`
- `decodeReuse(allocator, bytes)`
- `decodeKnownReuse(allocator, bytes)` for trusted same-schema hot paths
- `*FieldView` / `*BytesView` / `*StringView` for length-delimited views
- `*FieldSlices` / `*BytesSlices` / `*StringSlices` for borrowed
  length-delimited output
- `valuesPackedFixedView(bytes)` / `valuesPackedFixed32View(bytes)` for
  fixed-width packed zero-copy views
- `valuesPackedFixedSlices(header, values)` / `valuesPackedFixed32Slices(...)`
  for borrowed fixed-width packed output
- `valuesPackedIterator(bytes)` for packed varint scans

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
- `examples/proto2_extensions.zig` covers proto2 extension parsing and unknown
  preservation.
- `examples/well_known_types.zig` covers selected well known types.
- `zig build test` runs unit tests across parser, descriptor, dynamic,
  generated-code helpers, JSON, TextFormat, registry, WKT, codegen, and
  conformance helpers.

## Remaining non-goals / open audit items

These are not current full-gate blockers, but they should be revisited before
claiming broad superiority beyond the covered workloads:

- The full Protobuf conformance test suite is not vendored here; the repository
  has conformance-style helpers and examples, but not an exhaustive upstream
  conformance run.
- The comparison matrix is intentionally broad but not infinite: additional
  workloads such as very large unknown-field sets, pathological map ordering,
  deeply nested recursion limits, arena-style ownership patterns, streaming RPC
  transports, and every well-known-type edge case may deserve separate rows.
- `decodeKnownReuse` is a trusted same-schema hot path and intentionally rejects
  unknown fields instead of preserving them. Use `decode` / `decodeReuse` when
  unknown-field preservation is required.
- Benchmark results are hardware- and compiler-sensitive; keep using
  `--fail-on-loss` on the same machine before making performance claims.
