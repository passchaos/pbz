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

Latest accepted comparison (`/tmp/pbz-compare-string-number-json-final.log`,
summarized in `/tmp/pbz-summary-string-number-json-final.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Pivoted rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 29.96 | 124.43 (4.15x) | 51.81 (1.73x) | 104.17 (3.48x) | 914.48 (30.52x) |
| binary decode | 132.51 | 249.55 (1.88x) | 266.03 (2.01x) | 208.96 (1.58x) | 961.77 (7.26x) |
| unknown fields count by number | 3.57 | — | — | 162.99 (45.66x) | — |
| deterministic binary encode | 71.61 | — | — | 127.03 (1.77x) | 1371.38 (19.15x) |
| scalarmix encode | 18.39 | 145.84 (7.93x) | 46.48 (2.53x) | 51.16 (2.78x) | 216.28 (11.76x) |
| scalarmix decode | 59.52 | 135.66 (2.28x) | 188.50 (3.17x) | 84.65 (1.42x) | 291.84 (4.90x) |
| textbytes encode | 9.53 | 78.39 (8.23x) | 40.28 (4.23x) | 135.75 (14.24x) | 149.97 (15.74x) |
| textbytes decode | 41.57 | 408.60 (9.83x) | 237.06 (5.70x) | 171.22 (4.12x) | 591.46 (14.23x) |
| largebytes encode | 25.83 | 2759.56 (106.84x) | 2722.47 (105.40x) | 2732.05 (105.77x) | 2779.74 (107.62x) |
| largebytes decode | 89.57 | 6088.11 (67.97x) | 3273.33 (36.54x) | 2802.08 (31.28x) | 29112.77 (325.03x) |
| presencemix encode | 16.82 | 56.77 (3.38x) | 30.72 (1.83x) | 57.53 (3.42x) | 223.38 (13.28x) |
| presencemix decode | 56.17 | 158.65 (2.82x) | 129.19 (2.30x) | 163.87 (2.92x) | 507.66 (9.04x) |
| PresenceMix JSON stringify | 133.28 | — | — | 3754.51 (28.17x) | 2930.70 (21.99x) |
| PresenceMix JSON parse | 1361.70 | — | — | 7554.08 (5.55x) | 3578.86 (2.63x) |
| complex encode | 50.45 | 156.81 (3.11x) | 95.05 (1.88x) | 169.07 (3.35x) | 998.39 (19.79x) |
| complex decode | 173.23 | 406.66 (2.35x) | 356.50 (2.06x) | 405.99 (2.34x) | 1764.04 (10.18x) |
| complex deterministic binary encode | 93.30 | — | — | 231.14 (2.48x) | 1178.22 (12.63x) |
| complex JSON stringify | 260.15 | — | — | 5907.53 (22.71x) | 7214.22 (27.73x) |
| complex JSON parse | 2574.79 | — | — | 14926.80 (5.80x) | 8900.31 (3.46x) |
| Complex ProtoName JSON stringify | 411.79 | — | — | 6417.41 (15.58x) | 7612.57 (18.49x) |
| Complex ProtoName JSON parse | 2583.84 | — | — | 15216.90 (5.89x) | 8783.78 (3.40x) |
| complex TextFormat format | 250.75 | — | — | 4685.47 (18.69x) | 6164.95 (24.59x) |
| complex TextFormat parse | 3219.92 | — | — | 8447.67 (2.62x) | 9827.89 (3.05x) |
| packed int32 encode | 860.40 | 3828.70 (4.45x) | 2848.84 (3.31x) | 1609.33 (1.87x) | 3532.11 (4.11x) |
| packed int32 decode | 927.69 | 2382.56 (2.57x) | 3700.76 (3.99x) | 1181.62 (1.27x) | 3438.30 (3.71x) |
| JSON stringify | 161.71 | — | — | 3719.35 (23.00x) | 2492.66 (15.41x) |
| AlwaysPrint JSON stringify | 60.60 | — | — | 3240.53 (53.47x) | 1773.81 (29.27x) |
| ProtoName JSON stringify | 327.10 | — | — | 5730.37 (17.52x) | 4274.86 (13.07x) |
| EnumNumber JSON stringify | 291.70 | — | — | 5771.67 (19.79x) | 4403.96 (15.10x) |
| JSON parse | 1485.35 | — | — | 9191.34 (6.19x) | 4884.58 (3.29x) |
| MapKeySurrogate JSON parse | 642.61 | — | — | 4367.54 (6.80x) | 1077.73 (1.68x) |
| NullFields JSON parse | 599.47 | — | — | 2470.03 (4.12x) | 776.71 (1.30x) |
| IgnoreUnknown JSON parse | 1212.98 | — | — | 6682.30 (5.51x) | 2892.66 (2.38x) |
| OpenEnum JSON parse | 297.38 | — | — | 4588.52 (15.43x) | 485.64 (1.63x) |
| EnumName JSON parse | 296.01 | — | — | 4617.51 (15.60x) | 427.47 (1.44x) |
| ProtoName JSON parse | 523.98 | — | — | 5027.23 (9.59x) | 1249.28 (2.38x) |
| IntExponent JSON parse | 1688.70 | — | — | 9247.41 (5.48x) | 4892.52 (2.90x) |
| StringNumber JSON parse | 1805.30 | — | — | 8664.56 (4.80x) | 5065.91 (2.81x) |
| Any WKT JSON stringify | 127.30 | — | — | 2267.80 (17.81x) | 1016.76 (7.99x) |
| Any WKT JSON parse | 527.51 | — | — | 5106.92 (9.68x) | 1757.04 (3.33x) |
| Any Duration Escape WKT JSON parse | 788.77 | — | — | 5981.08 (7.58x) | 1994.99 (2.53x) |
| Any PlusDuration WKT JSON parse | 858.73 | — | — | 4602.80 (5.36x) | 1802.83 (2.10x) |
| Any ShortFractionDuration WKT JSON parse | 687.97 | — | — | 3840.44 (5.58x) | 1680.25 (2.44x) |
| Any MicroDuration WKT JSON stringify | 132.58 | — | — | 2288.69 (17.26x) | 967.43 (7.30x) |
| Any MicroDuration WKT JSON parse | 531.27 | — | — | 3880.85 (7.30x) | 1855.78 (3.49x) |
| Any NanoDuration WKT JSON stringify | 128.59 | — | — | 2408.57 (18.73x) | 1025.33 (7.97x) |
| Any NanoDuration WKT JSON parse | 534.65 | — | — | 3754.62 (7.02x) | 1863.53 (3.49x) |
| Any NegativeDuration WKT JSON stringify | 130.99 | — | — | 2423.57 (18.50x) | 1301.11 (9.93x) |
| Any NegativeDuration WKT JSON parse | 532.78 | — | — | 3890.78 (7.30x) | 1807.58 (3.39x) |
| Any FractionalNegativeDuration WKT JSON stringify | 126.72 | — | — | 2344.16 (18.50x) | 1137.17 (8.97x) |
| Any FractionalNegativeDuration WKT JSON parse | 526.67 | — | — | 3809.33 (7.23x) | 1684.70 (3.20x) |
| Any MaxDuration WKT JSON stringify | 119.45 | — | — | 2190.53 (18.34x) | 1015.33 (8.50x) |
| Any MaxDuration WKT JSON parse | 543.71 | — | — | 3779.47 (6.95x) | 1811.04 (3.33x) |
| Any MinDuration WKT JSON stringify | 121.73 | — | — | 2178.21 (17.89x) | 1303.70 (10.71x) |
| Any MinDuration WKT JSON parse | 737.76 | — | — | 3904.72 (5.29x) | 1789.03 (2.42x) |
| Any ZeroDuration WKT JSON stringify | 204.56 | — | — | 1090.23 (5.33x) | 940.94 (4.60x) |
| Any ZeroDuration WKT JSON parse | 754.67 | — | — | 2811.33 (3.73x) | 1610.15 (2.13x) |
| Any FieldMask WKT JSON stringify | 300.27 | — | — | 2243.75 (7.47x) | 2974.39 (9.91x) |
| Any FieldMask WKT JSON parse | 928.72 | — | — | 3915.78 (4.22x) | 6390.41 (6.88x) |
| Any FieldMask Escape WKT JSON parse | 738.61 | — | — | 4112.50 (5.57x) | 10448.22 (14.15x) |
| Any EmptyFieldMask WKT JSON stringify | 111.76 | — | — | 1078.67 (9.65x) | 3050.56 (27.30x) |
| Any EmptyFieldMask WKT JSON parse | 454.96 | — | — | 2708.86 (5.95x) | 4812.75 (10.58x) |
| Any Timestamp WKT JSON stringify | 171.91 | — | — | 2541.43 (14.78x) | 1806.20 (10.51x) |
| Any Timestamp WKT JSON parse | 573.29 | — | — | 3783.34 (6.60x) | 2124.79 (3.71x) |
| Any Timestamp Escape WKT JSON parse | 594.64 | — | — | 3833.59 (6.45x) | 3263.24 (5.49x) |
| Any ShortFraction Timestamp WKT JSON parse | 779.84 | — | — | 3829.84 (4.91x) | 4985.47 (6.39x) |
| Any Micro Timestamp WKT JSON stringify | 385.29 | — | — | 2408.62 (6.25x) | 2712.20 (7.04x) |
| Any Micro Timestamp WKT JSON parse | 848.72 | — | — | 3819.77 (4.50x) | 4771.36 (5.62x) |
| Any Nano Timestamp WKT JSON stringify | 213.65 | — | — | 2574.57 (12.05x) | 2860.13 (13.39x) |
| Any Nano Timestamp WKT JSON parse | 583.86 | — | — | 3905.27 (6.69x) | 2399.97 (4.11x) |
| Any Offset Timestamp WKT JSON parse | 591.00 | — | — | 3900.83 (6.60x) | 1875.05 (3.17x) |
| Any PreEpoch Timestamp WKT JSON stringify | 141.28 | — | — | 2494.56 (17.66x) | 1988.45 (14.07x) |
| Any PreEpoch Timestamp WKT JSON parse | 565.30 | — | — | 3904.40 (6.91x) | 2516.67 (4.45x) |
| Any Max Timestamp WKT JSON stringify | 157.22 | — | — | 2525.28 (16.06x) | 1214.92 (7.73x) |
| Any Max Timestamp WKT JSON parse | 585.46 | — | — | 3890.61 (6.65x) | 2160.28 (3.69x) |
| Any Min Timestamp WKT JSON stringify | 152.68 | — | — | 2449.08 (16.04x) | 1535.59 (10.06x) |
| Any Min Timestamp WKT JSON parse | 564.09 | — | — | 3794.21 (6.73x) | 3320.16 (5.89x) |
| Any Empty WKT JSON stringify | 89.28 | — | — | 997.66 (11.17x) | 1367.55 (15.32x) |
| Any Empty WKT JSON parse | 457.76 | — | — | 2595.15 (5.67x) | 3856.90 (8.43x) |
| Any Struct WKT JSON stringify | 1163.98 | — | — | 7290.70 (6.26x) | 8217.42 (7.06x) |
| Any Struct WKT JSON parse | 1770.75 | — | — | 13996.90 (7.90x) | 16160.19 (9.13x) |
| Any Struct Escape WKT JSON parse | 1791.70 | — | — | 14113.50 (7.88x) | 12245.46 (6.83x) |
| Any Struct NumberExponent WKT JSON parse | 2459.86 | — | — | 14042.60 (5.71x) | 9845.44 (4.00x) |
| Any Struct Surrogate WKT JSON parse | 775.22 | — | — | 7938.72 (10.24x) | 4402.46 (5.68x) |
| Any Struct KeySurrogate WKT JSON parse | 774.97 | — | — | 7935.10 (10.24x) | 3976.00 (5.13x) |
| Any EmptyStruct WKT JSON stringify | 113.48 | — | — | 1208.37 (10.65x) | 1182.70 (10.42x) |
| Any EmptyStruct WKT JSON parse | 445.99 | — | — | 2785.87 (6.25x) | 2089.77 (4.69x) |
| Any Value WKT JSON stringify | 652.07 | — | — | 7329.28 (11.24x) | 8395.32 (12.87x) |
| Any Value WKT JSON parse | 2154.52 | — | — | 14937.10 (6.93x) | 11108.11 (5.16x) |
| Any Value Escape WKT JSON parse | 1843.16 | — | — | 16109.30 (8.74x) | 11945.59 (6.48x) |
| Any Value NumberExponent WKT JSON parse | 1823.43 | — | — | 14648.90 (8.03x) | 10861.73 (5.96x) |
| Any Value Surrogate WKT JSON parse | 1158.63 | — | — | 8342.73 (7.20x) | 4075.09 (3.52x) |
| Any Value KeySurrogate WKT JSON parse | 1074.17 | — | — | 8218.69 (7.65x) | 4023.67 (3.75x) |
| Any NullValue WKT JSON stringify | 121.69 | — | — | 2728.22 (22.42x) | 1041.60 (8.56x) |
| Any NullValue WKT JSON parse | 466.34 | — | — | 5079.97 (10.89x) | 1750.36 (3.75x) |
| Any StringScalarValue WKT JSON stringify | 146.65 | — | — | 2773.80 (18.91x) | 1058.43 (7.22x) |
| Any StringScalarValue WKT JSON parse | 522.01 | — | — | 4470.37 (8.56x) | 1915.39 (3.67x) |
| Any StringScalarValue Escape WKT JSON parse | 537.27 | — | — | 4591.73 (8.55x) | 2086.43 (3.88x) |
| Any StringScalarValue Surrogate WKT JSON parse | 539.50 | — | — | 4781.79 (8.86x) | 2063.39 (3.82x) |
| Any EmptyStringScalarValue WKT JSON stringify | 133.89 | — | — | 2728.78 (20.38x) | 1220.40 (9.11x) |
| Any EmptyStringScalarValue WKT JSON parse | 492.89 | — | — | 4522.83 (9.18x) | 1731.96 (3.51x) |
| Any NumberValue WKT JSON stringify | 357.60 | — | — | 3125.76 (8.74x) | 1072.67 (3.00x) |
| Any NumberValue WKT JSON parse | 680.40 | — | — | 4531.15 (6.66x) | 1805.01 (2.65x) |
| Any NumberValue Exponent WKT JSON parse | 650.23 | — | — | 4599.50 (7.07x) | 1796.13 (2.76x) |
| Any NegativeNumberValue WKT JSON stringify | 314.34 | — | — | 3109.77 (9.89x) | 1098.51 (3.49x) |
| Any NegativeNumberValue WKT JSON parse | 512.65 | — | — | 4517.51 (8.81x) | 1756.03 (3.43x) |
| Any ZeroNumberValue WKT JSON stringify | 132.15 | — | — | 3161.91 (23.93x) | 1080.73 (8.18x) |
| Any ZeroNumberValue WKT JSON parse | 508.30 | — | — | 4585.38 (9.02x) | 1886.71 (3.71x) |
| Any BoolScalarValue WKT JSON stringify | 125.13 | — | — | 3088.42 (24.68x) | 898.94 (7.18x) |
| Any BoolScalarValue WKT JSON parse | 468.51 | — | — | 4621.86 (9.87x) | 1755.70 (3.75x) |
| Any FalseBoolScalarValue WKT JSON stringify | 122.94 | — | — | 2884.94 (23.47x) | 993.33 (8.08x) |
| Any FalseBoolScalarValue WKT JSON parse | 466.22 | — | — | 4623.75 (9.92x) | 1780.98 (3.82x) |
| Any ListKindValue WKT JSON stringify | 506.64 | — | — | 6923.75 (13.67x) | 5760.45 (11.37x) |
| Any ListKindValue WKT JSON parse | 1913.92 | — | — | 14261.30 (7.45x) | 8052.01 (4.21x) |
| Any ListKindValue Escape WKT JSON parse | 1430.55 | — | — | 12708.60 (8.88x) | 8475.62 (5.92x) |
| Any ListKindValue Surrogate WKT JSON parse | 730.60 | — | — | 5859.47 (8.02x) | 3103.00 (4.25x) |
| Any EmptyStructKindValue WKT JSON stringify | 141.36 | — | — | 3574.97 (25.29x) | 1578.30 (11.17x) |
| Any EmptyStructKindValue WKT JSON parse | 503.19 | — | — | 6687.84 (13.29x) | 2276.05 (4.52x) |
| Any EmptyListKindValue WKT JSON stringify | 144.95 | — | — | 3599.84 (24.84x) | 1422.36 (9.81x) |
| Any EmptyListKindValue WKT JSON parse | 510.64 | — | — | 5415.72 (10.61x) | 2059.59 (4.03x) |
| Any DoubleValue WKT JSON stringify | 366.72 | — | — | 2154.81 (5.88x) | 1165.54 (3.18x) |
| Any DoubleValue WKT JSON parse | 854.45 | — | — | 3406.02 (3.99x) | 1406.80 (1.65x) |
| Any DoubleValue String WKT JSON parse | 715.68 | — | — | 3422.60 (4.78x) | 1746.54 (2.44x) |
| Any DoubleValue Exponent WKT JSON parse | 633.36 | — | — | 3455.81 (5.46x) | 1736.72 (2.74x) |
| Any NegativeDoubleValue WKT JSON stringify | 191.76 | — | — | 2211.25 (11.53x) | 926.53 (4.83x) |
| Any NegativeDoubleValue WKT JSON parse | 536.94 | — | — | 3428.35 (6.38x) | 1686.99 (3.14x) |
| Any ZeroDoubleValue WKT JSON stringify | 152.48 | — | — | 1045.97 (6.86x) | 704.78 (4.62x) |
| Any ZeroDoubleValue WKT JSON parse | 535.91 | — | — | 2558.75 (4.77x) | 1520.08 (2.84x) |
| Any DoubleValue NaN WKT JSON stringify | 155.40 | — | — | 1898.86 (12.22x) | 757.85 (4.88x) |
| Any DoubleValue NaN WKT JSON parse | 532.33 | — | — | 3297.63 (6.19x) | 1540.27 (2.89x) |
| Any DoubleValue Infinity WKT JSON stringify | 159.72 | — | — | 1896.38 (11.87x) | 682.13 (4.27x) |
| Any DoubleValue Infinity WKT JSON parse | 534.81 | — | — | 3337.39 (6.24x) | 1511.38 (2.83x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 245.94 | — | — | 1942.02 (7.90x) | 715.44 (2.91x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 834.19 | — | — | 3338.74 (4.00x) | 1639.05 (1.96x) |
| Any FloatValue WKT JSON stringify | 242.55 | — | — | 2086.79 (8.60x) | 871.25 (3.59x) |
| Any FloatValue WKT JSON parse | 546.18 | — | — | 3376.02 (6.18x) | 1652.44 (3.03x) |
| Any FloatValue String WKT JSON parse | 697.56 | — | — | 3367.21 (4.83x) | 1841.26 (2.64x) |
| Any FloatValue Exponent WKT JSON parse | 537.33 | — | — | 3416.42 (6.36x) | 1685.74 (3.14x) |
| Any NegativeFloatValue WKT JSON stringify | 194.87 | — | — | 2092.56 (10.74x) | 905.25 (4.65x) |
| Any NegativeFloatValue WKT JSON parse | 532.76 | — | — | 3381.02 (6.35x) | 1622.74 (3.05x) |
| Any ZeroFloatValue WKT JSON stringify | 153.99 | — | — | 964.84 (6.27x) | 710.45 (4.61x) |
| Any ZeroFloatValue WKT JSON parse | 531.02 | — | — | 2522.91 (4.75x) | 1649.73 (3.11x) |
| Any FloatValue NaN WKT JSON stringify | 152.67 | — | — | 1916.87 (12.56x) | 811.27 (5.31x) |
| Any FloatValue NaN WKT JSON parse | 526.11 | — | — | 3273.73 (6.22x) | 1458.03 (2.77x) |
| Any FloatValue Infinity WKT JSON stringify | 159.05 | — | — | 1930.21 (12.14x) | 679.55 (4.27x) |
| Any FloatValue Infinity WKT JSON parse | 831.34 | — | — | 3317.56 (3.99x) | 1622.47 (1.95x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 261.48 | — | — | 1874.98 (7.17x) | 697.28 (2.67x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 725.87 | — | — | 3296.73 (4.54x) | 1594.55 (2.20x) |
| Any Int64Value WKT JSON stringify | 201.70 | — | — | 1904.05 (9.44x) | 979.47 (4.86x) |
| Any Int64Value WKT JSON parse | 727.52 | — | — | 3432.84 (4.72x) | 1876.28 (2.58x) |
| Any Int64Value Number WKT JSON parse | 564.68 | — | — | 3446.93 (6.10x) | 1812.32 (3.21x) |
| Any Int64Value Exponent WKT JSON parse | 547.05 | — | — | 3371.08 (6.16x) | 1824.99 (3.34x) |
| Any ZeroInt64Value WKT JSON stringify | 151.70 | — | — | 1075.90 (7.09x) | 939.19 (6.19x) |
| Any ZeroInt64Value WKT JSON parse | 534.93 | — | — | 2598.83 (4.86x) | 1595.80 (2.98x) |
| Any NegativeInt64Value WKT JSON stringify | 173.23 | — | — | 2621.22 (15.13x) | 795.86 (4.59x) |
| Any NegativeInt64Value WKT JSON parse | 564.46 | — | — | 4754.82 (8.42x) | 1967.88 (3.49x) |
| Any MinInt64Value WKT JSON stringify | 172.21 | — | — | 2293.01 (13.32x) | 905.96 (5.26x) |
| Any MinInt64Value WKT JSON parse | 929.69 | — | — | 3501.76 (3.77x) | 1904.66 (2.05x) |
| Any MaxInt64Value WKT JSON stringify | 271.89 | — | — | 1904.99 (7.01x) | 849.01 (3.12x) |
| Any MaxInt64Value WKT JSON parse | 796.28 | — | — | 3468.82 (4.36x) | 1984.05 (2.49x) |
| Any UInt64Value WKT JSON stringify | 178.41 | — | — | 1911.52 (10.71x) | 923.45 (5.18x) |
| Any UInt64Value WKT JSON parse | 569.89 | — | — | 3481.06 (6.11x) | 1874.87 (3.29x) |
| Any UInt64Value Number WKT JSON parse | 567.48 | — | — | 3436.62 (6.06x) | 1745.13 (3.08x) |
| Any UInt64Value Exponent WKT JSON parse | 552.92 | — | — | 3409.01 (6.17x) | 1678.88 (3.04x) |
| Any ZeroUInt64Value WKT JSON stringify | 164.92 | — | — | 998.97 (6.06x) | 782.86 (4.75x) |
| Any ZeroUInt64Value WKT JSON parse | 538.72 | — | — | 2492.49 (4.63x) | 1750.15 (3.25x) |
| Any MaxUInt64Value WKT JSON stringify | 179.62 | — | — | 1887.86 (10.51x) | 830.67 (4.62x) |
| Any MaxUInt64Value WKT JSON parse | 574.30 | — | — | 3525.79 (6.14x) | 1780.19 (3.10x) |
| Any Int32Value WKT JSON stringify | 272.14 | — | — | 1873.94 (6.89x) | 860.86 (3.16x) |
| Any Int32Value WKT JSON parse | 877.89 | — | — | 3329.08 (3.79x) | 1651.97 (1.88x) |
| Any Int32Value String WKT JSON parse | 757.32 | — | — | 3338.03 (4.41x) | 1725.70 (2.28x) |
| Any Int32Value Exponent WKT JSON parse | 700.81 | — | — | 3347.59 (4.78x) | 1719.13 (2.45x) |
| Any ZeroInt32Value WKT JSON stringify | 168.89 | — | — | 980.30 (5.80x) | 913.34 (5.41x) |
| Any ZeroInt32Value WKT JSON parse | 538.14 | — | — | 2551.85 (4.74x) | 1621.35 (3.01x) |
| Any NegativeInt32Value WKT JSON stringify | 173.95 | — | — | 1894.65 (10.89x) | 909.30 (5.23x) |
| Any NegativeInt32Value WKT JSON parse | 545.76 | — | — | 3330.04 (6.10x) | 1849.41 (3.39x) |
| Any MinInt32Value WKT JSON stringify | 173.49 | — | — | 1891.47 (10.90x) | 801.26 (4.62x) |
| Any MinInt32Value WKT JSON parse | 552.05 | — | — | 3379.34 (6.12x) | 1676.64 (3.04x) |
| Any MaxInt32Value WKT JSON stringify | 171.97 | — | — | 1887.45 (10.98x) | 825.91 (4.80x) |
| Any MaxInt32Value WKT JSON parse | 551.95 | — | — | 3338.64 (6.05x) | 1554.66 (2.82x) |
| Any UInt32Value WKT JSON stringify | 274.44 | — | — | 1892.39 (6.90x) | 708.03 (2.58x) |
| Any UInt32Value WKT JSON parse | 896.02 | — | — | 3323.78 (3.71x) | 1692.64 (1.89x) |
| Any UInt32Value String WKT JSON parse | 726.57 | — | — | 3337.24 (4.59x) | 1710.01 (2.35x) |
| Any UInt32Value Exponent WKT JSON parse | 614.30 | — | — | 3388.80 (5.52x) | 1705.83 (2.78x) |
| Any ZeroUInt32Value WKT JSON stringify | 173.81 | — | — | 1047.46 (6.03x) | 816.17 (4.70x) |
| Any ZeroUInt32Value WKT JSON parse | 545.41 | — | — | 2599.94 (4.77x) | 1746.65 (3.20x) |
| Any MaxUInt32Value WKT JSON stringify | 175.99 | — | — | 2501.50 (14.21x) | 835.18 (4.75x) |
| Any MaxUInt32Value WKT JSON parse | 558.96 | — | — | 4668.86 (8.35x) | 1742.26 (3.12x) |
| Any BoolValue WKT JSON stringify | 167.65 | — | — | 2586.89 (15.43x) | 896.55 (5.35x) |
| Any BoolValue WKT JSON parse | 497.48 | — | — | 3352.79 (6.74x) | 1381.19 (2.78x) |
| Any FalseBoolValue WKT JSON stringify | 167.87 | — | — | 1151.67 (6.86x) | 909.65 (5.42x) |
| Any FalseBoolValue WKT JSON parse | 496.22 | — | — | 2542.13 (5.12x) | 1508.62 (3.04x) |
| Any StringValue WKT JSON stringify | 252.65 | — | — | 1927.11 (7.63x) | 780.21 (3.09x) |
| Any StringValue WKT JSON parse | 887.12 | — | — | 3351.69 (3.78x) | 1534.20 (1.73x) |
| Any StringValue Escape WKT JSON parse | 721.42 | — | — | 3374.15 (4.68x) | 1671.55 (2.32x) |
| Any StringValue Surrogate WKT JSON parse | 673.66 | — | — | 3364.44 (4.99x) | 1766.25 (2.62x) |
| Any EmptyStringValue WKT JSON stringify | 175.63 | — | — | 992.18 (5.65x) | 722.42 (4.11x) |
| Any EmptyStringValue WKT JSON parse | 527.27 | — | — | 2500.64 (4.74x) | 1572.47 (2.98x) |
| Any BytesValue WKT JSON stringify | 183.09 | — | — | 1945.85 (10.63x) | 805.50 (4.40x) |
| Any BytesValue WKT JSON parse | 578.04 | — | — | 3370.49 (5.83x) | 1796.17 (3.11x) |
| Any BytesValue URL WKT JSON parse | 595.35 | — | — | 3351.79 (5.63x) | 1748.88 (2.94x) |
| Any BytesValue StandardBase64 WKT JSON parse | 581.40 | — | — | 3392.18 (5.83x) | 1707.44 (2.94x) |
| Any BytesValue Unpadded WKT JSON parse | 579.83 | — | — | 3352.53 (5.78x) | 1670.99 (2.88x) |
| Any EmptyBytesValue WKT JSON stringify | 260.81 | — | — | 1001.22 (3.84x) | 863.61 (3.31x) |
| Any EmptyBytesValue WKT JSON parse | 787.76 | — | — | 2633.83 (3.34x) | 1583.30 (2.01x) |
| Nested Any WKT JSON stringify | 380.06 | — | — | 3122.55 (8.22x) | 1851.75 (4.87x) |
| Nested Any WKT JSON parse | 879.08 | — | — | 5249.81 (5.97x) | 3377.98 (3.84x) |
| Duration JSON stringify | 58.36 | — | — | 1038.65 (17.80x) | 336.43 (5.76x) |
| Duration JSON parse | 19.57 | — | — | 1785.59 (91.24x) | 379.20 (19.38x) |
| Duration Escape JSON parse | 42.50 | — | — | 1840.64 (43.31x) | 429.33 (10.10x) |
| PlusDuration JSON parse | 19.21 | — | — | 1800.29 (93.72x) | 349.27 (18.18x) |
| ShortFractionDuration JSON parse | 15.05 | — | — | 1792.27 (119.09x) | 518.15 (34.43x) |
| MicroDuration JSON stringify | 59.48 | — | — | 1237.67 (20.81x) | 374.77 (6.30x) |
| MicroDuration JSON parse | 20.32 | — | — | 1804.86 (88.82x) | 357.34 (17.59x) |
| NanoDuration JSON stringify | 57.16 | — | — | 1128.97 (19.75x) | 378.50 (6.62x) |
| NanoDuration JSON parse | 24.30 | — | — | 1880.07 (77.37x) | 365.83 (15.05x) |
| NegativeDuration JSON stringify | 58.17 | — | — | 1116.88 (19.20x) | 604.65 (10.39x) |
| NegativeDuration JSON parse | 18.69 | — | — | 1847.41 (98.84x) | 351.41 (18.80x) |
| FractionalNegativeDuration JSON stringify | 58.18 | — | — | 1159.00 (19.92x) | 401.52 (6.90x) |
| FractionalNegativeDuration JSON parse | 19.50 | — | — | 1797.53 (92.18x) | 331.74 (17.01x) |
| MaxDuration JSON stringify | 49.75 | — | — | 922.92 (18.55x) | 512.57 (10.30x) |
| MaxDuration JSON parse | 35.11 | — | — | 1776.76 (50.61x) | 355.29 (10.12x) |
| MinDuration JSON stringify | 50.02 | — | — | 899.86 (17.99x) | 408.17 (8.16x) |
| MinDuration JSON parse | 36.10 | — | — | 1841.34 (51.01x) | 374.40 (10.37x) |
| ZeroDuration JSON stringify | 44.88 | — | — | 837.10 (18.65x) | 330.58 (7.37x) |
| ZeroDuration JSON parse | 15.15 | — | — | 1712.50 (113.04x) | 271.76 (17.94x) |
| FieldMask JSON stringify | 99.63 | — | — | 982.24 (9.86x) | 629.25 (6.32x) |
| FieldMask JSON parse | 143.81 | — | — | 2016.32 (14.02x) | 994.73 (6.92x) |
| FieldMask Escape JSON parse | 192.89 | — | — | 2080.89 (10.79x) | 1155.11 (5.99x) |
| EmptyFieldMask JSON stringify | 40.66 | — | — | 653.96 (16.08x) | 199.73 (4.91x) |
| EmptyFieldMask JSON parse | 4.79 | — | — | 1081.27 (225.73x) | 147.90 (30.88x) |
| Timestamp JSON stringify | 96.29 | — | — | 1475.49 (15.32x) | 412.25 (4.28x) |
| Timestamp JSON parse | 45.19 | — | — | 1813.52 (40.13x) | 414.14 (9.16x) |
| Timestamp Escape JSON parse | 90.88 | — | — | 1934.92 (21.29x) | 483.23 (5.32x) |
| ShortFraction Timestamp JSON parse | 43.60 | — | — | 1802.41 (41.34x) | 407.01 (9.34x) |
| Micro Timestamp JSON stringify | 95.72 | — | — | 1491.70 (15.58x) | 519.95 (5.43x) |
| Micro Timestamp JSON parse | 48.67 | — | — | 1841.20 (37.83x) | 447.32 (9.19x) |
| Nano Timestamp JSON stringify | 93.55 | — | — | 1523.22 (16.28x) | 447.69 (4.79x) |
| Nano Timestamp JSON parse | 51.60 | — | — | 1840.45 (35.67x) | 436.18 (8.45x) |
| Offset Timestamp JSON parse | 53.66 | — | — | 1842.83 (34.34x) | 461.00 (8.59x) |
| PreEpoch Timestamp JSON stringify | 66.81 | — | — | 1196.18 (17.90x) | 411.60 (6.16x) |
| PreEpoch Timestamp JSON parse | 43.01 | — | — | 1879.36 (43.70x) | 461.05 (10.72x) |
| Max Timestamp JSON stringify | 78.86 | — | — | 1479.34 (18.76x) | 439.28 (5.57x) |
| Max Timestamp JSON parse | 51.37 | — | — | 1872.54 (36.45x) | 428.39 (8.34x) |
| Min Timestamp JSON stringify | 79.38 | — | — | 1230.09 (15.50x) | 403.70 (5.09x) |
| Min Timestamp JSON parse | 41.43 | — | — | 1783.34 (43.04x) | 396.63 (9.57x) |
| Empty JSON stringify | 20.59 | — | — | 496.19 (24.10x) | 114.74 (5.57x) |
| Empty JSON parse | 67.70 | — | — | 873.13 (12.90x) | 182.79 (2.70x) |
| Struct JSON stringify | 177.47 | — | — | 6995.87 (39.42x) | 3631.28 (20.46x) |
| Struct JSON parse | 898.01 | — | — | 13380.50 (14.90x) | 5502.31 (6.13x) |
| Struct Escape JSON parse | 1238.93 | — | — | 13549.70 (10.94x) | 5488.85 (4.43x) |
| Struct NumberExponent JSON parse | 844.14 | — | — | 14729.80 (17.45x) | 5437.40 (6.44x) |
| Struct Surrogate JSON parse | 373.90 | — | — | 5857.50 (15.67x) | 1231.91 (3.29x) |
| Struct KeySurrogate JSON parse | 373.81 | — | — | 5842.02 (15.63x) | 1573.89 (4.21x) |
| EmptyStruct JSON stringify | 41.60 | — | — | 726.50 (17.46x) | 465.28 (11.18x) |
| EmptyStruct JSON parse | 86.72 | — | — | 2372.88 (27.36x) | 350.99 (4.05x) |
| Value JSON stringify | 181.95 | — | — | 8140.31 (44.74x) | 3641.98 (20.02x) |
| Value JSON parse | 866.28 | — | — | 14914.10 (17.22x) | 5686.43 (6.56x) |
| Value Escape JSON parse | 916.18 | — | — | 14954.50 (16.32x) | 5776.42 (6.30x) |
| Value NumberExponent JSON parse | 1195.99 | — | — | 14976.60 (12.52x) | 5707.86 (4.77x) |
| Value Surrogate JSON parse | 493.71 | — | — | 8175.47 (16.56x) | 1855.77 (3.76x) |
| Value KeySurrogate JSON parse | 475.50 | — | — | 8136.68 (17.11x) | 1845.85 (3.88x) |
| NullValue JSON stringify | 40.59 | — | — | 1650.22 (40.66x) | 220.42 (5.43x) |
| NullValue JSON parse | 69.70 | — | — | 3004.89 (43.11x) | 319.30 (4.58x) |
| StringScalarValue JSON stringify | 49.73 | — | — | 1646.15 (33.10x) | 278.30 (5.60x) |
| StringScalarValue JSON parse | 142.40 | — | — | 2457.38 (17.26x) | 395.59 (2.78x) |
| StringScalarValue Escape JSON parse | 151.25 | — | — | 2512.58 (16.61x) | 580.39 (3.84x) |
| StringScalarValue Surrogate JSON parse | 150.24 | — | — | 2553.09 (16.99x) | 450.86 (3.00x) |
| EmptyStringScalarValue JSON stringify | 48.46 | — | — | 1700.66 (35.09x) | 255.79 (5.28x) |
| EmptyStringScalarValue JSON parse | 87.22 | — | — | 2413.06 (27.67x) | 341.84 (3.92x) |
| NumberValue JSON stringify | 73.15 | — | — | 1906.39 (26.06x) | 357.46 (4.89x) |
| NumberValue JSON parse | 131.91 | — | — | 2639.18 (20.01x) | 421.58 (3.20x) |
| NumberValue Exponent JSON parse | 134.47 | — | — | 2711.96 (20.17x) | 437.33 (3.25x) |
| NegativeNumberValue JSON stringify | 73.04 | — | — | 2104.08 (28.81x) | 362.07 (4.96x) |
| NegativeNumberValue JSON parse | 132.92 | — | — | 3543.51 (26.66x) | 367.06 (2.76x) |
| ZeroNumberValue JSON stringify | 50.74 | — | — | 2514.38 (49.55x) | 276.46 (5.45x) |
| ZeroNumberValue JSON parse | 129.33 | — | — | 3465.46 (26.80x) | 357.01 (2.76x) |
| BoolScalarValue JSON stringify | 40.40 | — | — | 2264.55 (56.05x) | 237.67 (5.88x) |
| BoolScalarValue JSON parse | 69.68 | — | — | 2421.29 (34.75x) | 324.96 (4.66x) |
| FalseBoolScalarValue JSON stringify | 40.71 | — | — | 1606.18 (39.45x) | 252.58 (6.20x) |
| FalseBoolScalarValue JSON parse | 70.18 | — | — | 2360.16 (33.63x) | 295.86 (4.22x) |
| ListKindValue JSON stringify | 145.45 | — | — | 7369.42 (50.67x) | 2453.24 (16.87x) |
| ListKindValue JSON parse | 672.43 | — | — | 12610.30 (18.75x) | 4937.05 (7.34x) |
| ListKindValue Escape JSON parse | 695.87 | — | — | 12671.90 (18.21x) | 4787.67 (6.88x) |
| ListKindValue Surrogate JSON parse | 446.55 | — | — | 5821.21 (13.04x) | 1199.24 (2.69x) |
| EmptyStructKindValue JSON stringify | 59.12 | — | — | 2251.68 (38.09x) | 516.95 (8.74x) |
| EmptyStructKindValue JSON parse | 141.52 | — | — | 4493.26 (31.75x) | 774.09 (5.47x) |
| EmptyListKindValue JSON stringify | 55.39 | — | — | 2338.24 (42.21x) | 351.45 (6.35x) |
| EmptyListKindValue JSON parse | 184.25 | — | — | 4889.85 (26.54x) | 730.92 (3.97x) |
| ListValue JSON stringify | 265.24 | — | — | 5682.19 (21.42x) | 2557.07 (9.64x) |
| ListValue JSON parse | 848.69 | — | — | 10460.30 (12.33x) | 4340.44 (5.11x) |
| ListValue Escape JSON parse | 687.10 | — | — | 10535.40 (15.33x) | 4631.05 (6.74x) |
| ListValue Surrogate JSON parse | 297.80 | — | — | 3742.76 (12.57x) | 839.95 (2.82x) |
| EmptyListValue JSON stringify | 40.31 | — | — | 821.98 (20.39x) | 226.37 (5.62x) |
| EmptyListValue JSON parse | 126.42 | — | — | 2607.15 (20.62x) | 280.67 (2.22x) |
| DoubleValue JSON stringify | 70.45 | — | — | 950.12 (13.49x) | 265.18 (3.76x) |
| DoubleValue JSON parse | 110.88 | — | — | 1575.14 (14.21x) | 271.36 (2.45x) |
| DoubleValue String JSON parse | 111.06 | — | — | 1411.03 (12.71x) | 343.53 (3.09x) |
| DoubleValue Exponent JSON parse | 113.10 | — | — | 1587.52 (14.04x) | 267.94 (2.37x) |
| NegativeDoubleValue JSON stringify | 69.59 | — | — | 966.74 (13.89x) | 205.20 (2.95x) |
| NegativeDoubleValue JSON parse | 111.94 | — | — | 1566.51 (13.99x) | 261.14 (2.33x) |
| ZeroDoubleValue JSON stringify | 47.66 | — | — | 969.52 (20.34x) | 190.04 (3.99x) |
| ZeroDoubleValue JSON parse | 108.21 | — | — | 1514.73 (14.00x) | 245.72 (2.27x) |
| DoubleValue NaN JSON stringify | 46.13 | — | — | 697.96 (15.13x) | 135.52 (2.94x) |
| DoubleValue NaN JSON parse | 105.01 | — | — | 1366.85 (13.02x) | 245.32 (2.34x) |
| DoubleValue Infinity JSON stringify | 49.66 | — | — | 704.64 (14.19x) | 215.78 (4.35x) |
| DoubleValue Infinity JSON parse | 105.84 | — | — | 1404.58 (13.27x) | 249.99 (2.36x) |
| DoubleValue NegativeInfinity JSON stringify | 47.91 | — | — | 658.62 (13.75x) | 164.59 (3.44x) |
| DoubleValue NegativeInfinity JSON parse | 107.74 | — | — | 1305.75 (12.12x) | 248.60 (2.31x) |
| FloatValue JSON stringify | 73.01 | — | — | 902.54 (12.36x) | 190.53 (2.61x) |
| FloatValue JSON parse | 110.42 | — | — | 1567.53 (14.20x) | 330.85 (3.00x) |
| FloatValue String JSON parse | 110.28 | — | — | 1409.86 (12.78x) | 335.34 (3.04x) |
| FloatValue Exponent JSON parse | 112.53 | — | — | 1461.78 (12.99x) | 272.20 (2.42x) |
| NegativeFloatValue JSON stringify | 72.14 | — | — | 901.55 (12.50x) | 191.57 (2.66x) |
| NegativeFloatValue JSON parse | 111.12 | — | — | 1573.09 (14.16x) | 258.84 (2.33x) |
| ZeroFloatValue JSON stringify | 64.32 | — | — | 747.79 (11.63x) | 146.64 (2.28x) |
| ZeroFloatValue JSON parse | 139.93 | — | — | 1446.39 (10.34x) | 240.84 (1.72x) |
| FloatValue NaN JSON stringify | 65.70 | — | — | 711.91 (10.84x) | 156.62 (2.38x) |
| FloatValue NaN JSON parse | 116.67 | — | — | 1340.17 (11.49x) | 267.75 (2.29x) |
| FloatValue Infinity JSON stringify | 72.66 | — | — | 643.36 (8.85x) | 214.12 (2.95x) |
| FloatValue Infinity JSON parse | 133.09 | — | — | 1192.73 (8.96x) | 233.08 (1.75x) |
| FloatValue NegativeInfinity JSON stringify | 74.59 | — | — | 635.26 (8.52x) | 123.89 (1.66x) |
| FloatValue NegativeInfinity JSON parse | 137.79 | — | — | 1410.34 (10.24x) | 307.02 (2.23x) |
| Int64Value JSON stringify | 68.18 | — | — | 673.35 (9.88x) | 245.72 (3.60x) |
| Int64Value JSON parse | 179.63 | — | — | 1515.83 (8.44x) | 436.41 (2.43x) |
| Int64Value Number JSON parse | 190.07 | — | — | 1622.51 (8.54x) | 331.10 (1.74x) |
| Int64Value Exponent JSON parse | 152.55 | — | — | 1573.13 (10.31x) | 386.02 (2.53x) |
| ZeroInt64Value JSON stringify | 55.64 | — | — | 609.01 (10.95x) | 181.78 (3.27x) |
| ZeroInt64Value JSON parse | 128.80 | — | — | 1421.05 (11.03x) | 350.74 (2.72x) |
| NegativeInt64Value JSON stringify | 67.53 | — | — | 1125.85 (16.67x) | 252.19 (3.73x) |
| NegativeInt64Value JSON parse | 162.36 | — | — | 2153.30 (13.26x) | 452.85 (2.79x) |
| MinInt64Value JSON stringify | 49.36 | — | — | 924.83 (18.74x) | 279.44 (5.66x) |
| MinInt64Value JSON parse | 156.67 | — | — | 2095.70 (13.38x) | 454.02 (2.90x) |
| MaxInt64Value JSON stringify | 71.43 | — | — | 838.63 (11.74x) | 286.83 (4.02x) |
| MaxInt64Value JSON parse | 150.94 | — | — | 1577.67 (10.45x) | 444.80 (2.95x) |
| UInt64Value JSON stringify | 50.88 | — | — | 741.46 (14.57x) | 255.89 (5.03x) |
| UInt64Value JSON parse | 179.82 | — | — | 1466.27 (8.15x) | 505.73 (2.81x) |
| UInt64Value Number JSON parse | 142.05 | — | — | 1597.07 (11.24x) | 326.43 (2.30x) |
| UInt64Value Exponent JSON parse | 148.94 | — | — | 1576.56 (10.59x) | 361.44 (2.43x) |
| ZeroUInt64Value JSON stringify | 53.91 | — | — | 658.32 (12.21x) | 184.50 (3.42x) |
| ZeroUInt64Value JSON parse | 127.02 | — | — | 1365.79 (10.75x) | 309.46 (2.44x) |
| MaxUInt64Value JSON stringify | 49.51 | — | — | 731.13 (14.77x) | 260.34 (5.26x) |
| MaxUInt64Value JSON parse | 144.19 | — | — | 1567.84 (10.87x) | 450.81 (3.13x) |
| Int32Value JSON stringify | 46.82 | — | — | 750.83 (16.04x) | 171.58 (3.66x) |
| Int32Value JSON parse | 131.54 | — | — | 1355.26 (10.30x) | 292.34 (2.22x) |
| Int32Value String JSON parse | 135.01 | — | — | 1468.48 (10.88x) | 386.26 (2.86x) |
| Int32Value Exponent JSON parse | 135.08 | — | — | 1463.39 (10.83x) | 351.25 (2.60x) |
| ZeroInt32Value JSON stringify | 46.79 | — | — | 655.15 (14.00x) | 137.42 (2.94x) |
| ZeroInt32Value JSON parse | 127.49 | — | — | 1418.84 (11.13x) | 250.31 (1.96x) |
| NegativeInt32Value JSON stringify | 46.64 | — | — | 718.77 (15.41x) | 144.06 (3.09x) |
| NegativeInt32Value JSON parse | 131.01 | — | — | 1522.83 (11.62x) | 407.08 (3.11x) |
| MinInt32Value JSON stringify | 47.16 | — | — | 752.69 (15.96x) | 135.07 (2.86x) |
| MinInt32Value JSON parse | 136.64 | — | — | 1528.05 (11.18x) | 325.56 (2.38x) |
| MaxInt32Value JSON stringify | 47.18 | — | — | 696.10 (14.75x) | 146.25 (3.10x) |
| MaxInt32Value JSON parse | 136.98 | — | — | 1489.50 (10.87x) | 317.37 (2.32x) |
| UInt32Value JSON stringify | 46.81 | — | — | 633.53 (13.53x) | 223.09 (4.77x) |
| UInt32Value JSON parse | 131.73 | — | — | 1430.47 (10.86x) | 296.07 (2.25x) |
| UInt32Value String JSON parse | 135.36 | — | — | 1289.81 (9.53x) | 384.16 (2.84x) |
| UInt32Value Exponent JSON parse | 135.07 | — | — | 1567.22 (11.60x) | 323.74 (2.40x) |
| ZeroUInt32Value JSON stringify | 46.68 | — | — | 713.95 (15.29x) | 134.33 (2.88x) |
| ZeroUInt32Value JSON parse | 127.73 | — | — | 1410.81 (11.05x) | 259.30 (2.03x) |
| MaxUInt32Value JSON stringify | 47.31 | — | — | 660.31 (13.96x) | 139.68 (2.95x) |
| MaxUInt32Value JSON parse | 137.18 | — | — | 1481.80 (10.80x) | 313.13 (2.28x) |
| BoolValue JSON stringify | 44.96 | — | — | 820.33 (18.25x) | 124.40 (2.77x) |
| BoolValue JSON parse | 59.90 | — | — | 1669.92 (27.88x) | 306.62 (5.12x) |
| FalseBoolValue JSON stringify | 45.38 | — | — | 698.30 (15.39x) | 199.38 (4.39x) |
| FalseBoolValue JSON parse | 60.40 | — | — | 1216.36 (20.14x) | 192.55 (3.19x) |
| StringValue JSON stringify | 51.89 | — | — | 787.74 (15.18x) | 179.93 (3.47x) |
| StringValue JSON parse | 120.15 | — | — | 1495.20 (12.44x) | 284.39 (2.37x) |
| StringValue Escape JSON parse | 129.93 | — | — | 1444.80 (11.12x) | 372.15 (2.86x) |
| StringValue Surrogate JSON parse | 127.53 | — | — | 1410.42 (11.06x) | 317.03 (2.49x) |
| EmptyStringValue JSON stringify | 67.09 | — | — | 725.78 (10.82x) | 163.90 (2.44x) |
| EmptyStringValue JSON parse | 80.29 | — | — | 1356.53 (16.90x) | 195.78 (2.44x) |
| BytesValue JSON stringify | 65.74 | — | — | 742.99 (11.30x) | 191.61 (2.91x) |
| BytesValue JSON parse | 158.75 | — | — | 1507.82 (9.50x) | 307.51 (1.94x) |
| BytesValue URL JSON parse | 179.81 | — | — | 1404.83 (7.81x) | 336.32 (1.87x) |
| BytesValue StandardBase64 JSON parse | 155.82 | — | — | 1389.87 (8.92x) | 297.58 (1.91x) |
| BytesValue Unpadded JSON parse | 155.35 | — | — | 1497.97 (9.64x) | 416.18 (2.68x) |
| EmptyBytesValue JSON stringify | 55.70 | — | — | 746.44 (13.40x) | 173.81 (3.12x) |
| EmptyBytesValue JSON parse | 85.12 | — | — | 1430.28 (16.80x) | 260.40 (3.06x) |
| TextFormat format | 311.87 | — | — | 3235.12 (10.37x) | 2625.04 (8.42x) |
| TextFormat parse | 911.00 | — | — | 5940.55 (6.52x) | 7737.67 (8.49x) |
| packed fixed32 encode | 3.87 | 624.75 (161.43x) | 539.80 (139.48x) | 39.32 (10.16x) | 393.10 (101.58x) |
| packed fixed32 decode | 12.24 | 1274.26 (104.11x) | 2266.82 (185.20x) | 49.93 (4.08x) | 2036.80 (166.41x) |
| packed fixed64 encode | 3.85 | 673.83 (175.02x) | 642.91 (166.99x) | 90.95 (23.62x) | 390.55 (101.44x) |
| packed fixed64 decode | 12.23 | 1193.18 (97.56x) | 8566.37 (700.44x) | 76.68 (6.27x) | 2863.85 (234.17x) |
| packed sfixed32 encode | 2.01 | 620.92 (308.92x) | 539.87 (268.59x) | 43.50 (21.64x) | 431.47 (214.66x) |
| packed sfixed32 decode | 9.09 | 1262.17 (138.85x) | 2737.84 (301.19x) | 61.52 (6.77x) | 1902.57 (209.30x) |
| packed sfixed64 encode | 2.70 | 592.27 (219.36x) | 928.04 (343.72x) | 74.94 (27.75x) | 443.46 (164.24x) |
| packed sfixed64 decode | 8.96 | 1110.91 (123.99x) | 11464.25 (1279.49x) | 81.98 (9.15x) | 3149.14 (351.47x) |
| packed float encode | 2.90 | 879.44 (303.26x) | 541.37 (186.68x) | 57.79 (19.93x) | 353.81 (122.00x) |
| packed float decode | 9.06 | 1268.94 (140.06x) | 2402.94 (265.23x) | 57.45 (6.34x) | 2031.31 (224.21x) |
| packed double encode | 2.01 | 864.30 (430.00x) | 591.43 (294.24x) | 75.77 (37.69x) | 373.24 (185.69x) |
| packed double decode | 8.76 | 1066.15 (121.71x) | 2449.97 (279.68x) | 97.47 (11.13x) | 3201.19 (365.43x) |
| packed uint64 encode | 1289.51 | 5734.28 (4.45x) | 4995.43 (3.87x) | 2675.87 (2.08x) | 4225.51 (3.28x) |
| packed uint64 decode | 1803.10 | 3453.11 (1.92x) | 9873.26 (5.48x) | 3618.39 (2.01x) | 8185.11 (4.54x) |
| packed uint32 encode | 926.00 | 5757.86 (6.22x) | 3901.79 (4.21x) | 2273.82 (2.46x) | 3653.91 (3.95x) |
| packed uint32 decode | 1327.48 | 4112.73 (3.10x) | 3778.99 (2.85x) | 2356.62 (1.78x) | 6283.82 (4.73x) |
| packed int64 encode | 1424.97 | 12947.00 (9.09x) | 7249.04 (5.09x) | 3702.59 (2.60x) | 5343.22 (3.75x) |
| packed int64 decode | 2894.95 | 4248.04 (1.47x) | 11529.08 (3.98x) | 5539.36 (1.91x) | 10643.75 (3.68x) |
| packed sint32 encode | 781.69 | 3740.57 (4.79x) | 4687.10 (6.00x) | 1950.85 (2.50x) | 4173.69 (5.34x) |
| packed sint32 decode | 952.40 | 2995.11 (3.14x) | 3938.28 (4.14x) | 1483.25 (1.56x) | 3974.65 (4.17x) |
| packed sint64 encode | 1424.25 | 5947.71 (4.18x) | 5307.22 (3.73x) | 3136.60 (2.20x) | 5265.52 (3.70x) |
| packed sint64 decode | 2048.89 | 3809.34 (1.86x) | 10748.09 (5.25x) | 3665.23 (1.79x) | 9383.63 (4.58x) |
| packed bool encode | 2.01 | 1660.93 (826.33x) | 527.09 (262.23x) | 15.76 (7.84x) | 3065.24 (1525.00x) |
| packed bool decode | 316.01 | 1968.38 (6.23x) | 2997.39 (9.49x) | 992.22 (3.14x) | 2306.34 (7.30x) |
| packed enum encode | 273.19 | 3364.13 (12.31x) | 2002.85 (7.33x) | 1265.23 (4.63x) | 3241.64 (11.87x) |
| packed enum decode | 201.17 | 1859.60 (9.24x) | 3270.97 (16.26x) | 764.11 (3.80x) | 2463.37 (12.25x) |
| large map encode | 4075.62 | 17268.36 (4.24x) | 9992.77 (2.45x) | 24222.50 (5.94x) | 233876.41 (57.38x) |
| shuffled large map deterministic binary encode | 33615.04 | — | — | 95928.50 (2.85x) | 440524.79 (13.10x) |
| large map decode | 28665.16 | 109671.62 (3.83x) | 108290.85 (3.78x) | 108966.00 (3.80x) | 365443.30 (12.75x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON (including generated `map<string, int32>` surrogate-pair key parse, null-field parse, ignore-unknown parse, enum-name parse, always-print default-value stringify, enum-number stringify, proto-name stringify, proto-name parse, open-enum numeric parse, and integer numeric-exponent parse, and quoted numeric string parse), Any/WKT JSON (including embedded zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound `Duration`, non-empty/escaped-input parse/number-exponent parse/surrogate-pair value parse/surrogate-pair key parse and empty `Struct`, object/escaped-object parse/object-number-exponent/object-surrogate-pair value parse/object-surrogate-pair key parse/list/escaped-list/surrogate-list/string-scalar/escaped-string-scalar/surrogate-string-scalar/number-exponent/negative-number `Value` (including default-like scalar and empty object/list kinds),
`FieldMask` (non-empty, escaped JSON parse input, and empty), escaped-input parse/short-fraction parse/micro/nano/offset/min/pre/post/max-bound `Timestamp`, `Empty`, min/zero/positive/number-input parse/numeric-exponent parse/negative/max `Int64Value`, negative/zero/positive finite/string-input parse/numeric-exponent parse `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), negative/zero/positive finite/string-input parse/numeric-exponent parse `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), zero/normal/number-input parse/numeric-exponent parse/max `UInt64Value`, min/zero/positive/string-input parse/numeric-exponent parse/negative/max `Int32Value`, zero/normal/string-input parse/numeric-exponent parse/max `UInt32Value`, true/false `BoolValue`, non-empty/escape-input parse/surrogate-pair parse/empty `StringValue`, padded-standard/base64url/unpadded-base64 parse/empty `BytesValue`, and recursive nested `Any` payloads), direct zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound Duration, non-empty/escaped-input parse/empty FieldMask, and escaped-input parse/short-fraction parse/micro/nano/offset/min/pre/post/max-bound Timestamp WKT JSON plus other direct WKT JSON, including non-empty/escaped-input parse/number-exponent parse/surrogate-pair value parse/surrogate-pair key parse/empty `Struct`, object/escaped-object parse/object-number-exponent/object-surrogate-pair value parse/object-surrogate-pair key parse/list/escaped-list/surrogate-list/string-scalar/escaped-string-scalar/surrogate-string-scalar/number-exponent/negative-number `Value`, and escaped/surrogate-pair/non-empty/empty `ListValue`, TextFormat, packed scalars, large bytes,
maps, oneof/optional workloads (including PresenceMix JSON), and complex nested messages (including proto-name JSON). Benchmark results are hardware-sensitive; compare full same-machine
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
