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

Latest accepted comparison (`/tmp/pbz-compare-after-any-fieldmask-json-isolated-rerun.log`,
summarized in `/tmp/pbz-summary-after-any-fieldmask-json-isolated-rerun.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 22.29 | 147.87 (6.63x) | 53.28 (2.39x) | 162.24 (7.28x) | 872.25 (39.13x) |
| binary decode | 97.92 | 457.96 (4.68x) | 230.95 (2.36x) | 484.07 (4.94x) | 910.67 (9.30x) |
| unknown count by number | 3.57 | — | — | 271.22 (75.97x) | — |
| scalarmix encode | 20.25 | 152.46 (7.53x) | 49.96 (2.47x) | 59.75 (2.95x) | 213.50 (10.54x) |
| scalarmix decode | 38.57 | 227.24 (5.89x) | 182.02 (4.72x) | 127.90 (3.32x) | 562.27 (14.58x) |
| textbytes encode | 11.53 | 107.26 (9.30x) | 33.38 (2.90x) | 162.01 (14.05x) | 227.43 (19.73x) |
| complex decode | 168.43 | 400.54 (2.38x) | 340.10 (2.02x) | 403.12 (2.39x) | 1349.62 (8.01x) |
| complex JSON parse | 2416.11 | — | — | 11880.20 (4.92x) | 7571.76 (3.13x) |
| Any WKT JSON stringify | 121.74 | — | — | 1889.99 (15.52x) | 988.46 (8.12x) |
| Any WKT JSON parse | 521.82 | — | — | 2990.02 (5.73x) | 1560.25 (2.99x) |
| Any FieldMask WKT JSON stringify | 217.78 | — | — | 1747.64 (8.02x) | 1424.66 (6.54x) |
| Any FieldMask WKT JSON parse | 707.81 | — | — | 3161.57 (4.47x) | 2085.02 (2.95x) |
| Any Struct WKT JSON stringify | 603.32 | — | — | 5866.65 (9.72x) | 6031.01 (10.00x) |
| Any Struct WKT JSON parse | 1738.73 | — | — | 11195.20 (6.44x) | 8907.30 (5.12x) |
| Any Value WKT JSON stringify | 627.10 | — | — | 5943.62 (9.48x) | 6501.15 (10.37x) |
| Any Value WKT JSON parse | 1805.70 | — | — | 11780.20 (6.52x) | 9226.43 (5.11x) |
| Any StringValue WKT JSON stringify | 158.50 | — | — | 1552.70 (9.80x) | 826.49 (5.21x) |
| Any StringValue WKT JSON parse | 553.30 | — | — | 2714.67 (4.91x) | 1501.41 (2.71x) |
| Any BytesValue WKT JSON stringify | 142.63 | — | — | 1588.39 (11.14x) | 859.34 (6.02x) |
| Any BytesValue WKT JSON parse | 561.67 | — | — | 2729.05 (4.86x) | 1522.76 (2.71x) |
| Nested Any WKT JSON stringify | 258.03 | — | — | 2471.27 (9.58x) | 1491.40 (5.78x) |
| Nested Any WKT JSON parse | 877.35 | — | — | 4270.20 (4.87x) | 2970.01 (3.39x) |
| Duration JSON stringify | 57.94 | — | — | 956.47 (16.51x) | 361.86 (6.25x) |
| Duration JSON parse | 8.28 | — | — | 1458.09 (176.10x) | 467.33 (56.44x) |
| FieldMask JSON stringify | 70.62 | — | — | 898.18 (12.72x) | 646.33 (9.15x) |
| FieldMask JSON parse | 146.15 | — | — | 1692.24 (11.58x) | 882.96 (6.04x) |
| Timestamp JSON stringify | 95.03 | — | — | 1152.87 (12.13x) | 419.92 (4.42x) |
| Timestamp JSON parse | 41.53 | — | — | 1506.07 (36.26x) | 448.81 (10.81x) |
| Empty JSON stringify | 21.21 | — | — | 509.31 (24.01x) | 86.48 (4.08x) |
| Empty JSON parse | 67.36 | — | — | 729.96 (10.84x) | 220.59 (3.27x) |
| Struct JSON stringify | 175.76 | — | — | 5799.92 (33.00x) | 3053.88 (17.38x) |
| Struct JSON parse | 849.97 | — | — | 11303.60 (13.30x) | 5128.94 (6.03x) |
| Value JSON stringify | 174.86 | — | — | 6555.17 (37.49x) | 3234.09 (18.50x) |
| Value JSON parse | 866.98 | — | — | 12181.20 (14.05x) | 5019.60 (5.79x) |
| ListValue JSON stringify | 136.57 | — | — | 4743.63 (34.73x) | 2132.01 (15.61x) |
| ListValue JSON parse | 657.51 | — | — | 8552.74 (13.01x) | 3798.80 (5.78x) |
| DoubleValue JSON stringify | 61.00 | — | — | 899.13 (14.74x) | 184.86 (3.03x) |
| DoubleValue JSON parse | 110.13 | — | — | 1270.82 (11.54x) | 287.84 (2.61x) |
| FloatValue JSON stringify | 70.74 | — | — | 847.54 (11.98x) | 181.92 (2.57x) |
| FloatValue JSON parse | 110.47 | — | — | 1270.35 (11.50x) | 294.18 (2.66x) |
| Int64Value JSON stringify | 40.19 | — | — | 677.96 (16.87x) | 284.72 (7.08x) |
| Int64Value JSON parse | 126.15 | — | — | 1223.69 (9.70x) | 473.22 (3.75x) |
| UInt64Value JSON stringify | 40.32 | — | — | 679.38 (16.85x) | 284.53 (7.06x) |
| UInt64Value JSON parse | 126.19 | — | — | 1232.74 (9.77x) | 466.88 (3.70x) |
| Int32Value JSON stringify | 43.40 | — | — | 634.46 (14.62x) | 140.97 (3.25x) |
| Int32Value JSON parse | 129.13 | — | — | 1190.20 (9.22x) | 315.56 (2.44x) |
| UInt32Value JSON stringify | 43.16 | — | — | 634.73 (14.71x) | 140.97 (3.27x) |
| UInt32Value JSON parse | 129.41 | — | — | 1196.58 (9.25x) | 317.15 (2.45x) |
| BoolValue JSON stringify | 41.62 | — | — | 614.07 (14.75x) | 123.09 (2.96x) |
| BoolValue JSON parse | 59.40 | — | — | 1054.48 (17.75x) | 257.56 (4.34x) |
| StringValue JSON stringify | 47.18 | — | — | 657.59 (13.94x) | 186.15 (3.95x) |
| StringValue JSON parse | 136.26 | — | — | 1140.19 (8.37x) | 328.34 (2.41x) |
| BytesValue JSON stringify | 67.31 | — | — | 668.85 (9.94x) | 214.65 (3.19x) |
| BytesValue JSON parse | 184.73 | — | — | 1166.98 (6.32x) | 349.14 (1.89x) |
| TextFormat parse | 1162.24 | — | — | 4981.74 (4.29x) | 6603.65 (5.68x) |
| packed int32 decode | 762.77 | 1899.16 (2.49x) | 3257.57 (4.27x) | 941.23 (1.23x) | 2541.41 (3.33x) |
| packed bool encode | 2.01 | 1320.71 (657.07x) | 521.95 (259.68x) | 15.81 (7.86x) | 2222.47 (1105.71x) |
| packed bool decode | 264.34 | 1528.72 (5.78x) | 2563.18 (9.70x) | 816.69 (3.09x) | 1635.85 (6.19x) |
| largebytes decode | 93.35 | 7405.28 (79.33x) | 2994.79 (32.08x) | 2739.86 (29.35x) | 21338.20 (228.58x) |
| large map decode | 26067.77 | 90654.78 (3.48x) | 89513.25 (3.43x) | 88586.00 (3.40x) | 268295.27 (10.29x) |
| shuffled large map deterministic binary encode | 28218.28 | — | — | 87317.90 (3.09x) | 451668.51 (16.01x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded `Duration`, `Struct`, `Value`,
`FieldMask`, `StringValue`, `BytesValue`, and recursive nested `Any` payloads), direct WKT JSON, TextFormat, packed scalars, large bytes,
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
