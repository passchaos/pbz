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

Latest accepted comparison (`/tmp/pbz-compare-number-wrapper-json-isolated.log`,
summarized in `/tmp/pbz-summary-number-wrapper-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 19.79 | 127.12 (6.42x) | 51.04 (2.58x) | 103.84 (5.25x) | 804.29 (40.64x) |
| binary decode | 85.26 | 265.85 (3.12x) | 232.91 (2.73x) | 233.43 (2.74x) | 890.41 (10.44x) |
| unknown fields count by number | 3.57 | — | — | 161.98 (45.37x) | — |
| deterministic binary encode | 50.34 | — | — | 127.78 (2.54x) | 1042.17 (20.70x) |
| scalarmix encode | 19.80 | 97.73 (4.94x) | 80.91 (4.09x) | 29.99 (1.51x) | 227.46 (11.49x) |
| scalarmix decode | 35.07 | 140.96 (4.02x) | 221.41 (6.31x) | 85.31 (2.43x) | 327.55 (9.34x) |
| textbytes encode | 11.53 | 88.21 (7.65x) | 34.26 (2.97x) | 117.83 (10.22x) | 147.71 (12.81x) |
| textbytes decode | 46.01 | 383.54 (8.34x) | 240.47 (5.23x) | 164.83 (3.58x) | 659.34 (14.33x) |
| largebytes encode | 31.84 | 2702.08 (84.86x) | 2717.95 (85.36x) | 2681.51 (84.22x) | 2780.29 (87.32x) |
| largebytes decode | 88.56 | 5594.62 (63.17x) | 3020.77 (34.11x) | 2728.24 (30.81x) | 24803.57 (280.08x) |
| presencemix encode | 17.21 | 57.85 (3.36x) | 26.15 (1.52x) | 55.96 (3.25x) | 232.78 (13.53x) |
| presencemix decode | 56.61 | 137.15 (2.42x) | 110.32 (1.95x) | 161.28 (2.85x) | 489.50 (8.65x) |
| complex encode | 51.30 | 139.43 (2.72x) | 125.55 (2.45x) | 159.05 (3.10x) | 918.22 (17.90x) |
| complex decode | 190.48 | 391.79 (2.06x) | 342.27 (1.80x) | 400.06 (2.10x) | 1369.48 (7.19x) |
| complex deterministic binary encode | 93.40 | — | — | 168.28 (1.80x) | 1099.13 (11.77x) |
| complex JSON stringify | 272.62 | — | — | 4866.71 (17.85x) | 6154.64 (22.58x) |
| complex JSON parse | 2428.18 | — | — | 11936.30 (4.92x) | 7238.28 (2.98x) |
| complex TextFormat format | 244.26 | — | — | 3774.19 (15.45x) | 5346.56 (21.89x) |
| complex TextFormat parse | 1884.48 | — | — | 6907.22 (3.67x) | 8471.97 (4.50x) |
| packed int32 encode | 634.16 | 3170.94 (5.00x) | 2521.24 (3.98x) | 1265.15 (2.00x) | 2747.78 (4.33x) |
| packed int32 decode | 690.20 | 1929.02 (2.79x) | 3237.36 (4.69x) | 972.49 (1.41x) | 3565.07 (5.17x) |
| JSON stringify | 157.27 | — | — | 3011.11 (19.15x) | 2125.22 (13.51x) |
| JSON parse | 1510.69 | — | — | 7611.36 (5.04x) | 4311.40 (2.85x) |
| Any WKT JSON stringify | 244.95 | — | — | 1878.36 (7.67x) | 937.51 (3.83x) |
| Any WKT JSON parse | 839.53 | — | — | 2980.22 (3.55x) | 1408.30 (1.68x) |
| Any PlusDuration WKT JSON parse | 630.62 | — | — | 3007.36 (4.77x) | 1482.14 (2.35x) |
| Any ShortFractionDuration WKT JSON parse | 614.56 | — | — | 2976.19 (4.84x) | 1737.66 (2.83x) |
| Any MicroDuration WKT JSON stringify | 132.19 | — | — | 1895.81 (14.34x) | 994.30 (7.52x) |
| Any MicroDuration WKT JSON parse | 518.46 | — | — | 3002.23 (5.79x) | 1507.63 (2.91x) |
| Any NanoDuration WKT JSON stringify | 131.55 | — | — | 1916.44 (14.57x) | 1092.87 (8.31x) |
| Any NanoDuration WKT JSON parse | 523.70 | — | — | 3009.17 (5.75x) | 1768.37 (3.38x) |
| Any NegativeDuration WKT JSON stringify | 130.31 | — | — | 1936.13 (14.86x) | 1031.57 (7.92x) |
| Any NegativeDuration WKT JSON parse | 525.62 | — | — | 3093.30 (5.89x) | 1654.41 (3.15x) |
| Any FractionalNegativeDuration WKT JSON stringify | 124.36 | — | — | 1889.70 (15.20x) | 1122.32 (9.02x) |
| Any FractionalNegativeDuration WKT JSON parse | 513.07 | — | — | 3074.96 (5.99x) | 1622.91 (3.16x) |
| Any MaxDuration WKT JSON stringify | 119.69 | — | — | 1749.47 (14.62x) | 984.59 (8.23x) |
| Any MaxDuration WKT JSON parse | 527.46 | — | — | 3011.32 (5.71x) | 1472.85 (2.79x) |
| Any MinDuration WKT JSON stringify | 119.54 | — | — | 1764.80 (14.76x) | 957.76 (8.01x) |
| Any MinDuration WKT JSON parse | 531.19 | — | — | 3037.48 (5.72x) | 1442.83 (2.72x) |
| Any ZeroDuration WKT JSON stringify | 105.94 | — | — | 912.04 (8.61x) | 1007.81 (9.51x) |
| Any ZeroDuration WKT JSON parse | 462.75 | — | — | 2253.33 (4.87x) | 1348.27 (2.91x) |
| Any FieldMask WKT JSON stringify | 233.14 | — | — | 1740.31 (7.46x) | 1390.74 (5.97x) |
| Any FieldMask WKT JSON parse | 712.05 | — | — | 3164.65 (4.44x) | 2057.20 (2.89x) |
| Any EmptyFieldMask WKT JSON stringify | 109.11 | — | — | 1358.64 (12.45x) | 761.12 (6.98x) |
| Any EmptyFieldMask WKT JSON parse | 438.41 | — | — | 3269.91 (7.46x) | 1267.56 (2.89x) |
| Any Timestamp WKT JSON stringify | 178.16 | — | — | 2041.80 (11.46x) | 1002.35 (5.63x) |
| Any Timestamp WKT JSON parse | 560.03 | — | — | 3030.82 (5.41x) | 1640.28 (2.93x) |
| Any Micro Timestamp WKT JSON stringify | 177.78 | — | — | 2025.57 (11.39x) | 996.92 (5.61x) |
| Any Micro Timestamp WKT JSON parse | 566.04 | — | — | 3026.15 (5.35x) | 1720.73 (3.04x) |
| Any Nano Timestamp WKT JSON stringify | 175.47 | — | — | 2028.39 (11.56x) | 1044.18 (5.95x) |
| Any Nano Timestamp WKT JSON parse | 571.19 | — | — | 3029.28 (5.30x) | 1543.24 (2.70x) |
| Any Offset Timestamp WKT JSON parse | 578.09 | — | — | 3032.29 (5.25x) | 1632.05 (2.82x) |
| Any PreEpoch Timestamp WKT JSON stringify | 142.96 | — | — | 1934.83 (13.53x) | 978.89 (6.85x) |
| Any PreEpoch Timestamp WKT JSON parse | 549.58 | — | — | 3042.42 (5.54x) | 1577.09 (2.87x) |
| Any Max Timestamp WKT JSON stringify | 162.38 | — | — | 2052.39 (12.64x) | 1103.97 (6.80x) |
| Any Max Timestamp WKT JSON parse | 570.74 | — | — | 3114.96 (5.46x) | 1739.60 (3.05x) |
| Any Min Timestamp WKT JSON stringify | 154.35 | — | — | 1947.94 (12.62x) | 1052.99 (6.82x) |
| Any Min Timestamp WKT JSON parse | 550.34 | — | — | 3063.90 (5.57x) | 1688.01 (3.07x) |
| Any Empty WKT JSON stringify | 89.62 | — | — | 922.34 (10.29x) | 701.71 (7.83x) |
| Any Empty WKT JSON parse | 329.27 | — | — | 2164.80 (6.57x) | 1340.15 (4.07x) |
| Any Struct WKT JSON stringify | 644.95 | — | — | 5868.09 (9.10x) | 6364.63 (9.87x) |
| Any Struct WKT JSON parse | 1734.55 | — | — | 11153.50 (6.43x) | 8602.69 (4.96x) |
| Any EmptyStruct WKT JSON stringify | 115.78 | — | — | 910.17 (7.86x) | 913.94 (7.89x) |
| Any EmptyStruct WKT JSON parse | 429.98 | — | — | 2223.38 (5.17x) | 1531.31 (3.56x) |
| Any Value WKT JSON stringify | 666.74 | — | — | 5893.39 (8.84x) | 6286.00 (9.43x) |
| Any Value WKT JSON parse | 1803.53 | — | — | 11365.90 (6.30x) | 9490.93 (5.26x) |
| Any NullValue WKT JSON stringify | 127.32 | — | — | 2247.63 (17.65x) | 958.55 (7.53x) |
| Any NullValue WKT JSON parse | 449.82 | — | — | 4037.90 (8.98x) | 1610.79 (3.58x) |
| Any StringScalarValue WKT JSON stringify | 154.45 | — | — | 2264.57 (14.66x) | 1038.57 (6.72x) |
| Any StringScalarValue WKT JSON parse | 504.21 | — | — | 3625.46 (7.19x) | 1649.77 (3.27x) |
| Any EmptyStringScalarValue WKT JSON stringify | 138.46 | — | — | 2270.11 (16.40x) | 994.69 (7.18x) |
| Any EmptyStringScalarValue WKT JSON parse | 477.09 | — | — | 3610.31 (7.57x) | 1584.87 (3.32x) |
| Any NumberValue WKT JSON stringify | 175.97 | — | — | 2515.44 (14.29x) | 1024.01 (5.82x) |
| Any NumberValue WKT JSON parse | 491.56 | — | — | 3700.89 (7.53x) | 1505.39 (3.06x) |
| Any ZeroNumberValue WKT JSON stringify | 138.79 | — | — | 2470.35 (17.80x) | 906.59 (6.53x) |
| Any ZeroNumberValue WKT JSON parse | 489.42 | — | — | 3642.73 (7.44x) | 1569.27 (3.21x) |
| Any BoolScalarValue WKT JSON stringify | 126.56 | — | — | 2252.14 (17.80x) | 907.09 (7.17x) |
| Any BoolScalarValue WKT JSON parse | 451.95 | — | — | 4472.99 (9.90x) | 1630.43 (3.61x) |
| Any FalseBoolScalarValue WKT JSON stringify | 127.45 | — | — | 2252.61 (17.67x) | 902.22 (7.08x) |
| Any FalseBoolScalarValue WKT JSON parse | 452.87 | — | — | 3625.51 (8.01x) | 1500.33 (3.31x) |
| Any ListKindValue WKT JSON stringify | 511.01 | — | — | 5661.48 (11.08x) | 4895.75 (9.58x) |
| Any ListKindValue WKT JSON parse | 1414.04 | — | — | 9895.67 (7.00x) | 6939.82 (4.91x) |
| Any EmptyStructKindValue WKT JSON stringify | 144.81 | — | — | 2925.35 (20.20x) | 1429.81 (9.87x) |
| Any EmptyStructKindValue WKT JSON parse | 490.03 | — | — | 5389.00 (11.00x) | 2003.80 (4.09x) |
| Any EmptyListKindValue WKT JSON stringify | 144.40 | — | — | 2891.05 (20.02x) | 1127.99 (7.81x) |
| Any EmptyListKindValue WKT JSON parse | 495.55 | — | — | 4393.72 (8.87x) | 1954.10 (3.94x) |
| Any DoubleValue WKT JSON stringify | 188.67 | — | — | 1794.47 (9.51x) | 791.84 (4.20x) |
| Any DoubleValue WKT JSON parse | 510.80 | — | — | 2727.38 (5.34x) | 1371.36 (2.68x) |
| Any NegativeDoubleValue WKT JSON stringify | 189.79 | — | — | 1803.58 (9.50x) | 790.55 (4.17x) |
| Any NegativeDoubleValue WKT JSON parse | 512.24 | — | — | 2727.74 (5.33x) | 1712.79 (3.34x) |
| Any ZeroDoubleValue WKT JSON stringify | 149.46 | — | — | 927.38 (6.20x) | 764.75 (5.12x) |
| Any ZeroDoubleValue WKT JSON parse | 506.93 | — | — | 2175.75 (4.29x) | 1315.77 (2.60x) |
| Any DoubleValue NaN WKT JSON stringify | 152.05 | — | — | 1572.79 (10.34x) | 759.67 (5.00x) |
| Any DoubleValue NaN WKT JSON parse | 505.34 | — | — | 2650.93 (5.25x) | 1424.69 (2.82x) |
| Any DoubleValue Infinity WKT JSON stringify | 158.56 | — | — | 1564.02 (9.86x) | 693.41 (4.37x) |
| Any DoubleValue Infinity WKT JSON parse | 509.30 | — | — | 2682.95 (5.27x) | 1406.48 (2.76x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 153.37 | — | — | 1562.87 (10.19x) | 746.19 (4.87x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 513.45 | — | — | 2699.12 (5.26x) | 1327.36 (2.59x) |
| Any FloatValue WKT JSON stringify | 197.60 | — | — | 1743.23 (8.82x) | 824.99 (4.18x) |
| Any FloatValue WKT JSON parse | 508.56 | — | — | 2702.83 (5.31x) | 1409.49 (2.77x) |
| Any NegativeFloatValue WKT JSON stringify | 193.29 | — | — | 1751.14 (9.06x) | 769.96 (3.98x) |
| Any NegativeFloatValue WKT JSON parse | 510.00 | — | — | 2715.10 (5.32x) | 1429.09 (2.80x) |
| Any ZeroFloatValue WKT JSON stringify | 159.59 | — | — | 913.24 (5.72x) | 732.69 (4.59x) |
| Any ZeroFloatValue WKT JSON parse | 505.08 | — | — | 2293.50 (4.54x) | 1371.76 (2.72x) |
| Any FloatValue NaN WKT JSON stringify | 153.33 | — | — | 1553.50 (10.13x) | 747.06 (4.87x) |
| Any FloatValue NaN WKT JSON parse | 505.81 | — | — | 2621.50 (5.18x) | 1428.71 (2.82x) |
| Any FloatValue Infinity WKT JSON stringify | 160.41 | — | — | 1545.45 (9.63x) | 695.33 (4.33x) |
| Any FloatValue Infinity WKT JSON parse | 509.72 | — | — | 2660.21 (5.22x) | 1308.92 (2.57x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 159.82 | — | — | 1547.09 (9.68x) | 743.20 (4.65x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 514.51 | — | — | 2689.69 (5.23x) | 1445.88 (2.81x) |
| Any Int64Value WKT JSON stringify | 171.84 | — | — | 1766.19 (10.28x) | 911.38 (5.30x) |
| Any Int64Value WKT JSON parse | 540.48 | — | — | 2806.37 (5.19x) | 1622.14 (3.00x) |
| Any Int64Value Number WKT JSON parse | 538.06 | — | — | 2736.97 (5.09x) | 1549.12 (2.88x) |
| Any ZeroInt64Value WKT JSON stringify | 157.12 | — | — | 925.62 (5.89x) | 729.13 (4.64x) |
| Any ZeroInt64Value WKT JSON parse | 513.27 | — | — | 2160.36 (4.21x) | 1475.44 (2.87x) |
| Any NegativeInt64Value WKT JSON stringify | 171.96 | — | — | 1581.66 (9.20x) | 938.29 (5.46x) |
| Any NegativeInt64Value WKT JSON parse | 545.43 | — | — | 2796.01 (5.13x) | 1690.71 (3.10x) |
| Any MinInt64Value WKT JSON stringify | 168.93 | — | — | 1566.57 (9.27x) | 871.85 (5.16x) |
| Any MinInt64Value WKT JSON parse | 552.70 | — | — | 2805.82 (5.08x) | 1659.38 (3.00x) |
| Any MaxInt64Value WKT JSON stringify | 170.17 | — | — | 1558.23 (9.16x) | 878.85 (5.16x) |
| Any MaxInt64Value WKT JSON parse | 545.55 | — | — | 2820.47 (5.17x) | 1769.53 (3.24x) |
| Any UInt64Value WKT JSON stringify | 175.00 | — | — | 1555.20 (8.89x) | 1022.19 (5.84x) |
| Any UInt64Value WKT JSON parse | 551.55 | — | — | 2777.42 (5.04x) | 1599.85 (2.90x) |
| Any UInt64Value Number WKT JSON parse | 541.29 | — | — | 2777.18 (5.13x) | 1570.30 (2.90x) |
| Any ZeroUInt64Value WKT JSON stringify | 156.73 | — | — | 956.10 (6.10x) | 855.06 (5.46x) |
| Any ZeroUInt64Value WKT JSON parse | 517.83 | — | — | 2161.97 (4.18x) | 1359.88 (2.63x) |
| Any MaxUInt64Value WKT JSON stringify | 178.25 | — | — | 1567.84 (8.80x) | 838.13 (4.70x) |
| Any MaxUInt64Value WKT JSON parse | 562.97 | — | — | 2821.76 (5.01x) | 1624.84 (2.89x) |
| Any Int32Value WKT JSON stringify | 169.49 | — | — | 1548.80 (9.14x) | 765.97 (4.52x) |
| Any Int32Value WKT JSON parse | 520.58 | — | — | 2706.92 (5.20x) | 1433.10 (2.75x) |
| Any ZeroInt32Value WKT JSON stringify | 164.50 | — | — | 917.39 (5.58x) | 661.63 (4.02x) |
| Any ZeroInt32Value WKT JSON parse | 514.89 | — | — | 2161.63 (4.20x) | 1313.74 (2.55x) |
| Any NegativeInt32Value WKT JSON stringify | 170.18 | — | — | 1548.21 (9.10x) | 705.57 (4.15x) |
| Any NegativeInt32Value WKT JSON parse | 524.13 | — | — | 2691.43 (5.14x) | 1418.53 (2.71x) |
| Any MinInt32Value WKT JSON stringify | 173.76 | — | — | 1551.81 (8.93x) | 742.28 (4.27x) |
| Any MinInt32Value WKT JSON parse | 529.87 | — | — | 2696.33 (5.09x) | 1437.11 (2.71x) |
| Any MaxInt32Value WKT JSON stringify | 174.03 | — | — | 1558.30 (8.95x) | 740.98 (4.26x) |
| Any MaxInt32Value WKT JSON parse | 529.20 | — | — | 2684.16 (5.07x) | 1454.06 (2.75x) |
| Any UInt32Value WKT JSON stringify | 173.98 | — | — | 1575.65 (9.06x) | 759.08 (4.36x) |
| Any UInt32Value WKT JSON parse | 523.62 | — | — | 2765.28 (5.28x) | 1425.42 (2.72x) |
| Any ZeroUInt32Value WKT JSON stringify | 173.88 | — | — | 945.09 (5.44x) | 693.18 (3.99x) |
| Any ZeroUInt32Value WKT JSON parse | 518.50 | — | — | 2201.72 (4.25x) | 1289.43 (2.49x) |
| Any MaxUInt32Value WKT JSON stringify | 178.88 | — | — | 1571.60 (8.79x) | 736.88 (4.12x) |
| Any MaxUInt32Value WKT JSON parse | 532.67 | — | — | 2690.72 (5.05x) | 1563.99 (2.94x) |
| Any BoolValue WKT JSON stringify | 168.66 | — | — | 1521.65 (9.02x) | 712.26 (4.22x) |
| Any BoolValue WKT JSON parse | 478.20 | — | — | 2595.12 (5.43x) | 1214.12 (2.54x) |
| Any FalseBoolValue WKT JSON stringify | 168.78 | — | — | 918.66 (5.44x) | 696.51 (4.13x) |
| Any FalseBoolValue WKT JSON parse | 478.03 | — | — | 2144.19 (4.49x) | 1270.32 (2.66x) |
| Any StringValue WKT JSON stringify | 197.32 | — | — | 1554.28 (7.88x) | 798.15 (4.04x) |
| Any StringValue WKT JSON parse | 540.20 | — | — | 2652.24 (4.91x) | 1491.29 (2.76x) |
| Any EmptyStringValue WKT JSON stringify | 192.09 | — | — | 918.85 (4.78x) | 742.38 (3.86x) |
| Any EmptyStringValue WKT JSON parse | 508.73 | — | — | 2201.73 (4.33x) | 1382.93 (2.72x) |
| Any BytesValue WKT JSON stringify | 188.63 | — | — | 1571.90 (8.33x) | 834.45 (4.42x) |
| Any BytesValue WKT JSON parse | 550.87 | — | — | 2676.42 (4.86x) | 1453.89 (2.64x) |
| Any EmptyBytesValue WKT JSON stringify | 181.54 | — | — | 917.02 (5.05x) | 738.74 (4.07x) |
| Any EmptyBytesValue WKT JSON parse | 515.38 | — | — | 2154.90 (4.18x) | 1326.13 (2.57x) |
| Nested Any WKT JSON stringify | 313.80 | — | — | 2464.44 (7.85x) | 1419.35 (4.52x) |
| Nested Any WKT JSON parse | 850.27 | — | — | 4855.00 (5.71x) | 2782.28 (3.27x) |
| Duration JSON stringify | 57.36 | — | — | 1565.79 (27.30x) | 346.25 (6.04x) |
| Duration JSON parse | 8.65 | — | — | 2324.64 (268.74x) | 371.90 (42.99x) |
| PlusDuration JSON parse | 8.90 | — | — | 2367.12 (265.97x) | 370.92 (41.68x) |
| ShortFractionDuration JSON parse | 6.79 | — | — | 1444.43 (212.73x) | 362.30 (53.36x) |
| MicroDuration JSON stringify | 59.61 | — | — | 969.43 (16.26x) | 381.92 (6.41x) |
| MicroDuration JSON parse | 9.86 | — | — | 1464.00 (148.48x) | 366.58 (37.18x) |
| NanoDuration JSON stringify | 57.19 | — | — | 998.71 (17.46x) | 378.41 (6.62x) |
| NanoDuration JSON parse | 12.57 | — | — | 1474.89 (117.33x) | 373.87 (29.74x) |
| NegativeDuration JSON stringify | 58.26 | — | — | 1002.88 (17.21x) | 416.37 (7.15x) |
| NegativeDuration JSON parse | 8.30 | — | — | 1517.75 (182.86x) | 378.20 (45.57x) |
| FractionalNegativeDuration JSON stringify | 58.27 | — | — | 996.01 (17.09x) | 405.59 (6.96x) |
| FractionalNegativeDuration JSON parse | 8.28 | — | — | 1454.71 (175.69x) | 361.02 (43.60x) |
| MaxDuration JSON stringify | 50.22 | — | — | 853.04 (16.99x) | 395.07 (7.87x) |
| MaxDuration JSON parse | 22.12 | — | — | 1433.95 (64.83x) | 377.48 (17.07x) |
| MinDuration JSON stringify | 50.18 | — | — | 870.77 (17.35x) | 427.17 (8.51x) |
| MinDuration JSON parse | 22.54 | — | — | 1477.52 (65.55x) | 385.10 (17.09x) |
| ZeroDuration JSON stringify | 44.89 | — | — | 904.14 (20.14x) | 333.87 (7.44x) |
| ZeroDuration JSON parse | 5.57 | — | — | 1384.52 (248.57x) | 304.57 (54.68x) |
| FieldMask JSON stringify | 134.31 | — | — | 976.77 (7.27x) | 665.25 (4.95x) |
| FieldMask JSON parse | 155.43 | — | — | 1656.03 (10.65x) | 820.10 (5.28x) |
| EmptyFieldMask JSON stringify | 40.91 | — | — | 612.10 (14.96x) | 178.40 (4.36x) |
| EmptyFieldMask JSON parse | 2.53 | — | — | 941.36 (372.08x) | 163.02 (64.43x) |
| Timestamp JSON stringify | 96.63 | — | — | 1138.78 (11.78x) | 411.27 (4.26x) |
| Timestamp JSON parse | 41.51 | — | — | 1483.58 (35.74x) | 426.84 (10.28x) |
| Micro Timestamp JSON stringify | 96.62 | — | — | 1154.01 (11.94x) | 422.20 (4.37x) |
| Micro Timestamp JSON parse | 43.03 | — | — | 1490.72 (34.64x) | 426.32 (9.91x) |
| Nano Timestamp JSON stringify | 94.26 | — | — | 1200.29 (12.73x) | 431.40 (4.58x) |
| Nano Timestamp JSON parse | 45.15 | — | — | 1510.33 (33.45x) | 435.53 (9.65x) |
| Offset Timestamp JSON parse | 49.32 | — | — | 1526.46 (30.95x) | 451.58 (9.16x) |
| PreEpoch Timestamp JSON stringify | 66.97 | — | — | 1075.16 (16.05x) | 409.21 (6.11x) |
| PreEpoch Timestamp JSON parse | 40.02 | — | — | 1460.47 (36.49x) | 408.87 (10.22x) |
| Max Timestamp JSON stringify | 79.61 | — | — | 1202.68 (15.11x) | 437.38 (5.49x) |
| Max Timestamp JSON parse | 47.18 | — | — | 1547.83 (32.81x) | 431.96 (9.16x) |
| Min Timestamp JSON stringify | 79.53 | — | — | 1065.31 (13.40x) | 393.72 (4.95x) |
| Min Timestamp JSON parse | 37.93 | — | — | 1457.97 (38.44x) | 415.98 (10.97x) |
| Empty JSON stringify | 21.59 | — | — | 496.27 (22.99x) | 79.95 (3.70x) |
| Empty JSON parse | 67.21 | — | — | 777.35 (11.57x) | 201.36 (3.00x) |
| Struct JSON stringify | 201.53 | — | — | 5953.14 (29.54x) | 2936.06 (14.57x) |
| Struct JSON parse | 869.36 | — | — | 10937.40 (12.58x) | 4663.58 (5.36x) |
| EmptyStruct JSON stringify | 41.14 | — | — | 688.35 (16.73x) | 349.74 (8.50x) |
| EmptyStruct JSON parse | 100.75 | — | — | 2050.40 (20.35x) | 364.76 (3.62x) |
| Value JSON stringify | 204.86 | — | — | 6640.77 (32.42x) | 3047.18 (14.87x) |
| Value JSON parse | 863.76 | — | — | 12239.10 (14.17x) | 4911.80 (5.69x) |
| NullValue JSON stringify | 40.94 | — | — | 1317.43 (32.18x) | 219.95 (5.37x) |
| NullValue JSON parse | 64.90 | — | — | 2443.95 (37.66x) | 350.77 (5.40x) |
| StringScalarValue JSON stringify | 48.37 | — | — | 1335.19 (27.60x) | 276.34 (5.71x) |
| StringScalarValue JSON parse | 135.59 | — | — | 2068.14 (15.25x) | 404.48 (2.98x) |
| EmptyStringScalarValue JSON stringify | 46.49 | — | — | 1343.02 (28.89x) | 289.04 (6.22x) |
| EmptyStringScalarValue JSON parse | 82.46 | — | — | 2072.69 (25.14x) | 373.68 (4.53x) |
| NumberValue JSON stringify | 73.76 | — | — | 1673.52 (22.69x) | 330.11 (4.48x) |
| NumberValue JSON parse | 127.09 | — | — | 2196.32 (17.28x) | 405.62 (3.19x) |
| ZeroNumberValue JSON stringify | 51.21 | — | — | 1511.87 (29.52x) | 270.11 (5.27x) |
| ZeroNumberValue JSON parse | 125.66 | — | — | 2109.75 (16.79x) | 379.21 (3.02x) |
| BoolScalarValue JSON stringify | 41.01 | — | — | 1329.24 (32.41x) | 224.86 (5.48x) |
| BoolScalarValue JSON parse | 65.04 | — | — | 2002.78 (30.79x) | 314.79 (4.84x) |
| FalseBoolScalarValue JSON stringify | 41.08 | — | — | 1314.74 (32.00x) | 221.60 (5.39x) |
| FalseBoolScalarValue JSON parse | 65.41 | — | — | 2027.95 (31.00x) | 316.50 (4.84x) |
| ListKindValue JSON stringify | 150.60 | — | — | 6171.68 (40.98x) | 2301.02 (15.28x) |
| ListKindValue JSON parse | 661.04 | — | — | 10933.70 (16.54x) | 3950.38 (5.98x) |
| EmptyStructKindValue JSON stringify | 42.88 | — | — | 1949.31 (45.46x) | 489.78 (11.42x) |
| EmptyStructKindValue JSON parse | 105.28 | — | — | 3744.91 (35.57x) | 611.46 (5.81x) |
| EmptyListKindValue JSON stringify | 42.60 | — | — | 2017.74 (47.36x) | 353.01 (8.29x) |
| EmptyListKindValue JSON parse | 143.94 | — | — | 4049.13 (28.13x) | 552.23 (3.84x) |
| ListValue JSON stringify | 153.79 | — | — | 4750.25 (30.89x) | 2091.86 (13.60x) |
| ListValue JSON parse | 675.93 | — | — | 8449.69 (12.50x) | 3811.86 (5.64x) |
| EmptyListValue JSON stringify | 40.54 | — | — | 685.86 (16.92x) | 175.47 (4.33x) |
| EmptyListValue JSON parse | 140.08 | — | — | 2233.07 (15.94x) | 280.91 (2.01x) |
| DoubleValue JSON stringify | 67.43 | — | — | 862.63 (12.79x) | 192.43 (2.85x) |
| DoubleValue JSON parse | 112.41 | — | — | 1223.60 (10.89x) | 281.79 (2.51x) |
| NegativeDoubleValue JSON stringify | 68.15 | — | — | 865.93 (12.71x) | 183.61 (2.69x) |
| NegativeDoubleValue JSON parse | 112.87 | — | — | 1225.89 (10.86x) | 277.00 (2.45x) |
| ZeroDoubleValue JSON stringify | 47.67 | — | — | 820.00 (17.20x) | 157.38 (3.30x) |
| ZeroDoubleValue JSON parse | 110.36 | — | — | 1187.66 (10.76x) | 267.06 (2.42x) |
| DoubleValue NaN JSON stringify | 46.78 | — | — | 673.67 (14.40x) | 136.70 (2.92x) |
| DoubleValue NaN JSON parse | 104.49 | — | — | 1101.85 (10.55x) | 275.41 (2.64x) |
| DoubleValue Infinity JSON stringify | 48.29 | — | — | 670.23 (13.88x) | 150.63 (3.12x) |
| DoubleValue Infinity JSON parse | 106.29 | — | — | 1110.96 (10.45x) | 282.06 (2.65x) |
| DoubleValue NegativeInfinity JSON stringify | 48.73 | — | — | 692.05 (14.20x) | 129.91 (2.67x) |
| DoubleValue NegativeInfinity JSON parse | 108.04 | — | — | 1120.84 (10.37x) | 273.93 (2.54x) |
| FloatValue JSON stringify | 70.95 | — | — | 809.15 (11.40x) | 197.64 (2.79x) |
| FloatValue JSON parse | 112.58 | — | — | 1238.28 (11.00x) | 285.37 (2.53x) |
| NegativeFloatValue JSON stringify | 70.74 | — | — | 797.43 (11.27x) | 181.32 (2.56x) |
| NegativeFloatValue JSON parse | 113.53 | — | — | 1230.13 (10.84x) | 301.54 (2.66x) |
| ZeroFloatValue JSON stringify | 47.49 | — | — | 772.32 (16.26x) | 134.73 (2.84x) |
| ZeroFloatValue JSON parse | 109.87 | — | — | 1193.11 (10.86x) | 260.72 (2.37x) |
| FloatValue NaN JSON stringify | 46.41 | — | — | 644.75 (13.89x) | 139.81 (3.01x) |
| FloatValue NaN JSON parse | 105.24 | — | — | 1098.64 (10.44x) | 276.34 (2.63x) |
| FloatValue Infinity JSON stringify | 48.00 | — | — | 648.75 (13.52x) | 116.43 (2.43x) |
| FloatValue Infinity JSON parse | 106.58 | — | — | 1093.29 (10.26x) | 273.11 (2.56x) |
| FloatValue NegativeInfinity JSON stringify | 48.12 | — | — | 674.23 (14.01x) | 120.27 (2.50x) |
| FloatValue NegativeInfinity JSON parse | 108.46 | — | — | 1107.36 (10.21x) | 256.16 (2.36x) |
| Int64Value JSON stringify | 50.33 | — | — | 674.23 (13.40x) | 280.14 (5.57x) |
| Int64Value JSON parse | 125.31 | — | — | 1233.89 (9.85x) | 444.03 (3.54x) |
| Int64Value Number JSON parse | 127.95 | — | — | 1275.26 (9.97x) | 359.61 (2.81x) |
| ZeroInt64Value JSON stringify | 41.67 | — | — | 609.54 (14.63x) | 198.34 (4.76x) |
| ZeroInt64Value JSON parse | 105.75 | — | — | 1101.00 (10.41x) | 319.74 (3.02x) |
| NegativeInt64Value JSON stringify | 48.72 | — | — | 677.03 (13.90x) | 267.62 (5.49x) |
| NegativeInt64Value JSON parse | 127.79 | — | — | 1232.12 (9.64x) | 465.36 (3.64x) |
| MinInt64Value JSON stringify | 50.53 | — | — | 676.91 (13.40x) | 284.07 (5.62x) |
| MinInt64Value JSON parse | 141.07 | — | — | 1246.03 (8.83x) | 485.76 (3.44x) |
| MaxInt64Value JSON stringify | 49.57 | — | — | 676.07 (13.64x) | 268.34 (5.41x) |
| MaxInt64Value JSON parse | 133.40 | — | — | 1242.03 (9.31x) | 443.90 (3.33x) |
| UInt64Value JSON stringify | 50.34 | — | — | 677.35 (13.46x) | 292.21 (5.80x) |
| UInt64Value JSON parse | 124.55 | — | — | 1214.95 (9.75x) | 430.38 (3.46x) |
| UInt64Value Number JSON parse | 127.62 | — | — | 1274.06 (9.98x) | 343.11 (2.69x) |
| ZeroUInt64Value JSON stringify | 41.70 | — | — | 610.83 (14.65x) | 186.80 (4.48x) |
| ZeroUInt64Value JSON parse | 103.81 | — | — | 1105.22 (10.65x) | 310.45 (2.99x) |
| MaxUInt64Value JSON stringify | 50.21 | — | — | 679.12 (13.53x) | 264.86 (5.28x) |
| MaxUInt64Value JSON parse | 148.25 | — | — | 1254.97 (8.47x) | 452.53 (3.05x) |
| Int32Value JSON stringify | 46.28 | — | — | 636.05 (13.74x) | 150.64 (3.25x) |
| Int32Value JSON parse | 129.47 | — | — | 1181.76 (9.13x) | 313.62 (2.42x) |
| ZeroInt32Value JSON stringify | 46.15 | — | — | 615.63 (13.34x) | 121.55 (2.63x) |
| ZeroInt32Value JSON parse | 124.43 | — | — | 1159.63 (9.32x) | 264.35 (2.12x) |
| NegativeInt32Value JSON stringify | 46.16 | — | — | 643.97 (13.95x) | 131.27 (2.84x) |
| NegativeInt32Value JSON parse | 128.44 | — | — | 1198.39 (9.33x) | 301.91 (2.35x) |
| MinInt32Value JSON stringify | 47.06 | — | — | 638.63 (13.57x) | 140.60 (2.99x) |
| MinInt32Value JSON parse | 133.96 | — | — | 1212.27 (9.05x) | 329.94 (2.46x) |
| MaxInt32Value JSON stringify | 47.05 | — | — | 639.46 (13.59x) | 133.37 (2.83x) |
| MaxInt32Value JSON parse | 135.25 | — | — | 1211.32 (8.96x) | 332.07 (2.46x) |
| UInt32Value JSON stringify | 46.17 | — | — | 646.78 (14.01x) | 139.27 (3.02x) |
| UInt32Value JSON parse | 129.29 | — | — | 1189.82 (9.20x) | 314.25 (2.43x) |
| ZeroUInt32Value JSON stringify | 46.34 | — | — | 635.20 (13.71x) | 153.65 (3.32x) |
| ZeroUInt32Value JSON parse | 124.60 | — | — | 1176.60 (9.44x) | 250.35 (2.01x) |
| MaxUInt32Value JSON stringify | 46.84 | — | — | 648.12 (13.84x) | 171.30 (3.66x) |
| MaxUInt32Value JSON parse | 135.73 | — | — | 1213.52 (8.94x) | 370.35 (2.73x) |
| BoolValue JSON stringify | 44.83 | — | — | 631.28 (14.08x) | 143.74 (3.21x) |
| BoolValue JSON parse | 59.39 | — | — | 1062.70 (17.89x) | 230.10 (3.87x) |
| FalseBoolValue JSON stringify | 44.90 | — | — | 605.97 (13.50x) | 119.69 (2.67x) |
| FalseBoolValue JSON parse | 59.89 | — | — | 1058.89 (17.68x) | 205.86 (3.44x) |
| StringValue JSON stringify | 51.88 | — | — | 679.01 (13.09x) | 186.43 (3.59x) |
| StringValue JSON parse | 138.07 | — | — | 1154.94 (8.36x) | 287.81 (2.08x) |
| EmptyStringValue JSON stringify | 49.06 | — | — | 648.40 (13.22x) | 185.97 (3.79x) |
| EmptyStringValue JSON parse | 81.69 | — | — | 1123.91 (13.76x) | 230.72 (2.82x) |
| BytesValue JSON stringify | 49.59 | — | — | 665.32 (13.42x) | 215.05 (4.34x) |
| BytesValue JSON parse | 146.76 | — | — | 1183.55 (8.06x) | 317.50 (2.16x) |
| EmptyBytesValue JSON stringify | 41.13 | — | — | 645.48 (15.69x) | 176.00 (4.28x) |
| EmptyBytesValue JSON parse | 89.75 | — | — | 1140.53 (12.71x) | 249.33 (2.78x) |
| TextFormat format | 172.78 | — | — | 2516.28 (14.56x) | 2383.91 (13.80x) |
| TextFormat parse | 674.36 | — | — | 4988.90 (7.40x) | 6274.87 (9.30x) |
| packed fixed32 encode | 2.00 | 552.34 (276.17x) | 540.05 (270.02x) | 43.70 (21.85x) | 412.94 (206.47x) |
| packed fixed32 decode | 4.51 | 1049.85 (232.78x) | 1935.18 (429.09x) | 50.18 (11.13x) | 1687.63 (374.20x) |
| packed fixed64 encode | 2.06 | 575.69 (279.46x) | 561.08 (272.37x) | 76.18 (36.98x) | 402.86 (195.56x) |
| packed fixed64 decode | 4.65 | 1042.99 (224.30x) | 7954.47 (1710.64x) | 81.25 (17.47x) | 2603.21 (559.83x) |
| packed sfixed32 encode | 2.01 | 552.57 (274.91x) | 542.69 (270.00x) | 44.20 (21.99x) | 433.39 (215.62x) |
| packed sfixed32 decode | 4.53 | 1055.32 (232.96x) | 1974.17 (435.80x) | 49.84 (11.00x) | 1700.71 (375.43x) |
| packed sfixed64 encode | 2.01 | 573.86 (285.50x) | 576.84 (286.99x) | 76.02 (37.82x) | 390.82 (194.44x) |
| packed sfixed64 decode | 4.54 | 1001.05 (220.50x) | 7926.44 (1745.91x) | 80.24 (17.67x) | 2273.21 (500.71x) |
| packed float encode | 2.01 | 813.25 (404.60x) | 541.88 (269.59x) | 43.88 (21.83x) | 356.85 (177.54x) |
| packed float decode | 4.53 | 1054.45 (232.77x) | 2060.88 (454.94x) | 49.61 (10.95x) | 1780.46 (393.04x) |
| packed double encode | 2.01 | 833.47 (414.66x) | 563.48 (280.34x) | 76.13 (37.87x) | 353.50 (175.87x) |
| packed double decode | 4.52 | 962.27 (212.89x) | 2091.82 (462.79x) | 80.40 (17.79x) | 2695.54 (596.36x) |
| packed uint64 encode | 1292.81 | 4597.20 (3.56x) | 4065.70 (3.14x) | 2135.16 (1.65x) | 3437.49 (2.66x) |
| packed uint64 decode | 1779.03 | 2784.72 (1.57x) | 8862.56 (4.98x) | 2821.82 (1.59x) | 8317.71 (4.68x) |
| packed uint32 encode | 925.73 | 3623.86 (3.91x) | 3252.85 (3.51x) | 1723.27 (1.86x) | 2915.56 (3.15x) |
| packed uint32 decode | 1317.39 | 2432.75 (1.85x) | 3255.43 (2.47x) | 1989.76 (1.51x) | 6053.49 (4.60x) |
| packed int64 encode | 1397.84 | 10859.45 (7.77x) | 6066.39 (4.34x) | 2899.58 (2.07x) | 4119.60 (2.95x) |
| packed int64 decode | 2755.22 | 3367.81 (1.22x) | 10256.75 (3.72x) | 4765.20 (1.73x) | 10178.20 (3.69x) |
| packed sint32 encode | 864.16 | 3053.39 (3.53x) | 2865.81 (3.32x) | 1531.82 (1.77x) | 3408.54 (3.94x) |
| packed sint32 decode | 953.20 | 2548.49 (2.67x) | 3198.94 (3.36x) | 1127.65 (1.18x) | 3595.72 (3.77x) |
| packed sint64 encode | 1435.08 | 4937.58 (3.44x) | 4289.65 (2.99x) | 2394.10 (1.67x) | 4134.08 (2.88x) |
| packed sint64 decode | 2040.45 | 3117.57 (1.53x) | 9731.16 (4.77x) | 2933.65 (1.44x) | 8453.89 (4.14x) |
| packed bool encode | 2.01 | 1325.69 (659.55x) | 521.20 (259.30x) | 15.99 (7.95x) | 2203.78 (1096.41x) |
| packed bool decode | 263.07 | 1784.55 (6.78x) | 2556.66 (9.72x) | 803.49 (3.05x) | 1968.68 (7.48x) |
| packed enum encode | 274.99 | 2764.44 (10.05x) | 1806.87 (6.57x) | 1085.12 (3.95x) | 2485.09 (9.04x) |
| packed enum decode | 160.55 | 1542.65 (9.61x) | 2979.37 (18.56x) | 686.88 (4.28x) | 2713.03 (16.90x) |
| large map encode | 4082.00 | 16817.55 (4.12x) | 9672.53 (2.37x) | 20921.80 (5.13x) | 197816.94 (48.46x) |
| shuffled large map deterministic binary encode | 27829.94 | — | — | 90964.50 (3.27x) | 385573.70 (13.85x) |
| large map decode | 26063.56 | 90656.97 (3.48x) | 90137.70 (3.46x) | 92547.50 (3.55x) | 275930.20 (10.59x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded zero/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound `Duration`, non-empty and empty `Struct`, object/list/scalar `Value` (including default-like scalar and empty object/list kinds),
`FieldMask` (non-empty and empty), micro/nano/offset/min/pre/post/max-bound `Timestamp`, `Empty`, min/zero/positive/number-input parse/negative/max `Int64Value`, negative/zero/positive finite `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), negative/zero/positive finite `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), zero/normal/number-input parse/max `UInt64Value`, min/zero/positive/negative/max `Int32Value`, zero/normal/max `UInt32Value`, true/false `BoolValue`, non-empty/empty `StringValue`, base64/empty `BytesValue`, and recursive nested `Any` payloads), direct zero/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound Duration and micro/nano/offset/min/pre/post/max-bound Timestamp WKT JSON plus other direct WKT JSON, including empty `Struct` and empty `ListValue`, TextFormat, packed scalars, large bytes,
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
