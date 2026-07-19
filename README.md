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

Latest accepted comparison (`/tmp/pbz-compare-short-fraction-duration-json-isolated.log`,
summarized in `/tmp/pbz-summary-short-fraction-duration-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 23.56 | 102.49 (4.35x) | 50.23 (2.13x) | 103.52 (4.39x) | 796.18 (33.79x) |
| binary decode | 134.50 | 249.59 (1.86x) | 235.42 (1.75x) | 223.04 (1.66x) | 898.57 (6.68x) |
| unknown fields count by number | 3.57 | — | — | 162.65 (45.56x) | — |
| deterministic binary encode | 69.08 | — | — | 124.09 (1.80x) | 1049.14 (15.19x) |
| scalarmix encode | 27.51 | 110.03 (4.00x) | 48.80 (1.77x) | 29.07 (1.06x) | 209.08 (7.60x) |
| scalarmix decode | 50.74 | 134.85 (2.66x) | 182.25 (3.59x) | 80.27 (1.58x) | 297.61 (5.87x) |
| textbytes encode | 13.52 | 78.78 (5.83x) | 44.35 (3.28x) | 118.30 (8.75x) | 153.68 (11.37x) |
| textbytes decode | 67.60 | 381.75 (5.65x) | 253.06 (3.74x) | 165.61 (2.45x) | 681.99 (10.09x) |
| largebytes encode | 17.54 | 2712.19 (154.63x) | 2682.77 (152.95x) | 2688.05 (153.25x) | 2702.48 (154.08x) |
| largebytes decode | 88.85 | 5750.46 (64.72x) | 3054.95 (34.38x) | 2724.04 (30.66x) | 24502.93 (275.78x) |
| presencemix encode | 16.80 | 57.97 (3.45x) | 28.58 (1.70x) | 54.71 (3.26x) | 221.53 (13.19x) |
| presencemix decode | 58.24 | 130.17 (2.24x) | 112.14 (1.93x) | 164.94 (2.83x) | 498.62 (8.56x) |
| complex encode | 53.01 | 141.46 (2.67x) | 99.78 (1.88x) | 161.24 (3.04x) | 926.19 (17.47x) |
| complex decode | 169.67 | 392.04 (2.31x) | 343.91 (2.03x) | 389.56 (2.30x) | 1355.06 (7.99x) |
| complex deterministic binary encode | 95.85 | — | — | 171.30 (1.79x) | 1126.52 (11.75x) |
| complex JSON stringify | 269.73 | — | — | 4884.88 (18.11x) | 5848.55 (21.68x) |
| complex JSON parse | 2381.81 | — | — | 11886.10 (4.99x) | 7172.26 (3.01x) |
| complex TextFormat format | 257.09 | — | — | 3767.71 (14.66x) | 5079.64 (19.76x) |
| complex TextFormat parse | 1804.16 | — | — | 7014.32 (3.89x) | 8150.49 (4.52x) |
| packed int32 encode | 659.73 | 3184.07 (4.83x) | 2511.57 (3.81x) | 1232.93 (1.87x) | 2731.29 (4.14x) |
| packed int32 decode | 764.43 | 1908.22 (2.50x) | 3212.17 (4.20x) | 926.87 (1.21x) | 3311.85 (4.33x) |
| JSON stringify | 155.63 | — | — | 3013.76 (19.36x) | 2114.56 (13.59x) |
| JSON parse | 1534.16 | — | — | 7509.48 (4.89x) | 4317.97 (2.81x) |
| Any WKT JSON stringify | 131.81 | — | — | 1877.45 (14.24x) | 999.57 (7.58x) |
| Any WKT JSON parse | 520.18 | — | — | 2986.04 (5.74x) | 1502.06 (2.89x) |
| Any PlusDuration WKT JSON parse | 523.08 | — | — | 2989.56 (5.72x) | 1442.27 (2.76x) |
| Any ShortFractionDuration WKT JSON parse | 518.92 | — | — | 2937.20 (5.66x) | 1506.02 (2.90x) |
| Any MicroDuration WKT JSON stringify | 140.77 | — | — | 1906.60 (13.54x) | 949.33 (6.74x) |
| Any MicroDuration WKT JSON parse | 522.94 | — | — | 3024.86 (5.78x) | 1502.19 (2.87x) |
| Any NanoDuration WKT JSON stringify | 134.12 | — | — | 1933.96 (14.42x) | 959.61 (7.15x) |
| Any NanoDuration WKT JSON parse | 529.48 | — | — | 3006.17 (5.68x) | 1602.71 (3.03x) |
| Any NegativeDuration WKT JSON stringify | 135.53 | — | — | 1932.48 (14.26x) | 1038.44 (7.66x) |
| Any NegativeDuration WKT JSON parse | 527.45 | — | — | 3079.93 (5.84x) | 1593.34 (3.02x) |
| Any FractionalNegativeDuration WKT JSON stringify | 125.73 | — | — | 1882.79 (14.97x) | 992.83 (7.90x) |
| Any FractionalNegativeDuration WKT JSON parse | 542.91 | — | — | 3035.02 (5.59x) | 1412.74 (2.60x) |
| Any MaxDuration WKT JSON stringify | 114.46 | — | — | 1739.40 (15.20x) | 956.12 (8.35x) |
| Any MaxDuration WKT JSON parse | 534.80 | — | — | 2956.11 (5.53x) | 1613.42 (3.02x) |
| Any MinDuration WKT JSON stringify | 117.30 | — | — | 1755.16 (14.96x) | 1140.30 (9.72x) |
| Any MinDuration WKT JSON parse | 532.57 | — | — | 3011.26 (5.65x) | 1795.75 (3.37x) |
| Any ZeroDuration WKT JSON stringify | 108.98 | — | — | 908.58 (8.34x) | 935.83 (8.59x) |
| Any ZeroDuration WKT JSON parse | 470.08 | — | — | 2254.19 (4.80x) | 1326.03 (2.82x) |
| Any FieldMask WKT JSON stringify | 228.25 | — | — | 1741.05 (7.63x) | 1420.96 (6.23x) |
| Any FieldMask WKT JSON parse | 720.23 | — | — | 3142.09 (4.36x) | 2072.15 (2.88x) |
| Any EmptyFieldMask WKT JSON stringify | 112.32 | — | — | 912.15 (8.12x) | 785.64 (6.99x) |
| Any EmptyFieldMask WKT JSON parse | 445.48 | — | — | 2141.25 (4.81x) | 1247.26 (2.80x) |
| Any Timestamp WKT JSON stringify | 176.60 | — | — | 2021.50 (11.45x) | 1072.97 (6.08x) |
| Any Timestamp WKT JSON parse | 572.78 | — | — | 3024.70 (5.28x) | 1658.12 (2.89x) |
| Any Micro Timestamp WKT JSON stringify | 177.78 | — | — | 2026.99 (11.40x) | 1021.24 (5.74x) |
| Any Micro Timestamp WKT JSON parse | 583.98 | — | — | 3237.12 (5.54x) | 1497.19 (2.56x) |
| Any Nano Timestamp WKT JSON stringify | 179.03 | — | — | 2030.95 (11.34x) | 985.83 (5.51x) |
| Any Nano Timestamp WKT JSON parse | 588.97 | — | — | 3048.85 (5.18x) | 1575.93 (2.68x) |
| Any Offset Timestamp WKT JSON parse | 597.79 | — | — | 3066.43 (5.13x) | 1636.89 (2.74x) |
| Any PreEpoch Timestamp WKT JSON stringify | 142.31 | — | — | 1942.73 (13.65x) | 976.56 (6.86x) |
| Any PreEpoch Timestamp WKT JSON parse | 562.62 | — | — | 3041.96 (5.41x) | 1491.83 (2.65x) |
| Any Max Timestamp WKT JSON stringify | 162.93 | — | — | 2044.13 (12.55x) | 1046.97 (6.43x) |
| Any Max Timestamp WKT JSON parse | 591.27 | — | — | 3126.01 (5.29x) | 1529.40 (2.59x) |
| Any Min Timestamp WKT JSON stringify | 159.86 | — | — | 1942.12 (12.15x) | 1005.01 (6.29x) |
| Any Min Timestamp WKT JSON parse | 558.27 | — | — | 3033.87 (5.43x) | 1524.20 (2.73x) |
| Any Empty WKT JSON stringify | 97.99 | — | — | 907.70 (9.26x) | 694.64 (7.09x) |
| Any Empty WKT JSON parse | 341.93 | — | — | 2124.20 (6.21x) | 1244.62 (3.64x) |
| Any Struct WKT JSON stringify | 634.06 | — | — | 6469.31 (10.20x) | 6264.02 (9.88x) |
| Any Struct WKT JSON parse | 1848.18 | — | — | 11833.00 (6.40x) | 8545.53 (4.62x) |
| Any EmptyStruct WKT JSON stringify | 120.57 | — | — | 910.94 (7.56x) | 932.68 (7.74x) |
| Any EmptyStruct WKT JSON parse | 466.83 | — | — | 2244.77 (4.81x) | 1521.71 (3.26x) |
| Any Value WKT JSON stringify | 654.89 | — | — | 5909.20 (9.02x) | 6764.53 (10.33x) |
| Any Value WKT JSON parse | 1904.63 | — | — | 11377.40 (5.97x) | 9152.33 (4.81x) |
| Any NullValue WKT JSON stringify | 132.92 | — | — | 2278.09 (17.14x) | 874.78 (6.58x) |
| Any NullValue WKT JSON parse | 492.88 | — | — | 4046.40 (8.21x) | 1490.46 (3.02x) |
| Any StringScalarValue WKT JSON stringify | 147.92 | — | — | 2283.10 (15.43x) | 1080.34 (7.30x) |
| Any StringScalarValue WKT JSON parse | 550.94 | — | — | 3657.05 (6.64x) | 1758.53 (3.19x) |
| Any EmptyStringScalarValue WKT JSON stringify | 138.39 | — | — | 2288.24 (16.53x) | 1100.63 (7.95x) |
| Any EmptyStringScalarValue WKT JSON parse | 524.11 | — | — | 3626.90 (6.92x) | 1520.94 (2.90x) |
| Any NumberValue WKT JSON stringify | 182.51 | — | — | 2540.63 (13.92x) | 1093.71 (5.99x) |
| Any NumberValue WKT JSON parse | 533.67 | — | — | 3719.56 (6.97x) | 1627.24 (3.05x) |
| Any ZeroNumberValue WKT JSON stringify | 147.21 | — | — | 2489.69 (16.91x) | 1099.22 (7.47x) |
| Any ZeroNumberValue WKT JSON parse | 534.45 | — | — | 3652.95 (6.83x) | 1686.40 (3.16x) |
| Any BoolScalarValue WKT JSON stringify | 131.25 | — | — | 2267.80 (17.28x) | 1006.34 (7.67x) |
| Any BoolScalarValue WKT JSON parse | 490.01 | — | — | 3615.12 (7.38x) | 1712.17 (3.49x) |
| Any FalseBoolScalarValue WKT JSON stringify | 127.09 | — | — | 2269.98 (17.86x) | 960.77 (7.56x) |
| Any FalseBoolScalarValue WKT JSON parse | 490.45 | — | — | 3633.92 (7.41x) | 1586.51 (3.23x) |
| Any ListKindValue WKT JSON stringify | 508.58 | — | — | 5569.36 (10.95x) | 5317.76 (10.46x) |
| Any ListKindValue WKT JSON parse | 1454.02 | — | — | 9971.13 (6.86x) | 6683.92 (4.60x) |
| Any EmptyStructKindValue WKT JSON stringify | 146.17 | — | — | 2930.50 (20.05x) | 1323.55 (9.05x) |
| Any EmptyStructKindValue WKT JSON parse | 532.68 | — | — | 5591.44 (10.50x) | 1859.05 (3.49x) |
| Any EmptyListKindValue WKT JSON stringify | 144.80 | — | — | 2906.13 (20.07x) | 1197.83 (8.27x) |
| Any EmptyListKindValue WKT JSON parse | 534.07 | — | — | 4359.79 (8.16x) | 1699.30 (3.18x) |
| Any DoubleValue WKT JSON stringify | 191.59 | — | — | 1800.32 (9.40x) | 768.57 (4.01x) |
| Any DoubleValue WKT JSON parse | 553.95 | — | — | 2726.62 (4.92x) | 1467.71 (2.65x) |
| Any NegativeDoubleValue WKT JSON stringify | 191.60 | — | — | 1799.73 (9.39x) | 783.85 (4.09x) |
| Any NegativeDoubleValue WKT JSON parse | 556.47 | — | — | 2722.81 (4.89x) | 1535.54 (2.76x) |
| Any ZeroDoubleValue WKT JSON stringify | 167.09 | — | — | 929.15 (5.56x) | 735.15 (4.40x) |
| Any ZeroDoubleValue WKT JSON parse | 547.86 | — | — | 2167.54 (3.96x) | 1399.13 (2.55x) |
| Any DoubleValue NaN WKT JSON stringify | 155.14 | — | — | 1574.54 (10.15x) | 708.15 (4.56x) |
| Any DoubleValue NaN WKT JSON parse | 552.68 | — | — | 2643.29 (4.78x) | 1303.98 (2.36x) |
| Any DoubleValue Infinity WKT JSON stringify | 246.14 | — | — | 1562.11 (6.35x) | 724.41 (2.94x) |
| Any DoubleValue Infinity WKT JSON parse | 820.02 | — | — | 2684.42 (3.27x) | 1378.55 (1.68x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 192.50 | — | — | 1560.26 (8.11x) | 736.28 (3.82x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 700.47 | — | — | 2666.92 (3.81x) | 1374.35 (1.96x) |
| Any FloatValue WKT JSON stringify | 333.62 | — | — | 1739.05 (5.21x) | 859.37 (2.58x) |
| Any FloatValue WKT JSON parse | 553.33 | — | — | 2704.41 (4.89x) | 1312.82 (2.37x) |
| Any NegativeFloatValue WKT JSON stringify | 206.54 | — | — | 1761.15 (8.53x) | 775.68 (3.76x) |
| Any NegativeFloatValue WKT JSON parse | 556.28 | — | — | 2710.73 (4.87x) | 1306.19 (2.35x) |
| Any ZeroFloatValue WKT JSON stringify | 170.99 | — | — | 929.61 (5.44x) | 738.95 (4.32x) |
| Any ZeroFloatValue WKT JSON parse | 566.47 | — | — | 2143.20 (3.78x) | 1430.68 (2.53x) |
| Any FloatValue NaN WKT JSON stringify | 156.31 | — | — | 1568.56 (10.03x) | 721.51 (4.62x) |
| Any FloatValue NaN WKT JSON parse | 553.76 | — | — | 2621.59 (4.73x) | 1284.90 (2.32x) |
| Any FloatValue Infinity WKT JSON stringify | 168.14 | — | — | 1551.57 (9.23x) | 690.85 (4.11x) |
| Any FloatValue Infinity WKT JSON parse | 555.54 | — | — | 2667.04 (4.80x) | 1348.06 (2.43x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 167.12 | — | — | 1542.92 (9.23x) | 735.11 (4.40x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 560.32 | — | — | 2649.65 (4.73x) | 1261.95 (2.25x) |
| Any Int64Value WKT JSON stringify | 167.66 | — | — | 1557.71 (9.29x) | 924.53 (5.51x) |
| Any Int64Value WKT JSON parse | 582.49 | — | — | 2772.64 (4.76x) | 1569.51 (2.69x) |
| Any ZeroInt64Value WKT JSON stringify | 158.51 | — | — | 913.62 (5.76x) | 849.16 (5.36x) |
| Any ZeroInt64Value WKT JSON parse | 558.53 | — | — | 2142.33 (3.84x) | 1389.33 (2.49x) |
| Any NegativeInt64Value WKT JSON stringify | 171.22 | — | — | 1553.07 (9.07x) | 872.98 (5.10x) |
| Any NegativeInt64Value WKT JSON parse | 599.47 | — | — | 2800.18 (4.67x) | 1636.61 (2.73x) |
| Any MinInt64Value WKT JSON stringify | 168.55 | — | — | 1574.99 (9.34x) | 918.63 (5.45x) |
| Any MinInt64Value WKT JSON parse | 605.96 | — | — | 2819.84 (4.65x) | 1643.38 (2.71x) |
| Any MaxInt64Value WKT JSON stringify | 173.02 | — | — | 1564.57 (9.04x) | 901.47 (5.21x) |
| Any MaxInt64Value WKT JSON parse | 584.68 | — | — | 2809.22 (4.80x) | 1615.59 (2.76x) |
| Any UInt64Value WKT JSON stringify | 174.86 | — | — | 1560.22 (8.92x) | 935.41 (5.35x) |
| Any UInt64Value WKT JSON parse | 591.88 | — | — | 2788.44 (4.71x) | 1694.42 (2.86x) |
| Any ZeroUInt64Value WKT JSON stringify | 162.34 | — | — | 912.01 (5.62x) | 864.28 (5.32x) |
| Any ZeroUInt64Value WKT JSON parse | 568.81 | — | — | 2148.67 (3.78x) | 1407.90 (2.48x) |
| Any MaxUInt64Value WKT JSON stringify | 177.78 | — | — | 1555.10 (8.75x) | 851.97 (4.79x) |
| Any MaxUInt64Value WKT JSON parse | 600.65 | — | — | 2821.36 (4.70x) | 1804.13 (3.00x) |
| Any Int32Value WKT JSON stringify | 166.69 | — | — | 1548.57 (9.29x) | 720.91 (4.32x) |
| Any Int32Value WKT JSON parse | 568.41 | — | — | 2660.52 (4.68x) | 1442.76 (2.54x) |
| Any ZeroInt32Value WKT JSON stringify | 166.23 | — | — | 925.69 (5.57x) | 714.07 (4.30x) |
| Any ZeroInt32Value WKT JSON parse | 560.00 | — | — | 2146.03 (3.83x) | 1428.82 (2.55x) |
| Any NegativeInt32Value WKT JSON stringify | 173.22 | — | — | 1557.23 (8.99x) | 746.06 (4.31x) |
| Any NegativeInt32Value WKT JSON parse | 568.61 | — | — | 2694.26 (4.74x) | 1452.43 (2.55x) |
| Any MinInt32Value WKT JSON stringify | 171.23 | — | — | 1548.79 (9.05x) | 710.91 (4.15x) |
| Any MinInt32Value WKT JSON parse | 568.54 | — | — | 2700.90 (4.75x) | 1402.42 (2.47x) |
| Any MaxInt32Value WKT JSON stringify | 168.54 | — | — | 1549.53 (9.19x) | 732.66 (4.35x) |
| Any MaxInt32Value WKT JSON parse | 572.04 | — | — | 2672.45 (4.67x) | 1566.51 (2.74x) |
| Any UInt32Value WKT JSON stringify | 174.90 | — | — | 1556.76 (8.90x) | 779.62 (4.46x) |
| Any UInt32Value WKT JSON parse | 567.56 | — | — | 2683.20 (4.73x) | 1562.19 (2.75x) |
| Any ZeroUInt32Value WKT JSON stringify | 169.07 | — | — | 919.57 (5.44x) | 760.92 (4.50x) |
| Any ZeroUInt32Value WKT JSON parse | 567.22 | — | — | 2168.58 (3.82x) | 1593.24 (2.81x) |
| Any MaxUInt32Value WKT JSON stringify | 169.76 | — | — | 2195.73 (12.93x) | 775.89 (4.57x) |
| Any MaxUInt32Value WKT JSON parse | 577.10 | — | — | 3168.56 (5.49x) | 1618.11 (2.80x) |
| Any BoolValue WKT JSON stringify | 165.51 | — | — | 1994.88 (12.05x) | 739.65 (4.47x) |
| Any BoolValue WKT JSON parse | 519.09 | — | — | 2694.52 (5.19x) | 1329.04 (2.56x) |
| Any FalseBoolValue WKT JSON stringify | 175.99 | — | — | 909.65 (5.17x) | 717.99 (4.08x) |
| Any FalseBoolValue WKT JSON parse | 518.51 | — | — | 2134.15 (4.12x) | 1289.05 (2.49x) |
| Any StringValue WKT JSON stringify | 202.20 | — | — | 1559.53 (7.71x) | 791.32 (3.91x) |
| Any StringValue WKT JSON parse | 584.25 | — | — | 2672.31 (4.57x) | 1398.81 (2.39x) |
| Any EmptyStringValue WKT JSON stringify | 192.53 | — | — | 966.35 (5.02x) | 723.55 (3.76x) |
| Any EmptyStringValue WKT JSON parse | 550.86 | — | — | 2657.11 (4.82x) | 1263.04 (2.29x) |
| Any BytesValue WKT JSON stringify | 182.98 | — | — | 1578.89 (8.63x) | 815.54 (4.46x) |
| Any BytesValue WKT JSON parse | 596.36 | — | — | 2686.06 (4.50x) | 1398.37 (2.34x) |
| Any EmptyBytesValue WKT JSON stringify | 188.21 | — | — | 917.12 (4.87x) | 758.71 (4.03x) |
| Any EmptyBytesValue WKT JSON parse | 561.08 | — | — | 2160.55 (3.85x) | 1287.62 (2.29x) |
| Nested Any WKT JSON stringify | 303.78 | — | — | 2468.66 (8.13x) | 1390.92 (4.58x) |
| Nested Any WKT JSON parse | 902.28 | — | — | 4266.37 (4.73x) | 2698.93 (2.99x) |
| Duration JSON stringify | 60.51 | — | — | 956.55 (15.81x) | 335.43 (5.54x) |
| Duration JSON parse | 7.83 | — | — | 1443.85 (184.40x) | 390.23 (49.84x) |
| PlusDuration JSON parse | 8.81 | — | — | 1460.41 (165.77x) | 376.74 (42.76x) |
| ShortFractionDuration JSON parse | 6.62 | — | — | 1426.50 (215.48x) | 373.70 (56.45x) |
| MicroDuration JSON stringify | 61.24 | — | — | 961.95 (15.71x) | 384.68 (6.28x) |
| MicroDuration JSON parse | 10.05 | — | — | 1465.73 (145.84x) | 363.56 (36.18x) |
| NanoDuration JSON stringify | 59.17 | — | — | 1069.29 (18.07x) | 392.31 (6.63x) |
| NanoDuration JSON parse | 12.45 | — | — | 1477.22 (118.65x) | 364.29 (29.26x) |
| NegativeDuration JSON stringify | 62.47 | — | — | 998.59 (15.99x) | 392.37 (6.28x) |
| NegativeDuration JSON parse | 8.29 | — | — | 1506.91 (181.77x) | 368.81 (44.49x) |
| FractionalNegativeDuration JSON stringify | 61.22 | — | — | 966.80 (15.79x) | 377.52 (6.17x) |
| FractionalNegativeDuration JSON parse | 8.28 | — | — | 1458.94 (176.20x) | 340.03 (41.07x) |
| MaxDuration JSON stringify | 52.37 | — | — | 853.00 (16.29x) | 410.63 (7.84x) |
| MaxDuration JSON parse | 22.14 | — | — | 1442.54 (65.16x) | 388.36 (17.54x) |
| MinDuration JSON stringify | 52.13 | — | — | 872.84 (16.74x) | 405.13 (7.77x) |
| MinDuration JSON parse | 22.46 | — | — | 1465.61 (65.25x) | 396.49 (17.65x) |
| ZeroDuration JSON stringify | 46.89 | — | — | 807.62 (17.22x) | 352.75 (7.52x) |
| ZeroDuration JSON parse | 5.55 | — | — | 1362.74 (245.54x) | 298.96 (53.87x) |
| FieldMask JSON stringify | 135.58 | — | — | 879.90 (6.49x) | 691.17 (5.10x) |
| FieldMask JSON parse | 157.27 | — | — | 1648.88 (10.48x) | 850.32 (5.41x) |
| EmptyFieldMask JSON stringify | 40.86 | — | — | 608.38 (14.89x) | 204.64 (5.01x) |
| EmptyFieldMask JSON parse | 2.53 | — | — | 946.11 (373.95x) | 153.22 (60.56x) |
| Timestamp JSON stringify | 97.57 | — | — | 1818.75 (18.64x) | 418.12 (4.29x) |
| Timestamp JSON parse | 41.23 | — | — | 4314.56 (104.65x) | 413.71 (10.03x) |
| Micro Timestamp JSON stringify | 97.88 | — | — | 2265.45 (23.15x) | 420.18 (4.29x) |
| Micro Timestamp JSON parse | 43.52 | — | — | 2469.73 (56.75x) | 452.52 (10.40x) |
| Nano Timestamp JSON stringify | 96.55 | — | — | 1893.85 (19.62x) | 422.50 (4.38x) |
| Nano Timestamp JSON parse | 44.83 | — | — | 2441.64 (54.46x) | 448.89 (10.01x) |
| Offset Timestamp JSON parse | 49.05 | — | — | 2432.48 (49.59x) | 467.38 (9.53x) |
| PreEpoch Timestamp JSON stringify | 68.03 | — | — | 1650.00 (24.25x) | 417.62 (6.14x) |
| PreEpoch Timestamp JSON parse | 39.84 | — | — | 3107.24 (77.99x) | 417.34 (10.48x) |
| Max Timestamp JSON stringify | 79.99 | — | — | 1206.47 (15.08x) | 436.51 (5.46x) |
| Max Timestamp JSON parse | 47.12 | — | — | 1556.70 (33.04x) | 439.55 (9.33x) |
| Min Timestamp JSON stringify | 80.63 | — | — | 1050.24 (13.03x) | 396.54 (4.92x) |
| Min Timestamp JSON parse | 38.06 | — | — | 1448.16 (38.05x) | 383.27 (10.07x) |
| Empty JSON stringify | 21.07 | — | — | 494.99 (23.49x) | 76.53 (3.63x) |
| Empty JSON parse | 68.21 | — | — | 722.90 (10.60x) | 207.19 (3.04x) |
| Struct JSON stringify | 178.53 | — | — | 5719.40 (32.04x) | 3013.54 (16.88x) |
| Struct JSON parse | 856.68 | — | — | 18479.40 (21.57x) | 4942.38 (5.77x) |
| EmptyStruct JSON stringify | 43.21 | — | — | 1079.64 (24.99x) | 353.83 (8.19x) |
| EmptyStruct JSON parse | 89.75 | — | — | 3502.56 (39.03x) | 378.07 (4.21x) |
| Value JSON stringify | 179.09 | — | — | 10194.70 (56.93x) | 3331.83 (18.60x) |
| Value JSON parse | 869.47 | — | — | 18064.20 (20.78x) | 4955.60 (5.70x) |
| NullValue JSON stringify | 41.01 | — | — | 1748.94 (42.65x) | 216.85 (5.29x) |
| NullValue JSON parse | 64.90 | — | — | 3817.75 (58.83x) | 330.62 (5.09x) |
| StringScalarValue JSON stringify | 48.38 | — | — | 1916.42 (39.61x) | 271.34 (5.61x) |
| StringScalarValue JSON parse | 136.73 | — | — | 3148.41 (23.03x) | 410.19 (3.00x) |
| EmptyStringScalarValue JSON stringify | 46.97 | — | — | 1879.23 (40.01x) | 264.69 (5.64x) |
| EmptyStringScalarValue JSON parse | 82.71 | — | — | 2071.75 (25.05x) | 344.50 (4.17x) |
| NumberValue JSON stringify | 73.95 | — | — | 1570.73 (21.24x) | 335.23 (4.53x) |
| NumberValue JSON parse | 126.83 | — | — | 2181.58 (17.20x) | 390.33 (3.08x) |
| ZeroNumberValue JSON stringify | 51.28 | — | — | 1705.12 (33.25x) | 293.24 (5.72x) |
| ZeroNumberValue JSON parse | 125.68 | — | — | 2101.55 (16.72x) | 394.33 (3.14x) |
| BoolScalarValue JSON stringify | 41.04 | — | — | 1311.91 (31.97x) | 228.69 (5.57x) |
| BoolScalarValue JSON parse | 65.07 | — | — | 2018.17 (31.02x) | 327.24 (5.03x) |
| FalseBoolScalarValue JSON stringify | 40.99 | — | — | 1317.48 (32.14x) | 218.43 (5.33x) |
| FalseBoolScalarValue JSON parse | 65.57 | — | — | 2060.78 (31.43x) | 324.21 (4.94x) |
| ListKindValue JSON stringify | 155.52 | — | — | 6171.68 (39.68x) | 2280.08 (14.66x) |
| ListKindValue JSON parse | 668.03 | — | — | 10375.20 (15.53x) | 4143.62 (6.20x) |
| EmptyStructKindValue JSON stringify | 42.97 | — | — | 1928.83 (44.89x) | 492.05 (11.45x) |
| EmptyStructKindValue JSON parse | 105.30 | — | — | 3756.47 (35.67x) | 613.23 (5.82x) |
| EmptyListKindValue JSON stringify | 41.84 | — | — | 1933.93 (46.22x) | 344.56 (8.24x) |
| EmptyListKindValue JSON parse | 142.10 | — | — | 4055.72 (28.54x) | 581.41 (4.09x) |
| ListValue JSON stringify | 145.27 | — | — | 4787.39 (32.96x) | 2064.13 (14.21x) |
| ListValue JSON parse | 669.25 | — | — | 8505.98 (12.71x) | 3676.87 (5.49x) |
| EmptyListValue JSON stringify | 40.43 | — | — | 689.29 (17.05x) | 175.80 (4.35x) |
| EmptyListValue JSON parse | 128.43 | — | — | 2266.67 (17.65x) | 278.82 (2.17x) |
| DoubleValue JSON stringify | 68.24 | — | — | 859.82 (12.60x) | 187.88 (2.75x) |
| DoubleValue JSON parse | 112.53 | — | — | 1230.84 (10.94x) | 274.05 (2.44x) |
| NegativeDoubleValue JSON stringify | 67.69 | — | — | 867.16 (12.81x) | 208.76 (3.08x) |
| NegativeDoubleValue JSON parse | 113.02 | — | — | 1231.49 (10.90x) | 301.00 (2.66x) |
| ZeroDoubleValue JSON stringify | 47.88 | — | — | 805.60 (16.83x) | 132.74 (2.77x) |
| ZeroDoubleValue JSON parse | 109.40 | — | — | 1159.41 (10.60x) | 251.53 (2.30x) |
| DoubleValue NaN JSON stringify | 46.64 | — | — | 672.02 (14.41x) | 117.90 (2.53x) |
| DoubleValue NaN JSON parse | 105.74 | — | — | 1098.89 (10.39x) | 265.98 (2.52x) |
| DoubleValue Infinity JSON stringify | 48.16 | — | — | 666.82 (13.85x) | 114.48 (2.38x) |
| DoubleValue Infinity JSON parse | 106.72 | — | — | 1105.03 (10.35x) | 250.58 (2.35x) |
| DoubleValue NegativeInfinity JSON stringify | 48.39 | — | — | 664.48 (13.73x) | 120.41 (2.49x) |
| DoubleValue NegativeInfinity JSON parse | 109.12 | — | — | 1109.57 (10.17x) | 269.91 (2.47x) |
| FloatValue JSON stringify | 70.38 | — | — | 798.62 (11.35x) | 205.93 (2.93x) |
| FloatValue JSON parse | 112.85 | — | — | 1210.97 (10.73x) | 283.78 (2.51x) |
| NegativeFloatValue JSON stringify | 73.37 | — | — | 796.42 (10.85x) | 199.42 (2.72x) |
| NegativeFloatValue JSON parse | 113.72 | — | — | 1221.21 (10.74x) | 284.77 (2.50x) |
| ZeroFloatValue JSON stringify | 47.39 | — | — | 746.08 (15.74x) | 134.28 (2.83x) |
| ZeroFloatValue JSON parse | 109.84 | — | — | 1153.45 (10.50x) | 269.91 (2.46x) |
| FloatValue NaN JSON stringify | 46.40 | — | — | 639.17 (13.78x) | 135.22 (2.91x) |
| FloatValue NaN JSON parse | 106.06 | — | — | 1078.83 (10.17x) | 245.82 (2.32x) |
| FloatValue Infinity JSON stringify | 47.99 | — | — | 640.88 (13.35x) | 112.51 (2.34x) |
| FloatValue Infinity JSON parse | 106.74 | — | — | 1090.15 (10.21x) | 254.18 (2.38x) |
| FloatValue NegativeInfinity JSON stringify | 48.12 | — | — | 634.61 (13.19x) | 117.09 (2.43x) |
| FloatValue NegativeInfinity JSON parse | 109.57 | — | — | 1095.26 (10.00x) | 255.15 (2.33x) |
| Int64Value JSON stringify | 50.03 | — | — | 673.33 (13.46x) | 265.21 (5.30x) |
| Int64Value JSON parse | 127.16 | — | — | 1222.74 (9.62x) | 452.09 (3.56x) |
| ZeroInt64Value JSON stringify | 41.51 | — | — | 608.65 (14.66x) | 188.59 (4.54x) |
| ZeroInt64Value JSON parse | 106.47 | — | — | 1095.91 (10.29x) | 327.82 (3.08x) |
| NegativeInt64Value JSON stringify | 48.88 | — | — | 675.03 (13.81x) | 263.26 (5.39x) |
| NegativeInt64Value JSON parse | 128.88 | — | — | 1221.19 (9.48x) | 452.02 (3.51x) |
| MinInt64Value JSON stringify | 49.51 | — | — | 673.61 (13.61x) | 290.74 (5.87x) |
| MinInt64Value JSON parse | 134.37 | — | — | 1246.92 (9.28x) | 461.87 (3.44x) |
| MaxInt64Value JSON stringify | 49.85 | — | — | 676.93 (13.58x) | 286.91 (5.76x) |
| MaxInt64Value JSON parse | 134.52 | — | — | 1242.92 (9.24x) | 457.79 (3.40x) |
| UInt64Value JSON stringify | 50.23 | — | — | 675.05 (13.44x) | 260.79 (5.19x) |
| UInt64Value JSON parse | 125.21 | — | — | 1218.25 (9.73x) | 425.51 (3.40x) |
| ZeroUInt64Value JSON stringify | 41.93 | — | — | 608.86 (14.52x) | 184.50 (4.40x) |
| ZeroUInt64Value JSON parse | 104.99 | — | — | 1098.58 (10.46x) | 318.44 (3.03x) |
| MaxUInt64Value JSON stringify | 49.89 | — | — | 675.17 (13.53x) | 272.32 (5.46x) |
| MaxUInt64Value JSON parse | 135.47 | — | — | 1247.26 (9.21x) | 481.24 (3.55x) |
| Int32Value JSON stringify | 47.29 | — | — | 631.78 (13.36x) | 130.91 (2.77x) |
| Int32Value JSON parse | 129.74 | — | — | 1179.75 (9.09x) | 317.29 (2.45x) |
| ZeroInt32Value JSON stringify | 47.72 | — | — | 611.57 (12.82x) | 121.90 (2.55x) |
| ZeroInt32Value JSON parse | 124.66 | — | — | 1148.04 (9.21x) | 276.41 (2.22x) |
| NegativeInt32Value JSON stringify | 47.49 | — | — | 639.01 (13.46x) | 134.18 (2.83x) |
| NegativeInt32Value JSON parse | 128.99 | — | — | 1192.45 (9.24x) | 320.03 (2.48x) |
| MinInt32Value JSON stringify | 50.26 | — | — | 638.31 (12.70x) | 152.71 (3.04x) |
| MinInt32Value JSON parse | 136.94 | — | — | 1212.07 (8.85x) | 349.17 (2.55x) |
| MaxInt32Value JSON stringify | 50.11 | — | — | 631.64 (12.61x) | 156.01 (3.11x) |
| MaxInt32Value JSON parse | 137.04 | — | — | 1201.51 (8.77x) | 349.02 (2.55x) |
| UInt32Value JSON stringify | 47.59 | — | — | 645.54 (13.56x) | 136.16 (2.86x) |
| UInt32Value JSON parse | 129.93 | — | — | 1179.66 (9.08x) | 312.96 (2.41x) |
| ZeroUInt32Value JSON stringify | 47.35 | — | — | 627.33 (13.25x) | 132.18 (2.79x) |
| ZeroUInt32Value JSON parse | 125.47 | — | — | 1153.94 (9.20x) | 261.31 (2.08x) |
| MaxUInt32Value JSON stringify | 47.98 | — | — | 966.74 (20.15x) | 161.51 (3.37x) |
| MaxUInt32Value JSON parse | 137.26 | — | — | 1979.73 (14.42x) | 332.62 (2.42x) |
| BoolValue JSON stringify | 45.05 | — | — | 621.54 (13.80x) | 135.06 (3.00x) |
| BoolValue JSON parse | 59.40 | — | — | 1063.03 (17.90x) | 208.67 (3.51x) |
| FalseBoolValue JSON stringify | 44.91 | — | — | 600.27 (13.37x) | 126.97 (2.83x) |
| FalseBoolValue JSON parse | 59.90 | — | — | 1059.08 (17.68x) | 223.52 (3.73x) |
| StringValue JSON stringify | 52.78 | — | — | 677.71 (12.84x) | 174.14 (3.30x) |
| StringValue JSON parse | 137.00 | — | — | 1157.36 (8.45x) | 275.02 (2.01x) |
| EmptyStringValue JSON stringify | 48.72 | — | — | 643.48 (13.21x) | 188.30 (3.86x) |
| EmptyStringValue JSON parse | 81.73 | — | — | 1129.44 (13.82x) | 219.45 (2.69x) |
| BytesValue JSON stringify | 49.57 | — | — | 745.13 (15.03x) | 194.51 (3.92x) |
| BytesValue JSON parse | 148.43 | — | — | 1192.74 (8.04x) | 308.97 (2.08x) |
| EmptyBytesValue JSON stringify | 41.17 | — | — | 632.28 (15.36x) | 200.51 (4.87x) |
| EmptyBytesValue JSON parse | 90.10 | — | — | 1128.18 (12.52x) | 293.87 (3.26x) |
| TextFormat format | 184.34 | — | — | 2569.71 (13.94x) | 2274.36 (12.34x) |
| TextFormat parse | 701.28 | — | — | 4998.50 (7.13x) | 6217.36 (8.87x) |
| packed fixed32 encode | 2.01 | 552.72 (274.99x) | 581.53 (289.32x) | 43.57 (21.67x) | 403.53 (200.76x) |
| packed fixed32 decode | 4.53 | 1045.64 (230.83x) | 1963.10 (433.36x) | 50.01 (11.04x) | 1687.41 (372.50x) |
| packed fixed64 encode | 2.01 | 571.79 (284.47x) | 584.64 (290.87x) | 76.58 (38.10x) | 390.76 (194.41x) |
| packed fixed64 decode | 4.52 | 1039.35 (229.94x) | 7977.52 (1764.94x) | 81.15 (17.95x) | 2605.79 (576.50x) |
| packed sfixed32 encode | 2.01 | 550.21 (273.74x) | 540.14 (268.73x) | 44.27 (22.02x) | 412.50 (205.22x) |
| packed sfixed32 decode | 4.54 | 1046.35 (230.47x) | 1968.11 (433.50x) | 49.49 (10.90x) | 1723.54 (379.63x) |
| packed sfixed64 encode | 2.01 | 570.96 (284.06x) | 561.19 (279.20x) | 154.97 (77.10x) | 394.93 (196.48x) |
| packed sfixed64 decode | 4.52 | 1061.99 (234.95x) | 7918.87 (1751.96x) | 161.00 (35.62x) | 2400.06 (530.99x) |
| packed float encode | 2.26 | 807.93 (357.49x) | 564.18 (249.64x) | 46.33 (20.50x) | 359.12 (158.90x) |
| packed float decode | 7.11 | 1048.30 (147.44x) | 2080.08 (292.56x) | 50.30 (7.07x) | 1836.10 (258.24x) |
| packed double encode | 2.01 | 832.98 (414.42x) | 563.67 (280.43x) | 76.80 (38.21x) | 363.32 (180.76x) |
| packed double decode | 4.52 | 990.01 (219.03x) | 2051.32 (453.83x) | 80.44 (17.80x) | 2703.33 (598.08x) |
| packed uint64 encode | 1291.02 | 4655.79 (3.61x) | 4178.04 (3.24x) | 2147.17 (1.66x) | 3454.67 (2.68x) |
| packed uint64 decode | 1784.97 | 2901.88 (1.63x) | 8865.91 (4.97x) | 2868.31 (1.61x) | 8346.07 (4.68x) |
| packed uint32 encode | 1000.57 | 3616.78 (3.61x) | 3263.69 (3.26x) | 1729.15 (1.73x) | 2883.19 (2.88x) |
| packed uint32 decode | 1325.33 | 2430.20 (1.83x) | 3270.12 (2.47x) | 1988.37 (1.50x) | 5917.14 (4.46x) |
| packed int64 encode | 1414.79 | 10995.06 (7.77x) | 6085.69 (4.30x) | 2906.73 (2.05x) | 4160.15 (2.94x) |
| packed int64 decode | 2744.52 | 3376.23 (1.23x) | 10293.26 (3.75x) | 4845.48 (1.77x) | 10135.90 (3.69x) |
| packed sint32 encode | 778.58 | 3116.53 (4.00x) | 2874.69 (3.69x) | 1533.62 (1.97x) | 3426.74 (4.40x) |
| packed sint32 decode | 943.12 | 2560.75 (2.72x) | 3162.87 (3.35x) | 1126.94 (1.19x) | 4125.93 (4.37x) |
| packed sint64 encode | 1420.01 | 4943.03 (3.48x) | 4293.72 (3.02x) | 2415.00 (1.70x) | 4289.25 (3.02x) |
| packed sint64 decode | 2037.56 | 3066.44 (1.50x) | 9660.96 (4.74x) | 2932.53 (1.44x) | 9044.04 (4.44x) |
| packed bool encode | 2.01 | 1348.69 (670.99x) | 521.63 (259.52x) | 15.98 (7.95x) | 2464.51 (1226.12x) |
| packed bool decode | 264.83 | 1561.85 (5.90x) | 2559.97 (9.67x) | 807.74 (3.05x) | 1955.34 (7.38x) |
| packed enum encode | 274.18 | 2724.87 (9.94x) | 1801.82 (6.57x) | 1085.47 (3.96x) | 2696.87 (9.84x) |
| packed enum decode | 169.40 | 1536.72 (9.07x) | 2880.68 (17.01x) | 691.99 (4.08x) | 2181.38 (12.88x) |
| large map encode | 4225.37 | 17409.37 (4.12x) | 9706.90 (2.30x) | 22263.10 (5.27x) | 192308.17 (45.51x) |
| shuffled large map deterministic binary encode | 28642.63 | — | — | 94716.80 (3.31x) | 365055.70 (12.75x) |
| large map decode | 25631.53 | 92400.21 (3.60x) | 89398.18 (3.49x) | 89927.30 (3.51x) | 273353.29 (10.66x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded zero/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound `Duration`, non-empty and empty `Struct`, object/list/scalar `Value` (including default-like scalar and empty object/list kinds),
`FieldMask` (non-empty and empty), micro/nano/offset/min/pre/post/max-bound `Timestamp`, `Empty`, min/zero/positive/negative/max `Int64Value`, negative/zero/positive finite `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), negative/zero/positive finite `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), zero/normal/max `UInt64Value`, min/zero/positive/negative/max `Int32Value`, zero/normal/max `UInt32Value`, true/false `BoolValue`, non-empty/empty `StringValue`, base64/empty `BytesValue`, and recursive nested `Any` payloads), direct zero/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound Duration and micro/nano/offset/min/pre/post/max-bound Timestamp WKT JSON plus other direct WKT JSON, including empty `Struct` and empty `ListValue`, TextFormat, packed scalars, large bytes,
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
