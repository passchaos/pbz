# pbz

`pbz` is a pure Zig Protocol Buffers toolkit for Zig 0.16.0.

It provides:

- protobuf wire encode/decode runtime
- `.proto` parser, descriptor model, descriptor set encode/decode
- multi-file registry/import loader
- dynamic messages
- reflection facade over registry descriptors and dynamic messages
- generated Zig message types through `protoc-gen-pbz`
- JSON and TextFormat support
- selected well-known types
- upstream protobuf conformance runner integration
- generated-code performance paths intended to beat common C++/Rust/Go protobuf implementations on covered workloads

## Current status

### Functionality

The current implementation covers the protobuf surfaces used by the examples,
benchmarks, and upstream conformance suite:

- proto2, proto3, and protobuf editions metadata/features used by the test set
- scalar fields, repeated fields, packed fields, maps, nested messages, groups,
  oneof, proto3 optional, required-field validation
- unknown field preservation, deterministic encoding, MessageSet support, and
  proto2 extensions
- descriptor and descriptor-set workflows
- reflection helpers for runtime message creation, field lookup, typed
  get/set/add/clear, repeated fields, maps, and oneof inspection
- generated Zig structs with public fields and package-mirrored namespaces
- generated imports, generated enum helpers, service metadata, and lightweight
  service client/handler adapters
- dynamic JSON and TextFormat parse/format
- WKT JSON/wire helpers for Timestamp, Duration, FieldMask, Any, Empty,
  Struct/Value/ListValue, and wrappers

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

Latest accepted local result:

```text
CONFORMANCE SUITE PASSED: 2808 successes, 0 skipped, 0 expected failures, 0 unexpected failures.
CONFORMANCE SUITE PASSED: 445 successes, 0 skipped, 0 expected failures, 0 unexpected failures.
```

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
baselines when those toolchains are available:

```sh
bench/run_compare.sh 2>&1 | tee /tmp/pbz-compare.log
python3 bench/summarize_compare.py --fail-on-loss /tmp/pbz-compare.log
```

