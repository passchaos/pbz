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

Latest accepted comparison (`/tmp/pbz-compare-string-surrogate-json-final.log`,
summarized in `/tmp/pbz-summary-string-surrogate-json-final.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 20.55 | 101.49 (4.94x) | 52.68 (2.56x) | 128.42 (6.25x) | 834.95 (40.63x) |
| binary decode | 91.66 | 250.58 (2.73x) | 229.64 (2.51x) | 221.07 (2.41x) | 906.30 (9.89x) |
| unknown fields count by number | 3.60 | — | — | 161.60 (44.89x) | — |
| deterministic binary encode | 59.70 | — | — | 194.97 (3.27x) | 1147.37 (19.22x) |
| scalarmix encode | 20.05 | 103.65 (5.17x) | 47.34 (2.36x) | 29.32 (1.46x) | 213.66 (10.66x) |
| scalarmix decode | 35.63 | 132.65 (3.72x) | 176.52 (4.95x) | 84.49 (2.37x) | 313.26 (8.79x) |
| textbytes encode | 13.53 | 78.38 (5.79x) | 33.60 (2.48x) | 119.43 (8.83x) | 153.94 (11.38x) |
| textbytes decode | 48.54 | 381.23 (7.85x) | 240.74 (4.96x) | 167.05 (3.44x) | 676.41 (13.94x) |
| largebytes encode | 17.61 | 2708.25 (153.79x) | 2671.53 (151.71x) | 2823.76 (160.35x) | 2722.81 (154.62x) |
| largebytes decode | 92.51 | 5599.84 (60.53x) | 3087.21 (33.37x) | 2751.85 (29.75x) | 20980.53 (226.79x) |
| presencemix encode | 18.79 | 55.20 (2.94x) | 29.25 (1.56x) | 54.28 (2.89x) | 226.19 (12.04x) |
| presencemix decode | 56.10 | 135.58 (2.42x) | 108.09 (1.93x) | 162.26 (2.89x) | 488.90 (8.71x) |
| complex encode | 52.75 | 138.59 (2.63x) | 95.62 (1.81x) | 166.98 (3.17x) | 944.21 (17.90x) |
| complex decode | 170.24 | 388.01 (2.28x) | 338.00 (1.99x) | 392.25 (2.30x) | 1375.05 (8.08x) |
| complex deterministic binary encode | 104.88 | — | — | 173.00 (1.65x) | 1231.65 (11.74x) |
| complex JSON stringify | 274.49 | — | — | 4892.09 (17.82x) | 6580.90 (23.98x) |
| complex JSON parse | 2426.61 | — | — | 11934.20 (4.92x) | 7530.37 (3.10x) |
| complex TextFormat format | 269.91 | — | — | 3773.82 (13.98x) | 5775.89 (21.40x) |
| complex TextFormat parse | 1913.29 | — | — | 6994.01 (3.66x) | 8467.75 (4.43x) |
| packed int32 encode | 654.10 | 3150.82 (4.82x) | 2570.65 (3.93x) | 1225.97 (1.87x) | 2760.93 (4.22x) |
| packed int32 decode | 693.95 | 1890.15 (2.72x) | 3266.05 (4.71x) | 925.93 (1.33x) | 2592.18 (3.74x) |
| JSON stringify | 156.57 | — | — | 3003.12 (19.18x) | 2367.44 (15.12x) |
| JSON parse | 1507.60 | — | — | 7485.59 (4.97x) | 4626.88 (3.07x) |
| Any WKT JSON stringify | 273.42 | — | — | 1870.76 (6.84x) | 1276.64 (4.67x) |
| Any WKT JSON parse | 854.88 | — | — | 2971.04 (3.48x) | 1532.02 (1.79x) |
| Any Duration Escape WKT JSON parse | 892.63 | — | — | 2998.31 (3.36x) | 1627.22 (1.82x) |
| Any PlusDuration WKT JSON parse | 854.72 | — | — | 2992.95 (3.50x) | 1579.75 (1.85x) |
| Any ShortFractionDuration WKT JSON parse | 737.91 | — | — | 2948.59 (4.00x) | 1515.21 (2.05x) |
| Any MicroDuration WKT JSON stringify | 225.88 | — | — | 1886.73 (8.35x) | 983.63 (4.35x) |
| Any MicroDuration WKT JSON parse | 800.46 | — | — | 2983.53 (3.73x) | 1562.13 (1.95x) |
| Any NanoDuration WKT JSON stringify | 241.43 | — | — | 1908.92 (7.91x) | 1000.46 (4.14x) |
| Any NanoDuration WKT JSON parse | 703.26 | — | — | 3001.55 (4.27x) | 1571.20 (2.23x) |
| Any NegativeDuration WKT JSON stringify | 258.94 | — | — | 1926.05 (7.44x) | 1016.85 (3.93x) |
| Any NegativeDuration WKT JSON parse | 530.32 | — | — | 3090.16 (5.83x) | 1600.89 (3.02x) |
| Any FractionalNegativeDuration WKT JSON stringify | 129.76 | — | — | 1881.05 (14.50x) | 997.64 (7.69x) |
| Any FractionalNegativeDuration WKT JSON parse | 523.07 | — | — | 3033.99 (5.80x) | 1551.34 (2.97x) |
| Any MaxDuration WKT JSON stringify | 119.84 | — | — | 1739.30 (14.51x) | 1014.53 (8.47x) |
| Any MaxDuration WKT JSON parse | 538.49 | — | — | 2953.08 (5.48x) | 1547.33 (2.87x) |
| Any MinDuration WKT JSON stringify | 121.41 | — | — | 1749.27 (14.41x) | 1017.82 (8.38x) |
| Any MinDuration WKT JSON parse | 539.30 | — | — | 3014.40 (5.59x) | 1531.85 (2.84x) |
| Any ZeroDuration WKT JSON stringify | 105.28 | — | — | 914.85 (8.69x) | 965.40 (9.17x) |
| Any ZeroDuration WKT JSON parse | 470.39 | — | — | 2240.55 (4.76x) | 1478.12 (3.14x) |
| Any FieldMask WKT JSON stringify | 224.49 | — | — | 1740.33 (7.75x) | 1404.65 (6.26x) |
| Any FieldMask WKT JSON parse | 716.17 | — | — | 3162.07 (4.42x) | 2069.37 (2.89x) |
| Any FieldMask Escape WKT JSON parse | 730.17 | — | — | 3230.20 (4.42x) | 2238.15 (3.07x) |
| Any EmptyFieldMask WKT JSON stringify | 113.06 | — | — | 913.51 (8.08x) | 778.08 (6.88x) |
| Any EmptyFieldMask WKT JSON parse | 442.95 | — | — | 2152.58 (4.86x) | 1307.78 (2.95x) |
| Any Timestamp WKT JSON stringify | 181.53 | — | — | 2019.55 (11.13x) | 1014.64 (5.59x) |
| Any Timestamp WKT JSON parse | 577.76 | — | — | 3826.23 (6.62x) | 1603.27 (2.77x) |
| Any Timestamp Escape WKT JSON parse | 590.15 | — | — | 3069.23 (5.20x) | 1768.83 (3.00x) |
| Any ShortFraction Timestamp WKT JSON parse | 574.71 | — | — | 3118.74 (5.43x) | 1601.56 (2.79x) |
| Any Micro Timestamp WKT JSON stringify | 183.64 | — | — | 2071.24 (11.28x) | 1298.45 (7.07x) |
| Any Micro Timestamp WKT JSON parse | 584.84 | — | — | 3214.53 (5.50x) | 1643.62 (2.81x) |
| Any Nano Timestamp WKT JSON stringify | 185.47 | — | — | 2298.49 (12.39x) | 1018.85 (5.49x) |
| Any Nano Timestamp WKT JSON parse | 585.49 | — | — | 3060.16 (5.23x) | 1643.19 (2.81x) |
| Any Offset Timestamp WKT JSON parse | 595.65 | — | — | 3063.39 (5.14x) | 1668.62 (2.80x) |
| Any PreEpoch Timestamp WKT JSON stringify | 143.12 | — | — | 1947.94 (13.61x) | 987.64 (6.90x) |
| Any PreEpoch Timestamp WKT JSON parse | 565.88 | — | — | 3049.22 (5.39x) | 1571.37 (2.78x) |
| Any Max Timestamp WKT JSON stringify | 164.26 | — | — | 2053.84 (12.50x) | 1025.75 (6.24x) |
| Any Max Timestamp WKT JSON parse | 588.02 | — | — | 3196.72 (5.44x) | 1677.27 (2.85x) |
| Any Min Timestamp WKT JSON stringify | 160.55 | — | — | 1937.04 (12.07x) | 971.00 (6.05x) |
| Any Min Timestamp WKT JSON parse | 563.59 | — | — | 3024.66 (5.37x) | 1584.93 (2.81x) |
| Any Empty WKT JSON stringify | 90.78 | — | — | 908.88 (10.01x) | 700.81 (7.72x) |
| Any Empty WKT JSON parse | 334.46 | — | — | 2128.13 (6.36x) | 1348.78 (4.03x) |
| Any Struct WKT JSON stringify | 654.36 | — | — | 5804.13 (8.87x) | 6068.97 (9.27x) |
| Any Struct WKT JSON parse | 1736.98 | — | — | 11054.90 (6.36x) | 8842.71 (5.09x) |
| Any Struct Escape WKT JSON parse | 1777.13 | — | — | 11189.80 (6.30x) | 9006.46 (5.07x) |
| Any Struct NumberExponent WKT JSON parse | 1748.48 | — | — | 11116.60 (6.36x) | 9150.10 (5.23x) |
| Any EmptyStruct WKT JSON stringify | 121.50 | — | — | 908.90 (7.48x) | 1048.61 (8.63x) |
| Any EmptyStruct WKT JSON parse | 439.62 | — | — | 2225.24 (5.06x) | 1618.55 (3.68x) |
| Any Value WKT JSON stringify | 680.51 | — | — | 5876.53 (8.64x) | 6504.74 (9.56x) |
| Any Value WKT JSON parse | 1806.74 | — | — | 11266.40 (6.24x) | 9454.51 (5.23x) |
| Any Value Escape WKT JSON parse | 1819.32 | — | — | 11403.30 (6.27x) | 9489.72 (5.22x) |
| Any Value NumberExponent WKT JSON parse | 1801.11 | — | — | 11323.50 (6.29x) | 9172.05 (5.09x) |
| Any NullValue WKT JSON stringify | 131.45 | — | — | 2255.83 (17.16x) | 923.88 (7.03x) |
| Any NullValue WKT JSON parse | 463.93 | — | — | 4020.54 (8.67x) | 1577.40 (3.40x) |
| Any StringScalarValue WKT JSON stringify | 158.56 | — | — | 2274.33 (14.34x) | 1000.84 (6.31x) |
| Any StringScalarValue WKT JSON parse | 522.17 | — | — | 3619.46 (6.93x) | 1683.83 (3.22x) |
| Any StringScalarValue Escape WKT JSON parse | 534.02 | — | — | 3662.73 (6.86x) | 1784.99 (3.34x) |
| Any EmptyStringScalarValue WKT JSON stringify | 144.63 | — | — | 2279.25 (15.76x) | 989.66 (6.84x) |
| Any EmptyStringScalarValue WKT JSON parse | 490.93 | — | — | 3600.65 (7.33x) | 1580.46 (3.22x) |
| Any NumberValue WKT JSON stringify | 190.83 | — | — | 2521.55 (13.21x) | 1037.32 (5.44x) |
| Any NumberValue WKT JSON parse | 510.41 | — | — | 3672.65 (7.20x) | 1615.71 (3.17x) |
| Any NumberValue Exponent WKT JSON parse | 512.00 | — | — | 3682.46 (7.19x) | 1622.42 (3.17x) |
| Any NegativeNumberValue WKT JSON stringify | 186.28 | — | — | 2518.51 (13.52x) | 1035.84 (5.56x) |
| Any NegativeNumberValue WKT JSON parse | 511.64 | — | — | 3665.10 (7.16x) | 1626.08 (3.18x) |
| Any ZeroNumberValue WKT JSON stringify | 142.59 | — | — | 2476.47 (17.37x) | 915.72 (6.42x) |
| Any ZeroNumberValue WKT JSON parse | 506.55 | — | — | 3618.71 (7.14x) | 1620.09 (3.20x) |
| Any BoolScalarValue WKT JSON stringify | 135.72 | — | — | 2257.22 (16.63x) | 908.25 (6.69x) |
| Any BoolScalarValue WKT JSON parse | 468.19 | — | — | 3573.95 (7.63x) | 1524.01 (3.26x) |
| Any FalseBoolScalarValue WKT JSON stringify | 138.27 | — | — | 2258.00 (16.33x) | 912.29 (6.60x) |
| Any FalseBoolScalarValue WKT JSON parse | 468.50 | — | — | 3572.87 (7.63x) | 1528.47 (3.26x) |
| Any ListKindValue WKT JSON stringify | 504.38 | — | — | 5572.05 (11.05x) | 4687.47 (9.29x) |
| Any ListKindValue WKT JSON parse | 1385.27 | — | — | 9859.45 (7.12x) | 7080.64 (5.11x) |
| Any ListKindValue Escape WKT JSON parse | 1407.55 | — | — | 9966.14 (7.08x) | 7333.56 (5.21x) |
| Any EmptyStructKindValue WKT JSON stringify | 144.20 | — | — | 2915.18 (20.22x) | 1328.99 (9.22x) |
| Any EmptyStructKindValue WKT JSON parse | 504.24 | — | — | 5386.88 (10.68x) | 1954.59 (3.88x) |
| Any EmptyListKindValue WKT JSON stringify | 142.66 | — | — | 2900.48 (20.33x) | 1142.87 (8.01x) |
| Any EmptyListKindValue WKT JSON parse | 507.32 | — | — | 4369.29 (8.61x) | 1848.03 (3.64x) |
| Any DoubleValue WKT JSON stringify | 190.13 | — | — | 1786.90 (9.40x) | 807.46 (4.25x) |
| Any DoubleValue WKT JSON parse | 528.49 | — | — | 2719.40 (5.15x) | 1436.64 (2.72x) |
| Any DoubleValue String WKT JSON parse | 533.70 | — | — | 2719.58 (5.10x) | 1535.21 (2.88x) |
| Any DoubleValue Exponent WKT JSON parse | 532.08 | — | — | 2732.55 (5.14x) | 1472.88 (2.77x) |
| Any NegativeDoubleValue WKT JSON stringify | 185.66 | — | — | 1854.65 (9.99x) | 1015.49 (5.47x) |
| Any NegativeDoubleValue WKT JSON parse | 528.57 | — | — | 2768.75 (5.24x) | 1463.05 (2.77x) |
| Any ZeroDoubleValue WKT JSON stringify | 158.16 | — | — | 914.21 (5.78x) | 738.14 (4.67x) |
| Any ZeroDoubleValue WKT JSON parse | 524.01 | — | — | 2162.79 (4.13x) | 1392.83 (2.66x) |
| Any DoubleValue NaN WKT JSON stringify | 154.44 | — | — | 1569.28 (10.16x) | 729.40 (4.72x) |
| Any DoubleValue NaN WKT JSON parse | 516.42 | — | — | 2639.91 (5.11x) | 1443.58 (2.80x) |
| Any DoubleValue Infinity WKT JSON stringify | 159.78 | — | — | 1556.78 (9.74x) | 720.55 (4.51x) |
| Any DoubleValue Infinity WKT JSON parse | 521.09 | — | — | 2677.24 (5.14x) | 1426.60 (2.74x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 165.75 | — | — | 1560.93 (9.42x) | 717.41 (4.33x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 524.96 | — | — | 2667.96 (5.08x) | 1429.63 (2.72x) |
| Any FloatValue WKT JSON stringify | 194.19 | — | — | 1741.17 (8.97x) | 780.32 (4.02x) |
| Any FloatValue WKT JSON parse | 530.75 | — | — | 2711.89 (5.11x) | 1421.79 (2.68x) |
| Any FloatValue String WKT JSON parse | 536.82 | — | — | 2714.72 (5.06x) | 1508.15 (2.81x) |
| Any FloatValue Exponent WKT JSON parse | 539.12 | — | — | 2723.34 (5.05x) | 1415.88 (2.63x) |
| Any NegativeFloatValue WKT JSON stringify | 200.11 | — | — | 1735.64 (8.67x) | 782.88 (3.91x) |
| Any NegativeFloatValue WKT JSON parse | 531.88 | — | — | 2705.33 (5.09x) | 1419.79 (2.67x) |
| Any ZeroFloatValue WKT JSON stringify | 165.22 | — | — | 915.90 (5.54x) | 727.71 (4.40x) |
| Any ZeroFloatValue WKT JSON parse | 524.86 | — | — | 2145.44 (4.09x) | 1384.30 (2.64x) |
| Any FloatValue NaN WKT JSON stringify | 163.29 | — | — | 1568.53 (9.61x) | 712.71 (4.36x) |
| Any FloatValue NaN WKT JSON parse | 520.63 | — | — | 2620.79 (5.03x) | 1387.63 (2.67x) |
| Any FloatValue Infinity WKT JSON stringify | 174.74 | — | — | 1549.08 (8.87x) | 711.66 (4.07x) |
| Any FloatValue Infinity WKT JSON parse | 529.52 | — | — | 2664.61 (5.03x) | 1425.64 (2.69x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 167.77 | — | — | 1546.53 (9.22x) | 715.44 (4.26x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 529.35 | — | — | 2657.77 (5.02x) | 1414.83 (2.67x) |
| Any Int64Value WKT JSON stringify | 169.72 | — | — | 1556.61 (9.17x) | 900.69 (5.31x) |
| Any Int64Value WKT JSON parse | 553.57 | — | — | 2773.46 (5.01x) | 1642.01 (2.97x) |
| Any Int64Value Number WKT JSON parse | 553.88 | — | — | 2733.99 (4.94x) | 1532.35 (2.77x) |
| Any Int64Value Exponent WKT JSON parse | 543.11 | — | — | 2692.01 (4.96x) | 1518.01 (2.80x) |
| Any ZeroInt64Value WKT JSON stringify | 157.06 | — | — | 913.95 (5.82x) | 795.18 (5.06x) |
| Any ZeroInt64Value WKT JSON parse | 527.49 | — | — | 2148.55 (4.07x) | 1516.70 (2.88x) |
| Any NegativeInt64Value WKT JSON stringify | 171.20 | — | — | 1559.62 (9.11x) | 868.47 (5.07x) |
| Any NegativeInt64Value WKT JSON parse | 566.09 | — | — | 2801.46 (4.95x) | 1668.99 (2.95x) |
| Any MinInt64Value WKT JSON stringify | 171.44 | — | — | 3111.35 (18.15x) | 878.18 (5.12x) |
| Any MinInt64Value WKT JSON parse | 572.58 | — | — | 6941.91 (12.12x) | 2130.77 (3.72x) |
| Any MaxInt64Value WKT JSON stringify | 173.27 | — | — | 2843.39 (16.41x) | 861.98 (4.97x) |
| Any MaxInt64Value WKT JSON parse | 556.91 | — | — | 8032.38 (14.42x) | 1699.74 (3.05x) |
| Any UInt64Value WKT JSON stringify | 174.46 | — | — | 3841.06 (22.02x) | 858.64 (4.92x) |
| Any UInt64Value WKT JSON parse | 554.56 | — | — | 4791.83 (8.64x) | 1644.06 (2.96x) |
| Any UInt64Value Number WKT JSON parse | 555.08 | — | — | 9535.97 (17.18x) | 1565.70 (2.82x) |
| Any UInt64Value Exponent WKT JSON parse | 545.93 | — | — | 10107.20 (18.51x) | 1504.14 (2.76x) |
| Any ZeroUInt64Value WKT JSON stringify | 171.74 | — | — | 2192.54 (12.77x) | 798.58 (4.65x) |
| Any ZeroUInt64Value WKT JSON parse | 527.71 | — | — | 3830.20 (7.26x) | 1491.73 (2.83x) |
| Any MaxUInt64Value WKT JSON stringify | 177.05 | — | — | 3004.21 (16.97x) | 875.87 (4.95x) |
| Any MaxUInt64Value WKT JSON parse | 561.64 | — | — | 4569.55 (8.14x) | 1725.01 (3.07x) |
| Any Int32Value WKT JSON stringify | 172.86 | — | — | 1864.47 (10.79x) | 730.88 (4.23x) |
| Any Int32Value WKT JSON parse | 537.86 | — | — | 3037.60 (5.65x) | 1459.32 (2.71x) |
| Any Int32Value String WKT JSON parse | 548.37 | — | — | 2741.73 (5.00x) | 1566.55 (2.86x) |
| Any Int32Value Exponent WKT JSON parse | 545.75 | — | — | 2720.65 (4.99x) | 1498.19 (2.75x) |
| Any ZeroInt32Value WKT JSON stringify | 171.20 | — | — | 1195.11 (6.98x) | 720.71 (4.21x) |
| Any ZeroInt32Value WKT JSON parse | 532.20 | — | — | 2228.29 (4.19x) | 1399.38 (2.63x) |
| Any NegativeInt32Value WKT JSON stringify | 170.34 | — | — | 2099.13 (12.32x) | 747.49 (4.39x) |
| Any NegativeInt32Value WKT JSON parse | 544.54 | — | — | 3707.67 (6.81x) | 1455.78 (2.67x) |
| Any MinInt32Value WKT JSON stringify | 171.48 | — | — | 2084.13 (12.15x) | 1157.59 (6.75x) |
| Any MinInt32Value WKT JSON parse | 550.45 | — | — | 3637.31 (6.61x) | 2605.23 (4.73x) |
| Any MaxInt32Value WKT JSON stringify | 174.25 | — | — | 1555.09 (8.92x) | 1234.49 (7.08x) |
| Any MaxInt32Value WKT JSON parse | 548.14 | — | — | 2673.39 (4.88x) | 2534.11 (4.62x) |
| Any UInt32Value WKT JSON stringify | 178.47 | — | — | 1549.71 (8.68x) | 1303.08 (7.30x) |
| Any UInt32Value WKT JSON parse | 543.32 | — | — | 2669.66 (4.91x) | 1489.71 (2.74x) |
| Any UInt32Value String WKT JSON parse | 550.80 | — | — | 2658.78 (4.83x) | 1555.66 (2.82x) |
| Any UInt32Value Exponent WKT JSON parse | 549.91 | — | — | 2699.85 (4.91x) | 1497.02 (2.72x) |
| Any ZeroUInt32Value WKT JSON stringify | 171.86 | — | — | 915.90 (5.33x) | 709.00 (4.13x) |
| Any ZeroUInt32Value WKT JSON parse | 537.94 | — | — | 2151.98 (4.00x) | 1406.33 (2.61x) |
| Any MaxUInt32Value WKT JSON stringify | 180.00 | — | — | 1552.54 (8.63x) | 736.48 (4.09x) |
| Any MaxUInt32Value WKT JSON parse | 552.30 | — | — | 2677.27 (4.85x) | 1466.35 (2.65x) |
| Any BoolValue WKT JSON stringify | 176.11 | — | — | 1520.94 (8.64x) | 720.84 (4.09x) |
| Any BoolValue WKT JSON parse | 485.33 | — | — | 2600.40 (5.36x) | 1310.60 (2.70x) |
| Any FalseBoolValue WKT JSON stringify | 174.02 | — | — | 912.64 (5.24x) | 703.69 (4.04x) |
| Any FalseBoolValue WKT JSON parse | 487.22 | — | — | 2146.50 (4.41x) | 1352.07 (2.78x) |
| Any StringValue WKT JSON stringify | 200.02 | — | — | 1564.99 (7.82x) | 806.17 (4.03x) |
| Any StringValue WKT JSON parse | 548.94 | — | — | 2673.09 (4.87x) | 1453.87 (2.65x) |
| Any StringValue Escape WKT JSON parse | 554.90 | — | — | 2684.62 (4.84x) | 1551.08 (2.80x) |
| Any StringValue Surrogate WKT JSON parse | 559.80 | — | — | 2675.45 (4.78x) | 1561.96 (2.79x) |
| Any EmptyStringValue WKT JSON stringify | 188.70 | — | — | 914.33 (4.85x) | 764.18 (4.05x) |
| Any EmptyStringValue WKT JSON parse | 515.79 | — | — | 2149.52 (4.17x) | 1427.11 (2.77x) |
| Any BytesValue WKT JSON stringify | 189.27 | — | — | 1583.10 (8.36x) | 839.51 (4.44x) |
| Any BytesValue WKT JSON parse | 563.37 | — | — | 2687.09 (4.77x) | 1475.86 (2.62x) |
| Any BytesValue URL WKT JSON parse | 580.79 | — | — | 2675.23 (4.61x) | 2219.16 (3.82x) |
| Any BytesValue StandardBase64 WKT JSON parse | 565.07 | — | — | 2697.79 (4.77x) | 2175.27 (3.85x) |
| Any BytesValue Unpadded WKT JSON parse | 566.42 | — | — | 2674.59 (4.72x) | 1569.54 (2.77x) |
| Any EmptyBytesValue WKT JSON stringify | 183.22 | — | — | 914.03 (4.99x) | 766.02 (4.18x) |
| Any EmptyBytesValue WKT JSON parse | 524.38 | — | — | 2140.93 (4.08x) | 1475.11 (2.81x) |
| Nested Any WKT JSON stringify | 318.44 | — | — | 2480.30 (7.79x) | 1449.31 (4.55x) |
| Nested Any WKT JSON parse | 865.90 | — | — | 4267.86 (4.93x) | 2870.33 (3.31x) |
| Duration JSON stringify | 57.57 | — | — | 954.23 (16.58x) | 470.55 (8.17x) |
| Duration JSON parse | 17.78 | — | — | 1445.41 (81.29x) | 405.64 (22.81x) |
| Duration Escape JSON parse | 39.65 | — | — | 1481.35 (37.36x) | 433.21 (10.93x) |
| PlusDuration JSON parse | 18.24 | — | — | 1459.57 (80.02x) | 389.35 (21.35x) |
| ShortFractionDuration JSON parse | 16.05 | — | — | 1441.03 (89.78x) | 399.67 (24.90x) |
| MicroDuration JSON stringify | 59.02 | — | — | 976.25 (16.54x) | 407.54 (6.91x) |
| MicroDuration JSON parse | 19.21 | — | — | 1482.58 (77.18x) | 393.47 (20.48x) |
| NanoDuration JSON stringify | 56.65 | — | — | 1000.51 (17.66x) | 409.16 (7.22x) |
| NanoDuration JSON parse | 24.60 | — | — | 1487.82 (60.48x) | 401.29 (16.31x) |
| NegativeDuration JSON stringify | 57.91 | — | — | 1013.56 (17.50x) | 431.47 (7.45x) |
| NegativeDuration JSON parse | 17.57 | — | — | 1518.27 (86.41x) | 393.47 (22.39x) |
| FractionalNegativeDuration JSON stringify | 57.96 | — | — | 973.91 (16.80x) | 429.35 (7.41x) |
| FractionalNegativeDuration JSON parse | 17.72 | — | — | 1463.55 (82.59x) | 383.39 (21.64x) |
| MaxDuration JSON stringify | 50.02 | — | — | 865.32 (17.30x) | 420.32 (8.40x) |
| MaxDuration JSON parse | 30.13 | — | — | 1437.29 (47.70x) | 402.65 (13.36x) |
| MinDuration JSON stringify | 49.58 | — | — | 878.53 (17.72x) | 443.74 (8.95x) |
| MinDuration JSON parse | 31.84 | — | — | 1459.47 (45.84x) | 407.01 (12.78x) |
| ZeroDuration JSON stringify | 44.36 | — | — | 828.49 (18.68x) | 376.06 (8.48x) |
| ZeroDuration JSON parse | 14.80 | — | — | 1373.46 (92.80x) | 311.66 (21.06x) |
| FieldMask JSON stringify | 135.10 | — | — | 884.95 (6.55x) | 654.29 (4.84x) |
| FieldMask JSON parse | 140.05 | — | — | 1670.92 (11.93x) | 873.30 (6.24x) |
| FieldMask Escape JSON parse | 191.23 | — | — | 1719.29 (8.99x) | 1142.62 (5.98x) |
| EmptyFieldMask JSON stringify | 40.88 | — | — | 614.85 (15.04x) | 193.27 (4.73x) |
| EmptyFieldMask JSON parse | 4.54 | — | — | 948.17 (208.85x) | 172.69 (38.04x) |
| Timestamp JSON stringify | 95.57 | — | — | 1152.84 (12.06x) | 417.52 (4.37x) |
| Timestamp JSON parse | 45.09 | — | — | 1506.04 (33.40x) | 444.55 (9.86x) |
| Timestamp Escape JSON parse | 94.98 | — | — | 1525.29 (16.06x) | 509.40 (5.36x) |
| ShortFraction Timestamp JSON parse | 43.41 | — | — | 1515.73 (34.92x) | 439.92 (10.13x) |
| Micro Timestamp JSON stringify | 96.55 | — | — | 1151.79 (11.93x) | 420.16 (4.35x) |
| Micro Timestamp JSON parse | 48.32 | — | — | 1515.78 (31.37x) | 460.91 (9.54x) |
| Nano Timestamp JSON stringify | 94.16 | — | — | 1197.41 (12.72x) | 453.82 (4.82x) |
| Nano Timestamp JSON parse | 50.02 | — | — | 1531.19 (30.61x) | 463.09 (9.26x) |
| Offset Timestamp JSON parse | 51.09 | — | — | 1540.00 (30.14x) | 486.73 (9.53x) |
| PreEpoch Timestamp JSON stringify | 66.53 | — | — | 1067.43 (16.04x) | 402.58 (6.05x) |
| PreEpoch Timestamp JSON parse | 42.98 | — | — | 1489.23 (34.65x) | 417.45 (9.71x) |
| Max Timestamp JSON stringify | 78.75 | — | — | 1209.87 (15.36x) | 422.54 (5.37x) |
| Max Timestamp JSON parse | 50.95 | — | — | 1552.75 (30.48x) | 780.80 (15.32x) |
| Min Timestamp JSON stringify | 80.30 | — | — | 1062.12 (13.23x) | 400.07 (4.98x) |
| Min Timestamp JSON parse | 40.98 | — | — | 1471.55 (35.91x) | 425.38 (10.38x) |
| Empty JSON stringify | 20.92 | — | — | 504.39 (24.11x) | 84.00 (4.02x) |
| Empty JSON parse | 67.21 | — | — | 719.75 (10.71x) | 203.34 (3.03x) |
| Struct JSON stringify | 175.67 | — | — | 5727.66 (32.60x) | 3052.15 (17.37x) |
| Struct JSON parse | 851.83 | — | — | 10934.20 (12.84x) | 4668.64 (5.48x) |
| Struct Escape JSON parse | 895.60 | — | — | 10957.60 (12.23x) | 4774.39 (5.33x) |
| Struct NumberExponent JSON parse | 850.46 | — | — | 10879.80 (12.79x) | 4669.58 (5.49x) |
| EmptyStruct JSON stringify | 40.47 | — | — | 702.28 (17.35x) | 426.54 (10.54x) |
| EmptyStruct JSON parse | 87.44 | — | — | 2046.13 (23.40x) | 380.23 (4.35x) |
| Value JSON stringify | 176.93 | — | — | 6595.03 (37.27x) | 3213.63 (18.16x) |
| Value JSON parse | 898.66 | — | — | 12155.50 (13.53x) | 4908.10 (5.46x) |
| Value Escape JSON parse | 945.21 | — | — | 12241.30 (12.95x) | 5084.24 (5.38x) |
| Value NumberExponent JSON parse | 901.57 | — | — | 12152.60 (13.48x) | 4919.08 (5.46x) |
| NullValue JSON stringify | 40.14 | — | — | 1321.58 (32.92x) | 401.35 (10.00x) |
| NullValue JSON parse | 75.94 | — | — | 2445.48 (32.20x) | 367.09 (4.83x) |
| StringScalarValue JSON stringify | 47.98 | — | — | 1343.90 (28.01x) | 277.68 (5.79x) |
| StringScalarValue JSON parse | 145.27 | — | — | 2069.80 (14.25x) | 441.73 (3.04x) |
| StringScalarValue Escape JSON parse | 155.72 | — | — | 2109.75 (13.55x) | 492.71 (3.16x) |
| EmptyStringScalarValue JSON stringify | 47.43 | — | — | 1334.90 (28.14x) | 274.31 (5.78x) |
| EmptyStringScalarValue JSON parse | 92.55 | — | — | 2051.47 (22.17x) | 358.06 (3.87x) |
| NumberValue JSON stringify | 74.46 | — | — | 1552.62 (20.85x) | 325.19 (4.37x) |
| NumberValue JSON parse | 137.95 | — | — | 2157.47 (15.64x) | 407.38 (2.95x) |
| NumberValue Exponent JSON parse | 140.94 | — | — | 2172.20 (15.41x) | 420.52 (2.98x) |
| NegativeNumberValue JSON stringify | 74.75 | — | — | 1550.70 (20.75x) | 332.81 (4.45x) |
| NegativeNumberValue JSON parse | 138.71 | — | — | 2160.76 (15.58x) | 412.83 (2.98x) |
| ZeroNumberValue JSON stringify | 51.10 | — | — | 1503.31 (29.42x) | 281.46 (5.51x) |
| ZeroNumberValue JSON parse | 135.31 | — | — | 2096.39 (15.49x) | 374.10 (2.76x) |
| BoolScalarValue JSON stringify | 40.44 | — | — | 1312.90 (32.47x) | 213.54 (5.28x) |
| BoolScalarValue JSON parse | 75.42 | — | — | 1998.96 (26.50x) | 339.93 (4.51x) |
| FalseBoolScalarValue JSON stringify | 40.34 | — | — | 1310.25 (32.48x) | 224.27 (5.56x) |
| FalseBoolScalarValue JSON parse | 75.93 | — | — | 2009.19 (26.46x) | 325.66 (4.29x) |
| ListKindValue JSON stringify | 140.17 | — | — | 6130.31 (43.73x) | 2262.36 (16.14x) |
| ListKindValue JSON parse | 696.37 | — | — | 10383.50 (14.91x) | 4051.99 (5.82x) |
| ListKindValue Escape JSON parse | 717.81 | — | — | 10467.00 (14.58x) | 4267.20 (5.94x) |
| EmptyStructKindValue JSON stringify | 42.35 | — | — | 1929.73 (45.57x) | 525.00 (12.40x) |
| EmptyStructKindValue JSON parse | 115.53 | — | — | 3749.07 (32.45x) | 658.91 (5.70x) |
| EmptyListKindValue JSON stringify | 41.01 | — | — | 1930.75 (47.08x) | 361.61 (8.82x) |
| EmptyListKindValue JSON parse | 153.40 | — | — | 4034.48 (26.30x) | 595.21 (3.88x) |
| ListValue JSON stringify | 145.10 | — | — | 4732.48 (32.62x) | 2098.58 (14.46x) |
| ListValue JSON parse | 648.53 | — | — | 8528.83 (13.15x) | 3814.72 (5.88x) |
| ListValue Escape JSON parse | 673.62 | — | — | 8610.58 (12.78x) | 4028.90 (5.98x) |
| EmptyListValue JSON stringify | 40.05 | — | — | 684.82 (17.10x) | 188.58 (4.71x) |
| EmptyListValue JSON parse | 125.13 | — | — | 2263.11 (18.09x) | 334.85 (2.68x) |
| DoubleValue JSON stringify | 68.81 | — | — | 872.11 (12.67x) | 197.62 (2.87x) |
| DoubleValue JSON parse | 111.70 | — | — | 1231.67 (11.03x) | 296.58 (2.66x) |
| DoubleValue String JSON parse | 113.05 | — | — | 1173.33 (10.38x) | 381.92 (3.38x) |
| DoubleValue Exponent JSON parse | 113.19 | — | — | 1240.78 (10.96x) | 298.49 (2.64x) |
| NegativeDoubleValue JSON stringify | 68.17 | — | — | 873.82 (12.82x) | 192.24 (2.82x) |
| NegativeDoubleValue JSON parse | 110.93 | — | — | 1226.85 (11.06x) | 280.96 (2.53x) |
| ZeroDoubleValue JSON stringify | 48.66 | — | — | 810.57 (16.66x) | 143.16 (2.94x) |
| ZeroDoubleValue JSON parse | 108.78 | — | — | 1158.54 (10.65x) | 276.87 (2.55x) |
| DoubleValue NaN JSON stringify | 46.40 | — | — | 667.90 (14.39x) | 120.34 (2.59x) |
| DoubleValue NaN JSON parse | 105.21 | — | — | 1094.26 (10.40x) | 277.75 (2.64x) |
| DoubleValue Infinity JSON stringify | 47.65 | — | — | 672.62 (14.12x) | 121.06 (2.54x) |
| DoubleValue Infinity JSON parse | 106.44 | — | — | 1099.46 (10.33x) | 291.32 (2.74x) |
| DoubleValue NegativeInfinity JSON stringify | 47.62 | — | — | 667.99 (14.03x) | 142.06 (2.98x) |
| DoubleValue NegativeInfinity JSON parse | 108.52 | — | — | 1115.32 (10.28x) | 282.30 (2.60x) |
| FloatValue JSON stringify | 72.04 | — | — | 814.36 (11.30x) | 184.46 (2.56x) |
| FloatValue JSON parse | 111.58 | — | — | 1222.20 (10.95x) | 289.77 (2.60x) |
| FloatValue String JSON parse | 110.76 | — | — | 1165.99 (10.53x) | 365.34 (3.30x) |
| FloatValue Exponent JSON parse | 113.37 | — | — | 1232.86 (10.87x) | 299.81 (2.64x) |
| NegativeFloatValue JSON stringify | 71.40 | — | — | 817.36 (11.45x) | 260.84 (3.65x) |
| NegativeFloatValue JSON parse | 112.27 | — | — | 1224.36 (10.91x) | 506.26 (4.51x) |
| ZeroFloatValue JSON stringify | 48.65 | — | — | 769.29 (15.81x) | 142.09 (2.92x) |
| ZeroFloatValue JSON parse | 108.18 | — | — | 1164.47 (10.76x) | 269.35 (2.49x) |
| FloatValue NaN JSON stringify | 45.90 | — | — | 654.59 (14.26x) | 120.70 (2.63x) |
| FloatValue NaN JSON parse | 104.26 | — | — | 1079.42 (10.35x) | 270.39 (2.59x) |
| FloatValue Infinity JSON stringify | 47.37 | — | — | 650.02 (13.72x) | 125.46 (2.65x) |
| FloatValue Infinity JSON parse | 106.15 | — | — | 1091.01 (10.28x) | 261.78 (2.47x) |
| FloatValue NegativeInfinity JSON stringify | 48.03 | — | — | 651.86 (13.57x) | 122.02 (2.54x) |
| FloatValue NegativeInfinity JSON parse | 107.85 | — | — | 1103.25 (10.23x) | 275.75 (2.56x) |
| Int64Value JSON stringify | 50.00 | — | — | 678.58 (13.57x) | 278.98 (5.58x) |
| Int64Value JSON parse | 124.51 | — | — | 1233.28 (9.91x) | 468.61 (3.76x) |
| Int64Value Number JSON parse | 134.27 | — | — | 1286.43 (9.58x) | 365.60 (2.72x) |
| Int64Value Exponent JSON parse | 122.87 | — | — | 1225.68 (9.98x) | 361.11 (2.94x) |
| ZeroInt64Value JSON stringify | 41.67 | — | — | 611.65 (14.68x) | 192.15 (4.61x) |
| ZeroInt64Value JSON parse | 105.32 | — | — | 1094.95 (10.40x) | 345.59 (3.28x) |
| NegativeInt64Value JSON stringify | 48.49 | — | — | 673.39 (13.89x) | 283.25 (5.84x) |
| NegativeInt64Value JSON parse | 126.19 | — | — | 1213.77 (9.62x) | 492.34 (3.90x) |
| MinInt64Value JSON stringify | 50.41 | — | — | 680.81 (13.51x) | 288.68 (5.73x) |
| MinInt64Value JSON parse | 133.71 | — | — | 2120.94 (15.86x) | 492.92 (3.69x) |
| MaxInt64Value JSON stringify | 49.67 | — | — | 1647.80 (33.17x) | 287.82 (5.79x) |
| MaxInt64Value JSON parse | 132.81 | — | — | 2377.18 (17.90x) | 475.39 (3.58x) |
| UInt64Value JSON stringify | 50.27 | — | — | 1297.25 (25.81x) | 289.69 (5.76x) |
| UInt64Value JSON parse | 125.76 | — | — | 2382.93 (18.95x) | 461.26 (3.67x) |
| UInt64Value Number JSON parse | 128.57 | — | — | 2436.43 (18.95x) | 349.15 (2.72x) |
| UInt64Value Exponent JSON parse | 155.97 | — | — | 2127.57 (13.64x) | 355.17 (2.28x) |
| ZeroUInt64Value JSON stringify | 56.32 | — | — | 1216.71 (21.60x) | 189.52 (3.37x) |
| ZeroUInt64Value JSON parse | 128.58 | — | — | 2462.46 (19.15x) | 342.38 (2.66x) |
| MaxUInt64Value JSON stringify | 69.05 | — | — | 684.94 (9.92x) | 292.58 (4.24x) |
| MaxUInt64Value JSON parse | 200.21 | — | — | 1268.20 (6.33x) | 474.44 (2.37x) |
| Int32Value JSON stringify | 63.42 | — | — | 1130.29 (17.82x) | 132.93 (2.10x) |
| Int32Value JSON parse | 164.98 | — | — | 1729.00 (10.48x) | 327.36 (1.98x) |
| Int32Value String JSON parse | 169.02 | — | — | 1667.87 (9.87x) | 631.24 (3.73x) |
| Int32Value Exponent JSON parse | 175.09 | — | — | 1787.05 (10.21x) | 373.66 (2.13x) |
| ZeroInt32Value JSON stringify | 62.92 | — | — | 633.04 (10.06x) | 127.92 (2.03x) |
| ZeroInt32Value JSON parse | 153.53 | — | — | 1173.47 (7.64x) | 275.63 (1.80x) |
| NegativeInt32Value JSON stringify | 63.74 | — | — | 903.51 (14.17x) | 242.76 (3.81x) |
| NegativeInt32Value JSON parse | 163.35 | — | — | 1642.34 (10.05x) | 648.16 (3.97x) |
| MinInt32Value JSON stringify | 64.99 | — | — | 884.90 (13.62x) | 139.50 (2.15x) |
| MinInt32Value JSON parse | 184.46 | — | — | 1617.53 (8.77x) | 341.51 (1.85x) |
| MaxInt32Value JSON stringify | 64.80 | — | — | 655.27 (10.11x) | 258.65 (3.99x) |
| MaxInt32Value JSON parse | 186.23 | — | — | 1206.49 (6.48x) | 539.43 (2.90x) |
| UInt32Value JSON stringify | 63.75 | — | — | 643.50 (10.09x) | 237.99 (3.73x) |
| UInt32Value JSON parse | 165.91 | — | — | 1181.67 (7.12x) | 574.24 (3.46x) |
| UInt32Value String JSON parse | 168.46 | — | — | 1124.61 (6.68x) | 694.86 (4.12x) |
| UInt32Value Exponent JSON parse | 176.19 | — | — | 1219.14 (6.92x) | 643.10 (3.65x) |
| ZeroUInt32Value JSON stringify | 62.69 | — | — | 633.54 (10.11x) | 135.59 (2.16x) |
| ZeroUInt32Value JSON parse | 153.29 | — | — | 1153.96 (7.53x) | 267.28 (1.74x) |
| MaxUInt32Value JSON stringify | 64.67 | — | — | 645.66 (9.98x) | 150.16 (2.32x) |
| MaxUInt32Value JSON parse | 187.90 | — | — | 1209.93 (6.44x) | 358.45 (1.91x) |
| BoolValue JSON stringify | 58.99 | — | — | 613.35 (10.40x) | 121.55 (2.06x) |
| BoolValue JSON parse | 79.27 | — | — | 1055.13 (13.31x) | 228.37 (2.88x) |
| FalseBoolValue JSON stringify | 58.92 | — | — | 836.75 (14.20x) | 121.21 (2.06x) |
| FalseBoolValue JSON parse | 80.45 | — | — | 1058.95 (13.16x) | 207.39 (2.58x) |
| StringValue JSON stringify | 75.34 | — | — | 672.08 (8.92x) | 183.70 (2.44x) |
| StringValue JSON parse | 156.78 | — | — | 1140.85 (7.28x) | 360.33 (2.30x) |
| StringValue Escape JSON parse | 170.46 | — | — | 1167.82 (6.85x) | 435.35 (2.55x) |
| StringValue Surrogate JSON parse | 178.08 | — | — | 1168.45 (6.56x) | 384.78 (2.16x) |
| EmptyStringValue JSON stringify | 66.73 | — | — | 638.03 (9.56x) | 179.84 (2.70x) |
| EmptyStringValue JSON parse | 87.04 | — | — | 1109.03 (12.74x) | 238.96 (2.75x) |
| BytesValue JSON stringify | 66.34 | — | — | 679.55 (10.24x) | 217.70 (3.28x) |
| BytesValue JSON parse | 158.62 | — | — | 1177.65 (7.42x) | 352.17 (2.22x) |
| BytesValue URL JSON parse | 179.54 | — | — | 1164.22 (6.48x) | 334.18 (1.86x) |
| BytesValue StandardBase64 JSON parse | 155.25 | — | — | 1182.39 (7.62x) | 348.20 (2.24x) |
| BytesValue Unpadded JSON parse | 155.39 | — | — | 1164.54 (7.49x) | 348.63 (2.24x) |
| EmptyBytesValue JSON stringify | 56.10 | — | — | 654.17 (11.66x) | 188.71 (3.36x) |
| EmptyBytesValue JSON parse | 84.44 | — | — | 1132.08 (13.41x) | 305.16 (3.61x) |
| TextFormat format | 300.86 | — | — | 2601.72 (8.65x) | 2600.83 (8.64x) |
| TextFormat parse | 1216.23 | — | — | 4985.22 (4.10x) | 6666.06 (5.48x) |
| packed fixed32 encode | 2.01 | 561.89 (279.55x) | 541.43 (269.37x) | 43.46 (21.62x) | 392.82 (195.43x) |
| packed fixed32 decode | 4.53 | 1049.37 (231.65x) | 1964.22 (433.60x) | 49.68 (10.97x) | 1547.81 (341.68x) |
| packed fixed64 encode | 2.01 | 571.12 (284.14x) | 567.43 (282.30x) | 75.85 (37.74x) | 397.38 (197.70x) |
| packed fixed64 decode | 4.53 | 1034.10 (228.28x) | 8501.15 (1876.63x) | 79.77 (17.61x) | 2179.72 (481.17x) |
| packed sfixed32 encode | 2.01 | 548.44 (272.86x) | 575.20 (286.17x) | 43.47 (21.63x) | 420.94 (209.42x) |
| packed sfixed32 decode | 4.54 | 1067.38 (235.11x) | 2745.33 (604.70x) | 48.75 (10.74x) | 1544.75 (340.25x) |
| packed sfixed64 encode | 2.00 | 568.59 (284.30x) | 713.75 (356.88x) | 75.56 (37.78x) | 399.61 (199.81x) |
| packed sfixed64 decode | 4.53 | 990.93 (218.75x) | 8159.34 (1801.18x) | 79.78 (17.61x) | 2164.09 (477.72x) |
| packed float encode | 2.01 | 813.91 (404.93x) | 539.48 (268.40x) | 43.43 (21.61x) | 731.45 (363.91x) |
| packed float decode | 4.54 | 1044.77 (230.13x) | 2066.85 (455.25x) | 48.73 (10.73x) | 1542.10 (339.67x) |
| packed double encode | 2.01 | 829.48 (412.68x) | 560.99 (279.10x) | 76.19 (37.91x) | 362.50 (180.35x) |
| packed double decode | 4.52 | 981.00 (217.04x) | 2057.34 (455.16x) | 79.32 (17.55x) | 2159.30 (477.72x) |
| packed uint64 encode | 1294.87 | 4609.79 (3.56x) | 4042.24 (3.12x) | 2129.99 (1.64x) | 3451.21 (2.67x) |
| packed uint64 decode | 1782.69 | 2783.94 (1.56x) | 8877.17 (4.98x) | 2799.78 (1.57x) | 6290.15 (3.53x) |
| packed uint32 encode | 924.48 | 3616.03 (3.91x) | 3411.33 (3.69x) | 1733.40 (1.88x) | 2890.71 (3.13x) |
| packed uint32 decode | 1321.41 | 2426.40 (1.84x) | 3266.23 (2.47x) | 1988.89 (1.51x) | 4757.22 (3.60x) |
| packed int64 encode | 1398.87 | 10960.14 (7.83x) | 6076.29 (4.34x) | 2891.73 (2.07x) | 4152.68 (2.97x) |
| packed int64 decode | 2758.68 | 3371.01 (1.22x) | 10252.11 (3.72x) | 4780.17 (1.73x) | 7797.20 (2.83x) |
| packed sint32 encode | 846.43 | 3031.22 (3.58x) | 2854.11 (3.37x) | 1526.31 (1.80x) | 3381.18 (3.99x) |
| packed sint32 decode | 954.16 | 2549.52 (2.67x) | 3175.53 (3.33x) | 1121.71 (1.18x) | 3043.40 (3.19x) |
| packed sint64 encode | 1434.50 | 4925.04 (3.43x) | 4404.45 (3.07x) | 2451.71 (1.71x) | 4132.95 (2.88x) |
| packed sint64 decode | 2039.05 | 3057.42 (1.50x) | 9759.02 (4.79x) | 2932.32 (1.44x) | 6619.05 (3.25x) |
| packed bool encode | 2.86 | 1334.47 (466.60x) | 521.49 (182.34x) | 15.74 (5.50x) | 2421.84 (846.80x) |
| packed bool decode | 448.74 | 1522.27 (3.39x) | 2551.89 (5.69x) | 805.32 (1.79x) | 1663.45 (3.71x) |
| packed enum encode | 513.29 | 2731.00 (5.32x) | 1800.65 (3.51x) | 1083.31 (2.11x) | 2623.37 (5.11x) |
| packed enum decode | 246.08 | 1536.35 (6.24x) | 2919.32 (11.86x) | 701.58 (2.85x) | 2031.21 (8.25x) |
| large map encode | 4101.31 | 16571.23 (4.04x) | 9639.41 (2.35x) | 21723.30 (5.30x) | 209484.50 (51.08x) |
| shuffled large map deterministic binary encode | 28110.89 | — | — | 85587.10 (3.04x) | 445515.07 (15.85x) |
| large map decode | 25782.48 | 90788.04 (3.52x) | 88735.50 (3.44x) | 93013.40 (3.61x) | 281555.15 (10.92x) |
The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound `Duration`, non-empty/escaped-input parse/number-exponent parse and empty `Struct`, object/escaped-object parse/object-number-exponent/list/escaped-list/string-scalar/escaped-string-scalar/number-exponent/negative-number `Value` (including default-like scalar and empty object/list kinds),
`FieldMask` (non-empty, escaped JSON parse input, and empty), escaped-input parse/short-fraction parse/micro/nano/offset/min/pre/post/max-bound `Timestamp`, `Empty`, min/zero/positive/number-input parse/numeric-exponent parse/negative/max `Int64Value`, negative/zero/positive finite/string-input parse/numeric-exponent parse `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), negative/zero/positive finite/string-input parse/numeric-exponent parse `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), zero/normal/number-input parse/numeric-exponent parse/max `UInt64Value`, min/zero/positive/string-input parse/numeric-exponent parse/negative/max `Int32Value`, zero/normal/string-input parse/numeric-exponent parse/max `UInt32Value`, true/false `BoolValue`, non-empty/escape-input parse/surrogate-pair parse/empty `StringValue`, padded-standard/base64url/unpadded-base64 parse/empty `BytesValue`, and recursive nested `Any` payloads), direct zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound Duration, non-empty/escaped-input parse/empty FieldMask, and escaped-input parse/short-fraction parse/micro/nano/offset/min/pre/post/max-bound Timestamp WKT JSON plus other direct WKT JSON, including non-empty/escaped-input parse/number-exponent parse/empty `Struct`, object/escaped-object parse/object-number-exponent/list/escaped-list/string-scalar/escaped-string-scalar/number-exponent/negative-number `Value`, and escaped/non-empty/empty `ListValue`, TextFormat, packed scalars, large bytes,
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
