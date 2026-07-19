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

Latest accepted comparison (`/tmp/pbz-compare-default-value-scalars-json-isolated.log`,
summarized in `/tmp/pbz-summary-default-value-scalars-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 23.40 | 128.46 (5.49x) | 69.42 (2.97x) | 129.33 (5.53x) | 945.12 (40.39x) |
| binary decode | 130.28 | 300.70 (2.31x) | 297.23 (2.28x) | 267.04 (2.05x) | 1019.86 (7.83x) |
| unknown fields count by number | 5.02 | — | — | 212.33 (42.30x) | — |
| deterministic binary encode | 67.99 | — | — | 150.09 (2.21x) | 1220.66 (17.95x) |
| scalarmix encode | 26.82 | 112.96 (4.21x) | 67.38 (2.51x) | 45.72 (1.70x) | 238.05 (8.88x) |
| scalarmix decode | 50.72 | 161.40 (3.18x) | 209.82 (4.14x) | 117.86 (2.32x) | 373.13 (7.36x) |
| textbytes encode | 13.28 | 90.57 (6.82x) | 43.27 (3.26x) | 146.23 (11.01x) | 181.05 (13.63x) |
| textbytes decode | 61.77 | 473.76 (7.67x) | 310.02 (5.02x) | 207.21 (3.35x) | 816.86 (13.22x) |
| largebytes encode | 23.06 | 4022.63 (174.44x) | 3861.96 (167.47x) | 3820.95 (165.70x) | 4142.48 (179.64x) |
| largebytes decode | 124.45 | 8838.49 (71.02x) | 4591.05 (36.89x) | 4001.32 (32.15x) | 24353.91 (195.69x) |
| presencemix encode | 23.06 | 65.58 (2.84x) | 37.78 (1.64x) | 69.41 (3.01x) | 260.62 (11.30x) |
| presencemix decode | 67.37 | 160.42 (2.38x) | 144.26 (2.14x) | 204.05 (3.03x) | 575.51 (8.54x) |
| complex encode | 71.54 | 166.21 (2.32x) | 116.64 (1.63x) | 211.57 (2.96x) | 970.78 (13.57x) |
| complex decode | 224.75 | 463.33 (2.06x) | 438.58 (1.95x) | 487.95 (2.17x) | 1639.70 (7.30x) |
| complex deterministic binary encode | 128.56 | — | — | 222.76 (1.73x) | 1295.11 (10.07x) |
| complex JSON stringify | 378.36 | — | — | 7066.05 (18.68x) | 7763.05 (20.52x) |
| complex JSON parse | 2751.49 | — | — | 16643.60 (6.05x) | 10646.56 (3.87x) |
| complex TextFormat format | 341.42 | — | — | 4768.01 (13.97x) | 6743.04 (19.75x) |
| complex TextFormat parse | 2150.53 | — | — | 7756.29 (3.61x) | 11345.30 (5.28x) |
| packed int32 encode | 895.14 | 5391.42 (6.02x) | 3023.67 (3.38x) | 2208.29 (2.47x) | 5708.09 (6.38x) |
| packed int32 decode | 1029.75 | 2970.29 (2.88x) | 5451.72 (5.29x) | 1381.10 (1.34x) | 4413.75 (4.29x) |
| JSON stringify | 203.52 | — | — | 4768.73 (23.43x) | 2744.98 (13.49x) |
| JSON parse | 1723.26 | — | — | 10641.20 (6.18x) | 5767.21 (3.35x) |
| Any WKT JSON stringify | 178.64 | — | — | 3032.77 (16.98x) | 1355.57 (7.59x) |
| Any WKT JSON parse | 583.65 | — | — | 4596.08 (7.87x) | 2124.45 (3.64x) |
| Any NegativeDuration WKT JSON stringify | 185.90 | — | — | 3097.08 (16.66x) | 1440.20 (7.75x) |
| Any NegativeDuration WKT JSON parse | 588.81 | — | — | 4715.60 (8.01x) | 2162.84 (3.67x) |
| Any FractionalNegativeDuration WKT JSON stringify | 178.14 | — | — | 3069.27 (17.23x) | 1398.46 (7.85x) |
| Any FractionalNegativeDuration WKT JSON parse | 588.68 | — | — | 4689.39 (7.97x) | 2117.04 (3.60x) |
| Any MaxDuration WKT JSON stringify | 168.00 | — | — | 2712.98 (16.15x) | 1361.62 (8.10x) |
| Any MaxDuration WKT JSON parse | 604.54 | — | — | 4596.65 (7.60x) | 2135.02 (3.53x) |
| Any MinDuration WKT JSON stringify | 161.99 | — | — | 2747.82 (16.96x) | 1405.43 (8.68x) |
| Any MinDuration WKT JSON parse | 604.82 | — | — | 4685.49 (7.75x) | 2137.06 (3.53x) |
| Any ZeroDuration WKT JSON stringify | 145.90 | — | — | 1288.04 (8.83x) | 1245.08 (8.53x) |
| Any ZeroDuration WKT JSON parse | 530.45 | — | — | 3319.15 (6.26x) | 1942.21 (3.66x) |
| Any FieldMask WKT JSON stringify | 284.50 | — | — | 2435.36 (8.56x) | 1772.40 (6.23x) |
| Any FieldMask WKT JSON parse | 800.21 | — | — | 4883.84 (6.10x) | 2911.98 (3.64x) |
| Any EmptyFieldMask WKT JSON stringify | 151.85 | — | — | 1285.75 (8.47x) | 908.79 (5.98x) |
| Any EmptyFieldMask WKT JSON parse | 497.05 | — | — | 3228.08 (6.49x) | 1658.49 (3.34x) |
| Any Timestamp WKT JSON stringify | 247.02 | — | — | 3009.21 (12.18x) | 1325.15 (5.36x) |
| Any Timestamp WKT JSON parse | 645.33 | — | — | 4596.43 (7.12x) | 2254.01 (3.49x) |
| Any PreEpoch Timestamp WKT JSON stringify | 197.26 | — | — | 2890.47 (14.65x) | 1293.16 (6.56x) |
| Any PreEpoch Timestamp WKT JSON parse | 627.31 | — | — | 4672.20 (7.45x) | 2211.06 (3.52x) |
| Any Max Timestamp WKT JSON stringify | 224.41 | — | — | 3037.09 (13.53x) | 1330.98 (5.93x) |
| Any Max Timestamp WKT JSON parse | 660.29 | — | — | 4695.17 (7.11x) | 2299.18 (3.48x) |
| Any Min Timestamp WKT JSON stringify | 228.70 | — | — | 2908.40 (12.72x) | 1298.68 (5.68x) |
| Any Min Timestamp WKT JSON parse | 626.15 | — | — | 4732.45 (7.56x) | 2198.79 (3.51x) |
| Any Empty WKT JSON stringify | 121.82 | — | — | 1309.34 (10.75x) | 705.48 (5.79x) |
| Any Empty WKT JSON parse | 379.79 | — | — | 3169.40 (8.35x) | 1611.14 (4.24x) |
| Any Struct WKT JSON stringify | 773.99 | — | — | 8929.61 (11.54x) | 8708.64 (11.25x) |
| Any Struct WKT JSON parse | 1968.13 | — | — | 17158.20 (8.72x) | 12500.39 (6.35x) |
| Any EmptyStruct WKT JSON stringify | 157.38 | — | — | 1282.49 (8.15x) | 1257.22 (7.99x) |
| Any EmptyStruct WKT JSON parse | 504.33 | — | — | 3278.17 (6.50x) | 2243.97 (4.45x) |
| Any Value WKT JSON stringify | 809.36 | — | — | 9019.09 (11.14x) | 9107.54 (11.25x) |
| Any Value WKT JSON parse | 2025.28 | — | — | 16906.80 (8.35x) | 12962.12 (6.40x) |
| Any NullValue WKT JSON stringify | 161.94 | — | — | 3121.09 (19.27x) | 1246.49 (7.70x) |
| Any NullValue WKT JSON parse | 530.52 | — | — | 6133.07 (11.56x) | 2201.27 (4.15x) |
| Any StringScalarValue WKT JSON stringify | 194.11 | — | — | 3098.22 (15.96x) | 1412.61 (7.28x) |
| Any StringScalarValue WKT JSON parse | 575.65 | — | — | 5373.16 (9.33x) | 2302.47 (4.00x) |
| Any EmptyStringScalarValue WKT JSON stringify | 172.68 | — | — | 3160.34 (18.30x) | 1312.04 (7.60x) |
| Any EmptyStringScalarValue WKT JSON parse | 544.66 | — | — | 5328.18 (9.78x) | 2187.60 (4.02x) |
| Any NumberValue WKT JSON stringify | 234.77 | — | — | 3931.70 (16.75x) | 1493.79 (6.36x) |
| Any NumberValue WKT JSON parse | 561.58 | — | — | 5625.16 (10.02x) | 2414.45 (4.30x) |
| Any ZeroNumberValue WKT JSON stringify | 179.47 | — | — | 3776.80 (21.04x) | 1350.57 (7.53x) |
| Any ZeroNumberValue WKT JSON parse | 570.60 | — | — | 5429.07 (9.51x) | 2358.17 (4.13x) |
| Any BoolScalarValue WKT JSON stringify | 163.73 | — | — | 3145.13 (19.21x) | 1293.15 (7.90x) |
| Any BoolScalarValue WKT JSON parse | 527.31 | — | — | 5255.62 (9.97x) | 2157.30 (4.09x) |
| Any FalseBoolScalarValue WKT JSON stringify | 164.12 | — | — | 3109.84 (18.95x) | 1300.54 (7.92x) |
| Any FalseBoolScalarValue WKT JSON parse | 521.26 | — | — | 5331.24 (10.23x) | 2172.17 (4.17x) |
| Any ListKindValue WKT JSON stringify | 646.01 | — | — | 8792.78 (13.61x) | 6945.30 (10.75x) |
| Any ListKindValue WKT JSON parse | 1554.48 | — | — | 15472.30 (9.95x) | 10659.07 (6.86x) |
| Any EmptyStructKindValue WKT JSON stringify | 182.95 | — | — | 4118.24 (22.51x) | 2009.69 (10.98x) |
| Any EmptyStructKindValue WKT JSON parse | 565.59 | — | — | 8133.70 (14.38x) | 3022.26 (5.34x) |
| Any EmptyListKindValue WKT JSON stringify | 181.15 | — | — | 3997.93 (22.07x) | 1638.47 (9.04x) |
| Any EmptyListKindValue WKT JSON parse | 566.31 | — | — | 6578.48 (11.62x) | 2820.30 (4.98x) |
| Any DoubleValue WKT JSON stringify | 251.05 | — | — | 2877.81 (11.46x) | 983.20 (3.92x) |
| Any DoubleValue WKT JSON parse | 581.07 | — | — | 4379.65 (7.54x) | 1994.40 (3.43x) |
| Any NegativeDoubleValue WKT JSON stringify | 252.23 | — | — | 2873.00 (11.39x) | 956.68 (3.79x) |
| Any NegativeDoubleValue WKT JSON parse | 581.77 | — | — | 4416.66 (7.59x) | 1971.23 (3.39x) |
| Any ZeroDoubleValue WKT JSON stringify | 202.68 | — | — | 1289.88 (6.36x) | 838.34 (4.14x) |
| Any ZeroDoubleValue WKT JSON parse | 582.17 | — | — | 3217.10 (5.53x) | 1866.78 (3.21x) |
| Any DoubleValue NaN WKT JSON stringify | 197.89 | — | — | 2311.27 (11.68x) | 834.69 (4.22x) |
| Any DoubleValue NaN WKT JSON parse | 577.79 | — | — | 4068.47 (7.04x) | 1887.28 (3.27x) |
| Any DoubleValue Infinity WKT JSON stringify | 205.25 | — | — | 2216.30 (10.80x) | 837.12 (4.08x) |
| Any DoubleValue Infinity WKT JSON parse | 582.34 | — | — | 4060.30 (6.97x) | 1909.46 (3.28x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 205.13 | — | — | 2233.67 (10.89x) | 820.31 (4.00x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 584.83 | — | — | 4110.40 (7.03x) | 1925.18 (3.29x) |
| Any FloatValue WKT JSON stringify | 258.52 | — | — | 2864.21 (11.08x) | 912.48 (3.53x) |
| Any FloatValue WKT JSON parse | 578.89 | — | — | 4408.13 (7.61x) | 1931.72 (3.34x) |
| Any NegativeFloatValue WKT JSON stringify | 259.83 | — | — | 2782.01 (10.71x) | 901.68 (3.47x) |
| Any NegativeFloatValue WKT JSON parse | 579.77 | — | — | 4341.42 (7.49x) | 1883.91 (3.25x) |
| Any ZeroFloatValue WKT JSON stringify | 205.40 | — | — | 1322.01 (6.44x) | 827.60 (4.03x) |
| Any ZeroFloatValue WKT JSON parse | 580.99 | — | — | 3166.13 (5.45x) | 1841.68 (3.17x) |
| Any FloatValue NaN WKT JSON stringify | 201.04 | — | — | 2231.98 (11.10x) | 823.10 (4.09x) |
| Any FloatValue NaN WKT JSON parse | 575.36 | — | — | 4044.08 (7.03x) | 1831.69 (3.18x) |
| Any FloatValue Infinity WKT JSON stringify | 207.45 | — | — | 2174.10 (10.48x) | 813.10 (3.92x) |
| Any FloatValue Infinity WKT JSON parse | 581.31 | — | — | 4053.07 (6.97x) | 1879.38 (3.23x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 208.26 | — | — | 2158.58 (10.36x) | 814.58 (3.91x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 583.23 | — | — | 4070.31 (6.98x) | 1893.95 (3.25x) |
| Any Int64Value WKT JSON stringify | 206.27 | — | — | 2198.77 (10.66x) | 1161.44 (5.63x) |
| Any Int64Value WKT JSON parse | 634.36 | — | — | 4288.65 (6.76x) | 2280.58 (3.60x) |
| Any ZeroInt64Value WKT JSON stringify | 197.04 | — | — | 1304.42 (6.62x) | 998.83 (5.07x) |
| Any ZeroInt64Value WKT JSON parse | 581.22 | — | — | 3176.97 (5.47x) | 2035.89 (3.50x) |
| Any NegativeInt64Value WKT JSON stringify | 209.10 | — | — | 2169.29 (10.37x) | 1158.97 (5.54x) |
| Any NegativeInt64Value WKT JSON parse | 621.43 | — | — | 4298.45 (6.92x) | 2356.73 (3.79x) |
| Any MinInt64Value WKT JSON stringify | 214.66 | — | — | 2170.74 (10.11x) | 1195.18 (5.57x) |
| Any MinInt64Value WKT JSON parse | 632.65 | — | — | 4318.28 (6.83x) | 2377.91 (3.76x) |
| Any MaxInt64Value WKT JSON stringify | 214.46 | — | — | 2160.30 (10.07x) | 1168.11 (5.45x) |
| Any MaxInt64Value WKT JSON parse | 636.37 | — | — | 4322.42 (6.79x) | 2285.82 (3.59x) |
| Any UInt64Value WKT JSON stringify | 216.49 | — | — | 2160.25 (9.98x) | 1181.79 (5.46x) |
| Any UInt64Value WKT JSON parse | 629.51 | — | — | 4284.89 (6.81x) | 2228.95 (3.54x) |
| Any ZeroUInt64Value WKT JSON stringify | 204.02 | — | — | 1311.56 (6.43x) | 1020.71 (5.00x) |
| Any ZeroUInt64Value WKT JSON parse | 587.18 | — | — | 3205.92 (5.46x) | 2026.33 (3.45x) |
| Any MaxUInt64Value WKT JSON stringify | 221.92 | — | — | 2189.30 (9.87x) | 1147.89 (5.17x) |
| Any MaxUInt64Value WKT JSON parse | 641.96 | — | — | 4336.40 (6.75x) | 2277.83 (3.55x) |
| Any Int32Value WKT JSON stringify | 208.26 | — | — | 2257.53 (10.84x) | 826.17 (3.97x) |
| Any Int32Value WKT JSON parse | 598.11 | — | — | 4137.20 (6.92x) | 1908.59 (3.19x) |
| Any ZeroInt32Value WKT JSON stringify | 206.70 | — | — | 1296.94 (6.27x) | 800.84 (3.87x) |
| Any ZeroInt32Value WKT JSON parse | 590.62 | — | — | 3179.91 (5.38x) | 1868.31 (3.16x) |
| Any NegativeInt32Value WKT JSON stringify | 212.69 | — | — | 2224.13 (10.46x) | 859.18 (4.04x) |
| Any NegativeInt32Value WKT JSON parse | 596.21 | — | — | 4151.03 (6.96x) | 1966.29 (3.30x) |
| Any MinInt32Value WKT JSON stringify | 211.98 | — | — | 2206.69 (10.41x) | 853.95 (4.03x) |
| Any MinInt32Value WKT JSON parse | 608.90 | — | — | 4211.97 (6.92x) | 2070.36 (3.40x) |
| Any MaxInt32Value WKT JSON stringify | 211.21 | — | — | 2162.52 (10.24x) | 871.81 (4.13x) |
| Any MaxInt32Value WKT JSON parse | 611.25 | — | — | 4172.97 (6.83x) | 1986.81 (3.25x) |
| Any UInt32Value WKT JSON stringify | 217.48 | — | — | 2147.98 (9.88x) | 915.76 (4.21x) |
| Any UInt32Value WKT JSON parse | 606.62 | — | — | 4144.34 (6.83x) | 1950.39 (3.22x) |
| Any ZeroUInt32Value WKT JSON stringify | 212.53 | — | — | 1278.23 (6.01x) | 833.47 (3.92x) |
| Any ZeroUInt32Value WKT JSON parse | 600.74 | — | — | 3240.12 (5.39x) | 1855.70 (3.09x) |
| Any MaxUInt32Value WKT JSON stringify | 218.94 | — | — | 2173.23 (9.93x) | 872.92 (3.99x) |
| Any MaxUInt32Value WKT JSON parse | 619.53 | — | — | 4138.01 (6.68x) | 2017.92 (3.26x) |
| Any BoolValue WKT JSON stringify | 209.41 | — | — | 2147.40 (10.25x) | 858.14 (4.10x) |
| Any BoolValue WKT JSON parse | 555.71 | — | — | 4071.32 (7.33x) | 1742.12 (3.13x) |
| Any FalseBoolValue WKT JSON stringify | 209.85 | — | — | 1320.85 (6.29x) | 834.52 (3.98x) |
| Any FalseBoolValue WKT JSON parse | 556.19 | — | — | 3217.91 (5.79x) | 1687.03 (3.03x) |
| Any StringValue WKT JSON stringify | 245.92 | — | — | 2268.27 (9.22x) | 976.66 (3.97x) |
| Any StringValue WKT JSON parse | 615.41 | — | — | 4046.02 (6.57x) | 2001.99 (3.25x) |
| Any EmptyStringValue WKT JSON stringify | 228.47 | — | — | 1318.94 (5.77x) | 894.15 (3.91x) |
| Any EmptyStringValue WKT JSON parse | 577.69 | — | — | 3186.64 (5.52x) | 1705.60 (2.95x) |
| Any BytesValue WKT JSON stringify | 224.99 | — | — | 2297.12 (10.21x) | 1014.45 (4.51x) |
| Any BytesValue WKT JSON parse | 622.80 | — | — | 4223.94 (6.78x) | 2049.02 (3.29x) |
| Any EmptyBytesValue WKT JSON stringify | 219.43 | — | — | 1301.78 (5.93x) | 848.93 (3.87x) |
| Any EmptyBytesValue WKT JSON parse | 582.64 | — | — | 3146.19 (5.40x) | 1822.90 (3.13x) |
| Nested Any WKT JSON stringify | 385.62 | — | — | 3450.66 (8.95x) | 1729.41 (4.48x) |
| Nested Any WKT JSON parse | 1011.14 | — | — | 6020.07 (5.95x) | 3659.32 (3.62x) |
| Duration JSON stringify | 64.68 | — | — | 1531.67 (23.68x) | 420.00 (6.49x) |
| Duration JSON parse | 11.30 | — | — | 2329.78 (206.18x) | 447.12 (39.57x) |
| NegativeDuration JSON stringify | 65.75 | — | — | 1604.70 (24.41x) | 484.86 (7.37x) |
| NegativeDuration JSON parse | 11.78 | — | — | 2392.19 (203.07x) | 458.88 (38.95x) |
| FractionalNegativeDuration JSON stringify | 65.75 | — | — | 1570.60 (23.89x) | 506.60 (7.70x) |
| FractionalNegativeDuration JSON parse | 11.78 | — | — | 2302.72 (195.48x) | 443.70 (37.67x) |
| MaxDuration JSON stringify | 53.41 | — | — | 1290.27 (24.16x) | 485.60 (9.09x) |
| MaxDuration JSON parse | 29.16 | — | — | 2219.64 (76.12x) | 465.02 (15.95x) |
| MinDuration JSON stringify | 53.75 | — | — | 1323.37 (24.62x) | 514.44 (9.57x) |
| MinDuration JSON parse | 29.37 | — | — | 2229.81 (75.92x) | 460.37 (15.67x) |
| ZeroDuration JSON stringify | 47.94 | — | — | 1242.25 (25.91x) | 411.11 (8.58x) |
| ZeroDuration JSON parse | 8.79 | — | — | 2137.61 (243.19x) | 357.57 (40.68x) |
| FieldMask JSON stringify | 92.70 | — | — | 1302.91 (14.06x) | 805.10 (8.69x) |
| FieldMask JSON parse | 181.79 | — | — | 2681.72 (14.75x) | 1103.57 (6.07x) |
| EmptyFieldMask JSON stringify | 42.46 | — | — | 931.44 (21.94x) | 242.66 (5.72x) |
| EmptyFieldMask JSON parse | 3.52 | — | — | 1444.71 (410.43x) | 218.52 (62.08x) |
| Timestamp JSON stringify | 131.00 | — | — | 1728.68 (13.20x) | 497.71 (3.80x) |
| Timestamp JSON parse | 56.92 | — | — | 2307.33 (40.54x) | 510.51 (8.97x) |
| PreEpoch Timestamp JSON stringify | 85.21 | — | — | 1588.61 (18.64x) | 491.39 (5.77x) |
| PreEpoch Timestamp JSON parse | 54.82 | — | — | 2275.27 (41.50x) | 480.07 (8.76x) |
| Max Timestamp JSON stringify | 103.22 | — | — | 1720.02 (16.66x) | 502.34 (4.87x) |
| Max Timestamp JSON parse | 64.40 | — | — | 2336.57 (36.28x) | 525.44 (8.16x) |
| Min Timestamp JSON stringify | 118.62 | — | — | 1573.93 (13.27x) | 491.58 (4.14x) |
| Min Timestamp JSON parse | 52.79 | — | — | 2293.98 (43.45x) | 497.43 (9.42x) |
| Empty JSON stringify | 22.78 | — | — | 686.94 (30.16x) | 115.32 (5.06x) |
| Empty JSON parse | 74.27 | — | — | 1083.70 (14.59x) | 257.95 (3.47x) |
| Struct JSON stringify | 271.86 | — | — | 8765.40 (32.24x) | 4102.50 (15.09x) |
| Struct JSON parse | 958.94 | — | — | 16817.10 (17.54x) | 6522.18 (6.80x) |
| EmptyStruct JSON stringify | 44.19 | — | — | 1021.23 (23.11x) | 430.45 (9.74x) |
| EmptyStruct JSON parse | 97.20 | — | — | 3362.03 (34.59x) | 447.60 (4.60x) |
| Value JSON stringify | 275.39 | — | — | 9707.75 (35.25x) | 4280.81 (15.54x) |
| Value JSON parse | 950.18 | — | — | 17583.00 (18.50x) | 6654.04 (7.00x) |
| NullValue JSON stringify | 42.53 | — | — | 1712.48 (40.27x) | 239.73 (5.64x) |
| NullValue JSON parse | 63.28 | — | — | 3741.90 (59.13x) | 377.80 (5.97x) |
| StringScalarValue JSON stringify | 54.76 | — | — | 1832.80 (33.47x) | 281.66 (5.14x) |
| StringScalarValue JSON parse | 125.90 | — | — | 3017.40 (23.97x) | 483.50 (3.84x) |
| EmptyStringScalarValue JSON stringify | 51.03 | — | — | 1833.98 (35.94x) | 277.13 (5.43x) |
| EmptyStringScalarValue JSON parse | 72.93 | — | — | 3024.95 (41.48x) | 409.08 (5.61x) |
| NumberValue JSON stringify | 112.43 | — | — | 2307.98 (20.53x) | 345.27 (3.07x) |
| NumberValue JSON parse | 123.75 | — | — | 3259.24 (26.34x) | 445.53 (3.60x) |
| ZeroNumberValue JSON stringify | 63.87 | — | — | 2256.02 (35.32x) | 295.65 (4.63x) |
| ZeroNumberValue JSON parse | 126.53 | — | — | 3059.96 (24.18x) | 430.34 (3.40x) |
| BoolScalarValue JSON stringify | 42.34 | — | — | 1714.56 (40.50x) | 231.44 (5.47x) |
| BoolScalarValue JSON parse | 58.56 | — | — | 2911.84 (49.72x) | 368.80 (6.30x) |
| FalseBoolScalarValue JSON stringify | 42.38 | — | — | 1680.90 (39.66x) | 228.73 (5.40x) |
| FalseBoolScalarValue JSON parse | 59.28 | — | — | 2903.43 (48.98x) | 352.61 (5.95x) |
| ListKindValue JSON stringify | 207.85 | — | — | 9187.97 (44.20x) | 2876.71 (13.84x) |
| ListKindValue JSON parse | 752.51 | — | — | 15876.20 (21.10x) | 5535.02 (7.36x) |
| EmptyStructKindValue JSON stringify | 45.44 | — | — | 2706.72 (59.57x) | 641.58 (14.12x) |
| EmptyStructKindValue JSON parse | 107.07 | — | — | 5773.08 (53.92x) | 840.27 (7.85x) |
| EmptyListKindValue JSON stringify | 44.67 | — | — | 2714.77 (60.77x) | 375.40 (8.40x) |
| EmptyListKindValue JSON parse | 144.31 | — | — | 5595.45 (38.77x) | 681.50 (4.72x) |
| ListValue JSON stringify | 202.44 | — | — | 7559.75 (37.34x) | 2698.65 (13.33x) |
| ListValue JSON parse | 750.96 | — | — | 13450.10 (17.91x) | 5208.65 (6.94x) |
| EmptyListValue JSON stringify | 41.28 | — | — | 1001.28 (24.26x) | 230.85 (5.59x) |
| EmptyListValue JSON parse | 139.01 | — | — | 3180.00 (22.88x) | 390.47 (2.81x) |
| DoubleValue JSON stringify | 98.32 | — | — | 1463.96 (14.89x) | 219.96 (2.24x) |
| DoubleValue JSON parse | 114.02 | — | — | 2089.88 (18.33x) | 329.42 (2.89x) |
| NegativeDoubleValue JSON stringify | 98.28 | — | — | 1491.26 (15.17x) | 212.90 (2.17x) |
| NegativeDoubleValue JSON parse | 114.34 | — | — | 2118.67 (18.53x) | 319.18 (2.79x) |
| ZeroDoubleValue JSON stringify | 52.26 | — | — | 1369.26 (26.20x) | 164.41 (3.15x) |
| ZeroDoubleValue JSON parse | 116.40 | — | — | 1855.22 (15.94x) | 307.98 (2.65x) |
| DoubleValue NaN JSON stringify | 52.67 | — | — | 1012.20 (19.22x) | 144.39 (2.74x) |
| DoubleValue NaN JSON parse | 102.57 | — | — | 1697.86 (16.55x) | 316.34 (3.08x) |
| DoubleValue Infinity JSON stringify | 56.64 | — | — | 995.09 (17.57x) | 151.96 (2.68x) |
| DoubleValue Infinity JSON parse | 106.12 | — | — | 1715.07 (16.16x) | 322.78 (3.04x) |
| DoubleValue NegativeInfinity JSON stringify | 57.92 | — | — | 1018.22 (17.58x) | 148.38 (2.56x) |
| DoubleValue NegativeInfinity JSON parse | 108.96 | — | — | 1745.48 (16.02x) | 339.74 (3.12x) |
| FloatValue JSON stringify | 103.65 | — | — | 1422.51 (13.72x) | 210.02 (2.03x) |
| FloatValue JSON parse | 121.62 | — | — | 2134.90 (17.55x) | 329.48 (2.71x) |
| NegativeFloatValue JSON stringify | 102.99 | — | — | 1424.57 (13.83x) | 210.21 (2.04x) |
| NegativeFloatValue JSON parse | 122.51 | — | — | 2121.84 (17.32x) | 322.76 (2.63x) |
| ZeroFloatValue JSON stringify | 54.16 | — | — | 1354.13 (25.00x) | 166.97 (3.08x) |
| ZeroFloatValue JSON parse | 123.91 | — | — | 1864.17 (15.04x) | 301.81 (2.44x) |
| FloatValue NaN JSON stringify | 52.59 | — | — | 960.20 (18.26x) | 145.04 (2.76x) |
| FloatValue NaN JSON parse | 110.95 | — | — | 1696.40 (15.29x) | 304.84 (2.75x) |
| FloatValue Infinity JSON stringify | 56.37 | — | — | 959.90 (17.03x) | 155.93 (2.77x) |
| FloatValue Infinity JSON parse | 114.47 | — | — | 1715.98 (14.99x) | 317.18 (2.77x) |
| FloatValue NegativeInfinity JSON stringify | 57.72 | — | — | 952.84 (16.51x) | 156.54 (2.71x) |
| FloatValue NegativeInfinity JSON parse | 117.97 | — | — | 1725.68 (14.63x) | 324.12 (2.75x) |
| Int64Value JSON stringify | 54.29 | — | — | 992.63 (18.28x) | 308.07 (5.67x) |
| Int64Value JSON parse | 146.64 | — | — | 1964.04 (13.39x) | 517.33 (3.53x) |
| ZeroInt64Value JSON stringify | 44.13 | — | — | 936.32 (21.22x) | 199.62 (4.52x) |
| ZeroInt64Value JSON parse | 111.71 | — | — | 1810.72 (16.21x) | 359.16 (3.22x) |
| NegativeInt64Value JSON stringify | 54.51 | — | — | 986.44 (18.10x) | 314.58 (5.77x) |
| NegativeInt64Value JSON parse | 147.94 | — | — | 1958.52 (13.24x) | 521.36 (3.52x) |
| MinInt64Value JSON stringify | 59.65 | — | — | 992.72 (16.64x) | 334.40 (5.61x) |
| MinInt64Value JSON parse | 157.93 | — | — | 1989.36 (12.60x) | 547.63 (3.47x) |
| MaxInt64Value JSON stringify | 59.35 | — | — | 999.47 (16.84x) | 317.40 (5.35x) |
| MaxInt64Value JSON parse | 157.06 | — | — | 1978.13 (12.59x) | 523.13 (3.33x) |
| UInt64Value JSON stringify | 54.35 | — | — | 993.77 (18.28x) | 312.42 (5.75x) |
| UInt64Value JSON parse | 139.04 | — | — | 1955.88 (14.07x) | 511.78 (3.68x) |
| ZeroUInt64Value JSON stringify | 43.37 | — | — | 924.02 (21.31x) | 217.26 (5.01x) |
| ZeroUInt64Value JSON parse | 102.20 | — | — | 1789.47 (17.51x) | 385.40 (3.77x) |
| MaxUInt64Value JSON stringify | 57.41 | — | — | 1029.70 (17.94x) | 321.11 (5.59x) |
| MaxUInt64Value JSON parse | 152.43 | — | — | 1986.66 (13.03x) | 512.84 (3.36x) |
| Int32Value JSON stringify | 47.67 | — | — | 978.15 (20.52x) | 154.10 (3.23x) |
| Int32Value JSON parse | 133.41 | — | — | 1920.13 (14.39x) | 334.59 (2.51x) |
| ZeroInt32Value JSON stringify | 48.32 | — | — | 958.98 (19.85x) | 154.87 (3.21x) |
| ZeroInt32Value JSON parse | 128.09 | — | — | 1857.48 (14.50x) | 298.04 (2.33x) |
| NegativeInt32Value JSON stringify | 48.18 | — | — | 971.33 (20.16x) | 180.14 (3.74x) |
| NegativeInt32Value JSON parse | 128.76 | — | — | 1904.04 (14.79x) | 356.30 (2.77x) |
| MinInt32Value JSON stringify | 48.45 | — | — | 977.80 (20.18x) | 166.08 (3.43x) |
| MinInt32Value JSON parse | 141.15 | — | — | 1931.80 (13.69x) | 386.71 (2.74x) |
| MaxInt32Value JSON stringify | 48.26 | — | — | 981.34 (20.33x) | 163.78 (3.39x) |
| MaxInt32Value JSON parse | 143.60 | — | — | 1934.62 (13.47x) | 363.71 (2.53x) |
| UInt32Value JSON stringify | 47.74 | — | — | 959.73 (20.10x) | 170.93 (3.58x) |
| UInt32Value JSON parse | 133.59 | — | — | 1890.55 (14.15x) | 350.73 (2.63x) |
| ZeroUInt32Value JSON stringify | 48.48 | — | — | 919.59 (18.97x) | 167.71 (3.46x) |
| ZeroUInt32Value JSON parse | 127.90 | — | — | 1858.56 (14.53x) | 303.96 (2.38x) |
| MaxUInt32Value JSON stringify | 48.46 | — | — | 934.13 (19.28x) | 180.86 (3.73x) |
| MaxUInt32Value JSON parse | 143.77 | — | — | 1941.69 (13.51x) | 388.43 (2.70x) |
| BoolValue JSON stringify | 46.68 | — | — | 897.63 (19.23x) | 147.75 (3.17x) |
| BoolValue JSON parse | 54.83 | — | — | 1689.98 (30.82x) | 252.09 (4.60x) |
| FalseBoolValue JSON stringify | 46.74 | — | — | 899.80 (19.25x) | 160.43 (3.43x) |
| FalseBoolValue JSON parse | 55.26 | — | — | 1713.03 (31.00x) | 245.03 (4.43x) |
| StringValue JSON stringify | 62.35 | — | — | 1045.09 (16.76x) | 223.84 (3.59x) |
| StringValue JSON parse | 131.50 | — | — | 1847.45 (14.05x) | 360.84 (2.74x) |
| EmptyStringValue JSON stringify | 52.66 | — | — | 967.72 (18.38x) | 218.63 (4.15x) |
| EmptyStringValue JSON parse | 74.28 | — | — | 1788.94 (24.08x) | 271.45 (3.65x) |
| BytesValue JSON stringify | 49.40 | — | — | 1005.35 (20.35x) | 257.86 (5.22x) |
| BytesValue JSON parse | 138.26 | — | — | 1955.23 (14.14x) | 372.46 (2.69x) |
| EmptyBytesValue JSON stringify | 42.29 | — | — | 976.25 (23.08x) | 221.20 (5.23x) |
| EmptyBytesValue JSON parse | 77.44 | — | — | 1871.16 (24.16x) | 320.89 (4.14x) |
| TextFormat format | 232.84 | — | — | 3248.88 (13.95x) | 3101.30 (13.32x) |
| TextFormat parse | 840.72 | — | — | 5536.16 (6.59x) | 8086.75 (9.62x) |
| packed fixed32 encode | 2.26 | 805.34 (356.35x) | 628.96 (278.30x) | 90.56 (40.07x) | 568.99 (251.77x) |
| packed fixed32 decode | 7.02 | 1242.31 (176.97x) | 2823.76 (402.25x) | 99.58 (14.19x) | 2002.09 (285.20x) |
| packed fixed64 encode | 2.26 | 708.26 (313.39x) | 631.22 (279.30x) | 154.65 (68.43x) | 570.73 (252.54x) |
| packed fixed64 decode | 7.40 | 1224.61 (165.49x) | 7470.44 (1009.52x) | 163.64 (22.11x) | 3237.16 (437.45x) |
| packed sfixed32 encode | 2.26 | 704.63 (311.78x) | 628.58 (278.13x) | 90.88 (40.21x) | 569.43 (251.96x) |
| packed sfixed32 decode | 7.02 | 1300.48 (185.25x) | 2827.62 (402.79x) | 97.04 (13.82x) | 1989.37 (283.39x) |
| packed sfixed64 encode | 2.76 | 806.56 (292.23x) | 630.65 (228.50x) | 154.64 (56.03x) | 571.08 (206.91x) |
| packed sfixed64 decode | 7.32 | 1328.65 (181.51x) | 7305.38 (998.00x) | 161.33 (22.04x) | 2743.84 (374.84x) |
| packed float encode | 2.26 | 826.42 (365.67x) | 628.90 (278.27x) | 90.78 (40.17x) | 565.21 (250.09x) |
| packed float decode | 7.02 | 1315.65 (187.41x) | 2625.50 (374.00x) | 96.99 (13.82x) | 1990.59 (283.56x) |
| packed double encode | 2.26 | 855.28 (378.44x) | 632.71 (279.96x) | 154.57 (68.39x) | 566.84 (250.81x) |
| packed double decode | 7.02 | 2137.14 (304.44x) | 2862.63 (407.78x) | 161.32 (22.98x) | 3270.97 (465.95x) |
| packed uint64 encode | 2496.97 | 6957.76 (2.79x) | 6329.63 (2.53x) | 3403.23 (1.36x) | 6406.90 (2.57x) |
| packed uint64 decode | 2589.03 | 4300.76 (1.66x) | 8617.71 (3.33x) | 4533.08 (1.75x) | 11875.87 (4.59x) |
| packed uint32 encode | 1628.42 | 4765.00 (2.93x) | 4407.94 (2.71x) | 2662.22 (1.63x) | 5427.88 (3.33x) |
| packed uint32 decode | 1881.61 | 3795.69 (2.02x) | 4785.00 (2.54x) | 3257.70 (1.73x) | 8667.19 (4.61x) |
| packed int64 encode | 2288.67 | 15626.13 (6.83x) | 7305.66 (3.19x) | 4484.27 (1.96x) | 7650.26 (3.34x) |
| packed int64 decode | 4426.82 | 5587.55 (1.26x) | 10641.67 (2.40x) | 5991.88 (1.35x) | 14555.89 (3.29x) |
| packed sint32 encode | 1087.17 | 4422.42 (4.07x) | 4124.44 (3.79x) | 2630.82 (2.42x) | 5986.79 (5.51x) |
| packed sint32 decode | 1298.50 | 3857.32 (2.97x) | 4661.56 (3.59x) | 1588.84 (1.22x) | 5016.53 (3.86x) |
| packed sint64 encode | 2032.56 | 7608.04 (3.74x) | 6337.38 (3.12x) | 3824.93 (1.88x) | 6709.02 (3.30x) |
| packed sint64 decode | 2846.99 | 4308.00 (1.51x) | 9785.57 (3.44x) | 5144.11 (1.81x) | 11822.65 (4.15x) |
| packed bool encode | 2.26 | 2079.81 (920.27x) | 543.14 (240.33x) | 22.86 (10.11x) | 4385.55 (1940.51x) |
| packed bool decode | 271.66 | 2168.22 (7.98x) | 4151.60 (15.28x) | 1110.51 (4.09x) | 2665.32 (9.81x) |
| packed enum encode | 583.65 | 4923.09 (8.44x) | 2076.98 (3.56x) | 1628.56 (2.79x) | 5026.55 (8.61x) |
| packed enum decode | 277.75 | 2121.14 (7.64x) | 3895.47 (14.03x) | 1929.87 (6.95x) | 3215.77 (11.58x) |
| large map encode | 5381.99 | 22222.38 (4.13x) | 13015.35 (2.42x) | 34590.50 (6.43x) | 239213.39 (44.45x) |
| shuffled large map deterministic binary encode | 36205.07 | — | — | 117038.00 (3.23x) | 457880.80 (12.65x) |
| large map decode | 37305.95 | 128087.49 (3.43x) | 129674.72 (3.48x) | 126383.00 (3.39x) | 298561.68 (8.00x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded zero/positive/integer-negative/fractional-negative/min-max-bound `Duration`, non-empty and empty `Struct`, object/list/scalar `Value` (including default-like scalar and empty object/list kinds),
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
