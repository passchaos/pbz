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

Latest accepted comparison (`/tmp/pbz-compare-after-infinity-json-isolated.log`,
summarized in `/tmp/pbz-summary-after-infinity-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 26.82 | 125.40 (4.68x) | 63.64 (2.37x) | 131.04 (4.89x) | 952.11 (35.50x) |
| binary decode | 131.62 | 299.76 (2.28x) | 298.40 (2.27x) | 268.39 (2.04x) | 981.10 (7.45x) |
| unknown count by number | 4.77 | — | — | 175.16 (36.72x) | — |
| scalarmix encode | 26.32 | 113.16 (4.30x) | 67.29 (2.56x) | 45.70 (1.74x) | 237.36 (9.02x) |
| scalarmix decode | 55.75 | 163.66 (2.94x) | 208.25 (3.74x) | 112.27 (2.01x) | 361.18 (6.48x) |
| textbytes encode | 13.54 | 91.42 (6.75x) | 43.25 (3.19x) | 146.32 (10.81x) | 170.22 (12.57x) |
| complex decode | 216.56 | 472.46 (2.18x) | 432.60 (2.00x) | 481.40 (2.22x) | 1618.60 (7.47x) |
| complex JSON parse | 2718.73 | — | — | 16793.30 (6.18x) | 10542.37 (3.88x) |
| Any WKT JSON stringify | 168.06 | — | — | 3054.76 (18.18x) | 1344.09 (8.00x) |
| Any WKT JSON parse | 558.94 | — | — | 4605.97 (8.24x) | 2075.82 (3.71x) |
| Any FieldMask WKT JSON stringify | 274.94 | — | — | 2450.10 (8.91x) | 1743.97 (6.34x) |
| Any FieldMask WKT JSON parse | 779.40 | — | — | 4990.25 (6.40x) | 2915.93 (3.74x) |
| Any Timestamp WKT JSON stringify | 245.10 | — | — | 3048.23 (12.44x) | 1329.56 (5.42x) |
| Any Timestamp WKT JSON parse | 631.70 | — | — | 4577.27 (7.25x) | 2263.92 (3.58x) |
| Any Empty WKT JSON stringify | 115.39 | — | — | 1295.37 (11.23x) | 653.51 (5.66x) |
| Any Empty WKT JSON parse | 370.87 | — | — | 3145.64 (8.48x) | 1634.57 (4.41x) |
| Any Struct WKT JSON stringify | 765.24 | — | — | 9069.06 (11.85x) | 8846.64 (11.56x) |
| Any Struct WKT JSON parse | 1955.51 | — | — | 17384.80 (8.89x) | 12488.45 (6.39x) |
| Any Value WKT JSON stringify | 796.01 | — | — | 9499.89 (11.93x) | 9245.58 (11.61x) |
| Any Value WKT JSON parse | 2019.47 | — | — | 19856.20 (9.83x) | 12986.01 (6.43x) |
| Any DoubleValue WKT JSON stringify | 241.02 | — | — | 2829.68 (11.74x) | 894.77 (3.71x) |
| Any DoubleValue WKT JSON parse | 566.45 | — | — | 4389.93 (7.75x) | 1948.78 (3.44x) |
| Any DoubleValue NaN WKT JSON stringify | 184.72 | — | — | 2302.03 (12.46x) | 769.22 (4.16x) |
| Any DoubleValue NaN WKT JSON parse | 561.74 | — | — | 4053.16 (7.22x) | 1905.72 (3.39x) |
| Any DoubleValue Infinity WKT JSON stringify | 187.50 | — | — | 2254.41 (12.02x) | 773.82 (4.13x) |
| Any DoubleValue Infinity WKT JSON parse | 567.51 | — | — | 4052.59 (7.14x) | 1922.70 (3.39x) |
| Any FloatValue WKT JSON stringify | 247.25 | — | — | 2762.76 (11.17x) | 889.61 (3.60x) |
| Any FloatValue WKT JSON parse | 565.45 | — | — | 4341.48 (7.68x) | 1942.61 (3.44x) |
| Any FloatValue NaN WKT JSON stringify | 185.69 | — | — | 2237.51 (12.05x) | 781.60 (4.21x) |
| Any FloatValue NaN WKT JSON parse | 562.24 | — | — | 4056.03 (7.21x) | 1838.07 (3.27x) |
| Any FloatValue Infinity WKT JSON stringify | 190.71 | — | — | 2181.32 (11.44x) | 769.37 (4.03x) |
| Any FloatValue Infinity WKT JSON parse | 569.63 | — | — | 4021.92 (7.06x) | 1912.96 (3.36x) |
| Any Int64Value WKT JSON stringify | 200.74 | — | — | 2171.23 (10.82x) | 1119.26 (5.58x) |
| Any Int64Value WKT JSON parse | 616.04 | — | — | 4249.92 (6.90x) | 2341.43 (3.80x) |
| Any UInt64Value WKT JSON stringify | 212.79 | — | — | 2192.29 (10.30x) | 1143.24 (5.37x) |
| Any UInt64Value WKT JSON parse | 631.78 | — | — | 4264.17 (6.75x) | 2314.01 (3.66x) |
| Any Int32Value WKT JSON stringify | 207.61 | — | — | 2238.41 (10.78x) | 788.72 (3.80x) |
| Any Int32Value WKT JSON parse | 589.46 | — | — | 4117.21 (6.98x) | 1974.66 (3.35x) |
| Any UInt32Value WKT JSON stringify | 209.36 | — | — | 2183.20 (10.43x) | 820.99 (3.92x) |
| Any UInt32Value WKT JSON parse | 593.89 | — | — | 4133.74 (6.96x) | 2006.76 (3.38x) |
| Any BoolValue WKT JSON stringify | 205.75 | — | — | 2134.90 (10.38x) | 764.44 (3.72x) |
| Any BoolValue WKT JSON parse | 539.66 | — | — | 4041.26 (7.49x) | 1767.36 (3.27x) |
| Any StringValue WKT JSON stringify | 232.48 | — | — | 2645.63 (11.38x) | 893.90 (3.85x) |
| Any StringValue WKT JSON parse | 602.05 | — | — | 4275.49 (7.10x) | 1961.77 (3.26x) |
| Any BytesValue WKT JSON stringify | 221.45 | — | — | 2362.95 (10.67x) | 918.56 (4.15x) |
| Any BytesValue WKT JSON parse | 609.88 | — | — | 4359.60 (7.15x) | 2021.94 (3.32x) |
| Nested Any WKT JSON stringify | 351.90 | — | — | 3526.07 (10.02x) | 1645.56 (4.68x) |
| Nested Any WKT JSON parse | 983.88 | — | — | 6273.75 (6.38x) | 3566.53 (3.62x) |
| Duration JSON stringify | 63.00 | — | — | 1552.73 (24.65x) | 340.73 (5.41x) |
| Duration JSON parse | 11.80 | — | — | 2304.13 (195.27x) | 427.70 (36.25x) |
| FieldMask JSON stringify | 92.28 | — | — | 1307.48 (14.17x) | 715.05 (7.75x) |
| FieldMask JSON parse | 175.55 | — | — | 2660.81 (15.16x) | 1043.16 (5.94x) |
| Timestamp JSON stringify | 126.65 | — | — | 1738.25 (13.72x) | 461.37 (3.64x) |
| Timestamp JSON parse | 57.45 | — | — | 2318.36 (40.35x) | 473.30 (8.24x) |
| Empty JSON stringify | 22.14 | — | — | 695.11 (31.40x) | 105.89 (4.78x) |
| Empty JSON parse | 76.65 | — | — | 1110.25 (14.48x) | 246.79 (3.22x) |
| Struct JSON stringify | 257.90 | — | — | 9041.35 (35.06x) | 4131.04 (16.02x) |
| Struct JSON parse | 935.02 | — | — | 16865.40 (18.04x) | 6294.35 (6.73x) |
| Value JSON stringify | 265.84 | — | — | 9876.05 (37.15x) | 4340.67 (16.33x) |
| Value JSON parse | 966.89 | — | — | 18092.20 (18.71x) | 6544.27 (6.77x) |
| ListValue JSON stringify | 194.63 | — | — | 7599.75 (39.05x) | 2797.15 (14.37x) |
| ListValue JSON parse | 731.25 | — | — | 13598.50 (18.60x) | 5191.13 (7.10x) |
| DoubleValue JSON stringify | 98.26 | — | — | 1463.24 (14.89x) | 194.25 (1.98x) |
| DoubleValue JSON parse | 113.48 | — | — | 2078.17 (18.31x) | 317.64 (2.80x) |
| DoubleValue NaN JSON stringify | 52.95 | — | — | 980.48 (18.52x) | 140.00 (2.64x) |
| DoubleValue NaN JSON parse | 101.68 | — | — | 1747.92 (17.19x) | 311.53 (3.06x) |
| DoubleValue Infinity JSON stringify | 55.86 | — | — | 975.94 (17.47x) | 133.11 (2.38x) |
| DoubleValue Infinity JSON parse | 103.86 | — | — | 1743.71 (16.79x) | 313.71 (3.02x) |
| FloatValue JSON stringify | 102.55 | — | — | 1407.61 (13.73x) | 196.57 (1.92x) |
| FloatValue JSON parse | 112.10 | — | — | 2102.90 (18.76x) | 311.34 (2.78x) |
| FloatValue NaN JSON stringify | 52.71 | — | — | 999.24 (18.96x) | 135.25 (2.57x) |
| FloatValue NaN JSON parse | 101.30 | — | — | 1687.73 (16.66x) | 297.14 (2.93x) |
| FloatValue Infinity JSON stringify | 55.68 | — | — | 964.50 (17.32x) | 139.74 (2.51x) |
| FloatValue Infinity JSON parse | 103.28 | — | — | 1702.49 (16.48x) | 297.02 (2.88x) |
| Int64Value JSON stringify | 41.97 | — | — | 1005.89 (23.97x) | 280.24 (6.68x) |
| Int64Value JSON parse | 139.86 | — | — | 1977.18 (14.14x) | 503.78 (3.60x) |
| UInt64Value JSON stringify | 41.73 | — | — | 1002.24 (24.02x) | 303.46 (7.27x) |
| UInt64Value JSON parse | 139.66 | — | — | 1937.33 (13.87x) | 505.69 (3.62x) |
| Int32Value JSON stringify | 45.83 | — | — | 981.31 (21.41x) | 164.95 (3.60x) |
| Int32Value JSON parse | 135.36 | — | — | 1905.54 (14.08x) | 346.44 (2.56x) |
| UInt32Value JSON stringify | 46.18 | — | — | 917.31 (19.86x) | 155.67 (3.37x) |
| UInt32Value JSON parse | 135.29 | — | — | 1903.40 (14.07x) | 345.01 (2.55x) |
| BoolValue JSON stringify | 42.09 | — | — | 903.84 (21.47x) | 136.98 (3.25x) |
| BoolValue JSON parse | 59.10 | — | — | 1716.00 (29.04x) | 260.48 (4.41x) |
| StringValue JSON stringify | 53.60 | — | — | 993.30 (18.53x) | 207.61 (3.87x) |
| StringValue JSON parse | 131.28 | — | — | 1811.18 (13.80x) | 353.00 (2.69x) |
| BytesValue JSON stringify | 47.26 | — | — | 972.37 (20.57x) | 211.63 (4.48x) |
| BytesValue JSON parse | 142.33 | — | — | 1982.46 (13.93x) | 374.67 (2.63x) |
| TextFormat parse | 843.15 | — | — | 5572.72 (6.61x) | 7990.54 (9.48x) |
| packed int32 decode | 994.89 | 2973.14 (2.99x) | 4224.13 (4.25x) | 1342.49 (1.35x) | 4354.10 (4.38x) |
| packed bool encode | 2.51 | 2079.81 (828.61x) | 539.79 (215.06x) | 22.56 (8.99x) | 4379.73 (1744.91x) |
| packed bool decode | 271.19 | 2056.52 (7.58x) | 3877.34 (14.30x) | 1108.12 (4.09x) | 2678.79 (9.88x) |
| largebytes decode | 126.08 | 8454.43 (67.06x) | 4533.38 (35.96x) | 5843.02 (46.34x) | 23898.55 (189.55x) |
| large map decode | 38776.99 | 127953.25 (3.30x) | 131062.14 (3.38x) | 118740.00 (3.06x) | 305993.54 (7.89x) |
| shuffled large map deterministic binary encode | 36026.75 | — | — | 113486.00 (3.15x) | 460900.51 (12.79x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded `Duration`, `Struct`, `Value`,
`FieldMask`, `Timestamp`, `Empty`, `Int64Value`, `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`), `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`), `UInt64Value`, `Int32Value`, `UInt32Value`, `BoolValue`, `StringValue`, `BytesValue`, and recursive nested `Any` payloads), direct WKT JSON, TextFormat, packed scalars, large bytes,
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
