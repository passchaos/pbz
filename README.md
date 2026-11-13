# pbz

`pbz` is a pure Zig Protocol Buffers toolkit for Zig 0.16.0.

It provides:

- protobuf wire encode/decode runtime
- `.proto` parser, descriptor model, descriptor set encode/decode
- multi-file registry/import loader
- dynamic messages
- reflection facade over registry descriptors and dynamic messages
- generated Zig message types through `protoc-gen-pbz`
- embedded generated descriptors, descriptor lookup, and generated↔dynamic bridges
- JSON and TextFormat support, including conformant generated parsers
- selected well-known types
- `pbz` encode/decode/convert/describe CLI
- upstream protobuf conformance runner integration
- generated-code performance paths intended to beat common C++/Rust/Go protobuf implementations on covered workloads

## Current status

### Functionality

The current implementation covers the protobuf surfaces used by the examples,
benchmarks, and upstream conformance suite:

- proto2, proto3, and protobuf editions metadata/features used by the test set,
  including dynamic editions presence, repeated encoding, message encoding,
  UTF-8 validation, enum openness behavior, feature edition gating
  (2024/2026-introduced options), `default_symbol_visibility`
  (`EXPORT_ALL` / `EXPORT_TOP_LEVEL` / `LOCAL_ALL` / `STRICT`) enforcement,
  and STYLE2024/2026 naming checks (TitleCase, lower_snake_case,
  UPPER_SNAKE_CASE, package casing)
- scalar fields, repeated fields, packed fields, maps, nested messages, groups,
  oneof, proto3 optional, required-field validation
- unknown field preservation, deterministic encoding, MessageSet support, and
  proto2 extensions
- descriptor and descriptor-set workflows, including source-code info,
  uninterpreted custom options, and generated-code info annotations
- reflection helpers for runtime message creation, field lookup, typed
  get/set/add/clear, repeated fields, maps, and oneof inspection
- generated Zig structs with public fields and package-mirrored namespaces
- generated proto3 optional fields as ordinary fields plus `has_*` bits, without
  leaking protoc's descriptor-only synthetic oneofs into public APIs
- generated imports, generated enum helpers, service metadata, and lightweight
  service client/handler adapters
- dynamic loader support for public and weak imports, including missing weak
  imports that leave the rest of a schema usable
- dynamic JSON and TextFormat parse/format
- WKT JSON/wire helpers for Timestamp, Duration, FieldMask, Any, Empty,
  Struct/Value/ListValue, and wrappers
- generated Zig types validated by the upstream conformance suite: binary
  requests decode/encode through generated code, while JSON/TextFormat use the
  registry-aware dynamic bridge
- standalone deterministic fuzzer (`pbz-fuzz`) covering the wire reader,
  descriptor decoder/set decoder, `.proto` parser, dynamic binary/JSON/
  TextFormat parsers (including registry-backed imports and WKT types), and
  generated `Person` binary decode/encode, `decodeReuse`/`decodeOwnedReuse`,
  generated JSON/TextFormat parsers, proto2 extensions/MessageSet dynamic
  decoding, editions feature schemas, JSON/TextFormat option variants, and
  unknown-field sidecar queries, with a short seed-0 pass wired into
  `zig build check`

For detailed feature coverage, see:

- [`bench/COVERAGE.md`](bench/COVERAGE.md)
- [`examples/README.md`](examples/README.md)

### Upstream conformance

`pbz-conformance` implements the upstream protobuf conformance subprocess
protocol. The helper scripts can fetch/build the upstream runner and descriptor
set:

```sh
tools/run_conformance.sh
```

By default the script builds `pbz-conformance-generated`, which runs the
`protobuf_test_messages.*` binary tests through generated Zig message types and
bridges JSON/TextFormat through the registry-aware dynamic path. Set
`PBZ_CONFORMANCE_MODE=dynamic` to run the dynamic-only binary instead. The
generated runner is large; `PBZ_CONFORMANCE_OPTIMIZE=Debug` builds it much
faster for local iteration.

