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

Latest accepted comparison (`/tmp/pbz-compare-after-any-double-json-isolated.log`,
summarized in `/tmp/pbz-summary-after-any-double-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 26.81 | 128.74 (4.80x) | 68.64 (2.56x) | 128.19 (4.78x) | 946.51 (35.30x) |
| binary decode | 132.69 | 295.21 (2.22x) | 306.54 (2.31x) | 270.95 (2.04x) | 990.16 (7.46x) |
| unknown count by number | 5.02 | — | — | 175.19 (34.90x) | — |
| scalarmix encode | 26.33 | 114.66 (4.35x) | 68.10 (2.59x) | 45.76 (1.74x) | 237.75 (9.03x) |
| scalarmix decode | 56.01 | 162.78 (2.91x) | 214.62 (3.83x) | 112.33 (2.01x) | 361.14 (6.45x) |
| textbytes encode | 11.79 | 92.35 (7.83x) | 43.26 (3.67x) | 146.77 (12.45x) | 171.30 (14.53x) |
| complex decode | 217.08 | 462.05 (2.13x) | 434.23 (2.00x) | 482.95 (2.22x) | 1627.12 (7.50x) |
| complex JSON parse | 2726.76 | — | — | 16636.50 (6.10x) | 10401.75 (3.81x) |
| Any WKT JSON stringify | 171.95 | — | — | 3051.83 (17.75x) | 1349.17 (7.85x) |
| Any WKT JSON parse | 586.41 | — | — | 4599.52 (7.84x) | 2046.17 (3.49x) |
| Any FieldMask WKT JSON stringify | 276.63 | — | — | 2428.91 (8.78x) | 1733.47 (6.27x) |
| Any FieldMask WKT JSON parse | 800.78 | — | — | 4837.87 (6.04x) | 2881.63 (3.60x) |
| Any Timestamp WKT JSON stringify | 238.46 | — | — | 2971.82 (12.46x) | 1343.61 (5.63x) |
| Any Timestamp WKT JSON parse | 645.46 | — | — | 4678.95 (7.25x) | 2192.91 (3.40x) |
| Any Empty WKT JSON stringify | 115.57 | — | — | 1288.16 (11.15x) | 635.97 (5.50x) |
| Any Empty WKT JSON parse | 380.79 | — | — | 3146.37 (8.26x) | 1578.19 (4.14x) |
| Any Struct WKT JSON stringify | 775.23 | — | — | 8997.71 (11.61x) | 8838.85 (11.40x) |
| Any Struct WKT JSON parse | 1983.67 | — | — | 17039.00 (8.59x) | 12461.15 (6.28x) |
| Any Value WKT JSON stringify | 818.42 | — | — | 9061.47 (11.07x) | 9310.87 (11.38x) |
| Any Value WKT JSON parse | 2038.53 | — | — | 17075.60 (8.38x) | 12905.36 (6.33x) |
| Any DoubleValue WKT JSON stringify | 243.36 | — | — | 2832.87 (11.64x) | 953.98 (3.92x) |
| Any DoubleValue WKT JSON parse | 578.18 | — | — | 4385.91 (7.59x) | 1946.41 (3.37x) |
| Any Int64Value WKT JSON stringify | 202.83 | — | — | 2176.44 (10.73x) | 1117.89 (5.51x) |
| Any Int64Value WKT JSON parse | 626.98 | — | — | 4261.13 (6.80x) | 2328.28 (3.71x) |
| Any UInt64Value WKT JSON stringify | 209.67 | — | — | 2174.25 (10.37x) | 1110.10 (5.29x) |
| Any UInt64Value WKT JSON parse | 633.77 | — | — | 4264.58 (6.73x) | 2194.87 (3.46x) |
| Any BoolValue WKT JSON stringify | 208.17 | — | — | 2082.41 (10.00x) | 759.53 (3.65x) |
| Any BoolValue WKT JSON parse | 555.75 | — | — | 4007.52 (7.21x) | 1713.73 (3.08x) |
| Any StringValue WKT JSON stringify | 235.24 | — | — | 2189.93 (9.31x) | 881.18 (3.75x) |
| Any StringValue WKT JSON parse | 618.73 | — | — | 4094.65 (6.62x) | 1892.78 (3.06x) |
| Any BytesValue WKT JSON stringify | 224.25 | — | — | 2294.66 (10.23x) | 902.68 (4.03x) |
| Any BytesValue WKT JSON parse | 625.65 | — | — | 4254.89 (6.80x) | 1975.91 (3.16x) |
| Nested Any WKT JSON stringify | 359.48 | — | — | 3354.18 (9.33x) | 1574.87 (4.38x) |
| Nested Any WKT JSON parse | 1000.16 | — | — | 6070.70 (6.07x) | 3586.76 (3.59x) |
| Duration JSON stringify | 63.94 | — | — | 1525.83 (23.86x) | 377.67 (5.91x) |
| Duration JSON parse | 11.35 | — | — | 2292.56 (201.99x) | 442.40 (38.98x) |
| FieldMask JSON stringify | 88.52 | — | — | 1322.14 (14.94x) | 727.13 (8.21x) |
| FieldMask JSON parse | 180.93 | — | — | 2621.80 (14.49x) | 1042.86 (5.76x) |
| Timestamp JSON stringify | 125.80 | — | — | 1692.48 (13.45x) | 465.87 (3.70x) |
| Timestamp JSON parse | 56.97 | — | — | 2284.36 (40.10x) | 489.27 (8.59x) |
| Empty JSON stringify | 22.79 | — | — | 694.13 (30.46x) | 102.39 (4.49x) |
| Empty JSON parse | 73.43 | — | — | 1100.14 (14.98x) | 249.06 (3.39x) |
| Struct JSON stringify | 260.49 | — | — | 8928.53 (34.28x) | 4176.98 (16.04x) |
| Struct JSON parse | 948.25 | — | — | 16616.70 (17.52x) | 6264.80 (6.61x) |
| Value JSON stringify | 263.30 | — | — | 9868.46 (37.48x) | 4340.19 (16.48x) |
| Value JSON parse | 948.89 | — | — | 18207.70 (19.19x) | 6577.78 (6.93x) |
| ListValue JSON stringify | 196.32 | — | — | 7592.24 (38.67x) | 2808.36 (14.31x) |
| ListValue JSON parse | 737.61 | — | — | 13522.80 (18.33x) | 5146.43 (6.98x) |
| DoubleValue JSON stringify | 75.28 | — | — | 1481.65 (19.68x) | 200.77 (2.67x) |
| DoubleValue JSON parse | 113.23 | — | — | 2118.38 (18.71x) | 324.93 (2.87x) |
| FloatValue JSON stringify | 99.33 | — | — | 1396.15 (14.06x) | 196.66 (1.98x) |
| FloatValue JSON parse | 112.15 | — | — | 2111.05 (18.82x) | 317.44 (2.83x) |
| Int64Value JSON stringify | 44.70 | — | — | 1000.33 (22.38x) | 302.61 (6.77x) |
| Int64Value JSON parse | 137.40 | — | — | 1970.16 (14.34x) | 504.83 (3.67x) |
| UInt64Value JSON stringify | 44.97 | — | — | 1013.76 (22.54x) | 283.62 (6.31x) |
| UInt64Value JSON parse | 136.17 | — | — | 1955.58 (14.36x) | 499.80 (3.67x) |
| Int32Value JSON stringify | 45.92 | — | — | 974.60 (21.22x) | 143.35 (3.12x) |
| Int32Value JSON parse | 129.12 | — | — | 1902.50 (14.73x) | 331.64 (2.57x) |
| UInt32Value JSON stringify | 45.94 | — | — | 908.48 (19.78x) | 145.63 (3.17x) |
| UInt32Value JSON parse | 129.12 | — | — | 1900.83 (14.72x) | 353.94 (2.74x) |
| BoolValue JSON stringify | 42.14 | — | — | 885.02 (21.00x) | 142.48 (3.38x) |
| BoolValue JSON parse | 59.06 | — | — | 1688.60 (28.59x) | 257.91 (4.37x) |
| StringValue JSON stringify | 54.76 | — | — | 999.50 (18.25x) | 208.31 (3.80x) |
| StringValue JSON parse | 130.51 | — | — | 1834.78 (14.06x) | 352.36 (2.70x) |
| BytesValue JSON stringify | 47.48 | — | — | 996.34 (20.98x) | 222.73 (4.69x) |
| BytesValue JSON parse | 142.80 | — | — | 1956.78 (13.70x) | 384.87 (2.70x) |
| TextFormat parse | 866.92 | — | — | 5411.96 (6.24x) | 7990.73 (9.22x) |
| packed int32 decode | 995.10 | 2986.28 (3.00x) | 4242.25 (4.26x) | 1345.06 (1.35x) | 4352.71 (4.37x) |
| packed bool encode | 2.51 | 2080.71 (828.97x) | 540.22 (215.23x) | 22.43 (8.94x) | 4381.86 (1745.76x) |
| packed bool decode | 271.54 | 2061.65 (7.59x) | 4497.36 (16.56x) | 1108.44 (4.08x) | 2659.63 (9.79x) |
| largebytes decode | 125.14 | 8499.83 (67.92x) | 4537.46 (36.26x) | 4074.25 (32.56x) | 24239.11 (193.70x) |
| large map decode | 38854.65 | 126909.02 (3.27x) | 129160.28 (3.32x) | 119367.00 (3.07x) | 294135.26 (7.57x) |
| shuffled large map deterministic binary encode | 36060.26 | — | — | 113748.00 (3.15x) | 451064.52 (12.51x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded `Duration`, `Struct`, `Value`,
`FieldMask`, `Timestamp`, `Empty`, `Int64Value`, `DoubleValue`, `UInt64Value`, `BoolValue`, `StringValue`, `BytesValue`, and recursive nested `Any` payloads), direct WKT JSON, TextFormat, packed scalars, large bytes,
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
