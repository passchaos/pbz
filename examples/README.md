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
- `registry_loader.zig` — `MemorySourceTree`, recursive imports, and registry lookup.
- `descriptors_codegen.zig` — descriptor encode/decode, descriptor sets, direct codegen, and plugin request generation.
- `generated_types.zig` — C++/Rust-style use of the checked-in generated module `generated/person.pb.zig` from `proto/person.proto`.
- `generated_performance.zig` — generated fastest-path APIs: trusted buffer encode, borrowed length-delimited slices/views, packed fixed-width views/slices, packed varint iterators, and known-schema decode reuse.
- `generated_advanced.zig` — generated package namespaces, enum helpers, typed nested message fields, typed map message values, oneof union storage, JSON/TextFormat round-trips, and service metadata from `proto/advanced.proto`.
- `generated_imports.zig` — multi-file generated modules using proto imports with typed imported singular, repeated, map value, and oneof message fields from `proto/imported_app.proto` / `proto/imported_common.proto`.
- `generated_groups.zig` — typed proto2 group fields, repeated groups, oneof group message arms, and JSON/TextFormat round-trips from `proto/groups.proto`.
- `generated_recursive.zig` — generated self-recursive message usage from `proto/recursive.proto`, including raw-payload singular recursion, typed repeated recursion, and decode recursion-limit enforcement.
- `ownership_patterns.zig` — generated and dynamic arena-style ownership, clone-to-long-lived allocator, and generated decode reuse patterns.
- `well_known_types.zig` — Timestamp, Duration, FieldMask, wrappers, Any including embedded WKT JSON values, and Struct helpers.
- `proto2_extensions.zig` — proto2 extension parsing through TextFormat/JSON and preserved unknown storage.
- `conformance.zig` — conformance-style JSON-to-protobuf conversion.