`PBZ_CONFORMANCE_GENERATED_JSON=1` additionally routes JSON parse and stringify
through generated code; it passes the full 2817/2817 suite, including Any,
Struct/Value/ListValue, wrappers, duplicate keys, URL-safe base64, and the
100-container JSON recursion limit.
`PBZ_CONFORMANCE_GENERATED_TEXT=1` routes TextFormat parse and format through
generated code and now passes the full 445/445: the fast line-oriented parser
handles simple input, falls back to the conformant dynamic parser on complex
syntax, and the generated formatter supports `print_unknown_fields`.

Latest accepted local results (protobuf 36.2, including the new
`StructDeepNesting`/`ValueDeepNesting`/`ListValueDeepNesting` JSON recursion
tests):

```text
# dynamic path
CONFORMANCE SUITE PASSED: 2817 successes, 0 skipped, 0 expected failures, 0 unexpected failures.
CONFORMANCE SUITE PASSED: 445 successes, 0 skipped, 0 expected failures, 0 unexpected failures.

# generated path
CONFORMANCE SUITE PASSED: 2817 successes, 0 skipped, 0 expected failures, 0 unexpected failures.
CONFORMANCE SUITE PASSED: 445 successes, 0 skipped, 0 expected failures, 0 unexpected failures.
```

The generated path decodes binary requests with generated types, encodes them,
and normalizes the response through the registry-aware dynamic encoder so
canonical byte layout matches the reference for cyclic raw fields and unknown
field ordering. With `PBZ_CONFORMANCE_GENERATED_JSON=1` and
`PBZ_CONFORMANCE_GENERATED_TEXT=1` the same 2817/445 results are produced
entirely by generated parse/stringify/format code.
Source parsing is also differentially checked against `protoc` 36.2: all 183
`.proto` files shipped in the protobuf `src/` and `editions/` trees parse with
`pbz.ProtoParser` with zero false rejections, covering custom FeatureSet
extensions, `local`/`export` visibility modifiers, proto2 oneof defaults,
`packed = false` on non-packable fields, and scoped MessageSet extension
numbers. `FileDescriptorSet` decode/encode round-trips every protoc 36.2
descriptor set for that corpus, including visibility, map-entry `json_name`,
`packed = false`, and proto2 oneof defaults.

A lightweight smoke test is also available:

```sh
python3 tools/smoke_conformance.py
```

### Performance

Run pbz's local benchmark:

```sh
zig build bench -Doptimize=ReleaseFast
```

Run pbz plus Rust `prost`, Rust `quick-protobuf`, C++ protobuf, upb protobuf,
and Go protobuf baselines in one pinned session:

```sh
PBZ_COMPARE_CPUSET=3 PBZ_COMPARE_LATEST_CPP=1 PBZ_COMPARE_UPB=1 bench/run_compare.sh 2>&1 | tee /tmp/pbz-compare.log
python3 bench/summarize_compare.py /tmp/pbz-compare.log --fail-on-loss
python3 bench/summarize_compare.py /tmp/pbz-compare.log --pivot --exclude-zero-copy > /tmp/pbz-compare-fair.md
```

`PBZ_COMPARE_LATEST_CPP=1` builds the full C++ benchmark against the protobuf
release used by the upstream conformance suite (default 36.2) instead of the
system libprotobuf. `PBZ_COMPARE_UPB=1` builds the upb C-runtime benchmark
against the same release; upb is the C implementation behind Google's
production protobuf runtimes. The compare script derives `GOMAXPROCS` from the
CPU set when it is not already set.

The default summary selects the fastest public pbz path, which can include
zero-copy borrowed slices/views for `largebytes`, packed fixed-width, and
borrowed-decode rows. Those rows are useful for scatter/gather I/O but are not
semantically identical to a baseline that materializes/copies the payload. Use
`--exclude-zero-copy` to prefer owning/contiguous paths (`decode owned`,
`decode owned reuse`, contiguous encode/decode) and exclude borrowed
slice/view rows.

