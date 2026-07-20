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

Latest accepted comparison (`/tmp/pbz-compare-int32-uint32-exponent-json-final.log`,
summarized in `/tmp/pbz-summary-int32-uint32-exponent-json-final.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 19.56 | 100.87 (5.16x) | 50.53 (2.58x) | 102.27 (5.23x) | 848.27 (43.37x) |
| binary decode | 88.74 | 250.50 (2.82x) | 232.29 (2.62x) | 335.89 (3.79x) | 3080.31 (34.71x) |
| unknown fields count by number | 3.57 | — | — | 162.09 (45.40x) | — |
| deterministic binary encode | 50.64 | — | — | 126.50 (2.50x) | 1600.08 (31.60x) |
| scalarmix encode | 18.29 | 95.54 (5.22x) | 47.75 (2.61x) | 29.82 (1.63x) | 916.31 (50.10x) |
| scalarmix decode | 44.08 | 134.22 (3.04x) | 176.10 (4.00x) | 85.31 (1.94x) | 1835.83 (41.65x) |
| textbytes encode | 13.53 | 80.67 (5.96x) | 33.34 (2.46x) | 116.83 (8.63x) | 364.01 (26.90x) |
| textbytes decode | 41.70 | 380.25 (9.12x) | 240.38 (5.76x) | 167.43 (4.02x) | 4915.61 (117.88x) |
| largebytes encode | 18.04 | 2703.35 (149.85x) | 2678.69 (148.49x) | 2679.51 (148.53x) | 2707.66 (150.09x) |
| largebytes decode | 88.32 | 5888.77 (66.68x) | 3035.36 (34.37x) | 2739.56 (31.02x) | 21589.25 (244.44x) |
| presencemix encode | 16.54 | 55.06 (3.33x) | 29.65 (1.79x) | 56.13 (3.39x) | 237.21 (14.34x) |
| presencemix decode | 56.57 | 133.43 (2.36x) | 111.88 (1.98x) | 162.43 (2.87x) | 493.37 (8.72x) |
| complex encode | 49.27 | 135.81 (2.76x) | 95.27 (1.93x) | 157.31 (3.19x) | 942.47 (19.13x) |
| complex decode | 169.53 | 390.15 (2.30x) | 350.36 (2.07x) | 387.72 (2.29x) | 1365.65 (8.06x) |
| complex deterministic binary encode | 149.08 | — | — | 180.39 (1.21x) | 1160.81 (7.79x) |
| complex JSON stringify | 246.55 | — | — | 4883.02 (19.81x) | 6207.73 (25.18x) |
| complex JSON parse | 2381.98 | — | — | 11864.50 (4.98x) | 12063.28 (5.06x) |
| complex TextFormat format | 250.74 | — | — | 3771.70 (15.04x) | 7984.61 (31.84x) |
| complex TextFormat parse | 2578.22 | — | — | 6907.33 (2.68x) | 14391.66 (5.58x) |
| packed int32 encode | 644.68 | 3156.88 (4.90x) | 2517.44 (3.90x) | 1236.46 (1.92x) | 2767.93 (4.29x) |
| packed int32 decode | 690.37 | 1915.07 (2.77x) | 3241.33 (4.70x) | 944.50 (1.37x) | 2569.94 (3.72x) |
| JSON stringify | 248.10 | — | — | 2998.95 (12.09x) | 4357.28 (17.56x) |
| JSON parse | 2291.64 | — | — | 7411.23 (3.23x) | 6742.74 (2.94x) |
| Any WKT JSON stringify | 135.47 | — | — | 1908.64 (14.09x) | 1943.98 (14.35x) |
| Any WKT JSON parse | 522.38 | — | — | 2986.69 (5.72x) | 3478.68 (6.66x) |
| Any Duration Escape WKT JSON parse | 533.48 | — | — | 3015.24 (5.65x) | 2235.57 (4.19x) |
| Any PlusDuration WKT JSON parse | 517.97 | — | — | 3005.24 (5.80x) | 2161.13 (4.17x) |
| Any ShortFractionDuration WKT JSON parse | 513.56 | — | — | 2957.11 (5.76x) | 2181.51 (4.25x) |
| Any MicroDuration WKT JSON stringify | 133.78 | — | — | 1923.82 (14.38x) | 1456.31 (10.89x) |
| Any MicroDuration WKT JSON parse | 516.34 | — | — | 3005.47 (5.82x) | 2080.39 (4.03x) |
| Any NanoDuration WKT JSON stringify | 128.78 | — | — | 1948.95 (15.13x) | 1003.04 (7.79x) |
| Any NanoDuration WKT JSON parse | 524.19 | — | — | 3021.16 (5.76x) | 1608.35 (3.07x) |
| Any NegativeDuration WKT JSON stringify | 131.04 | — | — | 1961.20 (14.97x) | 1040.83 (7.94x) |
| Any NegativeDuration WKT JSON parse | 520.52 | — | — | 3096.54 (5.95x) | 1630.67 (3.13x) |
| Any FractionalNegativeDuration WKT JSON stringify | 126.26 | — | — | 1912.53 (15.15x) | 1061.89 (8.41x) |
| Any FractionalNegativeDuration WKT JSON parse | 512.71 | — | — | 3069.01 (5.99x) | 1543.41 (3.01x) |
| Any MaxDuration WKT JSON stringify | 118.69 | — | — | 1769.79 (14.91x) | 993.46 (8.37x) |
| Any MaxDuration WKT JSON parse | 530.90 | — | — | 2973.43 (5.60x) | 1557.80 (2.93x) |
| Any MinDuration WKT JSON stringify | 118.40 | — | — | 1779.27 (15.03x) | 1012.46 (8.55x) |
| Any MinDuration WKT JSON parse | 531.91 | — | — | 3019.83 (5.68x) | 1531.99 (2.88x) |
| Any ZeroDuration WKT JSON stringify | 104.72 | — | — | 913.39 (8.72x) | 978.59 (9.34x) |
| Any ZeroDuration WKT JSON parse | 461.08 | — | — | 2250.33 (4.88x) | 1469.54 (3.19x) |
| Any FieldMask WKT JSON stringify | 238.05 | — | — | 1769.11 (7.43x) | 1415.38 (5.95x) |
| Any FieldMask WKT JSON parse | 703.16 | — | — | 3167.62 (4.50x) | 2074.27 (2.95x) |
| Any FieldMask Escape WKT JSON parse | 722.70 | — | — | 3238.55 (4.48x) | 2262.25 (3.13x) |
| Any EmptyFieldMask WKT JSON stringify | 110.17 | — | — | 916.22 (8.32x) | 793.32 (7.20x) |
| Any EmptyFieldMask WKT JSON parse | 433.65 | — | — | 2165.20 (4.99x) | 1330.89 (3.07x) |
| Any Timestamp WKT JSON stringify | 174.24 | — | — | 2036.12 (11.69x) | 1992.01 (11.43x) |
| Any Timestamp WKT JSON parse | 562.29 | — | — | 3027.88 (5.38x) | 3198.93 (5.69x) |
| Any Timestamp Escape WKT JSON parse | 578.40 | — | — | 3075.65 (5.32x) | 3445.38 (5.96x) |
| Any ShortFraction Timestamp WKT JSON parse | 558.06 | — | — | 3012.75 (5.40x) | 3287.79 (5.89x) |
| Any Micro Timestamp WKT JSON stringify | 174.50 | — | — | 2036.29 (11.67x) | 2047.38 (11.73x) |
| Any Micro Timestamp WKT JSON parse | 568.48 | — | — | 3029.25 (5.33x) | 3132.86 (5.51x) |
| Any Nano Timestamp WKT JSON stringify | 172.41 | — | — | 2042.22 (11.85x) | 2063.08 (11.97x) |
| Any Nano Timestamp WKT JSON parse | 578.92 | — | — | 3062.13 (5.29x) | 2874.74 (4.97x) |
| Any Offset Timestamp WKT JSON parse | 586.79 | — | — | 3065.00 (5.22x) | 1831.16 (3.12x) |
| Any PreEpoch Timestamp WKT JSON stringify | 139.68 | — | — | 1949.60 (13.96x) | 1037.61 (7.43x) |
| Any PreEpoch Timestamp WKT JSON parse | 554.76 | — | — | 3058.54 (5.51x) | 1646.55 (2.97x) |
| Any Max Timestamp WKT JSON stringify | 158.18 | — | — | 2071.48 (13.10x) | 1078.99 (6.82x) |
| Any Max Timestamp WKT JSON parse | 582.75 | — | — | 3121.34 (5.36x) | 1775.79 (3.05x) |
| Any Min Timestamp WKT JSON stringify | 153.89 | — | — | 1954.05 (12.70x) | 1051.49 (6.83x) |
| Any Min Timestamp WKT JSON parse | 550.94 | — | — | 3057.64 (5.55x) | 1616.81 (2.93x) |
| Any Empty WKT JSON stringify | 88.04 | — | — | 911.62 (10.35x) | 651.54 (7.40x) |
| Any Empty WKT JSON parse | 329.88 | — | — | 2143.48 (6.50x) | 1373.55 (4.16x) |
| Any Struct WKT JSON stringify | 623.99 | — | — | 5830.94 (9.34x) | 6303.96 (10.10x) |
| Any Struct WKT JSON parse | 1785.41 | — | — | 11082.40 (6.21x) | 9028.79 (5.06x) |
| Any Struct Escape WKT JSON parse | 1816.69 | — | — | 11174.00 (6.15x) | 9109.90 (5.01x) |
| Any Struct NumberExponent WKT JSON parse | 1796.29 | — | — | 11105.50 (6.18x) | 8760.77 (4.88x) |
| Any EmptyStruct WKT JSON stringify | 120.23 | — | — | 908.49 (7.56x) | 961.29 (8.00x) |
| Any EmptyStruct WKT JSON parse | 435.72 | — | — | 2228.41 (5.11x) | 1564.29 (3.59x) |
| Any Value WKT JSON stringify | 652.35 | — | — | 5921.15 (9.08x) | 6463.24 (9.91x) |
| Any Value WKT JSON parse | 1837.66 | — | — | 11239.70 (6.12x) | 9115.70 (4.96x) |
| Any Value Escape WKT JSON parse | 1852.33 | — | — | 11413.40 (6.16x) | 9246.69 (4.99x) |
| Any Value NumberExponent WKT JSON parse | 1833.57 | — | — | 11350.80 (6.19x) | 9154.36 (4.99x) |
| Any NullValue WKT JSON stringify | 122.83 | — | — | 2267.17 (18.46x) | 916.44 (7.46x) |
| Any NullValue WKT JSON parse | 461.40 | — | — | 4070.80 (8.82x) | 1591.04 (3.45x) |
| Any StringScalarValue WKT JSON stringify | 150.08 | — | — | 2278.57 (15.18x) | 1001.34 (6.67x) |
| Any StringScalarValue WKT JSON parse | 522.11 | — | — | 3628.32 (6.95x) | 1693.23 (3.24x) |
| Any StringScalarValue Escape WKT JSON parse | 531.35 | — | — | 3676.60 (6.92x) | 1730.49 (3.26x) |
| Any EmptyStringScalarValue WKT JSON stringify | 134.40 | — | — | 2312.36 (17.21x) | 945.08 (7.03x) |
| Any EmptyStringScalarValue WKT JSON parse | 489.88 | — | — | 3588.04 (7.32x) | 1599.78 (3.27x) |
| Any NumberValue WKT JSON stringify | 171.56 | — | — | 2517.56 (14.67x) | 1032.50 (6.02x) |
| Any NumberValue WKT JSON parse | 501.92 | — | — | 3717.71 (7.41x) | 1613.38 (3.21x) |
| Any NumberValue Exponent WKT JSON parse | 501.45 | — | — | 3738.86 (7.46x) | 1609.44 (3.21x) |
| Any NegativeNumberValue WKT JSON stringify | 172.50 | — | — | 2517.52 (14.59x) | 1036.79 (6.01x) |
| Any NegativeNumberValue WKT JSON parse | 501.36 | — | — | 3684.70 (7.35x) | 1618.85 (3.23x) |
| Any ZeroNumberValue WKT JSON stringify | 136.09 | — | — | 2477.61 (18.21x) | 924.73 (6.79x) |
| Any ZeroNumberValue WKT JSON parse | 497.91 | — | — | 3632.58 (7.30x) | 1659.30 (3.33x) |
| Any BoolScalarValue WKT JSON stringify | 128.31 | — | — | 2278.09 (17.75x) | 916.00 (7.14x) |
| Any BoolScalarValue WKT JSON parse | 466.72 | — | — | 3574.55 (7.66x) | 1536.36 (3.29x) |
| Any FalseBoolScalarValue WKT JSON stringify | 128.85 | — | — | 2265.48 (17.58x) | 910.55 (7.07x) |
| Any FalseBoolScalarValue WKT JSON parse | 463.02 | — | — | 3588.07 (7.75x) | 1524.77 (3.29x) |
| Any ListKindValue WKT JSON stringify | 499.02 | — | — | 5575.15 (11.17x) | 4684.89 (9.39x) |
| Any ListKindValue WKT JSON parse | 1386.88 | — | — | 9860.17 (7.11x) | 7070.83 (5.10x) |
| Any ListKindValue Escape WKT JSON parse | 1407.29 | — | — | 9960.06 (7.08x) | 7275.17 (5.17x) |
| Any EmptyStructKindValue WKT JSON stringify | 145.86 | — | — | 2921.50 (20.03x) | 1272.05 (8.72x) |
| Any EmptyStructKindValue WKT JSON parse | 499.27 | — | — | 5382.52 (10.78x) | 1967.57 (3.94x) |
| Any EmptyListKindValue WKT JSON stringify | 141.79 | — | — | 2900.76 (20.46x) | 1115.74 (7.87x) |
| Any EmptyListKindValue WKT JSON parse | 503.07 | — | — | 4380.49 (8.71x) | 1822.55 (3.62x) |
| Any DoubleValue WKT JSON stringify | 185.21 | — | — | 1813.52 (9.79x) | 807.27 (4.36x) |
| Any DoubleValue WKT JSON parse | 519.30 | — | — | 2734.80 (5.27x) | 1442.51 (2.78x) |
| Any DoubleValue String WKT JSON parse | 524.71 | — | — | 2730.96 (5.20x) | 1515.40 (2.89x) |
| Any DoubleValue Exponent WKT JSON parse | 515.89 | — | — | 2743.00 (5.32x) | 1447.04 (2.80x) |
| Any NegativeDoubleValue WKT JSON stringify | 185.22 | — | — | 1805.93 (9.75x) | 795.87 (4.30x) |
| Any NegativeDoubleValue WKT JSON parse | 514.87 | — | — | 2736.40 (5.31x) | 1447.56 (2.81x) |
| Any ZeroDoubleValue WKT JSON stringify | 155.39 | — | — | 1091.41 (7.02x) | 742.05 (4.78x) |
| Any ZeroDoubleValue WKT JSON parse | 509.18 | — | — | 2170.33 (4.26x) | 1379.97 (2.71x) |
| Any DoubleValue NaN WKT JSON stringify | 148.19 | — | — | 1577.53 (10.65x) | 718.79 (4.85x) |
| Any DoubleValue NaN WKT JSON parse | 504.65 | — | — | 2653.39 (5.26x) | 1418.30 (2.81x) |
| Any DoubleValue Infinity WKT JSON stringify | 151.85 | — | — | 1576.57 (10.38x) | 718.55 (4.73x) |
| Any DoubleValue Infinity WKT JSON parse | 512.18 | — | — | 2694.79 (5.26x) | 1431.29 (2.79x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 155.53 | — | — | 1573.77 (10.12x) | 732.63 (4.71x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 513.03 | — | — | 2684.75 (5.23x) | 1438.24 (2.80x) |
| Any FloatValue WKT JSON stringify | 192.96 | — | — | 1747.78 (9.06x) | 787.37 (4.08x) |
| Any FloatValue WKT JSON parse | 517.41 | — | — | 2708.41 (5.23x) | 1428.33 (2.76x) |
| Any FloatValue String WKT JSON parse | 528.22 | — | — | 2721.51 (5.15x) | 1498.41 (2.84x) |
| Any FloatValue Exponent WKT JSON parse | 521.32 | — | — | 2718.49 (5.21x) | 1433.22 (2.75x) |
| Any NegativeFloatValue WKT JSON stringify | 193.36 | — | — | 1758.04 (9.09x) | 779.49 (4.03x) |
| Any NegativeFloatValue WKT JSON parse | 519.00 | — | — | 2723.38 (5.25x) | 1477.21 (2.85x) |
| Any ZeroFloatValue WKT JSON stringify | 163.48 | — | — | 917.46 (5.61x) | 727.91 (4.45x) |
| Any ZeroFloatValue WKT JSON parse | 516.70 | — | — | 2158.47 (4.18x) | 1389.70 (2.69x) |
| Any FloatValue NaN WKT JSON stringify | 152.26 | — | — | 1581.90 (10.39x) | 713.14 (4.68x) |
| Any FloatValue NaN WKT JSON parse | 514.01 | — | — | 2624.35 (5.11x) | 1408.07 (2.74x) |
| Any FloatValue Infinity WKT JSON stringify | 159.66 | — | — | 1562.78 (9.79x) | 720.95 (4.52x) |
| Any FloatValue Infinity WKT JSON parse | 523.61 | — | — | 2665.17 (5.09x) | 1410.47 (2.69x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 158.80 | — | — | 1554.32 (9.79x) | 723.93 (4.56x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 522.29 | — | — | 2646.44 (5.07x) | 1450.51 (2.78x) |
| Any Int64Value WKT JSON stringify | 166.51 | — | — | 1565.42 (9.40x) | 871.20 (5.23x) |
| Any Int64Value WKT JSON parse | 550.79 | — | — | 2774.90 (5.04x) | 1662.31 (3.02x) |
| Any Int64Value Number WKT JSON parse | 552.14 | — | — | 2734.00 (4.95x) | 1549.01 (2.81x) |
| Any ZeroInt64Value WKT JSON stringify | 157.31 | — | — | 911.74 (5.80x) | 801.55 (5.10x) |
| Any ZeroInt64Value WKT JSON parse | 523.85 | — | — | 2137.64 (4.08x) | 1507.31 (2.88x) |
| Any NegativeInt64Value WKT JSON stringify | 170.22 | — | — | 1563.17 (9.18x) | 860.39 (5.05x) |
| Any NegativeInt64Value WKT JSON parse | 564.70 | — | — | 2796.43 (4.95x) | 1661.20 (2.94x) |
| Any MinInt64Value WKT JSON stringify | 171.07 | — | — | 1560.45 (9.12x) | 860.29 (5.03x) |
| Any MinInt64Value WKT JSON parse | 570.61 | — | — | 2816.12 (4.94x) | 1685.34 (2.95x) |
| Any MaxInt64Value WKT JSON stringify | 172.24 | — | — | 1580.10 (9.17x) | 849.11 (4.93x) |
| Any MaxInt64Value WKT JSON parse | 555.97 | — | — | 2794.70 (5.03x) | 1679.54 (3.02x) |
| Any UInt64Value WKT JSON stringify | 173.91 | — | — | 1559.15 (8.97x) | 874.41 (5.03x) |
| Any UInt64Value WKT JSON parse | 551.43 | — | — | 2794.70 (5.07x) | 1640.79 (2.98x) |
| Any UInt64Value Number WKT JSON parse | 548.39 | — | — | 2753.51 (5.02x) | 1519.12 (2.77x) |
| Any ZeroUInt64Value WKT JSON stringify | 163.94 | — | — | 914.51 (5.58x) | 778.53 (4.75x) |
| Any ZeroUInt64Value WKT JSON parse | 521.76 | — | — | 2146.47 (4.11x) | 1465.69 (2.81x) |
| Any MaxUInt64Value WKT JSON stringify | 175.92 | — | — | 1565.62 (8.90x) | 875.14 (4.97x) |
| Any MaxUInt64Value WKT JSON parse | 559.58 | — | — | 2824.31 (5.05x) | 1675.59 (2.99x) |
| Any Int32Value WKT JSON stringify | 167.26 | — | — | 1554.43 (9.29x) | 746.48 (4.46x) |
| Any Int32Value WKT JSON parse | 535.46 | — | — | 2675.37 (5.00x) | 1434.72 (2.68x) |
| Any Int32Value String WKT JSON parse | 540.58 | — | — | 2685.70 (4.97x) | 1555.63 (2.88x) |
| Any Int32Value Exponent WKT JSON parse | 539.48 | — | — | 2716.71 (5.04x) | 1503.98 (2.79x) |
| Any ZeroInt32Value WKT JSON stringify | 164.60 | — | — | 918.30 (5.58x) | 781.96 (4.75x) |
| Any ZeroInt32Value WKT JSON parse | 530.70 | — | — | 2157.47 (4.07x) | 1453.71 (2.74x) |
| Any NegativeInt32Value WKT JSON stringify | 172.35 | — | — | 1560.12 (9.05x) | 771.59 (4.48x) |
| Any NegativeInt32Value WKT JSON parse | 536.82 | — | — | 2710.01 (5.05x) | 1522.76 (2.84x) |
| Any MinInt32Value WKT JSON stringify | 169.77 | — | — | 1563.81 (9.21x) | 782.98 (4.61x) |
| Any MinInt32Value WKT JSON parse | 543.81 | — | — | 2695.88 (4.96x) | 1569.12 (2.89x) |
| Any MaxInt32Value WKT JSON stringify | 169.56 | — | — | 1556.70 (9.18x) | 768.42 (4.53x) |
| Any MaxInt32Value WKT JSON parse | 543.45 | — | — | 2678.85 (4.93x) | 1547.13 (2.85x) |
| Any UInt32Value WKT JSON stringify | 174.53 | — | — | 1556.91 (8.92x) | 744.43 (4.27x) |
| Any UInt32Value WKT JSON parse | 534.27 | — | — | 2672.87 (5.00x) | 1483.40 (2.78x) |
| Any UInt32Value String WKT JSON parse | 538.09 | — | — | 2665.37 (4.95x) | 1575.37 (2.93x) |
| Any UInt32Value Exponent WKT JSON parse | 538.56 | — | — | 2706.81 (5.03x) | 1510.53 (2.80x) |
| Any ZeroUInt32Value WKT JSON stringify | 174.65 | — | — | 912.87 (5.23x) | 716.31 (4.10x) |
| Any ZeroUInt32Value WKT JSON parse | 529.57 | — | — | 2152.40 (4.06x) | 1425.75 (2.69x) |
| Any MaxUInt32Value WKT JSON stringify | 177.22 | — | — | 1562.60 (8.82x) | 742.32 (4.19x) |
| Any MaxUInt32Value WKT JSON parse | 541.62 | — | — | 2691.78 (4.97x) | 1470.67 (2.72x) |
| Any BoolValue WKT JSON stringify | 170.22 | — | — | 1528.24 (8.98x) | 721.84 (4.24x) |
| Any BoolValue WKT JSON parse | 488.38 | — | — | 2607.64 (5.34x) | 1335.43 (2.73x) |
| Any FalseBoolValue WKT JSON stringify | 172.53 | — | — | 1059.79 (6.14x) | 718.90 (4.17x) |
| Any FalseBoolValue WKT JSON parse | 482.29 | — | — | 2150.99 (4.46x) | 1342.53 (2.78x) |
| Any StringValue WKT JSON stringify | 189.84 | — | — | 1567.04 (8.25x) | 803.09 (4.23x) |
| Any StringValue WKT JSON parse | 546.47 | — | — | 2651.12 (4.85x) | 1429.82 (2.62x) |
| Any StringValue Escape WKT JSON parse | 551.20 | — | — | 2692.05 (4.88x) | 1538.18 (2.79x) |
| Any EmptyStringValue WKT JSON stringify | 184.14 | — | — | 916.43 (4.98x) | 757.50 (4.11x) |
| Any EmptyStringValue WKT JSON parse | 516.99 | — | — | 2164.43 (4.19x) | 1382.42 (2.67x) |
| Any BytesValue WKT JSON stringify | 181.24 | — | — | 1597.41 (8.81x) | 842.82 (4.65x) |
| Any BytesValue WKT JSON parse | 557.14 | — | — | 2684.74 (4.82x) | 1464.50 (2.63x) |
| Any BytesValue URL WKT JSON parse | 575.11 | — | — | 2820.15 (4.90x) | 1472.21 (2.56x) |
| Any EmptyBytesValue WKT JSON stringify | 182.44 | — | — | 914.05 (5.01x) | 766.44 (4.20x) |
| Any EmptyBytesValue WKT JSON parse | 520.47 | — | — | 2158.96 (4.15x) | 1436.99 (2.76x) |
| Nested Any WKT JSON stringify | 290.68 | — | — | 2476.73 (8.52x) | 1445.57 (4.97x) |
| Nested Any WKT JSON parse | 862.53 | — | — | 4272.98 (4.95x) | 2874.23 (3.33x) |
| Duration JSON stringify | 57.84 | — | — | 957.45 (16.55x) | 356.98 (6.17x) |
| Duration JSON parse | 20.58 | — | — | 1453.04 (70.60x) | 404.62 (19.66x) |
| Duration Escape JSON parse | 42.57 | — | — | 1481.58 (34.80x) | 430.03 (10.10x) |
| PlusDuration JSON parse | 19.58 | — | — | 1454.15 (74.27x) | 391.52 (20.00x) |
| ShortFractionDuration JSON parse | 16.30 | — | — | 1423.41 (87.33x) | 389.81 (23.91x) |
| MicroDuration JSON stringify | 58.80 | — | — | 972.08 (16.53x) | 412.20 (7.01x) |
| MicroDuration JSON parse | 19.10 | — | — | 1468.86 (76.90x) | 396.49 (20.76x) |
| NanoDuration JSON stringify | 56.81 | — | — | 998.44 (17.58x) | 407.83 (7.18x) |
| NanoDuration JSON parse | 23.09 | — | — | 1481.58 (64.17x) | 394.50 (17.09x) |
| NegativeDuration JSON stringify | 57.97 | — | — | 1007.41 (17.38x) | 432.89 (7.47x) |
| NegativeDuration JSON parse | 17.48 | — | — | 1510.90 (86.44x) | 392.11 (22.43x) |
| FractionalNegativeDuration JSON stringify | 57.93 | — | — | 970.54 (16.75x) | 433.35 (7.48x) |
| FractionalNegativeDuration JSON parse | 19.44 | — | — | 1456.81 (74.94x) | 384.26 (19.77x) |
| MaxDuration JSON stringify | 49.15 | — | — | 853.05 (17.36x) | 424.29 (8.63x) |
| MaxDuration JSON parse | 34.16 | — | — | 1435.15 (42.01x) | 404.41 (11.84x) |
| MinDuration JSON stringify | 49.39 | — | — | 873.62 (17.69x) | 448.10 (9.07x) |
| MinDuration JSON parse | 32.57 | — | — | 1451.09 (44.55x) | 410.56 (12.61x) |
| ZeroDuration JSON stringify | 44.43 | — | — | 812.22 (18.28x) | 628.94 (14.16x) |
| ZeroDuration JSON parse | 16.30 | — | — | 1363.22 (83.63x) | 332.47 (20.40x) |
| FieldMask JSON stringify | 77.10 | — | — | 881.43 (11.43x) | 662.34 (8.59x) |
| FieldMask JSON parse | 150.79 | — | — | 1650.92 (10.95x) | 891.25 (5.91x) |
| FieldMask Escape JSON parse | 195.57 | — | — | 1706.41 (8.73x) | 968.84 (4.95x) |
| EmptyFieldMask JSON stringify | 40.89 | — | — | 608.98 (14.89x) | 195.17 (4.77x) |
| EmptyFieldMask JSON parse | 4.78 | — | — | 940.66 (196.79x) | 164.71 (34.46x) |
| Timestamp JSON stringify | 96.02 | — | — | 1139.87 (11.87x) | 410.76 (4.28x) |
| Timestamp JSON parse | 45.16 | — | — | 1487.27 (32.93x) | 440.35 (9.75x) |
| Timestamp Escape JSON parse | 96.53 | — | — | 1516.67 (15.71x) | 510.88 (5.29x) |
| ShortFraction Timestamp JSON parse | 43.53 | — | — | 1483.04 (34.07x) | 437.26 (10.05x) |
| Micro Timestamp JSON stringify | 95.75 | — | — | 1138.30 (11.89x) | 418.42 (4.37x) |
| Micro Timestamp JSON parse | 48.59 | — | — | 1497.54 (30.82x) | 457.91 (9.42x) |
| Nano Timestamp JSON stringify | 94.34 | — | — | 1177.78 (12.48x) | 430.41 (4.56x) |
| Nano Timestamp JSON parse | 50.28 | — | — | 1516.63 (30.16x) | 461.97 (9.19x) |
| Offset Timestamp JSON parse | 52.11 | — | — | 1531.39 (29.39x) | 486.46 (9.34x) |
| PreEpoch Timestamp JSON stringify | 66.41 | — | — | 1058.91 (15.95x) | 401.88 (6.05x) |
| PreEpoch Timestamp JSON parse | 43.06 | — | — | 1459.98 (33.91x) | 424.69 (9.86x) |
| Max Timestamp JSON stringify | 78.63 | — | — | 1190.38 (15.14x) | 423.65 (5.39x) |
| Max Timestamp JSON parse | 51.12 | — | — | 1527.87 (29.89x) | 466.79 (9.13x) |
| Min Timestamp JSON stringify | 79.86 | — | — | 1060.31 (13.28x) | 692.04 (8.67x) |
| Min Timestamp JSON parse | 41.04 | — | — | 1448.11 (35.29x) | 429.95 (10.48x) |
| Empty JSON stringify | 20.83 | — | — | 503.54 (24.17x) | 86.13 (4.13x) |
| Empty JSON parse | 68.41 | — | — | 720.41 (10.53x) | 204.77 (2.99x) |
| Struct JSON stringify | 176.86 | — | — | 5749.89 (32.51x) | 3042.70 (17.20x) |
| Struct JSON parse | 848.59 | — | — | 10932.00 (12.88x) | 4676.03 (5.51x) |
| Struct Escape JSON parse | 891.40 | — | — | 10989.50 (12.33x) | 4774.30 (5.36x) |
| Struct NumberExponent JSON parse | 848.74 | — | — | 10908.70 (12.85x) | 4668.03 (5.50x) |
| EmptyStruct JSON stringify | 40.40 | — | — | 699.91 (17.32x) | 353.72 (8.76x) |
| EmptyStruct JSON parse | 87.44 | — | — | 2042.68 (23.36x) | 377.98 (4.32x) |
| Value JSON stringify | 177.63 | — | — | 6605.71 (37.19x) | 3203.78 (18.04x) |
| Value JSON parse | 895.17 | — | — | 12452.40 (13.91x) | 4925.83 (5.50x) |
| Value Escape JSON parse | 933.93 | — | — | 12348.10 (13.22x) | 5031.24 (5.39x) |
| Value NumberExponent JSON parse | 892.61 | — | — | 12283.00 (13.76x) | 4909.77 (5.50x) |
| NullValue JSON stringify | 40.30 | — | — | 1509.87 (37.47x) | 226.27 (5.61x) |
| NullValue JSON parse | 70.85 | — | — | 2465.03 (34.79x) | 342.83 (4.84x) |
| StringScalarValue JSON stringify | 47.36 | — | — | 1353.65 (28.58x) | 492.63 (10.40x) |
| StringScalarValue JSON parse | 140.41 | — | — | 2131.75 (15.18x) | 444.32 (3.16x) |
| StringScalarValue Escape JSON parse | 150.25 | — | — | 2115.32 (14.08x) | 489.62 (3.26x) |
| EmptyStringScalarValue JSON stringify | 45.47 | — | — | 1337.56 (29.42x) | 284.39 (6.25x) |
| EmptyStringScalarValue JSON parse | 87.37 | — | — | 2074.29 (23.74x) | 367.53 (4.21x) |
| NumberValue JSON stringify | 74.38 | — | — | 1557.02 (20.93x) | 319.02 (4.29x) |
| NumberValue JSON parse | 132.75 | — | — | 2172.16 (16.36x) | 420.43 (3.17x) |
| NumberValue Exponent JSON parse | 135.18 | — | — | 2174.84 (16.09x) | 422.07 (3.12x) |
| NegativeNumberValue JSON stringify | 75.37 | — | — | 1551.76 (20.59x) | 325.57 (4.32x) |
| NegativeNumberValue JSON parse | 133.45 | — | — | 2164.86 (16.22x) | 410.01 (3.07x) |
| ZeroNumberValue JSON stringify | 51.34 | — | — | 1504.91 (29.31x) | 277.92 (5.41x) |
| ZeroNumberValue JSON parse | 130.17 | — | — | 2096.98 (16.11x) | 391.53 (3.01x) |
| BoolScalarValue JSON stringify | 40.31 | — | — | 1320.64 (32.76x) | 224.10 (5.56x) |
| BoolScalarValue JSON parse | 70.22 | — | — | 2013.00 (28.67x) | 333.96 (4.76x) |
| FalseBoolScalarValue JSON stringify | 40.30 | — | — | 1315.52 (32.64x) | 218.26 (5.42x) |
| FalseBoolScalarValue JSON parse | 70.78 | — | — | 2025.81 (28.62x) | 334.72 (4.73x) |
| ListKindValue JSON stringify | 136.65 | — | — | 6097.01 (44.62x) | 2252.87 (16.49x) |
| ListKindValue JSON parse | 686.44 | — | — | 10389.10 (15.13x) | 4042.19 (5.89x) |
| ListKindValue Escape JSON parse | 709.54 | — | — | 10497.20 (14.79x) | 4256.57 (6.00x) |
| EmptyStructKindValue JSON stringify | 42.11 | — | — | 1977.89 (46.97x) | 533.93 (12.68x) |
| EmptyStructKindValue JSON parse | 110.39 | — | — | 3760.91 (34.07x) | 655.51 (5.94x) |
| EmptyListKindValue JSON stringify | 41.03 | — | — | 1936.07 (47.19x) | 359.01 (8.75x) |
| EmptyListKindValue JSON parse | 148.39 | — | — | 4031.27 (27.17x) | 596.21 (4.02x) |
| ListValue JSON stringify | 140.39 | — | — | 4720.67 (33.63x) | 2117.22 (15.08x) |
| ListValue JSON parse | 650.31 | — | — | 8518.88 (13.10x) | 3809.68 (5.86x) |
| ListValue Escape JSON parse | 672.92 | — | — | 8607.17 (12.79x) | 3998.66 (5.94x) |
| EmptyListValue JSON stringify | 40.08 | — | — | 684.36 (17.07x) | 342.18 (8.54x) |
| EmptyListValue JSON parse | 125.26 | — | — | 2241.83 (17.90x) | 529.04 (4.22x) |
| DoubleValue JSON stringify | 68.16 | — | — | 868.45 (12.74x) | 191.48 (2.81x) |
| DoubleValue JSON parse | 111.99 | — | — | 1239.56 (11.07x) | 290.75 (2.60x) |
| DoubleValue String JSON parse | 112.38 | — | — | 1181.16 (10.51x) | 360.72 (3.21x) |
| DoubleValue Exponent JSON parse | 113.30 | — | — | 1252.81 (11.06x) | 284.69 (2.51x) |
| NegativeDoubleValue JSON stringify | 69.06 | — | — | 872.71 (12.64x) | 185.20 (2.68x) |
| NegativeDoubleValue JSON parse | 111.40 | — | — | 1230.74 (11.05x) | 278.35 (2.50x) |
| ZeroDoubleValue JSON stringify | 47.13 | — | — | 806.54 (17.11x) | 227.09 (4.82x) |
| ZeroDoubleValue JSON parse | 107.65 | — | — | 1173.01 (10.90x) | 278.35 (2.59x) |
| DoubleValue NaN JSON stringify | 46.24 | — | — | 667.36 (14.43x) | 124.76 (2.70x) |
| DoubleValue NaN JSON parse | 105.88 | — | — | 1108.86 (10.47x) | 270.60 (2.56x) |
| DoubleValue Infinity JSON stringify | 47.38 | — | — | 667.58 (14.09x) | 125.62 (2.65x) |
| DoubleValue Infinity JSON parse | 106.13 | — | — | 1113.91 (10.50x) | 284.92 (2.68x) |
| DoubleValue NegativeInfinity JSON stringify | 47.67 | — | — | 662.49 (13.90x) | 127.07 (2.67x) |
| DoubleValue NegativeInfinity JSON parse | 109.51 | — | — | 1117.97 (10.21x) | 277.98 (2.54x) |
| FloatValue JSON stringify | 71.97 | — | — | 802.61 (11.15x) | 189.48 (2.63x) |
| FloatValue JSON parse | 117.35 | — | — | 1209.42 (10.31x) | 298.19 (2.54x) |
| FloatValue String JSON parse | 116.05 | — | — | 1150.86 (9.92x) | 366.22 (3.16x) |
| FloatValue Exponent JSON parse | 119.13 | — | — | 1223.90 (10.27x) | 290.13 (2.44x) |
| NegativeFloatValue JSON stringify | 71.73 | — | — | 797.49 (11.12x) | 182.54 (2.54x) |
| NegativeFloatValue JSON parse | 117.87 | — | — | 1227.23 (10.41x) | 285.85 (2.43x) |
| ZeroFloatValue JSON stringify | 47.49 | — | — | 741.35 (15.61x) | 144.21 (3.04x) |
| ZeroFloatValue JSON parse | 114.36 | — | — | 1161.73 (10.16x) | 258.78 (2.26x) |
| FloatValue NaN JSON stringify | 45.98 | — | — | 639.26 (13.90x) | 122.33 (2.66x) |
| FloatValue NaN JSON parse | 110.71 | — | — | 1089.22 (9.84x) | 264.86 (2.39x) |
| FloatValue Infinity JSON stringify | 47.38 | — | — | 645.43 (13.62x) | 123.32 (2.60x) |
| FloatValue Infinity JSON parse | 111.70 | — | — | 1114.45 (9.98x) | 258.63 (2.32x) |
| FloatValue NegativeInfinity JSON stringify | 47.63 | — | — | 637.65 (13.39x) | 124.06 (2.60x) |
| FloatValue NegativeInfinity JSON parse | 114.11 | — | — | 1100.25 (9.64x) | 277.09 (2.43x) |
| Int64Value JSON stringify | 50.21 | — | — | 674.85 (13.44x) | 275.55 (5.49x) |
| Int64Value JSON parse | 124.59 | — | — | 1232.88 (9.90x) | 474.97 (3.81x) |
| Int64Value Number JSON parse | 129.10 | — | — | 1283.65 (9.94x) | 377.77 (2.93x) |
| ZeroInt64Value JSON stringify | 41.50 | — | — | 611.12 (14.73x) | 199.47 (4.81x) |
| ZeroInt64Value JSON parse | 105.39 | — | — | 1097.69 (10.42x) | 338.89 (3.22x) |
| NegativeInt64Value JSON stringify | 48.41 | — | — | 673.73 (13.92x) | 413.64 (8.54x) |
| NegativeInt64Value JSON parse | 126.72 | — | — | 1214.89 (9.59x) | 483.83 (3.82x) |
| MinInt64Value JSON stringify | 49.53 | — | — | 674.29 (13.61x) | 279.74 (5.65x) |
| MinInt64Value JSON parse | 133.68 | — | — | 1250.74 (9.36x) | 481.11 (3.60x) |
| MaxInt64Value JSON stringify | 50.15 | — | — | 678.63 (13.53x) | 284.44 (5.67x) |
| MaxInt64Value JSON parse | 132.08 | — | — | 1251.30 (9.47x) | 478.74 (3.62x) |
| UInt64Value JSON stringify | 50.23 | — | — | 676.92 (13.48x) | 285.04 (5.67x) |
| UInt64Value JSON parse | 129.41 | — | — | 1210.86 (9.36x) | 462.63 (3.57x) |
| UInt64Value Number JSON parse | 132.18 | — | — | 1274.16 (9.64x) | 345.88 (2.62x) |
| ZeroUInt64Value JSON stringify | 41.72 | — | — | 609.58 (14.61x) | 199.22 (4.78x) |
| ZeroUInt64Value JSON parse | 110.25 | — | — | 1087.79 (9.87x) | 325.13 (2.95x) |
| MaxUInt64Value JSON stringify | 50.42 | — | — | 751.75 (14.91x) | 291.86 (5.79x) |
| MaxUInt64Value JSON parse | 135.69 | — | — | 1252.92 (9.23x) | 473.56 (3.49x) |
| Int32Value JSON stringify | 46.28 | — | — | 627.57 (13.56x) | 134.87 (2.91x) |
| Int32Value JSON parse | 132.81 | — | — | 1187.65 (8.94x) | 312.51 (2.35x) |
| Int32Value String JSON parse | 137.67 | — | — | 1137.46 (8.26x) | 403.37 (2.93x) |
| Int32Value Exponent JSON parse | 136.32 | — | — | 1229.77 (9.02x) | 360.53 (2.64x) |
| ZeroInt32Value JSON stringify | 46.04 | — | — | 617.47 (13.41x) | 130.75 (2.84x) |
| ZeroInt32Value JSON parse | 128.12 | — | — | 1156.86 (9.03x) | 268.24 (2.09x) |
| NegativeInt32Value JSON stringify | 64.42 | — | — | 640.57 (9.94x) | 143.04 (2.22x) |
| NegativeInt32Value JSON parse | 162.43 | — | — | 1192.67 (7.34x) | 366.10 (2.25x) |
| MinInt32Value JSON stringify | 64.50 | — | — | 636.43 (9.87x) | 139.86 (2.17x) |
| MinInt32Value JSON parse | 182.89 | — | — | 1205.19 (6.59x) | 363.69 (1.99x) |
| MaxInt32Value JSON stringify | 65.02 | — | — | 637.00 (9.80x) | 139.66 (2.15x) |
| MaxInt32Value JSON parse | 183.62 | — | — | 1204.56 (6.56x) | 333.52 (1.82x) |
| UInt32Value JSON stringify | 63.65 | — | — | 642.29 (10.09x) | 139.71 (2.19x) |
| UInt32Value JSON parse | 163.97 | — | — | 1188.03 (7.25x) | 333.98 (2.04x) |
| UInt32Value String JSON parse | 168.57 | — | — | 1131.36 (6.71x) | 419.28 (2.49x) |
| UInt32Value Exponent JSON parse | 173.68 | — | — | 1225.16 (7.05x) | 367.45 (2.12x) |
| ZeroUInt32Value JSON stringify | 63.15 | — | — | 625.38 (9.90x) | 134.47 (2.13x) |
| ZeroUInt32Value JSON parse | 153.10 | — | — | 1151.86 (7.52x) | 266.92 (1.74x) |
| MaxUInt32Value JSON stringify | 64.57 | — | — | 641.54 (9.94x) | 137.15 (2.12x) |
| MaxUInt32Value JSON parse | 183.48 | — | — | 1201.25 (6.55x) | 344.15 (1.88x) |
| BoolValue JSON stringify | 58.95 | — | — | 615.55 (10.44x) | 130.89 (2.22x) |
| BoolValue JSON parse | 75.07 | — | — | 1059.73 (14.12x) | 234.74 (3.13x) |
| FalseBoolValue JSON stringify | 58.84 | — | — | 601.18 (10.22x) | 124.54 (2.12x) |
| FalseBoolValue JSON parse | 75.02 | — | — | 1065.10 (14.20x) | 216.61 (2.89x) |
| StringValue JSON stringify | 75.52 | — | — | 671.40 (8.89x) | 188.04 (2.49x) |
| StringValue JSON parse | 150.11 | — | — | 1146.38 (7.64x) | 321.41 (2.14x) |
| StringValue Escape JSON parse | 163.50 | — | — | 1178.20 (7.21x) | 374.30 (2.29x) |
| EmptyStringValue JSON stringify | 66.97 | — | — | 636.87 (9.51x) | 199.40 (2.98x) |
| EmptyStringValue JSON parse | 80.72 | — | — | 1354.72 (16.78x) | 239.32 (2.96x) |
| BytesValue JSON stringify | 66.43 | — | — | 659.68 (9.93x) | 214.39 (3.23x) |
| BytesValue JSON parse | 158.34 | — | — | 1168.66 (7.38x) | 347.73 (2.20x) |
| BytesValue URL JSON parse | 179.72 | — | — | 1163.27 (6.47x) | 339.89 (1.89x) |
| EmptyBytesValue JSON stringify | 56.30 | — | — | 629.21 (11.18x) | 201.19 (3.57x) |
| EmptyBytesValue JSON parse | 83.97 | — | — | 1132.52 (13.49x) | 289.33 (3.45x) |
| TextFormat format | 295.34 | — | — | 2575.62 (8.72x) | 2584.52 (8.75x) |
| TextFormat parse | 1204.32 | — | — | 5003.16 (4.15x) | 6655.54 (5.53x) |
| packed fixed32 encode | 2.00 | 551.48 (275.74x) | 551.26 (275.63x) | 43.71 (21.86x) | 414.08 (207.04x) |
| packed fixed32 decode | 4.54 | 1038.57 (228.76x) | 1971.58 (434.27x) | 49.58 (10.92x) | 1558.45 (343.27x) |
| packed fixed64 encode | 2.69 | 574.08 (213.41x) | 571.80 (212.57x) | 75.85 (28.20x) | 394.29 (146.58x) |
| packed fixed64 decode | 8.96 | 1106.54 (123.50x) | 7958.81 (888.26x) | 79.47 (8.87x) | 2183.03 (243.64x) |
| packed sfixed32 encode | 2.01 | 555.75 (276.49x) | 539.64 (268.48x) | 43.31 (21.54x) | 406.84 (202.41x) |
| packed sfixed32 decode | 4.52 | 1043.73 (230.91x) | 1971.56 (436.19x) | 48.77 (10.79x) | 1552.75 (343.53x) |
| packed sfixed64 encode | 2.01 | 570.85 (284.00x) | 561.92 (279.56x) | 91.79 (45.67x) | 414.72 (206.33x) |
| packed sfixed64 decode | 4.53 | 1017.26 (224.56x) | 7912.65 (1746.72x) | 99.83 (22.04x) | 2162.61 (477.40x) |
| packed float encode | 2.01 | 808.46 (402.22x) | 539.56 (268.44x) | 59.19 (29.45x) | 366.49 (182.33x) |
| packed float decode | 4.53 | 1063.95 (234.87x) | 2082.61 (459.74x) | 67.35 (14.87x) | 1541.06 (340.19x) |
| packed double encode | 2.01 | 828.72 (412.30x) | 561.08 (279.14x) | 75.62 (37.62x) | 361.84 (180.02x) |
| packed double decode | 4.53 | 998.23 (220.36x) | 2056.90 (454.06x) | 78.77 (17.39x) | 2164.03 (477.71x) |
| packed uint64 encode | 1295.78 | 4595.73 (3.55x) | 4036.22 (3.11x) | 2125.24 (1.64x) | 3448.69 (2.66x) |
| packed uint64 decode | 1790.71 | 2787.99 (1.56x) | 8871.75 (4.95x) | 2799.65 (1.56x) | 6260.76 (3.50x) |
| packed uint32 encode | 927.04 | 3628.15 (3.91x) | 3264.86 (3.52x) | 1736.10 (1.87x) | 2886.51 (3.11x) |
| packed uint32 decode | 1304.85 | 2441.06 (1.87x) | 3259.98 (2.50x) | 1989.80 (1.52x) | 4746.34 (3.64x) |
| packed int64 encode | 1408.60 | 10963.56 (7.78x) | 6042.58 (4.29x) | 2923.05 (2.08x) | 4103.88 (2.91x) |
| packed int64 decode | 2742.70 | 3368.19 (1.23x) | 10257.90 (3.74x) | 4720.24 (1.72x) | 7741.96 (2.82x) |
| packed sint32 encode | 781.40 | 3039.18 (3.89x) | 2854.64 (3.65x) | 1521.25 (1.95x) | 3375.90 (4.32x) |
| packed sint32 decode | 952.13 | 2548.23 (2.68x) | 3185.94 (3.35x) | 1129.38 (1.19x) | 3015.25 (3.17x) |
| packed sint64 encode | 1422.60 | 4933.75 (3.47x) | 4300.11 (3.02x) | 2399.65 (1.69x) | 4134.71 (2.91x) |
| packed sint64 decode | 2038.17 | 3059.54 (1.50x) | 9652.29 (4.74x) | 2936.28 (1.44x) | 6481.77 (3.18x) |
| packed bool encode | 2.01 | 1339.59 (666.46x) | 519.44 (258.43x) | 15.97 (7.94x) | 2236.79 (1112.83x) |
| packed bool decode | 262.85 | 1558.35 (5.93x) | 2552.05 (9.71x) | 802.62 (3.05x) | 1576.12 (6.00x) |
| packed enum encode | 272.79 | 2713.05 (9.95x) | 1837.05 (6.73x) | 1090.01 (4.00x) | 2488.55 (9.12x) |
| packed enum decode | 153.35 | 1531.52 (9.99x) | 2957.94 (19.29x) | 864.07 (5.63x) | 2054.55 (13.40x) |
| large map encode | 4060.58 | 17706.29 (4.36x) | 9525.82 (2.35x) | 21276.80 (5.24x) | 209174.92 (51.51x) |
| shuffled large map deterministic binary encode | 27845.19 | — | — | 91020.70 (3.27x) | 436013.96 (15.66x) |
| large map decode | 25456.35 | 92065.57 (3.62x) | 89323.85 (3.51x) | 90986.50 (3.57x) | 277520.08 (10.90x) |
The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound `Duration`, non-empty/escaped-input parse/number-exponent parse and empty `Struct`, object/escaped-object parse/object-number-exponent/list/escaped-list/string-scalar/escaped-string-scalar/number-exponent/negative-number `Value` (including default-like scalar and empty object/list kinds),
`FieldMask` (non-empty, escaped JSON parse input, and empty), escaped-input parse/short-fraction parse/micro/nano/offset/min/pre/post/max-bound `Timestamp`, `Empty`, min/zero/positive/number-input parse/negative/max `Int64Value`, negative/zero/positive finite/string-input parse/numeric-exponent parse `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), negative/zero/positive finite/string-input parse/numeric-exponent parse `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), zero/normal/number-input parse/max `UInt64Value`, min/zero/positive/string-input parse/numeric-exponent parse/negative/max `Int32Value`, zero/normal/string-input parse/numeric-exponent parse/max `UInt32Value`, true/false `BoolValue`, non-empty/escape-input parse/empty `StringValue`, base64/base64url parse/empty `BytesValue`, and recursive nested `Any` payloads), direct zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound Duration, non-empty/escaped-input parse/empty FieldMask, and escaped-input parse/short-fraction parse/micro/nano/offset/min/pre/post/max-bound Timestamp WKT JSON plus other direct WKT JSON, including non-empty/escaped-input parse/number-exponent parse/empty `Struct`, object/escaped-object parse/object-number-exponent/list/escaped-list/string-scalar/escaped-string-scalar/number-exponent/negative-number `Value`, and escaped/non-empty/empty `ListValue`, TextFormat, packed scalars, large bytes,
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
