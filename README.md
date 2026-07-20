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

Latest accepted comparison (`/tmp/pbz-compare-list-surrogate-json-final.log`,
summarized in `/tmp/pbz-summary-list-surrogate-json-final.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 18.29 | 98.42 (5.38x) | 50.70 (2.77x) | 109.23 (5.97x) | 866.28 (47.36x) |
| binary decode | 88.25 | 247.11 (2.80x) | 235.19 (2.67x) | 225.30 (2.55x) | 916.97 (10.39x) |
| unknown fields count by number | 3.64 | — | — | 194.69 (53.49x) | — |
| deterministic binary encode | 50.71 | — | — | 133.63 (2.64x) | 1139.82 (22.48x) |
| scalarmix encode | 18.00 | 92.98 (5.17x) | 49.11 (2.73x) | 31.32 (1.74x) | 234.27 (13.02x) |
| scalarmix decode | 43.29 | 133.76 (3.09x) | 176.46 (4.08x) | 88.26 (2.04x) | 309.43 (7.15x) |
| textbytes encode | 9.74 | 78.00 (8.01x) | 33.62 (3.45x) | 118.13 (12.13x) | 146.73 (15.06x) |
| textbytes decode | 40.16 | 381.58 (9.50x) | 237.91 (5.92x) | 167.08 (4.16x) | 678.60 (16.90x) |
| largebytes encode | 18.05 | 2690.51 (149.06x) | 2673.42 (148.11x) | 2685.24 (148.77x) | 2710.87 (150.19x) |
| largebytes decode | 89.15 | 5537.32 (62.11x) | 3042.89 (34.13x) | 2726.05 (30.58x) | 21126.59 (236.98x) |
| presencemix encode | 17.53 | 55.84 (3.19x) | 27.50 (1.57x) | 57.22 (3.26x) | 233.24 (13.31x) |
| presencemix decode | 56.85 | 132.69 (2.33x) | 108.55 (1.91x) | 163.30 (2.87x) | 491.09 (8.64x) |
| complex encode | 49.18 | 134.27 (2.73x) | 94.59 (1.92x) | 166.34 (3.38x) | 916.42 (18.63x) |
| complex decode | 172.66 | 394.68 (2.29x) | 350.31 (2.03x) | 384.39 (2.23x) | 1352.27 (7.83x) |
| complex deterministic binary encode | 87.85 | — | — | 174.46 (1.99x) | 1102.37 (12.55x) |
| complex JSON stringify | 248.41 | — | — | 4863.77 (19.58x) | 6472.59 (26.06x) |
| complex JSON parse | 2393.42 | — | — | 11926.10 (4.98x) | 7511.26 (3.14x) |
| complex TextFormat format | 266.15 | — | — | 3766.81 (14.15x) | 5766.50 (21.67x) |
| complex TextFormat parse | 1814.63 | — | — | 6893.94 (3.80x) | 8446.97 (4.65x) |
| packed int32 encode | 659.45 | 3152.75 (4.78x) | 2510.67 (3.81x) | 1242.10 (1.88x) | 2741.09 (4.16x) |
| packed int32 decode | 689.85 | 1907.30 (2.76x) | 3208.56 (4.65x) | 947.38 (1.37x) | 2552.90 (3.70x) |
| JSON stringify | 151.84 | — | — | 3014.06 (19.85x) | 2399.22 (15.80x) |
| JSON parse | 1521.40 | — | — | 7426.23 (4.88x) | 4703.67 (3.09x) |
| Any WKT JSON stringify | 129.46 | — | — | 1883.08 (14.55x) | 974.45 (7.53x) |
| Any WKT JSON parse | 516.90 | — | — | 2994.25 (5.79x) | 1525.62 (2.95x) |
| Any Duration Escape WKT JSON parse | 537.12 | — | — | 3025.67 (5.63x) | 1602.45 (2.98x) |
| Any PlusDuration WKT JSON parse | 514.40 | — | — | 3024.41 (5.88x) | 1554.33 (3.02x) |
| Any ShortFractionDuration WKT JSON parse | 512.74 | — | — | 2964.16 (5.78x) | 1510.98 (2.95x) |
| Any MicroDuration WKT JSON stringify | 133.23 | — | — | 1895.99 (14.23x) | 992.03 (7.45x) |
| Any MicroDuration WKT JSON parse | 518.43 | — | — | 3004.92 (5.80x) | 1539.89 (2.97x) |
| Any NanoDuration WKT JSON stringify | 132.20 | — | — | 1920.43 (14.53x) | 976.43 (7.39x) |
| Any NanoDuration WKT JSON parse | 522.84 | — | — | 3010.21 (5.76x) | 1551.83 (2.97x) |
| Any NegativeDuration WKT JSON stringify | 130.86 | — | — | 1954.23 (14.93x) | 1010.78 (7.72x) |
| Any NegativeDuration WKT JSON parse | 518.02 | — | — | 3102.79 (5.99x) | 1576.97 (3.04x) |
| Any FractionalNegativeDuration WKT JSON stringify | 123.77 | — | — | 1885.35 (15.23x) | 999.35 (8.07x) |
| Any FractionalNegativeDuration WKT JSON parse | 512.40 | — | — | 3067.37 (5.99x) | 1512.89 (2.95x) |
| Any MaxDuration WKT JSON stringify | 115.53 | — | — | 1745.78 (15.11x) | 992.07 (8.59x) |
| Any MaxDuration WKT JSON parse | 528.93 | — | — | 2966.25 (5.61x) | 1519.03 (2.87x) |
| Any MinDuration WKT JSON stringify | 117.71 | — | — | 1759.41 (14.95x) | 1013.43 (8.61x) |
| Any MinDuration WKT JSON parse | 531.00 | — | — | 3024.53 (5.70x) | 1532.89 (2.89x) |
| Any ZeroDuration WKT JSON stringify | 103.81 | — | — | 992.56 (9.56x) | 952.38 (9.17x) |
| Any ZeroDuration WKT JSON parse | 461.74 | — | — | 2251.15 (4.88x) | 1459.50 (3.16x) |
| Any FieldMask WKT JSON stringify | 229.87 | — | — | 1737.20 (7.56x) | 1421.36 (6.18x) |
| Any FieldMask WKT JSON parse | 712.31 | — | — | 3142.34 (4.41x) | 2109.11 (2.96x) |
| Any FieldMask Escape WKT JSON parse | 726.33 | — | — | 3236.04 (4.46x) | 2232.13 (3.07x) |
| Any EmptyFieldMask WKT JSON stringify | 111.49 | — | — | 913.21 (8.19x) | 779.50 (6.99x) |
| Any EmptyFieldMask WKT JSON parse | 436.25 | — | — | 2144.62 (4.92x) | 1286.33 (2.95x) |
| Any Timestamp WKT JSON stringify | 173.90 | — | — | 2021.12 (11.62x) | 1006.36 (5.79x) |
| Any Timestamp WKT JSON parse | 564.47 | — | — | 3038.62 (5.38x) | 1604.19 (2.84x) |
| Any Timestamp Escape WKT JSON parse | 578.29 | — | — | 3085.79 (5.34x) | 1735.37 (3.00x) |
| Any ShortFraction Timestamp WKT JSON parse | 560.93 | — | — | 3029.03 (5.40x) | 1590.64 (2.84x) |
| Any Micro Timestamp WKT JSON stringify | 174.42 | — | — | 2022.54 (11.60x) | 1007.07 (5.77x) |
| Any Micro Timestamp WKT JSON parse | 570.85 | — | — | 3022.81 (5.30x) | 1625.37 (2.85x) |
| Any Nano Timestamp WKT JSON stringify | 172.86 | — | — | 2028.39 (11.73x) | 1020.42 (5.90x) |
| Any Nano Timestamp WKT JSON parse | 586.53 | — | — | 3031.54 (5.17x) | 1642.87 (2.80x) |
| Any Offset Timestamp WKT JSON parse | 589.68 | — | — | 3054.39 (5.18x) | 1666.36 (2.83x) |
| Any PreEpoch Timestamp WKT JSON stringify | 138.42 | — | — | 1944.39 (14.05x) | 973.37 (7.03x) |
| Any PreEpoch Timestamp WKT JSON parse | 555.26 | — | — | 3042.53 (5.48x) | 1570.67 (2.83x) |
| Any Max Timestamp WKT JSON stringify | 158.33 | — | — | 2045.95 (12.92x) | 1017.30 (6.43x) |
| Any Max Timestamp WKT JSON parse | 587.40 | — | — | 3091.58 (5.26x) | 1624.53 (2.77x) |
| Any Min Timestamp WKT JSON stringify | 155.48 | — | — | 1938.53 (12.47x) | 973.47 (6.26x) |
| Any Min Timestamp WKT JSON parse | 553.16 | — | — | 3033.90 (5.48x) | 1567.61 (2.83x) |
| Any Empty WKT JSON stringify | 90.02 | — | — | 908.88 (10.10x) | 668.76 (7.43x) |
| Any Empty WKT JSON parse | 334.45 | — | — | 2131.19 (6.37x) | 1318.12 (3.94x) |
| Any Struct WKT JSON stringify | 617.74 | — | — | 5864.51 (9.49x) | 6051.35 (9.80x) |
| Any Struct WKT JSON parse | 1754.62 | — | — | 11083.30 (6.32x) | 8810.18 (5.02x) |
| Any Struct Escape WKT JSON parse | 1771.61 | — | — | 11104.90 (6.27x) | 8904.95 (5.03x) |
| Any Struct NumberExponent WKT JSON parse | 1740.73 | — | — | 11083.70 (6.37x) | 8765.02 (5.04x) |
| Any Struct Surrogate WKT JSON parse | 752.98 | — | — | 6333.04 (8.41x) | 3067.79 (4.07x) |
| Any EmptyStruct WKT JSON stringify | 118.67 | — | — | 929.34 (7.83x) | 943.52 (7.95x) |
| Any EmptyStruct WKT JSON parse | 432.65 | — | — | 2235.80 (5.17x) | 1563.46 (3.61x) |
| Any Value WKT JSON stringify | 656.00 | — | — | 5928.37 (9.04x) | 6338.14 (9.66x) |
| Any Value WKT JSON parse | 1804.18 | — | — | 11229.60 (6.22x) | 9132.09 (5.06x) |
| Any Value Escape WKT JSON parse | 1819.16 | — | — | 11379.40 (6.26x) | 9254.04 (5.09x) |
| Any Value NumberExponent WKT JSON parse | 1796.88 | — | — | 11288.50 (6.28x) | 9173.77 (5.11x) |
| Any Value Surrogate WKT JSON parse | 808.51 | — | — | 6492.78 (8.03x) | 3488.86 (4.32x) |
| Any NullValue WKT JSON stringify | 127.37 | — | — | 2260.00 (17.74x) | 914.08 (7.18x) |
| Any NullValue WKT JSON parse | 460.82 | — | — | 4059.72 (8.81x) | 1578.61 (3.43x) |
| Any StringScalarValue WKT JSON stringify | 150.83 | — | — | 2266.48 (15.03x) | 996.24 (6.61x) |
| Any StringScalarValue WKT JSON parse | 521.37 | — | — | 3640.44 (6.98x) | 1680.74 (3.22x) |
| Any StringScalarValue Escape WKT JSON parse | 530.10 | — | — | 3664.25 (6.91x) | 1742.35 (3.29x) |
| Any StringScalarValue Surrogate WKT JSON parse | 528.53 | — | — | 3676.46 (6.96x) | 1741.12 (3.29x) |
| Any EmptyStringScalarValue WKT JSON stringify | 138.77 | — | — | 2264.40 (16.32x) | 995.82 (7.18x) |
| Any EmptyStringScalarValue WKT JSON parse | 487.81 | — | — | 3641.20 (7.46x) | 1565.96 (3.21x) |
| Any NumberValue WKT JSON stringify | 181.37 | — | — | 2510.84 (13.84x) | 1034.61 (5.70x) |
| Any NumberValue WKT JSON parse | 503.46 | — | — | 3686.22 (7.32x) | 1606.98 (3.19x) |
| Any NumberValue Exponent WKT JSON parse | 506.95 | — | — | 3698.22 (7.30x) | 1614.63 (3.18x) |
| Any NegativeNumberValue WKT JSON stringify | 173.02 | — | — | 2506.79 (14.49x) | 1036.43 (5.99x) |
| Any NegativeNumberValue WKT JSON parse | 504.54 | — | — | 3686.80 (7.31x) | 1612.84 (3.20x) |
| Any ZeroNumberValue WKT JSON stringify | 136.18 | — | — | 2461.14 (18.07x) | 924.79 (6.79x) |
| Any ZeroNumberValue WKT JSON parse | 499.34 | — | — | 3628.17 (7.27x) | 1615.54 (3.24x) |
| Any BoolScalarValue WKT JSON stringify | 131.67 | — | — | 2241.08 (17.02x) | 911.45 (6.92x) |
| Any BoolScalarValue WKT JSON parse | 460.20 | — | — | 3585.04 (7.79x) | 1512.27 (3.29x) |
| Any FalseBoolScalarValue WKT JSON stringify | 140.33 | — | — | 2246.08 (16.01x) | 915.48 (6.52x) |
| Any FalseBoolScalarValue WKT JSON parse | 462.65 | — | — | 3609.92 (7.80x) | 1528.50 (3.30x) |
| Any ListKindValue WKT JSON stringify | 496.92 | — | — | 5541.07 (11.15x) | 4683.41 (9.42x) |
| Any ListKindValue WKT JSON parse | 1387.33 | — | — | 9842.26 (7.09x) | 7085.05 (5.11x) |
| Any ListKindValue Escape WKT JSON parse | 1422.20 | — | — | 10016.30 (7.04x) | 7246.78 (5.10x) |
| Any ListKindValue Surrogate WKT JSON parse | 721.33 | — | — | 4796.32 (6.65x) | 2638.78 (3.66x) |
| Any EmptyStructKindValue WKT JSON stringify | 141.22 | — | — | 2917.95 (20.66x) | 1323.73 (9.37x) |
| Any EmptyStructKindValue WKT JSON parse | 499.50 | — | — | 5394.56 (10.80x) | 1937.68 (3.88x) |
| Any EmptyListKindValue WKT JSON stringify | 141.37 | — | — | 2898.49 (20.50x) | 1129.58 (7.99x) |
| Any EmptyListKindValue WKT JSON parse | 503.24 | — | — | 4381.89 (8.71x) | 1806.49 (3.59x) |
| Any DoubleValue WKT JSON stringify | 181.36 | — | — | 1797.80 (9.91x) | 817.15 (4.51x) |
| Any DoubleValue WKT JSON parse | 515.51 | — | — | 2744.29 (5.32x) | 1435.57 (2.78x) |
| Any DoubleValue String WKT JSON parse | 525.53 | — | — | 2737.63 (5.21x) | 1514.11 (2.88x) |
| Any DoubleValue Exponent WKT JSON parse | 516.81 | — | — | 2753.04 (5.33x) | 1441.40 (2.79x) |
| Any NegativeDoubleValue WKT JSON stringify | 179.48 | — | — | 1797.38 (10.01x) | 803.37 (4.48x) |
| Any NegativeDoubleValue WKT JSON parse | 515.32 | — | — | 2741.36 (5.32x) | 1424.12 (2.76x) |
| Any ZeroDoubleValue WKT JSON stringify | 152.27 | — | — | 916.28 (6.02x) | 748.23 (4.91x) |
| Any ZeroDoubleValue WKT JSON parse | 824.66 | — | — | 2167.69 (2.63x) | 1379.38 (1.67x) |
| Any DoubleValue NaN WKT JSON stringify | 244.57 | — | — | 1572.50 (6.43x) | 724.76 (2.96x) |
| Any DoubleValue NaN WKT JSON parse | 817.68 | — | — | 2650.84 (3.24x) | 1417.06 (1.73x) |
| Any DoubleValue Infinity WKT JSON stringify | 253.40 | — | — | 1571.47 (6.20x) | 723.86 (2.86x) |
| Any DoubleValue Infinity WKT JSON parse | 824.34 | — | — | 2694.40 (3.27x) | 1411.39 (1.71x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 255.51 | — | — | 1560.77 (6.11x) | 727.61 (2.85x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 830.15 | — | — | 2684.61 (3.23x) | 1432.48 (1.73x) |
| Any FloatValue WKT JSON stringify | 350.67 | — | — | 1742.54 (4.97x) | 789.25 (2.25x) |
| Any FloatValue WKT JSON parse | 843.36 | — | — | 2715.02 (3.22x) | 1438.56 (1.71x) |
| Any FloatValue String WKT JSON parse | 843.99 | — | — | 2721.42 (3.22x) | 1502.22 (1.78x) |
| Any FloatValue Exponent WKT JSON parse | 639.50 | — | — | 2727.21 (4.26x) | 1442.18 (2.26x) |
| Any NegativeFloatValue WKT JSON stringify | 320.20 | — | — | 1741.69 (5.44x) | 775.35 (2.42x) |
| Any NegativeFloatValue WKT JSON parse | 786.18 | — | — | 2722.03 (3.46x) | 1438.84 (1.83x) |
| Any ZeroFloatValue WKT JSON stringify | 204.46 | — | — | 917.28 (4.49x) | 725.78 (3.55x) |
| Any ZeroFloatValue WKT JSON parse | 676.26 | — | — | 2145.99 (3.17x) | 1362.87 (2.02x) |
| Any FloatValue NaN WKT JSON stringify | 150.95 | — | — | 1570.23 (10.40x) | 711.46 (4.71x) |
| Any FloatValue NaN WKT JSON parse | 508.91 | — | — | 2633.46 (5.17x) | 1408.88 (2.77x) |
| Any FloatValue Infinity WKT JSON stringify | 154.84 | — | — | 1552.99 (10.03x) | 721.72 (4.66x) |
| Any FloatValue Infinity WKT JSON parse | 515.88 | — | — | 2672.34 (5.18x) | 1397.93 (2.71x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 158.85 | — | — | 1546.76 (9.74x) | 721.03 (4.54x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 514.72 | — | — | 2649.72 (5.15x) | 1404.83 (2.73x) |
| Any Int64Value WKT JSON stringify | 167.37 | — | — | 1556.39 (9.30x) | 871.96 (5.21x) |
| Any Int64Value WKT JSON parse | 558.43 | — | — | 2787.70 (4.99x) | 1612.47 (2.89x) |
| Any Int64Value Number WKT JSON parse | 548.37 | — | — | 2756.69 (5.03x) | 1521.44 (2.77x) |
| Any Int64Value Exponent WKT JSON parse | 532.88 | — | — | 2713.72 (5.09x) | 1487.94 (2.79x) |
| Any ZeroInt64Value WKT JSON stringify | 154.26 | — | — | 914.00 (5.93x) | 777.15 (5.04x) |
| Any ZeroInt64Value WKT JSON parse | 522.45 | — | — | 2149.08 (4.11x) | 1480.57 (2.83x) |
| Any NegativeInt64Value WKT JSON stringify | 167.67 | — | — | 1559.31 (9.30x) | 851.83 (5.08x) |
| Any NegativeInt64Value WKT JSON parse | 562.37 | — | — | 2802.91 (4.98x) | 1638.49 (2.91x) |
| Any MinInt64Value WKT JSON stringify | 170.84 | — | — | 1558.99 (9.13x) | 858.79 (5.03x) |
| Any MinInt64Value WKT JSON parse | 570.67 | — | — | 2820.82 (4.94x) | 1676.80 (2.94x) |
| Any MaxInt64Value WKT JSON stringify | 166.18 | — | — | 1563.02 (9.41x) | 875.93 (5.27x) |
| Any MaxInt64Value WKT JSON parse | 565.32 | — | — | 2799.59 (4.95x) | 1682.72 (2.98x) |
| Any UInt64Value WKT JSON stringify | 170.74 | — | — | 1555.33 (9.11x) | 864.73 (5.06x) |
| Any UInt64Value WKT JSON parse | 553.40 | — | — | 2799.36 (5.06x) | 1627.19 (2.94x) |
| Any UInt64Value Number WKT JSON parse | 550.96 | — | — | 3028.76 (5.50x) | 1530.06 (2.78x) |
| Any UInt64Value Exponent WKT JSON parse | 535.59 | — | — | 4990.47 (9.32x) | 1490.35 (2.78x) |
| Any ZeroUInt64Value WKT JSON stringify | 159.07 | — | — | 1915.14 (12.04x) | 798.52 (5.02x) |
| Any ZeroUInt64Value WKT JSON parse | 523.73 | — | — | 4106.25 (7.84x) | 1467.41 (2.80x) |
| Any MaxUInt64Value WKT JSON stringify | 172.51 | — | — | 1659.28 (9.62x) | 866.86 (5.02x) |
| Any MaxUInt64Value WKT JSON parse | 561.76 | — | — | 2851.57 (5.08x) | 1683.22 (3.00x) |
| Any Int32Value WKT JSON stringify | 168.70 | — | — | 1549.94 (9.19x) | 732.71 (4.34x) |
| Any Int32Value WKT JSON parse | 532.89 | — | — | 2671.66 (5.01x) | 1447.38 (2.72x) |
| Any Int32Value String WKT JSON parse | 539.03 | — | — | 2679.21 (4.97x) | 1532.29 (2.84x) |
| Any Int32Value Exponent WKT JSON parse | 538.40 | — | — | 3276.59 (6.09x) | 1494.34 (2.78x) |
| Any ZeroInt32Value WKT JSON stringify | 164.66 | — | — | 1833.51 (11.14x) | 719.85 (4.37x) |
| Any ZeroInt32Value WKT JSON parse | 525.34 | — | — | 3913.83 (7.45x) | 1397.79 (2.66x) |
| Any NegativeInt32Value WKT JSON stringify | 167.89 | — | — | 3475.85 (20.70x) | 744.83 (4.44x) |
| Any NegativeInt32Value WKT JSON parse | 534.17 | — | — | 4919.37 (9.21x) | 1453.71 (2.72x) |
| Any MinInt32Value WKT JSON stringify | 174.02 | — | — | 3235.30 (18.59x) | 738.79 (4.25x) |
| Any MinInt32Value WKT JSON parse | 540.04 | — | — | 4501.84 (8.34x) | 1508.39 (2.79x) |
| Any MaxInt32Value WKT JSON stringify | 170.91 | — | — | 2564.41 (15.00x) | 732.15 (4.28x) |
| Any MaxInt32Value WKT JSON parse | 537.89 | — | — | 5113.17 (9.51x) | 1464.44 (2.72x) |
| Any UInt32Value WKT JSON stringify | 173.93 | — | — | 2353.18 (13.53x) | 733.90 (4.22x) |
| Any UInt32Value WKT JSON parse | 537.89 | — | — | 4049.95 (7.53x) | 1465.86 (2.73x) |
| Any UInt32Value String WKT JSON parse | 543.72 | — | — | 4117.33 (7.57x) | 1537.14 (2.83x) |
| Any UInt32Value Exponent WKT JSON parse | 546.52 | — | — | 5788.83 (10.59x) | 1510.53 (2.76x) |
| Any ZeroUInt32Value WKT JSON stringify | 174.69 | — | — | 1419.22 (8.12x) | 729.80 (4.18x) |
| Any ZeroUInt32Value WKT JSON parse | 532.73 | — | — | 2408.60 (4.52x) | 1377.97 (2.59x) |
| Any MaxUInt32Value WKT JSON stringify | 180.86 | — | — | 1561.76 (8.64x) | 739.51 (4.09x) |
| Any MaxUInt32Value WKT JSON parse | 545.58 | — | — | 2711.58 (4.97x) | 1471.40 (2.70x) |
| Any BoolValue WKT JSON stringify | 168.70 | — | — | 1530.37 (9.07x) | 727.05 (4.31x) |
| Any BoolValue WKT JSON parse | 484.14 | — | — | 2610.18 (5.39x) | 1343.37 (2.77x) |
| Any FalseBoolValue WKT JSON stringify | 172.71 | — | — | 925.28 (5.36x) | 717.67 (4.16x) |
| Any FalseBoolValue WKT JSON parse | 483.52 | — | — | 2160.32 (4.47x) | 1371.56 (2.84x) |
| Any StringValue WKT JSON stringify | 193.36 | — | — | 1561.06 (8.07x) | 796.86 (4.12x) |
| Any StringValue WKT JSON parse | 548.74 | — | — | 2670.54 (4.87x) | 1414.70 (2.58x) |
| Any StringValue Escape WKT JSON parse | 552.25 | — | — | 2686.91 (4.87x) | 1527.36 (2.77x) |
| Any StringValue Surrogate WKT JSON parse | 561.96 | — | — | 2689.23 (4.79x) | 1547.89 (2.75x) |
| Any EmptyStringValue WKT JSON stringify | 186.47 | — | — | 909.70 (4.88x) | 760.54 (4.08x) |
| Any EmptyStringValue WKT JSON parse | 516.40 | — | — | 2153.16 (4.17x) | 1357.26 (2.63x) |
| Any BytesValue WKT JSON stringify | 186.10 | — | — | 1591.45 (8.55x) | 864.39 (4.64x) |
| Any BytesValue WKT JSON parse | 564.41 | — | — | 2710.22 (4.80x) | 1468.09 (2.60x) |
| Any BytesValue URL WKT JSON parse | 581.69 | — | — | 2701.70 (4.64x) | 1488.50 (2.56x) |
| Any BytesValue StandardBase64 WKT JSON parse | 566.28 | — | — | 2713.27 (4.79x) | 1486.12 (2.62x) |
| Any BytesValue Unpadded WKT JSON parse | 565.50 | — | — | 2678.62 (4.74x) | 1498.21 (2.65x) |
| Any EmptyBytesValue WKT JSON stringify | 182.10 | — | — | 917.99 (5.04x) | 765.54 (4.20x) |
| Any EmptyBytesValue WKT JSON parse | 527.91 | — | — | 2147.84 (4.07x) | 1429.10 (2.71x) |
| Nested Any WKT JSON stringify | 291.71 | — | — | 2495.91 (8.56x) | 1454.73 (4.99x) |
| Nested Any WKT JSON parse | 854.78 | — | — | 4262.83 (4.99x) | 2837.78 (3.32x) |
| Duration JSON stringify | 57.16 | — | — | 966.68 (16.91x) | 377.29 (6.60x) |
| Duration JSON parse | 18.82 | — | — | 1451.68 (77.13x) | 389.19 (20.68x) |
| Duration Escape JSON parse | 40.37 | — | — | 1491.40 (36.94x) | 431.80 (10.70x) |
| PlusDuration JSON parse | 18.81 | — | — | 1459.96 (77.62x) | 394.21 (20.96x) |
| ShortFractionDuration JSON parse | 14.80 | — | — | 1424.88 (96.28x) | 395.18 (26.70x) |
| MicroDuration JSON stringify | 58.90 | — | — | 971.28 (16.49x) | 409.23 (6.95x) |
| MicroDuration JSON parse | 19.50 | — | — | 1465.59 (75.16x) | 388.22 (19.91x) |
| NanoDuration JSON stringify | 56.64 | — | — | 999.14 (17.64x) | 404.39 (7.14x) |
| NanoDuration JSON parse | 24.85 | — | — | 1476.95 (59.43x) | 398.41 (16.03x) |
| NegativeDuration JSON stringify | 58.23 | — | — | 1013.67 (17.41x) | 441.70 (7.59x) |
| NegativeDuration JSON parse | 19.20 | — | — | 1509.99 (78.65x) | 388.49 (20.23x) |
| FractionalNegativeDuration JSON stringify | 57.79 | — | — | 969.48 (16.78x) | 437.16 (7.56x) |
| FractionalNegativeDuration JSON parse | 19.19 | — | — | 1460.90 (76.13x) | 376.28 (19.61x) |
| MaxDuration JSON stringify | 49.17 | — | — | 855.25 (17.39x) | 413.28 (8.41x) |
| MaxDuration JSON parse | 34.65 | — | — | 1439.47 (41.54x) | 401.58 (11.59x) |
| MinDuration JSON stringify | 49.92 | — | — | 870.53 (17.44x) | 444.26 (8.90x) |
| MinDuration JSON parse | 32.15 | — | — | 1449.78 (45.09x) | 406.27 (12.64x) |
| ZeroDuration JSON stringify | 44.36 | — | — | 813.85 (18.35x) | 345.47 (7.79x) |
| ZeroDuration JSON parse | 15.29 | — | — | 1368.27 (89.49x) | 314.95 (20.60x) |
| FieldMask JSON stringify | 88.76 | — | — | 886.94 (9.99x) | 665.09 (7.49x) |
| FieldMask JSON parse | 155.00 | — | — | 1652.00 (10.66x) | 889.84 (5.74x) |
| FieldMask Escape JSON parse | 202.60 | — | — | 1716.29 (8.47x) | 970.49 (4.79x) |
| EmptyFieldMask JSON stringify | 40.68 | — | — | 609.42 (14.98x) | 196.30 (4.83x) |
| EmptyFieldMask JSON parse | 4.80 | — | — | 949.99 (197.91x) | 171.23 (35.67x) |
| Timestamp JSON stringify | 95.78 | — | — | 1131.88 (11.82x) | 410.32 (4.28x) |
| Timestamp JSON parse | 45.18 | — | — | 1492.13 (33.03x) | 447.54 (9.91x) |
| Timestamp Escape JSON parse | 98.26 | — | — | 1516.01 (15.43x) | 509.91 (5.19x) |
| ShortFraction Timestamp JSON parse | 43.52 | — | — | 1481.73 (34.05x) | 436.28 (10.02x) |
| Micro Timestamp JSON stringify | 96.80 | — | — | 1143.72 (11.82x) | 416.93 (4.31x) |
| Micro Timestamp JSON parse | 47.67 | — | — | 1510.90 (31.69x) | 729.23 (15.30x) |
| Nano Timestamp JSON stringify | 94.36 | — | — | 1186.67 (12.58x) | 425.79 (4.51x) |
| Nano Timestamp JSON parse | 50.21 | — | — | 1521.73 (30.31x) | 460.84 (9.18x) |
| Offset Timestamp JSON parse | 53.07 | — | — | 1532.23 (28.87x) | 486.39 (9.17x) |
| PreEpoch Timestamp JSON stringify | 66.13 | — | — | 1070.43 (16.19x) | 400.54 (6.06x) |
| PreEpoch Timestamp JSON parse | 42.92 | — | — | 1465.80 (34.15x) | 418.83 (9.76x) |
| Max Timestamp JSON stringify | 78.58 | — | — | 1198.28 (15.25x) | 421.99 (5.37x) |
| Max Timestamp JSON parse | 51.10 | — | — | 1541.09 (30.16x) | 467.60 (9.15x) |
| Min Timestamp JSON stringify | 79.51 | — | — | 1068.75 (13.44x) | 399.11 (5.02x) |
| Min Timestamp JSON parse | 40.87 | — | — | 1452.07 (35.53x) | 424.10 (10.38x) |
| Empty JSON stringify | 20.33 | — | — | 504.92 (24.84x) | 87.69 (4.31x) |
| Empty JSON parse | 67.21 | — | — | 788.74 (11.74x) | 220.59 (3.28x) |
| Struct JSON stringify | 174.91 | — | — | 5684.84 (32.50x) | 3073.64 (17.57x) |
| Struct JSON parse | 848.05 | — | — | 10855.20 (12.80x) | 4677.06 (5.52x) |
| Struct Escape JSON parse | 885.59 | — | — | 10915.40 (12.33x) | 4762.54 (5.38x) |
| Struct NumberExponent JSON parse | 847.94 | — | — | 10844.20 (12.79x) | 4663.34 (5.50x) |
| Struct Surrogate JSON parse | 372.42 | — | — | 4769.72 (12.81x) | 1193.06 (3.20x) |
| EmptyStruct JSON stringify | 40.65 | — | — | 700.38 (17.23x) | 348.69 (8.58x) |
| EmptyStruct JSON parse | 89.70 | — | — | 2017.72 (22.49x) | 376.97 (4.20x) |
| Value JSON stringify | 177.37 | — | — | 6571.16 (37.05x) | 3212.68 (18.11x) |
| Value JSON parse | 875.07 | — | — | 12134.00 (13.87x) | 4958.70 (5.67x) |
| Value Escape JSON parse | 914.43 | — | — | 12229.30 (13.37x) | 5050.45 (5.52x) |
| Value NumberExponent JSON parse | 866.40 | — | — | 12113.60 (13.98x) | 4906.49 (5.66x) |
| Value Surrogate JSON parse | 399.28 | — | — | 6655.18 (16.67x) | 1472.60 (3.69x) |
| NullValue JSON stringify | 39.98 | — | — | 1322.56 (33.08x) | 221.71 (5.55x) |
| NullValue JSON parse | 71.13 | — | — | 2473.94 (34.78x) | 350.97 (4.93x) |
| StringScalarValue JSON stringify | 47.62 | — | — | 1344.24 (28.23x) | 282.71 (5.94x) |
| StringScalarValue JSON parse | 140.01 | — | — | 2095.88 (14.97x) | 438.25 (3.13x) |
| StringScalarValue Escape JSON parse | 150.58 | — | — | 2138.68 (14.20x) | 491.05 (3.26x) |
| StringScalarValue Surrogate JSON parse | 153.66 | — | — | 2142.57 (13.94x) | 496.25 (3.23x) |
| EmptyStringScalarValue JSON stringify | 45.74 | — | — | 1345.46 (29.42x) | 274.15 (5.99x) |
| EmptyStringScalarValue JSON parse | 87.95 | — | — | 2067.64 (23.51x) | 362.62 (4.12x) |
| NumberValue JSON stringify | 73.91 | — | — | 1555.56 (21.05x) | 321.81 (4.35x) |
| NumberValue JSON parse | 132.55 | — | — | 2165.76 (16.34x) | 419.18 (3.16x) |
| NumberValue Exponent JSON parse | 135.04 | — | — | 2229.82 (16.51x) | 429.62 (3.18x) |
| NegativeNumberValue JSON stringify | 73.93 | — | — | 1560.18 (21.10x) | 320.86 (4.34x) |
| NegativeNumberValue JSON parse | 134.10 | — | — | 2176.12 (16.23x) | 408.86 (3.05x) |
| ZeroNumberValue JSON stringify | 50.68 | — | — | 1508.43 (29.76x) | 277.43 (5.47x) |
| ZeroNumberValue JSON parse | 131.15 | — | — | 2113.33 (16.11x) | 389.03 (2.97x) |
| BoolScalarValue JSON stringify | 40.10 | — | — | 1319.90 (32.92x) | 212.49 (5.30x) |
| BoolScalarValue JSON parse | 71.17 | — | — | 2023.63 (28.43x) | 333.75 (4.69x) |
| FalseBoolScalarValue JSON stringify | 40.19 | — | — | 1317.26 (32.78x) | 220.94 (5.50x) |
| FalseBoolScalarValue JSON parse | 71.04 | — | — | 2029.55 (28.57x) | 330.43 (4.65x) |
| ListKindValue JSON stringify | 139.28 | — | — | 6134.13 (44.04x) | 2275.12 (16.33x) |
| ListKindValue JSON parse | 674.65 | — | — | 10368.50 (15.37x) | 4037.54 (5.98x) |
| ListKindValue Escape JSON parse | 693.19 | — | — | 10442.40 (15.06x) | 4286.26 (6.18x) |
| ListKindValue Surrogate JSON parse | 329.54 | — | — | 4845.14 (14.70x) | 1194.60 (3.63x) |
| EmptyStructKindValue JSON stringify | 42.66 | — | — | 1947.96 (45.66x) | 522.27 (12.24x) |
| EmptyStructKindValue JSON parse | 112.00 | — | — | 3748.73 (33.47x) | 662.42 (5.91x) |
| EmptyListKindValue JSON stringify | 40.93 | — | — | 1928.37 (47.11x) | 364.08 (8.90x) |
| EmptyListKindValue JSON parse | 150.65 | — | — | 4036.04 (26.79x) | 601.95 (4.00x) |
| ListValue JSON stringify | 145.17 | — | — | 4719.71 (32.51x) | 2107.01 (14.51x) |
| ListValue JSON parse | 645.11 | — | — | 8497.12 (13.17x) | 3867.84 (6.00x) |
| ListValue Escape JSON parse | 663.89 | — | — | 8579.35 (12.92x) | 3972.01 (5.98x) |
| ListValue Surrogate JSON parse | 297.78 | — | — | 3072.57 (10.32x) | 930.41 (3.12x) |
| EmptyListValue JSON stringify | 39.87 | — | — | 880.00 (22.07x) | 194.82 (4.89x) |
| EmptyListValue JSON parse | 126.17 | — | — | 2231.20 (17.68x) | 333.69 (2.64x) |
| DoubleValue JSON stringify | 67.19 | — | — | 867.98 (12.92x) | 373.81 (5.56x) |
| DoubleValue JSON parse | 110.25 | — | — | 1231.27 (11.17x) | 290.61 (2.64x) |
| DoubleValue String JSON parse | 112.01 | — | — | 1175.07 (10.49x) | 365.63 (3.26x) |
| DoubleValue Exponent JSON parse | 112.37 | — | — | 1243.49 (11.07x) | 291.40 (2.59x) |
| NegativeDoubleValue JSON stringify | 68.43 | — | — | 865.59 (12.65x) | 193.19 (2.82x) |
| NegativeDoubleValue JSON parse | 110.57 | — | — | 1248.88 (11.29x) | 294.11 (2.66x) |
| ZeroDoubleValue JSON stringify | 46.93 | — | — | 807.59 (17.21x) | 136.58 (2.91x) |
| ZeroDoubleValue JSON parse | 107.83 | — | — | 1165.15 (10.81x) | 444.86 (4.13x) |
| DoubleValue NaN JSON stringify | 46.71 | — | — | 674.72 (14.44x) | 127.87 (2.74x) |
| DoubleValue NaN JSON parse | 105.11 | — | — | 1091.03 (10.38x) | 276.72 (2.63x) |
| DoubleValue Infinity JSON stringify | 48.10 | — | — | 674.17 (14.02x) | 125.64 (2.61x) |
| DoubleValue Infinity JSON parse | 105.99 | — | — | 1101.49 (10.39x) | 291.53 (2.75x) |
| DoubleValue NegativeInfinity JSON stringify | 48.12 | — | — | 669.54 (13.91x) | 131.32 (2.73x) |
| DoubleValue NegativeInfinity JSON parse | 108.24 | — | — | 1121.88 (10.36x) | 283.72 (2.62x) |
| FloatValue JSON stringify | 70.51 | — | — | 919.59 (13.04x) | 177.63 (2.52x) |
| FloatValue JSON parse | 110.50 | — | — | 1224.08 (11.08x) | 296.24 (2.68x) |
| FloatValue String JSON parse | 110.60 | — | — | 1164.97 (10.53x) | 376.14 (3.40x) |
| FloatValue Exponent JSON parse | 112.31 | — | — | 1236.12 (11.01x) | 289.43 (2.58x) |
| NegativeFloatValue JSON stringify | 70.81 | — | — | 809.93 (11.44x) | 185.38 (2.62x) |
| NegativeFloatValue JSON parse | 111.82 | — | — | 1222.40 (10.93x) | 283.42 (2.53x) |
| ZeroFloatValue JSON stringify | 47.18 | — | — | 748.83 (15.87x) | 155.11 (3.29x) |
| ZeroFloatValue JSON parse | 107.76 | — | — | 1157.32 (10.74x) | 260.32 (2.42x) |
| FloatValue NaN JSON stringify | 46.37 | — | — | 643.00 (13.87x) | 120.40 (2.60x) |
| FloatValue NaN JSON parse | 105.52 | — | — | 1090.02 (10.33x) | 267.29 (2.53x) |
| FloatValue Infinity JSON stringify | 47.96 | — | — | 643.41 (13.42x) | 122.59 (2.56x) |
| FloatValue Infinity JSON parse | 106.36 | — | — | 1095.74 (10.30x) | 267.87 (2.52x) |
| FloatValue NegativeInfinity JSON stringify | 48.13 | — | — | 643.03 (13.36x) | 124.66 (2.59x) |
| FloatValue NegativeInfinity JSON parse | 108.40 | — | — | 1102.79 (10.17x) | 280.86 (2.59x) |
| Int64Value JSON stringify | 52.00 | — | — | 676.75 (13.01x) | 276.74 (5.32x) |
| Int64Value JSON parse | 127.95 | — | — | 1228.30 (9.60x) | 470.13 (3.67x) |
| Int64Value Number JSON parse | 131.41 | — | — | 1282.12 (9.76x) | 352.71 (2.68x) |
| Int64Value Exponent JSON parse | 120.57 | — | — | 1221.16 (10.13x) | 364.25 (3.02x) |
| ZeroInt64Value JSON stringify | 43.74 | — | — | 609.34 (13.93x) | 190.05 (4.34x) |
| ZeroInt64Value JSON parse | 110.18 | — | — | 1101.41 (10.00x) | 344.74 (3.13x) |
| NegativeInt64Value JSON stringify | 50.47 | — | — | 676.27 (13.40x) | 284.42 (5.64x) |
| NegativeInt64Value JSON parse | 129.12 | — | — | 1215.02 (9.41x) | 484.12 (3.75x) |
| MinInt64Value JSON stringify | 52.30 | — | — | 676.01 (12.93x) | 275.29 (5.26x) |
| MinInt64Value JSON parse | 135.53 | — | — | 1247.29 (9.20x) | 502.25 (3.71x) |
| MaxInt64Value JSON stringify | 51.80 | — | — | 674.40 (13.02x) | 286.01 (5.52x) |
| MaxInt64Value JSON parse | 134.30 | — | — | 1247.89 (9.29x) | 479.32 (3.57x) |
| UInt64Value JSON stringify | 52.47 | — | — | 676.58 (12.89x) | 282.07 (5.38x) |
| UInt64Value JSON parse | 126.11 | — | — | 1214.09 (9.63x) | 471.86 (3.74x) |
| UInt64Value Number JSON parse | 129.00 | — | — | 1275.51 (9.89x) | 355.84 (2.76x) |
| UInt64Value Exponent JSON parse | 117.28 | — | — | 1229.03 (10.48x) | 369.01 (3.15x) |
| ZeroUInt64Value JSON stringify | 42.83 | — | — | 1255.58 (29.32x) | 199.23 (4.65x) |
| ZeroUInt64Value JSON parse | 106.06 | — | — | 2173.94 (20.50x) | 361.54 (3.41x) |
| MaxUInt64Value JSON stringify | 51.69 | — | — | 1326.78 (25.67x) | 295.20 (5.71x) |
| MaxUInt64Value JSON parse | 136.79 | — | — | 2450.46 (17.91x) | 474.01 (3.47x) |
| Int32Value JSON stringify | 47.50 | — | — | 632.51 (13.32x) | 134.74 (2.84x) |
| Int32Value JSON parse | 136.36 | — | — | 1188.00 (8.71x) | 312.98 (2.30x) |
| Int32Value String JSON parse | 139.16 | — | — | 1131.31 (8.13x) | 389.76 (2.80x) |
| Int32Value Exponent JSON parse | 139.54 | — | — | 1233.25 (8.84x) | 361.34 (2.59x) |
| ZeroInt32Value JSON stringify | 47.27 | — | — | 1294.94 (27.39x) | 124.26 (2.63x) |
| ZeroInt32Value JSON parse | 131.49 | — | — | 1903.14 (14.47x) | 276.17 (2.10x) |
| NegativeInt32Value JSON stringify | 48.04 | — | — | 1011.37 (21.05x) | 136.18 (2.83x) |
| NegativeInt32Value JSON parse | 135.64 | — | — | 2323.08 (17.13x) | 317.61 (2.34x) |
| MinInt32Value JSON stringify | 48.08 | — | — | 1272.32 (26.46x) | 137.57 (2.86x) |
| MinInt32Value JSON parse | 141.60 | — | — | 2414.52 (17.05x) | 353.75 (2.50x) |
| MaxInt32Value JSON stringify | 47.81 | — | — | 1336.44 (27.95x) | 138.85 (2.90x) |
| MaxInt32Value JSON parse | 142.78 | — | — | 2277.37 (15.95x) | 333.88 (2.34x) |
| UInt32Value JSON stringify | 47.45 | — | — | 1352.88 (28.51x) | 135.20 (2.85x) |
| UInt32Value JSON parse | 140.36 | — | — | 2214.03 (15.77x) | 307.38 (2.19x) |
| UInt32Value String JSON parse | 141.46 | — | — | 2064.76 (14.60x) | 390.27 (2.76x) |
| UInt32Value Exponent JSON parse | 139.86 | — | — | 1274.93 (9.12x) | 371.67 (2.66x) |
| ZeroUInt32Value JSON stringify | 47.45 | — | — | 1348.70 (28.42x) | 132.55 (2.79x) |
| ZeroUInt32Value JSON parse | 131.61 | — | — | 2428.24 (18.45x) | 270.04 (2.05x) |
| MaxUInt32Value JSON stringify | 47.79 | — | — | 649.44 (13.59x) | 140.10 (2.93x) |
| MaxUInt32Value JSON parse | 143.28 | — | — | 1217.51 (8.50x) | 337.25 (2.35x) |
| BoolValue JSON stringify | 45.50 | — | — | 622.88 (13.69x) | 121.92 (2.68x) |
| BoolValue JSON parse | 61.17 | — | — | 1058.91 (17.31x) | 213.41 (3.49x) |
| FalseBoolValue JSON stringify | 49.62 | — | — | 603.83 (12.17x) | 129.07 (2.60x) |
| FalseBoolValue JSON parse | 61.87 | — | — | 1073.82 (17.36x) | 222.44 (3.60x) |
| StringValue JSON stringify | 52.13 | — | — | 673.88 (12.93x) | 183.42 (3.52x) |
| StringValue JSON parse | 120.55 | — | — | 1148.76 (9.53x) | 321.23 (2.66x) |
| StringValue Escape JSON parse | 129.92 | — | — | 1178.42 (9.07x) | 376.74 (2.90x) |
| StringValue Surrogate JSON parse | 128.02 | — | — | 1178.80 (9.21x) | 381.40 (2.98x) |
| EmptyStringValue JSON stringify | 48.81 | — | — | 638.94 (13.09x) | 188.17 (3.86x) |
| EmptyStringValue JSON parse | 65.91 | — | — | 1116.16 (16.93x) | 227.98 (3.46x) |
| BytesValue JSON stringify | 49.35 | — | — | 677.15 (13.72x) | 205.58 (4.17x) |
| BytesValue JSON parse | 124.23 | — | — | 1185.42 (9.54x) | 358.74 (2.89x) |
| BytesValue URL JSON parse | 140.94 | — | — | 1173.91 (8.33x) | 338.56 (2.40x) |
| BytesValue StandardBase64 JSON parse | 122.90 | — | — | 1188.94 (9.67x) | 577.50 (4.70x) |
| BytesValue Unpadded JSON parse | 122.69 | — | — | 1171.53 (9.55x) | 342.91 (2.79x) |
| EmptyBytesValue JSON stringify | 40.85 | — | — | 658.44 (16.12x) | 190.14 (4.65x) |
| EmptyBytesValue JSON parse | 68.19 | — | — | 1140.62 (16.73x) | 287.67 (4.22x) |
| TextFormat format | 176.75 | — | — | 2591.98 (14.66x) | 2604.57 (14.74x) |
| TextFormat parse | 662.92 | — | — | 4977.64 (7.51x) | 6566.77 (9.91x) |
| packed fixed32 encode | 2.00 | 817.24 (408.62x) | 539.46 (269.73x) | 43.41 (21.71x) | 434.70 (217.35x) |
| packed fixed32 decode | 4.54 | 1044.41 (230.05x) | 1943.85 (428.16x) | 49.47 (10.90x) | 1552.99 (342.07x) |
| packed fixed64 encode | 2.01 | 574.72 (285.93x) | 586.85 (291.97x) | 75.83 (37.73x) | 391.49 (194.77x) |
| packed fixed64 decode | 4.52 | 1034.90 (228.96x) | 7940.00 (1756.64x) | 79.71 (17.64x) | 2165.24 (479.04x) |
| packed sfixed32 encode | 2.01 | 551.89 (274.57x) | 539.56 (268.44x) | 51.19 (25.47x) | 404.65 (201.32x) |
| packed sfixed32 decode | 4.54 | 1060.26 (233.54x) | 1986.48 (437.55x) | 48.55 (10.69x) | 1545.18 (340.35x) |
| packed sfixed64 encode | 2.00 | 572.38 (286.19x) | 561.48 (280.74x) | 75.64 (37.82x) | 410.98 (205.49x) |
| packed sfixed64 decode | 4.54 | 1024.67 (225.70x) | 7905.01 (1741.19x) | 79.45 (17.50x) | 2168.54 (477.65x) |
| packed float encode | 2.00 | 814.26 (407.13x) | 566.06 (283.03x) | 43.59 (21.79x) | 354.09 (177.04x) |
| packed float decode | 4.53 | 1044.58 (230.59x) | 2084.16 (460.08x) | 48.89 (10.79x) | 1538.77 (339.68x) |
| packed double encode | 2.01 | 834.08 (414.97x) | 561.23 (279.22x) | 75.80 (37.71x) | 353.38 (175.81x) |
| packed double decode | 4.54 | 1177.25 (259.31x) | 2046.04 (450.67x) | 79.64 (17.54x) | 2149.17 (473.39x) |
| packed uint64 encode | 1287.04 | 4603.47 (3.58x) | 4007.83 (3.11x) | 2128.08 (1.65x) | 3443.15 (2.68x) |
| packed uint64 decode | 1789.80 | 2784.00 (1.56x) | 8855.03 (4.95x) | 2800.88 (1.56x) | 6253.18 (3.49x) |
| packed uint32 encode | 1588.05 | 3612.69 (2.27x) | 3254.42 (2.05x) | 1744.08 (1.10x) | 2897.11 (1.82x) |
| packed uint32 decode | 1307.36 | 2427.74 (1.86x) | 3264.61 (2.50x) | 1987.58 (1.52x) | 4696.10 (3.59x) |
| packed int64 encode | 1410.06 | 10960.65 (7.77x) | 6065.96 (4.30x) | 2893.36 (2.05x) | 4119.10 (2.92x) |
| packed int64 decode | 2747.86 | 3406.91 (1.24x) | 10259.92 (3.73x) | 4783.80 (1.74x) | 7757.93 (2.82x) |
| packed sint32 encode | 781.41 | 3036.04 (3.89x) | 2787.39 (3.57x) | 1537.17 (1.97x) | 3384.75 (4.33x) |
| packed sint32 decode | 951.79 | 2548.27 (2.68x) | 3179.41 (3.34x) | 1122.22 (1.18x) | 3009.27 (3.16x) |
| packed sint64 encode | 1422.17 | 4929.29 (3.47x) | 4288.64 (3.02x) | 2412.14 (1.70x) | 4141.76 (2.91x) |
| packed sint64 decode | 2036.01 | 3059.11 (1.50x) | 9655.33 (4.74x) | 2935.05 (1.44x) | 6499.55 (3.19x) |
| packed bool encode | 2.01 | 1324.34 (658.88x) | 519.63 (258.52x) | 17.06 (8.49x) | 2416.70 (1202.34x) |
| packed bool decode | 262.80 | 1524.57 (5.80x) | 2556.28 (9.73x) | 805.07 (3.06x) | 1582.72 (6.02x) |
| packed enum encode | 272.76 | 2730.49 (10.01x) | 1811.46 (6.64x) | 1084.89 (3.98x) | 2618.55 (9.60x) |
| packed enum decode | 177.44 | 1532.65 (8.64x) | 2872.55 (16.19x) | 707.56 (3.99x) | 1985.56 (11.19x) |
| large map encode | 4054.36 | 16546.01 (4.08x) | 10382.34 (2.56x) | 22643.70 (5.59x) | 210370.88 (51.89x) |
| shuffled large map deterministic binary encode | 27818.98 | — | — | 103368.00 (3.72x) | 441792.75 (15.88x) |
| large map decode | 25326.89 | 90705.00 (3.58x) | 89627.27 (3.54x) | 93583.10 (3.70x) | 279934.26 (11.05x) |
The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound `Duration`, non-empty/escaped-input parse/number-exponent parse/surrogate-pair parse and empty `Struct`, object/escaped-object parse/object-number-exponent/object-surrogate-pair parse/list/escaped-list/surrogate-list/string-scalar/escaped-string-scalar/surrogate-string-scalar/number-exponent/negative-number `Value` (including default-like scalar and empty object/list kinds),
`FieldMask` (non-empty, escaped JSON parse input, and empty), escaped-input parse/short-fraction parse/micro/nano/offset/min/pre/post/max-bound `Timestamp`, `Empty`, min/zero/positive/number-input parse/numeric-exponent parse/negative/max `Int64Value`, negative/zero/positive finite/string-input parse/numeric-exponent parse `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), negative/zero/positive finite/string-input parse/numeric-exponent parse `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), zero/normal/number-input parse/numeric-exponent parse/max `UInt64Value`, min/zero/positive/string-input parse/numeric-exponent parse/negative/max `Int32Value`, zero/normal/string-input parse/numeric-exponent parse/max `UInt32Value`, true/false `BoolValue`, non-empty/escape-input parse/surrogate-pair parse/empty `StringValue`, padded-standard/base64url/unpadded-base64 parse/empty `BytesValue`, and recursive nested `Any` payloads), direct zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound Duration, non-empty/escaped-input parse/empty FieldMask, and escaped-input parse/short-fraction parse/micro/nano/offset/min/pre/post/max-bound Timestamp WKT JSON plus other direct WKT JSON, including non-empty/escaped-input parse/number-exponent parse/surrogate-pair parse/empty `Struct`, object/escaped-object parse/object-number-exponent/object-surrogate-pair parse/list/escaped-list/surrogate-list/string-scalar/escaped-string-scalar/surrogate-string-scalar/number-exponent/negative-number `Value`, and escaped/surrogate-pair/non-empty/empty `ListValue`, TextFormat, packed scalars, large bytes,
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