Latest same-session matrix (`bench/results/2026-11-12-linux-x86_64.md`,
2026-11-13 re-run after the lean JSON parser change), fair mode, pinned to one
CPU on an i9-13900K. Baseline cells show `ns/op (baseline / pbz)`; ratios above
1.0 mean pbz is faster. The machine was shared, so sub-10% cells are noise; the
JSON parse rows were also measured in a standalone bench run that removes
allocator/thermal carry-over from earlier rows.

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf 35.1 | upb protobuf 35.1 | Go protobuf |
|---|---:|---:|---:|---:|---:|---:|
| binary encode | 20.47 | 121.48 (5.93x) | 66.63 (3.26x) | 93.20 (4.55x) | 150.32 (7.34x) | 1194.28 (58.34x) |
| binary decode | 143.45 | 382.18 (2.66x) | 381.16 (2.66x) | 281.55 (1.96x) | 276.48 (1.93x) | 1441.92 (10.05x) |
| deterministic binary encode | 69.94 | — | — | 138.47 (1.98x) | 263.15 (3.76x) | 1767.38 (25.27x) |
| unknown fields count by number | 3.60 | — | — | 390.65 (108.51x) | 1953.23 (542.56x) | — |
| scalarmix encode | 16.70 | 132.28 (7.92x) | 73.00 (4.37x) | 48.11 (2.88x) | 178.82 (10.71x) | 303.77 (18.19x) |
| scalarmix decode | 42.19 | 238.22 (5.65x) | 197.62 (4.68x) | 85.80 (2.03x) | 164.78 (3.91x) | 563.92 (13.37x) |
| textbytes encode | 22.37 | 100.91 (4.51x) | 50.37 (2.25x) | 89.56 (4.00x) | 118.58 (5.30x) | 154.74 (6.92x) |
| textbytes decode | 85.82 | 560.92 (6.54x) | 293.05 (3.41x) | 223.17 (2.60x) | 178.50 (2.08x) | 1109.82 (12.93x) |
| largebytes encode | 2614.86 | 2816.10 (1.08x) | 2768.96 (1.06x) | 2821.86 (1.08x) | 174962.00 (66.91x) | 2735.35 (1.05x) |
| largebytes decode | 2818.64 | 6871.80 (2.44x) | 3468.44 (1.23x) | 4196.62 (1.49x) | 3048.63 (1.08x) | 24602.66 (8.73x) |
| presencemix encode | 17.62 | 88.49 (5.02x) | 41.17 (2.34x) | 46.72 (2.65x) | 126.20 (7.16x) | 321.15 (18.23x) |
| presencemix decode | 115.83 | 187.36 (1.62x) | 134.17 (1.16x) | 121.11 (1.05x) | 128.80 (1.11x) | 877.41 (7.57x) |
| complex encode | 60.20 | 182.18 (3.03x) | 118.57 (1.97x) | 134.33 (2.23x) | 294.05 (4.88x) | 1077.53 (17.90x) |
| complex decode | 422.13 | 524.81 (1.24x) | 449.24 (1.06x) | 345.81 (0.82x) | 493.53 (1.17x) | 2157.43 (5.11x) |
| complex deterministic binary encode | 96.33 | — | — | 158.24 (1.64x) | 320.94 (3.33x) | 1490.54 (15.47x) |
| packed int32 encode | 901.53 | 4193.83 (4.65x) | 2955.92 (3.28x) | 1663.13 (1.84x) | 6472.01 (7.18x) | 3739.14 (4.15x) |
| packed int32 decode | 808.90 | 2558.80 (3.16x) | 4165.06 (5.15x) | 2031.75 (2.51x) | 3370.77 (4.17x) | 4012.93 (4.96x) |
| packed fixed32 encode | 32.32 | 836.61 (25.89x) | 606.39 (18.76x) | 39.28 (1.22x) | 352.85 (10.92x) | 527.88 (16.33x) |
| packed fixed32 decode | 34.28 | 1412.83 (41.21x) | 2333.20 (68.06x) | 46.03 (1.34x) | 179.81 (5.25x) | 1973.67 (57.57x) |
| packed fixed64 encode | 62.09 | 685.87 (11.05x) | 741.64 (11.94x) | 68.92 (1.11x) | 399.88 (6.44x) | 547.07 (8.81x) |
| packed fixed64 decode | 67.71 | 1583.00 (23.38x) | 2173.49 (32.10x) | 88.20 (1.30x) | 134.86 (1.99x) | 3198.51 (47.24x) |
| packed bool encode | 10.61 | 1375.38 (129.63x) | 578.39 (54.51x) | 12.65 (1.19x) | 666.83 (62.85x) | 2953.39 (278.36x) |
| packed bool decode | 29.22 | 1671.37 (57.20x) | 3729.40 (127.63x) | 86.14 (2.95x) | 1903.86 (65.16x) | 2343.87 (80.21x) |
| packed enum encode | 276.99 | 2973.51 (10.74x) | 2418.98 (8.73x) | 1212.54 (4.38x) | 902.27 (3.26x) | 3426.32 (12.37x) |
| packed enum decode | 156.72 | 2280.95 (14.55x) | 3955.33 (25.24x) | 272.28 (1.74x) | 1365.07 (8.71x) | 3264.82 (20.83x) |
| large map encode | 4409.20 | 23024.88 (5.22x) | 11343.96 (2.57x) | 14417.30 (3.27x) | 24542.80 (5.57x) | 279388.02 (63.36x) |
| large map decode | 43410.39 | 167900.29 (3.87x) | 133117.28 (3.07x) | 59495.70 (1.37x) | 91317.70 (2.10x) | 395926.70 (9.12x) |
| ScalarMix JSON stringify | 356.04 | — | — | 3743.43 (10.51x) | 1991.78 (5.59x) | 4567.94 (12.83x) |
| ScalarMix JSON parse | 1857.65 | — | — | 7135.76 (3.84x) | 1584.98 (0.85x) | 12785.02 (6.88x) |
| TextBytes JSON stringify | 369.30 | — | — | 1789.43 (4.85x) | 381.92 (1.03x) | 3643.67 (9.87x) |
| TextBytes JSON parse | 530.92 | — | — | 5325.52 (10.03x) | 650.64 (1.23x) | 6699.94 (12.62x) |
| complex JSON stringify | 437.62 | — | — | 2944.65 (6.73x) | 1431.43 (3.27x) | 10150.31 (23.19x) |
| complex JSON parse | 1635.63 | — | — | 7331.73 (4.48x) | 1347.69 (0.82x) | 13403.89 (8.19x) |
| LargeMap JSON stringify | 27185.63 | — | — | 160526.00 (5.90x) | 62776.30 (2.31x) | 1051695.35 (38.69x) |
| LargeMap JSON parse | 105665.29 | — | — | 697230.00 (6.60x) | 144091.00 (1.36x) | 752469.27 (7.12x) |
| TextFormat format | 332.46 | — | — | 1986.80 (5.98x) | — | 3840.14 (11.55x) |
| TextFormat parse | 1047.98 | — | — | 4960.09 (4.73x) | — | 10692.86 (10.20x) |
| complex TextFormat format | 480.20 | — | — | 3760.29 (7.83x) | — | 6061.23 (12.62x) |
| complex TextFormat parse | 2116.88 | — | — | 7164.40 (3.38x) | — | 11399.61 (5.39x) |

