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

Latest accepted comparison (`/tmp/pbz-compare-empty-value-kinds-json-isolated.log`,
summarized in `/tmp/pbz-summary-empty-value-kinds-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 25.58 | 136.58 (5.34x) | 64.57 (2.52x) | 130.87 (5.12x) | 942.50 (36.85x) |
| binary decode | 126.23 | 312.23 (2.47x) | 304.28 (2.41x) | 267.52 (2.12x) | 1016.69 (8.05x) |
| unknown fields count by number | 4.77 | — | — | 212.20 (44.49x) | — |
| deterministic binary encode | 69.31 | — | — | 147.44 (2.13x) | 1243.83 (17.95x) |
| scalarmix encode | 26.15 | 115.10 (4.40x) | 69.83 (2.67x) | 45.21 (1.73x) | 238.91 (9.14x) |
| scalarmix decode | 55.94 | 162.60 (2.91x) | 209.58 (3.75x) | 106.31 (1.90x) | 362.90 (6.49x) |
| textbytes encode | 12.33 | 91.28 (7.40x) | 43.27 (3.51x) | 147.23 (11.94x) | 182.03 (14.76x) |
| textbytes decode | 62.10 | 479.73 (7.73x) | 309.26 (4.98x) | 202.32 (3.26x) | 813.92 (13.11x) |
| largebytes encode | 23.06 | 3873.88 (167.99x) | 3807.61 (165.12x) | 4097.98 (177.71x) | 4136.50 (179.38x) |
| largebytes decode | 124.96 | 8477.04 (67.84x) | 4550.60 (36.42x) | 4037.22 (32.31x) | 24862.74 (198.97x) |
| presencemix encode | 23.06 | 64.59 (2.80x) | 37.73 (1.64x) | 70.26 (3.05x) | 266.43 (11.55x) |
| presencemix decode | 67.37 | 161.40 (2.40x) | 143.90 (2.14x) | 197.24 (2.93x) | 562.63 (8.35x) |
| complex encode | 64.42 | 164.77 (2.56x) | 117.31 (1.82x) | 214.76 (3.33x) | 1007.27 (15.64x) |
| complex decode | 212.49 | 459.49 (2.16x) | 438.35 (2.06x) | 475.19 (2.24x) | 1594.48 (7.50x) |
| complex deterministic binary encode | 126.79 | — | — | 220.99 (1.74x) | 1279.61 (10.09x) |
| complex JSON stringify | 373.64 | — | — | 7055.90 (18.88x) | 8063.35 (21.58x) |
| complex JSON parse | 2741.95 | — | — | 16728.60 (6.10x) | 10312.43 (3.76x) |
| complex TextFormat format | 354.31 | — | — | 4799.57 (13.55x) | 7063.49 (19.94x) |
| complex TextFormat parse | 2262.98 | — | — | 7971.16 (3.52x) | 11285.83 (4.99x) |
| packed int32 encode | 896.92 | 5393.99 (6.01x) | 3022.54 (3.37x) | 2267.25 (2.53x) | 5705.54 (6.36x) |
| packed int32 decode | 995.18 | 2970.81 (2.99x) | 5444.73 (5.47x) | 1341.20 (1.35x) | 4412.82 (4.43x) |
| JSON stringify | 201.65 | — | — | 4882.19 (24.21x) | 2813.79 (13.95x) |
| JSON parse | 1694.16 | — | — | 10477.80 (6.18x) | 5718.99 (3.38x) |
| Any WKT JSON stringify | 177.21 | — | — | 3039.68 (17.15x) | 1358.80 (7.67x) |
| Any WKT JSON parse | 565.70 | — | — | 4543.15 (8.03x) | 2116.69 (3.74x) |
| Any NegativeDuration WKT JSON stringify | 185.49 | — | — | 3087.98 (16.65x) | 1424.81 (7.68x) |
| Any NegativeDuration WKT JSON parse | 569.07 | — | — | 4730.98 (8.31x) | 2169.81 (3.81x) |
| Any FractionalNegativeDuration WKT JSON stringify | 173.55 | — | — | 3009.50 (17.34x) | 1411.36 (8.13x) |
| Any FractionalNegativeDuration WKT JSON parse | 562.59 | — | — | 4691.64 (8.34x) | 2138.78 (3.80x) |
| Any MaxDuration WKT JSON stringify | 159.17 | — | — | 2769.63 (17.40x) | 1367.18 (8.59x) |
| Any MaxDuration WKT JSON parse | 589.23 | — | — | 4769.59 (8.09x) | 2164.57 (3.67x) |
| Any MinDuration WKT JSON stringify | 160.84 | — | — | 2825.34 (17.57x) | 1394.53 (8.67x) |
| Any MinDuration WKT JSON parse | 588.98 | — | — | 4810.99 (8.17x) | 2145.24 (3.64x) |
| Any ZeroDuration WKT JSON stringify | 144.94 | — | — | 2415.96 (16.67x) | 1255.67 (8.66x) |
| Any ZeroDuration WKT JSON parse | 516.48 | — | — | 3327.35 (6.44x) | 1932.94 (3.74x) |
| Any FieldMask WKT JSON stringify | 290.66 | — | — | 2395.35 (8.24x) | 1764.68 (6.07x) |
| Any FieldMask WKT JSON parse | 779.34 | — | — | 5014.90 (6.43x) | 2960.58 (3.80x) |
| Any EmptyFieldMask WKT JSON stringify | 149.86 | — | — | 1338.58 (8.93x) | 903.76 (6.03x) |
| Any EmptyFieldMask WKT JSON parse | 484.80 | — | — | 3172.11 (6.54x) | 1678.23 (3.46x) |
| Any Timestamp WKT JSON stringify | 248.91 | — | — | 2990.77 (12.02x) | 1346.29 (5.41x) |
| Any Timestamp WKT JSON parse | 628.70 | — | — | 4650.11 (7.40x) | 2291.99 (3.65x) |
| Any PreEpoch Timestamp WKT JSON stringify | 195.33 | — | — | 2957.67 (15.14x) | 1282.00 (6.56x) |
| Any PreEpoch Timestamp WKT JSON parse | 614.59 | — | — | 4652.39 (7.57x) | 2210.86 (3.60x) |
| Any Max Timestamp WKT JSON stringify | 222.50 | — | — | 3048.87 (13.70x) | 1356.86 (6.10x) |
| Any Max Timestamp WKT JSON parse | 645.46 | — | — | 4711.14 (7.30x) | 2306.08 (3.57x) |
| Any Min Timestamp WKT JSON stringify | 228.41 | — | — | 2910.75 (12.74x) | 1283.97 (5.62x) |
| Any Min Timestamp WKT JSON parse | 615.44 | — | — | 4843.68 (7.87x) | 2214.58 (3.60x) |
| Any Empty WKT JSON stringify | 125.97 | — | — | 1327.59 (10.54x) | 759.24 (6.03x) |
| Any Empty WKT JSON parse | 378.32 | — | — | 3226.78 (8.53x) | 1659.52 (4.39x) |
| Any Struct WKT JSON stringify | 790.99 | — | — | 9216.85 (11.65x) | 8584.63 (10.85x) |
| Any Struct WKT JSON parse | 1977.29 | — | — | 17561.80 (8.88x) | 12477.90 (6.31x) |
| Any EmptyStruct WKT JSON stringify | 157.21 | — | — | 2261.27 (14.38x) | 1265.12 (8.05x) |
| Any EmptyStruct WKT JSON parse | 488.89 | — | — | 3474.41 (7.11x) | 2227.55 (4.56x) |
| Any Value WKT JSON stringify | 833.41 | — | — | 9283.72 (11.14x) | 9081.54 (10.90x) |
| Any Value WKT JSON parse | 2049.29 | — | — | 17132.30 (8.36x) | 13021.95 (6.35x) |
| Any NullValue WKT JSON stringify | 165.66 | — | — | 3142.24 (18.97x) | 1271.03 (7.67x) |
| Any NullValue WKT JSON parse | 526.64 | — | — | 6135.06 (11.65x) | 2242.62 (4.26x) |
| Any StringScalarValue WKT JSON stringify | 195.78 | — | — | 3206.52 (16.38x) | 1415.16 (7.23x) |
| Any StringScalarValue WKT JSON parse | 573.01 | — | — | 5374.19 (9.38x) | 2350.43 (4.10x) |
| Any NumberValue WKT JSON stringify | 237.34 | — | — | 3893.01 (16.40x) | 1504.47 (6.34x) |
| Any NumberValue WKT JSON parse | 557.20 | — | — | 5659.01 (10.16x) | 2399.78 (4.31x) |
| Any BoolScalarValue WKT JSON stringify | 165.40 | — | — | 3135.51 (18.96x) | 1253.74 (7.58x) |
| Any BoolScalarValue WKT JSON parse | 522.11 | — | — | 5315.12 (10.18x) | 2184.36 (4.18x) |
| Any ListKindValue WKT JSON stringify | 670.26 | — | — | 8752.94 (13.06x) | 6910.48 (10.31x) |
| Any ListKindValue WKT JSON parse | 1582.99 | — | — | 15368.00 (9.71x) | 10453.67 (6.60x) |
| Any EmptyStructKindValue WKT JSON stringify | 186.78 | — | — | 4052.65 (21.70x) | 1995.60 (10.68x) |
| Any EmptyStructKindValue WKT JSON parse | 574.69 | — | — | 8031.20 (13.97x) | 3033.12 (5.28x) |
| Any EmptyListKindValue WKT JSON stringify | 182.87 | — | — | 4030.35 (22.04x) | 1627.10 (8.90x) |
| Any EmptyListKindValue WKT JSON parse | 568.09 | — | — | 6572.36 (11.57x) | 2783.76 (4.90x) |
| Any DoubleValue WKT JSON stringify | 253.39 | — | — | 2873.16 (11.34x) | 1015.66 (4.01x) |
| Any DoubleValue WKT JSON parse | 565.97 | — | — | 4329.12 (7.65x) | 2040.30 (3.60x) |
| Any NegativeDoubleValue WKT JSON stringify | 253.29 | — | — | 2859.58 (11.29x) | 942.65 (3.72x) |
| Any NegativeDoubleValue WKT JSON parse | 566.49 | — | — | 4390.16 (7.75x) | 2000.74 (3.53x) |
| Any ZeroDoubleValue WKT JSON stringify | 205.17 | — | — | 1289.03 (6.28x) | 839.27 (4.09x) |
| Any ZeroDoubleValue WKT JSON parse | 566.14 | — | — | 3208.81 (5.67x) | 1904.94 (3.36x) |
| Any DoubleValue NaN WKT JSON stringify | 199.60 | — | — | 2315.79 (11.60x) | 834.02 (4.18x) |
| Any DoubleValue NaN WKT JSON parse | 561.97 | — | — | 4075.85 (7.25x) | 1900.21 (3.38x) |
| Any DoubleValue Infinity WKT JSON stringify | 208.58 | — | — | 2250.52 (10.79x) | 872.25 (4.18x) |
| Any DoubleValue Infinity WKT JSON parse | 565.75 | — | — | 4085.90 (7.22x) | 1949.82 (3.45x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 206.88 | — | — | 2245.35 (10.85x) | 840.18 (4.06x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 567.92 | — | — | 4131.33 (7.27x) | 1980.41 (3.49x) |
| Any FloatValue WKT JSON stringify | 260.55 | — | — | 2785.50 (10.69x) | 939.58 (3.61x) |
| Any FloatValue WKT JSON parse | 563.66 | — | — | 4320.32 (7.66x) | 1923.35 (3.41x) |
| Any NegativeFloatValue WKT JSON stringify | 260.99 | — | — | 2788.61 (10.68x) | 919.63 (3.52x) |
| Any NegativeFloatValue WKT JSON parse | 564.83 | — | — | 4355.06 (7.71x) | 1945.97 (3.45x) |
| Any ZeroFloatValue WKT JSON stringify | 206.15 | — | — | 1315.89 (6.38x) | 820.86 (3.98x) |
| Any ZeroFloatValue WKT JSON parse | 564.53 | — | — | 3165.30 (5.61x) | 1883.03 (3.34x) |
| Any FloatValue NaN WKT JSON stringify | 201.08 | — | — | 2225.73 (11.07x) | 830.96 (4.13x) |
| Any FloatValue NaN WKT JSON parse | 561.02 | — | — | 4077.33 (7.27x) | 1841.57 (3.28x) |
| Any FloatValue Infinity WKT JSON stringify | 206.75 | — | — | 2185.87 (10.57x) | 829.02 (4.01x) |
| Any FloatValue Infinity WKT JSON parse | 567.46 | — | — | 4023.15 (7.09x) | 1871.49 (3.30x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 209.61 | — | — | 2159.48 (10.30x) | 827.90 (3.95x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 567.44 | — | — | 4017.20 (7.08x) | 1912.96 (3.37x) |
| Any Int64Value WKT JSON stringify | 206.07 | — | — | 2163.37 (10.50x) | 1141.95 (5.54x) |
| Any Int64Value WKT JSON parse | 611.75 | — | — | 4264.14 (6.97x) | 2324.92 (3.80x) |
| Any ZeroInt64Value WKT JSON stringify | 195.56 | — | — | 1259.61 (6.44x) | 1035.11 (5.29x) |
| Any ZeroInt64Value WKT JSON parse | 566.08 | — | — | 3152.07 (5.57x) | 2067.12 (3.65x) |
| Any NegativeInt64Value WKT JSON stringify | 207.22 | — | — | 2164.74 (10.45x) | 1160.49 (5.60x) |
| Any NegativeInt64Value WKT JSON parse | 609.13 | — | — | 4275.63 (7.02x) | 2317.27 (3.80x) |
| Any MinInt64Value WKT JSON stringify | 210.61 | — | — | 2174.53 (10.32x) | 1164.61 (5.53x) |
| Any MinInt64Value WKT JSON parse | 619.04 | — | — | 4302.54 (6.95x) | 2368.76 (3.83x) |
| Any MaxInt64Value WKT JSON stringify | 210.43 | — | — | 2187.74 (10.40x) | 1154.63 (5.49x) |
| Any MaxInt64Value WKT JSON parse | 621.03 | — | — | 4270.89 (6.88x) | 2302.20 (3.71x) |
| Any UInt64Value WKT JSON stringify | 213.86 | — | — | 2149.42 (10.05x) | 1175.75 (5.50x) |
| Any UInt64Value WKT JSON parse | 620.34 | — | — | 4225.28 (6.81x) | 2244.73 (3.62x) |
| Any ZeroUInt64Value WKT JSON stringify | 210.47 | — | — | 1280.41 (6.08x) | 1004.50 (4.77x) |
| Any ZeroUInt64Value WKT JSON parse | 577.92 | — | — | 3220.61 (5.57x) | 2017.81 (3.49x) |
| Any MaxUInt64Value WKT JSON stringify | 225.88 | — | — | 2127.13 (9.42x) | 1180.37 (5.23x) |
| Any MaxUInt64Value WKT JSON parse | 629.08 | — | — | 4374.93 (6.95x) | 2347.19 (3.73x) |
| Any Int32Value WKT JSON stringify | 209.08 | — | — | 2228.13 (10.66x) | 902.87 (4.32x) |
| Any Int32Value WKT JSON parse | 582.00 | — | — | 4072.02 (7.00x) | 1997.23 (3.43x) |
| Any ZeroInt32Value WKT JSON stringify | 208.08 | — | — | 1300.46 (6.25x) | 827.27 (3.98x) |
| Any ZeroInt32Value WKT JSON parse | 576.75 | — | — | 3170.80 (5.50x) | 1923.02 (3.33x) |
| Any NegativeInt32Value WKT JSON stringify | 212.49 | — | — | 2231.56 (10.50x) | 860.96 (4.05x) |
| Any NegativeInt32Value WKT JSON parse | 582.46 | — | — | 4185.89 (7.19x) | 2018.99 (3.47x) |
| Any MinInt32Value WKT JSON stringify | 212.84 | — | — | 2208.76 (10.38x) | 876.90 (4.12x) |
| Any MinInt32Value WKT JSON parse | 595.25 | — | — | 4116.18 (6.92x) | 2070.84 (3.48x) |
| Any MaxInt32Value WKT JSON stringify | 211.20 | — | — | 2231.44 (10.57x) | 871.60 (4.13x) |
| Any MaxInt32Value WKT JSON parse | 596.49 | — | — | 4110.73 (6.89x) | 2033.35 (3.41x) |
| Any UInt32Value WKT JSON stringify | 217.34 | — | — | 2158.62 (9.93x) | 907.30 (4.17x) |
| Any UInt32Value WKT JSON parse | 589.65 | — | — | 4094.50 (6.94x) | 1949.68 (3.31x) |
| Any ZeroUInt32Value WKT JSON stringify | 214.05 | — | — | 1299.20 (6.07x) | 847.06 (3.96x) |
| Any ZeroUInt32Value WKT JSON parse | 584.67 | — | — | 3253.68 (5.56x) | 1897.20 (3.24x) |
| Any MaxUInt32Value WKT JSON stringify | 219.12 | — | — | 2172.19 (9.91x) | 880.97 (4.02x) |
| Any MaxUInt32Value WKT JSON parse | 614.99 | — | — | 4173.01 (6.79x) | 1967.77 (3.20x) |
| Any BoolValue WKT JSON stringify | 209.57 | — | — | 2125.85 (10.14x) | 806.52 (3.85x) |
| Any BoolValue WKT JSON parse | 538.26 | — | — | 4035.60 (7.50x) | 1729.17 (3.21x) |
| Any FalseBoolValue WKT JSON stringify | 209.66 | — | — | 1281.06 (6.11x) | 817.78 (3.90x) |
| Any FalseBoolValue WKT JSON parse | 539.34 | — | — | 3193.75 (5.92x) | 1694.96 (3.14x) |
| Any StringValue WKT JSON stringify | 244.85 | — | — | 2219.91 (9.07x) | 941.24 (3.84x) |
| Any StringValue WKT JSON parse | 602.11 | — | — | 4043.33 (6.72x) | 1907.93 (3.17x) |
| Any EmptyStringValue WKT JSON stringify | 225.34 | — | — | 1297.33 (5.76x) | 864.47 (3.84x) |
| Any EmptyStringValue WKT JSON parse | 562.56 | — | — | 3191.00 (5.67x) | 1683.10 (2.99x) |
| Any BytesValue WKT JSON stringify | 224.78 | — | — | 2242.14 (9.97x) | 966.92 (4.30x) |
| Any BytesValue WKT JSON parse | 610.49 | — | — | 4207.32 (6.89x) | 1972.09 (3.23x) |
| Any EmptyBytesValue WKT JSON stringify | 218.96 | — | — | 1300.01 (5.94x) | 869.11 (3.97x) |
| Any EmptyBytesValue WKT JSON parse | 567.71 | — | — | 3180.69 (5.60x) | 1832.70 (3.23x) |
| Nested Any WKT JSON stringify | 385.68 | — | — | 3426.17 (8.88x) | 1629.56 (4.23x) |
| Nested Any WKT JSON parse | 980.86 | — | — | 5988.25 (6.11x) | 3562.86 (3.63x) |
| Duration JSON stringify | 65.22 | — | — | 1542.37 (23.65x) | 396.09 (6.07x) |
| Duration JSON parse | 12.16 | — | — | 2294.07 (188.66x) | 415.31 (34.15x) |
| NegativeDuration JSON stringify | 65.78 | — | — | 1600.58 (24.33x) | 455.32 (6.92x) |
| NegativeDuration JSON parse | 12.04 | — | — | 2386.40 (198.21x) | 421.26 (34.99x) |
| FractionalNegativeDuration JSON stringify | 65.33 | — | — | 1529.12 (23.41x) | 462.03 (7.07x) |
| FractionalNegativeDuration JSON parse | 12.04 | — | — | 2324.77 (193.09x) | 405.47 (33.68x) |
| MaxDuration JSON stringify | 54.28 | — | — | 1284.31 (23.66x) | 447.48 (8.24x) |
| MaxDuration JSON parse | 29.19 | — | — | 2224.18 (76.20x) | 435.41 (14.92x) |
| MinDuration JSON stringify | 54.67 | — | — | 1281.93 (23.45x) | 484.03 (8.85x) |
| MinDuration JSON parse | 29.37 | — | — | 2231.21 (75.97x) | 434.41 (14.79x) |
| ZeroDuration JSON stringify | 47.84 | — | — | 1246.38 (26.05x) | 362.39 (7.58x) |
| ZeroDuration JSON parse | 8.79 | — | — | 2159.87 (245.72x) | 345.38 (39.29x) |
| FieldMask JSON stringify | 93.78 | — | — | 1296.54 (13.83x) | 746.83 (7.96x) |
| FieldMask JSON parse | 181.48 | — | — | 2655.87 (14.63x) | 1041.04 (5.74x) |
| EmptyFieldMask JSON stringify | 43.19 | — | — | 928.98 (21.51x) | 233.07 (5.40x) |
| EmptyFieldMask JSON parse | 3.52 | — | — | 1440.23 (409.16x) | 204.97 (58.23x) |
| Timestamp JSON stringify | 130.22 | — | — | 1750.87 (13.45x) | 472.26 (3.63x) |
| Timestamp JSON parse | 56.91 | — | — | 2352.33 (41.33x) | 483.36 (8.49x) |
| PreEpoch Timestamp JSON stringify | 86.95 | — | — | 1611.15 (18.53x) | 473.21 (5.44x) |
| PreEpoch Timestamp JSON parse | 54.86 | — | — | 2276.29 (41.49x) | 462.58 (8.43x) |
| Max Timestamp JSON stringify | 103.64 | — | — | 1782.86 (17.20x) | 471.91 (4.55x) |
| Max Timestamp JSON parse | 64.33 | — | — | 2372.98 (36.89x) | 507.09 (7.88x) |
| Min Timestamp JSON stringify | 118.69 | — | — | 1624.73 (13.69x) | 465.90 (3.93x) |
| Min Timestamp JSON parse | 52.78 | — | — | 2266.02 (42.93x) | 467.82 (8.86x) |
| Empty JSON stringify | 22.85 | — | — | 683.48 (29.91x) | 109.25 (4.78x) |
| Empty JSON parse | 73.89 | — | — | 1118.63 (15.14x) | 257.69 (3.49x) |
| Struct JSON stringify | 273.37 | — | — | 8912.94 (32.60x) | 3903.25 (14.28x) |
| Struct JSON parse | 950.74 | — | — | 16830.10 (17.70x) | 6272.22 (6.60x) |
| EmptyStruct JSON stringify | 44.37 | — | — | 997.83 (22.49x) | 406.67 (9.17x) |
| EmptyStruct JSON parse | 97.16 | — | — | 3334.20 (34.32x) | 413.56 (4.26x) |
| Value JSON stringify | 278.23 | — | — | 9935.25 (35.71x) | 4046.22 (14.54x) |
| Value JSON parse | 947.35 | — | — | 17858.80 (18.85x) | 6584.11 (6.95x) |
| NullValue JSON stringify | 42.33 | — | — | 1705.07 (40.28x) | 240.13 (5.67x) |
| NullValue JSON parse | 63.29 | — | — | 3747.80 (59.22x) | 381.66 (6.03x) |
| StringScalarValue JSON stringify | 54.78 | — | — | 1889.08 (34.48x) | 275.36 (5.03x) |
| StringScalarValue JSON parse | 125.78 | — | — | 3093.79 (24.60x) | 493.52 (3.92x) |
| NumberValue JSON stringify | 112.53 | — | — | 2353.98 (20.92x) | 333.33 (2.96x) |
| NumberValue JSON parse | 121.86 | — | — | 3331.18 (27.34x) | 455.93 (3.74x) |
| BoolScalarValue JSON stringify | 42.13 | — | — | 1727.31 (41.00x) | 220.74 (5.24x) |
| BoolScalarValue JSON parse | 59.12 | — | — | 2954.32 (49.97x) | 363.73 (6.15x) |
| ListKindValue JSON stringify | 215.10 | — | — | 9276.45 (43.13x) | 2866.18 (13.32x) |
| ListKindValue JSON parse | 751.14 | — | — | 15978.30 (21.27x) | 5609.94 (7.47x) |
| EmptyStructKindValue JSON stringify | 45.19 | — | — | 2692.70 (59.59x) | 642.80 (14.22x) |
| EmptyStructKindValue JSON parse | 107.62 | — | — | 5846.50 (54.33x) | 849.58 (7.89x) |
| EmptyListKindValue JSON stringify | 43.75 | — | — | 2631.45 (60.15x) | 383.99 (8.78x) |
| EmptyListKindValue JSON parse | 144.44 | — | — | 5699.04 (39.46x) | 683.72 (4.73x) |
| ListValue JSON stringify | 211.15 | — | — | 7544.37 (35.73x) | 2668.44 (12.64x) |
| ListValue JSON parse | 751.65 | — | — | 13577.20 (18.06x) | 5272.37 (7.01x) |
| EmptyListValue JSON stringify | 41.27 | — | — | 1000.75 (24.25x) | 230.97 (5.60x) |
| EmptyListValue JSON parse | 137.66 | — | — | 3259.30 (23.68x) | 389.56 (2.83x) |
| DoubleValue JSON stringify | 99.30 | — | — | 1479.99 (14.90x) | 228.25 (2.30x) |
| DoubleValue JSON parse | 114.15 | — | — | 2132.67 (18.68x) | 338.55 (2.97x) |
| NegativeDoubleValue JSON stringify | 99.25 | — | — | 1471.80 (14.83x) | 237.87 (2.40x) |
| NegativeDoubleValue JSON parse | 114.46 | — | — | 2123.06 (18.55x) | 320.23 (2.80x) |
| ZeroDoubleValue JSON stringify | 53.02 | — | — | 1367.79 (25.80x) | 161.80 (3.05x) |
| ZeroDoubleValue JSON parse | 117.02 | — | — | 1853.90 (15.84x) | 309.76 (2.65x) |
| DoubleValue NaN JSON stringify | 52.73 | — | — | 1004.37 (19.05x) | 156.97 (2.98x) |
| DoubleValue NaN JSON parse | 101.74 | — | — | 1731.46 (17.02x) | 329.88 (3.24x) |
| DoubleValue Infinity JSON stringify | 56.53 | — | — | 975.43 (17.26x) | 152.98 (2.71x) |
| DoubleValue Infinity JSON parse | 105.38 | — | — | 1730.37 (16.42x) | 335.29 (3.18x) |
| DoubleValue NegativeInfinity JSON stringify | 57.72 | — | — | 969.18 (16.79x) | 148.85 (2.58x) |
| DoubleValue NegativeInfinity JSON parse | 107.77 | — | — | 1735.15 (16.10x) | 326.79 (3.03x) |
| FloatValue JSON stringify | 103.82 | — | — | 1399.03 (13.48x) | 214.83 (2.07x) |
| FloatValue JSON parse | 114.04 | — | — | 2108.17 (18.49x) | 353.49 (3.10x) |
| NegativeFloatValue JSON stringify | 104.04 | — | — | 1403.97 (13.49x) | 206.03 (1.98x) |
| NegativeFloatValue JSON parse | 114.74 | — | — | 2123.00 (18.50x) | 338.97 (2.95x) |
| ZeroFloatValue JSON stringify | 53.26 | — | — | 1329.14 (24.96x) | 166.40 (3.12x) |
| ZeroFloatValue JSON parse | 117.05 | — | — | 1871.35 (15.99x) | 294.56 (2.52x) |
| FloatValue NaN JSON stringify | 52.64 | — | — | 953.54 (18.11x) | 148.21 (2.82x) |
| FloatValue NaN JSON parse | 102.83 | — | — | 1675.30 (16.29x) | 301.57 (2.93x) |
| FloatValue Infinity JSON stringify | 55.85 | — | — | 949.80 (17.01x) | 154.84 (2.77x) |
| FloatValue Infinity JSON parse | 105.64 | — | — | 1695.77 (16.05x) | 294.50 (2.79x) |
| FloatValue NegativeInfinity JSON stringify | 57.40 | — | — | 932.28 (16.24x) | 149.58 (2.61x) |
| FloatValue NegativeInfinity JSON parse | 108.31 | — | — | 1696.79 (15.67x) | 320.23 (2.96x) |
| Int64Value JSON stringify | 54.03 | — | — | 976.08 (18.07x) | 310.59 (5.75x) |
| Int64Value JSON parse | 137.83 | — | — | 1969.55 (14.29x) | 510.23 (3.70x) |
| ZeroInt64Value JSON stringify | 43.43 | — | — | 910.55 (20.97x) | 216.51 (4.99x) |
| ZeroInt64Value JSON parse | 103.51 | — | — | 1799.93 (17.39x) | 361.90 (3.50x) |
| NegativeInt64Value JSON stringify | 54.18 | — | — | 985.38 (18.19x) | 308.78 (5.70x) |
| NegativeInt64Value JSON parse | 139.08 | — | — | 1956.91 (14.07x) | 518.05 (3.72x) |
| MinInt64Value JSON stringify | 57.80 | — | — | 986.64 (17.07x) | 324.39 (5.61x) |
| MinInt64Value JSON parse | 149.50 | — | — | 1999.43 (13.37x) | 530.02 (3.55x) |
| MaxInt64Value JSON stringify | 57.71 | — | — | 1000.21 (17.33x) | 318.39 (5.52x) |
| MaxInt64Value JSON parse | 147.69 | — | — | 2005.70 (13.58x) | 516.15 (3.49x) |
| UInt64Value JSON stringify | 53.74 | — | — | 993.13 (18.48x) | 302.06 (5.62x) |
| UInt64Value JSON parse | 137.48 | — | — | 1937.13 (14.09x) | 499.98 (3.64x) |
| ZeroUInt64Value JSON stringify | 42.84 | — | — | 912.38 (21.30x) | 195.06 (4.55x) |
| ZeroUInt64Value JSON parse | 101.11 | — | — | 1781.42 (17.62x) | 364.77 (3.61x) |
| MaxUInt64Value JSON stringify | 57.13 | — | — | 974.09 (17.05x) | 330.66 (5.79x) |
| MaxUInt64Value JSON parse | 150.63 | — | — | 1983.41 (13.17x) | 513.17 (3.41x) |
| Int32Value JSON stringify | 48.09 | — | — | 947.42 (19.70x) | 171.26 (3.56x) |
| Int32Value JSON parse | 133.74 | — | — | 1882.35 (14.07x) | 341.45 (2.55x) |
| ZeroInt32Value JSON stringify | 48.44 | — | — | 950.84 (19.63x) | 160.89 (3.32x) |
| ZeroInt32Value JSON parse | 128.69 | — | — | 1855.83 (14.42x) | 314.58 (2.44x) |
| NegativeInt32Value JSON stringify | 48.15 | — | — | 970.55 (20.16x) | 162.84 (3.38x) |
| NegativeInt32Value JSON parse | 130.63 | — | — | 1893.35 (14.49x) | 339.53 (2.60x) |
| MinInt32Value JSON stringify | 48.37 | — | — | 981.41 (20.29x) | 175.17 (3.62x) |
| MinInt32Value JSON parse | 141.88 | — | — | 1920.52 (13.54x) | 379.24 (2.67x) |
| MaxInt32Value JSON stringify | 48.30 | — | — | 946.16 (19.59x) | 161.90 (3.35x) |
| MaxInt32Value JSON parse | 145.33 | — | — | 1927.22 (13.26x) | 372.22 (2.56x) |
| UInt32Value JSON stringify | 47.58 | — | — | 907.87 (19.08x) | 175.34 (3.69x) |
| UInt32Value JSON parse | 133.75 | — | — | 1890.64 (14.14x) | 353.77 (2.65x) |
| ZeroUInt32Value JSON stringify | 48.42 | — | — | 909.37 (18.78x) | 161.36 (3.33x) |
| ZeroUInt32Value JSON parse | 128.84 | — | — | 1853.40 (14.39x) | 297.78 (2.31x) |
| MaxUInt32Value JSON stringify | 48.33 | — | — | 936.30 (19.37x) | 192.33 (3.98x) |
| MaxUInt32Value JSON parse | 145.19 | — | — | 1957.14 (13.48x) | 374.94 (2.58x) |
| BoolValue JSON stringify | 46.43 | — | — | 897.99 (19.34x) | 149.44 (3.22x) |
| BoolValue JSON parse | 54.79 | — | — | 1705.94 (31.14x) | 247.63 (4.52x) |
| FalseBoolValue JSON stringify | 46.27 | — | — | 894.34 (19.33x) | 156.46 (3.38x) |
| FalseBoolValue JSON parse | 55.17 | — | — | 1703.68 (30.88x) | 246.40 (4.47x) |
| StringValue JSON stringify | 57.99 | — | — | 985.78 (17.00x) | 210.57 (3.63x) |
| StringValue JSON parse | 132.36 | — | — | 1823.33 (13.78x) | 379.02 (2.86x) |
| EmptyStringValue JSON stringify | 51.94 | — | — | 936.63 (18.03x) | 205.07 (3.95x) |
| EmptyStringValue JSON parse | 74.27 | — | — | 1782.44 (24.00x) | 272.65 (3.67x) |
| BytesValue JSON stringify | 49.68 | — | — | 957.51 (19.27x) | 245.92 (4.95x) |
| BytesValue JSON parse | 137.90 | — | — | 1965.21 (14.25x) | 374.47 (2.72x) |
| EmptyBytesValue JSON stringify | 42.82 | — | — | 953.93 (22.28x) | 215.01 (5.02x) |
| EmptyBytesValue JSON parse | 77.88 | — | — | 1888.55 (24.25x) | 339.77 (4.36x) |
| TextFormat format | 234.76 | — | — | 3140.12 (13.38x) | 3152.65 (13.43x) |
| TextFormat parse | 845.78 | — | — | 5571.63 (6.59x) | 8105.51 (9.58x) |
| packed fixed32 encode | 2.76 | 805.89 (291.99x) | 628.47 (227.71x) | 90.11 (32.65x) | 568.51 (205.98x) |
| packed fixed32 decode | 7.02 | 1307.99 (186.32x) | 2819.95 (401.70x) | 103.70 (14.77x) | 1999.66 (284.85x) |
| packed fixed64 encode | 2.26 | 709.48 (313.93x) | 630.84 (279.13x) | 154.66 (68.43x) | 570.53 (252.45x) |
| packed fixed64 decode | 6.89 | 1223.14 (177.52x) | 7412.09 (1075.78x) | 163.65 (23.75x) | 3245.68 (471.07x) |
| packed sfixed32 encode | 2.51 | 704.90 (280.84x) | 628.45 (250.38x) | 90.60 (36.10x) | 568.89 (226.65x) |
| packed sfixed32 decode | 7.30 | 1228.33 (168.26x) | 2828.00 (387.40x) | 97.42 (13.35x) | 1987.29 (272.23x) |
| packed sfixed64 encode | 2.26 | 806.46 (356.84x) | 630.36 (278.92x) | 154.44 (68.33x) | 569.87 (252.15x) |
| packed sfixed64 decode | 7.27 | 1328.39 (182.72x) | 7318.20 (1006.63x) | 161.12 (22.16x) | 2755.21 (378.98x) |
| packed float encode | 2.76 | 826.20 (299.35x) | 629.41 (228.05x) | 90.70 (32.86x) | 565.08 (204.74x) |
| packed float decode | 7.27 | 1307.65 (179.87x) | 2400.00 (330.12x) | 97.41 (13.40x) | 2014.40 (277.08x) |
| packed double encode | 2.26 | 849.63 (375.94x) | 631.31 (279.34x) | 154.44 (68.33x) | 566.90 (250.84x) |
| packed double decode | 7.02 | 1222.55 (174.15x) | 2857.88 (407.11x) | 161.12 (22.95x) | 3241.72 (461.78x) |
| packed uint64 encode | 1833.66 | 6951.27 (3.79x) | 6299.58 (3.44x) | 3131.96 (1.71x) | 6132.60 (3.34x) |
| packed uint64 decode | 2588.14 | 4296.85 (1.66x) | 8620.94 (3.33x) | 4545.31 (1.76x) | 11369.82 (4.39x) |
| packed uint32 encode | 1349.71 | 4766.09 (3.53x) | 4408.26 (3.27x) | 2662.07 (1.97x) | 5421.42 (4.02x) |
| packed uint32 decode | 1880.90 | 3604.82 (1.92x) | 4785.82 (2.54x) | 3255.62 (1.73x) | 8686.06 (4.62x) |
| packed int64 encode | 2082.71 | 15617.23 (7.50x) | 7303.71 (3.51x) | 4172.52 (2.00x) | 7678.58 (3.69x) |
| packed int64 decode | 4451.51 | 5582.64 (1.25x) | 10652.53 (2.39x) | 5990.28 (1.35x) | 14642.13 (3.29x) |
| packed sint32 encode | 1091.03 | 4427.11 (4.06x) | 3606.53 (3.31x) | 2629.77 (2.41x) | 6009.19 (5.51x) |
| packed sint32 decode | 1296.01 | 3857.81 (2.98x) | 4661.98 (3.60x) | 1885.96 (1.46x) | 10730.34 (8.28x) |
| packed sint64 encode | 2495.70 | 7591.60 (3.04x) | 6291.56 (2.52x) | 3418.22 (1.37x) | 6789.39 (2.72x) |
| packed sint64 decode | 2848.29 | 4300.44 (1.51x) | 9776.70 (3.43x) | 4801.24 (1.69x) | 11833.80 (4.15x) |
| packed bool encode | 2.51 | 2080.34 (828.82x) | 539.49 (214.94x) | 22.94 (9.14x) | 4383.38 (1746.37x) |
| packed bool decode | 272.63 | 2057.96 (7.55x) | 3847.07 (14.11x) | 1107.32 (4.06x) | 2724.33 (9.99x) |
| packed enum encode | 570.70 | 4925.00 (8.63x) | 2076.43 (3.64x) | 2089.07 (3.66x) | 5023.77 (8.80x) |
| packed enum decode | 279.05 | 2166.47 (7.76x) | 3902.09 (13.98x) | 1000.35 (3.58x) | 3209.63 (11.50x) |
| large map encode | 5628.73 | 22298.63 (3.96x) | 13193.84 (2.34x) | 35038.60 (6.22x) | 240045.42 (42.65x) |
| shuffled large map deterministic binary encode | 36720.40 | — | — | 111391.00 (3.03x) | 451904.16 (12.31x) |
| large map decode | 37702.54 | 128238.84 (3.40x) | 129771.88 (3.44x) | 117291.00 (3.11x) | 295155.91 (7.83x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded zero/positive/integer-negative/fractional-negative/min-max-bound `Duration`, non-empty and empty `Struct`, object/list/scalar `Value` (including empty object/list kinds),
`FieldMask` (non-empty and empty), min/pre/post/max-bound `Timestamp`, `Empty`, min/zero/positive/negative/max `Int64Value`, negative/zero/positive finite `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), negative/zero/positive finite `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), zero/normal/max `UInt64Value`, min/zero/positive/negative/max `Int32Value`, zero/normal/max `UInt32Value`, true/false `BoolValue`, non-empty/empty `StringValue`, base64/empty `BytesValue`, and recursive nested `Any` payloads), direct zero/positive/integer-negative/fractional-negative/min-max-bound Duration and min/pre/post/max-bound Timestamp WKT JSON plus other direct WKT JSON, including empty `Struct` and empty `ListValue`, TextFormat, packed scalars, large bytes,
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
