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

Latest accepted comparison (`/tmp/pbz-compare-after-double-nan-json-isolated.log`,
summarized in `/tmp/pbz-summary-after-double-nan-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 22.81 | 126.68 (5.55x) | 65.68 (2.88x) | 136.27 (5.97x) | 948.14 (41.57x) |
| binary decode | 128.91 | 301.90 (2.34x) | 338.72 (2.63x) | 266.45 (2.07x) | 983.81 (7.63x) |
| unknown count by number | 5.02 | — | — | 175.69 (35.00x) | — |
| scalarmix encode | 26.82 | 113.75 (4.24x) | 69.30 (2.58x) | 47.31 (1.76x) | 238.95 (8.91x) |
| scalarmix decode | 50.48 | 164.80 (3.26x) | 220.73 (4.37x) | 107.06 (2.12x) | 358.02 (7.09x) |
| textbytes encode | 13.39 | 92.18 (6.88x) | 43.12 (3.22x) | 147.18 (10.99x) | 170.81 (12.76x) |
| complex decode | 223.77 | 472.63 (2.11x) | 437.31 (1.95x) | 471.28 (2.11x) | 1631.24 (7.29x) |
| complex JSON parse | 2712.16 | — | — | 16663.50 (6.14x) | 10486.21 (3.87x) |
| Any WKT JSON stringify | 187.63 | — | — | 3041.70 (16.21x) | 1336.43 (7.12x) |
| Any WKT JSON parse | 597.86 | — | — | 4540.40 (7.59x) | 2064.39 (3.45x) |
| Any FieldMask WKT JSON stringify | 290.83 | — | — | 2411.69 (8.29x) | 1789.35 (6.15x) |
| Any FieldMask WKT JSON parse | 835.23 | — | — | 4789.09 (5.73x) | 2925.62 (3.50x) |
| Any Timestamp WKT JSON stringify | 257.94 | — | — | 2978.52 (11.55x) | 1311.00 (5.08x) |
| Any Timestamp WKT JSON parse | 667.73 | — | — | 4559.47 (6.83x) | 2217.20 (3.32x) |
| Any Empty WKT JSON stringify | 129.58 | — | — | 1261.70 (9.74x) | 653.34 (5.04x) |
| Any Empty WKT JSON parse | 401.19 | — | — | 3066.18 (7.64x) | 1644.14 (4.10x) |
| Any Struct WKT JSON stringify | 808.55 | — | — | 9044.24 (11.19x) | 8903.45 (11.01x) |
| Any Struct WKT JSON parse | 2052.40 | — | — | 17200.90 (8.38x) | 12577.70 (6.13x) |
| Any Value WKT JSON stringify | 824.35 | — | — | 9107.81 (11.05x) | 9255.13 (11.23x) |
| Any Value WKT JSON parse | 2111.65 | — | — | 17071.50 (8.08x) | 12957.83 (6.14x) |
| Any DoubleValue WKT JSON stringify | 269.71 | — | — | 2834.73 (10.51x) | 880.50 (3.26x) |
| Any DoubleValue WKT JSON parse | 597.97 | — | — | 4392.98 (7.35x) | 1923.44 (3.22x) |
| Any DoubleValue NaN WKT JSON stringify | 204.99 | — | — | 2311.42 (11.28x) | 772.36 (3.77x) |
| Any DoubleValue NaN WKT JSON parse | 596.25 | — | — | 4029.94 (6.76x) | 1883.06 (3.16x) |
| Any FloatValue WKT JSON stringify | 266.44 | — | — | 2798.66 (10.50x) | 898.55 (3.37x) |
| Any FloatValue WKT JSON parse | 599.83 | — | — | 4339.27 (7.23x) | 1900.31 (3.17x) |
| Any Int64Value WKT JSON stringify | 211.23 | — | — | 2207.91 (10.45x) | 1116.27 (5.28x) |
| Any Int64Value WKT JSON parse | 652.88 | — | — | 4339.99 (6.65x) | 2330.29 (3.57x) |
| Any UInt64Value WKT JSON stringify | 219.96 | — | — | 2228.75 (10.13x) | 1140.02 (5.18x) |
| Any UInt64Value WKT JSON parse | 654.16 | — | — | 4308.84 (6.59x) | 2278.47 (3.48x) |
| Any Int32Value WKT JSON stringify | 216.55 | — | — | 2235.71 (10.32x) | 798.05 (3.69x) |
| Any Int32Value WKT JSON parse | 619.80 | — | — | 4187.70 (6.76x) | 1975.51 (3.19x) |
| Any UInt32Value WKT JSON stringify | 224.40 | — | — | 2180.73 (9.72x) | 824.86 (3.68x) |
| Any UInt32Value WKT JSON parse | 623.55 | — | — | 4182.20 (6.71x) | 1972.74 (3.16x) |
| Any BoolValue WKT JSON stringify | 218.53 | — | — | 2127.43 (9.74x) | 769.01 (3.52x) |
| Any BoolValue WKT JSON parse | 574.61 | — | — | 4028.32 (7.01x) | 1760.15 (3.06x) |
| Any StringValue WKT JSON stringify | 252.68 | — | — | 2205.72 (8.73x) | 937.08 (3.71x) |
| Any StringValue WKT JSON parse | 635.14 | — | — | 4039.10 (6.36x) | 1962.27 (3.09x) |
| Any BytesValue WKT JSON stringify | 230.46 | — | — | 2303.01 (9.99x) | 916.74 (3.98x) |
| Any BytesValue WKT JSON parse | 642.92 | — | — | 4249.24 (6.61x) | 2009.04 (3.12x) |
| Nested Any WKT JSON stringify | 397.19 | — | — | 3350.36 (8.44x) | 1572.91 (3.96x) |
| Nested Any WKT JSON parse | 1037.01 | — | — | 6042.62 (5.83x) | 3631.46 (3.50x) |
| Duration JSON stringify | 64.77 | — | — | 1526.46 (23.57x) | 369.38 (5.70x) |
| Duration JSON parse | 12.60 | — | — | 2328.79 (184.82x) | 436.42 (34.64x) |
| FieldMask JSON stringify | 92.49 | — | — | 1305.69 (14.12x) | 743.02 (8.03x) |
| FieldMask JSON parse | 187.21 | — | — | 2621.09 (14.00x) | 1061.87 (5.67x) |
| Timestamp JSON stringify | 129.06 | — | — | 1691.47 (13.11x) | 462.71 (3.59x) |
| Timestamp JSON parse | 58.39 | — | — | 2345.01 (40.16x) | 477.60 (8.18x) |
| Empty JSON stringify | 23.85 | — | — | 674.87 (28.30x) | 97.26 (4.08x) |
| Empty JSON parse | 76.12 | — | — | 1104.67 (14.51x) | 246.00 (3.23x) |
| Struct JSON stringify | 280.06 | — | — | 8873.47 (31.68x) | 4158.42 (14.85x) |
| Struct JSON parse | 966.77 | — | — | 16820.60 (17.40x) | 6294.77 (6.51x) |
| Value JSON stringify | 286.31 | — | — | 10074.30 (35.19x) | 4332.74 (15.13x) |
| Value JSON parse | 971.50 | — | — | 17932.30 (18.46x) | 6590.54 (6.78x) |
| ListValue JSON stringify | 204.84 | — | — | 7511.29 (36.67x) | 2818.04 (13.76x) |
| ListValue JSON parse | 760.93 | — | — | 13613.00 (17.89x) | 5190.36 (6.82x) |
| DoubleValue JSON stringify | 100.84 | — | — | 1462.99 (14.51x) | 194.95 (1.93x) |
| DoubleValue JSON parse | 117.21 | — | — | 2105.42 (17.96x) | 318.40 (2.72x) |
| DoubleValue NaN JSON stringify | 54.33 | — | — | 1013.78 (18.66x) | 145.47 (2.68x) |
| DoubleValue NaN JSON parse | 104.39 | — | — | 1712.26 (16.40x) | 308.89 (2.96x) |
| FloatValue JSON stringify | 101.24 | — | — | 1393.91 (13.77x) | 195.00 (1.93x) |
| FloatValue JSON parse | 116.24 | — | — | 2100.53 (18.07x) | 314.98 (2.71x) |
| Int64Value JSON stringify | 43.03 | — | — | 1019.91 (23.70x) | 304.80 (7.08x) |
| Int64Value JSON parse | 141.94 | — | — | 1985.78 (13.99x) | 506.61 (3.57x) |
| UInt64Value JSON stringify | 43.04 | — | — | 1001.41 (23.27x) | 314.30 (7.30x) |
| UInt64Value JSON parse | 141.51 | — | — | 1955.72 (13.82x) | 511.44 (3.61x) |
| Int32Value JSON stringify | 47.45 | — | — | 975.61 (20.56x) | 145.29 (3.06x) |
| Int32Value JSON parse | 133.58 | — | — | 1900.24 (14.23x) | 349.91 (2.62x) |
| UInt32Value JSON stringify | 48.00 | — | — | 927.69 (19.33x) | 142.07 (2.96x) |
| UInt32Value JSON parse | 132.95 | — | — | 1898.06 (14.28x) | 348.87 (2.62x) |
| BoolValue JSON stringify | 49.19 | — | — | 891.39 (18.12x) | 145.52 (2.96x) |
| BoolValue JSON parse | 62.63 | — | — | 1708.98 (27.29x) | 259.79 (4.15x) |
| StringValue JSON stringify | 55.30 | — | — | 1010.94 (18.28x) | 205.10 (3.71x) |
| StringValue JSON parse | 143.07 | — | — | 1816.92 (12.70x) | 357.20 (2.50x) |
| BytesValue JSON stringify | 48.90 | — | — | 972.02 (19.88x) | 224.13 (4.58x) |
| BytesValue JSON parse | 155.42 | — | — | 1961.29 (12.62x) | 389.77 (2.51x) |
| TextFormat parse | 861.37 | — | — | 5542.48 (6.43x) | 8081.88 (9.38x) |
| packed int32 decode | 1033.34 | 3026.09 (2.93x) | 4225.06 (4.09x) | 1448.00 (1.40x) | 4364.22 (4.22x) |
| packed bool encode | 2.41 | 2079.80 (862.99x) | 539.24 (223.75x) | 23.55 (9.77x) | 4381.67 (1818.12x) |
| packed bool decode | 272.91 | 2231.47 (8.18x) | 4040.94 (14.81x) | 1107.98 (4.06x) | 2661.23 (9.75x) |
| largebytes decode | 125.91 | 8485.95 (67.40x) | 4514.50 (35.85x) | 4011.19 (31.86x) | 23680.13 (188.07x) |
| large map decode | 38205.34 | 121266.36 (3.17x) | 126757.77 (3.32x) | 117326.00 (3.07x) | 296516.51 (7.76x) |
| shuffled large map deterministic binary encode | 37878.65 | — | — | 111909.00 (2.95x) | 456315.77 (12.05x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded `Duration`, `Struct`, `Value`,
`FieldMask`, `Timestamp`, `Empty`, `Int64Value`, `DoubleValue`, non-finite `DoubleValue` (`NaN`), `FloatValue`, `UInt64Value`, `Int32Value`, `UInt32Value`, `BoolValue`, `StringValue`, `BytesValue`, and recursive nested `Any` payloads), direct WKT JSON, TextFormat, packed scalars, large bytes,
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
