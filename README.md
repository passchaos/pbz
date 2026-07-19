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

Latest accepted comparison (`/tmp/pbz-compare-plus-duration-json-isolated.log`,
summarized in `/tmp/pbz-summary-plus-duration-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 24.31 | 128.99 (5.31x) | 66.19 (2.72x) | 128.68 (5.29x) | 942.38 (38.77x) |
| binary decode | 125.61 | 301.82 (2.40x) | 297.19 (2.37x) | 267.84 (2.13x) | 1029.45 (8.20x) |
| unknown fields count by number | 5.02 | — | — | 212.80 (42.39x) | — |
| deterministic binary encode | 66.65 | — | — | 152.86 (2.29x) | 1221.30 (18.32x) |
| scalarmix encode | 26.74 | 113.66 (4.25x) | 69.42 (2.60x) | 45.75 (1.71x) | 239.11 (8.94x) |
| scalarmix decode | 55.87 | 161.24 (2.89x) | 217.27 (3.89x) | 112.29 (2.01x) | 370.09 (6.62x) |
| textbytes encode | 11.78 | 92.56 (7.86x) | 43.22 (3.67x) | 146.81 (12.46x) | 170.94 (14.51x) |
| textbytes decode | 58.60 | 471.06 (8.04x) | 314.55 (5.37x) | 202.33 (3.45x) | 827.20 (14.12x) |
| largebytes encode | 25.81 | 3899.23 (151.07x) | 3826.61 (148.26x) | 3876.96 (150.21x) | 4136.16 (160.25x) |
| largebytes decode | 124.61 | 8438.56 (67.72x) | 4590.24 (36.84x) | 6765.29 (54.29x) | 24344.18 (195.36x) |
| presencemix encode | 23.05 | 64.57 (2.80x) | 38.34 (1.66x) | 69.53 (3.02x) | 258.67 (11.22x) |
| presencemix decode | 66.82 | 161.67 (2.42x) | 141.17 (2.11x) | 197.56 (2.96x) | 560.51 (8.39x) |
| complex encode | 65.23 | 163.26 (2.50x) | 114.39 (1.75x) | 208.75 (3.20x) | 954.29 (14.63x) |
| complex decode | 214.28 | 462.94 (2.16x) | 436.02 (2.03x) | 499.62 (2.33x) | 1660.44 (7.75x) |
| complex deterministic binary encode | 124.00 | — | — | 213.15 (1.72x) | 1332.20 (10.74x) |
| complex JSON stringify | 356.32 | — | — | 7174.54 (20.14x) | 7481.39 (21.00x) |
| complex JSON parse | 2739.51 | — | — | 16715.90 (6.10x) | 10268.59 (3.75x) |
| complex TextFormat format | 339.87 | — | — | 4901.68 (14.42x) | 6671.77 (19.63x) |
| complex TextFormat parse | 2288.76 | — | — | 7838.94 (3.42x) | 11389.45 (4.98x) |
| packed int32 encode | 894.76 | 5395.46 (6.03x) | 3023.75 (3.38x) | 2205.85 (2.47x) | 5699.12 (6.37x) |
| packed int32 decode | 994.94 | 2974.99 (2.99x) | 4288.79 (4.31x) | 1447.95 (1.46x) | 4379.91 (4.40x) |
| JSON stringify | 198.63 | — | — | 4979.14 (25.07x) | 2907.10 (14.64x) |
| JSON parse | 1689.04 | — | — | 10523.60 (6.23x) | 5675.84 (3.36x) |
| Any WKT JSON stringify | 173.73 | — | — | 3056.52 (17.59x) | 1329.27 (7.65x) |
| Any WKT JSON parse | 578.20 | — | — | 4725.53 (8.17x) | 2098.32 (3.63x) |
| Any PlusDuration WKT JSON parse | 579.64 | — | — | 4775.44 (8.24x) | 2105.16 (3.63x) |
| Any MicroDuration WKT JSON stringify | 177.06 | — | — | 3168.26 (17.89x) | 1349.38 (7.62x) |
| Any MicroDuration WKT JSON parse | 582.71 | — | — | 4756.07 (8.16x) | 2151.47 (3.69x) |
| Any NanoDuration WKT JSON stringify | 173.49 | — | — | 3181.74 (18.34x) | 1396.74 (8.05x) |
| Any NanoDuration WKT JSON parse | 593.84 | — | — | 4645.54 (7.82x) | 2164.77 (3.65x) |
| Any NegativeDuration WKT JSON stringify | 184.40 | — | — | 3136.56 (17.01x) | 1455.78 (7.89x) |
| Any NegativeDuration WKT JSON parse | 582.84 | — | — | 4777.50 (8.20x) | 2195.98 (3.77x) |
| Any FractionalNegativeDuration WKT JSON stringify | 171.61 | — | — | 3063.01 (17.85x) | 1386.99 (8.08x) |
| Any FractionalNegativeDuration WKT JSON parse | 576.63 | — | — | 4758.93 (8.25x) | 2118.56 (3.67x) |
| Any MaxDuration WKT JSON stringify | 156.12 | — | — | 2815.62 (18.03x) | 1315.89 (8.43x) |
| Any MaxDuration WKT JSON parse | 602.67 | — | — | 4600.76 (7.63x) | 2155.89 (3.58x) |
| Any MinDuration WKT JSON stringify | 159.38 | — | — | 2756.57 (17.30x) | 1401.04 (8.79x) |
| Any MinDuration WKT JSON parse | 604.09 | — | — | 4623.57 (7.65x) | 2125.21 (3.52x) |
| Any ZeroDuration WKT JSON stringify | 141.35 | — | — | 1365.35 (9.66x) | 1245.20 (8.81x) |
| Any ZeroDuration WKT JSON parse | 529.87 | — | — | 3370.52 (6.36x) | 1946.20 (3.67x) |
| Any FieldMask WKT JSON stringify | 272.56 | — | — | 2491.23 (9.14x) | 1803.66 (6.62x) |
| Any FieldMask WKT JSON parse | 801.64 | — | — | 4842.84 (6.04x) | 2934.82 (3.66x) |
| Any EmptyFieldMask WKT JSON stringify | 140.75 | — | — | 1331.39 (9.46x) | 882.97 (6.27x) |
| Any EmptyFieldMask WKT JSON parse | 500.70 | — | — | 3189.76 (6.37x) | 1649.56 (3.29x) |
| Any Timestamp WKT JSON stringify | 239.91 | — | — | 2984.33 (12.44x) | 1349.85 (5.63x) |
| Any Timestamp WKT JSON parse | 648.16 | — | — | 4689.18 (7.23x) | 2264.71 (3.49x) |
| Any Micro Timestamp WKT JSON stringify | 240.22 | — | — | 3002.05 (12.50x) | 1338.59 (5.57x) |
| Any Micro Timestamp WKT JSON parse | 654.07 | — | — | 4727.88 (7.23x) | 2268.96 (3.47x) |
| Any Nano Timestamp WKT JSON stringify | 243.30 | — | — | 3025.02 (12.43x) | 1341.20 (5.51x) |
| Any Nano Timestamp WKT JSON parse | 661.60 | — | — | 4665.80 (7.05x) | 2342.81 (3.54x) |
| Any Offset Timestamp WKT JSON parse | 668.63 | — | — | 4758.16 (7.12x) | 2377.76 (3.56x) |
| Any PreEpoch Timestamp WKT JSON stringify | 195.22 | — | — | 2927.14 (14.99x) | 1296.41 (6.64x) |
| Any PreEpoch Timestamp WKT JSON parse | 630.18 | — | — | 4698.93 (7.46x) | 2225.74 (3.53x) |
| Any Max Timestamp WKT JSON stringify | 217.55 | — | — | 3043.14 (13.99x) | 1340.15 (6.16x) |
| Any Max Timestamp WKT JSON parse | 664.74 | — | — | 4742.72 (7.13x) | 2327.90 (3.50x) |
| Any Min Timestamp WKT JSON stringify | 226.23 | — | — | 2899.13 (12.81x) | 1281.22 (5.66x) |
| Any Min Timestamp WKT JSON parse | 631.06 | — | — | 4670.25 (7.40x) | 2216.03 (3.51x) |
| Any Empty WKT JSON stringify | 114.76 | — | — | 1377.02 (12.00x) | 700.96 (6.11x) |
| Any Empty WKT JSON parse | 381.25 | — | — | 3136.95 (8.23x) | 1595.34 (4.18x) |
| Any Struct WKT JSON stringify | 767.79 | — | — | 9027.20 (11.76x) | 8635.70 (11.25x) |
| Any Struct WKT JSON parse | 1982.23 | — | — | 17275.40 (8.72x) | 12623.28 (6.37x) |
| Any EmptyStruct WKT JSON stringify | 144.55 | — | — | 1328.41 (9.19x) | 1245.21 (8.61x) |
| Any EmptyStruct WKT JSON parse | 507.32 | — | — | 3252.88 (6.41x) | 2236.19 (4.41x) |
| Any Value WKT JSON stringify | 784.78 | — | — | 9084.89 (11.58x) | 8920.41 (11.37x) |
| Any Value WKT JSON parse | 2050.28 | — | — | 17326.90 (8.45x) | 12986.72 (6.33x) |
| Any NullValue WKT JSON stringify | 154.67 | — | — | 3211.37 (20.76x) | 1256.92 (8.13x) |
| Any NullValue WKT JSON parse | 525.56 | — | — | 6238.53 (11.87x) | 2220.38 (4.22x) |
| Any StringScalarValue WKT JSON stringify | 184.23 | — | — | 3218.13 (17.47x) | 1381.17 (7.50x) |
| Any StringScalarValue WKT JSON parse | 578.64 | — | — | 5387.59 (9.31x) | 2303.27 (3.98x) |
| Any EmptyStringScalarValue WKT JSON stringify | 164.41 | — | — | 3209.08 (19.52x) | 1290.92 (7.85x) |
| Any EmptyStringScalarValue WKT JSON parse | 545.25 | — | — | 5422.40 (9.94x) | 2175.14 (3.99x) |
| Any NumberValue WKT JSON stringify | 227.92 | — | — | 3923.59 (17.21x) | 1476.68 (6.48x) |
| Any NumberValue WKT JSON parse | 563.53 | — | — | 5645.39 (10.02x) | 2394.97 (4.25x) |
| Any ZeroNumberValue WKT JSON stringify | 172.02 | — | — | 3782.21 (21.99x) | 1354.14 (7.87x) |
| Any ZeroNumberValue WKT JSON parse | 570.40 | — | — | 5436.59 (9.53x) | 2384.63 (4.18x) |
| Any BoolScalarValue WKT JSON stringify | 153.49 | — | — | 3151.41 (20.53x) | 1248.53 (8.13x) |
| Any BoolScalarValue WKT JSON parse | 524.65 | — | — | 5397.23 (10.29x) | 2163.28 (4.12x) |
| Any FalseBoolScalarValue WKT JSON stringify | 153.52 | — | — | 3137.38 (20.44x) | 1293.00 (8.42x) |
| Any FalseBoolScalarValue WKT JSON parse | 526.31 | — | — | 5360.60 (10.19x) | 2394.41 (4.55x) |
| Any ListKindValue WKT JSON stringify | 595.85 | — | — | 8733.90 (14.66x) | 7044.53 (11.82x) |
| Any ListKindValue WKT JSON parse | 1576.50 | — | — | 15220.60 (9.65x) | 10513.51 (6.67x) |
| Any EmptyStructKindValue WKT JSON stringify | 171.32 | — | — | 4039.69 (23.58x) | 1882.75 (10.99x) |
| Any EmptyStructKindValue WKT JSON parse | 570.57 | — | — | 8106.16 (14.21x) | 3010.95 (5.28x) |
| Any EmptyListKindValue WKT JSON stringify | 169.40 | — | — | 4033.94 (23.81x) | 1548.27 (9.14x) |
| Any EmptyListKindValue WKT JSON parse | 573.34 | — | — | 6497.52 (11.33x) | 2787.95 (4.86x) |
| Any DoubleValue WKT JSON stringify | 240.00 | — | — | 2860.82 (11.92x) | 955.57 (3.98x) |
| Any DoubleValue WKT JSON parse | 579.95 | — | — | 4353.06 (7.51x) | 1998.87 (3.45x) |
| Any NegativeDoubleValue WKT JSON stringify | 240.19 | — | — | 2842.38 (11.83x) | 969.44 (4.04x) |
| Any NegativeDoubleValue WKT JSON parse | 580.95 | — | — | 4415.55 (7.60x) | 2019.58 (3.48x) |
| Any ZeroDoubleValue WKT JSON stringify | 190.71 | — | — | 1318.90 (6.92x) | 848.14 (4.45x) |
| Any ZeroDoubleValue WKT JSON parse | 581.35 | — | — | 3198.39 (5.50x) | 1879.92 (3.23x) |
| Any DoubleValue NaN WKT JSON stringify | 191.41 | — | — | 2329.41 (12.17x) | 822.79 (4.30x) |
| Any DoubleValue NaN WKT JSON parse | 576.33 | — | — | 4133.94 (7.17x) | 1914.60 (3.32x) |
| Any DoubleValue Infinity WKT JSON stringify | 190.09 | — | — | 2282.20 (12.01x) | 825.31 (4.34x) |
| Any DoubleValue Infinity WKT JSON parse | 580.41 | — | — | 4138.31 (7.13x) | 1906.18 (3.28x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 192.08 | — | — | 2305.09 (12.00x) | 843.53 (4.39x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 584.09 | — | — | 4136.30 (7.08x) | 1984.01 (3.40x) |
| Any FloatValue WKT JSON stringify | 245.95 | — | — | 2816.67 (11.45x) | 930.89 (3.78x) |
| Any FloatValue WKT JSON parse | 580.61 | — | — | 4352.75 (7.50x) | 1939.22 (3.34x) |
| Any NegativeFloatValue WKT JSON stringify | 246.61 | — | — | 2797.12 (11.34x) | 938.20 (3.80x) |
| Any NegativeFloatValue WKT JSON parse | 580.18 | — | — | 4366.32 (7.53x) | 1952.09 (3.36x) |
| Any ZeroFloatValue WKT JSON stringify | 191.41 | — | — | 1326.11 (6.93x) | 839.01 (4.38x) |
| Any ZeroFloatValue WKT JSON parse | 581.11 | — | — | 3207.35 (5.52x) | 1862.30 (3.20x) |
| Any FloatValue NaN WKT JSON stringify | 186.30 | — | — | 2277.93 (12.23x) | 819.31 (4.40x) |
| Any FloatValue NaN WKT JSON parse | 578.04 | — | — | 4089.66 (7.08x) | 1835.68 (3.18x) |
| Any FloatValue Infinity WKT JSON stringify | 190.29 | — | — | 2210.40 (11.62x) | 809.84 (4.26x) |
| Any FloatValue Infinity WKT JSON parse | 581.56 | — | — | 4109.67 (7.07x) | 1887.61 (3.25x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 191.38 | — | — | 2236.53 (11.69x) | 822.96 (4.30x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 587.27 | — | — | 4113.78 (7.00x) | 1888.14 (3.22x) |
| Any Int64Value WKT JSON stringify | 193.48 | — | — | 2250.12 (11.63x) | 1169.01 (6.04x) |
| Any Int64Value WKT JSON parse | 628.30 | — | — | 4320.52 (6.88x) | 2254.26 (3.59x) |
| Any ZeroInt64Value WKT JSON stringify | 183.01 | — | — | 1312.49 (7.17x) | 1077.85 (5.89x) |
| Any ZeroInt64Value WKT JSON parse | 584.21 | — | — | 3144.06 (5.38x) | 2091.94 (3.58x) |
| Any NegativeInt64Value WKT JSON stringify | 194.91 | — | — | 2230.74 (11.44x) | 1165.52 (5.98x) |
| Any NegativeInt64Value WKT JSON parse | 625.89 | — | — | 4312.28 (6.89x) | 2356.06 (3.76x) |
| Any MinInt64Value WKT JSON stringify | 198.27 | — | — | 2242.64 (11.31x) | 1167.97 (5.89x) |
| Any MinInt64Value WKT JSON parse | 636.04 | — | — | 4305.48 (6.77x) | 2428.09 (3.82x) |
| Any MaxInt64Value WKT JSON stringify | 197.13 | — | — | 2255.72 (11.44x) | 1232.33 (6.25x) |
| Any MaxInt64Value WKT JSON parse | 637.85 | — | — | 4253.58 (6.67x) | 2429.22 (3.81x) |
| Any UInt64Value WKT JSON stringify | 203.57 | — | — | 2235.11 (10.98x) | 1242.09 (6.10x) |
| Any UInt64Value WKT JSON parse | 635.83 | — | — | 4264.49 (6.71x) | 2306.04 (3.63x) |
| Any ZeroUInt64Value WKT JSON stringify | 192.57 | — | — | 1306.66 (6.79x) | 1019.98 (5.30x) |
| Any ZeroUInt64Value WKT JSON parse | 591.55 | — | — | 3146.20 (5.32x) | 1990.30 (3.36x) |
| Any MaxUInt64Value WKT JSON stringify | 208.13 | — | — | 2179.90 (10.47x) | 1164.24 (5.59x) |
| Any MaxUInt64Value WKT JSON parse | 649.49 | — | — | 4282.84 (6.59x) | 2305.07 (3.55x) |
| Any Int32Value WKT JSON stringify | 198.95 | — | — | 2327.03 (11.70x) | 863.59 (4.34x) |
| Any Int32Value WKT JSON parse | 598.35 | — | — | 4138.50 (6.92x) | 1968.31 (3.29x) |
| Any ZeroInt32Value WKT JSON stringify | 195.87 | — | — | 1322.38 (6.75x) | 814.50 (4.16x) |
| Any ZeroInt32Value WKT JSON parse | 592.76 | — | — | 3230.08 (5.45x) | 1899.08 (3.20x) |
| Any NegativeInt32Value WKT JSON stringify | 202.65 | — | — | 2305.44 (11.38x) | 872.05 (4.30x) |
| Any NegativeInt32Value WKT JSON parse | 598.98 | — | — | 4174.97 (6.97x) | 2041.81 (3.41x) |
| Any MinInt32Value WKT JSON stringify | 203.64 | — | — | 2288.45 (11.24x) | 872.18 (4.28x) |
| Any MinInt32Value WKT JSON parse | 610.88 | — | — | 4251.22 (6.96x) | 2080.75 (3.41x) |
| Any MaxInt32Value WKT JSON stringify | 201.45 | — | — | 2292.64 (11.38x) | 851.60 (4.23x) |
| Any MaxInt32Value WKT JSON parse | 612.63 | — | — | 4150.81 (6.78x) | 1997.21 (3.26x) |
| Any UInt32Value WKT JSON stringify | 207.60 | — | — | 2195.81 (10.58x) | 930.24 (4.48x) |
| Any UInt32Value WKT JSON parse | 605.74 | — | — | 4144.20 (6.84x) | 1976.97 (3.26x) |
| Any ZeroUInt32Value WKT JSON stringify | 206.72 | — | — | 1308.81 (6.33x) | 865.61 (4.19x) |
| Any ZeroUInt32Value WKT JSON parse | 600.28 | — | — | 3186.07 (5.31x) | 1913.11 (3.19x) |
| Any MaxUInt32Value WKT JSON stringify | 210.91 | — | — | 2180.31 (10.34x) | 918.42 (4.35x) |
| Any MaxUInt32Value WKT JSON parse | 619.38 | — | — | 4103.88 (6.63x) | 1995.71 (3.22x) |
| Any BoolValue WKT JSON stringify | 200.73 | — | — | 2189.19 (10.91x) | 819.35 (4.08x) |
| Any BoolValue WKT JSON parse | 551.90 | — | — | 4044.56 (7.33x) | 1744.05 (3.16x) |
| Any FalseBoolValue WKT JSON stringify | 199.81 | — | — | 1342.79 (6.72x) | 806.71 (4.04x) |
| Any FalseBoolValue WKT JSON parse | 553.14 | — | — | 3183.17 (5.75x) | 1654.09 (2.99x) |
| Any StringValue WKT JSON stringify | 230.07 | — | — | 2266.98 (9.85x) | 970.99 (4.22x) |
| Any StringValue WKT JSON parse | 614.19 | — | — | 4147.66 (6.75x) | 1852.80 (3.02x) |
| Any EmptyStringValue WKT JSON stringify | 211.91 | — | — | 1336.15 (6.31x) | 857.63 (4.05x) |
| Any EmptyStringValue WKT JSON parse | 578.12 | — | — | 3167.08 (5.48x) | 1670.46 (2.89x) |
| Any BytesValue WKT JSON stringify | 211.28 | — | — | 2295.96 (10.87x) | 957.97 (4.53x) |
| Any BytesValue WKT JSON parse | 623.04 | — | — | 4212.32 (6.76x) | 1924.98 (3.09x) |
| Any EmptyBytesValue WKT JSON stringify | 204.87 | — | — | 1293.10 (6.31x) | 854.18 (4.17x) |
| Any EmptyBytesValue WKT JSON parse | 583.83 | — | — | 3138.41 (5.38x) | 1804.08 (3.09x) |
| Nested Any WKT JSON stringify | 358.23 | — | — | 3437.87 (9.60x) | 1614.21 (4.51x) |
| Nested Any WKT JSON parse | 1015.21 | — | — | 6057.37 (5.97x) | 3557.56 (3.50x) |
| Duration JSON stringify | 64.82 | — | — | 1543.78 (23.82x) | 414.41 (6.39x) |
| Duration JSON parse | 12.18 | — | — | 2302.20 (189.01x) | 431.36 (35.42x) |
| PlusDuration JSON parse | 12.79 | — | — | 2322.68 (181.60x) | 421.03 (32.92x) |
| MicroDuration JSON stringify | 68.52 | — | — | 1520.15 (22.19x) | 435.98 (6.36x) |
| MicroDuration JSON parse | 15.79 | — | — | 2356.84 (149.26x) | 442.90 (28.05x) |
| NanoDuration JSON stringify | 63.52 | — | — | 1590.28 (25.04x) | 415.43 (6.54x) |
| NanoDuration JSON parse | 22.04 | — | — | 2338.46 (106.10x) | 445.23 (20.20x) |
| NegativeDuration JSON stringify | 65.27 | — | — | 1602.96 (24.56x) | 470.20 (7.20x) |
| NegativeDuration JSON parse | 12.54 | — | — | 2395.28 (191.01x) | 449.56 (35.85x) |
| FractionalNegativeDuration JSON stringify | 65.07 | — | — | 1560.41 (23.98x) | 442.43 (6.80x) |
| FractionalNegativeDuration JSON parse | 12.54 | — | — | 2314.92 (184.60x) | 432.99 (34.53x) |
| MaxDuration JSON stringify | 54.29 | — | — | 1257.26 (23.16x) | 448.18 (8.26x) |
| MaxDuration JSON parse | 29.20 | — | — | 2224.58 (76.18x) | 450.06 (15.41x) |
| MinDuration JSON stringify | 54.71 | — | — | 1297.72 (23.72x) | 458.71 (8.38x) |
| MinDuration JSON parse | 29.39 | — | — | 2230.75 (75.90x) | 447.23 (15.22x) |
| ZeroDuration JSON stringify | 47.65 | — | — | 1294.43 (27.17x) | 372.82 (7.82x) |
| ZeroDuration JSON parse | 8.79 | — | — | 2153.56 (245.00x) | 347.57 (39.54x) |
| FieldMask JSON stringify | 93.99 | — | — | 1296.90 (13.80x) | 761.06 (8.10x) |
| FieldMask JSON parse | 180.51 | — | — | 2614.18 (14.48x) | 1036.95 (5.74x) |
| EmptyFieldMask JSON stringify | 43.14 | — | — | 944.78 (21.90x) | 241.41 (5.60x) |
| EmptyFieldMask JSON parse | 3.52 | — | — | 1433.18 (407.15x) | 212.84 (60.47x) |
| Timestamp JSON stringify | 128.83 | — | — | 1708.79 (13.26x) | 470.43 (3.65x) |
| Timestamp JSON parse | 56.74 | — | — | 2289.88 (40.36x) | 485.93 (8.56x) |
| Micro Timestamp JSON stringify | 132.00 | — | — | 1722.64 (13.05x) | 472.89 (3.58x) |
| Micro Timestamp JSON parse | 59.45 | — | — | 2328.65 (39.17x) | 482.33 (8.11x) |
| Nano Timestamp JSON stringify | 132.11 | — | — | 1761.79 (13.34x) | 471.86 (3.57x) |
| Nano Timestamp JSON parse | 62.74 | — | — | 2334.27 (37.21x) | 490.05 (7.81x) |
| Offset Timestamp JSON parse | 72.15 | — | — | 2348.02 (32.54x) | 519.21 (7.20x) |
| PreEpoch Timestamp JSON stringify | 88.18 | — | — | 1598.67 (18.13x) | 458.47 (5.20x) |
| PreEpoch Timestamp JSON parse | 54.72 | — | — | 2267.09 (41.43x) | 454.88 (8.31x) |
| Max Timestamp JSON stringify | 105.47 | — | — | 1764.18 (16.73x) | 469.50 (4.45x) |
| Max Timestamp JSON parse | 64.26 | — | — | 2312.28 (35.98x) | 488.06 (7.60x) |
| Min Timestamp JSON stringify | 118.45 | — | — | 1599.79 (13.51x) | 460.82 (3.89x) |
| Min Timestamp JSON parse | 52.63 | — | — | 2288.47 (43.48x) | 455.32 (8.65x) |
| Empty JSON stringify | 22.71 | — | — | 708.83 (31.21x) | 105.31 (4.64x) |
| Empty JSON parse | 73.02 | — | — | 1118.61 (15.32x) | 279.82 (3.83x) |
| Struct JSON stringify | 268.65 | — | — | 8872.10 (33.02x) | 3870.39 (14.41x) |
| Struct JSON parse | 943.32 | — | — | 16885.30 (17.90x) | 6282.47 (6.66x) |
| EmptyStruct JSON stringify | 43.62 | — | — | 999.71 (22.92x) | 399.83 (9.17x) |
| EmptyStruct JSON parse | 94.81 | — | — | 3365.55 (35.50x) | 422.67 (4.46x) |
| Value JSON stringify | 270.24 | — | — | 9977.69 (36.92x) | 4027.16 (14.90x) |
| Value JSON parse | 976.78 | — | — | 18035.20 (18.46x) | 6532.43 (6.69x) |
| NullValue JSON stringify | 43.14 | — | — | 1793.41 (41.57x) | 241.54 (5.60x) |
| NullValue JSON parse | 65.68 | — | — | 3808.12 (57.98x) | 376.22 (5.73x) |
| StringScalarValue JSON stringify | 55.02 | — | — | 1848.72 (33.60x) | 280.27 (5.09x) |
| StringScalarValue JSON parse | 125.89 | — | — | 3108.41 (24.69x) | 487.28 (3.87x) |
| EmptyStringScalarValue JSON stringify | 51.48 | — | — | 1855.89 (36.05x) | 277.89 (5.40x) |
| EmptyStringScalarValue JSON parse | 71.93 | — | — | 3052.69 (42.44x) | 404.21 (5.62x) |
| NumberValue JSON stringify | 113.20 | — | — | 2341.20 (20.68x) | 355.73 (3.14x) |
| NumberValue JSON parse | 122.26 | — | — | 3310.14 (27.07x) | 449.99 (3.68x) |
| ZeroNumberValue JSON stringify | 64.68 | — | — | 2270.76 (35.11x) | 304.84 (4.71x) |
| ZeroNumberValue JSON parse | 124.40 | — | — | 3137.02 (25.22x) | 416.77 (3.35x) |
| BoolScalarValue JSON stringify | 43.04 | — | — | 1789.29 (41.57x) | 238.36 (5.54x) |
| BoolScalarValue JSON parse | 61.71 | — | — | 2929.27 (47.47x) | 358.70 (5.81x) |
| FalseBoolScalarValue JSON stringify | 43.05 | — | — | 1763.65 (40.97x) | 226.29 (5.26x) |
| FalseBoolScalarValue JSON parse | 62.91 | — | — | 2990.88 (47.54x) | 365.19 (5.80x) |
| ListKindValue JSON stringify | 203.75 | — | — | 9197.57 (45.14x) | 2860.02 (14.04x) |
| ListKindValue JSON parse | 767.70 | — | — | 16110.00 (20.98x) | 5556.87 (7.24x) |
| EmptyStructKindValue JSON stringify | 45.62 | — | — | 2764.47 (60.60x) | 632.93 (13.87x) |
| EmptyStructKindValue JSON parse | 109.49 | — | — | 5878.30 (53.69x) | 843.14 (7.70x) |
| EmptyListKindValue JSON stringify | 44.02 | — | — | 2764.79 (62.81x) | 379.35 (8.62x) |
| EmptyListKindValue JSON parse | 151.10 | — | — | 5698.15 (37.71x) | 681.95 (4.51x) |
| ListValue JSON stringify | 199.01 | — | — | 7681.94 (38.60x) | 2698.68 (13.56x) |
| ListValue JSON parse | 738.23 | — | — | 13704.70 (18.56x) | 5240.80 (7.10x) |
| EmptyListValue JSON stringify | 41.03 | — | — | 1007.66 (24.56x) | 231.11 (5.63x) |
| EmptyListValue JSON parse | 134.20 | — | — | 3234.25 (24.10x) | 382.19 (2.85x) |
| DoubleValue JSON stringify | 107.26 | — | — | 1475.83 (13.76x) | 208.81 (1.95x) |
| DoubleValue JSON parse | 113.65 | — | — | 2121.01 (18.66x) | 328.86 (2.89x) |
| NegativeDoubleValue JSON stringify | 107.27 | — | — | 1489.87 (13.89x) | 211.85 (1.97x) |
| NegativeDoubleValue JSON parse | 113.61 | — | — | 2113.65 (18.60x) | 315.64 (2.78x) |
| ZeroDoubleValue JSON stringify | 54.04 | — | — | 1378.87 (25.52x) | 177.74 (3.29x) |
| ZeroDoubleValue JSON parse | 115.34 | — | — | 1868.33 (16.20x) | 314.40 (2.73x) |
| DoubleValue NaN JSON stringify | 52.72 | — | — | 992.78 (18.83x) | 145.56 (2.76x) |
| DoubleValue NaN JSON parse | 102.05 | — | — | 1721.52 (16.87x) | 307.43 (3.01x) |
| DoubleValue Infinity JSON stringify | 55.91 | — | — | 975.34 (17.44x) | 148.50 (2.66x) |
| DoubleValue Infinity JSON parse | 105.08 | — | — | 1740.64 (16.56x) | 310.28 (2.95x) |
| DoubleValue NegativeInfinity JSON stringify | 57.56 | — | — | 980.58 (17.04x) | 166.41 (2.89x) |
| DoubleValue NegativeInfinity JSON parse | 109.12 | — | — | 1740.81 (15.95x) | 319.84 (2.93x) |
| FloatValue JSON stringify | 102.42 | — | — | 1397.71 (13.65x) | 203.78 (1.99x) |
| FloatValue JSON parse | 113.38 | — | — | 2100.15 (18.52x) | 313.51 (2.77x) |
| NegativeFloatValue JSON stringify | 101.92 | — | — | 1421.94 (13.95x) | 216.43 (2.12x) |
| NegativeFloatValue JSON parse | 113.93 | — | — | 2121.70 (18.62x) | 338.59 (2.97x) |
| ZeroFloatValue JSON stringify | 54.42 | — | — | 1354.53 (24.89x) | 174.27 (3.20x) |
| ZeroFloatValue JSON parse | 115.91 | — | — | 1855.92 (16.01x) | 290.31 (2.50x) |
| FloatValue NaN JSON stringify | 52.74 | — | — | 985.05 (18.68x) | 156.69 (2.97x) |
| FloatValue NaN JSON parse | 102.84 | — | — | 1693.88 (16.47x) | 298.94 (2.91x) |
| FloatValue Infinity JSON stringify | 56.05 | — | — | 967.26 (17.26x) | 161.21 (2.88x) |
| FloatValue Infinity JSON parse | 105.93 | — | — | 1726.20 (16.30x) | 300.33 (2.84x) |
| FloatValue NegativeInfinity JSON stringify | 57.75 | — | — | 967.78 (16.76x) | 218.21 (3.78x) |
| FloatValue NegativeInfinity JSON parse | 108.73 | — | — | 1731.42 (15.92x) | 329.43 (3.03x) |
| Int64Value JSON stringify | 54.62 | — | — | 1023.15 (18.73x) | 312.75 (5.73x) |
| Int64Value JSON parse | 148.28 | — | — | 1995.95 (13.46x) | 513.05 (3.46x) |
| ZeroInt64Value JSON stringify | 43.87 | — | — | 937.45 (21.37x) | 217.38 (4.96x) |
| ZeroInt64Value JSON parse | 104.83 | — | — | 1809.49 (17.26x) | 375.78 (3.58x) |
| NegativeInt64Value JSON stringify | 54.50 | — | — | 1009.78 (18.53x) | 313.74 (5.76x) |
| NegativeInt64Value JSON parse | 149.44 | — | — | 1931.00 (12.92x) | 527.09 (3.53x) |
| MinInt64Value JSON stringify | 58.70 | — | — | 1005.60 (17.13x) | 326.11 (5.56x) |
| MinInt64Value JSON parse | 158.89 | — | — | 1989.75 (12.52x) | 535.62 (3.37x) |
| MaxInt64Value JSON stringify | 58.51 | — | — | 991.72 (16.95x) | 330.92 (5.66x) |
| MaxInt64Value JSON parse | 157.93 | — | — | 1978.36 (12.53x) | 544.20 (3.45x) |
| UInt64Value JSON stringify | 53.82 | — | — | 1018.34 (18.92x) | 329.72 (6.13x) |
| UInt64Value JSON parse | 156.18 | — | — | 1966.19 (12.59x) | 541.42 (3.47x) |
| ZeroUInt64Value JSON stringify | 43.21 | — | — | 916.08 (21.20x) | 227.16 (5.26x) |
| ZeroUInt64Value JSON parse | 109.94 | — | — | 1833.15 (16.67x) | 368.64 (3.35x) |
| MaxUInt64Value JSON stringify | 57.78 | — | — | 1002.88 (17.36x) | 331.85 (5.74x) |
| MaxUInt64Value JSON parse | 169.41 | — | — | 2017.10 (11.91x) | 526.65 (3.11x) |
| Int32Value JSON stringify | 48.78 | — | — | 979.25 (20.07x) | 166.45 (3.41x) |
| Int32Value JSON parse | 129.39 | — | — | 1889.87 (14.61x) | 336.95 (2.60x) |
| ZeroInt32Value JSON stringify | 48.53 | — | — | 977.72 (20.15x) | 158.10 (3.26x) |
| ZeroInt32Value JSON parse | 122.91 | — | — | 1876.80 (15.27x) | 299.53 (2.44x) |
| NegativeInt32Value JSON stringify | 48.22 | — | — | 1015.59 (21.06x) | 166.33 (3.45x) |
| NegativeInt32Value JSON parse | 126.79 | — | — | 1891.45 (14.92x) | 348.95 (2.75x) |
| MinInt32Value JSON stringify | 48.87 | — | — | 995.99 (20.38x) | 163.84 (3.35x) |
| MinInt32Value JSON parse | 138.22 | — | — | 1943.86 (14.06x) | 375.30 (2.72x) |
| MaxInt32Value JSON stringify | 48.51 | — | — | 1002.58 (20.67x) | 181.04 (3.73x) |
| MaxInt32Value JSON parse | 139.86 | — | — | 1944.39 (13.90x) | 365.36 (2.61x) |
| UInt32Value JSON stringify | 48.80 | — | — | 911.00 (18.67x) | 187.30 (3.84x) |
| UInt32Value JSON parse | 128.98 | — | — | 1909.84 (14.81x) | 357.95 (2.78x) |
| ZeroUInt32Value JSON stringify | 48.70 | — | — | 938.75 (19.28x) | 169.47 (3.48x) |
| ZeroUInt32Value JSON parse | 122.91 | — | — | 1863.45 (15.16x) | 324.79 (2.64x) |
| MaxUInt32Value JSON stringify | 48.47 | — | — | 941.53 (19.43x) | 179.98 (3.71x) |
| MaxUInt32Value JSON parse | 139.92 | — | — | 1943.61 (13.89x) | 375.57 (2.68x) |
| BoolValue JSON stringify | 46.68 | — | — | 902.00 (19.32x) | 161.91 (3.47x) |
| BoolValue JSON parse | 58.99 | — | — | 1714.86 (29.07x) | 253.92 (4.30x) |
| FalseBoolValue JSON stringify | 46.83 | — | — | 934.54 (19.96x) | 152.95 (3.27x) |
| FalseBoolValue JSON parse | 59.30 | — | — | 1781.42 (30.04x) | 252.38 (4.26x) |
| StringValue JSON stringify | 58.07 | — | — | 1033.20 (17.79x) | 203.66 (3.51x) |
| StringValue JSON parse | 130.29 | — | — | 1827.90 (14.03x) | 355.42 (2.73x) |
| EmptyStringValue JSON stringify | 52.44 | — | — | 960.41 (18.31x) | 218.62 (4.17x) |
| EmptyStringValue JSON parse | 73.47 | — | — | 1800.22 (24.50x) | 261.27 (3.56x) |
| BytesValue JSON stringify | 49.08 | — | — | 975.00 (19.87x) | 239.95 (4.89x) |
| BytesValue JSON parse | 142.28 | — | — | 1981.17 (13.92x) | 381.53 (2.68x) |
| EmptyBytesValue JSON stringify | 41.95 | — | — | 973.57 (23.21x) | 219.26 (5.23x) |
| EmptyBytesValue JSON parse | 82.77 | — | — | 1914.17 (23.13x) | 322.59 (3.90x) |
| TextFormat format | 238.31 | — | — | 3147.57 (13.21x) | 3095.09 (12.99x) |
| TextFormat parse | 843.79 | — | — | 5490.61 (6.51x) | 7980.67 (9.46x) |
| packed fixed32 encode | 2.26 | 804.62 (356.03x) | 628.90 (278.27x) | 90.35 (39.98x) | 581.45 (257.28x) |
| packed fixed32 decode | 7.10 | 1236.13 (174.10x) | 2831.26 (398.77x) | 99.46 (14.01x) | 2023.88 (285.05x) |
| packed fixed64 encode | 2.51 | 708.20 (282.15x) | 631.23 (251.49x) | 154.42 (61.52x) | 570.51 (227.29x) |
| packed fixed64 decode | 7.03 | 1223.62 (174.06x) | 7407.50 (1053.70x) | 163.45 (23.25x) | 3281.87 (466.84x) |
| packed sfixed32 encode | 2.51 | 705.07 (280.90x) | 628.67 (250.47x) | 90.79 (36.17x) | 584.73 (232.96x) |
| packed sfixed32 decode | 7.02 | 1233.29 (175.68x) | 2590.62 (369.03x) | 96.93 (13.81x) | 2050.14 (292.04x) |
| packed sfixed64 encode | 2.51 | 806.84 (321.45x) | 632.28 (251.90x) | 154.44 (61.53x) | 581.24 (231.57x) |
| packed sfixed64 decode | 7.15 | 1223.17 (171.07x) | 7350.41 (1028.03x) | 161.24 (22.55x) | 2835.32 (396.55x) |
| packed float encode | 2.51 | 827.96 (329.86x) | 629.63 (250.85x) | 90.78 (36.17x) | 602.44 (240.02x) |
| packed float decode | 7.02 | 1229.01 (175.07x) | 2625.30 (373.97x) | 96.95 (13.81x) | 2027.31 (288.79x) |
| packed double encode | 2.26 | 849.90 (376.06x) | 632.73 (279.97x) | 154.44 (68.34x) | 577.61 (255.58x) |
| packed double decode | 7.16 | 1222.11 (170.69x) | 2854.29 (398.64x) | 161.17 (22.51x) | 3338.99 (466.34x) |
| packed uint64 encode | 1834.39 | 6969.41 (3.80x) | 6356.92 (3.47x) | 3371.71 (1.84x) | 6181.32 (3.37x) |
| packed uint64 decode | 2588.58 | 4293.34 (1.66x) | 8622.92 (3.33x) | 4520.59 (1.75x) | 11575.78 (4.47x) |
| packed uint32 encode | 1348.65 | 4767.44 (3.53x) | 4918.54 (3.65x) | 2660.74 (1.97x) | 5426.23 (4.02x) |
| packed uint32 decode | 1880.38 | 3620.93 (1.93x) | 4785.63 (2.55x) | 3254.60 (1.73x) | 8717.98 (4.64x) |
| packed int64 encode | 2048.40 | 15633.01 (7.63x) | 7304.72 (3.57x) | 4487.99 (2.19x) | 7655.02 (3.74x) |
| packed int64 decode | 4435.15 | 5590.67 (1.26x) | 10649.75 (2.40x) | 5992.53 (1.35x) | 14473.25 (3.26x) |
| packed sint32 encode | 1091.32 | 4425.18 (4.05x) | 3604.05 (3.30x) | 2628.30 (2.41x) | 5987.36 (5.49x) |
| packed sint32 decode | 1296.38 | 3861.15 (2.98x) | 4664.26 (3.60x) | 1839.53 (1.42x) | 5014.89 (3.87x) |
| packed sint64 encode | 2497.47 | 7571.97 (3.03x) | 6265.56 (2.51x) | 3793.29 (1.52x) | 6707.32 (2.69x) |
| packed sint64 decode | 2846.89 | 4299.22 (1.51x) | 9790.63 (3.44x) | 4782.23 (1.68x) | 11783.44 (4.14x) |
| packed bool encode | 2.51 | 2080.26 (828.79x) | 539.58 (214.97x) | 23.48 (9.36x) | 4382.61 (1746.06x) |
| packed bool decode | 272.91 | 2057.57 (7.54x) | 3843.62 (14.08x) | 1107.05 (4.06x) | 2672.38 (9.79x) |
| packed enum encode | 549.21 | 4922.93 (8.96x) | 2077.78 (3.78x) | 1620.05 (2.95x) | 5045.59 (9.19x) |
| packed enum decode | 278.68 | 2443.43 (8.77x) | 3889.85 (13.96x) | 1002.11 (3.60x) | 3257.47 (11.69x) |
| large map encode | 5538.92 | 22354.86 (4.04x) | 13586.03 (2.45x) | 34489.60 (6.23x) | 239669.98 (43.27x) |
| shuffled large map deterministic binary encode | 36026.45 | — | — | 113765.00 (3.16x) | 441255.37 (12.25x) |
| large map decode | 37606.81 | 128397.41 (3.41x) | 116998.81 (3.11x) | 118813.00 (3.16x) | 306041.24 (8.14x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded zero/explicit-plus/positive/micro/nano/integer-negative/fractional-negative/min-max-bound `Duration`, non-empty and empty `Struct`, object/list/scalar `Value` (including default-like scalar and empty object/list kinds),
`FieldMask` (non-empty and empty), micro/nano/offset/min/pre/post/max-bound `Timestamp`, `Empty`, min/zero/positive/negative/max `Int64Value`, negative/zero/positive finite `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), negative/zero/positive finite `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), zero/normal/max `UInt64Value`, min/zero/positive/negative/max `Int32Value`, zero/normal/max `UInt32Value`, true/false `BoolValue`, non-empty/empty `StringValue`, base64/empty `BytesValue`, and recursive nested `Any` payloads), direct zero/explicit-plus/positive/micro/nano/integer-negative/fractional-negative/min-max-bound Duration and micro/nano/offset/min/pre/post/max-bound Timestamp WKT JSON plus other direct WKT JSON, including empty `Struct` and empty `ListValue`, TextFormat, packed scalars, large bytes,
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
