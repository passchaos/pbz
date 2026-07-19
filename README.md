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

Latest accepted comparison (`/tmp/pbz-compare-after-max-timestamp-json-isolated.log`,
summarized in `/tmp/pbz-summary-after-max-timestamp-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 22.61 | 128.90 (5.70x) | 66.39 (2.94x) | 133.75 (5.92x) | 945.55 (41.82x) |
| binary decode | 130.86 | 293.97 (2.25x) | 299.84 (2.29x) | 294.76 (2.25x) | 994.41 (7.60x) |
| unknown count by number | 5.02 | — | — | 237.52 (47.31x) | — |
| scalarmix encode | 26.82 | 117.07 (4.37x) | 69.27 (2.58x) | 49.05 (1.83x) | 238.51 (8.89x) |
| scalarmix decode | 50.27 | 166.43 (3.31x) | 217.05 (4.32x) | 121.22 (2.41x) | 362.83 (7.22x) |
| textbytes encode | 13.29 | 92.27 (6.94x) | 43.38 (3.26x) | 151.88 (11.43x) | 170.80 (12.85x) |
| complex decode | 226.65 | 469.64 (2.07x) | 430.97 (1.90x) | 493.63 (2.18x) | 1642.48 (7.25x) |
| complex JSON parse | 2730.51 | — | — | 16599.70 (6.08x) | 10562.18 (3.87x) |
| Any WKT JSON stringify | 180.05 | — | — | 3031.71 (16.84x) | 1362.56 (7.57x) |
| Any WKT JSON parse | 571.77 | — | — | 4587.94 (8.02x) | 2178.23 (3.81x) |
| Any NegativeDuration WKT JSON stringify | 185.93 | — | — | 3056.15 (16.44x) | 1408.19 (7.57x) |
| Any NegativeDuration WKT JSON parse | 578.09 | — | — | 4710.40 (8.15x) | 2247.77 (3.89x) |
| Any FieldMask WKT JSON stringify | 288.23 | — | — | 2402.56 (8.34x) | 1804.23 (6.26x) |
| Any FieldMask WKT JSON parse | 796.55 | — | — | 4896.80 (6.15x) | 3083.72 (3.87x) |
| Any Timestamp WKT JSON stringify | 246.39 | — | — | 2969.77 (12.05x) | 1505.07 (6.11x) |
| Any Timestamp WKT JSON parse | 640.52 | — | — | 4653.99 (7.27x) | 2531.08 (3.95x) |
| Any PreEpoch Timestamp WKT JSON stringify | 201.16 | — | — | 2877.51 (14.30x) | 1430.99 (7.11x) |
| Any PreEpoch Timestamp WKT JSON parse | 623.61 | — | — | 4685.19 (7.51x) | 2444.96 (3.92x) |
| Any Max Timestamp WKT JSON stringify | 224.69 | — | — | 3005.34 (13.38x) | 1443.28 (6.42x) |
| Any Max Timestamp WKT JSON parse | 656.93 | — | — | 4721.19 (7.19x) | 2464.70 (3.75x) |
| Any Empty WKT JSON stringify | 122.48 | — | — | 1281.46 (10.46x) | 676.91 (5.53x) |
| Any Empty WKT JSON parse | 377.55 | — | — | 3088.83 (8.18x) | 1776.44 (4.71x) |
| Any Struct WKT JSON stringify | 782.00 | — | — | 8936.62 (11.43x) | 8972.00 (11.47x) |
| Any Struct WKT JSON parse | 1968.42 | — | — | 16840.00 (8.56x) | 12487.91 (6.34x) |
| Any Value WKT JSON stringify | 804.03 | — | — | 9161.49 (11.39x) | 9359.18 (11.64x) |
| Any Value WKT JSON parse | 2034.40 | — | — | 16753.90 (8.24x) | 12892.02 (6.34x) |
| Any DoubleValue WKT JSON stringify | 254.88 | — | — | 2792.67 (10.96x) | 954.17 (3.74x) |
| Any DoubleValue WKT JSON parse | 575.73 | — | — | 4375.92 (7.60x) | 1994.16 (3.46x) |
| Any DoubleValue NaN WKT JSON stringify | 199.49 | — | — | 2286.73 (11.46x) | 786.28 (3.94x) |
| Any DoubleValue NaN WKT JSON parse | 571.96 | — | — | 4005.93 (7.00x) | 1907.79 (3.34x) |
| Any DoubleValue Infinity WKT JSON stringify | 206.50 | — | — | 2240.23 (10.85x) | 779.78 (3.78x) |
| Any DoubleValue Infinity WKT JSON parse | 575.20 | — | — | 4048.69 (7.04x) | 1945.95 (3.38x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 208.10 | — | — | 2252.64 (10.82x) | 769.30 (3.70x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 578.45 | — | — | 4015.98 (6.94x) | 1948.88 (3.37x) |
| Any FloatValue WKT JSON stringify | 259.26 | — | — | 2751.86 (10.61x) | 950.67 (3.67x) |
| Any FloatValue WKT JSON parse | 574.95 | — | — | 4285.84 (7.45x) | 1968.87 (3.42x) |
| Any FloatValue NaN WKT JSON stringify | 201.77 | — | — | 2280.76 (11.30x) | 797.31 (3.95x) |
| Any FloatValue NaN WKT JSON parse | 570.89 | — | — | 4053.49 (7.10x) | 1883.54 (3.30x) |
| Any FloatValue Infinity WKT JSON stringify | 206.65 | — | — | 2180.94 (10.55x) | 788.46 (3.82x) |
| Any FloatValue Infinity WKT JSON parse | 575.96 | — | — | 3999.81 (6.94x) | 1947.82 (3.38x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 209.20 | — | — | 2216.68 (10.60x) | 791.88 (3.79x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 578.96 | — | — | 3998.19 (6.91x) | 1946.45 (3.36x) |
| Any Int64Value WKT JSON stringify | 206.90 | — | — | 2218.14 (10.72x) | 1099.94 (5.32x) |
| Any Int64Value WKT JSON parse | 622.55 | — | — | 4248.12 (6.82x) | 2359.28 (3.79x) |
| Any UInt64Value WKT JSON stringify | 214.71 | — | — | 2262.16 (10.54x) | 1108.77 (5.16x) |
| Any UInt64Value WKT JSON parse | 630.11 | — | — | 4274.85 (6.78x) | 2306.77 (3.66x) |
| Any Int32Value WKT JSON stringify | 207.43 | — | — | 2255.02 (10.87x) | 865.02 (4.17x) |
| Any Int32Value WKT JSON parse | 594.62 | — | — | 4115.92 (6.92x) | 2025.50 (3.41x) |
| Any UInt32Value WKT JSON stringify | 220.48 | — | — | 2174.19 (9.86x) | 878.82 (3.99x) |
| Any UInt32Value WKT JSON parse | 601.30 | — | — | 4126.28 (6.86x) | 2017.86 (3.36x) |
| Any BoolValue WKT JSON stringify | 211.68 | — | — | 2133.71 (10.08x) | 784.15 (3.70x) |
| Any BoolValue WKT JSON parse | 551.59 | — | — | 3990.88 (7.24x) | 1804.23 (3.27x) |
| Any StringValue WKT JSON stringify | 254.18 | — | — | 2203.24 (8.67x) | 875.63 (3.44x) |
| Any StringValue WKT JSON parse | 610.70 | — | — | 4050.47 (6.63x) | 1959.22 (3.21x) |
| Any BytesValue WKT JSON stringify | 224.75 | — | — | 2270.31 (10.10x) | 931.04 (4.14x) |
| Any BytesValue WKT JSON parse | 617.73 | — | — | 4287.15 (6.94x) | 2033.80 (3.29x) |
| Nested Any WKT JSON stringify | 386.12 | — | — | 3400.01 (8.81x) | 1584.91 (4.10x) |
| Nested Any WKT JSON parse | 996.97 | — | — | 6113.31 (6.13x) | 3621.01 (3.63x) |
| Duration JSON stringify | 64.56 | — | — | 1513.35 (23.44x) | 390.46 (6.05x) |
| Duration JSON parse | 11.38 | — | — | 2288.53 (201.10x) | 424.28 (37.28x) |
| NegativeDuration JSON stringify | 64.89 | — | — | 1598.87 (24.64x) | 445.97 (6.87x) |
| NegativeDuration JSON parse | 11.30 | — | — | 2384.92 (211.05x) | 429.04 (37.97x) |
| FieldMask JSON stringify | 92.47 | — | — | 1283.11 (13.88x) | 721.20 (7.80x) |
| FieldMask JSON parse | 180.49 | — | — | 2634.94 (14.60x) | 1033.20 (5.72x) |
| Timestamp JSON stringify | 128.59 | — | — | 1701.40 (13.23x) | 471.60 (3.67x) |
| Timestamp JSON parse | 56.72 | — | — | 2270.96 (40.04x) | 478.52 (8.44x) |
| PreEpoch Timestamp JSON stringify | 86.94 | — | — | 1576.88 (18.14x) | 449.23 (5.17x) |
| PreEpoch Timestamp JSON parse | 54.79 | — | — | 2239.22 (40.87x) | 466.04 (8.51x) |
| Max Timestamp JSON stringify | 105.01 | — | — | 1727.13 (16.45x) | 467.52 (4.45x) |
| Max Timestamp JSON parse | 64.28 | — | — | 2299.38 (35.77x) | 490.87 (7.64x) |
| Empty JSON stringify | 22.81 | — | — | 699.21 (30.65x) | 106.10 (4.65x) |
| Empty JSON parse | 73.06 | — | — | 1098.96 (15.04x) | 247.61 (3.39x) |
| Struct JSON stringify | 272.71 | — | — | 8800.55 (32.27x) | 4111.74 (15.08x) |
| Struct JSON parse | 940.98 | — | — | 16721.20 (17.77x) | 6285.03 (6.68x) |
| Value JSON stringify | 273.97 | — | — | 9811.75 (35.81x) | 4334.71 (15.82x) |
| Value JSON parse | 964.36 | — | — | 17579.90 (18.23x) | 6605.84 (6.85x) |
| ListValue JSON stringify | 200.58 | — | — | 7545.37 (37.62x) | 2861.05 (14.26x) |
| ListValue JSON parse | 738.15 | — | — | 13579.00 (18.40x) | 5171.07 (7.01x) |
| DoubleValue JSON stringify | 97.07 | — | — | 1489.75 (15.35x) | 198.30 (2.04x) |
| DoubleValue JSON parse | 113.13 | — | — | 2137.81 (18.90x) | 312.95 (2.77x) |
| DoubleValue NaN JSON stringify | 52.74 | — | — | 996.53 (18.90x) | 143.09 (2.71x) |
| DoubleValue NaN JSON parse | 100.94 | — | — | 1708.75 (16.93x) | 313.88 (3.11x) |
| DoubleValue Infinity JSON stringify | 56.91 | — | — | 1008.15 (17.71x) | 149.52 (2.63x) |
| DoubleValue Infinity JSON parse | 104.22 | — | — | 1738.77 (16.68x) | 314.18 (3.01x) |
| DoubleValue NegativeInfinity JSON stringify | 57.93 | — | — | 989.16 (17.08x) | 154.02 (2.66x) |
| DoubleValue NegativeInfinity JSON parse | 108.08 | — | — | 1749.56 (16.19x) | 320.74 (2.97x) |
| FloatValue JSON stringify | 101.17 | — | — | 1396.63 (13.80x) | 210.45 (2.08x) |
| FloatValue JSON parse | 113.90 | — | — | 2102.27 (18.46x) | 327.38 (2.87x) |
| FloatValue NaN JSON stringify | 52.39 | — | — | 961.06 (18.34x) | 136.96 (2.61x) |
| FloatValue NaN JSON parse | 101.97 | — | — | 1683.17 (16.51x) | 304.30 (2.98x) |
| FloatValue Infinity JSON stringify | 56.91 | — | — | 971.36 (17.07x) | 133.52 (2.35x) |
| FloatValue Infinity JSON parse | 104.33 | — | — | 1708.68 (16.38x) | 310.32 (2.97x) |
| FloatValue NegativeInfinity JSON stringify | 57.91 | — | — | 964.74 (16.66x) | 144.08 (2.49x) |
| FloatValue NegativeInfinity JSON parse | 108.39 | — | — | 1725.03 (15.92x) | 320.98 (2.96x) |
| Int64Value JSON stringify | 42.07 | — | — | 1001.09 (23.80x) | 296.44 (7.05x) |
| Int64Value JSON parse | 139.23 | — | — | 1973.84 (14.18x) | 520.82 (3.74x) |
| UInt64Value JSON stringify | 42.30 | — | — | 995.24 (23.53x) | 300.73 (7.11x) |
| UInt64Value JSON parse | 139.29 | — | — | 1928.00 (13.84x) | 509.46 (3.66x) |
| Int32Value JSON stringify | 46.32 | — | — | 967.93 (20.90x) | 153.41 (3.31x) |
| Int32Value JSON parse | 130.09 | — | — | 1925.63 (14.80x) | 349.53 (2.69x) |
| UInt32Value JSON stringify | 46.21 | — | — | 907.44 (19.64x) | 151.93 (3.29x) |
| UInt32Value JSON parse | 129.00 | — | — | 1892.49 (14.67x) | 354.78 (2.75x) |
| BoolValue JSON stringify | 42.03 | — | — | 890.88 (21.20x) | 139.46 (3.32x) |
| BoolValue JSON parse | 59.00 | — | — | 1680.09 (28.48x) | 254.82 (4.32x) |
| StringValue JSON stringify | 53.85 | — | — | 1010.65 (18.77x) | 196.30 (3.65x) |
| StringValue JSON parse | 129.87 | — | — | 1816.59 (13.99x) | 363.24 (2.80x) |
| BytesValue JSON stringify | 47.63 | — | — | 972.47 (20.42x) | 232.04 (4.87x) |
| BytesValue JSON parse | 142.74 | — | — | 1967.86 (13.79x) | 384.01 (2.69x) |
| TextFormat parse | 835.54 | — | — | 5550.83 (6.64x) | 8039.04 (9.62x) |
| packed int32 decode | 1029.39 | 2972.31 (2.89x) | 4418.68 (4.29x) | 1355.28 (1.32x) | 4419.59 (4.29x) |
| packed bool encode | 2.26 | 2080.44 (920.55x) | 539.43 (238.69x) | 22.65 (10.02x) | 4386.57 (1940.96x) |
| packed bool decode | 272.53 | 2060.64 (7.56x) | 3850.63 (14.13x) | 1108.87 (4.07x) | 2647.18 (9.71x) |
| largebytes decode | 124.48 | 9303.12 (74.74x) | 4530.57 (36.40x) | 4071.97 (32.71x) | 23907.48 (192.06x) |
| large map decode | 37353.95 | 130159.96 (3.48x) | 129717.67 (3.47x) | 119484.00 (3.20x) | 300782.52 (8.05x) |
| shuffled large map deterministic binary encode | 36064.76 | — | — | 118923.00 (3.30x) | 454404.44 (12.60x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded positive/negative `Duration`, `Struct`, `Value`,
`FieldMask`, post/pre-epoch and max-bound `Timestamp`, `Empty`, `Int64Value`, `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), `UInt64Value`, `Int32Value`, `UInt32Value`, `BoolValue`, `StringValue`, `BytesValue`, and recursive nested `Any` payloads), direct positive/negative Duration and post/pre-epoch/max-bound Timestamp WKT JSON plus other direct WKT JSON, TextFormat, packed scalars, large bytes,
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
