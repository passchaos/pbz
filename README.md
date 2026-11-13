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
descriptor set for that corpus with zero errors, preserving visibility,
map-entry `json_name`, `packed = false`, proto2 oneof defaults, original
`default_value` text, unknown custom option/feature payloads, and nested-type
ordering; all 161 re-encoded sets are text-identical to protoc's after
removing only empty `options {}`/`features {}` blocks. `LoadOptions.validate_custom_options`
opts into protoc-parity option validation: over the same corpus it accepts and
rejects exactly the same 161/22 files as protoc, including nested extension
paths and unknown plain option names.

A lightweight smoke test is also available:

```sh
python3 tools/smoke_conformance.py
```

The corpus differential compares source parsing, strict option validation, and
`FileDescriptorSet` round-trips against the pinned protoc (default 36.2):

```sh
tools/run_corpus_differential.sh
```

It currently reports zero parser false rejections, exact strict-option parity
(161 accepted / 22 rejected), and zero descriptor round-trip errors or text
differences across the 183-file protobuf corpus.

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

Latest accepted cross-language matrix (`bench/results/2026-11-12-linux-x86_64.md`):
protobuf 36.2 C++/upb baselines, three full-matrix rounds with the same binaries
interleaved on one pinned core and merged per row. Fair mode
(`--exclude-zero-copy`); baseline cells show `ns/op (baseline / pbz)`, and
ratios above 1.0 mean pbz is faster. Mixed mode reports every parsed row as a
pbz win.

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf 36.2 | upb protobuf 36.2 | Go protobuf |
|---|---:|---:|---:|---:|---:|---:|
| binary encode | 24.06 | 129.26 (5.37x) | 55.98 (2.33x) | 85.25 (3.54x) | 151.20 (6.28x) | 966.85 (40.18x) |
| binary decode | 185.50 | 295.16 (1.59x) | 299.11 (1.61x) | 217.41 (1.17x) | 279.67 (1.51x) | 985.11 (5.31x) |
| unknown fields count by number | 5.02 | — | — | 212.52 (42.33x) | 2976.80 (592.99x) | — |
| deterministic binary encode | 66.77 | — | — | 127.05 (1.90x) | 188.26 (2.82x) | 1235.75 (18.51x) |
| scalarmix encode | 25.31 | 110.35 (4.36x) | 63.50 (2.51x) | 40.59 (1.60x) | 214.22 (8.46x) | 237.33 (9.38x) |
| scalarmix decode | 59.47 | 166.78 (2.80x) | 204.90 (3.45x) | 84.57 (1.42x) | 202.15 (3.40x) | 352.84 (5.93x) |
| ScalarMix JSON parse | 1500.74 | — | — | 6639.88 (4.42x) | 1589.61 (1.06x) | 10295.65 (6.86x) |
| textbytes encode | 26.82 | 88.34 (3.29x) | 46.23 (1.72x) | 87.66 (3.27x) | 117.49 (4.38x) | 169.63 (6.32x) |
| textbytes decode | 105.45 | 471.25 (4.47x) | 304.06 (2.88x) | 193.99 (1.84x) | 206.88 (1.96x) | 800.07 (7.59x) |
| TextBytes JSON parse | 634.63 | — | — | 3014.86 (4.75x) | 707.81 (1.12x) | 4889.22 (7.70x) |
| largebytes encode | 3751.04 | 3870.94 (1.03x) | 3794.05 (1.01x) | 3821.57 (1.02x) | 74745.70 (19.93x) | 4109.61 (1.10x) |
| largebytes decode (owned) | 5721.42 | 8402.14 (1.47x) | 4508.43 (0.79x) | 3996.86 (0.70x) | 4472.91 (0.78x) | 24615.47 (4.30x) |
| presencemix encode | 23.81 | 61.84 (2.60x) | 38.49 (1.62x) | 51.98 (2.18x) | 134.50 (5.65x) | 255.27 (10.72x) |
| presencemix decode | 115.00 | 163.64 (1.42x) | 130.64 (1.14x) | 138.45 (1.20x) | 148.59 (1.29x) | 551.75 (4.80x) |
| complex encode | 65.00 | 159.66 (2.46x) | 117.64 (1.81x) | 149.79 (2.30x) | 294.13 (4.53x) | 940.94 (14.48x) |
| complex decode | 327.78 | 455.12 (1.39x) | 424.38 (1.29x) | 386.70 (1.18x) | 423.41 (1.29x) | 1583.42 (4.83x) |
| complex JSON parse | 1108.62 | — | — | 6739.92 (6.08x) | 1318.11 (1.19x) | 9928.83 (8.96x) |
| packed int32 encode | 894.32 | 5387.80 (6.02x) | 2765.05 (3.09x) | 2205.70 (2.47x) | 4845.80 (5.42x) | 5697.26 (6.37x) |
| packed int32 decode | 1026.95 | 2527.77 (2.46x) | 4223.35 (4.11x) | 1340.86 (1.31x) | 3668.40 (3.57x) | 4361.62 (4.25x) |
| packed fixed64 encode | 153.11 | 705.90 (4.61x) | 630.06 (4.12x) | 153.36 (1.00x) | 581.57 (3.80x) | 569.60 (3.72x) |
| packed fixed64 decode | 148.49 | 2008.12 (13.52x) | 2760.41 (18.59x) | 159.15 (1.07x) | 224.93 (1.51x) | 3243.03 (21.84x) |
| packed bool encode | 17.60 | 2078.60 (118.10x) | 538.13 (30.58x) | 19.54 (1.11x) | 592.58 (33.67x) | 4377.09 (248.70x) |
| packed bool decode | 39.62 | 2289.98 (57.80x) | 3843.66 (97.01x) | 83.84 (2.12x) | 2464.05 (62.19x) | 2644.53 (66.75x) |
| packed enum encode | 555.99 | 4918.71 (8.85x) | 2329.29 (4.19x) | 1617.76 (2.91x) | 705.96 (1.27x) | 5018.36 (9.03x) |
| packed enum decode | 274.65 | 2070.18 (7.54x) | 3889.52 (14.16x) | 428.57 (1.56x) | 2051.13 (7.47x) | 3207.56 (11.68x) |
| large map encode | 5450.02 | 21817.21 (4.00x) | 12580.38 (2.31x) | 20206.60 (3.71x) | 31772.00 (5.83x) | 240231.57 (44.08x) |
| large map decode | 50109.12 | 125988.28 (2.51x) | 130775.34 (2.61x) | 61195.00 (1.22x) | 98899.60 (1.97x) | 293631.16 (5.86x) |
| LargeMap JSON parse | 116392.06 | — | — | 396769.00 (3.41x) | 150001.00 (1.29x) | 579789.17 (4.98x) |
| TextFormat format | 244.99 | — | — | 2230.05 (9.10x) | — | 3079.75 (12.57x) |
| TextFormat parse | 924.67 | — | — | 4526.37 (4.90x) | — | 7877.02 (8.52x) |
| complex TextFormat format | 348.77 | — | — | 3366.98 (9.65x) | — | 6591.81 (18.90x) |
| complex TextFormat parse | 2297.45 | — | — | 5846.06 (2.54x) | — | 11307.97 (4.92x) |

