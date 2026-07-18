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

Latest accepted comparison (`/tmp/pbz-compare-after-any-uint64-json-isolated.log`,
summarized in `/tmp/pbz-summary-after-any-uint64-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 22.81 | 125.63 (5.51x) | 65.30 (2.86x) | 128.14 (5.62x) | 970.48 (42.55x) |
| binary decode | 129.38 | 302.33 (2.34x) | 307.96 (2.38x) | 266.70 (2.06x) | 1009.80 (7.80x) |
| unknown count by number | 5.02 | — | — | 178.34 (35.53x) | — |
| scalarmix encode | 26.81 | 113.76 (4.24x) | 67.02 (2.50x) | 45.66 (1.70x) | 251.33 (9.37x) |
| scalarmix decode | 50.47 | 165.89 (3.29x) | 212.32 (4.21x) | 112.39 (2.23x) | 372.87 (7.39x) |
| textbytes encode | 13.28 | 91.33 (6.88x) | 43.36 (3.27x) | 146.73 (11.05x) | 174.42 (13.13x) |
| complex decode | 223.45 | 462.76 (2.07x) | 429.51 (1.92x) | 488.86 (2.19x) | 1624.01 (7.27x) |
| complex JSON parse | 2703.06 | — | — | 16878.80 (6.24x) | 10631.21 (3.93x) |
| Any WKT JSON stringify | 177.91 | — | — | 3091.18 (17.37x) | 1368.46 (7.69x) |
| Any WKT JSON parse | 574.46 | — | — | 4566.02 (7.95x) | 2097.69 (3.65x) |
| Any FieldMask WKT JSON stringify | 287.13 | — | — | 2570.82 (8.95x) | 1743.42 (6.07x) |
| Any FieldMask WKT JSON parse | 795.61 | — | — | 4934.07 (6.20x) | 2933.28 (3.69x) |
| Any Timestamp WKT JSON stringify | 245.69 | — | — | 3015.02 (12.27x) | 1324.59 (5.39x) |
| Any Timestamp WKT JSON parse | 640.20 | — | — | 4693.40 (7.33x) | 2256.62 (3.52x) |
| Any Empty WKT JSON stringify | 126.00 | — | — | 1302.19 (10.33x) | 643.78 (5.11x) |
| Any Empty WKT JSON parse | 376.02 | — | — | 3137.18 (8.34x) | 1666.53 (4.43x) |
| Any Struct WKT JSON stringify | 783.70 | — | — | 9074.79 (11.58x) | 8906.79 (11.37x) |
| Any Struct WKT JSON parse | 1964.95 | — | — | 16814.20 (8.56x) | 12832.80 (6.53x) |
| Any Value WKT JSON stringify | 803.59 | — | — | 9286.62 (11.56x) | 9411.98 (11.71x) |
| Any Value WKT JSON parse | 2041.46 | — | — | 17111.60 (8.38x) | 13378.01 (6.55x) |
| Any Int64Value WKT JSON stringify | 205.66 | — | — | 2336.27 (11.36x) | 1159.88 (5.64x) |
| Any Int64Value WKT JSON parse | 623.06 | — | — | 4311.74 (6.92x) | 2442.13 (3.92x) |
| Any UInt64Value WKT JSON stringify | 214.46 | — | — | 2192.31 (10.22x) | 1117.49 (5.21x) |
| Any UInt64Value WKT JSON parse | 625.84 | — | — | 4377.33 (6.99x) | 2251.53 (3.60x) |
| Any StringValue WKT JSON stringify | 246.59 | — | — | 2356.89 (9.56x) | 935.51 (3.79x) |
| Any StringValue WKT JSON parse | 608.98 | — | — | 4192.92 (6.89x) | 1943.06 (3.19x) |
| Any BytesValue WKT JSON stringify | 224.82 | — | — | 2395.57 (10.66x) | 914.21 (4.07x) |
| Any BytesValue WKT JSON parse | 617.73 | — | — | 4430.60 (7.17x) | 2021.44 (3.27x) |
| Nested Any WKT JSON stringify | 386.13 | — | — | 3602.49 (9.33x) | 1610.72 (4.17x) |
| Nested Any WKT JSON parse | 1001.36 | — | — | 6349.34 (6.34x) | 3794.02 (3.79x) |
| Duration JSON stringify | 63.27 | — | — | 1596.08 (25.23x) | 419.75 (6.63x) |
| Duration JSON parse | 11.55 | — | — | 2381.15 (206.16x) | 439.69 (38.07x) |
| FieldMask JSON stringify | 92.88 | — | — | 1410.63 (15.19x) | 768.63 (8.28x) |
| FieldMask JSON parse | 181.15 | — | — | 2745.04 (15.15x) | 1088.82 (6.01x) |
| Timestamp JSON stringify | 127.64 | — | — | 1767.43 (13.85x) | 496.12 (3.89x) |
| Timestamp JSON parse | 57.04 | — | — | 2406.21 (42.18x) | 502.07 (8.80x) |
| Empty JSON stringify | 23.62 | — | — | 749.12 (31.72x) | 111.77 (4.73x) |
| Empty JSON parse | 73.01 | — | — | 1166.60 (15.98x) | 276.51 (3.79x) |
| Struct JSON stringify | 272.34 | — | — | 9313.91 (34.20x) | 4434.58 (16.28x) |
| Struct JSON parse | 936.55 | — | — | 17398.50 (18.58x) | 6545.40 (6.99x) |
| Value JSON stringify | 276.11 | — | — | 10428.70 (37.77x) | 4320.28 (15.65x) |
| Value JSON parse | 942.82 | — | — | 18416.40 (19.53x) | 6734.49 (7.14x) |
| ListValue JSON stringify | 200.48 | — | — | 7621.07 (38.01x) | 2943.93 (14.68x) |
| ListValue JSON parse | 736.60 | — | — | 14160.20 (19.22x) | 5370.79 (7.29x) |
| DoubleValue JSON stringify | 75.83 | — | — | 1545.97 (20.39x) | 215.88 (2.85x) |
| DoubleValue JSON parse | 112.79 | — | — | 2167.16 (19.21x) | 344.79 (3.06x) |
| FloatValue JSON stringify | 100.62 | — | — | 1450.57 (14.42x) | 212.08 (2.11x) |
| FloatValue JSON parse | 113.30 | — | — | 2191.90 (19.35x) | 339.87 (3.00x) |
| Int64Value JSON stringify | 44.75 | — | — | 1050.59 (23.48x) | 314.37 (7.03x) |
| Int64Value JSON parse | 136.82 | — | — | 2051.19 (14.99x) | 532.84 (3.89x) |
| UInt64Value JSON stringify | 43.60 | — | — | 1019.14 (23.37x) | 297.60 (6.83x) |
| UInt64Value JSON parse | 137.15 | — | — | 1955.27 (14.26x) | 510.20 (3.72x) |
| Int32Value JSON stringify | 47.06 | — | — | 983.35 (20.90x) | 144.94 (3.08x) |
| Int32Value JSON parse | 129.09 | — | — | 1923.05 (14.90x) | 336.01 (2.60x) |
| UInt32Value JSON stringify | 46.60 | — | — | 938.74 (20.14x) | 141.69 (3.04x) |
| UInt32Value JSON parse | 129.01 | — | — | 1897.68 (14.71x) | 368.51 (2.86x) |
| BoolValue JSON stringify | 42.48 | — | — | 908.25 (21.38x) | 136.50 (3.21x) |
| BoolValue JSON parse | 59.00 | — | — | 1738.64 (29.47x) | 261.71 (4.44x) |
| StringValue JSON stringify | 54.24 | — | — | 1024.24 (18.88x) | 203.38 (3.75x) |
| StringValue JSON parse | 129.76 | — | — | 1840.01 (14.18x) | 363.41 (2.80x) |
| BytesValue JSON stringify | 47.70 | — | — | 982.43 (20.60x) | 223.82 (4.69x) |
| BytesValue JSON parse | 143.00 | — | — | 1980.52 (13.85x) | 388.32 (2.72x) |
| TextFormat parse | 833.29 | — | — | 5515.73 (6.62x) | 8099.63 (9.72x) |
| packed int32 decode | 1029.90 | 2973.94 (2.89x) | 4240.31 (4.12x) | 1342.62 (1.30x) | 4350.14 (4.22x) |
| packed bool encode | 2.45 | 2080.65 (849.24x) | 539.53 (220.22x) | 23.65 (9.65x) | 4386.31 (1790.33x) |
| packed bool decode | 271.62 | 2344.70 (8.63x) | 3851.30 (14.18x) | 1112.35 (4.10x) | 2656.81 (9.78x) |
| largebytes decode | 126.03 | 8758.74 (69.50x) | 4569.28 (36.26x) | 3976.46 (31.55x) | 24576.72 (195.01x) |
| large map decode | 37414.71 | 128898.76 (3.45x) | 129136.54 (3.45x) | 120549.00 (3.22x) | 303625.79 (8.12x) |
| shuffled large map deterministic binary encode | 36189.80 | — | — | 114443.00 (3.16x) | 460239.92 (12.72x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded `Duration`, `Struct`, `Value`,
`FieldMask`, `Timestamp`, `Empty`, `Int64Value`, `UInt64Value`, `StringValue`, `BytesValue`, and recursive nested `Any` payloads), direct WKT JSON, TextFormat, packed scalars, large bytes,
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
