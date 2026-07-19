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

Latest accepted comparison (`/tmp/pbz-compare-after-float-nan-json-isolated.log`,
summarized in `/tmp/pbz-summary-after-float-nan-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 25.47 | 126.60 (4.97x) | 62.59 (2.46x) | 119.11 (4.68x) | 950.96 (37.34x) |
| binary decode | 138.03 | 295.59 (2.14x) | 302.66 (2.19x) | 268.82 (1.95x) | 976.75 (7.08x) |
| unknown count by number | 4.77 | — | — | 177.55 (37.22x) | — |
| scalarmix encode | 27.11 | 112.62 (4.15x) | 66.94 (2.47x) | 45.67 (1.68x) | 238.59 (8.80x) |
| scalarmix decode | 50.29 | 162.90 (3.24x) | 210.20 (4.18x) | 112.35 (2.23x) | 361.52 (7.19x) |
| textbytes encode | 13.29 | 91.73 (6.90x) | 43.27 (3.26x) | 146.80 (11.05x) | 170.69 (12.84x) |
| complex decode | 227.95 | 461.78 (2.03x) | 431.23 (1.89x) | 478.70 (2.10x) | 1628.64 (7.14x) |
| complex JSON parse | 2725.84 | — | — | 16635.20 (6.10x) | 10526.49 (3.86x) |
| Any WKT JSON stringify | 170.90 | — | — | 3050.78 (17.85x) | 1306.32 (7.64x) |
| Any WKT JSON parse | 574.46 | — | — | 4568.27 (7.95x) | 2075.34 (3.61x) |
| Any FieldMask WKT JSON stringify | 277.46 | — | — | 2457.10 (8.86x) | 1748.38 (6.30x) |
| Any FieldMask WKT JSON parse | 796.77 | — | — | 4899.61 (6.15x) | 2856.83 (3.59x) |
| Any Timestamp WKT JSON stringify | 238.55 | — | — | 3023.15 (12.67x) | 1363.53 (5.72x) |
| Any Timestamp WKT JSON parse | 644.97 | — | — | 4682.82 (7.26x) | 2226.28 (3.45x) |
| Any Empty WKT JSON stringify | 114.99 | — | — | 1310.71 (11.40x) | 729.11 (6.34x) |
| Any Empty WKT JSON parse | 378.26 | — | — | 3150.51 (8.33x) | 1648.33 (4.36x) |
| Any Struct WKT JSON stringify | 760.83 | — | — | 9023.32 (11.86x) | 8850.93 (11.63x) |
| Any Struct WKT JSON parse | 1981.93 | — | — | 17147.90 (8.65x) | 12509.09 (6.31x) |
| Any Value WKT JSON stringify | 786.97 | — | — | 9219.48 (11.72x) | 9317.94 (11.84x) |
| Any Value WKT JSON parse | 2039.77 | — | — | 17069.50 (8.37x) | 12946.25 (6.35x) |
| Any DoubleValue WKT JSON stringify | 240.78 | — | — | 2848.73 (11.83x) | 882.41 (3.66x) |
| Any DoubleValue WKT JSON parse | 577.55 | — | — | 4311.10 (7.46x) | 1893.34 (3.28x) |
| Any DoubleValue NaN WKT JSON stringify | 184.32 | — | — | 2318.89 (12.58x) | 778.21 (4.22x) |
| Any DoubleValue NaN WKT JSON parse | 575.30 | — | — | 4050.06 (7.04x) | 1843.68 (3.20x) |
| Any FloatValue WKT JSON stringify | 247.61 | — | — | 2783.28 (11.24x) | 876.81 (3.54x) |
| Any FloatValue WKT JSON parse | 578.78 | — | — | 4264.09 (7.37x) | 1867.18 (3.23x) |
| Any FloatValue NaN WKT JSON stringify | 185.71 | — | — | 2245.30 (12.09x) | 786.02 (4.23x) |
| Any FloatValue NaN WKT JSON parse | 576.87 | — | — | 4008.10 (6.95x) | 1794.03 (3.11x) |
| Any Int64Value WKT JSON stringify | 199.20 | — | — | 2160.99 (10.85x) | 1111.07 (5.58x) |
| Any Int64Value WKT JSON parse | 627.51 | — | — | 4235.72 (6.75x) | 2310.96 (3.68x) |
| Any UInt64Value WKT JSON stringify | 207.74 | — | — | 2212.18 (10.65x) | 1114.18 (5.36x) |
| Any UInt64Value WKT JSON parse | 635.07 | — | — | 4227.96 (6.66x) | 2257.89 (3.56x) |
| Any Int32Value WKT JSON stringify | 202.45 | — | — | 2245.15 (11.09x) | 847.49 (4.19x) |
| Any Int32Value WKT JSON parse | 600.95 | — | — | 4081.19 (6.79x) | 1923.69 (3.20x) |
| Any UInt32Value WKT JSON stringify | 211.10 | — | — | 2198.67 (10.42x) | 833.93 (3.95x) |
| Any UInt32Value WKT JSON parse | 607.58 | — | — | 4066.63 (6.69x) | 1936.96 (3.19x) |
| Any BoolValue WKT JSON stringify | 207.91 | — | — | 2142.41 (10.30x) | 789.78 (3.80x) |
| Any BoolValue WKT JSON parse | 555.60 | — | — | 4022.33 (7.24x) | 1717.30 (3.09x) |
| Any StringValue WKT JSON stringify | 232.87 | — | — | 2254.49 (9.68x) | 895.45 (3.85x) |
| Any StringValue WKT JSON parse | 617.45 | — | — | 4076.03 (6.60x) | 1882.69 (3.05x) |
| Any BytesValue WKT JSON stringify | 221.78 | — | — | 2302.03 (10.38x) | 914.27 (4.12x) |
| Any BytesValue WKT JSON parse | 624.19 | — | — | 4220.61 (6.76x) | 1957.15 (3.14x) |
| Nested Any WKT JSON stringify | 350.42 | — | — | 3442.68 (9.82x) | 1580.42 (4.51x) |
| Nested Any WKT JSON parse | 1001.77 | — | — | 6092.77 (6.08x) | 3513.88 (3.51x) |
| Duration JSON stringify | 63.96 | — | — | 1552.97 (24.28x) | 383.74 (6.00x) |
| Duration JSON parse | 11.66 | — | — | 2294.00 (196.74x) | 416.78 (35.74x) |
| FieldMask JSON stringify | 92.89 | — | — | 1295.65 (13.95x) | 713.61 (7.68x) |
| FieldMask JSON parse | 179.38 | — | — | 2654.07 (14.80x) | 1033.70 (5.76x) |
| Timestamp JSON stringify | 125.17 | — | — | 1733.05 (13.85x) | 468.60 (3.74x) |
| Timestamp JSON parse | 57.38 | — | — | 2322.48 (40.48x) | 471.75 (8.22x) |
| Empty JSON stringify | 22.54 | — | — | 696.06 (30.88x) | 117.53 (5.21x) |
| Empty JSON parse | 73.01 | — | — | 1109.26 (15.19x) | 246.63 (3.38x) |
| Struct JSON stringify | 259.77 | — | — | 8814.99 (33.93x) | 4156.23 (16.00x) |
| Struct JSON parse | 938.67 | — | — | 16753.10 (17.85x) | 6316.06 (6.73x) |
| Value JSON stringify | 262.28 | — | — | 9850.79 (37.56x) | 4297.84 (16.39x) |
| Value JSON parse | 947.05 | — | — | 18050.20 (19.06x) | 6622.55 (6.99x) |
| ListValue JSON stringify | 194.92 | — | — | 7501.25 (38.48x) | 2823.16 (14.48x) |
| ListValue JSON parse | 736.70 | — | — | 13639.70 (18.51x) | 5216.26 (7.08x) |
| DoubleValue JSON stringify | 97.05 | — | — | 1447.76 (14.92x) | 213.42 (2.20x) |
| DoubleValue JSON parse | 113.13 | — | — | 2098.25 (18.55x) | 336.81 (2.98x) |
| DoubleValue NaN JSON stringify | 52.77 | — | — | 983.86 (18.64x) | 133.68 (2.53x) |
| DoubleValue NaN JSON parse | 102.00 | — | — | 1712.80 (16.79x) | 318.60 (3.12x) |
| FloatValue JSON stringify | 101.62 | — | — | 1374.91 (13.53x) | 189.06 (1.86x) |
| FloatValue JSON parse | 113.48 | — | — | 2139.25 (18.85x) | 318.23 (2.80x) |
| FloatValue NaN JSON stringify | 52.96 | — | — | 951.71 (17.97x) | 142.31 (2.69x) |
| FloatValue NaN JSON parse | 102.60 | — | — | 1724.52 (16.81x) | 308.49 (3.01x) |
| Int64Value JSON stringify | 44.43 | — | — | 967.87 (21.78x) | 295.89 (6.66x) |
| Int64Value JSON parse | 140.76 | — | — | 1958.89 (13.92x) | 504.24 (3.58x) |
| UInt64Value JSON stringify | 44.62 | — | — | 997.30 (22.35x) | 296.74 (6.65x) |
| UInt64Value JSON parse | 138.89 | — | — | 1942.87 (13.99x) | 497.77 (3.58x) |
| Int32Value JSON stringify | 45.90 | — | — | 951.55 (20.73x) | 156.81 (3.42x) |
| Int32Value JSON parse | 129.85 | — | — | 1879.46 (14.47x) | 346.37 (2.67x) |
| UInt32Value JSON stringify | 45.45 | — | — | 911.32 (20.05x) | 154.53 (3.40x) |
| UInt32Value JSON parse | 129.99 | — | — | 1884.60 (14.50x) | 348.02 (2.68x) |
| BoolValue JSON stringify | 42.35 | — | — | 892.82 (21.08x) | 129.03 (3.05x) |
| BoolValue JSON parse | 59.14 | — | — | 1682.73 (28.45x) | 255.89 (4.33x) |
| StringValue JSON stringify | 54.76 | — | — | 1021.73 (18.66x) | 199.09 (3.64x) |
| StringValue JSON parse | 130.00 | — | — | 1807.21 (13.90x) | 358.14 (2.75x) |
| BytesValue JSON stringify | 47.86 | — | — | 968.36 (20.23x) | 229.08 (4.79x) |
| BytesValue JSON parse | 142.95 | — | — | 1970.07 (13.78x) | 373.57 (2.61x) |
| TextFormat parse | 861.48 | — | — | 5429.85 (6.30x) | 8056.65 (9.35x) |
| packed int32 decode | 1028.91 | 2970.66 (2.89x) | 4229.92 (4.11x) | 1374.08 (1.34x) | 4401.52 (4.28x) |
| packed bool encode | 2.76 | 2079.94 (753.60x) | 539.14 (195.34x) | 25.76 (9.33x) | 4383.31 (1588.16x) |
| packed bool decode | 272.40 | 2058.42 (7.56x) | 4217.76 (15.48x) | 1107.61 (4.07x) | 2678.00 (9.83x) |
| largebytes decode | 124.51 | 8438.70 (67.78x) | 4548.56 (36.53x) | 4254.91 (34.17x) | 23608.06 (189.61x) |
| large map decode | 37551.85 | 133477.24 (3.55x) | 118394.77 (3.15x) | 117085.00 (3.12x) | 297263.56 (7.92x) |
| shuffled large map deterministic binary encode | 36381.90 | — | — | 111268.00 (3.06x) | 455077.80 (12.51x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded `Duration`, `Struct`, `Value`,
`FieldMask`, `Timestamp`, `Empty`, `Int64Value`, `DoubleValue`, non-finite `DoubleValue` (`NaN`), `FloatValue`, non-finite `FloatValue` (`NaN`), `UInt64Value`, `Int32Value`, `UInt32Value`, `BoolValue`, `StringValue`, `BytesValue`, and recursive nested `Any` payloads), direct WKT JSON, TextFormat, packed scalars, large bytes,
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
