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

Latest accepted comparison (`/tmp/pbz-compare-map-key-surrogate-json-final.log`,
summarized in `/tmp/pbz-summary-map-key-surrogate-json-final.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 19.30 | 107.19 (5.55x) | 52.48 (2.72x) | 103.62 (5.37x) | 850.07 (44.05x) |
| binary decode | 90.34 | 251.74 (2.79x) | 229.87 (2.54x) | 202.95 (2.25x) | 914.37 (10.12x) |
| unknown fields count by number | 3.57 | — | — | 161.77 (45.31x) | — |
| deterministic binary encode | 57.77 | — | — | 131.61 (2.28x) | 1150.06 (19.91x) |
| scalarmix encode | 19.39 | 152.81 (7.88x) | 48.48 (2.50x) | 27.84 (1.44x) | 211.03 (10.88x) |
| scalarmix decode | 34.23 | 224.40 (6.56x) | 173.58 (5.07x) | 82.79 (2.42x) | 310.70 (9.08x) |
| textbytes encode | 9.52 | 103.91 (10.91x) | 33.80 (3.55x) | 117.24 (12.32x) | 157.49 (16.54x) |
| textbytes decode | 48.56 | 380.69 (7.84x) | 240.19 (4.95x) | 167.81 (3.46x) | 672.35 (13.85x) |
| largebytes encode | 25.81 | 2703.87 (104.76x) | 2669.14 (103.41x) | 2687.66 (104.13x) | 2706.55 (104.86x) |
| largebytes decode | 88.43 | 5611.00 (63.45x) | 3002.39 (33.95x) | 2730.03 (30.87x) | 20884.54 (236.17x) |
| presencemix encode | 17.01 | 55.36 (3.25x) | 29.57 (1.74x) | 57.07 (3.36x) | 231.93 (13.63x) |
| presencemix decode | 55.44 | 134.18 (2.42x) | 109.66 (1.98x) | 160.16 (2.89x) | 491.65 (8.87x) |
| complex encode | 48.07 | 137.55 (2.86x) | 94.21 (1.96x) | 161.83 (3.37x) | 983.47 (20.46x) |
| complex decode | 171.10 | 405.69 (2.37x) | 343.56 (2.01x) | 395.00 (2.31x) | 1351.90 (7.90x) |
| complex deterministic binary encode | 91.58 | — | — | 170.12 (1.86x) | 1165.62 (12.73x) |
| complex JSON stringify | 271.20 | — | — | 4874.74 (17.97x) | 6499.83 (23.97x) |
| complex JSON parse | 2381.44 | — | — | 12054.30 (5.06x) | 7522.28 (3.16x) |
| complex TextFormat format | 273.35 | — | — | 3803.85 (13.92x) | 5798.83 (21.21x) |
| complex TextFormat parse | 1860.10 | — | — | 6898.27 (3.71x) | 8471.41 (4.55x) |
| packed int32 encode | 638.15 | 3178.26 (4.98x) | 2521.50 (3.95x) | 1232.10 (1.93x) | 2748.65 (4.31x) |
| packed int32 decode | 697.25 | 1903.03 (2.73x) | 3219.44 (4.62x) | 932.18 (1.34x) | 2556.80 (3.67x) |
| JSON stringify | 163.06 | — | — | 3005.17 (18.43x) | 2397.02 (14.70x) |
| JSON parse | 1528.88 | — | — | 7496.97 (4.90x) | 4757.18 (3.11x) |
| MapKeySurrogate JSON parse | 430.42 | — | — | 3541.58 (8.23x) | 1063.56 (2.47x) |
| Any WKT JSON stringify | 137.88 | — | — | 1875.88 (13.61x) | 979.66 (7.11x) |
| Any WKT JSON parse | 526.38 | — | — | 2972.87 (5.65x) | 1546.37 (2.94x) |
| Any Duration Escape WKT JSON parse | 541.80 | — | — | 3002.18 (5.54x) | 1619.69 (2.99x) |
| Any PlusDuration WKT JSON parse | 525.52 | — | — | 3011.48 (5.73x) | 1554.82 (2.96x) |
| Any ShortFractionDuration WKT JSON parse | 521.40 | — | — | 2950.82 (5.66x) | 1514.47 (2.90x) |
| Any MicroDuration WKT JSON stringify | 139.66 | — | — | 1888.17 (13.52x) | 966.58 (6.92x) |
| Any MicroDuration WKT JSON parse | 529.14 | — | — | 2989.65 (5.65x) | 1544.41 (2.92x) |
| Any NanoDuration WKT JSON stringify | 134.69 | — | — | 1910.14 (14.18x) | 985.67 (7.32x) |
| Any NanoDuration WKT JSON parse | 533.51 | — | — | 2998.06 (5.62x) | 1552.10 (2.91x) |
| Any NegativeDuration WKT JSON stringify | 141.63 | — | — | 1930.04 (13.63x) | 1010.98 (7.14x) |
| Any NegativeDuration WKT JSON parse | 529.08 | — | — | 3097.27 (5.85x) | 1585.36 (3.00x) |
| Any FractionalNegativeDuration WKT JSON stringify | 134.95 | — | — | 1887.42 (13.99x) | 996.33 (7.38x) |
| Any FractionalNegativeDuration WKT JSON parse | 521.84 | — | — | 3056.96 (5.86x) | 1534.49 (2.94x) |
| Any MaxDuration WKT JSON stringify | 122.08 | — | — | 1745.03 (14.29x) | 990.04 (8.11x) |
| Any MaxDuration WKT JSON parse | 540.16 | — | — | 2964.86 (5.49x) | 1559.53 (2.89x) |
| Any MinDuration WKT JSON stringify | 120.69 | — | — | 1753.25 (14.53x) | 1006.52 (8.34x) |
| Any MinDuration WKT JSON parse | 541.82 | — | — | 3014.23 (5.56x) | 1551.75 (2.86x) |
| Any ZeroDuration WKT JSON stringify | 110.78 | — | — | 911.78 (8.23x) | 953.92 (8.61x) |
| Any ZeroDuration WKT JSON parse | 474.23 | — | — | 2243.47 (4.73x) | 1458.83 (3.08x) |
| Any FieldMask WKT JSON stringify | 230.47 | — | — | 1740.80 (7.55x) | 1406.52 (6.10x) |
| Any FieldMask WKT JSON parse | 715.97 | — | — | 3140.84 (4.39x) | 2113.95 (2.95x) |
| Any FieldMask Escape WKT JSON parse | 753.64 | — | — | 3226.76 (4.28x) | 2239.02 (2.97x) |
| Any EmptyFieldMask WKT JSON stringify | 118.03 | — | — | 916.31 (7.76x) | 776.26 (6.58x) |
| Any EmptyFieldMask WKT JSON parse | 445.80 | — | — | 2178.80 (4.89x) | 1312.40 (2.94x) |
| Any Timestamp WKT JSON stringify | 182.33 | — | — | 2015.63 (11.05x) | 1009.31 (5.54x) |
| Any Timestamp WKT JSON parse | 575.75 | — | — | 3010.85 (5.23x) | 1618.68 (2.81x) |
| Any Timestamp Escape WKT JSON parse | 598.17 | — | — | 3056.34 (5.11x) | 1758.08 (2.94x) |
| Any ShortFraction Timestamp WKT JSON parse | 571.63 | — | — | 2999.68 (5.25x) | 1603.61 (2.81x) |
| Any Micro Timestamp WKT JSON stringify | 188.12 | — | — | 2018.95 (10.73x) | 1006.95 (5.35x) |
| Any Micro Timestamp WKT JSON parse | 582.50 | — | — | 3019.20 (5.18x) | 1653.42 (2.84x) |
| Any Nano Timestamp WKT JSON stringify | 184.10 | — | — | 2020.74 (10.98x) | 1016.68 (5.52x) |
| Any Nano Timestamp WKT JSON parse | 590.65 | — | — | 3024.55 (5.12x) | 1642.75 (2.78x) |
| Any Offset Timestamp WKT JSON parse | 596.66 | — | — | 3048.69 (5.11x) | 1658.24 (2.78x) |
| Any PreEpoch Timestamp WKT JSON stringify | 145.90 | — | — | 1933.93 (13.26x) | 980.41 (6.72x) |
| Any PreEpoch Timestamp WKT JSON parse | 568.90 | — | — | 3034.66 (5.33x) | 1599.17 (2.81x) |
| Any Max Timestamp WKT JSON stringify | 166.56 | — | — | 2034.63 (12.22x) | 1017.04 (6.11x) |
| Any Max Timestamp WKT JSON parse | 593.89 | — | — | 3081.01 (5.19x) | 1654.41 (2.79x) |
| Any Min Timestamp WKT JSON stringify | 167.06 | — | — | 1928.48 (11.54x) | 977.08 (5.85x) |
| Any Min Timestamp WKT JSON parse | 562.18 | — | — | 3025.03 (5.38x) | 1589.35 (2.83x) |
| Any Empty WKT JSON stringify | 92.38 | — | — | 912.95 (9.88x) | 671.46 (7.27x) |
| Any Empty WKT JSON parse | 336.98 | — | — | 2110.56 (6.26x) | 1389.39 (4.12x) |
| Any Struct WKT JSON stringify | 631.69 | — | — | 5859.74 (9.28x) | 6029.32 (9.54x) |
| Any Struct WKT JSON parse | 1776.34 | — | — | 11112.10 (6.26x) | 8758.49 (4.93x) |
| Any Struct Escape WKT JSON parse | 1798.69 | — | — | 11178.90 (6.22x) | 8866.24 (4.93x) |
| Any Struct NumberExponent WKT JSON parse | 1775.85 | — | — | 11103.40 (6.25x) | 8694.27 (4.90x) |
| Any Struct Surrogate WKT JSON parse | 766.40 | — | — | 6365.79 (8.31x) | 3075.83 (4.01x) |
| Any Struct KeySurrogate WKT JSON parse | 766.87 | — | — | 6303.82 (8.22x) | 3103.79 (4.05x) |
| Any EmptyStruct WKT JSON stringify | 125.74 | — | — | 910.77 (7.24x) | 949.03 (7.55x) |
| Any EmptyStruct WKT JSON parse | 439.49 | — | — | 2227.86 (5.07x) | 1576.83 (3.59x) |
| Any Value WKT JSON stringify | 665.80 | — | — | 5904.50 (8.87x) | 6367.48 (9.56x) |
| Any Value WKT JSON parse | 1834.36 | — | — | 11310.70 (6.17x) | 9135.40 (4.98x) |
| Any Value Escape WKT JSON parse | 1859.65 | — | — | 11385.90 (6.12x) | 9235.95 (4.97x) |
| Any Value NumberExponent WKT JSON parse | 1837.65 | — | — | 11295.40 (6.15x) | 9125.71 (4.97x) |
| Any Value Surrogate WKT JSON parse | 829.90 | — | — | 6511.88 (7.85x) | 3466.65 (4.18x) |
| Any Value KeySurrogate WKT JSON parse | 829.73 | — | — | 6503.16 (7.84x) | 3472.17 (4.18x) |
| Any NullValue WKT JSON stringify | 136.06 | — | — | 2248.70 (16.53x) | 916.57 (6.74x) |
| Any NullValue WKT JSON parse | 466.30 | — | — | 4033.55 (8.65x) | 1596.76 (3.42x) |
| Any StringScalarValue WKT JSON stringify | 164.74 | — | — | 2259.89 (13.72x) | 1024.06 (6.22x) |
| Any StringScalarValue WKT JSON parse | 519.47 | — | — | 3623.54 (6.98x) | 1685.03 (3.24x) |
| Any StringScalarValue Escape WKT JSON parse | 534.31 | — | — | 3662.46 (6.85x) | 1744.05 (3.26x) |
| Any StringScalarValue Surrogate WKT JSON parse | 534.54 | — | — | 3656.11 (6.84x) | 1742.83 (3.26x) |
| Any EmptyStringScalarValue WKT JSON stringify | 146.44 | — | — | 2265.85 (15.47x) | 992.27 (6.78x) |
| Any EmptyStringScalarValue WKT JSON parse | 488.35 | — | — | 3591.11 (7.35x) | 1590.64 (3.26x) |
| Any NumberValue WKT JSON stringify | 183.03 | — | — | 2506.45 (13.69x) | 1101.40 (6.02x) |
| Any NumberValue WKT JSON parse | 505.97 | — | — | 3689.21 (7.29x) | 1619.05 (3.20x) |
| Any NumberValue Exponent WKT JSON parse | 509.02 | — | — | 3686.03 (7.24x) | 1615.52 (3.17x) |
| Any NegativeNumberValue WKT JSON stringify | 181.35 | — | — | 2501.86 (13.80x) | 1038.08 (5.72x) |
| Any NegativeNumberValue WKT JSON parse | 505.05 | — | — | 3699.17 (7.32x) | 1616.24 (3.20x) |
| Any ZeroNumberValue WKT JSON stringify | 146.32 | — | — | 2462.10 (16.83x) | 924.66 (6.32x) |
| Any ZeroNumberValue WKT JSON parse | 501.70 | — | — | 3621.30 (7.22x) | 1625.00 (3.24x) |
| Any BoolScalarValue WKT JSON stringify | 135.82 | — | — | 2246.79 (16.54x) | 916.60 (6.75x) |
| Any BoolScalarValue WKT JSON parse | 464.94 | — | — | 3582.32 (7.70x) | 1548.21 (3.33x) |
| Any FalseBoolScalarValue WKT JSON stringify | 135.93 | — | — | 2244.17 (16.51x) | 917.40 (6.75x) |
| Any FalseBoolScalarValue WKT JSON parse | 465.55 | — | — | 3585.08 (7.70x) | 1541.89 (3.31x) |
| Any ListKindValue WKT JSON stringify | 500.96 | — | — | 5559.42 (11.10x) | 4674.71 (9.33x) |
| Any ListKindValue WKT JSON parse | 1403.26 | — | — | 9884.18 (7.04x) | 7102.40 (5.06x) |
| Any ListKindValue Escape WKT JSON parse | 1425.75 | — | — | 9981.67 (7.00x) | 7317.06 (5.13x) |
| Any ListKindValue Surrogate WKT JSON parse | 726.86 | — | — | 4819.68 (6.63x) | 2665.25 (3.67x) |
| Any EmptyStructKindValue WKT JSON stringify | 148.01 | — | — | 2912.64 (19.68x) | 1319.07 (8.91x) |
| Any EmptyStructKindValue WKT JSON parse | 499.84 | — | — | 5418.31 (10.84x) | 1963.05 (3.93x) |
| Any EmptyListKindValue WKT JSON stringify | 142.99 | — | — | 2898.23 (20.27x) | 1128.59 (7.89x) |
| Any EmptyListKindValue WKT JSON parse | 504.68 | — | — | 4383.31 (8.69x) | 1845.35 (3.66x) |
| Any DoubleValue WKT JSON stringify | 196.08 | — | — | 3463.59 (17.66x) | 813.12 (4.15x) |
| Any DoubleValue WKT JSON parse | 525.98 | — | — | 4765.39 (9.06x) | 1459.96 (2.78x) |
| Any DoubleValue String WKT JSON parse | 537.34 | — | — | 4679.16 (8.71x) | 1506.14 (2.80x) |
| Any DoubleValue Exponent WKT JSON parse | 531.19 | — | — | 3894.43 (7.33x) | 1446.88 (2.72x) |
| Any NegativeDoubleValue WKT JSON stringify | 199.29 | — | — | 3411.04 (17.12x) | 797.00 (4.00x) |
| Any NegativeDoubleValue WKT JSON parse | 526.81 | — | — | 3006.36 (5.71x) | 1453.07 (2.76x) |
| Any ZeroDoubleValue WKT JSON stringify | 171.30 | — | — | 921.26 (5.38x) | 739.40 (4.32x) |
| Any ZeroDoubleValue WKT JSON parse | 521.19 | — | — | 4054.89 (7.78x) | 1415.11 (2.72x) |
| Any DoubleValue NaN WKT JSON stringify | 159.27 | — | — | 4113.31 (25.83x) | 719.68 (4.52x) |
| Any DoubleValue NaN WKT JSON parse | 519.80 | — | — | 5164.91 (9.94x) | 1435.41 (2.76x) |
| Any DoubleValue Infinity WKT JSON stringify | 165.34 | — | — | 3723.25 (22.52x) | 718.05 (4.34x) |
| Any DoubleValue Infinity WKT JSON parse | 524.80 | — | — | 5445.57 (10.38x) | 1441.92 (2.75x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 168.30 | — | — | 3324.95 (19.76x) | 729.18 (4.33x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 526.94 | — | — | 4931.78 (9.36x) | 1459.86 (2.77x) |
| Any FloatValue WKT JSON stringify | 204.72 | — | — | 2360.92 (11.53x) | 791.85 (3.87x) |
| Any FloatValue WKT JSON parse | 526.45 | — | — | 5786.98 (10.99x) | 1418.37 (2.69x) |
| Any FloatValue String WKT JSON parse | 537.30 | — | — | 4420.58 (8.23x) | 1501.83 (2.80x) |
| Any FloatValue Exponent WKT JSON parse | 529.67 | — | — | 4880.73 (9.21x) | 1413.66 (2.67x) |
| Any NegativeFloatValue WKT JSON stringify | 384.96 | — | — | 3388.74 (8.80x) | 779.86 (2.03x) |
| Any NegativeFloatValue WKT JSON parse | 851.99 | — | — | 2824.58 (3.32x) | 1469.78 (1.73x) |
| Any ZeroFloatValue WKT JSON stringify | 300.25 | — | — | 925.75 (3.08x) | 731.68 (2.44x) |
| Any ZeroFloatValue WKT JSON parse | 824.56 | — | — | 2261.77 (2.74x) | 1403.06 (1.70x) |
| Any FloatValue NaN WKT JSON stringify | 251.55 | — | — | 1595.44 (6.34x) | 707.39 (2.81x) |
| Any FloatValue NaN WKT JSON parse | 818.13 | — | — | 2668.37 (3.26x) | 1431.87 (1.75x) |
| Any FloatValue Infinity WKT JSON stringify | 255.58 | — | — | 1675.22 (6.55x) | 718.31 (2.81x) |
| Any FloatValue Infinity WKT JSON parse | 827.09 | — | — | 2688.43 (3.25x) | 1420.33 (1.72x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 258.66 | — | — | 1552.41 (6.00x) | 728.72 (2.82x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 827.60 | — | — | 2663.75 (3.22x) | 1430.84 (1.73x) |
| Any Int64Value WKT JSON stringify | 297.87 | — | — | 1562.48 (5.25x) | 853.07 (2.86x) |
| Any Int64Value WKT JSON parse | 696.04 | — | — | 2802.61 (4.03x) | 1648.69 (2.37x) |
| Any Int64Value Number WKT JSON parse | 828.02 | — | — | 2748.07 (3.32x) | 1528.76 (1.85x) |
| Any Int64Value Exponent WKT JSON parse | 667.66 | — | — | 2703.87 (4.05x) | 1479.32 (2.22x) |
| Any ZeroInt64Value WKT JSON stringify | 157.58 | — | — | 917.24 (5.82x) | 971.59 (6.17x) |
| Any ZeroInt64Value WKT JSON parse | 526.49 | — | — | 2165.02 (4.11x) | 1474.01 (2.80x) |
| Any NegativeInt64Value WKT JSON stringify | 170.89 | — | — | 1564.15 (9.15x) | 852.46 (4.99x) |
| Any NegativeInt64Value WKT JSON parse | 552.94 | — | — | 2809.40 (5.08x) | 1667.51 (3.02x) |
| Any MinInt64Value WKT JSON stringify | 173.55 | — | — | 1580.17 (9.10x) | 855.35 (4.93x) |
| Any MinInt64Value WKT JSON parse | 560.21 | — | — | 2816.49 (5.03x) | 1701.49 (3.04x) |
| Any MaxInt64Value WKT JSON stringify | 186.05 | — | — | 1567.75 (8.43x) | 873.78 (4.70x) |
| Any MaxInt64Value WKT JSON parse | 564.42 | — | — | 2817.52 (4.99x) | 1669.33 (2.96x) |
| Any UInt64Value WKT JSON stringify | 178.99 | — | — | 1556.43 (8.70x) | 853.80 (4.77x) |
| Any UInt64Value WKT JSON parse | 561.41 | — | — | 2794.71 (4.98x) | 1615.77 (2.88x) |
| Any UInt64Value Number WKT JSON parse | 561.23 | — | — | 2765.25 (4.93x) | 1526.40 (2.72x) |
| Any UInt64Value Exponent WKT JSON parse | 548.53 | — | — | 2701.89 (4.93x) | 1501.59 (2.74x) |
| Any ZeroUInt64Value WKT JSON stringify | 174.56 | — | — | 917.62 (5.26x) | 792.48 (4.54x) |
| Any ZeroUInt64Value WKT JSON parse | 531.76 | — | — | 2159.86 (4.06x) | 1479.56 (2.78x) |
| Any MaxUInt64Value WKT JSON stringify | 182.31 | — | — | 1557.98 (8.55x) | 864.95 (4.74x) |
| Any MaxUInt64Value WKT JSON parse | 567.54 | — | — | 2827.13 (4.98x) | 1675.20 (2.95x) |
| Any Int32Value WKT JSON stringify | 177.84 | — | — | 1548.48 (8.71x) | 737.66 (4.15x) |
| Any Int32Value WKT JSON parse | 539.45 | — | — | 2670.00 (4.95x) | 1482.82 (2.75x) |
| Any Int32Value String WKT JSON parse | 544.57 | — | — | 2673.71 (4.91x) | 1531.22 (2.81x) |
| Any Int32Value Exponent WKT JSON parse | 544.58 | — | — | 2699.35 (4.96x) | 1492.57 (2.74x) |
| Any ZeroInt32Value WKT JSON stringify | 169.84 | — | — | 917.04 (5.40x) | 710.66 (4.18x) |
| Any ZeroInt32Value WKT JSON parse | 532.67 | — | — | 2147.08 (4.03x) | 1397.88 (2.62x) |
| Any NegativeInt32Value WKT JSON stringify | 171.27 | — | — | 1552.54 (9.06x) | 734.50 (4.29x) |
| Any NegativeInt32Value WKT JSON parse | 541.78 | — | — | 2697.55 (4.98x) | 1481.58 (2.73x) |
| Any MinInt32Value WKT JSON stringify | 176.55 | — | — | 1551.77 (8.79x) | 739.50 (4.19x) |
| Any MinInt32Value WKT JSON parse | 546.76 | — | — | 2706.72 (4.95x) | 1529.20 (2.80x) |
| Any MaxInt32Value WKT JSON stringify | 174.23 | — | — | 1548.14 (8.89x) | 744.57 (4.27x) |
| Any MaxInt32Value WKT JSON parse | 546.57 | — | — | 2680.32 (4.90x) | 1468.50 (2.69x) |
| Any UInt32Value WKT JSON stringify | 185.25 | — | — | 1550.89 (8.37x) | 759.39 (4.10x) |
| Any UInt32Value WKT JSON parse | 545.90 | — | — | 2677.04 (4.90x) | 1462.67 (2.68x) |
| Any UInt32Value String WKT JSON parse | 549.46 | — | — | 2664.32 (4.85x) | 1542.57 (2.81x) |
| Any UInt32Value Exponent WKT JSON parse | 552.73 | — | — | 2698.79 (4.88x) | 1521.78 (2.75x) |
| Any ZeroUInt32Value WKT JSON stringify | 181.48 | — | — | 914.29 (5.04x) | 717.69 (3.95x) |
| Any ZeroUInt32Value WKT JSON parse | 538.82 | — | — | 2150.11 (3.99x) | 1421.73 (2.64x) |
| Any MaxUInt32Value WKT JSON stringify | 184.15 | — | — | 1563.79 (8.49x) | 746.02 (4.05x) |
| Any MaxUInt32Value WKT JSON parse | 553.30 | — | — | 2692.31 (4.87x) | 1477.18 (2.67x) |
| Any BoolValue WKT JSON stringify | 171.30 | — | — | 1518.89 (8.87x) | 723.71 (4.22x) |
| Any BoolValue WKT JSON parse | 493.66 | — | — | 2597.22 (5.26x) | 1339.81 (2.71x) |
| Any FalseBoolValue WKT JSON stringify | 173.55 | — | — | 913.29 (5.26x) | 707.44 (4.08x) |
| Any FalseBoolValue WKT JSON parse | 494.16 | — | — | 2150.33 (4.35x) | 1348.78 (2.73x) |
| Any StringValue WKT JSON stringify | 203.21 | — | — | 1559.13 (7.67x) | 795.84 (3.92x) |
| Any StringValue WKT JSON parse | 554.59 | — | — | 2656.47 (4.79x) | 1451.79 (2.62x) |
| Any StringValue Escape WKT JSON parse | 559.43 | — | — | 2691.94 (4.81x) | 1550.59 (2.77x) |
| Any StringValue Surrogate WKT JSON parse | 562.27 | — | — | 2680.89 (4.77x) | 1545.46 (2.75x) |
| Any EmptyStringValue WKT JSON stringify | 188.63 | — | — | 914.65 (4.85x) | 760.74 (4.03x) |
| Any EmptyStringValue WKT JSON parse | 521.51 | — | — | 2158.42 (4.14x) | 1395.31 (2.68x) |
| Any BytesValue WKT JSON stringify | 201.51 | — | — | 1573.34 (7.81x) | 833.17 (4.13x) |
| Any BytesValue WKT JSON parse | 564.00 | — | — | 2683.09 (4.76x) | 1473.61 (2.61x) |
| Any BytesValue URL WKT JSON parse | 583.77 | — | — | 2667.13 (4.57x) | 1499.96 (2.57x) |
| Any BytesValue StandardBase64 WKT JSON parse | 568.14 | — | — | 2690.74 (4.74x) | 1497.93 (2.64x) |
| Any BytesValue Unpadded WKT JSON parse | 568.35 | — | — | 2670.38 (4.70x) | 1504.38 (2.65x) |
| Any EmptyBytesValue WKT JSON stringify | 187.78 | — | — | 914.42 (4.87x) | 767.49 (4.09x) |
| Any EmptyBytesValue WKT JSON parse | 528.37 | — | — | 2150.14 (4.07x) | 1457.74 (2.76x) |
| Nested Any WKT JSON stringify | 313.03 | — | — | 2469.24 (7.89x) | 1466.64 (4.69x) |
| Nested Any WKT JSON parse | 870.51 | — | — | 4264.25 (4.90x) | 2903.29 (3.34x) |
| Duration JSON stringify | 57.22 | — | — | 957.03 (16.73x) | 368.04 (6.43x) |
| Duration JSON parse | 21.62 | — | — | 1443.49 (66.77x) | 391.41 (18.10x) |
| Duration Escape JSON parse | 43.78 | — | — | 1476.71 (33.73x) | 441.46 (10.08x) |
| PlusDuration JSON parse | 21.25 | — | — | 1468.80 (69.12x) | 400.81 (18.86x) |
| ShortFractionDuration JSON parse | 18.56 | — | — | 1414.45 (76.21x) | 385.57 (20.77x) |
| MicroDuration JSON stringify | 59.88 | — | — | 965.30 (16.12x) | 399.47 (6.67x) |
| MicroDuration JSON parse | 22.45 | — | — | 1461.95 (65.12x) | 387.65 (17.27x) |
| NanoDuration JSON stringify | 57.37 | — | — | 991.19 (17.28x) | 410.96 (7.16x) |
| NanoDuration JSON parse | 27.17 | — | — | 1470.63 (54.13x) | 402.73 (14.82x) |
| NegativeDuration JSON stringify | 58.31 | — | — | 1001.18 (17.17x) | 426.24 (7.31x) |
| NegativeDuration JSON parse | 20.71 | — | — | 1501.39 (72.50x) | 392.77 (18.97x) |
| FractionalNegativeDuration JSON stringify | 58.35 | — | — | 965.77 (16.55x) | 425.03 (7.28x) |
| FractionalNegativeDuration JSON parse | 21.68 | — | — | 1450.11 (66.89x) | 374.99 (17.30x) |
| MaxDuration JSON stringify | 49.63 | — | — | 850.91 (17.15x) | 420.16 (8.47x) |
| MaxDuration JSON parse | 37.22 | — | — | 1426.08 (38.31x) | 688.73 (18.50x) |
| MinDuration JSON stringify | 49.93 | — | — | 864.98 (17.32x) | 454.55 (9.10x) |
| MinDuration JSON parse | 43.35 | — | — | 1439.25 (33.20x) | 401.99 (9.27x) |
| ZeroDuration JSON stringify | 44.87 | — | — | 810.73 (18.07x) | 342.87 (7.64x) |
| ZeroDuration JSON parse | 14.81 | — | — | 1362.92 (92.03x) | 319.43 (21.57x) |
| FieldMask JSON stringify | 67.31 | — | — | 881.97 (13.10x) | 646.60 (9.61x) |
| FieldMask JSON parse | 140.45 | — | — | 1645.48 (11.72x) | 885.58 (6.31x) |
| FieldMask Escape JSON parse | 188.55 | — | — | 1708.21 (9.06x) | 980.52 (5.20x) |
| EmptyFieldMask JSON stringify | 40.60 | — | — | 610.22 (15.03x) | 193.35 (4.76x) |
| EmptyFieldMask JSON parse | 4.79 | — | — | 947.48 (197.80x) | 160.86 (33.58x) |
| Timestamp JSON stringify | 95.32 | — | — | 1144.52 (12.01x) | 412.98 (4.33x) |
| Timestamp JSON parse | 45.37 | — | — | 1481.43 (32.65x) | 442.37 (9.75x) |
| Timestamp Escape JSON parse | 91.50 | — | — | 1516.39 (16.57x) | 505.30 (5.52x) |
| ShortFraction Timestamp JSON parse | 43.49 | — | — | 1472.47 (33.86x) | 438.59 (10.08x) |
| Micro Timestamp JSON stringify | 95.50 | — | — | 1139.70 (11.93x) | 412.82 (4.32x) |
| Micro Timestamp JSON parse | 47.36 | — | — | 1496.70 (31.60x) | 458.40 (9.68x) |
| Nano Timestamp JSON stringify | 94.50 | — | — | 1177.35 (12.46x) | 422.57 (4.47x) |
| Nano Timestamp JSON parse | 49.87 | — | — | 1510.64 (30.29x) | 465.03 (9.32x) |
| Offset Timestamp JSON parse | 51.25 | — | — | 1523.45 (29.73x) | 481.15 (9.39x) |
| PreEpoch Timestamp JSON stringify | 66.07 | — | — | 1059.90 (16.04x) | 396.85 (6.01x) |
| PreEpoch Timestamp JSON parse | 43.11 | — | — | 1452.85 (33.70x) | 589.55 (13.68x) |
| Max Timestamp JSON stringify | 78.52 | — | — | 1191.55 (15.18x) | 424.59 (5.41x) |
| Max Timestamp JSON parse | 54.33 | — | — | 1532.32 (28.20x) | 468.87 (8.63x) |
| Min Timestamp JSON stringify | 79.77 | — | — | 1061.02 (13.30x) | 398.36 (4.99x) |
| Min Timestamp JSON parse | 41.07 | — | — | 1448.56 (35.27x) | 423.55 (10.31x) |
| Empty JSON stringify | 20.57 | — | — | 494.71 (24.05x) | 80.48 (3.91x) |
| Empty JSON parse | 67.71 | — | — | 721.70 (10.66x) | 205.74 (3.04x) |
| Struct JSON stringify | 176.51 | — | — | 5748.18 (32.57x) | 3070.93 (17.40x) |
| Struct JSON parse | 838.97 | — | — | 10839.80 (12.92x) | 4673.87 (5.57x) |
| Struct Escape JSON parse | 880.35 | — | — | 10959.30 (12.45x) | 4769.83 (5.42x) |
| Struct NumberExponent JSON parse | 837.96 | — | — | 10869.60 (12.97x) | 4671.92 (5.58x) |
| Struct Surrogate JSON parse | 369.93 | — | — | 4802.11 (12.98x) | 1196.53 (3.23x) |
| Struct KeySurrogate JSON parse | 369.66 | — | — | 4774.56 (12.92x) | 1200.08 (3.25x) |
| EmptyStruct JSON stringify | 41.10 | — | — | 696.00 (16.93x) | 349.42 (8.50x) |
| EmptyStruct JSON parse | 86.62 | — | — | 2062.85 (23.81x) | 377.25 (4.36x) |
| Value JSON stringify | 176.32 | — | — | 6564.82 (37.23x) | 3197.97 (18.14x) |
| Value JSON parse | 862.77 | — | — | 12158.40 (14.09x) | 4917.97 (5.70x) |
| Value Escape JSON parse | 906.76 | — | — | 12256.90 (13.52x) | 5206.37 (5.74x) |
| Value NumberExponent JSON parse | 858.26 | — | — | 12190.20 (14.20x) | 4915.80 (5.73x) |
| Value Surrogate JSON parse | 393.22 | — | — | 6628.11 (16.86x) | 1471.87 (3.74x) |
| Value KeySurrogate JSON parse | 395.61 | — | — | 6611.36 (16.71x) | 1490.07 (3.77x) |
| NullValue JSON stringify | 40.42 | — | — | 1309.62 (32.40x) | 221.85 (5.49x) |
| NullValue JSON parse | 69.72 | — | — | 2467.19 (35.39x) | 357.21 (5.12x) |
| StringScalarValue JSON stringify | 47.61 | — | — | 1336.79 (28.08x) | 270.01 (5.67x) |
| StringScalarValue JSON parse | 140.19 | — | — | 2074.53 (14.80x) | 440.62 (3.14x) |
| StringScalarValue Escape JSON parse | 149.55 | — | — | 2102.66 (14.06x) | 496.44 (3.32x) |
| StringScalarValue Surrogate JSON parse | 148.42 | — | — | 2112.76 (14.24x) | 495.04 (3.34x) |
| EmptyStringScalarValue JSON stringify | 45.79 | — | — | 1331.14 (29.07x) | 267.71 (5.85x) |
| EmptyStringScalarValue JSON parse | 87.20 | — | — | 2052.86 (23.54x) | 358.44 (4.11x) |
| NumberValue JSON stringify | 74.44 | — | — | 1553.87 (20.87x) | 339.19 (4.56x) |
| NumberValue JSON parse | 131.71 | — | — | 2159.53 (16.40x) | 657.19 (4.99x) |
| NumberValue Exponent JSON parse | 134.13 | — | — | 2168.50 (16.17x) | 427.70 (3.19x) |
| NegativeNumberValue JSON stringify | 73.25 | — | — | 1550.91 (21.17x) | 325.27 (4.44x) |
| NegativeNumberValue JSON parse | 132.40 | — | — | 2163.55 (16.34x) | 407.41 (3.08x) |
| ZeroNumberValue JSON stringify | 50.66 | — | — | 1506.52 (29.74x) | 274.88 (5.43x) |
| ZeroNumberValue JSON parse | 129.57 | — | — | 2093.10 (16.15x) | 377.93 (2.92x) |
| BoolScalarValue JSON stringify | 40.42 | — | — | 1306.23 (32.32x) | 218.80 (5.41x) |
| BoolScalarValue JSON parse | 69.71 | — | — | 2023.09 (29.02x) | 329.86 (4.73x) |
| FalseBoolScalarValue JSON stringify | 40.49 | — | — | 1309.09 (32.33x) | 223.03 (5.51x) |
| FalseBoolScalarValue JSON parse | 70.26 | — | — | 2019.21 (28.74x) | 327.56 (4.66x) |
| ListKindValue JSON stringify | 144.06 | — | — | 6113.58 (42.44x) | 2264.58 (15.72x) |
| ListKindValue JSON parse | 665.60 | — | — | 10399.40 (15.62x) | 4061.32 (6.10x) |
| ListKindValue Escape JSON parse | 689.40 | — | — | 10490.50 (15.22x) | 4282.65 (6.21x) |
| ListKindValue Surrogate JSON parse | 321.51 | — | — | 4899.00 (15.24x) | 1195.71 (3.72x) |
| EmptyStructKindValue JSON stringify | 42.97 | — | — | 1921.59 (44.72x) | 526.26 (12.25x) |
| EmptyStructKindValue JSON parse | 110.25 | — | — | 3765.03 (34.15x) | 663.77 (6.02x) |
| EmptyListKindValue JSON stringify | 41.12 | — | — | 1923.28 (46.77x) | 362.53 (8.82x) |
| EmptyListKindValue JSON parse | 148.99 | — | — | 4018.65 (26.97x) | 600.13 (4.03x) |
| ListValue JSON stringify | 149.92 | — | — | 4758.35 (31.74x) | 2117.84 (14.13x) |
| ListValue JSON parse | 652.94 | — | — | 8541.24 (13.08x) | 3845.46 (5.89x) |
| ListValue Escape JSON parse | 675.67 | — | — | 8615.84 (12.75x) | 3988.33 (5.90x) |
| ListValue Surrogate JSON parse | 298.80 | — | — | 3157.84 (10.57x) | 918.52 (3.07x) |
| EmptyListValue JSON stringify | 40.08 | — | — | 701.04 (17.49x) | 344.73 (8.60x) |
| EmptyListValue JSON parse | 126.33 | — | — | 2239.64 (17.73x) | 521.30 (4.13x) |
| DoubleValue JSON stringify | 68.48 | — | — | 868.52 (12.68x) | 188.63 (2.75x) |
| DoubleValue JSON parse | 110.80 | — | — | 1514.84 (13.67x) | 291.26 (2.63x) |
| DoubleValue String JSON parse | 111.74 | — | — | 2002.32 (17.92x) | 362.74 (3.25x) |
| DoubleValue Exponent JSON parse | 113.57 | — | — | 2072.96 (18.25x) | 287.26 (2.53x) |
| NegativeDoubleValue JSON stringify | 67.77 | — | — | 1664.50 (24.56x) | 185.08 (2.73x) |
| NegativeDoubleValue JSON parse | 111.53 | — | — | 2333.82 (20.93x) | 277.01 (2.48x) |
| ZeroDoubleValue JSON stringify | 47.19 | — | — | 822.19 (17.42x) | 233.54 (4.95x) |
| ZeroDoubleValue JSON parse | 108.09 | — | — | 1176.25 (10.88x) | 275.13 (2.55x) |
| DoubleValue NaN JSON stringify | 46.43 | — | — | 1338.30 (28.82x) | 131.99 (2.84x) |
| DoubleValue NaN JSON parse | 105.45 | — | — | 2144.95 (20.34x) | 273.38 (2.59x) |
| DoubleValue Infinity JSON stringify | 47.87 | — | — | 1948.52 (40.70x) | 124.59 (2.60x) |
| DoubleValue Infinity JSON parse | 105.61 | — | — | 2678.95 (25.37x) | 286.61 (2.71x) |
| DoubleValue NegativeInfinity JSON stringify | 48.77 | — | — | 1274.79 (26.14x) | 124.67 (2.56x) |
| DoubleValue NegativeInfinity JSON parse | 107.95 | — | — | 2161.52 (20.02x) | 282.21 (2.61x) |
| FloatValue JSON stringify | 71.16 | — | — | 1497.41 (21.04x) | 181.56 (2.55x) |
| FloatValue JSON parse | 110.10 | — | — | 2038.69 (18.52x) | 293.59 (2.67x) |
| FloatValue String JSON parse | 110.64 | — | — | 1601.78 (14.48x) | 365.93 (3.31x) |
| FloatValue Exponent JSON parse | 112.20 | — | — | 1693.54 (15.09x) | 290.81 (2.59x) |
| NegativeFloatValue JSON stringify | 71.76 | — | — | 1671.69 (23.30x) | 176.85 (2.46x) |
| NegativeFloatValue JSON parse | 110.42 | — | — | 2040.83 (18.48x) | 282.02 (2.55x) |
| ZeroFloatValue JSON stringify | 47.33 | — | — | 752.51 (15.90x) | 134.65 (2.84x) |
| ZeroFloatValue JSON parse | 107.74 | — | — | 1193.75 (11.08x) | 261.08 (2.42x) |
| FloatValue NaN JSON stringify | 46.39 | — | — | 647.92 (13.97x) | 127.01 (2.74x) |
| FloatValue NaN JSON parse | 105.16 | — | — | 1098.33 (10.44x) | 272.52 (2.59x) |
| FloatValue Infinity JSON stringify | 47.96 | — | — | 641.17 (13.37x) | 125.01 (2.61x) |
| FloatValue Infinity JSON parse | 106.45 | — | — | 1111.72 (10.44x) | 271.39 (2.55x) |
| FloatValue NegativeInfinity JSON stringify | 48.14 | — | — | 642.70 (13.35x) | 116.26 (2.42x) |
| FloatValue NegativeInfinity JSON parse | 108.52 | — | — | 1106.37 (10.20x) | 278.81 (2.57x) |
| Int64Value JSON stringify | 50.30 | — | — | 679.24 (13.50x) | 278.67 (5.54x) |
| Int64Value JSON parse | 125.24 | — | — | 1222.33 (9.76x) | 471.74 (3.77x) |
| Int64Value Number JSON parse | 128.07 | — | — | 1286.97 (10.05x) | 353.70 (2.76x) |
| Int64Value Exponent JSON parse | 117.48 | — | — | 1221.22 (10.40x) | 363.92 (3.10x) |
| ZeroInt64Value JSON stringify | 41.47 | — | — | 617.99 (14.90x) | 205.64 (4.96x) |
| ZeroInt64Value JSON parse | 106.97 | — | — | 1106.76 (10.35x) | 346.17 (3.24x) |
| NegativeInt64Value JSON stringify | 49.95 | — | — | 679.88 (13.61x) | 281.66 (5.64x) |
| NegativeInt64Value JSON parse | 126.54 | — | — | 1224.16 (9.67x) | 482.50 (3.81x) |
| MinInt64Value JSON stringify | 50.05 | — | — | 679.87 (13.58x) | 285.85 (5.71x) |
| MinInt64Value JSON parse | 134.01 | — | — | 1240.35 (9.26x) | 492.93 (3.68x) |
| MaxInt64Value JSON stringify | 48.95 | — | — | 684.40 (13.98x) | 279.77 (5.72x) |
| MaxInt64Value JSON parse | 132.76 | — | — | 1247.70 (9.40x) | 482.31 (3.63x) |
| UInt64Value JSON stringify | 49.80 | — | — | 691.04 (13.88x) | 281.92 (5.66x) |
| UInt64Value JSON parse | 126.78 | — | — | 1251.58 (9.87x) | 466.85 (3.68x) |
| UInt64Value Number JSON parse | 128.80 | — | — | 1279.69 (9.94x) | 342.91 (2.66x) |
| UInt64Value Exponent JSON parse | 118.38 | — | — | 1229.19 (10.38x) | 354.66 (3.00x) |
| ZeroUInt64Value JSON stringify | 41.16 | — | — | 624.66 (15.18x) | 358.27 (8.70x) |
| ZeroUInt64Value JSON parse | 107.17 | — | — | 1127.22 (10.52x) | 340.33 (3.18x) |
| MaxUInt64Value JSON stringify | 49.50 | — | — | 688.91 (13.92x) | 284.49 (5.75x) |
| MaxUInt64Value JSON parse | 139.21 | — | — | 1282.03 (9.21x) | 480.23 (3.45x) |
| Int32Value JSON stringify | 46.84 | — | — | 630.26 (13.46x) | 134.07 (2.86x) |
| Int32Value JSON parse | 131.78 | — | — | 1180.85 (8.96x) | 317.83 (2.41x) |
| Int32Value String JSON parse | 135.01 | — | — | 1131.21 (8.38x) | 385.96 (2.86x) |
| Int32Value Exponent JSON parse | 134.89 | — | — | 1222.32 (9.06x) | 363.02 (2.69x) |
| ZeroInt32Value JSON stringify | 46.70 | — | — | 612.56 (13.12x) | 122.52 (2.62x) |
| ZeroInt32Value JSON parse | 127.06 | — | — | 1147.11 (9.03x) | 267.27 (2.10x) |
| NegativeInt32Value JSON stringify | 46.78 | — | — | 639.75 (13.68x) | 132.21 (2.83x) |
| NegativeInt32Value JSON parse | 130.91 | — | — | 1184.86 (9.05x) | 327.15 (2.50x) |
| MinInt32Value JSON stringify | 47.30 | — | — | 641.98 (13.57x) | 137.76 (2.91x) |
| MinInt32Value JSON parse | 137.31 | — | — | 1215.40 (8.85x) | 345.99 (2.52x) |
| MaxInt32Value JSON stringify | 47.27 | — | — | 630.58 (13.34x) | 139.75 (2.96x) |
| MaxInt32Value JSON parse | 137.18 | — | — | 1211.27 (8.83x) | 337.68 (2.46x) |
| UInt32Value JSON stringify | 46.66 | — | — | 641.84 (13.76x) | 141.25 (3.03x) |
| UInt32Value JSON parse | 132.03 | — | — | 1181.96 (8.95x) | 321.40 (2.43x) |
| UInt32Value String JSON parse | 135.67 | — | — | 1191.72 (8.78x) | 388.74 (2.87x) |
| UInt32Value Exponent JSON parse | 134.97 | — | — | 1294.74 (9.59x) | 365.79 (2.71x) |
| ZeroUInt32Value JSON stringify | 46.70 | — | — | 628.75 (13.46x) | 128.04 (2.74x) |
| ZeroUInt32Value JSON parse | 127.60 | — | — | 1144.81 (8.97x) | 273.50 (2.14x) |
| MaxUInt32Value JSON stringify | 46.95 | — | — | 649.32 (13.83x) | 143.99 (3.07x) |
| MaxUInt32Value JSON parse | 137.44 | — | — | 1200.77 (8.74x) | 338.39 (2.46x) |
| BoolValue JSON stringify | 45.26 | — | — | 623.07 (13.77x) | 127.54 (2.82x) |
| BoolValue JSON parse | 60.06 | — | — | 1059.15 (17.63x) | 222.89 (3.71x) |
| FalseBoolValue JSON stringify | 45.18 | — | — | 615.76 (13.63x) | 223.80 (4.95x) |
| FalseBoolValue JSON parse | 60.63 | — | — | 1086.98 (17.93x) | 383.69 (6.33x) |
| StringValue JSON stringify | 52.12 | — | — | 670.99 (12.87x) | 186.35 (3.58x) |
| StringValue JSON parse | 119.60 | — | — | 1146.00 (9.58x) | 322.67 (2.70x) |
| StringValue Escape JSON parse | 129.56 | — | — | 1172.97 (9.05x) | 373.12 (2.88x) |
| StringValue Surrogate JSON parse | 127.45 | — | — | 1170.73 (9.19x) | 379.01 (2.97x) |
| EmptyStringValue JSON stringify | 48.92 | — | — | 635.50 (12.99x) | 186.72 (3.82x) |
| EmptyStringValue JSON parse | 65.97 | — | — | 1110.32 (16.83x) | 229.52 (3.48x) |
| BytesValue JSON stringify | 48.96 | — | — | 670.21 (13.69x) | 379.10 (7.74x) |
| BytesValue JSON parse | 126.26 | — | — | 1172.20 (9.28x) | 435.99 (3.45x) |
| BytesValue URL JSON parse | 141.80 | — | — | 1162.46 (8.20x) | 339.03 (2.39x) |
| BytesValue StandardBase64 JSON parse | 124.71 | — | — | 1180.88 (9.47x) | 339.89 (2.73x) |
| BytesValue Unpadded JSON parse | 124.20 | — | — | 1163.05 (9.36x) | 332.15 (2.67x) |
| EmptyBytesValue JSON stringify | 40.67 | — | — | 653.48 (16.07x) | 194.66 (4.79x) |
| EmptyBytesValue JSON parse | 68.77 | — | — | 1136.62 (16.53x) | 288.20 (4.19x) |
| TextFormat format | 178.58 | — | — | 2609.84 (14.61x) | 2598.22 (14.55x) |
| TextFormat parse | 664.08 | — | — | 5010.89 (7.55x) | 6563.46 (9.88x) |
| packed fixed32 encode | 2.00 | 554.20 (277.10x) | 542.13 (271.06x) | 43.47 (21.74x) | 405.36 (202.68x) |
| packed fixed32 decode | 4.54 | 1047.55 (230.74x) | 1951.31 (429.80x) | 49.67 (10.94x) | 1547.95 (340.96x) |
| packed fixed64 encode | 2.00 | 577.01 (288.50x) | 610.67 (305.33x) | 75.76 (37.88x) | 391.11 (195.56x) |
| packed fixed64 decode | 4.54 | 1040.27 (229.13x) | 7937.82 (1748.42x) | 80.22 (17.67x) | 2176.56 (479.42x) |
| packed sfixed32 encode | 2.01 | 550.94 (274.10x) | 539.32 (268.32x) | 43.69 (21.74x) | 415.02 (206.48x) |
| packed sfixed32 decode | 4.54 | 1059.95 (233.47x) | 1969.09 (433.72x) | 48.87 (10.76x) | 1543.68 (340.02x) |
| packed sfixed64 encode | 2.01 | 570.54 (283.85x) | 562.32 (279.76x) | 75.65 (37.64x) | 393.46 (195.75x) |
| packed sfixed64 decode | 4.53 | 1006.08 (222.09x) | 7903.68 (1744.74x) | 79.39 (17.53x) | 2182.17 (481.72x) |
| packed float encode | 2.01 | 813.16 (404.56x) | 539.70 (268.51x) | 43.50 (21.64x) | 366.65 (182.41x) |
| packed float decode | 4.52 | 1052.39 (232.83x) | 2053.68 (454.35x) | 48.83 (10.80x) | 1552.82 (343.54x) |
| packed double encode | 2.01 | 829.36 (412.62x) | 561.30 (279.25x) | 75.81 (37.72x) | 355.96 (177.09x) |
| packed double decode | 4.51 | 964.12 (213.77x) | 2068.64 (458.68x) | 79.61 (17.65x) | 2174.82 (482.22x) |
| packed uint64 encode | 1293.39 | 4608.17 (3.56x) | 4179.59 (3.23x) | 2121.90 (1.64x) | 3453.37 (2.67x) |
| packed uint64 decode | 1780.72 | 2783.38 (1.56x) | 8854.56 (4.97x) | 2810.58 (1.58x) | 6249.02 (3.51x) |
| packed uint32 encode | 1576.78 | 3612.63 (2.29x) | 3518.47 (2.23x) | 1746.19 (1.11x) | 2880.85 (1.83x) |
| packed uint32 decode | 1307.17 | 2434.35 (1.86x) | 3269.84 (2.50x) | 1988.69 (1.52x) | 4716.91 (3.61x) |
| packed int64 encode | 1374.55 | 11024.06 (8.02x) | 6080.63 (4.42x) | 2904.81 (2.11x) | 4110.59 (2.99x) |
| packed int64 decode | 2743.43 | 3359.71 (1.22x) | 10296.07 (3.75x) | 4779.56 (1.74x) | 7771.41 (2.83x) |
| packed sint32 encode | 781.37 | 3042.69 (3.89x) | 2865.06 (3.67x) | 1527.22 (1.95x) | 3394.12 (4.34x) |
| packed sint32 decode | 940.74 | 2543.20 (2.70x) | 3156.52 (3.36x) | 1127.31 (1.20x) | 3025.85 (3.22x) |
| packed sint64 encode | 1423.91 | 4937.92 (3.47x) | 4424.82 (3.11x) | 2397.25 (1.68x) | 4151.68 (2.92x) |
| packed sint64 decode | 2031.39 | 3063.64 (1.51x) | 9663.24 (4.76x) | 2944.08 (1.45x) | 6736.82 (3.32x) |
| packed bool encode | 2.01 | 1318.97 (656.20x) | 518.92 (258.17x) | 15.92 (7.92x) | 2412.74 (1200.37x) |
| packed bool decode | 262.94 | 1532.75 (5.83x) | 2548.84 (9.69x) | 804.01 (3.06x) | 1625.95 (6.18x) |
| packed enum encode | 270.58 | 2743.30 (10.14x) | 1813.92 (6.70x) | 1084.56 (4.01x) | 2601.18 (9.61x) |
| packed enum decode | 157.72 | 1528.76 (9.69x) | 2922.91 (18.53x) | 693.60 (4.40x) | 2008.19 (12.73x) |
| large map encode | 4068.36 | 16598.19 (4.08x) | 9650.99 (2.37x) | 21761.50 (5.35x) | 209953.00 (51.61x) |
| shuffled large map deterministic binary encode | 27772.07 | — | — | 93428.30 (3.36x) | 442221.62 (15.92x) |
| large map decode | 23931.12 | 90548.42 (3.78x) | 89634.16 (3.75x) | 92293.10 (3.86x) | 279455.22 (11.68x) |
The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON (including generated `map<string, int32>` surrogate-pair key parse), Any/WKT JSON (including embedded zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound `Duration`, non-empty/escaped-input parse/number-exponent parse/surrogate-pair value parse/surrogate-pair key parse and empty `Struct`, object/escaped-object parse/object-number-exponent/object-surrogate-pair value parse/object-surrogate-pair key parse/list/escaped-list/surrogate-list/string-scalar/escaped-string-scalar/surrogate-string-scalar/number-exponent/negative-number `Value` (including default-like scalar and empty object/list kinds),
`FieldMask` (non-empty, escaped JSON parse input, and empty), escaped-input parse/short-fraction parse/micro/nano/offset/min/pre/post/max-bound `Timestamp`, `Empty`, min/zero/positive/number-input parse/numeric-exponent parse/negative/max `Int64Value`, negative/zero/positive finite/string-input parse/numeric-exponent parse `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), negative/zero/positive finite/string-input parse/numeric-exponent parse `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), zero/normal/number-input parse/numeric-exponent parse/max `UInt64Value`, min/zero/positive/string-input parse/numeric-exponent parse/negative/max `Int32Value`, zero/normal/string-input parse/numeric-exponent parse/max `UInt32Value`, true/false `BoolValue`, non-empty/escape-input parse/surrogate-pair parse/empty `StringValue`, padded-standard/base64url/unpadded-base64 parse/empty `BytesValue`, and recursive nested `Any` payloads), direct zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound Duration, non-empty/escaped-input parse/empty FieldMask, and escaped-input parse/short-fraction parse/micro/nano/offset/min/pre/post/max-bound Timestamp WKT JSON plus other direct WKT JSON, including non-empty/escaped-input parse/number-exponent parse/surrogate-pair value parse/surrogate-pair key parse/empty `Struct`, object/escaped-object parse/object-number-exponent/object-surrogate-pair value parse/object-surrogate-pair key parse/list/escaped-list/surrogate-list/string-scalar/escaped-string-scalar/surrogate-string-scalar/number-exponent/negative-number `Value`, and escaped/surrogate-pair/non-empty/empty `ListValue`, TextFormat, packed scalars, large bytes,
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
