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

Latest accepted comparison (`/tmp/pbz-compare-enum-number-json-final.log`,
summarized in `/tmp/pbz-summary-enum-number-json-final.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Pivoted rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 21.30 | 134.42 (6.31x) | 68.17 (3.20x) | 108.69 (5.10x) | 882.69 (41.44x) |
| binary decode | 124.68 | 254.85 (2.04x) | 228.46 (1.83x) | 318.94 (2.56x) | 1181.10 (9.47x) |
| unknown fields count by number | 3.58 | — | — | 160.60 (44.86x) | — |
| deterministic binary encode | 53.01 | — | — | 173.84 (3.28x) | 1161.03 (21.90x) |
| scalarmix encode | 17.80 | 107.60 (6.04x) | 81.32 (4.57x) | 29.69 (1.67x) | 208.05 (11.69x) |
| scalarmix decode | 59.76 | 143.16 (2.40x) | 229.74 (3.84x) | 100.27 (1.68x) | 295.69 (4.95x) |
| textbytes encode | 13.57 | 98.09 (7.23x) | 33.75 (2.49x) | 125.59 (9.26x) | 213.98 (15.77x) |
| textbytes decode | 41.03 | 395.12 (9.63x) | 236.60 (5.77x) | 167.47 (4.08x) | 976.76 (23.81x) |
| largebytes encode | 22.08 | 2758.47 (124.93x) | 2706.89 (122.59x) | 2742.45 (124.21x) | 2840.69 (128.65x) |
| largebytes decode | 88.40 | 6188.57 (70.01x) | 3237.65 (36.62x) | 2789.76 (31.56x) | 31058.74 (351.34x) |
| presencemix encode | 18.08 | 55.28 (3.06x) | 33.27 (1.84x) | 64.60 (3.57x) | 228.44 (12.63x) |
| presencemix decode | 56.97 | 133.08 (2.34x) | 111.35 (1.95x) | 164.49 (2.89x) | 485.49 (8.52x) |
| complex encode | 74.08 | 132.55 (1.79x) | 109.59 (1.48x) | 167.03 (2.25x) | 1003.19 (13.54x) |
| complex decode | 169.99 | 388.58 (2.29x) | 339.17 (2.00x) | 394.44 (2.32x) | 1895.55 (11.15x) |
| complex deterministic binary encode | 99.70 | — | — | 200.79 (2.01x) | 1376.77 (13.81x) |
| complex JSON stringify | 284.42 | — | — | 6116.94 (21.51x) | 7548.51 (26.54x) |
| complex JSON parse | 3165.83 | — | — | 14891.70 (4.70x) | 9129.10 (2.88x) |
| complex TextFormat format | 404.06 | — | — | 4653.38 (11.52x) | 7329.16 (18.14x) |
| complex TextFormat parse | 1788.09 | — | — | 8698.75 (4.86x) | 10202.81 (5.71x) |
| packed int32 encode | 641.89 | 3701.24 (5.77x) | 2940.82 (4.58x) | 1475.36 (2.30x) | 3367.04 (5.25x) |
| packed int32 decode | 698.67 | 2360.28 (3.38x) | 3801.86 (5.44x) | 1096.08 (1.57x) | 3915.08 (5.60x) |
| JSON stringify | 158.11 | — | — | 3824.56 (24.19x) | 2265.94 (14.33x) |
| AlwaysPrint JSON stringify | 59.75 | — | — | 3337.95 (55.87x) | 1495.24 (25.02x) |
| ProtoName JSON stringify | 310.86 | — | — | 5941.42 (19.11x) | 4528.13 (14.57x) |
| EnumNumber JSON stringify | 546.76 | — | — | 5785.58 (10.58x) | 4503.87 (8.24x) |
| JSON parse | 1983.73 | — | — | 9511.93 (4.79x) | 5121.23 (2.58x) |
| MapKeySurrogate JSON parse | 429.23 | — | — | 4377.76 (10.20x) | 1151.75 (2.68x) |
| NullFields JSON parse | 505.06 | — | — | 2457.23 (4.87x) | 828.23 (1.64x) |
| IgnoreUnknown JSON parse | 1199.17 | — | — | 6767.86 (5.64x) | 2777.93 (2.32x) |
| OpenEnum JSON parse | 300.27 | — | — | 5329.66 (17.75x) | 477.65 (1.59x) |
| EnumName JSON parse | 297.20 | — | — | 4543.89 (15.29x) | 448.68 (1.51x) |
| ProtoName JSON parse | 836.12 | — | — | 4983.42 (5.96x) | 1277.99 (1.53x) |
| IntExponent JSON parse | 1683.07 | — | — | 9100.40 (5.41x) | 4884.18 (2.90x) |
| Any WKT JSON stringify | 132.58 | — | — | 2423.15 (18.28x) | 1131.55 (8.53x) |
| Any WKT JSON parse | 850.21 | — | — | 3825.04 (4.50x) | 1792.72 (2.11x) |
| Any Duration Escape WKT JSON parse | 794.53 | — | — | 4076.86 (5.13x) | 1729.85 (2.18x) |
| Any PlusDuration WKT JSON parse | 718.89 | — | — | 3884.81 (5.40x) | 1688.42 (2.35x) |
| Any ShortFractionDuration WKT JSON parse | 525.63 | — | — | 3820.62 (7.27x) | 1796.61 (3.42x) |
| Any MicroDuration WKT JSON stringify | 134.53 | — | — | 2816.56 (20.94x) | 957.53 (7.12x) |
| Any MicroDuration WKT JSON parse | 531.88 | — | — | 4067.63 (7.65x) | 1582.58 (2.98x) |
| Any NanoDuration WKT JSON stringify | 129.30 | — | — | 2955.36 (22.86x) | 1170.18 (9.05x) |
| Any NanoDuration WKT JSON parse | 535.52 | — | — | 4697.63 (8.77x) | 1820.26 (3.40x) |
| Any NegativeDuration WKT JSON stringify | 136.66 | — | — | 2617.47 (19.15x) | 1101.27 (8.06x) |
| Any NegativeDuration WKT JSON parse | 536.52 | — | — | 3979.13 (7.42x) | 1888.03 (3.52x) |
| Any FractionalNegativeDuration WKT JSON stringify | 129.48 | — | — | 2373.34 (18.33x) | 1125.85 (8.70x) |
| Any FractionalNegativeDuration WKT JSON parse | 529.18 | — | — | 3864.04 (7.30x) | 1719.07 (3.25x) |
| Any MaxDuration WKT JSON stringify | 215.71 | — | — | 2327.35 (10.79x) | 1008.27 (4.67x) |
| Any MaxDuration WKT JSON parse | 872.12 | — | — | 3829.95 (4.39x) | 1717.60 (1.97x) |
| Any MinDuration WKT JSON stringify | 128.34 | — | — | 2219.23 (17.29x) | 971.41 (7.57x) |
| Any MinDuration WKT JSON parse | 647.70 | — | — | 3812.38 (5.89x) | 1824.83 (2.82x) |
| Any ZeroDuration WKT JSON stringify | 183.99 | — | — | 1068.46 (5.81x) | 953.75 (5.18x) |
| Any ZeroDuration WKT JSON parse | 472.88 | — | — | 2733.83 (5.78x) | 1859.46 (3.93x) |
| Any FieldMask WKT JSON stringify | 250.36 | — | — | 2204.59 (8.81x) | 1891.59 (7.56x) |
| Any FieldMask WKT JSON parse | 732.99 | — | — | 3961.90 (5.41x) | 2425.69 (3.31x) |
| Any FieldMask Escape WKT JSON parse | 732.86 | — | — | 4088.45 (5.58x) | 2580.06 (3.52x) |
| Any EmptyFieldMask WKT JSON stringify | 117.49 | — | — | 1025.25 (8.73x) | 773.53 (6.58x) |
| Any EmptyFieldMask WKT JSON parse | 446.33 | — | — | 2671.72 (5.99x) | 1566.50 (3.51x) |
| Any Timestamp WKT JSON stringify | 360.64 | — | — | 2480.51 (6.88x) | 1009.90 (2.80x) |
| Any Timestamp WKT JSON parse | 952.58 | — | — | 3745.97 (3.93x) | 2016.01 (2.12x) |
| Any Timestamp Escape WKT JSON parse | 822.47 | — | — | 3806.11 (4.63x) | 2066.14 (2.51x) |
| Any ShortFraction Timestamp WKT JSON parse | 572.27 | — | — | 3826.36 (6.69x) | 2309.48 (4.04x) |
| Any Micro Timestamp WKT JSON stringify | 177.74 | — | — | 2577.63 (14.50x) | 1142.70 (6.43x) |
| Any Micro Timestamp WKT JSON parse | 576.77 | — | — | 3846.19 (6.67x) | 1984.69 (3.44x) |
| Any Nano Timestamp WKT JSON stringify | 188.00 | — | — | 2565.34 (13.65x) | 1439.90 (7.66x) |
| Any Nano Timestamp WKT JSON parse | 582.03 | — | — | 3721.35 (6.39x) | 1805.81 (3.10x) |
| Any Offset Timestamp WKT JSON parse | 590.63 | — | — | 3725.79 (6.31x) | 2046.16 (3.46x) |
| Any PreEpoch Timestamp WKT JSON stringify | 142.07 | — | — | 2498.82 (17.59x) | 1028.17 (7.24x) |
| Any PreEpoch Timestamp WKT JSON parse | 925.76 | — | — | 3710.23 (4.01x) | 1942.82 (2.10x) |
| Any Max Timestamp WKT JSON stringify | 315.46 | — | — | 2381.56 (7.55x) | 1046.48 (3.32x) |
| Any Max Timestamp WKT JSON parse | 828.40 | — | — | 3789.65 (4.57x) | 2028.29 (2.45x) |
| Any Min Timestamp WKT JSON stringify | 229.98 | — | — | 2424.14 (10.54x) | 1547.95 (6.73x) |
| Any Min Timestamp WKT JSON parse | 563.17 | — | — | 3690.91 (6.55x) | 2318.29 (4.12x) |
| Any Empty WKT JSON stringify | 89.02 | — | — | 1018.61 (11.44x) | 935.46 (10.51x) |
| Any Empty WKT JSON parse | 336.70 | — | — | 2588.06 (7.69x) | 1703.86 (5.06x) |
| Any Struct WKT JSON stringify | 631.86 | — | — | 7239.88 (11.46x) | 7373.85 (11.67x) |
| Any Struct WKT JSON parse | 1745.92 | — | — | 13741.50 (7.87x) | 10053.74 (5.76x) |
| Any Struct Escape WKT JSON parse | 1926.70 | — | — | 13759.10 (7.14x) | 11443.19 (5.94x) |
| Any Struct NumberExponent WKT JSON parse | 1750.34 | — | — | 13654.60 (7.80x) | 11151.80 (6.37x) |
| Any Struct Surrogate WKT JSON parse | 753.12 | — | — | 7749.41 (10.29x) | 3771.69 (5.01x) |
| Any Struct KeySurrogate WKT JSON parse | 1074.57 | — | — | 7823.99 (7.28x) | 4195.28 (3.90x) |
| Any EmptyStruct WKT JSON stringify | 186.54 | — | — | 1088.35 (5.83x) | 1193.78 (6.40x) |
| Any EmptyStruct WKT JSON parse | 471.75 | — | — | 2705.40 (5.73x) | 1930.86 (4.09x) |
| Any Value WKT JSON stringify | 665.86 | — | — | 7355.77 (11.05x) | 8772.79 (13.18x) |
| Any Value WKT JSON parse | 1804.06 | — | — | 13911.50 (7.71x) | 11890.85 (6.59x) |
| Any Value Escape WKT JSON parse | 2590.48 | — | — | 14179.30 (5.47x) | 11688.69 (4.51x) |
| Any Value NumberExponent WKT JSON parse | 1800.20 | — | — | 14273.70 (7.93x) | 11643.29 (6.47x) |
| Any Value Surrogate WKT JSON parse | 815.45 | — | — | 8074.33 (9.90x) | 4889.54 (6.00x) |
| Any Value KeySurrogate WKT JSON parse | 1094.45 | — | — | 8026.67 (7.33x) | 4666.94 (4.26x) |
| Any NullValue WKT JSON stringify | 201.10 | — | — | 2682.90 (13.34x) | 1104.44 (5.49x) |
| Any NullValue WKT JSON parse | 607.74 | — | — | 5056.82 (8.32x) | 1934.14 (3.18x) |
| Any StringScalarValue WKT JSON stringify | 188.29 | — | — | 2678.14 (14.22x) | 1160.77 (6.16x) |
| Any StringScalarValue WKT JSON parse | 581.00 | — | — | 4438.18 (7.64x) | 2022.95 (3.48x) |
| Any StringScalarValue Escape WKT JSON parse | 526.03 | — | — | 4604.87 (8.75x) | 2124.86 (4.04x) |
| Any StringScalarValue Surrogate WKT JSON parse | 527.70 | — | — | 4336.49 (8.22x) | 1960.76 (3.72x) |
| Any EmptyStringScalarValue WKT JSON stringify | 142.79 | — | — | 2802.93 (19.63x) | 1524.31 (10.68x) |
| Any EmptyStringScalarValue WKT JSON parse | 483.79 | — | — | 4366.17 (9.02x) | 1942.17 (4.01x) |
| Any NumberValue WKT JSON stringify | 167.52 | — | — | 3066.99 (18.31x) | 1101.70 (6.58x) |
| Any NumberValue WKT JSON parse | 500.70 | — | — | 4465.89 (8.92x) | 1824.18 (3.64x) |
| Any NumberValue Exponent WKT JSON parse | 506.46 | — | — | 4500.48 (8.89x) | 1974.70 (3.90x) |
| Any NegativeNumberValue WKT JSON stringify | 326.23 | — | — | 3209.35 (9.84x) | 1060.50 (3.25x) |
| Any NegativeNumberValue WKT JSON parse | 651.30 | — | — | 4421.21 (6.79x) | 1826.76 (2.80x) |
| Any ZeroNumberValue WKT JSON stringify | 135.85 | — | — | 3160.89 (23.27x) | 1225.31 (9.02x) |
| Any ZeroNumberValue WKT JSON parse | 630.69 | — | — | 4403.21 (6.98x) | 1832.21 (2.91x) |
| Any BoolScalarValue WKT JSON stringify | 196.89 | — | — | 2688.76 (13.66x) | 1018.17 (5.17x) |
| Any BoolScalarValue WKT JSON parse | 459.63 | — | — | 4285.77 (9.32x) | 1942.51 (4.23x) |
| Any FalseBoolScalarValue WKT JSON stringify | 127.00 | — | — | 2819.08 (22.20x) | 930.00 (7.32x) |
| Any FalseBoolScalarValue WKT JSON parse | 459.60 | — | — | 4235.29 (9.22x) | 1748.54 (3.80x) |
| Any ListKindValue WKT JSON stringify | 505.45 | — | — | 6843.96 (13.54x) | 5809.50 (11.49x) |
| Any ListKindValue WKT JSON parse | 1390.10 | — | — | 12339.20 (8.88x) | 8306.76 (5.98x) |
| Any ListKindValue Escape WKT JSON parse | 2046.25 | — | — | 12435.90 (6.08x) | 8613.73 (4.21x) |
| Any ListKindValue Surrogate WKT JSON parse | 728.39 | — | — | 5850.63 (8.03x) | 3277.80 (4.50x) |
| Any EmptyStructKindValue WKT JSON stringify | 141.49 | — | — | 3721.71 (26.30x) | 1614.27 (11.41x) |
| Any EmptyStructKindValue WKT JSON parse | 494.18 | — | — | 6758.10 (13.68x) | 2320.48 (4.70x) |
| Any EmptyListKindValue WKT JSON stringify | 151.59 | — | — | 3667.01 (24.19x) | 1348.31 (8.89x) |
| Any EmptyListKindValue WKT JSON parse | 498.71 | — | — | 5336.44 (10.70x) | 2158.80 (4.33x) |
| Any DoubleValue WKT JSON stringify | 192.89 | — | — | 2142.38 (11.11x) | 938.45 (4.87x) |
| Any DoubleValue WKT JSON parse | 522.13 | — | — | 3367.66 (6.45x) | 1832.37 (3.51x) |
| Any DoubleValue String WKT JSON parse | 830.61 | — | — | 3377.56 (4.07x) | 1795.75 (2.16x) |
| Any DoubleValue Exponent WKT JSON parse | 706.97 | — | — | 3392.69 (4.80x) | 1816.36 (2.57x) |
| Any NegativeDoubleValue WKT JSON stringify | 233.43 | — | — | 2141.55 (9.17x) | 941.36 (4.03x) |
| Any NegativeDoubleValue WKT JSON parse | 715.17 | — | — | 3376.36 (4.72x) | 1705.70 (2.39x) |
| Any ZeroDoubleValue WKT JSON stringify | 159.02 | — | — | 980.53 (6.17x) | 856.83 (5.39x) |
| Any ZeroDoubleValue WKT JSON parse | 519.85 | — | — | 2629.53 (5.06x) | 1622.26 (3.12x) |
| Any DoubleValue NaN WKT JSON stringify | 152.19 | — | — | 1923.68 (12.64x) | 776.95 (5.11x) |
| Any DoubleValue NaN WKT JSON parse | 516.67 | — | — | 3286.35 (6.36x) | 1716.64 (3.32x) |
| Any DoubleValue Infinity WKT JSON stringify | 161.20 | — | — | 1903.28 (11.81x) | 842.90 (5.23x) |
| Any DoubleValue Infinity WKT JSON parse | 522.02 | — | — | 3282.37 (6.29x) | 1536.39 (2.94x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 168.45 | — | — | 1889.67 (11.22x) | 718.79 (4.27x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 527.61 | — | — | 3306.87 (6.27x) | 1685.76 (3.20x) |
| Any FloatValue WKT JSON stringify | 342.56 | — | — | 2101.38 (6.13x) | 832.34 (2.43x) |
| Any FloatValue WKT JSON parse | 842.55 | — | — | 3354.60 (3.98x) | 1680.98 (2.00x) |
| Any FloatValue String WKT JSON parse | 698.06 | — | — | 3367.87 (4.82x) | 1891.26 (2.71x) |
| Any FloatValue Exponent WKT JSON parse | 626.36 | — | — | 3372.88 (5.38x) | 1799.33 (2.87x) |
| Any NegativeFloatValue WKT JSON stringify | 194.98 | — | — | 2102.53 (10.78x) | 753.67 (3.87x) |
| Any NegativeFloatValue WKT JSON parse | 528.92 | — | — | 3331.03 (6.30x) | 1800.75 (3.40x) |
| Any ZeroFloatValue WKT JSON stringify | 164.11 | — | — | 1574.07 (9.59x) | 721.36 (4.40x) |
| Any ZeroFloatValue WKT JSON parse | 521.41 | — | — | 3402.65 (6.53x) | 1737.32 (3.33x) |
| Any FloatValue NaN WKT JSON stringify | 157.90 | — | — | 2613.03 (16.55x) | 695.87 (4.41x) |
| Any FloatValue NaN WKT JSON parse | 520.61 | — | — | 4502.84 (8.65x) | 1661.31 (3.19x) |
| Any FloatValue Infinity WKT JSON stringify | 160.68 | — | — | 1924.85 (11.98x) | 814.90 (5.07x) |
| Any FloatValue Infinity WKT JSON parse | 525.93 | — | — | 5197.15 (9.88x) | 1659.29 (3.15x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 250.80 | — | — | 3114.70 (12.42x) | 879.66 (3.51x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 827.21 | — | — | 4648.93 (5.62x) | 1411.50 (1.71x) |
| Any Int64Value WKT JSON stringify | 264.73 | — | — | 1588.44 (6.00x) | 883.47 (3.34x) |
| Any Int64Value WKT JSON parse | 751.51 | — | — | 3870.59 (5.15x) | 1856.58 (2.47x) |
| Any Int64Value Number WKT JSON parse | 548.51 | — | — | 5202.57 (9.48x) | 1673.04 (3.05x) |
| Any Int64Value Exponent WKT JSON parse | 531.32 | — | — | 5387.18 (10.14x) | 1632.08 (3.07x) |
| Any ZeroInt64Value WKT JSON stringify | 159.95 | — | — | 1336.29 (8.35x) | 890.31 (5.57x) |
| Any ZeroInt64Value WKT JSON parse | 522.87 | — | — | 3355.56 (6.42x) | 1699.39 (3.25x) |
| Any NegativeInt64Value WKT JSON stringify | 172.64 | — | — | 2554.55 (14.80x) | 1042.15 (6.04x) |
| Any NegativeInt64Value WKT JSON parse | 555.35 | — | — | 3948.21 (7.11x) | 1995.13 (3.59x) |
| Any MinInt64Value WKT JSON stringify | 175.57 | — | — | 3143.88 (17.91x) | 1229.58 (7.00x) |
| Any MinInt64Value WKT JSON parse | 558.75 | — | — | 5175.29 (9.26x) | 1870.73 (3.35x) |
| Any MaxInt64Value WKT JSON stringify | 272.65 | — | — | 3160.51 (11.59x) | 1038.60 (3.81x) |
| Any MaxInt64Value WKT JSON parse | 802.26 | — | — | 6329.27 (7.89x) | 2228.80 (2.78x) |
| Any UInt64Value WKT JSON stringify | 261.20 | — | — | 3830.96 (14.67x) | 1083.78 (4.15x) |
| Any UInt64Value WKT JSON parse | 697.81 | — | — | 8004.70 (11.47x) | 1881.79 (2.70x) |
| Any UInt64Value Number WKT JSON parse | 552.73 | — | — | 4513.43 (8.17x) | 1957.94 (3.54x) |
| Any UInt64Value Exponent WKT JSON parse | 537.05 | — | — | 4679.01 (8.71x) | 1676.29 (3.12x) |
| Any ZeroUInt64Value WKT JSON stringify | 166.29 | — | — | 1848.87 (11.12x) | 733.07 (4.41x) |
| Any ZeroUInt64Value WKT JSON parse | 526.44 | — | — | 4182.16 (7.94x) | 1785.19 (3.39x) |
| Any MaxUInt64Value WKT JSON stringify | 182.91 | — | — | 2764.35 (15.11x) | 983.09 (5.37x) |
| Any MaxUInt64Value WKT JSON parse | 559.97 | — | — | 4047.75 (7.23x) | 2098.34 (3.75x) |
| Any Int32Value WKT JSON stringify | 170.50 | — | — | 2979.28 (17.47x) | 847.29 (4.97x) |
| Any Int32Value WKT JSON parse | 539.49 | — | — | 4943.37 (9.16x) | 1518.38 (2.81x) |
| Any Int32Value String WKT JSON parse | 849.77 | — | — | 5679.43 (6.68x) | 1985.76 (2.34x) |
| Any Int32Value Exponent WKT JSON parse | 672.44 | — | — | 4274.55 (6.36x) | 1747.42 (2.60x) |
| Any ZeroInt32Value WKT JSON stringify | 205.86 | — | — | 2018.93 (9.81x) | 743.12 (3.61x) |
| Any ZeroInt32Value WKT JSON parse | 534.91 | — | — | 3098.06 (5.79x) | 1620.04 (3.03x) |
| Any NegativeInt32Value WKT JSON stringify | 173.02 | — | — | 1793.52 (10.37x) | 811.25 (4.69x) |
| Any NegativeInt32Value WKT JSON parse | 536.47 | — | — | 3497.66 (6.52x) | 1691.10 (3.15x) |
| Any MinInt32Value WKT JSON stringify | 174.78 | — | — | 1681.35 (9.62x) | 706.65 (4.04x) |
| Any MinInt32Value WKT JSON parse | 540.89 | — | — | 3245.21 (6.00x) | 1908.39 (3.53x) |
| Any MaxInt32Value WKT JSON stringify | 171.36 | — | — | 2389.27 (13.94x) | 967.31 (5.64x) |
| Any MaxInt32Value WKT JSON parse | 545.65 | — | — | 3878.40 (7.11x) | 1402.48 (2.57x) |
| Any UInt32Value WKT JSON stringify | 178.93 | — | — | 2292.04 (12.81x) | 741.08 (4.14x) |
| Any UInt32Value WKT JSON parse | 537.47 | — | — | 4422.92 (8.23x) | 1780.84 (3.31x) |
| Any UInt32Value String WKT JSON parse | 860.25 | — | — | 4427.22 (5.15x) | 1779.60 (2.07x) |
| Any UInt32Value Exponent WKT JSON parse | 727.30 | — | — | 3875.65 (5.33x) | 1769.77 (2.43x) |
| Any ZeroUInt32Value WKT JSON stringify | 228.56 | — | — | 920.30 (4.03x) | 773.38 (3.38x) |
| Any ZeroUInt32Value WKT JSON parse | 655.92 | — | — | 2426.58 (3.70x) | 1610.40 (2.46x) |
| Any MaxUInt32Value WKT JSON stringify | 181.23 | — | — | 1746.58 (9.64x) | 730.90 (4.03x) |
| Any MaxUInt32Value WKT JSON parse | 543.60 | — | — | 3157.24 (5.81x) | 1733.67 (3.19x) |
| Any BoolValue WKT JSON stringify | 171.06 | — | — | 1964.99 (11.49x) | 700.96 (4.10x) |
| Any BoolValue WKT JSON parse | 485.84 | — | — | 3035.12 (6.25x) | 1574.85 (3.24x) |
| Any FalseBoolValue WKT JSON stringify | 180.18 | — | — | 1098.72 (6.10x) | 999.55 (5.55x) |
| Any FalseBoolValue WKT JSON parse | 489.61 | — | — | 2640.44 (5.39x) | 1660.55 (3.39x) |
| Any StringValue WKT JSON stringify | 200.28 | — | — | 1955.16 (9.76x) | 999.62 (4.99x) |
| Any StringValue WKT JSON parse | 549.65 | — | — | 3050.61 (5.55x) | 1611.49 (2.93x) |
| Any StringValue Escape WKT JSON parse | 884.36 | — | — | 3194.46 (3.61x) | 1842.59 (2.08x) |
| Any StringValue Surrogate WKT JSON parse | 775.71 | — | — | 3312.02 (4.27x) | 1661.05 (2.14x) |
| Any EmptyStringValue WKT JSON stringify | 232.41 | — | — | 1126.98 (4.85x) | 795.74 (3.42x) |
| Any EmptyStringValue WKT JSON parse | 587.06 | — | — | 2613.87 (4.45x) | 1692.30 (2.88x) |
| Any BytesValue WKT JSON stringify | 266.78 | — | — | 1978.34 (7.42x) | 1074.89 (4.03x) |
| Any BytesValue WKT JSON parse | 559.72 | — | — | 3416.96 (6.10x) | 1674.80 (2.99x) |
| Any BytesValue URL WKT JSON parse | 579.57 | — | — | 3294.51 (5.68x) | 1723.39 (2.97x) |
| Any BytesValue StandardBase64 WKT JSON parse | 565.95 | — | — | 3354.14 (5.93x) | 1601.95 (2.83x) |
| Any BytesValue Unpadded WKT JSON parse | 565.36 | — | — | 3256.30 (5.76x) | 1719.53 (3.04x) |
| Any EmptyBytesValue WKT JSON stringify | 262.86 | — | — | 945.68 (3.60x) | 841.77 (3.20x) |
| Any EmptyBytesValue WKT JSON parse | 791.26 | — | — | 2548.31 (3.22x) | 1569.54 (1.98x) |
| Nested Any WKT JSON stringify | 403.35 | — | — | 3086.98 (7.65x) | 1503.47 (3.73x) |
| Nested Any WKT JSON parse | 874.19 | — | — | 5239.20 (5.99x) | 3257.64 (3.73x) |
| Duration JSON stringify | 57.50 | — | — | 1181.60 (20.55x) | 353.48 (6.15x) |
| Duration JSON parse | 20.06 | — | — | 1857.55 (92.60x) | 462.49 (23.06x) |
| Duration Escape JSON parse | 44.01 | — | — | 1889.90 (42.94x) | 449.50 (10.21x) |
| PlusDuration JSON parse | 20.04 | — | — | 1800.95 (89.87x) | 555.08 (27.70x) |
| ShortFractionDuration JSON parse | 16.31 | — | — | 1760.75 (107.96x) | 370.51 (22.72x) |
| MicroDuration JSON stringify | 58.86 | — | — | 1083.56 (18.41x) | 385.46 (6.55x) |
| MicroDuration JSON parse | 20.33 | — | — | 1826.36 (89.84x) | 353.13 (17.37x) |
| NanoDuration JSON stringify | 56.66 | — | — | 1122.02 (19.80x) | 376.96 (6.65x) |
| NanoDuration JSON parse | 25.07 | — | — | 1824.96 (72.79x) | 467.21 (18.64x) |
| NegativeDuration JSON stringify | 57.64 | — | — | 1141.17 (19.80x) | 411.96 (7.15x) |
| NegativeDuration JSON parse | 18.89 | — | — | 1907.33 (100.97x) | 384.12 (20.33x) |
| FractionalNegativeDuration JSON stringify | 59.22 | — | — | 1118.49 (18.89x) | 407.09 (6.87x) |
| FractionalNegativeDuration JSON parse | 20.03 | — | — | 1860.07 (92.86x) | 406.34 (20.29x) |
| MaxDuration JSON stringify | 49.28 | — | — | 901.52 (18.29x) | 391.41 (7.94x) |
| MaxDuration JSON parse | 28.97 | — | — | 1773.05 (61.20x) | 374.33 (12.92x) |
| MinDuration JSON stringify | 49.59 | — | — | 916.24 (18.48x) | 413.18 (8.33x) |
| MinDuration JSON parse | 29.52 | — | — | 1794.15 (60.78x) | 388.97 (13.18x) |
| ZeroDuration JSON stringify | 44.37 | — | — | 930.50 (20.97x) | 349.54 (7.88x) |
| ZeroDuration JSON parse | 15.50 | — | — | 1742.07 (112.39x) | 294.82 (19.02x) |
| FieldMask JSON stringify | 136.87 | — | — | 1080.53 (7.89x) | 733.79 (5.36x) |
| FieldMask JSON parse | 141.09 | — | — | 2001.40 (14.19x) | 1044.44 (7.40x) |
| FieldMask Escape JSON parse | 194.98 | — | — | 2074.33 (10.64x) | 1009.18 (5.18x) |
| EmptyFieldMask JSON stringify | 40.97 | — | — | 663.76 (16.20x) | 306.41 (7.48x) |
| EmptyFieldMask JSON parse | 4.79 | — | — | 1071.84 (223.77x) | 193.14 (40.32x) |
| Timestamp JSON stringify | 96.29 | — | — | 1408.15 (14.62x) | 429.65 (4.46x) |
| Timestamp JSON parse | 46.18 | — | — | 1817.13 (39.35x) | 457.56 (9.91x) |
| Timestamp Escape JSON parse | 94.95 | — | — | 1865.41 (19.65x) | 531.53 (5.60x) |
| ShortFraction Timestamp JSON parse | 43.48 | — | — | 1812.72 (41.69x) | 456.81 (10.51x) |
| Micro Timestamp JSON stringify | 96.11 | — | — | 1176.51 (12.24x) | 434.32 (4.52x) |
| Micro Timestamp JSON parse | 48.21 | — | — | 1847.32 (38.32x) | 438.23 (9.09x) |
| Nano Timestamp JSON stringify | 94.22 | — | — | 1528.68 (16.22x) | 423.93 (4.50x) |
| Nano Timestamp JSON parse | 92.01 | — | — | 1847.17 (20.08x) | 469.85 (5.11x) |
| Offset Timestamp JSON parse | 95.00 | — | — | 1917.10 (20.18x) | 466.44 (4.91x) |
| PreEpoch Timestamp JSON stringify | 108.60 | — | — | 1187.02 (10.93x) | 406.30 (3.74x) |
| PreEpoch Timestamp JSON parse | 76.51 | — | — | 1863.45 (24.36x) | 431.14 (5.64x) |
| Max Timestamp JSON stringify | 135.56 | — | — | 1493.49 (11.02x) | 461.66 (3.41x) |
| Max Timestamp JSON parse | 94.44 | — | — | 1868.09 (19.78x) | 459.55 (4.87x) |
| Min Timestamp JSON stringify | 149.15 | — | — | 1115.67 (7.48x) | 487.55 (3.27x) |
| Min Timestamp JSON parse | 72.81 | — | — | 1840.54 (25.28x) | 450.03 (6.18x) |
| Empty JSON stringify | 28.75 | — | — | 497.56 (17.31x) | 89.84 (3.12x) |
| Empty JSON parse | 87.73 | — | — | 876.33 (9.99x) | 302.07 (3.44x) |
| Struct JSON stringify | 327.58 | — | — | 6948.92 (21.21x) | 3702.76 (11.30x) |
| Struct JSON parse | 1147.77 | — | — | 13411.00 (11.68x) | 5830.18 (5.08x) |
| Struct Escape JSON parse | 900.62 | — | — | 13438.80 (14.92x) | 5818.11 (6.46x) |
| Struct NumberExponent JSON parse | 844.12 | — | — | 13409.60 (15.89x) | 5937.96 (7.03x) |
| Struct Surrogate JSON parse | 373.42 | — | — | 5890.21 (15.77x) | 1413.56 (3.79x) |
| Struct KeySurrogate JSON parse | 373.09 | — | — | 5770.30 (15.47x) | 1543.16 (4.14x) |
| EmptyStruct JSON stringify | 40.42 | — | — | 703.45 (17.40x) | 333.56 (8.25x) |
| EmptyStruct JSON parse | 87.43 | — | — | 2431.81 (27.81x) | 343.41 (3.93x) |
| Value JSON stringify | 193.84 | — | — | 8222.37 (42.42x) | 4201.56 (21.68x) |
| Value JSON parse | 1204.69 | — | — | 14825.80 (12.31x) | 6325.24 (5.25x) |
| Value Escape JSON parse | 1260.99 | — | — | 15044.00 (11.93x) | 6346.51 (5.03x) |
| Value NumberExponent JSON parse | 868.82 | — | — | 14967.80 (17.23x) | 6315.48 (7.27x) |
| Value Surrogate JSON parse | 397.53 | — | — | 8153.50 (20.51x) | 1934.33 (4.87x) |
| Value KeySurrogate JSON parse | 397.00 | — | — | 8097.17 (20.40x) | 1843.32 (4.64x) |
| NullValue JSON stringify | 40.17 | — | — | 1663.86 (41.42x) | 232.00 (5.78x) |
| NullValue JSON parse | 70.79 | — | — | 2992.64 (42.27x) | 363.62 (5.14x) |
| StringScalarValue JSON stringify | 47.37 | — | — | 1679.10 (35.45x) | 375.14 (7.92x) |
| StringScalarValue JSON parse | 140.83 | — | — | 2452.04 (17.41x) | 461.47 (3.28x) |
| StringScalarValue Escape JSON parse | 150.99 | — | — | 2546.70 (16.87x) | 605.36 (4.01x) |
| StringScalarValue Surrogate JSON parse | 150.54 | — | — | 2558.86 (17.00x) | 625.50 (4.16x) |
| EmptyStringScalarValue JSON stringify | 45.94 | — | — | 1690.66 (36.80x) | 339.83 (7.40x) |
| EmptyStringScalarValue JSON parse | 87.62 | — | — | 2436.50 (27.81x) | 349.41 (3.99x) |
| NumberValue JSON stringify | 73.34 | — | — | 1893.25 (25.81x) | 332.61 (4.54x) |
| NumberValue JSON parse | 133.48 | — | — | 2596.81 (19.45x) | 433.06 (3.24x) |
| NumberValue Exponent JSON parse | 135.73 | — | — | 3857.89 (28.42x) | 388.61 (2.86x) |
| NegativeNumberValue JSON stringify | 148.29 | — | — | 2421.37 (16.33x) | 442.92 (2.99x) |
| NegativeNumberValue JSON parse | 164.66 | — | — | 3386.49 (20.57x) | 384.84 (2.34x) |
| ZeroNumberValue JSON stringify | 82.26 | — | — | 2506.88 (30.48x) | 293.12 (3.56x) |
| ZeroNumberValue JSON parse | 157.00 | — | — | 2986.24 (19.02x) | 350.47 (2.23x) |
| BoolScalarValue JSON stringify | 54.23 | — | — | 1623.96 (29.95x) | 267.86 (4.94x) |
| BoolScalarValue JSON parse | 84.59 | — | — | 2333.24 (27.58x) | 324.97 (3.84x) |
| FalseBoolScalarValue JSON stringify | 53.77 | — | — | 1652.73 (30.74x) | 225.33 (4.19x) |
| FalseBoolScalarValue JSON parse | 85.21 | — | — | 2263.42 (26.56x) | 407.40 (4.78x) |
| ListKindValue JSON stringify | 267.98 | — | — | 7350.57 (27.43x) | 2591.32 (9.67x) |
| ListKindValue JSON parse | 907.44 | — | — | 12519.50 (13.80x) | 4902.27 (5.40x) |
| ListKindValue Escape JSON parse | 718.18 | — | — | 12756.10 (17.76x) | 5082.02 (7.08x) |
| ListKindValue Surrogate JSON parse | 323.30 | — | — | 5782.30 (17.89x) | 1456.69 (4.51x) |
| EmptyStructKindValue JSON stringify | 42.28 | — | — | 2284.04 (54.02x) | 1038.50 (24.56x) |
| EmptyStructKindValue JSON parse | 110.42 | — | — | 4592.92 (41.60x) | 823.95 (7.46x) |
| EmptyListKindValue JSON stringify | 41.16 | — | — | 2357.98 (57.29x) | 357.97 (8.70x) |
| EmptyListKindValue JSON parse | 148.27 | — | — | 4965.71 (33.49x) | 759.71 (5.12x) |
| ListValue JSON stringify | 147.17 | — | — | 5717.03 (38.85x) | 2521.03 (17.13x) |
| ListValue JSON parse | 650.95 | — | — | 10499.10 (16.13x) | 4971.75 (7.64x) |
| ListValue Escape JSON parse | 672.97 | — | — | 10478.20 (15.57x) | 4883.95 (7.26x) |
| ListValue Surrogate JSON parse | 297.37 | — | — | 3767.40 (12.67x) | 951.13 (3.20x) |
| EmptyListValue JSON stringify | 39.93 | — | — | 830.35 (20.80x) | 179.40 (4.49x) |
| EmptyListValue JSON parse | 126.60 | — | — | 2711.52 (21.42x) | 314.48 (2.48x) |
| DoubleValue JSON stringify | 121.26 | — | — | 988.38 (8.15x) | 203.20 (1.68x) |
| DoubleValue JSON parse | 140.87 | — | — | 1448.17 (10.28x) | 313.04 (2.22x) |
| DoubleValue String JSON parse | 140.72 | — | — | 1320.58 (9.38x) | 378.43 (2.69x) |
| DoubleValue Exponent JSON parse | 147.22 | — | — | 1442.33 (9.80x) | 261.36 (1.78x) |
| NegativeDoubleValue JSON stringify | 124.30 | — | — | 958.43 (7.71x) | 187.85 (1.51x) |
| NegativeDoubleValue JSON parse | 141.77 | — | — | 1581.51 (11.16x) | 295.97 (2.09x) |
| ZeroDoubleValue JSON stringify | 70.74 | — | — | 847.18 (11.98x) | 137.43 (1.94x) |
| ZeroDoubleValue JSON parse | 132.22 | — | — | 1462.96 (11.06x) | 337.45 (2.55x) |
| DoubleValue NaN JSON stringify | 68.80 | — | — | 671.16 (9.76x) | 161.92 (2.35x) |
| DoubleValue NaN JSON parse | 128.19 | — | — | 1425.25 (11.12x) | 245.20 (1.91x) |
| DoubleValue Infinity JSON stringify | 75.01 | — | — | 720.90 (9.61x) | 128.10 (1.71x) |
| DoubleValue Infinity JSON parse | 133.23 | — | — | 1338.02 (10.04x) | 408.62 (3.07x) |
| DoubleValue NegativeInfinity JSON stringify | 75.58 | — | — | 670.20 (8.87x) | 140.00 (1.85x) |
| DoubleValue NegativeInfinity JSON parse | 110.73 | — | — | 1322.20 (11.94x) | 282.53 (2.55x) |
| FloatValue JSON stringify | 125.93 | — | — | 864.78 (6.87x) | 185.78 (1.48x) |
| FloatValue JSON parse | 138.02 | — | — | 1550.28 (11.23x) | 263.51 (1.91x) |
| FloatValue String JSON parse | 111.03 | — | — | 1337.44 (12.05x) | 337.45 (3.04x) |
| FloatValue Exponent JSON parse | 141.99 | — | — | 1475.55 (10.39x) | 340.99 (2.40x) |
| NegativeFloatValue JSON stringify | 77.00 | — | — | 983.92 (12.78x) | 185.09 (2.40x) |
| NegativeFloatValue JSON parse | 122.36 | — | — | 1498.45 (12.25x) | 291.86 (2.39x) |
| ZeroFloatValue JSON stringify | 68.51 | — | — | 749.21 (10.94x) | 196.01 (2.86x) |
| ZeroFloatValue JSON parse | 129.97 | — | — | 1404.67 (10.81x) | 242.41 (1.87x) |
| FloatValue NaN JSON stringify | 67.72 | — | — | 1000.67 (14.78x) | 146.37 (2.16x) |
| FloatValue NaN JSON parse | 106.08 | — | — | 1924.65 (18.14x) | 259.93 (2.45x) |
| FloatValue Infinity JSON stringify | 47.71 | — | — | 752.81 (15.78x) | 139.55 (2.92x) |
| FloatValue Infinity JSON parse | 106.19 | — | — | 1276.48 (12.02x) | 236.46 (2.23x) |
| FloatValue NegativeInfinity JSON stringify | 47.95 | — | — | 1333.32 (27.81x) | 184.18 (3.84x) |
| FloatValue NegativeInfinity JSON parse | 107.82 | — | — | 2199.65 (20.40x) | 251.20 (2.33x) |
| Int64Value JSON stringify | 50.03 | — | — | 1133.39 (22.65x) | 263.67 (5.27x) |
| Int64Value JSON parse | 124.72 | — | — | 1786.19 (14.32x) | 530.20 (4.25x) |
| Int64Value Number JSON parse | 126.58 | — | — | 1843.22 (14.56x) | 378.45 (2.99x) |
| Int64Value Exponent JSON parse | 116.33 | — | — | 1535.27 (13.20x) | 342.93 (2.95x) |
| ZeroInt64Value JSON stringify | 41.58 | — | — | 1282.82 (30.85x) | 200.36 (4.82x) |
| ZeroInt64Value JSON parse | 105.21 | — | — | 1468.34 (13.96x) | 414.95 (3.94x) |
| NegativeInt64Value JSON stringify | 48.60 | — | — | 1311.83 (26.99x) | 261.28 (5.38x) |
| NegativeInt64Value JSON parse | 126.53 | — | — | 2533.50 (20.02x) | 518.05 (4.09x) |
| MinInt64Value JSON stringify | 50.43 | — | — | 1386.01 (27.48x) | 272.18 (5.40x) |
| MinInt64Value JSON parse | 134.07 | — | — | 2023.47 (15.09x) | 675.18 (5.04x) |
| MaxInt64Value JSON stringify | 49.64 | — | — | 1120.89 (22.58x) | 260.73 (5.25x) |
| MaxInt64Value JSON parse | 133.19 | — | — | 2205.78 (16.56x) | 521.36 (3.91x) |
| UInt64Value JSON stringify | 50.33 | — | — | 3020.09 (60.01x) | 279.54 (5.55x) |
| UInt64Value JSON parse | 126.43 | — | — | 2841.30 (22.47x) | 498.18 (3.94x) |
| UInt64Value Number JSON parse | 126.46 | — | — | 2960.56 (23.41x) | 456.87 (3.61x) |
| UInt64Value Exponent JSON parse | 117.36 | — | — | 3102.88 (26.44x) | 341.01 (2.91x) |
| ZeroUInt64Value JSON stringify | 41.70 | — | — | 1088.05 (26.09x) | 184.73 (4.43x) |
| ZeroUInt64Value JSON parse | 106.04 | — | — | 2397.15 (22.61x) | 466.01 (4.39x) |
| MaxUInt64Value JSON stringify | 50.78 | — | — | 1422.78 (28.02x) | 376.05 (7.41x) |
| MaxUInt64Value JSON parse | 142.78 | — | — | 2223.78 (15.57x) | 454.94 (3.19x) |
| Int32Value JSON stringify | 46.08 | — | — | 1953.25 (42.39x) | 141.35 (3.07x) |
| Int32Value JSON parse | 132.62 | — | — | 2506.50 (18.90x) | 292.61 (2.21x) |
| Int32Value String JSON parse | 137.50 | — | — | 2142.83 (15.58x) | 395.91 (2.88x) |
| Int32Value Exponent JSON parse | 172.84 | — | — | 2269.66 (13.13x) | 371.91 (2.15x) |
| ZeroInt32Value JSON stringify | 62.93 | — | — | 971.10 (15.43x) | 199.07 (3.16x) |
| ZeroInt32Value JSON parse | 153.69 | — | — | 1917.25 (12.47x) | 359.75 (2.34x) |
| NegativeInt32Value JSON stringify | 63.79 | — | — | 710.53 (11.14x) | 150.05 (2.35x) |
| NegativeInt32Value JSON parse | 162.73 | — | — | 1484.39 (9.12x) | 304.65 (1.87x) |
| MinInt32Value JSON stringify | 65.06 | — | — | 655.25 (10.07x) | 150.33 (2.31x) |
| MinInt32Value JSON parse | 181.28 | — | — | 1315.73 (7.26x) | 422.82 (2.33x) |
| MaxInt32Value JSON stringify | 64.70 | — | — | 652.81 (10.09x) | 152.50 (2.36x) |
| MaxInt32Value JSON parse | 185.04 | — | — | 1565.94 (8.46x) | 323.52 (1.75x) |
| UInt32Value JSON stringify | 63.90 | — | — | 779.74 (12.20x) | 150.87 (2.36x) |
| UInt32Value JSON parse | 164.76 | — | — | 1411.54 (8.57x) | 323.53 (1.96x) |
| UInt32Value String JSON parse | 168.85 | — | — | 1140.41 (6.75x) | 385.00 (2.28x) |
| UInt32Value Exponent JSON parse | 138.09 | — | — | 1712.51 (12.40x) | 342.07 (2.48x) |
| ZeroUInt32Value JSON stringify | 46.96 | — | — | 849.28 (18.09x) | 157.32 (3.35x) |
| ZeroUInt32Value JSON parse | 153.30 | — | — | 1163.12 (7.59x) | 363.80 (2.37x) |
| MaxUInt32Value JSON stringify | 63.99 | — | — | 649.07 (10.14x) | 134.86 (2.11x) |
| MaxUInt32Value JSON parse | 168.67 | — | — | 1203.63 (7.14x) | 377.65 (2.24x) |
| BoolValue JSON stringify | 56.97 | — | — | 614.80 (10.79x) | 150.62 (2.64x) |
| BoolValue JSON parse | 72.94 | — | — | 1060.77 (14.54x) | 218.34 (2.99x) |
| FalseBoolValue JSON stringify | 57.23 | — | — | 658.76 (11.51x) | 119.58 (2.09x) |
| FalseBoolValue JSON parse | 60.55 | — | — | 1321.44 (21.82x) | 285.05 (4.71x) |
| StringValue JSON stringify | 52.51 | — | — | 686.16 (13.07x) | 179.19 (3.41x) |
| StringValue JSON parse | 146.38 | — | — | 1232.38 (8.42x) | 464.43 (3.17x) |
| StringValue Escape JSON parse | 160.21 | — | — | 1274.91 (7.96x) | 497.99 (3.11x) |
| StringValue Surrogate JSON parse | 130.12 | — | — | 1303.08 (10.01x) | 417.64 (3.21x) |
| EmptyStringValue JSON stringify | 48.55 | — | — | 643.48 (13.25x) | 182.33 (3.76x) |
| EmptyStringValue JSON parse | 66.15 | — | — | 1297.27 (19.61x) | 292.48 (4.42x) |
| BytesValue JSON stringify | 50.36 | — | — | 708.30 (14.06x) | 206.54 (4.10x) |
| BytesValue JSON parse | 124.13 | — | — | 1603.80 (12.92x) | 330.71 (2.66x) |
| BytesValue URL JSON parse | 140.09 | — | — | 1328.55 (9.48x) | 312.10 (2.23x) |
| BytesValue StandardBase64 JSON parse | 122.76 | — | — | 1415.46 (11.53x) | 363.42 (2.96x) |
| BytesValue Unpadded JSON parse | 122.42 | — | — | 1401.03 (11.44x) | 304.46 (2.49x) |
| EmptyBytesValue JSON stringify | 41.95 | — | — | 644.91 (15.37x) | 183.78 (4.38x) |
| EmptyBytesValue JSON parse | 67.95 | — | — | 1250.83 (18.41x) | 374.98 (5.52x) |
| TextFormat format | 181.41 | — | — | 3003.02 (16.55x) | 2632.38 (14.51x) |
| TextFormat parse | 713.98 | — | — | 5915.13 (8.28x) | 8317.82 (11.65x) |
| packed fixed32 encode | 2.01 | 554.46 (275.85x) | 579.12 (288.12x) | 43.83 (21.80x) | 780.61 (388.36x) |
| packed fixed32 decode | 8.83 | 1209.03 (136.92x) | 2287.68 (259.08x) | 58.36 (6.61x) | 2030.85 (229.99x) |
| packed fixed64 encode | 2.01 | 634.04 (315.44x) | 567.11 (282.14x) | 76.09 (37.85x) | 543.25 (270.27x) |
| packed fixed64 decode | 4.51 | 1234.12 (273.64x) | 8609.67 (1909.02x) | 79.63 (17.66x) | 2782.44 (616.95x) |
| packed sfixed32 encode | 2.72 | 604.88 (222.38x) | 539.76 (198.44x) | 57.61 (21.18x) | 397.76 (146.24x) |
| packed sfixed32 decode | 7.68 | 1235.05 (160.81x) | 2282.20 (297.16x) | 51.39 (6.69x) | 2024.80 (263.65x) |
| packed sfixed64 encode | 2.88 | 573.82 (199.24x) | 561.40 (194.93x) | 76.16 (26.44x) | 432.80 (150.28x) |
| packed sfixed64 decode | 8.91 | 1291.56 (144.96x) | 8539.85 (958.46x) | 96.26 (10.80x) | 3007.46 (337.54x) |
| packed float encode | 2.01 | 835.90 (415.87x) | 542.78 (270.04x) | 52.32 (26.03x) | 391.13 (194.59x) |
| packed float decode | 4.54 | 1298.84 (286.09x) | 2425.65 (534.28x) | 48.98 (10.79x) | 2434.97 (536.34x) |
| packed double encode | 2.79 | 842.70 (302.04x) | 693.52 (248.57x) | 75.70 (27.13x) | 356.63 (127.82x) |
| packed double decode | 4.54 | 1069.22 (235.51x) | 2421.46 (533.36x) | 89.93 (19.81x) | 2838.63 (625.25x) |
| packed uint64 encode | 1292.54 | 5521.11 (4.27x) | 4984.85 (3.86x) | 2628.72 (2.03x) | 4315.89 (3.34x) |
| packed uint64 decode | 1797.09 | 3623.02 (2.02x) | 9886.50 (5.50x) | 4861.70 (2.71x) | 8853.01 (4.93x) |
| packed uint32 encode | 1240.46 | 4317.39 (3.48x) | 3900.30 (3.14x) | 2177.94 (1.76x) | 3565.55 (2.87x) |
| packed uint32 decode | 1763.47 | 3043.75 (1.73x) | 3815.54 (2.16x) | 2388.98 (1.35x) | 7055.92 (4.00x) |
| packed int64 encode | 1400.74 | 15386.42 (10.98x) | 7525.29 (5.37x) | 3710.36 (2.65x) | 5097.51 (3.64x) |
| packed int64 decode | 2757.39 | 4385.59 (1.59x) | 11553.05 (4.19x) | 5607.43 (2.03x) | 11249.24 (4.08x) |
| packed sint32 encode | 845.08 | 3707.28 (4.39x) | 3566.12 (4.22x) | 1965.10 (2.33x) | 4245.76 (5.02x) |
| packed sint32 decode | 1125.68 | 3256.88 (2.89x) | 3788.10 (3.37x) | 1454.13 (1.29x) | 4728.79 (4.20x) |
| packed sint64 encode | 1478.83 | 5866.52 (3.97x) | 5401.93 (3.65x) | 2877.70 (1.95x) | 5082.52 (3.44x) |
| packed sint64 decode | 2041.48 | 3812.96 (1.87x) | 10746.00 (5.26x) | 3598.58 (1.76x) | 9735.73 (4.77x) |
| packed bool encode | 2.01 | 1649.74 (820.77x) | 522.19 (259.80x) | 15.93 (7.93x) | 2663.55 (1325.15x) |
| packed bool decode | 263.02 | 1897.68 (7.21x) | 3142.80 (11.95x) | 817.32 (3.11x) | 1981.84 (7.53x) |
| packed enum encode | 430.03 | 3331.18 (7.75x) | 2025.11 (4.71x) | 1110.42 (2.58x) | 3048.47 (7.09x) |
| packed enum decode | 160.42 | 1888.88 (11.77x) | 3313.32 (20.65x) | 707.43 (4.41x) | 2922.29 (18.22x) |
| large map encode | 4752.76 | 16802.31 (3.54x) | 9680.35 (2.04x) | 25403.10 (5.34x) | 240010.25 (50.50x) |
| shuffled large map deterministic binary encode | 35299.84 | — | — | 104668.00 (2.97x) | 444359.58 (12.59x) |
| large map decode | 29681.52 | 109915.20 (3.70x) | 111857.67 (3.77x) | 102662.00 (3.46x) | 355755.09 (11.99x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON (including generated `map<string, int32>` surrogate-pair key parse, null-field parse, ignore-unknown parse, enum-name parse, always-print default-value stringify, enum-number stringify, proto-name stringify, proto-name parse, open-enum numeric parse, and integer numeric-exponent parse), Any/WKT JSON (including embedded zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound `Duration`, non-empty/escaped-input parse/number-exponent parse/surrogate-pair value parse/surrogate-pair key parse and empty `Struct`, object/escaped-object parse/object-number-exponent/object-surrogate-pair value parse/object-surrogate-pair key parse/list/escaped-list/surrogate-list/string-scalar/escaped-string-scalar/surrogate-string-scalar/number-exponent/negative-number `Value` (including default-like scalar and empty object/list kinds),
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
