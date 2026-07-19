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
| binary encode | 18.45 | 195.87 (10.62x) | 53.40 (2.89x) | 103.33 (5.60x) | 852.45 (46.20x) |
| binary decode | 94.83 | 252.25 (2.66x) | 231.43 (2.44x) | 220.31 (2.32x) | 937.91 (9.89x) |
| unknown fields count by number | 3.58 | — | — | 162.41 (45.37x) | — |
| deterministic binary encode | 47.09 | — | — | 129.91 (2.76x) | 1135.03 (24.10x) |
| scalarmix encode | 19.80 | 96.28 (4.86x) | 48.60 (2.45x) | 29.63 (1.50x) | 229.34 (11.58x) |
| scalarmix decode | 34.45 | 134.66 (3.91x) | 178.86 (5.19x) | 82.45 (2.39x) | 296.69 (8.61x) |
| textbytes encode | 9.27 | 78.34 (8.45x) | 33.36 (3.60x) | 117.81 (12.71x) | 155.69 (16.80x) |
| textbytes decode | 47.10 | 379.95 (8.07x) | 237.00 (5.03x) | 165.40 (3.51x) | 719.72 (15.28x) |
| largebytes encode | 18.05 | 2728.65 (151.17x) | 2699.98 (149.58x) | 2679.26 (148.44x) | 2796.21 (154.91x) |
| largebytes decode | 89.10 | 5597.76 (62.83x) | 3140.11 (35.24x) | 2747.81 (30.84x) | 24859.62 (279.01x) |
| presencemix encode | 16.86 | 55.54 (3.29x) | 27.56 (1.63x) | 57.66 (3.42x) | 255.36 (15.15x) |
| presencemix decode | 58.42 | 132.12 (2.26x) | 109.27 (1.87x) | 161.50 (2.76x) | 486.68 (8.33x) |
| complex encode | 48.86 | 143.52 (2.94x) | 96.25 (1.97x) | 159.82 (3.27x) | 937.81 (19.19x) |
| complex decode | 172.54 | 402.13 (2.33x) | 341.08 (1.98x) | 394.03 (2.28x) | 1323.04 (7.67x) |
| complex deterministic binary encode | 90.26 | — | — | 168.32 (1.86x) | 1164.62 (12.90x) |
| complex JSON stringify | 258.49 | — | — | 4886.39 (18.90x) | 6072.93 (23.49x) |
| complex JSON parse | 2398.19 | — | — | 11930.90 (4.97x) | 7501.47 (3.13x) |
| complex TextFormat format | 375.47 | — | — | 3815.63 (10.16x) | 5052.85 (13.46x) |
| complex TextFormat parse | 1880.43 | — | — | 6886.99 (3.66x) | 8174.85 (4.35x) |
| packed int32 encode | 690.65 | 3188.78 (4.62x) | 2523.02 (3.65x) | 1231.17 (1.78x) | 2761.38 (4.00x) |
| packed int32 decode | 728.83 | 1937.13 (2.66x) | 3232.38 (4.44x) | 953.52 (1.31x) | 3456.16 (4.74x) |
| JSON stringify | 152.55 | — | — | 2998.16 (19.65x) | 2039.91 (13.37x) |
| JSON parse | 1536.54 | — | — | 7474.23 (4.86x) | 4458.09 (2.90x) |
| Any WKT JSON stringify | 129.41 | — | — | 1881.37 (14.54x) | 945.89 (7.31x) |
| Any WKT JSON parse | 523.85 | — | — | 2973.55 (5.68x) | 1650.13 (3.15x) |
| Any Duration Escape WKT JSON parse | 543.61 | — | — | 3033.60 (5.58x) | 1655.74 (3.05x) |
| Any PlusDuration WKT JSON parse | 525.90 | — | — | 2997.82 (5.70x) | 1767.95 (3.36x) |
| Any ShortFractionDuration WKT JSON parse | 520.39 | — | — | 2947.43 (5.66x) | 1802.38 (3.46x) |
| Any MicroDuration WKT JSON stringify | 131.74 | — | — | 1902.27 (14.44x) | 1061.10 (8.05x) |
| Any MicroDuration WKT JSON parse | 528.23 | — | — | 3001.49 (5.68x) | 1725.86 (3.27x) |
| Any NanoDuration WKT JSON stringify | 133.78 | — | — | 1931.35 (14.44x) | 1040.41 (7.78x) |
| Any NanoDuration WKT JSON parse | 529.48 | — | — | 2995.21 (5.66x) | 1444.12 (2.73x) |
| Any NegativeDuration WKT JSON stringify | 135.28 | — | — | 1953.18 (14.44x) | 972.89 (7.19x) |
| Any NegativeDuration WKT JSON parse | 529.87 | — | — | 3098.64 (5.85x) | 1565.60 (2.95x) |
| Any FractionalNegativeDuration WKT JSON stringify | 123.50 | — | — | 1890.48 (15.31x) | 991.62 (8.03x) |
| Any FractionalNegativeDuration WKT JSON parse | 521.49 | — | — | 3051.71 (5.85x) | 1425.07 (2.73x) |
| Any MaxDuration WKT JSON stringify | 119.77 | — | — | 1748.29 (14.60x) | 1025.90 (8.57x) |
| Any MaxDuration WKT JSON parse | 539.72 | — | — | 2965.88 (5.50x) | 1553.23 (2.88x) |
| Any MinDuration WKT JSON stringify | 118.61 | — | — | 1763.12 (14.86x) | 948.28 (7.99x) |
| Any MinDuration WKT JSON parse | 543.47 | — | — | 3020.98 (5.56x) | 1485.35 (2.73x) |
| Any ZeroDuration WKT JSON stringify | 102.54 | — | — | 915.21 (8.93x) | 931.67 (9.09x) |
| Any ZeroDuration WKT JSON parse | 470.23 | — | — | 2259.84 (4.81x) | 1400.52 (2.98x) |
| Any FieldMask WKT JSON stringify | 228.67 | — | — | 1737.25 (7.60x) | 1369.06 (5.99x) |
| Any FieldMask WKT JSON parse | 719.65 | — | — | 3140.67 (4.36x) | 2104.58 (2.92x) |
| Any FieldMask Escape WKT JSON parse | 747.64 | — | — | 3225.17 (4.31x) | 2043.40 (2.73x) |
| Any EmptyFieldMask WKT JSON stringify | 116.74 | — | — | 924.40 (7.92x) | 739.06 (6.33x) |
| Any EmptyFieldMask WKT JSON parse | 451.95 | — | — | 2172.45 (4.81x) | 1225.65 (2.71x) |
| Any Timestamp WKT JSON stringify | 177.96 | — | — | 2029.52 (11.40x) | 988.07 (5.55x) |
| Any Timestamp WKT JSON parse | 573.61 | — | — | 3029.73 (5.28x) | 1476.45 (2.57x) |
| Any Timestamp Escape WKT JSON parse | 585.65 | — | — | 3079.85 (5.26x) | 1680.39 (2.87x) |
| Any ShortFraction Timestamp WKT JSON parse | 566.84 | — | — | 3025.76 (5.34x) | 1548.92 (2.73x) |
| Any Micro Timestamp WKT JSON stringify | 178.09 | — | — | 2036.92 (11.44x) | 991.22 (5.57x) |
| Any Micro Timestamp WKT JSON parse | 577.56 | — | — | 3035.50 (5.26x) | 1715.63 (2.97x) |
| Any Nano Timestamp WKT JSON stringify | 179.64 | — | — | 2038.54 (11.35x) | 1006.37 (5.60x) |
| Any Nano Timestamp WKT JSON parse | 583.69 | — | — | 3045.02 (5.22x) | 1847.10 (3.16x) |
| Any Offset Timestamp WKT JSON parse | 594.10 | — | — | 3069.21 (5.17x) | 1760.03 (2.96x) |
| Any PreEpoch Timestamp WKT JSON stringify | 143.60 | — | — | 1949.27 (13.57x) | 937.28 (6.53x) |
| Any PreEpoch Timestamp WKT JSON parse | 560.91 | — | — | 3043.50 (5.43x) | 1502.09 (2.68x) |
| Any Max Timestamp WKT JSON stringify | 166.13 | — | — | 2056.96 (12.38x) | 1146.92 (6.90x) |
| Any Max Timestamp WKT JSON parse | 586.38 | — | — | 3108.69 (5.30x) | 1531.71 (2.61x) |
| Any Min Timestamp WKT JSON stringify | 156.54 | — | — | 1943.90 (12.42x) | 986.28 (6.30x) |
| Any Min Timestamp WKT JSON parse | 558.00 | — | — | 3056.15 (5.48x) | 1480.59 (2.65x) |
| Any Empty WKT JSON stringify | 90.64 | — | — | 921.90 (10.17x) | 593.52 (6.55x) |
| Any Empty WKT JSON parse | 340.19 | — | — | 2140.56 (6.29x) | 1226.59 (3.61x) |
| Any Struct WKT JSON stringify | 628.56 | — | — | 5825.69 (9.27x) | 6008.59 (9.56x) |
| Any Struct WKT JSON parse | 1788.92 | — | — | 11067.70 (6.19x) | 8880.93 (4.96x) |
| Any Struct Escape WKT JSON parse | 1798.23 | — | — | 11124.70 (6.19x) | 8605.99 (4.79x) |
| Any Struct NumberExponent WKT JSON parse | 1771.25 | — | — | 11056.30 (6.24x) | 8325.67 (4.70x) |
| Any EmptyStruct WKT JSON stringify | 122.68 | — | — | 910.04 (7.42x) | 932.32 (7.60x) |
| Any EmptyStruct WKT JSON parse | 441.09 | — | — | 2226.34 (5.05x) | 1457.08 (3.30x) |
| Any Value WKT JSON stringify | 669.31 | — | — | 5906.83 (8.83x) | 6400.15 (9.56x) |
| Any Value WKT JSON parse | 1835.41 | — | — | 11272.80 (6.14x) | 9012.21 (4.91x) |
| Any Value Escape WKT JSON parse | 1869.57 | — | — | 11335.00 (6.06x) | 9547.38 (5.11x) |
| Any Value NumberExponent WKT JSON parse | 1847.33 | — | — | 11281.60 (6.11x) | 9033.43 (4.89x) |
| Any NullValue WKT JSON stringify | 130.82 | — | — | 2247.43 (17.18x) | 873.82 (6.68x) |
| Any NullValue WKT JSON parse | 466.45 | — | — | 4049.26 (8.68x) | 1433.16 (3.07x) |
| Any StringScalarValue WKT JSON stringify | 151.57 | — | — | 2265.67 (14.95x) | 950.54 (6.27x) |
| Any StringScalarValue WKT JSON parse | 524.10 | — | — | 3616.73 (6.90x) | 1549.35 (2.96x) |
| Any StringScalarValue Escape WKT JSON parse | 538.10 | — | — | 3640.85 (6.77x) | 1997.12 (3.71x) |
| Any EmptyStringScalarValue WKT JSON stringify | 138.31 | — | — | 2269.16 (16.41x) | 904.04 (6.54x) |
| Any EmptyStringScalarValue WKT JSON parse | 495.68 | — | — | 3609.38 (7.28x) | 1441.95 (2.91x) |
| Any NumberValue WKT JSON stringify | 174.59 | — | — | 2506.77 (14.36x) | 998.13 (5.72x) |
| Any NumberValue WKT JSON parse | 505.93 | — | — | 3672.27 (7.26x) | 1518.46 (3.00x) |
| Any NumberValue Exponent WKT JSON parse | 509.89 | — | — | 3698.41 (7.25x) | 1560.32 (3.06x) |
| Any ZeroNumberValue WKT JSON stringify | 145.21 | — | — | 2465.98 (16.98x) | 912.22 (6.28x) |
| Any ZeroNumberValue WKT JSON parse | 501.87 | — | — | 3625.06 (7.22x) | 1499.27 (2.99x) |
| Any BoolScalarValue WKT JSON stringify | 127.39 | — | — | 2253.54 (17.69x) | 883.09 (6.93x) |
| Any BoolScalarValue WKT JSON parse | 468.60 | — | — | 3594.29 (7.67x) | 1399.02 (2.99x) |
| Any FalseBoolScalarValue WKT JSON stringify | 130.20 | — | — | 2246.76 (17.26x) | 884.26 (6.79x) |
| Any FalseBoolScalarValue WKT JSON parse | 469.74 | — | — | 3592.10 (7.65x) | 1517.13 (3.23x) |
| Any ListKindValue WKT JSON stringify | 503.77 | — | — | 5560.95 (11.04x) | 4778.48 (9.49x) |
| Any ListKindValue WKT JSON parse | 1394.91 | — | — | 9934.39 (7.12x) | 7651.93 (5.49x) |
| Any ListKindValue Escape WKT JSON parse | 1423.41 | — | — | 9962.38 (7.00x) | 7484.36 (5.26x) |
| Any EmptyStructKindValue WKT JSON stringify | 144.18 | — | — | 2913.97 (20.21x) | 1214.69 (8.42x) |
| Any EmptyStructKindValue WKT JSON parse | 503.95 | — | — | 5389.28 (10.69x) | 1951.92 (3.87x) |
| Any EmptyListKindValue WKT JSON stringify | 141.79 | — | — | 2881.20 (20.32x) | 1062.87 (7.50x) |
| Any EmptyListKindValue WKT JSON parse | 510.36 | — | — | 4392.47 (8.61x) | 1684.70 (3.30x) |
| Any DoubleValue WKT JSON stringify | 188.43 | — | — | 1788.09 (9.49x) | 804.69 (4.27x) |
| Any DoubleValue WKT JSON parse | 527.59 | — | — | 2722.20 (5.16x) | 1397.18 (2.65x) |
| Any DoubleValue String WKT JSON parse | 539.09 | — | — | 2725.89 (5.06x) | 1467.18 (2.72x) |
| Any NegativeDoubleValue WKT JSON stringify | 190.98 | — | — | 1790.82 (9.38x) | 759.01 (3.97x) |
| Any NegativeDoubleValue WKT JSON parse | 528.35 | — | — | 2725.67 (5.16x) | 1352.37 (2.56x) |
| Any ZeroDoubleValue WKT JSON stringify | 161.35 | — | — | 914.96 (5.67x) | 733.04 (4.54x) |
| Any ZeroDoubleValue WKT JSON parse | 524.16 | — | — | 2169.74 (4.14x) | 1368.23 (2.61x) |
| Any DoubleValue NaN WKT JSON stringify | 150.90 | — | — | 1625.64 (10.77x) | 747.92 (4.96x) |
| Any DoubleValue NaN WKT JSON parse | 522.80 | — | — | 2674.64 (5.12x) | 1364.56 (2.61x) |
| Any DoubleValue Infinity WKT JSON stringify | 161.12 | — | — | 1566.11 (9.72x) | 708.24 (4.40x) |
| Any DoubleValue Infinity WKT JSON parse | 527.34 | — | — | 2701.98 (5.12x) | 1286.84 (2.44x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 158.07 | — | — | 1549.75 (9.80x) | 681.52 (4.31x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 530.01 | — | — | 2672.82 (5.04x) | 1269.65 (2.40x) |
| Any FloatValue WKT JSON stringify | 192.53 | — | — | 1763.73 (9.16x) | 755.36 (3.92x) |
| Any FloatValue WKT JSON parse | 523.88 | — | — | 2710.02 (5.17x) | 1423.00 (2.72x) |
| Any FloatValue String WKT JSON parse | 538.80 | — | — | 2704.27 (5.02x) | 1456.96 (2.70x) |
| Any NegativeFloatValue WKT JSON stringify | 197.53 | — | — | 1727.12 (8.74x) | 784.53 (3.97x) |
| Any NegativeFloatValue WKT JSON parse | 525.71 | — | — | 2699.96 (5.14x) | 1360.49 (2.59x) |
| Any ZeroFloatValue WKT JSON stringify | 166.88 | — | — | 911.87 (5.46x) | 703.39 (4.21x) |
| Any ZeroFloatValue WKT JSON parse | 519.96 | — | — | 2150.40 (4.14x) | 1249.08 (2.40x) |
| Any FloatValue NaN WKT JSON stringify | 152.06 | — | — | 1554.72 (10.22x) | 711.20 (4.68x) |
| Any FloatValue NaN WKT JSON parse | 519.04 | — | — | 2617.22 (5.04x) | 1344.71 (2.59x) |
| Any FloatValue Infinity WKT JSON stringify | 161.46 | — | — | 1541.07 (9.54x) | 733.77 (4.54x) |
| Any FloatValue Infinity WKT JSON parse | 522.70 | — | — | 2649.59 (5.07x) | 1307.79 (2.50x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 161.87 | — | — | 1534.79 (9.48x) | 729.78 (4.51x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 527.59 | — | — | 2628.12 (4.98x) | 1382.83 (2.62x) |
| Any Int64Value WKT JSON stringify | 170.06 | — | — | 1580.33 (9.29x) | 807.77 (4.75x) |
| Any Int64Value WKT JSON parse | 561.82 | — | — | 2781.08 (4.95x) | 1510.58 (2.69x) |
| Any Int64Value Number WKT JSON parse | 566.71 | — | — | 2748.89 (4.85x) | 1544.73 (2.73x) |
| Any ZeroInt64Value WKT JSON stringify | 156.02 | — | — | 913.14 (5.85x) | 828.82 (5.31x) |
| Any ZeroInt64Value WKT JSON parse | 527.77 | — | — | 2156.00 (4.09x) | 1397.66 (2.65x) |
| Any NegativeInt64Value WKT JSON stringify | 165.22 | — | — | 1558.76 (9.43x) | 863.41 (5.23x) |
| Any NegativeInt64Value WKT JSON parse | 563.36 | — | — | 2794.34 (4.96x) | 1665.97 (2.96x) |
| Any MinInt64Value WKT JSON stringify | 172.84 | — | — | 1558.58 (9.02x) | 873.64 (5.05x) |
| Any MinInt64Value WKT JSON parse | 571.61 | — | — | 2812.39 (4.92x) | 1721.14 (3.01x) |
| Any MaxInt64Value WKT JSON stringify | 168.85 | — | — | 1555.74 (9.21x) | 888.22 (5.26x) |
| Any MaxInt64Value WKT JSON parse | 571.33 | — | — | 2813.78 (4.92x) | 1640.42 (2.87x) |
| Any UInt64Value WKT JSON stringify | 177.91 | — | — | 1551.47 (8.72x) | 825.00 (4.64x) |
| Any UInt64Value WKT JSON parse | 555.85 | — | — | 2784.20 (5.01x) | 1504.98 (2.71x) |
| Any UInt64Value Number WKT JSON parse | 568.21 | — | — | 2750.54 (4.84x) | 1459.44 (2.57x) |
| Any ZeroUInt64Value WKT JSON stringify | 164.50 | — | — | 921.72 (5.60x) | 772.65 (4.70x) |
| Any ZeroUInt64Value WKT JSON parse | 532.93 | — | — | 2157.20 (4.05x) | 1448.10 (2.72x) |
| Any MaxUInt64Value WKT JSON stringify | 179.61 | — | — | 1557.90 (8.67x) | 900.79 (5.02x) |
| Any MaxUInt64Value WKT JSON parse | 565.28 | — | — | 2839.96 (5.02x) | 1636.94 (2.90x) |
| Any Int32Value WKT JSON stringify | 278.66 | — | — | 1549.25 (5.56x) | 711.78 (2.55x) |
| Any Int32Value WKT JSON parse | 537.83 | — | — | 2658.27 (4.94x) | 1402.19 (2.61x) |
| Any Int32Value String WKT JSON parse | 542.61 | — | — | 2667.26 (4.92x) | 1491.82 (2.75x) |
| Any ZeroInt32Value WKT JSON stringify | 164.66 | — | — | 911.78 (5.54x) | 708.67 (4.30x) |
| Any ZeroInt32Value WKT JSON parse | 533.17 | — | — | 2145.42 (4.02x) | 1287.23 (2.41x) |
| Any NegativeInt32Value WKT JSON stringify | 170.78 | — | — | 1544.28 (9.04x) | 700.76 (4.10x) |
| Any NegativeInt32Value WKT JSON parse | 540.42 | — | — | 2685.89 (4.97x) | 1354.88 (2.51x) |
| Any MinInt32Value WKT JSON stringify | 174.62 | — | — | 1545.38 (8.85x) | 710.95 (4.07x) |
| Any MinInt32Value WKT JSON parse | 545.42 | — | — | 2697.10 (4.94x) | 1397.45 (2.56x) |
| Any MaxInt32Value WKT JSON stringify | 175.38 | — | — | 1544.88 (8.81x) | 700.70 (4.00x) |
| Any MaxInt32Value WKT JSON parse | 545.69 | — | — | 2665.14 (4.88x) | 1360.17 (2.49x) |
| Any UInt32Value WKT JSON stringify | 179.33 | — | — | 1548.16 (8.63x) | 719.77 (4.01x) |
| Any UInt32Value WKT JSON parse | 540.22 | — | — | 2660.63 (4.93x) | 1405.90 (2.60x) |
| Any UInt32Value String WKT JSON parse | 550.20 | — | — | 2670.79 (4.85x) | 1459.06 (2.65x) |
| Any ZeroUInt32Value WKT JSON stringify | 177.81 | — | — | 919.97 (5.17x) | 680.62 (3.83x) |
| Any ZeroUInt32Value WKT JSON parse | 536.82 | — | — | 2151.12 (4.01x) | 1369.93 (2.55x) |
| Any MaxUInt32Value WKT JSON stringify | 183.78 | — | — | 1545.32 (8.41x) | 782.62 (4.26x) |
| Any MaxUInt32Value WKT JSON parse | 548.98 | — | — | 2668.47 (4.86x) | 1527.73 (2.78x) |
| Any BoolValue WKT JSON stringify | 171.53 | — | — | 1520.59 (8.86x) | 732.61 (4.27x) |
| Any BoolValue WKT JSON parse | 492.52 | — | — | 2592.66 (5.26x) | 1306.51 (2.65x) |
| Any FalseBoolValue WKT JSON stringify | 169.99 | — | — | 912.32 (5.37x) | 694.74 (4.09x) |
| Any FalseBoolValue WKT JSON parse | 493.45 | — | — | 2144.08 (4.35x) | 1289.48 (2.61x) |
| Any StringValue WKT JSON stringify | 195.25 | — | — | 1553.66 (7.96x) | 737.72 (3.78x) |
| Any StringValue WKT JSON parse | 556.77 | — | — | 2656.06 (4.77x) | 1320.30 (2.37x) |
| Any StringValue Escape WKT JSON parse | 565.68 | — | — | 2680.66 (4.74x) | 1430.80 (2.53x) |
| Any EmptyStringValue WKT JSON stringify | 184.05 | — | — | 911.75 (4.95x) | 730.22 (3.97x) |
| Any EmptyStringValue WKT JSON parse | 526.58 | — | — | 2159.14 (4.10x) | 1356.13 (2.58x) |
| Any BytesValue WKT JSON stringify | 189.60 | — | — | 1583.58 (8.35x) | 849.12 (4.48x) |
| Any BytesValue WKT JSON parse | 573.62 | — | — | 2690.22 (4.69x) | 1378.80 (2.40x) |
| Any BytesValue URL WKT JSON parse | 589.64 | — | — | 2666.84 (4.52x) | 1430.88 (2.43x) |
| Any EmptyBytesValue WKT JSON stringify | 183.25 | — | — | 909.67 (4.96x) | 740.04 (4.04x) |
| Any EmptyBytesValue WKT JSON parse | 536.78 | — | — | 2159.87 (4.02x) | 1358.40 (2.53x) |
| Nested Any WKT JSON stringify | 299.47 | — | — | 2480.56 (8.28x) | 1369.04 (4.57x) |
| Nested Any WKT JSON parse | 869.95 | — | — | 4247.41 (4.88x) | 2633.97 (3.03x) |
| Duration JSON stringify | 57.01 | — | — | 959.94 (16.84x) | 364.36 (6.39x) |
| Duration JSON parse | 19.32 | — | — | 1443.83 (74.73x) | 374.19 (19.37x) |
| Duration Escape JSON parse | 41.68 | — | — | 1599.68 (38.38x) | 416.19 (9.99x) |
| PlusDuration JSON parse | 19.56 | — | — | 1528.10 (78.12x) | 371.98 (19.02x) |
| ShortFractionDuration JSON parse | 15.56 | — | — | 1439.44 (92.51x) | 360.28 (23.15x) |
| MicroDuration JSON stringify | 59.11 | — | — | 966.21 (16.35x) | 389.20 (6.58x) |
| MicroDuration JSON parse | 19.33 | — | — | 1464.28 (75.75x) | 367.20 (19.00x) |
| NanoDuration JSON stringify | 57.25 | — | — | 1002.14 (17.50x) | 376.92 (6.58x) |
| NanoDuration JSON parse | 21.60 | — | — | 1471.08 (68.11x) | 391.66 (18.13x) |
| NegativeDuration JSON stringify | 57.77 | — | — | 1004.44 (17.39x) | 390.98 (6.77x) |
| NegativeDuration JSON parse | 21.20 | — | — | 1545.17 (72.89x) | 377.42 (17.80x) |
| FractionalNegativeDuration JSON stringify | 58.10 | — | — | 971.18 (16.72x) | 402.37 (6.93x) |
| FractionalNegativeDuration JSON parse | 21.06 | — | — | 1454.11 (69.05x) | 357.29 (16.97x) |
| MaxDuration JSON stringify | 49.25 | — | — | 856.29 (17.39x) | 391.22 (7.94x) |
| MaxDuration JSON parse | 32.61 | — | — | 1429.09 (43.82x) | 392.02 (12.02x) |
| MinDuration JSON stringify | 49.47 | — | — | 866.18 (17.51x) | 449.72 (9.09x) |
| MinDuration JSON parse | 34.52 | — | — | 1449.75 (42.00x) | 360.34 (10.44x) |
| ZeroDuration JSON stringify | 44.42 | — | — | 815.03 (18.35x) | 342.43 (7.71x) |
| ZeroDuration JSON parse | 14.55 | — | — | 1365.82 (93.87x) | 295.94 (20.34x) |
| FieldMask JSON stringify | 137.05 | — | — | 881.20 (6.43x) | 633.38 (4.62x) |
| FieldMask JSON parse | 138.85 | — | — | 1656.22 (11.93x) | 809.57 (5.83x) |
| FieldMask Escape JSON parse | 189.85 | — | — | 1708.52 (9.00x) | 876.38 (4.62x) |
| EmptyFieldMask JSON stringify | 40.67 | — | — | 605.12 (14.88x) | 185.97 (4.57x) |
| EmptyFieldMask JSON parse | 4.79 | — | — | 945.12 (197.31x) | 154.18 (32.19x) |
| Timestamp JSON stringify | 95.53 | — | — | 1152.60 (12.07x) | 408.97 (4.28x) |
| Timestamp JSON parse | 45.35 | — | — | 1498.41 (33.04x) | 412.82 (9.10x) |
| Timestamp Escape JSON parse | 80.74 | — | — | 1524.29 (18.88x) | 485.38 (6.01x) |
| ShortFraction Timestamp JSON parse | 43.41 | — | — | 1481.34 (34.12x) | 405.35 (9.34x) |
| Micro Timestamp JSON stringify | 96.84 | — | — | 1144.84 (11.82x) | 414.13 (4.28x) |
| Micro Timestamp JSON parse | 47.25 | — | — | 1504.89 (31.85x) | 434.12 (9.19x) |
| Nano Timestamp JSON stringify | 93.97 | — | — | 1185.18 (12.61x) | 420.94 (4.48x) |
| Nano Timestamp JSON parse | 49.86 | — | — | 1527.51 (30.64x) | 449.97 (9.02x) |
| Offset Timestamp JSON parse | 52.43 | — | — | 1538.20 (29.34x) | 471.85 (9.00x) |
| PreEpoch Timestamp JSON stringify | 66.20 | — | — | 1071.57 (16.19x) | 398.77 (6.02x) |
| PreEpoch Timestamp JSON parse | 43.08 | — | — | 1465.42 (34.02x) | 399.47 (9.27x) |
| Max Timestamp JSON stringify | 78.50 | — | — | 1199.46 (15.28x) | 424.82 (5.41x) |
| Max Timestamp JSON parse | 51.50 | — | — | 1535.67 (29.82x) | 448.55 (8.71x) |
| Min Timestamp JSON stringify | 80.27 | — | — | 1063.52 (13.25x) | 411.92 (5.13x) |
| Min Timestamp JSON parse | 41.07 | — | — | 1448.07 (35.26x) | 398.52 (9.70x) |
| Empty JSON stringify | 20.70 | — | — | 497.20 (24.02x) | 74.15 (3.58x) |
| Empty JSON parse | 67.46 | — | — | 716.90 (10.63x) | 185.54 (2.75x) |
| Struct JSON stringify | 176.77 | — | — | 5780.75 (32.70x) | 2913.46 (16.48x) |
| Struct JSON parse | 914.44 | — | — | 10874.90 (11.89x) | 4494.33 (4.91x) |
| Struct Escape JSON parse | 1221.07 | — | — | 10897.30 (8.92x) | 4519.11 (3.70x) |
| Struct NumberExponent JSON parse | 846.12 | — | — | 10930.50 (12.92x) | 4390.83 (5.19x) |
| EmptyStruct JSON stringify | 40.73 | — | — | 701.65 (17.23x) | 340.33 (8.36x) |
| EmptyStruct JSON parse | 87.85 | — | — | 2022.26 (23.02x) | 340.05 (3.87x) |
| Value JSON stringify | 180.35 | — | — | 6652.13 (36.88x) | 3361.53 (18.64x) |
| Value JSON parse | 971.04 | — | — | 12084.80 (12.45x) | 4947.69 (5.10x) |
| Value Escape JSON parse | 1042.60 | — | — | 12193.70 (11.70x) | 5329.41 (5.11x) |
| Value NumberExponent JSON parse | 999.41 | — | — | 17449.50 (17.46x) | 5003.77 (5.01x) |
| NullValue JSON stringify | 41.05 | — | — | 2372.93 (57.81x) | 220.99 (5.38x) |
| NullValue JSON parse | 83.14 | — | — | 4314.41 (51.89x) | 339.52 (4.08x) |
| StringScalarValue JSON stringify | 48.85 | — | — | 1949.25 (39.90x) | 271.25 (5.55x) |
| StringScalarValue JSON parse | 146.26 | — | — | 3264.21 (22.32x) | 422.97 (2.89x) |
| StringScalarValue Escape JSON parse | 154.73 | — | — | 3340.73 (21.59x) | 489.12 (3.16x) |
| EmptyStringScalarValue JSON stringify | 46.84 | — | — | 1930.66 (41.22x) | 269.40 (5.75x) |
| EmptyStringScalarValue JSON parse | 90.22 | — | — | 3249.93 (36.02x) | 351.29 (3.89x) |
| NumberValue JSON stringify | 77.20 | — | — | 2526.38 (32.73x) | 329.61 (4.27x) |
| NumberValue JSON parse | 136.16 | — | — | 2891.11 (21.23x) | 418.76 (3.08x) |
| NumberValue Exponent JSON parse | 138.45 | — | — | 2218.34 (16.02x) | 402.52 (2.91x) |
| ZeroNumberValue JSON stringify | 52.25 | — | — | 1513.78 (28.97x) | 277.85 (5.32x) |
| ZeroNumberValue JSON parse | 134.75 | — | — | 2126.02 (15.78x) | 368.97 (2.74x) |
| BoolScalarValue JSON stringify | 41.32 | — | — | 1312.20 (31.76x) | 230.38 (5.58x) |
| BoolScalarValue JSON parse | 81.19 | — | — | 2023.98 (24.93x) | 319.55 (3.94x) |
| FalseBoolScalarValue JSON stringify | 39.87 | — | — | 1316.01 (33.01x) | 216.01 (5.42x) |
| FalseBoolScalarValue JSON parse | 81.34 | — | — | 2026.81 (24.92x) | 307.61 (3.78x) |
| ListKindValue JSON stringify | 142.03 | — | — | 6094.98 (42.91x) | 2217.49 (15.61x) |
| ListKindValue JSON parse | 770.41 | — | — | 10398.70 (13.50x) | 3710.70 (4.82x) |
| ListKindValue Escape JSON parse | 802.77 | — | — | 10478.60 (13.05x) | 4518.23 (5.63x) |
| EmptyStructKindValue JSON stringify | 43.49 | — | — | 1938.04 (44.56x) | 531.56 (12.22x) |
| EmptyStructKindValue JSON parse | 135.22 | — | — | 3772.29 (27.90x) | 647.08 (4.79x) |
| EmptyListKindValue JSON stringify | 41.84 | — | — | 1932.98 (46.20x) | 359.91 (8.60x) |
| EmptyListKindValue JSON parse | 171.15 | — | — | 4049.24 (23.66x) | 547.09 (3.20x) |
| ListValue JSON stringify | 141.19 | — | — | 4725.10 (33.47x) | 2050.55 (14.52x) |
| ListValue JSON parse | 653.14 | — | — | 8471.32 (12.97x) | 3701.80 (5.67x) |
| ListValue Escape JSON parse | 673.66 | — | — | 8573.29 (12.73x) | 3997.05 (5.93x) |
| EmptyListValue JSON stringify | 39.98 | — | — | 688.58 (17.22x) | 176.68 (4.42x) |
| EmptyListValue JSON parse | 124.45 | — | — | 2249.91 (18.08x) | 304.27 (2.44x) |
| DoubleValue JSON stringify | 68.99 | — | — | 851.81 (12.35x) | 199.11 (2.89x) |
| DoubleValue JSON parse | 111.48 | — | — | 1229.85 (11.03x) | 286.45 (2.57x) |
| DoubleValue String JSON parse | 111.82 | — | — | 1170.09 (10.46x) | 376.00 (3.36x) |
| NegativeDoubleValue JSON stringify | 69.42 | — | — | 851.59 (12.27x) | 184.85 (2.66x) |
| NegativeDoubleValue JSON parse | 111.52 | — | — | 1239.45 (11.11x) | 262.57 (2.35x) |
| ZeroDoubleValue JSON stringify | 47.06 | — | — | 802.28 (17.05x) | 145.37 (3.09x) |
| ZeroDoubleValue JSON parse | 108.27 | — | — | 1155.24 (10.67x) | 264.74 (2.45x) |
| DoubleValue NaN JSON stringify | 46.38 | — | — | 663.10 (14.30x) | 127.41 (2.75x) |
| DoubleValue NaN JSON parse | 105.21 | — | — | 1100.42 (10.46x) | 265.84 (2.53x) |
| DoubleValue Infinity JSON stringify | 47.99 | — | — | 662.51 (13.81x) | 117.57 (2.45x) |
| DoubleValue Infinity JSON parse | 106.49 | — | — | 1108.85 (10.41x) | 275.61 (2.59x) |
| DoubleValue NegativeInfinity JSON stringify | 48.16 | — | — | 653.03 (13.56x) | 125.96 (2.62x) |
| DoubleValue NegativeInfinity JSON parse | 108.73 | — | — | 1111.54 (10.22x) | 264.90 (2.44x) |
| FloatValue JSON stringify | 70.50 | — | — | 797.00 (11.30x) | 178.63 (2.53x) |
| FloatValue JSON parse | 110.16 | — | — | 1215.64 (11.04x) | 273.10 (2.48x) |
| FloatValue String JSON parse | 110.71 | — | — | 1151.71 (10.40x) | 371.83 (3.36x) |
| NegativeFloatValue JSON stringify | 70.53 | — | — | 803.54 (11.39x) | 206.84 (2.93x) |
| NegativeFloatValue JSON parse | 111.73 | — | — | 1227.44 (10.99x) | 290.20 (2.60x) |
| ZeroFloatValue JSON stringify | 46.96 | — | — | 743.21 (15.83x) | 137.06 (2.92x) |
| ZeroFloatValue JSON parse | 108.50 | — | — | 1155.83 (10.65x) | 263.77 (2.43x) |
| FloatValue NaN JSON stringify | 46.38 | — | — | 636.98 (13.73x) | 119.53 (2.58x) |
| FloatValue NaN JSON parse | 105.94 | — | — | 1082.98 (10.22x) | 283.46 (2.68x) |
| FloatValue Infinity JSON stringify | 48.00 | — | — | 638.97 (13.31x) | 123.52 (2.57x) |
| FloatValue Infinity JSON parse | 106.93 | — | — | 1094.93 (10.24x) | 258.92 (2.42x) |
| FloatValue NegativeInfinity JSON stringify | 48.13 | — | — | 635.98 (13.21x) | 116.65 (2.42x) |
| FloatValue NegativeInfinity JSON parse | 108.40 | — | — | 1096.78 (10.12x) | 294.84 (2.72x) |
| Int64Value JSON stringify | 50.01 | — | — | 674.50 (13.49x) | 262.62 (5.25x) |
| Int64Value JSON parse | 125.71 | — | — | 1240.24 (9.87x) | 444.74 (3.54x) |
| Int64Value Number JSON parse | 127.48 | — | — | 1301.15 (10.21x) | 340.42 (2.67x) |
| ZeroInt64Value JSON stringify | 41.54 | — | — | 610.72 (14.70x) | 207.96 (5.01x) |
| ZeroInt64Value JSON parse | 106.45 | — | — | 1108.13 (10.41x) | 345.14 (3.24x) |
| NegativeInt64Value JSON stringify | 48.48 | — | — | 670.34 (13.83x) | 259.79 (5.36x) |
| NegativeInt64Value JSON parse | 127.19 | — | — | 1214.03 (9.55x) | 447.18 (3.52x) |
| MinInt64Value JSON stringify | 49.78 | — | — | 681.43 (13.69x) | 265.79 (5.34x) |
| MinInt64Value JSON parse | 134.87 | — | — | 1250.29 (9.27x) | 481.60 (3.57x) |
| MaxInt64Value JSON stringify | 50.83 | — | — | 676.78 (13.31x) | 280.57 (5.52x) |
| MaxInt64Value JSON parse | 134.46 | — | — | 1242.02 (9.24x) | 451.66 (3.36x) |
| UInt64Value JSON stringify | 50.51 | — | — | 674.51 (13.35x) | 254.48 (5.04x) |
| UInt64Value JSON parse | 125.77 | — | — | 1230.24 (9.78x) | 421.92 (3.35x) |
| UInt64Value Number JSON parse | 128.06 | — | — | 1291.23 (10.08x) | 321.35 (2.51x) |
| ZeroUInt64Value JSON stringify | 41.46 | — | — | 605.72 (14.61x) | 197.37 (4.76x) |
| ZeroUInt64Value JSON parse | 105.27 | — | — | 1090.02 (10.35x) | 314.37 (2.99x) |
| MaxUInt64Value JSON stringify | 49.37 | — | — | 678.24 (13.74x) | 271.63 (5.50x) |
| MaxUInt64Value JSON parse | 135.55 | — | — | 1258.21 (9.28x) | 475.97 (3.51x) |
| Int32Value JSON stringify | 47.41 | — | — | 631.22 (13.31x) | 140.55 (2.96x) |
| Int32Value JSON parse | 117.33 | — | — | 1179.16 (10.05x) | 286.91 (2.45x) |
| Int32Value String JSON parse | 115.00 | — | — | 1126.38 (9.79x) | 372.39 (3.24x) |
| ZeroInt32Value JSON stringify | 47.18 | — | — | 611.26 (12.96x) | 172.25 (3.65x) |
| ZeroInt32Value JSON parse | 113.84 | — | — | 1149.34 (10.10x) | 256.75 (2.26x) |
| NegativeInt32Value JSON stringify | 47.68 | — | — | 639.13 (13.40x) | 131.07 (2.75x) |
| NegativeInt32Value JSON parse | 117.55 | — | — | 1200.73 (10.21x) | 297.23 (2.53x) |
| MinInt32Value JSON stringify | 57.78 | — | — | 636.72 (11.02x) | 131.83 (2.28x) |
| MinInt32Value JSON parse | 166.74 | — | — | 1217.37 (7.30x) | 326.98 (1.96x) |
| MaxInt32Value JSON stringify | 48.05 | — | — | 631.16 (13.14x) | 128.49 (2.67x) |
| MaxInt32Value JSON parse | 123.56 | — | — | 1198.92 (9.70x) | 311.94 (2.52x) |
| UInt32Value JSON stringify | 47.43 | — | — | 637.88 (13.45x) | 129.67 (2.73x) |
| UInt32Value JSON parse | 117.32 | — | — | 1188.66 (10.13x) | 297.90 (2.54x) |
| UInt32Value String JSON parse | 115.08 | — | — | 1130.55 (9.82x) | 363.11 (3.16x) |
| ZeroUInt32Value JSON stringify | 47.24 | — | — | 626.11 (13.25x) | 148.57 (3.15x) |
| ZeroUInt32Value JSON parse | 113.70 | — | — | 1322.95 (11.64x) | 250.70 (2.20x) |
| MaxUInt32Value JSON stringify | 47.86 | — | — | 634.01 (13.25x) | 142.41 (2.98x) |
| MaxUInt32Value JSON parse | 123.60 | — | — | 1218.42 (9.86x) | 328.86 (2.66x) |
| BoolValue JSON stringify | 45.05 | — | — | 632.32 (14.04x) | 142.65 (3.17x) |
| BoolValue JSON parse | 71.66 | — | — | 1058.79 (14.78x) | 222.49 (3.10x) |
| FalseBoolValue JSON stringify | 45.01 | — | — | 602.21 (13.38x) | 130.27 (2.89x) |
| FalseBoolValue JSON parse | 71.17 | — | — | 1059.50 (14.89x) | 208.07 (2.92x) |
| StringValue JSON stringify | 52.13 | — | — | 660.09 (12.66x) | 174.47 (3.35x) |
| StringValue JSON parse | 121.15 | — | — | 1148.97 (9.48x) | 281.42 (2.32x) |
| StringValue Escape JSON parse | 130.25 | — | — | 1175.21 (9.02x) | 333.08 (2.56x) |
| EmptyStringValue JSON stringify | 48.81 | — | — | 621.48 (12.73x) | 182.45 (3.74x) |
| EmptyStringValue JSON parse | 65.99 | — | — | 1114.60 (16.89x) | 229.12 (3.47x) |
| BytesValue JSON stringify | 49.28 | — | — | 656.28 (13.32x) | 205.40 (4.17x) |
| BytesValue JSON parse | 124.36 | — | — | 1170.87 (9.42x) | 331.08 (2.66x) |
| BytesValue URL JSON parse | 140.08 | — | — | 1159.07 (8.27x) | 302.62 (2.16x) |
| EmptyBytesValue JSON stringify | 40.86 | — | — | 626.39 (15.33x) | 177.29 (4.34x) |
| EmptyBytesValue JSON parse | 68.21 | — | — | 1127.52 (16.53x) | 248.07 (3.64x) |
| TextFormat format | 186.31 | — | — | 2515.57 (13.50x) | 2188.68 (11.75x) |
| TextFormat parse | 699.41 | — | — | 4999.12 (7.15x) | 6152.05 (8.80x) |
| packed fixed32 encode | 2.01 | 550.39 (273.83x) | 542.24 (269.77x) | 43.37 (21.58x) | 773.80 (384.98x) |
| packed fixed32 decode | 4.53 | 1046.21 (230.95x) | 1951.08 (430.70x) | 50.92 (11.24x) | 7499.13 (1655.44x) |
| packed fixed64 encode | 2.01 | 616.22 (306.58x) | 620.41 (308.66x) | 76.67 (38.14x) | 603.17 (300.08x) |
| packed fixed64 decode | 4.54 | 1063.68 (234.29x) | 7955.91 (1752.40x) | 81.06 (17.86x) | 2521.31 (555.35x) |
| packed sfixed32 encode | 2.01 | 550.37 (273.82x) | 539.50 (268.41x) | 44.49 (22.13x) | 481.29 (239.45x) |
| packed sfixed32 decode | 4.53 | 1048.96 (231.56x) | 1943.31 (428.99x) | 48.64 (10.74x) | 3841.28 (847.96x) |
| packed sfixed64 encode | 2.01 | 634.90 (315.87x) | 561.15 (279.18x) | 80.41 (40.00x) | 412.12 (205.03x) |
| packed sfixed64 decode | 4.53 | 1051.63 (232.15x) | 7902.49 (1744.48x) | 79.36 (17.52x) | 2374.06 (524.08x) |
| packed float encode | 2.00 | 811.73 (405.87x) | 539.86 (269.93x) | 43.75 (21.88x) | 353.83 (176.91x) |
| packed float decode | 4.54 | 1047.88 (230.81x) | 2017.08 (444.29x) | 48.35 (10.65x) | 1607.67 (354.11x) |
| packed double encode | 2.01 | 853.07 (424.41x) | 561.77 (279.49x) | 75.71 (37.67x) | 365.39 (181.79x) |
| packed double decode | 4.54 | 1033.25 (227.59x) | 2048.60 (451.23x) | 79.12 (17.43x) | 2394.09 (527.33x) |
| packed uint64 encode | 1301.38 | 4592.33 (3.53x) | 4020.81 (3.09x) | 2128.68 (1.64x) | 3468.37 (2.67x) |
| packed uint64 decode | 1779.84 | 2791.86 (1.57x) | 8845.86 (4.97x) | 2797.29 (1.57x) | 7681.79 (4.32x) |
| packed uint32 encode | 925.36 | 3627.07 (3.92x) | 3255.18 (3.52x) | 1725.66 (1.86x) | 2882.84 (3.12x) |
| packed uint32 decode | 1316.78 | 2435.03 (1.85x) | 3267.77 (2.48x) | 1989.58 (1.51x) | 6066.26 (4.61x) |
| packed int64 encode | 1398.90 | 11160.18 (7.98x) | 6051.80 (4.33x) | 2898.36 (2.07x) | 4114.27 (2.94x) |
| packed int64 decode | 2756.55 | 3644.53 (1.32x) | 10255.07 (3.72x) | 4692.65 (1.70x) | 10517.51 (3.82x) |
| packed sint32 encode | 865.41 | 3027.43 (3.50x) | 2849.29 (3.29x) | 1528.19 (1.77x) | 3421.80 (3.95x) |
| packed sint32 decode | 952.11 | 2549.46 (2.68x) | 3214.88 (3.38x) | 1121.17 (1.18x) | 3601.93 (3.78x) |
| packed sint64 encode | 1436.23 | 4934.11 (3.44x) | 4299.16 (2.99x) | 2388.58 (1.66x) | 4128.99 (2.87x) |
| packed sint64 decode | 2039.66 | 3076.12 (1.51x) | 9650.09 (4.73x) | 2942.00 (1.44x) | 8090.70 (3.97x) |
| packed bool encode | 2.00 | 1360.19 (680.10x) | 521.05 (260.52x) | 15.91 (7.96x) | 2211.59 (1105.80x) |
| packed bool decode | 263.05 | 1532.34 (5.83x) | 2837.62 (10.79x) | 820.72 (3.12x) | 1866.16 (7.09x) |
| packed enum encode | 276.16 | 2762.26 (10.00x) | 2145.90 (7.77x) | 1083.32 (3.92x) | 2484.14 (9.00x) |
| packed enum decode | 160.86 | 1532.34 (9.53x) | 4551.48 (28.29x) | 698.74 (4.34x) | 2124.12 (13.20x) |
| large map encode | 4075.88 | 16542.32 (4.06x) | 14421.75 (3.54x) | 21582.00 (5.30x) | 195655.75 (48.00x) |
| shuffled large map deterministic binary encode | 28493.58 | — | — | 91641.50 (3.22x) | 379849.79 (13.33x) |
| large map decode | 25566.28 | 90754.73 (3.55x) | 139530.62 (5.46x) | 90024.10 (3.52x) | 273469.25 (10.70x) |

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
