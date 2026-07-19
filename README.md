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

Latest accepted comparison (`/tmp/pbz-compare-after-min-timestamp-json-isolated.log`,
summarized in `/tmp/pbz-summary-after-min-timestamp-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 23.38 | 128.08 (5.48x) | 66.25 (2.83x) | 131.05 (5.61x) | 949.58 (40.62x) |
| binary decode | 129.21 | 309.09 (2.39x) | 308.05 (2.38x) | 270.17 (2.09x) | 984.17 (7.62x) |
| unknown count by number | 5.02 | — | — | 175.71 (35.00x) | — |
| scalarmix encode | 26.82 | 116.06 (4.33x) | 68.68 (2.56x) | 45.31 (1.69x) | 237.27 (8.85x) |
| scalarmix decode | 50.71 | 167.04 (3.29x) | 231.30 (4.56x) | 112.61 (2.22x) | 360.38 (7.11x) |
| textbytes encode | 13.53 | 93.46 (6.91x) | 44.55 (3.29x) | 152.27 (11.25x) | 173.11 (12.79x) |
| complex decode | 225.77 | 468.75 (2.08x) | 437.89 (1.94x) | 496.13 (2.20x) | 1622.00 (7.18x) |
| complex JSON parse | 2744.45 | — | — | 16815.60 (6.13x) | 10425.95 (3.80x) |
| Any WKT JSON stringify | 176.73 | — | — | 3048.14 (17.25x) | 1333.22 (7.54x) |
| Any WKT JSON parse | 563.97 | — | — | 4573.01 (8.11x) | 2085.97 (3.70x) |
| Any NegativeDuration WKT JSON stringify | 187.60 | — | — | 3059.36 (16.31x) | 1392.76 (7.42x) |
| Any NegativeDuration WKT JSON parse | 566.75 | — | — | 4695.49 (8.28x) | 2191.56 (3.87x) |
| Any FieldMask WKT JSON stringify | 283.43 | — | — | 2420.82 (8.54x) | 1748.43 (6.17x) |
| Any FieldMask WKT JSON parse | 783.93 | — | — | 4865.99 (6.21x) | 2909.94 (3.71x) |
| Any Timestamp WKT JSON stringify | 246.98 | — | — | 2967.27 (12.01x) | 1359.63 (5.51x) |
| Any Timestamp WKT JSON parse | 628.37 | — | — | 4716.84 (7.51x) | 2246.87 (3.58x) |
| Any PreEpoch Timestamp WKT JSON stringify | 197.63 | — | — | 2862.20 (14.48x) | 1294.72 (6.55x) |
| Any PreEpoch Timestamp WKT JSON parse | 618.58 | — | — | 4675.10 (7.56x) | 2210.11 (3.57x) |
| Any Max Timestamp WKT JSON stringify | 223.03 | — | — | 3028.97 (13.58x) | 1345.07 (6.03x) |
| Any Max Timestamp WKT JSON parse | 647.55 | — | — | 4760.40 (7.35x) | 2277.98 (3.52x) |
| Any Min Timestamp WKT JSON stringify | 234.86 | — | — | 2870.19 (12.22x) | 1286.89 (5.48x) |
| Any Min Timestamp WKT JSON parse | 621.59 | — | — | 4654.82 (7.49x) | 2174.50 (3.50x) |
| Any Empty WKT JSON stringify | 125.59 | — | — | 1310.00 (10.43x) | 661.20 (5.26x) |
| Any Empty WKT JSON parse | 376.30 | — | — | 3153.99 (8.38x) | 1647.29 (4.38x) |
| Any Struct WKT JSON stringify | 800.91 | — | — | 9003.99 (11.24x) | 9044.59 (11.29x) |
| Any Struct WKT JSON parse | 1953.53 | — | — | 16543.00 (8.47x) | 12778.55 (6.54x) |
| Any Value WKT JSON stringify | 813.51 | — | — | 9069.74 (11.15x) | 9560.55 (11.75x) |
| Any Value WKT JSON parse | 2012.04 | — | — | 17194.90 (8.55x) | 13228.74 (6.57x) |
| Any DoubleValue WKT JSON stringify | 253.53 | — | — | 2827.32 (11.15x) | 1144.60 (4.51x) |
| Any DoubleValue WKT JSON parse | 567.94 | — | — | 4446.71 (7.83x) | 2131.43 (3.75x) |
| Any DoubleValue NaN WKT JSON stringify | 199.75 | — | — | 2327.59 (11.65x) | 909.10 (4.55x) |
| Any DoubleValue NaN WKT JSON parse | 559.78 | — | — | 4070.51 (7.27x) | 2012.62 (3.60x) |
| Any DoubleValue Infinity WKT JSON stringify | 205.84 | — | — | 2270.22 (11.03x) | 874.71 (4.25x) |
| Any DoubleValue Infinity WKT JSON parse | 571.83 | — | — | 4038.71 (7.06x) | 2087.28 (3.65x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 209.98 | — | — | 2239.73 (10.67x) | 897.83 (4.28x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 570.13 | — | — | 4042.11 (7.09x) | 2073.05 (3.64x) |
| Any FloatValue WKT JSON stringify | 260.83 | — | — | 2800.80 (10.74x) | 1052.10 (4.03x) |
| Any FloatValue WKT JSON parse | 569.75 | — | — | 4325.31 (7.59x) | 2088.44 (3.67x) |
| Any FloatValue NaN WKT JSON stringify | 203.50 | — | — | 2211.43 (10.87x) | 884.06 (4.34x) |
| Any FloatValue NaN WKT JSON parse | 571.23 | — | — | 4031.98 (7.06x) | 2017.52 (3.53x) |
| Any FloatValue Infinity WKT JSON stringify | 213.75 | — | — | 2223.46 (10.40x) | 896.43 (4.19x) |
| Any FloatValue Infinity WKT JSON parse | 571.00 | — | — | 4046.69 (7.09x) | 2081.38 (3.65x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 212.41 | — | — | 2220.05 (10.45x) | 898.07 (4.23x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 575.13 | — | — | 4049.94 (7.04x) | 2079.88 (3.62x) |
| Any Int64Value WKT JSON stringify | 208.99 | — | — | 2227.44 (10.66x) | 1236.65 (5.92x) |
| Any Int64Value WKT JSON parse | 616.94 | — | — | 4336.98 (7.03x) | 2433.76 (3.94x) |
| Any UInt64Value WKT JSON stringify | 217.75 | — | — | 2183.13 (10.03x) | 1255.42 (5.77x) |
| Any UInt64Value WKT JSON parse | 623.42 | — | — | 4257.36 (6.83x) | 2360.13 (3.79x) |
| Any Int32Value WKT JSON stringify | 213.80 | — | — | 2215.70 (10.36x) | 825.45 (3.86x) |
| Any Int32Value WKT JSON parse | 589.86 | — | — | 4170.56 (7.07x) | 2065.22 (3.50x) |
| Any UInt32Value WKT JSON stringify | 221.71 | — | — | 2177.45 (9.82x) | 887.57 (4.00x) |
| Any UInt32Value WKT JSON parse | 605.83 | — | — | 4162.35 (6.87x) | 2088.04 (3.45x) |
| Any BoolValue WKT JSON stringify | 214.28 | — | — | 2164.63 (10.10x) | 863.20 (4.03x) |
| Any BoolValue WKT JSON parse | 547.03 | — | — | 4016.90 (7.34x) | 1843.08 (3.37x) |
| Any StringValue WKT JSON stringify | 251.00 | — | — | 2246.21 (8.95x) | 901.63 (3.59x) |
| Any StringValue WKT JSON parse | 607.20 | — | — | 4073.64 (6.71x) | 1946.97 (3.21x) |
| Any BytesValue WKT JSON stringify | 229.71 | — | — | 2258.21 (9.83x) | 944.79 (4.11x) |
| Any BytesValue WKT JSON parse | 616.50 | — | — | 4227.67 (6.86x) | 2005.97 (3.25x) |
| Nested Any WKT JSON stringify | 396.63 | — | — | 3370.59 (8.50x) | 1676.53 (4.23x) |
| Nested Any WKT JSON parse | 999.16 | — | — | 6199.59 (6.20x) | 3731.45 (3.73x) |
| Duration JSON stringify | 65.78 | — | — | 1533.82 (23.32x) | 454.82 (6.91x) |
| Duration JSON parse | 12.32 | — | — | 2250.85 (182.70x) | 523.81 (42.52x) |
| NegativeDuration JSON stringify | 66.44 | — | — | 1592.44 (23.97x) | 514.84 (7.75x) |
| NegativeDuration JSON parse | 12.59 | — | — | 2368.49 (188.12x) | 499.19 (39.65x) |
| FieldMask JSON stringify | 91.87 | — | — | 1364.41 (14.85x) | 806.66 (8.78x) |
| FieldMask JSON parse | 183.50 | — | — | 2667.30 (14.54x) | 1193.12 (6.50x) |
| Timestamp JSON stringify | 131.22 | — | — | 1732.61 (13.20x) | 540.11 (4.12x) |
| Timestamp JSON parse | 57.08 | — | — | 2298.46 (40.27x) | 557.96 (9.78x) |
| PreEpoch Timestamp JSON stringify | 89.41 | — | — | 1619.95 (18.12x) | 507.74 (5.68x) |
| PreEpoch Timestamp JSON parse | 55.14 | — | — | 2293.68 (41.60x) | 543.48 (9.86x) |
| Max Timestamp JSON stringify | 105.88 | — | — | 1786.80 (16.88x) | 544.24 (5.14x) |
| Max Timestamp JSON parse | 64.61 | — | — | 2368.56 (36.66x) | 578.19 (8.95x) |
| Min Timestamp JSON stringify | 119.43 | — | — | 1610.22 (13.48x) | 519.38 (4.35x) |
| Min Timestamp JSON parse | 53.12 | — | — | 2276.07 (42.85x) | 534.63 (10.06x) |
| Empty JSON stringify | 23.86 | — | — | 699.38 (29.31x) | 112.06 (4.70x) |
| Empty JSON parse | 76.38 | — | — | 1100.22 (14.40x) | 434.20 (5.68x) |
| Struct JSON stringify | 281.69 | — | — | 8887.16 (31.55x) | 4537.75 (16.11x) |
| Struct JSON parse | 962.38 | — | — | 16750.00 (17.40x) | 6982.22 (7.26x) |
| Value JSON stringify | 285.98 | — | — | 9814.13 (34.32x) | 4715.76 (16.49x) |
| Value JSON parse | 977.75 | — | — | 18023.70 (18.43x) | 7832.28 (8.01x) |
| ListValue JSON stringify | 204.20 | — | — | 7594.35 (37.19x) | 3032.70 (14.85x) |
| ListValue JSON parse | 742.72 | — | — | 13515.20 (18.20x) | 6091.56 (8.20x) |
| DoubleValue JSON stringify | 97.06 | — | — | 1479.08 (15.24x) | 229.35 (2.36x) |
| DoubleValue JSON parse | 115.19 | — | — | 2129.51 (18.49x) | 395.16 (3.43x) |
| DoubleValue NaN JSON stringify | 53.15 | — | — | 1006.81 (18.94x) | 158.46 (2.98x) |
| DoubleValue NaN JSON parse | 103.67 | — | — | 1730.66 (16.69x) | 370.78 (3.58x) |
| DoubleValue Infinity JSON stringify | 56.69 | — | — | 973.07 (17.16x) | 152.07 (2.68x) |
| DoubleValue Infinity JSON parse | 105.03 | — | — | 1708.76 (16.27x) | 367.93 (3.50x) |
| DoubleValue NegativeInfinity JSON stringify | 58.28 | — | — | 967.36 (16.60x) | 158.70 (2.72x) |
| DoubleValue NegativeInfinity JSON parse | 108.26 | — | — | 1730.55 (15.99x) | 373.49 (3.45x) |
| FloatValue JSON stringify | 101.80 | — | — | 1409.76 (13.85x) | 212.40 (2.09x) |
| FloatValue JSON parse | 113.15 | — | — | 2127.06 (18.80x) | 359.74 (3.18x) |
| FloatValue NaN JSON stringify | 53.26 | — | — | 977.60 (18.36x) | 154.51 (2.90x) |
| FloatValue NaN JSON parse | 101.76 | — | — | 1714.99 (16.85x) | 349.05 (3.43x) |
| FloatValue Infinity JSON stringify | 57.16 | — | — | 975.53 (17.07x) | 162.46 (2.84x) |
| FloatValue Infinity JSON parse | 104.47 | — | — | 1738.27 (16.64x) | 342.46 (3.28x) |
| FloatValue NegativeInfinity JSON stringify | 57.98 | — | — | 962.91 (16.61x) | 165.26 (2.85x) |
| FloatValue NegativeInfinity JSON parse | 106.93 | — | — | 1741.64 (16.29x) | 383.30 (3.58x) |
| Int64Value JSON stringify | 45.52 | — | — | 990.92 (21.77x) | 331.40 (7.28x) |
| Int64Value JSON parse | 138.19 | — | — | 1995.19 (14.44x) | 559.50 (4.05x) |
| UInt64Value JSON stringify | 46.21 | — | — | 1017.11 (22.01x) | 329.31 (7.13x) |
| UInt64Value JSON parse | 139.14 | — | — | 1957.22 (14.07x) | 557.56 (4.01x) |
| Int32Value JSON stringify | 46.44 | — | — | 966.65 (20.82x) | 146.59 (3.16x) |
| Int32Value JSON parse | 136.47 | — | — | 1923.21 (14.09x) | 345.63 (2.53x) |
| UInt32Value JSON stringify | 47.32 | — | — | 928.78 (19.63x) | 162.92 (3.44x) |
| UInt32Value JSON parse | 136.64 | — | — | 1904.61 (13.94x) | 381.34 (2.79x) |
| BoolValue JSON stringify | 43.26 | — | — | 904.06 (20.90x) | 146.16 (3.38x) |
| BoolValue JSON parse | 59.46 | — | — | 1732.54 (29.14x) | 284.27 (4.78x) |
| StringValue JSON stringify | 54.64 | — | — | 1023.26 (18.73x) | 197.89 (3.62x) |
| StringValue JSON parse | 132.19 | — | — | 1814.25 (13.72x) | 381.84 (2.89x) |
| BytesValue JSON stringify | 45.89 | — | — | 951.47 (20.73x) | 234.68 (5.11x) |
| BytesValue JSON parse | 142.81 | — | — | 1970.33 (13.80x) | 396.96 (2.78x) |
| TextFormat parse | 848.54 | — | — | 5545.91 (6.54x) | 8158.11 (9.61x) |
| packed int32 decode | 1029.96 | 3049.72 (2.96x) | 4241.65 (4.12x) | 1341.70 (1.30x) | 4759.25 (4.62x) |
| packed bool encode | 2.51 | 2081.38 (829.24x) | 554.63 (220.97x) | 22.43 (8.94x) | 4386.45 (1747.59x) |
| packed bool decode | 271.41 | 2057.80 (7.58x) | 4483.00 (16.52x) | 1107.76 (4.08x) | 2670.44 (9.84x) |
| largebytes decode | 155.06 | 8475.95 (54.66x) | 4517.29 (29.13x) | 4106.68 (26.48x) | 23777.37 (153.34x) |
| large map decode | 37325.30 | 125778.55 (3.37x) | 121531.62 (3.26x) | 118884.00 (3.19x) | 303064.93 (8.12x) |
| shuffled large map deterministic binary encode | 37493.37 | — | — | 110185.00 (2.94x) | 458084.97 (12.22x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded positive/negative `Duration`, `Struct`, `Value`,
`FieldMask`, min/pre/post/max-bound `Timestamp`, `Empty`, `Int64Value`, `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), `UInt64Value`, `Int32Value`, `UInt32Value`, `BoolValue`, `StringValue`, `BytesValue`, and recursive nested `Any` payloads), direct positive/negative Duration and min/pre/post/max-bound Timestamp WKT JSON plus other direct WKT JSON, TextFormat, packed scalars, large bytes,
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
