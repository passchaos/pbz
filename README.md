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

Latest accepted comparison (`/tmp/pbz-compare-empty-fieldmask-json-isolated.log`,
summarized in `/tmp/pbz-summary-empty-fieldmask-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 25.27 | 125.94 (4.98x) | 68.20 (2.70x) | 123.34 (4.88x) | 943.95 (37.35x) |
| binary decode | 137.65 | 294.65 (2.14x) | 304.76 (2.21x) | 268.10 (1.95x) | 1017.77 (7.39x) |
| unknown fields count by number | 5.02 | — | — | 180.82 (36.02x) | — |
| scalarmix encode | 27.20 | 113.20 (4.16x) | 68.30 (2.51x) | 45.52 (1.67x) | 237.92 (8.75x) |
| scalarmix decode | 50.80 | 162.38 (3.20x) | 218.94 (4.31x) | 112.17 (2.21x) | 377.41 (7.43x) |
| textbytes encode | 13.53 | 91.95 (6.80x) | 43.26 (3.20x) | 145.60 (10.76x) | 173.98 (12.86x) |
| largebytes decode | 124.70 | 8427.12 (67.58x) | 4822.86 (38.68x) | 4100.51 (32.88x) | 24149.27 (193.66x) |
| complex decode | 227.17 | 463.34 (2.04x) | 489.56 (2.16x) | 490.69 (2.16x) | 1594.50 (7.02x) |
| complex JSON parse | 2821.84 | — | — | 16620.90 (5.89x) | 10448.27 (3.70x) |
| packed int32 decode | 1028.87 | 2977.00 (2.89x) | 4295.21 (4.17x) | 1341.77 (1.30x) | 4356.37 (4.23x) |
| Any WKT JSON stringify | 167.40 | — | — | 3003.26 (17.94x) | 1352.30 (8.08x) |
| Any WKT JSON parse | 564.25 | — | — | 4578.33 (8.11x) | 2120.67 (3.76x) |
| Any NegativeDuration WKT JSON stringify | 174.08 | — | — | 3052.06 (17.53x) | 1434.19 (8.24x) |
| Any NegativeDuration WKT JSON parse | 570.62 | — | — | 4655.54 (8.16x) | 2155.55 (3.78x) |
| Any FractionalNegativeDuration WKT JSON stringify | 164.23 | — | — | 3019.15 (18.38x) | 1366.32 (8.32x) |
| Any FractionalNegativeDuration WKT JSON parse | 561.21 | — | — | 4646.55 (8.28x) | 2100.83 (3.74x) |
| Any MaxDuration WKT JSON stringify | 150.76 | — | — | 2701.85 (17.92x) | 1339.54 (8.89x) |
| Any MaxDuration WKT JSON parse | 583.43 | — | — | 4505.44 (7.72x) | 2123.62 (3.64x) |
| Any MinDuration WKT JSON stringify | 152.98 | — | — | 2720.60 (17.78x) | 1402.17 (9.17x) |
| Any MinDuration WKT JSON parse | 584.81 | — | — | 4520.51 (7.73x) | 2103.67 (3.60x) |
| Any ZeroDuration WKT JSON stringify | 136.83 | — | — | 1279.32 (9.35x) | 1218.24 (8.90x) |
| Any ZeroDuration WKT JSON parse | 512.63 | — | — | 3232.89 (6.31x) | 1941.08 (3.79x) |
| Any FieldMask WKT JSON stringify | 276.82 | — | — | 2432.54 (8.79x) | 1794.47 (6.48x) |
| Any FieldMask WKT JSON parse | 781.93 | — | — | 4777.49 (6.11x) | 2916.24 (3.73x) |
| Any EmptyFieldMask WKT JSON stringify | 141.41 | — | — | 1312.16 (9.28x) | 894.41 (6.32x) |
| Any EmptyFieldMask WKT JSON parse | 486.28 | — | — | 3210.71 (6.60x) | 1607.43 (3.31x) |
| Any Timestamp WKT JSON stringify | 237.98 | — | — | 2991.19 (12.57x) | 1335.21 (5.61x) |
| Any Timestamp WKT JSON parse | 631.70 | — | — | 4646.05 (7.35x) | 2243.26 (3.55x) |
| Any PreEpoch Timestamp WKT JSON stringify | 185.41 | — | — | 2901.06 (15.65x) | 1281.70 (6.91x) |
| Any PreEpoch Timestamp WKT JSON parse | 618.92 | — | — | 4657.67 (7.53x) | 2212.50 (3.57x) |
| Any Max Timestamp WKT JSON stringify | 211.48 | — | — | 2978.55 (14.08x) | 1323.02 (6.26x) |
| Any Max Timestamp WKT JSON parse | 649.05 | — | — | 4715.50 (7.27x) | 2276.80 (3.51x) |
| Any Min Timestamp WKT JSON stringify | 218.00 | — | — | 2842.74 (13.04x) | 1281.96 (5.88x) |
| Any Min Timestamp WKT JSON parse | 613.90 | — | — | 4648.00 (7.57x) | 2202.98 (3.59x) |
| Any Empty WKT JSON stringify | 114.28 | — | — | 1301.78 (11.39x) | 739.73 (6.47x) |
| Any Empty WKT JSON parse | 371.66 | — | — | 3127.04 (8.41x) | 1621.89 (4.36x) |
| Any Struct WKT JSON stringify | 771.72 | — | — | 8933.73 (11.58x) | 8531.08 (11.05x) |
| Any Struct WKT JSON parse | 1946.22 | — | — | 17152.60 (8.81x) | 12491.16 (6.42x) |
| Any Value WKT JSON stringify | 800.06 | — | — | 8967.26 (11.21x) | 8979.84 (11.22x) |
| Any Value WKT JSON parse | 2000.89 | — | — | 16835.60 (8.41x) | 12890.43 (6.44x) |
| Any DoubleValue WKT JSON stringify | 240.43 | — | — | 2811.80 (11.69x) | 961.03 (4.00x) |
| Any DoubleValue WKT JSON parse | 565.84 | — | — | 4320.55 (7.64x) | 1973.30 (3.49x) |
| Any NegativeDoubleValue WKT JSON stringify | 240.51 | — | — | 2844.01 (11.82x) | 938.98 (3.90x) |
| Any NegativeDoubleValue WKT JSON parse | 568.11 | — | — | 4331.30 (7.62x) | 1968.39 (3.46x) |
| Any ZeroDoubleValue WKT JSON stringify | 191.42 | — | — | 1291.08 (6.74x) | 844.36 (4.41x) |
| Any ZeroDoubleValue WKT JSON parse | 567.15 | — | — | 3173.85 (5.60x) | 1884.71 (3.32x) |
| Any DoubleValue NaN WKT JSON stringify | 185.59 | — | — | 2313.14 (12.46x) | 838.83 (4.52x) |
| Any DoubleValue NaN WKT JSON parse | 565.73 | — | — | 4068.42 (7.19x) | 1873.15 (3.31x) |
| Any DoubleValue Infinity WKT JSON stringify | 189.19 | — | — | 2270.24 (12.00x) | 840.66 (4.44x) |
| Any DoubleValue Infinity WKT JSON parse | 568.95 | — | — | 4080.99 (7.17x) | 1895.98 (3.33x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 189.33 | — | — | 2247.49 (11.87x) | 831.76 (4.39x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 572.67 | — | — | 4047.21 (7.07x) | 1923.58 (3.36x) |
| Any FloatValue WKT JSON stringify | 247.68 | — | — | 2754.85 (11.12x) | 980.80 (3.96x) |
| Any FloatValue WKT JSON parse | 566.05 | — | — | 4280.26 (7.56x) | 1907.30 (3.37x) |
| Any NegativeFloatValue WKT JSON stringify | 247.83 | — | — | 2752.19 (11.11x) | 934.53 (3.77x) |
| Any NegativeFloatValue WKT JSON parse | 567.09 | — | — | 4360.00 (7.69x) | 1924.72 (3.39x) |
| Any ZeroFloatValue WKT JSON stringify | 193.87 | — | — | 1312.53 (6.77x) | 836.28 (4.31x) |
| Any ZeroFloatValue WKT JSON parse | 569.70 | — | — | 3117.31 (5.47x) | 1908.74 (3.35x) |
| Any FloatValue NaN WKT JSON stringify | 188.13 | — | — | 2228.23 (11.84x) | 831.48 (4.42x) |
| Any FloatValue NaN WKT JSON parse | 568.38 | — | — | 4071.54 (7.16x) | 1816.43 (3.20x) |
| Any FloatValue Infinity WKT JSON stringify | 191.34 | — | — | 2168.04 (11.33x) | 839.78 (4.39x) |
| Any FloatValue Infinity WKT JSON parse | 576.72 | — | — | 4099.32 (7.11x) | 1884.68 (3.27x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 193.88 | — | — | 2170.45 (11.19x) | 834.24 (4.30x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 584.20 | — | — | 4056.35 (6.94x) | 1894.00 (3.24x) |
| Any Int64Value WKT JSON stringify | 205.38 | — | — | 2172.37 (10.58x) | 1162.56 (5.66x) |
| Any Int64Value WKT JSON parse | 614.32 | — | — | 4249.40 (6.92x) | 2284.38 (3.72x) |
| Any ZeroInt64Value WKT JSON stringify | 187.68 | — | — | 1311.66 (6.99x) | 1010.89 (5.39x) |
| Any ZeroInt64Value WKT JSON parse | 569.52 | — | — | 3165.01 (5.56x) | 2052.43 (3.60x) |
| Any NegativeInt64Value WKT JSON stringify | 200.74 | — | — | 2172.33 (10.82x) | 1164.27 (5.80x) |
| Any NegativeInt64Value WKT JSON parse | 610.97 | — | — | 4286.10 (7.02x) | 2362.72 (3.87x) |
| Any MinInt64Value WKT JSON stringify | 203.85 | — | — | 2197.22 (10.78x) | 1178.78 (5.78x) |
| Any MinInt64Value WKT JSON parse | 621.09 | — | — | 4282.57 (6.90x) | 2375.34 (3.82x) |
| Any MaxInt64Value WKT JSON stringify | 203.02 | — | — | 2173.70 (10.71x) | 1171.94 (5.77x) |
| Any MaxInt64Value WKT JSON parse | 623.93 | — | — | 4339.37 (6.95x) | 2319.33 (3.72x) |
| Any UInt64Value WKT JSON stringify | 211.03 | — | — | 2187.03 (10.36x) | 1151.70 (5.46x) |
| Any UInt64Value WKT JSON parse | 620.03 | — | — | 4264.87 (6.88x) | 2230.01 (3.60x) |
| Any ZeroUInt64Value WKT JSON stringify | 194.84 | — | — | 1317.05 (6.76x) | 1002.77 (5.15x) |
| Any ZeroUInt64Value WKT JSON parse | 575.90 | — | — | 3189.48 (5.54x) | 2021.24 (3.51x) |
| Any MaxUInt64Value WKT JSON stringify | 220.34 | — | — | 2242.47 (10.18x) | 1163.41 (5.28x) |
| Any MaxUInt64Value WKT JSON parse | 634.86 | — | — | 4336.89 (6.83x) | 2344.22 (3.69x) |
| Any Int32Value WKT JSON stringify | 204.60 | — | — | 2207.32 (10.79x) | 892.59 (4.36x) |
| Any Int32Value WKT JSON parse | 588.21 | — | — | 4103.11 (6.98x) | 1981.46 (3.37x) |
| Any ZeroInt32Value WKT JSON stringify | 199.94 | — | — | 1287.45 (6.44x) | 816.01 (4.08x) |
| Any ZeroInt32Value WKT JSON parse | 581.70 | — | — | 3122.23 (5.37x) | 1900.58 (3.27x) |
| Any NegativeInt32Value WKT JSON stringify | 204.23 | — | — | 2210.71 (10.82x) | 864.22 (4.23x) |
| Any NegativeInt32Value WKT JSON parse | 587.69 | — | — | 4115.05 (7.00x) | 2041.33 (3.47x) |
| Any MinInt32Value WKT JSON stringify | 207.11 | — | — | 2216.71 (10.70x) | 897.10 (4.33x) |
| Any MinInt32Value WKT JSON parse | 601.89 | — | — | 4168.60 (6.93x) | 2065.38 (3.43x) |
| Any MaxInt32Value WKT JSON stringify | 206.24 | — | — | 2203.76 (10.69x) | 884.23 (4.29x) |
| Any MaxInt32Value WKT JSON parse | 600.85 | — | — | 4179.20 (6.96x) | 2013.54 (3.35x) |
| Any UInt32Value WKT JSON stringify | 209.28 | — | — | 2206.63 (10.54x) | 922.05 (4.41x) |
| Any UInt32Value WKT JSON parse | 593.32 | — | — | 4213.35 (7.10x) | 1964.91 (3.31x) |
| Any ZeroUInt32Value WKT JSON stringify | 205.76 | — | — | 1306.19 (6.35x) | 840.87 (4.09x) |
| Any ZeroUInt32Value WKT JSON parse | 587.18 | — | — | 3214.32 (5.47x) | 1887.76 (3.21x) |
| Any MaxUInt32Value WKT JSON stringify | 211.34 | — | — | 2204.94 (10.43x) | 907.16 (4.29x) |
| Any MaxUInt32Value WKT JSON parse | 606.71 | — | — | 4151.37 (6.84x) | 1951.42 (3.22x) |
| Any BoolValue WKT JSON stringify | 205.07 | — | — | 2147.67 (10.47x) | 832.90 (4.06x) |
| Any BoolValue WKT JSON parse | 539.55 | — | — | 4027.62 (7.46x) | 1712.85 (3.17x) |
| Any FalseBoolValue WKT JSON stringify | 205.71 | — | — | 1289.90 (6.27x) | 788.44 (3.83x) |
| Any FalseBoolValue WKT JSON parse | 540.11 | — | — | 3164.92 (5.86x) | 1661.58 (3.08x) |
| Any StringValue WKT JSON stringify | 231.89 | — | — | 2201.67 (9.49x) | 930.50 (4.01x) |
| Any StringValue WKT JSON parse | 605.24 | — | — | 4056.71 (6.70x) | 1881.26 (3.11x) |
| Any EmptyStringValue WKT JSON stringify | 220.60 | — | — | 1300.73 (5.90x) | 863.32 (3.91x) |
| Any EmptyStringValue WKT JSON parse | 566.16 | — | — | 3205.86 (5.66x) | 1648.98 (2.91x) |
| Any BytesValue WKT JSON stringify | 221.67 | — | — | 2278.42 (10.28x) | 1003.47 (4.53x) |
| Any BytesValue WKT JSON parse | 612.07 | — | — | 4202.82 (6.87x) | 1934.44 (3.16x) |
| Any EmptyBytesValue WKT JSON stringify | 212.79 | — | — | 1286.20 (6.04x) | 857.03 (4.03x) |
| Any EmptyBytesValue WKT JSON parse | 571.21 | — | — | 3219.58 (5.64x) | 1768.61 (3.10x) |
| Nested Any WKT JSON stringify | 352.08 | — | — | 3419.35 (9.71x) | 1668.36 (4.74x) |
| Nested Any WKT JSON parse | 999.25 | — | — | 6040.11 (6.04x) | 3525.47 (3.53x) |
| Duration JSON stringify | 64.48 | — | — | 1529.85 (23.73x) | 427.64 (6.63x) |
| Duration JSON parse | 11.31 | — | — | 2299.25 (203.29x) | 418.69 (37.02x) |
| NegativeDuration JSON stringify | 64.71 | — | — | 1596.78 (24.68x) | 479.71 (7.41x) |
| NegativeDuration JSON parse | 11.12 | — | — | 2397.19 (215.57x) | 427.62 (38.46x) |
| FractionalNegativeDuration JSON stringify | 64.80 | — | — | 1534.94 (23.69x) | 466.34 (7.20x) |
| FractionalNegativeDuration JSON parse | 11.07 | — | — | 2294.84 (207.30x) | 410.08 (37.04x) |
| MaxDuration JSON stringify | 53.27 | — | — | 1286.39 (24.15x) | 450.14 (8.45x) |
| MaxDuration JSON parse | 29.22 | — | — | 2225.54 (76.16x) | 435.41 (14.90x) |
| MinDuration JSON stringify | 53.91 | — | — | 1299.92 (24.11x) | 507.65 (9.42x) |
| MinDuration JSON parse | 29.41 | — | — | 2260.36 (76.86x) | 461.32 (15.69x) |
| ZeroDuration JSON stringify | 47.99 | — | — | 1235.98 (25.75x) | 378.58 (7.89x) |
| ZeroDuration JSON parse | 8.78 | — | — | 2123.59 (241.87x) | 354.61 (40.39x) |
| FieldMask JSON stringify | 93.12 | — | — | 1300.77 (13.97x) | 743.21 (7.98x) |
| FieldMask JSON parse | 181.66 | — | — | 2677.59 (14.74x) | 1055.50 (5.81x) |
| EmptyFieldMask JSON stringify | 42.60 | — | — | 926.26 (21.74x) | 237.15 (5.57x) |
| EmptyFieldMask JSON parse | 3.52 | — | — | 1464.48 (416.05x) | 200.10 (56.85x) |
| Timestamp JSON stringify | 129.74 | — | — | 1720.08 (13.26x) | 461.86 (3.56x) |
| Timestamp JSON parse | 57.43 | — | — | 2334.28 (40.65x) | 476.03 (8.29x) |
| PreEpoch Timestamp JSON stringify | 87.62 | — | — | 1592.26 (18.17x) | 464.17 (5.30x) |
| PreEpoch Timestamp JSON parse | 55.35 | — | — | 2323.95 (41.99x) | 450.70 (8.14x) |
| Max Timestamp JSON stringify | 105.47 | — | — | 1748.88 (16.58x) | 470.63 (4.46x) |
| Max Timestamp JSON parse | 65.44 | — | — | 2361.78 (36.09x) | 499.13 (7.63x) |
| Min Timestamp JSON stringify | 119.65 | — | — | 1594.96 (13.33x) | 458.55 (3.83x) |
| Min Timestamp JSON parse | 53.16 | — | — | 2275.07 (42.80x) | 458.50 (8.62x) |
| Empty JSON stringify | 22.90 | — | — | 691.34 (30.19x) | 97.87 (4.27x) |
| Empty JSON parse | 76.70 | — | — | 1089.15 (14.20x) | 238.49 (3.11x) |
| Struct JSON stringify | 259.53 | — | — | 8901.95 (34.30x) | 3919.17 (15.10x) |
| Struct JSON parse | 933.06 | — | — | 16817.20 (18.02x) | 6332.16 (6.79x) |
| Value JSON stringify | 264.54 | — | — | 9758.21 (36.89x) | 4047.94 (15.30x) |
| Value JSON parse | 974.94 | — | — | 17622.80 (18.08x) | 6603.70 (6.77x) |
| ListValue JSON stringify | 194.95 | — | — | 7533.13 (38.64x) | 2646.03 (13.57x) |
| ListValue JSON parse | 731.98 | — | — | 13658.40 (18.66x) | 5290.02 (7.23x) |
| DoubleValue JSON stringify | 97.83 | — | — | 1450.85 (14.83x) | 219.41 (2.24x) |
| DoubleValue JSON parse | 113.52 | — | — | 2081.32 (18.33x) | 323.74 (2.85x) |
| NegativeDoubleValue JSON stringify | 97.79 | — | — | 1452.46 (14.85x) | 208.76 (2.13x) |
| NegativeDoubleValue JSON parse | 113.75 | — | — | 2106.21 (18.52x) | 320.54 (2.82x) |
| ZeroDoubleValue JSON stringify | 54.13 | — | — | 1338.95 (24.74x) | 173.27 (3.20x) |
| ZeroDoubleValue JSON parse | 115.35 | — | — | 1845.63 (16.00x) | 301.21 (2.61x) |
| DoubleValue NaN JSON stringify | 52.58 | — | — | 998.85 (19.00x) | 158.26 (3.01x) |
| DoubleValue NaN JSON parse | 102.35 | — | — | 1697.37 (16.58x) | 301.73 (2.95x) |
| DoubleValue Infinity JSON stringify | 55.74 | — | — | 975.49 (17.50x) | 151.19 (2.71x) |
| DoubleValue Infinity JSON parse | 105.59 | — | — | 1740.29 (16.48x) | 316.60 (3.00x) |
| DoubleValue NegativeInfinity JSON stringify | 57.50 | — | — | 982.71 (17.09x) | 151.71 (2.64x) |
| DoubleValue NegativeInfinity JSON parse | 108.24 | — | — | 1748.25 (16.15x) | 314.72 (2.91x) |
| FloatValue JSON stringify | 103.58 | — | — | 1399.92 (13.52x) | 210.77 (2.03x) |
| FloatValue JSON parse | 112.14 | — | — | 2147.20 (19.15x) | 323.98 (2.89x) |
| NegativeFloatValue JSON stringify | 102.42 | — | — | 1410.96 (13.78x) | 202.34 (1.98x) |
| NegativeFloatValue JSON parse | 113.57 | — | — | 2175.15 (19.15x) | 313.07 (2.76x) |
| ZeroFloatValue JSON stringify | 53.58 | — | — | 1360.86 (25.40x) | 168.47 (3.14x) |
| ZeroFloatValue JSON parse | 114.83 | — | — | 1899.65 (16.54x) | 299.87 (2.61x) |
| FloatValue NaN JSON stringify | 52.78 | — | — | 963.02 (18.25x) | 158.23 (3.00x) |
| FloatValue NaN JSON parse | 102.22 | — | — | 1694.10 (16.57x) | 307.12 (3.00x) |
| FloatValue Infinity JSON stringify | 56.64 | — | — | 976.85 (17.25x) | 159.92 (2.82x) |
| FloatValue Infinity JSON parse | 105.49 | — | — | 1731.52 (16.41x) | 296.32 (2.81x) |
| FloatValue NegativeInfinity JSON stringify | 57.49 | — | — | 968.94 (16.85x) | 147.91 (2.57x) |
| FloatValue NegativeInfinity JSON parse | 107.94 | — | — | 1725.51 (15.99x) | 318.75 (2.95x) |
| Int64Value JSON stringify | 54.06 | — | — | 1012.56 (18.73x) | 304.67 (5.64x) |
| Int64Value JSON parse | 138.30 | — | — | 1982.03 (14.33x) | 518.78 (3.75x) |
| ZeroInt64Value JSON stringify | 44.37 | — | — | 920.05 (20.74x) | 197.99 (4.46x) |
| ZeroInt64Value JSON parse | 102.27 | — | — | 1817.92 (17.78x) | 379.51 (3.71x) |
| NegativeInt64Value JSON stringify | 54.18 | — | — | 999.13 (18.44x) | 305.21 (5.63x) |
| NegativeInt64Value JSON parse | 139.81 | — | — | 1954.23 (13.98x) | 520.61 (3.72x) |
| MinInt64Value JSON stringify | 58.12 | — | — | 986.34 (16.97x) | 323.37 (5.56x) |
| MinInt64Value JSON parse | 148.41 | — | — | 1987.80 (13.39x) | 533.40 (3.59x) |
| MaxInt64Value JSON stringify | 57.62 | — | — | 1001.72 (17.38x) | 321.43 (5.58x) |
| MaxInt64Value JSON parse | 148.27 | — | — | 1997.84 (13.47x) | 523.27 (3.53x) |
| UInt64Value JSON stringify | 53.89 | — | — | 1005.29 (18.65x) | 298.31 (5.54x) |
| UInt64Value JSON parse | 137.59 | — | — | 1929.91 (14.03x) | 514.40 (3.74x) |
| ZeroUInt64Value JSON stringify | 43.32 | — | — | 918.87 (21.21x) | 212.85 (4.91x) |
| ZeroUInt64Value JSON parse | 100.54 | — | — | 1792.33 (17.83x) | 375.79 (3.74x) |
| MaxUInt64Value JSON stringify | 57.75 | — | — | 989.97 (17.14x) | 319.51 (5.53x) |
| MaxUInt64Value JSON parse | 150.22 | — | — | 2014.41 (13.41x) | 528.58 (3.52x) |
| Int32Value JSON stringify | 48.09 | — | — | 945.63 (19.66x) | 159.39 (3.31x) |
| Int32Value JSON parse | 135.15 | — | — | 1927.36 (14.26x) | 336.07 (2.49x) |
| ZeroInt32Value JSON stringify | 47.89 | — | — | 949.65 (19.83x) | 163.63 (3.42x) |
| ZeroInt32Value JSON parse | 129.20 | — | — | 1868.13 (14.46x) | 294.70 (2.28x) |
| NegativeInt32Value JSON stringify | 48.42 | — | — | 958.77 (19.80x) | 154.14 (3.18x) |
| NegativeInt32Value JSON parse | 132.60 | — | — | 1929.83 (14.55x) | 345.51 (2.61x) |
| MinInt32Value JSON stringify | 48.71 | — | — | 962.28 (19.76x) | 162.46 (3.34x) |
| MinInt32Value JSON parse | 143.83 | — | — | 1954.67 (13.59x) | 381.54 (2.65x) |
| MaxInt32Value JSON stringify | 48.29 | — | — | 991.93 (20.54x) | 174.19 (3.61x) |
| MaxInt32Value JSON parse | 145.25 | — | — | 1951.31 (13.43x) | 362.48 (2.50x) |
| UInt32Value JSON stringify | 48.10 | — | — | 924.89 (19.23x) | 165.52 (3.44x) |
| UInt32Value JSON parse | 134.87 | — | — | 1938.94 (14.38x) | 357.26 (2.65x) |
| ZeroUInt32Value JSON stringify | 48.24 | — | — | 929.76 (19.27x) | 160.05 (3.32x) |
| ZeroUInt32Value JSON parse | 129.16 | — | — | 1870.13 (14.48x) | 315.99 (2.45x) |
| MaxUInt32Value JSON stringify | 48.19 | — | — | 904.22 (18.76x) | 180.16 (3.74x) |
| MaxUInt32Value JSON parse | 146.68 | — | — | 1976.06 (13.47x) | 369.87 (2.52x) |
| BoolValue JSON stringify | 45.48 | — | — | 914.85 (20.12x) | 140.89 (3.10x) |
| BoolValue JSON parse | 59.09 | — | — | 1718.78 (29.09x) | 264.01 (4.47x) |
| FalseBoolValue JSON stringify | 45.37 | — | — | 910.63 (20.07x) | 153.92 (3.39x) |
| FalseBoolValue JSON parse | 59.48 | — | — | 1722.50 (28.96x) | 241.19 (4.05x) |
| StringValue JSON stringify | 70.90 | — | — | 1011.90 (14.27x) | 202.42 (2.86x) |
| StringValue JSON parse | 130.60 | — | — | 1818.48 (13.92x) | 344.50 (2.64x) |
| EmptyStringValue JSON stringify | 52.22 | — | — | 941.72 (18.03x) | 218.47 (4.18x) |
| EmptyStringValue JSON parse | 74.39 | — | — | 1782.68 (23.96x) | 254.42 (3.42x) |
| BytesValue JSON stringify | 49.41 | — | — | 958.71 (19.40x) | 253.55 (5.13x) |
| BytesValue JSON parse | 141.50 | — | — | 1976.36 (13.97x) | 384.32 (2.72x) |
| EmptyBytesValue JSON stringify | 43.01 | — | — | 975.59 (22.68x) | 209.48 (4.87x) |
| EmptyBytesValue JSON parse | 82.45 | — | — | 1881.41 (22.82x) | 331.76 (4.02x) |
| TextFormat parse | 838.87 | — | — | 5638.82 (6.72x) | 7972.80 (9.50x) |
| packed bool encode | 2.51 | 2080.07 (828.71x) | 541.44 (215.71x) | 22.55 (8.99x) | 4382.86 (1746.16x) |
| packed bool decode | 271.33 | 2231.36 (8.22x) | 4249.51 (15.66x) | 1110.21 (4.09x) | 2752.23 (10.14x) |
| shuffled large map deterministic binary encode | 36088.85 | — | — | 113660.00 (3.15x) | 453711.77 (12.57x) |
| large map decode | 37416.95 | 129079.96 (3.45x) | 119236.03 (3.19x) | 117596.00 (3.14x) | 297254.28 (7.94x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded zero/positive/integer-negative/fractional-negative/min-max-bound `Duration`, `Struct`, `Value`,
`FieldMask` (non-empty and empty), min/pre/post/max-bound `Timestamp`, `Empty`, min/zero/positive/negative/max `Int64Value`, negative/zero/positive finite `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), negative/zero/positive finite `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), zero/normal/max `UInt64Value`, min/zero/positive/negative/max `Int32Value`, zero/normal/max `UInt32Value`, true/false `BoolValue`, non-empty/empty `StringValue`, base64/empty `BytesValue`, and recursive nested `Any` payloads), direct zero/positive/integer-negative/fractional-negative/min-max-bound Duration and min/pre/post/max-bound Timestamp WKT JSON plus other direct WKT JSON, TextFormat, packed scalars, large bytes,
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