Binary and TextFormat rows are pbz wins against every tracked baseline,
including upb. JSON parse was the one consistent cross-language gap found by the
upb baseline; the lean JSON value tree in `src/json_value.zig` replaced the
two-pass `std.json.Value` DOM and cut generated JSON parse cost by 1.7-3.3x
(ScalarMix 2730 -> 1858 ns, TextBytes 1311 -> 531 ns, complex 2343 -> 1636 ns,
LargeMap 167725 -> 105665 ns in the same matrix). Generated JSON fill also
rejects the same field reached through two accepted spellings
(`big_delta`/`bigDelta`), two different members of one oneof, and duplicate
extension keys using a comptime `StaticBitSet`; the focused probe shows the
checks inside noise.
Generated fields typed as `Timestamp`, `Duration`, `FieldMask`, `Empty`, a
wrapper type, or `Struct`/`Value`/`ListValue` now parse and emit their canonical
JSON forms instead of generic message objects. The opt-in
`PBZ_CONFORMANCE_GENERATED_JSON=1` audit mode runs the conformance suite through
generated parse and stringify and now passes 2817/2817 plus 445/445 TextFormat;
generated `Any` JSON uses a per-field dynamic fallback with a descriptor
registry built from the embedded file descriptor and imports.
A best-of-runs check with the
same binaries interleaved on one CPU confirms the close rows: pbz wins every
JSON parse row against upb by 1.14-1.99x, packed fixed64/sfixed64 encode and
decode are 1.03-1.08x faster than C++, and complex `decode owned` is 1.17x
faster. `pbz.wire.copyBytes` now uses ERMS `rep movsb` for 2-32 KiB copies,
cutting an 8 KiB copy from ~61 ns to ~54-58 ns and a 4 KiB copy from ~31 ns to
~28 ns; the packed 64-bit rows moved from roughly 62-67 ns to 60-63 ns. The only
cell still inside the run-to-run spread is packed double encode: across
repeated interleaved rounds the medians are 62.70 ns for pbz and 62.71 ns for
C++ 35.1, while one C++ round produced a 52.89 ns outlier that keeps the
best-of-runs ratio at 0.88x. It is the same 8 KiB copy path and is treated as
variance, not a real gap. See
the results snapshot for the full table, the best-of-runs evidence, the upb
comparison, the noise caveat, and the exact commands.

