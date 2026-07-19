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

Latest accepted comparison (`/tmp/pbz-compare-after-pre-epoch-timestamp-json-isolated.log`,
summarized in `/tmp/pbz-summary-after-pre-epoch-timestamp-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 25.72 | 125.54 (4.88x) | 64.24 (2.50x) | 127.55 (4.96x) | 945.51 (36.76x) |
| binary decode | 127.28 | 296.59 (2.33x) | 299.38 (2.35x) | 281.00 (2.21x) | 984.35 (7.73x) |
| unknown count by number | 5.02 | — | — | 212.83 (42.40x) | — |
| scalarmix encode | 26.36 | 114.76 (4.35x) | 66.88 (2.54x) | 45.51 (1.73x) | 239.25 (9.08x) |
| scalarmix decode | 56.34 | 163.54 (2.90x) | 212.53 (3.77x) | 112.43 (2.00x) | 368.62 (6.54x) |
| textbytes encode | 13.53 | 91.33 (6.75x) | 43.23 (3.20x) | 145.95 (10.79x) | 170.86 (12.63x) |
| complex decode | 214.02 | 463.15 (2.16x) | 423.23 (1.98x) | 491.86 (2.30x) | 1637.44 (7.65x) |
| complex JSON parse | 2732.88 | — | — | 16702.80 (6.11x) | 10528.08 (3.85x) |
| Any WKT JSON stringify | 176.02 | — | — | 3050.30 (17.33x) | 1339.98 (7.61x) |
| Any WKT JSON parse | 561.68 | — | — | 4576.09 (8.15x) | 2082.24 (3.71x) |
| Any NegativeDuration WKT JSON stringify | 182.98 | — | — | 3061.19 (16.73x) | 1367.19 (7.47x) |
| Any NegativeDuration WKT JSON parse | 572.16 | — | — | 4763.45 (8.33x) | 2164.76 (3.78x) |
| Any FieldMask WKT JSON stringify | 282.73 | — | — | 2439.97 (8.63x) | 1747.50 (6.18x) |
| Any FieldMask WKT JSON parse | 788.19 | — | — | 4881.00 (6.19x) | 2906.81 (3.69x) |
| Any Timestamp WKT JSON stringify | 247.88 | — | — | 3017.09 (12.17x) | 1344.25 (5.42x) |
| Any Timestamp WKT JSON parse | 631.90 | — | — | 4647.34 (7.35x) | 2245.17 (3.55x) |
| Any PreEpoch Timestamp WKT JSON stringify | 195.63 | — | — | 2884.33 (14.74x) | 1273.13 (6.51x) |
| Any PreEpoch Timestamp WKT JSON parse | 616.86 | — | — | 4639.34 (7.52x) | 2210.90 (3.58x) |
| Any Empty WKT JSON stringify | 121.69 | — | — | 1281.41 (10.53x) | 725.49 (5.96x) |
| Any Empty WKT JSON parse | 371.71 | — | — | 3137.53 (8.44x) | 1680.34 (4.52x) |
| Any Struct WKT JSON stringify | 786.36 | — | — | 8991.35 (11.43x) | 8883.66 (11.30x) |
| Any Struct WKT JSON parse | 1967.32 | — | — | 16753.80 (8.52x) | 12453.13 (6.33x) |
| Any Value WKT JSON stringify | 805.46 | — | — | 9018.79 (11.20x) | 9280.03 (11.52x) |
| Any Value WKT JSON parse | 2019.85 | — | — | 16771.00 (8.30x) | 12985.82 (6.43x) |
| Any DoubleValue WKT JSON stringify | 253.80 | — | — | 2827.58 (11.14x) | 883.19 (3.48x) |
| Any DoubleValue WKT JSON parse | 570.39 | — | — | 4379.93 (7.68x) | 1908.00 (3.35x) |
| Any DoubleValue NaN WKT JSON stringify | 200.00 | — | — | 2265.02 (11.33x) | 786.88 (3.93x) |
| Any DoubleValue NaN WKT JSON parse | 566.12 | — | — | 4018.74 (7.10x) | 1835.11 (3.24x) |
| Any DoubleValue Infinity WKT JSON stringify | 206.75 | — | — | 2223.42 (10.75x) | 787.16 (3.81x) |
| Any DoubleValue Infinity WKT JSON parse | 572.83 | — | — | 4070.70 (7.11x) | 1878.90 (3.28x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 207.65 | — | — | 2254.23 (10.86x) | 775.24 (3.73x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 576.37 | — | — | 4065.20 (7.05x) | 1870.62 (3.25x) |
| Any FloatValue WKT JSON stringify | 260.92 | — | — | 2787.41 (10.68x) | 893.75 (3.43x) |
| Any FloatValue WKT JSON parse | 572.51 | — | — | 4333.69 (7.57x) | 1880.83 (3.29x) |
| Any FloatValue NaN WKT JSON stringify | 203.20 | — | — | 2218.49 (10.92x) | 798.10 (3.93x) |
| Any FloatValue NaN WKT JSON parse | 567.07 | — | — | 4034.30 (7.11x) | 1832.44 (3.23x) |
| Any FloatValue Infinity WKT JSON stringify | 208.92 | — | — | 2176.99 (10.42x) | 776.22 (3.72x) |
| Any FloatValue Infinity WKT JSON parse | 571.20 | — | — | 4030.88 (7.06x) | 1838.59 (3.22x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 209.05 | — | — | 2196.60 (10.51x) | 785.89 (3.76x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 573.57 | — | — | 4046.46 (7.05x) | 1881.06 (3.28x) |
| Any Int64Value WKT JSON stringify | 207.66 | — | — | 2176.81 (10.48x) | 1116.68 (5.38x) |
| Any Int64Value WKT JSON parse | 617.40 | — | — | 4262.45 (6.90x) | 2334.69 (3.78x) |
| Any UInt64Value WKT JSON stringify | 217.24 | — | — | 2206.43 (10.16x) | 1127.51 (5.19x) |
| Any UInt64Value WKT JSON parse | 619.61 | — | — | 4300.96 (6.94x) | 2213.04 (3.57x) |
| Any Int32Value WKT JSON stringify | 210.12 | — | — | 2263.81 (10.77x) | 799.35 (3.80x) |
| Any Int32Value WKT JSON parse | 588.14 | — | — | 4150.84 (7.06x) | 1942.77 (3.30x) |
| Any UInt32Value WKT JSON stringify | 218.99 | — | — | 2160.28 (9.86x) | 847.35 (3.87x) |
| Any UInt32Value WKT JSON parse | 594.04 | — | — | 4133.71 (6.96x) | 1981.53 (3.34x) |
| Any BoolValue WKT JSON stringify | 212.34 | — | — | 2123.29 (10.00x) | 800.23 (3.77x) |
| Any BoolValue WKT JSON parse | 547.69 | — | — | 4016.40 (7.33x) | 1731.25 (3.16x) |
| Any StringValue WKT JSON stringify | 244.98 | — | — | 2247.44 (9.17x) | 896.66 (3.66x) |
| Any StringValue WKT JSON parse | 605.37 | — | — | 4066.45 (6.72x) | 1909.01 (3.15x) |
| Any BytesValue WKT JSON stringify | 225.16 | — | — | 2287.58 (10.16x) | 950.50 (4.22x) |
| Any BytesValue WKT JSON parse | 613.21 | — | — | 4185.09 (6.82x) | 1978.14 (3.23x) |
| Nested Any WKT JSON stringify | 384.86 | — | — | 3405.69 (8.85x) | 1571.50 (4.08x) |
| Nested Any WKT JSON parse | 986.10 | — | — | 5998.18 (6.08x) | 3558.82 (3.61x) |
| Duration JSON stringify | 64.50 | — | — | 1547.83 (24.00x) | 399.82 (6.20x) |
| Duration JSON parse | 12.05 | — | — | 2291.55 (190.17x) | 422.56 (35.07x) |
| NegativeDuration JSON stringify | 65.20 | — | — | 1581.20 (24.25x) | 453.98 (6.96x) |
| NegativeDuration JSON parse | 12.55 | — | — | 2382.25 (189.82x) | 426.73 (34.00x) |
| FieldMask JSON stringify | 90.82 | — | — | 1290.25 (14.21x) | 742.08 (8.17x) |
| FieldMask JSON parse | 178.95 | — | — | 2603.19 (14.55x) | 1023.10 (5.72x) |
| Timestamp JSON stringify | 129.60 | — | — | 1717.10 (13.25x) | 465.89 (3.59x) |
| Timestamp JSON parse | 56.72 | — | — | 2328.10 (41.05x) | 479.31 (8.45x) |
| PreEpoch Timestamp JSON stringify | 88.02 | — | — | 1609.12 (18.28x) | 450.22 (5.11x) |
| PreEpoch Timestamp JSON parse | 54.74 | — | — | 2292.02 (41.87x) | 464.33 (8.48x) |
| Empty JSON stringify | 22.45 | — | — | 728.88 (32.47x) | 107.56 (4.79x) |
| Empty JSON parse | 76.58 | — | — | 1114.15 (14.55x) | 246.33 (3.22x) |
| Struct JSON stringify | 270.01 | — | — | 8832.55 (32.71x) | 4159.62 (15.41x) |
| Struct JSON parse | 929.61 | — | — | 16757.00 (18.03x) | 6387.83 (6.87x) |
| Value JSON stringify | 274.91 | — | — | 9717.26 (35.35x) | 4332.94 (15.76x) |
| Value JSON parse | 981.88 | — | — | 17484.00 (17.81x) | 6696.64 (6.82x) |
| ListValue JSON stringify | 201.74 | — | — | 7486.92 (37.11x) | 2813.24 (13.94x) |
| ListValue JSON parse | 730.10 | — | — | 13486.50 (18.47x) | 5281.55 (7.23x) |
| DoubleValue JSON stringify | 97.41 | — | — | 1464.81 (15.04x) | 209.52 (2.15x) |
| DoubleValue JSON parse | 113.86 | — | — | 2088.58 (18.34x) | 338.83 (2.98x) |
| DoubleValue NaN JSON stringify | 52.45 | — | — | 982.04 (18.72x) | 143.34 (2.73x) |
| DoubleValue NaN JSON parse | 101.21 | — | — | 1701.85 (16.82x) | 312.59 (3.09x) |
| DoubleValue Infinity JSON stringify | 55.84 | — | — | 961.18 (17.21x) | 141.65 (2.54x) |
| DoubleValue Infinity JSON parse | 104.26 | — | — | 1699.03 (16.30x) | 308.96 (2.96x) |
| DoubleValue NegativeInfinity JSON stringify | 56.38 | — | — | 982.61 (17.43x) | 136.17 (2.42x) |
| DoubleValue NegativeInfinity JSON parse | 107.30 | — | — | 1736.54 (16.18x) | 322.50 (3.01x) |
| FloatValue JSON stringify | 102.33 | — | — | 1404.32 (13.72x) | 191.41 (1.87x) |
| FloatValue JSON parse | 112.10 | — | — | 2110.19 (18.82x) | 311.54 (2.78x) |
| FloatValue NaN JSON stringify | 52.90 | — | — | 999.08 (18.89x) | 144.22 (2.73x) |
| FloatValue NaN JSON parse | 101.33 | — | — | 1692.01 (16.70x) | 303.36 (2.99x) |
| FloatValue Infinity JSON stringify | 55.87 | — | — | 988.01 (17.68x) | 137.50 (2.46x) |
| FloatValue Infinity JSON parse | 104.02 | — | — | 1693.03 (16.28x) | 309.39 (2.97x) |
| FloatValue NegativeInfinity JSON stringify | 56.39 | — | — | 964.11 (17.10x) | 143.67 (2.55x) |
| FloatValue NegativeInfinity JSON parse | 106.01 | — | — | 1721.21 (16.24x) | 313.83 (2.96x) |
| Int64Value JSON stringify | 41.79 | — | — | 1000.90 (23.95x) | 283.26 (6.78x) |
| Int64Value JSON parse | 139.53 | — | — | 1990.30 (14.26x) | 508.44 (3.64x) |
| UInt64Value JSON stringify | 41.83 | — | — | 995.61 (23.80x) | 301.20 (7.20x) |
| UInt64Value JSON parse | 138.11 | — | — | 1951.86 (14.13x) | 514.98 (3.73x) |
| Int32Value JSON stringify | 45.83 | — | — | 978.82 (21.36x) | 143.21 (3.12x) |
| Int32Value JSON parse | 136.31 | — | — | 1908.84 (14.00x) | 341.92 (2.51x) |
| UInt32Value JSON stringify | 46.36 | — | — | 918.14 (19.80x) | 144.46 (3.12x) |
| UInt32Value JSON parse | 136.20 | — | — | 1912.58 (14.04x) | 340.08 (2.50x) |
| BoolValue JSON stringify | 42.42 | — | — | 904.93 (21.33x) | 141.04 (3.32x) |
| BoolValue JSON parse | 59.18 | — | — | 1687.84 (28.52x) | 249.27 (4.21x) |
| StringValue JSON stringify | 53.37 | — | — | 999.08 (18.72x) | 198.31 (3.72x) |
| StringValue JSON parse | 131.22 | — | — | 1780.91 (13.57x) | 356.40 (2.72x) |
| BytesValue JSON stringify | 47.37 | — | — | 972.93 (20.54x) | 223.26 (4.71x) |
| BytesValue JSON parse | 141.98 | — | — | 1963.51 (13.83x) | 372.18 (2.62x) |
| TextFormat parse | 845.82 | — | — | 5640.33 (6.67x) | 8323.78 (9.84x) |
| packed int32 decode | 995.83 | 3014.11 (3.03x) | 4375.56 (4.39x) | 1341.63 (1.35x) | 4369.44 (4.39x) |
| packed bool encode | 2.88 | 2079.53 (722.06x) | 539.10 (187.19x) | 22.43 (7.79x) | 4386.78 (1523.19x) |
| packed bool decode | 279.26 | 2060.85 (7.38x) | 4047.32 (14.49x) | 1107.77 (3.97x) | 2719.42 (9.74x) |
| largebytes decode | 127.98 | 8581.21 (67.05x) | 4543.90 (35.50x) | 4069.38 (31.80x) | 23742.38 (185.52x) |
| large map decode | 38001.26 | 128260.26 (3.38x) | 130337.46 (3.43x) | 117368.00 (3.09x) | 295381.58 (7.77x) |
| shuffled large map deterministic binary encode | 36231.44 | — | — | 116319.00 (3.21x) | 455345.77 (12.57x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded positive/negative `Duration`, `Struct`, `Value`,
`FieldMask`, post/pre-epoch `Timestamp`, `Empty`, `Int64Value`, `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), `UInt64Value`, `Int32Value`, `UInt32Value`, `BoolValue`, `StringValue`, `BytesValue`, and recursive nested `Any` payloads), direct positive/negative Duration and post/pre-epoch Timestamp WKT JSON plus other direct WKT JSON, TextFormat, packed scalars, large bytes,
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
