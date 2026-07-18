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

Latest accepted comparison (`/tmp/pbz-compare-after-any-bytesvalue-json-isolated.log`,
summarized in `/tmp/pbz-summary-after-any-bytesvalue-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 21.60 | 102.04 (4.72x) | 51.02 (2.36x) | 99.78 (4.62x) | 876.37 (40.57x) |
| binary decode | 93.97 | 252.53 (2.69x) | 231.70 (2.47x) | 210.29 (2.24x) | 895.87 (9.53x) |
| unknown count by number | 3.57 | — | — | 152.31 (42.66x) | — |
| scalarmix encode | 19.80 | 103.21 (5.21x) | 49.32 (2.49x) | 29.43 (1.49x) | 223.03 (11.26x) |
| scalarmix decode | 34.33 | 133.09 (3.88x) | 180.48 (5.26x) | 81.09 (2.36x) | 304.83 (8.88x) |
| textbytes encode | 11.53 | 78.64 (6.82x) | 33.36 (2.89x) | 116.42 (10.10x) | 146.23 (12.68x) |
| complex decode | 168.52 | 391.44 (2.32x) | 347.73 (2.06x) | 390.39 (2.32x) | 1365.41 (8.10x) |
| complex JSON parse | 2367.10 | — | — | 11964.60 (5.05x) | 7617.26 (3.22x) |
| Any WKT JSON stringify | 124.48 | — | — | 1888.26 (15.17x) | 990.12 (7.95x) |
| Any WKT JSON parse | 511.88 | — | — | 3027.24 (5.91x) | 1527.48 (2.98x) |
| Any Struct WKT JSON stringify | 603.50 | — | — | 5892.11 (9.76x) | 6061.81 (10.04x) |
| Any Struct WKT JSON parse | 1742.32 | — | — | 11137.30 (6.39x) | 8747.97 (5.02x) |
| Any Value WKT JSON stringify | 638.27 | — | — | 6076.64 (9.52x) | 6503.46 (10.19x) |
| Any Value WKT JSON parse | 1810.66 | — | — | 11294.90 (6.24x) | 9142.87 (5.05x) |
| Any StringValue WKT JSON stringify | 160.10 | — | — | 1564.82 (9.77x) | 805.96 (5.03x) |
| Any StringValue WKT JSON parse | 545.65 | — | — | 2679.34 (4.91x) | 1451.04 (2.66x) |
| Any BytesValue WKT JSON stringify | 143.78 | — | — | 1586.36 (11.03x) | 850.77 (5.92x) |
| Any BytesValue WKT JSON parse | 555.27 | — | — | 2702.57 (4.87x) | 1476.95 (2.66x) |
| Nested Any WKT JSON stringify | 255.39 | — | — | 2481.12 (9.72x) | 1459.82 (5.72x) |
| Nested Any WKT JSON parse | 858.31 | — | — | 4318.57 (5.03x) | 2844.27 (3.31x) |
| Duration JSON stringify | 57.80 | — | — | 966.21 (16.72x) | 380.69 (6.59x) |
| Duration JSON parse | 8.28 | — | — | 1462.18 (176.59x) | 402.16 (48.57x) |
| FieldMask JSON stringify | 92.53 | — | — | 891.89 (9.64x) | 646.13 (6.98x) |
| FieldMask JSON parse | 146.25 | — | — | 1666.95 (11.40x) | 877.20 (6.00x) |
| Timestamp JSON stringify | 95.72 | — | — | 1140.96 (11.92x) | 418.67 (4.37x) |
| Timestamp JSON parse | 41.40 | — | — | 1493.58 (36.08x) | 458.73 (11.08x) |
| Empty JSON stringify | 21.23 | — | — | 497.01 (23.41x) | 87.32 (4.11x) |
| Empty JSON parse | 67.45 | — | — | 719.21 (10.66x) | 214.01 (3.17x) |
| Struct JSON stringify | 170.10 | — | — | 5843.98 (34.36x) | 3083.08 (18.13x) |
| Struct JSON parse | 853.21 | — | — | 10927.00 (12.81x) | 4666.16 (5.47x) |
| Value JSON stringify | 174.62 | — | — | 6617.71 (37.90x) | 3224.36 (18.47x) |
| Value JSON parse | 863.48 | — | — | 12128.90 (14.05x) | 4933.99 (5.71x) |
| ListValue JSON stringify | 135.80 | — | — | 4764.24 (35.08x) | 2115.87 (15.58x) |
| ListValue JSON parse | 662.95 | — | — | 8535.75 (12.88x) | 3769.98 (5.69x) |
| DoubleValue JSON stringify | 59.40 | — | — | 861.32 (14.50x) | 187.27 (3.15x) |
| DoubleValue JSON parse | 111.21 | — | — | 1223.78 (11.00x) | 284.50 (2.56x) |
| FloatValue JSON stringify | 71.03 | — | — | 802.52 (11.30x) | 179.33 (2.52x) |
| FloatValue JSON parse | 110.27 | — | — | 1226.11 (11.12x) | 291.61 (2.64x) |
| Int64Value JSON stringify | 40.46 | — | — | 675.17 (16.69x) | 285.22 (7.05x) |
| Int64Value JSON parse | 124.71 | — | — | 1232.11 (9.88x) | 465.73 (3.73x) |
| UInt64Value JSON stringify | 40.51 | — | — | 679.87 (16.78x) | 284.50 (7.02x) |
| UInt64Value JSON parse | 126.51 | — | — | 1228.38 (9.71x) | 467.90 (3.70x) |
| Int32Value JSON stringify | 43.31 | — | — | 637.73 (14.72x) | 141.39 (3.26x) |
| Int32Value JSON parse | 129.98 | — | — | 1188.94 (9.15x) | 321.64 (2.47x) |
| UInt32Value JSON stringify | 43.24 | — | — | 644.77 (14.91x) | 143.17 (3.31x) |
| UInt32Value JSON parse | 129.37 | — | — | 1179.54 (9.12x) | 313.24 (2.42x) |
| BoolValue JSON stringify | 41.85 | — | — | 611.26 (14.61x) | 125.10 (2.99x) |
| BoolValue JSON parse | 59.48 | — | — | 1061.22 (17.84x) | 221.92 (3.73x) |
| StringValue JSON stringify | 47.13 | — | — | 675.50 (14.33x) | 190.14 (4.03x) |
| StringValue JSON parse | 138.00 | — | — | 1147.14 (8.31x) | 318.01 (2.30x) |
| BytesValue JSON stringify | 48.73 | — | — | 663.86 (13.62x) | 213.30 (4.38x) |
| BytesValue JSON parse | 148.10 | — | — | 1178.90 (7.96x) | 356.94 (2.41x) |
| TextFormat parse | 696.42 | — | — | 4989.69 (7.16x) | 6568.13 (9.43x) |
| packed int32 decode | 687.64 | 1915.31 (2.79x) | 3238.94 (4.71x) | 975.10 (1.42x) | 3009.74 (4.38x) |
| packed bool encode | 2.01 | 1321.08 (657.25x) | 517.97 (257.70x) | 15.73 (7.82x) | 2217.02 (1103.00x) |
| packed bool decode | 262.85 | 1524.71 (5.80x) | 2554.56 (9.72x) | 812.97 (3.09x) | 1579.08 (6.01x) |
| largebytes decode | 88.28 | 5635.87 (63.84x) | 3014.32 (34.14x) | 2725.90 (30.88x) | 21387.29 (242.27x) |
| large map decode | 25770.89 | 90286.59 (3.50x) | 89739.36 (3.48x) | 86167.90 (3.34x) | 264107.65 (10.25x) |
| shuffled large map deterministic binary encode | 28078.07 | — | — | 93022.70 (3.31x) | 436310.19 (15.54x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded `Duration`, `Struct`, `Value`,
`StringValue`, `BytesValue`, and recursive nested `Any` payloads), direct WKT JSON, TextFormat, packed scalars, large bytes,
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
