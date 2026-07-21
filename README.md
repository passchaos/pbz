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

Latest accepted comparison (`/tmp/pbz-compare-textbytes-json-final.log`,
summarized in `/tmp/pbz-summary-textbytes-json-final.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Pivoted rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 16.61 | 103.07 (6.21x) | 50.87 (3.06x) | 148.86 (8.96x) | 786.65 (47.36x) |
| binary decode | 155.71 | 250.16 (1.61x) | 231.16 (1.48x) | 403.66 (2.59x) | 842.42 (5.41x) |
| unknown fields count by number | 3.57 | — | — | 269.20 (75.41x) | — |
| deterministic binary encode | 79.09 | — | — | 217.07 (2.74x) | 1013.83 (12.82x) |
| scalarmix encode | 19.68 | 107.59 (5.47x) | 48.51 (2.46x) | 54.71 (2.78x) | 219.10 (11.13x) |
| scalarmix decode | 34.71 | 134.26 (3.87x) | 185.26 (5.34x) | 96.18 (2.77x) | 297.91 (8.58x) |
| textbytes encode | 13.74 | 90.79 (6.61x) | 33.93 (2.47x) | 151.23 (11.01x) | 146.74 (10.68x) |
| textbytes decode | 47.27 | 381.85 (8.08x) | 236.93 (5.01x) | 173.33 (3.67x) | 588.05 (12.44x) |
| TextBytes JSON stringify | 337.06 | — | — | 2319.95 (6.88x) | 2036.44 (6.04x) |
| TextBytes JSON parse | 1340.89 | — | — | 5660.00 (4.22x) | 3802.04 (2.84x) |
| largebytes encode | 17.56 | 2716.56 (154.70x) | 2690.36 (153.21x) | 2683.57 (152.82x) | 2690.39 (153.21x) |
| largebytes decode | 88.19 | 5560.90 (63.06x) | 3540.23 (40.14x) | 2760.62 (31.30x) | 18198.02 (206.35x) |
| presencemix encode | 17.26 | 55.12 (3.19x) | 27.20 (1.58x) | 56.04 (3.25x) | 224.19 (12.99x) |
| presencemix decode | 56.50 | 132.15 (2.34x) | 112.06 (1.98x) | 161.11 (2.85x) | 468.84 (8.30x) |
| PresenceMix JSON stringify | 133.77 | — | — | 3089.11 (23.09x) | 2245.09 (16.78x) |
| PresenceMix JSON parse | 1154.41 | — | — | 6258.31 (5.42x) | 2850.69 (2.47x) |
| complex encode | 49.33 | 132.76 (2.69x) | 97.08 (1.97x) | 163.60 (3.32x) | 902.55 (18.30x) |
| complex decode | 179.20 | 394.60 (2.20x) | 343.68 (1.92x) | 395.11 (2.20x) | 1263.70 (7.05x) |
| complex deterministic binary encode | 93.69 | — | — | 170.06 (1.82x) | 1106.55 (11.81x) |
| complex JSON stringify | 265.68 | — | — | 4923.91 (18.53x) | 5619.17 (21.15x) |
| complex JSON parse | 2418.10 | — | — | 12113.00 (5.01x) | 7015.47 (2.90x) |
| Complex ProtoName JSON stringify | 264.80 | — | — | 5223.56 (19.73x) | 5642.00 (21.31x) |
| Complex ProtoName JSON parse | 2434.45 | — | — | 12265.60 (5.04x) | 7207.04 (2.96x) |
| complex TextFormat format | 363.78 | — | — | 3939.14 (10.83x) | 5121.06 (14.08x) |
| complex TextFormat parse | 1772.57 | — | — | 6998.96 (3.95x) | 7937.46 (4.48x) |
| packed int32 encode | 631.69 | 3175.05 (5.03x) | 2526.96 (4.00x) | 1230.27 (1.95x) | 2844.08 (4.50x) |
| packed int32 decode | 712.41 | 1935.38 (2.72x) | 3232.98 (4.54x) | 935.81 (1.31x) | 2618.09 (3.67x) |
| JSON stringify | 157.84 | — | — | 3039.80 (19.26x) | 2134.31 (13.52x) |
| AlwaysPrint JSON stringify | 60.70 | — | — | 2649.38 (43.65x) | 1235.84 (20.36x) |
| ProtoName JSON stringify | 305.79 | — | — | 4836.81 (15.82x) | 3623.42 (11.85x) |
| EnumNumber JSON stringify | 280.61 | — | — | 4826.48 (17.20x) | 3569.16 (12.72x) |
| JSON parse | 1504.44 | — | — | 7503.07 (4.99x) | 4294.43 (2.85x) |
| MapKeySurrogate JSON parse | 432.47 | — | — | 3522.65 (8.15x) | 942.23 (2.18x) |
| NullFields JSON parse | 512.86 | — | — | 2062.66 (4.02x) | 727.64 (1.42x) |
| IgnoreUnknown JSON parse | 1201.76 | — | — | 5368.85 (4.47x) | 2325.33 (1.93x) |
| OpenEnum JSON parse | 298.11 | — | — | 3798.97 (12.74x) | 465.20 (1.56x) |
| EnumName JSON parse | 297.12 | — | — | 3834.47 (12.91x) | 441.11 (1.48x) |
| ProtoName JSON parse | 524.96 | — | — | 4034.39 (7.69x) | 1124.56 (2.14x) |
| IntExponent JSON parse | 1673.42 | — | — | 7321.90 (4.38x) | 3901.70 (2.33x) |
| StringNumber JSON parse | 1652.16 | — | — | 7090.26 (4.29x) | 4242.73 (2.57x) |
| Any WKT JSON stringify | 127.62 | — | — | 1892.55 (14.83x) | 910.20 (7.13x) |
| Any WKT JSON parse | 512.41 | — | — | 3002.58 (5.86x) | 1406.17 (2.74x) |
| Any Duration Escape WKT JSON parse | 530.74 | — | — | 3036.32 (5.72x) | 1498.39 (2.82x) |
| Any PlusDuration WKT JSON parse | 513.86 | — | — | 3019.15 (5.88x) | 1429.99 (2.78x) |
| Any ShortFractionDuration WKT JSON parse | 509.74 | — | — | 2961.64 (5.81x) | 1399.91 (2.75x) |
| Any MicroDuration WKT JSON stringify | 131.93 | — | — | 1893.46 (14.35x) | 918.02 (6.96x) |
| Any MicroDuration WKT JSON parse | 516.62 | — | — | 3009.42 (5.83x) | 1459.04 (2.82x) |
| Any NanoDuration WKT JSON stringify | 128.55 | — | — | 1925.91 (14.98x) | 940.34 (7.31x) |
| Any NanoDuration WKT JSON parse | 517.25 | — | — | 3016.18 (5.83x) | 1468.49 (2.84x) |
| Any NegativeDuration WKT JSON stringify | 133.39 | — | — | 1942.67 (14.56x) | 930.46 (6.98x) |
| Any NegativeDuration WKT JSON parse | 515.87 | — | — | 3230.90 (6.26x) | 1437.99 (2.79x) |
| Any FractionalNegativeDuration WKT JSON stringify | 121.68 | — | — | 1896.20 (15.58x) | 925.73 (7.61x) |
| Any FractionalNegativeDuration WKT JSON parse | 508.90 | — | — | 3080.38 (6.05x) | 1391.87 (2.74x) |
| Any MaxDuration WKT JSON stringify | 119.56 | — | — | 1751.90 (14.65x) | 918.34 (7.68x) |
| Any MaxDuration WKT JSON parse | 520.94 | — | — | 2969.58 (5.70x) | 1421.59 (2.73x) |
| Any MinDuration WKT JSON stringify | 118.95 | — | — | 1769.05 (14.87x) | 1010.24 (8.49x) |
| Any MinDuration WKT JSON parse | 521.13 | — | — | 3039.35 (5.83x) | 1428.34 (2.74x) |
| Any ZeroDuration WKT JSON stringify | 100.87 | — | — | 911.76 (9.04x) | 924.53 (9.17x) |
| Any ZeroDuration WKT JSON parse | 463.58 | — | — | 2263.85 (4.88x) | 1329.85 (2.87x) |
| Any FieldMask WKT JSON stringify | 222.20 | — | — | 1756.82 (7.91x) | 1372.14 (6.18x) |
| Any FieldMask WKT JSON parse | 702.52 | — | — | 3183.84 (4.53x) | 1954.42 (2.78x) |
| Any FieldMask Escape WKT JSON parse | 719.98 | — | — | 3322.52 (4.61x) | 2120.54 (2.95x) |
| Any EmptyFieldMask WKT JSON stringify | 111.36 | — | — | 933.33 (8.38x) | 737.88 (6.63x) |
| Any EmptyFieldMask WKT JSON parse | 448.21 | — | — | 2173.10 (4.85x) | 1189.66 (2.65x) |
| Any Timestamp WKT JSON stringify | 178.74 | — | — | 2046.95 (11.45x) | 974.10 (5.45x) |
| Any Timestamp WKT JSON parse | 570.64 | — | — | 3039.73 (5.33x) | 1490.25 (2.61x) |
| Any Timestamp Escape WKT JSON parse | 585.67 | — | — | 3084.30 (5.27x) | 1663.71 (2.84x) |
| Any ShortFraction Timestamp WKT JSON parse | 567.07 | — | — | 3018.87 (5.32x) | 1538.12 (2.71x) |
| Any Micro Timestamp WKT JSON stringify | 184.81 | — | — | 2035.28 (11.01x) | 978.69 (5.30x) |
| Any Micro Timestamp WKT JSON parse | 572.22 | — | — | 3028.68 (5.29x) | 1537.76 (2.69x) |
| Any Nano Timestamp WKT JSON stringify | 177.48 | — | — | 2055.13 (11.58x) | 1019.79 (5.75x) |
| Any Nano Timestamp WKT JSON parse | 576.86 | — | — | 3145.55 (5.45x) | 1531.86 (2.66x) |
| Any Offset Timestamp WKT JSON parse | 585.58 | — | — | 3049.11 (5.21x) | 1560.53 (2.66x) |
| Any PreEpoch Timestamp WKT JSON stringify | 142.66 | — | — | 1952.89 (13.69x) | 950.89 (6.67x) |
| Any PreEpoch Timestamp WKT JSON parse | 560.11 | — | — | 3052.65 (5.45x) | 1542.85 (2.75x) |
| Any Max Timestamp WKT JSON stringify | 161.22 | — | — | 2056.99 (12.76x) | 995.00 (6.17x) |
| Any Max Timestamp WKT JSON parse | 579.28 | — | — | 3097.24 (5.35x) | 1572.14 (2.71x) |
| Any Min Timestamp WKT JSON stringify | 153.96 | — | — | 1946.73 (12.64x) | 956.94 (6.22x) |
| Any Min Timestamp WKT JSON parse | 556.61 | — | — | 3035.98 (5.45x) | 1490.94 (2.68x) |
| Any Empty WKT JSON stringify | 88.64 | — | — | 926.67 (10.45x) | 634.91 (7.16x) |
| Any Empty WKT JSON parse | 338.18 | — | — | 2154.46 (6.37x) | 1238.15 (3.66x) |
| Any Struct WKT JSON stringify | 623.44 | — | — | 5855.28 (9.39x) | 5780.78 (9.27x) |
| Any Struct WKT JSON parse | 1756.67 | — | — | 11139.30 (6.34x) | 8254.71 (4.70x) |
| Any Struct Escape WKT JSON parse | 1799.77 | — | — | 11235.20 (6.24x) | 8408.21 (4.67x) |
| Any Struct NumberExponent WKT JSON parse | 1773.96 | — | — | 11116.80 (6.27x) | 8184.10 (4.61x) |
| Any Struct Surrogate WKT JSON parse | 754.20 | — | — | 6391.02 (8.47x) | 2850.38 (3.78x) |
| Any Struct KeySurrogate WKT JSON parse | 761.68 | — | — | 6277.90 (8.24x) | 2858.08 (3.75x) |
| Any EmptyStruct WKT JSON stringify | 110.82 | — | — | 910.17 (8.21x) | 870.15 (7.85x) |
| Any EmptyStruct WKT JSON parse | 442.37 | — | — | 2229.07 (5.04x) | 1409.53 (3.19x) |
| Any Value WKT JSON stringify | 656.71 | — | — | 5908.67 (9.00x) | 6100.74 (9.29x) |
| Any Value WKT JSON parse | 1815.15 | — | — | 11502.80 (6.34x) | 8472.66 (4.67x) |
| Any Value Escape WKT JSON parse | 1840.87 | — | — | 11589.60 (6.30x) | 8675.01 (4.71x) |
| Any Value NumberExponent WKT JSON parse | 1809.67 | — | — | 11440.30 (6.32x) | 8702.44 (4.81x) |
| Any Value Surrogate WKT JSON parse | 809.39 | — | — | 6573.73 (8.12x) | 3293.60 (4.07x) |
| Any Value KeySurrogate WKT JSON parse | 814.63 | — | — | 6562.97 (8.06x) | 3278.49 (4.02x) |
| Any NullValue WKT JSON stringify | 126.21 | — | — | 2260.85 (17.91x) | 873.70 (6.92x) |
| Any NullValue WKT JSON parse | 457.04 | — | — | 4072.68 (8.91x) | 1476.60 (3.23x) |
| Any StringScalarValue WKT JSON stringify | 147.10 | — | — | 2287.67 (15.55x) | 955.27 (6.49x) |
| Any StringScalarValue WKT JSON parse | 510.15 | — | — | 3632.01 (7.12x) | 1547.24 (3.03x) |
| Any StringScalarValue Escape WKT JSON parse | 525.73 | — | — | 3675.31 (6.99x) | 1616.52 (3.07x) |
| Any StringScalarValue Surrogate WKT JSON parse | 529.83 | — | — | 3667.80 (6.92x) | 1654.20 (3.12x) |
| Any EmptyStringScalarValue WKT JSON stringify | 138.56 | — | — | 2288.20 (16.51x) | 934.48 (6.74x) |
| Any EmptyStringScalarValue WKT JSON parse | 486.28 | — | — | 3630.16 (7.47x) | 1491.27 (3.07x) |
| Any NumberValue WKT JSON stringify | 177.09 | — | — | 2522.95 (14.25x) | 1015.16 (5.73x) |
| Any NumberValue WKT JSON parse | 505.70 | — | — | 3697.45 (7.31x) | 1492.44 (2.95x) |
| Any NumberValue Exponent WKT JSON parse | 502.19 | — | — | 3739.58 (7.45x) | 1512.82 (3.01x) |
| Any NegativeNumberValue WKT JSON stringify | 178.82 | — | — | 2536.24 (14.18x) | 1018.34 (5.69x) |
| Any NegativeNumberValue WKT JSON parse | 501.76 | — | — | 3727.73 (7.43x) | 1486.49 (2.96x) |
| Any ZeroNumberValue WKT JSON stringify | 139.95 | — | — | 2508.36 (17.92x) | 908.58 (6.49x) |
| Any ZeroNumberValue WKT JSON parse | 492.47 | — | — | 3685.70 (7.48x) | 1488.03 (3.02x) |
| Any BoolScalarValue WKT JSON stringify | 123.83 | — | — | 2272.99 (18.36x) | 871.63 (7.04x) |
| Any BoolScalarValue WKT JSON parse | 461.13 | — | — | 3647.93 (7.91x) | 1431.73 (3.10x) |
| Any FalseBoolScalarValue WKT JSON stringify | 123.15 | — | — | 2289.04 (18.59x) | 884.83 (7.18x) |
| Any FalseBoolScalarValue WKT JSON parse | 452.52 | — | — | 3649.36 (8.06x) | 1396.62 (3.09x) |
| Any ListKindValue WKT JSON stringify | 499.66 | — | — | 5982.56 (11.97x) | 4581.01 (9.17x) |
| Any ListKindValue WKT JSON parse | 1390.80 | — | — | 10733.80 (7.72x) | 6526.89 (4.69x) |
| Any ListKindValue Escape WKT JSON parse | 1422.24 | — | — | 11261.30 (7.92x) | 6808.21 (4.79x) |
| Any ListKindValue Surrogate WKT JSON parse | 718.90 | — | — | 4865.81 (6.77x) | 2525.03 (3.51x) |
| Any EmptyStructKindValue WKT JSON stringify | 143.81 | — | — | 2931.20 (20.38x) | 1256.24 (8.74x) |
| Any EmptyStructKindValue WKT JSON parse | 497.94 | — | — | 5459.79 (10.96x) | 1812.19 (3.64x) |
| Any EmptyListKindValue WKT JSON stringify | 140.38 | — | — | 2923.54 (20.83x) | 1094.79 (7.80x) |
| Any EmptyListKindValue WKT JSON parse | 499.14 | — | — | 4645.11 (9.31x) | 1726.58 (3.46x) |
| Any DoubleValue WKT JSON stringify | 198.51 | — | — | 1825.51 (9.20x) | 756.85 (3.81x) |
| Any DoubleValue WKT JSON parse | 523.02 | — | — | 2779.78 (5.31x) | 1311.37 (2.51x) |
| Any DoubleValue String WKT JSON parse | 534.11 | — | — | 2755.87 (5.16x) | 1404.30 (2.63x) |
| Any DoubleValue Exponent WKT JSON parse | 522.48 | — | — | 2759.45 (5.28x) | 1334.17 (2.55x) |
| Any NegativeDoubleValue WKT JSON stringify | 195.41 | — | — | 1808.37 (9.25x) | 750.87 (3.84x) |
| Any NegativeDoubleValue WKT JSON parse | 520.16 | — | — | 2764.83 (5.32x) | 1326.87 (2.55x) |
| Any ZeroDoubleValue WKT JSON stringify | 164.26 | — | — | 930.25 (5.66x) | 700.54 (4.26x) |
| Any ZeroDoubleValue WKT JSON parse | 511.97 | — | — | 2195.81 (4.29x) | 1270.66 (2.48x) |
| Any DoubleValue NaN WKT JSON stringify | 147.12 | — | — | 1582.26 (10.75x) | 660.38 (4.49x) |
| Any DoubleValue NaN WKT JSON parse | 513.49 | — | — | 2671.88 (5.20x) | 1290.25 (2.51x) |
| Any DoubleValue Infinity WKT JSON stringify | 149.71 | — | — | 1572.65 (10.50x) | 672.89 (4.49x) |
| Any DoubleValue Infinity WKT JSON parse | 517.51 | — | — | 2715.57 (5.25x) | 1283.09 (2.48x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 148.53 | — | — | 1566.68 (10.55x) | 663.80 (4.47x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 518.98 | — | — | 2669.68 (5.14x) | 1290.69 (2.49x) |
| Any FloatValue WKT JSON stringify | 187.83 | — | — | 1738.43 (9.26x) | 881.91 (4.70x) |
| Any FloatValue WKT JSON parse | 514.88 | — | — | 2708.14 (5.26x) | 1361.81 (2.64x) |
| Any FloatValue String WKT JSON parse | 526.39 | — | — | 2710.97 (5.15x) | 1451.40 (2.76x) |
| Any FloatValue Exponent WKT JSON parse | 519.90 | — | — | 2705.81 (5.20x) | 1305.51 (2.51x) |
| Any NegativeFloatValue WKT JSON stringify | 196.20 | — | — | 1734.40 (8.84x) | 740.86 (3.78x) |
| Any NegativeFloatValue WKT JSON parse | 519.37 | — | — | 2712.55 (5.22x) | 1282.39 (2.47x) |
| Any ZeroFloatValue WKT JSON stringify | 169.33 | — | — | 916.34 (5.41x) | 744.67 (4.40x) |
| Any ZeroFloatValue WKT JSON parse | 512.36 | — | — | 2150.86 (4.20x) | 1455.91 (2.84x) |
| Any FloatValue NaN WKT JSON stringify | 150.02 | — | — | 1561.23 (10.41x) | 686.09 (4.57x) |
| Any FloatValue NaN WKT JSON parse | 510.67 | — | — | 2628.33 (5.15x) | 1276.73 (2.50x) |
| Any FloatValue Infinity WKT JSON stringify | 157.25 | — | — | 1551.30 (9.87x) | 672.02 (4.27x) |
| Any FloatValue Infinity WKT JSON parse | 517.33 | — | — | 2679.20 (5.18x) | 1284.89 (2.48x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 150.33 | — | — | 1562.77 (10.40x) | 681.47 (4.53x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 517.32 | — | — | 2682.98 (5.19x) | 1263.26 (2.44x) |
| Any Int64Value WKT JSON stringify | 161.47 | — | — | 1577.39 (9.77x) | 803.11 (4.97x) |
| Any Int64Value WKT JSON parse | 543.71 | — | — | 2800.98 (5.15x) | 1534.41 (2.82x) |
| Any Int64Value Number WKT JSON parse | 539.45 | — | — | 2774.12 (5.14x) | 1403.85 (2.60x) |
| Any Int64Value Exponent WKT JSON parse | 526.91 | — | — | 2734.13 (5.19x) | 1413.73 (2.68x) |
| Any ZeroInt64Value WKT JSON stringify | 163.31 | — | — | 927.46 (5.68x) | 763.82 (4.68x) |
| Any ZeroInt64Value WKT JSON parse | 513.65 | — | — | 2169.75 (4.22x) | 1399.34 (2.72x) |
| Any NegativeInt64Value WKT JSON stringify | 167.78 | — | — | 1573.34 (9.38x) | 817.42 (4.87x) |
| Any NegativeInt64Value WKT JSON parse | 552.43 | — | — | 2825.04 (5.11x) | 1551.98 (2.81x) |
| Any MinInt64Value WKT JSON stringify | 167.59 | — | — | 1631.21 (9.73x) | 817.39 (4.88x) |
| Any MinInt64Value WKT JSON parse | 554.60 | — | — | 3030.79 (5.46x) | 1619.94 (2.92x) |
| Any MaxInt64Value WKT JSON stringify | 170.17 | — | — | 1691.84 (9.94x) | 819.29 (4.81x) |
| Any MaxInt64Value WKT JSON parse | 558.55 | — | — | 2962.10 (5.30x) | 1595.60 (2.86x) |
| Any UInt64Value WKT JSON stringify | 171.33 | — | — | 1566.20 (9.14x) | 843.31 (4.92x) |
| Any UInt64Value WKT JSON parse | 554.79 | — | — | 2820.41 (5.08x) | 1585.21 (2.86x) |
| Any UInt64Value Number WKT JSON parse | 556.94 | — | — | 2783.15 (5.00x) | 1525.06 (2.74x) |
| Any UInt64Value Exponent WKT JSON parse | 540.16 | — | — | 2728.86 (5.05x) | 1381.67 (2.56x) |
| Any ZeroUInt64Value WKT JSON stringify | 166.65 | — | — | 917.96 (5.51x) | 753.12 (4.52x) |
| Any ZeroUInt64Value WKT JSON parse | 521.89 | — | — | 2170.83 (4.16x) | 1416.82 (2.71x) |
| Any MaxUInt64Value WKT JSON stringify | 172.73 | — | — | 1571.96 (9.10x) | 818.61 (4.74x) |
| Any MaxUInt64Value WKT JSON parse | 559.90 | — | — | 2849.48 (5.09x) | 1564.24 (2.79x) |
| Any Int32Value WKT JSON stringify | 169.86 | — | — | 1558.06 (9.17x) | 715.72 (4.21x) |
| Any Int32Value WKT JSON parse | 528.79 | — | — | 2684.04 (5.08x) | 1357.21 (2.57x) |
| Any Int32Value String WKT JSON parse | 540.76 | — | — | 2690.36 (4.98x) | 1455.33 (2.69x) |
| Any Int32Value Exponent WKT JSON parse | 538.29 | — | — | 2717.17 (5.05x) | 1385.91 (2.57x) |
| Any ZeroInt32Value WKT JSON stringify | 171.17 | — | — | 915.70 (5.35x) | 665.45 (3.89x) |
| Any ZeroInt32Value WKT JSON parse | 521.37 | — | — | 2153.80 (4.13x) | 1286.99 (2.47x) |
| Any NegativeInt32Value WKT JSON stringify | 171.99 | — | — | 1555.22 (9.04x) | 699.34 (4.07x) |
| Any NegativeInt32Value WKT JSON parse | 526.31 | — | — | 2710.82 (5.15x) | 1358.20 (2.58x) |
| Any MinInt32Value WKT JSON stringify | 179.43 | — | — | 1555.02 (8.67x) | 698.16 (3.89x) |
| Any MinInt32Value WKT JSON parse | 534.69 | — | — | 2713.15 (5.07x) | 1386.98 (2.59x) |
| Any MaxInt32Value WKT JSON stringify | 168.40 | — | — | 1548.17 (9.19x) | 696.54 (4.14x) |
| Any MaxInt32Value WKT JSON parse | 533.03 | — | — | 2691.71 (5.05x) | 1330.66 (2.50x) |
| Any UInt32Value WKT JSON stringify | 175.84 | — | — | 1549.13 (8.81x) | 699.05 (3.98x) |
| Any UInt32Value WKT JSON parse | 533.39 | — | — | 2683.39 (5.03x) | 1346.41 (2.52x) |
| Any UInt32Value String WKT JSON parse | 541.41 | — | — | 2694.94 (4.98x) | 1462.50 (2.70x) |
| Any UInt32Value Exponent WKT JSON parse | 543.43 | — | — | 2723.77 (5.01x) | 1416.72 (2.61x) |
| Any ZeroUInt32Value WKT JSON stringify | 180.36 | — | — | 916.56 (5.08x) | 670.67 (3.72x) |
| Any ZeroUInt32Value WKT JSON parse | 527.74 | — | — | 2157.95 (4.09x) | 1283.42 (2.43x) |
| Any MaxUInt32Value WKT JSON stringify | 173.85 | — | — | 1557.66 (8.96x) | 687.72 (3.96x) |
| Any MaxUInt32Value WKT JSON parse | 541.74 | — | — | 2690.75 (4.97x) | 1302.42 (2.40x) |
| Any BoolValue WKT JSON stringify | 160.63 | — | — | 1529.86 (9.52x) | 649.99 (4.05x) |
| Any BoolValue WKT JSON parse | 486.21 | — | — | 2604.93 (5.36x) | 1186.11 (2.44x) |
| Any FalseBoolValue WKT JSON stringify | 167.42 | — | — | 915.64 (5.47x) | 660.98 (3.95x) |
| Any FalseBoolValue WKT JSON parse | 484.93 | — | — | 2150.21 (4.43x) | 1181.97 (2.44x) |
| Any StringValue WKT JSON stringify | 189.60 | — | — | 1632.53 (8.61x) | 750.39 (3.96x) |
| Any StringValue WKT JSON parse | 549.88 | — | — | 2804.24 (5.10x) | 1307.48 (2.38x) |
| Any StringValue Escape WKT JSON parse | 549.22 | — | — | 2703.36 (4.92x) | 1391.54 (2.53x) |
| Any StringValue Surrogate WKT JSON parse | 557.29 | — | — | 2691.70 (4.83x) | 1412.02 (2.53x) |
| Any EmptyStringValue WKT JSON stringify | 182.80 | — | — | 917.75 (5.02x) | 692.31 (3.79x) |
| Any EmptyStringValue WKT JSON parse | 520.10 | — | — | 2164.95 (4.16x) | 1210.89 (2.33x) |
| Any BytesValue WKT JSON stringify | 182.86 | — | — | 1681.69 (9.20x) | 805.58 (4.41x) |
| Any BytesValue WKT JSON parse | 567.29 | — | — | 2843.76 (5.01x) | 1314.92 (2.32x) |
| Any BytesValue URL WKT JSON parse | 588.27 | — | — | 2679.08 (4.55x) | 1317.56 (2.24x) |
| Any BytesValue StandardBase64 WKT JSON parse | 573.41 | — | — | 2708.89 (4.72x) | 1352.21 (2.36x) |
| Any BytesValue Unpadded WKT JSON parse | 573.19 | — | — | 2679.00 (4.67x) | 1350.29 (2.36x) |
| Any EmptyBytesValue WKT JSON stringify | 176.10 | — | — | 914.58 (5.19x) | 722.57 (4.10x) |
| Any EmptyBytesValue WKT JSON parse | 532.00 | — | — | 2148.01 (4.04x) | 1404.06 (2.64x) |
| Nested Any WKT JSON stringify | 280.20 | — | — | 2505.37 (8.94x) | 1339.52 (4.78x) |
| Nested Any WKT JSON parse | 852.94 | — | — | 4305.99 (5.05x) | 2616.35 (3.07x) |
| Duration JSON stringify | 57.41 | — | — | 960.19 (16.73x) | 342.59 (5.97x) |
| Duration JSON parse | 16.84 | — | — | 1465.50 (87.02x) | 355.39 (21.10x) |
| Duration Escape JSON parse | 39.73 | — | — | 1562.20 (39.32x) | 397.46 (10.00x) |
| PlusDuration JSON parse | 17.82 | — | — | 1471.45 (82.57x) | 368.66 (20.69x) |
| ShortFractionDuration JSON parse | 13.96 | — | — | 1441.34 (103.25x) | 363.34 (26.03x) |
| MicroDuration JSON stringify | 59.08 | — | — | 977.47 (16.54x) | 358.55 (6.07x) |
| MicroDuration JSON parse | 20.44 | — | — | 1475.33 (72.18x) | 363.84 (17.80x) |
| NanoDuration JSON stringify | 57.50 | — | — | 1023.99 (17.81x) | 383.06 (6.66x) |
| NanoDuration JSON parse | 23.69 | — | — | 1573.81 (66.43x) | 369.26 (15.59x) |
| NegativeDuration JSON stringify | 59.67 | — | — | 1013.30 (16.98x) | 377.96 (6.33x) |
| NegativeDuration JSON parse | 18.08 | — | — | 1605.92 (88.82x) | 364.54 (20.16x) |
| FractionalNegativeDuration JSON stringify | 57.85 | — | — | 1018.02 (17.60x) | 404.61 (6.99x) |
| FractionalNegativeDuration JSON parse | 17.07 | — | — | 1557.70 (91.25x) | 360.82 (21.14x) |
| MaxDuration JSON stringify | 49.19 | — | — | 894.63 (18.19x) | 390.40 (7.94x) |
| MaxDuration JSON parse | 31.72 | — | — | 1453.58 (45.83x) | 375.23 (11.83x) |
| MinDuration JSON stringify | 49.42 | — | — | 913.30 (18.48x) | 475.15 (9.61x) |
| MinDuration JSON parse | 32.13 | — | — | 1546.60 (48.14x) | 389.37 (12.12x) |
| ZeroDuration JSON stringify | 44.37 | — | — | 852.52 (19.21x) | 330.86 (7.46x) |
| ZeroDuration JSON parse | 14.19 | — | — | 1480.60 (104.34x) | 281.17 (19.81x) |
| FieldMask JSON stringify | 75.83 | — | — | 933.27 (12.31x) | 624.50 (8.24x) |
| FieldMask JSON parse | 140.69 | — | — | 1684.08 (11.97x) | 821.56 (5.84x) |
| FieldMask Escape JSON parse | 193.71 | — | — | 1728.46 (8.92x) | 910.01 (4.70x) |
| EmptyFieldMask JSON stringify | 40.91 | — | — | 621.41 (15.19x) | 178.44 (4.36x) |
| EmptyFieldMask JSON parse | 4.78 | — | — | 988.29 (206.76x) | 154.96 (32.42x) |
| Timestamp JSON stringify | 96.34 | — | — | 1151.84 (11.96x) | 429.92 (4.46x) |
| Timestamp JSON parse | 45.23 | — | — | 1522.23 (33.66x) | 417.65 (9.23x) |
| Timestamp Escape JSON parse | 81.13 | — | — | 1557.95 (19.20x) | 488.84 (6.03x) |
| ShortFraction Timestamp JSON parse | 43.54 | — | — | 1523.54 (34.99x) | 432.83 (9.94x) |
| Micro Timestamp JSON stringify | 96.49 | — | — | 1158.67 (12.01x) | 399.22 (4.14x) |
| Micro Timestamp JSON parse | 47.38 | — | — | 1643.25 (34.68x) | 431.90 (9.12x) |
| Nano Timestamp JSON stringify | 103.72 | — | — | 1879.81 (18.12x) | 410.69 (3.96x) |
| Nano Timestamp JSON parse | 50.59 | — | — | 2150.41 (42.51x) | 435.45 (8.61x) |
| Offset Timestamp JSON parse | 54.83 | — | — | 2218.81 (40.47x) | 457.95 (8.35x) |
| PreEpoch Timestamp JSON stringify | 66.46 | — | — | 1204.55 (18.12x) | 388.90 (5.85x) |
| PreEpoch Timestamp JSON parse | 43.33 | — | — | 1493.87 (34.48x) | 419.20 (9.67x) |
| Max Timestamp JSON stringify | 78.68 | — | — | 1217.06 (15.47x) | 404.17 (5.14x) |
| Max Timestamp JSON parse | 51.08 | — | — | 1557.03 (30.48x) | 428.84 (8.40x) |
| Min Timestamp JSON stringify | 79.91 | — | — | 1056.58 (13.22x) | 378.77 (4.74x) |
| Min Timestamp JSON parse | 40.92 | — | — | 1469.45 (35.91x) | 396.49 (9.69x) |
| Empty JSON stringify | 20.61 | — | — | 495.64 (24.05x) | 75.14 (3.65x) |
| Empty JSON parse | 67.48 | — | — | 727.40 (10.78x) | 185.62 (2.75x) |
| Struct JSON stringify | 173.56 | — | — | 5767.88 (33.23x) | 2846.02 (16.40x) |
| Struct JSON parse | 854.69 | — | — | 10958.30 (12.82x) | 4220.23 (4.94x) |
| Struct Escape JSON parse | 891.15 | — | — | 11072.40 (12.42x) | 4468.93 (5.01x) |
| Struct NumberExponent JSON parse | 849.94 | — | — | 10981.00 (12.92x) | 4374.46 (5.15x) |
| Struct Surrogate JSON parse | 371.13 | — | — | 4841.78 (13.05x) | 1053.01 (2.84x) |
| Struct KeySurrogate JSON parse | 370.60 | — | — | 4793.95 (12.94x) | 1077.77 (2.91x) |
| EmptyStruct JSON stringify | 40.73 | — | — | 701.69 (17.23x) | 328.00 (8.05x) |
| EmptyStruct JSON parse | 87.67 | — | — | 2044.16 (23.32x) | 334.54 (3.82x) |
| Value JSON stringify | 188.76 | — | — | 6622.12 (35.08x) | 3067.88 (16.25x) |
| Value JSON parse | 879.64 | — | — | 12232.50 (13.91x) | 4525.41 (5.14x) |
| Value Escape JSON parse | 922.78 | — | — | 12465.40 (13.51x) | 4817.33 (5.22x) |
| Value NumberExponent JSON parse | 874.38 | — | — | 12444.40 (14.23x) | 4543.15 (5.20x) |
| Value Surrogate JSON parse | 397.15 | — | — | 12548.60 (31.60x) | 1315.41 (3.31x) |
| Value KeySurrogate JSON parse | 395.99 | — | — | 10379.50 (26.21x) | 1343.90 (3.39x) |
| NullValue JSON stringify | 40.31 | — | — | 1998.41 (49.58x) | 232.09 (5.76x) |
| NullValue JSON parse | 70.31 | — | — | 3813.35 (54.24x) | 332.48 (4.73x) |
| StringScalarValue JSON stringify | 47.44 | — | — | 2035.17 (42.90x) | 318.43 (6.71x) |
| StringScalarValue JSON parse | 139.83 | — | — | 3498.88 (25.02x) | 384.59 (2.75x) |
| StringScalarValue Escape JSON parse | 150.62 | — | — | 3277.00 (21.76x) | 442.11 (2.94x) |
| StringScalarValue Surrogate JSON parse | 148.94 | — | — | 4467.91 (30.00x) | 458.23 (3.08x) |
| EmptyStringScalarValue JSON stringify | 45.39 | — | — | 2653.55 (58.46x) | 266.53 (5.87x) |
| EmptyStringScalarValue JSON parse | 87.81 | — | — | 4293.55 (48.90x) | 332.72 (3.79x) |
| NumberValue JSON stringify | 73.38 | — | — | 3320.19 (45.25x) | 331.83 (4.52x) |
| NumberValue JSON parse | 133.53 | — | — | 2616.28 (19.59x) | 383.14 (2.87x) |
| NumberValue Exponent JSON parse | 136.50 | — | — | 2235.50 (16.38x) | 374.39 (2.74x) |
| NegativeNumberValue JSON stringify | 73.89 | — | — | 1593.37 (21.56x) | 327.52 (4.43x) |
| NegativeNumberValue JSON parse | 134.08 | — | — | 2224.25 (16.59x) | 374.64 (2.79x) |
| ZeroNumberValue JSON stringify | 50.93 | — | — | 1573.07 (30.89x) | 275.26 (5.40x) |
| ZeroNumberValue JSON parse | 130.88 | — | — | 2179.86 (16.66x) | 363.76 (2.78x) |
| BoolScalarValue JSON stringify | 40.24 | — | — | 1371.43 (34.08x) | 229.80 (5.71x) |
| BoolScalarValue JSON parse | 70.27 | — | — | 2283.92 (32.50x) | 314.12 (4.47x) |
| FalseBoolScalarValue JSON stringify | 40.12 | — | — | 1456.11 (36.29x) | 233.53 (5.82x) |
| FalseBoolScalarValue JSON parse | 70.67 | — | — | 2221.94 (31.44x) | 302.27 (4.28x) |
| ListKindValue JSON stringify | 139.40 | — | — | 6750.16 (48.42x) | 2227.86 (15.98x) |
| ListKindValue JSON parse | 679.24 | — | — | 11280.60 (16.61x) | 3712.39 (5.47x) |
| ListKindValue Escape JSON parse | 701.77 | — | — | 16682.00 (23.77x) | 3882.98 (5.53x) |
| ListKindValue Surrogate JSON parse | 323.09 | — | — | 6568.63 (20.33x) | 1109.98 (3.44x) |
| EmptyStructKindValue JSON stringify | 42.19 | — | — | 2028.94 (48.09x) | 496.48 (11.77x) |
| EmptyStructKindValue JSON parse | 110.36 | — | — | 4276.07 (38.75x) | 606.75 (5.50x) |
| EmptyListKindValue JSON stringify | 41.11 | — | — | 3816.73 (92.84x) | 365.18 (8.88x) |
| EmptyListKindValue JSON parse | 151.41 | — | — | 4375.35 (28.90x) | 595.80 (3.94x) |
| ListValue JSON stringify | 143.93 | — | — | 4771.68 (33.15x) | 2083.61 (14.48x) |
| ListValue JSON parse | 700.49 | — | — | 8647.14 (12.34x) | 3571.85 (5.10x) |
| ListValue Escape JSON parse | 724.32 | — | — | 8937.29 (12.34x) | 3701.42 (5.11x) |
| ListValue Surrogate JSON parse | 309.66 | — | — | 3131.02 (10.11x) | 911.83 (2.94x) |
| EmptyListValue JSON stringify | 39.96 | — | — | 703.52 (17.61x) | 164.69 (4.12x) |
| EmptyListValue JSON parse | 125.52 | — | — | 2280.61 (18.17x) | 283.79 (2.26x) |
| DoubleValue JSON stringify | 67.90 | — | — | 852.68 (12.56x) | 194.79 (2.87x) |
| DoubleValue JSON parse | 112.68 | — | — | 1248.63 (11.08x) | 268.05 (2.38x) |
| DoubleValue String JSON parse | 112.77 | — | — | 1182.40 (10.49x) | 352.56 (3.13x) |
| DoubleValue Exponent JSON parse | 114.34 | — | — | 1260.35 (11.02x) | 273.34 (2.39x) |
| NegativeDoubleValue JSON stringify | 67.41 | — | — | 851.52 (12.63x) | 198.94 (2.95x) |
| NegativeDoubleValue JSON parse | 113.68 | — | — | 1238.39 (10.89x) | 265.20 (2.33x) |
| ZeroDoubleValue JSON stringify | 47.52 | — | — | 786.38 (16.55x) | 134.85 (2.84x) |
| ZeroDoubleValue JSON parse | 109.19 | — | — | 1158.22 (10.61x) | 251.03 (2.30x) |
| DoubleValue NaN JSON stringify | 45.93 | — | — | 656.61 (14.30x) | 121.76 (2.65x) |
| DoubleValue NaN JSON parse | 106.87 | — | — | 1100.25 (10.30x) | 251.26 (2.35x) |
| DoubleValue Infinity JSON stringify | 47.72 | — | — | 651.81 (13.66x) | 116.69 (2.45x) |
| DoubleValue Infinity JSON parse | 107.18 | — | — | 1105.79 (10.32x) | 260.36 (2.43x) |
| DoubleValue NegativeInfinity JSON stringify | 47.92 | — | — | 644.15 (13.44x) | 125.32 (2.62x) |
| DoubleValue NegativeInfinity JSON parse | 108.82 | — | — | 1107.51 (10.18x) | 254.08 (2.33x) |
| FloatValue JSON stringify | 71.63 | — | — | 820.49 (11.45x) | 186.11 (2.60x) |
| FloatValue JSON parse | 112.59 | — | — | 1218.82 (10.83x) | 278.18 (2.47x) |
| FloatValue String JSON parse | 110.38 | — | — | 1157.39 (10.49x) | 344.73 (3.12x) |
| FloatValue Exponent JSON parse | 114.46 | — | — | 1230.57 (10.75x) | 277.20 (2.42x) |
| NegativeFloatValue JSON stringify | 70.62 | — | — | 821.33 (11.63x) | 189.71 (2.69x) |
| NegativeFloatValue JSON parse | 112.77 | — | — | 1221.45 (10.83x) | 266.89 (2.37x) |
| ZeroFloatValue JSON stringify | 47.92 | — | — | 755.86 (15.77x) | 152.09 (3.17x) |
| ZeroFloatValue JSON parse | 108.75 | — | — | 1150.93 (10.58x) | 244.90 (2.25x) |
| FloatValue NaN JSON stringify | 46.43 | — | — | 652.26 (14.05x) | 121.22 (2.61x) |
| FloatValue NaN JSON parse | 105.08 | — | — | 1078.88 (10.27x) | 251.33 (2.39x) |
| FloatValue Infinity JSON stringify | 47.52 | — | — | 652.52 (13.73x) | 119.53 (2.52x) |
| FloatValue Infinity JSON parse | 106.38 | — | — | 1100.28 (10.34x) | 252.22 (2.37x) |
| FloatValue NegativeInfinity JSON stringify | 47.66 | — | — | 649.48 (13.63x) | 118.39 (2.48x) |
| FloatValue NegativeInfinity JSON parse | 107.93 | — | — | 1117.74 (10.36x) | 261.43 (2.42x) |
| Int64Value JSON stringify | 50.35 | — | — | 692.19 (13.75x) | 265.11 (5.27x) |
| Int64Value JSON parse | 126.41 | — | — | 1271.24 (10.06x) | 429.75 (3.40x) |
| Int64Value Number JSON parse | 126.54 | — | — | 1322.42 (10.45x) | 334.21 (2.64x) |
| Int64Value Exponent JSON parse | 117.02 | — | — | 1262.44 (10.79x) | 331.28 (2.83x) |
| ZeroInt64Value JSON stringify | 41.44 | — | — | 613.20 (14.80x) | 187.16 (4.52x) |
| ZeroInt64Value JSON parse | 106.24 | — | — | 1107.65 (10.43x) | 319.59 (3.01x) |
| NegativeInt64Value JSON stringify | 48.81 | — | — | 675.31 (13.84x) | 270.30 (5.54x) |
| NegativeInt64Value JSON parse | 126.33 | — | — | 1215.81 (9.62x) | 450.30 (3.56x) |
| MinInt64Value JSON stringify | 49.67 | — | — | 680.26 (13.70x) | 277.24 (5.58x) |
| MinInt64Value JSON parse | 133.92 | — | — | 1298.38 (9.70x) | 471.02 (3.52x) |
| MaxInt64Value JSON stringify | 49.94 | — | — | 680.01 (13.62x) | 284.19 (5.69x) |
| MaxInt64Value JSON parse | 132.98 | — | — | 1269.37 (9.55x) | 450.07 (3.38x) |
| UInt64Value JSON stringify | 50.51 | — | — | 675.94 (13.38x) | 273.96 (5.42x) |
| UInt64Value JSON parse | 125.92 | — | — | 1230.42 (9.77x) | 439.80 (3.49x) |
| UInt64Value Number JSON parse | 126.66 | — | — | 1314.68 (10.38x) | 329.00 (2.60x) |
| UInt64Value Exponent JSON parse | 116.97 | — | — | 1227.72 (10.50x) | 329.95 (2.82x) |
| ZeroUInt64Value JSON stringify | 41.70 | — | — | 613.50 (14.71x) | 185.24 (4.44x) |
| ZeroUInt64Value JSON parse | 105.54 | — | — | 1101.12 (10.43x) | 316.14 (3.00x) |
| MaxUInt64Value JSON stringify | 50.39 | — | — | 684.50 (13.58x) | 283.89 (5.63x) |
| MaxUInt64Value JSON parse | 137.76 | — | — | 1261.37 (9.16x) | 457.34 (3.32x) |
| Int32Value JSON stringify | 46.19 | — | — | 646.92 (14.01x) | 136.18 (2.95x) |
| Int32Value JSON parse | 137.91 | — | — | 1189.35 (8.62x) | 291.32 (2.11x) |
| Int32Value String JSON parse | 143.07 | — | — | 1135.46 (7.94x) | 383.96 (2.68x) |
| Int32Value Exponent JSON parse | 142.20 | — | — | 1236.37 (8.69x) | 331.60 (2.33x) |
| ZeroInt32Value JSON stringify | 46.03 | — | — | 628.83 (13.66x) | 130.18 (2.83x) |
| ZeroInt32Value JSON parse | 132.68 | — | — | 1151.77 (8.68x) | 251.60 (1.90x) |
| NegativeInt32Value JSON stringify | 46.09 | — | — | 650.04 (14.10x) | 132.83 (2.88x) |
| NegativeInt32Value JSON parse | 137.88 | — | — | 1192.10 (8.65x) | 301.93 (2.19x) |
| MinInt32Value JSON stringify | 46.65 | — | — | 651.82 (13.97x) | 136.52 (2.93x) |
| MinInt32Value JSON parse | 143.17 | — | — | 1212.36 (8.47x) | 326.37 (2.28x) |
| MaxInt32Value JSON stringify | 46.99 | — | — | 650.12 (13.84x) | 135.09 (2.87x) |
| MaxInt32Value JSON parse | 143.27 | — | — | 1210.66 (8.45x) | 313.43 (2.19x) |
| UInt32Value JSON stringify | 46.00 | — | — | 627.83 (13.65x) | 131.83 (2.87x) |
| UInt32Value JSON parse | 137.49 | — | — | 1198.78 (8.72x) | 290.89 (2.12x) |
| UInt32Value String JSON parse | 143.24 | — | — | 1137.85 (7.94x) | 399.54 (2.79x) |
| UInt32Value Exponent JSON parse | 142.02 | — | — | 1234.64 (8.69x) | 350.57 (2.47x) |
| ZeroUInt32Value JSON stringify | 45.93 | — | — | 612.18 (13.33x) | 127.98 (2.79x) |
| ZeroUInt32Value JSON parse | 132.80 | — | — | 1166.31 (8.78x) | 236.98 (1.78x) |
| MaxUInt32Value JSON stringify | 46.42 | — | — | 628.22 (13.53x) | 134.50 (2.90x) |
| MaxUInt32Value JSON parse | 143.58 | — | — | 1212.12 (8.44x) | 310.17 (2.16x) |
| BoolValue JSON stringify | 44.54 | — | — | 622.07 (13.97x) | 115.85 (2.60x) |
| BoolValue JSON parse | 59.83 | — | — | 1055.72 (17.65x) | 192.63 (3.22x) |
| FalseBoolValue JSON stringify | 44.69 | — | — | 610.50 (13.66x) | 118.80 (2.66x) |
| FalseBoolValue JSON parse | 60.48 | — | — | 1061.27 (17.55x) | 196.61 (3.25x) |
| StringValue JSON stringify | 51.37 | — | — | 665.41 (12.95x) | 164.28 (3.20x) |
| StringValue JSON parse | 138.67 | — | — | 1150.96 (8.30x) | 270.71 (1.95x) |
| StringValue Escape JSON parse | 147.61 | — | — | 1182.19 (8.01x) | 330.70 (2.24x) |
| StringValue Surrogate JSON parse | 146.20 | — | — | 1179.38 (8.07x) | 328.55 (2.25x) |
| EmptyStringValue JSON stringify | 48.46 | — | — | 623.79 (12.87x) | 166.59 (3.44x) |
| EmptyStringValue JSON parse | 72.67 | — | — | 1117.96 (15.38x) | 201.91 (2.78x) |
| BytesValue JSON stringify | 54.12 | — | — | 672.06 (12.42x) | 179.09 (3.31x) |
| BytesValue JSON parse | 125.01 | — | — | 1173.69 (9.39x) | 311.48 (2.49x) |
| BytesValue URL JSON parse | 141.26 | — | — | 1167.46 (8.26x) | 284.55 (2.01x) |
| BytesValue StandardBase64 JSON parse | 123.43 | — | — | 1185.51 (9.60x) | 293.73 (2.38x) |
| BytesValue Unpadded JSON parse | 122.46 | — | — | 1162.24 (9.49x) | 296.27 (2.42x) |
| EmptyBytesValue JSON stringify | 44.66 | — | — | 648.88 (14.53x) | 177.41 (3.97x) |
| EmptyBytesValue JSON parse | 67.99 | — | — | 1134.48 (16.69x) | 247.13 (3.63x) |
| TextFormat format | 192.88 | — | — | 2564.10 (13.29x) | 2272.18 (11.78x) |
| TextFormat parse | 725.39 | — | — | 4992.18 (6.88x) | 6378.28 (8.79x) |
| packed fixed32 encode | 2.00 | 574.00 (287.00x) | 566.10 (283.05x) | 43.62 (21.81x) | 393.49 (196.75x) |
| packed fixed32 decode | 4.53 | 1040.84 (229.77x) | 1936.87 (427.57x) | 50.11 (11.06x) | 1329.62 (293.51x) |
| packed fixed64 encode | 2.01 | 581.09 (289.10x) | 565.31 (281.25x) | 75.68 (37.65x) | 423.93 (210.91x) |
| packed fixed64 decode | 4.54 | 1065.19 (234.62x) | 7949.13 (1750.91x) | 80.43 (17.72x) | 1987.55 (437.79x) |
| packed sfixed32 encode | 2.01 | 574.62 (285.88x) | 543.76 (270.53x) | 44.05 (21.92x) | 392.24 (195.14x) |
| packed sfixed32 decode | 4.54 | 1104.88 (243.37x) | 1917.58 (422.37x) | 49.35 (10.87x) | 1313.63 (289.35x) |
| packed sfixed64 encode | 2.01 | 591.59 (294.32x) | 563.70 (280.45x) | 75.82 (37.72x) | 393.45 (195.75x) |
| packed sfixed64 decode | 4.53 | 1035.58 (228.60x) | 7994.16 (1764.72x) | 80.00 (17.66x) | 1820.38 (401.85x) |
| packed float encode | 2.00 | 823.22 (411.61x) | 543.84 (271.92x) | 43.80 (21.90x) | 357.44 (178.72x) |
| packed float decode | 4.54 | 1130.30 (248.96x) | 2094.62 (461.37x) | 49.20 (10.84x) | 1580.62 (348.15x) |
| packed double encode | 2.01 | 869.90 (432.79x) | 563.89 (280.54x) | 75.96 (37.79x) | 360.63 (179.42x) |
| packed double decode | 4.51 | 1005.06 (222.85x) | 2045.97 (453.65x) | 79.97 (17.73x) | 1870.68 (414.78x) |
| packed uint64 encode | 1293.61 | 4741.88 (3.67x) | 4037.12 (3.12x) | 2163.60 (1.67x) | 3581.56 (2.77x) |
| packed uint64 decode | 1783.42 | 2791.95 (1.57x) | 8858.23 (4.97x) | 2803.60 (1.57x) | 19179.90 (10.75x) |
| packed uint32 encode | 925.16 | 3689.60 (3.99x) | 3523.77 (3.81x) | 1727.41 (1.87x) | 3554.96 (3.84x) |
| packed uint32 decode | 1322.76 | 2443.84 (1.85x) | 3260.85 (2.47x) | 1996.72 (1.51x) | 5266.62 (3.98x) |
| packed int64 encode | 1398.92 | 11258.26 (8.05x) | 6083.69 (4.35x) | 2907.59 (2.08x) | 4406.73 (3.15x) |
| packed int64 decode | 2770.72 | 3408.25 (1.23x) | 10283.21 (3.71x) | 4768.09 (1.72x) | 8174.90 (2.95x) |
| packed sint32 encode | 845.83 | 3148.96 (3.72x) | 2860.35 (3.38x) | 1541.92 (1.82x) | 3474.87 (4.11x) |
| packed sint32 decode | 952.12 | 2569.90 (2.70x) | 3215.35 (3.38x) | 1146.29 (1.20x) | 3019.26 (3.17x) |
| packed sint64 encode | 1435.19 | 5077.48 (3.54x) | 4320.57 (3.01x) | 2444.39 (1.70x) | 4151.74 (2.89x) |
| packed sint64 decode | 2040.10 | 3121.82 (1.53x) | 9685.80 (4.75x) | 2934.88 (1.44x) | 6508.17 (3.19x) |
| packed bool encode | 2.02 | 1328.47 (657.66x) | 542.46 (268.54x) | 16.00 (7.92x) | 2561.84 (1268.24x) |
| packed bool decode | 262.90 | 1533.43 (5.83x) | 2550.00 (9.70x) | 812.37 (3.09x) | 1598.44 (6.08x) |
| packed enum encode | 276.67 | 2715.83 (9.82x) | 1819.25 (6.58x) | 1085.66 (3.92x) | 2496.17 (9.02x) |
| packed enum decode | 182.72 | 1915.71 (10.48x) | 2857.90 (15.64x) | 693.27 (3.79x) | 1999.38 (10.94x) |
| large map encode | 4113.47 | 20877.38 (5.08x) | 10093.60 (2.45x) | 21067.40 (5.12x) | 188505.52 (45.83x) |
| shuffled large map deterministic binary encode | 27913.34 | — | — | 86000.20 (3.08x) | 362754.46 (13.00x) |
| large map decode | 24916.86 | 93705.23 (3.76x) | 91347.26 (3.67x) | 88156.40 (3.54x) | 267352.06 (10.73x) |

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
