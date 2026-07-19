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
python3 bench/summarize_compare.py /tmp/pbz-compare.log --fail-on-loss
```

Latest accepted comparison (`/tmp/pbz-compare-after-any-uint32-json-isolated.log`,
summarized in `/tmp/pbz-summary-after-any-uint32-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 25.26 | 125.45 (4.97x) | 63.62 (2.52x) | 138.38 (5.48x) | 957.41 (37.90x) |
| binary decode | 126.51 | 301.92 (2.39x) | 295.30 (2.33x) | 268.51 (2.12x) | 1009.58 (7.98x) |
| unknown count by number | 5.04 | — | — | 175.14 (34.75x) | — |
| scalarmix encode | 26.40 | 115.05 (4.36x) | 66.83 (2.53x) | 45.24 (1.71x) | 238.77 (9.04x) |
| scalarmix decode | 56.11 | 163.96 (2.92x) | 211.04 (3.76x) | 107.45 (1.92x) | 364.11 (6.49x) |
| textbytes encode | 11.78 | 93.81 (7.96x) | 43.25 (3.67x) | 147.84 (12.55x) | 175.11 (14.87x) |
| complex decode | 214.48 | 464.25 (2.16x) | 432.33 (2.02x) | 477.39 (2.23x) | 1604.75 (7.48x) |
| complex JSON parse | 2777.13 | — | — | 16679.40 (6.01x) | 10550.96 (3.80x) |
| Any WKT JSON stringify | 177.24 | — | — | 3052.61 (17.22x) | 1347.72 (7.60x) |
| Any WKT JSON parse | 561.55 | — | — | 4623.37 (8.23x) | 2123.57 (3.78x) |
| Any FieldMask WKT JSON stringify | 285.73 | — | — | 2443.07 (8.55x) | 1751.21 (6.13x) |
| Any FieldMask WKT JSON parse | 777.36 | — | — | 4951.05 (6.37x) | 2929.14 (3.77x) |
| Any Timestamp WKT JSON stringify | 247.30 | — | — | 2958.69 (11.96x) | 1301.10 (5.26x) |
| Any Timestamp WKT JSON parse | 628.37 | — | — | 4678.56 (7.45x) | 2261.19 (3.60x) |
| Any Empty WKT JSON stringify | 121.83 | — | — | 1306.99 (10.73x) | 709.56 (5.82x) |
| Any Empty WKT JSON parse | 368.30 | — | — | 3151.49 (8.56x) | 1695.72 (4.60x) |
| Any Struct WKT JSON stringify | 784.59 | — | — | 9047.19 (11.53x) | 8878.78 (11.32x) |
| Any Struct WKT JSON parse | 1965.28 | — | — | 16605.30 (8.45x) | 12613.02 (6.42x) |
| Any Value WKT JSON stringify | 825.12 | — | — | 9249.99 (11.21x) | 9358.66 (11.34x) |
| Any Value WKT JSON parse | 2004.61 | — | — | 16865.90 (8.41x) | 13028.31 (6.50x) |
| Any DoubleValue WKT JSON stringify | 254.64 | — | — | 2835.98 (11.14x) | 871.83 (3.42x) |
| Any DoubleValue WKT JSON parse | 562.53 | — | — | 4421.34 (7.86x) | 1975.49 (3.51x) |
| Any FloatValue WKT JSON stringify | 259.24 | — | — | 2763.94 (10.66x) | 877.12 (3.38x) |
| Any FloatValue WKT JSON parse | 563.00 | — | — | 4355.20 (7.74x) | 1910.55 (3.39x) |
| Any Int64Value WKT JSON stringify | 207.20 | — | — | 2214.39 (10.69x) | 1098.11 (5.30x) |
| Any Int64Value WKT JSON parse | 609.56 | — | — | 4301.00 (7.06x) | 2338.27 (3.84x) |
| Any UInt64Value WKT JSON stringify | 216.15 | — | — | 2207.45 (10.21x) | 1128.28 (5.22x) |
| Any UInt64Value WKT JSON parse | 612.57 | — | — | 4329.40 (7.07x) | 2265.13 (3.70x) |
| Any Int32Value WKT JSON stringify | 206.95 | — | — | 2243.83 (10.84x) | 888.87 (4.30x) |
| Any Int32Value WKT JSON parse | 582.20 | — | — | 4138.56 (7.11x) | 2007.59 (3.45x) |
| Any UInt32Value WKT JSON stringify | 216.60 | — | — | 2212.43 (10.21x) | 872.46 (4.03x) |
| Any UInt32Value WKT JSON parse | 588.84 | — | — | 4105.04 (6.97x) | 2029.03 (3.45x) |
| Any BoolValue WKT JSON stringify | 211.97 | — | — | 2177.31 (10.27x) | 800.71 (3.78x) |
| Any BoolValue WKT JSON parse | 539.03 | — | — | 3988.20 (7.40x) | 1740.30 (3.23x) |
| Any StringValue WKT JSON stringify | 242.49 | — | — | 2248.99 (9.27x) | 906.95 (3.74x) |
| Any StringValue WKT JSON parse | 599.32 | — | — | 4106.78 (6.85x) | 1967.77 (3.28x) |
| Any BytesValue WKT JSON stringify | 226.97 | — | — | 2300.64 (10.14x) | 965.05 (4.25x) |
| Any BytesValue WKT JSON parse | 604.23 | — | — | 4282.72 (7.09x) | 2047.73 (3.39x) |
| Nested Any WKT JSON stringify | 386.17 | — | — | 3396.74 (8.80x) | 1573.34 (4.07x) |
| Nested Any WKT JSON parse | 978.78 | — | — | 6072.40 (6.20x) | 3612.74 (3.69x) |
| Duration JSON stringify | 63.31 | — | — | 1547.58 (24.44x) | 390.52 (6.17x) |
| Duration JSON parse | 12.06 | — | — | 2262.49 (187.60x) | 430.04 (35.66x) |
| FieldMask JSON stringify | 89.20 | — | — | 1319.26 (14.79x) | 734.98 (8.24x) |
| FieldMask JSON parse | 178.74 | — | — | 2661.07 (14.89x) | 1083.39 (6.06x) |
| Timestamp JSON stringify | 126.13 | — | — | 1728.93 (13.71x) | 469.39 (3.72x) |
| Timestamp JSON parse | 57.14 | — | — | 2331.28 (40.80x) | 489.90 (8.57x) |
| Empty JSON stringify | 22.58 | — | — | 672.63 (29.79x) | 97.03 (4.30x) |
| Empty JSON parse | 75.16 | — | — | 1111.42 (14.79x) | 261.99 (3.49x) |
| Struct JSON stringify | 271.47 | — | — | 8934.51 (32.91x) | 4320.79 (15.92x) |
| Struct JSON parse | 954.67 | — | — | 16890.60 (17.69x) | 6364.13 (6.67x) |
| Value JSON stringify | 275.61 | — | — | 9909.14 (35.95x) | 4367.71 (15.85x) |
| Value JSON parse | 949.18 | — | — | 17635.00 (18.58x) | 6740.23 (7.10x) |
| ListValue JSON stringify | 201.18 | — | — | 7558.67 (37.57x) | 2921.09 (14.52x) |
| ListValue JSON parse | 752.17 | — | — | 13586.50 (18.06x) | 5355.00 (7.12x) |
| DoubleValue JSON stringify | 74.95 | — | — | 1480.80 (19.76x) | 202.27 (2.70x) |
| DoubleValue JSON parse | 113.60 | — | — | 2109.84 (18.57x) | 318.17 (2.80x) |
| FloatValue JSON stringify | 98.70 | — | — | 1401.34 (14.20x) | 195.19 (1.98x) |
| FloatValue JSON parse | 113.85 | — | — | 2149.20 (18.88x) | 316.95 (2.78x) |
| Int64Value JSON stringify | 41.83 | — | — | 1002.69 (23.97x) | 281.99 (6.74x) |
| Int64Value JSON parse | 138.24 | — | — | 1984.28 (14.35x) | 522.27 (3.78x) |
| UInt64Value JSON stringify | 41.91 | — | — | 999.31 (23.84x) | 302.16 (7.21x) |
| UInt64Value JSON parse | 137.71 | — | — | 1945.91 (14.13x) | 512.08 (3.72x) |
| Int32Value JSON stringify | 45.88 | — | — | 965.28 (21.04x) | 153.51 (3.35x) |
| Int32Value JSON parse | 134.26 | — | — | 1903.05 (14.17x) | 336.12 (2.50x) |
| UInt32Value JSON stringify | 45.68 | — | — | 912.56 (19.98x) | 144.21 (3.16x) |
| UInt32Value JSON parse | 133.56 | — | — | 1928.41 (14.44x) | 343.89 (2.57x) |
| BoolValue JSON stringify | 43.53 | — | — | 903.82 (20.76x) | 128.26 (2.95x) |
| BoolValue JSON parse | 54.87 | — | — | 1680.45 (30.63x) | 246.63 (4.49x) |
| StringValue JSON stringify | 54.18 | — | — | 1015.47 (18.74x) | 188.24 (3.47x) |
| StringValue JSON parse | 131.64 | — | — | 1806.56 (13.72x) | 350.48 (2.66x) |
| BytesValue JSON stringify | 47.60 | — | — | 984.25 (20.68x) | 228.15 (4.79x) |
| BytesValue JSON parse | 138.11 | — | — | 1956.03 (14.16x) | 385.72 (2.79x) |
| TextFormat parse | 851.88 | — | — | 5317.04 (6.24x) | 8148.01 (9.56x) |
| packed int32 decode | 993.83 | 2977.08 (3.00x) | 4355.44 (4.38x) | 1341.68 (1.35x) | 4364.66 (4.39x) |
| packed bool encode | 2.26 | 2080.04 (920.37x) | 572.52 (253.33x) | 23.49 (10.40x) | 4385.31 (1940.40x) |
| packed bool decode | 271.90 | 2063.78 (7.59x) | 4189.11 (15.41x) | 1108.31 (4.08x) | 2725.06 (10.02x) |
| largebytes decode | 124.70 | 8496.80 (68.14x) | 4523.54 (36.28x) | 3989.36 (31.99x) | 23892.82 (191.60x) |
| large map decode | 37624.11 | 125989.04 (3.35x) | 119856.07 (3.19x) | 119481.00 (3.18x) | 295549.98 (7.86x) |
| shuffled large map deterministic binary encode | 36010.84 | — | — | 113497.00 (3.15x) | 455749.60 (12.66x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded `Duration`, `Struct`, `Value`,
`FieldMask`, `Timestamp`, `Empty`, `Int64Value`, `DoubleValue`, `FloatValue`, `UInt64Value`, `Int32Value`, `UInt32Value`, `BoolValue`, `StringValue`, `BytesValue`, and recursive nested `Any` payloads), direct WKT JSON, TextFormat, packed scalars, large bytes,
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
python3 bench/summarize_compare.py /tmp/pbz-compare.log --fail-on-loss
```
