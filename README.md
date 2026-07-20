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

Latest accepted comparison (`/tmp/pbz-compare-wrapper-exponent-json-final.log`,
summarized in `/tmp/pbz-summary-wrapper-exponent-json-final.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 18.79 | 122.56 (6.52x) | 55.06 (2.93x) | 110.11 (5.86x) | 800.35 (42.59x) |
| binary decode | 86.67 | 251.94 (2.91x) | 232.08 (2.68x) | 220.22 (2.54x) | 884.58 (10.21x) |
| unknown fields count by number | 3.57 | — | — | 162.21 (45.44x) | — |
| deterministic binary encode | 48.70 | — | — | 152.75 (3.14x) | 1104.07 (22.67x) |
| scalarmix encode | 16.25 | 93.04 (5.73x) | 50.47 (3.11x) | 28.46 (1.75x) | 208.65 (12.84x) |
| scalarmix decode | 43.73 | 135.24 (3.09x) | 175.97 (4.02x) | 79.23 (1.81x) | 274.56 (6.28x) |
| textbytes encode | 13.53 | 81.18 (6.00x) | 33.34 (2.46x) | 117.15 (8.66x) | 154.61 (11.43x) |
| textbytes decode | 39.71 | 384.91 (9.69x) | 242.45 (6.11x) | 165.96 (4.18x) | 643.37 (16.20x) |
| largebytes encode | 17.80 | 2712.57 (152.39x) | 2633.00 (147.92x) | 2670.34 (150.02x) | 2729.94 (153.37x) |
| largebytes decode | 88.08 | 5612.90 (63.73x) | 3071.16 (34.87x) | 2748.58 (31.21x) | 23653.95 (268.55x) |
| presencemix encode | 16.70 | 53.77 (3.22x) | 29.71 (1.78x) | 55.46 (3.32x) | 229.90 (13.77x) |
| presencemix decode | 57.08 | 135.17 (2.37x) | 109.03 (1.91x) | 163.09 (2.86x) | 464.76 (8.14x) |
| complex encode | 51.02 | 137.36 (2.69x) | 95.72 (1.88x) | 167.23 (3.28x) | 914.77 (17.93x) |
| complex decode | 168.87 | 393.39 (2.33x) | 349.31 (2.07x) | 382.19 (2.26x) | 1380.75 (8.18x) |
| complex deterministic binary encode | 91.18 | — | — | 173.59 (1.90x) | 1158.86 (12.71x) |
| complex JSON stringify | 261.48 | — | — | 4906.99 (18.77x) | 5903.62 (22.58x) |
| complex JSON parse | 2366.56 | — | — | 11885.00 (5.02x) | 6994.75 (2.96x) |
| complex TextFormat format | 240.45 | — | — | 3768.07 (15.67x) | 5073.65 (21.10x) |
| complex TextFormat parse | 1832.79 | — | — | 6924.53 (3.78x) | 8610.03 (4.70x) |
| packed int32 encode | 649.54 | 3177.06 (4.89x) | 2514.12 (3.87x) | 1231.64 (1.90x) | 2741.10 (4.22x) |
| packed int32 decode | 683.57 | 1902.83 (2.78x) | 3213.44 (4.70x) | 962.88 (1.41x) | 3226.83 (4.72x) |
| JSON stringify | 154.81 | — | — | 2997.57 (19.36x) | 2112.82 (13.65x) |
| JSON parse | 1526.72 | — | — | 7403.30 (4.85x) | 4525.69 (2.96x) |
| Any WKT JSON stringify | 132.85 | — | — | 1923.10 (14.48x) | 1169.94 (8.81x) |
| Any WKT JSON parse | 517.63 | — | — | 2990.82 (5.78x) | 1753.61 (3.39x) |
| Any Duration Escape WKT JSON parse | 535.16 | — | — | 3008.28 (5.62x) | 1778.24 (3.32x) |
| Any PlusDuration WKT JSON parse | 515.60 | — | — | 3003.31 (5.82x) | 1528.04 (2.96x) |
| Any ShortFractionDuration WKT JSON parse | 513.63 | — | — | 2964.64 (5.77x) | 1535.46 (2.99x) |
| Any MicroDuration WKT JSON stringify | 136.43 | — | — | 1912.40 (14.02x) | 988.23 (7.24x) |
| Any MicroDuration WKT JSON parse | 517.32 | — | — | 3003.30 (5.81x) | 1584.89 (3.06x) |
| Any NanoDuration WKT JSON stringify | 134.25 | — | — | 1971.02 (14.68x) | 952.72 (7.10x) |
| Any NanoDuration WKT JSON parse | 523.46 | — | — | 3007.30 (5.75x) | 1414.99 (2.70x) |
| Any NegativeDuration WKT JSON stringify | 135.63 | — | — | 1953.96 (14.41x) | 1005.37 (7.41x) |
| Any NegativeDuration WKT JSON parse | 522.51 | — | — | 3106.81 (5.95x) | 1572.99 (3.01x) |
| Any FractionalNegativeDuration WKT JSON stringify | 128.30 | — | — | 1920.31 (14.97x) | 1072.86 (8.36x) |
| Any FractionalNegativeDuration WKT JSON parse | 514.40 | — | — | 3054.08 (5.94x) | 1583.93 (3.08x) |
| Any MaxDuration WKT JSON stringify | 117.63 | — | — | 1762.67 (14.98x) | 945.16 (8.04x) |
| Any MaxDuration WKT JSON parse | 531.56 | — | — | 2974.24 (5.60x) | 1415.07 (2.66x) |
| Any MinDuration WKT JSON stringify | 121.88 | — | — | 1777.47 (14.58x) | 973.11 (7.98x) |
| Any MinDuration WKT JSON parse | 532.39 | — | — | 3035.97 (5.70x) | 1477.17 (2.77x) |
| Any ZeroDuration WKT JSON stringify | 113.27 | — | — | 931.12 (8.22x) | 963.62 (8.51x) |
| Any ZeroDuration WKT JSON parse | 462.26 | — | — | 2262.09 (4.89x) | 1421.09 (3.07x) |
| Any FieldMask WKT JSON stringify | 225.06 | — | — | 1753.53 (7.79x) | 1393.21 (6.19x) |
| Any FieldMask WKT JSON parse | 709.64 | — | — | 3156.71 (4.45x) | 1904.15 (2.68x) |
| Any FieldMask Escape WKT JSON parse | 727.28 | — | — | 3250.26 (4.47x) | 2155.99 (2.96x) |
| Any EmptyFieldMask WKT JSON stringify | 116.53 | — | — | 933.04 (8.01x) | 738.90 (6.34x) |
| Any EmptyFieldMask WKT JSON parse | 435.08 | — | — | 2160.06 (4.96x) | 1174.86 (2.70x) |
| Any Timestamp WKT JSON stringify | 181.56 | — | — | 2049.56 (11.29x) | 1063.96 (5.86x) |
| Any Timestamp WKT JSON parse | 562.73 | — | — | 3033.52 (5.39x) | 1524.48 (2.71x) |
| Any Timestamp Escape WKT JSON parse | 580.47 | — | — | 3084.83 (5.31x) | 1756.19 (3.03x) |
| Any ShortFraction Timestamp WKT JSON parse | 558.63 | — | — | 3021.98 (5.41x) | 1820.05 (3.26x) |
| Any Micro Timestamp WKT JSON stringify | 183.08 | — | — | 2046.56 (11.18x) | 1286.77 (7.03x) |
| Any Micro Timestamp WKT JSON parse | 577.10 | — | — | 3049.01 (5.28x) | 11779.55 (20.41x) |
| Any Nano Timestamp WKT JSON stringify | 187.63 | — | — | 2051.91 (10.94x) | 7348.65 (39.17x) |
| Any Nano Timestamp WKT JSON parse | 581.23 | — | — | 3053.29 (5.25x) | 4847.38 (8.34x) |
| Any Offset Timestamp WKT JSON parse | 589.04 | — | — | 3059.73 (5.19x) | 3531.93 (6.00x) |
| Any PreEpoch Timestamp WKT JSON stringify | 149.86 | — | — | 2816.13 (18.79x) | 2043.15 (13.63x) |
| Any PreEpoch Timestamp WKT JSON parse | 554.23 | — | — | 4532.61 (8.18x) | 2304.65 (4.16x) |
| Any Max Timestamp WKT JSON stringify | 166.59 | — | — | 2114.34 (12.69x) | 1297.40 (7.79x) |
| Any Max Timestamp WKT JSON parse | 754.99 | — | — | 3122.32 (4.14x) | 1835.36 (2.43x) |
| Any Min Timestamp WKT JSON stringify | 344.22 | — | — | 1951.75 (5.67x) | 1084.34 (3.15x) |
| Any Min Timestamp WKT JSON parse | 922.98 | — | — | 3042.13 (3.30x) | 1671.49 (1.81x) |
| Any Empty WKT JSON stringify | 165.13 | — | — | 937.58 (5.68x) | 623.73 (3.78x) |
| Any Empty WKT JSON parse | 504.62 | — | — | 2142.69 (4.25x) | 1322.89 (2.62x) |
| Any Struct WKT JSON stringify | 645.91 | — | — | 5819.11 (9.01x) | 6926.13 (10.72x) |
| Any Struct WKT JSON parse | 1876.96 | — | — | 11116.00 (5.92x) | 16369.37 (8.72x) |
| Any Struct Escape WKT JSON parse | 2028.71 | — | — | 11231.30 (5.54x) | 10202.83 (5.03x) |
| Any Struct NumberExponent WKT JSON parse | 1976.69 | — | — | 11165.40 (5.65x) | 18398.95 (9.31x) |
| Any EmptyStruct WKT JSON stringify | 128.05 | — | — | 919.60 (7.18x) | 1173.43 (9.16x) |
| Any EmptyStruct WKT JSON parse | 446.04 | — | — | 2235.57 (5.01x) | 2098.95 (4.71x) |
| Any Value WKT JSON stringify | 680.08 | — | — | 5846.04 (8.60x) | 7851.34 (11.54x) |
| Any Value WKT JSON parse | 1814.69 | — | — | 11380.70 (6.27x) | 10724.39 (5.91x) |
| Any Value Escape WKT JSON parse | 1835.93 | — | — | 11511.60 (6.27x) | 10434.67 (5.68x) |
| Any Value NumberExponent WKT JSON parse | 1813.41 | — | — | 11359.00 (6.26x) | 10045.92 (5.54x) |
| Any NullValue WKT JSON stringify | 123.38 | — | — | 2269.80 (18.40x) | 1025.00 (8.31x) |
| Any NullValue WKT JSON parse | 462.23 | — | — | 4062.01 (8.79x) | 1714.37 (3.71x) |
| Any StringScalarValue WKT JSON stringify | 152.02 | — | — | 2284.44 (15.03x) | 1004.65 (6.61x) |
| Any StringScalarValue WKT JSON parse | 518.35 | — | — | 3644.46 (7.03x) | 1811.47 (3.49x) |
| Any StringScalarValue Escape WKT JSON parse | 531.52 | — | — | 3677.01 (6.92x) | 1732.29 (3.26x) |
| Any EmptyStringScalarValue WKT JSON stringify | 140.19 | — | — | 2285.63 (16.30x) | 1175.85 (8.39x) |
| Any EmptyStringScalarValue WKT JSON parse | 487.71 | — | — | 3627.47 (7.44x) | 1536.94 (3.15x) |
| Any NumberValue WKT JSON stringify | 185.94 | — | — | 2538.77 (13.65x) | 1137.28 (6.12x) |
| Any NumberValue WKT JSON parse | 501.93 | — | — | 3692.07 (7.36x) | 1715.92 (3.42x) |
| Any NumberValue Exponent WKT JSON parse | 504.43 | — | — | 3704.39 (7.34x) | 1621.81 (3.22x) |
| Any NegativeNumberValue WKT JSON stringify | 180.59 | — | — | 2531.30 (14.02x) | 1276.70 (7.07x) |
| Any NegativeNumberValue WKT JSON parse | 503.38 | — | — | 3701.95 (7.35x) | 1906.59 (3.79x) |
| Any ZeroNumberValue WKT JSON stringify | 145.58 | — | — | 2481.95 (17.05x) | 965.06 (6.63x) |
| Any ZeroNumberValue WKT JSON parse | 499.23 | — | — | 3624.14 (7.26x) | 1490.03 (2.98x) |
| Any BoolScalarValue WKT JSON stringify | 135.13 | — | — | 2275.13 (16.84x) | 980.83 (7.26x) |
| Any BoolScalarValue WKT JSON parse | 462.41 | — | — | 3600.60 (7.79x) | 1634.92 (3.54x) |
| Any FalseBoolScalarValue WKT JSON stringify | 133.95 | — | — | 2266.52 (16.92x) | 1008.36 (7.53x) |
| Any FalseBoolScalarValue WKT JSON parse | 462.17 | — | — | 3616.71 (7.83x) | 1538.57 (3.33x) |
| Any ListKindValue WKT JSON stringify | 510.59 | — | — | 5673.42 (11.11x) | 5199.98 (10.18x) |
| Any ListKindValue WKT JSON parse | 1397.24 | — | — | 9944.59 (7.12x) | 7316.67 (5.24x) |
| Any ListKindValue Escape WKT JSON parse | 1421.76 | — | — | 10026.40 (7.05x) | 7672.49 (5.40x) |
| Any EmptyStructKindValue WKT JSON stringify | 144.97 | — | — | 2968.10 (20.47x) | 1413.26 (9.75x) |
| Any EmptyStructKindValue WKT JSON parse | 501.96 | — | — | 5394.37 (10.75x) | 1913.88 (3.81x) |
| Any EmptyListKindValue WKT JSON stringify | 141.06 | — | — | 2890.97 (20.49x) | 1185.17 (8.40x) |
| Any EmptyListKindValue WKT JSON parse | 502.45 | — | — | 4393.72 (8.74x) | 1696.49 (3.38x) |
| Any DoubleValue WKT JSON stringify | 187.59 | — | — | 1867.09 (9.95x) | 811.63 (4.33x) |
| Any DoubleValue WKT JSON parse | 518.37 | — | — | 2734.11 (5.27x) | 1379.24 (2.66x) |
| Any DoubleValue String WKT JSON parse | 528.81 | — | — | 2730.60 (5.16x) | 1532.04 (2.90x) |
| Any DoubleValue Exponent WKT JSON parse | 522.53 | — | — | 2741.84 (5.25x) | 1414.43 (2.71x) |
| Any NegativeDoubleValue WKT JSON stringify | 191.97 | — | — | 1792.19 (9.34x) | 836.09 (4.36x) |
| Any NegativeDoubleValue WKT JSON parse | 517.68 | — | — | 2738.41 (5.29x) | 1340.69 (2.59x) |
| Any ZeroDoubleValue WKT JSON stringify | 165.74 | — | — | 922.01 (5.56x) | 754.54 (4.55x) |
| Any ZeroDoubleValue WKT JSON parse | 515.48 | — | — | 2168.22 (4.21x) | 1405.02 (2.73x) |
| Any DoubleValue NaN WKT JSON stringify | 155.01 | — | — | 1569.55 (10.13x) | 739.50 (4.77x) |
| Any DoubleValue NaN WKT JSON parse | 512.07 | — | — | 2648.45 (5.17x) | 1457.30 (2.85x) |
| Any DoubleValue Infinity WKT JSON stringify | 164.49 | — | — | 1564.86 (9.51x) | 712.61 (4.33x) |
| Any DoubleValue Infinity WKT JSON parse | 517.09 | — | — | 2691.87 (5.21x) | 1397.77 (2.70x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 161.21 | — | — | 1563.53 (9.70x) | 707.64 (4.39x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 517.81 | — | — | 2833.31 (5.47x) | 1343.50 (2.59x) |
| Any FloatValue WKT JSON stringify | 204.93 | — | — | 1732.85 (8.46x) | 784.28 (3.83x) |
| Any FloatValue WKT JSON parse | 519.86 | — | — | 2707.14 (5.21x) | 1435.34 (2.76x) |
| Any FloatValue String WKT JSON parse | 523.97 | — | — | 2709.33 (5.17x) | 1627.80 (3.11x) |
| Any FloatValue Exponent WKT JSON parse | 517.95 | — | — | 2707.81 (5.23x) | 1539.21 (2.97x) |
| Any NegativeFloatValue WKT JSON stringify | 197.33 | — | — | 1733.09 (8.78x) | 769.04 (3.90x) |
| Any NegativeFloatValue WKT JSON parse | 517.72 | — | — | 2703.10 (5.22x) | 1351.24 (2.61x) |
| Any ZeroFloatValue WKT JSON stringify | 173.40 | — | — | 909.71 (5.25x) | 686.62 (3.96x) |
| Any ZeroFloatValue WKT JSON parse | 514.49 | — | — | 2155.43 (4.19x) | 1440.28 (2.80x) |
| Any FloatValue NaN WKT JSON stringify | 157.99 | — | — | 1562.64 (9.89x) | 719.75 (4.56x) |
| Any FloatValue NaN WKT JSON parse | 511.62 | — | — | 2622.34 (5.13x) | 1574.06 (3.08x) |
| Any FloatValue Infinity WKT JSON stringify | 168.91 | — | — | 1548.35 (9.17x) | 699.43 (4.14x) |
| Any FloatValue Infinity WKT JSON parse | 512.97 | — | — | 2661.89 (5.19x) | 1269.60 (2.47x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 169.50 | — | — | 1542.60 (9.10x) | 691.25 (4.08x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 516.51 | — | — | 2643.63 (5.12x) | 1490.59 (2.89x) |
| Any Int64Value WKT JSON stringify | 170.86 | — | — | 1558.08 (9.12x) | 838.26 (4.91x) |
| Any Int64Value WKT JSON parse | 552.52 | — | — | 2778.86 (5.03x) | 1869.16 (3.38x) |
| Any Int64Value Number WKT JSON parse | 559.95 | — | — | 2748.15 (4.91x) | 1619.41 (2.89x) |
| Any ZeroInt64Value WKT JSON stringify | 165.95 | — | — | 910.03 (5.48x) | 798.95 (4.81x) |
| Any ZeroInt64Value WKT JSON parse | 523.15 | — | — | 2157.39 (4.12x) | 1514.05 (2.89x) |
| Any NegativeInt64Value WKT JSON stringify | 173.67 | — | — | 1559.25 (8.98x) | 906.27 (5.22x) |
| Any NegativeInt64Value WKT JSON parse | 550.81 | — | — | 2800.21 (5.08x) | 1529.99 (2.78x) |
| Any MinInt64Value WKT JSON stringify | 175.05 | — | — | 1558.50 (8.90x) | 947.50 (5.41x) |
| Any MinInt64Value WKT JSON parse | 556.55 | — | — | 2811.99 (5.05x) | 1621.27 (2.91x) |
| Any MaxInt64Value WKT JSON stringify | 173.75 | — | — | 1556.50 (8.96x) | 813.98 (4.68x) |
| Any MaxInt64Value WKT JSON parse | 558.47 | — | — | 2803.95 (5.02x) | 1618.91 (2.90x) |
| Any UInt64Value WKT JSON stringify | 179.22 | — | — | 1551.36 (8.66x) | 860.55 (4.80x) |
| Any UInt64Value WKT JSON parse | 549.29 | — | — | 2790.24 (5.08x) | 1562.76 (2.85x) |
| Any UInt64Value Number WKT JSON parse | 560.59 | — | — | 2756.73 (4.92x) | 1592.78 (2.84x) |
| Any ZeroUInt64Value WKT JSON stringify | 172.03 | — | — | 914.08 (5.31x) | 830.92 (4.83x) |
| Any ZeroUInt64Value WKT JSON parse | 522.57 | — | — | 2158.56 (4.13x) | 1380.62 (2.64x) |
| Any MaxUInt64Value WKT JSON stringify | 183.78 | — | — | 1557.40 (8.47x) | 5035.34 (27.40x) |
| Any MaxUInt64Value WKT JSON parse | 555.78 | — | — | 2832.42 (5.10x) | 3704.12 (6.66x) |
| Any Int32Value WKT JSON stringify | 173.16 | — | — | 1546.39 (8.93x) | 1323.61 (7.64x) |
| Any Int32Value WKT JSON parse | 532.20 | — | — | 2665.40 (5.01x) | 2462.85 (4.63x) |
| Any Int32Value String WKT JSON parse | 535.91 | — | — | 2668.07 (4.98x) | 3335.19 (6.22x) |
| Any ZeroInt32Value WKT JSON stringify | 175.13 | — | — | 911.56 (5.21x) | 1069.72 (6.11x) |
| Any ZeroInt32Value WKT JSON parse | 527.55 | — | — | 2148.24 (4.07x) | 2695.92 (5.11x) |
| Any NegativeInt32Value WKT JSON stringify | 182.15 | — | — | 1548.20 (8.50x) | 1273.70 (6.99x) |
| Any NegativeInt32Value WKT JSON parse | 531.39 | — | — | 2689.03 (5.06x) | 2130.65 (4.01x) |
| Any MinInt32Value WKT JSON stringify | 179.03 | — | — | 1558.61 (8.71x) | 966.53 (5.40x) |
| Any MinInt32Value WKT JSON parse | 536.94 | — | — | 2700.61 (5.03x) | 1882.85 (3.51x) |
| Any MaxInt32Value WKT JSON stringify | 180.45 | — | — | 1548.89 (8.58x) | 1521.68 (8.43x) |
| Any MaxInt32Value WKT JSON parse | 537.04 | — | — | 2683.05 (5.00x) | 3401.99 (6.33x) |
| Any UInt32Value WKT JSON stringify | 179.34 | — | — | 1549.81 (8.64x) | 1326.47 (7.40x) |
| Any UInt32Value WKT JSON parse | 535.66 | — | — | 2676.01 (5.00x) | 3162.06 (5.90x) |
| Any UInt32Value String WKT JSON parse | 542.01 | — | — | 2665.67 (4.92x) | 3100.89 (5.72x) |
| Any ZeroUInt32Value WKT JSON stringify | 182.67 | — | — | 915.21 (5.01x) | 1181.59 (6.47x) |
| Any ZeroUInt32Value WKT JSON parse | 531.98 | — | — | 2160.45 (4.06x) | 2706.73 (5.09x) |
| Any MaxUInt32Value WKT JSON stringify | 180.86 | — | — | 1557.30 (8.61x) | 1166.66 (6.45x) |
| Any MaxUInt32Value WKT JSON parse | 542.42 | — | — | 2683.35 (4.95x) | 3867.48 (7.13x) |
| Any BoolValue WKT JSON stringify | 174.07 | — | — | 1523.18 (8.75x) | 1848.72 (10.62x) |
| Any BoolValue WKT JSON parse | 484.68 | — | — | 4025.19 (8.30x) | 2641.01 (5.45x) |
| Any FalseBoolValue WKT JSON stringify | 181.32 | — | — | 910.90 (5.02x) | 1753.10 (9.67x) |
| Any FalseBoolValue WKT JSON parse | 483.89 | — | — | 2166.85 (4.48x) | 1933.31 (4.00x) |
| Any StringValue WKT JSON stringify | 203.79 | — | — | 1569.26 (7.70x) | 774.08 (3.80x) |
| Any StringValue WKT JSON parse | 545.38 | — | — | 2665.24 (4.89x) | 1327.96 (2.43x) |
| Any StringValue Escape WKT JSON parse | 550.51 | — | — | 2693.47 (4.89x) | 1852.73 (3.37x) |
| Any EmptyStringValue WKT JSON stringify | 193.67 | — | — | 918.11 (4.74x) | 706.10 (3.65x) |
| Any EmptyStringValue WKT JSON parse | 514.69 | — | — | 2168.49 (4.21x) | 1373.09 (2.67x) |
| Any BytesValue WKT JSON stringify | 187.65 | — | — | 1843.49 (9.82x) | 840.91 (4.48x) |
| Any BytesValue WKT JSON parse | 561.29 | — | — | 2696.02 (4.80x) | 1417.05 (2.52x) |
| Any BytesValue URL WKT JSON parse | 576.50 | — | — | 2723.87 (4.72x) | 1469.62 (2.55x) |
| Any EmptyBytesValue WKT JSON stringify | 187.23 | — | — | 924.66 (4.94x) | 770.36 (4.11x) |
| Any EmptyBytesValue WKT JSON parse | 520.74 | — | — | 2170.11 (4.17x) | 1357.27 (2.61x) |
| Nested Any WKT JSON stringify | 303.39 | — | — | 2497.93 (8.23x) | 1414.82 (4.66x) |
| Nested Any WKT JSON parse | 852.62 | — | — | 4282.48 (5.02x) | 2640.04 (3.10x) |
| Duration JSON stringify | 57.15 | — | — | 956.29 (16.73x) | 348.86 (6.10x) |
| Duration JSON parse | 18.93 | — | — | 1449.60 (76.58x) | 394.89 (20.86x) |
| Duration Escape JSON parse | 42.15 | — | — | 1485.16 (35.24x) | 420.07 (9.97x) |
| PlusDuration JSON parse | 18.56 | — | — | 1452.99 (78.29x) | 387.97 (20.90x) |
| ShortFractionDuration JSON parse | 15.86 | — | — | 1418.44 (89.44x) | 375.03 (23.65x) |
| MicroDuration JSON stringify | 58.94 | — | — | 969.37 (16.45x) | 380.23 (6.45x) |
| MicroDuration JSON parse | 20.81 | — | — | 1467.43 (70.52x) | 379.92 (18.26x) |
| NanoDuration JSON stringify | 56.78 | — | — | 987.01 (17.38x) | 395.06 (6.96x) |
| NanoDuration JSON parse | 22.07 | — | — | 1474.86 (66.83x) | 384.60 (17.43x) |
| NegativeDuration JSON stringify | 58.31 | — | — | 1003.06 (17.20x) | 414.15 (7.10x) |
| NegativeDuration JSON parse | 17.85 | — | — | 1503.26 (84.22x) | 360.84 (20.22x) |
| FractionalNegativeDuration JSON stringify | 57.74 | — | — | 968.36 (16.77x) | 407.48 (7.06x) |
| FractionalNegativeDuration JSON parse | 19.07 | — | — | 1456.92 (76.40x) | 371.19 (19.46x) |
| MaxDuration JSON stringify | 49.29 | — | — | 848.09 (17.21x) | 389.30 (7.90x) |
| MaxDuration JSON parse | 32.84 | — | — | 1431.44 (43.59x) | 406.05 (12.36x) |
| MinDuration JSON stringify | 49.48 | — | — | 866.39 (17.51x) | 412.19 (8.33x) |
| MinDuration JSON parse | 33.41 | — | — | 1444.67 (43.24x) | 370.25 (11.08x) |
| ZeroDuration JSON stringify | 44.36 | — | — | 805.76 (18.16x) | 323.16 (7.28x) |
| ZeroDuration JSON parse | 17.06 | — | — | 1365.05 (80.01x) | 290.62 (17.04x) |
| FieldMask JSON stringify | 103.30 | — | — | 880.72 (8.53x) | 620.24 (6.00x) |
| FieldMask JSON parse | 139.00 | — | — | 1647.65 (11.85x) | 816.64 (5.88x) |
| FieldMask Escape JSON parse | 189.01 | — | — | 1704.27 (9.02x) | 894.17 (4.73x) |
| EmptyFieldMask JSON stringify | 40.94 | — | — | 610.32 (14.91x) | 183.71 (4.49x) |
| EmptyFieldMask JSON parse | 4.79 | — | — | 948.43 (198.00x) | 151.42 (31.61x) |
| Timestamp JSON stringify | 96.57 | — | — | 1134.60 (11.75x) | 408.64 (4.23x) |
| Timestamp JSON parse | 46.01 | — | — | 1494.26 (32.48x) | 408.65 (8.88x) |
| Timestamp Escape JSON parse | 83.47 | — | — | 1522.36 (18.24x) | 490.84 (5.88x) |
| ShortFraction Timestamp JSON parse | 43.77 | — | — | 1482.45 (33.87x) | 421.16 (9.62x) |
| Micro Timestamp JSON stringify | 96.02 | — | — | 1157.11 (12.05x) | 472.05 (4.92x) |
| Micro Timestamp JSON parse | 48.42 | — | — | 1614.01 (33.33x) | 441.14 (9.11x) |
| Nano Timestamp JSON stringify | 93.70 | — | — | 1178.72 (12.58x) | 447.31 (4.77x) |
| Nano Timestamp JSON parse | 52.62 | — | — | 1522.03 (28.92x) | 445.55 (8.47x) |
| Offset Timestamp JSON parse | 54.66 | — | — | 1534.24 (28.07x) | 462.39 (8.46x) |
| PreEpoch Timestamp JSON stringify | 66.27 | — | — | 1071.00 (16.16x) | 401.64 (6.06x) |
| PreEpoch Timestamp JSON parse | 42.99 | — | — | 1460.99 (33.98x) | 391.06 (9.10x) |
| Max Timestamp JSON stringify | 78.73 | — | — | 1187.91 (15.09x) | 430.30 (5.47x) |
| Max Timestamp JSON parse | 51.15 | — | — | 1536.13 (30.03x) | 420.54 (8.22x) |
| Min Timestamp JSON stringify | 79.96 | — | — | 1054.24 (13.18x) | 390.15 (4.88x) |
| Min Timestamp JSON parse | 41.09 | — | — | 1453.51 (35.37x) | 421.54 (10.26x) |
| Empty JSON stringify | 20.59 | — | — | 494.96 (24.04x) | 79.20 (3.85x) |
| Empty JSON parse | 67.19 | — | — | 716.53 (10.66x) | 185.94 (2.77x) |
| Struct JSON stringify | 183.42 | — | — | 5713.31 (31.15x) | 2880.77 (15.71x) |
| Struct JSON parse | 853.97 | — | — | 10889.30 (12.75x) | 4770.64 (5.59x) |
| Struct Escape JSON parse | 887.42 | — | — | 11034.80 (12.43x) | 4730.65 (5.33x) |
| Struct NumberExponent JSON parse | 846.09 | — | — | 10966.50 (12.96x) | 4880.53 (5.77x) |
| EmptyStruct JSON stringify | 40.66 | — | — | 702.42 (17.28x) | 323.08 (7.95x) |
| EmptyStruct JSON parse | 87.50 | — | — | 2025.60 (23.15x) | 340.92 (3.90x) |
| Value JSON stringify | 188.17 | — | — | 6583.98 (34.99x) | 3016.62 (16.03x) |
| Value JSON parse | 868.92 | — | — | 12152.40 (13.99x) | 4534.84 (5.22x) |
| Value Escape JSON parse | 922.85 | — | — | 12277.00 (13.30x) | 5022.64 (5.44x) |
| Value NumberExponent JSON parse | 867.65 | — | — | 12208.90 (14.07x) | 5263.15 (6.07x) |
| NullValue JSON stringify | 40.50 | — | — | 1315.28 (32.48x) | 226.61 (5.60x) |
| NullValue JSON parse | 70.30 | — | — | 2457.24 (34.95x) | 308.83 (4.39x) |
| StringScalarValue JSON stringify | 47.44 | — | — | 1339.34 (28.23x) | 276.59 (5.83x) |
| StringScalarValue JSON parse | 139.99 | — | — | 2092.27 (14.95x) | 394.31 (2.82x) |
| StringScalarValue Escape JSON parse | 150.29 | — | — | 2129.12 (14.17x) | 450.04 (2.99x) |
| EmptyStringScalarValue JSON stringify | 45.46 | — | — | 1330.31 (29.26x) | 261.59 (5.75x) |
| EmptyStringScalarValue JSON parse | 87.56 | — | — | 2086.59 (23.83x) | 328.70 (3.75x) |
| NumberValue JSON stringify | 73.60 | — | — | 1554.81 (21.13x) | 344.35 (4.68x) |
| NumberValue JSON parse | 132.54 | — | — | 2177.88 (16.43x) | 393.62 (2.97x) |
| NumberValue Exponent JSON parse | 134.94 | — | — | 2190.37 (16.23x) | 400.80 (2.97x) |
| NegativeNumberValue JSON stringify | 74.21 | — | — | 1550.35 (20.89x) | 337.19 (4.54x) |
| NegativeNumberValue JSON parse | 133.34 | — | — | 2187.02 (16.40x) | 395.54 (2.97x) |
| ZeroNumberValue JSON stringify | 50.99 | — | — | 1512.02 (29.65x) | 273.95 (5.37x) |
| ZeroNumberValue JSON parse | 130.53 | — | — | 2143.66 (16.42x) | 373.35 (2.86x) |
| BoolScalarValue JSON stringify | 40.27 | — | — | 1311.13 (32.56x) | 207.89 (5.16x) |
| BoolScalarValue JSON parse | 70.16 | — | — | 2027.87 (28.90x) | 316.75 (4.51x) |
| FalseBoolScalarValue JSON stringify | 40.26 | — | — | 1312.70 (32.61x) | 221.61 (5.50x) |
| FalseBoolScalarValue JSON parse | 70.76 | — | — | 2029.07 (28.68x) | 488.53 (6.90x) |
| ListKindValue JSON stringify | 146.28 | — | — | 6245.87 (42.70x) | 2146.69 (14.68x) |
| ListKindValue JSON parse | 678.19 | — | — | 10424.40 (15.37x) | 4060.03 (5.99x) |
| ListKindValue Escape JSON parse | 699.65 | — | — | 10534.50 (15.06x) | 4166.32 (5.95x) |
| EmptyStructKindValue JSON stringify | 42.16 | — | — | 1936.40 (45.93x) | 504.96 (11.98x) |
| EmptyStructKindValue JSON parse | 110.73 | — | — | 3741.95 (33.79x) | 633.19 (5.72x) |
| EmptyListKindValue JSON stringify | 41.05 | — | — | 1940.14 (47.26x) | 338.30 (8.24x) |
| EmptyListKindValue JSON parse | 148.11 | — | — | 4023.18 (27.16x) | 542.98 (3.67x) |
| ListValue JSON stringify | 144.41 | — | — | 4745.03 (32.86x) | 1977.68 (13.69x) |
| ListValue JSON parse | 658.33 | — | — | 8553.13 (12.99x) | 3733.95 (5.67x) |
| ListValue Escape JSON parse | 675.20 | — | — | 8633.64 (12.79x) | 3841.03 (5.69x) |
| EmptyListValue JSON stringify | 39.78 | — | — | 697.18 (17.53x) | 198.46 (4.99x) |
| EmptyListValue JSON parse | 125.25 | — | — | 2250.34 (17.97x) | 301.06 (2.40x) |
| DoubleValue JSON stringify | 67.48 | — | — | 858.02 (12.72x) | 184.70 (2.74x) |
| DoubleValue JSON parse | 111.88 | — | — | 1226.83 (10.97x) | 282.25 (2.52x) |
| DoubleValue String JSON parse | 110.65 | — | — | 1168.54 (10.56x) | 336.13 (3.04x) |
| DoubleValue Exponent JSON parse | 112.94 | — | — | 1237.40 (10.96x) | 276.42 (2.45x) |
| NegativeDoubleValue JSON stringify | 68.30 | — | — | 855.62 (12.53x) | 210.45 (3.08x) |
| NegativeDoubleValue JSON parse | 111.21 | — | — | 1237.50 (11.13x) | 282.66 (2.54x) |
| ZeroDoubleValue JSON stringify | 47.19 | — | — | 795.57 (16.86x) | 133.45 (2.83x) |
| ZeroDoubleValue JSON parse | 109.88 | — | — | 1168.21 (10.63x) | 253.21 (2.30x) |
| DoubleValue NaN JSON stringify | 45.94 | — | — | 660.82 (14.38x) | 119.90 (2.61x) |
| DoubleValue NaN JSON parse | 104.36 | — | — | 1095.96 (10.50x) | 263.67 (2.53x) |
| DoubleValue Infinity JSON stringify | 47.37 | — | — | 660.77 (13.95x) | 125.16 (2.64x) |
| DoubleValue Infinity JSON parse | 105.69 | — | — | 1103.24 (10.44x) | 254.40 (2.41x) |
| DoubleValue NegativeInfinity JSON stringify | 47.61 | — | — | 652.78 (13.71x) | 114.53 (2.41x) |
| DoubleValue NegativeInfinity JSON parse | 108.11 | — | — | 1110.91 (10.28x) | 253.46 (2.34x) |
| FloatValue JSON stringify | 71.36 | — | — | 804.67 (11.28x) | 178.93 (2.51x) |
| FloatValue JSON parse | 112.02 | — | — | 1212.74 (10.83x) | 265.42 (2.37x) |
| FloatValue String JSON parse | 111.15 | — | — | 1153.02 (10.37x) | 349.25 (3.14x) |
| FloatValue Exponent JSON parse | 113.71 | — | — | 1222.05 (10.75x) | 284.67 (2.50x) |
| NegativeFloatValue JSON stringify | 71.23 | — | — | 807.62 (11.34x) | 176.41 (2.48x) |
| NegativeFloatValue JSON parse | 112.17 | — | — | 1215.70 (10.84x) | 285.12 (2.54x) |
| ZeroFloatValue JSON stringify | 47.16 | — | — | 753.76 (15.98x) | 135.23 (2.87x) |
| ZeroFloatValue JSON parse | 108.13 | — | — | 1150.90 (10.64x) | 250.65 (2.32x) |
| FloatValue NaN JSON stringify | 46.04 | — | — | 646.15 (14.03x) | 122.51 (2.66x) |
| FloatValue NaN JSON parse | 104.85 | — | — | 1079.31 (10.29x) | 250.79 (2.39x) |
| FloatValue Infinity JSON stringify | 47.48 | — | — | 647.79 (13.64x) | 115.67 (2.44x) |
| FloatValue Infinity JSON parse | 105.87 | — | — | 1090.09 (10.30x) | 251.23 (2.37x) |
| FloatValue NegativeInfinity JSON stringify | 47.66 | — | — | 646.75 (13.57x) | 119.26 (2.50x) |
| FloatValue NegativeInfinity JSON parse | 108.14 | — | — | 1092.65 (10.10x) | 248.70 (2.30x) |
| Int64Value JSON stringify | 50.07 | — | — | 691.80 (13.82x) | 268.49 (5.36x) |
| Int64Value JSON parse | 127.03 | — | — | 1227.90 (9.67x) | 406.85 (3.20x) |
| Int64Value Number JSON parse | 127.03 | — | — | 1282.01 (10.09x) | 342.37 (2.70x) |
| ZeroInt64Value JSON stringify | 41.47 | — | — | 629.47 (15.18x) | 185.60 (4.48x) |
| ZeroInt64Value JSON parse | 105.64 | — | — | 1096.18 (10.38x) | 339.55 (3.21x) |
| NegativeInt64Value JSON stringify | 48.46 | — | — | 694.94 (14.34x) | 258.96 (5.34x) |
| NegativeInt64Value JSON parse | 128.39 | — | — | 1218.94 (9.49x) | 450.35 (3.51x) |
| MinInt64Value JSON stringify | 50.13 | — | — | 691.88 (13.80x) | 263.27 (5.25x) |
| MinInt64Value JSON parse | 134.23 | — | — | 1259.86 (9.39x) | 448.46 (3.34x) |
| MaxInt64Value JSON stringify | 49.23 | — | — | 693.43 (14.09x) | 261.20 (5.31x) |
| MaxInt64Value JSON parse | 134.41 | — | — | 1249.60 (9.30x) | 454.50 (3.38x) |
| UInt64Value JSON stringify | 50.43 | — | — | 676.39 (13.41x) | 268.87 (5.33x) |
| UInt64Value JSON parse | 124.87 | — | — | 1219.61 (9.77x) | 450.80 (3.61x) |
| UInt64Value Number JSON parse | 126.46 | — | — | 1282.33 (10.14x) | 325.98 (2.58x) |
| ZeroUInt64Value JSON stringify | 41.72 | — | — | 610.01 (14.62x) | 188.84 (4.53x) |
| ZeroUInt64Value JSON parse | 103.20 | — | — | 1095.82 (10.62x) | 318.67 (3.09x) |
| MaxUInt64Value JSON stringify | 50.18 | — | — | 816.51 (16.27x) | 269.71 (5.37x) |
| MaxUInt64Value JSON parse | 136.40 | — | — | 1254.52 (9.20x) | 530.28 (3.89x) |
| Int32Value JSON stringify | 46.04 | — | — | 643.21 (13.97x) | 248.59 (5.40x) |
| Int32Value JSON parse | 117.73 | — | — | 1177.35 (10.00x) | 424.30 (3.60x) |
| Int32Value String JSON parse | 114.41 | — | — | 1124.61 (9.83x) | 495.64 (4.33x) |
| ZeroInt32Value JSON stringify | 45.92 | — | — | 626.71 (13.65x) | 228.93 (4.99x) |
| ZeroInt32Value JSON parse | 113.61 | — | — | 1153.11 (10.15x) | 817.20 (7.19x) |
| NegativeInt32Value JSON stringify | 45.92 | — | — | 654.43 (14.25x) | 280.70 (6.11x) |
| NegativeInt32Value JSON parse | 117.36 | — | — | 1192.50 (10.16x) | 428.24 (3.65x) |
| MinInt32Value JSON stringify | 47.14 | — | — | 651.30 (13.82x) | 177.60 (3.77x) |
| MinInt32Value JSON parse | 123.43 | — | — | 1214.00 (9.84x) | 416.64 (3.38x) |
| MaxInt32Value JSON stringify | 46.88 | — | — | 648.50 (13.83x) | 269.04 (5.74x) |
| MaxInt32Value JSON parse | 123.61 | — | — | 1198.45 (9.70x) | 429.83 (3.48x) |
| UInt32Value JSON stringify | 46.02 | — | — | 636.26 (13.83x) | 224.55 (4.88x) |
| UInt32Value JSON parse | 118.27 | — | — | 1182.36 (10.00x) | 534.89 (4.52x) |
| UInt32Value String JSON parse | 115.07 | — | — | 1128.97 (9.81x) | 770.20 (6.69x) |
| ZeroUInt32Value JSON stringify | 45.94 | — | — | 617.42 (13.44x) | 237.70 (5.17x) |
| ZeroUInt32Value JSON parse | 113.42 | — | — | 1151.70 (10.15x) | 335.98 (2.96x) |
| MaxUInt32Value JSON stringify | 46.46 | — | — | 633.00 (13.62x) | 354.32 (7.63x) |
| MaxUInt32Value JSON parse | 123.61 | — | — | 1204.06 (9.74x) | 460.65 (3.73x) |
| BoolValue JSON stringify | 44.57 | — | — | 611.54 (13.72x) | 432.58 (9.71x) |
| BoolValue JSON parse | 59.89 | — | — | 1050.05 (17.53x) | 819.17 (13.68x) |
| FalseBoolValue JSON stringify | 44.22 | — | — | 609.37 (13.78x) | 239.76 (5.42x) |
| FalseBoolValue JSON parse | 59.89 | — | — | 1056.72 (17.64x) | 278.47 (4.65x) |
| StringValue JSON stringify | 51.38 | — | — | 654.24 (12.73x) | 247.90 (4.82x) |
| StringValue JSON parse | 122.81 | — | — | 1154.02 (9.40x) | 360.15 (2.93x) |
| StringValue Escape JSON parse | 130.29 | — | — | 1169.03 (8.97x) | 366.49 (2.81x) |
| EmptyStringValue JSON stringify | 48.60 | — | — | 617.92 (12.71x) | 169.77 (3.49x) |
| EmptyStringValue JSON parse | 66.00 | — | — | 1111.66 (16.84x) | 229.84 (3.48x) |
| BytesValue JSON stringify | 50.08 | — | — | 669.15 (13.36x) | 202.95 (4.05x) |
| BytesValue JSON parse | 124.68 | — | — | 1169.98 (9.38x) | 321.70 (2.58x) |
| BytesValue URL JSON parse | 140.57 | — | — | 1164.40 (8.28x) | 312.15 (2.22x) |
| EmptyBytesValue JSON stringify | 41.61 | — | — | 643.15 (15.46x) | 175.53 (4.22x) |
| EmptyBytesValue JSON parse | 67.67 | — | — | 1121.54 (16.57x) | 281.29 (4.16x) |
| TextFormat format | 175.13 | — | — | 2615.92 (14.94x) | 2455.75 (14.02x) |
| TextFormat parse | 694.79 | — | — | 5014.67 (7.22x) | 6058.40 (8.72x) |
| packed fixed32 encode | 2.01 | 554.95 (276.09x) | 539.42 (268.37x) | 43.58 (21.68x) | 441.36 (219.58x) |
| packed fixed32 decode | 4.53 | 1003.97 (221.63x) | 1938.39 (427.90x) | 49.62 (10.95x) | 1656.29 (365.63x) |
| packed fixed64 encode | 2.01 | 575.13 (286.13x) | 561.05 (279.13x) | 76.03 (37.83x) | 417.91 (207.92x) |
| packed fixed64 decode | 4.52 | 1041.96 (230.52x) | 7951.71 (1759.23x) | 80.05 (17.71x) | 2702.34 (597.86x) |
| packed sfixed32 encode | 2.00 | 556.19 (278.10x) | 539.90 (269.95x) | 43.90 (21.95x) | 427.23 (213.62x) |
| packed sfixed32 decode | 4.53 | 1069.43 (236.08x) | 1978.33 (436.72x) | 48.79 (10.77x) | 1586.51 (350.22x) |
| packed sfixed64 encode | 2.01 | 576.59 (286.86x) | 561.15 (279.18x) | 75.75 (37.69x) | 404.38 (201.18x) |
| packed sfixed64 decode | 4.53 | 1021.36 (225.47x) | 7853.23 (1733.60x) | 79.84 (17.62x) | 2295.74 (506.79x) |
| packed float encode | 2.01 | 813.10 (404.53x) | 539.48 (268.40x) | 43.94 (21.86x) | 364.72 (181.45x) |
| packed float decode | 4.53 | 1057.68 (233.48x) | 2083.13 (459.85x) | 49.13 (10.85x) | 1716.30 (378.87x) |
| packed double encode | 2.01 | 832.95 (414.40x) | 560.99 (279.10x) | 76.37 (37.99x) | 364.42 (181.30x) |
| packed double decode | 4.54 | 984.47 (216.84x) | 2045.90 (450.64x) | 79.93 (17.61x) | 2591.64 (570.85x) |
| packed uint64 encode | 1287.87 | 4605.08 (3.58x) | 4025.10 (3.13x) | 2123.15 (1.65x) | 3447.59 (2.68x) |
| packed uint64 decode | 1790.35 | 2782.10 (1.55x) | 8847.67 (4.94x) | 2818.09 (1.57x) | 8142.38 (4.55x) |
| packed uint32 encode | 927.48 | 3631.78 (3.92x) | 3251.40 (3.51x) | 1763.82 (1.90x) | 2894.56 (3.12x) |
| packed uint32 decode | 1291.93 | 2424.01 (1.88x) | 3255.26 (2.52x) | 1992.94 (1.54x) | 5586.35 (4.32x) |
| packed int64 encode | 1411.59 | 10919.70 (7.74x) | 6064.43 (4.30x) | 2902.02 (2.06x) | 4139.05 (2.93x) |
| packed int64 decode | 2740.74 | 3369.75 (1.23x) | 10270.48 (3.75x) | 4821.05 (1.76x) | 10052.22 (3.67x) |
| packed sint32 encode | 780.53 | 3030.62 (3.88x) | 2866.79 (3.67x) | 1517.92 (1.94x) | 3485.36 (4.47x) |
| packed sint32 decode | 954.20 | 2551.18 (2.67x) | 3173.70 (3.33x) | 1147.00 (1.20x) | 3481.39 (3.65x) |
| packed sint64 encode | 1424.37 | 4940.52 (3.47x) | 4279.71 (3.00x) | 2403.05 (1.69x) | 4149.79 (2.91x) |
| packed sint64 decode | 2036.49 | 3075.91 (1.51x) | 9662.82 (4.74x) | 2930.44 (1.44x) | 7877.95 (3.87x) |
| packed bool encode | 2.01 | 1345.69 (669.50x) | 519.05 (258.23x) | 16.04 (7.98x) | 2229.10 (1109.00x) |
| packed bool decode | 276.66 | 1531.75 (5.54x) | 2558.29 (9.25x) | 803.55 (2.90x) | 1778.17 (6.43x) |
| packed enum encode | 272.27 | 2702.42 (9.93x) | 1809.42 (6.65x) | 1086.98 (3.99x) | 2486.34 (9.13x) |
| packed enum decode | 155.90 | 1533.55 (9.84x) | 2861.78 (18.36x) | 694.81 (4.46x) | 2431.73 (15.60x) |
| large map encode | 4059.60 | 16673.15 (4.11x) | 9895.06 (2.44x) | 22357.60 (5.51x) | 199603.72 (49.17x) |
| shuffled large map deterministic binary encode | 27648.50 | — | — | 92398.90 (3.34x) | 388117.34 (14.04x) |
| large map decode | 25602.28 | 90853.76 (3.55x) | 89920.65 (3.51x) | 90888.50 (3.55x) | 283297.27 (11.07x) |
The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound `Duration`, non-empty/escaped-input parse/number-exponent parse and empty `Struct`, object/escaped-object parse/object-number-exponent/list/escaped-list/string-scalar/escaped-string-scalar/number-exponent/negative-number `Value` (including default-like scalar and empty object/list kinds),
`FieldMask` (non-empty, escaped JSON parse input, and empty), escaped-input parse/short-fraction parse/micro/nano/offset/min/pre/post/max-bound `Timestamp`, `Empty`, min/zero/positive/number-input parse/negative/max `Int64Value`, negative/zero/positive finite/string-input parse/numeric-exponent parse `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), negative/zero/positive finite/string-input parse/numeric-exponent parse `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), zero/normal/number-input parse/max `UInt64Value`, min/zero/positive/string-input parse/negative/max `Int32Value`, zero/normal/string-input parse/max `UInt32Value`, true/false `BoolValue`, non-empty/escape-input parse/empty `StringValue`, base64/base64url parse/empty `BytesValue`, and recursive nested `Any` payloads), direct zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound Duration, non-empty/escaped-input parse/empty FieldMask, and escaped-input parse/short-fraction parse/micro/nano/offset/min/pre/post/max-bound Timestamp WKT JSON plus other direct WKT JSON, including non-empty/escaped-input parse/number-exponent parse/empty `Struct`, object/escaped-object parse/object-number-exponent/list/escaped-list/string-scalar/escaped-string-scalar/number-exponent/negative-number `Value`, and escaped/non-empty/empty `ListValue`, TextFormat, packed scalars, large bytes,
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
