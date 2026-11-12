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
  UTF-8 validation, and enum openness behavior
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
  generated `Person` decode/encode plus `decodeReuse`/`decodeOwnedReuse`, with a
  short seed-0 pass wired into `zig build check`

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

Latest accepted local results (protobuf 35.1):

```text
# dynamic path
CONFORMANCE SUITE PASSED: 2808 successes, 0 skipped, 0 expected failures, 0 unexpected failures.
CONFORMANCE SUITE PASSED: 445 successes, 0 skipped, 0 expected failures, 0 unexpected failures.

# generated path
CONFORMANCE SUITE PASSED: 2808 successes, 0 skipped, 0 expected failures, 0 unexpected failures.
CONFORMANCE SUITE PASSED: 445 successes, 0 skipped, 0 expected failures, 0 unexpected failures.
```

The generated path decodes binary requests with generated types, encodes them,
and normalizes the response through the registry-aware dynamic encoder so
canonical byte layout matches the reference for cyclic raw fields and unknown
field ordering.

A lightweight smoke test is also available:

```sh
python3 tools/smoke_conformance.py
```

### Performance

Run pbz's local benchmark:

```sh
zig build bench -Doptimize=ReleaseFast
```

Run pbz plus Rust `prost`, Rust `quick-protobuf`, C++ protobuf, and Go protobuf
baselines in one pinned session:

```sh
PBZ_COMPARE_CPUSET=3 PBZ_COMPARE_LATEST_CPP=1 bench/run_compare.sh 2>&1 | tee /tmp/pbz-compare.log
python3 bench/summarize_compare.py /tmp/pbz-compare.log --fail-on-loss
python3 bench/summarize_compare.py /tmp/pbz-compare.log --pivot --exclude-zero-copy > /tmp/pbz-compare-fair.md
```

`PBZ_COMPARE_LATEST_CPP=1` builds the full C++ benchmark against the protobuf
release used by the upstream conformance suite (default 35.1) instead of the
system libprotobuf. The compare script derives `GOMAXPROCS` from the CPU set
when it is not already set.

The default summary selects the fastest public pbz path, which can include
zero-copy borrowed slices/views for `largebytes`, packed fixed-width, and
borrowed-decode rows. Those rows are useful for scatter/gather I/O but are not
semantically identical to a baseline that materializes/copies the payload. Use
`--exclude-zero-copy` to prefer owning/contiguous paths (`decode owned`,
`decode owned reuse`, contiguous encode/decode) and exclude borrowed
slice/view rows.

