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

Latest accepted comparison (`/tmp/pbz-compare-always-print-json-final.log`,
summarized in `/tmp/pbz-summary-always-print-json-final.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Pivoted rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 26.18 | 127.85 (4.88x) | 70.07 (2.68x) | 125.20 (4.78x) | 867.70 (33.14x) |
| binary decode | 148.52 | 340.56 (2.29x) | 322.53 (2.17x) | 243.65 (1.64x) | 1200.03 (8.08x) |
| unknown fields count by number | 3.58 | — | — | 184.59 (51.56x) | — |
| deterministic binary encode | 78.75 | — | — | 155.75 (1.98x) | 1167.90 (14.83x) |
| scalarmix encode | 28.80 | 123.63 (4.29x) | 74.75 (2.60x) | 51.53 (1.79x) | 242.46 (8.42x) |
| scalarmix decode | 34.34 | 173.06 (5.04x) | 237.11 (6.90x) | 115.31 (3.36x) | 290.70 (8.47x) |
| textbytes encode | 15.98 | 107.38 (6.72x) | 51.87 (3.25x) | 120.31 (7.53x) | 180.54 (11.30x) |
| textbytes decode | 69.57 | 379.38 (5.45x) | 343.43 (4.94x) | 164.62 (2.37x) | 845.97 (12.16x) |
| largebytes encode | 31.98 | 2746.07 (85.87x) | 2717.89 (84.99x) | 3112.87 (97.34x) | 2821.99 (88.24x) |
| largebytes decode | 91.71 | 6207.11 (67.68x) | 5538.07 (60.39x) | 2970.72 (32.39x) | 34630.58 (377.61x) |
| presencemix encode | 22.25 | 56.23 (2.53x) | 45.22 (2.03x) | 73.67 (3.31x) | 290.72 (13.07x) |
| presencemix decode | 56.94 | 182.92 (3.21x) | 175.00 (3.07x) | 164.53 (2.89x) | 545.47 (9.58x) |
| complex encode | 70.49 | 177.56 (2.52x) | 151.38 (2.15x) | 165.94 (2.35x) | 915.66 (12.99x) |
| complex decode | 207.50 | 531.01 (2.56x) | 545.27 (2.63x) | 517.41 (2.49x) | 1706.77 (8.23x) |
| complex deterministic binary encode | 136.62 | — | — | 239.39 (1.75x) | 1133.11 (8.29x) |
| complex JSON stringify | 405.08 | — | — | 6000.21 (14.81x) | 7826.02 (19.32x) |
| complex JSON parse | 2368.63 | — | — | 15360.00 (6.48x) | 8870.74 (3.75x) |
| complex TextFormat format | 260.05 | — | — | 4661.82 (17.93x) | 6761.27 (26.00x) |
| complex TextFormat parse | 1852.68 | — | — | 8552.23 (4.62x) | 9634.65 (5.20x) |
| packed int32 encode | 621.91 | 3793.07 (6.10x) | 2828.82 (4.55x) | 1451.62 (2.33x) | 3647.72 (5.87x) |
| packed int32 decode | 768.91 | 2335.84 (3.04x) | 3847.89 (5.00x) | 1468.88 (1.91x) | 4624.44 (6.01x) |
| JSON stringify | 159.76 | — | — | 3654.05 (22.87x) | 2640.93 (16.53x) |
| AlwaysPrint JSON stringify | 60.04 | — | — | 3320.08 (55.30x) | 1666.03 (27.75x) |
| ProtoName JSON stringify | 315.85 | — | — | 6073.55 (19.23x) | 4776.03 (15.12x) |
| JSON parse | 2127.07 | — | — | 9455.11 (4.45x) | 5287.77 (2.49x) |
| MapKeySurrogate JSON parse | 525.34 | — | — | 4560.18 (8.68x) | 1342.07 (2.55x) |
| NullFields JSON parse | 638.35 | — | — | 2550.95 (4.00x) | 819.77 (1.28x) |
| OpenEnum JSON parse | 359.67 | — | — | 4526.95 (12.59x) | 508.00 (1.41x) |
| EnumName JSON parse | 358.19 | — | — | 4565.50 (12.75x) | 493.78 (1.38x) |
| ProtoName JSON parse | 641.91 | — | — | 4892.88 (7.62x) | 1463.38 (2.28x) |
| IntExponent JSON parse | 1949.40 | — | — | 8940.15 (4.59x) | 4561.56 (2.34x) |
| Any WKT JSON stringify | 202.25 | — | — | 2335.43 (11.55x) | 1010.31 (5.00x) |
| Any WKT JSON parse | 636.22 | — | — | 3673.90 (5.77x) | 1777.19 (2.79x) |
| Any Duration Escape WKT JSON parse | 624.66 | — | — | 3650.16 (5.84x) | 1923.18 (3.08x) |
| Any PlusDuration WKT JSON parse | 603.27 | — | — | 3626.63 (6.01x) | 1806.35 (2.99x) |
| Any ShortFractionDuration WKT JSON parse | 595.54 | — | — | 3777.31 (6.34x) | 1814.93 (3.05x) |
| Any MicroDuration WKT JSON stringify | 190.94 | — | — | 2577.50 (13.50x) | 1091.72 (5.72x) |
| Any MicroDuration WKT JSON parse | 604.56 | — | — | 3749.49 (6.20x) | 1799.76 (2.98x) |
| Any NanoDuration WKT JSON stringify | 187.77 | — | — | 2623.00 (13.97x) | 1180.22 (6.29x) |
| Any NanoDuration WKT JSON parse | 612.52 | — | — | 3819.75 (6.24x) | 1781.72 (2.91x) |
| Any NegativeDuration WKT JSON stringify | 196.40 | — | — | 2334.70 (11.89x) | 1115.89 (5.68x) |
| Any NegativeDuration WKT JSON parse | 607.98 | — | — | 3773.65 (6.21x) | 2047.56 (3.37x) |
| Any FractionalNegativeDuration WKT JSON stringify | 195.34 | — | — | 2338.81 (11.97x) | 1294.21 (6.63x) |
| Any FractionalNegativeDuration WKT JSON parse | 623.94 | — | — | 3728.74 (5.98x) | 2032.65 (3.26x) |
| Any MaxDuration WKT JSON stringify | 177.92 | — | — | 2134.18 (12.00x) | 1092.73 (6.14x) |
| Any MaxDuration WKT JSON parse | 546.56 | — | — | 3657.42 (6.69x) | 1888.05 (3.45x) |
| Any MinDuration WKT JSON stringify | 125.53 | — | — | 2118.65 (16.88x) | 1092.69 (8.70x) |
| Any MinDuration WKT JSON parse | 548.06 | — | — | 3743.03 (6.83x) | 1823.36 (3.33x) |
| Any ZeroDuration WKT JSON stringify | 109.18 | — | — | 1062.74 (9.73x) | 1034.81 (9.48x) |
| Any ZeroDuration WKT JSON parse | 478.41 | — | — | 2682.16 (5.61x) | 1936.34 (4.05x) |
| Any FieldMask WKT JSON stringify | 236.02 | — | — | 2118.91 (8.98x) | 1861.24 (7.89x) |
| Any FieldMask WKT JSON parse | 723.32 | — | — | 3819.26 (5.28x) | 2615.27 (3.62x) |
| Any FieldMask Escape WKT JSON parse | 1085.68 | — | — | 3979.20 (3.67x) | 3144.09 (2.90x) |
| Any EmptyFieldMask WKT JSON stringify | 200.74 | — | — | 1002.41 (4.99x) | 820.11 (4.09x) |
| Any EmptyFieldMask WKT JSON parse | 619.22 | — | — | 2551.17 (4.12x) | 1511.91 (2.44x) |
| Any Timestamp WKT JSON stringify | 295.58 | — | — | 2392.13 (8.09x) | 1119.83 (3.79x) |
| Any Timestamp WKT JSON parse | 654.53 | — | — | 3840.77 (5.87x) | 2048.19 (3.13x) |
| Any Timestamp Escape WKT JSON parse | 584.07 | — | — | 3855.03 (6.60x) | 2231.45 (3.82x) |
| Any ShortFraction Timestamp WKT JSON parse | 562.36 | — | — | 3892.07 (6.92x) | 2041.44 (3.63x) |
| Any Micro Timestamp WKT JSON stringify | 182.66 | — | — | 2353.42 (12.88x) | 1192.35 (6.53x) |
| Any Micro Timestamp WKT JSON parse | 574.03 | — | — | 3695.11 (6.44x) | 2017.46 (3.51x) |
| Any Nano Timestamp WKT JSON stringify | 181.08 | — | — | 2512.04 (13.87x) | 1309.85 (7.23x) |
| Any Nano Timestamp WKT JSON parse | 580.92 | — | — | 3800.70 (6.54x) | 2086.67 (3.59x) |
| Any Offset Timestamp WKT JSON parse | 730.24 | — | — | 4702.06 (6.44x) | 2112.32 (2.89x) |
| Any PreEpoch Timestamp WKT JSON stringify | 277.69 | — | — | 2450.68 (8.83x) | 1129.13 (4.07x) |
| Any PreEpoch Timestamp WKT JSON parse | 673.95 | — | — | 3847.88 (5.71x) | 1987.80 (2.95x) |
| Any Max Timestamp WKT JSON stringify | 239.99 | — | — | 2574.47 (10.73x) | 1207.65 (5.03x) |
| Any Max Timestamp WKT JSON parse | 622.43 | — | — | 3827.61 (6.15x) | 2030.01 (3.26x) |
| Any Min Timestamp WKT JSON stringify | 165.15 | — | — | 2379.28 (14.41x) | 1179.27 (7.14x) |
| Any Min Timestamp WKT JSON parse | 554.03 | — | — | 3608.03 (6.51x) | 1946.09 (3.51x) |
| Any Empty WKT JSON stringify | 87.31 | — | — | 959.95 (10.99x) | 613.94 (7.03x) |
| Any Empty WKT JSON parse | 333.63 | — | — | 2700.52 (8.09x) | 1687.43 (5.06x) |
| Any Struct WKT JSON stringify | 630.60 | — | — | 7193.75 (11.41x) | 7741.67 (12.28x) |
| Any Struct WKT JSON parse | 1776.67 | — | — | 13854.90 (7.80x) | 11523.40 (6.49x) |
| Any Struct Escape WKT JSON parse | 2545.43 | — | — | 21512.90 (8.45x) | 11239.72 (4.42x) |
| Any Struct NumberExponent WKT JSON parse | 1747.70 | — | — | 23084.60 (13.21x) | 11139.54 (6.37x) |
| Any Struct Surrogate WKT JSON parse | 756.43 | — | — | 10345.40 (13.68x) | 4318.67 (5.71x) |
| Any Struct KeySurrogate WKT JSON parse | 1247.29 | — | — | 9603.65 (7.70x) | 4383.96 (3.51x) |
| Any EmptyStruct WKT JSON stringify | 192.41 | — | — | 1564.61 (8.13x) | 1211.59 (6.30x) |
| Any EmptyStruct WKT JSON parse | 559.65 | — | — | 3447.92 (6.16x) | 1944.98 (3.48x) |
| Any Value WKT JSON stringify | 900.69 | — | — | 11272.60 (12.52x) | 8761.40 (9.73x) |
| Any Value WKT JSON parse | 2219.18 | — | — | 19502.20 (8.79x) | 11890.17 (5.36x) |
| Any Value Escape WKT JSON parse | 2148.84 | — | — | 20332.90 (9.46x) | 11154.76 (5.19x) |
| Any Value NumberExponent WKT JSON parse | 2272.16 | — | — | 20091.00 (8.84x) | 11082.43 (4.88x) |
| Any Value Surrogate WKT JSON parse | 992.49 | — | — | 11342.10 (11.43x) | 4376.46 (4.41x) |
| Any Value KeySurrogate WKT JSON parse | 945.92 | — | — | 11933.80 (12.62x) | 4855.54 (5.13x) |
| Any NullValue WKT JSON stringify | 169.07 | — | — | 3890.99 (23.01x) | 1011.26 (5.98x) |
| Any NullValue WKT JSON parse | 542.50 | — | — | 7136.65 (13.16x) | 2122.85 (3.91x) |
| Any StringScalarValue WKT JSON stringify | 207.73 | — | — | 3894.60 (18.75x) | 1092.02 (5.26x) |
| Any StringScalarValue WKT JSON parse | 600.35 | — | — | 6557.32 (10.92x) | 2192.43 (3.65x) |
| Any StringScalarValue Escape WKT JSON parse | 610.99 | — | — | 5834.99 (9.55x) | 2021.49 (3.31x) |
| Any StringScalarValue Surrogate WKT JSON parse | 646.94 | — | — | 5717.07 (8.84x) | 2156.18 (3.33x) |
| Any EmptyStringScalarValue WKT JSON stringify | 194.37 | — | — | 2970.40 (15.28x) | 1170.32 (6.02x) |
| Any EmptyStringScalarValue WKT JSON parse | 493.89 | — | — | 4636.24 (9.39x) | 1915.37 (3.88x) |
| Any NumberValue WKT JSON stringify | 179.54 | — | — | 3272.30 (18.23x) | 1397.13 (7.78x) |
| Any NumberValue WKT JSON parse | 502.15 | — | — | 6079.32 (12.11x) | 1977.46 (3.94x) |
| Any NumberValue Exponent WKT JSON parse | 504.27 | — | — | 6779.19 (13.44x) | 1981.81 (3.93x) |
| Any NegativeNumberValue WKT JSON stringify | 171.51 | — | — | 3761.49 (21.93x) | 1207.78 (7.04x) |
| Any NegativeNumberValue WKT JSON parse | 501.49 | — | — | 5435.11 (10.84x) | 2036.53 (4.06x) |
| Any ZeroNumberValue WKT JSON stringify | 143.19 | — | — | 4163.86 (29.08x) | 1058.08 (7.39x) |
| Any ZeroNumberValue WKT JSON parse | 498.48 | — | — | 4702.58 (9.43x) | 1979.22 (3.97x) |
| Any BoolScalarValue WKT JSON stringify | 204.74 | — | — | 2925.11 (14.29x) | 1157.05 (5.65x) |
| Any BoolScalarValue WKT JSON parse | 747.63 | — | — | 5090.03 (6.81x) | 2124.71 (2.84x) |
| Any FalseBoolScalarValue WKT JSON stringify | 207.25 | — | — | 3733.98 (18.02x) | 921.46 (4.45x) |
| Any FalseBoolScalarValue WKT JSON parse | 595.15 | — | — | 5657.82 (9.51x) | 1987.92 (3.34x) |
| Any ListKindValue WKT JSON stringify | 669.53 | — | — | 10547.40 (15.75x) | 5955.81 (8.90x) |
| Any ListKindValue WKT JSON parse | 1390.88 | — | — | 17654.00 (12.69x) | 8742.81 (6.29x) |
| Any ListKindValue Escape WKT JSON parse | 1408.04 | — | — | 14176.50 (10.07x) | 9525.27 (6.76x) |
| Any ListKindValue Surrogate WKT JSON parse | 720.92 | — | — | 6442.45 (8.94x) | 3511.80 (4.87x) |
| Any EmptyStructKindValue WKT JSON stringify | 237.97 | — | — | 4150.13 (17.44x) | 1770.38 (7.44x) |
| Any EmptyStructKindValue WKT JSON parse | 827.01 | — | — | 9237.96 (11.17x) | 2314.96 (2.80x) |
| Any EmptyListKindValue WKT JSON stringify | 235.66 | — | — | 4564.63 (19.37x) | 1439.10 (6.11x) |
| Any EmptyListKindValue WKT JSON parse | 633.72 | — | — | 5498.84 (8.68x) | 2144.92 (3.38x) |
| Any DoubleValue WKT JSON stringify | 293.17 | — | — | 2233.45 (7.62x) | 822.92 (2.81x) |
| Any DoubleValue WKT JSON parse | 674.05 | — | — | 3767.32 (5.59x) | 1786.14 (2.65x) |
| Any DoubleValue String WKT JSON parse | 544.57 | — | — | 3667.71 (6.74x) | 1908.80 (3.51x) |
| Any DoubleValue Exponent WKT JSON parse | 536.16 | — | — | 3729.60 (6.96x) | 1781.81 (3.32x) |
| Any NegativeDoubleValue WKT JSON stringify | 190.63 | — | — | 2200.11 (11.54x) | 907.83 (4.76x) |
| Any NegativeDoubleValue WKT JSON parse | 521.42 | — | — | 3438.17 (6.59x) | 1806.13 (3.46x) |
| Any ZeroDoubleValue WKT JSON stringify | 163.71 | — | — | 1022.33 (6.24x) | 788.47 (4.82x) |
| Any ZeroDoubleValue WKT JSON parse | 515.06 | — | — | 2928.15 (5.69x) | 1472.19 (2.86x) |
| Any DoubleValue NaN WKT JSON stringify | 158.80 | — | — | 2174.25 (13.69x) | 702.96 (4.43x) |
| Any DoubleValue NaN WKT JSON parse | 513.10 | — | — | 3359.35 (6.55x) | 1926.18 (3.75x) |
| Any DoubleValue Infinity WKT JSON stringify | 244.27 | — | — | 2083.47 (8.53x) | 735.15 (3.01x) |
| Any DoubleValue Infinity WKT JSON parse | 811.34 | — | — | 3380.09 (4.17x) | 1704.12 (2.10x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 245.64 | — | — | 1968.34 (8.01x) | 812.84 (3.31x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 650.27 | — | — | 3494.18 (5.37x) | 1744.24 (2.68x) |
| Any FloatValue WKT JSON stringify | 283.62 | — | — | 2133.96 (7.52x) | 822.63 (2.90x) |
| Any FloatValue WKT JSON parse | 650.20 | — | — | 3425.20 (5.27x) | 1865.98 (2.87x) |
| Any FloatValue String WKT JSON parse | 676.24 | — | — | 3391.83 (5.02x) | 1652.16 (2.44x) |
| Any FloatValue Exponent WKT JSON parse | 666.32 | — | — | 3487.51 (5.23x) | 1797.03 (2.70x) |
| Any NegativeFloatValue WKT JSON stringify | 282.39 | — | — | 2437.35 (8.63x) | 786.41 (2.78x) |
| Any NegativeFloatValue WKT JSON parse | 618.82 | — | — | 3834.96 (6.20x) | 1687.29 (2.73x) |
| Any ZeroFloatValue WKT JSON stringify | 217.91 | — | — | 1271.37 (5.83x) | 792.98 (3.64x) |
| Any ZeroFloatValue WKT JSON parse | 609.04 | — | — | 2675.92 (4.39x) | 1694.19 (2.78x) |
| Any FloatValue NaN WKT JSON stringify | 211.29 | — | — | 1943.01 (9.20x) | 804.41 (3.81x) |
| Any FloatValue NaN WKT JSON parse | 598.28 | — | — | 3350.61 (5.60x) | 1864.46 (3.12x) |
| Any FloatValue Infinity WKT JSON stringify | 218.05 | — | — | 1935.75 (8.88x) | 734.29 (3.37x) |
| Any FloatValue Infinity WKT JSON parse | 621.03 | — | — | 3064.93 (4.94x) | 1898.35 (3.06x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 229.84 | — | — | 1869.81 (8.14x) | 751.16 (3.27x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 645.72 | — | — | 3357.36 (5.20x) | 1892.64 (2.93x) |
| Any Int64Value WKT JSON stringify | 230.84 | — | — | 1994.60 (8.64x) | 1105.97 (4.79x) |
| Any Int64Value WKT JSON parse | 707.96 | — | — | 3508.12 (4.96x) | 2068.33 (2.92x) |
| Any Int64Value Number WKT JSON parse | 696.75 | — | — | 3446.34 (4.95x) | 1771.45 (2.54x) |
| Any Int64Value Exponent WKT JSON parse | 562.31 | — | — | 3418.47 (6.08x) | 1691.39 (3.01x) |
| Any ZeroInt64Value WKT JSON stringify | 166.98 | — | — | 1194.06 (7.15x) | 784.69 (4.70x) |
| Any ZeroInt64Value WKT JSON parse | 536.08 | — | — | 3520.09 (6.57x) | 1880.12 (3.51x) |
| Any NegativeInt64Value WKT JSON stringify | 173.92 | — | — | 2447.69 (14.07x) | 957.43 (5.51x) |
| Any NegativeInt64Value WKT JSON parse | 559.61 | — | — | 4470.70 (7.99x) | 2248.69 (4.02x) |
| Any MinInt64Value WKT JSON stringify | 178.70 | — | — | 2032.35 (11.37x) | 1073.06 (6.00x) |
| Any MinInt64Value WKT JSON parse | 938.16 | — | — | 3721.02 (3.97x) | 2059.03 (2.19x) |
| Any MaxInt64Value WKT JSON stringify | 280.76 | — | — | 2105.75 (7.50x) | 947.36 (3.37x) |
| Any MaxInt64Value WKT JSON parse | 680.50 | — | — | 3570.32 (5.25x) | 1909.97 (2.81x) |
| Any UInt64Value WKT JSON stringify | 227.71 | — | — | 1865.28 (8.19x) | 1058.32 (4.65x) |
| Any UInt64Value WKT JSON parse | 657.49 | — | — | 3749.52 (5.70x) | 1933.98 (2.94x) |
| Any UInt64Value Number WKT JSON parse | 563.10 | — | — | 3636.97 (6.46x) | 1849.09 (3.28x) |
| Any UInt64Value Exponent WKT JSON parse | 547.35 | — | — | 3624.33 (6.62x) | 1926.24 (3.52x) |
| Any ZeroUInt64Value WKT JSON stringify | 173.01 | — | — | 1235.78 (7.14x) | 902.03 (5.21x) |
| Any ZeroUInt64Value WKT JSON parse | 533.46 | — | — | 2886.82 (5.41x) | 1825.68 (3.42x) |
| Any MaxUInt64Value WKT JSON stringify | 186.90 | — | — | 1931.59 (10.33x) | 1061.48 (5.68x) |
| Any MaxUInt64Value WKT JSON parse | 555.00 | — | — | 3658.70 (6.59x) | 2114.52 (3.81x) |
| Any Int32Value WKT JSON stringify | 172.08 | — | — | 2087.57 (12.13x) | 794.05 (4.61x) |
| Any Int32Value WKT JSON parse | 668.61 | — | — | 3280.27 (4.91x) | 1633.27 (2.44x) |
| Any Int32Value String WKT JSON parse | 853.99 | — | — | 3561.77 (4.17x) | 1822.55 (2.13x) |
| Any Int32Value Exponent WKT JSON parse | 654.54 | — | — | 3473.82 (5.31x) | 1850.29 (2.83x) |
| Any ZeroInt32Value WKT JSON stringify | 233.69 | — | — | 1122.57 (4.80x) | 729.39 (3.12x) |
| Any ZeroInt32Value WKT JSON parse | 564.84 | — | — | 2882.77 (5.10x) | 1828.73 (3.24x) |
| Any NegativeInt32Value WKT JSON stringify | 177.67 | — | — | 1959.16 (11.03x) | 748.85 (4.21x) |
| Any NegativeInt32Value WKT JSON parse | 650.64 | — | — | 3422.35 (5.26x) | 1769.81 (2.72x) |
| Any MinInt32Value WKT JSON stringify | 232.45 | — | — | 2308.18 (9.93x) | 758.51 (3.26x) |
| Any MinInt32Value WKT JSON parse | 557.62 | — | — | 4275.41 (7.67x) | 1741.07 (3.12x) |
| Any MaxInt32Value WKT JSON stringify | 180.67 | — | — | 1936.04 (10.72x) | 831.13 (4.60x) |
| Any MaxInt32Value WKT JSON parse | 556.84 | — | — | 3652.43 (6.56x) | 1811.17 (3.25x) |
| Any UInt32Value WKT JSON stringify | 176.73 | — | — | 2078.37 (11.76x) | 840.26 (4.75x) |
| Any UInt32Value WKT JSON parse | 662.06 | — | — | 3487.26 (5.27x) | 1881.48 (2.84x) |
| Any UInt32Value String WKT JSON parse | 865.25 | — | — | 3368.39 (3.89x) | 1960.12 (2.27x) |
| Any UInt32Value Exponent WKT JSON parse | 759.51 | — | — | 3544.30 (4.67x) | 1770.33 (2.33x) |
| Any ZeroUInt32Value WKT JSON stringify | 175.39 | — | — | 1100.54 (6.27x) | 694.03 (3.96x) |
| Any ZeroUInt32Value WKT JSON parse | 535.10 | — | — | 2639.97 (4.93x) | 1552.69 (2.90x) |
| Any MaxUInt32Value WKT JSON stringify | 177.98 | — | — | 1916.93 (10.77x) | 800.02 (4.49x) |
| Any MaxUInt32Value WKT JSON parse | 540.61 | — | — | 3373.94 (6.24x) | 1690.70 (3.13x) |
| Any BoolValue WKT JSON stringify | 168.26 | — | — | 1922.66 (11.43x) | 799.76 (4.75x) |
| Any BoolValue WKT JSON parse | 482.58 | — | — | 3252.85 (6.74x) | 1638.72 (3.40x) |
| Any FalseBoolValue WKT JSON stringify | 169.21 | — | — | 957.66 (5.66x) | 731.67 (4.32x) |
| Any FalseBoolValue WKT JSON parse | 480.59 | — | — | 2595.34 (5.40x) | 1578.35 (3.28x) |
| Any StringValue WKT JSON stringify | 259.29 | — | — | 1989.53 (7.67x) | 869.52 (3.35x) |
| Any StringValue WKT JSON parse | 649.16 | — | — | 3369.37 (5.19x) | 1730.19 (2.67x) |
| Any StringValue Escape WKT JSON parse | 644.98 | — | — | 4029.85 (6.25x) | 1913.82 (2.97x) |
| Any StringValue Surrogate WKT JSON parse | 654.70 | — | — | 3361.26 (5.13x) | 2092.14 (3.20x) |
| Any EmptyStringValue WKT JSON stringify | 244.85 | — | — | 1033.03 (4.22x) | 825.55 (3.37x) |
| Any EmptyStringValue WKT JSON parse | 629.69 | — | — | 2711.86 (4.31x) | 1708.67 (2.71x) |
| Any BytesValue WKT JSON stringify | 253.46 | — | — | 1971.35 (7.78x) | 837.41 (3.30x) |
| Any BytesValue WKT JSON parse | 674.71 | — | — | 3437.60 (5.09x) | 1761.21 (2.61x) |
| Any BytesValue URL WKT JSON parse | 696.68 | — | — | 3374.33 (4.84x) | 1699.83 (2.44x) |
| Any BytesValue StandardBase64 WKT JSON parse | 635.46 | — | — | 3336.34 (5.25x) | 1692.94 (2.66x) |
| Any BytesValue Unpadded WKT JSON parse | 580.11 | — | — | 3162.22 (5.45x) | 1670.56 (2.88x) |
| Any EmptyBytesValue WKT JSON stringify | 183.25 | — | — | 985.81 (5.38x) | 763.03 (4.16x) |
| Any EmptyBytesValue WKT JSON parse | 623.44 | — | — | 2560.93 (4.11x) | 1512.47 (2.43x) |
| Nested Any WKT JSON stringify | 479.46 | — | — | 2962.66 (6.18x) | 1781.33 (3.72x) |
| Nested Any WKT JSON parse | 1265.14 | — | — | 5490.43 (4.34x) | 3281.29 (2.59x) |
| Duration JSON stringify | 59.46 | — | — | 1277.02 (21.48x) | 330.48 (5.56x) |
| Duration JSON parse | 19.94 | — | — | 1856.66 (93.11x) | 353.92 (17.75x) |
| Duration Escape JSON parse | 60.96 | — | — | 1884.10 (30.91x) | 458.87 (7.53x) |
| PlusDuration JSON parse | 29.51 | — | — | 1848.58 (62.64x) | 422.27 (14.31x) |
| ShortFractionDuration JSON parse | 24.78 | — | — | 1999.85 (80.70x) | 368.12 (14.86x) |
| MicroDuration JSON stringify | 90.32 | — | — | 1125.68 (12.46x) | 386.27 (4.28x) |
| MicroDuration JSON parse | 35.35 | — | — | 1833.26 (51.86x) | 413.54 (11.70x) |
| NanoDuration JSON stringify | 83.84 | — | — | 1141.02 (13.61x) | 392.90 (4.69x) |
| NanoDuration JSON parse | 41.67 | — | — | 2220.44 (53.29x) | 432.97 (10.39x) |
| NegativeDuration JSON stringify | 84.20 | — | — | 1382.25 (16.42x) | 415.15 (4.93x) |
| NegativeDuration JSON parse | 20.30 | — | — | 1900.01 (93.60x) | 420.06 (20.69x) |
| FractionalNegativeDuration JSON stringify | 60.11 | — | — | 1219.00 (20.28x) | 422.18 (7.02x) |
| FractionalNegativeDuration JSON parse | 21.92 | — | — | 1799.40 (82.09x) | 352.38 (16.08x) |
| MaxDuration JSON stringify | 51.53 | — | — | 1028.34 (19.96x) | 403.23 (7.83x) |
| MaxDuration JSON parse | 33.52 | — | — | 1777.00 (53.01x) | 418.47 (12.48x) |
| MinDuration JSON stringify | 51.31 | — | — | 1046.46 (20.39x) | 419.46 (8.18x) |
| MinDuration JSON parse | 31.46 | — | — | 1558.19 (49.53x) | 419.23 (13.33x) |
| ZeroDuration JSON stringify | 44.91 | — | — | 988.05 (22.00x) | 351.49 (7.83x) |
| ZeroDuration JSON parse | 16.31 | — | — | 1711.38 (104.93x) | 284.58 (17.45x) |
| FieldMask JSON stringify | 102.20 | — | — | 1012.43 (9.91x) | 710.79 (6.95x) |
| FieldMask JSON parse | 195.63 | — | — | 2220.15 (11.35x) | 1070.11 (5.47x) |
| FieldMask Escape JSON parse | 273.62 | — | — | 2066.81 (7.55x) | 1089.50 (3.98x) |
| EmptyFieldMask JSON stringify | 48.78 | — | — | 764.58 (15.67x) | 209.23 (4.29x) |
| EmptyFieldMask JSON parse | 8.60 | — | — | 1136.62 (132.17x) | 182.27 (21.19x) |
| Timestamp JSON stringify | 143.38 | — | — | 1347.33 (9.40x) | 443.14 (3.09x) |
| Timestamp JSON parse | 75.88 | — | — | 1843.36 (24.29x) | 438.18 (5.77x) |
| Timestamp Escape JSON parse | 149.24 | — | — | 1878.45 (12.59x) | 538.14 (3.61x) |
| ShortFraction Timestamp JSON parse | 69.73 | — | — | 1949.57 (27.96x) | 469.85 (6.74x) |
| Micro Timestamp JSON stringify | 138.78 | — | — | 1506.17 (10.85x) | 433.50 (3.12x) |
| Micro Timestamp JSON parse | 75.67 | — | — | 1827.84 (24.16x) | 452.43 (5.98x) |
| Nano Timestamp JSON stringify | 138.97 | — | — | 1533.55 (11.04x) | 472.47 (3.40x) |
| Nano Timestamp JSON parse | 80.94 | — | — | 1991.58 (24.61x) | 465.96 (5.76x) |
| Offset Timestamp JSON parse | 83.41 | — | — | 1907.77 (22.87x) | 468.99 (5.62x) |
| PreEpoch Timestamp JSON stringify | 90.65 | — | — | 1428.51 (15.76x) | 434.05 (4.79x) |
| PreEpoch Timestamp JSON parse | 66.89 | — | — | 1837.35 (27.47x) | 435.16 (6.51x) |
| Max Timestamp JSON stringify | 109.09 | — | — | 1487.66 (13.64x) | 455.16 (4.17x) |
| Max Timestamp JSON parse | 83.47 | — | — | 1867.72 (22.38x) | 470.19 (5.63x) |
| Min Timestamp JSON stringify | 124.94 | — | — | 1190.10 (9.53x) | 409.55 (3.28x) |
| Min Timestamp JSON parse | 63.24 | — | — | 1895.98 (29.98x) | 438.72 (6.94x) |
| Empty JSON stringify | 23.66 | — | — | 518.49 (21.91x) | 92.75 (3.92x) |
| Empty JSON parse | 74.99 | — | — | 881.79 (11.76x) | 201.67 (2.69x) |
| Struct JSON stringify | 281.74 | — | — | 7602.36 (26.98x) | 3746.60 (13.30x) |
| Struct JSON parse | 958.26 | — | — | 13867.30 (14.47x) | 5887.08 (6.14x) |
| Struct Escape JSON parse | 1017.91 | — | — | 15545.80 (15.27x) | 6053.67 (5.95x) |
| Struct NumberExponent JSON parse | 1033.49 | — | — | 13768.90 (13.32x) | 6156.84 (5.96x) |
| Struct Surrogate JSON parse | 414.73 | — | — | 6424.55 (15.49x) | 1647.61 (3.97x) |
| Struct KeySurrogate JSON parse | 414.37 | — | — | 5924.80 (14.30x) | 1695.53 (4.09x) |
| EmptyStruct JSON stringify | 46.57 | — | — | 768.91 (16.51x) | 371.84 (7.98x) |
| EmptyStruct JSON parse | 90.87 | — | — | 2676.26 (29.45x) | 416.67 (4.59x) |
| Value JSON stringify | 304.18 | — | — | 8486.50 (27.90x) | 4027.77 (13.24x) |
| Value JSON parse | 914.60 | — | — | 15369.30 (16.80x) | 5854.78 (6.40x) |
| Value Escape JSON parse | 933.55 | — | — | 16908.10 (18.11x) | 6086.95 (6.52x) |
| Value NumberExponent JSON parse | 1357.81 | — | — | 16020.80 (11.80x) | 6657.05 (4.90x) |
| Value Surrogate JSON parse | 423.43 | — | — | 8351.04 (19.72x) | 1966.85 (4.65x) |
| Value KeySurrogate JSON parse | 427.86 | — | — | 9239.58 (21.59x) | 2012.03 (4.70x) |
| NullValue JSON stringify | 46.22 | — | — | 1640.36 (35.49x) | 252.05 (5.45x) |
| NullValue JSON parse | 60.83 | — | — | 3325.53 (54.67x) | 376.54 (6.19x) |
| StringScalarValue JSON stringify | 60.01 | — | — | 1731.97 (28.86x) | 275.22 (4.59x) |
| StringScalarValue JSON parse | 132.40 | — | — | 2655.13 (20.05x) | 416.00 (3.14x) |
| StringScalarValue Escape JSON parse | 144.26 | — | — | 2720.18 (18.86x) | 541.41 (3.75x) |
| StringScalarValue Surrogate JSON parse | 150.60 | — | — | 2925.35 (19.42x) | 513.40 (3.41x) |
| EmptyStringScalarValue JSON stringify | 55.14 | — | — | 1693.52 (30.71x) | 319.04 (5.79x) |
| EmptyStringScalarValue JSON parse | 73.00 | — | — | 2564.72 (35.13x) | 357.77 (4.90x) |
| NumberValue JSON stringify | 122.22 | — | — | 2162.87 (17.70x) | 354.60 (2.90x) |
| NumberValue JSON parse | 126.78 | — | — | 2633.78 (20.77x) | 442.01 (3.49x) |
| NumberValue Exponent JSON parse | 132.21 | — | — | 2915.27 (22.05x) | 458.62 (3.47x) |
| NegativeNumberValue JSON stringify | 122.78 | — | — | 1930.65 (15.72x) | 360.07 (2.93x) |
| NegativeNumberValue JSON parse | 127.12 | — | — | 2666.32 (20.97x) | 374.10 (2.94x) |
| ZeroNumberValue JSON stringify | 69.05 | — | — | 1896.26 (27.46x) | 301.00 (4.36x) |
| ZeroNumberValue JSON parse | 130.23 | — | — | 2536.97 (19.48x) | 408.06 (3.13x) |
| BoolScalarValue JSON stringify | 45.68 | — | — | 1641.22 (35.93x) | 228.87 (5.01x) |
| BoolScalarValue JSON parse | 56.51 | — | — | 2627.54 (46.50x) | 311.87 (5.52x) |
| FalseBoolScalarValue JSON stringify | 44.36 | — | — | 2102.12 (47.39x) | 297.68 (6.71x) |
| FalseBoolScalarValue JSON parse | 63.59 | — | — | 3003.39 (47.23x) | 352.92 (5.55x) |
| ListKindValue JSON stringify | 223.05 | — | — | 7921.05 (35.51x) | 2605.99 (11.68x) |
| ListKindValue JSON parse | 772.44 | — | — | 14062.50 (18.21x) | 5200.34 (6.73x) |
| ListKindValue Escape JSON parse | 802.15 | — | — | 13325.50 (16.61x) | 5596.64 (6.98x) |
| ListKindValue Surrogate JSON parse | 359.72 | — | — | 6834.83 (19.00x) | 1535.36 (4.27x) |
| EmptyStructKindValue JSON stringify | 46.84 | — | — | 2571.42 (54.90x) | 546.53 (11.67x) |
| EmptyStructKindValue JSON parse | 107.11 | — | — | 4903.80 (45.78x) | 829.65 (7.75x) |
| EmptyListKindValue JSON stringify | 44.36 | — | — | 2629.26 (59.27x) | 408.31 (9.20x) |
| EmptyListKindValue JSON parse | 145.46 | — | — | 4973.93 (34.19x) | 578.99 (3.98x) |
| ListValue JSON stringify | 210.31 | — | — | 6077.05 (28.90x) | 2644.89 (12.58x) |
| ListValue JSON parse | 769.04 | — | — | 10758.40 (13.99x) | 4779.91 (6.22x) |
| ListValue Escape JSON parse | 825.23 | — | — | 12082.80 (14.64x) | 4368.20 (5.29x) |
| ListValue Surrogate JSON parse | 361.75 | — | — | 3953.94 (10.93x) | 1053.80 (2.91x) |
| EmptyListValue JSON stringify | 45.12 | — | — | 1101.66 (24.42x) | 179.56 (3.98x) |
| EmptyListValue JSON parse | 144.59 | — | — | 3049.13 (21.09x) | 376.08 (2.60x) |
| DoubleValue JSON stringify | 104.97 | — | — | 1072.85 (10.22x) | 201.50 (1.92x) |
| DoubleValue JSON parse | 123.61 | — | — | 1545.82 (12.51x) | 361.32 (2.92x) |
| DoubleValue String JSON parse | 118.35 | — | — | 1539.98 (13.01x) | 423.60 (3.58x) |
| DoubleValue Exponent JSON parse | 129.83 | — | — | 1608.85 (12.39x) | 299.60 (2.31x) |
| NegativeDoubleValue JSON stringify | 104.99 | — | — | 1126.10 (10.73x) | 222.53 (2.12x) |
| NegativeDoubleValue JSON parse | 123.85 | — | — | 1622.25 (13.10x) | 261.69 (2.11x) |
| ZeroDoubleValue JSON stringify | 57.71 | — | — | 1080.89 (18.73x) | 153.50 (2.66x) |
| ZeroDoubleValue JSON parse | 126.30 | — | — | 1494.39 (11.83x) | 246.73 (1.95x) |
| DoubleValue NaN JSON stringify | 58.00 | — | — | 699.60 (12.06x) | 140.45 (2.42x) |
| DoubleValue NaN JSON parse | 109.36 | — | — | 1424.89 (13.03x) | 248.33 (2.27x) |
| DoubleValue Infinity JSON stringify | 60.69 | — | — | 778.97 (12.84x) | 140.70 (2.32x) |
| DoubleValue Infinity JSON parse | 112.93 | — | — | 1162.21 (10.29x) | 277.97 (2.46x) |
| DoubleValue NegativeInfinity JSON stringify | 60.68 | — | — | 675.35 (11.13x) | 119.73 (1.97x) |
| DoubleValue NegativeInfinity JSON parse | 112.25 | — | — | 1477.29 (13.16x) | 250.50 (2.23x) |
| FloatValue JSON stringify | 105.36 | — | — | 1019.47 (9.68x) | 197.84 (1.88x) |
| FloatValue JSON parse | 118.28 | — | — | 1611.46 (13.62x) | 308.62 (2.61x) |
| FloatValue String JSON parse | 116.74 | — | — | 1474.41 (12.63x) | 373.67 (3.20x) |
| FloatValue Exponent JSON parse | 123.67 | — | — | 1607.59 (13.00x) | 308.24 (2.49x) |
| NegativeFloatValue JSON stringify | 104.83 | — | — | 1221.42 (11.65x) | 187.83 (1.79x) |
| NegativeFloatValue JSON parse | 118.95 | — | — | 1672.36 (14.06x) | 284.79 (2.39x) |
| ZeroFloatValue JSON stringify | 56.18 | — | — | 942.67 (16.78x) | 133.81 (2.38x) |
| ZeroFloatValue JSON parse | 120.37 | — | — | 1734.41 (14.41x) | 258.22 (2.15x) |
| FloatValue NaN JSON stringify | 55.12 | — | — | 643.82 (11.68x) | 130.11 (2.36x) |
| FloatValue NaN JSON parse | 105.74 | — | — | 1431.62 (13.54x) | 287.47 (2.72x) |
| FloatValue Infinity JSON stringify | 59.30 | — | — | 736.57 (12.42x) | 124.51 (2.10x) |
| FloatValue Infinity JSON parse | 109.33 | — | — | 1311.70 (12.00x) | 280.15 (2.56x) |
| FloatValue NegativeInfinity JSON stringify | 60.75 | — | — | 755.00 (12.43x) | 143.60 (2.36x) |
| FloatValue NegativeInfinity JSON parse | 113.54 | — | — | 1650.18 (14.53x) | 280.11 (2.47x) |
| Int64Value JSON stringify | 57.14 | — | — | 688.88 (12.06x) | 282.12 (4.94x) |
| Int64Value JSON parse | 143.57 | — | — | 1547.85 (10.78x) | 475.05 (3.31x) |
| Int64Value Number JSON parse | 157.00 | — | — | 1687.32 (10.75x) | 398.34 (2.54x) |
| Int64Value Exponent JSON parse | 127.01 | — | — | 1706.32 (13.43x) | 366.76 (2.89x) |
| ZeroInt64Value JSON stringify | 45.79 | — | — | 1073.03 (23.43x) | 191.29 (4.18x) |
| ZeroInt64Value JSON parse | 106.63 | — | — | 1965.23 (18.43x) | 347.01 (3.25x) |
| NegativeInt64Value JSON stringify | 56.96 | — | — | 1116.76 (19.61x) | 273.22 (4.80x) |
| NegativeInt64Value JSON parse | 145.79 | — | — | 2098.12 (14.39x) | 507.28 (3.48x) |
| MinInt64Value JSON stringify | 61.05 | — | — | 748.77 (12.26x) | 280.99 (4.60x) |
| MinInt64Value JSON parse | 155.64 | — | — | 1833.14 (11.78x) | 477.32 (3.07x) |
| MaxInt64Value JSON stringify | 61.07 | — | — | 756.37 (12.39x) | 273.28 (4.47x) |
| MaxInt64Value JSON parse | 157.79 | — | — | 1527.60 (9.68x) | 510.39 (3.23x) |
| UInt64Value JSON stringify | 57.85 | — | — | 917.18 (15.85x) | 269.54 (4.66x) |
| UInt64Value JSON parse | 149.52 | — | — | 1607.95 (10.75x) | 527.01 (3.52x) |
| UInt64Value Number JSON parse | 160.87 | — | — | 1652.89 (10.27x) | 370.06 (2.30x) |
| UInt64Value Exponent JSON parse | 131.17 | — | — | 1628.58 (12.42x) | 385.36 (2.94x) |
| ZeroUInt64Value JSON stringify | 47.47 | — | — | 1024.97 (21.59x) | 189.63 (3.99x) |
| ZeroUInt64Value JSON parse | 110.87 | — | — | 1215.29 (10.96x) | 338.64 (3.05x) |
| MaxUInt64Value JSON stringify | 63.83 | — | — | 860.83 (13.49x) | 286.61 (4.49x) |
| MaxUInt64Value JSON parse | 168.11 | — | — | 1610.37 (9.58x) | 454.79 (2.71x) |
| Int32Value JSON stringify | 53.38 | — | — | 762.04 (14.28x) | 151.67 (2.84x) |
| Int32Value JSON parse | 147.41 | — | — | 1504.45 (10.21x) | 452.27 (3.07x) |
| Int32Value String JSON parse | 141.07 | — | — | 1480.85 (10.50x) | 406.91 (2.88x) |
| Int32Value Exponent JSON parse | 147.75 | — | — | 1609.09 (10.89x) | 360.36 (2.44x) |
| ZeroInt32Value JSON stringify | 52.93 | — | — | 800.07 (15.12x) | 131.29 (2.48x) |
| ZeroInt32Value JSON parse | 131.31 | — | — | 1518.85 (11.57x) | 310.13 (2.36x) |
| NegativeInt32Value JSON stringify | 47.91 | — | — | 1098.87 (22.94x) | 136.46 (2.85x) |
| NegativeInt32Value JSON parse | 134.90 | — | — | 1624.34 (12.04x) | 328.92 (2.44x) |
| MinInt32Value JSON stringify | 48.48 | — | — | 865.16 (17.85x) | 151.97 (3.13x) |
| MinInt32Value JSON parse | 141.22 | — | — | 1476.42 (10.45x) | 357.21 (2.53x) |
| MaxInt32Value JSON stringify | 48.82 | — | — | 873.59 (17.89x) | 133.06 (2.73x) |
| MaxInt32Value JSON parse | 141.93 | — | — | 1573.41 (11.09x) | 371.16 (2.62x) |
| UInt32Value JSON stringify | 47.97 | — | — | 770.17 (16.06x) | 154.60 (3.22x) |
| UInt32Value JSON parse | 135.70 | — | — | 1564.98 (11.53x) | 345.30 (2.54x) |
| UInt32Value String JSON parse | 140.12 | — | — | 1485.93 (10.60x) | 438.70 (3.13x) |
| UInt32Value Exponent JSON parse | 138.60 | — | — | 1488.44 (10.74x) | 343.81 (2.48x) |
| ZeroUInt32Value JSON stringify | 48.23 | — | — | 671.34 (13.92x) | 139.21 (2.89x) |
| ZeroUInt32Value JSON parse | 127.91 | — | — | 1383.05 (10.81x) | 299.44 (2.34x) |
| MaxUInt32Value JSON stringify | 46.98 | — | — | 766.61 (16.32x) | 151.25 (3.22x) |
| MaxUInt32Value JSON parse | 139.84 | — | — | 1446.86 (10.35x) | 328.63 (2.35x) |
| BoolValue JSON stringify | 45.03 | — | — | 950.18 (21.10x) | 128.03 (2.84x) |
| BoolValue JSON parse | 68.45 | — | — | 1499.98 (21.91x) | 234.85 (3.43x) |
| FalseBoolValue JSON stringify | 45.13 | — | — | 628.77 (13.93x) | 136.71 (3.03x) |
| FalseBoolValue JSON parse | 68.93 | — | — | 1339.18 (19.43x) | 245.36 (3.56x) |
| StringValue JSON stringify | 51.88 | — | — | 706.26 (13.61x) | 168.20 (3.24x) |
| StringValue JSON parse | 122.18 | — | — | 1452.67 (11.89x) | 325.79 (2.67x) |
| StringValue Escape JSON parse | 132.03 | — | — | 1550.02 (11.74x) | 362.36 (2.74x) |
| StringValue Surrogate JSON parse | 127.10 | — | — | 1548.11 (12.18x) | 359.94 (2.83x) |
| EmptyStringValue JSON stringify | 48.83 | — | — | 883.52 (18.09x) | 200.53 (4.11x) |
| EmptyStringValue JSON parse | 66.31 | — | — | 1393.13 (21.01x) | 243.02 (3.66x) |
| BytesValue JSON stringify | 49.01 | — | — | 846.89 (17.28x) | 215.00 (4.39x) |
| BytesValue JSON parse | 131.92 | — | — | 1482.61 (11.24x) | 333.02 (2.52x) |
| BytesValue URL JSON parse | 146.92 | — | — | 1493.09 (10.16x) | 404.38 (2.75x) |
| BytesValue StandardBase64 JSON parse | 161.57 | — | — | 1508.96 (9.34x) | 324.94 (2.01x) |
| BytesValue Unpadded JSON parse | 161.02 | — | — | 1376.27 (8.55x) | 320.83 (1.99x) |
| EmptyBytesValue JSON stringify | 55.19 | — | — | 639.07 (11.58x) | 187.17 (3.39x) |
| EmptyBytesValue JSON parse | 91.23 | — | — | 1278.28 (14.01x) | 327.20 (3.59x) |
| TextFormat format | 313.01 | — | — | 3119.02 (9.96x) | 3176.84 (10.15x) |
| TextFormat parse | 1194.92 | — | — | 5906.45 (4.94x) | 7955.92 (6.66x) |
| packed fixed32 encode | 2.63 | 555.10 (211.06x) | 667.10 (253.65x) | 95.71 (36.39x) | 406.36 (154.51x) |
| packed fixed32 decode | 7.60 | 1160.75 (152.73x) | 2296.17 (302.13x) | 100.17 (13.18x) | 2264.88 (298.01x) |
| packed fixed64 encode | 2.00 | 573.72 (286.86x) | 565.48 (282.74x) | 82.08 (41.04x) | 392.21 (196.10x) |
| packed fixed64 decode | 4.54 | 1105.96 (243.60x) | 8410.16 (1852.46x) | 92.96 (20.48x) | 3638.76 (801.49x) |
| packed sfixed32 encode | 2.42 | 717.04 (296.30x) | 546.12 (225.67x) | 90.52 (37.40x) | 549.78 (227.18x) |
| packed sfixed32 decode | 7.93 | 1363.86 (171.99x) | 2478.93 (312.60x) | 97.11 (12.25x) | 2095.40 (264.24x) |
| packed sfixed64 encode | 2.68 | 857.75 (320.06x) | 589.21 (219.85x) | 75.66 (28.23x) | 465.32 (173.63x) |
| packed sfixed64 decode | 7.89 | 1175.57 (148.99x) | 7782.44 (986.37x) | 79.30 (10.05x) | 3002.60 (380.56x) |
| packed float encode | 2.61 | 886.60 (339.69x) | 576.96 (221.06x) | 50.77 (19.45x) | 610.78 (234.02x) |
| packed float decode | 7.89 | 1155.96 (146.51x) | 2516.28 (318.92x) | 48.80 (6.18x) | 2502.70 (317.20x) |
| packed double encode | 2.01 | 847.65 (421.72x) | 566.74 (281.96x) | 75.84 (37.73x) | 365.30 (181.74x) |
| packed double decode | 4.52 | 1078.18 (238.54x) | 2390.17 (528.80x) | 90.11 (19.94x) | 3517.35 (778.17x) |
| packed uint64 encode | 1762.99 | 5560.79 (3.15x) | 4904.95 (2.78x) | 2459.82 (1.40x) | 4448.47 (2.52x) |
| packed uint64 decode | 1786.59 | 3451.02 (1.93x) | 9773.83 (5.47x) | 3610.15 (2.02x) | 11696.59 (6.55x) |
| packed uint32 encode | 1001.31 | 4297.65 (4.29x) | 3995.80 (3.99x) | 2157.96 (2.16x) | 3901.04 (3.90x) |
| packed uint32 decode | 1362.10 | 2936.55 (2.16x) | 3879.77 (2.85x) | 2411.57 (1.77x) | 8004.54 (5.88x) |
| packed int64 encode | 1417.29 | 12828.33 (9.05x) | 7121.93 (5.03x) | 3838.86 (2.71x) | 5413.69 (3.82x) |
| packed int64 decode | 2759.23 | 4319.31 (1.57x) | 11620.36 (4.21x) | 5758.65 (2.09x) | 14472.62 (5.25x) |
| packed sint32 encode | 798.86 | 3853.72 (4.82x) | 3479.68 (4.36x) | 2068.99 (2.59x) | 4642.65 (5.81x) |
| packed sint32 decode | 1299.02 | 3114.85 (2.40x) | 3897.29 (3.00x) | 1341.95 (1.03x) | 4894.29 (3.77x) |
| packed sint64 encode | 1429.60 | 6189.94 (4.33x) | 6099.02 (4.27x) | 3067.67 (2.15x) | 5464.53 (3.82x) |
| packed sint64 decode | 2047.52 | 4661.78 (2.28x) | 10798.31 (5.27x) | 3653.86 (1.78x) | 11566.03 (5.65x) |
| packed bool encode | 2.44 | 1665.21 (682.46x) | 526.82 (215.91x) | 15.82 (6.48x) | 3452.28 (1414.87x) |
| packed bool decode | 286.99 | 1895.01 (6.60x) | 2904.10 (10.12x) | 954.22 (3.32x) | 2402.56 (8.37x) |
| packed enum encode | 503.74 | 3230.28 (6.41x) | 2107.29 (4.18x) | 1184.82 (2.35x) | 3428.88 (6.81x) |
| packed enum decode | 154.26 | 1841.32 (11.94x) | 3319.05 (21.52x) | 818.90 (5.31x) | 3489.59 (22.62x) |
| large map encode | 3903.55 | 18341.60 (4.70x) | 14035.78 (3.60x) | 24300.20 (6.23x) | 237120.04 (60.74x) |
| shuffled large map deterministic binary encode | 34247.43 | — | — | 97901.60 (2.86x) | 441561.42 (12.89x) |
| large map decode | 28930.22 | 111636.22 (3.86x) | 112622.38 (3.89x) | 106061.00 (3.67x) | 350439.56 (12.11x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON (including generated `map<string, int32>` surrogate-pair key parse, null-field parse, enum-name parse, always-print default-value stringify, proto-name stringify, proto-name parse, open-enum numeric parse, and integer numeric-exponent parse), Any/WKT JSON (including embedded zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound `Duration`, non-empty/escaped-input parse/number-exponent parse/surrogate-pair value parse/surrogate-pair key parse and empty `Struct`, object/escaped-object parse/object-number-exponent/object-surrogate-pair value parse/object-surrogate-pair key parse/list/escaped-list/surrogate-list/string-scalar/escaped-string-scalar/surrogate-string-scalar/number-exponent/negative-number `Value` (including default-like scalar and empty object/list kinds),
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
