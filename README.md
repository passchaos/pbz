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

Latest accepted comparison (`/tmp/pbz-compare-after-zero-duration-json-isolated.log`,
summarized in `/tmp/pbz-summary-after-zero-duration-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 26.57 | 128.50 (4.84x) | 63.80 (2.40x) | 126.95 (4.78x) | 951.37 (35.81x) |
| binary decode | 131.41 | 304.87 (2.32x) | 310.47 (2.36x) | 268.59 (2.04x) | 986.16 (7.50x) |
| unknown count by number | 5.02 | — | — | 175.48 (34.96x) | — |
| scalarmix encode | 26.47 | 115.50 (4.36x) | 69.42 (2.62x) | 45.74 (1.73x) | 239.29 (9.04x) |
| scalarmix decode | 56.01 | 163.52 (2.92x) | 209.73 (3.74x) | 112.89 (2.02x) | 356.94 (6.37x) |
| textbytes encode | 11.78 | 91.74 (7.79x) | 43.91 (3.73x) | 146.81 (12.46x) | 169.65 (14.40x) |
| complex decode | 217.43 | 464.52 (2.14x) | 441.50 (2.03x) | 482.71 (2.22x) | 1635.65 (7.52x) |
| complex JSON parse | 2750.25 | — | — | 16725.00 (6.08x) | 10535.81 (3.83x) |
| Any WKT JSON stringify | 169.25 | — | — | 3062.81 (18.10x) | 1367.22 (8.08x) |
| Any WKT JSON parse | 570.53 | — | — | 4609.98 (8.08x) | 2056.07 (3.60x) |
| Any NegativeDuration WKT JSON stringify | 182.05 | — | — | 3082.27 (16.93x) | 1373.02 (7.54x) |
| Any NegativeDuration WKT JSON parse | 577.16 | — | — | 4694.44 (8.13x) | 2164.21 (3.75x) |
| Any FractionalNegativeDuration WKT JSON stringify | 164.83 | — | — | 3042.14 (18.46x) | 1342.50 (8.14x) |
| Any FractionalNegativeDuration WKT JSON parse | 567.15 | — | — | 4666.66 (8.23x) | 2096.64 (3.70x) |
| Any MaxDuration WKT JSON stringify | 150.41 | — | — | 2706.73 (18.00x) | 1319.47 (8.77x) |
| Any MaxDuration WKT JSON parse | 593.88 | — | — | 4490.05 (7.56x) | 2117.83 (3.57x) |
| Any MinDuration WKT JSON stringify | 153.35 | — | — | 2727.97 (17.79x) | 1358.56 (8.86x) |
| Any MinDuration WKT JSON parse | 595.72 | — | — | 4604.59 (7.73x) | 2122.67 (3.56x) |
| Any ZeroDuration WKT JSON stringify | 135.92 | — | — | 1297.33 (9.54x) | 1237.37 (9.10x) |
| Any ZeroDuration WKT JSON parse | 521.91 | — | — | 3315.94 (6.35x) | 1897.78 (3.64x) |
| Any FieldMask WKT JSON stringify | 275.67 | — | — | 2417.97 (8.77x) | 1737.90 (6.30x) |
| Any FieldMask WKT JSON parse | 788.76 | — | — | 4882.88 (6.19x) | 2913.50 (3.69x) |
| Any Timestamp WKT JSON stringify | 236.92 | — | — | 3040.27 (12.83x) | 1334.60 (5.63x) |
| Any Timestamp WKT JSON parse | 639.63 | — | — | 4609.23 (7.21x) | 2197.53 (3.44x) |
| Any PreEpoch Timestamp WKT JSON stringify | 185.16 | — | — | 2919.11 (15.77x) | 1265.68 (6.84x) |
| Any PreEpoch Timestamp WKT JSON parse | 622.40 | — | — | 4642.19 (7.46x) | 2227.44 (3.58x) |
| Any Max Timestamp WKT JSON stringify | 211.83 | — | — | 3008.54 (14.20x) | 1328.85 (6.27x) |
| Any Max Timestamp WKT JSON parse | 654.52 | — | — | 4660.11 (7.12x) | 2241.33 (3.42x) |
| Any Min Timestamp WKT JSON stringify | 217.90 | — | — | 2877.26 (13.20x) | 1267.37 (5.82x) |
| Any Min Timestamp WKT JSON parse | 619.31 | — | — | 4579.48 (7.39x) | 2181.87 (3.52x) |
| Any Empty WKT JSON stringify | 114.79 | — | — | 1302.70 (11.35x) | 720.09 (6.27x) |
| Any Empty WKT JSON parse | 372.60 | — | — | 3076.82 (8.26x) | 1683.72 (4.52x) |
| Any Struct WKT JSON stringify | 759.28 | — | — | 9035.12 (11.90x) | 8860.76 (11.67x) |
| Any Struct WKT JSON parse | 1947.19 | — | — | 17120.60 (8.79x) | 12475.60 (6.41x) |
| Any Value WKT JSON stringify | 795.97 | — | — | 9082.15 (11.41x) | 9300.17 (11.68x) |
| Any Value WKT JSON parse | 2012.57 | — | — | 16799.80 (8.35x) | 12898.52 (6.41x) |
| Any DoubleValue WKT JSON stringify | 240.89 | — | — | 2829.96 (11.75x) | 880.46 (3.66x) |
| Any DoubleValue WKT JSON parse | 573.87 | — | — | 4443.67 (7.74x) | 1900.35 (3.31x) |
| Any DoubleValue NaN WKT JSON stringify | 184.35 | — | — | 2272.90 (12.33x) | 780.82 (4.24x) |
| Any DoubleValue NaN WKT JSON parse | 568.73 | — | — | 4096.30 (7.20x) | 1866.69 (3.28x) |
| Any DoubleValue Infinity WKT JSON stringify | 190.51 | — | — | 2252.06 (11.82x) | 777.85 (4.08x) |
| Any DoubleValue Infinity WKT JSON parse | 573.68 | — | — | 4097.98 (7.14x) | 1876.91 (3.27x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 189.17 | — | — | 2240.29 (11.84x) | 778.46 (4.12x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 578.66 | — | — | 4148.21 (7.17x) | 1851.53 (3.20x) |
| Any FloatValue WKT JSON stringify | 246.99 | — | — | 2725.22 (11.03x) | 945.58 (3.83x) |
| Any FloatValue WKT JSON parse | 571.37 | — | — | 4349.58 (7.61x) | 1898.97 (3.32x) |
| Any FloatValue NaN WKT JSON stringify | 186.58 | — | — | 2245.05 (12.03x) | 791.55 (4.24x) |
| Any FloatValue NaN WKT JSON parse | 568.40 | — | — | 4039.16 (7.11x) | 1795.06 (3.16x) |
| Any FloatValue Infinity WKT JSON stringify | 189.75 | — | — | 2190.85 (11.55x) | 769.96 (4.06x) |
| Any FloatValue Infinity WKT JSON parse | 572.73 | — | — | 4092.61 (7.15x) | 1820.35 (3.18x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 190.71 | — | — | 2204.55 (11.56x) | 779.45 (4.09x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 575.74 | — | — | 4110.19 (7.14x) | 1826.54 (3.17x) |
| Any Int64Value WKT JSON stringify | 198.75 | — | — | 2199.82 (11.07x) | 1401.68 (7.05x) |
| Any Int64Value WKT JSON parse | 619.57 | — | — | 4329.74 (6.99x) | 2601.38 (4.20x) |
| Any UInt64Value WKT JSON stringify | 209.34 | — | — | 2198.36 (10.50x) | 1706.55 (8.15x) |
| Any UInt64Value WKT JSON parse | 626.10 | — | — | 4359.91 (6.96x) | 2697.58 (4.31x) |
| Any Int32Value WKT JSON stringify | 201.51 | — | — | 2235.18 (11.09x) | 993.46 (4.93x) |
| Any Int32Value WKT JSON parse | 595.88 | — | — | 4190.31 (7.03x) | 2185.25 (3.67x) |
| Any UInt32Value WKT JSON stringify | 209.97 | — | — | 2191.68 (10.44x) | 966.51 (4.60x) |
| Any UInt32Value WKT JSON parse | 601.64 | — | — | 4082.47 (6.79x) | 2209.34 (3.67x) |
| Any BoolValue WKT JSON stringify | 208.11 | — | — | 2153.75 (10.35x) | 835.58 (4.02x) |
| Any BoolValue WKT JSON parse | 542.70 | — | — | 4028.16 (7.42x) | 1696.49 (3.13x) |
| Any StringValue WKT JSON stringify | 232.05 | — | — | 2262.28 (9.75x) | 926.96 (3.99x) |
| Any StringValue WKT JSON parse | 609.03 | — | — | 4135.78 (6.79x) | 1893.14 (3.11x) |
| Any BytesValue WKT JSON stringify | 223.71 | — | — | 2302.30 (10.29x) | 976.47 (4.36x) |
| Any BytesValue WKT JSON parse | 617.26 | — | — | 4271.76 (6.92x) | 1958.35 (3.17x) |
| Nested Any WKT JSON stringify | 351.41 | — | — | 3393.96 (9.66x) | 1576.78 (4.49x) |
| Nested Any WKT JSON parse | 990.07 | — | — | 6100.41 (6.16x) | 3570.37 (3.61x) |
| Duration JSON stringify | 65.05 | — | — | 1512.73 (23.25x) | 394.93 (6.07x) |
| Duration JSON parse | 11.78 | — | — | 2281.49 (193.67x) | 418.13 (35.49x) |
| NegativeDuration JSON stringify | 65.47 | — | — | 1608.59 (24.57x) | 448.58 (6.85x) |
| NegativeDuration JSON parse | 12.30 | — | — | 2371.18 (192.78x) | 430.53 (35.00x) |
| FractionalNegativeDuration JSON stringify | 65.42 | — | — | 1549.41 (23.68x) | 449.21 (6.87x) |
| FractionalNegativeDuration JSON parse | 12.28 | — | — | 2291.71 (186.62x) | 415.91 (33.87x) |
| MaxDuration JSON stringify | 53.99 | — | — | 1247.28 (23.10x) | 433.16 (8.02x) |
| MaxDuration JSON parse | 29.18 | — | — | 2221.53 (76.13x) | 441.12 (15.12x) |
| MinDuration JSON stringify | 54.14 | — | — | 1303.52 (24.08x) | 468.83 (8.66x) |
| MinDuration JSON parse | 29.43 | — | — | 2236.18 (75.98x) | 436.78 (14.84x) |
| ZeroDuration JSON stringify | 48.63 | — | — | 1256.13 (25.83x) | 338.11 (6.95x) |
| ZeroDuration JSON parse | 8.78 | — | — | 2123.49 (241.86x) | 360.20 (41.03x) |
| FieldMask JSON stringify | 92.19 | — | — | 1300.44 (14.11x) | 734.16 (7.96x) |
| FieldMask JSON parse | 176.80 | — | — | 2640.12 (14.93x) | 1026.35 (5.81x) |
| Timestamp JSON stringify | 129.29 | — | — | 1715.59 (13.27x) | 461.94 (3.57x) |
| Timestamp JSON parse | 57.42 | — | — | 2346.44 (40.86x) | 481.74 (8.39x) |
| PreEpoch Timestamp JSON stringify | 86.95 | — | — | 1596.87 (18.37x) | 456.71 (5.25x) |
| PreEpoch Timestamp JSON parse | 54.80 | — | — | 2296.50 (41.91x) | 456.14 (8.32x) |
| Max Timestamp JSON stringify | 104.60 | — | — | 1721.51 (16.46x) | 464.55 (4.44x) |
| Max Timestamp JSON parse | 65.18 | — | — | 2378.69 (36.49x) | 495.29 (7.60x) |
| Min Timestamp JSON stringify | 118.51 | — | — | 1606.02 (13.55x) | 452.17 (3.82x) |
| Min Timestamp JSON parse | 52.77 | — | — | 2288.46 (43.37x) | 455.63 (8.63x) |
| Empty JSON stringify | 22.47 | — | — | 707.24 (31.47x) | 105.70 (4.70x) |
| Empty JSON parse | 74.18 | — | — | 1120.39 (15.10x) | 243.74 (3.29x) |
| Struct JSON stringify | 260.40 | — | — | 8960.66 (34.41x) | 4206.99 (16.16x) |
| Struct JSON parse | 956.58 | — | — | 16836.80 (17.60x) | 6380.50 (6.67x) |
| Value JSON stringify | 263.83 | — | — | 9868.72 (37.41x) | 4370.49 (16.57x) |
| Value JSON parse | 951.67 | — | — | 17758.20 (18.66x) | 6726.40 (7.07x) |
| ListValue JSON stringify | 194.18 | — | — | 7477.55 (38.51x) | 2843.42 (14.64x) |
| ListValue JSON parse | 754.93 | — | — | 13497.50 (17.88x) | 5241.69 (6.94x) |
| DoubleValue JSON stringify | 98.40 | — | — | 1490.89 (15.15x) | 202.49 (2.06x) |
| DoubleValue JSON parse | 117.29 | — | — | 2122.13 (18.09x) | 332.44 (2.83x) |
| DoubleValue NaN JSON stringify | 52.91 | — | — | 1002.72 (18.95x) | 143.62 (2.71x) |
| DoubleValue NaN JSON parse | 104.14 | — | — | 1740.11 (16.71x) | 318.49 (3.06x) |
| DoubleValue Infinity JSON stringify | 56.53 | — | — | 966.28 (17.09x) | 135.99 (2.41x) |
| DoubleValue Infinity JSON parse | 107.39 | — | — | 1750.25 (16.30x) | 309.78 (2.88x) |
| DoubleValue NegativeInfinity JSON stringify | 57.83 | — | — | 988.45 (17.09x) | 138.51 (2.40x) |
| DoubleValue NegativeInfinity JSON parse | 111.00 | — | — | 1740.85 (15.68x) | 335.30 (3.02x) |
| FloatValue JSON stringify | 101.97 | — | — | 1384.85 (13.58x) | 199.26 (1.95x) |
| FloatValue JSON parse | 117.21 | — | — | 2119.70 (18.08x) | 313.81 (2.68x) |
| FloatValue NaN JSON stringify | 53.24 | — | — | 968.66 (18.19x) | 138.75 (2.61x) |
| FloatValue NaN JSON parse | 105.47 | — | — | 1703.29 (16.15x) | 300.59 (2.85x) |
| FloatValue Infinity JSON stringify | 56.37 | — | — | 958.06 (17.00x) | 146.66 (2.60x) |
| FloatValue Infinity JSON parse | 108.08 | — | — | 1729.14 (16.00x) | 302.37 (2.80x) |
| FloatValue NegativeInfinity JSON stringify | 57.65 | — | — | 947.76 (16.44x) | 143.58 (2.49x) |
| FloatValue NegativeInfinity JSON parse | 110.46 | — | — | 1735.90 (15.72x) | 315.05 (2.85x) |
| Int64Value JSON stringify | 41.83 | — | — | 1008.81 (24.12x) | 304.23 (7.27x) |
| Int64Value JSON parse | 136.98 | — | — | 2006.04 (14.64x) | 582.02 (4.25x) |
| UInt64Value JSON stringify | 41.93 | — | — | 998.18 (23.81x) | 570.07 (13.60x) |
| UInt64Value JSON parse | 137.01 | — | — | 1980.50 (14.46x) | 1039.32 (7.59x) |
| Int32Value JSON stringify | 45.72 | — | — | 953.29 (20.85x) | 251.28 (5.50x) |
| Int32Value JSON parse | 133.56 | — | — | 1922.74 (14.40x) | 382.63 (2.86x) |
| UInt32Value JSON stringify | 45.52 | — | — | 915.86 (20.12x) | 307.73 (6.76x) |
| UInt32Value JSON parse | 133.56 | — | — | 1884.95 (14.11x) | 771.38 (5.78x) |
| BoolValue JSON stringify | 43.56 | — | — | 909.13 (20.87x) | 154.82 (3.55x) |
| BoolValue JSON parse | 55.10 | — | — | 1685.92 (30.60x) | 299.43 (5.43x) |
| StringValue JSON stringify | 55.42 | — | — | 1018.38 (18.38x) | 210.02 (3.79x) |
| StringValue JSON parse | 131.96 | — | — | 1817.57 (13.77x) | 367.43 (2.78x) |
| BytesValue JSON stringify | 47.47 | — | — | 970.17 (20.44x) | 242.65 (5.11x) |
| BytesValue JSON parse | 137.94 | — | — | 1949.99 (14.14x) | 438.28 (3.18x) |
| TextFormat parse | 862.33 | — | — | 5459.05 (6.33x) | 8386.53 (9.73x) |
| packed int32 decode | 995.56 | 2986.36 (3.00x) | 4450.49 (4.47x) | 1340.92 (1.35x) | 4378.17 (4.40x) |
| packed bool encode | 2.76 | 2081.19 (754.05x) | 539.73 (195.55x) | 25.64 (9.29x) | 4388.80 (1590.14x) |
| packed bool decode | 271.29 | 2055.36 (7.58x) | 4036.59 (14.88x) | 1107.63 (4.08x) | 2662.68 (9.81x) |
| largebytes decode | 122.78 | 8432.75 (68.68x) | 4545.49 (37.02x) | 4304.68 (35.06x) | 23902.07 (194.67x) |
| large map decode | 38769.26 | 118470.39 (3.06x) | 116987.90 (3.02x) | 117502.00 (3.03x) | 293447.13 (7.57x) |
| shuffled large map deterministic binary encode | 36107.25 | — | — | 112779.00 (3.12x) | 456839.49 (12.65x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded zero/positive/integer-negative/fractional-negative/min-max-bound `Duration`, `Struct`, `Value`,
`FieldMask`, min/pre/post/max-bound `Timestamp`, `Empty`, `Int64Value`, `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), `UInt64Value`, `Int32Value`, `UInt32Value`, `BoolValue`, `StringValue`, `BytesValue`, and recursive nested `Any` payloads), direct zero/positive/integer-negative/fractional-negative/min-max-bound Duration and min/pre/post/max-bound Timestamp WKT JSON plus other direct WKT JSON, TextFormat, packed scalars, large bytes,
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
