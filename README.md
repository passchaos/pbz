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

Latest accepted comparison (`/tmp/pbz-compare-struct-value-number-exponent-json-final.log`,
summarized in `/tmp/pbz-summary-struct-value-number-exponent-json-final.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 20.31 | 99.61 (4.90x) | 51.53 (2.54x) | 102.50 (5.05x) | 792.49 (39.02x) |
| binary decode | 90.79 | 251.48 (2.77x) | 227.50 (2.51x) | 229.74 (2.53x) | 878.65 (9.68x) |
| unknown fields count by number | 3.57 | — | — | 162.99 (45.65x) | — |
| deterministic binary encode | 64.36 | — | — | 128.63 (2.00x) | 1057.94 (16.44x) |
| scalarmix encode | 19.55 | 107.49 (5.50x) | 48.09 (2.46x) | 30.65 (1.57x) | 224.34 (11.48x) |
| scalarmix decode | 34.70 | 134.18 (3.87x) | 175.71 (5.06x) | 81.79 (2.36x) | 296.98 (8.56x) |
| textbytes encode | 12.83 | 78.56 (6.12x) | 33.60 (2.62x) | 116.41 (9.07x) | 176.09 (13.72x) |
| textbytes decode | 49.03 | 377.98 (7.71x) | 238.32 (4.86x) | 165.88 (3.38x) | 649.18 (13.24x) |
| largebytes encode | 18.04 | 2718.20 (150.68x) | 2676.69 (148.38x) | 2670.84 (148.05x) | 2702.94 (149.83x) |
| largebytes decode | 87.92 | 5478.23 (62.31x) | 3045.59 (34.64x) | 2748.54 (31.26x) | 25372.87 (288.59x) |
| presencemix encode | 17.54 | 56.58 (3.23x) | 27.62 (1.57x) | 56.36 (3.21x) | 231.07 (13.17x) |
| presencemix decode | 57.99 | 135.70 (2.34x) | 119.08 (2.05x) | 163.68 (2.82x) | 479.29 (8.27x) |
| complex encode | 49.62 | 137.61 (2.77x) | 97.74 (1.97x) | 163.43 (3.29x) | 933.76 (18.82x) |
| complex decode | 172.76 | 392.42 (2.27x) | 346.84 (2.01x) | 384.76 (2.23x) | 1360.04 (7.87x) |
| complex deterministic binary encode | 91.36 | — | — | 173.88 (1.90x) | 1129.74 (12.37x) |
| complex JSON stringify | 259.72 | — | — | 4907.85 (18.90x) | 6118.99 (23.56x) |
| complex JSON parse | 2420.72 | — | — | 11888.70 (4.91x) | 7387.47 (3.05x) |
| complex TextFormat format | 246.66 | — | — | 3767.75 (15.28x) | 5177.44 (20.99x) |
| complex TextFormat parse | 1879.55 | — | — | 6901.42 (3.67x) | 8505.47 (4.53x) |
| packed int32 encode | 633.67 | 3171.16 (5.00x) | 2516.85 (3.97x) | 1225.79 (1.93x) | 2745.61 (4.33x) |
| packed int32 decode | 691.24 | 1937.09 (2.80x) | 3219.32 (4.66x) | 958.99 (1.39x) | 3730.48 (5.40x) |
| JSON stringify | 152.54 | — | — | 3006.33 (19.71x) | 2120.92 (13.90x) |
| JSON parse | 1520.08 | — | — | 7426.12 (4.89x) | 4340.21 (2.86x) |
| Any WKT JSON stringify | 140.23 | — | — | 1875.79 (13.38x) | 1041.07 (7.42x) |
| Any WKT JSON parse | 562.30 | — | — | 2983.23 (5.31x) | 1438.34 (2.56x) |
| Any Duration Escape WKT JSON parse | 570.61 | — | — | 3010.65 (5.28x) | 1499.40 (2.63x) |
| Any PlusDuration WKT JSON parse | 544.44 | — | — | 3007.78 (5.52x) | 1454.71 (2.67x) |
| Any ShortFractionDuration WKT JSON parse | 537.42 | — | — | 2944.92 (5.48x) | 1469.18 (2.73x) |
| Any MicroDuration WKT JSON stringify | 138.34 | — | — | 1886.57 (13.64x) | 1049.84 (7.59x) |
| Any MicroDuration WKT JSON parse | 539.88 | — | — | 3001.98 (5.56x) | 1459.12 (2.70x) |
| Any NanoDuration WKT JSON stringify | 132.54 | — | — | 1908.90 (14.40x) | 1051.10 (7.93x) |
| Any NanoDuration WKT JSON parse | 531.97 | — | — | 3009.68 (5.66x) | 1464.13 (2.75x) |
| Any NegativeDuration WKT JSON stringify | 132.57 | — | — | 1931.66 (14.57x) | 1118.21 (8.43x) |
| Any NegativeDuration WKT JSON parse | 529.33 | — | — | 3095.09 (5.85x) | 1521.11 (2.87x) |
| Any FractionalNegativeDuration WKT JSON stringify | 127.32 | — | — | 1886.77 (14.82x) | 983.93 (7.73x) |
| Any FractionalNegativeDuration WKT JSON parse | 522.69 | — | — | 3052.07 (5.84x) | 1626.94 (3.11x) |
| Any MaxDuration WKT JSON stringify | 119.85 | — | — | 1740.49 (14.52x) | 991.33 (8.27x) |
| Any MaxDuration WKT JSON parse | 540.98 | — | — | 2966.73 (5.48x) | 1577.17 (2.92x) |
| Any MinDuration WKT JSON stringify | 122.05 | — | — | 1768.59 (14.49x) | 993.94 (8.14x) |
| Any MinDuration WKT JSON parse | 543.74 | — | — | 3031.51 (5.58x) | 1522.23 (2.80x) |
| Any ZeroDuration WKT JSON stringify | 107.63 | — | — | 1315.98 (12.23x) | 988.55 (9.18x) |
| Any ZeroDuration WKT JSON parse | 473.72 | — | — | 2267.76 (4.79x) | 1359.02 (2.87x) |
| Any FieldMask WKT JSON stringify | 228.69 | — | — | 1738.07 (7.60x) | 1420.92 (6.21x) |
| Any FieldMask WKT JSON parse | 722.75 | — | — | 3148.41 (4.36x) | 2038.66 (2.82x) |
| Any FieldMask Escape WKT JSON parse | 735.37 | — | — | 3244.57 (4.41x) | 2290.05 (3.11x) |
| Any EmptyFieldMask WKT JSON stringify | 115.06 | — | — | 924.89 (8.04x) | 744.95 (6.47x) |
| Any EmptyFieldMask WKT JSON parse | 449.97 | — | — | 2166.29 (4.81x) | 1247.03 (2.77x) |
| Any Timestamp WKT JSON stringify | 178.94 | — | — | 2045.20 (11.43x) | 1043.16 (5.83x) |
| Any Timestamp WKT JSON parse | 570.24 | — | — | 3042.33 (5.34x) | 1710.18 (3.00x) |
| Any Timestamp Escape WKT JSON parse | 588.46 | — | — | 3121.18 (5.30x) | 1670.14 (2.84x) |
| Any ShortFraction Timestamp WKT JSON parse | 567.18 | — | — | 3030.85 (5.34x) | 1532.84 (2.70x) |
| Any Micro Timestamp WKT JSON stringify | 179.76 | — | — | 2051.70 (11.41x) | 1052.48 (5.85x) |
| Any Micro Timestamp WKT JSON parse | 578.38 | — | — | 3035.67 (5.25x) | 1822.42 (3.15x) |
| Any Nano Timestamp WKT JSON stringify | 177.82 | — | — | 2046.38 (11.51x) | 1060.54 (5.96x) |
| Any Nano Timestamp WKT JSON parse | 583.39 | — | — | 3041.77 (5.21x) | 1560.84 (2.68x) |
| Any Offset Timestamp WKT JSON parse | 595.77 | — | — | 3067.72 (5.15x) | 1599.38 (2.68x) |
| Any PreEpoch Timestamp WKT JSON stringify | 143.45 | — | — | 1949.70 (13.59x) | 993.88 (6.93x) |
| Any PreEpoch Timestamp WKT JSON parse | 561.43 | — | — | 3045.14 (5.42x) | 1497.80 (2.67x) |
| Any Max Timestamp WKT JSON stringify | 162.52 | — | — | 2058.42 (12.67x) | 1099.48 (6.77x) |
| Any Max Timestamp WKT JSON parse | 586.50 | — | — | 3091.56 (5.27x) | 1578.00 (2.69x) |
| Any Min Timestamp WKT JSON stringify | 158.38 | — | — | 1944.29 (12.28x) | 1000.48 (6.32x) |
| Any Min Timestamp WKT JSON parse | 559.40 | — | — | 3037.35 (5.43x) | 1562.86 (2.79x) |
| Any Empty WKT JSON stringify | 88.75 | — | — | 916.51 (10.33x) | 616.57 (6.95x) |
| Any Empty WKT JSON parse | 342.21 | — | — | 2147.61 (6.28x) | 1292.20 (3.78x) |
| Any Struct WKT JSON stringify | 636.02 | — | — | 5826.98 (9.16x) | 6202.92 (9.75x) |
| Any Struct WKT JSON parse | 1747.97 | — | — | 11126.50 (6.37x) | 8988.73 (5.14x) |
| Any Struct Escape WKT JSON parse | 1770.96 | — | — | 11198.80 (6.32x) | 8784.36 (4.96x) |
| Any Struct NumberExponent WKT JSON parse | 1757.22 | — | — | 11103.30 (6.32x) | 9063.57 (5.16x) |
| Any EmptyStruct WKT JSON stringify | 117.80 | — | — | 911.32 (7.74x) | 904.46 (7.68x) |
| Any EmptyStruct WKT JSON parse | 437.26 | — | — | 2225.00 (5.09x) | 1523.52 (3.48x) |
| Any Value WKT JSON stringify | 666.46 | — | — | 5912.27 (8.87x) | 7022.84 (10.54x) |
| Any Value WKT JSON parse | 1802.12 | — | — | 11355.10 (6.30x) | 9267.61 (5.14x) |
| Any Value Escape WKT JSON parse | 1831.97 | — | — | 11404.20 (6.23x) | 9466.83 (5.17x) |
| Any Value NumberExponent WKT JSON parse | 1807.90 | — | — | 11370.50 (6.29x) | 9274.43 (5.13x) |
| Any NullValue WKT JSON stringify | 128.48 | — | — | 2246.21 (17.48x) | 921.45 (7.17x) |
| Any NullValue WKT JSON parse | 468.58 | — | — | 4045.88 (8.63x) | 1539.43 (3.29x) |
| Any StringScalarValue WKT JSON stringify | 152.62 | — | — | 2268.27 (14.86x) | 1063.64 (6.97x) |
| Any StringScalarValue WKT JSON parse | 521.80 | — | — | 3600.40 (6.90x) | 1570.74 (3.01x) |
| Any StringScalarValue Escape WKT JSON parse | 537.44 | — | — | 3666.41 (6.82x) | 1654.21 (3.08x) |
| Any EmptyStringScalarValue WKT JSON stringify | 141.43 | — | — | 2268.81 (16.04x) | 941.03 (6.65x) |
| Any EmptyStringScalarValue WKT JSON parse | 496.06 | — | — | 3602.51 (7.26x) | 1477.14 (2.98x) |
| Any NumberValue WKT JSON stringify | 176.13 | — | — | 2507.33 (14.24x) | 1012.79 (5.75x) |
| Any NumberValue WKT JSON parse | 505.04 | — | — | 3661.18 (7.25x) | 1521.68 (3.01x) |
| Any NumberValue Exponent WKT JSON parse | 507.87 | — | — | 3707.00 (7.30x) | 1589.17 (3.13x) |
| Any ZeroNumberValue WKT JSON stringify | 140.39 | — | — | 2462.93 (17.54x) | 915.71 (6.52x) |
| Any ZeroNumberValue WKT JSON parse | 501.26 | — | — | 3633.80 (7.25x) | 1504.10 (3.00x) |
| Any BoolScalarValue WKT JSON stringify | 131.67 | — | — | 2254.58 (17.12x) | 901.21 (6.84x) |
| Any BoolScalarValue WKT JSON parse | 467.59 | — | — | 3607.08 (7.71x) | 1427.13 (3.05x) |
| Any FalseBoolScalarValue WKT JSON stringify | 130.19 | — | — | 2261.15 (17.37x) | 920.79 (7.07x) |
| Any FalseBoolScalarValue WKT JSON parse | 466.65 | — | — | 3626.05 (7.77x) | 1483.01 (3.18x) |
| Any ListKindValue WKT JSON stringify | 503.96 | — | — | 5743.41 (11.40x) | 5118.52 (10.16x) |
| Any ListKindValue WKT JSON parse | 1381.23 | — | — | 9971.99 (7.22x) | 7125.60 (5.16x) |
| Any ListKindValue Escape WKT JSON parse | 1431.93 | — | — | 10043.40 (7.01x) | 7841.49 (5.48x) |
| Any EmptyStructKindValue WKT JSON stringify | 148.34 | — | — | 2909.19 (19.61x) | 1311.96 (8.84x) |
| Any EmptyStructKindValue WKT JSON parse | 507.33 | — | — | 5413.39 (10.67x) | 1868.68 (3.68x) |
| Any EmptyListKindValue WKT JSON stringify | 145.77 | — | — | 2888.10 (19.81x) | 1192.70 (8.18x) |
| Any EmptyListKindValue WKT JSON parse | 506.82 | — | — | 4379.62 (8.64x) | 1803.22 (3.56x) |
| Any DoubleValue WKT JSON stringify | 191.53 | — | — | 1794.30 (9.37x) | 807.52 (4.22x) |
| Any DoubleValue WKT JSON parse | 528.83 | — | — | 2735.21 (5.17x) | 1387.26 (2.62x) |
| Any DoubleValue String WKT JSON parse | 540.82 | — | — | 2732.53 (5.05x) | 1574.32 (2.91x) |
| Any NegativeDoubleValue WKT JSON stringify | 193.18 | — | — | 1803.84 (9.34x) | 821.54 (4.25x) |
| Any NegativeDoubleValue WKT JSON parse | 530.25 | — | — | 2741.94 (5.17x) | 1591.66 (3.00x) |
| Any ZeroDoubleValue WKT JSON stringify | 161.61 | — | — | 984.51 (6.09x) | 762.39 (4.72x) |
| Any ZeroDoubleValue WKT JSON parse | 525.40 | — | — | 2166.31 (4.12x) | 1511.66 (2.88x) |
| Any DoubleValue NaN WKT JSON stringify | 157.22 | — | — | 1582.43 (10.07x) | 735.38 (4.68x) |
| Any DoubleValue NaN WKT JSON parse | 523.28 | — | — | 2663.71 (5.09x) | 1573.10 (3.01x) |
| Any DoubleValue Infinity WKT JSON stringify | 155.57 | — | — | 1561.87 (10.04x) | 715.83 (4.60x) |
| Any DoubleValue Infinity WKT JSON parse | 528.06 | — | — | 2684.89 (5.08x) | 1364.23 (2.58x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 166.87 | — | — | 1557.66 (9.33x) | 758.65 (4.55x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 529.75 | — | — | 2658.41 (5.02x) | 1489.90 (2.81x) |
| Any FloatValue WKT JSON stringify | 196.17 | — | — | 1726.03 (8.80x) | 824.18 (4.20x) |
| Any FloatValue WKT JSON parse | 524.73 | — | — | 2694.13 (5.13x) | 1643.18 (3.13x) |
| Any FloatValue String WKT JSON parse | 538.69 | — | — | 2703.78 (5.02x) | 1452.22 (2.70x) |
| Any NegativeFloatValue WKT JSON stringify | 199.70 | — | — | 1725.62 (8.64x) | 760.76 (3.81x) |
| Any NegativeFloatValue WKT JSON parse | 527.56 | — | — | 2695.83 (5.11x) | 1454.01 (2.76x) |
| Any ZeroFloatValue WKT JSON stringify | 164.78 | — | — | 911.77 (5.53x) | 742.51 (4.51x) |
| Any ZeroFloatValue WKT JSON parse | 521.10 | — | — | 2144.40 (4.12x) | 1333.74 (2.56x) |
| Any FloatValue NaN WKT JSON stringify | 158.10 | — | — | 1553.25 (9.82x) | 727.12 (4.60x) |
| Any FloatValue NaN WKT JSON parse | 517.35 | — | — | 2604.29 (5.03x) | 1430.06 (2.76x) |
| Any FloatValue Infinity WKT JSON stringify | 162.26 | — | — | 1541.36 (9.50x) | 728.56 (4.49x) |
| Any FloatValue Infinity WKT JSON parse | 521.88 | — | — | 2648.34 (5.07x) | 1402.86 (2.69x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 162.51 | — | — | 1540.70 (9.48x) | 719.52 (4.43x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 526.40 | — | — | 2641.20 (5.02x) | 1484.12 (2.82x) |
| Any Int64Value WKT JSON stringify | 169.94 | — | — | 1555.57 (9.15x) | 1000.03 (5.88x) |
| Any Int64Value WKT JSON parse | 563.21 | — | — | 2768.62 (4.92x) | 1890.08 (3.36x) |
| Any Int64Value Number WKT JSON parse | 563.65 | — | — | 2744.99 (4.87x) | 1530.25 (2.71x) |
| Any ZeroInt64Value WKT JSON stringify | 159.32 | — | — | 911.69 (5.72x) | 915.96 (5.75x) |
| Any ZeroInt64Value WKT JSON parse | 528.56 | — | — | 2143.66 (4.06x) | 1504.07 (2.85x) |
| Any NegativeInt64Value WKT JSON stringify | 170.39 | — | — | 1551.07 (9.10x) | 953.05 (5.59x) |
| Any NegativeInt64Value WKT JSON parse | 563.59 | — | — | 2790.92 (4.95x) | 1665.56 (2.96x) |
| Any MinInt64Value WKT JSON stringify | 171.22 | — | — | 1554.50 (9.08x) | 911.67 (5.32x) |
| Any MinInt64Value WKT JSON parse | 571.91 | — | — | 2812.94 (4.92x) | 1889.38 (3.30x) |
| Any MaxInt64Value WKT JSON stringify | 171.52 | — | — | 1558.59 (9.09x) | 988.04 (5.76x) |
| Any MaxInt64Value WKT JSON parse | 569.49 | — | — | 2793.95 (4.91x) | 1628.22 (2.86x) |
| Any UInt64Value WKT JSON stringify | 175.88 | — | — | 1550.85 (8.82x) | 907.10 (5.16x) |
| Any UInt64Value WKT JSON parse | 555.70 | — | — | 2782.50 (5.01x) | 1725.04 (3.10x) |
| Any UInt64Value Number WKT JSON parse | 570.53 | — | — | 2763.37 (4.84x) | 1560.08 (2.73x) |
| Any ZeroUInt64Value WKT JSON stringify | 165.93 | — | — | 913.97 (5.51x) | 815.22 (4.91x) |
| Any ZeroUInt64Value WKT JSON parse | 532.64 | — | — | 2152.92 (4.04x) | 1556.21 (2.92x) |
| Any MaxUInt64Value WKT JSON stringify | 177.20 | — | — | 1553.07 (8.76x) | 882.60 (4.98x) |
| Any MaxUInt64Value WKT JSON parse | 564.10 | — | — | 2836.73 (5.03x) | 2118.99 (3.76x) |
| Any Int32Value WKT JSON stringify | 173.97 | — | — | 1542.36 (8.87x) | 757.05 (4.35x) |
| Any Int32Value WKT JSON parse | 537.77 | — | — | 2650.60 (4.93x) | 1603.77 (2.98x) |
| Any Int32Value String WKT JSON parse | 542.47 | — | — | 2669.73 (4.92x) | 1440.63 (2.66x) |
| Any ZeroInt32Value WKT JSON stringify | 170.40 | — | — | 911.32 (5.35x) | 721.25 (4.23x) |
| Any ZeroInt32Value WKT JSON parse | 534.24 | — | — | 2148.77 (4.02x) | 1508.81 (2.82x) |
| Any NegativeInt32Value WKT JSON stringify | 174.52 | — | — | 1544.64 (8.85x) | 760.87 (4.36x) |
| Any NegativeInt32Value WKT JSON parse | 538.06 | — | — | 2687.01 (4.99x) | 1713.54 (3.18x) |
| Any MinInt32Value WKT JSON stringify | 178.01 | — | — | 1549.72 (8.71x) | 777.35 (4.37x) |
| Any MinInt32Value WKT JSON parse | 545.94 | — | — | 2707.16 (4.96x) | 1636.26 (3.00x) |
| Any MaxInt32Value WKT JSON stringify | 177.61 | — | — | 1544.46 (8.70x) | 745.36 (4.20x) |
| Any MaxInt32Value WKT JSON parse | 546.54 | — | — | 2665.40 (4.88x) | 1470.79 (2.69x) |
| Any UInt32Value WKT JSON stringify | 179.39 | — | — | 1551.69 (8.65x) | 848.67 (4.73x) |
| Any UInt32Value WKT JSON parse | 540.00 | — | — | 2656.80 (4.92x) | 1437.64 (2.66x) |
| Any UInt32Value String WKT JSON parse | 547.48 | — | — | 2673.02 (4.88x) | 1462.49 (2.67x) |
| Any ZeroUInt32Value WKT JSON stringify | 178.09 | — | — | 913.40 (5.13x) | 724.71 (4.07x) |
| Any ZeroUInt32Value WKT JSON parse | 536.51 | — | — | 2158.16 (4.02x) | 1368.59 (2.55x) |
| Any MaxUInt32Value WKT JSON stringify | 184.16 | — | — | 1548.44 (8.41x) | 712.11 (3.87x) |
| Any MaxUInt32Value WKT JSON parse | 548.20 | — | — | 2668.81 (4.87x) | 1522.06 (2.78x) |
| Any BoolValue WKT JSON stringify | 170.88 | — | — | 1520.97 (8.90x) | 759.31 (4.44x) |
| Any BoolValue WKT JSON parse | 494.58 | — | — | 2605.70 (5.27x) | 1344.80 (2.72x) |
| Any FalseBoolValue WKT JSON stringify | 168.33 | — | — | 911.99 (5.42x) | 759.45 (4.51x) |
| Any FalseBoolValue WKT JSON parse | 493.40 | — | — | 2143.05 (4.34x) | 1433.72 (2.91x) |
| Any StringValue WKT JSON stringify | 197.55 | — | — | 1557.64 (7.88x) | 840.77 (4.26x) |
| Any StringValue WKT JSON parse | 559.61 | — | — | 2649.66 (4.73x) | 1421.74 (2.54x) |
| Any StringValue Escape WKT JSON parse | 565.67 | — | — | 2693.14 (4.76x) | 1624.39 (2.87x) |
| Any EmptyStringValue WKT JSON stringify | 190.27 | — | — | 912.27 (4.79x) | 748.80 (3.94x) |
| Any EmptyStringValue WKT JSON parse | 527.80 | — | — | 2155.77 (4.08x) | 1405.42 (2.66x) |
| Any BytesValue WKT JSON stringify | 188.14 | — | — | 1580.64 (8.40x) | 843.59 (4.48x) |
| Any BytesValue WKT JSON parse | 573.51 | — | — | 2681.44 (4.68x) | 1530.93 (2.67x) |
| Any BytesValue URL WKT JSON parse | 587.40 | — | — | 2671.29 (4.55x) | 1511.20 (2.57x) |
| Any EmptyBytesValue WKT JSON stringify | 185.10 | — | — | 912.44 (4.93x) | 784.04 (4.24x) |
| Any EmptyBytesValue WKT JSON parse | 536.88 | — | — | 2150.95 (4.01x) | 1493.87 (2.78x) |
| Nested Any WKT JSON stringify | 302.36 | — | — | 2473.70 (8.18x) | 1495.14 (4.94x) |
| Nested Any WKT JSON parse | 868.80 | — | — | 4251.66 (4.89x) | 2978.34 (3.43x) |
| Duration JSON stringify | 57.59 | — | — | 962.46 (16.71x) | 370.88 (6.44x) |
| Duration JSON parse | 20.41 | — | — | 1444.31 (70.76x) | 386.30 (18.93x) |
| Duration Escape JSON parse | 41.84 | — | — | 1479.73 (35.37x) | 427.27 (10.21x) |
| PlusDuration JSON parse | 19.32 | — | — | 1455.94 (75.36x) | 387.51 (20.06x) |
| ShortFractionDuration JSON parse | 15.06 | — | — | 1448.70 (96.20x) | 372.80 (24.75x) |
| MicroDuration JSON stringify | 58.87 | — | — | 977.50 (16.60x) | 404.93 (6.88x) |
| MicroDuration JSON parse | 20.67 | — | — | 1475.31 (71.37x) | 382.26 (18.49x) |
| NanoDuration JSON stringify | 56.62 | — | — | 999.35 (17.65x) | 395.98 (6.99x) |
| NanoDuration JSON parse | 22.75 | — | — | 1490.31 (65.51x) | 373.87 (16.43x) |
| NegativeDuration JSON stringify | 57.78 | — | — | 1022.53 (17.70x) | 422.24 (7.31x) |
| NegativeDuration JSON parse | 19.46 | — | — | 1526.84 (78.46x) | 381.59 (19.61x) |
| FractionalNegativeDuration JSON stringify | 58.71 | — | — | 988.25 (16.83x) | 409.47 (6.97x) |
| FractionalNegativeDuration JSON parse | 19.81 | — | — | 1477.79 (74.60x) | 366.17 (18.48x) |
| MaxDuration JSON stringify | 49.16 | — | — | 860.23 (17.50x) | 411.38 (8.37x) |
| MaxDuration JSON parse | 35.78 | — | — | 1448.79 (40.49x) | 397.69 (11.11x) |
| MinDuration JSON stringify | 49.50 | — | — | 885.61 (17.89x) | 413.14 (8.35x) |
| MinDuration JSON parse | 34.48 | — | — | 1458.76 (42.31x) | 398.90 (11.57x) |
| ZeroDuration JSON stringify | 44.37 | — | — | 824.10 (18.57x) | 361.75 (8.15x) |
| ZeroDuration JSON parse | 16.33 | — | — | 1388.53 (85.03x) | 300.27 (18.39x) |
| FieldMask JSON stringify | 134.77 | — | — | 893.24 (6.63x) | 668.34 (4.96x) |
| FieldMask JSON parse | 152.75 | — | — | 1671.45 (10.94x) | 819.66 (5.37x) |
| FieldMask Escape JSON parse | 200.26 | — | — | 1729.63 (8.64x) | 973.65 (4.86x) |
| EmptyFieldMask JSON stringify | 40.66 | — | — | 611.33 (15.04x) | 184.94 (4.55x) |
| EmptyFieldMask JSON parse | 4.78 | — | — | 949.98 (198.74x) | 186.40 (39.00x) |
| Timestamp JSON stringify | 95.47 | — | — | 1174.79 (12.31x) | 418.34 (4.38x) |
| Timestamp JSON parse | 45.53 | — | — | 1511.09 (33.19x) | 419.13 (9.21x) |
| Timestamp Escape JSON parse | 84.39 | — | — | 1537.72 (18.22x) | 499.28 (5.92x) |
| ShortFraction Timestamp JSON parse | 43.56 | — | — | 1499.31 (34.42x) | 436.75 (10.03x) |
| Micro Timestamp JSON stringify | 95.74 | — | — | 1156.82 (12.08x) | 440.63 (4.60x) |
| Micro Timestamp JSON parse | 48.24 | — | — | 1525.54 (31.62x) | 441.86 (9.16x) |
| Nano Timestamp JSON stringify | 94.05 | — | — | 1204.87 (12.81x) | 449.58 (4.78x) |
| Nano Timestamp JSON parse | 51.88 | — | — | 1543.74 (29.76x) | 445.66 (8.59x) |
| Offset Timestamp JSON parse | 52.09 | — | — | 1554.61 (29.84x) | 470.28 (9.03x) |
| PreEpoch Timestamp JSON stringify | 66.09 | — | — | 1083.83 (16.40x) | 409.30 (6.19x) |
| PreEpoch Timestamp JSON parse | 43.06 | — | — | 1487.20 (34.54x) | 425.91 (9.89x) |
| Max Timestamp JSON stringify | 78.34 | — | — | 1215.72 (15.52x) | 444.20 (5.67x) |
| Max Timestamp JSON parse | 51.08 | — | — | 1558.87 (30.52x) | 443.68 (8.69x) |
| Min Timestamp JSON stringify | 80.02 | — | — | 1082.86 (13.53x) | 399.82 (5.00x) |
| Min Timestamp JSON parse | 41.05 | — | — | 1472.05 (35.86x) | 402.49 (9.80x) |
| Empty JSON stringify | 20.58 | — | — | 498.39 (24.22x) | 80.72 (3.92x) |
| Empty JSON parse | 67.46 | — | — | 727.43 (10.78x) | 207.66 (3.08x) |
| Struct JSON stringify | 182.31 | — | — | 5861.09 (32.15x) | 2829.02 (15.52x) |
| Struct JSON parse | 857.96 | — | — | 11035.30 (12.86x) | 4885.11 (5.69x) |
| Struct Escape JSON parse | 905.84 | — | — | 11041.20 (12.19x) | 5063.12 (5.59x) |
| Struct NumberExponent JSON parse | 854.15 | — | — | 10927.90 (12.79x) | 4814.93 (5.64x) |
| EmptyStruct JSON stringify | 41.05 | — | — | 688.36 (16.77x) | 330.24 (8.04x) |
| EmptyStruct JSON parse | 87.78 | — | — | 2018.88 (23.00x) | 365.75 (4.17x) |
| Value JSON stringify | 181.58 | — | — | 6644.06 (36.59x) | 3149.62 (17.35x) |
| Value JSON parse | 873.89 | — | — | 12167.10 (13.92x) | 4896.56 (5.60x) |
| Value Escape JSON parse | 924.40 | — | — | 12239.00 (13.24x) | 5517.06 (5.97x) |
| Value NumberExponent JSON parse | 866.86 | — | — | 12163.70 (14.03x) | 6176.49 (7.13x) |
| NullValue JSON stringify | 40.00 | — | — | 1312.85 (32.82x) | 224.95 (5.62x) |
| NullValue JSON parse | 70.67 | — | — | 2439.15 (34.51x) | 331.84 (4.70x) |
| StringScalarValue JSON stringify | 48.17 | — | — | 1337.42 (27.76x) | 269.31 (5.59x) |
| StringScalarValue JSON parse | 140.73 | — | — | 2091.11 (14.86x) | 440.50 (3.13x) |
| StringScalarValue Escape JSON parse | 150.96 | — | — | 2120.90 (14.05x) | 462.24 (3.06x) |
| EmptyStringScalarValue JSON stringify | 48.73 | — | — | 1329.65 (27.29x) | 270.29 (5.55x) |
| EmptyStringScalarValue JSON parse | 87.95 | — | — | 2058.31 (23.40x) | 378.35 (4.30x) |
| NumberValue JSON stringify | 72.96 | — | — | 1548.73 (21.23x) | 332.20 (4.55x) |
| NumberValue JSON parse | 132.95 | — | — | 2172.41 (16.34x) | 399.29 (3.00x) |
| NumberValue Exponent JSON parse | 134.88 | — | — | 2183.42 (16.19x) | 416.01 (3.08x) |
| ZeroNumberValue JSON stringify | 50.68 | — | — | 1505.11 (29.70x) | 288.36 (5.69x) |
| ZeroNumberValue JSON parse | 131.30 | — | — | 2100.95 (16.00x) | 386.05 (2.94x) |
| BoolScalarValue JSON stringify | 40.06 | — | — | 1310.24 (32.71x) | 219.20 (5.47x) |
| BoolScalarValue JSON parse | 71.16 | — | — | 2035.33 (28.60x) | 326.66 (4.59x) |
| FalseBoolScalarValue JSON stringify | 40.18 | — | — | 1307.91 (32.55x) | 229.03 (5.70x) |
| FalseBoolScalarValue JSON parse | 70.91 | — | — | 2011.33 (28.36x) | 322.94 (4.55x) |
| ListKindValue JSON stringify | 141.01 | — | — | 6113.48 (43.35x) | 2380.28 (16.88x) |
| ListKindValue JSON parse | 679.15 | — | — | 10420.90 (15.34x) | 4220.78 (6.21x) |
| ListKindValue Escape JSON parse | 697.32 | — | — | 10494.80 (15.05x) | 4410.70 (6.33x) |
| EmptyStructKindValue JSON stringify | 42.66 | — | — | 1941.11 (45.50x) | 507.79 (11.90x) |
| EmptyStructKindValue JSON parse | 110.67 | — | — | 3763.22 (34.00x) | 675.70 (6.11x) |
| EmptyListKindValue JSON stringify | 41.17 | — | — | 1929.77 (46.87x) | 367.31 (8.92x) |
| EmptyListKindValue JSON parse | 149.10 | — | — | 4029.58 (27.03x) | 606.49 (4.07x) |
| ListValue JSON stringify | 141.97 | — | — | 4730.43 (33.32x) | 2199.17 (15.49x) |
| ListValue JSON parse | 659.16 | — | — | 8485.77 (12.87x) | 4012.01 (6.09x) |
| ListValue Escape JSON parse | 680.63 | — | — | 8579.94 (12.61x) | 4322.98 (6.35x) |
| EmptyListValue JSON stringify | 39.87 | — | — | 700.88 (17.58x) | 188.38 (4.72x) |
| EmptyListValue JSON parse | 124.19 | — | — | 2255.52 (18.16x) | 294.23 (2.37x) |
| DoubleValue JSON stringify | 69.30 | — | — | 859.64 (12.40x) | 189.15 (2.73x) |
| DoubleValue JSON parse | 110.28 | — | — | 1228.09 (11.14x) | 336.79 (3.05x) |
| DoubleValue String JSON parse | 111.92 | — | — | 1165.42 (10.41x) | 347.81 (3.11x) |
| NegativeDoubleValue JSON stringify | 68.42 | — | — | 858.14 (12.54x) | 191.01 (2.79x) |
| NegativeDoubleValue JSON parse | 111.30 | — | — | 1249.96 (11.23x) | 282.23 (2.54x) |
| ZeroDoubleValue JSON stringify | 47.40 | — | — | 803.80 (16.96x) | 167.17 (3.53x) |
| ZeroDoubleValue JSON parse | 107.84 | — | — | 1165.92 (10.81x) | 282.47 (2.62x) |
| DoubleValue NaN JSON stringify | 46.36 | — | — | 663.71 (14.32x) | 146.67 (3.16x) |
| DoubleValue NaN JSON parse | 105.01 | — | — | 1100.67 (10.48x) | 259.80 (2.47x) |
| DoubleValue Infinity JSON stringify | 48.11 | — | — | 662.06 (13.76x) | 124.46 (2.59x) |
| DoubleValue Infinity JSON parse | 106.87 | — | — | 1109.73 (10.38x) | 279.09 (2.61x) |
| DoubleValue NegativeInfinity JSON stringify | 48.37 | — | — | 653.39 (13.51x) | 148.00 (3.06x) |
| DoubleValue NegativeInfinity JSON parse | 109.50 | — | — | 1114.94 (10.18x) | 258.36 (2.36x) |
| FloatValue JSON stringify | 71.20 | — | — | 798.49 (11.21x) | 197.00 (2.77x) |
| FloatValue JSON parse | 110.46 | — | — | 1218.13 (11.03x) | 282.51 (2.56x) |
| FloatValue String JSON parse | 111.00 | — | — | 1155.76 (10.41x) | 377.84 (3.40x) |
| NegativeFloatValue JSON stringify | 71.54 | — | — | 798.56 (11.16x) | 205.28 (2.87x) |
| NegativeFloatValue JSON parse | 111.72 | — | — | 1220.61 (10.93x) | 298.26 (2.67x) |
| ZeroFloatValue JSON stringify | 72.61 | — | — | 742.12 (10.22x) | 134.04 (1.85x) |
| ZeroFloatValue JSON parse | 131.78 | — | — | 1155.61 (8.77x) | 258.70 (1.96x) |
| FloatValue NaN JSON stringify | 68.34 | — | — | 637.07 (9.32x) | 146.82 (2.15x) |
| FloatValue NaN JSON parse | 127.76 | — | — | 1084.12 (8.49x) | 282.26 (2.21x) |
| FloatValue Infinity JSON stringify | 73.39 | — | — | 641.17 (8.74x) | 129.95 (1.77x) |
| FloatValue Infinity JSON parse | 133.71 | — | — | 1096.79 (8.20x) | 283.38 (2.12x) |
| FloatValue NegativeInfinity JSON stringify | 75.21 | — | — | 634.23 (8.43x) | 115.78 (1.54x) |
| FloatValue NegativeInfinity JSON parse | 140.45 | — | — | 1099.45 (7.83x) | 277.21 (1.97x) |
| Int64Value JSON stringify | 67.45 | — | — | 675.22 (10.01x) | 275.23 (4.08x) |
| Int64Value JSON parse | 184.34 | — | — | 1239.14 (6.72x) | 474.11 (2.57x) |
| Int64Value Number JSON parse | 195.29 | — | — | 1291.29 (6.61x) | 351.87 (1.80x) |
| ZeroInt64Value JSON stringify | 56.00 | — | — | 610.90 (10.91x) | 213.25 (3.81x) |
| ZeroInt64Value JSON parse | 127.87 | — | — | 1101.24 (8.61x) | 355.02 (2.78x) |
| NegativeInt64Value JSON stringify | 48.64 | — | — | 672.47 (13.83x) | 253.80 (5.22x) |
| NegativeInt64Value JSON parse | 142.55 | — | — | 1218.25 (8.55x) | 484.03 (3.40x) |
| MinInt64Value JSON stringify | 71.98 | — | — | 675.18 (9.38x) | 287.03 (3.99x) |
| MinInt64Value JSON parse | 161.02 | — | — | 1249.01 (7.76x) | 467.83 (2.91x) |
| MaxInt64Value JSON stringify | 66.26 | — | — | 676.05 (10.20x) | 295.92 (4.47x) |
| MaxInt64Value JSON parse | 166.81 | — | — | 1247.42 (7.48x) | 455.68 (2.73x) |
| UInt64Value JSON stringify | 50.59 | — | — | 675.42 (13.35x) | 280.82 (5.55x) |
| UInt64Value JSON parse | 174.89 | — | — | 1219.55 (6.97x) | 453.84 (2.60x) |
| UInt64Value Number JSON parse | 182.82 | — | — | 1281.76 (7.01x) | 341.69 (1.87x) |
| ZeroUInt64Value JSON stringify | 41.87 | — | — | 606.44 (14.48x) | 195.67 (4.67x) |
| ZeroUInt64Value JSON parse | 105.86 | — | — | 1102.17 (10.41x) | 338.18 (3.19x) |
| MaxUInt64Value JSON stringify | 49.74 | — | — | 673.16 (13.53x) | 287.40 (5.78x) |
| MaxUInt64Value JSON parse | 135.48 | — | — | 1248.92 (9.22x) | 470.46 (3.47x) |
| Int32Value JSON stringify | 47.61 | — | — | 629.06 (13.21x) | 133.70 (2.81x) |
| Int32Value JSON parse | 117.61 | — | — | 1178.84 (10.02x) | 319.85 (2.72x) |
| Int32Value String JSON parse | 114.95 | — | — | 1128.71 (9.82x) | 391.62 (3.41x) |
| ZeroInt32Value JSON stringify | 47.20 | — | — | 611.08 (12.95x) | 122.84 (2.60x) |
| ZeroInt32Value JSON parse | 113.95 | — | — | 1147.34 (10.07x) | 272.65 (2.39x) |
| NegativeInt32Value JSON stringify | 47.90 | — | — | 638.50 (13.33x) | 159.47 (3.33x) |
| NegativeInt32Value JSON parse | 117.65 | — | — | 1191.65 (10.13x) | 338.01 (2.87x) |
| MinInt32Value JSON stringify | 48.20 | — | — | 637.44 (13.22x) | 128.13 (2.66x) |
| MinInt32Value JSON parse | 123.63 | — | — | 1206.79 (9.76x) | 361.25 (2.92x) |
| MaxInt32Value JSON stringify | 47.80 | — | — | 631.13 (13.20x) | 130.00 (2.72x) |
| MaxInt32Value JSON parse | 123.95 | — | — | 1200.12 (9.68x) | 338.32 (2.73x) |
| UInt32Value JSON stringify | 47.62 | — | — | 635.56 (13.35x) | 158.36 (3.33x) |
| UInt32Value JSON parse | 117.09 | — | — | 1185.73 (10.13x) | 324.01 (2.77x) |
| UInt32Value String JSON parse | 115.43 | — | — | 1129.28 (9.78x) | 395.40 (3.43x) |
| ZeroUInt32Value JSON stringify | 47.28 | — | — | 620.01 (13.11x) | 127.73 (2.70x) |
| ZeroUInt32Value JSON parse | 113.52 | — | — | 1154.99 (10.17x) | 273.21 (2.41x) |
| MaxUInt32Value JSON stringify | 47.92 | — | — | 633.01 (13.21x) | 143.01 (2.98x) |
| MaxUInt32Value JSON parse | 123.44 | — | — | 1210.44 (9.81x) | 337.29 (2.73x) |
| BoolValue JSON stringify | 45.31 | — | — | 622.88 (13.75x) | 151.89 (3.35x) |
| BoolValue JSON parse | 61.45 | — | — | 1057.32 (17.21x) | 200.40 (3.26x) |
| FalseBoolValue JSON stringify | 45.09 | — | — | 618.82 (13.72x) | 148.11 (3.28x) |
| FalseBoolValue JSON parse | 60.89 | — | — | 1063.95 (17.47x) | 200.28 (3.29x) |
| StringValue JSON stringify | 52.15 | — | — | 663.86 (12.73x) | 190.98 (3.66x) |
| StringValue JSON parse | 120.42 | — | — | 1150.76 (9.56x) | 294.26 (2.44x) |
| StringValue Escape JSON parse | 130.03 | — | — | 1179.80 (9.07x) | 366.54 (2.82x) |
| EmptyStringValue JSON stringify | 48.67 | — | — | 626.99 (12.88x) | 169.25 (3.48x) |
| EmptyStringValue JSON parse | 65.93 | — | — | 1116.15 (16.93x) | 240.29 (3.64x) |
| BytesValue JSON stringify | 49.18 | — | — | 665.84 (13.54x) | 232.33 (4.72x) |
| BytesValue JSON parse | 124.26 | — | — | 1171.02 (9.42x) | 334.02 (2.69x) |
| BytesValue URL JSON parse | 141.88 | — | — | 1160.01 (8.18x) | 333.36 (2.35x) |
| EmptyBytesValue JSON stringify | 40.89 | — | — | 645.35 (15.78x) | 204.53 (5.00x) |
| EmptyBytesValue JSON parse | 68.20 | — | — | 1131.36 (16.59x) | 289.90 (4.25x) |
| TextFormat format | 183.09 | — | — | 2561.08 (13.99x) | 2497.19 (13.64x) |
| TextFormat parse | 703.36 | — | — | 4995.39 (7.10x) | 6540.29 (9.30x) |
| packed fixed32 encode | 2.01 | 562.57 (279.89x) | 539.55 (268.43x) | 43.41 (21.60x) | 433.50 (215.67x) |
| packed fixed32 decode | 4.51 | 1081.60 (239.82x) | 1953.04 (433.05x) | 50.92 (11.29x) | 2338.72 (518.56x) |
| packed fixed64 encode | 2.01 | 575.34 (286.24x) | 563.27 (280.23x) | 76.54 (38.08x) | 607.33 (302.15x) |
| packed fixed64 decode | 4.53 | 1207.96 (266.66x) | 7958.40 (1756.82x) | 81.07 (17.90x) | 2801.63 (618.46x) |
| packed sfixed32 encode | 2.01 | 561.22 (279.21x) | 539.97 (268.64x) | 44.43 (22.11x) | 407.69 (202.83x) |
| packed sfixed32 decode | 4.53 | 1102.54 (243.39x) | 1960.71 (432.83x) | 48.69 (10.75x) | 1744.87 (385.18x) |
| packed sfixed64 encode | 2.01 | 570.01 (283.59x) | 561.33 (279.27x) | 75.72 (37.67x) | 412.18 (205.06x) |
| packed sfixed64 decode | 4.53 | 1148.38 (253.51x) | 7904.07 (1744.83x) | 70.89 (15.65x) | 2470.44 (545.35x) |
| packed float encode | 2.06 | 817.59 (396.89x) | 539.80 (262.04x) | 43.83 (21.28x) | 473.22 (229.72x) |
| packed float decode | 4.65 | 1079.39 (232.13x) | 2052.82 (441.47x) | 48.35 (10.40x) | 1879.60 (404.22x) |
| packed double encode | 2.01 | 831.48 (413.67x) | 561.40 (279.30x) | 75.70 (37.66x) | 356.04 (177.13x) |
| packed double decode | 4.53 | 1109.57 (244.94x) | 2051.35 (452.84x) | 79.08 (17.46x) | 2695.24 (594.98x) |
| packed uint64 encode | 1291.09 | 4616.71 (3.58x) | 4058.43 (3.14x) | 2122.26 (1.64x) | 3470.71 (2.69x) |
| packed uint64 decode | 1779.95 | 2889.20 (1.62x) | 8857.01 (4.98x) | 2800.61 (1.57x) | 8691.88 (4.88x) |
| packed uint32 encode | 925.77 | 3628.00 (3.92x) | 3262.75 (3.52x) | 1730.13 (1.87x) | 2899.95 (3.13x) |
| packed uint32 decode | 1317.70 | 2478.04 (1.88x) | 3267.21 (2.48x) | 2001.00 (1.52x) | 6430.51 (4.88x) |
| packed int64 encode | 1398.95 | 10934.14 (7.82x) | 6078.55 (4.35x) | 2897.64 (2.07x) | 4262.91 (3.05x) |
| packed int64 decode | 2756.10 | 3857.68 (1.40x) | 10278.08 (3.73x) | 4724.40 (1.71x) | 10736.39 (3.90x) |
| packed sint32 encode | 864.11 | 3053.62 (3.53x) | 2862.22 (3.31x) | 1531.54 (1.77x) | 3382.64 (3.91x) |
| packed sint32 decode | 953.95 | 2572.33 (2.70x) | 3188.39 (3.34x) | 1127.95 (1.18x) | 3637.95 (3.81x) |
| packed sint64 encode | 1434.92 | 4939.43 (3.44x) | 4317.50 (3.01x) | 2387.05 (1.66x) | 4127.53 (2.88x) |
| packed sint64 decode | 2039.53 | 3171.80 (1.56x) | 9675.50 (4.74x) | 2932.02 (1.44x) | 7723.14 (3.79x) |
| packed bool encode | 2.01 | 1360.80 (677.01x) | 519.26 (258.34x) | 15.90 (7.91x) | 2222.37 (1105.66x) |
| packed bool decode | 263.14 | 1560.36 (5.93x) | 2549.46 (9.69x) | 804.99 (3.06x) | 1768.29 (6.72x) |
| packed enum encode | 276.17 | 2742.56 (9.93x) | 1795.86 (6.50x) | 1084.82 (3.93x) | 2522.36 (9.13x) |
| packed enum decode | 158.12 | 1536.02 (9.71x) | 2885.31 (18.25x) | 694.87 (4.39x) | 2442.06 (15.44x) |
| large map encode | 4026.59 | 16584.71 (4.12x) | 9746.41 (2.42x) | 21327.10 (5.30x) | 190979.71 (47.43x) |
| shuffled large map deterministic binary encode | 28597.68 | — | — | 90813.50 (3.18x) | 367939.50 (12.87x) |
| large map decode | 25729.85 | 90219.59 (3.51x) | 89209.79 (3.47x) | 88754.30 (3.45x) | 266600.27 (10.36x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound `Duration`, non-empty/escaped-input parse/number-exponent parse and empty `Struct`, object/escaped-object parse/object-number-exponent/list/escaped-list/string-scalar/escaped-string-scalar/number-exponent `Value` (including default-like scalar and empty object/list kinds),
`FieldMask` (non-empty, escaped JSON parse input, and empty), escaped-input parse/short-fraction parse/micro/nano/offset/min/pre/post/max-bound `Timestamp`, `Empty`, min/zero/positive/number-input parse/negative/max `Int64Value`, negative/zero/positive finite/string-input parse `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), negative/zero/positive finite/string-input parse `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), zero/normal/number-input parse/max `UInt64Value`, min/zero/positive/string-input parse/negative/max `Int32Value`, zero/normal/string-input parse/max `UInt32Value`, true/false `BoolValue`, non-empty/escape-input parse/empty `StringValue`, base64/base64url parse/empty `BytesValue`, and recursive nested `Any` payloads), direct zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound Duration, non-empty/escaped-input parse/empty FieldMask, and escaped-input parse/short-fraction parse/micro/nano/offset/min/pre/post/max-bound Timestamp WKT JSON plus other direct WKT JSON, including non-empty/escaped-input parse/number-exponent parse/empty `Struct`, object/escaped-object parse/object-number-exponent/list/escaped-list/string-scalar/escaped-string-scalar/number-exponent `Value`, and escaped/non-empty/empty `ListValue`, TextFormat, packed scalars, large bytes,
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
