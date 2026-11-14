# pbz code generation

`protoc-gen-pbz` converts `.proto` files into plain Zig structs. The same
generator is available through `build.zig`'s `generateProtobuf` helper. This
document covers the output layout, generator parameters, and the generated API
surface.

## Output layout

For `package demo; message Person { ... }` in `person.proto`, the generated
`person.pb.zig` contains:

- `pub const demo = struct { ... }` — a namespace mirroring the protobuf
  package; nested messages/enums become nested Zig declarations.
- `pub const Person = struct { ... }` — a plain Zig struct with public fields
  (no getters/setters).
- Message and enum descriptor lookup helpers (`Person.descriptor(file)`).
- An embedded serialized `FileDescriptorProto` (`decodeFileDescriptor`).
- Generated ↔ dynamic bridges (`toDynamic` / `fromDynamic`) and conformant
  JSON/TextFormat fallbacks.
- Service metadata and lightweight client/handler adapters for `service`
  declarations.

Generated files import the runtime as `@import("pbz")` by default; see
`pbz_import` below. Output paths are always source-relative: `foo/bar.proto`
produces `foo/bar.pb.zig` (subject to `output_suffix` and `strip_proto_ext`).

## Generator parameters

Pass with `--pbz_out=...` or `--pbz_opt=...` / `parameter` in `build.zig`.
Parameters are comma-separated `key=value` pairs. Unknown keys are rejected.

| Parameter | Aliases | Default | Meaning |
|---|---|---|---|
| `include_imports` | `emit_imports` | `false` | Generate code for every file in the request, not just `file_to_generate` (protoc passes imports as dependencies only) |
| `generated_info` | `annotate_code` | `true` | Populate `GeneratedCodeInfo` annotations (source spans) in the response |
| `pbz_import` | `runtime_import` | `pbz` | Module name used for `@import(...)` in generated files |
| `json` | `emit_json` | `true` | Emit JSON parse/stringify methods and options |
| `text` | `text_format`, `emit_text` | `true` | Emit TextFormat parse/format methods and options |
| `descriptor` | `emit_descriptor` | `true` | Emit the embedded descriptor, descriptor lookups, dynamic bridges, and conformant JSON/TextFormat fallbacks |
| `output_suffix` | — | `.pb.zig` | Suffix appended to the output file stem |
| `strip_proto_ext` | — | `true` | Strip `.proto` from the output stem before adding the suffix |
| `paths` | — | — | Accepted for protoc-gen-go compatibility; the only supported value is `source_relative` (output is always source-relative) |

Boolean parameters accept `true`/`false`; a bare key means `true`.

`descriptor=false` removes the embedded descriptor, descriptor/dynamic bridge
helpers, and the conformant fallbacks. JSON/TextFormat then only use the fast
generated paths, which cover the common cases but not every construct (for
example `Any` JSON needs the dynamic fallback).

## Generated API families

Every message gets the families below. `X` is the message type.

### Binary

- `encode(allocator)` / `encodeInto(buffer)` / `encodeIntoAssumeCapacity(buffer)`
- `encodeIntoAssumeCapacityTrustedUtf8(buffer)` — skips UTF-8 validation
- `writeTo(writer)` / `writeToAssumeCapacity(writer)`
- `encodeDeterministic(...)` / `writeDeterministicTo(...)` /
  `writeDeterministicToAssumeCapacity(...)` — sorted map keys
- `encodedSize()` and `*Initialized` variants that validate required fields
- `decode(allocator, bytes)` / `decodeFromReader(allocator, reader)` —
  string/bytes payloads borrow the input
- `decodeReuse(allocator, bytes)` / `decodeOwnedReuse(allocator, bytes)` —
  refill an existing message, keeping repeated buffers
- `decodeKnownReuse(allocator, bytes)` — trusted same-schema path; caller
  pre-sizes repeated buffers; rejects unknown fields
- `decodeOwned(...)` / `decodeOwnedInitialized(...)` — arena-backed owning
  decode
- `mergeFrom(other)` — deep-copy merge

### JSON

- `jsonParse(allocator, text)` / `jsonParseWithOptions(...)`
- `jsonParseInitialized(...)` — validates required fields
- `jsonParseValue(allocator, arena, value)` /
  `jsonParseValueWithOptions(...)` — parse from an existing
  `pbz.json.Value` without reserializing
