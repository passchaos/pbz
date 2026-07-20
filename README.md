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

Latest accepted comparison (`/tmp/pbz-compare-open-enum-json-final.log`,
summarized in `/tmp/pbz-summary-open-enum-json-final.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 29.42 | 98.05 (3.33x) | 49.59 (1.69x) | 112.04 (3.81x) | 830.93 (28.24x) |
| binary decode | 90.98 | 328.01 (3.61x) | 226.00 (2.48x) | 292.78 (3.22x) | 1151.48 (12.66x) |
| unknown fields count by number | 3.58 | — | — | 240.79 (67.26x) | — |
| deterministic binary encode | 53.56 | — | — | 181.48 (3.39x) | 1144.08 (21.36x) |
| scalarmix encode | 21.07 | 102.54 (4.87x) | 72.26 (3.43x) | 28.68 (1.36x) | 204.73 (9.72x) |
| scalarmix decode | 32.13 | 138.47 (4.31x) | 190.03 (5.91x) | 91.04 (2.83x) | 315.37 (9.82x) |
| textbytes encode | 17.10 | 81.64 (4.77x) | 33.79 (1.98x) | 118.40 (6.92x) | 145.65 (8.52x) |
| textbytes decode | 61.29 | 380.53 (6.21x) | 238.29 (3.89x) | 202.50 (3.30x) | 683.63 (11.15x) |
| largebytes encode | 24.12 | 2918.29 (120.99x) | 2825.33 (117.14x) | 2736.38 (113.45x) | 3729.53 (154.62x) |
| largebytes decode | 116.31 | 6151.53 (52.89x) | 3254.09 (27.98x) | 2824.87 (24.29x) | 35439.56 (304.70x) |
| presencemix encode | 17.24 | 80.07 (4.64x) | 47.29 (2.74x) | 54.65 (3.17x) | 234.74 (13.62x) |
| presencemix decode | 61.11 | 168.02 (2.75x) | 132.01 (2.16x) | 189.50 (3.10x) | 507.62 (8.31x) |
| complex encode | 57.57 | 149.54 (2.60x) | 96.28 (1.67x) | 161.41 (2.80x) | 954.34 (16.58x) |
| complex decode | 170.91 | 436.79 (2.56x) | 343.50 (2.01x) | 391.53 (2.29x) | 1731.81 (10.13x) |
| complex deterministic binary encode | 128.32 | — | — | 191.97 (1.50x) | 1249.09 (9.73x) |
| complex JSON stringify | 486.40 | — | — | 6057.19 (12.45x) | 7809.76 (16.06x) |
| complex JSON parse | 2439.48 | — | — | 15015.30 (6.16x) | 9409.79 (3.86x) |
| complex TextFormat format | 241.85 | — | — | 4814.72 (19.91x) | 6824.37 (28.22x) |
| complex TextFormat parse | 1879.94 | — | — | 8809.88 (4.69x) | 11064.59 (5.89x) |
| packed int32 encode | 709.64 | 3912.54 (5.51x) | 3020.65 (4.26x) | 1656.52 (2.33x) | 3620.36 (5.10x) |
| packed int32 decode | 764.76 | 2346.31 (3.07x) | 3761.38 (4.92x) | 1054.18 (1.38x) | 4756.52 (6.22x) |
| JSON stringify | 239.46 | — | — | 3826.67 (15.98x) | 2634.60 (11.00x) |
| JSON parse | 1914.17 | — | — | 9184.79 (4.80x) | 5371.00 (2.81x) |
| MapKeySurrogate JSON parse | 461.16 | — | — | 4283.84 (9.29x) | 1268.83 (2.75x) |
| NullFields JSON parse | 527.26 | — | — | 2428.37 (4.61x) | 794.23 (1.51x) |
| OpenEnum JSON parse | 311.44 | — | — | 4400.54 (14.13x) | 532.39 (1.71x) |
| IntExponent JSON parse | 2467.50 | — | — | 8858.07 (3.59x) | 5297.94 (2.15x) |
| Any WKT JSON stringify | 127.16 | — | — | 2548.66 (20.04x) | 1009.62 (7.94x) |
| Any WKT JSON parse | 533.13 | — | — | 3730.54 (7.00x) | 1749.92 (3.28x) |
| Any Duration Escape WKT JSON parse | 839.67 | — | — | 4036.00 (4.81x) | 2165.27 (2.58x) |
| Any PlusDuration WKT JSON parse | 864.74 | — | — | 3853.35 (4.46x) | 1963.55 (2.27x) |
| Any ShortFractionDuration WKT JSON parse | 599.95 | — | — | 3665.94 (6.11x) | 2013.74 (3.36x) |
| Any MicroDuration WKT JSON stringify | 192.64 | — | — | 2400.81 (12.46x) | 1323.28 (6.87x) |
| Any MicroDuration WKT JSON parse | 622.14 | — | — | 3826.73 (6.15x) | 2114.20 (3.40x) |
| Any NanoDuration WKT JSON stringify | 135.89 | — | — | 2357.44 (17.35x) | 1552.81 (11.43x) |
| Any NanoDuration WKT JSON parse | 551.56 | — | — | 3727.91 (6.76x) | 2062.99 (3.74x) |
| Any NegativeDuration WKT JSON stringify | 132.15 | — | — | 2358.25 (17.85x) | 1204.35 (9.11x) |
| Any NegativeDuration WKT JSON parse | 550.47 | — | — | 3790.31 (6.89x) | 2028.21 (3.68x) |
| Any FractionalNegativeDuration WKT JSON stringify | 123.74 | — | — | 2395.95 (19.36x) | 1269.72 (10.26x) |
| Any FractionalNegativeDuration WKT JSON parse | 542.66 | — | — | 4042.28 (7.45x) | 1910.15 (3.52x) |
| Any MaxDuration WKT JSON stringify | 118.73 | — | — | 2168.25 (18.26x) | 1239.76 (10.44x) |
| Any MaxDuration WKT JSON parse | 682.40 | — | — | 3896.88 (5.71x) | 2126.60 (3.12x) |
| Any MinDuration WKT JSON stringify | 234.83 | — | — | 2169.89 (9.24x) | 1063.14 (4.53x) |
| Any MinDuration WKT JSON parse | 832.75 | — | — | 3736.87 (4.49x) | 2048.38 (2.46x) |
| Any ZeroDuration WKT JSON stringify | 145.57 | — | — | 998.51 (6.86x) | 1076.72 (7.40x) |
| Any ZeroDuration WKT JSON parse | 567.75 | — | — | 2732.07 (4.81x) | 2049.59 (3.61x) |
| Any FieldMask WKT JSON stringify | 312.32 | — | — | 2207.97 (7.07x) | 1884.31 (6.03x) |
| Any FieldMask WKT JSON parse | 856.65 | — | — | 3835.15 (4.48x) | 2754.65 (3.22x) |
| Any FieldMask Escape WKT JSON parse | 776.99 | — | — | 3920.89 (5.05x) | 3244.53 (4.18x) |
| Any EmptyFieldMask WKT JSON stringify | 110.02 | — | — | 1158.20 (10.53x) | 784.90 (7.13x) |
| Any EmptyFieldMask WKT JSON parse | 459.15 | — | — | 2555.29 (5.57x) | 1784.29 (3.89x) |
| Any Timestamp WKT JSON stringify | 179.97 | — | — | 2466.25 (13.70x) | 1349.20 (7.50x) |
| Any Timestamp WKT JSON parse | 996.86 | — | — | 3727.90 (3.74x) | 2192.20 (2.20x) |
| Any Timestamp Escape WKT JSON parse | 861.59 | — | — | 3801.30 (4.41x) | 2438.10 (2.83x) |
| Any ShortFraction Timestamp WKT JSON parse | 587.45 | — | — | 3744.22 (6.37x) | 1914.80 (3.26x) |
| Any Micro Timestamp WKT JSON stringify | 180.23 | — | — | 2530.62 (14.04x) | 1246.02 (6.91x) |
| Any Micro Timestamp WKT JSON parse | 597.43 | — | — | 3859.82 (6.46x) | 2189.17 (3.66x) |
| Any Nano Timestamp WKT JSON stringify | 175.26 | — | — | 2825.62 (16.12x) | 1092.76 (6.24x) |
| Any Nano Timestamp WKT JSON parse | 584.18 | — | — | 4007.31 (6.86x) | 1907.48 (3.27x) |
| Any Offset Timestamp WKT JSON parse | 594.33 | — | — | 4095.81 (6.89x) | 2150.35 (3.62x) |
| Any PreEpoch Timestamp WKT JSON stringify | 141.75 | — | — | 2521.16 (17.79x) | 1159.95 (8.18x) |
| Any PreEpoch Timestamp WKT JSON parse | 938.17 | — | — | 3796.52 (4.05x) | 2058.78 (2.19x) |
| Any Max Timestamp WKT JSON stringify | 330.86 | — | — | 2533.06 (7.66x) | 1155.58 (3.49x) |
| Any Max Timestamp WKT JSON parse | 741.40 | — | — | 3793.12 (5.12x) | 2067.30 (2.79x) |
| Any Min Timestamp WKT JSON stringify | 160.42 | — | — | 2326.66 (14.50x) | 1114.24 (6.95x) |
| Any Min Timestamp WKT JSON parse | 566.22 | — | — | 3809.25 (6.73x) | 1893.24 (3.34x) |
| Any Empty WKT JSON stringify | 90.49 | — | — | 1110.27 (12.27x) | 627.98 (6.94x) |
| Any Empty WKT JSON parse | 334.17 | — | — | 2625.68 (7.86x) | 1464.20 (4.38x) |
| Any Struct WKT JSON stringify | 621.95 | — | — | 7592.65 (12.21x) | 8370.61 (13.46x) |
| Any Struct WKT JSON parse | 1747.89 | — | — | 13613.40 (7.79x) | 11428.58 (6.54x) |
| Any Struct Escape WKT JSON parse | 1842.43 | — | — | 13785.50 (7.48x) | 11497.57 (6.24x) |
| Any Struct NumberExponent WKT JSON parse | 1757.92 | — | — | 13603.50 (7.74x) | 11642.07 (6.62x) |
| Any Struct Surrogate WKT JSON parse | 1282.92 | — | — | 7730.45 (6.03x) | 4346.19 (3.39x) |
| Any Struct KeySurrogate WKT JSON parse | 1101.42 | — | — | 7614.06 (6.91x) | 4174.77 (3.79x) |
| Any EmptyStruct WKT JSON stringify | 188.31 | — | — | 962.89 (5.11x) | 1351.62 (7.18x) |
| Any EmptyStruct WKT JSON parse | 441.48 | — | — | 2697.41 (6.11x) | 2028.19 (4.59x) |
| Any Value WKT JSON stringify | 641.70 | — | — | 7164.28 (11.16x) | 8494.58 (13.24x) |
| Any Value WKT JSON parse | 1812.15 | — | — | 14221.70 (7.85x) | 11379.36 (6.28x) |
| Any Value Escape WKT JSON parse | 2635.19 | — | — | 13819.40 (5.24x) | 12593.35 (4.78x) |
| Any Value NumberExponent WKT JSON parse | 1812.06 | — | — | 13782.60 (7.61x) | 12071.20 (6.66x) |
| Any Value Surrogate WKT JSON parse | 828.54 | — | — | 7899.31 (9.53x) | 4799.18 (5.79x) |
| Any Value KeySurrogate WKT JSON parse | 1371.67 | — | — | 8110.04 (5.91x) | 5008.88 (3.65x) |
| Any NullValue WKT JSON stringify | 132.60 | — | — | 2931.73 (22.11x) | 1105.55 (8.34x) |
| Any NullValue WKT JSON parse | 650.82 | — | — | 4849.27 (7.45x) | 2260.86 (3.47x) |
| Any StringScalarValue WKT JSON stringify | 181.59 | — | — | 2720.08 (14.98x) | 1332.26 (7.34x) |
| Any StringScalarValue WKT JSON parse | 607.03 | — | — | 4645.82 (7.65x) | 2090.04 (3.44x) |
| Any StringScalarValue Escape WKT JSON parse | 534.55 | — | — | 4429.43 (8.29x) | 2236.40 (4.18x) |
| Any StringScalarValue Surrogate WKT JSON parse | 536.85 | — | — | 4454.56 (8.30x) | 2366.43 (4.41x) |
| Any EmptyStringScalarValue WKT JSON stringify | 134.25 | — | — | 2620.30 (19.52x) | 1100.62 (8.20x) |
| Any EmptyStringScalarValue WKT JSON parse | 486.13 | — | — | 4624.59 (9.51x) | 1887.43 (3.88x) |
| Any NumberValue WKT JSON stringify | 323.97 | — | — | 3073.24 (9.49x) | 1194.55 (3.69x) |
| Any NumberValue WKT JSON parse | 827.98 | — | — | 4393.84 (5.31x) | 2213.12 (2.67x) |
| Any NumberValue Exponent WKT JSON parse | 739.71 | — | — | 4338.61 (5.87x) | 2080.59 (2.81x) |
| Any NegativeNumberValue WKT JSON stringify | 279.60 | — | — | 3196.15 (11.43x) | 1189.18 (4.25x) |
| Any NegativeNumberValue WKT JSON parse | 634.87 | — | — | 4761.83 (7.50x) | 2087.54 (3.29x) |
| Any ZeroNumberValue WKT JSON stringify | 229.93 | — | — | 3187.40 (13.86x) | 1044.18 (4.54x) |
| Any ZeroNumberValue WKT JSON parse | 508.87 | — | — | 4632.86 (9.10x) | 2147.44 (4.22x) |
| Any BoolScalarValue WKT JSON stringify | 119.76 | — | — | 2787.02 (23.27x) | 1406.80 (11.75x) |
| Any BoolScalarValue WKT JSON parse | 471.13 | — | — | 4320.82 (9.17x) | 2075.43 (4.41x) |
| Any FalseBoolScalarValue WKT JSON stringify | 122.47 | — | — | 2863.91 (23.38x) | 1372.53 (11.21x) |
| Any FalseBoolScalarValue WKT JSON parse | 468.51 | — | — | 4513.71 (9.63x) | 2154.01 (4.60x) |
| Any ListKindValue WKT JSON stringify | 499.48 | — | — | 7166.42 (14.35x) | 6724.31 (13.46x) |
| Any ListKindValue WKT JSON parse | 1949.62 | — | — | 12798.40 (6.56x) | 9496.36 (4.87x) |
| Any ListKindValue Escape WKT JSON parse | 1821.18 | — | — | 13472.80 (7.40x) | 10077.50 (5.53x) |
| Any ListKindValue Surrogate WKT JSON parse | 746.79 | — | — | 5980.46 (8.01x) | 3554.95 (4.76x) |
| Any EmptyStructKindValue WKT JSON stringify | 145.02 | — | — | 3661.30 (25.25x) | 1492.78 (10.29x) |
| Any EmptyStructKindValue WKT JSON parse | 512.53 | — | — | 6445.82 (12.58x) | 2523.70 (4.92x) |
| Any EmptyListKindValue WKT JSON stringify | 242.64 | — | — | 3610.72 (14.88x) | 1740.47 (7.17x) |
| Any EmptyListKindValue WKT JSON parse | 841.92 | — | — | 5569.58 (6.62x) | 2567.58 (3.05x) |
| Any DoubleValue WKT JSON stringify | 337.53 | — | — | 2227.03 (6.60x) | 1016.12 (3.01x) |
| Any DoubleValue WKT JSON parse | 728.79 | — | — | 3393.13 (4.66x) | 1825.27 (2.50x) |
| Any DoubleValue String WKT JSON parse | 664.53 | — | — | 3769.10 (5.67x) | 2111.29 (3.18x) |
| Any DoubleValue Exponent WKT JSON parse | 656.46 | — | — | 3370.73 (5.13x) | 1913.27 (2.91x) |
| Any NegativeDoubleValue WKT JSON stringify | 271.95 | — | — | 2173.74 (7.99x) | 925.83 (3.40x) |
| Any NegativeDoubleValue WKT JSON parse | 630.22 | — | — | 3429.79 (5.44x) | 1758.58 (2.79x) |
| Any ZeroDoubleValue WKT JSON stringify | 181.71 | — | — | 1005.42 (5.53x) | 901.64 (4.96x) |
| Any ZeroDoubleValue WKT JSON parse | 599.03 | — | — | 2655.53 (4.43x) | 1936.11 (3.23x) |
| Any DoubleValue NaN WKT JSON stringify | 253.98 | — | — | 1999.42 (7.87x) | 922.46 (3.63x) |
| Any DoubleValue NaN WKT JSON parse | 843.45 | — | — | 3293.66 (3.90x) | 1621.33 (1.92x) |
| Any DoubleValue Infinity WKT JSON stringify | 154.50 | — | — | 1908.62 (12.35x) | 830.99 (5.38x) |
| Any DoubleValue Infinity WKT JSON parse | 684.41 | — | — | 3323.85 (4.86x) | 1745.38 (2.55x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 218.84 | — | — | 1981.53 (9.05x) | 772.34 (3.53x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 538.04 | — | — | 3329.07 (6.19x) | 1849.37 (3.44x) |
| Any FloatValue WKT JSON stringify | 186.87 | — | — | 2185.73 (11.70x) | 981.20 (5.25x) |
| Any FloatValue WKT JSON parse | 543.03 | — | — | 3383.48 (6.23x) | 1953.13 (3.60x) |
| Any FloatValue String WKT JSON parse | 547.04 | — | — | 3395.33 (6.21x) | 1880.67 (3.44x) |
| Any FloatValue Exponent WKT JSON parse | 624.57 | — | — | 3552.67 (5.69x) | 1840.79 (2.95x) |
| Any NegativeFloatValue WKT JSON stringify | 261.82 | — | — | 2394.74 (9.15x) | 874.58 (3.34x) |
| Any NegativeFloatValue WKT JSON parse | 590.64 | — | — | 3713.05 (6.29x) | 2111.21 (3.57x) |
| Any ZeroFloatValue WKT JSON stringify | 198.28 | — | — | 1026.73 (5.18x) | 850.87 (4.29x) |
| Any ZeroFloatValue WKT JSON parse | 590.44 | — | — | 2486.15 (4.21x) | 1779.43 (3.01x) |
| Any FloatValue NaN WKT JSON stringify | 192.75 | — | — | 1906.73 (9.89x) | 1012.51 (5.25x) |
| Any FloatValue NaN WKT JSON parse | 600.41 | — | — | 3259.39 (5.43x) | 1758.17 (2.93x) |
| Any FloatValue Infinity WKT JSON stringify | 202.30 | — | — | 1914.94 (9.47x) | 781.90 (3.87x) |
| Any FloatValue Infinity WKT JSON parse | 670.98 | — | — | 3247.97 (4.84x) | 1695.09 (2.53x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 156.60 | — | — | 1890.96 (12.08x) | 761.52 (4.86x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 575.44 | — | — | 3286.37 (5.71x) | 1615.35 (2.81x) |
| Any Int64Value WKT JSON stringify | 164.88 | — | — | 1901.86 (11.53x) | 1003.86 (6.09x) |
| Any Int64Value WKT JSON parse | 574.53 | — | — | 3518.16 (6.12x) | 2286.04 (3.98x) |
| Any Int64Value Number WKT JSON parse | 569.71 | — | — | 3522.40 (6.18x) | 1787.51 (3.14x) |
| Any Int64Value Exponent WKT JSON parse | 551.53 | — | — | 3317.29 (6.01x) | 2077.92 (3.77x) |
| Any ZeroInt64Value WKT JSON stringify | 149.07 | — | — | 1432.02 (9.61x) | 1014.28 (6.80x) |
| Any ZeroInt64Value WKT JSON parse | 525.83 | — | — | 3896.61 (7.41x) | 1951.48 (3.71x) |
| Any NegativeInt64Value WKT JSON stringify | 162.41 | — | — | 4193.82 (25.82x) | 1212.76 (7.47x) |
| Any NegativeInt64Value WKT JSON parse | 916.38 | — | — | 4390.36 (4.79x) | 2168.77 (2.37x) |
| Any MinInt64Value WKT JSON stringify | 269.66 | — | — | 2282.71 (8.47x) | 902.79 (3.35x) |
| Any MinInt64Value WKT JSON parse | 698.16 | — | — | 4515.23 (6.47x) | 2103.28 (3.01x) |
| Any MaxInt64Value WKT JSON stringify | 223.85 | — | — | 2099.09 (9.38x) | 1013.09 (4.53x) |
| Any MaxInt64Value WKT JSON parse | 690.93 | — | — | 3494.47 (5.06x) | 2438.28 (3.53x) |
| Any UInt64Value WKT JSON stringify | 240.17 | — | — | 1945.40 (8.10x) | 1250.69 (5.21x) |
| Any UInt64Value WKT JSON parse | 691.41 | — | — | 3565.22 (5.16x) | 2181.70 (3.16x) |
| Any UInt64Value Number WKT JSON parse | 679.59 | — | — | 3544.07 (5.22x) | 2031.80 (2.99x) |
| Any UInt64Value Exponent WKT JSON parse | 636.91 | — | — | 3479.78 (5.46x) | 1911.25 (3.00x) |
| Any ZeroUInt64Value WKT JSON stringify | 202.17 | — | — | 1030.15 (5.10x) | 962.75 (4.76x) |
| Any ZeroUInt64Value WKT JSON parse | 605.16 | — | — | 2583.41 (4.27x) | 1917.92 (3.17x) |
| Any MaxUInt64Value WKT JSON stringify | 181.81 | — | — | 1950.81 (10.73x) | 999.97 (5.50x) |
| Any MaxUInt64Value WKT JSON parse | 975.36 | — | — | 3501.76 (3.59x) | 2026.18 (2.08x) |
| Any Int32Value WKT JSON stringify | 261.63 | — | — | 1809.30 (6.92x) | 856.67 (3.27x) |
| Any Int32Value WKT JSON parse | 653.86 | — | — | 3342.93 (5.11x) | 2018.09 (3.09x) |
| Any Int32Value String WKT JSON parse | 648.74 | — | — | 3366.79 (5.19x) | 1919.02 (2.96x) |
| Any Int32Value Exponent WKT JSON parse | 662.57 | — | — | 3359.42 (5.07x) | 1879.61 (2.84x) |
| Any ZeroInt32Value WKT JSON stringify | 220.93 | — | — | 1063.74 (4.81x) | 788.05 (3.57x) |
| Any ZeroInt32Value WKT JSON parse | 647.85 | — | — | 2589.28 (4.00x) | 1782.02 (2.75x) |
| Any NegativeInt32Value WKT JSON stringify | 221.02 | — | — | 1983.37 (8.97x) | 907.04 (4.10x) |
| Any NegativeInt32Value WKT JSON parse | 642.62 | — | — | 3361.61 (5.23x) | 1765.70 (2.75x) |
| Any MinInt32Value WKT JSON stringify | 216.50 | — | — | 1959.44 (9.05x) | 857.74 (3.96x) |
| Any MinInt32Value WKT JSON parse | 629.91 | — | — | 3403.98 (5.40x) | 1875.78 (2.98x) |
| Any MaxInt32Value WKT JSON stringify | 208.44 | — | — | 1928.30 (9.25x) | 800.65 (3.84x) |
| Any MaxInt32Value WKT JSON parse | 623.26 | — | — | 3065.36 (4.92x) | 1913.69 (3.07x) |
| Any UInt32Value WKT JSON stringify | 215.98 | — | — | 1957.95 (9.07x) | 836.02 (3.87x) |
| Any UInt32Value WKT JSON parse | 646.70 | — | — | 3325.98 (5.14x) | 1799.40 (2.78x) |
| Any UInt32Value String WKT JSON parse | 649.43 | — | — | 3749.90 (5.77x) | 1870.41 (2.88x) |
| Any UInt32Value Exponent WKT JSON parse | 637.89 | — | — | 3596.44 (5.64x) | 1973.45 (3.09x) |
| Any ZeroUInt32Value WKT JSON stringify | 171.65 | — | — | 1070.68 (6.24x) | 869.94 (5.07x) |
| Any ZeroUInt32Value WKT JSON parse | 552.64 | — | — | 2521.22 (4.56x) | 1693.69 (3.06x) |
| Any MaxUInt32Value WKT JSON stringify | 170.52 | — | — | 2052.32 (12.04x) | 919.23 (5.39x) |
| Any MaxUInt32Value WKT JSON parse | 567.31 | — | — | 3463.85 (6.11x) | 1910.48 (3.37x) |
| Any BoolValue WKT JSON stringify | 165.13 | — | — | 2238.00 (13.55x) | 770.76 (4.67x) |
| Any BoolValue WKT JSON parse | 505.78 | — | — | 4047.35 (8.00x) | 1745.75 (3.45x) |
| Any FalseBoolValue WKT JSON stringify | 208.41 | — | — | 1406.55 (6.75x) | 917.37 (4.40x) |
| Any FalseBoolValue WKT JSON parse | 581.93 | — | — | 2751.72 (4.73x) | 1734.06 (2.98x) |
| Any StringValue WKT JSON stringify | 248.41 | — | — | 2486.14 (10.01x) | 944.48 (3.80x) |
| Any StringValue WKT JSON parse | 669.61 | — | — | 3133.23 (4.68x) | 1559.39 (2.33x) |
| Any StringValue Escape WKT JSON parse | 691.51 | — | — | 3501.19 (5.06x) | 1967.89 (2.85x) |
| Any StringValue Surrogate WKT JSON parse | 621.12 | — | — | 3366.41 (5.42x) | 2035.74 (3.28x) |
| Any EmptyStringValue WKT JSON stringify | 187.36 | — | — | 1097.39 (5.86x) | 866.70 (4.63x) |
| Any EmptyStringValue WKT JSON parse | 532.57 | — | — | 3109.67 (5.84x) | 1652.80 (3.10x) |
| Any BytesValue WKT JSON stringify | 175.16 | — | — | 1974.61 (11.27x) | 933.03 (5.33x) |
| Any BytesValue WKT JSON parse | 587.42 | — | — | 3417.48 (5.82x) | 1914.90 (3.26x) |
| Any BytesValue URL WKT JSON parse | 604.57 | — | — | 3351.43 (5.54x) | 1799.36 (2.98x) |
| Any BytesValue StandardBase64 WKT JSON parse | 905.13 | — | — | 3392.42 (3.75x) | 1671.39 (1.85x) |
| Any BytesValue Unpadded WKT JSON parse | 627.87 | — | — | 3407.52 (5.43x) | 1936.06 (3.08x) |
| Any EmptyBytesValue WKT JSON stringify | 197.40 | — | — | 1105.48 (5.60x) | 1012.56 (5.13x) |
| Any EmptyBytesValue WKT JSON parse | 692.45 | — | — | 2798.92 (4.04x) | 1701.47 (2.46x) |
| Nested Any WKT JSON stringify | 283.24 | — | — | 2896.37 (10.23x) | 1814.39 (6.41x) |
| Nested Any WKT JSON parse | 867.35 | — | — | 5374.16 (6.20x) | 3988.01 (4.60x) |
| Duration JSON stringify | 57.28 | — | — | 1151.47 (20.10x) | 500.91 (8.74x) |
| Duration JSON parse | 20.76 | — | — | 1804.53 (86.92x) | 516.67 (24.89x) |
| Duration Escape JSON parse | 40.53 | — | — | 1841.29 (45.43x) | 586.15 (14.46x) |
| PlusDuration JSON parse | 21.31 | — | — | 1794.19 (84.19x) | 678.34 (31.83x) |
| ShortFractionDuration JSON parse | 16.32 | — | — | 1741.44 (106.71x) | 606.68 (37.17x) |
| MicroDuration JSON stringify | 58.76 | — | — | 1080.42 (18.39x) | 547.08 (9.31x) |
| MicroDuration JSON parse | 20.95 | — | — | 1726.03 (82.39x) | 648.19 (30.94x) |
| NanoDuration JSON stringify | 57.30 | — | — | 1163.81 (20.31x) | 645.63 (11.27x) |
| NanoDuration JSON parse | 26.44 | — | — | 1842.58 (69.69x) | 689.46 (26.08x) |
| NegativeDuration JSON stringify | 58.09 | — | — | 1171.23 (20.16x) | 629.38 (10.83x) |
| NegativeDuration JSON parse | 21.56 | — | — | 1789.24 (82.99x) | 596.21 (27.65x) |
| FractionalNegativeDuration JSON stringify | 58.08 | — | — | 1191.29 (20.51x) | 629.27 (10.83x) |
| FractionalNegativeDuration JSON parse | 20.82 | — | — | 1854.09 (89.05x) | 548.44 (26.34x) |
| MaxDuration JSON stringify | 49.15 | — | — | 862.09 (17.54x) | 806.02 (16.40x) |
| MaxDuration JSON parse | 34.61 | — | — | 1886.55 (54.51x) | 598.32 (17.29x) |
| MinDuration JSON stringify | 49.41 | — | — | 1011.36 (20.47x) | 418.06 (8.46x) |
| MinDuration JSON parse | 35.81 | — | — | 1810.93 (50.57x) | 399.44 (11.15x) |
| ZeroDuration JSON stringify | 44.37 | — | — | 910.21 (20.51x) | 369.40 (8.33x) |
| ZeroDuration JSON parse | 13.56 | — | — | 1729.62 (127.55x) | 310.21 (22.88x) |
| FieldMask JSON stringify | 66.47 | — | — | 1073.83 (16.16x) | 654.33 (9.84x) |
| FieldMask JSON parse | 139.45 | — | — | 2099.04 (15.05x) | 923.56 (6.62x) |
| FieldMask Escape JSON parse | 204.28 | — | — | 2259.63 (11.06x) | 1112.84 (5.45x) |
| EmptyFieldMask JSON stringify | 40.87 | — | — | 654.17 (16.01x) | 187.35 (4.58x) |
| EmptyFieldMask JSON parse | 4.78 | — | — | 1095.49 (229.18x) | 179.41 (37.53x) |
| Timestamp JSON stringify | 95.98 | — | — | 1520.93 (15.85x) | 429.74 (4.48x) |
| Timestamp JSON parse | 82.48 | — | — | 1847.27 (22.40x) | 432.63 (5.25x) |
| Timestamp Escape JSON parse | 143.44 | — | — | 1886.42 (13.15x) | 527.48 (3.68x) |
| ShortFraction Timestamp JSON parse | 63.53 | — | — | 1840.16 (28.97x) | 407.78 (6.42x) |
| Micro Timestamp JSON stringify | 162.49 | — | — | 1371.21 (8.44x) | 443.86 (2.73x) |
| Micro Timestamp JSON parse | 90.63 | — | — | 1831.87 (20.21x) | 455.51 (5.03x) |
| Nano Timestamp JSON stringify | 160.97 | — | — | 1377.87 (8.56x) | 418.80 (2.60x) |
| Nano Timestamp JSON parse | 94.93 | — | — | 1925.09 (20.28x) | 456.84 (4.81x) |
| Offset Timestamp JSON parse | 96.41 | — | — | 1859.27 (19.29x) | 464.78 (4.82x) |
| PreEpoch Timestamp JSON stringify | 107.41 | — | — | 1404.57 (13.08x) | 398.64 (3.71x) |
| PreEpoch Timestamp JSON parse | 75.85 | — | — | 1800.45 (23.74x) | 441.92 (5.83x) |
| Max Timestamp JSON stringify | 131.93 | — | — | 1541.11 (11.68x) | 437.34 (3.31x) |
| Max Timestamp JSON parse | 94.92 | — | — | 1883.55 (19.84x) | 439.85 (4.63x) |
| Min Timestamp JSON stringify | 147.45 | — | — | 1300.71 (8.82x) | 453.59 (3.08x) |
| Min Timestamp JSON parse | 72.16 | — | — | 1861.24 (25.79x) | 396.91 (5.50x) |
| Empty JSON stringify | 28.44 | — | — | 494.53 (17.39x) | 84.37 (2.97x) |
| Empty JSON parse | 87.57 | — | — | 743.44 (8.49x) | 280.18 (3.20x) |
| Struct JSON stringify | 299.59 | — | — | 7004.46 (23.38x) | 3627.37 (12.11x) |
| Struct JSON parse | 886.16 | — | — | 13704.00 (15.46x) | 5919.29 (6.68x) |
| Struct Escape JSON parse | 897.67 | — | — | 13888.10 (15.47x) | 6741.02 (7.51x) |
| Struct NumberExponent JSON parse | 843.51 | — | — | 13956.30 (16.55x) | 6264.82 (7.43x) |
| Struct Surrogate JSON parse | 372.15 | — | — | 5830.34 (15.67x) | 1663.40 (4.47x) |
| Struct KeySurrogate JSON parse | 505.68 | — | — | 5887.61 (11.64x) | 1536.31 (3.04x) |
| EmptyStruct JSON stringify | 54.41 | — | — | 764.49 (14.05x) | 371.23 (6.82x) |
| EmptyStruct JSON parse | 110.92 | — | — | 2514.62 (22.67x) | 375.82 (3.39x) |
| Value JSON stringify | 324.63 | — | — | 8048.87 (24.79x) | 4060.27 (12.51x) |
| Value JSON parse | 1191.61 | — | — | 14932.80 (12.53x) | 6654.02 (5.58x) |
| Value Escape JSON parse | 1014.45 | — | — | 22655.30 (22.33x) | 6901.41 (6.80x) |
| Value NumberExponent JSON parse | 875.02 | — | — | 21608.60 (24.69x) | 6719.03 (7.68x) |
| Value Surrogate JSON parse | 394.55 | — | — | 12223.20 (30.98x) | 1944.28 (4.93x) |
| Value KeySurrogate JSON parse | 395.59 | — | — | 13282.80 (33.58x) | 2020.85 (5.11x) |
| NullValue JSON stringify | 40.35 | — | — | 2218.88 (54.99x) | 226.92 (5.62x) |
| NullValue JSON parse | 70.30 | — | — | 6300.25 (89.62x) | 355.68 (5.06x) |
| StringScalarValue JSON stringify | 47.52 | — | — | 2018.84 (42.48x) | 302.73 (6.37x) |
| StringScalarValue JSON parse | 140.53 | — | — | 3531.48 (25.13x) | 404.26 (2.88x) |
| StringScalarValue Escape JSON parse | 151.19 | — | — | 4097.61 (27.10x) | 542.78 (3.59x) |
| StringScalarValue Surrogate JSON parse | 149.51 | — | — | 3957.51 (26.47x) | 521.32 (3.49x) |
| EmptyStringScalarValue JSON stringify | 45.59 | — | — | 2318.61 (50.86x) | 285.33 (6.26x) |
| EmptyStringScalarValue JSON parse | 87.81 | — | — | 3632.19 (41.36x) | 417.21 (4.75x) |
| NumberValue JSON stringify | 75.60 | — | — | 2883.04 (38.14x) | 376.41 (4.98x) |
| NumberValue JSON parse | 133.35 | — | — | 4270.44 (32.02x) | 423.88 (3.18x) |
| NumberValue Exponent JSON parse | 168.69 | — | — | 4176.07 (24.76x) | 441.71 (2.62x) |
| NegativeNumberValue JSON stringify | 138.42 | — | — | 2684.97 (19.40x) | 382.91 (2.77x) |
| NegativeNumberValue JSON parse | 164.42 | — | — | 2473.82 (15.05x) | 438.80 (2.67x) |
| ZeroNumberValue JSON stringify | 82.51 | — | — | 1568.53 (19.01x) | 329.02 (3.99x) |
| ZeroNumberValue JSON parse | 157.17 | — | — | 2732.79 (17.39x) | 352.20 (2.24x) |
| BoolScalarValue JSON stringify | 53.98 | — | — | 2060.54 (38.17x) | 239.22 (4.43x) |
| BoolScalarValue JSON parse | 84.48 | — | — | 2575.76 (30.49x) | 431.26 (5.10x) |
| FalseBoolScalarValue JSON stringify | 53.49 | — | — | 2077.46 (38.84x) | 268.83 (5.03x) |
| FalseBoolScalarValue JSON parse | 85.36 | — | — | 3424.40 (40.12x) | 376.39 (4.41x) |
| ListKindValue JSON stringify | 270.32 | — | — | 10071.50 (37.26x) | 2868.61 (10.61x) |
| ListKindValue JSON parse | 809.32 | — | — | 15334.80 (18.95x) | 5465.30 (6.75x) |
| ListKindValue Escape JSON parse | 873.13 | — | — | 13760.40 (15.76x) | 5516.52 (6.32x) |
| ListKindValue Surrogate JSON parse | 321.32 | — | — | 6079.63 (18.92x) | 1564.38 (4.87x) |
| EmptyStructKindValue JSON stringify | 42.29 | — | — | 2911.81 (68.85x) | 598.18 (14.14x) |
| EmptyStructKindValue JSON parse | 110.37 | — | — | 5349.57 (48.47x) | 689.82 (6.25x) |
| EmptyListKindValue JSON stringify | 41.11 | — | — | 2463.65 (59.93x) | 395.58 (9.62x) |
| EmptyListKindValue JSON parse | 147.98 | — | — | 5289.76 (35.75x) | 692.44 (4.68x) |
| ListValue JSON stringify | 138.17 | — | — | 6019.20 (43.56x) | 3030.11 (21.93x) |
| ListValue JSON parse | 651.57 | — | — | 10756.70 (16.51x) | 5464.11 (8.39x) |
| ListValue Escape JSON parse | 668.08 | — | — | 10712.00 (16.03x) | 5359.33 (8.02x) |
| ListValue Surrogate JSON parse | 297.29 | — | — | 4303.24 (14.47x) | 1337.31 (4.50x) |
| EmptyListValue JSON stringify | 39.88 | — | — | 927.29 (23.25x) | 181.15 (4.54x) |
| EmptyListValue JSON parse | 125.26 | — | — | 2981.54 (23.80x) | 328.67 (2.62x) |
| DoubleValue JSON stringify | 120.95 | — | — | 997.01 (8.24x) | 207.45 (1.72x) |
| DoubleValue JSON parse | 140.17 | — | — | 1526.62 (10.89x) | 295.03 (2.10x) |
| DoubleValue String JSON parse | 140.59 | — | — | 1484.01 (10.56x) | 437.05 (3.11x) |
| DoubleValue Exponent JSON parse | 145.77 | — | — | 1604.44 (11.01x) | 322.06 (2.21x) |
| NegativeDoubleValue JSON stringify | 123.17 | — | — | 958.99 (7.79x) | 214.80 (1.74x) |
| NegativeDoubleValue JSON parse | 141.26 | — | — | 1548.34 (10.96x) | 332.15 (2.35x) |
| ZeroDoubleValue JSON stringify | 70.30 | — | — | 883.24 (12.56x) | 184.68 (2.63x) |
| ZeroDoubleValue JSON parse | 132.10 | — | — | 1485.98 (11.25x) | 268.88 (2.04x) |
| DoubleValue NaN JSON stringify | 68.32 | — | — | 699.73 (10.24x) | 145.21 (2.13x) |
| DoubleValue NaN JSON parse | 127.88 | — | — | 1372.03 (10.73x) | 268.09 (2.10x) |
| DoubleValue Infinity JSON stringify | 72.71 | — | — | 682.78 (9.39x) | 167.08 (2.30x) |
| DoubleValue Infinity JSON parse | 134.22 | — | — | 1417.40 (10.56x) | 338.72 (2.52x) |
| DoubleValue NegativeInfinity JSON stringify | 74.50 | — | — | 937.23 (12.58x) | 124.37 (1.67x) |
| DoubleValue NegativeInfinity JSON parse | 138.87 | — | — | 1458.17 (10.50x) | 298.24 (2.15x) |
| FloatValue JSON stringify | 127.16 | — | — | 827.81 (6.51x) | 245.79 (1.93x) |
| FloatValue JSON parse | 115.85 | — | — | 1608.33 (13.88x) | 333.08 (2.88x) |
| FloatValue String JSON parse | 137.19 | — | — | 1493.65 (10.89x) | 392.04 (2.86x) |
| FloatValue Exponent JSON parse | 143.64 | — | — | 1501.67 (10.45x) | 413.31 (2.88x) |
| NegativeFloatValue JSON stringify | 74.41 | — | — | 859.14 (11.55x) | 190.07 (2.55x) |
| NegativeFloatValue JSON parse | 116.93 | — | — | 1566.83 (13.40x) | 292.08 (2.50x) |
| ZeroFloatValue JSON stringify | 65.70 | — | — | 796.45 (12.12x) | 183.05 (2.79x) |
| ZeroFloatValue JSON parse | 130.06 | — | — | 1518.66 (11.68x) | 323.46 (2.49x) |
| FloatValue NaN JSON stringify | 46.10 | — | — | 637.10 (13.82x) | 150.61 (3.27x) |
| FloatValue NaN JSON parse | 109.53 | — | — | 1421.91 (12.98x) | 389.16 (3.55x) |
| FloatValue Infinity JSON stringify | 71.06 | — | — | 671.84 (9.45x) | 166.28 (2.34x) |
| FloatValue Infinity JSON parse | 131.11 | — | — | 1425.56 (10.87x) | 269.37 (2.05x) |
| FloatValue NegativeInfinity JSON stringify | 72.95 | — | — | 765.88 (10.50x) | 155.95 (2.14x) |
| FloatValue NegativeInfinity JSON parse | 121.63 | — | — | 1356.01 (11.15x) | 327.34 (2.69x) |
| Int64Value JSON stringify | 50.00 | — | — | 697.40 (13.95x) | 305.58 (6.11x) |
| Int64Value JSON parse | 124.88 | — | — | 1556.69 (12.47x) | 523.45 (4.19x) |
| Int64Value Number JSON parse | 126.96 | — | — | 1576.34 (12.42x) | 405.06 (3.19x) |
| Int64Value Exponent JSON parse | 116.26 | — | — | 1448.19 (12.46x) | 469.66 (4.04x) |
| ZeroInt64Value JSON stringify | 41.44 | — | — | 669.76 (16.16x) | 216.65 (5.23x) |
| ZeroInt64Value JSON parse | 106.23 | — | — | 1154.77 (10.87x) | 361.90 (3.41x) |
| NegativeInt64Value JSON stringify | 48.53 | — | — | 1341.60 (27.64x) | 280.40 (5.78x) |
| NegativeInt64Value JSON parse | 126.36 | — | — | 3615.25 (28.61x) | 537.25 (4.25x) |
| MinInt64Value JSON stringify | 49.57 | — | — | 1059.32 (21.37x) | 282.64 (5.70x) |
| MinInt64Value JSON parse | 133.92 | — | — | 2005.63 (14.98x) | 583.87 (4.36x) |
| MaxInt64Value JSON stringify | 49.30 | — | — | 1040.47 (21.10x) | 313.41 (6.36x) |
| MaxInt64Value JSON parse | 133.35 | — | — | 2012.85 (15.09x) | 499.15 (3.74x) |
| UInt64Value JSON stringify | 50.34 | — | — | 1060.67 (21.07x) | 294.01 (5.84x) |
| UInt64Value JSON parse | 126.09 | — | — | 1625.74 (12.89x) | 521.22 (4.13x) |
| UInt64Value Number JSON parse | 127.12 | — | — | 1632.11 (12.84x) | 406.80 (3.20x) |
| UInt64Value Exponent JSON parse | 116.29 | — | — | 1547.29 (13.31x) | 392.91 (3.38x) |
| ZeroUInt64Value JSON stringify | 41.73 | — | — | 635.09 (15.22x) | 223.27 (5.35x) |
| ZeroUInt64Value JSON parse | 105.56 | — | — | 1467.20 (13.90x) | 383.67 (3.63x) |
| MaxUInt64Value JSON stringify | 50.38 | — | — | 783.37 (15.55x) | 296.03 (5.88x) |
| MaxUInt64Value JSON parse | 139.85 | — | — | 1608.69 (11.50x) | 471.09 (3.37x) |
| Int32Value JSON stringify | 62.10 | — | — | 737.15 (11.87x) | 182.07 (2.93x) |
| Int32Value JSON parse | 164.23 | — | — | 1533.18 (9.34x) | 294.13 (1.79x) |
| Int32Value String JSON parse | 168.34 | — | — | 1383.78 (8.22x) | 400.65 (2.38x) |
| Int32Value Exponent JSON parse | 173.85 | — | — | 1463.17 (8.42x) | 343.99 (1.98x) |
| ZeroInt32Value JSON stringify | 62.79 | — | — | 669.23 (10.66x) | 156.98 (2.50x) |
| ZeroInt32Value JSON parse | 153.89 | — | — | 1440.80 (9.36x) | 327.71 (2.13x) |
| NegativeInt32Value JSON stringify | 63.50 | — | — | 689.02 (10.85x) | 155.04 (2.44x) |
| NegativeInt32Value JSON parse | 162.64 | — | — | 1470.65 (9.04x) | 380.16 (2.34x) |
| MinInt32Value JSON stringify | 64.77 | — | — | 668.81 (10.33x) | 149.95 (2.32x) |
| MinInt32Value JSON parse | 184.06 | — | — | 1544.76 (8.39x) | 344.94 (1.87x) |
| MaxInt32Value JSON stringify | 64.31 | — | — | 660.67 (10.27x) | 143.36 (2.23x) |
| MaxInt32Value JSON parse | 185.72 | — | — | 1491.11 (8.03x) | 353.16 (1.90x) |
| UInt32Value JSON stringify | 63.20 | — | — | 854.42 (13.52x) | 203.42 (3.22x) |
| UInt32Value JSON parse | 137.66 | — | — | 1563.54 (11.36x) | 325.87 (2.37x) |
| UInt32Value String JSON parse | 163.93 | — | — | 1443.87 (8.81x) | 386.63 (2.36x) |
| UInt32Value Exponent JSON parse | 171.11 | — | — | 1535.85 (8.98x) | 389.53 (2.28x) |
| ZeroUInt32Value JSON stringify | 49.80 | — | — | 687.62 (13.81x) | 150.43 (3.02x) |
| ZeroUInt32Value JSON parse | 131.64 | — | — | 1500.71 (11.40x) | 298.60 (2.27x) |
| MaxUInt32Value JSON stringify | 61.73 | — | — | 738.54 (11.96x) | 138.69 (2.25x) |
| MaxUInt32Value JSON parse | 180.13 | — | — | 1597.91 (8.87x) | 321.30 (1.78x) |
| BoolValue JSON stringify | 44.10 | — | — | 619.99 (14.06x) | 135.69 (3.08x) |
| BoolValue JSON parse | 59.69 | — | — | 1268.19 (21.25x) | 236.92 (3.97x) |
| FalseBoolValue JSON stringify | 56.99 | — | — | 697.41 (12.24x) | 122.20 (2.14x) |
| FalseBoolValue JSON parse | 73.09 | — | — | 1558.05 (21.32x) | 304.02 (4.16x) |
| StringValue JSON stringify | 72.13 | — | — | 740.32 (10.26x) | 203.95 (2.83x) |
| StringValue JSON parse | 146.35 | — | — | 1313.30 (8.97x) | 344.78 (2.36x) |
| StringValue Escape JSON parse | 136.17 | — | — | 1549.76 (11.38x) | 435.81 (3.20x) |
| StringValue Surrogate JSON parse | 128.63 | — | — | 1508.90 (11.73x) | 387.36 (3.01x) |
| EmptyStringValue JSON stringify | 48.57 | — | — | 638.01 (13.14x) | 222.43 (4.58x) |
| EmptyStringValue JSON parse | 66.02 | — | — | 1470.75 (22.28x) | 251.02 (3.80x) |
| BytesValue JSON stringify | 50.10 | — | — | 1076.89 (21.49x) | 236.93 (4.73x) |
| BytesValue JSON parse | 125.37 | — | — | 1614.76 (12.88x) | 363.20 (2.90x) |
| BytesValue URL JSON parse | 141.29 | — | — | 2047.21 (14.49x) | 348.68 (2.47x) |
| BytesValue StandardBase64 JSON parse | 124.03 | — | — | 1562.72 (12.60x) | 361.98 (2.92x) |
| BytesValue Unpadded JSON parse | 123.70 | — | — | 1463.83 (11.83x) | 335.93 (2.72x) |
| EmptyBytesValue JSON stringify | 41.63 | — | — | 808.93 (19.43x) | 206.76 (4.97x) |
| EmptyBytesValue JSON parse | 67.95 | — | — | 1436.54 (21.14x) | 289.49 (4.26x) |
| TextFormat format | 175.26 | — | — | 3260.19 (18.60x) | 3242.61 (18.50x) |
| TextFormat parse | 710.59 | — | — | 6263.89 (8.82x) | 7947.55 (11.18x) |
| packed fixed32 encode | 2.80 | 662.27 (236.53x) | 544.03 (194.30x) | 48.00 (17.14x) | 496.91 (177.47x) |
| packed fixed32 decode | 8.96 | 1405.31 (156.84x) | 2339.67 (261.12x) | 43.47 (4.85x) | 2371.49 (264.68x) |
| packed fixed64 encode | 2.01 | 592.27 (294.66x) | 578.34 (287.73x) | 75.79 (37.71x) | 412.60 (205.27x) |
| packed fixed64 decode | 4.51 | 1302.66 (288.84x) | 7999.44 (1773.71x) | 91.32 (20.25x) | 4285.29 (950.18x) |
| packed sfixed32 encode | 2.01 | 628.99 (312.93x) | 544.00 (270.65x) | 44.17 (21.97x) | 418.72 (208.32x) |
| packed sfixed32 decode | 4.54 | 1193.72 (262.93x) | 2351.88 (518.04x) | 49.03 (10.80x) | 2433.14 (535.93x) |
| packed sfixed64 encode | 2.01 | 636.04 (316.44x) | 561.29 (279.25x) | 82.05 (40.82x) | 398.04 (198.03x) |
| packed sfixed64 decode | 8.88 | 1190.69 (134.09x) | 7701.56 (867.29x) | 76.98 (8.67x) | 3428.04 (386.04x) |
| packed float encode | 2.01 | 913.49 (454.47x) | 580.23 (288.67x) | 44.12 (21.95x) | 489.30 (243.43x) |
| packed float decode | 4.54 | 1152.23 (253.80x) | 2405.30 (529.80x) | 66.22 (14.59x) | 2333.53 (513.99x) |
| packed double encode | 2.06 | 943.19 (457.86x) | 582.72 (282.87x) | 69.79 (33.88x) | 354.66 (172.17x) |
| packed double decode | 4.54 | 1027.87 (226.40x) | 2435.05 (536.35x) | 79.54 (17.52x) | 3839.31 (845.66x) |
| packed uint64 encode | 1301.74 | 5679.04 (4.36x) | 7138.69 (5.48x) | 2796.45 (2.15x) | 4714.23 (3.62x) |
| packed uint64 decode | 1787.68 | 3564.83 (1.99x) | 10179.64 (5.69x) | 3608.66 (2.02x) | 12167.62 (6.81x) |
| packed uint32 encode | 994.17 | 4480.20 (4.51x) | 4067.49 (4.09x) | 2131.89 (2.14x) | 3998.25 (4.02x) |
| packed uint32 decode | 1960.32 | 2943.16 (1.50x) | 3815.21 (1.95x) | 2634.20 (1.34x) | 8727.42 (4.45x) |
| packed int64 encode | 1409.24 | 13676.24 (9.70x) | 7012.40 (4.98x) | 3738.11 (2.65x) | 6681.73 (4.74x) |
| packed int64 decode | 2789.67 | 4315.01 (1.55x) | 11673.58 (4.18x) | 5730.09 (2.05x) | 15038.46 (5.39x) |
| packed sint32 encode | 1149.53 | 4189.08 (3.64x) | 3500.19 (3.04x) | 1972.65 (1.72x) | 4583.94 (3.99x) |
| packed sint32 decode | 970.69 | 3366.86 (3.47x) | 3957.19 (4.08x) | 1498.81 (1.54x) | 5354.02 (5.52x) |
| packed sint64 encode | 1414.16 | 6120.98 (4.33x) | 4988.63 (3.53x) | 3121.69 (2.21x) | 5698.53 (4.03x) |
| packed sint64 decode | 2286.91 | 4037.07 (1.77x) | 10780.13 (4.71x) | 3669.49 (1.60x) | 11186.27 (4.89x) |
| packed bool encode | 2.01 | 1723.28 (857.35x) | 541.65 (269.48x) | 23.28 (11.58x) | 2937.33 (1461.36x) |
| packed bool decode | 264.25 | 2004.64 (7.59x) | 3163.17 (11.97x) | 860.68 (3.26x) | 2501.36 (9.47x) |
| packed enum encode | 281.53 | 3539.41 (12.57x) | 2082.60 (7.40x) | 1257.40 (4.47x) | 3299.44 (11.72x) |
| packed enum decode | 224.40 | 2000.62 (8.92x) | 3355.17 (14.95x) | 717.20 (3.20x) | 3231.04 (14.40x) |
| large map encode | 4715.74 | 19643.61 (4.17x) | 10083.16 (2.14x) | 26271.00 (5.57x) | 236072.37 (50.06x) |
| shuffled large map deterministic binary encode | 36580.60 | — | — | 105195.00 (2.88x) | 455636.97 (12.46x) |
| large map decode | 30254.14 | 112226.39 (3.71x) | 110112.02 (3.64x) | 106928.00 (3.53x) | 345804.64 (11.43x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON (including generated `map<string, int32>` surrogate-pair key parse, null-field parse, open-enum numeric parse, and integer numeric-exponent parse), Any/WKT JSON (including embedded zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound `Duration`, non-empty/escaped-input parse/number-exponent parse/surrogate-pair value parse/surrogate-pair key parse and empty `Struct`, object/escaped-object parse/object-number-exponent/object-surrogate-pair value parse/object-surrogate-pair key parse/list/escaped-list/surrogate-list/string-scalar/escaped-string-scalar/surrogate-string-scalar/number-exponent/negative-number `Value` (including default-like scalar and empty object/list kinds),
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
