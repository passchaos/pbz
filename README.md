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

Latest accepted comparison (`/tmp/pbz-compare-after-wrapper-json-isolated.log`,
summarized in `/tmp/pbz-summary-after-wrapper-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 18.93 | 105.04 (5.55x) | 52.71 (2.78x) | 108.21 (5.72x) | 878.82 (46.42x) |
| binary decode | 85.09 | 251.26 (2.95x) | 230.55 (2.71x) | 222.48 (2.61x) | 911.91 (10.72x) |
| unknown count by number | 3.57 | — | — | 151.36 (42.40x) | — |
| scalarmix encode | 19.80 | 105.50 (5.33x) | 51.43 (2.60x) | 30.32 (1.53x) | 200.13 (10.11x) |
| scalarmix decode | 35.18 | 133.66 (3.80x) | 172.68 (4.91x) | 85.32 (2.43x) | 308.42 (8.77x) |
| textbytes encode | 11.53 | 76.70 (6.65x) | 33.34 (2.89x) | 117.50 (10.19x) | 145.53 (12.62x) |
| complex decode | 189.44 | 386.05 (2.04x) | 336.50 (1.78x) | 395.25 (2.09x) | 1337.22 (7.06x) |
| complex JSON parse | 2395.51 | — | — | 11913.60 (4.97x) | 7718.21 (3.22x) |
| Any WKT JSON stringify | 123.75 | — | — | 1878.14 (15.18x) | 977.90 (7.90x) |
| Any WKT JSON parse | 520.59 | — | — | 2991.42 (5.75x) | 1505.64 (2.89x) |
| Duration JSON stringify | 57.64 | — | — | 963.06 (16.71x) | 377.56 (6.55x) |
| Duration JSON parse | 7.58 | — | — | 1452.51 (191.62x) | 392.75 (51.81x) |
| FieldMask JSON stringify | 104.67 | — | — | 890.59 (8.51x) | 647.17 (6.18x) |
| FieldMask JSON parse | 156.72 | — | — | 1657.72 (10.58x) | 896.12 (5.72x) |
| Timestamp JSON stringify | 96.48 | — | — | 1144.48 (11.86x) | 420.85 (4.36x) |
| Timestamp JSON parse | 41.61 | — | — | 1489.40 (35.79x) | 451.07 (10.84x) |
| DoubleValue JSON stringify | 59.09 | — | — | 848.58 (14.36x) | 193.43 (3.27x) |
| DoubleValue JSON parse | 111.74 | — | — | 1222.59 (10.94x) | 289.06 (2.59x) |
| FloatValue JSON stringify | 70.65 | — | — | 794.63 (11.25x) | 192.48 (2.72x) |
| FloatValue JSON parse | 111.84 | — | — | 1211.11 (10.83x) | 293.91 (2.63x) |
| Int64Value JSON stringify | 40.58 | — | — | 671.41 (16.55x) | 275.04 (6.78x) |
| Int64Value JSON parse | 128.60 | — | — | 1226.55 (9.54x) | 467.04 (3.63x) |
| UInt64Value JSON stringify | 40.82 | — | — | 673.52 (16.50x) | 280.28 (6.87x) |
| UInt64Value JSON parse | 127.44 | — | — | 1210.58 (9.50x) | 460.76 (3.62x) |
| Int32Value JSON stringify | 43.43 | — | — | 630.20 (14.51x) | 140.90 (3.24x) |
| Int32Value JSON parse | 128.98 | — | — | 1177.13 (9.13x) | 315.48 (2.45x) |
| UInt32Value JSON stringify | 43.28 | — | — | 630.29 (14.56x) | 145.70 (3.37x) |
| UInt32Value JSON parse | 130.16 | — | — | 1185.83 (9.11x) | 320.62 (2.46x) |
| BoolValue JSON stringify | 46.11 | — | — | 610.17 (13.23x) | 124.63 (2.70x) |
| BoolValue JSON parse | 60.16 | — | — | 1056.32 (17.56x) | 224.93 (3.74x) |
| StringValue JSON stringify | 47.65 | — | — | 658.92 (13.83x) | 187.60 (3.94x) |
| StringValue JSON parse | 138.01 | — | — | 1141.61 (8.27x) | 320.14 (2.32x) |
| BytesValue JSON stringify | 48.42 | — | — | 653.61 (13.50x) | 211.59 (4.37x) |
| BytesValue JSON parse | 149.05 | — | — | 1163.75 (7.81x) | 337.59 (2.26x) |
| TextFormat parse | 709.99 | — | — | 4989.23 (7.03x) | 6525.75 (9.19x) |
| packed int32 decode | 767.80 | 1911.88 (2.49x) | 3250.76 (4.23x) | 949.36 (1.24x) | 2586.34 (3.37x) |
| packed bool encode | 2.01 | 1319.24 (656.34x) | 521.60 (259.50x) | 16.06 (7.99x) | 2389.84 (1188.98x) |
| packed bool decode | 263.78 | 1524.48 (5.78x) | 2552.80 (9.68x) | 803.16 (3.04x) | 1587.83 (6.02x) |
| largebytes decode | 89.70 | 5636.51 (62.84x) | 3019.52 (33.66x) | 2821.82 (31.46x) | 18574.36 (207.07x) |
| large map decode | 25445.94 | 91128.22 (3.58x) | 89441.28 (3.51x) | 93388.50 (3.67x) | 263679.45 (10.36x) |
| shuffled large map deterministic binary encode | 28063.08 | — | — | 91112.30 (3.25x) | 442224.20 (15.76x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON, direct WKT JSON, TextFormat, packed scalars, large bytes, maps,
oneof/optional workloads, and complex nested messages. Benchmark results are hardware-sensitive; compare full same-machine
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
