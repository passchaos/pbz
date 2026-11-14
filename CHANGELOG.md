# Changelog

## 0.1.0 — 2026-11-14

First tagged release of pbz, a pure Zig Protocol Buffers toolkit for Zig 0.16.0.

### Functionality

- Wire encode/decode with varint, fixed, group, packed, map, and unknown-field
  preservation.
- `.proto` parser for proto2, proto3, and protobuf editions (2023/2024/2026),
  including options, features, visibility modifiers, naming styles, and proto
  limits.
- Descriptor model, `descriptor.proto` codec, `FileDescriptorSet` round-trips,
  registry/import loader, and reflection facade.
- Dynamic messages with mutation, merge, clone, reuse, and unknown-field APIs.
- `protoc-gen-pbz` code generator and `build.zig` `generateProtobuf` helper.
- JSON and TextFormat parse/stringify for dynamic and generated messages,
  including canonical well-known-type forms, `Any`, and proto-name options.
- Selected well-known types with wire and JSON helpers.
- `pbz` CLI (`encode`/`decode`/`convert`/`describe`) and `pbz-fuzz` standalone
  fuzzer.
- Upstream conformance against protobuf 36.2: 2817 binary/JSON and 445
  TextFormat cases pass on both the dynamic and generated paths, with zero
  skips and zero unexpected failures.
- Differential parity with protoc 36.2 over the 183-file corpus: zero parser
  false rejections, exact strict-option accept/reject parity, and zero
  descriptor round-trip differences.

### Performance

- Three-round pinned-CPU cross-language gate against protobuf 36.2 C++/upb,
  prost 0.14.6, quick-protobuf 0.8.1, and Go protobuf v1.36.12: all parsed rows
  are pbz wins in both mixed and fair (`--exclude-zero-copy`) modes.
- Generated JSON parse uses length-guarded key comparisons, fused integer token
  scanning, and an FNV-1a duplicate-key table; generated JSON stringify
  pre-sizes its output buffer.

### Structure and tooling

- `src/codegen.zig` is a hub over phase modules
  (`decl/encode/decode/lifecycle/extension/validate/view/json/text_emit`).
- Inline test suites for `descriptor`, `dynamic`, `parser`, `json`, `wire`, and
  `registry` live in sibling `<module>_tests.zig` files; reflection helpers live
  in `src/reflect/helpers.zig`.
- `zig build check` runs unit tests, examples, generated-example drift,
  `zig fmt --check`, conformance smoke, CLI smoke, and fuzz smoke.
- Design documentation: `docs/architecture.md`, `docs/ownership.md`,
  `docs/codegen.md`.
