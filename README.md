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

Latest accepted comparison (`/tmp/pbz-compare-after-any-stringvalue-json-isolated.log`,
summarized in `/tmp/pbz-summary-after-any-stringvalue-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 17.46 | 96.91 (5.55x) | 49.55 (2.84x) | 91.29 (5.23x) | 866.20 (49.61x) |
| binary decode | 100.11 | 243.85 (2.44x) | 232.21 (2.32x) | 209.82 (2.10x) | 906.18 (9.05x) |
| unknown count by number | 3.57 | — | — | 151.35 (42.39x) | — |
| scalarmix encode | 19.30 | 94.90 (4.92x) | 47.95 (2.48x) | 31.10 (1.61x) | 216.82 (11.23x) |
| scalarmix decode | 39.91 | 133.84 (3.35x) | 180.86 (4.53x) | 83.16 (2.08x) | 306.04 (7.67x) |
| textbytes encode | 13.53 | 80.16 (5.92x) | 33.59 (2.48x) | 118.72 (8.77x) | 143.03 (10.57x) |
| complex decode | 178.41 | 394.12 (2.21x) | 336.35 (1.89x) | 403.97 (2.26x) | 1360.86 (7.63x) |
| complex JSON parse | 2421.69 | — | — | 11893.30 (4.91x) | 7577.31 (3.13x) |
| Any WKT JSON stringify | 119.81 | — | — | 1875.61 (15.65x) | 983.83 (8.21x) |
| Any WKT JSON parse | 527.55 | — | — | 2975.66 (5.64x) | 1526.17 (2.89x) |
| Any Struct WKT JSON stringify | 670.82 | — | — | 5885.34 (8.77x) | 6141.69 (9.16x) |
| Any Struct WKT JSON parse | 1750.19 | — | — | 11236.40 (6.42x) | 8693.98 (4.97x) |
| Any Value WKT JSON stringify | 657.73 | — | — | 6065.04 (9.22x) | 6461.49 (9.82x) |
| Any Value WKT JSON parse | 1785.15 | — | — | 11422.80 (6.40x) | 9124.70 (5.11x) |
| Any StringValue WKT JSON stringify | 160.99 | — | — | 1563.08 (9.71x) | 806.26 (5.01x) |
| Any StringValue WKT JSON parse | 553.35 | — | — | 2658.39 (4.80x) | 1449.39 (2.62x) |
| Duration JSON stringify | 57.78 | — | — | 953.20 (16.50x) | 367.88 (6.37x) |
| Duration JSON parse | 8.02 | — | — | 1442.14 (179.82x) | 408.87 (50.98x) |
| FieldMask JSON stringify | 79.39 | — | — | 886.58 (11.17x) | 662.30 (8.34x) |
| FieldMask JSON parse | 146.78 | — | — | 1652.90 (11.26x) | 891.47 (6.07x) |
| Timestamp JSON stringify | 95.18 | — | — | 1135.81 (11.93x) | 416.77 (4.38x) |
| Timestamp JSON parse | 41.50 | — | — | 1485.94 (35.81x) | 447.87 (10.79x) |
| Empty JSON stringify | 20.85 | — | — | 513.89 (24.65x) | 85.98 (4.12x) |
| Empty JSON parse | 67.77 | — | — | 728.47 (10.75x) | 209.38 (3.09x) |
| Struct JSON stringify | 172.73 | — | — | 5790.86 (33.53x) | 3067.44 (17.76x) |
| Struct JSON parse | 863.86 | — | — | 11035.50 (12.77x) | 4702.32 (5.44x) |
| Value JSON stringify | 176.50 | — | — | 6628.11 (37.55x) | 3215.00 (18.22x) |
| Value JSON parse | 873.10 | — | — | 12231.40 (14.01x) | 4933.05 (5.65x) |
| ListValue JSON stringify | 137.61 | — | — | 4778.41 (34.72x) | 2119.73 (15.40x) |
| ListValue JSON parse | 665.29 | — | — | 8636.92 (12.98x) | 3824.88 (5.75x) |
| DoubleValue JSON stringify | 58.57 | — | — | 867.17 (14.81x) | 188.26 (3.21x) |
| DoubleValue JSON parse | 112.04 | — | — | 1244.46 (11.11x) | 284.46 (2.54x) |
| FloatValue JSON stringify | 69.09 | — | — | 847.22 (12.26x) | 183.38 (2.65x) |
| FloatValue JSON parse | 110.29 | — | — | 1259.34 (11.42x) | 289.08 (2.62x) |
| Int64Value JSON stringify | 39.93 | — | — | 677.01 (16.96x) | 285.59 (7.15x) |
| Int64Value JSON parse | 125.04 | — | — | 1232.25 (9.85x) | 471.86 (3.77x) |
| UInt64Value JSON stringify | 39.95 | — | — | 674.46 (16.88x) | 282.95 (7.08x) |
| UInt64Value JSON parse | 125.80 | — | — | 1224.63 (9.73x) | 469.09 (3.73x) |
| Int32Value JSON stringify | 43.21 | — | — | 629.18 (14.56x) | 138.23 (3.20x) |
| Int32Value JSON parse | 129.70 | — | — | 1197.58 (9.23x) | 315.54 (2.43x) |
| UInt32Value JSON stringify | 43.08 | — | — | 640.98 (14.88x) | 135.27 (3.14x) |
| UInt32Value JSON parse | 129.31 | — | — | 1195.84 (9.25x) | 309.27 (2.39x) |
| BoolValue JSON stringify | 41.12 | — | — | 629.02 (15.30x) | 195.92 (4.76x) |
| BoolValue JSON parse | 59.65 | — | — | 1055.90 (17.70x) | 221.82 (3.72x) |
| StringValue JSON stringify | 47.63 | — | — | 678.77 (14.25x) | 190.26 (3.99x) |
| StringValue JSON parse | 136.65 | — | — | 1156.05 (8.46x) | 318.85 (2.33x) |
| BytesValue JSON stringify | 48.65 | — | — | 665.45 (13.68x) | 210.00 (4.32x) |
| BytesValue JSON parse | 146.95 | — | — | 1175.36 (8.00x) | 363.25 (2.47x) |
| TextFormat parse | 685.15 | — | — | 4992.74 (7.29x) | 6623.48 (9.67x) |
| packed int32 decode | 763.65 | 1932.77 (2.53x) | 3210.66 (4.20x) | 946.71 (1.24x) | 2576.01 (3.37x) |
| packed bool encode | 2.01 | 1327.20 (660.30x) | 518.42 (257.92x) | 15.71 (7.81x) | 2406.80 (1197.41x) |
| packed bool decode | 264.51 | 1537.68 (5.81x) | 2552.00 (9.65x) | 821.18 (3.10x) | 1572.16 (5.94x) |
| largebytes decode | 88.82 | 5604.23 (63.10x) | 3041.92 (34.25x) | 2805.59 (31.59x) | 20146.81 (226.83x) |
| large map decode | 25482.30 | 91501.94 (3.59x) | 89704.72 (3.52x) | 88316.10 (3.47x) | 264149.86 (10.37x) |
| shuffled large map deterministic binary encode | 27796.02 | — | — | 88338.80 (3.18x) | 442818.82 (15.93x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded `Duration`, `Struct`, `Value`, and
`StringValue` payloads), direct WKT JSON, TextFormat, packed scalars, large bytes,
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