Latest snapshot (`bench/results/2026-11-12-linux-x86_64.md`), fair mode,
pinned to one CPU on an i9-13900K. Baseline cells show
`ns/op (baseline / pbz)`; ratios above 1.0 mean pbz is faster.

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf 35.1 | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 18.25 | 84.38 (4.62x) | 50.20 (2.75x) | 74.45 (4.08x) | 858.58 (47.05x) |
| binary decode | 125.44 | 251.13 (2.00x) | 242.24 (1.93x) | 189.78 (1.51x) | 912.61 (7.28x) |
| deterministic binary encode | 50.35 | — | — | 104.78 (2.08x) | 1144.91 (22.74x) |
| unknown fields count by number | 3.57 | — | — | 280.67 (78.62x) | — |
| scalarmix encode | 18.79 | 84.31 (4.49x) | 49.09 (2.61x) | 28.60 (1.52x) | 217.33 (11.57x) |
| scalarmix decode | 42.12 | 145.51 (3.45x) | 174.04 (4.13x) | 65.30 (1.55x) | 319.59 (7.59x) |
| textbytes encode | 23.00 | 76.12 (3.31x) | 34.75 (1.51x) | 68.63 (2.98x) | 141.64 (6.16x) |
| textbytes decode | 77.36 | 369.91 (4.78x) | 242.13 (3.13x) | 167.29 (2.16x) | 671.85 (8.68x) |
| largebytes encode | 2476.54 | 2674.58 (1.08x) | 2666.69 (1.08x) | 2626.85 (1.06x) | 2811.21 (1.14x) |
| largebytes decode | 2632.61 | 5347.66 (2.03x) | 3012.32 (1.14x) | 4061.80 (1.54x) | 21593.16 (8.20x) |
| presencemix encode | 17.67 | 53.62 (3.03x) | 27.43 (1.55x) | 47.50 (2.69x) | 228.09 (12.91x) |
| presencemix decode | 97.16 | 131.46 (1.35x) | 111.70 (1.15x) | 122.19 (1.26x) | 494.53 (5.09x) |
| complex encode | 48.47 | 128.09 (2.64x) | 99.79 (2.06x) | 135.44 (2.79x) | 894.03 (18.45x) |
| complex decode | 286.94 | 406.41 (1.42x) | 352.15 (1.23x) | 340.64 (1.19x) | 1370.20 (4.78x) |
| complex deterministic binary encode | 95.95 | — | — | 157.98 (1.65x) | 1150.73 (11.99x) |
| packed int32 encode | 621.06 | 3184.99 (5.13x) | 2296.32 (3.70x) | 1165.70 (1.88x) | 2874.61 (4.63x) |
| packed int32 decode | 695.44 | 1885.99 (2.71x) | 3513.84 (5.05x) | 1322.70 (1.90x) | 2589.56 (3.72x) |
| packed fixed32 encode | 34.95 | 549.91 (15.73x) | 543.70 (15.56x) | 38.67 (1.11x) | 394.11 (11.28x) |
| packed fixed32 decode | 34.63 | 1032.85 (29.83x) | 1826.89 (52.75x) | 44.69 (1.29x) | 1567.65 (45.27x) |
| packed fixed64 encode | 62.11 | 573.11 (9.23x) | 560.47 (9.02x) | 62.34 (1.00x) | 402.13 (6.47x) |
| packed fixed64 decode | 65.43 | 1014.76 (15.51x) | 1918.14 (29.32x) | 68.89 (1.05x) | 2219.62 (33.92x) |
| packed bool encode | 14.18 | 1309.86 (92.37x) | 517.40 (36.49x) | 11.42 (0.81x) | 2223.31 (156.79x) |
| packed bool decode | 28.73 | 1619.61 (56.37x) | 3039.40 (105.79x) | 55.93 (1.95x) | 1602.39 (55.77x) |
| packed enum encode | 272.20 | 2707.19 (9.95x) | 1807.00 (6.64x) | 915.01 (3.36x) | 2484.29 (9.13x) |
| packed enum decode | 159.51 | 1592.64 (9.98x) | 3051.64 (19.13x) | 272.08 (1.71x) | 2067.28 (12.96x) |
| large map encode | 4079.98 | 16748.71 (4.11x) | 9158.25 (2.24x) | 12253.70 (3.00x) | 203890.55 (49.97x) |
| large map decode | 35730.92 | 92534.54 (2.59x) | 90704.88 (2.54x) | 47440.10 (1.33x) | 267877.37 (7.50x) |
| ScalarMix JSON stringify | 355.16 | — | — | 2639.36 (7.43x) | 3753.36 (10.57x) |
| ScalarMix JSON parse | 2730.46 | — | — | 7042.65 (2.58x) | 8260.21 (3.03x) |
| TextBytes JSON stringify | 335.04 | — | — | 1189.71 (3.55x) | 2293.77 (6.85x) |
| TextBytes JSON parse | 1310.56 | — | — | 3555.13 (2.71x) | 4002.98 (3.05x) |
| complex JSON stringify | 313.99 | — | — | 2925.11 (9.32x) | 6174.99 (19.67x) |
| complex JSON parse | 2342.86 | — | — | 6811.85 (2.91x) | 7606.56 (3.25x) |
| LargeMap JSON stringify | 22343.15 | — | — | 133940.00 (5.99x) | 744286.28 (33.31x) |
| LargeMap JSON parse | 167724.90 | — | — | 492421.00 (2.94x) | 540464.98 (3.22x) |
| TextFormat format | 196.62 | — | — | 1543.67 (7.85x) | 2564.04 (13.04x) |
| TextFormat parse | 776.78 | — | — | 3781.24 (4.87x) | 6660.10 (8.57x) |
| complex TextFormat format | 280.05 | — | — | 2472.90 (8.83x) | 5435.66 (19.41x) |
| complex TextFormat parse | 1845.00 | — | — | 5040.36 (2.73x) | 8525.87 (4.62x) |

In mixed mode every parsed cross-language row is a pbz win. In fair mode the
only residual gaps are two 64-bit packed encode rows within 0.5% (run-to-run
noise) and packed bool encode at 14.18 ns vs 11.42 ns. See the results snapshot
for the full table and the exact commands.

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
