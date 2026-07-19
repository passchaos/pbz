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

Latest accepted comparison (`/tmp/pbz-compare-temporal-escape-json-isolated-rerun.log`,
summarized in `/tmp/pbz-summary-temporal-escape-json-isolated-rerun.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 20.51 | 100.73 (4.91x) | 51.80 (2.53x) | 108.53 (5.29x) | 828.08 (40.37x) |
| binary decode | 86.56 | 252.29 (2.91x) | 229.57 (2.65x) | 225.37 (2.60x) | 886.80 (10.24x) |
| unknown fields count by number | 3.57 | — | — | 161.13 (45.13x) | — |
| deterministic binary encode | 50.40 | — | — | 131.28 (2.60x) | 1037.85 (20.59x) |
| scalarmix encode | 19.29 | 99.44 (5.16x) | 47.53 (2.46x) | 31.28 (1.62x) | 213.81 (11.08x) |
| scalarmix decode | 34.33 | 131.65 (3.83x) | 172.26 (5.02x) | 87.32 (2.54x) | 294.74 (8.59x) |
| textbytes encode | 13.53 | 78.08 (5.77x) | 34.35 (2.54x) | 120.42 (8.90x) | 175.38 (12.96x) |
| textbytes decode | 44.46 | 378.76 (8.52x) | 243.97 (5.49x) | 165.43 (3.72x) | 629.06 (14.15x) |
| largebytes encode | 17.54 | 2724.96 (155.36x) | 2679.58 (152.77x) | 2679.98 (152.79x) | 3195.35 (182.18x) |
| largebytes decode | 88.90 | 5576.72 (62.73x) | 3006.08 (33.81x) | 2786.66 (31.35x) | 24935.93 (280.49x) |
| presencemix encode | 17.29 | 55.87 (3.23x) | 28.66 (1.66x) | 57.73 (3.34x) | 228.13 (13.19x) |
| presencemix decode | 56.42 | 134.93 (2.39x) | 108.15 (1.92x) | 162.63 (2.88x) | 490.70 (8.70x) |
| complex encode | 51.20 | 137.08 (2.68x) | 95.15 (1.86x) | 168.32 (3.29x) | 931.50 (18.19x) |
| complex decode | 169.41 | 393.43 (2.32x) | 341.73 (2.02x) | 388.06 (2.29x) | 1409.61 (8.32x) |
| complex deterministic binary encode | 88.65 | — | — | 173.45 (1.96x) | 1133.09 (12.78x) |
| complex JSON stringify | 268.71 | — | — | 4873.94 (18.14x) | 6202.03 (23.08x) |
| complex JSON parse | 2381.52 | — | — | 11906.60 (5.00x) | 7741.31 (3.25x) |
| complex TextFormat format | 239.51 | — | — | 3778.91 (15.78x) | 5470.62 (22.84x) |
| complex TextFormat parse | 1857.38 | — | — | 6918.17 (3.72x) | 8604.78 (4.63x) |
| packed int32 encode | 621.99 | 3154.29 (5.07x) | 2512.27 (4.04x) | 1248.96 (2.01x) | 2902.73 (4.67x) |
| packed int32 decode | 690.62 | 1934.24 (2.80x) | 3213.06 (4.65x) | 945.92 (1.37x) | 3303.44 (4.78x) |
| JSON stringify | 158.24 | — | — | 3004.86 (18.99x) | 2384.59 (15.07x) |
| JSON parse | 1527.24 | — | — | 7423.41 (4.86x) | 4696.42 (3.08x) |
| Any WKT JSON stringify | 132.28 | — | — | 1882.19 (14.23x) | 1134.61 (8.58x) |
| Any WKT JSON parse | 518.58 | — | — | 2977.98 (5.74x) | 1616.90 (3.12x) |
| Any Duration Escape WKT JSON parse | 538.84 | — | — | 3005.77 (5.58x) | 1974.36 (3.66x) |
| Any PlusDuration WKT JSON parse | 522.14 | — | — | 2995.60 (5.74x) | 1543.67 (2.96x) |
| Any ShortFractionDuration WKT JSON parse | 518.33 | — | — | 2945.96 (5.68x) | 1477.14 (2.85x) |
| Any MicroDuration WKT JSON stringify | 137.07 | — | — | 1895.85 (13.83x) | 1273.15 (9.29x) |
| Any MicroDuration WKT JSON parse | 521.22 | — | — | 2992.02 (5.74x) | 1550.25 (2.97x) |
| Any NanoDuration WKT JSON stringify | 136.22 | — | — | 1920.76 (14.10x) | 1092.50 (8.02x) |
| Any NanoDuration WKT JSON parse | 527.04 | — | — | 3009.60 (5.71x) | 1702.88 (3.23x) |
| Any NegativeDuration WKT JSON stringify | 138.29 | — | — | 1941.84 (14.04x) | 977.48 (7.07x) |
| Any NegativeDuration WKT JSON parse | 525.54 | — | — | 3086.49 (5.87x) | 1555.00 (2.96x) |
| Any FractionalNegativeDuration WKT JSON stringify | 129.93 | — | — | 1913.58 (14.73x) | 1002.86 (7.72x) |
| Any FractionalNegativeDuration WKT JSON parse | 517.92 | — | — | 3048.86 (5.89x) | 1471.24 (2.84x) |
| Any MaxDuration WKT JSON stringify | 124.02 | — | — | 1742.40 (14.05x) | 1103.18 (8.90x) |
| Any MaxDuration WKT JSON parse | 539.53 | — | — | 2955.95 (5.48x) | 1554.83 (2.88x) |
| Any MinDuration WKT JSON stringify | 123.95 | — | — | 1784.90 (14.40x) | 991.39 (8.00x) |
| Any MinDuration WKT JSON parse | 540.53 | — | — | 3013.97 (5.58x) | 1612.46 (2.98x) |
| Any ZeroDuration WKT JSON stringify | 108.93 | — | — | 911.10 (8.36x) | 972.43 (8.93x) |
| Any ZeroDuration WKT JSON parse | 467.92 | — | — | 2239.00 (4.79x) | 1361.81 (2.91x) |
| Any FieldMask WKT JSON stringify | 241.58 | — | — | 1744.69 (7.22x) | 1510.96 (6.25x) |
| Any FieldMask WKT JSON parse | 725.67 | — | — | 3143.27 (4.33x) | 2059.32 (2.84x) |
| Any FieldMask Escape WKT JSON parse | 755.57 | — | — | 3243.00 (4.29x) | 2659.73 (3.52x) |
| Any EmptyFieldMask WKT JSON stringify | 116.43 | — | — | 914.31 (7.85x) | 762.05 (6.55x) |
| Any EmptyFieldMask WKT JSON parse | 447.62 | — | — | 2153.68 (4.81x) | 1270.16 (2.84x) |
| Any Timestamp WKT JSON stringify | 182.77 | — | — | 2045.89 (11.19x) | 1037.92 (5.68x) |
| Any Timestamp WKT JSON parse | 571.83 | — | — | 3025.27 (5.29x) | 1738.71 (3.04x) |
| Any Timestamp Escape WKT JSON parse | 589.87 | — | — | 3061.12 (5.19x) | 1747.93 (2.96x) |
| Any ShortFraction Timestamp WKT JSON parse | 565.73 | — | — | 3006.18 (5.31x) | 1580.90 (2.79x) |
| Any Micro Timestamp WKT JSON stringify | 188.19 | — | — | 2025.11 (10.76x) | 1023.91 (5.44x) |
| Any Micro Timestamp WKT JSON parse | 575.15 | — | — | 3077.57 (5.35x) | 1611.80 (2.80x) |
| Any Nano Timestamp WKT JSON stringify | 184.59 | — | — | 2049.98 (11.11x) | 1064.86 (5.77x) |
| Any Nano Timestamp WKT JSON parse | 582.82 | — | — | 3040.58 (5.22x) | 1640.53 (2.81x) |
| Any Offset Timestamp WKT JSON parse | 588.79 | — | — | 3046.79 (5.17x) | 1823.68 (3.10x) |
| Any PreEpoch Timestamp WKT JSON stringify | 149.26 | — | — | 1966.38 (13.17x) | 1103.93 (7.40x) |
| Any PreEpoch Timestamp WKT JSON parse | 563.70 | — | — | 3033.10 (5.38x) | 1583.50 (2.81x) |
| Any Max Timestamp WKT JSON stringify | 167.50 | — | — | 2064.76 (12.33x) | 1137.02 (6.79x) |
| Any Max Timestamp WKT JSON parse | 582.69 | — | — | 3079.10 (5.28x) | 1697.51 (2.91x) |
| Any Min Timestamp WKT JSON stringify | 167.40 | — | — | 1955.70 (11.68x) | 1020.75 (6.10x) |
| Any Min Timestamp WKT JSON parse | 559.77 | — | — | 3023.19 (5.40x) | 1822.96 (3.26x) |
| Any Empty WKT JSON stringify | 94.17 | — | — | 914.11 (9.71x) | 646.64 (6.87x) |
| Any Empty WKT JSON parse | 339.23 | — | — | 2131.79 (6.28x) | 1253.72 (3.70x) |
| Any Struct WKT JSON stringify | 624.79 | — | — | 5791.87 (9.27x) | 6925.46 (11.08x) |
| Any Struct WKT JSON parse | 1735.51 | — | — | 11111.10 (6.40x) | 9350.01 (5.39x) |
| Any EmptyStruct WKT JSON stringify | 124.17 | — | — | 912.52 (7.35x) | 993.83 (8.00x) |
| Any EmptyStruct WKT JSON parse | 432.06 | — | — | 2222.56 (5.14x) | 1565.32 (3.62x) |
| Any Value WKT JSON stringify | 650.82 | — | — | 5913.11 (9.09x) | 6839.08 (10.51x) |
| Any Value WKT JSON parse | 1786.31 | — | — | 11326.40 (6.34x) | 9946.23 (5.57x) |
| Any NullValue WKT JSON stringify | 134.25 | — | — | 2252.59 (16.78x) | 1281.78 (9.55x) |
| Any NullValue WKT JSON parse | 457.41 | — | — | 4049.14 (8.85x) | 2190.49 (4.79x) |
| Any StringScalarValue WKT JSON stringify | 156.07 | — | — | 2284.37 (14.64x) | 1604.35 (10.28x) |
| Any StringScalarValue WKT JSON parse | 516.83 | — | — | 3605.89 (6.98x) | 1736.91 (3.36x) |
| Any EmptyStringScalarValue WKT JSON stringify | 141.84 | — | — | 2280.41 (16.08x) | 1071.28 (7.55x) |
| Any EmptyStringScalarValue WKT JSON parse | 487.32 | — | — | 3580.55 (7.35x) | 1883.52 (3.87x) |
| Any NumberValue WKT JSON stringify | 172.62 | — | — | 2523.11 (14.62x) | 1091.55 (6.32x) |
| Any NumberValue WKT JSON parse | 495.06 | — | — | 3665.41 (7.40x) | 1527.18 (3.08x) |
| Any ZeroNumberValue WKT JSON stringify | 139.71 | — | — | 2477.01 (17.73x) | 1155.36 (8.27x) |
| Any ZeroNumberValue WKT JSON parse | 492.47 | — | — | 3607.08 (7.32x) | 1619.65 (3.29x) |
| Any BoolScalarValue WKT JSON stringify | 132.06 | — | — | 2263.30 (17.14x) | 906.07 (6.86x) |
| Any BoolScalarValue WKT JSON parse | 452.32 | — | — | 3569.69 (7.89x) | 1547.02 (3.42x) |
| Any FalseBoolScalarValue WKT JSON stringify | 133.46 | — | — | 2280.38 (17.09x) | 894.76 (6.70x) |
| Any FalseBoolScalarValue WKT JSON parse | 452.75 | — | — | 3585.19 (7.92x) | 1606.03 (3.55x) |
| Any ListKindValue WKT JSON stringify | 502.26 | — | — | 5582.35 (11.11x) | 5330.94 (10.61x) |
| Any ListKindValue WKT JSON parse | 1376.29 | — | — | 9883.18 (7.18x) | 7586.54 (5.51x) |
| Any EmptyStructKindValue WKT JSON stringify | 147.37 | — | — | 2907.04 (19.73x) | 1250.60 (8.49x) |
| Any EmptyStructKindValue WKT JSON parse | 490.77 | — | — | 5392.54 (10.99x) | 2207.94 (4.50x) |
| Any EmptyListKindValue WKT JSON stringify | 144.39 | — | — | 2900.17 (20.09x) | 1167.70 (8.09x) |
| Any EmptyListKindValue WKT JSON parse | 498.80 | — | — | 4370.10 (8.76x) | 1773.25 (3.56x) |
| Any DoubleValue WKT JSON stringify | 187.96 | — | — | 1923.76 (10.23x) | 834.81 (4.44x) |
| Any DoubleValue WKT JSON parse | 512.94 | — | — | 2894.60 (5.64x) | 1473.83 (2.87x) |
| Any DoubleValue String WKT JSON parse | 531.47 | — | — | 2782.00 (5.23x) | 1515.14 (2.85x) |
| Any NegativeDoubleValue WKT JSON stringify | 189.15 | — | — | 2118.96 (11.20x) | 818.71 (4.33x) |
| Any NegativeDoubleValue WKT JSON parse | 516.70 | — | — | 4754.91 (9.20x) | 1388.04 (2.69x) |
| Any ZeroDoubleValue WKT JSON stringify | 159.06 | — | — | 2836.93 (17.84x) | 820.52 (5.16x) |
| Any ZeroDoubleValue WKT JSON parse | 510.45 | — | — | 4328.28 (8.48x) | 1616.39 (3.17x) |
| Any DoubleValue NaN WKT JSON stringify | 155.22 | — | — | 2865.77 (18.46x) | 753.34 (4.85x) |
| Any DoubleValue NaN WKT JSON parse | 517.76 | — | — | 4996.92 (9.65x) | 1385.13 (2.68x) |
| Any DoubleValue Infinity WKT JSON stringify | 164.48 | — | — | 1567.52 (9.53x) | 745.04 (4.53x) |
| Any DoubleValue Infinity WKT JSON parse | 517.27 | — | — | 2721.39 (5.26x) | 1445.17 (2.79x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 168.77 | — | — | 1573.29 (9.32x) | 721.05 (4.27x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 520.35 | — | — | 4185.14 (8.04x) | 1612.82 (3.10x) |
| Any FloatValue WKT JSON stringify | 191.28 | — | — | 2804.05 (14.66x) | 819.07 (4.28x) |
| Any FloatValue WKT JSON parse | 517.59 | — | — | 3886.87 (7.51x) | 1576.67 (3.05x) |
| Any FloatValue String WKT JSON parse | 533.57 | — | — | 3638.61 (6.82x) | 1522.74 (2.85x) |
| Any NegativeFloatValue WKT JSON stringify | 194.59 | — | — | 2886.52 (14.83x) | 824.15 (4.24x) |
| Any NegativeFloatValue WKT JSON parse | 515.25 | — | — | 4462.75 (8.66x) | 1371.45 (2.66x) |
| Any ZeroFloatValue WKT JSON stringify | 163.82 | — | — | 1410.83 (8.61x) | 709.20 (4.33x) |
| Any ZeroFloatValue WKT JSON parse | 512.69 | — | — | 3236.67 (6.31x) | 1282.59 (2.50x) |
| Any FloatValue NaN WKT JSON stringify | 162.12 | — | — | 1665.24 (10.27x) | 722.70 (4.46x) |
| Any FloatValue NaN WKT JSON parse | 515.34 | — | — | 2624.18 (5.09x) | 1389.17 (2.70x) |
| Any FloatValue Infinity WKT JSON stringify | 165.68 | — | — | 1542.80 (9.31x) | 718.91 (4.34x) |
| Any FloatValue Infinity WKT JSON parse | 519.21 | — | — | 2662.93 (5.13x) | 1511.18 (2.91x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 171.83 | — | — | 1565.28 (9.11x) | 686.70 (4.00x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 523.58 | — | — | 2661.07 (5.08x) | 1356.88 (2.59x) |
| Any Int64Value WKT JSON stringify | 170.49 | — | — | 1576.46 (9.25x) | 946.56 (5.55x) |
| Any Int64Value WKT JSON parse | 563.83 | — | — | 4360.70 (7.73x) | 1638.80 (2.91x) |
| Any Int64Value Number WKT JSON parse | 550.64 | — | — | 4420.24 (8.03x) | 1690.46 (3.07x) |
| Any ZeroInt64Value WKT JSON stringify | 153.33 | — | — | 1413.34 (9.22x) | 792.73 (5.17x) |
| Any ZeroInt64Value WKT JSON parse | 525.37 | — | — | 3341.63 (6.36x) | 1454.74 (2.77x) |
| Any NegativeInt64Value WKT JSON stringify | 170.74 | — | — | 1553.32 (9.10x) | 811.70 (4.75x) |
| Any NegativeInt64Value WKT JSON parse | 556.02 | — | — | 2804.16 (5.04x) | 1711.02 (3.08x) |
| Any MinInt64Value WKT JSON stringify | 175.73 | — | — | 1558.89 (8.87x) | 956.80 (5.44x) |
| Any MinInt64Value WKT JSON parse | 559.28 | — | — | 2821.39 (5.04x) | 1881.33 (3.36x) |
| Any MaxInt64Value WKT JSON stringify | 175.83 | — | — | 1575.88 (8.96x) | 903.54 (5.14x) |
| Any MaxInt64Value WKT JSON parse | 567.65 | — | — | 2796.55 (4.93x) | 1791.09 (3.16x) |
| Any UInt64Value WKT JSON stringify | 176.97 | — | — | 1587.78 (8.97x) | 1017.43 (5.75x) |
| Any UInt64Value WKT JSON parse | 559.28 | — | — | 2790.87 (4.99x) | 1750.70 (3.13x) |
| Any UInt64Value Number WKT JSON parse | 557.22 | — | — | 2768.26 (4.97x) | 1532.30 (2.75x) |
| Any ZeroUInt64Value WKT JSON stringify | 166.99 | — | — | 914.14 (5.47x) | 885.13 (5.30x) |
| Any ZeroUInt64Value WKT JSON parse | 529.21 | — | — | 2160.09 (4.08x) | 1911.30 (3.61x) |
| Any MaxUInt64Value WKT JSON stringify | 181.11 | — | — | 1585.30 (8.75x) | 1222.07 (6.75x) |
| Any MaxUInt64Value WKT JSON parse | 568.15 | — | — | 2835.85 (4.99x) | 2214.78 (3.90x) |
| Any Int32Value WKT JSON stringify | 165.76 | — | — | 1541.64 (9.30x) | 817.53 (4.93x) |
| Any Int32Value WKT JSON parse | 531.99 | — | — | 2666.77 (5.01x) | 1553.88 (2.92x) |
| Any Int32Value String WKT JSON parse | 542.53 | — | — | 2674.68 (4.93x) | 1766.82 (3.26x) |
| Any ZeroInt32Value WKT JSON stringify | 169.63 | — | — | 912.59 (5.38x) | 732.05 (4.32x) |
| Any ZeroInt32Value WKT JSON parse | 527.06 | — | — | 2148.19 (4.08x) | 1574.69 (2.99x) |
| Any NegativeInt32Value WKT JSON stringify | 172.62 | — | — | 1566.88 (9.08x) | 776.72 (4.50x) |
| Any NegativeInt32Value WKT JSON parse | 530.60 | — | — | 2683.48 (5.06x) | 1622.91 (3.06x) |
| Any MinInt32Value WKT JSON stringify | 182.29 | — | — | 1550.69 (8.51x) | 751.18 (4.12x) |
| Any MinInt32Value WKT JSON parse | 536.06 | — | — | 2699.49 (5.04x) | 1625.03 (3.03x) |
| Any MaxInt32Value WKT JSON stringify | 175.49 | — | — | 1542.41 (8.79x) | 787.59 (4.49x) |
| Any MaxInt32Value WKT JSON parse | 537.92 | — | — | 2677.08 (4.98x) | 1541.59 (2.87x) |
| Any UInt32Value WKT JSON stringify | 175.93 | — | — | 1556.12 (8.85x) | 786.61 (4.47x) |
| Any UInt32Value WKT JSON parse | 532.70 | — | — | 2672.13 (5.02x) | 1467.44 (2.75x) |
| Any UInt32Value String WKT JSON parse | 543.37 | — | — | 2682.22 (4.94x) | 1689.63 (3.11x) |
| Any ZeroUInt32Value WKT JSON stringify | 186.36 | — | — | 914.96 (4.91x) | 781.63 (4.19x) |
| Any ZeroUInt32Value WKT JSON parse | 526.73 | — | — | 2163.10 (4.11x) | 1461.89 (2.78x) |
| Any MaxUInt32Value WKT JSON stringify | 182.26 | — | — | 1550.29 (8.51x) | 756.94 (4.15x) |
| Any MaxUInt32Value WKT JSON parse | 540.49 | — | — | 2674.08 (4.95x) | 1436.46 (2.66x) |
| Any BoolValue WKT JSON stringify | 173.86 | — | — | 1528.45 (8.79x) | 739.35 (4.25x) |
| Any BoolValue WKT JSON parse | 479.59 | — | — | 2597.74 (5.42x) | 1266.81 (2.64x) |
| Any FalseBoolValue WKT JSON stringify | 176.95 | — | — | 916.35 (5.18x) | 706.38 (3.99x) |
| Any FalseBoolValue WKT JSON parse | 479.30 | — | — | 2137.69 (4.46x) | 1339.75 (2.80x) |
| Any StringValue WKT JSON stringify | 197.98 | — | — | 1578.77 (7.97x) | 827.00 (4.18x) |
| Any StringValue WKT JSON parse | 552.75 | — | — | 2679.94 (4.85x) | 1420.80 (2.57x) |
| Any StringValue Escape WKT JSON parse | 556.23 | — | — | 2706.29 (4.87x) | 1584.75 (2.85x) |
| Any EmptyStringValue WKT JSON stringify | 189.86 | — | — | 911.07 (4.80x) | 749.40 (3.95x) |
| Any EmptyStringValue WKT JSON parse | 521.41 | — | — | 2154.83 (4.13x) | 1326.81 (2.54x) |
| Any BytesValue WKT JSON stringify | 187.80 | — | — | 1596.65 (8.50x) | 813.86 (4.33x) |
| Any BytesValue WKT JSON parse | 561.05 | — | — | 2723.47 (4.85x) | 1371.03 (2.44x) |
| Any BytesValue URL WKT JSON parse | 581.23 | — | — | 2665.81 (4.59x) | 1406.57 (2.42x) |
| Any EmptyBytesValue WKT JSON stringify | 188.55 | — | — | 911.15 (4.83x) | 744.48 (3.95x) |
| Any EmptyBytesValue WKT JSON parse | 528.38 | — | — | 2143.43 (4.06x) | 1402.50 (2.65x) |
| Nested Any WKT JSON stringify | 301.86 | — | — | 2505.74 (8.30x) | 1525.17 (5.05x) |
| Nested Any WKT JSON parse | 866.11 | — | — | 4346.64 (5.02x) | 2886.19 (3.33x) |
| Duration JSON stringify | 58.17 | — | — | 968.69 (16.65x) | 336.70 (5.79x) |
| Duration JSON parse | 20.32 | — | — | 1453.84 (71.55x) | 402.47 (19.81x) |
| Duration Escape JSON parse | 38.78 | — | — | 1497.31 (38.61x) | 430.78 (11.11x) |
| PlusDuration JSON parse | 21.45 | — | — | 1455.27 (67.84x) | 386.97 (18.04x) |
| ShortFractionDuration JSON parse | 17.80 | — | — | 1415.32 (79.51x) | 374.70 (21.05x) |
| MicroDuration JSON stringify | 59.10 | — | — | 969.19 (16.40x) | 394.95 (6.68x) |
| MicroDuration JSON parse | 21.95 | — | — | 1461.20 (66.57x) | 362.90 (16.53x) |
| NanoDuration JSON stringify | 56.79 | — | — | 997.14 (17.56x) | 396.43 (6.98x) |
| NanoDuration JSON parse | 24.31 | — | — | 1474.68 (60.66x) | 389.44 (16.02x) |
| NegativeDuration JSON stringify | 58.09 | — | — | 1018.06 (17.53x) | 419.30 (7.22x) |
| NegativeDuration JSON parse | 21.07 | — | — | 1504.00 (71.38x) | 371.10 (17.61x) |
| FractionalNegativeDuration JSON stringify | 58.14 | — | — | 980.33 (16.86x) | 394.52 (6.79x) |
| FractionalNegativeDuration JSON parse | 20.31 | — | — | 1456.62 (71.72x) | 354.64 (17.46x) |
| MaxDuration JSON stringify | 49.21 | — | — | 855.20 (17.38x) | 387.82 (7.88x) |
| MaxDuration JSON parse | 32.36 | — | — | 1430.16 (44.20x) | 381.87 (11.80x) |
| MinDuration JSON stringify | 49.41 | — | — | 871.79 (17.64x) | 413.53 (8.37x) |
| MinDuration JSON parse | 33.01 | — | — | 1440.95 (43.65x) | 391.91 (11.87x) |
| ZeroDuration JSON stringify | 44.91 | — | — | 813.00 (18.10x) | 358.22 (7.98x) |
| ZeroDuration JSON parse | 14.24 | — | — | 1378.27 (96.79x) | 305.44 (21.45x) |
| FieldMask JSON stringify | 136.49 | — | — | 886.42 (6.49x) | 661.78 (4.85x) |
| FieldMask JSON parse | 139.80 | — | — | 1647.47 (11.78x) | 868.95 (6.22x) |
| FieldMask Escape JSON parse | 190.45 | — | — | 1702.42 (8.94x) | 1048.73 (5.51x) |
| EmptyFieldMask JSON stringify | 41.03 | — | — | 610.83 (14.89x) | 206.88 (5.04x) |
| EmptyFieldMask JSON parse | 4.78 | — | — | 943.15 (197.31x) | 172.03 (35.99x) |
| Timestamp JSON stringify | 96.79 | — | — | 1142.94 (11.81x) | 410.35 (4.24x) |
| Timestamp JSON parse | 46.05 | — | — | 1488.71 (32.33x) | 427.26 (9.28x) |
| Timestamp Escape JSON parse | 94.84 | — | — | 1518.17 (16.01x) | 506.20 (5.34x) |
| ShortFraction Timestamp JSON parse | 43.76 | — | — | 1481.44 (33.85x) | 402.20 (9.19x) |
| Micro Timestamp JSON stringify | 96.76 | — | — | 1141.81 (11.80x) | 426.28 (4.41x) |
| Micro Timestamp JSON parse | 47.98 | — | — | 1506.81 (31.40x) | 438.08 (9.13x) |
| Nano Timestamp JSON stringify | 94.10 | — | — | 1182.01 (12.56x) | 444.67 (4.73x) |
| Nano Timestamp JSON parse | 55.08 | — | — | 1527.84 (27.74x) | 439.34 (7.98x) |
| Offset Timestamp JSON parse | 52.88 | — | — | 1543.54 (29.19x) | 477.02 (9.02x) |
| PreEpoch Timestamp JSON stringify | 66.37 | — | — | 1071.40 (16.14x) | 409.60 (6.17x) |
| PreEpoch Timestamp JSON parse | 43.09 | — | — | 1467.38 (34.05x) | 409.51 (9.50x) |
| Max Timestamp JSON stringify | 78.92 | — | — | 1195.46 (15.15x) | 441.25 (5.59x) |
| Max Timestamp JSON parse | 53.65 | — | — | 1542.56 (28.75x) | 459.59 (8.57x) |
| Min Timestamp JSON stringify | 83.59 | — | — | 1067.61 (12.77x) | 412.39 (4.93x) |
| Min Timestamp JSON parse | 41.20 | — | — | 1468.66 (35.65x) | 412.10 (10.00x) |
| Empty JSON stringify | 20.63 | — | — | 493.53 (23.92x) | 79.89 (3.87x) |
| Empty JSON parse | 67.38 | — | — | 718.11 (10.66x) | 196.18 (2.91x) |
| Struct JSON stringify | 179.10 | — | — | 5679.64 (31.71x) | 3006.99 (16.79x) |
| Struct JSON parse | 839.68 | — | — | 10873.20 (12.95x) | 4757.36 (5.67x) |
| EmptyStruct JSON stringify | 40.60 | — | — | 700.41 (17.25x) | 361.98 (8.92x) |
| EmptyStruct JSON parse | 89.20 | — | — | 2025.79 (22.71x) | 362.40 (4.06x) |
| Value JSON stringify | 186.18 | — | — | 6604.04 (35.47x) | 3233.36 (17.37x) |
| Value JSON parse | 857.60 | — | — | 12119.90 (14.13x) | 5110.64 (5.96x) |
| NullValue JSON stringify | 40.11 | — | — | 1314.60 (32.77x) | 221.84 (5.53x) |
| NullValue JSON parse | 65.61 | — | — | 2452.90 (37.39x) | 329.35 (5.02x) |
| StringScalarValue JSON stringify | 47.41 | — | — | 1337.90 (28.22x) | 302.31 (6.38x) |
| StringScalarValue JSON parse | 135.46 | — | — | 2070.51 (15.29x) | 407.82 (3.01x) |
| EmptyStringScalarValue JSON stringify | 45.37 | — | — | 1326.54 (29.24x) | 290.89 (6.41x) |
| EmptyStringScalarValue JSON parse | 82.94 | — | — | 2062.90 (24.87x) | 350.61 (4.23x) |
| NumberValue JSON stringify | 73.18 | — | — | 1539.72 (21.04x) | 324.58 (4.44x) |
| NumberValue JSON parse | 127.89 | — | — | 2155.73 (16.86x) | 395.65 (3.09x) |
| ZeroNumberValue JSON stringify | 50.96 | — | — | 1496.56 (29.37x) | 295.94 (5.81x) |
| ZeroNumberValue JSON parse | 125.18 | — | — | 2085.39 (16.66x) | 376.32 (3.01x) |
| BoolScalarValue JSON stringify | 40.60 | — | — | 1307.42 (32.20x) | 218.45 (5.38x) |
| BoolScalarValue JSON parse | 65.41 | — | — | 1996.92 (30.53x) | 313.20 (4.79x) |
| FalseBoolScalarValue JSON stringify | 40.30 | — | — | 1310.13 (32.51x) | 215.11 (5.34x) |
| FalseBoolScalarValue JSON parse | 65.91 | — | — | 2003.34 (30.40x) | 322.80 (4.90x) |
| ListKindValue JSON stringify | 141.07 | — | — | 6105.92 (43.28x) | 2252.83 (15.97x) |
| ListKindValue JSON parse | 764.90 | — | — | 10419.40 (13.62x) | 4347.26 (5.68x) |
| EmptyStructKindValue JSON stringify | 56.65 | — | — | 1986.93 (35.07x) | 504.69 (8.91x) |
| EmptyStructKindValue JSON parse | 134.15 | — | — | 3929.03 (29.29x) | 686.60 (5.12x) |
| EmptyListKindValue JSON stringify | 54.84 | — | — | 1975.27 (36.02x) | 357.88 (6.53x) |
| EmptyListKindValue JSON parse | 179.12 | — | — | 4022.27 (22.46x) | 583.48 (3.26x) |
| ListValue JSON stringify | 262.78 | — | — | 4723.08 (17.97x) | 2111.61 (8.04x) |
| ListValue JSON parse | 884.24 | — | — | 8481.65 (9.59x) | 3724.71 (4.21x) |
| EmptyListValue JSON stringify | 40.00 | — | — | 694.11 (17.35x) | 175.91 (4.40x) |
| EmptyListValue JSON parse | 141.66 | — | — | 2253.75 (15.91x) | 285.95 (2.02x) |
| DoubleValue JSON stringify | 121.97 | — | — | 853.61 (7.00x) | 206.83 (1.70x) |
| DoubleValue JSON parse | 136.43 | — | — | 1227.53 (9.00x) | 259.84 (1.90x) |
| DoubleValue String JSON parse | 113.52 | — | — | 1183.97 (10.43x) | 368.17 (3.24x) |
| NegativeDoubleValue JSON stringify | 68.21 | — | — | 855.27 (12.54x) | 186.58 (2.74x) |
| NegativeDoubleValue JSON parse | 111.28 | — | — | 1234.16 (11.09x) | 291.89 (2.62x) |
| ZeroDoubleValue JSON stringify | 47.19 | — | — | 1464.24 (31.03x) | 143.61 (3.04x) |
| ZeroDoubleValue JSON parse | 108.18 | — | — | 1952.33 (18.05x) | 267.17 (2.47x) |
| DoubleValue NaN JSON stringify | 46.20 | — | — | 1100.93 (23.83x) | 143.09 (3.10x) |
| DoubleValue NaN JSON parse | 105.80 | — | — | 1820.36 (17.21x) | 270.90 (2.56x) |
| DoubleValue Infinity JSON stringify | 47.83 | — | — | 1073.00 (22.43x) | 116.01 (2.43x) |
| DoubleValue Infinity JSON parse | 105.64 | — | — | 1520.70 (14.40x) | 273.50 (2.59x) |
| DoubleValue NegativeInfinity JSON stringify | 47.91 | — | — | 1038.83 (21.68x) | 125.59 (2.62x) |
| DoubleValue NegativeInfinity JSON parse | 108.47 | — | — | 1803.50 (16.63x) | 270.52 (2.49x) |
| FloatValue JSON stringify | 70.97 | — | — | 1444.57 (20.35x) | 184.10 (2.59x) |
| FloatValue JSON parse | 111.44 | — | — | 2147.80 (19.27x) | 291.39 (2.61x) |
| FloatValue String JSON parse | 110.57 | — | — | 2043.12 (18.48x) | 345.97 (3.13x) |
| NegativeFloatValue JSON stringify | 71.28 | — | — | 1437.19 (20.16x) | 183.20 (2.57x) |
| NegativeFloatValue JSON parse | 112.59 | — | — | 2425.32 (21.54x) | 278.60 (2.47x) |
| ZeroFloatValue JSON stringify | 47.30 | — | — | 1395.10 (29.49x) | 125.99 (2.66x) |
| ZeroFloatValue JSON parse | 108.32 | — | — | 1941.73 (17.93x) | 270.59 (2.50x) |
| FloatValue NaN JSON stringify | 46.15 | — | — | 1020.84 (22.12x) | 117.25 (2.54x) |
| FloatValue NaN JSON parse | 104.85 | — | — | 1761.47 (16.80x) | 263.19 (2.51x) |
| FloatValue Infinity JSON stringify | 47.69 | — | — | 657.26 (13.78x) | 123.06 (2.58x) |
| FloatValue Infinity JSON parse | 106.00 | — | — | 1095.79 (10.34x) | 249.93 (2.36x) |
| FloatValue NegativeInfinity JSON stringify | 47.93 | — | — | 635.79 (13.26x) | 120.29 (2.51x) |
| FloatValue NegativeInfinity JSON parse | 107.92 | — | — | 1164.96 (10.79x) | 273.86 (2.54x) |
| Int64Value JSON stringify | 49.94 | — | — | 676.74 (13.55x) | 274.02 (5.49x) |
| Int64Value JSON parse | 126.92 | — | — | 1228.50 (9.68x) | 438.10 (3.45x) |
| Int64Value Number JSON parse | 128.19 | — | — | 1282.49 (10.00x) | 367.80 (2.87x) |
| ZeroInt64Value JSON stringify | 41.57 | — | — | 939.89 (22.61x) | 186.98 (4.50x) |
| ZeroInt64Value JSON parse | 105.14 | — | — | 1854.50 (17.64x) | 342.54 (3.26x) |
| NegativeInt64Value JSON stringify | 48.62 | — | — | 1021.48 (21.01x) | 264.34 (5.44x) |
| NegativeInt64Value JSON parse | 127.91 | — | — | 1222.60 (9.56x) | 446.27 (3.49x) |
| MinInt64Value JSON stringify | 49.57 | — | — | 681.11 (13.74x) | 279.05 (5.63x) |
| MinInt64Value JSON parse | 139.78 | — | — | 1252.11 (8.96x) | 474.73 (3.40x) |
| MaxInt64Value JSON stringify | 49.83 | — | — | 681.33 (13.67x) | 277.13 (5.56x) |
| MaxInt64Value JSON parse | 133.00 | — | — | 1241.27 (9.33x) | 475.87 (3.58x) |
| UInt64Value JSON stringify | 50.30 | — | — | 671.89 (13.36x) | 283.96 (5.65x) |
| UInt64Value JSON parse | 123.15 | — | — | 1211.95 (9.84x) | 451.54 (3.67x) |
| UInt64Value Number JSON parse | 127.15 | — | — | 1273.35 (10.01x) | 356.53 (2.80x) |
| ZeroUInt64Value JSON stringify | 41.66 | — | — | 606.58 (14.56x) | 184.59 (4.43x) |
| ZeroUInt64Value JSON parse | 103.61 | — | — | 1088.90 (10.51x) | 328.28 (3.17x) |
| MaxUInt64Value JSON stringify | 50.76 | — | — | 674.51 (13.29x) | 376.35 (7.41x) |
| MaxUInt64Value JSON parse | 135.02 | — | — | 1250.43 (9.26x) | 527.43 (3.91x) |
| Int32Value JSON stringify | 45.92 | — | — | 632.96 (13.78x) | 159.73 (3.48x) |
| Int32Value JSON parse | 117.63 | — | — | 1178.14 (10.02x) | 373.35 (3.17x) |
| Int32Value String JSON parse | 114.60 | — | — | 1122.24 (9.79x) | 444.70 (3.88x) |
| ZeroInt32Value JSON stringify | 45.96 | — | — | 611.32 (13.30x) | 151.43 (3.29x) |
| ZeroInt32Value JSON parse | 113.44 | — | — | 1150.24 (10.14x) | 263.85 (2.33x) |
| NegativeInt32Value JSON stringify | 45.95 | — | — | 635.81 (13.84x) | 156.21 (3.40x) |
| NegativeInt32Value JSON parse | 116.95 | — | — | 1184.81 (10.13x) | 324.89 (2.78x) |
| MinInt32Value JSON stringify | 46.67 | — | — | 637.15 (13.65x) | 151.28 (3.24x) |
| MinInt32Value JSON parse | 122.90 | — | — | 1207.84 (9.83x) | 346.70 (2.82x) |
| MaxInt32Value JSON stringify | 46.99 | — | — | 632.09 (13.45x) | 136.03 (2.89x) |
| MaxInt32Value JSON parse | 124.24 | — | — | 1202.44 (9.68x) | 309.31 (2.49x) |
| UInt32Value JSON stringify | 45.91 | — | — | 628.67 (13.69x) | 159.58 (3.48x) |
| UInt32Value JSON parse | 117.64 | — | — | 1178.30 (10.02x) | 339.90 (2.89x) |
| UInt32Value String JSON parse | 114.70 | — | — | 1122.41 (9.79x) | 412.58 (3.60x) |
| ZeroUInt32Value JSON stringify | 45.92 | — | — | 616.23 (13.42x) | 127.29 (2.77x) |
| ZeroUInt32Value JSON parse | 113.29 | — | — | 1151.88 (10.17x) | 269.50 (2.38x) |
| MaxUInt32Value JSON stringify | 46.65 | — | — | 632.32 (13.55x) | 140.62 (3.01x) |
| MaxUInt32Value JSON parse | 123.01 | — | — | 1211.06 (9.85x) | 320.82 (2.61x) |
| BoolValue JSON stringify | 44.09 | — | — | 623.92 (14.15x) | 119.52 (2.71x) |
| BoolValue JSON parse | 59.81 | — | — | 1054.31 (17.63x) | 236.87 (3.96x) |
| FalseBoolValue JSON stringify | 44.10 | — | — | 613.03 (13.90x) | 131.41 (2.98x) |
| FalseBoolValue JSON parse | 60.22 | — | — | 1065.08 (17.69x) | 221.29 (3.67x) |
| StringValue JSON stringify | 51.74 | — | — | 654.39 (12.65x) | 193.98 (3.75x) |
| StringValue JSON parse | 121.49 | — | — | 1134.81 (9.34x) | 276.05 (2.27x) |
| StringValue Escape JSON parse | 129.70 | — | — | 1169.46 (9.02x) | 347.12 (2.68x) |
| EmptyStringValue JSON stringify | 48.42 | — | — | 622.19 (12.85x) | 184.65 (3.81x) |
| EmptyStringValue JSON parse | 66.30 | — | — | 1106.25 (16.69x) | 219.01 (3.30x) |
| BytesValue JSON stringify | 49.89 | — | — | 671.33 (13.46x) | 200.61 (4.02x) |
| BytesValue JSON parse | 123.99 | — | — | 1166.11 (9.40x) | 321.57 (2.59x) |
| BytesValue URL JSON parse | 140.18 | — | — | 1156.67 (8.25x) | 297.04 (2.12x) |
| EmptyBytesValue JSON stringify | 41.61 | — | — | 645.45 (15.51x) | 176.57 (4.24x) |
| EmptyBytesValue JSON parse | 67.68 | — | — | 1129.47 (16.69x) | 246.05 (3.64x) |
| TextFormat format | 177.35 | — | — | 2580.34 (14.55x) | 2337.38 (13.18x) |
| TextFormat parse | 709.90 | — | — | 4997.37 (7.04x) | 6228.36 (8.77x) |
| packed fixed32 encode | 2.00 | 550.15 (275.07x) | 539.45 (269.73x) | 43.73 (21.86x) | 403.98 (201.99x) |
| packed fixed32 decode | 4.53 | 1067.36 (235.62x) | 1904.04 (420.32x) | 49.45 (10.92x) | 1690.98 (373.28x) |
| packed fixed64 encode | 2.01 | 576.38 (286.76x) | 573.26 (285.20x) | 75.80 (37.71x) | 402.57 (200.28x) |
| packed fixed64 decode | 4.52 | 1033.46 (228.64x) | 7969.87 (1763.25x) | 79.85 (17.67x) | 2731.55 (604.33x) |
| packed sfixed32 encode | 2.00 | 554.05 (277.02x) | 553.07 (276.54x) | 44.13 (22.07x) | 439.63 (219.81x) |
| packed sfixed32 decode | 4.53 | 1041.82 (229.98x) | 1952.91 (431.11x) | 48.96 (10.81x) | 1713.26 (378.20x) |
| packed sfixed64 encode | 2.01 | 576.01 (286.57x) | 561.38 (279.29x) | 75.75 (37.69x) | 397.48 (197.75x) |
| packed sfixed64 decode | 4.52 | 1124.39 (248.76x) | 7904.64 (1748.81x) | 79.49 (17.59x) | 2342.85 (518.33x) |
| packed float encode | 2.00 | 820.57 (410.29x) | 541.72 (270.86x) | 44.33 (22.17x) | 420.90 (210.45x) |
| packed float decode | 4.54 | 1054.17 (232.20x) | 2100.13 (462.58x) | 48.96 (10.78x) | 1652.07 (363.89x) |
| packed double encode | 2.06 | 830.53 (403.17x) | 561.73 (272.68x) | 75.73 (36.76x) | 367.37 (178.33x) |
| packed double decode | 4.65 | 961.95 (206.87x) | 2045.73 (439.94x) | 79.60 (17.12x) | 2580.81 (555.01x) |
| packed uint64 encode | 1293.61 | 4615.21 (3.57x) | 4010.34 (3.10x) | 2120.07 (1.64x) | 3446.70 (2.66x) |
| packed uint64 decode | 1780.50 | 2811.66 (1.58x) | 8847.39 (4.97x) | 2801.53 (1.57x) | 13135.93 (7.38x) |
| packed uint32 encode | 932.25 | 3656.06 (3.92x) | 3258.99 (3.50x) | 1729.38 (1.86x) | 2881.18 (3.09x) |
| packed uint32 decode | 1309.32 | 2434.47 (1.86x) | 3268.00 (2.50x) | 1988.24 (1.52x) | 7277.70 (5.56x) |
| packed int64 encode | 1347.14 | 11013.83 (8.18x) | 6099.59 (4.53x) | 2889.99 (2.15x) | 4103.90 (3.05x) |
| packed int64 decode | 2742.42 | 3383.55 (1.23x) | 10256.49 (3.74x) | 4677.94 (1.71x) | 13447.94 (4.90x) |
| packed sint32 encode | 780.81 | 3049.23 (3.91x) | 2821.31 (3.61x) | 1542.96 (1.98x) | 3383.82 (4.33x) |
| packed sint32 decode | 934.44 | 2547.17 (2.73x) | 3209.04 (3.43x) | 1145.17 (1.23x) | 3751.19 (4.01x) |
| packed sint64 encode | 1420.58 | 4930.56 (3.47x) | 4302.55 (3.03x) | 2421.74 (1.70x) | 4129.11 (2.91x) |
| packed sint64 decode | 2031.62 | 3069.23 (1.51x) | 9648.22 (4.75x) | 2936.95 (1.45x) | 11100.78 (5.46x) |
| packed bool encode | 2.01 | 1328.81 (661.10x) | 519.50 (258.46x) | 15.87 (7.90x) | 3180.32 (1582.25x) |
| packed bool decode | 263.20 | 1520.99 (5.78x) | 2550.52 (9.69x) | 804.63 (3.06x) | 3077.23 (11.69x) |
| packed enum encode | 582.96 | 2718.18 (4.66x) | 1805.10 (3.10x) | 1090.04 (1.87x) | 5071.24 (8.70x) |
| packed enum decode | 162.51 | 1567.27 (9.64x) | 2862.02 (17.61x) | 699.33 (4.30x) | 2620.95 (16.13x) |
| large map encode | 4052.63 | 16573.41 (4.09x) | 9731.48 (2.40x) | 22293.30 (5.50x) | 214533.48 (52.94x) |
| shuffled large map deterministic binary encode | 27435.59 | — | — | 104186.00 (3.80x) | 406143.75 (14.80x) |
| large map decode | 25229.55 | 90891.31 (3.60x) | 89603.91 (3.55x) | 93173.20 (3.69x) | 425793.05 (16.88x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound `Duration`, non-empty and empty `Struct`, object/list/scalar `Value` (including default-like scalar and empty object/list kinds),
`FieldMask` (non-empty, escaped JSON parse input, and empty), escaped-input parse/short-fraction parse/micro/nano/offset/min/pre/post/max-bound `Timestamp`, `Empty`, min/zero/positive/number-input parse/negative/max `Int64Value`, negative/zero/positive finite/string-input parse `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), negative/zero/positive finite/string-input parse `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), zero/normal/number-input parse/max `UInt64Value`, min/zero/positive/string-input parse/negative/max `Int32Value`, zero/normal/string-input parse/max `UInt32Value`, true/false `BoolValue`, non-empty/escape-input parse/empty `StringValue`, base64/base64url parse/empty `BytesValue`, and recursive nested `Any` payloads), direct zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound Duration, non-empty/escaped-input parse/empty FieldMask, and escaped-input parse/short-fraction parse/micro/nano/offset/min/pre/post/max-bound Timestamp WKT JSON plus other direct WKT JSON, including empty `Struct` and empty `ListValue`, TextFormat, packed scalars, large bytes,
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
