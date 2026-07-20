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

Latest accepted comparison (`/tmp/pbz-compare-negative-number-value-json-final.log`,
summarized in `/tmp/pbz-summary-negative-number-value-json-final.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 17.14 | 127.55 (7.44x) | 66.64 (3.89x) | 121.09 (7.06x) | 790.34 (46.11x) |
| binary decode | 93.38 | 255.52 (2.74x) | 300.28 (3.22x) | 342.82 (3.67x) | 1160.11 (12.42x) |
| unknown fields count by number | 3.65 | — | — | 162.11 (44.41x) | — |
| deterministic binary encode | 54.14 | — | — | 134.97 (2.49x) | 1498.83 (27.68x) |
| scalarmix encode | 19.92 | 109.35 (5.49x) | 67.16 (3.37x) | 31.76 (1.59x) | 219.83 (11.04x) |
| scalarmix decode | 39.66 | 135.90 (3.43x) | 220.67 (5.56x) | 85.09 (2.15x) | 285.30 (7.19x) |
| textbytes encode | 11.53 | 80.69 (7.00x) | 44.09 (3.82x) | 117.49 (10.19x) | 158.48 (13.75x) |
| textbytes decode | 45.98 | 381.66 (8.30x) | 240.86 (5.24x) | 163.03 (3.55x) | 678.68 (14.76x) |
| largebytes encode | 17.54 | 2704.60 (154.20x) | 2649.03 (151.03x) | 2675.94 (152.56x) | 2703.93 (154.16x) |
| largebytes decode | 89.66 | 5734.59 (63.96x) | 3026.85 (33.76x) | 2732.34 (30.47x) | 31847.10 (355.20x) |
| presencemix encode | 18.46 | 55.21 (2.99x) | 28.50 (1.54x) | 55.79 (3.02x) | 327.21 (17.73x) |
| presencemix decode | 56.56 | 131.57 (2.33x) | 108.94 (1.93x) | 163.89 (2.90x) | 471.06 (8.33x) |
| complex encode | 49.70 | 135.74 (2.73x) | 101.21 (2.04x) | 170.71 (3.43x) | 940.18 (18.92x) |
| complex decode | 168.56 | 394.08 (2.34x) | 563.96 (3.35x) | 391.05 (2.32x) | 1405.38 (8.34x) |
| complex deterministic binary encode | 90.57 | — | — | 172.66 (1.91x) | 1116.67 (12.33x) |
| complex JSON stringify | 263.84 | — | — | 4935.26 (18.71x) | 5943.70 (22.53x) |
| complex JSON parse | 2409.33 | — | — | 11884.10 (4.93x) | 7650.75 (3.18x) |
| complex TextFormat format | 252.13 | — | — | 3773.94 (14.97x) | 7700.87 (30.54x) |
| complex TextFormat parse | 1784.36 | — | — | 7009.08 (3.93x) | 9590.40 (5.37x) |
| packed int32 encode | 620.22 | 3173.56 (5.12x) | 2510.52 (4.05x) | 1247.60 (2.01x) | 2745.88 (4.43x) |
| packed int32 decode | 763.90 | 1922.16 (2.52x) | 3204.43 (4.19x) | 942.88 (1.23x) | 4550.00 (5.96x) |
| JSON stringify | 160.09 | — | — | 3075.31 (19.21x) | 2172.00 (13.57x) |
| JSON parse | 1519.25 | — | — | 7436.14 (4.89x) | 4513.85 (2.97x) |
| Any WKT JSON stringify | 132.78 | — | — | 1890.36 (14.24x) | 935.01 (7.04x) |
| Any WKT JSON parse | 523.36 | — | — | 3010.69 (5.75x) | 1431.40 (2.74x) |
| Any Duration Escape WKT JSON parse | 539.76 | — | — | 3061.78 (5.67x) | 1594.28 (2.95x) |
| Any PlusDuration WKT JSON parse | 523.81 | — | — | 3051.01 (5.82x) | 2206.55 (4.21x) |
| Any ShortFractionDuration WKT JSON parse | 520.51 | — | — | 3047.32 (5.85x) | 1417.19 (2.72x) |
| Any MicroDuration WKT JSON stringify | 133.30 | — | — | 1905.93 (14.30x) | 958.58 (7.19x) |
| Any MicroDuration WKT JSON parse | 525.12 | — | — | 3047.10 (5.80x) | 1449.12 (2.76x) |
| Any NanoDuration WKT JSON stringify | 130.19 | — | — | 1939.51 (14.90x) | 940.47 (7.22x) |
| Any NanoDuration WKT JSON parse | 531.40 | — | — | 3079.95 (5.80x) | 1538.58 (2.90x) |
| Any NegativeDuration WKT JSON stringify | 132.89 | — | — | 2075.24 (15.62x) | 1024.50 (7.71x) |
| Any NegativeDuration WKT JSON parse | 528.00 | — | — | 3137.09 (5.94x) | 1482.64 (2.81x) |
| Any FractionalNegativeDuration WKT JSON stringify | 126.13 | — | — | 1917.18 (15.20x) | 951.77 (7.55x) |
| Any FractionalNegativeDuration WKT JSON parse | 520.62 | — | — | 3077.98 (5.91x) | 2482.90 (4.77x) |
| Any MaxDuration WKT JSON stringify | 122.77 | — | — | 1758.13 (14.32x) | 1018.41 (8.30x) |
| Any MaxDuration WKT JSON parse | 536.54 | — | — | 2982.23 (5.56x) | 1432.52 (2.67x) |
| Any MinDuration WKT JSON stringify | 121.60 | — | — | 1775.81 (14.60x) | 1181.39 (9.72x) |
| Any MinDuration WKT JSON parse | 537.72 | — | — | 3052.23 (5.68x) | 1806.86 (3.36x) |
| Any ZeroDuration WKT JSON stringify | 110.17 | — | — | 926.39 (8.41x) | 933.53 (8.47x) |
| Any ZeroDuration WKT JSON parse | 465.37 | — | — | 2262.96 (4.86x) | 1399.35 (3.01x) |
| Any FieldMask WKT JSON stringify | 257.62 | — | — | 1757.94 (6.82x) | 1496.04 (5.81x) |
| Any FieldMask WKT JSON parse | 709.33 | — | — | 3150.52 (4.44x) | 2056.29 (2.90x) |
| Any FieldMask Escape WKT JSON parse | 723.68 | — | — | 3263.21 (4.51x) | 3259.53 (4.50x) |
| Any EmptyFieldMask WKT JSON stringify | 112.62 | — | — | 918.91 (8.16x) | 906.91 (8.05x) |
| Any EmptyFieldMask WKT JSON parse | 441.87 | — | — | 2156.47 (4.88x) | 1280.68 (2.90x) |
| Any Timestamp WKT JSON stringify | 179.37 | — | — | 2020.52 (11.26x) | 1048.93 (5.85x) |
| Any Timestamp WKT JSON parse | 581.23 | — | — | 3017.80 (5.19x) | 2013.58 (3.46x) |
| Any Timestamp Escape WKT JSON parse | 600.78 | — | — | 3081.42 (5.13x) | 1747.90 (2.91x) |
| Any ShortFraction Timestamp WKT JSON parse | 570.14 | — | — | 3005.17 (5.27x) | 1582.60 (2.78x) |
| Any Micro Timestamp WKT JSON stringify | 179.65 | — | — | 2015.71 (11.22x) | 1037.24 (5.77x) |
| Any Micro Timestamp WKT JSON parse | 587.73 | — | — | 3039.43 (5.17x) | 1822.34 (3.10x) |
| Any Nano Timestamp WKT JSON stringify | 177.96 | — | — | 2033.62 (11.43x) | 1074.99 (6.04x) |
| Any Nano Timestamp WKT JSON parse | 591.50 | — | — | 3057.63 (5.17x) | 1697.34 (2.87x) |
| Any Offset Timestamp WKT JSON parse | 598.84 | — | — | 3059.26 (5.11x) | 1910.04 (3.19x) |
| Any PreEpoch Timestamp WKT JSON stringify | 146.91 | — | — | 1947.54 (13.26x) | 1226.89 (8.35x) |
| Any PreEpoch Timestamp WKT JSON parse | 563.85 | — | — | 3075.78 (5.45x) | 1691.09 (3.00x) |
| Any Max Timestamp WKT JSON stringify | 166.68 | — | — | 2042.13 (12.25x) | 1335.57 (8.01x) |
| Any Max Timestamp WKT JSON parse | 594.10 | — | — | 3091.78 (5.20x) | 1517.69 (2.55x) |
| Any Min Timestamp WKT JSON stringify | 163.76 | — | — | 1926.66 (11.77x) | 1020.13 (6.23x) |
| Any Min Timestamp WKT JSON parse | 559.66 | — | — | 3044.61 (5.44x) | 2288.42 (4.09x) |
| Any Empty WKT JSON stringify | 92.64 | — | — | 909.50 (9.82x) | 624.41 (6.74x) |
| Any Empty WKT JSON parse | 334.11 | — | — | 2130.31 (6.38x) | 1324.29 (3.96x) |
| Any Struct WKT JSON stringify | 651.77 | — | — | 5893.26 (9.04x) | 8393.34 (12.88x) |
| Any Struct WKT JSON parse | 1749.13 | — | — | 11096.90 (6.34x) | 11065.29 (6.33x) |
| Any Struct Escape WKT JSON parse | 1779.81 | — | — | 11145.40 (6.26x) | 12093.58 (6.79x) |
| Any Struct NumberExponent WKT JSON parse | 1752.09 | — | — | 11141.30 (6.36x) | 10997.08 (6.28x) |
| Any EmptyStruct WKT JSON stringify | 120.33 | — | — | 953.66 (7.93x) | 1132.60 (9.41x) |
| Any EmptyStruct WKT JSON parse | 436.72 | — | — | 2235.55 (5.12x) | 1517.53 (3.47x) |
| Any Value WKT JSON stringify | 662.61 | — | — | 5866.21 (8.85x) | 6498.94 (9.81x) |
| Any Value WKT JSON parse | 1807.65 | — | — | 11282.40 (6.24x) | 11908.89 (6.59x) |
| Any Value Escape WKT JSON parse | 1837.10 | — | — | 11435.30 (6.22x) | 10109.27 (5.50x) |
| Any Value NumberExponent WKT JSON parse | 1811.58 | — | — | 11364.60 (6.27x) | 9752.22 (5.38x) |
| Any NullValue WKT JSON stringify | 131.10 | — | — | 2255.52 (17.20x) | 930.82 (7.10x) |
| Any NullValue WKT JSON parse | 462.08 | — | — | 4061.54 (8.79x) | 1655.24 (3.58x) |
| Any StringScalarValue WKT JSON stringify | 153.73 | — | — | 2287.78 (14.88x) | 1152.89 (7.50x) |
| Any StringScalarValue WKT JSON parse | 517.64 | — | — | 3682.00 (7.11x) | 1964.66 (3.80x) |
| Any StringScalarValue Escape WKT JSON parse | 529.23 | — | — | 3723.57 (7.04x) | 1726.32 (3.26x) |
| Any EmptyStringScalarValue WKT JSON stringify | 139.82 | — | — | 2289.72 (16.38x) | 985.44 (7.05x) |
| Any EmptyStringScalarValue WKT JSON parse | 490.36 | — | — | 3615.13 (7.37x) | 1500.35 (3.06x) |
| Any NumberValue WKT JSON stringify | 177.21 | — | — | 2522.50 (14.23x) | 987.78 (5.57x) |
| Any NumberValue WKT JSON parse | 502.20 | — | — | 3699.47 (7.37x) | 1804.87 (3.59x) |
| Any NumberValue Exponent WKT JSON parse | 506.05 | — | — | 3707.81 (7.33x) | 1614.38 (3.19x) |
| Any NegativeNumberValue WKT JSON stringify | 177.96 | — | — | 2523.41 (14.18x) | 1358.02 (7.63x) |
| Any NegativeNumberValue WKT JSON parse | 505.55 | — | — | 3701.05 (7.32x) | 1755.59 (3.47x) |
| Any ZeroNumberValue WKT JSON stringify | 138.54 | — | — | 2473.75 (17.86x) | 879.98 (6.35x) |
| Any ZeroNumberValue WKT JSON parse | 499.86 | — | — | 3627.97 (7.26x) | 1494.93 (2.99x) |
| Any BoolScalarValue WKT JSON stringify | 132.19 | — | — | 2266.07 (17.14x) | 936.83 (7.09x) |
| Any BoolScalarValue WKT JSON parse | 463.66 | — | — | 3615.34 (7.80x) | 1461.35 (3.15x) |
| Any FalseBoolScalarValue WKT JSON stringify | 127.88 | — | — | 2252.95 (17.62x) | 944.72 (7.39x) |
| Any FalseBoolScalarValue WKT JSON parse | 463.61 | — | — | 3594.09 (7.75x) | 1561.32 (3.37x) |
| Any ListKindValue WKT JSON stringify | 510.89 | — | — | 5599.34 (10.96x) | 5138.93 (10.06x) |
| Any ListKindValue WKT JSON parse | 1375.04 | — | — | 12783.00 (9.30x) | 8120.88 (5.91x) |
| Any ListKindValue Escape WKT JSON parse | 1408.86 | — | — | 12631.20 (8.97x) | 8816.74 (6.26x) |
| Any EmptyStructKindValue WKT JSON stringify | 148.52 | — | — | 2941.64 (19.81x) | 1421.36 (9.57x) |
| Any EmptyStructKindValue WKT JSON parse | 497.28 | — | — | 5394.37 (10.85x) | 2053.39 (4.13x) |
| Any EmptyListKindValue WKT JSON stringify | 147.64 | — | — | 2887.12 (19.56x) | 1239.20 (8.39x) |
| Any EmptyListKindValue WKT JSON parse | 501.42 | — | — | 4389.04 (8.75x) | 2268.05 (4.52x) |
| Any DoubleValue WKT JSON stringify | 190.19 | — | — | 1796.53 (9.45x) | 1225.10 (6.44x) |
| Any DoubleValue WKT JSON parse | 520.32 | — | — | 2725.26 (5.24x) | 1469.23 (2.82x) |
| Any DoubleValue String WKT JSON parse | 529.40 | — | — | 2728.96 (5.15x) | 1693.34 (3.20x) |
| Any NegativeDoubleValue WKT JSON stringify | 190.90 | — | — | 1794.73 (9.40x) | 777.99 (4.08x) |
| Any NegativeDoubleValue WKT JSON parse | 519.08 | — | — | 2729.32 (5.26x) | 1419.52 (2.73x) |
| Any ZeroDoubleValue WKT JSON stringify | 159.69 | — | — | 912.91 (5.72x) | 699.79 (4.38x) |
| Any ZeroDoubleValue WKT JSON parse | 515.38 | — | — | 2150.67 (4.17x) | 1450.15 (2.81x) |
| Any DoubleValue NaN WKT JSON stringify | 152.40 | — | — | 1567.83 (10.29x) | 743.18 (4.88x) |
| Any DoubleValue NaN WKT JSON parse | 515.08 | — | — | 2635.85 (5.12x) | 1475.21 (2.86x) |
| Any DoubleValue Infinity WKT JSON stringify | 156.96 | — | — | 1564.65 (9.97x) | 740.89 (4.72x) |
| Any DoubleValue Infinity WKT JSON parse | 517.92 | — | — | 2689.12 (5.19x) | 1364.29 (2.63x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 159.97 | — | — | 1557.10 (9.73x) | 701.66 (4.39x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 519.44 | — | — | 3099.25 (5.97x) | 2064.22 (3.97x) |
| Any FloatValue WKT JSON stringify | 195.79 | — | — | 1738.15 (8.88x) | 788.68 (4.03x) |
| Any FloatValue WKT JSON parse | 517.62 | — | — | 2701.67 (5.22x) | 1345.37 (2.60x) |
| Any FloatValue String WKT JSON parse | 528.35 | — | — | 2713.15 (5.14x) | 1485.05 (2.81x) |
| Any NegativeFloatValue WKT JSON stringify | 199.89 | — | — | 1735.29 (8.68x) | 1066.54 (5.34x) |
| Any NegativeFloatValue WKT JSON parse | 518.14 | — | — | 2705.80 (5.22x) | 1580.16 (3.05x) |
| Any ZeroFloatValue WKT JSON stringify | 162.94 | — | — | 918.65 (5.64x) | 702.33 (4.31x) |
| Any ZeroFloatValue WKT JSON parse | 514.77 | — | — | 2148.17 (4.17x) | 1456.64 (2.83x) |
| Any FloatValue NaN WKT JSON stringify | 159.08 | — | — | 1564.91 (9.84x) | 728.21 (4.58x) |
| Any FloatValue NaN WKT JSON parse | 511.79 | — | — | 2654.12 (5.19x) | 1403.15 (2.74x) |
| Any FloatValue Infinity WKT JSON stringify | 165.29 | — | — | 1549.51 (9.37x) | 704.34 (4.26x) |
| Any FloatValue Infinity WKT JSON parse | 516.27 | — | — | 2653.23 (5.14x) | 1312.94 (2.54x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 160.96 | — | — | 1550.62 (9.63x) | 714.22 (4.44x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 520.20 | — | — | 2646.41 (5.09x) | 1390.05 (2.67x) |
| Any Int64Value WKT JSON stringify | 169.55 | — | — | 1559.39 (9.20x) | 807.63 (4.76x) |
| Any Int64Value WKT JSON parse | 553.23 | — | — | 2784.99 (5.03x) | 1571.72 (2.84x) |
| Any Int64Value Number WKT JSON parse | 548.37 | — | — | 2744.89 (5.01x) | 1443.54 (2.63x) |
| Any ZeroInt64Value WKT JSON stringify | 162.07 | — | — | 914.96 (5.65x) | 793.24 (4.89x) |
| Any ZeroInt64Value WKT JSON parse | 523.83 | — | — | 2154.42 (4.11x) | 1360.16 (2.60x) |
| Any NegativeInt64Value WKT JSON stringify | 172.30 | — | — | 1557.48 (9.04x) | 832.51 (4.83x) |
| Any NegativeInt64Value WKT JSON parse | 559.03 | — | — | 2804.10 (5.02x) | 1837.85 (3.29x) |
| Any MinInt64Value WKT JSON stringify | 173.67 | — | — | 1560.72 (8.99x) | 828.39 (4.77x) |
| Any MinInt64Value WKT JSON parse | 566.23 | — | — | 2812.72 (4.97x) | 1618.06 (2.86x) |
| Any MaxInt64Value WKT JSON stringify | 174.08 | — | — | 1560.90 (8.97x) | 942.04 (5.41x) |
| Any MaxInt64Value WKT JSON parse | 557.49 | — | — | 2813.24 (5.05x) | 1707.85 (3.06x) |
| Any UInt64Value WKT JSON stringify | 177.36 | — | — | 1560.88 (8.80x) | 1180.32 (6.65x) |
| Any UInt64Value WKT JSON parse | 549.13 | — | — | 2779.96 (5.06x) | 1654.61 (3.01x) |
| Any UInt64Value Number WKT JSON parse | 546.75 | — | — | 2753.21 (5.04x) | 1453.19 (2.66x) |
| Any ZeroUInt64Value WKT JSON stringify | 166.14 | — | — | 914.68 (5.51x) | 976.83 (5.88x) |
| Any ZeroUInt64Value WKT JSON parse | 520.09 | — | — | 2165.11 (4.16x) | 1470.60 (2.83x) |
| Any MaxUInt64Value WKT JSON stringify | 180.46 | — | — | 1566.63 (8.68x) | 864.57 (4.79x) |
| Any MaxUInt64Value WKT JSON parse | 556.86 | — | — | 2847.30 (5.11x) | 1689.81 (3.03x) |
| Any Int32Value WKT JSON stringify | 171.73 | — | — | 1561.79 (9.09x) | 879.04 (5.12x) |
| Any Int32Value WKT JSON parse | 533.69 | — | — | 2671.43 (5.01x) | 1438.08 (2.69x) |
| Any Int32Value String WKT JSON parse | 537.04 | — | — | 2679.50 (4.99x) | 1591.76 (2.96x) |
| Any ZeroInt32Value WKT JSON stringify | 170.91 | — | — | 927.94 (5.43x) | 858.81 (5.02x) |
| Any ZeroInt32Value WKT JSON parse | 524.80 | — | — | 2163.36 (4.12x) | 1353.26 (2.58x) |
| Any NegativeInt32Value WKT JSON stringify | 169.53 | — | — | 1558.89 (9.20x) | 1303.40 (7.69x) |
| Any NegativeInt32Value WKT JSON parse | 531.73 | — | — | 2703.90 (5.09x) | 2333.24 (4.39x) |
| Any MinInt32Value WKT JSON stringify | 175.77 | — | — | 1566.08 (8.91x) | 706.10 (4.02x) |
| Any MinInt32Value WKT JSON parse | 537.05 | — | — | 2708.33 (5.04x) | 1660.72 (3.09x) |
| Any MaxInt32Value WKT JSON stringify | 173.42 | — | — | 1549.24 (8.93x) | 775.62 (4.47x) |
| Any MaxInt32Value WKT JSON parse | 537.81 | — | — | 2671.63 (4.97x) | 1405.27 (2.61x) |
| Any UInt32Value WKT JSON stringify | 177.77 | — | — | 1551.55 (8.73x) | 778.60 (4.38x) |
| Any UInt32Value WKT JSON parse | 547.00 | — | — | 2670.73 (4.88x) | 1554.89 (2.84x) |
| Any UInt32Value String WKT JSON parse | 553.95 | — | — | 2670.25 (4.82x) | 1434.79 (2.59x) |
| Any ZeroUInt32Value WKT JSON stringify | 268.86 | — | — | 920.25 (3.42x) | 875.83 (3.26x) |
| Any ZeroUInt32Value WKT JSON parse | 854.24 | — | — | 2161.43 (2.53x) | 1559.05 (1.83x) |
| Any MaxUInt32Value WKT JSON stringify | 279.93 | — | — | 1555.59 (5.56x) | 722.82 (2.58x) |
| Any MaxUInt32Value WKT JSON parse | 914.77 | — | — | 2684.12 (2.93x) | 1534.69 (1.68x) |
| Any BoolValue WKT JSON stringify | 267.65 | — | — | 1529.40 (5.71x) | 680.13 (2.54x) |
| Any BoolValue WKT JSON parse | 774.11 | — | — | 2612.23 (3.37x) | 1458.78 (1.88x) |
| Any FalseBoolValue WKT JSON stringify | 264.36 | — | — | 926.62 (3.51x) | 728.19 (2.75x) |
| Any FalseBoolValue WKT JSON parse | 774.80 | — | — | 2336.41 (3.02x) | 1240.01 (1.60x) |
| Any StringValue WKT JSON stringify | 306.04 | — | — | 1557.10 (5.09x) | 836.14 (2.73x) |
| Any StringValue WKT JSON parse | 871.28 | — | — | 2657.66 (3.05x) | 1357.49 (1.56x) |
| Any StringValue Escape WKT JSON parse | 718.34 | — | — | 2692.33 (3.75x) | 1542.85 (2.15x) |
| Any EmptyStringValue WKT JSON stringify | 264.49 | — | — | 929.25 (3.51x) | 748.77 (2.83x) |
| Any EmptyStringValue WKT JSON parse | 606.74 | — | — | 2262.26 (3.73x) | 1315.49 (2.17x) |
| Any BytesValue WKT JSON stringify | 241.92 | — | — | 1591.75 (6.58x) | 853.26 (3.53x) |
| Any BytesValue WKT JSON parse | 743.76 | — | — | 2689.63 (3.62x) | 1372.63 (1.85x) |
| Any BytesValue URL WKT JSON parse | 594.07 | — | — | 2717.98 (4.58x) | 1487.79 (2.50x) |
| Any EmptyBytesValue WKT JSON stringify | 189.21 | — | — | 952.88 (5.04x) | 1074.40 (5.68x) |
| Any EmptyBytesValue WKT JSON parse | 526.25 | — | — | 2160.51 (4.11x) | 1908.19 (3.63x) |
| Nested Any WKT JSON stringify | 304.99 | — | — | 2474.51 (8.11x) | 1433.60 (4.70x) |
| Nested Any WKT JSON parse | 859.32 | — | — | 4249.38 (4.95x) | 2879.76 (3.35x) |
| Duration JSON stringify | 58.03 | — | — | 962.64 (16.59x) | 366.34 (6.31x) |
| Duration JSON parse | 19.32 | — | — | 1450.42 (75.07x) | 583.34 (30.19x) |
| Duration Escape JSON parse | 40.70 | — | — | 1483.14 (36.44x) | 436.25 (10.72x) |
| PlusDuration JSON parse | 18.71 | — | — | 1451.68 (77.59x) | 380.41 (20.33x) |
| ShortFractionDuration JSON parse | 16.07 | — | — | 1423.18 (88.56x) | 390.19 (24.28x) |
| MicroDuration JSON stringify | 59.53 | — | — | 972.80 (16.34x) | 397.89 (6.68x) |
| MicroDuration JSON parse | 21.58 | — | — | 1464.41 (67.86x) | 380.30 (17.62x) |
| NanoDuration JSON stringify | 57.14 | — | — | 1001.24 (17.52x) | 392.55 (6.87x) |
| NanoDuration JSON parse | 26.36 | — | — | 1476.50 (56.01x) | 383.58 (14.55x) |
| NegativeDuration JSON stringify | 58.50 | — | — | 999.52 (17.09x) | 418.81 (7.16x) |
| NegativeDuration JSON parse | 21.33 | — | — | 1504.99 (70.56x) | 398.45 (18.68x) |
| FractionalNegativeDuration JSON stringify | 58.47 | — | — | 966.22 (16.53x) | 408.60 (6.99x) |
| FractionalNegativeDuration JSON parse | 20.58 | — | — | 1674.06 (81.34x) | 381.23 (18.52x) |
| MaxDuration JSON stringify | 50.25 | — | — | 888.59 (17.68x) | 404.63 (8.05x) |
| MaxDuration JSON parse | 34.59 | — | — | 1450.51 (41.93x) | 386.66 (11.18x) |
| MinDuration JSON stringify | 50.14 | — | — | 868.82 (17.33x) | 421.76 (8.41x) |
| MinDuration JSON parse | 34.28 | — | — | 1453.60 (42.40x) | 375.44 (10.95x) |
| ZeroDuration JSON stringify | 44.88 | — | — | 820.25 (18.28x) | 348.09 (7.76x) |
| ZeroDuration JSON parse | 17.18 | — | — | 1370.12 (79.75x) | 309.23 (18.00x) |
| FieldMask JSON stringify | 97.10 | — | — | 885.00 (9.11x) | 646.00 (6.65x) |
| FieldMask JSON parse | 149.45 | — | — | 1651.19 (11.05x) | 864.73 (5.79x) |
| FieldMask Escape JSON parse | 206.09 | — | — | 1709.52 (8.30x) | 1057.01 (5.13x) |
| EmptyFieldMask JSON stringify | 40.88 | — | — | 611.55 (14.96x) | 228.30 (5.58x) |
| EmptyFieldMask JSON parse | 4.79 | — | — | 943.31 (196.93x) | 185.48 (38.72x) |
| Timestamp JSON stringify | 96.54 | — | — | 1142.29 (11.83x) | 421.16 (4.36x) |
| Timestamp JSON parse | 48.14 | — | — | 1485.30 (30.85x) | 419.45 (8.71x) |
| Timestamp Escape JSON parse | 102.32 | — | — | 1520.27 (14.86x) | 504.66 (4.93x) |
| ShortFraction Timestamp JSON parse | 43.83 | — | — | 1477.93 (33.72x) | 438.80 (10.01x) |
| Micro Timestamp JSON stringify | 97.37 | — | — | 1144.57 (11.75x) | 430.59 (4.42x) |
| Micro Timestamp JSON parse | 51.98 | — | — | 1513.11 (29.11x) | 461.58 (8.88x) |
| Nano Timestamp JSON stringify | 95.25 | — | — | 1183.32 (12.42x) | 456.88 (4.80x) |
| Nano Timestamp JSON parse | 56.85 | — | — | 1543.52 (27.15x) | 471.91 (8.30x) |
| Offset Timestamp JSON parse | 61.33 | — | — | 1529.12 (24.93x) | 480.99 (7.84x) |
| PreEpoch Timestamp JSON stringify | 67.19 | — | — | 1063.60 (15.83x) | 395.57 (5.89x) |
| PreEpoch Timestamp JSON parse | 43.04 | — | — | 1467.54 (34.10x) | 427.83 (9.94x) |
| Max Timestamp JSON stringify | 80.32 | — | — | 1188.86 (14.80x) | 428.86 (5.34x) |
| Max Timestamp JSON parse | 52.91 | — | — | 1535.83 (29.03x) | 524.86 (9.92x) |
| Min Timestamp JSON stringify | 79.56 | — | — | 1054.80 (13.26x) | 442.98 (5.57x) |
| Min Timestamp JSON parse | 40.99 | — | — | 1449.09 (35.35x) | 407.75 (9.95x) |
| Empty JSON stringify | 21.09 | — | — | 498.20 (23.62x) | 80.77 (3.83x) |
| Empty JSON parse | 68.18 | — | — | 719.17 (10.55x) | 230.92 (3.39x) |
| Struct JSON stringify | 176.46 | — | — | 5776.18 (32.73x) | 3134.40 (17.76x) |
| Struct JSON parse | 848.18 | — | — | 10838.70 (12.78x) | 4953.10 (5.84x) |
| Struct Escape JSON parse | 899.30 | — | — | 10951.20 (12.18x) | 5652.88 (6.29x) |
| Struct NumberExponent JSON parse | 850.07 | — | — | 10898.20 (12.82x) | 5354.01 (6.30x) |
| EmptyStruct JSON stringify | 41.38 | — | — | 701.29 (16.95x) | 444.40 (10.74x) |
| EmptyStruct JSON parse | 90.93 | — | — | 2019.32 (22.21x) | 360.58 (3.97x) |
| Value JSON stringify | 178.82 | — | — | 6584.82 (36.82x) | 3445.81 (19.27x) |
| Value JSON parse | 882.36 | — | — | 12338.00 (13.98x) | 5319.18 (6.03x) |
| Value Escape JSON parse | 915.70 | — | — | 12328.10 (13.46x) | 5355.46 (5.85x) |
| Value NumberExponent JSON parse | 873.59 | — | — | 12222.70 (13.99x) | 5221.87 (5.98x) |
| NullValue JSON stringify | 41.01 | — | — | 1324.27 (32.29x) | 222.12 (5.42x) |
| NullValue JSON parse | 70.51 | — | — | 2489.64 (35.31x) | 335.97 (4.76x) |
| StringScalarValue JSON stringify | 48.48 | — | — | 1347.62 (27.80x) | 264.28 (5.45x) |
| StringScalarValue JSON parse | 141.20 | — | — | 2103.31 (14.90x) | 400.56 (2.84x) |
| StringScalarValue Escape JSON parse | 151.04 | — | — | 2142.63 (14.19x) | 488.76 (3.24x) |
| EmptyStringScalarValue JSON stringify | 46.45 | — | — | 1340.11 (28.85x) | 272.47 (5.87x) |
| EmptyStringScalarValue JSON parse | 88.15 | — | — | 2085.53 (23.66x) | 334.49 (3.79x) |
| NumberValue JSON stringify | 74.46 | — | — | 1559.02 (20.94x) | 325.33 (4.37x) |
| NumberValue JSON parse | 133.33 | — | — | 2193.97 (16.46x) | 384.92 (2.89x) |
| NumberValue Exponent JSON parse | 135.14 | — | — | 2205.06 (16.32x) | 411.25 (3.04x) |
| NegativeNumberValue JSON stringify | 73.89 | — | — | 1561.91 (21.14x) | 336.60 (4.56x) |
| NegativeNumberValue JSON parse | 133.38 | — | — | 2201.83 (16.51x) | 403.27 (3.02x) |
| ZeroNumberValue JSON stringify | 51.24 | — | — | 1506.58 (29.40x) | 297.31 (5.80x) |
| ZeroNumberValue JSON parse | 130.37 | — | — | 2128.52 (16.33x) | 386.77 (2.97x) |
| BoolScalarValue JSON stringify | 40.98 | — | — | 1318.73 (32.18x) | 211.49 (5.16x) |
| BoolScalarValue JSON parse | 70.67 | — | — | 2034.10 (28.78x) | 309.97 (4.39x) |
| FalseBoolScalarValue JSON stringify | 40.97 | — | — | 1315.89 (32.12x) | 227.48 (5.55x) |
| FalseBoolScalarValue JSON parse | 71.16 | — | — | 2056.91 (28.91x) | 349.26 (4.91x) |
| ListKindValue JSON stringify | 139.62 | — | — | 6163.26 (44.14x) | 2506.20 (17.95x) |
| ListKindValue JSON parse | 678.82 | — | — | 10479.40 (15.44x) | 3874.68 (5.71x) |
| ListKindValue Escape JSON parse | 700.93 | — | — | 10656.50 (15.20x) | 4332.03 (6.18x) |
| EmptyStructKindValue JSON stringify | 42.87 | — | — | 1933.58 (45.10x) | 539.96 (12.60x) |
| EmptyStructKindValue JSON parse | 119.18 | — | — | 3731.29 (31.31x) | 629.03 (5.28x) |
| EmptyListKindValue JSON stringify | 41.72 | — | — | 1925.54 (46.15x) | 355.49 (8.52x) |
| EmptyListKindValue JSON parse | 148.47 | — | — | 4051.04 (27.29x) | 601.15 (4.05x) |
| ListValue JSON stringify | 146.91 | — | — | 4728.94 (32.19x) | 2070.49 (14.09x) |
| ListValue JSON parse | 656.37 | — | — | 8732.48 (13.30x) | 3919.36 (5.97x) |
| ListValue Escape JSON parse | 676.76 | — | — | 8581.51 (12.68x) | 4318.42 (6.38x) |
| EmptyListValue JSON stringify | 40.35 | — | — | 686.58 (17.02x) | 189.33 (4.69x) |
| EmptyListValue JSON parse | 127.98 | — | — | 2266.44 (17.71x) | 661.70 (5.17x) |
| DoubleValue JSON stringify | 68.47 | — | — | 872.17 (12.74x) | 369.85 (5.40x) |
| DoubleValue JSON parse | 111.55 | — | — | 1224.49 (10.98x) | 313.19 (2.81x) |
| DoubleValue String JSON parse | 111.66 | — | — | 1162.31 (10.41x) | 755.62 (6.77x) |
| NegativeDoubleValue JSON stringify | 68.85 | — | — | 864.92 (12.56x) | 197.53 (2.87x) |
| NegativeDoubleValue JSON parse | 112.00 | — | — | 1234.86 (11.03x) | 338.25 (3.02x) |
| ZeroDoubleValue JSON stringify | 47.64 | — | — | 809.44 (16.99x) | 144.57 (3.03x) |
| ZeroDoubleValue JSON parse | 108.98 | — | — | 1163.40 (10.68x) | 260.52 (2.39x) |
| DoubleValue NaN JSON stringify | 46.63 | — | — | 672.85 (14.43x) | 140.72 (3.02x) |
| DoubleValue NaN JSON parse | 104.81 | — | — | 1090.33 (10.40x) | 273.99 (2.61x) |
| DoubleValue Infinity JSON stringify | 48.24 | — | — | 668.12 (13.85x) | 146.31 (3.03x) |
| DoubleValue Infinity JSON parse | 106.31 | — | — | 1129.86 (10.63x) | 275.55 (2.59x) |
| DoubleValue NegativeInfinity JSON stringify | 48.38 | — | — | 664.38 (13.73x) | 146.41 (3.03x) |
| DoubleValue NegativeInfinity JSON parse | 108.04 | — | — | 1109.14 (10.27x) | 265.46 (2.46x) |
| FloatValue JSON stringify | 71.23 | — | — | 809.78 (11.37x) | 199.11 (2.80x) |
| FloatValue JSON parse | 110.68 | — | — | 1213.76 (10.97x) | 264.60 (2.39x) |
| FloatValue String JSON parse | 110.38 | — | — | 1151.43 (10.43x) | 346.25 (3.14x) |
| NegativeFloatValue JSON stringify | 71.81 | — | — | 811.36 (11.30x) | 212.77 (2.96x) |
| NegativeFloatValue JSON parse | 110.75 | — | — | 1214.37 (10.96x) | 277.56 (2.51x) |
| ZeroFloatValue JSON stringify | 47.57 | — | — | 754.35 (15.86x) | 134.42 (2.83x) |
| ZeroFloatValue JSON parse | 107.70 | — | — | 1151.87 (10.70x) | 254.12 (2.36x) |
| FloatValue NaN JSON stringify | 46.46 | — | — | 648.27 (13.95x) | 118.81 (2.56x) |
| FloatValue NaN JSON parse | 104.78 | — | — | 1078.52 (10.29x) | 267.62 (2.55x) |
| FloatValue Infinity JSON stringify | 48.16 | — | — | 653.37 (13.57x) | 136.69 (2.84x) |
| FloatValue Infinity JSON parse | 105.87 | — | — | 1095.29 (10.35x) | 265.27 (2.51x) |
| FloatValue NegativeInfinity JSON stringify | 48.13 | — | — | 646.18 (13.43x) | 137.78 (2.86x) |
| FloatValue NegativeInfinity JSON parse | 107.95 | — | — | 1095.09 (10.14x) | 295.36 (2.74x) |
| Int64Value JSON stringify | 50.02 | — | — | 672.71 (13.45x) | 271.18 (5.42x) |
| Int64Value JSON parse | 126.00 | — | — | 1222.32 (9.70x) | 420.64 (3.34x) |
| Int64Value Number JSON parse | 126.76 | — | — | 1277.36 (10.08x) | 345.75 (2.73x) |
| ZeroInt64Value JSON stringify | 41.45 | — | — | 606.98 (14.64x) | 187.28 (4.52x) |
| ZeroInt64Value JSON parse | 105.67 | — | — | 1093.30 (10.35x) | 332.01 (3.14x) |
| NegativeInt64Value JSON stringify | 48.47 | — | — | 671.47 (13.85x) | 446.47 (9.21x) |
| NegativeInt64Value JSON parse | 127.48 | — | — | 1210.34 (9.49x) | 479.01 (3.76x) |
| MinInt64Value JSON stringify | 49.98 | — | — | 672.77 (13.46x) | 274.04 (5.48x) |
| MinInt64Value JSON parse | 134.16 | — | — | 1243.33 (9.27x) | 492.26 (3.67x) |
| MaxInt64Value JSON stringify | 49.42 | — | — | 674.69 (13.65x) | 283.01 (5.73x) |
| MaxInt64Value JSON parse | 134.37 | — | — | 1241.81 (9.24x) | 460.65 (3.43x) |
| UInt64Value JSON stringify | 50.43 | — | — | 683.62 (13.56x) | 269.32 (5.34x) |
| UInt64Value JSON parse | 124.42 | — | — | 1224.85 (9.84x) | 442.27 (3.55x) |
| UInt64Value Number JSON parse | 127.11 | — | — | 1282.93 (10.09x) | 542.92 (4.27x) |
| ZeroUInt64Value JSON stringify | 41.68 | — | — | 614.38 (14.74x) | 183.86 (4.41x) |
| ZeroUInt64Value JSON parse | 103.83 | — | — | 1097.09 (10.57x) | 352.73 (3.40x) |
| MaxUInt64Value JSON stringify | 50.07 | — | — | 682.60 (13.63x) | 292.48 (5.84x) |
| MaxUInt64Value JSON parse | 136.21 | — | — | 1246.06 (9.15x) | 491.20 (3.61x) |
| Int32Value JSON stringify | 46.27 | — | — | 642.75 (13.89x) | 134.20 (2.90x) |
| Int32Value JSON parse | 117.50 | — | — | 1184.14 (10.08x) | 314.92 (2.68x) |
| Int32Value String JSON parse | 114.22 | — | — | 1123.47 (9.84x) | 378.88 (3.32x) |
| ZeroInt32Value JSON stringify | 46.17 | — | — | 624.97 (13.54x) | 141.42 (3.06x) |
| ZeroInt32Value JSON parse | 113.00 | — | — | 1149.91 (10.18x) | 258.98 (2.29x) |
| NegativeInt32Value JSON stringify | 46.29 | — | — | 649.89 (14.04x) | 153.22 (3.31x) |
| NegativeInt32Value JSON parse | 116.65 | — | — | 1188.38 (10.19x) | 312.46 (2.68x) |
| MinInt32Value JSON stringify | 46.90 | — | — | 652.11 (13.90x) | 131.65 (2.81x) |
| MinInt32Value JSON parse | 122.46 | — | — | 1206.32 (9.85x) | 360.62 (2.94x) |
| MaxInt32Value JSON stringify | 47.11 | — | — | 643.55 (13.66x) | 152.62 (3.24x) |
| MaxInt32Value JSON parse | 123.45 | — | — | 1200.95 (9.73x) | 373.34 (3.02x) |
| UInt32Value JSON stringify | 46.14 | — | — | 643.61 (13.95x) | 236.65 (5.13x) |
| UInt32Value JSON parse | 117.09 | — | — | 1181.94 (10.09x) | 343.46 (2.93x) |
| UInt32Value String JSON parse | 114.72 | — | — | 1156.28 (10.08x) | 386.65 (3.37x) |
| ZeroUInt32Value JSON stringify | 46.28 | — | — | 624.78 (13.50x) | 122.07 (2.64x) |
| ZeroUInt32Value JSON parse | 112.93 | — | — | 1150.52 (10.19x) | 249.24 (2.21x) |
| MaxUInt32Value JSON stringify | 46.80 | — | — | 643.37 (13.75x) | 136.14 (2.91x) |
| MaxUInt32Value JSON parse | 122.97 | — | — | 1200.44 (9.76x) | 326.64 (2.66x) |
| BoolValue JSON stringify | 45.95 | — | — | 612.73 (13.33x) | 215.96 (4.70x) |
| BoolValue JSON parse | 59.39 | — | — | 1058.87 (17.83x) | 240.05 (4.04x) |
| FalseBoolValue JSON stringify | 45.58 | — | — | 603.01 (13.23x) | 164.18 (3.60x) |
| FalseBoolValue JSON parse | 59.90 | — | — | 1055.15 (17.62x) | 326.78 (5.46x) |
| StringValue JSON stringify | 51.89 | — | — | 678.63 (13.08x) | 186.51 (3.59x) |
| StringValue JSON parse | 121.90 | — | — | 1148.56 (9.42x) | 298.92 (2.45x) |
| StringValue Escape JSON parse | 131.41 | — | — | 1176.71 (8.95x) | 355.76 (2.71x) |
| EmptyStringValue JSON stringify | 48.93 | — | — | 641.67 (13.11x) | 180.45 (3.69x) |
| EmptyStringValue JSON parse | 66.91 | — | — | 1113.11 (16.64x) | 233.29 (3.49x) |
| BytesValue JSON stringify | 49.60 | — | — | 669.80 (13.50x) | 199.66 (4.03x) |
| BytesValue JSON parse | 125.09 | — | — | 1167.39 (9.33x) | 319.65 (2.56x) |
| BytesValue URL JSON parse | 140.80 | — | — | 1162.88 (8.26x) | 310.76 (2.21x) |
| EmptyBytesValue JSON stringify | 41.11 | — | — | 673.90 (16.39x) | 196.72 (4.79x) |
| EmptyBytesValue JSON parse | 68.28 | — | — | 1131.46 (16.57x) | 428.65 (6.28x) |
| TextFormat format | 178.97 | — | — | 2563.23 (14.32x) | 2351.71 (13.14x) |
| TextFormat parse | 667.46 | — | — | 5081.65 (7.61x) | 6577.20 (9.85x) |
| packed fixed32 encode | 2.00 | 550.07 (275.04x) | 539.19 (269.60x) | 43.62 (21.81x) | 424.77 (212.38x) |
| packed fixed32 decode | 4.53 | 1052.64 (232.37x) | 1969.89 (434.85x) | 49.66 (10.96x) | 1735.89 (383.20x) |
| packed fixed64 encode | 2.01 | 572.83 (284.99x) | 561.05 (279.13x) | 76.10 (37.86x) | 580.82 (288.97x) |
| packed fixed64 decode | 4.52 | 1033.16 (228.58x) | 7941.21 (1756.90x) | 79.71 (17.64x) | 2607.76 (576.94x) |
| packed sfixed32 encode | 2.01 | 556.75 (276.99x) | 539.74 (268.53x) | 43.96 (21.87x) | 455.53 (226.63x) |
| packed sfixed32 decode | 4.52 | 1042.95 (230.74x) | 1980.25 (438.11x) | 48.95 (10.83x) | 1672.69 (370.06x) |
| packed sfixed64 encode | 2.90 | 571.01 (196.90x) | 561.12 (193.49x) | 75.68 (26.10x) | 404.59 (139.51x) |
| packed sfixed64 decode | 9.05 | 1008.70 (111.46x) | 7897.48 (872.65x) | 79.74 (8.81x) | 2526.49 (279.17x) |
| packed float encode | 2.00 | 811.40 (405.70x) | 539.50 (269.75x) | 44.34 (22.17x) | 375.63 (187.81x) |
| packed float decode | 4.54 | 1040.92 (229.28x) | 2048.37 (451.18x) | 48.67 (10.72x) | 1712.71 (377.25x) |
| packed double encode | 2.01 | 830.79 (413.33x) | 592.57 (294.81x) | 75.72 (37.67x) | 353.12 (175.68x) |
| packed double decode | 4.52 | 968.66 (214.31x) | 2041.52 (451.66x) | 79.03 (17.48x) | 2637.33 (583.48x) |
| packed uint64 encode | 1636.99 | 4614.97 (2.82x) | 4014.25 (2.45x) | 2125.74 (1.30x) | 3593.77 (2.20x) |
| packed uint64 decode | 1782.43 | 2774.69 (1.56x) | 8849.40 (4.96x) | 2800.45 (1.57x) | 8606.94 (4.83x) |
| packed uint32 encode | 984.46 | 3624.51 (3.68x) | 3276.49 (3.33x) | 1739.50 (1.77x) | 2878.79 (2.92x) |
| packed uint32 decode | 1325.20 | 2422.88 (1.83x) | 3262.46 (2.46x) | 1988.81 (1.50x) | 6457.06 (4.87x) |
| packed int64 encode | 1413.35 | 10959.41 (7.75x) | 6067.90 (4.29x) | 2885.95 (2.04x) | 4110.55 (2.91x) |
| packed int64 decode | 2737.49 | 3369.05 (1.23x) | 10253.40 (3.75x) | 4753.65 (1.74x) | 12288.08 (4.49x) |
| packed sint32 encode | 778.07 | 3042.94 (3.91x) | 2837.75 (3.65x) | 1544.53 (1.99x) | 3602.88 (4.63x) |
| packed sint32 decode | 937.50 | 2549.90 (2.72x) | 3185.23 (3.40x) | 1141.94 (1.22x) | 5821.22 (6.21x) |
| packed sint64 encode | 1417.72 | 4938.12 (3.48x) | 4309.57 (3.04x) | 2406.81 (1.70x) | 4147.25 (2.93x) |
| packed sint64 decode | 2036.49 | 3082.92 (1.51x) | 9666.63 (4.75x) | 2931.07 (1.44x) | 9213.50 (4.52x) |
| packed bool encode | 2.01 | 1312.96 (653.21x) | 521.71 (259.56x) | 16.13 (8.03x) | 2303.44 (1145.99x) |
| packed bool decode | 264.29 | 1556.36 (5.89x) | 2550.26 (9.65x) | 804.84 (3.05x) | 2190.95 (8.29x) |
| packed enum encode | 273.55 | 2713.28 (9.92x) | 1892.18 (6.92x) | 1085.91 (3.97x) | 2509.33 (9.17x) |
| packed enum decode | 151.55 | 1590.80 (10.50x) | 2985.86 (19.70x) | 700.21 (4.62x) | 2948.07 (19.45x) |
| large map encode | 4086.92 | 18107.79 (4.43x) | 9726.49 (2.38x) | 22694.60 (5.55x) | 199247.13 (48.75x) |
| shuffled large map deterministic binary encode | 28607.94 | — | — | 104929.00 (3.67x) | 389190.11 (13.60x) |
| large map decode | 25642.06 | 90526.13 (3.53x) | 89451.28 (3.49x) | 94451.80 (3.68x) | 275736.42 (10.75x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound `Duration`, non-empty/escaped-input parse/number-exponent parse and empty `Struct`, object/escaped-object parse/object-number-exponent/list/escaped-list/string-scalar/escaped-string-scalar/number-exponent/negative-number `Value` (including default-like scalar and empty object/list kinds),
`FieldMask` (non-empty, escaped JSON parse input, and empty), escaped-input parse/short-fraction parse/micro/nano/offset/min/pre/post/max-bound `Timestamp`, `Empty`, min/zero/positive/number-input parse/negative/max `Int64Value`, negative/zero/positive finite/string-input parse `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), negative/zero/positive finite/string-input parse `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), zero/normal/number-input parse/max `UInt64Value`, min/zero/positive/string-input parse/negative/max `Int32Value`, zero/normal/string-input parse/max `UInt32Value`, true/false `BoolValue`, non-empty/escape-input parse/empty `StringValue`, base64/base64url parse/empty `BytesValue`, and recursive nested `Any` payloads), direct zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound Duration, non-empty/escaped-input parse/empty FieldMask, and escaped-input parse/short-fraction parse/micro/nano/offset/min/pre/post/max-bound Timestamp WKT JSON plus other direct WKT JSON, including non-empty/escaped-input parse/number-exponent parse/empty `Struct`, object/escaped-object parse/object-number-exponent/list/escaped-list/string-scalar/escaped-string-scalar/number-exponent/negative-number `Value`, and escaped/non-empty/empty `ListValue`, TextFormat, packed scalars, large bytes,
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