- `jsonParseConformant(...)` — registry-aware fallback for constructs the fast
  parser does not cover
- `jsonStringify(writer)` / `jsonStringifyAlloc(allocator)` /
  `jsonStringifyWithOptions(...)` / `jsonStringifyAllocWithOptions(...)`

JSON options cover `ignore_unknown_fields`, proto-name field names,
always-print defaults, and enum numbers. Well-known types use their canonical
JSON forms.

### TextFormat

- `parseText(allocator, text)` / `parseTextWithOptions(...)`
- `parseTextInitialized(...)` / `parseTextConformant(...)`
- `formatText(...)` / `formatTextAlloc(...)` / `formatTextWithOptions(...)`

The fast parser is line-oriented; complex syntax falls back to the conformant
dynamic parser. The formatter honors `print_unknown_fields`.

### Zero-copy views and iterators

- `*FieldView` / `*BytesView` / `*StringView` — borrowed length-delimited
  views over the decode buffer
- `*FieldSlices` / `*BytesSlices` / `*StringSlices` — borrowed slices for
  encoded output
- `valuesPackedFixedView(bytes)` / `valuesPackedFixed32View(bytes)` — zero-copy
  packed fixed-width views
- `valuesPackedFixedSlices(...)` / `valuesPackedFixed32Slices(...)` /
  `valuesPackedBoolSlices(...)` — borrowed packed output
- `valuesPackedIterator(bytes)` — zero-allocation varint scans across packed or
  unpacked occurrences

### Unknown fields

- `unknownFields()` / `unknownFieldCount()` /
  `unknownFieldCountByNumber(number)`
- `unknownFieldNumbersAlloc(allocator)` /
  `unknownFieldNumberRunsAlloc(allocator)` — by-number query sidecars
- `unknownFieldsByNumberAlloc(...)` / `appendUnknownRaw(...)` /
  `clearUnknownFields()` / `clearUnknownFieldsByNumber(...)`
- `hasUnknownFieldNumber(number)`

### Ownership and lifecycle

- `init()` / `deinit(allocator)` / `clear(allocator)`
- `cloneOwned(allocator)` — deep clone into owned storage
- `adoptOwned(allocator)` / `adoptOwnedInto(allocator, owned_allocator)` —
  convert borrowed decode into arena-backed owned storage
- `validateRequired()` / `validateRequiredRecursive()`

See `docs/ownership.md` for the full ownership model.

### Descriptors, dynamic bridge, services

- `descriptor(file)` on messages, enums, services, and methods
- `toDynamic(allocator, file)` / `fromDynamic(allocator, file, dynamic)`
- `decodeFileDescriptor(allocator)` for the embedded descriptor
- Service metadata plus client/handler adapters for unary, client-streaming,
  server-streaming, and bidirectional-streaming shapes

## build.zig helper

```zig
const generated = pbz_build.generateProtobuf(b, .{
    .dependency = pbz_dep,
    .proto_files = &.{"proto/person.proto"},
    .include_paths = &.{"proto"},
    .parameter = "paths=source_relative,generated_info=false",
});
const person_pb = generated.addModule(b, "person_pb", "proto/person.proto", target, optimize, pbz_mod);
```

The helper shells out to `protoc` with the built `protoc-gen-pbz` executable,
so standalone and build-graph generation share one implementation. See
`examples/build_codegen.zig` and `zig build build-codegen-smoke`.

## Choosing fast paths

| Workload | Recommended API |
|---|---|
| Encode into a known-size buffer | `encodeIntoAssumeCapacity` |
| Encode into a writer with reserved capacity | `writeToAssumeCapacity` |
| Trusted UTF-8 input | `encodeIntoAssumeCapacityTrustedUtf8` |
| Repeated decode in a loop | `decodeReuse` / `decodeOwnedReuse` |
| Trusted schema, no unknown fields | `decodeKnownReuse` |
| Borrow payloads from a stable buffer | `decode` + `*View`/`*Slices` |
| JSON from an already-parsed tree | `jsonParseValueWithOptions` |

All of these are public APIs exercised by `examples/generated_performance.zig`
and by the cross-language benchmark matrix (`bench/COVERAGE.md`).
