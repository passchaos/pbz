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

Latest accepted comparison (`/tmp/pbz-compare-after-any-struct-json-isolated.log`,
summarized in `/tmp/pbz-summary-after-any-struct-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 16.45 | 99.34 (6.04x) | 53.55 (3.26x) | 102.86 (6.25x) | 863.23 (52.48x) |
| binary decode | 92.35 | 250.38 (2.71x) | 233.43 (2.53x) | 222.81 (2.41x) | 899.58 (9.74x) |
| unknown count by number | 3.57 | — | — | 151.90 (42.55x) | — |
| scalarmix encode | 19.04 | 107.06 (5.62x) | 48.51 (2.55x) | 31.82 (1.67x) | 208.27 (10.94x) |
| scalarmix decode | 39.43 | 136.22 (3.45x) | 170.88 (4.33x) | 85.59 (2.17x) | 302.64 (7.68x) |
| textbytes encode | 9.52 | 77.33 (8.12x) | 33.60 (3.53x) | 117.55 (12.35x) | 147.65 (15.51x) |
| complex decode | 170.95 | 392.87 (2.30x) | 339.57 (1.99x) | 387.84 (2.27x) | 1351.50 (7.91x) |
| complex JSON parse | 2367.18 | — | — | 11943.40 (5.05x) | 7410.10 (3.13x) |
| Any WKT JSON stringify | 120.46 | — | — | 1887.48 (15.67x) | 988.15 (8.20x) |
| Any WKT JSON parse | 523.27 | — | — | 2987.85 (5.71x) | 1516.87 (2.90x) |
| Any Struct WKT JSON stringify | 601.07 | — | — | 5880.64 (9.78x) | 6012.79 (10.00x) |
| Any Struct WKT JSON parse | 1729.83 | — | — | 11081.20 (6.41x) | 8643.29 (5.00x) |
| Duration JSON stringify | 62.99 | — | — | 956.64 (15.19x) | 389.76 (6.19x) |
| Duration JSON parse | 7.95 | — | — | 1444.79 (181.73x) | 393.76 (49.53x) |
| FieldMask JSON stringify | 91.03 | — | — | 886.26 (9.74x) | 656.59 (7.21x) |
| FieldMask JSON parse | 147.27 | — | — | 1685.62 (11.45x) | 878.20 (5.96x) |
| Timestamp JSON stringify | 95.11 | — | — | 1133.32 (11.92x) | 424.03 (4.46x) |
| Timestamp JSON parse | 41.53 | — | — | 1490.80 (35.90x) | 446.91 (10.76x) |
| Empty JSON stringify | 20.84 | — | — | 495.29 (23.77x) | 86.31 (4.14x) |
| Empty JSON parse | 67.96 | — | — | 729.68 (10.74x) | 219.58 (3.23x) |
| Struct JSON stringify | 174.62 | — | — | 5783.92 (33.12x) | 3040.64 (17.41x) |
| Struct JSON parse | 847.45 | — | — | 16694.10 (19.70x) | 4642.20 (5.48x) |
| Value JSON stringify | 175.85 | — | — | 6657.67 (37.86x) | 3207.87 (18.24x) |
| Value JSON parse | 866.19 | — | — | 12221.00 (14.11x) | 4899.91 (5.66x) |
| ListValue JSON stringify | 129.49 | — | — | 4753.24 (36.71x) | 2120.04 (16.37x) |
| ListValue JSON parse | 654.33 | — | — | 8515.71 (13.01x) | 3830.03 (5.85x) |
| DoubleValue JSON stringify | 58.82 | — | — | 862.56 (14.66x) | 185.90 (3.16x) |
| DoubleValue JSON parse | 110.69 | — | — | 1225.91 (11.08x) | 289.91 (2.62x) |
| FloatValue JSON stringify | 68.96 | — | — | 798.64 (11.58x) | 184.69 (2.68x) |
| FloatValue JSON parse | 109.93 | — | — | 1214.80 (11.05x) | 289.52 (2.63x) |
| Int64Value JSON stringify | 40.33 | — | — | 681.26 (16.89x) | 282.86 (7.01x) |
| Int64Value JSON parse | 125.28 | — | — | 1233.55 (9.85x) | 463.01 (3.70x) |
| UInt64Value JSON stringify | 40.34 | — | — | 680.03 (16.86x) | 282.51 (7.00x) |
| UInt64Value JSON parse | 125.14 | — | — | 1218.55 (9.74x) | 458.36 (3.66x) |
| Int32Value JSON stringify | 43.68 | — | — | 634.14 (14.52x) | 134.77 (3.09x) |
| Int32Value JSON parse | 128.60 | — | — | 1185.15 (9.22x) | 319.99 (2.49x) |
| UInt32Value JSON stringify | 43.64 | — | — | 651.92 (14.94x) | 145.44 (3.33x) |
| UInt32Value JSON parse | 128.18 | — | — | 1186.56 (9.26x) | 318.05 (2.48x) |
| BoolValue JSON stringify | 41.19 | — | — | 626.11 (15.20x) | 127.87 (3.10x) |
| BoolValue JSON parse | 59.90 | — | — | 1058.35 (17.67x) | 230.28 (3.84x) |
| StringValue JSON stringify | 47.47 | — | — | 677.55 (14.27x) | 180.04 (3.79x) |
| StringValue JSON parse | 135.07 | — | — | 1147.39 (8.49x) | 319.82 (2.37x) |
| BytesValue JSON stringify | 48.52 | — | — | 658.06 (13.56x) | 214.85 (4.43x) |
| BytesValue JSON parse | 147.88 | — | — | 1171.40 (7.92x) | 345.69 (2.34x) |
| TextFormat parse | 711.30 | — | — | 4973.04 (6.99x) | 6562.56 (9.23x) |
| packed int32 decode | 686.93 | 1910.36 (2.78x) | 3208.85 (4.67x) | 961.79 (1.40x) | 2530.35 (3.68x) |
| packed bool encode | 2.01 | 1310.38 (651.93x) | 524.99 (261.19x) | 15.72 (7.82x) | 2388.08 (1188.10x) |
| packed bool decode | 262.84 | 1520.17 (5.78x) | 2546.66 (9.69x) | 810.06 (3.08x) | 1569.14 (5.97x) |
| largebytes decode | 91.01 | 5559.18 (61.08x) | 3026.07 (33.25x) | 2741.10 (30.12x) | 20005.24 (219.81x) |
| large map decode | 25616.45 | 90617.70 (3.54x) | 89634.93 (3.50x) | 95412.90 (3.72x) | 264463.76 (10.32x) |
| shuffled large map deterministic binary encode | 28606.78 | — | — | 103254.00 (3.61x) | 442342.67 (15.46x) |

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
