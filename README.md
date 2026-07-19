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

Latest accepted comparison (`/tmp/pbz-compare-default-wrapper-json-isolated.log`,
summarized in `/tmp/pbz-summary-default-wrapper-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 16.96 | 98.22 (5.79x) | 59.32 (3.50x) | 144.32 (8.51x) | 865.02 (51.00x) |
| binary decode | 91.97 | 251.53 (2.73x) | 311.62 (3.39x) | 399.89 (4.35x) | 900.00 (9.79x) |
| unknown fields count by number | 3.59 | — | — | 250.37 (69.74x) | — |
| scalarmix encode | 19.67 | 102.12 (5.19x) | 64.83 (3.30x) | 48.06 (2.44x) | 211.85 (10.77x) |
| scalarmix decode | 39.72 | 136.18 (3.43x) | 237.41 (5.98x) | 111.11 (2.80x) | 307.90 (7.75x) |
| textbytes encode | 15.89 | 77.26 (4.86x) | 43.75 (2.75x) | 118.73 (7.47x) | 149.79 (9.43x) |
| largebytes decode | 94.84 | 5688.78 (59.98x) | 3136.21 (33.07x) | 2709.86 (28.57x) | 20362.83 (214.71x) |
| complex decode | 168.92 | 389.33 (2.30x) | 336.54 (1.99x) | 394.64 (2.34x) | 1354.49 (8.02x) |
| complex JSON parse | 2466.85 | — | — | 11905.50 (4.83x) | 7583.64 (3.07x) |
| packed int32 decode | 764.25 | 1924.37 (2.52x) | 3222.00 (4.22x) | 941.66 (1.23x) | 2537.42 (3.32x) |
| Any WKT JSON stringify | 136.39 | — | — | 1883.63 (13.81x) | 995.38 (7.30x) |
| Any WKT JSON parse | 549.62 | — | — | 2982.83 (5.43x) | 1531.07 (2.79x) |
| Any NegativeDuration WKT JSON stringify | 140.00 | — | — | 1940.41 (13.86x) | 1022.48 (7.30x) |
| Any NegativeDuration WKT JSON parse | 553.70 | — | — | 3074.12 (5.55x) | 1582.54 (2.86x) |
| Any FractionalNegativeDuration WKT JSON stringify | 133.30 | — | — | 1895.34 (14.22x) | 1005.18 (7.54x) |
| Any FractionalNegativeDuration WKT JSON parse | 546.72 | — | — | 3054.35 (5.59x) | 1514.19 (2.77x) |
| Any MaxDuration WKT JSON stringify | 118.26 | — | — | 1751.93 (14.81x) | 987.38 (8.35x) |
| Any MaxDuration WKT JSON parse | 559.66 | — | — | 2969.37 (5.31x) | 1545.27 (2.76x) |
| Any MinDuration WKT JSON stringify | 121.73 | — | — | 1765.45 (14.50x) | 1016.33 (8.35x) |
| Any MinDuration WKT JSON parse | 563.06 | — | — | 3027.64 (5.38x) | 1544.43 (2.74x) |
| Any ZeroDuration WKT JSON stringify | 113.87 | — | — | 917.63 (8.06x) | 968.65 (8.51x) |
| Any ZeroDuration WKT JSON parse | 493.05 | — | — | 2247.08 (4.56x) | 1442.08 (2.92x) |
| Any FieldMask WKT JSON stringify | 236.20 | — | — | 1745.81 (7.39x) | 1413.78 (5.99x) |
| Any FieldMask WKT JSON parse | 740.20 | — | — | 3186.14 (4.30x) | 2066.13 (2.79x) |
| Any Timestamp WKT JSON stringify | 183.40 | — | — | 2017.92 (11.00x) | 995.24 (5.43x) |
| Any Timestamp WKT JSON parse | 592.29 | — | — | 3009.00 (5.08x) | 1586.82 (2.68x) |
| Any PreEpoch Timestamp WKT JSON stringify | 141.78 | — | — | 1941.66 (13.69x) | 982.40 (6.93x) |
| Any PreEpoch Timestamp WKT JSON parse | 583.03 | — | — | 3031.56 (5.20x) | 1576.18 (2.70x) |
| Any Max Timestamp WKT JSON stringify | 161.27 | — | — | 2047.10 (12.69x) | 1024.71 (6.35x) |
| Any Max Timestamp WKT JSON parse | 607.25 | — | — | 3086.11 (5.08x) | 1649.06 (2.72x) |
| Any Min Timestamp WKT JSON stringify | 169.64 | — | — | 1931.61 (11.39x) | 977.98 (5.77x) |
| Any Min Timestamp WKT JSON parse | 581.33 | — | — | 3018.66 (5.19x) | 1650.49 (2.84x) |
| Any Empty WKT JSON stringify | 96.99 | — | — | 908.88 (9.37x) | 662.95 (6.84x) |
| Any Empty WKT JSON parse | 358.72 | — | — | 2116.60 (5.90x) | 1346.04 (3.75x) |
| Any Struct WKT JSON stringify | 624.26 | — | — | 5818.17 (9.32x) | 6030.81 (9.66x) |
| Any Struct WKT JSON parse | 1772.31 | — | — | 11126.60 (6.28x) | 8758.42 (4.94x) |
| Any Value WKT JSON stringify | 648.92 | — | — | 5877.97 (9.06x) | 6451.20 (9.94x) |
| Any Value WKT JSON parse | 1835.43 | — | — | 11340.60 (6.18x) | 9150.83 (4.99x) |
| Any DoubleValue WKT JSON stringify | 194.43 | — | — | 1791.78 (9.22x) | 809.35 (4.16x) |
| Any DoubleValue WKT JSON parse | 544.14 | — | — | 2739.39 (5.03x) | 1431.76 (2.63x) |
| Any DoubleValue NaN WKT JSON stringify | 170.68 | — | — | 1578.43 (9.25x) | 714.46 (4.19x) |
| Any DoubleValue NaN WKT JSON parse | 539.93 | — | — | 2670.05 (4.95x) | 1384.57 (2.56x) |
| Any DoubleValue Infinity WKT JSON stringify | 179.61 | — | — | 1567.64 (8.73x) | 714.56 (3.98x) |
| Any DoubleValue Infinity WKT JSON parse | 542.67 | — | — | 2706.05 (4.99x) | 1416.67 (2.61x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 168.61 | — | — | 1567.85 (9.30x) | 732.49 (4.34x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 545.45 | — | — | 2682.12 (4.92x) | 1420.86 (2.60x) |
| Any FloatValue WKT JSON stringify | 199.37 | — | — | 1735.91 (8.71x) | 792.54 (3.98x) |
| Any FloatValue WKT JSON parse | 552.56 | — | — | 2704.73 (4.89x) | 1402.74 (2.54x) |
| Any FloatValue NaN WKT JSON stringify | 159.92 | — | — | 1554.00 (9.72x) | 725.82 (4.54x) |
| Any FloatValue NaN WKT JSON parse | 543.69 | — | — | 2623.56 (4.83x) | 1382.48 (2.54x) |
| Any FloatValue Infinity WKT JSON stringify | 163.35 | — | — | 1555.76 (9.52x) | 722.96 (4.43x) |
| Any FloatValue Infinity WKT JSON parse | 550.05 | — | — | 2667.78 (4.85x) | 1404.13 (2.55x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 165.39 | — | — | 1551.94 (9.38x) | 725.10 (4.38x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 550.33 | — | — | 2668.03 (4.85x) | 1407.43 (2.56x) |
| Any Int64Value WKT JSON stringify | 169.65 | — | — | 1569.18 (9.25x) | 857.65 (5.06x) |
| Any Int64Value WKT JSON parse | 578.09 | — | — | 2784.80 (4.82x) | 1636.72 (2.83x) |
| Any NegativeInt64Value WKT JSON stringify | 170.39 | — | — | 1559.72 (9.15x) | 852.56 (5.00x) |
| Any NegativeInt64Value WKT JSON parse | 571.34 | — | — | 2809.45 (4.92x) | 1658.31 (2.90x) |
| Any UInt64Value WKT JSON stringify | 174.57 | — | — | 1551.85 (8.89x) | 859.37 (4.92x) |
| Any UInt64Value WKT JSON parse | 582.82 | — | — | 2796.72 (4.80x) | 1623.69 (2.79x) |
| Any MaxUInt64Value WKT JSON stringify | 176.78 | — | — | 1620.73 (9.17x) | 870.98 (4.93x) |
| Any MaxUInt64Value WKT JSON parse | 591.51 | — | — | 2839.93 (4.80x) | 1690.59 (2.86x) |
| Any Int32Value WKT JSON stringify | 170.89 | — | — | 2136.08 (12.50x) | 726.49 (4.25x) |
| Any Int32Value WKT JSON parse | 559.25 | — | — | 4723.34 (8.45x) | 1450.62 (2.59x) |
| Any NegativeInt32Value WKT JSON stringify | 170.72 | — | — | 2650.88 (15.53x) | 733.60 (4.30x) |
| Any NegativeInt32Value WKT JSON parse | 559.13 | — | — | 2687.87 (4.81x) | 1448.01 (2.59x) |
| Any UInt32Value WKT JSON stringify | 173.50 | — | — | 1542.53 (8.89x) | 742.94 (4.28x) |
| Any UInt32Value WKT JSON parse | 567.71 | — | — | 2664.15 (4.69x) | 1441.62 (2.54x) |
| Any MaxUInt32Value WKT JSON stringify | 180.29 | — | — | 1545.22 (8.57x) | 740.90 (4.11x) |
| Any MaxUInt32Value WKT JSON parse | 576.32 | — | — | 2671.31 (4.64x) | 1454.90 (2.52x) |
| Any BoolValue WKT JSON stringify | 170.73 | — | — | 1551.86 (9.09x) | 725.89 (4.25x) |
| Any BoolValue WKT JSON parse | 510.19 | — | — | 2661.26 (5.22x) | 1334.28 (2.62x) |
| Any FalseBoolValue WKT JSON stringify | 169.07 | — | — | 1759.43 (10.41x) | 705.19 (4.17x) |
| Any FalseBoolValue WKT JSON parse | 511.35 | — | — | 4309.15 (8.43x) | 1349.54 (2.64x) |
| Any StringValue WKT JSON stringify | 209.27 | — | — | 1561.36 (7.46x) | 802.60 (3.84x) |
| Any StringValue WKT JSON parse | 580.09 | — | — | 2651.90 (4.57x) | 1449.07 (2.50x) |
| Any EmptyStringValue WKT JSON stringify | 194.38 | — | — | 1542.24 (7.93x) | 750.78 (3.86x) |
| Any EmptyStringValue WKT JSON parse | 549.37 | — | — | 4042.67 (7.36x) | 1363.12 (2.48x) |
| Any BytesValue WKT JSON stringify | 183.29 | — | — | 1585.32 (8.65x) | 860.61 (4.70x) |
| Any BytesValue WKT JSON parse | 591.05 | — | — | 2704.20 (4.58x) | 1474.70 (2.50x) |
| Any EmptyBytesValue WKT JSON stringify | 178.12 | — | — | 1463.03 (8.21x) | 773.39 (4.34x) |
| Any EmptyBytesValue WKT JSON parse | 552.50 | — | — | 2569.97 (4.65x) | 1421.84 (2.57x) |
| Nested Any WKT JSON stringify | 307.88 | — | — | 2478.63 (8.05x) | 1456.44 (4.73x) |
| Nested Any WKT JSON parse | 906.18 | — | — | 4282.82 (4.73x) | 2883.23 (3.18x) |
| Duration JSON stringify | 61.80 | — | — | 954.05 (15.44x) | 389.11 (6.30x) |
| Duration JSON parse | 7.77 | — | — | 1442.43 (185.64x) | 391.47 (50.38x) |
| NegativeDuration JSON stringify | 63.08 | — | — | 1009.26 (16.00x) | 419.35 (6.65x) |
| NegativeDuration JSON parse | 7.91 | — | — | 1504.73 (190.23x) | 387.79 (49.03x) |
| FractionalNegativeDuration JSON stringify | 62.39 | — | — | 975.21 (15.63x) | 437.06 (7.01x) |
| FractionalNegativeDuration JSON parse | 7.90 | — | — | 1456.34 (184.35x) | 372.74 (47.18x) |
| MaxDuration JSON stringify | 52.32 | — | — | 844.37 (16.14x) | 421.04 (8.05x) |
| MaxDuration JSON parse | 22.17 | — | — | 1427.01 (64.37x) | 442.91 (19.98x) |
| MinDuration JSON stringify | 51.95 | — | — | 871.79 (16.78x) | 463.15 (8.92x) |
| MinDuration JSON parse | 24.86 | — | — | 1441.14 (57.97x) | 405.85 (16.33x) |
| ZeroDuration JSON stringify | 48.12 | — | — | 812.64 (16.89x) | 360.66 (7.50x) |
| ZeroDuration JSON parse | 5.58 | — | — | 1358.75 (243.50x) | 320.32 (57.41x) |
| FieldMask JSON stringify | 92.59 | — | — | 889.56 (9.61x) | 670.16 (7.24x) |
| FieldMask JSON parse | 148.00 | — | — | 1654.70 (11.18x) | 920.40 (6.22x) |
| Timestamp JSON stringify | 96.75 | — | — | 1140.21 (11.79x) | 424.70 (4.39x) |
| Timestamp JSON parse | 41.34 | — | — | 1483.20 (35.88x) | 446.13 (10.79x) |
| PreEpoch Timestamp JSON stringify | 67.05 | — | — | 1056.79 (15.76x) | 398.74 (5.95x) |
| PreEpoch Timestamp JSON parse | 40.03 | — | — | 1451.90 (36.27x) | 426.01 (10.64x) |
| Max Timestamp JSON stringify | 79.92 | — | — | 1192.69 (14.92x) | 423.67 (5.30x) |
| Max Timestamp JSON parse | 46.77 | — | — | 1535.81 (32.84x) | 461.89 (9.88x) |
| Min Timestamp JSON stringify | 80.15 | — | — | 1055.13 (13.16x) | 402.13 (5.02x) |
| Min Timestamp JSON parse | 38.08 | — | — | 1444.09 (37.92x) | 426.93 (11.21x) |
| Empty JSON stringify | 21.58 | — | — | 498.84 (23.12x) | 83.16 (3.85x) |
| Empty JSON parse | 67.45 | — | — | 721.41 (10.70x) | 206.57 (3.06x) |
| Struct JSON stringify | 174.93 | — | — | 5716.94 (32.68x) | 3067.60 (17.54x) |
| Struct JSON parse | 915.60 | — | — | 10899.00 (11.90x) | 4667.27 (5.10x) |
| Value JSON stringify | 178.20 | — | — | 6595.42 (37.01x) | 3218.99 (18.06x) |
| Value JSON parse | 867.93 | — | — | 12107.30 (13.95x) | 4886.37 (5.63x) |
| ListValue JSON stringify | 133.54 | — | — | 4749.73 (35.57x) | 2114.01 (15.83x) |
| ListValue JSON parse | 712.16 | — | — | 8501.48 (11.94x) | 3806.97 (5.35x) |
| DoubleValue JSON stringify | 68.01 | — | — | 858.50 (12.62x) | 204.49 (3.01x) |
| DoubleValue JSON parse | 110.39 | — | — | 1227.71 (11.12x) | 285.27 (2.58x) |
| DoubleValue NaN JSON stringify | 47.88 | — | — | 660.02 (13.78x) | 127.14 (2.66x) |
| DoubleValue NaN JSON parse | 105.24 | — | — | 1091.26 (10.37x) | 274.01 (2.60x) |
| DoubleValue Infinity JSON stringify | 48.49 | — | — | 661.73 (13.65x) | 121.42 (2.50x) |
| DoubleValue Infinity JSON parse | 105.67 | — | — | 1095.29 (10.37x) | 284.20 (2.69x) |
| DoubleValue NegativeInfinity JSON stringify | 48.57 | — | — | 654.83 (13.48x) | 124.11 (2.56x) |
| DoubleValue NegativeInfinity JSON parse | 107.72 | — | — | 1114.68 (10.35x) | 276.27 (2.56x) |
| FloatValue JSON stringify | 70.38 | — | — | 797.00 (11.32x) | 182.96 (2.60x) |
| FloatValue JSON parse | 112.22 | — | — | 1213.43 (10.81x) | 293.36 (2.61x) |
| FloatValue NaN JSON stringify | 47.66 | — | — | 639.20 (13.41x) | 129.15 (2.71x) |
| FloatValue NaN JSON parse | 104.95 | — | — | 1081.52 (10.31x) | 284.84 (2.71x) |
| FloatValue Infinity JSON stringify | 47.88 | — | — | 641.12 (13.39x) | 126.28 (2.64x) |
| FloatValue Infinity JSON parse | 105.99 | — | — | 1090.18 (10.29x) | 276.25 (2.61x) |
| FloatValue NegativeInfinity JSON stringify | 48.13 | — | — | 635.17 (13.20x) | 127.02 (2.64x) |
| FloatValue NegativeInfinity JSON parse | 108.27 | — | — | 1095.49 (10.12x) | 279.29 (2.58x) |
| Int64Value JSON stringify | 50.05 | — | — | 676.32 (13.51x) | 279.68 (5.59x) |
| Int64Value JSON parse | 126.63 | — | — | 1224.18 (9.67x) | 463.48 (3.66x) |
| NegativeInt64Value JSON stringify | 48.51 | — | — | 674.97 (13.91x) | 279.82 (5.77x) |
| NegativeInt64Value JSON parse | 134.86 | — | — | 1220.95 (9.05x) | 478.13 (3.55x) |
| UInt64Value JSON stringify | 50.36 | — | — | 678.83 (13.48x) | 282.84 (5.62x) |
| UInt64Value JSON parse | 125.79 | — | — | 1212.41 (9.64x) | 465.83 (3.70x) |
| MaxUInt64Value JSON stringify | 49.95 | — | — | 684.80 (13.71x) | 291.26 (5.83x) |
| MaxUInt64Value JSON parse | 136.38 | — | — | 1278.44 (9.37x) | 475.57 (3.49x) |
| Int32Value JSON stringify | 48.81 | — | — | 630.10 (12.91x) | 136.51 (2.80x) |
| Int32Value JSON parse | 130.80 | — | — | 1178.93 (9.01x) | 312.57 (2.39x) |
| NegativeInt32Value JSON stringify | 48.65 | — | — | 1669.38 (34.31x) | 138.13 (2.84x) |
| NegativeInt32Value JSON parse | 130.04 | — | — | 1540.57 (11.85x) | 331.96 (2.55x) |
| UInt32Value JSON stringify | 48.61 | — | — | 634.22 (13.05x) | 139.64 (2.87x) |
| UInt32Value JSON parse | 130.86 | — | — | 1188.33 (9.08x) | 312.95 (2.39x) |
| MaxUInt32Value JSON stringify | 48.44 | — | — | 631.26 (13.03x) | 140.57 (2.90x) |
| MaxUInt32Value JSON parse | 136.34 | — | — | 1206.67 (8.85x) | 329.32 (2.42x) |
| BoolValue JSON stringify | 46.17 | — | — | 611.80 (13.25x) | 125.51 (2.72x) |
| BoolValue JSON parse | 59.39 | — | — | 1119.60 (18.85x) | 228.18 (3.84x) |
| FalseBoolValue JSON stringify | 46.16 | — | — | 615.68 (13.34x) | 129.83 (2.81x) |
| FalseBoolValue JSON parse | 60.16 | — | — | 1080.99 (17.97x) | 224.41 (3.73x) |
| StringValue JSON stringify | 53.13 | — | — | 1359.29 (25.58x) | 188.12 (3.54x) |
| StringValue JSON parse | 137.72 | — | — | 2122.69 (15.41x) | 311.68 (2.26x) |
| EmptyStringValue JSON stringify | 51.09 | — | — | 1261.86 (24.70x) | 182.65 (3.58x) |
| EmptyStringValue JSON parse | 81.46 | — | — | 1669.88 (20.50x) | 241.83 (2.97x) |
| BytesValue JSON stringify | 50.79 | — | — | 1147.21 (22.59x) | 206.87 (4.07x) |
| BytesValue JSON parse | 148.29 | — | — | 2213.63 (14.93x) | 351.11 (2.37x) |
| EmptyBytesValue JSON stringify | 42.37 | — | — | 1158.87 (27.35x) | 190.42 (4.49x) |
| EmptyBytesValue JSON parse | 89.97 | — | — | 2214.94 (24.62x) | 289.42 (3.22x) |
| TextFormat parse | 693.09 | — | — | 5114.29 (7.38x) | 6594.02 (9.51x) |
| packed bool encode | 2.01 | 1358.35 (675.80x) | 521.30 (259.35x) | 16.28 (8.10x) | 2386.47 (1187.30x) |
| packed bool decode | 262.60 | 1535.52 (5.85x) | 2564.18 (9.76x) | 808.96 (3.08x) | 1554.46 (5.92x) |
| shuffled large map deterministic binary encode | 28834.32 | — | — | 94674.20 (3.28x) | 442678.98 (15.35x) |
| large map decode | 25926.50 | 91314.91 (3.52x) | 96578.03 (3.73x) | 87834.30 (3.39x) | 269908.32 (10.41x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded zero/positive/integer-negative/fractional-negative/min-max-bound `Duration`, `Struct`, `Value`,
`FieldMask`, min/pre/post/max-bound `Timestamp`, `Empty`, positive/negative `Int64Value`, `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), normal/max `UInt64Value`, positive/negative `Int32Value`, normal/max `UInt32Value`, true/false `BoolValue`, non-empty/empty `StringValue`, base64/empty `BytesValue`, and recursive nested `Any` payloads), direct zero/positive/integer-negative/fractional-negative/min-max-bound Duration and min/pre/post/max-bound Timestamp WKT JSON plus other direct WKT JSON, TextFormat, packed scalars, large bytes,
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
