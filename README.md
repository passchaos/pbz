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

Latest accepted comparison (`/tmp/pbz-compare-int-exponent-json-final.log`,
summarized in `/tmp/pbz-summary-int-exponent-json-final.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 21.55 | 127.76 (5.93x) | 50.67 (2.35x) | 96.27 (4.47x) | 907.38 (42.11x) |
| binary decode | 122.89 | 323.93 (2.64x) | 226.32 (1.84x) | 210.67 (1.71x) | 930.89 (7.57x) |
| unknown fields count by number | 3.61 | — | — | 280.85 (77.80x) | — |
| deterministic binary encode | 44.99 | — | — | 124.18 (2.76x) | 1153.35 (25.64x) |
| scalarmix encode | 17.09 | 127.58 (7.47x) | 51.74 (3.03x) | 54.02 (3.16x) | 211.32 (12.37x) |
| scalarmix decode | 51.60 | 136.74 (2.65x) | 176.69 (3.42x) | 107.66 (2.09x) | 326.60 (6.33x) |
| textbytes encode | 9.53 | 88.68 (9.31x) | 44.30 (4.65x) | 148.03 (15.53x) | 172.79 (18.13x) |
| textbytes decode | 46.71 | 530.24 (11.35x) | 239.73 (5.13x) | 237.83 (5.09x) | 862.66 (18.47x) |
| largebytes encode | 27.26 | 4360.42 (159.96x) | 3242.43 (118.94x) | 2760.89 (101.28x) | 2760.48 (101.26x) |
| largebytes decode | 138.02 | 9654.93 (69.95x) | 5370.02 (38.91x) | 2776.58 (20.12x) | 33732.16 (244.40x) |
| presencemix encode | 26.90 | 72.97 (2.71x) | 42.44 (1.58x) | 54.55 (2.03x) | 227.55 (8.46x) |
| presencemix decode | 76.39 | 188.13 (2.46x) | 159.53 (2.09x) | 191.39 (2.51x) | 578.67 (7.58x) |
| complex encode | 57.26 | 179.72 (3.14x) | 134.98 (2.36x) | 167.82 (2.93x) | 1001.68 (17.49x) |
| complex decode | 175.91 | 516.55 (2.94x) | 486.21 (2.76x) | 394.42 (2.24x) | 1751.81 (9.96x) |
| complex deterministic binary encode | 95.84 | — | — | 173.33 (1.81x) | 1288.79 (13.45x) |
| complex JSON stringify | 288.90 | — | — | 6489.01 (22.46x) | 7987.68 (27.65x) |
| complex JSON parse | 2418.20 | — | — | 14763.30 (6.11x) | 9522.41 (3.94x) |
| complex TextFormat format | 423.24 | — | — | 4522.33 (10.69x) | 6849.76 (16.18x) |
| complex TextFormat parse | 2636.48 | — | — | 8213.11 (3.12x) | 10878.74 (4.13x) |
| packed int32 encode | 1000.12 | 5844.51 (5.84x) | 3360.10 (3.36x) | 1421.96 (1.42x) | 3281.57 (3.28x) |
| packed int32 decode | 698.45 | 3403.99 (4.87x) | 4669.39 (6.69x) | 1072.56 (1.54x) | 4657.04 (6.67x) |
| JSON stringify | 226.80 | — | — | 3749.95 (16.53x) | 2627.22 (11.58x) |
| JSON parse | 1861.09 | — | — | 9006.90 (4.84x) | 5408.48 (2.91x) |
| MapKeySurrogate JSON parse | 480.01 | — | — | 4239.70 (8.83x) | 1480.71 (3.08x) |
| IntExponent JSON parse | 1902.39 | — | — | 8806.10 (4.63x) | 5004.32 (2.63x) |
| Any WKT JSON stringify | 198.96 | — | — | 2254.36 (11.33x) | 1035.53 (5.20x) |
| Any WKT JSON parse | 643.72 | — | — | 3558.46 (5.53x) | 2119.25 (3.29x) |
| Any Duration Escape WKT JSON parse | 657.66 | — | — | 3716.87 (5.65x) | 1903.69 (2.89x) |
| Any PlusDuration WKT JSON parse | 614.09 | — | — | 3536.75 (5.76x) | 1939.18 (3.16x) |
| Any ShortFractionDuration WKT JSON parse | 606.95 | — | — | 3532.89 (5.82x) | 1941.64 (3.20x) |
| Any MicroDuration WKT JSON stringify | 186.21 | — | — | 2335.84 (12.54x) | 1155.07 (6.20x) |
| Any MicroDuration WKT JSON parse | 614.15 | — | — | 3798.37 (6.18x) | 1716.65 (2.80x) |
| Any NanoDuration WKT JSON stringify | 183.42 | — | — | 2606.46 (14.21x) | 1115.41 (6.08x) |
| Any NanoDuration WKT JSON parse | 642.26 | — | — | 3519.30 (5.48x) | 1982.07 (3.09x) |
| Any NegativeDuration WKT JSON stringify | 204.56 | — | — | 2342.67 (11.45x) | 1152.93 (5.64x) |
| Any NegativeDuration WKT JSON parse | 660.01 | — | — | 3845.80 (5.83x) | 2035.34 (3.08x) |
| Any FractionalNegativeDuration WKT JSON stringify | 192.37 | — | — | 2572.31 (13.37x) | 1492.43 (7.76x) |
| Any FractionalNegativeDuration WKT JSON parse | 659.72 | — | — | 3832.76 (5.81x) | 2045.00 (3.10x) |
| Any MaxDuration WKT JSON stringify | 180.18 | — | — | 2867.57 (15.92x) | 1277.71 (7.09x) |
| Any MaxDuration WKT JSON parse | 685.34 | — | — | 4700.21 (6.86x) | 1819.14 (2.65x) |
| Any MinDuration WKT JSON stringify | 181.38 | — | — | 2153.84 (11.87x) | 1172.69 (6.47x) |
| Any MinDuration WKT JSON parse | 655.60 | — | — | 4339.39 (6.62x) | 1861.43 (2.84x) |
| Any ZeroDuration WKT JSON stringify | 156.09 | — | — | 1025.79 (6.57x) | 1231.32 (7.89x) |
| Any ZeroDuration WKT JSON parse | 560.76 | — | — | 3054.28 (5.45x) | 1825.67 (3.26x) |
| Any FieldMask WKT JSON stringify | 283.14 | — | — | 2212.43 (7.81x) | 1804.04 (6.37x) |
| Any FieldMask WKT JSON parse | 806.62 | — | — | 3898.84 (4.83x) | 2412.49 (2.99x) |
| Any FieldMask Escape WKT JSON parse | 820.81 | — | — | 3908.05 (4.76x) | 2912.77 (3.55x) |
| Any EmptyFieldMask WKT JSON stringify | 153.97 | — | — | 1009.27 (6.55x) | 883.61 (5.74x) |
| Any EmptyFieldMask WKT JSON parse | 514.14 | — | — | 2673.61 (5.20x) | 1553.68 (3.02x) |
| Any Timestamp WKT JSON stringify | 259.98 | — | — | 2647.75 (10.18x) | 1372.57 (5.28x) |
| Any Timestamp WKT JSON parse | 709.97 | — | — | 4749.35 (6.69x) | 2239.49 (3.15x) |
| Any Timestamp Escape WKT JSON parse | 746.71 | — | — | 4078.57 (5.46x) | 1652.22 (2.21x) |
| Any ShortFraction Timestamp WKT JSON parse | 715.75 | — | — | 3760.97 (5.25x) | 2026.40 (2.83x) |
| Any Micro Timestamp WKT JSON stringify | 271.74 | — | — | 2298.86 (8.46x) | 1214.55 (4.47x) |
| Any Micro Timestamp WKT JSON parse | 710.74 | — | — | 3764.75 (5.30x) | 1974.91 (2.78x) |
| Any Nano Timestamp WKT JSON stringify | 261.89 | — | — | 2439.43 (9.31x) | 1377.56 (5.26x) |
| Any Nano Timestamp WKT JSON parse | 702.97 | — | — | 3759.95 (5.35x) | 1860.31 (2.65x) |
| Any Offset Timestamp WKT JSON parse | 694.07 | — | — | 3880.47 (5.59x) | 2044.73 (2.95x) |
| Any PreEpoch Timestamp WKT JSON stringify | 205.35 | — | — | 2557.76 (12.46x) | 1198.49 (5.84x) |
| Any PreEpoch Timestamp WKT JSON parse | 655.21 | — | — | 3656.17 (5.58x) | 1927.53 (2.94x) |
| Any Max Timestamp WKT JSON stringify | 236.69 | — | — | 2438.42 (10.30x) | 1097.41 (4.64x) |
| Any Max Timestamp WKT JSON parse | 733.92 | — | — | 3824.70 (5.21x) | 1781.63 (2.43x) |
| Any Min Timestamp WKT JSON stringify | 254.27 | — | — | 2307.35 (9.07x) | 1151.18 (4.53x) |
| Any Min Timestamp WKT JSON parse | 709.97 | — | — | 3644.43 (5.13x) | 2099.70 (2.96x) |
| Any Empty WKT JSON stringify | 135.60 | — | — | 908.71 (6.70x) | 749.24 (5.53x) |
| Any Empty WKT JSON parse | 436.04 | — | — | 2544.28 (5.83x) | 1549.67 (3.55x) |
| Any Struct WKT JSON stringify | 877.43 | — | — | 7123.49 (8.12x) | 7696.73 (8.77x) |
| Any Struct WKT JSON parse | 2032.30 | — | — | 14252.90 (7.01x) | 11531.20 (5.67x) |
| Any Struct Escape WKT JSON parse | 2040.77 | — | — | 13735.50 (6.73x) | 11653.90 (5.71x) |
| Any Struct NumberExponent WKT JSON parse | 2182.35 | — | — | 13601.90 (6.23x) | 12126.79 (5.56x) |
| Any Struct Surrogate WKT JSON parse | 935.13 | — | — | 7692.26 (8.23x) | 4538.87 (4.85x) |
| Any Struct KeySurrogate WKT JSON parse | 886.97 | — | — | 7490.42 (8.44x) | 3973.36 (4.48x) |
| Any EmptyStruct WKT JSON stringify | 155.59 | — | — | 1007.30 (6.47x) | 1178.54 (7.57x) |
| Any EmptyStruct WKT JSON parse | 524.54 | — | — | 2582.93 (4.92x) | 1952.98 (3.72x) |
| Any Value WKT JSON stringify | 805.07 | — | — | 7087.65 (8.80x) | 8747.81 (10.87x) |
| Any Value WKT JSON parse | 2129.19 | — | — | 14765.50 (6.93x) | 12602.54 (5.92x) |
| Any Value Escape WKT JSON parse | 2256.17 | — | — | 14143.90 (6.27x) | 11869.79 (5.26x) |
| Any Value NumberExponent WKT JSON parse | 2079.86 | — | — | 13941.90 (6.70x) | 11785.58 (5.67x) |
| Any Value Surrogate WKT JSON parse | 923.27 | — | — | 7822.95 (8.47x) | 4768.32 (5.16x) |
| Any Value KeySurrogate WKT JSON parse | 970.72 | — | — | 7867.07 (8.10x) | 4980.70 (5.13x) |
| Any NullValue WKT JSON stringify | 179.76 | — | — | 2618.92 (14.57x) | 1073.32 (5.97x) |
| Any NullValue WKT JSON parse | 592.14 | — | — | 4801.55 (8.11x) | 1999.70 (3.38x) |
| Any StringScalarValue WKT JSON stringify | 216.05 | — | — | 2644.16 (12.24x) | 1441.93 (6.67x) |
| Any StringScalarValue WKT JSON parse | 656.00 | — | — | 4467.24 (6.81x) | 2181.62 (3.33x) |
| Any StringScalarValue Escape WKT JSON parse | 643.98 | — | — | 4482.54 (6.96x) | 2216.55 (3.44x) |
| Any StringScalarValue Surrogate WKT JSON parse | 632.93 | — | — | 4775.63 (7.55x) | 2433.77 (3.85x) |
| Any EmptyStringScalarValue WKT JSON stringify | 182.25 | — | — | 6896.60 (37.84x) | 1351.84 (7.42x) |
| Any EmptyStringScalarValue WKT JSON parse | 582.03 | — | — | 5641.31 (9.69x) | 1802.82 (3.10x) |
| Any NumberValue WKT JSON stringify | 246.46 | — | — | 5675.41 (23.03x) | 1269.78 (5.15x) |
| Any NumberValue WKT JSON parse | 573.43 | — | — | 7029.46 (12.26x) | 2191.92 (3.82x) |
| Any NumberValue Exponent WKT JSON parse | 574.76 | — | — | 7477.08 (13.01x) | 2217.43 (3.86x) |
| Any NegativeNumberValue WKT JSON stringify | 239.16 | — | — | 4888.31 (20.44x) | 1401.27 (5.86x) |
| Any NegativeNumberValue WKT JSON parse | 585.02 | — | — | 6713.80 (11.48x) | 2213.31 (3.78x) |
| Any ZeroNumberValue WKT JSON stringify | 193.25 | — | — | 4611.83 (23.86x) | 992.42 (5.14x) |
| Any ZeroNumberValue WKT JSON parse | 636.86 | — | — | 6356.34 (9.98x) | 1873.91 (2.94x) |
| Any BoolScalarValue WKT JSON stringify | 179.69 | — | — | 3836.64 (21.35x) | 1320.99 (7.35x) |
| Any BoolScalarValue WKT JSON parse | 590.05 | — | — | 6330.40 (10.73x) | 1938.74 (3.29x) |
| Any FalseBoolScalarValue WKT JSON stringify | 180.28 | — | — | 3807.50 (21.12x) | 928.35 (5.15x) |
| Any FalseBoolScalarValue WKT JSON parse | 593.48 | — | — | 6048.84 (10.19x) | 1856.16 (3.13x) |
| Any ListKindValue WKT JSON stringify | 670.42 | — | — | 10007.80 (14.93x) | 6587.79 (9.83x) |
| Any ListKindValue WKT JSON parse | 1589.17 | — | — | 17234.70 (10.85x) | 10128.35 (6.37x) |
| Any ListKindValue Escape WKT JSON parse | 1602.85 | — | — | 18924.90 (11.81x) | 9417.66 (5.88x) |
| Any ListKindValue Surrogate WKT JSON parse | 824.59 | — | — | 13155.50 (15.95x) | 3923.65 (4.76x) |
| Any EmptyStructKindValue WKT JSON stringify | 190.52 | — | — | 5175.22 (27.16x) | 1979.66 (10.39x) |
| Any EmptyStructKindValue WKT JSON parse | 620.22 | — | — | 8714.48 (14.05x) | 2418.22 (3.90x) |
| Any EmptyListKindValue WKT JSON stringify | 197.48 | — | — | 4614.94 (23.37x) | 1440.78 (7.30x) |
| Any EmptyListKindValue WKT JSON parse | 630.45 | — | — | 7665.86 (12.16x) | 2355.38 (3.74x) |
| Any DoubleValue WKT JSON stringify | 274.54 | — | — | 2200.10 (8.01x) | 903.11 (3.29x) |
| Any DoubleValue WKT JSON parse | 651.68 | — | — | 3225.99 (4.95x) | 1881.96 (2.89x) |
| Any DoubleValue String WKT JSON parse | 651.61 | — | — | 3273.27 (5.02x) | 1932.37 (2.97x) |
| Any DoubleValue Exponent WKT JSON parse | 622.89 | — | — | 3301.67 (5.30x) | 1952.75 (3.13x) |
| Any NegativeDoubleValue WKT JSON stringify | 257.59 | — | — | 2254.84 (8.75x) | 893.24 (3.47x) |
| Any NegativeDoubleValue WKT JSON parse | 593.44 | — | — | 4755.82 (8.01x) | 2011.86 (3.39x) |
| Any ZeroDoubleValue WKT JSON stringify | 200.98 | — | — | 1474.74 (7.34x) | 757.24 (3.77x) |
| Any ZeroDoubleValue WKT JSON parse | 594.70 | — | — | 3417.10 (5.75x) | 1958.81 (3.29x) |
| Any DoubleValue NaN WKT JSON stringify | 195.98 | — | — | 2539.97 (12.96x) | 803.63 (4.10x) |
| Any DoubleValue NaN WKT JSON parse | 600.74 | — | — | 4363.32 (7.26x) | 1587.69 (2.64x) |
| Any DoubleValue Infinity WKT JSON stringify | 210.94 | — | — | 1939.41 (9.19x) | 783.89 (3.72x) |
| Any DoubleValue Infinity WKT JSON parse | 649.77 | — | — | 3466.23 (5.33x) | 1999.25 (3.08x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 224.70 | — | — | 1899.95 (8.46x) | 791.43 (3.52x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 653.15 | — | — | 3369.87 (5.16x) | 1962.48 (3.00x) |
| Any FloatValue WKT JSON stringify | 285.82 | — | — | 2190.16 (7.66x) | 944.53 (3.30x) |
| Any FloatValue WKT JSON parse | 663.32 | — | — | 3282.25 (4.95x) | 1801.41 (2.72x) |
| Any FloatValue String WKT JSON parse | 662.33 | — | — | 3223.04 (4.87x) | 1711.78 (2.58x) |
| Any FloatValue Exponent WKT JSON parse | 653.96 | — | — | 3155.64 (4.83x) | 1772.30 (2.71x) |
| Any NegativeFloatValue WKT JSON stringify | 269.71 | — | — | 2282.47 (8.46x) | 852.51 (3.16x) |
| Any NegativeFloatValue WKT JSON parse | 611.38 | — | — | 3190.13 (5.22x) | 1555.44 (2.54x) |
| Any ZeroFloatValue WKT JSON stringify | 210.18 | — | — | 968.89 (4.61x) | 971.56 (4.62x) |
| Any ZeroFloatValue WKT JSON parse | 598.42 | — | — | 3432.74 (5.74x) | 1820.81 (3.04x) |
| Any FloatValue NaN WKT JSON stringify | 200.13 | — | — | 1931.82 (9.65x) | 786.45 (3.93x) |
| Any FloatValue NaN WKT JSON parse | 596.99 | — | — | 3157.50 (5.29x) | 1628.84 (2.73x) |
| Any FloatValue Infinity WKT JSON stringify | 206.33 | — | — | 2002.79 (9.71x) | 771.43 (3.74x) |
| Any FloatValue Infinity WKT JSON parse | 616.13 | — | — | 3677.99 (5.97x) | 1741.33 (2.83x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 222.27 | — | — | 1959.88 (8.82x) | 697.93 (3.14x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 653.96 | — | — | 3100.93 (4.74x) | 1640.79 (2.51x) |
| Any Int64Value WKT JSON stringify | 228.38 | — | — | 1899.76 (8.32x) | 1066.34 (4.67x) |
| Any Int64Value WKT JSON parse | 707.42 | — | — | 3201.22 (4.53x) | 2149.85 (3.04x) |
| Any Int64Value Number WKT JSON parse | 722.82 | — | — | 3212.56 (4.44x) | 1582.54 (2.19x) |
| Any Int64Value Exponent WKT JSON parse | 666.35 | — | — | 3269.19 (4.91x) | 1710.60 (2.57x) |
| Any ZeroInt64Value WKT JSON stringify | 215.40 | — | — | 1458.46 (6.77x) | 855.23 (3.97x) |
| Any ZeroInt64Value WKT JSON parse | 639.76 | — | — | 2745.00 (4.29x) | 1795.02 (2.81x) |
| Any NegativeInt64Value WKT JSON stringify | 224.05 | — | — | 1906.29 (8.51x) | 838.46 (3.74x) |
| Any NegativeInt64Value WKT JSON parse | 684.75 | — | — | 3543.01 (5.17x) | 2143.73 (3.13x) |
| Any MinInt64Value WKT JSON stringify | 231.84 | — | — | 2001.48 (8.63x) | 1149.38 (4.96x) |
| Any MinInt64Value WKT JSON parse | 690.02 | — | — | 3318.17 (4.81x) | 2245.27 (3.25x) |
| Any MaxInt64Value WKT JSON stringify | 228.53 | — | — | 1747.28 (7.65x) | 993.49 (4.35x) |
| Any MaxInt64Value WKT JSON parse | 711.81 | — | — | 3407.75 (4.79x) | 2053.18 (2.88x) |
| Any UInt64Value WKT JSON stringify | 235.54 | — | — | 1893.18 (8.04x) | 1176.11 (4.99x) |
| Any UInt64Value WKT JSON parse | 724.03 | — | — | 3285.21 (4.54x) | 2111.39 (2.92x) |
| Any UInt64Value Number WKT JSON parse | 727.82 | — | — | 3264.34 (4.49x) | 2008.52 (2.76x) |
| Any UInt64Value Exponent WKT JSON parse | 699.03 | — | — | 3345.29 (4.79x) | 1827.39 (2.61x) |
| Any ZeroUInt64Value WKT JSON stringify | 228.39 | — | — | 996.11 (4.36x) | 755.19 (3.31x) |
| Any ZeroUInt64Value WKT JSON parse | 663.01 | — | — | 2596.42 (3.92x) | 1796.61 (2.71x) |
| Any MaxUInt64Value WKT JSON stringify | 238.21 | — | — | 1961.56 (8.23x) | 1059.94 (4.45x) |
| Any MaxUInt64Value WKT JSON parse | 712.56 | — | — | 3607.41 (5.06x) | 2023.23 (2.84x) |
| Any Int32Value WKT JSON stringify | 218.76 | — | — | 1983.01 (9.06x) | 835.48 (3.82x) |
| Any Int32Value WKT JSON parse | 639.58 | — | — | 3075.86 (4.81x) | 1843.61 (2.88x) |
| Any Int32Value String WKT JSON parse | 640.59 | — | — | 3075.50 (4.80x) | 2164.20 (3.38x) |
| Any Int32Value Exponent WKT JSON parse | 643.89 | — | — | 3449.60 (5.36x) | 1801.48 (2.80x) |
| Any ZeroInt32Value WKT JSON stringify | 224.35 | — | — | 1018.41 (4.54x) | 753.79 (3.36x) |
| Any ZeroInt32Value WKT JSON parse | 664.40 | — | — | 2634.47 (3.97x) | 1802.02 (2.71x) |
| Any NegativeInt32Value WKT JSON stringify | 233.73 | — | — | 1947.81 (8.33x) | 781.57 (3.34x) |
| Any NegativeInt32Value WKT JSON parse | 686.51 | — | — | 3376.12 (4.92x) | 1786.90 (2.60x) |
| Any MinInt32Value WKT JSON stringify | 242.10 | — | — | 2425.90 (10.02x) | 821.86 (3.39x) |
| Any MinInt32Value WKT JSON parse | 698.10 | — | — | 4493.27 (6.44x) | 1788.39 (2.56x) |
| Any MaxInt32Value WKT JSON stringify | 237.15 | — | — | 1937.82 (8.17x) | 837.56 (3.53x) |
| Any MaxInt32Value WKT JSON parse | 680.30 | — | — | 3242.24 (4.77x) | 1873.67 (2.75x) |
| Any UInt32Value WKT JSON stringify | 235.67 | — | — | 1886.41 (8.00x) | 991.91 (4.21x) |
| Any UInt32Value WKT JSON parse | 656.12 | — | — | 3102.41 (4.73x) | 1727.93 (2.63x) |
| Any UInt32Value String WKT JSON parse | 654.62 | — | — | 3172.07 (4.85x) | 2125.37 (3.25x) |
| Any UInt32Value Exponent WKT JSON parse | 639.51 | — | — | 3169.99 (4.96x) | 1848.93 (2.89x) |
| Any ZeroUInt32Value WKT JSON stringify | 221.29 | — | — | 1022.12 (4.62x) | 707.98 (3.20x) |
| Any ZeroUInt32Value WKT JSON parse | 632.96 | — | — | 2537.15 (4.01x) | 1881.31 (2.97x) |
| Any MaxUInt32Value WKT JSON stringify | 228.61 | — | — | 1942.22 (8.50x) | 874.74 (3.83x) |
| Any MaxUInt32Value WKT JSON parse | 676.74 | — | — | 3284.40 (4.85x) | 1755.12 (2.59x) |
| Any BoolValue WKT JSON stringify | 233.29 | — | — | 1895.11 (8.12x) | 854.75 (3.66x) |
| Any BoolValue WKT JSON parse | 614.40 | — | — | 3286.09 (5.35x) | 1652.07 (2.69x) |
| Any FalseBoolValue WKT JSON stringify | 243.58 | — | — | 1057.79 (4.34x) | 753.85 (3.09x) |
| Any FalseBoolValue WKT JSON parse | 628.63 | — | — | 2524.24 (4.02x) | 1516.98 (2.41x) |
| Any StringValue WKT JSON stringify | 266.21 | — | — | 2680.21 (10.07x) | 894.54 (3.36x) |
| Any StringValue WKT JSON parse | 706.83 | — | — | 3135.29 (4.44x) | 1787.07 (2.53x) |
| Any StringValue Escape WKT JSON parse | 694.65 | — | — | 3419.47 (4.92x) | 2099.34 (3.02x) |
| Any StringValue Surrogate WKT JSON parse | 699.67 | — | — | 3186.56 (4.55x) | 2040.17 (2.92x) |
| Any EmptyStringValue WKT JSON stringify | 237.55 | — | — | 996.52 (4.19x) | 893.20 (3.76x) |
| Any EmptyStringValue WKT JSON parse | 636.76 | — | — | 2543.28 (3.99x) | 1712.96 (2.69x) |
| Any BytesValue WKT JSON stringify | 234.38 | — | — | 1976.80 (8.43x) | 1003.87 (4.28x) |
| Any BytesValue WKT JSON parse | 662.18 | — | — | 3252.66 (4.91x) | 1583.33 (2.39x) |
| Any BytesValue URL WKT JSON parse | 682.27 | — | — | 3059.81 (4.48x) | 1897.95 (2.78x) |
| Any BytesValue StandardBase64 WKT JSON parse | 688.31 | — | — | 3108.83 (4.52x) | 2111.22 (3.07x) |
| Any BytesValue Unpadded WKT JSON parse | 709.79 | — | — | 3161.71 (4.45x) | 2004.35 (2.82x) |
| Any EmptyBytesValue WKT JSON stringify | 243.19 | — | — | 1119.29 (4.60x) | 996.42 (4.10x) |
| Any EmptyBytesValue WKT JSON parse | 677.72 | — | — | 2657.78 (3.92x) | 1861.90 (2.75x) |
| Nested Any WKT JSON stringify | 421.31 | — | — | 3008.83 (7.14x) | 1677.72 (3.98x) |
| Nested Any WKT JSON parse | 1081.05 | — | — | 5165.93 (4.78x) | 3494.79 (3.23x) |
| Duration JSON stringify | 68.70 | — | — | 955.32 (13.91x) | 358.90 (5.22x) |
| Duration JSON parse | 26.55 | — | — | 1698.07 (63.96x) | 400.50 (15.08x) |
| Duration Escape JSON parse | 55.37 | — | — | 1746.13 (31.54x) | 444.32 (8.02x) |
| PlusDuration JSON parse | 26.83 | — | — | 1637.38 (61.03x) | 396.64 (14.78x) |
| ShortFractionDuration JSON parse | 24.71 | — | — | 1782.16 (72.12x) | 356.54 (14.43x) |
| MicroDuration JSON stringify | 73.74 | — | — | 963.95 (13.07x) | 418.12 (5.67x) |
| MicroDuration JSON parse | 28.45 | — | — | 1757.46 (61.77x) | 435.00 (15.29x) |
| NanoDuration JSON stringify | 68.52 | — | — | 1119.83 (16.34x) | 393.90 (5.75x) |
| NanoDuration JSON parse | 34.08 | — | — | 1780.93 (52.26x) | 413.28 (12.13x) |
| NegativeDuration JSON stringify | 69.89 | — | — | 1333.06 (19.07x) | 436.14 (6.24x) |
| NegativeDuration JSON parse | 26.60 | — | — | 1937.38 (72.83x) | 415.42 (15.62x) |
| FractionalNegativeDuration JSON stringify | 70.25 | — | — | 1127.76 (16.05x) | 456.85 (6.50x) |
| FractionalNegativeDuration JSON parse | 27.51 | — | — | 1817.64 (66.07x) | 361.61 (13.14x) |
| MaxDuration JSON stringify | 58.38 | — | — | 959.01 (16.43x) | 441.51 (7.56x) |
| MaxDuration JSON parse | 45.26 | — | — | 1647.17 (36.39x) | 405.68 (8.96x) |
| MinDuration JSON stringify | 58.47 | — | — | 875.56 (14.97x) | 443.19 (7.58x) |
| MinDuration JSON parse | 46.11 | — | — | 1842.00 (39.95x) | 400.98 (8.70x) |
| ZeroDuration JSON stringify | 51.61 | — | — | 901.87 (17.47x) | 345.76 (6.70x) |
| ZeroDuration JSON parse | 27.60 | — | — | 1717.74 (62.24x) | 300.47 (10.89x) |
| FieldMask JSON stringify | 96.63 | — | — | 924.67 (9.57x) | 704.27 (7.29x) |
| FieldMask JSON parse | 187.48 | — | — | 2011.85 (10.73x) | 994.22 (5.30x) |
| FieldMask Escape JSON parse | 249.08 | — | — | 2199.63 (8.83x) | 1197.27 (4.81x) |
| EmptyFieldMask JSON stringify | 44.92 | — | — | 994.02 (22.13x) | 224.77 (5.00x) |
| EmptyFieldMask JSON parse | 7.66 | — | — | 1499.29 (195.73x) | 190.86 (24.92x) |
| Timestamp JSON stringify | 131.08 | — | — | 1404.10 (10.71x) | 495.65 (3.78x) |
| Timestamp JSON parse | 66.71 | — | — | 1851.38 (27.75x) | 491.42 (7.37x) |
| Timestamp Escape JSON parse | 115.25 | — | — | 1914.63 (16.61x) | 530.17 (4.60x) |
| ShortFraction Timestamp JSON parse | 62.70 | — | — | 1861.02 (29.68x) | 470.75 (7.51x) |
| Micro Timestamp JSON stringify | 132.04 | — | — | 1782.28 (13.50x) | 418.17 (3.17x) |
| Micro Timestamp JSON parse | 71.01 | — | — | 1851.00 (26.07x) | 502.52 (7.08x) |
| Nano Timestamp JSON stringify | 131.85 | — | — | 1375.69 (10.43x) | 454.57 (3.45x) |
| Nano Timestamp JSON parse | 75.60 | — | — | 1869.42 (24.73x) | 456.44 (6.04x) |
| Offset Timestamp JSON parse | 79.69 | — | — | 2140.57 (26.86x) | 488.18 (6.13x) |
| PreEpoch Timestamp JSON stringify | 86.69 | — | — | 1196.98 (13.81x) | 498.63 (5.75x) |
| PreEpoch Timestamp JSON parse | 62.30 | — | — | 1699.31 (27.28x) | 429.07 (6.89x) |
| Max Timestamp JSON stringify | 105.68 | — | — | 1380.97 (13.07x) | 446.37 (4.22x) |
| Max Timestamp JSON parse | 78.76 | — | — | 1882.45 (23.90x) | 476.98 (6.06x) |
| Min Timestamp JSON stringify | 121.95 | — | — | 1259.96 (10.33x) | 420.75 (3.45x) |
| Min Timestamp JSON parse | 61.93 | — | — | 1792.46 (28.94x) | 425.46 (6.87x) |
| Empty JSON stringify | 24.41 | — | — | 502.98 (20.61x) | 88.40 (3.62x) |
| Empty JSON parse | 78.94 | — | — | 813.41 (10.30x) | 198.76 (2.52x) |
| Struct JSON stringify | 285.69 | — | — | 7419.36 (25.97x) | 3759.71 (13.16x) |
| Struct JSON parse | 1017.34 | — | — | 14646.30 (14.40x) | 6452.88 (6.34x) |
| Struct Escape JSON parse | 1095.14 | — | — | 16380.20 (14.96x) | 6536.86 (5.97x) |
| Struct NumberExponent JSON parse | 1045.08 | — | — | 15328.00 (14.67x) | 6545.55 (6.26x) |
| Struct Surrogate JSON parse | 421.08 | — | — | 5677.53 (13.48x) | 1699.64 (4.04x) |
| Struct KeySurrogate JSON parse | 418.51 | — | — | 6191.53 (14.79x) | 1523.55 (3.64x) |
| EmptyStruct JSON stringify | 46.77 | — | — | 853.70 (18.25x) | 355.74 (7.61x) |
| EmptyStruct JSON parse | 100.27 | — | — | 2676.44 (26.69x) | 380.48 (3.79x) |
| Value JSON stringify | 288.73 | — | — | 8520.63 (29.51x) | 4048.98 (14.02x) |
| Value JSON parse | 986.60 | — | — | 15871.80 (16.09x) | 6781.46 (6.87x) |
| Value Escape JSON parse | 1020.23 | — | — | 15108.70 (14.81x) | 6458.88 (6.33x) |
| Value NumberExponent JSON parse | 976.71 | — | — | 16203.60 (16.59x) | 6537.45 (6.69x) |
| Value Surrogate JSON parse | 435.81 | — | — | 8301.05 (19.05x) | 1952.23 (4.48x) |
| Value KeySurrogate JSON parse | 442.50 | — | — | 8453.38 (19.10x) | 2011.74 (4.55x) |
| NullValue JSON stringify | 47.38 | — | — | 2062.90 (43.54x) | 226.46 (4.78x) |
| NullValue JSON parse | 63.05 | — | — | 4207.29 (66.73x) | 360.46 (5.72x) |
| StringScalarValue JSON stringify | 60.07 | — | — | 2068.88 (34.44x) | 273.88 (4.56x) |
| StringScalarValue JSON parse | 133.44 | — | — | 3401.56 (25.49x) | 450.81 (3.38x) |
| StringScalarValue Escape JSON parse | 148.07 | — | — | 3077.76 (20.79x) | 475.75 (3.21x) |
| StringScalarValue Surrogate JSON parse | 151.94 | — | — | 2862.02 (18.84x) | 533.98 (3.51x) |
| EmptyStringScalarValue JSON stringify | 56.83 | — | — | 2104.91 (37.04x) | 340.83 (6.00x) |
| EmptyStringScalarValue JSON parse | 76.76 | — | — | 3353.74 (43.69x) | 409.37 (5.33x) |
| NumberValue JSON stringify | 126.35 | — | — | 2591.47 (20.51x) | 343.04 (2.71x) |
| NumberValue JSON parse | 133.81 | — | — | 3615.85 (27.02x) | 504.87 (3.77x) |
| NumberValue Exponent JSON parse | 137.88 | — | — | 2928.79 (21.24x) | 420.39 (3.05x) |
| NegativeNumberValue JSON stringify | 126.58 | — | — | 2372.90 (18.75x) | 341.52 (2.70x) |
| NegativeNumberValue JSON parse | 133.90 | — | — | 3722.52 (27.80x) | 410.15 (3.06x) |
| ZeroNumberValue JSON stringify | 72.27 | — | — | 2309.25 (31.95x) | 261.87 (3.62x) |
| ZeroNumberValue JSON parse | 135.88 | — | — | 2734.39 (20.12x) | 395.57 (2.91x) |
| BoolScalarValue JSON stringify | 48.68 | — | — | 1791.70 (36.81x) | 211.00 (4.33x) |
| BoolScalarValue JSON parse | 61.25 | — | — | 2701.88 (44.11x) | 340.25 (5.56x) |
| FalseBoolScalarValue JSON stringify | 48.23 | — | — | 1710.00 (35.46x) | 241.08 (5.00x) |
| FalseBoolScalarValue JSON parse | 61.73 | — | — | 2523.87 (40.89x) | 302.21 (4.90x) |
| ListKindValue JSON stringify | 228.20 | — | — | 8630.08 (37.82x) | 3122.94 (13.69x) |
| ListKindValue JSON parse | 831.24 | — | — | 15775.10 (18.98x) | 5136.89 (6.18x) |
| ListKindValue Escape JSON parse | 831.06 | — | — | 14539.50 (17.50x) | 5831.40 (7.02x) |
| ListKindValue Surrogate JSON parse | 355.57 | — | — | 6089.42 (17.13x) | 1359.72 (3.82x) |
| EmptyStructKindValue JSON stringify | 47.69 | — | — | 2325.32 (48.76x) | 619.83 (13.00x) |
| EmptyStructKindValue JSON parse | 109.40 | — | — | 4626.78 (42.29x) | 775.26 (7.09x) |
| EmptyListKindValue JSON stringify | 46.13 | — | — | 2380.74 (51.61x) | 376.59 (8.16x) |
| EmptyListKindValue JSON parse | 147.72 | — | — | 4982.16 (33.73x) | 596.69 (4.04x) |
| ListValue JSON stringify | 213.58 | — | — | 6026.27 (28.22x) | 2506.37 (11.74x) |
| ListValue JSON parse | 774.40 | — | — | 10721.70 (13.85x) | 5022.47 (6.49x) |
| ListValue Escape JSON parse | 825.42 | — | — | 14260.40 (17.28x) | 5282.13 (6.40x) |
| ListValue Surrogate JSON parse | 360.72 | — | — | 3668.16 (10.17x) | 1255.56 (3.48x) |
| EmptyListValue JSON stringify | 47.97 | — | — | 685.51 (14.29x) | 181.91 (3.79x) |
| EmptyListValue JSON parse | 148.71 | — | — | 2654.33 (17.85x) | 353.72 (2.38x) |
| DoubleValue JSON stringify | 109.31 | — | — | 1005.57 (9.20x) | 203.96 (1.87x) |
| DoubleValue JSON parse | 130.72 | — | — | 1320.71 (10.10x) | 282.99 (2.16x) |
| DoubleValue String JSON parse | 127.86 | — | — | 1409.15 (11.02x) | 398.22 (3.11x) |
| DoubleValue Exponent JSON parse | 137.42 | — | — | 1406.51 (10.24x) | 310.39 (2.26x) |
| NegativeDoubleValue JSON stringify | 109.16 | — | — | 888.68 (8.14x) | 212.24 (1.94x) |
| NegativeDoubleValue JSON parse | 131.28 | — | — | 1545.08 (11.77x) | 340.75 (2.60x) |
| ZeroDoubleValue JSON stringify | 60.91 | — | — | 1517.41 (24.91x) | 137.05 (2.25x) |
| ZeroDoubleValue JSON parse | 135.55 | — | — | 2043.14 (15.07x) | 262.16 (1.93x) |
| DoubleValue NaN JSON stringify | 60.29 | — | — | 1105.80 (18.34x) | 155.41 (2.58x) |
| DoubleValue NaN JSON parse | 119.07 | — | — | 1870.95 (15.71x) | 325.69 (2.74x) |
| DoubleValue Infinity JSON stringify | 65.28 | — | — | 686.79 (10.52x) | 157.90 (2.42x) |
| DoubleValue Infinity JSON parse | 124.90 | — | — | 1486.08 (11.90x) | 274.73 (2.20x) |
| DoubleValue NegativeInfinity JSON stringify | 66.46 | — | — | 1066.78 (16.05x) | 127.88 (1.92x) |
| DoubleValue NegativeInfinity JSON parse | 122.60 | — | — | 1420.60 (11.59x) | 307.76 (2.51x) |
| FloatValue JSON stringify | 115.34 | — | — | 805.33 (6.98x) | 187.13 (1.62x) |
| FloatValue JSON parse | 130.38 | — | — | 1666.69 (12.78x) | 347.57 (2.67x) |
| FloatValue String JSON parse | 128.24 | — | — | 1329.72 (10.37x) | 397.62 (3.10x) |
| FloatValue Exponent JSON parse | 135.96 | — | — | 1422.20 (10.46x) | 304.70 (2.24x) |
| NegativeFloatValue JSON stringify | 114.08 | — | — | 1021.01 (8.95x) | 208.25 (1.83x) |
| NegativeFloatValue JSON parse | 127.10 | — | — | 1693.18 (13.32x) | 298.25 (2.35x) |
| ZeroFloatValue JSON stringify | 58.96 | — | — | 798.47 (13.54x) | 208.73 (3.54x) |
| ZeroFloatValue JSON parse | 129.71 | — | — | 1218.01 (9.39x) | 267.33 (2.06x) |
| FloatValue NaN JSON stringify | 55.09 | — | — | 640.93 (11.63x) | 156.41 (2.84x) |
| FloatValue NaN JSON parse | 111.15 | — | — | 1175.60 (10.58x) | 323.62 (2.91x) |
| FloatValue Infinity JSON stringify | 59.58 | — | — | 654.63 (10.99x) | 144.98 (2.43x) |
| FloatValue Infinity JSON parse | 113.34 | — | — | 1667.29 (14.71x) | 242.88 (2.14x) |
| FloatValue NegativeInfinity JSON stringify | 61.04 | — | — | 1024.28 (16.78x) | 151.50 (2.48x) |
| FloatValue NegativeInfinity JSON parse | 117.31 | — | — | 1841.14 (15.69x) | 272.95 (2.33x) |
| Int64Value JSON stringify | 57.19 | — | — | 748.26 (13.08x) | 284.31 (4.97x) |
| Int64Value JSON parse | 144.11 | — | — | 1434.92 (9.96x) | 559.82 (3.88x) |
| Int64Value Number JSON parse | 159.27 | — | — | 1543.95 (9.69x) | 393.89 (2.47x) |
| Int64Value Exponent JSON parse | 129.16 | — | — | 1390.19 (10.76x) | 383.53 (2.97x) |
| ZeroInt64Value JSON stringify | 46.28 | — | — | 615.08 (13.29x) | 183.21 (3.96x) |
| ZeroInt64Value JSON parse | 107.50 | — | — | 1417.64 (13.19x) | 339.84 (3.16x) |
| NegativeInt64Value JSON stringify | 57.05 | — | — | 680.59 (11.93x) | 302.80 (5.31x) |
| NegativeInt64Value JSON parse | 146.11 | — | — | 1318.59 (9.02x) | 473.52 (3.24x) |
| MinInt64Value JSON stringify | 62.64 | — | — | 743.24 (11.87x) | 290.33 (4.63x) |
| MinInt64Value JSON parse | 153.93 | — | — | 1644.64 (10.68x) | 530.13 (3.44x) |
| MaxInt64Value JSON stringify | 61.27 | — | — | 764.93 (12.48x) | 268.53 (4.38x) |
| MaxInt64Value JSON parse | 150.14 | — | — | 1524.08 (10.15x) | 476.19 (3.17x) |
| UInt64Value JSON stringify | 55.64 | — | — | 674.05 (12.11x) | 266.37 (4.79x) |
| UInt64Value JSON parse | 143.34 | — | — | 1401.15 (9.78x) | 471.30 (3.29x) |
| UInt64Value Number JSON parse | 156.60 | — | — | 1450.37 (9.26x) | 391.63 (2.50x) |
| UInt64Value Exponent JSON parse | 124.00 | — | — | 1454.01 (11.73x) | 364.52 (2.94x) |
| ZeroUInt64Value JSON stringify | 43.38 | — | — | 642.47 (14.81x) | 191.00 (4.40x) |
| ZeroUInt64Value JSON parse | 104.37 | — | — | 1321.44 (12.66x) | 405.17 (3.88x) |
| MaxUInt64Value JSON stringify | 57.64 | — | — | 726.98 (12.61x) | 270.33 (4.69x) |
| MaxUInt64Value JSON parse | 153.65 | — | — | 1300.51 (8.46x) | 476.61 (3.10x) |
| Int32Value JSON stringify | 48.11 | — | — | 961.67 (19.99x) | 163.40 (3.40x) |
| Int32Value JSON parse | 137.69 | — | — | 2027.27 (14.72x) | 362.56 (2.63x) |
| Int32Value String JSON parse | 133.97 | — | — | 1257.66 (9.39x) | 417.39 (3.12x) |
| Int32Value Exponent JSON parse | 142.54 | — | — | 2205.72 (15.47x) | 373.59 (2.62x) |
| ZeroInt32Value JSON stringify | 49.98 | — | — | 672.31 (13.45x) | 150.75 (3.02x) |
| ZeroInt32Value JSON parse | 138.33 | — | — | 1332.01 (9.63x) | 294.45 (2.13x) |
| NegativeInt32Value JSON stringify | 51.55 | — | — | 1085.90 (21.06x) | 142.83 (2.77x) |
| NegativeInt32Value JSON parse | 142.31 | — | — | 2084.40 (14.65x) | 318.01 (2.23x) |
| MinInt32Value JSON stringify | 51.76 | — | — | 1053.80 (20.36x) | 153.31 (2.96x) |
| MinInt32Value JSON parse | 157.26 | — | — | 2073.23 (13.18x) | 346.86 (2.21x) |
| MaxInt32Value JSON stringify | 54.30 | — | — | 1034.79 (19.06x) | 162.36 (2.99x) |
| MaxInt32Value JSON parse | 160.79 | — | — | 1652.34 (10.28x) | 341.48 (2.12x) |
| UInt32Value JSON stringify | 52.99 | — | — | 626.19 (11.82x) | 137.67 (2.60x) |
| UInt32Value JSON parse | 150.08 | — | — | 1493.10 (9.95x) | 307.53 (2.05x) |
| UInt32Value String JSON parse | 143.34 | — | — | 1188.43 (8.29x) | 422.94 (2.95x) |
| UInt32Value Exponent JSON parse | 152.66 | — | — | 1378.08 (9.03x) | 385.15 (2.52x) |
| ZeroUInt32Value JSON stringify | 53.86 | — | — | 999.18 (18.55x) | 154.55 (2.87x) |
| ZeroUInt32Value JSON parse | 144.18 | — | — | 1865.23 (12.94x) | 352.05 (2.44x) |
| MaxUInt32Value JSON stringify | 54.09 | — | — | 670.23 (12.39x) | 155.76 (2.88x) |
| MaxUInt32Value JSON parse | 161.41 | — | — | 1342.09 (8.31x) | 355.07 (2.20x) |
| BoolValue JSON stringify | 52.13 | — | — | 620.55 (11.90x) | 191.63 (3.68x) |
| BoolValue JSON parse | 66.88 | — | — | 1137.27 (17.00x) | 235.91 (3.53x) |
| FalseBoolValue JSON stringify | 52.28 | — | — | 661.62 (12.66x) | 123.41 (2.36x) |
| FalseBoolValue JSON parse | 67.48 | — | — | 1238.96 (18.36x) | 218.25 (3.23x) |
| StringValue JSON stringify | 62.61 | — | — | 1097.67 (17.53x) | 211.46 (3.38x) |
| StringValue JSON parse | 136.36 | — | — | 1290.04 (9.46x) | 298.83 (2.19x) |
| StringValue Escape JSON parse | 149.80 | — | — | 1588.54 (10.60x) | 395.59 (2.64x) |
| StringValue Surrogate JSON parse | 155.34 | — | — | 1317.16 (8.48x) | 424.98 (2.74x) |
| EmptyStringValue JSON stringify | 59.79 | — | — | 621.18 (10.39x) | 283.29 (4.74x) |
| EmptyStringValue JSON parse | 74.70 | — | — | 1173.82 (15.71x) | 292.64 (3.92x) |
| BytesValue JSON stringify | 56.00 | — | — | 653.84 (11.68x) | 327.51 (5.85x) |
| BytesValue JSON parse | 150.48 | — | — | 1250.45 (8.31x) | 342.33 (2.27x) |
| BytesValue URL JSON parse | 169.95 | — | — | 1353.67 (7.97x) | 358.23 (2.11x) |
| BytesValue StandardBase64 JSON parse | 150.25 | — | — | 1442.90 (9.60x) | 339.22 (2.26x) |
| BytesValue Unpadded JSON parse | 146.10 | — | — | 1397.79 (9.57x) | 330.30 (2.26x) |
| EmptyBytesValue JSON stringify | 47.12 | — | — | 633.45 (13.44x) | 193.12 (4.10x) |
| EmptyBytesValue JSON parse | 78.25 | — | — | 1288.53 (16.47x) | 293.97 (3.76x) |
| TextFormat format | 265.02 | — | — | 3055.27 (11.53x) | 3257.72 (12.29x) |
| TextFormat parse | 933.90 | — | — | 5926.27 (6.35x) | 8328.31 (8.92x) |
| packed fixed32 encode | 2.01 | 890.07 (442.82x) | 677.39 (337.01x) | 80.28 (39.94x) | 504.49 (250.99x) |
| packed fixed32 decode | 4.53 | 2141.34 (472.70x) | 2868.76 (633.28x) | 102.38 (22.60x) | 2024.15 (446.83x) |
| packed fixed64 encode | 2.70 | 770.68 (285.44x) | 689.20 (255.26x) | 86.58 (32.07x) | 398.82 (147.71x) |
| packed fixed64 decode | 9.14 | 2154.71 (235.75x) | 8090.30 (885.15x) | 79.40 (8.69x) | 3818.66 (417.80x) |
| packed sfixed32 encode | 2.73 | 718.89 (263.33x) | 615.37 (225.41x) | 44.65 (16.35x) | 406.60 (148.94x) |
| packed sfixed32 decode | 8.79 | 2369.22 (269.54x) | 2769.09 (315.03x) | 63.93 (7.27x) | 2443.87 (278.03x) |
| packed sfixed64 encode | 2.02 | 914.29 (452.62x) | 598.71 (296.39x) | 68.75 (34.03x) | 472.58 (233.95x) |
| packed sfixed64 decode | 8.97 | 1437.22 (160.23x) | 8584.42 (957.01x) | 79.42 (8.85x) | 3749.68 (418.02x) |
| packed float encode | 2.01 | 909.71 (452.59x) | 560.67 (278.94x) | 57.88 (28.80x) | 470.12 (233.89x) |
| packed float decode | 9.03 | 2176.12 (240.99x) | 2637.71 (292.11x) | 62.87 (6.96x) | 2427.60 (268.84x) |
| packed double encode | 2.85 | 943.30 (330.98x) | 582.17 (204.27x) | 75.69 (26.56x) | 393.12 (137.94x) |
| packed double decode | 9.10 | 2181.72 (239.75x) | 2444.43 (268.62x) | 79.66 (8.75x) | 3974.90 (436.80x) |
| packed uint64 encode | 1303.58 | 7277.58 (5.58x) | 5316.56 (4.08x) | 2641.13 (2.03x) | 4839.47 (3.71x) |
| packed uint64 decode | 1820.99 | 4804.27 (2.64x) | 9763.55 (5.36x) | 3361.45 (1.85x) | 12651.02 (6.95x) |
| packed uint32 encode | 953.91 | 5426.53 (5.69x) | 4138.21 (4.34x) | 2170.76 (2.28x) | 3896.26 (4.08x) |
| packed uint32 decode | 1353.22 | 4672.13 (3.45x) | 4633.73 (3.42x) | 2426.79 (1.79x) | 8375.13 (6.19x) |
| packed int64 encode | 1385.42 | 13109.61 (9.46x) | 7506.62 (5.42x) | 3701.90 (2.67x) | 5577.63 (4.03x) |
| packed int64 decode | 2745.90 | 4289.91 (1.56x) | 11436.45 (4.16x) | 5661.50 (2.06x) | 15502.91 (5.65x) |
| packed sint32 encode | 864.11 | 3628.01 (4.20x) | 3246.51 (3.76x) | 2034.60 (2.35x) | 4461.70 (5.16x) |
| packed sint32 decode | 1064.89 | 3022.83 (2.84x) | 4603.25 (4.32x) | 1299.27 (1.22x) | 5407.17 (5.08x) |
| packed sint64 encode | 1434.53 | 6320.15 (4.41x) | 6418.52 (4.47x) | 2908.13 (2.03x) | 5771.46 (4.02x) |
| packed sint64 decode | 2039.04 | 4129.37 (2.03x) | 10593.40 (5.20x) | 3665.10 (1.80x) | 12133.62 (5.95x) |
| packed bool encode | 2.01 | 1569.40 (780.80x) | 531.10 (264.23x) | 23.13 (11.51x) | 3090.14 (1537.38x) |
| packed bool decode | 264.65 | 1887.12 (7.13x) | 3051.44 (11.53x) | 965.04 (3.65x) | 2462.30 (9.30x) |
| packed enum encode | 323.43 | 3129.14 (9.67x) | 2048.30 (6.33x) | 1157.75 (3.58x) | 3469.34 (10.73x) |
| packed enum decode | 155.92 | 1947.50 (12.49x) | 4275.25 (27.42x) | 704.28 (4.52x) | 3503.47 (22.47x) |
| large map encode | 4089.11 | 23284.26 (5.69x) | 14060.41 (3.44x) | 24514.40 (6.00x) | 233653.77 (57.14x) |
| shuffled large map deterministic binary encode | 34977.01 | — | — | 101321.00 (2.90x) | 439921.96 (12.58x) |
| large map decode | 27759.95 | 111269.04 (4.01x) | 113027.82 (4.07x) | 105549.00 (3.80x) | 345506.12 (12.45x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON (including generated `map<string, int32>` surrogate-pair key parse and integer numeric-exponent parse), Any/WKT JSON (including embedded zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound `Duration`, non-empty/escaped-input parse/number-exponent parse/surrogate-pair value parse/surrogate-pair key parse and empty `Struct`, object/escaped-object parse/object-number-exponent/object-surrogate-pair value parse/object-surrogate-pair key parse/list/escaped-list/surrogate-list/string-scalar/escaped-string-scalar/surrogate-string-scalar/number-exponent/negative-number `Value` (including default-like scalar and empty object/list kinds),
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