Every binary/TextFormat/JSON row is a pbz win against the 36.2 baselines
except the close or core-sensitive cells below:

- `packed fixed64/sfixed64/double encode` are 0.97-1.00x vs C++ (inside the
  1-3% run-to-run spread on this shared machine).
- `largebytes decode (owned)` is 0.70-0.79x on the pinned E-core because
  `rep movsb` is slower than libc memcpy there; on a P-core the same fixture
  measures 2765 ns for pbz vs 4865 ns for C++ 36.2 (1.76x) and 2740 ns for
  upb 36.2 (1.01x). The ERMS range now starts at 8 KiB so 2-8 KiB copies use
  the vector loop, which is within 4-16% of libc on E-cores and faster on
  P-cores.

The earlier TextBytes JSON parse gap is closed: the benchmark row now measures
634.63 ns vs upb 36.2 at 707.81 ns (1.12x) after replacing the two-pass
per-byte base64 decoder with a single table-driven pass; the focused
`json-probe` TextBytes row dropped from ~1085 ns to ~505 ns. Generated JSON
parse uses the lean `src/json_value.zig` tree, rejects duplicate spellings,
oneof members, and extension keys, emits canonical WKT JSON, and the opt-in
`PBZ_CONFORMANCE_GENERATED_JSON=1` audit passes 2817/2817 plus 445/445
TextFormat. The full fair-mode table, the upb comparison, the noise caveat, and
the exact commands are in the results snapshot.

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
