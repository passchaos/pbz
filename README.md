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

Latest accepted comparison (`/tmp/pbz-compare-after-any-float-json-isolated.log`,
summarized in `/tmp/pbz-summary-after-any-float-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 24.82 | 125.15 (5.04x) | 62.17 (2.50x) | 127.76 (5.15x) | 948.92 (38.23x) |
| binary decode | 137.76 | 295.86 (2.15x) | 304.52 (2.21x) | 271.35 (1.97x) | 983.79 (7.14x) |
| unknown count by number | 5.02 | — | — | 213.12 (42.45x) | — |
| scalarmix encode | 27.11 | 113.35 (4.18x) | 65.94 (2.43x) | 45.48 (1.68x) | 239.27 (8.83x) |
| scalarmix decode | 50.32 | 163.57 (3.25x) | 218.77 (4.35x) | 112.29 (2.23x) | 360.48 (7.16x) |
| textbytes encode | 13.44 | 93.09 (6.93x) | 43.22 (3.22x) | 148.20 (11.03x) | 171.19 (12.74x) |
| complex decode | 231.76 | 461.35 (1.99x) | 426.88 (1.84x) | 486.70 (2.10x) | 1622.11 (7.00x) |
| complex JSON parse | 2747.59 | — | — | 16769.30 (6.10x) | 10507.47 (3.82x) |
| Any WKT JSON stringify | 182.01 | — | — | 3027.01 (16.63x) | 1345.81 (7.39x) |
| Any WKT JSON parse | 567.46 | — | — | 4566.83 (8.05x) | 2075.59 (3.66x) |
| Any FieldMask WKT JSON stringify | 284.01 | — | — | 2414.67 (8.50x) | 1744.87 (6.14x) |
| Any FieldMask WKT JSON parse | 787.99 | — | — | 4902.14 (6.22x) | 2904.33 (3.69x) |
| Any Timestamp WKT JSON stringify | 237.56 | — | — | 2986.63 (12.57x) | 1322.05 (5.57x) |
| Any Timestamp WKT JSON parse | 632.79 | — | — | 4591.74 (7.26x) | 2234.71 (3.53x) |
| Any Empty WKT JSON stringify | 115.85 | — | — | 1301.06 (11.23x) | 647.34 (5.59x) |
| Any Empty WKT JSON parse | 371.58 | — | — | 3070.18 (8.26x) | 1620.44 (4.36x) |
| Any Struct WKT JSON stringify | 763.11 | — | — | 8918.63 (11.69x) | 8872.27 (11.63x) |
| Any Struct WKT JSON parse | 1953.39 | — | — | 16574.30 (8.48x) | 12515.72 (6.41x) |
| Any Value WKT JSON stringify | 802.22 | — | — | 9006.72 (11.23x) | 9440.89 (11.77x) |
| Any Value WKT JSON parse | 2018.88 | — | — | 16804.60 (8.32x) | 13049.26 (6.46x) |
| Any DoubleValue WKT JSON stringify | 243.88 | — | — | 2863.36 (11.74x) | 880.14 (3.61x) |
| Any DoubleValue WKT JSON parse | 568.84 | — | — | 4388.96 (7.72x) | 1982.78 (3.49x) |
| Any FloatValue WKT JSON stringify | 251.46 | — | — | 2759.72 (10.97x) | 863.48 (3.43x) |
| Any FloatValue WKT JSON parse | 567.60 | — | — | 4334.66 (7.64x) | 1895.62 (3.34x) |
| Any Int64Value WKT JSON stringify | 203.00 | — | — | 2177.36 (10.73x) | 1122.65 (5.53x) |
| Any Int64Value WKT JSON parse | 618.00 | — | — | 4265.03 (6.90x) | 2375.53 (3.84x) |
| Any UInt64Value WKT JSON stringify | 209.18 | — | — | 2188.62 (10.46x) | 1134.72 (5.42x) |
| Any UInt64Value WKT JSON parse | 625.13 | — | — | 4302.06 (6.88x) | 2248.27 (3.60x) |
| Any BoolValue WKT JSON stringify | 207.56 | — | — | 2102.98 (10.13x) | 807.39 (3.89x) |
| Any BoolValue WKT JSON parse | 540.92 | — | — | 4034.00 (7.46x) | 1770.52 (3.27x) |
| Any StringValue WKT JSON stringify | 234.90 | — | — | 2215.36 (9.43x) | 889.24 (3.79x) |
| Any StringValue WKT JSON parse | 607.12 | — | — | 4038.57 (6.65x) | 1907.01 (3.14x) |
| Any BytesValue WKT JSON stringify | 224.37 | — | — | 2243.80 (10.00x) | 916.02 (4.08x) |
| Any BytesValue WKT JSON parse | 615.74 | — | — | 4244.74 (6.89x) | 2023.00 (3.29x) |
| Nested Any WKT JSON stringify | 359.40 | — | — | 3397.22 (9.45x) | 1570.35 (4.37x) |
| Nested Any WKT JSON parse | 997.26 | — | — | 6136.51 (6.15x) | 3564.24 (3.57x) |
| Duration JSON stringify | 63.13 | — | — | 1530.47 (24.24x) | 380.49 (6.03x) |
| Duration JSON parse | 11.67 | — | — | 2296.01 (196.74x) | 425.49 (36.46x) |
| FieldMask JSON stringify | 92.87 | — | — | 1300.48 (14.00x) | 725.59 (7.81x) |
| FieldMask JSON parse | 181.29 | — | — | 2653.74 (14.64x) | 1074.25 (5.93x) |
| Timestamp JSON stringify | 125.16 | — | — | 1715.14 (13.70x) | 460.92 (3.68x) |
| Timestamp JSON parse | 57.03 | — | — | 2305.01 (40.42x) | 475.51 (8.34x) |
| Empty JSON stringify | 22.14 | — | — | 684.32 (30.91x) | 100.79 (4.55x) |
| Empty JSON parse | 75.02 | — | — | 1092.07 (14.56x) | 245.11 (3.27x) |
| Struct JSON stringify | 258.81 | — | — | 8891.98 (34.36x) | 4159.38 (16.07x) |
| Struct JSON parse | 963.06 | — | — | 16838.60 (17.48x) | 6326.96 (6.57x) |
| Value JSON stringify | 263.80 | — | — | 9772.71 (37.05x) | 4363.14 (16.54x) |
| Value JSON parse | 962.16 | — | — | 17577.00 (18.27x) | 6664.88 (6.93x) |
| ListValue JSON stringify | 195.69 | — | — | 7549.73 (38.58x) | 2818.85 (14.40x) |
| ListValue JSON parse | 754.46 | — | — | 13583.10 (18.00x) | 5243.62 (6.95x) |
| DoubleValue JSON stringify | 74.68 | — | — | 1483.19 (19.86x) | 198.26 (2.65x) |
| DoubleValue JSON parse | 115.09 | — | — | 2104.68 (18.29x) | 330.57 (2.87x) |
| FloatValue JSON stringify | 98.82 | — | — | 1403.95 (14.21x) | 191.86 (1.94x) |
| FloatValue JSON parse | 112.79 | — | — | 2128.86 (18.87x) | 309.95 (2.75x) |
| Int64Value JSON stringify | 42.04 | — | — | 1011.32 (24.06x) | 289.39 (6.88x) |
| Int64Value JSON parse | 137.87 | — | — | 1996.18 (14.48x) | 503.11 (3.65x) |
| UInt64Value JSON stringify | 42.05 | — | — | 997.05 (23.71x) | 293.93 (6.99x) |
| UInt64Value JSON parse | 138.37 | — | — | 1941.29 (14.03x) | 505.39 (3.65x) |
| Int32Value JSON stringify | 45.58 | — | — | 954.46 (20.94x) | 145.23 (3.19x) |
| Int32Value JSON parse | 133.34 | — | — | 1898.40 (14.24x) | 343.72 (2.58x) |
| UInt32Value JSON stringify | 45.34 | — | — | 912.46 (20.12x) | 154.28 (3.40x) |
| UInt32Value JSON parse | 133.38 | — | — | 1922.97 (14.42x) | 351.07 (2.63x) |
| BoolValue JSON stringify | 42.77 | — | — | 902.43 (21.10x) | 137.32 (3.21x) |
| BoolValue JSON parse | 54.85 | — | — | 1679.55 (30.62x) | 257.17 (4.69x) |
| StringValue JSON stringify | 53.93 | — | — | 1000.54 (18.55x) | 191.44 (3.55x) |
| StringValue JSON parse | 131.72 | — | — | 1811.61 (13.75x) | 364.78 (2.77x) |
| BytesValue JSON stringify | 48.51 | — | — | 973.75 (20.07x) | 225.07 (4.64x) |
| BytesValue JSON parse | 137.68 | — | — | 1967.61 (14.29x) | 373.37 (2.71x) |
| TextFormat parse | 846.96 | — | — | 5439.05 (6.42x) | 8003.99 (9.45x) |
| packed int32 decode | 1032.93 | 2971.54 (2.88x) | 4230.97 (4.10x) | 1341.72 (1.30x) | 4349.45 (4.21x) |
| packed bool encode | 2.38 | 2079.07 (873.56x) | 540.47 (227.09x) | 22.68 (9.53x) | 4385.95 (1842.84x) |
| packed bool decode | 271.50 | 2060.87 (7.59x) | 3892.66 (14.34x) | 1108.39 (4.08x) | 2692.19 (9.92x) |
| largebytes decode | 124.75 | 8399.67 (67.33x) | 4579.67 (36.71x) | 4014.29 (32.18x) | 23585.57 (189.06x) |
| large map decode | 37742.36 | 130420.83 (3.46x) | 127393.18 (3.38x) | 123082.00 (3.26x) | 294106.00 (7.79x) |
| shuffled large map deterministic binary encode | 36034.06 | — | — | 117062.00 (3.25x) | 455512.22 (12.64x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded `Duration`, `Struct`, `Value`,
`FieldMask`, `Timestamp`, `Empty`, `Int64Value`, `DoubleValue`, `FloatValue`, `UInt64Value`, `BoolValue`, `StringValue`, `BytesValue`, and recursive nested `Any` payloads), direct WKT JSON, TextFormat, packed scalars, large bytes,
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
