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

Latest accepted comparison (`/tmp/pbz-compare-bytes-unpadded-json-final.log`,
summarized in `/tmp/pbz-summary-bytes-unpadded-json-final.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 31.11 | 100.95 (3.24x) | 52.62 (1.69x) | 139.98 (4.50x) | 870.06 (27.97x) |
| binary decode | 85.25 | 291.70 (3.42x) | 231.83 (2.72x) | 209.69 (2.46x) | 908.51 (10.66x) |
| unknown fields count by number | 3.57 | — | — | 161.41 (45.21x) | — |
| deterministic binary encode | 61.14 | — | — | 173.46 (2.84x) | 1305.85 (21.36x) |
| scalarmix encode | 20.05 | 146.89 (7.33x) | 47.10 (2.35x) | 31.07 (1.55x) | 209.41 (10.44x) |
| scalarmix decode | 36.22 | 211.94 (5.85x) | 180.77 (4.99x) | 87.06 (2.40x) | 308.80 (8.53x) |
| textbytes encode | 11.53 | 100.02 (8.67x) | 33.35 (2.89x) | 116.75 (10.13x) | 154.26 (13.38x) |
| textbytes decode | 46.86 | 382.12 (8.15x) | 237.07 (5.06x) | 162.95 (3.48x) | 666.43 (14.22x) |
| largebytes encode | 17.54 | 2705.04 (154.22x) | 2678.58 (152.71x) | 2692.81 (153.52x) | 2700.38 (153.96x) |
| largebytes decode | 88.29 | 5566.62 (63.05x) | 3014.35 (34.14x) | 2757.35 (31.23x) | 21495.15 (243.46x) |
| presencemix encode | 16.99 | 55.59 (3.27x) | 29.26 (1.72x) | 56.38 (3.32x) | 232.67 (13.69x) |
| presencemix decode | 56.02 | 131.86 (2.35x) | 112.78 (2.01x) | 165.05 (2.95x) | 505.69 (9.03x) |
| complex encode | 47.63 | 133.40 (2.80x) | 95.33 (2.00x) | 164.76 (3.46x) | 928.94 (19.50x) |
| complex decode | 168.28 | 539.35 (3.21x) | 347.10 (2.06x) | 392.15 (2.33x) | 1371.50 (8.15x) |
| complex deterministic binary encode | 94.98 | — | — | 171.15 (1.80x) | 1281.62 (13.49x) |
| complex JSON stringify | 283.02 | — | — | 4874.20 (17.22x) | 6183.15 (21.85x) |
| complex JSON parse | 2419.02 | — | — | 11847.50 (4.90x) | 7514.55 (3.11x) |
| complex TextFormat format | 251.78 | — | — | 3823.82 (15.19x) | 6020.44 (23.91x) |
| complex TextFormat parse | 1884.34 | — | — | 6937.95 (3.68x) | 8530.32 (4.53x) |
| packed int32 encode | 632.17 | 3151.86 (4.99x) | 2513.90 (3.98x) | 1240.20 (1.96x) | 2743.06 (4.34x) |
| packed int32 decode | 692.93 | 1896.46 (2.74x) | 3215.54 (4.64x) | 931.88 (1.34x) | 3029.98 (4.37x) |
| JSON stringify | 159.17 | — | — | 3019.07 (18.97x) | 2387.47 (15.00x) |
| JSON parse | 1522.90 | — | — | 7432.47 (4.88x) | 4643.83 (3.05x) |
| Any WKT JSON stringify | 137.44 | — | — | 1879.27 (13.67x) | 973.13 (7.08x) |
| Any WKT JSON parse | 518.81 | — | — | 2991.59 (5.77x) | 1521.69 (2.93x) |
| Any Duration Escape WKT JSON parse | 533.14 | — | — | 3009.24 (5.64x) | 1594.27 (2.99x) |
| Any PlusDuration WKT JSON parse | 520.29 | — | — | 2998.47 (5.76x) | 1543.46 (2.97x) |
| Any ShortFractionDuration WKT JSON parse | 514.38 | — | — | 2953.52 (5.74x) | 1503.56 (2.92x) |
| Any MicroDuration WKT JSON stringify | 147.84 | — | — | 1934.27 (13.08x) | 972.24 (6.58x) |
| Any MicroDuration WKT JSON parse | 522.68 | — | — | 3081.46 (5.90x) | 1526.99 (2.92x) |
| Any NanoDuration WKT JSON stringify | 140.96 | — | — | 1957.63 (13.89x) | 977.99 (6.94x) |
| Any NanoDuration WKT JSON parse | 525.98 | — | — | 3102.49 (5.90x) | 1543.03 (2.93x) |
| Any NegativeDuration WKT JSON stringify | 140.88 | — | — | 1941.66 (13.78x) | 1004.10 (7.13x) |
| Any NegativeDuration WKT JSON parse | 523.82 | — | — | 3104.46 (5.93x) | 1566.07 (2.99x) |
| Any FractionalNegativeDuration WKT JSON stringify | 132.05 | — | — | 1891.35 (14.32x) | 989.41 (7.49x) |
| Any FractionalNegativeDuration WKT JSON parse | 515.36 | — | — | 3069.56 (5.96x) | 1500.21 (2.91x) |
| Any MaxDuration WKT JSON stringify | 120.93 | — | — | 1874.02 (15.50x) | 978.34 (8.09x) |
| Any MaxDuration WKT JSON parse | 534.15 | — | — | 2974.66 (5.57x) | 1520.18 (2.85x) |
| Any MinDuration WKT JSON stringify | 121.71 | — | — | 2052.02 (16.86x) | 1001.86 (8.23x) |
| Any MinDuration WKT JSON parse | 536.42 | — | — | 3022.08 (5.63x) | 1525.25 (2.84x) |
| Any ZeroDuration WKT JSON stringify | 112.46 | — | — | 911.50 (8.11x) | 959.59 (8.53x) |
| Any ZeroDuration WKT JSON parse | 468.33 | — | — | 2254.88 (4.81x) | 1446.93 (3.09x) |
| Any FieldMask WKT JSON stringify | 235.18 | — | — | 1748.59 (7.44x) | 1416.38 (6.02x) |
| Any FieldMask WKT JSON parse | 706.27 | — | — | 3152.76 (4.46x) | 2065.29 (2.92x) |
| Any FieldMask Escape WKT JSON parse | 735.93 | — | — | 3245.56 (4.41x) | 2228.58 (3.03x) |
| Any EmptyFieldMask WKT JSON stringify | 114.40 | — | — | 913.28 (7.98x) | 779.43 (6.81x) |
| Any EmptyFieldMask WKT JSON parse | 439.80 | — | — | 2158.33 (4.91x) | 1290.74 (2.93x) |
| Any Timestamp WKT JSON stringify | 183.13 | — | — | 2029.21 (11.08x) | 1012.49 (5.53x) |
| Any Timestamp WKT JSON parse | 568.02 | — | — | 3024.85 (5.33x) | 1601.15 (2.82x) |
| Any Timestamp Escape WKT JSON parse | 586.82 | — | — | 3066.93 (5.23x) | 1744.36 (2.97x) |
| Any ShortFraction Timestamp WKT JSON parse | 564.64 | — | — | 3004.85 (5.32x) | 1576.68 (2.79x) |
| Any Micro Timestamp WKT JSON stringify | 188.95 | — | — | 2035.78 (10.77x) | 1004.33 (5.32x) |
| Any Micro Timestamp WKT JSON parse | 575.12 | — | — | 3038.28 (5.28x) | 1638.04 (2.85x) |
| Any Nano Timestamp WKT JSON stringify | 184.66 | — | — | 2038.54 (11.04x) | 1034.55 (5.60x) |
| Any Nano Timestamp WKT JSON parse | 579.22 | — | — | 3040.15 (5.25x) | 1629.45 (2.81x) |
| Any Offset Timestamp WKT JSON parse | 581.42 | — | — | 3046.88 (5.24x) | 1651.43 (2.84x) |
| Any PreEpoch Timestamp WKT JSON stringify | 150.66 | — | — | 1953.26 (12.96x) | 986.99 (6.55x) |
| Any PreEpoch Timestamp WKT JSON parse | 560.60 | — | — | 3048.28 (5.44x) | 1572.15 (2.80x) |
| Any Max Timestamp WKT JSON stringify | 168.00 | — | — | 2058.60 (12.25x) | 1020.27 (6.07x) |
| Any Max Timestamp WKT JSON parse | 581.52 | — | — | 3097.00 (5.33x) | 1629.68 (2.80x) |
| Any Min Timestamp WKT JSON stringify | 168.59 | — | — | 1944.14 (11.53x) | 977.31 (5.80x) |
| Any Min Timestamp WKT JSON parse | 558.57 | — | — | 3030.88 (5.43x) | 1601.04 (2.87x) |
| Any Empty WKT JSON stringify | 93.75 | — | — | 907.67 (9.68x) | 634.54 (6.77x) |
| Any Empty WKT JSON parse | 332.67 | — | — | 2127.46 (6.40x) | 1350.80 (4.06x) |
| Any Struct WKT JSON stringify | 637.32 | — | — | 5871.80 (9.21x) | 6055.68 (9.50x) |
| Any Struct WKT JSON parse | 2348.49 | — | — | 11113.50 (4.73x) | 8742.50 (3.72x) |
| Any Struct Escape WKT JSON parse | 2902.48 | — | — | 11153.60 (3.84x) | 8871.00 (3.06x) |
| Any Struct NumberExponent WKT JSON parse | 2411.88 | — | — | 11089.00 (4.60x) | 8734.65 (3.62x) |
| Any EmptyStruct WKT JSON stringify | 196.33 | — | — | 921.69 (4.69x) | 951.41 (4.85x) |
| Any EmptyStruct WKT JSON parse | 435.41 | — | — | 2252.52 (5.17x) | 1570.01 (3.61x) |
| Any Value WKT JSON stringify | 657.92 | — | — | 5886.24 (8.95x) | 6385.91 (9.71x) |
| Any Value WKT JSON parse | 1787.98 | — | — | 11330.90 (6.34x) | 9177.13 (5.13x) |
| Any Value Escape WKT JSON parse | 1808.75 | — | — | 11416.60 (6.31x) | 9253.63 (5.12x) |
| Any Value NumberExponent WKT JSON parse | 1796.47 | — | — | 11364.10 (6.33x) | 9185.52 (5.11x) |
| Any NullValue WKT JSON stringify | 139.10 | — | — | 2293.12 (16.49x) | 927.50 (6.67x) |
| Any NullValue WKT JSON parse | 461.08 | — | — | 4074.13 (8.84x) | 1593.83 (3.46x) |
| Any StringScalarValue WKT JSON stringify | 167.01 | — | — | 2267.95 (13.58x) | 1018.96 (6.10x) |
| Any StringScalarValue WKT JSON parse | 522.71 | — | — | 3632.63 (6.95x) | 1676.93 (3.21x) |
| Any StringScalarValue Escape WKT JSON parse | 536.01 | — | — | 3680.03 (6.87x) | 1748.52 (3.26x) |
| Any EmptyStringScalarValue WKT JSON stringify | 154.82 | — | — | 2280.65 (14.73x) | 952.26 (6.15x) |
| Any EmptyStringScalarValue WKT JSON parse | 491.95 | — | — | 3633.00 (7.38x) | 1594.10 (3.24x) |
| Any NumberValue WKT JSON stringify | 183.11 | — | — | 2512.09 (13.72x) | 1043.77 (5.70x) |
| Any NumberValue WKT JSON parse | 498.98 | — | — | 3697.74 (7.41x) | 1752.94 (3.51x) |
| Any NumberValue Exponent WKT JSON parse | 505.11 | — | — | 3723.49 (7.37x) | 1612.69 (3.19x) |
| Any NegativeNumberValue WKT JSON stringify | 184.28 | — | — | 2515.87 (13.65x) | 1043.64 (5.66x) |
| Any NegativeNumberValue WKT JSON parse | 500.30 | — | — | 3717.24 (7.43x) | 1610.08 (3.22x) |
| Any ZeroNumberValue WKT JSON stringify | 153.27 | — | — | 2489.43 (16.24x) | 932.27 (6.08x) |
| Any ZeroNumberValue WKT JSON parse | 499.66 | — | — | 3644.14 (7.29x) | 1630.17 (3.26x) |
| Any BoolScalarValue WKT JSON stringify | 142.17 | — | — | 2264.36 (15.93x) | 1551.99 (10.92x) |
| Any BoolScalarValue WKT JSON parse | 464.15 | — | — | 3602.04 (7.76x) | 2671.04 (5.75x) |
| Any FalseBoolScalarValue WKT JSON stringify | 139.16 | — | — | 2257.41 (16.22x) | 1677.70 (12.06x) |
| Any FalseBoolScalarValue WKT JSON parse | 464.60 | — | — | 3627.63 (7.81x) | 1559.71 (3.36x) |
| Any ListKindValue WKT JSON stringify | 515.39 | — | — | 5588.82 (10.84x) | 4698.86 (9.12x) |
| Any ListKindValue WKT JSON parse | 1401.01 | — | — | 9898.99 (7.07x) | 7227.95 (5.16x) |
| Any ListKindValue Escape WKT JSON parse | 1427.11 | — | — | 9972.74 (6.99x) | 7312.84 (5.12x) |
| Any EmptyStructKindValue WKT JSON stringify | 147.24 | — | — | 2927.60 (19.88x) | 1294.01 (8.79x) |
| Any EmptyStructKindValue WKT JSON parse | 498.95 | — | — | 5406.62 (10.84x) | 1959.72 (3.93x) |
| Any EmptyListKindValue WKT JSON stringify | 149.13 | — | — | 2907.04 (19.49x) | 1101.20 (7.38x) |
| Any EmptyListKindValue WKT JSON parse | 506.70 | — | — | 4404.07 (8.69x) | 1850.27 (3.65x) |
| Any DoubleValue WKT JSON stringify | 195.56 | — | — | 1794.85 (9.18x) | 805.72 (4.12x) |
| Any DoubleValue WKT JSON parse | 522.29 | — | — | 2735.67 (5.24x) | 1443.78 (2.76x) |
| Any DoubleValue String WKT JSON parse | 534.46 | — | — | 2727.79 (5.10x) | 1512.60 (2.83x) |
| Any DoubleValue Exponent WKT JSON parse | 526.14 | — | — | 2740.50 (5.21x) | 1435.73 (2.73x) |
| Any NegativeDoubleValue WKT JSON stringify | 196.21 | — | — | 1796.46 (9.16x) | 799.35 (4.07x) |
| Any NegativeDoubleValue WKT JSON parse | 522.49 | — | — | 2735.56 (5.24x) | 1439.09 (2.75x) |
| Any ZeroDoubleValue WKT JSON stringify | 165.64 | — | — | 916.10 (5.53x) | 738.99 (4.46x) |
| Any ZeroDoubleValue WKT JSON parse | 515.02 | — | — | 2160.30 (4.19x) | 1389.90 (2.70x) |
| Any DoubleValue NaN WKT JSON stringify | 161.46 | — | — | 1572.61 (9.74x) | 723.72 (4.48x) |
| Any DoubleValue NaN WKT JSON parse | 514.17 | — | — | 2648.39 (5.15x) | 1427.18 (2.78x) |
| Any DoubleValue Infinity WKT JSON stringify | 169.03 | — | — | 1562.22 (9.24x) | 722.10 (4.27x) |
| Any DoubleValue Infinity WKT JSON parse | 518.07 | — | — | 2689.23 (5.19x) | 1429.02 (2.76x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 175.27 | — | — | 1564.26 (8.92x) | 732.11 (4.18x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 521.50 | — | — | 2689.87 (5.16x) | 1416.35 (2.72x) |
| Any FloatValue WKT JSON stringify | 202.43 | — | — | 1745.24 (8.62x) | 793.21 (3.92x) |
| Any FloatValue WKT JSON parse | 520.65 | — | — | 2716.63 (5.22x) | 1471.66 (2.83x) |
| Any FloatValue String WKT JSON parse | 530.12 | — | — | 2718.28 (5.13x) | 1496.76 (2.82x) |
| Any FloatValue Exponent WKT JSON parse | 522.22 | — | — | 2716.47 (5.20x) | 1406.77 (2.69x) |
| Any NegativeFloatValue WKT JSON stringify | 203.62 | — | — | 1742.59 (8.56x) | 780.99 (3.84x) |
| Any NegativeFloatValue WKT JSON parse | 518.92 | — | — | 2712.29 (5.23x) | 1426.59 (2.75x) |
| Any ZeroFloatValue WKT JSON stringify | 169.26 | — | — | 913.40 (5.40x) | 731.77 (4.32x) |
| Any ZeroFloatValue WKT JSON parse | 516.75 | — | — | 2147.53 (4.16x) | 1428.90 (2.77x) |
| Any FloatValue NaN WKT JSON stringify | 166.29 | — | — | 1563.90 (9.40x) | 721.16 (4.34x) |
| Any FloatValue NaN WKT JSON parse | 512.63 | — | — | 2612.82 (5.10x) | 1385.28 (2.70x) |
| Any FloatValue Infinity WKT JSON stringify | 167.32 | — | — | 1558.06 (9.31x) | 712.78 (4.26x) |
| Any FloatValue Infinity WKT JSON parse | 522.02 | — | — | 2672.76 (5.12x) | 1406.11 (2.69x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 171.35 | — | — | 1554.65 (9.07x) | 712.77 (4.16x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 519.63 | — | — | 2652.17 (5.10x) | 1383.21 (2.66x) |
| Any Int64Value WKT JSON stringify | 172.29 | — | — | 1565.75 (9.09x) | 877.84 (5.10x) |
| Any Int64Value WKT JSON parse | 550.49 | — | — | 2787.04 (5.06x) | 1662.16 (3.02x) |
| Any Int64Value Number WKT JSON parse | 549.27 | — | — | 2740.79 (4.99x) | 1525.52 (2.78x) |
| Any Int64Value Exponent WKT JSON parse | 535.15 | — | — | 2697.15 (5.04x) | 1477.99 (2.76x) |
| Any ZeroInt64Value WKT JSON stringify | 165.61 | — | — | 912.37 (5.51x) | 787.27 (4.75x) |
| Any ZeroInt64Value WKT JSON parse | 519.64 | — | — | 2154.01 (4.15x) | 1469.08 (2.83x) |
| Any NegativeInt64Value WKT JSON stringify | 172.84 | — | — | 1563.40 (9.05x) | 858.34 (4.97x) |
| Any NegativeInt64Value WKT JSON parse | 557.83 | — | — | 2804.04 (5.03x) | 1674.19 (3.00x) |
| Any MinInt64Value WKT JSON stringify | 177.77 | — | — | 1563.38 (8.79x) | 858.62 (4.83x) |
| Any MinInt64Value WKT JSON parse | 567.12 | — | — | 2814.28 (4.96x) | 1660.96 (2.93x) |
| Any MaxInt64Value WKT JSON stringify | 174.15 | — | — | 1562.84 (8.97x) | 850.66 (4.88x) |
| Any MaxInt64Value WKT JSON parse | 558.22 | — | — | 2807.25 (5.03x) | 1649.86 (2.96x) |
| Any UInt64Value WKT JSON stringify | 181.53 | — | — | 1557.41 (8.58x) | 861.68 (4.75x) |
| Any UInt64Value WKT JSON parse | 555.69 | — | — | 2782.64 (5.01x) | 1627.04 (2.93x) |
| Any UInt64Value Number WKT JSON parse | 552.36 | — | — | 2755.54 (4.99x) | 1524.84 (2.76x) |
| Any UInt64Value Exponent WKT JSON parse | 538.68 | — | — | 2708.36 (5.03x) | 1489.58 (2.77x) |
| Any ZeroUInt64Value WKT JSON stringify | 174.19 | — | — | 915.84 (5.26x) | 786.23 (4.51x) |
| Any ZeroUInt64Value WKT JSON parse | 524.46 | — | — | 2153.61 (4.11x) | 1481.39 (2.82x) |
| Any MaxUInt64Value WKT JSON stringify | 178.93 | — | — | 1570.40 (8.78x) | 974.05 (5.44x) |
| Any MaxUInt64Value WKT JSON parse | 563.65 | — | — | 2837.72 (5.03x) | 1681.04 (2.98x) |
| Any Int32Value WKT JSON stringify | 182.55 | — | — | 1547.54 (8.48x) | 737.74 (4.04x) |
| Any Int32Value WKT JSON parse | 534.47 | — | — | 2666.57 (4.99x) | 1453.80 (2.72x) |
| Any Int32Value String WKT JSON parse | 541.56 | — | — | 2673.11 (4.94x) | 1541.08 (2.85x) |
| Any Int32Value Exponent WKT JSON parse | 539.05 | — | — | 2703.43 (5.02x) | 1520.42 (2.82x) |
| Any ZeroInt32Value WKT JSON stringify | 180.57 | — | — | 915.97 (5.07x) | 927.18 (5.13x) |
| Any ZeroInt32Value WKT JSON parse | 529.68 | — | — | 2155.16 (4.07x) | 1396.27 (2.64x) |
| Any NegativeInt32Value WKT JSON stringify | 184.56 | — | — | 1552.04 (8.41x) | 732.68 (3.97x) |
| Any NegativeInt32Value WKT JSON parse | 538.81 | — | — | 2697.62 (5.01x) | 1466.67 (2.72x) |
| Any MinInt32Value WKT JSON stringify | 185.51 | — | — | 1553.69 (8.38x) | 744.11 (4.01x) |
| Any MinInt32Value WKT JSON parse | 541.97 | — | — | 2702.08 (4.99x) | 1505.32 (2.78x) |
| Any MaxInt32Value WKT JSON stringify | 180.75 | — | — | 1550.15 (8.58x) | 742.54 (4.11x) |
| Any MaxInt32Value WKT JSON parse | 540.40 | — | — | 2671.66 (4.94x) | 1481.54 (2.74x) |
| Any UInt32Value WKT JSON stringify | 186.34 | — | — | 1548.39 (8.31x) | 744.50 (4.00x) |
| Any UInt32Value WKT JSON parse | 540.19 | — | — | 2672.51 (4.95x) | 1433.73 (2.65x) |
| Any UInt32Value String WKT JSON parse | 548.55 | — | — | 2663.63 (4.86x) | 1520.15 (2.77x) |
| Any UInt32Value Exponent WKT JSON parse | 544.78 | — | — | 2699.08 (4.95x) | 1491.69 (2.74x) |
| Any ZeroUInt32Value WKT JSON stringify | 190.10 | — | — | 917.16 (4.82x) | 717.39 (3.77x) |
| Any ZeroUInt32Value WKT JSON parse | 533.77 | — | — | 2148.40 (4.02x) | 1392.33 (2.61x) |
| Any MaxUInt32Value WKT JSON stringify | 194.14 | — | — | 1550.72 (7.99x) | 747.91 (3.85x) |
| Any MaxUInt32Value WKT JSON parse | 549.60 | — | — | 2692.51 (4.90x) | 1446.63 (2.63x) |
| Any BoolValue WKT JSON stringify | 178.78 | — | — | 1526.53 (8.54x) | 725.91 (4.06x) |
| Any BoolValue WKT JSON parse | 485.50 | — | — | 2606.76 (5.37x) | 1325.20 (2.73x) |
| Any FalseBoolValue WKT JSON stringify | 182.27 | — | — | 917.17 (5.03x) | 704.33 (3.86x) |
| Any FalseBoolValue WKT JSON parse | 484.45 | — | — | 2141.97 (4.42x) | 1338.21 (2.76x) |
| Any StringValue WKT JSON stringify | 208.21 | — | — | 1565.93 (7.52x) | 801.98 (3.85x) |
| Any StringValue WKT JSON parse | 552.10 | — | — | 2663.17 (4.82x) | 1454.94 (2.64x) |
| Any StringValue Escape WKT JSON parse | 558.65 | — | — | 2690.55 (4.82x) | 1531.36 (2.74x) |
| Any EmptyStringValue WKT JSON stringify | 193.85 | — | — | 914.44 (4.72x) | 762.25 (3.93x) |
| Any EmptyStringValue WKT JSON parse | 519.80 | — | — | 2154.94 (4.15x) | 1363.18 (2.62x) |
| Any BytesValue WKT JSON stringify | 185.54 | — | — | 1600.88 (8.63x) | 849.66 (4.58x) |
| Any BytesValue WKT JSON parse | 561.74 | — | — | 2697.44 (4.80x) | 1512.90 (2.69x) |
| Any BytesValue URL WKT JSON parse | 576.71 | — | — | 2682.28 (4.65x) | 1485.45 (2.58x) |
| Any BytesValue Unpadded WKT JSON parse | 564.89 | — | — | 2682.22 (4.75x) | 1486.32 (2.63x) |
| Any EmptyBytesValue WKT JSON stringify | 190.06 | — | — | 912.46 (4.80x) | 752.01 (3.96x) |
| Any EmptyBytesValue WKT JSON parse | 525.04 | — | — | 2153.57 (4.10x) | 1455.26 (2.77x) |
| Nested Any WKT JSON stringify | 330.73 | — | — | 2476.22 (7.49x) | 1464.70 (4.43x) |
| Nested Any WKT JSON parse | 868.14 | — | — | 4262.83 (4.91x) | 2865.96 (3.30x) |
| Duration JSON stringify | 58.48 | — | — | 952.63 (16.29x) | 353.85 (6.05x) |
| Duration JSON parse | 20.41 | — | — | 1448.39 (70.96x) | 406.77 (19.93x) |
| Duration Escape JSON parse | 40.50 | — | — | 1481.11 (36.57x) | 429.53 (10.61x) |
| PlusDuration JSON parse | 20.15 | — | — | 1454.06 (72.16x) | 391.68 (19.44x) |
| ShortFractionDuration JSON parse | 16.34 | — | — | 1419.97 (86.90x) | 399.48 (24.45x) |
| MicroDuration JSON stringify | 59.86 | — | — | 968.59 (16.18x) | 409.88 (6.85x) |
| MicroDuration JSON parse | 20.84 | — | — | 1461.90 (70.15x) | 551.51 (26.46x) |
| NanoDuration JSON stringify | 57.47 | — | — | 995.55 (17.32x) | 416.77 (7.25x) |
| NanoDuration JSON parse | 27.37 | — | — | 1472.21 (53.79x) | 395.87 (14.46x) |
| NegativeDuration JSON stringify | 58.48 | — | — | 996.72 (17.04x) | 418.70 (7.16x) |
| NegativeDuration JSON parse | 21.08 | — | — | 1503.99 (71.35x) | 394.99 (18.74x) |
| FractionalNegativeDuration JSON stringify | 58.45 | — | — | 965.45 (16.52x) | 425.21 (7.27x) |
| FractionalNegativeDuration JSON parse | 20.35 | — | — | 1458.22 (71.66x) | 377.21 (18.54x) |
| MaxDuration JSON stringify | 50.21 | — | — | 855.61 (17.04x) | 405.54 (8.08x) |
| MaxDuration JSON parse | 35.62 | — | — | 1431.75 (40.20x) | 405.48 (11.38x) |
| MinDuration JSON stringify | 49.97 | — | — | 872.14 (17.45x) | 426.78 (8.54x) |
| MinDuration JSON parse | 36.68 | — | — | 1447.26 (39.46x) | 407.54 (11.11x) |
| ZeroDuration JSON stringify | 44.86 | — | — | 810.35 (18.06x) | 378.05 (8.43x) |
| ZeroDuration JSON parse | 13.10 | — | — | 1366.64 (104.32x) | 312.69 (23.87x) |
| FieldMask JSON stringify | 66.32 | — | — | 880.99 (13.28x) | 654.05 (9.86x) |
| FieldMask JSON parse | 140.01 | — | — | 1648.58 (11.77x) | 881.74 (6.30x) |
| FieldMask Escape JSON parse | 189.11 | — | — | 1708.96 (9.04x) | 970.21 (5.13x) |
| EmptyFieldMask JSON stringify | 40.90 | — | — | 607.79 (14.86x) | 193.64 (4.73x) |
| EmptyFieldMask JSON parse | 4.60 | — | — | 942.35 (204.86x) | 167.01 (36.31x) |
| Timestamp JSON stringify | 97.46 | — | — | 1165.57 (11.96x) | 412.55 (4.23x) |
| Timestamp JSON parse | 45.49 | — | — | 1541.59 (33.89x) | 444.41 (9.77x) |
| Timestamp Escape JSON parse | 92.71 | — | — | 1567.16 (16.90x) | 506.24 (5.46x) |
| ShortFraction Timestamp JSON parse | 43.57 | — | — | 1534.17 (35.21x) | 569.15 (13.06x) |
| Micro Timestamp JSON stringify | 97.32 | — | — | 1143.56 (11.75x) | 681.69 (7.00x) |
| Micro Timestamp JSON parse | 49.16 | — | — | 1547.55 (31.48x) | 460.63 (9.37x) |
| Nano Timestamp JSON stringify | 94.28 | — | — | 1184.44 (12.56x) | 428.11 (4.54x) |
| Nano Timestamp JSON parse | 53.16 | — | — | 1510.93 (28.42x) | 466.52 (8.78x) |
| Offset Timestamp JSON parse | 52.84 | — | — | 1523.81 (28.84x) | 489.07 (9.26x) |
| PreEpoch Timestamp JSON stringify | 66.87 | — | — | 1061.15 (15.87x) | 401.79 (6.01x) |
| PreEpoch Timestamp JSON parse | 43.42 | — | — | 1458.06 (33.58x) | 425.98 (9.81x) |
| Max Timestamp JSON stringify | 79.72 | — | — | 1191.69 (14.95x) | 424.85 (5.33x) |
| Max Timestamp JSON parse | 56.38 | — | — | 1532.53 (27.18x) | 471.93 (8.37x) |
| Min Timestamp JSON stringify | 81.08 | — | — | 1051.14 (12.96x) | 399.85 (4.93x) |
| Min Timestamp JSON parse | 41.28 | — | — | 1447.36 (35.06x) | 763.28 (18.49x) |
| Empty JSON stringify | 20.92 | — | — | 503.03 (24.05x) | 84.79 (4.05x) |
| Empty JSON parse | 67.22 | — | — | 730.97 (10.87x) | 206.45 (3.07x) |
| Struct JSON stringify | 190.83 | — | — | 5760.38 (30.19x) | 3042.90 (15.95x) |
| Struct JSON parse | 848.13 | — | — | 10896.60 (12.85x) | 4750.91 (5.60x) |
| Struct Escape JSON parse | 887.91 | — | — | 10973.60 (12.36x) | 4849.53 (5.46x) |
| Struct NumberExponent JSON parse | 844.66 | — | — | 10912.20 (12.92x) | 4737.44 (5.61x) |
| EmptyStruct JSON stringify | 41.26 | — | — | 702.28 (17.02x) | 350.70 (8.50x) |
| EmptyStruct JSON parse | 88.62 | — | — | 2033.03 (22.94x) | 375.22 (4.23x) |
| Value JSON stringify | 185.13 | — | — | 6605.49 (35.68x) | 3232.98 (17.46x) |
| Value JSON parse | 869.22 | — | — | 12127.60 (13.95x) | 4978.31 (5.73x) |
| Value Escape JSON parse | 910.01 | — | — | 12223.30 (13.43x) | 5121.35 (5.63x) |
| Value NumberExponent JSON parse | 862.47 | — | — | 12197.30 (14.14x) | 4967.01 (5.76x) |
| NullValue JSON stringify | 41.06 | — | — | 1325.88 (32.29x) | 216.90 (5.28x) |
| NullValue JSON parse | 70.78 | — | — | 2485.18 (35.11x) | 346.61 (4.90x) |
| StringScalarValue JSON stringify | 48.38 | — | — | 1354.21 (27.99x) | 286.65 (5.92x) |
| StringScalarValue JSON parse | 141.16 | — | — | 2104.38 (14.91x) | 444.42 (3.15x) |
| StringScalarValue Escape JSON parse | 150.80 | — | — | 2120.95 (14.06x) | 492.91 (3.27x) |
| EmptyStringScalarValue JSON stringify | 46.92 | — | — | 1336.91 (28.49x) | 270.56 (5.77x) |
| EmptyStringScalarValue JSON parse | 88.04 | — | — | 2084.99 (23.68x) | 367.58 (4.18x) |
| NumberValue JSON stringify | 74.12 | — | — | 1559.22 (21.04x) | 330.00 (4.45x) |
| NumberValue JSON parse | 132.81 | — | — | 2185.13 (16.45x) | 412.63 (3.11x) |
| NumberValue Exponent JSON parse | 135.69 | — | — | 2195.26 (16.18x) | 426.42 (3.14x) |
| NegativeNumberValue JSON stringify | 73.44 | — | — | 1563.03 (21.28x) | 331.53 (4.51x) |
| NegativeNumberValue JSON parse | 133.44 | — | — | 2197.67 (16.47x) | 428.38 (3.21x) |
| ZeroNumberValue JSON stringify | 51.22 | — | — | 1517.94 (29.64x) | 358.35 (7.00x) |
| ZeroNumberValue JSON parse | 131.73 | — | — | 2131.90 (16.18x) | 383.27 (2.91x) |
| BoolScalarValue JSON stringify | 41.04 | — | — | 1326.79 (32.33x) | 218.84 (5.33x) |
| BoolScalarValue JSON parse | 70.66 | — | — | 2031.39 (28.75x) | 336.68 (4.76x) |
| FalseBoolScalarValue JSON stringify | 40.97 | — | — | 1321.65 (32.26x) | 221.01 (5.39x) |
| FalseBoolScalarValue JSON parse | 71.27 | — | — | 2034.71 (28.55x) | 333.07 (4.67x) |
| ListKindValue JSON stringify | 145.37 | — | — | 6170.83 (42.45x) | 2249.12 (15.47x) |
| ListKindValue JSON parse | 676.74 | — | — | 10399.10 (15.37x) | 4048.41 (5.98x) |
| ListKindValue Escape JSON parse | 697.97 | — | — | 10519.00 (15.07x) | 4280.87 (6.13x) |
| EmptyStructKindValue JSON stringify | 42.94 | — | — | 1954.37 (45.51x) | 524.07 (12.20x) |
| EmptyStructKindValue JSON parse | 111.05 | — | — | 3766.64 (33.92x) | 659.45 (5.94x) |
| EmptyListKindValue JSON stringify | 41.63 | — | — | 1947.03 (46.77x) | 362.74 (8.71x) |
| EmptyListKindValue JSON parse | 148.77 | — | — | 4027.26 (27.07x) | 589.09 (3.96x) |
| ListValue JSON stringify | 152.40 | — | — | 4764.91 (31.27x) | 2113.78 (13.87x) |
| ListValue JSON parse | 653.19 | — | — | 8515.87 (13.04x) | 3808.84 (5.83x) |
| ListValue Escape JSON parse | 676.64 | — | — | 8610.42 (12.73x) | 4014.36 (5.93x) |
| EmptyListValue JSON stringify | 40.12 | — | — | 687.30 (17.13x) | 187.01 (4.66x) |
| EmptyListValue JSON parse | 129.36 | — | — | 2257.15 (17.45x) | 332.07 (2.57x) |
| DoubleValue JSON stringify | 67.59 | — | — | 865.22 (12.80x) | 191.47 (2.83x) |
| DoubleValue JSON parse | 111.74 | — | — | 1229.71 (11.01x) | 282.09 (2.52x) |
| DoubleValue String JSON parse | 112.43 | — | — | 1170.62 (10.41x) | 368.43 (3.28x) |
| DoubleValue Exponent JSON parse | 115.81 | — | — | 1243.01 (10.73x) | 285.74 (2.47x) |
| NegativeDoubleValue JSON stringify | 67.90 | — | — | 865.49 (12.75x) | 193.98 (2.86x) |
| NegativeDoubleValue JSON parse | 112.02 | — | — | 1227.44 (10.96x) | 290.75 (2.60x) |
| ZeroDoubleValue JSON stringify | 47.49 | — | — | 807.62 (17.01x) | 138.84 (2.92x) |
| ZeroDoubleValue JSON parse | 109.03 | — | — | 1164.22 (10.68x) | 272.45 (2.50x) |
| DoubleValue NaN JSON stringify | 46.91 | — | — | 724.38 (15.44x) | 126.03 (2.69x) |
| DoubleValue NaN JSON parse | 105.46 | — | — | 1100.25 (10.43x) | 283.59 (2.69x) |
| DoubleValue Infinity JSON stringify | 48.49 | — | — | 670.30 (13.82x) | 121.55 (2.51x) |
| DoubleValue Infinity JSON parse | 107.05 | — | — | 1118.32 (10.45x) | 293.59 (2.74x) |
| DoubleValue NegativeInfinity JSON stringify | 48.63 | — | — | 672.54 (13.83x) | 128.03 (2.63x) |
| DoubleValue NegativeInfinity JSON parse | 110.52 | — | — | 1120.48 (10.14x) | 286.28 (2.59x) |
| FloatValue JSON stringify | 71.89 | — | — | 797.62 (11.09x) | 186.59 (2.60x) |
| FloatValue JSON parse | 111.04 | — | — | 1218.08 (10.97x) | 305.56 (2.75x) |
| FloatValue String JSON parse | 110.04 | — | — | 1153.66 (10.48x) | 354.50 (3.22x) |
| FloatValue Exponent JSON parse | 112.55 | — | — | 1228.24 (10.91x) | 290.36 (2.58x) |
| NegativeFloatValue JSON stringify | 72.62 | — | — | 805.01 (11.09x) | 188.09 (2.59x) |
| NegativeFloatValue JSON parse | 110.95 | — | — | 1236.63 (11.15x) | 291.52 (2.63x) |
| ZeroFloatValue JSON stringify | 47.38 | — | — | 742.15 (15.66x) | 142.15 (3.00x) |
| ZeroFloatValue JSON parse | 108.55 | — | — | 1156.37 (10.65x) | 261.56 (2.41x) |
| FloatValue NaN JSON stringify | 49.67 | — | — | 638.21 (12.85x) | 123.19 (2.48x) |
| FloatValue NaN JSON parse | 104.41 | — | — | 1081.88 (10.36x) | 271.13 (2.60x) |
| FloatValue Infinity JSON stringify | 48.15 | — | — | 640.79 (13.31x) | 126.11 (2.62x) |
| FloatValue Infinity JSON parse | 105.71 | — | — | 1095.13 (10.36x) | 275.87 (2.61x) |
| FloatValue NegativeInfinity JSON stringify | 48.38 | — | — | 637.72 (13.18x) | 128.92 (2.66x) |
| FloatValue NegativeInfinity JSON parse | 108.01 | — | — | 1099.34 (10.18x) | 287.25 (2.66x) |
| Int64Value JSON stringify | 49.96 | — | — | 678.34 (13.58x) | 280.41 (5.61x) |
| Int64Value JSON parse | 126.18 | — | — | 1233.09 (9.77x) | 472.83 (3.75x) |
| Int64Value Number JSON parse | 128.85 | — | — | 1289.29 (10.01x) | 367.68 (2.85x) |
| Int64Value Exponent JSON parse | 116.56 | — | — | 1231.71 (10.57x) | 369.88 (3.17x) |
| ZeroInt64Value JSON stringify | 41.47 | — | — | 721.07 (17.39x) | 198.01 (4.77x) |
| ZeroInt64Value JSON parse | 106.91 | — | — | 1098.05 (10.27x) | 334.81 (3.13x) |
| NegativeInt64Value JSON stringify | 48.46 | — | — | 671.99 (13.87x) | 279.07 (5.76x) |
| NegativeInt64Value JSON parse | 127.48 | — | — | 1213.10 (9.52x) | 471.06 (3.70x) |
| MinInt64Value JSON stringify | 49.56 | — | — | 674.08 (13.60x) | 287.45 (5.80x) |
| MinInt64Value JSON parse | 134.88 | — | — | 1237.66 (9.18x) | 487.67 (3.62x) |
| MaxInt64Value JSON stringify | 49.31 | — | — | 676.22 (13.71x) | 284.40 (5.77x) |
| MaxInt64Value JSON parse | 134.16 | — | — | 1243.96 (9.27x) | 479.27 (3.57x) |
| UInt64Value JSON stringify | 50.34 | — | — | 679.05 (13.49x) | 282.26 (5.61x) |
| UInt64Value JSON parse | 127.03 | — | — | 1220.75 (9.61x) | 472.21 (3.72x) |
| UInt64Value Number JSON parse | 129.68 | — | — | 1283.98 (9.90x) | 352.64 (2.72x) |
| UInt64Value Exponent JSON parse | 117.26 | — | — | 1233.77 (10.52x) | 371.78 (3.17x) |
| ZeroUInt64Value JSON stringify | 41.98 | — | — | 618.09 (14.72x) | 206.31 (4.91x) |
| ZeroUInt64Value JSON parse | 105.96 | — | — | 1094.59 (10.33x) | 338.90 (3.20x) |
| MaxUInt64Value JSON stringify | 50.07 | — | — | 680.45 (13.59x) | 289.73 (5.79x) |
| MaxUInt64Value JSON parse | 139.24 | — | — | 1250.60 (8.98x) | 478.78 (3.44x) |
| Int32Value JSON stringify | 46.28 | — | — | 636.86 (13.76x) | 134.92 (2.92x) |
| Int32Value JSON parse | 132.99 | — | — | 1187.52 (8.93x) | 318.07 (2.39x) |
| Int32Value String JSON parse | 136.49 | — | — | 1139.31 (8.35x) | 414.21 (3.03x) |
| Int32Value Exponent JSON parse | 135.69 | — | — | 1229.45 (9.06x) | 358.69 (2.64x) |
| ZeroInt32Value JSON stringify | 46.18 | — | — | 611.60 (13.24x) | 132.55 (2.87x) |
| ZeroInt32Value JSON parse | 129.13 | — | — | 1159.39 (8.98x) | 282.01 (2.18x) |
| NegativeInt32Value JSON stringify | 46.14 | — | — | 644.72 (13.97x) | 138.78 (3.01x) |
| NegativeInt32Value JSON parse | 132.61 | — | — | 1198.93 (9.04x) | 319.73 (2.41x) |
| MinInt32Value JSON stringify | 47.04 | — | — | 642.05 (13.65x) | 137.75 (2.93x) |
| MinInt32Value JSON parse | 138.60 | — | — | 1212.38 (8.75x) | 399.27 (2.88x) |
| MaxInt32Value JSON stringify | 47.04 | — | — | 636.58 (13.53x) | 139.83 (2.97x) |
| MaxInt32Value JSON parse | 138.74 | — | — | 1211.44 (8.73x) | 343.32 (2.47x) |
| UInt32Value JSON stringify | 46.15 | — | — | 646.71 (14.01x) | 135.07 (2.93x) |
| UInt32Value JSON parse | 133.22 | — | — | 1195.07 (8.97x) | 319.24 (2.40x) |
| UInt32Value String JSON parse | 136.78 | — | — | 1138.29 (8.32x) | 394.57 (2.88x) |
| UInt32Value Exponent JSON parse | 136.47 | — | — | 1233.89 (9.04x) | 367.87 (2.70x) |
| ZeroUInt32Value JSON stringify | 46.21 | — | — | 627.30 (13.57x) | 131.68 (2.85x) |
| ZeroUInt32Value JSON parse | 128.25 | — | — | 1152.80 (8.99x) | 271.44 (2.12x) |
| MaxUInt32Value JSON stringify | 46.78 | — | — | 642.00 (13.72x) | 216.83 (4.64x) |
| MaxUInt32Value JSON parse | 139.00 | — | — | 1203.78 (8.66x) | 331.85 (2.39x) |
| BoolValue JSON stringify | 44.94 | — | — | 612.87 (13.64x) | 122.79 (2.73x) |
| BoolValue JSON parse | 59.39 | — | — | 1070.00 (18.02x) | 230.91 (3.89x) |
| FalseBoolValue JSON stringify | 44.80 | — | — | 606.70 (13.54x) | 123.73 (2.76x) |
| FalseBoolValue JSON parse | 59.90 | — | — | 1064.24 (17.77x) | 223.70 (3.73x) |
| StringValue JSON stringify | 52.14 | — | — | 681.62 (13.07x) | 195.25 (3.74x) |
| StringValue JSON parse | 121.70 | — | — | 1154.81 (9.49x) | 319.28 (2.62x) |
| StringValue Escape JSON parse | 130.90 | — | — | 1186.40 (9.06x) | 368.96 (2.82x) |
| EmptyStringValue JSON stringify | 48.92 | — | — | 647.58 (13.24x) | 178.70 (3.65x) |
| EmptyStringValue JSON parse | 66.18 | — | — | 1125.42 (17.01x) | 233.58 (3.53x) |
| BytesValue JSON stringify | 49.93 | — | — | 665.00 (13.32x) | 215.48 (4.32x) |
| BytesValue JSON parse | 124.55 | — | — | 1179.16 (9.47x) | 348.69 (2.80x) |
| BytesValue URL JSON parse | 140.64 | — | — | 1165.59 (8.29x) | 328.55 (2.34x) |
| BytesValue Unpadded JSON parse | 122.93 | — | — | 1165.77 (9.48x) | 333.94 (2.72x) |
| EmptyBytesValue JSON stringify | 41.75 | — | — | 636.63 (15.25x) | 186.90 (4.48x) |
| EmptyBytesValue JSON parse | 68.22 | — | — | 1140.71 (16.72x) | 304.24 (4.46x) |
| TextFormat format | 178.42 | — | — | 2562.05 (14.36x) | 2553.13 (14.31x) |
| TextFormat parse | 711.24 | — | — | 4994.46 (7.02x) | 6672.30 (9.38x) |
| packed fixed32 encode | 2.01 | 550.84 (274.05x) | 539.43 (268.37x) | 43.95 (21.86x) | 433.18 (215.51x) |
| packed fixed32 decode | 4.53 | 1050.65 (231.93x) | 1941.14 (428.51x) | 49.40 (10.91x) | 1551.94 (342.59x) |
| packed fixed64 encode | 2.01 | 572.36 (284.76x) | 561.09 (279.15x) | 75.81 (37.72x) | 393.12 (195.58x) |
| packed fixed64 decode | 4.53 | 1064.22 (234.93x) | 7940.41 (1752.85x) | 79.82 (17.62x) | 2165.22 (477.97x) |
| packed sfixed32 encode | 2.01 | 553.96 (275.60x) | 539.55 (268.43x) | 43.92 (21.85x) | 719.38 (357.90x) |
| packed sfixed32 decode | 4.54 | 1148.35 (252.94x) | 2001.09 (440.77x) | 49.07 (10.81x) | 1549.98 (341.41x) |
| packed sfixed64 encode | 2.01 | 570.97 (284.06x) | 561.22 (279.21x) | 76.21 (37.92x) | 396.82 (197.42x) |
| packed sfixed64 decode | 4.53 | 986.49 (217.77x) | 7900.33 (1744.00x) | 79.48 (17.54x) | 2166.72 (478.30x) |
| packed float encode | 2.01 | 811.24 (403.60x) | 542.19 (269.75x) | 43.94 (21.86x) | 372.70 (185.42x) |
| packed float decode | 4.52 | 1050.08 (232.32x) | 2062.51 (456.31x) | 48.86 (10.81x) | 1558.35 (344.77x) |
| packed double encode | 2.91 | 831.43 (285.71x) | 561.08 (192.81x) | 75.73 (26.02x) | 360.99 (124.05x) |
| packed double decode | 9.00 | 980.20 (108.91x) | 2040.99 (226.78x) | 79.66 (8.85x) | 2174.30 (241.59x) |
| packed uint64 encode | 1292.78 | 4604.48 (3.56x) | 4011.53 (3.10x) | 2122.82 (1.64x) | 3460.57 (2.68x) |
| packed uint64 decode | 1780.55 | 2783.91 (1.56x) | 8868.74 (4.98x) | 2798.84 (1.57x) | 6233.96 (3.50x) |
| packed uint32 encode | 925.25 | 3608.92 (3.90x) | 3282.94 (3.55x) | 1734.48 (1.87x) | 2878.89 (3.11x) |
| packed uint32 decode | 1317.06 | 2436.85 (1.85x) | 3269.12 (2.48x) | 1988.47 (1.51x) | 4693.88 (3.56x) |
| packed int64 encode | 1398.76 | 11048.66 (7.90x) | 6052.49 (4.33x) | 2905.06 (2.08x) | 4124.37 (2.95x) |
| packed int64 decode | 2759.43 | 3379.69 (1.22x) | 10260.83 (3.72x) | 4517.70 (1.64x) | 7737.75 (2.80x) |
| packed sint32 encode | 865.08 | 3030.65 (3.50x) | 2789.07 (3.22x) | 1534.09 (1.77x) | 3408.81 (3.94x) |
| packed sint32 decode | 951.54 | 2550.43 (2.68x) | 3184.80 (3.35x) | 1173.97 (1.23x) | 3123.46 (3.28x) |
| packed sint64 encode | 1434.93 | 4933.98 (3.44x) | 4427.68 (3.09x) | 2400.55 (1.67x) | 4179.60 (2.91x) |
| packed sint64 decode | 2036.13 | 3080.01 (1.51x) | 9642.92 (4.74x) | 2930.91 (1.44x) | 6513.09 (3.20x) |
| packed bool encode | 2.00 | 1334.04 (667.02x) | 520.68 (260.34x) | 15.58 (7.79x) | 2251.44 (1125.72x) |
| packed bool decode | 262.78 | 1540.29 (5.86x) | 2547.72 (9.70x) | 805.21 (3.06x) | 1614.59 (6.14x) |
| packed enum encode | 274.85 | 2719.43 (9.89x) | 1804.71 (6.57x) | 1084.51 (3.95x) | 2493.44 (9.07x) |
| packed enum decode | 156.12 | 1642.60 (10.52x) | 2860.52 (18.32x) | 705.53 (4.52x) | 2085.49 (13.36x) |
| large map encode | 4130.78 | 21578.77 (5.22x) | 9617.14 (2.33x) | 22636.60 (5.48x) | 209342.91 (50.68x) |
| shuffled large map deterministic binary encode | 27773.33 | — | — | 104213.00 (3.75x) | 441999.93 (15.91x) |
| large map decode | 25272.98 | 90723.19 (3.59x) | 89379.53 (3.54x) | 89400.90 (3.54x) | 281662.70 (11.14x) |
The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound `Duration`, non-empty/escaped-input parse/number-exponent parse and empty `Struct`, object/escaped-object parse/object-number-exponent/list/escaped-list/string-scalar/escaped-string-scalar/number-exponent/negative-number `Value` (including default-like scalar and empty object/list kinds),
`FieldMask` (non-empty, escaped JSON parse input, and empty), escaped-input parse/short-fraction parse/micro/nano/offset/min/pre/post/max-bound `Timestamp`, `Empty`, min/zero/positive/number-input parse/numeric-exponent parse/negative/max `Int64Value`, negative/zero/positive finite/string-input parse/numeric-exponent parse `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), negative/zero/positive finite/string-input parse/numeric-exponent parse `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), zero/normal/number-input parse/numeric-exponent parse/max `UInt64Value`, min/zero/positive/string-input parse/numeric-exponent parse/negative/max `Int32Value`, zero/normal/string-input parse/numeric-exponent parse/max `UInt32Value`, true/false `BoolValue`, non-empty/escape-input parse/empty `StringValue`, base64/base64url/unpadded-base64 parse/empty `BytesValue`, and recursive nested `Any` payloads), direct zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound Duration, non-empty/escaped-input parse/empty FieldMask, and escaped-input parse/short-fraction parse/micro/nano/offset/min/pre/post/max-bound Timestamp WKT JSON plus other direct WKT JSON, including non-empty/escaped-input parse/number-exponent parse/empty `Struct`, object/escaped-object parse/object-number-exponent/list/escaped-list/string-scalar/escaped-string-scalar/number-exponent/negative-number `Value`, and escaped/non-empty/empty `ListValue`, TextFormat, packed scalars, large bytes,
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
