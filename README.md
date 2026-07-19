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

Latest accepted comparison (`/tmp/pbz-compare-32-string-wrapper-json-isolated.log`,
summarized in `/tmp/pbz-summary-32-string-wrapper-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 19.84 | 113.24 (5.71x) | 51.21 (2.58x) | 112.03 (5.65x) | 829.24 (41.80x) |
| binary decode | 92.81 | 257.12 (2.77x) | 230.33 (2.48x) | 218.48 (2.35x) | 903.50 (9.73x) |
| unknown fields count by number | 3.57 | — | — | 162.52 (45.52x) | — |
| deterministic binary encode | 61.29 | — | — | 129.06 (2.11x) | 1110.33 (18.12x) |
| scalarmix encode | 18.79 | 93.54 (4.98x) | 48.08 (2.56x) | 31.07 (1.65x) | 210.97 (11.23x) |
| scalarmix decode | 34.54 | 135.92 (3.94x) | 176.54 (5.11x) | 88.97 (2.58x) | 310.97 (9.00x) |
| textbytes encode | 12.14 | 81.23 (6.69x) | 33.60 (2.77x) | 117.35 (9.67x) | 170.60 (14.05x) |
| textbytes decode | 45.97 | 382.66 (8.32x) | 237.19 (5.16x) | 167.92 (3.65x) | 660.72 (14.37x) |
| largebytes encode | 17.79 | 2716.84 (152.72x) | 2639.00 (148.34x) | 2682.95 (150.81x) | 2771.66 (155.80x) |
| largebytes decode | 88.67 | 5493.20 (61.95x) | 3032.65 (34.20x) | 2727.46 (30.76x) | 24376.90 (274.92x) |
| presencemix encode | 18.71 | 56.18 (3.00x) | 28.67 (1.53x) | 56.77 (3.03x) | 250.63 (13.40x) |
| presencemix decode | 57.99 | 132.88 (2.29x) | 109.37 (1.89x) | 166.78 (2.88x) | 503.98 (8.69x) |
| complex encode | 53.99 | 151.02 (2.80x) | 98.68 (1.83x) | 160.70 (2.98x) | 945.67 (17.52x) |
| complex decode | 190.16 | 391.60 (2.06x) | 341.58 (1.80x) | 394.22 (2.07x) | 1376.18 (7.24x) |
| complex deterministic binary encode | 99.32 | — | — | 171.13 (1.72x) | 1109.53 (11.17x) |
| complex JSON stringify | 284.46 | — | — | 4892.29 (17.20x) | 6316.44 (22.21x) |
| complex JSON parse | 2412.49 | — | — | 11959.20 (4.96x) | 7314.67 (3.03x) |
| complex TextFormat format | 260.22 | — | — | 3765.15 (14.47x) | 5499.90 (21.14x) |
| complex TextFormat parse | 1835.44 | — | — | 6896.79 (3.76x) | 9294.81 (5.06x) |
| packed int32 encode | 626.50 | 3183.73 (5.08x) | 2566.91 (4.10x) | 1282.68 (2.05x) | 2741.24 (4.38x) |
| packed int32 decode | 705.13 | 1926.53 (2.73x) | 3241.07 (4.60x) | 1455.10 (2.06x) | 3238.87 (4.59x) |
| JSON stringify | 161.67 | — | — | 2998.28 (18.55x) | 2196.63 (13.59x) |
| JSON parse | 1517.50 | — | — | 7447.72 (4.91x) | 4557.51 (3.00x) |
| Any WKT JSON stringify | 130.17 | — | — | 1876.68 (14.42x) | 1044.28 (8.02x) |
| Any WKT JSON parse | 519.08 | — | — | 2971.41 (5.72x) | 1656.85 (3.19x) |
| Any PlusDuration WKT JSON parse | 518.79 | — | — | 3000.53 (5.78x) | 1797.30 (3.46x) |
| Any ShortFractionDuration WKT JSON parse | 515.94 | — | — | 2948.64 (5.72x) | 1441.12 (2.79x) |
| Any MicroDuration WKT JSON stringify | 136.93 | — | — | 1885.10 (13.77x) | 1084.15 (7.92x) |
| Any MicroDuration WKT JSON parse | 522.30 | — | — | 2997.68 (5.74x) | 1912.15 (3.66x) |
| Any NanoDuration WKT JSON stringify | 132.77 | — | — | 1915.02 (14.42x) | 1049.01 (7.90x) |
| Any NanoDuration WKT JSON parse | 528.50 | — | — | 3000.01 (5.68x) | 1933.42 (3.66x) |
| Any NegativeDuration WKT JSON stringify | 135.47 | — | — | 1931.32 (14.26x) | 1212.44 (8.95x) |
| Any NegativeDuration WKT JSON parse | 523.46 | — | — | 3092.28 (5.91x) | 1647.33 (3.15x) |
| Any FractionalNegativeDuration WKT JSON stringify | 126.72 | — | — | 1880.70 (14.84x) | 1131.61 (8.93x) |
| Any FractionalNegativeDuration WKT JSON parse | 507.27 | — | — | 3066.23 (6.04x) | 1492.10 (2.94x) |
| Any MaxDuration WKT JSON stringify | 118.85 | — | — | 1743.07 (14.67x) | 1119.99 (9.42x) |
| Any MaxDuration WKT JSON parse | 528.24 | — | — | 2964.72 (5.61x) | 1770.32 (3.35x) |
| Any MinDuration WKT JSON stringify | 120.44 | — | — | 1752.37 (14.55x) | 1165.77 (9.68x) |
| Any MinDuration WKT JSON parse | 529.45 | — | — | 3022.69 (5.71x) | 1481.64 (2.80x) |
| Any ZeroDuration WKT JSON stringify | 106.94 | — | — | 912.84 (8.54x) | 1013.77 (9.48x) |
| Any ZeroDuration WKT JSON parse | 459.44 | — | — | 2242.47 (4.88x) | 1597.15 (3.48x) |
| Any FieldMask WKT JSON stringify | 239.53 | — | — | 1738.56 (7.26x) | 1527.92 (6.38x) |
| Any FieldMask WKT JSON parse | 711.95 | — | — | 3146.27 (4.42x) | 2368.51 (3.33x) |
| Any EmptyFieldMask WKT JSON stringify | 118.75 | — | — | 914.83 (7.70x) | 781.13 (6.58x) |
| Any EmptyFieldMask WKT JSON parse | 436.45 | — | — | 2144.64 (4.91x) | 1313.12 (3.01x) |
| Any Timestamp WKT JSON stringify | 178.61 | — | — | 2019.69 (11.31x) | 1139.76 (6.38x) |
| Any Timestamp WKT JSON parse | 562.62 | — | — | 3038.16 (5.40x) | 1875.83 (3.33x) |
| Any Micro Timestamp WKT JSON stringify | 178.82 | — | — | 2028.69 (11.34x) | 1041.91 (5.83x) |
| Any Micro Timestamp WKT JSON parse | 566.29 | — | — | 3029.87 (5.35x) | 1990.97 (3.52x) |
| Any Nano Timestamp WKT JSON stringify | 180.14 | — | — | 2024.60 (11.24x) | 1163.42 (6.46x) |
| Any Nano Timestamp WKT JSON parse | 572.61 | — | — | 3039.93 (5.31x) | 1732.03 (3.02x) |
| Any Offset Timestamp WKT JSON parse | 580.35 | — | — | 3051.98 (5.26x) | 1827.27 (3.15x) |
| Any PreEpoch Timestamp WKT JSON stringify | 143.30 | — | — | 1940.64 (13.54x) | 1051.11 (7.34x) |
| Any PreEpoch Timestamp WKT JSON parse | 552.43 | — | — | 3043.27 (5.51x) | 1582.29 (2.86x) |
| Any Max Timestamp WKT JSON stringify | 162.16 | — | — | 2041.22 (12.59x) | 1140.16 (7.03x) |
| Any Max Timestamp WKT JSON parse | 574.67 | — | — | 3091.25 (5.38x) | 1716.89 (2.99x) |
| Any Min Timestamp WKT JSON stringify | 156.81 | — | — | 1930.31 (12.31x) | 1062.59 (6.78x) |
| Any Min Timestamp WKT JSON parse | 548.72 | — | — | 3034.74 (5.53x) | 1654.89 (3.02x) |
| Any Empty WKT JSON stringify | 92.75 | — | — | 911.43 (9.83x) | 664.31 (7.16x) |
| Any Empty WKT JSON parse | 330.81 | — | — | 2121.31 (6.41x) | 1280.56 (3.87x) |
| Any Struct WKT JSON stringify | 635.25 | — | — | 5845.89 (9.20x) | 6850.64 (10.78x) |
| Any Struct WKT JSON parse | 1755.19 | — | — | 11114.50 (6.33x) | 9664.93 (5.51x) |
| Any EmptyStruct WKT JSON stringify | 122.90 | — | — | 909.90 (7.40x) | 1052.17 (8.56x) |
| Any EmptyStruct WKT JSON parse | 429.98 | — | — | 2242.67 (5.22x) | 1745.85 (4.06x) |
| Any Value WKT JSON stringify | 655.82 | — | — | 5921.42 (9.03x) | 7351.44 (11.21x) |
| Any Value WKT JSON parse | 1792.24 | — | — | 11389.50 (6.35x) | 10269.55 (5.73x) |
| Any NullValue WKT JSON stringify | 133.25 | — | — | 2251.18 (16.89x) | 1011.54 (7.59x) |
| Any NullValue WKT JSON parse | 458.40 | — | — | 4040.22 (8.81x) | 1781.84 (3.89x) |
| Any StringScalarValue WKT JSON stringify | 153.90 | — | — | 2270.21 (14.75x) | 1150.38 (7.47x) |
| Any StringScalarValue WKT JSON parse | 503.33 | — | — | 3632.18 (7.22x) | 1698.80 (3.38x) |
| Any EmptyStringScalarValue WKT JSON stringify | 146.65 | — | — | 2275.76 (15.52x) | 1126.22 (7.68x) |
| Any EmptyStringScalarValue WKT JSON parse | 475.26 | — | — | 3601.48 (7.58x) | 1781.38 (3.75x) |
| Any NumberValue WKT JSON stringify | 177.26 | — | — | 2522.37 (14.23x) | 1226.57 (6.92x) |
| Any NumberValue WKT JSON parse | 497.85 | — | — | 3682.46 (7.40x) | 1694.63 (3.40x) |
| Any ZeroNumberValue WKT JSON stringify | 142.83 | — | — | 2465.23 (17.26x) | 965.33 (6.76x) |
| Any ZeroNumberValue WKT JSON parse | 489.85 | — | — | 3612.75 (7.38x) | 1778.45 (3.63x) |
| Any BoolScalarValue WKT JSON stringify | 133.10 | — | — | 2256.90 (16.96x) | 972.55 (7.31x) |
| Any BoolScalarValue WKT JSON parse | 450.30 | — | — | 3630.83 (8.06x) | 1538.79 (3.42x) |
| Any FalseBoolScalarValue WKT JSON stringify | 133.62 | — | — | 2252.59 (16.86x) | 1074.78 (8.04x) |
| Any FalseBoolScalarValue WKT JSON parse | 453.95 | — | — | 3584.21 (7.90x) | 1761.77 (3.88x) |
| Any ListKindValue WKT JSON stringify | 496.71 | — | — | 5581.03 (11.24x) | 5868.09 (11.81x) |
| Any ListKindValue WKT JSON parse | 1380.02 | — | — | 9903.31 (7.18x) | 8263.19 (5.99x) |
| Any EmptyStructKindValue WKT JSON stringify | 147.47 | — | — | 2921.02 (19.81x) | 1568.33 (10.63x) |
| Any EmptyStructKindValue WKT JSON parse | 489.93 | — | — | 5435.59 (11.09x) | 2109.19 (4.31x) |
| Any EmptyListKindValue WKT JSON stringify | 144.96 | — | — | 2900.10 (20.01x) | 1341.57 (9.25x) |
| Any EmptyListKindValue WKT JSON parse | 495.71 | — | — | 4369.01 (8.81x) | 1926.00 (3.89x) |
| Any DoubleValue WKT JSON stringify | 187.54 | — | — | 1798.81 (9.59x) | 843.38 (4.50x) |
| Any DoubleValue WKT JSON parse | 515.17 | — | — | 2735.27 (5.31x) | 1618.65 (3.14x) |
| Any NegativeDoubleValue WKT JSON stringify | 191.38 | — | — | 1791.27 (9.36x) | 842.29 (4.40x) |
| Any NegativeDoubleValue WKT JSON parse | 515.64 | — | — | 2726.70 (5.29x) | 1517.18 (2.94x) |
| Any ZeroDoubleValue WKT JSON stringify | 156.75 | — | — | 912.50 (5.82x) | 735.78 (4.69x) |
| Any ZeroDoubleValue WKT JSON parse | 506.37 | — | — | 2313.14 (4.57x) | 1476.54 (2.92x) |
| Any DoubleValue NaN WKT JSON stringify | 155.15 | — | — | 1581.24 (10.19x) | 731.34 (4.71x) |
| Any DoubleValue NaN WKT JSON parse | 790.31 | — | — | 2646.37 (3.35x) | 1402.03 (1.77x) |
| Any DoubleValue Infinity WKT JSON stringify | 249.65 | — | — | 1615.42 (6.47x) | 785.23 (3.15x) |
| Any DoubleValue Infinity WKT JSON parse | 698.11 | — | — | 2710.60 (3.88x) | 1472.40 (2.11x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 208.58 | — | — | 1561.30 (7.49x) | 715.30 (3.43x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 681.82 | — | — | 2671.17 (3.92x) | 1443.63 (2.12x) |
| Any FloatValue WKT JSON stringify | 194.95 | — | — | 1739.19 (8.92x) | 770.44 (3.95x) |
| Any FloatValue WKT JSON parse | 514.74 | — | — | 2691.92 (5.23x) | 1445.69 (2.81x) |
| Any NegativeFloatValue WKT JSON stringify | 200.72 | — | — | 1741.01 (8.67x) | 764.07 (3.81x) |
| Any NegativeFloatValue WKT JSON parse | 515.41 | — | — | 2948.97 (5.72x) | 1494.04 (2.90x) |
| Any ZeroFloatValue WKT JSON stringify | 163.49 | — | — | 969.83 (5.93x) | 718.09 (4.39x) |
| Any ZeroFloatValue WKT JSON parse | 509.93 | — | — | 2153.71 (4.22x) | 1589.07 (3.12x) |
| Any FloatValue NaN WKT JSON stringify | 160.74 | — | — | 1558.41 (9.70x) | 728.04 (4.53x) |
| Any FloatValue NaN WKT JSON parse | 505.66 | — | — | 2624.27 (5.19x) | 1425.06 (2.82x) |
| Any FloatValue Infinity WKT JSON stringify | 168.53 | — | — | 1547.85 (9.18x) | 690.79 (4.10x) |
| Any FloatValue Infinity WKT JSON parse | 512.04 | — | — | 2751.92 (5.37x) | 1345.24 (2.63x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 167.39 | — | — | 1559.97 (9.32x) | 742.84 (4.44x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 514.05 | — | — | 2737.25 (5.32x) | 1444.74 (2.81x) |
| Any Int64Value WKT JSON stringify | 170.66 | — | — | 1574.10 (9.22x) | 870.75 (5.10x) |
| Any Int64Value WKT JSON parse | 550.17 | — | — | 2810.66 (5.11x) | 1931.58 (3.51x) |
| Any Int64Value Number WKT JSON parse | 546.35 | — | — | 2743.21 (5.02x) | 1726.24 (3.16x) |
| Any ZeroInt64Value WKT JSON stringify | 161.68 | — | — | 931.56 (5.76x) | 772.61 (4.78x) |
| Any ZeroInt64Value WKT JSON parse | 514.49 | — | — | 2152.26 (4.18x) | 1481.20 (2.88x) |
| Any NegativeInt64Value WKT JSON stringify | 185.33 | — | — | 1557.09 (8.40x) | 855.32 (4.62x) |
| Any NegativeInt64Value WKT JSON parse | 545.43 | — | — | 2795.53 (5.13x) | 1642.65 (3.01x) |
| Any MinInt64Value WKT JSON stringify | 178.50 | — | — | 1568.37 (8.79x) | 914.72 (5.12x) |
| Any MinInt64Value WKT JSON parse | 548.84 | — | — | 2810.61 (5.12x) | 1915.29 (3.49x) |
| Any MaxInt64Value WKT JSON stringify | 176.63 | — | — | 2269.97 (12.85x) | 832.66 (4.71x) |
| Any MaxInt64Value WKT JSON parse | 553.02 | — | — | 4562.53 (8.25x) | 1760.82 (3.18x) |
| Any UInt64Value WKT JSON stringify | 175.64 | — | — | 2330.36 (13.27x) | 965.26 (5.50x) |
| Any UInt64Value WKT JSON parse | 547.88 | — | — | 4875.94 (8.90x) | 1779.73 (3.25x) |
| Any UInt64Value Number WKT JSON parse | 549.07 | — | — | 4672.89 (8.51x) | 1502.20 (2.74x) |
| Any ZeroUInt64Value WKT JSON stringify | 169.71 | — | — | 954.43 (5.62x) | 787.36 (4.64x) |
| Any ZeroUInt64Value WKT JSON parse | 518.57 | — | — | 2162.86 (4.17x) | 1517.52 (2.93x) |
| Any MaxUInt64Value WKT JSON stringify | 179.97 | — | — | 1587.76 (8.82x) | 922.21 (5.12x) |
| Any MaxUInt64Value WKT JSON parse | 553.84 | — | — | 2866.04 (5.17x) | 1756.23 (3.17x) |
| Any Int32Value WKT JSON stringify | 167.17 | — | — | 1570.54 (9.39x) | 732.59 (4.38x) |
| Any Int32Value WKT JSON parse | 526.04 | — | — | 2795.29 (5.31x) | 1566.41 (2.98x) |
| Any Int32Value String WKT JSON parse | 531.05 | — | — | 2686.64 (5.06x) | 1507.48 (2.84x) |
| Any ZeroInt32Value WKT JSON stringify | 169.02 | — | — | 918.97 (5.44x) | 767.48 (4.54x) |
| Any ZeroInt32Value WKT JSON parse | 517.58 | — | — | 2161.37 (4.18x) | 1514.67 (2.93x) |
| Any NegativeInt32Value WKT JSON stringify | 170.63 | — | — | 1551.68 (9.09x) | 722.42 (4.23x) |
| Any NegativeInt32Value WKT JSON parse | 529.23 | — | — | 2720.24 (5.14x) | 1543.63 (2.92x) |
| Any MinInt32Value WKT JSON stringify | 174.24 | — | — | 1581.00 (9.07x) | 744.16 (4.27x) |
| Any MinInt32Value WKT JSON parse | 529.60 | — | — | 2788.09 (5.26x) | 1674.27 (3.16x) |
| Any MaxInt32Value WKT JSON stringify | 177.40 | — | — | 3003.70 (16.93x) | 720.53 (4.06x) |
| Any MaxInt32Value WKT JSON parse | 533.50 | — | — | 6699.42 (12.56x) | 1458.47 (2.73x) |
| Any UInt32Value WKT JSON stringify | 224.61 | — | — | 2335.89 (10.40x) | 757.37 (3.37x) |
| Any UInt32Value WKT JSON parse | 618.57 | — | — | 4307.56 (6.96x) | 1483.18 (2.40x) |
| Any UInt32Value String WKT JSON parse | 617.16 | — | — | 4105.23 (6.65x) | 1459.11 (2.36x) |
| Any ZeroUInt32Value WKT JSON stringify | 222.01 | — | — | 1221.51 (5.50x) | 711.69 (3.21x) |
| Any ZeroUInt32Value WKT JSON parse | 609.31 | — | — | 2892.05 (4.75x) | 1498.05 (2.46x) |
| Any MaxUInt32Value WKT JSON stringify | 226.07 | — | — | 2085.82 (9.23x) | 760.44 (3.36x) |
| Any MaxUInt32Value WKT JSON parse | 615.68 | — | — | 2824.28 (4.59x) | 1479.62 (2.40x) |
| Any BoolValue WKT JSON stringify | 213.78 | — | — | 2204.90 (10.31x) | 730.05 (3.41x) |
| Any BoolValue WKT JSON parse | 548.16 | — | — | 4107.63 (7.49x) | 1273.57 (2.32x) |
| Any FalseBoolValue WKT JSON stringify | 215.14 | — | — | 1330.65 (6.19x) | 705.30 (3.28x) |
| Any FalseBoolValue WKT JSON parse | 547.23 | — | — | 3230.45 (5.90x) | 1267.48 (2.32x) |
| Any StringValue WKT JSON stringify | 210.14 | — | — | 1559.43 (7.42x) | 826.88 (3.93x) |
| Any StringValue WKT JSON parse | 568.21 | — | — | 2646.23 (4.66x) | 1425.63 (2.51x) |
| Any EmptyStringValue WKT JSON stringify | 192.40 | — | — | 1359.67 (7.07x) | 744.31 (3.87x) |
| Any EmptyStringValue WKT JSON parse | 520.67 | — | — | 3138.77 (6.03x) | 1384.55 (2.66x) |
| Any BytesValue WKT JSON stringify | 193.00 | — | — | 1576.94 (8.17x) | 873.39 (4.53x) |
| Any BytesValue WKT JSON parse | 568.13 | — | — | 2676.05 (4.71x) | 1524.87 (2.68x) |
| Any EmptyBytesValue WKT JSON stringify | 188.88 | — | — | 937.60 (4.96x) | 780.77 (4.13x) |
| Any EmptyBytesValue WKT JSON parse | 531.45 | — | — | 2182.87 (4.11x) | 1378.67 (2.59x) |
| Nested Any WKT JSON stringify | 308.42 | — | — | 2464.70 (7.99x) | 1593.28 (5.17x) |
| Nested Any WKT JSON parse | 856.72 | — | — | 4268.07 (4.98x) | 2911.20 (3.40x) |
| Duration JSON stringify | 58.15 | — | — | 966.54 (16.62x) | 353.17 (6.07x) |
| Duration JSON parse | 7.91 | — | — | 1456.27 (184.10x) | 383.79 (48.52x) |
| PlusDuration JSON parse | 7.82 | — | — | 1477.69 (188.96x) | 392.86 (50.24x) |
| ShortFractionDuration JSON parse | 6.39 | — | — | 1440.67 (225.46x) | 364.42 (57.03x) |
| MicroDuration JSON stringify | 59.54 | — | — | 972.13 (16.33x) | 385.49 (6.47x) |
| MicroDuration JSON parse | 10.03 | — | — | 1469.08 (146.47x) | 371.23 (37.01x) |
| NanoDuration JSON stringify | 57.13 | — | — | 993.89 (17.40x) | 388.31 (6.80x) |
| NanoDuration JSON parse | 12.39 | — | — | 1476.52 (119.17x) | 364.26 (29.40x) |
| NegativeDuration JSON stringify | 60.07 | — | — | 998.13 (16.62x) | 401.94 (6.69x) |
| NegativeDuration JSON parse | 7.90 | — | — | 1502.69 (190.21x) | 377.32 (47.76x) |
| FractionalNegativeDuration JSON stringify | 60.10 | — | — | 968.19 (16.11x) | 415.04 (6.91x) |
| FractionalNegativeDuration JSON parse | 7.90 | — | — | 1455.18 (184.20x) | 378.01 (47.85x) |
| MaxDuration JSON stringify | 50.31 | — | — | 853.12 (16.96x) | 397.26 (7.90x) |
| MaxDuration JSON parse | 22.21 | — | — | 1439.93 (64.83x) | 393.22 (17.70x) |
| MinDuration JSON stringify | 49.93 | — | — | 872.45 (17.47x) | 424.55 (8.50x) |
| MinDuration JSON parse | 25.96 | — | — | 1448.43 (55.79x) | 375.66 (14.47x) |
| ZeroDuration JSON stringify | 44.88 | — | — | 817.03 (18.20x) | 340.94 (7.60x) |
| ZeroDuration JSON parse | 5.60 | — | — | 1364.20 (243.61x) | 315.81 (56.39x) |
| FieldMask JSON stringify | 136.78 | — | — | 878.51 (6.42x) | 673.21 (4.92x) |
| FieldMask JSON parse | 149.18 | — | — | 1652.05 (11.07x) | 896.35 (6.01x) |
| EmptyFieldMask JSON stringify | 40.85 | — | — | 609.63 (14.92x) | 190.21 (4.66x) |
| EmptyFieldMask JSON parse | 2.52 | — | — | 941.07 (373.44x) | 177.20 (70.32x) |
| Timestamp JSON stringify | 96.17 | — | — | 1146.75 (11.92x) | 394.31 (4.10x) |
| Timestamp JSON parse | 41.24 | — | — | 1488.30 (36.09x) | 413.75 (10.03x) |
| Micro Timestamp JSON stringify | 96.72 | — | — | 1156.90 (11.96x) | 425.26 (4.40x) |
| Micro Timestamp JSON parse | 42.95 | — | — | 1503.74 (35.01x) | 443.17 (10.32x) |
| Nano Timestamp JSON stringify | 95.24 | — | — | 1195.15 (12.55x) | 442.78 (4.65x) |
| Nano Timestamp JSON parse | 44.85 | — | — | 1522.37 (33.94x) | 446.13 (9.95x) |
| Offset Timestamp JSON parse | 48.93 | — | — | 1532.10 (31.31x) | 477.70 (9.76x) |
| PreEpoch Timestamp JSON stringify | 66.87 | — | — | 1076.37 (16.10x) | 463.60 (6.93x) |
| PreEpoch Timestamp JSON parse | 39.99 | — | — | 1466.64 (36.68x) | 419.36 (10.49x) |
| Max Timestamp JSON stringify | 79.72 | — | — | 1205.75 (15.12x) | 430.75 (5.40x) |
| Max Timestamp JSON parse | 46.87 | — | — | 1538.63 (32.83x) | 430.42 (9.18x) |
| Min Timestamp JSON stringify | 79.82 | — | — | 1058.03 (13.26x) | 383.34 (4.80x) |
| Min Timestamp JSON parse | 37.80 | — | — | 1451.68 (38.40x) | 418.10 (11.06x) |
| Empty JSON stringify | 20.83 | — | — | 495.87 (23.81x) | 99.01 (4.75x) |
| Empty JSON parse | 67.38 | — | — | 721.92 (10.71x) | 200.24 (2.97x) |
| Struct JSON stringify | 179.66 | — | — | 5767.30 (32.10x) | 3121.61 (17.38x) |
| Struct JSON parse | 873.98 | — | — | 10994.90 (12.58x) | 4672.51 (5.35x) |
| EmptyStruct JSON stringify | 41.22 | — | — | 692.03 (16.79x) | 352.64 (8.56x) |
| EmptyStruct JSON parse | 100.95 | — | — | 2043.40 (20.24x) | 348.00 (3.45x) |
| Value JSON stringify | 176.22 | — | — | 6645.97 (37.71x) | 3136.54 (17.80x) |
| Value JSON parse | 864.19 | — | — | 12241.20 (14.16x) | 5528.50 (6.40x) |
| NullValue JSON stringify | 40.86 | — | — | 1316.43 (32.22x) | 232.46 (5.69x) |
| NullValue JSON parse | 64.92 | — | — | 2468.20 (38.02x) | 342.47 (5.28x) |
| StringScalarValue JSON stringify | 48.52 | — | — | 1342.59 (27.67x) | 279.94 (5.77x) |
| StringScalarValue JSON parse | 136.24 | — | — | 2090.71 (15.35x) | 427.24 (3.14x) |
| EmptyStringScalarValue JSON stringify | 46.58 | — | — | 1335.89 (28.68x) | 276.92 (5.95x) |
| EmptyStringScalarValue JSON parse | 82.71 | — | — | 2069.37 (25.02x) | 357.45 (4.32x) |
| NumberValue JSON stringify | 74.45 | — | — | 1553.09 (20.86x) | 359.00 (4.82x) |
| NumberValue JSON parse | 127.07 | — | — | 2173.74 (17.11x) | 415.70 (3.27x) |
| ZeroNumberValue JSON stringify | 51.38 | — | — | 1514.10 (29.47x) | 282.78 (5.50x) |
| ZeroNumberValue JSON parse | 124.61 | — | — | 2110.40 (16.94x) | 349.17 (2.80x) |
| BoolScalarValue JSON stringify | 41.01 | — | — | 1311.71 (31.99x) | 220.40 (5.37x) |
| BoolScalarValue JSON parse | 64.91 | — | — | 2005.61 (30.90x) | 376.56 (5.80x) |
| FalseBoolScalarValue JSON stringify | 40.91 | — | — | 1310.65 (32.04x) | 227.02 (5.55x) |
| FalseBoolScalarValue JSON parse | 65.43 | — | — | 2008.61 (30.70x) | 312.24 (4.77x) |
| ListKindValue JSON stringify | 139.20 | — | — | 6128.41 (44.03x) | 2422.65 (17.40x) |
| ListKindValue JSON parse | 665.21 | — | — | 10390.70 (15.62x) | 4342.96 (6.53x) |
| EmptyStructKindValue JSON stringify | 42.92 | — | — | 1952.92 (45.50x) | 549.20 (12.80x) |
| EmptyStructKindValue JSON parse | 105.26 | — | — | 3744.84 (35.58x) | 652.75 (6.20x) |
| EmptyListKindValue JSON stringify | 41.79 | — | — | 1941.12 (46.45x) | 355.36 (8.50x) |
| EmptyListKindValue JSON parse | 142.33 | — | — | 4027.48 (28.30x) | 586.40 (4.12x) |
| ListValue JSON stringify | 147.74 | — | — | 5420.61 (36.69x) | 2145.31 (14.52x) |
| ListValue JSON parse | 676.53 | — | — | 8645.92 (12.78x) | 4065.29 (6.01x) |
| EmptyListValue JSON stringify | 40.71 | — | — | 688.20 (16.90x) | 186.49 (4.58x) |
| EmptyListValue JSON parse | 139.96 | — | — | 2270.59 (16.22x) | 306.48 (2.19x) |
| DoubleValue JSON stringify | 68.78 | — | — | 865.27 (12.58x) | 196.88 (2.86x) |
| DoubleValue JSON parse | 112.28 | — | — | 1228.44 (10.94x) | 280.72 (2.50x) |
| NegativeDoubleValue JSON stringify | 67.92 | — | — | 866.45 (12.76x) | 209.44 (3.08x) |
| NegativeDoubleValue JSON parse | 112.55 | — | — | 1232.51 (10.95x) | 300.00 (2.67x) |
| ZeroDoubleValue JSON stringify | 47.46 | — | — | 806.77 (17.00x) | 140.07 (2.95x) |
| ZeroDoubleValue JSON parse | 109.28 | — | — | 1162.25 (10.64x) | 269.84 (2.47x) |
| DoubleValue NaN JSON stringify | 47.75 | — | — | 677.39 (14.19x) | 117.82 (2.47x) |
| DoubleValue NaN JSON parse | 104.49 | — | — | 1103.39 (10.56x) | 271.76 (2.60x) |
| DoubleValue Infinity JSON stringify | 48.59 | — | — | 667.26 (13.73x) | 114.00 (2.35x) |
| DoubleValue Infinity JSON parse | 105.59 | — | — | 1230.35 (11.65x) | 280.88 (2.66x) |
| DoubleValue NegativeInfinity JSON stringify | 48.72 | — | — | 662.47 (13.60x) | 143.41 (2.94x) |
| DoubleValue NegativeInfinity JSON parse | 108.63 | — | — | 1106.07 (10.18x) | 278.39 (2.56x) |
| FloatValue JSON stringify | 70.65 | — | — | 795.68 (11.26x) | 207.94 (2.94x) |
| FloatValue JSON parse | 112.93 | — | — | 1212.65 (10.74x) | 285.22 (2.53x) |
| NegativeFloatValue JSON stringify | 71.02 | — | — | 797.30 (11.23x) | 186.70 (2.63x) |
| NegativeFloatValue JSON parse | 113.48 | — | — | 1221.12 (10.76x) | 290.90 (2.56x) |
| ZeroFloatValue JSON stringify | 47.43 | — | — | 1014.84 (21.40x) | 133.80 (2.82x) |
| ZeroFloatValue JSON parse | 109.85 | — | — | 1258.11 (11.45x) | 274.22 (2.50x) |
| FloatValue NaN JSON stringify | 46.73 | — | — | 635.64 (13.60x) | 146.81 (3.14x) |
| FloatValue NaN JSON parse | 105.28 | — | — | 1081.88 (10.28x) | 262.84 (2.50x) |
| FloatValue Infinity JSON stringify | 48.26 | — | — | 638.16 (13.22x) | 119.43 (2.47x) |
| FloatValue Infinity JSON parse | 106.03 | — | — | 1095.57 (10.33x) | 261.65 (2.47x) |
| FloatValue NegativeInfinity JSON stringify | 48.38 | — | — | 635.02 (13.13x) | 118.97 (2.46x) |
| FloatValue NegativeInfinity JSON parse | 108.65 | — | — | 1119.05 (10.30x) | 261.82 (2.41x) |
| Int64Value JSON stringify | 50.11 | — | — | 994.63 (19.85x) | 272.61 (5.44x) |
| Int64Value JSON parse | 126.25 | — | — | 1225.80 (9.71x) | 451.17 (3.57x) |
| Int64Value Number JSON parse | 128.20 | — | — | 1292.52 (10.08x) | 374.96 (2.92x) |
| ZeroInt64Value JSON stringify | 41.50 | — | — | 629.10 (15.16x) | 198.87 (4.79x) |
| ZeroInt64Value JSON parse | 105.92 | — | — | 1109.30 (10.47x) | 334.95 (3.16x) |
| NegativeInt64Value JSON stringify | 48.45 | — | — | 673.93 (13.91x) | 276.05 (5.70x) |
| NegativeInt64Value JSON parse | 127.22 | — | — | 1210.66 (9.52x) | 459.41 (3.61x) |
| MinInt64Value JSON stringify | 50.24 | — | — | 672.42 (13.38x) | 276.27 (5.50x) |
| MinInt64Value JSON parse | 134.72 | — | — | 1274.57 (9.46x) | 484.76 (3.60x) |
| MaxInt64Value JSON stringify | 49.35 | — | — | 674.88 (13.68x) | 273.92 (5.55x) |
| MaxInt64Value JSON parse | 133.04 | — | — | 1236.02 (9.29x) | 460.67 (3.46x) |
| UInt64Value JSON stringify | 50.31 | — | — | 1083.12 (21.53x) | 268.41 (5.34x) |
| UInt64Value JSON parse | 125.12 | — | — | 1943.77 (15.54x) | 436.51 (3.49x) |
| UInt64Value Number JSON parse | 127.73 | — | — | 2028.84 (15.88x) | 344.75 (2.70x) |
| ZeroUInt64Value JSON stringify | 41.87 | — | — | 1096.95 (26.20x) | 197.41 (4.71x) |
| ZeroUInt64Value JSON parse | 103.82 | — | — | 1214.79 (11.70x) | 325.83 (3.14x) |
| MaxUInt64Value JSON stringify | 50.16 | — | — | 676.62 (13.49x) | 290.05 (5.78x) |
| MaxUInt64Value JSON parse | 135.73 | — | — | 1247.91 (9.19x) | 455.73 (3.36x) |
| Int32Value JSON stringify | 46.39 | — | — | 645.42 (13.91x) | 153.81 (3.32x) |
| Int32Value JSON parse | 118.77 | — | — | 1209.92 (10.19x) | 302.77 (2.55x) |
| Int32Value String JSON parse | 114.17 | — | — | 1165.84 (10.21x) | 410.27 (3.59x) |
| ZeroInt32Value JSON stringify | 46.30 | — | — | 608.68 (13.15x) | 122.12 (2.64x) |
| ZeroInt32Value JSON parse | 114.68 | — | — | 1148.38 (10.01x) | 266.52 (2.32x) |
| NegativeInt32Value JSON stringify | 46.28 | — | — | 634.45 (13.71x) | 154.47 (3.34x) |
| NegativeInt32Value JSON parse | 118.61 | — | — | 1193.56 (10.06x) | 328.15 (2.77x) |
| MinInt32Value JSON stringify | 46.90 | — | — | 643.08 (13.71x) | 151.10 (3.22x) |
| MinInt32Value JSON parse | 123.71 | — | — | 1250.30 (10.11x) | 340.90 (2.76x) |
| MaxInt32Value JSON stringify | 47.16 | — | — | 1087.24 (23.05x) | 131.88 (2.80x) |
| MaxInt32Value JSON parse | 124.25 | — | — | 3597.13 (28.95x) | 328.74 (2.65x) |
| UInt32Value JSON stringify | 46.18 | — | — | 1127.37 (24.41x) | 148.07 (3.21x) |
| UInt32Value JSON parse | 118.43 | — | — | 2538.03 (21.43x) | 317.50 (2.68x) |
| UInt32Value String JSON parse | 114.73 | — | — | 3634.12 (31.68x) | 379.34 (3.31x) |
| ZeroUInt32Value JSON stringify | 46.32 | — | — | 847.06 (18.29x) | 146.71 (3.17x) |
| ZeroUInt32Value JSON parse | 114.27 | — | — | 1567.95 (13.72x) | 259.49 (2.27x) |
| MaxUInt32Value JSON stringify | 46.91 | — | — | 854.05 (18.21x) | 133.33 (2.84x) |
| MaxUInt32Value JSON parse | 124.05 | — | — | 1609.24 (12.97x) | 333.06 (2.68x) |
| BoolValue JSON stringify | 47.02 | — | — | 622.96 (13.25x) | 141.46 (3.01x) |
| BoolValue JSON parse | 56.28 | — | — | 1073.13 (19.07x) | 200.99 (3.57x) |
| FalseBoolValue JSON stringify | 47.19 | — | — | 929.22 (19.69x) | 143.63 (3.04x) |
| FalseBoolValue JSON parse | 56.65 | — | — | 1704.25 (30.08x) | 217.80 (3.84x) |
| StringValue JSON stringify | 59.97 | — | — | 1052.13 (17.54x) | 188.27 (3.14x) |
| StringValue JSON parse | 135.41 | — | — | 1850.41 (13.67x) | 294.54 (2.18x) |
| EmptyStringValue JSON stringify | 50.32 | — | — | 983.94 (19.55x) | 181.58 (3.61x) |
| EmptyStringValue JSON parse | 83.18 | — | — | 1818.88 (21.87x) | 227.07 (2.73x) |
| BytesValue JSON stringify | 50.66 | — | — | 947.42 (18.70x) | 217.71 (4.30x) |
| BytesValue JSON parse | 151.14 | — | — | 1331.84 (8.81x) | 332.10 (2.20x) |
| EmptyBytesValue JSON stringify | 42.17 | — | — | 673.53 (15.97x) | 211.72 (5.02x) |
| EmptyBytesValue JSON parse | 92.27 | — | — | 1176.51 (12.75x) | 279.77 (3.03x) |
| TextFormat format | 184.14 | — | — | 2586.52 (14.05x) | 2327.65 (12.64x) |
| TextFormat parse | 734.00 | — | — | 4976.46 (6.78x) | 6444.79 (8.78x) |
| packed fixed32 encode | 2.01 | 553.80 (275.52x) | 540.10 (268.71x) | 90.36 (44.96x) | 411.35 (204.65x) |
| packed fixed32 decode | 4.53 | 1000.77 (220.92x) | 1952.29 (430.97x) | 99.79 (22.03x) | 1677.13 (370.23x) |
| packed fixed64 encode | 2.01 | 583.67 (290.38x) | 566.96 (282.07x) | 155.28 (77.25x) | 574.57 (285.86x) |
| packed fixed64 decode | 4.52 | 1029.21 (227.70x) | 7963.11 (1761.75x) | 164.13 (36.31x) | 2502.62 (553.68x) |
| packed sfixed32 encode | 2.77 | 553.20 (199.71x) | 539.50 (194.77x) | 90.82 (32.79x) | 461.51 (166.61x) |
| packed sfixed32 decode | 7.38 | 1047.97 (142.00x) | 1964.00 (266.12x) | 97.74 (13.24x) | 1734.99 (235.09x) |
| packed sfixed64 encode | 2.01 | 572.38 (284.77x) | 562.93 (280.06x) | 155.44 (77.34x) | 397.53 (197.78x) |
| packed sfixed64 decode | 4.53 | 1046.39 (230.99x) | 7951.45 (1755.29x) | 161.19 (35.58x) | 2362.12 (521.44x) |
| packed float encode | 2.01 | 817.51 (406.72x) | 541.80 (269.55x) | 91.02 (45.28x) | 359.80 (179.00x) |
| packed float decode | 4.52 | 1081.39 (239.25x) | 2081.31 (460.47x) | 97.68 (21.61x) | 1663.91 (368.12x) |
| packed double encode | 2.00 | 851.36 (425.68x) | 563.18 (281.59x) | 155.18 (77.59x) | 361.74 (180.87x) |
| packed double decode | 4.53 | 980.87 (216.53x) | 2066.61 (456.21x) | 161.07 (35.56x) | 2674.59 (590.42x) |
| packed uint64 encode | 1293.37 | 4610.30 (3.56x) | 4024.94 (3.11x) | 3144.62 (2.43x) | 3457.43 (2.67x) |
| packed uint64 decode | 1786.08 | 2833.79 (1.59x) | 8851.34 (4.96x) | 5089.08 (2.85x) | 8609.07 (4.82x) |
| packed uint32 encode | 933.23 | 3683.40 (3.95x) | 3281.39 (3.52x) | 2736.90 (2.93x) | 2885.33 (3.09x) |
| packed uint32 decode | 1312.69 | 2612.69 (1.99x) | 3262.67 (2.49x) | 3447.99 (2.63x) | 6361.18 (4.85x) |
| packed int64 encode | 1382.31 | 11008.60 (7.96x) | 6087.52 (4.40x) | 2902.57 (2.10x) | 4159.28 (3.01x) |
| packed int64 decode | 2740.74 | 3495.26 (1.28x) | 10270.93 (3.75x) | 4807.01 (1.75x) | 10241.34 (3.74x) |
| packed sint32 encode | 831.92 | 3034.63 (3.65x) | 2849.58 (3.43x) | 1544.02 (1.86x) | 3377.26 (4.06x) |
| packed sint32 decode | 937.97 | 2582.47 (2.75x) | 3225.50 (3.44x) | 1130.05 (1.20x) | 4496.96 (4.79x) |
| packed sint64 encode | 1420.53 | 4955.08 (3.49x) | 4525.26 (3.19x) | 2421.53 (1.70x) | 4471.47 (3.15x) |
| packed sint64 decode | 2032.77 | 3086.22 (1.52x) | 9676.42 (4.76x) | 2938.46 (1.45x) | 9115.06 (4.48x) |
| packed bool encode | 2.01 | 1349.63 (671.46x) | 520.50 (258.96x) | 15.75 (7.84x) | 3267.56 (1625.65x) |
| packed bool decode | 262.66 | 1556.38 (5.93x) | 2554.10 (9.72x) | 814.44 (3.10x) | 2079.06 (7.92x) |
| packed enum encode | 271.84 | 2764.04 (10.17x) | 1887.77 (6.94x) | 1090.27 (4.01x) | 2608.07 (9.59x) |
| packed enum decode | 187.56 | 1556.86 (8.30x) | 2910.04 (15.52x) | 770.39 (4.11x) | 2436.18 (12.99x) |
| large map encode | 3915.69 | 16461.64 (4.20x) | 9657.25 (2.47x) | 23133.90 (5.91x) | 201217.56 (51.39x) |
| shuffled large map deterministic binary encode | 27845.41 | — | — | 104069.00 (3.74x) | 378338.52 (13.59x) |
| large map decode | 25515.04 | 92807.53 (3.64x) | 89223.98 (3.50x) | 91939.40 (3.60x) | 269272.04 (10.55x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded zero/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound `Duration`, non-empty and empty `Struct`, object/list/scalar `Value` (including default-like scalar and empty object/list kinds),
`FieldMask` (non-empty and empty), micro/nano/offset/min/pre/post/max-bound `Timestamp`, `Empty`, min/zero/positive/number-input parse/negative/max `Int64Value`, negative/zero/positive finite `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), negative/zero/positive finite `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), zero/normal/number-input parse/max `UInt64Value`, min/zero/positive/string-input parse/negative/max `Int32Value`, zero/normal/string-input parse/max `UInt32Value`, true/false `BoolValue`, non-empty/empty `StringValue`, base64/empty `BytesValue`, and recursive nested `Any` payloads), direct zero/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound Duration and micro/nano/offset/min/pre/post/max-bound Timestamp WKT JSON plus other direct WKT JSON, including empty `Struct` and empty `ListValue`, TextFormat, packed scalars, large bytes,
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
