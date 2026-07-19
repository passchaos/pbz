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

Latest accepted comparison (`/tmp/pbz-compare-list-kind-value-json-isolated.log`,
summarized in `/tmp/pbz-summary-list-kind-value-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 23.43 | 127.03 (5.42x) | 62.09 (2.65x) | 134.00 (5.72x) | 957.26 (40.86x) |
| binary decode | 130.50 | 306.42 (2.35x) | 300.33 (2.30x) | 269.91 (2.07x) | 1058.70 (8.11x) |
| unknown fields count by number | 5.02 | — | — | 179.78 (35.81x) | — |
| deterministic binary encode | 67.31 | — | — | 156.87 (2.33x) | 1315.70 (19.55x) |
| scalarmix encode | 26.94 | 114.51 (4.25x) | 68.69 (2.55x) | 45.84 (1.70x) | 239.48 (8.89x) |
| scalarmix decode | 50.76 | 163.00 (3.21x) | 207.80 (4.09x) | 113.92 (2.24x) | 367.27 (7.24x) |
| textbytes encode | 13.29 | 91.15 (6.86x) | 43.64 (3.28x) | 150.42 (11.32x) | 171.54 (12.91x) |
| textbytes decode | 61.78 | 476.52 (7.71x) | 304.83 (4.93x) | 206.34 (3.34x) | 858.56 (13.90x) |
| largebytes encode | 25.81 | 3875.57 (150.16x) | 3798.18 (147.16x) | 3890.27 (150.73x) | 4129.26 (159.99x) |
| largebytes decode | 125.06 | 8660.48 (69.25x) | 4534.41 (36.26x) | 4214.31 (33.70x) | 24716.78 (197.64x) |
| presencemix encode | 23.06 | 65.20 (2.83x) | 38.37 (1.66x) | 70.16 (3.04x) | 260.39 (11.29x) |
| presencemix decode | 67.09 | 165.22 (2.46x) | 136.96 (2.04x) | 197.23 (2.94x) | 568.10 (8.47x) |
| complex encode | 68.12 | 166.37 (2.44x) | 115.67 (1.70x) | 205.58 (3.02x) | 982.59 (14.42x) |
| complex decode | 225.23 | 462.59 (2.05x) | 418.33 (1.86x) | 489.15 (2.17x) | 1591.77 (7.07x) |
| complex deterministic binary encode | 129.71 | — | — | 220.19 (1.70x) | 1287.15 (9.92x) |
| complex JSON stringify | 373.95 | — | — | 7007.34 (18.74x) | 7618.70 (20.37x) |
| complex JSON parse | 2701.59 | — | — | 16772.50 (6.21x) | 10545.91 (3.90x) |
| complex TextFormat format | 343.28 | — | — | 4755.94 (13.85x) | 6727.05 (19.60x) |
| complex TextFormat parse | 2116.92 | — | — | 7880.66 (3.72x) | 11303.03 (5.34x) |
| packed int32 encode | 895.80 | 5388.79 (6.02x) | 3049.47 (3.40x) | 2208.65 (2.47x) | 5713.04 (6.38x) |
| packed int32 decode | 1029.18 | 2971.27 (2.89x) | 5468.39 (5.31x) | 1341.81 (1.30x) | 4380.03 (4.26x) |
| JSON stringify | 202.97 | — | — | 4881.85 (24.05x) | 2778.14 (13.69x) |
| JSON parse | 1691.75 | — | — | 10783.70 (6.37x) | 5711.31 (3.38x) |
| Any WKT JSON stringify | 178.21 | — | — | 3039.60 (17.06x) | 1452.93 (8.15x) |
| Any WKT JSON parse | 587.18 | — | — | 4642.12 (7.91x) | 2125.61 (3.62x) |
| Any NegativeDuration WKT JSON stringify | 185.54 | — | — | 3098.60 (16.70x) | 1453.17 (7.83x) |
| Any NegativeDuration WKT JSON parse | 592.59 | — | — | 4715.98 (7.96x) | 2195.07 (3.70x) |
| Any FractionalNegativeDuration WKT JSON stringify | 174.85 | — | — | 3054.61 (17.47x) | 1389.84 (7.95x) |
| Any FractionalNegativeDuration WKT JSON parse | 583.71 | — | — | 4707.56 (8.06x) | 2131.97 (3.65x) |
| Any MaxDuration WKT JSON stringify | 161.47 | — | — | 2686.50 (16.64x) | 1350.15 (8.36x) |
| Any MaxDuration WKT JSON parse | 613.49 | — | — | 4600.60 (7.50x) | 2147.71 (3.50x) |
| Any MinDuration WKT JSON stringify | 163.24 | — | — | 2710.71 (16.61x) | 1410.06 (8.64x) |
| Any MinDuration WKT JSON parse | 615.43 | — | — | 4651.14 (7.56x) | 2115.73 (3.44x) |
| Any ZeroDuration WKT JSON stringify | 145.00 | — | — | 1281.83 (8.84x) | 1261.10 (8.70x) |
| Any ZeroDuration WKT JSON parse | 538.66 | — | — | 3302.58 (6.13x) | 1959.46 (3.64x) |
| Any FieldMask WKT JSON stringify | 287.80 | — | — | 2450.01 (8.51x) | 1807.98 (6.28x) |
| Any FieldMask WKT JSON parse | 816.90 | — | — | 4829.27 (5.91x) | 3000.24 (3.67x) |
| Any EmptyFieldMask WKT JSON stringify | 151.89 | — | — | 1285.37 (8.46x) | 908.97 (5.98x) |
| Any EmptyFieldMask WKT JSON parse | 510.51 | — | — | 3203.29 (6.27x) | 1650.91 (3.23x) |
| Any Timestamp WKT JSON stringify | 246.58 | — | — | 2949.56 (11.96x) | 1366.39 (5.54x) |
| Any Timestamp WKT JSON parse | 655.89 | — | — | 4641.35 (7.08x) | 2301.50 (3.51x) |
| Any PreEpoch Timestamp WKT JSON stringify | 197.47 | — | — | 2855.76 (14.46x) | 1310.94 (6.64x) |
| Any PreEpoch Timestamp WKT JSON parse | 640.16 | — | — | 4656.66 (7.27x) | 2239.90 (3.50x) |
| Any Max Timestamp WKT JSON stringify | 219.52 | — | — | 2986.44 (13.60x) | 1327.92 (6.05x) |
| Any Max Timestamp WKT JSON parse | 671.44 | — | — | 4748.29 (7.07x) | 2307.24 (3.44x) |
| Any Min Timestamp WKT JSON stringify | 230.41 | — | — | 2829.06 (12.28x) | 1285.40 (5.58x) |
| Any Min Timestamp WKT JSON parse | 638.25 | — | — | 4672.41 (7.32x) | 2213.25 (3.47x) |
| Any Empty WKT JSON stringify | 122.12 | — | — | 1275.67 (10.45x) | 692.84 (5.67x) |
| Any Empty WKT JSON parse | 393.44 | — | — | 3120.57 (7.93x) | 1617.46 (4.11x) |
| Any Struct WKT JSON stringify | 776.97 | — | — | 8933.07 (11.50x) | 8637.71 (11.12x) |
| Any Struct WKT JSON parse | 2012.12 | — | — | 16700.30 (8.30x) | 12570.53 (6.25x) |
| Any EmptyStruct WKT JSON stringify | 157.14 | — | — | 1286.29 (8.19x) | 1382.83 (8.80x) |
| Any EmptyStruct WKT JSON parse | 518.11 | — | — | 3319.04 (6.41x) | 2319.12 (4.48x) |
| Any Value WKT JSON stringify | 800.56 | — | — | 8895.13 (11.11x) | 8913.34 (11.13x) |
| Any Value WKT JSON parse | 2097.87 | — | — | 17014.10 (8.11x) | 13113.45 (6.25x) |
| Any NullValue WKT JSON stringify | 161.92 | — | — | 3135.32 (19.36x) | 1237.65 (7.64x) |
| Any NullValue WKT JSON parse | 535.43 | — | — | 6155.84 (11.50x) | 2237.72 (4.18x) |
| Any StringScalarValue WKT JSON stringify | 196.02 | — | — | 3168.56 (16.16x) | 1409.23 (7.19x) |
| Any StringScalarValue WKT JSON parse | 589.16 | — | — | 5299.66 (9.00x) | 2330.27 (3.96x) |
| Any NumberValue WKT JSON stringify | 236.93 | — | — | 3827.51 (16.15x) | 1486.53 (6.27x) |
| Any NumberValue WKT JSON parse | 568.56 | — | — | 5629.05 (9.90x) | 2387.43 (4.20x) |
| Any BoolScalarValue WKT JSON stringify | 163.57 | — | — | 3097.26 (18.94x) | 1248.92 (7.64x) |
| Any BoolScalarValue WKT JSON parse | 535.01 | — | — | 5258.86 (9.83x) | 2148.63 (4.02x) |
| Any ListKindValue WKT JSON stringify | 614.83 | — | — | 8525.39 (13.87x) | 6952.65 (11.31x) |
| Any ListKindValue WKT JSON parse | 1600.96 | — | — | 15512.10 (9.69x) | 10481.57 (6.55x) |
| Any DoubleValue WKT JSON stringify | 253.98 | — | — | 2858.89 (11.26x) | 969.33 (3.82x) |
| Any DoubleValue WKT JSON parse | 590.75 | — | — | 4431.04 (7.50x) | 2063.74 (3.49x) |
| Any NegativeDoubleValue WKT JSON stringify | 254.31 | — | — | 2873.29 (11.30x) | 967.25 (3.80x) |
| Any NegativeDoubleValue WKT JSON parse | 590.72 | — | — | 4395.01 (7.44x) | 2035.75 (3.45x) |
| Any ZeroDoubleValue WKT JSON stringify | 203.01 | — | — | 1301.45 (6.41x) | 855.76 (4.22x) |
| Any ZeroDoubleValue WKT JSON parse | 591.42 | — | — | 3161.62 (5.35x) | 1973.05 (3.34x) |
| Any DoubleValue NaN WKT JSON stringify | 199.37 | — | — | 2325.19 (11.66x) | 834.62 (4.19x) |
| Any DoubleValue NaN WKT JSON parse | 585.76 | — | — | 4120.86 (7.04x) | 1974.14 (3.37x) |
| Any DoubleValue Infinity WKT JSON stringify | 204.74 | — | — | 2300.29 (11.24x) | 863.25 (4.22x) |
| Any DoubleValue Infinity WKT JSON parse | 591.85 | — | — | 4092.46 (6.91x) | 1955.36 (3.30x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 206.79 | — | — | 2228.55 (10.78x) | 861.09 (4.16x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 595.24 | — | — | 4049.87 (6.80x) | 1954.21 (3.28x) |
| Any FloatValue WKT JSON stringify | 260.82 | — | — | 2774.30 (10.64x) | 979.55 (3.76x) |
| Any FloatValue WKT JSON parse | 593.61 | — | — | 4380.52 (7.38x) | 1977.93 (3.33x) |
| Any NegativeFloatValue WKT JSON stringify | 261.72 | — | — | 3206.43 (12.25x) | 925.95 (3.54x) |
| Any NegativeFloatValue WKT JSON parse | 594.37 | — | — | 5762.47 (9.70x) | 1991.56 (3.35x) |
| Any ZeroFloatValue WKT JSON stringify | 213.65 | — | — | 1343.39 (6.29x) | 852.96 (3.99x) |
| Any ZeroFloatValue WKT JSON parse | 603.88 | — | — | 3261.86 (5.40x) | 1883.75 (3.12x) |
| Any FloatValue NaN WKT JSON stringify | 213.71 | — | — | 2780.32 (13.01x) | 829.50 (3.88x) |
| Any FloatValue NaN WKT JSON parse | 588.20 | — | — | 4425.49 (7.52x) | 1888.09 (3.21x) |
| Any FloatValue Infinity WKT JSON stringify | 207.81 | — | — | 2360.26 (11.36x) | 828.22 (3.99x) |
| Any FloatValue Infinity WKT JSON parse | 592.02 | — | — | 4213.53 (7.12x) | 1949.78 (3.29x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 208.27 | — | — | 2321.26 (11.15x) | 853.40 (4.10x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 597.10 | — | — | 4353.04 (7.29x) | 1946.93 (3.26x) |
| Any Int64Value WKT JSON stringify | 207.64 | — | — | 2282.12 (10.99x) | 1170.44 (5.64x) |
| Any Int64Value WKT JSON parse | 639.48 | — | — | 4393.99 (6.87x) | 2378.05 (3.72x) |
| Any ZeroInt64Value WKT JSON stringify | 195.90 | — | — | 1340.13 (6.84x) | 1032.15 (5.27x) |
| Any ZeroInt64Value WKT JSON parse | 592.75 | — | — | 3278.28 (5.53x) | 2096.27 (3.54x) |
| Any NegativeInt64Value WKT JSON stringify | 208.77 | — | — | 2294.88 (10.99x) | 1181.34 (5.66x) |
| Any NegativeInt64Value WKT JSON parse | 637.82 | — | — | 4482.34 (7.03x) | 2383.03 (3.74x) |
| Any MinInt64Value WKT JSON stringify | 212.43 | — | — | 2255.29 (10.62x) | 1196.88 (5.63x) |
| Any MinInt64Value WKT JSON parse | 647.20 | — | — | 4349.19 (6.72x) | 2468.95 (3.81x) |
| Any MaxInt64Value WKT JSON stringify | 211.71 | — | — | 2248.25 (10.62x) | 1173.91 (5.54x) |
| Any MaxInt64Value WKT JSON parse | 650.20 | — | — | 4334.37 (6.67x) | 2376.63 (3.66x) |
| Any UInt64Value WKT JSON stringify | 216.92 | — | — | 2217.58 (10.22x) | 1183.47 (5.46x) |
| Any UInt64Value WKT JSON parse | 644.16 | — | — | 4230.61 (6.57x) | 2282.65 (3.54x) |
| Any ZeroUInt64Value WKT JSON stringify | 203.90 | — | — | 1316.03 (6.45x) | 1001.52 (4.91x) |
| Any ZeroUInt64Value WKT JSON parse | 599.08 | — | — | 3170.19 (5.29x) | 2079.18 (3.47x) |
| Any MaxUInt64Value WKT JSON stringify | 221.82 | — | — | 2181.03 (9.83x) | 1162.59 (5.24x) |
| Any MaxUInt64Value WKT JSON parse | 657.96 | — | — | 4265.69 (6.48x) | 2360.87 (3.59x) |
| Any Int32Value WKT JSON stringify | 207.79 | — | — | 2245.53 (10.81x) | 899.04 (4.33x) |
| Any Int32Value WKT JSON parse | 611.99 | — | — | 4077.02 (6.66x) | 2028.65 (3.31x) |
| Any ZeroInt32Value WKT JSON stringify | 207.61 | — | — | 1294.43 (6.23x) | 811.81 (3.91x) |
| Any ZeroInt32Value WKT JSON parse | 604.88 | — | — | 3191.09 (5.28x) | 1884.94 (3.12x) |
| Any NegativeInt32Value WKT JSON stringify | 214.90 | — | — | 2262.99 (10.53x) | 860.32 (4.00x) |
| Any NegativeInt32Value WKT JSON parse | 609.88 | — | — | 4163.80 (6.83x) | 2037.70 (3.34x) |
| Any MinInt32Value WKT JSON stringify | 215.23 | — | — | 2227.03 (10.35x) | 895.40 (4.16x) |
| Any MinInt32Value WKT JSON parse | 622.06 | — | — | 4182.60 (6.72x) | 2126.36 (3.42x) |
| Any MaxInt32Value WKT JSON stringify | 211.24 | — | — | 2242.06 (10.61x) | 868.92 (4.11x) |
| Any MaxInt32Value WKT JSON parse | 624.08 | — | — | 4146.32 (6.64x) | 1997.93 (3.20x) |
| Any UInt32Value WKT JSON stringify | 219.08 | — | — | 2154.72 (9.84x) | 879.60 (4.01x) |
| Any UInt32Value WKT JSON parse | 614.64 | — | — | 4133.92 (6.73x) | 2006.60 (3.26x) |
| Any ZeroUInt32Value WKT JSON stringify | 216.36 | — | — | 1305.19 (6.03x) | 817.17 (3.78x) |
| Any ZeroUInt32Value WKT JSON parse | 609.03 | — | — | 3184.62 (5.23x) | 1877.35 (3.08x) |
| Any MaxUInt32Value WKT JSON stringify | 221.68 | — | — | 2197.80 (9.91x) | 871.76 (3.93x) |
| Any MaxUInt32Value WKT JSON parse | 629.83 | — | — | 4175.30 (6.63x) | 2011.71 (3.19x) |
| Any BoolValue WKT JSON stringify | 213.25 | — | — | 2150.76 (10.09x) | 849.11 (3.98x) |
| Any BoolValue WKT JSON parse | 568.82 | — | — | 4007.28 (7.04x) | 1731.01 (3.04x) |
| Any FalseBoolValue WKT JSON stringify | 212.08 | — | — | 1287.14 (6.07x) | 811.56 (3.83x) |
| Any FalseBoolValue WKT JSON parse | 569.99 | — | — | 3181.02 (5.58x) | 1656.74 (2.91x) |
| Any StringValue WKT JSON stringify | 243.97 | — | — | 2277.10 (9.33x) | 937.56 (3.84x) |
| Any StringValue WKT JSON parse | 627.02 | — | — | 4055.47 (6.47x) | 1885.50 (3.01x) |
| Any EmptyStringValue WKT JSON stringify | 224.99 | — | — | 1279.76 (5.69x) | 880.06 (3.91x) |
| Any EmptyStringValue WKT JSON parse | 589.00 | — | — | 3144.30 (5.34x) | 1666.69 (2.83x) |
| Any BytesValue WKT JSON stringify | 225.45 | — | — | 2326.35 (10.32x) | 953.09 (4.23x) |
| Any BytesValue WKT JSON parse | 637.74 | — | — | 4243.02 (6.65x) | 1952.09 (3.06x) |
| Any EmptyBytesValue WKT JSON stringify | 225.66 | — | — | 1289.69 (5.72x) | 860.33 (3.81x) |
| Any EmptyBytesValue WKT JSON parse | 604.69 | — | — | 3144.43 (5.20x) | 1843.94 (3.05x) |
| Nested Any WKT JSON stringify | 399.42 | — | — | 3433.91 (8.60x) | 1650.50 (4.13x) |
| Nested Any WKT JSON parse | 1039.91 | — | — | 6191.76 (5.95x) | 3597.09 (3.46x) |
| Duration JSON stringify | 65.17 | — | — | 1569.90 (24.09x) | 378.66 (5.81x) |
| Duration JSON parse | 12.23 | — | — | 2308.45 (188.75x) | 435.69 (35.62x) |
| NegativeDuration JSON stringify | 65.44 | — | — | 1625.16 (24.83x) | 465.86 (7.12x) |
| NegativeDuration JSON parse | 12.75 | — | — | 2363.10 (185.34x) | 436.00 (34.20x) |
| FractionalNegativeDuration JSON stringify | 65.39 | — | — | 1565.36 (23.94x) | 438.47 (6.71x) |
| FractionalNegativeDuration JSON parse | 12.73 | — | — | 2309.37 (181.41x) | 423.18 (33.24x) |
| MaxDuration JSON stringify | 54.21 | — | — | 1344.56 (24.80x) | 456.56 (8.42x) |
| MaxDuration JSON parse | 29.49 | — | — | 2213.40 (75.06x) | 441.72 (14.98x) |
| MinDuration JSON stringify | 54.79 | — | — | 1349.98 (24.64x) | 454.90 (8.30x) |
| MinDuration JSON parse | 29.76 | — | — | 2224.87 (74.76x) | 433.98 (14.58x) |
| ZeroDuration JSON stringify | 49.17 | — | — | 1280.33 (26.04x) | 399.18 (8.12x) |
| ZeroDuration JSON parse | 8.83 | — | — | 2158.89 (244.49x) | 341.46 (38.67x) |
| FieldMask JSON stringify | 93.38 | — | — | 1330.11 (14.24x) | 749.43 (8.03x) |
| FieldMask JSON parse | 187.08 | — | — | 2626.83 (14.04x) | 1033.84 (5.53x) |
| EmptyFieldMask JSON stringify | 43.82 | — | — | 949.77 (21.67x) | 231.47 (5.28x) |
| EmptyFieldMask JSON parse | 3.57 | — | — | 1442.67 (404.11x) | 207.23 (58.05x) |
| Timestamp JSON stringify | 129.39 | — | — | 1724.19 (13.33x) | 466.62 (3.61x) |
| Timestamp JSON parse | 57.15 | — | — | 2317.61 (40.55x) | 480.48 (8.41x) |
| PreEpoch Timestamp JSON stringify | 85.77 | — | — | 1613.09 (18.81x) | 461.95 (5.39x) |
| PreEpoch Timestamp JSON parse | 54.92 | — | — | 2266.55 (41.27x) | 483.01 (8.79x) |
| Max Timestamp JSON stringify | 103.98 | — | — | 1772.58 (17.05x) | 480.87 (4.62x) |
| Max Timestamp JSON parse | 64.87 | — | — | 2322.17 (35.80x) | 492.85 (7.60x) |
| Min Timestamp JSON stringify | 119.08 | — | — | 1596.14 (13.40x) | 476.04 (4.00x) |
| Min Timestamp JSON parse | 52.77 | — | — | 2248.94 (42.62x) | 475.56 (9.01x) |
| Empty JSON stringify | 22.65 | — | — | 722.85 (31.91x) | 112.64 (4.97x) |
| Empty JSON parse | 73.68 | — | — | 1117.92 (15.17x) | 263.32 (3.57x) |
| Struct JSON stringify | 273.93 | — | — | 9005.09 (32.87x) | 3980.45 (14.53x) |
| Struct JSON parse | 946.94 | — | — | 17036.50 (17.99x) | 6347.90 (6.70x) |
| EmptyStruct JSON stringify | 44.54 | — | — | 1044.25 (23.45x) | 414.75 (9.31x) |
| EmptyStruct JSON parse | 95.10 | — | — | 3369.53 (35.43x) | 441.86 (4.65x) |
| Value JSON stringify | 278.98 | — | — | 9964.42 (35.72x) | 4076.93 (14.61x) |
| Value JSON parse | 963.68 | — | — | 18161.10 (18.85x) | 6733.15 (6.99x) |
| NullValue JSON stringify | 42.45 | — | — | 1794.78 (42.28x) | 239.30 (5.64x) |
| NullValue JSON parse | 64.31 | — | — | 3869.89 (60.18x) | 385.07 (5.99x) |
| StringScalarValue JSON stringify | 55.44 | — | — | 1909.76 (34.45x) | 302.26 (5.45x) |
| StringScalarValue JSON parse | 125.69 | — | — | 3137.69 (24.96x) | 486.11 (3.87x) |
| NumberValue JSON stringify | 112.52 | — | — | 2371.07 (21.07x) | 370.64 (3.29x) |
| NumberValue JSON parse | 122.44 | — | — | 3402.81 (27.79x) | 465.30 (3.80x) |
| BoolScalarValue JSON stringify | 41.98 | — | — | 1748.82 (41.66x) | 240.78 (5.74x) |
| BoolScalarValue JSON parse | 61.65 | — | — | 3020.82 (49.00x) | 375.00 (6.08x) |
| ListKindValue JSON stringify | 208.33 | — | — | 9249.00 (44.40x) | 2911.04 (13.97x) |
| ListKindValue JSON parse | 767.06 | — | — | 16183.40 (21.10x) | 5748.22 (7.49x) |
| ListValue JSON stringify | 201.87 | — | — | 7621.35 (37.75x) | 2701.97 (13.38x) |
| ListValue JSON parse | 737.12 | — | — | 13552.60 (18.39x) | 5393.88 (7.32x) |
| EmptyListValue JSON stringify | 41.06 | — | — | 983.39 (23.95x) | 234.59 (5.71x) |
| EmptyListValue JSON parse | 132.58 | — | — | 3220.82 (24.29x) | 400.74 (3.02x) |
| DoubleValue JSON stringify | 98.24 | — | — | 1500.02 (15.27x) | 231.93 (2.36x) |
| DoubleValue JSON parse | 112.91 | — | — | 2110.32 (18.69x) | 330.75 (2.93x) |
| NegativeDoubleValue JSON stringify | 98.83 | — | — | 1488.02 (15.06x) | 224.80 (2.27x) |
| NegativeDoubleValue JSON parse | 113.50 | — | — | 2108.11 (18.57x) | 318.18 (2.80x) |
| ZeroDoubleValue JSON stringify | 52.16 | — | — | 1368.99 (26.25x) | 178.29 (3.42x) |
| ZeroDoubleValue JSON parse | 115.30 | — | — | 1862.89 (16.16x) | 312.95 (2.71x) |
| DoubleValue NaN JSON stringify | 52.56 | — | — | 984.39 (18.73x) | 156.44 (2.98x) |
| DoubleValue NaN JSON parse | 101.72 | — | — | 1718.91 (16.90x) | 319.98 (3.15x) |
| DoubleValue Infinity JSON stringify | 55.82 | — | — | 1007.23 (18.04x) | 155.74 (2.79x) |
| DoubleValue Infinity JSON parse | 104.06 | — | — | 1755.17 (16.87x) | 314.93 (3.03x) |
| DoubleValue NegativeInfinity JSON stringify | 57.42 | — | — | 968.70 (16.87x) | 151.72 (2.64x) |
| DoubleValue NegativeInfinity JSON parse | 107.51 | — | — | 1740.51 (16.19x) | 332.01 (3.09x) |
| FloatValue JSON stringify | 102.40 | — | — | 1441.75 (14.08x) | 207.78 (2.03x) |
| FloatValue JSON parse | 113.61 | — | — | 2137.78 (18.82x) | 334.74 (2.95x) |
| NegativeFloatValue JSON stringify | 102.63 | — | — | 1829.46 (17.83x) | 221.19 (2.16x) |
| NegativeFloatValue JSON parse | 114.29 | — | — | 2368.21 (20.72x) | 323.85 (2.83x) |
| ZeroFloatValue JSON stringify | 52.02 | — | — | 1526.06 (29.34x) | 166.62 (3.20x) |
| ZeroFloatValue JSON parse | 115.84 | — | — | 1913.71 (16.52x) | 307.45 (2.65x) |
| FloatValue NaN JSON stringify | 52.70 | — | — | 3407.85 (64.67x) | 150.70 (2.86x) |
| FloatValue NaN JSON parse | 102.91 | — | — | 5374.36 (52.22x) | 306.94 (2.98x) |
| FloatValue Infinity JSON stringify | 55.83 | — | — | 1079.64 (19.34x) | 162.15 (2.90x) |
| FloatValue Infinity JSON parse | 105.10 | — | — | 1877.93 (17.87x) | 318.56 (3.03x) |
| FloatValue NegativeInfinity JSON stringify | 57.43 | — | — | 1020.60 (17.77x) | 157.49 (2.74x) |
| FloatValue NegativeInfinity JSON parse | 107.71 | — | — | 1752.17 (16.27x) | 338.28 (3.14x) |
| Int64Value JSON stringify | 54.17 | — | — | 1109.00 (20.47x) | 318.24 (5.87x) |
| Int64Value JSON parse | 147.29 | — | — | 2052.23 (13.93x) | 513.96 (3.49x) |
| ZeroInt64Value JSON stringify | 44.04 | — | — | 976.42 (22.17x) | 210.56 (4.78x) |
| ZeroInt64Value JSON parse | 103.63 | — | — | 1832.47 (17.68x) | 371.21 (3.58x) |
| NegativeInt64Value JSON stringify | 54.09 | — | — | 1062.95 (19.65x) | 320.65 (5.93x) |
| NegativeInt64Value JSON parse | 148.41 | — | — | 2034.48 (13.71x) | 536.68 (3.62x) |
| MinInt64Value JSON stringify | 57.85 | — | — | 1067.40 (18.45x) | 328.65 (5.68x) |
| MinInt64Value JSON parse | 158.22 | — | — | 2026.95 (12.81x) | 544.20 (3.44x) |
| MaxInt64Value JSON stringify | 57.86 | — | — | 1041.75 (18.00x) | 315.40 (5.45x) |
| MaxInt64Value JSON parse | 156.82 | — | — | 2039.96 (13.01x) | 535.92 (3.42x) |
| UInt64Value JSON stringify | 53.95 | — | — | 1002.83 (18.59x) | 310.76 (5.76x) |
| UInt64Value JSON parse | 147.02 | — | — | 1936.69 (13.17x) | 502.37 (3.42x) |
| ZeroUInt64Value JSON stringify | 43.59 | — | — | 942.19 (21.61x) | 204.43 (4.69x) |
| ZeroUInt64Value JSON parse | 102.25 | — | — | 1807.15 (17.67x) | 361.07 (3.53x) |
| MaxUInt64Value JSON stringify | 57.79 | — | — | 994.70 (17.21x) | 327.39 (5.67x) |
| MaxUInt64Value JSON parse | 160.06 | — | — | 1955.47 (12.22x) | 522.19 (3.26x) |
| Int32Value JSON stringify | 47.87 | — | — | 976.87 (20.41x) | 171.25 (3.58x) |
| Int32Value JSON parse | 129.03 | — | — | 1905.55 (14.77x) | 355.07 (2.75x) |
| ZeroInt32Value JSON stringify | 48.71 | — | — | 962.37 (19.76x) | 152.72 (3.14x) |
| ZeroInt32Value JSON parse | 123.18 | — | — | 1862.74 (15.12x) | 310.00 (2.52x) |
| NegativeInt32Value JSON stringify | 48.30 | — | — | 990.39 (20.50x) | 155.24 (3.21x) |
| NegativeInt32Value JSON parse | 126.60 | — | — | 1922.31 (15.18x) | 341.49 (2.70x) |
| MinInt32Value JSON stringify | 48.77 | — | — | 976.60 (20.02x) | 168.95 (3.46x) |
| MinInt32Value JSON parse | 137.75 | — | — | 1931.59 (14.02x) | 385.92 (2.80x) |
| MaxInt32Value JSON stringify | 48.68 | — | — | 991.64 (20.37x) | 171.68 (3.53x) |
| MaxInt32Value JSON parse | 139.10 | — | — | 1954.95 (14.05x) | 364.44 (2.62x) |
| UInt32Value JSON stringify | 47.36 | — | — | 919.46 (19.41x) | 172.43 (3.64x) |
| UInt32Value JSON parse | 128.99 | — | — | 1893.12 (14.68x) | 348.94 (2.71x) |
| ZeroUInt32Value JSON stringify | 48.82 | — | — | 901.86 (18.47x) | 170.94 (3.50x) |
| ZeroUInt32Value JSON parse | 122.89 | — | — | 1861.76 (15.15x) | 300.13 (2.44x) |
| MaxUInt32Value JSON stringify | 48.42 | — | — | 941.80 (19.45x) | 170.07 (3.51x) |
| MaxUInt32Value JSON parse | 140.12 | — | — | 1931.10 (13.78x) | 381.23 (2.72x) |
| BoolValue JSON stringify | 46.56 | — | — | 909.23 (19.53x) | 149.53 (3.21x) |
| BoolValue JSON parse | 59.00 | — | — | 1709.16 (28.97x) | 253.11 (4.29x) |
| FalseBoolValue JSON stringify | 46.59 | — | — | 904.07 (19.40x) | 168.43 (3.62x) |
| FalseBoolValue JSON parse | 59.33 | — | — | 1722.49 (29.03x) | 241.60 (4.07x) |
| StringValue JSON stringify | 57.71 | — | — | 1004.85 (17.41x) | 219.29 (3.80x) |
| StringValue JSON parse | 129.72 | — | — | 1798.13 (13.86x) | 361.09 (2.78x) |
| EmptyStringValue JSON stringify | 52.30 | — | — | 933.82 (17.86x) | 216.29 (4.14x) |
| EmptyStringValue JSON parse | 73.65 | — | — | 1762.57 (23.93x) | 265.86 (3.61x) |
| BytesValue JSON stringify | 48.45 | — | — | 997.07 (20.58x) | 237.69 (4.91x) |
| BytesValue JSON parse | 142.94 | — | — | 1958.95 (13.70x) | 373.30 (2.61x) |
| EmptyBytesValue JSON stringify | 43.15 | — | — | 973.33 (22.56x) | 223.59 (5.18x) |
| EmptyBytesValue JSON parse | 82.22 | — | — | 1877.52 (22.84x) | 327.02 (3.98x) |
| TextFormat format | 235.23 | — | — | 3157.50 (13.42x) | 3101.64 (13.19x) |
| TextFormat parse | 836.48 | — | — | 5634.04 (6.74x) | 8050.35 (9.62x) |
| packed fixed32 encode | 2.26 | 806.24 (356.74x) | 628.87 (278.26x) | 90.83 (40.19x) | 569.47 (251.98x) |
| packed fixed32 decode | 6.94 | 2143.73 (308.89x) | 2596.76 (374.17x) | 98.94 (14.26x) | 2006.67 (289.15x) |
| packed fixed64 encode | 2.76 | 724.59 (262.53x) | 633.24 (229.43x) | 155.05 (56.18x) | 570.90 (206.85x) |
| packed fixed64 decode | 7.27 | 1222.92 (168.21x) | 7405.12 (1018.59x) | 166.03 (22.84x) | 3242.44 (446.00x) |
| packed sfixed32 encode | 2.51 | 706.18 (281.35x) | 628.82 (250.53x) | 91.23 (36.35x) | 569.84 (227.03x) |
| packed sfixed32 decode | 7.27 | 2136.09 (293.82x) | 2840.55 (390.72x) | 95.88 (13.19x) | 2007.63 (276.15x) |
| packed sfixed64 encode | 2.51 | 806.76 (321.42x) | 631.39 (251.55x) | 155.00 (61.75x) | 571.26 (227.59x) |
| packed sfixed64 decode | 7.02 | 1229.87 (175.20x) | 7302.03 (1040.18x) | 161.01 (22.94x) | 2741.71 (390.56x) |
| packed float encode | 2.26 | 831.63 (367.98x) | 629.60 (278.58x) | 91.11 (40.31x) | 565.27 (250.12x) |
| packed float decode | 7.29 | 1974.58 (270.86x) | 2630.11 (360.78x) | 96.03 (13.17x) | 1998.73 (274.17x) |
| packed double encode | 2.51 | 848.74 (338.14x) | 633.10 (252.23x) | 154.96 (61.74x) | 567.03 (225.91x) |
| packed double decode | 7.24 | 1958.09 (270.45x) | 2862.38 (395.36x) | 161.09 (22.25x) | 3274.47 (452.27x) |
| packed uint64 encode | 2495.86 | 6943.66 (2.78x) | 6310.99 (2.53x) | 3374.54 (1.35x) | 6165.88 (2.47x) |
| packed uint64 decode | 2590.06 | 4294.32 (1.66x) | 8622.84 (3.33x) | 4541.13 (1.75x) | 11442.43 (4.42x) |
| packed uint32 encode | 1631.70 | 4770.75 (2.92x) | 4414.34 (2.71x) | 2663.32 (1.63x) | 5423.36 (3.32x) |
| packed uint32 decode | 1881.31 | 3605.02 (1.92x) | 4789.08 (2.55x) | 3256.06 (1.73x) | 8699.83 (4.62x) |
| packed int64 encode | 2280.44 | 15633.62 (6.86x) | 7316.32 (3.21x) | 4490.17 (1.97x) | 7662.34 (3.36x) |
| packed int64 decode | 4426.40 | 5589.82 (1.26x) | 10697.07 (2.42x) | 5994.09 (1.35x) | 14457.65 (3.27x) |
| packed sint32 encode | 1085.88 | 4424.59 (4.07x) | 3628.21 (3.34x) | 2631.04 (2.42x) | 6002.25 (5.53x) |
| packed sint32 decode | 1298.33 | 3858.03 (2.97x) | 4757.33 (3.66x) | 1849.85 (1.42x) | 5114.41 (3.94x) |
| packed sint64 encode | 2033.80 | 7590.96 (3.73x) | 6338.31 (3.12x) | 3863.24 (1.90x) | 6715.80 (3.30x) |
| packed sint64 decode | 2845.40 | 4305.70 (1.51x) | 9789.77 (3.44x) | 4788.98 (1.68x) | 12064.06 (4.24x) |
| packed bool encode | 3.00 | 2080.36 (693.45x) | 539.70 (179.90x) | 22.56 (7.52x) | 4388.91 (1462.97x) |
| packed bool decode | 271.72 | 2059.04 (7.58x) | 3855.47 (14.19x) | 1108.08 (4.08x) | 2766.23 (10.18x) |
| packed enum encode | 582.45 | 4921.52 (8.45x) | 2590.23 (4.45x) | 1623.71 (2.79x) | 5051.92 (8.67x) |
| packed enum decode | 276.63 | 2107.86 (7.62x) | 4163.38 (15.05x) | 1001.68 (3.62x) | 3386.56 (12.24x) |
| large map encode | 5386.21 | 22310.14 (4.14x) | 13230.16 (2.46x) | 34542.20 (6.41x) | 241954.35 (44.92x) |
| shuffled large map deterministic binary encode | 35948.85 | — | — | 116472.00 (3.24x) | 457294.57 (12.72x) |
| large map decode | 37407.35 | 136835.85 (3.66x) | 125785.72 (3.36x) | 117413.00 (3.14x) | 302239.20 (8.08x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded zero/positive/integer-negative/fractional-negative/min-max-bound `Duration`, non-empty and empty `Struct`, object/list/scalar `Value`,
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
