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

Latest accepted comparison (`/tmp/pbz-compare-empty-struct-list-json-isolated.log`,
summarized in `/tmp/pbz-summary-empty-struct-list-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 24.61 | 124.91 (5.08x) | 64.13 (2.61x) | 129.56 (5.26x) | 954.63 (38.79x) |
| binary decode | 128.87 | 295.90 (2.30x) | 298.07 (2.31x) | 267.58 (2.08x) | 1090.06 (8.46x) |
| unknown fields count by number | 5.02 | — | — | 178.86 (35.63x) | — |
| deterministic binary encode | 66.96 | — | — | 156.77 (2.34x) | 1287.90 (19.23x) |
| scalarmix encode | 26.07 | 112.83 (4.33x) | 69.58 (2.67x) | 45.43 (1.74x) | 245.09 (9.40x) |
| scalarmix decode | 55.95 | 163.27 (2.92x) | 212.37 (3.80x) | 110.05 (1.97x) | 393.07 (7.03x) |
| textbytes encode | 11.94 | 90.06 (7.54x) | 43.29 (3.63x) | 147.67 (12.37x) | 173.28 (14.51x) |
| textbytes decode | 59.82 | 474.11 (7.93x) | 313.77 (5.25x) | 203.54 (3.40x) | 845.87 (14.14x) |
| largebytes encode | 23.34 | 3896.94 (166.96x) | 3802.89 (162.93x) | 3837.81 (164.43x) | 4156.21 (178.07x) |
| largebytes decode | 139.63 | 8385.33 (60.05x) | 4518.58 (32.36x) | 4128.78 (29.57x) | 24899.98 (178.33x) |
| presencemix encode | 23.06 | 65.57 (2.84x) | 36.84 (1.60x) | 70.82 (3.07x) | 258.07 (11.19x) |
| presencemix decode | 66.25 | 160.70 (2.43x) | 142.99 (2.16x) | 198.60 (3.00x) | 557.42 (8.41x) |
| complex encode | 66.10 | 164.77 (2.49x) | 117.13 (1.77x) | 210.43 (3.18x) | 1005.17 (15.21x) |
| complex decode | 212.79 | 462.18 (2.17x) | 430.43 (2.02x) | 487.51 (2.29x) | 1610.35 (7.57x) |
| complex deterministic binary encode | 125.48 | — | — | 225.02 (1.79x) | 1270.61 (10.13x) |
| complex JSON stringify | 372.31 | — | — | 7079.50 (19.02x) | 7562.27 (20.31x) |
| complex JSON parse | 2702.10 | — | — | 16533.80 (6.12x) | 10563.87 (3.91x) |
| complex TextFormat format | 337.27 | — | — | 4790.05 (14.20x) | 6715.93 (19.91x) |
| complex TextFormat parse | 2271.39 | — | — | 7994.63 (3.52x) | 11580.63 (5.10x) |
| packed int32 encode | 903.97 | 5393.83 (5.97x) | 3023.16 (3.34x) | 2267.74 (2.51x) | 5706.21 (6.31x) |
| packed int32 decode | 994.91 | 2994.89 (3.01x) | 4233.57 (4.26x) | 1342.00 (1.35x) | 4385.56 (4.41x) |
| JSON stringify | 201.40 | — | — | 4871.17 (24.19x) | 2871.18 (14.26x) |
| JSON parse | 1692.47 | — | — | 10679.20 (6.31x) | 5806.84 (3.43x) |
| Any WKT JSON stringify | 176.47 | — | — | 3073.08 (17.41x) | 1420.34 (8.05x) |
| Any WKT JSON parse | 569.70 | — | — | 4648.96 (8.16x) | 2150.59 (3.77x) |
| Any NegativeDuration WKT JSON stringify | 184.30 | — | — | 3073.80 (16.68x) | 1482.02 (8.04x) |
| Any NegativeDuration WKT JSON parse | 579.44 | — | — | 4705.03 (8.12x) | 2243.98 (3.87x) |
| Any FractionalNegativeDuration WKT JSON stringify | 175.77 | — | — | 3065.90 (17.44x) | 1411.86 (8.03x) |
| Any FractionalNegativeDuration WKT JSON parse | 575.20 | — | — | 4689.78 (8.15x) | 2119.88 (3.69x) |
| Any MaxDuration WKT JSON stringify | 164.88 | — | — | 2707.59 (16.42x) | 1366.22 (8.29x) |
| Any MaxDuration WKT JSON parse | 603.64 | — | — | 4482.28 (7.43x) | 2166.17 (3.59x) |
| Any MinDuration WKT JSON stringify | 163.18 | — | — | 2718.42 (16.66x) | 1424.03 (8.73x) |
| Any MinDuration WKT JSON parse | 605.65 | — | — | 4540.30 (7.50x) | 2197.71 (3.63x) |
| Any ZeroDuration WKT JSON stringify | 149.90 | — | — | 1288.80 (8.60x) | 1308.84 (8.73x) |
| Any ZeroDuration WKT JSON parse | 526.01 | — | — | 3274.53 (6.23x) | 1951.83 (3.71x) |
| Any FieldMask WKT JSON stringify | 290.44 | — | — | 2436.54 (8.39x) | 1783.61 (6.14x) |
| Any FieldMask WKT JSON parse | 799.95 | — | — | 4806.36 (6.01x) | 2977.94 (3.72x) |
| Any EmptyFieldMask WKT JSON stringify | 155.34 | — | — | 1282.23 (8.25x) | 899.46 (5.79x) |
| Any EmptyFieldMask WKT JSON parse | 494.14 | — | — | 3160.84 (6.40x) | 1668.45 (3.38x) |
| Any Timestamp WKT JSON stringify | 252.35 | — | — | 3020.67 (11.97x) | 1350.03 (5.35x) |
| Any Timestamp WKT JSON parse | 646.01 | — | — | 4644.00 (7.19x) | 2298.69 (3.56x) |
| Any PreEpoch Timestamp WKT JSON stringify | 196.90 | — | — | 2907.23 (14.77x) | 1359.18 (6.90x) |
| Any PreEpoch Timestamp WKT JSON parse | 624.34 | — | — | 4638.57 (7.43x) | 2294.68 (3.68x) |
| Any Max Timestamp WKT JSON stringify | 220.72 | — | — | 3028.39 (13.72x) | 1337.84 (6.06x) |
| Any Max Timestamp WKT JSON parse | 656.33 | — | — | 4838.11 (7.37x) | 2325.29 (3.54x) |
| Any Min Timestamp WKT JSON stringify | 231.97 | — | — | 2920.10 (12.59x) | 1318.11 (5.68x) |
| Any Min Timestamp WKT JSON parse | 622.88 | — | — | 4735.52 (7.60x) | 2247.67 (3.61x) |
| Any Empty WKT JSON stringify | 122.57 | — | — | 1292.44 (10.54x) | 704.67 (5.75x) |
| Any Empty WKT JSON parse | 376.77 | — | — | 3145.36 (8.35x) | 1692.10 (4.49x) |
| Any Struct WKT JSON stringify | 791.73 | — | — | 8984.83 (11.35x) | 8817.46 (11.14x) |
| Any Struct WKT JSON parse | 1977.09 | — | — | 16629.70 (8.41x) | 12763.13 (6.46x) |
| Any EmptyStruct WKT JSON stringify | 159.36 | — | — | 1265.50 (7.94x) | 1269.09 (7.96x) |
| Any EmptyStruct WKT JSON parse | 501.24 | — | — | 3275.27 (6.53x) | 2282.02 (4.55x) |
| Any Value WKT JSON stringify | 827.37 | — | — | 9128.92 (11.03x) | 9163.87 (11.08x) |
| Any Value WKT JSON parse | 2022.35 | — | — | 17319.80 (8.56x) | 13233.13 (6.54x) |
| Any NullValue WKT JSON stringify | 165.90 | — | — | 3269.97 (19.71x) | 1281.20 (7.72x) |
| Any NullValue WKT JSON parse | 514.92 | — | — | 6235.65 (12.11x) | 2300.12 (4.47x) |
| Any StringScalarValue WKT JSON stringify | 194.72 | — | — | 3225.53 (16.56x) | 1450.69 (7.45x) |
| Any StringScalarValue WKT JSON parse | 567.15 | — | — | 5371.00 (9.47x) | 2424.73 (4.28x) |
| Any NumberValue WKT JSON stringify | 237.67 | — | — | 3958.30 (16.65x) | 1557.45 (6.55x) |
| Any NumberValue WKT JSON parse | 551.02 | — | — | 5739.17 (10.42x) | 2470.74 (4.48x) |
| Any BoolScalarValue WKT JSON stringify | 165.31 | — | — | 3230.80 (19.54x) | 1324.86 (8.01x) |
| Any BoolScalarValue WKT JSON parse | 517.10 | — | — | 5395.57 (10.43x) | 2229.42 (4.31x) |
| Any DoubleValue WKT JSON stringify | 253.63 | — | — | 2855.87 (11.26x) | 1016.91 (4.01x) |
| Any DoubleValue WKT JSON parse | 572.35 | — | — | 4355.06 (7.61x) | 2055.15 (3.59x) |
| Any NegativeDoubleValue WKT JSON stringify | 252.69 | — | — | 2814.33 (11.14x) | 953.96 (3.78x) |
| Any NegativeDoubleValue WKT JSON parse | 572.76 | — | — | 4351.24 (7.60x) | 2020.26 (3.53x) |
| Any ZeroDoubleValue WKT JSON stringify | 203.51 | — | — | 1263.30 (6.21x) | 845.24 (4.15x) |
| Any ZeroDoubleValue WKT JSON parse | 572.73 | — | — | 3184.68 (5.56x) | 1924.95 (3.36x) |
| Any DoubleValue NaN WKT JSON stringify | 200.31 | — | — | 2300.53 (11.48x) | 834.71 (4.17x) |
| Any DoubleValue NaN WKT JSON parse | 568.83 | — | — | 4058.41 (7.13x) | 1918.98 (3.37x) |
| Any DoubleValue Infinity WKT JSON stringify | 203.83 | — | — | 2261.37 (11.09x) | 847.97 (4.16x) |
| Any DoubleValue Infinity WKT JSON parse | 574.18 | — | — | 4067.36 (7.08x) | 1962.42 (3.42x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 207.32 | — | — | 2261.46 (10.91x) | 841.80 (4.06x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 578.67 | — | — | 4087.77 (7.06x) | 1982.33 (3.43x) |
| Any FloatValue WKT JSON stringify | 257.98 | — | — | 2755.96 (10.68x) | 976.58 (3.79x) |
| Any FloatValue WKT JSON parse | 575.37 | — | — | 4309.81 (7.49x) | 2005.18 (3.49x) |
| Any NegativeFloatValue WKT JSON stringify | 260.57 | — | — | 2747.34 (10.54x) | 974.98 (3.74x) |
| Any NegativeFloatValue WKT JSON parse | 575.37 | — | — | 4330.05 (7.53x) | 1978.70 (3.44x) |
| Any ZeroFloatValue WKT JSON stringify | 205.52 | — | — | 1275.83 (6.21x) | 838.43 (4.08x) |
| Any ZeroFloatValue WKT JSON parse | 576.91 | — | — | 3209.87 (5.56x) | 1912.94 (3.32x) |
| Any FloatValue NaN WKT JSON stringify | 199.15 | — | — | 2174.93 (10.92x) | 821.11 (4.12x) |
| Any FloatValue NaN WKT JSON parse | 578.87 | — | — | 3971.56 (6.86x) | 1870.41 (3.23x) |
| Any FloatValue Infinity WKT JSON stringify | 207.48 | — | — | 2124.85 (10.24x) | 829.49 (4.00x) |
| Any FloatValue Infinity WKT JSON parse | 579.19 | — | — | 3951.13 (6.82x) | 1921.70 (3.32x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 208.63 | — | — | 2145.33 (10.28x) | 835.44 (4.00x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 582.40 | — | — | 3998.69 (6.87x) | 1902.71 (3.27x) |
| Any Int64Value WKT JSON stringify | 204.90 | — | — | 2184.86 (10.66x) | 1159.91 (5.66x) |
| Any Int64Value WKT JSON parse | 622.40 | — | — | 4176.38 (6.71x) | 2330.73 (3.74x) |
| Any ZeroInt64Value WKT JSON stringify | 194.86 | — | — | 1300.44 (6.67x) | 1045.39 (5.36x) |
| Any ZeroInt64Value WKT JSON parse | 575.15 | — | — | 3174.29 (5.52x) | 2065.18 (3.59x) |
| Any NegativeInt64Value WKT JSON stringify | 205.39 | — | — | 2215.59 (10.79x) | 1184.60 (5.77x) |
| Any NegativeInt64Value WKT JSON parse | 621.13 | — | — | 4202.25 (6.77x) | 2349.04 (3.78x) |
| Any MinInt64Value WKT JSON stringify | 211.10 | — | — | 2172.35 (10.29x) | 1182.21 (5.60x) |
| Any MinInt64Value WKT JSON parse | 631.72 | — | — | 4288.68 (6.79x) | 2386.70 (3.78x) |
| Any MaxInt64Value WKT JSON stringify | 209.40 | — | — | 2188.04 (10.45x) | 1177.74 (5.62x) |
| Any MaxInt64Value WKT JSON parse | 633.32 | — | — | 4278.53 (6.76x) | 2303.98 (3.64x) |
| Any UInt64Value WKT JSON stringify | 213.73 | — | — | 2211.53 (10.35x) | 1170.48 (5.48x) |
| Any UInt64Value WKT JSON parse | 627.06 | — | — | 4221.44 (6.73x) | 2275.88 (3.63x) |
| Any ZeroUInt64Value WKT JSON stringify | 203.94 | — | — | 1279.73 (6.28x) | 1024.78 (5.02x) |
| Any ZeroUInt64Value WKT JSON parse | 580.79 | — | — | 3164.94 (5.45x) | 2079.63 (3.58x) |
| Any MaxUInt64Value WKT JSON stringify | 219.22 | — | — | 2202.12 (10.05x) | 1175.05 (5.36x) |
| Any MaxUInt64Value WKT JSON parse | 641.24 | — | — | 4308.67 (6.72x) | 2336.51 (3.64x) |
| Any Int32Value WKT JSON stringify | 210.94 | — | — | 2220.85 (10.53x) | 879.46 (4.17x) |
| Any Int32Value WKT JSON parse | 596.72 | — | — | 4129.68 (6.92x) | 2095.88 (3.51x) |
| Any ZeroInt32Value WKT JSON stringify | 207.69 | — | — | 1268.43 (6.11x) | 846.91 (4.08x) |
| Any ZeroInt32Value WKT JSON parse | 593.46 | — | — | 3193.37 (5.38x) | 1991.74 (3.36x) |
| Any NegativeInt32Value WKT JSON stringify | 215.36 | — | — | 2220.61 (10.31x) | 886.90 (4.12x) |
| Any NegativeInt32Value WKT JSON parse | 595.21 | — | — | 4168.16 (7.00x) | 2079.32 (3.49x) |
| Any MinInt32Value WKT JSON stringify | 216.81 | — | — | 2196.22 (10.13x) | 893.87 (4.12x) |
| Any MinInt32Value WKT JSON parse | 605.31 | — | — | 4153.35 (6.86x) | 2152.09 (3.56x) |
| Any MaxInt32Value WKT JSON stringify | 211.28 | — | — | 2237.68 (10.59x) | 872.59 (4.13x) |
| Any MaxInt32Value WKT JSON parse | 608.30 | — | — | 4144.57 (6.81x) | 2046.57 (3.36x) |
| Any UInt32Value WKT JSON stringify | 217.84 | — | — | 2164.11 (9.93x) | 911.53 (4.18x) |
| Any UInt32Value WKT JSON parse | 598.68 | — | — | 4104.67 (6.86x) | 1975.20 (3.30x) |
| Any ZeroUInt32Value WKT JSON stringify | 214.00 | — | — | 1273.42 (5.95x) | 862.81 (4.03x) |
| Any ZeroUInt32Value WKT JSON parse | 591.72 | — | — | 3187.02 (5.39x) | 1885.53 (3.19x) |
| Any MaxUInt32Value WKT JSON stringify | 218.96 | — | — | 2147.08 (9.81x) | 973.33 (4.45x) |
| Any MaxUInt32Value WKT JSON parse | 611.70 | — | — | 4101.15 (6.70x) | 2009.11 (3.28x) |
| Any BoolValue WKT JSON stringify | 212.58 | — | — | 2100.67 (9.88x) | 859.03 (4.04x) |
| Any BoolValue WKT JSON parse | 549.56 | — | — | 3960.66 (7.21x) | 1758.74 (3.20x) |
| Any FalseBoolValue WKT JSON stringify | 208.92 | — | — | 1269.66 (6.08x) | 853.09 (4.08x) |
| Any FalseBoolValue WKT JSON parse | 554.90 | — | — | 3140.83 (5.66x) | 1662.03 (3.00x) |
| Any StringValue WKT JSON stringify | 245.62 | — | — | 2272.78 (9.25x) | 969.92 (3.95x) |
| Any StringValue WKT JSON parse | 609.80 | — | — | 4107.27 (6.74x) | 1936.34 (3.18x) |
| Any EmptyStringValue WKT JSON stringify | 224.07 | — | — | 1294.14 (5.78x) | 858.11 (3.83x) |
| Any EmptyStringValue WKT JSON parse | 571.25 | — | — | 3198.30 (5.60x) | 1674.68 (2.93x) |
| Any BytesValue WKT JSON stringify | 224.87 | — | — | 2288.62 (10.18x) | 966.48 (4.30x) |
| Any BytesValue WKT JSON parse | 616.84 | — | — | 4236.87 (6.87x) | 1959.08 (3.18x) |
| Any EmptyBytesValue WKT JSON stringify | 220.03 | — | — | 1284.13 (5.84x) | 850.04 (3.86x) |
| Any EmptyBytesValue WKT JSON parse | 577.71 | — | — | 3151.06 (5.45x) | 1807.51 (3.13x) |
| Nested Any WKT JSON stringify | 383.66 | — | — | 3408.51 (8.88x) | 1782.27 (4.65x) |
| Nested Any WKT JSON parse | 994.60 | — | — | 6064.96 (6.10x) | 3617.88 (3.64x) |
| Duration JSON stringify | 64.61 | — | — | 1531.32 (23.70x) | 406.65 (6.29x) |
| Duration JSON parse | 12.21 | — | — | 2331.04 (190.91x) | 447.73 (36.67x) |
| NegativeDuration JSON stringify | 64.65 | — | — | 1603.84 (24.81x) | 452.25 (7.00x) |
| NegativeDuration JSON parse | 12.55 | — | — | 2454.42 (195.57x) | 455.58 (36.30x) |
| FractionalNegativeDuration JSON stringify | 64.68 | — | — | 1559.78 (24.12x) | 470.22 (7.27x) |
| FractionalNegativeDuration JSON parse | 12.53 | — | — | 2352.65 (187.76x) | 444.13 (35.45x) |
| MaxDuration JSON stringify | 53.49 | — | — | 1282.17 (23.97x) | 457.67 (8.56x) |
| MaxDuration JSON parse | 29.19 | — | — | 2291.79 (78.51x) | 456.62 (15.64x) |
| MinDuration JSON stringify | 53.85 | — | — | 1319.91 (24.51x) | 472.77 (8.78x) |
| MinDuration JSON parse | 29.43 | — | — | 2275.16 (77.31x) | 454.35 (15.44x) |
| ZeroDuration JSON stringify | 47.72 | — | — | 1240.41 (25.99x) | 424.43 (8.89x) |
| ZeroDuration JSON parse | 8.78 | — | — | 2160.07 (246.02x) | 374.61 (42.67x) |
| FieldMask JSON stringify | 95.70 | — | — | 1293.44 (13.52x) | 758.31 (7.92x) |
| FieldMask JSON parse | 182.68 | — | — | 2664.87 (14.59x) | 1059.55 (5.80x) |
| EmptyFieldMask JSON stringify | 42.25 | — | — | 927.46 (21.95x) | 234.57 (5.55x) |
| EmptyFieldMask JSON parse | 3.52 | — | — | 1415.23 (402.05x) | 223.31 (63.44x) |
| Timestamp JSON stringify | 129.61 | — | — | 1718.69 (13.26x) | 480.82 (3.71x) |
| Timestamp JSON parse | 56.73 | — | — | 2349.42 (41.41x) | 498.47 (8.79x) |
| PreEpoch Timestamp JSON stringify | 84.79 | — | — | 1626.19 (19.18x) | 472.70 (5.57x) |
| PreEpoch Timestamp JSON parse | 54.71 | — | — | 2323.63 (42.47x) | 478.80 (8.75x) |
| Max Timestamp JSON stringify | 103.25 | — | — | 1802.18 (17.45x) | 470.93 (4.56x) |
| Max Timestamp JSON parse | 64.27 | — | — | 2350.97 (36.58x) | 519.01 (8.08x) |
| Min Timestamp JSON stringify | 119.17 | — | — | 1584.41 (13.30x) | 466.43 (3.91x) |
| Min Timestamp JSON parse | 52.63 | — | — | 2272.13 (43.17x) | 473.91 (9.00x) |
| Empty JSON stringify | 22.86 | — | — | 692.85 (30.31x) | 109.03 (4.77x) |
| Empty JSON parse | 72.69 | — | — | 1108.23 (15.25x) | 257.91 (3.55x) |
| Struct JSON stringify | 274.21 | — | — | 8990.86 (32.79x) | 3925.36 (14.32x) |
| Struct JSON parse | 932.37 | — | — | 16459.70 (17.65x) | 6312.86 (6.77x) |
| EmptyStruct JSON stringify | 42.20 | — | — | 1003.86 (23.79x) | 396.53 (9.40x) |
| EmptyStruct JSON parse | 89.93 | — | — | 3388.23 (37.68x) | 441.47 (4.91x) |
| Value JSON stringify | 278.36 | — | — | 10031.80 (36.04x) | 4083.57 (14.67x) |
| Value JSON parse | 954.14 | — | — | 17948.30 (18.81x) | 6611.51 (6.93x) |
| NullValue JSON stringify | 41.61 | — | — | 1765.66 (42.43x) | 243.70 (5.86x) |
| NullValue JSON parse | 58.35 | — | — | 3803.59 (65.19x) | 411.85 (7.06x) |
| StringScalarValue JSON stringify | 54.01 | — | — | 1862.44 (34.48x) | 297.33 (5.51x) |
| StringScalarValue JSON parse | 120.56 | — | — | 3078.47 (25.53x) | 505.97 (4.20x) |
| NumberValue JSON stringify | 112.41 | — | — | 2350.14 (20.91x) | 356.87 (3.17x) |
| NumberValue JSON parse | 116.49 | — | — | 3325.32 (28.55x) | 480.74 (4.13x) |
| BoolScalarValue JSON stringify | 41.58 | — | — | 1741.44 (41.88x) | 230.72 (5.55x) |
| BoolScalarValue JSON parse | 55.18 | — | — | 2960.29 (53.65x) | 386.15 (7.00x) |
| ListValue JSON stringify | 203.03 | — | — | 7479.83 (36.84x) | 2698.81 (13.29x) |
| ListValue JSON parse | 738.60 | — | — | 13506.50 (18.29x) | 5237.20 (7.09x) |
| EmptyListValue JSON stringify | 40.84 | — | — | 994.21 (24.34x) | 249.30 (6.10x) |
| EmptyListValue JSON parse | 130.34 | — | — | 3209.92 (24.63x) | 419.95 (3.22x) |
| DoubleValue JSON stringify | 97.41 | — | — | 1461.94 (15.01x) | 219.04 (2.25x) |
| DoubleValue JSON parse | 113.59 | — | — | 2085.75 (18.36x) | 349.15 (3.07x) |
| NegativeDoubleValue JSON stringify | 97.43 | — | — | 1452.05 (14.90x) | 233.98 (2.40x) |
| NegativeDoubleValue JSON parse | 113.46 | — | — | 2094.94 (18.46x) | 351.75 (3.10x) |
| ZeroDoubleValue JSON stringify | 53.33 | — | — | 1361.33 (25.53x) | 164.69 (3.09x) |
| ZeroDoubleValue JSON parse | 115.97 | — | — | 1841.03 (15.88x) | 319.91 (2.76x) |
| DoubleValue NaN JSON stringify | 52.46 | — | — | 998.99 (19.04x) | 153.31 (2.92x) |
| DoubleValue NaN JSON parse | 100.89 | — | — | 1712.25 (16.97x) | 330.76 (3.28x) |
| DoubleValue Infinity JSON stringify | 56.34 | — | — | 973.65 (17.28x) | 190.15 (3.38x) |
| DoubleValue Infinity JSON parse | 103.92 | — | — | 1703.17 (16.39x) | 349.49 (3.36x) |
| DoubleValue NegativeInfinity JSON stringify | 57.74 | — | — | 972.13 (16.84x) | 160.14 (2.77x) |
| DoubleValue NegativeInfinity JSON parse | 106.88 | — | — | 1729.72 (16.18x) | 366.14 (3.43x) |
| FloatValue JSON stringify | 101.24 | — | — | 1397.37 (13.80x) | 214.72 (2.12x) |
| FloatValue JSON parse | 112.51 | — | — | 2128.25 (18.92x) | 350.29 (3.11x) |
| NegativeFloatValue JSON stringify | 102.17 | — | — | 1379.70 (13.50x) | 211.21 (2.07x) |
| NegativeFloatValue JSON parse | 112.76 | — | — | 2128.62 (18.88x) | 358.71 (3.18x) |
| ZeroFloatValue JSON stringify | 52.53 | — | — | 1312.05 (24.98x) | 165.74 (3.16x) |
| ZeroFloatValue JSON parse | 121.33 | — | — | 1855.95 (15.30x) | 327.61 (2.70x) |
| FloatValue NaN JSON stringify | 52.95 | — | — | 934.00 (17.64x) | 150.93 (2.85x) |
| FloatValue NaN JSON parse | 101.61 | — | — | 1693.58 (16.67x) | 321.28 (3.16x) |
| FloatValue Infinity JSON stringify | 56.34 | — | — | 924.91 (16.42x) | 160.35 (2.85x) |
| FloatValue Infinity JSON parse | 104.47 | — | — | 1719.52 (16.46x) | 327.51 (3.13x) |
| FloatValue NegativeInfinity JSON stringify | 57.79 | — | — | 932.11 (16.13x) | 159.00 (2.75x) |
| FloatValue NegativeInfinity JSON parse | 106.44 | — | — | 1725.96 (16.22x) | 337.32 (3.17x) |
| Int64Value JSON stringify | 54.12 | — | — | 1012.95 (18.72x) | 314.38 (5.81x) |
| Int64Value JSON parse | 137.93 | — | — | 1983.21 (14.38x) | 538.05 (3.90x) |
| ZeroInt64Value JSON stringify | 43.95 | — | — | 905.36 (20.60x) | 217.57 (4.95x) |
| ZeroInt64Value JSON parse | 101.60 | — | — | 1817.83 (17.89x) | 395.87 (3.90x) |
| NegativeInt64Value JSON stringify | 54.00 | — | — | 987.28 (18.28x) | 311.88 (5.78x) |
| NegativeInt64Value JSON parse | 138.85 | — | — | 1924.65 (13.86x) | 542.00 (3.90x) |
| MinInt64Value JSON stringify | 58.44 | — | — | 973.87 (16.66x) | 322.49 (5.52x) |
| MinInt64Value JSON parse | 149.45 | — | — | 1958.15 (13.10x) | 555.41 (3.72x) |
| MaxInt64Value JSON stringify | 58.27 | — | — | 987.85 (16.95x) | 322.79 (5.54x) |
| MaxInt64Value JSON parse | 147.94 | — | — | 1965.85 (13.29x) | 541.13 (3.66x) |
| UInt64Value JSON stringify | 54.07 | — | — | 976.26 (18.06x) | 314.57 (5.82x) |
| UInt64Value JSON parse | 137.95 | — | — | 1927.72 (13.97x) | 519.24 (3.76x) |
| ZeroUInt64Value JSON stringify | 43.20 | — | — | 908.24 (21.02x) | 222.88 (5.16x) |
| ZeroUInt64Value JSON parse | 100.87 | — | — | 1782.48 (17.67x) | 387.13 (3.84x) |
| MaxUInt64Value JSON stringify | 58.06 | — | — | 969.63 (16.70x) | 333.84 (5.75x) |
| MaxUInt64Value JSON parse | 151.17 | — | — | 1994.08 (13.19x) | 548.56 (3.63x) |
| Int32Value JSON stringify | 48.32 | — | — | 957.07 (19.81x) | 162.72 (3.37x) |
| Int32Value JSON parse | 135.20 | — | — | 1879.80 (13.90x) | 368.94 (2.73x) |
| ZeroInt32Value JSON stringify | 48.39 | — | — | 943.39 (19.50x) | 161.80 (3.34x) |
| ZeroInt32Value JSON parse | 129.88 | — | — | 1837.07 (14.14x) | 325.73 (2.51x) |
| NegativeInt32Value JSON stringify | 48.75 | — | — | 968.08 (19.86x) | 159.51 (3.27x) |
| NegativeInt32Value JSON parse | 131.87 | — | — | 1889.00 (14.32x) | 369.63 (2.80x) |
| MinInt32Value JSON stringify | 48.80 | — | — | 961.11 (19.69x) | 190.23 (3.90x) |
| MinInt32Value JSON parse | 142.92 | — | — | 1893.34 (13.25x) | 406.69 (2.85x) |
| MaxInt32Value JSON stringify | 48.41 | — | — | 966.92 (19.97x) | 171.73 (3.55x) |
| MaxInt32Value JSON parse | 146.79 | — | — | 1889.27 (12.87x) | 398.59 (2.72x) |
| UInt32Value JSON stringify | 47.93 | — | — | 902.63 (18.83x) | 165.70 (3.46x) |
| UInt32Value JSON parse | 135.28 | — | — | 1891.48 (13.98x) | 373.32 (2.76x) |
| ZeroUInt32Value JSON stringify | 47.87 | — | — | 898.93 (18.78x) | 159.18 (3.33x) |
| ZeroUInt32Value JSON parse | 129.16 | — | — | 1836.36 (14.22x) | 324.34 (2.51x) |
| MaxUInt32Value JSON stringify | 48.35 | — | — | 897.21 (18.56x) | 167.63 (3.47x) |
| MaxUInt32Value JSON parse | 145.58 | — | — | 1924.48 (13.22x) | 387.73 (2.66x) |
| BoolValue JSON stringify | 46.08 | — | — | 894.77 (19.42x) | 158.92 (3.45x) |
| BoolValue JSON parse | 62.41 | — | — | 1712.00 (27.43x) | 271.72 (4.35x) |
| FalseBoolValue JSON stringify | 46.75 | — | — | 892.58 (19.09x) | 163.12 (3.49x) |
| FalseBoolValue JSON parse | 62.99 | — | — | 1690.31 (26.83x) | 266.77 (4.24x) |
| StringValue JSON stringify | 58.02 | — | — | 1003.22 (17.29x) | 206.89 (3.57x) |
| StringValue JSON parse | 126.31 | — | — | 1814.25 (14.36x) | 376.85 (2.98x) |
| EmptyStringValue JSON stringify | 51.68 | — | — | 947.86 (18.34x) | 221.23 (4.28x) |
| EmptyStringValue JSON parse | 68.82 | — | — | 1766.58 (25.67x) | 285.52 (4.15x) |
| BytesValue JSON stringify | 48.75 | — | — | 965.71 (19.81x) | 254.15 (5.21x) |
| BytesValue JSON parse | 145.40 | — | — | 1945.07 (13.38x) | 403.32 (2.77x) |
| EmptyBytesValue JSON stringify | 43.39 | — | — | 956.95 (22.05x) | 208.56 (4.81x) |
| EmptyBytesValue JSON parse | 85.08 | — | — | 1876.12 (22.05x) | 351.99 (4.14x) |
| TextFormat format | 234.95 | — | — | 3231.85 (13.76x) | 3093.76 (13.17x) |
| TextFormat parse | 846.96 | — | — | 5536.80 (6.54x) | 8086.32 (9.55x) |
| packed fixed32 encode | 2.76 | 807.05 (292.41x) | 628.91 (227.87x) | 90.22 (32.69x) | 569.70 (206.41x) |
| packed fixed32 decode | 7.02 | 2154.66 (306.93x) | 2589.95 (368.94x) | 106.08 (15.11x) | 2057.51 (293.09x) |
| packed fixed64 encode | 2.51 | 709.45 (282.65x) | 633.90 (252.55x) | 154.76 (61.66x) | 570.07 (227.12x) |
| packed fixed64 decode | 7.02 | 1268.67 (180.72x) | 7410.24 (1055.59x) | 171.98 (24.50x) | 3200.83 (455.96x) |
| packed sfixed32 encode | 2.76 | 705.05 (255.45x) | 628.86 (227.85x) | 91.25 (33.06x) | 570.20 (206.59x) |
| packed sfixed32 decode | 7.27 | 1979.74 (272.32x) | 2599.99 (357.63x) | 97.36 (13.39x) | 2005.90 (275.91x) |
| packed sfixed64 encode | 2.26 | 817.38 (361.67x) | 634.14 (280.59x) | 154.83 (68.51x) | 571.31 (252.79x) |
| packed sfixed64 decode | 7.02 | 1223.24 (174.25x) | 7328.42 (1043.93x) | 160.52 (22.87x) | 2713.76 (386.58x) |
| packed float encode | 2.51 | 830.07 (330.71x) | 630.62 (251.24x) | 90.63 (36.11x) | 565.44 (225.27x) |
| packed float decode | 7.07 | 2134.61 (301.93x) | 2649.78 (374.79x) | 97.44 (13.78x) | 1999.22 (282.78x) |
| packed double encode | 2.76 | 857.73 (310.77x) | 634.72 (229.97x) | 154.72 (56.06x) | 566.64 (205.30x) |
| packed double decode | 7.26 | 1222.17 (168.34x) | 2869.80 (395.29x) | 160.48 (22.10x) | 3240.85 (446.40x) |
| packed uint64 encode | 1833.73 | 6975.70 (3.80x) | 6589.37 (3.59x) | 3134.44 (1.71x) | 6138.26 (3.35x) |
| packed uint64 decode | 2588.28 | 4299.62 (1.66x) | 8624.37 (3.33x) | 4552.72 (1.76x) | 11387.84 (4.40x) |
| packed uint32 encode | 1347.61 | 5543.72 (4.11x) | 4411.45 (3.27x) | 2663.62 (1.98x) | 5432.14 (4.03x) |
| packed uint32 decode | 1881.63 | 3624.02 (1.93x) | 4797.91 (2.55x) | 3257.97 (1.73x) | 8776.42 (4.66x) |
| packed int64 encode | 2066.06 | 15644.47 (7.57x) | 7818.79 (3.78x) | 4174.02 (2.02x) | 7586.61 (3.67x) |
| packed int64 decode | 4434.27 | 5680.33 (1.28x) | 10647.29 (2.40x) | 5989.71 (1.35x) | 14740.96 (3.32x) |
| packed sint32 encode | 1091.32 | 4426.20 (4.06x) | 4118.23 (3.77x) | 2631.50 (2.41x) | 5989.18 (5.49x) |
| packed sint32 decode | 1295.86 | 3858.44 (2.98x) | 4693.55 (3.62x) | 1588.57 (1.23x) | 5041.99 (3.89x) |
| packed sint64 encode | 2496.01 | 7595.28 (3.04x) | 6278.02 (2.52x) | 3429.15 (1.37x) | 6714.56 (2.69x) |
| packed sint64 decode | 2846.55 | 4307.86 (1.51x) | 9782.02 (3.44x) | 4783.93 (1.68x) | 12091.54 (4.25x) |
| packed bool encode | 2.51 | 2080.13 (828.74x) | 539.94 (215.12x) | 22.82 (9.09x) | 4386.69 (1747.69x) |
| packed bool decode | 271.63 | 2058.35 (7.58x) | 4047.94 (14.90x) | 1108.04 (4.08x) | 2718.67 (10.01x) |
| packed enum encode | 554.15 | 4926.34 (8.89x) | 2589.53 (4.67x) | 2090.42 (3.77x) | 5027.17 (9.07x) |
| packed enum decode | 276.07 | 2442.65 (8.85x) | 3898.04 (14.12x) | 1001.88 (3.63x) | 3224.45 (11.68x) |
| large map encode | 5544.65 | 22183.05 (4.00x) | 13165.79 (2.37x) | 34989.50 (6.31x) | 240477.72 (43.37x) |
| shuffled large map deterministic binary encode | 35950.51 | — | — | 111193.00 (3.09x) | 456947.04 (12.71x) |
| large map decode | 37650.36 | 130420.42 (3.46x) | 127359.50 (3.38x) | 117347.00 (3.12x) | 294409.72 (7.82x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded zero/positive/integer-negative/fractional-negative/min-max-bound `Duration`, non-empty and empty `Struct`, object/scalar `Value`,
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