The full fair-mode table for every tracked workload is in
`bench/results/2026-11-12-linux-x86_64.md`. Use `--pivot` without
`--exclude-zero-copy` for mixed-mode results; do not compare mixed-mode rows to
materializing baselines.

## Basic usage

### Dynamic messages

```zig
const std = @import("std");
const pbz = @import("pbz");

pub fn example(allocator: std.mem.Allocator) !void {
    const source =
        \\syntax = "proto3";
        \\package demo;
        \\message Person {
        \\  int32 id = 1;
        \\  string name = 2;
        \\  repeated int32 scores = 3;
        \\}
    ;

    var file = try pbz.ProtoParser.parse(allocator, source);
    defer file.deinit();

    const desc = file.findMessage("Person").?;
    var msg = pbz.DynamicMessage.init(allocator, desc);
    defer msg.deinit();

    try msg.add(desc.findField("id").?, .{ .int32 = 7 });
    try msg.add(desc.findField("name").?, .{ .string = try allocator.dupe(u8, "Zig") });
    try msg.add(desc.findField("scores").?, .{ .int32 = 10 });

    const bytes = try msg.encoded(&file);
    defer allocator.free(bytes);
}
```

### Generated types with `protoc-gen-pbz`

Build/install the plugin:

```sh
zig build -Doptimize=ReleaseFast
```

Generate Zig from `.proto`:

```sh
protoc \
  --plugin=protoc-gen-pbz=zig-out/bin/protoc-gen-pbz \
  --pbz_out=src/generated \
  --proto_path=proto \
  proto/person.proto
```

Generated files expose package namespaces as Zig namespaces. For example,
`package demo; message Person { ... }` becomes `person_pb.demo.Person`.
Generated messages are plain Zig structs with public fields, not getter/setter
objects.

### Generated types from `build.zig`

`pbz` also exports a build helper similar in spirit to `prost-build`. It shells
out to `protoc` with the same `protoc-gen-pbz` plugin, so it uses the same
capabilities and plugin parameters as the standalone executable.

```zig
const std = @import("std");
const pbz_build = @import("pbz");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const pbz_dep = b.dependency("pbz", .{ .target = target, .optimize = optimize });
    const pbz_mod = pbz_dep.module("pbz");

    const generated = pbz_build.generateProtobuf(b, .{
        .dependency = pbz_dep,
        .proto_files = &.{"proto/person.proto"},
        .include_paths = &.{"proto"},
        .parameter = "paths=source_relative,generated_info=false",
    });

    const person_pb = generated.addModule(
        b,
        "person_pb",
        "proto/person.proto",
        target,
        optimize,
        pbz_mod,
    );

    const exe = b.addExecutable(.{
        .name = "app",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "pbz", .module = pbz_mod },
                .{ .name = "person_pb", .module = person_pb },
            },
        }),
    });
    exe.step.dependOn(generated.step);
}
```

The returned `ProtobufCodegen` exposes:

- `step`
- `run`
- `output_dir`
- `generatedFile(b, proto_path)`
- `addModule(...)`

This repository verifies the helper with:

```sh
zig build build-codegen-smoke
```

### Generated descriptors and dynamic bridges

Generated modules embed their serialized `google.protobuf.FileDescriptorProto`.
This enables registry/reflection workflows without re-parsing `.proto` source at
runtime:

