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

Latest accepted comparison (`/tmp/pbz-compare-struct-value-escape-json-isolated.log`,
summarized in `/tmp/pbz-summary-struct-value-escape-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 18.84 | 107.17 (5.69x) | 53.14 (2.82x) | 102.03 (5.42x) | 887.85 (47.13x) |
| binary decode | 89.11 | 260.33 (2.92x) | 226.03 (2.54x) | 216.64 (2.43x) | 882.89 (9.91x) |
| unknown fields count by number | 3.64 | — | — | 162.18 (44.55x) | — |
| deterministic binary encode | 49.40 | — | — | 124.89 (2.53x) | 1048.99 (21.23x) |
| scalarmix encode | 20.17 | 111.39 (5.52x) | 48.14 (2.39x) | 29.97 (1.49x) | 208.59 (10.34x) |
| scalarmix decode | 36.07 | 138.41 (3.84x) | 179.56 (4.98x) | 84.99 (2.36x) | 272.75 (7.56x) |
| textbytes encode | 11.53 | 100.40 (8.71x) | 33.68 (2.92x) | 119.84 (10.39x) | 155.93 (13.52x) |
| textbytes decode | 47.85 | 390.45 (8.16x) | 238.23 (4.98x) | 164.80 (3.44x) | 653.99 (13.67x) |
| largebytes encode | 17.55 | 2715.46 (154.73x) | 2683.35 (152.90x) | 2737.29 (155.97x) | 2712.21 (154.54x) |
| largebytes decode | 91.81 | 5670.06 (61.76x) | 2996.11 (32.63x) | 2748.31 (29.93x) | 51214.87 (557.84x) |
| presencemix encode | 17.19 | 55.02 (3.20x) | 26.51 (1.54x) | 54.96 (3.20x) | 257.64 (14.99x) |
| presencemix decode | 56.62 | 132.74 (2.34x) | 110.60 (1.95x) | 161.79 (2.86x) | 582.79 (10.29x) |
| complex encode | 49.23 | 136.00 (2.76x) | 96.59 (1.96x) | 158.79 (3.23x) | 919.83 (18.68x) |
| complex decode | 168.72 | 392.49 (2.33x) | 345.45 (2.05x) | 392.38 (2.33x) | 1371.80 (8.13x) |
| complex deterministic binary encode | 92.57 | — | — | 175.43 (1.90x) | 1106.71 (11.96x) |
| complex JSON stringify | 268.91 | — | — | 4911.16 (18.26x) | 9425.73 (35.05x) |
| complex JSON parse | 2393.44 | — | — | 11897.80 (4.97x) | 8942.51 (3.74x) |
| complex TextFormat format | 247.94 | — | — | 3775.91 (15.23x) | 7611.93 (30.70x) |
| complex TextFormat parse | 1917.93 | — | — | 6923.64 (3.61x) | 8969.69 (4.68x) |
| packed int32 encode | 662.09 | 3188.60 (4.82x) | 2513.44 (3.80x) | 1236.17 (1.87x) | 2753.76 (4.16x) |
| packed int32 decode | 691.14 | 1940.02 (2.81x) | 3211.52 (4.65x) | 943.42 (1.37x) | 5196.72 (7.52x) |
| JSON stringify | 153.69 | — | — | 3010.75 (19.59x) | 2461.21 (16.01x) |
| JSON parse | 1518.78 | — | — | 7463.10 (4.91x) | 4886.84 (3.22x) |
| Any WKT JSON stringify | 131.76 | — | — | 1912.70 (14.52x) | 1347.18 (10.22x) |
| Any WKT JSON parse | 524.21 | — | — | 2981.39 (5.69x) | 1453.09 (2.77x) |
| Any Duration Escape WKT JSON parse | 544.52 | — | — | 3016.90 (5.54x) | 1769.71 (3.25x) |
| Any PlusDuration WKT JSON parse | 524.88 | — | — | 3005.65 (5.73x) | 1467.93 (2.80x) |
| Any ShortFractionDuration WKT JSON parse | 520.47 | — | — | 2953.20 (5.67x) | 1561.37 (3.00x) |
| Any MicroDuration WKT JSON stringify | 127.81 | — | — | 1897.05 (14.84x) | 961.86 (7.53x) |
| Any MicroDuration WKT JSON parse | 526.80 | — | — | 2998.86 (5.69x) | 1881.50 (3.57x) |
| Any NanoDuration WKT JSON stringify | 126.60 | — | — | 1923.75 (15.20x) | 1039.28 (8.21x) |
| Any NanoDuration WKT JSON parse | 529.73 | — | — | 3015.60 (5.69x) | 2254.72 (4.26x) |
| Any NegativeDuration WKT JSON stringify | 130.89 | — | — | 1935.41 (14.79x) | 1566.00 (11.96x) |
| Any NegativeDuration WKT JSON parse | 530.03 | — | — | 3092.08 (5.83x) | 2106.91 (3.98x) |
| Any FractionalNegativeDuration WKT JSON stringify | 125.99 | — | — | 1918.89 (15.23x) | 1044.67 (8.29x) |
| Any FractionalNegativeDuration WKT JSON parse | 520.15 | — | — | 3052.43 (5.87x) | 1437.79 (2.76x) |
| Any MaxDuration WKT JSON stringify | 117.67 | — | — | 1747.50 (14.85x) | 1549.65 (13.17x) |
| Any MaxDuration WKT JSON parse | 534.64 | — | — | 2965.28 (5.55x) | 2141.24 (4.01x) |
| Any MinDuration WKT JSON stringify | 122.60 | — | — | 1779.70 (14.52x) | 1205.53 (9.83x) |
| Any MinDuration WKT JSON parse | 536.10 | — | — | 3027.52 (5.65x) | 1596.03 (2.98x) |
| Any ZeroDuration WKT JSON stringify | 102.17 | — | — | 912.90 (8.94x) | 1170.51 (11.46x) |
| Any ZeroDuration WKT JSON parse | 472.97 | — | — | 2251.67 (4.76x) | 1383.40 (2.92x) |
| Any FieldMask WKT JSON stringify | 224.84 | — | — | 1745.55 (7.76x) | 1516.21 (6.74x) |
| Any FieldMask WKT JSON parse | 712.49 | — | — | 3161.61 (4.44x) | 2125.32 (2.98x) |
| Any FieldMask Escape WKT JSON parse | 746.71 | — | — | 3241.79 (4.34x) | 2426.16 (3.25x) |
| Any EmptyFieldMask WKT JSON stringify | 111.83 | — | — | 949.44 (8.49x) | 826.17 (7.39x) |
| Any EmptyFieldMask WKT JSON parse | 448.74 | — | — | 2159.96 (4.81x) | 1424.27 (3.17x) |
| Any Timestamp WKT JSON stringify | 179.66 | — | — | 2029.62 (11.30x) | 1451.34 (8.08x) |
| Any Timestamp WKT JSON parse | 569.67 | — | — | 3026.52 (5.31x) | 2255.31 (3.96x) |
| Any Timestamp Escape WKT JSON parse | 587.71 | — | — | 3059.19 (5.21x) | 2054.27 (3.50x) |
| Any ShortFraction Timestamp WKT JSON parse | 567.47 | — | — | 3003.85 (5.29x) | 2042.93 (3.60x) |
| Any Micro Timestamp WKT JSON stringify | 181.84 | — | — | 2046.63 (11.26x) | 1538.01 (8.46x) |
| Any Micro Timestamp WKT JSON parse | 576.70 | — | — | 3029.48 (5.25x) | 2150.89 (3.73x) |
| Any Nano Timestamp WKT JSON stringify | 177.86 | — | — | 2043.16 (11.49x) | 1315.60 (7.40x) |
| Any Nano Timestamp WKT JSON parse | 580.26 | — | — | 3035.82 (5.23x) | 1648.96 (2.84x) |
| Any Offset Timestamp WKT JSON parse | 591.29 | — | — | 3054.39 (5.17x) | 2290.18 (3.87x) |
| Any PreEpoch Timestamp WKT JSON stringify | 145.16 | — | — | 1948.83 (13.43x) | 1272.09 (8.76x) |
| Any PreEpoch Timestamp WKT JSON parse | 566.82 | — | — | 3047.20 (5.38x) | 1560.36 (2.75x) |
| Any Max Timestamp WKT JSON stringify | 163.14 | — | — | 2078.10 (12.74x) | 1155.96 (7.09x) |
| Any Max Timestamp WKT JSON parse | 585.58 | — | — | 3102.29 (5.30x) | 1712.53 (2.92x) |
| Any Min Timestamp WKT JSON stringify | 159.41 | — | — | 1960.47 (12.30x) | 2067.31 (12.97x) |
| Any Min Timestamp WKT JSON parse | 562.30 | — | — | 3041.09 (5.41x) | 2171.35 (3.86x) |
| Any Empty WKT JSON stringify | 91.46 | — | — | 915.48 (10.01x) | 893.32 (9.77x) |
| Any Empty WKT JSON parse | 344.63 | — | — | 2140.10 (6.21x) | 1244.43 (3.61x) |
| Any Struct WKT JSON stringify | 616.15 | — | — | 5801.32 (9.42x) | 7525.66 (12.21x) |
| Any Struct WKT JSON parse | 1750.98 | — | — | 11064.50 (6.32x) | 10714.61 (6.12x) |
| Any Struct Escape WKT JSON parse | 1779.42 | — | — | 11113.50 (6.25x) | 11161.53 (6.27x) |
| Any EmptyStruct WKT JSON stringify | 114.10 | — | — | 913.59 (8.01x) | 1419.84 (12.44x) |
| Any EmptyStruct WKT JSON parse | 443.25 | — | — | 2221.38 (5.01x) | 2384.83 (5.38x) |
| Any Value WKT JSON stringify | 651.23 | — | — | 5865.24 (9.01x) | 8718.02 (13.39x) |
| Any Value WKT JSON parse | 1810.00 | — | — | 11242.10 (6.21x) | 11166.81 (6.17x) |
| Any Value Escape WKT JSON parse | 1834.22 | — | — | 11474.60 (6.26x) | 10979.89 (5.99x) |
| Any NullValue WKT JSON stringify | 127.79 | — | — | 2244.00 (17.56x) | 1413.71 (11.06x) |
| Any NullValue WKT JSON parse | 466.12 | — | — | 4044.24 (8.68x) | 2029.81 (4.35x) |
| Any StringScalarValue WKT JSON stringify | 152.78 | — | — | 2260.04 (14.79x) | 1786.23 (11.69x) |
| Any StringScalarValue WKT JSON parse | 520.71 | — | — | 3636.58 (6.98x) | 1928.15 (3.70x) |
| Any EmptyStringScalarValue WKT JSON stringify | 137.94 | — | — | 2273.22 (16.48x) | 993.98 (7.21x) |
| Any EmptyStringScalarValue WKT JSON parse | 492.52 | — | — | 3644.30 (7.40x) | 1755.54 (3.56x) |
| Any NumberValue WKT JSON stringify | 175.16 | — | — | 2522.75 (14.40x) | 1140.52 (6.51x) |
| Any NumberValue WKT JSON parse | 506.62 | — | — | 3709.57 (7.32x) | 2156.27 (4.26x) |
| Any ZeroNumberValue WKT JSON stringify | 152.02 | — | — | 2470.78 (16.25x) | 904.33 (5.95x) |
| Any ZeroNumberValue WKT JSON parse | 501.95 | — | — | 3654.73 (7.28x) | 2542.85 (5.07x) |
| Any BoolScalarValue WKT JSON stringify | 127.17 | — | — | 2244.37 (17.65x) | 968.32 (7.61x) |
| Any BoolScalarValue WKT JSON parse | 465.35 | — | — | 3614.93 (7.77x) | 1911.91 (4.11x) |
| Any FalseBoolScalarValue WKT JSON stringify | 129.18 | — | — | 2245.24 (17.38x) | 882.07 (6.83x) |
| Any FalseBoolScalarValue WKT JSON parse | 465.75 | — | — | 3603.12 (7.74x) | 1784.95 (3.83x) |
| Any ListKindValue WKT JSON stringify | 504.19 | — | — | 5550.31 (11.01x) | 4972.35 (9.86x) |
| Any ListKindValue WKT JSON parse | 1390.19 | — | — | 9858.25 (7.09x) | 8474.02 (6.10x) |
| Any EmptyStructKindValue WKT JSON stringify | 144.21 | — | — | 2908.49 (20.17x) | 1437.23 (9.97x) |
| Any EmptyStructKindValue WKT JSON parse | 501.62 | — | — | 5381.38 (10.73x) | 1970.49 (3.93x) |
| Any EmptyListKindValue WKT JSON stringify | 151.38 | — | — | 2894.30 (19.12x) | 1217.59 (8.04x) |
| Any EmptyListKindValue WKT JSON parse | 507.26 | — | — | 4386.45 (8.65x) | 2109.95 (4.16x) |
| Any DoubleValue WKT JSON stringify | 188.66 | — | — | 1831.95 (9.71x) | 1418.67 (7.52x) |
| Any DoubleValue WKT JSON parse | 521.62 | — | — | 2749.23 (5.27x) | 1447.74 (2.78x) |
| Any DoubleValue String WKT JSON parse | 532.10 | — | — | 2739.16 (5.15x) | 1860.46 (3.50x) |
| Any NegativeDoubleValue WKT JSON stringify | 188.95 | — | — | 1808.63 (9.57x) | 782.75 (4.14x) |
| Any NegativeDoubleValue WKT JSON parse | 525.54 | — | — | 2738.25 (5.21x) | 2411.76 (4.59x) |
| Any ZeroDoubleValue WKT JSON stringify | 154.93 | — | — | 928.19 (5.99x) | 745.42 (4.81x) |
| Any ZeroDoubleValue WKT JSON parse | 518.35 | — | — | 2174.72 (4.20x) | 1332.32 (2.57x) |
| Any DoubleValue NaN WKT JSON stringify | 151.31 | — | — | 1580.69 (10.45x) | 762.62 (5.04x) |
| Any DoubleValue NaN WKT JSON parse | 516.23 | — | — | 2650.80 (5.13x) | 1973.73 (3.82x) |
| Any DoubleValue Infinity WKT JSON stringify | 154.90 | — | — | 1569.74 (10.13x) | 1265.98 (8.17x) |
| Any DoubleValue Infinity WKT JSON parse | 519.52 | — | — | 2690.85 (5.18x) | 1636.11 (3.15x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 157.09 | — | — | 1589.43 (10.12x) | 1064.27 (6.77x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 522.51 | — | — | 2675.33 (5.12x) | 1641.14 (3.14x) |
| Any FloatValue WKT JSON stringify | 193.07 | — | — | 1736.34 (8.99x) | 1626.24 (8.42x) |
| Any FloatValue WKT JSON parse | 521.21 | — | — | 2712.15 (5.20x) | 1358.10 (2.61x) |
| Any FloatValue String WKT JSON parse | 530.40 | — | — | 2712.16 (5.11x) | 1994.92 (3.76x) |
| Any NegativeFloatValue WKT JSON stringify | 193.77 | — | — | 1738.20 (8.97x) | 822.13 (4.24x) |
| Any NegativeFloatValue WKT JSON parse | 522.81 | — | — | 2710.91 (5.19x) | 1518.65 (2.90x) |
| Any ZeroFloatValue WKT JSON stringify | 161.24 | — | — | 921.26 (5.71x) | 1620.73 (10.05x) |
| Any ZeroFloatValue WKT JSON parse | 516.53 | — | — | 2158.52 (4.18x) | 1381.76 (2.68x) |
| Any FloatValue NaN WKT JSON stringify | 153.82 | — | — | 1572.61 (10.22x) | 758.63 (4.93x) |
| Any FloatValue NaN WKT JSON parse | 517.43 | — | — | 2623.44 (5.07x) | 1925.61 (3.72x) |
| Any FloatValue Infinity WKT JSON stringify | 158.79 | — | — | 1558.58 (9.82x) | 1192.91 (7.51x) |
| Any FloatValue Infinity WKT JSON parse | 522.67 | — | — | 2682.09 (5.13x) | 1386.11 (2.65x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 161.40 | — | — | 1537.98 (9.53x) | 714.63 (4.43x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 524.97 | — | — | 2643.87 (5.04x) | 1870.33 (3.56x) |
| Any Int64Value WKT JSON stringify | 166.49 | — | — | 1581.96 (9.50x) | 1528.92 (9.18x) |
| Any Int64Value WKT JSON parse | 556.26 | — | — | 2786.72 (5.01x) | 1726.58 (3.10x) |
| Any Int64Value Number WKT JSON parse | 556.62 | — | — | 2744.25 (4.93x) | 1609.83 (2.89x) |
| Any ZeroInt64Value WKT JSON stringify | 153.29 | — | — | 914.78 (5.97x) | 976.70 (6.37x) |
| Any ZeroInt64Value WKT JSON parse | 527.43 | — | — | 2147.11 (4.07x) | 1631.26 (3.09x) |
| Any NegativeInt64Value WKT JSON stringify | 164.66 | — | — | 1574.79 (9.56x) | 1248.34 (7.58x) |
| Any NegativeInt64Value WKT JSON parse | 559.57 | — | — | 2806.43 (5.02x) | 1708.65 (3.05x) |
| Any MinInt64Value WKT JSON stringify | 173.35 | — | — | 1581.19 (9.12x) | 1175.36 (6.78x) |
| Any MinInt64Value WKT JSON parse | 563.20 | — | — | 2827.93 (5.02x) | 2574.76 (4.57x) |
| Any MaxInt64Value WKT JSON stringify | 165.11 | — | — | 1585.94 (9.61x) | 1683.23 (10.19x) |
| Any MaxInt64Value WKT JSON parse | 561.38 | — | — | 2811.41 (5.01x) | 2028.04 (3.61x) |
| Any UInt64Value WKT JSON stringify | 171.62 | — | — | 1576.83 (9.19x) | 1231.43 (7.18x) |
| Any UInt64Value WKT JSON parse | 557.84 | — | — | 2788.27 (5.00x) | 1972.61 (3.54x) |
| Any UInt64Value Number WKT JSON parse | 560.78 | — | — | 2760.86 (4.92x) | 2124.47 (3.79x) |
| Any ZeroUInt64Value WKT JSON stringify | 160.59 | — | — | 928.53 (5.78x) | 1114.38 (6.94x) |
| Any ZeroUInt64Value WKT JSON parse | 532.49 | — | — | 2163.08 (4.06x) | 1942.73 (3.65x) |
| Any MaxUInt64Value WKT JSON stringify | 173.93 | — | — | 1583.26 (9.10x) | 1021.29 (5.87x) |
| Any MaxUInt64Value WKT JSON parse | 564.20 | — | — | 2832.71 (5.02x) | 2029.75 (3.60x) |
| Any Int32Value WKT JSON stringify | 161.44 | — | — | 1555.34 (9.63x) | 1306.31 (8.09x) |
| Any Int32Value WKT JSON parse | 540.57 | — | — | 2658.42 (4.92x) | 2052.92 (3.80x) |
| Any Int32Value String WKT JSON parse | 545.46 | — | — | 2659.06 (4.87x) | 2094.36 (3.84x) |
| Any ZeroInt32Value WKT JSON stringify | 162.34 | — | — | 919.49 (5.66x) | 1409.61 (8.68x) |
| Any ZeroInt32Value WKT JSON parse | 532.04 | — | — | 2149.50 (4.04x) | 1333.84 (2.51x) |
| Any NegativeInt32Value WKT JSON stringify | 167.93 | — | — | 1555.46 (9.26x) | 1582.80 (9.43x) |
| Any NegativeInt32Value WKT JSON parse | 542.05 | — | — | 2697.14 (4.98x) | 1574.30 (2.90x) |
| Any MinInt32Value WKT JSON stringify | 172.95 | — | — | 1556.20 (9.00x) | 1280.21 (7.40x) |
| Any MinInt32Value WKT JSON parse | 545.56 | — | — | 2708.85 (4.97x) | 1431.68 (2.62x) |
| Any MaxInt32Value WKT JSON stringify | 171.41 | — | — | 1553.50 (9.06x) | 831.96 (4.85x) |
| Any MaxInt32Value WKT JSON parse | 545.58 | — | — | 2675.58 (4.90x) | 1713.49 (3.14x) |
| Any UInt32Value WKT JSON stringify | 173.19 | — | — | 1549.26 (8.95x) | 1313.38 (7.58x) |
| Any UInt32Value WKT JSON parse | 543.10 | — | — | 2662.52 (4.90x) | 2191.41 (4.04x) |
| Any UInt32Value String WKT JSON parse | 551.84 | — | — | 2662.38 (4.82x) | 1454.66 (2.64x) |
| Any ZeroUInt32Value WKT JSON stringify | 169.34 | — | — | 918.01 (5.42x) | 1040.14 (6.14x) |
| Any ZeroUInt32Value WKT JSON parse | 536.00 | — | — | 2152.55 (4.02x) | 1679.69 (3.13x) |
| Any MaxUInt32Value WKT JSON stringify | 176.69 | — | — | 1554.82 (8.80x) | 787.91 (4.46x) |
| Any MaxUInt32Value WKT JSON parse | 553.04 | — | — | 2693.07 (4.87x) | 1542.29 (2.79x) |
| Any BoolValue WKT JSON stringify | 166.45 | — | — | 1519.14 (9.13x) | 1637.21 (9.84x) |
| Any BoolValue WKT JSON parse | 496.70 | — | — | 2594.53 (5.22x) | 1406.64 (2.83x) |
| Any FalseBoolValue WKT JSON stringify | 168.92 | — | — | 915.29 (5.42x) | 686.31 (4.06x) |
| Any FalseBoolValue WKT JSON parse | 495.52 | — | — | 2139.74 (4.32x) | 1397.65 (2.82x) |
| Any StringValue WKT JSON stringify | 196.97 | — | — | 1559.69 (7.92x) | 995.90 (5.06x) |
| Any StringValue WKT JSON parse | 557.19 | — | — | 2656.82 (4.77x) | 2039.92 (3.66x) |
| Any StringValue Escape WKT JSON parse | 563.55 | — | — | 2675.44 (4.75x) | 1503.68 (2.67x) |
| Any EmptyStringValue WKT JSON stringify | 185.47 | — | — | 914.69 (4.93x) | 850.85 (4.59x) |
| Any EmptyStringValue WKT JSON parse | 525.51 | — | — | 2159.42 (4.11x) | 1603.32 (3.05x) |
| Any BytesValue WKT JSON stringify | 182.11 | — | — | 1579.89 (8.68x) | 946.30 (5.20x) |
| Any BytesValue WKT JSON parse | 573.10 | — | — | 2691.68 (4.70x) | 1761.40 (3.07x) |
| Any BytesValue URL WKT JSON parse | 591.99 | — | — | 2671.33 (4.51x) | 1934.98 (3.27x) |
| Any EmptyBytesValue WKT JSON stringify | 172.02 | — | — | 913.05 (5.31x) | 1487.85 (8.65x) |
| Any EmptyBytesValue WKT JSON parse | 541.19 | — | — | 2151.67 (3.98x) | 1742.05 (3.22x) |
| Nested Any WKT JSON stringify | 291.91 | — | — | 2745.04 (9.40x) | 2075.28 (7.11x) |
| Nested Any WKT JSON parse | 881.65 | — | — | 4251.96 (4.82x) | 3268.37 (3.71x) |
| Duration JSON stringify | 58.25 | — | — | 956.72 (16.42x) | 472.81 (8.12x) |
| Duration JSON parse | 20.09 | — | — | 1462.34 (72.79x) | 481.98 (23.99x) |
| Duration Escape JSON parse | 39.98 | — | — | 1480.35 (37.03x) | 415.50 (10.39x) |
| PlusDuration JSON parse | 18.23 | — | — | 1461.98 (80.20x) | 404.00 (22.16x) |
| ShortFractionDuration JSON parse | 15.40 | — | — | 1427.39 (92.69x) | 399.26 (25.93x) |
| MicroDuration JSON stringify | 59.81 | — | — | 978.21 (16.36x) | 382.16 (6.39x) |
| MicroDuration JSON parse | 18.99 | — | — | 1466.88 (77.24x) | 515.61 (27.15x) |
| NanoDuration JSON stringify | 59.17 | — | — | 999.24 (16.89x) | 374.35 (6.33x) |
| NanoDuration JSON parse | 21.88 | — | — | 1483.87 (67.82x) | 733.35 (33.52x) |
| NegativeDuration JSON stringify | 61.61 | — | — | 1015.51 (16.48x) | 579.51 (9.41x) |
| NegativeDuration JSON parse | 19.94 | — | — | 1510.74 (75.76x) | 722.04 (36.21x) |
| FractionalNegativeDuration JSON stringify | 60.42 | — | — | 972.84 (16.10x) | 451.29 (7.47x) |
| FractionalNegativeDuration JSON parse | 18.72 | — | — | 1473.94 (78.74x) | 417.90 (22.32x) |
| MaxDuration JSON stringify | 50.20 | — | — | 868.81 (17.31x) | 391.23 (7.79x) |
| MaxDuration JSON parse | 31.18 | — | — | 1434.43 (46.00x) | 381.56 (12.24x) |
| MinDuration JSON stringify | 50.03 | — | — | 891.89 (17.83x) | 770.65 (15.40x) |
| MinDuration JSON parse | 32.15 | — | — | 1454.38 (45.24x) | 798.31 (24.83x) |
| ZeroDuration JSON stringify | 44.87 | — | — | 818.70 (18.25x) | 337.58 (7.52x) |
| ZeroDuration JSON parse | 13.55 | — | — | 1371.07 (101.19x) | 323.71 (23.89x) |
| FieldMask JSON stringify | 67.08 | — | — | 882.45 (13.16x) | 640.29 (9.55x) |
| FieldMask JSON parse | 141.68 | — | — | 1655.40 (11.68x) | 1596.87 (11.27x) |
| FieldMask Escape JSON parse | 188.23 | — | — | 1707.55 (9.07x) | 1203.77 (6.40x) |
| EmptyFieldMask JSON stringify | 40.90 | — | — | 607.12 (14.84x) | 188.31 (4.60x) |
| EmptyFieldMask JSON parse | 4.80 | — | — | 941.70 (196.19x) | 306.74 (63.90x) |
| Timestamp JSON stringify | 96.14 | — | — | 1147.06 (11.93x) | 648.84 (6.75x) |
| Timestamp JSON parse | 45.31 | — | — | 1513.38 (33.40x) | 626.33 (13.82x) |
| Timestamp Escape JSON parse | 96.97 | — | — | 1522.34 (15.70x) | 570.69 (5.89x) |
| ShortFraction Timestamp JSON parse | 43.47 | — | — | 1496.35 (34.42x) | 420.28 (9.67x) |
| Micro Timestamp JSON stringify | 96.35 | — | — | 1164.48 (12.09x) | 417.77 (4.34x) |
| Micro Timestamp JSON parse | 47.13 | — | — | 1520.18 (32.26x) | 435.96 (9.25x) |
| Nano Timestamp JSON stringify | 94.32 | — | — | 1199.99 (12.72x) | 418.29 (4.43x) |
| Nano Timestamp JSON parse | 51.89 | — | — | 1533.71 (29.56x) | 441.83 (8.51x) |
| Offset Timestamp JSON parse | 51.32 | — | — | 1541.15 (30.03x) | 456.25 (8.89x) |
| PreEpoch Timestamp JSON stringify | 66.90 | — | — | 1080.02 (16.14x) | 412.74 (6.17x) |
| PreEpoch Timestamp JSON parse | 43.10 | — | — | 1474.46 (34.21x) | 434.82 (10.09x) |
| Max Timestamp JSON stringify | 79.61 | — | — | 1215.37 (15.27x) | 560.10 (7.04x) |
| Max Timestamp JSON parse | 51.50 | — | — | 1557.36 (30.24x) | 478.13 (9.28x) |
| Min Timestamp JSON stringify | 79.62 | — | — | 1066.66 (13.40x) | 477.19 (5.99x) |
| Min Timestamp JSON parse | 41.11 | — | — | 1470.45 (35.77x) | 415.83 (10.12x) |
| Empty JSON stringify | 20.91 | — | — | 493.56 (23.60x) | 217.53 (10.40x) |
| Empty JSON parse | 73.20 | — | — | 718.35 (9.81x) | 513.18 (7.01x) |
| Struct JSON stringify | 175.92 | — | — | 5721.98 (32.53x) | 4187.04 (23.80x) |
| Struct JSON parse | 855.03 | — | — | 10899.60 (12.75x) | 4894.27 (5.72x) |
| Struct Escape JSON parse | 897.83 | — | — | 10945.80 (12.19x) | 6269.97 (6.98x) |
| EmptyStruct JSON stringify | 41.42 | — | — | 698.91 (16.87x) | 459.08 (11.08x) |
| EmptyStruct JSON parse | 90.43 | — | — | 2018.19 (22.32x) | 538.07 (5.95x) |
| Value JSON stringify | 181.37 | — | — | 6559.57 (36.17x) | 3778.24 (20.83x) |
| Value JSON parse | 897.64 | — | — | 12100.20 (13.48x) | 6416.73 (7.15x) |
| Value Escape JSON parse | 945.73 | — | — | 12183.10 (12.88x) | 7028.02 (7.43x) |
| NullValue JSON stringify | 54.57 | — | — | 1335.67 (24.48x) | 612.31 (11.22x) |
| NullValue JSON parse | 84.39 | — | — | 2467.01 (29.23x) | 522.51 (6.19x) |
| StringScalarValue JSON stringify | 71.77 | — | — | 1340.50 (18.68x) | 278.76 (3.88x) |
| StringScalarValue JSON parse | 170.30 | — | — | 2089.17 (12.27x) | 523.21 (3.07x) |
| EmptyStringScalarValue JSON stringify | 65.27 | — | — | 1332.89 (20.42x) | 279.05 (4.28x) |
| EmptyStringScalarValue JSON parse | 105.04 | — | — | 2069.58 (19.70x) | 395.09 (3.76x) |
| NumberValue JSON stringify | 141.85 | — | — | 1547.75 (10.91x) | 518.87 (3.66x) |
| NumberValue JSON parse | 163.71 | — | — | 2167.47 (13.24x) | 433.19 (2.65x) |
| ZeroNumberValue JSON stringify | 83.47 | — | — | 1501.95 (17.99x) | 284.92 (3.41x) |
| ZeroNumberValue JSON parse | 139.68 | — | — | 2114.38 (15.14x) | 364.54 (2.61x) |
| BoolScalarValue JSON stringify | 43.28 | — | — | 1313.47 (30.35x) | 415.82 (9.61x) |
| BoolScalarValue JSON parse | 82.88 | — | — | 2015.63 (24.32x) | 792.50 (9.56x) |
| FalseBoolScalarValue JSON stringify | 54.21 | — | — | 1312.68 (24.21x) | 617.58 (11.39x) |
| FalseBoolScalarValue JSON parse | 83.94 | — | — | 2014.15 (24.00x) | 753.20 (8.97x) |
| ListKindValue JSON stringify | 213.68 | — | — | 6076.04 (28.44x) | 2296.13 (10.75x) |
| ListKindValue JSON parse | 818.74 | — | — | 10381.30 (12.68x) | 4825.56 (5.89x) |
| EmptyStructKindValue JSON stringify | 43.07 | — | — | 1951.95 (45.32x) | 742.50 (17.24x) |
| EmptyStructKindValue JSON parse | 113.57 | — | — | 3753.06 (33.05x) | 1155.71 (10.18x) |
| EmptyListKindValue JSON stringify | 41.82 | — | — | 1941.48 (46.42x) | 370.09 (8.85x) |
| EmptyListKindValue JSON parse | 158.00 | — | — | 4033.88 (25.53x) | 617.37 (3.91x) |
| ListValue JSON stringify | 147.51 | — | — | 4820.16 (32.68x) | 2503.03 (16.97x) |
| ListValue JSON parse | 706.00 | — | — | 8564.56 (12.13x) | 4810.95 (6.81x) |
| EmptyListValue JSON stringify | 42.47 | — | — | 687.86 (16.20x) | 183.54 (4.32x) |
| EmptyListValue JSON parse | 145.82 | — | — | 2260.34 (15.50x) | 652.95 (4.48x) |
| DoubleValue JSON stringify | 67.46 | — | — | 868.79 (12.88x) | 323.74 (4.80x) |
| DoubleValue JSON parse | 111.60 | — | — | 1224.48 (10.97x) | 276.65 (2.48x) |
| DoubleValue String JSON parse | 112.08 | — | — | 1164.38 (10.39x) | 572.80 (5.11x) |
| NegativeDoubleValue JSON stringify | 67.85 | — | — | 868.51 (12.80x) | 192.10 (2.83x) |
| NegativeDoubleValue JSON parse | 112.05 | — | — | 1225.36 (10.94x) | 260.92 (2.33x) |
| ZeroDoubleValue JSON stringify | 47.72 | — | — | 808.10 (16.93x) | 355.70 (7.45x) |
| ZeroDoubleValue JSON parse | 108.47 | — | — | 1161.47 (10.71x) | 592.44 (5.46x) |
| DoubleValue NaN JSON stringify | 46.78 | — | — | 671.94 (14.36x) | 131.93 (2.82x) |
| DoubleValue NaN JSON parse | 104.76 | — | — | 1619.20 (15.46x) | 260.29 (2.48x) |
| DoubleValue Infinity JSON stringify | 48.52 | — | — | 672.26 (13.86x) | 226.80 (4.67x) |
| DoubleValue Infinity JSON parse | 106.20 | — | — | 1108.26 (10.44x) | 433.81 (4.08x) |
| DoubleValue NegativeInfinity JSON stringify | 48.41 | — | — | 670.62 (13.85x) | 185.64 (3.83x) |
| DoubleValue NegativeInfinity JSON parse | 108.15 | — | — | 1109.31 (10.26x) | 465.22 (4.30x) |
| FloatValue JSON stringify | 72.39 | — | — | 798.17 (11.03x) | 221.79 (3.06x) |
| FloatValue JSON parse | 111.63 | — | — | 1326.74 (11.89x) | 408.24 (3.66x) |
| FloatValue String JSON parse | 116.54 | — | — | 1181.77 (10.14x) | 672.10 (5.77x) |
| NegativeFloatValue JSON stringify | 70.53 | — | — | 823.16 (11.67x) | 196.24 (2.78x) |
| NegativeFloatValue JSON parse | 111.00 | — | — | 1237.57 (11.15x) | 365.47 (3.29x) |
| ZeroFloatValue JSON stringify | 47.64 | — | — | 748.76 (15.72x) | 131.84 (2.77x) |
| ZeroFloatValue JSON parse | 107.56 | — | — | 1147.79 (10.67x) | 313.83 (2.92x) |
| FloatValue NaN JSON stringify | 46.37 | — | — | 645.22 (13.91x) | 180.46 (3.89x) |
| FloatValue NaN JSON parse | 110.92 | — | — | 1082.72 (9.76x) | 261.23 (2.36x) |
| FloatValue Infinity JSON stringify | 48.10 | — | — | 647.92 (13.47x) | 144.88 (3.01x) |
| FloatValue Infinity JSON parse | 112.38 | — | — | 1101.53 (9.80x) | 345.06 (3.07x) |
| FloatValue NegativeInfinity JSON stringify | 48.32 | — | — | 640.69 (13.26x) | 201.42 (4.17x) |
| FloatValue NegativeInfinity JSON parse | 114.39 | — | — | 1107.47 (9.68x) | 286.87 (2.51x) |
| Int64Value JSON stringify | 50.23 | — | — | 681.18 (13.56x) | 326.93 (6.51x) |
| Int64Value JSON parse | 131.25 | — | — | 1228.03 (9.36x) | 524.36 (4.00x) |
| Int64Value Number JSON parse | 127.19 | — | — | 1286.07 (10.11x) | 633.17 (4.98x) |
| ZeroInt64Value JSON stringify | 41.66 | — | — | 615.03 (14.76x) | 238.29 (5.72x) |
| ZeroInt64Value JSON parse | 112.10 | — | — | 1102.43 (9.83x) | 703.70 (6.28x) |
| NegativeInt64Value JSON stringify | 50.12 | — | — | 674.37 (13.46x) | 265.15 (5.29x) |
| NegativeInt64Value JSON parse | 132.90 | — | — | 1214.41 (9.14x) | 450.62 (3.39x) |
| MinInt64Value JSON stringify | 52.52 | — | — | 675.26 (12.86x) | 267.08 (5.09x) |
| MinInt64Value JSON parse | 140.00 | — | — | 1246.76 (8.91x) | 540.92 (3.86x) |
| MaxInt64Value JSON stringify | 52.56 | — | — | 676.35 (12.87x) | 272.01 (5.18x) |
| MaxInt64Value JSON parse | 138.87 | — | — | 1249.62 (9.00x) | 891.84 (6.42x) |
| UInt64Value JSON stringify | 50.54 | — | — | 676.61 (13.39x) | 252.34 (4.99x) |
| UInt64Value JSON parse | 129.79 | — | — | 1214.30 (9.36x) | 526.53 (4.06x) |
| UInt64Value Number JSON parse | 126.55 | — | — | 1275.29 (10.08x) | 726.62 (5.74x) |
| ZeroUInt64Value JSON stringify | 44.86 | — | — | 611.07 (13.62x) | 187.43 (4.18x) |
| ZeroUInt64Value JSON parse | 110.38 | — | — | 1092.07 (9.89x) | 313.46 (2.84x) |
| MaxUInt64Value JSON stringify | 50.70 | — | — | 678.25 (13.38x) | 304.85 (6.01x) |
| MaxUInt64Value JSON parse | 140.09 | — | — | 1243.48 (8.88x) | 887.14 (6.33x) |
| Int32Value JSON stringify | 46.31 | — | — | 634.97 (13.71x) | 129.08 (2.79x) |
| Int32Value JSON parse | 117.51 | — | — | 1188.25 (10.11x) | 299.32 (2.55x) |
| Int32Value String JSON parse | 121.10 | — | — | 1136.50 (9.38x) | 383.16 (3.16x) |
| ZeroInt32Value JSON stringify | 46.20 | — | — | 619.49 (13.41x) | 125.28 (2.71x) |
| ZeroInt32Value JSON parse | 113.16 | — | — | 1159.77 (10.25x) | 397.16 (3.51x) |
| NegativeInt32Value JSON stringify | 46.21 | — | — | 645.48 (13.97x) | 296.93 (6.43x) |
| NegativeInt32Value JSON parse | 116.66 | — | — | 1194.81 (10.24x) | 753.48 (6.46x) |
| MinInt32Value JSON stringify | 47.05 | — | — | 640.96 (13.62x) | 131.07 (2.79x) |
| MinInt32Value JSON parse | 122.64 | — | — | 1206.66 (9.84x) | 345.67 (2.82x) |
| MaxInt32Value JSON stringify | 47.05 | — | — | 637.74 (13.55x) | 141.93 (3.02x) |
| MaxInt32Value JSON parse | 123.16 | — | — | 1212.56 (9.85x) | 348.10 (2.83x) |
| UInt32Value JSON stringify | 46.27 | — | — | 647.53 (13.99x) | 235.91 (5.10x) |
| UInt32Value JSON parse | 117.29 | — | — | 1184.99 (10.10x) | 703.42 (6.00x) |
| UInt32Value String JSON parse | 121.30 | — | — | 1127.38 (9.29x) | 678.73 (5.60x) |
| ZeroUInt32Value JSON stringify | 46.35 | — | — | 629.96 (13.59x) | 125.93 (2.72x) |
| ZeroUInt32Value JSON parse | 112.84 | — | — | 1151.36 (10.20x) | 508.20 (4.50x) |
| MaxUInt32Value JSON stringify | 47.31 | — | — | 645.45 (13.64x) | 194.01 (4.10x) |
| MaxUInt32Value JSON parse | 123.58 | — | — | 1202.74 (9.73x) | 787.57 (6.37x) |
| BoolValue JSON stringify | 45.81 | — | — | 613.32 (13.39x) | 142.39 (3.11x) |
| BoolValue JSON parse | 59.66 | — | — | 1062.00 (17.80x) | 490.01 (8.21x) |
| FalseBoolValue JSON stringify | 45.45 | — | — | 601.97 (13.24x) | 207.10 (4.56x) |
| FalseBoolValue JSON parse | 60.14 | — | — | 1063.19 (17.68x) | 560.65 (9.32x) |
| StringValue JSON stringify | 51.91 | — | — | 675.31 (13.01x) | 453.48 (8.74x) |
| StringValue JSON parse | 123.58 | — | — | 1141.37 (9.24x) | 324.41 (2.63x) |
| StringValue Escape JSON parse | 132.07 | — | — | 1170.40 (8.86x) | 338.46 (2.56x) |
| EmptyStringValue JSON stringify | 49.06 | — | — | 639.78 (13.04x) | 174.15 (3.55x) |
| EmptyStringValue JSON parse | 66.40 | — | — | 1123.85 (16.93x) | 301.86 (4.55x) |
| BytesValue JSON stringify | 49.62 | — | — | 658.07 (13.26x) | 195.49 (3.94x) |
| BytesValue JSON parse | 125.78 | — | — | 1169.29 (9.30x) | 324.14 (2.58x) |
| BytesValue URL JSON parse | 142.39 | — | — | 1157.95 (8.13x) | 543.35 (3.82x) |
| EmptyBytesValue JSON stringify | 41.45 | — | — | 633.67 (15.29x) | 369.41 (8.91x) |
| EmptyBytesValue JSON parse | 70.60 | — | — | 1130.53 (16.01x) | 731.15 (10.36x) |
| TextFormat format | 176.80 | — | — | 2572.31 (14.55x) | 3327.58 (18.82x) |
| TextFormat parse | 711.71 | — | — | 4996.76 (7.02x) | 6826.79 (9.59x) |
| packed fixed32 encode | 2.01 | 548.74 (273.00x) | 539.83 (268.57x) | 43.90 (21.84x) | 392.04 (195.04x) |
| packed fixed32 decode | 4.54 | 1055.10 (232.40x) | 1873.69 (412.71x) | 49.92 (11.00x) | 1776.46 (391.29x) |
| packed fixed64 encode | 2.01 | 575.88 (286.51x) | 561.01 (279.11x) | 75.83 (37.73x) | 408.65 (203.31x) |
| packed fixed64 decode | 4.54 | 1061.26 (233.76x) | 7941.51 (1749.23x) | 80.09 (17.64x) | 6151.45 (1354.94x) |
| packed sfixed32 encode | 2.01 | 554.65 (275.95x) | 542.67 (269.99x) | 43.79 (21.78x) | 409.94 (203.95x) |
| packed sfixed32 decode | 4.52 | 1084.01 (239.83x) | 2010.78 (444.86x) | 49.24 (10.89x) | 1650.37 (365.13x) |
| packed sfixed64 encode | 2.01 | 577.07 (287.10x) | 565.06 (281.12x) | 76.00 (37.81x) | 420.40 (209.15x) |
| packed sfixed64 decode | 4.52 | 1059.22 (234.34x) | 7900.88 (1747.98x) | 79.52 (17.59x) | 2566.39 (567.79x) |
| packed float encode | 2.00 | 811.70 (405.85x) | 539.43 (269.71x) | 44.16 (22.08x) | 403.80 (201.90x) |
| packed float decode | 4.54 | 1038.54 (228.75x) | 2070.62 (456.08x) | 49.10 (10.81x) | 1640.06 (361.25x) |
| packed double encode | 2.39 | 831.41 (347.87x) | 561.19 (234.81x) | 75.71 (31.68x) | 375.03 (156.92x) |
| packed double decode | 4.56 | 991.51 (217.44x) | 2046.21 (448.73x) | 79.81 (17.50x) | 6535.50 (1433.22x) |
| packed uint64 encode | 1516.60 | 4612.06 (3.04x) | 4008.48 (2.64x) | 2134.07 (1.41x) | 3439.67 (2.27x) |
| packed uint64 decode | 1816.20 | 2783.56 (1.53x) | 8855.68 (4.88x) | 2801.65 (1.54x) | 12573.75 (6.92x) |
| packed uint32 encode | 1364.08 | 3640.37 (2.67x) | 3266.02 (2.39x) | 1756.45 (1.29x) | 2883.21 (2.11x) |
| packed uint32 decode | 1357.93 | 2434.51 (1.79x) | 3270.55 (2.41x) | 1993.31 (1.47x) | 9750.96 (7.18x) |
| packed int64 encode | 1396.96 | 11036.08 (7.90x) | 6209.97 (4.45x) | 2918.20 (2.09x) | 4111.92 (2.94x) |
| packed int64 decode | 2756.01 | 3392.51 (1.23x) | 10320.76 (3.74x) | 4613.72 (1.67x) | 16489.17 (5.98x) |
| packed sint32 encode | 880.63 | 3046.94 (3.46x) | 2837.75 (3.22x) | 1533.12 (1.74x) | 3379.32 (3.84x) |
| packed sint32 decode | 953.11 | 2546.56 (2.67x) | 3191.17 (3.35x) | 1131.73 (1.19x) | 5070.05 (5.32x) |
| packed sint64 encode | 1434.74 | 4931.36 (3.44x) | 4282.36 (2.98x) | 2398.07 (1.67x) | 4279.99 (2.98x) |
| packed sint64 decode | 2037.09 | 3057.86 (1.50x) | 9648.87 (4.74x) | 2932.65 (1.44x) | 11419.45 (5.61x) |
| packed bool encode | 2.01 | 1330.93 (662.15x) | 517.97 (257.70x) | 15.67 (7.80x) | 2246.41 (1117.62x) |
| packed bool decode | 262.79 | 1539.24 (5.86x) | 2560.21 (9.74x) | 805.03 (3.06x) | 1658.87 (6.31x) |
| packed enum encode | 275.75 | 2708.18 (9.82x) | 1803.76 (6.54x) | 1085.35 (3.94x) | 2485.83 (9.01x) |
| packed enum decode | 160.63 | 1539.51 (9.58x) | 2837.27 (17.66x) | 694.41 (4.32x) | 3110.17 (19.36x) |
| large map encode | 4029.73 | 16368.48 (4.06x) | 9741.43 (2.42x) | 21473.20 (5.33x) | 210806.11 (52.31x) |
| shuffled large map deterministic binary encode | 27844.44 | — | — | 88833.60 (3.19x) | 404263.12 (14.52x) |
| large map decode | 25405.12 | 90569.50 (3.57x) | 89236.39 (3.51x) | 94288.60 (3.71x) | 375683.75 (14.79x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound `Duration`, non-empty/escaped-input parse and empty `Struct`, object/escaped-object parse/list/scalar `Value` (including default-like scalar and empty object/list kinds),
`FieldMask` (non-empty, escaped JSON parse input, and empty), escaped-input parse/short-fraction parse/micro/nano/offset/min/pre/post/max-bound `Timestamp`, `Empty`, min/zero/positive/number-input parse/negative/max `Int64Value`, negative/zero/positive finite/string-input parse `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), negative/zero/positive finite/string-input parse `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), zero/normal/number-input parse/max `UInt64Value`, min/zero/positive/string-input parse/negative/max `Int32Value`, zero/normal/string-input parse/max `UInt32Value`, true/false `BoolValue`, non-empty/escape-input parse/empty `StringValue`, base64/base64url parse/empty `BytesValue`, and recursive nested `Any` payloads), direct zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound Duration, non-empty/escaped-input parse/empty FieldMask, and escaped-input parse/short-fraction parse/micro/nano/offset/min/pre/post/max-bound Timestamp WKT JSON plus other direct WKT JSON, including non-empty/escaped-input parse/empty `Struct`, object/escaped-object parse/list/scalar `Value`, and empty `ListValue`, TextFormat, packed scalars, large bytes,
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
