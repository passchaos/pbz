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

For noisy shared machines, run all compared implementations on the same CPU set
with `PBZ_COMPARE_CPUSET`, for example:

```sh
PBZ_COMPARE_CPUSET=3 bench/run_compare.sh 2>&1 | tee /tmp/pbz-compare.log
```

Latest accepted comparison (`/tmp/pbz-compare-scalarmix-json-cpu3.log`,
summarized in `/tmp/pbz-summary-scalarmix-json-cpu3.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Pivoted rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 21.78 | 105.17 (4.83x) | 51.21 (2.35x) | 106.25 (4.88x) | 863.52 (39.65x) |
| binary decode | 132.09 | 253.67 (1.92x) | 232.54 (1.76x) | 222.94 (1.69x) | 914.49 (6.92x) |
| unknown fields count by number | 3.64 | — | — | 163.19 (44.83x) | — |
| deterministic binary encode | 62.69 | — | — | 126.90 (2.02x) | 1164.43 (18.57x) |
| scalarmix encode | 18.79 | 94.47 (5.03x) | 49.02 (2.61x) | 29.37 (1.56x) | 202.96 (10.80x) |
| scalarmix decode | 42.47 | 138.09 (3.25x) | 176.47 (4.16x) | 83.82 (1.97x) | 327.90 (7.72x) |
| ScalarMix JSON stringify | 313.57 | — | — | 4805.03 (15.32x) | 3765.41 (12.01x) |
| ScalarMix JSON parse | 2694.28 | — | — | 11865.10 (4.40x) | 8354.35 (3.10x) |
| textbytes encode | 9.66 | 78.23 (8.10x) | 37.31 (3.86x) | 118.89 (12.31x) | 145.79 (15.09x) |
| textbytes decode | 36.07 | 378.83 (10.50x) | 238.92 (6.62x) | 163.06 (4.52x) | 676.65 (18.76x) |
| TextBytes JSON stringify | 340.26 | — | — | 2258.07 (6.64x) | 2277.09 (6.69x) |
| TextBytes JSON parse | 1336.95 | — | — | 5709.34 (4.27x) | 4036.10 (3.02x) |
| largebytes encode | 25.81 | 2713.28 (105.13x) | 2665.18 (103.26x) | 2746.44 (106.41x) | 2700.90 (104.65x) |
| largebytes decode | 91.79 | 5617.53 (61.20x) | 3035.36 (33.07x) | 2822.83 (30.75x) | 21756.43 (237.02x) |
| presencemix encode | 18.79 | 62.78 (3.34x) | 29.28 (1.56x) | 54.69 (2.91x) | 224.03 (11.92x) |
| presencemix decode | 58.90 | 135.54 (2.30x) | 110.80 (1.88x) | 160.66 (2.73x) | 505.57 (8.58x) |
| PresenceMix JSON stringify | 146.20 | — | — | 3065.47 (20.97x) | 2406.94 (16.46x) |
| PresenceMix JSON parse | 1175.40 | — | — | 6149.17 (5.23x) | 3189.92 (2.71x) |
| complex encode | 53.13 | 143.42 (2.70x) | 96.69 (1.82x) | 152.50 (2.87x) | 965.17 (18.17x) |
| complex decode | 176.21 | 397.02 (2.25x) | 335.06 (1.90x) | 401.64 (2.28x) | 1376.54 (7.81x) |
| complex deterministic binary encode | 92.40 | — | — | 165.44 (1.79x) | 1164.09 (12.60x) |
| complex JSON stringify | 299.34 | — | — | 4920.96 (16.44x) | 6288.80 (21.01x) |
| complex JSON parse | 2396.85 | — | — | 12064.40 (5.03x) | 7666.38 (3.20x) |
| Complex ProtoName JSON stringify | 305.51 | — | — | 5295.70 (17.33x) | 6393.71 (20.93x) |
| Complex ProtoName JSON parse | 2396.76 | — | — | 12858.00 (5.36x) | 8123.31 (3.39x) |
| complex TextFormat format | 273.58 | — | — | 3816.58 (13.95x) | 5518.92 (20.17x) |
| complex TextFormat parse | 1816.69 | — | — | 6965.83 (3.83x) | 8548.42 (4.71x) |
| packed int32 encode | 663.79 | 3184.01 (4.80x) | 2537.04 (3.82x) | 1235.92 (1.86x) | 2856.14 (4.30x) |
| packed int32 decode | 690.81 | 1901.79 (2.75x) | 3248.68 (4.70x) | 931.02 (1.35x) | 2717.53 (3.93x) |
| JSON stringify | 162.53 | — | — | 3047.47 (18.75x) | 2367.22 (14.56x) |
| AlwaysPrint JSON stringify | 61.44 | — | — | 2670.20 (43.46x) | 1395.60 (22.71x) |
| ProtoName JSON stringify | 312.85 | — | — | 4789.86 (15.31x) | 3813.85 (12.19x) |
| EnumNumber JSON stringify | 286.26 | — | — | 4773.50 (16.68x) | 3745.67 (13.08x) |
| JSON parse | 1521.62 | — | — | 7459.80 (4.90x) | 4703.15 (3.09x) |
| MapKeySurrogate JSON parse | 432.44 | — | — | 3505.47 (8.11x) | 1068.92 (2.47x) |
| NullFields JSON parse | 549.43 | — | — | 2113.65 (3.85x) | 851.86 (1.55x) |
| IgnoreUnknown JSON parse | 1243.42 | — | — | 5409.98 (4.35x) | 2639.67 (2.12x) |
| OpenEnum JSON parse | 297.59 | — | — | 3815.28 (12.82x) | 528.64 (1.78x) |
| EnumName JSON parse | 294.87 | — | — | 3833.74 (13.00x) | 524.65 (1.78x) |
| ProtoName JSON parse | 536.20 | — | — | 4093.01 (7.63x) | 1273.34 (2.37x) |
| IntExponent JSON parse | 1680.53 | — | — | 7243.66 (4.31x) | 4218.84 (2.51x) |
| StringNumber JSON parse | 1658.43 | — | — | 7055.57 (4.25x) | 4655.58 (2.81x) |
| Any WKT JSON stringify | 132.65 | — | — | 1896.97 (14.30x) | 991.02 (7.47x) |
| Any WKT JSON parse | 529.19 | — | — | 3016.98 (5.70x) | 1524.07 (2.88x) |
| Any Duration Escape WKT JSON parse | 548.46 | — | — | 3042.29 (5.55x) | 1648.04 (3.00x) |
| Any PlusDuration WKT JSON parse | 531.48 | — | — | 3033.11 (5.71x) | 1582.09 (2.98x) |
| Any ShortFractionDuration WKT JSON parse | 525.43 | — | — | 2982.91 (5.68x) | 1571.81 (2.99x) |
| Any MicroDuration WKT JSON stringify | 134.36 | — | — | 1911.26 (14.22x) | 1001.84 (7.46x) |
| Any MicroDuration WKT JSON parse | 531.02 | — | — | 3028.41 (5.70x) | 1564.47 (2.95x) |
| Any NanoDuration WKT JSON stringify | 136.29 | — | — | 1934.21 (14.19x) | 996.95 (7.31x) |
| Any NanoDuration WKT JSON parse | 536.02 | — | — | 3014.82 (5.62x) | 1597.96 (2.98x) |
| Any NegativeDuration WKT JSON stringify | 135.97 | — | — | 1941.53 (14.28x) | 1027.77 (7.56x) |
| Any NegativeDuration WKT JSON parse | 532.59 | — | — | 3124.81 (5.87x) | 1590.78 (2.99x) |
| Any FractionalNegativeDuration WKT JSON stringify | 129.62 | — | — | 1915.64 (14.78x) | 991.40 (7.65x) |
| Any FractionalNegativeDuration WKT JSON parse | 520.93 | — | — | 3067.03 (5.89x) | 1540.45 (2.96x) |
| Any MaxDuration WKT JSON stringify | 120.90 | — | — | 1747.15 (14.45x) | 1006.19 (8.32x) |
| Any MaxDuration WKT JSON parse | 535.67 | — | — | 3011.94 (5.62x) | 1588.26 (2.96x) |
| Any MinDuration WKT JSON stringify | 122.62 | — | — | 1764.41 (14.39x) | 1027.71 (8.38x) |
| Any MinDuration WKT JSON parse | 536.30 | — | — | 3052.96 (5.69x) | 1556.49 (2.90x) |
| Any ZeroDuration WKT JSON stringify | 108.35 | — | — | 909.93 (8.40x) | 958.80 (8.85x) |
| Any ZeroDuration WKT JSON parse | 478.36 | — | — | 2266.24 (4.74x) | 1454.61 (3.04x) |
| Any FieldMask WKT JSON stringify | 234.54 | — | — | 1752.00 (7.47x) | 1421.99 (6.06x) |
| Any FieldMask WKT JSON parse | 719.53 | — | — | 3177.71 (4.42x) | 2094.08 (2.91x) |
| Any FieldMask Escape WKT JSON parse | 749.40 | — | — | 3271.19 (4.37x) | 2271.27 (3.03x) |
| Any EmptyFieldMask WKT JSON stringify | 116.31 | — | — | 919.06 (7.90x) | 790.25 (6.79x) |
| Any EmptyFieldMask WKT JSON parse | 448.96 | — | — | 2167.16 (4.83x) | 1320.48 (2.94x) |
| Any Timestamp WKT JSON stringify | 180.27 | — | — | 2029.87 (11.26x) | 1022.24 (5.67x) |
| Any Timestamp WKT JSON parse | 574.86 | — | — | 3038.35 (5.29x) | 1632.80 (2.84x) |
| Any Timestamp Escape WKT JSON parse | 598.89 | — | — | 3099.66 (5.18x) | 1799.83 (3.01x) |
| Any ShortFraction Timestamp WKT JSON parse | 573.88 | — | — | 3039.17 (5.30x) | 1628.15 (2.84x) |
| Any Micro Timestamp WKT JSON stringify | 181.42 | — | — | 2035.68 (11.22x) | 1023.62 (5.64x) |
| Any Micro Timestamp WKT JSON parse | 583.32 | — | — | 3058.32 (5.24x) | 1646.12 (2.82x) |
| Any Nano Timestamp WKT JSON stringify | 179.53 | — | — | 2043.53 (11.38x) | 1014.93 (5.65x) |
| Any Nano Timestamp WKT JSON parse | 588.40 | — | — | 3052.41 (5.19x) | 1670.06 (2.84x) |
| Any Offset Timestamp WKT JSON parse | 594.39 | — | — | 3070.02 (5.16x) | 1686.76 (2.84x) |
| Any PreEpoch Timestamp WKT JSON stringify | 146.65 | — | — | 1949.84 (13.30x) | 986.56 (6.73x) |
| Any PreEpoch Timestamp WKT JSON parse | 568.80 | — | — | 3060.91 (5.38x) | 1617.55 (2.84x) |
| Any Max Timestamp WKT JSON stringify | 163.42 | — | — | 2056.62 (12.58x) | 1007.13 (6.16x) |
| Any Max Timestamp WKT JSON parse | 589.94 | — | — | 3103.37 (5.26x) | 1660.88 (2.82x) |
| Any Min Timestamp WKT JSON stringify | 160.89 | — | — | 1941.23 (12.07x) | 978.75 (6.08x) |
| Any Min Timestamp WKT JSON parse | 563.91 | — | — | 3049.32 (5.41x) | 1621.06 (2.87x) |
| Any Empty WKT JSON stringify | 94.31 | — | — | 911.36 (9.66x) | 634.12 (6.72x) |
| Any Empty WKT JSON parse | 339.61 | — | — | 2142.49 (6.31x) | 1362.83 (4.01x) |
| Any Struct WKT JSON stringify | 642.37 | — | — | 5883.69 (9.16x) | 6111.83 (9.51x) |
| Any Struct WKT JSON parse | 1749.68 | — | — | 11112.20 (6.35x) | 8840.49 (5.05x) |
| Any Struct Escape WKT JSON parse | 1774.95 | — | — | 11166.60 (6.29x) | 9060.55 (5.10x) |
| Any Struct NumberExponent WKT JSON parse | 1743.19 | — | — | 11126.00 (6.38x) | 8917.82 (5.12x) |
| Any Struct Surrogate WKT JSON parse | 763.20 | — | — | 6393.61 (8.38x) | 3135.82 (4.11x) |
| Any Struct KeySurrogate WKT JSON parse | 757.51 | — | — | 6303.42 (8.32x) | 3099.28 (4.09x) |
| Any EmptyStruct WKT JSON stringify | 120.09 | — | — | 908.85 (7.57x) | 954.46 (7.95x) |
| Any EmptyStruct WKT JSON parse | 443.83 | — | — | 2252.48 (5.08x) | 1605.16 (3.62x) |
| Any Value WKT JSON stringify | 662.85 | — | — | 5874.44 (8.86x) | 6522.85 (9.84x) |
| Any Value WKT JSON parse | 1797.64 | — | — | 11384.70 (6.33x) | 9230.19 (5.13x) |
| Any Value Escape WKT JSON parse | 1819.98 | — | — | 11453.00 (6.29x) | 9382.60 (5.16x) |
| Any Value NumberExponent WKT JSON parse | 1811.37 | — | — | 11401.70 (6.29x) | 9231.44 (5.10x) |
| Any Value Surrogate WKT JSON parse | 819.50 | — | — | 6526.19 (7.96x) | 3501.00 (4.27x) |
| Any Value KeySurrogate WKT JSON parse | 814.46 | — | — | 6514.81 (8.00x) | 3494.00 (4.29x) |
| Any NullValue WKT JSON stringify | 132.38 | — | — | 2260.17 (17.07x) | 917.80 (6.93x) |
| Any NullValue WKT JSON parse | 470.57 | — | — | 4090.69 (8.69x) | 1621.29 (3.45x) |
| Any StringScalarValue WKT JSON stringify | 160.19 | — | — | 2284.32 (14.26x) | 991.23 (6.19x) |
| Any StringScalarValue WKT JSON parse | 522.01 | — | — | 3658.95 (7.01x) | 1691.42 (3.24x) |
| Any StringScalarValue Escape WKT JSON parse | 531.27 | — | — | 3692.17 (6.95x) | 1798.53 (3.39x) |
| Any StringScalarValue Surrogate WKT JSON parse | 536.80 | — | — | 3676.36 (6.85x) | 1775.86 (3.31x) |
| Any EmptyStringScalarValue WKT JSON stringify | 148.14 | — | — | 2291.84 (15.47x) | 940.93 (6.35x) |
| Any EmptyStringScalarValue WKT JSON parse | 490.92 | — | — | 3634.95 (7.40x) | 1629.94 (3.32x) |
| Any NumberValue WKT JSON stringify | 176.69 | — | — | 2525.85 (14.30x) | 1038.84 (5.88x) |
| Any NumberValue WKT JSON parse | 512.99 | — | — | 3708.14 (7.23x) | 1646.91 (3.21x) |
| Any NumberValue Exponent WKT JSON parse | 513.56 | — | — | 3716.32 (7.24x) | 1642.18 (3.20x) |
| Any NegativeNumberValue WKT JSON stringify | 173.15 | — | — | 2516.53 (14.53x) | 1040.79 (6.01x) |
| Any NegativeNumberValue WKT JSON parse | 509.26 | — | — | 3700.03 (7.27x) | 1648.46 (3.24x) |
| Any ZeroNumberValue WKT JSON stringify | 141.65 | — | — | 2477.03 (17.49x) | 932.72 (6.58x) |
| Any ZeroNumberValue WKT JSON parse | 510.90 | — | — | 3650.15 (7.14x) | 1658.69 (3.25x) |
| Any BoolScalarValue WKT JSON stringify | 132.55 | — | — | 2257.09 (17.03x) | 916.15 (6.91x) |
| Any BoolScalarValue WKT JSON parse | 465.68 | — | — | 3628.90 (7.79x) | 1578.91 (3.39x) |
| Any FalseBoolScalarValue WKT JSON stringify | 129.89 | — | — | 2276.86 (17.53x) | 922.84 (7.10x) |
| Any FalseBoolScalarValue WKT JSON parse | 469.09 | — | — | 3621.44 (7.72x) | 1591.01 (3.39x) |
| Any ListKindValue WKT JSON stringify | 515.47 | — | — | 5601.31 (10.87x) | 4786.63 (9.29x) |
| Any ListKindValue WKT JSON parse | 1397.00 | — | — | 9893.30 (7.08x) | 7128.71 (5.10x) |
| Any ListKindValue Escape WKT JSON parse | 1411.98 | — | — | 9971.22 (7.06x) | 7343.30 (5.20x) |
| Any ListKindValue Surrogate WKT JSON parse | 730.65 | — | — | 4847.14 (6.63x) | 2707.37 (3.71x) |
| Any EmptyStructKindValue WKT JSON stringify | 145.51 | — | — | 2922.89 (20.09x) | 1284.98 (8.83x) |
| Any EmptyStructKindValue WKT JSON parse | 502.02 | — | — | 5413.86 (10.78x) | 2000.70 (3.99x) |
| Any EmptyListKindValue WKT JSON stringify | 142.61 | — | — | 2909.17 (20.40x) | 1103.84 (7.74x) |
| Any EmptyListKindValue WKT JSON parse | 506.33 | — | — | 4405.48 (8.70x) | 1919.68 (3.79x) |
| Any DoubleValue WKT JSON stringify | 193.23 | — | — | 1801.08 (9.32x) | 817.58 (4.23x) |
| Any DoubleValue WKT JSON parse | 528.46 | — | — | 2752.10 (5.21x) | 1473.24 (2.79x) |
| Any DoubleValue String WKT JSON parse | 546.58 | — | — | 2747.54 (5.03x) | 1527.39 (2.79x) |
| Any DoubleValue Exponent WKT JSON parse | 533.20 | — | — | 2759.49 (5.18x) | 1480.76 (2.78x) |
| Any NegativeDoubleValue WKT JSON stringify | 192.44 | — | — | 1802.91 (9.37x) | 807.72 (4.20x) |
| Any NegativeDoubleValue WKT JSON parse | 529.25 | — | — | 2747.05 (5.19x) | 1464.97 (2.77x) |
| Any ZeroDoubleValue WKT JSON stringify | 157.39 | — | — | 917.92 (5.83x) | 743.85 (4.73x) |
| Any ZeroDoubleValue WKT JSON parse | 525.39 | — | — | 2180.30 (4.15x) | 1402.26 (2.67x) |
| Any DoubleValue NaN WKT JSON stringify | 162.23 | — | — | 1572.68 (9.69x) | 715.30 (4.41x) |
| Any DoubleValue NaN WKT JSON parse | 520.29 | — | — | 2679.96 (5.15x) | 1437.84 (2.76x) |
| Any DoubleValue Infinity WKT JSON stringify | 168.80 | — | — | 1563.20 (9.26x) | 728.12 (4.31x) |
| Any DoubleValue Infinity WKT JSON parse | 524.64 | — | — | 2712.20 (5.17x) | 1434.74 (2.73x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 163.73 | — | — | 1558.02 (9.52x) | 720.84 (4.40x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 528.23 | — | — | 2677.73 (5.07x) | 1434.89 (2.72x) |
| Any FloatValue WKT JSON stringify | 190.94 | — | — | 1737.47 (9.10x) | 803.57 (4.21x) |
| Any FloatValue WKT JSON parse | 527.33 | — | — | 2712.44 (5.14x) | 1419.89 (2.69x) |
| Any FloatValue String WKT JSON parse | 537.17 | — | — | 2707.67 (5.04x) | 1538.54 (2.86x) |
| Any FloatValue Exponent WKT JSON parse | 529.57 | — | — | 2716.50 (5.13x) | 1482.21 (2.80x) |
| Any NegativeFloatValue WKT JSON stringify | 194.34 | — | — | 1743.66 (8.97x) | 788.62 (4.06x) |
| Any NegativeFloatValue WKT JSON parse | 525.13 | — | — | 2729.68 (5.20x) | 1455.08 (2.77x) |
| Any ZeroFloatValue WKT JSON stringify | 155.24 | — | — | 916.72 (5.91x) | 731.66 (4.71x) |
| Any ZeroFloatValue WKT JSON parse | 527.39 | — | — | 2167.19 (4.11x) | 1387.87 (2.63x) |
| Any FloatValue NaN WKT JSON stringify | 163.87 | — | — | 1568.92 (9.57x) | 725.91 (4.43x) |
| Any FloatValue NaN WKT JSON parse | 522.56 | — | — | 2640.86 (5.05x) | 1399.78 (2.68x) |
| Any FloatValue Infinity WKT JSON stringify | 164.52 | — | — | 1556.47 (9.46x) | 718.92 (4.37x) |
| Any FloatValue Infinity WKT JSON parse | 525.26 | — | — | 2695.82 (5.13x) | 1407.81 (2.68x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 172.59 | — | — | 1547.48 (8.97x) | 721.52 (4.18x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 528.73 | — | — | 2658.42 (5.03x) | 1404.53 (2.66x) |
| Any Int64Value WKT JSON stringify | 171.56 | — | — | 1585.08 (9.24x) | 872.17 (5.08x) |
| Any Int64Value WKT JSON parse | 555.68 | — | — | 2798.73 (5.04x) | 1675.41 (3.02x) |
| Any Int64Value Number WKT JSON parse | 550.46 | — | — | 2750.70 (5.00x) | 1567.84 (2.85x) |
| Any Int64Value Exponent WKT JSON parse | 539.83 | — | — | 2708.68 (5.02x) | 1501.84 (2.78x) |
| Any ZeroInt64Value WKT JSON stringify | 159.89 | — | — | 916.96 (5.73x) | 794.20 (4.97x) |
| Any ZeroInt64Value WKT JSON parse | 529.87 | — | — | 2155.60 (4.07x) | 1509.28 (2.85x) |
| Any NegativeInt64Value WKT JSON stringify | 167.96 | — | — | 1560.29 (9.29x) | 850.88 (5.07x) |
| Any NegativeInt64Value WKT JSON parse | 559.83 | — | — | 2801.68 (5.00x) | 1696.22 (3.03x) |
| Any MinInt64Value WKT JSON stringify | 171.24 | — | — | 1565.23 (9.14x) | 874.94 (5.11x) |
| Any MinInt64Value WKT JSON parse | 561.40 | — | — | 2840.64 (5.06x) | 1707.18 (3.04x) |
| Any MaxInt64Value WKT JSON stringify | 179.86 | — | — | 1574.51 (8.75x) | 859.30 (4.78x) |
| Any MaxInt64Value WKT JSON parse | 559.60 | — | — | 2828.85 (5.06x) | 1717.35 (3.07x) |
| Any UInt64Value WKT JSON stringify | 173.53 | — | — | 1570.26 (9.05x) | 858.97 (4.95x) |
| Any UInt64Value WKT JSON parse | 563.20 | — | — | 2798.85 (4.97x) | 1677.11 (2.98x) |
| Any UInt64Value Number WKT JSON parse | 555.69 | — | — | 2767.09 (4.98x) | 1547.44 (2.78x) |
| Any UInt64Value Exponent WKT JSON parse | 547.08 | — | — | 2726.81 (4.98x) | 1507.52 (2.76x) |
| Any ZeroUInt64Value WKT JSON stringify | 164.93 | — | — | 914.93 (5.55x) | 785.59 (4.76x) |
| Any ZeroUInt64Value WKT JSON parse | 534.13 | — | — | 2171.84 (4.07x) | 1538.78 (2.88x) |
| Any MaxUInt64Value WKT JSON stringify | 176.13 | — | — | 1569.34 (8.91x) | 871.38 (4.95x) |
| Any MaxUInt64Value WKT JSON parse | 571.42 | — | — | 2833.32 (4.96x) | 1709.86 (2.99x) |
| Any Int32Value WKT JSON stringify | 174.85 | — | — | 1548.33 (8.86x) | 755.66 (4.32x) |
| Any Int32Value WKT JSON parse | 545.37 | — | — | 2666.95 (4.89x) | 1484.81 (2.72x) |
| Any Int32Value String WKT JSON parse | 551.31 | — | — | 2685.49 (4.87x) | 1554.35 (2.82x) |
| Any Int32Value Exponent WKT JSON parse | 550.90 | — | — | 2707.28 (4.91x) | 1518.69 (2.76x) |
| Any ZeroInt32Value WKT JSON stringify | 166.45 | — | — | 923.43 (5.55x) | 715.52 (4.30x) |
| Any ZeroInt32Value WKT JSON parse | 542.26 | — | — | 2167.25 (4.00x) | 1406.72 (2.59x) |
| Any NegativeInt32Value WKT JSON stringify | 173.10 | — | — | 1555.67 (8.99x) | 730.00 (4.22x) |
| Any NegativeInt32Value WKT JSON parse | 547.38 | — | — | 2701.04 (4.93x) | 1456.02 (2.66x) |
| Any MinInt32Value WKT JSON stringify | 169.15 | — | — | 1562.62 (9.24x) | 735.79 (4.35x) |
| Any MinInt32Value WKT JSON parse | 553.92 | — | — | 2727.64 (4.92x) | 1510.94 (2.73x) |
| Any MaxInt32Value WKT JSON stringify | 174.10 | — | — | 1562.53 (8.97x) | 748.78 (4.30x) |
| Any MaxInt32Value WKT JSON parse | 549.96 | — | — | 2694.47 (4.90x) | 1473.19 (2.68x) |
| Any UInt32Value WKT JSON stringify | 174.11 | — | — | 1589.24 (9.13x) | 746.58 (4.29x) |
| Any UInt32Value WKT JSON parse | 542.78 | — | — | 2700.46 (4.98x) | 1444.13 (2.66x) |
| Any UInt32Value String WKT JSON parse | 551.94 | — | — | 2715.93 (4.92x) | 1529.27 (2.77x) |
| Any UInt32Value Exponent WKT JSON parse | 548.24 | — | — | 2723.99 (4.97x) | 1510.34 (2.75x) |
| Any ZeroUInt32Value WKT JSON stringify | 174.66 | — | — | 926.07 (5.30x) | 727.64 (4.17x) |
| Any ZeroUInt32Value WKT JSON parse | 540.75 | — | — | 2189.68 (4.05x) | 1465.45 (2.71x) |
| Any MaxUInt32Value WKT JSON stringify | 179.45 | — | — | 1578.56 (8.80x) | 786.86 (4.38x) |
| Any MaxUInt32Value WKT JSON parse | 551.85 | — | — | 2738.71 (4.96x) | 1501.73 (2.72x) |
| Any BoolValue WKT JSON stringify | 178.39 | — | — | 1526.94 (8.56x) | 751.05 (4.21x) |
| Any BoolValue WKT JSON parse | 494.50 | — | — | 2611.80 (5.28x) | 1359.71 (2.75x) |
| Any FalseBoolValue WKT JSON stringify | 177.15 | — | — | 912.20 (5.15x) | 718.86 (4.06x) |
| Any FalseBoolValue WKT JSON parse | 494.71 | — | — | 2153.98 (4.35x) | 1429.63 (2.89x) |
| Any StringValue WKT JSON stringify | 203.95 | — | — | 1566.79 (7.68x) | 836.71 (4.10x) |
| Any StringValue WKT JSON parse | 558.25 | — | — | 2673.57 (4.79x) | 1452.70 (2.60x) |
| Any StringValue Escape WKT JSON parse | 564.36 | — | — | 2719.33 (4.82x) | 1561.01 (2.77x) |
| Any StringValue Surrogate WKT JSON parse | 572.97 | — | — | 2722.62 (4.75x) | 1615.26 (2.82x) |
| Any EmptyStringValue WKT JSON stringify | 189.73 | — | — | 917.47 (4.84x) | 797.07 (4.20x) |
| Any EmptyStringValue WKT JSON parse | 528.37 | — | — | 2207.93 (4.18x) | 1412.96 (2.67x) |
| Any BytesValue WKT JSON stringify | 183.75 | — | — | 1582.46 (8.61x) | 842.34 (4.58x) |
| Any BytesValue WKT JSON parse | 566.55 | — | — | 2691.37 (4.75x) | 1488.59 (2.63x) |
| Any BytesValue URL WKT JSON parse | 584.88 | — | — | 2709.44 (4.63x) | 1543.04 (2.64x) |
| Any BytesValue StandardBase64 WKT JSON parse | 571.46 | — | — | 2720.31 (4.76x) | 1511.98 (2.65x) |
| Any BytesValue Unpadded WKT JSON parse | 568.70 | — | — | 2711.04 (4.77x) | 1559.49 (2.74x) |
| Any EmptyBytesValue WKT JSON stringify | 176.72 | — | — | 915.35 (5.18x) | 780.17 (4.41x) |
| Any EmptyBytesValue WKT JSON parse | 533.97 | — | — | 2158.29 (4.04x) | 1474.55 (2.76x) |
| Nested Any WKT JSON stringify | 313.20 | — | — | 2490.48 (7.95x) | 1474.65 (4.71x) |
| Nested Any WKT JSON parse | 879.42 | — | — | 4301.18 (4.89x) | 2877.80 (3.27x) |
| Duration JSON stringify | 58.50 | — | — | 958.53 (16.39x) | 371.74 (6.35x) |
| Duration JSON parse | 19.06 | — | — | 1453.32 (76.25x) | 407.67 (21.39x) |
| Duration Escape JSON parse | 40.49 | — | — | 1483.54 (36.64x) | 444.46 (10.98x) |
| PlusDuration JSON parse | 20.18 | — | — | 1458.11 (72.26x) | 400.23 (19.83x) |
| ShortFractionDuration JSON parse | 16.30 | — | — | 1426.80 (87.53x) | 398.95 (24.48x) |
| MicroDuration JSON stringify | 59.38 | — | — | 972.10 (16.37x) | 418.60 (7.05x) |
| MicroDuration JSON parse | 21.57 | — | — | 1457.88 (67.59x) | 406.60 (18.85x) |
| NanoDuration JSON stringify | 57.16 | — | — | 998.23 (17.46x) | 419.73 (7.34x) |
| NanoDuration JSON parse | 23.32 | — | — | 1480.82 (63.50x) | 418.70 (17.95x) |
| NegativeDuration JSON stringify | 58.74 | — | — | 1007.89 (17.16x) | 432.60 (7.36x) |
| NegativeDuration JSON parse | 18.49 | — | — | 1508.29 (81.57x) | 403.55 (21.83x) |
| FractionalNegativeDuration JSON stringify | 58.79 | — | — | 976.02 (16.60x) | 419.67 (7.14x) |
| FractionalNegativeDuration JSON parse | 19.93 | — | — | 1453.54 (72.93x) | 394.60 (19.80x) |
| MaxDuration JSON stringify | 49.64 | — | — | 858.36 (17.29x) | 420.09 (8.46x) |
| MaxDuration JSON parse | 31.72 | — | — | 1435.71 (45.26x) | 413.82 (13.05x) |
| MinDuration JSON stringify | 49.89 | — | — | 871.50 (17.47x) | 449.38 (9.01x) |
| MinDuration JSON parse | 32.19 | — | — | 1443.54 (44.84x) | 409.60 (12.72x) |
| ZeroDuration JSON stringify | 44.91 | — | — | 814.13 (18.13x) | 361.96 (8.06x) |
| ZeroDuration JSON parse | 15.05 | — | — | 1359.63 (90.34x) | 342.32 (22.75x) |
| FieldMask JSON stringify | 96.91 | — | — | 891.69 (9.20x) | 648.31 (6.69x) |
| FieldMask JSON parse | 142.71 | — | — | 1679.97 (11.77x) | 895.54 (6.28x) |
| FieldMask Escape JSON parse | 191.70 | — | — | 1739.81 (9.08x) | 977.40 (5.10x) |
| EmptyFieldMask JSON stringify | 40.76 | — | — | 622.85 (15.28x) | 192.51 (4.72x) |
| EmptyFieldMask JSON parse | 4.78 | — | — | 947.11 (198.14x) | 171.05 (35.78x) |
| Timestamp JSON stringify | 95.59 | — | — | 1150.49 (12.04x) | 412.87 (4.32x) |
| Timestamp JSON parse | 45.06 | — | — | 1499.44 (33.28x) | 476.23 (10.57x) |
| Timestamp Escape JSON parse | 106.49 | — | — | 1522.84 (14.30x) | 526.42 (4.94x) |
| ShortFraction Timestamp JSON parse | 43.55 | — | — | 1481.19 (34.01x) | 461.62 (10.60x) |
| Micro Timestamp JSON stringify | 95.50 | — | — | 1152.20 (12.06x) | 417.29 (4.37x) |
| Micro Timestamp JSON parse | 47.14 | — | — | 1512.31 (32.08x) | 467.02 (9.91x) |
| Nano Timestamp JSON stringify | 93.43 | — | — | 1194.08 (12.78x) | 418.81 (4.48x) |
| Nano Timestamp JSON parse | 49.71 | — | — | 1521.11 (30.60x) | 478.97 (9.64x) |
| Offset Timestamp JSON parse | 51.24 | — | — | 1543.32 (30.12x) | 503.68 (9.83x) |
| PreEpoch Timestamp JSON stringify | 66.14 | — | — | 1116.78 (16.89x) | 390.32 (5.90x) |
| PreEpoch Timestamp JSON parse | 42.99 | — | — | 1476.86 (34.35x) | 443.25 (10.31x) |
| Max Timestamp JSON stringify | 78.37 | — | — | 1214.95 (15.50x) | 415.60 (5.30x) |
| Max Timestamp JSON parse | 51.05 | — | — | 1547.02 (30.30x) | 478.13 (9.37x) |
| Min Timestamp JSON stringify | 80.11 | — | — | 1054.80 (13.17x) | 383.68 (4.79x) |
| Min Timestamp JSON parse | 40.89 | — | — | 1456.54 (35.62x) | 440.67 (10.78x) |
| Empty JSON stringify | 20.82 | — | — | 495.42 (23.80x) | 84.65 (4.07x) |
| Empty JSON parse | 68.68 | — | — | 727.99 (10.60x) | 232.75 (3.39x) |
| Struct JSON stringify | 191.44 | — | — | 5887.08 (30.75x) | 3104.00 (16.21x) |
| Struct JSON parse | 852.67 | — | — | 10971.60 (12.87x) | 4729.48 (5.55x) |
| Struct Escape JSON parse | 905.92 | — | — | 10969.30 (12.11x) | 4869.98 (5.38x) |
| Struct NumberExponent JSON parse | 859.09 | — | — | 10948.20 (12.74x) | 4766.59 (5.55x) |
| Struct Surrogate JSON parse | 369.90 | — | — | 4835.67 (13.07x) | 1221.99 (3.30x) |
| Struct KeySurrogate JSON parse | 369.78 | — | — | 4773.10 (12.91x) | 1214.86 (3.29x) |
| EmptyStruct JSON stringify | 41.23 | — | — | 686.98 (16.66x) | 356.43 (8.64x) |
| EmptyStruct JSON parse | 86.61 | — | — | 2032.74 (23.47x) | 389.98 (4.50x) |
| Value JSON stringify | 177.42 | — | — | 6617.89 (37.30x) | 3281.05 (18.49x) |
| Value JSON parse | 875.21 | — | — | 12234.90 (13.98x) | 5004.50 (5.72x) |
| Value Escape JSON parse | 918.84 | — | — | 12391.80 (13.49x) | 5108.06 (5.56x) |
| Value NumberExponent JSON parse | 876.60 | — | — | 12332.10 (14.07x) | 4990.05 (5.69x) |
| Value Surrogate JSON parse | 397.70 | — | — | 6714.12 (16.88x) | 1489.40 (3.75x) |
| Value KeySurrogate JSON parse | 395.82 | — | — | 6691.23 (16.90x) | 1503.82 (3.80x) |
| NullValue JSON stringify | 40.35 | — | — | 1326.28 (32.87x) | 237.07 (5.88x) |
| NullValue JSON parse | 69.66 | — | — | 2473.44 (35.51x) | 365.08 (5.24x) |
| StringScalarValue JSON stringify | 47.63 | — | — | 1346.84 (28.28x) | 280.61 (5.89x) |
| StringScalarValue JSON parse | 140.81 | — | — | 2088.97 (14.84x) | 441.93 (3.14x) |
| StringScalarValue Escape JSON parse | 149.97 | — | — | 2135.40 (14.24x) | 507.78 (3.39x) |
| StringScalarValue Surrogate JSON parse | 148.85 | — | — | 2150.06 (14.44x) | 501.40 (3.37x) |
| EmptyStringScalarValue JSON stringify | 46.12 | — | — | 1337.44 (29.00x) | 282.74 (6.13x) |
| EmptyStringScalarValue JSON parse | 87.29 | — | — | 2060.76 (23.61x) | 377.73 (4.33x) |
| NumberValue JSON stringify | 76.86 | — | — | 1556.94 (20.26x) | 336.11 (4.37x) |
| NumberValue JSON parse | 132.33 | — | — | 2173.61 (16.43x) | 412.07 (3.11x) |
| NumberValue Exponent JSON parse | 135.15 | — | — | 2192.21 (16.22x) | 433.97 (3.21x) |
| NegativeNumberValue JSON stringify | 76.86 | — | — | 1549.80 (20.16x) | 334.97 (4.36x) |
| NegativeNumberValue JSON parse | 133.58 | — | — | 2167.75 (16.23x) | 426.35 (3.19x) |
| ZeroNumberValue JSON stringify | 51.36 | — | — | 1504.52 (29.29x) | 291.51 (5.68x) |
| ZeroNumberValue JSON parse | 129.40 | — | — | 2115.23 (16.35x) | 397.48 (3.07x) |
| BoolScalarValue JSON stringify | 40.65 | — | — | 1317.73 (32.42x) | 235.04 (5.78x) |
| BoolScalarValue JSON parse | 69.68 | — | — | 2013.35 (28.89x) | 344.36 (4.94x) |
| FalseBoolScalarValue JSON stringify | 40.51 | — | — | 1313.83 (32.43x) | 233.73 (5.77x) |
| FalseBoolScalarValue JSON parse | 70.19 | — | — | 2017.40 (28.74x) | 324.54 (4.62x) |
| ListKindValue JSON stringify | 143.85 | — | — | 6181.93 (42.97x) | 2328.49 (16.19x) |
| ListKindValue JSON parse | 681.94 | — | — | 10453.70 (15.33x) | 4111.82 (6.03x) |
| ListKindValue Escape JSON parse | 698.76 | — | — | 10536.00 (15.08x) | 4333.11 (6.20x) |
| ListKindValue Surrogate JSON parse | 330.75 | — | — | 4887.16 (14.78x) | 1206.30 (3.65x) |
| EmptyStructKindValue JSON stringify | 42.95 | — | — | 1944.73 (45.28x) | 547.25 (12.74x) |
| EmptyStructKindValue JSON parse | 110.27 | — | — | 3764.46 (34.14x) | 660.83 (5.99x) |
| EmptyListKindValue JSON stringify | 41.39 | — | — | 1934.95 (46.75x) | 373.31 (9.02x) |
| EmptyListKindValue JSON parse | 147.09 | — | — | 4044.94 (27.50x) | 590.78 (4.02x) |
| ListValue JSON stringify | 146.82 | — | — | 4785.94 (32.60x) | 2166.35 (14.76x) |
| ListValue JSON parse | 670.19 | — | — | 8585.70 (12.81x) | 3844.71 (5.74x) |
| ListValue Escape JSON parse | 692.11 | — | — | 8695.99 (12.56x) | 4041.46 (5.84x) |
| ListValue Surrogate JSON parse | 297.47 | — | — | 3099.95 (10.42x) | 939.20 (3.16x) |
| EmptyListValue JSON stringify | 40.21 | — | — | 690.23 (17.17x) | 185.63 (4.62x) |
| EmptyListValue JSON parse | 126.33 | — | — | 2262.51 (17.91x) | 341.69 (2.70x) |
| DoubleValue JSON stringify | 67.61 | — | — | 853.97 (12.63x) | 189.59 (2.80x) |
| DoubleValue JSON parse | 111.33 | — | — | 1231.14 (11.06x) | 301.88 (2.71x) |
| DoubleValue String JSON parse | 111.05 | — | — | 1168.07 (10.52x) | 377.01 (3.39x) |
| DoubleValue Exponent JSON parse | 113.26 | — | — | 1242.20 (10.97x) | 305.05 (2.69x) |
| NegativeDoubleValue JSON stringify | 68.64 | — | — | 867.03 (12.63x) | 199.23 (2.90x) |
| NegativeDoubleValue JSON parse | 111.65 | — | — | 1239.03 (11.10x) | 295.11 (2.64x) |
| ZeroDoubleValue JSON stringify | 47.48 | — | — | 801.16 (16.87x) | 140.41 (2.96x) |
| ZeroDoubleValue JSON parse | 108.47 | — | — | 1155.51 (10.65x) | 275.67 (2.54x) |
| DoubleValue NaN JSON stringify | 46.40 | — | — | 666.15 (14.36x) | 127.60 (2.75x) |
| DoubleValue NaN JSON parse | 105.17 | — | — | 1101.69 (10.48x) | 277.56 (2.64x) |
| DoubleValue Infinity JSON stringify | 47.89 | — | — | 669.86 (13.99x) | 123.98 (2.59x) |
| DoubleValue Infinity JSON parse | 105.88 | — | — | 1104.28 (10.43x) | 290.15 (2.74x) |
| DoubleValue NegativeInfinity JSON stringify | 48.12 | — | — | 658.83 (13.69x) | 126.94 (2.64x) |
| DoubleValue NegativeInfinity JSON parse | 107.51 | — | — | 1112.72 (10.35x) | 297.93 (2.77x) |
| FloatValue JSON stringify | 71.64 | — | — | 816.07 (11.39x) | 196.88 (2.75x) |
| FloatValue JSON parse | 110.39 | — | — | 1208.79 (10.95x) | 306.52 (2.78x) |
| FloatValue String JSON parse | 110.11 | — | — | 1154.49 (10.48x) | 376.66 (3.42x) |
| FloatValue Exponent JSON parse | 112.49 | — | — | 1222.71 (10.87x) | 306.64 (2.73x) |
| NegativeFloatValue JSON stringify | 86.10 | — | — | 809.40 (9.40x) | 195.41 (2.27x) |
| NegativeFloatValue JSON parse | 111.00 | — | — | 1220.92 (11.00x) | 314.91 (2.84x) |
| ZeroFloatValue JSON stringify | 47.26 | — | — | 758.11 (16.04x) | 149.79 (3.17x) |
| ZeroFloatValue JSON parse | 109.87 | — | — | 1154.35 (10.51x) | 275.47 (2.51x) |
| FloatValue NaN JSON stringify | 46.50 | — | — | 652.76 (14.04x) | 135.31 (2.91x) |
| FloatValue NaN JSON parse | 104.81 | — | — | 1081.82 (10.32x) | 283.38 (2.70x) |
| FloatValue Infinity JSON stringify | 47.89 | — | — | 657.23 (13.72x) | 132.80 (2.77x) |
| FloatValue Infinity JSON parse | 106.59 | — | — | 1097.77 (10.30x) | 284.47 (2.67x) |
| FloatValue NegativeInfinity JSON stringify | 48.20 | — | — | 649.44 (13.47x) | 134.52 (2.79x) |
| FloatValue NegativeInfinity JSON parse | 108.43 | — | — | 1100.75 (10.15x) | 283.25 (2.61x) |
| Int64Value JSON stringify | 50.42 | — | — | 690.89 (13.70x) | 293.46 (5.82x) |
| Int64Value JSON parse | 124.82 | — | — | 1239.65 (9.93x) | 488.41 (3.91x) |
| Int64Value Number JSON parse | 126.92 | — | — | 1290.99 (10.17x) | 357.82 (2.82x) |
| Int64Value Exponent JSON parse | 117.79 | — | — | 1229.35 (10.44x) | 367.76 (3.12x) |
| ZeroInt64Value JSON stringify | 41.20 | — | — | 625.72 (15.19x) | 207.91 (5.05x) |
| ZeroInt64Value JSON parse | 106.67 | — | — | 1099.96 (10.31x) | 353.81 (3.32x) |
| NegativeInt64Value JSON stringify | 50.31 | — | — | 696.68 (13.85x) | 294.13 (5.85x) |
| NegativeInt64Value JSON parse | 126.52 | — | — | 1235.49 (9.77x) | 497.86 (3.94x) |
| MinInt64Value JSON stringify | 49.40 | — | — | 694.13 (14.05x) | 295.18 (5.98x) |
| MinInt64Value JSON parse | 134.21 | — | — | 1255.66 (9.36x) | 506.53 (3.77x) |
| MaxInt64Value JSON stringify | 49.64 | — | — | 700.91 (14.12x) | 296.67 (5.98x) |
| MaxInt64Value JSON parse | 134.21 | — | — | 1260.05 (9.39x) | 500.99 (3.73x) |
| UInt64Value JSON stringify | 49.66 | — | — | 675.73 (13.61x) | 282.87 (5.70x) |
| UInt64Value JSON parse | 127.71 | — | — | 1228.94 (9.62x) | 476.02 (3.73x) |
| UInt64Value Number JSON parse | 127.60 | — | — | 1278.73 (10.02x) | 353.68 (2.77x) |
| UInt64Value Exponent JSON parse | 118.87 | — | — | 1232.51 (10.37x) | 370.41 (3.12x) |
| ZeroUInt64Value JSON stringify | 41.17 | — | — | 610.72 (14.83x) | 193.22 (4.69x) |
| ZeroUInt64Value JSON parse | 107.48 | — | — | 1091.61 (10.16x) | 353.02 (3.28x) |
| MaxUInt64Value JSON stringify | 49.10 | — | — | 679.32 (13.84x) | 304.12 (6.19x) |
| MaxUInt64Value JSON parse | 145.27 | — | — | 1252.97 (8.63x) | 496.19 (3.42x) |
| Int32Value JSON stringify | 46.69 | — | — | 644.57 (13.81x) | 136.89 (2.93x) |
| Int32Value JSON parse | 131.76 | — | — | 1182.61 (8.98x) | 325.03 (2.47x) |
| Int32Value String JSON parse | 135.17 | — | — | 1129.08 (8.35x) | 403.11 (2.98x) |
| Int32Value Exponent JSON parse | 136.51 | — | — | 1224.39 (8.97x) | 368.95 (2.70x) |
| ZeroInt32Value JSON stringify | 48.33 | — | — | 624.46 (12.92x) | 137.72 (2.85x) |
| ZeroInt32Value JSON parse | 128.64 | — | — | 1159.02 (9.01x) | 278.26 (2.16x) |
| NegativeInt32Value JSON stringify | 46.78 | — | — | 652.75 (13.95x) | 136.64 (2.92x) |
| NegativeInt32Value JSON parse | 131.06 | — | — | 1199.38 (9.15x) | 335.36 (2.56x) |
| MinInt32Value JSON stringify | 47.40 | — | — | 656.13 (13.84x) | 137.77 (2.91x) |
| MinInt32Value JSON parse | 136.65 | — | — | 1214.05 (8.88x) | 350.07 (2.56x) |
| MaxInt32Value JSON stringify | 47.29 | — | — | 649.09 (13.73x) | 142.03 (3.00x) |
| MaxInt32Value JSON parse | 136.90 | — | — | 1205.69 (8.81x) | 355.69 (2.60x) |
| UInt32Value JSON stringify | 46.78 | — | — | 647.39 (13.84x) | 143.69 (3.07x) |
| UInt32Value JSON parse | 132.22 | — | — | 1194.16 (9.03x) | 332.54 (2.52x) |
| UInt32Value String JSON parse | 135.60 | — | — | 1140.35 (8.41x) | 428.66 (3.16x) |
| UInt32Value Exponent JSON parse | 135.71 | — | — | 1246.64 (9.19x) | 370.30 (2.73x) |
| ZeroUInt32Value JSON stringify | 46.82 | — | — | 653.98 (13.97x) | 128.15 (2.74x) |
| ZeroUInt32Value JSON parse | 128.97 | — | — | 1181.33 (9.16x) | 265.19 (2.06x) |
| MaxUInt32Value JSON stringify | 46.95 | — | — | 651.26 (13.87x) | 140.60 (2.99x) |
| MaxUInt32Value JSON parse | 137.73 | — | — | 1218.04 (8.84x) | 335.06 (2.43x) |
| BoolValue JSON stringify | 45.13 | — | — | 619.50 (13.73x) | 124.51 (2.76x) |
| BoolValue JSON parse | 59.91 | — | — | 1057.06 (17.64x) | 223.65 (3.73x) |
| FalseBoolValue JSON stringify | 45.27 | — | — | 605.71 (13.38x) | 130.47 (2.88x) |
| FalseBoolValue JSON parse | 60.39 | — | — | 1060.74 (17.56x) | 227.34 (3.76x) |
| StringValue JSON stringify | 52.59 | — | — | 674.11 (12.82x) | 183.48 (3.49x) |
| StringValue JSON parse | 120.23 | — | — | 1149.68 (9.56x) | 334.88 (2.79x) |
| StringValue Escape JSON parse | 130.07 | — | — | 1174.91 (9.03x) | 382.25 (2.94x) |
| StringValue Surrogate JSON parse | 127.49 | — | — | 1171.44 (9.19x) | 382.34 (3.00x) |
| EmptyStringValue JSON stringify | 48.94 | — | — | 646.23 (13.20x) | 199.74 (4.08x) |
| EmptyStringValue JSON parse | 66.34 | — | — | 1115.05 (16.81x) | 242.15 (3.65x) |
| BytesValue JSON stringify | 49.45 | — | — | 670.37 (13.56x) | 215.08 (4.35x) |
| BytesValue JSON parse | 126.49 | — | — | 1178.85 (9.32x) | 368.94 (2.92x) |
| BytesValue URL JSON parse | 142.93 | — | — | 1160.37 (8.12x) | 356.93 (2.50x) |
| BytesValue StandardBase64 JSON parse | 124.87 | — | — | 1186.76 (9.50x) | 378.37 (3.03x) |
| BytesValue Unpadded JSON parse | 124.62 | — | — | 1164.18 (9.34x) | 355.71 (2.85x) |
| EmptyBytesValue JSON stringify | 40.83 | — | — | 647.09 (15.85x) | 202.09 (4.95x) |
| EmptyBytesValue JSON parse | 68.71 | — | — | 1128.90 (16.43x) | 308.25 (4.49x) |
| TextFormat format | 181.75 | — | — | 2596.05 (14.28x) | 2591.61 (14.26x) |
| TextFormat parse | 717.32 | — | — | 5004.44 (6.98x) | 6633.23 (9.25x) |
| packed fixed32 encode | 2.01 | 549.96 (273.61x) | 543.21 (270.25x) | 44.22 (22.00x) | 397.62 (197.82x) |
| packed fixed32 decode | 4.54 | 1065.64 (234.72x) | 2000.00 (440.53x) | 49.85 (10.98x) | 1579.18 (347.84x) |
| packed fixed64 encode | 2.00 | 578.72 (289.36x) | 565.19 (282.60x) | 75.72 (37.86x) | 400.16 (200.08x) |
| packed fixed64 decode | 4.54 | 1030.43 (226.97x) | 7959.78 (1753.26x) | 79.79 (17.57x) | 2237.41 (492.82x) |
| packed sfixed32 encode | 2.01 | 554.74 (275.99x) | 541.74 (269.52x) | 44.12 (21.95x) | 400.02 (199.01x) |
| packed sfixed32 decode | 4.52 | 1065.43 (235.71x) | 1998.97 (442.25x) | 49.34 (10.92x) | 1623.34 (359.15x) |
| packed sfixed64 encode | 2.01 | 575.58 (286.36x) | 565.19 (281.19x) | 75.70 (37.66x) | 397.35 (197.69x) |
| packed sfixed64 decode | 4.53 | 984.99 (217.44x) | 7936.76 (1752.04x) | 79.41 (17.53x) | 2228.78 (492.00x) |
| packed float encode | 2.01 | 816.40 (406.17x) | 542.82 (270.06x) | 43.70 (21.74x) | 361.37 (179.79x) |
| packed float decode | 4.51 | 1053.61 (233.62x) | 2073.61 (459.78x) | 48.96 (10.86x) | 1591.51 (352.88x) |
| packed double encode | 2.01 | 836.07 (415.96x) | 594.52 (295.78x) | 75.69 (37.66x) | 361.84 (180.02x) |
| packed double decode | 4.52 | 964.71 (213.43x) | 2041.54 (451.67x) | 79.29 (17.54x) | 2204.05 (487.62x) |
| packed uint64 encode | 1297.23 | 4641.99 (3.58x) | 4064.99 (3.13x) | 2165.83 (1.67x) | 3479.10 (2.68x) |
| packed uint64 decode | 1780.38 | 2794.63 (1.57x) | 8905.78 (5.00x) | 2811.33 (1.58x) | 6406.33 (3.60x) |
| packed uint32 encode | 926.27 | 3630.58 (3.92x) | 3276.69 (3.54x) | 1742.06 (1.88x) | 2908.77 (3.14x) |
| packed uint32 decode | 1294.26 | 2447.98 (1.89x) | 3281.63 (2.54x) | 1993.95 (1.54x) | 4799.25 (3.71x) |
| packed int64 encode | 1409.91 | 10996.77 (7.80x) | 6078.98 (4.31x) | 2907.16 (2.06x) | 4173.15 (2.96x) |
| packed int64 decode | 2750.05 | 3428.83 (1.25x) | 10304.24 (3.75x) | 4857.79 (1.77x) | 7790.65 (2.83x) |
| packed sint32 encode | 781.25 | 3055.13 (3.91x) | 2897.81 (3.71x) | 1528.04 (1.96x) | 3455.77 (4.42x) |
| packed sint32 decode | 951.51 | 2556.80 (2.69x) | 3258.35 (3.42x) | 1129.88 (1.19x) | 3045.80 (3.20x) |
| packed sint64 encode | 1448.70 | 4957.94 (3.42x) | 4324.01 (2.98x) | 2443.43 (1.69x) | 4182.72 (2.89x) |
| packed sint64 decode | 2047.06 | 3091.29 (1.51x) | 9735.85 (4.76x) | 2944.34 (1.44x) | 6618.47 (3.23x) |
| packed bool encode | 2.01 | 1314.51 (653.99x) | 522.48 (259.94x) | 15.98 (7.95x) | 2348.03 (1168.17x) |
| packed bool decode | 264.53 | 1528.49 (5.78x) | 2562.72 (9.69x) | 807.65 (3.05x) | 1597.13 (6.04x) |
| packed enum encode | 273.39 | 2716.37 (9.94x) | 1828.62 (6.69x) | 1083.81 (3.96x) | 2482.90 (9.08x) |
| packed enum decode | 154.04 | 1551.96 (10.08x) | 2824.36 (18.34x) | 703.87 (4.57x) | 2065.10 (13.41x) |
| large map encode | 4070.12 | 16520.99 (4.06x) | 9909.01 (2.43x) | 20980.40 (5.15x) | 205077.85 (50.39x) |
| shuffled large map deterministic binary encode | 28253.56 | — | — | 143049.00 (5.06x) | 435183.43 (15.40x) |
| large map decode | 24076.70 | 90900.43 (3.78x) | 90425.46 (3.76x) | 93036.30 (3.86x) | 280106.52 (11.63x) |
| LargeMap JSON stringify | 23406.59 | — | — | 106674.00 (4.56x) | 758194.16 (32.39x) |
| LargeMap JSON parse | 191453.88 | — | — | 758984.00 (3.96x) | 546220.38 (2.85x) |

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
