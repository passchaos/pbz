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

Latest accepted comparison (`/tmp/pbz-compare-zero-numeric-wrapper-json-isolated.log`,
summarized in `/tmp/pbz-summary-zero-numeric-wrapper-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 17.54 | 99.41 (5.67x) | 50.26 (2.87x) | 132.92 (7.58x) | 867.62 (49.47x) |
| binary decode | 87.35 | 250.64 (2.87x) | 231.43 (2.65x) | 441.54 (5.05x) | 908.99 (10.41x) |
| unknown fields count by number | 3.57 | — | — | 257.80 (72.21x) | — |
| scalarmix encode | 16.49 | 95.97 (5.82x) | 49.08 (2.98x) | 52.08 (3.16x) | 208.84 (12.66x) |
| scalarmix decode | 43.06 | 135.01 (3.14x) | 172.20 (4.00x) | 121.95 (2.83x) | 308.03 (7.15x) |
| textbytes encode | 16.25 | 77.49 (4.77x) | 33.59 (2.07x) | 152.56 (9.39x) | 154.60 (9.51x) |
| largebytes decode | 89.03 | 5616.74 (63.09x) | 3024.55 (33.97x) | 3091.88 (34.73x) | 20835.74 (234.03x) |
| complex decode | 169.74 | 386.22 (2.28x) | 344.42 (2.03x) | 393.48 (2.32x) | 1348.39 (7.94x) |
| complex JSON parse | 2383.29 | — | — | 11850.60 (4.97x) | 7645.36 (3.21x) |
| packed int32 decode | 687.74 | 1939.68 (2.82x) | 3197.85 (4.65x) | 937.44 (1.36x) | 2637.39 (3.83x) |
| Any WKT JSON stringify | 144.95 | — | — | 1882.00 (12.98x) | 985.97 (6.80x) |
| Any WKT JSON parse | 538.10 | — | — | 2983.68 (5.54x) | 1540.97 (2.86x) |
| Any NegativeDuration WKT JSON stringify | 142.28 | — | — | 1938.74 (13.63x) | 1026.54 (7.21x) |
| Any NegativeDuration WKT JSON parse | 542.70 | — | — | 3099.26 (5.71x) | 1590.45 (2.93x) |
| Any FractionalNegativeDuration WKT JSON stringify | 131.64 | — | — | 1899.51 (14.43x) | 989.59 (7.52x) |
| Any FractionalNegativeDuration WKT JSON parse | 531.59 | — | — | 3075.77 (5.79x) | 1527.42 (2.87x) |
| Any MaxDuration WKT JSON stringify | 119.89 | — | — | 1758.69 (14.67x) | 993.15 (8.28x) |
| Any MaxDuration WKT JSON parse | 553.73 | — | — | 2991.77 (5.40x) | 1564.58 (2.83x) |
| Any MinDuration WKT JSON stringify | 124.70 | — | — | 1772.54 (14.21x) | 1005.84 (8.07x) |
| Any MinDuration WKT JSON parse | 556.77 | — | — | 3029.86 (5.44x) | 1539.54 (2.77x) |
| Any ZeroDuration WKT JSON stringify | 109.49 | — | — | 915.40 (8.36x) | 959.12 (8.76x) |
| Any ZeroDuration WKT JSON parse | 482.28 | — | — | 2248.85 (4.66x) | 1459.18 (3.03x) |
| Any FieldMask WKT JSON stringify | 226.87 | — | — | 1741.09 (7.67x) | 1427.07 (6.29x) |
| Any FieldMask WKT JSON parse | 735.36 | — | — | 3160.41 (4.30x) | 2074.49 (2.82x) |
| Any Timestamp WKT JSON stringify | 177.74 | — | — | 2011.00 (11.31x) | 1006.61 (5.66x) |
| Any Timestamp WKT JSON parse | 583.05 | — | — | 3017.86 (5.18x) | 1612.01 (2.76x) |
| Any PreEpoch Timestamp WKT JSON stringify | 142.53 | — | — | 1940.14 (13.61x) | 978.32 (6.86x) |
| Any PreEpoch Timestamp WKT JSON parse | 571.65 | — | — | 3041.26 (5.32x) | 1582.01 (2.77x) |
| Any Max Timestamp WKT JSON stringify | 167.63 | — | — | 2042.37 (12.18x) | 1013.01 (6.04x) |
| Any Max Timestamp WKT JSON parse | 598.00 | — | — | 3102.66 (5.19x) | 1632.77 (2.73x) |
| Any Min Timestamp WKT JSON stringify | 165.14 | — | — | 1925.47 (11.66x) | 979.79 (5.93x) |
| Any Min Timestamp WKT JSON parse | 569.35 | — | — | 3023.90 (5.31x) | 1579.60 (2.77x) |
| Any Empty WKT JSON stringify | 95.98 | — | — | 910.62 (9.49x) | 631.62 (6.58x) |
| Any Empty WKT JSON parse | 346.58 | — | — | 2132.30 (6.15x) | 1354.11 (3.91x) |
| Any Struct WKT JSON stringify | 625.96 | — | — | 5883.07 (9.40x) | 6153.78 (9.83x) |
| Any Struct WKT JSON parse | 1777.78 | — | — | 11152.30 (6.27x) | 8828.76 (4.97x) |
| Any Value WKT JSON stringify | 654.49 | — | — | 5950.86 (9.09x) | 6402.44 (9.78x) |
| Any Value WKT JSON parse | 1863.30 | — | — | 11348.00 (6.09x) | 10022.19 (5.38x) |
| Any DoubleValue WKT JSON stringify | 200.69 | — | — | 1864.89 (9.29x) | 818.46 (4.08x) |
| Any DoubleValue WKT JSON parse | 533.48 | — | — | 2834.09 (5.31x) | 1481.73 (2.78x) |
| Any ZeroDoubleValue WKT JSON stringify | 171.47 | — | — | 924.95 (5.39x) | 748.00 (4.36x) |
| Any ZeroDoubleValue WKT JSON parse | 527.90 | — | — | 2169.68 (4.11x) | 1447.14 (2.74x) |
| Any DoubleValue NaN WKT JSON stringify | 168.71 | — | — | 1567.78 (9.29x) | 747.84 (4.43x) |
| Any DoubleValue NaN WKT JSON parse | 530.14 | — | — | 2648.56 (5.00x) | 1457.85 (2.75x) |
| Any DoubleValue Infinity WKT JSON stringify | 172.97 | — | — | 1556.37 (9.00x) | 740.96 (4.28x) |
| Any DoubleValue Infinity WKT JSON parse | 531.36 | — | — | 2687.65 (5.06x) | 1451.08 (2.73x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 173.56 | — | — | 1555.36 (8.96x) | 737.80 (4.25x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 535.26 | — | — | 2676.86 (5.00x) | 3008.67 (5.62x) |
| Any FloatValue WKT JSON stringify | 202.34 | — | — | 1744.32 (8.62x) | 1542.05 (7.62x) |
| Any FloatValue WKT JSON parse | 535.91 | — | — | 2710.90 (5.06x) | 3215.45 (6.00x) |
| Any ZeroFloatValue WKT JSON stringify | 171.83 | — | — | 929.31 (5.41x) | 2708.27 (15.76x) |
| Any ZeroFloatValue WKT JSON parse | 530.07 | — | — | 2152.77 (4.06x) | 2986.82 (5.63x) |
| Any FloatValue NaN WKT JSON stringify | 167.44 | — | — | 1567.54 (9.36x) | 1431.76 (8.55x) |
| Any FloatValue NaN WKT JSON parse | 530.07 | — | — | 2629.20 (4.96x) | 2329.27 (4.39x) |
| Any FloatValue Infinity WKT JSON stringify | 172.43 | — | — | 1554.61 (9.02x) | 1318.11 (7.64x) |
| Any FloatValue Infinity WKT JSON parse | 532.49 | — | — | 2658.29 (4.99x) | 3117.01 (5.85x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 176.21 | — | — | 1545.69 (8.77x) | 1284.76 (7.29x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 532.05 | — | — | 2647.51 (4.98x) | 2506.60 (4.71x) |
| Any Int64Value WKT JSON stringify | 169.39 | — | — | 1555.56 (9.18x) | 1690.47 (9.98x) |
| Any Int64Value WKT JSON parse | 569.21 | — | — | 2778.61 (4.88x) | 3140.25 (5.52x) |
| Any ZeroInt64Value WKT JSON stringify | 158.95 | — | — | 913.27 (5.75x) | 1512.05 (9.51x) |
| Any ZeroInt64Value WKT JSON parse | 537.53 | — | — | 2147.24 (3.99x) | 2715.75 (5.05x) |
| Any NegativeInt64Value WKT JSON stringify | 167.00 | — | — | 1555.65 (9.32x) | 1677.99 (10.05x) |
| Any NegativeInt64Value WKT JSON parse | 561.91 | — | — | 2810.85 (5.00x) | 3145.83 (5.60x) |
| Any UInt64Value WKT JSON stringify | 182.92 | — | — | 1555.39 (8.50x) | 1646.02 (9.00x) |
| Any UInt64Value WKT JSON parse | 572.19 | — | — | 2792.49 (4.88x) | 3062.80 (5.35x) |
| Any ZeroUInt64Value WKT JSON stringify | 170.26 | — | — | 913.63 (5.37x) | 1502.53 (8.82x) |
| Any ZeroUInt64Value WKT JSON parse | 539.47 | — | — | 2155.88 (4.00x) | 2703.76 (5.01x) |
| Any MaxUInt64Value WKT JSON stringify | 179.99 | — | — | 1560.45 (8.67x) | 1654.96 (9.19x) |
| Any MaxUInt64Value WKT JSON parse | 577.60 | — | — | 2831.60 (4.90x) | 3130.81 (5.42x) |
| Any Int32Value WKT JSON stringify | 177.09 | — | — | 1555.29 (8.78x) | 1381.32 (7.80x) |
| Any Int32Value WKT JSON parse | 545.90 | — | — | 2668.46 (4.89x) | 2709.20 (4.96x) |
| Any ZeroInt32Value WKT JSON stringify | 176.31 | — | — | 936.41 (5.31x) | 1344.61 (7.63x) |
| Any ZeroInt32Value WKT JSON parse | 539.64 | — | — | 2158.94 (4.00x) | 2602.20 (4.82x) |
| Any NegativeInt32Value WKT JSON stringify | 175.84 | — | — | 1561.22 (8.88x) | 1386.83 (7.89x) |
| Any NegativeInt32Value WKT JSON parse | 544.79 | — | — | 2699.92 (4.96x) | 2741.65 (5.03x) |
| Any UInt32Value WKT JSON stringify | 187.54 | — | — | 1560.44 (8.32x) | 1411.73 (7.53x) |
| Any UInt32Value WKT JSON parse | 549.91 | — | — | 2684.74 (4.88x) | 2716.67 (4.94x) |
| Any ZeroUInt32Value WKT JSON stringify | 181.90 | — | — | 916.50 (5.04x) | 1348.34 (7.41x) |
| Any ZeroUInt32Value WKT JSON parse | 544.39 | — | — | 2155.38 (3.96x) | 1436.33 (2.64x) |
| Any MaxUInt32Value WKT JSON stringify | 185.68 | — | — | 1550.05 (8.35x) | 740.81 (3.99x) |
| Any MaxUInt32Value WKT JSON parse | 560.78 | — | — | 2686.27 (4.79x) | 1495.08 (2.67x) |
| Any BoolValue WKT JSON stringify | 170.79 | — | — | 1534.67 (8.99x) | 734.00 (4.30x) |
| Any BoolValue WKT JSON parse | 495.80 | — | — | 2608.28 (5.26x) | 1365.46 (2.75x) |
| Any FalseBoolValue WKT JSON stringify | 175.91 | — | — | 925.44 (5.26x) | 711.11 (4.04x) |
| Any FalseBoolValue WKT JSON parse | 500.49 | — | — | 2152.34 (4.30x) | 1321.81 (2.64x) |
| Any StringValue WKT JSON stringify | 208.45 | — | — | 1570.81 (7.54x) | 855.68 (4.10x) |
| Any StringValue WKT JSON parse | 565.64 | — | — | 2680.76 (4.74x) | 1540.08 (2.72x) |
| Any EmptyStringValue WKT JSON stringify | 199.99 | — | — | 928.79 (4.64x) | 765.05 (3.83x) |
| Any EmptyStringValue WKT JSON parse | 533.94 | — | — | 2165.08 (4.05x) | 1364.09 (2.55x) |
| Any BytesValue WKT JSON stringify | 195.16 | — | — | 1600.28 (8.20x) | 913.28 (4.68x) |
| Any BytesValue WKT JSON parse | 578.34 | — | — | 2692.88 (4.66x) | 1542.49 (2.67x) |
| Any EmptyBytesValue WKT JSON stringify | 181.94 | — | — | 927.13 (5.10x) | 769.79 (4.23x) |
| Any EmptyBytesValue WKT JSON parse | 544.06 | — | — | 2153.35 (3.96x) | 1456.26 (2.68x) |
| Nested Any WKT JSON stringify | 321.77 | — | — | 2474.22 (7.69x) | 1452.10 (4.51x) |
| Nested Any WKT JSON parse | 883.11 | — | — | 4286.10 (4.85x) | 2891.53 (3.27x) |
| Duration JSON stringify | 57.89 | — | — | 955.52 (16.51x) | 364.79 (6.30x) |
| Duration JSON parse | 9.02 | — | — | 1459.82 (161.84x) | 393.45 (43.62x) |
| NegativeDuration JSON stringify | 58.27 | — | — | 1005.68 (17.26x) | 439.41 (7.54x) |
| NegativeDuration JSON parse | 8.32 | — | — | 1509.35 (181.41x) | 386.55 (46.46x) |
| FractionalNegativeDuration JSON stringify | 58.39 | — | — | 962.84 (16.49x) | 437.67 (7.50x) |
| FractionalNegativeDuration JSON parse | 8.06 | — | — | 1473.42 (182.81x) | 374.91 (46.51x) |
| MaxDuration JSON stringify | 50.43 | — | — | 851.73 (16.89x) | 420.18 (8.33x) |
| MaxDuration JSON parse | 22.15 | — | — | 1455.82 (65.73x) | 402.48 (18.17x) |
| MinDuration JSON stringify | 49.99 | — | — | 887.22 (17.75x) | 455.07 (9.10x) |
| MinDuration JSON parse | 22.46 | — | — | 1458.83 (64.95x) | 403.44 (17.96x) |
| ZeroDuration JSON stringify | 44.87 | — | — | 822.26 (18.33x) | 351.59 (7.84x) |
| ZeroDuration JSON parse | 5.57 | — | — | 1375.45 (246.94x) | 302.30 (54.27x) |
| FieldMask JSON stringify | 65.68 | — | — | 892.20 (13.58x) | 661.02 (10.06x) |
| FieldMask JSON parse | 154.02 | — | — | 1654.83 (10.74x) | 893.02 (5.80x) |
| Timestamp JSON stringify | 96.75 | — | — | 1146.51 (11.85x) | 413.75 (4.28x) |
| Timestamp JSON parse | 41.31 | — | — | 1503.69 (36.40x) | 433.61 (10.50x) |
| PreEpoch Timestamp JSON stringify | 66.95 | — | — | 1074.90 (16.06x) | 397.76 (5.94x) |
| PreEpoch Timestamp JSON parse | 40.09 | — | — | 1475.97 (36.82x) | 425.36 (10.61x) |
| Max Timestamp JSON stringify | 79.66 | — | — | 1215.70 (15.26x) | 423.46 (5.32x) |
| Max Timestamp JSON parse | 46.70 | — | — | 1550.13 (33.19x) | 461.00 (9.87x) |
| Min Timestamp JSON stringify | 80.08 | — | — | 1063.49 (13.28x) | 400.78 (5.00x) |
| Min Timestamp JSON parse | 37.91 | — | — | 1461.41 (38.55x) | 426.30 (11.25x) |
| Empty JSON stringify | 20.83 | — | — | 516.43 (24.79x) | 78.07 (3.75x) |
| Empty JSON parse | 67.52 | — | — | 729.58 (10.81x) | 202.45 (3.00x) |
| Struct JSON stringify | 177.23 | — | — | 5803.23 (32.74x) | 3037.16 (17.14x) |
| Struct JSON parse | 860.79 | — | — | 10878.60 (12.64x) | 4646.26 (5.40x) |
| Value JSON stringify | 184.21 | — | — | 6641.97 (36.06x) | 3216.69 (17.46x) |
| Value JSON parse | 871.58 | — | — | 12266.60 (14.07x) | 4906.89 (5.63x) |
| ListValue JSON stringify | 138.61 | — | — | 4764.71 (34.37x) | 2115.21 (15.26x) |
| ListValue JSON parse | 670.48 | — | — | 8680.92 (12.95x) | 3813.83 (5.69x) |
| DoubleValue JSON stringify | 67.92 | — | — | 859.46 (12.65x) | 196.79 (2.90x) |
| DoubleValue JSON parse | 110.77 | — | — | 1260.22 (11.38x) | 285.99 (2.58x) |
| ZeroDoubleValue JSON stringify | 47.59 | — | — | 804.41 (16.90x) | 156.04 (3.28x) |
| ZeroDoubleValue JSON parse | 107.85 | — | — | 1155.91 (10.72x) | 273.31 (2.53x) |
| DoubleValue NaN JSON stringify | 46.89 | — | — | 660.17 (14.08x) | 124.14 (2.65x) |
| DoubleValue NaN JSON parse | 104.61 | — | — | 1088.71 (10.41x) | 280.52 (2.68x) |
| DoubleValue Infinity JSON stringify | 48.95 | — | — | 661.67 (13.52x) | 127.17 (2.60x) |
| DoubleValue Infinity JSON parse | 106.28 | — | — | 1100.39 (10.35x) | 288.96 (2.72x) |
| DoubleValue NegativeInfinity JSON stringify | 48.63 | — | — | 657.78 (13.53x) | 122.65 (2.52x) |
| DoubleValue NegativeInfinity JSON parse | 108.11 | — | — | 1122.43 (10.38x) | 288.84 (2.67x) |
| FloatValue JSON stringify | 72.57 | — | — | 793.21 (10.93x) | 535.55 (7.38x) |
| FloatValue JSON parse | 111.58 | — | — | 1215.55 (10.89x) | 1126.64 (10.10x) |
| ZeroFloatValue JSON stringify | 47.37 | — | — | 744.77 (15.72x) | 579.05 (12.22x) |
| ZeroFloatValue JSON parse | 108.20 | — | — | 1159.00 (10.71x) | 1081.12 (9.99x) |
| FloatValue NaN JSON stringify | 46.63 | — | — | 638.28 (13.69x) | 256.94 (5.51x) |
| FloatValue NaN JSON parse | 104.97 | — | — | 1082.83 (10.32x) | 308.59 (2.94x) |
| FloatValue Infinity JSON stringify | 48.16 | — | — | 638.86 (13.27x) | 260.65 (5.41x) |
| FloatValue Infinity JSON parse | 107.19 | — | — | 1102.41 (10.28x) | 385.81 (3.60x) |
| FloatValue NegativeInfinity JSON stringify | 48.55 | — | — | 635.61 (13.09x) | 225.75 (4.65x) |
| FloatValue NegativeInfinity JSON parse | 108.57 | — | — | 1112.33 (10.25x) | 538.17 (4.96x) |
| Int64Value JSON stringify | 50.40 | — | — | 675.27 (13.40x) | 528.25 (10.48x) |
| Int64Value JSON parse | 126.55 | — | — | 1238.48 (9.79x) | 887.76 (7.02x) |
| ZeroInt64Value JSON stringify | 41.64 | — | — | 611.18 (14.68x) | 352.72 (8.47x) |
| ZeroInt64Value JSON parse | 105.82 | — | — | 1105.16 (10.44x) | 654.19 (6.18x) |
| NegativeInt64Value JSON stringify | 48.86 | — | — | 675.54 (13.83x) | 527.70 (10.80x) |
| NegativeInt64Value JSON parse | 128.00 | — | — | 1226.11 (9.58x) | 912.02 (7.13x) |
| UInt64Value JSON stringify | 50.25 | — | — | 673.64 (13.41x) | 519.78 (10.34x) |
| UInt64Value JSON parse | 124.46 | — | — | 1215.22 (9.76x) | 853.59 (6.86x) |
| ZeroUInt64Value JSON stringify | 41.65 | — | — | 607.92 (14.60x) | 362.41 (8.70x) |
| ZeroUInt64Value JSON parse | 103.69 | — | — | 1095.42 (10.56x) | 647.43 (6.24x) |
| MaxUInt64Value JSON stringify | 49.65 | — | — | 676.28 (13.62x) | 548.31 (11.04x) |
| MaxUInt64Value JSON parse | 135.65 | — | — | 1251.94 (9.23x) | 897.96 (6.62x) |
| Int32Value JSON stringify | 46.27 | — | — | 635.94 (13.74x) | 263.92 (5.70x) |
| Int32Value JSON parse | 129.37 | — | — | 1201.17 (9.28x) | 609.98 (4.72x) |
| ZeroInt32Value JSON stringify | 46.19 | — | — | 612.47 (13.26x) | 241.04 (5.22x) |
| ZeroInt32Value JSON parse | 125.08 | — | — | 1151.27 (9.20x) | 533.61 (4.27x) |
| NegativeInt32Value JSON stringify | 46.31 | — | — | 647.76 (13.99x) | 258.08 (5.57x) |
| NegativeInt32Value JSON parse | 128.50 | — | — | 1199.78 (9.34x) | 630.91 (4.91x) |
| UInt32Value JSON stringify | 46.16 | — | — | 632.95 (13.71x) | 279.67 (6.06x) |
| UInt32Value JSON parse | 129.81 | — | — | 1192.92 (9.19x) | 602.43 (4.64x) |
| ZeroUInt32Value JSON stringify | 46.17 | — | — | 620.35 (13.44x) | 239.58 (5.19x) |
| ZeroUInt32Value JSON parse | 125.03 | — | — | 1162.91 (9.30x) | 517.97 (4.14x) |
| MaxUInt32Value JSON stringify | 47.04 | — | — | 633.59 (13.47x) | 132.40 (2.81x) |
| MaxUInt32Value JSON parse | 134.76 | — | — | 1219.95 (9.05x) | 345.79 (2.57x) |
| BoolValue JSON stringify | 44.68 | — | — | 612.64 (13.71x) | 122.25 (2.74x) |
| BoolValue JSON parse | 59.39 | — | — | 1067.70 (17.98x) | 222.12 (3.74x) |
| FalseBoolValue JSON stringify | 44.80 | — | — | 601.23 (13.42x) | 131.70 (2.94x) |
| FalseBoolValue JSON parse | 60.13 | — | — | 1064.96 (17.71x) | 214.09 (3.56x) |
| StringValue JSON stringify | 52.14 | — | — | 657.40 (12.61x) | 186.02 (3.57x) |
| StringValue JSON parse | 136.94 | — | — | 1146.03 (8.37x) | 321.67 (2.35x) |
| EmptyStringValue JSON stringify | 48.95 | — | — | 621.89 (12.70x) | 181.76 (3.71x) |
| EmptyStringValue JSON parse | 81.19 | — | — | 1115.77 (13.74x) | 243.32 (3.00x) |
| BytesValue JSON stringify | 49.74 | — | — | 657.55 (13.22x) | 208.30 (4.19x) |
| BytesValue JSON parse | 146.84 | — | — | 1172.39 (7.98x) | 350.48 (2.39x) |
| EmptyBytesValue JSON stringify | 41.39 | — | — | 634.46 (15.33x) | 197.24 (4.77x) |
| EmptyBytesValue JSON parse | 90.11 | — | — | 1132.24 (12.57x) | 304.19 (3.38x) |
| TextFormat parse | 673.65 | — | — | 4978.66 (7.39x) | 6601.01 (9.80x) |
| packed bool encode | 2.01 | 1330.15 (661.77x) | 521.15 (259.28x) | 17.07 (8.49x) | 2395.56 (1191.82x) |
| packed bool decode | 262.83 | 1568.16 (5.97x) | 2554.86 (9.72x) | 809.88 (3.08x) | 1558.86 (5.93x) |
| shuffled large map deterministic binary encode | 28025.14 | — | — | 94262.40 (3.36x) | 442192.38 (15.78x) |
| large map decode | 25039.52 | 90577.28 (3.62x) | 90064.20 (3.60x) | 87471.90 (3.49x) | 270943.05 (10.82x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded zero/positive/integer-negative/fractional-negative/min-max-bound `Duration`, `Struct`, `Value`,
`FieldMask`, min/pre/post/max-bound `Timestamp`, `Empty`, zero/positive/negative `Int64Value`, zero/finite `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), zero/finite `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), zero/normal/max `UInt64Value`, zero/positive/negative `Int32Value`, zero/normal/max `UInt32Value`, true/false `BoolValue`, non-empty/empty `StringValue`, base64/empty `BytesValue`, and recursive nested `Any` payloads), direct zero/positive/integer-negative/fractional-negative/min-max-bound Duration and min/pre/post/max-bound Timestamp WKT JSON plus other direct WKT JSON, TextFormat, packed scalars, large bytes,
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
