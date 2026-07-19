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

Latest accepted comparison (`/tmp/pbz-compare-negative-float-wrapper-json-isolated-rerun.log`,
summarized in `/tmp/pbz-summary-negative-float-wrapper-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 25.45 | 126.86 (4.98x) | 62.09 (2.44x) | 133.24 (5.24x) | 963.75 (37.87x) |
| binary decode | 126.79 | 298.64 (2.36x) | 294.66 (2.32x) | 273.90 (2.16x) | 1037.03 (8.18x) |
| unknown fields count by number | 5.01 | — | — | 215.45 (43.00x) | — |
| scalarmix encode | 26.08 | 114.21 (4.38x) | 67.09 (2.57x) | 45.96 (1.76x) | 239.88 (9.20x) |
| scalarmix decode | 55.71 | 162.28 (2.91x) | 219.49 (3.94x) | 107.97 (1.94x) | 368.11 (6.61x) |
| textbytes encode | 11.78 | 91.75 (7.79x) | 43.24 (3.67x) | 148.63 (12.62x) | 175.43 (14.89x) |
| largebytes decode | 124.08 | 8449.71 (68.10x) | 4522.01 (36.44x) | 4010.95 (32.33x) | 24285.03 (195.72x) |
| complex decode | 213.54 | 463.63 (2.17x) | 440.47 (2.06x) | 483.89 (2.27x) | 1600.17 (7.49x) |
| complex JSON parse | 2707.12 | — | — | 16834.30 (6.22x) | 10424.58 (3.85x) |
| packed int32 decode | 994.69 | 2976.54 (2.99x) | 4227.72 (4.25x) | 1341.47 (1.35x) | 4353.73 (4.38x) |
| Any WKT JSON stringify | 186.87 | — | — | 3027.75 (16.20x) | 1371.63 (7.34x) |
| Any WKT JSON parse | 604.48 | — | — | 4521.18 (7.48x) | 2111.65 (3.49x) |
| Any NegativeDuration WKT JSON stringify | 197.62 | — | — | 3066.91 (15.52x) | 1399.03 (7.08x) |
| Any NegativeDuration WKT JSON parse | 611.46 | — | — | 4744.40 (7.76x) | 2203.07 (3.60x) |
| Any FractionalNegativeDuration WKT JSON stringify | 188.70 | — | — | 3040.71 (16.11x) | 1378.73 (7.31x) |
| Any FractionalNegativeDuration WKT JSON parse | 604.19 | — | — | 4753.27 (7.87x) | 2109.40 (3.49x) |
| Any MaxDuration WKT JSON stringify | 170.87 | — | — | 2698.21 (15.79x) | 1334.67 (7.81x) |
| Any MaxDuration WKT JSON parse | 627.79 | — | — | 4543.02 (7.24x) | 2107.82 (3.36x) |
| Any MinDuration WKT JSON stringify | 172.35 | — | — | 2734.93 (15.87x) | 1412.85 (8.20x) |
| Any MinDuration WKT JSON parse | 629.47 | — | — | 4668.50 (7.42x) | 2125.84 (3.38x) |
| Any ZeroDuration WKT JSON stringify | 154.11 | — | — | 1328.69 (8.62x) | 1259.94 (8.18x) |
| Any ZeroDuration WKT JSON parse | 552.02 | — | — | 3320.11 (6.01x) | 1931.47 (3.50x) |
| Any FieldMask WKT JSON stringify | 303.19 | — | — | 2457.88 (8.11x) | 1776.69 (5.86x) |
| Any FieldMask WKT JSON parse | 840.32 | — | — | 4887.71 (5.82x) | 2933.37 (3.49x) |
| Any Timestamp WKT JSON stringify | 260.43 | — | — | 2961.44 (11.37x) | 1330.96 (5.11x) |
| Any Timestamp WKT JSON parse | 691.28 | — | — | 4696.35 (6.79x) | 2272.01 (3.29x) |
| Any PreEpoch Timestamp WKT JSON stringify | 208.68 | — | — | 2865.16 (13.73x) | 1290.78 (6.19x) |
| Any PreEpoch Timestamp WKT JSON parse | 656.07 | — | — | 4722.86 (7.20x) | 2214.34 (3.38x) |
| Any Max Timestamp WKT JSON stringify | 235.41 | — | — | 3003.54 (12.76x) | 1341.04 (5.70x) |
| Any Max Timestamp WKT JSON parse | 687.72 | — | — | 4718.54 (6.86x) | 2321.91 (3.38x) |
| Any Min Timestamp WKT JSON stringify | 244.84 | — | — | 2835.23 (11.58x) | 1288.95 (5.26x) |
| Any Min Timestamp WKT JSON parse | 658.38 | — | — | 4615.48 (7.01x) | 2238.71 (3.40x) |
| Any Empty WKT JSON stringify | 130.40 | — | — | 1308.30 (10.03x) | 756.29 (5.80x) |
| Any Empty WKT JSON parse | 392.62 | — | — | 3107.15 (7.91x) | 1600.38 (4.08x) |
| Any Struct WKT JSON stringify | 857.26 | — | — | 9044.34 (10.55x) | 8561.15 (9.99x) |
| Any Struct WKT JSON parse | 2096.51 | — | — | 17149.30 (8.18x) | 12531.01 (5.98x) |
| Any Value WKT JSON stringify | 852.38 | — | — | 9031.25 (10.60x) | 8913.11 (10.46x) |
| Any Value WKT JSON parse | 2134.86 | — | — | 17010.60 (7.97x) | 12926.34 (6.05x) |
| Any DoubleValue WKT JSON stringify | 267.69 | — | — | 2849.42 (10.64x) | 941.55 (3.52x) |
| Any DoubleValue WKT JSON parse | 603.18 | — | — | 4369.91 (7.24x) | 1973.50 (3.27x) |
| Any NegativeDoubleValue WKT JSON stringify | 265.69 | — | — | 2858.73 (10.76x) | 948.74 (3.57x) |
| Any NegativeDoubleValue WKT JSON parse | 601.83 | — | — | 4344.47 (7.22x) | 2009.50 (3.34x) |
| Any ZeroDoubleValue WKT JSON stringify | 217.85 | — | — | 1298.58 (5.96x) | 823.45 (3.78x) |
| Any ZeroDoubleValue WKT JSON parse | 609.22 | — | — | 3126.95 (5.13x) | 1865.11 (3.06x) |
| Any DoubleValue NaN WKT JSON stringify | 214.27 | — | — | 2294.94 (10.71x) | 821.37 (3.83x) |
| Any DoubleValue NaN WKT JSON parse | 603.03 | — | — | 4019.97 (6.67x) | 1851.67 (3.07x) |
| Any DoubleValue Infinity WKT JSON stringify | 219.81 | — | — | 2281.90 (10.38x) | 819.00 (3.73x) |
| Any DoubleValue Infinity WKT JSON parse | 605.13 | — | — | 4025.45 (6.65x) | 1913.64 (3.16x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 222.13 | — | — | 2257.02 (10.16x) | 839.74 (3.78x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 609.36 | — | — | 4051.73 (6.65x) | 1914.06 (3.14x) |
| Any FloatValue WKT JSON stringify | 275.53 | — | — | 2756.82 (10.01x) | 918.30 (3.33x) |
| Any FloatValue WKT JSON parse | 607.20 | — | — | 4333.40 (7.14x) | 1961.39 (3.23x) |
| Any NegativeFloatValue WKT JSON stringify | 274.15 | — | — | 2826.45 (10.31x) | 912.39 (3.33x) |
| Any NegativeFloatValue WKT JSON parse | 607.22 | — | — | 4392.52 (7.23x) | 1938.51 (3.19x) |
| Any ZeroFloatValue WKT JSON stringify | 220.84 | — | — | 1298.63 (5.88x) | 830.62 (3.76x) |
| Any ZeroFloatValue WKT JSON parse | 609.99 | — | — | 3209.68 (5.26x) | 1828.10 (3.00x) |
| Any FloatValue NaN WKT JSON stringify | 214.95 | — | — | 2250.39 (10.47x) | 818.38 (3.81x) |
| Any FloatValue NaN WKT JSON parse | 604.02 | — | — | 4036.60 (6.68x) | 1850.22 (3.06x) |
| Any FloatValue Infinity WKT JSON stringify | 223.09 | — | — | 2223.49 (9.97x) | 809.92 (3.63x) |
| Any FloatValue Infinity WKT JSON parse | 609.21 | — | — | 4015.09 (6.59x) | 1874.31 (3.08x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 224.53 | — | — | 2210.77 (9.85x) | 826.96 (3.68x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 614.50 | — | — | 4062.73 (6.61x) | 1909.07 (3.11x) |
| Any Int64Value WKT JSON stringify | 220.42 | — | — | 2215.33 (10.05x) | 1202.03 (5.45x) |
| Any Int64Value WKT JSON parse | 672.21 | — | — | 4373.79 (6.51x) | 2286.66 (3.40x) |
| Any ZeroInt64Value WKT JSON stringify | 210.85 | — | — | 1319.35 (6.26x) | 1060.65 (5.03x) |
| Any ZeroInt64Value WKT JSON parse | 623.55 | — | — | 3228.58 (5.18x) | 2040.51 (3.27x) |
| Any NegativeInt64Value WKT JSON stringify | 223.01 | — | — | 2209.72 (9.91x) | 1178.99 (5.29x) |
| Any NegativeInt64Value WKT JSON parse | 656.32 | — | — | 4314.91 (6.57x) | 2302.90 (3.51x) |
| Any MinInt64Value WKT JSON stringify | 226.33 | — | — | 2230.91 (9.86x) | 1197.76 (5.29x) |
| Any MinInt64Value WKT JSON parse | 664.04 | — | — | 4327.59 (6.52x) | 2422.97 (3.65x) |
| Any MaxInt64Value WKT JSON stringify | 227.84 | — | — | 2225.82 (9.77x) | 1188.69 (5.22x) |
| Any MaxInt64Value WKT JSON parse | 677.20 | — | — | 4377.68 (6.46x) | 2315.33 (3.42x) |
| Any UInt64Value WKT JSON stringify | 228.76 | — | — | 2240.56 (9.79x) | 1155.09 (5.05x) |
| Any UInt64Value WKT JSON parse | 679.52 | — | — | 4317.78 (6.35x) | 2236.59 (3.29x) |
| Any ZeroUInt64Value WKT JSON stringify | 219.18 | — | — | 1325.45 (6.05x) | 1007.79 (4.60x) |
| Any ZeroUInt64Value WKT JSON parse | 616.75 | — | — | 3223.44 (5.23x) | 1991.45 (3.23x) |
| Any MaxUInt64Value WKT JSON stringify | 236.22 | — | — | 2227.51 (9.43x) | 1142.38 (4.84x) |
| Any MaxUInt64Value WKT JSON parse | 678.51 | — | — | 4362.76 (6.43x) | 2303.51 (3.39x) |
| Any Int32Value WKT JSON stringify | 222.31 | — | — | 2303.45 (10.36x) | 875.88 (3.94x) |
| Any Int32Value WKT JSON parse | 623.43 | — | — | 4159.75 (6.67x) | 2012.28 (3.23x) |
| Any ZeroInt32Value WKT JSON stringify | 221.89 | — | — | 1311.46 (5.91x) | 819.95 (3.70x) |
| Any ZeroInt32Value WKT JSON parse | 616.54 | — | — | 3234.52 (5.25x) | 1926.65 (3.12x) |
| Any NegativeInt32Value WKT JSON stringify | 228.54 | — | — | 2327.68 (10.19x) | 871.12 (3.81x) |
| Any NegativeInt32Value WKT JSON parse | 619.82 | — | — | 4218.96 (6.81x) | 2036.62 (3.29x) |
| Any MinInt32Value WKT JSON stringify | 227.62 | — | — | 2270.11 (9.97x) | 859.46 (3.78x) |
| Any MinInt32Value WKT JSON parse | 635.25 | — | — | 4234.83 (6.67x) | 2101.10 (3.31x) |
| Any MaxInt32Value WKT JSON stringify | 224.87 | — | — | 2289.97 (10.18x) | 852.81 (3.79x) |
| Any MaxInt32Value WKT JSON parse | 637.56 | — | — | 4116.62 (6.46x) | 2003.50 (3.14x) |
| Any UInt32Value WKT JSON stringify | 231.11 | — | — | 2233.21 (9.66x) | 904.32 (3.91x) |
| Any UInt32Value WKT JSON parse | 627.83 | — | — | 4142.40 (6.60x) | 1984.17 (3.16x) |
| Any ZeroUInt32Value WKT JSON stringify | 229.95 | — | — | 1303.63 (5.67x) | 826.33 (3.59x) |
| Any ZeroUInt32Value WKT JSON parse | 621.11 | — | — | 3180.18 (5.12x) | 1917.79 (3.09x) |
| Any MaxUInt32Value WKT JSON stringify | 233.65 | — | — | 2242.70 (9.60x) | 888.53 (3.80x) |
| Any MaxUInt32Value WKT JSON parse | 641.88 | — | — | 4151.40 (6.47x) | 2001.71 (3.12x) |
| Any BoolValue WKT JSON stringify | 224.45 | — | — | 2236.81 (9.97x) | 829.18 (3.69x) |
| Any BoolValue WKT JSON parse | 579.46 | — | — | 4019.71 (6.94x) | 1734.07 (2.99x) |
| Any FalseBoolValue WKT JSON stringify | 224.98 | — | — | 1339.35 (5.95x) | 814.16 (3.62x) |
| Any FalseBoolValue WKT JSON parse | 577.84 | — | — | 3241.18 (5.61x) | 1704.72 (2.95x) |
| Any StringValue WKT JSON stringify | 265.40 | — | — | 2204.64 (8.31x) | 908.34 (3.42x) |
| Any StringValue WKT JSON parse | 641.70 | — | — | 4048.33 (6.31x) | 1891.32 (2.95x) |
| Any EmptyStringValue WKT JSON stringify | 249.26 | — | — | 1325.52 (5.32x) | 895.98 (3.59x) |
| Any EmptyStringValue WKT JSON parse | 604.73 | — | — | 3259.31 (5.39x) | 1668.38 (2.76x) |
| Any BytesValue WKT JSON stringify | 241.50 | — | — | 2279.49 (9.44x) | 1027.40 (4.25x) |
| Any BytesValue WKT JSON parse | 656.54 | — | — | 4245.07 (6.47x) | 1956.96 (2.98x) |
| Any EmptyBytesValue WKT JSON stringify | 235.10 | — | — | 1298.67 (5.52x) | 862.93 (3.67x) |
| Any EmptyBytesValue WKT JSON parse | 612.16 | — | — | 3205.12 (5.24x) | 1790.29 (2.92x) |
| Nested Any WKT JSON stringify | 422.41 | — | — | 3395.35 (8.04x) | 1646.04 (3.90x) |
| Nested Any WKT JSON parse | 1051.08 | — | — | 6155.61 (5.86x) | 3563.06 (3.39x) |
| Duration JSON stringify | 68.31 | — | — | 1539.44 (22.54x) | 409.44 (5.99x) |
| Duration JSON parse | 13.03 | — | — | 2305.20 (176.91x) | 416.01 (31.93x) |
| NegativeDuration JSON stringify | 69.30 | — | — | 1611.13 (23.25x) | 460.63 (6.65x) |
| NegativeDuration JSON parse | 13.19 | — | — | 2396.36 (181.68x) | 422.80 (32.05x) |
| FractionalNegativeDuration JSON stringify | 68.59 | — | — | 1540.33 (22.46x) | 463.60 (6.76x) |
| FractionalNegativeDuration JSON parse | 13.68 | — | — | 2319.55 (169.56x) | 407.30 (29.77x) |
| MaxDuration JSON stringify | 57.62 | — | — | 1264.42 (21.94x) | 449.31 (7.80x) |
| MaxDuration JSON parse | 29.95 | — | — | 2245.64 (74.98x) | 436.21 (14.56x) |
| MinDuration JSON stringify | 56.93 | — | — | 1296.49 (22.77x) | 480.03 (8.43x) |
| MinDuration JSON parse | 30.39 | — | — | 2257.57 (74.29x) | 435.16 (14.32x) |
| ZeroDuration JSON stringify | 51.75 | — | — | 1259.42 (24.34x) | 354.51 (6.85x) |
| ZeroDuration JSON parse | 9.36 | — | — | 2140.90 (228.73x) | 336.29 (35.93x) |
| FieldMask JSON stringify | 96.58 | — | — | 1300.86 (13.47x) | 755.61 (7.82x) |
| FieldMask JSON parse | 187.61 | — | — | 2696.16 (14.37x) | 1041.01 (5.55x) |
| Timestamp JSON stringify | 134.28 | — | — | 1689.11 (12.58x) | 472.19 (3.52x) |
| Timestamp JSON parse | 58.74 | — | — | 2321.26 (39.52x) | 483.94 (8.24x) |
| PreEpoch Timestamp JSON stringify | 89.85 | — | — | 1554.29 (17.30x) | 467.91 (5.21x) |
| PreEpoch Timestamp JSON parse | 56.26 | — | — | 2264.57 (40.25x) | 462.65 (8.22x) |
| Max Timestamp JSON stringify | 108.41 | — | — | 1726.23 (15.92x) | 468.22 (4.32x) |
| Max Timestamp JSON parse | 66.28 | — | — | 2357.46 (35.57x) | 490.90 (7.41x) |
| Min Timestamp JSON stringify | 122.03 | — | — | 1592.40 (13.05x) | 458.61 (3.76x) |
| Min Timestamp JSON parse | 54.33 | — | — | 2279.45 (41.96x) | 456.60 (8.40x) |
| Empty JSON stringify | 23.99 | — | — | 710.68 (29.62x) | 104.57 (4.36x) |
| Empty JSON parse | 76.58 | — | — | 1107.60 (14.46x) | 255.33 (3.33x) |
| Struct JSON stringify | 285.30 | — | — | 8884.02 (31.14x) | 3891.58 (13.64x) |
| Struct JSON parse | 991.22 | — | — | 16656.70 (16.80x) | 6254.76 (6.31x) |
| Value JSON stringify | 287.59 | — | — | 9922.95 (34.50x) | 4069.73 (14.15x) |
| Value JSON parse | 982.17 | — | — | 17898.50 (18.22x) | 6545.21 (6.66x) |
| ListValue JSON stringify | 207.62 | — | — | 7553.26 (36.38x) | 2695.88 (12.98x) |
| ListValue JSON parse | 766.87 | — | — | 13388.30 (17.46x) | 5239.81 (6.83x) |
| DoubleValue JSON stringify | 99.43 | — | — | 1474.26 (14.83x) | 204.56 (2.06x) |
| DoubleValue JSON parse | 118.30 | — | — | 2126.44 (17.97x) | 322.34 (2.72x) |
| NegativeDoubleValue JSON stringify | 99.43 | — | — | 1486.33 (14.95x) | 218.98 (2.20x) |
| NegativeDoubleValue JSON parse | 118.74 | — | — | 2148.38 (18.09x) | 313.58 (2.64x) |
| ZeroDoubleValue JSON stringify | 55.01 | — | — | 1360.92 (24.74x) | 174.88 (3.18x) |
| ZeroDoubleValue JSON parse | 119.85 | — | — | 1892.64 (15.79x) | 310.72 (2.59x) |
| DoubleValue NaN JSON stringify | 55.34 | — | — | 986.90 (17.83x) | 157.89 (2.85x) |
| DoubleValue NaN JSON parse | 107.76 | — | — | 1697.56 (15.75x) | 305.69 (2.84x) |
| DoubleValue Infinity JSON stringify | 59.76 | — | — | 990.55 (16.58x) | 151.96 (2.54x) |
| DoubleValue Infinity JSON parse | 108.97 | — | — | 1722.19 (15.80x) | 320.01 (2.94x) |
| DoubleValue NegativeInfinity JSON stringify | 60.72 | — | — | 970.56 (15.98x) | 155.73 (2.56x) |
| DoubleValue NegativeInfinity JSON parse | 113.86 | — | — | 1753.12 (15.40x) | 318.94 (2.80x) |
| FloatValue JSON stringify | 103.87 | — | — | 1398.74 (13.47x) | 201.53 (1.94x) |
| FloatValue JSON parse | 118.59 | — | — | 2129.09 (17.95x) | 316.69 (2.67x) |
| NegativeFloatValue JSON stringify | 104.56 | — | — | 1404.61 (13.43x) | 211.37 (2.02x) |
| NegativeFloatValue JSON parse | 119.33 | — | — | 2146.63 (17.99x) | 317.81 (2.66x) |
| ZeroFloatValue JSON stringify | 55.65 | — | — | 1336.08 (24.01x) | 173.18 (3.11x) |
| ZeroFloatValue JSON parse | 121.08 | — | — | 1879.55 (15.52x) | 291.58 (2.41x) |
| FloatValue NaN JSON stringify | 56.06 | — | — | 956.18 (17.06x) | 145.31 (2.59x) |
| FloatValue NaN JSON parse | 106.80 | — | — | 1729.19 (16.19x) | 296.52 (2.78x) |
| FloatValue Infinity JSON stringify | 59.30 | — | — | 955.82 (16.12x) | 161.94 (2.73x) |
| FloatValue Infinity JSON parse | 110.64 | — | — | 1756.47 (15.88x) | 299.11 (2.70x) |
| FloatValue NegativeInfinity JSON stringify | 60.71 | — | — | 951.10 (15.67x) | 154.46 (2.54x) |
| FloatValue NegativeInfinity JSON parse | 114.31 | — | — | 1777.80 (15.55x) | 321.99 (2.82x) |
| Int64Value JSON stringify | 57.05 | — | — | 1009.82 (17.70x) | 309.30 (5.42x) |
| Int64Value JSON parse | 154.62 | — | — | 1973.64 (12.76x) | 509.63 (3.30x) |
| ZeroInt64Value JSON stringify | 46.80 | — | — | 942.51 (20.14x) | 202.32 (4.32x) |
| ZeroInt64Value JSON parse | 108.59 | — | — | 1826.02 (16.82x) | 382.59 (3.52x) |
| NegativeInt64Value JSON stringify | 56.71 | — | — | 999.28 (17.62x) | 307.36 (5.42x) |
| NegativeInt64Value JSON parse | 155.58 | — | — | 1965.99 (12.64x) | 524.53 (3.37x) |
| MinInt64Value JSON stringify | 60.83 | — | — | 1004.32 (16.51x) | 327.65 (5.39x) |
| MinInt64Value JSON parse | 166.06 | — | — | 2006.08 (12.08x) | 535.49 (3.22x) |
| MaxInt64Value JSON stringify | 60.49 | — | — | 1006.34 (16.64x) | 321.25 (5.31x) |
| MaxInt64Value JSON parse | 165.08 | — | — | 1995.85 (12.09x) | 511.85 (3.10x) |
| UInt64Value JSON stringify | 56.32 | — | — | 1007.09 (17.88x) | 297.25 (5.28x) |
| UInt64Value JSON parse | 155.25 | — | — | 1988.72 (12.81x) | 486.56 (3.13x) |
| ZeroUInt64Value JSON stringify | 45.13 | — | — | 943.04 (20.90x) | 203.05 (4.50x) |
| ZeroUInt64Value JSON parse | 107.31 | — | — | 1809.58 (16.86x) | 366.07 (3.41x) |
| MaxUInt64Value JSON stringify | 60.58 | — | — | 1009.29 (16.66x) | 321.67 (5.31x) |
| MaxUInt64Value JSON parse | 168.62 | — | — | 2018.01 (11.97x) | 518.27 (3.07x) |
| Int32Value JSON stringify | 50.48 | — | — | 986.01 (19.53x) | 162.47 (3.22x) |
| Int32Value JSON parse | 133.69 | — | — | 1909.23 (14.28x) | 334.94 (2.51x) |
| ZeroInt32Value JSON stringify | 51.27 | — | — | 975.94 (19.04x) | 157.86 (3.08x) |
| ZeroInt32Value JSON parse | 128.20 | — | — | 1866.43 (14.56x) | 293.68 (2.29x) |
| NegativeInt32Value JSON stringify | 50.51 | — | — | 1010.43 (20.00x) | 160.65 (3.18x) |
| NegativeInt32Value JSON parse | 131.66 | — | — | 1925.02 (14.62x) | 354.78 (2.69x) |
| MinInt32Value JSON stringify | 50.68 | — | — | 1001.00 (19.75x) | 175.56 (3.46x) |
| MinInt32Value JSON parse | 141.91 | — | — | 1918.89 (13.52x) | 386.83 (2.73x) |
| MaxInt32Value JSON stringify | 50.75 | — | — | 986.55 (19.44x) | 172.61 (3.40x) |
| MaxInt32Value JSON parse | 144.51 | — | — | 1928.21 (13.34x) | 356.46 (2.47x) |
| UInt32Value JSON stringify | 50.04 | — | — | 915.21 (18.29x) | 167.88 (3.35x) |
| UInt32Value JSON parse | 134.12 | — | — | 1897.50 (14.15x) | 349.85 (2.61x) |
| ZeroUInt32Value JSON stringify | 49.99 | — | — | 918.17 (18.37x) | 176.67 (3.53x) |
| ZeroUInt32Value JSON parse | 128.25 | — | — | 1845.55 (14.39x) | 311.79 (2.43x) |
| MaxUInt32Value JSON stringify | 50.50 | — | — | 947.60 (18.76x) | 184.85 (3.66x) |
| MaxUInt32Value JSON parse | 144.42 | — | — | 1934.54 (13.40x) | 375.33 (2.60x) |
| BoolValue JSON stringify | 48.91 | — | — | 912.14 (18.65x) | 141.41 (2.89x) |
| BoolValue JSON parse | 61.15 | — | — | 1712.43 (28.00x) | 248.29 (4.06x) |
| FalseBoolValue JSON stringify | 49.14 | — | — | 913.47 (18.59x) | 154.48 (3.14x) |
| FalseBoolValue JSON parse | 61.39 | — | — | 1751.99 (28.54x) | 247.88 (4.04x) |
| StringValue JSON stringify | 60.73 | — | — | 1023.85 (16.86x) | 210.50 (3.47x) |
| StringValue JSON parse | 135.71 | — | — | 1836.75 (13.53x) | 355.45 (2.62x) |
| EmptyStringValue JSON stringify | 55.16 | — | — | 953.01 (17.28x) | 210.39 (3.81x) |
| EmptyStringValue JSON parse | 76.28 | — | — | 1796.23 (23.55x) | 260.18 (3.41x) |
| BytesValue JSON stringify | 51.86 | — | — | 992.55 (19.14x) | 249.91 (4.82x) |
| BytesValue JSON parse | 149.75 | — | — | 1988.74 (13.28x) | 376.90 (2.52x) |
| EmptyBytesValue JSON stringify | 45.25 | — | — | 980.24 (21.66x) | 208.86 (4.62x) |
| EmptyBytesValue JSON parse | 86.68 | — | — | 1878.80 (21.68x) | 337.42 (3.89x) |
| TextFormat parse | 899.31 | — | — | 5392.59 (6.00x) | 8018.85 (8.92x) |
| packed bool encode | 2.26 | 2080.19 (920.44x) | 539.42 (238.68x) | 22.84 (10.11x) | 4382.35 (1939.09x) |
| packed bool decode | 271.59 | 2054.52 (7.56x) | 4214.53 (15.52x) | 1107.74 (4.08x) | 2674.02 (9.85x) |
| shuffled large map deterministic binary encode | 37154.30 | — | — | 114363.00 (3.08x) | 459744.76 (12.37x) |
| large map decode | 40611.43 | 127372.38 (3.14x) | 129316.34 (3.18x) | 117406.00 (2.89x) | 301493.19 (7.42x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded zero/positive/integer-negative/fractional-negative/min-max-bound `Duration`, `Struct`, `Value`,
`FieldMask`, min/pre/post/max-bound `Timestamp`, `Empty`, min/zero/positive/negative/max `Int64Value`, negative/zero/positive finite `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), negative/zero/positive finite `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), zero/normal/max `UInt64Value`, min/zero/positive/negative/max `Int32Value`, zero/normal/max `UInt32Value`, true/false `BoolValue`, non-empty/empty `StringValue`, base64/empty `BytesValue`, and recursive nested `Any` payloads), direct zero/positive/integer-negative/fractional-negative/min-max-bound Duration and min/pre/post/max-bound Timestamp WKT JSON plus other direct WKT JSON, TextFormat, packed scalars, large bytes,
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
