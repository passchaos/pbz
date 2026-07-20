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

Latest accepted comparison (`/tmp/pbz-compare-int64-uint64-exponent-json-final.log`,
summarized in `/tmp/pbz-summary-int64-uint64-exponent-json-final.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 18.21 | 104.88 (5.76x) | 52.13 (2.86x) | 105.57 (5.80x) | 870.88 (47.82x) |
| binary decode | 89.69 | 248.26 (2.77x) | 228.16 (2.54x) | 219.91 (2.45x) | 906.64 (10.11x) |
| unknown fields count by number | 3.57 | — | — | 161.60 (45.26x) | — |
| deterministic binary encode | 84.78 | — | — | 133.14 (1.57x) | 1140.09 (13.45x) |
| scalarmix encode | 17.32 | 113.42 (6.55x) | 48.39 (2.79x) | 29.06 (1.68x) | 215.23 (12.43x) |
| scalarmix decode | 59.31 | 132.16 (2.23x) | 185.33 (3.12x) | 82.38 (1.39x) | 310.85 (5.24x) |
| textbytes encode | 14.92 | 79.69 (5.34x) | 33.46 (2.24x) | 118.96 (7.97x) | 154.80 (10.38x) |
| textbytes decode | 62.46 | 380.59 (6.09x) | 238.13 (3.81x) | 165.89 (2.66x) | 678.72 (10.87x) |
| largebytes encode | 25.81 | 2704.05 (104.77x) | 2683.41 (103.97x) | 2671.31 (103.50x) | 2712.40 (105.09x) |
| largebytes decode | 88.97 | 5521.17 (62.06x) | 3082.45 (34.65x) | 2760.57 (31.03x) | 20718.21 (232.87x) |
| presencemix encode | 16.69 | 55.24 (3.31x) | 28.53 (1.71x) | 57.86 (3.47x) | 234.58 (14.06x) |
| presencemix decode | 56.71 | 132.77 (2.34x) | 108.45 (1.91x) | 161.54 (2.85x) | 497.08 (8.77x) |
| complex encode | 50.26 | 132.50 (2.64x) | 96.70 (1.92x) | 166.96 (3.32x) | 918.63 (18.28x) |
| complex decode | 171.26 | 387.87 (2.26x) | 338.64 (1.98x) | 392.02 (2.29x) | 1362.59 (7.96x) |
| complex deterministic binary encode | 89.49 | — | — | 176.28 (1.97x) | 1258.28 (14.06x) |
| complex JSON stringify | 249.58 | — | — | 4916.73 (19.70x) | 6471.84 (25.93x) |
| complex JSON parse | 2453.89 | — | — | 11911.60 (4.85x) | 7514.05 (3.06x) |
| complex TextFormat format | 255.23 | — | — | 3770.45 (14.77x) | 5780.33 (22.65x) |
| complex TextFormat parse | 1836.36 | — | — | 6907.74 (3.76x) | 8459.58 (4.61x) |
| packed int32 encode | 657.08 | 3155.79 (4.80x) | 2517.65 (3.83x) | 1237.47 (1.88x) | 2741.14 (4.17x) |
| packed int32 decode | 676.72 | 1908.59 (2.82x) | 3226.61 (4.77x) | 938.89 (1.39x) | 2574.27 (3.80x) |
| JSON stringify | 154.01 | — | — | 3009.18 (19.54x) | 2361.40 (15.33x) |
| JSON parse | 1530.11 | — | — | 7506.72 (4.91x) | 4576.89 (2.99x) |
| Any WKT JSON stringify | 130.53 | — | — | 1871.72 (14.34x) | 990.76 (7.59x) |
| Any WKT JSON parse | 517.86 | — | — | 2961.50 (5.72x) | 1524.09 (2.94x) |
| Any Duration Escape WKT JSON parse | 533.31 | — | — | 2994.76 (5.62x) | 1623.63 (3.04x) |
| Any PlusDuration WKT JSON parse | 519.39 | — | — | 2996.09 (5.77x) | 1532.79 (2.95x) |
| Any ShortFractionDuration WKT JSON parse | 516.26 | — | — | 2942.06 (5.70x) | 1505.12 (2.92x) |
| Any MicroDuration WKT JSON stringify | 132.61 | — | — | 1888.40 (14.24x) | 988.81 (7.46x) |
| Any MicroDuration WKT JSON parse | 521.20 | — | — | 2975.98 (5.71x) | 1533.21 (2.94x) |
| Any NanoDuration WKT JSON stringify | 129.41 | — | — | 1914.53 (14.79x) | 991.55 (7.66x) |
| Any NanoDuration WKT JSON parse | 526.06 | — | — | 2997.50 (5.70x) | 1551.36 (2.95x) |
| Any NegativeDuration WKT JSON stringify | 130.60 | — | — | 1931.75 (14.79x) | 1016.83 (7.79x) |
| Any NegativeDuration WKT JSON parse | 521.41 | — | — | 3097.29 (5.94x) | 1567.41 (3.01x) |
| Any FractionalNegativeDuration WKT JSON stringify | 123.18 | — | — | 1888.42 (15.33x) | 988.12 (8.02x) |
| Any FractionalNegativeDuration WKT JSON parse | 509.34 | — | — | 3050.96 (5.99x) | 1534.44 (3.01x) |
| Any MaxDuration WKT JSON stringify | 117.79 | — | — | 1743.35 (14.80x) | 983.27 (8.35x) |
| Any MaxDuration WKT JSON parse | 526.59 | — | — | 2955.36 (5.61x) | 1552.77 (2.95x) |
| Any MinDuration WKT JSON stringify | 119.40 | — | — | 1758.07 (14.72x) | 1010.75 (8.47x) |
| Any MinDuration WKT JSON parse | 528.80 | — | — | 3064.67 (5.80x) | 1534.24 (2.90x) |
| Any ZeroDuration WKT JSON stringify | 104.07 | — | — | 923.69 (8.88x) | 964.56 (9.27x) |
| Any ZeroDuration WKT JSON parse | 459.33 | — | — | 2242.97 (4.88x) | 1458.75 (3.18x) |
| Any FieldMask WKT JSON stringify | 253.11 | — | — | 1743.72 (6.89x) | 1408.76 (5.57x) |
| Any FieldMask WKT JSON parse | 706.90 | — | — | 3158.41 (4.47x) | 2065.92 (2.92x) |
| Any FieldMask Escape WKT JSON parse | 726.95 | — | — | 3237.20 (4.45x) | 2242.61 (3.08x) |
| Any EmptyFieldMask WKT JSON stringify | 108.33 | — | — | 918.73 (8.48x) | 782.19 (7.22x) |
| Any EmptyFieldMask WKT JSON parse | 432.85 | — | — | 2159.01 (4.99x) | 1295.49 (2.99x) |
| Any Timestamp WKT JSON stringify | 173.33 | — | — | 2023.76 (11.68x) | 1003.68 (5.79x) |
| Any Timestamp WKT JSON parse | 564.12 | — | — | 3029.28 (5.37x) | 1611.47 (2.86x) |
| Any Timestamp Escape WKT JSON parse | 579.99 | — | — | 3067.81 (5.29x) | 1715.86 (2.96x) |
| Any ShortFraction Timestamp WKT JSON parse | 558.45 | — | — | 3006.92 (5.38x) | 1605.77 (2.88x) |
| Any Micro Timestamp WKT JSON stringify | 173.11 | — | — | 2024.48 (11.69x) | 1004.93 (5.81x) |
| Any Micro Timestamp WKT JSON parse | 579.29 | — | — | 3033.18 (5.24x) | 1636.51 (2.83x) |
| Any Nano Timestamp WKT JSON stringify | 171.60 | — | — | 2030.29 (11.83x) | 1016.73 (5.93x) |
| Any Nano Timestamp WKT JSON parse | 581.95 | — | — | 3035.68 (5.22x) | 1633.43 (2.81x) |
| Any Offset Timestamp WKT JSON parse | 591.50 | — | — | 3051.97 (5.16x) | 1646.64 (2.78x) |
| Any PreEpoch Timestamp WKT JSON stringify | 141.33 | — | — | 1943.23 (13.75x) | 974.46 (6.89x) |
| Any PreEpoch Timestamp WKT JSON parse | 555.21 | — | — | 3044.07 (5.48x) | 1587.96 (2.86x) |
| Any Max Timestamp WKT JSON stringify | 156.34 | — | — | 2043.23 (13.07x) | 1018.74 (6.52x) |
| Any Max Timestamp WKT JSON parse | 585.58 | — | — | 3084.77 (5.27x) | 1639.04 (2.80x) |
| Any Min Timestamp WKT JSON stringify | 152.58 | — | — | 1936.20 (12.69x) | 978.79 (6.41x) |
| Any Min Timestamp WKT JSON parse | 551.64 | — | — | 3027.27 (5.49x) | 1580.64 (2.87x) |
| Any Empty WKT JSON stringify | 91.77 | — | — | 918.65 (10.01x) | 674.72 (7.35x) |
| Any Empty WKT JSON parse | 336.08 | — | — | 2133.66 (6.35x) | 1358.70 (4.04x) |
| Any Struct WKT JSON stringify | 628.95 | — | — | 5861.45 (9.32x) | 6036.06 (9.60x) |
| Any Struct WKT JSON parse | 1740.87 | — | — | 11147.90 (6.40x) | 8753.31 (5.03x) |
| Any Struct Escape WKT JSON parse | 1767.80 | — | — | 11281.40 (6.38x) | 8851.29 (5.01x) |
| Any Struct NumberExponent WKT JSON parse | 1739.05 | — | — | 11181.30 (6.43x) | 8733.63 (5.02x) |
| Any EmptyStruct WKT JSON stringify | 117.55 | — | — | 911.13 (7.75x) | 951.57 (8.10x) |
| Any EmptyStruct WKT JSON parse | 431.75 | — | — | 2213.09 (5.13x) | 1565.05 (3.62x) |
| Any Value WKT JSON stringify | 653.62 | — | — | 5902.98 (9.03x) | 6447.58 (9.86x) |
| Any Value WKT JSON parse | 1796.93 | — | — | 11298.90 (6.29x) | 9125.94 (5.08x) |
| Any Value Escape WKT JSON parse | 1826.74 | — | — | 11481.20 (6.29x) | 9225.31 (5.05x) |
| Any Value NumberExponent WKT JSON parse | 1797.08 | — | — | 11407.90 (6.35x) | 9138.37 (5.09x) |
| Any NullValue WKT JSON stringify | 126.70 | — | — | 2263.14 (17.86x) | 914.62 (7.22x) |
| Any NullValue WKT JSON parse | 460.39 | — | — | 4065.78 (8.83x) | 1587.49 (3.45x) |
| Any StringScalarValue WKT JSON stringify | 151.60 | — | — | 2278.76 (15.03x) | 1003.02 (6.62x) |
| Any StringScalarValue WKT JSON parse | 518.90 | — | — | 3636.65 (7.01x) | 1689.16 (3.26x) |
| Any StringScalarValue Escape WKT JSON parse | 531.23 | — | — | 3681.99 (6.93x) | 1754.34 (3.30x) |
| Any EmptyStringScalarValue WKT JSON stringify | 138.39 | — | — | 2287.54 (16.53x) | 992.74 (7.17x) |
| Any EmptyStringScalarValue WKT JSON parse | 487.44 | — | — | 3646.10 (7.48x) | 1595.75 (3.27x) |
| Any NumberValue WKT JSON stringify | 172.74 | — | — | 2517.70 (14.58x) | 1034.15 (5.99x) |
| Any NumberValue WKT JSON parse | 506.01 | — | — | 3698.26 (7.31x) | 1628.68 (3.22x) |
| Any NumberValue Exponent WKT JSON parse | 507.68 | — | — | 3733.89 (7.35x) | 1616.12 (3.18x) |
| Any NegativeNumberValue WKT JSON stringify | 171.90 | — | — | 2510.23 (14.60x) | 1037.88 (6.04x) |
| Any NegativeNumberValue WKT JSON parse | 504.95 | — | — | 3696.09 (7.32x) | 1620.22 (3.21x) |
| Any ZeroNumberValue WKT JSON stringify | 135.37 | — | — | 2685.18 (19.84x) | 930.02 (6.87x) |
| Any ZeroNumberValue WKT JSON parse | 500.29 | — | — | 3628.98 (7.25x) | 1639.74 (3.28x) |
| Any BoolScalarValue WKT JSON stringify | 127.82 | — | — | 2296.62 (17.97x) | 906.62 (7.09x) |
| Any BoolScalarValue WKT JSON parse | 460.07 | — | — | 3624.15 (7.88x) | 1564.44 (3.40x) |
| Any FalseBoolScalarValue WKT JSON stringify | 130.42 | — | — | 2258.36 (17.32x) | 914.16 (7.01x) |
| Any FalseBoolScalarValue WKT JSON parse | 459.86 | — | — | 3599.95 (7.83x) | 1575.72 (3.43x) |
| Any ListKindValue WKT JSON stringify | 495.21 | — | — | 5567.79 (11.24x) | 4743.57 (9.58x) |
| Any ListKindValue WKT JSON parse | 1374.63 | — | — | 9970.91 (7.25x) | 7180.81 (5.22x) |
| Any ListKindValue Escape WKT JSON parse | 1404.28 | — | — | 10076.60 (7.18x) | 7306.39 (5.20x) |
| Any EmptyStructKindValue WKT JSON stringify | 144.19 | — | — | 2919.48 (20.25x) | 1335.65 (9.26x) |
| Any EmptyStructKindValue WKT JSON parse | 504.38 | — | — | 5390.23 (10.69x) | 2009.12 (3.98x) |
| Any EmptyListKindValue WKT JSON stringify | 141.52 | — | — | 2889.34 (20.42x) | 1153.08 (8.15x) |
| Any EmptyListKindValue WKT JSON parse | 506.54 | — | — | 4390.31 (8.67x) | 1868.67 (3.69x) |
| Any DoubleValue WKT JSON stringify | 181.11 | — | — | 1797.65 (9.93x) | 799.87 (4.42x) |
| Any DoubleValue WKT JSON parse | 517.44 | — | — | 2729.58 (5.28x) | 1459.07 (2.82x) |
| Any DoubleValue String WKT JSON parse | 527.43 | — | — | 2736.36 (5.19x) | 1516.47 (2.88x) |
| Any DoubleValue Exponent WKT JSON parse | 519.56 | — | — | 2745.46 (5.28x) | 1448.38 (2.79x) |
| Any NegativeDoubleValue WKT JSON stringify | 184.51 | — | — | 1803.42 (9.77x) | 805.52 (4.37x) |
| Any NegativeDoubleValue WKT JSON parse | 516.50 | — | — | 2732.46 (5.29x) | 1426.52 (2.76x) |
| Any ZeroDoubleValue WKT JSON stringify | 156.21 | — | — | 917.65 (5.87x) | 735.35 (4.71x) |
| Any ZeroDoubleValue WKT JSON parse | 510.94 | — | — | 2170.91 (4.25x) | 1380.27 (2.70x) |
| Any DoubleValue NaN WKT JSON stringify | 148.63 | — | — | 1569.78 (10.56x) | 721.26 (4.85x) |
| Any DoubleValue NaN WKT JSON parse | 506.02 | — | — | 2648.79 (5.23x) | 1401.83 (2.77x) |
| Any DoubleValue Infinity WKT JSON stringify | 150.95 | — | — | 1569.50 (10.40x) | 775.30 (5.14x) |
| Any DoubleValue Infinity WKT JSON parse | 512.58 | — | — | 2695.96 (5.26x) | 1428.49 (2.79x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 153.74 | — | — | 1561.63 (10.16x) | 723.97 (4.71x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 514.09 | — | — | 2671.76 (5.20x) | 1461.78 (2.84x) |
| Any FloatValue WKT JSON stringify | 188.32 | — | — | 1812.72 (9.63x) | 802.15 (4.26x) |
| Any FloatValue WKT JSON parse | 515.63 | — | — | 2847.51 (5.52x) | 1422.59 (2.76x) |
| Any FloatValue String WKT JSON parse | 527.11 | — | — | 2704.99 (5.13x) | 1519.68 (2.88x) |
| Any FloatValue Exponent WKT JSON parse | 522.90 | — | — | 2713.57 (5.19x) | 1439.29 (2.75x) |
| Any NegativeFloatValue WKT JSON stringify | 184.44 | — | — | 1732.66 (9.39x) | 779.61 (4.23x) |
| Any NegativeFloatValue WKT JSON parse | 517.65 | — | — | 2700.49 (5.22x) | 1427.65 (2.76x) |
| Any ZeroFloatValue WKT JSON stringify | 155.72 | — | — | 915.20 (5.88x) | 728.47 (4.68x) |
| Any ZeroFloatValue WKT JSON parse | 511.38 | — | — | 2141.31 (4.19x) | 1376.69 (2.69x) |
| Any FloatValue NaN WKT JSON stringify | 161.65 | — | — | 1562.83 (9.67x) | 713.28 (4.41x) |
| Any FloatValue NaN WKT JSON parse | 508.11 | — | — | 2613.88 (5.14x) | 1424.17 (2.80x) |
| Any FloatValue Infinity WKT JSON stringify | 156.38 | — | — | 1547.47 (9.90x) | 726.52 (4.65x) |
| Any FloatValue Infinity WKT JSON parse | 515.25 | — | — | 2655.77 (5.15x) | 1421.96 (2.76x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 158.42 | — | — | 1537.51 (9.71x) | 727.24 (4.59x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 515.74 | — | — | 2645.10 (5.13x) | 1420.93 (2.76x) |
| Any Int64Value WKT JSON stringify | 169.94 | — | — | 1549.64 (9.12x) | 859.99 (5.06x) |
| Any Int64Value WKT JSON parse | 547.48 | — | — | 2770.10 (5.06x) | 1643.96 (3.00x) |
| Any Int64Value Number WKT JSON parse | 547.59 | — | — | 2743.45 (5.01x) | 1534.15 (2.80x) |
| Any Int64Value Exponent WKT JSON parse | 532.13 | — | — | 2710.32 (5.09x) | 1488.85 (2.80x) |
| Any ZeroInt64Value WKT JSON stringify | 155.62 | — | — | 913.41 (5.87x) | 783.72 (5.04x) |
| Any ZeroInt64Value WKT JSON parse | 522.67 | — | — | 2139.20 (4.09x) | 1483.03 (2.84x) |
| Any NegativeInt64Value WKT JSON stringify | 170.27 | — | — | 1554.27 (9.13x) | 854.26 (5.02x) |
| Any NegativeInt64Value WKT JSON parse | 561.10 | — | — | 2799.58 (4.99x) | 1664.14 (2.97x) |
| Any MinInt64Value WKT JSON stringify | 168.06 | — | — | 1565.52 (9.32x) | 868.26 (5.17x) |
| Any MinInt64Value WKT JSON parse | 569.32 | — | — | 2823.18 (4.96x) | 1705.92 (3.00x) |
| Any MaxInt64Value WKT JSON stringify | 168.65 | — | — | 1581.08 (9.37x) | 864.38 (5.13x) |
| Any MaxInt64Value WKT JSON parse | 554.61 | — | — | 2819.51 (5.08x) | 1687.21 (3.04x) |
| Any UInt64Value WKT JSON stringify | 174.03 | — | — | 1567.03 (9.00x) | 861.81 (4.95x) |
| Any UInt64Value WKT JSON parse | 550.85 | — | — | 2797.46 (5.08x) | 1664.02 (3.02x) |
| Any UInt64Value Number WKT JSON parse | 547.00 | — | — | 2767.86 (5.06x) | 1527.21 (2.79x) |
| Any UInt64Value Exponent WKT JSON parse | 533.98 | — | — | 2715.22 (5.08x) | 1486.68 (2.78x) |
| Any ZeroUInt64Value WKT JSON stringify | 164.23 | — | — | 917.30 (5.59x) | 781.39 (4.76x) |
| Any ZeroUInt64Value WKT JSON parse | 520.77 | — | — | 2153.85 (4.14x) | 1502.07 (2.88x) |
| Any MaxUInt64Value WKT JSON stringify | 169.71 | — | — | 1576.95 (9.29x) | 867.00 (5.11x) |
| Any MaxUInt64Value WKT JSON parse | 559.48 | — | — | 2837.65 (5.07x) | 1716.13 (3.07x) |
| Any Int32Value WKT JSON stringify | 170.88 | — | — | 1577.57 (9.23x) | 736.05 (4.31x) |
| Any Int32Value WKT JSON parse | 531.14 | — | — | 2673.58 (5.03x) | 1460.37 (2.75x) |
| Any Int32Value String WKT JSON parse | 535.67 | — | — | 2703.43 (5.05x) | 1532.72 (2.86x) |
| Any Int32Value Exponent WKT JSON parse | 542.32 | — | — | 2715.04 (5.01x) | 1509.77 (2.78x) |
| Any ZeroInt32Value WKT JSON stringify | 163.54 | — | — | 924.68 (5.65x) | 709.14 (4.34x) |
| Any ZeroInt32Value WKT JSON parse | 525.13 | — | — | 2154.49 (4.10x) | 1451.77 (2.76x) |
| Any NegativeInt32Value WKT JSON stringify | 169.71 | — | — | 1560.56 (9.20x) | 732.20 (4.31x) |
| Any NegativeInt32Value WKT JSON parse | 531.68 | — | — | 2708.55 (5.09x) | 1481.29 (2.79x) |
| Any MinInt32Value WKT JSON stringify | 174.04 | — | — | 1555.83 (8.94x) | 743.28 (4.27x) |
| Any MinInt32Value WKT JSON parse | 536.50 | — | — | 2691.77 (5.02x) | 1501.51 (2.80x) |
| Any MaxInt32Value WKT JSON stringify | 172.99 | — | — | 1548.85 (8.95x) | 734.17 (4.24x) |
| Any MaxInt32Value WKT JSON parse | 537.75 | — | — | 2675.35 (4.98x) | 1467.04 (2.73x) |
| Any UInt32Value WKT JSON stringify | 173.56 | — | — | 1553.59 (8.95x) | 746.69 (4.30x) |
| Any UInt32Value WKT JSON parse | 541.38 | — | — | 2665.84 (4.92x) | 1463.73 (2.70x) |
| Any UInt32Value String WKT JSON parse | 546.87 | — | — | 2673.79 (4.89x) | 1553.03 (2.84x) |
| Any UInt32Value Exponent WKT JSON parse | 544.95 | — | — | 2704.21 (4.96x) | 1512.88 (2.78x) |
| Any ZeroUInt32Value WKT JSON stringify | 172.69 | — | — | 918.61 (5.32x) | 724.44 (4.20x) |
| Any ZeroUInt32Value WKT JSON parse | 529.96 | — | — | 2147.27 (4.05x) | 1415.61 (2.67x) |
| Any MaxUInt32Value WKT JSON stringify | 178.44 | — | — | 1564.15 (8.77x) | 743.07 (4.16x) |
| Any MaxUInt32Value WKT JSON parse | 553.16 | — | — | 2693.28 (4.87x) | 1496.53 (2.71x) |
| Any BoolValue WKT JSON stringify | 267.87 | — | — | 1531.02 (5.72x) | 730.76 (2.73x) |
| Any BoolValue WKT JSON parse | 774.89 | — | — | 2604.44 (3.36x) | 1328.79 (1.71x) |
| Any FalseBoolValue WKT JSON stringify | 265.18 | — | — | 928.31 (3.50x) | 712.36 (2.69x) |
| Any FalseBoolValue WKT JSON parse | 763.32 | — | — | 2156.18 (2.82x) | 1360.96 (1.78x) |
| Any StringValue WKT JSON stringify | 304.84 | — | — | 1553.49 (5.10x) | 810.92 (2.66x) |
| Any StringValue WKT JSON parse | 883.36 | — | — | 2637.74 (2.99x) | 1461.26 (1.65x) |
| Any StringValue Escape WKT JSON parse | 900.38 | — | — | 2692.95 (2.99x) | 1536.42 (1.71x) |
| Any EmptyStringValue WKT JSON stringify | 286.49 | — | — | 927.05 (3.24x) | 775.11 (2.71x) |
| Any EmptyStringValue WKT JSON parse | 838.93 | — | — | 2170.98 (2.59x) | 1367.46 (1.63x) |
| Any BytesValue WKT JSON stringify | 286.87 | — | — | 1570.11 (5.47x) | 970.25 (3.38x) |
| Any BytesValue WKT JSON parse | 753.03 | — | — | 2672.89 (3.55x) | 1470.03 (1.95x) |
| Any BytesValue URL WKT JSON parse | 833.12 | — | — | 2688.95 (3.23x) | 1495.26 (1.79x) |
| Any EmptyBytesValue WKT JSON stringify | 175.52 | — | — | 923.85 (5.26x) | 776.23 (4.42x) |
| Any EmptyBytesValue WKT JSON parse | 523.82 | — | — | 2157.09 (4.12x) | 1442.81 (2.75x) |
| Nested Any WKT JSON stringify | 291.72 | — | — | 2468.05 (8.46x) | 1442.69 (4.95x) |
| Nested Any WKT JSON parse | 852.79 | — | — | 4266.64 (5.00x) | 2860.36 (3.35x) |
| Duration JSON stringify | 57.97 | — | — | 958.50 (16.53x) | 368.94 (6.36x) |
| Duration JSON parse | 20.30 | — | — | 1448.68 (71.36x) | 397.27 (19.57x) |
| Duration Escape JSON parse | 40.69 | — | — | 1481.69 (36.41x) | 440.57 (10.83x) |
| PlusDuration JSON parse | 20.69 | — | — | 1457.14 (70.43x) | 400.12 (19.34x) |
| ShortFractionDuration JSON parse | 15.07 | — | — | 1427.77 (94.74x) | 386.06 (25.62x) |
| MicroDuration JSON stringify | 59.44 | — | — | 964.70 (16.23x) | 403.10 (6.78x) |
| MicroDuration JSON parse | 20.42 | — | — | 1468.93 (71.94x) | 397.01 (19.44x) |
| NanoDuration JSON stringify | 57.24 | — | — | 999.82 (17.47x) | 415.86 (7.27x) |
| NanoDuration JSON parse | 23.84 | — | — | 1477.97 (62.00x) | 405.61 (17.01x) |
| NegativeDuration JSON stringify | 59.26 | — | — | 1002.61 (16.92x) | 416.05 (7.02x) |
| NegativeDuration JSON parse | 18.69 | — | — | 1508.85 (80.73x) | 400.67 (21.44x) |
| FractionalNegativeDuration JSON stringify | 59.01 | — | — | 966.10 (16.37x) | 428.81 (7.27x) |
| FractionalNegativeDuration JSON parse | 19.34 | — | — | 1482.32 (76.65x) | 379.46 (19.62x) |
| MaxDuration JSON stringify | 49.68 | — | — | 862.61 (17.36x) | 415.19 (8.36x) |
| MaxDuration JSON parse | 34.32 | — | — | 1442.46 (42.03x) | 405.74 (11.82x) |
| MinDuration JSON stringify | 49.99 | — | — | 868.60 (17.38x) | 441.66 (8.83x) |
| MinDuration JSON parse | 32.98 | — | — | 1466.82 (44.48x) | 399.61 (12.12x) |
| ZeroDuration JSON stringify | 44.92 | — | — | 817.19 (18.19x) | 354.40 (7.89x) |
| ZeroDuration JSON parse | 14.80 | — | — | 1373.56 (92.81x) | 316.10 (21.36x) |
| FieldMask JSON stringify | 66.91 | — | — | 897.41 (13.41x) | 649.16 (9.70x) |
| FieldMask JSON parse | 139.48 | — | — | 1647.02 (11.81x) | 895.56 (6.42x) |
| FieldMask Escape JSON parse | 194.04 | — | — | 1710.20 (8.81x) | 966.23 (4.98x) |
| EmptyFieldMask JSON stringify | 40.71 | — | — | 607.19 (14.91x) | 196.79 (4.83x) |
| EmptyFieldMask JSON parse | 4.78 | — | — | 940.59 (196.78x) | 169.92 (35.55x) |
| Timestamp JSON stringify | 95.35 | — | — | 1147.54 (12.04x) | 413.30 (4.33x) |
| Timestamp JSON parse | 46.41 | — | — | 1491.11 (32.13x) | 448.24 (9.66x) |
| Timestamp Escape JSON parse | 93.00 | — | — | 1526.43 (16.41x) | 509.44 (5.48x) |
| ShortFraction Timestamp JSON parse | 43.60 | — | — | 1483.81 (34.03x) | 443.13 (10.16x) |
| Micro Timestamp JSON stringify | 96.25 | — | — | 1146.92 (11.92x) | 639.65 (6.65x) |
| Micro Timestamp JSON parse | 47.59 | — | — | 1504.19 (31.61x) | 462.65 (9.72x) |
| Nano Timestamp JSON stringify | 94.63 | — | — | 1185.15 (12.52x) | 422.15 (4.46x) |
| Nano Timestamp JSON parse | 49.97 | — | — | 1521.45 (30.45x) | 469.56 (9.40x) |
| Offset Timestamp JSON parse | 51.47 | — | — | 1530.40 (29.73x) | 484.36 (9.41x) |
| PreEpoch Timestamp JSON stringify | 66.23 | — | — | 1069.26 (16.14x) | 399.58 (6.03x) |
| PreEpoch Timestamp JSON parse | 42.92 | — | — | 1468.71 (34.22x) | 429.70 (10.01x) |
| Max Timestamp JSON stringify | 78.42 | — | — | 1201.64 (15.32x) | 424.12 (5.41x) |
| Max Timestamp JSON parse | 50.90 | — | — | 1538.60 (30.23x) | 466.84 (9.17x) |
| Min Timestamp JSON stringify | 79.48 | — | — | 1062.71 (13.37x) | 402.14 (5.06x) |
| Min Timestamp JSON parse | 40.96 | — | — | 1454.79 (35.52x) | 427.84 (10.45x) |
| Empty JSON stringify | 20.88 | — | — | 496.53 (23.78x) | 85.48 (4.09x) |
| Empty JSON parse | 68.73 | — | — | 720.41 (10.48x) | 203.85 (2.97x) |
| Struct JSON stringify | 172.13 | — | — | 5756.67 (33.44x) | 3050.04 (17.72x) |
| Struct JSON parse | 838.65 | — | — | 10938.80 (13.04x) | 4675.98 (5.58x) |
| Struct Escape JSON parse | 890.22 | — | — | 10937.30 (12.29x) | 4782.76 (5.37x) |
| Struct NumberExponent JSON parse | 838.24 | — | — | 10872.40 (12.97x) | 4679.56 (5.58x) |
| EmptyStruct JSON stringify | 41.11 | — | — | 698.45 (16.99x) | 352.50 (8.57x) |
| EmptyStruct JSON parse | 86.47 | — | — | 2020.49 (23.37x) | 387.64 (4.48x) |
| Value JSON stringify | 172.92 | — | — | 6614.36 (38.25x) | 3220.72 (18.63x) |
| Value JSON parse | 863.06 | — | — | 12180.10 (14.11x) | 4910.73 (5.69x) |
| Value Escape JSON parse | 908.75 | — | — | 12825.90 (14.11x) | 5086.38 (5.60x) |
| Value NumberExponent JSON parse | 861.21 | — | — | 12212.90 (14.18x) | 4916.14 (5.71x) |
| NullValue JSON stringify | 40.50 | — | — | 1324.14 (32.69x) | 222.41 (5.49x) |
| NullValue JSON parse | 69.79 | — | — | 2449.55 (35.10x) | 357.20 (5.12x) |
| StringScalarValue JSON stringify | 47.63 | — | — | 1353.01 (28.41x) | 277.51 (5.83x) |
| StringScalarValue JSON parse | 140.13 | — | — | 2089.25 (14.91x) | 442.99 (3.16x) |
| StringScalarValue Escape JSON parse | 150.77 | — | — | 2125.62 (14.10x) | 492.71 (3.27x) |
| EmptyStringScalarValue JSON stringify | 45.90 | — | — | 1344.06 (29.28x) | 269.63 (5.87x) |
| EmptyStringScalarValue JSON parse | 87.22 | — | — | 2068.77 (23.72x) | 367.14 (4.21x) |
| NumberValue JSON stringify | 74.37 | — | — | 1562.31 (21.01x) | 329.69 (4.43x) |
| NumberValue JSON parse | 131.71 | — | — | 2172.01 (16.49x) | 412.69 (3.13x) |
| NumberValue Exponent JSON parse | 133.96 | — | — | 2185.88 (16.32x) | 414.62 (3.10x) |
| NegativeNumberValue JSON stringify | 73.10 | — | — | 1565.87 (21.42x) | 329.14 (4.50x) |
| NegativeNumberValue JSON parse | 132.37 | — | — | 2170.02 (16.39x) | 418.45 (3.16x) |
| ZeroNumberValue JSON stringify | 50.85 | — | — | 1516.12 (29.82x) | 277.11 (5.45x) |
| ZeroNumberValue JSON parse | 129.05 | — | — | 2107.62 (16.33x) | 380.44 (2.95x) |
| BoolScalarValue JSON stringify | 40.62 | — | — | 1321.42 (32.53x) | 223.98 (5.51x) |
| BoolScalarValue JSON parse | 69.81 | — | — | 2014.20 (28.85x) | 336.17 (4.82x) |
| FalseBoolScalarValue JSON stringify | 40.68 | — | — | 1319.34 (32.43x) | 215.69 (5.30x) |
| FalseBoolScalarValue JSON parse | 70.17 | — | — | 2025.65 (28.87x) | 341.30 (4.86x) |
| ListKindValue JSON stringify | 141.84 | — | — | 6151.76 (43.37x) | 2262.72 (15.95x) |
| ListKindValue JSON parse | 668.06 | — | — | 10417.40 (15.59x) | 4064.35 (6.08x) |
| ListKindValue Escape JSON parse | 688.04 | — | — | 10522.20 (15.29x) | 4270.78 (6.21x) |
| EmptyStructKindValue JSON stringify | 42.96 | — | — | 1948.02 (45.34x) | 526.37 (12.25x) |
| EmptyStructKindValue JSON parse | 112.85 | — | — | 3772.66 (33.43x) | 661.16 (5.86x) |
| EmptyListKindValue JSON stringify | 41.37 | — | — | 1948.89 (47.11x) | 364.86 (8.82x) |
| EmptyListKindValue JSON parse | 148.73 | — | — | 4045.92 (27.20x) | 596.00 (4.01x) |
| ListValue JSON stringify | 137.36 | — | — | 4741.71 (34.52x) | 2130.86 (15.51x) |
| ListValue JSON parse | 658.71 | — | — | 8583.96 (13.03x) | 3782.48 (5.74x) |
| ListValue Escape JSON parse | 677.86 | — | — | 8646.63 (12.76x) | 3987.37 (5.88x) |
| EmptyListValue JSON stringify | 40.33 | — | — | 684.99 (16.98x) | 188.13 (4.66x) |
| EmptyListValue JSON parse | 126.17 | — | — | 2242.85 (17.78x) | 332.06 (2.63x) |
| DoubleValue JSON stringify | 68.42 | — | — | 858.58 (12.55x) | 190.85 (2.79x) |
| DoubleValue JSON parse | 111.53 | — | — | 1228.58 (11.02x) | 285.78 (2.56x) |
| DoubleValue String JSON parse | 111.15 | — | — | 1175.91 (10.58x) | 363.77 (3.27x) |
| DoubleValue Exponent JSON parse | 113.35 | — | — | 1239.30 (10.93x) | 290.28 (2.56x) |
| NegativeDoubleValue JSON stringify | 68.23 | — | — | 854.76 (12.53x) | 196.79 (2.88x) |
| NegativeDoubleValue JSON parse | 112.09 | — | — | 1244.53 (11.10x) | 287.59 (2.57x) |
| ZeroDoubleValue JSON stringify | 47.22 | — | — | 794.80 (16.83x) | 137.57 (2.91x) |
| ZeroDoubleValue JSON parse | 107.89 | — | — | 1156.59 (10.72x) | 257.71 (2.39x) |
| DoubleValue NaN JSON stringify | 46.15 | — | — | 658.62 (14.27x) | 123.58 (2.68x) |
| DoubleValue NaN JSON parse | 104.79 | — | — | 1090.29 (10.40x) | 288.26 (2.75x) |
| DoubleValue Infinity JSON stringify | 48.24 | — | — | 657.91 (13.64x) | 123.83 (2.57x) |
| DoubleValue Infinity JSON parse | 105.55 | — | — | 1109.48 (10.51x) | 401.48 (3.80x) |
| DoubleValue NegativeInfinity JSON stringify | 47.87 | — | — | 656.02 (13.70x) | 126.58 (2.64x) |
| DoubleValue NegativeInfinity JSON parse | 108.78 | — | — | 1120.64 (10.30x) | 289.47 (2.66x) |
| FloatValue JSON stringify | 72.33 | — | — | 826.14 (11.42x) | 187.35 (2.59x) |
| FloatValue JSON parse | 110.51 | — | — | 1263.00 (11.43x) | 291.33 (2.64x) |
| FloatValue String JSON parse | 110.75 | — | — | 1180.11 (10.66x) | 354.87 (3.20x) |
| FloatValue Exponent JSON parse | 112.20 | — | — | 1272.42 (11.34x) | 288.56 (2.57x) |
| NegativeFloatValue JSON stringify | 70.90 | — | — | 799.65 (11.28x) | 184.06 (2.60x) |
| NegativeFloatValue JSON parse | 110.32 | — | — | 1222.91 (11.09x) | 286.39 (2.60x) |
| ZeroFloatValue JSON stringify | 47.15 | — | — | 742.28 (15.74x) | 145.59 (3.09x) |
| ZeroFloatValue JSON parse | 107.54 | — | — | 1151.59 (10.71x) | 256.65 (2.39x) |
| FloatValue NaN JSON stringify | 46.15 | — | — | 634.75 (13.75x) | 120.05 (2.60x) |
| FloatValue NaN JSON parse | 104.70 | — | — | 1083.69 (10.35x) | 268.45 (2.56x) |
| FloatValue Infinity JSON stringify | 47.76 | — | — | 643.99 (13.48x) | 140.42 (2.94x) |
| FloatValue Infinity JSON parse | 106.67 | — | — | 1107.22 (10.38x) | 267.74 (2.51x) |
| FloatValue NegativeInfinity JSON stringify | 48.13 | — | — | 639.26 (13.28x) | 123.24 (2.56x) |
| FloatValue NegativeInfinity JSON parse | 108.06 | — | — | 1098.29 (10.16x) | 284.14 (2.63x) |
| Int64Value JSON stringify | 50.67 | — | — | 675.53 (13.33x) | 280.78 (5.54x) |
| Int64Value JSON parse | 125.10 | — | — | 1222.73 (9.77x) | 470.96 (3.76x) |
| Int64Value Number JSON parse | 128.99 | — | — | 1284.67 (9.96x) | 365.20 (2.83x) |
| Int64Value Exponent JSON parse | 117.27 | — | — | 1219.45 (10.40x) | 372.28 (3.17x) |
| ZeroInt64Value JSON stringify | 41.47 | — | — | 610.52 (14.72x) | 193.72 (4.67x) |
| ZeroInt64Value JSON parse | 106.74 | — | — | 1091.47 (10.23x) | 335.14 (3.14x) |
| NegativeInt64Value JSON stringify | 50.47 | — | — | 673.98 (13.35x) | 285.59 (5.66x) |
| NegativeInt64Value JSON parse | 127.51 | — | — | 1215.23 (9.53x) | 481.35 (3.77x) |
| MinInt64Value JSON stringify | 49.80 | — | — | 675.70 (13.57x) | 294.59 (5.92x) |
| MinInt64Value JSON parse | 134.43 | — | — | 1245.70 (9.27x) | 507.94 (3.78x) |
| MaxInt64Value JSON stringify | 49.42 | — | — | 677.21 (13.70x) | 288.68 (5.84x) |
| MaxInt64Value JSON parse | 134.15 | — | — | 1253.57 (9.34x) | 477.91 (3.56x) |
| UInt64Value JSON stringify | 49.73 | — | — | 678.24 (13.64x) | 282.88 (5.69x) |
| UInt64Value JSON parse | 127.28 | — | — | 1213.21 (9.53x) | 463.02 (3.64x) |
| UInt64Value Number JSON parse | 127.72 | — | — | 1294.90 (10.14x) | 358.97 (2.81x) |
| UInt64Value Exponent JSON parse | 117.54 | — | — | 1230.07 (10.47x) | 356.58 (3.03x) |
| ZeroUInt64Value JSON stringify | 41.71 | — | — | 615.16 (14.75x) | 195.06 (4.68x) |
| ZeroUInt64Value JSON parse | 107.14 | — | — | 1098.25 (10.25x) | 344.45 (3.21x) |
| MaxUInt64Value JSON stringify | 49.34 | — | — | 678.76 (13.76x) | 289.38 (5.87x) |
| MaxUInt64Value JSON parse | 138.04 | — | — | 1269.94 (9.20x) | 469.76 (3.40x) |
| Int32Value JSON stringify | 46.79 | — | — | 634.85 (13.57x) | 137.49 (2.94x) |
| Int32Value JSON parse | 131.83 | — | — | 1190.27 (9.03x) | 322.75 (2.45x) |
| Int32Value String JSON parse | 135.79 | — | — | 1131.06 (8.33x) | 398.71 (2.94x) |
| Int32Value Exponent JSON parse | 134.92 | — | — | 1224.19 (9.07x) | 366.03 (2.71x) |
| ZeroInt32Value JSON stringify | 46.73 | — | — | 619.12 (13.25x) | 130.61 (2.79x) |
| ZeroInt32Value JSON parse | 127.16 | — | — | 1157.97 (9.11x) | 270.72 (2.13x) |
| NegativeInt32Value JSON stringify | 46.65 | — | — | 643.94 (13.80x) | 139.14 (2.98x) |
| NegativeInt32Value JSON parse | 131.15 | — | — | 1197.51 (9.13x) | 321.90 (2.45x) |
| MinInt32Value JSON stringify | 47.15 | — | — | 640.79 (13.59x) | 138.82 (2.94x) |
| MinInt32Value JSON parse | 137.89 | — | — | 1221.87 (8.86x) | 358.93 (2.60x) |
| MaxInt32Value JSON stringify | 47.24 | — | — | 630.61 (13.35x) | 139.48 (2.95x) |
| MaxInt32Value JSON parse | 137.29 | — | — | 1200.25 (8.74x) | 345.49 (2.52x) |
| UInt32Value JSON stringify | 46.87 | — | — | 628.42 (13.41x) | 138.78 (2.96x) |
| UInt32Value JSON parse | 131.96 | — | — | 1182.14 (8.96x) | 315.09 (2.39x) |
| UInt32Value String JSON parse | 135.55 | — | — | 1124.46 (8.30x) | 416.41 (3.07x) |
| UInt32Value Exponent JSON parse | 135.65 | — | — | 1219.30 (8.99x) | 484.09 (3.57x) |
| ZeroUInt32Value JSON stringify | 46.74 | — | — | 614.46 (13.15x) | 132.96 (2.84x) |
| ZeroUInt32Value JSON parse | 127.78 | — | — | 1158.04 (9.06x) | 270.04 (2.11x) |
| MaxUInt32Value JSON stringify | 47.29 | — | — | 633.81 (13.40x) | 147.42 (3.12x) |
| MaxUInt32Value JSON parse | 137.53 | — | — | 1209.47 (8.79x) | 345.04 (2.51x) |
| BoolValue JSON stringify | 45.22 | — | — | 612.83 (13.55x) | 125.79 (2.78x) |
| BoolValue JSON parse | 59.89 | — | — | 1059.75 (17.69x) | 221.70 (3.70x) |
| FalseBoolValue JSON stringify | 45.29 | — | — | 601.57 (13.28x) | 124.64 (2.75x) |
| FalseBoolValue JSON parse | 60.39 | — | — | 1055.82 (17.48x) | 222.73 (3.69x) |
| StringValue JSON stringify | 51.89 | — | — | 656.19 (12.65x) | 181.97 (3.51x) |
| StringValue JSON parse | 119.74 | — | — | 1140.42 (9.52x) | 322.24 (2.69x) |
| StringValue Escape JSON parse | 129.73 | — | — | 1168.58 (9.01x) | 375.12 (2.89x) |
| EmptyStringValue JSON stringify | 49.07 | — | — | 621.73 (12.67x) | 181.70 (3.70x) |
| EmptyStringValue JSON parse | 65.91 | — | — | 1111.58 (16.87x) | 241.79 (3.67x) |
| BytesValue JSON stringify | 49.01 | — | — | 659.78 (13.46x) | 219.01 (4.47x) |
| BytesValue JSON parse | 126.75 | — | — | 1168.03 (9.22x) | 357.70 (2.82x) |
| BytesValue URL JSON parse | 143.41 | — | — | 1159.88 (8.09x) | 336.46 (2.35x) |
| EmptyBytesValue JSON stringify | 40.61 | — | — | 638.93 (15.73x) | 189.24 (4.66x) |
| EmptyBytesValue JSON parse | 69.01 | — | — | 1137.80 (16.49x) | 306.17 (4.44x) |
| TextFormat format | 180.62 | — | — | 2621.07 (14.51x) | 2595.18 (14.37x) |
| TextFormat parse | 673.25 | — | — | 4988.70 (7.41x) | 6569.74 (9.76x) |
| packed fixed32 encode | 2.70 | 548.18 (203.03x) | 539.61 (199.86x) | 43.73 (16.20x) | 418.21 (154.89x) |
| packed fixed32 decode | 8.34 | 1201.94 (144.12x) | 2249.06 (269.67x) | 49.18 (5.90x) | 1575.63 (188.92x) |
| packed fixed64 encode | 2.00 | 609.28 (304.64x) | 619.80 (309.90x) | 75.84 (37.92x) | 395.84 (197.92x) |
| packed fixed64 decode | 4.54 | 1034.22 (227.80x) | 7950.19 (1751.14x) | 79.63 (17.54x) | 2170.37 (478.06x) |
| packed sfixed32 encode | 2.01 | 550.05 (273.66x) | 544.37 (270.83x) | 44.10 (21.94x) | 434.49 (216.16x) |
| packed sfixed32 decode | 4.53 | 1040.85 (229.77x) | 1966.45 (434.09x) | 48.93 (10.80x) | 1542.25 (340.45x) |
| packed sfixed64 encode | 2.01 | 619.06 (307.99x) | 561.40 (279.30x) | 76.09 (37.86x) | 403.33 (200.66x) |
| packed sfixed64 decode | 5.53 | 1035.19 (187.20x) | 7913.50 (1431.01x) | 79.35 (14.35x) | 2160.93 (390.76x) |
| packed float encode | 2.01 | 812.48 (404.22x) | 540.37 (268.84x) | 44.01 (21.90x) | 415.61 (206.77x) |
| packed float decode | 4.54 | 1049.51 (231.17x) | 2033.40 (447.89x) | 48.85 (10.76x) | 1537.83 (338.73x) |
| packed double encode | 2.01 | 843.51 (419.66x) | 561.07 (279.14x) | 75.99 (37.80x) | 362.65 (180.42x) |
| packed double decode | 4.53 | 1030.41 (227.46x) | 2058.91 (454.51x) | 79.73 (17.60x) | 2154.90 (475.70x) |
| packed uint64 encode | 1293.31 | 4606.18 (3.56x) | 4026.03 (3.11x) | 2119.18 (1.64x) | 3448.20 (2.67x) |
| packed uint64 decode | 1790.71 | 2783.95 (1.55x) | 8849.20 (4.94x) | 2800.51 (1.56x) | 6221.54 (3.47x) |
| packed uint32 encode | 925.88 | 3621.26 (3.91x) | 3263.21 (3.52x) | 1748.79 (1.89x) | 2885.32 (3.12x) |
| packed uint32 decode | 1295.91 | 2425.18 (1.87x) | 3267.68 (2.52x) | 2006.10 (1.55x) | 4684.68 (3.61x) |
| packed int64 encode | 1416.43 | 10990.24 (7.76x) | 6071.14 (4.29x) | 2896.12 (2.04x) | 4114.46 (2.90x) |
| packed int64 decode | 2738.94 | 3452.89 (1.26x) | 10256.89 (3.74x) | 4620.24 (1.69x) | 7747.92 (2.83x) |
| packed sint32 encode | 783.43 | 3047.05 (3.89x) | 2844.18 (3.63x) | 1535.93 (1.96x) | 3392.58 (4.33x) |
| packed sint32 decode | 952.45 | 2544.44 (2.67x) | 3213.98 (3.37x) | 1141.01 (1.20x) | 3058.63 (3.21x) |
| packed sint64 encode | 1423.80 | 4936.46 (3.47x) | 4280.94 (3.01x) | 2414.44 (1.70x) | 4145.38 (2.91x) |
| packed sint64 decode | 2036.65 | 3060.27 (1.50x) | 9656.48 (4.74x) | 2966.34 (1.46x) | 6485.17 (3.18x) |
| packed bool encode | 2.00 | 1334.11 (667.05x) | 524.98 (262.49x) | 15.96 (7.98x) | 2219.81 (1109.90x) |
| packed bool decode | 262.96 | 1537.53 (5.85x) | 2546.41 (9.68x) | 809.57 (3.08x) | 1574.33 (5.99x) |
| packed enum encode | 272.33 | 2720.54 (9.99x) | 1813.16 (6.66x) | 1084.40 (3.98x) | 2489.69 (9.14x) |
| packed enum decode | 153.14 | 1530.74 (10.00x) | 2918.00 (19.05x) | 751.65 (4.91x) | 1994.06 (13.02x) |
| large map encode | 4045.87 | 16676.65 (4.12x) | 9732.89 (2.41x) | 21734.50 (5.37x) | 209243.29 (51.72x) |
| shuffled large map deterministic binary encode | 27783.41 | — | — | 93923.00 (3.38x) | 442892.58 (15.94x) |
| large map decode | 25204.11 | 90740.29 (3.60x) | 89455.17 (3.55x) | 90772.70 (3.60x) | 276679.51 (10.98x) |
The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound `Duration`, non-empty/escaped-input parse/number-exponent parse and empty `Struct`, object/escaped-object parse/object-number-exponent/list/escaped-list/string-scalar/escaped-string-scalar/number-exponent/negative-number `Value` (including default-like scalar and empty object/list kinds),
`FieldMask` (non-empty, escaped JSON parse input, and empty), escaped-input parse/short-fraction parse/micro/nano/offset/min/pre/post/max-bound `Timestamp`, `Empty`, min/zero/positive/number-input parse/numeric-exponent parse/negative/max `Int64Value`, negative/zero/positive finite/string-input parse/numeric-exponent parse `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), negative/zero/positive finite/string-input parse/numeric-exponent parse `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), zero/normal/number-input parse/numeric-exponent parse/max `UInt64Value`, min/zero/positive/string-input parse/numeric-exponent parse/negative/max `Int32Value`, zero/normal/string-input parse/numeric-exponent parse/max `UInt32Value`, true/false `BoolValue`, non-empty/escape-input parse/empty `StringValue`, base64/base64url parse/empty `BytesValue`, and recursive nested `Any` payloads), direct zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound Duration, non-empty/escaped-input parse/empty FieldMask, and escaped-input parse/short-fraction parse/micro/nano/offset/min/pre/post/max-bound Timestamp WKT JSON plus other direct WKT JSON, including non-empty/escaped-input parse/number-exponent parse/empty `Struct`, object/escaped-object parse/object-number-exponent/list/escaped-list/string-scalar/escaped-string-scalar/number-exponent/negative-number `Value`, and escaped/non-empty/empty `ListValue`, TextFormat, packed scalars, large bytes,
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
