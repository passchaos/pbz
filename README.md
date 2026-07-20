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

Latest accepted comparison (`/tmp/pbz-compare-enum-name-json-final.log`,
summarized in `/tmp/pbz-summary-enum-name-json-final.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 23.81 | 127.70 (5.36x) | 62.80 (2.64x) | 103.96 (4.37x) | 863.85 (36.28x) |
| binary decode | 128.31 | 310.77 (2.42x) | 357.41 (2.79x) | 323.43 (2.52x) | 1180.30 (9.20x) |
| unknown fields count by number | 7.08 | — | — | 240.84 (34.02x) | — |
| deterministic binary encode | 74.18 | — | — | 130.62 (1.76x) | 1286.54 (17.34x) |
| scalarmix encode | 28.75 | 119.01 (4.14x) | 84.09 (2.92x) | 30.91 (1.08x) | 212.63 (7.40x) |
| scalarmix decode | 50.62 | 171.40 (3.39x) | 286.94 (5.67x) | 91.76 (1.81x) | 335.84 (6.63x) |
| textbytes encode | 13.80 | 97.44 (7.06x) | 54.57 (3.95x) | 117.24 (8.50x) | 178.22 (12.91x) |
| textbytes decode | 62.50 | 394.46 (6.31x) | 395.98 (6.34x) | 163.92 (2.62x) | 711.16 (11.38x) |
| largebytes encode | 29.77 | 2766.69 (92.94x) | 2698.29 (90.64x) | 2754.86 (92.54x) | 2806.98 (94.29x) |
| largebytes decode | 97.61 | 6665.01 (68.28x) | 3370.13 (34.53x) | 3593.31 (36.81x) | 34126.69 (349.62x) |
| presencemix encode | 19.45 | 66.62 (3.43x) | 27.76 (1.43x) | 57.45 (2.95x) | 259.97 (13.37x) |
| presencemix decode | 61.09 | 168.62 (2.76x) | 108.69 (1.78x) | 167.27 (2.74x) | 486.42 (7.96x) |
| complex encode | 68.29 | 166.01 (2.43x) | 120.72 (1.77x) | 171.54 (2.51x) | 1004.91 (14.72x) |
| complex decode | 192.81 | 474.86 (2.46x) | 351.45 (1.82x) | 427.82 (2.22x) | 1567.47 (8.13x) |
| complex deterministic binary encode | 95.00 | — | — | 221.49 (2.33x) | 1191.74 (12.54x) |
| complex JSON stringify | 392.55 | — | — | 5964.31 (15.19x) | 7535.42 (19.20x) |
| complex JSON parse | 2370.56 | — | — | 14617.90 (6.17x) | 9546.47 (4.03x) |
| complex TextFormat format | 245.72 | — | — | 4779.42 (19.45x) | 6466.15 (26.32x) |
| complex TextFormat parse | 1868.39 | — | — | 8277.18 (4.43x) | 10377.41 (5.55x) |
| packed int32 encode | 752.44 | 5408.38 (7.19x) | 3367.75 (4.48x) | 2404.67 (3.20x) | 3947.96 (5.25x) |
| packed int32 decode | 770.91 | 2392.51 (3.10x) | 4119.75 (5.34x) | 1020.96 (1.32x) | 4509.96 (5.85x) |
| JSON stringify | 152.94 | — | — | 3718.36 (24.31x) | 2635.55 (17.23x) |
| JSON parse | 2073.05 | — | — | 9373.54 (4.52x) | 5350.74 (2.58x) |
| MapKeySurrogate JSON parse | 555.99 | — | — | 4484.74 (8.07x) | 1192.05 (2.14x) |
| NullFields JSON parse | 656.53 | — | — | 2413.99 (3.68x) | 813.67 (1.24x) |
| OpenEnum JSON parse | 296.74 | — | — | 4507.13 (15.19x) | 518.79 (1.75x) |
| EnumName JSON parse | 293.35 | — | — | 4843.55 (16.51x) | 443.11 (1.51x) |
| IntExponent JSON parse | 1662.37 | — | — | 9118.14 (5.49x) | 5038.83 (3.03x) |
| Any WKT JSON stringify | 174.57 | — | — | 2502.02 (14.33x) | 1353.98 (7.76x) |
| Any WKT JSON parse | 709.52 | — | — | 3751.89 (5.29x) | 1952.61 (2.75x) |
| Any Duration Escape WKT JSON parse | 530.96 | — | — | 3777.07 (7.11x) | 1958.42 (3.69x) |
| Any PlusDuration WKT JSON parse | 517.17 | — | — | 3670.90 (7.10x) | 1812.51 (3.50x) |
| Any ShortFractionDuration WKT JSON parse | 513.45 | — | — | 3612.03 (7.03x) | 1784.88 (3.48x) |
| Any MicroDuration WKT JSON stringify | 133.25 | — | — | 2315.67 (17.38x) | 1034.62 (7.76x) |
| Any MicroDuration WKT JSON parse | 516.24 | — | — | 3545.68 (6.87x) | 2275.49 (4.41x) |
| Any NanoDuration WKT JSON stringify | 129.94 | — | — | 2355.41 (18.13x) | 1198.71 (9.23x) |
| Any NanoDuration WKT JSON parse | 522.08 | — | — | 3684.71 (7.06x) | 2151.77 (4.12x) |
| Any NegativeDuration WKT JSON stringify | 262.57 | — | — | 2391.88 (9.11x) | 1401.66 (5.34x) |
| Any NegativeDuration WKT JSON parse | 855.98 | — | — | 3811.14 (4.45x) | 1916.39 (2.24x) |
| Any FractionalNegativeDuration WKT JSON stringify | 247.96 | — | — | 2304.94 (9.30x) | 1218.57 (4.91x) |
| Any FractionalNegativeDuration WKT JSON parse | 592.00 | — | — | 3763.11 (6.36x) | 2018.08 (3.41x) |
| Any MaxDuration WKT JSON stringify | 170.07 | — | — | 2216.34 (13.03x) | 1275.66 (7.50x) |
| Any MaxDuration WKT JSON parse | 631.23 | — | — | 3812.29 (6.04x) | 2177.71 (3.45x) |
| Any MinDuration WKT JSON stringify | 165.48 | — | — | 3174.18 (19.18x) | 1350.42 (8.16x) |
| Any MinDuration WKT JSON parse | 542.84 | — | — | 5283.92 (9.73x) | 1835.47 (3.38x) |
| Any ZeroDuration WKT JSON stringify | 109.20 | — | — | 1879.06 (17.21x) | 1079.03 (9.88x) |
| Any ZeroDuration WKT JSON parse | 480.22 | — | — | 4131.97 (8.60x) | 1935.20 (4.03x) |
| Any FieldMask WKT JSON stringify | 228.26 | — | — | 2900.60 (12.71x) | 1792.96 (7.85x) |
| Any FieldMask WKT JSON parse | 702.06 | — | — | 5216.43 (7.43x) | 2696.46 (3.84x) |
| Any FieldMask Escape WKT JSON parse | 730.73 | — | — | 4378.68 (5.99x) | 2890.14 (3.96x) |
| Any EmptyFieldMask WKT JSON stringify | 107.41 | — | — | 1292.66 (12.03x) | 820.75 (7.64x) |
| Any EmptyFieldMask WKT JSON parse | 436.21 | — | — | 3014.22 (6.91x) | 1601.78 (3.67x) |
| Any Timestamp WKT JSON stringify | 362.16 | — | — | 2619.01 (7.23x) | 1140.11 (3.15x) |
| Any Timestamp WKT JSON parse | 835.33 | — | — | 3746.32 (4.48x) | 2148.20 (2.57x) |
| Any Timestamp Escape WKT JSON parse | 724.32 | — | — | 3920.13 (5.41x) | 2554.13 (3.53x) |
| Any ShortFraction Timestamp WKT JSON parse | 608.12 | — | — | 4428.55 (7.28x) | 1909.00 (3.14x) |
| Any Micro Timestamp WKT JSON stringify | 181.50 | — | — | 2821.70 (15.55x) | 1271.95 (7.01x) |
| Any Micro Timestamp WKT JSON parse | 580.07 | — | — | 3971.46 (6.85x) | 2190.10 (3.78x) |
| Any Nano Timestamp WKT JSON stringify | 175.55 | — | — | 2473.21 (14.09x) | 1321.68 (7.53x) |
| Any Nano Timestamp WKT JSON parse | 567.72 | — | — | 4008.56 (7.06x) | 2530.39 (4.46x) |
| Any Offset Timestamp WKT JSON parse | 573.97 | — | — | 3973.40 (6.92x) | 2223.99 (3.87x) |
| Any PreEpoch Timestamp WKT JSON stringify | 140.81 | — | — | 2355.80 (16.73x) | 1207.98 (8.58x) |
| Any PreEpoch Timestamp WKT JSON parse | 553.63 | — | — | 3796.31 (6.86x) | 2124.40 (3.84x) |
| Any Max Timestamp WKT JSON stringify | 326.68 | — | — | 2523.75 (7.73x) | 1221.33 (3.74x) |
| Any Max Timestamp WKT JSON parse | 900.82 | — | — | 3756.07 (4.17x) | 2418.75 (2.69x) |
| Any Min Timestamp WKT JSON stringify | 178.11 | — | — | 2385.59 (13.39x) | 1173.79 (6.59x) |
| Any Min Timestamp WKT JSON parse | 735.37 | — | — | 3689.87 (5.02x) | 1977.91 (2.69x) |
| Any Empty WKT JSON stringify | 151.22 | — | — | 1087.50 (7.19x) | 677.40 (4.48x) |
| Any Empty WKT JSON parse | 333.18 | — | — | 2782.08 (8.35x) | 1514.35 (4.55x) |
| Any Struct WKT JSON stringify | 628.21 | — | — | 7308.43 (11.63x) | 8484.98 (13.51x) |
| Any Struct WKT JSON parse | 1756.29 | — | — | 13892.20 (7.91x) | 11905.97 (6.78x) |
| Any Struct Escape WKT JSON parse | 2429.01 | — | — | 14219.60 (5.85x) | 11561.92 (4.76x) |
| Any Struct NumberExponent WKT JSON parse | 1758.75 | — | — | 13862.00 (7.88x) | 12249.19 (6.96x) |
| Any Struct Surrogate WKT JSON parse | 756.40 | — | — | 8033.17 (10.62x) | 3825.11 (5.06x) |
| Any Struct KeySurrogate WKT JSON parse | 752.70 | — | — | 7718.34 (10.25x) | 4483.32 (5.96x) |
| Any EmptyStruct WKT JSON stringify | 197.98 | — | — | 990.71 (5.00x) | 1292.71 (6.53x) |
| Any EmptyStruct WKT JSON parse | 707.01 | — | — | 2612.31 (3.69x) | 1815.55 (2.57x) |
| Any Value WKT JSON stringify | 861.32 | — | — | 7142.31 (8.29x) | 8865.75 (10.29x) |
| Any Value WKT JSON parse | 1851.99 | — | — | 14469.40 (7.81x) | 12429.56 (6.71x) |
| Any Value Escape WKT JSON parse | 1854.75 | — | — | 14630.10 (7.89x) | 12404.00 (6.69x) |
| Any Value NumberExponent WKT JSON parse | 2062.63 | — | — | 14988.20 (7.27x) | 12390.58 (6.01x) |
| Any Value Surrogate WKT JSON parse | 822.86 | — | — | 8270.74 (10.05x) | 5063.24 (6.15x) |
| Any Value KeySurrogate WKT JSON parse | 836.46 | — | — | 7935.90 (9.49x) | 4615.37 (5.52x) |
| Any NullValue WKT JSON stringify | 125.75 | — | — | 2692.88 (21.41x) | 1078.23 (8.57x) |
| Any NullValue WKT JSON parse | 455.85 | — | — | 5001.43 (10.97x) | 2034.35 (4.46x) |
| Any StringScalarValue WKT JSON stringify | 148.78 | — | — | 2689.01 (18.07x) | 1195.67 (8.04x) |
| Any StringScalarValue WKT JSON parse | 829.94 | — | — | 4314.98 (5.20x) | 2188.83 (2.64x) |
| Any StringScalarValue Escape WKT JSON parse | 822.21 | — | — | 4440.03 (5.40x) | 2222.48 (2.70x) |
| Any StringScalarValue Surrogate WKT JSON parse | 626.25 | — | — | 4445.27 (7.10x) | 2239.00 (3.58x) |
| Any EmptyStringScalarValue WKT JSON stringify | 176.03 | — | — | 2759.40 (15.68x) | 1058.52 (6.01x) |
| Any EmptyStringScalarValue WKT JSON parse | 571.21 | — | — | 4401.82 (7.71x) | 1986.43 (3.48x) |
| Any NumberValue WKT JSON stringify | 170.95 | — | — | 3055.82 (17.88x) | 1367.40 (8.00x) |
| Any NumberValue WKT JSON parse | 500.24 | — | — | 4652.29 (9.30x) | 2184.54 (4.37x) |
| Any NumberValue Exponent WKT JSON parse | 504.15 | — | — | 4471.61 (8.87x) | 2397.81 (4.76x) |
| Any NegativeNumberValue WKT JSON stringify | 168.65 | — | — | 3263.26 (19.35x) | 1354.38 (8.03x) |
| Any NegativeNumberValue WKT JSON parse | 500.85 | — | — | 4603.87 (9.19x) | 2356.19 (4.70x) |
| Any ZeroNumberValue WKT JSON stringify | 137.46 | — | — | 3073.01 (22.36x) | 1127.27 (8.20x) |
| Any ZeroNumberValue WKT JSON parse | 497.51 | — | — | 4432.97 (8.91x) | 1888.61 (3.80x) |
| Any BoolScalarValue WKT JSON stringify | 125.29 | — | — | 2702.52 (21.57x) | 1234.41 (9.85x) |
| Any BoolScalarValue WKT JSON parse | 461.99 | — | — | 4336.84 (9.39x) | 1888.82 (4.09x) |
| Any FalseBoolScalarValue WKT JSON stringify | 125.83 | — | — | 2655.10 (21.10x) | 1365.14 (10.85x) |
| Any FalseBoolScalarValue WKT JSON parse | 461.54 | — | — | 4375.68 (9.48x) | 1804.08 (3.91x) |
| Any ListKindValue WKT JSON stringify | 894.80 | — | — | 6950.21 (7.77x) | 7575.66 (8.47x) |
| Any ListKindValue WKT JSON parse | 1562.60 | — | — | 12378.40 (7.92x) | 10006.92 (6.40x) |
| Any ListKindValue Escape WKT JSON parse | 1445.85 | — | — | 12426.70 (8.59x) | 10119.72 (7.00x) |
| Any ListKindValue Surrogate WKT JSON parse | 727.75 | — | — | 5816.73 (7.99x) | 3929.03 (5.40x) |
| Any EmptyStructKindValue WKT JSON stringify | 157.99 | — | — | 3589.08 (22.72x) | 1960.17 (12.41x) |
| Any EmptyStructKindValue WKT JSON parse | 495.98 | — | — | 6820.62 (13.75x) | 2786.96 (5.62x) |
| Any EmptyListKindValue WKT JSON stringify | 233.43 | — | — | 3833.95 (16.42x) | 1440.12 (6.17x) |
| Any EmptyListKindValue WKT JSON parse | 814.52 | — | — | 6222.19 (7.64x) | 2722.89 (3.34x) |
| Any DoubleValue WKT JSON stringify | 257.81 | — | — | 3190.92 (12.38x) | 1097.88 (4.26x) |
| Any DoubleValue WKT JSON parse | 617.47 | — | — | 4393.04 (7.11x) | 1829.22 (2.96x) |
| Any DoubleValue String WKT JSON parse | 616.60 | — | — | 3871.41 (6.28x) | 1933.68 (3.14x) |
| Any DoubleValue Exponent WKT JSON parse | 531.92 | — | — | 2767.77 (5.20x) | 1850.02 (3.48x) |
| Any NegativeDoubleValue WKT JSON stringify | 194.22 | — | — | 5735.97 (29.53x) | 931.04 (4.79x) |
| Any NegativeDoubleValue WKT JSON parse | 527.42 | — | — | 6709.76 (12.72x) | 1949.68 (3.70x) |
| Any ZeroDoubleValue WKT JSON stringify | 163.39 | — | — | 1565.74 (9.58x) | 916.73 (5.61x) |
| Any ZeroDoubleValue WKT JSON parse | 525.34 | — | — | 3961.30 (7.54x) | 1760.72 (3.35x) |
| Any DoubleValue NaN WKT JSON stringify | 154.76 | — | — | 2875.30 (18.58x) | 835.70 (5.40x) |
| Any DoubleValue NaN WKT JSON parse | 509.89 | — | — | 5092.58 (9.99x) | 1934.95 (3.79x) |
| Any DoubleValue Infinity WKT JSON stringify | 215.09 | — | — | 1727.04 (8.03x) | 948.31 (4.41x) |
| Any DoubleValue Infinity WKT JSON parse | 814.91 | — | — | 3371.67 (4.14x) | 1899.32 (2.33x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 245.09 | — | — | 2822.23 (11.52x) | 790.07 (3.22x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 678.93 | — | — | 4971.85 (7.32x) | 1969.24 (2.90x) |
| Any FloatValue WKT JSON stringify | 285.49 | — | — | 3322.26 (11.64x) | 936.85 (3.28x) |
| Any FloatValue WKT JSON parse | 575.41 | — | — | 5308.83 (9.23x) | 1663.39 (2.89x) |
| Any FloatValue String WKT JSON parse | 525.10 | — | — | 5365.46 (10.22x) | 2111.47 (4.02x) |
| Any FloatValue Exponent WKT JSON parse | 518.77 | — | — | 5410.48 (10.43x) | 1682.75 (3.24x) |
| Any NegativeFloatValue WKT JSON stringify | 194.50 | — | — | 3392.96 (17.44x) | 837.66 (4.31x) |
| Any NegativeFloatValue WKT JSON parse | 514.35 | — | — | 4279.79 (8.32x) | 1893.52 (3.68x) |
| Any ZeroFloatValue WKT JSON stringify | 166.01 | — | — | 1437.57 (8.66x) | 835.03 (5.03x) |
| Any ZeroFloatValue WKT JSON parse | 513.65 | — | — | 3607.90 (7.02x) | 1763.48 (3.43x) |
| Any FloatValue NaN WKT JSON stringify | 153.99 | — | — | 2810.51 (18.25x) | 788.30 (5.12x) |
| Any FloatValue NaN WKT JSON parse | 691.14 | — | — | 5034.96 (7.29x) | 1961.72 (2.84x) |
| Any FloatValue Infinity WKT JSON stringify | 245.81 | — | — | 2528.29 (10.29x) | 888.98 (3.62x) |
| Any FloatValue Infinity WKT JSON parse | 756.35 | — | — | 4417.54 (5.84x) | 1690.87 (2.24x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 206.67 | — | — | 2568.43 (12.43x) | 833.50 (4.03x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 620.91 | — | — | 3179.08 (5.12x) | 1839.79 (2.96x) |
| Any Int64Value WKT JSON stringify | 213.91 | — | — | 1907.36 (8.92x) | 1094.31 (5.12x) |
| Any Int64Value WKT JSON parse | 631.39 | — | — | 3896.27 (6.17x) | 2059.67 (3.26x) |
| Any Int64Value Number WKT JSON parse | 635.09 | — | — | 3718.62 (5.86x) | 2022.59 (3.18x) |
| Any Int64Value Exponent WKT JSON parse | 595.69 | — | — | 3405.41 (5.72x) | 1889.64 (3.17x) |
| Any ZeroInt64Value WKT JSON stringify | 188.31 | — | — | 965.54 (5.13x) | 892.67 (4.74x) |
| Any ZeroInt64Value WKT JSON parse | 599.16 | — | — | 2516.93 (4.20x) | 1881.30 (3.14x) |
| Any NegativeInt64Value WKT JSON stringify | 201.58 | — | — | 2327.40 (11.55x) | 1099.18 (5.45x) |
| Any NegativeInt64Value WKT JSON parse | 632.29 | — | — | 3880.80 (6.14x) | 2119.59 (3.35x) |
| Any MinInt64Value WKT JSON stringify | 206.83 | — | — | 2566.61 (12.41x) | 958.33 (4.63x) |
| Any MinInt64Value WKT JSON parse | 642.48 | — | — | 3511.88 (5.47x) | 2420.59 (3.77x) |
| Any MaxInt64Value WKT JSON stringify | 209.98 | — | — | 2512.29 (11.96x) | 1046.81 (4.99x) |
| Any MaxInt64Value WKT JSON parse | 656.71 | — | — | 3413.17 (5.20x) | 2238.99 (3.41x) |
| Any UInt64Value WKT JSON stringify | 216.15 | — | — | 2440.75 (11.29x) | 1342.67 (6.21x) |
| Any UInt64Value WKT JSON parse | 545.65 | — | — | 3265.18 (5.98x) | 2210.33 (4.05x) |
| Any UInt64Value Number WKT JSON parse | 548.25 | — | — | 3529.74 (6.44x) | 1981.54 (3.61x) |
| Any UInt64Value Exponent WKT JSON parse | 532.70 | — | — | 3008.26 (5.65x) | 1976.24 (3.71x) |
| Any ZeroUInt64Value WKT JSON stringify | 158.35 | — | — | 931.30 (5.88x) | 1100.39 (6.95x) |
| Any ZeroUInt64Value WKT JSON parse | 524.92 | — | — | 2621.09 (4.99x) | 1979.23 (3.77x) |
| Any MaxUInt64Value WKT JSON stringify | 175.12 | — | — | 2025.96 (11.57x) | 969.74 (5.54x) |
| Any MaxUInt64Value WKT JSON parse | 551.64 | — | — | 3239.18 (5.87x) | 2354.51 (4.27x) |
| Any Int32Value WKT JSON stringify | 250.67 | — | — | 2132.86 (8.51x) | 820.41 (3.27x) |
| Any Int32Value WKT JSON parse | 801.88 | — | — | 3094.00 (3.86x) | 1851.22 (2.31x) |
| Any Int32Value String WKT JSON parse | 754.98 | — | — | 4678.09 (6.20x) | 1963.43 (2.60x) |
| Any Int32Value Exponent WKT JSON parse | 550.42 | — | — | 4764.14 (8.66x) | 1990.13 (3.62x) |
| Any ZeroInt32Value WKT JSON stringify | 166.86 | — | — | 1043.10 (6.25x) | 859.65 (5.15x) |
| Any ZeroInt32Value WKT JSON parse | 537.22 | — | — | 3061.51 (5.70x) | 1812.00 (3.37x) |
| Any NegativeInt32Value WKT JSON stringify | 166.62 | — | — | 1967.64 (11.81x) | 935.57 (5.61x) |
| Any NegativeInt32Value WKT JSON parse | 535.21 | — | — | 3215.86 (6.01x) | 2003.26 (3.74x) |
| Any MinInt32Value WKT JSON stringify | 166.43 | — | — | 1857.56 (11.16x) | 746.37 (4.48x) |
| Any MinInt32Value WKT JSON parse | 543.42 | — | — | 3130.89 (5.76x) | 1899.63 (3.50x) |
| Any MaxInt32Value WKT JSON stringify | 171.02 | — | — | 1890.90 (11.06x) | 857.28 (5.01x) |
| Any MaxInt32Value WKT JSON parse | 537.93 | — | — | 3064.98 (5.70x) | 2000.81 (3.72x) |
| Any UInt32Value WKT JSON stringify | 264.89 | — | — | 1935.10 (7.31x) | 832.17 (3.14x) |
| Any UInt32Value WKT JSON parse | 878.40 | — | — | 3256.96 (3.71x) | 1898.74 (2.16x) |
| Any UInt32Value String WKT JSON parse | 634.03 | — | — | 3493.86 (5.51x) | 2236.76 (3.53x) |
| Any UInt32Value Exponent WKT JSON parse | 634.05 | — | — | 3169.06 (5.00x) | 1979.84 (3.12x) |
| Any ZeroUInt32Value WKT JSON stringify | 174.52 | — | — | 960.43 (5.50x) | 766.27 (4.39x) |
| Any ZeroUInt32Value WKT JSON parse | 531.22 | — | — | 2516.05 (4.74x) | 1755.56 (3.30x) |
| Any MaxUInt32Value WKT JSON stringify | 182.12 | — | — | 1941.39 (10.66x) | 845.34 (4.64x) |
| Any MaxUInt32Value WKT JSON parse | 545.67 | — | — | 3169.26 (5.81x) | 1885.23 (3.45x) |
| Any BoolValue WKT JSON stringify | 165.07 | — | — | 2026.51 (12.28x) | 895.15 (5.42x) |
| Any BoolValue WKT JSON parse | 481.34 | — | — | 3003.62 (6.24x) | 1469.95 (3.05x) |
| Any FalseBoolValue WKT JSON stringify | 165.79 | — | — | 1137.41 (6.86x) | 935.99 (5.65x) |
| Any FalseBoolValue WKT JSON parse | 480.11 | — | — | 2843.78 (5.92x) | 1641.35 (3.42x) |
| Any StringValue WKT JSON stringify | 189.87 | — | — | 1939.38 (10.21x) | 892.01 (4.70x) |
| Any StringValue WKT JSON parse | 537.04 | — | — | 3378.98 (6.29x) | 1622.79 (3.02x) |
| Any StringValue Escape WKT JSON parse | 835.94 | — | — | 3549.43 (4.25x) | 2095.52 (2.51x) |
| Any StringValue Surrogate WKT JSON parse | 788.69 | — | — | 4019.05 (5.10x) | 1917.56 (2.43x) |
| Any EmptyStringValue WKT JSON stringify | 187.65 | — | — | 923.60 (4.92x) | 825.57 (4.40x) |
| Any EmptyStringValue WKT JSON parse | 599.85 | — | — | 2555.41 (4.26x) | 1831.47 (3.05x) |
| Any BytesValue WKT JSON stringify | 267.70 | — | — | 2263.39 (8.45x) | 948.04 (3.54x) |
| Any BytesValue WKT JSON parse | 570.47 | — | — | 3394.34 (5.95x) | 1938.43 (3.40x) |
| Any BytesValue URL WKT JSON parse | 594.08 | — | — | 3362.97 (5.66x) | 1812.41 (3.05x) |
| Any BytesValue StandardBase64 WKT JSON parse | 577.14 | — | — | 3509.92 (6.08x) | 1657.61 (2.87x) |
| Any BytesValue Unpadded WKT JSON parse | 562.26 | — | — | 3134.64 (5.58x) | 1768.98 (3.15x) |
| Any EmptyBytesValue WKT JSON stringify | 167.62 | — | — | 1046.05 (6.24x) | 880.53 (5.25x) |
| Any EmptyBytesValue WKT JSON parse | 520.41 | — | — | 2528.19 (4.86x) | 1884.66 (3.62x) |
| Nested Any WKT JSON stringify | 457.99 | — | — | 3247.39 (7.09x) | 1881.91 (4.11x) |
| Nested Any WKT JSON parse | 1227.97 | — | — | 5326.87 (4.34x) | 3778.11 (3.08x) |
| Duration JSON stringify | 63.27 | — | — | 1275.25 (20.16x) | 411.81 (6.51x) |
| Duration JSON parse | 24.58 | — | — | 1812.72 (73.75x) | 429.61 (17.48x) |
| Duration Escape JSON parse | 55.12 | — | — | 1806.73 (32.78x) | 455.81 (8.27x) |
| PlusDuration JSON parse | 24.87 | — | — | 1830.04 (73.58x) | 468.27 (18.83x) |
| ShortFractionDuration JSON parse | 21.64 | — | — | 1787.52 (82.60x) | 394.61 (18.24x) |
| MicroDuration JSON stringify | 84.11 | — | — | 1181.66 (14.05x) | 428.17 (5.09x) |
| MicroDuration JSON parse | 21.61 | — | — | 1834.48 (84.89x) | 400.84 (18.55x) |
| NanoDuration JSON stringify | 57.49 | — | — | 1295.25 (22.53x) | 448.46 (7.80x) |
| NanoDuration JSON parse | 27.74 | — | — | 1875.84 (67.62x) | 434.69 (15.67x) |
| NegativeDuration JSON stringify | 84.32 | — | — | 1220.65 (14.48x) | 496.13 (5.88x) |
| NegativeDuration JSON parse | 29.00 | — | — | 1994.12 (68.76x) | 427.20 (14.73x) |
| FractionalNegativeDuration JSON stringify | 85.93 | — | — | 1381.17 (16.07x) | 405.04 (4.71x) |
| FractionalNegativeDuration JSON parse | 27.92 | — | — | 1927.25 (69.03x) | 350.96 (12.57x) |
| MaxDuration JSON stringify | 70.27 | — | — | 1007.44 (14.34x) | 427.31 (6.08x) |
| MaxDuration JSON parse | 51.16 | — | — | 1849.63 (36.15x) | 395.21 (7.72x) |
| MinDuration JSON stringify | 49.96 | — | — | 1153.06 (23.08x) | 441.20 (8.83x) |
| MinDuration JSON parse | 31.15 | — | — | 1969.09 (63.21x) | 426.30 (13.69x) |
| ZeroDuration JSON stringify | 44.88 | — | — | 822.11 (18.32x) | 384.78 (8.57x) |
| ZeroDuration JSON parse | 16.67 | — | — | 1753.05 (105.16x) | 348.91 (20.93x) |
| FieldMask JSON stringify | 66.61 | — | — | 1440.18 (21.62x) | 765.17 (11.49x) |
| FieldMask JSON parse | 140.97 | — | — | 2406.86 (17.07x) | 1002.55 (7.11x) |
| FieldMask Escape JSON parse | 193.55 | — | — | 2143.19 (11.07x) | 1115.28 (5.76x) |
| EmptyFieldMask JSON stringify | 40.68 | — | — | 797.12 (19.59x) | 258.75 (6.36x) |
| EmptyFieldMask JSON parse | 4.78 | — | — | 1345.23 (281.43x) | 145.66 (30.47x) |
| Timestamp JSON stringify | 95.76 | — | — | 1613.30 (16.85x) | 433.45 (4.53x) |
| Timestamp JSON parse | 45.18 | — | — | 1886.54 (41.76x) | 428.30 (9.48x) |
| Timestamp Escape JSON parse | 98.20 | — | — | 2069.61 (21.08x) | 517.86 (5.27x) |
| ShortFraction Timestamp JSON parse | 43.53 | — | — | 2346.38 (53.90x) | 411.72 (9.46x) |
| Micro Timestamp JSON stringify | 95.70 | — | — | 1415.62 (14.79x) | 472.17 (4.93x) |
| Micro Timestamp JSON parse | 48.01 | — | — | 1861.73 (38.78x) | 457.25 (9.52x) |
| Nano Timestamp JSON stringify | 93.74 | — | — | 1532.26 (16.35x) | 501.05 (5.35x) |
| Nano Timestamp JSON parse | 50.71 | — | — | 1883.01 (37.13x) | 484.01 (9.54x) |
| Offset Timestamp JSON parse | 52.14 | — | — | 1912.32 (36.68x) | 526.12 (10.09x) |
| PreEpoch Timestamp JSON stringify | 66.11 | — | — | 1184.40 (17.92x) | 447.70 (6.77x) |
| PreEpoch Timestamp JSON parse | 43.02 | — | — | 1900.36 (44.17x) | 432.95 (10.06x) |
| Max Timestamp JSON stringify | 78.43 | — | — | 1518.67 (19.36x) | 453.38 (5.78x) |
| Max Timestamp JSON parse | 51.12 | — | — | 1909.17 (37.35x) | 463.18 (9.06x) |
| Min Timestamp JSON stringify | 79.51 | — | — | 1164.63 (14.65x) | 480.81 (6.05x) |
| Min Timestamp JSON parse | 41.23 | — | — | 1845.54 (44.76x) | 451.75 (10.96x) |
| Empty JSON stringify | 20.82 | — | — | 531.56 (25.53x) | 106.58 (5.12x) |
| Empty JSON parse | 73.64 | — | — | 903.98 (12.28x) | 258.67 (3.51x) |
| Struct JSON stringify | 174.54 | — | — | 7071.43 (40.51x) | 4109.79 (23.55x) |
| Struct JSON parse | 847.58 | — | — | 15004.20 (17.70x) | 6707.09 (7.91x) |
| Struct Escape JSON parse | 1018.41 | — | — | 13931.10 (13.68x) | 6155.03 (6.04x) |
| Struct NumberExponent JSON parse | 1029.46 | — | — | 14925.80 (14.50x) | 6156.03 (5.98x) |
| Struct Surrogate JSON parse | 425.70 | — | — | 6730.38 (15.81x) | 1548.53 (3.64x) |
| Struct KeySurrogate JSON parse | 396.43 | — | — | 6322.62 (15.95x) | 1549.63 (3.91x) |
| EmptyStruct JSON stringify | 41.60 | — | — | 703.14 (16.90x) | 344.52 (8.28x) |
| EmptyStruct JSON parse | 86.90 | — | — | 2547.46 (29.31x) | 368.78 (4.24x) |
| Value JSON stringify | 174.49 | — | — | 8309.08 (47.62x) | 3470.42 (19.89x) |
| Value JSON parse | 867.03 | — | — | 15132.80 (17.45x) | 6277.18 (7.24x) |
| Value Escape JSON parse | 917.45 | — | — | 15392.50 (16.78x) | 7033.34 (7.67x) |
| Value NumberExponent JSON parse | 863.82 | — | — | 15459.30 (17.90x) | 6686.00 (7.74x) |
| Value Surrogate JSON parse | 548.97 | — | — | 8839.17 (16.10x) | 2012.13 (3.67x) |
| Value KeySurrogate JSON parse | 544.17 | — | — | 10241.70 (18.82x) | 2075.66 (3.81x) |
| NullValue JSON stringify | 54.44 | — | — | 1979.13 (36.35x) | 393.87 (7.23x) |
| NullValue JSON parse | 82.74 | — | — | 3168.54 (38.30x) | 357.16 (4.32x) |
| StringScalarValue JSON stringify | 71.15 | — | — | 1792.68 (25.20x) | 306.18 (4.30x) |
| StringScalarValue JSON parse | 160.87 | — | — | 2716.03 (16.88x) | 420.25 (2.61x) |
| StringScalarValue Escape JSON parse | 150.42 | — | — | 2580.94 (17.16x) | 544.14 (3.62x) |
| StringScalarValue Surrogate JSON parse | 192.75 | — | — | 2781.63 (14.43x) | 498.16 (2.58x) |
| EmptyStringScalarValue JSON stringify | 65.43 | — | — | 2031.50 (31.05x) | 474.94 (7.26x) |
| EmptyStringScalarValue JSON parse | 87.32 | — | — | 2654.68 (30.40x) | 436.59 (5.00x) |
| NumberValue JSON stringify | 122.17 | — | — | 1962.71 (16.07x) | 360.85 (2.95x) |
| NumberValue JSON parse | 141.43 | — | — | 2716.94 (19.21x) | 430.53 (3.04x) |
| NumberValue Exponent JSON parse | 151.19 | — | — | 2704.39 (17.89x) | 449.16 (2.97x) |
| NegativeNumberValue JSON stringify | 140.76 | — | — | 1928.97 (13.70x) | 480.21 (3.41x) |
| NegativeNumberValue JSON parse | 157.89 | — | — | 2606.85 (16.51x) | 444.06 (2.81x) |
| ZeroNumberValue JSON stringify | 50.98 | — | — | 1896.02 (37.19x) | 478.94 (9.39x) |
| ZeroNumberValue JSON parse | 129.47 | — | — | 2471.77 (19.09x) | 391.82 (3.03x) |
| BoolScalarValue JSON stringify | 40.42 | — | — | 1658.68 (41.04x) | 401.38 (9.93x) |
| BoolScalarValue JSON parse | 69.67 | — | — | 2455.77 (35.25x) | 355.47 (5.10x) |
| FalseBoolScalarValue JSON stringify | 40.54 | — | — | 1666.71 (41.11x) | 374.02 (9.23x) |
| FalseBoolScalarValue JSON parse | 70.28 | — | — | 2733.42 (38.89x) | 303.00 (4.31x) |
| ListKindValue JSON stringify | 140.49 | — | — | 7578.51 (53.94x) | 3238.60 (23.05x) |
| ListKindValue JSON parse | 668.25 | — | — | 12973.60 (19.41x) | 5652.45 (8.46x) |
| ListKindValue Escape JSON parse | 692.06 | — | — | 13071.20 (18.89x) | 5839.14 (8.44x) |
| ListKindValue Surrogate JSON parse | 318.65 | — | — | 6518.08 (20.46x) | 1512.61 (4.75x) |
| EmptyStructKindValue JSON stringify | 42.99 | — | — | 2344.03 (54.53x) | 616.86 (14.35x) |
| EmptyStructKindValue JSON parse | 110.38 | — | — | 4693.57 (42.52x) | 856.85 (7.76x) |
| EmptyListKindValue JSON stringify | 41.37 | — | — | 2382.57 (57.59x) | 454.89 (11.00x) |
| EmptyListKindValue JSON parse | 146.19 | — | — | 4846.24 (33.15x) | 728.02 (4.98x) |
| ListValue JSON stringify | 144.58 | — | — | 5944.11 (41.11x) | 2824.13 (19.53x) |
| ListValue JSON parse | 771.10 | — | — | 13225.20 (17.15x) | 5089.30 (6.60x) |
| ListValue Escape JSON parse | 836.61 | — | — | 13369.80 (15.98x) | 5356.43 (6.40x) |
| ListValue Surrogate JSON parse | 332.98 | — | — | 3976.82 (11.94x) | 1094.36 (3.29x) |
| EmptyListValue JSON stringify | 51.02 | — | — | 716.71 (14.05x) | 201.73 (3.95x) |
| EmptyListValue JSON parse | 153.56 | — | — | 2627.03 (17.11x) | 350.14 (2.28x) |
| DoubleValue JSON stringify | 68.37 | — | — | 868.95 (12.71x) | 261.27 (3.82x) |
| DoubleValue JSON parse | 123.25 | — | — | 1401.42 (11.37x) | 298.76 (2.42x) |
| DoubleValue String JSON parse | 136.92 | — | — | 1800.04 (13.15x) | 373.81 (2.73x) |
| DoubleValue Exponent JSON parse | 142.92 | — | — | 2324.68 (16.27x) | 393.87 (2.76x) |
| NegativeDoubleValue JSON stringify | 67.54 | — | — | 1562.14 (23.13x) | 209.93 (3.11x) |
| NegativeDoubleValue JSON parse | 111.89 | — | — | 3194.15 (28.55x) | 319.82 (2.86x) |
| ZeroDoubleValue JSON stringify | 47.48 | — | — | 1675.11 (35.28x) | 188.30 (3.97x) |
| ZeroDoubleValue JSON parse | 108.93 | — | — | 2977.17 (27.33x) | 260.98 (2.40x) |
| DoubleValue NaN JSON stringify | 46.13 | — | — | 1253.62 (27.18x) | 193.03 (4.18x) |
| DoubleValue NaN JSON parse | 104.80 | — | — | 2189.88 (20.90x) | 279.42 (2.67x) |
| DoubleValue Infinity JSON stringify | 47.91 | — | — | 1284.66 (26.81x) | 156.06 (3.26x) |
| DoubleValue Infinity JSON parse | 105.63 | — | — | 2015.29 (19.08x) | 288.29 (2.73x) |
| DoubleValue NegativeInfinity JSON stringify | 48.09 | — | — | 713.02 (14.83x) | 124.57 (2.59x) |
| DoubleValue NegativeInfinity JSON parse | 107.58 | — | — | 1597.36 (14.85x) | 321.05 (2.98x) |
| FloatValue JSON stringify | 71.09 | — | — | 1613.46 (22.70x) | 205.08 (2.88x) |
| FloatValue JSON parse | 110.67 | — | — | 2040.02 (18.43x) | 327.30 (2.96x) |
| FloatValue String JSON parse | 110.37 | — | — | 2348.22 (21.28x) | 409.87 (3.71x) |
| FloatValue Exponent JSON parse | 112.40 | — | — | 2511.03 (22.34x) | 284.66 (2.53x) |
| NegativeFloatValue JSON stringify | 71.79 | — | — | 1700.35 (23.69x) | 201.33 (2.80x) |
| NegativeFloatValue JSON parse | 110.86 | — | — | 2627.11 (23.70x) | 330.01 (2.98x) |
| ZeroFloatValue JSON stringify | 47.56 | — | — | 1650.55 (34.70x) | 174.27 (3.66x) |
| ZeroFloatValue JSON parse | 108.24 | — | — | 1727.47 (15.96x) | 308.60 (2.85x) |
| FloatValue NaN JSON stringify | 46.45 | — | — | 1072.41 (23.09x) | 132.57 (2.85x) |
| FloatValue NaN JSON parse | 105.04 | — | — | 2107.76 (20.07x) | 249.53 (2.38x) |
| FloatValue Infinity JSON stringify | 47.84 | — | — | 1209.03 (25.27x) | 118.38 (2.47x) |
| FloatValue Infinity JSON parse | 106.05 | — | — | 1723.70 (16.25x) | 340.18 (3.21x) |
| FloatValue NegativeInfinity JSON stringify | 48.13 | — | — | 1158.83 (24.08x) | 186.46 (3.87x) |
| FloatValue NegativeInfinity JSON parse | 108.11 | — | — | 2039.72 (18.87x) | 330.11 (3.05x) |
| Int64Value JSON stringify | 50.28 | — | — | 835.90 (16.62x) | 293.93 (5.85x) |
| Int64Value JSON parse | 125.10 | — | — | 2265.95 (18.11x) | 575.52 (4.60x) |
| Int64Value Number JSON parse | 127.12 | — | — | 2436.86 (19.17x) | 407.86 (3.21x) |
| Int64Value Exponent JSON parse | 117.74 | — | — | 1390.06 (11.81x) | 403.35 (3.43x) |
| ZeroInt64Value JSON stringify | 41.21 | — | — | 656.64 (15.93x) | 279.79 (6.79x) |
| ZeroInt64Value JSON parse | 107.21 | — | — | 1275.01 (11.89x) | 374.09 (3.49x) |
| NegativeInt64Value JSON stringify | 49.93 | — | — | 671.22 (13.44x) | 280.13 (5.61x) |
| NegativeInt64Value JSON parse | 126.43 | — | — | 1870.16 (14.79x) | 711.25 (5.63x) |
| MinInt64Value JSON stringify | 49.31 | — | — | 813.43 (16.50x) | 281.48 (5.71x) |
| MinInt64Value JSON parse | 134.42 | — | — | 1535.32 (11.42x) | 727.88 (5.41x) |
| MaxInt64Value JSON stringify | 49.26 | — | — | 788.39 (16.00x) | 312.78 (6.35x) |
| MaxInt64Value JSON parse | 133.64 | — | — | 2254.59 (16.87x) | 534.78 (4.00x) |
| UInt64Value JSON stringify | 49.81 | — | — | 670.11 (13.45x) | 271.02 (5.44x) |
| UInt64Value JSON parse | 127.19 | — | — | 1544.31 (12.14x) | 522.18 (4.11x) |
| UInt64Value Number JSON parse | 129.28 | — | — | 1721.72 (13.32x) | 336.95 (2.61x) |
| UInt64Value Exponent JSON parse | 154.36 | — | — | 1359.25 (8.81x) | 401.10 (2.60x) |
| ZeroUInt64Value JSON stringify | 55.41 | — | — | 608.34 (10.98x) | 189.34 (3.42x) |
| ZeroUInt64Value JSON parse | 128.42 | — | — | 1329.84 (10.36x) | 400.47 (3.12x) |
| MaxUInt64Value JSON stringify | 67.88 | — | — | 673.26 (9.92x) | 303.38 (4.47x) |
| MaxUInt64Value JSON parse | 208.88 | — | — | 2203.42 (10.55x) | 506.78 (2.43x) |
| Int32Value JSON stringify | 63.89 | — | — | 629.30 (9.85x) | 148.90 (2.33x) |
| Int32Value JSON parse | 163.44 | — | — | 1357.10 (8.30x) | 354.29 (2.17x) |
| Int32Value String JSON parse | 166.66 | — | — | 1151.35 (6.91x) | 427.49 (2.57x) |
| Int32Value Exponent JSON parse | 176.30 | — | — | 1707.84 (9.69x) | 373.13 (2.12x) |
| ZeroInt32Value JSON stringify | 62.98 | — | — | 1013.16 (16.09x) | 140.58 (2.23x) |
| ZeroInt32Value JSON parse | 152.71 | — | — | 1884.41 (12.34x) | 278.49 (1.82x) |
| NegativeInt32Value JSON stringify | 63.80 | — | — | 640.68 (10.04x) | 152.10 (2.38x) |
| NegativeInt32Value JSON parse | 134.16 | — | — | 1383.33 (10.31x) | 348.50 (2.60x) |
| MinInt32Value JSON stringify | 63.64 | — | — | 640.22 (10.06x) | 176.98 (2.78x) |
| MinInt32Value JSON parse | 182.31 | — | — | 1323.46 (7.26x) | 393.64 (2.16x) |
| MaxInt32Value JSON stringify | 63.18 | — | — | 720.31 (11.40x) | 148.52 (2.35x) |
| MaxInt32Value JSON parse | 149.72 | — | — | 1349.06 (9.01x) | 357.57 (2.39x) |
| UInt32Value JSON stringify | 62.24 | — | — | 818.51 (13.15x) | 143.00 (2.30x) |
| UInt32Value JSON parse | 159.64 | — | — | 1489.82 (9.33x) | 385.59 (2.42x) |
| UInt32Value String JSON parse | 138.39 | — | — | 1324.14 (9.57x) | 437.40 (3.16x) |
| UInt32Value Exponent JSON parse | 168.24 | — | — | 1612.22 (9.58x) | 379.14 (2.25x) |
| ZeroUInt32Value JSON stringify | 61.12 | — | — | 624.60 (10.22x) | 157.39 (2.58x) |
| ZeroUInt32Value JSON parse | 150.87 | — | — | 1444.03 (9.57x) | 270.01 (1.79x) |
| MaxUInt32Value JSON stringify | 62.95 | — | — | 640.46 (10.17x) | 167.70 (2.66x) |
| MaxUInt32Value JSON parse | 137.57 | — | — | 1365.97 (9.93x) | 376.63 (2.74x) |
| BoolValue JSON stringify | 45.36 | — | — | 609.20 (13.43x) | 199.35 (4.39x) |
| BoolValue JSON parse | 59.99 | — | — | 1112.90 (18.55x) | 214.51 (3.58x) |
| FalseBoolValue JSON stringify | 45.04 | — | — | 616.62 (13.69x) | 157.72 (3.50x) |
| FalseBoolValue JSON parse | 60.42 | — | — | 1141.79 (18.90x) | 289.70 (4.79x) |
| StringValue JSON stringify | 51.93 | — | — | 672.18 (12.94x) | 196.46 (3.78x) |
| StringValue JSON parse | 121.18 | — | — | 1546.41 (12.76x) | 325.33 (2.68x) |
| StringValue Escape JSON parse | 130.05 | — | — | 1232.33 (9.48x) | 425.72 (3.27x) |
| StringValue Surrogate JSON parse | 127.56 | — | — | 1998.16 (15.66x) | 407.43 (3.19x) |
| EmptyStringValue JSON stringify | 49.07 | — | — | 681.34 (13.89x) | 207.42 (4.23x) |
| EmptyStringValue JSON parse | 66.20 | — | — | 1271.34 (19.20x) | 277.30 (4.19x) |
| BytesValue JSON stringify | 49.28 | — | — | 660.08 (13.39x) | 211.96 (4.30x) |
| BytesValue JSON parse | 126.31 | — | — | 1936.54 (15.33x) | 410.79 (3.25x) |
| BytesValue URL JSON parse | 142.35 | — | — | 1308.10 (9.19x) | 310.60 (2.18x) |
| BytesValue StandardBase64 JSON parse | 126.10 | — | — | 1547.17 (12.27x) | 322.75 (2.56x) |
| BytesValue Unpadded JSON parse | 124.81 | — | — | 1181.82 (9.47x) | 416.08 (3.33x) |
| EmptyBytesValue JSON stringify | 40.91 | — | — | 635.97 (15.55x) | 192.17 (4.70x) |
| EmptyBytesValue JSON parse | 68.70 | — | — | 1258.86 (18.32x) | 318.10 (4.63x) |
| TextFormat format | 172.54 | — | — | 3133.86 (18.16x) | 2882.32 (16.71x) |
| TextFormat parse | 741.86 | — | — | 6016.41 (8.11x) | 8210.52 (11.07x) |
| packed fixed32 encode | 2.70 | 594.02 (220.01x) | 544.82 (201.79x) | 98.33 (36.42x) | 414.09 (153.37x) |
| packed fixed32 decode | 4.79 | 1271.44 (265.44x) | 2584.40 (539.54x) | 104.11 (21.74x) | 2312.85 (482.85x) |
| packed fixed64 encode | 2.78 | 666.60 (239.78x) | 681.98 (245.32x) | 94.93 (34.15x) | 432.02 (155.40x) |
| packed fixed64 decode | 4.53 | 1268.82 (280.09x) | 8221.18 (1814.83x) | 169.88 (37.50x) | 3652.07 (806.20x) |
| packed sfixed32 encode | 2.01 | 567.55 (282.36x) | 677.63 (337.13x) | 54.89 (27.31x) | 424.40 (211.14x) |
| packed sfixed32 decode | 4.52 | 1347.72 (298.17x) | 2355.28 (521.08x) | 55.42 (12.26x) | 2381.94 (526.98x) |
| packed sfixed64 encode | 2.37 | 650.02 (274.27x) | 566.91 (239.20x) | 75.84 (32.00x) | 398.59 (168.18x) |
| packed sfixed64 decode | 7.47 | 1170.98 (156.76x) | 8384.91 (1122.48x) | 79.53 (10.65x) | 3249.81 (435.05x) |
| packed float encode | 2.76 | 844.04 (305.81x) | 547.76 (198.46x) | 57.49 (20.83x) | 541.78 (196.30x) |
| packed float decode | 4.53 | 1223.29 (270.04x) | 2422.55 (534.78x) | 56.72 (12.52x) | 2382.43 (525.92x) |
| packed double encode | 2.06 | 882.98 (428.63x) | 622.31 (302.09x) | 75.97 (36.88x) | 359.13 (174.33x) |
| packed double decode | 4.66 | 1526.84 (327.65x) | 2502.97 (537.12x) | 79.48 (17.06x) | 3673.45 (788.29x) |
| packed uint64 encode | 2509.54 | 5888.21 (2.35x) | 5657.73 (2.25x) | 2615.24 (1.04x) | 5031.88 (2.01x) |
| packed uint64 decode | 1784.22 | 4144.76 (2.32x) | 9928.85 (5.56x) | 3441.24 (1.93x) | 11545.86 (6.47x) |
| packed uint32 encode | 990.11 | 4781.64 (4.83x) | 4115.29 (4.16x) | 2204.96 (2.23x) | 3717.97 (3.76x) |
| packed uint32 decode | 1328.72 | 3432.63 (2.58x) | 4361.35 (3.28x) | 2437.68 (1.83x) | 8094.02 (6.09x) |
| packed int64 encode | 1413.52 | 13048.98 (9.23x) | 8111.48 (5.74x) | 3711.83 (2.63x) | 5490.04 (3.88x) |
| packed int64 decode | 3661.09 | 4585.57 (1.25x) | 11649.54 (3.18x) | 5583.57 (1.53x) | 13485.83 (3.68x) |
| packed sint32 encode | 792.26 | 4143.71 (5.23x) | 3709.20 (4.68x) | 1899.38 (2.40x) | 4337.51 (5.47x) |
| packed sint32 decode | 1016.16 | 3305.24 (3.25x) | 4601.50 (4.53x) | 1434.42 (1.41x) | 5404.72 (5.32x) |
| packed sint64 encode | 1416.53 | 6465.82 (4.56x) | 6058.02 (4.28x) | 2903.97 (2.05x) | 5230.40 (3.69x) |
| packed sint64 decode | 2037.18 | 3845.32 (1.89x) | 10848.02 (5.33x) | 3958.26 (1.94x) | 11875.16 (5.83x) |
| packed bool encode | 2.01 | 1718.70 (855.07x) | 597.85 (297.44x) | 25.84 (12.86x) | 2874.99 (1430.34x) |
| packed bool decode | 315.81 | 1934.34 (6.13x) | 3220.34 (10.20x) | 822.33 (2.60x) | 2126.52 (6.73x) |
| packed enum encode | 272.19 | 3392.17 (12.46x) | 2051.97 (7.54x) | 1180.20 (4.34x) | 3018.50 (11.09x) |
| packed enum decode | 174.68 | 1887.98 (10.81x) | 4267.45 (24.43x) | 706.12 (4.04x) | 2743.28 (15.70x) |
| large map encode | 4223.08 | 17874.97 (4.23x) | 15094.97 (3.57x) | 23881.50 (5.65x) | 232675.32 (55.10x) |
| shuffled large map deterministic binary encode | 33470.17 | — | — | 113725.00 (3.40x) | 452746.10 (13.53x) |
| large map decode | 29090.37 | 113510.29 (3.90x) | 116039.62 (3.99x) | 113995.00 (3.92x) | 354636.25 (12.19x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON (including generated `map<string, int32>` surrogate-pair key parse, null-field parse, enum-name parse, open-enum numeric parse, and integer numeric-exponent parse), Any/WKT JSON (including embedded zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound `Duration`, non-empty/escaped-input parse/number-exponent parse/surrogate-pair value parse/surrogate-pair key parse and empty `Struct`, object/escaped-object parse/object-number-exponent/object-surrogate-pair value parse/object-surrogate-pair key parse/list/escaped-list/surrogate-list/string-scalar/escaped-string-scalar/surrogate-string-scalar/number-exponent/negative-number `Value` (including default-like scalar and empty object/list kinds),
`FieldMask` (non-empty, escaped JSON parse input, and empty), escaped-input parse/short-fraction parse/micro/nano/offset/min/pre/post/max-bound `Timestamp`, `Empty`, min/zero/positive/number-input parse/numeric-exponent parse/negative/max `Int64Value`, negative/zero/positive finite/string-input parse/numeric-exponent parse `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), negative/zero/positive finite/string-input parse/numeric-exponent parse `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), zero/normal/number-input parse/numeric-exponent parse/max `UInt64Value`, min/zero/positive/string-input parse/numeric-exponent parse/negative/max `Int32Value`, zero/normal/string-input parse/numeric-exponent parse/max `UInt32Value`, true/false `BoolValue`, non-empty/escape-input parse/surrogate-pair parse/empty `StringValue`, padded-standard/base64url/unpadded-base64 parse/empty `BytesValue`, and recursive nested `Any` payloads), direct zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound Duration, non-empty/escaped-input parse/empty FieldMask, and escaped-input parse/short-fraction parse/micro/nano/offset/min/pre/post/max-bound Timestamp WKT JSON plus other direct WKT JSON, including non-empty/escaped-input parse/number-exponent parse/surrogate-pair value parse/surrogate-pair key parse/empty `Struct`, object/escaped-object parse/object-number-exponent/object-surrogate-pair value parse/object-surrogate-pair key parse/list/escaped-list/surrogate-list/string-scalar/escaped-string-scalar/surrogate-string-scalar/number-exponent/negative-number `Value`, and escaped/surrogate-pair/non-empty/empty `ListValue`, TextFormat, packed scalars, large bytes,
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
