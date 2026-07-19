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

Latest accepted comparison (`/tmp/pbz-compare-string-escape-json-isolated.log`,
summarized in `/tmp/pbz-summary-string-escape-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 25.05 | 102.49 (4.09x) | 64.46 (2.57x) | 108.69 (4.34x) | 819.96 (32.73x) |
| binary decode | 90.99 | 281.53 (3.09x) | 241.56 (2.65x) | 224.12 (2.46x) | 889.77 (9.78x) |
| unknown fields count by number | 3.57 | — | — | 163.09 (45.68x) | — |
| deterministic binary encode | 58.28 | — | — | 129.80 (2.23x) | 1049.79 (18.01x) |
| scalarmix encode | 17.74 | 101.07 (5.70x) | 47.10 (2.66x) | 30.67 (1.73x) | 217.19 (12.24x) |
| scalarmix decode | 43.20 | 137.68 (3.19x) | 175.64 (4.07x) | 84.59 (1.96x) | 272.33 (6.30x) |
| textbytes encode | 9.27 | 80.27 (8.66x) | 33.69 (3.63x) | 117.90 (12.72x) | 157.30 (16.97x) |
| textbytes decode | 45.76 | 382.19 (8.35x) | 238.17 (5.20x) | 163.81 (3.58x) | 627.60 (13.72x) |
| largebytes encode | 18.04 | 2702.88 (149.83x) | 2669.22 (147.96x) | 2679.00 (148.50x) | 2827.60 (156.74x) |
| largebytes decode | 92.26 | 5856.24 (63.48x) | 3107.95 (33.69x) | 2723.12 (29.52x) | 23966.56 (259.77x) |
| presencemix encode | 16.62 | 64.58 (3.89x) | 28.26 (1.70x) | 58.65 (3.53x) | 244.69 (14.72x) |
| presencemix decode | 58.60 | 164.13 (2.80x) | 106.30 (1.81x) | 162.30 (2.77x) | 501.52 (8.56x) |
| complex encode | 50.95 | 151.31 (2.97x) | 95.31 (1.87x) | 151.18 (2.97x) | 939.54 (18.44x) |
| complex decode | 172.62 | 391.27 (2.27x) | 349.22 (2.02x) | 391.56 (2.27x) | 1302.72 (7.55x) |
| complex deterministic binary encode | 93.39 | — | — | 167.81 (1.80x) | 1083.23 (11.60x) |
| complex JSON stringify | 265.02 | — | — | 4940.10 (18.64x) | 5573.85 (21.03x) |
| complex JSON parse | 2396.08 | — | — | 11993.10 (5.01x) | 6867.11 (2.87x) |
| complex TextFormat format | 266.65 | — | — | 3768.45 (14.13x) | 4850.53 (18.19x) |
| complex TextFormat parse | 1830.67 | — | — | 7095.70 (3.88x) | 7896.95 (4.31x) |
| packed int32 encode | 647.93 | 3150.15 (4.86x) | 2505.70 (3.87x) | 1237.19 (1.91x) | 2926.37 (4.52x) |
| packed int32 decode | 685.12 | 1920.56 (2.80x) | 3200.60 (4.67x) | 1026.47 (1.50x) | 3547.77 (5.18x) |
| JSON stringify | 150.01 | — | — | 3109.49 (20.73x) | 2047.49 (13.65x) |
| JSON parse | 1530.97 | — | — | 7523.52 (4.91x) | 5237.59 (3.42x) |
| Any WKT JSON stringify | 132.47 | — | — | 1884.16 (14.22x) | 1064.99 (8.04x) |
| Any WKT JSON parse | 520.49 | — | — | 2967.10 (5.70x) | 1401.56 (2.69x) |
| Any PlusDuration WKT JSON parse | 520.63 | — | — | 2991.40 (5.75x) | 1775.01 (3.41x) |
| Any ShortFractionDuration WKT JSON parse | 516.52 | — | — | 2939.67 (5.69x) | 2840.27 (5.50x) |
| Any MicroDuration WKT JSON stringify | 134.41 | — | — | 1902.87 (14.16x) | 1440.33 (10.72x) |
| Any MicroDuration WKT JSON parse | 520.89 | — | — | 2994.40 (5.75x) | 1607.14 (3.09x) |
| Any NanoDuration WKT JSON stringify | 130.45 | — | — | 1923.84 (14.75x) | 1668.04 (12.79x) |
| Any NanoDuration WKT JSON parse | 525.70 | — | — | 2995.13 (5.70x) | 1450.51 (2.76x) |
| Any NegativeDuration WKT JSON stringify | 134.02 | — | — | 1950.34 (14.55x) | 1758.40 (13.12x) |
| Any NegativeDuration WKT JSON parse | 526.98 | — | — | 3129.11 (5.94x) | 1697.88 (3.22x) |
| Any FractionalNegativeDuration WKT JSON stringify | 129.23 | — | — | 1903.40 (14.73x) | 1271.89 (9.84x) |
| Any FractionalNegativeDuration WKT JSON parse | 519.47 | — | — | 3074.18 (5.92x) | 2046.51 (3.94x) |
| Any MaxDuration WKT JSON stringify | 117.14 | — | — | 1806.52 (15.42x) | 1330.10 (11.35x) |
| Any MaxDuration WKT JSON parse | 538.93 | — | — | 2952.49 (5.48x) | 1523.21 (2.83x) |
| Any MinDuration WKT JSON stringify | 117.64 | — | — | 1762.51 (14.98x) | 931.78 (7.92x) |
| Any MinDuration WKT JSON parse | 533.11 | — | — | 3009.56 (5.65x) | 1662.55 (3.12x) |
| Any ZeroDuration WKT JSON stringify | 107.25 | — | — | 919.20 (8.57x) | 936.68 (8.73x) |
| Any ZeroDuration WKT JSON parse | 473.58 | — | — | 2235.73 (4.72x) | 1413.29 (2.98x) |
| Any FieldMask WKT JSON stringify | 225.23 | — | — | 1741.61 (7.73x) | 1434.59 (6.37x) |
| Any FieldMask WKT JSON parse | 728.91 | — | — | 3153.70 (4.33x) | 2349.48 (3.22x) |
| Any EmptyFieldMask WKT JSON stringify | 119.53 | — | — | 914.57 (7.65x) | 778.42 (6.51x) |
| Any EmptyFieldMask WKT JSON parse | 446.84 | — | — | 2134.91 (4.78x) | 1199.25 (2.68x) |
| Any Timestamp WKT JSON stringify | 174.71 | — | — | 2020.81 (11.57x) | 1235.61 (7.07x) |
| Any Timestamp WKT JSON parse | 572.11 | — | — | 3017.90 (5.28x) | 1575.39 (2.75x) |
| Any ShortFraction Timestamp WKT JSON parse | 571.03 | — | — | 3009.14 (5.27x) | 1544.79 (2.71x) |
| Any Micro Timestamp WKT JSON stringify | 175.99 | — | — | 2022.12 (11.49x) | 986.09 (5.60x) |
| Any Micro Timestamp WKT JSON parse | 574.60 | — | — | 3056.94 (5.32x) | 1488.97 (2.59x) |
| Any Nano Timestamp WKT JSON stringify | 173.15 | — | — | 2028.66 (11.72x) | 1103.14 (6.37x) |
| Any Nano Timestamp WKT JSON parse | 584.01 | — | — | 3023.80 (5.18x) | 1728.65 (2.96x) |
| Any Offset Timestamp WKT JSON parse | 587.58 | — | — | 3036.16 (5.17x) | 1724.34 (2.93x) |
| Any PreEpoch Timestamp WKT JSON stringify | 141.47 | — | — | 1939.93 (13.71x) | 982.12 (6.94x) |
| Any PreEpoch Timestamp WKT JSON parse | 564.70 | — | — | 3033.45 (5.37x) | 1491.83 (2.64x) |
| Any Max Timestamp WKT JSON stringify | 159.54 | — | — | 2043.31 (12.81x) | 965.05 (6.05x) |
| Any Max Timestamp WKT JSON parse | 584.13 | — | — | 3064.46 (5.25x) | 1540.20 (2.64x) |
| Any Min Timestamp WKT JSON stringify | 155.30 | — | — | 1930.24 (12.43x) | 1003.37 (6.46x) |
| Any Min Timestamp WKT JSON parse | 559.14 | — | — | 3011.08 (5.39x) | 1515.71 (2.71x) |
| Any Empty WKT JSON stringify | 94.22 | — | — | 909.09 (9.65x) | 575.85 (6.11x) |
| Any Empty WKT JSON parse | 334.93 | — | — | 2109.17 (6.30x) | 1282.39 (3.83x) |
| Any Struct WKT JSON stringify | 641.29 | — | — | 5791.16 (9.03x) | 6360.71 (9.92x) |
| Any Struct WKT JSON parse | 1767.83 | — | — | 11026.50 (6.24x) | 9360.32 (5.29x) |
| Any EmptyStruct WKT JSON stringify | 127.54 | — | — | 909.74 (7.13x) | 876.35 (6.87x) |
| Any EmptyStruct WKT JSON parse | 441.60 | — | — | 2221.71 (5.03x) | 1499.56 (3.40x) |
| Any Value WKT JSON stringify | 665.53 | — | — | 5901.33 (8.87x) | 7012.89 (10.54x) |
| Any Value WKT JSON parse | 1809.35 | — | — | 11364.50 (6.28x) | 10071.21 (5.57x) |
| Any NullValue WKT JSON stringify | 131.14 | — | — | 2270.39 (17.31x) | 963.64 (7.35x) |
| Any NullValue WKT JSON parse | 465.46 | — | — | 4067.35 (8.74x) | 1506.07 (3.24x) |
| Any StringScalarValue WKT JSON stringify | 151.81 | — | — | 2434.07 (16.03x) | 996.61 (6.56x) |
| Any StringScalarValue WKT JSON parse | 519.13 | — | — | 3605.88 (6.95x) | 1694.59 (3.26x) |
| Any EmptyStringScalarValue WKT JSON stringify | 138.94 | — | — | 2283.42 (16.43x) | 1066.35 (7.67x) |
| Any EmptyStringScalarValue WKT JSON parse | 487.81 | — | — | 3582.48 (7.34x) | 1653.87 (3.39x) |
| Any NumberValue WKT JSON stringify | 186.97 | — | — | 2540.79 (13.59x) | 1075.48 (5.75x) |
| Any NumberValue WKT JSON parse | 507.35 | — | — | 3723.09 (7.34x) | 1687.85 (3.33x) |
| Any ZeroNumberValue WKT JSON stringify | 152.95 | — | — | 2479.01 (16.21x) | 1010.97 (6.61x) |
| Any ZeroNumberValue WKT JSON parse | 504.04 | — | — | 3636.35 (7.21x) | 1493.57 (2.96x) |
| Any BoolScalarValue WKT JSON stringify | 132.86 | — | — | 2276.55 (17.13x) | 934.58 (7.03x) |
| Any BoolScalarValue WKT JSON parse | 463.00 | — | — | 3604.97 (7.79x) | 1572.77 (3.40x) |
| Any FalseBoolScalarValue WKT JSON stringify | 134.82 | — | — | 2290.91 (16.99x) | 910.57 (6.75x) |
| Any FalseBoolScalarValue WKT JSON parse | 466.90 | — | — | 3614.61 (7.74x) | 1445.22 (3.10x) |
| Any ListKindValue WKT JSON stringify | 505.88 | — | — | 5637.43 (11.14x) | 5082.12 (10.05x) |
| Any ListKindValue WKT JSON parse | 1396.56 | — | — | 9843.07 (7.05x) | 7340.98 (5.26x) |
| Any EmptyStructKindValue WKT JSON stringify | 145.99 | — | — | 2908.34 (19.92x) | 1222.25 (8.37x) |
| Any EmptyStructKindValue WKT JSON parse | 497.68 | — | — | 5365.64 (10.78x) | 1813.41 (3.64x) |
| Any EmptyListKindValue WKT JSON stringify | 143.79 | — | — | 2898.92 (20.16x) | 1286.68 (8.95x) |
| Any EmptyListKindValue WKT JSON parse | 501.27 | — | — | 4356.00 (8.69x) | 1729.34 (3.45x) |
| Any DoubleValue WKT JSON stringify | 191.92 | — | — | 1781.41 (9.28x) | 830.85 (4.33x) |
| Any DoubleValue WKT JSON parse | 532.28 | — | — | 2723.62 (5.12x) | 1324.24 (2.49x) |
| Any DoubleValue String WKT JSON parse | 539.59 | — | — | 2723.13 (5.05x) | 1622.87 (3.01x) |
| Any NegativeDoubleValue WKT JSON stringify | 198.88 | — | — | 1796.37 (9.03x) | 802.92 (4.04x) |
| Any NegativeDoubleValue WKT JSON parse | 532.08 | — | — | 2726.88 (5.12x) | 1475.19 (2.77x) |
| Any ZeroDoubleValue WKT JSON stringify | 166.75 | — | — | 934.91 (5.61x) | 691.36 (4.15x) |
| Any ZeroDoubleValue WKT JSON parse | 524.61 | — | — | 2174.54 (4.15x) | 1449.15 (2.76x) |
| Any DoubleValue NaN WKT JSON stringify | 158.34 | — | — | 1571.64 (9.93x) | 720.03 (4.55x) |
| Any DoubleValue NaN WKT JSON parse | 524.59 | — | — | 2633.01 (5.02x) | 1438.59 (2.74x) |
| Any DoubleValue Infinity WKT JSON stringify | 164.50 | — | — | 1572.39 (9.56x) | 704.99 (4.29x) |
| Any DoubleValue Infinity WKT JSON parse | 526.32 | — | — | 2681.34 (5.09x) | 1435.05 (2.73x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 168.96 | — | — | 1552.36 (9.19x) | 719.18 (4.26x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 529.85 | — | — | 2665.30 (5.03x) | 1462.97 (2.76x) |
| Any FloatValue WKT JSON stringify | 201.77 | — | — | 1737.23 (8.61x) | 757.82 (3.76x) |
| Any FloatValue WKT JSON parse | 524.22 | — | — | 2687.73 (5.13x) | 1432.44 (2.73x) |
| Any FloatValue String WKT JSON parse | 537.67 | — | — | 2701.89 (5.03x) | 1469.11 (2.73x) |
| Any NegativeFloatValue WKT JSON stringify | 204.54 | — | — | 1733.56 (8.48x) | 733.99 (3.59x) |
| Any NegativeFloatValue WKT JSON parse | 527.07 | — | — | 2699.63 (5.12x) | 1317.64 (2.50x) |
| Any ZeroFloatValue WKT JSON stringify | 170.92 | — | — | 914.48 (5.35x) | 723.74 (4.23x) |
| Any ZeroFloatValue WKT JSON parse | 522.77 | — | — | 2170.30 (4.15x) | 1422.27 (2.72x) |
| Any FloatValue NaN WKT JSON stringify | 161.61 | — | — | 1563.47 (9.67x) | 714.96 (4.42x) |
| Any FloatValue NaN WKT JSON parse | 523.88 | — | — | 2611.91 (4.99x) | 1506.06 (2.87x) |
| Any FloatValue Infinity WKT JSON stringify | 167.00 | — | — | 1550.54 (9.28x) | 738.67 (4.42x) |
| Any FloatValue Infinity WKT JSON parse | 527.79 | — | — | 2650.80 (5.02x) | 1493.60 (2.83x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 165.44 | — | — | 1546.53 (9.35x) | 736.09 (4.45x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 530.57 | — | — | 2645.92 (4.99x) | 1275.95 (2.40x) |
| Any Int64Value WKT JSON stringify | 172.45 | — | — | 1567.29 (9.09x) | 938.32 (5.44x) |
| Any Int64Value WKT JSON parse | 556.32 | — | — | 2764.24 (4.97x) | 1641.84 (2.95x) |
| Any Int64Value Number WKT JSON parse | 553.90 | — | — | 2733.09 (4.93x) | 1595.31 (2.88x) |
| Any ZeroInt64Value WKT JSON stringify | 166.27 | — | — | 912.75 (5.49x) | 743.85 (4.47x) |
| Any ZeroInt64Value WKT JSON parse | 532.14 | — | — | 2135.13 (4.01x) | 1474.02 (2.77x) |
| Any NegativeInt64Value WKT JSON stringify | 172.50 | — | — | 1555.40 (9.02x) | 843.41 (4.89x) |
| Any NegativeInt64Value WKT JSON parse | 569.10 | — | — | 2787.95 (4.90x) | 1611.71 (2.83x) |
| Any MinInt64Value WKT JSON stringify | 174.32 | — | — | 1565.16 (8.98x) | 987.27 (5.66x) |
| Any MinInt64Value WKT JSON parse | 572.15 | — | — | 2827.69 (4.94x) | 1719.42 (3.01x) |
| Any MaxInt64Value WKT JSON stringify | 172.18 | — | — | 1555.56 (9.03x) | 824.73 (4.79x) |
| Any MaxInt64Value WKT JSON parse | 559.30 | — | — | 2788.42 (4.99x) | 1564.82 (2.80x) |
| Any UInt64Value WKT JSON stringify | 174.77 | — | — | 1554.58 (8.90x) | 870.08 (4.98x) |
| Any UInt64Value WKT JSON parse | 561.69 | — | — | 2775.14 (4.94x) | 1667.97 (2.97x) |
| Any UInt64Value Number WKT JSON parse | 557.69 | — | — | 2757.03 (4.94x) | 2097.25 (3.76x) |
| Any ZeroUInt64Value WKT JSON stringify | 168.62 | — | — | 929.74 (5.51x) | 1183.29 (7.02x) |
| Any ZeroUInt64Value WKT JSON parse | 535.67 | — | — | 2154.80 (4.02x) | 1784.63 (3.33x) |
| Any MaxUInt64Value WKT JSON stringify | 180.84 | — | — | 1558.55 (8.62x) | 838.09 (4.63x) |
| Any MaxUInt64Value WKT JSON parse | 567.91 | — | — | 2823.16 (4.97x) | 1622.60 (2.86x) |
| Any Int32Value WKT JSON stringify | 174.51 | — | — | 1548.04 (8.87x) | 753.22 (4.32x) |
| Any Int32Value WKT JSON parse | 540.26 | — | — | 2655.85 (4.92x) | 1579.00 (2.92x) |
| Any Int32Value String WKT JSON parse | 550.14 | — | — | 2665.94 (4.85x) | 1777.51 (3.23x) |
| Any ZeroInt32Value WKT JSON stringify | 169.80 | — | — | 917.69 (5.40x) | 671.14 (3.95x) |
| Any ZeroInt32Value WKT JSON parse | 534.29 | — | — | 2138.55 (4.00x) | 1509.39 (2.83x) |
| Any NegativeInt32Value WKT JSON stringify | 174.93 | — | — | 1546.38 (8.84x) | 726.81 (4.15x) |
| Any NegativeInt32Value WKT JSON parse | 539.58 | — | — | 2682.58 (4.97x) | 1465.87 (2.72x) |
| Any MinInt32Value WKT JSON stringify | 178.86 | — | — | 1547.34 (8.65x) | 744.20 (4.16x) |
| Any MinInt32Value WKT JSON parse | 549.21 | — | — | 2703.10 (4.92x) | 1466.05 (2.67x) |
| Any MaxInt32Value WKT JSON stringify | 182.13 | — | — | 1544.74 (8.48x) | 736.13 (4.04x) |
| Any MaxInt32Value WKT JSON parse | 548.72 | — | — | 2673.37 (4.87x) | 1533.99 (2.80x) |
| Any UInt32Value WKT JSON stringify | 180.03 | — | — | 1552.75 (8.62x) | 749.41 (4.16x) |
| Any UInt32Value WKT JSON parse | 543.75 | — | — | 2664.83 (4.90x) | 1477.36 (2.72x) |
| Any UInt32Value String WKT JSON parse | 553.62 | — | — | 2669.46 (4.82x) | 1651.98 (2.98x) |
| Any ZeroUInt32Value WKT JSON stringify | 174.72 | — | — | 915.07 (5.24x) | 716.56 (4.10x) |
| Any ZeroUInt32Value WKT JSON parse | 539.17 | — | — | 2152.65 (3.99x) | 1443.25 (2.68x) |
| Any MaxUInt32Value WKT JSON stringify | 177.76 | — | — | 1543.49 (8.68x) | 767.87 (4.32x) |
| Any MaxUInt32Value WKT JSON parse | 550.00 | — | — | 2677.24 (4.87x) | 1606.45 (2.92x) |
| Any BoolValue WKT JSON stringify | 166.19 | — | — | 1523.40 (9.17x) | 701.02 (4.22x) |
| Any BoolValue WKT JSON parse | 492.37 | — | — | 2592.04 (5.26x) | 1328.90 (2.70x) |
| Any FalseBoolValue WKT JSON stringify | 176.15 | — | — | 918.98 (5.22x) | 695.74 (3.95x) |
| Any FalseBoolValue WKT JSON parse | 493.69 | — | — | 2133.89 (4.32x) | 1237.11 (2.51x) |
| Any StringValue WKT JSON stringify | 196.26 | — | — | 1556.07 (7.93x) | 817.27 (4.16x) |
| Any StringValue WKT JSON parse | 561.68 | — | — | 2644.98 (4.71x) | 1309.29 (2.33x) |
| Any StringValue Escape WKT JSON parse | 566.21 | — | — | 2675.22 (4.72x) | 1418.61 (2.51x) |
| Any EmptyStringValue WKT JSON stringify | 189.05 | — | — | 915.78 (4.84x) | 743.87 (3.93x) |
| Any EmptyStringValue WKT JSON parse | 529.58 | — | — | 2136.37 (4.03x) | 1362.68 (2.57x) |
| Any BytesValue WKT JSON stringify | 184.37 | — | — | 1580.13 (8.57x) | 841.70 (4.57x) |
| Any BytesValue WKT JSON parse | 569.30 | — | — | 2668.99 (4.69x) | 1419.54 (2.49x) |
| Any BytesValue URL WKT JSON parse | 587.97 | — | — | 2676.97 (4.55x) | 1451.02 (2.47x) |
| Any EmptyBytesValue WKT JSON stringify | 187.00 | — | — | 914.36 (4.89x) | 732.68 (3.92x) |
| Any EmptyBytesValue WKT JSON parse | 534.00 | — | — | 2156.01 (4.04x) | 1392.64 (2.61x) |
| Nested Any WKT JSON stringify | 300.17 | — | — | 2464.38 (8.21x) | 1432.55 (4.77x) |
| Nested Any WKT JSON parse | 865.04 | — | — | 4268.24 (4.93x) | 2701.59 (3.12x) |
| Duration JSON stringify | 57.86 | — | — | 959.42 (16.58x) | 351.30 (6.07x) |
| Duration JSON parse | 7.78 | — | — | 1446.01 (185.86x) | 377.37 (48.51x) |
| PlusDuration JSON parse | 7.81 | — | — | 1451.09 (185.80x) | 422.07 (54.04x) |
| ShortFractionDuration JSON parse | 6.78 | — | — | 1420.99 (209.59x) | 376.56 (55.54x) |
| MicroDuration JSON stringify | 59.32 | — | — | 972.27 (16.39x) | 385.30 (6.50x) |
| MicroDuration JSON parse | 9.83 | — | — | 1467.21 (149.26x) | 368.83 (37.52x) |
| NanoDuration JSON stringify | 56.63 | — | — | 998.76 (17.64x) | 398.50 (7.04x) |
| NanoDuration JSON parse | 12.43 | — | — | 1480.90 (119.14x) | 383.86 (30.88x) |
| NegativeDuration JSON stringify | 57.80 | — | — | 1013.61 (17.54x) | 401.74 (6.95x) |
| NegativeDuration JSON parse | 8.04 | — | — | 1513.74 (188.28x) | 372.15 (46.29x) |
| FractionalNegativeDuration JSON stringify | 57.80 | — | — | 968.65 (16.76x) | 392.11 (6.78x) |
| FractionalNegativeDuration JSON parse | 9.03 | — | — | 1460.06 (161.69x) | 351.86 (38.97x) |
| MaxDuration JSON stringify | 49.19 | — | — | 858.05 (17.44x) | 381.82 (7.76x) |
| MaxDuration JSON parse | 24.66 | — | — | 1439.37 (58.37x) | 380.98 (15.45x) |
| MinDuration JSON stringify | 49.52 | — | — | 872.13 (17.61x) | 422.98 (8.54x) |
| MinDuration JSON parse | 22.51 | — | — | 1453.39 (64.57x) | 382.42 (16.99x) |
| ZeroDuration JSON stringify | 44.36 | — | — | 818.49 (18.45x) | 349.46 (7.88x) |
| ZeroDuration JSON parse | 5.59 | — | — | 1369.09 (244.92x) | 300.28 (53.72x) |
| FieldMask JSON stringify | 75.96 | — | — | 884.07 (11.64x) | 645.69 (8.50x) |
| FieldMask JSON parse | 152.72 | — | — | 1651.27 (10.81x) | 817.60 (5.35x) |
| EmptyFieldMask JSON stringify | 40.66 | — | — | 619.77 (15.24x) | 185.51 (4.56x) |
| EmptyFieldMask JSON parse | 2.40 | — | — | 940.88 (392.03x) | 156.63 (65.26x) |
| Timestamp JSON stringify | 95.83 | — | — | 1145.60 (11.95x) | 403.62 (4.21x) |
| Timestamp JSON parse | 41.13 | — | — | 1483.86 (36.08x) | 435.32 (10.58x) |
| ShortFraction Timestamp JSON parse | 39.75 | — | — | 1474.83 (37.10x) | 412.33 (10.37x) |
| Micro Timestamp JSON stringify | 95.72 | — | — | 1141.68 (11.93x) | 423.88 (4.43x) |
| Micro Timestamp JSON parse | 42.90 | — | — | 1492.21 (34.78x) | 483.01 (11.26x) |
| Nano Timestamp JSON stringify | 93.55 | — | — | 1181.32 (12.63x) | 426.25 (4.56x) |
| Nano Timestamp JSON parse | 44.84 | — | — | 1512.03 (33.72x) | 440.51 (9.82x) |
| Offset Timestamp JSON parse | 50.27 | — | — | 1534.79 (30.53x) | 456.37 (9.08x) |
| PreEpoch Timestamp JSON stringify | 66.07 | — | — | 1066.30 (16.14x) | 434.78 (6.58x) |
| PreEpoch Timestamp JSON parse | 39.98 | — | — | 1454.38 (36.38x) | 403.79 (10.10x) |
| Max Timestamp JSON stringify | 78.68 | — | — | 1193.22 (15.17x) | 423.31 (5.38x) |
| Max Timestamp JSON parse | 46.98 | — | — | 1526.44 (32.49x) | 448.85 (9.55x) |
| Min Timestamp JSON stringify | 80.18 | — | — | 1048.80 (13.08x) | 426.01 (5.31x) |
| Min Timestamp JSON parse | 37.82 | — | — | 1444.84 (38.20x) | 420.89 (11.13x) |
| Empty JSON stringify | 20.33 | — | — | 509.48 (25.06x) | 78.71 (3.87x) |
| Empty JSON parse | 67.23 | — | — | 731.37 (10.88x) | 216.51 (3.22x) |
| Struct JSON stringify | 174.76 | — | — | 5714.50 (32.70x) | 2908.33 (16.64x) |
| Struct JSON parse | 857.30 | — | — | 10846.80 (12.65x) | 4762.85 (5.56x) |
| EmptyStruct JSON stringify | 40.67 | — | — | 699.64 (17.20x) | 343.84 (8.45x) |
| EmptyStruct JSON parse | 89.72 | — | — | 2018.86 (22.50x) | 357.25 (3.98x) |
| Value JSON stringify | 174.45 | — | — | 6624.94 (37.98x) | 3101.02 (17.78x) |
| Value JSON parse | 879.46 | — | — | 12078.70 (13.73x) | 4755.75 (5.41x) |
| NullValue JSON stringify | 39.99 | — | — | 1314.57 (32.87x) | 219.78 (5.50x) |
| NullValue JSON parse | 66.66 | — | — | 2461.46 (36.93x) | 327.15 (4.91x) |
| StringScalarValue JSON stringify | 47.66 | — | — | 1342.22 (28.16x) | 267.94 (5.62x) |
| StringScalarValue JSON parse | 136.68 | — | — | 2071.18 (15.15x) | 420.19 (3.07x) |
| EmptyStringScalarValue JSON stringify | 45.92 | — | — | 1327.93 (28.92x) | 263.04 (5.73x) |
| EmptyStringScalarValue JSON parse | 83.79 | — | — | 2048.02 (24.44x) | 350.66 (4.18x) |
| NumberValue JSON stringify | 75.49 | — | — | 1557.44 (20.63x) | 338.74 (4.49x) |
| NumberValue JSON parse | 129.05 | — | — | 2151.84 (16.67x) | 399.62 (3.10x) |
| ZeroNumberValue JSON stringify | 52.83 | — | — | 1503.32 (28.46x) | 275.82 (5.22x) |
| ZeroNumberValue JSON parse | 126.46 | — | — | 2095.99 (16.57x) | 381.34 (3.02x) |
| BoolScalarValue JSON stringify | 39.87 | — | — | 1318.21 (33.06x) | 227.44 (5.70x) |
| BoolScalarValue JSON parse | 66.66 | — | — | 1999.28 (29.99x) | 317.04 (4.76x) |
| FalseBoolScalarValue JSON stringify | 39.84 | — | — | 1308.03 (32.83x) | 210.17 (5.28x) |
| FalseBoolScalarValue JSON parse | 67.16 | — | — | 2003.72 (29.84x) | 299.36 (4.46x) |
| ListKindValue JSON stringify | 138.14 | — | — | 6120.05 (44.30x) | 2187.53 (15.84x) |
| ListKindValue JSON parse | 669.62 | — | — | 10398.40 (15.53x) | 4297.49 (6.42x) |
| EmptyStructKindValue JSON stringify | 42.55 | — | — | 1931.29 (45.39x) | 513.82 (12.08x) |
| EmptyStructKindValue JSON parse | 106.81 | — | — | 3715.01 (34.78x) | 663.96 (6.22x) |
| EmptyListKindValue JSON stringify | 40.84 | — | — | 1917.14 (46.94x) | 345.13 (8.45x) |
| EmptyListKindValue JSON parse | 144.75 | — | — | 3998.72 (27.63x) | 600.50 (4.15x) |
| ListValue JSON stringify | 139.89 | — | — | 4722.32 (33.76x) | 2127.88 (15.21x) |
| ListValue JSON parse | 666.64 | — | — | 8470.37 (12.71x) | 3865.67 (5.80x) |
| EmptyListValue JSON stringify | 40.14 | — | — | 684.68 (17.06x) | 185.14 (4.61x) |
| EmptyListValue JSON parse | 126.31 | — | — | 2244.74 (17.77x) | 298.78 (2.37x) |
| DoubleValue JSON stringify | 67.75 | — | — | 850.38 (12.55x) | 185.18 (2.73x) |
| DoubleValue JSON parse | 110.30 | — | — | 1231.79 (11.17x) | 280.21 (2.54x) |
| DoubleValue String JSON parse | 112.23 | — | — | 1167.43 (10.40x) | 376.57 (3.36x) |
| NegativeDoubleValue JSON stringify | 67.69 | — | — | 855.86 (12.64x) | 186.86 (2.76x) |
| NegativeDoubleValue JSON parse | 110.68 | — | — | 1234.80 (11.16x) | 281.32 (2.54x) |
| ZeroDoubleValue JSON stringify | 47.06 | — | — | 792.86 (16.85x) | 161.96 (3.44x) |
| ZeroDoubleValue JSON parse | 107.56 | — | — | 1165.15 (10.83x) | 268.68 (2.50x) |
| DoubleValue NaN JSON stringify | 46.38 | — | — | 659.50 (14.22x) | 118.04 (2.55x) |
| DoubleValue NaN JSON parse | 105.27 | — | — | 1091.97 (10.37x) | 254.89 (2.42x) |
| DoubleValue Infinity JSON stringify | 47.88 | — | — | 659.38 (13.77x) | 136.74 (2.86x) |
| DoubleValue Infinity JSON parse | 106.11 | — | — | 1103.21 (10.40x) | 260.08 (2.45x) |
| DoubleValue NegativeInfinity JSON stringify | 48.13 | — | — | 652.11 (13.55x) | 121.96 (2.53x) |
| DoubleValue NegativeInfinity JSON parse | 108.40 | — | — | 1119.98 (10.33x) | 255.02 (2.35x) |
| FloatValue JSON stringify | 71.07 | — | — | 846.26 (11.91x) | 197.51 (2.78x) |
| FloatValue JSON parse | 110.40 | — | — | 1212.51 (10.98x) | 278.08 (2.52x) |
| FloatValue String JSON parse | 109.94 | — | — | 1191.74 (10.84x) | 347.82 (3.16x) |
| NegativeFloatValue JSON stringify | 70.50 | — | — | 851.37 (12.08x) | 175.10 (2.48x) |
| NegativeFloatValue JSON parse | 111.52 | — | — | 1228.60 (11.02x) | 270.71 (2.43x) |
| ZeroFloatValue JSON stringify | 46.90 | — | — | 792.81 (16.90x) | 131.89 (2.81x) |
| ZeroFloatValue JSON parse | 109.22 | — | — | 1153.65 (10.56x) | 243.08 (2.23x) |
| FloatValue NaN JSON stringify | 46.39 | — | — | 638.11 (13.76x) | 126.44 (2.73x) |
| FloatValue NaN JSON parse | 105.21 | — | — | 1081.44 (10.28x) | 257.07 (2.44x) |
| FloatValue Infinity JSON stringify | 48.13 | — | — | 640.11 (13.30x) | 128.07 (2.66x) |
| FloatValue Infinity JSON parse | 106.34 | — | — | 1091.75 (10.27x) | 253.06 (2.38x) |
| FloatValue NegativeInfinity JSON stringify | 48.22 | — | — | 635.20 (13.17x) | 118.21 (2.45x) |
| FloatValue NegativeInfinity JSON parse | 107.91 | — | — | 1094.72 (10.14x) | 271.20 (2.51x) |
| Int64Value JSON stringify | 49.93 | — | — | 678.23 (13.58x) | 278.95 (5.59x) |
| Int64Value JSON parse | 126.17 | — | — | 1236.21 (9.80x) | 457.14 (3.62x) |
| Int64Value Number JSON parse | 127.55 | — | — | 1292.56 (10.13x) | 363.41 (2.85x) |
| ZeroInt64Value JSON stringify | 41.45 | — | — | 609.79 (14.71x) | 197.64 (4.77x) |
| ZeroInt64Value JSON parse | 106.48 | — | — | 1096.66 (10.30x) | 332.96 (3.13x) |
| NegativeInt64Value JSON stringify | 48.50 | — | — | 672.73 (13.87x) | 267.49 (5.52x) |
| NegativeInt64Value JSON parse | 127.32 | — | — | 1211.97 (9.52x) | 481.48 (3.78x) |
| MinInt64Value JSON stringify | 50.00 | — | — | 680.50 (13.61x) | 276.55 (5.53x) |
| MinInt64Value JSON parse | 132.83 | — | — | 1245.35 (9.38x) | 474.46 (3.57x) |
| MaxInt64Value JSON stringify | 50.12 | — | — | 675.80 (13.48x) | 269.87 (5.38x) |
| MaxInt64Value JSON parse | 134.11 | — | — | 1246.44 (9.29x) | 458.21 (3.42x) |
| UInt64Value JSON stringify | 50.55 | — | — | 675.41 (13.36x) | 266.64 (5.27x) |
| UInt64Value JSON parse | 124.22 | — | — | 1220.79 (9.83x) | 430.70 (3.47x) |
| UInt64Value Number JSON parse | 127.97 | — | — | 1279.35 (10.00x) | 361.59 (2.83x) |
| ZeroUInt64Value JSON stringify | 41.45 | — | — | 610.18 (14.72x) | 224.92 (5.43x) |
| ZeroUInt64Value JSON parse | 105.82 | — | — | 1093.04 (10.33x) | 352.69 (3.33x) |
| MaxUInt64Value JSON stringify | 49.32 | — | — | 674.65 (13.68x) | 304.90 (6.18x) |
| MaxUInt64Value JSON parse | 136.91 | — | — | 1248.82 (9.12x) | 489.01 (3.57x) |
| Int32Value JSON stringify | 51.23 | — | — | 633.68 (12.37x) | 148.86 (2.91x) |
| Int32Value JSON parse | 148.59 | — | — | 1187.65 (7.99x) | 298.96 (2.01x) |
| Int32Value String JSON parse | 143.49 | — | — | 1133.10 (7.90x) | 374.33 (2.61x) |
| ZeroInt32Value JSON stringify | 63.18 | — | — | 614.73 (9.73x) | 135.42 (2.14x) |
| ZeroInt32Value JSON parse | 137.27 | — | — | 1149.29 (8.37x) | 290.10 (2.11x) |
| NegativeInt32Value JSON stringify | 64.15 | — | — | 640.74 (9.99x) | 130.07 (2.03x) |
| NegativeInt32Value JSON parse | 147.62 | — | — | 1191.27 (8.07x) | 317.61 (2.15x) |
| MinInt32Value JSON stringify | 65.26 | — | — | 638.02 (9.78x) | 146.58 (2.25x) |
| MinInt32Value JSON parse | 167.37 | — | — | 1213.78 (7.25x) | 332.79 (1.99x) |
| MaxInt32Value JSON stringify | 65.18 | — | — | 633.41 (9.72x) | 133.01 (2.04x) |
| MaxInt32Value JSON parse | 170.85 | — | — | 1210.14 (7.08x) | 326.10 (1.91x) |
| UInt32Value JSON stringify | 64.19 | — | — | 631.51 (9.84x) | 155.57 (2.42x) |
| UInt32Value JSON parse | 149.53 | — | — | 1179.66 (7.89x) | 312.23 (2.09x) |
| UInt32Value String JSON parse | 118.15 | — | — | 1124.08 (9.51x) | 413.76 (3.50x) |
| ZeroUInt32Value JSON stringify | 63.69 | — | — | 612.39 (9.62x) | 146.76 (2.30x) |
| ZeroUInt32Value JSON parse | 138.10 | — | — | 1157.72 (8.38x) | 264.67 (1.92x) |
| MaxUInt32Value JSON stringify | 64.70 | — | — | 635.76 (9.83x) | 135.57 (2.10x) |
| MaxUInt32Value JSON parse | 138.17 | — | — | 1222.90 (8.85x) | 332.43 (2.41x) |
| BoolValue JSON stringify | 57.54 | — | — | 615.93 (10.70x) | 117.90 (2.05x) |
| BoolValue JSON parse | 73.29 | — | — | 1057.11 (14.42x) | 221.13 (3.02x) |
| FalseBoolValue JSON stringify | 57.41 | — | — | 606.76 (10.57x) | 125.11 (2.18x) |
| FalseBoolValue JSON parse | 62.86 | — | — | 1059.32 (16.85x) | 221.38 (3.52x) |
| StringValue JSON stringify | 58.52 | — | — | 669.92 (11.45x) | 182.01 (3.11x) |
| StringValue JSON parse | 121.04 | — | — | 1139.23 (9.41x) | 292.83 (2.42x) |
| StringValue Escape JSON parse | 131.75 | — | — | 1167.27 (8.86x) | 323.49 (2.46x) |
| EmptyStringValue JSON stringify | 52.67 | — | — | 619.69 (11.77x) | 168.11 (3.19x) |
| EmptyStringValue JSON parse | 63.82 | — | — | 1112.65 (17.43x) | 214.47 (3.36x) |
| BytesValue JSON stringify | 48.85 | — | — | 661.76 (13.55x) | 220.75 (4.52x) |
| BytesValue JSON parse | 127.01 | — | — | 1190.28 (9.37x) | 332.44 (2.62x) |
| BytesValue URL JSON parse | 143.72 | — | — | 1180.49 (8.21x) | 299.48 (2.08x) |
| EmptyBytesValue JSON stringify | 41.73 | — | — | 631.70 (15.14x) | 198.77 (4.76x) |
| EmptyBytesValue JSON parse | 66.37 | — | — | 1122.83 (16.92x) | 262.92 (3.96x) |
| TextFormat format | 236.09 | — | — | 2589.73 (10.97x) | 2370.70 (10.04x) |
| TextFormat parse | 847.63 | — | — | 5002.12 (5.90x) | 6377.23 (7.52x) |
| packed fixed32 encode | 2.00 | 560.17 (280.08x) | 539.91 (269.95x) | 45.67 (22.83x) | 410.77 (205.38x) |
| packed fixed32 decode | 4.54 | 1041.75 (229.46x) | 1950.27 (429.57x) | 51.15 (11.27x) | 1681.34 (370.34x) |
| packed fixed64 encode | 2.01 | 575.63 (286.38x) | 561.06 (279.13x) | 75.96 (37.79x) | 398.73 (198.37x) |
| packed fixed64 decode | 4.53 | 1027.16 (226.75x) | 7947.56 (1754.43x) | 80.81 (17.84x) | 2638.52 (582.45x) |
| packed sfixed32 encode | 2.01 | 555.85 (276.54x) | 539.49 (268.40x) | 44.41 (22.09x) | 406.11 (202.04x) |
| packed sfixed32 decode | 4.52 | 1064.68 (235.55x) | 1958.89 (433.38x) | 49.34 (10.92x) | 1746.20 (386.33x) |
| packed sfixed64 encode | 2.01 | 577.26 (287.19x) | 560.96 (279.08x) | 76.16 (37.89x) | 390.99 (194.52x) |
| packed sfixed64 decode | 4.55 | 1016.39 (223.38x) | 7902.09 (1736.72x) | 79.78 (17.53x) | 2400.51 (527.58x) |
| packed float encode | 2.01 | 813.90 (404.93x) | 539.51 (268.41x) | 43.98 (21.88x) | 384.09 (191.09x) |
| packed float decode | 4.53 | 1063.96 (234.87x) | 2086.94 (460.69x) | 49.58 (10.95x) | 1740.77 (384.28x) |
| packed double encode | 2.01 | 838.07 (416.95x) | 561.96 (279.58x) | 75.95 (37.79x) | 355.31 (176.77x) |
| packed double decode | 4.56 | 982.01 (215.35x) | 2042.90 (448.00x) | 80.24 (17.60x) | 2574.86 (564.66x) |
| packed uint64 encode | 1287.09 | 4617.38 (3.59x) | 4024.56 (3.13x) | 2143.23 (1.67x) | 3442.37 (2.67x) |
| packed uint64 decode | 1789.50 | 2795.53 (1.56x) | 8846.80 (4.94x) | 2828.06 (1.58x) | 8798.08 (4.92x) |
| packed uint32 encode | 926.13 | 3612.46 (3.90x) | 3251.30 (3.51x) | 1731.08 (1.87x) | 2940.24 (3.17x) |
| packed uint32 decode | 1292.00 | 2430.04 (1.88x) | 3263.57 (2.53x) | 1994.42 (1.54x) | 6203.88 (4.80x) |
| packed int64 encode | 1412.56 | 11308.81 (8.01x) | 6055.21 (4.29x) | 2908.56 (2.06x) | 4121.40 (2.92x) |
| packed int64 decode | 2738.57 | 3379.14 (1.23x) | 10283.41 (3.76x) | 4667.05 (1.70x) | 10534.42 (3.85x) |
| packed sint32 encode | 781.79 | 3078.82 (3.94x) | 2769.37 (3.54x) | 1534.65 (1.96x) | 3392.65 (4.34x) |
| packed sint32 decode | 952.76 | 2545.97 (2.67x) | 3201.33 (3.36x) | 1149.87 (1.21x) | 4441.80 (4.66x) |
| packed sint64 encode | 1425.01 | 4966.66 (3.49x) | 4462.51 (3.13x) | 2434.31 (1.71x) | 4475.13 (3.14x) |
| packed sint64 decode | 2036.98 | 3062.60 (1.50x) | 9656.17 (4.74x) | 2933.47 (1.44x) | 9658.27 (4.74x) |
| packed bool encode | 2.01 | 1327.86 (660.63x) | 519.88 (258.65x) | 17.04 (8.48x) | 2211.50 (1100.25x) |
| packed bool decode | 263.06 | 1539.88 (5.85x) | 2547.41 (9.68x) | 818.14 (3.11x) | 1820.68 (6.92x) |
| packed enum encode | 271.99 | 2727.95 (10.03x) | 1814.02 (6.67x) | 1086.54 (3.99x) | 2599.59 (9.56x) |
| packed enum decode | 152.49 | 1529.49 (10.03x) | 2846.57 (18.67x) | 682.64 (4.48x) | 2132.73 (13.99x) |
| large map encode | 3937.81 | 16781.22 (4.26x) | 9775.56 (2.48x) | 21189.30 (5.38x) | 195904.73 (49.75x) |
| shuffled large map deterministic binary encode | 28595.86 | — | — | 92149.20 (3.22x) | 375696.27 (13.14x) |
| large map decode | 25338.93 | 90584.89 (3.57x) | 97877.77 (3.86x) | 95082.30 (3.75x) | 277804.44 (10.96x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded zero/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound `Duration`, non-empty and empty `Struct`, object/list/scalar `Value` (including default-like scalar and empty object/list kinds),
`FieldMask` (non-empty and empty), short-fraction parse/micro/nano/offset/min/pre/post/max-bound `Timestamp`, `Empty`, min/zero/positive/number-input parse/negative/max `Int64Value`, negative/zero/positive finite/string-input parse `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), negative/zero/positive finite/string-input parse `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), zero/normal/number-input parse/max `UInt64Value`, min/zero/positive/string-input parse/negative/max `Int32Value`, zero/normal/string-input parse/max `UInt32Value`, true/false `BoolValue`, non-empty/escape-input parse/empty `StringValue`, base64/base64url parse/empty `BytesValue`, and recursive nested `Any` payloads), direct zero/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound Duration and short-fraction parse/micro/nano/offset/min/pre/post/max-bound Timestamp WKT JSON plus other direct WKT JSON, including empty `Struct` and empty `ListValue`, TextFormat, packed scalars, large bytes,
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
