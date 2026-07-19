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

Latest accepted comparison (`/tmp/pbz-compare-list-escape-json-final.log`,
summarized in `/tmp/pbz-summary-list-escape-json-final.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 17.15 | 108.10 (6.30x) | 53.58 (3.12x) | 105.24 (6.14x) | 809.39 (47.19x) |
| binary decode | 95.06 | 256.14 (2.69x) | 228.44 (2.40x) | 229.50 (2.41x) | 891.30 (9.38x) |
| unknown fields count by number | 3.58 | — | — | 165.81 (46.32x) | — |
| deterministic binary encode | 48.54 | — | — | 131.24 (2.70x) | 1070.36 (22.05x) |
| scalarmix encode | 18.79 | 92.57 (4.93x) | 47.27 (2.52x) | 31.22 (1.66x) | 243.27 (12.95x) |
| scalarmix decode | 39.09 | 137.99 (3.53x) | 171.27 (4.38x) | 84.96 (2.17x) | 288.57 (7.38x) |
| textbytes encode | 9.52 | 80.56 (8.46x) | 33.34 (3.50x) | 121.61 (12.77x) | 156.35 (16.42x) |
| textbytes decode | 44.74 | 379.52 (8.48x) | 239.43 (5.35x) | 165.22 (3.69x) | 686.02 (15.33x) |
| largebytes encode | 25.81 | 2705.91 (104.84x) | 2674.22 (103.61x) | 4887.66 (189.37x) | 2791.67 (108.16x) |
| largebytes decode | 93.61 | 5602.18 (59.85x) | 3056.36 (32.65x) | 4846.05 (51.77x) | 26588.63 (284.04x) |
| presencemix encode | 16.77 | 57.71 (3.44x) | 30.22 (1.80x) | 73.57 (4.39x) | 241.57 (14.40x) |
| presencemix decode | 55.70 | 132.64 (2.38x) | 109.55 (1.97x) | 214.60 (3.85x) | 492.82 (8.85x) |
| complex encode | 51.41 | 136.59 (2.66x) | 95.12 (1.85x) | 223.78 (4.35x) | 1088.29 (21.17x) |
| complex decode | 170.48 | 395.26 (2.32x) | 345.57 (2.03x) | 520.19 (3.05x) | 1407.43 (8.26x) |
| complex deterministic binary encode | 90.62 | — | — | 227.51 (2.51x) | 1233.69 (13.61x) |
| complex JSON stringify | 262.43 | — | — | 5631.22 (21.46x) | 6056.39 (23.08x) |
| complex JSON parse | 2377.94 | — | — | 12277.60 (5.16x) | 7185.20 (3.02x) |
| complex TextFormat format | 244.23 | — | — | 3756.65 (15.38x) | 5530.83 (22.65x) |
| complex TextFormat parse | 1778.70 | — | — | 6967.31 (3.92x) | 8552.15 (4.81x) |
| packed int32 encode | 900.04 | 3161.17 (3.51x) | 2660.66 (2.96x) | 1247.42 (1.39x) | 2736.51 (3.04x) |
| packed int32 decode | 775.12 | 1903.22 (2.46x) | 3209.22 (4.14x) | 1003.83 (1.30x) | 3588.17 (4.63x) |
| JSON stringify | 152.30 | — | — | 3000.01 (19.70x) | 2111.74 (13.87x) |
| JSON parse | 1548.38 | — | — | 7458.60 (4.82x) | 4344.75 (2.81x) |
| Any WKT JSON stringify | 129.66 | — | — | 1885.50 (14.54x) | 1444.55 (11.14x) |
| Any WKT JSON parse | 521.70 | — | — | 2986.19 (5.72x) | 1458.58 (2.80x) |
| Any Duration Escape WKT JSON parse | 540.51 | — | — | 3020.20 (5.59x) | 1776.76 (3.29x) |
| Any PlusDuration WKT JSON parse | 518.39 | — | — | 2999.08 (5.79x) | 1422.82 (2.74x) |
| Any ShortFractionDuration WKT JSON parse | 520.24 | — | — | 2952.93 (5.68x) | 1446.72 (2.78x) |
| Any MicroDuration WKT JSON stringify | 133.65 | — | — | 3126.41 (23.39x) | 1125.33 (8.42x) |
| Any MicroDuration WKT JSON parse | 528.71 | — | — | 4829.25 (9.13x) | 1647.67 (3.12x) |
| Any NanoDuration WKT JSON stringify | 177.84 | — | — | 3136.24 (17.64x) | 1042.62 (5.86x) |
| Any NanoDuration WKT JSON parse | 593.25 | — | — | 4842.05 (8.16x) | 1740.68 (2.93x) |
| Any NegativeDuration WKT JSON stringify | 182.12 | — | — | 2895.25 (15.90x) | 1078.36 (5.92x) |
| Any NegativeDuration WKT JSON parse | 581.35 | — | — | 3178.24 (5.47x) | 1597.33 (2.75x) |
| Any FractionalNegativeDuration WKT JSON stringify | 171.46 | — | — | 1890.69 (11.03x) | 1063.48 (6.20x) |
| Any FractionalNegativeDuration WKT JSON parse | 573.53 | — | — | 3074.53 (5.36x) | 1634.38 (2.85x) |
| Any MaxDuration WKT JSON stringify | 127.83 | — | — | 1742.72 (13.63x) | 989.61 (7.74x) |
| Any MaxDuration WKT JSON parse | 552.83 | — | — | 3380.67 (6.12x) | 1565.83 (2.83x) |
| Any MinDuration WKT JSON stringify | 123.04 | — | — | 1788.78 (14.54x) | 1033.26 (8.40x) |
| Any MinDuration WKT JSON parse | 554.68 | — | — | 3653.44 (6.59x) | 2338.66 (4.22x) |
| Any ZeroDuration WKT JSON stringify | 110.52 | — | — | 1347.59 (12.19x) | 1978.83 (17.90x) |
| Any ZeroDuration WKT JSON parse | 485.03 | — | — | 3370.30 (6.95x) | 1435.76 (2.96x) |
| Any FieldMask WKT JSON stringify | 243.84 | — | — | 2548.64 (10.45x) | 1465.13 (6.01x) |
| Any FieldMask WKT JSON parse | 717.67 | — | — | 3312.13 (4.62x) | 2194.41 (3.06x) |
| Any FieldMask Escape WKT JSON parse | 758.07 | — | — | 3257.56 (4.30x) | 2393.17 (3.16x) |
| Any EmptyFieldMask WKT JSON stringify | 117.94 | — | — | 924.42 (7.84x) | 746.42 (6.33x) |
| Any EmptyFieldMask WKT JSON parse | 440.46 | — | — | 2181.94 (4.95x) | 1219.56 (2.77x) |
| Any Timestamp WKT JSON stringify | 185.81 | — | — | 2057.71 (11.07x) | 992.43 (5.34x) |
| Any Timestamp WKT JSON parse | 582.71 | — | — | 3095.20 (5.31x) | 1594.77 (2.74x) |
| Any Timestamp Escape WKT JSON parse | 603.19 | — | — | 3145.88 (5.22x) | 1703.49 (2.82x) |
| Any ShortFraction Timestamp WKT JSON parse | 579.28 | — | — | 3112.09 (5.37x) | 1841.02 (3.18x) |
| Any Micro Timestamp WKT JSON stringify | 189.52 | — | — | 2045.16 (10.79x) | 1002.93 (5.29x) |
| Any Micro Timestamp WKT JSON parse | 582.69 | — | — | 3057.73 (5.25x) | 2234.16 (3.83x) |
| Any Nano Timestamp WKT JSON stringify | 187.09 | — | — | 2042.08 (10.91x) | 1114.90 (5.96x) |
| Any Nano Timestamp WKT JSON parse | 586.22 | — | — | 3222.81 (5.50x) | 1873.65 (3.20x) |
| Any Offset Timestamp WKT JSON parse | 595.53 | — | — | 7611.83 (12.78x) | 1616.79 (2.71x) |
| Any PreEpoch Timestamp WKT JSON stringify | 145.36 | — | — | 2960.61 (20.37x) | 959.14 (6.60x) |
| Any PreEpoch Timestamp WKT JSON parse | 561.88 | — | — | 3082.58 (5.49x) | 1559.64 (2.78x) |
| Any Max Timestamp WKT JSON stringify | 169.65 | — | — | 2070.77 (12.21x) | 1046.98 (6.17x) |
| Any Max Timestamp WKT JSON parse | 591.48 | — | — | 3142.68 (5.31x) | 1564.85 (2.65x) |
| Any Min Timestamp WKT JSON stringify | 168.24 | — | — | 1950.02 (11.59x) | 964.49 (5.73x) |
| Any Min Timestamp WKT JSON parse | 557.24 | — | — | 3047.50 (5.47x) | 1497.65 (2.69x) |
| Any Empty WKT JSON stringify | 93.13 | — | — | 921.09 (9.89x) | 614.71 (6.60x) |
| Any Empty WKT JSON parse | 335.96 | — | — | 2134.25 (6.35x) | 1248.37 (3.72x) |
| Any Struct WKT JSON stringify | 639.61 | — | — | 5859.97 (9.16x) | 6486.58 (10.14x) |
| Any Struct WKT JSON parse | 1744.53 | — | — | 11111.70 (6.37x) | 9021.15 (5.17x) |
| Any Struct Escape WKT JSON parse | 1773.34 | — | — | 11256.70 (6.35x) | 11479.95 (6.47x) |
| Any EmptyStruct WKT JSON stringify | 120.19 | — | — | 916.74 (7.63x) | 957.51 (7.97x) |
| Any EmptyStruct WKT JSON parse | 439.62 | — | — | 2237.85 (5.09x) | 1816.75 (4.13x) |
| Any Value WKT JSON stringify | 669.89 | — | — | 5845.41 (8.73x) | 7805.25 (11.65x) |
| Any Value WKT JSON parse | 1802.67 | — | — | 11367.80 (6.31x) | 11266.15 (6.25x) |
| Any Value Escape WKT JSON parse | 1834.28 | — | — | 11419.70 (6.23x) | 11456.86 (6.25x) |
| Any NullValue WKT JSON stringify | 132.37 | — | — | 2272.77 (17.17x) | 1014.71 (7.67x) |
| Any NullValue WKT JSON parse | 466.67 | — | — | 4051.58 (8.68x) | 2023.01 (4.33x) |
| Any StringScalarValue WKT JSON stringify | 152.83 | — | — | 2269.50 (14.85x) | 1433.92 (9.38x) |
| Any StringScalarValue WKT JSON parse | 523.16 | — | — | 3625.38 (6.93x) | 1657.80 (3.17x) |
| Any StringScalarValue Escape WKT JSON parse | 536.12 | — | — | 3698.90 (6.90x) | 1886.15 (3.52x) |
| Any EmptyStringScalarValue WKT JSON stringify | 140.60 | — | — | 2290.02 (16.29x) | 1322.14 (9.40x) |
| Any EmptyStringScalarValue WKT JSON parse | 493.65 | — | — | 3603.57 (7.30x) | 2180.69 (4.42x) |
| Any NumberValue WKT JSON stringify | 175.50 | — | — | 2519.65 (14.36x) | 1700.46 (9.69x) |
| Any NumberValue WKT JSON parse | 506.36 | — | — | 3691.84 (7.29x) | 1575.79 (3.11x) |
| Any ZeroNumberValue WKT JSON stringify | 142.24 | — | — | 2479.45 (17.43x) | 1319.99 (9.28x) |
| Any ZeroNumberValue WKT JSON parse | 502.79 | — | — | 3673.98 (7.31x) | 1888.48 (3.76x) |
| Any BoolScalarValue WKT JSON stringify | 132.46 | — | — | 2247.40 (16.97x) | 1799.07 (13.58x) |
| Any BoolScalarValue WKT JSON parse | 467.05 | — | — | 3609.15 (7.73x) | 2813.18 (6.02x) |
| Any FalseBoolScalarValue WKT JSON stringify | 134.55 | — | — | 2258.63 (16.79x) | 1108.60 (8.24x) |
| Any FalseBoolScalarValue WKT JSON parse | 467.50 | — | — | 3596.34 (7.69x) | 2648.17 (5.66x) |
| Any ListKindValue WKT JSON stringify | 509.82 | — | — | 5545.76 (10.88x) | 5396.43 (10.58x) |
| Any ListKindValue WKT JSON parse | 1401.99 | — | — | 10002.80 (7.13x) | 7641.74 (5.45x) |
| Any ListKindValue Escape WKT JSON parse | 1431.35 | — | — | 10037.70 (7.01x) | 7438.47 (5.20x) |
| Any EmptyStructKindValue WKT JSON stringify | 148.24 | — | — | 2932.97 (19.79x) | 1363.48 (9.20x) |
| Any EmptyStructKindValue WKT JSON parse | 500.31 | — | — | 5412.16 (10.82x) | 1899.54 (3.80x) |
| Any EmptyListKindValue WKT JSON stringify | 145.43 | — | — | 2919.94 (20.08x) | 1077.48 (7.41x) |
| Any EmptyListKindValue WKT JSON parse | 506.80 | — | — | 4409.16 (8.70x) | 2118.62 (4.18x) |
| Any DoubleValue WKT JSON stringify | 193.52 | — | — | 1797.53 (9.29x) | 816.69 (4.22x) |
| Any DoubleValue WKT JSON parse | 519.48 | — | — | 2728.49 (5.25x) | 2084.85 (4.01x) |
| Any DoubleValue String WKT JSON parse | 532.19 | — | — | 2730.97 (5.13x) | 1407.98 (2.65x) |
| Any NegativeDoubleValue WKT JSON stringify | 192.38 | — | — | 1793.28 (9.32x) | 762.63 (3.96x) |
| Any NegativeDoubleValue WKT JSON parse | 520.39 | — | — | 2743.79 (5.27x) | 1488.80 (2.86x) |
| Any ZeroDoubleValue WKT JSON stringify | 158.56 | — | — | 919.04 (5.80x) | 719.59 (4.54x) |
| Any ZeroDoubleValue WKT JSON parse | 516.26 | — | — | 2174.36 (4.21x) | 1627.33 (3.15x) |
| Any DoubleValue NaN WKT JSON stringify | 153.79 | — | — | 1562.22 (10.16x) | 1131.94 (7.36x) |
| Any DoubleValue NaN WKT JSON parse | 519.23 | — | — | 2663.69 (5.13x) | 1298.22 (2.50x) |
| Any DoubleValue Infinity WKT JSON stringify | 158.89 | — | — | 1559.66 (9.82x) | 831.28 (5.23x) |
| Any DoubleValue Infinity WKT JSON parse | 524.89 | — | — | 2666.63 (5.08x) | 1341.87 (2.56x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 157.30 | — | — | 1554.59 (9.88x) | 719.42 (4.57x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 519.88 | — | — | 2672.42 (5.14x) | 1399.12 (2.69x) |
| Any FloatValue WKT JSON stringify | 193.01 | — | — | 1733.73 (8.98x) | 778.04 (4.03x) |
| Any FloatValue WKT JSON parse | 521.16 | — | — | 2703.49 (5.19x) | 1402.32 (2.69x) |
| Any FloatValue String WKT JSON parse | 535.97 | — | — | 2716.96 (5.07x) | 1486.64 (2.77x) |
| Any NegativeFloatValue WKT JSON stringify | 197.97 | — | — | 1752.62 (8.85x) | 760.55 (3.84x) |
| Any NegativeFloatValue WKT JSON parse | 521.41 | — | — | 2720.11 (5.22x) | 1326.41 (2.54x) |
| Any ZeroFloatValue WKT JSON stringify | 160.46 | — | — | 915.53 (5.71x) | 751.96 (4.69x) |
| Any ZeroFloatValue WKT JSON parse | 822.18 | — | — | 2151.76 (2.62x) | 1397.93 (1.70x) |
| Any FloatValue NaN WKT JSON stringify | 241.47 | — | — | 1570.11 (6.50x) | 729.31 (3.02x) |
| Any FloatValue NaN WKT JSON parse | 818.60 | — | — | 2684.84 (3.28x) | 1426.48 (1.74x) |
| Any FloatValue Infinity WKT JSON stringify | 179.32 | — | — | 1562.47 (8.71x) | 744.88 (4.15x) |
| Any FloatValue Infinity WKT JSON parse | 592.39 | — | — | 2682.36 (4.53x) | 1421.89 (2.40x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 201.84 | — | — | 1546.99 (7.66x) | 980.45 (4.86x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 582.74 | — | — | 2656.89 (4.56x) | 1467.97 (2.52x) |
| Any Int64Value WKT JSON stringify | 172.19 | — | — | 1560.26 (9.06x) | 882.02 (5.12x) |
| Any Int64Value WKT JSON parse | 561.54 | — | — | 2793.85 (4.98x) | 1723.19 (3.07x) |
| Any Int64Value Number WKT JSON parse | 557.77 | — | — | 2754.76 (4.94x) | 1506.04 (2.70x) |
| Any ZeroInt64Value WKT JSON stringify | 160.76 | — | — | 924.25 (5.75x) | 1102.83 (6.86x) |
| Any ZeroInt64Value WKT JSON parse | 525.61 | — | — | 2172.83 (4.13x) | 1478.46 (2.81x) |
| Any NegativeInt64Value WKT JSON stringify | 170.48 | — | — | 1561.27 (9.16x) | 835.61 (4.90x) |
| Any NegativeInt64Value WKT JSON parse | 557.75 | — | — | 2814.55 (5.05x) | 1644.31 (2.95x) |
| Any MinInt64Value WKT JSON stringify | 173.03 | — | — | 1559.27 (9.01x) | 1066.89 (6.17x) |
| Any MinInt64Value WKT JSON parse | 565.26 | — | — | 2822.95 (4.99x) | 1581.53 (2.80x) |
| Any MaxInt64Value WKT JSON stringify | 177.78 | — | — | 1561.26 (8.78x) | 874.59 (4.92x) |
| Any MaxInt64Value WKT JSON parse | 570.85 | — | — | 2820.80 (4.94x) | 1594.61 (2.79x) |
| Any UInt64Value WKT JSON stringify | 179.52 | — | — | 1558.77 (8.68x) | 807.60 (4.50x) |
| Any UInt64Value WKT JSON parse | 550.74 | — | — | 2799.87 (5.08x) | 2506.22 (4.55x) |
| Any UInt64Value Number WKT JSON parse | 554.04 | — | — | 2771.90 (5.00x) | 1488.09 (2.69x) |
| Any ZeroUInt64Value WKT JSON stringify | 164.80 | — | — | 914.92 (5.55x) | 743.24 (4.51x) |
| Any ZeroUInt64Value WKT JSON parse | 523.32 | — | — | 2149.47 (4.11x) | 1386.87 (2.65x) |
| Any MaxUInt64Value WKT JSON stringify | 180.56 | — | — | 1557.64 (8.63x) | 893.88 (4.95x) |
| Any MaxUInt64Value WKT JSON parse | 562.76 | — | — | 2844.13 (5.05x) | 1616.10 (2.87x) |
| Any Int32Value WKT JSON stringify | 171.10 | — | — | 1553.13 (9.08x) | 735.08 (4.30x) |
| Any Int32Value WKT JSON parse | 533.19 | — | — | 2691.51 (5.05x) | 1529.89 (2.87x) |
| Any Int32Value String WKT JSON parse | 538.10 | — | — | 2681.50 (4.98x) | 1542.64 (2.87x) |
| Any ZeroInt32Value WKT JSON stringify | 165.14 | — | — | 914.01 (5.53x) | 689.33 (4.17x) |
| Any ZeroInt32Value WKT JSON parse | 527.87 | — | — | 2154.90 (4.08x) | 1870.22 (3.54x) |
| Any NegativeInt32Value WKT JSON stringify | 170.66 | — | — | 1552.33 (9.10x) | 740.74 (4.34x) |
| Any NegativeInt32Value WKT JSON parse | 534.11 | — | — | 2707.05 (5.07x) | 1386.73 (2.60x) |
| Any MinInt32Value WKT JSON stringify | 171.65 | — | — | 1553.73 (9.05x) | 753.75 (4.39x) |
| Any MinInt32Value WKT JSON parse | 539.58 | — | — | 2701.30 (5.01x) | 1533.24 (2.84x) |
| Any MaxInt32Value WKT JSON stringify | 174.98 | — | — | 1552.31 (8.87x) | 750.22 (4.29x) |
| Any MaxInt32Value WKT JSON parse | 538.79 | — | — | 2682.07 (4.98x) | 1393.20 (2.59x) |
| Any UInt32Value WKT JSON stringify | 179.18 | — | — | 1548.93 (8.64x) | 1040.98 (5.81x) |
| Any UInt32Value WKT JSON parse | 538.34 | — | — | 2666.43 (4.95x) | 1784.84 (3.32x) |
| Any UInt32Value String WKT JSON parse | 542.91 | — | — | 2670.32 (4.92x) | 1730.57 (3.19x) |
| Any ZeroUInt32Value WKT JSON stringify | 174.35 | — | — | 916.70 (5.26x) | 1135.38 (6.51x) |
| Any ZeroUInt32Value WKT JSON parse | 533.38 | — | — | 2171.52 (4.07x) | 1433.24 (2.69x) |
| Any MaxUInt32Value WKT JSON stringify | 180.45 | — | — | 1554.84 (8.62x) | 855.37 (4.74x) |
| Any MaxUInt32Value WKT JSON parse | 547.42 | — | — | 2692.69 (4.92x) | 1539.13 (2.81x) |
| Any BoolValue WKT JSON stringify | 172.32 | — | — | 1527.05 (8.86x) | 1043.78 (6.06x) |
| Any BoolValue WKT JSON parse | 489.38 | — | — | 2610.75 (5.33x) | 1846.28 (3.77x) |
| Any FalseBoolValue WKT JSON stringify | 174.24 | — | — | 915.91 (5.26x) | 1176.09 (6.75x) |
| Any FalseBoolValue WKT JSON parse | 491.69 | — | — | 2155.35 (4.38x) | 1808.76 (3.68x) |
| Any StringValue WKT JSON stringify | 193.26 | — | — | 1577.01 (8.16x) | 1717.01 (8.88x) |
| Any StringValue WKT JSON parse | 551.95 | — | — | 2664.01 (4.83x) | 2005.56 (3.63x) |
| Any StringValue Escape WKT JSON parse | 558.88 | — | — | 2704.68 (4.84x) | 1753.32 (3.14x) |
| Any EmptyStringValue WKT JSON stringify | 187.69 | — | — | 915.66 (4.88x) | 1563.92 (8.33x) |
| Any EmptyStringValue WKT JSON parse | 520.83 | — | — | 2187.61 (4.20x) | 1850.97 (3.55x) |
| Any BytesValue WKT JSON stringify | 186.34 | — | — | 1603.76 (8.61x) | 1603.31 (8.60x) |
| Any BytesValue WKT JSON parse | 562.19 | — | — | 2703.57 (4.81x) | 3663.94 (6.52x) |
| Any BytesValue URL WKT JSON parse | 580.83 | — | — | 2687.90 (4.63x) | 1402.12 (2.41x) |
| Any EmptyBytesValue WKT JSON stringify | 180.93 | — | — | 915.80 (5.06x) | 1815.78 (10.04x) |
| Any EmptyBytesValue WKT JSON parse | 527.76 | — | — | 2164.63 (4.10x) | 2001.86 (3.79x) |
| Nested Any WKT JSON stringify | 307.14 | — | — | 2503.04 (8.15x) | 4405.91 (14.34x) |
| Nested Any WKT JSON parse | 871.91 | — | — | 4286.61 (4.92x) | 6278.38 (7.20x) |
| Duration JSON stringify | 58.20 | — | — | 972.20 (16.70x) | 376.32 (6.47x) |
| Duration JSON parse | 18.94 | — | — | 1465.64 (77.38x) | 550.76 (29.08x) |
| Duration Escape JSON parse | 38.42 | — | — | 1503.37 (39.13x) | 439.35 (11.44x) |
| PlusDuration JSON parse | 17.82 | — | — | 1456.18 (81.72x) | 396.19 (22.23x) |
| ShortFractionDuration JSON parse | 15.55 | — | — | 1431.26 (92.04x) | 388.96 (25.01x) |
| MicroDuration JSON stringify | 59.52 | — | — | 977.19 (16.42x) | 387.99 (6.52x) |
| MicroDuration JSON parse | 20.08 | — | — | 1480.77 (73.74x) | 378.29 (18.84x) |
| NanoDuration JSON stringify | 57.86 | — | — | 1001.31 (17.31x) | 386.91 (6.69x) |
| NanoDuration JSON parse | 22.62 | — | — | 1485.03 (65.65x) | 380.18 (16.81x) |
| NegativeDuration JSON stringify | 58.57 | — | — | 1001.97 (17.11x) | 426.44 (7.28x) |
| NegativeDuration JSON parse | 19.11 | — | — | 1512.86 (79.17x) | 398.20 (20.84x) |
| FractionalNegativeDuration JSON stringify | 58.41 | — | — | 968.89 (16.59x) | 408.66 (7.00x) |
| FractionalNegativeDuration JSON parse | 18.57 | — | — | 1476.00 (79.48x) | 348.20 (18.75x) |
| MaxDuration JSON stringify | 49.63 | — | — | 860.11 (17.33x) | 390.10 (7.86x) |
| MaxDuration JSON parse | 33.86 | — | — | 1444.94 (42.67x) | 385.18 (11.38x) |
| MinDuration JSON stringify | 49.89 | — | — | 864.55 (17.33x) | 440.69 (8.83x) |
| MinDuration JSON parse | 33.91 | — | — | 1462.15 (43.12x) | 622.45 (18.36x) |
| ZeroDuration JSON stringify | 44.88 | — | — | 813.53 (18.13x) | 957.30 (21.33x) |
| ZeroDuration JSON parse | 15.30 | — | — | 1380.32 (90.22x) | 958.95 (62.68x) |
| FieldMask JSON stringify | 67.06 | — | — | 889.89 (13.27x) | 1117.47 (16.66x) |
| FieldMask JSON parse | 139.19 | — | — | 1659.37 (11.92x) | 3108.09 (22.33x) |
| FieldMask Escape JSON parse | 190.42 | — | — | 1718.49 (9.02x) | 2617.08 (13.74x) |
| EmptyFieldMask JSON stringify | 40.62 | — | — | 606.43 (14.93x) | 609.53 (15.01x) |
| EmptyFieldMask JSON parse | 4.79 | — | — | 951.93 (198.73x) | 632.28 (132.00x) |
| Timestamp JSON stringify | 95.47 | — | — | 1149.48 (12.04x) | 698.26 (7.31x) |
| Timestamp JSON parse | 47.27 | — | — | 1510.50 (31.95x) | 1137.98 (24.07x) |
| Timestamp Escape JSON parse | 81.44 | — | — | 1529.79 (18.78x) | 780.83 (9.59x) |
| ShortFraction Timestamp JSON parse | 43.44 | — | — | 1498.90 (34.51x) | 438.99 (10.11x) |
| Micro Timestamp JSON stringify | 95.53 | — | — | 1158.18 (12.12x) | 444.77 (4.66x) |
| Micro Timestamp JSON parse | 50.17 | — | — | 1517.95 (30.26x) | 439.78 (8.77x) |
| Nano Timestamp JSON stringify | 93.89 | — | — | 1197.59 (12.76x) | 427.27 (4.55x) |
| Nano Timestamp JSON parse | 51.97 | — | — | 1538.42 (29.60x) | 442.80 (8.52x) |
| Offset Timestamp JSON parse | 57.30 | — | — | 1546.11 (26.98x) | 478.83 (8.36x) |
| PreEpoch Timestamp JSON stringify | 66.67 | — | — | 1083.35 (16.25x) | 419.51 (6.29x) |
| PreEpoch Timestamp JSON parse | 42.93 | — | — | 1481.55 (34.51x) | 394.52 (9.19x) |
| Max Timestamp JSON stringify | 78.40 | — | — | 1207.90 (15.41x) | 432.67 (5.52x) |
| Max Timestamp JSON parse | 51.08 | — | — | 1552.11 (30.39x) | 464.80 (9.10x) |
| Min Timestamp JSON stringify | 79.27 | — | — | 1061.76 (13.39x) | 414.24 (5.23x) |
| Min Timestamp JSON parse | 40.93 | — | — | 1468.64 (35.88x) | 424.99 (10.38x) |
| Empty JSON stringify | 21.15 | — | — | 496.63 (23.48x) | 82.50 (3.90x) |
| Empty JSON parse | 68.70 | — | — | 722.90 (10.52x) | 221.68 (3.23x) |
| Struct JSON stringify | 177.30 | — | — | 5809.82 (32.77x) | 3001.25 (16.93x) |
| Struct JSON parse | 856.08 | — | — | 10945.80 (12.79x) | 5281.81 (6.17x) |
| Struct Escape JSON parse | 900.04 | — | — | 11004.20 (12.23x) | 5981.80 (6.65x) |
| EmptyStruct JSON stringify | 41.44 | — | — | 699.05 (16.87x) | 328.37 (7.92x) |
| EmptyStruct JSON parse | 86.67 | — | — | 2040.61 (23.54x) | 354.87 (4.09x) |
| Value JSON stringify | 183.35 | — | — | 6568.02 (35.82x) | 3625.95 (19.78x) |
| Value JSON parse | 868.89 | — | — | 12173.20 (14.01x) | 7090.01 (8.16x) |
| Value Escape JSON parse | 910.57 | — | — | 12293.40 (13.50x) | 6505.83 (7.14x) |
| NullValue JSON stringify | 40.38 | — | — | 1329.83 (32.93x) | 273.28 (6.77x) |
| NullValue JSON parse | 69.68 | — | — | 2485.16 (35.67x) | 622.64 (8.94x) |
| StringScalarValue JSON stringify | 47.64 | — | — | 1358.38 (28.51x) | 445.49 (9.35x) |
| StringScalarValue JSON parse | 140.85 | — | — | 2103.05 (14.93x) | 690.89 (4.91x) |
| StringScalarValue Escape JSON parse | 150.11 | — | — | 2150.38 (14.33x) | 891.30 (5.94x) |
| EmptyStringScalarValue JSON stringify | 45.71 | — | — | 1353.97 (29.62x) | 365.56 (8.00x) |
| EmptyStringScalarValue JSON parse | 87.21 | — | — | 2086.81 (23.93x) | 524.77 (6.02x) |
| NumberValue JSON stringify | 73.24 | — | — | 1564.71 (21.36x) | 403.47 (5.51x) |
| NumberValue JSON parse | 131.58 | — | — | 2190.47 (16.65x) | 449.89 (3.42x) |
| ZeroNumberValue JSON stringify | 50.78 | — | — | 1518.40 (29.90x) | 427.75 (8.42x) |
| ZeroNumberValue JSON parse | 129.78 | — | — | 2118.48 (16.32x) | 411.89 (3.17x) |
| BoolScalarValue JSON stringify | 40.51 | — | — | 1317.50 (32.52x) | 237.95 (5.87x) |
| BoolScalarValue JSON parse | 69.67 | — | — | 2032.68 (29.18x) | 319.97 (4.59x) |
| FalseBoolScalarValue JSON stringify | 40.57 | — | — | 1324.86 (32.66x) | 231.51 (5.71x) |
| FalseBoolScalarValue JSON parse | 70.16 | — | — | 2034.23 (28.99x) | 351.14 (5.00x) |
| ListKindValue JSON stringify | 141.79 | — | — | 6159.21 (43.44x) | 2297.11 (16.20x) |
| ListKindValue JSON parse | 670.41 | — | — | 10467.40 (15.61x) | 3917.32 (5.84x) |
| ListKindValue Escape JSON parse | 690.33 | — | — | 10557.90 (15.29x) | 4168.35 (6.04x) |
| EmptyStructKindValue JSON stringify | 42.89 | — | — | 1944.03 (45.33x) | 637.06 (14.85x) |
| EmptyStructKindValue JSON parse | 110.26 | — | — | 3753.66 (34.04x) | 1248.53 (11.32x) |
| EmptyListKindValue JSON stringify | 41.11 | — | — | 1950.21 (47.44x) | 401.87 (9.78x) |
| EmptyListKindValue JSON parse | 146.68 | — | — | 4044.40 (27.57x) | 637.73 (4.35x) |
| ListValue JSON stringify | 147.04 | — | — | 4729.85 (32.17x) | 2325.27 (15.81x) |
| ListValue JSON parse | 660.30 | — | — | 8563.36 (12.97x) | 3982.69 (6.03x) |
| ListValue Escape JSON parse | 684.56 | — | — | 8618.75 (12.59x) | 3810.99 (5.57x) |
| EmptyListValue JSON stringify | 40.68 | — | — | 684.82 (16.83x) | 185.44 (4.56x) |
| EmptyListValue JSON parse | 127.30 | — | — | 2268.95 (17.82x) | 427.49 (3.36x) |
| DoubleValue JSON stringify | 67.97 | — | — | 855.57 (12.59x) | 180.41 (2.65x) |
| DoubleValue JSON parse | 111.04 | — | — | 1231.63 (11.09x) | 299.99 (2.70x) |
| DoubleValue String JSON parse | 111.16 | — | — | 1171.94 (10.54x) | 337.31 (3.03x) |
| NegativeDoubleValue JSON stringify | 68.28 | — | — | 863.48 (12.65x) | 218.40 (3.20x) |
| NegativeDoubleValue JSON parse | 111.19 | — | — | 1242.30 (11.17x) | 425.82 (3.83x) |
| ZeroDoubleValue JSON stringify | 47.67 | — | — | 795.64 (16.69x) | 141.60 (2.97x) |
| ZeroDoubleValue JSON parse | 107.94 | — | — | 1167.33 (10.81x) | 255.16 (2.36x) |
| DoubleValue NaN JSON stringify | 46.12 | — | — | 658.85 (14.29x) | 140.07 (3.04x) |
| DoubleValue NaN JSON parse | 104.86 | — | — | 1098.60 (10.48x) | 258.55 (2.47x) |
| DoubleValue Infinity JSON stringify | 48.05 | — | — | 651.93 (13.57x) | 118.78 (2.47x) |
| DoubleValue Infinity JSON parse | 105.94 | — | — | 1110.40 (10.48x) | 278.15 (2.63x) |
| DoubleValue NegativeInfinity JSON stringify | 48.05 | — | — | 648.61 (13.50x) | 125.23 (2.61x) |
| DoubleValue NegativeInfinity JSON parse | 108.51 | — | — | 1107.03 (10.20x) | 282.12 (2.60x) |
| FloatValue JSON stringify | 71.95 | — | — | 801.90 (11.15x) | 175.20 (2.44x) |
| FloatValue JSON parse | 110.05 | — | — | 1216.27 (11.05x) | 293.67 (2.67x) |
| FloatValue String JSON parse | 110.58 | — | — | 1153.83 (10.43x) | 356.28 (3.22x) |
| NegativeFloatValue JSON stringify | 70.32 | — | — | 800.75 (11.39x) | 178.78 (2.54x) |
| NegativeFloatValue JSON parse | 111.02 | — | — | 1233.48 (11.11x) | 297.32 (2.68x) |
| ZeroFloatValue JSON stringify | 47.23 | — | — | 741.74 (15.70x) | 137.24 (2.91x) |
| ZeroFloatValue JSON parse | 107.72 | — | — | 1161.22 (10.78x) | 243.30 (2.26x) |
| FloatValue NaN JSON stringify | 46.15 | — | — | 636.51 (13.79x) | 133.62 (2.90x) |
| FloatValue NaN JSON parse | 105.12 | — | — | 1092.46 (10.39x) | 258.39 (2.46x) |
| FloatValue Infinity JSON stringify | 48.19 | — | — | 644.31 (13.37x) | 305.40 (6.34x) |
| FloatValue Infinity JSON parse | 106.91 | — | — | 1098.66 (10.28x) | 643.31 (6.02x) |
| FloatValue NegativeInfinity JSON stringify | 47.87 | — | — | 637.62 (13.32x) | 150.20 (3.14x) |
| FloatValue NegativeInfinity JSON parse | 108.27 | — | — | 1100.15 (10.16x) | 375.18 (3.47x) |
| Int64Value JSON stringify | 50.32 | — | — | 673.29 (13.38x) | 242.88 (4.83x) |
| Int64Value JSON parse | 126.25 | — | — | 1228.56 (9.73x) | 436.57 (3.46x) |
| Int64Value Number JSON parse | 126.69 | — | — | 1287.60 (10.16x) | 343.87 (2.71x) |
| ZeroInt64Value JSON stringify | 41.30 | — | — | 612.77 (14.84x) | 194.90 (4.72x) |
| ZeroInt64Value JSON parse | 106.21 | — | — | 1108.98 (10.44x) | 328.95 (3.10x) |
| NegativeInt64Value JSON stringify | 49.93 | — | — | 674.92 (13.52x) | 262.81 (5.26x) |
| NegativeInt64Value JSON parse | 127.97 | — | — | 1232.04 (9.63x) | 449.99 (3.52x) |
| MinInt64Value JSON stringify | 49.33 | — | — | 673.61 (13.66x) | 267.18 (5.42x) |
| MinInt64Value JSON parse | 135.47 | — | — | 1255.35 (9.27x) | 501.72 (3.70x) |
| MaxInt64Value JSON stringify | 49.11 | — | — | 676.65 (13.78x) | 288.87 (5.88x) |
| MaxInt64Value JSON parse | 134.85 | — | — | 1251.84 (9.28x) | 446.34 (3.31x) |
| UInt64Value JSON stringify | 49.70 | — | — | 680.46 (13.69x) | 277.94 (5.59x) |
| UInt64Value JSON parse | 125.61 | — | — | 1233.95 (9.82x) | 491.67 (3.91x) |
| UInt64Value Number JSON parse | 127.90 | — | — | 1286.61 (10.06x) | 739.74 (5.78x) |
| ZeroUInt64Value JSON stringify | 41.14 | — | — | 610.14 (14.83x) | 191.25 (4.65x) |
| ZeroUInt64Value JSON parse | 105.52 | — | — | 1105.49 (10.48x) | 345.66 (3.28x) |
| MaxUInt64Value JSON stringify | 49.39 | — | — | 678.50 (13.74x) | 271.87 (5.50x) |
| MaxUInt64Value JSON parse | 150.72 | — | — | 1256.45 (8.34x) | 486.11 (3.23x) |
| Int32Value JSON stringify | 46.80 | — | — | 635.76 (13.58x) | 128.76 (2.75x) |
| Int32Value JSON parse | 118.66 | — | — | 1189.63 (10.03x) | 303.49 (2.56x) |
| Int32Value String JSON parse | 114.73 | — | — | 1134.33 (9.89x) | 390.05 (3.40x) |
| ZeroInt32Value JSON stringify | 46.78 | — | — | 620.73 (13.27x) | 145.48 (3.11x) |
| ZeroInt32Value JSON parse | 113.15 | — | — | 1167.78 (10.32x) | 275.23 (2.43x) |
| NegativeInt32Value JSON stringify | 46.89 | — | — | 641.80 (13.69x) | 151.45 (3.23x) |
| NegativeInt32Value JSON parse | 117.86 | — | — | 1205.12 (10.23x) | 306.21 (2.60x) |
| MinInt32Value JSON stringify | 47.39 | — | — | 645.37 (13.62x) | 127.31 (2.69x) |
| MinInt32Value JSON parse | 128.41 | — | — | 1227.25 (9.56x) | 336.24 (2.62x) |
| MaxInt32Value JSON stringify | 47.15 | — | — | 635.47 (13.48x) | 144.65 (3.07x) |
| MaxInt32Value JSON parse | 129.27 | — | — | 1204.13 (9.31x) | 331.43 (2.56x) |
| UInt32Value JSON stringify | 46.83 | — | — | 634.59 (13.55x) | 248.98 (5.32x) |
| UInt32Value JSON parse | 117.17 | — | — | 1194.42 (10.19x) | 598.58 (5.11x) |
| UInt32Value String JSON parse | 114.76 | — | — | 1136.87 (9.91x) | 458.85 (4.00x) |
| ZeroUInt32Value JSON stringify | 46.65 | — | — | 614.69 (13.18x) | 169.30 (3.63x) |
| ZeroUInt32Value JSON parse | 112.96 | — | — | 1165.14 (10.31x) | 457.64 (4.05x) |
| MaxUInt32Value JSON stringify | 47.05 | — | — | 635.97 (13.52x) | 147.07 (3.13x) |
| MaxUInt32Value JSON parse | 122.31 | — | — | 1215.20 (9.94x) | 565.09 (4.62x) |
| BoolValue JSON stringify | 45.31 | — | — | 618.07 (13.64x) | 287.32 (6.34x) |
| BoolValue JSON parse | 60.14 | — | — | 1055.30 (17.55x) | 405.96 (6.75x) |
| FalseBoolValue JSON stringify | 45.27 | — | — | 602.91 (13.32x) | 188.91 (4.17x) |
| FalseBoolValue JSON parse | 60.39 | — | — | 1061.59 (17.58x) | 416.44 (6.90x) |
| StringValue JSON stringify | 51.87 | — | — | 665.99 (12.84x) | 190.92 (3.68x) |
| StringValue JSON parse | 119.75 | — | — | 1191.21 (9.95x) | 291.65 (2.44x) |
| StringValue Escape JSON parse | 129.88 | — | — | 1192.86 (9.18x) | 338.92 (2.61x) |
| EmptyStringValue JSON stringify | 49.05 | — | — | 628.51 (12.81x) | 327.48 (6.68x) |
| EmptyStringValue JSON parse | 65.90 | — | — | 1123.61 (17.05x) | 414.13 (6.28x) |
| BytesValue JSON stringify | 49.00 | — | — | 659.09 (13.45x) | 258.11 (5.27x) |
| BytesValue JSON parse | 126.57 | — | — | 1168.66 (9.23x) | 318.56 (2.52x) |
| BytesValue URL JSON parse | 142.33 | — | — | 1160.46 (8.15x) | 433.42 (3.05x) |
| EmptyBytesValue JSON stringify | 40.63 | — | — | 630.55 (15.52x) | 246.07 (6.06x) |
| EmptyBytesValue JSON parse | 68.76 | — | — | 1128.37 (16.41x) | 635.81 (9.25x) |
| TextFormat format | 175.15 | — | — | 2572.13 (14.69x) | 2351.11 (13.42x) |
| TextFormat parse | 667.76 | — | — | 4978.92 (7.46x) | 6482.25 (9.71x) |
| packed fixed32 encode | 2.01 | 552.55 (274.90x) | 547.50 (272.39x) | 43.76 (21.77x) | 436.84 (217.33x) |
| packed fixed32 decode | 4.53 | 1020.78 (225.34x) | 1960.68 (432.82x) | 49.82 (11.00x) | 1693.66 (373.88x) |
| packed fixed64 encode | 2.01 | 573.48 (285.31x) | 588.02 (292.55x) | 76.87 (38.25x) | 398.92 (198.47x) |
| packed fixed64 decode | 4.53 | 1045.01 (230.69x) | 7941.37 (1753.06x) | 79.90 (17.64x) | 2512.70 (554.68x) |
| packed sfixed32 encode | 2.01 | 552.64 (274.95x) | 539.55 (268.43x) | 44.02 (21.90x) | 419.22 (208.57x) |
| packed sfixed32 decode | 4.52 | 1057.97 (234.06x) | 1957.83 (433.15x) | 49.14 (10.87x) | 3035.68 (671.61x) |
| packed sfixed64 encode | 2.01 | 570.51 (283.84x) | 563.02 (280.11x) | 75.62 (37.62x) | 496.23 (246.88x) |
| packed sfixed64 decode | 4.54 | 1014.86 (223.54x) | 7904.35 (1741.05x) | 79.38 (17.49x) | 2488.90 (548.22x) |
| packed float encode | 2.01 | 811.89 (403.93x) | 540.96 (269.13x) | 43.77 (21.78x) | 388.79 (193.43x) |
| packed float decode | 4.51 | 1056.03 (234.15x) | 2073.33 (459.72x) | 49.03 (10.87x) | 1656.94 (367.39x) |
| packed double encode | 2.01 | 830.80 (413.33x) | 561.85 (279.53x) | 75.90 (37.76x) | 356.36 (177.29x) |
| packed double decode | 4.52 | 987.47 (218.47x) | 2032.94 (449.77x) | 79.46 (17.58x) | 2680.21 (592.97x) |
| packed uint64 encode | 1292.57 | 4598.62 (3.56x) | 4037.71 (3.12x) | 2123.92 (1.64x) | 3460.33 (2.68x) |
| packed uint64 decode | 1789.85 | 2779.21 (1.55x) | 8851.18 (4.95x) | 2800.82 (1.56x) | 9143.36 (5.11x) |
| packed uint32 encode | 992.27 | 3625.03 (3.65x) | 3295.78 (3.32x) | 1750.49 (1.76x) | 2893.03 (2.92x) |
| packed uint32 decode | 1945.92 | 2433.86 (1.25x) | 3273.39 (1.68x) | 1986.81 (1.02x) | 5950.50 (3.06x) |
| packed int64 encode | 1450.29 | 11007.33 (7.59x) | 6048.42 (4.17x) | 2883.28 (1.99x) | 4099.76 (2.83x) |
| packed int64 decode | 2786.74 | 3383.06 (1.21x) | 10270.55 (3.69x) | 4757.49 (1.71x) | 16376.51 (5.88x) |
| packed sint32 encode | 784.27 | 3027.31 (3.86x) | 2971.69 (3.79x) | 1545.32 (1.97x) | 3372.53 (4.30x) |
| packed sint32 decode | 919.10 | 2548.75 (2.77x) | 3217.64 (3.50x) | 1125.17 (1.22x) | 5679.06 (6.18x) |
| packed sint64 encode | 1439.32 | 4935.14 (3.43x) | 4305.33 (2.99x) | 2406.04 (1.67x) | 4179.99 (2.90x) |
| packed sint64 decode | 2080.09 | 3077.13 (1.48x) | 9656.87 (4.64x) | 2935.39 (1.41x) | 13595.66 (6.54x) |
| packed bool encode | 2.01 | 1333.53 (663.45x) | 521.94 (259.67x) | 15.78 (7.85x) | 2461.44 (1224.60x) |
| packed bool decode | 266.05 | 1523.58 (5.73x) | 2551.59 (9.59x) | 813.43 (3.06x) | 2008.28 (7.55x) |
| packed enum encode | 279.97 | 2723.23 (9.73x) | 1814.34 (6.48x) | 1084.40 (3.87x) | 2707.10 (9.67x) |
| packed enum decode | 291.43 | 1534.50 (5.27x) | 2876.85 (9.87x) | 727.17 (2.50x) | 5140.98 (17.64x) |
| large map encode | 4068.77 | 16586.97 (4.08x) | 9666.45 (2.38x) | 23939.90 (5.88x) | 206951.25 (50.86x) |
| shuffled large map deterministic binary encode | 28680.43 | — | — | 101509.00 (3.54x) | 406840.29 (14.19x) |
| large map decode | 25339.10 | 90948.93 (3.59x) | 89452.17 (3.53x) | 93404.30 (3.69x) | 276645.25 (10.92x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound `Duration`, non-empty/escaped-input parse and empty `Struct`, object/escaped-object parse/list/escaped-list/string-scalar/escaped-string-scalar `Value` (including default-like scalar and empty object/list kinds),
`FieldMask` (non-empty, escaped JSON parse input, and empty), escaped-input parse/short-fraction parse/micro/nano/offset/min/pre/post/max-bound `Timestamp`, `Empty`, min/zero/positive/number-input parse/negative/max `Int64Value`, negative/zero/positive finite/string-input parse `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), negative/zero/positive finite/string-input parse `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), zero/normal/number-input parse/max `UInt64Value`, min/zero/positive/string-input parse/negative/max `Int32Value`, zero/normal/string-input parse/max `UInt32Value`, true/false `BoolValue`, non-empty/escape-input parse/empty `StringValue`, base64/base64url parse/empty `BytesValue`, and recursive nested `Any` payloads), direct zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound Duration, non-empty/escaped-input parse/empty FieldMask, and escaped-input parse/short-fraction parse/micro/nano/offset/min/pre/post/max-bound Timestamp WKT JSON plus other direct WKT JSON, including non-empty/escaped-input parse/empty `Struct`, object/escaped-object parse/list/escaped-list/string-scalar/escaped-string-scalar `Value`, and escaped/non-empty/empty `ListValue`, TextFormat, packed scalars, large bytes,
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