Latest accepted comparison (`/tmp/pbz-compare-after-nested-any-json-isolated.log`,
summarized in `/tmp/pbz-summary-after-nested-any-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 17.88 | 101.84 (5.70x) | 53.38 (2.99x) | 102.33 (5.72x) | 869.20 (48.61x) |
| binary decode | 93.34 | 251.50 (2.69x) | 235.29 (2.52x) | 220.13 (2.36x) | 897.36 (9.61x) |
| unknown count by number | 3.62 | — | — | 150.70 (41.63x) | — |
| scalarmix encode | 18.88 | 118.02 (6.25x) | 50.48 (2.67x) | 28.81 (1.53x) | 216.62 (11.47x) |
| scalarmix decode | 39.22 | 137.16 (3.50x) | 184.96 (4.72x) | 79.87 (2.04x) | 305.89 (7.80x) |
| textbytes encode | 9.03 | 76.68 (8.49x) | 33.69 (3.73x) | 117.08 (12.97x) | 153.39 (16.99x) |
| complex decode | 173.64 | 396.55 (2.28x) | 337.60 (1.94x) | 388.00 (2.23x) | 1351.18 (7.78x) |
| complex JSON parse | 2376.60 | — | — | 11872.50 (5.00x) | 7647.18 (3.22x) |
| Any WKT JSON stringify | 132.40 | — | — | 1894.51 (14.31x) | 997.91 (7.54x) |
| Any WKT JSON parse | 517.30 | — | — | 2993.48 (5.79x) | 1540.81 (2.98x) |
| Any Struct WKT JSON stringify | 609.17 | — | — | 5848.81 (9.60x) | 6063.06 (9.95x) |
| Any Struct WKT JSON parse | 1760.95 | — | — | 11192.50 (6.36x) | 8774.40 (4.98x) |
| Any Value WKT JSON stringify | 635.64 | — | — | 5960.69 (9.38x) | 6451.74 (10.15x) |
| Any Value WKT JSON parse | 1819.88 | — | — | 11365.10 (6.24x) | 9147.32 (5.03x) |
| Any StringValue WKT JSON stringify | 169.36 | — | — | 1558.15 (9.20x) | 821.59 (4.85x) |
| Any StringValue WKT JSON parse | 553.79 | — | — | 2669.22 (4.82x) | 1462.00 (2.64x) |
| Nested Any WKT JSON stringify | 270.94 | — | — | 2468.22 (9.11x) | 1447.63 (5.34x) |
| Nested Any WKT JSON parse | 869.03 | — | — | 4275.02 (4.92x) | 2885.28 (3.32x) |
| Duration JSON stringify | 57.47 | — | — | 965.27 (16.80x) | 365.56 (6.36x) |
| Duration JSON parse | 8.53 | — | — | 1465.84 (171.85x) | 410.41 (48.11x) |
| FieldMask JSON stringify | 90.31 | — | — | 888.17 (9.83x) | 659.68 (7.30x) |
| FieldMask JSON parse | 146.21 | — | — | 1668.43 (11.41x) | 932.01 (6.37x) |
| Timestamp JSON stringify | 95.04 | — | — | 1135.70 (11.95x) | 418.56 (4.40x) |
| Timestamp JSON parse | 41.46 | — | — | 1498.86 (36.15x) | 449.69 (10.85x) |
| Empty JSON stringify | 20.32 | — | — | 495.53 (24.39x) | 80.50 (3.96x) |
| Empty JSON parse | 67.22 | — | — | 721.81 (10.74x) | 209.00 (3.11x) |
| Struct JSON stringify | 193.76 | — | — | 5770.83 (29.78x) | 3079.27 (15.89x) |
| Struct JSON parse | 844.11 | — | — | 10960.00 (12.98x) | 4700.54 (5.57x) |
| Value JSON stringify | 187.95 | — | — | 6617.56 (35.21x) | 3245.02 (17.27x) |
| Value JSON parse | 869.33 | — | — | 12229.00 (14.07x) | 4962.72 (5.71x) |
| ListValue JSON stringify | 140.75 | — | — | 4763.07 (33.84x) | 2126.70 (15.11x) |
| ListValue JSON parse | 662.71 | — | — | 8550.33 (12.90x) | 3821.62 (5.77x) |
| DoubleValue JSON stringify | 59.05 | — | — | 855.46 (14.49x) | 197.32 (3.34x) |
| DoubleValue JSON parse | 110.17 | — | — | 1233.15 (11.19x) | 292.10 (2.65x) |
| FloatValue JSON stringify | 69.58 | — | — | 816.85 (11.74x) | 187.88 (2.70x) |
| FloatValue JSON parse | 110.18 | — | — | 1223.71 (11.11x) | 302.99 (2.75x) |
| Int64Value JSON stringify | 39.96 | — | — | 680.73 (17.04x) | 284.93 (7.13x) |
| Int64Value JSON parse | 126.68 | — | — | 1243.75 (9.82x) | 461.47 (3.64x) |
| UInt64Value JSON stringify | 40.14 | — | — | 680.02 (16.94x) | 282.68 (7.04x) |
| UInt64Value JSON parse | 125.86 | — | — | 1232.84 (9.80x) | 465.81 (3.70x) |
| Int32Value JSON stringify | 42.75 | — | — | 639.14 (14.95x) | 138.40 (3.24x) |
| Int32Value JSON parse | 128.61 | — | — | 1195.14 (9.29x) | 319.59 (2.48x) |
| UInt32Value JSON stringify | 42.75 | — | — | 638.85 (14.94x) | 140.07 (3.28x) |
| UInt32Value JSON parse | 128.89 | — | — | 1200.79 (9.32x) | 312.60 (2.43x) |
| BoolValue JSON stringify | 40.93 | — | — | 632.73 (15.46x) | 124.52 (3.04x) |
| BoolValue JSON parse | 60.90 | — | — | 1075.72 (17.66x) | 224.13 (3.68x) |
| StringValue JSON stringify | 47.70 | — | — | 669.24 (14.03x) | 189.68 (3.98x) |
| StringValue JSON parse | 135.71 | — | — | 1158.43 (8.54x) | 316.84 (2.33x) |
| BytesValue JSON stringify | 48.09 | — | — | 674.58 (14.03x) | 210.83 (4.38x) |
| BytesValue JSON parse | 148.69 | — | — | 1186.92 (7.98x) | 356.80 (2.40x) |
| TextFormat parse | 677.94 | — | — | 4977.73 (7.34x) | 6577.62 (9.70x) |
| packed int32 decode | 763.86 | 1898.90 (2.49x) | 3216.28 (4.21x) | 974.38 (1.28x) | 2554.62 (3.34x) |
| packed bool encode | 2.01 | 1319.45 (656.44x) | 518.92 (258.17x) | 15.75 (7.84x) | 2216.90 (1102.94x) |
| packed bool decode | 263.34 | 1534.78 (5.83x) | 2548.70 (9.68x) | 810.30 (3.08x) | 1563.75 (5.94x) |
| largebytes decode | 89.71 | 5546.94 (61.83x) | 3030.69 (33.78x) | 2723.70 (30.36x) | 20114.02 (224.21x) |
| large map decode | 25629.02 | 90533.24 (3.53x) | 89664.21 (3.50x) | 87143.00 (3.40x) | 264636.29 (10.33x) |
| shuffled large map deterministic binary encode | 28424.07 | — | — | 93105.30 (3.28x) | 444198.62 (15.63x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded `Duration`, `Struct`, `Value`,
`StringValue`, and recursive nested `Any` payloads), direct WKT JSON, TextFormat, packed scalars, large bytes,
maps, oneof/optional workloads, and complex nested messages. Benchmark results are hardware-sensitive; compare full same-machine
runs rather than individual copied rows.

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
- `examples/proto2_extensions.zig` — proto2 extensions
- `examples/well_known_types.zig` — selected WKT helpers
- `examples/conformance.zig` — conformance-style dynamic conversion

## Validation commands

```sh
zig build check
zig build test
zig build examples
zig build build-codegen-smoke
zig build conformance-smoke
python3 bench/summarize_compare.py --self-test
tools/run_conformance.sh
bench/run_compare.sh 2>&1 | tee /tmp/pbz-compare.log
python3 bench/summarize_compare.py --fail-on-loss /tmp/pbz-compare.log
```
