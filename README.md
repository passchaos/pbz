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

Latest accepted comparison (`/tmp/pbz-compare-after-max-unsigned-wrapper-json-isolated.log`,
summarized in `/tmp/pbz-summary-after-max-unsigned-wrapper-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 24.82 | 124.52 (5.02x) | 67.58 (2.72x) | 127.96 (5.16x) | 934.10 (37.63x) |
| binary decode | 138.31 | 297.97 (2.15x) | 303.37 (2.19x) | 270.42 (1.96x) | 986.70 (7.13x) |
| unknown count by number | 5.02 | — | — | 225.92 (45.00x) | — |
| scalarmix encode | 27.07 | 113.90 (4.21x) | 69.40 (2.56x) | 47.51 (1.76x) | 239.02 (8.83x) |
| scalarmix decode | 50.73 | 163.53 (3.22x) | 212.79 (4.19x) | 114.83 (2.26x) | 362.22 (7.14x) |
| textbytes encode | 13.53 | 91.96 (6.80x) | 43.30 (3.20x) | 148.21 (10.95x) | 171.17 (12.65x) |
| complex decode | 227.28 | 463.06 (2.04x) | 437.98 (1.93x) | 484.96 (2.13x) | 1630.65 (7.17x) |
| complex JSON parse | 2743.24 | — | — | 16695.90 (6.09x) | 10545.78 (3.84x) |
| Any WKT JSON stringify | 167.43 | — | — | 3069.14 (18.33x) | 1360.95 (8.13x) |
| Any WKT JSON parse | 563.03 | — | — | 4692.94 (8.34x) | 2068.99 (3.67x) |
| Any NegativeDuration WKT JSON stringify | 174.35 | — | — | 3115.39 (17.87x) | 1397.25 (8.01x) |
| Any NegativeDuration WKT JSON parse | 567.72 | — | — | 4779.35 (8.42x) | 2160.13 (3.80x) |
| Any FractionalNegativeDuration WKT JSON stringify | 164.48 | — | — | 3036.37 (18.46x) | 1392.06 (8.46x) |
| Any FractionalNegativeDuration WKT JSON parse | 559.08 | — | — | 4791.49 (8.57x) | 2111.87 (3.78x) |
| Any MaxDuration WKT JSON stringify | 151.06 | — | — | 2699.57 (17.87x) | 1329.01 (8.80x) |
| Any MaxDuration WKT JSON parse | 584.88 | — | — | 4521.27 (7.73x) | 2131.44 (3.64x) |
| Any MinDuration WKT JSON stringify | 153.19 | — | — | 2705.92 (17.66x) | 1367.29 (8.93x) |
| Any MinDuration WKT JSON parse | 586.98 | — | — | 4632.29 (7.89x) | 2113.16 (3.60x) |
| Any ZeroDuration WKT JSON stringify | 136.02 | — | — | 1289.76 (9.48x) | 1228.44 (9.03x) |
| Any ZeroDuration WKT JSON parse | 513.21 | — | — | 3361.33 (6.55x) | 1950.95 (3.80x) |
| Any FieldMask WKT JSON stringify | 277.11 | — | — | 2506.49 (9.05x) | 1766.97 (6.38x) |
| Any FieldMask WKT JSON parse | 781.21 | — | — | 4836.30 (6.19x) | 2909.14 (3.72x) |
| Any Timestamp WKT JSON stringify | 234.95 | — | — | 2999.25 (12.77x) | 1373.00 (5.84x) |
| Any Timestamp WKT JSON parse | 634.50 | — | — | 4614.35 (7.27x) | 2247.34 (3.54x) |
| Any PreEpoch Timestamp WKT JSON stringify | 184.48 | — | — | 2894.23 (15.69x) | 1299.44 (7.04x) |
| Any PreEpoch Timestamp WKT JSON parse | 615.18 | — | — | 4640.84 (7.54x) | 2222.71 (3.61x) |
| Any Max Timestamp WKT JSON stringify | 209.04 | — | — | 3057.90 (14.63x) | 1369.78 (6.55x) |
| Any Max Timestamp WKT JSON parse | 650.33 | — | — | 4665.91 (7.17x) | 2290.92 (3.52x) |
| Any Min Timestamp WKT JSON stringify | 217.64 | — | — | 2915.32 (13.40x) | 1316.67 (6.05x) |
| Any Min Timestamp WKT JSON parse | 613.07 | — | — | 4723.58 (7.70x) | 2190.68 (3.57x) |
| Any Empty WKT JSON stringify | 113.72 | — | — | 1284.70 (11.30x) | 733.07 (6.45x) |
| Any Empty WKT JSON parse | 370.60 | — | — | 3178.91 (8.58x) | 1698.29 (4.58x) |
| Any Struct WKT JSON stringify | 768.66 | — | — | 8993.93 (11.70x) | 8948.03 (11.64x) |
| Any Struct WKT JSON parse | 1959.14 | — | — | 17115.90 (8.74x) | 12639.71 (6.45x) |
| Any Value WKT JSON stringify | 787.59 | — | — | 9043.23 (11.48x) | 9556.19 (12.13x) |
| Any Value WKT JSON parse | 2018.75 | — | — | 17144.70 (8.49x) | 13251.72 (6.56x) |
| Any DoubleValue WKT JSON stringify | 241.02 | — | — | 2835.05 (11.76x) | 897.22 (3.72x) |
| Any DoubleValue WKT JSON parse | 564.52 | — | — | 4364.51 (7.73x) | 1937.62 (3.43x) |
| Any DoubleValue NaN WKT JSON stringify | 182.38 | — | — | 2275.02 (12.47x) | 796.57 (4.37x) |
| Any DoubleValue NaN WKT JSON parse | 561.61 | — | — | 4021.00 (7.16x) | 1855.05 (3.30x) |
| Any DoubleValue Infinity WKT JSON stringify | 187.60 | — | — | 2266.01 (12.08x) | 802.01 (4.28x) |
| Any DoubleValue Infinity WKT JSON parse | 567.00 | — | — | 4060.97 (7.16x) | 1870.74 (3.30x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 188.23 | — | — | 2262.54 (12.02x) | 785.55 (4.17x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 570.88 | — | — | 4095.19 (7.17x) | 1865.34 (3.27x) |
| Any FloatValue WKT JSON stringify | 247.50 | — | — | 2757.70 (11.14x) | 901.73 (3.64x) |
| Any FloatValue WKT JSON parse | 565.46 | — | — | 4283.28 (7.57x) | 1878.92 (3.32x) |
| Any FloatValue NaN WKT JSON stringify | 184.76 | — | — | 2208.69 (11.95x) | 798.04 (4.32x) |
| Any FloatValue NaN WKT JSON parse | 560.83 | — | — | 4028.20 (7.18x) | 1809.78 (3.23x) |
| Any FloatValue Infinity WKT JSON stringify | 189.22 | — | — | 2194.34 (11.60x) | 799.89 (4.23x) |
| Any FloatValue Infinity WKT JSON parse | 567.19 | — | — | 4006.89 (7.06x) | 1832.60 (3.23x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 190.15 | — | — | 2174.22 (11.43x) | 798.58 (4.20x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 571.99 | — | — | 4009.05 (7.01x) | 1870.25 (3.27x) |
| Any Int64Value WKT JSON stringify | 197.94 | — | — | 2124.28 (10.73x) | 1124.97 (5.68x) |
| Any Int64Value WKT JSON parse | 614.23 | — | — | 4245.65 (6.91x) | 2320.81 (3.78x) |
| Any NegativeInt64Value WKT JSON stringify | 200.12 | — | — | 2142.23 (10.70x) | 1121.17 (5.60x) |
| Any NegativeInt64Value WKT JSON parse | 612.57 | — | — | 4256.86 (6.95x) | 2337.75 (3.82x) |
| Any UInt64Value WKT JSON stringify | 207.60 | — | — | 2176.42 (10.48x) | 1126.08 (5.42x) |
| Any UInt64Value WKT JSON parse | 619.77 | — | — | 4221.94 (6.81x) | 2248.40 (3.63x) |
| Any MaxUInt64Value WKT JSON stringify | 211.51 | — | — | 2131.44 (10.08x) | 1148.76 (5.43x) |
| Any MaxUInt64Value WKT JSON parse | 633.60 | — | — | 4337.47 (6.85x) | 2267.52 (3.58x) |
| Any Int32Value WKT JSON stringify | 200.85 | — | — | 2213.42 (11.02x) | 849.69 (4.23x) |
| Any Int32Value WKT JSON parse | 587.61 | — | — | 4115.41 (7.00x) | 1967.77 (3.35x) |
| Any NegativeInt32Value WKT JSON stringify | 204.95 | — | — | 2239.02 (10.92x) | 858.54 (4.19x) |
| Any NegativeInt32Value WKT JSON parse | 586.68 | — | — | 4139.63 (7.06x) | 1946.05 (3.32x) |
| Any UInt32Value WKT JSON stringify | 208.70 | — | — | 2164.67 (10.37x) | 903.96 (4.33x) |
| Any UInt32Value WKT JSON parse | 593.59 | — | — | 4055.57 (6.83x) | 1955.44 (3.29x) |
| Any MaxUInt32Value WKT JSON stringify | 212.08 | — | — | 2181.05 (10.28x) | 842.44 (3.97x) |
| Any MaxUInt32Value WKT JSON parse | 607.10 | — | — | 4160.04 (6.85x) | 1992.02 (3.28x) |
| Any BoolValue WKT JSON stringify | 205.37 | — | — | 2087.80 (10.17x) | 815.97 (3.97x) |
| Any BoolValue WKT JSON parse | 538.81 | — | — | 3969.17 (7.37x) | 1724.14 (3.20x) |
| Any StringValue WKT JSON stringify | 230.54 | — | — | 2214.92 (9.61x) | 898.77 (3.90x) |
| Any StringValue WKT JSON parse | 601.80 | — | — | 4112.08 (6.83x) | 1940.52 (3.22x) |
| Any BytesValue WKT JSON stringify | 220.41 | — | — | 2263.75 (10.27x) | 947.37 (4.30x) |
| Any BytesValue WKT JSON parse | 611.02 | — | — | 4271.76 (6.99x) | 2012.41 (3.29x) |
| Nested Any WKT JSON stringify | 352.12 | — | — | 3392.59 (9.63x) | 1657.63 (4.71x) |
| Nested Any WKT JSON parse | 991.83 | — | — | 6115.59 (6.17x) | 3581.13 (3.61x) |
| Duration JSON stringify | 64.40 | — | — | 1528.75 (23.74x) | 365.47 (5.67x) |
| Duration JSON parse | 10.90 | — | — | 2308.75 (211.81x) | 425.70 (39.06x) |
| NegativeDuration JSON stringify | 65.33 | — | — | 1606.45 (24.59x) | 446.76 (6.84x) |
| NegativeDuration JSON parse | 11.09 | — | — | 2402.49 (216.64x) | 438.87 (39.57x) |
| FractionalNegativeDuration JSON stringify | 65.32 | — | — | 1549.47 (23.72x) | 441.83 (6.76x) |
| FractionalNegativeDuration JSON parse | 11.07 | — | — | 2306.80 (208.38x) | 425.20 (38.41x) |
| MaxDuration JSON stringify | 53.18 | — | — | 1284.91 (24.16x) | 443.73 (8.34x) |
| MaxDuration JSON parse | 29.22 | — | — | 2241.50 (76.71x) | 445.48 (15.25x) |
| MinDuration JSON stringify | 53.95 | — | — | 1306.43 (24.22x) | 451.41 (8.37x) |
| MinDuration JSON parse | 29.40 | — | — | 2250.38 (76.54x) | 439.96 (14.96x) |
| ZeroDuration JSON stringify | 48.08 | — | — | 1243.51 (25.86x) | 376.90 (7.84x) |
| ZeroDuration JSON parse | 8.78 | — | — | 2157.30 (245.71x) | 344.36 (39.22x) |
| FieldMask JSON stringify | 92.67 | — | — | 1286.95 (13.89x) | 722.28 (7.79x) |
| FieldMask JSON parse | 178.67 | — | — | 2656.03 (14.87x) | 1073.17 (6.01x) |
| Timestamp JSON stringify | 129.80 | — | — | 1710.03 (13.17x) | 464.52 (3.58x) |
| Timestamp JSON parse | 57.12 | — | — | 2310.54 (40.45x) | 478.08 (8.37x) |
| PreEpoch Timestamp JSON stringify | 85.78 | — | — | 1591.13 (18.55x) | 447.21 (5.21x) |
| PreEpoch Timestamp JSON parse | 54.81 | — | — | 2270.78 (41.43x) | 458.71 (8.37x) |
| Max Timestamp JSON stringify | 103.97 | — | — | 1745.14 (16.79x) | 465.55 (4.48x) |
| Max Timestamp JSON parse | 66.46 | — | — | 2339.33 (35.20x) | 495.57 (7.46x) |
| Min Timestamp JSON stringify | 118.43 | — | — | 1581.35 (13.35x) | 455.06 (3.84x) |
| Min Timestamp JSON parse | 52.79 | — | — | 2259.24 (42.80x) | 466.07 (8.83x) |
| Empty JSON stringify | 22.56 | — | — | 687.53 (30.48x) | 106.66 (4.73x) |
| Empty JSON parse | 75.52 | — | — | 1114.88 (14.76x) | 263.02 (3.48x) |
| Struct JSON stringify | 261.97 | — | — | 9043.58 (34.52x) | 4181.71 (15.96x) |
| Struct JSON parse | 960.89 | — | — | 17103.50 (17.80x) | 6376.14 (6.64x) |
| Value JSON stringify | 263.08 | — | — | 9919.11 (37.70x) | 4327.31 (16.45x) |
| Value JSON parse | 977.44 | — | — | 18144.80 (18.56x) | 6713.77 (6.87x) |
| ListValue JSON stringify | 195.84 | — | — | 7640.93 (39.02x) | 2828.04 (14.44x) |
| ListValue JSON parse | 738.63 | — | — | 13668.00 (18.50x) | 5247.12 (7.10x) |
| DoubleValue JSON stringify | 97.39 | — | — | 1482.11 (15.22x) | 195.39 (2.01x) |
| DoubleValue JSON parse | 113.34 | — | — | 2073.69 (18.30x) | 317.47 (2.80x) |
| DoubleValue NaN JSON stringify | 52.87 | — | — | 1023.77 (19.36x) | 143.92 (2.72x) |
| DoubleValue NaN JSON parse | 101.46 | — | — | 1708.75 (16.84x) | 306.58 (3.02x) |
| DoubleValue Infinity JSON stringify | 55.76 | — | — | 1010.90 (18.13x) | 143.94 (2.58x) |
| DoubleValue Infinity JSON parse | 104.67 | — | — | 1710.22 (16.34x) | 337.55 (3.22x) |
| DoubleValue NegativeInfinity JSON stringify | 57.20 | — | — | 1007.07 (17.61x) | 146.66 (2.56x) |
| DoubleValue NegativeInfinity JSON parse | 107.41 | — | — | 1741.96 (16.22x) | 337.84 (3.15x) |
| FloatValue JSON stringify | 103.68 | — | — | 1411.78 (13.62x) | 203.93 (1.97x) |
| FloatValue JSON parse | 112.04 | — | — | 2118.05 (18.90x) | 339.83 (3.03x) |
| FloatValue NaN JSON stringify | 52.76 | — | — | 981.17 (18.60x) | 145.02 (2.75x) |
| FloatValue NaN JSON parse | 101.30 | — | — | 1716.10 (16.94x) | 305.50 (3.02x) |
| FloatValue Infinity JSON stringify | 55.75 | — | — | 962.11 (17.26x) | 140.41 (2.52x) |
| FloatValue Infinity JSON parse | 104.49 | — | — | 1731.13 (16.57x) | 309.03 (2.96x) |
| FloatValue NegativeInfinity JSON stringify | 57.53 | — | — | 961.65 (16.72x) | 145.88 (2.54x) |
| FloatValue NegativeInfinity JSON parse | 107.00 | — | — | 1743.95 (16.30x) | 309.39 (2.89x) |
| Int64Value JSON stringify | 55.11 | — | — | 1001.47 (18.17x) | 296.71 (5.38x) |
| Int64Value JSON parse | 136.91 | — | — | 1975.20 (14.43x) | 512.70 (3.74x) |
| NegativeInt64Value JSON stringify | 54.78 | — | — | 983.68 (17.96x) | 303.56 (5.54x) |
| NegativeInt64Value JSON parse | 137.90 | — | — | 1947.17 (14.12x) | 529.58 (3.84x) |
| UInt64Value JSON stringify | 54.73 | — | — | 997.00 (18.22x) | 289.39 (5.29x) |
| UInt64Value JSON parse | 136.87 | — | — | 1936.63 (14.15x) | 498.73 (3.64x) |
| MaxUInt64Value JSON stringify | 58.36 | — | — | 994.11 (17.03x) | 303.88 (5.21x) |
| MaxUInt64Value JSON parse | 150.11 | — | — | 1969.76 (13.12x) | 521.16 (3.47x) |
| Int32Value JSON stringify | 48.21 | — | — | 976.31 (20.25x) | 146.78 (3.04x) |
| Int32Value JSON parse | 136.25 | — | — | 1890.66 (13.88x) | 336.73 (2.47x) |
| NegativeInt32Value JSON stringify | 47.95 | — | — | 987.93 (20.60x) | 146.76 (3.06x) |
| NegativeInt32Value JSON parse | 132.94 | — | — | 1900.91 (14.30x) | 344.51 (2.59x) |
| UInt32Value JSON stringify | 48.39 | — | — | 915.79 (18.93x) | 157.15 (3.25x) |
| UInt32Value JSON parse | 134.77 | — | — | 1883.47 (13.98x) | 341.62 (2.53x) |
| MaxUInt32Value JSON stringify | 48.21 | — | — | 915.99 (19.00x) | 148.79 (3.09x) |
| MaxUInt32Value JSON parse | 145.61 | — | — | 1943.02 (13.34x) | 373.44 (2.56x) |
| BoolValue JSON stringify | 42.64 | — | — | 904.53 (21.21x) | 132.13 (3.10x) |
| BoolValue JSON parse | 59.11 | — | — | 1670.70 (28.26x) | 239.34 (4.05x) |
| StringValue JSON stringify | 54.26 | — | — | 1042.00 (19.20x) | 189.89 (3.50x) |
| StringValue JSON parse | 131.42 | — | — | 1804.41 (13.73x) | 351.80 (2.68x) |
| BytesValue JSON stringify | 47.25 | — | — | 1006.80 (21.31x) | 233.38 (4.94x) |
| BytesValue JSON parse | 142.26 | — | — | 1953.74 (13.73x) | 381.66 (2.68x) |
| TextFormat parse | 842.74 | — | — | 5583.85 (6.63x) | 8199.00 (9.73x) |
| packed int32 decode | 1029.53 | 2976.71 (2.89x) | 4546.51 (4.42x) | 1342.47 (1.30x) | 4356.36 (4.23x) |
| packed bool encode | 2.38 | 2079.46 (873.72x) | 538.96 (226.45x) | 22.95 (9.64x) | 4379.23 (1840.01x) |
| packed bool decode | 272.75 | 2061.59 (7.56x) | 4165.65 (15.27x) | 1107.97 (4.06x) | 2706.10 (9.92x) |
| largebytes decode | 124.68 | 8421.86 (67.55x) | 4590.75 (36.82x) | 4220.25 (33.85x) | 24027.28 (192.71x) |
| large map decode | 37487.56 | 128771.09 (3.44x) | 117290.29 (3.13x) | 122107.00 (3.26x) | 294991.34 (7.87x) |
| shuffled large map deterministic binary encode | 36064.10 | — | — | 115608.00 (3.21x) | 456199.66 (12.65x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded zero/positive/integer-negative/fractional-negative/min-max-bound `Duration`, `Struct`, `Value`,
`FieldMask`, min/pre/post/max-bound `Timestamp`, `Empty`, positive/negative `Int64Value`, `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), normal/max `UInt64Value`, positive/negative `Int32Value`, normal/max `UInt32Value`, `BoolValue`, `StringValue`, `BytesValue`, and recursive nested `Any` payloads), direct zero/positive/integer-negative/fractional-negative/min-max-bound Duration and min/pre/post/max-bound Timestamp WKT JSON plus other direct WKT JSON, TextFormat, packed scalars, large bytes,
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
