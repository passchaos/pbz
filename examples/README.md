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
- `well_known_types.zig` — Timestamp, Duration, FieldMask, wrappers, Any, and Struct helpers.
- `proto2_extensions.zig` — proto2 extension parsing through TextFormat/JSON and preserved unknown storage.
- `conformance.zig` — conformance-style JSON-to-protobuf conversion.
