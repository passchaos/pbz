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

Latest accepted comparison (`/tmp/pbz-compare-key-surrogate-json-final.log`,
summarized in `/tmp/pbz-summary-key-surrogate-json-final.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 20.21 | 126.08 (6.24x) | 52.76 (2.61x) | 102.85 (5.09x) | 867.15 (42.91x) |
| binary decode | 86.12 | 453.28 (5.26x) | 227.34 (2.64x) | 336.18 (3.90x) | 908.27 (10.55x) |
| unknown fields count by number | 3.58 | — | — | 163.33 (45.62x) | — |
| deterministic binary encode | 53.28 | — | — | 128.39 (2.41x) | 1170.00 (21.96x) |
| scalarmix encode | 18.76 | 139.94 (7.46x) | 47.79 (2.55x) | 29.82 (1.59x) | 209.37 (11.16x) |
| scalarmix decode | 33.69 | 166.61 (4.95x) | 175.46 (5.21x) | 86.11 (2.56x) | 308.76 (9.16x) |
| textbytes encode | 9.52 | 77.28 (8.12x) | 33.48 (3.52x) | 117.12 (12.30x) | 146.97 (15.44x) |
| textbytes decode | 45.57 | 380.25 (8.34x) | 240.47 (5.28x) | 163.32 (3.58x) | 684.60 (15.02x) |
| largebytes encode | 25.90 | 2707.02 (104.52x) | 2671.13 (103.13x) | 2685.22 (103.68x) | 2718.05 (104.94x) |
| largebytes decode | 87.95 | 5532.58 (62.91x) | 2996.05 (34.07x) | 2719.37 (30.92x) | 21503.43 (244.50x) |
| presencemix encode | 16.96 | 55.91 (3.30x) | 26.59 (1.57x) | 57.57 (3.39x) | 270.97 (15.98x) |
| presencemix decode | 55.70 | 131.48 (2.36x) | 109.36 (1.96x) | 164.42 (2.95x) | 497.42 (8.93x) |
| complex encode | 50.79 | 209.57 (4.13x) | 95.53 (1.88x) | 155.63 (3.06x) | 921.29 (18.14x) |
| complex decode | 170.01 | 553.44 (3.26x) | 342.03 (2.01x) | 396.76 (2.33x) | 1351.86 (7.95x) |
| complex deterministic binary encode | 91.67 | — | — | 166.77 (1.82x) | 1149.25 (12.54x) |
| complex JSON stringify | 281.53 | — | — | 4878.74 (17.33x) | 6163.20 (21.89x) |
| complex JSON parse | 2402.62 | — | — | 11860.60 (4.94x) | 7441.88 (3.10x) |
| complex TextFormat format | 246.31 | — | — | 3763.61 (15.28x) | 5429.93 (22.05x) |
| complex TextFormat parse | 1824.72 | — | — | 6943.06 (3.81x) | 8449.11 (4.63x) |
| packed int32 encode | 623.71 | 3162.29 (5.07x) | 2514.48 (4.03x) | 1229.31 (1.97x) | 2739.95 (4.39x) |
| packed int32 decode | 692.90 | 1906.09 (2.75x) | 3218.16 (4.64x) | 959.24 (1.38x) | 2561.83 (3.70x) |
| JSON stringify | 160.89 | — | — | 3004.13 (18.67x) | 2334.27 (14.51x) |
| JSON parse | 1518.62 | — | — | 7459.23 (4.91x) | 4563.19 (3.00x) |
| Any WKT JSON stringify | 142.78 | — | — | 1874.28 (13.13x) | 983.79 (6.89x) |
| Any WKT JSON parse | 509.36 | — | — | 2974.72 (5.84x) | 1503.38 (2.95x) |
| Any Duration Escape WKT JSON parse | 528.10 | — | — | 3003.70 (5.69x) | 1598.77 (3.03x) |
| Any PlusDuration WKT JSON parse | 512.31 | — | — | 3005.66 (5.87x) | 1550.09 (3.03x) |
| Any ShortFractionDuration WKT JSON parse | 508.46 | — | — | 2964.17 (5.83x) | 1512.56 (2.97x) |
| Any MicroDuration WKT JSON stringify | 153.51 | — | — | 1887.28 (12.29x) | 1030.14 (6.71x) |
| Any MicroDuration WKT JSON parse | 511.53 | — | — | 2984.67 (5.83x) | 1525.18 (2.98x) |
| Any NanoDuration WKT JSON stringify | 143.98 | — | — | 1915.06 (13.30x) | 976.64 (6.78x) |
| Any NanoDuration WKT JSON parse | 517.80 | — | — | 2998.73 (5.79x) | 1532.06 (2.96x) |
| Any NegativeDuration WKT JSON stringify | 142.53 | — | — | 1951.38 (13.69x) | 1007.88 (7.07x) |
| Any NegativeDuration WKT JSON parse | 516.51 | — | — | 3099.49 (6.00x) | 1580.15 (3.06x) |
| Any FractionalNegativeDuration WKT JSON stringify | 140.80 | — | — | 1893.68 (13.45x) | 992.87 (7.05x) |
| Any FractionalNegativeDuration WKT JSON parse | 507.58 | — | — | 3062.28 (6.03x) | 1512.70 (2.98x) |
| Any MaxDuration WKT JSON stringify | 124.00 | — | — | 1744.78 (14.07x) | 978.99 (7.90x) |
| Any MaxDuration WKT JSON parse | 527.62 | — | — | 2959.11 (5.61x) | 1531.86 (2.90x) |
| Any MinDuration WKT JSON stringify | 118.26 | — | — | 1763.44 (14.91x) | 1009.15 (8.53x) |
| Any MinDuration WKT JSON parse | 526.73 | — | — | 3028.19 (5.75x) | 1517.54 (2.88x) |
| Any ZeroDuration WKT JSON stringify | 112.79 | — | — | 912.12 (8.09x) | 952.67 (8.45x) |
| Any ZeroDuration WKT JSON parse | 457.18 | — | — | 2248.59 (4.92x) | 1438.77 (3.15x) |
| Any FieldMask WKT JSON stringify | 232.24 | — | — | 1743.60 (7.51x) | 1412.19 (6.08x) |
| Any FieldMask WKT JSON parse | 703.26 | — | — | 3153.36 (4.48x) | 2061.85 (2.93x) |
| Any FieldMask Escape WKT JSON parse | 710.69 | — | — | 3245.69 (4.57x) | 2242.65 (3.16x) |
| Any EmptyFieldMask WKT JSON stringify | 120.93 | — | — | 915.32 (7.57x) | 776.53 (6.42x) |
| Any EmptyFieldMask WKT JSON parse | 431.21 | — | — | 2147.30 (4.98x) | 1302.82 (3.02x) |
| Any Timestamp WKT JSON stringify | 184.08 | — | — | 2020.10 (10.97x) | 1002.41 (5.45x) |
| Any Timestamp WKT JSON parse | 558.24 | — | — | 3021.34 (5.41x) | 1593.87 (2.86x) |
| Any Timestamp Escape WKT JSON parse | 580.04 | — | — | 3073.21 (5.30x) | 1734.00 (2.99x) |
| Any ShortFraction Timestamp WKT JSON parse | 556.75 | — | — | 3000.21 (5.39x) | 1588.35 (2.85x) |
| Any Micro Timestamp WKT JSON stringify | 187.21 | — | — | 2022.88 (10.81x) | 999.60 (5.34x) |
| Any Micro Timestamp WKT JSON parse | 564.32 | — | — | 3032.68 (5.37x) | 1621.87 (2.87x) |
| Any Nano Timestamp WKT JSON stringify | 188.94 | — | — | 2026.66 (10.73x) | 1019.53 (5.40x) |
| Any Nano Timestamp WKT JSON parse | 570.16 | — | — | 3023.57 (5.30x) | 1629.91 (2.86x) |
| Any Offset Timestamp WKT JSON parse | 973.06 | — | — | 3048.07 (3.13x) | 1673.29 (1.72x) |
| Any PreEpoch Timestamp WKT JSON stringify | 304.00 | — | — | 1938.73 (6.38x) | 987.98 (3.25x) |
| Any PreEpoch Timestamp WKT JSON parse | 905.22 | — | — | 3033.02 (3.35x) | 1570.65 (1.74x) |
| Any Max Timestamp WKT JSON stringify | 330.01 | — | — | 2041.93 (6.19x) | 1024.72 (3.11x) |
| Any Max Timestamp WKT JSON parse | 964.06 | — | — | 3085.99 (3.20x) | 1685.97 (1.75x) |
| Any Min Timestamp WKT JSON stringify | 354.53 | — | — | 1927.11 (5.44x) | 978.70 (2.76x) |
| Any Min Timestamp WKT JSON parse | 899.73 | — | — | 3063.63 (3.41x) | 1576.37 (1.75x) |
| Any Empty WKT JSON stringify | 175.09 | — | — | 907.98 (5.19x) | 626.48 (3.58x) |
| Any Empty WKT JSON parse | 510.57 | — | — | 2123.74 (4.16x) | 1354.93 (2.65x) |
| Any Struct WKT JSON stringify | 931.91 | — | — | 5901.22 (6.33x) | 6103.27 (6.55x) |
| Any Struct WKT JSON parse | 1762.75 | — | — | 11173.90 (6.34x) | 8743.70 (4.96x) |
| Any Struct Escape WKT JSON parse | 1769.59 | — | — | 11237.60 (6.35x) | 8859.49 (5.01x) |
| Any Struct NumberExponent WKT JSON parse | 1762.15 | — | — | 11190.30 (6.35x) | 8689.75 (4.93x) |
| Any Struct Surrogate WKT JSON parse | 751.21 | — | — | 6349.41 (8.45x) | 3046.73 (4.06x) |
| Any Struct KeySurrogate WKT JSON parse | 789.72 | — | — | 6287.37 (7.96x) | 3055.91 (3.87x) |
| Any EmptyStruct WKT JSON stringify | 127.30 | — | — | 913.86 (7.18x) | 935.41 (7.35x) |
| Any EmptyStruct WKT JSON parse | 430.99 | — | — | 2227.84 (5.17x) | 1555.35 (3.61x) |
| Any Value WKT JSON stringify | 666.33 | — | — | 5945.54 (8.92x) | 6355.55 (9.54x) |
| Any Value WKT JSON parse | 1793.62 | — | — | 11403.40 (6.36x) | 9083.24 (5.06x) |
| Any Value Escape WKT JSON parse | 1814.78 | — | — | 11503.80 (6.34x) | 9199.22 (5.07x) |
| Any Value NumberExponent WKT JSON parse | 1793.59 | — | — | 11414.20 (6.36x) | 9115.45 (5.08x) |
| Any Value Surrogate WKT JSON parse | 815.62 | — | — | 6541.29 (8.02x) | 3567.09 (4.37x) |
| Any Value KeySurrogate WKT JSON parse | 817.82 | — | — | 6538.94 (8.00x) | 3452.71 (4.22x) |
| Any NullValue WKT JSON stringify | 139.69 | — | — | 2250.58 (16.11x) | 918.07 (6.57x) |
| Any NullValue WKT JSON parse | 455.36 | — | — | 4092.20 (8.99x) | 1580.43 (3.47x) |
| Any StringScalarValue WKT JSON stringify | 166.38 | — | — | 2259.43 (13.58x) | 1005.92 (6.05x) |
| Any StringScalarValue WKT JSON parse | 516.32 | — | — | 3649.00 (7.07x) | 1680.15 (3.25x) |
| Any StringScalarValue Escape WKT JSON parse | 528.88 | — | — | 3697.83 (6.99x) | 1739.50 (3.29x) |
| Any StringScalarValue Surrogate WKT JSON parse | 534.31 | — | — | 3684.58 (6.90x) | 1740.92 (3.26x) |
| Any EmptyStringScalarValue WKT JSON stringify | 149.17 | — | — | 2277.19 (15.27x) | 939.86 (6.30x) |
| Any EmptyStringScalarValue WKT JSON parse | 484.28 | — | — | 3620.46 (7.48x) | 1580.88 (3.26x) |
| Any NumberValue WKT JSON stringify | 181.70 | — | — | 2510.01 (13.81x) | 1038.75 (5.72x) |
| Any NumberValue WKT JSON parse | 494.80 | — | — | 3728.28 (7.53x) | 1608.21 (3.25x) |
| Any NumberValue Exponent WKT JSON parse | 499.27 | — | — | 3735.66 (7.48x) | 1613.34 (3.23x) |
| Any NegativeNumberValue WKT JSON stringify | 186.00 | — | — | 2511.76 (13.50x) | 1033.86 (5.56x) |
| Any NegativeNumberValue WKT JSON parse | 494.34 | — | — | 3737.83 (7.56x) | 1617.26 (3.27x) |
| Any ZeroNumberValue WKT JSON stringify | 154.42 | — | — | 2474.34 (16.02x) | 929.50 (6.02x) |
| Any ZeroNumberValue WKT JSON parse | 493.15 | — | — | 3659.37 (7.42x) | 1603.61 (3.25x) |
| Any BoolScalarValue WKT JSON stringify | 137.31 | — | — | 2254.43 (16.42x) | 913.43 (6.65x) |
| Any BoolScalarValue WKT JSON parse | 460.14 | — | — | 3622.05 (7.87x) | 1558.19 (3.39x) |
| Any FalseBoolScalarValue WKT JSON stringify | 137.87 | — | — | 2249.41 (16.32x) | 910.17 (6.60x) |
| Any FalseBoolScalarValue WKT JSON parse | 464.18 | — | — | 3601.63 (7.76x) | 1532.33 (3.30x) |
| Any ListKindValue WKT JSON stringify | 513.53 | — | — | 5577.81 (10.86x) | 4679.17 (9.11x) |
| Any ListKindValue WKT JSON parse | 1390.60 | — | — | 9949.16 (7.15x) | 7042.02 (5.06x) |
| Any ListKindValue Escape WKT JSON parse | 1417.74 | — | — | 10021.10 (7.07x) | 7251.18 (5.11x) |
| Any ListKindValue Surrogate WKT JSON parse | 728.12 | — | — | 4851.44 (6.66x) | 2632.58 (3.62x) |
| Any EmptyStructKindValue WKT JSON stringify | 149.02 | — | — | 2910.55 (19.53x) | 1270.40 (8.53x) |
| Any EmptyStructKindValue WKT JSON parse | 497.21 | — | — | 5397.89 (10.86x) | 1936.65 (3.90x) |
| Any EmptyListKindValue WKT JSON stringify | 147.14 | — | — | 2924.11 (19.87x) | 1084.32 (7.37x) |
| Any EmptyListKindValue WKT JSON parse | 498.32 | — | — | 4411.26 (8.85x) | 1813.20 (3.64x) |
| Any DoubleValue WKT JSON stringify | 196.81 | — | — | 1790.15 (9.10x) | 809.03 (4.11x) |
| Any DoubleValue WKT JSON parse | 510.39 | — | — | 2734.27 (5.36x) | 1455.79 (2.85x) |
| Any DoubleValue String WKT JSON parse | 522.58 | — | — | 2723.93 (5.21x) | 1520.63 (2.91x) |
| Any DoubleValue Exponent WKT JSON parse | 514.61 | — | — | 2746.65 (5.34x) | 1461.57 (2.84x) |
| Any NegativeDoubleValue WKT JSON stringify | 200.46 | — | — | 1795.54 (8.96x) | 806.13 (4.02x) |
| Any NegativeDoubleValue WKT JSON parse | 511.14 | — | — | 2752.30 (5.38x) | 1441.66 (2.82x) |
| Any ZeroDoubleValue WKT JSON stringify | 158.81 | — | — | 919.95 (5.79x) | 734.70 (4.63x) |
| Any ZeroDoubleValue WKT JSON parse | 507.42 | — | — | 2175.82 (4.29x) | 1378.40 (2.72x) |
| Any DoubleValue NaN WKT JSON stringify | 165.44 | — | — | 1563.85 (9.45x) | 717.76 (4.34x) |
| Any DoubleValue NaN WKT JSON parse | 505.01 | — | — | 2647.24 (5.24x) | 1410.48 (2.79x) |
| Any DoubleValue Infinity WKT JSON stringify | 167.83 | — | — | 1563.12 (9.31x) | 721.74 (4.30x) |
| Any DoubleValue Infinity WKT JSON parse | 508.40 | — | — | 2692.37 (5.30x) | 1421.58 (2.80x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 172.31 | — | — | 1554.66 (9.02x) | 719.44 (4.18x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 509.78 | — | — | 2678.39 (5.25x) | 1419.23 (2.78x) |
| Any FloatValue WKT JSON stringify | 202.35 | — | — | 1732.28 (8.56x) | 788.46 (3.90x) |
| Any FloatValue WKT JSON parse | 511.54 | — | — | 2708.58 (5.29x) | 1423.82 (2.78x) |
| Any FloatValue String WKT JSON parse | 523.02 | — | — | 2705.84 (5.17x) | 1535.15 (2.94x) |
| Any FloatValue Exponent WKT JSON parse | 515.21 | — | — | 2713.21 (5.27x) | 1447.78 (2.81x) |
| Any NegativeFloatValue WKT JSON stringify | 205.58 | — | — | 1734.03 (8.43x) | 791.08 (3.85x) |
| Any NegativeFloatValue WKT JSON parse | 512.03 | — | — | 2880.92 (5.63x) | 1431.75 (2.80x) |
| Any ZeroFloatValue WKT JSON stringify | 169.22 | — | — | 934.48 (5.52x) | 730.13 (4.31x) |
| Any ZeroFloatValue WKT JSON parse | 508.23 | — | — | 2161.32 (4.25x) | 1376.38 (2.71x) |
| Any FloatValue NaN WKT JSON stringify | 166.44 | — | — | 1559.23 (9.37x) | 710.09 (4.27x) |
| Any FloatValue NaN WKT JSON parse | 506.84 | — | — | 2625.01 (5.18x) | 1385.37 (2.73x) |
| Any FloatValue Infinity WKT JSON stringify | 169.73 | — | — | 1542.46 (9.09x) | 719.82 (4.24x) |
| Any FloatValue Infinity WKT JSON parse | 514.12 | — | — | 2664.29 (5.18x) | 1385.76 (2.70x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 175.15 | — | — | 1539.62 (8.79x) | 713.75 (4.08x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 516.56 | — | — | 2654.75 (5.14x) | 1412.01 (2.73x) |
| Any Int64Value WKT JSON stringify | 168.09 | — | — | 1559.26 (9.28x) | 855.82 (5.09x) |
| Any Int64Value WKT JSON parse | 538.05 | — | — | 2789.14 (5.18x) | 1627.25 (3.02x) |
| Any Int64Value Number WKT JSON parse | 536.94 | — | — | 2747.38 (5.12x) | 1530.35 (2.85x) |
| Any Int64Value Exponent WKT JSON parse | 523.32 | — | — | 2704.07 (5.17x) | 1486.92 (2.84x) |
| Any ZeroInt64Value WKT JSON stringify | 162.51 | — | — | 912.52 (5.62x) | 783.12 (4.82x) |
| Any ZeroInt64Value WKT JSON parse | 512.65 | — | — | 2158.72 (4.21x) | 1490.84 (2.91x) |
| Any NegativeInt64Value WKT JSON stringify | 165.36 | — | — | 1556.29 (9.41x) | 854.45 (5.17x) |
| Any NegativeInt64Value WKT JSON parse | 551.05 | — | — | 2811.69 (5.10x) | 1652.67 (3.00x) |
| Any MinInt64Value WKT JSON stringify | 176.18 | — | — | 1559.45 (8.85x) | 859.87 (4.88x) |
| Any MinInt64Value WKT JSON parse | 558.98 | — | — | 2814.65 (5.04x) | 1660.11 (2.97x) |
| Any MaxInt64Value WKT JSON stringify | 176.23 | — | — | 1558.05 (8.84x) | 865.37 (4.91x) |
| Any MaxInt64Value WKT JSON parse | 546.96 | — | — | 2802.43 (5.12x) | 1797.96 (3.29x) |
| Any UInt64Value WKT JSON stringify | 179.40 | — | — | 1555.41 (8.67x) | 891.34 (4.97x) |
| Any UInt64Value WKT JSON parse | 546.05 | — | — | 2793.44 (5.12x) | 1630.69 (2.99x) |
| Any UInt64Value Number WKT JSON parse | 541.70 | — | — | 2756.53 (5.09x) | 1561.76 (2.88x) |
| Any UInt64Value Exponent WKT JSON parse | 528.89 | — | — | 2700.36 (5.11x) | 1489.73 (2.82x) |
| Any ZeroUInt64Value WKT JSON stringify | 172.28 | — | — | 915.60 (5.31x) | 796.21 (4.62x) |
| Any ZeroUInt64Value WKT JSON parse | 517.55 | — | — | 2149.97 (4.15x) | 1469.73 (2.84x) |
| Any MaxUInt64Value WKT JSON stringify | 186.38 | — | — | 1565.20 (8.40x) | 863.08 (4.63x) |
| Any MaxUInt64Value WKT JSON parse | 555.72 | — | — | 2839.49 (5.11x) | 1668.93 (3.00x) |
| Any Int32Value WKT JSON stringify | 185.40 | — | — | 1544.79 (8.33x) | 737.63 (3.98x) |
| Any Int32Value WKT JSON parse | 523.92 | — | — | 2661.98 (5.08x) | 1439.84 (2.75x) |
| Any Int32Value String WKT JSON parse | 534.60 | — | — | 2670.70 (5.00x) | 1532.55 (2.87x) |
| Any Int32Value Exponent WKT JSON parse | 530.92 | — | — | 2697.36 (5.08x) | 1506.18 (2.84x) |
| Any ZeroInt32Value WKT JSON stringify | 179.16 | — | — | 1001.60 (5.59x) | 707.37 (3.95x) |
| Any ZeroInt32Value WKT JSON parse | 519.74 | — | — | 2147.07 (4.13x) | 1381.60 (2.66x) |
| Any NegativeInt32Value WKT JSON stringify | 186.11 | — | — | 1548.30 (8.32x) | 733.42 (3.94x) |
| Any NegativeInt32Value WKT JSON parse | 525.82 | — | — | 2691.84 (5.12x) | 1460.31 (2.78x) |
| Any MinInt32Value WKT JSON stringify | 189.25 | — | — | 1548.36 (8.18x) | 739.47 (3.91x) |
| Any MinInt32Value WKT JSON parse | 532.16 | — | — | 2708.60 (5.09x) | 1527.90 (2.87x) |
| Any MaxInt32Value WKT JSON stringify | 182.88 | — | — | 1546.32 (8.46x) | 741.50 (4.05x) |
| Any MaxInt32Value WKT JSON parse | 534.39 | — | — | 2676.07 (5.01x) | 1460.77 (2.73x) |
| Any UInt32Value WKT JSON stringify | 188.08 | — | — | 1549.36 (8.24x) | 744.37 (3.96x) |
| Any UInt32Value WKT JSON parse | 530.13 | — | — | 2668.71 (5.03x) | 1431.12 (2.70x) |
| Any UInt32Value String WKT JSON parse | 543.39 | — | — | 2660.80 (4.90x) | 1543.03 (2.84x) |
| Any UInt32Value Exponent WKT JSON parse | 535.98 | — | — | 2695.22 (5.03x) | 1506.40 (2.81x) |
| Any ZeroUInt32Value WKT JSON stringify | 187.13 | — | — | 916.19 (4.90x) | 718.94 (3.84x) |
| Any ZeroUInt32Value WKT JSON parse | 525.16 | — | — | 2149.27 (4.09x) | 1396.32 (2.66x) |
| Any MaxUInt32Value WKT JSON stringify | 189.94 | — | — | 1550.01 (8.16x) | 741.41 (3.90x) |
| Any MaxUInt32Value WKT JSON parse | 543.34 | — | — | 2683.02 (4.94x) | 1450.64 (2.67x) |
| Any BoolValue WKT JSON stringify | 175.51 | — | — | 1523.84 (8.68x) | 719.15 (4.10x) |
| Any BoolValue WKT JSON parse | 480.51 | — | — | 2606.05 (5.42x) | 1311.89 (2.73x) |
| Any FalseBoolValue WKT JSON stringify | 182.84 | — | — | 912.47 (4.99x) | 705.12 (3.86x) |
| Any FalseBoolValue WKT JSON parse | 483.74 | — | — | 2147.86 (4.44x) | 1342.91 (2.78x) |
| Any StringValue WKT JSON stringify | 211.99 | — | — | 1563.86 (7.38x) | 799.99 (3.77x) |
| Any StringValue WKT JSON parse | 541.84 | — | — | 2671.70 (4.93x) | 1397.04 (2.58x) |
| Any StringValue Escape WKT JSON parse | 550.48 | — | — | 2682.09 (4.87x) | 1532.85 (2.78x) |
| Any StringValue Surrogate WKT JSON parse | 555.28 | — | — | 2681.57 (4.83x) | 1549.01 (2.79x) |
| Any EmptyStringValue WKT JSON stringify | 200.52 | — | — | 914.87 (4.56x) | 765.63 (3.82x) |
| Any EmptyStringValue WKT JSON parse | 508.80 | — | — | 2159.70 (4.24x) | 1364.95 (2.68x) |
| Any BytesValue WKT JSON stringify | 188.97 | — | — | 1582.29 (8.37x) | 831.28 (4.40x) |
| Any BytesValue WKT JSON parse | 552.57 | — | — | 2678.81 (4.85x) | 1466.91 (2.65x) |
| Any BytesValue URL WKT JSON parse | 569.37 | — | — | 2677.28 (4.70x) | 1477.24 (2.59x) |
| Any BytesValue StandardBase64 WKT JSON parse | 555.25 | — | — | 2698.79 (4.86x) | 1496.83 (2.70x) |
| Any BytesValue Unpadded WKT JSON parse | 553.58 | — | — | 2671.44 (4.83x) | 1497.40 (2.70x) |
| Any EmptyBytesValue WKT JSON stringify | 179.47 | — | — | 913.42 (5.09x) | 757.27 (4.22x) |
| Any EmptyBytesValue WKT JSON parse | 514.95 | — | — | 2144.64 (4.16x) | 1433.34 (2.78x) |
| Nested Any WKT JSON stringify | 333.86 | — | — | 2482.13 (7.43x) | 1450.90 (4.35x) |
| Nested Any WKT JSON parse | 844.65 | — | — | 4281.07 (5.07x) | 2843.39 (3.37x) |
| Duration JSON stringify | 57.48 | — | — | 960.90 (16.72x) | 391.44 (6.81x) |
| Duration JSON parse | 19.94 | — | — | 1445.33 (72.48x) | 437.47 (21.94x) |
| Duration Escape JSON parse | 39.38 | — | — | 1484.58 (37.70x) | 441.58 (11.21x) |
| PlusDuration JSON parse | 19.57 | — | — | 1476.00 (75.42x) | 388.91 (19.87x) |
| ShortFractionDuration JSON parse | 17.57 | — | — | 1440.66 (82.00x) | 396.03 (22.54x) |
| MicroDuration JSON stringify | 59.92 | — | — | 970.92 (16.20x) | 399.09 (6.66x) |
| MicroDuration JSON parse | 21.38 | — | — | 1465.10 (68.53x) | 389.73 (18.23x) |
| NanoDuration JSON stringify | 57.23 | — | — | 994.59 (17.38x) | 405.55 (7.09x) |
| NanoDuration JSON parse | 25.23 | — | — | 1478.29 (58.59x) | 392.84 (15.57x) |
| NegativeDuration JSON stringify | 58.28 | — | — | 1012.25 (17.37x) | 435.92 (7.48x) |
| NegativeDuration JSON parse | 19.82 | — | — | 1508.65 (76.12x) | 391.21 (19.74x) |
| FractionalNegativeDuration JSON stringify | 58.25 | — | — | 976.72 (16.77x) | 432.93 (7.43x) |
| FractionalNegativeDuration JSON parse | 20.56 | — | — | 1458.26 (70.93x) | 373.92 (18.19x) |
| MaxDuration JSON stringify | 50.16 | — | — | 851.81 (16.98x) | 421.73 (8.41x) |
| MaxDuration JSON parse | 28.95 | — | — | 1435.07 (49.57x) | 396.55 (13.70x) |
| MinDuration JSON stringify | 50.23 | — | — | 873.22 (17.38x) | 434.34 (8.65x) |
| MinDuration JSON parse | 31.72 | — | — | 1446.33 (45.60x) | 691.27 (21.79x) |
| ZeroDuration JSON stringify | 44.86 | — | — | 813.35 (18.13x) | 357.40 (7.97x) |
| ZeroDuration JSON parse | 14.69 | — | — | 1368.83 (93.18x) | 307.56 (20.94x) |
| FieldMask JSON stringify | 67.37 | — | — | 883.05 (13.11x) | 658.71 (9.78x) |
| FieldMask JSON parse | 139.86 | — | — | 1656.43 (11.84x) | 884.25 (6.32x) |
| FieldMask Escape JSON parse | 191.51 | — | — | 1715.06 (8.96x) | 968.66 (5.06x) |
| EmptyFieldMask JSON stringify | 40.68 | — | — | 604.42 (14.86x) | 193.01 (4.74x) |
| EmptyFieldMask JSON parse | 4.78 | — | — | 941.21 (196.91x) | 162.29 (33.95x) |
| Timestamp JSON stringify | 96.40 | — | — | 1142.85 (11.86x) | 409.30 (4.25x) |
| Timestamp JSON parse | 45.42 | — | — | 1497.90 (32.98x) | 442.68 (9.75x) |
| Timestamp Escape JSON parse | 92.74 | — | — | 1535.81 (16.56x) | 507.09 (5.47x) |
| ShortFraction Timestamp JSON parse | 44.02 | — | — | 1492.37 (33.90x) | 438.59 (9.96x) |
| Micro Timestamp JSON stringify | 96.75 | — | — | 1143.91 (11.82x) | 416.86 (4.31x) |
| Micro Timestamp JSON parse | 50.14 | — | — | 1511.59 (30.15x) | 458.27 (9.14x) |
| Nano Timestamp JSON stringify | 94.24 | — | — | 1193.34 (12.66x) | 428.45 (4.55x) |
| Nano Timestamp JSON parse | 52.23 | — | — | 1524.01 (29.18x) | 464.12 (8.89x) |
| Offset Timestamp JSON parse | 52.26 | — | — | 1550.75 (29.67x) | 485.14 (9.28x) |
| PreEpoch Timestamp JSON stringify | 66.15 | — | — | 1060.27 (16.03x) | 400.44 (6.05x) |
| PreEpoch Timestamp JSON parse | 43.40 | — | — | 1467.13 (33.80x) | 423.67 (9.76x) |
| Max Timestamp JSON stringify | 78.49 | — | — | 1207.12 (15.38x) | 422.94 (5.39x) |
| Max Timestamp JSON parse | 54.70 | — | — | 1542.19 (28.19x) | 677.88 (12.39x) |
| Min Timestamp JSON stringify | 79.52 | — | — | 1057.06 (13.29x) | 401.53 (5.05x) |
| Min Timestamp JSON parse | 41.23 | — | — | 1457.62 (35.35x) | 424.58 (10.30x) |
| Empty JSON stringify | 20.83 | — | — | 494.70 (23.75x) | 79.93 (3.84x) |
| Empty JSON parse | 68.71 | — | — | 720.78 (10.49x) | 202.75 (2.95x) |
| Struct JSON stringify | 187.04 | — | — | 5724.96 (30.61x) | 3037.68 (16.24x) |
| Struct JSON parse | 848.10 | — | — | 10912.40 (12.87x) | 4659.54 (5.49x) |
| Struct Escape JSON parse | 894.33 | — | — | 10997.50 (12.30x) | 4792.74 (5.36x) |
| Struct NumberExponent JSON parse | 849.50 | — | — | 10941.80 (12.88x) | 4660.28 (5.49x) |
| Struct Surrogate JSON parse | 371.93 | — | — | 4794.80 (12.89x) | 1198.17 (3.22x) |
| Struct KeySurrogate JSON parse | 372.41 | — | — | 4768.21 (12.80x) | 1209.29 (3.25x) |
| EmptyStruct JSON stringify | 41.10 | — | — | 699.40 (17.02x) | 350.89 (8.54x) |
| EmptyStruct JSON parse | 86.94 | — | — | 2026.67 (23.31x) | 386.13 (4.44x) |
| Value JSON stringify | 194.22 | — | — | 6660.46 (34.29x) | 3194.81 (16.45x) |
| Value JSON parse | 888.13 | — | — | 12203.40 (13.74x) | 4899.34 (5.52x) |
| Value Escape JSON parse | 922.78 | — | — | 12312.60 (13.34x) | 5028.24 (5.45x) |
| Value NumberExponent JSON parse | 879.89 | — | — | 12240.20 (13.91x) | 4913.58 (5.58x) |
| Value Surrogate JSON parse | 397.96 | — | — | 6695.92 (16.83x) | 1482.49 (3.73x) |
| Value KeySurrogate JSON parse | 399.03 | — | — | 6663.69 (16.70x) | 1488.45 (3.73x) |
| NullValue JSON stringify | 40.50 | — | — | 1319.91 (32.59x) | 229.46 (5.67x) |
| NullValue JSON parse | 69.80 | — | — | 2466.30 (35.33x) | 350.01 (5.01x) |
| StringScalarValue JSON stringify | 47.62 | — | — | 1345.11 (28.25x) | 271.20 (5.70x) |
| StringScalarValue JSON parse | 140.67 | — | — | 2083.89 (14.81x) | 437.17 (3.11x) |
| StringScalarValue Escape JSON parse | 149.94 | — | — | 2130.11 (14.21x) | 498.97 (3.33x) |
| StringScalarValue Surrogate JSON parse | 148.57 | — | — | 2132.09 (14.35x) | 502.54 (3.38x) |
| EmptyStringScalarValue JSON stringify | 45.62 | — | — | 1333.99 (29.24x) | 273.23 (5.99x) |
| EmptyStringScalarValue JSON parse | 87.21 | — | — | 2060.79 (23.63x) | 358.90 (4.12x) |
| NumberValue JSON stringify | 73.91 | — | — | 1554.35 (21.03x) | 318.39 (4.31x) |
| NumberValue JSON parse | 131.45 | — | — | 2171.91 (16.52x) | 419.35 (3.19x) |
| NumberValue Exponent JSON parse | 133.56 | — | — | 2184.26 (16.35x) | 428.22 (3.21x) |
| NegativeNumberValue JSON stringify | 74.41 | — | — | 1553.51 (20.88x) | 323.16 (4.34x) |
| NegativeNumberValue JSON parse | 132.50 | — | — | 2168.18 (16.36x) | 639.48 (4.83x) |
| ZeroNumberValue JSON stringify | 50.74 | — | — | 1510.10 (29.76x) | 292.12 (5.76x) |
| ZeroNumberValue JSON parse | 129.03 | — | — | 2098.25 (16.26x) | 366.44 (2.84x) |
| BoolScalarValue JSON stringify | 40.61 | — | — | 1316.07 (32.41x) | 230.27 (5.67x) |
| BoolScalarValue JSON parse | 74.76 | — | — | 2006.94 (26.85x) | 348.54 (4.66x) |
| FalseBoolScalarValue JSON stringify | 40.55 | — | — | 1313.36 (32.39x) | 219.56 (5.41x) |
| FalseBoolScalarValue JSON parse | 70.16 | — | — | 2016.80 (28.75x) | 332.92 (4.75x) |
| ListKindValue JSON stringify | 145.11 | — | — | 6166.11 (42.49x) | 2263.14 (15.60x) |
| ListKindValue JSON parse | 677.74 | — | — | 10439.50 (15.40x) | 4029.37 (5.95x) |
| ListKindValue Escape JSON parse | 697.48 | — | — | 10494.70 (15.05x) | 4262.70 (6.11x) |
| ListKindValue Surrogate JSON parse | 319.94 | — | — | 4902.59 (15.32x) | 1185.62 (3.71x) |
| EmptyStructKindValue JSON stringify | 42.96 | — | — | 1936.16 (45.07x) | 522.02 (12.15x) |
| EmptyStructKindValue JSON parse | 116.49 | — | — | 3785.26 (32.49x) | 654.18 (5.62x) |
| EmptyListKindValue JSON stringify | 41.85 | — | — | 1939.04 (46.33x) | 362.04 (8.65x) |
| EmptyListKindValue JSON parse | 146.89 | — | — | 4057.35 (27.62x) | 597.55 (4.07x) |
| ListValue JSON stringify | 150.13 | — | — | 4760.10 (31.71x) | 2100.60 (13.99x) |
| ListValue JSON parse | 655.01 | — | — | 8547.73 (13.05x) | 3800.41 (5.80x) |
| ListValue Escape JSON parse | 676.05 | — | — | 8651.50 (12.80x) | 3993.95 (5.91x) |
| ListValue Surrogate JSON parse | 297.59 | — | — | 3112.66 (10.46x) | 918.18 (3.09x) |
| EmptyListValue JSON stringify | 40.46 | — | — | 683.00 (16.88x) | 185.92 (4.60x) |
| EmptyListValue JSON parse | 126.57 | — | — | 2251.65 (17.79x) | 331.45 (2.62x) |
| DoubleValue JSON stringify | 69.12 | — | — | 869.66 (12.58x) | 186.88 (2.70x) |
| DoubleValue JSON parse | 110.98 | — | — | 1237.67 (11.15x) | 281.30 (2.53x) |
| DoubleValue String JSON parse | 111.42 | — | — | 1179.34 (10.58x) | 379.89 (3.41x) |
| DoubleValue Exponent JSON parse | 112.90 | — | — | 1251.00 (11.08x) | 435.14 (3.85x) |
| NegativeDoubleValue JSON stringify | 67.28 | — | — | 869.35 (12.92x) | 191.85 (2.85x) |
| NegativeDoubleValue JSON parse | 111.18 | — | — | 1286.85 (11.57x) | 279.21 (2.51x) |
| ZeroDoubleValue JSON stringify | 47.18 | — | — | 807.31 (17.11x) | 141.82 (3.01x) |
| ZeroDoubleValue JSON parse | 108.20 | — | — | 1153.19 (10.66x) | 271.16 (2.51x) |
| DoubleValue NaN JSON stringify | 46.41 | — | — | 666.56 (14.36x) | 119.24 (2.57x) |
| DoubleValue NaN JSON parse | 105.85 | — | — | 1086.25 (10.26x) | 282.75 (2.67x) |
| DoubleValue Infinity JSON stringify | 48.20 | — | — | 671.45 (13.93x) | 118.98 (2.47x) |
| DoubleValue Infinity JSON parse | 106.05 | — | — | 1108.48 (10.45x) | 291.18 (2.75x) |
| DoubleValue NegativeInfinity JSON stringify | 48.13 | — | — | 664.73 (13.81x) | 122.10 (2.54x) |
| DoubleValue NegativeInfinity JSON parse | 108.26 | — | — | 1101.72 (10.18x) | 277.36 (2.56x) |
| FloatValue JSON stringify | 71.11 | — | — | 798.03 (11.22x) | 194.43 (2.73x) |
| FloatValue JSON parse | 110.38 | — | — | 1211.13 (10.97x) | 487.81 (4.42x) |
| FloatValue String JSON parse | 110.45 | — | — | 1149.12 (10.40x) | 374.81 (3.39x) |
| FloatValue Exponent JSON parse | 112.16 | — | — | 1219.46 (10.87x) | 290.93 (2.59x) |
| NegativeFloatValue JSON stringify | 70.83 | — | — | 796.07 (11.24x) | 188.52 (2.66x) |
| NegativeFloatValue JSON parse | 110.93 | — | — | 1217.66 (10.98x) | 306.86 (2.77x) |
| ZeroFloatValue JSON stringify | 47.22 | — | — | 768.87 (16.28x) | 137.42 (2.91x) |
| ZeroFloatValue JSON parse | 107.46 | — | — | 1221.70 (11.37x) | 273.49 (2.55x) |
| FloatValue NaN JSON stringify | 46.38 | — | — | 635.53 (13.70x) | 122.19 (2.63x) |
| FloatValue NaN JSON parse | 104.79 | — | — | 1077.74 (10.28x) | 260.63 (2.49x) |
| FloatValue Infinity JSON stringify | 47.88 | — | — | 636.58 (13.30x) | 122.64 (2.56x) |
| FloatValue Infinity JSON parse | 106.46 | — | — | 1092.14 (10.26x) | 272.70 (2.56x) |
| FloatValue NegativeInfinity JSON stringify | 48.12 | — | — | 635.61 (13.21x) | 128.49 (2.67x) |
| FloatValue NegativeInfinity JSON parse | 108.19 | — | — | 1090.14 (10.08x) | 281.70 (2.60x) |
| Int64Value JSON stringify | 50.69 | — | — | 673.77 (13.29x) | 280.56 (5.53x) |
| Int64Value JSON parse | 124.97 | — | — | 1226.14 (9.81x) | 468.14 (3.75x) |
| Int64Value Number JSON parse | 128.77 | — | — | 1293.07 (10.04x) | 372.62 (2.89x) |
| Int64Value Exponent JSON parse | 116.59 | — | — | 1245.70 (10.68x) | 366.08 (3.14x) |
| ZeroInt64Value JSON stringify | 41.17 | — | — | 610.47 (14.83x) | 200.46 (4.87x) |
| ZeroInt64Value JSON parse | 106.35 | — | — | 1100.96 (10.35x) | 339.53 (3.19x) |
| NegativeInt64Value JSON stringify | 49.95 | — | — | 673.16 (13.48x) | 281.27 (5.63x) |
| NegativeInt64Value JSON parse | 126.38 | — | — | 1213.01 (9.60x) | 479.88 (3.80x) |
| MinInt64Value JSON stringify | 49.32 | — | — | 676.15 (13.71x) | 286.12 (5.80x) |
| MinInt64Value JSON parse | 134.17 | — | — | 1253.24 (9.34x) | 496.24 (3.70x) |
| MaxInt64Value JSON stringify | 49.15 | — | — | 857.34 (17.44x) | 289.01 (5.88x) |
| MaxInt64Value JSON parse | 134.15 | — | — | 1240.98 (9.25x) | 463.16 (3.45x) |
| UInt64Value JSON stringify | 49.77 | — | — | 690.45 (13.87x) | 275.25 (5.53x) |
| UInt64Value JSON parse | 127.32 | — | — | 1222.87 (9.60x) | 479.34 (3.76x) |
| UInt64Value Number JSON parse | 128.09 | — | — | 1280.22 (9.99x) | 347.26 (2.71x) |
| UInt64Value Exponent JSON parse | 117.48 | — | — | 1229.90 (10.47x) | 366.12 (3.12x) |
| ZeroUInt64Value JSON stringify | 41.22 | — | — | 627.05 (15.21x) | 199.79 (4.85x) |
| ZeroUInt64Value JSON parse | 107.69 | — | — | 1096.89 (10.19x) | 340.80 (3.16x) |
| MaxUInt64Value JSON stringify | 49.13 | — | — | 691.18 (14.07x) | 288.11 (5.86x) |
| MaxUInt64Value JSON parse | 138.04 | — | — | 1253.61 (9.08x) | 478.31 (3.47x) |
| Int32Value JSON stringify | 46.87 | — | — | 630.25 (13.45x) | 138.01 (2.94x) |
| Int32Value JSON parse | 134.59 | — | — | 1178.18 (8.75x) | 312.63 (2.32x) |
| Int32Value String JSON parse | 137.63 | — | — | 1126.63 (8.19x) | 409.41 (2.97x) |
| Int32Value Exponent JSON parse | 137.10 | — | — | 1227.21 (8.95x) | 362.05 (2.64x) |
| ZeroInt32Value JSON stringify | 46.80 | — | — | 610.60 (13.05x) | 130.99 (2.80x) |
| ZeroInt32Value JSON parse | 129.33 | — | — | 1154.25 (8.92x) | 280.61 (2.17x) |
| NegativeInt32Value JSON stringify | 47.71 | — | — | 637.68 (13.37x) | 137.66 (2.89x) |
| NegativeInt32Value JSON parse | 133.22 | — | — | 1192.23 (8.95x) | 316.14 (2.37x) |
| MinInt32Value JSON stringify | 47.15 | — | — | 635.24 (13.47x) | 137.24 (2.91x) |
| MinInt32Value JSON parse | 139.46 | — | — | 1207.87 (8.66x) | 348.58 (2.50x) |
| MaxInt32Value JSON stringify | 47.16 | — | — | 631.43 (13.39x) | 140.86 (2.99x) |
| MaxInt32Value JSON parse | 139.99 | — | — | 1212.63 (8.66x) | 335.02 (2.39x) |
| UInt32Value JSON stringify | 46.91 | — | — | 645.05 (13.75x) | 136.41 (2.91x) |
| UInt32Value JSON parse | 134.20 | — | — | 1187.48 (8.85x) | 323.95 (2.41x) |
| UInt32Value String JSON parse | 137.21 | — | — | 1133.08 (8.26x) | 395.89 (2.89x) |
| UInt32Value Exponent JSON parse | 136.86 | — | — | 1227.68 (8.97x) | 360.50 (2.63x) |
| ZeroUInt32Value JSON stringify | 47.01 | — | — | 629.15 (13.38x) | 129.82 (2.76x) |
| ZeroUInt32Value JSON parse | 126.36 | — | — | 1153.00 (9.12x) | 274.50 (2.17x) |
| MaxUInt32Value JSON stringify | 47.28 | — | — | 649.95 (13.75x) | 137.48 (2.91x) |
| MaxUInt32Value JSON parse | 140.99 | — | — | 1219.44 (8.65x) | 340.83 (2.42x) |
| BoolValue JSON stringify | 45.11 | — | — | 611.24 (13.55x) | 125.87 (2.79x) |
| BoolValue JSON parse | 64.99 | — | — | 1065.82 (16.40x) | 218.19 (3.36x) |
| FalseBoolValue JSON stringify | 45.08 | — | — | 602.78 (13.37x) | 121.28 (2.69x) |
| FalseBoolValue JSON parse | 60.39 | — | — | 1065.91 (17.65x) | 211.63 (3.50x) |
| StringValue JSON stringify | 52.12 | — | — | 674.96 (12.95x) | 181.30 (3.48x) |
| StringValue JSON parse | 119.92 | — | — | 1145.93 (9.56x) | 312.92 (2.61x) |
| StringValue Escape JSON parse | 129.64 | — | — | 1169.29 (9.02x) | 376.68 (2.91x) |
| StringValue Surrogate JSON parse | 127.82 | — | — | 1165.73 (9.12x) | 378.79 (2.96x) |
| EmptyStringValue JSON stringify | 49.12 | — | — | 640.41 (13.04x) | 178.75 (3.64x) |
| EmptyStringValue JSON parse | 65.95 | — | — | 1119.37 (16.97x) | 242.46 (3.68x) |
| BytesValue JSON stringify | 48.96 | — | — | 658.23 (13.44x) | 211.87 (4.33x) |
| BytesValue JSON parse | 127.07 | — | — | 1172.37 (9.23x) | 345.71 (2.72x) |
| BytesValue URL JSON parse | 143.56 | — | — | 1158.27 (8.07x) | 327.70 (2.28x) |
| BytesValue StandardBase64 JSON parse | 125.35 | — | — | 1177.07 (9.39x) | 343.99 (2.74x) |
| BytesValue Unpadded JSON parse | 125.12 | — | — | 1157.73 (9.25x) | 560.69 (4.48x) |
| EmptyBytesValue JSON stringify | 40.64 | — | — | 634.52 (15.61x) | 188.56 (4.64x) |
| EmptyBytesValue JSON parse | 68.69 | — | — | 1253.48 (18.25x) | 301.97 (4.40x) |
| TextFormat format | 175.13 | — | — | 2572.33 (14.69x) | 2553.13 (14.58x) |
| TextFormat parse | 709.78 | — | — | 4984.28 (7.02x) | 6581.86 (9.27x) |
| packed fixed32 encode | 2.01 | 548.14 (272.71x) | 559.91 (278.56x) | 43.34 (21.56x) | 402.18 (200.09x) |
| packed fixed32 decode | 4.53 | 1048.47 (231.45x) | 1930.36 (426.13x) | 49.94 (11.02x) | 1558.58 (344.06x) |
| packed fixed64 encode | 2.01 | 572.73 (284.94x) | 560.97 (279.09x) | 75.78 (37.70x) | 395.85 (196.94x) |
| packed fixed64 decode | 4.53 | 1039.97 (229.57x) | 7939.21 (1752.58x) | 80.33 (17.73x) | 2188.21 (483.05x) |
| packed sfixed32 encode | 2.01 | 547.74 (272.51x) | 539.37 (268.34x) | 43.66 (21.72x) | 435.86 (216.85x) |
| packed sfixed32 decode | 4.53 | 1093.84 (241.47x) | 1963.84 (433.52x) | 49.44 (10.91x) | 1564.98 (345.47x) |
| packed sfixed64 encode | 2.01 | 569.01 (283.09x) | 561.16 (279.18x) | 75.72 (37.67x) | 393.12 (195.58x) |
| packed sfixed64 decode | 4.54 | 1021.41 (224.98x) | 7914.14 (1743.20x) | 79.46 (17.50x) | 2179.04 (479.96x) |
| packed float encode | 2.01 | 810.97 (403.47x) | 540.96 (269.13x) | 43.45 (21.61x) | 358.02 (178.12x) |
| packed float decode | 4.52 | 1049.79 (232.25x) | 2081.56 (460.52x) | 49.23 (10.89x) | 1535.04 (339.61x) |
| packed double encode | 2.00 | 827.73 (413.87x) | 561.53 (280.76x) | 75.56 (37.78x) | 353.48 (176.74x) |
| packed double decode | 4.52 | 971.95 (215.03x) | 2042.05 (451.78x) | 79.62 (17.62x) | 2162.82 (478.50x) |
| packed uint64 encode | 1294.59 | 4601.61 (3.55x) | 4019.69 (3.10x) | 2138.28 (1.65x) | 3443.83 (2.66x) |
| packed uint64 decode | 1782.54 | 2778.68 (1.56x) | 8870.14 (4.98x) | 2801.55 (1.57x) | 6333.34 (3.55x) |
| packed uint32 encode | 931.80 | 3607.85 (3.87x) | 3251.15 (3.49x) | 1735.76 (1.86x) | 2887.60 (3.10x) |
| packed uint32 decode | 1293.50 | 2427.76 (1.88x) | 3262.90 (2.52x) | 1988.67 (1.54x) | 4841.79 (3.74x) |
| packed int64 encode | 1381.17 | 11065.02 (8.01x) | 6048.45 (4.38x) | 2938.21 (2.13x) | 4121.53 (2.98x) |
| packed int64 decode | 2746.11 | 3371.44 (1.23x) | 10259.48 (3.74x) | 4716.07 (1.72x) | 7792.15 (2.84x) |
| packed sint32 encode | 780.99 | 3005.65 (3.85x) | 2858.27 (3.66x) | 1532.86 (1.96x) | 3394.54 (4.35x) |
| packed sint32 decode | 938.56 | 2552.38 (2.72x) | 3186.95 (3.40x) | 1235.07 (1.32x) | 3046.30 (3.25x) |
| packed sint64 encode | 1420.73 | 4929.65 (3.47x) | 4278.81 (3.01x) | 2403.59 (1.69x) | 4138.69 (2.91x) |
| packed sint64 decode | 2031.21 | 3060.77 (1.51x) | 9650.12 (4.75x) | 2933.38 (1.44x) | 6535.76 (3.22x) |
| packed bool encode | 2.00 | 1341.80 (670.90x) | 519.02 (259.51x) | 16.13 (8.06x) | 2219.11 (1109.56x) |
| packed bool decode | 262.90 | 1535.72 (5.84x) | 2554.58 (9.72x) | 805.34 (3.06x) | 1564.76 (5.95x) |
| packed enum encode | 271.98 | 2719.46 (10.00x) | 1806.00 (6.64x) | 1086.81 (4.00x) | 2491.14 (9.16x) |
| packed enum decode | 156.72 | 1528.41 (9.75x) | 2896.48 (18.48x) | 688.05 (4.39x) | 2011.54 (12.84x) |
| large map encode | 4027.49 | 16633.62 (4.13x) | 9782.75 (2.43x) | 21435.80 (5.32x) | 210251.54 (52.20x) |
| shuffled large map deterministic binary encode | 27740.15 | — | — | 91571.10 (3.30x) | 440286.00 (15.87x) |
| large map decode | 25452.71 | 90969.63 (3.57x) | 89576.96 (3.52x) | 92763.30 (3.64x) | 279146.22 (10.97x) |
The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound `Duration`, non-empty/escaped-input parse/number-exponent parse/surrogate-pair value parse/surrogate-pair key parse and empty `Struct`, object/escaped-object parse/object-number-exponent/object-surrogate-pair value parse/object-surrogate-pair key parse/list/escaped-list/surrogate-list/string-scalar/escaped-string-scalar/surrogate-string-scalar/number-exponent/negative-number `Value` (including default-like scalar and empty object/list kinds),
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
