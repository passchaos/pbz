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

Latest accepted comparison (`/tmp/pbz-compare-null-fields-json-final.log`,
summarized in `/tmp/pbz-summary-null-fields-json-final.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 29.81 | 99.67 (3.34x) | 52.11 (1.75x) | 122.64 (4.11x) | 839.14 (28.15x) |
| binary decode | 139.70 | 257.24 (1.84x) | 226.10 (1.62x) | 213.22 (1.53x) | 898.10 (6.43x) |
| unknown fields count by number | 3.58 | — | — | 226.62 (63.30x) | — |
| deterministic binary encode | 71.79 | — | — | 124.57 (1.74x) | 1101.25 (15.34x) |
| scalarmix encode | 27.93 | 113.56 (4.07x) | 49.52 (1.77x) | 30.82 (1.10x) | 237.90 (8.52x) |
| scalarmix decode | 62.39 | 137.32 (2.20x) | 174.90 (2.80x) | 86.01 (1.38x) | 326.56 (5.23x) |
| textbytes encode | 17.04 | 76.28 (4.48x) | 33.42 (1.96x) | 119.00 (6.98x) | 181.56 (10.65x) |
| textbytes decode | 62.21 | 426.61 (6.86x) | 314.05 (5.05x) | 167.81 (2.70x) | 677.52 (10.89x) |
| largebytes encode | 26.50 | 2831.70 (106.86x) | 3847.59 (145.19x) | 2885.99 (108.91x) | 3214.37 (121.30x) |
| largebytes decode | 116.10 | 6323.27 (54.46x) | 3759.88 (32.38x) | 2828.39 (24.36x) | 33850.42 (291.56x) |
| presencemix encode | 17.79 | 59.29 (3.33x) | 42.50 (2.39x) | 55.11 (3.10x) | 228.17 (12.83x) |
| presencemix decode | 55.64 | 173.39 (3.12x) | 159.83 (2.87x) | 163.93 (2.95x) | 605.46 (10.88x) |
| complex encode | 52.07 | 140.61 (2.70x) | 137.87 (2.65x) | 169.70 (3.26x) | 975.02 (18.73x) |
| complex decode | 227.92 | 396.61 (1.74x) | 494.35 (2.17x) | 395.18 (1.73x) | 1708.64 (7.50x) |
| complex deterministic binary encode | 93.48 | — | — | 169.87 (1.82x) | 1270.70 (13.59x) |
| complex JSON stringify | 248.04 | — | — | 6389.64 (25.76x) | 7855.80 (31.67x) |
| complex JSON parse | 2420.34 | — | — | 14924.80 (6.17x) | 9225.09 (3.81x) |
| complex TextFormat format | 238.92 | — | — | 4466.25 (18.69x) | 6860.87 (28.72x) |
| complex TextFormat parse | 1841.29 | — | — | 8050.66 (4.37x) | 10544.56 (5.73x) |
| packed int32 encode | 783.82 | 4314.04 (5.50x) | 2847.32 (3.63x) | 1632.95 (2.08x) | 3797.53 (4.84x) |
| packed int32 decode | 695.67 | 2602.48 (3.74x) | 4277.49 (6.15x) | 1217.95 (1.75x) | 5145.39 (7.40x) |
| JSON stringify | 154.45 | — | — | 3741.46 (24.22x) | 2636.10 (17.07x) |
| JSON parse | 1504.90 | — | — | 9427.18 (6.26x) | 5261.78 (3.50x) |
| MapKeySurrogate JSON parse | 430.29 | — | — | 4428.45 (10.29x) | 1175.97 (2.73x) |
| NullFields JSON parse | 780.16 | — | — | 2517.45 (3.23x) | 859.51 (1.10x) |
| IntExponent JSON parse | 2139.16 | — | — | 8855.92 (4.14x) | 4871.24 (2.28x) |
| Any WKT JSON stringify | 127.52 | — | — | 2318.85 (18.18x) | 1453.44 (11.40x) |
| Any WKT JSON parse | 524.88 | — | — | 3962.74 (7.55x) | 1762.91 (3.36x) |
| Any Duration Escape WKT JSON parse | 895.03 | — | — | 3699.49 (4.13x) | 2033.69 (2.27x) |
| Any PlusDuration WKT JSON parse | 865.45 | — | — | 3733.68 (4.31x) | 2040.10 (2.36x) |
| Any ShortFractionDuration WKT JSON parse | 619.17 | — | — | 3970.67 (6.41x) | 2069.67 (3.34x) |
| Any MicroDuration WKT JSON stringify | 205.16 | — | — | 2561.47 (12.49x) | 1230.00 (6.00x) |
| Any MicroDuration WKT JSON parse | 618.08 | — | — | 3797.27 (6.14x) | 1917.99 (3.10x) |
| Any NanoDuration WKT JSON stringify | 133.14 | — | — | 3104.55 (23.32x) | 1251.23 (9.40x) |
| Any NanoDuration WKT JSON parse | 546.41 | — | — | 4190.84 (7.67x) | 2108.91 (3.86x) |
| Any NegativeDuration WKT JSON stringify | 133.67 | — | — | 2557.55 (19.13x) | 1246.23 (9.32x) |
| Any NegativeDuration WKT JSON parse | 532.24 | — | — | 4453.84 (8.37x) | 2115.77 (3.98x) |
| Any FractionalNegativeDuration WKT JSON stringify | 122.81 | — | — | 2287.85 (18.63x) | 1331.72 (10.84x) |
| Any FractionalNegativeDuration WKT JSON parse | 520.60 | — | — | 3516.93 (6.76x) | 1820.81 (3.50x) |
| Any MaxDuration WKT JSON stringify | 116.72 | — | — | 2173.57 (18.62x) | 1206.79 (10.34x) |
| Any MaxDuration WKT JSON parse | 548.14 | — | — | 3812.71 (6.96x) | 1893.87 (3.46x) |
| Any MinDuration WKT JSON stringify | 118.04 | — | — | 2303.22 (19.51x) | 1092.98 (9.26x) |
| Any MinDuration WKT JSON parse | 747.02 | — | — | 3767.99 (5.04x) | 1993.57 (2.67x) |
| Any ZeroDuration WKT JSON stringify | 202.92 | — | — | 1045.22 (5.15x) | 1239.11 (6.11x) |
| Any ZeroDuration WKT JSON parse | 743.63 | — | — | 2837.80 (3.82x) | 1814.22 (2.44x) |
| Any FieldMask WKT JSON stringify | 288.75 | — | — | 2101.16 (7.28x) | 1812.41 (6.28x) |
| Any FieldMask WKT JSON parse | 865.49 | — | — | 4115.97 (4.76x) | 2779.14 (3.21x) |
| Any FieldMask Escape WKT JSON parse | 766.30 | — | — | 3889.41 (5.08x) | 3282.83 (4.28x) |
| Any EmptyFieldMask WKT JSON stringify | 112.44 | — | — | 1159.62 (10.31x) | 957.46 (8.52x) |
| Any EmptyFieldMask WKT JSON parse | 446.99 | — | — | 2903.42 (6.50x) | 1525.71 (3.41x) |
| Any Timestamp WKT JSON stringify | 172.75 | — | — | 2505.12 (14.50x) | 1309.55 (7.58x) |
| Any Timestamp WKT JSON parse | 574.41 | — | — | 3736.62 (6.51x) | 2193.96 (3.82x) |
| Any Timestamp Escape WKT JSON parse | 588.12 | — | — | 3761.28 (6.40x) | 2447.79 (4.16x) |
| Any ShortFraction Timestamp WKT JSON parse | 569.25 | — | — | 3745.18 (6.58x) | 1971.81 (3.46x) |
| Any Micro Timestamp WKT JSON stringify | 361.96 | — | — | 2413.98 (6.67x) | 1361.08 (3.76x) |
| Any Micro Timestamp WKT JSON parse | 983.85 | — | — | 3778.74 (3.84x) | 1998.41 (2.03x) |
| Any Nano Timestamp WKT JSON stringify | 286.57 | — | — | 2918.74 (10.19x) | 1507.71 (5.26x) |
| Any Nano Timestamp WKT JSON parse | 847.47 | — | — | 3811.88 (4.50x) | 2125.45 (2.51x) |
| Any Offset Timestamp WKT JSON parse | 738.78 | — | — | 3779.47 (5.12x) | 2068.65 (2.80x) |
| Any PreEpoch Timestamp WKT JSON stringify | 205.20 | — | — | 3385.76 (16.50x) | 1163.69 (5.67x) |
| Any PreEpoch Timestamp WKT JSON parse | 687.07 | — | — | 5193.34 (7.56x) | 1988.45 (2.89x) |
| Any Max Timestamp WKT JSON stringify | 224.32 | — | — | 3298.18 (14.70x) | 1252.10 (5.58x) |
| Any Max Timestamp WKT JSON parse | 695.04 | — | — | 4143.02 (5.96x) | 2095.90 (3.02x) |
| Any Min Timestamp WKT JSON stringify | 229.27 | — | — | 2463.07 (10.74x) | 1345.21 (5.87x) |
| Any Min Timestamp WKT JSON parse | 646.50 | — | — | 4289.65 (6.64x) | 2068.78 (3.20x) |
| Any Empty WKT JSON stringify | 118.55 | — | — | 1033.52 (8.72x) | 770.60 (6.50x) |
| Any Empty WKT JSON parse | 390.87 | — | — | 2790.87 (7.14x) | 1584.62 (4.05x) |
| Any Struct WKT JSON stringify | 789.02 | — | — | 7174.86 (9.09x) | 8505.39 (10.78x) |
| Any Struct WKT JSON parse | 2075.08 | — | — | 14083.10 (6.79x) | 11595.37 (5.59x) |
| Any Struct Escape WKT JSON parse | 2097.57 | — | — | 13927.70 (6.64x) | 11922.43 (5.68x) |
| Any Struct NumberExponent WKT JSON parse | 2056.80 | — | — | 13916.10 (6.77x) | 11060.10 (5.38x) |
| Any Struct Surrogate WKT JSON parse | 873.55 | — | — | 7891.49 (9.03x) | 3988.00 (4.57x) |
| Any Struct KeySurrogate WKT JSON parse | 894.63 | — | — | 7666.32 (8.57x) | 4532.05 (5.07x) |
| Any EmptyStruct WKT JSON stringify | 156.50 | — | — | 1069.21 (6.83x) | 1233.38 (7.88x) |
| Any EmptyStruct WKT JSON parse | 545.53 | — | — | 2863.70 (5.25x) | 1932.02 (3.54x) |
| Any Value WKT JSON stringify | 836.55 | — | — | 7364.70 (8.80x) | 8753.50 (10.46x) |
| Any Value WKT JSON parse | 2112.03 | — | — | 14925.40 (7.07x) | 12200.61 (5.78x) |
| Any Value Escape WKT JSON parse | 2162.35 | — | — | 14315.50 (6.62x) | 11626.27 (5.38x) |
| Any Value NumberExponent WKT JSON parse | 2146.19 | — | — | 14077.40 (6.56x) | 11738.24 (5.47x) |
| Any Value Surrogate WKT JSON parse | 929.81 | — | — | 7900.14 (8.50x) | 4669.55 (5.02x) |
| Any Value KeySurrogate WKT JSON parse | 928.75 | — | — | 7894.80 (8.50x) | 4675.23 (5.03x) |
| Any NullValue WKT JSON stringify | 155.93 | — | — | 2715.86 (17.42x) | 1023.51 (6.56x) |
| Any NullValue WKT JSON parse | 544.14 | — | — | 5129.09 (9.43x) | 1886.77 (3.47x) |
| Any StringScalarValue WKT JSON stringify | 204.14 | — | — | 2640.20 (12.93x) | 1424.64 (6.98x) |
| Any StringScalarValue WKT JSON parse | 634.29 | — | — | 4350.81 (6.86x) | 2215.37 (3.49x) |
| Any StringScalarValue Escape WKT JSON parse | 645.06 | — | — | 4347.96 (6.74x) | 2268.29 (3.52x) |
| Any StringScalarValue Surrogate WKT JSON parse | 649.69 | — | — | 4364.20 (6.72x) | 2394.22 (3.69x) |
| Any EmptyStringScalarValue WKT JSON stringify | 173.08 | — | — | 2608.25 (15.07x) | 1178.52 (6.81x) |
| Any EmptyStringScalarValue WKT JSON parse | 570.67 | — | — | 4313.01 (7.56x) | 2115.92 (3.71x) |
| Any NumberValue WKT JSON stringify | 236.77 | — | — | 3083.72 (13.02x) | 1173.96 (4.96x) |
| Any NumberValue WKT JSON parse | 573.61 | — | — | 4778.49 (8.33x) | 1891.02 (3.30x) |
| Any NumberValue Exponent WKT JSON parse | 577.46 | — | — | 4362.99 (7.56x) | 2125.02 (3.68x) |
| Any NegativeNumberValue WKT JSON stringify | 231.57 | — | — | 3238.19 (13.98x) | 1475.31 (6.37x) |
| Any NegativeNumberValue WKT JSON parse | 584.95 | — | — | 4469.82 (7.64x) | 2107.68 (3.60x) |
| Any ZeroNumberValue WKT JSON stringify | 175.16 | — | — | 2935.91 (16.76x) | 997.90 (5.70x) |
| Any ZeroNumberValue WKT JSON parse | 577.13 | — | — | 4356.23 (7.55x) | 2103.04 (3.64x) |
| Any BoolScalarValue WKT JSON stringify | 156.41 | — | — | 3140.10 (20.08x) | 991.25 (6.34x) |
| Any BoolScalarValue WKT JSON parse | 558.28 | — | — | 4629.32 (8.29x) | 1836.19 (3.29x) |
| Any FalseBoolScalarValue WKT JSON stringify | 166.19 | — | — | 2889.18 (17.38x) | 1139.59 (6.86x) |
| Any FalseBoolScalarValue WKT JSON parse | 577.93 | — | — | 4365.18 (7.55x) | 2022.79 (3.50x) |
| Any ListKindValue WKT JSON stringify | 656.87 | — | — | 6874.98 (10.47x) | 6402.03 (9.75x) |
| Any ListKindValue WKT JSON parse | 1640.92 | — | — | 12075.30 (7.36x) | 9521.62 (5.80x) |
| Any ListKindValue Escape WKT JSON parse | 1612.33 | — | — | 12133.20 (7.53x) | 9978.81 (6.19x) |
| Any ListKindValue Surrogate WKT JSON parse | 831.01 | — | — | 6013.23 (7.24x) | 3752.85 (4.52x) |
| Any EmptyStructKindValue WKT JSON stringify | 187.37 | — | — | 3586.77 (19.14x) | 1514.35 (8.08x) |
| Any EmptyStructKindValue WKT JSON parse | 624.34 | — | — | 7037.62 (11.27x) | 2622.17 (4.20x) |
| Any EmptyListKindValue WKT JSON stringify | 192.66 | — | — | 3597.31 (18.67x) | 1665.85 (8.65x) |
| Any EmptyListKindValue WKT JSON parse | 632.71 | — | — | 7353.17 (11.62x) | 2295.49 (3.63x) |
| Any DoubleValue WKT JSON stringify | 264.99 | — | — | 2157.44 (8.14x) | 941.51 (3.55x) |
| Any DoubleValue WKT JSON parse | 625.66 | — | — | 3291.21 (5.26x) | 1867.02 (2.98x) |
| Any DoubleValue String WKT JSON parse | 621.47 | — | — | 3387.64 (5.45x) | 1889.00 (3.04x) |
| Any DoubleValue Exponent WKT JSON parse | 593.21 | — | — | 3360.79 (5.67x) | 1778.37 (3.00x) |
| Any NegativeDoubleValue WKT JSON stringify | 197.64 | — | — | 2218.32 (11.22x) | 924.97 (4.68x) |
| Any NegativeDoubleValue WKT JSON parse | 802.55 | — | — | 3624.18 (4.52x) | 2109.88 (2.63x) |
| Any ZeroDoubleValue WKT JSON stringify | 283.03 | — | — | 1083.29 (3.83x) | 739.87 (2.61x) |
| Any ZeroDoubleValue WKT JSON parse | 734.46 | — | — | 2550.85 (3.47x) | 1734.48 (2.36x) |
| Any DoubleValue NaN WKT JSON stringify | 200.77 | — | — | 1927.95 (9.60x) | 938.83 (4.68x) |
| Any DoubleValue NaN WKT JSON parse | 633.83 | — | — | 3268.60 (5.16x) | 1855.24 (2.93x) |
| Any DoubleValue Infinity WKT JSON stringify | 210.50 | — | — | 1934.84 (9.19x) | 819.28 (3.89x) |
| Any DoubleValue Infinity WKT JSON parse | 523.49 | — | — | 3404.70 (6.50x) | 1626.76 (3.11x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 153.52 | — | — | 1925.88 (12.54x) | 977.44 (6.37x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 521.06 | — | — | 3430.09 (6.58x) | 1878.16 (3.60x) |
| Any FloatValue WKT JSON stringify | 184.95 | — | — | 2112.80 (11.42x) | 871.16 (4.71x) |
| Any FloatValue WKT JSON parse | 519.72 | — | — | 3494.34 (6.72x) | 1668.48 (3.21x) |
| Any FloatValue String WKT JSON parse | 541.00 | — | — | 3451.40 (6.38x) | 1831.50 (3.39x) |
| Any FloatValue Exponent WKT JSON parse | 521.70 | — | — | 3409.75 (6.54x) | 1693.79 (3.25x) |
| Any NegativeFloatValue WKT JSON stringify | 192.76 | — | — | 2085.10 (10.82x) | 808.49 (4.19x) |
| Any NegativeFloatValue WKT JSON parse | 776.15 | — | — | 3496.30 (4.50x) | 1762.07 (2.27x) |
| Any ZeroFloatValue WKT JSON stringify | 268.19 | — | — | 1018.52 (3.80x) | 830.92 (3.10x) |
| Any ZeroFloatValue WKT JSON parse | 700.25 | — | — | 2689.77 (3.84x) | 1684.06 (2.40x) |
| Any FloatValue NaN WKT JSON stringify | 198.51 | — | — | 1917.27 (9.66x) | 694.51 (3.50x) |
| Any FloatValue NaN WKT JSON parse | 626.54 | — | — | 3148.31 (5.02x) | 1601.21 (2.56x) |
| Any FloatValue Infinity WKT JSON stringify | 209.68 | — | — | 1900.41 (9.06x) | 787.91 (3.76x) |
| Any FloatValue Infinity WKT JSON parse | 628.15 | — | — | 3317.51 (5.28x) | 1685.79 (2.68x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 213.40 | — | — | 2058.45 (9.65x) | 905.84 (4.24x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 627.96 | — | — | 3397.70 (5.41x) | 1567.54 (2.50x) |
| Any Int64Value WKT JSON stringify | 212.05 | — | — | 1928.15 (9.09x) | 1141.47 (5.38x) |
| Any Int64Value WKT JSON parse | 574.66 | — | — | 3582.57 (6.23x) | 1956.03 (3.40x) |
| Any Int64Value Number WKT JSON parse | 570.96 | — | — | 3392.71 (5.94x) | 1933.20 (3.39x) |
| Any Int64Value Exponent WKT JSON parse | 553.03 | — | — | 3379.97 (6.11x) | 1798.09 (3.25x) |
| Any ZeroInt64Value WKT JSON stringify | 255.79 | — | — | 987.99 (3.86x) | 881.83 (3.45x) |
| Any ZeroInt64Value WKT JSON parse | 837.85 | — | — | 2666.46 (3.18x) | 1736.76 (2.07x) |
| Any NegativeInt64Value WKT JSON stringify | 201.27 | — | — | 1945.78 (9.67x) | 1179.93 (5.86x) |
| Any NegativeInt64Value WKT JSON parse | 590.21 | — | — | 3554.53 (6.02x) | 2281.44 (3.87x) |
| Any MinInt64Value WKT JSON stringify | 224.19 | — | — | 1894.81 (8.45x) | 960.50 (4.28x) |
| Any MinInt64Value WKT JSON parse | 687.77 | — | — | 3523.47 (5.12x) | 2208.82 (3.21x) |
| Any MaxInt64Value WKT JSON stringify | 217.54 | — | — | 1910.75 (8.78x) | 1267.99 (5.83x) |
| Any MaxInt64Value WKT JSON parse | 692.26 | — | — | 3509.01 (5.07x) | 2071.06 (2.99x) |
| Any UInt64Value WKT JSON stringify | 220.18 | — | — | 2027.45 (9.21x) | 1108.88 (5.04x) |
| Any UInt64Value WKT JSON parse | 652.79 | — | — | 3577.16 (5.48x) | 2027.90 (3.11x) |
| Any UInt64Value Number WKT JSON parse | 650.18 | — | — | 3494.00 (5.37x) | 1983.02 (3.05x) |
| Any UInt64Value Exponent WKT JSON parse | 617.44 | — | — | 3385.29 (5.48x) | 1866.64 (3.02x) |
| Any ZeroUInt64Value WKT JSON stringify | 198.19 | — | — | 1032.19 (5.21x) | 923.84 (4.66x) |
| Any ZeroUInt64Value WKT JSON parse | 607.64 | — | — | 2730.28 (4.49x) | 1776.01 (2.92x) |
| Any MaxUInt64Value WKT JSON stringify | 216.72 | — | — | 2055.33 (9.48x) | 976.13 (4.50x) |
| Any MaxUInt64Value WKT JSON parse | 705.14 | — | — | 3552.53 (5.04x) | 2010.23 (2.85x) |
| Any Int32Value WKT JSON stringify | 220.61 | — | — | 1901.28 (8.62x) | 746.93 (3.39x) |
| Any Int32Value WKT JSON parse | 555.37 | — | — | 3254.13 (5.86x) | 1900.03 (3.42x) |
| Any Int32Value String WKT JSON parse | 554.52 | — | — | 3391.86 (6.12x) | 2019.04 (3.64x) |
| Any Int32Value Exponent WKT JSON parse | 544.28 | — | — | 3458.22 (6.35x) | 1858.37 (3.41x) |
| Any ZeroInt32Value WKT JSON stringify | 164.41 | — | — | 1101.55 (6.70x) | 797.85 (4.85x) |
| Any ZeroInt32Value WKT JSON parse | 536.23 | — | — | 2630.20 (4.90x) | 1784.30 (3.33x) |
| Any NegativeInt32Value WKT JSON stringify | 166.97 | — | — | 1911.63 (11.45x) | 733.44 (4.39x) |
| Any NegativeInt32Value WKT JSON parse | 545.99 | — | — | 3473.89 (6.36x) | 1910.73 (3.50x) |
| Any MinInt32Value WKT JSON stringify | 270.22 | — | — | 1908.41 (7.06x) | 767.32 (2.84x) |
| Any MinInt32Value WKT JSON parse | 919.80 | — | — | 3528.65 (3.84x) | 1727.77 (1.88x) |
| Any MaxInt32Value WKT JSON stringify | 177.21 | — | — | 1929.89 (10.89x) | 967.41 (5.46x) |
| Any MaxInt32Value WKT JSON parse | 563.97 | — | — | 3465.04 (6.14x) | 1693.14 (3.00x) |
| Any UInt32Value WKT JSON stringify | 209.48 | — | — | 1920.62 (9.17x) | 1260.86 (6.02x) |
| Any UInt32Value WKT JSON parse | 543.38 | — | — | 3442.10 (6.33x) | 2782.88 (5.12x) |
| Any UInt32Value String WKT JSON parse | 549.13 | — | — | 3317.63 (6.04x) | 2125.66 (3.87x) |
| Any UInt32Value Exponent WKT JSON parse | 547.20 | — | — | 3194.49 (5.84x) | 2405.10 (4.40x) |
| Any ZeroUInt32Value WKT JSON stringify | 160.17 | — | — | 1061.79 (6.63x) | 938.79 (5.86x) |
| Any ZeroUInt32Value WKT JSON parse | 531.88 | — | — | 2546.91 (4.79x) | 1943.55 (3.65x) |
| Any MaxUInt32Value WKT JSON stringify | 172.05 | — | — | 1959.13 (11.39x) | 887.21 (5.16x) |
| Any MaxUInt32Value WKT JSON parse | 564.93 | — | — | 3400.01 (6.02x) | 2096.54 (3.71x) |
| Any BoolValue WKT JSON stringify | 259.29 | — | — | 1888.58 (7.28x) | 726.07 (2.80x) |
| Any BoolValue WKT JSON parse | 788.70 | — | — | 3337.77 (4.23x) | 1640.30 (2.08x) |
| Any FalseBoolValue WKT JSON stringify | 258.43 | — | — | 964.34 (3.73x) | 745.04 (2.88x) |
| Any FalseBoolValue WKT JSON parse | 696.06 | — | — | 2646.58 (3.80x) | 1713.27 (2.46x) |
| Any StringValue WKT JSON stringify | 199.54 | — | — | 2210.00 (11.08x) | 929.52 (4.66x) |
| Any StringValue WKT JSON parse | 675.33 | — | — | 3587.92 (5.31x) | 1753.73 (2.60x) |
| Any StringValue Escape WKT JSON parse | 556.00 | — | — | 3327.91 (5.99x) | 2253.46 (4.05x) |
| Any StringValue Surrogate WKT JSON parse | 559.91 | — | — | 3240.21 (5.79x) | 2024.02 (3.61x) |
| Any EmptyStringValue WKT JSON stringify | 181.17 | — | — | 981.46 (5.42x) | 834.37 (4.61x) |
| Any EmptyStringValue WKT JSON parse | 519.13 | — | — | 2618.00 (5.04x) | 1763.59 (3.40x) |
| Any BytesValue WKT JSON stringify | 172.69 | — | — | 1966.80 (11.39x) | 924.67 (5.35x) |
| Any BytesValue WKT JSON parse | 586.31 | — | — | 3466.44 (5.91x) | 1735.12 (2.96x) |
| Any BytesValue URL WKT JSON parse | 673.54 | — | — | 3095.62 (4.60x) | 1685.16 (2.50x) |
| Any BytesValue StandardBase64 WKT JSON parse | 920.99 | — | — | 3276.34 (3.56x) | 2146.26 (2.33x) |
| Any BytesValue Unpadded WKT JSON parse | 786.08 | — | — | 3306.57 (4.21x) | 2102.21 (2.67x) |
| Any EmptyBytesValue WKT JSON stringify | 192.59 | — | — | 939.91 (4.88x) | 887.10 (4.61x) |
| Any EmptyBytesValue WKT JSON parse | 534.20 | — | — | 2577.33 (4.82x) | 1828.24 (3.42x) |
| Nested Any WKT JSON stringify | 283.20 | — | — | 3202.11 (11.31x) | 1893.75 (6.69x) |
| Nested Any WKT JSON parse | 869.98 | — | — | 5772.41 (6.64x) | 3308.17 (3.80x) |
| Duration JSON stringify | 57.91 | — | — | 1126.90 (19.46x) | 385.64 (6.66x) |
| Duration JSON parse | 21.20 | — | — | 1837.73 (86.69x) | 390.75 (18.43x) |
| Duration Escape JSON parse | 40.90 | — | — | 1838.26 (44.95x) | 465.78 (11.39x) |
| PlusDuration JSON parse | 20.16 | — | — | 1823.35 (90.44x) | 411.82 (20.43x) |
| ShortFractionDuration JSON parse | 16.13 | — | — | 1794.51 (111.25x) | 393.62 (24.40x) |
| MicroDuration JSON stringify | 59.42 | — | — | 1222.93 (20.58x) | 398.92 (6.71x) |
| MicroDuration JSON parse | 20.73 | — | — | 1860.43 (89.75x) | 392.04 (18.91x) |
| NanoDuration JSON stringify | 57.16 | — | — | 1242.41 (21.74x) | 376.87 (6.59x) |
| NanoDuration JSON parse | 26.44 | — | — | 1801.85 (68.15x) | 392.21 (14.83x) |
| NegativeDuration JSON stringify | 58.19 | — | — | 1154.43 (19.84x) | 429.04 (7.37x) |
| NegativeDuration JSON parse | 20.33 | — | — | 1865.67 (91.77x) | 389.46 (19.16x) |
| FractionalNegativeDuration JSON stringify | 58.14 | — | — | 1135.50 (19.53x) | 441.44 (7.59x) |
| FractionalNegativeDuration JSON parse | 20.56 | — | — | 1853.89 (90.17x) | 379.86 (18.48x) |
| MaxDuration JSON stringify | 49.66 | — | — | 1110.51 (22.36x) | 446.33 (8.99x) |
| MaxDuration JSON parse | 37.24 | — | — | 1949.23 (52.34x) | 431.24 (11.58x) |
| MinDuration JSON stringify | 50.40 | — | — | 941.72 (18.68x) | 415.82 (8.25x) |
| MinDuration JSON parse | 39.20 | — | — | 1800.86 (45.94x) | 425.89 (10.86x) |
| ZeroDuration JSON stringify | 45.26 | — | — | 912.06 (20.15x) | 357.28 (7.89x) |
| ZeroDuration JSON parse | 16.17 | — | — | 1709.71 (105.73x) | 280.31 (17.34x) |
| FieldMask JSON stringify | 67.86 | — | — | 1072.38 (15.80x) | 737.64 (10.87x) |
| FieldMask JSON parse | 140.21 | — | — | 2004.04 (14.29x) | 899.72 (6.42x) |
| FieldMask Escape JSON parse | 190.83 | — | — | 2088.90 (10.95x) | 1363.79 (7.15x) |
| EmptyFieldMask JSON stringify | 40.60 | — | — | 705.62 (17.38x) | 191.30 (4.71x) |
| EmptyFieldMask JSON parse | 4.78 | — | — | 1037.45 (217.04x) | 172.27 (36.04x) |
| Timestamp JSON stringify | 95.11 | — | — | 1481.46 (15.58x) | 516.87 (5.43x) |
| Timestamp JSON parse | 49.56 | — | — | 1844.52 (37.22x) | 430.16 (8.68x) |
| Timestamp Escape JSON parse | 144.53 | — | — | 1942.38 (13.44x) | 547.36 (3.79x) |
| ShortFraction Timestamp JSON parse | 78.35 | — | — | 1810.88 (23.11x) | 458.61 (5.85x) |
| Micro Timestamp JSON stringify | 166.07 | — | — | 1149.69 (6.92x) | 492.45 (2.97x) |
| Micro Timestamp JSON parse | 87.72 | — | — | 1789.31 (20.40x) | 462.31 (5.27x) |
| Nano Timestamp JSON stringify | 162.11 | — | — | 1843.43 (11.37x) | 481.72 (2.97x) |
| Nano Timestamp JSON parse | 92.56 | — | — | 2570.15 (27.77x) | 491.57 (5.31x) |
| Offset Timestamp JSON parse | 94.38 | — | — | 2532.28 (26.83x) | 534.26 (5.66x) |
| PreEpoch Timestamp JSON stringify | 107.81 | — | — | 1647.74 (15.28x) | 518.57 (4.81x) |
| PreEpoch Timestamp JSON parse | 76.36 | — | — | 2475.83 (32.42x) | 437.69 (5.73x) |
| Max Timestamp JSON stringify | 137.40 | — | — | 2109.10 (15.35x) | 463.61 (3.37x) |
| Max Timestamp JSON parse | 96.52 | — | — | 2618.81 (27.13x) | 492.90 (5.11x) |
| Min Timestamp JSON stringify | 147.15 | — | — | 1361.00 (9.25x) | 464.04 (3.15x) |
| Min Timestamp JSON parse | 72.08 | — | — | 1843.75 (25.58x) | 407.51 (5.65x) |
| Empty JSON stringify | 28.73 | — | — | 572.42 (19.92x) | 107.50 (3.74x) |
| Empty JSON parse | 89.41 | — | — | 903.19 (10.10x) | 222.42 (2.49x) |
| Struct JSON stringify | 201.59 | — | — | 7280.99 (36.12x) | 3724.13 (18.47x) |
| Struct JSON parse | 1132.06 | — | — | 13439.30 (11.87x) | 5752.47 (5.08x) |
| Struct Escape JSON parse | 901.12 | — | — | 13517.30 (15.00x) | 6287.61 (6.98x) |
| Struct NumberExponent JSON parse | 847.45 | — | — | 13523.00 (15.96x) | 6159.47 (7.27x) |
| Struct Surrogate JSON parse | 376.46 | — | — | 6104.74 (16.22x) | 1678.08 (4.46x) |
| Struct KeySurrogate JSON parse | 381.17 | — | — | 5918.31 (15.53x) | 1713.69 (4.50x) |
| EmptyStruct JSON stringify | 41.12 | — | — | 743.25 (18.08x) | 336.49 (8.18x) |
| EmptyStruct JSON parse | 92.99 | — | — | 2598.44 (27.94x) | 399.05 (4.29x) |
| Value JSON stringify | 174.42 | — | — | 8237.29 (47.23x) | 4169.61 (23.91x) |
| Value JSON parse | 1325.50 | — | — | 15101.50 (11.39x) | 5776.35 (4.36x) |
| Value Escape JSON parse | 1175.85 | — | — | 15580.60 (13.25x) | 6773.95 (5.76x) |
| Value NumberExponent JSON parse | 860.40 | — | — | 15080.00 (17.53x) | 6233.08 (7.24x) |
| Value Surrogate JSON parse | 392.91 | — | — | 8494.71 (21.62x) | 2011.87 (5.12x) |
| Value KeySurrogate JSON parse | 391.13 | — | — | 8505.73 (21.75x) | 1931.09 (4.94x) |
| NullValue JSON stringify | 40.51 | — | — | 1743.41 (43.04x) | 227.82 (5.62x) |
| NullValue JSON parse | 69.83 | — | — | 2918.49 (41.79x) | 359.22 (5.14x) |
| StringScalarValue JSON stringify | 47.64 | — | — | 1691.31 (35.50x) | 301.71 (6.33x) |
| StringScalarValue JSON parse | 140.73 | — | — | 2459.40 (17.48x) | 484.21 (3.44x) |
| StringScalarValue Escape JSON parse | 150.09 | — | — | 2594.80 (17.29x) | 477.23 (3.18x) |
| StringScalarValue Surrogate JSON parse | 148.86 | — | — | 2589.19 (17.39x) | 478.33 (3.21x) |
| EmptyStringScalarValue JSON stringify | 46.27 | — | — | 1686.36 (36.45x) | 282.85 (6.11x) |
| EmptyStringScalarValue JSON parse | 87.23 | — | — | 2442.70 (28.00x) | 325.73 (3.73x) |
| NumberValue JSON stringify | 72.74 | — | — | 1907.22 (26.22x) | 381.70 (5.25x) |
| NumberValue JSON parse | 131.89 | — | — | 2540.71 (19.26x) | 427.11 (3.24x) |
| NumberValue Exponent JSON parse | 135.01 | — | — | 2659.50 (19.70x) | 441.01 (3.27x) |
| NegativeNumberValue JSON stringify | 73.54 | — | — | 1904.97 (25.90x) | 352.28 (4.79x) |
| NegativeNumberValue JSON parse | 132.40 | — | — | 2617.13 (19.77x) | 469.76 (3.55x) |
| ZeroNumberValue JSON stringify | 50.74 | — | — | 1855.03 (36.56x) | 304.36 (6.00x) |
| ZeroNumberValue JSON parse | 129.67 | — | — | 2457.54 (18.95x) | 374.19 (2.89x) |
| BoolScalarValue JSON stringify | 40.43 | — | — | 1659.30 (41.04x) | 226.52 (5.60x) |
| BoolScalarValue JSON parse | 83.36 | — | — | 2340.92 (28.08x) | 335.12 (4.02x) |
| FalseBoolScalarValue JSON stringify | 54.26 | — | — | 1562.00 (28.79x) | 244.26 (4.50x) |
| FalseBoolScalarValue JSON parse | 83.74 | — | — | 2397.05 (28.62x) | 346.19 (4.13x) |
| ListKindValue JSON stringify | 269.23 | — | — | 7634.17 (28.36x) | 2797.07 (10.39x) |
| ListKindValue JSON parse | 1011.32 | — | — | 12827.10 (12.68x) | 4705.10 (4.65x) |
| ListKindValue Escape JSON parse | 910.01 | — | — | 13354.20 (14.67x) | 5568.92 (6.12x) |
| ListKindValue Surrogate JSON parse | 374.28 | — | — | 5943.29 (15.88x) | 1720.35 (4.60x) |
| EmptyStructKindValue JSON stringify | 56.87 | — | — | 2323.13 (40.85x) | 678.62 (11.93x) |
| EmptyStructKindValue JSON parse | 127.26 | — | — | 4873.64 (38.30x) | 597.62 (4.70x) |
| EmptyListKindValue JSON stringify | 41.31 | — | — | 2285.11 (55.32x) | 383.75 (9.29x) |
| EmptyListKindValue JSON parse | 146.70 | — | — | 4735.99 (32.28x) | 760.32 (5.18x) |
| ListValue JSON stringify | 137.36 | — | — | 5728.57 (41.70x) | 2750.22 (20.02x) |
| ListValue JSON parse | 662.35 | — | — | 10571.00 (15.96x) | 5095.97 (7.69x) |
| ListValue Escape JSON parse | 682.69 | — | — | 10568.50 (15.48x) | 5277.21 (7.73x) |
| ListValue Surrogate JSON parse | 305.88 | — | — | 3753.14 (12.27x) | 1059.79 (3.46x) |
| EmptyListValue JSON stringify | 40.22 | — | — | 744.87 (18.52x) | 176.92 (4.40x) |
| EmptyListValue JSON parse | 134.12 | — | — | 2732.27 (20.37x) | 377.15 (2.81x) |
| DoubleValue JSON stringify | 67.57 | — | — | 992.13 (14.68x) | 223.23 (3.30x) |
| DoubleValue JSON parse | 118.33 | — | — | 1522.05 (12.86x) | 329.72 (2.79x) |
| DoubleValue String JSON parse | 111.28 | — | — | 1514.30 (13.61x) | 389.21 (3.50x) |
| DoubleValue Exponent JSON parse | 120.26 | — | — | 1611.24 (13.40x) | 265.82 (2.21x) |
| NegativeDoubleValue JSON stringify | 67.72 | — | — | 985.83 (14.56x) | 277.21 (4.09x) |
| NegativeDoubleValue JSON parse | 119.15 | — | — | 1598.44 (13.42x) | 284.24 (2.39x) |
| ZeroDoubleValue JSON stringify | 70.66 | — | — | 915.62 (12.96x) | 135.27 (1.91x) |
| ZeroDoubleValue JSON parse | 141.31 | — | — | 1523.13 (10.78x) | 305.86 (2.16x) |
| DoubleValue NaN JSON stringify | 67.76 | — | — | 692.91 (10.23x) | 215.79 (3.18x) |
| DoubleValue NaN JSON parse | 128.28 | — | — | 1228.19 (9.57x) | 272.58 (2.12x) |
| DoubleValue Infinity JSON stringify | 61.08 | — | — | 1029.94 (16.86x) | 124.75 (2.04x) |
| DoubleValue Infinity JSON parse | 134.81 | — | — | 1335.16 (9.90x) | 320.06 (2.37x) |
| DoubleValue NegativeInfinity JSON stringify | 66.74 | — | — | 1071.03 (16.05x) | 180.17 (2.70x) |
| DoubleValue NegativeInfinity JSON parse | 133.58 | — | — | 1524.64 (11.41x) | 269.61 (2.02x) |
| FloatValue JSON stringify | 97.95 | — | — | 929.27 (9.49x) | 181.10 (1.85x) |
| FloatValue JSON parse | 148.62 | — | — | 1471.94 (9.90x) | 297.00 (2.00x) |
| FloatValue String JSON parse | 143.02 | — | — | 2015.10 (14.09x) | 435.85 (3.05x) |
| FloatValue Exponent JSON parse | 150.23 | — | — | 2066.29 (13.75x) | 344.46 (2.29x) |
| NegativeFloatValue JSON stringify | 122.60 | — | — | 877.75 (7.16x) | 207.93 (1.70x) |
| NegativeFloatValue JSON parse | 145.82 | — | — | 1570.11 (10.77x) | 267.79 (1.84x) |
| ZeroFloatValue JSON stringify | 48.39 | — | — | 763.94 (15.79x) | 192.25 (3.97x) |
| ZeroFloatValue JSON parse | 128.67 | — | — | 1521.76 (11.83x) | 286.57 (2.23x) |
| FloatValue NaN JSON stringify | 69.60 | — | — | 797.25 (11.45x) | 144.18 (2.07x) |
| FloatValue NaN JSON parse | 128.33 | — | — | 1287.37 (10.03x) | 310.27 (2.42x) |
| FloatValue Infinity JSON stringify | 73.71 | — | — | 876.85 (11.90x) | 164.20 (2.23x) |
| FloatValue Infinity JSON parse | 109.49 | — | — | 1254.72 (11.46x) | 281.23 (2.57x) |
| FloatValue NegativeInfinity JSON stringify | 70.03 | — | — | 785.81 (11.22x) | 142.12 (2.03x) |
| FloatValue NegativeInfinity JSON parse | 134.68 | — | — | 1295.01 (9.62x) | 297.30 (2.21x) |
| Int64Value JSON stringify | 65.45 | — | — | 688.41 (10.52x) | 294.96 (4.51x) |
| Int64Value JSON parse | 128.47 | — | — | 1577.14 (12.28x) | 504.08 (3.92x) |
| Int64Value Number JSON parse | 184.16 | — | — | 1639.91 (8.90x) | 378.81 (2.06x) |
| Int64Value Exponent JSON parse | 148.14 | — | — | 1454.87 (9.82x) | 348.32 (2.35x) |
| ZeroInt64Value JSON stringify | 51.24 | — | — | 687.34 (13.41x) | 183.42 (3.58x) |
| ZeroInt64Value JSON parse | 106.20 | — | — | 1352.24 (12.73x) | 347.11 (3.27x) |
| NegativeInt64Value JSON stringify | 50.13 | — | — | 810.79 (16.17x) | 301.42 (6.01x) |
| NegativeInt64Value JSON parse | 127.00 | — | — | 1397.24 (11.00x) | 465.85 (3.67x) |
| MinInt64Value JSON stringify | 49.24 | — | — | 743.89 (15.11x) | 289.76 (5.88x) |
| MinInt64Value JSON parse | 135.42 | — | — | 1507.27 (11.13x) | 688.57 (5.08x) |
| MaxInt64Value JSON stringify | 49.05 | — | — | 851.06 (17.35x) | 300.17 (6.12x) |
| MaxInt64Value JSON parse | 133.33 | — | — | 1603.00 (12.02x) | 524.83 (3.94x) |
| UInt64Value JSON stringify | 49.95 | — | — | 690.30 (13.82x) | 274.93 (5.50x) |
| UInt64Value JSON parse | 128.00 | — | — | 1611.77 (12.59x) | 437.64 (3.42x) |
| UInt64Value Number JSON parse | 131.82 | — | — | 1638.38 (12.43x) | 351.79 (2.67x) |
| UInt64Value Exponent JSON parse | 122.63 | — | — | 1471.23 (12.00x) | 356.60 (2.91x) |
| ZeroUInt64Value JSON stringify | 41.17 | — | — | 647.22 (15.72x) | 190.22 (4.62x) |
| ZeroUInt64Value JSON parse | 107.12 | — | — | 1315.60 (12.28x) | 369.87 (3.45x) |
| MaxUInt64Value JSON stringify | 49.71 | — | — | 690.35 (13.89x) | 304.97 (6.13x) |
| MaxUInt64Value JSON parse | 138.06 | — | — | 1608.82 (11.65x) | 454.14 (3.29x) |
| Int32Value JSON stringify | 46.81 | — | — | 863.75 (18.45x) | 143.60 (3.07x) |
| Int32Value JSON parse | 132.11 | — | — | 1329.63 (10.06x) | 314.10 (2.38x) |
| Int32Value String JSON parse | 135.06 | — | — | 1502.02 (11.12x) | 383.56 (2.84x) |
| Int32Value Exponent JSON parse | 134.92 | — | — | 1603.33 (11.88x) | 367.15 (2.72x) |
| ZeroInt32Value JSON stringify | 46.72 | — | — | 638.03 (13.66x) | 162.27 (3.47x) |
| ZeroInt32Value JSON parse | 127.32 | — | — | 1286.46 (10.10x) | 280.29 (2.20x) |
| NegativeInt32Value JSON stringify | 46.79 | — | — | 658.60 (14.08x) | 151.39 (3.24x) |
| NegativeInt32Value JSON parse | 130.93 | — | — | 1558.86 (11.91x) | 345.57 (2.64x) |
| MinInt32Value JSON stringify | 47.33 | — | — | 710.73 (15.02x) | 166.06 (3.51x) |
| MinInt32Value JSON parse | 136.56 | — | — | 1532.48 (11.22x) | 357.85 (2.62x) |
| MaxInt32Value JSON stringify | 47.26 | — | — | 649.18 (13.74x) | 164.80 (3.49x) |
| MaxInt32Value JSON parse | 137.62 | — | — | 1558.95 (11.33x) | 336.28 (2.44x) |
| UInt32Value JSON stringify | 46.88 | — | — | 701.06 (14.95x) | 134.87 (2.88x) |
| UInt32Value JSON parse | 131.71 | — | — | 1430.28 (10.86x) | 370.14 (2.81x) |
| UInt32Value String JSON parse | 135.69 | — | — | 1347.06 (9.93x) | 400.85 (2.95x) |
| UInt32Value Exponent JSON parse | 135.24 | — | — | 1913.90 (14.15x) | 374.30 (2.77x) |
| ZeroUInt32Value JSON stringify | 62.90 | — | — | 636.77 (10.12x) | 219.29 (3.49x) |
| ZeroUInt32Value JSON parse | 152.10 | — | — | 1363.71 (8.97x) | 276.23 (1.82x) |
| MaxUInt32Value JSON stringify | 64.23 | — | — | 968.97 (15.09x) | 184.28 (2.87x) |
| MaxUInt32Value JSON parse | 182.72 | — | — | 1507.15 (8.25x) | 386.85 (2.12x) |
| BoolValue JSON stringify | 59.77 | — | — | 701.10 (11.73x) | 153.61 (2.57x) |
| BoolValue JSON parse | 74.54 | — | — | 1192.58 (16.00x) | 278.40 (3.73x) |
| FalseBoolValue JSON stringify | 59.73 | — | — | 602.53 (10.09x) | 171.72 (2.87x) |
| FalseBoolValue JSON parse | 74.83 | — | — | 1199.68 (16.03x) | 199.04 (2.66x) |
| StringValue JSON stringify | 75.13 | — | — | 675.83 (9.00x) | 197.88 (2.63x) |
| StringValue JSON parse | 150.30 | — | — | 1477.64 (9.83x) | 286.94 (1.91x) |
| StringValue Escape JSON parse | 164.80 | — | — | 1406.44 (8.53x) | 345.34 (2.10x) |
| StringValue Surrogate JSON parse | 171.82 | — | — | 1466.16 (8.53x) | 424.46 (2.47x) |
| EmptyStringValue JSON stringify | 67.34 | — | — | 676.49 (10.05x) | 256.91 (3.82x) |
| EmptyStringValue JSON parse | 80.45 | — | — | 1248.77 (15.52x) | 260.87 (3.24x) |
| BytesValue JSON stringify | 65.24 | — | — | 679.46 (10.41x) | 231.88 (3.55x) |
| BytesValue JSON parse | 159.65 | — | — | 1453.83 (9.11x) | 348.58 (2.18x) |
| BytesValue URL JSON parse | 147.45 | — | — | 1430.67 (9.70x) | 357.87 (2.43x) |
| BytesValue StandardBase64 JSON parse | 153.69 | — | — | 1580.07 (10.28x) | 351.33 (2.29x) |
| BytesValue Unpadded JSON parse | 153.98 | — | — | 1428.80 (9.28x) | 385.68 (2.50x) |
| EmptyBytesValue JSON stringify | 40.71 | — | — | 653.70 (16.06x) | 186.95 (4.59x) |
| EmptyBytesValue JSON parse | 69.51 | — | — | 1473.72 (21.20x) | 297.30 (4.28x) |
| TextFormat format | 263.41 | — | — | 3132.67 (11.89x) | 3294.88 (12.51x) |
| TextFormat parse | 970.00 | — | — | 6757.69 (6.97x) | 8201.68 (8.46x) |
| packed fixed32 encode | 2.97 | 1019.68 (343.33x) | 670.60 (225.79x) | 91.11 (30.68x) | 396.23 (133.41x) |
| packed fixed32 decode | 7.49 | 1209.25 (161.45x) | 2612.94 (348.86x) | 61.07 (8.15x) | 2711.09 (361.96x) |
| packed fixed64 encode | 2.91 | 579.42 (199.11x) | 590.29 (202.85x) | 75.70 (26.01x) | 581.75 (199.91x) |
| packed fixed64 decode | 8.63 | 1173.20 (135.94x) | 8330.33 (965.28x) | 96.80 (11.22x) | 3833.62 (444.22x) |
| packed sfixed32 encode | 2.01 | 596.83 (296.93x) | 627.78 (312.33x) | 45.71 (22.74x) | 635.15 (316.00x) |
| packed sfixed32 decode | 4.53 | 1178.70 (260.20x) | 2692.46 (594.36x) | 49.54 (10.94x) | 2581.25 (569.81x) |
| packed sfixed64 encode | 2.90 | 743.59 (256.41x) | 673.55 (232.26x) | 75.67 (26.09x) | 455.73 (157.15x) |
| packed sfixed64 decode | 8.39 | 1224.15 (145.91x) | 8319.02 (991.54x) | 82.24 (9.80x) | 3952.60 (471.11x) |
| packed float encode | 2.01 | 894.97 (445.26x) | 590.00 (293.53x) | 45.20 (22.49x) | 644.48 (320.64x) |
| packed float decode | 4.54 | 1116.04 (245.82x) | 2514.21 (553.79x) | 50.15 (11.05x) | 2566.11 (565.22x) |
| packed double encode | 2.01 | 847.59 (421.69x) | 588.44 (292.76x) | 86.32 (42.94x) | 525.51 (261.45x) |
| packed double decode | 4.51 | 1213.05 (268.97x) | 2489.55 (552.01x) | 79.50 (17.63x) | 4281.54 (949.34x) |
| packed uint64 encode | 1288.39 | 5693.35 (4.42x) | 5073.56 (3.94x) | 2674.58 (2.08x) | 8066.51 (6.26x) |
| packed uint64 decode | 1789.59 | 3412.59 (1.91x) | 9222.55 (5.15x) | 3483.57 (1.95x) | 10471.61 (5.85x) |
| packed uint32 encode | 1377.78 | 4313.27 (3.13x) | 4314.86 (3.13x) | 2113.69 (1.53x) | 7512.57 (5.45x) |
| packed uint32 decode | 1364.45 | 2861.65 (2.10x) | 3868.16 (2.83x) | 2454.08 (1.80x) | 14763.11 (10.82x) |
| packed int64 encode | 2409.76 | 13021.13 (5.40x) | 7285.93 (3.02x) | 3867.06 (1.60x) | 6825.34 (2.83x) |
| packed int64 decode | 4001.93 | 4286.78 (1.07x) | 11517.28 (2.88x) | 5674.00 (1.42x) | 29391.50 (7.34x) |
| packed sint32 encode | 781.06 | 3929.92 (5.03x) | 3317.97 (4.25x) | 1957.27 (2.51x) | 4242.85 (5.43x) |
| packed sint32 decode | 953.82 | 3102.65 (3.25x) | 3903.10 (4.09x) | 1574.03 (1.65x) | 10010.76 (10.50x) |
| packed sint64 encode | 1442.66 | 7505.47 (5.20x) | 5411.70 (3.75x) | 3130.17 (2.17x) | 6294.13 (4.36x) |
| packed sint64 decode | 2038.67 | 4033.92 (1.98x) | 10688.49 (5.24x) | 3638.34 (1.78x) | 12728.45 (6.24x) |
| packed bool encode | 2.01 | 1653.72 (822.75x) | 525.58 (261.48x) | 23.16 (11.52x) | 2837.24 (1411.56x) |
| packed bool decode | 264.55 | 2317.30 (8.76x) | 3253.59 (12.30x) | 865.31 (3.27x) | 2841.77 (10.74x) |
| packed enum encode | 497.54 | 5396.85 (10.85x) | 2086.41 (4.19x) | 1193.09 (2.40x) | 3071.12 (6.17x) |
| packed enum decode | 157.43 | 2340.57 (14.87x) | 3245.95 (20.62x) | 1041.17 (6.61x) | 3724.86 (23.66x) |
| large map encode | 4051.90 | 24190.79 (5.97x) | 14205.67 (3.51x) | 26038.70 (6.43x) | 247346.51 (61.04x) |
| shuffled large map deterministic binary encode | 35920.06 | — | — | 94653.40 (2.64x) | 450696.22 (12.55x) |
| large map decode | 27087.01 | 142947.81 (5.28x) | 107716.57 (3.98x) | 113277.00 (4.18x) | 353327.67 (13.04x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON (including generated `map<string, int32>` surrogate-pair key parse, null-field parse, and integer numeric-exponent parse), Any/WKT JSON (including embedded zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound `Duration`, non-empty/escaped-input parse/number-exponent parse/surrogate-pair value parse/surrogate-pair key parse and empty `Struct`, object/escaped-object parse/object-number-exponent/object-surrogate-pair value parse/object-surrogate-pair key parse/list/escaped-list/surrogate-list/string-scalar/escaped-string-scalar/surrogate-string-scalar/number-exponent/negative-number `Value` (including default-like scalar and empty object/list kinds),
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
