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

Latest accepted comparison (`/tmp/pbz-compare-float-string-wrapper-json-isolated.log`,
summarized in `/tmp/pbz-summary-float-string-wrapper-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 16.96 | 100.47 (5.92x) | 53.74 (3.17x) | 107.36 (6.33x) | 873.03 (51.48x) |
| binary decode | 89.26 | 248.02 (2.78x) | 232.43 (2.60x) | 233.53 (2.62x) | 880.91 (9.87x) |
| unknown fields count by number | 3.58 | — | — | 161.88 (45.22x) | — |
| deterministic binary encode | 75.53 | — | — | 129.74 (1.72x) | 1041.12 (13.78x) |
| scalarmix encode | 19.05 | 102.24 (5.37x) | 48.05 (2.52x) | 31.41 (1.65x) | 233.92 (12.28x) |
| scalarmix decode | 39.09 | 132.46 (3.39x) | 174.83 (4.47x) | 85.91 (2.20x) | 271.22 (6.94x) |
| textbytes encode | 11.53 | 79.55 (6.90x) | 37.75 (3.27x) | 116.44 (10.10x) | 156.52 (13.58x) |
| textbytes decode | 43.08 | 380.42 (8.83x) | 240.70 (5.59x) | 164.70 (3.82x) | 624.99 (14.51x) |
| largebytes encode | 17.80 | 2702.09 (151.80x) | 2678.39 (150.47x) | 2681.12 (150.62x) | 2778.82 (156.11x) |
| largebytes decode | 94.26 | 5576.00 (59.16x) | 3125.24 (33.16x) | 2724.96 (28.91x) | 24757.00 (262.65x) |
| presencemix encode | 16.65 | 56.77 (3.41x) | 26.66 (1.60x) | 57.24 (3.44x) | 228.27 (13.71x) |
| presencemix decode | 55.93 | 132.61 (2.37x) | 110.83 (1.98x) | 164.78 (2.95x) | 479.36 (8.57x) |
| complex encode | 52.42 | 138.82 (2.65x) | 95.77 (1.83x) | 167.35 (3.19x) | 918.75 (17.53x) |
| complex decode | 169.38 | 398.28 (2.35x) | 348.35 (2.06x) | 403.92 (2.38x) | 1309.14 (7.73x) |
| complex deterministic binary encode | 94.41 | — | — | 172.46 (1.83x) | 1089.49 (11.54x) |
| complex JSON stringify | 261.47 | — | — | 4933.14 (18.87x) | 5857.70 (22.40x) |
| complex JSON parse | 2399.55 | — | — | 11954.50 (4.98x) | 6712.89 (2.80x) |
| complex TextFormat format | 262.73 | — | — | 3773.65 (14.36x) | 5238.91 (19.94x) |
| complex TextFormat parse | 1757.80 | — | — | 6889.08 (3.92x) | 8230.60 (4.68x) |
| packed int32 encode | 641.86 | 3181.96 (4.96x) | 2505.74 (3.90x) | 1250.86 (1.95x) | 2745.20 (4.28x) |
| packed int32 decode | 764.95 | 1892.22 (2.47x) | 3220.52 (4.21x) | 959.05 (1.25x) | 3443.64 (4.50x) |
| JSON stringify | 158.17 | — | — | 3078.72 (19.46x) | 2077.72 (13.14x) |
| JSON parse | 1523.63 | — | — | 7437.98 (4.88x) | 4386.85 (2.88x) |
| Any WKT JSON stringify | 126.16 | — | — | 1892.08 (15.00x) | 1049.82 (8.32x) |
| Any WKT JSON parse | 524.04 | — | — | 2974.14 (5.68x) | 1381.81 (2.64x) |
| Any PlusDuration WKT JSON parse | 528.52 | — | — | 3003.24 (5.68x) | 1505.22 (2.85x) |
| Any ShortFractionDuration WKT JSON parse | 524.57 | — | — | 2948.32 (5.62x) | 1421.50 (2.71x) |
| Any MicroDuration WKT JSON stringify | 132.09 | — | — | 1909.36 (14.45x) | 1011.56 (7.66x) |
| Any MicroDuration WKT JSON parse | 529.44 | — | — | 3002.82 (5.67x) | 1418.09 (2.68x) |
| Any NanoDuration WKT JSON stringify | 125.25 | — | — | 1925.47 (15.37x) | 927.21 (7.40x) |
| Any NanoDuration WKT JSON parse | 534.99 | — | — | 2995.69 (5.60x) | 1582.15 (2.96x) |
| Any NegativeDuration WKT JSON stringify | 132.31 | — | — | 1960.79 (14.82x) | 951.11 (7.19x) |
| Any NegativeDuration WKT JSON parse | 529.83 | — | — | 3092.74 (5.84x) | 1432.61 (2.70x) |
| Any FractionalNegativeDuration WKT JSON stringify | 123.63 | — | — | 1897.47 (15.35x) | 964.80 (7.80x) |
| Any FractionalNegativeDuration WKT JSON parse | 524.76 | — | — | 3042.08 (5.80x) | 1541.41 (2.94x) |
| Any MaxDuration WKT JSON stringify | 117.26 | — | — | 1771.22 (15.11x) | 936.49 (7.99x) |
| Any MaxDuration WKT JSON parse | 541.06 | — | — | 3027.41 (5.60x) | 1592.32 (2.94x) |
| Any MinDuration WKT JSON stringify | 119.59 | — | — | 1771.78 (14.82x) | 991.01 (8.29x) |
| Any MinDuration WKT JSON parse | 545.32 | — | — | 3009.99 (5.52x) | 1484.85 (2.72x) |
| Any ZeroDuration WKT JSON stringify | 106.75 | — | — | 933.04 (8.74x) | 986.76 (9.24x) |
| Any ZeroDuration WKT JSON parse | 476.56 | — | — | 2251.81 (4.73x) | 1339.96 (2.81x) |
| Any FieldMask WKT JSON stringify | 238.50 | — | — | 1746.48 (7.32x) | 1400.16 (5.87x) |
| Any FieldMask WKT JSON parse | 730.47 | — | — | 3143.56 (4.30x) | 1882.75 (2.58x) |
| Any EmptyFieldMask WKT JSON stringify | 111.53 | — | — | 924.53 (8.29x) | 777.43 (6.97x) |
| Any EmptyFieldMask WKT JSON parse | 457.55 | — | — | 2142.78 (4.68x) | 1251.24 (2.73x) |
| Any Timestamp WKT JSON stringify | 180.86 | — | — | 2025.56 (11.20x) | 982.26 (5.43x) |
| Any Timestamp WKT JSON parse | 582.59 | — | — | 3039.87 (5.22x) | 1481.14 (2.54x) |
| Any Micro Timestamp WKT JSON stringify | 179.33 | — | — | 2047.82 (11.42x) | 1022.32 (5.70x) |
| Any Micro Timestamp WKT JSON parse | 582.15 | — | — | 3032.24 (5.21x) | 1630.91 (2.80x) |
| Any Nano Timestamp WKT JSON stringify | 178.20 | — | — | 2036.44 (11.43x) | 1003.56 (5.63x) |
| Any Nano Timestamp WKT JSON parse | 591.48 | — | — | 3055.54 (5.17x) | 1668.63 (2.82x) |
| Any Offset Timestamp WKT JSON parse | 594.31 | — | — | 3145.26 (5.29x) | 1672.69 (2.81x) |
| Any PreEpoch Timestamp WKT JSON stringify | 142.42 | — | — | 1945.41 (13.66x) | 941.44 (6.61x) |
| Any PreEpoch Timestamp WKT JSON parse | 573.24 | — | — | 3062.35 (5.34x) | 1452.46 (2.53x) |
| Any Max Timestamp WKT JSON stringify | 162.17 | — | — | 2053.78 (12.66x) | 989.79 (6.10x) |
| Any Max Timestamp WKT JSON parse | 593.01 | — | — | 3126.98 (5.27x) | 1502.72 (2.53x) |
| Any Min Timestamp WKT JSON stringify | 154.22 | — | — | 1948.54 (12.63x) | 938.53 (6.09x) |
| Any Min Timestamp WKT JSON parse | 570.72 | — | — | 3018.79 (5.29x) | 1510.26 (2.65x) |
| Any Empty WKT JSON stringify | 88.37 | — | — | 923.93 (10.46x) | 641.42 (7.26x) |
| Any Empty WKT JSON parse | 339.38 | — | — | 2121.91 (6.25x) | 1337.64 (3.94x) |
| Any Struct WKT JSON stringify | 640.62 | — | — | 5803.98 (9.06x) | 5978.15 (9.33x) |
| Any Struct WKT JSON parse | 1770.91 | — | — | 11106.60 (6.27x) | 8342.85 (4.71x) |
| Any EmptyStruct WKT JSON stringify | 118.80 | — | — | 912.14 (7.68x) | 907.37 (7.64x) |
| Any EmptyStruct WKT JSON parse | 451.49 | — | — | 2245.17 (4.97x) | 1549.46 (3.43x) |
| Any Value WKT JSON stringify | 666.58 | — | — | 5907.34 (8.86x) | 6351.13 (9.53x) |
| Any Value WKT JSON parse | 1825.44 | — | — | 11320.40 (6.20x) | 8660.86 (4.74x) |
| Any NullValue WKT JSON stringify | 134.58 | — | — | 2248.89 (16.71x) | 923.67 (6.86x) |
| Any NullValue WKT JSON parse | 467.85 | — | — | 4038.37 (8.63x) | 1467.51 (3.14x) |
| Any StringScalarValue WKT JSON stringify | 150.93 | — | — | 2263.31 (15.00x) | 1047.40 (6.94x) |
| Any StringScalarValue WKT JSON parse | 528.78 | — | — | 3613.82 (6.83x) | 1544.70 (2.92x) |
| Any EmptyStringScalarValue WKT JSON stringify | 142.07 | — | — | 2281.38 (16.06x) | 1001.05 (7.05x) |
| Any EmptyStringScalarValue WKT JSON parse | 493.54 | — | — | 3599.07 (7.29x) | 1471.31 (2.98x) |
| Any NumberValue WKT JSON stringify | 175.25 | — | — | 2521.20 (14.39x) | 1004.35 (5.73x) |
| Any NumberValue WKT JSON parse | 508.48 | — | — | 3655.14 (7.19x) | 1480.53 (2.91x) |
| Any ZeroNumberValue WKT JSON stringify | 138.09 | — | — | 2464.78 (17.85x) | 997.07 (7.22x) |
| Any ZeroNumberValue WKT JSON parse | 504.91 | — | — | 3603.70 (7.14x) | 1515.43 (3.00x) |
| Any BoolScalarValue WKT JSON stringify | 130.76 | — | — | 2250.24 (17.21x) | 855.70 (6.54x) |
| Any BoolScalarValue WKT JSON parse | 469.41 | — | — | 3600.38 (7.67x) | 1458.04 (3.11x) |
| Any FalseBoolScalarValue WKT JSON stringify | 132.41 | — | — | 2254.44 (17.03x) | 885.55 (6.69x) |
| Any FalseBoolScalarValue WKT JSON parse | 466.26 | — | — | 3595.43 (7.71x) | 1455.55 (3.12x) |
| Any ListKindValue WKT JSON stringify | 512.99 | — | — | 5584.93 (10.89x) | 4791.05 (9.34x) |
| Any ListKindValue WKT JSON parse | 1400.98 | — | — | 9878.38 (7.05x) | 7214.99 (5.15x) |
| Any EmptyStructKindValue WKT JSON stringify | 144.78 | — | — | 2917.30 (20.15x) | 1459.74 (10.08x) |
| Any EmptyStructKindValue WKT JSON parse | 507.63 | — | — | 5426.55 (10.69x) | 1889.08 (3.72x) |
| Any EmptyListKindValue WKT JSON stringify | 140.76 | — | — | 2886.51 (20.51x) | 1273.25 (9.05x) |
| Any EmptyListKindValue WKT JSON parse | 514.57 | — | — | 4353.89 (8.46x) | 1988.46 (3.86x) |
| Any DoubleValue WKT JSON stringify | 188.69 | — | — | 1805.81 (9.57x) | 763.18 (4.04x) |
| Any DoubleValue WKT JSON parse | 527.40 | — | — | 2733.72 (5.18x) | 1331.61 (2.52x) |
| Any DoubleValue String WKT JSON parse | 541.39 | — | — | 2733.08 (5.05x) | 1404.18 (2.59x) |
| Any NegativeDoubleValue WKT JSON stringify | 190.20 | — | — | 1809.14 (9.51x) | 772.50 (4.06x) |
| Any NegativeDoubleValue WKT JSON parse | 526.01 | — | — | 2735.17 (5.20x) | 1429.31 (2.72x) |
| Any ZeroDoubleValue WKT JSON stringify | 158.28 | — | — | 921.47 (5.82x) | 717.57 (4.53x) |
| Any ZeroDoubleValue WKT JSON parse | 522.18 | — | — | 2171.00 (4.16x) | 1287.16 (2.46x) |
| Any DoubleValue NaN WKT JSON stringify | 149.03 | — | — | 1576.17 (10.58x) | 679.92 (4.56x) |
| Any DoubleValue NaN WKT JSON parse | 527.41 | — | — | 2657.52 (5.04x) | 1424.23 (2.70x) |
| Any DoubleValue Infinity WKT JSON stringify | 155.85 | — | — | 1569.40 (10.07x) | 684.44 (4.39x) |
| Any DoubleValue Infinity WKT JSON parse | 529.41 | — | — | 2698.49 (5.10x) | 1321.62 (2.50x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 154.20 | — | — | 1563.55 (10.14x) | 710.58 (4.61x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 529.71 | — | — | 2709.26 (5.11x) | 1292.89 (2.44x) |
| Any FloatValue WKT JSON stringify | 199.35 | — | — | 1750.50 (8.78x) | 804.00 (4.03x) |
| Any FloatValue WKT JSON parse | 528.60 | — | — | 2712.86 (5.13x) | 1340.80 (2.54x) |
| Any FloatValue String WKT JSON parse | 540.90 | — | — | 2716.14 (5.02x) | 1397.48 (2.58x) |
| Any NegativeFloatValue WKT JSON stringify | 202.52 | — | — | 1760.93 (8.70x) | 748.45 (3.70x) |
| Any NegativeFloatValue WKT JSON parse | 528.74 | — | — | 2760.18 (5.22x) | 1297.34 (2.45x) |
| Any ZeroFloatValue WKT JSON stringify | 161.56 | — | — | 924.91 (5.72x) | 746.64 (4.62x) |
| Any ZeroFloatValue WKT JSON parse | 524.96 | — | — | 2160.58 (4.12x) | 1260.08 (2.40x) |
| Any FloatValue NaN WKT JSON stringify | 152.22 | — | — | 1571.50 (10.32x) | 684.49 (4.50x) |
| Any FloatValue NaN WKT JSON parse | 528.62 | — | — | 2625.40 (4.97x) | 1252.38 (2.37x) |
| Any FloatValue Infinity WKT JSON stringify | 159.15 | — | — | 1550.61 (9.74x) | 684.04 (4.30x) |
| Any FloatValue Infinity WKT JSON parse | 531.63 | — | — | 2651.65 (4.99x) | 1353.06 (2.55x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 155.86 | — | — | 1548.68 (9.94x) | 692.16 (4.44x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 533.65 | — | — | 2649.94 (4.97x) | 1295.82 (2.43x) |
| Any Int64Value WKT JSON stringify | 169.75 | — | — | 1564.11 (9.21x) | 822.69 (4.85x) |
| Any Int64Value WKT JSON parse | 569.82 | — | — | 2774.33 (4.87x) | 1531.53 (2.69x) |
| Any Int64Value Number WKT JSON parse | 560.04 | — | — | 2739.22 (4.89x) | 1472.22 (2.63x) |
| Any ZeroInt64Value WKT JSON stringify | 146.39 | — | — | 913.59 (6.24x) | 743.43 (5.08x) |
| Any ZeroInt64Value WKT JSON parse | 535.76 | — | — | 2146.02 (4.01x) | 1367.83 (2.55x) |
| Any NegativeInt64Value WKT JSON stringify | 165.91 | — | — | 1557.08 (9.39x) | 883.47 (5.32x) |
| Any NegativeInt64Value WKT JSON parse | 562.70 | — | — | 2808.15 (4.99x) | 1673.50 (2.97x) |
| Any MinInt64Value WKT JSON stringify | 171.38 | — | — | 1557.94 (9.09x) | 909.61 (5.31x) |
| Any MinInt64Value WKT JSON parse | 567.00 | — | — | 2841.43 (5.01x) | 1719.54 (3.03x) |
| Any MaxInt64Value WKT JSON stringify | 165.69 | — | — | 1559.31 (9.41x) | 818.95 (4.94x) |
| Any MaxInt64Value WKT JSON parse | 572.97 | — | — | 2807.18 (4.90x) | 1628.38 (2.84x) |
| Any UInt64Value WKT JSON stringify | 174.29 | — | — | 1557.25 (8.93x) | 910.49 (5.22x) |
| Any UInt64Value WKT JSON parse | 559.12 | — | — | 2802.18 (5.01x) | 1701.64 (3.04x) |
| Any UInt64Value Number WKT JSON parse | 563.66 | — | — | 2769.64 (4.91x) | 1519.13 (2.70x) |
| Any ZeroUInt64Value WKT JSON stringify | 157.23 | — | — | 927.58 (5.90x) | 738.31 (4.70x) |
| Any ZeroUInt64Value WKT JSON parse | 542.37 | — | — | 2175.23 (4.01x) | 1338.95 (2.47x) |
| Any MaxUInt64Value WKT JSON stringify | 170.47 | — | — | 1572.14 (9.22x) | 961.39 (5.64x) |
| Any MaxUInt64Value WKT JSON parse | 570.98 | — | — | 2844.39 (4.98x) | 1658.82 (2.91x) |
| Any Int32Value WKT JSON stringify | 163.90 | — | — | 1555.49 (9.49x) | 708.10 (4.32x) |
| Any Int32Value WKT JSON parse | 540.65 | — | — | 2684.32 (4.96x) | 1421.02 (2.63x) |
| Any Int32Value String WKT JSON parse | 557.63 | — | — | 2678.08 (4.80x) | 1446.96 (2.59x) |
| Any ZeroInt32Value WKT JSON stringify | 165.80 | — | — | 915.68 (5.52x) | 675.93 (4.08x) |
| Any ZeroInt32Value WKT JSON parse | 534.61 | — | — | 2157.20 (4.04x) | 1350.79 (2.53x) |
| Any NegativeInt32Value WKT JSON stringify | 170.01 | — | — | 1562.68 (9.19x) | 694.60 (4.09x) |
| Any NegativeInt32Value WKT JSON parse | 542.47 | — | — | 2694.72 (4.97x) | 1471.97 (2.71x) |
| Any MinInt32Value WKT JSON stringify | 281.23 | — | — | 1557.41 (5.54x) | 700.91 (2.49x) |
| Any MinInt32Value WKT JSON parse | 911.76 | — | — | 2701.46 (2.96x) | 1405.53 (1.54x) |
| Any MaxInt32Value WKT JSON stringify | 266.33 | — | — | 1556.26 (5.84x) | 729.35 (2.74x) |
| Any MaxInt32Value WKT JSON parse | 705.30 | — | — | 2680.67 (3.80x) | 1351.23 (1.92x) |
| Any UInt32Value WKT JSON stringify | 233.31 | — | — | 1556.89 (6.67x) | 747.94 (3.21x) |
| Any UInt32Value WKT JSON parse | 625.28 | — | — | 2687.24 (4.30x) | 1383.53 (2.21x) |
| Any UInt32Value String WKT JSON parse | 554.19 | — | — | 2686.75 (4.85x) | 1594.60 (2.88x) |
| Any ZeroUInt32Value WKT JSON stringify | 172.55 | — | — | 916.20 (5.31x) | 719.25 (4.17x) |
| Any ZeroUInt32Value WKT JSON parse | 543.54 | — | — | 2178.90 (4.01x) | 1415.98 (2.61x) |
| Any MaxUInt32Value WKT JSON stringify | 175.95 | — | — | 1556.67 (8.85x) | 727.21 (4.13x) |
| Any MaxUInt32Value WKT JSON parse | 553.47 | — | — | 2693.10 (4.87x) | 1336.34 (2.41x) |
| Any BoolValue WKT JSON stringify | 173.28 | — | — | 1525.60 (8.80x) | 693.49 (4.00x) |
| Any BoolValue WKT JSON parse | 499.87 | — | — | 2601.94 (5.21x) | 1261.53 (2.52x) |
| Any FalseBoolValue WKT JSON stringify | 171.62 | — | — | 913.63 (5.32x) | 697.73 (4.07x) |
| Any FalseBoolValue WKT JSON parse | 498.20 | — | — | 2151.76 (4.32x) | 1281.55 (2.57x) |
| Any StringValue WKT JSON stringify | 200.46 | — | — | 1553.59 (7.75x) | 769.98 (3.84x) |
| Any StringValue WKT JSON parse | 564.39 | — | — | 2653.22 (4.70x) | 1391.01 (2.46x) |
| Any EmptyStringValue WKT JSON stringify | 186.04 | — | — | 916.30 (4.93x) | 722.77 (3.89x) |
| Any EmptyStringValue WKT JSON parse | 528.57 | — | — | 2164.99 (4.10x) | 1327.82 (2.51x) |
| Any BytesValue WKT JSON stringify | 195.82 | — | — | 1584.00 (8.09x) | 815.26 (4.16x) |
| Any BytesValue WKT JSON parse | 577.83 | — | — | 2682.32 (4.64x) | 1394.60 (2.41x) |
| Any EmptyBytesValue WKT JSON stringify | 178.44 | — | — | 917.66 (5.14x) | 738.10 (4.14x) |
| Any EmptyBytesValue WKT JSON parse | 536.67 | — | — | 2159.25 (4.02x) | 1364.95 (2.54x) |
| Nested Any WKT JSON stringify | 307.12 | — | — | 2471.58 (8.05x) | 1369.08 (4.46x) |
| Nested Any WKT JSON parse | 877.97 | — | — | 4271.68 (4.87x) | 2724.51 (3.10x) |
| Duration JSON stringify | 57.97 | — | — | 962.12 (16.60x) | 341.21 (5.89x) |
| Duration JSON parse | 7.83 | — | — | 1451.95 (185.43x) | 365.91 (46.73x) |
| PlusDuration JSON parse | 8.01 | — | — | 1455.08 (181.66x) | 387.13 (48.33x) |
| ShortFractionDuration JSON parse | 6.31 | — | — | 1417.73 (224.68x) | 377.58 (59.84x) |
| MicroDuration JSON stringify | 59.43 | — | — | 965.45 (16.25x) | 379.35 (6.38x) |
| MicroDuration JSON parse | 10.03 | — | — | 1456.79 (145.24x) | 375.92 (37.48x) |
| NanoDuration JSON stringify | 57.16 | — | — | 995.21 (17.41x) | 378.19 (6.62x) |
| NanoDuration JSON parse | 12.45 | — | — | 1471.20 (118.17x) | 367.04 (29.48x) |
| NegativeDuration JSON stringify | 58.53 | — | — | 1000.10 (17.09x) | 407.43 (6.96x) |
| NegativeDuration JSON parse | 7.90 | — | — | 1497.63 (189.57x) | 358.94 (45.44x) |
| FractionalNegativeDuration JSON stringify | 58.54 | — | — | 967.34 (16.52x) | 385.70 (6.59x) |
| FractionalNegativeDuration JSON parse | 8.02 | — | — | 1453.10 (181.18x) | 358.32 (44.68x) |
| MaxDuration JSON stringify | 50.25 | — | — | 847.27 (16.86x) | 386.60 (7.69x) |
| MaxDuration JSON parse | 22.14 | — | — | 1427.59 (64.48x) | 375.01 (16.94x) |
| MinDuration JSON stringify | 50.04 | — | — | 869.66 (17.38x) | 412.39 (8.24x) |
| MinDuration JSON parse | 22.45 | — | — | 1454.61 (64.79x) | 375.63 (16.73x) |
| ZeroDuration JSON stringify | 45.04 | — | — | 808.98 (17.96x) | 342.95 (7.61x) |
| ZeroDuration JSON parse | 5.57 | — | — | 1360.38 (244.23x) | 296.75 (53.28x) |
| FieldMask JSON stringify | 79.16 | — | — | 889.01 (11.23x) | 650.87 (8.22x) |
| FieldMask JSON parse | 145.63 | — | — | 1660.06 (11.40x) | 843.59 (5.79x) |
| EmptyFieldMask JSON stringify | 41.46 | — | — | 622.62 (15.02x) | 183.19 (4.42x) |
| EmptyFieldMask JSON parse | 2.52 | — | — | 941.24 (373.51x) | 200.74 (79.66x) |
| Timestamp JSON stringify | 95.95 | — | — | 1155.31 (12.04x) | 426.43 (4.44x) |
| Timestamp JSON parse | 41.47 | — | — | 1490.14 (35.93x) | 417.17 (10.06x) |
| Micro Timestamp JSON stringify | 96.56 | — | — | 1138.57 (11.79x) | 402.05 (4.16x) |
| Micro Timestamp JSON parse | 43.25 | — | — | 1493.56 (34.53x) | 415.97 (9.62x) |
| Nano Timestamp JSON stringify | 94.27 | — | — | 1184.74 (12.57x) | 422.71 (4.48x) |
| Nano Timestamp JSON parse | 45.35 | — | — | 1513.24 (33.37x) | 443.56 (9.78x) |
| Offset Timestamp JSON parse | 49.41 | — | — | 1520.91 (30.78x) | 454.06 (9.19x) |
| PreEpoch Timestamp JSON stringify | 66.87 | — | — | 1062.80 (15.89x) | 395.98 (5.92x) |
| PreEpoch Timestamp JSON parse | 39.97 | — | — | 1460.80 (36.55x) | 399.93 (10.01x) |
| Max Timestamp JSON stringify | 81.33 | — | — | 1194.01 (14.68x) | 428.97 (5.27x) |
| Max Timestamp JSON parse | 46.97 | — | — | 1536.41 (32.71x) | 443.16 (9.43x) |
| Min Timestamp JSON stringify | 79.68 | — | — | 1071.21 (13.44x) | 387.41 (4.86x) |
| Min Timestamp JSON parse | 38.07 | — | — | 1450.70 (38.11x) | 396.81 (10.42x) |
| Empty JSON stringify | 21.25 | — | — | 625.88 (29.45x) | 97.52 (4.59x) |
| Empty JSON parse | 67.54 | — | — | 745.23 (11.03x) | 218.67 (3.24x) |
| Struct JSON stringify | 184.93 | — | — | 5711.61 (30.89x) | 3048.21 (16.48x) |
| Struct JSON parse | 853.07 | — | — | 10866.90 (12.74x) | 4443.90 (5.21x) |
| EmptyStruct JSON stringify | 41.10 | — | — | 691.21 (16.82x) | 330.20 (8.03x) |
| EmptyStruct JSON parse | 90.45 | — | — | 2064.92 (22.83x) | 356.34 (3.94x) |
| Value JSON stringify | 187.65 | — | — | 6563.18 (34.98x) | 3159.29 (16.84x) |
| Value JSON parse | 853.19 | — | — | 12037.50 (14.11x) | 4740.19 (5.56x) |
| NullValue JSON stringify | 40.95 | — | — | 1316.06 (32.14x) | 217.33 (5.31x) |
| NullValue JSON parse | 65.10 | — | — | 2472.72 (37.98x) | 322.50 (4.95x) |
| StringScalarValue JSON stringify | 48.39 | — | — | 1344.55 (27.79x) | 277.81 (5.74x) |
| StringScalarValue JSON parse | 135.98 | — | — | 2089.76 (15.37x) | 389.88 (2.87x) |
| EmptyStringScalarValue JSON stringify | 46.39 | — | — | 1331.99 (28.71x) | 277.89 (5.99x) |
| EmptyStringScalarValue JSON parse | 82.44 | — | — | 2073.95 (25.16x) | 358.69 (4.35x) |
| NumberValue JSON stringify | 73.62 | — | — | 1551.32 (21.07x) | 323.71 (4.40x) |
| NumberValue JSON parse | 126.83 | — | — | 2171.99 (17.13x) | 393.30 (3.10x) |
| ZeroNumberValue JSON stringify | 51.62 | — | — | 1505.52 (29.17x) | 272.18 (5.27x) |
| ZeroNumberValue JSON parse | 125.37 | — | — | 2103.78 (16.78x) | 348.08 (2.78x) |
| BoolScalarValue JSON stringify | 41.00 | — | — | 1316.89 (32.12x) | 224.93 (5.49x) |
| BoolScalarValue JSON parse | 65.50 | — | — | 2019.32 (30.83x) | 330.70 (5.05x) |
| FalseBoolScalarValue JSON stringify | 41.17 | — | — | 1312.31 (31.88x) | 216.64 (5.26x) |
| FalseBoolScalarValue JSON parse | 72.52 | — | — | 2017.65 (27.82x) | 325.32 (4.49x) |
| ListKindValue JSON stringify | 148.15 | — | — | 6105.99 (41.21x) | 2236.67 (15.10x) |
| ListKindValue JSON parse | 664.47 | — | — | 10340.80 (15.56x) | 3916.35 (5.89x) |
| EmptyStructKindValue JSON stringify | 42.86 | — | — | 1930.88 (45.05x) | 536.70 (12.52x) |
| EmptyStructKindValue JSON parse | 106.26 | — | — | 3737.94 (35.18x) | 590.15 (5.55x) |
| EmptyListKindValue JSON stringify | 41.62 | — | — | 1928.29 (46.33x) | 351.01 (8.43x) |
| EmptyListKindValue JSON parse | 143.11 | — | — | 4014.75 (28.05x) | 553.78 (3.87x) |
| ListValue JSON stringify | 149.62 | — | — | 4746.48 (31.72x) | 1975.44 (13.20x) |
| ListValue JSON parse | 665.86 | — | — | 8470.37 (12.72x) | 3870.84 (5.81x) |
| EmptyListValue JSON stringify | 40.35 | — | — | 697.28 (17.28x) | 161.26 (4.00x) |
| EmptyListValue JSON parse | 130.18 | — | — | 2252.40 (17.30x) | 283.50 (2.18x) |
| DoubleValue JSON stringify | 67.38 | — | — | 867.26 (12.87x) | 183.15 (2.72x) |
| DoubleValue JSON parse | 112.03 | — | — | 1232.89 (11.00x) | 267.34 (2.39x) |
| DoubleValue String JSON parse | 112.55 | — | — | 1174.61 (10.44x) | 354.97 (3.15x) |
| NegativeDoubleValue JSON stringify | 67.74 | — | — | 871.29 (12.86x) | 204.90 (3.02x) |
| NegativeDoubleValue JSON parse | 111.63 | — | — | 1234.91 (11.06x) | 264.45 (2.37x) |
| ZeroDoubleValue JSON stringify | 47.51 | — | — | 811.71 (17.09x) | 149.19 (3.14x) |
| ZeroDoubleValue JSON parse | 108.48 | — | — | 1161.26 (10.70x) | 272.13 (2.51x) |
| DoubleValue NaN JSON stringify | 46.62 | — | — | 672.25 (14.42x) | 114.50 (2.46x) |
| DoubleValue NaN JSON parse | 105.19 | — | — | 1089.55 (10.36x) | 257.53 (2.45x) |
| DoubleValue Infinity JSON stringify | 48.32 | — | — | 672.36 (13.91x) | 126.70 (2.62x) |
| DoubleValue Infinity JSON parse | 106.54 | — | — | 1105.34 (10.37x) | 274.36 (2.58x) |
| DoubleValue NegativeInfinity JSON stringify | 48.37 | — | — | 663.74 (13.72x) | 116.07 (2.40x) |
| DoubleValue NegativeInfinity JSON parse | 108.41 | — | — | 1102.00 (10.17x) | 290.93 (2.68x) |
| FloatValue JSON stringify | 70.27 | — | — | 812.64 (11.56x) | 180.25 (2.57x) |
| FloatValue JSON parse | 111.02 | — | — | 1220.70 (11.00x) | 295.14 (2.66x) |
| FloatValue String JSON parse | 110.07 | — | — | 1153.14 (10.48x) | 340.69 (3.10x) |
| NegativeFloatValue JSON stringify | 72.78 | — | — | 810.78 (11.14x) | 191.23 (2.63x) |
| NegativeFloatValue JSON parse | 111.06 | — | — | 1222.24 (11.01x) | 277.24 (2.50x) |
| ZeroFloatValue JSON stringify | 47.43 | — | — | 761.20 (16.05x) | 135.65 (2.86x) |
| ZeroFloatValue JSON parse | 107.92 | — | — | 1153.39 (10.69x) | 245.48 (2.27x) |
| FloatValue NaN JSON stringify | 46.88 | — | — | 651.88 (13.91x) | 119.11 (2.54x) |
| FloatValue NaN JSON parse | 104.58 | — | — | 1086.74 (10.39x) | 265.91 (2.54x) |
| FloatValue Infinity JSON stringify | 48.22 | — | — | 653.01 (13.54x) | 116.65 (2.42x) |
| FloatValue Infinity JSON parse | 105.77 | — | — | 1089.18 (10.30x) | 274.13 (2.59x) |
| FloatValue NegativeInfinity JSON stringify | 48.13 | — | — | 649.10 (13.49x) | 124.85 (2.59x) |
| FloatValue NegativeInfinity JSON parse | 108.16 | — | — | 1104.04 (10.21x) | 267.84 (2.48x) |
| Int64Value JSON stringify | 50.04 | — | — | 690.11 (13.79x) | 260.94 (5.21x) |
| Int64Value JSON parse | 125.60 | — | — | 1225.20 (9.75x) | 452.40 (3.60x) |
| Int64Value Number JSON parse | 127.06 | — | — | 1283.93 (10.10x) | 339.49 (2.67x) |
| ZeroInt64Value JSON stringify | 41.48 | — | — | 623.24 (15.02x) | 184.77 (4.45x) |
| ZeroInt64Value JSON parse | 105.45 | — | — | 1095.37 (10.39x) | 326.26 (3.09x) |
| NegativeInt64Value JSON stringify | 48.48 | — | — | 724.67 (14.95x) | 259.70 (5.36x) |
| NegativeInt64Value JSON parse | 127.53 | — | — | 1230.21 (9.65x) | 451.94 (3.54x) |
| MinInt64Value JSON stringify | 49.68 | — | — | 692.79 (13.95x) | 270.75 (5.45x) |
| MinInt64Value JSON parse | 141.43 | — | — | 1250.62 (8.84x) | 471.35 (3.33x) |
| MaxInt64Value JSON stringify | 49.41 | — | — | 691.27 (13.99x) | 266.78 (5.40x) |
| MaxInt64Value JSON parse | 135.11 | — | — | 1247.39 (9.23x) | 473.09 (3.50x) |
| UInt64Value JSON stringify | 50.33 | — | — | 695.28 (13.81x) | 268.97 (5.34x) |
| UInt64Value JSON parse | 124.76 | — | — | 1214.23 (9.73x) | 447.57 (3.59x) |
| UInt64Value Number JSON parse | 127.21 | — | — | 1278.43 (10.05x) | 348.05 (2.74x) |
| ZeroUInt64Value JSON stringify | 41.82 | — | — | 630.28 (15.07x) | 182.67 (4.37x) |
| ZeroUInt64Value JSON parse | 103.59 | — | — | 1104.30 (10.66x) | 312.84 (3.02x) |
| MaxUInt64Value JSON stringify | 50.32 | — | — | 692.88 (13.77x) | 273.36 (5.43x) |
| MaxUInt64Value JSON parse | 141.93 | — | — | 1257.18 (8.86x) | 442.83 (3.12x) |
| Int32Value JSON stringify | 46.15 | — | — | 643.80 (13.95x) | 154.43 (3.35x) |
| Int32Value JSON parse | 117.38 | — | — | 1189.63 (10.13x) | 321.93 (2.74x) |
| Int32Value String JSON parse | 114.17 | — | — | 1132.92 (9.92x) | 397.78 (3.48x) |
| ZeroInt32Value JSON stringify | 46.20 | — | — | 625.38 (13.54x) | 125.01 (2.71x) |
| ZeroInt32Value JSON parse | 113.18 | — | — | 1155.08 (10.21x) | 255.21 (2.25x) |
| NegativeInt32Value JSON stringify | 46.33 | — | — | 650.93 (14.05x) | 137.97 (2.98x) |
| NegativeInt32Value JSON parse | 117.05 | — | — | 1190.79 (10.17x) | 313.79 (2.68x) |
| MinInt32Value JSON stringify | 46.89 | — | — | 650.66 (13.88x) | 134.78 (2.87x) |
| MinInt32Value JSON parse | 123.15 | — | — | 1206.45 (9.80x) | 330.20 (2.68x) |
| MaxInt32Value JSON stringify | 46.92 | — | — | 647.14 (13.79x) | 133.16 (2.84x) |
| MaxInt32Value JSON parse | 123.33 | — | — | 1205.65 (9.78x) | 316.50 (2.57x) |
| UInt32Value JSON stringify | 46.26 | — | — | 643.34 (13.91x) | 126.46 (2.73x) |
| UInt32Value JSON parse | 117.37 | — | — | 1196.86 (10.20x) | 295.27 (2.52x) |
| UInt32Value String JSON parse | 114.58 | — | — | 1142.62 (9.97x) | 383.23 (3.34x) |
| ZeroUInt32Value JSON stringify | 46.29 | — | — | 625.17 (13.51x) | 134.92 (2.91x) |
| ZeroUInt32Value JSON parse | 112.84 | — | — | 1162.30 (10.30x) | 269.85 (2.39x) |
| MaxUInt32Value JSON stringify | 46.78 | — | — | 642.64 (13.74x) | 131.11 (2.80x) |
| MaxUInt32Value JSON parse | 122.82 | — | — | 1206.14 (9.82x) | 345.54 (2.81x) |
| BoolValue JSON stringify | 44.84 | — | — | 625.39 (13.95x) | 113.97 (2.54x) |
| BoolValue JSON parse | 59.53 | — | — | 1053.42 (17.70x) | 202.91 (3.41x) |
| FalseBoolValue JSON stringify | 44.92 | — | — | 613.23 (13.65x) | 121.26 (2.70x) |
| FalseBoolValue JSON parse | 66.91 | — | — | 1060.10 (15.84x) | 197.70 (2.95x) |
| StringValue JSON stringify | 51.87 | — | — | 679.04 (13.09x) | 183.78 (3.54x) |
| StringValue JSON parse | 136.99 | — | — | 1155.86 (8.44x) | 281.59 (2.06x) |
| EmptyStringValue JSON stringify | 48.96 | — | — | 643.77 (13.15x) | 188.40 (3.85x) |
| EmptyStringValue JSON parse | 81.76 | — | — | 1125.70 (13.77x) | 225.53 (2.76x) |
| BytesValue JSON stringify | 49.40 | — | — | 672.63 (13.62x) | 206.42 (4.18x) |
| BytesValue JSON parse | 146.74 | — | — | 1175.00 (8.01x) | 318.11 (2.17x) |
| EmptyBytesValue JSON stringify | 41.18 | — | — | 646.68 (15.70x) | 182.70 (4.44x) |
| EmptyBytesValue JSON parse | 90.03 | — | — | 1132.90 (12.58x) | 246.82 (2.74x) |
| TextFormat format | 184.28 | — | — | 2600.97 (14.11x) | 2288.69 (12.42x) |
| TextFormat parse | 728.55 | — | — | 5008.66 (6.87x) | 6166.86 (8.46x) |
| packed fixed32 encode | 2.00 | 549.79 (274.89x) | 539.38 (269.69x) | 43.76 (21.88x) | 466.75 (233.38x) |
| packed fixed32 decode | 4.52 | 1047.44 (231.73x) | 1961.31 (433.92x) | 49.75 (11.01x) | 1722.78 (381.15x) |
| packed fixed64 encode | 2.01 | 578.52 (287.82x) | 563.28 (280.24x) | 75.86 (37.74x) | 403.00 (200.50x) |
| packed fixed64 decode | 4.53 | 1058.26 (233.61x) | 7944.24 (1753.70x) | 80.32 (17.73x) | 2509.60 (554.00x) |
| packed sfixed32 encode | 2.01 | 558.50 (277.86x) | 539.46 (268.39x) | 43.96 (21.87x) | 405.17 (201.58x) |
| packed sfixed32 decode | 4.53 | 1061.50 (234.33x) | 1970.34 (434.95x) | 48.88 (10.79x) | 1669.90 (368.63x) |
| packed sfixed64 encode | 2.00 | 570.30 (285.15x) | 561.48 (280.74x) | 75.83 (37.92x) | 405.76 (202.88x) |
| packed sfixed64 decode | 4.53 | 1046.06 (230.92x) | 7899.47 (1743.81x) | 79.69 (17.59x) | 2303.98 (508.60x) |
| packed float encode | 2.01 | 814.16 (405.05x) | 539.72 (268.52x) | 43.96 (21.87x) | 417.04 (207.48x) |
| packed float decode | 4.53 | 1048.38 (231.43x) | 2087.14 (460.74x) | 48.91 (10.80x) | 1627.51 (359.27x) |
| packed double encode | 2.01 | 830.15 (413.01x) | 561.15 (279.18x) | 75.85 (37.73x) | 382.11 (190.10x) |
| packed double decode | 4.54 | 989.34 (217.92x) | 2044.95 (450.43x) | 79.80 (17.58x) | 2454.60 (540.66x) |
| packed uint64 encode | 1304.44 | 4626.05 (3.55x) | 4007.79 (3.07x) | 2122.01 (1.63x) | 3472.37 (2.66x) |
| packed uint64 decode | 1781.04 | 2780.98 (1.56x) | 8867.82 (4.98x) | 2800.62 (1.57x) | 7716.41 (4.33x) |
| packed uint32 encode | 985.14 | 3608.41 (3.66x) | 3261.19 (3.31x) | 1719.06 (1.74x) | 2892.74 (2.94x) |
| packed uint32 decode | 1329.61 | 2479.50 (1.86x) | 3253.55 (2.45x) | 1995.17 (1.50x) | 5563.61 (4.18x) |
| packed int64 encode | 1487.48 | 10953.57 (7.36x) | 6044.99 (4.06x) | 2888.51 (1.94x) | 4101.97 (2.76x) |
| packed int64 decode | 2739.22 | 3378.27 (1.23x) | 10261.59 (3.75x) | 4763.97 (1.74x) | 9531.27 (3.48x) |
| packed sint32 encode | 778.21 | 3033.46 (3.90x) | 2885.88 (3.71x) | 1527.73 (1.96x) | 3378.71 (4.34x) |
| packed sint32 decode | 927.41 | 2558.82 (2.76x) | 3215.61 (3.47x) | 1129.67 (1.22x) | 3530.86 (3.81x) |
| packed sint64 encode | 1415.48 | 4975.21 (3.51x) | 4311.64 (3.05x) | 2397.68 (1.69x) | 4135.46 (2.92x) |
| packed sint64 decode | 2038.60 | 3074.04 (1.51x) | 9644.56 (4.73x) | 2931.44 (1.44x) | 8522.22 (4.18x) |
| packed bool encode | 2.00 | 1339.48 (669.74x) | 519.96 (259.98x) | 15.59 (7.80x) | 2203.57 (1101.79x) |
| packed bool decode | 263.02 | 1544.10 (5.87x) | 2551.65 (9.70x) | 805.51 (3.06x) | 1801.94 (6.85x) |
| packed enum encode | 273.86 | 2737.41 (10.00x) | 1815.59 (6.63x) | 1087.76 (3.97x) | 2489.27 (9.09x) |
| packed enum decode | 152.32 | 1621.65 (10.65x) | 2870.84 (18.85x) | 694.57 (4.56x) | 2397.16 (15.74x) |
| large map encode | 4065.20 | 16820.11 (4.14x) | 9847.11 (2.42x) | 22259.20 (5.48x) | 195899.73 (48.19x) |
| shuffled large map deterministic binary encode | 27728.16 | — | — | 98454.20 (3.55x) | 370788.53 (13.37x) |
| large map decode | 25808.79 | 90774.62 (3.52x) | 90622.88 (3.51x) | 92739.80 (3.59x) | 270711.18 (10.49x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded zero/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound `Duration`, non-empty and empty `Struct`, object/list/scalar `Value` (including default-like scalar and empty object/list kinds),
`FieldMask` (non-empty and empty), micro/nano/offset/min/pre/post/max-bound `Timestamp`, `Empty`, min/zero/positive/number-input parse/negative/max `Int64Value`, negative/zero/positive finite/string-input parse `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), negative/zero/positive finite/string-input parse `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), zero/normal/number-input parse/max `UInt64Value`, min/zero/positive/string-input parse/negative/max `Int32Value`, zero/normal/string-input parse/max `UInt32Value`, true/false `BoolValue`, non-empty/empty `StringValue`, base64/empty `BytesValue`, and recursive nested `Any` payloads), direct zero/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound Duration and micro/nano/offset/min/pre/post/max-bound Timestamp WKT JSON plus other direct WKT JSON, including empty `Struct` and empty `ListValue`, TextFormat, packed scalars, large bytes,
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
