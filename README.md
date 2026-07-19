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

Latest accepted comparison (`/tmp/pbz-compare-after-negative-signed-wrapper-json-isolated.log`,
summarized in `/tmp/pbz-summary-after-negative-signed-wrapper-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 28.92 | 124.71 (4.31x) | 62.63 (2.17x) | 130.65 (4.52x) | 955.59 (33.04x) |
| binary decode | 139.19 | 296.61 (2.13x) | 313.67 (2.25x) | 270.65 (1.94x) | 993.17 (7.14x) |
| unknown count by number | 5.00 | — | — | 175.42 (35.08x) | — |
| scalarmix encode | 27.49 | 116.56 (4.24x) | 69.59 (2.53x) | 45.76 (1.66x) | 237.37 (8.63x) |
| scalarmix decode | 59.28 | 162.06 (2.73x) | 223.77 (3.77x) | 113.66 (1.92x) | 366.63 (6.18x) |
| textbytes encode | 13.54 | 92.52 (6.83x) | 43.12 (3.18x) | 146.74 (10.84x) | 169.86 (12.55x) |
| complex decode | 216.81 | 461.88 (2.13x) | 430.06 (1.98x) | 484.34 (2.23x) | 1609.47 (7.42x) |
| complex JSON parse | 2756.92 | — | — | 16765.20 (6.08x) | 10543.05 (3.82x) |
| Any WKT JSON stringify | 168.37 | — | — | 3026.71 (17.98x) | 1375.73 (8.17x) |
| Any WKT JSON parse | 570.35 | — | — | 4593.96 (8.05x) | 2099.78 (3.68x) |
| Any NegativeDuration WKT JSON stringify | 175.53 | — | — | 3057.56 (17.42x) | 1406.44 (8.01x) |
| Any NegativeDuration WKT JSON parse | 567.59 | — | — | 4724.92 (8.32x) | 2158.93 (3.80x) |
| Any FractionalNegativeDuration WKT JSON stringify | 165.40 | — | — | 2963.43 (17.92x) | 1366.56 (8.26x) |
| Any FractionalNegativeDuration WKT JSON parse | 559.99 | — | — | 4642.47 (8.29x) | 2113.00 (3.77x) |
| Any MaxDuration WKT JSON stringify | 151.03 | — | — | 2658.68 (17.60x) | 1330.61 (8.81x) |
| Any MaxDuration WKT JSON parse | 588.07 | — | — | 4549.44 (7.74x) | 2148.77 (3.65x) |
| Any MinDuration WKT JSON stringify | 153.29 | — | — | 2692.74 (17.57x) | 1412.74 (9.22x) |
| Any MinDuration WKT JSON parse | 589.73 | — | — | 4614.47 (7.82x) | 2126.87 (3.61x) |
| Any ZeroDuration WKT JSON stringify | 136.50 | — | — | 1266.00 (9.27x) | 1250.37 (9.16x) |
| Any ZeroDuration WKT JSON parse | 516.47 | — | — | 3319.66 (6.43x) | 1930.79 (3.74x) |
| Any FieldMask WKT JSON stringify | 273.31 | — | — | 2440.21 (8.93x) | 1754.05 (6.42x) |
| Any FieldMask WKT JSON parse | 782.43 | — | — | 4906.02 (6.27x) | 2969.42 (3.80x) |
| Any Timestamp WKT JSON stringify | 235.92 | — | — | 2968.92 (12.58x) | 1374.19 (5.82x) |
| Any Timestamp WKT JSON parse | 633.42 | — | — | 4652.15 (7.34x) | 2260.27 (3.57x) |
| Any PreEpoch Timestamp WKT JSON stringify | 184.91 | — | — | 2856.42 (15.45x) | 1278.29 (6.91x) |
| Any PreEpoch Timestamp WKT JSON parse | 617.54 | — | — | 4662.66 (7.55x) | 2195.79 (3.56x) |
| Any Max Timestamp WKT JSON stringify | 208.56 | — | — | 2998.52 (14.38x) | 1335.40 (6.40x) |
| Any Max Timestamp WKT JSON parse | 650.72 | — | — | 4737.93 (7.28x) | 2266.42 (3.48x) |
| Any Min Timestamp WKT JSON stringify | 217.49 | — | — | 2860.74 (13.15x) | 1268.07 (5.83x) |
| Any Min Timestamp WKT JSON parse | 613.67 | — | — | 4624.87 (7.54x) | 2231.50 (3.64x) |
| Any Empty WKT JSON stringify | 115.01 | — | — | 1288.73 (11.21x) | 762.29 (6.63x) |
| Any Empty WKT JSON parse | 371.30 | — | — | 3176.59 (8.56x) | 1755.77 (4.73x) |
| Any Struct WKT JSON stringify | 770.31 | — | — | 9041.85 (11.74x) | 9116.77 (11.84x) |
| Any Struct WKT JSON parse | 1964.28 | — | — | 16960.90 (8.63x) | 12731.34 (6.48x) |
| Any Value WKT JSON stringify | 790.19 | — | — | 8972.06 (11.35x) | 9348.58 (11.83x) |
| Any Value WKT JSON parse | 2032.25 | — | — | 16743.10 (8.24x) | 13151.44 (6.47x) |
| Any DoubleValue WKT JSON stringify | 239.44 | — | — | 2843.84 (11.88x) | 908.99 (3.80x) |
| Any DoubleValue WKT JSON parse | 563.71 | — | — | 4371.11 (7.75x) | 1994.08 (3.54x) |
| Any DoubleValue NaN WKT JSON stringify | 182.41 | — | — | 2306.66 (12.65x) | 786.07 (4.31x) |
| Any DoubleValue NaN WKT JSON parse | 562.70 | — | — | 4075.83 (7.24x) | 1873.08 (3.33x) |
| Any DoubleValue Infinity WKT JSON stringify | 187.48 | — | — | 2274.80 (12.13x) | 782.80 (4.18x) |
| Any DoubleValue Infinity WKT JSON parse | 567.40 | — | — | 4182.31 (7.37x) | 1894.57 (3.34x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 188.27 | — | — | 2284.10 (12.13x) | 797.81 (4.24x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 572.37 | — | — | 4022.69 (7.03x) | 1917.06 (3.35x) |
| Any FloatValue WKT JSON stringify | 246.33 | — | — | 2818.04 (11.44x) | 925.33 (3.76x) |
| Any FloatValue WKT JSON parse | 564.40 | — | — | 4377.63 (7.76x) | 1907.02 (3.38x) |
| Any FloatValue NaN WKT JSON stringify | 186.04 | — | — | 2254.15 (12.12x) | 788.56 (4.24x) |
| Any FloatValue NaN WKT JSON parse | 561.91 | — | — | 4064.88 (7.23x) | 1844.18 (3.28x) |
| Any FloatValue Infinity WKT JSON stringify | 189.10 | — | — | 2192.42 (11.59x) | 806.43 (4.26x) |
| Any FloatValue Infinity WKT JSON parse | 566.10 | — | — | 4071.69 (7.19x) | 1916.98 (3.39x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 190.10 | — | — | 2201.02 (11.58x) | 795.14 (4.18x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 571.01 | — | — | 4096.35 (7.17x) | 1891.47 (3.31x) |
| Any Int64Value WKT JSON stringify | 198.26 | — | — | 2190.86 (11.05x) | 1124.68 (5.67x) |
| Any Int64Value WKT JSON parse | 613.73 | — | — | 4324.88 (7.05x) | 2356.56 (3.84x) |
| Any NegativeInt64Value WKT JSON stringify | 199.37 | — | — | 2197.26 (11.02x) | 1134.51 (5.69x) |
| Any NegativeInt64Value WKT JSON parse | 610.72 | — | — | 4323.20 (7.08x) | 2458.21 (4.03x) |
| Any UInt64Value WKT JSON stringify | 207.59 | — | — | 2211.40 (10.65x) | 1135.24 (5.47x) |
| Any UInt64Value WKT JSON parse | 620.61 | — | — | 4312.86 (6.95x) | 2296.11 (3.70x) |
| Any Int32Value WKT JSON stringify | 200.73 | — | — | 2213.25 (11.03x) | 897.91 (4.47x) |
| Any Int32Value WKT JSON parse | 587.84 | — | — | 4135.35 (7.03x) | 2023.63 (3.44x) |
| Any NegativeInt32Value WKT JSON stringify | 204.56 | — | — | 2198.03 (10.75x) | 898.01 (4.39x) |
| Any NegativeInt32Value WKT JSON parse | 585.79 | — | — | 4148.06 (7.08x) | 2054.41 (3.51x) |
| Any UInt32Value WKT JSON stringify | 209.85 | — | — | 2183.26 (10.40x) | 830.84 (3.96x) |
| Any UInt32Value WKT JSON parse | 593.93 | — | — | 4180.07 (7.04x) | 1997.11 (3.36x) |
| Any BoolValue WKT JSON stringify | 203.57 | — | — | 2139.67 (10.51x) | 815.24 (4.00x) |
| Any BoolValue WKT JSON parse | 538.41 | — | — | 4000.43 (7.43x) | 1716.27 (3.19x) |
| Any StringValue WKT JSON stringify | 232.69 | — | — | 2229.91 (9.58x) | 912.83 (3.92x) |
| Any StringValue WKT JSON parse | 602.75 | — | — | 4084.27 (6.78x) | 1968.13 (3.27x) |
| Any BytesValue WKT JSON stringify | 218.79 | — | — | 2295.46 (10.49x) | 985.38 (4.50x) |
| Any BytesValue WKT JSON parse | 610.84 | — | — | 4257.32 (6.97x) | 2038.12 (3.34x) |
| Nested Any WKT JSON stringify | 351.61 | — | — | 3353.32 (9.54x) | 1587.16 (4.51x) |
| Nested Any WKT JSON parse | 1003.57 | — | — | 6086.56 (6.06x) | 3669.81 (3.66x) |
| Duration JSON stringify | 64.63 | — | — | 1508.68 (23.34x) | 358.93 (5.55x) |
| Duration JSON parse | 11.80 | — | — | 2223.46 (188.43x) | 455.28 (38.58x) |
| NegativeDuration JSON stringify | 64.91 | — | — | 1600.95 (24.66x) | 429.26 (6.61x) |
| NegativeDuration JSON parse | 12.17 | — | — | 2359.39 (193.87x) | 453.65 (37.28x) |
| FractionalNegativeDuration JSON stringify | 64.95 | — | — | 1533.79 (23.61x) | 448.82 (6.91x) |
| FractionalNegativeDuration JSON parse | 12.29 | — | — | 2263.44 (184.17x) | 439.97 (35.80x) |
| MaxDuration JSON stringify | 53.46 | — | — | 1283.64 (24.01x) | 439.74 (8.23x) |
| MaxDuration JSON parse | 29.21 | — | — | 2193.24 (75.09x) | 458.83 (15.71x) |
| MinDuration JSON stringify | 53.95 | — | — | 1307.20 (24.23x) | 463.96 (8.60x) |
| MinDuration JSON parse | 29.40 | — | — | 2250.81 (76.56x) | 458.96 (15.61x) |
| ZeroDuration JSON stringify | 47.69 | — | — | 1267.40 (26.58x) | 353.88 (7.42x) |
| ZeroDuration JSON parse | 8.77 | — | — | 2117.69 (241.47x) | 354.23 (40.39x) |
| FieldMask JSON stringify | 91.84 | — | — | 1273.60 (13.87x) | 750.34 (8.17x) |
| FieldMask JSON parse | 179.34 | — | — | 2657.83 (14.82x) | 1096.64 (6.11x) |
| Timestamp JSON stringify | 129.35 | — | — | 1724.44 (13.33x) | 463.06 (3.58x) |
| Timestamp JSON parse | 57.37 | — | — | 2262.52 (39.44x) | 496.61 (8.66x) |
| PreEpoch Timestamp JSON stringify | 85.77 | — | — | 1600.11 (18.66x) | 455.49 (5.31x) |
| PreEpoch Timestamp JSON parse | 54.93 | — | — | 2244.95 (40.87x) | 470.91 (8.57x) |
| Max Timestamp JSON stringify | 104.29 | — | — | 1759.57 (16.87x) | 472.33 (4.53x) |
| Max Timestamp JSON parse | 65.38 | — | — | 2306.37 (35.28x) | 512.71 (7.84x) |
| Min Timestamp JSON stringify | 118.47 | — | — | 1608.82 (13.58x) | 457.68 (3.86x) |
| Min Timestamp JSON parse | 52.90 | — | — | 2236.68 (42.28x) | 477.02 (9.02x) |
| Empty JSON stringify | 22.56 | — | — | 696.41 (30.87x) | 117.06 (5.19x) |
| Empty JSON parse | 84.59 | — | — | 1107.11 (13.09x) | 270.97 (3.20x) |
| Struct JSON stringify | 260.58 | — | — | 8984.32 (34.48x) | 4235.73 (16.26x) |
| Struct JSON parse | 939.53 | — | — | 16807.30 (17.89x) | 6410.07 (6.82x) |
| Value JSON stringify | 262.43 | — | — | 9769.59 (37.23x) | 4451.96 (16.96x) |
| Value JSON parse | 974.71 | — | — | 17689.00 (18.15x) | 6834.65 (7.01x) |
| ListValue JSON stringify | 194.91 | — | — | 7593.03 (38.96x) | 2892.21 (14.84x) |
| ListValue JSON parse | 731.07 | — | — | 13481.00 (18.44x) | 5311.55 (7.27x) |
| DoubleValue JSON stringify | 97.30 | — | — | 1477.47 (15.18x) | 210.91 (2.17x) |
| DoubleValue JSON parse | 113.19 | — | — | 2103.65 (18.59x) | 352.14 (3.11x) |
| DoubleValue NaN JSON stringify | 52.39 | — | — | 1011.62 (19.31x) | 145.80 (2.78x) |
| DoubleValue NaN JSON parse | 102.34 | — | — | 1719.12 (16.80x) | 337.54 (3.30x) |
| DoubleValue Infinity JSON stringify | 55.89 | — | — | 993.09 (17.77x) | 140.90 (2.52x) |
| DoubleValue Infinity JSON parse | 104.48 | — | — | 1715.18 (16.42x) | 343.31 (3.29x) |
| DoubleValue NegativeInfinity JSON stringify | 57.30 | — | — | 992.87 (17.33x) | 141.38 (2.47x) |
| DoubleValue NegativeInfinity JSON parse | 107.28 | — | — | 1728.37 (16.11x) | 331.57 (3.09x) |
| FloatValue JSON stringify | 102.77 | — | — | 1422.55 (13.84x) | 203.26 (1.98x) |
| FloatValue JSON parse | 112.78 | — | — | 2109.34 (18.70x) | 328.57 (2.91x) |
| FloatValue NaN JSON stringify | 52.86 | — | — | 994.60 (18.82x) | 144.85 (2.74x) |
| FloatValue NaN JSON parse | 102.89 | — | — | 1687.67 (16.40x) | 323.46 (3.14x) |
| FloatValue Infinity JSON stringify | 56.26 | — | — | 970.06 (17.24x) | 136.56 (2.43x) |
| FloatValue Infinity JSON parse | 104.73 | — | — | 1717.94 (16.40x) | 327.50 (3.13x) |
| FloatValue NegativeInfinity JSON stringify | 57.91 | — | — | 970.93 (16.77x) | 145.85 (2.52x) |
| FloatValue NegativeInfinity JSON parse | 106.94 | — | — | 1734.24 (16.22x) | 333.74 (3.12x) |
| Int64Value JSON stringify | 54.52 | — | — | 1008.78 (18.50x) | 299.96 (5.50x) |
| Int64Value JSON parse | 137.96 | — | — | 1981.18 (14.36x) | 530.49 (3.85x) |
| NegativeInt64Value JSON stringify | 54.26 | — | — | 1009.32 (18.60x) | 297.16 (5.48x) |
| NegativeInt64Value JSON parse | 139.52 | — | — | 1973.61 (14.15x) | 547.92 (3.93x) |
| UInt64Value JSON stringify | 41.78 | — | — | 1013.32 (24.25x) | 304.78 (7.29x) |
| UInt64Value JSON parse | 145.11 | — | — | 1967.07 (13.56x) | 525.88 (3.62x) |
| Int32Value JSON stringify | 47.40 | — | — | 970.35 (20.47x) | 147.43 (3.11x) |
| Int32Value JSON parse | 134.89 | — | — | 1916.44 (14.21x) | 369.46 (2.74x) |
| NegativeInt32Value JSON stringify | 48.01 | — | — | 987.74 (20.57x) | 155.75 (3.24x) |
| NegativeInt32Value JSON parse | 130.64 | — | — | 1933.34 (14.80x) | 370.06 (2.83x) |
| UInt32Value JSON stringify | 45.84 | — | — | 915.19 (19.96x) | 148.02 (3.23x) |
| UInt32Value JSON parse | 134.94 | — | — | 1915.07 (14.19x) | 361.61 (2.68x) |
| BoolValue JSON stringify | 42.28 | — | — | 900.27 (21.29x) | 145.22 (3.43x) |
| BoolValue JSON parse | 59.12 | — | — | 1679.11 (28.40x) | 280.56 (4.75x) |
| StringValue JSON stringify | 53.56 | — | — | 1014.68 (18.94x) | 210.46 (3.93x) |
| StringValue JSON parse | 130.92 | — | — | 1825.57 (13.94x) | 378.52 (2.89x) |
| BytesValue JSON stringify | 47.15 | — | — | 994.13 (21.08x) | 217.18 (4.61x) |
| BytesValue JSON parse | 142.00 | — | — | 1972.89 (13.89x) | 399.51 (2.81x) |
| TextFormat parse | 852.05 | — | — | 5587.79 (6.56x) | 8073.27 (9.48x) |
| packed int32 decode | 994.16 | 2976.12 (2.99x) | 4226.86 (4.25x) | 1342.31 (1.35x) | 4428.82 (4.45x) |
| packed bool encode | 2.51 | 2078.98 (828.28x) | 539.24 (214.84x) | 22.67 (9.03x) | 4388.62 (1748.45x) |
| packed bool decode | 272.44 | 2058.16 (7.55x) | 3848.62 (14.13x) | 1107.52 (4.07x) | 2707.63 (9.94x) |
| largebytes decode | 125.09 | 8423.44 (67.34x) | 4609.67 (36.85x) | 7123.55 (56.95x) | 24059.78 (192.34x) |
| large map decode | 38645.32 | 127846.88 (3.31x) | 126959.97 (3.29x) | 118274.00 (3.06x) | 296167.33 (7.66x) |
| shuffled large map deterministic binary encode | 36703.55 | — | — | 114042.00 (3.11x) | 457687.56 (12.47x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded zero/positive/integer-negative/fractional-negative/min-max-bound `Duration`, `Struct`, `Value`,
`FieldMask`, min/pre/post/max-bound `Timestamp`, `Empty`, positive/negative `Int64Value`, `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), `UInt64Value`, positive/negative `Int32Value`, `UInt32Value`, `BoolValue`, `StringValue`, `BytesValue`, and recursive nested `Any` payloads), direct zero/positive/integer-negative/fractional-negative/min-max-bound Duration and min/pre/post/max-bound Timestamp WKT JSON plus other direct WKT JSON, TextFormat, packed scalars, large bytes,
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
