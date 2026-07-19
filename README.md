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

Latest accepted comparison (`/tmp/pbz-compare-offset-timestamp-json-isolated.log`,
summarized in `/tmp/pbz-summary-offset-timestamp-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 27.87 | 125.57 (4.51x) | 63.85 (2.29x) | 131.19 (4.71x) | 940.45 (33.74x) |
| binary decode | 134.81 | 305.47 (2.27x) | 299.69 (2.22x) | 268.93 (1.99x) | 1019.42 (7.56x) |
| unknown fields count by number | 5.02 | — | — | 179.24 (35.70x) | — |
| deterministic binary encode | 69.62 | — | — | 151.62 (2.18x) | 1223.16 (17.57x) |
| scalarmix encode | 26.44 | 113.59 (4.30x) | 69.48 (2.63x) | 45.29 (1.71x) | 237.27 (8.97x) |
| scalarmix decode | 58.85 | 162.86 (2.77x) | 212.11 (3.60x) | 107.28 (1.82x) | 366.99 (6.24x) |
| textbytes encode | 13.53 | 91.58 (6.77x) | 43.42 (3.21x) | 147.88 (10.93x) | 183.97 (13.60x) |
| textbytes decode | 58.55 | 485.09 (8.29x) | 306.68 (5.24x) | 202.28 (3.45x) | 811.19 (13.85x) |
| largebytes encode | 23.06 | 3906.93 (169.42x) | 3807.23 (165.10x) | 3873.41 (167.97x) | 4116.64 (178.52x) |
| largebytes decode | 126.68 | 8467.13 (66.84x) | 4588.47 (36.22x) | 6784.28 (53.55x) | 24345.90 (192.18x) |
| presencemix encode | 23.81 | 64.52 (2.71x) | 38.57 (1.62x) | 70.81 (2.97x) | 261.39 (10.98x) |
| presencemix decode | 70.03 | 161.87 (2.31x) | 139.34 (1.99x) | 193.08 (2.76x) | 552.42 (7.89x) |
| complex encode | 67.15 | 164.75 (2.45x) | 115.50 (1.72x) | 219.94 (3.28x) | 972.44 (14.48x) |
| complex decode | 217.75 | 477.55 (2.19x) | 435.71 (2.00x) | 473.79 (2.18x) | 1574.85 (7.23x) |
| complex deterministic binary encode | 124.31 | — | — | 223.32 (1.80x) | 1254.95 (10.10x) |
| complex JSON stringify | 368.21 | — | — | 7036.05 (19.11x) | 7490.49 (20.34x) |
| complex JSON parse | 2769.60 | — | — | 16683.10 (6.02x) | 10369.75 (3.74x) |
| complex TextFormat format | 353.54 | — | — | 4813.35 (13.61x) | 6578.97 (18.61x) |
| complex TextFormat parse | 2255.81 | — | — | 7890.83 (3.50x) | 11303.02 (5.01x) |
| packed int32 encode | 896.12 | 5390.71 (6.02x) | 3024.80 (3.38x) | 2275.01 (2.54x) | 5693.96 (6.35x) |
| packed int32 decode | 995.15 | 2980.72 (3.00x) | 4382.17 (4.40x) | 1342.62 (1.35x) | 4405.25 (4.43x) |
| JSON stringify | 204.99 | — | — | 4811.36 (23.47x) | 2785.12 (13.59x) |
| JSON parse | 1680.62 | — | — | 10699.20 (6.37x) | 5695.53 (3.39x) |
| Any WKT JSON stringify | 177.67 | — | — | 3029.14 (17.05x) | 1342.33 (7.56x) |
| Any WKT JSON parse | 562.52 | — | — | 4643.70 (8.26x) | 2106.57 (3.74x) |
| Any MicroDuration WKT JSON stringify | 178.82 | — | — | 3057.81 (17.10x) | 1346.37 (7.53x) |
| Any MicroDuration WKT JSON parse | 568.35 | — | — | 4667.03 (8.21x) | 2140.26 (3.77x) |
| Any NanoDuration WKT JSON stringify | 176.15 | — | — | 3098.72 (17.59x) | 1320.67 (7.50x) |
| Any NanoDuration WKT JSON parse | 578.00 | — | — | 4616.69 (7.99x) | 2125.76 (3.68x) |
| Any NegativeDuration WKT JSON stringify | 182.07 | — | — | 3059.64 (16.80x) | 1427.82 (7.84x) |
| Any NegativeDuration WKT JSON parse | 567.26 | — | — | 4660.75 (8.22x) | 2182.56 (3.85x) |
| Any FractionalNegativeDuration WKT JSON stringify | 172.12 | — | — | 3007.77 (17.47x) | 1385.71 (8.05x) |
| Any FractionalNegativeDuration WKT JSON parse | 559.08 | — | — | 4638.68 (8.30x) | 2120.51 (3.79x) |
| Any MaxDuration WKT JSON stringify | 158.26 | — | — | 2713.83 (17.15x) | 1346.52 (8.51x) |
| Any MaxDuration WKT JSON parse | 587.32 | — | — | 4539.40 (7.73x) | 2115.21 (3.60x) |
| Any MinDuration WKT JSON stringify | 160.28 | — | — | 2718.40 (16.96x) | 1393.00 (8.69x) |
| Any MinDuration WKT JSON parse | 587.77 | — | — | 4669.51 (7.94x) | 2125.24 (3.62x) |
| Any ZeroDuration WKT JSON stringify | 142.50 | — | — | 1289.54 (9.05x) | 1225.98 (8.60x) |
| Any ZeroDuration WKT JSON parse | 516.03 | — | — | 3271.13 (6.34x) | 1951.65 (3.78x) |
| Any FieldMask WKT JSON stringify | 281.15 | — | — | 2424.99 (8.63x) | 1757.81 (6.25x) |
| Any FieldMask WKT JSON parse | 783.37 | — | — | 4820.74 (6.15x) | 2895.43 (3.70x) |
| Any EmptyFieldMask WKT JSON stringify | 149.29 | — | — | 1267.95 (8.49x) | 875.36 (5.86x) |
| Any EmptyFieldMask WKT JSON parse | 488.61 | — | — | 3140.99 (6.43x) | 1620.47 (3.32x) |
| Any Timestamp WKT JSON stringify | 243.81 | — | — | 2982.44 (12.23x) | 1363.08 (5.59x) |
| Any Timestamp WKT JSON parse | 630.90 | — | — | 4616.20 (7.32x) | 2236.63 (3.55x) |
| Any Micro Timestamp WKT JSON stringify | 246.32 | — | — | 3011.71 (12.23x) | 1385.34 (5.62x) |
| Any Micro Timestamp WKT JSON parse | 638.02 | — | — | 4668.57 (7.32x) | 2287.26 (3.58x) |
| Any Nano Timestamp WKT JSON stringify | 245.51 | — | — | 2988.14 (12.17x) | 1326.34 (5.40x) |
| Any Nano Timestamp WKT JSON parse | 645.43 | — | — | 4635.61 (7.18x) | 2311.38 (3.58x) |
| Any Offset Timestamp WKT JSON parse | 655.64 | — | — | 4661.63 (7.11x) | 2313.39 (3.53x) |
| Any PreEpoch Timestamp WKT JSON stringify | 190.62 | — | — | 2904.14 (15.24x) | 1284.63 (6.74x) |
| Any PreEpoch Timestamp WKT JSON parse | 613.43 | — | — | 4626.26 (7.54x) | 2210.49 (3.60x) |
| Any Max Timestamp WKT JSON stringify | 217.68 | — | — | 3007.97 (13.82x) | 1330.18 (6.11x) |
| Any Max Timestamp WKT JSON parse | 646.96 | — | — | 4660.08 (7.20x) | 2305.54 (3.56x) |
| Any Min Timestamp WKT JSON stringify | 224.34 | — | — | 2910.38 (12.97x) | 1284.24 (5.72x) |
| Any Min Timestamp WKT JSON parse | 611.83 | — | — | 4643.59 (7.59x) | 2238.78 (3.66x) |
| Any Empty WKT JSON stringify | 121.64 | — | — | 1274.93 (10.48x) | 689.12 (5.67x) |
| Any Empty WKT JSON parse | 372.63 | — | — | 3059.39 (8.21x) | 1597.53 (4.29x) |
| Any Struct WKT JSON stringify | 787.56 | — | — | 9066.91 (11.51x) | 8497.95 (10.79x) |
| Any Struct WKT JSON parse | 1958.93 | — | — | 17142.50 (8.75x) | 12541.95 (6.40x) |
| Any EmptyStruct WKT JSON stringify | 155.76 | — | — | 1259.39 (8.09x) | 1266.12 (8.13x) |
| Any EmptyStruct WKT JSON parse | 490.93 | — | — | 3284.86 (6.69x) | 2225.63 (4.53x) |
| Any Value WKT JSON stringify | 830.06 | — | — | 9003.49 (10.85x) | 9036.18 (10.89x) |
| Any Value WKT JSON parse | 2053.93 | — | — | 17095.80 (8.32x) | 12922.12 (6.29x) |
| Any NullValue WKT JSON stringify | 162.70 | — | — | 3196.41 (19.65x) | 1250.97 (7.69x) |
| Any NullValue WKT JSON parse | 510.51 | — | — | 6158.17 (12.06x) | 2180.77 (4.27x) |
| Any StringScalarValue WKT JSON stringify | 193.49 | — | — | 3173.75 (16.40x) | 1385.71 (7.16x) |
| Any StringScalarValue WKT JSON parse | 562.74 | — | — | 5307.32 (9.43x) | 2302.66 (4.09x) |
| Any EmptyStringScalarValue WKT JSON stringify | 173.04 | — | — | 3197.91 (18.48x) | 1315.81 (7.60x) |
| Any EmptyStringScalarValue WKT JSON parse | 530.95 | — | — | 5315.60 (10.01x) | 2196.09 (4.14x) |
| Any NumberValue WKT JSON stringify | 239.55 | — | — | 3878.84 (16.19x) | 1489.10 (6.22x) |
| Any NumberValue WKT JSON parse | 550.23 | — | — | 5627.91 (10.23x) | 2375.60 (4.32x) |
| Any ZeroNumberValue WKT JSON stringify | 183.20 | — | — | 3791.65 (20.70x) | 1340.14 (7.32x) |
| Any ZeroNumberValue WKT JSON parse | 552.29 | — | — | 5392.08 (9.76x) | 2369.80 (4.29x) |
| Any BoolScalarValue WKT JSON stringify | 165.18 | — | — | 3128.72 (18.94x) | 1264.76 (7.66x) |
| Any BoolScalarValue WKT JSON parse | 508.76 | — | — | 5297.25 (10.41x) | 2151.24 (4.23x) |
| Any FalseBoolScalarValue WKT JSON stringify | 164.91 | — | — | 3134.28 (19.01x) | 1277.20 (7.74x) |
| Any FalseBoolScalarValue WKT JSON parse | 508.56 | — | — | 5313.03 (10.45x) | 2162.86 (4.25x) |
| Any ListKindValue WKT JSON stringify | 608.58 | — | — | 8698.88 (14.29x) | 6969.03 (11.45x) |
| Any ListKindValue WKT JSON parse | 1539.66 | — | — | 15459.20 (10.04x) | 10462.00 (6.80x) |
| Any EmptyStructKindValue WKT JSON stringify | 187.48 | — | — | 4062.12 (21.67x) | 1949.76 (10.40x) |
| Any EmptyStructKindValue WKT JSON parse | 551.84 | — | — | 8062.82 (14.61x) | 3049.09 (5.53x) |
| Any EmptyListKindValue WKT JSON stringify | 183.29 | — | — | 4101.77 (22.38x) | 1658.01 (9.05x) |
| Any EmptyListKindValue WKT JSON parse | 560.64 | — | — | 6564.43 (11.71x) | 2854.14 (5.09x) |
| Any DoubleValue WKT JSON stringify | 251.35 | — | — | 2876.45 (11.44x) | 1008.14 (4.01x) |
| Any DoubleValue WKT JSON parse | 571.04 | — | — | 4378.50 (7.67x) | 2029.61 (3.55x) |
| Any NegativeDoubleValue WKT JSON stringify | 252.72 | — | — | 2936.16 (11.62x) | 938.08 (3.71x) |
| Any NegativeDoubleValue WKT JSON parse | 574.22 | — | — | 4489.72 (7.82x) | 1997.96 (3.48x) |
| Any ZeroDoubleValue WKT JSON stringify | 202.71 | — | — | 1302.69 (6.43x) | 846.40 (4.18x) |
| Any ZeroDoubleValue WKT JSON parse | 573.89 | — | — | 3189.91 (5.56x) | 1904.76 (3.32x) |
| Any DoubleValue NaN WKT JSON stringify | 197.44 | — | — | 2360.95 (11.96x) | 822.55 (4.17x) |
| Any DoubleValue NaN WKT JSON parse | 568.24 | — | — | 4089.96 (7.20x) | 1932.46 (3.40x) |
| Any DoubleValue Infinity WKT JSON stringify | 199.86 | — | — | 2285.41 (11.44x) | 829.30 (4.15x) |
| Any DoubleValue Infinity WKT JSON parse | 573.86 | — | — | 4058.12 (7.07x) | 1921.21 (3.35x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 201.01 | — | — | 2260.15 (11.24x) | 848.15 (4.22x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 576.41 | — | — | 4081.59 (7.08x) | 1938.58 (3.36x) |
| Any FloatValue WKT JSON stringify | 261.30 | — | — | 2799.37 (10.71x) | 1015.79 (3.89x) |
| Any FloatValue WKT JSON parse | 570.70 | — | — | 4350.80 (7.62x) | 1975.25 (3.46x) |
| Any NegativeFloatValue WKT JSON stringify | 260.85 | — | — | 2793.23 (10.71x) | 908.80 (3.48x) |
| Any NegativeFloatValue WKT JSON parse | 571.46 | — | — | 4334.16 (7.58x) | 1971.55 (3.45x) |
| Any ZeroFloatValue WKT JSON stringify | 207.80 | — | — | 1313.40 (6.32x) | 822.68 (3.96x) |
| Any ZeroFloatValue WKT JSON parse | 579.89 | — | — | 3205.94 (5.53x) | 1874.77 (3.23x) |
| Any FloatValue NaN WKT JSON stringify | 200.66 | — | — | 2246.70 (11.20x) | 816.41 (4.07x) |
| Any FloatValue NaN WKT JSON parse | 567.54 | — | — | 4011.46 (7.07x) | 1862.74 (3.28x) |
| Any FloatValue Infinity WKT JSON stringify | 205.61 | — | — | 2210.41 (10.75x) | 823.89 (4.01x) |
| Any FloatValue Infinity WKT JSON parse | 573.59 | — | — | 3985.59 (6.95x) | 1898.69 (3.31x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 206.52 | — | — | 2159.93 (10.46x) | 820.85 (3.97x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 576.83 | — | — | 4021.75 (6.97x) | 1857.15 (3.22x) |
| Any Int64Value WKT JSON stringify | 211.34 | — | — | 2184.06 (10.33x) | 1180.07 (5.58x) |
| Any Int64Value WKT JSON parse | 618.18 | — | — | 4202.79 (6.80x) | 2312.87 (3.74x) |
| Any ZeroInt64Value WKT JSON stringify | 201.85 | — | — | 1280.92 (6.35x) | 1026.37 (5.08x) |
| Any ZeroInt64Value WKT JSON parse | 573.55 | — | — | 3143.04 (5.48x) | 2070.48 (3.61x) |
| Any NegativeInt64Value WKT JSON stringify | 214.69 | — | — | 2171.23 (10.11x) | 1151.52 (5.36x) |
| Any NegativeInt64Value WKT JSON parse | 616.00 | — | — | 4333.74 (7.04x) | 2354.81 (3.82x) |
| Any MinInt64Value WKT JSON stringify | 217.48 | — | — | 2193.89 (10.09x) | 1197.31 (5.51x) |
| Any MinInt64Value WKT JSON parse | 625.97 | — | — | 4400.58 (7.03x) | 2371.77 (3.79x) |
| Any MaxInt64Value WKT JSON stringify | 217.71 | — | — | 2187.53 (10.05x) | 1167.46 (5.36x) |
| Any MaxInt64Value WKT JSON parse | 628.17 | — | — | 4332.76 (6.90x) | 2301.42 (3.66x) |
| Any UInt64Value WKT JSON stringify | 221.25 | — | — | 2214.24 (10.01x) | 1163.70 (5.26x) |
| Any UInt64Value WKT JSON parse | 622.91 | — | — | 4237.04 (6.80x) | 2293.10 (3.68x) |
| Any ZeroUInt64Value WKT JSON stringify | 208.11 | — | — | 1279.83 (6.15x) | 1017.47 (4.89x) |
| Any ZeroUInt64Value WKT JSON parse | 577.65 | — | — | 3151.81 (5.46x) | 2064.57 (3.57x) |
| Any MaxUInt64Value WKT JSON stringify | 226.23 | — | — | 2197.11 (9.71x) | 1171.26 (5.18x) |
| Any MaxUInt64Value WKT JSON parse | 635.34 | — | — | 4386.85 (6.90x) | 2279.36 (3.59x) |
| Any Int32Value WKT JSON stringify | 212.94 | — | — | 2262.89 (10.63x) | 858.42 (4.03x) |
| Any Int32Value WKT JSON parse | 591.82 | — | — | 4177.93 (7.06x) | 1985.32 (3.35x) |
| Any ZeroInt32Value WKT JSON stringify | 210.86 | — | — | 1293.41 (6.13x) | 821.76 (3.90x) |
| Any ZeroInt32Value WKT JSON parse | 585.05 | — | — | 3226.52 (5.51x) | 1958.94 (3.35x) |
| Any NegativeInt32Value WKT JSON stringify | 215.72 | — | — | 2245.52 (10.41x) | 865.35 (4.01x) |
| Any NegativeInt32Value WKT JSON parse | 588.39 | — | — | 4204.78 (7.15x) | 2019.64 (3.43x) |
| Any MinInt32Value WKT JSON stringify | 218.23 | — | — | 2255.83 (10.34x) | 869.60 (3.98x) |
| Any MinInt32Value WKT JSON parse | 599.79 | — | — | 4338.97 (7.23x) | 2093.82 (3.49x) |
| Any MaxInt32Value WKT JSON stringify | 215.49 | — | — | 2369.03 (10.99x) | 877.81 (4.07x) |
| Any MaxInt32Value WKT JSON parse | 601.97 | — | — | 4272.90 (7.10x) | 2008.79 (3.34x) |
| Any UInt32Value WKT JSON stringify | 221.37 | — | — | 2199.74 (9.94x) | 925.42 (4.18x) |
| Any UInt32Value WKT JSON parse | 595.85 | — | — | 4138.47 (6.95x) | 1974.94 (3.31x) |
| Any ZeroUInt32Value WKT JSON stringify | 217.29 | — | — | 1334.18 (6.14x) | 836.11 (3.85x) |
| Any ZeroUInt32Value WKT JSON parse | 589.50 | — | — | 3261.42 (5.53x) | 1837.50 (3.12x) |
| Any MaxUInt32Value WKT JSON stringify | 223.55 | — | — | 2446.46 (10.94x) | 887.33 (3.97x) |
| Any MaxUInt32Value WKT JSON parse | 609.86 | — | — | 4749.08 (7.79x) | 1974.50 (3.24x) |
| Any BoolValue WKT JSON stringify | 217.28 | — | — | 2525.25 (11.62x) | 826.11 (3.80x) |
| Any BoolValue WKT JSON parse | 546.83 | — | — | 4328.86 (7.92x) | 1714.01 (3.13x) |
| Any FalseBoolValue WKT JSON stringify | 218.77 | — | — | 1426.51 (6.52x) | 795.20 (3.63x) |
| Any FalseBoolValue WKT JSON parse | 543.21 | — | — | 3329.62 (6.13x) | 1717.61 (3.16x) |
| Any StringValue WKT JSON stringify | 247.06 | — | — | 2210.10 (8.95x) | 986.77 (3.99x) |
| Any StringValue WKT JSON parse | 609.62 | — | — | 4087.50 (6.70x) | 2011.01 (3.30x) |
| Any EmptyStringValue WKT JSON stringify | 233.50 | — | — | 1500.22 (6.42x) | 858.00 (3.67x) |
| Any EmptyStringValue WKT JSON parse | 570.69 | — | — | 3569.82 (6.26x) | 1668.07 (2.92x) |
| Any BytesValue WKT JSON stringify | 235.12 | — | — | 2254.83 (9.59x) | 1030.34 (4.38x) |
| Any BytesValue WKT JSON parse | 617.04 | — | — | 4202.06 (6.81x) | 2047.53 (3.32x) |
| Any EmptyBytesValue WKT JSON stringify | 226.85 | — | — | 1397.98 (6.16x) | 847.82 (3.74x) |
| Any EmptyBytesValue WKT JSON parse | 575.29 | — | — | 3340.93 (5.81x) | 1815.11 (3.16x) |
| Nested Any WKT JSON stringify | 382.07 | — | — | 3413.74 (8.93x) | 1659.98 (4.34x) |
| Nested Any WKT JSON parse | 995.72 | — | — | 6031.22 (6.06x) | 3639.75 (3.66x) |
| Duration JSON stringify | 64.90 | — | — | 1545.96 (23.82x) | 383.20 (5.90x) |
| Duration JSON parse | 10.89 | — | — | 2292.80 (210.54x) | 433.73 (39.83x) |
| MicroDuration JSON stringify | 68.83 | — | — | 1547.57 (22.48x) | 435.39 (6.33x) |
| MicroDuration JSON parse | 15.81 | — | — | 2311.08 (146.18x) | 435.56 (27.55x) |
| NanoDuration JSON stringify | 63.91 | — | — | 1593.19 (24.93x) | 438.69 (6.86x) |
| NanoDuration JSON parse | 22.05 | — | — | 2320.08 (105.22x) | 436.77 (19.81x) |
| NegativeDuration JSON stringify | 65.17 | — | — | 1624.96 (24.93x) | 462.89 (7.10x) |
| NegativeDuration JSON parse | 11.08 | — | — | 2391.74 (215.86x) | 440.10 (39.72x) |
| FractionalNegativeDuration JSON stringify | 65.18 | — | — | 1591.09 (24.41x) | 463.37 (7.11x) |
| FractionalNegativeDuration JSON parse | 11.06 | — | — | 2295.19 (207.52x) | 422.36 (38.19x) |
| MaxDuration JSON stringify | 54.51 | — | — | 1293.68 (23.73x) | 455.84 (8.36x) |
| MaxDuration JSON parse | 29.18 | — | — | 2211.72 (75.80x) | 441.77 (15.14x) |
| MinDuration JSON stringify | 54.04 | — | — | 1295.75 (23.98x) | 450.74 (8.34x) |
| MinDuration JSON parse | 29.39 | — | — | 2220.52 (75.55x) | 437.97 (14.90x) |
| ZeroDuration JSON stringify | 47.74 | — | — | 1307.20 (27.38x) | 358.97 (7.52x) |
| ZeroDuration JSON parse | 8.78 | — | — | 2188.06 (249.21x) | 345.36 (39.33x) |
| FieldMask JSON stringify | 92.05 | — | — | 1339.61 (14.55x) | 767.31 (8.34x) |
| FieldMask JSON parse | 181.39 | — | — | 2712.37 (14.95x) | 1044.83 (5.76x) |
| EmptyFieldMask JSON stringify | 43.26 | — | — | 944.10 (21.82x) | 236.98 (5.48x) |
| EmptyFieldMask JSON parse | 3.52 | — | — | 1445.90 (410.77x) | 198.22 (56.31x) |
| Timestamp JSON stringify | 130.03 | — | — | 1749.91 (13.46x) | 473.80 (3.64x) |
| Timestamp JSON parse | 56.75 | — | — | 2343.57 (41.30x) | 492.23 (8.67x) |
| Micro Timestamp JSON stringify | 132.29 | — | — | 1757.43 (13.28x) | 469.57 (3.55x) |
| Micro Timestamp JSON parse | 59.48 | — | — | 2338.94 (39.32x) | 497.86 (8.37x) |
| Nano Timestamp JSON stringify | 131.97 | — | — | 1765.74 (13.38x) | 482.45 (3.66x) |
| Nano Timestamp JSON parse | 62.77 | — | — | 2336.16 (37.22x) | 505.61 (8.05x) |
| Offset Timestamp JSON parse | 71.79 | — | — | 2368.79 (33.00x) | 509.34 (7.09x) |
| PreEpoch Timestamp JSON stringify | 86.06 | — | — | 1595.32 (18.54x) | 473.69 (5.50x) |
| PreEpoch Timestamp JSON parse | 54.79 | — | — | 2287.37 (41.75x) | 474.82 (8.67x) |
| Max Timestamp JSON stringify | 103.84 | — | — | 1751.54 (16.87x) | 477.65 (4.60x) |
| Max Timestamp JSON parse | 64.26 | — | — | 2355.15 (36.65x) | 505.24 (7.86x) |
| Min Timestamp JSON stringify | 118.58 | — | — | 1648.48 (13.90x) | 457.70 (3.86x) |
| Min Timestamp JSON parse | 52.71 | — | — | 2270.76 (43.08x) | 473.97 (8.99x) |
| Empty JSON stringify | 22.56 | — | — | 696.22 (30.86x) | 96.71 (4.29x) |
| Empty JSON parse | 75.47 | — | — | 1104.79 (14.64x) | 275.11 (3.65x) |
| Struct JSON stringify | 272.97 | — | — | 9110.96 (33.38x) | 3877.98 (14.21x) |
| Struct JSON parse | 930.29 | — | — | 16928.10 (18.20x) | 6310.94 (6.78x) |
| EmptyStruct JSON stringify | 43.02 | — | — | 975.97 (22.69x) | 406.43 (9.45x) |
| EmptyStruct JSON parse | 90.37 | — | — | 3381.07 (37.41x) | 429.20 (4.75x) |
| Value JSON stringify | 269.59 | — | — | 9902.13 (36.73x) | 4059.31 (15.06x) |
| Value JSON parse | 947.35 | — | — | 18014.50 (19.02x) | 6610.83 (6.98x) |
| NullValue JSON stringify | 43.16 | — | — | 1743.86 (40.40x) | 236.47 (5.48x) |
| NullValue JSON parse | 63.24 | — | — | 3829.73 (60.56x) | 377.53 (5.97x) |
| StringScalarValue JSON stringify | 55.62 | — | — | 1848.69 (33.24x) | 283.79 (5.10x) |
| StringScalarValue JSON parse | 126.38 | — | — | 3073.07 (24.32x) | 498.87 (3.95x) |
| EmptyStringScalarValue JSON stringify | 50.56 | — | — | 1823.23 (36.06x) | 273.21 (5.40x) |
| EmptyStringScalarValue JSON parse | 73.68 | — | — | 3055.73 (41.47x) | 408.18 (5.54x) |
| NumberValue JSON stringify | 112.68 | — | — | 2317.33 (20.57x) | 364.63 (3.24x) |
| NumberValue JSON parse | 123.38 | — | — | 3369.32 (27.31x) | 451.79 (3.66x) |
| ZeroNumberValue JSON stringify | 63.84 | — | — | 2240.90 (35.10x) | 302.33 (4.74x) |
| ZeroNumberValue JSON parse | 125.04 | — | — | 3104.95 (24.83x) | 438.95 (3.51x) |
| BoolScalarValue JSON stringify | 43.05 | — | — | 1760.87 (40.90x) | 237.68 (5.52x) |
| BoolScalarValue JSON parse | 60.02 | — | — | 2986.48 (49.76x) | 371.17 (6.18x) |
| FalseBoolScalarValue JSON stringify | 43.20 | — | — | 1793.58 (41.52x) | 226.58 (5.24x) |
| FalseBoolScalarValue JSON parse | 60.38 | — | — | 2994.60 (49.60x) | 371.19 (6.15x) |
| ListKindValue JSON stringify | 202.54 | — | — | 9096.57 (44.91x) | 2900.16 (14.32x) |
| ListKindValue JSON parse | 754.32 | — | — | 15837.20 (21.00x) | 5596.91 (7.42x) |
| EmptyStructKindValue JSON stringify | 45.20 | — | — | 2729.00 (60.38x) | 634.48 (14.04x) |
| EmptyStructKindValue JSON parse | 109.32 | — | — | 5840.84 (53.43x) | 845.05 (7.73x) |
| EmptyListKindValue JSON stringify | 43.70 | — | — | 2671.02 (61.12x) | 379.70 (8.69x) |
| EmptyListKindValue JSON parse | 145.53 | — | — | 5616.43 (38.59x) | 688.12 (4.73x) |
| ListValue JSON stringify | 199.90 | — | — | 7524.07 (37.64x) | 2695.13 (13.48x) |
| ListValue JSON parse | 729.90 | — | — | 13570.00 (18.59x) | 5254.76 (7.20x) |
| EmptyListValue JSON stringify | 40.81 | — | — | 1015.80 (24.89x) | 232.04 (5.69x) |
| EmptyListValue JSON parse | 127.58 | — | — | 3156.82 (24.74x) | 399.19 (3.13x) |
| DoubleValue JSON stringify | 97.02 | — | — | 1499.13 (15.45x) | 221.40 (2.28x) |
| DoubleValue JSON parse | 113.43 | — | — | 2087.28 (18.40x) | 325.48 (2.87x) |
| NegativeDoubleValue JSON stringify | 96.99 | — | — | 1519.68 (15.67x) | 219.52 (2.26x) |
| NegativeDoubleValue JSON parse | 114.12 | — | — | 2087.36 (18.29x) | 331.03 (2.90x) |
| ZeroDoubleValue JSON stringify | 54.99 | — | — | 1402.57 (25.51x) | 168.53 (3.06x) |
| ZeroDoubleValue JSON parse | 115.69 | — | — | 1889.13 (16.33x) | 309.41 (2.67x) |
| DoubleValue NaN JSON stringify | 52.75 | — | — | 1031.55 (19.56x) | 169.94 (3.22x) |
| DoubleValue NaN JSON parse | 101.72 | — | — | 1729.16 (17.00x) | 310.60 (3.05x) |
| DoubleValue Infinity JSON stringify | 56.09 | — | — | 993.42 (17.71x) | 154.15 (2.75x) |
| DoubleValue Infinity JSON parse | 104.74 | — | — | 1731.31 (16.53x) | 322.37 (3.08x) |
| DoubleValue NegativeInfinity JSON stringify | 57.52 | — | — | 990.33 (17.22x) | 160.71 (2.79x) |
| DoubleValue NegativeInfinity JSON parse | 107.36 | — | — | 1759.65 (16.39x) | 326.35 (3.04x) |
| FloatValue JSON stringify | 103.11 | — | — | 1406.37 (13.64x) | 208.01 (2.02x) |
| FloatValue JSON parse | 112.37 | — | — | 2132.11 (18.97x) | 318.65 (2.84x) |
| NegativeFloatValue JSON stringify | 101.91 | — | — | 1414.44 (13.88x) | 201.05 (1.97x) |
| NegativeFloatValue JSON parse | 112.26 | — | — | 2157.48 (19.22x) | 311.98 (2.78x) |
| ZeroFloatValue JSON stringify | 54.00 | — | — | 1350.36 (25.01x) | 167.61 (3.10x) |
| ZeroFloatValue JSON parse | 114.47 | — | — | 1910.94 (16.69x) | 307.30 (2.68x) |
| FloatValue NaN JSON stringify | 52.67 | — | — | 978.04 (18.57x) | 154.00 (2.92x) |
| FloatValue NaN JSON parse | 101.64 | — | — | 1726.55 (16.99x) | 319.47 (3.14x) |
| FloatValue Infinity JSON stringify | 56.10 | — | — | 962.84 (17.16x) | 148.49 (2.65x) |
| FloatValue Infinity JSON parse | 103.86 | — | — | 1734.58 (16.70x) | 311.66 (3.00x) |
| FloatValue NegativeInfinity JSON stringify | 57.61 | — | — | 944.32 (16.39x) | 149.80 (2.60x) |
| FloatValue NegativeInfinity JSON parse | 106.98 | — | — | 1763.46 (16.48x) | 322.88 (3.02x) |
| Int64Value JSON stringify | 54.32 | — | — | 997.37 (18.36x) | 311.59 (5.74x) |
| Int64Value JSON parse | 137.33 | — | — | 2002.44 (14.58x) | 532.40 (3.88x) |
| ZeroInt64Value JSON stringify | 44.12 | — | — | 917.07 (20.79x) | 196.98 (4.46x) |
| ZeroInt64Value JSON parse | 101.75 | — | — | 1827.02 (17.96x) | 400.82 (3.94x) |
| NegativeInt64Value JSON stringify | 54.11 | — | — | 998.31 (18.45x) | 312.33 (5.77x) |
| NegativeInt64Value JSON parse | 138.06 | — | — | 1967.67 (14.25x) | 577.51 (4.18x) |
| MinInt64Value JSON stringify | 57.90 | — | — | 1004.76 (17.35x) | 328.51 (5.67x) |
| MinInt64Value JSON parse | 147.89 | — | — | 2015.91 (13.63x) | 544.50 (3.68x) |
| MaxInt64Value JSON stringify | 57.69 | — | — | 1026.21 (17.79x) | 305.73 (5.30x) |
| MaxInt64Value JSON parse | 147.05 | — | — | 2008.55 (13.66x) | 540.20 (3.67x) |
| UInt64Value JSON stringify | 54.11 | — | — | 1001.57 (18.51x) | 312.51 (5.78x) |
| UInt64Value JSON parse | 136.65 | — | — | 1932.02 (14.14x) | 525.71 (3.85x) |
| ZeroUInt64Value JSON stringify | 44.32 | — | — | 939.21 (21.19x) | 200.13 (4.52x) |
| ZeroUInt64Value JSON parse | 100.60 | — | — | 1798.11 (17.87x) | 395.46 (3.93x) |
| MaxUInt64Value JSON stringify | 58.43 | — | — | 995.53 (17.04x) | 320.51 (5.49x) |
| MaxUInt64Value JSON parse | 150.07 | — | — | 1993.42 (13.28x) | 536.84 (3.58x) |
| Int32Value JSON stringify | 48.34 | — | — | 973.34 (20.14x) | 155.48 (3.22x) |
| Int32Value JSON parse | 135.03 | — | — | 1934.39 (14.33x) | 345.32 (2.56x) |
| ZeroInt32Value JSON stringify | 47.90 | — | — | 957.78 (20.00x) | 149.69 (3.13x) |
| ZeroInt32Value JSON parse | 129.16 | — | — | 1884.49 (14.59x) | 321.92 (2.49x) |
| NegativeInt32Value JSON stringify | 48.47 | — | — | 976.95 (20.16x) | 154.30 (3.18x) |
| NegativeInt32Value JSON parse | 130.90 | — | — | 1955.59 (14.94x) | 361.58 (2.76x) |
| MinInt32Value JSON stringify | 49.22 | — | — | 990.77 (20.13x) | 169.23 (3.44x) |
| MinInt32Value JSON parse | 142.96 | — | — | 1893.28 (13.24x) | 386.98 (2.71x) |
| MaxInt32Value JSON stringify | 48.95 | — | — | 2389.99 (48.83x) | 162.04 (3.31x) |
| MaxInt32Value JSON parse | 145.67 | — | — | 4728.93 (32.46x) | 376.81 (2.59x) |
| UInt32Value JSON stringify | 48.36 | — | — | 946.55 (19.57x) | 175.83 (3.64x) |
| UInt32Value JSON parse | 134.97 | — | — | 1895.35 (14.04x) | 350.82 (2.60x) |
| ZeroUInt32Value JSON stringify | 48.22 | — | — | 944.40 (19.59x) | 157.53 (3.27x) |
| ZeroUInt32Value JSON parse | 129.16 | — | — | 1888.49 (14.62x) | 315.18 (2.44x) |
| MaxUInt32Value JSON stringify | 48.92 | — | — | 974.90 (19.93x) | 173.50 (3.55x) |
| MaxUInt32Value JSON parse | 145.50 | — | — | 2083.52 (14.32x) | 363.75 (2.50x) |
| BoolValue JSON stringify | 45.62 | — | — | 982.67 (21.54x) | 157.40 (3.45x) |
| BoolValue JSON parse | 59.07 | — | — | 2094.17 (35.45x) | 248.67 (4.21x) |
| FalseBoolValue JSON stringify | 45.74 | — | — | 953.19 (20.84x) | 164.77 (3.60x) |
| FalseBoolValue JSON parse | 59.48 | — | — | 1822.30 (30.64x) | 250.01 (4.20x) |
| StringValue JSON stringify | 58.14 | — | — | 1105.42 (19.01x) | 227.99 (3.92x) |
| StringValue JSON parse | 131.58 | — | — | 1982.19 (15.06x) | 369.03 (2.80x) |
| EmptyStringValue JSON stringify | 51.98 | — | — | 1059.23 (20.38x) | 213.77 (4.11x) |
| EmptyStringValue JSON parse | 74.45 | — | — | 1968.97 (26.45x) | 271.56 (3.65x) |
| BytesValue JSON stringify | 49.57 | — | — | 1061.50 (21.41x) | 242.09 (4.88x) |
| BytesValue JSON parse | 141.94 | — | — | 2237.59 (15.76x) | 374.65 (2.64x) |
| EmptyBytesValue JSON stringify | 43.28 | — | — | 1075.91 (24.86x) | 221.25 (5.11x) |
| EmptyBytesValue JSON parse | 83.48 | — | — | 2008.77 (24.06x) | 330.84 (3.96x) |
| TextFormat format | 237.53 | — | — | 6616.92 (27.86x) | 3072.04 (12.93x) |
| TextFormat parse | 834.87 | — | — | 5775.05 (6.92x) | 8006.67 (9.59x) |
| packed fixed32 encode | 2.51 | 805.33 (320.85x) | 628.71 (250.48x) | 90.93 (36.23x) | 570.21 (227.18x) |
| packed fixed32 decode | 7.02 | 1989.78 (283.44x) | 2587.44 (368.58x) | 99.12 (14.12x) | 2026.36 (288.66x) |
| packed fixed64 encode | 2.76 | 707.05 (256.18x) | 630.59 (228.47x) | 155.19 (56.23x) | 572.59 (207.46x) |
| packed fixed64 decode | 7.02 | 2130.63 (303.51x) | 7422.81 (1057.38x) | 164.59 (23.45x) | 3309.65 (471.46x) |
| packed sfixed32 encode | 2.76 | 705.66 (255.67x) | 628.79 (227.82x) | 90.36 (32.74x) | 572.40 (207.39x) |
| packed sfixed32 decode | 7.15 | 1233.22 (172.48x) | 2591.94 (362.51x) | 96.54 (13.50x) | 2009.44 (281.04x) |
| packed sfixed64 encode | 2.76 | 805.79 (291.95x) | 632.02 (228.99x) | 155.05 (56.18x) | 571.88 (207.20x) |
| packed sfixed64 decode | 7.27 | 2128.32 (292.75x) | 7308.41 (1005.28x) | 162.06 (22.29x) | 2772.32 (381.34x) |
| packed float encode | 2.76 | 824.21 (298.63x) | 630.47 (228.43x) | 90.46 (32.77x) | 565.75 (204.98x) |
| packed float decode | 7.02 | 1233.09 (175.65x) | 2444.88 (348.27x) | 96.68 (13.77x) | 2009.02 (286.19x) |
| packed double encode | 2.26 | 858.02 (379.65x) | 632.82 (280.01x) | 155.29 (68.71x) | 566.78 (250.79x) |
| packed double decode | 7.02 | 1334.22 (190.06x) | 2860.33 (407.45x) | 162.10 (23.09x) | 3234.03 (460.69x) |
| packed uint64 encode | 1843.52 | 6950.13 (3.77x) | 6341.23 (3.44x) | 3141.59 (1.70x) | 6133.17 (3.33x) |
| packed uint64 decode | 2588.53 | 4300.85 (1.66x) | 8627.06 (3.33x) | 4568.69 (1.76x) | 11341.01 (4.38x) |
| packed uint32 encode | 1347.22 | 4759.57 (3.53x) | 4412.25 (3.28x) | 2661.62 (1.98x) | 5428.69 (4.03x) |
| packed uint32 decode | 1881.43 | 3602.01 (1.91x) | 4783.68 (2.54x) | 3265.83 (1.74x) | 8655.61 (4.60x) |
| packed int64 encode | 2054.57 | 15625.02 (7.61x) | 7308.10 (3.56x) | 4181.67 (2.04x) | 7581.84 (3.69x) |
| packed int64 decode | 4434.24 | 5576.89 (1.26x) | 10650.62 (2.40x) | 6038.86 (1.36x) | 14451.00 (3.26x) |
| packed sint32 encode | 1090.70 | 4424.80 (4.06x) | 4118.24 (3.78x) | 2629.34 (2.41x) | 5992.33 (5.49x) |
| packed sint32 decode | 1295.88 | 3862.71 (2.98x) | 4658.64 (3.59x) | 1869.38 (1.44x) | 5030.22 (3.88x) |
| packed sint64 encode | 2563.45 | 7939.90 (3.10x) | 6267.76 (2.45x) | 3424.07 (1.34x) | 6704.21 (2.62x) |
| packed sint64 decode | 2849.37 | 4410.85 (1.55x) | 9788.02 (3.44x) | 5045.67 (1.77x) | 11763.98 (4.13x) |
| packed bool encode | 2.26 | 2080.13 (920.41x) | 540.23 (239.04x) | 24.53 (10.85x) | 4377.56 (1936.97x) |
| packed bool decode | 271.92 | 2059.31 (7.57x) | 4134.90 (15.21x) | 1108.95 (4.08x) | 2714.24 (9.98x) |
| packed enum encode | 554.67 | 4925.77 (8.88x) | 2600.55 (4.69x) | 2130.39 (3.84x) | 5027.67 (9.06x) |
| packed enum decode | 287.61 | 2070.41 (7.20x) | 4209.93 (14.64x) | 1001.38 (3.48x) | 3322.77 (11.55x) |
| large map encode | 5812.09 | 22424.48 (3.86x) | 13034.10 (2.24x) | 35550.90 (6.12x) | 241235.87 (41.51x) |
| shuffled large map deterministic binary encode | 35933.72 | — | — | 117195.00 (3.26x) | 443656.19 (12.35x) |
| large map decode | 38551.64 | 131238.75 (3.40x) | 128749.39 (3.34x) | 117838.00 (3.06x) | 301266.22 (7.81x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded zero/positive/micro/nano/integer-negative/fractional-negative/min-max-bound `Duration`, non-empty and empty `Struct`, object/list/scalar `Value` (including default-like scalar and empty object/list kinds),
`FieldMask` (non-empty and empty), micro/nano/offset/min/pre/post/max-bound `Timestamp`, `Empty`, min/zero/positive/negative/max `Int64Value`, negative/zero/positive finite `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), negative/zero/positive finite `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), zero/normal/max `UInt64Value`, min/zero/positive/negative/max `Int32Value`, zero/normal/max `UInt32Value`, true/false `BoolValue`, non-empty/empty `StringValue`, base64/empty `BytesValue`, and recursive nested `Any` payloads), direct zero/positive/micro/nano/integer-negative/fractional-negative/min-max-bound Duration and micro/nano/offset/min/pre/post/max-bound Timestamp WKT JSON plus other direct WKT JSON, including empty `Struct` and empty `ListValue`, TextFormat, packed scalars, large bytes,
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