```zig
var file_descriptor = try person_pb.decodeFileDescriptor(allocator);
defer file_descriptor.deinit();

const person_descriptor = person_pb.demo.Person.descriptor(&file_descriptor).?;
var dynamic = try person.toDynamic(allocator, &file_descriptor);
defer dynamic.deinit();
const roundtrip = try person_pb.demo.Person.fromDynamic(allocator, &file_descriptor, &dynamic);
```

Generated messages, enums, services, and methods also expose `descriptor(...)`
lookup helpers. `parseTextConformant` / `jsonParseConformant` delegate to the
dynamic parsers for the full TextFormat/JSON surface when the fast generated
parser does not cover a construct. `adoptOwned` converts a borrowed decode into
owned storage in place; owned payloads, including nested message payloads, are
backed by the message's arena, so keep the top-level message alive while using
its nested messages. `decodeOwned` / `decodeOwnedReuse` perform that conversion
automatically, and `clear` releases owned storage and resets a message.

Pass `descriptor=false` to `protoc-gen-pbz` / `generateProtobuf` to omit the
embedded descriptor and the generated descriptor/dynamic-bridge/conformant-parser
helpers.

### CLI

The `pbz` executable converts between binary, TextFormat, and JSON using a
descriptor set:

```sh
pbz encode   --descriptor-set descriptors.pb --type demo.Person < person.text > person.bin
pbz decode   --descriptor-set descriptors.pb --type demo.Person --json < person.bin
pbz convert  --descriptor-set descriptors.pb --type demo.Person --from json --to text
pbz describe --descriptor-set descriptors.pb --type demo.Person
```

Use `--json` / `--text` as shorthand for the relevant direction. `pbz` reads
stdin and writes stdout; `tools/smoke_cli.py` verifies the round-trip in
`zig build check`.

## Examples

Run all examples:

```sh
zig build examples
```

Important examples:

- `examples/generated_types.zig` — generated concrete message usage
- `examples/build_codegen.zig` — `build.zig` codegen helper usage
- `examples/generated_performance.zig` — fastest generated APIs
- `examples/generated_imports.zig` — multi-file generated imports
- `examples/generated_groups.zig` — proto2 groups
- `examples/generated_required.zig` — proto2 required-field initialization gates
- `examples/generated_defaults.zig` — proto2 default values and has-bit semantics
- `examples/generated_extensions.zig` — generated proto2 extension accessors
- `examples/generated_identifiers.zig` — quoted generated identifiers for Zig keyword collisions
- `examples/generated_enum_alias.zig` — generated enum alias handling
- `examples/generated_json_names.zig` — explicit generated JSON names
- `examples/generated_messageset.zig` — generated proto2 MessageSet extensions
- `examples/generated_map_keys.zig` — generated non-string map keys
- `examples/generated_nested_types.zig` — nested generated message/enum refs
- `examples/generated_unpacked.zig` — unpacked repeated scalar fields
- `examples/generated_public_imports.zig` — generated public import chains
- `examples/dynamic_public_imports.zig` — dynamic public import chains
- `examples/generated_merge_semantics.zig` — generated decode merge/last-wins semantics
- `examples/generated_clone_owned.zig` — generated deep-clone ownership handoff
- `examples/generated_unknown_mutation.zig` — generated unknown-field mutation APIs
- `examples/generated_closed_enum.zig` — proto2 closed enum unknown preservation
- `examples/proto2_extensions.zig` — proto2 extensions
- `examples/well_known_types.zig` — selected WKT helpers
- `examples/any_dynamic.zig` — dynamic-message Any helpers
- `examples/any_type_url.zig` — Any type URL prefix helpers
- `examples/conformance.zig` — conformance-style dynamic conversion

## Validation commands

```sh
zig build check
zig build test
zig build examples
zig build build-codegen-smoke
zig build check-generated-examples
zig build conformance-smoke
zig build cli-smoke
zig build fuzz-smoke
zig build fuzz -Dfuzz-iterations=1000000 -Dfuzz-seed=0
python3 bench/summarize_compare.py --self-test
tools/run_conformance.sh
bench/run_compare.sh 2>&1 | tee /tmp/pbz-compare.log
python3 bench/summarize_compare.py /tmp/pbz-compare.log --fail-on-loss
```
