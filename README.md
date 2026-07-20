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

Latest accepted comparison (`/tmp/pbz-compare-value-surrogate-json-final.log`,
summarized in `/tmp/pbz-summary-value-surrogate-json-final.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 15.79 | 138.85 (8.79x) | 52.27 (3.31x) | 103.03 (6.53x) | 839.25 (53.15x) |
| binary decode | 91.75 | 248.70 (2.71x) | 234.48 (2.56x) | 227.24 (2.48x) | 906.72 (9.88x) |
| unknown fields count by number | 3.57 | — | — | 162.71 (45.58x) | — |
| deterministic binary encode | 57.71 | — | — | 131.39 (2.28x) | 1147.01 (19.88x) |
| scalarmix encode | 18.95 | 95.42 (5.04x) | 49.39 (2.61x) | 29.69 (1.57x) | 211.21 (11.15x) |
| scalarmix decode | 39.07 | 135.20 (3.46x) | 177.11 (4.53x) | 85.08 (2.18x) | 532.01 (13.62x) |
| textbytes encode | 13.54 | 81.57 (6.02x) | 33.59 (2.48x) | 119.72 (8.84x) | 154.06 (11.38x) |
| textbytes decode | 47.11 | 379.14 (8.05x) | 236.93 (5.03x) | 164.66 (3.50x) | 666.25 (14.14x) |
| largebytes encode | 17.79 | 2712.08 (152.45x) | 2687.74 (151.08x) | 2797.06 (157.23x) | 2715.01 (152.61x) |
| largebytes decode | 88.77 | 5600.77 (63.09x) | 3018.36 (34.00x) | 2736.48 (30.83x) | 20910.41 (235.56x) |
| presencemix encode | 16.65 | 79.69 (4.79x) | 29.78 (1.79x) | 53.94 (3.24x) | 233.23 (14.01x) |
| presencemix decode | 56.45 | 195.42 (3.46x) | 107.42 (1.90x) | 159.29 (2.82x) | 494.60 (8.76x) |
| complex encode | 51.10 | 193.50 (3.79x) | 97.28 (1.90x) | 162.15 (3.17x) | 973.99 (19.06x) |
| complex decode | 184.75 | 398.24 (2.16x) | 346.70 (1.88x) | 382.12 (2.07x) | 1352.59 (7.32x) |
| complex deterministic binary encode | 93.26 | — | — | 178.77 (1.92x) | 1179.88 (12.65x) |
| complex JSON stringify | 294.02 | — | — | 4887.25 (16.62x) | 6479.93 (22.04x) |
| complex JSON parse | 2434.06 | — | — | 11930.50 (4.90x) | 7598.84 (3.12x) |
| complex TextFormat format | 385.06 | — | — | 3781.21 (9.82x) | 5797.38 (15.06x) |
| complex TextFormat parse | 1752.75 | — | — | 6888.66 (3.93x) | 8447.93 (4.82x) |
| packed int32 encode | 638.19 | 3159.02 (4.95x) | 2527.76 (3.96x) | 1241.58 (1.95x) | 2739.16 (4.29x) |
| packed int32 decode | 764.46 | 1908.32 (2.50x) | 3236.08 (4.23x) | 986.67 (1.29x) | 3817.26 (4.99x) |
| JSON stringify | 160.66 | — | — | 3009.84 (18.73x) | 2374.32 (14.78x) |
| JSON parse | 1523.48 | — | — | 7608.39 (4.99x) | 4756.01 (3.12x) |
| Any WKT JSON stringify | 131.48 | — | — | 2036.87 (15.49x) | 986.14 (7.50x) |
| Any WKT JSON parse | 530.13 | — | — | 3133.88 (5.91x) | 1543.62 (2.91x) |
| Any Duration Escape WKT JSON parse | 558.68 | — | — | 3310.35 (5.93x) | 1611.53 (2.88x) |
| Any PlusDuration WKT JSON parse | 529.57 | — | — | 2993.89 (5.65x) | 1553.03 (2.93x) |
| Any ShortFractionDuration WKT JSON parse | 525.24 | — | — | 2944.05 (5.61x) | 1523.00 (2.90x) |
| Any MicroDuration WKT JSON stringify | 142.24 | — | — | 1891.07 (13.29x) | 981.16 (6.90x) |
| Any MicroDuration WKT JSON parse | 528.98 | — | — | 2985.58 (5.64x) | 1541.79 (2.91x) |
| Any NanoDuration WKT JSON stringify | 136.37 | — | — | 1915.19 (14.04x) | 984.25 (7.22x) |
| Any NanoDuration WKT JSON parse | 540.85 | — | — | 2999.55 (5.55x) | 1536.92 (2.84x) |
| Any NegativeDuration WKT JSON stringify | 147.61 | — | — | 1934.26 (13.10x) | 1011.55 (6.85x) |
| Any NegativeDuration WKT JSON parse | 532.46 | — | — | 3108.26 (5.84x) | 1576.48 (2.96x) |
| Any FractionalNegativeDuration WKT JSON stringify | 130.41 | — | — | 1892.49 (14.51x) | 998.12 (7.65x) |
| Any FractionalNegativeDuration WKT JSON parse | 522.06 | — | — | 3113.72 (5.96x) | 1503.77 (2.88x) |
| Any MaxDuration WKT JSON stringify | 126.29 | — | — | 1750.16 (13.86x) | 998.10 (7.90x) |
| Any MaxDuration WKT JSON parse | 538.76 | — | — | 3020.03 (5.61x) | 1546.90 (2.87x) |
| Any MinDuration WKT JSON stringify | 125.41 | — | — | 1768.12 (14.10x) | 1012.35 (8.07x) |
| Any MinDuration WKT JSON parse | 550.91 | — | — | 3030.20 (5.50x) | 1525.59 (2.77x) |
| Any ZeroDuration WKT JSON stringify | 112.82 | — | — | 915.62 (8.12x) | 973.23 (8.63x) |
| Any ZeroDuration WKT JSON parse | 486.30 | — | — | 2273.14 (4.67x) | 1458.71 (3.00x) |
| Any FieldMask WKT JSON stringify | 227.91 | — | — | 1745.64 (7.66x) | 1434.68 (6.29x) |
| Any FieldMask WKT JSON parse | 723.77 | — | — | 3161.77 (4.37x) | 2072.69 (2.86x) |
| Any FieldMask Escape WKT JSON parse | 758.79 | — | — | 3273.93 (4.31x) | 2249.67 (2.96x) |
| Any EmptyFieldMask WKT JSON stringify | 119.02 | — | — | 912.88 (7.67x) | 778.49 (6.54x) |
| Any EmptyFieldMask WKT JSON parse | 452.02 | — | — | 2162.73 (4.78x) | 1305.41 (2.89x) |
| Any Timestamp WKT JSON stringify | 178.89 | — | — | 2028.78 (11.34x) | 1006.74 (5.63x) |
| Any Timestamp WKT JSON parse | 588.11 | — | — | 3044.08 (5.18x) | 1637.35 (2.78x) |
| Any Timestamp Escape WKT JSON parse | 600.18 | — | — | 3113.95 (5.19x) | 1748.94 (2.91x) |
| Any ShortFraction Timestamp WKT JSON parse | 577.47 | — | — | 3065.60 (5.31x) | 1608.36 (2.79x) |
| Any Micro Timestamp WKT JSON stringify | 183.23 | — | — | 2057.22 (11.23x) | 1012.77 (5.53x) |
| Any Micro Timestamp WKT JSON parse | 587.11 | — | — | 3094.82 (5.27x) | 1646.69 (2.80x) |
| Any Nano Timestamp WKT JSON stringify | 177.10 | — | — | 2069.71 (11.69x) | 1024.44 (5.78x) |
| Any Nano Timestamp WKT JSON parse | 590.69 | — | — | 3099.38 (5.25x) | 1634.32 (2.77x) |
| Any Offset Timestamp WKT JSON parse | 596.31 | — | — | 3098.48 (5.20x) | 1677.93 (2.81x) |
| Any PreEpoch Timestamp WKT JSON stringify | 148.93 | — | — | 1955.24 (13.13x) | 976.62 (6.56x) |
| Any PreEpoch Timestamp WKT JSON parse | 572.97 | — | — | 3062.91 (5.35x) | 1589.78 (2.77x) |
| Any Max Timestamp WKT JSON stringify | 165.71 | — | — | 2052.35 (12.39x) | 1020.62 (6.16x) |
| Any Max Timestamp WKT JSON parse | 602.61 | — | — | 3111.78 (5.16x) | 1654.97 (2.75x) |
| Any Min Timestamp WKT JSON stringify | 163.60 | — | — | 1941.24 (11.87x) | 974.55 (5.96x) |
| Any Min Timestamp WKT JSON parse | 565.77 | — | — | 3041.91 (5.38x) | 1585.38 (2.80x) |
| Any Empty WKT JSON stringify | 95.44 | — | — | 910.23 (9.54x) | 783.96 (8.21x) |
| Any Empty WKT JSON parse | 343.14 | — | — | 2133.90 (6.22x) | 1358.38 (3.96x) |
| Any Struct WKT JSON stringify | 638.82 | — | — | 5931.88 (9.29x) | 6038.95 (9.45x) |
| Any Struct WKT JSON parse | 1740.04 | — | — | 11161.80 (6.41x) | 8758.01 (5.03x) |
| Any Struct Escape WKT JSON parse | 1782.97 | — | — | 11178.50 (6.27x) | 8933.26 (5.01x) |
| Any Struct NumberExponent WKT JSON parse | 1754.67 | — | — | 11120.20 (6.34x) | 8779.94 (5.00x) |
| Any EmptyStruct WKT JSON stringify | 118.53 | — | — | 908.11 (7.66x) | 952.16 (8.03x) |
| Any EmptyStruct WKT JSON parse | 454.58 | — | — | 2225.77 (4.90x) | 1608.80 (3.54x) |
| Any Value WKT JSON stringify | 656.22 | — | — | 6206.58 (9.46x) | 6373.14 (9.71x) |
| Any Value WKT JSON parse | 1805.16 | — | — | 11915.60 (6.60x) | 9165.95 (5.08x) |
| Any Value Escape WKT JSON parse | 1831.84 | — | — | 11707.00 (6.39x) | 9304.19 (5.08x) |
| Any Value NumberExponent WKT JSON parse | 1825.99 | — | — | 11381.30 (6.23x) | 9212.81 (5.05x) |
| Any NullValue WKT JSON stringify | 139.79 | — | — | 2254.83 (16.13x) | 921.57 (6.59x) |
| Any NullValue WKT JSON parse | 473.79 | — | — | 4080.62 (8.61x) | 1570.83 (3.32x) |
| Any StringScalarValue WKT JSON stringify | 160.73 | — | — | 2294.70 (14.28x) | 1011.38 (6.29x) |
| Any StringScalarValue WKT JSON parse | 657.66 | — | — | 3664.69 (5.57x) | 1684.53 (2.56x) |
| Any StringScalarValue Escape WKT JSON parse | 884.35 | — | — | 3697.51 (4.18x) | 1743.32 (1.97x) |
| Any StringScalarValue Surrogate WKT JSON parse | 899.66 | — | — | 3702.11 (4.12x) | 1765.25 (1.96x) |
| Any EmptyStringScalarValue WKT JSON stringify | 246.77 | — | — | 2300.91 (9.32x) | 995.14 (4.03x) |
| Any EmptyStringScalarValue WKT JSON parse | 805.70 | — | — | 3657.48 (4.54x) | 1576.16 (1.96x) |
| Any NumberValue WKT JSON stringify | 349.16 | — | — | 2543.64 (7.29x) | 1037.56 (2.97x) |
| Any NumberValue WKT JSON parse | 831.24 | — | — | 3709.14 (4.46x) | 1622.80 (1.95x) |
| Any NumberValue Exponent WKT JSON parse | 850.58 | — | — | 3724.22 (4.38x) | 1619.77 (1.90x) |
| Any NegativeNumberValue WKT JSON stringify | 348.30 | — | — | 2534.18 (7.28x) | 1038.42 (2.98x) |
| Any NegativeNumberValue WKT JSON parse | 539.46 | — | — | 3738.08 (6.93x) | 1613.04 (2.99x) |
| Any ZeroNumberValue WKT JSON stringify | 147.17 | — | — | 2482.78 (16.87x) | 929.92 (6.32x) |
| Any ZeroNumberValue WKT JSON parse | 519.80 | — | — | 3857.09 (7.42x) | 1627.11 (3.13x) |
| Any BoolScalarValue WKT JSON stringify | 135.53 | — | — | 2281.96 (16.84x) | 926.01 (6.83x) |
| Any BoolScalarValue WKT JSON parse | 546.42 | — | — | 3622.16 (6.63x) | 1557.55 (2.85x) |
| Any FalseBoolScalarValue WKT JSON stringify | 131.37 | — | — | 2277.12 (17.33x) | 910.73 (6.93x) |
| Any FalseBoolScalarValue WKT JSON parse | 474.22 | — | — | 3635.72 (7.67x) | 1553.81 (3.28x) |
| Any ListKindValue WKT JSON stringify | 507.80 | — | — | 5604.36 (11.04x) | 4699.04 (9.25x) |
| Any ListKindValue WKT JSON parse | 1392.27 | — | — | 9957.11 (7.15x) | 7093.25 (5.09x) |
| Any ListKindValue Escape WKT JSON parse | 1437.01 | — | — | 9984.30 (6.95x) | 7366.93 (5.13x) |
| Any EmptyStructKindValue WKT JSON stringify | 144.50 | — | — | 2946.08 (20.39x) | 1337.74 (9.26x) |
| Any EmptyStructKindValue WKT JSON parse | 523.97 | — | — | 5457.97 (10.42x) | 1966.65 (3.75x) |
| Any EmptyListKindValue WKT JSON stringify | 143.99 | — | — | 2928.85 (20.34x) | 1144.84 (7.95x) |
| Any EmptyListKindValue WKT JSON parse | 515.29 | — | — | 4447.25 (8.63x) | 1858.44 (3.61x) |
| Any DoubleValue WKT JSON stringify | 185.21 | — | — | 1836.44 (9.92x) | 814.35 (4.40x) |
| Any DoubleValue WKT JSON parse | 529.97 | — | — | 2761.37 (5.21x) | 1435.18 (2.71x) |
| Any DoubleValue String WKT JSON parse | 613.02 | — | — | 2759.01 (4.50x) | 1538.27 (2.51x) |
| Any DoubleValue Exponent WKT JSON parse | 542.25 | — | — | 2775.44 (5.12x) | 1462.43 (2.70x) |
| Any NegativeDoubleValue WKT JSON stringify | 189.24 | — | — | 1817.28 (9.60x) | 800.64 (4.23x) |
| Any NegativeDoubleValue WKT JSON parse | 533.60 | — | — | 2744.84 (5.14x) | 1446.39 (2.71x) |
| Any ZeroDoubleValue WKT JSON stringify | 158.04 | — | — | 922.58 (5.84x) | 734.85 (4.65x) |
| Any ZeroDoubleValue WKT JSON parse | 529.90 | — | — | 2195.83 (4.14x) | 1399.01 (2.64x) |
| Any DoubleValue NaN WKT JSON stringify | 156.18 | — | — | 1589.24 (10.18x) | 722.32 (4.62x) |
| Any DoubleValue NaN WKT JSON parse | 537.00 | — | — | 2666.12 (4.96x) | 1418.71 (2.64x) |
| Any DoubleValue Infinity WKT JSON stringify | 168.47 | — | — | 1573.68 (9.34x) | 735.15 (4.36x) |
| Any DoubleValue Infinity WKT JSON parse | 538.43 | — | — | 2679.30 (4.98x) | 1433.06 (2.66x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 171.59 | — | — | 1558.88 (9.08x) | 718.93 (4.19x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 541.05 | — | — | 2680.83 (4.95x) | 1421.82 (2.63x) |
| Any FloatValue WKT JSON stringify | 188.67 | — | — | 1759.19 (9.32x) | 786.83 (4.17x) |
| Any FloatValue WKT JSON parse | 524.98 | — | — | 2726.97 (5.19x) | 1481.41 (2.82x) |
| Any FloatValue String WKT JSON parse | 547.87 | — | — | 2736.55 (4.99x) | 1519.74 (2.77x) |
| Any FloatValue Exponent WKT JSON parse | 539.91 | — | — | 2765.81 (5.12x) | 1425.66 (2.64x) |
| Any NegativeFloatValue WKT JSON stringify | 192.95 | — | — | 1761.47 (9.13x) | 791.86 (4.10x) |
| Any NegativeFloatValue WKT JSON parse | 538.39 | — | — | 2732.80 (5.08x) | 1441.19 (2.68x) |
| Any ZeroFloatValue WKT JSON stringify | 253.03 | — | — | 932.80 (3.69x) | 728.63 (2.88x) |
| Any ZeroFloatValue WKT JSON parse | 521.76 | — | — | 2179.65 (4.18x) | 1422.04 (2.73x) |
| Any FloatValue NaN WKT JSON stringify | 157.71 | — | — | 1590.99 (10.09x) | 724.87 (4.60x) |
| Any FloatValue NaN WKT JSON parse | 526.54 | — | — | 2637.77 (5.01x) | 1405.18 (2.67x) |
| Any FloatValue Infinity WKT JSON stringify | 167.77 | — | — | 1550.62 (9.24x) | 1046.43 (6.24x) |
| Any FloatValue Infinity WKT JSON parse | 529.61 | — | — | 2681.02 (5.06x) | 1429.38 (2.70x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 165.44 | — | — | 1559.52 (9.43x) | 700.58 (4.23x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 530.27 | — | — | 2673.70 (5.04x) | 1420.73 (2.68x) |
| Any Int64Value WKT JSON stringify | 169.11 | — | — | 1577.28 (9.33x) | 868.34 (5.13x) |
| Any Int64Value WKT JSON parse | 583.06 | — | — | 2792.39 (4.79x) | 1641.93 (2.82x) |
| Any Int64Value Number WKT JSON parse | 594.89 | — | — | 2776.48 (4.67x) | 1524.82 (2.56x) |
| Any Int64Value Exponent WKT JSON parse | 551.54 | — | — | 2725.94 (4.94x) | 1487.37 (2.70x) |
| Any ZeroInt64Value WKT JSON stringify | 159.62 | — | — | 935.86 (5.86x) | 880.17 (5.51x) |
| Any ZeroInt64Value WKT JSON parse | 529.85 | — | — | 2177.27 (4.11x) | 1513.15 (2.86x) |
| Any NegativeInt64Value WKT JSON stringify | 172.59 | — | — | 1576.55 (9.13x) | 855.12 (4.95x) |
| Any NegativeInt64Value WKT JSON parse | 590.38 | — | — | 2824.53 (4.78x) | 1665.66 (2.82x) |
| Any MinInt64Value WKT JSON stringify | 175.96 | — | — | 1558.80 (8.86x) | 866.40 (4.92x) |
| Any MinInt64Value WKT JSON parse | 583.69 | — | — | 2842.43 (4.87x) | 1687.82 (2.89x) |
| Any MaxInt64Value WKT JSON stringify | 171.08 | — | — | 1576.59 (9.22x) | 874.37 (5.11x) |
| Any MaxInt64Value WKT JSON parse | 564.05 | — | — | 2829.70 (5.02x) | 1686.64 (2.99x) |
| Any UInt64Value WKT JSON stringify | 174.17 | — | — | 1579.73 (9.07x) | 863.81 (4.96x) |
| Any UInt64Value WKT JSON parse | 571.68 | — | — | 2817.74 (4.93x) | 1639.77 (2.87x) |
| Any UInt64Value Number WKT JSON parse | 568.47 | — | — | 2783.55 (4.90x) | 1522.64 (2.68x) |
| Any UInt64Value Exponent WKT JSON parse | 551.02 | — | — | 2730.61 (4.96x) | 1491.15 (2.71x) |
| Any ZeroUInt64Value WKT JSON stringify | 162.67 | — | — | 936.27 (5.76x) | 784.17 (4.82x) |
| Any ZeroUInt64Value WKT JSON parse | 535.01 | — | — | 2173.70 (4.06x) | 1474.67 (2.76x) |
| Any MaxUInt64Value WKT JSON stringify | 172.96 | — | — | 1571.50 (9.09x) | 868.18 (5.02x) |
| Any MaxUInt64Value WKT JSON parse | 575.07 | — | — | 2846.42 (4.95x) | 1667.17 (2.90x) |
| Any Int32Value WKT JSON stringify | 169.94 | — | — | 1572.49 (9.25x) | 731.63 (4.31x) |
| Any Int32Value WKT JSON parse | 554.51 | — | — | 2682.30 (4.84x) | 1454.25 (2.62x) |
| Any Int32Value String WKT JSON parse | 567.51 | — | — | 2692.96 (4.75x) | 1551.01 (2.73x) |
| Any Int32Value Exponent WKT JSON parse | 555.21 | — | — | 2712.74 (4.89x) | 1500.73 (2.70x) |
| Any ZeroInt32Value WKT JSON stringify | 171.21 | — | — | 915.57 (5.35x) | 721.51 (4.21x) |
| Any ZeroInt32Value WKT JSON parse | 538.45 | — | — | 2172.31 (4.03x) | 1419.42 (2.64x) |
| Any NegativeInt32Value WKT JSON stringify | 169.34 | — | — | 1563.08 (9.23x) | 739.69 (4.37x) |
| Any NegativeInt32Value WKT JSON parse | 548.15 | — | — | 2713.64 (4.95x) | 1458.92 (2.66x) |
| Any MinInt32Value WKT JSON stringify | 177.64 | — | — | 1553.20 (8.74x) | 962.77 (5.42x) |
| Any MinInt32Value WKT JSON parse | 574.26 | — | — | 2718.13 (4.73x) | 1508.58 (2.63x) |
| Any MaxInt32Value WKT JSON stringify | 185.58 | — | — | 1559.29 (8.40x) | 730.42 (3.94x) |
| Any MaxInt32Value WKT JSON parse | 557.78 | — | — | 2705.47 (4.85x) | 1465.60 (2.63x) |
| Any UInt32Value WKT JSON stringify | 181.02 | — | — | 1565.91 (8.65x) | 740.42 (4.09x) |
| Any UInt32Value WKT JSON parse | 559.85 | — | — | 2686.08 (4.80x) | 1472.24 (2.63x) |
| Any UInt32Value String WKT JSON parse | 571.72 | — | — | 2690.27 (4.71x) | 1536.18 (2.69x) |
| Any UInt32Value Exponent WKT JSON parse | 559.39 | — | — | 2725.39 (4.87x) | 1508.39 (2.70x) |
| Any ZeroUInt32Value WKT JSON stringify | 171.99 | — | — | 929.99 (5.41x) | 728.58 (4.24x) |
| Any ZeroUInt32Value WKT JSON parse | 543.21 | — | — | 2181.12 (4.02x) | 1425.21 (2.62x) |
| Any MaxUInt32Value WKT JSON stringify | 181.16 | — | — | 1558.75 (8.60x) | 750.06 (4.14x) |
| Any MaxUInt32Value WKT JSON parse | 560.70 | — | — | 2695.07 (4.81x) | 1460.21 (2.60x) |
| Any BoolValue WKT JSON stringify | 169.24 | — | — | 1520.02 (8.98x) | 723.24 (4.27x) |
| Any BoolValue WKT JSON parse | 496.46 | — | — | 2611.58 (5.26x) | 1330.49 (2.68x) |
| Any FalseBoolValue WKT JSON stringify | 175.81 | — | — | 919.73 (5.23x) | 706.34 (4.02x) |
| Any FalseBoolValue WKT JSON parse | 496.91 | — | — | 2159.09 (4.35x) | 1347.65 (2.71x) |
| Any StringValue WKT JSON stringify | 206.01 | — | — | 1569.86 (7.62x) | 807.06 (3.92x) |
| Any StringValue WKT JSON parse | 570.36 | — | — | 2678.99 (4.70x) | 1452.11 (2.55x) |
| Any StringValue Escape WKT JSON parse | 571.14 | — | — | 2703.54 (4.73x) | 1528.89 (2.68x) |
| Any StringValue Surrogate WKT JSON parse | 579.22 | — | — | 2700.04 (4.66x) | 1547.79 (2.67x) |
| Any EmptyStringValue WKT JSON stringify | 177.11 | — | — | 918.26 (5.18x) | 760.22 (4.29x) |
| Any EmptyStringValue WKT JSON parse | 537.86 | — | — | 2176.29 (4.05x) | 1396.75 (2.60x) |
| Any BytesValue WKT JSON stringify | 195.76 | — | — | 1605.95 (8.20x) | 848.28 (4.33x) |
| Any BytesValue WKT JSON parse | 576.18 | — | — | 2698.60 (4.68x) | 1467.12 (2.55x) |
| Any BytesValue URL WKT JSON parse | 596.34 | — | — | 2675.22 (4.49x) | 1487.10 (2.49x) |
| Any BytesValue StandardBase64 WKT JSON parse | 579.55 | — | — | 2698.81 (4.66x) | 1503.37 (2.59x) |
| Any BytesValue Unpadded WKT JSON parse | 584.75 | — | — | 2690.67 (4.60x) | 1495.19 (2.56x) |
| Any EmptyBytesValue WKT JSON stringify | 179.46 | — | — | 913.32 (5.09x) | 772.44 (4.30x) |
| Any EmptyBytesValue WKT JSON parse | 535.77 | — | — | 2166.03 (4.04x) | 1430.48 (2.67x) |
| Nested Any WKT JSON stringify | 306.63 | — | — | 2500.41 (8.15x) | 1445.39 (4.71x) |
| Nested Any WKT JSON parse | 883.07 | — | — | 4272.96 (4.84x) | 2863.01 (3.24x) |
| Duration JSON stringify | 58.90 | — | — | 953.88 (16.19x) | 375.82 (6.38x) |
| Duration JSON parse | 20.50 | — | — | 1454.75 (70.96x) | 389.26 (18.99x) |
| Duration Escape JSON parse | 43.04 | — | — | 1490.39 (34.63x) | 432.12 (10.04x) |
| PlusDuration JSON parse | 21.34 | — | — | 1454.75 (68.17x) | 403.12 (18.89x) |
| ShortFractionDuration JSON parse | 17.56 | — | — | 1417.79 (80.74x) | 397.49 (22.64x) |
| MicroDuration JSON stringify | 59.11 | — | — | 964.34 (16.31x) | 403.12 (6.82x) |
| MicroDuration JSON parse | 23.36 | — | — | 1465.05 (62.72x) | 381.75 (16.34x) |
| NanoDuration JSON stringify | 57.49 | — | — | 1010.42 (17.58x) | 405.31 (7.05x) |
| NanoDuration JSON parse | 26.11 | — | — | 1479.55 (56.67x) | 393.65 (15.08x) |
| NegativeDuration JSON stringify | 58.60 | — | — | 1023.49 (17.47x) | 420.73 (7.18x) |
| NegativeDuration JSON parse | 20.82 | — | — | 1557.61 (74.81x) | 393.48 (18.90x) |
| FractionalNegativeDuration JSON stringify | 57.70 | — | — | 978.76 (16.96x) | 435.94 (7.56x) |
| FractionalNegativeDuration JSON parse | 21.56 | — | — | 1471.79 (68.26x) | 377.41 (17.51x) |
| MaxDuration JSON stringify | 49.33 | — | — | 855.58 (17.34x) | 419.42 (8.50x) |
| MaxDuration JSON parse | 37.99 | — | — | 1443.61 (38.00x) | 403.70 (10.63x) |
| MinDuration JSON stringify | 49.41 | — | — | 867.99 (17.57x) | 444.54 (9.00x) |
| MinDuration JSON parse | 40.59 | — | — | 1445.52 (35.61x) | 403.69 (9.95x) |
| ZeroDuration JSON stringify | 44.40 | — | — | 815.43 (18.37x) | 346.00 (7.79x) |
| ZeroDuration JSON parse | 14.58 | — | — | 1367.32 (93.78x) | 316.25 (21.69x) |
| FieldMask JSON stringify | 69.68 | — | — | 891.28 (12.79x) | 668.62 (9.60x) |
| FieldMask JSON parse | 139.49 | — | — | 1682.39 (12.06x) | 889.85 (6.38x) |
| FieldMask Escape JSON parse | 188.64 | — | — | 1742.26 (9.24x) | 970.48 (5.14x) |
| EmptyFieldMask JSON stringify | 44.91 | — | — | 613.07 (13.65x) | 194.10 (4.32x) |
| EmptyFieldMask JSON parse | 4.79 | — | — | 952.07 (198.76x) | 168.06 (35.09x) |
| Timestamp JSON stringify | 97.61 | — | — | 1147.22 (11.75x) | 414.68 (4.25x) |
| Timestamp JSON parse | 45.86 | — | — | 1511.75 (32.96x) | 449.62 (9.80x) |
| Timestamp Escape JSON parse | 91.16 | — | — | 1532.40 (16.81x) | 505.55 (5.55x) |
| ShortFraction Timestamp JSON parse | 43.60 | — | — | 1482.11 (33.99x) | 438.75 (10.06x) |
| Micro Timestamp JSON stringify | 96.20 | — | — | 1155.87 (12.02x) | 418.59 (4.35x) |
| Micro Timestamp JSON parse | 47.50 | — | — | 1514.41 (31.88x) | 458.14 (9.65x) |
| Nano Timestamp JSON stringify | 94.14 | — | — | 1200.54 (12.75x) | 423.76 (4.50x) |
| Nano Timestamp JSON parse | 50.88 | — | — | 1537.13 (30.21x) | 466.65 (9.17x) |
| Offset Timestamp JSON parse | 51.53 | — | — | 1544.73 (29.98x) | 485.06 (9.41x) |
| PreEpoch Timestamp JSON stringify | 67.07 | — | — | 1081.89 (16.13x) | 405.52 (6.05x) |
| PreEpoch Timestamp JSON parse | 43.13 | — | — | 1487.54 (34.49x) | 426.93 (9.90x) |
| Max Timestamp JSON stringify | 80.35 | — | — | 1214.97 (15.12x) | 421.93 (5.25x) |
| Max Timestamp JSON parse | 52.06 | — | — | 1546.09 (29.70x) | 468.64 (9.00x) |
| Min Timestamp JSON stringify | 81.60 | — | — | 1064.16 (13.04x) | 398.96 (4.89x) |
| Min Timestamp JSON parse | 41.18 | — | — | 1458.74 (35.42x) | 426.48 (10.36x) |
| Empty JSON stringify | 20.83 | — | — | 496.35 (23.83x) | 82.79 (3.97x) |
| Empty JSON parse | 68.63 | — | — | 720.36 (10.50x) | 210.53 (3.07x) |
| Struct JSON stringify | 188.90 | — | — | 5836.00 (30.89x) | 3064.48 (16.22x) |
| Struct JSON parse | 859.57 | — | — | 11025.10 (12.83x) | 4672.49 (5.44x) |
| Struct Escape JSON parse | 904.37 | — | — | 11067.30 (12.24x) | 4805.61 (5.31x) |
| Struct NumberExponent JSON parse | 860.11 | — | — | 10970.80 (12.76x) | 4671.74 (5.43x) |
| EmptyStruct JSON stringify | 40.35 | — | — | 692.49 (17.16x) | 349.54 (8.66x) |
| EmptyStruct JSON parse | 87.72 | — | — | 2034.56 (23.19x) | 384.04 (4.38x) |
| Value JSON stringify | 192.52 | — | — | 6690.01 (34.75x) | 3228.74 (16.77x) |
| Value JSON parse | 875.45 | — | — | 12176.20 (13.91x) | 4908.42 (5.61x) |
| Value Escape JSON parse | 915.71 | — | — | 12304.20 (13.44x) | 5093.42 (5.56x) |
| Value NumberExponent JSON parse | 871.04 | — | — | 12207.90 (14.02x) | 4926.64 (5.66x) |
| NullValue JSON stringify | 40.20 | — | — | 1361.48 (33.87x) | 230.87 (5.74x) |
| NullValue JSON parse | 71.24 | — | — | 2489.03 (34.94x) | 349.09 (4.90x) |
| StringScalarValue JSON stringify | 47.39 | — | — | 1345.54 (28.39x) | 283.52 (5.98x) |
| StringScalarValue JSON parse | 142.58 | — | — | 2096.80 (14.71x) | 444.82 (3.12x) |
| StringScalarValue Escape JSON parse | 152.12 | — | — | 2125.90 (13.98x) | 491.61 (3.23x) |
| StringScalarValue Surrogate JSON parse | 150.77 | — | — | 2142.96 (14.21x) | 506.71 (3.36x) |
| EmptyStringScalarValue JSON stringify | 45.89 | — | — | 1336.36 (29.12x) | 433.56 (9.45x) |
| EmptyStringScalarValue JSON parse | 88.47 | — | — | 2085.16 (23.57x) | 382.38 (4.32x) |
| NumberValue JSON stringify | 73.50 | — | — | 1561.11 (21.24x) | 323.93 (4.41x) |
| NumberValue JSON parse | 135.07 | — | — | 2177.83 (16.12x) | 421.10 (3.12x) |
| NumberValue Exponent JSON parse | 137.80 | — | — | 2213.10 (16.06x) | 417.22 (3.03x) |
| NegativeNumberValue JSON stringify | 73.66 | — | — | 1559.21 (21.17x) | 324.41 (4.40x) |
| NegativeNumberValue JSON parse | 135.98 | — | — | 2190.44 (16.11x) | 416.33 (3.06x) |
| ZeroNumberValue JSON stringify | 52.46 | — | — | 1513.09 (28.84x) | 276.04 (5.26x) |
| ZeroNumberValue JSON parse | 132.94 | — | — | 2120.47 (15.95x) | 388.00 (2.92x) |
| BoolScalarValue JSON stringify | 41.46 | — | — | 1327.03 (32.01x) | 220.50 (5.32x) |
| BoolScalarValue JSON parse | 71.31 | — | — | 2025.38 (28.40x) | 323.74 (4.54x) |
| FalseBoolScalarValue JSON stringify | 40.24 | — | — | 1321.22 (32.83x) | 221.21 (5.50x) |
| FalseBoolScalarValue JSON parse | 71.66 | — | — | 2039.40 (28.46x) | 340.10 (4.75x) |
| ListKindValue JSON stringify | 145.85 | — | — | 6201.10 (42.52x) | 2265.15 (15.53x) |
| ListKindValue JSON parse | 684.78 | — | — | 10441.20 (15.25x) | 4073.39 (5.95x) |
| ListKindValue Escape JSON parse | 710.46 | — | — | 10503.30 (14.78x) | 4287.66 (6.04x) |
| EmptyStructKindValue JSON stringify | 42.11 | — | — | 1954.48 (46.41x) | 524.48 (12.45x) |
| EmptyStructKindValue JSON parse | 111.91 | — | — | 3803.91 (33.99x) | 660.05 (5.90x) |
| EmptyListKindValue JSON stringify | 40.91 | — | — | 1948.60 (47.63x) | 361.02 (8.82x) |
| EmptyListKindValue JSON parse | 150.58 | — | — | 4070.26 (27.03x) | 600.68 (3.99x) |
| ListValue JSON stringify | 150.06 | — | — | 4794.77 (31.95x) | 2112.28 (14.08x) |
| ListValue JSON parse | 662.84 | — | — | 8554.92 (12.91x) | 3803.12 (5.74x) |
| ListValue Escape JSON parse | 679.34 | — | — | 8613.35 (12.68x) | 4051.75 (5.96x) |
| EmptyListValue JSON stringify | 40.23 | — | — | 690.66 (17.17x) | 187.53 (4.66x) |
| EmptyListValue JSON parse | 125.37 | — | — | 2266.82 (18.08x) | 324.90 (2.59x) |
| DoubleValue JSON stringify | 67.97 | — | — | 856.86 (12.61x) | 195.53 (2.88x) |
| DoubleValue JSON parse | 115.91 | — | — | 1238.29 (10.68x) | 289.40 (2.50x) |
| DoubleValue String JSON parse | 115.85 | — | — | 1181.78 (10.20x) | 657.20 (5.67x) |
| DoubleValue Exponent JSON parse | 118.10 | — | — | 1248.23 (10.57x) | 298.18 (2.52x) |
| NegativeDoubleValue JSON stringify | 67.41 | — | — | 858.39 (12.73x) | 182.51 (2.71x) |
| NegativeDoubleValue JSON parse | 116.20 | — | — | 1244.56 (10.71x) | 291.44 (2.51x) |
| ZeroDoubleValue JSON stringify | 47.19 | — | — | 801.39 (16.98x) | 136.04 (2.88x) |
| ZeroDoubleValue JSON parse | 113.17 | — | — | 1160.28 (10.25x) | 266.77 (2.36x) |
| DoubleValue NaN JSON stringify | 46.13 | — | — | 659.78 (14.30x) | 122.64 (2.66x) |
| DoubleValue NaN JSON parse | 109.61 | — | — | 1093.94 (9.98x) | 280.15 (2.56x) |
| DoubleValue Infinity JSON stringify | 47.75 | — | — | 662.51 (13.87x) | 126.45 (2.65x) |
| DoubleValue Infinity JSON parse | 111.46 | — | — | 1107.44 (9.94x) | 274.77 (2.47x) |
| DoubleValue NegativeInfinity JSON stringify | 47.89 | — | — | 657.65 (13.73x) | 120.46 (2.52x) |
| DoubleValue NegativeInfinity JSON parse | 112.74 | — | — | 1122.71 (9.96x) | 290.22 (2.57x) |
| FloatValue JSON stringify | 72.12 | — | — | 807.88 (11.20x) | 335.51 (4.65x) |
| FloatValue JSON parse | 117.84 | — | — | 1224.43 (10.39x) | 293.55 (2.49x) |
| FloatValue String JSON parse | 118.77 | — | — | 1168.15 (9.84x) | 360.65 (3.04x) |
| FloatValue Exponent JSON parse | 119.88 | — | — | 1237.02 (10.32x) | 298.57 (2.49x) |
| NegativeFloatValue JSON stringify | 70.90 | — | — | 800.15 (11.29x) | 189.43 (2.67x) |
| NegativeFloatValue JSON parse | 118.46 | — | — | 1232.17 (10.40x) | 293.54 (2.48x) |
| ZeroFloatValue JSON stringify | 47.27 | — | — | 745.15 (15.76x) | 272.41 (5.76x) |
| ZeroFloatValue JSON parse | 114.77 | — | — | 1152.05 (10.04x) | 497.86 (4.34x) |
| FloatValue NaN JSON stringify | 46.23 | — | — | 641.89 (13.88x) | 129.31 (2.80x) |
| FloatValue NaN JSON parse | 111.21 | — | — | 1092.36 (9.82x) | 265.98 (2.39x) |
| FloatValue Infinity JSON stringify | 47.64 | — | — | 645.67 (13.55x) | 124.71 (2.62x) |
| FloatValue Infinity JSON parse | 112.29 | — | — | 1105.01 (9.84x) | 293.52 (2.61x) |
| FloatValue NegativeInfinity JSON stringify | 47.94 | — | — | 636.03 (13.27x) | 124.15 (2.59x) |
| FloatValue NegativeInfinity JSON parse | 114.61 | — | — | 1097.77 (9.58x) | 281.84 (2.46x) |
| Int64Value JSON stringify | 50.04 | — | — | 674.98 (13.49x) | 279.28 (5.58x) |
| Int64Value JSON parse | 124.59 | — | — | 1223.47 (9.82x) | 469.37 (3.77x) |
| Int64Value Number JSON parse | 127.75 | — | — | 1301.59 (10.19x) | 372.18 (2.91x) |
| Int64Value Exponent JSON parse | 116.13 | — | — | 1220.97 (10.51x) | 358.07 (3.08x) |
| ZeroInt64Value JSON stringify | 41.42 | — | — | 613.86 (14.82x) | 199.63 (4.82x) |
| ZeroInt64Value JSON parse | 105.25 | — | — | 1102.48 (10.47x) | 347.80 (3.30x) |
| NegativeInt64Value JSON stringify | 48.58 | — | — | 690.02 (14.20x) | 281.62 (5.80x) |
| NegativeInt64Value JSON parse | 126.31 | — | — | 1225.52 (9.70x) | 481.05 (3.81x) |
| MinInt64Value JSON stringify | 49.64 | — | — | 674.06 (13.58x) | 288.20 (5.81x) |
| MinInt64Value JSON parse | 140.50 | — | — | 1255.50 (8.94x) | 504.51 (3.59x) |
| MaxInt64Value JSON stringify | 49.79 | — | — | 674.14 (13.54x) | 291.33 (5.85x) |
| MaxInt64Value JSON parse | 136.50 | — | — | 1251.81 (9.17x) | 478.32 (3.50x) |
| UInt64Value JSON stringify | 50.38 | — | — | 673.63 (13.37x) | 283.68 (5.63x) |
| UInt64Value JSON parse | 137.50 | — | — | 1212.14 (8.82x) | 459.85 (3.34x) |
| UInt64Value Number JSON parse | 134.27 | — | — | 1284.45 (9.57x) | 349.60 (2.60x) |
| UInt64Value Exponent JSON parse | 122.74 | — | — | 1233.19 (10.05x) | 365.63 (2.98x) |
| ZeroUInt64Value JSON stringify | 41.69 | — | — | 608.82 (14.60x) | 309.99 (7.44x) |
| ZeroUInt64Value JSON parse | 111.53 | — | — | 1093.45 (9.80x) | 332.34 (2.98x) |
| MaxUInt64Value JSON stringify | 50.16 | — | — | 675.49 (13.47x) | 289.51 (5.77x) |
| MaxUInt64Value JSON parse | 151.43 | — | — | 1252.94 (8.27x) | 469.95 (3.10x) |
| Int32Value JSON stringify | 49.02 | — | — | 637.07 (13.00x) | 129.86 (2.65x) |
| Int32Value JSON parse | 132.65 | — | — | 1193.36 (9.00x) | 314.07 (2.37x) |
| Int32Value String JSON parse | 137.33 | — | — | 1139.40 (8.30x) | 399.54 (2.91x) |
| Int32Value Exponent JSON parse | 136.42 | — | — | 1235.10 (9.05x) | 358.89 (2.63x) |
| ZeroInt32Value JSON stringify | 50.06 | — | — | 623.05 (12.45x) | 132.00 (2.64x) |
| ZeroInt32Value JSON parse | 128.25 | — | — | 1167.78 (9.11x) | 271.96 (2.12x) |
| NegativeInt32Value JSON stringify | 46.67 | — | — | 645.50 (13.83x) | 140.40 (3.01x) |
| NegativeInt32Value JSON parse | 131.90 | — | — | 1199.58 (9.09x) | 326.82 (2.48x) |
| MinInt32Value JSON stringify | 47.15 | — | — | 642.37 (13.62x) | 136.88 (2.90x) |
| MinInt32Value JSON parse | 137.26 | — | — | 1210.44 (8.82x) | 356.89 (2.60x) |
| MaxInt32Value JSON stringify | 49.99 | — | — | 634.66 (12.70x) | 132.04 (2.64x) |
| MaxInt32Value JSON parse | 137.87 | — | — | 1203.75 (8.73x) | 335.22 (2.43x) |
| UInt32Value JSON stringify | 50.11 | — | — | 631.80 (12.61x) | 136.81 (2.73x) |
| UInt32Value JSON parse | 132.63 | — | — | 1192.89 (8.99x) | 308.82 (2.33x) |
| UInt32Value String JSON parse | 138.30 | — | — | 1141.47 (8.25x) | 395.08 (2.86x) |
| UInt32Value Exponent JSON parse | 136.73 | — | — | 1228.09 (8.98x) | 358.91 (2.62x) |
| ZeroUInt32Value JSON stringify | 50.54 | — | — | 614.74 (12.16x) | 137.46 (2.72x) |
| ZeroUInt32Value JSON parse | 128.30 | — | — | 1196.14 (9.32x) | 274.22 (2.14x) |
| MaxUInt32Value JSON stringify | 51.02 | — | — | 633.12 (12.41x) | 138.58 (2.72x) |
| MaxUInt32Value JSON parse | 140.38 | — | — | 1203.92 (8.58x) | 340.80 (2.43x) |
| BoolValue JSON stringify | 44.18 | — | — | 620.90 (14.05x) | 124.58 (2.82x) |
| BoolValue JSON parse | 60.15 | — | — | 1059.13 (17.61x) | 224.50 (3.73x) |
| FalseBoolValue JSON stringify | 44.09 | — | — | 602.00 (13.65x) | 214.76 (4.87x) |
| FalseBoolValue JSON parse | 59.89 | — | — | 1057.26 (17.65x) | 378.91 (6.33x) |
| StringValue JSON stringify | 52.53 | — | — | 655.61 (12.48x) | 187.69 (3.57x) |
| StringValue JSON parse | 121.03 | — | — | 1141.39 (9.43x) | 317.79 (2.63x) |
| StringValue Escape JSON parse | 129.64 | — | — | 1173.97 (9.06x) | 371.85 (2.87x) |
| StringValue Surrogate JSON parse | 128.44 | — | — | 1177.07 (9.16x) | 379.01 (2.95x) |
| EmptyStringValue JSON stringify | 48.38 | — | — | 621.72 (12.85x) | 178.74 (3.69x) |
| EmptyStringValue JSON parse | 66.06 | — | — | 1111.21 (16.82x) | 235.10 (3.56x) |
| BytesValue JSON stringify | 50.35 | — | — | 652.38 (12.96x) | 393.39 (7.81x) |
| BytesValue JSON parse | 124.16 | — | — | 1167.91 (9.41x) | 358.59 (2.89x) |
| BytesValue URL JSON parse | 140.86 | — | — | 1164.58 (8.27x) | 342.66 (2.43x) |
| BytesValue StandardBase64 JSON parse | 122.57 | — | — | 1177.84 (9.61x) | 336.21 (2.74x) |
| BytesValue Unpadded JSON parse | 122.42 | — | — | 1162.59 (9.50x) | 333.40 (2.72x) |
| EmptyBytesValue JSON stringify | 42.14 | — | — | 629.72 (14.94x) | 192.60 (4.57x) |
| EmptyBytesValue JSON parse | 67.72 | — | — | 1133.27 (16.73x) | 289.91 (4.28x) |
| TextFormat format | 182.28 | — | — | 2575.22 (14.13x) | 2560.76 (14.05x) |
| TextFormat parse | 705.38 | — | — | 4999.82 (7.09x) | 6598.71 (9.35x) |
| packed fixed32 encode | 2.01 | 550.81 (274.03x) | 542.02 (269.66x) | 43.25 (21.52x) | 1623.83 (807.88x) |
| packed fixed32 decode | 4.52 | 1046.52 (231.53x) | 1954.09 (432.32x) | 49.30 (10.91x) | 2942.95 (651.10x) |
| packed fixed64 encode | 2.01 | 575.76 (286.45x) | 562.66 (279.93x) | 75.73 (37.67x) | 707.14 (351.81x) |
| packed fixed64 decode | 4.53 | 1037.65 (229.06x) | 7941.34 (1753.06x) | 79.65 (17.58x) | 3799.86 (838.82x) |
| packed sfixed32 encode | 2.01 | 697.68 (347.10x) | 539.59 (268.45x) | 43.36 (21.57x) | 406.50 (202.24x) |
| packed sfixed32 decode | 4.53 | 1053.54 (232.57x) | 1942.04 (428.71x) | 48.52 (10.71x) | 1681.02 (371.09x) |
| packed sfixed64 encode | 2.01 | 573.16 (285.15x) | 563.88 (280.54x) | 75.84 (37.73x) | 782.65 (389.38x) |
| packed sfixed64 decode | 4.53 | 1039.63 (229.50x) | 7904.68 (1744.96x) | 79.19 (17.48x) | 3756.47 (829.24x) |
| packed float encode | 2.01 | 813.46 (404.71x) | 540.27 (268.79x) | 44.37 (22.07x) | 762.75 (379.48x) |
| packed float decode | 4.53 | 1048.40 (231.43x) | 2076.65 (458.42x) | 48.43 (10.69x) | 2690.83 (594.00x) |
| packed double encode | 2.01 | 831.76 (413.81x) | 565.86 (281.52x) | 75.99 (37.81x) | 1443.10 (717.96x) |
| packed double decode | 4.51 | 979.24 (217.13x) | 2049.40 (454.41x) | 79.12 (17.54x) | 8018.19 (1777.87x) |
| packed uint64 encode | 1294.91 | 4635.71 (3.58x) | 4214.25 (3.25x) | 2268.45 (1.75x) | 6366.25 (4.92x) |
| packed uint64 decode | 1781.76 | 2782.32 (1.56x) | 8853.85 (4.97x) | 2810.93 (1.58x) | 12528.97 (7.03x) |
| packed uint32 encode | 990.08 | 3617.90 (3.65x) | 3279.82 (3.31x) | 1778.47 (1.80x) | 5650.32 (5.71x) |
| packed uint32 decode | 1329.67 | 2435.97 (1.83x) | 3273.26 (2.46x) | 1991.31 (1.50x) | 9652.58 (7.26x) |
| packed int64 encode | 1416.67 | 10992.65 (7.76x) | 6061.34 (4.28x) | 2912.08 (2.06x) | 4160.15 (2.94x) |
| packed int64 decode | 2739.17 | 3393.89 (1.24x) | 10300.82 (3.76x) | 4486.22 (1.64x) | 7913.75 (2.89x) |
| packed sint32 encode | 779.04 | 3049.27 (3.91x) | 2867.31 (3.68x) | 1530.32 (1.96x) | 3415.83 (4.38x) |
| packed sint32 decode | 951.82 | 2547.30 (2.68x) | 3197.57 (3.36x) | 1128.62 (1.19x) | 3136.54 (3.30x) |
| packed sint64 encode | 1416.86 | 4934.85 (3.48x) | 4308.71 (3.04x) | 2406.45 (1.70x) | 4168.26 (2.94x) |
| packed sint64 decode | 2038.83 | 3070.39 (1.51x) | 9654.03 (4.74x) | 2958.70 (1.45x) | 6664.95 (3.27x) |
| packed bool encode | 2.00 | 1319.58 (659.79x) | 538.38 (269.19x) | 16.05 (8.03x) | 2237.93 (1118.96x) |
| packed bool decode | 267.10 | 1526.91 (5.72x) | 2744.03 (10.27x) | 803.56 (3.01x) | 1598.39 (5.98x) |
| packed enum encode | 272.23 | 2729.64 (10.03x) | 1817.04 (6.67x) | 1082.75 (3.98x) | 2489.27 (9.14x) |
| packed enum decode | 154.23 | 1555.33 (10.08x) | 2873.01 (18.63x) | 699.75 (4.54x) | 2036.25 (13.20x) |
| large map encode | 4075.39 | 16422.48 (4.03x) | 9683.02 (2.38x) | 20860.80 (5.12x) | 210642.89 (51.69x) |
| shuffled large map deterministic binary encode | 27747.53 | — | — | 93184.50 (3.36x) | 444948.06 (16.04x) |
| large map decode | 25734.75 | 91248.07 (3.55x) | 90112.40 (3.50x) | 94477.10 (3.67x) | 283118.32 (11.00x) |
The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound `Duration`, non-empty/escaped-input parse/number-exponent parse and empty `Struct`, object/escaped-object parse/object-number-exponent/list/escaped-list/string-scalar/escaped-string-scalar/surrogate-string-scalar/number-exponent/negative-number `Value` (including default-like scalar and empty object/list kinds),
`FieldMask` (non-empty, escaped JSON parse input, and empty), escaped-input parse/short-fraction parse/micro/nano/offset/min/pre/post/max-bound `Timestamp`, `Empty`, min/zero/positive/number-input parse/numeric-exponent parse/negative/max `Int64Value`, negative/zero/positive finite/string-input parse/numeric-exponent parse `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), negative/zero/positive finite/string-input parse/numeric-exponent parse `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), zero/normal/number-input parse/numeric-exponent parse/max `UInt64Value`, min/zero/positive/string-input parse/numeric-exponent parse/negative/max `Int32Value`, zero/normal/string-input parse/numeric-exponent parse/max `UInt32Value`, true/false `BoolValue`, non-empty/escape-input parse/surrogate-pair parse/empty `StringValue`, padded-standard/base64url/unpadded-base64 parse/empty `BytesValue`, and recursive nested `Any` payloads), direct zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound Duration, non-empty/escaped-input parse/empty FieldMask, and escaped-input parse/short-fraction parse/micro/nano/offset/min/pre/post/max-bound Timestamp WKT JSON plus other direct WKT JSON, including non-empty/escaped-input parse/number-exponent parse/empty `Struct`, object/escaped-object parse/object-number-exponent/list/escaped-list/string-scalar/escaped-string-scalar/surrogate-string-scalar/number-exponent/negative-number `Value`, and escaped/non-empty/empty `ListValue`, TextFormat, packed scalars, large bytes,
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
