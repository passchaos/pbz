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

Latest accepted comparison (`/tmp/pbz-compare-bytes-url-json-isolated.log`,
summarized in `/tmp/pbz-summary-bytes-url-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 17.78 | 124.70 (7.01x) | 50.10 (2.82x) | 114.06 (6.42x) | 838.07 (47.14x) |
| binary decode | 89.19 | 302.39 (3.39x) | 233.29 (2.62x) | 218.21 (2.45x) | 902.98 (10.12x) |
| unknown fields count by number | 3.57 | — | — | 165.51 (46.36x) | — |
| deterministic binary encode | 58.74 | — | — | 132.91 (2.26x) | 1070.39 (18.22x) |
| scalarmix encode | 19.04 | 118.83 (6.24x) | 49.80 (2.62x) | 30.67 (1.61x) | 218.31 (11.47x) |
| scalarmix decode | 34.09 | 148.33 (4.35x) | 183.67 (5.39x) | 86.35 (2.53x) | 320.41 (9.40x) |
| textbytes encode | 13.53 | 82.65 (6.11x) | 33.90 (2.51x) | 116.76 (8.63x) | 151.83 (11.22x) |
| textbytes decode | 47.33 | 390.93 (8.26x) | 239.72 (5.06x) | 166.39 (3.52x) | 693.36 (14.65x) |
| largebytes encode | 17.54 | 2713.31 (154.69x) | 2688.23 (153.26x) | 2676.44 (152.59x) | 2708.32 (154.41x) |
| largebytes decode | 88.65 | 5596.66 (63.13x) | 3116.24 (35.15x) | 2733.25 (30.83x) | 22924.21 (258.59x) |
| presencemix encode | 18.29 | 56.53 (3.09x) | 26.95 (1.47x) | 54.34 (2.97x) | 227.93 (12.46x) |
| presencemix decode | 57.59 | 133.20 (2.31x) | 107.36 (1.86x) | 163.11 (2.83x) | 493.80 (8.57x) |
| complex encode | 51.31 | 131.22 (2.56x) | 95.12 (1.85x) | 160.33 (3.12x) | 952.41 (18.56x) |
| complex decode | 170.68 | 394.39 (2.31x) | 337.15 (1.98x) | 387.76 (2.27x) | 1337.76 (7.84x) |
| complex deterministic binary encode | 91.85 | — | — | 172.95 (1.88x) | 1110.37 (12.09x) |
| complex JSON stringify | 279.90 | — | — | 4873.52 (17.41x) | 5755.89 (20.56x) |
| complex JSON parse | 2487.64 | — | — | 11951.40 (4.80x) | 6985.70 (2.81x) |
| complex TextFormat format | 251.17 | — | — | 3780.87 (15.05x) | 4813.87 (19.17x) |
| complex TextFormat parse | 1899.56 | — | — | 6927.41 (3.65x) | 8074.59 (4.25x) |
| packed int32 encode | 644.54 | 3174.29 (4.92x) | 2506.06 (3.89x) | 1257.31 (1.95x) | 2747.48 (4.26x) |
| packed int32 decode | 692.35 | 1903.32 (2.75x) | 3203.63 (4.63x) | 955.97 (1.38x) | 3223.08 (4.66x) |
| JSON stringify | 155.57 | — | — | 3013.27 (19.37x) | 2006.55 (12.90x) |
| JSON parse | 1695.94 | — | — | 7464.29 (4.40x) | 4275.16 (2.52x) |
| Any WKT JSON stringify | 130.59 | — | — | 1884.50 (14.43x) | 925.27 (7.09x) |
| Any WKT JSON parse | 509.23 | — | — | 2966.84 (5.83x) | 1503.89 (2.95x) |
| Any PlusDuration WKT JSON parse | 511.50 | — | — | 2997.33 (5.86x) | 1486.16 (2.91x) |
| Any ShortFractionDuration WKT JSON parse | 508.81 | — | — | 2941.13 (5.78x) | 1424.96 (2.80x) |
| Any MicroDuration WKT JSON stringify | 132.94 | — | — | 1896.12 (14.26x) | 937.81 (7.05x) |
| Any MicroDuration WKT JSON parse | 512.93 | — | — | 2978.97 (5.81x) | 1437.47 (2.80x) |
| Any NanoDuration WKT JSON stringify | 131.31 | — | — | 1919.23 (14.62x) | 953.98 (7.27x) |
| Any NanoDuration WKT JSON parse | 517.73 | — | — | 2995.61 (5.79x) | 1535.76 (2.97x) |
| Any NegativeDuration WKT JSON stringify | 132.99 | — | — | 1941.76 (14.60x) | 948.76 (7.13x) |
| Any NegativeDuration WKT JSON parse | 516.74 | — | — | 3108.36 (6.02x) | 1463.46 (2.83x) |
| Any FractionalNegativeDuration WKT JSON stringify | 128.43 | — | — | 1892.79 (14.74x) | 929.68 (7.24x) |
| Any FractionalNegativeDuration WKT JSON parse | 509.91 | — | — | 3046.90 (5.98x) | 1563.84 (3.07x) |
| Any MaxDuration WKT JSON stringify | 117.40 | — | — | 1746.99 (14.88x) | 1051.45 (8.96x) |
| Any MaxDuration WKT JSON parse | 523.33 | — | — | 2952.33 (5.64x) | 1745.70 (3.34x) |
| Any MinDuration WKT JSON stringify | 117.00 | — | — | 1761.91 (15.06x) | 1084.56 (9.27x) |
| Any MinDuration WKT JSON parse | 521.19 | — | — | 3010.37 (5.78x) | 1504.91 (2.89x) |
| Any ZeroDuration WKT JSON stringify | 108.38 | — | — | 913.51 (8.43x) | 934.07 (8.62x) |
| Any ZeroDuration WKT JSON parse | 464.21 | — | — | 2250.46 (4.85x) | 1423.82 (3.07x) |
| Any FieldMask WKT JSON stringify | 222.25 | — | — | 1737.29 (7.82x) | 1480.37 (6.66x) |
| Any FieldMask WKT JSON parse | 707.93 | — | — | 3139.42 (4.43x) | 2309.58 (3.26x) |
| Any EmptyFieldMask WKT JSON stringify | 109.60 | — | — | 916.17 (8.36x) | 742.61 (6.78x) |
| Any EmptyFieldMask WKT JSON parse | 435.02 | — | — | 2143.31 (4.93x) | 1188.16 (2.73x) |
| Any Timestamp WKT JSON stringify | 180.66 | — | — | 2012.06 (11.14x) | 1055.39 (5.84x) |
| Any Timestamp WKT JSON parse | 563.78 | — | — | 3005.12 (5.33x) | 1632.14 (2.89x) |
| Any ShortFraction Timestamp WKT JSON parse | 560.99 | — | — | 2995.80 (5.34x) | 1645.44 (2.93x) |
| Any Micro Timestamp WKT JSON stringify | 189.02 | — | — | 2016.19 (10.67x) | 1046.35 (5.54x) |
| Any Micro Timestamp WKT JSON parse | 576.56 | — | — | 3022.06 (5.24x) | 1596.14 (2.77x) |
| Any Nano Timestamp WKT JSON stringify | 179.64 | — | — | 2018.96 (11.24x) | 977.26 (5.44x) |
| Any Nano Timestamp WKT JSON parse | 583.39 | — | — | 3018.04 (5.17x) | 1541.92 (2.64x) |
| Any Offset Timestamp WKT JSON parse | 592.86 | — | — | 3037.38 (5.12x) | 1559.38 (2.63x) |
| Any PreEpoch Timestamp WKT JSON stringify | 146.28 | — | — | 1936.42 (13.24x) | 937.31 (6.41x) |
| Any PreEpoch Timestamp WKT JSON parse | 558.65 | — | — | 3019.81 (5.41x) | 1462.83 (2.62x) |
| Any Max Timestamp WKT JSON stringify | 163.73 | — | — | 2035.69 (12.43x) | 1016.15 (6.21x) |
| Any Max Timestamp WKT JSON parse | 586.38 | — | — | 3077.73 (5.25x) | 1497.90 (2.55x) |
| Any Min Timestamp WKT JSON stringify | 162.62 | — | — | 1923.99 (11.83x) | 940.33 (5.78x) |
| Any Min Timestamp WKT JSON parse | 551.52 | — | — | 3003.50 (5.45x) | 1592.43 (2.89x) |
| Any Empty WKT JSON stringify | 93.46 | — | — | 908.28 (9.72x) | 589.19 (6.30x) |
| Any Empty WKT JSON parse | 329.80 | — | — | 2122.69 (6.44x) | 1274.37 (3.86x) |
| Any Struct WKT JSON stringify | 637.17 | — | — | 5842.41 (9.17x) | 5978.78 (9.38x) |
| Any Struct WKT JSON parse | 1749.37 | — | — | 11011.90 (6.29x) | 8322.92 (4.76x) |
| Any EmptyStruct WKT JSON stringify | 120.40 | — | — | 908.93 (7.55x) | 969.37 (8.05x) |
| Any EmptyStruct WKT JSON parse | 431.13 | — | — | 2225.09 (5.16x) | 1456.35 (3.38x) |
| Any Value WKT JSON stringify | 661.19 | — | — | 5860.27 (8.86x) | 6297.13 (9.52x) |
| Any Value WKT JSON parse | 1785.54 | — | — | 11350.00 (6.36x) | 9035.36 (5.06x) |
| Any NullValue WKT JSON stringify | 130.05 | — | — | 2254.23 (17.33x) | 874.41 (6.72x) |
| Any NullValue WKT JSON parse | 452.98 | — | — | 4130.55 (9.12x) | 1583.28 (3.50x) |
| Any StringScalarValue WKT JSON stringify | 146.20 | — | — | 2270.51 (15.53x) | 1033.77 (7.07x) |
| Any StringScalarValue WKT JSON parse | 506.15 | — | — | 3612.26 (7.14x) | 1819.48 (3.59x) |
| Any EmptyStringScalarValue WKT JSON stringify | 134.29 | — | — | 2282.91 (17.00x) | 995.37 (7.41x) |
| Any EmptyStringScalarValue WKT JSON parse | 476.41 | — | — | 3630.27 (7.62x) | 1492.98 (3.13x) |
| Any NumberValue WKT JSON stringify | 187.35 | — | — | 2525.30 (13.48x) | 1126.84 (6.01x) |
| Any NumberValue WKT JSON parse | 500.58 | — | — | 3670.27 (7.33x) | 1497.11 (2.99x) |
| Any ZeroNumberValue WKT JSON stringify | 141.34 | — | — | 2471.49 (17.49x) | 882.60 (6.24x) |
| Any ZeroNumberValue WKT JSON parse | 496.07 | — | — | 3649.38 (7.36x) | 1469.72 (2.96x) |
| Any BoolScalarValue WKT JSON stringify | 134.62 | — | — | 2249.88 (16.71x) | 857.10 (6.37x) |
| Any BoolScalarValue WKT JSON parse | 454.33 | — | — | 3562.19 (7.84x) | 1461.02 (3.22x) |
| Any FalseBoolScalarValue WKT JSON stringify | 129.19 | — | — | 2252.87 (17.44x) | 937.84 (7.26x) |
| Any FalseBoolScalarValue WKT JSON parse | 454.27 | — | — | 3575.90 (7.87x) | 1622.84 (3.57x) |
| Any ListKindValue WKT JSON stringify | 505.25 | — | — | 5552.32 (10.99x) | 4901.88 (9.70x) |
| Any ListKindValue WKT JSON parse | 1395.11 | — | — | 9857.22 (7.07x) | 7505.83 (5.38x) |
| Any EmptyStructKindValue WKT JSON stringify | 148.77 | — | — | 2911.00 (19.57x) | 1219.39 (8.20x) |
| Any EmptyStructKindValue WKT JSON parse | 487.31 | — | — | 5373.54 (11.03x) | 2090.89 (4.29x) |
| Any EmptyListKindValue WKT JSON stringify | 144.33 | — | — | 2888.09 (20.01x) | 1050.45 (7.28x) |
| Any EmptyListKindValue WKT JSON parse | 496.46 | — | — | 4335.81 (8.73x) | 1881.42 (3.79x) |
| Any DoubleValue WKT JSON stringify | 192.23 | — | — | 1791.44 (9.32x) | 787.54 (4.10x) |
| Any DoubleValue WKT JSON parse | 513.06 | — | — | 2728.16 (5.32x) | 1444.01 (2.81x) |
| Any DoubleValue String WKT JSON parse | 522.10 | — | — | 2750.05 (5.27x) | 1440.35 (2.76x) |
| Any NegativeDoubleValue WKT JSON stringify | 192.25 | — | — | 1794.65 (9.33x) | 756.25 (3.93x) |
| Any NegativeDoubleValue WKT JSON parse | 513.51 | — | — | 2734.23 (5.32x) | 1478.68 (2.88x) |
| Any ZeroDoubleValue WKT JSON stringify | 165.18 | — | — | 920.92 (5.58x) | 718.87 (4.35x) |
| Any ZeroDoubleValue WKT JSON parse | 509.57 | — | — | 2175.02 (4.27x) | 1324.29 (2.60x) |
| Any DoubleValue NaN WKT JSON stringify | 156.13 | — | — | 1569.92 (10.06x) | 722.33 (4.63x) |
| Any DoubleValue NaN WKT JSON parse | 506.11 | — | — | 2648.53 (5.23x) | 1302.89 (2.57x) |
| Any DoubleValue Infinity WKT JSON stringify | 160.96 | — | — | 1557.47 (9.68x) | 696.95 (4.33x) |
| Any DoubleValue Infinity WKT JSON parse | 508.94 | — | — | 2682.42 (5.27x) | 1481.64 (2.91x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 166.85 | — | — | 1549.74 (9.29x) | 736.65 (4.42x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 513.42 | — | — | 2682.32 (5.22x) | 1530.00 (2.98x) |
| Any FloatValue WKT JSON stringify | 202.71 | — | — | 1730.02 (8.53x) | 774.31 (3.82x) |
| Any FloatValue WKT JSON parse | 519.55 | — | — | 2783.38 (5.36x) | 1349.26 (2.60x) |
| Any FloatValue String WKT JSON parse | 524.66 | — | — | 2706.57 (5.16x) | 1435.80 (2.74x) |
| Any NegativeFloatValue WKT JSON stringify | 205.85 | — | — | 1726.73 (8.39x) | 749.73 (3.64x) |
| Any NegativeFloatValue WKT JSON parse | 514.68 | — | — | 2699.04 (5.24x) | 1291.62 (2.51x) |
| Any ZeroFloatValue WKT JSON stringify | 173.32 | — | — | 1393.54 (8.04x) | 686.50 (3.96x) |
| Any ZeroFloatValue WKT JSON parse | 512.65 | — | — | 3233.80 (6.31x) | 1278.90 (2.49x) |
| Any FloatValue NaN WKT JSON stringify | 160.65 | — | — | 1606.12 (10.00x) | 684.58 (4.26x) |
| Any FloatValue NaN WKT JSON parse | 506.18 | — | — | 2626.49 (5.19x) | 1433.15 (2.83x) |
| Any FloatValue Infinity WKT JSON stringify | 171.76 | — | — | 1548.37 (9.01x) | 723.02 (4.21x) |
| Any FloatValue Infinity WKT JSON parse | 510.90 | — | — | 2796.85 (5.47x) | 1455.38 (2.85x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 167.33 | — | — | 1761.56 (10.53x) | 697.99 (4.17x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 512.74 | — | — | 2642.84 (5.15x) | 1388.24 (2.71x) |
| Any Int64Value WKT JSON stringify | 174.37 | — | — | 1578.31 (9.05x) | 825.64 (4.73x) |
| Any Int64Value WKT JSON parse | 541.99 | — | — | 2796.67 (5.16x) | 1551.38 (2.86x) |
| Any Int64Value Number WKT JSON parse | 547.21 | — | — | 2769.12 (5.06x) | 1528.71 (2.79x) |
| Any ZeroInt64Value WKT JSON stringify | 164.65 | — | — | 913.51 (5.55x) | 794.61 (4.83x) |
| Any ZeroInt64Value WKT JSON parse | 518.37 | — | — | 2158.35 (4.16x) | 1446.09 (2.79x) |
| Any NegativeInt64Value WKT JSON stringify | 174.76 | — | — | 1568.88 (8.98x) | 801.71 (4.59x) |
| Any NegativeInt64Value WKT JSON parse | 554.02 | — | — | 2920.67 (5.27x) | 1632.34 (2.95x) |
| Any MinInt64Value WKT JSON stringify | 174.68 | — | — | 1579.93 (9.04x) | 820.93 (4.70x) |
| Any MinInt64Value WKT JSON parse | 563.39 | — | — | 2820.24 (5.01x) | 1653.10 (2.93x) |
| Any MaxInt64Value WKT JSON stringify | 176.62 | — | — | 1573.34 (8.91x) | 828.47 (4.69x) |
| Any MaxInt64Value WKT JSON parse | 546.58 | — | — | 2809.54 (5.14x) | 1626.32 (2.98x) |
| Any UInt64Value WKT JSON stringify | 173.97 | — | — | 1573.03 (9.04x) | 866.26 (4.98x) |
| Any UInt64Value WKT JSON parse | 554.25 | — | — | 2805.24 (5.06x) | 1559.62 (2.81x) |
| Any UInt64Value Number WKT JSON parse | 548.36 | — | — | 2770.32 (5.05x) | 1457.41 (2.66x) |
| Any ZeroUInt64Value WKT JSON stringify | 170.32 | — | — | 958.05 (5.63x) | 814.97 (4.78x) |
| Any ZeroUInt64Value WKT JSON parse | 522.06 | — | — | 2196.90 (4.21x) | 1467.40 (2.81x) |
| Any MaxUInt64Value WKT JSON stringify | 179.40 | — | — | 1562.67 (8.71x) | 856.21 (4.77x) |
| Any MaxUInt64Value WKT JSON parse | 562.68 | — | — | 2833.29 (5.04x) | 1817.10 (3.23x) |
| Any Int32Value WKT JSON stringify | 172.14 | — | — | 1552.18 (9.02x) | 711.44 (4.13x) |
| Any Int32Value WKT JSON parse | 527.96 | — | — | 2826.51 (5.35x) | 1381.37 (2.62x) |
| Any Int32Value String WKT JSON parse | 533.99 | — | — | 2682.94 (5.02x) | 1450.74 (2.72x) |
| Any ZeroInt32Value WKT JSON stringify | 178.68 | — | — | 923.90 (5.17x) | 699.66 (3.92x) |
| Any ZeroInt32Value WKT JSON parse | 520.88 | — | — | 2148.42 (4.12x) | 1337.47 (2.57x) |
| Any NegativeInt32Value WKT JSON stringify | 173.88 | — | — | 1549.34 (8.91x) | 706.76 (4.06x) |
| Any NegativeInt32Value WKT JSON parse | 529.71 | — | — | 2691.30 (5.08x) | 1395.42 (2.63x) |
| Any MinInt32Value WKT JSON stringify | 177.57 | — | — | 1545.71 (8.70x) | 748.81 (4.22x) |
| Any MinInt32Value WKT JSON parse | 535.77 | — | — | 2707.72 (5.05x) | 1429.93 (2.67x) |
| Any MaxInt32Value WKT JSON stringify | 178.97 | — | — | 1556.08 (8.69x) | 736.61 (4.12x) |
| Any MaxInt32Value WKT JSON parse | 534.79 | — | — | 2678.74 (5.01x) | 1341.74 (2.51x) |
| Any UInt32Value WKT JSON stringify | 170.28 | — | — | 1554.00 (9.13x) | 709.61 (4.17x) |
| Any UInt32Value WKT JSON parse | 528.12 | — | — | 2674.21 (5.06x) | 1315.71 (2.49x) |
| Any UInt32Value String WKT JSON parse | 537.10 | — | — | 2704.01 (5.03x) | 1455.65 (2.71x) |
| Any ZeroUInt32Value WKT JSON stringify | 179.14 | — | — | 914.21 (5.10x) | 676.36 (3.78x) |
| Any ZeroUInt32Value WKT JSON parse | 524.87 | — | — | 2156.48 (4.11x) | 1331.05 (2.54x) |
| Any MaxUInt32Value WKT JSON stringify | 189.06 | — | — | 1595.06 (8.44x) | 709.41 (3.75x) |
| Any MaxUInt32Value WKT JSON parse | 533.82 | — | — | 2711.09 (5.08x) | 1405.59 (2.63x) |
| Any BoolValue WKT JSON stringify | 167.60 | — | — | 1525.11 (9.10x) | 703.62 (4.20x) |
| Any BoolValue WKT JSON parse | 479.00 | — | — | 2625.02 (5.48x) | 1212.62 (2.53x) |
| Any FalseBoolValue WKT JSON stringify | 171.70 | — | — | 919.43 (5.35x) | 661.41 (3.85x) |
| Any FalseBoolValue WKT JSON parse | 479.80 | — | — | 3260.18 (6.79x) | 1295.35 (2.70x) |
| Any StringValue WKT JSON stringify | 198.16 | — | — | 1562.11 (7.88x) | 742.33 (3.75x) |
| Any StringValue WKT JSON parse | 541.49 | — | — | 2672.00 (4.93x) | 1332.28 (2.46x) |
| Any EmptyStringValue WKT JSON stringify | 191.14 | — | — | 1209.37 (6.33x) | 741.27 (3.88x) |
| Any EmptyStringValue WKT JSON parse | 509.67 | — | — | 3233.58 (6.34x) | 1307.28 (2.56x) |
| Any BytesValue WKT JSON stringify | 190.85 | — | — | 1577.08 (8.26x) | 801.13 (4.20x) |
| Any BytesValue WKT JSON parse | 554.08 | — | — | 2700.34 (4.87x) | 1378.82 (2.49x) |
| Any BytesValue URL WKT JSON parse | 575.31 | — | — | 4243.61 (7.38x) | 1509.80 (2.62x) |
| Any EmptyBytesValue WKT JSON stringify | 182.15 | — | — | 926.40 (5.09x) | 719.56 (3.95x) |
| Any EmptyBytesValue WKT JSON parse | 517.57 | — | — | 2259.77 (4.37x) | 1396.49 (2.70x) |
| Nested Any WKT JSON stringify | 298.73 | — | — | 2470.30 (8.27x) | 1369.00 (4.58x) |
| Nested Any WKT JSON parse | 850.64 | — | — | 4259.33 (5.01x) | 2607.21 (3.06x) |
| Duration JSON stringify | 58.22 | — | — | 969.43 (16.65x) | 346.04 (5.94x) |
| Duration JSON parse | 7.78 | — | — | 1456.83 (187.25x) | 385.10 (49.50x) |
| PlusDuration JSON parse | 7.86 | — | — | 1456.19 (185.27x) | 375.27 (47.74x) |
| ShortFractionDuration JSON parse | 6.47 | — | — | 1415.69 (218.81x) | 361.98 (55.95x) |
| MicroDuration JSON stringify | 59.71 | — | — | 969.27 (16.23x) | 374.72 (6.28x) |
| MicroDuration JSON parse | 9.80 | — | — | 1462.19 (149.20x) | 355.77 (36.30x) |
| NanoDuration JSON stringify | 57.15 | — | — | 997.61 (17.46x) | 376.35 (6.59x) |
| NanoDuration JSON parse | 12.40 | — | — | 1469.88 (118.54x) | 372.44 (30.04x) |
| NegativeDuration JSON stringify | 58.26 | — | — | 1002.19 (17.20x) | 399.30 (6.85x) |
| NegativeDuration JSON parse | 7.90 | — | — | 1499.45 (189.80x) | 370.09 (46.85x) |
| FractionalNegativeDuration JSON stringify | 58.24 | — | — | 970.70 (16.67x) | 400.17 (6.87x) |
| FractionalNegativeDuration JSON parse | 7.89 | — | — | 1452.62 (184.11x) | 349.13 (44.25x) |
| MaxDuration JSON stringify | 48.64 | — | — | 859.72 (17.68x) | 400.06 (8.22x) |
| MaxDuration JSON parse | 22.24 | — | — | 1431.15 (64.35x) | 386.13 (17.36x) |
| MinDuration JSON stringify | 49.22 | — | — | 867.43 (17.62x) | 415.02 (8.43x) |
| MinDuration JSON parse | 22.51 | — | — | 1442.37 (64.08x) | 383.89 (17.05x) |
| ZeroDuration JSON stringify | 44.92 | — | — | 816.15 (18.17x) | 335.05 (7.46x) |
| ZeroDuration JSON parse | 5.56 | — | — | 1368.63 (246.16x) | 306.68 (55.16x) |
| FieldMask JSON stringify | 108.40 | — | — | 882.97 (8.15x) | 637.90 (5.88x) |
| FieldMask JSON parse | 156.25 | — | — | 1667.63 (10.67x) | 836.07 (5.35x) |
| EmptyFieldMask JSON stringify | 40.84 | — | — | 610.00 (14.94x) | 182.85 (4.48x) |
| EmptyFieldMask JSON parse | 2.78 | — | — | 943.15 (339.26x) | 168.52 (60.62x) |
| Timestamp JSON stringify | 95.80 | — | — | 1137.50 (11.87x) | 438.97 (4.58x) |
| Timestamp JSON parse | 41.54 | — | — | 1498.63 (36.08x) | 429.80 (10.35x) |
| ShortFraction Timestamp JSON parse | 39.89 | — | — | 1472.00 (36.90x) | 408.02 (10.23x) |
| Micro Timestamp JSON stringify | 94.98 | — | — | 1629.44 (17.16x) | 447.53 (4.71x) |
| Micro Timestamp JSON parse | 42.91 | — | — | 1508.30 (35.15x) | 426.62 (9.94x) |
| Nano Timestamp JSON stringify | 95.23 | — | — | 1197.78 (12.58x) | 420.41 (4.41x) |
| Nano Timestamp JSON parse | 45.37 | — | — | 1534.84 (33.83x) | 428.41 (9.44x) |
| Offset Timestamp JSON parse | 50.99 | — | — | 1538.86 (30.18x) | 466.24 (9.14x) |
| PreEpoch Timestamp JSON stringify | 66.78 | — | — | 1074.74 (16.09x) | 399.56 (5.98x) |
| PreEpoch Timestamp JSON parse | 40.10 | — | — | 1475.75 (36.80x) | 401.06 (10.00x) |
| Max Timestamp JSON stringify | 79.07 | — | — | 1200.28 (15.18x) | 415.39 (5.25x) |
| Max Timestamp JSON parse | 47.07 | — | — | 1532.56 (32.56x) | 434.20 (9.22x) |
| Min Timestamp JSON stringify | 81.16 | — | — | 1065.97 (13.13x) | 395.10 (4.87x) |
| Min Timestamp JSON parse | 37.84 | — | — | 1451.06 (38.35x) | 388.87 (10.28x) |
| Empty JSON stringify | 20.57 | — | — | 495.10 (24.07x) | 83.93 (4.08x) |
| Empty JSON parse | 67.29 | — | — | 717.80 (10.67x) | 185.13 (2.75x) |
| Struct JSON stringify | 176.26 | — | — | 5812.52 (32.98x) | 3065.62 (17.39x) |
| Struct JSON parse | 850.38 | — | — | 10863.90 (12.78x) | 4548.45 (5.35x) |
| EmptyStruct JSON stringify | 41.05 | — | — | 697.87 (17.00x) | 321.60 (7.83x) |
| EmptyStruct JSON parse | 89.45 | — | — | 2014.17 (22.52x) | 368.88 (4.12x) |
| Value JSON stringify | 183.09 | — | — | 6828.40 (37.30x) | 3001.40 (16.39x) |
| Value JSON parse | 866.68 | — | — | 12137.10 (14.00x) | 4834.11 (5.58x) |
| NullValue JSON stringify | 40.44 | — | — | 1319.24 (32.62x) | 211.32 (5.23x) |
| NullValue JSON parse | 65.65 | — | — | 2478.47 (37.75x) | 322.26 (4.91x) |
| StringScalarValue JSON stringify | 47.62 | — | — | 1348.33 (28.31x) | 263.62 (5.54x) |
| StringScalarValue JSON parse | 136.07 | — | — | 2101.21 (15.44x) | 416.88 (3.06x) |
| EmptyStringScalarValue JSON stringify | 45.86 | — | — | 1335.36 (29.12x) | 263.19 (5.74x) |
| EmptyStringScalarValue JSON parse | 82.94 | — | — | 2075.64 (25.03x) | 338.16 (4.08x) |
| NumberValue JSON stringify | 73.63 | — | — | 1550.83 (21.06x) | 322.89 (4.39x) |
| NumberValue JSON parse | 127.85 | — | — | 2249.54 (17.60x) | 399.00 (3.12x) |
| ZeroNumberValue JSON stringify | 51.26 | — | — | 1507.38 (29.41x) | 272.62 (5.32x) |
| ZeroNumberValue JSON parse | 125.83 | — | — | 2116.69 (16.82x) | 365.33 (2.90x) |
| BoolScalarValue JSON stringify | 40.61 | — | — | 1325.69 (32.64x) | 224.78 (5.54x) |
| BoolScalarValue JSON parse | 65.40 | — | — | 2055.58 (31.43x) | 304.63 (4.66x) |
| FalseBoolScalarValue JSON stringify | 40.53 | — | — | 1319.26 (32.55x) | 216.50 (5.34x) |
| FalseBoolScalarValue JSON parse | 66.05 | — | — | 2056.34 (31.13x) | 322.50 (4.88x) |
| ListKindValue JSON stringify | 141.71 | — | — | 6271.24 (44.25x) | 2273.59 (16.04x) |
| ListKindValue JSON parse | 671.63 | — | — | 10394.90 (15.48x) | 3835.47 (5.71x) |
| EmptyStructKindValue JSON stringify | 42.35 | — | — | 1928.21 (45.53x) | 496.97 (11.73x) |
| EmptyStructKindValue JSON parse | 107.03 | — | — | 3750.22 (35.04x) | 649.44 (6.07x) |
| EmptyListKindValue JSON stringify | 41.28 | — | — | 1918.99 (46.49x) | 343.70 (8.33x) |
| EmptyListKindValue JSON parse | 144.27 | — | — | 4004.03 (27.75x) | 565.94 (3.92x) |
| ListValue JSON stringify | 151.25 | — | — | 4718.79 (31.20x) | 2067.65 (13.67x) |
| ListValue JSON parse | 653.68 | — | — | 8541.93 (13.07x) | 3788.77 (5.80x) |
| EmptyListValue JSON stringify | 50.10 | — | — | 683.61 (13.64x) | 186.97 (3.73x) |
| EmptyListValue JSON parse | 126.08 | — | — | 2258.66 (17.91x) | 306.77 (2.43x) |
| DoubleValue JSON stringify | 68.60 | — | — | 848.03 (12.36x) | 194.96 (2.84x) |
| DoubleValue JSON parse | 112.57 | — | — | 1234.17 (10.96x) | 285.84 (2.54x) |
| DoubleValue String JSON parse | 114.80 | — | — | 1174.47 (10.23x) | 386.06 (3.36x) |
| NegativeDoubleValue JSON stringify | 124.06 | — | — | 851.66 (6.86x) | 184.76 (1.49x) |
| NegativeDoubleValue JSON parse | 142.51 | — | — | 1228.16 (8.62x) | 278.62 (1.96x) |
| ZeroDoubleValue JSON stringify | 70.86 | — | — | 783.96 (11.06x) | 135.80 (1.92x) |
| ZeroDoubleValue JSON parse | 131.63 | — | — | 1153.44 (8.76x) | 261.86 (1.99x) |
| DoubleValue NaN JSON stringify | 68.75 | — | — | 652.00 (9.48x) | 129.44 (1.88x) |
| DoubleValue NaN JSON parse | 128.52 | — | — | 1094.07 (8.51x) | 248.33 (1.93x) |
| DoubleValue Infinity JSON stringify | 73.23 | — | — | 659.89 (9.01x) | 115.27 (1.57x) |
| DoubleValue Infinity JSON parse | 133.66 | — | — | 1105.53 (8.27x) | 258.23 (1.93x) |
| DoubleValue NegativeInfinity JSON stringify | 75.50 | — | — | 651.62 (8.63x) | 138.23 (1.83x) |
| DoubleValue NegativeInfinity JSON parse | 139.51 | — | — | 1115.75 (8.00x) | 270.29 (1.94x) |
| FloatValue JSON stringify | 129.65 | — | — | 798.21 (6.16x) | 199.75 (1.54x) |
| FloatValue JSON parse | 127.82 | — | — | 1213.11 (9.49x) | 281.61 (2.20x) |
| FloatValue String JSON parse | 110.78 | — | — | 1154.62 (10.42x) | 365.72 (3.30x) |
| NegativeFloatValue JSON stringify | 128.47 | — | — | 797.00 (6.20x) | 178.06 (1.39x) |
| NegativeFloatValue JSON parse | 122.67 | — | — | 1215.86 (9.91x) | 274.92 (2.24x) |
| ZeroFloatValue JSON stringify | 47.56 | — | — | 742.67 (15.62x) | 131.22 (2.76x) |
| ZeroFloatValue JSON parse | 131.16 | — | — | 1181.05 (9.00x) | 247.09 (1.88x) |
| FloatValue NaN JSON stringify | 64.31 | — | — | 1017.32 (15.82x) | 118.47 (1.84x) |
| FloatValue NaN JSON parse | 106.35 | — | — | 1731.12 (16.28x) | 244.82 (2.30x) |
| FloatValue Infinity JSON stringify | 71.80 | — | — | 747.35 (10.41x) | 147.13 (2.05x) |
| FloatValue Infinity JSON parse | 130.27 | — | — | 1288.72 (9.89x) | 266.81 (2.05x) |
| FloatValue NegativeInfinity JSON stringify | 73.12 | — | — | 635.59 (8.69x) | 129.19 (1.77x) |
| FloatValue NegativeInfinity JSON parse | 132.74 | — | — | 1105.73 (8.33x) | 267.56 (2.02x) |
| Int64Value JSON stringify | 50.71 | — | — | 676.20 (13.33x) | 376.17 (7.42x) |
| Int64Value JSON parse | 127.45 | — | — | 1221.40 (9.58x) | 427.20 (3.35x) |
| Int64Value Number JSON parse | 128.92 | — | — | 1505.70 (11.68x) | 336.05 (2.61x) |
| ZeroInt64Value JSON stringify | 41.92 | — | — | 610.49 (14.56x) | 195.06 (4.65x) |
| ZeroInt64Value JSON parse | 105.42 | — | — | 1111.18 (10.54x) | 321.87 (3.05x) |
| NegativeInt64Value JSON stringify | 48.91 | — | — | 672.13 (13.74x) | 265.93 (5.44x) |
| NegativeInt64Value JSON parse | 128.35 | — | — | 1222.45 (9.52x) | 451.27 (3.52x) |
| MinInt64Value JSON stringify | 50.03 | — | — | 680.22 (13.60x) | 259.38 (5.18x) |
| MinInt64Value JSON parse | 135.17 | — | — | 1261.01 (9.33x) | 457.86 (3.39x) |
| MaxInt64Value JSON stringify | 50.06 | — | — | 674.06 (13.47x) | 280.04 (5.59x) |
| MaxInt64Value JSON parse | 133.62 | — | — | 1251.27 (9.36x) | 452.74 (3.39x) |
| UInt64Value JSON stringify | 50.38 | — | — | 679.52 (13.49x) | 276.63 (5.49x) |
| UInt64Value JSON parse | 124.83 | — | — | 1217.63 (9.75x) | 432.12 (3.46x) |
| UInt64Value Number JSON parse | 126.72 | — | — | 1278.70 (10.09x) | 345.19 (2.72x) |
| ZeroUInt64Value JSON stringify | 41.81 | — | — | 609.17 (14.57x) | 187.97 (4.50x) |
| ZeroUInt64Value JSON parse | 103.44 | — | — | 1094.29 (10.58x) | 323.04 (3.12x) |
| MaxUInt64Value JSON stringify | 51.11 | — | — | 683.54 (13.37x) | 281.36 (5.50x) |
| MaxUInt64Value JSON parse | 134.12 | — | — | 1278.41 (9.53x) | 440.36 (3.28x) |
| Int32Value JSON stringify | 46.15 | — | — | 720.16 (15.60x) | 126.25 (2.74x) |
| Int32Value JSON parse | 117.98 | — | — | 1370.89 (11.62x) | 280.97 (2.38x) |
| Int32Value String JSON parse | 114.51 | — | — | 1151.75 (10.06x) | 399.97 (3.49x) |
| ZeroInt32Value JSON stringify | 49.66 | — | — | 615.00 (12.38x) | 123.24 (2.48x) |
| ZeroInt32Value JSON parse | 116.13 | — | — | 1173.78 (10.11x) | 254.30 (2.19x) |
| NegativeInt32Value JSON stringify | 46.05 | — | — | 639.28 (13.88x) | 151.60 (3.29x) |
| NegativeInt32Value JSON parse | 117.14 | — | — | 1197.59 (10.22x) | 312.72 (2.67x) |
| MinInt32Value JSON stringify | 46.65 | — | — | 635.77 (13.63x) | 128.28 (2.75x) |
| MinInt32Value JSON parse | 123.13 | — | — | 1208.39 (9.81x) | 332.55 (2.70x) |
| MaxInt32Value JSON stringify | 47.07 | — | — | 634.92 (13.49x) | 130.48 (2.77x) |
| MaxInt32Value JSON parse | 123.24 | — | — | 1213.06 (9.84x) | 316.37 (2.57x) |
| UInt32Value JSON stringify | 45.97 | — | — | 629.29 (13.69x) | 126.01 (2.74x) |
| UInt32Value JSON parse | 118.21 | — | — | 1183.12 (10.01x) | 299.25 (2.53x) |
| UInt32Value String JSON parse | 115.08 | — | — | 1131.75 (9.83x) | 372.40 (3.24x) |
| ZeroUInt32Value JSON stringify | 47.39 | — | — | 613.29 (12.94x) | 137.36 (2.90x) |
| ZeroUInt32Value JSON parse | 113.46 | — | — | 1150.40 (10.14x) | 254.90 (2.25x) |
| MaxUInt32Value JSON stringify | 46.78 | — | — | 645.87 (13.81x) | 126.29 (2.70x) |
| MaxUInt32Value JSON parse | 123.53 | — | — | 1208.96 (9.79x) | 308.49 (2.50x) |
| BoolValue JSON stringify | 45.22 | — | — | 620.94 (13.73x) | 134.33 (2.97x) |
| BoolValue JSON parse | 60.28 | — | — | 1058.70 (17.56x) | 219.41 (3.64x) |
| FalseBoolValue JSON stringify | 45.10 | — | — | 650.53 (14.42x) | 140.02 (3.10x) |
| FalseBoolValue JSON parse | 61.13 | — | — | 1073.93 (17.57x) | 194.10 (3.18x) |
| StringValue JSON stringify | 51.98 | — | — | 1042.90 (20.06x) | 171.91 (3.31x) |
| StringValue JSON parse | 142.57 | — | — | 1174.65 (8.24x) | 283.99 (1.99x) |
| EmptyStringValue JSON stringify | 48.73 | — | — | 627.96 (12.89x) | 184.84 (3.79x) |
| EmptyStringValue JSON parse | 82.70 | — | — | 1591.25 (19.24x) | 236.60 (2.86x) |
| BytesValue JSON stringify | 50.10 | — | — | 992.58 (19.81x) | 218.31 (4.36x) |
| BytesValue JSON parse | 125.01 | — | — | 2005.70 (16.04x) | 324.78 (2.60x) |
| BytesValue URL JSON parse | 141.33 | — | — | 1971.99 (13.95x) | 296.81 (2.10x) |
| EmptyBytesValue JSON stringify | 41.63 | — | — | 958.02 (23.01x) | 204.90 (4.92x) |
| EmptyBytesValue JSON parse | 67.69 | — | — | 1526.61 (22.55x) | 260.83 (3.85x) |
| TextFormat format | 183.27 | — | — | 2500.21 (13.64x) | 2308.34 (12.60x) |
| TextFormat parse | 663.17 | — | — | 5134.53 (7.74x) | 6179.25 (9.32x) |
| packed fixed32 encode | 2.01 | 554.24 (275.74x) | 539.48 (268.40x) | 43.80 (21.79x) | 404.71 (201.35x) |
| packed fixed32 decode | 4.52 | 1046.95 (231.63x) | 1944.19 (430.13x) | 50.07 (11.08x) | 1623.10 (359.09x) |
| packed fixed64 encode | 2.01 | 571.68 (284.42x) | 561.34 (279.27x) | 75.83 (37.73x) | 402.46 (200.23x) |
| packed fixed64 decode | 4.51 | 1048.00 (232.37x) | 7937.37 (1759.95x) | 80.25 (17.79x) | 2311.44 (512.51x) |
| packed sfixed32 encode | 2.01 | 565.75 (281.47x) | 540.87 (269.09x) | 43.82 (21.80x) | 420.14 (209.02x) |
| packed sfixed32 decode | 4.54 | 1060.17 (233.52x) | 1971.41 (434.23x) | 49.21 (10.84x) | 1591.40 (350.53x) |
| packed sfixed64 encode | 2.06 | 571.03 (277.20x) | 561.21 (272.43x) | 75.69 (36.74x) | 411.02 (199.52x) |
| packed sfixed64 decode | 4.55 | 988.89 (217.34x) | 7913.51 (1739.23x) | 79.86 (17.55x) | 2305.00 (506.59x) |
| packed float encode | 2.01 | 814.96 (405.45x) | 542.19 (269.75x) | 45.10 (22.44x) | 371.24 (184.70x) |
| packed float decode | 4.53 | 1041.14 (229.83x) | 2087.63 (460.85x) | 50.08 (11.05x) | 1645.34 (363.21x) |
| packed double encode | 2.00 | 832.11 (416.06x) | 561.60 (280.80x) | 77.84 (38.92x) | 354.74 (177.37x) |
| packed double decode | 4.53 | 976.20 (215.50x) | 2054.41 (453.51x) | 81.83 (18.07x) | 2431.43 (536.74x) |
| packed uint64 encode | 1291.00 | 4617.05 (3.58x) | 4024.01 (3.12x) | 2129.10 (1.65x) | 3437.44 (2.66x) |
| packed uint64 decode | 1782.04 | 2784.42 (1.56x) | 8851.38 (4.97x) | 2872.61 (1.61x) | 8149.93 (4.57x) |
| packed uint32 encode | 931.85 | 3612.68 (3.88x) | 3253.49 (3.49x) | 1744.93 (1.87x) | 2903.65 (3.12x) |
| packed uint32 decode | 1292.93 | 2433.70 (1.88x) | 3252.75 (2.52x) | 1988.86 (1.54x) | 6048.38 (4.68x) |
| packed int64 encode | 1363.45 | 10996.39 (8.07x) | 6072.33 (4.45x) | 2923.90 (2.14x) | 4103.08 (3.01x) |
| packed int64 decode | 2745.22 | 3375.68 (1.23x) | 10341.27 (3.77x) | 4692.64 (1.71x) | 10282.78 (3.75x) |
| packed sint32 encode | 780.55 | 3031.76 (3.88x) | 2832.54 (3.63x) | 1530.18 (1.96x) | 3383.34 (4.33x) |
| packed sint32 decode | 917.57 | 2546.49 (2.78x) | 3184.02 (3.47x) | 1123.85 (1.22x) | 3541.17 (3.86x) |
| packed sint64 encode | 1421.13 | 4937.44 (3.47x) | 4304.41 (3.03x) | 2406.81 (1.69x) | 4128.20 (2.90x) |
| packed sint64 decode | 2032.96 | 3061.36 (1.51x) | 9765.66 (4.80x) | 2932.01 (1.44x) | 8893.68 (4.37x) |
| packed bool encode | 2.55 | 1332.76 (522.65x) | 518.65 (203.39x) | 16.29 (6.39x) | 2448.64 (960.25x) |
| packed bool decode | 262.81 | 1544.98 (5.88x) | 2558.81 (9.74x) | 808.34 (3.08x) | 1660.91 (6.32x) |
| packed enum encode | 272.36 | 2720.71 (9.99x) | 1796.65 (6.60x) | 1086.51 (3.99x) | 2587.91 (9.50x) |
| packed enum decode | 159.79 | 1527.66 (9.56x) | 2881.03 (18.03x) | 691.90 (4.33x) | 2325.62 (14.55x) |
| large map encode | 3967.51 | 16537.86 (4.17x) | 9761.58 (2.46x) | 22988.30 (5.79x) | 192798.22 (48.59x) |
| shuffled large map deterministic binary encode | 28252.44 | — | — | 104720.00 (3.71x) | 370593.17 (13.12x) |
| large map decode | 25635.60 | 90534.38 (3.53x) | 89704.88 (3.50x) | 92911.10 (3.62x) | 276300.96 (10.78x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded zero/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound `Duration`, non-empty and empty `Struct`, object/list/scalar `Value` (including default-like scalar and empty object/list kinds),
`FieldMask` (non-empty and empty), short-fraction parse/micro/nano/offset/min/pre/post/max-bound `Timestamp`, `Empty`, min/zero/positive/number-input parse/negative/max `Int64Value`, negative/zero/positive finite/string-input parse `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), negative/zero/positive finite/string-input parse `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), zero/normal/number-input parse/max `UInt64Value`, min/zero/positive/string-input parse/negative/max `Int32Value`, zero/normal/string-input parse/max `UInt32Value`, true/false `BoolValue`, non-empty/empty `StringValue`, base64/base64url parse/empty `BytesValue`, and recursive nested `Any` payloads), direct zero/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound Duration and short-fraction parse/micro/nano/offset/min/pre/post/max-bound Timestamp WKT JSON plus other direct WKT JSON, including empty `Struct` and empty `ListValue`, TextFormat, packed scalars, large bytes,
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
