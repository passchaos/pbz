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

Latest accepted comparison (`/tmp/pbz-compare-fieldmask-escape-json-isolated.log`,
summarized in `/tmp/pbz-summary-fieldmask-escape-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 21.05 | 104.94 (4.99x) | 66.21 (3.15x) | 109.68 (5.21x) | 842.37 (40.02x) |
| binary decode | 97.99 | 244.19 (2.49x) | 232.56 (2.37x) | 209.21 (2.14x) | 887.58 (9.06x) |
| unknown fields count by number | 3.57 | — | — | 161.93 (45.36x) | — |
| deterministic binary encode | 59.74 | — | — | 125.19 (2.10x) | 1042.42 (17.45x) |
| scalarmix encode | 19.70 | 100.35 (5.09x) | 48.20 (2.45x) | 29.95 (1.52x) | 222.82 (11.31x) |
| scalarmix decode | 34.16 | 133.42 (3.91x) | 174.96 (5.12x) | 82.09 (2.40x) | 350.30 (10.25x) |
| textbytes encode | 9.53 | 79.24 (8.31x) | 33.34 (3.50x) | 118.87 (12.47x) | 145.59 (15.28x) |
| textbytes decode | 46.10 | 378.83 (8.22x) | 236.10 (5.12x) | 179.57 (3.90x) | 679.88 (14.75x) |
| largebytes encode | 25.81 | 2723.70 (105.53x) | 2672.46 (103.54x) | 2676.81 (103.71x) | 2717.77 (105.30x) |
| largebytes decode | 93.03 | 5521.22 (59.35x) | 3005.69 (32.31x) | 2727.99 (29.32x) | 46608.64 (501.01x) |
| presencemix encode | 19.30 | 55.34 (2.87x) | 27.62 (1.43x) | 57.08 (2.96x) | 230.87 (11.96x) |
| presencemix decode | 56.67 | 135.11 (2.38x) | 109.04 (1.92x) | 163.05 (2.88x) | 466.48 (8.23x) |
| complex encode | 55.25 | 138.67 (2.51x) | 96.33 (1.74x) | 173.88 (3.15x) | 912.11 (16.51x) |
| complex decode | 170.36 | 396.16 (2.33x) | 340.19 (2.00x) | 396.56 (2.33x) | 1291.48 (7.58x) |
| complex deterministic binary encode | 100.88 | — | — | 179.89 (1.78x) | 1118.68 (11.09x) |
| complex JSON stringify | 275.01 | — | — | 4879.13 (17.74x) | 6549.94 (23.82x) |
| complex JSON parse | 2378.95 | — | — | 11879.20 (4.99x) | 8008.85 (3.37x) |
| complex TextFormat format | 249.71 | — | — | 3782.16 (15.15x) | 8208.09 (32.87x) |
| complex TextFormat parse | 1888.05 | — | — | 6957.03 (3.68x) | 8183.22 (4.33x) |
| packed int32 encode | 623.38 | 3160.13 (5.07x) | 2512.06 (4.03x) | 1231.22 (1.98x) | 2843.31 (4.56x) |
| packed int32 decode | 699.71 | 1908.86 (2.73x) | 3215.91 (4.60x) | 945.66 (1.35x) | 3877.57 (5.54x) |
| JSON stringify | 154.77 | — | — | 3017.51 (19.50x) | 2132.74 (13.78x) |
| JSON parse | 1521.83 | — | — | 7448.02 (4.89x) | 4571.82 (3.00x) |
| Any WKT JSON stringify | 136.42 | — | — | 1905.24 (13.97x) | 979.47 (7.18x) |
| Any WKT JSON parse | 526.11 | — | — | 2987.39 (5.68x) | 1720.80 (3.27x) |
| Any PlusDuration WKT JSON parse | 523.81 | — | — | 3016.08 (5.76x) | 1530.84 (2.92x) |
| Any ShortFractionDuration WKT JSON parse | 521.90 | — | — | 2958.61 (5.67x) | 1479.01 (2.83x) |
| Any MicroDuration WKT JSON stringify | 131.73 | — | — | 1893.68 (14.38x) | 1027.66 (7.80x) |
| Any MicroDuration WKT JSON parse | 528.53 | — | — | 3006.82 (5.69x) | 1475.71 (2.79x) |
| Any NanoDuration WKT JSON stringify | 133.69 | — | — | 1917.25 (14.34x) | 1350.21 (10.10x) |
| Any NanoDuration WKT JSON parse | 533.78 | — | — | 3017.89 (5.65x) | 1705.52 (3.20x) |
| Any NegativeDuration WKT JSON stringify | 134.23 | — | — | 1932.74 (14.40x) | 1138.33 (8.48x) |
| Any NegativeDuration WKT JSON parse | 530.90 | — | — | 3088.87 (5.82x) | 1551.30 (2.92x) |
| Any FractionalNegativeDuration WKT JSON stringify | 127.44 | — | — | 1912.12 (15.00x) | 1300.59 (10.21x) |
| Any FractionalNegativeDuration WKT JSON parse | 518.60 | — | — | 3054.46 (5.89x) | 2637.76 (5.09x) |
| Any MaxDuration WKT JSON stringify | 119.72 | — | — | 1746.51 (14.59x) | 2135.87 (17.84x) |
| Any MaxDuration WKT JSON parse | 533.31 | — | — | 2966.28 (5.56x) | 1800.76 (3.38x) |
| Any MinDuration WKT JSON stringify | 118.92 | — | — | 1791.01 (15.06x) | 989.82 (8.32x) |
| Any MinDuration WKT JSON parse | 531.80 | — | — | 3034.13 (5.71x) | 1676.95 (3.15x) |
| Any ZeroDuration WKT JSON stringify | 106.77 | — | — | 910.11 (8.52x) | 1056.80 (9.90x) |
| Any ZeroDuration WKT JSON parse | 465.82 | — | — | 2241.70 (4.81x) | 1617.61 (3.47x) |
| Any FieldMask WKT JSON stringify | 239.64 | — | — | 1740.13 (7.26x) | 1869.77 (7.80x) |
| Any FieldMask WKT JSON parse | 705.13 | — | — | 3301.48 (4.68x) | 2164.15 (3.07x) |
| Any FieldMask Escape WKT JSON parse | 727.52 | — | — | 3372.11 (4.64x) | 2881.86 (3.96x) |
| Any EmptyFieldMask WKT JSON stringify | 117.00 | — | — | 953.84 (8.15x) | 747.87 (6.39x) |
| Any EmptyFieldMask WKT JSON parse | 438.37 | — | — | 2166.33 (4.94x) | 1241.73 (2.83x) |
| Any Timestamp WKT JSON stringify | 180.68 | — | — | 2038.58 (11.28x) | 1115.66 (6.17x) |
| Any Timestamp WKT JSON parse | 562.47 | — | — | 3007.66 (5.35x) | 1603.53 (2.85x) |
| Any ShortFraction Timestamp WKT JSON parse | 560.46 | — | — | 3011.33 (5.37x) | 1615.26 (2.88x) |
| Any Micro Timestamp WKT JSON stringify | 178.97 | — | — | 2050.44 (11.46x) | 1034.31 (5.78x) |
| Any Micro Timestamp WKT JSON parse | 567.34 | — | — | 3983.76 (7.02x) | 2526.11 (4.45x) |
| Any Nano Timestamp WKT JSON stringify | 177.73 | — | — | 2277.59 (12.81x) | 1026.88 (5.78x) |
| Any Nano Timestamp WKT JSON parse | 572.75 | — | — | 3056.52 (5.34x) | 2273.05 (3.97x) |
| Any Offset Timestamp WKT JSON parse | 581.85 | — | — | 3058.12 (5.26x) | 1957.71 (3.36x) |
| Any PreEpoch Timestamp WKT JSON stringify | 145.30 | — | — | 1950.70 (13.43x) | 1100.72 (7.58x) |
| Any PreEpoch Timestamp WKT JSON parse | 554.73 | — | — | 3055.81 (5.51x) | 2264.16 (4.08x) |
| Any Max Timestamp WKT JSON stringify | 162.24 | — | — | 2107.42 (12.99x) | 1066.76 (6.58x) |
| Any Max Timestamp WKT JSON parse | 573.75 | — | — | 3107.88 (5.42x) | 1839.33 (3.21x) |
| Any Min Timestamp WKT JSON stringify | 157.71 | — | — | 1961.05 (12.43x) | 1480.43 (9.39x) |
| Any Min Timestamp WKT JSON parse | 549.31 | — | — | 3049.35 (5.55x) | 2121.42 (3.86x) |
| Any Empty WKT JSON stringify | 91.99 | — | — | 909.34 (9.89x) | 749.87 (8.15x) |
| Any Empty WKT JSON parse | 333.44 | — | — | 2120.71 (6.36x) | 1245.07 (3.73x) |
| Any Struct WKT JSON stringify | 634.00 | — | — | 5832.00 (9.20x) | 6673.76 (10.53x) |
| Any Struct WKT JSON parse | 1746.04 | — | — | 11099.00 (6.36x) | 10614.31 (6.08x) |
| Any EmptyStruct WKT JSON stringify | 121.08 | — | — | 924.62 (7.64x) | 1340.76 (11.07x) |
| Any EmptyStruct WKT JSON parse | 439.44 | — | — | 2233.59 (5.08x) | 2415.86 (5.50x) |
| Any Value WKT JSON stringify | 674.67 | — | — | 5872.09 (8.70x) | 6577.85 (9.75x) |
| Any Value WKT JSON parse | 1837.02 | — | — | 11327.70 (6.17x) | 12463.30 (6.78x) |
| Any NullValue WKT JSON stringify | 130.07 | — | — | 2272.59 (17.47x) | 1054.22 (8.11x) |
| Any NullValue WKT JSON parse | 463.44 | — | — | 4078.21 (8.80x) | 1460.28 (3.15x) |
| Any StringScalarValue WKT JSON stringify | 150.85 | — | — | 2295.58 (15.22x) | 1381.72 (9.16x) |
| Any StringScalarValue WKT JSON parse | 507.75 | — | — | 3664.90 (7.22x) | 2185.43 (4.30x) |
| Any EmptyStringScalarValue WKT JSON stringify | 138.58 | — | — | 2273.88 (16.41x) | 920.08 (6.64x) |
| Any EmptyStringScalarValue WKT JSON parse | 477.12 | — | — | 3602.51 (7.55x) | 2891.23 (6.06x) |
| Any NumberValue WKT JSON stringify | 179.46 | — | — | 2520.54 (14.05x) | 1224.00 (6.82x) |
| Any NumberValue WKT JSON parse | 498.63 | — | — | 3679.85 (7.38x) | 1553.06 (3.11x) |
| Any ZeroNumberValue WKT JSON stringify | 145.14 | — | — | 2482.48 (17.10x) | 998.70 (6.88x) |
| Any ZeroNumberValue WKT JSON parse | 496.77 | — | — | 3615.38 (7.28x) | 1621.37 (3.26x) |
| Any BoolScalarValue WKT JSON stringify | 131.90 | — | — | 2247.62 (17.04x) | 1270.08 (9.63x) |
| Any BoolScalarValue WKT JSON parse | 457.23 | — | — | 3577.48 (7.82x) | 1664.72 (3.64x) |
| Any FalseBoolScalarValue WKT JSON stringify | 134.77 | — | — | 2258.48 (16.76x) | 1118.65 (8.30x) |
| Any FalseBoolScalarValue WKT JSON parse | 455.06 | — | — | 3585.92 (7.88x) | 2364.49 (5.20x) |
| Any ListKindValue WKT JSON stringify | 509.80 | — | — | 5756.37 (11.29x) | 6123.21 (12.01x) |
| Any ListKindValue WKT JSON parse | 1387.89 | — | — | 9996.04 (7.20x) | 9952.51 (7.17x) |
| Any EmptyStructKindValue WKT JSON stringify | 147.43 | — | — | 2905.62 (19.71x) | 1698.72 (11.52x) |
| Any EmptyStructKindValue WKT JSON parse | 491.76 | — | — | 5384.04 (10.95x) | 3264.65 (6.64x) |
| Any EmptyListKindValue WKT JSON stringify | 144.25 | — | — | 2895.88 (20.08x) | 1053.43 (7.30x) |
| Any EmptyListKindValue WKT JSON parse | 500.19 | — | — | 4437.04 (8.87x) | 2477.99 (4.95x) |
| Any DoubleValue WKT JSON stringify | 191.71 | — | — | 1834.04 (9.57x) | 859.58 (4.48x) |
| Any DoubleValue WKT JSON parse | 523.02 | — | — | 2737.69 (5.23x) | 1440.41 (2.75x) |
| Any DoubleValue String WKT JSON parse | 528.40 | — | — | 2740.27 (5.19x) | 1577.81 (2.99x) |
| Any NegativeDoubleValue WKT JSON stringify | 193.72 | — | — | 1835.28 (9.47x) | 772.68 (3.99x) |
| Any NegativeDoubleValue WKT JSON parse | 525.58 | — | — | 2744.78 (5.22x) | 1373.48 (2.61x) |
| Any ZeroDoubleValue WKT JSON stringify | 163.56 | — | — | 915.78 (5.60x) | 859.81 (5.26x) |
| Any ZeroDoubleValue WKT JSON parse | 516.28 | — | — | 2153.65 (4.17x) | 1433.26 (2.78x) |
| Any DoubleValue NaN WKT JSON stringify | 154.61 | — | — | 1595.58 (10.32x) | 927.40 (6.00x) |
| Any DoubleValue NaN WKT JSON parse | 512.74 | — | — | 2645.36 (5.16x) | 1299.19 (2.53x) |
| Any DoubleValue Infinity WKT JSON stringify | 158.27 | — | — | 1585.60 (10.02x) | 739.99 (4.68x) |
| Any DoubleValue Infinity WKT JSON parse | 515.55 | — | — | 2692.85 (5.22x) | 1745.81 (3.39x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 160.70 | — | — | 1591.40 (9.90x) | 694.94 (4.32x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 518.14 | — | — | 2714.63 (5.24x) | 1306.99 (2.52x) |
| Any FloatValue WKT JSON stringify | 197.39 | — | — | 1741.68 (8.82x) | 1491.41 (7.56x) |
| Any FloatValue WKT JSON parse | 520.73 | — | — | 2738.75 (5.26x) | 1333.29 (2.56x) |
| Any FloatValue String WKT JSON parse | 527.94 | — | — | 2726.41 (5.16x) | 2455.16 (4.65x) |
| Any NegativeFloatValue WKT JSON stringify | 196.94 | — | — | 1727.78 (8.77x) | 740.67 (3.76x) |
| Any NegativeFloatValue WKT JSON parse | 522.43 | — | — | 2762.12 (5.29x) | 1662.27 (3.18x) |
| Any ZeroFloatValue WKT JSON stringify | 167.54 | — | — | 915.41 (5.46x) | 698.61 (4.17x) |
| Any ZeroFloatValue WKT JSON parse | 523.87 | — | — | 2143.24 (4.09x) | 1303.77 (2.49x) |
| Any FloatValue NaN WKT JSON stringify | 158.39 | — | — | 1639.10 (10.35x) | 732.41 (4.62x) |
| Any FloatValue NaN WKT JSON parse | 515.19 | — | — | 2622.61 (5.09x) | 1438.68 (2.79x) |
| Any FloatValue Infinity WKT JSON stringify | 164.43 | — | — | 1543.73 (9.39x) | 722.34 (4.39x) |
| Any FloatValue Infinity WKT JSON parse | 518.36 | — | — | 2657.39 (5.13x) | 1321.42 (2.55x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 164.18 | — | — | 1547.12 (9.42x) | 720.44 (4.39x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 522.77 | — | — | 2655.01 (5.08x) | 1422.10 (2.72x) |
| Any Int64Value WKT JSON stringify | 169.58 | — | — | 1574.40 (9.28x) | 1732.01 (10.21x) |
| Any Int64Value WKT JSON parse | 545.70 | — | — | 2780.44 (5.10x) | 2218.71 (4.07x) |
| Any Int64Value Number WKT JSON parse | 543.18 | — | — | 2740.80 (5.05x) | 2194.61 (4.04x) |
| Any ZeroInt64Value WKT JSON stringify | 158.17 | — | — | 919.91 (5.82x) | 910.87 (5.76x) |
| Any ZeroInt64Value WKT JSON parse | 518.63 | — | — | 2161.26 (4.17x) | 1656.56 (3.19x) |
| Any NegativeInt64Value WKT JSON stringify | 182.59 | — | — | 1583.82 (8.67x) | 1570.65 (8.60x) |
| Any NegativeInt64Value WKT JSON parse | 550.42 | — | — | 2799.41 (5.09x) | 1640.83 (2.98x) |
| Any MinInt64Value WKT JSON stringify | 292.27 | — | — | 1570.75 (5.37x) | 849.31 (2.91x) |
| Any MinInt64Value WKT JSON parse | 924.90 | — | — | 2807.40 (3.04x) | 1673.03 (1.81x) |
| Any MaxInt64Value WKT JSON stringify | 200.86 | — | — | 1571.91 (7.83x) | 1113.89 (5.55x) |
| Any MaxInt64Value WKT JSON parse | 779.40 | — | — | 2798.14 (3.59x) | 3026.50 (3.88x) |
| Any UInt64Value WKT JSON stringify | 243.91 | — | — | 1589.15 (6.52x) | 904.53 (3.71x) |
| Any UInt64Value WKT JSON parse | 563.07 | — | — | 2784.16 (4.94x) | 3058.22 (5.43x) |
| Any UInt64Value Number WKT JSON parse | 557.63 | — | — | 2761.64 (4.95x) | 1610.88 (2.89x) |
| Any ZeroUInt64Value WKT JSON stringify | 171.10 | — | — | 917.86 (5.36x) | 760.86 (4.45x) |
| Any ZeroUInt64Value WKT JSON parse | 534.24 | — | — | 2152.57 (4.03x) | 1466.34 (2.74x) |
| Any MaxUInt64Value WKT JSON stringify | 183.60 | — | — | 1569.88 (8.55x) | 845.10 (4.60x) |
| Any MaxUInt64Value WKT JSON parse | 569.74 | — | — | 2834.09 (4.97x) | 1824.28 (3.20x) |
| Any Int32Value WKT JSON stringify | 167.02 | — | — | 1545.11 (9.25x) | 715.68 (4.28x) |
| Any Int32Value WKT JSON parse | 533.21 | — | — | 2659.12 (4.99x) | 1434.50 (2.69x) |
| Any Int32Value String WKT JSON parse | 540.12 | — | — | 2669.84 (4.94x) | 1455.63 (2.70x) |
| Any ZeroInt32Value WKT JSON stringify | 165.88 | — | — | 915.12 (5.52x) | 1290.71 (7.78x) |
| Any ZeroInt32Value WKT JSON parse | 527.75 | — | — | 2143.08 (4.06x) | 1451.93 (2.75x) |
| Any NegativeInt32Value WKT JSON stringify | 172.27 | — | — | 1560.78 (9.06x) | 733.54 (4.26x) |
| Any NegativeInt32Value WKT JSON parse | 533.92 | — | — | 2685.11 (5.03x) | 1376.45 (2.58x) |
| Any MinInt32Value WKT JSON stringify | 175.08 | — | — | 1544.98 (8.82x) | 769.72 (4.40x) |
| Any MinInt32Value WKT JSON parse | 542.19 | — | — | 2706.24 (4.99x) | 1517.25 (2.80x) |
| Any MaxInt32Value WKT JSON stringify | 176.00 | — | — | 1549.18 (8.80x) | 714.86 (4.06x) |
| Any MaxInt32Value WKT JSON parse | 537.98 | — | — | 2667.22 (4.96x) | 1389.24 (2.58x) |
| Any UInt32Value WKT JSON stringify | 176.55 | — | — | 1548.61 (8.77x) | 708.38 (4.01x) |
| Any UInt32Value WKT JSON parse | 536.17 | — | — | 2663.06 (4.97x) | 1755.16 (3.27x) |
| Any UInt32Value String WKT JSON parse | 538.89 | — | — | 2668.28 (4.95x) | 1455.50 (2.70x) |
| Any ZeroUInt32Value WKT JSON stringify | 171.76 | — | — | 915.92 (5.33x) | 719.60 (4.19x) |
| Any ZeroUInt32Value WKT JSON parse | 532.20 | — | — | 2154.66 (4.05x) | 1932.29 (3.63x) |
| Any MaxUInt32Value WKT JSON stringify | 180.59 | — | — | 1552.80 (8.60x) | 1337.96 (7.41x) |
| Any MaxUInt32Value WKT JSON parse | 546.45 | — | — | 2677.78 (4.90x) | 1404.08 (2.57x) |
| Any BoolValue WKT JSON stringify | 174.37 | — | — | 1522.13 (8.73x) | 709.58 (4.07x) |
| Any BoolValue WKT JSON parse | 489.50 | — | — | 2589.71 (5.29x) | 1241.18 (2.54x) |
| Any FalseBoolValue WKT JSON stringify | 175.18 | — | — | 913.49 (5.21x) | 760.06 (4.34x) |
| Any FalseBoolValue WKT JSON parse | 486.71 | — | — | 2136.67 (4.39x) | 1236.47 (2.54x) |
| Any StringValue WKT JSON stringify | 202.08 | — | — | 1576.98 (7.80x) | 1116.10 (5.52x) |
| Any StringValue WKT JSON parse | 547.76 | — | — | 2678.67 (4.89x) | 2903.80 (5.30x) |
| Any StringValue Escape WKT JSON parse | 553.59 | — | — | 2690.01 (4.86x) | 1565.98 (2.83x) |
| Any EmptyStringValue WKT JSON stringify | 191.80 | — | — | 913.86 (4.76x) | 794.30 (4.14x) |
| Any EmptyStringValue WKT JSON parse | 515.65 | — | — | 2157.76 (4.18x) | 1307.38 (2.54x) |
| Any BytesValue WKT JSON stringify | 186.09 | — | — | 1585.87 (8.52x) | 859.69 (4.62x) |
| Any BytesValue WKT JSON parse | 563.72 | — | — | 2692.21 (4.78x) | 2687.28 (4.77x) |
| Any BytesValue URL WKT JSON parse | 583.97 | — | — | 2678.26 (4.59x) | 1571.54 (2.69x) |
| Any EmptyBytesValue WKT JSON stringify | 181.95 | — | — | 916.43 (5.04x) | 738.41 (4.06x) |
| Any EmptyBytesValue WKT JSON parse | 529.32 | — | — | 2149.66 (4.06x) | 1452.36 (2.74x) |
| Nested Any WKT JSON stringify | 302.86 | — | — | 2566.85 (8.48x) | 2219.39 (7.33x) |
| Nested Any WKT JSON parse | 863.65 | — | — | 4263.20 (4.94x) | 2854.17 (3.30x) |
| Duration JSON stringify | 59.43 | — | — | 961.91 (16.19x) | 378.21 (6.36x) |
| Duration JSON parse | 7.60 | — | — | 1447.22 (190.42x) | 470.32 (61.88x) |
| PlusDuration JSON parse | 7.83 | — | — | 1524.08 (194.65x) | 644.82 (82.35x) |
| ShortFractionDuration JSON parse | 6.62 | — | — | 1557.87 (235.33x) | 482.47 (72.88x) |
| MicroDuration JSON stringify | 60.66 | — | — | 974.31 (16.06x) | 388.07 (6.40x) |
| MicroDuration JSON parse | 9.80 | — | — | 1469.40 (149.94x) | 908.57 (92.71x) |
| NanoDuration JSON stringify | 57.13 | — | — | 998.50 (17.48x) | 403.63 (7.07x) |
| NanoDuration JSON parse | 12.40 | — | — | 1474.94 (118.95x) | 583.49 (47.06x) |
| NegativeDuration JSON stringify | 60.76 | — | — | 999.82 (16.46x) | 582.42 (9.59x) |
| NegativeDuration JSON parse | 7.90 | — | — | 1508.56 (190.96x) | 693.18 (87.74x) |
| FractionalNegativeDuration JSON stringify | 60.13 | — | — | 971.47 (16.16x) | 685.19 (11.40x) |
| FractionalNegativeDuration JSON parse | 7.90 | — | — | 1497.24 (189.52x) | 714.52 (90.45x) |
| MaxDuration JSON stringify | 49.71 | — | — | 873.96 (17.58x) | 390.63 (7.86x) |
| MaxDuration JSON parse | 22.22 | — | — | 1448.17 (65.17x) | 363.93 (16.38x) |
| MinDuration JSON stringify | 50.02 | — | — | 866.67 (17.33x) | 641.21 (12.82x) |
| MinDuration JSON parse | 22.59 | — | — | 1458.03 (64.54x) | 853.13 (37.77x) |
| ZeroDuration JSON stringify | 44.88 | — | — | 823.48 (18.35x) | 366.68 (8.17x) |
| ZeroDuration JSON parse | 5.57 | — | — | 1371.07 (246.15x) | 543.60 (97.59x) |
| FieldMask JSON stringify | 70.53 | — | — | 895.51 (12.70x) | 1588.22 (22.52x) |
| FieldMask JSON parse | 264.85 | — | — | 1667.12 (6.29x) | 1538.59 (5.81x) |
| FieldMask Escape JSON parse | 275.52 | — | — | 1726.06 (6.26x) | 2002.09 (7.27x) |
| EmptyFieldMask JSON stringify | 40.99 | — | — | 607.83 (14.83x) | 201.00 (4.90x) |
| EmptyFieldMask JSON parse | 80.09 | — | — | 957.22 (11.95x) | 179.74 (2.24x) |
| Timestamp JSON stringify | 96.30 | — | — | 1145.92 (11.90x) | 474.71 (4.93x) |
| Timestamp JSON parse | 41.56 | — | — | 1495.89 (35.99x) | 701.39 (16.88x) |
| ShortFraction Timestamp JSON parse | 39.92 | — | — | 1521.22 (38.11x) | 658.69 (16.50x) |
| Micro Timestamp JSON stringify | 95.75 | — | — | 1165.26 (12.17x) | 751.98 (7.85x) |
| Micro Timestamp JSON parse | 43.11 | — | — | 1536.13 (35.63x) | 637.63 (14.79x) |
| Nano Timestamp JSON stringify | 93.90 | — | — | 1189.81 (12.67x) | 527.17 (5.61x) |
| Nano Timestamp JSON parse | 45.49 | — | — | 1532.75 (33.69x) | 881.80 (19.38x) |
| Offset Timestamp JSON parse | 51.50 | — | — | 1546.98 (30.04x) | 1010.41 (19.62x) |
| PreEpoch Timestamp JSON stringify | 66.26 | — | — | 1082.86 (16.34x) | 459.96 (6.94x) |
| PreEpoch Timestamp JSON parse | 40.04 | — | — | 1475.85 (36.86x) | 654.46 (16.35x) |
| Max Timestamp JSON stringify | 79.27 | — | — | 1199.89 (15.14x) | 456.61 (5.76x) |
| Max Timestamp JSON parse | 46.71 | — | — | 1543.72 (33.05x) | 431.96 (9.25x) |
| Min Timestamp JSON stringify | 81.09 | — | — | 1065.67 (13.14x) | 414.23 (5.11x) |
| Min Timestamp JSON parse | 37.93 | — | — | 1458.17 (38.44x) | 422.19 (11.13x) |
| Empty JSON stringify | 20.59 | — | — | 512.72 (24.90x) | 138.22 (6.71x) |
| Empty JSON parse | 67.67 | — | — | 719.07 (10.63x) | 524.13 (7.75x) |
| Struct JSON stringify | 171.84 | — | — | 5773.91 (33.60x) | 4131.15 (24.04x) |
| Struct JSON parse | 863.27 | — | — | 10880.00 (12.60x) | 4885.23 (5.66x) |
| EmptyStruct JSON stringify | 41.14 | — | — | 698.75 (16.98x) | 484.98 (11.79x) |
| EmptyStruct JSON parse | 90.67 | — | — | 2022.94 (22.31x) | 370.32 (4.08x) |
| Value JSON stringify | 174.27 | — | — | 6561.24 (37.65x) | 3177.74 (18.23x) |
| Value JSON parse | 869.39 | — | — | 12098.90 (13.92x) | 6319.56 (7.27x) |
| NullValue JSON stringify | 40.34 | — | — | 1326.59 (32.89x) | 378.57 (9.38x) |
| NullValue JSON parse | 67.41 | — | — | 2472.23 (36.67x) | 511.78 (7.59x) |
| StringScalarValue JSON stringify | 48.10 | — | — | 1349.32 (28.05x) | 466.96 (9.71x) |
| StringScalarValue JSON parse | 137.96 | — | — | 2093.26 (15.17x) | 448.64 (3.25x) |
| EmptyStringScalarValue JSON stringify | 45.87 | — | — | 1346.48 (29.35x) | 269.73 (5.88x) |
| EmptyStringScalarValue JSON parse | 84.34 | — | — | 2076.02 (24.61x) | 357.57 (4.24x) |
| NumberValue JSON stringify | 73.42 | — | — | 1563.02 (21.29x) | 319.85 (4.36x) |
| NumberValue JSON parse | 129.06 | — | — | 2173.19 (16.84x) | 407.49 (3.16x) |
| ZeroNumberValue JSON stringify | 50.87 | — | — | 1556.68 (30.60x) | 282.62 (5.56x) |
| ZeroNumberValue JSON parse | 128.08 | — | — | 3086.11 (24.10x) | 384.79 (3.00x) |
| BoolScalarValue JSON stringify | 40.52 | — | — | 1811.63 (44.71x) | 209.51 (5.17x) |
| BoolScalarValue JSON parse | 67.07 | — | — | 3048.27 (45.45x) | 337.21 (5.03x) |
| FalseBoolScalarValue JSON stringify | 40.35 | — | — | 1858.38 (46.06x) | 213.33 (5.29x) |
| FalseBoolScalarValue JSON parse | 67.91 | — | — | 2967.52 (43.70x) | 313.79 (4.62x) |
| ListKindValue JSON stringify | 140.70 | — | — | 6720.29 (47.76x) | 2294.08 (16.30x) |
| ListKindValue JSON parse | 672.64 | — | — | 10847.00 (16.13x) | 4427.19 (6.58x) |
| EmptyStructKindValue JSON stringify | 42.85 | — | — | 1950.57 (45.52x) | 521.08 (12.16x) |
| EmptyStructKindValue JSON parse | 106.71 | — | — | 3767.04 (35.30x) | 1003.27 (9.40x) |
| EmptyListKindValue JSON stringify | 41.47 | — | — | 1934.17 (46.64x) | 464.05 (11.19x) |
| EmptyListKindValue JSON parse | 145.41 | — | — | 4029.96 (27.71x) | 538.20 (3.70x) |
| ListValue JSON stringify | 140.90 | — | — | 4736.79 (33.62x) | 2133.57 (15.14x) |
| ListValue JSON parse | 669.33 | — | — | 8651.57 (12.93x) | 4558.52 (6.81x) |
| EmptyListValue JSON stringify | 40.03 | — | — | 694.16 (17.34x) | 173.91 (4.34x) |
| EmptyListValue JSON parse | 127.52 | — | — | 2257.81 (17.71x) | 583.97 (4.58x) |
| DoubleValue JSON stringify | 69.77 | — | — | 870.46 (12.48x) | 251.21 (3.60x) |
| DoubleValue JSON parse | 111.07 | — | — | 1224.75 (11.03x) | 427.57 (3.85x) |
| DoubleValue String JSON parse | 111.44 | — | — | 1157.22 (10.38x) | 814.13 (7.31x) |
| NegativeDoubleValue JSON stringify | 68.33 | — | — | 867.16 (12.69x) | 205.81 (3.01x) |
| NegativeDoubleValue JSON parse | 111.46 | — | — | 1233.86 (11.07x) | 620.92 (5.57x) |
| ZeroDoubleValue JSON stringify | 48.27 | — | — | 812.93 (16.84x) | 334.84 (6.94x) |
| ZeroDoubleValue JSON parse | 108.24 | — | — | 1171.29 (10.82x) | 351.52 (3.25x) |
| DoubleValue NaN JSON stringify | 46.23 | — | — | 671.61 (14.53x) | 129.15 (2.79x) |
| DoubleValue NaN JSON parse | 104.50 | — | — | 1098.44 (10.51x) | 279.11 (2.67x) |
| DoubleValue Infinity JSON stringify | 47.76 | — | — | 682.60 (14.29x) | 117.53 (2.46x) |
| DoubleValue Infinity JSON parse | 105.87 | — | — | 1109.19 (10.48x) | 255.13 (2.41x) |
| DoubleValue NegativeInfinity JSON stringify | 48.09 | — | — | 669.40 (13.92x) | 116.08 (2.41x) |
| DoubleValue NegativeInfinity JSON parse | 108.99 | — | — | 1111.48 (10.20x) | 263.14 (2.41x) |
| FloatValue JSON stringify | 70.83 | — | — | 814.86 (11.50x) | 239.02 (3.37x) |
| FloatValue JSON parse | 110.36 | — | — | 1241.10 (11.25x) | 448.30 (4.06x) |
| FloatValue String JSON parse | 110.69 | — | — | 1164.10 (10.52x) | 391.99 (3.54x) |
| NegativeFloatValue JSON stringify | 71.15 | — | — | 810.54 (11.39x) | 193.91 (2.73x) |
| NegativeFloatValue JSON parse | 110.33 | — | — | 1217.03 (11.03x) | 292.21 (2.65x) |
| ZeroFloatValue JSON stringify | 47.57 | — | — | 766.45 (16.11x) | 272.20 (5.72x) |
| ZeroFloatValue JSON parse | 107.69 | — | — | 1147.42 (10.65x) | 515.27 (4.78x) |
| FloatValue NaN JSON stringify | 46.14 | — | — | 654.95 (14.19x) | 146.03 (3.16x) |
| FloatValue NaN JSON parse | 104.84 | — | — | 1103.25 (10.52x) | 254.76 (2.43x) |
| FloatValue Infinity JSON stringify | 47.63 | — | — | 652.72 (13.70x) | 136.58 (2.87x) |
| FloatValue Infinity JSON parse | 106.69 | — | — | 1091.25 (10.23x) | 244.04 (2.29x) |
| FloatValue NegativeInfinity JSON stringify | 48.42 | — | — | 647.55 (13.37x) | 147.01 (3.04x) |
| FloatValue NegativeInfinity JSON parse | 108.48 | — | — | 1093.04 (10.08x) | 257.85 (2.38x) |
| Int64Value JSON stringify | 50.24 | — | — | 677.67 (13.49x) | 284.69 (5.67x) |
| Int64Value JSON parse | 127.48 | — | — | 1223.62 (9.60x) | 640.63 (5.03x) |
| Int64Value Number JSON parse | 126.59 | — | — | 1276.01 (10.08x) | 364.45 (2.88x) |
| ZeroInt64Value JSON stringify | 41.44 | — | — | 614.92 (14.84x) | 197.27 (4.76x) |
| ZeroInt64Value JSON parse | 105.84 | — | — | 1090.08 (10.30x) | 330.25 (3.12x) |
| NegativeInt64Value JSON stringify | 49.97 | — | — | 677.88 (13.57x) | 385.23 (7.71x) |
| NegativeInt64Value JSON parse | 128.46 | — | — | 1223.80 (9.53x) | 609.97 (4.75x) |
| MinInt64Value JSON stringify | 49.36 | — | — | 674.57 (13.67x) | 292.68 (5.93x) |
| MinInt64Value JSON parse | 142.43 | — | — | 1255.42 (8.81x) | 535.45 (3.76x) |
| MaxInt64Value JSON stringify | 49.57 | — | — | 676.17 (13.64x) | 271.24 (5.47x) |
| MaxInt64Value JSON parse | 134.16 | — | — | 1240.46 (9.25x) | 491.06 (3.66x) |
| UInt64Value JSON stringify | 49.83 | — | — | 674.56 (13.54x) | 365.33 (7.33x) |
| UInt64Value JSON parse | 126.13 | — | — | 1210.15 (9.59x) | 452.82 (3.59x) |
| UInt64Value Number JSON parse | 127.49 | — | — | 1273.93 (9.99x) | 321.19 (2.52x) |
| ZeroUInt64Value JSON stringify | 41.15 | — | — | 612.99 (14.90x) | 195.42 (4.75x) |
| ZeroUInt64Value JSON parse | 105.22 | — | — | 1089.95 (10.36x) | 856.06 (8.14x) |
| MaxUInt64Value JSON stringify | 49.04 | — | — | 674.10 (13.75x) | 277.25 (5.65x) |
| MaxUInt64Value JSON parse | 141.92 | — | — | 1250.57 (8.81x) | 453.92 (3.20x) |
| Int32Value JSON stringify | 46.68 | — | — | 641.44 (13.74x) | 131.48 (2.82x) |
| Int32Value JSON parse | 117.04 | — | — | 1184.01 (10.12x) | 300.62 (2.57x) |
| Int32Value String JSON parse | 114.10 | — | — | 1144.83 (10.03x) | 393.74 (3.45x) |
| ZeroInt32Value JSON stringify | 46.77 | — | — | 628.14 (13.43x) | 154.22 (3.30x) |
| ZeroInt32Value JSON parse | 112.60 | — | — | 1155.88 (10.27x) | 417.26 (3.71x) |
| NegativeInt32Value JSON stringify | 46.66 | — | — | 649.16 (13.91x) | 155.70 (3.34x) |
| NegativeInt32Value JSON parse | 116.26 | — | — | 1194.23 (10.27x) | 328.82 (2.83x) |
| MinInt32Value JSON stringify | 47.27 | — | — | 650.73 (13.77x) | 130.50 (2.76x) |
| MinInt32Value JSON parse | 121.83 | — | — | 1217.78 (10.00x) | 346.76 (2.85x) |
| MaxInt32Value JSON stringify | 47.36 | — | — | 646.07 (13.64x) | 133.73 (2.82x) |
| MaxInt32Value JSON parse | 122.10 | — | — | 1205.77 (9.88x) | 319.79 (2.62x) |
| UInt32Value JSON stringify | 46.75 | — | — | 639.02 (13.67x) | 132.53 (2.83x) |
| UInt32Value JSON parse | 116.78 | — | — | 1181.82 (10.12x) | 288.45 (2.47x) |
| UInt32Value String JSON parse | 115.41 | — | — | 1122.45 (9.73x) | 373.93 (3.24x) |
| ZeroUInt32Value JSON stringify | 46.82 | — | — | 628.19 (13.42x) | 123.53 (2.64x) |
| ZeroUInt32Value JSON parse | 112.98 | — | — | 1149.29 (10.17x) | 286.73 (2.54x) |
| MaxUInt32Value JSON stringify | 47.15 | — | — | 645.78 (13.70x) | 172.86 (3.67x) |
| MaxUInt32Value JSON parse | 122.38 | — | — | 1207.48 (9.87x) | 658.90 (5.38x) |
| BoolValue JSON stringify | 45.07 | — | — | 621.66 (13.79x) | 144.70 (3.21x) |
| BoolValue JSON parse | 59.90 | — | — | 1058.10 (17.66x) | 404.78 (6.76x) |
| FalseBoolValue JSON stringify | 45.07 | — | — | 610.31 (13.54x) | 120.58 (2.68x) |
| FalseBoolValue JSON parse | 67.79 | — | — | 1058.06 (15.61x) | 197.94 (2.92x) |
| StringValue JSON stringify | 51.88 | — | — | 667.45 (12.87x) | 169.14 (3.26x) |
| StringValue JSON parse | 121.56 | — | — | 1142.49 (9.40x) | 282.12 (2.32x) |
| StringValue Escape JSON parse | 130.75 | — | — | 1171.25 (8.96x) | 356.16 (2.72x) |
| EmptyStringValue JSON stringify | 49.07 | — | — | 630.33 (12.85x) | 185.85 (3.79x) |
| EmptyStringValue JSON parse | 66.07 | — | — | 1108.06 (16.77x) | 510.98 (7.73x) |
| BytesValue JSON stringify | 49.02 | — | — | 669.43 (13.66x) | 226.67 (4.62x) |
| BytesValue JSON parse | 128.15 | — | — | 1165.41 (9.09x) | 404.22 (3.15x) |
| BytesValue URL JSON parse | 143.17 | — | — | 1154.18 (8.06x) | 487.51 (3.41x) |
| EmptyBytesValue JSON stringify | 40.65 | — | — | 646.11 (15.89x) | 176.34 (4.34x) |
| EmptyBytesValue JSON parse | 69.68 | — | — | 1125.37 (16.15x) | 265.23 (3.81x) |
| TextFormat format | 181.11 | — | — | 2503.50 (13.82x) | 2603.56 (14.38x) |
| TextFormat parse | 726.04 | — | — | 5018.77 (6.91x) | 7532.86 (10.38x) |
| packed fixed32 encode | 2.01 | 549.09 (273.18x) | 539.78 (268.55x) | 43.67 (21.73x) | 420.37 (209.14x) |
| packed fixed32 decode | 4.53 | 1051.97 (232.22x) | 1951.10 (430.71x) | 49.80 (10.99x) | 1927.02 (425.39x) |
| packed fixed64 encode | 2.01 | 591.39 (294.22x) | 560.99 (279.10x) | 75.73 (37.68x) | 403.54 (200.77x) |
| packed fixed64 decode | 4.53 | 1027.03 (226.72x) | 7939.45 (1752.64x) | 79.80 (17.62x) | 3859.95 (852.09x) |
| packed sfixed32 encode | 2.01 | 554.95 (276.09x) | 539.29 (268.30x) | 44.21 (21.99x) | 460.54 (229.12x) |
| packed sfixed32 decode | 4.53 | 1061.34 (234.29x) | 1929.03 (425.83x) | 49.34 (10.89x) | 3300.89 (728.67x) |
| packed sfixed64 encode | 2.00 | 573.67 (286.83x) | 623.84 (311.92x) | 75.61 (37.80x) | 396.07 (198.03x) |
| packed sfixed64 decode | 4.53 | 1023.87 (226.02x) | 7937.98 (1752.31x) | 79.84 (17.62x) | 2925.07 (645.71x) |
| packed float encode | 2.01 | 813.43 (404.69x) | 539.31 (268.31x) | 44.34 (22.06x) | 391.73 (194.89x) |
| packed float decode | 4.54 | 1068.86 (235.43x) | 2067.73 (455.45x) | 49.24 (10.85x) | 2340.50 (515.53x) |
| packed double encode | 2.01 | 834.33 (415.09x) | 561.10 (279.15x) | 75.76 (37.69x) | 351.26 (174.76x) |
| packed double decode | 4.52 | 960.22 (212.44x) | 2063.53 (456.53x) | 79.77 (17.65x) | 2569.33 (568.44x) |
| packed uint64 encode | 1293.83 | 4624.87 (3.57x) | 4181.51 (3.23x) | 2171.61 (1.68x) | 3460.50 (2.67x) |
| packed uint64 decode | 1783.89 | 2790.50 (1.56x) | 8860.69 (4.97x) | 2824.05 (1.58x) | 13692.52 (7.68x) |
| packed uint32 encode | 932.80 | 3614.80 (3.88x) | 3271.06 (3.51x) | 1728.67 (1.85x) | 2925.35 (3.14x) |
| packed uint32 decode | 1291.97 | 2462.52 (1.91x) | 3268.74 (2.53x) | 1987.49 (1.54x) | 9208.23 (7.13x) |
| packed int64 encode | 1369.18 | 11012.67 (8.04x) | 6209.44 (4.54x) | 2897.73 (2.12x) | 4122.33 (3.01x) |
| packed int64 decode | 2743.27 | 3410.26 (1.24x) | 10251.04 (3.74x) | 4783.70 (1.74x) | 10207.52 (3.72x) |
| packed sint32 encode | 779.91 | 3047.53 (3.91x) | 2803.38 (3.59x) | 1522.18 (1.95x) | 3470.72 (4.45x) |
| packed sint32 decode | 932.30 | 2545.34 (2.73x) | 3186.79 (3.42x) | 1131.71 (1.21x) | 4014.99 (4.31x) |
| packed sint64 encode | 1420.54 | 4938.01 (3.48x) | 4312.87 (3.04x) | 2422.41 (1.71x) | 4270.33 (3.01x) |
| packed sint64 decode | 2025.61 | 3067.75 (1.51x) | 9653.81 (4.77x) | 2933.39 (1.45x) | 8455.15 (4.17x) |
| packed bool encode | 2.01 | 1320.77 (657.10x) | 521.22 (259.31x) | 15.69 (7.81x) | 2209.98 (1099.49x) |
| packed bool decode | 262.84 | 1523.06 (5.79x) | 2573.28 (9.79x) | 807.25 (3.07x) | 1771.35 (6.74x) |
| packed enum encode | 270.68 | 2710.32 (10.01x) | 1819.75 (6.72x) | 1083.60 (4.00x) | 2580.32 (9.53x) |
| packed enum decode | 157.72 | 1552.53 (9.84x) | 2866.80 (18.18x) | 733.86 (4.65x) | 2163.23 (13.72x) |
| large map encode | 3953.93 | 16423.76 (4.15x) | 10129.51 (2.56x) | 21391.20 (5.41x) | 195900.94 (49.55x) |
| shuffled large map deterministic binary encode | 27973.76 | — | — | 87754.90 (3.14x) | 374538.93 (13.39x) |
| large map decode | 25425.88 | 90792.25 (3.57x) | 89582.95 (3.52x) | 91966.10 (3.62x) | 290307.09 (11.42x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded zero/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound `Duration`, non-empty and empty `Struct`, object/list/scalar `Value` (including default-like scalar and empty object/list kinds),
`FieldMask` (non-empty, escaped JSON parse input, and empty), short-fraction parse/micro/nano/offset/min/pre/post/max-bound `Timestamp`, `Empty`, min/zero/positive/number-input parse/negative/max `Int64Value`, negative/zero/positive finite/string-input parse `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), negative/zero/positive finite/string-input parse `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), zero/normal/number-input parse/max `UInt64Value`, min/zero/positive/string-input parse/negative/max `Int32Value`, zero/normal/string-input parse/max `UInt32Value`, true/false `BoolValue`, non-empty/escape-input parse/empty `StringValue`, base64/base64url parse/empty `BytesValue`, and recursive nested `Any` payloads), direct zero/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound Duration, non-empty/escaped-input parse/empty FieldMask, and short-fraction parse/micro/nano/offset/min/pre/post/max-bound Timestamp WKT JSON plus other direct WKT JSON, including empty `Struct` and empty `ListValue`, TextFormat, packed scalars, large bytes,
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
