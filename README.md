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

Latest accepted comparison (`/tmp/pbz-compare-after-negative-infinity-json-isolated.log`,
summarized in `/tmp/pbz-summary-after-negative-infinity-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 24.88 | 124.62 (5.01x) | 62.16 (2.50x) | 125.33 (5.04x) | 954.15 (38.35x) |
| binary decode | 137.98 | 296.52 (2.15x) | 302.92 (2.20x) | 264.34 (1.92x) | 992.53 (7.19x) |
| unknown count by number | 5.02 | — | — | 212.76 (42.38x) | — |
| scalarmix encode | 27.07 | 113.40 (4.19x) | 67.14 (2.48x) | 45.61 (1.69x) | 237.80 (8.78x) |
| scalarmix decode | 50.58 | 162.11 (3.21x) | 208.67 (4.13x) | 112.25 (2.22x) | 363.44 (7.19x) |
| textbytes encode | 13.38 | 91.09 (6.81x) | 43.25 (3.23x) | 146.30 (10.93x) | 172.49 (12.89x) |
| complex decode | 228.39 | 473.10 (2.07x) | 427.12 (1.87x) | 488.24 (2.14x) | 1663.63 (7.28x) |
| complex JSON parse | 2744.47 | — | — | 16987.00 (6.19x) | 10557.39 (3.85x) |
| Any WKT JSON stringify | 173.32 | — | — | 3037.40 (17.52x) | 1382.92 (7.98x) |
| Any WKT JSON parse | 576.13 | — | — | 4627.20 (8.03x) | 2054.31 (3.57x) |
| Any FieldMask WKT JSON stringify | 274.92 | — | — | 2462.02 (8.96x) | 1757.24 (6.39x) |
| Any FieldMask WKT JSON parse | 797.03 | — | — | 4924.05 (6.18x) | 2892.40 (3.63x) |
| Any Timestamp WKT JSON stringify | 237.03 | — | — | 3010.05 (12.70x) | 1338.02 (5.64x) |
| Any Timestamp WKT JSON parse | 648.33 | — | — | 4613.39 (7.12x) | 2266.76 (3.50x) |
| Any Empty WKT JSON stringify | 115.10 | — | — | 1282.63 (11.14x) | 673.75 (5.85x) |
| Any Empty WKT JSON parse | 379.46 | — | — | 3122.10 (8.23x) | 1632.10 (4.30x) |
| Any Struct WKT JSON stringify | 759.43 | — | — | 8889.00 (11.70x) | 8933.34 (11.76x) |
| Any Struct WKT JSON parse | 1975.60 | — | — | 16762.50 (8.48x) | 12594.51 (6.38x) |
| Any Value WKT JSON stringify | 786.38 | — | — | 9116.81 (11.59x) | 9425.59 (11.99x) |
| Any Value WKT JSON parse | 2034.51 | — | — | 17133.60 (8.42x) | 13058.94 (6.42x) |
| Any DoubleValue WKT JSON stringify | 242.90 | — | — | 2863.02 (11.79x) | 903.49 (3.72x) |
| Any DoubleValue WKT JSON parse | 579.54 | — | — | 4345.40 (7.50x) | 1911.48 (3.30x) |
| Any DoubleValue NaN WKT JSON stringify | 185.65 | — | — | 2316.03 (12.48x) | 779.49 (4.20x) |
| Any DoubleValue NaN WKT JSON parse | 576.41 | — | — | 4027.11 (6.99x) | 1865.16 (3.24x) |
| Any DoubleValue Infinity WKT JSON stringify | 189.27 | — | — | 2303.12 (12.17x) | 784.03 (4.14x) |
| Any DoubleValue Infinity WKT JSON parse | 581.70 | — | — | 4026.41 (6.92x) | 1879.57 (3.23x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 191.07 | — | — | 2257.65 (11.82x) | 774.56 (4.05x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 584.38 | — | — | 4053.63 (6.94x) | 1849.15 (3.16x) |
| Any FloatValue WKT JSON stringify | 248.54 | — | — | 2750.31 (11.07x) | 885.94 (3.56x) |
| Any FloatValue WKT JSON parse | 581.45 | — | — | 4347.59 (7.48x) | 1877.83 (3.23x) |
| Any FloatValue NaN WKT JSON stringify | 197.23 | — | — | 2215.87 (11.23x) | 787.13 (3.99x) |
| Any FloatValue NaN WKT JSON parse | 577.45 | — | — | 4083.20 (7.07x) | 1804.17 (3.12x) |
| Any FloatValue Infinity WKT JSON stringify | 190.50 | — | — | 2181.07 (11.45x) | 778.78 (4.09x) |
| Any FloatValue Infinity WKT JSON parse | 582.11 | — | — | 4075.54 (7.00x) | 1837.26 (3.16x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 191.78 | — | — | 2168.81 (11.31x) | 794.00 (4.14x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 584.81 | — | — | 4047.74 (6.92x) | 1820.87 (3.11x) |
| Any Int64Value WKT JSON stringify | 200.72 | — | — | 2231.60 (11.12x) | 1113.66 (5.55x) |
| Any Int64Value WKT JSON parse | 629.40 | — | — | 4242.35 (6.74x) | 2282.77 (3.63x) |
| Any UInt64Value WKT JSON stringify | 210.45 | — | — | 2219.07 (10.54x) | 1120.89 (5.33x) |
| Any UInt64Value WKT JSON parse | 638.92 | — | — | 4278.54 (6.70x) | 2208.08 (3.46x) |
| Any Int32Value WKT JSON stringify | 202.73 | — | — | 2213.85 (10.92x) | 877.38 (4.33x) |
| Any Int32Value WKT JSON parse | 602.49 | — | — | 4102.31 (6.81x) | 1942.46 (3.22x) |
| Any UInt32Value WKT JSON stringify | 212.99 | — | — | 2170.44 (10.19x) | 835.30 (3.92x) |
| Any UInt32Value WKT JSON parse | 608.25 | — | — | 4139.42 (6.81x) | 1932.44 (3.18x) |
| Any BoolValue WKT JSON stringify | 207.99 | — | — | 2134.24 (10.26x) | 826.04 (3.97x) |
| Any BoolValue WKT JSON parse | 555.11 | — | — | 4015.15 (7.23x) | 1791.09 (3.23x) |
| Any StringValue WKT JSON stringify | 234.14 | — | — | 2219.10 (9.48x) | 882.95 (3.77x) |
| Any StringValue WKT JSON parse | 617.99 | — | — | 4081.55 (6.60x) | 1934.83 (3.13x) |
| Any BytesValue WKT JSON stringify | 221.07 | — | — | 2275.26 (10.29x) | 931.17 (4.21x) |
| Any BytesValue WKT JSON parse | 626.73 | — | — | 4255.48 (6.79x) | 1983.69 (3.17x) |
| Nested Any WKT JSON stringify | 351.50 | — | — | 3401.56 (9.68x) | 1580.35 (4.50x) |
| Nested Any WKT JSON parse | 1005.00 | — | — | 6108.72 (6.08x) | 3570.46 (3.55x) |
| Duration JSON stringify | 63.56 | — | — | 1561.87 (24.57x) | 380.28 (5.98x) |
| Duration JSON parse | 10.89 | — | — | 2332.56 (214.19x) | 426.16 (39.13x) |
| FieldMask JSON stringify | 93.19 | — | — | 1316.25 (14.12x) | 728.19 (7.81x) |
| FieldMask JSON parse | 178.17 | — | — | 2697.58 (15.14x) | 1085.65 (6.09x) |
| Timestamp JSON stringify | 126.15 | — | — | 1701.62 (13.49x) | 465.95 (3.69x) |
| Timestamp JSON parse | 57.28 | — | — | 2328.03 (40.64x) | 480.96 (8.40x) |
| Empty JSON stringify | 22.93 | — | — | 686.41 (29.93x) | 99.23 (4.33x) |
| Empty JSON parse | 73.50 | — | — | 1094.78 (14.89x) | 240.75 (3.28x) |
| Struct JSON stringify | 257.80 | — | — | 8916.03 (34.59x) | 4202.32 (16.30x) |
| Struct JSON parse | 940.49 | — | — | 16773.50 (17.83x) | 6358.62 (6.76x) |
| Value JSON stringify | 264.07 | — | — | 9789.33 (37.07x) | 4331.76 (16.40x) |
| Value JSON parse | 942.39 | — | — | 18065.90 (19.17x) | 6660.71 (7.07x) |
| ListValue JSON stringify | 194.61 | — | — | 7579.01 (38.94x) | 2848.33 (14.64x) |
| ListValue JSON parse | 737.45 | — | — | 13518.10 (18.33x) | 5281.10 (7.16x) |
| DoubleValue JSON stringify | 97.41 | — | — | 1470.75 (15.10x) | 204.10 (2.10x) |
| DoubleValue JSON parse | 113.11 | — | — | 2128.07 (18.81x) | 331.52 (2.93x) |
| DoubleValue NaN JSON stringify | 52.27 | — | — | 1009.26 (19.31x) | 138.49 (2.65x) |
| DoubleValue NaN JSON parse | 101.02 | — | — | 1725.33 (17.08x) | 311.91 (3.09x) |
| DoubleValue Infinity JSON stringify | 55.70 | — | — | 1001.19 (17.97x) | 135.91 (2.44x) |
| DoubleValue Infinity JSON parse | 104.85 | — | — | 1733.36 (16.53x) | 310.11 (2.96x) |
| DoubleValue NegativeInfinity JSON stringify | 57.72 | — | — | 986.22 (17.09x) | 140.12 (2.43x) |
| DoubleValue NegativeInfinity JSON parse | 108.91 | — | — | 1744.78 (16.02x) | 315.97 (2.90x) |
| FloatValue JSON stringify | 104.33 | — | — | 1385.54 (13.28x) | 201.85 (1.93x) |
| FloatValue JSON parse | 113.32 | — | — | 2125.15 (18.75x) | 321.04 (2.83x) |
| FloatValue NaN JSON stringify | 52.45 | — | — | 973.69 (18.56x) | 131.55 (2.51x) |
| FloatValue NaN JSON parse | 102.13 | — | — | 1705.37 (16.70x) | 293.61 (2.87x) |
| FloatValue Infinity JSON stringify | 55.99 | — | — | 963.93 (17.22x) | 159.19 (2.84x) |
| FloatValue Infinity JSON parse | 105.35 | — | — | 1729.48 (16.42x) | 302.56 (2.87x) |
| FloatValue NegativeInfinity JSON stringify | 57.67 | — | — | 955.78 (16.57x) | 147.19 (2.55x) |
| FloatValue NegativeInfinity JSON parse | 108.93 | — | — | 1735.84 (15.94x) | 308.36 (2.83x) |
| Int64Value JSON stringify | 44.89 | — | — | 1023.53 (22.80x) | 295.70 (6.59x) |
| Int64Value JSON parse | 137.06 | — | — | 1990.33 (14.52x) | 515.56 (3.76x) |
| UInt64Value JSON stringify | 44.64 | — | — | 984.15 (22.05x) | 300.16 (6.72x) |
| UInt64Value JSON parse | 137.19 | — | — | 1946.38 (14.19x) | 513.71 (3.74x) |
| Int32Value JSON stringify | 47.15 | — | — | 973.05 (20.64x) | 158.88 (3.37x) |
| Int32Value JSON parse | 129.04 | — | — | 1918.45 (14.87x) | 349.03 (2.70x) |
| UInt32Value JSON stringify | 46.90 | — | — | 922.02 (19.66x) | 164.78 (3.51x) |
| UInt32Value JSON parse | 130.27 | — | — | 1927.08 (14.79x) | 375.02 (2.88x) |
| BoolValue JSON stringify | 42.17 | — | — | 913.53 (21.66x) | 129.74 (3.08x) |
| BoolValue JSON parse | 58.98 | — | — | 1706.11 (28.93x) | 267.80 (4.54x) |
| StringValue JSON stringify | 52.99 | — | — | 1011.59 (19.09x) | 202.17 (3.82x) |
| StringValue JSON parse | 130.07 | — | — | 1842.29 (14.16x) | 360.79 (2.77x) |
| BytesValue JSON stringify | 47.51 | — | — | 959.99 (20.21x) | 232.54 (4.89x) |
| BytesValue JSON parse | 142.95 | — | — | 1975.99 (13.82x) | 372.60 (2.61x) |
| TextFormat parse | 849.23 | — | — | 5520.85 (6.50x) | 8080.81 (9.52x) |
| packed int32 decode | 1029.78 | 2999.22 (2.91x) | 4248.18 (4.13x) | 1342.50 (1.30x) | 4475.33 (4.35x) |
| packed bool encode | 2.76 | 2079.42 (753.41x) | 539.19 (195.36x) | 22.69 (8.22x) | 4384.73 (1588.67x) |
| packed bool decode | 271.43 | 2082.41 (7.67x) | 3869.73 (14.26x) | 1107.27 (4.08x) | 2670.49 (9.84x) |
| largebytes decode | 126.54 | 8521.30 (67.34x) | 4606.83 (36.41x) | 6079.19 (48.04x) | 23800.80 (188.09x) |
| large map decode | 37698.77 | 129556.07 (3.44x) | 118420.28 (3.14x) | 122877.00 (3.26x) | 298202.14 (7.91x) |
| shuffled large map deterministic binary encode | 36095.37 | — | — | 110229.00 (3.05x) | 460001.16 (12.74x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded `Duration`, `Struct`, `Value`,
`FieldMask`, `Timestamp`, `Empty`, `Int64Value`, `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), `UInt64Value`, `Int32Value`, `UInt32Value`, `BoolValue`, `StringValue`, `BytesValue`, and recursive nested `Any` payloads), direct WKT JSON, TextFormat, packed scalars, large bytes,
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
