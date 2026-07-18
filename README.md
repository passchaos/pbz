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

Latest accepted comparison (`/tmp/pbz-compare-after-any-empty-json-isolated-rerun2.log`,
summarized in `/tmp/pbz-summary-after-any-empty-json-isolated-rerun2.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 27.00 | 124.95 (4.63x) | 63.91 (2.37x) | 131.46 (4.87x) | 944.49 (34.98x) |
| binary decode | 128.51 | 294.35 (2.29x) | 302.70 (2.36x) | 266.81 (2.08x) | 992.43 (7.72x) |
| unknown count by number | 5.03 | — | — | 175.21 (34.83x) | — |
| scalarmix encode | 26.11 | 113.72 (4.36x) | 68.27 (2.61x) | 45.23 (1.73x) | 237.89 (9.11x) |
| scalarmix decode | 56.14 | 163.46 (2.91x) | 221.24 (3.94x) | 108.36 (1.93x) | 359.85 (6.41x) |
| textbytes encode | 13.56 | 91.56 (6.75x) | 43.12 (3.18x) | 149.02 (10.99x) | 170.60 (12.58x) |
| complex decode | 212.77 | 462.70 (2.17x) | 432.43 (2.03x) | 482.11 (2.27x) | 1650.46 (7.76x) |
| complex JSON parse | 2827.46 | — | — | 16661.60 (5.89x) | 10549.25 (3.73x) |
| Any WKT JSON stringify | 174.56 | — | — | 3053.14 (17.49x) | 1326.82 (7.60x) |
| Any WKT JSON parse | 563.47 | — | — | 4644.69 (8.24x) | 2095.20 (3.72x) |
| Any FieldMask WKT JSON stringify | 277.84 | — | — | 2428.39 (8.74x) | 1742.59 (6.27x) |
| Any FieldMask WKT JSON parse | 775.56 | — | — | 4866.18 (6.27x) | 2933.65 (3.78x) |
| Any Timestamp WKT JSON stringify | 245.61 | — | — | 2963.52 (12.07x) | 1338.27 (5.45x) |
| Any Timestamp WKT JSON parse | 627.50 | — | — | 4638.35 (7.39x) | 2230.46 (3.55x) |
| Any Empty WKT JSON stringify | 120.99 | — | — | 1299.47 (10.74x) | 695.61 (5.75x) |
| Any Empty WKT JSON parse | 365.88 | — | — | 3139.84 (8.58x) | 1688.35 (4.61x) |
| Any Struct WKT JSON stringify | 793.77 | — | — | 8982.76 (11.32x) | 8863.21 (11.17x) |
| Any Struct WKT JSON parse | 1950.77 | — | — | 17037.90 (8.73x) | 12660.58 (6.49x) |
| Any Value WKT JSON stringify | 834.48 | — | — | 9163.48 (10.98x) | 9263.22 (11.10x) |
| Any Value WKT JSON parse | 1999.36 | — | — | 17171.50 (8.59x) | 13115.73 (6.56x) |
| Any StringValue WKT JSON stringify | 244.71 | — | — | 2232.72 (9.12x) | 876.70 (3.58x) |
| Any StringValue WKT JSON parse | 592.09 | — | — | 4093.06 (6.91x) | 1963.20 (3.32x) |
| Any BytesValue WKT JSON stringify | 221.33 | — | — | 2260.53 (10.21x) | 915.76 (4.14x) |
| Any BytesValue WKT JSON parse | 602.45 | — | — | 4142.57 (6.88x) | 2025.82 (3.36x) |
| Nested Any WKT JSON stringify | 379.33 | — | — | 3445.15 (9.08x) | 1568.69 (4.14x) |
| Nested Any WKT JSON parse | 967.27 | — | — | 6051.76 (6.26x) | 3643.05 (3.77x) |
| Duration JSON stringify | 63.72 | — | — | 1553.77 (24.38x) | 364.05 (5.71x) |
| Duration JSON parse | 11.53 | — | — | 2279.04 (197.66x) | 431.82 (37.45x) |
| FieldMask JSON stringify | 91.14 | — | — | 1315.55 (14.43x) | 725.99 (7.97x) |
| FieldMask JSON parse | 177.19 | — | — | 2664.60 (15.04x) | 1043.28 (5.89x) |
| Timestamp JSON stringify | 126.13 | — | — | 1720.72 (13.64x) | 464.85 (3.69x) |
| Timestamp JSON parse | 57.42 | — | — | 2301.60 (40.08x) | 476.16 (8.29x) |
| Empty JSON stringify | 22.78 | — | — | 697.90 (30.64x) | 109.44 (4.80x) |
| Empty JSON parse | 75.20 | — | — | 1097.49 (14.59x) | 254.11 (3.38x) |
| Struct JSON stringify | 273.41 | — | — | 8877.49 (32.47x) | 4157.38 (15.21x) |
| Struct JSON parse | 928.20 | — | — | 16777.50 (18.08x) | 6347.71 (6.84x) |
| Value JSON stringify | 276.09 | — | — | 9966.96 (36.10x) | 4342.82 (15.73x) |
| Value JSON parse | 972.14 | — | — | 17872.40 (18.38x) | 6609.80 (6.80x) |
| ListValue JSON stringify | 200.05 | — | — | 7588.26 (37.93x) | 2818.90 (14.09x) |
| ListValue JSON parse | 729.25 | — | — | 13610.50 (18.66x) | 5231.93 (7.17x) |
| DoubleValue JSON stringify | 75.58 | — | — | 1459.90 (19.32x) | 206.84 (2.74x) |
| DoubleValue JSON parse | 114.46 | — | — | 2125.54 (18.57x) | 348.33 (3.04x) |
| FloatValue JSON stringify | 98.17 | — | — | 1406.28 (14.32x) | 189.27 (1.93x) |
| FloatValue JSON parse | 112.22 | — | — | 2121.23 (18.90x) | 324.32 (2.89x) |
| Int64Value JSON stringify | 41.66 | — | — | 997.42 (23.94x) | 294.99 (7.08x) |
| Int64Value JSON parse | 138.44 | — | — | 2006.22 (14.49x) | 496.81 (3.59x) |
| UInt64Value JSON stringify | 41.69 | — | — | 1007.04 (24.16x) | 285.75 (6.85x) |
| UInt64Value JSON parse | 136.56 | — | — | 1962.16 (14.37x) | 509.62 (3.73x) |
| Int32Value JSON stringify | 45.76 | — | — | 969.93 (21.20x) | 150.41 (3.29x) |
| Int32Value JSON parse | 135.10 | — | — | 1912.21 (14.15x) | 331.36 (2.45x) |
| UInt32Value JSON stringify | 45.97 | — | — | 915.38 (19.91x) | 143.11 (3.11x) |
| UInt32Value JSON parse | 134.95 | — | — | 1956.68 (14.50x) | 339.70 (2.52x) |
| BoolValue JSON stringify | 42.25 | — | — | 892.14 (21.12x) | 128.32 (3.04x) |
| BoolValue JSON parse | 59.23 | — | — | 1720.61 (29.05x) | 266.31 (4.50x) |
| StringValue JSON stringify | 53.94 | — | — | 1007.89 (18.69x) | 188.44 (3.49x) |
| StringValue JSON parse | 131.60 | — | — | 1781.71 (13.54x) | 372.82 (2.83x) |
| BytesValue JSON stringify | 47.13 | — | — | 973.90 (20.66x) | 227.74 (4.83x) |
| BytesValue JSON parse | 142.08 | — | — | 1963.73 (13.82x) | 385.09 (2.71x) |
| TextFormat parse | 838.22 | — | — | 5509.92 (6.57x) | 8026.17 (9.58x) |
| packed int32 decode | 994.57 | 2981.64 (3.00x) | 4242.20 (4.27x) | 1341.83 (1.35x) | 4355.13 (4.38x) |
| packed bool encode | 2.51 | 2079.19 (828.36x) | 539.21 (214.82x) | 23.30 (9.28x) | 4379.69 (1744.90x) |
| packed bool decode | 272.35 | 2264.72 (8.32x) | 3848.26 (14.13x) | 1108.16 (4.07x) | 2703.98 (9.93x) |
| largebytes decode | 125.95 | 8456.97 (67.15x) | 4556.77 (36.18x) | 4153.73 (32.98x) | 23702.94 (188.19x) |
| large map decode | 37700.44 | 128246.73 (3.40x) | 129583.73 (3.44x) | 126340.00 (3.35x) | 296650.56 (7.87x) |
| shuffled large map deterministic binary encode | 36541.05 | — | — | 118849.00 (3.25x) | 459473.39 (12.57x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded `Duration`, `Struct`, `Value`,
`FieldMask`, `Timestamp`, `Empty`, `StringValue`, `BytesValue`, and recursive nested `Any` payloads), direct WKT JSON, TextFormat, packed scalars, large bytes,
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
