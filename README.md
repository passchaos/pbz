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

Latest accepted comparison (`/tmp/pbz-compare-fractional-time-precision-json-isolated.log`,
summarized in `/tmp/pbz-summary-fractional-time-precision-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 25.97 | 125.42 (4.83x) | 77.58 (2.99x) | 130.86 (5.04x) | 946.61 (36.45x) |
| binary decode | 131.39 | 294.55 (2.24x) | 301.50 (2.29x) | 276.02 (2.10x) | 1018.67 (7.75x) |
| unknown fields count by number | 4.77 | — | — | 178.94 (37.51x) | — |
| deterministic binary encode | 67.49 | — | — | 149.27 (2.21x) | 1237.53 (18.34x) |
| scalarmix encode | 26.24 | 113.78 (4.34x) | 69.49 (2.65x) | 45.13 (1.72x) | 237.13 (9.04x) |
| scalarmix decode | 56.02 | 162.92 (2.91x) | 210.80 (3.76x) | 108.26 (1.93x) | 367.59 (6.56x) |
| textbytes encode | 11.78 | 91.22 (7.74x) | 43.24 (3.67x) | 149.08 (12.66x) | 182.30 (15.48x) |
| textbytes decode | 60.02 | 472.10 (7.87x) | 308.88 (5.15x) | 197.96 (3.30x) | 812.68 (13.54x) |
| largebytes encode | 23.06 | 3907.75 (169.46x) | 3818.02 (165.57x) | 3905.56 (169.37x) | 4221.26 (183.06x) |
| largebytes decode | 123.26 | 8520.90 (69.13x) | 4562.15 (37.01x) | 5502.65 (44.64x) | 24295.42 (197.11x) |
| presencemix encode | 23.05 | 64.61 (2.80x) | 37.79 (1.64x) | 70.87 (3.07x) | 260.09 (11.28x) |
| presencemix decode | 67.34 | 162.36 (2.41x) | 145.62 (2.16x) | 197.60 (2.93x) | 563.52 (8.37x) |
| complex encode | 66.03 | 164.97 (2.50x) | 118.02 (1.79x) | 210.18 (3.18x) | 956.38 (14.48x) |
| complex decode | 214.45 | 461.00 (2.15x) | 440.33 (2.05x) | 473.78 (2.21x) | 1586.01 (7.40x) |
| complex deterministic binary encode | 126.67 | — | — | 217.82 (1.72x) | 1272.06 (10.04x) |
| complex JSON stringify | 372.07 | — | — | 7070.45 (19.00x) | 7527.53 (20.23x) |
| complex JSON parse | 2753.03 | — | — | 16729.70 (6.08x) | 10345.03 (3.76x) |
| complex TextFormat format | 335.83 | — | — | 4811.04 (14.33x) | 6666.37 (19.85x) |
| complex TextFormat parse | 2304.73 | — | — | 7894.75 (3.43x) | 11866.89 (5.15x) |
| packed int32 encode | 895.15 | 5395.60 (6.03x) | 3045.39 (3.40x) | 2269.05 (2.53x) | 5710.56 (6.38x) |
| packed int32 decode | 994.44 | 2988.19 (3.00x) | 4236.97 (4.26x) | 1447.74 (1.46x) | 4362.40 (4.39x) |
| JSON stringify | 202.03 | — | — | 4859.91 (24.06x) | 2997.93 (14.84x) |
| JSON parse | 1716.61 | — | — | 10709.40 (6.24x) | 6041.82 (3.52x) |
| Any WKT JSON stringify | 175.63 | — | — | 3047.43 (17.35x) | 1475.91 (8.40x) |
| Any WKT JSON parse | 565.74 | — | — | 4605.23 (8.14x) | 2262.98 (4.00x) |
| Any MicroDuration WKT JSON stringify | 180.44 | — | — | 3097.23 (17.16x) | 1494.63 (8.28x) |
| Any MicroDuration WKT JSON parse | 573.17 | — | — | 4691.21 (8.18x) | 2179.99 (3.80x) |
| Any NanoDuration WKT JSON stringify | 176.52 | — | — | 3101.50 (17.57x) | 1467.69 (8.31x) |
| Any NanoDuration WKT JSON parse | 582.44 | — | — | 4659.86 (8.00x) | 2622.22 (4.50x) |
| Any NegativeDuration WKT JSON stringify | 183.86 | — | — | 3102.09 (16.87x) | 1722.12 (9.37x) |
| Any NegativeDuration WKT JSON parse | 572.52 | — | — | 4734.48 (8.27x) | 2500.37 (4.37x) |
| Any FractionalNegativeDuration WKT JSON stringify | 173.46 | — | — | 3028.78 (17.46x) | 1622.89 (9.36x) |
| Any FractionalNegativeDuration WKT JSON parse | 563.64 | — | — | 4681.57 (8.31x) | 2341.63 (4.15x) |
| Any MaxDuration WKT JSON stringify | 158.78 | — | — | 2695.94 (16.98x) | 1524.37 (9.60x) |
| Any MaxDuration WKT JSON parse | 592.22 | — | — | 4570.64 (7.72x) | 2472.62 (4.18x) |
| Any MinDuration WKT JSON stringify | 160.07 | — | — | 2742.96 (17.14x) | 1704.46 (10.65x) |
| Any MinDuration WKT JSON parse | 594.32 | — | — | 4657.84 (7.84x) | 2436.82 (4.10x) |
| Any ZeroDuration WKT JSON stringify | 146.15 | — | — | 1315.02 (9.00x) | 1350.61 (9.24x) |
| Any ZeroDuration WKT JSON parse | 519.27 | — | — | 3289.89 (6.34x) | 2067.04 (3.98x) |
| Any FieldMask WKT JSON stringify | 284.41 | — | — | 2476.53 (8.71x) | 1875.29 (6.59x) |
| Any FieldMask WKT JSON parse | 787.20 | — | — | 4781.77 (6.07x) | 3059.91 (3.89x) |
| Any EmptyFieldMask WKT JSON stringify | 150.54 | — | — | 1299.47 (8.63x) | 970.46 (6.45x) |
| Any EmptyFieldMask WKT JSON parse | 489.64 | — | — | 3163.37 (6.46x) | 1723.24 (3.52x) |
| Any Timestamp WKT JSON stringify | 245.54 | — | — | 3004.20 (12.24x) | 1416.78 (5.77x) |
| Any Timestamp WKT JSON parse | 635.65 | — | — | 4618.18 (7.27x) | 2312.80 (3.64x) |
| Any Micro Timestamp WKT JSON stringify | 248.33 | — | — | 2996.91 (12.07x) | 1389.10 (5.59x) |
| Any Micro Timestamp WKT JSON parse | 641.10 | — | — | 4700.67 (7.33x) | 2369.86 (3.70x) |
| Any Nano Timestamp WKT JSON stringify | 249.32 | — | — | 2973.73 (11.93x) | 1394.85 (5.59x) |
| Any Nano Timestamp WKT JSON parse | 649.78 | — | — | 4717.76 (7.26x) | 2394.81 (3.69x) |
| Any PreEpoch Timestamp WKT JSON stringify | 194.84 | — | — | 2883.02 (14.80x) | 1392.62 (7.15x) |
| Any PreEpoch Timestamp WKT JSON parse | 617.60 | — | — | 4675.15 (7.57x) | 2251.37 (3.65x) |
| Any Max Timestamp WKT JSON stringify | 220.12 | — | — | 3036.62 (13.80x) | 1348.05 (6.12x) |
| Any Max Timestamp WKT JSON parse | 650.09 | — | — | 4774.33 (7.34x) | 2296.30 (3.53x) |
| Any Min Timestamp WKT JSON stringify | 230.15 | — | — | 2881.01 (12.52x) | 1350.86 (5.87x) |
| Any Min Timestamp WKT JSON parse | 615.31 | — | — | 4687.73 (7.62x) | 2246.92 (3.65x) |
| Any Empty WKT JSON stringify | 122.56 | — | — | 1318.39 (10.76x) | 786.14 (6.41x) |
| Any Empty WKT JSON parse | 372.67 | — | — | 3146.03 (8.44x) | 1598.91 (4.29x) |
| Any Struct WKT JSON stringify | 774.38 | — | — | 8997.22 (11.62x) | 8614.94 (11.12x) |
| Any Struct WKT JSON parse | 1950.15 | — | — | 17054.20 (8.75x) | 12979.68 (6.66x) |
| Any EmptyStruct WKT JSON stringify | 158.83 | — | — | 1276.83 (8.04x) | 1331.68 (8.38x) |
| Any EmptyStruct WKT JSON parse | 497.08 | — | — | 3280.50 (6.60x) | 2336.38 (4.70x) |
| Any Value WKT JSON stringify | 818.89 | — | — | 8964.11 (10.95x) | 9424.81 (11.51x) |
| Any Value WKT JSON parse | 2035.37 | — | — | 17149.20 (8.43x) | 13374.92 (6.57x) |
| Any NullValue WKT JSON stringify | 165.98 | — | — | 3194.07 (19.24x) | 1296.92 (7.81x) |
| Any NullValue WKT JSON parse | 514.49 | — | — | 6130.25 (11.92x) | 2243.21 (4.36x) |
| Any StringScalarValue WKT JSON stringify | 197.67 | — | — | 3174.44 (16.06x) | 1432.55 (7.25x) |
| Any StringScalarValue WKT JSON parse | 565.79 | — | — | 5335.89 (9.43x) | 2351.38 (4.16x) |
| Any EmptyStringScalarValue WKT JSON stringify | 176.39 | — | — | 3171.86 (17.98x) | 1364.44 (7.74x) |
| Any EmptyStringScalarValue WKT JSON parse | 533.68 | — | — | 5281.31 (9.90x) | 2233.43 (4.18x) |
| Any NumberValue WKT JSON stringify | 242.30 | — | — | 3907.20 (16.13x) | 1500.78 (6.19x) |
| Any NumberValue WKT JSON parse | 550.53 | — | — | 5611.22 (10.19x) | 2401.95 (4.36x) |
| Any ZeroNumberValue WKT JSON stringify | 186.91 | — | — | 3784.09 (20.25x) | 1387.65 (7.42x) |
| Any ZeroNumberValue WKT JSON parse | 561.57 | — | — | 5398.56 (9.61x) | 2393.63 (4.26x) |
| Any BoolScalarValue WKT JSON stringify | 168.06 | — | — | 3147.79 (18.73x) | 1305.93 (7.77x) |
| Any BoolScalarValue WKT JSON parse | 517.74 | — | — | 5241.11 (10.12x) | 2221.95 (4.29x) |
| Any FalseBoolScalarValue WKT JSON stringify | 167.45 | — | — | 3098.05 (18.50x) | 1294.35 (7.73x) |
| Any FalseBoolScalarValue WKT JSON parse | 513.48 | — | — | 5251.27 (10.23x) | 2198.84 (4.28x) |
| Any ListKindValue WKT JSON stringify | 613.68 | — | — | 8662.33 (14.12x) | 6947.31 (11.32x) |
| Any ListKindValue WKT JSON parse | 1528.32 | — | — | 15359.30 (10.05x) | 10476.14 (6.85x) |
| Any EmptyStructKindValue WKT JSON stringify | 186.67 | — | — | 4088.62 (21.90x) | 1949.10 (10.44x) |
| Any EmptyStructKindValue WKT JSON parse | 554.55 | — | — | 8062.09 (14.54x) | 3065.09 (5.53x) |
| Any EmptyListKindValue WKT JSON stringify | 185.19 | — | — | 4094.61 (22.11x) | 1596.67 (8.62x) |
| Any EmptyListKindValue WKT JSON parse | 564.58 | — | — | 6510.20 (11.53x) | 2759.19 (4.89x) |
| Any DoubleValue WKT JSON stringify | 253.84 | — | — | 2835.39 (11.17x) | 974.02 (3.84x) |
| Any DoubleValue WKT JSON parse | 569.62 | — | — | 4349.48 (7.64x) | 1969.00 (3.46x) |
| Any NegativeDoubleValue WKT JSON stringify | 255.38 | — | — | 2822.28 (11.05x) | 978.36 (3.83x) |
| Any NegativeDoubleValue WKT JSON parse | 571.20 | — | — | 4332.02 (7.58x) | 2005.86 (3.51x) |
| Any ZeroDoubleValue WKT JSON stringify | 203.03 | — | — | 1283.16 (6.32x) | 846.07 (4.17x) |
| Any ZeroDoubleValue WKT JSON parse | 571.29 | — | — | 3191.25 (5.59x) | 1827.02 (3.20x) |
| Any DoubleValue NaN WKT JSON stringify | 199.54 | — | — | 2319.43 (11.62x) | 842.34 (4.22x) |
| Any DoubleValue NaN WKT JSON parse | 567.10 | — | — | 4056.61 (7.15x) | 1888.75 (3.33x) |
| Any DoubleValue Infinity WKT JSON stringify | 205.42 | — | — | 2313.63 (11.26x) | 836.69 (4.07x) |
| Any DoubleValue Infinity WKT JSON parse | 571.64 | — | — | 4087.73 (7.15x) | 1891.25 (3.31x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 218.48 | — | — | 2240.58 (10.26x) | 843.49 (3.86x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 576.47 | — | — | 4088.06 (7.09x) | 1922.39 (3.33x) |
| Any FloatValue WKT JSON stringify | 259.71 | — | — | 2741.60 (10.56x) | 934.33 (3.60x) |
| Any FloatValue WKT JSON parse | 572.20 | — | — | 4272.32 (7.47x) | 1901.24 (3.32x) |
| Any NegativeFloatValue WKT JSON stringify | 258.87 | — | — | 2795.14 (10.80x) | 934.09 (3.61x) |
| Any NegativeFloatValue WKT JSON parse | 572.96 | — | — | 4296.63 (7.50x) | 1927.77 (3.36x) |
| Any ZeroFloatValue WKT JSON stringify | 206.34 | — | — | 1335.65 (6.47x) | 832.00 (4.03x) |
| Any ZeroFloatValue WKT JSON parse | 571.84 | — | — | 3205.72 (5.61x) | 1870.44 (3.27x) |
| Any FloatValue NaN WKT JSON stringify | 201.49 | — | — | 2262.95 (11.23x) | 832.41 (4.13x) |
| Any FloatValue NaN WKT JSON parse | 567.95 | — | — | 4029.37 (7.09x) | 1861.63 (3.28x) |
| Any FloatValue Infinity WKT JSON stringify | 207.60 | — | — | 2227.49 (10.73x) | 837.93 (4.04x) |
| Any FloatValue Infinity WKT JSON parse | 572.15 | — | — | 4059.16 (7.09x) | 1881.62 (3.29x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 207.60 | — | — | 2220.67 (10.70x) | 838.30 (4.04x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 575.58 | — | — | 4087.03 (7.10x) | 1923.71 (3.34x) |
| Any Int64Value WKT JSON stringify | 205.88 | — | — | 2211.45 (10.74x) | 1209.64 (5.88x) |
| Any Int64Value WKT JSON parse | 619.53 | — | — | 4319.67 (6.97x) | 2314.23 (3.74x) |
| Any ZeroInt64Value WKT JSON stringify | 196.02 | — | — | 1291.70 (6.59x) | 1036.93 (5.29x) |
| Any ZeroInt64Value WKT JSON parse | 572.35 | — | — | 3210.81 (5.61x) | 2104.42 (3.68x) |
| Any NegativeInt64Value WKT JSON stringify | 207.44 | — | — | 2201.59 (10.61x) | 1162.54 (5.60x) |
| Any NegativeInt64Value WKT JSON parse | 616.15 | — | — | 4299.06 (6.98x) | 2356.17 (3.82x) |
| Any MinInt64Value WKT JSON stringify | 213.51 | — | — | 2229.80 (10.44x) | 1185.08 (5.55x) |
| Any MinInt64Value WKT JSON parse | 627.47 | — | — | 4334.20 (6.91x) | 2376.47 (3.79x) |
| Any MaxInt64Value WKT JSON stringify | 210.35 | — | — | 2221.02 (10.56x) | 1179.70 (5.61x) |
| Any MaxInt64Value WKT JSON parse | 629.21 | — | — | 4369.91 (6.95x) | 2332.95 (3.71x) |
| Any UInt64Value WKT JSON stringify | 213.72 | — | — | 2185.22 (10.22x) | 1159.84 (5.43x) |
| Any UInt64Value WKT JSON parse | 622.94 | — | — | 4291.77 (6.89x) | 2291.12 (3.68x) |
| Any ZeroUInt64Value WKT JSON stringify | 205.38 | — | — | 1309.10 (6.37x) | 1015.51 (4.94x) |
| Any ZeroUInt64Value WKT JSON parse | 578.08 | — | — | 3212.07 (5.56x) | 2046.86 (3.54x) |
| Any MaxUInt64Value WKT JSON stringify | 220.10 | — | — | 2238.36 (10.17x) | 1179.06 (5.36x) |
| Any MaxUInt64Value WKT JSON parse | 636.17 | — | — | 4361.91 (6.86x) | 2340.04 (3.68x) |
| Any Int32Value WKT JSON stringify | 208.63 | — | — | 2310.69 (11.08x) | 845.17 (4.05x) |
| Any Int32Value WKT JSON parse | 594.80 | — | — | 4188.28 (7.04x) | 2022.30 (3.40x) |
| Any ZeroInt32Value WKT JSON stringify | 210.51 | — | — | 1320.43 (6.27x) | 809.24 (3.84x) |
| Any ZeroInt32Value WKT JSON parse | 588.18 | — | — | 3198.63 (5.44x) | 1899.73 (3.23x) |
| Any NegativeInt32Value WKT JSON stringify | 216.41 | — | — | 2301.32 (10.63x) | 865.90 (4.00x) |
| Any NegativeInt32Value WKT JSON parse | 592.24 | — | — | 4236.15 (7.15x) | 2071.45 (3.50x) |
| Any MinInt32Value WKT JSON stringify | 213.41 | — | — | 2279.02 (10.68x) | 883.35 (4.14x) |
| Any MinInt32Value WKT JSON parse | 600.59 | — | — | 4240.03 (7.06x) | 2131.37 (3.55x) |
| Any MaxInt32Value WKT JSON stringify | 214.56 | — | — | 2276.46 (10.61x) | 836.91 (3.90x) |
| Any MaxInt32Value WKT JSON parse | 608.23 | — | — | 4182.81 (6.88x) | 2033.94 (3.34x) |
| Any UInt32Value WKT JSON stringify | 220.47 | — | — | 2213.36 (10.04x) | 894.46 (4.06x) |
| Any UInt32Value WKT JSON parse | 599.65 | — | — | 4150.88 (6.92x) | 1998.67 (3.33x) |
| Any ZeroUInt32Value WKT JSON stringify | 216.18 | — | — | 1320.39 (6.11x) | 864.15 (4.00x) |
| Any ZeroUInt32Value WKT JSON parse | 592.50 | — | — | 3184.86 (5.38x) | 1929.65 (3.26x) |
| Any MaxUInt32Value WKT JSON stringify | 221.15 | — | — | 2175.01 (9.83x) | 916.53 (4.14x) |
| Any MaxUInt32Value WKT JSON parse | 612.70 | — | — | 4141.25 (6.76x) | 2002.71 (3.27x) |
| Any BoolValue WKT JSON stringify | 212.18 | — | — | 2159.47 (10.18x) | 876.27 (4.13x) |
| Any BoolValue WKT JSON parse | 552.59 | — | — | 4063.09 (7.35x) | 1748.04 (3.16x) |
| Any FalseBoolValue WKT JSON stringify | 212.23 | — | — | 1339.10 (6.31x) | 821.73 (3.87x) |
| Any FalseBoolValue WKT JSON parse | 551.65 | — | — | 3202.96 (5.81x) | 1640.62 (2.97x) |
| Any StringValue WKT JSON stringify | 247.75 | — | — | 2268.05 (9.15x) | 990.24 (4.00x) |
| Any StringValue WKT JSON parse | 611.35 | — | — | 4080.30 (6.67x) | 1877.72 (3.07x) |
| Any EmptyStringValue WKT JSON stringify | 228.13 | — | — | 1302.90 (5.71x) | 896.81 (3.93x) |
| Any EmptyStringValue WKT JSON parse | 572.60 | — | — | 3157.22 (5.51x) | 1634.66 (2.85x) |
| Any BytesValue WKT JSON stringify | 227.33 | — | — | 2309.53 (10.16x) | 1012.56 (4.45x) |
| Any BytesValue WKT JSON parse | 615.56 | — | — | 4219.31 (6.85x) | 1937.51 (3.15x) |
| Any EmptyBytesValue WKT JSON stringify | 221.95 | — | — | 1306.67 (5.89x) | 865.88 (3.90x) |
| Any EmptyBytesValue WKT JSON parse | 578.30 | — | — | 3173.84 (5.49x) | 1806.84 (3.12x) |
| Nested Any WKT JSON stringify | 389.03 | — | — | 3462.89 (8.90x) | 1658.66 (4.26x) |
| Nested Any WKT JSON parse | 998.00 | — | — | 6128.96 (6.14x) | 3566.28 (3.57x) |
| Duration JSON stringify | 65.47 | — | — | 1560.84 (23.84x) | 415.74 (6.35x) |
| Duration JSON parse | 12.38 | — | — | 2357.33 (190.41x) | 418.31 (33.79x) |
| MicroDuration JSON stringify | 69.26 | — | — | 1498.56 (21.64x) | 441.85 (6.38x) |
| MicroDuration JSON parse | 15.76 | — | — | 2347.41 (148.95x) | 434.03 (27.54x) |
| NanoDuration JSON stringify | 65.28 | — | — | 1581.77 (24.23x) | 444.98 (6.82x) |
| NanoDuration JSON parse | 22.04 | — | — | 2387.45 (108.32x) | 437.23 (19.84x) |
| NegativeDuration JSON stringify | 66.39 | — | — | 1598.47 (24.08x) | 466.41 (7.03x) |
| NegativeDuration JSON parse | 12.88 | — | — | 2412.55 (187.31x) | 436.10 (33.86x) |
| FractionalNegativeDuration JSON stringify | 66.09 | — | — | 1547.87 (23.42x) | 468.98 (7.10x) |
| FractionalNegativeDuration JSON parse | 13.07 | — | — | 2345.39 (179.45x) | 421.62 (32.26x) |
| MaxDuration JSON stringify | 53.77 | — | — | 1319.55 (24.54x) | 437.36 (8.13x) |
| MaxDuration JSON parse | 29.29 | — | — | 2236.89 (76.37x) | 438.26 (14.96x) |
| MinDuration JSON stringify | 54.85 | — | — | 1318.09 (24.03x) | 493.76 (9.00x) |
| MinDuration JSON parse | 29.65 | — | — | 2259.94 (76.22x) | 433.67 (14.63x) |
| ZeroDuration JSON stringify | 48.85 | — | — | 1261.93 (25.83x) | 362.31 (7.42x) |
| ZeroDuration JSON parse | 8.78 | — | — | 2178.03 (248.07x) | 339.14 (38.63x) |
| FieldMask JSON stringify | 94.55 | — | — | 1284.59 (13.59x) | 769.35 (8.14x) |
| FieldMask JSON parse | 182.77 | — | — | 2682.73 (14.68x) | 1028.03 (5.62x) |
| EmptyFieldMask JSON stringify | 43.89 | — | — | 941.14 (21.44x) | 238.12 (5.43x) |
| EmptyFieldMask JSON parse | 3.52 | — | — | 1464.27 (415.99x) | 208.43 (59.21x) |
| Timestamp JSON stringify | 129.54 | — | — | 1718.36 (13.27x) | 481.65 (3.72x) |
| Timestamp JSON parse | 56.89 | — | — | 2321.82 (40.81x) | 477.83 (8.40x) |
| Micro Timestamp JSON stringify | 131.01 | — | — | 1719.85 (13.13x) | 484.77 (3.70x) |
| Micro Timestamp JSON parse | 59.66 | — | — | 2301.68 (38.58x) | 484.52 (8.12x) |
| Nano Timestamp JSON stringify | 130.73 | — | — | 1737.12 (13.29x) | 484.83 (3.71x) |
| Nano Timestamp JSON parse | 62.80 | — | — | 2290.39 (36.47x) | 491.65 (7.83x) |
| PreEpoch Timestamp JSON stringify | 85.67 | — | — | 1572.90 (18.36x) | 470.09 (5.49x) |
| PreEpoch Timestamp JSON parse | 54.85 | — | — | 2239.47 (40.83x) | 473.83 (8.64x) |
| Max Timestamp JSON stringify | 103.79 | — | — | 1722.86 (16.60x) | 498.89 (4.81x) |
| Max Timestamp JSON parse | 64.30 | — | — | 2310.47 (35.93x) | 505.49 (7.86x) |
| Min Timestamp JSON stringify | 118.52 | — | — | 1574.95 (13.29x) | 496.56 (4.19x) |
| Min Timestamp JSON parse | 52.76 | — | — | 2237.03 (42.40x) | 473.52 (8.97x) |
| Empty JSON stringify | 23.77 | — | — | 693.24 (29.16x) | 102.83 (4.33x) |
| Empty JSON parse | 72.62 | — | — | 1099.89 (15.15x) | 251.06 (3.46x) |
| Struct JSON stringify | 273.31 | — | — | 8974.67 (32.84x) | 3871.79 (14.17x) |
| Struct JSON parse | 934.12 | — | — | 16922.40 (18.12x) | 6312.91 (6.76x) |
| EmptyStruct JSON stringify | 43.63 | — | — | 1040.22 (23.84x) | 412.75 (9.46x) |
| EmptyStruct JSON parse | 89.97 | — | — | 3396.19 (37.75x) | 436.59 (4.85x) |
| Value JSON stringify | 285.90 | — | — | 9920.49 (34.70x) | 4060.17 (14.20x) |
| Value JSON parse | 954.85 | — | — | 17961.40 (18.81x) | 6550.40 (6.86x) |
| NullValue JSON stringify | 41.81 | — | — | 1726.20 (41.29x) | 248.71 (5.95x) |
| NullValue JSON parse | 58.60 | — | — | 3744.80 (63.90x) | 373.26 (6.37x) |
| StringScalarValue JSON stringify | 56.49 | — | — | 1813.08 (32.10x) | 294.26 (5.21x) |
| StringScalarValue JSON parse | 121.65 | — | — | 3062.56 (25.18x) | 493.03 (4.05x) |
| EmptyStringScalarValue JSON stringify | 51.38 | — | — | 1786.85 (34.78x) | 290.79 (5.66x) |
| EmptyStringScalarValue JSON parse | 68.04 | — | — | 3039.62 (44.67x) | 401.81 (5.91x) |
| NumberValue JSON stringify | 113.01 | — | — | 2287.14 (20.24x) | 381.39 (3.37x) |
| NumberValue JSON parse | 117.48 | — | — | 3303.18 (28.12x) | 448.14 (3.81x) |
| ZeroNumberValue JSON stringify | 64.50 | — | — | 2218.04 (34.39x) | 328.15 (5.09x) |
| ZeroNumberValue JSON parse | 120.07 | — | — | 3117.47 (25.96x) | 429.94 (3.58x) |
| BoolScalarValue JSON stringify | 42.76 | — | — | 1704.21 (39.86x) | 238.41 (5.58x) |
| BoolScalarValue JSON parse | 55.38 | — | — | 2948.57 (53.24x) | 352.35 (6.36x) |
| FalseBoolScalarValue JSON stringify | 42.30 | — | — | 1720.72 (40.68x) | 245.66 (5.81x) |
| FalseBoolScalarValue JSON parse | 62.75 | — | — | 2967.75 (47.29x) | 372.47 (5.94x) |
| ListKindValue JSON stringify | 209.19 | — | — | 9191.46 (43.94x) | 2918.89 (13.95x) |
| ListKindValue JSON parse | 758.38 | — | — | 15900.40 (20.97x) | 5654.74 (7.46x) |
| EmptyStructKindValue JSON stringify | 45.14 | — | — | 2767.68 (61.31x) | 663.87 (14.71x) |
| EmptyStructKindValue JSON parse | 106.27 | — | — | 5747.45 (54.08x) | 867.52 (8.16x) |
| EmptyListKindValue JSON stringify | 43.96 | — | — | 2664.38 (60.61x) | 400.64 (9.11x) |
| EmptyListKindValue JSON parse | 142.57 | — | — | 5571.25 (39.08x) | 693.21 (4.86x) |
| ListValue JSON stringify | 203.40 | — | — | 7537.58 (37.06x) | 2712.21 (13.33x) |
| ListValue JSON parse | 742.57 | — | — | 13607.30 (18.32x) | 5395.57 (7.27x) |
| EmptyListValue JSON stringify | 41.22 | — | — | 979.03 (23.75x) | 242.36 (5.88x) |
| EmptyListValue JSON parse | 130.51 | — | — | 3206.02 (24.57x) | 403.39 (3.09x) |
| DoubleValue JSON stringify | 97.59 | — | — | 1470.11 (15.06x) | 230.12 (2.36x) |
| DoubleValue JSON parse | 114.27 | — | — | 2093.82 (18.32x) | 332.50 (2.91x) |
| NegativeDoubleValue JSON stringify | 97.44 | — | — | 1470.03 (15.09x) | 218.35 (2.24x) |
| NegativeDoubleValue JSON parse | 114.12 | — | — | 2126.29 (18.63x) | 327.04 (2.87x) |
| ZeroDoubleValue JSON stringify | 53.41 | — | — | 1368.70 (25.63x) | 173.60 (3.25x) |
| ZeroDoubleValue JSON parse | 116.12 | — | — | 1870.91 (16.11x) | 309.34 (2.66x) |
| DoubleValue NaN JSON stringify | 53.00 | — | — | 997.64 (18.82x) | 155.07 (2.93x) |
| DoubleValue NaN JSON parse | 101.89 | — | — | 1715.99 (16.84x) | 314.19 (3.08x) |
| DoubleValue Infinity JSON stringify | 56.59 | — | — | 976.64 (17.26x) | 165.20 (2.92x) |
| DoubleValue Infinity JSON parse | 104.30 | — | — | 1726.41 (16.55x) | 319.59 (3.06x) |
| DoubleValue NegativeInfinity JSON stringify | 58.11 | — | — | 979.27 (16.85x) | 163.57 (2.81x) |
| DoubleValue NegativeInfinity JSON parse | 107.36 | — | — | 1744.95 (16.25x) | 319.19 (2.97x) |
| FloatValue JSON stringify | 102.38 | — | — | 1436.75 (14.03x) | 217.33 (2.12x) |
| FloatValue JSON parse | 113.82 | — | — | 2115.05 (18.58x) | 324.75 (2.85x) |
| NegativeFloatValue JSON stringify | 102.21 | — | — | 1435.80 (14.05x) | 209.81 (2.05x) |
| NegativeFloatValue JSON parse | 113.98 | — | — | 2160.15 (18.95x) | 320.42 (2.81x) |
| ZeroFloatValue JSON stringify | 52.28 | — | — | 1357.89 (25.97x) | 178.30 (3.41x) |
| ZeroFloatValue JSON parse | 115.96 | — | — | 1868.61 (16.11x) | 311.09 (2.68x) |
| FloatValue NaN JSON stringify | 53.21 | — | — | 1001.76 (18.83x) | 162.78 (3.06x) |
| FloatValue NaN JSON parse | 102.80 | — | — | 1721.18 (16.74x) | 311.98 (3.03x) |
| FloatValue Infinity JSON stringify | 56.53 | — | — | 969.80 (17.16x) | 161.02 (2.85x) |
| FloatValue Infinity JSON parse | 104.34 | — | — | 1723.94 (16.52x) | 323.10 (3.10x) |
| FloatValue NegativeInfinity JSON stringify | 58.10 | — | — | 965.79 (16.62x) | 160.87 (2.77x) |
| FloatValue NegativeInfinity JSON parse | 108.02 | — | — | 1752.82 (16.23x) | 328.61 (3.04x) |
| Int64Value JSON stringify | 54.50 | — | — | 1005.87 (18.46x) | 300.70 (5.52x) |
| Int64Value JSON parse | 138.47 | — | — | 1990.79 (14.38x) | 517.76 (3.74x) |
| ZeroInt64Value JSON stringify | 44.37 | — | — | 928.72 (20.93x) | 201.68 (4.55x) |
| ZeroInt64Value JSON parse | 102.75 | — | — | 1821.79 (17.73x) | 383.03 (3.73x) |
| NegativeInt64Value JSON stringify | 54.45 | — | — | 1007.63 (18.51x) | 322.49 (5.92x) |
| NegativeInt64Value JSON parse | 139.35 | — | — | 1966.14 (14.11x) | 544.05 (3.90x) |
| MinInt64Value JSON stringify | 72.89 | — | — | 1018.77 (13.98x) | 329.09 (4.51x) |
| MinInt64Value JSON parse | 148.88 | — | — | 2014.51 (13.53x) | 564.34 (3.79x) |
| MaxInt64Value JSON stringify | 73.02 | — | — | 989.28 (13.55x) | 323.23 (4.43x) |
| MaxInt64Value JSON parse | 148.23 | — | — | 2001.59 (13.50x) | 526.88 (3.55x) |
| UInt64Value JSON stringify | 72.71 | — | — | 1016.99 (13.99x) | 320.26 (4.40x) |
| UInt64Value JSON parse | 146.46 | — | — | 1951.31 (13.32x) | 508.07 (3.47x) |
| ZeroUInt64Value JSON stringify | 44.79 | — | — | 924.66 (20.64x) | 208.35 (4.65x) |
| ZeroUInt64Value JSON parse | 109.63 | — | — | 1786.03 (16.29x) | 383.76 (3.50x) |
| MaxUInt64Value JSON stringify | 67.56 | — | — | 1012.19 (14.98x) | 346.09 (5.12x) |
| MaxUInt64Value JSON parse | 159.93 | — | — | 2010.43 (12.57x) | 524.25 (3.28x) |
| Int32Value JSON stringify | 49.15 | — | — | 975.80 (19.85x) | 169.97 (3.46x) |
| Int32Value JSON parse | 134.77 | — | — | 1919.94 (14.25x) | 335.05 (2.49x) |
| ZeroInt32Value JSON stringify | 48.49 | — | — | 960.18 (19.80x) | 165.86 (3.42x) |
| ZeroInt32Value JSON parse | 129.34 | — | — | 1883.81 (14.56x) | 308.48 (2.39x) |
| NegativeInt32Value JSON stringify | 49.63 | — | — | 1000.61 (20.16x) | 164.33 (3.31x) |
| NegativeInt32Value JSON parse | 130.37 | — | — | 1926.50 (14.78x) | 345.68 (2.65x) |
| MinInt32Value JSON stringify | 49.85 | — | — | 1003.86 (20.14x) | 173.34 (3.48x) |
| MinInt32Value JSON parse | 142.38 | — | — | 1945.22 (13.66x) | 379.49 (2.67x) |
| MaxInt32Value JSON stringify | 49.73 | — | — | 979.75 (19.70x) | 184.25 (3.71x) |
| MaxInt32Value JSON parse | 145.49 | — | — | 1938.23 (13.32x) | 353.79 (2.43x) |
| UInt32Value JSON stringify | 49.36 | — | — | 933.15 (18.91x) | 168.86 (3.42x) |
| UInt32Value JSON parse | 135.44 | — | — | 1905.60 (14.07x) | 345.25 (2.55x) |
| ZeroUInt32Value JSON stringify | 48.85 | — | — | 920.20 (18.84x) | 169.38 (3.47x) |
| ZeroUInt32Value JSON parse | 129.93 | — | — | 1866.24 (14.36x) | 311.11 (2.39x) |
| MaxUInt32Value JSON stringify | 49.48 | — | — | 933.25 (18.86x) | 186.71 (3.77x) |
| MaxUInt32Value JSON parse | 145.32 | — | — | 1926.47 (13.26x) | 374.87 (2.58x) |
| BoolValue JSON stringify | 46.49 | — | — | 912.08 (19.62x) | 155.55 (3.35x) |
| BoolValue JSON parse | 62.41 | — | — | 1701.59 (27.26x) | 262.47 (4.21x) |
| FalseBoolValue JSON stringify | 46.75 | — | — | 922.91 (19.74x) | 166.08 (3.55x) |
| FalseBoolValue JSON parse | 63.03 | — | — | 1726.06 (27.38x) | 262.98 (4.17x) |
| StringValue JSON stringify | 58.68 | — | — | 1022.64 (17.43x) | 215.79 (3.68x) |
| StringValue JSON parse | 126.86 | — | — | 1842.85 (14.53x) | 347.88 (2.74x) |
| EmptyStringValue JSON stringify | 52.65 | — | — | 954.68 (18.13x) | 223.03 (4.24x) |
| EmptyStringValue JSON parse | 68.97 | — | — | 1781.93 (25.84x) | 265.83 (3.85x) |
| BytesValue JSON stringify | 49.07 | — | — | 976.21 (19.89x) | 248.42 (5.06x) |
| BytesValue JSON parse | 145.95 | — | — | 1968.10 (13.48x) | 382.79 (2.62x) |
| EmptyBytesValue JSON stringify | 43.43 | — | — | 962.18 (22.15x) | 219.53 (5.05x) |
| EmptyBytesValue JSON parse | 86.30 | — | — | 1909.60 (22.13x) | 318.54 (3.69x) |
| TextFormat format | 238.36 | — | — | 3135.09 (13.15x) | 3111.53 (13.05x) |
| TextFormat parse | 878.46 | — | — | 5525.45 (6.29x) | 8090.48 (9.21x) |
| packed fixed32 encode | 2.26 | 808.41 (357.70x) | 628.59 (278.14x) | 90.36 (39.98x) | 569.60 (252.04x) |
| packed fixed32 decode | 7.02 | 1306.78 (186.15x) | 2839.13 (404.43x) | 99.23 (14.14x) | 2005.23 (285.65x) |
| packed fixed64 encode | 2.51 | 708.16 (282.14x) | 630.76 (251.30x) | 157.69 (62.83x) | 570.35 (227.23x) |
| packed fixed64 decode | 7.75 | 1971.30 (254.36x) | 7418.68 (957.25x) | 166.53 (21.49x) | 3215.31 (414.88x) |
| packed sfixed32 encode | 2.94 | 704.81 (239.73x) | 629.23 (214.02x) | 94.01 (31.98x) | 574.24 (195.32x) |
| packed sfixed32 decode | 7.38 | 1233.97 (167.20x) | 2606.69 (353.21x) | 98.86 (13.40x) | 2010.72 (272.46x) |
| packed sfixed64 encode | 2.26 | 846.30 (374.47x) | 632.82 (280.01x) | 155.08 (68.62x) | 571.09 (252.69x) |
| packed sfixed64 decode | 7.25 | 1949.51 (268.90x) | 7317.53 (1009.31x) | 161.53 (22.28x) | 2750.67 (379.40x) |
| packed float encode | 2.80 | 834.31 (297.97x) | 629.11 (224.68x) | 90.89 (32.46x) | 565.86 (202.09x) |
| packed float decode | 7.54 | 1978.55 (262.41x) | 2639.93 (350.12x) | 96.77 (12.83x) | 2002.74 (265.62x) |
| packed double encode | 2.33 | 858.58 (368.49x) | 632.88 (271.62x) | 154.76 (66.42x) | 567.81 (243.70x) |
| packed double decode | 7.32 | 1222.95 (167.07x) | 2869.16 (391.96x) | 161.53 (22.07x) | 3235.66 (442.03x) |
| packed uint64 encode | 1836.50 | 6929.01 (3.77x) | 6588.68 (3.59x) | 3134.04 (1.71x) | 6149.50 (3.35x) |
| packed uint64 decode | 2590.78 | 4305.27 (1.66x) | 8622.27 (3.33x) | 4529.80 (1.75x) | 11437.95 (4.41x) |
| packed uint32 encode | 1365.77 | 4740.55 (3.47x) | 4413.56 (3.23x) | 2663.43 (1.95x) | 5430.35 (3.98x) |
| packed uint32 decode | 1881.48 | 3605.93 (1.92x) | 4796.35 (2.55x) | 3258.71 (1.73x) | 8722.88 (4.64x) |
| packed int64 encode | 2208.09 | 15637.99 (7.08x) | 7312.77 (3.31x) | 4176.03 (1.89x) | 7742.86 (3.51x) |
| packed int64 decode | 4311.07 | 5598.41 (1.30x) | 10651.06 (2.47x) | 5996.83 (1.39x) | 15094.13 (3.50x) |
| packed sint32 encode | 1091.51 | 4427.75 (4.06x) | 3605.39 (3.30x) | 2634.55 (2.41x) | 5997.90 (5.50x) |
| packed sint32 decode | 1295.95 | 3856.30 (2.98x) | 4662.66 (3.60x) | 1589.02 (1.23x) | 5105.07 (3.94x) |
| packed sint64 encode | 2496.67 | 7851.82 (3.14x) | 6265.07 (2.51x) | 3434.70 (1.38x) | 6729.34 (2.70x) |
| packed sint64 decode | 2845.21 | 4300.29 (1.51x) | 9787.52 (3.44x) | 4786.66 (1.68x) | 11986.65 (4.21x) |
| packed bool encode | 2.76 | 2079.55 (753.46x) | 539.10 (195.33x) | 24.07 (8.72x) | 4383.22 (1588.12x) |
| packed bool decode | 272.01 | 2054.74 (7.55x) | 4312.12 (15.85x) | 1109.19 (4.08x) | 2729.96 (10.04x) |
| packed enum encode | 553.81 | 4922.11 (8.89x) | 2588.45 (4.67x) | 2099.33 (3.79x) | 5038.02 (9.10x) |
| packed enum decode | 277.75 | 2073.00 (7.46x) | 3897.74 (14.03x) | 1932.99 (6.96x) | 3255.61 (11.72x) |
| large map encode | 5654.20 | 22226.60 (3.93x) | 13237.88 (2.34x) | 34593.10 (6.12x) | 239879.11 (42.42x) |
| shuffled large map deterministic binary encode | 36887.25 | — | — | 109590.00 (2.97x) | 448189.70 (12.15x) |
| large map decode | 38175.80 | 129091.52 (3.38x) | 118778.88 (3.11x) | 117783.00 (3.09x) | 296770.33 (7.77x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded zero/positive/micro/nano/integer-negative/fractional-negative/min-max-bound `Duration`, non-empty and empty `Struct`, object/list/scalar `Value` (including default-like scalar and empty object/list kinds),
`FieldMask` (non-empty and empty), micro/nano/min/pre/post/max-bound `Timestamp`, `Empty`, min/zero/positive/negative/max `Int64Value`, negative/zero/positive finite `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), negative/zero/positive finite `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), zero/normal/max `UInt64Value`, min/zero/positive/negative/max `Int32Value`, zero/normal/max `UInt32Value`, true/false `BoolValue`, non-empty/empty `StringValue`, base64/empty `BytesValue`, and recursive nested `Any` payloads), direct zero/positive/micro/nano/integer-negative/fractional-negative/min-max-bound Duration and micro/nano/min/pre/post/max-bound Timestamp WKT JSON plus other direct WKT JSON, including empty `Struct` and empty `ListValue`, TextFormat, packed scalars, large bytes,
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
