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

Latest accepted comparison (`/tmp/pbz-compare-after-negative-duration-json-isolated.log`,
summarized in `/tmp/pbz-summary-after-negative-duration-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 25.48 | 125.12 (4.91x) | 64.45 (2.53x) | 122.62 (4.81x) | 951.67 (37.35x) |
| binary decode | 127.27 | 301.87 (2.37x) | 299.08 (2.35x) | 272.57 (2.14x) | 982.84 (7.72x) |
| unknown count by number | 5.03 | — | — | 175.56 (34.90x) | — |
| scalarmix encode | 26.20 | 116.77 (4.46x) | 66.89 (2.55x) | 45.76 (1.75x) | 247.67 (9.45x) |
| scalarmix decode | 55.76 | 166.72 (2.99x) | 219.39 (3.93x) | 112.35 (2.01x) | 358.41 (6.43x) |
| textbytes encode | 11.78 | 93.92 (7.97x) | 43.29 (3.67x) | 146.38 (12.43x) | 170.60 (14.48x) |
| complex decode | 216.04 | 461.62 (2.14x) | 430.64 (1.99x) | 486.62 (2.25x) | 1629.01 (7.54x) |
| complex JSON parse | 2750.11 | — | — | 16721.40 (6.08x) | 10500.26 (3.82x) |
| Any WKT JSON stringify | 179.65 | — | — | 3061.46 (17.04x) | 1336.03 (7.44x) |
| Any WKT JSON parse | 586.06 | — | — | 4580.14 (7.82x) | 2100.27 (3.58x) |
| Any NegativeDuration WKT JSON stringify | 193.66 | — | — | 3082.26 (15.92x) | 1383.75 (7.15x) |
| Any NegativeDuration WKT JSON parse | 581.65 | — | — | 4717.11 (8.11x) | 2153.03 (3.70x) |
| Any FieldMask WKT JSON stringify | 281.24 | — | — | 2477.44 (8.81x) | 1793.25 (6.38x) |
| Any FieldMask WKT JSON parse | 798.93 | — | — | 4859.87 (6.08x) | 2936.56 (3.68x) |
| Any Timestamp WKT JSON stringify | 247.87 | — | — | 3051.40 (12.31x) | 1382.62 (5.58x) |
| Any Timestamp WKT JSON parse | 642.25 | — | — | 4778.85 (7.44x) | 2244.55 (3.49x) |
| Any Empty WKT JSON stringify | 123.57 | — | — | 1314.48 (10.64x) | 664.06 (5.37x) |
| Any Empty WKT JSON parse | 377.77 | — | — | 3187.66 (8.44x) | 1688.51 (4.47x) |
| Any Struct WKT JSON stringify | 783.13 | — | — | 8992.98 (11.48x) | 8840.23 (11.29x) |
| Any Struct WKT JSON parse | 2022.41 | — | — | 16890.90 (8.35x) | 12716.86 (6.29x) |
| Any Value WKT JSON stringify | 835.38 | — | — | 9197.04 (11.01x) | 9267.01 (11.09x) |
| Any Value WKT JSON parse | 2086.44 | — | — | 16782.90 (8.04x) | 13526.03 (6.48x) |
| Any DoubleValue WKT JSON stringify | 254.68 | — | — | 2819.07 (11.07x) | 893.56 (3.51x) |
| Any DoubleValue WKT JSON parse | 578.40 | — | — | 4392.40 (7.59x) | 1956.56 (3.38x) |
| Any DoubleValue NaN WKT JSON stringify | 199.03 | — | — | 2305.33 (11.58x) | 782.69 (3.93x) |
| Any DoubleValue NaN WKT JSON parse | 572.48 | — | — | 3977.14 (6.95x) | 1853.25 (3.24x) |
| Any DoubleValue Infinity WKT JSON stringify | 204.66 | — | — | 2253.78 (11.01x) | 777.74 (3.80x) |
| Any DoubleValue Infinity WKT JSON parse | 577.44 | — | — | 4000.14 (6.93x) | 1888.08 (3.27x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 206.96 | — | — | 2307.48 (11.15x) | 797.60 (3.85x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 579.90 | — | — | 4196.81 (7.24x) | 1901.39 (3.28x) |
| Any FloatValue WKT JSON stringify | 258.42 | — | — | 2851.96 (11.04x) | 937.86 (3.63x) |
| Any FloatValue WKT JSON parse | 577.41 | — | — | 4290.36 (7.43x) | 1892.99 (3.28x) |
| Any FloatValue NaN WKT JSON stringify | 209.93 | — | — | 2247.72 (10.71x) | 776.61 (3.70x) |
| Any FloatValue NaN WKT JSON parse | 574.65 | — | — | 4002.64 (6.97x) | 1847.52 (3.22x) |
| Any FloatValue Infinity WKT JSON stringify | 208.75 | — | — | 2199.77 (10.54x) | 788.05 (3.78x) |
| Any FloatValue Infinity WKT JSON parse | 578.59 | — | — | 4005.74 (6.92x) | 1829.64 (3.16x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 212.07 | — | — | 2208.61 (10.41x) | 807.27 (3.81x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 585.99 | — | — | 3989.55 (6.81x) | 1901.97 (3.25x) |
| Any Int64Value WKT JSON stringify | 206.32 | — | — | 2248.81 (10.90x) | 1163.80 (5.64x) |
| Any Int64Value WKT JSON parse | 625.37 | — | — | 4291.29 (6.86x) | 2379.82 (3.81x) |
| Any UInt64Value WKT JSON stringify | 215.53 | — | — | 2295.09 (10.65x) | 1142.10 (5.30x) |
| Any UInt64Value WKT JSON parse | 632.05 | — | — | 4240.93 (6.71x) | 2271.79 (3.59x) |
| Any Int32Value WKT JSON stringify | 209.52 | — | — | 2268.78 (10.83x) | 823.24 (3.93x) |
| Any Int32Value WKT JSON parse | 599.96 | — | — | 4074.34 (6.79x) | 1950.29 (3.25x) |
| Any UInt32Value WKT JSON stringify | 220.83 | — | — | 2209.21 (10.00x) | 835.09 (3.78x) |
| Any UInt32Value WKT JSON parse | 606.31 | — | — | 4075.93 (6.72x) | 1998.41 (3.30x) |
| Any BoolValue WKT JSON stringify | 219.21 | — | — | 2188.96 (9.99x) | 796.83 (3.64x) |
| Any BoolValue WKT JSON parse | 557.21 | — | — | 4052.15 (7.27x) | 1739.87 (3.12x) |
| Any StringValue WKT JSON stringify | 248.89 | — | — | 2212.20 (8.89x) | 958.89 (3.85x) |
| Any StringValue WKT JSON parse | 619.48 | — | — | 4071.25 (6.57x) | 2077.63 (3.35x) |
| Any BytesValue WKT JSON stringify | 231.57 | — | — | 2325.23 (10.04x) | 1018.60 (4.40x) |
| Any BytesValue WKT JSON parse | 621.87 | — | — | 4230.19 (6.80x) | 2100.06 (3.38x) |
| Nested Any WKT JSON stringify | 391.89 | — | — | 3434.59 (8.76x) | 1572.64 (4.01x) |
| Nested Any WKT JSON parse | 1005.04 | — | — | 6081.29 (6.05x) | 3728.44 (3.71x) |
| Duration JSON stringify | 64.92 | — | — | 1553.09 (23.92x) | 367.91 (5.67x) |
| Duration JSON parse | 12.08 | — | — | 2301.47 (190.52x) | 437.23 (36.19x) |
| NegativeDuration JSON stringify | 65.44 | — | — | 1623.27 (24.81x) | 446.63 (6.83x) |
| NegativeDuration JSON parse | 12.61 | — | — | 2397.66 (190.14x) | 441.27 (34.99x) |
| FieldMask JSON stringify | 91.61 | — | — | 1269.17 (13.85x) | 720.14 (7.86x) |
| FieldMask JSON parse | 181.61 | — | — | 2671.02 (14.71x) | 1074.48 (5.92x) |
| Timestamp JSON stringify | 126.13 | — | — | 1712.59 (13.58x) | 465.58 (3.69x) |
| Timestamp JSON parse | 57.03 | — | — | 2324.52 (40.76x) | 476.84 (8.36x) |
| Empty JSON stringify | 22.77 | — | — | 679.63 (29.85x) | 95.93 (4.21x) |
| Empty JSON parse | 75.13 | — | — | 1089.37 (14.50x) | 249.91 (3.33x) |
| Struct JSON stringify | 277.67 | — | — | 8877.31 (31.97x) | 4159.63 (14.98x) |
| Struct JSON parse | 959.47 | — | — | 16519.10 (17.22x) | 6291.53 (6.56x) |
| Value JSON stringify | 279.60 | — | — | 9906.45 (35.43x) | 4329.61 (15.49x) |
| Value JSON parse | 964.87 | — | — | 17810.40 (18.46x) | 6653.68 (6.90x) |
| ListValue JSON stringify | 202.22 | — | — | 7570.80 (37.44x) | 2788.22 (13.79x) |
| ListValue JSON parse | 742.04 | — | — | 13550.30 (18.26x) | 5192.34 (7.00x) |
| DoubleValue JSON stringify | 97.62 | — | — | 1484.49 (15.21x) | 195.24 (2.00x) |
| DoubleValue JSON parse | 113.76 | — | — | 2101.85 (18.48x) | 318.15 (2.80x) |
| DoubleValue NaN JSON stringify | 54.05 | — | — | 971.95 (17.98x) | 134.44 (2.49x) |
| DoubleValue NaN JSON parse | 101.52 | — | — | 1716.92 (16.91x) | 309.21 (3.05x) |
| DoubleValue Infinity JSON stringify | 57.69 | — | — | 956.26 (16.58x) | 134.01 (2.32x) |
| DoubleValue Infinity JSON parse | 103.71 | — | — | 1718.02 (16.57x) | 326.11 (3.14x) |
| DoubleValue NegativeInfinity JSON stringify | 59.16 | — | — | 990.89 (16.75x) | 144.43 (2.44x) |
| DoubleValue NegativeInfinity JSON parse | 108.00 | — | — | 1759.18 (16.29x) | 323.88 (3.00x) |
| FloatValue JSON stringify | 101.43 | — | — | 1425.50 (14.05x) | 204.31 (2.01x) |
| FloatValue JSON parse | 114.25 | — | — | 2151.27 (18.83x) | 313.60 (2.74x) |
| FloatValue NaN JSON stringify | 54.53 | — | — | 967.58 (17.74x) | 132.67 (2.43x) |
| FloatValue NaN JSON parse | 102.55 | — | — | 1707.37 (16.65x) | 310.23 (3.03x) |
| FloatValue Infinity JSON stringify | 57.78 | — | — | 942.12 (16.31x) | 142.95 (2.47x) |
| FloatValue Infinity JSON parse | 104.65 | — | — | 1732.53 (16.56x) | 311.55 (2.98x) |
| FloatValue NegativeInfinity JSON stringify | 59.11 | — | — | 960.43 (16.25x) | 143.01 (2.42x) |
| FloatValue NegativeInfinity JSON parse | 107.55 | — | — | 1716.40 (15.96x) | 329.36 (3.06x) |
| Int64Value JSON stringify | 41.95 | — | — | 1015.79 (24.21x) | 296.42 (7.07x) |
| Int64Value JSON parse | 139.86 | — | — | 1984.93 (14.19x) | 524.62 (3.75x) |
| UInt64Value JSON stringify | 42.28 | — | — | 1001.61 (23.69x) | 291.39 (6.89x) |
| UInt64Value JSON parse | 140.20 | — | — | 1945.57 (13.88x) | 509.54 (3.63x) |
| Int32Value JSON stringify | 46.41 | — | — | 975.28 (21.01x) | 141.90 (3.06x) |
| Int32Value JSON parse | 129.98 | — | — | 1902.74 (14.64x) | 333.91 (2.57x) |
| UInt32Value JSON stringify | 45.92 | — | — | 912.89 (19.88x) | 147.98 (3.22x) |
| UInt32Value JSON parse | 129.76 | — | — | 1890.03 (14.57x) | 342.19 (2.64x) |
| BoolValue JSON stringify | 42.14 | — | — | 873.12 (20.72x) | 141.03 (3.35x) |
| BoolValue JSON parse | 58.97 | — | — | 1687.37 (28.61x) | 244.74 (4.15x) |
| StringValue JSON stringify | 53.85 | — | — | 1026.26 (19.06x) | 198.20 (3.68x) |
| StringValue JSON parse | 130.17 | — | — | 1781.32 (13.68x) | 360.75 (2.77x) |
| BytesValue JSON stringify | 47.46 | — | — | 944.00 (19.89x) | 232.71 (4.90x) |
| BytesValue JSON parse | 142.77 | — | — | 1930.32 (13.52x) | 380.74 (2.67x) |
| TextFormat parse | 839.57 | — | — | 5460.01 (6.50x) | 8044.91 (9.58x) |
| packed int32 decode | 1093.52 | 2994.05 (2.74x) | 5510.28 (5.04x) | 1341.50 (1.23x) | 4377.17 (4.00x) |
| packed bool encode | 2.51 | 2079.37 (828.43x) | 539.97 (215.13x) | 23.39 (9.32x) | 4385.50 (1747.21x) |
| packed bool decode | 271.87 | 2060.46 (7.58x) | 4056.71 (14.92x) | 1109.04 (4.08x) | 2711.62 (9.97x) |
| largebytes decode | 124.73 | 8527.61 (68.37x) | 4559.48 (36.55x) | 4011.35 (32.16x) | 23945.88 (191.98x) |
| large map decode | 37571.08 | 134225.40 (3.57x) | 118290.97 (3.15x) | 119786.00 (3.19x) | 296159.23 (7.88x) |
| shuffled large map deterministic binary encode | 36331.29 | — | — | 113353.00 (3.12x) | 450721.60 (12.41x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded positive/negative `Duration`, `Struct`, `Value`,
`FieldMask`, `Timestamp`, `Empty`, `Int64Value`, `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), `UInt64Value`, `Int32Value`, `UInt32Value`, `BoolValue`, `StringValue`, `BytesValue`, and recursive nested `Any` payloads), direct positive/negative Duration WKT JSON plus other direct WKT JSON, TextFormat, packed scalars, large bytes,
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
