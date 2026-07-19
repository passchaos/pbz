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

Latest accepted comparison (`/tmp/pbz-compare-value-string-escape-json-final.log`,
summarized in `/tmp/pbz-summary-value-string-escape-json-final.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 17.99 | 110.08 (6.12x) | 53.14 (2.95x) | 109.80 (6.10x) | 828.15 (46.03x) |
| binary decode | 88.80 | 248.38 (2.80x) | 226.19 (2.55x) | 215.44 (2.43x) | 895.02 (10.08x) |
| unknown fields count by number | 3.57 | — | — | 162.80 (45.60x) | — |
| deterministic binary encode | 46.52 | — | — | 130.45 (2.80x) | 1064.63 (22.89x) |
| scalarmix encode | 16.56 | 108.61 (6.56x) | 48.33 (2.92x) | 29.32 (1.77x) | 222.02 (13.41x) |
| scalarmix decode | 43.01 | 132.91 (3.09x) | 174.48 (4.06x) | 83.64 (1.94x) | 278.53 (6.48x) |
| textbytes encode | 13.53 | 87.85 (6.49x) | 33.60 (2.48x) | 118.08 (8.73x) | 144.79 (10.70x) |
| textbytes decode | 43.04 | 380.41 (8.84x) | 239.00 (5.55x) | 174.08 (4.04x) | 648.74 (15.07x) |
| largebytes encode | 17.54 | 2704.58 (154.19x) | 2674.95 (152.51x) | 2681.69 (152.89x) | 2724.77 (155.35x) |
| largebytes decode | 86.54 | 5552.94 (64.17x) | 2997.23 (34.63x) | 2745.82 (31.73x) | 24037.27 (277.76x) |
| presencemix encode | 16.67 | 57.58 (3.45x) | 27.24 (1.63x) | 57.27 (3.44x) | 237.12 (14.22x) |
| presencemix decode | 60.86 | 137.24 (2.26x) | 109.11 (1.79x) | 163.00 (2.68x) | 475.37 (7.81x) |
| complex encode | 47.15 | 136.08 (2.89x) | 96.27 (2.04x) | 159.59 (3.38x) | 941.79 (19.97x) |
| complex decode | 169.96 | 389.15 (2.29x) | 337.59 (1.99x) | 393.10 (2.31x) | 1356.55 (7.98x) |
| complex deterministic binary encode | 109.55 | — | — | 170.97 (1.56x) | 1089.05 (9.94x) |
| complex JSON stringify | 250.46 | — | — | 4895.03 (19.54x) | 5707.19 (22.79x) |
| complex JSON parse | 2375.81 | — | — | 11937.60 (5.02x) | 7374.10 (3.10x) |
| complex TextFormat format | 235.01 | — | — | 3769.57 (16.04x) | 5011.93 (21.33x) |
| complex TextFormat parse | 1856.35 | — | — | 6891.00 (3.71x) | 8292.91 (4.47x) |
| packed int32 encode | 657.07 | 3166.86 (4.82x) | 2509.95 (3.82x) | 1233.43 (1.88x) | 2758.87 (4.20x) |
| packed int32 decode | 682.37 | 1919.76 (2.81x) | 3208.44 (4.70x) | 932.27 (1.37x) | 3654.38 (5.36x) |
| JSON stringify | 154.99 | — | — | 2994.01 (19.32x) | 2121.14 (13.69x) |
| JSON parse | 1512.00 | — | — | 7489.43 (4.95x) | 4414.86 (2.92x) |
| Any WKT JSON stringify | 131.00 | — | — | 1891.17 (14.44x) | 1050.39 (8.02x) |
| Any WKT JSON parse | 527.42 | — | — | 2973.18 (5.64x) | 1807.57 (3.43x) |
| Any Duration Escape WKT JSON parse | 543.98 | — | — | 3000.21 (5.52x) | 1626.22 (2.99x) |
| Any PlusDuration WKT JSON parse | 529.16 | — | — | 2991.61 (5.65x) | 1727.01 (3.26x) |
| Any ShortFractionDuration WKT JSON parse | 525.17 | — | — | 2931.98 (5.58x) | 1593.42 (3.03x) |
| Any MicroDuration WKT JSON stringify | 129.40 | — | — | 1886.69 (14.58x) | 1003.07 (7.75x) |
| Any MicroDuration WKT JSON parse | 528.45 | — | — | 2991.08 (5.66x) | 1550.09 (2.93x) |
| Any NanoDuration WKT JSON stringify | 132.41 | — | — | 1909.99 (14.42x) | 1059.07 (8.00x) |
| Any NanoDuration WKT JSON parse | 534.23 | — | — | 2999.21 (5.61x) | 1697.00 (3.18x) |
| Any NegativeDuration WKT JSON stringify | 130.90 | — | — | 1938.30 (14.81x) | 1119.01 (8.55x) |
| Any NegativeDuration WKT JSON parse | 531.99 | — | — | 3089.02 (5.81x) | 1767.00 (3.32x) |
| Any FractionalNegativeDuration WKT JSON stringify | 123.54 | — | — | 1885.57 (15.26x) | 1183.09 (9.58x) |
| Any FractionalNegativeDuration WKT JSON parse | 527.92 | — | — | 3047.56 (5.77x) | 1610.43 (3.05x) |
| Any MaxDuration WKT JSON stringify | 115.85 | — | — | 1743.47 (15.05x) | 955.13 (8.24x) |
| Any MaxDuration WKT JSON parse | 540.13 | — | — | 2964.37 (5.49x) | 1473.53 (2.73x) |
| Any MinDuration WKT JSON stringify | 117.78 | — | — | 1755.74 (14.91x) | 1034.12 (8.78x) |
| Any MinDuration WKT JSON parse | 541.72 | — | — | 3022.62 (5.58x) | 1614.12 (2.98x) |
| Any ZeroDuration WKT JSON stringify | 103.94 | — | — | 912.15 (8.78x) | 1019.01 (9.80x) |
| Any ZeroDuration WKT JSON parse | 476.69 | — | — | 2245.71 (4.71x) | 1441.56 (3.02x) |
| Any FieldMask WKT JSON stringify | 225.78 | — | — | 1740.12 (7.71x) | 1520.91 (6.74x) |
| Any FieldMask WKT JSON parse | 717.11 | — | — | 3161.83 (4.41x) | 2170.30 (3.03x) |
| Any FieldMask Escape WKT JSON parse | 738.95 | — | — | 3240.96 (4.39x) | 2791.46 (3.78x) |
| Any EmptyFieldMask WKT JSON stringify | 110.76 | — | — | 918.08 (8.29x) | 760.56 (6.87x) |
| Any EmptyFieldMask WKT JSON parse | 446.45 | — | — | 2156.71 (4.83x) | 1196.27 (2.68x) |
| Any Timestamp WKT JSON stringify | 177.06 | — | — | 2031.47 (11.47x) | 1096.02 (6.19x) |
| Any Timestamp WKT JSON parse | 576.09 | — | — | 3026.53 (5.25x) | 1538.50 (2.67x) |
| Any Timestamp Escape WKT JSON parse | 592.47 | — | — | 3064.10 (5.17x) | 1919.87 (3.24x) |
| Any ShortFraction Timestamp WKT JSON parse | 573.21 | — | — | 3013.71 (5.26x) | 1575.92 (2.75x) |
| Any Micro Timestamp WKT JSON stringify | 180.36 | — | — | 2036.75 (11.29x) | 1123.07 (6.23x) |
| Any Micro Timestamp WKT JSON parse | 582.15 | — | — | 3033.46 (5.21x) | 2427.49 (4.17x) |
| Any Nano Timestamp WKT JSON stringify | 183.59 | — | — | 2041.07 (11.12x) | 1262.71 (6.88x) |
| Any Nano Timestamp WKT JSON parse | 586.63 | — | — | 3040.86 (5.18x) | 2085.24 (3.55x) |
| Any Offset Timestamp WKT JSON parse | 594.54 | — | — | 3048.12 (5.13x) | 1735.37 (2.92x) |
| Any PreEpoch Timestamp WKT JSON stringify | 145.82 | — | — | 1953.45 (13.40x) | 1151.42 (7.90x) |
| Any PreEpoch Timestamp WKT JSON parse | 569.04 | — | — | 3045.70 (5.35x) | 2097.36 (3.69x) |
| Any Max Timestamp WKT JSON stringify | 165.55 | — | — | 2052.27 (12.40x) | 1003.90 (6.06x) |
| Any Max Timestamp WKT JSON parse | 591.75 | — | — | 3094.44 (5.23x) | 1875.17 (3.17x) |
| Any Min Timestamp WKT JSON stringify | 160.97 | — | — | 1940.53 (12.06x) | 1021.79 (6.35x) |
| Any Min Timestamp WKT JSON parse | 566.54 | — | — | 3037.13 (5.36x) | 1603.41 (2.83x) |
| Any Empty WKT JSON stringify | 89.32 | — | — | 911.79 (10.21x) | 713.67 (7.99x) |
| Any Empty WKT JSON parse | 339.39 | — | — | 2130.53 (6.28x) | 1238.28 (3.65x) |
| Any Struct WKT JSON stringify | 624.92 | — | — | 5841.88 (9.35x) | 8253.78 (13.21x) |
| Any Struct WKT JSON parse | 1755.24 | — | — | 11167.90 (6.36x) | 10937.73 (6.23x) |
| Any Struct Escape WKT JSON parse | 1786.13 | — | — | 11274.10 (6.31x) | 10705.01 (5.99x) |
| Any EmptyStruct WKT JSON stringify | 116.09 | — | — | 910.97 (7.85x) | 1079.28 (9.30x) |
| Any EmptyStruct WKT JSON parse | 444.23 | — | — | 2219.94 (5.00x) | 1457.95 (3.28x) |
| Any Value WKT JSON stringify | 656.02 | — | — | 5830.16 (8.89x) | 7915.22 (12.07x) |
| Any Value WKT JSON parse | 1803.61 | — | — | 11402.30 (6.32x) | 9951.16 (5.52x) |
| Any Value Escape WKT JSON parse | 1840.91 | — | — | 11468.00 (6.23x) | 9694.09 (5.27x) |
| Any NullValue WKT JSON stringify | 129.11 | — | — | 2266.57 (17.56x) | 1129.73 (8.75x) |
| Any NullValue WKT JSON parse | 471.07 | — | — | 4058.73 (8.62x) | 1546.19 (3.28x) |
| Any StringScalarValue WKT JSON stringify | 150.07 | — | — | 2262.69 (15.08x) | 1024.84 (6.83x) |
| Any StringScalarValue WKT JSON parse | 528.63 | — | — | 3634.59 (6.88x) | 1603.54 (3.03x) |
| Any StringScalarValue Escape WKT JSON parse | 542.73 | — | — | 3677.33 (6.78x) | 1886.35 (3.48x) |
| Any EmptyStringScalarValue WKT JSON stringify | 138.19 | — | — | 2272.58 (16.45x) | 901.16 (6.52x) |
| Any EmptyStringScalarValue WKT JSON parse | 500.56 | — | — | 3607.43 (7.21x) | 1471.52 (2.94x) |
| Any NumberValue WKT JSON stringify | 173.56 | — | — | 2517.08 (14.50x) | 1051.46 (6.06x) |
| Any NumberValue WKT JSON parse | 510.85 | — | — | 3683.90 (7.21x) | 1697.93 (3.32x) |
| Any ZeroNumberValue WKT JSON stringify | 141.06 | — | — | 2455.67 (17.41x) | 918.19 (6.51x) |
| Any ZeroNumberValue WKT JSON parse | 507.56 | — | — | 3635.22 (7.16x) | 1494.88 (2.95x) |
| Any BoolScalarValue WKT JSON stringify | 128.37 | — | — | 2247.42 (17.51x) | 1001.36 (7.80x) |
| Any BoolScalarValue WKT JSON parse | 468.19 | — | — | 3595.29 (7.68x) | 1457.13 (3.11x) |
| Any FalseBoolScalarValue WKT JSON stringify | 130.02 | — | — | 2252.17 (17.32x) | 877.73 (6.75x) |
| Any FalseBoolScalarValue WKT JSON parse | 467.46 | — | — | 3582.41 (7.66x) | 1441.54 (3.08x) |
| Any ListKindValue WKT JSON stringify | 491.78 | — | — | 5559.90 (11.31x) | 4949.20 (10.06x) |
| Any ListKindValue WKT JSON parse | 1383.40 | — | — | 9961.71 (7.20x) | 7132.17 (5.16x) |
| Any EmptyStructKindValue WKT JSON stringify | 145.21 | — | — | 2913.99 (20.07x) | 1346.47 (9.27x) |
| Any EmptyStructKindValue WKT JSON parse | 504.55 | — | — | 5389.07 (10.68x) | 2273.44 (4.51x) |
| Any EmptyListKindValue WKT JSON stringify | 142.50 | — | — | 2899.40 (20.35x) | 1130.23 (7.93x) |
| Any EmptyListKindValue WKT JSON parse | 510.64 | — | — | 4384.81 (8.59x) | 1894.08 (3.71x) |
| Any DoubleValue WKT JSON stringify | 189.80 | — | — | 1787.10 (9.42x) | 761.91 (4.01x) |
| Any DoubleValue WKT JSON parse | 523.98 | — | — | 2723.53 (5.20x) | 1495.81 (2.85x) |
| Any DoubleValue String WKT JSON parse | 852.62 | — | — | 2721.30 (3.19x) | 1734.51 (2.03x) |
| Any NegativeDoubleValue WKT JSON stringify | 337.59 | — | — | 1792.54 (5.31x) | 790.33 (2.34x) |
| Any NegativeDoubleValue WKT JSON parse | 602.22 | — | — | 2723.13 (4.52x) | 1470.32 (2.44x) |
| Any ZeroDoubleValue WKT JSON stringify | 179.84 | — | — | 924.20 (5.14x) | 705.64 (3.92x) |
| Any ZeroDoubleValue WKT JSON parse | 519.64 | — | — | 2163.80 (4.16x) | 1317.24 (2.53x) |
| Any DoubleValue NaN WKT JSON stringify | 152.37 | — | — | 1570.03 (10.30x) | 684.57 (4.49x) |
| Any DoubleValue NaN WKT JSON parse | 521.09 | — | — | 2639.85 (5.07x) | 1392.75 (2.67x) |
| Any DoubleValue Infinity WKT JSON stringify | 162.79 | — | — | 1565.75 (9.62x) | 713.88 (4.39x) |
| Any DoubleValue Infinity WKT JSON parse | 523.74 | — | — | 2683.25 (5.12x) | 1423.78 (2.72x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 154.19 | — | — | 1553.28 (10.07x) | 731.07 (4.74x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 525.81 | — | — | 2696.98 (5.13x) | 1348.36 (2.56x) |
| Any FloatValue WKT JSON stringify | 190.74 | — | — | 1731.64 (9.08x) | 764.61 (4.01x) |
| Any FloatValue WKT JSON parse | 523.83 | — | — | 2685.90 (5.13x) | 1544.13 (2.95x) |
| Any FloatValue String WKT JSON parse | 532.61 | — | — | 2708.80 (5.09x) | 1557.88 (2.92x) |
| Any NegativeFloatValue WKT JSON stringify | 192.34 | — | — | 1729.22 (8.99x) | 788.10 (4.10x) |
| Any NegativeFloatValue WKT JSON parse | 525.76 | — | — | 2714.35 (5.16x) | 1354.58 (2.58x) |
| Any ZeroFloatValue WKT JSON stringify | 154.28 | — | — | 916.13 (5.94x) | 743.82 (4.82x) |
| Any ZeroFloatValue WKT JSON parse | 521.16 | — | — | 2143.63 (4.11x) | 1330.69 (2.55x) |
| Any FloatValue NaN WKT JSON stringify | 148.76 | — | — | 1563.22 (10.51x) | 670.80 (4.51x) |
| Any FloatValue NaN WKT JSON parse | 518.01 | — | — | 2616.19 (5.05x) | 1338.82 (2.58x) |
| Any FloatValue Infinity WKT JSON stringify | 158.05 | — | — | 1546.86 (9.79x) | 671.80 (4.25x) |
| Any FloatValue Infinity WKT JSON parse | 526.16 | — | — | 2628.33 (5.00x) | 1450.99 (2.76x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 153.79 | — | — | 1545.22 (10.05x) | 677.53 (4.41x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 525.55 | — | — | 2632.02 (5.01x) | 1279.31 (2.43x) |
| Any Int64Value WKT JSON stringify | 166.49 | — | — | 1551.55 (9.32x) | 860.07 (5.17x) |
| Any Int64Value WKT JSON parse | 558.58 | — | — | 2775.05 (4.97x) | 1726.86 (3.09x) |
| Any Int64Value Number WKT JSON parse | 559.64 | — | — | 2742.35 (4.90x) | 1604.34 (2.87x) |
| Any ZeroInt64Value WKT JSON stringify | 149.88 | — | — | 913.24 (6.09x) | 833.90 (5.56x) |
| Any ZeroInt64Value WKT JSON parse | 531.49 | — | — | 2138.47 (4.02x) | 1509.35 (2.84x) |
| Any NegativeInt64Value WKT JSON stringify | 164.25 | — | — | 1553.92 (9.46x) | 992.57 (6.04x) |
| Any NegativeInt64Value WKT JSON parse | 574.03 | — | — | 2789.72 (4.86x) | 1799.64 (3.14x) |
| Any MinInt64Value WKT JSON stringify | 174.36 | — | — | 1564.61 (8.97x) | 907.00 (5.20x) |
| Any MinInt64Value WKT JSON parse | 602.42 | — | — | 2809.65 (4.66x) | 1852.42 (3.07x) |
| Any MaxInt64Value WKT JSON stringify | 175.88 | — | — | 1558.96 (8.86x) | 962.25 (5.47x) |
| Any MaxInt64Value WKT JSON parse | 578.05 | — | — | 2796.16 (4.84x) | 1773.93 (3.07x) |
| Any UInt64Value WKT JSON stringify | 179.26 | — | — | 1550.20 (8.65x) | 960.46 (5.36x) |
| Any UInt64Value WKT JSON parse | 571.01 | — | — | 2776.36 (4.86x) | 1554.38 (2.72x) |
| Any UInt64Value Number WKT JSON parse | 573.64 | — | — | 2745.56 (4.79x) | 1502.86 (2.62x) |
| Any ZeroUInt64Value WKT JSON stringify | 163.79 | — | — | 914.55 (5.58x) | 747.53 (4.56x) |
| Any ZeroUInt64Value WKT JSON parse | 547.32 | — | — | 2144.99 (3.92x) | 1447.97 (2.65x) |
| Any MaxUInt64Value WKT JSON stringify | 180.81 | — | — | 1553.63 (8.59x) | 954.89 (5.28x) |
| Any MaxUInt64Value WKT JSON parse | 565.79 | — | — | 2824.63 (4.99x) | 1667.00 (2.95x) |
| Any Int32Value WKT JSON stringify | 164.93 | — | — | 1539.86 (9.34x) | 732.67 (4.44x) |
| Any Int32Value WKT JSON parse | 540.10 | — | — | 2654.25 (4.91x) | 1558.47 (2.89x) |
| Any Int32Value String WKT JSON parse | 546.23 | — | — | 2661.83 (4.87x) | 1665.94 (3.05x) |
| Any ZeroInt32Value WKT JSON stringify | 165.28 | — | — | 912.02 (5.52x) | 660.46 (4.00x) |
| Any ZeroInt32Value WKT JSON parse | 533.34 | — | — | 2141.05 (4.01x) | 1466.50 (2.75x) |
| Any NegativeInt32Value WKT JSON stringify | 167.51 | — | — | 1543.28 (9.21x) | 726.64 (4.34x) |
| Any NegativeInt32Value WKT JSON parse | 539.27 | — | — | 2690.30 (4.99x) | 1585.38 (2.94x) |
| Any MinInt32Value WKT JSON stringify | 169.53 | — | — | 1552.26 (9.16x) | 723.27 (4.27x) |
| Any MinInt32Value WKT JSON parse | 548.53 | — | — | 2690.93 (4.91x) | 1508.21 (2.75x) |
| Any MaxInt32Value WKT JSON stringify | 171.98 | — | — | 1549.65 (9.01x) | 738.37 (4.29x) |
| Any MaxInt32Value WKT JSON parse | 547.78 | — | — | 2679.29 (4.89x) | 1369.29 (2.50x) |
| Any UInt32Value WKT JSON stringify | 173.92 | — | — | 1560.22 (8.97x) | 799.05 (4.59x) |
| Any UInt32Value WKT JSON parse | 546.46 | — | — | 2676.24 (4.90x) | 1484.08 (2.72x) |
| Any UInt32Value String WKT JSON parse | 554.96 | — | — | 2671.54 (4.81x) | 1461.25 (2.63x) |
| Any ZeroUInt32Value WKT JSON stringify | 171.18 | — | — | 928.62 (5.42x) | 743.10 (4.34x) |
| Any ZeroUInt32Value WKT JSON parse | 541.42 | — | — | 2167.84 (4.00x) | 1460.49 (2.70x) |
| Any MaxUInt32Value WKT JSON stringify | 174.82 | — | — | 1558.08 (8.91x) | 712.41 (4.08x) |
| Any MaxUInt32Value WKT JSON parse | 554.37 | — | — | 2671.72 (4.82x) | 1553.62 (2.80x) |
| Any BoolValue WKT JSON stringify | 168.33 | — | — | 1521.67 (9.04x) | 750.58 (4.46x) |
| Any BoolValue WKT JSON parse | 491.59 | — | — | 2590.97 (5.27x) | 1339.54 (2.72x) |
| Any FalseBoolValue WKT JSON stringify | 167.94 | — | — | 912.06 (5.43x) | 707.07 (4.21x) |
| Any FalseBoolValue WKT JSON parse | 491.79 | — | — | 2130.26 (4.33x) | 1268.20 (2.58x) |
| Any StringValue WKT JSON stringify | 194.56 | — | — | 1561.84 (8.03x) | 782.34 (4.02x) |
| Any StringValue WKT JSON parse | 560.08 | — | — | 2649.53 (4.73x) | 1446.49 (2.58x) |
| Any StringValue Escape WKT JSON parse | 564.87 | — | — | 2674.97 (4.74x) | 1424.15 (2.52x) |
| Any EmptyStringValue WKT JSON stringify | 182.88 | — | — | 916.25 (5.01x) | 717.47 (3.92x) |
| Any EmptyStringValue WKT JSON parse | 555.75 | — | — | 2149.30 (3.87x) | 1326.26 (2.39x) |
| Any BytesValue WKT JSON stringify | 193.80 | — | — | 1575.90 (8.13x) | 814.00 (4.20x) |
| Any BytesValue WKT JSON parse | 593.20 | — | — | 2710.62 (4.57x) | 1558.69 (2.63x) |
| Any BytesValue URL WKT JSON parse | 603.25 | — | — | 2687.00 (4.45x) | 1383.80 (2.29x) |
| Any EmptyBytesValue WKT JSON stringify | 185.57 | — | — | 939.61 (5.06x) | 781.85 (4.21x) |
| Any EmptyBytesValue WKT JSON parse | 547.29 | — | — | 2140.74 (3.91x) | 1493.57 (2.73x) |
| Nested Any WKT JSON stringify | 300.96 | — | — | 2489.45 (8.27x) | 1459.72 (4.85x) |
| Nested Any WKT JSON parse | 940.72 | — | — | 9993.84 (10.62x) | 3036.42 (3.23x) |
| Duration JSON stringify | 66.61 | — | — | 1957.55 (29.39x) | 379.39 (5.70x) |
| Duration JSON parse | 26.52 | — | — | 3315.68 (125.03x) | 417.31 (15.74x) |
| Duration Escape JSON parse | 57.01 | — | — | 2745.83 (48.16x) | 404.28 (7.09x) |
| PlusDuration JSON parse | 27.92 | — | — | 1527.04 (54.69x) | 379.99 (13.61x) |
| ShortFractionDuration JSON parse | 23.92 | — | — | 1443.20 (60.33x) | 405.95 (16.97x) |
| MicroDuration JSON stringify | 60.77 | — | — | 999.01 (16.44x) | 379.83 (6.25x) |
| MicroDuration JSON parse | 23.63 | — | — | 1516.19 (64.16x) | 386.88 (16.37x) |
| NanoDuration JSON stringify | 58.15 | — | — | 1027.14 (17.66x) | 378.26 (6.50x) |
| NanoDuration JSON parse | 26.23 | — | — | 1536.23 (58.57x) | 446.71 (17.03x) |
| NegativeDuration JSON stringify | 60.14 | — | — | 1014.96 (16.88x) | 435.07 (7.23x) |
| NegativeDuration JSON parse | 21.08 | — | — | 1519.80 (72.10x) | 424.41 (20.13x) |
| FractionalNegativeDuration JSON stringify | 60.13 | — | — | 983.63 (16.36x) | 446.64 (7.43x) |
| FractionalNegativeDuration JSON parse | 20.32 | — | — | 1478.16 (72.74x) | 383.77 (18.89x) |
| MaxDuration JSON stringify | 50.57 | — | — | 874.76 (17.30x) | 407.73 (8.06x) |
| MaxDuration JSON parse | 35.57 | — | — | 1468.94 (41.30x) | 407.22 (11.45x) |
| MinDuration JSON stringify | 50.88 | — | — | 877.45 (17.25x) | 476.77 (9.37x) |
| MinDuration JSON parse | 35.25 | — | — | 1467.81 (41.64x) | 412.63 (11.71x) |
| ZeroDuration JSON stringify | 45.87 | — | — | 833.73 (18.18x) | 357.39 (7.79x) |
| ZeroDuration JSON parse | 17.23 | — | — | 1575.37 (91.43x) | 284.86 (16.53x) |
| FieldMask JSON stringify | 69.31 | — | — | 1291.20 (18.63x) | 664.17 (9.58x) |
| FieldMask JSON parse | 142.70 | — | — | 1717.24 (12.03x) | 873.09 (6.12x) |
| FieldMask Escape JSON parse | 194.31 | — | — | 1726.63 (8.89x) | 1005.47 (5.17x) |
| EmptyFieldMask JSON stringify | 41.93 | — | — | 615.43 (14.68x) | 179.61 (4.28x) |
| EmptyFieldMask JSON parse | 4.91 | — | — | 953.60 (194.22x) | 144.09 (29.35x) |
| Timestamp JSON stringify | 98.35 | — | — | 2210.99 (22.48x) | 421.37 (4.28x) |
| Timestamp JSON parse | 46.62 | — | — | 2919.79 (62.63x) | 411.91 (8.84x) |
| Timestamp Escape JSON parse | 98.38 | — | — | 2438.18 (24.78x) | 482.46 (4.90x) |
| ShortFraction Timestamp JSON parse | 44.98 | — | — | 2350.34 (52.25x) | 395.96 (8.80x) |
| Micro Timestamp JSON stringify | 98.63 | — | — | 1194.16 (12.11x) | 413.80 (4.20x) |
| Micro Timestamp JSON parse | 48.95 | — | — | 1521.85 (31.09x) | 442.91 (9.05x) |
| Nano Timestamp JSON stringify | 96.81 | — | — | 1180.41 (12.19x) | 441.43 (4.56x) |
| Nano Timestamp JSON parse | 51.94 | — | — | 1529.03 (29.44x) | 451.29 (8.69x) |
| Offset Timestamp JSON parse | 55.36 | — | — | 1573.77 (28.43x) | 472.62 (8.54x) |
| PreEpoch Timestamp JSON stringify | 68.02 | — | — | 1110.90 (16.33x) | 402.63 (5.92x) |
| PreEpoch Timestamp JSON parse | 44.13 | — | — | 1574.62 (35.68x) | 415.48 (9.41x) |
| Max Timestamp JSON stringify | 80.66 | — | — | 1214.24 (15.05x) | 426.67 (5.29x) |
| Max Timestamp JSON parse | 53.30 | — | — | 1553.89 (29.15x) | 439.27 (8.24x) |
| Min Timestamp JSON stringify | 82.19 | — | — | 1065.20 (12.96x) | 439.58 (5.35x) |
| Min Timestamp JSON parse | 42.33 | — | — | 1461.83 (34.53x) | 393.49 (9.30x) |
| Empty JSON stringify | 21.40 | — | — | 504.46 (23.57x) | 99.76 (4.66x) |
| Empty JSON parse | 79.59 | — | — | 720.06 (9.05x) | 194.94 (2.45x) |
| Struct JSON stringify | 180.09 | — | — | 5756.36 (31.96x) | 2986.45 (16.58x) |
| Struct JSON parse | 874.71 | — | — | 10935.00 (12.50x) | 4926.10 (5.63x) |
| Struct Escape JSON parse | 888.91 | — | — | 10957.40 (12.33x) | 4882.22 (5.49x) |
| EmptyStruct JSON stringify | 40.45 | — | — | 689.49 (17.05x) | 313.86 (7.76x) |
| EmptyStruct JSON parse | 87.75 | — | — | 2017.75 (22.99x) | 352.86 (4.02x) |
| Value JSON stringify | 178.27 | — | — | 6591.62 (36.98x) | 3339.92 (18.74x) |
| Value JSON parse | 882.03 | — | — | 12099.50 (13.72x) | 5201.89 (5.90x) |
| Value Escape JSON parse | 923.33 | — | — | 12204.50 (13.22x) | 5300.00 (5.74x) |
| NullValue JSON stringify | 40.24 | — | — | 1329.62 (33.04x) | 216.88 (5.39x) |
| NullValue JSON parse | 75.69 | — | — | 2477.60 (32.73x) | 347.96 (4.60x) |
| StringScalarValue JSON stringify | 47.39 | — | — | 1356.10 (28.62x) | 279.51 (5.90x) |
| StringScalarValue JSON parse | 145.56 | — | — | 2099.26 (14.42x) | 402.41 (2.76x) |
| StringScalarValue Escape JSON parse | 155.93 | — | — | 2124.39 (13.62x) | 481.16 (3.09x) |
| EmptyStringScalarValue JSON stringify | 45.37 | — | — | 1342.30 (29.59x) | 262.13 (5.78x) |
| EmptyStringScalarValue JSON parse | 92.97 | — | — | 2061.75 (22.18x) | 341.31 (3.67x) |
| NumberValue JSON stringify | 72.94 | — | — | 1561.13 (21.40x) | 324.40 (4.45x) |
| NumberValue JSON parse | 138.07 | — | — | 2225.66 (16.12x) | 387.96 (2.81x) |
| ZeroNumberValue JSON stringify | 50.97 | — | — | 1514.95 (29.72x) | 284.09 (5.57x) |
| ZeroNumberValue JSON parse | 135.56 | — | — | 2111.55 (15.58x) | 365.90 (2.70x) |
| BoolScalarValue JSON stringify | 40.27 | — | — | 1321.70 (32.82x) | 212.06 (5.27x) |
| BoolScalarValue JSON parse | 75.68 | — | — | 2023.09 (26.73x) | 326.45 (4.31x) |
| FalseBoolScalarValue JSON stringify | 40.45 | — | — | 1325.52 (32.77x) | 221.35 (5.47x) |
| FalseBoolScalarValue JSON parse | 76.18 | — | — | 2033.35 (26.69x) | 328.62 (4.31x) |
| ListKindValue JSON stringify | 144.44 | — | — | 6146.73 (42.56x) | 2281.32 (15.79x) |
| ListKindValue JSON parse | 672.96 | — | — | 13942.00 (20.72x) | 4433.35 (6.59x) |
| EmptyStructKindValue JSON stringify | 42.29 | — | — | 1958.15 (46.30x) | 517.54 (12.24x) |
| EmptyStructKindValue JSON parse | 116.33 | — | — | 3762.73 (32.35x) | 666.77 (5.73x) |
| EmptyListKindValue JSON stringify | 41.13 | — | — | 1960.09 (47.66x) | 356.71 (8.67x) |
| EmptyListKindValue JSON parse | 153.74 | — | — | 4041.49 (26.29x) | 579.66 (3.77x) |
| ListValue JSON stringify | 142.10 | — | — | 5069.59 (35.68x) | 2049.35 (14.42x) |
| ListValue JSON parse | 651.34 | — | — | 8480.62 (13.02x) | 4253.60 (6.53x) |
| EmptyListValue JSON stringify | 39.89 | — | — | 694.75 (17.42x) | 175.19 (4.39x) |
| EmptyListValue JSON parse | 125.20 | — | — | 2239.61 (17.89x) | 295.53 (2.36x) |
| DoubleValue JSON stringify | 68.86 | — | — | 846.88 (12.30x) | 183.19 (2.66x) |
| DoubleValue JSON parse | 112.26 | — | — | 1233.09 (10.98x) | 273.83 (2.44x) |
| DoubleValue String JSON parse | 112.24 | — | — | 1174.73 (10.47x) | 356.13 (3.17x) |
| NegativeDoubleValue JSON stringify | 67.46 | — | — | 853.09 (12.65x) | 188.55 (2.79x) |
| NegativeDoubleValue JSON parse | 111.35 | — | — | 1237.09 (11.11x) | 285.03 (2.56x) |
| ZeroDoubleValue JSON stringify | 47.24 | — | — | 792.86 (16.78x) | 144.28 (3.05x) |
| ZeroDoubleValue JSON parse | 108.91 | — | — | 1153.29 (10.59x) | 255.40 (2.35x) |
| DoubleValue NaN JSON stringify | 45.94 | — | — | 653.59 (14.23x) | 119.68 (2.61x) |
| DoubleValue NaN JSON parse | 105.58 | — | — | 1092.64 (10.35x) | 259.50 (2.46x) |
| DoubleValue Infinity JSON stringify | 47.60 | — | — | 660.23 (13.87x) | 140.04 (2.94x) |
| DoubleValue Infinity JSON parse | 106.73 | — | — | 1101.71 (10.32x) | 250.86 (2.35x) |
| DoubleValue NegativeInfinity JSON stringify | 47.65 | — | — | 652.12 (13.69x) | 115.08 (2.42x) |
| DoubleValue NegativeInfinity JSON parse | 109.32 | — | — | 1109.00 (10.14x) | 277.10 (2.53x) |
| FloatValue JSON stringify | 70.83 | — | — | 797.91 (11.27x) | 174.78 (2.47x) |
| FloatValue JSON parse | 111.72 | — | — | 1225.10 (10.97x) | 276.35 (2.47x) |
| FloatValue String JSON parse | 110.36 | — | — | 1155.07 (10.47x) | 350.42 (3.18x) |
| NegativeFloatValue JSON stringify | 71.46 | — | — | 798.02 (11.17x) | 187.43 (2.62x) |
| NegativeFloatValue JSON parse | 112.15 | — | — | 1218.41 (10.86x) | 296.31 (2.64x) |
| ZeroFloatValue JSON stringify | 47.19 | — | — | 742.88 (15.74x) | 131.04 (2.78x) |
| ZeroFloatValue JSON parse | 108.21 | — | — | 1156.99 (10.69x) | 276.35 (2.55x) |
| FloatValue NaN JSON stringify | 45.97 | — | — | 635.69 (13.83x) | 117.79 (2.56x) |
| FloatValue NaN JSON parse | 104.94 | — | — | 1085.14 (10.34x) | 267.69 (2.55x) |
| FloatValue Infinity JSON stringify | 47.40 | — | — | 641.56 (13.54x) | 116.40 (2.46x) |
| FloatValue Infinity JSON parse | 106.61 | — | — | 1097.72 (10.30x) | 246.96 (2.32x) |
| FloatValue NegativeInfinity JSON stringify | 47.63 | — | — | 635.82 (13.35x) | 115.12 (2.42x) |
| FloatValue NegativeInfinity JSON parse | 108.07 | — | — | 1096.56 (10.15x) | 268.98 (2.49x) |
| Int64Value JSON stringify | 50.11 | — | — | 674.11 (13.45x) | 274.56 (5.48x) |
| Int64Value JSON parse | 125.61 | — | — | 1216.07 (9.68x) | 423.00 (3.37x) |
| Int64Value Number JSON parse | 127.34 | — | — | 1274.04 (10.01x) | 338.54 (2.66x) |
| ZeroInt64Value JSON stringify | 41.54 | — | — | 609.71 (14.68x) | 183.81 (4.42x) |
| ZeroInt64Value JSON parse | 104.93 | — | — | 1088.17 (10.37x) | 322.53 (3.07x) |
| NegativeInt64Value JSON stringify | 48.43 | — | — | 671.77 (13.87x) | 262.06 (5.41x) |
| NegativeInt64Value JSON parse | 128.58 | — | — | 1207.55 (9.39x) | 458.45 (3.57x) |
| MinInt64Value JSON stringify | 49.53 | — | — | 675.31 (13.63x) | 275.51 (5.56x) |
| MinInt64Value JSON parse | 136.52 | — | — | 1249.63 (9.15x) | 480.22 (3.52x) |
| MaxInt64Value JSON stringify | 49.48 | — | — | 672.01 (13.58x) | 270.61 (5.47x) |
| MaxInt64Value JSON parse | 135.19 | — | — | 1237.94 (9.16x) | 453.48 (3.35x) |
| UInt64Value JSON stringify | 50.35 | — | — | 674.81 (13.40x) | 284.02 (5.64x) |
| UInt64Value JSON parse | 123.56 | — | — | 1213.03 (9.82x) | 451.45 (3.65x) |
| UInt64Value Number JSON parse | 126.69 | — | — | 1274.13 (10.06x) | 325.91 (2.57x) |
| ZeroUInt64Value JSON stringify | 41.79 | — | — | 610.67 (14.61x) | 185.38 (4.44x) |
| ZeroUInt64Value JSON parse | 103.18 | — | — | 1095.15 (10.61x) | 322.41 (3.12x) |
| MaxUInt64Value JSON stringify | 50.21 | — | — | 674.86 (13.44x) | 273.61 (5.45x) |
| MaxUInt64Value JSON parse | 141.21 | — | — | 1246.92 (8.83x) | 477.97 (3.38x) |
| Int32Value JSON stringify | 46.04 | — | — | 631.01 (13.71x) | 142.63 (3.10x) |
| Int32Value JSON parse | 118.34 | — | — | 1180.11 (9.97x) | 304.42 (2.57x) |
| Int32Value String JSON parse | 114.79 | — | — | 1129.42 (9.84x) | 402.56 (3.51x) |
| ZeroInt32Value JSON stringify | 46.00 | — | — | 614.75 (13.36x) | 119.46 (2.60x) |
| ZeroInt32Value JSON parse | 113.84 | — | — | 1148.70 (10.09x) | 252.95 (2.22x) |
| NegativeInt32Value JSON stringify | 46.15 | — | — | 638.16 (13.83x) | 126.58 (2.74x) |
| NegativeInt32Value JSON parse | 117.32 | — | — | 1190.92 (10.15x) | 315.99 (2.69x) |
| MinInt32Value JSON stringify | 46.95 | — | — | 637.90 (13.59x) | 150.16 (3.20x) |
| MinInt32Value JSON parse | 124.58 | — | — | 1209.76 (9.71x) | 346.57 (2.78x) |
| MaxInt32Value JSON stringify | 46.79 | — | — | 632.52 (13.52x) | 149.38 (3.19x) |
| MaxInt32Value JSON parse | 124.23 | — | — | 1200.60 (9.66x) | 327.03 (2.63x) |
| UInt32Value JSON stringify | 45.96 | — | — | 627.62 (13.66x) | 137.24 (2.99x) |
| UInt32Value JSON parse | 117.80 | — | — | 1182.38 (10.04x) | 292.92 (2.49x) |
| UInt32Value String JSON parse | 115.02 | — | — | 1125.20 (9.78x) | 382.44 (3.32x) |
| ZeroUInt32Value JSON stringify | 45.93 | — | — | 612.38 (13.33x) | 124.41 (2.71x) |
| ZeroUInt32Value JSON parse | 113.49 | — | — | 1148.17 (10.12x) | 250.84 (2.21x) |
| MaxUInt32Value JSON stringify | 46.81 | — | — | 630.34 (13.47x) | 130.09 (2.78x) |
| MaxUInt32Value JSON parse | 123.90 | — | — | 1206.75 (9.74x) | 312.22 (2.52x) |
| BoolValue JSON stringify | 44.10 | — | — | 611.63 (13.87x) | 127.27 (2.89x) |
| BoolValue JSON parse | 60.15 | — | — | 1054.16 (17.53x) | 235.13 (3.91x) |
| FalseBoolValue JSON stringify | 44.20 | — | — | 603.56 (13.66x) | 136.31 (3.08x) |
| FalseBoolValue JSON parse | 60.65 | — | — | 1057.74 (17.44x) | 228.27 (3.76x) |
| StringValue JSON stringify | 51.39 | — | — | 656.26 (12.77x) | 172.07 (3.35x) |
| StringValue JSON parse | 120.65 | — | — | 1137.87 (9.43x) | 282.17 (2.34x) |
| StringValue Escape JSON parse | 130.58 | — | — | 1167.61 (8.94x) | 343.84 (2.63x) |
| EmptyStringValue JSON stringify | 48.50 | — | — | 633.02 (13.05x) | 195.75 (4.04x) |
| EmptyStringValue JSON parse | 66.03 | — | — | 1111.08 (16.83x) | 219.62 (3.33x) |
| BytesValue JSON stringify | 50.42 | — | — | 660.07 (13.09x) | 194.29 (3.85x) |
| BytesValue JSON parse | 124.19 | — | — | 1168.09 (9.41x) | 330.03 (2.66x) |
| BytesValue URL JSON parse | 140.25 | — | — | 1159.69 (8.27x) | 305.47 (2.18x) |
| EmptyBytesValue JSON stringify | 41.64 | — | — | 635.32 (15.26x) | 190.50 (4.57x) |
| EmptyBytesValue JSON parse | 67.71 | — | — | 1127.11 (16.65x) | 258.80 (3.82x) |
| TextFormat format | 177.26 | — | — | 2560.70 (14.45x) | 2306.93 (13.01x) |
| TextFormat parse | 659.46 | — | — | 4976.63 (7.55x) | 6405.39 (9.71x) |
| packed fixed32 encode | 2.01 | 552.51 (274.88x) | 539.38 (268.35x) | 43.84 (21.81x) | 422.36 (210.13x) |
| packed fixed32 decode | 4.54 | 1055.13 (232.41x) | 1951.26 (429.79x) | 49.78 (10.97x) | 1885.23 (415.25x) |
| packed fixed64 encode | 2.01 | 573.22 (285.18x) | 561.01 (279.11x) | 80.52 (40.06x) | 484.27 (240.93x) |
| packed fixed64 decode | 4.54 | 1036.69 (228.35x) | 7936.17 (1748.06x) | 79.84 (17.59x) | 2670.42 (588.20x) |
| packed sfixed32 encode | 2.00 | 551.37 (275.69x) | 539.54 (269.77x) | 43.95 (21.98x) | 415.83 (207.91x) |
| packed sfixed32 decode | 4.54 | 1071.44 (236.00x) | 1916.89 (422.22x) | 49.07 (10.81x) | 1756.23 (386.83x) |
| packed sfixed64 encode | 2.00 | 569.81 (284.90x) | 561.03 (280.51x) | 75.74 (37.87x) | 426.88 (213.44x) |
| packed sfixed64 decode | 4.53 | 998.29 (220.37x) | 7895.72 (1742.98x) | 79.47 (17.54x) | 2445.40 (539.82x) |
| packed float encode | 2.01 | 811.77 (403.87x) | 539.41 (268.36x) | 43.90 (21.84x) | 550.85 (274.05x) |
| packed float decode | 4.53 | 1046.99 (231.12x) | 2053.44 (453.30x) | 48.82 (10.78x) | 1714.67 (378.51x) |
| packed double encode | 2.00 | 840.10 (420.05x) | 561.10 (280.55x) | 75.86 (37.93x) | 443.98 (221.99x) |
| packed double decode | 4.52 | 960.94 (212.60x) | 2067.74 (457.46x) | 79.52 (17.59x) | 2549.14 (563.97x) |
| packed uint64 encode | 1287.21 | 4599.65 (3.57x) | 4028.31 (3.13x) | 2134.12 (1.66x) | 3442.55 (2.67x) |
| packed uint64 decode | 1790.29 | 2779.12 (1.55x) | 8847.53 (4.94x) | 2801.87 (1.57x) | 8055.60 (4.50x) |
| packed uint32 encode | 925.41 | 3609.28 (3.90x) | 3261.92 (3.52x) | 1721.72 (1.86x) | 2993.07 (3.23x) |
| packed uint32 decode | 1311.25 | 2430.17 (1.85x) | 3264.92 (2.49x) | 1988.14 (1.52x) | 5951.69 (4.54x) |
| packed int64 encode | 1586.35 | 11056.15 (6.97x) | 6060.76 (3.82x) | 2904.42 (1.83x) | 4224.50 (2.66x) |
| packed int64 decode | 2750.56 | 3360.51 (1.22x) | 10286.92 (3.74x) | 4627.77 (1.68x) | 9328.53 (3.39x) |
| packed sint32 encode | 782.58 | 3037.38 (3.88x) | 2796.10 (3.57x) | 1525.03 (1.95x) | 3393.35 (4.34x) |
| packed sint32 decode | 953.20 | 2548.29 (2.67x) | 3182.78 (3.34x) | 1120.07 (1.18x) | 3538.98 (3.71x) |
| packed sint64 encode | 1423.54 | 4939.68 (3.47x) | 4284.89 (3.01x) | 2400.30 (1.69x) | 4124.58 (2.90x) |
| packed sint64 decode | 2038.93 | 3061.40 (1.50x) | 9662.63 (4.74x) | 3010.41 (1.48x) | 8395.29 (4.12x) |
| packed bool encode | 2.01 | 1329.20 (661.29x) | 519.42 (258.42x) | 16.16 (8.04x) | 2205.21 (1097.12x) |
| packed bool decode | 266.76 | 1531.24 (5.74x) | 2552.30 (9.57x) | 882.68 (3.31x) | 1796.57 (6.73x) |
| packed enum encode | 271.86 | 2710.40 (9.97x) | 1812.57 (6.67x) | 1142.11 (4.20x) | 2496.40 (9.18x) |
| packed enum decode | 153.34 | 1542.62 (10.06x) | 2901.31 (18.92x) | 690.96 (4.51x) | 2404.49 (15.68x) |
| large map encode | 4041.28 | 16610.33 (4.11x) | 9723.66 (2.41x) | 21941.70 (5.43x) | 191772.68 (47.45x) |
| shuffled large map deterministic binary encode | 27751.73 | — | — | 89980.90 (3.24x) | 367270.84 (13.23x) |
| large map decode | 25188.11 | 91165.39 (3.62x) | 90939.08 (3.61x) | 91693.80 (3.64x) | 266062.06 (10.56x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound `Duration`, non-empty/escaped-input parse and empty `Struct`, object/escaped-object parse/list/string-scalar/escaped-string-scalar `Value` (including default-like scalar and empty object/list kinds),
`FieldMask` (non-empty, escaped JSON parse input, and empty), escaped-input parse/short-fraction parse/micro/nano/offset/min/pre/post/max-bound `Timestamp`, `Empty`, min/zero/positive/number-input parse/negative/max `Int64Value`, negative/zero/positive finite/string-input parse `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), negative/zero/positive finite/string-input parse `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), zero/normal/number-input parse/max `UInt64Value`, min/zero/positive/string-input parse/negative/max `Int32Value`, zero/normal/string-input parse/max `UInt32Value`, true/false `BoolValue`, non-empty/escape-input parse/empty `StringValue`, base64/base64url parse/empty `BytesValue`, and recursive nested `Any` payloads), direct zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound Duration, non-empty/escaped-input parse/empty FieldMask, and escaped-input parse/short-fraction parse/micro/nano/offset/min/pre/post/max-bound Timestamp WKT JSON plus other direct WKT JSON, including non-empty/escaped-input parse/empty `Struct`, object/escaped-object parse/list/string-scalar/escaped-string-scalar `Value`, and empty `ListValue`, TextFormat, packed scalars, large bytes,
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
