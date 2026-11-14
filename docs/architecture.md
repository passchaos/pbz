# pbz architecture

`pbz` is a pure Zig Protocol Buffers toolkit. It has two message runtimes that
share one schema model:

- **dynamic** messages driven by descriptors at runtime (reflection, CLI,
  conformance, tooling);
- **generated** Zig structs emitted by `protoc-gen-pbz` (hot paths,
  C++/Rust-style concrete types).

Both runtimes expose the same wire, JSON, and TextFormat semantics.

## Layering

Dependencies point downward; no module imports a higher layer.

| Layer | Modules | Responsibility |
|---|---|---|
| Wire primitives | `src/wire.zig` | varint/fixed/group readers and writers, tags, raw unknown-field storage |
| Schema model | `src/schema.zig` | `FileDescriptor`, `MessageDescriptor`, `FieldDescriptor`, enums, oneofs, services, options, features |
| Source parser | `src/parser.zig` | `.proto` lexer/parser for proto2, proto3, and editions, including option and feature syntax |
| Descriptor codec | `src/descriptor.zig` | `descriptor.proto` encode/decode, `FileDescriptorSet`, `FeatureSetDefaults`, `GeneratedCodeInfo` |
| Registry / loader | `src/registry.zig`, `src/loader.zig` | symbol tables, import resolution, filesystem and in-memory source trees, strict option validation |
| Dynamic runtime | `src/dynamic.zig` | descriptor-driven message storage, encode/decode, unknown fields, merge/reuse |
| Format frontends | `src/json.zig`, `src/json_value.zig`, `src/text.zig`, `src/wkt.zig` | JSON/TextFormat parse/stringify, lean JSON value tree for generated parsers, canonical well-known-type forms |
| Reflection | `src/reflect.zig` | typed facade over registry descriptors and dynamic messages |
| Code generation | `src/codegen.zig`, `src/codegen/*.zig`, `src/plugin.zig` | `protoc` plugin protocol, Zig emission (declarations, binary, JSON, TextFormat), generated descriptors and dynamic bridges |
| Entry points | `src/pbz_cli.zig`, `src/protoc_gen_pbz.zig`, `src/pbz_fuzz.zig`, `src/pbz_conformance*.zig` | CLI, plugin executable, fuzzer, conformance subprocesses |
| Public facade | `src/root.zig` | re-exports the stable public API surface |

## Data flows

- **Source to schema**: `ProtoParser.parse` → `schema.FileDescriptor`.
  `Registry.addFile` resolves imports and symbols; `loader.loadDir` /
  `loadMemory` walk source trees and build a registry.
- **Source to generated code**: `protoc` invokes `protoc-gen-pbz` with a
  `CodeGeneratorRequest` (`src/plugin.zig`); `src/codegen.zig` emits one
  `<name>.pb.zig` per file, embedding the serialized `FileDescriptorProto`.
  `build.zig`'s `generateProtobuf` helper wires the same plugin into a Zig
  build graph.
- **Binary runtime**: generated structs encode/decode directly against
  `pbz.wire`; dynamic messages walk descriptors and reuse the same wire
  primitives.
- **JSON/TextFormat**: the dynamic path parses into `pbz.json.Value` /
  `dynamic.DynamicMessage`; generated code parses with a lean value tree
  (`src/json_value.zig`) and emits field code specialized per message. Complex
  constructs fall back to the registry-aware dynamic parser
  (`jsonParseConformant` / `parseTextConformant`).
- **Descriptors at runtime**: generated modules decode their embedded
  descriptor, build a `Registry`, and bridge generated ↔ dynamic messages for
  reflection, `Any`, and conformant JSON/TextFormat.

## Design principles

1. **Conformance first.** Behavior follows protobuf 36.2 semantics; the upstream
   conformance suite (binary/JSON/TextFormat) is the primary gate. See
   `bench/COVERAGE.md` for the current evidence.
2. **Two runtimes, one model.** Dynamic and generated paths share descriptors,
   wire rules, WKT forms, and option semantics, so fixes land in both.
3. **Zero-copy where it is sound, owning where it is not.** Borrowed views and
   slices are public APIs for scatter/gather use; `decodeOwned`/`adoptOwned`
   provide arena-backed owning values. Benchmarks report both modes; the fair
   mode (`--exclude-zero-copy`) compares owning/contiguous paths only. See
   `docs/ownership.md`.
4. **Performance from public APIs.** Benchmark wins come from documented
   generated/runtime entry points (`encodeIntoAssumeCapacity`,
   `writeToAssumeCapacity`, `decodeKnownReuse`, field views/slices, packed
   iterators), not benchmark-only code.
5. **Pure Zig, explicit allocators.** No C dependencies at runtime; every
   allocation goes through a caller-provided `std.mem.Allocator`.
6. **Generated output is checked in and drift-checked.**
   `zig build check-generated-examples` regenerates `examples/generated/*` and
   fails on any difference.

## Module size map

Implementation sizes exclude `test` blocks. Files above roughly 2k lines are
candidates for further splitting; the current intentional structure is:

| File | Implementation lines | Role |
|---|---:|---|
| `src/codegen.zig` | ~9.1k | codegen orchestration plus binary/JSON/Text emission; split into `src/codegen/*.zig` by output family |
| `src/reflect.zig` | ~4.1k | reflection facade |
| `src/descriptor.zig` | ~3.9k | descriptor codec (plus ~4.4k tests) |
| `src/parser.zig` | ~3.1k | `.proto` parser |
| `src/dynamic.zig` | ~2.4k | dynamic runtime |
| `src/wire.zig` | ~2.1k | wire primitives |
| `src/schema.zig` | ~2.2k | schema model |
| `src/wkt.zig` | ~2.0k | well-known types |
| `src/json.zig` | ~1.8k | dynamic JSON |
| `src/registry.zig` | ~1.7k | registry |
| `src/text.zig` | ~1.4k | dynamic TextFormat |

## Validation map

| Command | Scope |
|---|---|
| `zig build check` | unit tests, examples, generated drift, fmt check, conformance smoke, CLI smoke, fuzz smoke |
| `zig build test` | unit tests + examples + summarizer self-test |
| `zig build fmt-check` | `zig fmt --check` over hand-written sources |
| `zig build check-generated-examples` | regenerate checked-in examples, fail on drift |
| `tools/run_conformance.sh` | full upstream conformance (dynamic or generated mode) |
| `tools/run_corpus_differential.sh` | `.proto` parsing and descriptor round-trip parity against protoc |
| `bench/run_compare.sh` + `bench/summarize_compare.py` | cross-language performance matrix |
