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

Latest accepted comparison (`/tmp/pbz-compare-after-any-int64-json-isolated.log`,
summarized in `/tmp/pbz-summary-after-any-int64-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 24.70 | 128.70 (5.21x) | 62.37 (2.53x) | 129.19 (5.23x) | 952.38 (38.56x) |
| binary decode | 136.64 | 299.99 (2.20x) | 298.99 (2.19x) | 270.32 (1.98x) | 994.40 (7.28x) |
| unknown count by number | 5.02 | — | — | 213.57 (42.54x) | — |
| scalarmix encode | 27.19 | 114.19 (4.20x) | 69.44 (2.55x) | 45.77 (1.68x) | 239.49 (8.81x) |
| scalarmix decode | 50.28 | 161.48 (3.21x) | 220.81 (4.39x) | 112.32 (2.23x) | 359.37 (7.15x) |
| textbytes encode | 13.53 | 91.43 (6.76x) | 43.29 (3.20x) | 146.57 (10.83x) | 172.04 (12.72x) |
| complex decode | 227.54 | 460.81 (2.03x) | 436.52 (1.92x) | 488.95 (2.15x) | 1627.87 (7.15x) |
| complex JSON parse | 2741.53 | — | — | 16990.90 (6.20x) | 10547.32 (3.85x) |
| Any WKT JSON stringify | 169.15 | — | — | 3059.48 (18.09x) | 1357.37 (8.02x) |
| Any WKT JSON parse | 560.58 | — | — | 4610.97 (8.23x) | 2054.13 (3.66x) |
| Any FieldMask WKT JSON stringify | 278.64 | — | — | 2449.48 (8.79x) | 1728.43 (6.20x) |
| Any FieldMask WKT JSON parse | 785.63 | — | — | 4859.91 (6.19x) | 2853.62 (3.63x) |
| Any Timestamp WKT JSON stringify | 236.99 | — | — | 3013.12 (12.71x) | 1357.45 (5.73x) |
| Any Timestamp WKT JSON parse | 631.29 | — | — | 4683.93 (7.42x) | 2203.95 (3.49x) |
| Any Empty WKT JSON stringify | 114.03 | — | — | 1304.95 (11.44x) | 658.99 (5.78x) |
| Any Empty WKT JSON parse | 371.64 | — | — | 3151.69 (8.48x) | 1637.00 (4.40x) |
| Any Struct WKT JSON stringify | 773.20 | — | — | 8991.14 (11.63x) | 8869.54 (11.47x) |
| Any Struct WKT JSON parse | 1948.41 | — | — | 16743.10 (8.59x) | 12453.49 (6.39x) |
| Any Value WKT JSON stringify | 790.33 | — | — | 9009.85 (11.40x) | 9402.84 (11.90x) |
| Any Value WKT JSON parse | 2011.91 | — | — | 16789.90 (8.35x) | 12907.23 (6.42x) |
| Any Int64Value WKT JSON stringify | 205.64 | — | — | 2222.47 (10.81x) | 1091.72 (5.31x) |
| Any Int64Value WKT JSON parse | 617.10 | — | — | 4287.25 (6.95x) | 2290.57 (3.71x) |
| Any StringValue WKT JSON stringify | 234.71 | — | — | 2247.18 (9.57x) | 875.23 (3.73x) |
| Any StringValue WKT JSON parse | 604.57 | — | — | 4104.13 (6.79x) | 1899.07 (3.14x) |
| Any BytesValue WKT JSON stringify | 223.33 | — | — | 2345.44 (10.50x) | 925.65 (4.14x) |
| Any BytesValue WKT JSON parse | 612.42 | — | — | 4204.75 (6.87x) | 1964.07 (3.21x) |
| Nested Any WKT JSON stringify | 358.99 | — | — | 3421.30 (9.53x) | 1570.44 (4.37x) |
| Nested Any WKT JSON parse | 989.50 | — | — | 6162.15 (6.23x) | 3580.22 (3.62x) |
| Duration JSON stringify | 63.32 | — | — | 1547.96 (24.45x) | 368.10 (5.81x) |
| Duration JSON parse | 11.29 | — | — | 2272.31 (201.27x) | 426.08 (37.74x) |
| FieldMask JSON stringify | 92.27 | — | — | 1312.14 (14.22x) | 741.14 (8.03x) |
| FieldMask JSON parse | 182.46 | — | — | 2643.96 (14.49x) | 1029.69 (5.64x) |
| Timestamp JSON stringify | 126.08 | — | — | 1696.42 (13.46x) | 462.59 (3.67x) |
| Timestamp JSON parse | 57.30 | — | — | 2252.20 (39.31x) | 476.41 (8.31x) |
| Empty JSON stringify | 22.51 | — | — | 702.06 (31.19x) | 102.76 (4.57x) |
| Empty JSON parse | 75.45 | — | — | 1094.68 (14.51x) | 242.76 (3.22x) |
| Struct JSON stringify | 259.29 | — | — | 8852.37 (34.14x) | 4178.26 (16.11x) |
| Struct JSON parse | 943.35 | — | — | 16841.70 (17.85x) | 6276.80 (6.65x) |
| Value JSON stringify | 264.21 | — | — | 9814.53 (37.15x) | 4323.38 (16.36x) |
| Value JSON parse | 967.71 | — | — | 17959.60 (18.56x) | 6616.22 (6.84x) |
| ListValue JSON stringify | 195.42 | — | — | 9547.02 (48.85x) | 2784.08 (14.25x) |
| ListValue JSON parse | 733.81 | — | — | 14048.50 (19.14x) | 5166.09 (7.04x) |
| DoubleValue JSON stringify | 75.55 | — | — | 1516.59 (20.07x) | 203.84 (2.70x) |
| DoubleValue JSON parse | 113.61 | — | — | 2139.21 (18.83x) | 314.74 (2.77x) |
| FloatValue JSON stringify | 99.25 | — | — | 1437.71 (14.49x) | 202.53 (2.04x) |
| FloatValue JSON parse | 112.98 | — | — | 2136.92 (18.91x) | 304.59 (2.70x) |
| Int64Value JSON stringify | 44.87 | — | — | 1027.73 (22.90x) | 295.28 (6.58x) |
| Int64Value JSON parse | 138.35 | — | — | 1972.58 (14.26x) | 511.56 (3.70x) |
| UInt64Value JSON stringify | 45.11 | — | — | 1022.25 (22.66x) | 295.49 (6.55x) |
| UInt64Value JSON parse | 137.43 | — | — | 1964.50 (14.29x) | 497.63 (3.62x) |
| Int32Value JSON stringify | 45.86 | — | — | 962.67 (20.99x) | 149.09 (3.25x) |
| Int32Value JSON parse | 134.95 | — | — | 1896.16 (14.05x) | 346.19 (2.57x) |
| UInt32Value JSON stringify | 45.69 | — | — | 919.70 (20.13x) | 154.63 (3.38x) |
| UInt32Value JSON parse | 134.75 | — | — | 1919.91 (14.25x) | 348.75 (2.59x) |
| BoolValue JSON stringify | 42.72 | — | — | 923.38 (21.61x) | 142.19 (3.33x) |
| BoolValue JSON parse | 59.23 | — | — | 1714.84 (28.95x) | 266.33 (4.50x) |
| StringValue JSON stringify | 54.11 | — | — | 1039.02 (19.20x) | 187.22 (3.46x) |
| StringValue JSON parse | 130.81 | — | — | 1854.63 (14.18x) | 369.36 (2.82x) |
| BytesValue JSON stringify | 47.14 | — | — | 1027.03 (21.79x) | 220.82 (4.68x) |
| BytesValue JSON parse | 141.69 | — | — | 2035.33 (14.36x) | 370.57 (2.62x) |
| TextFormat parse | 850.77 | — | — | 5842.32 (6.87x) | 8017.09 (9.42x) |
| packed int32 decode | 1029.80 | 2989.84 (2.90x) | 4271.61 (4.15x) | 1891.08 (1.84x) | 4350.89 (4.22x) |
| packed bool encode | 2.38 | 2081.80 (874.71x) | 540.83 (227.24x) | 22.97 (9.65x) | 4383.36 (1841.75x) |
| packed bool decode | 272.80 | 2422.09 (8.88x) | 3842.38 (14.08x) | 1108.62 (4.06x) | 2707.77 (9.93x) |
| largebytes decode | 124.92 | 8449.62 (67.64x) | 4544.28 (36.38x) | 4062.56 (32.52x) | 24060.82 (192.61x) |
| large map decode | 37446.33 | 129017.43 (3.45x) | 128058.46 (3.42x) | 119513.00 (3.19x) | 297677.30 (7.95x) |
| shuffled large map deterministic binary encode | 36967.00 | — | — | 113798.00 (3.08x) | 450141.18 (12.18x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded `Duration`, `Struct`, `Value`,
`FieldMask`, `Timestamp`, `Empty`, `Int64Value`, `StringValue`, `BytesValue`, and recursive nested `Any` payloads), direct WKT JSON, TextFormat, packed scalars, large bytes,
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
