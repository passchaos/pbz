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
python3 bench/summarize_compare.py /tmp/pbz-compare.log --pivot > /tmp/pbz-compare-pivot.md
```

Latest accepted comparison (`/tmp/pbz-compare-short-timestamp-json-isolated.log`,
summarized in `/tmp/pbz-summary-short-timestamp-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 18.76 | 126.69 (6.75x) | 62.21 (3.32x) | 112.20 (5.98x) | 827.15 (44.09x) |
| binary decode | 89.19 | 250.46 (2.81x) | 301.40 (3.38x) | 220.24 (2.47x) | 939.38 (10.53x) |
| unknown fields count by number | 3.57 | — | — | 161.19 (45.15x) | — |
| deterministic binary encode | 52.28 | — | — | 153.71 (2.94x) | 1062.11 (20.32x) |
| scalarmix encode | 15.32 | 98.56 (6.43x) | 51.62 (3.37x) | 30.52 (1.99x) | 219.15 (14.30x) |
| scalarmix decode | 44.23 | 137.63 (3.11x) | 190.93 (4.32x) | 84.68 (1.91x) | 308.02 (6.96x) |
| textbytes encode | 9.52 | 74.64 (7.84x) | 35.54 (3.73x) | 117.48 (12.34x) | 152.25 (15.99x) |
| textbytes decode | 41.74 | 379.86 (9.10x) | 250.85 (6.01x) | 166.13 (3.98x) | 643.00 (15.40x) |
| largebytes encode | 25.81 | 2706.83 (104.88x) | 2666.78 (103.32x) | 2716.10 (105.23x) | 2720.22 (105.39x) |
| largebytes decode | 88.53 | 5537.56 (62.55x) | 3033.44 (34.26x) | 2729.30 (30.83x) | 25054.83 (283.01x) |
| presencemix encode | 17.23 | 55.67 (3.23x) | 27.04 (1.57x) | 57.87 (3.36x) | 237.41 (13.78x) |
| presencemix decode | 55.77 | 134.78 (2.42x) | 106.92 (1.92x) | 167.25 (3.00x) | 467.38 (8.38x) |
| complex encode | 51.95 | 135.72 (2.61x) | 95.89 (1.85x) | 164.09 (3.16x) | 919.33 (17.70x) |
| complex decode | 170.24 | 396.44 (2.33x) | 336.93 (1.98x) | 395.07 (2.32x) | 1250.80 (7.35x) |
| complex deterministic binary encode | 93.29 | — | — | 170.96 (1.83x) | 1080.32 (11.58x) |
| complex JSON stringify | 260.92 | — | — | 5017.27 (19.23x) | 5763.08 (22.09x) |
| complex JSON parse | 2404.80 | — | — | 11908.70 (4.95x) | 7203.12 (3.00x) |
| complex TextFormat format | 260.43 | — | — | 3763.39 (14.45x) | 5264.73 (20.22x) |
| complex TextFormat parse | 1836.60 | — | — | 6900.27 (3.76x) | 8300.78 (4.52x) |
| packed int32 encode | 647.47 | 3183.62 (4.92x) | 2521.09 (3.89x) | 1244.42 (1.92x) | 2738.63 (4.23x) |
| packed int32 decode | 687.05 | 1915.34 (2.79x) | 3227.13 (4.70x) | 960.53 (1.40x) | 2976.76 (4.33x) |
| JSON stringify | 152.06 | — | — | 3096.20 (20.36x) | 2085.77 (13.72x) |
| JSON parse | 1558.74 | — | — | 7443.09 (4.78x) | 4160.57 (2.67x) |
| Any WKT JSON stringify | 128.29 | — | — | 1938.73 (15.11x) | 1136.07 (8.86x) |
| Any WKT JSON parse | 518.69 | — | — | 2962.56 (5.71x) | 1423.73 (2.74x) |
| Any PlusDuration WKT JSON parse | 517.28 | — | — | 2985.45 (5.77x) | 1532.43 (2.96x) |
| Any ShortFractionDuration WKT JSON parse | 513.25 | — | — | 2947.73 (5.74x) | 1480.28 (2.88x) |
| Any MicroDuration WKT JSON stringify | 132.49 | — | — | 1949.82 (14.72x) | 978.72 (7.39x) |
| Any MicroDuration WKT JSON parse | 518.15 | — | — | 3016.88 (5.82x) | 1448.91 (2.80x) |
| Any NanoDuration WKT JSON stringify | 131.10 | — | — | 2105.72 (16.06x) | 1002.03 (7.64x) |
| Any NanoDuration WKT JSON parse | 524.70 | — | — | 3117.87 (5.94x) | 1440.28 (2.74x) |
| Any NegativeDuration WKT JSON stringify | 130.29 | — | — | 1992.95 (15.30x) | 997.40 (7.66x) |
| Any NegativeDuration WKT JSON parse | 525.09 | — | — | 3093.79 (5.89x) | 1442.22 (2.75x) |
| Any FractionalNegativeDuration WKT JSON stringify | 124.36 | — | — | 1936.78 (15.57x) | 1044.85 (8.40x) |
| Any FractionalNegativeDuration WKT JSON parse | 516.25 | — | — | 3043.44 (5.90x) | 1528.55 (2.96x) |
| Any MaxDuration WKT JSON stringify | 116.66 | — | — | 1799.47 (15.42x) | 907.93 (7.78x) |
| Any MaxDuration WKT JSON parse | 536.46 | — | — | 2949.67 (5.50x) | 1477.84 (2.75x) |
| Any MinDuration WKT JSON stringify | 117.68 | — | — | 1808.32 (15.37x) | 949.90 (8.07x) |
| Any MinDuration WKT JSON parse | 535.98 | — | — | 3007.86 (5.61x) | 1450.68 (2.71x) |
| Any ZeroDuration WKT JSON stringify | 105.26 | — | — | 961.78 (9.14x) | 919.80 (8.74x) |
| Any ZeroDuration WKT JSON parse | 471.15 | — | — | 2264.39 (4.81x) | 1319.19 (2.80x) |
| Any FieldMask WKT JSON stringify | 229.11 | — | — | 1796.25 (7.84x) | 1384.21 (6.04x) |
| Any FieldMask WKT JSON parse | 722.15 | — | — | 3146.14 (4.36x) | 1963.46 (2.72x) |
| Any EmptyFieldMask WKT JSON stringify | 111.03 | — | — | 966.11 (8.70x) | 747.62 (6.73x) |
| Any EmptyFieldMask WKT JSON parse | 447.11 | — | — | 2146.94 (4.80x) | 1192.78 (2.67x) |
| Any Timestamp WKT JSON stringify | 175.68 | — | — | 2090.07 (11.90x) | 964.13 (5.49x) |
| Any Timestamp WKT JSON parse | 567.61 | — | — | 3007.09 (5.30x) | 1472.38 (2.59x) |
| Any ShortFraction Timestamp WKT JSON parse | 565.07 | — | — | 3057.47 (5.41x) | 1499.74 (2.65x) |
| Any Micro Timestamp WKT JSON stringify | 175.65 | — | — | 2085.78 (11.87x) | 999.59 (5.69x) |
| Any Micro Timestamp WKT JSON parse | 573.70 | — | — | 3029.30 (5.28x) | 1503.92 (2.62x) |
| Any Nano Timestamp WKT JSON stringify | 174.62 | — | — | 2085.58 (11.94x) | 980.86 (5.62x) |
| Any Nano Timestamp WKT JSON parse | 578.97 | — | — | 3130.48 (5.41x) | 1739.66 (3.00x) |
| Any Offset Timestamp WKT JSON parse | 582.54 | — | — | 3038.89 (5.22x) | 1590.48 (2.73x) |
| Any PreEpoch Timestamp WKT JSON stringify | 142.87 | — | — | 2002.12 (14.01x) | 1019.87 (7.14x) |
| Any PreEpoch Timestamp WKT JSON parse | 560.38 | — | — | 3034.31 (5.41x) | 1567.82 (2.80x) |
| Any Max Timestamp WKT JSON stringify | 159.48 | — | — | 2102.34 (13.18x) | 990.07 (6.21x) |
| Any Max Timestamp WKT JSON parse | 579.06 | — | — | 3089.02 (5.33x) | 1525.70 (2.63x) |
| Any Min Timestamp WKT JSON stringify | 154.54 | — | — | 1993.11 (12.90x) | 1002.79 (6.49x) |
| Any Min Timestamp WKT JSON parse | 559.19 | — | — | 3007.81 (5.38x) | 1699.78 (3.04x) |
| Any Empty WKT JSON stringify | 90.24 | — | — | 960.43 (10.64x) | 646.76 (7.17x) |
| Any Empty WKT JSON parse | 339.19 | — | — | 2115.04 (6.24x) | 1243.06 (3.66x) |
| Any Struct WKT JSON stringify | 643.40 | — | — | 5899.48 (9.17x) | 6215.36 (9.66x) |
| Any Struct WKT JSON parse | 1750.88 | — | — | 11023.60 (6.30x) | 8232.88 (4.70x) |
| Any EmptyStruct WKT JSON stringify | 115.81 | — | — | 975.94 (8.43x) | 941.23 (8.13x) |
| Any EmptyStruct WKT JSON parse | 441.68 | — | — | 2216.72 (5.02x) | 1568.03 (3.55x) |
| Any Value WKT JSON stringify | 666.60 | — | — | 5921.19 (8.88x) | 6406.11 (9.61x) |
| Any Value WKT JSON parse | 1814.75 | — | — | 11289.80 (6.22x) | 9027.00 (4.97x) |
| Any NullValue WKT JSON stringify | 131.42 | — | — | 2309.60 (17.57x) | 872.94 (6.64x) |
| Any NullValue WKT JSON parse | 462.56 | — | — | 4027.79 (8.71x) | 1443.99 (3.12x) |
| Any StringScalarValue WKT JSON stringify | 149.33 | — | — | 2337.14 (15.65x) | 1043.63 (6.99x) |
| Any StringScalarValue WKT JSON parse | 515.37 | — | — | 3593.11 (6.97x) | 1589.38 (3.08x) |
| Any EmptyStringScalarValue WKT JSON stringify | 137.01 | — | — | 2340.62 (17.08x) | 944.94 (6.90x) |
| Any EmptyStringScalarValue WKT JSON parse | 485.56 | — | — | 3609.62 (7.43x) | 1489.03 (3.07x) |
| Any NumberValue WKT JSON stringify | 177.21 | — | — | 2589.83 (14.61x) | 1308.26 (7.38x) |
| Any NumberValue WKT JSON parse | 508.67 | — | — | 3694.39 (7.26x) | 1560.73 (3.07x) |
| Any ZeroNumberValue WKT JSON stringify | 143.52 | — | — | 2535.48 (17.67x) | 908.12 (6.33x) |
| Any ZeroNumberValue WKT JSON parse | 503.77 | — | — | 3637.42 (7.22x) | 1481.42 (2.94x) |
| Any BoolScalarValue WKT JSON stringify | 130.22 | — | — | 2317.19 (17.79x) | 897.12 (6.89x) |
| Any BoolScalarValue WKT JSON parse | 462.87 | — | — | 3578.53 (7.73x) | 1444.22 (3.12x) |
| Any FalseBoolScalarValue WKT JSON stringify | 129.71 | — | — | 2311.25 (17.82x) | 950.09 (7.32x) |
| Any FalseBoolScalarValue WKT JSON parse | 465.11 | — | — | 3567.05 (7.67x) | 1434.39 (3.08x) |
| Any ListKindValue WKT JSON stringify | 516.36 | — | — | 5609.39 (10.86x) | 4884.85 (9.46x) |
| Any ListKindValue WKT JSON parse | 1769.59 | — | — | 9844.40 (5.56x) | 6565.04 (3.71x) |
| Any EmptyStructKindValue WKT JSON stringify | 173.75 | — | — | 2995.87 (17.24x) | 1237.70 (7.12x) |
| Any EmptyStructKindValue WKT JSON parse | 578.99 | — | — | 5423.43 (9.37x) | 1957.87 (3.38x) |
| Any EmptyListKindValue WKT JSON stringify | 174.24 | — | — | 2965.20 (17.02x) | 1083.82 (6.22x) |
| Any EmptyListKindValue WKT JSON parse | 572.22 | — | — | 4375.28 (7.65x) | 1696.71 (2.97x) |
| Any DoubleValue WKT JSON stringify | 241.05 | — | — | 1859.87 (7.72x) | 834.06 (3.46x) |
| Any DoubleValue WKT JSON parse | 577.40 | — | — | 2734.92 (4.74x) | 1413.66 (2.45x) |
| Any DoubleValue String WKT JSON parse | 592.24 | — | — | 2831.11 (4.78x) | 1434.73 (2.42x) |
| Any NegativeDoubleValue WKT JSON stringify | 240.37 | — | — | 1885.17 (7.84x) | 780.30 (3.25x) |
| Any NegativeDoubleValue WKT JSON parse | 578.62 | — | — | 2732.98 (4.72x) | 1344.57 (2.32x) |
| Any ZeroDoubleValue WKT JSON stringify | 190.16 | — | — | 975.78 (5.13x) | 692.30 (3.64x) |
| Any ZeroDoubleValue WKT JSON parse | 589.37 | — | — | 2163.00 (3.67x) | 1308.72 (2.22x) |
| Any DoubleValue NaN WKT JSON stringify | 168.14 | — | — | 1636.37 (9.73x) | 680.08 (4.04x) |
| Any DoubleValue NaN WKT JSON parse | 562.38 | — | — | 2658.05 (4.73x) | 1265.55 (2.25x) |
| Any DoubleValue Infinity WKT JSON stringify | 167.55 | — | — | 1621.02 (9.67x) | 681.76 (4.07x) |
| Any DoubleValue Infinity WKT JSON parse | 552.58 | — | — | 2688.82 (4.87x) | 1445.96 (2.62x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 160.34 | — | — | 1625.15 (10.14x) | 713.21 (4.45x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 553.47 | — | — | 2673.93 (4.83x) | 1324.71 (2.39x) |
| Any FloatValue WKT JSON stringify | 203.80 | — | — | 1798.72 (8.83x) | 819.12 (4.02x) |
| Any FloatValue WKT JSON parse | 542.83 | — | — | 2712.13 (5.00x) | 1403.91 (2.59x) |
| Any FloatValue String WKT JSON parse | 546.98 | — | — | 2751.78 (5.03x) | 1485.40 (2.72x) |
| Any NegativeFloatValue WKT JSON stringify | 202.45 | — | — | 1791.12 (8.85x) | 736.36 (3.64x) |
| Any NegativeFloatValue WKT JSON parse | 542.90 | — | — | 2699.84 (4.97x) | 1384.19 (2.55x) |
| Any ZeroFloatValue WKT JSON stringify | 169.11 | — | — | 969.12 (5.73x) | 686.92 (4.06x) |
| Any ZeroFloatValue WKT JSON parse | 528.88 | — | — | 2147.96 (4.06x) | 1290.14 (2.44x) |
| Any FloatValue NaN WKT JSON stringify | 153.55 | — | — | 1619.92 (10.55x) | 709.75 (4.62x) |
| Any FloatValue NaN WKT JSON parse | 520.58 | — | — | 2626.98 (5.05x) | 1344.92 (2.58x) |
| Any FloatValue Infinity WKT JSON stringify | 159.08 | — | — | 1629.14 (10.24x) | 701.80 (4.41x) |
| Any FloatValue Infinity WKT JSON parse | 521.27 | — | — | 2657.07 (5.10x) | 1354.43 (2.60x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 157.06 | — | — | 1604.03 (10.21x) | 691.12 (4.40x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 524.68 | — | — | 2649.84 (5.05x) | 1344.67 (2.56x) |
| Any Int64Value WKT JSON stringify | 168.84 | — | — | 1617.20 (9.58x) | 894.07 (5.30x) |
| Any Int64Value WKT JSON parse | 560.98 | — | — | 2781.38 (4.96x) | 1509.53 (2.69x) |
| Any Int64Value Number WKT JSON parse | 551.32 | — | — | 2787.80 (5.06x) | 1545.67 (2.80x) |
| Any ZeroInt64Value WKT JSON stringify | 153.35 | — | — | 983.13 (6.41x) | 748.51 (4.88x) |
| Any ZeroInt64Value WKT JSON parse | 523.51 | — | — | 2148.12 (4.10x) | 1393.93 (2.66x) |
| Any NegativeInt64Value WKT JSON stringify | 167.52 | — | — | 1619.24 (9.67x) | 830.26 (4.96x) |
| Any NegativeInt64Value WKT JSON parse | 551.41 | — | — | 2802.50 (5.08x) | 1631.61 (2.96x) |
| Any MinInt64Value WKT JSON stringify | 172.28 | — | — | 1619.79 (9.40x) | 811.52 (4.71x) |
| Any MinInt64Value WKT JSON parse | 556.50 | — | — | 2822.23 (5.07x) | 1668.98 (3.00x) |
| Any MaxInt64Value WKT JSON stringify | 174.09 | — | — | 1622.81 (9.32x) | 936.90 (5.38x) |
| Any MaxInt64Value WKT JSON parse | 563.93 | — | — | 2801.62 (4.97x) | 1567.66 (2.78x) |
| Any UInt64Value WKT JSON stringify | 172.47 | — | — | 1618.50 (9.38x) | 856.82 (4.97x) |
| Any UInt64Value WKT JSON parse | 554.85 | — | — | 2787.43 (5.02x) | 1662.90 (3.00x) |
| Any UInt64Value Number WKT JSON parse | 553.72 | — | — | 2814.15 (5.08x) | 1501.87 (2.71x) |
| Any ZeroUInt64Value WKT JSON stringify | 157.84 | — | — | 969.33 (6.14x) | 776.97 (4.92x) |
| Any ZeroUInt64Value WKT JSON parse | 528.63 | — | — | 2158.40 (4.08x) | 1353.22 (2.56x) |
| Any MaxUInt64Value WKT JSON stringify | 180.72 | — | — | 1622.11 (8.98x) | 955.95 (5.29x) |
| Any MaxUInt64Value WKT JSON parse | 563.28 | — | — | 2830.32 (5.02x) | 1570.15 (2.79x) |
| Any Int32Value WKT JSON stringify | 165.33 | — | — | 1603.41 (9.70x) | 698.35 (4.22x) |
| Any Int32Value WKT JSON parse | 538.29 | — | — | 2657.10 (4.94x) | 1358.99 (2.52x) |
| Any Int32Value String WKT JSON parse | 546.63 | — | — | 2717.91 (4.97x) | 1466.48 (2.68x) |
| Any ZeroInt32Value WKT JSON stringify | 165.14 | — | — | 964.75 (5.84x) | 679.92 (4.12x) |
| Any ZeroInt32Value WKT JSON parse | 528.42 | — | — | 2141.76 (4.05x) | 1289.64 (2.44x) |
| Any NegativeInt32Value WKT JSON stringify | 171.63 | — | — | 1605.92 (9.36x) | 715.71 (4.17x) |
| Any NegativeInt32Value WKT JSON parse | 537.52 | — | — | 2687.98 (5.00x) | 1524.48 (2.84x) |
| Any MinInt32Value WKT JSON stringify | 178.85 | — | — | 1601.83 (8.96x) | 722.01 (4.04x) |
| Any MinInt32Value WKT JSON parse | 542.95 | — | — | 2710.99 (4.99x) | 1362.41 (2.51x) |
| Any MaxInt32Value WKT JSON stringify | 169.08 | — | — | 1605.69 (9.50x) | 715.47 (4.23x) |
| Any MaxInt32Value WKT JSON parse | 540.28 | — | — | 2684.26 (4.97x) | 1363.11 (2.52x) |
| Any UInt32Value WKT JSON stringify | 173.70 | — | — | 1612.58 (9.28x) | 768.20 (4.42x) |
| Any UInt32Value WKT JSON parse | 537.13 | — | — | 2663.59 (4.96x) | 1577.77 (2.94x) |
| Any UInt32Value String WKT JSON parse | 546.81 | — | — | 2712.81 (4.96x) | 1445.01 (2.64x) |
| Any ZeroUInt32Value WKT JSON stringify | 170.69 | — | — | 967.12 (5.67x) | 690.27 (4.04x) |
| Any ZeroUInt32Value WKT JSON parse | 534.16 | — | — | 2181.67 (4.08x) | 1417.63 (2.65x) |
| Any MaxUInt32Value WKT JSON stringify | 175.65 | — | — | 1611.44 (9.17x) | 705.79 (4.02x) |
| Any MaxUInt32Value WKT JSON parse | 544.93 | — | — | 2706.32 (4.97x) | 1553.94 (2.85x) |
| Any BoolValue WKT JSON stringify | 167.59 | — | — | 1583.23 (9.45x) | 754.06 (4.50x) |
| Any BoolValue WKT JSON parse | 490.85 | — | — | 2613.32 (5.32x) | 1223.47 (2.49x) |
| Any FalseBoolValue WKT JSON stringify | 169.19 | — | — | 1316.10 (7.78x) | 681.36 (4.03x) |
| Any FalseBoolValue WKT JSON parse | 490.92 | — | — | 2155.73 (4.39x) | 1223.79 (2.49x) |
| Any StringValue WKT JSON stringify | 200.85 | — | — | 1634.95 (8.14x) | 806.66 (4.02x) |
| Any StringValue WKT JSON parse | 554.54 | — | — | 2667.40 (4.81x) | 1322.83 (2.39x) |
| Any EmptyStringValue WKT JSON stringify | 187.92 | — | — | 969.21 (5.16x) | 722.85 (3.85x) |
| Any EmptyStringValue WKT JSON parse | 520.75 | — | — | 2162.69 (4.15x) | 1282.08 (2.46x) |
| Any BytesValue WKT JSON stringify | 184.10 | — | — | 1652.03 (8.97x) | 813.06 (4.42x) |
| Any BytesValue WKT JSON parse | 565.64 | — | — | 2682.44 (4.74x) | 1391.68 (2.46x) |
| Any EmptyBytesValue WKT JSON stringify | 176.90 | — | — | 969.75 (5.48x) | 741.30 (4.19x) |
| Any EmptyBytesValue WKT JSON parse | 531.04 | — | — | 2157.39 (4.06x) | 1464.62 (2.76x) |
| Nested Any WKT JSON stringify | 308.55 | — | — | 2553.00 (8.27x) | 1462.65 (4.74x) |
| Nested Any WKT JSON parse | 870.88 | — | — | 4259.23 (4.89x) | 2835.42 (3.26x) |
| Duration JSON stringify | 57.46 | — | — | 958.53 (16.68x) | 334.73 (5.83x) |
| Duration JSON parse | 8.20 | — | — | 1441.44 (175.79x) | 377.99 (46.10x) |
| PlusDuration JSON parse | 7.82 | — | — | 1449.16 (185.31x) | 370.71 (47.41x) |
| ShortFractionDuration JSON parse | 6.81 | — | — | 1422.82 (208.93x) | 376.30 (55.26x) |
| MicroDuration JSON stringify | 59.66 | — | — | 966.05 (16.19x) | 359.85 (6.03x) |
| MicroDuration JSON parse | 9.79 | — | — | 1459.77 (149.11x) | 362.79 (37.06x) |
| NanoDuration JSON stringify | 57.39 | — | — | 992.42 (17.29x) | 377.93 (6.59x) |
| NanoDuration JSON parse | 12.47 | — | — | 1508.47 (120.97x) | 360.99 (28.95x) |
| NegativeDuration JSON stringify | 58.58 | — | — | 1026.47 (17.52x) | 396.89 (6.78x) |
| NegativeDuration JSON parse | 8.03 | — | — | 1548.52 (192.84x) | 376.73 (46.92x) |
| FractionalNegativeDuration JSON stringify | 58.52 | — | — | 978.42 (16.72x) | 399.19 (6.82x) |
| FractionalNegativeDuration JSON parse | 8.02 | — | — | 1477.18 (184.19x) | 349.08 (43.53x) |
| MaxDuration JSON stringify | 49.63 | — | — | 859.64 (17.32x) | 385.66 (7.77x) |
| MaxDuration JSON parse | 22.21 | — | — | 1436.97 (64.70x) | 378.99 (17.06x) |
| MinDuration JSON stringify | 49.89 | — | — | 868.26 (17.40x) | 429.62 (8.61x) |
| MinDuration JSON parse | 22.49 | — | — | 1442.17 (64.12x) | 398.86 (17.73x) |
| ZeroDuration JSON stringify | 44.86 | — | — | 818.97 (18.26x) | 351.79 (7.84x) |
| ZeroDuration JSON parse | 5.77 | — | — | 1370.28 (237.48x) | 295.23 (51.17x) |
| FieldMask JSON stringify | 73.90 | — | — | 890.15 (12.05x) | 614.34 (8.31x) |
| FieldMask JSON parse | 146.54 | — | — | 1655.60 (11.30x) | 853.62 (5.83x) |
| EmptyFieldMask JSON stringify | 40.68 | — | — | 609.63 (14.99x) | 175.69 (4.32x) |
| EmptyFieldMask JSON parse | 2.52 | — | — | 946.89 (375.75x) | 165.51 (65.68x) |
| Timestamp JSON stringify | 96.36 | — | — | 1150.50 (11.94x) | 412.74 (4.28x) |
| Timestamp JSON parse | 41.21 | — | — | 1491.07 (36.18x) | 423.69 (10.28x) |
| ShortFraction Timestamp JSON parse | 39.90 | — | — | 1502.56 (37.66x) | 416.21 (10.43x) |
| Micro Timestamp JSON stringify | 96.15 | — | — | 1157.31 (12.04x) | 412.18 (4.29x) |
| Micro Timestamp JSON parse | 42.98 | — | — | 1502.60 (34.96x) | 454.62 (10.58x) |
| Nano Timestamp JSON stringify | 93.42 | — | — | 1184.91 (12.68x) | 453.92 (4.86x) |
| Nano Timestamp JSON parse | 45.57 | — | — | 1513.55 (33.21x) | 452.86 (9.94x) |
| Offset Timestamp JSON parse | 51.63 | — | — | 1520.48 (29.45x) | 469.13 (9.09x) |
| PreEpoch Timestamp JSON stringify | 66.18 | — | — | 1074.78 (16.24x) | 435.36 (6.58x) |
| PreEpoch Timestamp JSON parse | 40.02 | — | — | 1460.62 (36.50x) | 418.18 (10.45x) |
| Max Timestamp JSON stringify | 78.67 | — | — | 1203.43 (15.30x) | 454.40 (5.78x) |
| Max Timestamp JSON parse | 46.51 | — | — | 1548.80 (33.30x) | 439.68 (9.45x) |
| Min Timestamp JSON stringify | 79.50 | — | — | 1066.65 (13.42x) | 394.59 (4.96x) |
| Min Timestamp JSON parse | 37.91 | — | — | 1495.35 (39.44x) | 395.62 (10.44x) |
| Empty JSON stringify | 20.82 | — | — | 496.00 (23.82x) | 78.57 (3.77x) |
| Empty JSON parse | 68.70 | — | — | 722.80 (10.52x) | 202.84 (2.95x) |
| Struct JSON stringify | 185.66 | — | — | 5833.55 (31.42x) | 3017.27 (16.25x) |
| Struct JSON parse | 873.94 | — | — | 10957.80 (12.54x) | 4776.92 (5.47x) |
| EmptyStruct JSON stringify | 41.19 | — | — | 688.18 (16.71x) | 313.99 (7.62x) |
| EmptyStruct JSON parse | 90.60 | — | — | 2132.35 (23.54x) | 354.19 (3.91x) |
| Value JSON stringify | 189.81 | — | — | 6581.07 (34.67x) | 3171.12 (16.71x) |
| Value JSON parse | 890.68 | — | — | 12469.00 (14.00x) | 4626.90 (5.19x) |
| NullValue JSON stringify | 40.34 | — | — | 1317.22 (32.65x) | 225.72 (5.60x) |
| NullValue JSON parse | 67.30 | — | — | 2503.48 (37.20x) | 323.08 (4.80x) |
| StringScalarValue JSON stringify | 47.89 | — | — | 1396.94 (29.17x) | 264.17 (5.52x) |
| StringScalarValue JSON parse | 141.71 | — | — | 2130.10 (15.03x) | 405.84 (2.86x) |
| EmptyStringScalarValue JSON stringify | 47.06 | — | — | 1335.50 (28.38x) | 273.07 (5.80x) |
| EmptyStringScalarValue JSON parse | 84.27 | — | — | 2097.70 (24.89x) | 342.07 (4.06x) |
| NumberValue JSON stringify | 74.99 | — | — | 1549.72 (20.67x) | 325.86 (4.35x) |
| NumberValue JSON parse | 129.14 | — | — | 2202.04 (17.05x) | 373.03 (2.89x) |
| ZeroNumberValue JSON stringify | 50.71 | — | — | 1509.91 (29.78x) | 334.73 (6.60x) |
| ZeroNumberValue JSON parse | 127.59 | — | — | 2126.52 (16.67x) | 349.85 (2.74x) |
| BoolScalarValue JSON stringify | 40.42 | — | — | 1315.64 (32.55x) | 225.39 (5.58x) |
| BoolScalarValue JSON parse | 67.15 | — | — | 2040.43 (30.39x) | 311.60 (4.64x) |
| FalseBoolScalarValue JSON stringify | 40.40 | — | — | 1320.78 (32.69x) | 217.61 (5.39x) |
| FalseBoolScalarValue JSON parse | 67.66 | — | — | 2046.51 (30.25x) | 322.19 (4.76x) |
| ListKindValue JSON stringify | 149.68 | — | — | 6114.16 (40.85x) | 2193.75 (14.66x) |
| ListKindValue JSON parse | 675.56 | — | — | 10420.80 (15.43x) | 3950.16 (5.85x) |
| EmptyStructKindValue JSON stringify | 46.86 | — | — | 1962.93 (41.89x) | 504.36 (10.76x) |
| EmptyStructKindValue JSON parse | 109.29 | — | — | 3789.88 (34.68x) | 611.32 (5.59x) |
| EmptyListKindValue JSON stringify | 41.10 | — | — | 1960.23 (47.69x) | 350.99 (8.54x) |
| EmptyListKindValue JSON parse | 148.42 | — | — | 4078.76 (27.48x) | 587.36 (3.96x) |
| ListValue JSON stringify | 152.11 | — | — | 4755.88 (31.27x) | 2054.26 (13.51x) |
| ListValue JSON parse | 665.43 | — | — | 8642.85 (12.99x) | 3756.50 (5.65x) |
| EmptyListValue JSON stringify | 40.38 | — | — | 688.19 (17.04x) | 185.38 (4.59x) |
| EmptyListValue JSON parse | 127.01 | — | — | 2268.74 (17.86x) | 287.89 (2.27x) |
| DoubleValue JSON stringify | 68.38 | — | — | 852.18 (12.46x) | 181.31 (2.65x) |
| DoubleValue JSON parse | 110.72 | — | — | 1224.48 (11.06x) | 280.95 (2.54x) |
| DoubleValue String JSON parse | 111.23 | — | — | 1174.88 (10.56x) | 366.43 (3.29x) |
| NegativeDoubleValue JSON stringify | 68.32 | — | — | 860.01 (12.59x) | 203.68 (2.98x) |
| NegativeDoubleValue JSON parse | 111.22 | — | — | 1240.30 (11.15x) | 260.87 (2.35x) |
| ZeroDoubleValue JSON stringify | 47.57 | — | — | 799.44 (16.81x) | 137.13 (2.88x) |
| ZeroDoubleValue JSON parse | 108.21 | — | — | 1153.49 (10.66x) | 247.26 (2.29x) |
| DoubleValue NaN JSON stringify | 46.13 | — | — | 656.06 (14.22x) | 116.54 (2.53x) |
| DoubleValue NaN JSON parse | 104.49 | — | — | 1094.41 (10.47x) | 266.53 (2.55x) |
| DoubleValue Infinity JSON stringify | 47.76 | — | — | 659.54 (13.81x) | 204.89 (4.29x) |
| DoubleValue Infinity JSON parse | 105.65 | — | — | 1102.89 (10.44x) | 288.08 (2.73x) |
| DoubleValue NegativeInfinity JSON stringify | 47.87 | — | — | 658.14 (13.75x) | 117.96 (2.46x) |
| DoubleValue NegativeInfinity JSON parse | 108.10 | — | — | 1113.69 (10.30x) | 264.22 (2.44x) |
| FloatValue JSON stringify | 73.07 | — | — | 795.09 (10.88x) | 183.55 (2.51x) |
| FloatValue JSON parse | 110.14 | — | — | 1211.49 (11.00x) | 271.88 (2.47x) |
| FloatValue String JSON parse | 110.35 | — | — | 1169.76 (10.60x) | 358.95 (3.25x) |
| NegativeFloatValue JSON stringify | 73.12 | — | — | 793.43 (10.85x) | 186.30 (2.55x) |
| NegativeFloatValue JSON parse | 110.48 | — | — | 1233.96 (11.17x) | 290.15 (2.63x) |
| ZeroFloatValue JSON stringify | 47.44 | — | — | 741.29 (15.63x) | 143.81 (3.03x) |
| ZeroFloatValue JSON parse | 107.51 | — | — | 1161.18 (10.80x) | 262.02 (2.44x) |
| FloatValue NaN JSON stringify | 46.18 | — | — | 638.32 (13.82x) | 119.79 (2.59x) |
| FloatValue NaN JSON parse | 104.80 | — | — | 1079.19 (10.30x) | 259.93 (2.48x) |
| FloatValue Infinity JSON stringify | 47.63 | — | — | 640.33 (13.44x) | 113.75 (2.39x) |
| FloatValue Infinity JSON parse | 105.93 | — | — | 1119.54 (10.57x) | 237.66 (2.24x) |
| FloatValue NegativeInfinity JSON stringify | 47.87 | — | — | 635.98 (13.29x) | 138.44 (2.89x) |
| FloatValue NegativeInfinity JSON parse | 107.87 | — | — | 1093.07 (10.13x) | 272.13 (2.52x) |
| Int64Value JSON stringify | 50.50 | — | — | 676.37 (13.39x) | 258.36 (5.12x) |
| Int64Value JSON parse | 126.83 | — | — | 1228.57 (9.69x) | 455.79 (3.59x) |
| Int64Value Number JSON parse | 126.68 | — | — | 1301.60 (10.27x) | 342.11 (2.70x) |
| ZeroInt64Value JSON stringify | 41.39 | — | — | 609.90 (14.74x) | 184.95 (4.47x) |
| ZeroInt64Value JSON parse | 105.27 | — | — | 1094.28 (10.39x) | 339.08 (3.22x) |
| NegativeInt64Value JSON stringify | 49.96 | — | — | 673.28 (13.48x) | 264.51 (5.29x) |
| NegativeInt64Value JSON parse | 128.16 | — | — | 1211.87 (9.46x) | 450.68 (3.52x) |
| MinInt64Value JSON stringify | 49.20 | — | — | 674.99 (13.72x) | 264.99 (5.39x) |
| MinInt64Value JSON parse | 142.28 | — | — | 1244.68 (8.75x) | 460.40 (3.24x) |
| MaxInt64Value JSON stringify | 48.95 | — | — | 673.46 (13.76x) | 261.99 (5.35x) |
| MaxInt64Value JSON parse | 133.09 | — | — | 1244.97 (9.35x) | 443.56 (3.33x) |
| UInt64Value JSON stringify | 49.81 | — | — | 673.29 (13.52x) | 263.96 (5.30x) |
| UInt64Value JSON parse | 125.81 | — | — | 1217.18 (9.67x) | 422.78 (3.36x) |
| UInt64Value Number JSON parse | 126.31 | — | — | 1290.21 (10.21x) | 323.24 (2.56x) |
| ZeroUInt64Value JSON stringify | 41.33 | — | — | 612.13 (14.81x) | 182.97 (4.43x) |
| ZeroUInt64Value JSON parse | 105.53 | — | — | 1102.47 (10.45x) | 303.29 (2.87x) |
| MaxUInt64Value JSON stringify | 49.49 | — | — | 675.18 (13.64x) | 335.65 (6.78x) |
| MaxUInt64Value JSON parse | 136.86 | — | — | 1252.74 (9.15x) | 449.06 (3.28x) |
| Int32Value JSON stringify | 47.03 | — | — | 630.29 (13.40x) | 136.96 (2.91x) |
| Int32Value JSON parse | 116.55 | — | — | 1179.59 (10.12x) | 304.76 (2.61x) |
| Int32Value String JSON parse | 115.28 | — | — | 1140.00 (9.89x) | 390.87 (3.39x) |
| ZeroInt32Value JSON stringify | 47.09 | — | — | 609.75 (12.95x) | 117.64 (2.50x) |
| ZeroInt32Value JSON parse | 112.51 | — | — | 1145.39 (10.18x) | 252.00 (2.24x) |
| NegativeInt32Value JSON stringify | 46.68 | — | — | 636.83 (13.64x) | 156.11 (3.34x) |
| NegativeInt32Value JSON parse | 116.27 | — | — | 1190.09 (10.24x) | 323.11 (2.78x) |
| MinInt32Value JSON stringify | 47.18 | — | — | 639.74 (13.56x) | 127.42 (2.70x) |
| MinInt32Value JSON parse | 122.36 | — | — | 1211.50 (9.90x) | 331.29 (2.71x) |
| MaxInt32Value JSON stringify | 47.43 | — | — | 632.90 (13.34x) | 132.45 (2.79x) |
| MaxInt32Value JSON parse | 122.87 | — | — | 1203.34 (9.79x) | 316.11 (2.57x) |
| UInt32Value JSON stringify | 46.67 | — | — | 632.23 (13.55x) | 132.23 (2.83x) |
| UInt32Value JSON parse | 116.28 | — | — | 1193.11 (10.26x) | 312.45 (2.69x) |
| UInt32Value String JSON parse | 114.83 | — | — | 1152.81 (10.04x) | 411.79 (3.59x) |
| ZeroUInt32Value JSON stringify | 46.85 | — | — | 615.57 (13.14x) | 141.19 (3.01x) |
| ZeroUInt32Value JSON parse | 112.39 | — | — | 1153.65 (10.26x) | 252.08 (2.24x) |
| MaxUInt32Value JSON stringify | 47.48 | — | — | 633.87 (13.35x) | 129.97 (2.74x) |
| MaxUInt32Value JSON parse | 122.62 | — | — | 1210.35 (9.87x) | 324.68 (2.65x) |
| BoolValue JSON stringify | 45.68 | — | — | 612.67 (13.41x) | 132.94 (2.91x) |
| BoolValue JSON parse | 59.89 | — | — | 1051.52 (17.56x) | 209.96 (3.51x) |
| FalseBoolValue JSON stringify | 44.96 | — | — | 600.53 (13.36x) | 121.24 (2.70x) |
| FalseBoolValue JSON parse | 60.39 | — | — | 1061.87 (17.58x) | 206.03 (3.41x) |
| StringValue JSON stringify | 51.87 | — | — | 663.76 (12.80x) | 178.49 (3.44x) |
| StringValue JSON parse | 135.08 | — | — | 1148.06 (8.50x) | 269.14 (1.99x) |
| EmptyStringValue JSON stringify | 49.01 | — | — | 650.52 (13.27x) | 198.00 (4.04x) |
| EmptyStringValue JSON parse | 80.70 | — | — | 1116.13 (13.83x) | 222.75 (2.76x) |
| BytesValue JSON stringify | 49.20 | — | — | 670.24 (13.62x) | 226.50 (4.60x) |
| BytesValue JSON parse | 147.45 | — | — | 1168.27 (7.92x) | 329.66 (2.24x) |
| EmptyBytesValue JSON stringify | 40.63 | — | — | 645.10 (15.88x) | 186.52 (4.59x) |
| EmptyBytesValue JSON parse | 90.52 | — | — | 1129.42 (12.48x) | 276.98 (3.06x) |
| TextFormat format | 180.77 | — | — | 2606.31 (14.42x) | 2299.35 (12.72x) |
| TextFormat parse | 710.89 | — | — | 4996.85 (7.03x) | 6241.20 (8.78x) |
| packed fixed32 encode | 2.00 | 552.51 (276.25x) | 542.21 (271.11x) | 43.78 (21.89x) | 433.43 (216.72x) |
| packed fixed32 decode | 4.53 | 1042.19 (230.06x) | 1971.42 (435.19x) | 49.66 (10.96x) | 1781.46 (393.26x) |
| packed fixed64 encode | 2.01 | 573.21 (285.18x) | 561.37 (279.29x) | 75.74 (37.68x) | 398.51 (198.26x) |
| packed fixed64 decode | 4.52 | 1044.89 (231.17x) | 7939.96 (1756.63x) | 80.21 (17.75x) | 2397.52 (530.42x) |
| packed sfixed32 encode | 2.01 | 552.56 (274.91x) | 539.50 (268.41x) | 44.03 (21.91x) | 580.47 (288.79x) |
| packed sfixed32 decode | 4.53 | 1078.83 (238.15x) | 1962.81 (433.29x) | 48.88 (10.79x) | 1728.62 (381.59x) |
| packed sfixed64 encode | 2.01 | 572.76 (284.96x) | 561.63 (279.42x) | 75.73 (37.67x) | 406.83 (202.40x) |
| packed sfixed64 decode | 4.54 | 1038.77 (228.80x) | 7912.59 (1742.86x) | 79.57 (17.53x) | 2366.41 (521.24x) |
| packed float encode | 2.32 | 816.31 (351.86x) | 539.61 (232.59x) | 44.04 (18.98x) | 366.24 (157.86x) |
| packed float decode | 4.77 | 1049.28 (219.97x) | 2042.62 (428.22x) | 48.88 (10.25x) | 1682.73 (352.77x) |
| packed double encode | 2.01 | 828.09 (411.99x) | 561.32 (279.26x) | 75.58 (37.60x) | 364.29 (181.24x) |
| packed double decode | 4.53 | 981.93 (216.76x) | 2046.49 (451.76x) | 79.71 (17.60x) | 2555.96 (564.23x) |
| packed uint64 encode | 1288.09 | 4599.45 (3.57x) | 4018.16 (3.12x) | 2131.86 (1.66x) | 3484.58 (2.71x) |
| packed uint64 decode | 1789.96 | 2786.48 (1.56x) | 8870.47 (4.96x) | 2800.41 (1.56x) | 8098.58 (4.52x) |
| packed uint32 encode | 926.47 | 3613.21 (3.90x) | 3258.10 (3.52x) | 1773.19 (1.91x) | 3329.69 (3.59x) |
| packed uint32 decode | 1291.06 | 2426.30 (1.88x) | 3262.16 (2.53x) | 1988.70 (1.54x) | 5999.41 (4.65x) |
| packed int64 encode | 1410.02 | 10971.22 (7.78x) | 6055.57 (4.29x) | 2893.33 (2.05x) | 4113.99 (2.92x) |
| packed int64 decode | 2744.54 | 3498.50 (1.27x) | 10284.07 (3.75x) | 4784.73 (1.74x) | 10364.83 (3.78x) |
| packed sint32 encode | 781.79 | 3034.11 (3.88x) | 2960.74 (3.79x) | 1535.62 (1.96x) | 3407.33 (4.36x) |
| packed sint32 decode | 953.26 | 2546.19 (2.67x) | 3197.82 (3.35x) | 1123.31 (1.18x) | 3734.08 (3.92x) |
| packed sint64 encode | 1423.71 | 4936.33 (3.47x) | 4306.97 (3.03x) | 2399.64 (1.69x) | 4125.29 (2.90x) |
| packed sint64 decode | 2035.94 | 3065.16 (1.51x) | 9664.23 (4.75x) | 2930.44 (1.44x) | 8278.69 (4.07x) |
| packed bool encode | 2.01 | 1361.70 (677.46x) | 519.06 (258.24x) | 15.92 (7.92x) | 2392.38 (1190.24x) |
| packed bool decode | 262.78 | 1533.37 (5.84x) | 2539.48 (9.66x) | 812.53 (3.09x) | 1650.20 (6.28x) |
| packed enum encode | 272.35 | 2720.98 (9.99x) | 1800.37 (6.61x) | 1086.06 (3.99x) | 2615.64 (9.60x) |
| packed enum decode | 153.89 | 1540.31 (10.01x) | 2889.33 (18.78x) | 697.96 (4.54x) | 2264.27 (14.71x) |
| large map encode | 4041.20 | 16399.39 (4.06x) | 9859.79 (2.44x) | 23674.80 (5.86x) | 190093.90 (47.04x) |
| shuffled large map deterministic binary encode | 27792.31 | — | — | 104266.00 (3.75x) | 371700.79 (13.37x) |
| large map decode | 25442.63 | 90781.90 (3.57x) | 89077.41 (3.50x) | 91795.80 (3.61x) | 272842.77 (10.72x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded zero/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound `Duration`, non-empty and empty `Struct`, object/list/scalar `Value` (including default-like scalar and empty object/list kinds),
`FieldMask` (non-empty and empty), short-fraction parse/micro/nano/offset/min/pre/post/max-bound `Timestamp`, `Empty`, min/zero/positive/number-input parse/negative/max `Int64Value`, negative/zero/positive finite/string-input parse `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), negative/zero/positive finite/string-input parse `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), zero/normal/number-input parse/max `UInt64Value`, min/zero/positive/string-input parse/negative/max `Int32Value`, zero/normal/string-input parse/max `UInt32Value`, true/false `BoolValue`, non-empty/empty `StringValue`, base64/empty `BytesValue`, and recursive nested `Any` payloads), direct zero/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound Duration and short-fraction parse/micro/nano/offset/min/pre/post/max-bound Timestamp WKT JSON plus other direct WKT JSON, including empty `Struct` and empty `ListValue`, TextFormat, packed scalars, large bytes,
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
