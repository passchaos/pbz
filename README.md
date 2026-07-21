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

Latest accepted comparison (`/tmp/pbz-compare-large-map-json-final.log`,
summarized in `/tmp/pbz-summary-large-map-json-final.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Pivoted rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 16.71 | 102.34 (6.12x) | 53.73 (3.22x) | 109.44 (6.55x) | 816.10 (48.84x) |
| binary decode | 88.39 | 260.17 (2.94x) | 233.26 (2.64x) | 207.29 (2.35x) | 861.39 (9.75x) |
| unknown fields count by number | 3.89 | — | — | 162.68 (41.82x) | — |
| deterministic binary encode | 59.94 | — | — | 126.84 (2.12x) | 1135.50 (18.94x) |
| scalarmix encode | 19.92 | 115.27 (5.79x) | 47.60 (2.39x) | 29.21 (1.47x) | 216.44 (10.87x) |
| scalarmix decode | 44.31 | 137.40 (3.10x) | 184.72 (4.17x) | 80.75 (1.82x) | 317.92 (7.17x) |
| textbytes encode | 13.68 | 78.17 (5.71x) | 33.46 (2.45x) | 119.39 (8.73x) | 147.96 (10.82x) |
| textbytes decode | 37.39 | 379.14 (10.14x) | 239.06 (6.39x) | 164.47 (4.40x) | 622.38 (16.65x) |
| TextBytes JSON stringify | 345.38 | — | — | 2237.00 (6.48x) | 2133.85 (6.18x) |
| TextBytes JSON parse | 1386.43 | — | — | 5681.59 (4.10x) | 3701.49 (2.67x) |
| largebytes encode | 17.56 | 2715.92 (154.67x) | 2671.85 (152.16x) | 2746.40 (156.40x) | 2720.60 (154.93x) |
| largebytes decode | 92.51 | 5589.24 (60.42x) | 3030.40 (32.76x) | 2755.66 (29.79x) | 23549.79 (254.56x) |
| presencemix encode | 16.79 | 54.32 (3.24x) | 27.16 (1.62x) | 55.32 (3.30x) | 234.93 (13.99x) |
| presencemix decode | 55.37 | 130.07 (2.35x) | 108.30 (1.96x) | 161.84 (2.92x) | 498.46 (9.00x) |
| PresenceMix JSON stringify | 139.53 | — | — | 3094.21 (22.18x) | 2450.62 (17.56x) |
| PresenceMix JSON parse | 1168.54 | — | — | 6166.23 (5.28x) | 2893.09 (2.48x) |
| complex encode | 48.82 | 138.79 (2.84x) | 95.10 (1.95x) | 163.87 (3.36x) | 934.89 (19.15x) |
| complex decode | 170.43 | 392.57 (2.30x) | 340.88 (2.00x) | 400.69 (2.35x) | 1377.97 (8.09x) |
| complex deterministic binary encode | 93.93 | — | — | 171.34 (1.82x) | 1174.11 (12.50x) |
| complex JSON stringify | 267.77 | — | — | 4900.93 (18.30x) | 5916.58 (22.10x) |
| complex JSON parse | 2391.16 | — | — | 12116.70 (5.07x) | 7088.31 (2.96x) |
| Complex ProtoName JSON stringify | 267.31 | — | — | 5199.47 (19.45x) | 6320.46 (23.64x) |
| Complex ProtoName JSON parse | 2404.21 | — | — | 12322.50 (5.13x) | 7327.55 (3.05x) |
| complex TextFormat format | 246.48 | — | — | 3790.51 (15.38x) | 5323.66 (21.60x) |
| complex TextFormat parse | 1834.80 | — | — | 8063.46 (4.39x) | 8497.48 (4.63x) |
| packed int32 encode | 646.75 | 3189.28 (4.93x) | 2533.63 (3.92x) | 2268.60 (3.51x) | 2865.15 (4.43x) |
| packed int32 decode | 799.37 | 1899.34 (2.38x) | 3229.53 (4.04x) | 1350.50 (1.69x) | 3379.80 (4.23x) |
| JSON stringify | 206.57 | — | — | 4974.20 (24.08x) | 2173.68 (10.52x) |
| AlwaysPrint JSON stringify | 72.17 | — | — | 4483.53 (62.12x) | 1278.81 (17.72x) |
| ProtoName JSON stringify | 427.60 | — | — | 7480.27 (17.49x) | 3991.81 (9.34x) |
| EnumNumber JSON stringify | 400.98 | — | — | 7557.05 (18.85x) | 3845.45 (9.59x) |
| JSON parse | 1693.18 | — | — | 7499.52 (4.43x) | 4305.99 (2.54x) |
| MapKeySurrogate JSON parse | 448.99 | — | — | 3562.60 (7.93x) | 1044.92 (2.33x) |
| NullFields JSON parse | 539.63 | — | — | 2063.59 (3.82x) | 771.22 (1.43x) |
| IgnoreUnknown JSON parse | 1251.56 | — | — | 6984.68 (5.58x) | 2533.87 (2.02x) |
| OpenEnum JSON parse | 306.84 | — | — | 3790.07 (12.35x) | 492.42 (1.60x) |
| EnumName JSON parse | 303.25 | — | — | 3860.62 (12.73x) | 518.92 (1.71x) |
| ProtoName JSON parse | 539.92 | — | — | 5315.03 (9.84x) | 1162.51 (2.15x) |
| IntExponent JSON parse | 1749.87 | — | — | 9632.44 (5.50x) | 3935.09 (2.25x) |
| StringNumber JSON parse | 1906.60 | — | — | 9288.26 (4.87x) | 4364.93 (2.29x) |
| Any WKT JSON stringify | 134.93 | — | — | 1901.12 (14.09x) | 945.90 (7.01x) |
| Any WKT JSON parse | 565.63 | — | — | 3102.02 (5.48x) | 1672.48 (2.96x) |
| Any Duration Escape WKT JSON parse | 551.20 | — | — | 3131.01 (5.68x) | 1528.93 (2.77x) |
| Any PlusDuration WKT JSON parse | 525.19 | — | — | 3135.89 (5.97x) | 1541.58 (2.94x) |
| Any ShortFractionDuration WKT JSON parse | 520.93 | — | — | 3069.90 (5.89x) | 1459.49 (2.80x) |
| Any MicroDuration WKT JSON stringify | 130.85 | — | — | 1933.37 (14.78x) | 946.58 (7.23x) |
| Any MicroDuration WKT JSON parse | 521.96 | — | — | 3086.26 (5.91x) | 1513.31 (2.90x) |
| Any NanoDuration WKT JSON stringify | 131.08 | — | — | 3121.45 (23.81x) | 983.51 (7.50x) |
| Any NanoDuration WKT JSON parse | 525.34 | — | — | 4740.95 (9.02x) | 1656.15 (3.15x) |
| Any NegativeDuration WKT JSON stringify | 131.45 | — | — | 3150.81 (23.97x) | 965.61 (7.35x) |
| Any NegativeDuration WKT JSON parse | 532.11 | — | — | 4792.41 (9.01x) | 1585.87 (2.98x) |
| Any FractionalNegativeDuration WKT JSON stringify | 125.73 | — | — | 3077.55 (24.48x) | 1043.19 (8.30x) |
| Any FractionalNegativeDuration WKT JSON parse | 518.79 | — | — | 4375.45 (8.43x) | 1713.09 (3.30x) |
| Any MaxDuration WKT JSON stringify | 119.61 | — | — | 2767.96 (23.14x) | 1021.49 (8.54x) |
| Any MaxDuration WKT JSON parse | 532.56 | — | — | 4675.55 (8.78x) | 1541.15 (2.89x) |
| Any MinDuration WKT JSON stringify | 115.27 | — | — | 1785.36 (15.49x) | 1027.80 (8.92x) |
| Any MinDuration WKT JSON parse | 531.96 | — | — | 3107.11 (5.84x) | 1597.84 (3.00x) |
| Any ZeroDuration WKT JSON stringify | 103.33 | — | — | 918.35 (8.89x) | 1009.84 (9.77x) |
| Any ZeroDuration WKT JSON parse | 464.59 | — | — | 2313.16 (4.98x) | 1523.04 (3.28x) |
| Any FieldMask WKT JSON stringify | 226.26 | — | — | 1761.38 (7.78x) | 1374.13 (6.07x) |
| Any FieldMask WKT JSON parse | 723.68 | — | — | 3590.80 (4.96x) | 2097.50 (2.90x) |
| Any FieldMask Escape WKT JSON parse | 745.21 | — | — | 4637.87 (6.22x) | 2332.56 (3.13x) |
| Any EmptyFieldMask WKT JSON stringify | 111.16 | — | — | 1139.14 (10.25x) | 765.50 (6.89x) |
| Any EmptyFieldMask WKT JSON parse | 447.46 | — | — | 3244.63 (7.25x) | 1305.73 (2.92x) |
| Any Timestamp WKT JSON stringify | 173.20 | — | — | 3050.69 (17.61x) | 994.44 (5.74x) |
| Any Timestamp WKT JSON parse | 570.48 | — | — | 4916.27 (8.62x) | 1755.02 (3.08x) |
| Any Timestamp Escape WKT JSON parse | 588.19 | — | — | 3131.89 (5.32x) | 1925.51 (3.27x) |
| Any ShortFraction Timestamp WKT JSON parse | 568.06 | — | — | 3297.67 (5.81x) | 1662.62 (2.93x) |
| Any Micro Timestamp WKT JSON stringify | 178.62 | — | — | 3056.69 (17.11x) | 1025.35 (5.74x) |
| Any Micro Timestamp WKT JSON parse | 581.56 | — | — | 4643.09 (7.98x) | 1607.28 (2.76x) |
| Any Nano Timestamp WKT JSON stringify | 177.38 | — | — | 3039.11 (17.13x) | 1033.57 (5.83x) |
| Any Nano Timestamp WKT JSON parse | 585.90 | — | — | 4659.01 (7.95x) | 1723.07 (2.94x) |
| Any Offset Timestamp WKT JSON parse | 591.90 | — | — | 4738.06 (8.00x) | 1587.08 (2.68x) |
| Any PreEpoch Timestamp WKT JSON stringify | 143.87 | — | — | 3178.62 (22.09x) | 991.77 (6.89x) |
| Any PreEpoch Timestamp WKT JSON parse | 561.03 | — | — | 5085.29 (9.06x) | 1586.98 (2.83x) |
| Any Max Timestamp WKT JSON stringify | 162.16 | — | — | 3327.20 (20.52x) | 993.87 (6.13x) |
| Any Max Timestamp WKT JSON parse | 589.31 | — | — | 5186.73 (8.80x) | 1708.25 (2.90x) |
| Any Min Timestamp WKT JSON stringify | 157.17 | — | — | 3199.54 (20.36x) | 1021.09 (6.50x) |
| Any Min Timestamp WKT JSON parse | 558.62 | — | — | 5163.32 (9.24x) | 1581.63 (2.83x) |
| Any Empty WKT JSON stringify | 87.49 | — | — | 1436.78 (16.42x) | 641.05 (7.33x) |
| Any Empty WKT JSON parse | 336.30 | — | — | 3434.27 (10.21x) | 1406.84 (4.18x) |
| Any Struct WKT JSON stringify | 627.55 | — | — | 10025.00 (15.97x) | 6354.07 (10.13x) |
| Any Struct WKT JSON parse | 2269.03 | — | — | 18636.20 (8.21x) | 9073.41 (4.00x) |
| Any Struct Escape WKT JSON parse | 2417.46 | — | — | 18902.40 (7.82x) | 9010.10 (3.73x) |
| Any Struct NumberExponent WKT JSON parse | 2460.91 | — | — | 17146.70 (6.97x) | 8719.61 (3.54x) |
| Any Struct Surrogate WKT JSON parse | 805.29 | — | — | 9996.10 (12.41x) | 3284.24 (4.08x) |
| Any Struct KeySurrogate WKT JSON parse | 991.20 | — | — | 6379.34 (6.44x) | 3357.14 (3.39x) |
| Any EmptyStruct WKT JSON stringify | 122.11 | — | — | 910.75 (7.46x) | 929.88 (7.62x) |
| Any EmptyStruct WKT JSON parse | 504.48 | — | — | 2784.79 (5.52x) | 1539.00 (3.05x) |
| Any Value WKT JSON stringify | 705.31 | — | — | 5935.57 (8.42x) | 6888.70 (9.77x) |
| Any Value WKT JSON parse | 2153.49 | — | — | 15799.80 (7.34x) | 9122.57 (4.24x) |
| Any Value Escape WKT JSON parse | 2107.13 | — | — | 12965.30 (6.15x) | 9512.23 (4.51x) |
| Any Value NumberExponent WKT JSON parse | 2093.06 | — | — | 11557.30 (5.52x) | 9189.69 (4.39x) |
| Any Value Surrogate WKT JSON parse | 920.69 | — | — | 6707.90 (7.29x) | 3518.44 (3.82x) |
| Any Value KeySurrogate WKT JSON parse | 921.02 | — | — | 6708.24 (7.28x) | 3513.21 (3.81x) |
| Any NullValue WKT JSON stringify | 167.05 | — | — | 2291.53 (13.72x) | 890.76 (5.33x) |
| Any NullValue WKT JSON parse | 525.24 | — | — | 6267.50 (11.93x) | 1619.45 (3.08x) |
| Any StringScalarValue WKT JSON stringify | 206.29 | — | — | 3302.00 (16.01x) | 983.22 (4.77x) |
| Any StringScalarValue WKT JSON parse | 594.56 | — | — | 4718.09 (7.94x) | 1805.57 (3.04x) |
| Any StringScalarValue Escape WKT JSON parse | 598.01 | — | — | 5480.90 (9.17x) | 1709.91 (2.86x) |
| Any StringScalarValue Surrogate WKT JSON parse | 603.11 | — | — | 5530.04 (9.17x) | 1870.09 (3.10x) |
| Any EmptyStringScalarValue WKT JSON stringify | 186.21 | — | — | 3231.18 (17.35x) | 986.69 (5.30x) |
| Any EmptyStringScalarValue WKT JSON parse | 556.97 | — | — | 5404.04 (9.70x) | 1641.22 (2.95x) |
| Any NumberValue WKT JSON stringify | 251.13 | — | — | 3961.27 (15.77x) | 1032.10 (4.11x) |
| Any NumberValue WKT JSON parse | 574.52 | — | — | 5687.12 (9.90x) | 1643.32 (2.86x) |
| Any NumberValue Exponent WKT JSON parse | 583.90 | — | — | 5739.18 (9.83x) | 1735.82 (2.97x) |
| Any NegativeNumberValue WKT JSON stringify | 252.66 | — | — | 3943.75 (15.61x) | 1130.78 (4.48x) |
| Any NegativeNumberValue WKT JSON parse | 580.66 | — | — | 5779.37 (9.95x) | 1903.01 (3.28x) |
| Any ZeroNumberValue WKT JSON stringify | 194.47 | — | — | 3836.17 (19.73x) | 971.05 (4.99x) |
| Any ZeroNumberValue WKT JSON parse | 576.72 | — | — | 5513.64 (9.56x) | 1660.10 (2.88x) |
| Any BoolScalarValue WKT JSON stringify | 177.39 | — | — | 2277.59 (12.84x) | 900.12 (5.07x) |
| Any BoolScalarValue WKT JSON parse | 536.74 | — | — | 4563.17 (8.50x) | 1583.83 (2.95x) |
| Any FalseBoolScalarValue WKT JSON stringify | 169.23 | — | — | 3194.77 (18.88x) | 1085.24 (6.41x) |
| Any FalseBoolScalarValue WKT JSON parse | 529.41 | — | — | 5413.97 (10.23x) | 1609.66 (3.04x) |
| Any ListKindValue WKT JSON stringify | 633.00 | — | — | 5996.91 (9.47x) | 5005.98 (7.91x) |
| Any ListKindValue WKT JSON parse | 1578.53 | — | — | 10100.40 (6.40x) | 7010.09 (4.44x) |
| Any ListKindValue Escape WKT JSON parse | 1577.71 | — | — | 10152.20 (6.43x) | 7228.06 (4.58x) |
| Any ListKindValue Surrogate WKT JSON parse | 805.77 | — | — | 4875.34 (6.05x) | 2614.41 (3.24x) |
| Any EmptyStructKindValue WKT JSON stringify | 182.59 | — | — | 2929.08 (16.04x) | 1425.59 (7.81x) |
| Any EmptyStructKindValue WKT JSON parse | 559.67 | — | — | 5848.46 (10.45x) | 1935.62 (3.46x) |
| Any EmptyListKindValue WKT JSON stringify | 184.36 | — | — | 2925.84 (15.87x) | 1118.45 (6.07x) |
| Any EmptyListKindValue WKT JSON parse | 558.15 | — | — | 4460.60 (7.99x) | 1896.40 (3.40x) |
| Any DoubleValue WKT JSON stringify | 252.78 | — | — | 2904.41 (11.49x) | 818.25 (3.24x) |
| Any DoubleValue WKT JSON parse | 572.81 | — | — | 2795.82 (4.88x) | 1415.34 (2.47x) |
| Any DoubleValue String WKT JSON parse | 594.09 | — | — | 2789.40 (4.70x) | 1432.68 (2.41x) |
| Any DoubleValue Exponent WKT JSON parse | 580.15 | — | — | 4427.31 (7.63x) | 1429.92 (2.46x) |
| Any NegativeDoubleValue WKT JSON stringify | 251.63 | — | — | 2892.51 (11.50x) | 762.02 (3.03x) |
| Any NegativeDoubleValue WKT JSON parse | 574.40 | — | — | 4440.40 (7.73x) | 1660.44 (2.89x) |
| Any ZeroDoubleValue WKT JSON stringify | 206.27 | — | — | 1300.65 (6.31x) | 706.23 (3.42x) |
| Any ZeroDoubleValue WKT JSON parse | 578.81 | — | — | 3249.21 (5.61x) | 1344.03 (2.32x) |
| Any DoubleValue NaN WKT JSON stringify | 203.41 | — | — | 2287.97 (11.25x) | 696.14 (3.42x) |
| Any DoubleValue NaN WKT JSON parse | 573.28 | — | — | 4053.33 (7.07x) | 1347.04 (2.35x) |
| Any DoubleValue Infinity WKT JSON stringify | 216.75 | — | — | 2326.81 (10.73x) | 687.43 (3.17x) |
| Any DoubleValue Infinity WKT JSON parse | 583.81 | — | — | 4131.10 (7.08x) | 1536.50 (2.63x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 214.01 | — | — | 1563.50 (7.31x) | 684.72 (3.20x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 585.20 | — | — | 4339.58 (7.42x) | 1356.96 (2.32x) |
| Any FloatValue WKT JSON stringify | 262.98 | — | — | 2981.61 (11.34x) | 778.97 (2.96x) |
| Any FloatValue WKT JSON parse | 578.53 | — | — | 4573.00 (7.90x) | 1525.49 (2.64x) |
| Any FloatValue String WKT JSON parse | 591.74 | — | — | 4605.39 (7.78x) | 1562.27 (2.64x) |
| Any FloatValue Exponent WKT JSON parse | 586.38 | — | — | 2772.84 (4.73x) | 1502.60 (2.56x) |
| Any NegativeFloatValue WKT JSON stringify | 265.52 | — | — | 1782.69 (6.71x) | 774.24 (2.92x) |
| Any NegativeFloatValue WKT JSON parse | 582.56 | — | — | 2753.54 (4.73x) | 1386.88 (2.38x) |
| Any ZeroFloatValue WKT JSON stringify | 206.73 | — | — | 1297.56 (6.28x) | 734.76 (3.55x) |
| Any ZeroFloatValue WKT JSON parse | 586.73 | — | — | 3196.44 (5.45x) | 1378.86 (2.35x) |
| Any FloatValue NaN WKT JSON stringify | 209.01 | — | — | 2264.28 (10.83x) | 685.77 (3.28x) |
| Any FloatValue NaN WKT JSON parse | 573.21 | — | — | 4027.28 (7.03x) | 1371.67 (2.39x) |
| Any FloatValue Infinity WKT JSON stringify | 217.43 | — | — | 2214.95 (10.19x) | 688.77 (3.17x) |
| Any FloatValue Infinity WKT JSON parse | 581.18 | — | — | 4041.92 (6.95x) | 1358.18 (2.34x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 211.21 | — | — | 2187.44 (10.36x) | 699.63 (3.31x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 587.60 | — | — | 4027.55 (6.85x) | 1362.97 (2.32x) |
| Any Int64Value WKT JSON stringify | 214.70 | — | — | 2192.30 (10.21x) | 891.58 (4.15x) |
| Any Int64Value WKT JSON parse | 627.24 | — | — | 2844.93 (4.54x) | 1658.68 (2.64x) |
| Any Int64Value Number WKT JSON parse | 624.99 | — | — | 4363.70 (6.98x) | 1493.74 (2.39x) |
| Any Int64Value Exponent WKT JSON parse | 593.22 | — | — | 4342.67 (7.32x) | 1451.08 (2.45x) |
| Any ZeroInt64Value WKT JSON stringify | 194.77 | — | — | 1287.29 (6.61x) | 771.42 (3.96x) |
| Any ZeroInt64Value WKT JSON parse | 573.11 | — | — | 3232.43 (5.64x) | 1545.14 (2.70x) |
| Any NegativeInt64Value WKT JSON stringify | 207.59 | — | — | 2195.24 (10.57x) | 856.19 (4.12x) |
| Any NegativeInt64Value WKT JSON parse | 615.32 | — | — | 4306.36 (7.00x) | 1794.25 (2.92x) |
| Any MinInt64Value WKT JSON stringify | 211.27 | — | — | 2205.30 (10.44x) | 881.48 (4.17x) |
| Any MinInt64Value WKT JSON parse | 625.38 | — | — | 2929.32 (4.68x) | 1817.26 (2.91x) |
| Any MaxInt64Value WKT JSON stringify | 250.17 | — | — | 1949.45 (7.79x) | 841.44 (3.36x) |
| Any MaxInt64Value WKT JSON parse | 910.25 | — | — | 2946.13 (3.24x) | 1787.91 (1.96x) |
| Any UInt64Value WKT JSON stringify | 273.51 | — | — | 2217.75 (8.11x) | 844.62 (3.09x) |
| Any UInt64Value WKT JSON parse | 806.79 | — | — | 4332.97 (5.37x) | 1780.06 (2.21x) |
| Any UInt64Value Number WKT JSON parse | 922.60 | — | — | 4313.06 (4.67x) | 1570.16 (1.70x) |
| Any UInt64Value Exponent WKT JSON parse | 898.87 | — | — | 4378.36 (4.87x) | 1424.65 (1.58x) |
| Any ZeroUInt64Value WKT JSON stringify | 247.08 | — | — | 1324.76 (5.36x) | 734.79 (2.97x) |
| Any ZeroUInt64Value WKT JSON parse | 816.80 | — | — | 3254.61 (3.98x) | 1491.67 (1.83x) |
| Any MaxUInt64Value WKT JSON stringify | 246.52 | — | — | 2242.11 (9.10x) | 865.49 (3.51x) |
| Any MaxUInt64Value WKT JSON parse | 771.27 | — | — | 4406.37 (5.71x) | 1708.26 (2.21x) |
| Any Int32Value WKT JSON stringify | 198.13 | — | — | 2248.41 (11.35x) | 696.67 (3.52x) |
| Any Int32Value WKT JSON parse | 760.44 | — | — | 4194.73 (5.52x) | 1572.56 (2.07x) |
| Any Int32Value String WKT JSON parse | 774.04 | — | — | 4222.99 (5.46x) | 1606.03 (2.07x) |
| Any Int32Value Exponent WKT JSON parse | 883.36 | — | — | 2812.15 (3.18x) | 1638.70 (1.86x) |
| Any ZeroInt32Value WKT JSON stringify | 261.02 | — | — | 1315.68 (5.04x) | 697.92 (2.67x) |
| Any ZeroInt32Value WKT JSON parse | 860.52 | — | — | 3197.14 (3.72x) | 1386.89 (1.61x) |
| Any NegativeInt32Value WKT JSON stringify | 284.17 | — | — | 2226.48 (7.84x) | 732.17 (2.58x) |
| Any NegativeInt32Value WKT JSON parse | 901.21 | — | — | 4171.83 (4.63x) | 1674.59 (1.86x) |
| Any MinInt32Value WKT JSON stringify | 292.46 | — | — | 2230.49 (7.63x) | 759.45 (2.60x) |
| Any MinInt32Value WKT JSON parse | 940.87 | — | — | 4239.74 (4.51x) | 1544.09 (1.64x) |
| Any MaxInt32Value WKT JSON stringify | 276.30 | — | — | 2219.61 (8.03x) | 725.78 (2.63x) |
| Any MaxInt32Value WKT JSON parse | 952.34 | — | — | 4108.44 (4.31x) | 1441.32 (1.51x) |
| Any UInt32Value WKT JSON stringify | 289.77 | — | — | 2202.15 (7.60x) | 703.34 (2.43x) |
| Any UInt32Value WKT JSON parse | 948.09 | — | — | 4156.51 (4.38x) | 1467.61 (1.55x) |
| Any UInt32Value String WKT JSON parse | 919.03 | — | — | 3668.65 (3.99x) | 1517.98 (1.65x) |
| Any UInt32Value Exponent WKT JSON parse | 962.10 | — | — | 2800.16 (2.91x) | 1548.71 (1.61x) |
| Any ZeroUInt32Value WKT JSON stringify | 283.04 | — | — | 914.00 (3.23x) | 708.34 (2.50x) |
| Any ZeroUInt32Value WKT JSON parse | 637.92 | — | — | 2195.53 (3.44x) | 1384.89 (2.17x) |
| Any MaxUInt32Value WKT JSON stringify | 247.37 | — | — | 1565.20 (6.33x) | 718.63 (2.91x) |
| Any MaxUInt32Value WKT JSON parse | 648.02 | — | — | 2747.10 (4.24x) | 1602.83 (2.47x) |
| Any BoolValue WKT JSON stringify | 235.97 | — | — | 1533.54 (6.50x) | 693.33 (2.94x) |
| Any BoolValue WKT JSON parse | 577.34 | — | — | 2660.63 (4.61x) | 1347.36 (2.33x) |
| Any FalseBoolValue WKT JSON stringify | 240.13 | — | — | 921.29 (3.84x) | 678.54 (2.83x) |
| Any FalseBoolValue WKT JSON parse | 579.17 | — | — | 2200.01 (3.80x) | 1300.01 (2.24x) |
| Any StringValue WKT JSON stringify | 281.27 | — | — | 1570.79 (5.58x) | 884.12 (3.14x) |
| Any StringValue WKT JSON parse | 659.56 | — | — | 2707.59 (4.11x) | 1435.35 (2.18x) |
| Any StringValue Escape WKT JSON parse | 669.71 | — | — | 2778.00 (4.15x) | 1463.58 (2.19x) |
| Any StringValue Surrogate WKT JSON parse | 688.76 | — | — | 2758.73 (4.01x) | 1574.20 (2.29x) |
| Any EmptyStringValue WKT JSON stringify | 259.28 | — | — | 930.09 (3.59x) | 851.18 (3.28x) |
| Any EmptyStringValue WKT JSON parse | 612.88 | — | — | 2221.75 (3.63x) | 1325.14 (2.16x) |
| Any BytesValue WKT JSON stringify | 259.88 | — | — | 1593.37 (6.13x) | 832.34 (3.20x) |
| Any BytesValue WKT JSON parse | 668.04 | — | — | 2759.16 (4.13x) | 1422.97 (2.13x) |
| Any BytesValue URL WKT JSON parse | 683.51 | — | — | 2746.34 (4.02x) | 1425.91 (2.09x) |
| Any BytesValue StandardBase64 WKT JSON parse | 669.51 | — | — | 2758.43 (4.12x) | 1415.64 (2.11x) |
| Any BytesValue Unpadded WKT JSON parse | 672.91 | — | — | 4335.16 (6.44x) | 1449.11 (2.15x) |
| Any EmptyBytesValue WKT JSON stringify | 250.37 | — | — | 929.99 (3.71x) | 724.02 (2.89x) |
| Any EmptyBytesValue WKT JSON parse | 626.29 | — | — | 2322.31 (3.71x) | 1463.85 (2.34x) |
| Nested Any WKT JSON stringify | 440.87 | — | — | 2523.85 (5.72x) | 1419.78 (3.22x) |
| Nested Any WKT JSON parse | 1089.43 | — | — | 4333.36 (3.98x) | 2824.50 (2.59x) |
| Duration JSON stringify | 67.53 | — | — | 973.76 (14.42x) | 344.97 (5.11x) |
| Duration JSON parse | 29.20 | — | — | 1471.55 (50.40x) | 369.83 (12.67x) |
| Duration Escape JSON parse | 62.66 | — | — | 1502.79 (23.98x) | 421.45 (6.73x) |
| PlusDuration JSON parse | 29.73 | — | — | 1476.32 (49.66x) | 381.56 (12.83x) |
| ShortFractionDuration JSON parse | 25.38 | — | — | 1442.71 (56.84x) | 363.42 (14.32x) |
| MicroDuration JSON stringify | 71.48 | — | — | 977.80 (13.68x) | 376.69 (5.27x) |
| MicroDuration JSON parse | 30.84 | — | — | 1489.23 (48.29x) | 365.27 (11.84x) |
| NanoDuration JSON stringify | 67.05 | — | — | 1006.98 (15.02x) | 384.06 (5.73x) |
| NanoDuration JSON parse | 33.25 | — | — | 1497.92 (45.05x) | 382.07 (11.49x) |
| NegativeDuration JSON stringify | 68.83 | — | — | 1007.47 (14.64x) | 400.94 (5.83x) |
| NegativeDuration JSON parse | 29.50 | — | — | 1524.67 (51.68x) | 371.25 (12.58x) |
| FractionalNegativeDuration JSON stringify | 68.74 | — | — | 985.55 (14.34x) | 397.58 (5.78x) |
| FractionalNegativeDuration JSON parse | 29.43 | — | — | 1480.03 (50.29x) | 351.26 (11.94x) |
| MaxDuration JSON stringify | 57.62 | — | — | 863.24 (14.98x) | 392.64 (6.81x) |
| MaxDuration JSON parse | 47.71 | — | — | 1932.23 (40.50x) | 393.53 (8.25x) |
| MinDuration JSON stringify | 57.61 | — | — | 1351.71 (23.46x) | 419.65 (7.28x) |
| MinDuration JSON parse | 46.97 | — | — | 2236.36 (47.61x) | 416.28 (8.86x) |
| ZeroDuration JSON stringify | 50.40 | — | — | 1270.49 (25.21x) | 322.98 (6.41x) |
| ZeroDuration JSON parse | 26.57 | — | — | 2137.10 (80.43x) | 284.52 (10.71x) |
| FieldMask JSON stringify | 97.29 | — | — | 1361.84 (14.00x) | 623.56 (6.41x) |
| FieldMask JSON parse | 188.73 | — | — | 2696.63 (14.29x) | 805.62 (4.27x) |
| FieldMask Escape JSON parse | 263.06 | — | — | 2759.45 (10.49x) | 944.02 (3.59x) |
| EmptyFieldMask JSON stringify | 46.03 | — | — | 939.04 (20.40x) | 175.98 (3.82x) |
| EmptyFieldMask JSON parse | 7.57 | — | — | 1444.46 (190.81x) | 152.59 (20.16x) |
| Timestamp JSON stringify | 133.34 | — | — | 1521.27 (11.41x) | 420.11 (3.15x) |
| Timestamp JSON parse | 73.59 | — | — | 2325.64 (31.60x) | 431.42 (5.86x) |
| Timestamp Escape JSON parse | 137.91 | — | — | 2404.33 (17.43x) | 594.84 (4.31x) |
| ShortFraction Timestamp JSON parse | 68.95 | — | — | 2294.42 (33.28x) | 462.71 (6.71x) |
| Micro Timestamp JSON stringify | 133.72 | — | — | 1742.46 (13.03x) | 437.34 (3.27x) |
| Micro Timestamp JSON parse | 76.76 | — | — | 1672.15 (21.78x) | 517.05 (6.74x) |
| Nano Timestamp JSON stringify | 132.86 | — | — | 1788.61 (13.46x) | 471.35 (3.55x) |
| Nano Timestamp JSON parse | 82.18 | — | — | 2300.45 (27.99x) | 468.86 (5.71x) |
| Offset Timestamp JSON parse | 83.27 | — | — | 2378.86 (28.57x) | 561.41 (6.74x) |
| PreEpoch Timestamp JSON stringify | 88.18 | — | — | 1647.11 (18.68x) | 419.36 (4.76x) |
| PreEpoch Timestamp JSON parse | 68.24 | — | — | 2310.86 (33.86x) | 508.17 (7.45x) |
| Max Timestamp JSON stringify | 105.97 | — | — | 1813.99 (17.12x) | 614.59 (5.80x) |
| Max Timestamp JSON parse | 84.37 | — | — | 1666.22 (19.75x) | 705.05 (8.36x) |
| Min Timestamp JSON stringify | 120.24 | — | — | 1625.06 (13.52x) | 728.12 (6.06x) |
| Min Timestamp JSON parse | 64.50 | — | — | 2301.61 (35.68x) | 1315.28 (20.39x) |
| Empty JSON stringify | 24.18 | — | — | 727.66 (30.09x) | 140.18 (5.80x) |
| Empty JSON parse | 79.13 | — | — | 1137.20 (14.37x) | 448.43 (5.67x) |
| Struct JSON stringify | 301.78 | — | — | 7746.26 (25.67x) | 7429.45 (24.62x) |
| Struct JSON parse | 1003.38 | — | — | 16986.30 (16.93x) | 4912.35 (4.90x) |
| Struct Escape JSON parse | 1059.22 | — | — | 17720.80 (16.73x) | 5250.81 (4.96x) |
| Struct NumberExponent JSON parse | 1004.39 | — | — | 16928.00 (16.85x) | 5029.08 (5.01x) |
| Struct Surrogate JSON parse | 406.27 | — | — | 8470.03 (20.85x) | 2547.64 (6.27x) |
| Struct KeySurrogate JSON parse | 405.12 | — | — | 8433.58 (20.82x) | 3314.62 (8.18x) |
| EmptyStruct JSON stringify | 46.21 | — | — | 1165.14 (25.21x) | 2156.31 (46.66x) |
| EmptyStruct JSON parse | 89.61 | — | — | 3678.02 (41.04x) | 2110.05 (23.55x) |
| Value JSON stringify | 305.66 | — | — | 11002.60 (36.00x) | 6655.51 (21.77x) |
| Value JSON parse | 1033.85 | — | — | 19875.50 (19.22x) | 8694.99 (8.41x) |
| Value Escape JSON parse | 1076.90 | — | — | 19635.10 (18.23x) | 14097.86 (13.09x) |
| Value NumberExponent JSON parse | 1029.03 | — | — | 12374.40 (12.03x) | 7476.11 (7.27x) |
| Value Surrogate JSON parse | 425.50 | — | — | 6910.05 (16.24x) | 1498.76 (3.52x) |
| Value KeySurrogate JSON parse | 408.84 | — | — | 10008.80 (24.48x) | 1453.21 (3.55x) |
| NullValue JSON stringify | 43.70 | — | — | 1729.80 (39.58x) | 232.01 (5.31x) |
| NullValue JSON parse | 58.46 | — | — | 3790.91 (64.85x) | 318.85 (5.45x) |
| StringScalarValue JSON stringify | 55.12 | — | — | 1865.74 (33.85x) | 274.04 (4.97x) |
| StringScalarValue JSON parse | 123.11 | — | — | 3088.03 (25.08x) | 405.00 (3.29x) |
| StringScalarValue Escape JSON parse | 134.76 | — | — | 3138.84 (23.29x) | 474.56 (3.52x) |
| StringScalarValue Surrogate JSON parse | 145.08 | — | — | 3178.05 (21.91x) | 481.61 (3.32x) |
| EmptyStringScalarValue JSON stringify | 54.15 | — | — | 1858.47 (34.32x) | 264.63 (4.89x) |
| EmptyStringScalarValue JSON parse | 70.09 | — | — | 3046.05 (43.46x) | 369.57 (5.27x) |
| NumberValue JSON stringify | 115.10 | — | — | 2356.41 (20.47x) | 332.27 (2.89x) |
| NumberValue JSON parse | 118.90 | — | — | 3342.65 (28.11x) | 392.35 (3.30x) |
| NumberValue Exponent JSON parse | 123.79 | — | — | 3376.44 (27.28x) | 409.68 (3.31x) |
| NegativeNumberValue JSON stringify | 113.87 | — | — | 2369.85 (20.81x) | 347.80 (3.05x) |
| NegativeNumberValue JSON parse | 119.69 | — | — | 3363.31 (28.10x) | 433.91 (3.63x) |
| ZeroNumberValue JSON stringify | 67.14 | — | — | 2280.72 (33.97x) | 282.95 (4.21x) |
| ZeroNumberValue JSON parse | 124.23 | — | — | 3136.62 (25.25x) | 351.18 (2.83x) |
| BoolScalarValue JSON stringify | 44.53 | — | — | 1798.17 (40.38x) | 228.13 (5.12x) |
| BoolScalarValue JSON parse | 56.60 | — | — | 2879.81 (50.88x) | 329.46 (5.82x) |
| FalseBoolScalarValue JSON stringify | 44.46 | — | — | 1792.70 (40.32x) | 234.13 (5.27x) |
| FalseBoolScalarValue JSON parse | 56.08 | — | — | 3002.33 (53.54x) | 318.01 (5.67x) |
| ListKindValue JSON stringify | 227.67 | — | — | 8328.80 (36.58x) | 2284.31 (10.03x) |
| ListKindValue JSON parse | 786.78 | — | — | 15652.80 (19.89x) | 4203.65 (5.34x) |
| ListKindValue Escape JSON parse | 819.50 | — | — | 16475.70 (20.10x) | 4285.01 (5.23x) |
| ListKindValue Surrogate JSON parse | 359.98 | — | — | 7136.17 (19.82x) | 1089.11 (3.03x) |
| EmptyStructKindValue JSON stringify | 47.61 | — | — | 2756.12 (57.89x) | 568.10 (11.93x) |
| EmptyStructKindValue JSON parse | 109.20 | — | — | 5863.45 (53.69x) | 658.08 (6.03x) |
| EmptyListKindValue JSON stringify | 46.67 | — | — | 2721.16 (58.31x) | 361.62 (7.75x) |
| EmptyListKindValue JSON parse | 149.14 | — | — | 5749.75 (38.55x) | 599.61 (4.02x) |
| ListValue JSON stringify | 219.05 | — | — | 7713.80 (35.21x) | 2225.73 (10.16x) |
| ListValue JSON parse | 762.77 | — | — | 13756.20 (18.03x) | 3552.74 (4.66x) |
| ListValue Escape JSON parse | 791.04 | — | — | 13689.60 (17.31x) | 4024.59 (5.09x) |
| ListValue Surrogate JSON parse | 341.42 | — | — | 4042.68 (11.84x) | 871.63 (2.55x) |
| EmptyListValue JSON stringify | 43.77 | — | — | 701.23 (16.02x) | 183.93 (4.20x) |
| EmptyListValue JSON parse | 133.74 | — | — | 3310.72 (24.75x) | 294.91 (2.21x) |
| DoubleValue JSON stringify | 98.47 | — | — | 1488.49 (15.12x) | 184.29 (1.87x) |
| DoubleValue JSON parse | 117.11 | — | — | 2106.05 (17.98x) | 285.20 (2.44x) |
| DoubleValue String JSON parse | 114.29 | — | — | 2016.73 (17.65x) | 373.33 (3.27x) |
| DoubleValue Exponent JSON parse | 122.74 | — | — | 1378.14 (11.23x) | 280.33 (2.28x) |
| NegativeDoubleValue JSON stringify | 98.77 | — | — | 1481.26 (15.00x) | 190.97 (1.93x) |
| NegativeDoubleValue JSON parse | 118.09 | — | — | 2110.16 (17.87x) | 291.99 (2.47x) |
| ZeroDoubleValue JSON stringify | 56.37 | — | — | 1379.23 (24.47x) | 136.85 (2.43x) |
| ZeroDoubleValue JSON parse | 119.11 | — | — | 1863.46 (15.64x) | 277.00 (2.33x) |
| DoubleValue NaN JSON stringify | 55.57 | — | — | 1011.61 (18.20x) | 120.02 (2.16x) |
| DoubleValue NaN JSON parse | 105.81 | — | — | 1706.80 (16.13x) | 259.49 (2.45x) |
| DoubleValue Infinity JSON stringify | 59.79 | — | — | 998.88 (16.71x) | 137.01 (2.29x) |
| DoubleValue Infinity JSON parse | 109.26 | — | — | 1728.17 (15.82x) | 273.52 (2.50x) |
| DoubleValue NegativeInfinity JSON stringify | 60.93 | — | — | 986.27 (16.19x) | 133.25 (2.19x) |
| DoubleValue NegativeInfinity JSON parse | 112.22 | — | — | 1748.01 (15.58x) | 287.09 (2.56x) |
| FloatValue JSON stringify | 104.29 | — | — | 1496.71 (14.35x) | 195.92 (1.88x) |
| FloatValue JSON parse | 117.39 | — | — | 2230.24 (19.00x) | 398.33 (3.39x) |
| FloatValue String JSON parse | 115.18 | — | — | 2169.87 (18.84x) | 395.23 (3.43x) |
| FloatValue Exponent JSON parse | 122.40 | — | — | 2251.00 (18.39x) | 288.17 (2.35x) |
| NegativeFloatValue JSON stringify | 104.63 | — | — | 800.06 (7.65x) | 195.22 (1.87x) |
| NegativeFloatValue JSON parse | 118.53 | — | — | 1223.00 (10.32x) | 277.91 (2.34x) |
| ZeroFloatValue JSON stringify | 55.97 | — | — | 744.06 (13.29x) | 138.93 (2.48x) |
| ZeroFloatValue JSON parse | 118.65 | — | — | 1163.83 (9.81x) | 248.54 (2.09x) |
| FloatValue NaN JSON stringify | 55.35 | — | — | 986.21 (17.82x) | 126.71 (2.29x) |
| FloatValue NaN JSON parse | 107.22 | — | — | 1690.68 (15.77x) | 271.46 (2.53x) |
| FloatValue Infinity JSON stringify | 60.47 | — | — | 968.64 (16.02x) | 143.56 (2.37x) |
| FloatValue Infinity JSON parse | 109.88 | — | — | 1687.64 (15.36x) | 266.55 (2.43x) |
| FloatValue NegativeInfinity JSON stringify | 62.09 | — | — | 967.32 (15.58x) | 125.28 (2.02x) |
| FloatValue NegativeInfinity JSON parse | 111.83 | — | — | 1704.38 (15.24x) | 275.50 (2.46x) |
| Int64Value JSON stringify | 57.15 | — | — | 998.33 (17.47x) | 264.32 (4.63x) |
| Int64Value JSON parse | 143.12 | — | — | 1956.39 (13.67x) | 451.18 (3.15x) |
| Int64Value Number JSON parse | 155.56 | — | — | 2082.57 (13.39x) | 365.75 (2.35x) |
| Int64Value Exponent JSON parse | 125.91 | — | — | 2116.92 (16.81x) | 367.21 (2.92x) |
| ZeroInt64Value JSON stringify | 46.76 | — | — | 935.75 (20.01x) | 174.98 (3.74x) |
| ZeroInt64Value JSON parse | 107.42 | — | — | 1804.35 (16.80x) | 388.21 (3.61x) |
| NegativeInt64Value JSON stringify | 56.62 | — | — | 1004.23 (17.74x) | 282.77 (4.99x) |
| NegativeInt64Value JSON parse | 144.97 | — | — | 1962.59 (13.54x) | 470.03 (3.24x) |
| MinInt64Value JSON stringify | 60.00 | — | — | 1007.13 (16.79x) | 332.51 (5.54x) |
| MinInt64Value JSON parse | 154.61 | — | — | 1992.34 (12.89x) | 507.40 (3.28x) |
| MaxInt64Value JSON stringify | 59.76 | — | — | 684.46 (11.45x) | 306.41 (5.13x) |
| MaxInt64Value JSON parse | 152.57 | — | — | 1307.65 (8.57x) | 482.36 (3.16x) |
| UInt64Value JSON stringify | 56.44 | — | — | 681.79 (12.08x) | 307.11 (5.44x) |
| UInt64Value JSON parse | 144.91 | — | — | 1235.06 (8.52x) | 473.47 (3.27x) |
| UInt64Value Number JSON parse | 154.61 | — | — | 1273.58 (8.24x) | 324.17 (2.10x) |
| UInt64Value Exponent JSON parse | 125.85 | — | — | 2086.45 (16.58x) | 449.17 (3.57x) |
| ZeroUInt64Value JSON stringify | 46.28 | — | — | 940.11 (20.31x) | 191.54 (4.14x) |
| ZeroUInt64Value JSON parse | 106.74 | — | — | 1808.11 (16.94x) | 317.34 (2.97x) |
| MaxUInt64Value JSON stringify | 59.53 | — | — | 1016.84 (17.08x) | 293.05 (4.92x) |
| MaxUInt64Value JSON parse | 158.16 | — | — | 1988.22 (12.57x) | 463.42 (2.93x) |
| Int32Value JSON stringify | 51.57 | — | — | 969.15 (18.79x) | 132.75 (2.57x) |
| Int32Value JSON parse | 138.12 | — | — | 1921.95 (13.92x) | 301.08 (2.18x) |
| Int32Value String JSON parse | 135.17 | — | — | 1803.50 (13.34x) | 387.88 (2.87x) |
| Int32Value Exponent JSON parse | 139.27 | — | — | 2105.58 (15.12x) | 367.81 (2.64x) |
| ZeroInt32Value JSON stringify | 51.37 | — | — | 614.93 (11.97x) | 126.93 (2.47x) |
| ZeroInt32Value JSON parse | 132.41 | — | — | 1883.79 (14.23x) | 269.58 (2.04x) |
| NegativeInt32Value JSON stringify | 51.10 | — | — | 965.63 (18.90x) | 153.52 (3.00x) |
| NegativeInt32Value JSON parse | 134.18 | — | — | 1918.68 (14.30x) | 301.44 (2.25x) |
| MinInt32Value JSON stringify | 52.02 | — | — | 970.66 (18.66x) | 138.06 (2.65x) |
| MinInt32Value JSON parse | 145.38 | — | — | 1930.38 (13.28x) | 339.54 (2.34x) |
| MaxInt32Value JSON stringify | 51.76 | — | — | 965.54 (18.65x) | 133.71 (2.58x) |
| MaxInt32Value JSON parse | 149.00 | — | — | 1916.76 (12.86x) | 314.95 (2.11x) |
| UInt32Value JSON stringify | 52.29 | — | — | 917.71 (17.55x) | 144.61 (2.77x) |
| UInt32Value JSON parse | 136.74 | — | — | 1878.72 (13.74x) | 312.91 (2.29x) |
| UInt32Value String JSON parse | 135.40 | — | — | 1727.96 (12.76x) | 443.12 (3.27x) |
| UInt32Value Exponent JSON parse | 139.66 | — | — | 2071.94 (14.84x) | 351.51 (2.52x) |
| ZeroUInt32Value JSON stringify | 51.15 | — | — | 630.23 (12.32x) | 130.79 (2.56x) |
| ZeroUInt32Value JSON parse | 132.43 | — | — | 1161.20 (8.77x) | 254.70 (1.92x) |
| MaxUInt32Value JSON stringify | 51.97 | — | — | 649.24 (12.49x) | 141.15 (2.72x) |
| MaxUInt32Value JSON parse | 148.12 | — | — | 1213.57 (8.19x) | 329.89 (2.23x) |
| BoolValue JSON stringify | 49.80 | — | — | 615.83 (12.37x) | 129.54 (2.60x) |
| BoolValue JSON parse | 60.57 | — | — | 1057.68 (17.46x) | 217.74 (3.59x) |
| FalseBoolValue JSON stringify | 48.82 | — | — | 609.97 (12.49x) | 124.17 (2.54x) |
| FalseBoolValue JSON parse | 60.87 | — | — | 1067.88 (17.54x) | 203.73 (3.35x) |
| StringValue JSON stringify | 63.02 | — | — | 674.68 (10.71x) | 183.11 (2.91x) |
| StringValue JSON parse | 120.99 | — | — | 1156.02 (9.55x) | 307.41 (2.54x) |
| StringValue Escape JSON parse | 137.72 | — | — | 1174.66 (8.53x) | 340.87 (2.48x) |
| StringValue Surrogate JSON parse | 142.65 | — | — | 1172.63 (8.22x) | 364.78 (2.56x) |
| EmptyStringValue JSON stringify | 55.00 | — | — | 638.44 (11.61x) | 173.29 (3.15x) |
| EmptyStringValue JSON parse | 65.39 | — | — | 1123.93 (17.19x) | 214.45 (3.28x) |
| BytesValue JSON stringify | 52.69 | — | — | 660.47 (12.54x) | 186.92 (3.55x) |
| BytesValue JSON parse | 133.48 | — | — | 1178.71 (8.83x) | 351.08 (2.63x) |
| BytesValue URL JSON parse | 151.70 | — | — | 1958.90 (12.91x) | 290.38 (1.91x) |
| BytesValue StandardBase64 JSON parse | 131.62 | — | — | 1981.11 (15.05x) | 312.87 (2.38x) |
| BytesValue Unpadded JSON parse | 132.07 | — | — | 1956.29 (14.81x) | 320.92 (2.43x) |
| EmptyBytesValue JSON stringify | 46.00 | — | — | 762.96 (16.59x) | 174.84 (3.80x) |
| EmptyBytesValue JSON parse | 67.92 | — | — | 1617.23 (23.81x) | 253.24 (3.73x) |
| TextFormat format | 263.30 | — | — | 3172.12 (12.05x) | 2405.49 (9.14x) |
| TextFormat parse | 1093.40 | — | — | 5495.05 (5.03x) | 6356.58 (5.81x) |
| packed fixed32 encode | 2.17 | 552.98 (254.83x) | 539.09 (248.43x) | 90.62 (41.76x) | 393.11 (181.16x) |
| packed fixed32 decode | 4.76 | 1062.81 (223.28x) | 1935.51 (406.62x) | 99.18 (20.84x) | 1573.11 (330.49x) |
| packed fixed64 encode | 2.01 | 575.66 (286.40x) | 566.53 (281.86x) | 154.99 (77.11x) | 407.35 (202.66x) |
| packed fixed64 decode | 4.53 | 1061.63 (234.36x) | 7952.30 (1755.47x) | 164.31 (36.27x) | 2429.53 (536.32x) |
| packed sfixed32 encode | 2.01 | 562.19 (279.70x) | 548.48 (272.88x) | 91.12 (45.33x) | 408.56 (203.26x) |
| packed sfixed32 decode | 4.53 | 1058.08 (233.57x) | 1988.25 (438.91x) | 96.00 (21.19x) | 1589.12 (350.80x) |
| packed sfixed64 encode | 2.01 | 579.03 (288.07x) | 564.97 (281.08x) | 155.53 (77.38x) | 408.68 (203.32x) |
| packed sfixed64 decode | 4.54 | 1003.31 (220.99x) | 7610.36 (1676.29x) | 161.02 (35.47x) | 2159.90 (475.75x) |
| packed float encode | 3.04 | 815.22 (268.16x) | 544.61 (179.15x) | 91.19 (30.00x) | 371.21 (122.11x) |
| packed float decode | 7.84 | 1053.17 (134.33x) | 2118.12 (270.17x) | 95.94 (12.24x) | 1723.54 (219.84x) |
| packed double encode | 2.01 | 840.40 (418.11x) | 566.71 (281.95x) | 154.92 (77.08x) | 362.90 (180.55x) |
| packed double decode | 4.53 | 989.11 (218.35x) | 2078.96 (458.93x) | 161.40 (35.63x) | 2256.64 (498.15x) |
| packed uint64 encode | 1311.75 | 4669.33 (3.56x) | 4064.30 (3.10x) | 3132.59 (2.39x) | 3529.59 (2.69x) |
| packed uint64 decode | 1792.73 | 2806.65 (1.57x) | 8874.26 (4.95x) | 2825.95 (1.58x) | 7454.32 (4.16x) |
| packed uint32 encode | 1357.67 | 3658.32 (2.69x) | 3279.00 (2.42x) | 1731.90 (1.28x) | 2947.37 (2.17x) |
| packed uint32 decode | 1295.31 | 2457.90 (1.90x) | 3468.50 (2.68x) | 1999.24 (1.54x) | 6072.31 (4.69x) |
| packed int64 encode | 1416.47 | 11074.73 (7.82x) | 6083.03 (4.29x) | 2931.83 (2.07x) | 4169.53 (2.94x) |
| packed int64 decode | 2763.80 | 3398.18 (1.23x) | 10315.69 (3.73x) | 4769.81 (1.73x) | 9119.65 (3.30x) |
| packed sint32 encode | 781.95 | 3065.06 (3.92x) | 2865.95 (3.67x) | 1545.28 (1.98x) | 3456.73 (4.42x) |
| packed sint32 decode | 952.20 | 2564.89 (2.69x) | 3237.17 (3.40x) | 1705.35 (1.79x) | 3738.59 (3.93x) |
| packed sint64 encode | 1526.15 | 4985.39 (3.27x) | 4327.78 (2.84x) | 2425.45 (1.59x) | 4175.60 (2.74x) |
| packed sint64 decode | 2041.84 | 3080.44 (1.51x) | 9852.27 (4.83x) | 2963.20 (1.45x) | 7519.25 (3.68x) |
| packed bool encode | 2.01 | 1312.61 (653.04x) | 521.35 (259.38x) | 16.36 (8.14x) | 2474.15 (1230.92x) |
| packed bool decode | 262.79 | 1746.70 (6.65x) | 2561.18 (9.75x) | 829.59 (3.16x) | 1808.33 (6.88x) |
| packed enum encode | 273.20 | 2737.46 (10.02x) | 1819.79 (6.66x) | 1094.71 (4.01x) | 2599.73 (9.52x) |
| packed enum decode | 154.71 | 1533.51 (9.91x) | 2870.96 (18.56x) | 702.25 (4.54x) | 2404.22 (15.54x) |
| large map encode | 4120.81 | 17794.10 (4.32x) | 9708.02 (2.36x) | 22445.90 (5.45x) | 202788.08 (49.21x) |
| shuffled large map deterministic binary encode | 28611.75 | — | — | 103133.00 (3.60x) | 382796.31 (13.38x) |
| large map decode | 24299.97 | 91410.92 (3.76x) | 89630.34 (3.69x) | 119506.00 (4.92x) | 275579.42 (11.34x) |
| LargeMap JSON stringify | 20948.26 | — | — | 118606.00 (5.66x) | 651036.77 (31.08x) |
| LargeMap JSON parse | 192097.13 | — | — | 843974.00 (4.39x) | 554307.73 (2.89x) |

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
