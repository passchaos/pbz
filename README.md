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

Latest accepted comparison (`/tmp/pbz-compare-number-exponent-json-final.log`,
summarized in `/tmp/pbz-summary-number-exponent-json-final.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 21.56 | 99.79 (4.63x) | 51.65 (2.40x) | 105.30 (4.88x) | 797.93 (37.01x) |
| binary decode | 95.01 | 256.49 (2.70x) | 249.33 (2.62x) | 210.69 (2.22x) | 901.97 (9.49x) |
| unknown fields count by number | 3.57 | — | — | 161.57 (45.26x) | — |
| deterministic binary encode | 64.22 | — | — | 128.42 (2.00x) | 1047.04 (16.30x) |
| scalarmix encode | 19.54 | 95.51 (4.89x) | 48.82 (2.50x) | 29.32 (1.50x) | 210.47 (10.77x) |
| scalarmix decode | 34.68 | 133.71 (3.86x) | 174.11 (5.02x) | 84.63 (2.44x) | 287.76 (8.30x) |
| textbytes encode | 9.52 | 78.72 (8.27x) | 33.35 (3.50x) | 122.16 (12.83x) | 149.16 (15.67x) |
| textbytes decode | 45.58 | 471.31 (10.34x) | 239.16 (5.25x) | 169.02 (3.71x) | 694.92 (15.25x) |
| largebytes encode | 32.97 | 2718.50 (82.45x) | 2684.23 (81.41x) | 2691.15 (81.62x) | 2709.57 (82.18x) |
| largebytes decode | 109.88 | 5476.37 (49.84x) | 3133.17 (28.51x) | 2785.24 (25.35x) | 24596.50 (223.85x) |
| presencemix encode | 18.79 | 55.83 (2.97x) | 29.45 (1.57x) | 57.93 (3.08x) | 232.15 (12.35x) |
| presencemix decode | 55.88 | 133.47 (2.39x) | 108.74 (1.95x) | 163.31 (2.92x) | 496.20 (8.88x) |
| complex encode | 52.67 | 133.61 (2.54x) | 96.22 (1.83x) | 167.09 (3.17x) | 959.51 (18.22x) |
| complex decode | 170.00 | 395.65 (2.33x) | 339.77 (2.00x) | 397.40 (2.34x) | 1386.86 (8.16x) |
| complex deterministic binary encode | 103.18 | — | — | 177.97 (1.72x) | 1125.59 (10.91x) |
| complex JSON stringify | 287.62 | — | — | 4880.10 (16.97x) | 5945.12 (20.67x) |
| complex JSON parse | 2391.70 | — | — | 11921.80 (4.98x) | 7325.46 (3.06x) |
| complex TextFormat format | 415.88 | — | — | 3778.75 (9.09x) | 5109.40 (12.29x) |
| complex TextFormat parse | 1883.58 | — | — | 6949.94 (3.69x) | 8108.35 (4.30x) |
| packed int32 encode | 661.39 | 3155.65 (4.77x) | 2506.73 (3.79x) | 1222.81 (1.85x) | 3232.01 (4.89x) |
| packed int32 decode | 687.45 | 1907.90 (2.78x) | 3183.17 (4.63x) | 971.56 (1.41x) | 4010.39 (5.83x) |
| JSON stringify | 164.11 | — | — | 3004.45 (18.31x) | 1983.32 (12.09x) |
| JSON parse | 1532.76 | — | — | 7517.58 (4.90x) | 4424.16 (2.89x) |
| Any WKT JSON stringify | 137.76 | — | — | 1885.53 (13.69x) | 994.59 (7.22x) |
| Any WKT JSON parse | 527.82 | — | — | 2981.76 (5.65x) | 1441.59 (2.73x) |
| Any Duration Escape WKT JSON parse | 541.59 | — | — | 3027.63 (5.59x) | 1505.89 (2.78x) |
| Any PlusDuration WKT JSON parse | 526.69 | — | — | 2998.88 (5.69x) | 1607.40 (3.05x) |
| Any ShortFractionDuration WKT JSON parse | 523.57 | — | — | 2962.36 (5.66x) | 1513.46 (2.89x) |
| Any MicroDuration WKT JSON stringify | 143.97 | — | — | 1906.03 (13.24x) | 945.19 (6.57x) |
| Any MicroDuration WKT JSON parse | 527.30 | — | — | 3018.76 (5.72x) | 1493.00 (2.83x) |
| Any NanoDuration WKT JSON stringify | 135.31 | — | — | 1926.55 (14.24x) | 1012.38 (7.48x) |
| Any NanoDuration WKT JSON parse | 529.51 | — | — | 3016.68 (5.70x) | 1458.89 (2.76x) |
| Any NegativeDuration WKT JSON stringify | 141.37 | — | — | 1942.07 (13.74x) | 995.75 (7.04x) |
| Any NegativeDuration WKT JSON parse | 530.27 | — | — | 3112.21 (5.87x) | 1542.81 (2.91x) |
| Any FractionalNegativeDuration WKT JSON stringify | 132.33 | — | — | 1891.46 (14.29x) | 981.27 (7.42x) |
| Any FractionalNegativeDuration WKT JSON parse | 518.69 | — | — | 3078.23 (5.93x) | 1408.90 (2.72x) |
| Any MaxDuration WKT JSON stringify | 124.58 | — | — | 1748.70 (14.04x) | 953.88 (7.66x) |
| Any MaxDuration WKT JSON parse | 542.97 | — | — | 2971.90 (5.47x) | 1541.13 (2.84x) |
| Any MinDuration WKT JSON stringify | 123.05 | — | — | 1889.00 (15.35x) | 1053.18 (8.56x) |
| Any MinDuration WKT JSON parse | 545.23 | — | — | 3016.99 (5.53x) | 1582.49 (2.90x) |
| Any ZeroDuration WKT JSON stringify | 112.04 | — | — | 916.66 (8.18x) | 940.13 (8.39x) |
| Any ZeroDuration WKT JSON parse | 471.36 | — | — | 2250.71 (4.77x) | 1451.94 (3.08x) |
| Any FieldMask WKT JSON stringify | 226.30 | — | — | 1744.28 (7.71x) | 1389.72 (6.14x) |
| Any FieldMask WKT JSON parse | 723.45 | — | — | 3150.30 (4.35x) | 2124.47 (2.94x) |
| Any FieldMask Escape WKT JSON parse | 736.33 | — | — | 3237.36 (4.40x) | 2480.09 (3.37x) |
| Any EmptyFieldMask WKT JSON stringify | 120.48 | — | — | 915.25 (7.60x) | 782.99 (6.50x) |
| Any EmptyFieldMask WKT JSON parse | 443.26 | — | — | 2164.78 (4.88x) | 1342.10 (3.03x) |
| Any Timestamp WKT JSON stringify | 176.84 | — | — | 2035.81 (11.51x) | 1084.01 (6.13x) |
| Any Timestamp WKT JSON parse | 567.83 | — | — | 3046.05 (5.36x) | 1620.34 (2.85x) |
| Any Timestamp Escape WKT JSON parse | 585.84 | — | — | 3087.43 (5.27x) | 1703.40 (2.91x) |
| Any ShortFraction Timestamp WKT JSON parse | 563.66 | — | — | 3038.71 (5.39x) | 1545.91 (2.74x) |
| Any Micro Timestamp WKT JSON stringify | 177.75 | — | — | 2038.61 (11.47x) | 1079.57 (6.07x) |
| Any Micro Timestamp WKT JSON parse | 571.77 | — | — | 3050.39 (5.33x) | 1880.28 (3.29x) |
| Any Nano Timestamp WKT JSON stringify | 176.44 | — | — | 2039.64 (11.56x) | 1061.30 (6.02x) |
| Any Nano Timestamp WKT JSON parse | 576.15 | — | — | 3074.04 (5.34x) | 1689.06 (2.93x) |
| Any Offset Timestamp WKT JSON parse | 584.45 | — | — | 3070.56 (5.25x) | 1836.94 (3.14x) |
| Any PreEpoch Timestamp WKT JSON stringify | 142.17 | — | — | 1953.84 (13.74x) | 1045.32 (7.35x) |
| Any PreEpoch Timestamp WKT JSON parse | 560.51 | — | — | 3063.32 (5.47x) | 1839.95 (3.28x) |
| Any Max Timestamp WKT JSON stringify | 163.71 | — | — | 2055.07 (12.55x) | 1076.10 (6.57x) |
| Any Max Timestamp WKT JSON parse | 579.42 | — | — | 3118.14 (5.38x) | 1596.10 (2.75x) |
| Any Min Timestamp WKT JSON stringify | 159.61 | — | — | 1947.62 (12.20x) | 1022.06 (6.40x) |
| Any Min Timestamp WKT JSON parse | 556.43 | — | — | 3060.21 (5.50x) | 1579.21 (2.84x) |
| Any Empty WKT JSON stringify | 93.15 | — | — | 912.26 (9.79x) | 631.95 (6.78x) |
| Any Empty WKT JSON parse | 339.46 | — | — | 2134.10 (6.29x) | 1247.90 (3.68x) |
| Any Struct WKT JSON stringify | 637.79 | — | — | 5803.09 (9.10x) | 6560.71 (10.29x) |
| Any Struct WKT JSON parse | 1734.39 | — | — | 11138.50 (6.42x) | 8684.14 (5.01x) |
| Any Struct Escape WKT JSON parse | 1775.77 | — | — | 11246.20 (6.33x) | 9055.97 (5.10x) |
| Any EmptyStruct WKT JSON stringify | 121.99 | — | — | 915.25 (7.50x) | 919.52 (7.54x) |
| Any EmptyStruct WKT JSON parse | 439.74 | — | — | 2231.16 (5.07x) | 1496.43 (3.40x) |
| Any Value WKT JSON stringify | 670.17 | — | — | 5919.42 (8.83x) | 6589.97 (9.83x) |
| Any Value WKT JSON parse | 1799.25 | — | — | 11422.80 (6.35x) | 8653.16 (4.81x) |
| Any Value Escape WKT JSON parse | 1831.49 | — | — | 11499.50 (6.28x) | 9251.92 (5.05x) |
| Any NullValue WKT JSON stringify | 139.01 | — | — | 2262.94 (16.28x) | 887.87 (6.39x) |
| Any NullValue WKT JSON parse | 461.89 | — | — | 4076.15 (8.82x) | 1473.52 (3.19x) |
| Any StringScalarValue WKT JSON stringify | 161.85 | — | — | 2289.14 (14.14x) | 1127.74 (6.97x) |
| Any StringScalarValue WKT JSON parse | 523.27 | — | — | 3652.41 (6.98x) | 1598.98 (3.06x) |
| Any StringScalarValue Escape WKT JSON parse | 533.46 | — | — | 3691.58 (6.92x) | 1839.61 (3.45x) |
| Any EmptyStringScalarValue WKT JSON stringify | 148.31 | — | — | 2295.40 (15.48x) | 932.54 (6.29x) |
| Any EmptyStringScalarValue WKT JSON parse | 491.12 | — | — | 3620.27 (7.37x) | 1476.30 (3.01x) |
| Any NumberValue WKT JSON stringify | 181.86 | — | — | 2521.20 (13.86x) | 1038.76 (5.71x) |
| Any NumberValue WKT JSON parse | 501.49 | — | — | 3719.87 (7.42x) | 1758.61 (3.51x) |
| Any NumberValue Exponent WKT JSON parse | 503.80 | — | — | 3721.26 (7.39x) | 1582.96 (3.14x) |
| Any ZeroNumberValue WKT JSON stringify | 147.05 | — | — | 2484.21 (16.89x) | 1000.52 (6.80x) |
| Any ZeroNumberValue WKT JSON parse | 501.70 | — | — | 3652.74 (7.28x) | 1515.51 (3.02x) |
| Any BoolScalarValue WKT JSON stringify | 135.13 | — | — | 2271.37 (16.81x) | 1033.79 (7.65x) |
| Any BoolScalarValue WKT JSON parse | 466.70 | — | — | 3612.27 (7.74x) | 1654.90 (3.55x) |
| Any FalseBoolScalarValue WKT JSON stringify | 136.05 | — | — | 2281.57 (16.77x) | 1008.00 (7.41x) |
| Any FalseBoolScalarValue WKT JSON parse | 466.66 | — | — | 3626.21 (7.77x) | 1522.00 (3.26x) |
| Any ListKindValue WKT JSON stringify | 505.65 | — | — | 5637.91 (11.15x) | 4763.77 (9.42x) |
| Any ListKindValue WKT JSON parse | 1389.01 | — | — | 9917.44 (7.14x) | 7070.70 (5.09x) |
| Any ListKindValue Escape WKT JSON parse | 1414.94 | — | — | 10019.50 (7.08x) | 7185.08 (5.08x) |
| Any EmptyStructKindValue WKT JSON stringify | 145.10 | — | — | 2921.96 (20.14x) | 1347.75 (9.29x) |
| Any EmptyStructKindValue WKT JSON parse | 493.71 | — | — | 5413.62 (10.97x) | 1817.92 (3.68x) |
| Any EmptyListKindValue WKT JSON stringify | 146.57 | — | — | 2895.53 (19.76x) | 1045.21 (7.13x) |
| Any EmptyListKindValue WKT JSON parse | 502.37 | — | — | 4394.37 (8.75x) | 1701.30 (3.39x) |
| Any DoubleValue WKT JSON stringify | 191.28 | — | — | 1804.91 (9.44x) | 770.55 (4.03x) |
| Any DoubleValue WKT JSON parse | 521.43 | — | — | 2755.70 (5.28x) | 1519.65 (2.91x) |
| Any DoubleValue String WKT JSON parse | 533.82 | — | — | 2742.23 (5.14x) | 1789.85 (3.35x) |
| Any NegativeDoubleValue WKT JSON stringify | 193.04 | — | — | 1809.86 (9.38x) | 2870.46 (14.87x) |
| Any NegativeDoubleValue WKT JSON parse | 522.96 | — | — | 2756.59 (5.27x) | 4473.23 (8.55x) |
| Any ZeroDoubleValue WKT JSON stringify | 163.16 | — | — | 915.18 (5.61x) | 1806.54 (11.07x) |
| Any ZeroDoubleValue WKT JSON parse | 517.03 | — | — | 2184.40 (4.22x) | 3593.32 (6.95x) |
| Any DoubleValue NaN WKT JSON stringify | 160.00 | — | — | 1570.76 (9.82x) | 1951.67 (12.20x) |
| Any DoubleValue NaN WKT JSON parse | 514.95 | — | — | 2659.97 (5.17x) | 3422.48 (6.65x) |
| Any DoubleValue Infinity WKT JSON stringify | 162.52 | — | — | 1567.35 (9.64x) | 2389.49 (14.70x) |
| Any DoubleValue Infinity WKT JSON parse | 519.86 | — | — | 2708.44 (5.21x) | 2730.41 (5.25x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 168.60 | — | — | 1565.16 (9.28x) | 1077.51 (6.39x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 523.08 | — | — | 2693.74 (5.15x) | 1607.24 (3.07x) |
| Any FloatValue WKT JSON stringify | 205.34 | — | — | 1747.61 (8.51x) | 781.27 (3.80x) |
| Any FloatValue WKT JSON parse | 520.28 | — | — | 2709.04 (5.21x) | 1325.04 (2.55x) |
| Any FloatValue String WKT JSON parse | 531.34 | — | — | 2707.37 (5.10x) | 1409.96 (2.65x) |
| Any NegativeFloatValue WKT JSON stringify | 199.62 | — | — | 1743.22 (8.73x) | 748.21 (3.75x) |
| Any NegativeFloatValue WKT JSON parse | 519.57 | — | — | 2723.30 (5.24x) | 1351.58 (2.60x) |
| Any ZeroFloatValue WKT JSON stringify | 164.76 | — | — | 916.34 (5.56x) | 731.67 (4.44x) |
| Any ZeroFloatValue WKT JSON parse | 517.26 | — | — | 2163.16 (4.18x) | 1315.85 (2.54x) |
| Any FloatValue NaN WKT JSON stringify | 163.66 | — | — | 1558.49 (9.52x) | 692.36 (4.23x) |
| Any FloatValue NaN WKT JSON parse | 514.78 | — | — | 2627.01 (5.10x) | 1380.03 (2.68x) |
| Any FloatValue Infinity WKT JSON stringify | 168.58 | — | — | 1549.65 (9.19x) | 695.52 (4.13x) |
| Any FloatValue Infinity WKT JSON parse | 519.28 | — | — | 2660.09 (5.12x) | 1329.96 (2.56x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 175.07 | — | — | 1552.07 (8.87x) | 742.84 (4.24x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 522.03 | — | — | 2670.64 (5.12x) | 1396.17 (2.67x) |
| Any Int64Value WKT JSON stringify | 171.25 | — | — | 1565.62 (9.14x) | 863.78 (5.04x) |
| Any Int64Value WKT JSON parse | 556.60 | — | — | 2784.81 (5.00x) | 1599.84 (2.87x) |
| Any Int64Value Number WKT JSON parse | 554.01 | — | — | 2759.09 (4.98x) | 1542.92 (2.79x) |
| Any ZeroInt64Value WKT JSON stringify | 166.33 | — | — | 971.42 (5.84x) | 893.32 (5.37x) |
| Any ZeroInt64Value WKT JSON parse | 523.30 | — | — | 2153.74 (4.12x) | 1582.24 (3.02x) |
| Any NegativeInt64Value WKT JSON stringify | 175.09 | — | — | 1570.41 (8.97x) | 1052.23 (6.01x) |
| Any NegativeInt64Value WKT JSON parse | 556.45 | — | — | 2818.30 (5.06x) | 1813.62 (3.26x) |
| Any MinInt64Value WKT JSON stringify | 175.27 | — | — | 1564.19 (8.92x) | 1408.05 (8.03x) |
| Any MinInt64Value WKT JSON parse | 563.03 | — | — | 2823.13 (5.01x) | 1857.58 (3.30x) |
| Any MaxInt64Value WKT JSON stringify | 183.54 | — | — | 1559.16 (8.49x) | 873.87 (4.76x) |
| Any MaxInt64Value WKT JSON parse | 563.57 | — | — | 2814.24 (4.99x) | 1730.95 (3.07x) |
| Any UInt64Value WKT JSON stringify | 177.48 | — | — | 1568.33 (8.84x) | 925.92 (5.22x) |
| Any UInt64Value WKT JSON parse | 562.72 | — | — | 2803.20 (4.98x) | 1691.59 (3.01x) |
| Any UInt64Value Number WKT JSON parse | 564.26 | — | — | 2773.19 (4.91x) | 1510.02 (2.68x) |
| Any ZeroUInt64Value WKT JSON stringify | 170.55 | — | — | 930.96 (5.46x) | 823.17 (4.83x) |
| Any ZeroUInt64Value WKT JSON parse | 533.73 | — | — | 2170.23 (4.07x) | 1375.12 (2.58x) |
| Any MaxUInt64Value WKT JSON stringify | 180.65 | — | — | 1564.37 (8.66x) | 906.56 (5.02x) |
| Any MaxUInt64Value WKT JSON parse | 572.20 | — | — | 2848.60 (4.98x) | 1792.47 (3.13x) |
| Any Int32Value WKT JSON stringify | 171.69 | — | — | 1544.95 (9.00x) | 832.06 (4.85x) |
| Any Int32Value WKT JSON parse | 531.11 | — | — | 2666.02 (5.02x) | 1594.88 (3.00x) |
| Any Int32Value String WKT JSON parse | 538.36 | — | — | 2668.60 (4.96x) | 1492.83 (2.77x) |
| Any ZeroInt32Value WKT JSON stringify | 176.69 | — | — | 913.86 (5.17x) | 763.22 (4.32x) |
| Any ZeroInt32Value WKT JSON parse | 524.84 | — | — | 2148.97 (4.09x) | 1440.14 (2.74x) |
| Any NegativeInt32Value WKT JSON stringify | 177.02 | — | — | 1552.44 (8.77x) | 804.53 (4.54x) |
| Any NegativeInt32Value WKT JSON parse | 532.56 | — | — | 2710.31 (5.09x) | 1625.32 (3.05x) |
| Any MinInt32Value WKT JSON stringify | 173.81 | — | — | 1562.11 (8.99x) | 866.44 (4.98x) |
| Any MinInt32Value WKT JSON parse | 541.01 | — | — | 2738.56 (5.06x) | 2297.08 (4.25x) |
| Any MaxInt32Value WKT JSON stringify | 177.18 | — | — | 1553.94 (8.77x) | 866.42 (4.89x) |
| Any MaxInt32Value WKT JSON parse | 538.59 | — | — | 2704.62 (5.02x) | 1750.85 (3.25x) |
| Any UInt32Value WKT JSON stringify | 187.05 | — | — | 1554.66 (8.31x) | 1099.00 (5.88x) |
| Any UInt32Value WKT JSON parse | 533.45 | — | — | 2673.98 (5.01x) | 1575.54 (2.95x) |
| Any UInt32Value String WKT JSON parse | 544.30 | — | — | 2710.47 (4.98x) | 1530.25 (2.81x) |
| Any ZeroUInt32Value WKT JSON stringify | 195.72 | — | — | 915.52 (4.68x) | 737.49 (3.77x) |
| Any ZeroUInt32Value WKT JSON parse | 528.14 | — | — | 2202.05 (4.17x) | 1445.99 (2.74x) |
| Any MaxUInt32Value WKT JSON stringify | 186.90 | — | — | 1555.32 (8.32x) | 739.36 (3.96x) |
| Any MaxUInt32Value WKT JSON parse | 542.92 | — | — | 2699.36 (4.97x) | 1611.01 (2.97x) |
| Any BoolValue WKT JSON stringify | 173.05 | — | — | 1523.97 (8.81x) | 730.63 (4.22x) |
| Any BoolValue WKT JSON parse | 486.07 | — | — | 2618.01 (5.39x) | 1363.11 (2.80x) |
| Any FalseBoolValue WKT JSON stringify | 177.21 | — | — | 913.93 (5.16x) | 709.63 (4.00x) |
| Any FalseBoolValue WKT JSON parse | 486.36 | — | — | 2155.85 (4.43x) | 1370.76 (2.82x) |
| Any StringValue WKT JSON stringify | 200.44 | — | — | 1567.53 (7.82x) | 784.15 (3.91x) |
| Any StringValue WKT JSON parse | 548.74 | — | — | 2659.25 (4.85x) | 1480.47 (2.70x) |
| Any StringValue Escape WKT JSON parse | 553.58 | — | — | 2697.95 (4.87x) | 1659.57 (3.00x) |
| Any EmptyStringValue WKT JSON stringify | 193.09 | — | — | 918.00 (4.75x) | 817.03 (4.23x) |
| Any EmptyStringValue WKT JSON parse | 520.01 | — | — | 2181.70 (4.20x) | 1394.78 (2.68x) |
| Any BytesValue WKT JSON stringify | 189.97 | — | — | 1587.72 (8.36x) | 842.43 (4.43x) |
| Any BytesValue WKT JSON parse | 560.45 | — | — | 2696.58 (4.81x) | 1580.99 (2.82x) |
| Any BytesValue URL WKT JSON parse | 575.89 | — | — | 2692.75 (4.68x) | 1649.76 (2.86x) |
| Any EmptyBytesValue WKT JSON stringify | 183.80 | — | — | 922.42 (5.02x) | 737.48 (4.01x) |
| Any EmptyBytesValue WKT JSON parse | 524.18 | — | — | 2176.62 (4.15x) | 1469.43 (2.80x) |
| Nested Any WKT JSON stringify | 310.28 | — | — | 2488.02 (8.02x) | 1463.36 (4.72x) |
| Nested Any WKT JSON parse | 859.73 | — | — | 4294.29 (4.99x) | 2727.60 (3.17x) |
| Duration JSON stringify | 57.74 | — | — | 962.31 (16.67x) | 338.22 (5.86x) |
| Duration JSON parse | 20.63 | — | — | 1451.88 (70.38x) | 373.44 (18.10x) |
| Duration Escape JSON parse | 41.25 | — | — | 1500.90 (36.39x) | 446.25 (10.82x) |
| PlusDuration JSON parse | 20.84 | — | — | 1462.94 (70.20x) | 394.38 (18.92x) |
| ShortFractionDuration JSON parse | 18.05 | — | — | 1420.09 (78.68x) | 358.86 (19.88x) |
| MicroDuration JSON stringify | 59.79 | — | — | 967.51 (16.18x) | 391.72 (6.55x) |
| MicroDuration JSON parse | 21.33 | — | — | 1460.71 (68.48x) | 394.42 (18.49x) |
| NanoDuration JSON stringify | 57.22 | — | — | 996.08 (17.41x) | 386.80 (6.76x) |
| NanoDuration JSON parse | 26.19 | — | — | 1627.61 (62.15x) | 370.19 (14.13x) |
| NegativeDuration JSON stringify | 58.79 | — | — | 1014.68 (17.26x) | 409.81 (6.97x) |
| NegativeDuration JSON parse | 20.79 | — | — | 1556.04 (74.85x) | 382.10 (18.38x) |
| FractionalNegativeDuration JSON stringify | 58.60 | — | — | 975.49 (16.65x) | 408.42 (6.97x) |
| FractionalNegativeDuration JSON parse | 21.89 | — | — | 1460.53 (66.72x) | 367.84 (16.80x) |
| MaxDuration JSON stringify | 49.80 | — | — | 858.55 (17.24x) | 418.37 (8.40x) |
| MaxDuration JSON parse | 33.41 | — | — | 1439.13 (43.07x) | 391.72 (11.72x) |
| MinDuration JSON stringify | 50.03 | — | — | 870.97 (17.41x) | 440.77 (8.81x) |
| MinDuration JSON parse | 37.16 | — | — | 1450.79 (39.04x) | 386.95 (10.41x) |
| ZeroDuration JSON stringify | 44.97 | — | — | 816.33 (18.15x) | 356.49 (7.93x) |
| ZeroDuration JSON parse | 15.93 | — | — | 1363.76 (85.61x) | 297.88 (18.70x) |
| FieldMask JSON stringify | 110.47 | — | — | 881.43 (7.98x) | 627.84 (5.68x) |
| FieldMask JSON parse | 142.29 | — | — | 1647.99 (11.58x) | 878.89 (6.18x) |
| FieldMask Escape JSON parse | 188.27 | — | — | 1708.62 (9.08x) | 1033.00 (5.49x) |
| EmptyFieldMask JSON stringify | 40.75 | — | — | 614.51 (15.08x) | 218.57 (5.36x) |
| EmptyFieldMask JSON parse | 4.78 | — | — | 942.34 (197.14x) | 191.26 (40.01x) |
| Timestamp JSON stringify | 96.35 | — | — | 1139.96 (11.83x) | 406.38 (4.22x) |
| Timestamp JSON parse | 45.78 | — | — | 1493.46 (32.62x) | 419.69 (9.17x) |
| Timestamp Escape JSON parse | 98.06 | — | — | 1531.40 (15.62x) | 520.36 (5.31x) |
| ShortFraction Timestamp JSON parse | 43.65 | — | — | 1486.31 (34.05x) | 430.88 (9.87x) |
| Micro Timestamp JSON stringify | 96.34 | — | — | 1163.97 (12.08x) | 461.43 (4.79x) |
| Micro Timestamp JSON parse | 48.79 | — | — | 1509.74 (30.94x) | 446.42 (9.15x) |
| Nano Timestamp JSON stringify | 94.28 | — | — | 1183.75 (12.56x) | 444.94 (4.72x) |
| Nano Timestamp JSON parse | 50.46 | — | — | 1555.96 (30.84x) | 458.69 (9.09x) |
| Offset Timestamp JSON parse | 51.08 | — | — | 1583.15 (30.99x) | 479.65 (9.39x) |
| PreEpoch Timestamp JSON stringify | 66.25 | — | — | 1071.62 (16.18x) | 434.48 (6.56x) |
| PreEpoch Timestamp JSON parse | 43.31 | — | — | 1490.84 (34.42x) | 423.04 (9.77x) |
| Max Timestamp JSON stringify | 78.52 | — | — | 1217.94 (15.51x) | 420.20 (5.35x) |
| Max Timestamp JSON parse | 55.60 | — | — | 1536.71 (27.64x) | 439.48 (7.90x) |
| Min Timestamp JSON stringify | 81.53 | — | — | 1056.62 (12.96x) | 414.16 (5.08x) |
| Min Timestamp JSON parse | 41.16 | — | — | 1453.41 (35.31x) | 414.40 (10.07x) |
| Empty JSON stringify | 20.63 | — | — | 497.70 (24.12x) | 95.88 (4.65x) |
| Empty JSON parse | 67.71 | — | — | 719.93 (10.63x) | 196.62 (2.90x) |
| Struct JSON stringify | 184.27 | — | — | 5737.79 (31.14x) | 2999.58 (16.28x) |
| Struct JSON parse | 856.87 | — | — | 10957.40 (12.79x) | 4715.85 (5.50x) |
| Struct Escape JSON parse | 897.96 | — | — | 10992.70 (12.24x) | 4923.36 (5.48x) |
| EmptyStruct JSON stringify | 41.10 | — | — | 703.26 (17.11x) | 380.62 (9.26x) |
| EmptyStruct JSON parse | 87.63 | — | — | 2025.95 (23.12x) | 365.28 (4.17x) |
| Value JSON stringify | 183.50 | — | — | 6583.94 (35.88x) | 3124.51 (17.03x) |
| Value JSON parse | 865.23 | — | — | 12194.20 (14.09x) | 4919.19 (5.69x) |
| Value Escape JSON parse | 916.56 | — | — | 12283.80 (13.40x) | 5507.26 (6.01x) |
| NullValue JSON stringify | 40.36 | — | — | 1325.32 (32.84x) | 226.67 (5.62x) |
| NullValue JSON parse | 69.79 | — | — | 2481.90 (35.56x) | 320.20 (4.59x) |
| StringScalarValue JSON stringify | 47.63 | — | — | 1348.26 (28.31x) | 273.16 (5.74x) |
| StringScalarValue JSON parse | 140.95 | — | — | 2092.16 (14.84x) | 427.49 (3.03x) |
| StringScalarValue Escape JSON parse | 153.00 | — | — | 2128.67 (13.91x) | 476.02 (3.11x) |
| EmptyStringScalarValue JSON stringify | 45.96 | — | — | 1340.99 (29.18x) | 268.93 (5.85x) |
| EmptyStringScalarValue JSON parse | 87.22 | — | — | 2070.31 (23.74x) | 343.71 (3.94x) |
| NumberValue JSON stringify | 73.65 | — | — | 1558.16 (21.16x) | 342.63 (4.65x) |
| NumberValue JSON parse | 133.08 | — | — | 2172.37 (16.32x) | 391.12 (2.94x) |
| NumberValue Exponent JSON parse | 134.72 | — | — | 2207.80 (16.39x) | 398.26 (2.96x) |
| ZeroNumberValue JSON stringify | 52.37 | — | — | 1512.23 (28.88x) | 295.93 (5.65x) |
| ZeroNumberValue JSON parse | 133.56 | — | — | 2110.28 (15.80x) | 386.66 (2.90x) |
| BoolScalarValue JSON stringify | 40.52 | — | — | 1319.99 (32.58x) | 226.85 (5.60x) |
| BoolScalarValue JSON parse | 69.68 | — | — | 2021.32 (29.01x) | 328.90 (4.72x) |
| FalseBoolScalarValue JSON stringify | 40.52 | — | — | 1319.12 (32.55x) | 237.00 (5.85x) |
| FalseBoolScalarValue JSON parse | 77.22 | — | — | 2021.91 (26.18x) | 332.33 (4.30x) |
| ListKindValue JSON stringify | 141.52 | — | — | 6158.50 (43.52x) | 2303.96 (16.28x) |
| ListKindValue JSON parse | 671.38 | — | — | 10398.10 (15.49x) | 4475.49 (6.67x) |
| ListKindValue Escape JSON parse | 695.23 | — | — | 10600.70 (15.25x) | 4465.84 (6.42x) |
| EmptyStructKindValue JSON stringify | 42.99 | — | — | 2001.96 (46.57x) | 548.81 (12.77x) |
| EmptyStructKindValue JSON parse | 110.39 | — | — | 3754.63 (34.01x) | 676.92 (6.13x) |
| EmptyListKindValue JSON stringify | 41.32 | — | — | 1945.12 (47.07x) | 380.82 (9.22x) |
| EmptyListKindValue JSON parse | 146.95 | — | — | 4034.60 (27.46x) | 610.18 (4.15x) |
| ListValue JSON stringify | 155.30 | — | — | 4748.31 (30.58x) | 2122.02 (13.66x) |
| ListValue JSON parse | 657.74 | — | — | 8596.80 (13.07x) | 4104.64 (6.24x) |
| ListValue Escape JSON parse | 681.61 | — | — | 8647.70 (12.69x) | 4179.67 (6.13x) |
| EmptyListValue JSON stringify | 40.17 | — | — | 711.62 (17.72x) | 186.36 (4.64x) |
| EmptyListValue JSON parse | 126.74 | — | — | 2274.56 (17.95x) | 308.69 (2.44x) |
| DoubleValue JSON stringify | 68.77 | — | — | 849.34 (12.35x) | 210.49 (3.06x) |
| DoubleValue JSON parse | 111.11 | — | — | 1233.33 (11.10x) | 290.08 (2.61x) |
| DoubleValue String JSON parse | 112.01 | — | — | 1169.19 (10.44x) | 358.37 (3.20x) |
| NegativeDoubleValue JSON stringify | 67.85 | — | — | 849.31 (12.52x) | 315.33 (4.65x) |
| NegativeDoubleValue JSON parse | 111.26 | — | — | 1246.84 (11.21x) | 601.40 (5.41x) |
| ZeroDoubleValue JSON stringify | 47.16 | — | — | 787.34 (16.69x) | 221.56 (4.70x) |
| ZeroDoubleValue JSON parse | 108.01 | — | — | 1171.26 (10.84x) | 857.63 (7.94x) |
| DoubleValue NaN JSON stringify | 46.39 | — | — | 655.56 (14.13x) | 201.05 (4.33x) |
| DoubleValue NaN JSON parse | 104.48 | — | — | 1088.36 (10.42x) | 637.77 (6.10x) |
| DoubleValue Infinity JSON stringify | 48.29 | — | — | 654.07 (13.54x) | 356.02 (7.37x) |
| DoubleValue Infinity JSON parse | 105.74 | — | — | 1105.18 (10.45x) | 1080.61 (10.22x) |
| DoubleValue NegativeInfinity JSON stringify | 48.28 | — | — | 654.47 (13.56x) | 200.73 (4.16x) |
| DoubleValue NegativeInfinity JSON parse | 108.15 | — | — | 1111.69 (10.28x) | 473.36 (4.38x) |
| FloatValue JSON stringify | 72.48 | — | — | 820.75 (11.32x) | 194.28 (2.68x) |
| FloatValue JSON parse | 110.35 | — | — | 1227.75 (11.13x) | 293.62 (2.66x) |
| FloatValue String JSON parse | 110.61 | — | — | 1170.41 (10.58x) | 365.02 (3.30x) |
| NegativeFloatValue JSON stringify | 71.26 | — | — | 818.55 (11.49x) | 179.00 (2.51x) |
| NegativeFloatValue JSON parse | 110.41 | — | — | 1225.82 (11.10x) | 273.95 (2.48x) |
| ZeroFloatValue JSON stringify | 47.44 | — | — | 761.79 (16.06x) | 137.53 (2.90x) |
| ZeroFloatValue JSON parse | 107.70 | — | — | 1154.01 (10.72x) | 267.77 (2.49x) |
| FloatValue NaN JSON stringify | 46.38 | — | — | 652.84 (14.08x) | 118.93 (2.56x) |
| FloatValue NaN JSON parse | 105.17 | — | — | 1084.73 (10.31x) | 258.11 (2.45x) |
| FloatValue Infinity JSON stringify | 47.90 | — | — | 653.40 (13.64x) | 149.86 (3.13x) |
| FloatValue Infinity JSON parse | 106.77 | — | — | 1097.59 (10.28x) | 261.29 (2.45x) |
| FloatValue NegativeInfinity JSON stringify | 48.33 | — | — | 649.74 (13.44x) | 139.77 (2.89x) |
| FloatValue NegativeInfinity JSON parse | 108.28 | — | — | 1098.79 (10.15x) | 282.99 (2.61x) |
| Int64Value JSON stringify | 50.20 | — | — | 697.32 (13.89x) | 250.10 (4.98x) |
| Int64Value JSON parse | 126.85 | — | — | 1240.71 (9.78x) | 467.63 (3.69x) |
| Int64Value Number JSON parse | 127.24 | — | — | 1293.60 (10.17x) | 356.09 (2.80x) |
| ZeroInt64Value JSON stringify | 41.21 | — | — | 636.19 (15.44x) | 198.85 (4.83x) |
| ZeroInt64Value JSON parse | 106.60 | — | — | 1101.41 (10.33x) | 340.30 (3.19x) |
| NegativeInt64Value JSON stringify | 49.99 | — | — | 699.23 (13.99x) | 551.34 (11.03x) |
| NegativeInt64Value JSON parse | 128.23 | — | — | 1228.70 (9.58x) | 747.55 (5.83x) |
| MinInt64Value JSON stringify | 49.33 | — | — | 698.50 (14.16x) | 323.28 (6.55x) |
| MinInt64Value JSON parse | 134.69 | — | — | 1256.47 (9.33x) | 662.27 (4.92x) |
| MaxInt64Value JSON stringify | 49.07 | — | — | 690.92 (14.08x) | 272.38 (5.55x) |
| MaxInt64Value JSON parse | 136.40 | — | — | 1259.20 (9.23x) | 485.72 (3.56x) |
| UInt64Value JSON stringify | 49.79 | — | — | 677.97 (13.62x) | 280.96 (5.64x) |
| UInt64Value JSON parse | 126.02 | — | — | 1231.63 (9.77x) | 500.75 (3.97x) |
| UInt64Value Number JSON parse | 126.78 | — | — | 1292.64 (10.20x) | 353.00 (2.78x) |
| ZeroUInt64Value JSON stringify | 41.26 | — | — | 620.84 (15.05x) | 182.51 (4.42x) |
| ZeroUInt64Value JSON parse | 105.08 | — | — | 1102.82 (10.50x) | 352.40 (3.35x) |
| MaxUInt64Value JSON stringify | 49.11 | — | — | 681.66 (13.88x) | 271.22 (5.52x) |
| MaxUInt64Value JSON parse | 142.07 | — | — | 1254.11 (8.83x) | 461.60 (3.25x) |
| Int32Value JSON stringify | 46.74 | — | — | 644.66 (13.79x) | 126.86 (2.71x) |
| Int32Value JSON parse | 116.83 | — | — | 1188.65 (10.17x) | 336.50 (2.88x) |
| Int32Value String JSON parse | 114.64 | — | — | 1134.82 (9.90x) | 401.46 (3.50x) |
| ZeroInt32Value JSON stringify | 46.89 | — | — | 631.74 (13.47x) | 158.96 (3.39x) |
| ZeroInt32Value JSON parse | 112.41 | — | — | 1152.15 (10.25x) | 250.61 (2.23x) |
| NegativeInt32Value JSON stringify | 47.83 | — | — | 655.51 (13.71x) | 134.33 (2.81x) |
| NegativeInt32Value JSON parse | 116.09 | — | — | 1198.37 (10.32x) | 324.33 (2.79x) |
| MinInt32Value JSON stringify | 47.29 | — | — | 655.58 (13.86x) | 130.35 (2.76x) |
| MinInt32Value JSON parse | 121.48 | — | — | 1220.36 (10.05x) | 471.16 (3.88x) |
| MaxInt32Value JSON stringify | 47.51 | — | — | 649.93 (13.68x) | 190.13 (4.00x) |
| MaxInt32Value JSON parse | 122.00 | — | — | 1216.48 (9.97x) | 421.76 (3.46x) |
| UInt32Value JSON stringify | 46.72 | — | — | 635.48 (13.60x) | 128.78 (2.76x) |
| UInt32Value JSON parse | 116.49 | — | — | 1191.83 (10.23x) | 343.80 (2.95x) |
| UInt32Value String JSON parse | 115.22 | — | — | 1138.31 (9.88x) | 442.41 (3.84x) |
| ZeroUInt32Value JSON stringify | 46.77 | — | — | 614.68 (13.14x) | 143.51 (3.07x) |
| ZeroUInt32Value JSON parse | 112.02 | — | — | 1160.73 (10.36x) | 256.88 (2.29x) |
| MaxUInt32Value JSON stringify | 47.70 | — | — | 632.25 (13.25x) | 162.75 (3.41x) |
| MaxUInt32Value JSON parse | 121.72 | — | — | 1205.23 (9.90x) | 330.29 (2.71x) |
| BoolValue JSON stringify | 45.02 | — | — | 623.32 (13.85x) | 117.46 (2.61x) |
| BoolValue JSON parse | 59.89 | — | — | 1059.18 (17.69x) | 310.88 (5.19x) |
| FalseBoolValue JSON stringify | 45.10 | — | — | 618.15 (13.71x) | 141.43 (3.14x) |
| FalseBoolValue JSON parse | 67.41 | — | — | 1075.63 (15.96x) | 226.37 (3.36x) |
| StringValue JSON stringify | 52.13 | — | — | 669.43 (12.84x) | 191.11 (3.67x) |
| StringValue JSON parse | 120.21 | — | — | 1158.53 (9.64x) | 332.71 (2.77x) |
| StringValue Escape JSON parse | 129.64 | — | — | 1189.69 (9.18x) | 374.44 (2.89x) |
| EmptyStringValue JSON stringify | 49.15 | — | — | 629.66 (12.81x) | 181.75 (3.70x) |
| EmptyStringValue JSON parse | 66.01 | — | — | 1126.52 (17.07x) | 245.77 (3.72x) |
| BytesValue JSON stringify | 49.03 | — | — | 676.15 (13.79x) | 213.02 (4.34x) |
| BytesValue JSON parse | 125.99 | — | — | 1180.81 (9.37x) | 339.52 (2.69x) |
| BytesValue URL JSON parse | 142.30 | — | — | 1169.08 (8.22x) | 308.89 (2.17x) |
| EmptyBytesValue JSON stringify | 40.61 | — | — | 650.72 (16.02x) | 194.96 (4.80x) |
| EmptyBytesValue JSON parse | 68.68 | — | — | 1139.76 (16.60x) | 259.95 (3.78x) |
| TextFormat format | 185.12 | — | — | 2556.84 (13.81x) | 2400.81 (12.97x) |
| TextFormat parse | 716.00 | — | — | 5003.47 (6.99x) | 6589.71 (9.20x) |
| packed fixed32 encode | 2.00 | 550.62 (275.31x) | 539.58 (269.79x) | 44.96 (22.48x) | 454.51 (227.25x) |
| packed fixed32 decode | 4.52 | 1040.54 (230.21x) | 1940.54 (429.32x) | 48.97 (10.84x) | 1719.29 (380.37x) |
| packed fixed64 encode | 2.00 | 572.46 (286.23x) | 561.48 (280.74x) | 75.94 (37.97x) | 398.55 (199.28x) |
| packed fixed64 decode | 4.51 | 1037.12 (229.96x) | 7937.96 (1760.08x) | 79.96 (17.73x) | 2611.81 (579.12x) |
| packed sfixed32 encode | 2.51 | 548.27 (218.43x) | 539.37 (214.89x) | 44.22 (17.62x) | 408.64 (162.80x) |
| packed sfixed32 decode | 7.37 | 1054.48 (143.08x) | 1973.95 (267.84x) | 48.83 (6.63x) | 1840.67 (249.75x) |
| packed sfixed64 encode | 2.01 | 580.79 (288.95x) | 561.12 (279.16x) | 76.36 (37.99x) | 409.97 (203.97x) |
| packed sfixed64 decode | 4.53 | 999.88 (220.72x) | 7899.98 (1743.92x) | 79.76 (17.61x) | 2425.00 (535.32x) |
| packed float encode | 2.01 | 810.70 (403.33x) | 539.52 (268.42x) | 58.28 (28.99x) | 364.18 (181.18x) |
| packed float decode | 4.53 | 1044.89 (230.66x) | 2080.87 (459.35x) | 43.38 (9.58x) | 1713.79 (378.32x) |
| packed double encode | 2.01 | 833.36 (414.61x) | 561.15 (279.18x) | 75.96 (37.79x) | 367.41 (182.79x) |
| packed double decode | 4.51 | 976.89 (216.61x) | 2032.07 (450.57x) | 79.79 (17.69x) | 2340.84 (519.03x) |
| packed uint64 encode | 1295.65 | 4606.62 (3.56x) | 4058.61 (3.13x) | 2140.14 (1.65x) | 3500.27 (2.70x) |
| packed uint64 decode | 1780.88 | 2779.46 (1.56x) | 8842.04 (4.96x) | 2801.26 (1.57x) | 8531.04 (4.79x) |
| packed uint32 encode | 930.32 | 3621.39 (3.89x) | 3270.62 (3.52x) | 1735.78 (1.87x) | 2969.87 (3.19x) |
| packed uint32 decode | 1324.27 | 2416.09 (1.82x) | 3260.11 (2.46x) | 1986.92 (1.50x) | 5273.11 (3.98x) |
| packed int64 encode | 1335.90 | 11040.34 (8.26x) | 6070.97 (4.54x) | 2890.13 (2.16x) | 4101.02 (3.07x) |
| packed int64 decode | 2741.22 | 3414.06 (1.25x) | 10261.12 (3.74x) | 4681.36 (1.71x) | 10348.33 (3.78x) |
| packed sint32 encode | 780.86 | 3039.77 (3.89x) | 2783.38 (3.56x) | 1518.41 (1.94x) | 3393.01 (4.35x) |
| packed sint32 decode | 935.64 | 2549.45 (2.72x) | 3152.61 (3.37x) | 1122.20 (1.20x) | 3821.87 (4.08x) |
| packed sint64 encode | 1420.25 | 4938.83 (3.48x) | 4282.90 (3.02x) | 2433.75 (1.71x) | 4864.16 (3.42x) |
| packed sint64 decode | 2037.30 | 3066.35 (1.51x) | 9639.03 (4.73x) | 2944.50 (1.45x) | 8000.88 (3.93x) |
| packed bool encode | 2.01 | 1331.82 (662.60x) | 518.34 (257.88x) | 15.60 (7.76x) | 2214.88 (1101.93x) |
| packed bool decode | 263.29 | 1540.78 (5.85x) | 2544.95 (9.67x) | 821.19 (3.12x) | 1614.90 (6.13x) |
| packed enum encode | 272.15 | 2722.53 (10.00x) | 1802.78 (6.62x) | 1083.30 (3.98x) | 2490.20 (9.15x) |
| packed enum decode | 183.59 | 1527.02 (8.32x) | 2949.53 (16.07x) | 686.27 (3.74x) | 2252.16 (12.27x) |
| large map encode | 3974.22 | 16604.81 (4.18x) | 9889.20 (2.49x) | 24385.20 (6.14x) | 193593.41 (48.71x) |
| shuffled large map deterministic binary encode | 27603.04 | — | — | 85338.50 (3.09x) | 366861.22 (13.29x) |
| large map decode | 25602.60 | 90975.09 (3.55x) | 89547.53 (3.50x) | 92598.50 (3.62x) | 272276.52 (10.63x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound `Duration`, non-empty/escaped-input parse and empty `Struct`, object/escaped-object parse/list/escaped-list/string-scalar/escaped-string-scalar/number-exponent `Value` (including default-like scalar and empty object/list kinds),
`FieldMask` (non-empty, escaped JSON parse input, and empty), escaped-input parse/short-fraction parse/micro/nano/offset/min/pre/post/max-bound `Timestamp`, `Empty`, min/zero/positive/number-input parse/negative/max `Int64Value`, negative/zero/positive finite/string-input parse `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), negative/zero/positive finite/string-input parse `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), zero/normal/number-input parse/max `UInt64Value`, min/zero/positive/string-input parse/negative/max `Int32Value`, zero/normal/string-input parse/max `UInt32Value`, true/false `BoolValue`, non-empty/escape-input parse/empty `StringValue`, base64/base64url parse/empty `BytesValue`, and recursive nested `Any` payloads), direct zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound Duration, non-empty/escaped-input parse/empty FieldMask, and escaped-input parse/short-fraction parse/micro/nano/offset/min/pre/post/max-bound Timestamp WKT JSON plus other direct WKT JSON, including non-empty/escaped-input parse/empty `Struct`, object/escaped-object parse/list/escaped-list/string-scalar/escaped-string-scalar/number-exponent `Value`, and escaped/non-empty/empty `ListValue`, TextFormat, packed scalars, large bytes,
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
