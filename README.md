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

Latest accepted comparison (`/tmp/pbz-compare-bytes-standard-base64-json-final.log`,
summarized in `/tmp/pbz-summary-bytes-standard-base64-json-final.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 20.30 | 114.19 (5.63x) | 54.84 (2.70x) | 99.08 (4.88x) | 813.91 (40.09x) |
| binary decode | 164.03 | 252.36 (1.54x) | 236.25 (1.44x) | 204.68 (1.25x) | 907.50 (5.53x) |
| unknown fields count by number | 3.64 | — | — | 161.85 (44.46x) | — |
| deterministic binary encode | 55.48 | — | — | 126.69 (2.28x) | 1136.58 (20.49x) |
| scalarmix encode | 20.61 | 103.18 (5.01x) | 80.33 (3.90x) | 30.62 (1.49x) | 212.03 (10.29x) |
| scalarmix decode | 39.84 | 133.46 (3.35x) | 260.07 (6.53x) | 87.08 (2.19x) | 307.73 (7.72x) |
| textbytes encode | 13.53 | 86.12 (6.37x) | 44.93 (3.32x) | 118.07 (8.73x) | 154.00 (11.38x) |
| textbytes decode | 49.08 | 380.15 (7.75x) | 238.62 (4.86x) | 170.98 (3.48x) | 675.36 (13.76x) |
| largebytes encode | 17.54 | 2704.00 (154.16x) | 2680.34 (152.81x) | 2729.08 (155.59x) | 2700.96 (153.99x) |
| largebytes decode | 87.88 | 5563.45 (63.31x) | 3019.35 (34.36x) | 2757.92 (31.38x) | 21567.36 (245.42x) |
| presencemix encode | 19.54 | 55.84 (2.86x) | 28.38 (1.45x) | 56.77 (2.91x) | 230.29 (11.79x) |
| presencemix decode | 57.85 | 135.02 (2.33x) | 108.94 (1.88x) | 248.18 (4.29x) | 436.00 (7.54x) |
| complex encode | 54.14 | 141.52 (2.61x) | 124.98 (2.31x) | 172.15 (3.18x) | 946.77 (17.49x) |
| complex decode | 168.92 | 396.55 (2.35x) | 522.27 (3.09x) | 400.70 (2.37x) | 1353.13 (8.01x) |
| complex deterministic binary encode | 102.54 | — | — | 174.28 (1.70x) | 1147.69 (11.19x) |
| complex JSON stringify | 279.98 | — | — | 4894.92 (17.48x) | 6154.89 (21.98x) |
| complex JSON parse | 2378.18 | — | — | 11890.60 (5.00x) | 7566.42 (3.18x) |
| complex TextFormat format | 258.47 | — | — | 3786.99 (14.65x) | 5440.39 (21.05x) |
| complex TextFormat parse | 1895.92 | — | — | 6914.72 (3.65x) | 8546.65 (4.51x) |
| packed int32 encode | 706.96 | 3174.07 (4.49x) | 2505.29 (3.54x) | 1235.77 (1.75x) | 2731.74 (3.86x) |
| packed int32 decode | 767.85 | 1901.44 (2.48x) | 3223.66 (4.20x) | 961.75 (1.25x) | 2582.01 (3.36x) |
| JSON stringify | 156.72 | — | — | 2984.92 (19.05x) | 2344.40 (14.96x) |
| JSON parse | 1521.05 | — | — | 7360.68 (4.84x) | 4697.90 (3.09x) |
| Any WKT JSON stringify | 134.95 | — | — | 1882.82 (13.95x) | 981.53 (7.27x) |
| Any WKT JSON parse | 528.39 | — | — | 2981.40 (5.64x) | 1532.72 (2.90x) |
| Any Duration Escape WKT JSON parse | 545.70 | — | — | 3018.55 (5.53x) | 1624.38 (2.98x) |
| Any PlusDuration WKT JSON parse | 528.37 | — | — | 3047.81 (5.77x) | 1573.51 (2.98x) |
| Any ShortFractionDuration WKT JSON parse | 525.82 | — | — | 3015.40 (5.73x) | 1505.74 (2.86x) |
| Any MicroDuration WKT JSON stringify | 142.86 | — | — | 1922.15 (13.45x) | 1000.09 (7.00x) |
| Any MicroDuration WKT JSON parse | 528.76 | — | — | 3002.14 (5.68x) | 1530.41 (2.89x) |
| Any NanoDuration WKT JSON stringify | 136.51 | — | — | 1923.27 (14.09x) | 986.05 (7.22x) |
| Any NanoDuration WKT JSON parse | 533.30 | — | — | 2999.90 (5.63x) | 1550.94 (2.91x) |
| Any NegativeDuration WKT JSON stringify | 140.73 | — | — | 1949.15 (13.85x) | 1010.27 (7.18x) |
| Any NegativeDuration WKT JSON parse | 533.41 | — | — | 3099.36 (5.81x) | 1578.74 (2.96x) |
| Any FractionalNegativeDuration WKT JSON stringify | 136.01 | — | — | 1897.15 (13.95x) | 1012.10 (7.44x) |
| Any FractionalNegativeDuration WKT JSON parse | 529.25 | — | — | 3051.72 (5.77x) | 1505.62 (2.84x) |
| Any MaxDuration WKT JSON stringify | 120.45 | — | — | 1764.21 (14.65x) | 980.86 (8.14x) |
| Any MaxDuration WKT JSON parse | 539.43 | — | — | 2949.46 (5.47x) | 1563.12 (2.90x) |
| Any MinDuration WKT JSON stringify | 123.16 | — | — | 1758.94 (14.28x) | 1006.29 (8.17x) |
| Any MinDuration WKT JSON parse | 542.49 | — | — | 3009.15 (5.55x) | 1544.87 (2.85x) |
| Any ZeroDuration WKT JSON stringify | 111.17 | — | — | 914.61 (8.23x) | 967.74 (8.71x) |
| Any ZeroDuration WKT JSON parse | 475.39 | — | — | 2249.26 (4.73x) | 1487.80 (3.13x) |
| Any FieldMask WKT JSON stringify | 234.03 | — | — | 1741.33 (7.44x) | 1414.87 (6.05x) |
| Any FieldMask WKT JSON parse | 699.69 | — | — | 3157.85 (4.51x) | 2083.50 (2.98x) |
| Any FieldMask Escape WKT JSON parse | 729.25 | — | — | 3241.01 (4.44x) | 2241.60 (3.07x) |
| Any EmptyFieldMask WKT JSON stringify | 116.31 | — | — | 916.62 (7.88x) | 782.52 (6.73x) |
| Any EmptyFieldMask WKT JSON parse | 445.18 | — | — | 2157.47 (4.85x) | 1298.00 (2.92x) |
| Any Timestamp WKT JSON stringify | 183.82 | — | — | 2030.05 (11.04x) | 1051.25 (5.72x) |
| Any Timestamp WKT JSON parse | 570.40 | — | — | 3049.96 (5.35x) | 1618.69 (2.84x) |
| Any Timestamp Escape WKT JSON parse | 591.73 | — | — | 3147.18 (5.32x) | 1770.99 (2.99x) |
| Any ShortFraction Timestamp WKT JSON parse | 565.03 | — | — | 3018.52 (5.34x) | 1606.34 (2.84x) |
| Any Micro Timestamp WKT JSON stringify | 182.32 | — | — | 2031.57 (11.14x) | 1010.39 (5.54x) |
| Any Micro Timestamp WKT JSON parse | 573.83 | — | — | 3048.14 (5.31x) | 1639.15 (2.86x) |
| Any Nano Timestamp WKT JSON stringify | 183.00 | — | — | 2034.25 (11.12x) | 1023.26 (5.59x) |
| Any Nano Timestamp WKT JSON parse | 578.96 | — | — | 3048.15 (5.26x) | 1644.74 (2.84x) |
| Any Offset Timestamp WKT JSON parse | 586.03 | — | — | 3063.59 (5.23x) | 1677.50 (2.86x) |
| Any PreEpoch Timestamp WKT JSON stringify | 150.03 | — | — | 1952.85 (13.02x) | 977.48 (6.52x) |
| Any PreEpoch Timestamp WKT JSON parse | 559.55 | — | — | 3055.11 (5.46x) | 1579.65 (2.82x) |
| Any Max Timestamp WKT JSON stringify | 181.03 | — | — | 2055.98 (11.36x) | 1024.85 (5.66x) |
| Any Max Timestamp WKT JSON parse | 578.97 | — | — | 3159.27 (5.46x) | 1665.60 (2.88x) |
| Any Min Timestamp WKT JSON stringify | 166.51 | — | — | 1939.15 (11.65x) | 993.28 (5.97x) |
| Any Min Timestamp WKT JSON parse | 557.46 | — | — | 3045.11 (5.46x) | 1605.46 (2.88x) |
| Any Empty WKT JSON stringify | 92.33 | — | — | 913.65 (9.90x) | 632.95 (6.86x) |
| Any Empty WKT JSON parse | 335.43 | — | — | 2139.32 (6.38x) | 1345.31 (4.01x) |
| Any Struct WKT JSON stringify | 652.53 | — | — | 5863.57 (8.99x) | 6117.98 (9.38x) |
| Any Struct WKT JSON parse | 1749.85 | — | — | 11034.30 (6.31x) | 8757.15 (5.00x) |
| Any Struct Escape WKT JSON parse | 1781.33 | — | — | 11081.80 (6.22x) | 8930.02 (5.01x) |
| Any Struct NumberExponent WKT JSON parse | 1757.89 | — | — | 11112.10 (6.32x) | 8898.41 (5.06x) |
| Any EmptyStruct WKT JSON stringify | 120.01 | — | — | 932.67 (7.77x) | 952.53 (7.94x) |
| Any EmptyStruct WKT JSON parse | 442.36 | — | — | 2241.54 (5.07x) | 1573.31 (3.56x) |
| Any Value WKT JSON stringify | 676.06 | — | — | 5845.46 (8.65x) | 6375.70 (9.43x) |
| Any Value WKT JSON parse | 1809.65 | — | — | 11188.00 (6.18x) | 9152.02 (5.06x) |
| Any Value Escape WKT JSON parse | 1834.33 | — | — | 11346.20 (6.19x) | 9278.16 (5.06x) |
| Any Value NumberExponent WKT JSON parse | 1807.01 | — | — | 11288.80 (6.25x) | 9148.90 (5.06x) |
| Any NullValue WKT JSON stringify | 131.18 | — | — | 2267.54 (17.29x) | 923.40 (7.04x) |
| Any NullValue WKT JSON parse | 465.43 | — | — | 4040.56 (8.68x) | 1563.28 (3.36x) |
| Any StringScalarValue WKT JSON stringify | 155.68 | — | — | 2279.85 (14.64x) | 1149.96 (7.39x) |
| Any StringScalarValue WKT JSON parse | 521.94 | — | — | 3639.12 (6.97x) | 1679.87 (3.22x) |
| Any StringScalarValue Escape WKT JSON parse | 535.22 | — | — | 3714.30 (6.94x) | 1732.55 (3.24x) |
| Any EmptyStringScalarValue WKT JSON stringify | 144.08 | — | — | 2282.45 (15.84x) | 945.67 (6.56x) |
| Any EmptyStringScalarValue WKT JSON parse | 494.13 | — | — | 3657.93 (7.40x) | 1591.60 (3.22x) |
| Any NumberValue WKT JSON stringify | 182.48 | — | — | 2515.38 (13.78x) | 1036.35 (5.68x) |
| Any NumberValue WKT JSON parse | 510.47 | — | — | 3699.01 (7.25x) | 1607.01 (3.15x) |
| Any NumberValue Exponent WKT JSON parse | 513.91 | — | — | 3726.90 (7.25x) | 1629.04 (3.17x) |
| Any NegativeNumberValue WKT JSON stringify | 347.77 | — | — | 2519.01 (7.24x) | 1035.09 (2.98x) |
| Any NegativeNumberValue WKT JSON parse | 822.05 | — | — | 3725.88 (4.53x) | 1610.51 (1.96x) |
| Any ZeroNumberValue WKT JSON stringify | 269.01 | — | — | 3201.62 (11.90x) | 932.54 (3.47x) |
| Any ZeroNumberValue WKT JSON parse | 804.92 | — | — | 3668.25 (4.56x) | 1622.18 (2.02x) |
| Any BoolScalarValue WKT JSON stringify | 239.88 | — | — | 2274.39 (9.48x) | 917.26 (3.82x) |
| Any BoolScalarValue WKT JSON parse | 751.95 | — | — | 3628.87 (4.83x) | 1514.73 (2.01x) |
| Any FalseBoolScalarValue WKT JSON stringify | 238.23 | — | — | 2272.49 (9.54x) | 937.75 (3.94x) |
| Any FalseBoolScalarValue WKT JSON parse | 753.77 | — | — | 3638.30 (4.83x) | 1531.79 (2.03x) |
| Any ListKindValue WKT JSON stringify | 962.89 | — | — | 5572.12 (5.79x) | 4686.14 (4.87x) |
| Any ListKindValue WKT JSON parse | 1929.23 | — | — | 9859.20 (5.11x) | 7026.59 (3.64x) |
| Any ListKindValue Escape WKT JSON parse | 1426.02 | — | — | 9923.70 (6.96x) | 7338.65 (5.15x) |
| Any EmptyStructKindValue WKT JSON stringify | 144.26 | — | — | 2915.65 (20.21x) | 1274.74 (8.84x) |
| Any EmptyStructKindValue WKT JSON parse | 504.04 | — | — | 5386.88 (10.69x) | 1939.67 (3.85x) |
| Any EmptyListKindValue WKT JSON stringify | 145.11 | — | — | 2895.94 (19.96x) | 1089.93 (7.51x) |
| Any EmptyListKindValue WKT JSON parse | 511.93 | — | — | 4367.54 (8.53x) | 1826.48 (3.57x) |
| Any DoubleValue WKT JSON stringify | 187.48 | — | — | 1792.15 (9.56x) | 1353.62 (7.22x) |
| Any DoubleValue WKT JSON parse | 522.17 | — | — | 2726.56 (5.22x) | 1452.71 (2.78x) |
| Any DoubleValue String WKT JSON parse | 529.70 | — | — | 2734.92 (5.16x) | 1527.32 (2.88x) |
| Any DoubleValue Exponent WKT JSON parse | 525.36 | — | — | 2743.70 (5.22x) | 1537.30 (2.93x) |
| Any NegativeDoubleValue WKT JSON stringify | 186.07 | — | — | 1804.60 (9.70x) | 815.42 (4.38x) |
| Any NegativeDoubleValue WKT JSON parse | 518.51 | — | — | 2740.23 (5.28x) | 2127.25 (4.10x) |
| Any ZeroDoubleValue WKT JSON stringify | 160.26 | — | — | 918.42 (5.73x) | 753.98 (4.70x) |
| Any ZeroDoubleValue WKT JSON parse | 518.14 | — | — | 2168.61 (4.19x) | 1403.22 (2.71x) |
| Any DoubleValue NaN WKT JSON stringify | 162.70 | — | — | 1574.73 (9.68x) | 721.24 (4.43x) |
| Any DoubleValue NaN WKT JSON parse | 517.26 | — | — | 2646.65 (5.12x) | 1421.64 (2.75x) |
| Any DoubleValue Infinity WKT JSON stringify | 175.23 | — | — | 1566.77 (8.94x) | 724.83 (4.14x) |
| Any DoubleValue Infinity WKT JSON parse | 519.39 | — | — | 2679.79 (5.16x) | 1428.33 (2.75x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 161.30 | — | — | 1559.25 (9.67x) | 718.14 (4.45x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 524.22 | — | — | 2672.19 (5.10x) | 1441.78 (2.75x) |
| Any FloatValue WKT JSON stringify | 194.44 | — | — | 1754.58 (9.02x) | 794.89 (4.09x) |
| Any FloatValue WKT JSON parse | 522.56 | — | — | 2706.70 (5.18x) | 1419.48 (2.72x) |
| Any FloatValue String WKT JSON parse | 531.71 | — | — | 2729.23 (5.13x) | 1519.25 (2.86x) |
| Any FloatValue Exponent WKT JSON parse | 529.25 | — | — | 2724.83 (5.15x) | 1424.99 (2.69x) |
| Any NegativeFloatValue WKT JSON stringify | 196.46 | — | — | 1745.52 (8.88x) | 784.72 (3.99x) |
| Any NegativeFloatValue WKT JSON parse | 525.58 | — | — | 2713.21 (5.16x) | 1424.36 (2.71x) |
| Any ZeroFloatValue WKT JSON stringify | 162.76 | — | — | 919.61 (5.65x) | 911.73 (5.60x) |
| Any ZeroFloatValue WKT JSON parse | 519.93 | — | — | 2150.36 (4.14x) | 1403.08 (2.70x) |
| Any FloatValue NaN WKT JSON stringify | 154.96 | — | — | 1562.64 (10.08x) | 727.94 (4.70x) |
| Any FloatValue NaN WKT JSON parse | 516.32 | — | — | 2605.31 (5.05x) | 1404.87 (2.72x) |
| Any FloatValue Infinity WKT JSON stringify | 160.93 | — | — | 1552.96 (9.65x) | 729.20 (4.53x) |
| Any FloatValue Infinity WKT JSON parse | 523.44 | — | — | 2649.50 (5.06x) | 1442.90 (2.76x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 164.80 | — | — | 1547.92 (9.39x) | 734.10 (4.45x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 523.77 | — | — | 2636.68 (5.03x) | 1438.73 (2.75x) |
| Any Int64Value WKT JSON stringify | 167.05 | — | — | 1568.48 (9.39x) | 876.88 (5.25x) |
| Any Int64Value WKT JSON parse | 556.02 | — | — | 2767.71 (4.98x) | 1647.03 (2.96x) |
| Any Int64Value Number WKT JSON parse | 550.48 | — | — | 2729.82 (4.96x) | 1553.18 (2.82x) |
| Any Int64Value Exponent WKT JSON parse | 538.30 | — | — | 2692.93 (5.00x) | 1499.10 (2.78x) |
| Any ZeroInt64Value WKT JSON stringify | 171.14 | — | — | 917.16 (5.36x) | 785.04 (4.59x) |
| Any ZeroInt64Value WKT JSON parse | 523.21 | — | — | 2146.49 (4.10x) | 1485.58 (2.84x) |
| Any NegativeInt64Value WKT JSON stringify | 170.36 | — | — | 1565.99 (9.19x) | 849.95 (4.99x) |
| Any NegativeInt64Value WKT JSON parse | 562.23 | — | — | 2796.15 (4.97x) | 1673.07 (2.98x) |
| Any MinInt64Value WKT JSON stringify | 171.38 | — | — | 1570.00 (9.16x) | 882.02 (5.15x) |
| Any MinInt64Value WKT JSON parse | 569.53 | — | — | 2810.26 (4.93x) | 1658.59 (2.91x) |
| Any MaxInt64Value WKT JSON stringify | 172.84 | — | — | 1560.79 (9.03x) | 861.95 (4.99x) |
| Any MaxInt64Value WKT JSON parse | 558.92 | — | — | 2790.32 (4.99x) | 1671.20 (2.99x) |
| Any UInt64Value WKT JSON stringify | 172.30 | — | — | 1560.51 (9.06x) | 854.96 (4.96x) |
| Any UInt64Value WKT JSON parse | 562.19 | — | — | 2783.42 (4.95x) | 1646.51 (2.93x) |
| Any UInt64Value Number WKT JSON parse | 556.06 | — | — | 2759.19 (4.96x) | 1535.40 (2.76x) |
| Any UInt64Value Exponent WKT JSON parse | 541.35 | — | — | 2705.91 (5.00x) | 1484.36 (2.74x) |
| Any ZeroUInt64Value WKT JSON stringify | 165.10 | — | — | 920.52 (5.58x) | 778.79 (4.72x) |
| Any ZeroUInt64Value WKT JSON parse | 529.46 | — | — | 2153.73 (4.07x) | 1493.70 (2.82x) |
| Any MaxUInt64Value WKT JSON stringify | 178.13 | — | — | 1568.87 (8.81x) | 863.19 (4.85x) |
| Any MaxUInt64Value WKT JSON parse | 569.82 | — | — | 2833.24 (4.97x) | 1669.57 (2.93x) |
| Any Int32Value WKT JSON stringify | 169.22 | — | — | 1558.82 (9.21x) | 729.69 (4.31x) |
| Any Int32Value WKT JSON parse | 539.56 | — | — | 2686.99 (4.98x) | 1435.00 (2.66x) |
| Any Int32Value String WKT JSON parse | 544.31 | — | — | 3644.77 (6.70x) | 1544.82 (2.84x) |
| Any Int32Value Exponent WKT JSON parse | 545.75 | — | — | 4883.42 (8.95x) | 1498.42 (2.75x) |
| Any ZeroInt32Value WKT JSON stringify | 166.48 | — | — | 961.25 (5.77x) | 703.71 (4.23x) |
| Any ZeroInt32Value WKT JSON parse | 533.15 | — | — | 2210.75 (4.15x) | 1402.55 (2.63x) |
| Any NegativeInt32Value WKT JSON stringify | 179.56 | — | — | 1616.73 (9.00x) | 746.71 (4.16x) |
| Any NegativeInt32Value WKT JSON parse | 541.10 | — | — | 2693.78 (4.98x) | 1463.89 (2.71x) |
| Any MinInt32Value WKT JSON stringify | 170.96 | — | — | 1555.17 (9.10x) | 742.48 (4.34x) |
| Any MinInt32Value WKT JSON parse | 548.14 | — | — | 2707.98 (4.94x) | 1493.66 (2.72x) |
| Any MaxInt32Value WKT JSON stringify | 171.51 | — | — | 1553.21 (9.06x) | 731.98 (4.27x) |
| Any MaxInt32Value WKT JSON parse | 545.80 | — | — | 2675.44 (4.90x) | 1441.52 (2.64x) |
| Any UInt32Value WKT JSON stringify | 173.71 | — | — | 1556.80 (8.96x) | 994.38 (5.72x) |
| Any UInt32Value WKT JSON parse | 541.54 | — | — | 2683.78 (4.96x) | 1434.21 (2.65x) |
| Any UInt32Value String WKT JSON parse | 552.86 | — | — | 2680.17 (4.85x) | 1548.39 (2.80x) |
| Any UInt32Value Exponent WKT JSON parse | 549.25 | — | — | 2707.65 (4.93x) | 1504.65 (2.74x) |
| Any ZeroUInt32Value WKT JSON stringify | 175.30 | — | — | 920.64 (5.25x) | 718.72 (4.10x) |
| Any ZeroUInt32Value WKT JSON parse | 533.54 | — | — | 2154.63 (4.04x) | 1410.74 (2.64x) |
| Any MaxUInt32Value WKT JSON stringify | 179.70 | — | — | 1555.01 (8.65x) | 748.37 (4.16x) |
| Any MaxUInt32Value WKT JSON parse | 554.58 | — | — | 2699.60 (4.87x) | 1472.01 (2.65x) |
| Any BoolValue WKT JSON stringify | 177.34 | — | — | 1524.25 (8.60x) | 732.03 (4.13x) |
| Any BoolValue WKT JSON parse | 490.62 | — | — | 2590.90 (5.28x) | 1321.77 (2.69x) |
| Any FalseBoolValue WKT JSON stringify | 175.24 | — | — | 918.54 (5.24x) | 718.90 (4.10x) |
| Any FalseBoolValue WKT JSON parse | 489.52 | — | — | 2145.42 (4.38x) | 1343.38 (2.74x) |
| Any StringValue WKT JSON stringify | 191.37 | — | — | 1574.81 (8.23x) | 806.13 (4.21x) |
| Any StringValue WKT JSON parse | 548.82 | — | — | 2665.35 (4.86x) | 1448.90 (2.64x) |
| Any StringValue Escape WKT JSON parse | 555.89 | — | — | 2682.53 (4.83x) | 1527.56 (2.75x) |
| Any EmptyStringValue WKT JSON stringify | 192.38 | — | — | 919.86 (4.78x) | 753.00 (3.91x) |
| Any EmptyStringValue WKT JSON parse | 521.19 | — | — | 2152.43 (4.13x) | 1407.47 (2.70x) |
| Any BytesValue WKT JSON stringify | 187.85 | — | — | 1572.44 (8.37x) | 836.41 (4.45x) |
| Any BytesValue WKT JSON parse | 564.32 | — | — | 2676.10 (4.74x) | 1489.88 (2.64x) |
| Any BytesValue URL WKT JSON parse | 581.53 | — | — | 2675.86 (4.60x) | 1512.39 (2.60x) |
| Any BytesValue StandardBase64 WKT JSON parse | 566.88 | — | — | 2727.14 (4.81x) | 1503.14 (2.65x) |
| Any BytesValue Unpadded WKT JSON parse | 565.74 | — | — | 2687.76 (4.75x) | 1500.09 (2.65x) |
| Any EmptyBytesValue WKT JSON stringify | 180.66 | — | — | 915.95 (5.07x) | 772.32 (4.27x) |
| Any EmptyBytesValue WKT JSON parse | 525.98 | — | — | 2152.55 (4.09x) | 1528.20 (2.91x) |
| Nested Any WKT JSON stringify | 324.02 | — | — | 2471.45 (7.63x) | 1441.00 (4.45x) |
| Nested Any WKT JSON parse | 871.14 | — | — | 4262.67 (4.89x) | 2851.42 (3.27x) |
| Duration JSON stringify | 57.24 | — | — | 955.41 (16.69x) | 370.49 (6.47x) |
| Duration JSON parse | 19.07 | — | — | 1453.56 (76.22x) | 391.84 (20.55x) |
| Duration Escape JSON parse | 39.58 | — | — | 1487.00 (37.57x) | 442.71 (11.19x) |
| PlusDuration JSON parse | 17.32 | — | — | 1458.44 (84.21x) | 402.11 (23.22x) |
| ShortFractionDuration JSON parse | 14.79 | — | — | 1419.98 (96.01x) | 467.74 (31.63x) |
| MicroDuration JSON stringify | 59.25 | — | — | 967.62 (16.33x) | 404.39 (6.83x) |
| MicroDuration JSON parse | 20.61 | — | — | 1464.55 (71.06x) | 393.92 (19.11x) |
| NanoDuration JSON stringify | 57.36 | — | — | 991.98 (17.29x) | 415.26 (7.24x) |
| NanoDuration JSON parse | 24.90 | — | — | 1478.57 (59.38x) | 403.32 (16.20x) |
| NegativeDuration JSON stringify | 58.65 | — | — | 1005.42 (17.14x) | 429.07 (7.32x) |
| NegativeDuration JSON parse | 18.09 | — | — | 1508.20 (83.37x) | 397.07 (21.95x) |
| FractionalNegativeDuration JSON stringify | 58.19 | — | — | 970.17 (16.67x) | 429.77 (7.39x) |
| FractionalNegativeDuration JSON parse | 18.08 | — | — | 1456.59 (80.56x) | 383.16 (21.19x) |
| MaxDuration JSON stringify | 49.32 | — | — | 854.98 (17.34x) | 422.32 (8.56x) |
| MaxDuration JSON parse | 32.07 | — | — | 1431.57 (44.64x) | 404.65 (12.62x) |
| MinDuration JSON stringify | 49.97 | — | — | 874.23 (17.50x) | 445.37 (8.91x) |
| MinDuration JSON parse | 30.36 | — | — | 1460.41 (48.10x) | 404.41 (13.32x) |
| ZeroDuration JSON stringify | 44.83 | — | — | 921.68 (20.56x) | 356.86 (7.96x) |
| ZeroDuration JSON parse | 16.56 | — | — | 1367.49 (82.58x) | 310.37 (18.74x) |
| FieldMask JSON stringify | 116.98 | — | — | 894.28 (7.64x) | 649.93 (5.56x) |
| FieldMask JSON parse | 161.56 | — | — | 1671.66 (10.35x) | 894.91 (5.54x) |
| FieldMask Escape JSON parse | 187.72 | — | — | 1712.41 (9.12x) | 972.31 (5.18x) |
| EmptyFieldMask JSON stringify | 40.88 | — | — | 621.66 (15.21x) | 195.53 (4.78x) |
| EmptyFieldMask JSON parse | 4.78 | — | — | 949.63 (198.67x) | 173.72 (36.34x) |
| Timestamp JSON stringify | 99.71 | — | — | 1143.51 (11.47x) | 411.88 (4.13x) |
| Timestamp JSON parse | 52.07 | — | — | 1607.10 (30.86x) | 514.76 (9.89x) |
| Timestamp Escape JSON parse | 91.60 | — | — | 1521.99 (16.62x) | 508.81 (5.55x) |
| ShortFraction Timestamp JSON parse | 50.91 | — | — | 1482.08 (29.11x) | 439.36 (8.63x) |
| Micro Timestamp JSON stringify | 100.37 | — | — | 1151.91 (11.48x) | 415.83 (4.14x) |
| Micro Timestamp JSON parse | 53.68 | — | — | 1502.76 (27.99x) | 464.91 (8.66x) |
| Nano Timestamp JSON stringify | 97.57 | — | — | 1199.03 (12.29x) | 421.21 (4.32x) |
| Nano Timestamp JSON parse | 55.12 | — | — | 1518.68 (27.55x) | 464.16 (8.42x) |
| Offset Timestamp JSON parse | 58.23 | — | — | 1521.31 (26.13x) | 490.37 (8.42x) |
| PreEpoch Timestamp JSON stringify | 70.34 | — | — | 1070.20 (15.21x) | 399.69 (5.68x) |
| PreEpoch Timestamp JSON parse | 50.96 | — | — | 1456.16 (28.57x) | 428.33 (8.41x) |
| Max Timestamp JSON stringify | 82.47 | — | — | 1210.49 (14.68x) | 427.33 (5.18x) |
| Max Timestamp JSON parse | 56.17 | — | — | 1536.78 (27.36x) | 462.62 (8.24x) |
| Min Timestamp JSON stringify | 84.10 | — | — | 1060.38 (12.61x) | 402.94 (4.79x) |
| Min Timestamp JSON parse | 49.15 | — | — | 1455.74 (29.62x) | 425.67 (8.66x) |
| Empty JSON stringify | 20.58 | — | — | 851.26 (41.36x) | 88.24 (4.29x) |
| Empty JSON parse | 67.16 | — | — | 722.67 (10.76x) | 218.74 (3.26x) |
| Struct JSON stringify | 177.02 | — | — | 5714.49 (32.28x) | 3046.84 (17.21x) |
| Struct JSON parse | 886.29 | — | — | 10901.90 (12.30x) | 4682.78 (5.28x) |
| Struct Escape JSON parse | 931.19 | — | — | 10970.60 (11.78x) | 4815.30 (5.17x) |
| Struct NumberExponent JSON parse | 887.74 | — | — | 10902.60 (12.28x) | 4674.71 (5.27x) |
| EmptyStruct JSON stringify | 40.35 | — | — | 687.29 (17.03x) | 354.58 (8.79x) |
| EmptyStruct JSON parse | 97.26 | — | — | 2017.00 (20.74x) | 384.53 (3.95x) |
| Value JSON stringify | 183.14 | — | — | 6573.38 (35.89x) | 3205.12 (17.50x) |
| Value JSON parse | 888.68 | — | — | 12237.10 (13.77x) | 4944.93 (5.56x) |
| Value Escape JSON parse | 930.22 | — | — | 12256.70 (13.18x) | 5082.81 (5.46x) |
| Value NumberExponent JSON parse | 883.91 | — | — | 12195.10 (13.80x) | 4943.31 (5.59x) |
| NullValue JSON stringify | 41.38 | — | — | 1317.87 (31.85x) | 219.83 (5.31x) |
| NullValue JSON parse | 74.42 | — | — | 2480.11 (33.33x) | 345.13 (4.64x) |
| StringScalarValue JSON stringify | 47.38 | — | — | 1342.16 (28.33x) | 275.39 (5.81x) |
| StringScalarValue JSON parse | 141.50 | — | — | 2093.44 (14.79x) | 443.04 (3.13x) |
| StringScalarValue Escape JSON parse | 151.32 | — | — | 2125.35 (14.05x) | 495.59 (3.28x) |
| EmptyStringScalarValue JSON stringify | 45.95 | — | — | 1334.87 (29.05x) | 281.41 (6.12x) |
| EmptyStringScalarValue JSON parse | 87.40 | — | — | 2070.54 (23.69x) | 356.22 (4.08x) |
| NumberValue JSON stringify | 73.88 | — | — | 1558.29 (21.09x) | 334.88 (4.53x) |
| NumberValue JSON parse | 133.33 | — | — | 2165.55 (16.24x) | 420.80 (3.16x) |
| NumberValue Exponent JSON parse | 135.23 | — | — | 2177.88 (16.11x) | 417.92 (3.09x) |
| NegativeNumberValue JSON stringify | 73.87 | — | — | 1553.44 (21.03x) | 329.62 (4.46x) |
| NegativeNumberValue JSON parse | 133.80 | — | — | 2171.49 (16.23x) | 410.77 (3.07x) |
| ZeroNumberValue JSON stringify | 50.94 | — | — | 1505.38 (29.55x) | 461.68 (9.06x) |
| ZeroNumberValue JSON parse | 129.92 | — | — | 2113.54 (16.27x) | 396.50 (3.05x) |
| BoolScalarValue JSON stringify | 42.27 | — | — | 1312.09 (31.04x) | 218.10 (5.16x) |
| BoolScalarValue JSON parse | 70.17 | — | — | 2021.37 (28.81x) | 340.49 (4.85x) |
| FalseBoolScalarValue JSON stringify | 42.26 | — | — | 1316.43 (31.15x) | 218.67 (5.17x) |
| FalseBoolScalarValue JSON parse | 70.67 | — | — | 2024.33 (28.64x) | 327.93 (4.64x) |
| ListKindValue JSON stringify | 143.99 | — | — | 6149.30 (42.71x) | 2259.74 (15.69x) |
| ListKindValue JSON parse | 722.65 | — | — | 10439.90 (14.45x) | 4039.25 (5.59x) |
| ListKindValue Escape JSON parse | 747.52 | — | — | 10495.30 (14.04x) | 4255.40 (5.69x) |
| EmptyStructKindValue JSON stringify | 42.28 | — | — | 1933.45 (45.73x) | 522.13 (12.35x) |
| EmptyStructKindValue JSON parse | 112.50 | — | — | 3730.28 (33.16x) | 658.13 (5.85x) |
| EmptyListKindValue JSON stringify | 42.95 | — | — | 1936.51 (45.09x) | 363.62 (8.47x) |
| EmptyListKindValue JSON parse | 148.94 | — | — | 4032.02 (27.07x) | 599.83 (4.03x) |
| ListValue JSON stringify | 144.38 | — | — | 4728.73 (32.75x) | 2109.54 (14.61x) |
| ListValue JSON parse | 673.78 | — | — | 8557.80 (12.70x) | 3828.45 (5.68x) |
| ListValue Escape JSON parse | 695.96 | — | — | 8598.07 (12.35x) | 4010.58 (5.76x) |
| EmptyListValue JSON stringify | 39.90 | — | — | 686.60 (17.21x) | 188.15 (4.72x) |
| EmptyListValue JSON parse | 139.28 | — | — | 2267.83 (16.28x) | 343.45 (2.47x) |
| DoubleValue JSON stringify | 67.57 | — | — | 865.59 (12.81x) | 196.60 (2.91x) |
| DoubleValue JSON parse | 111.70 | — | — | 1227.33 (10.99x) | 599.48 (5.37x) |
| DoubleValue String JSON parse | 112.86 | — | — | 1164.26 (10.32x) | 673.24 (5.97x) |
| DoubleValue Exponent JSON parse | 113.10 | — | — | 1238.30 (10.95x) | 596.38 (5.27x) |
| NegativeDoubleValue JSON stringify | 67.87 | — | — | 865.89 (12.76x) | 195.05 (2.87x) |
| NegativeDoubleValue JSON parse | 111.00 | — | — | 1232.33 (11.10x) | 281.48 (2.54x) |
| ZeroDoubleValue JSON stringify | 47.13 | — | — | 816.14 (17.32x) | 293.84 (6.23x) |
| ZeroDoubleValue JSON parse | 110.09 | — | — | 1161.20 (10.55x) | 281.90 (2.56x) |
| DoubleValue NaN JSON stringify | 46.40 | — | — | 676.30 (14.58x) | 124.45 (2.68x) |
| DoubleValue NaN JSON parse | 105.75 | — | — | 1105.34 (10.45x) | 282.19 (2.67x) |
| DoubleValue Infinity JSON stringify | 47.51 | — | — | 670.95 (14.12x) | 127.28 (2.68x) |
| DoubleValue Infinity JSON parse | 107.32 | — | — | 1104.00 (10.29x) | 271.46 (2.53x) |
| DoubleValue NegativeInfinity JSON stringify | 47.74 | — | — | 662.21 (13.87x) | 122.06 (2.56x) |
| DoubleValue NegativeInfinity JSON parse | 109.58 | — | — | 1106.96 (10.10x) | 284.93 (2.60x) |
| FloatValue JSON stringify | 70.93 | — | — | 796.40 (11.23x) | 187.33 (2.64x) |
| FloatValue JSON parse | 111.67 | — | — | 1208.32 (10.82x) | 292.73 (2.62x) |
| FloatValue String JSON parse | 111.22 | — | — | 1237.89 (11.13x) | 371.49 (3.34x) |
| FloatValue Exponent JSON parse | 113.33 | — | — | 1255.57 (11.08x) | 296.87 (2.62x) |
| NegativeFloatValue JSON stringify | 71.38 | — | — | 798.30 (11.18x) | 205.51 (2.88x) |
| NegativeFloatValue JSON parse | 112.54 | — | — | 1213.80 (10.79x) | 299.80 (2.66x) |
| ZeroFloatValue JSON stringify | 47.19 | — | — | 741.93 (15.72x) | 191.44 (4.06x) |
| ZeroFloatValue JSON parse | 109.45 | — | — | 1145.17 (10.46x) | 337.38 (3.08x) |
| FloatValue NaN JSON stringify | 45.98 | — | — | 645.18 (14.03x) | 132.03 (2.87x) |
| FloatValue NaN JSON parse | 105.26 | — | — | 1083.22 (10.29x) | 282.97 (2.69x) |
| FloatValue Infinity JSON stringify | 47.63 | — | — | 638.07 (13.40x) | 124.07 (2.60x) |
| FloatValue Infinity JSON parse | 106.27 | — | — | 1085.54 (10.21x) | 269.51 (2.54x) |
| FloatValue NegativeInfinity JSON stringify | 48.00 | — | — | 634.77 (13.22x) | 127.77 (2.66x) |
| FloatValue NegativeInfinity JSON parse | 108.57 | — | — | 1096.48 (10.10x) | 288.07 (2.65x) |
| Int64Value JSON stringify | 50.12 | — | — | 679.20 (13.55x) | 282.18 (5.63x) |
| Int64Value JSON parse | 125.36 | — | — | 1223.60 (9.76x) | 476.99 (3.80x) |
| Int64Value Number JSON parse | 126.78 | — | — | 1279.82 (10.09x) | 375.74 (2.96x) |
| Int64Value Exponent JSON parse | 115.87 | — | — | 1216.95 (10.50x) | 371.23 (3.20x) |
| ZeroInt64Value JSON stringify | 41.55 | — | — | 611.38 (14.71x) | 192.01 (4.62x) |
| ZeroInt64Value JSON parse | 106.59 | — | — | 1089.97 (10.23x) | 347.45 (3.26x) |
| NegativeInt64Value JSON stringify | 48.54 | — | — | 678.34 (13.97x) | 278.93 (5.75x) |
| NegativeInt64Value JSON parse | 126.16 | — | — | 1223.49 (9.70x) | 480.24 (3.81x) |
| MinInt64Value JSON stringify | 49.84 | — | — | 685.12 (13.75x) | 286.17 (5.74x) |
| MinInt64Value JSON parse | 133.96 | — | — | 1251.67 (9.34x) | 493.15 (3.68x) |
| MaxInt64Value JSON stringify | 49.23 | — | — | 676.47 (13.74x) | 283.89 (5.77x) |
| MaxInt64Value JSON parse | 133.62 | — | — | 1235.32 (9.25x) | 475.63 (3.56x) |
| UInt64Value JSON stringify | 50.18 | — | — | 677.49 (13.50x) | 274.16 (5.46x) |
| UInt64Value JSON parse | 125.90 | — | — | 1216.50 (9.66x) | 458.04 (3.64x) |
| UInt64Value Number JSON parse | 127.42 | — | — | 1280.68 (10.05x) | 353.34 (2.77x) |
| UInt64Value Exponent JSON parse | 116.19 | — | — | 1228.21 (10.57x) | 357.33 (3.08x) |
| ZeroUInt64Value JSON stringify | 41.75 | — | — | 615.13 (14.73x) | 198.15 (4.75x) |
| ZeroUInt64Value JSON parse | 105.92 | — | — | 1108.22 (10.46x) | 341.04 (3.22x) |
| MaxUInt64Value JSON stringify | 50.66 | — | — | 680.92 (13.44x) | 290.19 (5.73x) |
| MaxUInt64Value JSON parse | 136.17 | — | — | 1244.41 (9.14x) | 475.80 (3.49x) |
| Int32Value JSON stringify | 48.64 | — | — | 637.75 (13.11x) | 219.25 (4.51x) |
| Int32Value JSON parse | 132.64 | — | — | 1179.15 (8.89x) | 321.75 (2.43x) |
| Int32Value String JSON parse | 137.36 | — | — | 1131.43 (8.24x) | 403.54 (2.94x) |
| Int32Value Exponent JSON parse | 136.05 | — | — | 1217.35 (8.95x) | 364.58 (2.68x) |
| ZeroInt32Value JSON stringify | 45.92 | — | — | 689.53 (15.02x) | 130.79 (2.85x) |
| ZeroInt32Value JSON parse | 128.09 | — | — | 1214.28 (9.48x) | 266.89 (2.08x) |
| NegativeInt32Value JSON stringify | 48.72 | — | — | 643.32 (13.20x) | 146.38 (3.00x) |
| NegativeInt32Value JSON parse | 132.04 | — | — | 1230.50 (9.32x) | 552.16 (4.18x) |
| MinInt32Value JSON stringify | 49.46 | — | — | 641.77 (12.98x) | 131.96 (2.67x) |
| MinInt32Value JSON parse | 137.43 | — | — | 1212.12 (8.82x) | 350.31 (2.55x) |
| MaxInt32Value JSON stringify | 49.41 | — | — | 637.55 (12.90x) | 138.40 (2.80x) |
| MaxInt32Value JSON parse | 138.49 | — | — | 1203.54 (8.69x) | 334.22 (2.41x) |
| UInt32Value JSON stringify | 48.65 | — | — | 642.22 (13.20x) | 137.29 (2.82x) |
| UInt32Value JSON parse | 132.41 | — | — | 1179.60 (8.91x) | 311.16 (2.35x) |
| UInt32Value String JSON parse | 139.28 | — | — | 1120.60 (8.05x) | 404.34 (2.90x) |
| UInt32Value Exponent JSON parse | 136.25 | — | — | 1218.53 (8.94x) | 372.73 (2.74x) |
| ZeroUInt32Value JSON stringify | 46.36 | — | — | 633.83 (13.67x) | 133.44 (2.88x) |
| ZeroUInt32Value JSON parse | 128.49 | — | — | 1168.17 (9.09x) | 266.07 (2.07x) |
| MaxUInt32Value JSON stringify | 49.39 | — | — | 650.41 (13.17x) | 137.77 (2.79x) |
| MaxUInt32Value JSON parse | 138.17 | — | — | 1211.99 (8.77x) | 345.66 (2.50x) |
| BoolValue JSON stringify | 44.05 | — | — | 609.72 (13.84x) | 126.60 (2.87x) |
| BoolValue JSON parse | 60.52 | — | — | 1050.70 (17.36x) | 221.14 (3.65x) |
| FalseBoolValue JSON stringify | 44.07 | — | — | 600.10 (13.62x) | 124.26 (2.82x) |
| FalseBoolValue JSON parse | 60.39 | — | — | 1054.33 (17.46x) | 222.93 (3.69x) |
| StringValue JSON stringify | 56.83 | — | — | 673.81 (11.86x) | 182.85 (3.22x) |
| StringValue JSON parse | 122.10 | — | — | 1148.42 (9.41x) | 323.77 (2.65x) |
| StringValue Escape JSON parse | 132.56 | — | — | 1172.85 (8.85x) | 375.55 (2.83x) |
| EmptyStringValue JSON stringify | 51.83 | — | — | 643.15 (12.41x) | 187.38 (3.62x) |
| EmptyStringValue JSON parse | 67.41 | — | — | 1116.64 (16.56x) | 229.36 (3.40x) |
| BytesValue JSON stringify | 49.97 | — | — | 655.57 (13.12x) | 211.30 (4.23x) |
| BytesValue JSON parse | 135.26 | — | — | 1166.27 (8.62x) | 357.54 (2.64x) |
| BytesValue URL JSON parse | 149.66 | — | — | 1156.83 (7.73x) | 338.31 (2.26x) |
| BytesValue StandardBase64 JSON parse | 132.55 | — | — | 1171.66 (8.84x) | 358.39 (2.70x) |
| BytesValue Unpadded JSON parse | 131.76 | — | — | 1152.59 (8.75x) | 346.03 (2.63x) |
| EmptyBytesValue JSON stringify | 41.64 | — | — | 631.10 (15.16x) | 201.27 (4.83x) |
| EmptyBytesValue JSON parse | 74.94 | — | — | 1120.85 (14.96x) | 289.86 (3.87x) |
| TextFormat format | 183.27 | — | — | 2562.48 (13.98x) | 2545.93 (13.89x) |
| TextFormat parse | 738.65 | — | — | 4976.94 (6.74x) | 6553.17 (8.87x) |
| packed fixed32 encode | 2.01 | 550.61 (273.94x) | 539.33 (268.32x) | 43.85 (21.82x) | 409.96 (203.96x) |
| packed fixed32 decode | 4.53 | 1057.25 (233.39x) | 1890.80 (417.40x) | 49.54 (10.94x) | 1548.96 (341.93x) |
| packed fixed64 encode | 2.01 | 572.52 (284.84x) | 560.94 (279.07x) | 76.07 (37.85x) | 393.57 (195.81x) |
| packed fixed64 decode | 4.53 | 1035.54 (228.60x) | 7936.15 (1751.91x) | 80.05 (17.67x) | 2174.22 (479.96x) |
| packed sfixed32 encode | 2.91 | 553.91 (190.35x) | 539.41 (185.36x) | 43.66 (15.00x) | 422.14 (145.07x) |
| packed sfixed32 decode | 8.93 | 1058.43 (118.53x) | 1919.76 (214.98x) | 48.95 (5.48x) | 1537.56 (172.18x) |
| packed sfixed64 encode | 2.01 | 571.09 (284.12x) | 561.00 (279.10x) | 75.81 (37.71x) | 398.34 (198.18x) |
| packed sfixed64 decode | 4.54 | 1018.56 (224.35x) | 7907.92 (1741.83x) | 79.04 (17.41x) | 2162.85 (476.40x) |
| packed float encode | 2.01 | 810.27 (403.12x) | 541.41 (269.36x) | 43.38 (21.58x) | 361.35 (179.78x) |
| packed float decode | 4.53 | 1048.95 (231.56x) | 2026.01 (447.24x) | 48.47 (10.70x) | 1539.02 (339.74x) |
| packed double encode | 2.01 | 830.47 (413.17x) | 563.19 (280.19x) | 75.78 (37.70x) | 356.46 (177.34x) |
| packed double decode | 4.52 | 970.56 (214.73x) | 2059.30 (455.60x) | 79.27 (17.54x) | 2169.88 (480.06x) |
| packed uint64 encode | 1291.63 | 4616.67 (3.57x) | 4015.52 (3.11x) | 2161.81 (1.67x) | 3457.57 (2.68x) |
| packed uint64 decode | 1779.90 | 2781.12 (1.56x) | 8869.09 (4.98x) | 2806.29 (1.58x) | 6276.76 (3.53x) |
| packed uint32 encode | 924.49 | 3626.29 (3.92x) | 3249.37 (3.51x) | 1735.87 (1.88x) | 2875.02 (3.11x) |
| packed uint32 decode | 1321.82 | 2428.13 (1.84x) | 3255.08 (2.46x) | 1995.09 (1.51x) | 4693.37 (3.55x) |
| packed int64 encode | 1394.65 | 10937.83 (7.84x) | 6062.41 (4.35x) | 2892.25 (2.07x) | 4128.76 (2.96x) |
| packed int64 decode | 2760.50 | 3365.47 (1.22x) | 10275.49 (3.72x) | 4754.38 (1.72x) | 7737.69 (2.80x) |
| packed sint32 encode | 845.79 | 3033.06 (3.59x) | 2790.11 (3.30x) | 1525.33 (1.80x) | 3385.76 (4.00x) |
| packed sint32 decode | 952.92 | 2546.43 (2.67x) | 3176.89 (3.33x) | 1128.06 (1.18x) | 3033.83 (3.18x) |
| packed sint64 encode | 1437.50 | 4941.85 (3.44x) | 4282.31 (2.98x) | 2422.91 (1.69x) | 4139.28 (2.88x) |
| packed sint64 decode | 2040.88 | 3070.48 (1.50x) | 9646.65 (4.73x) | 2932.73 (1.44x) | 6514.21 (3.19x) |
| packed bool encode | 2.01 | 1327.79 (660.59x) | 519.25 (258.33x) | 16.20 (8.06x) | 2276.40 (1132.54x) |
| packed bool decode | 262.78 | 1517.60 (5.78x) | 2553.88 (9.72x) | 804.15 (3.06x) | 1570.66 (5.98x) |
| packed enum encode | 275.24 | 2717.54 (9.87x) | 1817.55 (6.60x) | 1079.00 (3.92x) | 2487.52 (9.04x) |
| packed enum decode | 159.83 | 1550.85 (9.70x) | 2879.68 (18.02x) | 710.14 (4.44x) | 1990.43 (12.45x) |
| large map encode | 4024.80 | 16543.87 (4.11x) | 9753.50 (2.42x) | 20740.10 (5.15x) | 209127.14 (51.96x) |
| shuffled large map deterministic binary encode | 27770.57 | — | — | 88357.70 (3.18x) | 442199.17 (15.92x) |
| large map decode | 25726.83 | 91016.26 (3.54x) | 89514.00 (3.48x) | 91787.00 (3.57x) | 278901.15 (10.84x) |
The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound `Duration`, non-empty/escaped-input parse/number-exponent parse and empty `Struct`, object/escaped-object parse/object-number-exponent/list/escaped-list/string-scalar/escaped-string-scalar/number-exponent/negative-number `Value` (including default-like scalar and empty object/list kinds),
`FieldMask` (non-empty, escaped JSON parse input, and empty), escaped-input parse/short-fraction parse/micro/nano/offset/min/pre/post/max-bound `Timestamp`, `Empty`, min/zero/positive/number-input parse/numeric-exponent parse/negative/max `Int64Value`, negative/zero/positive finite/string-input parse/numeric-exponent parse `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), negative/zero/positive finite/string-input parse/numeric-exponent parse `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), zero/normal/number-input parse/numeric-exponent parse/max `UInt64Value`, min/zero/positive/string-input parse/numeric-exponent parse/negative/max `Int32Value`, zero/normal/string-input parse/numeric-exponent parse/max `UInt32Value`, true/false `BoolValue`, non-empty/escape-input parse/empty `StringValue`, padded-standard/base64url/unpadded-base64 parse/empty `BytesValue`, and recursive nested `Any` payloads), direct zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound Duration, non-empty/escaped-input parse/empty FieldMask, and escaped-input parse/short-fraction parse/micro/nano/offset/min/pre/post/max-bound Timestamp WKT JSON plus other direct WKT JSON, including non-empty/escaped-input parse/number-exponent parse/empty `Struct`, object/escaped-object parse/object-number-exponent/list/escaped-list/string-scalar/escaped-string-scalar/number-exponent/negative-number `Value`, and escaped/non-empty/empty `ListValue`, TextFormat, packed scalars, large bytes,
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
