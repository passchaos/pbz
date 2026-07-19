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
```

Latest accepted comparison (`/tmp/pbz-compare-signed-minmax-wrapper-json-isolated.log`,
summarized in `/tmp/pbz-summary-signed-minmax-wrapper-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 30.69 | 152.67 (4.97x) | 73.46 (2.39x) | 102.04 (3.32x) | 839.74 (27.36x) |
| binary decode | 90.70 | 453.93 (5.00x) | 388.16 (4.28x) | 216.00 (2.38x) | 907.65 (10.01x) |
| unknown fields count by number | 3.57 | — | — | 162.06 (45.40x) | — |
| scalarmix encode | 20.05 | 166.90 (8.32x) | 67.54 (3.37x) | 28.32 (1.41x) | 204.13 (10.18x) |
| scalarmix decode | 34.33 | 232.73 (6.78x) | 266.79 (7.77x) | 78.47 (2.29x) | 308.89 (9.00x) |
| textbytes encode | 11.53 | 118.67 (10.29x) | 47.34 (4.11x) | 116.53 (10.11x) | 148.56 (12.88x) |
| largebytes decode | 88.80 | 7160.61 (80.64x) | 3631.82 (40.90x) | 2748.60 (30.95x) | 20540.00 (231.31x) |
| complex decode | 167.71 | 662.93 (3.95x) | 565.70 (3.37x) | 387.07 (2.31x) | 1341.94 (8.00x) |
| complex JSON parse | 2444.49 | — | — | 11955.70 (4.89x) | 7472.59 (3.06x) |
| packed int32 decode | 694.68 | 3291.73 (4.74x) | 5210.31 (7.50x) | 968.93 (1.39x) | 2537.96 (3.65x) |
| Any WKT JSON stringify | 128.19 | — | — | 1887.29 (14.72x) | 1012.74 (7.90x) |
| Any WKT JSON parse | 514.14 | — | — | 2981.50 (5.80x) | 1529.11 (2.97x) |
| Any NegativeDuration WKT JSON stringify | 131.74 | — | — | 1943.19 (14.75x) | 1009.83 (7.67x) |
| Any NegativeDuration WKT JSON parse | 515.66 | — | — | 3074.79 (5.96x) | 1567.18 (3.04x) |
| Any FractionalNegativeDuration WKT JSON stringify | 127.26 | — | — | 1886.11 (14.82x) | 1037.81 (8.16x) |
| Any FractionalNegativeDuration WKT JSON parse | 511.66 | — | — | 3051.54 (5.96x) | 1560.04 (3.05x) |
| Any MaxDuration WKT JSON stringify | 118.88 | — | — | 1748.83 (14.71x) | 997.79 (8.39x) |
| Any MaxDuration WKT JSON parse | 525.63 | — | — | 2954.91 (5.62x) | 1555.12 (2.96x) |
| Any MinDuration WKT JSON stringify | 118.93 | — | — | 1761.44 (14.81x) | 1061.79 (8.93x) |
| Any MinDuration WKT JSON parse | 524.81 | — | — | 3160.57 (6.02x) | 1540.44 (2.94x) |
| Any ZeroDuration WKT JSON stringify | 104.89 | — | — | 952.01 (9.08x) | 962.07 (9.17x) |
| Any ZeroDuration WKT JSON parse | 472.05 | — | — | 2324.27 (4.92x) | 1442.63 (3.06x) |
| Any FieldMask WKT JSON stringify | 247.30 | — | — | 1810.07 (7.32x) | 1429.23 (5.78x) |
| Any FieldMask WKT JSON parse | 709.58 | — | — | 3272.07 (4.61x) | 2091.08 (2.95x) |
| Any Timestamp WKT JSON stringify | 177.36 | — | — | 2018.68 (11.38x) | 1011.53 (5.70x) |
| Any Timestamp WKT JSON parse | 562.90 | — | — | 3015.24 (5.36x) | 1629.09 (2.89x) |
| Any PreEpoch Timestamp WKT JSON stringify | 154.02 | — | — | 1944.58 (12.63x) | 980.53 (6.37x) |
| Any PreEpoch Timestamp WKT JSON parse | 555.04 | — | — | 3031.16 (5.46x) | 1582.38 (2.85x) |
| Any Max Timestamp WKT JSON stringify | 162.63 | — | — | 2116.40 (13.01x) | 1022.89 (6.29x) |
| Any Max Timestamp WKT JSON parse | 575.85 | — | — | 3184.86 (5.53x) | 1637.76 (2.84x) |
| Any Min Timestamp WKT JSON stringify | 155.49 | — | — | 1990.88 (12.80x) | 969.27 (6.23x) |
| Any Min Timestamp WKT JSON parse | 552.56 | — | — | 3109.46 (5.63x) | 1580.95 (2.86x) |
| Any Empty WKT JSON stringify | 91.78 | — | — | 939.29 (10.23x) | 618.97 (6.74x) |
| Any Empty WKT JSON parse | 333.25 | — | — | 2181.06 (6.54x) | 1313.64 (3.94x) |
| Any Struct WKT JSON stringify | 625.83 | — | — | 6022.43 (9.62x) | 6048.16 (9.66x) |
| Any Struct WKT JSON parse | 1752.54 | — | — | 11067.50 (6.32x) | 8874.03 (5.06x) |
| Any Value WKT JSON stringify | 649.91 | — | — | 5851.11 (9.00x) | 7984.34 (12.29x) |
| Any Value WKT JSON parse | 1803.73 | — | — | 11321.50 (6.28x) | 9132.91 (5.06x) |
| Any DoubleValue WKT JSON stringify | 187.49 | — | — | 1806.86 (9.64x) | 846.66 (4.52x) |
| Any DoubleValue WKT JSON parse | 512.63 | — | — | 2760.68 (5.39x) | 1554.96 (3.03x) |
| Any ZeroDoubleValue WKT JSON stringify | 157.96 | — | — | 917.98 (5.81x) | 752.99 (4.77x) |
| Any ZeroDoubleValue WKT JSON parse | 509.15 | — | — | 2168.26 (4.26x) | 1432.01 (2.81x) |
| Any DoubleValue NaN WKT JSON stringify | 154.21 | — | — | 1574.01 (10.21x) | 741.86 (4.81x) |
| Any DoubleValue NaN WKT JSON parse | 510.38 | — | — | 2668.24 (5.23x) | 1480.06 (2.90x) |
| Any DoubleValue Infinity WKT JSON stringify | 158.67 | — | — | 1558.91 (9.82x) | 718.19 (4.53x) |
| Any DoubleValue Infinity WKT JSON parse | 513.83 | — | — | 2686.72 (5.23x) | 1458.89 (2.84x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 160.88 | — | — | 1594.17 (9.91x) | 718.43 (4.47x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 517.16 | — | — | 2712.13 (5.24x) | 1443.61 (2.79x) |
| Any FloatValue WKT JSON stringify | 193.07 | — | — | 1769.01 (9.16x) | 797.61 (4.13x) |
| Any FloatValue WKT JSON parse | 514.28 | — | — | 2757.02 (5.36x) | 1432.97 (2.79x) |
| Any ZeroFloatValue WKT JSON stringify | 164.22 | — | — | 915.62 (5.58x) | 734.45 (4.47x) |
| Any ZeroFloatValue WKT JSON parse | 512.74 | — | — | 2177.65 (4.25x) | 1399.64 (2.73x) |
| Any FloatValue NaN WKT JSON stringify | 157.08 | — | — | 1601.57 (10.20x) | 720.53 (4.59x) |
| Any FloatValue NaN WKT JSON parse | 509.56 | — | — | 2660.45 (5.22x) | 1375.20 (2.70x) |
| Any FloatValue Infinity WKT JSON stringify | 156.25 | — | — | 1585.81 (10.15x) | 729.11 (4.67x) |
| Any FloatValue Infinity WKT JSON parse | 512.17 | — | — | 2699.63 (5.27x) | 1411.05 (2.76x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 162.10 | — | — | 1584.12 (9.77x) | 719.54 (4.44x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 517.45 | — | — | 2691.45 (5.20x) | 1410.23 (2.73x) |
| Any Int64Value WKT JSON stringify | 165.86 | — | — | 1596.78 (9.63x) | 890.14 (5.37x) |
| Any Int64Value WKT JSON parse | 544.04 | — | — | 2824.83 (5.19x) | 1649.10 (3.03x) |
| Any ZeroInt64Value WKT JSON stringify | 156.02 | — | — | 918.10 (5.88x) | 795.42 (5.10x) |
| Any ZeroInt64Value WKT JSON parse | 514.16 | — | — | 2173.49 (4.23x) | 1483.86 (2.89x) |
| Any NegativeInt64Value WKT JSON stringify | 164.61 | — | — | 1590.88 (9.66x) | 861.10 (5.23x) |
| Any NegativeInt64Value WKT JSON parse | 545.42 | — | — | 2841.13 (5.21x) | 1661.91 (3.05x) |
| Any MinInt64Value WKT JSON stringify | 164.78 | — | — | 1594.33 (9.68x) | 873.29 (5.30x) |
| Any MinInt64Value WKT JSON parse | 548.02 | — | — | 2853.15 (5.21x) | 1665.76 (3.04x) |
| Any MaxInt64Value WKT JSON stringify | 168.96 | — | — | 1594.37 (9.44x) | 870.69 (5.15x) |
| Any MaxInt64Value WKT JSON parse | 552.30 | — | — | 2850.85 (5.16x) | 1687.24 (3.05x) |
| Any UInt64Value WKT JSON stringify | 172.85 | — | — | 1557.93 (9.01x) | 863.85 (5.00x) |
| Any UInt64Value WKT JSON parse | 544.42 | — | — | 2849.78 (5.23x) | 1640.55 (3.01x) |
| Any ZeroUInt64Value WKT JSON stringify | 160.12 | — | — | 917.11 (5.73x) | 797.76 (4.98x) |
| Any ZeroUInt64Value WKT JSON parse | 520.90 | — | — | 2185.49 (4.20x) | 1502.68 (2.88x) |
| Any MaxUInt64Value WKT JSON stringify | 177.11 | — | — | 1604.36 (9.06x) | 878.35 (4.96x) |
| Any MaxUInt64Value WKT JSON parse | 562.77 | — | — | 2880.26 (5.12x) | 1659.56 (2.95x) |
| Any Int32Value WKT JSON stringify | 162.59 | — | — | 1590.14 (9.78x) | 745.31 (4.58x) |
| Any Int32Value WKT JSON parse | 526.33 | — | — | 2675.24 (5.08x) | 1440.06 (2.74x) |
| Any ZeroInt32Value WKT JSON stringify | 162.68 | — | — | 917.08 (5.64x) | 714.96 (4.39x) |
| Any ZeroInt32Value WKT JSON parse | 521.79 | — | — | 2149.76 (4.12x) | 1408.94 (2.70x) |
| Any NegativeInt32Value WKT JSON stringify | 168.62 | — | — | 1557.19 (9.23x) | 743.57 (4.41x) |
| Any NegativeInt32Value WKT JSON parse | 527.30 | — | — | 2695.40 (5.11x) | 1453.59 (2.76x) |
| Any MinInt32Value WKT JSON stringify | 166.55 | — | — | 1552.10 (9.32x) | 735.01 (4.41x) |
| Any MinInt32Value WKT JSON parse | 531.04 | — | — | 2711.09 (5.11x) | 1498.49 (2.82x) |
| Any MaxInt32Value WKT JSON stringify | 168.07 | — | — | 1552.25 (9.24x) | 740.27 (4.40x) |
| Any MaxInt32Value WKT JSON parse | 533.12 | — | — | 2685.73 (5.04x) | 1444.32 (2.71x) |
| Any UInt32Value WKT JSON stringify | 174.17 | — | — | 1869.72 (10.74x) | 749.21 (4.30x) |
| Any UInt32Value WKT JSON parse | 528.83 | — | — | 2782.99 (5.26x) | 1441.55 (2.73x) |
| Any ZeroUInt32Value WKT JSON stringify | 170.71 | — | — | 916.50 (5.37x) | 727.39 (4.26x) |
| Any ZeroUInt32Value WKT JSON parse | 521.55 | — | — | 2150.63 (4.12x) | 1389.37 (2.66x) |
| Any MaxUInt32Value WKT JSON stringify | 173.84 | — | — | 1555.11 (8.95x) | 734.39 (4.22x) |
| Any MaxUInt32Value WKT JSON parse | 537.47 | — | — | 2688.16 (5.00x) | 1459.05 (2.71x) |
| Any BoolValue WKT JSON stringify | 171.56 | — | — | 3379.75 (19.70x) | 731.78 (4.27x) |
| Any BoolValue WKT JSON parse | 480.06 | — | — | 2626.21 (5.47x) | 1368.95 (2.85x) |
| Any FalseBoolValue WKT JSON stringify | 176.36 | — | — | 918.27 (5.21x) | 712.59 (4.04x) |
| Any FalseBoolValue WKT JSON parse | 481.65 | — | — | 2969.45 (6.17x) | 1324.71 (2.75x) |
| Any StringValue WKT JSON stringify | 197.72 | — | — | 1563.27 (7.91x) | 801.93 (4.06x) |
| Any StringValue WKT JSON parse | 550.47 | — | — | 2666.43 (4.84x) | 1442.69 (2.62x) |
| Any EmptyStringValue WKT JSON stringify | 184.41 | — | — | 921.48 (5.00x) | 754.74 (4.09x) |
| Any EmptyStringValue WKT JSON parse | 518.29 | — | — | 2158.19 (4.16x) | 1361.57 (2.63x) |
| Any BytesValue WKT JSON stringify | 182.96 | — | — | 1583.00 (8.65x) | 845.34 (4.62x) |
| Any BytesValue WKT JSON parse | 553.79 | — | — | 2693.00 (4.86x) | 3240.15 (5.85x) |
| Any EmptyBytesValue WKT JSON stringify | 188.94 | — | — | 919.14 (4.86x) | 766.38 (4.06x) |
| Any EmptyBytesValue WKT JSON parse | 917.56 | — | — | 2176.25 (2.37x) | 1426.12 (1.55x) |
| Nested Any WKT JSON stringify | 540.72 | — | — | 2490.97 (4.61x) | 1627.12 (3.01x) |
| Nested Any WKT JSON parse | 889.79 | — | — | 4269.91 (4.80x) | 5004.87 (5.62x) |
| Duration JSON stringify | 58.20 | — | — | 965.43 (16.59x) | 720.91 (12.39x) |
| Duration JSON parse | 7.59 | — | — | 1446.29 (190.55x) | 693.87 (91.42x) |
| NegativeDuration JSON stringify | 58.70 | — | — | 1000.27 (17.04x) | 813.34 (13.86x) |
| NegativeDuration JSON parse | 8.06 | — | — | 1507.21 (187.00x) | 413.91 (51.35x) |
| FractionalNegativeDuration JSON stringify | 58.51 | — | — | 975.07 (16.67x) | 429.70 (7.34x) |
| FractionalNegativeDuration JSON parse | 8.20 | — | — | 1459.45 (177.98x) | 415.10 (50.62x) |
| MaxDuration JSON stringify | 50.35 | — | — | 861.91 (17.12x) | 623.03 (12.37x) |
| MaxDuration JSON parse | 22.14 | — | — | 1431.55 (64.66x) | 773.85 (34.95x) |
| MinDuration JSON stringify | 50.08 | — | — | 869.32 (17.36x) | 689.74 (13.77x) |
| MinDuration JSON parse | 22.46 | — | — | 1444.18 (64.30x) | 776.38 (34.57x) |
| ZeroDuration JSON stringify | 44.87 | — | — | 816.95 (18.21x) | 1124.59 (25.06x) |
| ZeroDuration JSON parse | 5.60 | — | — | 1359.70 (242.80x) | 677.06 (120.90x) |
| FieldMask JSON stringify | 66.67 | — | — | 886.68 (13.30x) | 1251.67 (18.77x) |
| FieldMask JSON parse | 145.47 | — | — | 1664.77 (11.44x) | 1806.61 (12.42x) |
| Timestamp JSON stringify | 96.67 | — | — | 1145.98 (11.85x) | 884.15 (9.15x) |
| Timestamp JSON parse | 41.34 | — | — | 1477.50 (35.74x) | 871.44 (21.08x) |
| PreEpoch Timestamp JSON stringify | 66.90 | — | — | 1065.02 (15.92x) | 819.10 (12.24x) |
| PreEpoch Timestamp JSON parse | 40.02 | — | — | 1455.56 (36.37x) | 1675.92 (41.88x) |
| Max Timestamp JSON stringify | 79.87 | — | — | 1189.90 (14.90x) | 1058.89 (13.26x) |
| Max Timestamp JSON parse | 46.82 | — | — | 1525.42 (32.58x) | 1019.95 (21.78x) |
| Min Timestamp JSON stringify | 79.69 | — | — | 1069.81 (13.42x) | 836.33 (10.49x) |
| Min Timestamp JSON parse | 37.90 | — | — | 1443.52 (38.09x) | 861.96 (22.74x) |
| Empty JSON stringify | 20.87 | — | — | 500.55 (23.98x) | 353.87 (16.96x) |
| Empty JSON parse | 67.41 | — | — | 724.45 (10.75x) | 935.08 (13.87x) |
| Struct JSON stringify | 174.61 | — | — | 5719.12 (32.75x) | 5629.00 (32.24x) |
| Struct JSON parse | 869.31 | — | — | 10846.20 (12.48x) | 6263.32 (7.20x) |
| Value JSON stringify | 354.51 | — | — | 6848.31 (19.32x) | 4454.45 (12.57x) |
| Value JSON parse | 1440.55 | — | — | 12619.30 (8.76x) | 6174.33 (4.29x) |
| ListValue JSON stringify | 268.41 | — | — | 4769.70 (17.77x) | 2250.79 (8.39x) |
| ListValue JSON parse | 968.24 | — | — | 8570.71 (8.85x) | 4069.43 (4.20x) |
| DoubleValue JSON stringify | 80.02 | — | — | 866.22 (10.83x) | 198.90 (2.49x) |
| DoubleValue JSON parse | 115.34 | — | — | 1232.26 (10.68x) | 321.40 (2.79x) |
| ZeroDoubleValue JSON stringify | 48.72 | — | — | 804.79 (16.52x) | 135.58 (2.78x) |
| ZeroDoubleValue JSON parse | 111.42 | — | — | 1159.44 (10.41x) | 295.41 (2.65x) |
| DoubleValue NaN JSON stringify | 46.63 | — | — | 665.40 (14.27x) | 126.71 (2.72x) |
| DoubleValue NaN JSON parse | 114.57 | — | — | 1087.67 (9.49x) | 285.28 (2.49x) |
| DoubleValue Infinity JSON stringify | 48.24 | — | — | 664.90 (13.78x) | 127.10 (2.63x) |
| DoubleValue Infinity JSON parse | 112.62 | — | — | 1097.16 (9.74x) | 277.31 (2.46x) |
| DoubleValue NegativeInfinity JSON stringify | 54.27 | — | — | 667.37 (12.30x) | 122.83 (2.26x) |
| DoubleValue NegativeInfinity JSON parse | 125.22 | — | — | 1106.95 (8.84x) | 295.61 (2.36x) |
| FloatValue JSON stringify | 75.49 | — | — | 798.34 (10.58x) | 178.90 (2.37x) |
| FloatValue JSON parse | 112.12 | — | — | 1260.47 (11.24x) | 286.63 (2.56x) |
| ZeroFloatValue JSON stringify | 47.62 | — | — | 744.59 (15.64x) | 142.06 (2.98x) |
| ZeroFloatValue JSON parse | 108.23 | — | — | 1200.68 (11.09x) | 257.35 (2.38x) |
| FloatValue NaN JSON stringify | 46.61 | — | — | 642.13 (13.78x) | 130.56 (2.80x) |
| FloatValue NaN JSON parse | 105.81 | — | — | 1080.58 (10.21x) | 279.24 (2.64x) |
| FloatValue Infinity JSON stringify | 48.06 | — | — | 640.62 (13.33x) | 123.75 (2.57x) |
| FloatValue Infinity JSON parse | 107.57 | — | — | 1087.68 (10.11x) | 274.45 (2.55x) |
| FloatValue NegativeInfinity JSON stringify | 48.26 | — | — | 645.32 (13.37x) | 123.43 (2.56x) |
| FloatValue NegativeInfinity JSON parse | 109.30 | — | — | 1115.70 (10.21x) | 281.72 (2.58x) |
| Int64Value JSON stringify | 49.97 | — | — | 676.83 (13.54x) | 284.88 (5.70x) |
| Int64Value JSON parse | 127.63 | — | — | 1232.96 (9.66x) | 484.09 (3.79x) |
| ZeroInt64Value JSON stringify | 41.98 | — | — | 611.69 (14.57x) | 188.09 (4.48x) |
| ZeroInt64Value JSON parse | 106.05 | — | — | 1088.00 (10.26x) | 344.40 (3.25x) |
| NegativeInt64Value JSON stringify | 48.52 | — | — | 675.17 (13.92x) | 280.50 (5.78x) |
| NegativeInt64Value JSON parse | 128.79 | — | — | 1244.55 (9.66x) | 484.97 (3.77x) |
| MinInt64Value JSON stringify | 49.57 | — | — | 680.51 (13.73x) | 286.25 (5.77x) |
| MinInt64Value JSON parse | 134.81 | — | — | 1235.35 (9.16x) | 513.06 (3.81x) |
| MaxInt64Value JSON stringify | 49.60 | — | — | 684.63 (13.80x) | 281.21 (5.67x) |
| MaxInt64Value JSON parse | 135.38 | — | — | 1248.30 (9.22x) | 476.56 (3.52x) |
| UInt64Value JSON stringify | 50.24 | — | — | 680.16 (13.54x) | 284.51 (5.66x) |
| UInt64Value JSON parse | 125.32 | — | — | 1304.72 (10.41x) | 466.77 (3.72x) |
| ZeroUInt64Value JSON stringify | 41.97 | — | — | 610.03 (14.53x) | 189.05 (4.50x) |
| ZeroUInt64Value JSON parse | 104.14 | — | — | 1099.25 (10.56x) | 372.41 (3.58x) |
| MaxUInt64Value JSON stringify | 49.68 | — | — | 721.21 (14.52x) | 289.89 (5.84x) |
| MaxUInt64Value JSON parse | 149.43 | — | — | 1258.77 (8.42x) | 482.39 (3.23x) |
| Int32Value JSON stringify | 46.31 | — | — | 639.03 (13.80x) | 141.62 (3.06x) |
| Int32Value JSON parse | 129.16 | — | — | 1189.54 (9.21x) | 308.22 (2.39x) |
| ZeroInt32Value JSON stringify | 46.19 | — | — | 613.72 (13.29x) | 136.70 (2.96x) |
| ZeroInt32Value JSON parse | 124.75 | — | — | 1147.04 (9.19x) | 272.20 (2.18x) |
| NegativeInt32Value JSON stringify | 46.20 | — | — | 639.50 (13.84x) | 131.22 (2.84x) |
| NegativeInt32Value JSON parse | 128.47 | — | — | 1191.40 (9.27x) | 329.01 (2.56x) |
| MinInt32Value JSON stringify | 46.93 | — | — | 638.32 (13.60x) | 131.72 (2.81x) |
| MinInt32Value JSON parse | 133.64 | — | — | 1220.13 (9.13x) | 356.56 (2.67x) |
| MaxInt32Value JSON stringify | 47.16 | — | — | 640.81 (13.59x) | 140.64 (2.98x) |
| MaxInt32Value JSON parse | 135.08 | — | — | 1200.28 (8.89x) | 340.63 (2.52x) |
| UInt32Value JSON stringify | 46.22 | — | — | 651.75 (14.10x) | 206.10 (4.46x) |
| UInt32Value JSON parse | 129.34 | — | — | 1316.26 (10.18x) | 308.75 (2.39x) |
| ZeroUInt32Value JSON stringify | 46.45 | — | — | 628.30 (13.53x) | 132.15 (2.84x) |
| ZeroUInt32Value JSON parse | 124.88 | — | — | 1149.96 (9.21x) | 266.05 (2.13x) |
| MaxUInt32Value JSON stringify | 46.91 | — | — | 647.22 (13.80x) | 137.72 (2.94x) |
| MaxUInt32Value JSON parse | 135.81 | — | — | 1213.69 (8.94x) | 333.27 (2.45x) |
| BoolValue JSON stringify | 44.81 | — | — | 762.07 (17.01x) | 126.85 (2.83x) |
| BoolValue JSON parse | 59.40 | — | — | 2058.17 (34.65x) | 223.42 (3.76x) |
| FalseBoolValue JSON stringify | 44.81 | — | — | 604.35 (13.49x) | 122.73 (2.74x) |
| FalseBoolValue JSON parse | 59.90 | — | — | 1065.60 (17.79x) | 224.97 (3.76x) |
| StringValue JSON stringify | 51.89 | — | — | 1142.73 (22.02x) | 191.42 (3.69x) |
| StringValue JSON parse | 137.27 | — | — | 2140.65 (15.59x) | 316.20 (2.30x) |
| EmptyStringValue JSON stringify | 48.88 | — | — | 1075.50 (22.00x) | 179.00 (3.66x) |
| EmptyStringValue JSON parse | 81.73 | — | — | 2076.65 (25.41x) | 239.14 (2.93x) |
| BytesValue JSON stringify | 49.42 | — | — | 659.99 (13.35x) | 208.78 (4.22x) |
| BytesValue JSON parse | 147.91 | — | — | 1167.16 (7.89x) | 342.48 (2.32x) |
| EmptyBytesValue JSON stringify | 41.17 | — | — | 633.05 (15.38x) | 198.28 (4.82x) |
| EmptyBytesValue JSON parse | 89.73 | — | — | 1130.72 (12.60x) | 288.50 (3.22x) |
| TextFormat parse | 728.62 | — | — | 4985.11 (6.84x) | 6524.06 (8.95x) |
| packed bool encode | 2.01 | 1337.56 (665.45x) | 521.58 (259.49x) | 15.78 (7.85x) | 2392.45 (1190.27x) |
| packed bool decode | 263.75 | 1542.87 (5.85x) | 2565.91 (9.73x) | 807.49 (3.06x) | 1573.68 (5.97x) |
| shuffled large map deterministic binary encode | 27771.10 | — | — | 93047.80 (3.35x) | 441264.39 (15.89x) |
| large map decode | 25595.22 | 90312.21 (3.53x) | 89573.68 (3.50x) | 89177.40 (3.48x) | 273467.71 (10.68x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded zero/positive/integer-negative/fractional-negative/min-max-bound `Duration`, `Struct`, `Value`,
`FieldMask`, min/pre/post/max-bound `Timestamp`, `Empty`, min/zero/positive/negative/max `Int64Value`, zero/finite `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), zero/finite `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), zero/normal/max `UInt64Value`, min/zero/positive/negative/max `Int32Value`, zero/normal/max `UInt32Value`, true/false `BoolValue`, non-empty/empty `StringValue`, base64/empty `BytesValue`, and recursive nested `Any` payloads), direct zero/positive/integer-negative/fractional-negative/min-max-bound Duration and min/pre/post/max-bound Timestamp WKT JSON plus other direct WKT JSON, TextFormat, packed scalars, large bytes,
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
