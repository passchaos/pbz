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

Latest accepted comparison (`/tmp/pbz-compare-after-any-value-json-isolated.log`,
summarized in `/tmp/pbz-summary-after-any-value-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 21.36 | 111.79 (5.23x) | 50.80 (2.38x) | 102.28 (4.79x) | 863.75 (40.44x) |
| binary decode | 87.41 | 260.89 (2.98x) | 235.45 (2.69x) | 215.04 (2.46x) | 904.83 (10.35x) |
| unknown count by number | 3.57 | — | — | 151.87 (42.54x) | — |
| scalarmix encode | 19.80 | 98.03 (4.95x) | 49.53 (2.50x) | 30.13 (1.52x) | 220.89 (11.16x) |
| scalarmix decode | 34.33 | 139.84 (4.07x) | 174.40 (5.08x) | 83.96 (2.45x) | 304.13 (8.86x) |
| textbytes encode | 13.53 | 82.57 (6.10x) | 33.60 (2.48x) | 117.94 (8.72x) | 155.22 (11.47x) |
| complex decode | 169.00 | 396.60 (2.35x) | 342.44 (2.03x) | 389.63 (2.31x) | 1392.39 (8.24x) |
| complex JSON parse | 2384.20 | — | — | 11868.10 (4.98x) | 7580.28 (3.18x) |
| Any WKT JSON stringify | 124.60 | — | — | 1903.67 (15.28x) | 983.32 (7.89x) |
| Any WKT JSON parse | 517.63 | — | — | 3003.98 (5.80x) | 1534.70 (2.96x) |
| Any Struct WKT JSON stringify | 618.85 | — | — | 5985.93 (9.67x) | 6128.98 (9.90x) |
| Any Struct WKT JSON parse | 1733.84 | — | — | 11088.50 (6.40x) | 8679.74 (5.01x) |
| Any Value WKT JSON stringify | 993.97 | — | — | 5974.82 (6.01x) | 6397.85 (6.44x) |
| Any Value WKT JSON parse | 1804.26 | — | — | 11343.30 (6.29x) | 9133.68 (5.06x) |
| Duration JSON stringify | 57.57 | — | — | 961.50 (16.70x) | 364.59 (6.33x) |
| Duration JSON parse | 7.91 | — | — | 1456.31 (184.11x) | 408.13 (51.60x) |
| FieldMask JSON stringify | 101.49 | — | — | 890.92 (8.78x) | 645.07 (6.36x) |
| FieldMask JSON parse | 146.23 | — | — | 1652.74 (11.30x) | 889.71 (6.08x) |
| Timestamp JSON stringify | 99.71 | — | — | 1139.12 (11.42x) | 417.43 (4.19x) |
| Timestamp JSON parse | 41.59 | — | — | 1481.53 (35.62x) | 457.19 (10.99x) |
| Empty JSON stringify | 20.60 | — | — | 521.72 (25.33x) | 87.51 (4.25x) |
| Empty JSON parse | 67.70 | — | — | 739.89 (10.93x) | 211.96 (3.13x) |
| Struct JSON stringify | 186.24 | — | — | 5797.62 (31.13x) | 3061.56 (16.44x) |
| Struct JSON parse | 862.23 | — | — | 10943.90 (12.69x) | 4664.20 (5.41x) |
| Value JSON stringify | 190.00 | — | — | 6631.01 (34.90x) | 3224.24 (16.97x) |
| Value JSON parse | 870.04 | — | — | 12147.10 (13.96x) | 4939.41 (5.68x) |
| ListValue JSON stringify | 142.83 | — | — | 4749.71 (33.25x) | 2122.34 (14.86x) |
| ListValue JSON parse | 667.93 | — | — | 8517.91 (12.75x) | 3820.85 (5.72x) |
| DoubleValue JSON stringify | 59.22 | — | — | 927.39 (15.66x) | 190.26 (3.21x) |
| DoubleValue JSON parse | 111.26 | — | — | 1283.12 (11.53x) | 296.39 (2.66x) |
| FloatValue JSON stringify | 70.71 | — | — | 798.12 (11.29x) | 188.30 (2.66x) |
| FloatValue JSON parse | 109.82 | — | — | 1260.63 (11.48x) | 299.79 (2.73x) |
| Int64Value JSON stringify | 40.45 | — | — | 674.55 (16.68x) | 283.89 (7.02x) |
| Int64Value JSON parse | 125.21 | — | — | 1225.49 (9.79x) | 471.16 (3.76x) |
| UInt64Value JSON stringify | 40.50 | — | — | 673.49 (16.63x) | 284.91 (7.03x) |
| UInt64Value JSON parse | 125.01 | — | — | 1223.98 (9.79x) | 464.02 (3.71x) |
| Int32Value JSON stringify | 43.00 | — | — | 634.57 (14.76x) | 153.58 (3.57x) |
| Int32Value JSON parse | 129.62 | — | — | 1194.48 (9.22x) | 307.23 (2.37x) |
| UInt32Value JSON stringify | 43.09 | — | — | 642.93 (14.92x) | 137.61 (3.19x) |
| UInt32Value JSON parse | 130.18 | — | — | 1185.09 (9.10x) | 318.63 (2.45x) |
| BoolValue JSON stringify | 42.01 | — | — | 617.92 (14.71x) | 130.06 (3.10x) |
| BoolValue JSON parse | 60.39 | — | — | 1064.74 (17.63x) | 218.44 (3.62x) |
| StringValue JSON stringify | 47.12 | — | — | 674.79 (14.32x) | 178.91 (3.80x) |
| StringValue JSON parse | 137.16 | — | — | 1150.94 (8.39x) | 330.64 (2.41x) |
| BytesValue JSON stringify | 48.18 | — | — | 667.47 (13.85x) | 219.56 (4.56x) |
| BytesValue JSON parse | 149.91 | — | — | 1170.94 (7.81x) | 350.52 (2.34x) |
| TextFormat parse | 715.03 | — | — | 4977.56 (6.96x) | 6639.70 (9.29x) |
| packed int32 decode | 700.36 | 1913.47 (2.73x) | 3209.78 (4.58x) | 939.97 (1.34x) | 2518.51 (3.60x) |
| packed bool encode | 2.01 | 1328.83 (661.11x) | 521.53 (259.47x) | 18.29 (9.10x) | 2211.74 (1100.37x) |
| packed bool decode | 266.50 | 1550.18 (5.82x) | 2553.47 (9.58x) | 809.42 (3.04x) | 1573.94 (5.91x) |
| largebytes decode | 93.07 | 5595.84 (60.13x) | 3044.81 (32.72x) | 2750.66 (29.55x) | 20114.21 (216.12x) |
| large map decode | 25595.75 | 90771.03 (3.55x) | 89269.27 (3.49x) | 92920.70 (3.63x) | 265730.51 (10.38x) |
| shuffled large map deterministic binary encode | 28623.34 | — | — | 91494.50 (3.20x) | 437510.70 (15.29x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded `Duration`, `Struct`, and
`Value` payloads), direct WKT JSON, TextFormat, packed scalars, large bytes,
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
