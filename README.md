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

Latest accepted comparison (`/tmp/pbz-compare-ignore-unknown-json-final.log`,
summarized in `/tmp/pbz-summary-ignore-unknown-json-final.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Pivoted rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 19.81 | 124.03 (6.26x) | 70.30 (3.55x) | 103.24 (5.21x) | 853.55 (43.09x) |
| binary decode | 94.06 | 247.05 (2.63x) | 476.39 (5.06x) | 222.76 (2.37x) | 1371.11 (14.58x) |
| unknown fields count by number | 3.65 | — | — | 236.61 (64.82x) | — |
| deterministic binary encode | 80.81 | — | — | 126.40 (1.56x) | 1479.68 (18.31x) |
| scalarmix encode | 18.80 | 92.81 (4.94x) | 63.49 (3.38x) | 28.23 (1.50x) | 212.62 (11.31x) |
| scalarmix decode | 34.58 | 135.41 (3.92x) | 243.41 (7.04x) | 79.66 (2.30x) | 293.62 (8.49x) |
| textbytes encode | 14.53 | 98.99 (6.81x) | 59.46 (4.09x) | 117.29 (8.07x) | 199.75 (13.75x) |
| textbytes decode | 43.91 | 381.64 (8.69x) | 319.48 (7.28x) | 166.08 (3.78x) | 858.22 (19.54x) |
| largebytes encode | 17.58 | 2737.96 (155.74x) | 3400.16 (193.41x) | 2713.77 (154.37x) | 2877.91 (163.70x) |
| largebytes decode | 88.11 | 6041.96 (68.57x) | 3175.04 (36.03x) | 2761.90 (31.35x) | 31079.58 (352.74x) |
| presencemix encode | 26.60 | 56.20 (2.11x) | 34.77 (1.31x) | 59.05 (2.22x) | 224.24 (8.43x) |
| presencemix decode | 57.39 | 177.82 (3.10x) | 110.24 (1.92x) | 163.75 (2.85x) | 598.09 (10.42x) |
| complex encode | 80.86 | 143.35 (1.77x) | 95.60 (1.18x) | 164.48 (2.03x) | 1005.33 (12.43x) |
| complex decode | 169.99 | 407.87 (2.40x) | 395.50 (2.33x) | 389.96 (2.29x) | 1989.62 (11.70x) |
| complex deterministic binary encode | 98.01 | — | — | 174.53 (1.78x) | 1338.87 (13.66x) |
| complex JSON stringify | 508.31 | — | — | 6006.30 (11.82x) | 7591.44 (14.93x) |
| complex JSON parse | 2441.61 | — | — | 14567.00 (5.97x) | 8535.61 (3.50x) |
| complex TextFormat format | 255.26 | — | — | 4561.67 (17.87x) | 6698.50 (26.24x) |
| complex TextFormat parse | 1851.68 | — | — | 8245.85 (4.45x) | 9374.53 (5.06x) |
| packed int32 encode | 622.19 | 3677.51 (5.91x) | 2841.73 (4.57x) | 1386.53 (2.23x) | 3701.92 (5.95x) |
| packed int32 decode | 763.82 | 2323.26 (3.04x) | 3656.89 (4.79x) | 1147.87 (1.50x) | 4437.11 (5.81x) |
| JSON stringify | 157.83 | — | — | 3422.02 (21.68x) | 2650.86 (16.80x) |
| AlwaysPrint JSON stringify | 60.17 | — | — | 3155.29 (52.44x) | 1432.45 (23.81x) |
| ProtoName JSON stringify | 314.48 | — | — | 5498.24 (17.48x) | 4293.82 (13.65x) |
| JSON parse | 1475.33 | — | — | 8929.75 (6.05x) | 5298.60 (3.59x) |
| MapKeySurrogate JSON parse | 428.69 | — | — | 4368.42 (10.19x) | 1218.28 (2.84x) |
| NullFields JSON parse | 609.48 | — | — | 2399.78 (3.94x) | 837.58 (1.37x) |
| IgnoreUnknown JSON parse | 1741.04 | — | — | 6486.47 (3.73x) | 3019.71 (1.73x) |
| OpenEnum JSON parse | 341.45 | — | — | 4403.34 (12.90x) | 512.49 (1.50x) |
| EnumName JSON parse | 296.44 | — | — | 4548.42 (15.34x) | 515.98 (1.74x) |
| ProtoName JSON parse | 523.73 | — | — | 4786.98 (9.14x) | 1289.09 (2.46x) |
| IntExponent JSON parse | 1657.97 | — | — | 8723.18 (5.26x) | 4603.93 (2.78x) |
| Any WKT JSON stringify | 232.90 | — | — | 2601.76 (11.17x) | 1396.91 (6.00x) |
| Any WKT JSON parse | 680.74 | — | — | 3667.48 (5.39x) | 1821.63 (2.68x) |
| Any Duration Escape WKT JSON parse | 548.92 | — | — | 3595.56 (6.55x) | 2164.45 (3.94x) |
| Any PlusDuration WKT JSON parse | 526.74 | — | — | 3683.08 (6.99x) | 1827.82 (3.47x) |
| Any ShortFractionDuration WKT JSON parse | 522.39 | — | — | 3570.52 (6.83x) | 1719.08 (3.29x) |
| Any MicroDuration WKT JSON stringify | 135.07 | — | — | 2329.56 (17.25x) | 1307.47 (9.68x) |
| Any MicroDuration WKT JSON parse | 528.55 | — | — | 3608.75 (6.83x) | 1893.95 (3.58x) |
| Any NanoDuration WKT JSON stringify | 143.99 | — | — | 2401.61 (16.68x) | 1005.51 (6.98x) |
| Any NanoDuration WKT JSON parse | 531.82 | — | — | 3455.13 (6.50x) | 1856.23 (3.49x) |
| Any NegativeDuration WKT JSON stringify | 137.78 | — | — | 2348.74 (17.05x) | 1027.69 (7.46x) |
| Any NegativeDuration WKT JSON parse | 528.88 | — | — | 3552.19 (6.72x) | 1904.83 (3.60x) |
| Any FractionalNegativeDuration WKT JSON stringify | 250.71 | — | — | 2357.15 (9.40x) | 1116.93 (4.46x) |
| Any FractionalNegativeDuration WKT JSON parse | 850.47 | — | — | 3520.05 (4.14x) | 1857.21 (2.18x) |
| Any MaxDuration WKT JSON stringify | 217.73 | — | — | 2298.65 (10.56x) | 1038.89 (4.77x) |
| Any MaxDuration WKT JSON parse | 751.57 | — | — | 6481.52 (8.62x) | 1874.75 (2.49x) |
| Any MinDuration WKT JSON stringify | 150.76 | — | — | 5758.87 (38.20x) | 1270.25 (8.43x) |
| Any MinDuration WKT JSON parse | 724.40 | — | — | 11059.30 (15.27x) | 1818.35 (2.51x) |
| Any ZeroDuration WKT JSON stringify | 155.64 | — | — | 6745.05 (43.34x) | 1020.18 (6.55x) |
| Any ZeroDuration WKT JSON parse | 469.18 | — | — | 3773.56 (8.04x) | 1681.46 (3.58x) |
| Any FieldMask WKT JSON stringify | 229.60 | — | — | 2951.92 (12.86x) | 1581.65 (6.89x) |
| Any FieldMask WKT JSON parse | 702.59 | — | — | 5345.35 (7.61x) | 2467.27 (3.51x) |
| Any FieldMask Escape WKT JSON parse | 725.13 | — | — | 8953.85 (12.35x) | 2615.44 (3.61x) |
| Any EmptyFieldMask WKT JSON stringify | 111.44 | — | — | 1825.25 (16.38x) | 939.13 (8.43x) |
| Any EmptyFieldMask WKT JSON parse | 441.32 | — | — | 5131.23 (11.63x) | 1625.58 (3.68x) |
| Any Timestamp WKT JSON stringify | 186.85 | — | — | 4027.37 (21.55x) | 1320.86 (7.07x) |
| Any Timestamp WKT JSON parse | 563.79 | — | — | 6669.34 (11.83x) | 1910.22 (3.39x) |
| Any Timestamp Escape WKT JSON parse | 988.93 | — | — | 5541.56 (5.60x) | 2048.58 (2.07x) |
| Any ShortFraction Timestamp WKT JSON parse | 771.10 | — | — | 3543.66 (4.60x) | 1941.69 (2.52x) |
| Any Micro Timestamp WKT JSON stringify | 278.90 | — | — | 2104.60 (7.55x) | 1183.43 (4.24x) |
| Any Micro Timestamp WKT JSON parse | 663.85 | — | — | 4030.19 (6.07x) | 1999.75 (3.01x) |
| Any Nano Timestamp WKT JSON stringify | 183.33 | — | — | 2637.08 (14.38x) | 1119.39 (6.11x) |
| Any Nano Timestamp WKT JSON parse | 576.12 | — | — | 3919.62 (6.80x) | 1990.89 (3.46x) |
| Any Offset Timestamp WKT JSON parse | 581.11 | — | — | 4069.50 (7.00x) | 1912.45 (3.29x) |
| Any PreEpoch Timestamp WKT JSON stringify | 145.00 | — | — | 2550.80 (17.59x) | 1003.93 (6.92x) |
| Any PreEpoch Timestamp WKT JSON parse | 555.41 | — | — | 3937.87 (7.09x) | 1926.40 (3.47x) |
| Any Max Timestamp WKT JSON stringify | 166.00 | — | — | 2622.38 (15.80x) | 1026.71 (6.19x) |
| Any Max Timestamp WKT JSON parse | 578.21 | — | — | 3596.81 (6.22x) | 1869.59 (3.23x) |
| Any Min Timestamp WKT JSON stringify | 164.03 | — | — | 2543.66 (15.51x) | 1028.28 (6.27x) |
| Any Min Timestamp WKT JSON parse | 554.43 | — | — | 3589.89 (6.47x) | 2048.91 (3.70x) |
| Any Empty WKT JSON stringify | 91.58 | — | — | 929.71 (10.15x) | 784.69 (8.57x) |
| Any Empty WKT JSON parse | 485.79 | — | — | 2851.80 (5.87x) | 1624.79 (3.34x) |
| Any Struct WKT JSON stringify | 1168.50 | — | — | 11728.40 (10.04x) | 7335.51 (6.28x) |
| Any Struct WKT JSON parse | 1740.56 | — | — | 17513.60 (10.06x) | 10036.70 (5.77x) |
| Any Struct Escape WKT JSON parse | 1757.29 | — | — | 13842.20 (7.88x) | 10538.65 (6.00x) |
| Any Struct NumberExponent WKT JSON parse | 1747.70 | — | — | 13406.50 (7.67x) | 11138.24 (6.37x) |
| Any Struct Surrogate WKT JSON parse | 1071.24 | — | — | 7825.74 (7.31x) | 3584.90 (3.35x) |
| Any Struct KeySurrogate WKT JSON parse | 752.54 | — | — | 10329.60 (13.73x) | 3786.55 (5.03x) |
| Any EmptyStruct WKT JSON stringify | 118.00 | — | — | 1236.72 (10.48x) | 987.48 (8.37x) |
| Any EmptyStruct WKT JSON parse | 433.69 | — | — | 2714.12 (6.26x) | 1998.92 (4.61x) |
| Any Value WKT JSON stringify | 688.61 | — | — | 7266.64 (10.55x) | 7695.39 (11.18x) |
| Any Value WKT JSON parse | 2343.57 | — | — | 13939.00 (5.95x) | 10929.79 (4.66x) |
| Any Value Escape WKT JSON parse | 1837.10 | — | — | 14073.90 (7.66x) | 10832.14 (5.90x) |
| Any Value NumberExponent WKT JSON parse | 1789.72 | — | — | 13716.90 (7.66x) | 10900.57 (6.09x) |
| Any Value Surrogate WKT JSON parse | 805.35 | — | — | 7883.44 (9.79x) | 3924.11 (4.87x) |
| Any Value KeySurrogate WKT JSON parse | 1349.53 | — | — | 7771.37 (5.76x) | 4090.17 (3.03x) |
| Any NullValue WKT JSON stringify | 203.72 | — | — | 2673.18 (13.12x) | 892.91 (4.38x) |
| Any NullValue WKT JSON parse | 649.62 | — | — | 4733.85 (7.29x) | 1828.59 (2.81x) |
| Any StringScalarValue WKT JSON stringify | 161.82 | — | — | 2681.14 (16.57x) | 1111.52 (6.87x) |
| Any StringScalarValue WKT JSON parse | 662.61 | — | — | 4397.59 (6.64x) | 2065.03 (3.12x) |
| Any StringScalarValue Escape WKT JSON parse | 519.56 | — | — | 4459.82 (8.58x) | 2030.42 (3.91x) |
| Any StringScalarValue Surrogate WKT JSON parse | 521.71 | — | — | 4409.59 (8.45x) | 2015.79 (3.86x) |
| Any EmptyStringScalarValue WKT JSON stringify | 136.80 | — | — | 2700.46 (19.74x) | 981.11 (7.17x) |
| Any EmptyStringScalarValue WKT JSON parse | 477.70 | — | — | 4380.10 (9.17x) | 1826.93 (3.82x) |
| Any NumberValue WKT JSON stringify | 172.59 | — | — | 2930.39 (16.98x) | 1025.19 (5.94x) |
| Any NumberValue WKT JSON parse | 494.37 | — | — | 4488.11 (9.08x) | 1999.58 (4.04x) |
| Any NumberValue Exponent WKT JSON parse | 498.53 | — | — | 4467.55 (8.96x) | 1897.86 (3.81x) |
| Any NegativeNumberValue WKT JSON stringify | 173.63 | — | — | 2918.40 (16.81x) | 1247.50 (7.18x) |
| Any NegativeNumberValue WKT JSON parse | 496.87 | — | — | 4409.95 (8.88x) | 1940.31 (3.91x) |
| Any ZeroNumberValue WKT JSON stringify | 246.54 | — | — | 2880.44 (11.68x) | 1118.87 (4.54x) |
| Any ZeroNumberValue WKT JSON parse | 797.07 | — | — | 4313.76 (5.41x) | 1867.37 (2.34x) |
| Any BoolScalarValue WKT JSON stringify | 202.43 | — | — | 2673.73 (13.21x) | 1060.05 (5.24x) |
| Any BoolScalarValue WKT JSON parse | 591.90 | — | — | 4343.31 (7.34x) | 1719.16 (2.90x) |
| Any FalseBoolScalarValue WKT JSON stringify | 142.07 | — | — | 2610.48 (18.37x) | 1135.74 (7.99x) |
| Any FalseBoolScalarValue WKT JSON parse | 625.48 | — | — | 4274.04 (6.83x) | 1843.00 (2.95x) |
| Any ListKindValue WKT JSON stringify | 514.03 | — | — | 6626.40 (12.89x) | 5791.30 (11.27x) |
| Any ListKindValue WKT JSON parse | 1390.10 | — | — | 11947.30 (8.59x) | 8377.11 (6.03x) |
| Any ListKindValue Escape WKT JSON parse | 1415.12 | — | — | 12115.60 (8.56x) | 8629.92 (6.10x) |
| Any ListKindValue Surrogate WKT JSON parse | 721.16 | — | — | 5946.05 (8.25x) | 3035.84 (4.21x) |
| Any EmptyStructKindValue WKT JSON stringify | 229.92 | — | — | 3498.57 (15.22x) | 1595.79 (6.94x) |
| Any EmptyStructKindValue WKT JSON parse | 808.10 | — | — | 6514.83 (8.06x) | 2685.28 (3.32x) |
| Any EmptyListKindValue WKT JSON stringify | 217.57 | — | — | 3459.42 (15.90x) | 1408.65 (6.47x) |
| Any EmptyListKindValue WKT JSON parse | 658.89 | — | — | 5297.28 (8.04x) | 2113.88 (3.21x) |
| Any DoubleValue WKT JSON stringify | 301.44 | — | — | 2194.47 (7.28x) | 1150.84 (3.82x) |
| Any DoubleValue WKT JSON parse | 514.67 | — | — | 3159.61 (6.14x) | 1820.97 (3.54x) |
| Any DoubleValue String WKT JSON parse | 523.73 | — | — | 3258.29 (6.22x) | 1901.11 (3.63x) |
| Any DoubleValue Exponent WKT JSON parse | 517.67 | — | — | 3399.78 (6.57x) | 1719.42 (3.32x) |
| Any NegativeDoubleValue WKT JSON stringify | 193.55 | — | — | 2201.43 (11.37x) | 1157.27 (5.98x) |
| Any NegativeDoubleValue WKT JSON parse | 512.24 | — | — | 3269.39 (6.38x) | 1643.70 (3.21x) |
| Any ZeroDoubleValue WKT JSON stringify | 161.06 | — | — | 930.96 (5.78x) | 944.41 (5.86x) |
| Any ZeroDoubleValue WKT JSON parse | 509.67 | — | — | 2553.55 (5.01x) | 1573.32 (3.09x) |
| Any DoubleValue NaN WKT JSON stringify | 165.77 | — | — | 1956.78 (11.80x) | 858.16 (5.18x) |
| Any DoubleValue NaN WKT JSON parse | 507.61 | — | — | 3091.91 (6.09x) | 1558.27 (3.07x) |
| Any DoubleValue Infinity WKT JSON stringify | 249.86 | — | — | 1952.92 (7.82x) | 864.47 (3.46x) |
| Any DoubleValue Infinity WKT JSON parse | 811.28 | — | — | 3069.50 (3.78x) | 1762.69 (2.17x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 248.03 | — | — | 1956.41 (7.89x) | 883.46 (3.56x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 708.60 | — | — | 3072.10 (4.34x) | 1615.25 (2.28x) |
| Any FloatValue WKT JSON stringify | 203.04 | — | — | 2130.74 (10.49x) | 871.49 (4.29x) |
| Any FloatValue WKT JSON parse | 513.49 | — | — | 3206.94 (6.25x) | 1753.68 (3.42x) |
| Any FloatValue String WKT JSON parse | 522.47 | — | — | 3107.01 (5.95x) | 1839.81 (3.52x) |
| Any FloatValue Exponent WKT JSON parse | 515.89 | — | — | 3224.71 (6.25x) | 1802.95 (3.49x) |
| Any NegativeFloatValue WKT JSON stringify | 197.40 | — | — | 2155.37 (10.92x) | 1077.56 (5.46x) |
| Any NegativeFloatValue WKT JSON parse | 512.52 | — | — | 3254.87 (6.35x) | 1780.74 (3.47x) |
| Any ZeroFloatValue WKT JSON stringify | 164.79 | — | — | 950.14 (5.77x) | 704.97 (4.28x) |
| Any ZeroFloatValue WKT JSON parse | 510.69 | — | — | 2528.41 (4.95x) | 1832.03 (3.59x) |
| Any FloatValue NaN WKT JSON stringify | 161.39 | — | — | 1946.13 (12.06x) | 906.58 (5.62x) |
| Any FloatValue NaN WKT JSON parse | 508.16 | — | — | 3045.51 (5.99x) | 1742.89 (3.43x) |
| Any FloatValue Infinity WKT JSON stringify | 169.19 | — | — | 1749.11 (10.34x) | 867.10 (5.13x) |
| Any FloatValue Infinity WKT JSON parse | 512.09 | — | — | 3227.46 (6.30x) | 1777.51 (3.47x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 247.85 | — | — | 1944.13 (7.84x) | 747.21 (3.01x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 822.17 | — | — | 3176.50 (3.86x) | 1758.66 (2.14x) |
| Any Int64Value WKT JSON stringify | 276.31 | — | — | 1933.93 (7.00x) | 1194.50 (4.32x) |
| Any Int64Value WKT JSON parse | 648.04 | — | — | 3394.24 (5.24x) | 1891.98 (2.92x) |
| Any Int64Value Number WKT JSON parse | 752.45 | — | — | 3226.72 (4.29x) | 2206.74 (2.93x) |
| Any Int64Value Exponent WKT JSON parse | 526.26 | — | — | 3061.99 (5.82x) | 1895.14 (3.60x) |
| Any ZeroInt64Value WKT JSON stringify | 162.52 | — | — | 917.51 (5.65x) | 764.72 (4.71x) |
| Any ZeroInt64Value WKT JSON parse | 513.89 | — | — | 2524.98 (4.91x) | 1678.13 (3.27x) |
| Any NegativeInt64Value WKT JSON stringify | 173.88 | — | — | 1929.45 (11.10x) | 857.98 (4.93x) |
| Any NegativeInt64Value WKT JSON parse | 547.20 | — | — | 3310.83 (6.05x) | 1915.56 (3.50x) |
| Any MinInt64Value WKT JSON stringify | 177.36 | — | — | 1857.99 (10.48x) | 1330.65 (7.50x) |
| Any MinInt64Value WKT JSON parse | 555.06 | — | — | 3326.33 (5.99x) | 2003.27 (3.61x) |
| Any MaxInt64Value WKT JSON stringify | 174.87 | — | — | 1729.23 (9.89x) | 1032.16 (5.90x) |
| Any MaxInt64Value WKT JSON parse | 553.13 | — | — | 3490.22 (6.31x) | 2056.61 (3.72x) |
| Any UInt64Value WKT JSON stringify | 182.57 | — | — | 1946.10 (10.66x) | 1199.94 (6.57x) |
| Any UInt64Value WKT JSON parse | 549.59 | — | — | 3291.39 (5.99x) | 2009.31 (3.66x) |
| Any UInt64Value Number WKT JSON parse | 922.89 | — | — | 3227.87 (3.50x) | 2100.40 (2.28x) |
| Any UInt64Value Exponent WKT JSON parse | 694.33 | — | — | 3198.73 (4.61x) | 1729.48 (2.49x) |
| Any ZeroUInt64Value WKT JSON stringify | 234.02 | — | — | 1003.28 (4.29x) | 849.92 (3.63x) |
| Any ZeroUInt64Value WKT JSON parse | 644.61 | — | — | 2628.38 (4.08x) | 1767.94 (2.74x) |
| Any MaxUInt64Value WKT JSON stringify | 184.10 | — | — | 1896.61 (10.30x) | 929.32 (5.05x) |
| Any MaxUInt64Value WKT JSON parse | 549.14 | — | — | 3390.17 (6.17x) | 2048.88 (3.73x) |
| Any Int32Value WKT JSON stringify | 170.26 | — | — | 1840.20 (10.81x) | 975.84 (5.73x) |
| Any Int32Value WKT JSON parse | 525.68 | — | — | 3094.37 (5.89x) | 1664.17 (3.17x) |
| Any Int32Value String WKT JSON parse | 529.55 | — | — | 3062.65 (5.78x) | 1760.02 (3.32x) |
| Any Int32Value Exponent WKT JSON parse | 530.71 | — | — | 3075.66 (5.80x) | 1699.03 (3.20x) |
| Any ZeroInt32Value WKT JSON stringify | 170.71 | — | — | 941.15 (5.51x) | 670.82 (3.93x) |
| Any ZeroInt32Value WKT JSON parse | 520.68 | — | — | 2521.54 (4.84x) | 1611.03 (3.09x) |
| Any NegativeInt32Value WKT JSON stringify | 171.08 | — | — | 1910.75 (11.17x) | 871.83 (5.10x) |
| Any NegativeInt32Value WKT JSON parse | 699.85 | — | — | 3090.06 (4.42x) | 1826.06 (2.61x) |
| Any MinInt32Value WKT JSON stringify | 270.96 | — | — | 1940.81 (7.16x) | 892.02 (3.29x) |
| Any MinInt32Value WKT JSON parse | 897.05 | — | — | 3159.53 (3.52x) | 1786.05 (1.99x) |
| Any MaxInt32Value WKT JSON stringify | 186.45 | — | — | 1934.00 (10.37x) | 881.24 (4.73x) |
| Any MaxInt32Value WKT JSON parse | 660.34 | — | — | 3144.09 (4.76x) | 1760.99 (2.67x) |
| Any UInt32Value WKT JSON stringify | 256.24 | — | — | 1919.77 (7.49x) | 985.79 (3.85x) |
| Any UInt32Value WKT JSON parse | 527.36 | — | — | 3218.95 (6.10x) | 1843.79 (3.50x) |
| Any UInt32Value String WKT JSON parse | 535.17 | — | — | 3181.97 (5.95x) | 1691.76 (3.16x) |
| Any UInt32Value Exponent WKT JSON parse | 535.13 | — | — | 3180.53 (5.94x) | 1751.06 (3.27x) |
| Any ZeroUInt32Value WKT JSON stringify | 176.10 | — | — | 1035.89 (5.88x) | 1076.49 (6.11x) |
| Any ZeroUInt32Value WKT JSON parse | 524.17 | — | — | 2565.20 (4.89x) | 1753.78 (3.35x) |
| Any MaxUInt32Value WKT JSON stringify | 179.10 | — | — | 1859.00 (10.38x) | 761.76 (4.25x) |
| Any MaxUInt32Value WKT JSON parse | 534.07 | — | — | 3150.35 (5.90x) | 1761.71 (3.30x) |
| Any BoolValue WKT JSON stringify | 176.41 | — | — | 1907.05 (10.81x) | 805.03 (4.56x) |
| Any BoolValue WKT JSON parse | 480.85 | — | — | 2978.09 (6.19x) | 1515.15 (3.15x) |
| Any FalseBoolValue WKT JSON stringify | 256.14 | — | — | 921.38 (3.60x) | 791.44 (3.09x) |
| Any FalseBoolValue WKT JSON parse | 778.76 | — | — | 2520.78 (3.24x) | 1344.67 (1.73x) |
| Any StringValue WKT JSON stringify | 293.41 | — | — | 1900.99 (6.48x) | 863.81 (2.94x) |
| Any StringValue WKT JSON parse | 763.04 | — | — | 3014.83 (3.95x) | 1488.74 (1.95x) |
| Any StringValue Escape WKT JSON parse | 720.77 | — | — | 3159.43 (4.38x) | 1926.71 (2.67x) |
| Any StringValue Surrogate WKT JSON parse | 550.66 | — | — | 3124.80 (5.67x) | 1631.40 (2.96x) |
| Any EmptyStringValue WKT JSON stringify | 185.07 | — | — | 964.53 (5.21x) | 693.60 (3.75x) |
| Any EmptyStringValue WKT JSON parse | 510.33 | — | — | 2546.89 (4.99x) | 1968.48 (3.86x) |
| Any BytesValue WKT JSON stringify | 192.15 | — | — | 1914.42 (9.96x) | 925.66 (4.82x) |
| Any BytesValue WKT JSON parse | 551.73 | — | — | 3174.74 (5.75x) | 1761.64 (3.19x) |
| Any BytesValue URL WKT JSON parse | 571.81 | — | — | 3132.84 (5.48x) | 1803.55 (3.15x) |
| Any BytesValue StandardBase64 WKT JSON parse | 555.13 | — | — | 3093.70 (5.57x) | 1702.65 (3.07x) |
| Any BytesValue Unpadded WKT JSON parse | 555.03 | — | — | 3153.60 (5.68x) | 1780.94 (3.21x) |
| Any EmptyBytesValue WKT JSON stringify | 265.22 | — | — | 925.68 (3.49x) | 768.27 (2.90x) |
| Any EmptyBytesValue WKT JSON parse | 758.36 | — | — | 2533.78 (3.34x) | 1797.33 (2.37x) |
| Nested Any WKT JSON stringify | 463.63 | — | — | 2961.62 (6.39x) | 1808.80 (3.90x) |
| Nested Any WKT JSON parse | 1193.04 | — | — | 5027.56 (4.21x) | 3426.19 (2.87x) |
| Duration JSON stringify | 82.78 | — | — | 1067.33 (12.89x) | 360.36 (4.35x) |
| Duration JSON parse | 28.36 | — | — | 1743.34 (61.47x) | 391.31 (13.80x) |
| Duration Escape JSON parse | 63.09 | — | — | 1793.09 (28.42x) | 498.43 (7.90x) |
| PlusDuration JSON parse | 29.64 | — | — | 1797.48 (60.64x) | 550.40 (18.57x) |
| ShortFractionDuration JSON parse | 24.75 | — | — | 1819.38 (73.51x) | 355.38 (14.36x) |
| MicroDuration JSON stringify | 87.13 | — | — | 1124.27 (12.90x) | 379.55 (4.36x) |
| MicroDuration JSON parse | 33.88 | — | — | 1706.80 (50.38x) | 481.95 (14.23x) |
| NanoDuration JSON stringify | 75.20 | — | — | 1133.65 (15.08x) | 399.09 (5.31x) |
| NanoDuration JSON parse | 26.17 | — | — | 1754.88 (67.06x) | 365.48 (13.97x) |
| NegativeDuration JSON stringify | 59.39 | — | — | 1083.08 (18.24x) | 396.12 (6.67x) |
| NegativeDuration JSON parse | 19.06 | — | — | 1895.28 (99.44x) | 448.78 (23.55x) |
| FractionalNegativeDuration JSON stringify | 59.30 | — | — | 1129.11 (19.04x) | 398.15 (6.71x) |
| FractionalNegativeDuration JSON parse | 20.20 | — | — | 1833.82 (90.78x) | 343.91 (17.03x) |
| MaxDuration JSON stringify | 50.37 | — | — | 1001.82 (19.89x) | 378.35 (7.51x) |
| MaxDuration JSON parse | 31.90 | — | — | 1705.58 (53.47x) | 473.21 (14.83x) |
| MinDuration JSON stringify | 50.15 | — | — | 872.43 (17.40x) | 416.15 (8.30x) |
| MinDuration JSON parse | 33.11 | — | — | 1637.41 (49.45x) | 397.92 (12.02x) |
| ZeroDuration JSON stringify | 45.11 | — | — | 990.18 (21.95x) | 326.76 (7.24x) |
| ZeroDuration JSON parse | 15.94 | — | — | 1721.77 (108.02x) | 340.56 (21.37x) |
| FieldMask JSON stringify | 77.20 | — | — | 886.17 (11.48x) | 714.33 (9.25x) |
| FieldMask JSON parse | 145.90 | — | — | 1906.49 (13.07x) | 1068.88 (7.33x) |
| FieldMask Escape JSON parse | 208.75 | — | — | 2025.04 (9.70x) | 1024.20 (4.91x) |
| EmptyFieldMask JSON stringify | 40.88 | — | — | 611.32 (14.95x) | 253.73 (6.21x) |
| EmptyFieldMask JSON parse | 4.80 | — | — | 942.92 (196.44x) | 298.18 (62.12x) |
| Timestamp JSON stringify | 96.59 | — | — | 1263.09 (13.08x) | 566.74 (5.87x) |
| Timestamp JSON parse | 46.26 | — | — | 1791.48 (38.73x) | 468.55 (10.13x) |
| Timestamp Escape JSON parse | 100.57 | — | — | 1833.83 (18.23x) | 683.47 (6.80x) |
| ShortFraction Timestamp JSON parse | 43.52 | — | — | 1681.99 (38.65x) | 534.75 (12.29x) |
| Micro Timestamp JSON stringify | 96.55 | — | — | 1225.33 (12.69x) | 470.37 (4.87x) |
| Micro Timestamp JSON parse | 48.04 | — | — | 1825.79 (38.01x) | 574.20 (11.95x) |
| Nano Timestamp JSON stringify | 94.47 | — | — | 1298.42 (13.74x) | 424.19 (4.49x) |
| Nano Timestamp JSON parse | 51.94 | — | — | 1825.61 (35.15x) | 520.41 (10.02x) |
| Offset Timestamp JSON parse | 55.90 | — | — | 1892.83 (33.86x) | 485.25 (8.68x) |
| PreEpoch Timestamp JSON stringify | 66.86 | — | — | 1139.87 (17.05x) | 456.47 (6.83x) |
| PreEpoch Timestamp JSON parse | 42.95 | — | — | 1848.16 (43.03x) | 397.00 (9.24x) |
| Max Timestamp JSON stringify | 79.94 | — | — | 1338.88 (16.75x) | 444.00 (5.55x) |
| Max Timestamp JSON parse | 50.76 | — | — | 1933.83 (38.10x) | 619.64 (12.21x) |
| Min Timestamp JSON stringify | 80.30 | — | — | 1189.37 (14.81x) | 412.67 (5.14x) |
| Min Timestamp JSON parse | 40.90 | — | — | 1706.22 (41.72x) | 502.16 (12.28x) |
| Empty JSON stringify | 20.96 | — | — | 493.23 (23.53x) | 118.01 (5.63x) |
| Empty JSON parse | 67.21 | — | — | 721.86 (10.74x) | 195.04 (2.90x) |
| Struct JSON stringify | 176.69 | — | — | 6880.82 (38.94x) | 3707.07 (20.98x) |
| Struct JSON parse | 859.47 | — | — | 13260.00 (15.43x) | 5372.14 (6.25x) |
| Struct Escape JSON parse | 1413.89 | — | — | 13254.80 (9.37x) | 5680.81 (4.02x) |
| Struct NumberExponent JSON parse | 901.17 | — | — | 13357.50 (14.82x) | 5409.72 (6.00x) |
| Struct Surrogate JSON parse | 435.77 | — | — | 5814.76 (13.34x) | 1633.86 (3.75x) |
| Struct KeySurrogate JSON parse | 392.78 | — | — | 5730.47 (14.59x) | 1522.70 (3.88x) |
| EmptyStruct JSON stringify | 41.28 | — | — | 709.35 (17.18x) | 404.47 (9.80x) |
| EmptyStruct JSON parse | 88.66 | — | — | 2422.81 (27.33x) | 344.94 (3.89x) |
| Value JSON stringify | 192.53 | — | — | 7982.83 (41.46x) | 3776.23 (19.61x) |
| Value JSON parse | 875.39 | — | — | 14676.30 (16.77x) | 6065.12 (6.93x) |
| Value Escape JSON parse | 921.79 | — | — | 14706.80 (15.95x) | 6020.73 (6.53x) |
| Value NumberExponent JSON parse | 871.89 | — | — | 14615.50 (16.76x) | 5752.03 (6.60x) |
| Value Surrogate JSON parse | 406.84 | — | — | 8000.38 (19.66x) | 1745.22 (4.29x) |
| Value KeySurrogate JSON parse | 554.66 | — | — | 8007.61 (14.44x) | 1727.17 (3.11x) |
| NullValue JSON stringify | 54.60 | — | — | 1433.99 (26.26x) | 209.79 (3.84x) |
| NullValue JSON parse | 92.75 | — | — | 2823.37 (30.44x) | 322.26 (3.47x) |
| StringScalarValue JSON stringify | 72.06 | — | — | 1699.41 (23.58x) | 314.99 (4.37x) |
| StringScalarValue JSON parse | 179.86 | — | — | 2485.41 (13.82x) | 382.14 (2.12x) |
| StringScalarValue Escape JSON parse | 194.70 | — | — | 2479.39 (12.73x) | 457.08 (2.35x) |
| StringScalarValue Surrogate JSON parse | 201.93 | — | — | 2505.46 (12.41x) | 449.20 (2.22x) |
| EmptyStringScalarValue JSON stringify | 65.45 | — | — | 1717.20 (26.24x) | 263.36 (4.02x) |
| EmptyStringScalarValue JSON parse | 112.77 | — | — | 2426.47 (21.52x) | 377.70 (3.35x) |
| NumberValue JSON stringify | 137.36 | — | — | 1788.13 (13.02x) | 503.35 (3.66x) |
| NumberValue JSON parse | 142.49 | — | — | 2537.92 (17.81x) | 512.71 (3.60x) |
| NumberValue Exponent JSON parse | 175.26 | — | — | 2623.34 (14.97x) | 465.02 (2.65x) |
| NegativeNumberValue JSON stringify | 119.33 | — | — | 1933.13 (16.20x) | 482.32 (4.04x) |
| NegativeNumberValue JSON parse | 169.20 | — | — | 2558.37 (15.12x) | 554.41 (3.28x) |
| ZeroNumberValue JSON stringify | 79.10 | — | — | 1816.09 (22.96x) | 280.17 (3.54x) |
| ZeroNumberValue JSON parse | 143.25 | — | — | 2468.86 (17.23x) | 560.13 (3.91x) |
| BoolScalarValue JSON stringify | 52.66 | — | — | 1457.72 (27.68x) | 315.60 (5.99x) |
| BoolScalarValue JSON parse | 91.14 | — | — | 2439.67 (26.77x) | 350.37 (3.84x) |
| FalseBoolScalarValue JSON stringify | 52.69 | — | — | 1537.24 (29.18x) | 330.54 (6.27x) |
| FalseBoolScalarValue JSON parse | 91.78 | — | — | 2393.37 (26.08x) | 345.55 (3.76x) |
| ListKindValue JSON stringify | 187.78 | — | — | 7597.29 (40.46x) | 2631.44 (14.01x) |
| ListKindValue JSON parse | 686.60 | — | — | 12564.60 (18.30x) | 5043.93 (7.35x) |
| ListKindValue Escape JSON parse | 713.02 | — | — | 12805.90 (17.96x) | 5003.83 (7.02x) |
| ListKindValue Surrogate JSON parse | 328.77 | — | — | 5949.07 (18.09x) | 1233.52 (3.75x) |
| EmptyStructKindValue JSON stringify | 42.86 | — | — | 2310.73 (53.91x) | 705.94 (16.47x) |
| EmptyStructKindValue JSON parse | 118.04 | — | — | 4484.52 (37.99x) | 716.74 (6.07x) |
| EmptyListKindValue JSON stringify | 41.69 | — | — | 2293.68 (55.02x) | 369.47 (8.86x) |
| EmptyListKindValue JSON parse | 155.66 | — | — | 4727.76 (30.37x) | 782.96 (5.03x) |
| ListValue JSON stringify | 151.80 | — | — | 5909.38 (38.93x) | 2430.08 (16.01x) |
| ListValue JSON parse | 660.73 | — | — | 10398.00 (15.74x) | 4499.87 (6.81x) |
| ListValue Escape JSON parse | 718.60 | — | — | 10549.30 (14.68x) | 4766.29 (6.63x) |
| ListValue Surrogate JSON parse | 426.55 | — | — | 3807.16 (8.93x) | 1237.90 (2.90x) |
| EmptyListValue JSON stringify | 53.58 | — | — | 689.98 (12.88x) | 236.68 (4.42x) |
| EmptyListValue JSON parse | 157.42 | — | — | 2708.05 (17.20x) | 400.71 (2.55x) |
| DoubleValue JSON stringify | 123.12 | — | — | 857.49 (6.96x) | 181.88 (1.48x) |
| DoubleValue JSON parse | 144.54 | — | — | 1383.80 (9.57x) | 505.27 (3.50x) |
| DoubleValue String JSON parse | 141.64 | — | — | 1297.53 (9.16x) | 342.23 (2.42x) |
| DoubleValue Exponent JSON parse | 116.68 | — | — | 1560.80 (13.38x) | 289.94 (2.48x) |
| NegativeDoubleValue JSON stringify | 71.76 | — | — | 984.00 (13.71x) | 304.83 (4.25x) |
| NegativeDoubleValue JSON parse | 141.39 | — | — | 1405.05 (9.94x) | 300.46 (2.13x) |
| ZeroDoubleValue JSON stringify | 69.93 | — | — | 913.15 (13.06x) | 270.42 (3.87x) |
| ZeroDoubleValue JSON parse | 120.56 | — | — | 1258.35 (10.44x) | 244.33 (2.03x) |
| DoubleValue NaN JSON stringify | 65.04 | — | — | 735.80 (11.31x) | 125.94 (1.94x) |
| DoubleValue NaN JSON parse | 127.89 | — | — | 1225.26 (9.58x) | 331.52 (2.59x) |
| DoubleValue Infinity JSON stringify | 69.29 | — | — | 750.82 (10.84x) | 116.49 (1.68x) |
| DoubleValue Infinity JSON parse | 109.36 | — | — | 1164.15 (10.65x) | 402.44 (3.68x) |
| DoubleValue NegativeInfinity JSON stringify | 64.74 | — | — | 649.73 (10.04x) | 130.30 (2.01x) |
| DoubleValue NegativeInfinity JSON parse | 135.44 | — | — | 1273.63 (9.40x) | 341.05 (2.52x) |
| FloatValue JSON stringify | 127.22 | — | — | 809.64 (6.36x) | 194.48 (1.53x) |
| FloatValue JSON parse | 136.25 | — | — | 1387.17 (10.18x) | 266.54 (1.96x) |
| FloatValue String JSON parse | 109.61 | — | — | 1217.88 (11.11x) | 373.87 (3.41x) |
| FloatValue Exponent JSON parse | 113.21 | — | — | 1494.46 (13.20x) | 260.44 (2.30x) |
| NegativeFloatValue JSON stringify | 72.14 | — | — | 811.87 (11.25x) | 185.01 (2.56x) |
| NegativeFloatValue JSON parse | 111.95 | — | — | 1477.01 (13.19x) | 274.47 (2.45x) |
| ZeroFloatValue JSON stringify | 47.46 | — | — | 758.69 (15.99x) | 143.34 (3.02x) |
| ZeroFloatValue JSON parse | 108.26 | — | — | 1294.79 (11.96x) | 342.70 (3.17x) |
| FloatValue NaN JSON stringify | 46.46 | — | — | 649.16 (13.97x) | 124.57 (2.68x) |
| FloatValue NaN JSON parse | 104.38 | — | — | 1214.74 (11.64x) | 249.19 (2.39x) |
| FloatValue Infinity JSON stringify | 47.96 | — | — | 651.72 (13.59x) | 134.29 (2.80x) |
| FloatValue Infinity JSON parse | 106.07 | — | — | 1236.72 (11.66x) | 247.78 (2.34x) |
| FloatValue NegativeInfinity JSON stringify | 48.16 | — | — | 688.00 (14.29x) | 123.97 (2.57x) |
| FloatValue NegativeInfinity JSON parse | 107.23 | — | — | 1271.47 (11.86x) | 408.34 (3.81x) |
| Int64Value JSON stringify | 50.42 | — | — | 683.09 (13.55x) | 264.75 (5.25x) |
| Int64Value JSON parse | 126.62 | — | — | 1388.20 (10.96x) | 545.78 (4.31x) |
| Int64Value Number JSON parse | 127.34 | — | — | 1530.63 (12.02x) | 410.91 (3.23x) |
| Int64Value Exponent JSON parse | 117.37 | — | — | 1399.11 (11.92x) | 338.97 (2.89x) |
| ZeroInt64Value JSON stringify | 41.57 | — | — | 613.01 (14.75x) | 297.51 (7.16x) |
| ZeroInt64Value JSON parse | 108.12 | — | — | 1183.38 (10.95x) | 323.88 (3.00x) |
| NegativeInt64Value JSON stringify | 48.81 | — | — | 679.21 (13.92x) | 254.63 (5.22x) |
| NegativeInt64Value JSON parse | 128.03 | — | — | 1594.74 (12.46x) | 461.19 (3.60x) |
| MinInt64Value JSON stringify | 50.26 | — | — | 741.64 (14.76x) | 384.79 (7.66x) |
| MinInt64Value JSON parse | 141.48 | — | — | 1388.34 (9.81x) | 540.78 (3.82x) |
| MaxInt64Value JSON stringify | 49.84 | — | — | 674.44 (13.53x) | 266.26 (5.34x) |
| MaxInt64Value JSON parse | 135.78 | — | — | 1460.80 (10.76x) | 513.80 (3.78x) |
| UInt64Value JSON stringify | 50.51 | — | — | 673.94 (13.34x) | 264.28 (5.23x) |
| UInt64Value JSON parse | 126.41 | — | — | 1357.59 (10.74x) | 531.38 (4.20x) |
| UInt64Value Number JSON parse | 128.82 | — | — | 1560.80 (12.12x) | 354.98 (2.76x) |
| UInt64Value Exponent JSON parse | 117.78 | — | — | 1337.23 (11.35x) | 500.57 (4.25x) |
| ZeroUInt64Value JSON stringify | 41.91 | — | — | 611.08 (14.58x) | 197.45 (4.71x) |
| ZeroUInt64Value JSON parse | 106.45 | — | — | 1156.48 (10.86x) | 365.93 (3.44x) |
| MaxUInt64Value JSON stringify | 50.01 | — | — | 672.93 (13.46x) | 351.32 (7.02x) |
| MaxUInt64Value JSON parse | 140.86 | — | — | 1452.47 (10.31x) | 482.72 (3.43x) |
| Int32Value JSON stringify | 63.99 | — | — | 645.06 (10.08x) | 227.30 (3.55x) |
| Int32Value JSON parse | 163.59 | — | — | 1366.85 (8.36x) | 358.20 (2.19x) |
| Int32Value String JSON parse | 167.50 | — | — | 1211.64 (7.23x) | 466.06 (2.78x) |
| Int32Value Exponent JSON parse | 173.34 | — | — | 1573.36 (9.08x) | 560.82 (3.24x) |
| ZeroInt32Value JSON stringify | 63.01 | — | — | 627.49 (9.96x) | 140.10 (2.22x) |
| ZeroInt32Value JSON parse | 153.23 | — | — | 1351.06 (8.82x) | 248.03 (1.62x) |
| NegativeInt32Value JSON stringify | 63.78 | — | — | 653.08 (10.24x) | 244.07 (3.83x) |
| NegativeInt32Value JSON parse | 161.76 | — | — | 1468.80 (9.08x) | 450.52 (2.79x) |
| MinInt32Value JSON stringify | 65.00 | — | — | 651.66 (10.03x) | 144.78 (2.23x) |
| MinInt32Value JSON parse | 181.21 | — | — | 1320.97 (7.29x) | 333.37 (1.84x) |
| MaxInt32Value JSON stringify | 65.02 | — | — | 670.79 (10.32x) | 259.43 (3.99x) |
| MaxInt32Value JSON parse | 184.29 | — | — | 1316.55 (7.14x) | 347.24 (1.88x) |
| UInt32Value JSON stringify | 63.89 | — | — | 678.42 (10.62x) | 134.81 (2.11x) |
| UInt32Value JSON parse | 159.49 | — | — | 1387.33 (8.70x) | 394.40 (2.47x) |
| UInt32Value String JSON parse | 142.58 | — | — | 1133.32 (7.95x) | 489.98 (3.44x) |
| UInt32Value Exponent JSON parse | 171.50 | — | — | 1623.40 (9.47x) | 349.76 (2.04x) |
| ZeroUInt32Value JSON stringify | 62.47 | — | — | 607.79 (9.73x) | 268.37 (4.30x) |
| ZeroUInt32Value JSON parse | 143.29 | — | — | 1213.42 (8.47x) | 253.66 (1.77x) |
| MaxUInt32Value JSON stringify | 61.86 | — | — | 630.44 (10.19x) | 133.31 (2.16x) |
| MaxUInt32Value JSON parse | 155.10 | — | — | 1393.84 (8.99x) | 335.71 (2.16x) |
| BoolValue JSON stringify | 57.47 | — | — | 615.61 (10.71x) | 124.15 (2.16x) |
| BoolValue JSON parse | 71.68 | — | — | 1070.63 (14.94x) | 211.85 (2.96x) |
| FalseBoolValue JSON stringify | 57.83 | — | — | 601.61 (10.40x) | 149.97 (2.59x) |
| FalseBoolValue JSON parse | 72.90 | — | — | 1113.34 (15.27x) | 185.71 (2.55x) |
| StringValue JSON stringify | 74.55 | — | — | 660.42 (8.86x) | 304.16 (4.08x) |
| StringValue JSON parse | 121.61 | — | — | 1221.67 (10.05x) | 313.26 (2.58x) |
| StringValue Escape JSON parse | 130.90 | — | — | 1339.11 (10.23x) | 350.91 (2.68x) |
| StringValue Surrogate JSON parse | 133.17 | — | — | 1309.89 (9.84x) | 407.39 (3.06x) |
| EmptyStringValue JSON stringify | 49.26 | — | — | 630.08 (12.79x) | 259.12 (5.26x) |
| EmptyStringValue JSON parse | 67.03 | — | — | 1274.07 (19.01x) | 276.13 (4.12x) |
| BytesValue JSON stringify | 49.81 | — | — | 682.04 (13.69x) | 282.01 (5.66x) |
| BytesValue JSON parse | 127.85 | — | — | 1305.09 (10.21x) | 370.19 (2.90x) |
| BytesValue URL JSON parse | 142.07 | — | — | 1200.68 (8.45x) | 379.31 (2.67x) |
| BytesValue StandardBase64 JSON parse | 127.00 | — | — | 1360.33 (10.71x) | 291.50 (2.30x) |
| BytesValue Unpadded JSON parse | 126.71 | — | — | 1266.05 (9.99x) | 292.17 (2.31x) |
| EmptyBytesValue JSON stringify | 41.47 | — | — | 653.72 (15.76x) | 244.38 (5.89x) |
| EmptyBytesValue JSON parse | 68.38 | — | — | 1257.81 (18.39x) | 433.17 (6.33x) |
| TextFormat format | 178.30 | — | — | 2921.48 (16.39x) | 2726.99 (15.29x) |
| TextFormat parse | 697.79 | — | — | 6028.64 (8.64x) | 8012.82 (11.48x) |
| packed fixed32 encode | 2.74 | 562.25 (205.20x) | 544.45 (198.70x) | 43.70 (15.95x) | 413.12 (150.77x) |
| packed fixed32 decode | 8.84 | 1109.38 (125.50x) | 2336.23 (264.28x) | 66.99 (7.58x) | 2602.49 (294.40x) |
| packed fixed64 encode | 2.01 | 586.93 (292.00x) | 565.16 (281.17x) | 79.51 (39.56x) | 402.74 (200.37x) |
| packed fixed64 decode | 4.53 | 1210.78 (267.28x) | 8591.47 (1896.57x) | 79.64 (17.58x) | 3429.26 (757.01x) |
| packed sfixed32 encode | 2.88 | 626.55 (217.55x) | 539.41 (187.30x) | 43.83 (15.22x) | 410.30 (142.47x) |
| packed sfixed32 decode | 8.81 | 1303.88 (148.00x) | 2272.12 (257.90x) | 66.17 (7.51x) | 2023.78 (229.71x) |
| packed sfixed64 encode | 2.69 | 587.17 (218.28x) | 562.50 (209.11x) | 81.29 (30.22x) | 768.31 (285.62x) |
| packed sfixed64 decode | 8.36 | 1347.19 (161.15x) | 8499.17 (1016.65x) | 79.52 (9.51x) | 3241.82 (387.78x) |
| packed float encode | 2.02 | 812.56 (402.26x) | 541.95 (268.29x) | 43.15 (21.36x) | 387.17 (191.67x) |
| packed float decode | 4.53 | 1149.04 (253.65x) | 2421.48 (534.54x) | 68.19 (15.05x) | 2234.66 (493.30x) |
| packed double encode | 2.70 | 832.50 (308.33x) | 579.22 (214.53x) | 72.25 (26.76x) | 586.13 (217.09x) |
| packed double decode | 8.75 | 1101.41 (125.88x) | 2391.95 (273.37x) | 79.46 (9.08x) | 3347.76 (382.60x) |
| packed uint64 encode | 1303.49 | 5421.06 (4.16x) | 4957.42 (3.80x) | 2574.89 (1.98x) | 4684.96 (3.59x) |
| packed uint64 decode | 1782.77 | 3500.94 (1.96x) | 9820.43 (5.51x) | 3402.62 (1.91x) | 9260.82 (5.19x) |
| packed uint32 encode | 1045.75 | 4274.43 (4.09x) | 3905.13 (3.73x) | 2167.18 (2.07x) | 3885.63 (3.72x) |
| packed uint32 decode | 1327.44 | 3013.57 (2.27x) | 3740.34 (2.82x) | 2502.12 (1.88x) | 6849.91 (5.16x) |
| packed int64 encode | 1413.74 | 12674.92 (8.97x) | 7201.67 (5.09x) | 3778.01 (2.67x) | 5257.41 (3.72x) |
| packed int64 decode | 2738.38 | 4219.77 (1.54x) | 11509.98 (4.20x) | 5702.52 (2.08x) | 11384.88 (4.16x) |
| packed sint32 encode | 778.55 | 3758.82 (4.83x) | 3252.62 (4.18x) | 2020.13 (2.59x) | 4406.60 (5.66x) |
| packed sint32 decode | 958.38 | 3021.91 (3.15x) | 3766.62 (3.93x) | 1285.40 (1.34x) | 4242.26 (4.43x) |
| packed sint64 encode | 1426.75 | 5943.19 (4.17x) | 5365.61 (3.76x) | 3085.79 (2.16x) | 5325.11 (3.73x) |
| packed sint64 decode | 2037.13 | 3896.71 (1.91x) | 10660.74 (5.23x) | 3590.72 (1.76x) | 9052.56 (4.44x) |
| packed bool encode | 2.01 | 1563.08 (777.65x) | 544.67 (270.98x) | 23.58 (11.73x) | 3023.80 (1504.38x) |
| packed bool decode | 313.83 | 1922.62 (6.13x) | 2982.72 (9.50x) | 989.05 (3.15x) | 2342.93 (7.47x) |
| packed enum encode | 273.39 | 3151.99 (11.53x) | 2017.64 (7.38x) | 1090.67 (3.99x) | 3205.74 (11.73x) |
| packed enum decode | 156.72 | 1899.26 (12.12x) | 3195.16 (20.39x) | 705.34 (4.50x) | 2740.75 (17.49x) |
| large map encode | 3889.28 | 18562.23 (4.77x) | 10077.54 (2.59x) | 24455.80 (6.29x) | 229596.72 (59.03x) |
| shuffled large map deterministic binary encode | 36024.93 | — | — | 104662.00 (2.91x) | 440227.45 (12.22x) |
| large map decode | 28107.68 | 143483.14 (5.10x) | 106179.02 (3.78x) | 104714.00 (3.73x) | 341848.42 (12.16x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON (including generated `map<string, int32>` surrogate-pair key parse, null-field parse, ignore-unknown parse, enum-name parse, always-print default-value stringify, proto-name stringify, proto-name parse, open-enum numeric parse, and integer numeric-exponent parse), Any/WKT JSON (including embedded zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound `Duration`, non-empty/escaped-input parse/number-exponent parse/surrogate-pair value parse/surrogate-pair key parse and empty `Struct`, object/escaped-object parse/object-number-exponent/object-surrogate-pair value parse/object-surrogate-pair key parse/list/escaped-list/surrogate-list/string-scalar/escaped-string-scalar/surrogate-string-scalar/number-exponent/negative-number `Value` (including default-like scalar and empty object/list kinds),
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
