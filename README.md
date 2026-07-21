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
with `PBZ_COMPARE_CPUSET`. The compare script also derives `GOMAXPROCS` from
the CPU set when the variable is not already set, keeping Go baseline
parallelism aligned with the pinned run. For example:

```sh
PBZ_COMPARE_CPUSET=3 bench/run_compare.sh 2>&1 | tee /tmp/pbz-compare.log
```

Latest accepted comparison (`/tmp/pbz-compare-current-cpu3.log`,
summarized in `/tmp/pbz-summary-current-cpu3.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Pivoted rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 21.59 | 100.58 (4.66x) | 50.00 (2.32x) | 104.39 (4.83x) | 806.55 (37.36x) |
| binary decode | 86.82 | 248.32 (2.86x) | 235.64 (2.71x) | 222.39 (2.56x) | 906.95 (10.45x) |
| unknown fields count by number | 3.58 | — | — | 161.46 (45.10x) | — |
| deterministic binary encode | 50.51 | — | — | 126.60 (2.51x) | 1172.13 (23.21x) |
| scalarmix encode | 18.79 | 99.39 (5.29x) | 48.31 (2.57x) | 29.81 (1.59x) | 209.17 (11.13x) |
| scalarmix decode | 43.05 | 132.47 (3.08x) | 181.02 (4.20x) | 83.28 (1.93x) | 328.78 (7.64x) |
| ScalarMix JSON stringify | 310.88 | — | — | 4781.90 (15.38x) | 3708.99 (11.93x) |
| ScalarMix JSON parse | 2687.26 | — | — | 11926.00 (4.44x) | 8293.56 (3.09x) |
| textbytes encode | 9.52 | 78.81 (8.28x) | 34.09 (3.58x) | 120.64 (12.67x) | 145.26 (15.26x) |
| textbytes decode | 38.23 | 384.47 (10.06x) | 235.94 (6.17x) | 163.70 (4.28x) | 668.21 (17.48x) |
| TextBytes JSON stringify | 342.59 | — | — | 2237.88 (6.53x) | 2241.38 (6.54x) |
| TextBytes JSON parse | 1339.60 | — | — | 5602.82 (4.18x) | 4007.26 (2.99x) |
| largebytes encode | 25.81 | 2707.83 (104.91x) | 2684.49 (104.01x) | 2734.96 (105.97x) | 2811.43 (108.93x) |
| largebytes decode | 88.21 | 5554.56 (62.97x) | 3036.10 (34.42x) | 2733.12 (30.98x) | 21370.39 (242.27x) |
| presencemix encode | 17.31 | 56.08 (3.24x) | 27.24 (1.57x) | 57.18 (3.30x) | 228.75 (13.21x) |
| presencemix decode | 58.72 | 132.41 (2.25x) | 108.56 (1.85x) | 159.83 (2.72x) | 491.33 (8.37x) |
| PresenceMix JSON stringify | 142.80 | — | — | 3043.64 (21.31x) | 2373.65 (16.62x) |
| PresenceMix JSON parse | 1187.00 | — | — | 6135.44 (5.17x) | 3143.73 (2.65x) |
| complex encode | 54.77 | 135.37 (2.47x) | 95.47 (1.74x) | 163.80 (2.99x) | 954.87 (17.43x) |
| complex decode | 165.89 | 392.80 (2.37x) | 342.84 (2.07x) | 396.66 (2.39x) | 1368.18 (8.25x) |
| complex deterministic binary encode | 93.43 | — | — | 171.08 (1.83x) | 1155.20 (12.36x) |
| complex JSON stringify | 296.01 | — | — | 4875.61 (16.47x) | 6169.03 (20.84x) |
| complex JSON parse | 2438.48 | — | — | 12032.00 (4.93x) | 7617.98 (3.12x) |
| Complex ProtoName JSON stringify | 284.70 | — | — | 5163.90 (18.14x) | 6256.91 (21.98x) |
| Complex ProtoName JSON parse | 2426.22 | — | — | 12312.30 (5.07x) | 7604.79 (3.13x) |
| complex TextFormat format | 279.05 | — | — | 3772.96 (13.52x) | 5407.72 (19.38x) |
| complex TextFormat parse | 1809.23 | — | — | 6920.10 (3.82x) | 8401.70 (4.64x) |
| packed int32 encode | 650.14 | 3161.30 (4.86x) | 2527.57 (3.89x) | 1233.68 (1.90x) | 2834.21 (4.36x) |
| packed int32 decode | 687.69 | 1907.16 (2.77x) | 3229.36 (4.70x) | 934.18 (1.36x) | 2584.50 (3.76x) |
| JSON stringify | 162.83 | — | — | 3031.84 (18.62x) | 2330.45 (14.31x) |
| AlwaysPrint JSON stringify | 60.72 | — | — | 2614.72 (43.06x) | 1360.43 (22.40x) |
| ProtoName JSON stringify | 311.29 | — | — | 4752.98 (15.27x) | 3748.11 (12.04x) |
| EnumNumber JSON stringify | 288.48 | — | — | 4720.88 (16.36x) | 3692.04 (12.80x) |
| JSON parse | 1468.72 | — | — | 7440.52 (5.07x) | 4659.32 (3.17x) |
| MapKeySurrogate JSON parse | 414.01 | — | — | 3510.24 (8.48x) | 1079.33 (2.61x) |
| NullFields JSON parse | 505.02 | — | — | 2073.98 (4.11x) | 841.85 (1.67x) |
| IgnoreUnknown JSON parse | 1182.68 | — | — | 5402.95 (4.57x) | 2638.16 (2.23x) |
| OpenEnum JSON parse | 296.34 | — | — | 3781.64 (12.76x) | 515.95 (1.74x) |
| EnumName JSON parse | 295.39 | — | — | 3839.22 (13.00x) | 500.79 (1.70x) |
| ProtoName JSON parse | 534.63 | — | — | 4044.61 (7.57x) | 1253.95 (2.35x) |
| IntExponent JSON parse | 1656.92 | — | — | 7251.84 (4.38x) | 4210.03 (2.54x) |
| StringNumber JSON parse | 1649.70 | — | — | 7059.21 (4.28x) | 4615.67 (2.80x) |
| Any WKT JSON stringify | 134.23 | — | — | 1884.26 (14.04x) | 975.67 (7.27x) |
| Any WKT JSON parse | 526.80 | — | — | 3011.19 (5.72x) | 1561.19 (2.96x) |
| Any Duration Escape WKT JSON parse | 544.28 | — | — | 3043.99 (5.59x) | 1662.19 (3.05x) |
| Any PlusDuration WKT JSON parse | 525.86 | — | — | 3015.54 (5.73x) | 1589.17 (3.02x) |
| Any ShortFractionDuration WKT JSON parse | 524.25 | — | — | 2963.31 (5.65x) | 1527.88 (2.91x) |
| Any MicroDuration WKT JSON stringify | 140.56 | — | — | 1887.50 (13.43x) | 979.87 (6.97x) |
| Any MicroDuration WKT JSON parse | 528.83 | — | — | 3016.30 (5.70x) | 1542.90 (2.92x) |
| Any NanoDuration WKT JSON stringify | 132.29 | — | — | 1912.90 (14.46x) | 980.85 (7.41x) |
| Any NanoDuration WKT JSON parse | 531.45 | — | — | 3025.45 (5.69x) | 1566.89 (2.95x) |
| Any NegativeDuration WKT JSON stringify | 137.40 | — | — | 1944.74 (14.15x) | 1007.58 (7.33x) |
| Any NegativeDuration WKT JSON parse | 530.37 | — | — | 3114.51 (5.87x) | 1583.81 (2.99x) |
| Any FractionalNegativeDuration WKT JSON stringify | 129.78 | — | — | 1890.16 (14.56x) | 990.80 (7.63x) |
| Any FractionalNegativeDuration WKT JSON parse | 522.93 | — | — | 3078.71 (5.89x) | 1531.44 (2.93x) |
| Any MaxDuration WKT JSON stringify | 122.73 | — | — | 1743.61 (14.21x) | 979.18 (7.98x) |
| Any MaxDuration WKT JSON parse | 535.13 | — | — | 2982.90 (5.57x) | 1558.78 (2.91x) |
| Any MinDuration WKT JSON stringify | 123.08 | — | — | 1757.24 (14.28x) | 998.60 (8.11x) |
| Any MinDuration WKT JSON parse | 536.32 | — | — | 3047.23 (5.68x) | 1551.30 (2.89x) |
| Any ZeroDuration WKT JSON stringify | 112.33 | — | — | 911.69 (8.12x) | 961.96 (8.56x) |
| Any ZeroDuration WKT JSON parse | 475.57 | — | — | 2263.11 (4.76x) | 1464.86 (3.08x) |
| Any FieldMask WKT JSON stringify | 230.39 | — | — | 1748.07 (7.59x) | 1422.16 (6.17x) |
| Any FieldMask WKT JSON parse | 717.19 | — | — | 3163.34 (4.41x) | 2082.62 (2.90x) |
| Any FieldMask Escape WKT JSON parse | 735.85 | — | — | 3250.59 (4.42x) | 2269.28 (3.08x) |
| Any EmptyFieldMask WKT JSON stringify | 118.21 | — | — | 912.38 (7.72x) | 778.84 (6.59x) |
| Any EmptyFieldMask WKT JSON parse | 448.48 | — | — | 2173.64 (4.85x) | 1329.36 (2.96x) |
| Any Timestamp WKT JSON stringify | 182.89 | — | — | 2038.77 (11.15x) | 1004.63 (5.49x) |
| Any Timestamp WKT JSON parse | 574.91 | — | — | 3050.15 (5.31x) | 1627.94 (2.83x) |
| Any Timestamp Escape WKT JSON parse | 591.74 | — | — | 3789.45 (6.40x) | 1783.93 (3.01x) |
| Any ShortFraction Timestamp WKT JSON parse | 573.16 | — | — | 3146.15 (5.49x) | 1662.25 (2.90x) |
| Any Micro Timestamp WKT JSON stringify | 183.20 | — | — | 2037.20 (11.12x) | 1006.45 (5.49x) |
| Any Micro Timestamp WKT JSON parse | 581.84 | — | — | 3056.21 (5.25x) | 1652.03 (2.84x) |
| Any Nano Timestamp WKT JSON stringify | 179.34 | — | — | 2030.43 (11.32x) | 1009.19 (5.63x) |
| Any Nano Timestamp WKT JSON parse | 587.56 | — | — | 3065.84 (5.22x) | 1627.43 (2.77x) |
| Any Offset Timestamp WKT JSON parse | 595.76 | — | — | 3066.08 (5.15x) | 1661.48 (2.79x) |
| Any PreEpoch Timestamp WKT JSON stringify | 145.77 | — | — | 1947.22 (13.36x) | 967.64 (6.64x) |
| Any PreEpoch Timestamp WKT JSON parse | 566.81 | — | — | 3058.83 (5.40x) | 1596.26 (2.82x) |
| Any Max Timestamp WKT JSON stringify | 166.08 | — | — | 2048.10 (12.33x) | 1003.48 (6.04x) |
| Any Max Timestamp WKT JSON parse | 589.81 | — | — | 3110.95 (5.27x) | 1638.68 (2.78x) |
| Any Min Timestamp WKT JSON stringify | 161.95 | — | — | 1935.67 (11.95x) | 982.86 (6.07x) |
| Any Min Timestamp WKT JSON parse | 563.02 | — | — | 3040.16 (5.40x) | 1610.43 (2.86x) |
| Any Empty WKT JSON stringify | 95.99 | — | — | 907.56 (9.45x) | 628.12 (6.54x) |
| Any Empty WKT JSON parse | 338.02 | — | — | 2137.07 (6.32x) | 1340.90 (3.97x) |
| Any Struct WKT JSON stringify | 635.30 | — | — | 5837.51 (9.19x) | 6093.82 (9.59x) |
| Any Struct WKT JSON parse | 1750.12 | — | — | 11075.60 (6.33x) | 8717.74 (4.98x) |
| Any Struct Escape WKT JSON parse | 1774.47 | — | — | 11162.40 (6.29x) | 8947.51 (5.04x) |
| Any Struct NumberExponent WKT JSON parse | 1757.12 | — | — | 11093.20 (6.31x) | 8741.87 (4.98x) |
| Any Struct Surrogate WKT JSON parse | 763.45 | — | — | 6312.75 (8.27x) | 3057.48 (4.00x) |
| Any Struct KeySurrogate WKT JSON parse | 756.85 | — | — | 6228.88 (8.23x) | 3052.54 (4.03x) |
| Any EmptyStruct WKT JSON stringify | 120.97 | — | — | 910.11 (7.52x) | 947.05 (7.83x) |
| Any EmptyStruct WKT JSON parse | 441.47 | — | — | 2226.71 (5.04x) | 1574.29 (3.57x) |
| Any Value WKT JSON stringify | 657.68 | — | — | 5907.77 (8.98x) | 6417.31 (9.76x) |
| Any Value WKT JSON parse | 1798.10 | — | — | 11279.70 (6.27x) | 9091.07 (5.06x) |
| Any Value Escape WKT JSON parse | 1822.81 | — | — | 11371.10 (6.24x) | 9272.91 (5.09x) |
| Any Value NumberExponent WKT JSON parse | 1796.72 | — | — | 11316.20 (6.30x) | 9098.28 (5.06x) |
| Any Value Surrogate WKT JSON parse | 815.44 | — | — | 6499.71 (7.97x) | 3460.32 (4.24x) |
| Any Value KeySurrogate WKT JSON parse | 813.32 | — | — | 6476.91 (7.96x) | 3457.18 (4.25x) |
| Any NullValue WKT JSON stringify | 133.28 | — | — | 2250.52 (16.89x) | 919.77 (6.90x) |
| Any NullValue WKT JSON parse | 463.86 | — | — | 4055.38 (8.74x) | 1583.26 (3.41x) |
| Any StringScalarValue WKT JSON stringify | 160.75 | — | — | 2267.29 (14.10x) | 998.31 (6.21x) |
| Any StringScalarValue WKT JSON parse | 520.45 | — | — | 3635.63 (6.99x) | 1691.90 (3.25x) |
| Any StringScalarValue Escape WKT JSON parse | 528.90 | — | — | 3678.47 (6.95x) | 1747.75 (3.30x) |
| Any StringScalarValue Surrogate WKT JSON parse | 536.99 | — | — | 3666.74 (6.83x) | 1751.22 (3.26x) |
| Any EmptyStringScalarValue WKT JSON stringify | 147.08 | — | — | 2277.60 (15.49x) | 925.38 (6.29x) |
| Any EmptyStringScalarValue WKT JSON parse | 486.69 | — | — | 3607.23 (7.41x) | 1595.14 (3.28x) |
| Any NumberValue WKT JSON stringify | 172.52 | — | — | 2505.02 (14.52x) | 1037.42 (6.01x) |
| Any NumberValue WKT JSON parse | 507.19 | — | — | 3687.00 (7.27x) | 1646.47 (3.25x) |
| Any NumberValue Exponent WKT JSON parse | 509.58 | — | — | 3690.33 (7.24x) | 1631.95 (3.20x) |
| Any NegativeNumberValue WKT JSON stringify | 174.64 | — | — | 2508.84 (14.37x) | 1040.08 (5.96x) |
| Any NegativeNumberValue WKT JSON parse | 509.80 | — | — | 3705.21 (7.27x) | 1614.75 (3.17x) |
| Any ZeroNumberValue WKT JSON stringify | 142.30 | — | — | 2473.29 (17.38x) | 932.34 (6.55x) |
| Any ZeroNumberValue WKT JSON parse | 507.88 | — | — | 3625.82 (7.14x) | 1643.41 (3.24x) |
| Any BoolScalarValue WKT JSON stringify | 128.27 | — | — | 2251.12 (17.55x) | 912.16 (7.11x) |
| Any BoolScalarValue WKT JSON parse | 468.53 | — | — | 3594.08 (7.67x) | 1553.47 (3.32x) |
| Any FalseBoolScalarValue WKT JSON stringify | 134.85 | — | — | 2250.77 (16.69x) | 913.86 (6.78x) |
| Any FalseBoolScalarValue WKT JSON parse | 468.56 | — | — | 3599.59 (7.68x) | 1567.47 (3.35x) |
| Any ListKindValue WKT JSON stringify | 508.18 | — | — | 5557.74 (10.94x) | 4761.39 (9.37x) |
| Any ListKindValue WKT JSON parse | 1385.17 | — | — | 9843.31 (7.11x) | 7068.79 (5.10x) |
| Any ListKindValue Escape WKT JSON parse | 1406.82 | — | — | 9918.14 (7.05x) | 7245.42 (5.15x) |
| Any ListKindValue Surrogate WKT JSON parse | 724.16 | — | — | 4830.87 (6.67x) | 2676.37 (3.70x) |
| Any EmptyStructKindValue WKT JSON stringify | 144.53 | — | — | 2910.73 (20.14x) | 1277.96 (8.84x) |
| Any EmptyStructKindValue WKT JSON parse | 504.78 | — | — | 5385.72 (10.67x) | 1962.16 (3.89x) |
| Any EmptyListKindValue WKT JSON stringify | 144.41 | — | — | 2891.98 (20.03x) | 1091.24 (7.56x) |
| Any EmptyListKindValue WKT JSON parse | 503.38 | — | — | 4392.03 (8.73x) | 1851.70 (3.68x) |
| Any DoubleValue WKT JSON stringify | 191.42 | — | — | 1792.36 (9.36x) | 803.65 (4.20x) |
| Any DoubleValue WKT JSON parse | 529.56 | — | — | 2740.73 (5.18x) | 1457.24 (2.75x) |
| Any DoubleValue String WKT JSON parse | 545.63 | — | — | 2730.92 (5.01x) | 1523.19 (2.79x) |
| Any DoubleValue Exponent WKT JSON parse | 531.72 | — | — | 2742.85 (5.16x) | 1487.56 (2.80x) |
| Any NegativeDoubleValue WKT JSON stringify | 189.98 | — | — | 1791.76 (9.43x) | 799.92 (4.21x) |
| Any NegativeDoubleValue WKT JSON parse | 530.11 | — | — | 2731.11 (5.15x) | 1448.91 (2.73x) |
| Any ZeroDoubleValue WKT JSON stringify | 162.23 | — | — | 913.64 (5.63x) | 730.90 (4.51x) |
| Any ZeroDoubleValue WKT JSON parse | 529.05 | — | — | 2157.64 (4.08x) | 1390.57 (2.63x) |
| Any DoubleValue NaN WKT JSON stringify | 158.65 | — | — | 1562.38 (9.85x) | 719.29 (4.53x) |
| Any DoubleValue NaN WKT JSON parse | 523.29 | — | — | 2644.07 (5.05x) | 1417.65 (2.71x) |
| Any DoubleValue Infinity WKT JSON stringify | 165.93 | — | — | 1556.92 (9.38x) | 727.93 (4.39x) |
| Any DoubleValue Infinity WKT JSON parse | 529.41 | — | — | 2687.43 (5.08x) | 1412.87 (2.67x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 168.93 | — | — | 1546.88 (9.16x) | 720.56 (4.27x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 533.36 | — | — | 2673.71 (5.01x) | 1424.98 (2.67x) |
| Any FloatValue WKT JSON stringify | 194.09 | — | — | 1733.43 (8.93x) | 810.02 (4.17x) |
| Any FloatValue WKT JSON parse | 525.96 | — | — | 2703.42 (5.14x) | 1424.66 (2.71x) |
| Any FloatValue String WKT JSON parse | 538.93 | — | — | 2706.16 (5.02x) | 1529.01 (2.84x) |
| Any FloatValue Exponent WKT JSON parse | 527.56 | — | — | 2716.63 (5.15x) | 1445.85 (2.74x) |
| Any NegativeFloatValue WKT JSON stringify | 198.58 | — | — | 1732.08 (8.72x) | 787.74 (3.97x) |
| Any NegativeFloatValue WKT JSON parse | 526.88 | — | — | 2706.79 (5.14x) | 1415.39 (2.69x) |
| Any ZeroFloatValue WKT JSON stringify | 159.42 | — | — | 917.56 (5.76x) | 735.91 (4.62x) |
| Any ZeroFloatValue WKT JSON parse | 526.32 | — | — | 2146.96 (4.08x) | 1396.65 (2.65x) |
| Any FloatValue NaN WKT JSON stringify | 165.04 | — | — | 1561.83 (9.46x) | 720.49 (4.37x) |
| Any FloatValue NaN WKT JSON parse | 519.79 | — | — | 2615.66 (5.03x) | 1394.03 (2.68x) |
| Any FloatValue Infinity WKT JSON stringify | 164.18 | — | — | 1542.34 (9.39x) | 717.51 (4.37x) |
| Any FloatValue Infinity WKT JSON parse | 525.72 | — | — | 2660.14 (5.06x) | 1398.43 (2.66x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 166.83 | — | — | 1541.77 (9.24x) | 717.02 (4.30x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 525.14 | — | — | 2646.18 (5.04x) | 1413.88 (2.69x) |
| Any Int64Value WKT JSON stringify | 172.45 | — | — | 1558.99 (9.04x) | 843.35 (4.89x) |
| Any Int64Value WKT JSON parse | 552.87 | — | — | 2772.59 (5.01x) | 1665.06 (3.01x) |
| Any Int64Value Number WKT JSON parse | 550.48 | — | — | 2761.48 (5.02x) | 1523.65 (2.77x) |
| Any Int64Value Exponent WKT JSON parse | 540.08 | — | — | 2718.70 (5.03x) | 1493.49 (2.77x) |
| Any ZeroInt64Value WKT JSON stringify | 164.26 | — | — | 915.39 (5.57x) | 778.16 (4.74x) |
| Any ZeroInt64Value WKT JSON parse | 530.92 | — | — | 2164.80 (4.08x) | 1530.04 (2.88x) |
| Any NegativeInt64Value WKT JSON stringify | 177.61 | — | — | 1557.26 (8.77x) | 850.21 (4.79x) |
| Any NegativeInt64Value WKT JSON parse | 558.49 | — | — | 2803.12 (5.02x) | 1672.97 (3.00x) |
| Any MinInt64Value WKT JSON stringify | 176.92 | — | — | 1562.24 (8.83x) | 861.70 (4.87x) |
| Any MinInt64Value WKT JSON parse | 568.59 | — | — | 2815.31 (4.95x) | 1704.07 (3.00x) |
| Any MaxInt64Value WKT JSON stringify | 179.31 | — | — | 1560.04 (8.70x) | 864.19 (4.82x) |
| Any MaxInt64Value WKT JSON parse | 558.05 | — | — | 2807.09 (5.03x) | 1686.53 (3.02x) |
| Any UInt64Value WKT JSON stringify | 182.73 | — | — | 1557.79 (8.53x) | 850.77 (4.66x) |
| Any UInt64Value WKT JSON parse | 564.10 | — | — | 2794.80 (4.95x) | 1664.28 (2.95x) |
| Any UInt64Value Number WKT JSON parse | 555.46 | — | — | 2766.08 (4.98x) | 1529.62 (2.75x) |
| Any UInt64Value Exponent WKT JSON parse | 546.29 | — | — | 2712.26 (4.96x) | 1489.53 (2.73x) |
| Any ZeroUInt64Value WKT JSON stringify | 171.49 | — | — | 916.98 (5.35x) | 790.86 (4.61x) |
| Any ZeroUInt64Value WKT JSON parse | 535.27 | — | — | 2150.44 (4.02x) | 1502.20 (2.81x) |
| Any MaxUInt64Value WKT JSON stringify | 186.34 | — | — | 1556.38 (8.35x) | 866.51 (4.65x) |
| Any MaxUInt64Value WKT JSON parse | 570.96 | — | — | 2828.37 (4.95x) | 1708.29 (2.99x) |
| Any Int32Value WKT JSON stringify | 174.14 | — | — | 1544.38 (8.87x) | 736.75 (4.23x) |
| Any Int32Value WKT JSON parse | 543.49 | — | — | 2666.51 (4.91x) | 1444.27 (2.66x) |
| Any Int32Value String WKT JSON parse | 551.12 | — | — | 2673.02 (4.85x) | 1536.11 (2.79x) |
| Any Int32Value Exponent WKT JSON parse | 550.94 | — | — | 2707.44 (4.91x) | 1485.51 (2.70x) |
| Any ZeroInt32Value WKT JSON stringify | 174.62 | — | — | 914.82 (5.24x) | 719.46 (4.12x) |
| Any ZeroInt32Value WKT JSON parse | 541.80 | — | — | 2156.32 (3.98x) | 1409.34 (2.60x) |
| Any NegativeInt32Value WKT JSON stringify | 176.47 | — | — | 1621.58 (9.19x) | 739.10 (4.19x) |
| Any NegativeInt32Value WKT JSON parse | 546.58 | — | — | 2719.17 (4.97x) | 1468.69 (2.69x) |
| Any MinInt32Value WKT JSON stringify | 177.86 | — | — | 1559.92 (8.77x) | 744.40 (4.19x) |
| Any MinInt32Value WKT JSON parse | 552.33 | — | — | 2722.09 (4.93x) | 1506.60 (2.73x) |
| Any MaxInt32Value WKT JSON stringify | 174.37 | — | — | 1554.04 (8.91x) | 741.04 (4.25x) |
| Any MaxInt32Value WKT JSON parse | 549.28 | — | — | 2686.59 (4.89x) | 1447.25 (2.63x) |
| Any UInt32Value WKT JSON stringify | 180.58 | — | — | 1552.10 (8.60x) | 730.14 (4.04x) |
| Any UInt32Value WKT JSON parse | 545.04 | — | — | 2689.66 (4.93x) | 1456.54 (2.67x) |
| Any UInt32Value String WKT JSON parse | 553.17 | — | — | 2683.45 (4.85x) | 1552.67 (2.81x) |
| Any UInt32Value Exponent WKT JSON parse | 548.46 | — | — | 2710.43 (4.94x) | 1499.33 (2.73x) |
| Any ZeroUInt32Value WKT JSON stringify | 177.93 | — | — | 917.68 (5.16x) | 709.41 (3.99x) |
| Any ZeroUInt32Value WKT JSON parse | 540.71 | — | — | 2155.23 (3.99x) | 1401.41 (2.59x) |
| Any MaxUInt32Value WKT JSON stringify | 186.08 | — | — | 1557.88 (8.37x) | 737.38 (3.96x) |
| Any MaxUInt32Value WKT JSON parse | 551.32 | — | — | 2690.30 (4.88x) | 1451.72 (2.63x) |
| Any BoolValue WKT JSON stringify | 180.19 | — | — | 1525.18 (8.46x) | 717.99 (3.98x) |
| Any BoolValue WKT JSON parse | 496.30 | — | — | 2617.07 (5.27x) | 1360.92 (2.74x) |
| Any FalseBoolValue WKT JSON stringify | 181.36 | — | — | 915.61 (5.05x) | 702.69 (3.87x) |
| Any FalseBoolValue WKT JSON parse | 496.36 | — | — | 2153.67 (4.34x) | 1345.73 (2.71x) |
| Any StringValue WKT JSON stringify | 208.83 | — | — | 1564.18 (7.49x) | 798.46 (3.82x) |
| Any StringValue WKT JSON parse | 557.89 | — | — | 2661.48 (4.77x) | 1450.31 (2.60x) |
| Any StringValue Escape WKT JSON parse | 566.90 | — | — | 2712.71 (4.79x) | 1550.80 (2.74x) |
| Any StringValue Surrogate WKT JSON parse | 572.38 | — | — | 2699.28 (4.72x) | 1553.40 (2.71x) |
| Any EmptyStringValue WKT JSON stringify | 195.34 | — | — | 925.70 (4.74x) | 754.52 (3.86x) |
| Any EmptyStringValue WKT JSON parse | 527.57 | — | — | 2171.41 (4.12x) | 1377.26 (2.61x) |
| Any BytesValue WKT JSON stringify | 194.85 | — | — | 1593.83 (8.18x) | 839.22 (4.31x) |
| Any BytesValue WKT JSON parse | 569.80 | — | — | 2690.26 (4.72x) | 1477.77 (2.59x) |
| Any BytesValue URL WKT JSON parse | 584.50 | — | — | 2686.84 (4.60x) | 1471.97 (2.52x) |
| Any BytesValue StandardBase64 WKT JSON parse | 570.70 | — | — | 2709.48 (4.75x) | 1455.22 (2.55x) |
| Any BytesValue Unpadded WKT JSON parse | 571.50 | — | — | 2695.42 (4.72x) | 1485.17 (2.60x) |
| Any EmptyBytesValue WKT JSON stringify | 190.90 | — | — | 913.49 (4.79x) | 757.23 (3.97x) |
| Any EmptyBytesValue WKT JSON parse | 535.19 | — | — | 2159.43 (4.03x) | 1420.88 (2.65x) |
| Nested Any WKT JSON stringify | 313.32 | — | — | 2472.72 (7.89x) | 1444.70 (4.61x) |
| Nested Any WKT JSON parse | 878.77 | — | — | 4258.78 (4.85x) | 2896.09 (3.30x) |
| Duration JSON stringify | 58.84 | — | — | 959.28 (16.30x) | 362.87 (6.17x) |
| Duration JSON parse | 21.05 | — | — | 1447.63 (68.77x) | 408.94 (19.43x) |
| Duration Escape JSON parse | 39.74 | — | — | 1481.82 (37.29x) | 450.28 (11.33x) |
| PlusDuration JSON parse | 18.86 | — | — | 1443.45 (76.53x) | 394.07 (20.89x) |
| ShortFractionDuration JSON parse | 17.30 | — | — | 1415.10 (81.80x) | 389.04 (22.49x) |
| MicroDuration JSON stringify | 59.84 | — | — | 970.38 (16.22x) | 414.27 (6.92x) |
| MicroDuration JSON parse | 20.57 | — | — | 1463.77 (71.16x) | 392.67 (19.09x) |
| NanoDuration JSON stringify | 57.14 | — | — | 998.15 (17.47x) | 414.67 (7.26x) |
| NanoDuration JSON parse | 24.06 | — | — | 1475.91 (61.34x) | 411.11 (17.09x) |
| NegativeDuration JSON stringify | 60.09 | — | — | 999.90 (16.64x) | 427.55 (7.12x) |
| NegativeDuration JSON parse | 18.75 | — | — | 1505.40 (80.29x) | 403.28 (21.51x) |
| FractionalNegativeDuration JSON stringify | 60.08 | — | — | 973.42 (16.20x) | 435.70 (7.25x) |
| FractionalNegativeDuration JSON parse | 19.43 | — | — | 1460.24 (75.15x) | 375.76 (19.34x) |
| MaxDuration JSON stringify | 49.65 | — | — | 859.34 (17.31x) | 419.01 (8.44x) |
| MaxDuration JSON parse | 31.14 | — | — | 1436.72 (46.14x) | 412.30 (13.24x) |
| MinDuration JSON stringify | 49.97 | — | — | 869.21 (17.39x) | 446.77 (8.94x) |
| MinDuration JSON parse | 33.63 | — | — | 1447.05 (43.03x) | 419.91 (12.49x) |
| ZeroDuration JSON stringify | 44.85 | — | — | 815.98 (18.19x) | 351.67 (7.84x) |
| ZeroDuration JSON parse | 14.80 | — | — | 1362.55 (92.06x) | 319.35 (21.58x) |
| FieldMask JSON stringify | 67.80 | — | — | 883.29 (13.03x) | 658.38 (9.71x) |
| FieldMask JSON parse | 139.99 | — | — | 1659.40 (11.85x) | 892.35 (6.37x) |
| FieldMask Escape JSON parse | 187.88 | — | — | 1715.52 (9.13x) | 987.58 (5.26x) |
| EmptyFieldMask JSON stringify | 40.67 | — | — | 609.65 (14.99x) | 190.39 (4.68x) |
| EmptyFieldMask JSON parse | 4.78 | — | — | 940.64 (196.79x) | 167.76 (35.10x) |
| Timestamp JSON stringify | 94.89 | — | — | 1140.35 (12.02x) | 420.03 (4.43x) |
| Timestamp JSON parse | 45.12 | — | — | 1496.34 (33.16x) | 467.28 (10.36x) |
| Timestamp Escape JSON parse | 97.00 | — | — | 1523.90 (15.71x) | 532.19 (5.49x) |
| ShortFraction Timestamp JSON parse | 43.43 | — | — | 1485.93 (34.21x) | 460.83 (10.61x) |
| Micro Timestamp JSON stringify | 96.76 | — | — | 1152.46 (11.91x) | 409.53 (4.23x) |
| Micro Timestamp JSON parse | 48.15 | — | — | 1512.90 (31.42x) | 473.65 (9.84x) |
| Nano Timestamp JSON stringify | 94.52 | — | — | 1185.64 (12.54x) | 412.37 (4.36x) |
| Nano Timestamp JSON parse | 49.66 | — | — | 1520.90 (30.63x) | 477.12 (9.61x) |
| Offset Timestamp JSON parse | 51.27 | — | — | 1512.02 (29.49x) | 499.07 (9.73x) |
| PreEpoch Timestamp JSON stringify | 66.19 | — | — | 1069.01 (16.15x) | 387.98 (5.86x) |
| PreEpoch Timestamp JSON parse | 43.04 | — | — | 1464.28 (34.02x) | 442.66 (10.28x) |
| Max Timestamp JSON stringify | 78.65 | — | — | 1205.61 (15.33x) | 413.58 (5.26x) |
| Max Timestamp JSON parse | 51.08 | — | — | 1548.49 (30.31x) | 473.60 (9.27x) |
| Min Timestamp JSON stringify | 79.69 | — | — | 1069.62 (13.42x) | 393.63 (4.94x) |
| Min Timestamp JSON parse | 41.15 | — | — | 1479.85 (35.96x) | 438.97 (10.67x) |
| Empty JSON stringify | 20.84 | — | — | 496.75 (23.84x) | 78.78 (3.78x) |
| Empty JSON parse | 68.66 | — | — | 725.55 (10.57x) | 229.71 (3.35x) |
| Struct JSON stringify | 193.87 | — | — | 5725.46 (29.53x) | 3067.66 (15.82x) |
| Struct JSON parse | 848.81 | — | — | 10896.90 (12.84x) | 4629.11 (5.45x) |
| Struct Escape JSON parse | 888.36 | — | — | 17893.20 (20.14x) | 4760.00 (5.36x) |
| Struct NumberExponent JSON parse | 841.23 | — | — | 11145.20 (13.25x) | 4674.58 (5.56x) |
| Struct Surrogate JSON parse | 370.52 | — | — | 4945.17 (13.35x) | 1185.17 (3.20x) |
| Struct KeySurrogate JSON parse | 370.56 | — | — | 9242.86 (24.94x) | 1187.66 (3.21x) |
| EmptyStruct JSON stringify | 41.14 | — | — | 1250.48 (30.40x) | 353.41 (8.59x) |
| EmptyStruct JSON parse | 86.58 | — | — | 2128.77 (24.59x) | 375.25 (4.33x) |
| Value JSON stringify | 194.36 | — | — | 10309.50 (53.04x) | 3249.56 (16.72x) |
| Value JSON parse | 867.58 | — | — | 12235.50 (14.10x) | 4883.56 (5.63x) |
| Value Escape JSON parse | 914.55 | — | — | 12228.90 (13.37x) | 5015.43 (5.48x) |
| Value NumberExponent JSON parse | 863.80 | — | — | 12157.60 (14.07x) | 4922.23 (5.70x) |
| Value Surrogate JSON parse | 394.98 | — | — | 6637.65 (16.81x) | 1473.81 (3.73x) |
| Value KeySurrogate JSON parse | 393.59 | — | — | 6604.86 (16.78x) | 1558.14 (3.96x) |
| NullValue JSON stringify | 40.34 | — | — | 1315.71 (32.62x) | 251.37 (6.23x) |
| NullValue JSON parse | 69.66 | — | — | 2468.19 (35.43x) | 399.83 (5.74x) |
| StringScalarValue JSON stringify | 47.61 | — | — | 1338.64 (28.12x) | 300.21 (6.31x) |
| StringScalarValue JSON parse | 140.75 | — | — | 2091.02 (14.86x) | 443.34 (3.15x) |
| StringScalarValue Escape JSON parse | 150.75 | — | — | 2131.64 (14.14x) | 493.79 (3.28x) |
| StringScalarValue Surrogate JSON parse | 149.51 | — | — | 2139.29 (14.31x) | 502.00 (3.36x) |
| EmptyStringScalarValue JSON stringify | 45.78 | — | — | 1332.10 (29.10x) | 276.25 (6.03x) |
| EmptyStringScalarValue JSON parse | 87.21 | — | — | 2066.33 (23.69x) | 369.59 (4.24x) |
| NumberValue JSON stringify | 73.10 | — | — | 1548.59 (21.18x) | 340.84 (4.66x) |
| NumberValue JSON parse | 133.34 | — | — | 2170.31 (16.28x) | 412.04 (3.09x) |
| NumberValue Exponent JSON parse | 134.90 | — | — | 2183.71 (16.19x) | 435.54 (3.23x) |
| NegativeNumberValue JSON stringify | 73.55 | — | — | 1551.56 (21.10x) | 335.58 (4.56x) |
| NegativeNumberValue JSON parse | 133.12 | — | — | 2183.41 (16.40x) | 440.36 (3.31x) |
| ZeroNumberValue JSON stringify | 50.66 | — | — | 1501.35 (29.64x) | 290.12 (5.73x) |
| ZeroNumberValue JSON parse | 130.02 | — | — | 2107.97 (16.21x) | 388.19 (2.99x) |
| BoolScalarValue JSON stringify | 40.50 | — | — | 1311.82 (32.39x) | 222.25 (5.49x) |
| BoolScalarValue JSON parse | 69.66 | — | — | 2014.11 (28.91x) | 343.71 (4.93x) |
| FalseBoolScalarValue JSON stringify | 40.35 | — | — | 1310.18 (32.47x) | 240.10 (5.95x) |
| FalseBoolScalarValue JSON parse | 70.17 | — | — | 2020.61 (28.80x) | 333.82 (4.76x) |
| ListKindValue JSON stringify | 144.93 | — | — | 6122.16 (42.24x) | 2364.47 (16.31x) |
| ListKindValue JSON parse | 673.43 | — | — | 10391.40 (15.43x) | 4096.28 (6.08x) |
| ListKindValue Escape JSON parse | 695.20 | — | — | 10469.90 (15.06x) | 4350.13 (6.26x) |
| ListKindValue Surrogate JSON parse | 320.84 | — | — | 4854.32 (15.13x) | 1203.08 (3.75x) |
| EmptyStructKindValue JSON stringify | 42.88 | — | — | 1927.41 (44.95x) | 537.30 (12.53x) |
| EmptyStructKindValue JSON parse | 110.27 | — | — | 3748.59 (33.99x) | 666.11 (6.04x) |
| EmptyListKindValue JSON stringify | 41.39 | — | — | 1943.96 (46.97x) | 366.67 (8.86x) |
| EmptyListKindValue JSON parse | 147.19 | — | — | 4028.89 (27.37x) | 609.70 (4.14x) |
| ListValue JSON stringify | 148.21 | — | — | 4739.54 (31.98x) | 2174.00 (14.67x) |
| ListValue JSON parse | 657.28 | — | — | 8517.41 (12.96x) | 3842.88 (5.85x) |
| ListValue Escape JSON parse | 680.46 | — | — | 8620.56 (12.67x) | 3943.48 (5.80x) |
| ListValue Surrogate JSON parse | 298.01 | — | — | 3085.85 (10.35x) | 920.01 (3.09x) |
| EmptyListValue JSON stringify | 40.19 | — | — | 702.81 (17.49x) | 186.79 (4.65x) |
| EmptyListValue JSON parse | 126.42 | — | — | 2240.81 (17.73x) | 338.65 (2.68x) |
| DoubleValue JSON stringify | 68.67 | — | — | 868.14 (12.64x) | 196.11 (2.86x) |
| DoubleValue JSON parse | 109.68 | — | — | 1235.53 (11.26x) | 303.87 (2.77x) |
| DoubleValue String JSON parse | 111.44 | — | — | 1173.35 (10.53x) | 390.27 (3.50x) |
| DoubleValue Exponent JSON parse | 113.28 | — | — | 1250.11 (11.04x) | 298.61 (2.64x) |
| NegativeDoubleValue JSON stringify | 67.92 | — | — | 870.31 (12.81x) | 199.25 (2.93x) |
| NegativeDoubleValue JSON parse | 111.71 | — | — | 1230.45 (11.01x) | 303.13 (2.71x) |
| ZeroDoubleValue JSON stringify | 47.30 | — | — | 812.28 (17.17x) | 140.31 (2.97x) |
| ZeroDoubleValue JSON parse | 108.67 | — | — | 1162.95 (10.70x) | 270.06 (2.49x) |
| DoubleValue NaN JSON stringify | 46.42 | — | — | 674.88 (14.54x) | 126.79 (2.73x) |
| DoubleValue NaN JSON parse | 104.54 | — | — | 1093.97 (10.46x) | 284.79 (2.72x) |
| DoubleValue Infinity JSON stringify | 48.23 | — | — | 670.43 (13.90x) | 122.94 (2.55x) |
| DoubleValue Infinity JSON parse | 106.07 | — | — | 1108.65 (10.45x) | 282.82 (2.67x) |
| DoubleValue NegativeInfinity JSON stringify | 48.25 | — | — | 665.66 (13.80x) | 126.47 (2.62x) |
| DoubleValue NegativeInfinity JSON parse | 107.59 | — | — | 1104.27 (10.26x) | 303.36 (2.82x) |
| FloatValue JSON stringify | 71.23 | — | — | 801.53 (11.25x) | 185.97 (2.61x) |
| FloatValue JSON parse | 110.55 | — | — | 1211.87 (10.96x) | 307.26 (2.78x) |
| FloatValue String JSON parse | 110.00 | — | — | 1146.84 (10.43x) | 379.65 (3.45x) |
| FloatValue Exponent JSON parse | 113.27 | — | — | 1221.97 (10.79x) | 316.24 (2.79x) |
| NegativeFloatValue JSON stringify | 86.87 | — | — | 802.60 (9.24x) | 195.88 (2.25x) |
| NegativeFloatValue JSON parse | 111.04 | — | — | 1219.44 (10.98x) | 292.78 (2.64x) |
| ZeroFloatValue JSON stringify | 47.19 | — | — | 752.67 (15.95x) | 148.31 (3.14x) |
| ZeroFloatValue JSON parse | 107.72 | — | — | 1161.04 (10.78x) | 270.58 (2.51x) |
| FloatValue NaN JSON stringify | 46.48 | — | — | 650.33 (13.99x) | 124.71 (2.68x) |
| FloatValue NaN JSON parse | 104.90 | — | — | 1086.33 (10.36x) | 280.49 (2.67x) |
| FloatValue Infinity JSON stringify | 47.92 | — | — | 639.95 (13.35x) | 127.61 (2.66x) |
| FloatValue Infinity JSON parse | 106.36 | — | — | 1092.34 (10.27x) | 284.83 (2.68x) |
| FloatValue NegativeInfinity JSON stringify | 48.21 | — | — | 636.80 (13.21x) | 130.46 (2.71x) |
| FloatValue NegativeInfinity JSON parse | 107.67 | — | — | 1094.15 (10.16x) | 293.65 (2.73x) |
| Int64Value JSON stringify | 50.31 | — | — | 677.11 (13.46x) | 278.26 (5.53x) |
| Int64Value JSON parse | 124.84 | — | — | 1227.56 (9.83x) | 478.94 (3.84x) |
| Int64Value Number JSON parse | 129.01 | — | — | 1281.84 (9.94x) | 352.69 (2.73x) |
| Int64Value Exponent JSON parse | 116.49 | — | — | 1220.89 (10.48x) | 364.66 (3.13x) |
| ZeroInt64Value JSON stringify | 41.29 | — | — | 619.98 (15.02x) | 192.34 (4.66x) |
| ZeroInt64Value JSON parse | 106.49 | — | — | 1099.86 (10.33x) | 350.49 (3.29x) |
| NegativeInt64Value JSON stringify | 50.42 | — | — | 675.50 (13.40x) | 288.77 (5.73x) |
| NegativeInt64Value JSON parse | 126.72 | — | — | 1212.96 (9.57x) | 494.32 (3.90x) |
| MinInt64Value JSON stringify | 49.43 | — | — | 676.50 (13.69x) | 297.39 (6.02x) |
| MinInt64Value JSON parse | 136.56 | — | — | 1248.59 (9.14x) | 504.76 (3.70x) |
| MaxInt64Value JSON stringify | 49.56 | — | — | 675.15 (13.62x) | 296.00 (5.97x) |
| MaxInt64Value JSON parse | 132.61 | — | — | 1247.23 (9.41x) | 498.66 (3.76x) |
| UInt64Value JSON stringify | 49.72 | — | — | 676.13 (13.60x) | 286.68 (5.77x) |
| UInt64Value JSON parse | 127.68 | — | — | 1215.66 (9.52x) | 473.95 (3.71x) |
| UInt64Value Number JSON parse | 127.32 | — | — | 1274.07 (10.01x) | 352.15 (2.77x) |
| UInt64Value Exponent JSON parse | 117.81 | — | — | 1221.70 (10.37x) | 363.01 (3.08x) |
| ZeroUInt64Value JSON stringify | 41.35 | — | — | 615.19 (14.88x) | 201.66 (4.88x) |
| ZeroUInt64Value JSON parse | 107.69 | — | — | 1096.58 (10.18x) | 343.10 (3.19x) |
| MaxUInt64Value JSON stringify | 49.94 | — | — | 677.87 (13.57x) | 299.13 (5.99x) |
| MaxUInt64Value JSON parse | 144.32 | — | — | 1253.55 (8.69x) | 485.76 (3.37x) |
| Int32Value JSON stringify | 46.79 | — | — | 636.85 (13.61x) | 138.83 (2.97x) |
| Int32Value JSON parse | 131.75 | — | — | 1183.39 (8.98x) | 316.34 (2.40x) |
| Int32Value String JSON parse | 135.07 | — | — | 1131.86 (8.38x) | 405.68 (3.00x) |
| Int32Value Exponent JSON parse | 134.94 | — | — | 1221.56 (9.05x) | 361.56 (2.68x) |
| ZeroInt32Value JSON stringify | 46.81 | — | — | 614.44 (13.13x) | 129.50 (2.77x) |
| ZeroInt32Value JSON parse | 127.53 | — | — | 1153.15 (9.04x) | 268.59 (2.11x) |
| NegativeInt32Value JSON stringify | 46.75 | — | — | 643.33 (13.76x) | 139.74 (2.99x) |
| NegativeInt32Value JSON parse | 130.91 | — | — | 1256.87 (9.60x) | 327.34 (2.50x) |
| MinInt32Value JSON stringify | 47.39 | — | — | 643.24 (13.57x) | 138.22 (2.92x) |
| MinInt32Value JSON parse | 136.51 | — | — | 1210.12 (8.86x) | 352.10 (2.58x) |
| MaxInt32Value JSON stringify | 47.27 | — | — | 631.40 (13.36x) | 137.21 (2.90x) |
| MaxInt32Value JSON parse | 137.57 | — | — | 1206.55 (8.77x) | 334.32 (2.43x) |
| UInt32Value JSON stringify | 46.86 | — | — | 654.03 (13.96x) | 136.38 (2.91x) |
| UInt32Value JSON parse | 132.24 | — | — | 1186.56 (8.97x) | 322.85 (2.44x) |
| UInt32Value String JSON parse | 135.61 | — | — | 1130.44 (8.34x) | 395.23 (2.91x) |
| UInt32Value Exponent JSON parse | 135.63 | — | — | 1224.87 (9.03x) | 363.26 (2.68x) |
| ZeroUInt32Value JSON stringify | 46.67 | — | — | 638.29 (13.68x) | 132.83 (2.85x) |
| ZeroUInt32Value JSON parse | 127.54 | — | — | 1156.49 (9.07x) | 265.67 (2.08x) |
| MaxUInt32Value JSON stringify | 46.91 | — | — | 648.79 (13.83x) | 142.56 (3.04x) |
| MaxUInt32Value JSON parse | 137.74 | — | — | 1209.76 (8.78x) | 328.47 (2.38x) |
| BoolValue JSON stringify | 45.10 | — | — | 629.14 (13.95x) | 130.84 (2.90x) |
| BoolValue JSON parse | 60.14 | — | — | 1059.67 (17.62x) | 228.50 (3.80x) |
| FalseBoolValue JSON stringify | 45.01 | — | — | 623.83 (13.86x) | 127.61 (2.84x) |
| FalseBoolValue JSON parse | 60.59 | — | — | 1059.85 (17.49x) | 215.58 (3.56x) |
| StringValue JSON stringify | 52.57 | — | — | 675.84 (12.86x) | 185.55 (3.53x) |
| StringValue JSON parse | 120.84 | — | — | 1142.40 (9.45x) | 326.32 (2.70x) |
| StringValue Escape JSON parse | 130.00 | — | — | 1175.70 (9.04x) | 377.31 (2.90x) |
| StringValue Surrogate JSON parse | 127.34 | — | — | 1170.24 (9.19x) | 381.52 (3.00x) |
| EmptyStringValue JSON stringify | 50.15 | — | — | 643.17 (12.82x) | 177.02 (3.53x) |
| EmptyStringValue JSON parse | 66.29 | — | — | 1115.70 (16.83x) | 242.31 (3.66x) |
| BytesValue JSON stringify | 49.02 | — | — | 681.19 (13.90x) | 202.97 (4.14x) |
| BytesValue JSON parse | 126.02 | — | — | 1178.34 (9.35x) | 355.38 (2.82x) |
| BytesValue URL JSON parse | 142.20 | — | — | 1164.69 (8.19x) | 341.34 (2.40x) |
| BytesValue StandardBase64 JSON parse | 124.45 | — | — | 1181.86 (9.50x) | 348.79 (2.80x) |
| BytesValue Unpadded JSON parse | 124.07 | — | — | 1164.20 (9.38x) | 344.27 (2.77x) |
| EmptyBytesValue JSON stringify | 40.62 | — | — | 662.07 (16.30x) | 182.99 (4.50x) |
| EmptyBytesValue JSON parse | 68.69 | — | — | 1136.56 (16.55x) | 301.21 (4.39x) |
| TextFormat format | 183.14 | — | — | 2572.94 (14.05x) | 2523.64 (13.78x) |
| TextFormat parse | 715.19 | — | — | 4999.11 (6.99x) | 6564.03 (9.18x) |
| packed fixed32 encode | 2.01 | 551.06 (274.16x) | 541.27 (269.29x) | 44.18 (21.98x) | 394.33 (196.18x) |
| packed fixed32 decode | 4.54 | 1028.86 (226.62x) | 1970.60 (434.05x) | 49.48 (10.90x) | 1566.24 (344.99x) |
| packed fixed64 encode | 2.01 | 576.57 (286.85x) | 562.93 (280.06x) | 76.18 (37.90x) | 399.33 (198.67x) |
| packed fixed64 decode | 4.51 | 1039.81 (230.56x) | 7944.75 (1761.59x) | 79.79 (17.69x) | 2221.19 (492.50x) |
| packed sfixed32 encode | 2.01 | 552.38 (274.82x) | 561.67 (279.44x) | 43.74 (21.76x) | 394.67 (196.35x) |
| packed sfixed32 decode | 4.53 | 1056.16 (233.15x) | 1983.78 (437.92x) | 48.72 (10.76x) | 1561.64 (344.73x) |
| packed sfixed64 encode | 2.01 | 573.43 (285.29x) | 565.71 (281.45x) | 75.48 (37.55x) | 396.39 (197.21x) |
| packed sfixed64 decode | 4.53 | 1007.81 (222.47x) | 7910.04 (1746.15x) | 79.43 (17.53x) | 2215.36 (489.04x) |
| packed float encode | 2.01 | 817.90 (406.92x) | 540.97 (269.14x) | 43.81 (21.80x) | 356.20 (177.21x) |
| packed float decode | 4.54 | 1042.29 (229.58x) | 2050.05 (451.55x) | 48.64 (10.71x) | 1562.79 (344.23x) |
| packed double encode | 2.00 | 834.28 (417.14x) | 562.29 (281.14x) | 75.67 (37.84x) | 356.89 (178.44x) |
| packed double decode | 4.52 | 987.35 (218.44x) | 2045.06 (452.45x) | 79.11 (17.50x) | 2189.40 (484.38x) |
| packed uint64 encode | 1298.69 | 4600.72 (3.54x) | 4039.24 (3.11x) | 2162.13 (1.66x) | 3468.73 (2.67x) |
| packed uint64 decode | 1783.24 | 2787.29 (1.56x) | 8855.67 (4.97x) | 2807.13 (1.57x) | 6323.66 (3.55x) |
| packed uint32 encode | 923.97 | 3613.10 (3.91x) | 3532.97 (3.82x) | 1757.67 (1.90x) | 2884.90 (3.12x) |
| packed uint32 decode | 1292.75 | 2438.17 (1.89x) | 3265.98 (2.53x) | 1990.44 (1.54x) | 4700.84 (3.64x) |
| packed int64 encode | 1409.57 | 10957.31 (7.77x) | 6073.42 (4.31x) | 2915.80 (2.07x) | 4104.43 (2.91x) |
| packed int64 decode | 2738.61 | 3422.34 (1.25x) | 10267.98 (3.75x) | 4567.13 (1.67x) | 7691.45 (2.81x) |
| packed sint32 encode | 781.61 | 3032.15 (3.88x) | 2904.00 (3.72x) | 1531.04 (1.96x) | 3413.35 (4.37x) |
| packed sint32 decode | 954.42 | 2544.97 (2.67x) | 3213.74 (3.37x) | 1130.62 (1.18x) | 3001.24 (3.14x) |
| packed sint64 encode | 1437.05 | 4927.64 (3.43x) | 4308.87 (3.00x) | 2453.25 (1.71x) | 4145.77 (2.88x) |
| packed sint64 decode | 2036.95 | 3064.25 (1.50x) | 9648.53 (4.74x) | 2936.97 (1.44x) | 6509.06 (3.20x) |
| packed bool encode | 2.00 | 1311.41 (655.71x) | 519.67 (259.83x) | 15.97 (7.99x) | 2222.55 (1111.28x) |
| packed bool decode | 263.44 | 1532.64 (5.82x) | 2548.58 (9.67x) | 814.80 (3.09x) | 1597.24 (6.06x) |
| packed enum encode | 273.95 | 2705.81 (9.88x) | 1814.38 (6.62x) | 1088.17 (3.97x) | 2477.41 (9.04x) |
| packed enum decode | 152.84 | 1542.15 (10.09x) | 2884.56 (18.87x) | 695.61 (4.55x) | 2045.78 (13.39x) |
| large map encode | 3967.02 | 16563.50 (4.18x) | 9741.33 (2.46x) | 21603.40 (5.45x) | 201414.14 (50.77x) |
| shuffled large map deterministic binary encode | 27968.90 | — | — | 93626.00 (3.35x) | 429604.19 (15.36x) |
| large map decode | 24070.24 | 90706.18 (3.77x) | 89320.46 (3.71x) | 91352.00 (3.80x) | 265216.84 (11.02x) |
| LargeMap JSON stringify | 23456.07 | — | — | 90656.50 (3.86x) | 741841.62 (31.63x) |
| LargeMap JSON parse | 190242.30 | — | — | 755947.00 (3.97x) | 540615.01 (2.84x) |

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
- `examples/generated_required.zig` — proto2 required-field initialization gates
- `examples/generated_defaults.zig` — proto2 default values and has-bit semantics
- `examples/generated_extensions.zig` — generated proto2 extension accessors
- `examples/generated_identifiers.zig` — quoted generated identifiers for Zig keyword collisions
- `examples/generated_enum_alias.zig` — generated enum alias handling
- `examples/generated_json_names.zig` — explicit generated JSON names
- `examples/generated_messageset.zig` — generated proto2 MessageSet extensions
- `examples/generated_map_keys.zig` — generated non-string map keys
- `examples/proto2_extensions.zig` — proto2 extensions
- `examples/well_known_types.zig` — selected WKT helpers
- `examples/conformance.zig` — conformance-style dynamic conversion

## Validation commands

```sh
zig build check
zig build test
zig build examples
zig build build-codegen-smoke
zig build check-generated-examples
zig build conformance-smoke
python3 bench/summarize_compare.py --self-test
tools/run_conformance.sh
bench/run_compare.sh 2>&1 | tee /tmp/pbz-compare.log
python3 bench/summarize_compare.py /tmp/pbz-compare.log --fail-on-loss
```
