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

Latest accepted comparison (`/tmp/pbz-compare-struct-value-surrogate-json-final.log`,
summarized in `/tmp/pbz-summary-struct-value-surrogate-json-final.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 27.77 | 142.60 (5.14x) | 72.01 (2.59x) | 100.70 (3.63x) | 871.20 (31.37x) |
| binary decode | 152.56 | 246.27 (1.61x) | 396.69 (2.60x) | 213.72 (1.40x) | 914.12 (5.99x) |
| unknown fields count by number | 3.61 | — | — | 160.55 (44.47x) | — |
| deterministic binary encode | 86.07 | — | — | 127.79 (1.48x) | 1137.36 (13.21x) |
| scalarmix encode | 29.05 | 107.38 (3.70x) | 89.14 (3.07x) | 29.83 (1.03x) | 213.10 (7.34x) |
| scalarmix decode | 56.17 | 133.74 (2.38x) | 293.02 (5.22x) | 86.33 (1.54x) | 306.56 (5.46x) |
| textbytes encode | 16.39 | 84.91 (5.18x) | 55.06 (3.36x) | 122.03 (7.45x) | 150.78 (9.20x) |
| textbytes decode | 68.45 | 381.79 (5.58x) | 336.01 (4.91x) | 164.19 (2.40x) | 673.13 (9.83x) |
| largebytes encode | 25.82 | 2704.93 (104.76x) | 2740.19 (106.13x) | 2681.23 (103.84x) | 2699.00 (104.53x) |
| largebytes decode | 88.72 | 5675.42 (63.97x) | 3714.09 (41.86x) | 2744.26 (30.93x) | 20934.92 (235.97x) |
| presencemix encode | 18.29 | 80.25 (4.39x) | 52.43 (2.87x) | 56.34 (3.08x) | 235.01 (12.85x) |
| presencemix decode | 55.85 | 181.05 (3.24x) | 148.50 (2.66x) | 160.92 (2.88x) | 492.10 (8.81x) |
| complex encode | 48.27 | 142.23 (2.95x) | 139.54 (2.89x) | 164.29 (3.40x) | 924.36 (19.15x) |
| complex decode | 183.14 | 401.28 (2.19x) | 570.96 (3.12x) | 391.93 (2.14x) | 2626.23 (14.34x) |
| complex deterministic binary encode | 95.35 | — | — | 170.00 (1.78x) | 1222.30 (12.82x) |
| complex JSON stringify | 268.28 | — | — | 4892.45 (18.24x) | 11639.72 (43.39x) |
| complex JSON parse | 2378.38 | — | — | 11909.10 (5.01x) | 14498.10 (6.10x) |
| complex TextFormat format | 253.51 | — | — | 3767.85 (14.86x) | 10304.48 (40.65x) |
| complex TextFormat parse | 1887.03 | — | — | 6945.65 (3.68x) | 8520.24 (4.52x) |
| packed int32 encode | 632.32 | 3159.38 (5.00x) | 4211.14 (6.66x) | 1238.23 (1.96x) | 2748.61 (4.35x) |
| packed int32 decode | 698.13 | 1909.08 (2.73x) | 4869.75 (6.98x) | 960.47 (1.38x) | 2789.53 (4.00x) |
| JSON stringify | 148.31 | — | — | 3006.43 (20.27x) | 2338.76 (15.77x) |
| JSON parse | 1535.23 | — | — | 7456.03 (4.86x) | 4720.18 (3.07x) |
| Any WKT JSON stringify | 138.35 | — | — | 3794.80 (27.43x) | 995.03 (7.19x) |
| Any WKT JSON parse | 531.34 | — | — | 5702.34 (10.73x) | 1521.84 (2.86x) |
| Any Duration Escape WKT JSON parse | 545.92 | — | — | 5876.15 (10.76x) | 1613.19 (2.95x) |
| Any PlusDuration WKT JSON parse | 530.88 | — | — | 5756.84 (10.84x) | 1545.66 (2.91x) |
| Any ShortFractionDuration WKT JSON parse | 527.76 | — | — | 8704.30 (16.49x) | 1522.55 (2.88x) |
| Any MicroDuration WKT JSON stringify | 132.84 | — | — | 2047.04 (15.41x) | 995.28 (7.49x) |
| Any MicroDuration WKT JSON parse | 530.30 | — | — | 2999.91 (5.66x) | 1527.97 (2.88x) |
| Any NanoDuration WKT JSON stringify | 134.64 | — | — | 1917.70 (14.24x) | 979.37 (7.27x) |
| Any NanoDuration WKT JSON parse | 545.91 | — | — | 3003.67 (5.50x) | 1535.99 (2.81x) |
| Any NegativeDuration WKT JSON stringify | 140.38 | — | — | 1934.90 (13.78x) | 1013.54 (7.22x) |
| Any NegativeDuration WKT JSON parse | 535.85 | — | — | 3094.49 (5.77x) | 1561.26 (2.91x) |
| Any FractionalNegativeDuration WKT JSON stringify | 131.49 | — | — | 1882.36 (14.32x) | 994.77 (7.57x) |
| Any FractionalNegativeDuration WKT JSON parse | 528.03 | — | — | 3039.15 (5.76x) | 1512.65 (2.86x) |
| Any MaxDuration WKT JSON stringify | 119.81 | — | — | 1740.08 (14.52x) | 996.11 (8.31x) |
| Any MaxDuration WKT JSON parse | 542.91 | — | — | 2956.02 (5.44x) | 1532.41 (2.82x) |
| Any MinDuration WKT JSON stringify | 122.30 | — | — | 1758.81 (14.38x) | 1008.51 (8.25x) |
| Any MinDuration WKT JSON parse | 543.72 | — | — | 3034.28 (5.58x) | 1536.07 (2.83x) |
| Any ZeroDuration WKT JSON stringify | 104.23 | — | — | 909.08 (8.72x) | 943.74 (9.05x) |
| Any ZeroDuration WKT JSON parse | 473.75 | — | — | 2239.28 (4.73x) | 1428.12 (3.01x) |
| Any FieldMask WKT JSON stringify | 226.60 | — | — | 1745.25 (7.70x) | 1407.90 (6.21x) |
| Any FieldMask WKT JSON parse | 741.23 | — | — | 3183.60 (4.30x) | 2083.20 (2.81x) |
| Any FieldMask Escape WKT JSON parse | 750.63 | — | — | 3250.49 (4.33x) | 2230.07 (2.97x) |
| Any EmptyFieldMask WKT JSON stringify | 111.72 | — | — | 916.16 (8.20x) | 782.32 (7.00x) |
| Any EmptyFieldMask WKT JSON parse | 453.15 | — | — | 2157.55 (4.76x) | 1303.36 (2.88x) |
| Any Timestamp WKT JSON stringify | 177.68 | — | — | 2030.80 (11.43x) | 1011.65 (5.69x) |
| Any Timestamp WKT JSON parse | 580.06 | — | — | 3035.46 (5.23x) | 1590.89 (2.74x) |
| Any Timestamp Escape WKT JSON parse | 594.41 | — | — | 3077.90 (5.18x) | 1748.73 (2.94x) |
| Any ShortFraction Timestamp WKT JSON parse | 573.63 | — | — | 3022.85 (5.27x) | 1593.01 (2.78x) |
| Any Micro Timestamp WKT JSON stringify | 173.05 | — | — | 2035.43 (11.76x) | 1005.20 (5.81x) |
| Any Micro Timestamp WKT JSON parse | 709.28 | — | — | 3042.99 (4.29x) | 1616.25 (2.28x) |
| Any Nano Timestamp WKT JSON stringify | 372.04 | — | — | 2043.31 (5.49x) | 1021.94 (2.75x) |
| Any Nano Timestamp WKT JSON parse | 987.42 | — | — | 3055.00 (3.09x) | 1614.12 (1.63x) |
| Any Offset Timestamp WKT JSON parse | 996.76 | — | — | 3076.36 (3.09x) | 1661.41 (1.67x) |
| Any PreEpoch Timestamp WKT JSON stringify | 289.49 | — | — | 1951.27 (6.74x) | 979.01 (3.38x) |
| Any PreEpoch Timestamp WKT JSON parse | 942.62 | — | — | 3056.07 (3.24x) | 1574.60 (1.67x) |
| Any Max Timestamp WKT JSON stringify | 336.75 | — | — | 2053.33 (6.10x) | 1026.64 (3.05x) |
| Any Max Timestamp WKT JSON parse | 992.06 | — | — | 3106.52 (3.13x) | 1640.78 (1.65x) |
| Any Min Timestamp WKT JSON stringify | 341.95 | — | — | 1940.67 (5.68x) | 974.06 (2.85x) |
| Any Min Timestamp WKT JSON parse | 785.02 | — | — | 3037.76 (3.87x) | 1572.96 (2.00x) |
| Any Empty WKT JSON stringify | 148.65 | — | — | 914.79 (6.15x) | 625.65 (4.21x) |
| Any Empty WKT JSON parse | 509.77 | — | — | 2131.31 (4.18x) | 1371.04 (2.69x) |
| Any Struct WKT JSON stringify | 983.10 | — | — | 5780.72 (5.88x) | 6026.27 (6.13x) |
| Any Struct WKT JSON parse | 1746.34 | — | — | 11045.30 (6.32x) | 8734.56 (5.00x) |
| Any Struct Escape WKT JSON parse | 1775.02 | — | — | 11179.00 (6.30x) | 8876.42 (5.00x) |
| Any Struct NumberExponent WKT JSON parse | 1747.97 | — | — | 11115.00 (6.36x) | 8750.46 (5.01x) |
| Any Struct Surrogate WKT JSON parse | 770.73 | — | — | 6385.32 (8.28x) | 3085.30 (4.00x) |
| Any EmptyStruct WKT JSON stringify | 118.59 | — | — | 929.73 (7.84x) | 943.42 (7.96x) |
| Any EmptyStruct WKT JSON parse | 445.25 | — | — | 2236.72 (5.02x) | 1597.49 (3.59x) |
| Any Value WKT JSON stringify | 653.65 | — | — | 5905.65 (9.03x) | 6342.44 (9.70x) |
| Any Value WKT JSON parse | 1796.24 | — | — | 11315.50 (6.30x) | 9106.22 (5.07x) |
| Any Value Escape WKT JSON parse | 1829.95 | — | — | 11455.60 (6.26x) | 9258.25 (5.06x) |
| Any Value NumberExponent WKT JSON parse | 1807.34 | — | — | 11399.60 (6.31x) | 9141.26 (5.06x) |
| Any Value Surrogate WKT JSON parse | 829.25 | — | — | 6562.81 (7.91x) | 3472.63 (4.19x) |
| Any NullValue WKT JSON stringify | 127.05 | — | — | 2246.67 (17.68x) | 916.44 (7.21x) |
| Any NullValue WKT JSON parse | 471.56 | — | — | 4043.92 (8.58x) | 1556.35 (3.30x) |
| Any StringScalarValue WKT JSON stringify | 152.95 | — | — | 2295.01 (15.00x) | 996.44 (6.51x) |
| Any StringScalarValue WKT JSON parse | 527.22 | — | — | 3614.15 (6.86x) | 1661.37 (3.15x) |
| Any StringScalarValue Escape WKT JSON parse | 537.53 | — | — | 3657.59 (6.80x) | 1732.27 (3.22x) |
| Any StringScalarValue Surrogate WKT JSON parse | 543.13 | — | — | 3665.70 (6.75x) | 1740.64 (3.20x) |
| Any EmptyStringScalarValue WKT JSON stringify | 139.30 | — | — | 2292.19 (16.46x) | 943.64 (6.77x) |
| Any EmptyStringScalarValue WKT JSON parse | 496.92 | — | — | 3605.34 (7.26x) | 1576.55 (3.17x) |
| Any NumberValue WKT JSON stringify | 173.97 | — | — | 2532.21 (14.56x) | 1036.16 (5.96x) |
| Any NumberValue WKT JSON parse | 513.98 | — | — | 3681.36 (7.16x) | 1596.71 (3.11x) |
| Any NumberValue Exponent WKT JSON parse | 518.11 | — | — | 3682.68 (7.11x) | 1620.78 (3.13x) |
| Any NegativeNumberValue WKT JSON stringify | 174.63 | — | — | 2523.06 (14.45x) | 1034.85 (5.93x) |
| Any NegativeNumberValue WKT JSON parse | 511.99 | — | — | 3685.33 (7.20x) | 1600.94 (3.13x) |
| Any ZeroNumberValue WKT JSON stringify | 134.88 | — | — | 2474.20 (18.34x) | 939.67 (6.97x) |
| Any ZeroNumberValue WKT JSON parse | 510.69 | — | — | 3615.10 (7.08x) | 1619.09 (3.17x) |
| Any BoolScalarValue WKT JSON stringify | 130.69 | — | — | 2274.89 (17.41x) | 912.87 (6.99x) |
| Any BoolScalarValue WKT JSON parse | 470.30 | — | — | 3673.38 (7.81x) | 1528.95 (3.25x) |
| Any FalseBoolScalarValue WKT JSON stringify | 128.30 | — | — | 4402.52 (34.31x) | 909.74 (7.09x) |
| Any FalseBoolScalarValue WKT JSON parse | 470.53 | — | — | 6433.94 (13.67x) | 1535.14 (3.26x) |
| Any ListKindValue WKT JSON stringify | 506.67 | — | — | 10490.50 (20.70x) | 4702.04 (9.28x) |
| Any ListKindValue WKT JSON parse | 1397.02 | — | — | 13895.10 (9.95x) | 7683.64 (5.50x) |
| Any ListKindValue Escape WKT JSON parse | 1430.75 | — | — | 9967.61 (6.97x) | 7305.82 (5.11x) |
| Any EmptyStructKindValue WKT JSON stringify | 148.08 | — | — | 2910.15 (19.65x) | 1276.43 (8.62x) |
| Any EmptyStructKindValue WKT JSON parse | 511.95 | — | — | 5398.09 (10.54x) | 1938.45 (3.79x) |
| Any EmptyListKindValue WKT JSON stringify | 144.53 | — | — | 2890.95 (20.00x) | 1088.27 (7.53x) |
| Any EmptyListKindValue WKT JSON parse | 510.85 | — | — | 4371.33 (8.56x) | 1820.54 (3.56x) |
| Any DoubleValue WKT JSON stringify | 192.19 | — | — | 1792.11 (9.32x) | 803.49 (4.18x) |
| Any DoubleValue WKT JSON parse | 531.09 | — | — | 2721.40 (5.12x) | 1448.21 (2.73x) |
| Any DoubleValue String WKT JSON parse | 539.12 | — | — | 2740.95 (5.08x) | 1523.67 (2.83x) |
| Any DoubleValue Exponent WKT JSON parse | 535.28 | — | — | 2758.77 (5.15x) | 1460.31 (2.73x) |
| Any NegativeDoubleValue WKT JSON stringify | 189.85 | — | — | 1814.27 (9.56x) | 805.09 (4.24x) |
| Any NegativeDoubleValue WKT JSON parse | 529.88 | — | — | 2734.45 (5.16x) | 1447.66 (2.73x) |
| Any ZeroDoubleValue WKT JSON stringify | 159.07 | — | — | 915.20 (5.75x) | 732.80 (4.61x) |
| Any ZeroDoubleValue WKT JSON parse | 529.18 | — | — | 2172.13 (4.10x) | 1362.08 (2.57x) |
| Any DoubleValue NaN WKT JSON stringify | 152.42 | — | — | 1566.59 (10.28x) | 719.02 (4.72x) |
| Any DoubleValue NaN WKT JSON parse | 525.99 | — | — | 2644.65 (5.03x) | 1402.27 (2.67x) |
| Any DoubleValue Infinity WKT JSON stringify | 161.83 | — | — | 1559.52 (9.64x) | 722.66 (4.47x) |
| Any DoubleValue Infinity WKT JSON parse | 527.03 | — | — | 2667.12 (5.06x) | 1411.99 (2.68x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 158.49 | — | — | 1554.79 (9.81x) | 734.70 (4.64x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 531.26 | — | — | 2663.11 (5.01x) | 1450.17 (2.73x) |
| Any FloatValue WKT JSON stringify | 195.51 | — | — | 1733.53 (8.87x) | 780.38 (3.99x) |
| Any FloatValue WKT JSON parse | 532.81 | — | — | 2704.33 (5.08x) | 1442.98 (2.71x) |
| Any FloatValue String WKT JSON parse | 537.32 | — | — | 2701.77 (5.03x) | 1552.11 (2.89x) |
| Any FloatValue Exponent WKT JSON parse | 533.81 | — | — | 2711.41 (5.08x) | 1464.61 (2.74x) |
| Any NegativeFloatValue WKT JSON stringify | 188.93 | — | — | 1730.49 (9.16x) | 791.75 (4.19x) |
| Any NegativeFloatValue WKT JSON parse | 530.55 | — | — | 2700.94 (5.09x) | 1439.36 (2.71x) |
| Any ZeroFloatValue WKT JSON stringify | 158.19 | — | — | 914.11 (5.78x) | 736.38 (4.66x) |
| Any ZeroFloatValue WKT JSON parse | 527.14 | — | — | 2153.82 (4.09x) | 1389.36 (2.64x) |
| Any FloatValue NaN WKT JSON stringify | 154.10 | — | — | 1564.54 (10.15x) | 712.89 (4.63x) |
| Any FloatValue NaN WKT JSON parse | 522.13 | — | — | 2622.93 (5.02x) | 1372.51 (2.63x) |
| Any FloatValue Infinity WKT JSON stringify | 167.72 | — | — | 1541.55 (9.19x) | 711.59 (4.24x) |
| Any FloatValue Infinity WKT JSON parse | 529.00 | — | — | 2648.35 (5.01x) | 1425.09 (2.69x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 165.51 | — | — | 1538.88 (9.30x) | 711.87 (4.30x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 532.32 | — | — | 2639.14 (4.96x) | 1389.06 (2.61x) |
| Any Int64Value WKT JSON stringify | 171.61 | — | — | 1554.78 (9.06x) | 861.17 (5.02x) |
| Any Int64Value WKT JSON parse | 563.28 | — | — | 2781.17 (4.94x) | 1625.65 (2.89x) |
| Any Int64Value Number WKT JSON parse | 561.63 | — | — | 2750.82 (4.90x) | 1545.19 (2.75x) |
| Any Int64Value Exponent WKT JSON parse | 544.90 | — | — | 2709.95 (4.97x) | 1513.43 (2.78x) |
| Any ZeroInt64Value WKT JSON stringify | 152.87 | — | — | 914.79 (5.98x) | 778.43 (5.09x) |
| Any ZeroInt64Value WKT JSON parse | 533.67 | — | — | 2156.33 (4.04x) | 1470.23 (2.75x) |
| Any NegativeInt64Value WKT JSON stringify | 171.75 | — | — | 1557.36 (9.07x) | 851.64 (4.96x) |
| Any NegativeInt64Value WKT JSON parse | 570.95 | — | — | 2796.77 (4.90x) | 1624.19 (2.84x) |
| Any MinInt64Value WKT JSON stringify | 175.10 | — | — | 1561.76 (8.92x) | 867.78 (4.96x) |
| Any MinInt64Value WKT JSON parse | 580.16 | — | — | 2819.24 (4.86x) | 1805.68 (3.11x) |
| Any MaxInt64Value WKT JSON stringify | 175.82 | — | — | 1558.27 (8.86x) | 861.04 (4.90x) |
| Any MaxInt64Value WKT JSON parse | 571.70 | — | — | 2802.47 (4.90x) | 1669.24 (2.92x) |
| Any UInt64Value WKT JSON stringify | 177.94 | — | — | 1553.50 (8.73x) | 871.94 (4.90x) |
| Any UInt64Value WKT JSON parse | 572.19 | — | — | 2803.01 (4.90x) | 1621.20 (2.83x) |
| Any UInt64Value Number WKT JSON parse | 567.68 | — | — | 2770.49 (4.88x) | 1545.87 (2.72x) |
| Any UInt64Value Exponent WKT JSON parse | 551.15 | — | — | 2705.48 (4.91x) | 1497.70 (2.72x) |
| Any ZeroUInt64Value WKT JSON stringify | 165.59 | — | — | 915.14 (5.53x) | 773.22 (4.67x) |
| Any ZeroUInt64Value WKT JSON parse | 536.66 | — | — | 2147.34 (4.00x) | 1470.98 (2.74x) |
| Any MaxUInt64Value WKT JSON stringify | 179.13 | — | — | 1565.12 (8.74x) | 865.06 (4.83x) |
| Any MaxUInt64Value WKT JSON parse | 581.51 | — | — | 2854.60 (4.91x) | 1666.27 (2.87x) |
| Any Int32Value WKT JSON stringify | 165.37 | — | — | 1549.63 (9.37x) | 748.04 (4.52x) |
| Any Int32Value WKT JSON parse | 546.30 | — | — | 2660.24 (4.87x) | 1429.52 (2.62x) |
| Any Int32Value String WKT JSON parse | 551.68 | — | — | 2679.91 (4.86x) | 1536.97 (2.79x) |
| Any Int32Value Exponent WKT JSON parse | 553.56 | — | — | 2694.61 (4.87x) | 1520.89 (2.75x) |
| Any ZeroInt32Value WKT JSON stringify | 164.91 | — | — | 916.88 (5.56x) | 720.03 (4.37x) |
| Any ZeroInt32Value WKT JSON parse | 542.42 | — | — | 2151.16 (3.97x) | 1398.54 (2.58x) |
| Any NegativeInt32Value WKT JSON stringify | 173.55 | — | — | 1556.38 (8.97x) | 744.58 (4.29x) |
| Any NegativeInt32Value WKT JSON parse | 549.28 | — | — | 2695.62 (4.91x) | 1453.77 (2.65x) |
| Any MinInt32Value WKT JSON stringify | 170.40 | — | — | 1554.59 (9.12x) | 735.81 (4.32x) |
| Any MinInt32Value WKT JSON parse | 555.29 | — | — | 2713.00 (4.89x) | 1484.59 (2.67x) |
| Any MaxInt32Value WKT JSON stringify | 174.73 | — | — | 1544.54 (8.84x) | 734.81 (4.21x) |
| Any MaxInt32Value WKT JSON parse | 557.22 | — | — | 2669.29 (4.79x) | 1466.56 (2.63x) |
| Any UInt32Value WKT JSON stringify | 174.90 | — | — | 1551.89 (8.87x) | 735.03 (4.20x) |
| Any UInt32Value WKT JSON parse | 550.03 | — | — | 2668.74 (4.85x) | 1457.97 (2.65x) |
| Any UInt32Value String WKT JSON parse | 557.36 | — | — | 2662.97 (4.78x) | 1537.94 (2.76x) |
| Any UInt32Value Exponent WKT JSON parse | 553.97 | — | — | 2699.00 (4.87x) | 1486.47 (2.68x) |
| Any ZeroUInt32Value WKT JSON stringify | 174.01 | — | — | 1764.48 (10.14x) | 720.36 (4.14x) |
| Any ZeroUInt32Value WKT JSON parse | 545.81 | — | — | 3824.98 (7.01x) | 1401.59 (2.57x) |
| Any MaxUInt32Value WKT JSON stringify | 180.24 | — | — | 3159.71 (17.53x) | 739.22 (4.10x) |
| Any MaxUInt32Value WKT JSON parse | 560.06 | — | — | 5134.13 (9.17x) | 1470.90 (2.63x) |
| Any BoolValue WKT JSON stringify | 164.85 | — | — | 3148.64 (19.10x) | 749.33 (4.55x) |
| Any BoolValue WKT JSON parse | 501.33 | — | — | 4988.14 (9.95x) | 1348.49 (2.69x) |
| Any FalseBoolValue WKT JSON stringify | 168.44 | — | — | 1725.29 (10.24x) | 718.17 (4.26x) |
| Any FalseBoolValue WKT JSON parse | 496.37 | — | — | 3401.22 (6.85x) | 1345.18 (2.71x) |
| Any StringValue WKT JSON stringify | 193.76 | — | — | 1551.99 (8.01x) | 789.61 (4.08x) |
| Any StringValue WKT JSON parse | 556.93 | — | — | 2656.26 (4.77x) | 1399.34 (2.51x) |
| Any StringValue Escape WKT JSON parse | 560.56 | — | — | 2687.36 (4.79x) | 1534.03 (2.74x) |
| Any StringValue Surrogate WKT JSON parse | 571.12 | — | — | 2693.07 (4.72x) | 1537.74 (2.69x) |
| Any EmptyStringValue WKT JSON stringify | 189.57 | — | — | 917.53 (4.84x) | 760.30 (4.01x) |
| Any EmptyStringValue WKT JSON parse | 527.94 | — | — | 2158.94 (4.09x) | 1354.49 (2.57x) |
| Any BytesValue WKT JSON stringify | 187.28 | — | — | 1574.46 (8.41x) | 841.39 (4.49x) |
| Any BytesValue WKT JSON parse | 573.69 | — | — | 2687.26 (4.68x) | 1465.14 (2.55x) |
| Any BytesValue URL WKT JSON parse | 589.32 | — | — | 2676.65 (4.54x) | 1499.32 (2.54x) |
| Any BytesValue StandardBase64 WKT JSON parse | 574.17 | — | — | 2702.16 (4.71x) | 1506.94 (2.62x) |
| Any BytesValue Unpadded WKT JSON parse | 573.76 | — | — | 2678.92 (4.67x) | 1504.39 (2.62x) |
| Any EmptyBytesValue WKT JSON stringify | 179.10 | — | — | 910.48 (5.08x) | 777.73 (4.34x) |
| Any EmptyBytesValue WKT JSON parse | 533.64 | — | — | 2152.97 (4.03x) | 1425.23 (2.67x) |
| Nested Any WKT JSON stringify | 287.84 | — | — | 2466.13 (8.57x) | 1438.02 (5.00x) |
| Nested Any WKT JSON parse | 884.46 | — | — | 4285.27 (4.85x) | 2873.63 (3.25x) |
| Duration JSON stringify | 57.67 | — | — | 959.04 (16.63x) | 364.13 (6.31x) |
| Duration JSON parse | 16.98 | — | — | 1451.01 (85.45x) | 395.17 (23.27x) |
| Duration Escape JSON parse | 38.91 | — | — | 1481.35 (38.07x) | 439.93 (11.31x) |
| PlusDuration JSON parse | 16.58 | — | — | 1463.68 (88.28x) | 397.14 (23.95x) |
| ShortFractionDuration JSON parse | 13.81 | — | — | 1421.83 (102.96x) | 385.38 (27.91x) |
| MicroDuration JSON stringify | 59.65 | — | — | 961.92 (16.13x) | 408.17 (6.84x) |
| MicroDuration JSON parse | 17.93 | — | — | 1461.66 (81.52x) | 386.93 (21.58x) |
| NanoDuration JSON stringify | 57.19 | — | — | 996.60 (17.43x) | 412.52 (7.21x) |
| NanoDuration JSON parse | 21.34 | — | — | 1470.06 (68.89x) | 402.66 (18.87x) |
| NegativeDuration JSON stringify | 59.08 | — | — | 1001.88 (16.96x) | 426.83 (7.22x) |
| NegativeDuration JSON parse | 17.45 | — | — | 1503.04 (86.13x) | 389.92 (22.34x) |
| FractionalNegativeDuration JSON stringify | 59.06 | — | — | 964.99 (16.34x) | 426.50 (7.22x) |
| FractionalNegativeDuration JSON parse | 19.94 | — | — | 1455.58 (73.00x) | 375.98 (18.86x) |
| MaxDuration JSON stringify | 49.79 | — | — | 858.12 (17.23x) | 674.87 (13.55x) |
| MaxDuration JSON parse | 28.99 | — | — | 1434.15 (49.47x) | 405.61 (13.99x) |
| MinDuration JSON stringify | 50.00 | — | — | 868.84 (17.38x) | 455.67 (9.11x) |
| MinDuration JSON parse | 29.51 | — | — | 1444.56 (48.95x) | 404.14 (13.70x) |
| ZeroDuration JSON stringify | 44.86 | — | — | 821.62 (18.32x) | 351.29 (7.83x) |
| ZeroDuration JSON parse | 15.53 | — | — | 1359.04 (87.51x) | 317.76 (20.46x) |
| FieldMask JSON stringify | 66.07 | — | — | 880.14 (13.32x) | 654.14 (9.90x) |
| FieldMask JSON parse | 139.40 | — | — | 1668.11 (11.97x) | 895.76 (6.43x) |
| FieldMask Escape JSON parse | 199.76 | — | — | 1727.88 (8.65x) | 971.52 (4.86x) |
| EmptyFieldMask JSON stringify | 40.75 | — | — | 611.04 (14.99x) | 198.18 (4.86x) |
| EmptyFieldMask JSON parse | 4.79 | — | — | 939.35 (196.11x) | 171.78 (35.86x) |
| Timestamp JSON stringify | 95.15 | — | — | 1139.31 (11.97x) | 415.35 (4.37x) |
| Timestamp JSON parse | 45.11 | — | — | 1484.63 (32.91x) | 445.17 (9.87x) |
| Timestamp Escape JSON parse | 93.82 | — | — | 1512.83 (16.12x) | 511.66 (5.45x) |
| ShortFraction Timestamp JSON parse | 43.55 | — | — | 1478.94 (33.96x) | 441.33 (10.13x) |
| Micro Timestamp JSON stringify | 96.26 | — | — | 1136.70 (11.81x) | 417.29 (4.34x) |
| Micro Timestamp JSON parse | 49.85 | — | — | 1501.86 (30.13x) | 463.80 (9.30x) |
| Nano Timestamp JSON stringify | 94.03 | — | — | 1172.29 (12.47x) | 423.65 (4.51x) |
| Nano Timestamp JSON parse | 50.74 | — | — | 1512.28 (29.80x) | 463.09 (9.13x) |
| Offset Timestamp JSON parse | 51.39 | — | — | 1524.89 (29.67x) | 487.57 (9.49x) |
| PreEpoch Timestamp JSON stringify | 66.23 | — | — | 1058.10 (15.98x) | 625.36 (9.44x) |
| PreEpoch Timestamp JSON parse | 43.07 | — | — | 1453.52 (33.75x) | 428.50 (9.95x) |
| Max Timestamp JSON stringify | 79.61 | — | — | 1187.30 (14.91x) | 425.30 (5.34x) |
| Max Timestamp JSON parse | 51.88 | — | — | 1527.03 (29.43x) | 462.85 (8.92x) |
| Min Timestamp JSON stringify | 79.29 | — | — | 1048.96 (13.23x) | 401.55 (5.06x) |
| Min Timestamp JSON parse | 41.11 | — | — | 1451.14 (35.30x) | 421.78 (10.26x) |
| Empty JSON stringify | 20.56 | — | — | 509.36 (24.77x) | 87.98 (4.28x) |
| Empty JSON parse | 67.72 | — | — | 719.08 (10.62x) | 216.77 (3.20x) |
| Struct JSON stringify | 174.34 | — | — | 5730.26 (32.87x) | 3032.88 (17.40x) |
| Struct JSON parse | 840.60 | — | — | 10901.90 (12.97x) | 4658.53 (5.54x) |
| Struct Escape JSON parse | 882.83 | — | — | 10992.70 (12.45x) | 4772.82 (5.41x) |
| Struct NumberExponent JSON parse | 842.23 | — | — | 10924.50 (12.97x) | 5792.49 (6.88x) |
| Struct Surrogate JSON parse | 370.21 | — | — | 4807.83 (12.99x) | 1276.76 (3.45x) |
| EmptyStruct JSON stringify | 41.43 | — | — | 687.12 (16.58x) | 364.18 (8.79x) |
| EmptyStruct JSON parse | 86.49 | — | — | 2036.32 (23.54x) | 427.34 (4.94x) |
| Value JSON stringify | 177.84 | — | — | 6620.41 (37.23x) | 6095.04 (34.27x) |
| Value JSON parse | 863.64 | — | — | 12199.30 (14.13x) | 9523.33 (11.03x) |
| Value Escape JSON parse | 916.97 | — | — | 12224.60 (13.33x) | 6294.93 (6.86x) |
| Value NumberExponent JSON parse | 865.42 | — | — | 12151.10 (14.04x) | 5129.33 (5.93x) |
| Value Surrogate JSON parse | 394.20 | — | — | 6656.10 (16.89x) | 1506.28 (3.82x) |
| NullValue JSON stringify | 40.56 | — | — | 1319.63 (32.54x) | 220.48 (5.44x) |
| NullValue JSON parse | 69.80 | — | — | 2475.45 (35.46x) | 355.05 (5.09x) |
| StringScalarValue JSON stringify | 47.63 | — | — | 1346.69 (28.27x) | 270.68 (5.68x) |
| StringScalarValue JSON parse | 140.77 | — | — | 2096.97 (14.90x) | 440.01 (3.13x) |
| StringScalarValue Escape JSON parse | 151.30 | — | — | 2129.77 (14.08x) | 497.03 (3.29x) |
| StringScalarValue Surrogate JSON parse | 149.94 | — | — | 2132.61 (14.22x) | 500.33 (3.34x) |
| EmptyStringScalarValue JSON stringify | 45.98 | — | — | 1339.24 (29.13x) | 270.84 (5.89x) |
| EmptyStringScalarValue JSON parse | 87.25 | — | — | 2074.20 (23.77x) | 359.74 (4.12x) |
| NumberValue JSON stringify | 72.95 | — | — | 1553.02 (21.29x) | 323.22 (4.43x) |
| NumberValue JSON parse | 132.07 | — | — | 2180.57 (16.51x) | 399.39 (3.02x) |
| NumberValue Exponent JSON parse | 134.08 | — | — | 2194.10 (16.36x) | 427.71 (3.19x) |
| NegativeNumberValue JSON stringify | 74.15 | — | — | 1552.74 (20.94x) | 327.81 (4.42x) |
| NegativeNumberValue JSON parse | 132.34 | — | — | 2183.05 (16.50x) | 411.88 (3.11x) |
| ZeroNumberValue JSON stringify | 50.77 | — | — | 1504.71 (29.64x) | 273.30 (5.38x) |
| ZeroNumberValue JSON parse | 129.77 | — | — | 2118.03 (16.32x) | 379.91 (2.93x) |
| BoolScalarValue JSON stringify | 40.52 | — | — | 1316.75 (32.50x) | 218.62 (5.40x) |
| BoolScalarValue JSON parse | 69.68 | — | — | 2018.38 (28.97x) | 331.80 (4.76x) |
| FalseBoolScalarValue JSON stringify | 40.52 | — | — | 1313.95 (32.43x) | 222.51 (5.49x) |
| FalseBoolScalarValue JSON parse | 70.29 | — | — | 2031.87 (28.91x) | 339.33 (4.83x) |
| ListKindValue JSON stringify | 141.39 | — | — | 6151.05 (43.50x) | 2293.58 (16.22x) |
| ListKindValue JSON parse | 669.62 | — | — | 12272.80 (18.33x) | 4095.23 (6.12x) |
| ListKindValue Escape JSON parse | 690.09 | — | — | 19679.30 (28.52x) | 4337.22 (6.29x) |
| EmptyStructKindValue JSON stringify | 43.18 | — | — | 3777.83 (87.49x) | 537.19 (12.44x) |
| EmptyStructKindValue JSON parse | 110.25 | — | — | 6766.39 (61.37x) | 855.10 (7.76x) |
| EmptyListKindValue JSON stringify | 41.25 | — | — | 1944.13 (47.13x) | 361.17 (8.76x) |
| EmptyListKindValue JSON parse | 147.16 | — | — | 4039.56 (27.45x) | 596.16 (4.05x) |
| ListValue JSON stringify | 145.52 | — | — | 4779.92 (32.85x) | 2117.31 (14.55x) |
| ListValue JSON parse | 654.21 | — | — | 8531.51 (13.04x) | 3808.49 (5.82x) |
| ListValue Escape JSON parse | 675.38 | — | — | 8629.03 (12.78x) | 3965.46 (5.87x) |
| EmptyListValue JSON stringify | 40.33 | — | — | 695.94 (17.26x) | 188.52 (4.67x) |
| EmptyListValue JSON parse | 126.57 | — | — | 2252.77 (17.80x) | 347.97 (2.75x) |
| DoubleValue JSON stringify | 68.17 | — | — | 870.84 (12.77x) | 184.46 (2.71x) |
| DoubleValue JSON parse | 110.67 | — | — | 1220.86 (11.03x) | 298.16 (2.69x) |
| DoubleValue String JSON parse | 111.42 | — | — | 1158.56 (10.40x) | 366.54 (3.29x) |
| DoubleValue Exponent JSON parse | 112.83 | — | — | 1232.81 (10.93x) | 289.36 (2.56x) |
| NegativeDoubleValue JSON stringify | 67.96 | — | — | 874.76 (12.87x) | 186.18 (2.74x) |
| NegativeDoubleValue JSON parse | 111.20 | — | — | 1242.16 (11.17x) | 285.43 (2.57x) |
| ZeroDoubleValue JSON stringify | 47.35 | — | — | 809.44 (17.09x) | 140.62 (2.97x) |
| ZeroDoubleValue JSON parse | 107.95 | — | — | 1167.41 (10.81x) | 266.53 (2.47x) |
| DoubleValue NaN JSON stringify | 46.11 | — | — | 674.28 (14.62x) | 126.89 (2.75x) |
| DoubleValue NaN JSON parse | 105.32 | — | — | 1095.41 (10.40x) | 280.49 (2.66x) |
| DoubleValue Infinity JSON stringify | 47.62 | — | — | 675.44 (14.18x) | 127.09 (2.67x) |
| DoubleValue Infinity JSON parse | 105.90 | — | — | 1104.43 (10.43x) | 274.70 (2.59x) |
| DoubleValue NegativeInfinity JSON stringify | 47.88 | — | — | 667.77 (13.95x) | 131.59 (2.75x) |
| DoubleValue NegativeInfinity JSON parse | 108.00 | — | — | 1104.27 (10.22x) | 291.46 (2.70x) |
| FloatValue JSON stringify | 70.78 | — | — | 811.97 (11.47x) | 192.64 (2.72x) |
| FloatValue JSON parse | 110.02 | — | — | 1213.84 (11.03x) | 290.76 (2.64x) |
| FloatValue String JSON parse | 110.99 | — | — | 1156.98 (10.42x) | 376.78 (3.39x) |
| FloatValue Exponent JSON parse | 112.13 | — | — | 1224.26 (10.92x) | 294.10 (2.62x) |
| NegativeFloatValue JSON stringify | 70.21 | — | — | 807.87 (11.51x) | 243.18 (3.46x) |
| NegativeFloatValue JSON parse | 110.70 | — | — | 1214.83 (10.97x) | 294.48 (2.66x) |
| ZeroFloatValue JSON stringify | 47.18 | — | — | 756.63 (16.04x) | 134.73 (2.86x) |
| ZeroFloatValue JSON parse | 107.13 | — | — | 1149.03 (10.73x) | 260.35 (2.43x) |
| FloatValue NaN JSON stringify | 46.18 | — | — | 650.29 (14.08x) | 128.90 (2.79x) |
| FloatValue NaN JSON parse | 105.12 | — | — | 1082.83 (10.30x) | 277.60 (2.64x) |
| FloatValue Infinity JSON stringify | 48.34 | — | — | 648.95 (13.42x) | 126.25 (2.61x) |
| FloatValue Infinity JSON parse | 106.71 | — | — | 1089.96 (10.21x) | 261.38 (2.45x) |
| FloatValue NegativeInfinity JSON stringify | 47.92 | — | — | 647.97 (13.52x) | 124.58 (2.60x) |
| FloatValue NegativeInfinity JSON parse | 108.60 | — | — | 1092.65 (10.06x) | 272.11 (2.51x) |
| Int64Value JSON stringify | 50.22 | — | — | 687.88 (13.70x) | 280.34 (5.58x) |
| Int64Value JSON parse | 125.07 | — | — | 1225.56 (9.80x) | 463.86 (3.71x) |
| Int64Value Number JSON parse | 129.81 | — | — | 1281.33 (9.87x) | 370.06 (2.85x) |
| Int64Value Exponent JSON parse | 116.54 | — | — | 1221.22 (10.48x) | 361.46 (3.10x) |
| ZeroInt64Value JSON stringify | 41.35 | — | — | 623.64 (15.08x) | 194.02 (4.69x) |
| ZeroInt64Value JSON parse | 106.73 | — | — | 1099.28 (10.30x) | 346.52 (3.25x) |
| NegativeInt64Value JSON stringify | 50.03 | — | — | 686.46 (13.72x) | 276.73 (5.53x) |
| NegativeInt64Value JSON parse | 127.14 | — | — | 1211.20 (9.53x) | 485.83 (3.82x) |
| MinInt64Value JSON stringify | 49.28 | — | — | 730.24 (14.82x) | 294.55 (5.98x) |
| MinInt64Value JSON parse | 133.43 | — | — | 1245.99 (9.34x) | 489.00 (3.66x) |
| MaxInt64Value JSON stringify | 49.12 | — | — | 693.87 (14.13x) | 278.56 (5.67x) |
| MaxInt64Value JSON parse | 134.03 | — | — | 1251.23 (9.34x) | 475.77 (3.55x) |
| UInt64Value JSON stringify | 49.67 | — | — | 673.69 (13.56x) | 283.74 (5.71x) |
| UInt64Value JSON parse | 127.47 | — | — | 1216.17 (9.54x) | 461.89 (3.62x) |
| UInt64Value Number JSON parse | 128.53 | — | — | 1273.60 (9.91x) | 343.77 (2.67x) |
| UInt64Value Exponent JSON parse | 117.07 | — | — | 1224.55 (10.46x) | 353.05 (3.02x) |
| ZeroUInt64Value JSON stringify | 41.23 | — | — | 610.46 (14.81x) | 194.05 (4.71x) |
| ZeroUInt64Value JSON parse | 107.16 | — | — | 1093.52 (10.20x) | 326.20 (3.04x) |
| MaxUInt64Value JSON stringify | 49.93 | — | — | 682.83 (13.68x) | 285.37 (5.72x) |
| MaxUInt64Value JSON parse | 139.09 | — | — | 1255.77 (9.03x) | 473.90 (3.41x) |
| Int32Value JSON stringify | 46.72 | — | — | 645.69 (13.82x) | 139.13 (2.98x) |
| Int32Value JSON parse | 132.19 | — | — | 1180.19 (8.93x) | 319.05 (2.41x) |
| Int32Value String JSON parse | 134.81 | — | — | 1126.42 (8.36x) | 417.74 (3.10x) |
| Int32Value Exponent JSON parse | 134.95 | — | — | 1222.13 (9.06x) | 662.95 (4.91x) |
| ZeroInt32Value JSON stringify | 46.66 | — | — | 625.18 (13.40x) | 123.97 (2.66x) |
| ZeroInt32Value JSON parse | 127.17 | — | — | 1150.89 (9.05x) | 308.70 (2.43x) |
| NegativeInt32Value JSON stringify | 46.86 | — | — | 702.65 (14.99x) | 136.63 (2.92x) |
| NegativeInt32Value JSON parse | 130.85 | — | — | 1186.92 (9.07x) | 318.57 (2.43x) |
| MinInt32Value JSON stringify | 47.18 | — | — | 652.75 (13.84x) | 138.69 (2.94x) |
| MinInt32Value JSON parse | 137.08 | — | — | 1215.66 (8.87x) | 352.55 (2.57x) |
| MaxInt32Value JSON stringify | 47.28 | — | — | 647.94 (13.70x) | 139.29 (2.95x) |
| MaxInt32Value JSON parse | 139.16 | — | — | 1205.61 (8.66x) | 339.90 (2.44x) |
| UInt32Value JSON stringify | 46.83 | — | — | 640.11 (13.67x) | 133.65 (2.85x) |
| UInt32Value JSON parse | 132.31 | — | — | 1184.29 (8.95x) | 320.03 (2.42x) |
| UInt32Value String JSON parse | 135.11 | — | — | 1122.82 (8.31x) | 391.15 (2.90x) |
| UInt32Value Exponent JSON parse | 134.74 | — | — | 1218.72 (9.04x) | 366.75 (2.72x) |
| ZeroUInt32Value JSON stringify | 46.66 | — | — | 625.38 (13.40x) | 133.93 (2.87x) |
| ZeroUInt32Value JSON parse | 127.17 | — | — | 2299.28 (18.08x) | 276.19 (2.17x) |
| MaxUInt32Value JSON stringify | 47.03 | — | — | 1205.97 (25.64x) | 142.83 (3.04x) |
| MaxUInt32Value JSON parse | 140.21 | — | — | 2407.91 (17.17x) | 348.19 (2.48x) |
| BoolValue JSON stringify | 45.46 | — | — | 1158.73 (25.49x) | 123.37 (2.71x) |
| BoolValue JSON parse | 59.89 | — | — | 2121.70 (35.43x) | 343.43 (5.73x) |
| FalseBoolValue JSON stringify | 45.20 | — | — | 1138.95 (25.20x) | 128.71 (2.85x) |
| FalseBoolValue JSON parse | 60.39 | — | — | 2381.25 (39.43x) | 216.38 (3.58x) |
| StringValue JSON stringify | 51.89 | — | — | 674.50 (13.00x) | 185.33 (3.57x) |
| StringValue JSON parse | 120.88 | — | — | 1145.56 (9.48x) | 321.11 (2.66x) |
| StringValue Escape JSON parse | 129.91 | — | — | 1178.54 (9.07x) | 376.52 (2.90x) |
| StringValue Surrogate JSON parse | 127.87 | — | — | 1169.98 (9.15x) | 381.54 (2.98x) |
| EmptyStringValue JSON stringify | 49.00 | — | — | 637.49 (13.01x) | 182.01 (3.71x) |
| EmptyStringValue JSON parse | 65.92 | — | — | 1109.62 (16.83x) | 318.66 (4.83x) |
| BytesValue JSON stringify | 49.08 | — | — | 673.43 (13.72x) | 210.82 (4.30x) |
| BytesValue JSON parse | 126.70 | — | — | 1169.76 (9.23x) | 352.45 (2.78x) |
| BytesValue URL JSON parse | 142.80 | — | — | 1159.74 (8.12x) | 335.96 (2.35x) |
| BytesValue StandardBase64 JSON parse | 125.19 | — | — | 1173.94 (9.38x) | 337.56 (2.70x) |
| BytesValue Unpadded JSON parse | 125.03 | — | — | 1158.39 (9.26x) | 333.05 (2.66x) |
| EmptyBytesValue JSON stringify | 40.63 | — | — | 646.62 (15.91x) | 188.58 (4.64x) |
| EmptyBytesValue JSON parse | 68.82 | — | — | 1130.37 (16.43x) | 281.10 (4.08x) |
| TextFormat format | 172.52 | — | — | 2551.38 (14.79x) | 2579.78 (14.95x) |
| TextFormat parse | 715.52 | — | — | 4987.30 (6.97x) | 6745.09 (9.43x) |
| packed fixed32 encode | 2.01 | 551.87 (274.56x) | 975.91 (485.53x) | 43.83 (21.80x) | 424.36 (211.12x) |
| packed fixed32 decode | 4.54 | 1051.64 (231.64x) | 3238.82 (713.40x) | 49.28 (10.86x) | 1549.38 (341.27x) |
| packed fixed64 encode | 2.01 | 571.35 (284.25x) | 1003.16 (499.08x) | 76.30 (37.96x) | 393.28 (195.66x) |
| packed fixed64 decode | 4.53 | 1047.22 (231.17x) | 9786.27 (2160.32x) | 79.76 (17.61x) | 2202.40 (486.18x) |
| packed sfixed32 encode | 2.01 | 736.39 (366.36x) | 978.26 (486.70x) | 43.65 (21.72x) | 414.12 (206.03x) |
| packed sfixed32 decode | 4.53 | 1067.49 (235.65x) | 3237.57 (714.70x) | 48.56 (10.72x) | 2179.34 (481.09x) |
| packed sfixed64 encode | 2.01 | 569.68 (283.42x) | 1003.24 (499.12x) | 76.87 (38.24x) | 1963.22 (976.73x) |
| packed sfixed64 decode | 4.56 | 1005.86 (220.58x) | 9661.12 (2118.67x) | 79.65 (17.47x) | 5513.87 (1209.18x) |
| packed float encode | 2.00 | 811.29 (405.64x) | 977.10 (488.55x) | 43.90 (21.95x) | 661.53 (330.76x) |
| packed float decode | 4.53 | 1049.05 (231.58x) | 3625.45 (800.32x) | 48.81 (10.77x) | 2749.93 (607.05x) |
| packed double encode | 2.02 | 828.79 (410.29x) | 1001.91 (496.00x) | 76.34 (37.79x) | 614.52 (304.22x) |
| packed double decode | 4.53 | 972.83 (214.75x) | 3506.48 (774.06x) | 79.94 (17.65x) | 3590.68 (792.64x) |
| packed uint64 encode | 1291.50 | 4589.57 (3.55x) | 7046.00 (5.46x) | 2197.76 (1.70x) | 5973.06 (4.62x) |
| packed uint64 decode | 1780.49 | 2783.26 (1.56x) | 11629.14 (6.53x) | 2858.61 (1.61x) | 13392.05 (7.52x) |
| packed uint32 encode | 925.45 | 3614.34 (3.91x) | 5598.38 (6.05x) | 1739.53 (1.88x) | 5149.64 (5.56x) |
| packed uint32 decode | 1316.68 | 2447.58 (1.86x) | 5211.81 (3.96x) | 1990.48 (1.51x) | 5823.56 (4.42x) |
| packed int64 encode | 1391.91 | 10980.67 (7.89x) | 9736.22 (6.99x) | 2904.46 (2.09x) | 4119.25 (2.96x) |
| packed int64 decode | 2754.57 | 3366.21 (1.22x) | 13825.48 (5.02x) | 4718.09 (1.71x) | 12735.58 (4.62x) |
| packed sint32 encode | 864.81 | 3030.18 (3.50x) | 5194.60 (6.01x) | 1528.61 (1.77x) | 4909.52 (5.68x) |
| packed sint32 decode | 951.24 | 2548.94 (2.68x) | 5462.70 (5.74x) | 1125.88 (1.18x) | 5101.74 (5.36x) |
| packed sint64 encode | 1434.80 | 4933.60 (3.44x) | 7662.95 (5.34x) | 2448.31 (1.71x) | 7274.61 (5.07x) |
| packed sint64 decode | 2038.06 | 3063.52 (1.50x) | 12605.59 (6.19x) | 2941.16 (1.44x) | 6691.07 (3.28x) |
| packed bool encode | 2.00 | 1316.68 (658.34x) | 711.19 (355.60x) | 15.67 (7.84x) | 2225.56 (1112.78x) |
| packed bool decode | 263.06 | 1530.06 (5.82x) | 4121.70 (15.67x) | 803.33 (3.05x) | 1609.38 (6.12x) |
| packed enum encode | 275.73 | 2711.44 (9.83x) | 2560.76 (9.29x) | 1080.62 (3.92x) | 2506.77 (9.09x) |
| packed enum decode | 160.61 | 1526.72 (9.51x) | 4171.54 (25.97x) | 710.47 (4.42x) | 2119.01 (13.19x) |
| large map encode | 3936.65 | 16564.61 (4.21x) | 14347.53 (3.64x) | 21123.40 (5.37x) | 210207.29 (53.40x) |
| shuffled large map deterministic binary encode | 28616.34 | — | — | 89470.50 (3.13x) | 471248.69 (16.47x) |
| large map decode | 26203.16 | 90225.14 (3.44x) | 143653.54 (5.48x) | 97564.70 (3.72x) | 286676.44 (10.94x) |
The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound `Duration`, non-empty/escaped-input parse/number-exponent parse/surrogate-pair parse and empty `Struct`, object/escaped-object parse/object-number-exponent/object-surrogate-pair parse/list/escaped-list/string-scalar/escaped-string-scalar/surrogate-string-scalar/number-exponent/negative-number `Value` (including default-like scalar and empty object/list kinds),
`FieldMask` (non-empty, escaped JSON parse input, and empty), escaped-input parse/short-fraction parse/micro/nano/offset/min/pre/post/max-bound `Timestamp`, `Empty`, min/zero/positive/number-input parse/numeric-exponent parse/negative/max `Int64Value`, negative/zero/positive finite/string-input parse/numeric-exponent parse `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), negative/zero/positive finite/string-input parse/numeric-exponent parse `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), zero/normal/number-input parse/numeric-exponent parse/max `UInt64Value`, min/zero/positive/string-input parse/numeric-exponent parse/negative/max `Int32Value`, zero/normal/string-input parse/numeric-exponent parse/max `UInt32Value`, true/false `BoolValue`, non-empty/escape-input parse/surrogate-pair parse/empty `StringValue`, padded-standard/base64url/unpadded-base64 parse/empty `BytesValue`, and recursive nested `Any` payloads), direct zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound Duration, non-empty/escaped-input parse/empty FieldMask, and escaped-input parse/short-fraction parse/micro/nano/offset/min/pre/post/max-bound Timestamp WKT JSON plus other direct WKT JSON, including non-empty/escaped-input parse/number-exponent parse/surrogate-pair parse/empty `Struct`, object/escaped-object parse/object-number-exponent/object-surrogate-pair parse/list/escaped-list/string-scalar/escaped-string-scalar/surrogate-string-scalar/number-exponent/negative-number `Value`, and escaped/non-empty/empty `ListValue`, TextFormat, packed scalars, large bytes,
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
