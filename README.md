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

Latest accepted comparison (`/tmp/pbz-compare-presencemix-json-final.log`,
summarized in `/tmp/pbz-summary-presencemix-json-final.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Pivoted rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 17.38 | 101.60 (5.85x) | 67.37 (3.88x) | 105.10 (6.05x) | 1022.01 (58.80x) |
| binary decode | 86.03 | 250.52 (2.91x) | 228.12 (2.65x) | 222.75 (2.59x) | 1007.32 (11.71x) |
| unknown fields count by number | 3.56 | — | — | 164.44 (46.19x) | — |
| deterministic binary encode | 87.37 | — | — | 128.37 (1.47x) | 1491.57 (17.07x) |
| scalarmix encode | 19.04 | 101.45 (5.33x) | 48.09 (2.53x) | 29.44 (1.55x) | 205.76 (10.81x) |
| scalarmix decode | 56.11 | 130.55 (2.33x) | 269.16 (4.80x) | 110.39 (1.97x) | 328.99 (5.86x) |
| textbytes encode | 9.53 | 90.76 (9.52x) | 33.40 (3.50x) | 114.80 (12.05x) | 153.54 (16.11x) |
| textbytes decode | 48.21 | 382.84 (7.94x) | 245.76 (5.10x) | 165.59 (3.43x) | 844.72 (17.52x) |
| largebytes encode | 25.82 | 2738.75 (106.07x) | 2714.81 (105.14x) | 2725.55 (105.56x) | 2780.07 (107.67x) |
| largebytes decode | 89.45 | 5994.69 (67.02x) | 3236.16 (36.18x) | 2775.99 (31.03x) | 30508.27 (341.07x) |
| presencemix encode | 16.94 | 69.77 (4.12x) | 26.63 (1.57x) | 60.73 (3.58x) | 228.13 (13.47x) |
| presencemix decode | 55.42 | 178.53 (3.22x) | 121.44 (2.19x) | 164.80 (2.97x) | 461.08 (8.32x) |
| PresenceMix JSON stringify | 143.27 | — | — | 3761.71 (26.26x) | 2694.42 (18.81x) |
| PresenceMix JSON parse | 1154.32 | — | — | 7193.81 (6.23x) | 3456.11 (2.99x) |
| complex encode | 60.77 | 136.36 (2.24x) | 96.22 (1.58x) | 167.11 (2.75x) | 997.62 (16.42x) |
| complex decode | 171.80 | 402.88 (2.35x) | 335.12 (1.95x) | 400.13 (2.33x) | 1711.95 (9.96x) |
| complex deterministic binary encode | 98.42 | — | — | 179.79 (1.83x) | 1325.87 (13.47x) |
| complex JSON stringify | 498.15 | — | — | 6016.49 (12.08x) | 7757.31 (15.57x) |
| complex JSON parse | 2359.35 | — | — | 14411.90 (6.11x) | 8694.80 (3.69x) |
| complex TextFormat format | 251.10 | — | — | 4573.73 (18.21x) | 7191.89 (28.64x) |
| complex TextFormat parse | 1871.18 | — | — | 8155.86 (4.36x) | 9824.75 (5.25x) |
| packed int32 encode | 646.88 | 3811.62 (5.89x) | 2808.69 (4.34x) | 1561.21 (2.41x) | 3396.79 (5.25x) |
| packed int32 decode | 755.52 | 2300.10 (3.04x) | 3677.59 (4.87x) | 1110.73 (1.47x) | 3685.29 (4.88x) |
| JSON stringify | 159.53 | — | — | 3798.05 (23.81x) | 2645.58 (16.58x) |
| AlwaysPrint JSON stringify | 61.07 | — | — | 3063.02 (50.16x) | 1694.60 (27.75x) |
| ProtoName JSON stringify | 311.57 | — | — | 5778.82 (18.55x) | 4857.03 (15.59x) |
| EnumNumber JSON stringify | 287.79 | — | — | 5819.59 (20.22x) | 4419.91 (15.36x) |
| JSON parse | 2057.26 | — | — | 9085.55 (4.42x) | 5449.18 (2.65x) |
| MapKeySurrogate JSON parse | 506.17 | — | — | 4248.25 (8.39x) | 1041.28 (2.06x) |
| NullFields JSON parse | 499.09 | — | — | 2387.41 (4.78x) | 818.37 (1.64x) |
| IgnoreUnknown JSON parse | 1196.16 | — | — | 6418.57 (5.37x) | 3100.76 (2.59x) |
| OpenEnum JSON parse | 297.10 | — | — | 4390.68 (14.78x) | 474.68 (1.60x) |
| EnumName JSON parse | 293.19 | — | — | 4559.70 (15.55x) | 448.97 (1.53x) |
| ProtoName JSON parse | 534.06 | — | — | 4644.64 (8.70x) | 1239.93 (2.32x) |
| IntExponent JSON parse | 1681.36 | — | — | 8596.24 (5.11x) | 4923.90 (2.93x) |
| Any WKT JSON stringify | 136.30 | — | — | 2275.65 (16.70x) | 1059.73 (7.77x) |
| Any WKT JSON parse | 522.67 | — | — | 3629.04 (6.94x) | 1895.00 (3.63x) |
| Any Duration Escape WKT JSON parse | 536.92 | — | — | 3582.67 (6.67x) | 1926.27 (3.59x) |
| Any PlusDuration WKT JSON parse | 524.80 | — | — | 3590.91 (6.84x) | 1740.41 (3.32x) |
| Any ShortFractionDuration WKT JSON parse | 522.29 | — | — | 3649.05 (6.99x) | 1793.38 (3.43x) |
| Any MicroDuration WKT JSON stringify | 145.54 | — | — | 2286.18 (15.71x) | 1335.00 (9.17x) |
| Any MicroDuration WKT JSON parse | 527.59 | — | — | 3553.51 (6.74x) | 1755.29 (3.33x) |
| Any NanoDuration WKT JSON stringify | 255.93 | — | — | 2296.28 (8.97x) | 1111.69 (4.34x) |
| Any NanoDuration WKT JSON parse | 877.90 | — | — | 3712.38 (4.23x) | 1851.93 (2.11x) |
| Any NegativeDuration WKT JSON stringify | 143.90 | — | — | 2308.37 (16.04x) | 1333.08 (9.26x) |
| Any NegativeDuration WKT JSON parse | 712.77 | — | — | 3649.42 (5.12x) | 1784.98 (2.50x) |
| Any FractionalNegativeDuration WKT JSON stringify | 236.30 | — | — | 2256.39 (9.55x) | 1163.34 (4.92x) |
| Any FractionalNegativeDuration WKT JSON parse | 521.46 | — | — | 3686.15 (7.07x) | 1596.69 (3.06x) |
| Any MaxDuration WKT JSON stringify | 123.59 | — | — | 2139.40 (17.31x) | 1022.52 (8.27x) |
| Any MaxDuration WKT JSON parse | 536.26 | — | — | 3604.13 (6.72x) | 1876.46 (3.50x) |
| Any MinDuration WKT JSON stringify | 123.97 | — | — | 2129.82 (17.18x) | 1324.24 (10.68x) |
| Any MinDuration WKT JSON parse | 538.39 | — | — | 3719.42 (6.91x) | 1688.78 (3.14x) |
| Any ZeroDuration WKT JSON stringify | 110.02 | — | — | 954.17 (8.67x) | 905.37 (8.23x) |
| Any ZeroDuration WKT JSON parse | 474.37 | — | — | 2623.70 (5.53x) | 1624.07 (3.42x) |
| Any FieldMask WKT JSON stringify | 230.10 | — | — | 2134.86 (9.28x) | 1901.71 (8.26x) |
| Any FieldMask WKT JSON parse | 733.05 | — | — | 3748.54 (5.11x) | 2172.11 (2.96x) |
| Any FieldMask Escape WKT JSON parse | 741.66 | — | — | 3808.73 (5.14x) | 2606.45 (3.51x) |
| Any EmptyFieldMask WKT JSON stringify | 206.39 | — | — | 992.18 (4.81x) | 864.44 (4.19x) |
| Any EmptyFieldMask WKT JSON parse | 715.30 | — | — | 2485.74 (3.48x) | 1581.20 (2.21x) |
| Any Timestamp WKT JSON stringify | 287.27 | — | — | 2379.20 (8.28x) | 1096.84 (3.82x) |
| Any Timestamp WKT JSON parse | 784.54 | — | — | 3652.71 (4.66x) | 1935.28 (2.47x) |
| Any Timestamp Escape WKT JSON parse | 588.65 | — | — | 3722.98 (6.32x) | 1979.24 (3.36x) |
| Any ShortFraction Timestamp WKT JSON parse | 566.68 | — | — | 3569.31 (6.30x) | 1806.31 (3.19x) |
| Any Micro Timestamp WKT JSON stringify | 177.70 | — | — | 2415.65 (13.59x) | 1190.79 (6.70x) |
| Any Micro Timestamp WKT JSON parse | 578.82 | — | — | 3618.90 (6.25x) | 1886.24 (3.26x) |
| Any Nano Timestamp WKT JSON stringify | 179.10 | — | — | 2392.07 (13.36x) | 1371.67 (7.66x) |
| Any Nano Timestamp WKT JSON parse | 582.82 | — | — | 3727.69 (6.40x) | 1989.32 (3.41x) |
| Any Offset Timestamp WKT JSON parse | 590.91 | — | — | 3640.43 (6.16x) | 2031.57 (3.44x) |
| Any PreEpoch Timestamp WKT JSON stringify | 145.12 | — | — | 2304.36 (15.88x) | 1019.56 (7.03x) |
| Any PreEpoch Timestamp WKT JSON parse | 561.35 | — | — | 4704.05 (8.38x) | 1798.55 (3.20x) |
| Any Max Timestamp WKT JSON stringify | 328.80 | — | — | 3251.50 (9.89x) | 1283.43 (3.90x) |
| Any Max Timestamp WKT JSON parse | 906.54 | — | — | 5132.00 (5.66x) | 2173.48 (2.40x) |
| Any Min Timestamp WKT JSON stringify | 278.76 | — | — | 3190.69 (11.45x) | 1020.01 (3.66x) |
| Any Min Timestamp WKT JSON parse | 763.18 | — | — | 3677.51 (4.82x) | 1823.48 (2.39x) |
| Any Empty WKT JSON stringify | 121.53 | — | — | 906.82 (7.46x) | 633.45 (5.21x) |
| Any Empty WKT JSON parse | 335.34 | — | — | 2456.30 (7.32x) | 1646.76 (4.91x) |
| Any Struct WKT JSON stringify | 615.39 | — | — | 6935.01 (11.27x) | 7441.63 (12.09x) |
| Any Struct WKT JSON parse | 1752.68 | — | — | 13397.40 (7.64x) | 10948.42 (6.25x) |
| Any Struct Escape WKT JSON parse | 1778.28 | — | — | 17226.90 (9.69x) | 10441.01 (5.87x) |
| Any Struct NumberExponent WKT JSON parse | 2036.93 | — | — | 13546.90 (6.65x) | 10044.13 (4.93x) |
| Any Struct Surrogate WKT JSON parse | 768.48 | — | — | 9648.25 (12.55x) | 3432.49 (4.47x) |
| Any Struct KeySurrogate WKT JSON parse | 761.04 | — | — | 9173.98 (12.05x) | 3647.40 (4.79x) |
| Any EmptyStruct WKT JSON stringify | 122.95 | — | — | 999.45 (8.13x) | 1141.01 (9.28x) |
| Any EmptyStruct WKT JSON parse | 437.80 | — | — | 2809.43 (6.42x) | 1717.85 (3.92x) |
| Any Value WKT JSON stringify | 644.02 | — | — | 6833.64 (10.61x) | 7465.27 (11.59x) |
| Any Value WKT JSON parse | 2482.27 | — | — | 13454.50 (5.42x) | 11036.54 (4.45x) |
| Any Value Escape WKT JSON parse | 1846.18 | — | — | 14520.60 (7.87x) | 10595.37 (5.74x) |
| Any Value NumberExponent WKT JSON parse | 1815.55 | — | — | 20488.00 (11.28x) | 10598.33 (5.84x) |
| Any Value Surrogate WKT JSON parse | 822.57 | — | — | 7518.74 (9.14x) | 11392.60 (13.85x) |
| Any Value KeySurrogate WKT JSON parse | 1372.39 | — | — | 7710.97 (5.62x) | 7567.06 (5.51x) |
| Any NullValue WKT JSON stringify | 211.14 | — | — | 2927.79 (13.87x) | 3415.83 (16.18x) |
| Any NullValue WKT JSON parse | 651.23 | — | — | 4660.07 (7.16x) | 3383.86 (5.20x) |
| Any StringScalarValue WKT JSON stringify | 226.46 | — | — | 2655.19 (11.72x) | 1837.18 (8.11x) |
| Any StringScalarValue WKT JSON parse | 621.31 | — | — | 5121.10 (8.24x) | 2717.54 (4.37x) |
| Any StringScalarValue Escape WKT JSON parse | 532.99 | — | — | 4510.66 (8.46x) | 2568.89 (4.82x) |
| Any StringScalarValue Surrogate WKT JSON parse | 537.12 | — | — | 4299.91 (8.01x) | 3017.52 (5.62x) |
| Any EmptyStringScalarValue WKT JSON stringify | 142.03 | — | — | 2738.29 (19.28x) | 1761.91 (12.41x) |
| Any EmptyStringScalarValue WKT JSON parse | 488.45 | — | — | 4522.80 (9.26x) | 1825.19 (3.74x) |
| Any NumberValue WKT JSON stringify | 175.30 | — | — | 3031.71 (17.29x) | 1356.78 (7.74x) |
| Any NumberValue WKT JSON parse | 507.99 | — | — | 4204.44 (8.28x) | 2499.71 (4.92x) |
| Any NumberValue Exponent WKT JSON parse | 510.95 | — | — | 4410.58 (8.63x) | 5564.34 (10.89x) |
| Any NegativeNumberValue WKT JSON stringify | 178.65 | — | — | 2963.70 (16.59x) | 2634.31 (14.75x) |
| Any NegativeNumberValue WKT JSON parse | 699.32 | — | — | 4428.29 (6.33x) | 4409.10 (6.30x) |
| Any ZeroNumberValue WKT JSON stringify | 267.83 | — | — | 2927.24 (10.93x) | 2269.51 (8.47x) |
| Any ZeroNumberValue WKT JSON parse | 758.90 | — | — | 4220.36 (5.56x) | 4145.32 (5.46x) |
| Any BoolScalarValue WKT JSON stringify | 193.75 | — | — | 2790.31 (14.40x) | 2201.71 (11.36x) |
| Any BoolScalarValue WKT JSON parse | 625.63 | — | — | 4431.72 (7.08x) | 2126.34 (3.40x) |
| Any FalseBoolScalarValue WKT JSON stringify | 207.93 | — | — | 2734.56 (13.15x) | 1540.21 (7.41x) |
| Any FalseBoolScalarValue WKT JSON parse | 463.51 | — | — | 4055.23 (8.75x) | 2493.03 (5.38x) |
| Any ListKindValue WKT JSON stringify | 506.35 | — | — | 6638.54 (13.11x) | 5802.81 (11.46x) |
| Any ListKindValue WKT JSON parse | 1389.81 | — | — | 11608.80 (8.35x) | 8514.19 (6.13x) |
| Any ListKindValue Escape WKT JSON parse | 1419.18 | — | — | 12110.50 (8.53x) | 9267.48 (6.53x) |
| Any ListKindValue Surrogate WKT JSON parse | 731.27 | — | — | 5669.03 (7.75x) | 3320.81 (4.54x) |
| Any EmptyStructKindValue WKT JSON stringify | 249.99 | — | — | 3397.71 (13.59x) | 1635.20 (6.54x) |
| Any EmptyStructKindValue WKT JSON parse | 712.49 | — | — | 6475.55 (9.09x) | 2498.68 (3.51x) |
| Any EmptyListKindValue WKT JSON stringify | 221.11 | — | — | 3378.03 (15.28x) | 1171.09 (5.30x) |
| Any EmptyListKindValue WKT JSON parse | 673.69 | — | — | 5240.74 (7.78x) | 2499.68 (3.71x) |
| Any DoubleValue WKT JSON stringify | 188.08 | — | — | 2172.41 (11.55x) | 802.02 (4.26x) |
| Any DoubleValue WKT JSON parse | 526.38 | — | — | 3224.85 (6.13x) | 1722.22 (3.27x) |
| Any DoubleValue String WKT JSON parse | 534.74 | — | — | 3282.13 (6.14x) | 1803.98 (3.37x) |
| Any DoubleValue Exponent WKT JSON parse | 529.22 | — | — | 3137.01 (5.93x) | 1612.72 (3.05x) |
| Any NegativeDoubleValue WKT JSON stringify | 193.35 | — | — | 2181.68 (11.28x) | 1168.10 (6.04x) |
| Any NegativeDoubleValue WKT JSON parse | 529.17 | — | — | 3154.56 (5.96x) | 1843.28 (3.48x) |
| Any ZeroDoubleValue WKT JSON stringify | 164.48 | — | — | 953.01 (5.79x) | 1029.48 (6.26x) |
| Any ZeroDoubleValue WKT JSON parse | 522.20 | — | — | 2520.47 (4.83x) | 1487.47 (2.85x) |
| Any DoubleValue NaN WKT JSON stringify | 161.46 | — | — | 1958.35 (12.13x) | 928.35 (5.75x) |
| Any DoubleValue NaN WKT JSON parse | 522.11 | — | — | 3171.69 (6.07x) | 1562.25 (2.99x) |
| Any DoubleValue Infinity WKT JSON stringify | 251.16 | — | — | 1932.09 (7.69x) | 773.23 (3.08x) |
| Any DoubleValue Infinity WKT JSON parse | 828.86 | — | — | 3210.21 (3.87x) | 1405.84 (1.70x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 250.94 | — | — | 1928.10 (7.68x) | 686.18 (2.73x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 643.60 | — | — | 3315.34 (5.15x) | 1861.84 (2.89x) |
| Any FloatValue WKT JSON stringify | 236.37 | — | — | 2113.02 (8.94x) | 918.76 (3.89x) |
| Any FloatValue WKT JSON parse | 520.28 | — | — | 3189.11 (6.13x) | 1793.02 (3.45x) |
| Any FloatValue String WKT JSON parse | 533.94 | — | — | 3165.37 (5.93x) | 1568.53 (2.94x) |
| Any FloatValue Exponent WKT JSON parse | 527.12 | — | — | 3144.78 (5.97x) | 1685.70 (3.20x) |
| Any NegativeFloatValue WKT JSON stringify | 199.91 | — | — | 2105.78 (10.53x) | 855.42 (4.28x) |
| Any NegativeFloatValue WKT JSON parse | 523.16 | — | — | 3131.50 (5.99x) | 1468.33 (2.81x) |
| Any ZeroFloatValue WKT JSON stringify | 169.00 | — | — | 971.08 (5.75x) | 849.21 (5.02x) |
| Any ZeroFloatValue WKT JSON parse | 521.79 | — | — | 2518.06 (4.83x) | 1595.60 (3.06x) |
| Any FloatValue NaN WKT JSON stringify | 162.28 | — | — | 1833.20 (11.30x) | 824.38 (5.08x) |
| Any FloatValue NaN WKT JSON parse | 518.12 | — | — | 3164.33 (6.11x) | 1626.36 (3.14x) |
| Any FloatValue Infinity WKT JSON stringify | 165.22 | — | — | 1919.71 (11.62x) | 827.50 (5.01x) |
| Any FloatValue Infinity WKT JSON parse | 523.54 | — | — | 3098.73 (5.92x) | 1760.74 (3.36x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 254.61 | — | — | 1923.57 (7.55x) | 846.04 (3.32x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 835.84 | — | — | 3176.73 (3.80x) | 1671.47 (2.00x) |
| Any Int64Value WKT JSON stringify | 179.01 | — | — | 1791.89 (10.01x) | 1031.91 (5.76x) |
| Any Int64Value WKT JSON parse | 696.53 | — | — | 3334.12 (4.79x) | 1891.51 (2.72x) |
| Any Int64Value Number WKT JSON parse | 551.72 | — | — | 3224.45 (5.84x) | 1694.33 (3.07x) |
| Any Int64Value Exponent WKT JSON parse | 535.19 | — | — | 3144.28 (5.88x) | 1526.80 (2.85x) |
| Any ZeroInt64Value WKT JSON stringify | 176.48 | — | — | 987.83 (5.60x) | 850.77 (4.82x) |
| Any ZeroInt64Value WKT JSON parse | 525.35 | — | — | 2504.83 (4.77x) | 1585.27 (3.02x) |
| Any NegativeInt64Value WKT JSON stringify | 175.16 | — | — | 1922.09 (10.97x) | 979.61 (5.59x) |
| Any NegativeInt64Value WKT JSON parse | 558.36 | — | — | 3273.23 (5.86x) | 2009.91 (3.60x) |
| Any MinInt64Value WKT JSON stringify | 194.06 | — | — | 1937.47 (9.98x) | 1356.47 (6.99x) |
| Any MinInt64Value WKT JSON parse | 565.90 | — | — | 3390.14 (5.99x) | 1803.73 (3.19x) |
| Any MaxInt64Value WKT JSON stringify | 175.66 | — | — | 1933.00 (11.00x) | 962.89 (5.48x) |
| Any MaxInt64Value WKT JSON parse | 556.54 | — | — | 3360.91 (6.04x) | 2197.44 (3.95x) |
| Any UInt64Value WKT JSON stringify | 270.11 | — | — | 2613.51 (9.68x) | 993.84 (3.68x) |
| Any UInt64Value WKT JSON parse | 922.75 | — | — | 3359.90 (3.64x) | 1903.97 (2.06x) |
| Any UInt64Value Number WKT JSON parse | 799.80 | — | — | 3350.61 (4.19x) | 2094.50 (2.62x) |
| Any UInt64Value Exponent WKT JSON parse | 706.31 | — | — | 3177.31 (4.50x) | 1723.30 (2.44x) |
| Any ZeroUInt64Value WKT JSON stringify | 173.01 | — | — | 971.68 (5.62x) | 1053.58 (6.09x) |
| Any ZeroUInt64Value WKT JSON parse | 533.48 | — | — | 2563.50 (4.81x) | 1803.33 (3.38x) |
| Any MaxUInt64Value WKT JSON stringify | 178.71 | — | — | 1947.91 (10.90x) | 917.92 (5.14x) |
| Any MaxUInt64Value WKT JSON parse | 565.34 | — | — | 3395.25 (6.01x) | 2000.10 (3.54x) |
| Any Int32Value WKT JSON stringify | 179.56 | — | — | 1921.61 (10.70x) | 1048.02 (5.84x) |
| Any Int32Value WKT JSON parse | 537.71 | — | — | 3201.73 (5.95x) | 1771.24 (3.29x) |
| Any Int32Value String WKT JSON parse | 542.33 | — | — | 3226.87 (5.95x) | 1846.81 (3.41x) |
| Any Int32Value Exponent WKT JSON parse | 544.68 | — | — | 3306.84 (6.07x) | 1495.75 (2.75x) |
| Any ZeroInt32Value WKT JSON stringify | 176.46 | — | — | 984.49 (5.58x) | 788.47 (4.47x) |
| Any ZeroInt32Value WKT JSON parse | 534.83 | — | — | 2583.79 (4.83x) | 1554.18 (2.91x) |
| Any NegativeInt32Value WKT JSON stringify | 279.41 | — | — | 1940.37 (6.94x) | 892.98 (3.20x) |
| Any NegativeInt32Value WKT JSON parse | 893.04 | — | — | 3274.00 (3.67x) | 1420.24 (1.59x) |
| Any MinInt32Value WKT JSON stringify | 225.58 | — | — | 1883.10 (8.35x) | 924.92 (4.10x) |
| Any MinInt32Value WKT JSON parse | 773.82 | — | — | 3361.94 (4.34x) | 1752.14 (2.26x) |
| Any MaxInt32Value WKT JSON stringify | 216.60 | — | — | 1911.05 (8.82x) | 941.18 (4.35x) |
| Any MaxInt32Value WKT JSON parse | 545.63 | — | — | 3220.19 (5.90x) | 1765.08 (3.23x) |
| Any UInt32Value WKT JSON stringify | 184.32 | — | — | 1886.04 (10.23x) | 818.33 (4.44x) |
| Any UInt32Value WKT JSON parse | 543.63 | — | — | 3134.17 (5.77x) | 1879.71 (3.46x) |
| Any UInt32Value String WKT JSON parse | 548.33 | — | — | 3224.99 (5.88x) | 1782.03 (3.25x) |
| Any UInt32Value Exponent WKT JSON parse | 548.56 | — | — | 3154.36 (5.75x) | 2002.14 (3.65x) |
| Any ZeroUInt32Value WKT JSON stringify | 176.31 | — | — | 956.19 (5.42x) | 675.99 (3.83x) |
| Any ZeroUInt32Value WKT JSON parse | 540.02 | — | — | 2531.82 (4.69x) | 1787.83 (3.31x) |
| Any MaxUInt32Value WKT JSON stringify | 187.20 | — | — | 1921.03 (10.26x) | 822.67 (4.39x) |
| Any MaxUInt32Value WKT JSON parse | 918.45 | — | — | 3248.01 (3.54x) | 1809.51 (1.97x) |
| Any BoolValue WKT JSON stringify | 256.33 | — | — | 1920.30 (7.49x) | 998.51 (3.90x) |
| Any BoolValue WKT JSON parse | 707.51 | — | — | 3041.60 (4.30x) | 1723.76 (2.44x) |
| Any FalseBoolValue WKT JSON stringify | 201.12 | — | — | 1008.12 (5.01x) | 761.27 (3.79x) |
| Any FalseBoolValue WKT JSON parse | 672.67 | — | — | 2651.16 (3.94x) | 1513.78 (2.25x) |
| Any StringValue WKT JSON stringify | 199.42 | — | — | 1959.58 (9.83x) | 1291.55 (6.48x) |
| Any StringValue WKT JSON parse | 553.78 | — | — | 3021.23 (5.46x) | 1893.56 (3.42x) |
| Any StringValue Escape WKT JSON parse | 559.23 | — | — | 3427.60 (6.13x) | 1917.78 (3.43x) |
| Any StringValue Surrogate WKT JSON parse | 563.26 | — | — | 3391.88 (6.02x) | 2202.51 (3.91x) |
| Any EmptyStringValue WKT JSON stringify | 200.46 | — | — | 981.72 (4.90x) | 810.55 (4.04x) |
| Any EmptyStringValue WKT JSON parse | 522.63 | — | — | 2622.75 (5.02x) | 1535.37 (2.94x) |
| Any BytesValue WKT JSON stringify | 198.00 | — | — | 1771.18 (8.95x) | 1498.73 (7.57x) |
| Any BytesValue WKT JSON parse | 570.21 | — | — | 3208.64 (5.63x) | 1660.09 (2.91x) |
| Any BytesValue URL WKT JSON parse | 943.30 | — | — | 3360.67 (3.56x) | 1632.23 (1.73x) |
| Any BytesValue StandardBase64 WKT JSON parse | 851.87 | — | — | 3174.71 (3.73x) | 1563.10 (1.83x) |
| Any BytesValue Unpadded WKT JSON parse | 786.64 | — | — | 3184.08 (4.05x) | 1659.10 (2.11x) |
| Any EmptyBytesValue WKT JSON stringify | 253.32 | — | — | 994.04 (3.92x) | 944.23 (3.73x) |
| Any EmptyBytesValue WKT JSON parse | 530.29 | — | — | 2517.64 (4.75x) | 1651.73 (3.11x) |
| Nested Any WKT JSON stringify | 314.24 | — | — | 2914.87 (9.28x) | 2086.12 (6.64x) |
| Nested Any WKT JSON parse | 879.09 | — | — | 4940.31 (5.62x) | 3338.94 (3.80x) |
| Duration JSON stringify | 57.40 | — | — | 958.21 (16.69x) | 348.29 (6.07x) |
| Duration JSON parse | 19.75 | — | — | 1600.93 (81.06x) | 361.63 (18.31x) |
| Duration Escape JSON parse | 41.29 | — | — | 1809.52 (43.82x) | 388.59 (9.41x) |
| PlusDuration JSON parse | 20.44 | — | — | 1826.72 (89.37x) | 367.41 (17.98x) |
| ShortFractionDuration JSON parse | 16.57 | — | — | 1560.40 (94.17x) | 403.04 (24.32x) |
| MicroDuration JSON stringify | 59.65 | — | — | 1026.35 (17.21x) | 533.88 (8.95x) |
| MicroDuration JSON parse | 20.72 | — | — | 1852.08 (89.39x) | 430.87 (20.79x) |
| NanoDuration JSON stringify | 57.27 | — | — | 1127.28 (19.68x) | 717.59 (12.53x) |
| NanoDuration JSON parse | 25.81 | — | — | 1834.51 (71.08x) | 574.20 (22.25x) |
| NegativeDuration JSON stringify | 60.10 | — | — | 1153.93 (19.20x) | 1235.59 (20.56x) |
| NegativeDuration JSON parse | 20.10 | — | — | 1865.67 (92.82x) | 1228.53 (61.12x) |
| FractionalNegativeDuration JSON stringify | 60.12 | — | — | 978.04 (16.27x) | 1067.06 (17.75x) |
| FractionalNegativeDuration JSON parse | 20.39 | — | — | 1745.99 (85.63x) | 718.23 (35.22x) |
| MaxDuration JSON stringify | 49.68 | — | — | 856.70 (17.24x) | 1048.31 (21.10x) |
| MaxDuration JSON parse | 38.11 | — | — | 1762.75 (46.25x) | 1158.91 (30.41x) |
| MinDuration JSON stringify | 50.12 | — | — | 1009.80 (20.15x) | 890.34 (17.76x) |
| MinDuration JSON parse | 37.93 | — | — | 1656.54 (43.67x) | 1478.73 (38.99x) |
| ZeroDuration JSON stringify | 44.90 | — | — | 807.00 (17.97x) | 1025.45 (22.84x) |
| ZeroDuration JSON parse | 12.83 | — | — | 1561.25 (121.69x) | 1018.26 (79.37x) |
| FieldMask JSON stringify | 81.51 | — | — | 919.48 (11.28x) | 1066.99 (13.09x) |
| FieldMask JSON parse | 139.90 | — | — | 2007.58 (14.35x) | 2532.05 (18.10x) |
| FieldMask Escape JSON parse | 194.29 | — | — | 2099.87 (10.81x) | 2326.26 (11.97x) |
| EmptyFieldMask JSON stringify | 40.60 | — | — | 713.43 (17.57x) | 368.30 (9.07x) |
| EmptyFieldMask JSON parse | 4.78 | — | — | 1060.95 (221.96x) | 228.77 (47.86x) |
| Timestamp JSON stringify | 96.68 | — | — | 1277.39 (13.21x) | 839.63 (8.68x) |
| Timestamp JSON parse | 45.17 | — | — | 1842.91 (40.80x) | 772.86 (17.11x) |
| Timestamp Escape JSON parse | 87.78 | — | — | 1896.11 (21.60x) | 744.17 (8.48x) |
| ShortFraction Timestamp JSON parse | 43.64 | — | — | 1746.75 (40.03x) | 429.66 (9.85x) |
| Micro Timestamp JSON stringify | 95.80 | — | — | 1335.37 (13.94x) | 717.51 (7.49x) |
| Micro Timestamp JSON parse | 47.70 | — | — | 1842.76 (38.63x) | 450.18 (9.44x) |
| Nano Timestamp JSON stringify | 94.53 | — | — | 1351.61 (14.30x) | 463.07 (4.90x) |
| Nano Timestamp JSON parse | 49.84 | — | — | 1854.50 (37.21x) | 439.39 (8.82x) |
| Offset Timestamp JSON parse | 52.05 | — | — | 1902.98 (36.56x) | 491.50 (9.44x) |
| PreEpoch Timestamp JSON stringify | 107.00 | — | — | 1234.13 (11.53x) | 541.28 (5.06x) |
| PreEpoch Timestamp JSON parse | 76.37 | — | — | 1803.11 (23.61x) | 415.66 (5.44x) |
| Max Timestamp JSON stringify | 139.90 | — | — | 1343.49 (9.60x) | 631.62 (4.51x) |
| Max Timestamp JSON parse | 95.48 | — | — | 1857.98 (19.46x) | 452.41 (4.74x) |
| Min Timestamp JSON stringify | 150.37 | — | — | 1135.84 (7.55x) | 397.42 (2.64x) |
| Min Timestamp JSON parse | 72.01 | — | — | 1715.27 (23.82x) | 565.74 (7.86x) |
| Empty JSON stringify | 29.12 | — | — | 508.85 (17.47x) | 81.12 (2.79x) |
| Empty JSON parse | 89.45 | — | — | 813.35 (9.09x) | 192.69 (2.15x) |
| Struct JSON stringify | 315.23 | — | — | 6676.82 (21.18x) | 3510.02 (11.13x) |
| Struct JSON parse | 1178.95 | — | — | 13101.60 (11.11x) | 5898.24 (5.00x) |
| Struct Escape JSON parse | 884.47 | — | — | 13249.40 (14.98x) | 5752.45 (6.50x) |
| Struct NumberExponent JSON parse | 839.90 | — | — | 13039.80 (15.53x) | 6354.33 (7.57x) |
| Struct Surrogate JSON parse | 369.30 | — | — | 5828.32 (15.78x) | 1342.92 (3.64x) |
| Struct KeySurrogate JSON parse | 370.07 | — | — | 5797.98 (15.67x) | 1641.91 (4.44x) |
| EmptyStruct JSON stringify | 41.11 | — | — | 771.16 (18.76x) | 326.03 (7.93x) |
| EmptyStruct JSON parse | 86.68 | — | — | 2390.15 (27.57x) | 348.60 (4.02x) |
| Value JSON stringify | 179.52 | — | — | 7889.89 (43.95x) | 4260.48 (23.73x) |
| Value JSON parse | 860.56 | — | — | 14583.00 (16.95x) | 5980.32 (6.95x) |
| Value Escape JSON parse | 906.87 | — | — | 14978.70 (16.52x) | 6374.10 (7.03x) |
| Value NumberExponent JSON parse | 956.33 | — | — | 14658.60 (15.33x) | 6103.06 (6.38x) |
| Value Surrogate JSON parse | 403.81 | — | — | 7977.43 (19.76x) | 1880.92 (4.66x) |
| Value KeySurrogate JSON parse | 484.73 | — | — | 8006.74 (16.52x) | 2003.34 (4.13x) |
| NullValue JSON stringify | 40.55 | — | — | 1563.04 (38.55x) | 224.93 (5.55x) |
| NullValue JSON parse | 69.67 | — | — | 2911.00 (41.78x) | 346.49 (4.97x) |
| StringScalarValue JSON stringify | 47.62 | — | — | 1534.51 (32.22x) | 266.84 (5.60x) |
| StringScalarValue JSON parse | 140.90 | — | — | 2437.59 (17.30x) | 476.70 (3.38x) |
| StringScalarValue Escape JSON parse | 150.02 | — | — | 2492.30 (16.61x) | 550.93 (3.67x) |
| StringScalarValue Surrogate JSON parse | 148.36 | — | — | 2475.55 (16.69x) | 468.27 (3.16x) |
| EmptyStringScalarValue JSON stringify | 45.77 | — | — | 1662.62 (36.33x) | 270.64 (5.91x) |
| EmptyStringScalarValue JSON parse | 87.23 | — | — | 2436.30 (27.93x) | 366.00 (4.20x) |
| NumberValue JSON stringify | 88.60 | — | — | 1908.66 (21.54x) | 319.83 (3.61x) |
| NumberValue JSON parse | 131.85 | — | — | 2506.68 (19.01x) | 514.09 (3.90x) |
| NumberValue Exponent JSON parse | 135.29 | — | — | 2539.22 (18.77x) | 589.52 (4.36x) |
| NegativeNumberValue JSON stringify | 74.50 | — | — | 1883.04 (25.28x) | 513.00 (6.89x) |
| NegativeNumberValue JSON parse | 133.03 | — | — | 2525.06 (18.98x) | 601.52 (4.52x) |
| ZeroNumberValue JSON stringify | 50.87 | — | — | 1867.32 (36.71x) | 287.10 (5.64x) |
| ZeroNumberValue JSON parse | 129.63 | — | — | 2467.29 (19.03x) | 333.85 (2.58x) |
| BoolScalarValue JSON stringify | 40.51 | — | — | 1616.26 (39.90x) | 261.05 (6.44x) |
| BoolScalarValue JSON parse | 69.68 | — | — | 2375.01 (34.08x) | 300.07 (4.31x) |
| FalseBoolScalarValue JSON stringify | 40.49 | — | — | 1497.40 (36.98x) | 248.13 (6.13x) |
| FalseBoolScalarValue JSON parse | 70.30 | — | — | 2448.63 (34.83x) | 342.92 (4.88x) |
| ListKindValue JSON stringify | 139.54 | — | — | 7540.38 (54.04x) | 2799.75 (20.06x) |
| ListKindValue JSON parse | 666.33 | — | — | 12621.30 (18.94x) | 4372.26 (6.56x) |
| ListKindValue Escape JSON parse | 687.09 | — | — | 12679.10 (18.45x) | 5121.81 (7.45x) |
| ListKindValue Surrogate JSON parse | 319.64 | — | — | 5900.86 (18.46x) | 1434.17 (4.49x) |
| EmptyStructKindValue JSON stringify | 43.01 | — | — | 2278.77 (52.98x) | 587.24 (13.65x) |
| EmptyStructKindValue JSON parse | 110.26 | — | — | 4446.33 (40.33x) | 707.64 (6.42x) |
| EmptyListKindValue JSON stringify | 42.25 | — | — | 2309.45 (54.66x) | 532.99 (12.62x) |
| EmptyListKindValue JSON parse | 182.10 | — | — | 4855.55 (26.66x) | 748.39 (4.11x) |
| ListValue JSON stringify | 261.19 | — | — | 5754.67 (22.03x) | 2717.97 (10.41x) |
| ListValue JSON parse | 1006.33 | — | — | 10251.30 (10.19x) | 4548.48 (4.52x) |
| ListValue Escape JSON parse | 917.12 | — | — | 10426.60 (11.37x) | 5048.20 (5.50x) |
| ListValue Surrogate JSON parse | 345.36 | — | — | 3788.09 (10.97x) | 849.18 (2.46x) |
| EmptyListValue JSON stringify | 51.48 | — | — | 687.41 (13.35x) | 180.22 (3.50x) |
| EmptyListValue JSON parse | 153.00 | — | — | 2621.77 (17.14x) | 278.12 (1.82x) |
| DoubleValue JSON stringify | 70.20 | — | — | 1009.43 (14.38x) | 184.24 (2.62x) |
| DoubleValue JSON parse | 111.28 | — | — | 1444.63 (12.98x) | 346.78 (3.12x) |
| DoubleValue String JSON parse | 111.55 | — | — | 1313.84 (11.78x) | 403.47 (3.62x) |
| DoubleValue Exponent JSON parse | 113.46 | — | — | 1438.50 (12.68x) | 445.49 (3.93x) |
| NegativeDoubleValue JSON stringify | 67.78 | — | — | 912.33 (13.46x) | 192.90 (2.85x) |
| NegativeDoubleValue JSON parse | 111.74 | — | — | 1521.26 (13.61x) | 312.03 (2.79x) |
| ZeroDoubleValue JSON stringify | 47.44 | — | — | 898.37 (18.94x) | 136.42 (2.88x) |
| ZeroDoubleValue JSON parse | 108.62 | — | — | 1302.86 (11.99x) | 360.89 (3.32x) |
| DoubleValue NaN JSON stringify | 46.46 | — | — | 678.73 (14.61x) | 122.99 (2.65x) |
| DoubleValue NaN JSON parse | 104.58 | — | — | 1271.58 (12.16x) | 317.10 (3.03x) |
| DoubleValue Infinity JSON stringify | 48.15 | — | — | 674.15 (14.00x) | 180.71 (3.75x) |
| DoubleValue Infinity JSON parse | 105.76 | — | — | 1232.17 (11.65x) | 327.56 (3.10x) |
| DoubleValue NegativeInfinity JSON stringify | 48.14 | — | — | 723.45 (15.03x) | 139.01 (2.89x) |
| DoubleValue NegativeInfinity JSON parse | 107.97 | — | — | 1234.70 (11.44x) | 369.21 (3.42x) |
| FloatValue JSON stringify | 71.10 | — | — | 813.26 (11.44x) | 181.92 (2.56x) |
| FloatValue JSON parse | 110.80 | — | — | 1604.40 (14.48x) | 274.36 (2.48x) |
| FloatValue String JSON parse | 110.28 | — | — | 1308.52 (11.87x) | 427.93 (3.88x) |
| FloatValue Exponent JSON parse | 113.05 | — | — | 1589.16 (14.06x) | 297.90 (2.64x) |
| NegativeFloatValue JSON stringify | 71.30 | — | — | 876.29 (12.29x) | 315.36 (4.42x) |
| NegativeFloatValue JSON parse | 111.04 | — | — | 1341.47 (12.08x) | 274.60 (2.47x) |
| ZeroFloatValue JSON stringify | 47.23 | — | — | 759.38 (16.08x) | 230.74 (4.89x) |
| ZeroFloatValue JSON parse | 108.14 | — | — | 1328.96 (12.29x) | 243.66 (2.25x) |
| FloatValue NaN JSON stringify | 46.41 | — | — | 650.94 (14.03x) | 119.13 (2.57x) |
| FloatValue NaN JSON parse | 104.66 | — | — | 1202.95 (11.49x) | 281.23 (2.69x) |
| FloatValue Infinity JSON stringify | 47.88 | — | — | 655.06 (13.68x) | 118.42 (2.47x) |
| FloatValue Infinity JSON parse | 106.36 | — | — | 1158.31 (10.89x) | 238.68 (2.24x) |
| FloatValue NegativeInfinity JSON stringify | 48.22 | — | — | 708.25 (14.69x) | 183.36 (3.80x) |
| FloatValue NegativeInfinity JSON parse | 108.05 | — | — | 1326.91 (12.28x) | 346.70 (3.21x) |
| Int64Value JSON stringify | 50.29 | — | — | 672.93 (13.38x) | 293.87 (5.84x) |
| Int64Value JSON parse | 125.31 | — | — | 1500.54 (11.97x) | 532.06 (4.25x) |
| Int64Value Number JSON parse | 127.89 | — | — | 1504.47 (11.76x) | 434.17 (3.39x) |
| Int64Value Exponent JSON parse | 116.82 | — | — | 1471.46 (12.60x) | 549.23 (4.70x) |
| ZeroInt64Value JSON stringify | 41.33 | — | — | 658.51 (15.93x) | 185.59 (4.49x) |
| ZeroInt64Value JSON parse | 106.96 | — | — | 1315.27 (12.30x) | 341.68 (3.19x) |
| NegativeInt64Value JSON stringify | 50.10 | — | — | 712.40 (14.22x) | 251.86 (5.03x) |
| NegativeInt64Value JSON parse | 126.68 | — | — | 1363.69 (10.76x) | 446.15 (3.52x) |
| MinInt64Value JSON stringify | 49.24 | — | — | 747.25 (15.18x) | 259.41 (5.27x) |
| MinInt64Value JSON parse | 134.95 | — | — | 1508.42 (11.18x) | 578.64 (4.29x) |
| MaxInt64Value JSON stringify | 68.95 | — | — | 676.69 (9.81x) | 257.97 (3.74x) |
| MaxInt64Value JSON parse | 188.32 | — | — | 1427.13 (7.58x) | 429.27 (2.28x) |
| UInt64Value JSON stringify | 67.46 | — | — | 959.59 (14.22x) | 333.73 (4.95x) |
| UInt64Value JSON parse | 181.64 | — | — | 1964.39 (10.81x) | 461.64 (2.54x) |
| UInt64Value Number JSON parse | 186.42 | — | — | 2264.29 (12.15x) | 368.72 (1.98x) |
| UInt64Value Exponent JSON parse | 152.87 | — | — | 2058.06 (13.46x) | 621.26 (4.06x) |
| ZeroUInt64Value JSON stringify | 55.65 | — | — | 613.79 (11.03x) | 236.38 (4.25x) |
| ZeroUInt64Value JSON parse | 129.52 | — | — | 1169.80 (9.03x) | 334.67 (2.58x) |
| MaxUInt64Value JSON stringify | 68.47 | — | — | 682.31 (9.97x) | 444.92 (6.50x) |
| MaxUInt64Value JSON parse | 198.10 | — | — | 1616.14 (8.16x) | 527.46 (2.66x) |
| Int32Value JSON stringify | 63.96 | — | — | 717.42 (11.22x) | 132.49 (2.07x) |
| Int32Value JSON parse | 163.93 | — | — | 1368.15 (8.35x) | 386.93 (2.36x) |
| Int32Value String JSON parse | 142.38 | — | — | 1398.55 (9.82x) | 400.95 (2.82x) |
| Int32Value Exponent JSON parse | 171.38 | — | — | 1457.21 (8.50x) | 393.93 (2.30x) |
| ZeroInt32Value JSON stringify | 62.18 | — | — | 705.59 (11.35x) | 121.83 (1.96x) |
| ZeroInt32Value JSON parse | 142.39 | — | — | 1257.93 (8.83x) | 290.43 (2.04x) |
| NegativeInt32Value JSON stringify | 61.90 | — | — | 797.42 (12.88x) | 220.16 (3.56x) |
| NegativeInt32Value JSON parse | 159.39 | — | — | 1396.32 (8.76x) | 314.22 (1.97x) |
| MinInt32Value JSON stringify | 49.55 | — | — | 655.79 (13.23x) | 133.17 (2.69x) |
| MinInt32Value JSON parse | 149.41 | — | — | 1322.62 (8.85x) | 434.19 (2.91x) |
| MaxInt32Value JSON stringify | 63.37 | — | — | 650.50 (10.27x) | 130.92 (2.07x) |
| MaxInt32Value JSON parse | 179.75 | — | — | 1336.63 (7.44x) | 313.29 (1.74x) |
| UInt32Value JSON stringify | 61.33 | — | — | 642.69 (10.48x) | 159.33 (2.60x) |
| UInt32Value JSON parse | 132.12 | — | — | 1292.53 (9.78x) | 286.89 (2.17x) |
| UInt32Value String JSON parse | 135.45 | — | — | 1269.08 (9.37x) | 502.43 (3.71x) |
| UInt32Value Exponent JSON parse | 135.28 | — | — | 1495.10 (11.05x) | 379.83 (2.81x) |
| ZeroUInt32Value JSON stringify | 46.68 | — | — | 626.10 (13.41x) | 125.12 (2.68x) |
| ZeroUInt32Value JSON parse | 128.49 | — | — | 1446.67 (11.26x) | 243.34 (1.89x) |
| MaxUInt32Value JSON stringify | 47.32 | — | — | 639.14 (13.51x) | 137.06 (2.90x) |
| MaxUInt32Value JSON parse | 136.96 | — | — | 1457.22 (10.64x) | 313.84 (2.29x) |
| BoolValue JSON stringify | 45.29 | — | — | 623.22 (13.76x) | 125.76 (2.78x) |
| BoolValue JSON parse | 59.90 | — | — | 1233.01 (20.58x) | 288.68 (4.82x) |
| FalseBoolValue JSON stringify | 45.23 | — | — | 611.88 (13.53x) | 132.33 (2.93x) |
| FalseBoolValue JSON parse | 60.40 | — | — | 1168.63 (19.35x) | 247.04 (4.09x) |
| StringValue JSON stringify | 52.60 | — | — | 782.71 (14.88x) | 316.26 (6.01x) |
| StringValue JSON parse | 119.81 | — | — | 1487.14 (12.41x) | 361.88 (3.02x) |
| StringValue Escape JSON parse | 129.60 | — | — | 1453.32 (11.21x) | 365.82 (2.82x) |
| StringValue Surrogate JSON parse | 126.85 | — | — | 1342.29 (10.58x) | 473.60 (3.73x) |
| EmptyStringValue JSON stringify | 48.71 | — | — | 657.68 (13.50x) | 175.90 (3.61x) |
| EmptyStringValue JSON parse | 66.23 | — | — | 1210.27 (18.27x) | 294.59 (4.45x) |
| BytesValue JSON stringify | 49.27 | — | — | 673.30 (13.67x) | 188.84 (3.83x) |
| BytesValue JSON parse | 125.42 | — | — | 1396.40 (11.13x) | 432.44 (3.45x) |
| BytesValue URL JSON parse | 142.40 | — | — | 1427.19 (10.02x) | 325.15 (2.28x) |
| BytesValue StandardBase64 JSON parse | 124.71 | — | — | 1328.30 (10.65x) | 316.41 (2.54x) |
| BytesValue Unpadded JSON parse | 124.08 | — | — | 1505.55 (12.13x) | 552.74 (4.45x) |
| EmptyBytesValue JSON stringify | 41.00 | — | — | 747.24 (18.23x) | 191.08 (4.66x) |
| EmptyBytesValue JSON parse | 70.70 | — | — | 1336.83 (18.91x) | 438.79 (6.21x) |
| TextFormat format | 186.32 | — | — | 3103.11 (16.65x) | 3002.72 (16.12x) |
| TextFormat parse | 705.78 | — | — | 5915.99 (8.38x) | 7673.49 (10.87x) |
| packed fixed32 encode | 3.56 | 587.01 (164.89x) | 542.88 (152.49x) | 39.43 (11.08x) | 428.41 (120.34x) |
| packed fixed32 decode | 8.64 | 1111.14 (128.60x) | 2275.27 (263.34x) | 49.75 (5.76x) | 2158.46 (249.82x) |
| packed fixed64 encode | 2.74 | 575.37 (209.99x) | 560.78 (204.66x) | 82.82 (30.23x) | 389.80 (142.26x) |
| packed fixed64 decode | 8.64 | 1076.10 (124.55x) | 8531.86 (987.48x) | 85.57 (9.90x) | 2997.24 (346.90x) |
| packed sfixed32 encode | 2.01 | 567.89 (282.53x) | 549.86 (273.56x) | 43.96 (21.87x) | 396.72 (197.37x) |
| packed sfixed32 decode | 4.52 | 1101.89 (243.78x) | 2304.27 (509.79x) | 48.96 (10.83x) | 2393.47 (529.53x) |
| packed sfixed64 encode | 2.01 | 576.58 (286.86x) | 561.32 (279.26x) | 80.38 (39.99x) | 476.93 (237.28x) |
| packed sfixed64 decode | 4.54 | 1182.57 (260.48x) | 8475.41 (1866.83x) | 79.43 (17.50x) | 3050.37 (671.89x) |
| packed float encode | 2.00 | 853.24 (426.62x) | 539.80 (269.90x) | 44.04 (22.02x) | 358.55 (179.28x) |
| packed float decode | 4.53 | 1133.37 (250.19x) | 2402.04 (530.25x) | 66.17 (14.61x) | 2083.77 (459.99x) |
| packed double encode | 2.12 | 831.67 (392.30x) | 605.91 (285.81x) | 70.36 (33.19x) | 365.76 (172.53x) |
| packed double decode | 8.87 | 1142.54 (128.81x) | 2379.75 (268.29x) | 79.84 (9.00x) | 3031.60 (341.78x) |
| packed uint64 encode | 1294.24 | 5285.93 (4.08x) | 4788.06 (3.70x) | 2644.27 (2.04x) | 4310.68 (3.33x) |
| packed uint64 decode | 1781.27 | 3526.18 (1.98x) | 9767.83 (5.48x) | 3529.08 (1.98x) | 9216.69 (5.17x) |
| packed uint32 encode | 1072.74 | 4279.08 (3.99x) | 3904.22 (3.64x) | 2132.99 (1.99x) | 3714.07 (3.46x) |
| packed uint32 decode | 1296.75 | 2957.15 (2.28x) | 3835.32 (2.96x) | 2517.13 (1.94x) | 7073.72 (5.45x) |
| packed int64 encode | 1345.08 | 15095.53 (11.22x) | 7142.49 (5.31x) | 3710.43 (2.76x) | 5161.67 (3.84x) |
| packed int64 decode | 2744.92 | 4222.51 (1.54x) | 11357.44 (4.14x) | 5496.20 (2.00x) | 11916.67 (4.34x) |
| packed sint32 encode | 787.78 | 3752.58 (4.76x) | 3266.36 (4.15x) | 2007.93 (2.55x) | 4381.27 (5.56x) |
| packed sint32 decode | 1047.73 | 3037.61 (2.90x) | 3943.70 (3.76x) | 1732.00 (1.65x) | 4752.22 (4.54x) |
| packed sint64 encode | 1432.60 | 5823.19 (4.06x) | 5084.67 (3.55x) | 4109.84 (2.87x) | 5165.68 (3.61x) |
| packed sint64 decode | 2032.27 | 3969.69 (1.95x) | 10399.75 (5.12x) | 3649.91 (1.80x) | 9496.99 (4.67x) |
| packed bool encode | 2.51 | 1476.04 (588.06x) | 525.81 (209.49x) | 15.70 (6.26x) | 2669.19 (1063.42x) |
| packed bool decode | 262.92 | 1901.99 (7.23x) | 2783.47 (10.59x) | 825.34 (3.14x) | 2008.90 (7.64x) |
| packed enum encode | 271.53 | 3161.89 (11.64x) | 2025.98 (7.46x) | 1212.26 (4.46x) | 3173.44 (11.69x) |
| packed enum decode | 156.32 | 1913.37 (12.24x) | 3195.23 (20.44x) | 867.82 (5.55x) | 2823.58 (18.06x) |
| large map encode | 3970.39 | 17838.05 (4.49x) | 9779.76 (2.46x) | 25422.20 (6.40x) | 228222.67 (57.48x) |
| shuffled large map deterministic binary encode | 29974.57 | — | — | 102644.00 (3.42x) | 411234.88 (13.72x) |
| large map decode | 27655.50 | 109235.31 (3.95x) | 102705.35 (3.71x) | 107436.00 (3.88x) | 325251.05 (11.76x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON (including generated `map<string, int32>` surrogate-pair key parse, null-field parse, ignore-unknown parse, enum-name parse, always-print default-value stringify, enum-number stringify, proto-name stringify, proto-name parse, open-enum numeric parse, and integer numeric-exponent parse), Any/WKT JSON (including embedded zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound `Duration`, non-empty/escaped-input parse/number-exponent parse/surrogate-pair value parse/surrogate-pair key parse and empty `Struct`, object/escaped-object parse/object-number-exponent/object-surrogate-pair value parse/object-surrogate-pair key parse/list/escaped-list/surrogate-list/string-scalar/escaped-string-scalar/surrogate-string-scalar/number-exponent/negative-number `Value` (including default-like scalar and empty object/list kinds),
`FieldMask` (non-empty, escaped JSON parse input, and empty), escaped-input parse/short-fraction parse/micro/nano/offset/min/pre/post/max-bound `Timestamp`, `Empty`, min/zero/positive/number-input parse/numeric-exponent parse/negative/max `Int64Value`, negative/zero/positive finite/string-input parse/numeric-exponent parse `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), negative/zero/positive finite/string-input parse/numeric-exponent parse `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), zero/normal/number-input parse/numeric-exponent parse/max `UInt64Value`, min/zero/positive/string-input parse/numeric-exponent parse/negative/max `Int32Value`, zero/normal/string-input parse/numeric-exponent parse/max `UInt32Value`, true/false `BoolValue`, non-empty/escape-input parse/surrogate-pair parse/empty `StringValue`, padded-standard/base64url/unpadded-base64 parse/empty `BytesValue`, and recursive nested `Any` payloads), direct zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound Duration, non-empty/escaped-input parse/empty FieldMask, and escaped-input parse/short-fraction parse/micro/nano/offset/min/pre/post/max-bound Timestamp WKT JSON plus other direct WKT JSON, including non-empty/escaped-input parse/number-exponent parse/surrogate-pair value parse/surrogate-pair key parse/empty `Struct`, object/escaped-object parse/object-number-exponent/object-surrogate-pair value parse/object-surrogate-pair key parse/list/escaped-list/surrogate-list/string-scalar/escaped-string-scalar/surrogate-string-scalar/number-exponent/negative-number `Value`, and escaped/surrogate-pair/non-empty/empty `ListValue`, TextFormat, packed scalars, large bytes,
maps, oneof/optional workloads (including PresenceMix JSON), and complex nested messages. Benchmark results are hardware-sensitive; compare full same-machine
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
