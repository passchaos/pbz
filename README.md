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

Latest accepted comparison (`/tmp/pbz-compare-after-min-duration-json-isolated.log`,
summarized in `/tmp/pbz-summary-after-min-duration-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 23.81 | 125.03 (5.25x) | 64.46 (2.71x) | 131.89 (5.54x) | 950.81 (39.93x) |
| binary decode | 131.13 | 296.33 (2.26x) | 300.54 (2.29x) | 268.29 (2.05x) | 996.85 (7.60x) |
| unknown count by number | 5.10 | — | — | 212.36 (41.64x) | — |
| scalarmix encode | 27.09 | 113.95 (4.21x) | 69.47 (2.56x) | 45.23 (1.67x) | 241.48 (8.91x) |
| scalarmix decode | 50.54 | 163.47 (3.23x) | 220.89 (4.37x) | 106.68 (2.11x) | 363.70 (7.20x) |
| textbytes encode | 13.29 | 91.25 (6.87x) | 43.22 (3.25x) | 147.29 (11.08x) | 183.96 (13.84x) |
| complex decode | 225.45 | 473.23 (2.10x) | 441.41 (1.96x) | 479.67 (2.13x) | 1636.17 (7.26x) |
| complex JSON parse | 2737.92 | — | — | 16635.20 (6.08x) | 10559.11 (3.86x) |
| Any WKT JSON stringify | 180.65 | — | — | 3033.21 (16.79x) | 1383.06 (7.66x) |
| Any WKT JSON parse | 575.90 | — | — | 4568.98 (7.93x) | 2089.70 (3.63x) |
| Any NegativeDuration WKT JSON stringify | 187.44 | — | — | 3091.44 (16.49x) | 1381.91 (7.37x) |
| Any NegativeDuration WKT JSON parse | 578.36 | — | — | 4673.10 (8.08x) | 2165.22 (3.74x) |
| Any FractionalNegativeDuration WKT JSON stringify | 177.67 | — | — | 3043.10 (17.13x) | 1338.67 (7.53x) |
| Any FractionalNegativeDuration WKT JSON parse | 570.93 | — | — | 4706.23 (8.24x) | 2094.46 (3.67x) |
| Any MaxDuration WKT JSON stringify | 162.05 | — | — | 2703.59 (16.68x) | 1324.20 (8.17x) |
| Any MaxDuration WKT JSON parse | 596.99 | — | — | 4525.37 (7.58x) | 2133.66 (3.57x) |
| Any MinDuration WKT JSON stringify | 165.53 | — | — | 2724.54 (16.46x) | 1386.99 (8.38x) |
| Any MinDuration WKT JSON parse | 599.30 | — | — | 4617.56 (7.70x) | 2126.11 (3.55x) |
| Any FieldMask WKT JSON stringify | 287.45 | — | — | 2460.41 (8.56x) | 1748.60 (6.08x) |
| Any FieldMask WKT JSON parse | 797.58 | — | — | 4911.59 (6.16x) | 2895.32 (3.63x) |
| Any Timestamp WKT JSON stringify | 246.97 | — | — | 2970.93 (12.03x) | 1367.27 (5.54x) |
| Any Timestamp WKT JSON parse | 640.60 | — | — | 4716.99 (7.36x) | 2219.55 (3.46x) |
| Any PreEpoch Timestamp WKT JSON stringify | 198.99 | — | — | 2880.79 (14.48x) | 1284.90 (6.46x) |
| Any PreEpoch Timestamp WKT JSON parse | 625.73 | — | — | 4728.47 (7.56x) | 2212.67 (3.54x) |
| Any Max Timestamp WKT JSON stringify | 220.91 | — | — | 3021.76 (13.68x) | 1347.33 (6.10x) |
| Any Max Timestamp WKT JSON parse | 655.77 | — | — | 4770.30 (7.27x) | 2258.35 (3.44x) |
| Any Min Timestamp WKT JSON stringify | 230.97 | — | — | 2897.21 (12.54x) | 1272.75 (5.51x) |
| Any Min Timestamp WKT JSON parse | 622.97 | — | — | 4646.35 (7.46x) | 2188.08 (3.51x) |
| Any Empty WKT JSON stringify | 121.87 | — | — | 1280.52 (10.51x) | 720.79 (5.91x) |
| Any Empty WKT JSON parse | 377.47 | — | — | 3110.00 (8.24x) | 1644.63 (4.36x) |
| Any Struct WKT JSON stringify | 778.73 | — | — | 8982.28 (11.53x) | 8844.23 (11.36x) |
| Any Struct WKT JSON parse | 1977.67 | — | — | 16534.70 (8.36x) | 12622.84 (6.38x) |
| Any Value WKT JSON stringify | 805.26 | — | — | 9053.08 (11.24x) | 9199.72 (11.42x) |
| Any Value WKT JSON parse | 2032.32 | — | — | 16704.90 (8.22x) | 13022.84 (6.41x) |
| Any DoubleValue WKT JSON stringify | 252.82 | — | — | 2814.53 (11.13x) | 868.59 (3.44x) |
| Any DoubleValue WKT JSON parse | 578.30 | — | — | 4355.53 (7.53x) | 1922.61 (3.32x) |
| Any DoubleValue NaN WKT JSON stringify | 199.30 | — | — | 2270.13 (11.39x) | 781.67 (3.92x) |
| Any DoubleValue NaN WKT JSON parse | 573.53 | — | — | 4047.90 (7.06x) | 1882.71 (3.28x) |
| Any DoubleValue Infinity WKT JSON stringify | 205.67 | — | — | 2255.18 (10.97x) | 777.88 (3.78x) |
| Any DoubleValue Infinity WKT JSON parse | 579.22 | — | — | 4114.83 (7.10x) | 1893.49 (3.27x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 206.23 | — | — | 2245.91 (10.89x) | 772.95 (3.75x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 580.82 | — | — | 4120.61 (7.09x) | 1886.32 (3.25x) |
| Any FloatValue WKT JSON stringify | 258.67 | — | — | 2766.57 (10.70x) | 939.47 (3.63x) |
| Any FloatValue WKT JSON parse | 576.98 | — | — | 4319.52 (7.49x) | 1858.88 (3.22x) |
| Any FloatValue NaN WKT JSON stringify | 201.86 | — | — | 2236.13 (11.08x) | 770.17 (3.82x) |
| Any FloatValue NaN WKT JSON parse | 572.13 | — | — | 4045.82 (7.07x) | 1847.81 (3.23x) |
| Any FloatValue Infinity WKT JSON stringify | 207.42 | — | — | 2183.98 (10.53x) | 786.16 (3.79x) |
| Any FloatValue Infinity WKT JSON parse | 576.58 | — | — | 4013.66 (6.96x) | 1834.91 (3.18x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 208.77 | — | — | 2159.75 (10.35x) | 779.61 (3.73x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 579.16 | — | — | 3996.69 (6.90x) | 1849.93 (3.19x) |
| Any Int64Value WKT JSON stringify | 207.16 | — | — | 2193.73 (10.59x) | 1130.12 (5.46x) |
| Any Int64Value WKT JSON parse | 623.57 | — | — | 4312.77 (6.92x) | 2353.52 (3.77x) |
| Any UInt64Value WKT JSON stringify | 218.32 | — | — | 2149.44 (9.85x) | 1135.15 (5.20x) |
| Any UInt64Value WKT JSON parse | 630.83 | — | — | 4311.67 (6.83x) | 2230.39 (3.54x) |
| Any Int32Value WKT JSON stringify | 209.63 | — | — | 2196.35 (10.48x) | 901.98 (4.30x) |
| Any Int32Value WKT JSON parse | 594.67 | — | — | 4157.75 (6.99x) | 1957.71 (3.29x) |
| Any UInt32Value WKT JSON stringify | 218.61 | — | — | 2159.14 (9.88x) | 898.61 (4.11x) |
| Any UInt32Value WKT JSON parse | 600.34 | — | — | 4154.56 (6.92x) | 2026.92 (3.38x) |
| Any BoolValue WKT JSON stringify | 211.03 | — | — | 2153.18 (10.20x) | 779.09 (3.69x) |
| Any BoolValue WKT JSON parse | 557.89 | — | — | 4005.43 (7.18x) | 1747.66 (3.13x) |
| Any StringValue WKT JSON stringify | 245.37 | — | — | 2227.22 (9.08x) | 882.63 (3.60x) |
| Any StringValue WKT JSON parse | 612.51 | — | — | 4075.47 (6.65x) | 1951.03 (3.19x) |
| Any BytesValue WKT JSON stringify | 224.46 | — | — | 2299.85 (10.25x) | 923.10 (4.11x) |
| Any BytesValue WKT JSON parse | 619.35 | — | — | 4244.69 (6.85x) | 1965.70 (3.17x) |
| Nested Any WKT JSON stringify | 386.41 | — | — | 3382.12 (8.75x) | 1604.12 (4.15x) |
| Nested Any WKT JSON parse | 997.67 | — | — | 6113.63 (6.13x) | 3614.67 (3.62x) |
| Duration JSON stringify | 65.19 | — | — | 1536.13 (23.56x) | 387.90 (5.95x) |
| Duration JSON parse | 11.04 | — | — | 2263.86 (205.06x) | 425.15 (38.51x) |
| NegativeDuration JSON stringify | 65.49 | — | — | 1606.31 (24.53x) | 448.34 (6.85x) |
| NegativeDuration JSON parse | 11.30 | — | — | 2354.32 (208.35x) | 434.42 (38.44x) |
| FractionalNegativeDuration JSON stringify | 65.49 | — | — | 1559.93 (23.82x) | 450.92 (6.89x) |
| FractionalNegativeDuration JSON parse | 11.29 | — | — | 2276.41 (201.63x) | 420.48 (37.24x) |
| MaxDuration JSON stringify | 54.48 | — | — | 1283.01 (23.55x) | 436.30 (8.01x) |
| MaxDuration JSON parse | 29.22 | — | — | 2190.39 (74.96x) | 446.83 (15.29x) |
| MinDuration JSON stringify | 54.76 | — | — | 1269.09 (23.18x) | 457.88 (8.36x) |
| MinDuration JSON parse | 29.39 | — | — | 2214.40 (75.35x) | 436.94 (14.87x) |
| FieldMask JSON stringify | 92.83 | — | — | 1271.48 (13.70x) | 722.09 (7.78x) |
| FieldMask JSON parse | 181.07 | — | — | 2646.41 (14.62x) | 1051.35 (5.81x) |
| Timestamp JSON stringify | 128.84 | — | — | 1705.75 (13.24x) | 464.75 (3.61x) |
| Timestamp JSON parse | 56.73 | — | — | 2298.84 (40.52x) | 477.93 (8.42x) |
| PreEpoch Timestamp JSON stringify | 85.49 | — | — | 1569.41 (18.36x) | 453.50 (5.30x) |
| PreEpoch Timestamp JSON parse | 54.71 | — | — | 2279.06 (41.66x) | 458.09 (8.37x) |
| Max Timestamp JSON stringify | 104.49 | — | — | 1740.61 (16.66x) | 468.73 (4.49x) |
| Max Timestamp JSON parse | 64.29 | — | — | 2330.88 (36.26x) | 488.66 (7.60x) |
| Min Timestamp JSON stringify | 118.53 | — | — | 1577.78 (13.31x) | 456.43 (3.85x) |
| Min Timestamp JSON parse | 52.67 | — | — | 2214.43 (42.04x) | 457.59 (8.69x) |
| Empty JSON stringify | 22.58 | — | — | 669.46 (29.65x) | 94.44 (4.18x) |
| Empty JSON parse | 74.43 | — | — | 1112.17 (14.94x) | 244.37 (3.28x) |
| Struct JSON stringify | 267.90 | — | — | 8954.90 (33.43x) | 4138.98 (15.45x) |
| Struct JSON parse | 941.39 | — | — | 16694.20 (17.73x) | 6334.71 (6.73x) |
| Value JSON stringify | 273.28 | — | — | 9826.92 (35.96x) | 4338.07 (15.87x) |
| Value JSON parse | 946.56 | — | — | 17506.30 (18.49x) | 6629.09 (7.00x) |
| ListValue JSON stringify | 200.09 | — | — | 7590.90 (37.94x) | 2838.02 (14.18x) |
| ListValue JSON parse | 742.75 | — | — | 13581.90 (18.29x) | 5224.18 (7.03x) |
| DoubleValue JSON stringify | 97.25 | — | — | 1457.03 (14.98x) | 192.37 (1.98x) |
| DoubleValue JSON parse | 113.37 | — | — | 2113.42 (18.64x) | 323.89 (2.86x) |
| DoubleValue NaN JSON stringify | 52.70 | — | — | 973.59 (18.47x) | 143.75 (2.73x) |
| DoubleValue NaN JSON parse | 101.71 | — | — | 1729.36 (17.00x) | 311.55 (3.06x) |
| DoubleValue Infinity JSON stringify | 56.17 | — | — | 1000.06 (17.80x) | 133.00 (2.37x) |
| DoubleValue Infinity JSON parse | 104.27 | — | — | 1743.84 (16.72x) | 318.57 (3.06x) |
| DoubleValue NegativeInfinity JSON stringify | 57.46 | — | — | 1004.71 (17.49x) | 139.25 (2.42x) |
| DoubleValue NegativeInfinity JSON parse | 107.58 | — | — | 1772.84 (16.48x) | 340.29 (3.16x) |
| FloatValue JSON stringify | 101.45 | — | — | 1393.39 (13.73x) | 200.53 (1.98x) |
| FloatValue JSON parse | 113.33 | — | — | 2153.16 (19.00x) | 306.45 (2.70x) |
| FloatValue NaN JSON stringify | 52.29 | — | — | 968.74 (18.53x) | 135.42 (2.59x) |
| FloatValue NaN JSON parse | 102.62 | — | — | 1740.70 (16.96x) | 298.41 (2.91x) |
| FloatValue Infinity JSON stringify | 56.08 | — | — | 947.54 (16.90x) | 137.12 (2.45x) |
| FloatValue Infinity JSON parse | 104.77 | — | — | 1756.82 (16.77x) | 327.94 (3.13x) |
| FloatValue NegativeInfinity JSON stringify | 57.43 | — | — | 946.37 (16.48x) | 144.45 (2.52x) |
| FloatValue NegativeInfinity JSON parse | 108.00 | — | — | 1747.99 (16.19x) | 327.97 (3.04x) |
| Int64Value JSON stringify | 41.87 | — | — | 1001.76 (23.93x) | 295.76 (7.06x) |
| Int64Value JSON parse | 139.08 | — | — | 1976.79 (14.21x) | 515.82 (3.71x) |
| UInt64Value JSON stringify | 41.98 | — | — | 988.85 (23.56x) | 297.17 (7.08x) |
| UInt64Value JSON parse | 137.55 | — | — | 1970.38 (14.32x) | 509.83 (3.71x) |
| Int32Value JSON stringify | 45.76 | — | — | 958.27 (20.94x) | 142.55 (3.12x) |
| Int32Value JSON parse | 130.15 | — | — | 1921.17 (14.76x) | 337.78 (2.60x) |
| UInt32Value JSON stringify | 45.61 | — | — | 928.89 (20.37x) | 162.49 (3.56x) |
| UInt32Value JSON parse | 130.09 | — | — | 1930.89 (14.84x) | 359.90 (2.77x) |
| BoolValue JSON stringify | 42.09 | — | — | 898.12 (21.34x) | 130.14 (3.09x) |
| BoolValue JSON parse | 59.08 | — | — | 1700.60 (28.78x) | 256.55 (4.34x) |
| StringValue JSON stringify | 54.10 | — | — | 1011.80 (18.70x) | 192.84 (3.56x) |
| StringValue JSON parse | 130.47 | — | — | 1841.33 (14.11x) | 360.01 (2.76x) |
| BytesValue JSON stringify | 47.69 | — | — | 966.98 (20.28x) | 226.93 (4.76x) |
| BytesValue JSON parse | 143.13 | — | — | 1972.98 (13.78x) | 372.81 (2.60x) |
| TextFormat parse | 851.73 | — | — | 5656.97 (6.64x) | 8046.19 (9.45x) |
| packed int32 decode | 1030.85 | 2980.46 (2.89x) | 4252.27 (4.13x) | 1448.21 (1.40x) | 4365.98 (4.24x) |
| packed bool encode | 2.51 | 2080.23 (828.78x) | 540.65 (215.40x) | 22.68 (9.04x) | 4386.86 (1747.75x) |
| packed bool decode | 272.07 | 2308.49 (8.48x) | 3850.80 (14.15x) | 1108.07 (4.07x) | 2644.94 (9.72x) |
| largebytes decode | 124.92 | 8515.93 (68.17x) | 4556.52 (36.48x) | 4062.52 (32.52x) | 24049.75 (192.52x) |
| large map decode | 37565.09 | 128928.77 (3.43x) | 119480.70 (3.18x) | 118102.00 (3.14x) | 294447.22 (7.84x) |
| shuffled large map deterministic binary encode | 36238.43 | — | — | 110573.00 (3.05x) | 453626.61 (12.52x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded positive/integer-negative/fractional-negative/min-max-bound `Duration`, `Struct`, `Value`,
`FieldMask`, min/pre/post/max-bound `Timestamp`, `Empty`, `Int64Value`, `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), `UInt64Value`, `Int32Value`, `UInt32Value`, `BoolValue`, `StringValue`, `BytesValue`, and recursive nested `Any` payloads), direct positive/integer-negative/fractional-negative/min-max-bound Duration and min/pre/post/max-bound Timestamp WKT JSON plus other direct WKT JSON, TextFormat, packed scalars, large bytes,
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
