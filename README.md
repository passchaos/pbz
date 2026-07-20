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

Latest accepted comparison (`/tmp/pbz-compare-complex-proto-name-json-final.log`,
summarized in `/tmp/pbz-summary-complex-proto-name-json-final.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Pivoted rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 23.35 | 101.25 (4.34x) | 51.14 (2.19x) | 104.48 (4.47x) | 963.03 (41.24x) |
| binary decode | 122.31 | 255.54 (2.09x) | 268.47 (2.19x) | 300.35 (2.46x) | 1233.20 (10.08x) |
| unknown fields count by number | 5.21 | — | — | 161.59 (31.02x) | — |
| deterministic binary encode | 86.39 | — | — | 129.77 (1.50x) | 1198.88 (13.88x) |
| scalarmix encode | 27.68 | 100.24 (3.62x) | 48.46 (1.75x) | 47.98 (1.73x) | 217.05 (7.84x) |
| scalarmix decode | 43.03 | 133.48 (3.10x) | 211.99 (4.93x) | 84.85 (1.97x) | 297.64 (6.92x) |
| textbytes encode | 17.94 | 77.47 (4.32x) | 33.90 (1.89x) | 120.27 (6.70x) | 142.78 (7.96x) |
| textbytes decode | 73.76 | 376.27 (5.10x) | 236.75 (3.21x) | 165.52 (2.24x) | 971.14 (13.17x) |
| largebytes encode | 23.60 | 2743.66 (116.26x) | 2718.14 (115.18x) | 2739.45 (116.08x) | 2779.28 (117.77x) |
| largebytes decode | 87.61 | 6184.70 (70.59x) | 3230.62 (36.88x) | 2804.74 (32.01x) | 35561.17 (405.90x) |
| presencemix encode | 19.67 | 56.00 (2.85x) | 46.10 (2.34x) | 68.12 (3.46x) | 226.78 (11.53x) |
| presencemix decode | 56.61 | 133.52 (2.36x) | 127.42 (2.25x) | 165.37 (2.92x) | 469.37 (8.29x) |
| PresenceMix JSON stringify | 142.92 | — | — | 3674.76 (25.71x) | 3471.52 (24.29x) |
| PresenceMix JSON parse | 1152.18 | — | — | 7443.77 (6.46x) | 3877.54 (3.37x) |
| complex encode | 52.04 | 192.96 (3.71x) | 96.13 (1.85x) | 157.49 (3.03x) | 930.42 (17.88x) |
| complex decode | 247.78 | 384.89 (1.55x) | 356.65 (1.44x) | 397.91 (1.61x) | 1890.86 (7.63x) |
| complex deterministic binary encode | 131.06 | — | — | 235.84 (1.80x) | 1513.08 (11.54x) |
| complex JSON stringify | 366.22 | — | — | 5988.44 (16.35x) | 8978.71 (24.52x) |
| complex JSON parse | 2391.60 | — | — | 14607.00 (6.11x) | 9537.14 (3.99x) |
| Complex ProtoName JSON stringify | 300.46 | — | — | 6535.31 (21.75x) | 8710.86 (28.99x) |
| Complex ProtoName JSON parse | 3085.85 | — | — | 14838.40 (4.81x) | 9496.17 (3.08x) |
| complex TextFormat format | 276.53 | — | — | 4589.47 (16.60x) | 7127.22 (25.77x) |
| complex TextFormat parse | 1768.92 | — | — | 8515.45 (4.81x) | 9887.08 (5.59x) |
| packed int32 encode | 633.35 | 3961.97 (6.26x) | 2904.81 (4.59x) | 1651.21 (2.61x) | 3623.46 (5.72x) |
| packed int32 decode | 687.82 | 2455.10 (3.57x) | 3709.70 (5.39x) | 1197.22 (1.74x) | 3738.88 (5.44x) |
| JSON stringify | 251.48 | — | — | 3752.25 (14.92x) | 2942.76 (11.70x) |
| AlwaysPrint JSON stringify | 60.81 | — | — | 3252.60 (53.49x) | 1746.95 (28.73x) |
| ProtoName JSON stringify | 331.48 | — | — | 5738.29 (17.31x) | 5235.80 (15.80x) |
| EnumNumber JSON stringify | 290.96 | — | — | 5663.37 (19.46x) | 4639.42 (15.95x) |
| JSON parse | 1486.76 | — | — | 9055.30 (6.09x) | 5565.84 (3.74x) |
| MapKeySurrogate JSON parse | 426.62 | — | — | 4196.08 (9.84x) | 1070.94 (2.51x) |
| NullFields JSON parse | 768.14 | — | — | 2389.37 (3.11x) | 806.17 (1.05x) |
| IgnoreUnknown JSON parse | 1752.27 | — | — | 6600.38 (3.77x) | 3212.25 (1.83x) |
| OpenEnum JSON parse | 335.94 | — | — | 4452.87 (13.25x) | 559.89 (1.67x) |
| EnumName JSON parse | 324.22 | — | — | 4603.55 (14.20x) | 609.48 (1.88x) |
| ProtoName JSON parse | 526.81 | — | — | 4782.33 (9.08x) | 1489.63 (2.83x) |
| IntExponent JSON parse | 1714.38 | — | — | 9060.11 (5.28x) | 4815.55 (2.81x) |
| Any WKT JSON stringify | 138.53 | — | — | 2255.55 (16.28x) | 1263.22 (9.12x) |
| Any WKT JSON parse | 523.76 | — | — | 3670.09 (7.01x) | 1829.15 (3.49x) |
| Any Duration Escape WKT JSON parse | 541.04 | — | — | 3380.06 (6.25x) | 1842.64 (3.41x) |
| Any PlusDuration WKT JSON parse | 521.31 | — | — | 3650.59 (7.00x) | 1795.40 (3.44x) |
| Any ShortFractionDuration WKT JSON parse | 520.44 | — | — | 3583.35 (6.89x) | 1771.75 (3.40x) |
| Any MicroDuration WKT JSON stringify | 143.59 | — | — | 2235.66 (15.57x) | 1323.91 (9.22x) |
| Any MicroDuration WKT JSON parse | 525.03 | — | — | 3618.16 (6.89x) | 1845.48 (3.51x) |
| Any NanoDuration WKT JSON stringify | 242.21 | — | — | 2265.27 (9.35x) | 1187.52 (4.90x) |
| Any NanoDuration WKT JSON parse | 847.43 | — | — | 3518.54 (4.15x) | 1829.75 (2.16x) |
| Any NegativeDuration WKT JSON stringify | 249.19 | — | — | 2306.88 (9.26x) | 1625.46 (6.52x) |
| Any NegativeDuration WKT JSON parse | 784.38 | — | — | 3439.92 (4.39x) | 1625.64 (2.07x) |
| Any FractionalNegativeDuration WKT JSON stringify | 187.31 | — | — | 2262.84 (12.08x) | 1209.85 (6.46x) |
| Any FractionalNegativeDuration WKT JSON parse | 688.42 | — | — | 3496.41 (5.08x) | 1776.00 (2.58x) |
| Any MaxDuration WKT JSON stringify | 129.65 | — | — | 2101.46 (16.21x) | 1015.32 (7.83x) |
| Any MaxDuration WKT JSON parse | 540.52 | — | — | 3567.66 (6.60x) | 1979.20 (3.66x) |
| Any MinDuration WKT JSON stringify | 123.22 | — | — | 2134.84 (17.33x) | 1311.34 (10.64x) |
| Any MinDuration WKT JSON parse | 543.00 | — | — | 3673.86 (6.77x) | 2233.35 (4.11x) |
| Any ZeroDuration WKT JSON stringify | 119.40 | — | — | 1034.18 (8.66x) | 992.09 (8.31x) |
| Any ZeroDuration WKT JSON parse | 469.97 | — | — | 2583.40 (5.50x) | 1704.99 (3.63x) |
| Any FieldMask WKT JSON stringify | 232.06 | — | — | 2100.12 (9.05x) | 1742.97 (7.51x) |
| Any FieldMask WKT JSON parse | 703.27 | — | — | 3657.15 (5.20x) | 2397.84 (3.41x) |
| Any FieldMask Escape WKT JSON parse | 1250.28 | — | — | 3914.08 (3.13x) | 2631.64 (2.10x) |
| Any EmptyFieldMask WKT JSON stringify | 140.92 | — | — | 977.77 (6.94x) | 895.49 (6.35x) |
| Any EmptyFieldMask WKT JSON parse | 626.94 | — | — | 2574.92 (4.11x) | 1532.83 (2.44x) |
| Any Timestamp WKT JSON stringify | 316.12 | — | — | 2376.04 (7.52x) | 1111.46 (3.52x) |
| Any Timestamp WKT JSON parse | 567.80 | — | — | 3682.43 (6.49x) | 2057.28 (3.62x) |
| Any Timestamp Escape WKT JSON parse | 583.15 | — | — | 3739.88 (6.41x) | 2041.29 (3.50x) |
| Any ShortFraction Timestamp WKT JSON parse | 562.44 | — | — | 3703.66 (6.58x) | 2085.75 (3.71x) |
| Any Micro Timestamp WKT JSON stringify | 181.43 | — | — | 2390.40 (13.18x) | 1220.52 (6.73x) |
| Any Micro Timestamp WKT JSON parse | 571.65 | — | — | 3695.52 (6.46x) | 2148.04 (3.76x) |
| Any Nano Timestamp WKT JSON stringify | 194.06 | — | — | 2377.46 (12.25x) | 1143.00 (5.89x) |
| Any Nano Timestamp WKT JSON parse | 576.16 | — | — | 3681.43 (6.39x) | 2042.99 (3.55x) |
| Any Offset Timestamp WKT JSON parse | 805.82 | — | — | 3787.83 (4.70x) | 1941.62 (2.41x) |
| Any PreEpoch Timestamp WKT JSON stringify | 283.05 | — | — | 2304.31 (8.14x) | 1341.64 (4.74x) |
| Any PreEpoch Timestamp WKT JSON parse | 936.12 | — | — | 3706.09 (3.96x) | 2059.63 (2.20x) |
| Any Max Timestamp WKT JSON stringify | 309.52 | — | — | 2382.11 (7.70x) | 1191.21 (3.85x) |
| Any Max Timestamp WKT JSON parse | 807.95 | — | — | 3801.06 (4.70x) | 2071.05 (2.56x) |
| Any Min Timestamp WKT JSON stringify | 166.97 | — | — | 2288.01 (13.70x) | 1186.60 (7.11x) |
| Any Min Timestamp WKT JSON parse | 558.23 | — | — | 3693.45 (6.62x) | 1902.60 (3.41x) |
| Any Empty WKT JSON stringify | 98.26 | — | — | 918.38 (9.35x) | 632.77 (6.44x) |
| Any Empty WKT JSON parse | 333.49 | — | — | 2579.54 (7.73x) | 1619.93 (4.86x) |
| Any Struct WKT JSON stringify | 642.72 | — | — | 7241.09 (11.27x) | 7884.44 (12.27x) |
| Any Struct WKT JSON parse | 1773.93 | — | — | 13468.10 (7.59x) | 10711.81 (6.04x) |
| Any Struct Escape WKT JSON parse | 2528.38 | — | — | 13631.80 (5.39x) | 11276.31 (4.46x) |
| Any Struct NumberExponent WKT JSON parse | 1769.62 | — | — | 13456.70 (7.60x) | 10918.03 (6.17x) |
| Any Struct Surrogate WKT JSON parse | 1272.98 | — | — | 7684.38 (6.04x) | 4083.67 (3.21x) |
| Any Struct KeySurrogate WKT JSON parse | 1145.14 | — | — | 7624.91 (6.66x) | 3947.66 (3.45x) |
| Any EmptyStruct WKT JSON stringify | 128.09 | — | — | 982.25 (7.67x) | 968.16 (7.56x) |
| Any EmptyStruct WKT JSON parse | 588.81 | — | — | 2630.84 (4.47x) | 1987.79 (3.38x) |
| Any Value WKT JSON stringify | 669.71 | — | — | 7147.65 (10.67x) | 10630.47 (15.87x) |
| Any Value WKT JSON parse | 1814.33 | — | — | 13519.20 (7.45x) | 11260.06 (6.21x) |
| Any Value Escape WKT JSON parse | 2086.47 | — | — | 13848.60 (6.64x) | 11836.25 (5.67x) |
| Any Value NumberExponent WKT JSON parse | 1806.96 | — | — | 13649.20 (7.55x) | 13762.88 (7.62x) |
| Any Value Surrogate WKT JSON parse | 822.07 | — | — | 7884.01 (9.59x) | 4374.01 (5.32x) |
| Any Value KeySurrogate WKT JSON parse | 822.35 | — | — | 7961.61 (9.68x) | 4378.28 (5.32x) |
| Any NullValue WKT JSON stringify | 201.45 | — | — | 2669.69 (13.25x) | 1213.95 (6.03x) |
| Any NullValue WKT JSON parse | 762.29 | — | — | 4743.03 (6.22x) | 1885.89 (2.47x) |
| Any StringScalarValue WKT JSON stringify | 249.71 | — | — | 2633.00 (10.54x) | 1070.89 (4.29x) |
| Any StringScalarValue WKT JSON parse | 713.13 | — | — | 4279.35 (6.00x) | 2031.93 (2.85x) |
| Any StringScalarValue Escape WKT JSON parse | 742.26 | — | — | 4328.49 (5.83x) | 2154.97 (2.90x) |
| Any StringScalarValue Surrogate WKT JSON parse | 538.31 | — | — | 4379.38 (8.14x) | 2310.15 (4.29x) |
| Any EmptyStringScalarValue WKT JSON stringify | 152.76 | — | — | 2807.15 (18.38x) | 1085.72 (7.11x) |
| Any EmptyStringScalarValue WKT JSON parse | 493.12 | — | — | 4279.28 (8.68x) | 2034.37 (4.13x) |
| Any NumberValue WKT JSON stringify | 188.74 | — | — | 3073.69 (16.29x) | 1161.92 (6.16x) |
| Any NumberValue WKT JSON parse | 508.12 | — | — | 4325.83 (8.51x) | 1943.14 (3.82x) |
| Any NumberValue Exponent WKT JSON parse | 512.29 | — | — | 4456.29 (8.70x) | 2026.72 (3.96x) |
| Any NegativeNumberValue WKT JSON stringify | 271.46 | — | — | 3041.28 (11.20x) | 1368.30 (5.04x) |
| Any NegativeNumberValue WKT JSON parse | 843.85 | — | — | 4430.26 (5.25x) | 2120.32 (2.51x) |
| Any ZeroNumberValue WKT JSON stringify | 255.25 | — | — | 2964.77 (11.62x) | 1151.07 (4.51x) |
| Any ZeroNumberValue WKT JSON parse | 607.28 | — | — | 4342.77 (7.15x) | 1911.92 (3.15x) |
| Any BoolScalarValue WKT JSON stringify | 172.69 | — | — | 2633.79 (15.25x) | 1150.19 (6.66x) |
| Any BoolScalarValue WKT JSON parse | 604.75 | — | — | 4385.24 (7.25x) | 1842.73 (3.05x) |
| Any FalseBoolScalarValue WKT JSON stringify | 171.25 | — | — | 2717.19 (15.87x) | 957.42 (5.59x) |
| Any FalseBoolScalarValue WKT JSON parse | 467.84 | — | — | 4292.25 (9.17x) | 1880.75 (4.02x) |
| Any ListKindValue WKT JSON stringify | 516.04 | — | — | 6725.49 (13.03x) | 6188.58 (11.99x) |
| Any ListKindValue WKT JSON parse | 1425.64 | — | — | 12042.80 (8.45x) | 23632.27 (16.58x) |
| Any ListKindValue Escape WKT JSON parse | 2052.79 | — | — | 12079.00 (5.88x) | 25963.64 (12.65x) |
| Any ListKindValue Surrogate WKT JSON parse | 733.26 | — | — | 5918.78 (8.07x) | 6848.60 (9.34x) |
| Any EmptyStructKindValue WKT JSON stringify | 148.28 | — | — | 3441.79 (23.21x) | 2737.40 (18.46x) |
| Any EmptyStructKindValue WKT JSON parse | 507.82 | — | — | 6511.57 (12.82x) | 5874.63 (11.57x) |
| Any EmptyListKindValue WKT JSON stringify | 151.76 | — | — | 3367.03 (22.19x) | 4182.87 (27.56x) |
| Any EmptyListKindValue WKT JSON parse | 506.05 | — | — | 5346.36 (10.56x) | 5638.11 (11.14x) |
| Any DoubleValue WKT JSON stringify | 191.49 | — | — | 2157.99 (11.27x) | 889.30 (4.64x) |
| Any DoubleValue WKT JSON parse | 532.08 | — | — | 3348.09 (6.29x) | 1821.64 (3.42x) |
| Any DoubleValue String WKT JSON parse | 846.04 | — | — | 3240.17 (3.83x) | 1946.27 (2.30x) |
| Any DoubleValue Exponent WKT JSON parse | 739.86 | — | — | 3392.65 (4.59x) | 1619.62 (2.19x) |
| Any NegativeDoubleValue WKT JSON stringify | 268.33 | — | — | 2170.90 (8.09x) | 892.77 (3.33x) |
| Any NegativeDoubleValue WKT JSON parse | 617.43 | — | — | 3382.33 (5.48x) | 1854.84 (3.00x) |
| Any ZeroDoubleValue WKT JSON stringify | 166.26 | — | — | 1018.92 (6.13x) | 994.54 (5.98x) |
| Any ZeroDoubleValue WKT JSON parse | 524.18 | — | — | 2473.06 (4.72x) | 1664.28 (3.18x) |
| Any DoubleValue NaN WKT JSON stringify | 163.55 | — | — | 1918.60 (11.73x) | 792.20 (4.84x) |
| Any DoubleValue NaN WKT JSON parse | 521.90 | — | — | 3101.45 (5.94x) | 1720.74 (3.30x) |
| Any DoubleValue Infinity WKT JSON stringify | 168.58 | — | — | 1879.27 (11.15x) | 781.97 (4.64x) |
| Any DoubleValue Infinity WKT JSON parse | 521.55 | — | — | 3193.40 (6.12x) | 1719.25 (3.30x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 171.52 | — | — | 1927.96 (11.24x) | 882.10 (5.14x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 527.03 | — | — | 3081.93 (5.85x) | 1740.49 (3.30x) |
| Any FloatValue WKT JSON stringify | 357.32 | — | — | 2113.66 (5.92x) | 888.11 (2.49x) |
| Any FloatValue WKT JSON parse | 850.70 | — | — | 3417.25 (4.02x) | 1779.84 (2.09x) |
| Any FloatValue String WKT JSON parse | 633.06 | — | — | 3316.90 (5.24x) | 1839.77 (2.91x) |
| Any FloatValue Exponent WKT JSON parse | 677.78 | — | — | 3286.63 (4.85x) | 1815.28 (2.68x) |
| Any NegativeFloatValue WKT JSON stringify | 329.17 | — | — | 2158.04 (6.56x) | 974.34 (2.96x) |
| Any NegativeFloatValue WKT JSON parse | 530.51 | — | — | 3379.47 (6.37x) | 1756.44 (3.31x) |
| Any ZeroFloatValue WKT JSON stringify | 161.80 | — | — | 1130.01 (6.98x) | 776.62 (4.80x) |
| Any ZeroFloatValue WKT JSON parse | 523.05 | — | — | 2575.29 (4.92x) | 1729.52 (3.31x) |
| Any FloatValue NaN WKT JSON stringify | 170.22 | — | — | 1904.29 (11.19x) | 805.98 (4.73x) |
| Any FloatValue NaN WKT JSON parse | 520.63 | — | — | 3008.14 (5.78x) | 1784.90 (3.43x) |
| Any FloatValue Infinity WKT JSON stringify | 173.91 | — | — | 1880.40 (10.81x) | 879.00 (5.05x) |
| Any FloatValue Infinity WKT JSON parse | 778.81 | — | — | 3120.85 (4.01x) | 2067.61 (2.65x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 257.27 | — | — | 1831.32 (7.12x) | 752.03 (2.92x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 833.88 | — | — | 3057.58 (3.67x) | 1842.37 (2.21x) |
| Any Int64Value WKT JSON stringify | 213.06 | — | — | 1926.44 (9.04x) | 1206.65 (5.66x) |
| Any Int64Value WKT JSON parse | 752.35 | — | — | 3322.52 (4.42x) | 2021.60 (2.69x) |
| Any Int64Value Number WKT JSON parse | 560.22 | — | — | 3337.39 (5.96x) | 1966.81 (3.51x) |
| Any Int64Value Exponent WKT JSON parse | 539.47 | — | — | 3187.69 (5.91x) | 2007.70 (3.72x) |
| Any ZeroInt64Value WKT JSON stringify | 165.42 | — | — | 1095.34 (6.62x) | 824.28 (4.98x) |
| Any ZeroInt64Value WKT JSON parse | 528.46 | — | — | 2539.06 (4.80x) | 1726.46 (3.27x) |
| Any NegativeInt64Value WKT JSON stringify | 169.13 | — | — | 1983.07 (11.73x) | 1059.70 (6.27x) |
| Any NegativeInt64Value WKT JSON parse | 560.08 | — | — | 3313.20 (5.92x) | 1867.36 (3.33x) |
| Any MinInt64Value WKT JSON stringify | 178.25 | — | — | 1948.36 (10.93x) | 984.42 (5.52x) |
| Any MinInt64Value WKT JSON parse | 927.98 | — | — | 3344.80 (3.60x) | 1989.40 (2.14x) |
| Any MaxInt64Value WKT JSON stringify | 274.56 | — | — | 1761.25 (6.41x) | 1017.05 (3.70x) |
| Any MaxInt64Value WKT JSON parse | 821.95 | — | — | 3555.41 (4.33x) | 2140.69 (2.60x) |
| Any UInt64Value WKT JSON stringify | 225.15 | — | — | 1895.22 (8.42x) | 885.24 (3.93x) |
| Any UInt64Value WKT JSON parse | 706.66 | — | — | 3470.25 (4.91x) | 1888.54 (2.67x) |
| Any UInt64Value Number WKT JSON parse | 558.98 | — | — | 3473.18 (6.21x) | 1799.51 (3.22x) |
| Any UInt64Value Exponent WKT JSON parse | 544.15 | — | — | 3394.14 (6.24x) | 1828.25 (3.36x) |
| Any ZeroUInt64Value WKT JSON stringify | 173.94 | — | — | 1035.08 (5.95x) | 862.82 (4.96x) |
| Any ZeroUInt64Value WKT JSON parse | 530.24 | — | — | 2609.60 (4.92x) | 1778.17 (3.35x) |
| Any MaxUInt64Value WKT JSON stringify | 178.32 | — | — | 1794.11 (10.06x) | 880.39 (4.94x) |
| Any MaxUInt64Value WKT JSON parse | 561.20 | — | — | 3536.06 (6.30x) | 1876.89 (3.34x) |
| Any Int32Value WKT JSON stringify | 180.37 | — | — | 1929.20 (10.70x) | 798.23 (4.43x) |
| Any Int32Value WKT JSON parse | 542.85 | — | — | 3351.83 (6.17x) | 1909.46 (3.52x) |
| Any Int32Value String WKT JSON parse | 870.73 | — | — | 3340.57 (3.84x) | 1785.89 (2.05x) |
| Any Int32Value Exponent WKT JSON parse | 797.75 | — | — | 3328.09 (4.17x) | 1861.84 (2.33x) |
| Any ZeroInt32Value WKT JSON stringify | 243.15 | — | — | 1104.32 (4.54x) | 856.02 (3.52x) |
| Any ZeroInt32Value WKT JSON parse | 709.13 | — | — | 2661.65 (3.75x) | 1724.28 (2.43x) |
| Any NegativeInt32Value WKT JSON stringify | 256.10 | — | — | 1911.38 (7.46x) | 911.12 (3.56x) |
| Any NegativeInt32Value WKT JSON parse | 543.78 | — | — | 3371.66 (6.20x) | 1789.03 (3.29x) |
| Any MinInt32Value WKT JSON stringify | 186.72 | — | — | 1906.99 (10.21x) | 836.77 (4.48x) |
| Any MinInt32Value WKT JSON parse | 549.54 | — | — | 3397.43 (6.18x) | 1854.98 (3.38x) |
| Any MaxInt32Value WKT JSON stringify | 181.76 | — | — | 1915.35 (10.54x) | 861.34 (4.74x) |
| Any MaxInt32Value WKT JSON parse | 550.52 | — | — | 3212.35 (5.84x) | 1750.27 (3.18x) |
| Any UInt32Value WKT JSON stringify | 183.71 | — | — | 1915.67 (10.43x) | 794.71 (4.33x) |
| Any UInt32Value WKT JSON parse | 884.30 | — | — | 3354.21 (3.79x) | 1633.65 (1.85x) |
| Any UInt32Value String WKT JSON parse | 733.08 | — | — | 3346.31 (4.56x) | 1863.74 (2.54x) |
| Any UInt32Value Exponent WKT JSON parse | 739.19 | — | — | 3461.78 (4.68x) | 1854.45 (2.51x) |
| Any ZeroUInt32Value WKT JSON stringify | 256.84 | — | — | 1060.65 (4.13x) | 846.44 (3.30x) |
| Any ZeroUInt32Value WKT JSON parse | 543.06 | — | — | 2648.60 (4.88x) | 1749.51 (3.22x) |
| Any MaxUInt32Value WKT JSON stringify | 181.31 | — | — | 1999.69 (11.03x) | 889.87 (4.91x) |
| Any MaxUInt32Value WKT JSON parse | 550.87 | — | — | 3385.10 (6.15x) | 1795.74 (3.26x) |
| Any BoolValue WKT JSON stringify | 182.90 | — | — | 1989.28 (10.88x) | 733.88 (4.01x) |
| Any BoolValue WKT JSON parse | 494.29 | — | — | 3285.07 (6.65x) | 1589.24 (3.22x) |
| Any FalseBoolValue WKT JSON stringify | 180.12 | — | — | 967.39 (5.37x) | 825.00 (4.58x) |
| Any FalseBoolValue WKT JSON parse | 677.40 | — | — | 2614.65 (3.86x) | 1727.07 (2.55x) |
| Any StringValue WKT JSON stringify | 296.85 | — | — | 1870.13 (6.30x) | 2141.50 (7.21x) |
| Any StringValue WKT JSON parse | 885.46 | — | — | 3075.38 (3.47x) | 1944.40 (2.20x) |
| Any StringValue Escape WKT JSON parse | 756.44 | — | — | 3365.06 (4.45x) | 1758.67 (2.32x) |
| Any StringValue Surrogate WKT JSON parse | 700.03 | — | — | 3382.85 (4.83x) | 1701.14 (2.43x) |
| Any EmptyStringValue WKT JSON stringify | 195.16 | — | — | 977.01 (5.01x) | 782.55 (4.01x) |
| Any EmptyStringValue WKT JSON parse | 521.08 | — | — | 2631.65 (5.05x) | 1507.66 (2.89x) |
| Any BytesValue WKT JSON stringify | 205.59 | — | — | 1929.60 (9.39x) | 1098.42 (5.34x) |
| Any BytesValue WKT JSON parse | 572.72 | — | — | 3263.66 (5.70x) | 2078.33 (3.63x) |
| Any BytesValue URL WKT JSON parse | 592.34 | — | — | 3405.11 (5.75x) | 1719.48 (2.90x) |
| Any BytesValue StandardBase64 WKT JSON parse | 577.48 | — | — | 3356.44 (5.81x) | 1729.26 (2.99x) |
| Any BytesValue Unpadded WKT JSON parse | 686.19 | — | — | 3389.26 (4.94x) | 1759.97 (2.56x) |
| Any EmptyBytesValue WKT JSON stringify | 268.05 | — | — | 927.54 (3.46x) | 717.34 (2.68x) |
| Any EmptyBytesValue WKT JSON parse | 861.71 | — | — | 2619.02 (3.04x) | 1682.21 (1.95x) |
| Nested Any WKT JSON stringify | 357.23 | — | — | 3097.55 (8.67x) | 1997.75 (5.59x) |
| Nested Any WKT JSON parse | 1118.82 | — | — | 5223.47 (4.67x) | 3822.43 (3.42x) |
| Duration JSON stringify | 57.68 | — | — | 1127.60 (19.55x) | 343.32 (5.95x) |
| Duration JSON parse | 19.08 | — | — | 1804.34 (94.57x) | 389.42 (20.41x) |
| Duration Escape JSON parse | 38.81 | — | — | 1842.03 (47.46x) | 631.05 (16.26x) |
| PlusDuration JSON parse | 18.82 | — | — | 1824.77 (96.96x) | 385.85 (20.50x) |
| ShortFractionDuration JSON parse | 17.25 | — | — | 1789.49 (103.74x) | 370.47 (21.48x) |
| MicroDuration JSON stringify | 59.42 | — | — | 1100.82 (18.53x) | 422.38 (7.11x) |
| MicroDuration JSON parse | 21.87 | — | — | 1816.28 (83.05x) | 548.56 (25.08x) |
| NanoDuration JSON stringify | 56.80 | — | — | 1112.52 (19.59x) | 379.52 (6.68x) |
| NanoDuration JSON parse | 26.09 | — | — | 1836.55 (70.39x) | 561.01 (21.50x) |
| NegativeDuration JSON stringify | 57.85 | — | — | 1167.73 (20.19x) | 536.40 (9.27x) |
| NegativeDuration JSON parse | 19.55 | — | — | 1860.86 (95.18x) | 661.91 (33.86x) |
| FractionalNegativeDuration JSON stringify | 58.02 | — | — | 1057.01 (18.22x) | 531.06 (9.15x) |
| FractionalNegativeDuration JSON parse | 19.32 | — | — | 1761.84 (91.19x) | 387.78 (20.07x) |
| MaxDuration JSON stringify | 49.30 | — | — | 929.21 (18.85x) | 655.05 (13.29x) |
| MaxDuration JSON parse | 34.41 | — | — | 1663.58 (48.35x) | 545.28 (15.85x) |
| MinDuration JSON stringify | 49.42 | — | — | 1010.85 (20.45x) | 411.60 (8.33x) |
| MinDuration JSON parse | 32.86 | — | — | 1817.14 (55.30x) | 536.44 (16.33x) |
| ZeroDuration JSON stringify | 44.53 | — | — | 877.74 (19.71x) | 354.39 (7.96x) |
| ZeroDuration JSON parse | 14.67 | — | — | 1622.76 (110.62x) | 284.57 (19.40x) |
| FieldMask JSON stringify | 137.22 | — | — | 929.83 (6.78x) | 868.60 (6.33x) |
| FieldMask JSON parse | 139.41 | — | — | 2121.80 (15.22x) | 1064.34 (7.63x) |
| FieldMask Escape JSON parse | 195.23 | — | — | 2095.17 (10.73x) | 1300.40 (6.66x) |
| EmptyFieldMask JSON stringify | 40.90 | — | — | 677.33 (16.56x) | 265.17 (6.48x) |
| EmptyFieldMask JSON parse | 4.79 | — | — | 1107.76 (231.27x) | 282.55 (58.99x) |
| Timestamp JSON stringify | 96.26 | — | — | 1340.73 (13.93x) | 489.46 (5.08x) |
| Timestamp JSON parse | 45.89 | — | — | 1836.77 (40.03x) | 639.15 (13.93x) |
| Timestamp Escape JSON parse | 90.79 | — | — | 1878.29 (20.69x) | 1481.45 (16.32x) |
| ShortFraction Timestamp JSON parse | 43.49 | — | — | 1827.97 (42.03x) | 861.31 (19.80x) |
| Micro Timestamp JSON stringify | 95.81 | — | — | 1366.38 (14.26x) | 942.65 (9.84x) |
| Micro Timestamp JSON parse | 49.35 | — | — | 1855.86 (37.61x) | 1025.61 (20.78x) |
| Nano Timestamp JSON stringify | 93.86 | — | — | 1556.41 (16.58x) | 986.65 (10.51x) |
| Nano Timestamp JSON parse | 50.22 | — | — | 1862.38 (37.08x) | 585.46 (11.66x) |
| Offset Timestamp JSON parse | 51.41 | — | — | 1870.87 (36.39x) | 1341.12 (26.09x) |
| PreEpoch Timestamp JSON stringify | 66.46 | — | — | 1113.84 (16.76x) | 606.35 (9.12x) |
| PreEpoch Timestamp JSON parse | 43.21 | — | — | 1828.01 (42.31x) | 683.42 (15.82x) |
| Max Timestamp JSON stringify | 78.67 | — | — | 1410.22 (17.93x) | 753.40 (9.58x) |
| Max Timestamp JSON parse | 51.81 | — | — | 1880.62 (36.30x) | 967.37 (18.67x) |
| Min Timestamp JSON stringify | 80.32 | — | — | 1186.05 (14.77x) | 776.04 (9.66x) |
| Min Timestamp JSON parse | 41.00 | — | — | 1800.58 (43.92x) | 1279.94 (31.22x) |
| Empty JSON stringify | 20.82 | — | — | 513.80 (24.68x) | 153.05 (7.35x) |
| Empty JSON parse | 67.17 | — | — | 736.58 (10.97x) | 554.41 (8.25x) |
| Struct JSON stringify | 196.90 | — | — | 7140.76 (36.27x) | 7918.39 (40.22x) |
| Struct JSON parse | 1316.55 | — | — | 13256.10 (10.07x) | 6457.82 (4.91x) |
| Struct Escape JSON parse | 1193.15 | — | — | 13420.30 (11.25x) | 6519.76 (5.46x) |
| Struct NumberExponent JSON parse | 850.20 | — | — | 13286.80 (15.63x) | 6775.50 (7.97x) |
| Struct Surrogate JSON parse | 371.82 | — | — | 5794.83 (15.59x) | 1686.41 (4.54x) |
| Struct KeySurrogate JSON parse | 369.59 | — | — | 7906.58 (21.39x) | 1510.89 (4.09x) |
| EmptyStruct JSON stringify | 40.42 | — | — | 1093.20 (27.05x) | 420.41 (10.40x) |
| EmptyStruct JSON parse | 87.58 | — | — | 3413.61 (38.98x) | 564.60 (6.45x) |
| Value JSON stringify | 201.45 | — | — | 7886.88 (39.15x) | 4198.78 (20.84x) |
| Value JSON parse | 884.88 | — | — | 14727.10 (16.64x) | 7055.42 (7.97x) |
| Value Escape JSON parse | 921.89 | — | — | 15117.30 (16.40x) | 6376.54 (6.92x) |
| Value NumberExponent JSON parse | 882.96 | — | — | 14714.10 (16.66x) | 5935.49 (6.72x) |
| Value Surrogate JSON parse | 547.52 | — | — | 8099.89 (14.79x) | 2091.83 (3.82x) |
| Value KeySurrogate JSON parse | 545.60 | — | — | 7996.12 (14.66x) | 2146.36 (3.93x) |
| NullValue JSON stringify | 53.76 | — | — | 1516.65 (28.21x) | 220.65 (4.10x) |
| NullValue JSON parse | 84.06 | — | — | 2950.20 (35.10x) | 385.77 (4.59x) |
| StringScalarValue JSON stringify | 71.24 | — | — | 1630.23 (22.88x) | 268.17 (3.76x) |
| StringScalarValue JSON parse | 142.66 | — | — | 2435.80 (17.07x) | 433.22 (3.04x) |
| StringScalarValue Escape JSON parse | 181.20 | — | — | 2459.36 (13.57x) | 465.69 (2.57x) |
| StringScalarValue Surrogate JSON parse | 195.41 | — | — | 2620.44 (13.41x) | 659.97 (3.38x) |
| EmptyStringScalarValue JSON stringify | 46.51 | — | — | 1384.00 (29.76x) | 294.35 (6.33x) |
| EmptyStringScalarValue JSON parse | 91.11 | — | — | 2420.00 (26.56x) | 346.09 (3.80x) |
| NumberValue JSON stringify | 127.33 | — | — | 1921.09 (15.09x) | 327.61 (2.57x) |
| NumberValue JSON parse | 145.06 | — | — | 2529.56 (17.44x) | 412.74 (2.85x) |
| NumberValue Exponent JSON parse | 145.30 | — | — | 2502.96 (17.23x) | 494.31 (3.40x) |
| NegativeNumberValue JSON stringify | 140.03 | — | — | 1959.18 (13.99x) | 312.56 (2.23x) |
| NegativeNumberValue JSON parse | 162.44 | — | — | 2529.22 (15.57x) | 518.99 (3.19x) |
| ZeroNumberValue JSON stringify | 74.01 | — | — | 1871.08 (25.28x) | 359.69 (4.86x) |
| ZeroNumberValue JSON parse | 130.86 | — | — | 2500.10 (19.11x) | 428.73 (3.28x) |
| BoolScalarValue JSON stringify | 40.25 | — | — | 1451.83 (36.07x) | 251.87 (6.26x) |
| BoolScalarValue JSON parse | 70.82 | — | — | 2382.94 (33.65x) | 490.53 (6.93x) |
| FalseBoolScalarValue JSON stringify | 40.32 | — | — | 1659.76 (41.16x) | 208.34 (5.17x) |
| FalseBoolScalarValue JSON parse | 70.75 | — | — | 2348.86 (33.20x) | 321.44 (4.54x) |
| ListKindValue JSON stringify | 138.00 | — | — | 7465.61 (54.10x) | 2845.81 (20.62x) |
| ListKindValue JSON parse | 672.69 | — | — | 12637.40 (18.79x) | 5727.30 (8.51x) |
| ListKindValue Escape JSON parse | 696.34 | — | — | 12628.00 (18.13x) | 5291.54 (7.60x) |
| ListKindValue Surrogate JSON parse | 323.13 | — | — | 5914.77 (18.30x) | 1658.54 (5.13x) |
| EmptyStructKindValue JSON stringify | 42.38 | — | — | 2289.16 (54.02x) | 568.70 (13.42x) |
| EmptyStructKindValue JSON parse | 110.27 | — | — | 4545.08 (41.22x) | 757.73 (6.87x) |
| EmptyListKindValue JSON stringify | 41.09 | — | — | 2298.29 (55.93x) | 367.27 (8.94x) |
| EmptyListKindValue JSON parse | 148.26 | — | — | 4874.80 (32.88x) | 651.73 (4.40x) |
| ListValue JSON stringify | 273.70 | — | — | 5599.85 (20.46x) | 2812.02 (10.27x) |
| ListValue JSON parse | 1025.62 | — | — | 10062.40 (9.81x) | 5093.37 (4.97x) |
| ListValue Escape JSON parse | 919.71 | — | — | 10227.40 (11.12x) | 4963.29 (5.40x) |
| ListValue Surrogate JSON parse | 339.27 | — | — | 3743.86 (11.04x) | 1039.36 (3.06x) |
| EmptyListValue JSON stringify | 40.14 | — | — | 702.59 (17.50x) | 199.30 (4.97x) |
| EmptyListValue JSON parse | 154.74 | — | — | 2569.78 (16.61x) | 299.62 (1.94x) |
| DoubleValue JSON stringify | 122.40 | — | — | 871.72 (7.12x) | 203.57 (1.66x) |
| DoubleValue JSON parse | 136.65 | — | — | 1451.44 (10.62x) | 323.12 (2.36x) |
| DoubleValue String JSON parse | 112.18 | — | — | 1429.85 (12.75x) | 504.74 (4.50x) |
| DoubleValue Exponent JSON parse | 113.67 | — | — | 1442.98 (12.69x) | 364.44 (3.21x) |
| NegativeDoubleValue JSON stringify | 69.34 | — | — | 958.84 (13.83x) | 230.76 (3.33x) |
| NegativeDoubleValue JSON parse | 112.24 | — | — | 1620.56 (14.44x) | 280.26 (2.50x) |
| ZeroDoubleValue JSON stringify | 47.23 | — | — | 794.62 (16.82x) | 153.09 (3.24x) |
| ZeroDoubleValue JSON parse | 110.03 | — | — | 1400.00 (12.72x) | 312.15 (2.84x) |
| DoubleValue NaN JSON stringify | 46.55 | — | — | 659.44 (14.17x) | 126.36 (2.71x) |
| DoubleValue NaN JSON parse | 105.37 | — | — | 1166.31 (11.07x) | 379.28 (3.60x) |
| DoubleValue Infinity JSON stringify | 48.16 | — | — | 658.43 (13.67x) | 213.50 (4.43x) |
| DoubleValue Infinity JSON parse | 105.60 | — | — | 1251.31 (11.85x) | 266.46 (2.52x) |
| DoubleValue NegativeInfinity JSON stringify | 48.04 | — | — | 707.50 (14.73x) | 216.58 (4.51x) |
| DoubleValue NegativeInfinity JSON parse | 108.56 | — | — | 1392.29 (12.83x) | 260.52 (2.40x) |
| FloatValue JSON stringify | 70.74 | — | — | 886.06 (12.53x) | 190.61 (2.69x) |
| FloatValue JSON parse | 112.43 | — | — | 1399.75 (12.45x) | 268.98 (2.39x) |
| FloatValue String JSON parse | 110.48 | — | — | 1343.31 (12.16x) | 377.09 (3.41x) |
| FloatValue Exponent JSON parse | 114.41 | — | — | 1492.97 (13.05x) | 269.86 (2.36x) |
| NegativeFloatValue JSON stringify | 70.71 | — | — | 888.03 (12.56x) | 235.37 (3.33x) |
| NegativeFloatValue JSON parse | 112.68 | — | — | 1470.77 (13.05x) | 297.37 (2.64x) |
| ZeroFloatValue JSON stringify | 47.55 | — | — | 761.58 (16.02x) | 133.66 (2.81x) |
| ZeroFloatValue JSON parse | 108.68 | — | — | 1220.11 (11.23x) | 256.78 (2.36x) |
| FloatValue NaN JSON stringify | 46.17 | — | — | 654.19 (14.17x) | 221.33 (4.79x) |
| FloatValue NaN JSON parse | 105.30 | — | — | 1242.09 (11.80x) | 392.37 (3.73x) |
| FloatValue Infinity JSON stringify | 49.29 | — | — | 651.00 (13.21x) | 133.48 (2.71x) |
| FloatValue Infinity JSON parse | 133.66 | — | — | 1279.79 (9.57x) | 400.90 (3.00x) |
| FloatValue NegativeInfinity JSON stringify | 78.52 | — | — | 717.52 (9.14x) | 161.20 (2.05x) |
| FloatValue NegativeInfinity JSON parse | 137.71 | — | — | 1238.23 (8.99x) | 391.11 (2.84x) |
| Int64Value JSON stringify | 66.93 | — | — | 691.45 (10.33x) | 376.36 (5.62x) |
| Int64Value JSON parse | 177.17 | — | — | 1578.36 (8.91x) | 463.66 (2.62x) |
| Int64Value Number JSON parse | 192.88 | — | — | 1470.75 (7.63x) | 453.42 (2.35x) |
| Int64Value Exponent JSON parse | 154.61 | — | — | 1520.47 (9.83x) | 442.83 (2.86x) |
| ZeroInt64Value JSON stringify | 55.70 | — | — | 629.23 (11.30x) | 195.71 (3.51x) |
| ZeroInt64Value JSON parse | 128.71 | — | — | 1211.54 (9.41x) | 416.06 (3.23x) |
| NegativeInt64Value JSON stringify | 66.87 | — | — | 690.94 (10.33x) | 282.69 (4.23x) |
| NegativeInt64Value JSON parse | 178.98 | — | — | 1400.37 (7.82x) | 631.38 (3.53x) |
| MinInt64Value JSON stringify | 69.47 | — | — | 699.79 (10.07x) | 269.06 (3.87x) |
| MinInt64Value JSON parse | 190.09 | — | — | 1370.77 (7.21x) | 616.10 (3.24x) |
| MaxInt64Value JSON stringify | 49.33 | — | — | 692.66 (14.04x) | 330.86 (6.71x) |
| MaxInt64Value JSON parse | 136.00 | — | — | 1429.65 (10.51x) | 552.27 (4.06x) |
| UInt64Value JSON stringify | 69.68 | — | — | 822.42 (11.80x) | 309.20 (4.44x) |
| UInt64Value JSON parse | 179.97 | — | — | 1478.58 (8.22x) | 572.89 (3.18x) |
| UInt64Value Number JSON parse | 129.00 | — | — | 1557.93 (12.08x) | 336.11 (2.61x) |
| UInt64Value Exponent JSON parse | 147.99 | — | — | 1621.88 (10.96x) | 376.54 (2.54x) |
| ZeroUInt64Value JSON stringify | 47.33 | — | — | 718.22 (15.17x) | 203.49 (4.30x) |
| ZeroUInt64Value JSON parse | 105.47 | — | — | 1328.59 (12.60x) | 363.55 (3.45x) |
| MaxUInt64Value JSON stringify | 68.12 | — | — | 679.34 (9.97x) | 274.02 (4.02x) |
| MaxUInt64Value JSON parse | 192.57 | — | — | 1561.07 (8.11x) | 455.79 (2.37x) |
| Int32Value JSON stringify | 61.14 | — | — | 719.20 (11.76x) | 132.55 (2.17x) |
| Int32Value JSON parse | 134.45 | — | — | 1556.90 (11.58x) | 319.49 (2.38x) |
| Int32Value String JSON parse | 137.61 | — | — | 1359.15 (9.88x) | 372.27 (2.71x) |
| Int32Value Exponent JSON parse | 136.91 | — | — | 1525.82 (11.14x) | 394.31 (2.88x) |
| ZeroInt32Value JSON stringify | 46.01 | — | — | 679.74 (14.77x) | 136.01 (2.96x) |
| ZeroInt32Value JSON parse | 129.21 | — | — | 1495.92 (11.58x) | 247.74 (1.92x) |
| NegativeInt32Value JSON stringify | 45.93 | — | — | 709.36 (15.44x) | 151.41 (3.30x) |
| NegativeInt32Value JSON parse | 132.41 | — | — | 1490.44 (11.26x) | 308.42 (2.33x) |
| MinInt32Value JSON stringify | 46.83 | — | — | 651.44 (13.91x) | 129.63 (2.77x) |
| MinInt32Value JSON parse | 137.48 | — | — | 1534.17 (11.16x) | 320.57 (2.33x) |
| MaxInt32Value JSON stringify | 47.00 | — | — | 769.87 (16.38x) | 221.43 (4.71x) |
| MaxInt32Value JSON parse | 137.74 | — | — | 1541.61 (11.19x) | 386.63 (2.81x) |
| UInt32Value JSON stringify | 45.94 | — | — | 703.97 (15.32x) | 152.96 (3.33x) |
| UInt32Value JSON parse | 132.61 | — | — | 1435.83 (10.83x) | 305.31 (2.30x) |
| UInt32Value String JSON parse | 138.07 | — | — | 1379.79 (9.99x) | 383.83 (2.78x) |
| UInt32Value Exponent JSON parse | 136.46 | — | — | 1501.60 (11.00x) | 378.50 (2.77x) |
| ZeroUInt32Value JSON stringify | 45.96 | — | — | 666.51 (14.50x) | 145.18 (3.16x) |
| ZeroUInt32Value JSON parse | 129.34 | — | — | 1503.93 (11.63x) | 241.72 (1.87x) |
| MaxUInt32Value JSON stringify | 46.43 | — | — | 787.90 (16.97x) | 137.70 (2.97x) |
| MaxUInt32Value JSON parse | 137.57 | — | — | 1489.76 (10.83x) | 314.13 (2.28x) |
| BoolValue JSON stringify | 44.21 | — | — | 616.79 (13.95x) | 137.45 (3.11x) |
| BoolValue JSON parse | 59.65 | — | — | 1267.89 (21.26x) | 206.14 (3.46x) |
| FalseBoolValue JSON stringify | 59.15 | — | — | 685.24 (11.58x) | 125.73 (2.13x) |
| FalseBoolValue JSON parse | 75.44 | — | — | 1295.37 (17.17x) | 213.56 (2.83x) |
| StringValue JSON stringify | 74.81 | — | — | 698.99 (9.34x) | 180.70 (2.42x) |
| StringValue JSON parse | 154.93 | — | — | 1445.83 (9.33x) | 291.28 (1.88x) |
| StringValue Escape JSON parse | 168.09 | — | — | 1570.86 (9.35x) | 336.40 (2.00x) |
| StringValue Surrogate JSON parse | 176.39 | — | — | 1509.69 (8.56x) | 333.72 (1.89x) |
| EmptyStringValue JSON stringify | 66.80 | — | — | 717.38 (10.74x) | 185.40 (2.78x) |
| EmptyStringValue JSON parse | 85.43 | — | — | 1309.29 (15.33x) | 224.59 (2.63x) |
| BytesValue JSON stringify | 66.25 | — | — | 702.66 (10.61x) | 204.82 (3.09x) |
| BytesValue JSON parse | 158.64 | — | — | 1479.18 (9.32x) | 407.85 (2.57x) |
| BytesValue URL JSON parse | 180.98 | — | — | 1559.46 (8.62x) | 349.72 (1.93x) |
| BytesValue StandardBase64 JSON parse | 157.08 | — | — | 1299.72 (8.27x) | 385.60 (2.45x) |
| BytesValue Unpadded JSON parse | 155.64 | — | — | 1460.88 (9.39x) | 404.28 (2.60x) |
| EmptyBytesValue JSON stringify | 56.30 | — | — | 683.49 (12.14x) | 189.11 (3.36x) |
| EmptyBytesValue JSON parse | 84.31 | — | — | 1268.70 (15.05x) | 258.56 (3.07x) |
| TextFormat format | 194.94 | — | — | 3238.36 (16.61x) | 2928.16 (15.02x) |
| TextFormat parse | 899.82 | — | — | 5999.21 (6.67x) | 8006.94 (8.90x) |
| packed fixed32 encode | 2.01 | 698.70 (347.61x) | 564.51 (280.85x) | 43.71 (21.75x) | 392.50 (195.27x) |
| packed fixed32 decode | 4.56 | 1244.11 (272.83x) | 2387.40 (523.55x) | 49.41 (10.84x) | 2374.18 (520.65x) |
| packed fixed64 encode | 2.88 | 614.07 (213.22x) | 564.08 (195.86x) | 92.17 (32.00x) | 386.39 (134.16x) |
| packed fixed64 decode | 4.53 | 1214.31 (268.06x) | 8582.71 (1894.64x) | 78.50 (17.33x) | 3123.01 (689.41x) |
| packed sfixed32 encode | 2.83 | 621.58 (219.64x) | 542.88 (191.83x) | 43.39 (15.33x) | 438.02 (154.78x) |
| packed sfixed32 decode | 6.64 | 1244.64 (187.45x) | 2247.86 (338.53x) | 65.87 (9.92x) | 2321.21 (349.58x) |
| packed sfixed64 encode | 2.91 | 650.29 (223.47x) | 589.06 (202.43x) | 70.22 (24.13x) | 809.35 (278.13x) |
| packed sfixed64 decode | 4.52 | 1176.34 (260.25x) | 8538.03 (1888.94x) | 79.47 (17.58x) | 3031.61 (670.71x) |
| packed float encode | 2.01 | 896.68 (446.11x) | 564.98 (281.08x) | 47.31 (23.54x) | 364.69 (181.44x) |
| packed float decode | 4.54 | 1234.96 (272.02x) | 2490.70 (548.61x) | 42.81 (9.43x) | 2554.13 (562.58x) |
| packed double encode | 2.01 | 897.14 (446.34x) | 561.80 (279.50x) | 75.94 (37.78x) | 356.97 (177.60x) |
| packed double decode | 4.53 | 1170.14 (258.31x) | 2393.41 (528.35x) | 90.86 (20.06x) | 3267.34 (721.27x) |
| packed uint64 encode | 1368.60 | 5712.60 (4.17x) | 5122.92 (3.74x) | 2647.75 (1.93x) | 4634.88 (3.39x) |
| packed uint64 decode | 1809.39 | 3457.72 (1.91x) | 9842.70 (5.44x) | 3587.76 (1.98x) | 8699.03 (4.81x) |
| packed uint32 encode | 1450.99 | 4395.52 (3.03x) | 3869.23 (2.67x) | 2204.61 (1.52x) | 3723.33 (2.57x) |
| packed uint32 decode | 1317.27 | 2988.84 (2.27x) | 3779.45 (2.87x) | 2633.75 (2.00x) | 6177.58 (4.69x) |
| packed int64 encode | 1396.17 | 12836.82 (9.19x) | 7263.66 (5.20x) | 3888.31 (2.78x) | 5465.64 (3.91x) |
| packed int64 decode | 2760.19 | 4206.28 (1.52x) | 11496.41 (4.17x) | 5641.70 (2.04x) | 11873.17 (4.30x) |
| packed sint32 encode | 1082.28 | 3878.32 (3.58x) | 3305.26 (3.05x) | 1982.82 (1.83x) | 4303.30 (3.98x) |
| packed sint32 decode | 955.38 | 3196.16 (3.35x) | 3845.79 (4.03x) | 1438.03 (1.51x) | 4487.51 (4.70x) |
| packed sint64 encode | 1762.76 | 6163.69 (3.50x) | 5355.32 (3.04x) | 3055.35 (1.73x) | 5370.07 (3.05x) |
| packed sint64 decode | 2043.84 | 3929.56 (1.92x) | 10665.45 (5.22x) | 3727.72 (1.82x) | 9847.27 (4.82x) |
| packed bool encode | 2.43 | 1545.80 (636.13x) | 529.23 (217.79x) | 23.67 (9.74x) | 3284.05 (1351.46x) |
| packed bool decode | 262.73 | 1929.21 (7.34x) | 3001.16 (11.42x) | 929.93 (3.54x) | 2258.03 (8.59x) |
| packed enum encode | 424.10 | 3367.62 (7.94x) | 2003.93 (4.73x) | 1240.79 (2.93x) | 3491.71 (8.23x) |
| packed enum decode | 155.80 | 1927.13 (12.37x) | 3274.65 (21.02x) | 700.37 (4.50x) | 3143.78 (20.18x) |
| large map encode | 4337.66 | 16541.87 (3.81x) | 9682.66 (2.23x) | 24288.70 (5.60x) | 239990.35 (55.33x) |
| shuffled large map deterministic binary encode | 36138.24 | — | — | 99079.80 (2.74x) | 434879.56 (12.03x) |
| large map decode | 29173.77 | 110244.87 (3.78x) | 107687.59 (3.69x) | 111201.00 (3.81x) | 339616.64 (11.64x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON (including generated `map<string, int32>` surrogate-pair key parse, null-field parse, ignore-unknown parse, enum-name parse, always-print default-value stringify, enum-number stringify, proto-name stringify, proto-name parse, open-enum numeric parse, and integer numeric-exponent parse), Any/WKT JSON (including embedded zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound `Duration`, non-empty/escaped-input parse/number-exponent parse/surrogate-pair value parse/surrogate-pair key parse and empty `Struct`, object/escaped-object parse/object-number-exponent/object-surrogate-pair value parse/object-surrogate-pair key parse/list/escaped-list/surrogate-list/string-scalar/escaped-string-scalar/surrogate-string-scalar/number-exponent/negative-number `Value` (including default-like scalar and empty object/list kinds),
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
