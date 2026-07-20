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

Latest accepted comparison (`/tmp/pbz-compare-proto-name-json-final.log`,
summarized in `/tmp/pbz-summary-proto-name-json-final.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 27.44 | 105.44 (3.84x) | 69.01 (2.51x) | 110.77 (4.04x) | 862.26 (31.42x) |
| binary decode | 98.04 | 247.11 (2.52x) | 236.14 (2.41x) | 313.26 (3.20x) | 1204.23 (12.28x) |
| unknown fields count by number | 3.70 | — | — | 187.60 (50.70x) | — |
| deterministic binary encode | 70.06 | — | — | 176.89 (2.52x) | 1220.00 (17.41x) |
| scalarmix encode | 28.61 | 140.42 (4.91x) | 49.22 (1.72x) | 52.43 (1.83x) | 241.64 (8.45x) |
| scalarmix decode | 34.08 | 149.18 (4.38x) | 230.25 (6.76x) | 91.44 (2.68x) | 327.00 (9.60x) |
| textbytes encode | 17.12 | 89.22 (5.21x) | 33.62 (1.96x) | 130.30 (7.61x) | 146.81 (8.58x) |
| textbytes decode | 55.47 | 382.03 (6.89x) | 240.67 (4.34x) | 168.47 (3.04x) | 708.92 (12.78x) |
| largebytes encode | 17.56 | 2852.51 (162.44x) | 2704.71 (154.03x) | 2769.77 (157.73x) | 2825.24 (160.89x) |
| largebytes decode | 133.40 | 6186.59 (46.38x) | 3186.19 (23.88x) | 3017.50 (22.62x) | 34943.63 (261.95x) |
| presencemix encode | 18.38 | 75.80 (4.12x) | 28.89 (1.57x) | 75.76 (4.12x) | 233.18 (12.69x) |
| presencemix decode | 60.05 | 169.40 (2.82x) | 109.03 (1.82x) | 211.08 (3.52x) | 552.11 (9.19x) |
| complex encode | 50.46 | 136.80 (2.71x) | 112.35 (2.23x) | 179.07 (3.55x) | 986.98 (19.56x) |
| complex decode | 170.76 | 428.94 (2.51x) | 338.29 (1.98x) | 400.24 (2.34x) | 1593.79 (9.33x) |
| complex deterministic binary encode | 130.44 | — | — | 171.24 (1.31x) | 1231.47 (9.44x) |
| complex JSON stringify | 272.33 | — | — | 6738.40 (24.74x) | 7493.11 (27.51x) |
| complex JSON parse | 2625.90 | — | — | 15908.40 (6.06x) | 8955.35 (3.41x) |
| complex TextFormat format | 404.72 | — | — | 4883.81 (12.07x) | 6800.62 (16.80x) |
| complex TextFormat parse | 1857.00 | — | — | 8461.18 (4.56x) | 10087.07 (5.43x) |
| packed int32 encode | 984.18 | 3982.98 (4.05x) | 3062.68 (3.11x) | 1575.74 (1.60x) | 3704.83 (3.76x) |
| packed int32 decode | 763.73 | 2531.24 (3.31x) | 4276.38 (5.60x) | 1109.17 (1.45x) | 4589.06 (6.01x) |
| JSON stringify | 163.82 | — | — | 3694.73 (22.55x) | 2500.78 (15.27x) |
| JSON parse | 1512.59 | — | — | 9769.01 (6.46x) | 5391.85 (3.56x) |
| MapKeySurrogate JSON parse | 423.12 | — | — | 4470.93 (10.57x) | 1522.65 (3.60x) |
| NullFields JSON parse | 503.29 | — | — | 2502.19 (4.97x) | 796.79 (1.58x) |
| OpenEnum JSON parse | 295.86 | — | — | 4570.19 (15.45x) | 500.98 (1.69x) |
| EnumName JSON parse | 297.98 | — | — | 4806.29 (16.13x) | 540.29 (1.81x) |
| ProtoName JSON parse | 850.51 | — | — | 5323.15 (6.26x) | 1360.16 (1.60x) |
| IntExponent JSON parse | 2090.43 | — | — | 8887.15 (4.25x) | 4847.82 (2.32x) |
| Any WKT JSON stringify | 139.23 | — | — | 2482.20 (17.83x) | 1176.42 (8.45x) |
| Any WKT JSON parse | 875.95 | — | — | 3971.00 (4.53x) | 1999.97 (2.28x) |
| Any Duration Escape WKT JSON parse | 655.91 | — | — | 3939.13 (6.01x) | 2149.03 (3.28x) |
| Any PlusDuration WKT JSON parse | 589.14 | — | — | 3853.23 (6.54x) | 1962.17 (3.33x) |
| Any ShortFractionDuration WKT JSON parse | 577.59 | — | — | 3738.28 (6.47x) | 1748.70 (3.03x) |
| Any MicroDuration WKT JSON stringify | 141.89 | — | — | 2357.33 (16.61x) | 1307.08 (9.21x) |
| Any MicroDuration WKT JSON parse | 540.83 | — | — | 3691.67 (6.83x) | 1858.70 (3.44x) |
| Any NanoDuration WKT JSON stringify | 143.37 | — | — | 2319.67 (16.18x) | 1317.89 (9.19x) |
| Any NanoDuration WKT JSON parse | 543.42 | — | — | 3714.55 (6.84x) | 1819.36 (3.35x) |
| Any NegativeDuration WKT JSON stringify | 146.90 | — | — | 2352.00 (16.01x) | 1150.50 (7.83x) |
| Any NegativeDuration WKT JSON parse | 529.16 | — | — | 3933.89 (7.43x) | 2033.20 (3.84x) |
| Any FractionalNegativeDuration WKT JSON stringify | 130.34 | — | — | 2479.01 (19.02x) | 1121.93 (8.61x) |
| Any FractionalNegativeDuration WKT JSON parse | 524.90 | — | — | 3912.65 (7.45x) | 1714.12 (3.27x) |
| Any MaxDuration WKT JSON stringify | 119.61 | — | — | 2194.89 (18.35x) | 1279.08 (10.69x) |
| Any MaxDuration WKT JSON parse | 546.05 | — | — | 3887.93 (7.12x) | 1908.20 (3.49x) |
| Any MinDuration WKT JSON stringify | 209.09 | — | — | 2226.19 (10.65x) | 1269.93 (6.07x) |
| Any MinDuration WKT JSON parse | 891.32 | — | — | 3728.14 (4.18x) | 1928.68 (2.16x) |
| Any ZeroDuration WKT JSON stringify | 211.68 | — | — | 972.99 (4.60x) | 1077.09 (5.09x) |
| Any ZeroDuration WKT JSON parse | 549.41 | — | — | 2596.54 (4.73x) | 1602.97 (2.92x) |
| Any FieldMask WKT JSON stringify | 287.73 | — | — | 2111.44 (7.34x) | 1663.84 (5.78x) |
| Any FieldMask WKT JSON parse | 810.41 | — | — | 4083.46 (5.04x) | 2648.76 (3.27x) |
| Any FieldMask Escape WKT JSON parse | 769.44 | — | — | 3971.33 (5.16x) | 2736.79 (3.56x) |
| Any EmptyFieldMask WKT JSON stringify | 121.58 | — | — | 1355.15 (11.15x) | 815.57 (6.71x) |
| Any EmptyFieldMask WKT JSON parse | 457.94 | — | — | 2506.67 (5.47x) | 1371.49 (2.99x) |
| Any Timestamp WKT JSON stringify | 193.47 | — | — | 2451.74 (12.67x) | 1332.53 (6.89x) |
| Any Timestamp WKT JSON parse | 582.20 | — | — | 3790.42 (6.51x) | 2020.46 (3.47x) |
| Any Timestamp Escape WKT JSON parse | 597.01 | — | — | 3739.62 (6.26x) | 2097.96 (3.51x) |
| Any ShortFraction Timestamp WKT JSON parse | 966.29 | — | — | 3719.64 (3.85x) | 1914.31 (1.98x) |
| Any Micro Timestamp WKT JSON stringify | 344.88 | — | — | 2639.08 (7.65x) | 1184.73 (3.44x) |
| Any Micro Timestamp WKT JSON parse | 819.04 | — | — | 3822.67 (4.67x) | 1967.47 (2.40x) |
| Any Nano Timestamp WKT JSON stringify | 302.55 | — | — | 2422.28 (8.01x) | 1126.50 (3.72x) |
| Any Nano Timestamp WKT JSON parse | 580.11 | — | — | 3742.39 (6.45x) | 2054.67 (3.54x) |
| Any Offset Timestamp WKT JSON parse | 580.74 | — | — | 3769.48 (6.49x) | 1914.03 (3.30x) |
| Any PreEpoch Timestamp WKT JSON stringify | 146.21 | — | — | 2434.03 (16.65x) | 1098.70 (7.51x) |
| Any PreEpoch Timestamp WKT JSON parse | 555.32 | — | — | 3777.49 (6.80x) | 1850.90 (3.33x) |
| Any Max Timestamp WKT JSON stringify | 162.29 | — | — | 2751.00 (16.95x) | 1212.82 (7.47x) |
| Any Max Timestamp WKT JSON parse | 575.09 | — | — | 3779.69 (6.57x) | 2177.63 (3.79x) |
| Any Min Timestamp WKT JSON stringify | 173.21 | — | — | 2303.47 (13.30x) | 1207.33 (6.97x) |
| Any Min Timestamp WKT JSON parse | 938.06 | — | — | 3887.23 (4.14x) | 1912.41 (2.04x) |
| Any Empty WKT JSON stringify | 159.49 | — | — | 1002.41 (6.29x) | 636.04 (3.99x) |
| Any Empty WKT JSON parse | 476.93 | — | — | 2766.53 (5.80x) | 1759.79 (3.69x) |
| Any Struct WKT JSON stringify | 972.53 | — | — | 7339.92 (7.55x) | 8228.87 (8.46x) |
| Any Struct WKT JSON parse | 1746.18 | — | — | 13499.20 (7.73x) | 10907.04 (6.25x) |
| Any Struct Escape WKT JSON parse | 1787.26 | — | — | 13980.60 (7.82x) | 11038.26 (6.18x) |
| Any Struct NumberExponent WKT JSON parse | 1808.33 | — | — | 13519.00 (7.48x) | 11192.35 (6.19x) |
| Any Struct Surrogate WKT JSON parse | 775.29 | — | — | 7724.29 (9.96x) | 4730.66 (6.10x) |
| Any Struct KeySurrogate WKT JSON parse | 761.12 | — | — | 7688.33 (10.10x) | 4484.78 (5.89x) |
| Any EmptyStruct WKT JSON stringify | 129.89 | — | — | 1002.17 (7.72x) | 1167.22 (8.99x) |
| Any EmptyStruct WKT JSON parse | 433.79 | — | — | 2726.00 (6.28x) | 2059.66 (4.75x) |
| Any Value WKT JSON stringify | 1169.73 | — | — | 7270.30 (6.22x) | 8401.34 (7.18x) |
| Any Value WKT JSON parse | 1905.03 | — | — | 14234.40 (7.47x) | 11710.43 (6.15x) |
| Any Value Escape WKT JSON parse | 1827.24 | — | — | 14479.60 (7.92x) | 12499.53 (6.84x) |
| Any Value NumberExponent WKT JSON parse | 2264.01 | — | — | 14648.70 (6.47x) | 11782.23 (5.20x) |
| Any Value Surrogate WKT JSON parse | 860.20 | — | — | 7866.02 (9.14x) | 4437.32 (5.16x) |
| Any Value KeySurrogate WKT JSON parse | 838.46 | — | — | 7903.17 (9.43x) | 4363.57 (5.20x) |
| Any NullValue WKT JSON stringify | 140.37 | — | — | 3893.42 (27.74x) | 1142.64 (8.14x) |
| Any NullValue WKT JSON parse | 464.38 | — | — | 4744.42 (10.22x) | 1988.26 (4.28x) |
| Any StringScalarValue WKT JSON stringify | 160.59 | — | — | 2713.10 (16.89x) | 1433.08 (8.92x) |
| Any StringScalarValue WKT JSON parse | 518.81 | — | — | 4283.08 (8.26x) | 2119.14 (4.08x) |
| Any StringScalarValue Escape WKT JSON parse | 535.07 | — | — | 4552.53 (8.51x) | 2001.68 (3.74x) |
| Any StringScalarValue Surrogate WKT JSON parse | 888.01 | — | — | 4736.10 (5.33x) | 2199.18 (2.48x) |
| Any EmptyStringScalarValue WKT JSON stringify | 231.30 | — | — | 2830.95 (12.24x) | 1063.77 (4.60x) |
| Any EmptyStringScalarValue WKT JSON parse | 548.00 | — | — | 4508.34 (8.23x) | 1887.92 (3.45x) |
| Any NumberValue WKT JSON stringify | 232.59 | — | — | 3026.13 (13.01x) | 1223.79 (5.26x) |
| Any NumberValue WKT JSON parse | 561.61 | — | — | 4389.55 (7.82x) | 2068.08 (3.68x) |
| Any NumberValue Exponent WKT JSON parse | 517.27 | — | — | 4339.77 (8.39x) | 1953.11 (3.78x) |
| Any NegativeNumberValue WKT JSON stringify | 174.86 | — | — | 3380.13 (19.33x) | 1081.46 (6.18x) |
| Any NegativeNumberValue WKT JSON parse | 501.17 | — | — | 4466.99 (8.91x) | 1998.64 (3.99x) |
| Any ZeroNumberValue WKT JSON stringify | 144.80 | — | — | 3101.56 (21.42x) | 1391.84 (9.61x) |
| Any ZeroNumberValue WKT JSON parse | 496.65 | — | — | 4490.86 (9.04x) | 1969.47 (3.97x) |
| Any BoolScalarValue WKT JSON stringify | 128.46 | — | — | 2883.95 (22.45x) | 993.89 (7.74x) |
| Any BoolScalarValue WKT JSON parse | 461.88 | — | — | 4299.69 (9.31x) | 1937.14 (4.19x) |
| Any FalseBoolScalarValue WKT JSON stringify | 133.73 | — | — | 2633.91 (19.70x) | 957.46 (7.16x) |
| Any FalseBoolScalarValue WKT JSON parse | 466.32 | — | — | 4389.72 (9.41x) | 1906.52 (4.09x) |
| Any ListKindValue WKT JSON stringify | 957.07 | — | — | 7749.75 (8.10x) | 6363.75 (6.65x) |
| Any ListKindValue WKT JSON parse | 1614.28 | — | — | 12130.70 (7.51x) | 9074.70 (5.62x) |
| Any ListKindValue Escape WKT JSON parse | 1593.85 | — | — | 13795.50 (8.66x) | 9572.31 (6.01x) |
| Any ListKindValue Surrogate WKT JSON parse | 744.80 | — | — | 5849.92 (7.85x) | 3248.81 (4.36x) |
| Any EmptyStructKindValue WKT JSON stringify | 248.93 | — | — | 3636.69 (14.61x) | 1566.67 (6.29x) |
| Any EmptyStructKindValue WKT JSON parse | 838.28 | — | — | 6723.72 (8.02x) | 2430.36 (2.90x) |
| Any EmptyListKindValue WKT JSON stringify | 240.15 | — | — | 3260.13 (13.58x) | 1551.17 (6.46x) |
| Any EmptyListKindValue WKT JSON parse | 659.54 | — | — | 5484.13 (8.32x) | 2227.50 (3.38x) |
| Any DoubleValue WKT JSON stringify | 254.61 | — | — | 2380.70 (9.35x) | 895.43 (3.52x) |
| Any DoubleValue WKT JSON parse | 618.93 | — | — | 3399.03 (5.49x) | 1963.78 (3.17x) |
| Any DoubleValue String WKT JSON parse | 635.79 | — | — | 3427.17 (5.39x) | 1826.68 (2.87x) |
| Any DoubleValue Exponent WKT JSON parse | 609.18 | — | — | 3374.85 (5.54x) | 1844.49 (3.03x) |
| Any NegativeDoubleValue WKT JSON stringify | 242.52 | — | — | 2126.69 (8.77x) | 815.74 (3.36x) |
| Any NegativeDoubleValue WKT JSON parse | 524.13 | — | — | 3389.15 (6.47x) | 1664.60 (3.18x) |
| Any ZeroDoubleValue WKT JSON stringify | 160.80 | — | — | 997.16 (6.20x) | 774.83 (4.82x) |
| Any ZeroDoubleValue WKT JSON parse | 517.76 | — | — | 2603.00 (5.03x) | 1874.71 (3.62x) |
| Any DoubleValue NaN WKT JSON stringify | 249.36 | — | — | 1937.98 (7.77x) | 845.79 (3.39x) |
| Any DoubleValue NaN WKT JSON parse | 829.31 | — | — | 3299.92 (3.98x) | 1826.03 (2.20x) |
| Any DoubleValue Infinity WKT JSON stringify | 250.77 | — | — | 1978.80 (7.89x) | 743.89 (2.97x) |
| Any DoubleValue Infinity WKT JSON parse | 764.63 | — | — | 3388.74 (4.43x) | 1930.53 (2.52x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 189.80 | — | — | 1878.27 (9.90x) | 912.49 (4.81x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 580.78 | — | — | 3197.34 (5.51x) | 1879.47 (3.24x) |
| Any FloatValue WKT JSON stringify | 216.37 | — | — | 2462.93 (11.38x) | 919.22 (4.25x) |
| Any FloatValue WKT JSON parse | 534.73 | — | — | 3527.63 (6.60x) | 1517.53 (2.84x) |
| Any FloatValue String WKT JSON parse | 537.10 | — | — | 3729.55 (6.94x) | 1878.03 (3.50x) |
| Any FloatValue Exponent WKT JSON parse | 520.23 | — | — | 3266.49 (6.28x) | 1771.00 (3.40x) |
| Any NegativeFloatValue WKT JSON stringify | 208.47 | — | — | 2095.63 (10.05x) | 851.85 (4.09x) |
| Any NegativeFloatValue WKT JSON parse | 520.23 | — | — | 3374.91 (6.49x) | 1845.44 (3.55x) |
| Any ZeroFloatValue WKT JSON stringify | 162.31 | — | — | 1078.12 (6.64x) | 790.65 (4.87x) |
| Any ZeroFloatValue WKT JSON parse | 514.55 | — | — | 2764.36 (5.37x) | 1446.74 (2.81x) |
| Any FloatValue NaN WKT JSON stringify | 242.67 | — | — | 1884.66 (7.77x) | 829.67 (3.42x) |
| Any FloatValue NaN WKT JSON parse | 825.43 | — | — | 3077.10 (3.73x) | 1684.66 (2.04x) |
| Any FloatValue Infinity WKT JSON stringify | 248.22 | — | — | 1938.07 (7.81x) | 734.57 (2.96x) |
| Any FloatValue Infinity WKT JSON parse | 746.44 | — | — | 3225.84 (4.32x) | 1723.81 (2.31x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 207.07 | — | — | 1987.64 (9.60x) | 799.09 (3.86x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 524.08 | — | — | 3303.64 (6.30x) | 1727.30 (3.30x) |
| Any Int64Value WKT JSON stringify | 175.16 | — | — | 1881.61 (10.74x) | 1070.99 (6.11x) |
| Any Int64Value WKT JSON parse | 558.85 | — | — | 3417.82 (6.12x) | 2000.44 (3.58x) |
| Any Int64Value Number WKT JSON parse | 548.41 | — | — | 3151.60 (5.75x) | 2019.80 (3.68x) |
| Any Int64Value Exponent WKT JSON parse | 528.72 | — | — | 3265.51 (6.18x) | 1677.86 (3.17x) |
| Any ZeroInt64Value WKT JSON stringify | 170.67 | — | — | 1018.49 (5.97x) | 781.43 (4.58x) |
| Any ZeroInt64Value WKT JSON parse | 527.47 | — | — | 2781.71 (5.27x) | 1936.16 (3.67x) |
| Any NegativeInt64Value WKT JSON stringify | 176.51 | — | — | 1919.90 (10.88x) | 1047.00 (5.93x) |
| Any NegativeInt64Value WKT JSON parse | 925.47 | — | — | 3487.50 (3.77x) | 2059.13 (2.22x) |
| Any MinInt64Value WKT JSON stringify | 276.80 | — | — | 1905.55 (6.88x) | 995.93 (3.60x) |
| Any MinInt64Value WKT JSON parse | 831.76 | — | — | 3429.32 (4.12x) | 2195.53 (2.64x) |
| Any MaxInt64Value WKT JSON stringify | 189.89 | — | — | 1957.61 (10.31x) | 1035.57 (5.45x) |
| Any MaxInt64Value WKT JSON parse | 568.81 | — | — | 4321.59 (7.60x) | 2310.17 (4.06x) |
| Any UInt64Value WKT JSON stringify | 172.62 | — | — | 1906.88 (11.05x) | 1177.66 (6.82x) |
| Any UInt64Value WKT JSON parse | 559.84 | — | — | 3467.09 (6.19x) | 1919.40 (3.43x) |
| Any UInt64Value Number WKT JSON parse | 554.21 | — | — | 3395.23 (6.13x) | 2104.19 (3.80x) |
| Any UInt64Value Exponent WKT JSON parse | 533.82 | — | — | 3458.81 (6.48x) | 1906.82 (3.57x) |
| Any ZeroUInt64Value WKT JSON stringify | 170.36 | — | — | 1003.85 (5.89x) | 864.93 (5.08x) |
| Any ZeroUInt64Value WKT JSON parse | 532.62 | — | — | 2535.65 (4.76x) | 1758.72 (3.30x) |
| Any MaxUInt64Value WKT JSON stringify | 281.16 | — | — | 1849.23 (6.58x) | 966.08 (3.44x) |
| Any MaxUInt64Value WKT JSON parse | 949.25 | — | — | 3501.26 (3.69x) | 2297.67 (2.42x) |
| Any Int32Value WKT JSON stringify | 232.92 | — | — | 2054.93 (8.82x) | 878.66 (3.77x) |
| Any Int32Value WKT JSON parse | 606.11 | — | — | 3231.11 (5.33x) | 1974.95 (3.26x) |
| Any Int32Value String WKT JSON parse | 602.61 | — | — | 3012.93 (5.00x) | 1900.47 (3.15x) |
| Any Int32Value Exponent WKT JSON parse | 532.73 | — | — | 3328.82 (6.25x) | 1990.96 (3.74x) |
| Any ZeroInt32Value WKT JSON stringify | 176.11 | — | — | 1067.16 (6.06x) | 969.56 (5.51x) |
| Any ZeroInt32Value WKT JSON parse | 526.76 | — | — | 2613.10 (4.96x) | 1829.08 (3.47x) |
| Any NegativeInt32Value WKT JSON stringify | 175.33 | — | — | 1999.39 (11.40x) | 972.06 (5.54x) |
| Any NegativeInt32Value WKT JSON parse | 535.37 | — | — | 3350.38 (6.26x) | 2012.07 (3.76x) |
| Any MinInt32Value WKT JSON stringify | 177.66 | — | — | 1913.91 (10.77x) | 873.39 (4.92x) |
| Any MinInt32Value WKT JSON parse | 542.87 | — | — | 3311.37 (6.10x) | 1794.92 (3.31x) |
| Any MaxInt32Value WKT JSON stringify | 268.01 | — | — | 1950.41 (7.28x) | 911.80 (3.40x) |
| Any MaxInt32Value WKT JSON parse | 907.01 | — | — | 3205.46 (3.53x) | 1852.70 (2.04x) |
| Any UInt32Value WKT JSON stringify | 263.17 | — | — | 1946.72 (7.40x) | 870.00 (3.31x) |
| Any UInt32Value WKT JSON parse | 743.18 | — | — | 3375.10 (4.54x) | 1885.09 (2.54x) |
| Any UInt32Value String WKT JSON parse | 546.20 | — | — | 3323.77 (6.09x) | 1818.20 (3.33x) |
| Any UInt32Value Exponent WKT JSON parse | 542.91 | — | — | 3267.22 (6.02x) | 1772.83 (3.27x) |
| Any ZeroUInt32Value WKT JSON stringify | 180.55 | — | — | 975.36 (5.40x) | 864.92 (4.79x) |
| Any ZeroUInt32Value WKT JSON parse | 528.69 | — | — | 2627.41 (4.97x) | 1651.19 (3.12x) |
| Any MaxUInt32Value WKT JSON stringify | 178.71 | — | — | 1938.87 (10.85x) | 774.50 (4.33x) |
| Any MaxUInt32Value WKT JSON parse | 545.90 | — | — | 3387.18 (6.20x) | 2031.05 (3.72x) |
| Any BoolValue WKT JSON stringify | 170.90 | — | — | 1949.94 (11.41x) | 806.12 (4.72x) |
| Any BoolValue WKT JSON parse | 482.16 | — | — | 3199.62 (6.64x) | 1665.04 (3.45x) |
| Any FalseBoolValue WKT JSON stringify | 259.47 | — | — | 1108.17 (4.27x) | 756.02 (2.91x) |
| Any FalseBoolValue WKT JSON parse | 786.15 | — | — | 2499.43 (3.18x) | 1736.53 (2.21x) |
| Any StringValue WKT JSON stringify | 296.00 | — | — | 1998.05 (6.75x) | 854.57 (2.89x) |
| Any StringValue WKT JSON parse | 727.48 | — | — | 3368.64 (4.63x) | 1631.89 (2.24x) |
| Any StringValue Escape WKT JSON parse | 709.21 | — | — | 3230.14 (4.55x) | 1840.31 (2.59x) |
| Any StringValue Surrogate WKT JSON parse | 563.63 | — | — | 3577.70 (6.35x) | 1990.09 (3.53x) |
| Any EmptyStringValue WKT JSON stringify | 199.76 | — | — | 1092.17 (5.47x) | 773.08 (3.87x) |
| Any EmptyStringValue WKT JSON parse | 517.60 | — | — | 2555.16 (4.94x) | 1633.27 (3.16x) |
| Any BytesValue WKT JSON stringify | 182.50 | — | — | 2022.29 (11.08x) | 969.04 (5.31x) |
| Any BytesValue WKT JSON parse | 571.10 | — | — | 3463.53 (6.06x) | 1734.53 (3.04x) |
| Any BytesValue URL WKT JSON parse | 588.16 | — | — | 3221.83 (5.48x) | 1784.90 (3.03x) |
| Any BytesValue StandardBase64 WKT JSON parse | 701.97 | — | — | 3320.11 (4.73x) | 1733.76 (2.47x) |
| Any BytesValue Unpadded WKT JSON parse | 905.53 | — | — | 3291.25 (3.63x) | 1824.72 (2.02x) |
| Any EmptyBytesValue WKT JSON stringify | 206.74 | — | — | 1096.95 (5.31x) | 813.32 (3.93x) |
| Any EmptyBytesValue WKT JSON parse | 718.81 | — | — | 2660.71 (3.70x) | 1717.64 (2.39x) |
| Nested Any WKT JSON stringify | 299.67 | — | — | 3182.29 (10.62x) | 1908.59 (6.37x) |
| Nested Any WKT JSON parse | 861.14 | — | — | 5264.19 (6.11x) | 3636.92 (4.22x) |
| Duration JSON stringify | 57.97 | — | — | 956.70 (16.50x) | 359.69 (6.20x) |
| Duration JSON parse | 20.12 | — | — | 1839.52 (91.43x) | 414.26 (20.59x) |
| Duration Escape JSON parse | 42.21 | — | — | 2018.06 (47.81x) | 433.15 (10.26x) |
| PlusDuration JSON parse | 20.22 | — | — | 1936.43 (95.77x) | 415.92 (20.57x) |
| ShortFractionDuration JSON parse | 17.57 | — | — | 1811.79 (103.12x) | 395.68 (22.52x) |
| MicroDuration JSON stringify | 58.92 | — | — | 1014.96 (17.23x) | 388.49 (6.59x) |
| MicroDuration JSON parse | 22.23 | — | — | 1811.47 (81.49x) | 386.08 (17.37x) |
| NanoDuration JSON stringify | 57.18 | — | — | 1270.24 (22.21x) | 421.46 (7.37x) |
| NanoDuration JSON parse | 25.33 | — | — | 1816.75 (71.72x) | 418.80 (16.53x) |
| NegativeDuration JSON stringify | 58.28 | — | — | 1133.05 (19.44x) | 437.21 (7.50x) |
| NegativeDuration JSON parse | 20.75 | — | — | 1892.11 (91.19x) | 396.79 (19.12x) |
| FractionalNegativeDuration JSON stringify | 58.28 | — | — | 1194.10 (20.49x) | 438.34 (7.52x) |
| FractionalNegativeDuration JSON parse | 20.81 | — | — | 1807.34 (86.85x) | 361.30 (17.36x) |
| MaxDuration JSON stringify | 49.15 | — | — | 1009.00 (20.53x) | 441.30 (8.98x) |
| MaxDuration JSON parse | 35.18 | — | — | 1774.62 (50.44x) | 454.09 (12.91x) |
| MinDuration JSON stringify | 49.55 | — | — | 1034.35 (20.87x) | 430.97 (8.70x) |
| MinDuration JSON parse | 35.86 | — | — | 1803.10 (50.28x) | 429.43 (11.98x) |
| ZeroDuration JSON stringify | 44.54 | — | — | 903.80 (20.29x) | 428.57 (9.62x) |
| ZeroDuration JSON parse | 16.09 | — | — | 1728.55 (107.43x) | 271.59 (16.88x) |
| FieldMask JSON stringify | 66.19 | — | — | 1079.06 (16.30x) | 705.38 (10.66x) |
| FieldMask JSON parse | 138.99 | — | — | 2361.32 (16.99x) | 966.86 (6.96x) |
| FieldMask Escape JSON parse | 197.12 | — | — | 2513.77 (12.75x) | 1217.56 (6.18x) |
| EmptyFieldMask JSON stringify | 40.86 | — | — | 3803.95 (93.10x) | 200.59 (4.91x) |
| EmptyFieldMask JSON parse | 4.79 | — | — | 3334.57 (696.15x) | 266.55 (55.65x) |
| Timestamp JSON stringify | 95.58 | — | — | 2422.43 (25.34x) | 477.35 (4.99x) |
| Timestamp JSON parse | 46.44 | — | — | 3752.72 (80.81x) | 489.56 (10.54x) |
| Timestamp Escape JSON parse | 99.47 | — | — | 2303.50 (23.16x) | 515.38 (5.18x) |
| ShortFraction Timestamp JSON parse | 43.51 | — | — | 2462.05 (56.59x) | 496.95 (11.42x) |
| Micro Timestamp JSON stringify | 96.69 | — | — | 1350.02 (13.96x) | 454.91 (4.70x) |
| Micro Timestamp JSON parse | 47.47 | — | — | 1870.52 (39.40x) | 459.19 (9.67x) |
| Nano Timestamp JSON stringify | 168.05 | — | — | 1349.30 (8.03x) | 504.99 (3.00x) |
| Nano Timestamp JSON parse | 91.11 | — | — | 1892.56 (20.77x) | 489.02 (5.37x) |
| Offset Timestamp JSON parse | 96.12 | — | — | 1981.04 (20.61x) | 522.09 (5.43x) |
| PreEpoch Timestamp JSON stringify | 106.99 | — | — | 1215.19 (11.36x) | 399.86 (3.74x) |
| PreEpoch Timestamp JSON parse | 74.85 | — | — | 1790.81 (23.93x) | 449.51 (6.01x) |
| Max Timestamp JSON stringify | 131.54 | — | — | 1532.05 (11.65x) | 476.22 (3.62x) |
| Max Timestamp JSON parse | 93.35 | — | — | 1842.98 (19.74x) | 448.42 (4.80x) |
| Min Timestamp JSON stringify | 151.41 | — | — | 1385.70 (9.15x) | 433.87 (2.87x) |
| Min Timestamp JSON parse | 71.04 | — | — | 1813.09 (25.52x) | 403.79 (5.68x) |
| Empty JSON stringify | 28.78 | — | — | 1477.59 (51.34x) | 130.73 (4.54x) |
| Empty JSON parse | 88.87 | — | — | 1169.46 (13.16x) | 217.72 (2.45x) |
| Struct JSON stringify | 330.59 | — | — | 8436.77 (25.52x) | 3694.48 (11.18x) |
| Struct JSON parse | 1000.85 | — | — | 17870.30 (17.86x) | 6136.01 (6.13x) |
| Struct Escape JSON parse | 910.59 | — | — | 15808.20 (17.36x) | 6480.51 (7.12x) |
| Struct NumberExponent JSON parse | 864.66 | — | — | 16949.60 (19.60x) | 6003.66 (6.94x) |
| Struct Surrogate JSON parse | 371.63 | — | — | 8731.99 (23.50x) | 1441.70 (3.88x) |
| Struct KeySurrogate JSON parse | 371.28 | — | — | 8422.08 (22.68x) | 1712.98 (4.61x) |
| EmptyStruct JSON stringify | 40.64 | — | — | 1085.51 (26.71x) | 350.45 (8.62x) |
| EmptyStruct JSON parse | 87.61 | — | — | 2288.83 (26.13x) | 403.26 (4.60x) |
| Value JSON stringify | 183.39 | — | — | 11758.10 (64.12x) | 3997.48 (21.80x) |
| Value JSON parse | 1255.22 | — | — | 22823.60 (18.18x) | 6689.68 (5.33x) |
| Value Escape JSON parse | 1243.19 | — | — | 20949.40 (16.85x) | 6856.91 (5.52x) |
| Value NumberExponent JSON parse | 869.51 | — | — | 14644.10 (16.84x) | 6122.91 (7.04x) |
| Value Surrogate JSON parse | 394.93 | — | — | 8187.97 (20.73x) | 1924.69 (4.87x) |
| Value KeySurrogate JSON parse | 394.50 | — | — | 8064.53 (20.44x) | 1877.62 (4.76x) |
| NullValue JSON stringify | 40.27 | — | — | 1493.33 (37.08x) | 246.47 (6.12x) |
| NullValue JSON parse | 70.33 | — | — | 2844.52 (40.45x) | 342.71 (4.87x) |
| StringScalarValue JSON stringify | 47.38 | — | — | 1697.94 (35.84x) | 281.08 (5.93x) |
| StringScalarValue JSON parse | 140.39 | — | — | 2430.81 (17.31x) | 419.11 (2.99x) |
| StringScalarValue Escape JSON parse | 150.66 | — | — | 2483.72 (16.49x) | 493.86 (3.28x) |
| StringScalarValue Surrogate JSON parse | 148.74 | — | — | 2477.90 (16.66x) | 498.28 (3.35x) |
| EmptyStringScalarValue JSON stringify | 45.83 | — | — | 1604.05 (35.00x) | 282.88 (6.17x) |
| EmptyStringScalarValue JSON parse | 87.82 | — | — | 2462.92 (28.05x) | 359.63 (4.10x) |
| NumberValue JSON stringify | 73.54 | — | — | 1839.54 (25.01x) | 336.85 (4.58x) |
| NumberValue JSON parse | 133.30 | — | — | 2609.95 (19.58x) | 424.80 (3.19x) |
| NumberValue Exponent JSON parse | 135.83 | — | — | 2625.35 (19.33x) | 438.00 (3.22x) |
| NegativeNumberValue JSON stringify | 138.20 | — | — | 1936.18 (14.01x) | 345.32 (2.50x) |
| NegativeNumberValue JSON parse | 165.32 | — | — | 2533.94 (15.33x) | 403.19 (2.44x) |
| ZeroNumberValue JSON stringify | 82.68 | — | — | 1887.84 (22.83x) | 344.79 (4.17x) |
| ZeroNumberValue JSON parse | 157.08 | — | — | 2471.61 (15.73x) | 394.31 (2.51x) |
| BoolScalarValue JSON stringify | 54.02 | — | — | 1449.48 (26.83x) | 261.08 (4.83x) |
| BoolScalarValue JSON parse | 84.71 | — | — | 2349.34 (27.73x) | 332.07 (3.92x) |
| FalseBoolScalarValue JSON stringify | 53.74 | — | — | 1594.13 (29.66x) | 213.67 (3.98x) |
| FalseBoolScalarValue JSON parse | 85.50 | — | — | 2360.60 (27.61x) | 366.97 (4.29x) |
| ListKindValue JSON stringify | 271.39 | — | — | 7503.16 (27.65x) | 2844.84 (10.48x) |
| ListKindValue JSON parse | 918.24 | — | — | 12561.80 (13.68x) | 5442.72 (5.93x) |
| ListKindValue Escape JSON parse | 798.52 | — | — | 12609.40 (15.79x) | 5687.79 (7.12x) |
| ListKindValue Surrogate JSON parse | 321.79 | — | — | 5882.25 (18.28x) | 1662.84 (5.17x) |
| EmptyStructKindValue JSON stringify | 42.47 | — | — | 2304.50 (54.26x) | 590.30 (13.90x) |
| EmptyStructKindValue JSON parse | 110.74 | — | — | 4510.00 (40.73x) | 759.49 (6.86x) |
| EmptyListKindValue JSON stringify | 41.12 | — | — | 2268.89 (55.18x) | 383.23 (9.32x) |
| EmptyListKindValue JSON parse | 148.37 | — | — | 5570.60 (37.55x) | 654.29 (4.41x) |
| ListValue JSON stringify | 144.33 | — | — | 7766.90 (53.81x) | 2619.46 (18.15x) |
| ListValue JSON parse | 659.72 | — | — | 10276.00 (15.58x) | 4816.74 (7.30x) |
| ListValue Escape JSON parse | 680.26 | — | — | 10477.90 (15.40x) | 4821.09 (7.09x) |
| ListValue Surrogate JSON parse | 299.26 | — | — | 3762.99 (12.57x) | 922.12 (3.08x) |
| EmptyListValue JSON stringify | 47.55 | — | — | 808.20 (17.00x) | 242.06 (5.09x) |
| EmptyListValue JSON parse | 155.77 | — | — | 2751.57 (17.66x) | 301.65 (1.94x) |
| DoubleValue JSON stringify | 123.91 | — | — | 971.53 (7.84x) | 246.60 (1.99x) |
| DoubleValue JSON parse | 140.67 | — | — | 1362.49 (9.69x) | 281.63 (2.00x) |
| DoubleValue String JSON parse | 140.26 | — | — | 1520.78 (10.84x) | 389.82 (2.78x) |
| DoubleValue Exponent JSON parse | 146.63 | — | — | 1575.74 (10.75x) | 308.82 (2.11x) |
| NegativeDoubleValue JSON stringify | 122.70 | — | — | 995.64 (8.11x) | 193.85 (1.58x) |
| NegativeDoubleValue JSON parse | 142.04 | — | — | 1579.90 (11.12x) | 320.11 (2.25x) |
| ZeroDoubleValue JSON stringify | 70.30 | — | — | 1039.71 (14.79x) | 231.56 (3.29x) |
| ZeroDoubleValue JSON parse | 132.16 | — | — | 1523.84 (11.53x) | 253.31 (1.92x) |
| DoubleValue NaN JSON stringify | 68.28 | — | — | 743.41 (10.89x) | 152.85 (2.24x) |
| DoubleValue NaN JSON parse | 128.07 | — | — | 1322.81 (10.33x) | 322.40 (2.52x) |
| DoubleValue Infinity JSON stringify | 73.92 | — | — | 688.82 (9.32x) | 123.02 (1.66x) |
| DoubleValue Infinity JSON parse | 109.44 | — | — | 1347.53 (12.31x) | 285.74 (2.61x) |
| DoubleValue NegativeInfinity JSON stringify | 73.30 | — | — | 787.32 (10.74x) | 207.42 (2.83x) |
| DoubleValue NegativeInfinity JSON parse | 139.76 | — | — | 1335.12 (9.55x) | 262.07 (1.88x) |
| FloatValue JSON stringify | 124.15 | — | — | 1021.64 (8.23x) | 208.08 (1.68x) |
| FloatValue JSON parse | 116.64 | — | — | 1559.21 (13.37x) | 290.11 (2.49x) |
| FloatValue String JSON parse | 114.52 | — | — | 1258.28 (10.99x) | 409.91 (3.58x) |
| FloatValue Exponent JSON parse | 126.07 | — | — | 1599.46 (12.69x) | 276.25 (2.19x) |
| NegativeFloatValue JSON stringify | 106.90 | — | — | 959.87 (8.98x) | 217.42 (2.03x) |
| NegativeFloatValue JSON parse | 122.10 | — | — | 1618.73 (13.26x) | 299.08 (2.45x) |
| ZeroFloatValue JSON stringify | 55.95 | — | — | 776.54 (13.88x) | 143.42 (2.56x) |
| ZeroFloatValue JSON parse | 122.14 | — | — | 1523.32 (12.47x) | 278.96 (2.28x) |
| FloatValue NaN JSON stringify | 55.65 | — | — | 719.31 (12.93x) | 121.13 (2.18x) |
| FloatValue NaN JSON parse | 108.12 | — | — | 1197.24 (11.07x) | 276.03 (2.55x) |
| FloatValue Infinity JSON stringify | 48.62 | — | — | 768.91 (15.81x) | 127.59 (2.62x) |
| FloatValue Infinity JSON parse | 109.40 | — | — | 1280.80 (11.71x) | 298.40 (2.73x) |
| FloatValue NegativeInfinity JSON stringify | 48.88 | — | — | 754.83 (15.44x) | 166.48 (3.41x) |
| FloatValue NegativeInfinity JSON parse | 110.58 | — | — | 1149.85 (10.40x) | 285.74 (2.58x) |
| Int64Value JSON stringify | 51.31 | — | — | 782.30 (15.25x) | 281.49 (5.49x) |
| Int64Value JSON parse | 124.39 | — | — | 1456.35 (11.71x) | 473.63 (3.81x) |
| Int64Value Number JSON parse | 127.75 | — | — | 1627.14 (12.74x) | 359.12 (2.81x) |
| Int64Value Exponent JSON parse | 116.27 | — | — | 1512.43 (13.01x) | 357.73 (3.08x) |
| ZeroInt64Value JSON stringify | 41.98 | — | — | 755.81 (18.00x) | 188.71 (4.50x) |
| ZeroInt64Value JSON parse | 105.35 | — | — | 1268.51 (12.04x) | 357.35 (3.39x) |
| NegativeInt64Value JSON stringify | 48.86 | — | — | 719.18 (14.72x) | 349.36 (7.15x) |
| NegativeInt64Value JSON parse | 126.21 | — | — | 1572.34 (12.46x) | 483.78 (3.83x) |
| MinInt64Value JSON stringify | 50.44 | — | — | 821.69 (16.29x) | 298.34 (5.91x) |
| MinInt64Value JSON parse | 133.88 | — | — | 1625.84 (12.14x) | 472.88 (3.53x) |
| MaxInt64Value JSON stringify | 49.46 | — | — | 689.86 (13.95x) | 283.59 (5.73x) |
| MaxInt64Value JSON parse | 133.15 | — | — | 1469.64 (11.04x) | 506.05 (3.80x) |
| UInt64Value JSON stringify | 50.42 | — | — | 821.47 (16.29x) | 367.58 (7.29x) |
| UInt64Value JSON parse | 125.86 | — | — | 1500.89 (11.93x) | 491.29 (3.90x) |
| UInt64Value Number JSON parse | 127.70 | — | — | 1421.47 (11.13x) | 341.65 (2.68x) |
| UInt64Value Exponent JSON parse | 117.12 | — | — | 1694.77 (14.47x) | 347.35 (2.97x) |
| ZeroUInt64Value JSON stringify | 41.75 | — | — | 625.53 (14.98x) | 203.67 (4.88x) |
| ZeroUInt64Value JSON parse | 105.34 | — | — | 1270.77 (12.06x) | 329.12 (3.12x) |
| MaxUInt64Value JSON stringify | 50.84 | — | — | 690.48 (13.58x) | 286.85 (5.64x) |
| MaxUInt64Value JSON parse | 134.42 | — | — | 1502.83 (11.18x) | 514.48 (3.83x) |
| Int32Value JSON stringify | 46.11 | — | — | 648.13 (14.06x) | 181.41 (3.93x) |
| Int32Value JSON parse | 138.56 | — | — | 1236.63 (8.92x) | 320.34 (2.31x) |
| Int32Value String JSON parse | 137.39 | — | — | 1281.04 (9.32x) | 405.17 (2.95x) |
| Int32Value Exponent JSON parse | 179.32 | — | — | 1567.06 (8.74x) | 395.92 (2.21x) |
| ZeroInt32Value JSON stringify | 62.74 | — | — | 707.47 (11.28x) | 179.61 (2.86x) |
| ZeroInt32Value JSON parse | 160.38 | — | — | 1480.01 (9.23x) | 275.60 (1.72x) |
| NegativeInt32Value JSON stringify | 63.20 | — | — | 790.45 (12.51x) | 135.94 (2.15x) |
| NegativeInt32Value JSON parse | 170.70 | — | — | 1401.82 (8.21x) | 400.41 (2.35x) |
| MinInt32Value JSON stringify | 64.50 | — | — | 821.74 (12.74x) | 162.43 (2.52x) |
| MinInt32Value JSON parse | 193.74 | — | — | 1595.56 (8.24x) | 387.98 (2.00x) |
| MaxInt32Value JSON stringify | 64.86 | — | — | 795.89 (12.27x) | 185.00 (2.85x) |
| MaxInt32Value JSON parse | 192.24 | — | — | 2010.35 (10.46x) | 352.28 (1.83x) |
| UInt32Value JSON stringify | 63.22 | — | — | 689.52 (10.91x) | 145.71 (2.30x) |
| UInt32Value JSON parse | 169.56 | — | — | 1475.29 (8.70x) | 315.21 (1.86x) |
| UInt32Value String JSON parse | 169.01 | — | — | 1309.77 (7.75x) | 382.99 (2.27x) |
| UInt32Value Exponent JSON parse | 144.89 | — | — | 1592.22 (10.99x) | 345.32 (2.38x) |
| ZeroUInt32Value JSON stringify | 62.75 | — | — | 639.21 (10.19x) | 171.91 (2.74x) |
| ZeroUInt32Value JSON parse | 160.25 | — | — | 1318.33 (8.23x) | 267.02 (1.67x) |
| MaxUInt32Value JSON stringify | 46.71 | — | — | 734.33 (15.72x) | 146.73 (3.14x) |
| MaxUInt32Value JSON parse | 174.51 | — | — | 2017.91 (11.56x) | 333.69 (1.91x) |
| BoolValue JSON stringify | 57.16 | — | — | 621.07 (10.87x) | 146.62 (2.57x) |
| BoolValue JSON parse | 60.20 | — | — | 1229.38 (20.42x) | 215.13 (3.57x) |
| FalseBoolValue JSON stringify | 44.09 | — | — | 642.32 (14.57x) | 178.28 (4.04x) |
| FalseBoolValue JSON parse | 73.46 | — | — | 1339.20 (18.23x) | 207.75 (2.83x) |
| StringValue JSON stringify | 73.69 | — | — | 1057.59 (14.35x) | 199.31 (2.70x) |
| StringValue JSON parse | 146.04 | — | — | 1521.24 (10.42x) | 339.94 (2.33x) |
| StringValue Escape JSON parse | 142.88 | — | — | 1917.76 (13.42x) | 358.18 (2.51x) |
| StringValue Surrogate JSON parse | 128.21 | — | — | 1451.13 (11.32x) | 375.49 (2.93x) |
| EmptyStringValue JSON stringify | 48.42 | — | — | 1000.45 (20.66x) | 197.68 (4.08x) |
| EmptyStringValue JSON parse | 66.08 | — | — | 1308.59 (19.80x) | 326.28 (4.94x) |
| BytesValue JSON stringify | 50.00 | — | — | 672.61 (13.45x) | 219.32 (4.39x) |
| BytesValue JSON parse | 124.33 | — | — | 1363.83 (10.97x) | 370.35 (2.98x) |
| BytesValue URL JSON parse | 140.40 | — | — | 2010.80 (14.32x) | 393.63 (2.80x) |
| BytesValue StandardBase64 JSON parse | 122.31 | — | — | 1826.81 (14.94x) | 334.90 (2.74x) |
| BytesValue Unpadded JSON parse | 121.94 | — | — | 1197.94 (9.82x) | 345.41 (2.83x) |
| EmptyBytesValue JSON stringify | 41.63 | — | — | 733.62 (17.62x) | 197.96 (4.76x) |
| EmptyBytesValue JSON parse | 68.98 | — | — | 1371.99 (19.89x) | 307.17 (4.45x) |
| TextFormat format | 174.78 | — | — | 3056.26 (17.49x) | 2957.13 (16.92x) |
| TextFormat parse | 730.27 | — | — | 5855.40 (8.02x) | 7325.14 (10.03x) |
| packed fixed32 encode | 2.01 | 600.91 (298.96x) | 637.51 (317.17x) | 44.24 (22.01x) | 404.68 (201.33x) |
| packed fixed32 decode | 8.64 | 1129.41 (130.72x) | 2921.39 (338.12x) | 50.30 (5.82x) | 2499.59 (289.30x) |
| packed fixed64 encode | 2.01 | 576.25 (286.69x) | 648.00 (322.39x) | 77.79 (38.70x) | 400.09 (199.05x) |
| packed fixed64 decode | 4.52 | 1295.14 (286.54x) | 7699.21 (1703.37x) | 79.44 (17.58x) | 3855.21 (852.92x) |
| packed sfixed32 encode | 2.01 | 654.48 (325.61x) | 741.59 (368.95x) | 98.42 (48.97x) | 395.40 (196.72x) |
| packed sfixed32 decode | 8.61 | 1220.47 (141.75x) | 2965.21 (344.39x) | 102.84 (11.94x) | 2346.75 (272.56x) |
| packed sfixed64 encode | 2.06 | 578.36 (280.76x) | 704.92 (342.19x) | 90.42 (43.90x) | 415.67 (201.78x) |
| packed sfixed64 decode | 4.64 | 1304.64 (281.17x) | 8029.70 (1730.54x) | 98.33 (21.19x) | 3469.11 (747.65x) |
| packed float encode | 2.01 | 836.76 (416.30x) | 542.15 (269.73x) | 92.06 (45.80x) | 355.82 (177.02x) |
| packed float decode | 9.09 | 1218.60 (134.06x) | 2471.26 (271.87x) | 107.27 (11.80x) | 2233.40 (245.70x) |
| packed double encode | 2.82 | 854.09 (302.87x) | 581.91 (206.35x) | 91.46 (32.43x) | 362.21 (128.44x) |
| packed double decode | 4.63 | 1163.63 (251.32x) | 2525.44 (545.45x) | 132.07 (28.53x) | 3893.36 (840.90x) |
| packed uint64 encode | 1314.40 | 5650.91 (4.30x) | 5039.49 (3.83x) | 2843.97 (2.16x) | 4482.89 (3.41x) |
| packed uint64 decode | 2542.30 | 3525.03 (1.39x) | 9864.34 (3.88x) | 3514.90 (1.38x) | 11460.41 (4.51x) |
| packed uint32 encode | 995.00 | 4397.62 (4.42x) | 4264.65 (4.29x) | 2148.35 (2.16x) | 3738.84 (3.76x) |
| packed uint32 decode | 1332.30 | 3082.34 (2.31x) | 3833.27 (2.88x) | 2382.83 (1.79x) | 8763.21 (6.58x) |
| packed int64 encode | 1455.00 | 12746.91 (8.76x) | 7590.50 (5.22x) | 3758.63 (2.58x) | 5695.20 (3.91x) |
| packed int64 decode | 2745.87 | 4578.80 (1.67x) | 11407.86 (4.15x) | 5724.96 (2.08x) | 14197.78 (5.17x) |
| packed sint32 encode | 778.70 | 3685.78 (4.73x) | 3545.71 (4.55x) | 1971.02 (2.53x) | 4258.81 (5.47x) |
| packed sint32 decode | 954.43 | 3151.17 (3.30x) | 3948.24 (4.14x) | 1321.71 (1.38x) | 5260.89 (5.51x) |
| packed sint64 encode | 1730.38 | 5994.09 (3.46x) | 5336.36 (3.08x) | 3273.69 (1.89x) | 5392.17 (3.12x) |
| packed sint64 decode | 2097.58 | 3940.46 (1.88x) | 10830.79 (5.16x) | 3634.27 (1.73x) | 12240.74 (5.84x) |
| packed bool encode | 2.62 | 1687.41 (644.05x) | 547.12 (208.82x) | 18.80 (7.18x) | 2678.90 (1022.48x) |
| packed bool decode | 374.03 | 1902.65 (5.09x) | 3056.84 (8.17x) | 932.20 (2.49x) | 2579.46 (6.90x) |
| packed enum encode | 507.65 | 3294.35 (6.49x) | 2117.06 (4.17x) | 1209.28 (2.38x) | 3075.00 (6.06x) |
| packed enum decode | 153.77 | 1894.49 (12.32x) | 3279.40 (21.33x) | 804.81 (5.23x) | 3790.86 (24.65x) |
| large map encode | 4017.26 | 20229.37 (5.04x) | 10317.59 (2.57x) | 24228.30 (6.03x) | 243584.25 (60.63x) |
| shuffled large map deterministic binary encode | 33929.12 | — | — | 100816.00 (2.97x) | 448367.18 (13.21x) |
| large map decode | 29025.90 | 110591.06 (3.81x) | 109912.26 (3.79x) | 107109.00 (3.69x) | 366945.01 (12.64x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON (including generated `map<string, int32>` surrogate-pair key parse, null-field parse, enum-name parse, proto-name parse, open-enum numeric parse, and integer numeric-exponent parse), Any/WKT JSON (including embedded zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound `Duration`, non-empty/escaped-input parse/number-exponent parse/surrogate-pair value parse/surrogate-pair key parse and empty `Struct`, object/escaped-object parse/object-number-exponent/object-surrogate-pair value parse/object-surrogate-pair key parse/list/escaped-list/surrogate-list/string-scalar/escaped-string-scalar/surrogate-string-scalar/number-exponent/negative-number `Value` (including default-like scalar and empty object/list kinds),
`FieldMask` (non-empty, escaped JSON parse input, and empty), escaped-input parse/short-fraction parse/micro/nano/offset/min/pre/post/max-bound `Timestamp`, `Empty`, min/zero/positive/number-input parse/numeric-exponent parse/negative/max `Int64Value`, negative/zero/positive finite/string-input parse/numeric-exponent parse `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), negative/zero/positive finite/string-input parse/numeric-exponent parse `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), zero/normal/number-input parse/numeric-exponent parse/max `UInt64Value`, min/zero/positive/string-input parse/numeric-exponent parse/negative/max `Int32Value`, zero/normal/string-input parse/numeric-exponent parse/max `UInt32Value`, true/false `BoolValue`, non-empty/escape-input parse/surrogate-pair parse/empty `StringValue`, padded-standard/base64url/unpadded-base64 parse/empty `BytesValue`, and recursive nested `Any` payloads), direct zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound Duration, non-empty/escaped-input parse/empty FieldMask, and escaped-input parse/short-fraction parse/micro/nano/offset/min/pre/post/max-bound Timestamp WKT JSON plus other direct WKT JSON, including non-empty/escaped-input parse/number-exponent parse/surrogate-pair value parse/surrogate-pair key parse/empty `Struct`, object/escaped-object parse/object-number-exponent/object-surrogate-pair value parse/object-surrogate-pair key parse/list/escaped-list/surrogate-list/string-scalar/escaped-string-scalar/surrogate-string-scalar/number-exponent/negative-number `Value`, and escaped/surrogate-pair/non-empty/empty `ListValue`, TextFormat, packed scalars, large bytes,
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
