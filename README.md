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

Latest accepted comparison (`/tmp/pbz-compare-packed-u32-final.log`,
summarized in `/tmp/pbz-summary-packed-u32-final.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Pivoted rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 16.45 | 105.83 (6.43x) | 64.68 (3.93x) | 99.75 (6.06x) | 832.76 (50.62x) |
| binary decode | 84.71 | 255.43 (3.02x) | 301.24 (3.56x) | 216.54 (2.56x) | 921.16 (10.87x) |
| unknown fields count by number | 3.69 | — | — | 161.87 (43.87x) | — |
| deterministic binary encode | 67.94 | — | — | 125.80 (1.85x) | 1089.77 (16.04x) |
| scalarmix encode | 20.56 | 124.22 (6.04x) | 67.82 (3.30x) | 30.46 (1.48x) | 213.69 (10.39x) |
| scalarmix decode | 35.98 | 145.45 (4.04x) | 219.44 (6.10x) | 81.07 (2.25x) | 395.57 (10.99x) |
| textbytes encode | 13.88 | 81.40 (5.86x) | 45.20 (3.26x) | 117.47 (8.46x) | 149.80 (10.79x) |
| textbytes decode | 36.73 | 381.66 (10.39x) | 309.48 (8.43x) | 165.81 (4.51x) | 718.55 (19.56x) |
| TextBytes JSON stringify | 339.73 | — | — | 2246.79 (6.61x) | 2326.78 (6.85x) |
| TextBytes JSON parse | 1340.54 | — | — | 5643.63 (4.21x) | 3731.85 (2.78x) |
| largebytes encode | 17.55 | 2708.98 (154.36x) | 2684.46 (152.96x) | 2745.70 (156.45x) | 2701.40 (153.93x) |
| largebytes decode | 88.93 | 5654.85 (63.59x) | 3032.48 (34.10x) | 2722.98 (30.62x) | 23854.99 (268.24x) |
| presencemix encode | 16.99 | 55.76 (3.28x) | 26.64 (1.57x) | 55.00 (3.24x) | 225.78 (13.29x) |
| presencemix decode | 58.79 | 130.81 (2.23x) | 109.40 (1.86x) | 161.20 (2.74x) | 462.61 (7.87x) |
| PresenceMix JSON stringify | 138.08 | — | — | 3064.12 (22.19x) | 2298.65 (16.65x) |
| PresenceMix JSON parse | 1156.19 | — | — | 6160.59 (5.33x) | 3114.06 (2.69x) |
| complex encode | 51.82 | 134.06 (2.59x) | 116.41 (2.25x) | 160.45 (3.10x) | 901.56 (17.40x) |
| complex decode | 170.39 | 390.97 (2.29x) | 409.50 (2.40x) | 401.53 (2.36x) | 1457.16 (8.55x) |
| complex deterministic binary encode | 96.32 | — | — | 169.35 (1.76x) | 1134.19 (11.78x) |
| complex JSON stringify | 279.43 | — | — | 4903.07 (17.55x) | 6044.14 (21.63x) |
| complex JSON parse | 2424.34 | — | — | 12153.60 (5.01x) | 7506.94 (3.10x) |
| Complex ProtoName JSON stringify | 272.03 | — | — | 5241.62 (19.27x) | 6375.58 (23.44x) |
| Complex ProtoName JSON parse | 2417.92 | — | — | 12325.80 (5.10x) | 7561.04 (3.13x) |
| complex TextFormat format | 255.43 | — | — | 3960.09 (15.50x) | 5216.37 (20.42x) |
| complex TextFormat parse | 1865.11 | — | — | 6969.45 (3.74x) | 8427.97 (4.52x) |
| packed int32 encode | 637.06 | 3169.13 (4.97x) | 2519.89 (3.96x) | 2332.91 (3.66x) | 2957.29 (4.64x) |
| packed int32 decode | 702.43 | 1906.83 (2.71x) | 3227.30 (4.59x) | 1449.31 (2.06x) | 3192.79 (4.55x) |
| JSON stringify | 157.01 | — | — | 3024.49 (19.26x) | 2323.41 (14.80x) |
| AlwaysPrint JSON stringify | 60.70 | — | — | 2626.49 (43.27x) | 1343.43 (22.13x) |
| ProtoName JSON stringify | 316.47 | — | — | 4848.18 (15.32x) | 3853.24 (12.18x) |
| EnumNumber JSON stringify | 291.91 | — | — | 4790.83 (16.41x) | 4321.25 (14.80x) |
| JSON parse | 1487.46 | — | — | 7525.40 (5.06x) | 4474.29 (3.01x) |
| MapKeySurrogate JSON parse | 419.48 | — | — | 3563.48 (8.49x) | 991.93 (2.36x) |
| NullFields JSON parse | 502.54 | — | — | 2073.12 (4.13x) | 785.82 (1.56x) |
| IgnoreUnknown JSON parse | 1198.91 | — | — | 5409.89 (4.51x) | 2376.87 (1.98x) |
| OpenEnum JSON parse | 302.62 | — | — | 3795.35 (12.54x) | 513.28 (1.70x) |
| EnumName JSON parse | 300.69 | — | — | 3853.77 (12.82x) | 505.35 (1.68x) |
| ProtoName JSON parse | 530.24 | — | — | 4041.89 (7.62x) | 1177.43 (2.22x) |
| IntExponent JSON parse | 1687.06 | — | — | 7357.95 (4.36x) | 4237.01 (2.51x) |
| StringNumber JSON parse | 1653.16 | — | — | 7106.26 (4.30x) | 4540.06 (2.75x) |
| Any WKT JSON stringify | 132.55 | — | — | 1889.61 (14.26x) | 957.48 (7.22x) |
| Any WKT JSON parse | 538.20 | — | — | 3016.77 (5.61x) | 1492.07 (2.77x) |
| Any Duration Escape WKT JSON parse | 554.24 | — | — | 3050.02 (5.50x) | 1552.49 (2.80x) |
| Any PlusDuration WKT JSON parse | 530.19 | — | — | 3069.08 (5.79x) | 1540.85 (2.91x) |
| Any ShortFractionDuration WKT JSON parse | 529.37 | — | — | 2989.05 (5.65x) | 1629.76 (3.08x) |
| Any MicroDuration WKT JSON stringify | 132.57 | — | — | 1912.56 (14.43x) | 983.75 (7.42x) |
| Any MicroDuration WKT JSON parse | 531.29 | — | — | 3005.99 (5.66x) | 1490.28 (2.81x) |
| Any NanoDuration WKT JSON stringify | 132.50 | — | — | 1921.19 (14.50x) | 976.23 (7.37x) |
| Any NanoDuration WKT JSON parse | 534.32 | — | — | 3033.68 (5.68x) | 1508.95 (2.82x) |
| Any NegativeDuration WKT JSON stringify | 137.59 | — | — | 1984.48 (14.42x) | 1004.02 (7.30x) |
| Any NegativeDuration WKT JSON parse | 531.91 | — | — | 3135.91 (5.90x) | 1555.68 (2.92x) |
| Any FractionalNegativeDuration WKT JSON stringify | 124.12 | — | — | 1902.34 (15.33x) | 1040.28 (8.38x) |
| Any FractionalNegativeDuration WKT JSON parse | 525.84 | — | — | 3078.71 (5.85x) | 1539.68 (2.93x) |
| Any MaxDuration WKT JSON stringify | 115.34 | — | — | 1858.31 (16.11x) | 1047.96 (9.09x) |
| Any MaxDuration WKT JSON parse | 541.54 | — | — | 3022.64 (5.58x) | 1577.68 (2.91x) |
| Any MinDuration WKT JSON stringify | 117.76 | — | — | 1777.69 (15.10x) | 994.69 (8.45x) |
| Any MinDuration WKT JSON parse | 541.29 | — | — | 3037.00 (5.61x) | 1522.33 (2.81x) |
| Any ZeroDuration WKT JSON stringify | 107.81 | — | — | 941.14 (8.73x) | 952.24 (8.83x) |
| Any ZeroDuration WKT JSON parse | 474.92 | — | — | 2274.54 (4.79x) | 1469.03 (3.09x) |
| Any FieldMask WKT JSON stringify | 240.87 | — | — | 1772.45 (7.36x) | 1351.63 (5.61x) |
| Any FieldMask WKT JSON parse | 720.20 | — | — | 3206.46 (4.45x) | 2100.97 (2.92x) |
| Any FieldMask Escape WKT JSON parse | 752.18 | — | — | 3317.78 (4.41x) | 2214.65 (2.94x) |
| Any EmptyFieldMask WKT JSON stringify | 121.86 | — | — | 935.91 (7.68x) | 761.81 (6.25x) |
| Any EmptyFieldMask WKT JSON parse | 447.55 | — | — | 2231.97 (4.99x) | 1363.84 (3.05x) |
| Any Timestamp WKT JSON stringify | 176.93 | — | — | 2060.36 (11.65x) | 1007.77 (5.70x) |
| Any Timestamp WKT JSON parse | 578.99 | — | — | 3045.56 (5.26x) | 1591.04 (2.75x) |
| Any Timestamp Escape WKT JSON parse | 597.24 | — | — | 3084.00 (5.16x) | 1761.83 (2.95x) |
| Any ShortFraction Timestamp WKT JSON parse | 574.61 | — | — | 3017.64 (5.25x) | 1715.34 (2.99x) |
| Any Micro Timestamp WKT JSON stringify | 178.77 | — | — | 2063.32 (11.54x) | 1002.86 (5.61x) |
| Any Micro Timestamp WKT JSON parse | 585.28 | — | — | 3043.31 (5.20x) | 1709.58 (2.92x) |
| Any Nano Timestamp WKT JSON stringify | 176.74 | — | — | 2061.86 (11.67x) | 1001.83 (5.67x) |
| Any Nano Timestamp WKT JSON parse | 589.70 | — | — | 3045.61 (5.16x) | 1779.32 (3.02x) |
| Any Offset Timestamp WKT JSON parse | 600.27 | — | — | 3068.41 (5.11x) | 1634.91 (2.72x) |
| Any PreEpoch Timestamp WKT JSON stringify | 144.66 | — | — | 1977.95 (13.67x) | 955.55 (6.61x) |
| Any PreEpoch Timestamp WKT JSON parse | 571.37 | — | — | 3064.23 (5.36x) | 1545.45 (2.70x) |
| Any Max Timestamp WKT JSON stringify | 162.10 | — | — | 2081.82 (12.84x) | 972.88 (6.00x) |
| Any Max Timestamp WKT JSON parse | 593.44 | — | — | 3114.77 (5.25x) | 1707.82 (2.88x) |
| Any Min Timestamp WKT JSON stringify | 161.47 | — | — | 1971.21 (12.21x) | 967.79 (5.99x) |
| Any Min Timestamp WKT JSON parse | 570.77 | — | — | 3046.09 (5.34x) | 1544.03 (2.71x) |
| Any Empty WKT JSON stringify | 99.73 | — | — | 917.13 (9.20x) | 641.18 (6.43x) |
| Any Empty WKT JSON parse | 345.57 | — | — | 2133.45 (6.17x) | 1388.14 (4.02x) |
| Any Struct WKT JSON stringify | 631.36 | — | — | 5824.63 (9.23x) | 6521.01 (10.33x) |
| Any Struct WKT JSON parse | 1775.65 | — | — | 11212.90 (6.31x) | 8448.16 (4.76x) |
| Any Struct Escape WKT JSON parse | 1823.70 | — | — | 11331.80 (6.21x) | 8604.37 (4.72x) |
| Any Struct NumberExponent WKT JSON parse | 1778.91 | — | — | 11163.00 (6.28x) | 8516.17 (4.79x) |
| Any Struct Surrogate WKT JSON parse | 759.95 | — | — | 6419.34 (8.45x) | 2995.79 (3.94x) |
| Any Struct KeySurrogate WKT JSON parse | 760.23 | — | — | 9457.08 (12.44x) | 2947.85 (3.88x) |
| Any EmptyStruct WKT JSON stringify | 119.36 | — | — | 1302.81 (10.91x) | 928.84 (7.78x) |
| Any EmptyStruct WKT JSON parse | 444.10 | — | — | 3375.55 (7.60x) | 1575.79 (3.55x) |
| Any Value WKT JSON stringify | 665.95 | — | — | 9067.50 (13.62x) | 6441.88 (9.67x) |
| Any Value WKT JSON parse | 1818.54 | — | — | 17611.20 (9.68x) | 9525.12 (5.24x) |
| Any Value Escape WKT JSON parse | 1845.96 | — | — | 11672.10 (6.32x) | 9199.06 (4.98x) |
| Any Value NumberExponent WKT JSON parse | 1811.52 | — | — | 11461.30 (6.33x) | 9015.53 (4.98x) |
| Any Value Surrogate WKT JSON parse | 810.93 | — | — | 6604.90 (8.14x) | 3422.93 (4.22x) |
| Any Value KeySurrogate WKT JSON parse | 816.39 | — | — | 6578.49 (8.06x) | 3339.67 (4.09x) |
| Any NullValue WKT JSON stringify | 133.21 | — | — | 2293.69 (17.22x) | 894.54 (6.72x) |
| Any NullValue WKT JSON parse | 465.30 | — | — | 6025.30 (12.95x) | 1556.02 (3.34x) |
| Any StringScalarValue WKT JSON stringify | 153.83 | — | — | 3276.51 (21.30x) | 1007.55 (6.55x) |
| Any StringScalarValue WKT JSON parse | 519.71 | — | — | 5411.39 (10.41x) | 1650.71 (3.18x) |
| Any StringScalarValue Escape WKT JSON parse | 532.70 | — | — | 3722.59 (6.99x) | 1761.30 (3.31x) |
| Any StringScalarValue Surrogate WKT JSON parse | 534.11 | — | — | 3698.59 (6.92x) | 1782.51 (3.34x) |
| Any EmptyStringScalarValue WKT JSON stringify | 144.41 | — | — | 2306.99 (15.98x) | 993.76 (6.88x) |
| Any EmptyStringScalarValue WKT JSON parse | 492.29 | — | — | 3651.33 (7.42x) | 1561.55 (3.17x) |
| Any NumberValue WKT JSON stringify | 172.23 | — | — | 2541.77 (14.76x) | 1038.45 (6.03x) |
| Any NumberValue WKT JSON parse | 508.13 | — | — | 3712.24 (7.31x) | 1648.18 (3.24x) |
| Any NumberValue Exponent WKT JSON parse | 510.20 | — | — | 3728.27 (7.31x) | 1648.11 (3.23x) |
| Any NegativeNumberValue WKT JSON stringify | 189.00 | — | — | 2536.17 (13.42x) | 1098.43 (5.81x) |
| Any NegativeNumberValue WKT JSON parse | 509.82 | — | — | 3737.59 (7.33x) | 1785.86 (3.50x) |
| Any ZeroNumberValue WKT JSON stringify | 141.87 | — | — | 2485.46 (17.52x) | 945.34 (6.66x) |
| Any ZeroNumberValue WKT JSON parse | 505.08 | — | — | 3652.58 (7.23x) | 1964.86 (3.89x) |
| Any BoolScalarValue WKT JSON stringify | 139.04 | — | — | 2274.18 (16.36x) | 911.84 (6.56x) |
| Any BoolScalarValue WKT JSON parse | 462.73 | — | — | 3632.34 (7.85x) | 1514.97 (3.27x) |
| Any FalseBoolScalarValue WKT JSON stringify | 133.25 | — | — | 3238.60 (24.30x) | 925.26 (6.94x) |
| Any FalseBoolScalarValue WKT JSON parse | 466.12 | — | — | 5492.31 (11.78x) | 1542.38 (3.31x) |
| Any ListKindValue WKT JSON stringify | 512.54 | — | — | 8756.66 (17.08x) | 4900.99 (9.56x) |
| Any ListKindValue WKT JSON parse | 1397.99 | — | — | 9995.04 (7.15x) | 6948.15 (4.97x) |
| Any ListKindValue Escape WKT JSON parse | 1418.82 | — | — | 10230.30 (7.21x) | 7714.14 (5.44x) |
| Any ListKindValue Surrogate WKT JSON parse | 734.75 | — | — | 7512.01 (10.22x) | 2613.77 (3.56x) |
| Any EmptyStructKindValue WKT JSON stringify | 144.59 | — | — | 3883.89 (26.86x) | 1473.44 (10.19x) |
| Any EmptyStructKindValue WKT JSON parse | 505.16 | — | — | 5436.33 (10.76x) | 2127.11 (4.21x) |
| Any EmptyListKindValue WKT JSON stringify | 145.25 | — | — | 2910.99 (20.04x) | 1146.04 (7.89x) |
| Any EmptyListKindValue WKT JSON parse | 503.36 | — | — | 4392.34 (8.73x) | 1980.02 (3.93x) |
| Any DoubleValue WKT JSON stringify | 189.61 | — | — | 2621.13 (13.82x) | 799.98 (4.22x) |
| Any DoubleValue WKT JSON parse | 533.94 | — | — | 4654.03 (8.72x) | 1415.75 (2.65x) |
| Any DoubleValue String WKT JSON parse | 545.47 | — | — | 4679.41 (8.58x) | 1445.97 (2.65x) |
| Any DoubleValue Exponent WKT JSON parse | 537.02 | — | — | 4714.05 (8.78x) | 1399.55 (2.61x) |
| Any NegativeDoubleValue WKT JSON stringify | 198.76 | — | — | 3078.75 (15.49x) | 810.70 (4.08x) |
| Any NegativeDoubleValue WKT JSON parse | 535.36 | — | — | 4706.72 (8.79x) | 1453.51 (2.72x) |
| Any ZeroDoubleValue WKT JSON stringify | 160.61 | — | — | 1468.17 (9.14x) | 717.94 (4.47x) |
| Any ZeroDoubleValue WKT JSON parse | 528.70 | — | — | 3484.45 (6.59x) | 1402.31 (2.65x) |
| Any DoubleValue NaN WKT JSON stringify | 158.09 | — | — | 2516.61 (15.92x) | 693.84 (4.39x) |
| Any DoubleValue NaN WKT JSON parse | 529.70 | — | — | 4354.22 (8.22x) | 1388.69 (2.62x) |
| Any DoubleValue Infinity WKT JSON stringify | 169.46 | — | — | 2314.94 (13.66x) | 719.66 (4.25x) |
| Any DoubleValue Infinity WKT JSON parse | 532.93 | — | — | 4132.53 (7.75x) | 1512.85 (2.84x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 171.92 | — | — | 1576.55 (9.17x) | 705.90 (4.11x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 532.63 | — | — | 4225.20 (7.93x) | 1423.42 (2.67x) |
| Any FloatValue WKT JSON stringify | 193.97 | — | — | 2766.11 (14.26x) | 792.98 (4.09x) |
| Any FloatValue WKT JSON parse | 527.22 | — | — | 4600.17 (8.73x) | 1631.26 (3.09x) |
| Any FloatValue String WKT JSON parse | 541.97 | — | — | 4608.85 (8.50x) | 1522.44 (2.81x) |
| Any FloatValue Exponent WKT JSON parse | 531.77 | — | — | 4472.39 (8.41x) | 1328.90 (2.50x) |
| Any NegativeFloatValue WKT JSON stringify | 193.77 | — | — | 2790.63 (14.40x) | 779.06 (4.02x) |
| Any NegativeFloatValue WKT JSON parse | 528.75 | — | — | 4651.64 (8.80x) | 1460.81 (2.76x) |
| Any ZeroFloatValue WKT JSON stringify | 160.35 | — | — | 1437.59 (8.97x) | 727.72 (4.54x) |
| Any ZeroFloatValue WKT JSON parse | 524.82 | — | — | 3259.03 (6.21x) | 1426.37 (2.72x) |
| Any FloatValue NaN WKT JSON stringify | 153.38 | — | — | 2300.49 (15.00x) | 689.91 (4.50x) |
| Any FloatValue NaN WKT JSON parse | 523.76 | — | — | 4124.60 (7.87x) | 1370.38 (2.62x) |
| Any FloatValue Infinity WKT JSON stringify | 162.78 | — | — | 2223.06 (13.66x) | 719.49 (4.42x) |
| Any FloatValue Infinity WKT JSON parse | 530.02 | — | — | 4259.08 (8.04x) | 1382.68 (2.61x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 164.22 | — | — | 2252.16 (13.71x) | 702.59 (4.28x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 529.78 | — | — | 3489.02 (6.59x) | 1440.58 (2.72x) |
| Any Int64Value WKT JSON stringify | 167.69 | — | — | 1603.63 (9.56x) | 843.17 (5.03x) |
| Any Int64Value WKT JSON parse | 554.69 | — | — | 2804.15 (5.06x) | 1783.53 (3.22x) |
| Any Int64Value Number WKT JSON parse | 554.96 | — | — | 2787.94 (5.02x) | 1443.85 (2.60x) |
| Any Int64Value Exponent WKT JSON parse | 539.89 | — | — | 2731.50 (5.06x) | 1437.71 (2.66x) |
| Any ZeroInt64Value WKT JSON stringify | 160.82 | — | — | 909.44 (5.66x) | 755.92 (4.70x) |
| Any ZeroInt64Value WKT JSON parse | 530.76 | — | — | 2166.88 (4.08x) | 1523.35 (2.87x) |
| Any NegativeInt64Value WKT JSON stringify | 164.68 | — | — | 1574.25 (9.56x) | 806.64 (4.90x) |
| Any NegativeInt64Value WKT JSON parse | 558.73 | — | — | 2895.61 (5.18x) | 1696.11 (3.04x) |
| Any MinInt64Value WKT JSON stringify | 166.74 | — | — | 1595.60 (9.57x) | 851.76 (5.11x) |
| Any MinInt64Value WKT JSON parse | 564.58 | — | — | 3154.88 (5.59x) | 1767.81 (3.13x) |
| Any MaxInt64Value WKT JSON stringify | 165.63 | — | — | 1585.98 (9.58x) | 824.71 (4.98x) |
| Any MaxInt64Value WKT JSON parse | 561.23 | — | — | 2848.83 (5.08x) | 1870.79 (3.33x) |
| Any UInt64Value WKT JSON stringify | 172.59 | — | — | 1586.20 (9.19x) | 1056.30 (6.12x) |
| Any UInt64Value WKT JSON parse | 562.56 | — | — | 2838.92 (5.05x) | 2386.51 (4.24x) |
| Any UInt64Value Number WKT JSON parse | 558.28 | — | — | 2812.83 (5.04x) | 1702.53 (3.05x) |
| Any UInt64Value Exponent WKT JSON parse | 546.51 | — | — | 2761.40 (5.05x) | 1425.59 (2.61x) |
| Any ZeroUInt64Value WKT JSON stringify | 163.05 | — | — | 930.66 (5.71x) | 757.94 (4.65x) |
| Any ZeroUInt64Value WKT JSON parse | 536.12 | — | — | 2220.58 (4.14x) | 1519.62 (2.83x) |
| Any MaxUInt64Value WKT JSON stringify | 173.42 | — | — | 1602.41 (9.24x) | 948.17 (5.47x) |
| Any MaxUInt64Value WKT JSON parse | 572.60 | — | — | 4506.20 (7.87x) | 1701.38 (2.97x) |
| Any Int32Value WKT JSON stringify | 168.40 | — | — | 1574.90 (9.35x) | 748.40 (4.44x) |
| Any Int32Value WKT JSON parse | 545.70 | — | — | 2687.30 (4.92x) | 1439.90 (2.64x) |
| Any Int32Value String WKT JSON parse | 552.90 | — | — | 2690.03 (4.87x) | 1489.56 (2.69x) |
| Any Int32Value Exponent WKT JSON parse | 552.53 | — | — | 2716.61 (4.92x) | 1435.37 (2.60x) |
| Any ZeroInt32Value WKT JSON stringify | 169.15 | — | — | 923.12 (5.46x) | 710.20 (4.20x) |
| Any ZeroInt32Value WKT JSON parse | 540.36 | — | — | 2184.23 (4.04x) | 1363.71 (2.52x) |
| Any NegativeInt32Value WKT JSON stringify | 164.80 | — | — | 2312.16 (14.03x) | 693.50 (4.21x) |
| Any NegativeInt32Value WKT JSON parse | 546.60 | — | — | 4059.24 (7.43x) | 1494.18 (2.73x) |
| Any MinInt32Value WKT JSON stringify | 177.61 | — | — | 2236.92 (12.59x) | 771.65 (4.34x) |
| Any MinInt32Value WKT JSON parse | 552.16 | — | — | 4217.01 (7.64x) | 1473.32 (2.67x) |
| Any MaxInt32Value WKT JSON stringify | 172.48 | — | — | 2239.84 (12.99x) | 717.20 (4.16x) |
| Any MaxInt32Value WKT JSON parse | 551.25 | — | — | 4162.46 (7.55x) | 1434.02 (2.60x) |
| Any UInt32Value WKT JSON stringify | 176.53 | — | — | 1584.01 (8.97x) | 722.69 (4.09x) |
| Any UInt32Value WKT JSON parse | 544.88 | — | — | 2717.52 (4.99x) | 1444.64 (2.65x) |
| Any UInt32Value String WKT JSON parse | 563.55 | — | — | 2835.88 (5.03x) | 1818.35 (3.23x) |
| Any UInt32Value Exponent WKT JSON parse | 555.12 | — | — | 2767.86 (4.99x) | 1600.01 (2.88x) |
| Any ZeroUInt32Value WKT JSON stringify | 172.19 | — | — | 930.87 (5.41x) | 703.05 (4.08x) |
| Any ZeroUInt32Value WKT JSON parse | 539.72 | — | — | 2173.06 (4.03x) | 1529.04 (2.83x) |
| Any MaxUInt32Value WKT JSON stringify | 175.23 | — | — | 1574.14 (8.98x) | 766.36 (4.37x) |
| Any MaxUInt32Value WKT JSON parse | 551.31 | — | — | 2731.30 (4.95x) | 1664.75 (3.02x) |
| Any BoolValue WKT JSON stringify | 174.58 | — | — | 2044.73 (11.71x) | 737.80 (4.23x) |
| Any BoolValue WKT JSON parse | 491.10 | — | — | 3032.38 (6.17x) | 1355.07 (2.76x) |
| Any FalseBoolValue WKT JSON stringify | 170.69 | — | — | 1483.48 (8.69x) | 690.22 (4.04x) |
| Any FalseBoolValue WKT JSON parse | 494.33 | — | — | 3425.37 (6.93x) | 1552.33 (3.14x) |
| Any StringValue WKT JSON stringify | 203.73 | — | — | 1565.73 (7.69x) | 801.39 (3.93x) |
| Any StringValue WKT JSON parse | 562.49 | — | — | 2676.68 (4.76x) | 1413.09 (2.51x) |
| Any StringValue Escape WKT JSON parse | 569.47 | — | — | 4480.98 (7.87x) | 1545.84 (2.71x) |
| Any StringValue Surrogate WKT JSON parse | 571.31 | — | — | 4495.44 (7.87x) | 1721.66 (3.01x) |
| Any EmptyStringValue WKT JSON stringify | 201.00 | — | — | 1428.36 (7.11x) | 749.18 (3.73x) |
| Any EmptyStringValue WKT JSON parse | 531.24 | — | — | 3456.02 (6.51x) | 1444.50 (2.72x) |
| Any BytesValue WKT JSON stringify | 192.07 | — | — | 1605.41 (8.36x) | 815.90 (4.25x) |
| Any BytesValue WKT JSON parse | 575.10 | — | — | 2710.29 (4.71x) | 1464.31 (2.55x) |
| Any BytesValue URL WKT JSON parse | 590.76 | — | — | 4479.32 (7.58x) | 1425.88 (2.41x) |
| Any BytesValue StandardBase64 WKT JSON parse | 577.25 | — | — | 4516.40 (7.82x) | 1531.95 (2.65x) |
| Any BytesValue Unpadded WKT JSON parse | 578.68 | — | — | 4470.17 (7.72x) | 1388.68 (2.40x) |
| Any EmptyBytesValue WKT JSON stringify | 191.06 | — | — | 1413.23 (7.40x) | 775.83 (4.06x) |
| Any EmptyBytesValue WKT JSON parse | 541.66 | — | — | 3387.42 (6.25x) | 1497.38 (2.76x) |
| Nested Any WKT JSON stringify | 303.09 | — | — | 2490.10 (8.22x) | 1488.26 (4.91x) |
| Nested Any WKT JSON parse | 881.44 | — | — | 4294.56 (4.87x) | 2889.69 (3.28x) |
| Duration JSON stringify | 57.14 | — | — | 1538.62 (26.93x) | 337.20 (5.90x) |
| Duration JSON parse | 20.94 | — | — | 2310.91 (110.36x) | 391.72 (18.71x) |
| Duration Escape JSON parse | 40.96 | — | — | 2397.99 (58.54x) | 426.49 (10.41x) |
| PlusDuration JSON parse | 22.56 | — | — | 2333.73 (103.45x) | 400.32 (17.74x) |
| ShortFractionDuration JSON parse | 18.56 | — | — | 2292.72 (123.53x) | 366.16 (19.73x) |
| MicroDuration JSON stringify | 59.21 | — | — | 1541.49 (26.03x) | 392.66 (6.63x) |
| MicroDuration JSON parse | 21.84 | — | — | 2331.63 (106.76x) | 378.60 (17.34x) |
| NanoDuration JSON stringify | 56.71 | — | — | 1585.51 (27.96x) | 402.66 (7.10x) |
| NanoDuration JSON parse | 27.17 | — | — | 2381.33 (87.65x) | 387.70 (14.27x) |
| NegativeDuration JSON stringify | 57.92 | — | — | 1623.67 (28.03x) | 417.96 (7.22x) |
| NegativeDuration JSON parse | 20.12 | — | — | 2408.02 (119.68x) | 367.33 (18.26x) |
| FractionalNegativeDuration JSON stringify | 58.26 | — | — | 1562.65 (26.82x) | 422.30 (7.25x) |
| FractionalNegativeDuration JSON parse | 21.07 | — | — | 2325.59 (110.37x) | 357.75 (16.98x) |
| MaxDuration JSON stringify | 49.19 | — | — | 1333.85 (27.12x) | 402.41 (8.18x) |
| MaxDuration JSON parse | 32.90 | — | — | 2261.22 (68.73x) | 392.23 (11.92x) |
| MinDuration JSON stringify | 49.42 | — | — | 1355.09 (27.42x) | 428.83 (8.68x) |
| MinDuration JSON parse | 37.51 | — | — | 2291.93 (61.10x) | 396.20 (10.56x) |
| ZeroDuration JSON stringify | 44.36 | — | — | 1287.80 (29.03x) | 345.72 (7.79x) |
| ZeroDuration JSON parse | 16.69 | — | — | 2135.71 (127.96x) | 292.55 (17.53x) |
| FieldMask JSON stringify | 65.25 | — | — | 1347.44 (20.65x) | 642.85 (9.85x) |
| FieldMask JSON parse | 139.30 | — | — | 2725.63 (19.57x) | 858.17 (6.16x) |
| FieldMask Escape JSON parse | 192.19 | — | — | 2807.52 (14.61x) | 1041.15 (5.42x) |
| EmptyFieldMask JSON stringify | 40.88 | — | — | 964.32 (23.59x) | 182.33 (4.46x) |
| EmptyFieldMask JSON parse | 4.79 | — | — | 1481.79 (309.35x) | 172.86 (36.09x) |
| Timestamp JSON stringify | 95.75 | — | — | 1746.73 (18.24x) | 416.39 (4.35x) |
| Timestamp JSON parse | 46.47 | — | — | 2345.86 (50.48x) | 437.73 (9.42x) |
| Timestamp Escape JSON parse | 87.75 | — | — | 2400.30 (27.35x) | 515.38 (5.87x) |
| ShortFraction Timestamp JSON parse | 43.62 | — | — | 2321.97 (53.23x) | 432.10 (9.91x) |
| Micro Timestamp JSON stringify | 96.68 | — | — | 1777.25 (18.38x) | 438.86 (4.54x) |
| Micro Timestamp JSON parse | 47.40 | — | — | 1726.69 (36.43x) | 456.92 (9.64x) |
| Nano Timestamp JSON stringify | 93.95 | — | — | 1192.11 (12.69x) | 429.27 (4.57x) |
| Nano Timestamp JSON parse | 52.23 | — | — | 1524.97 (29.20x) | 456.83 (8.75x) |
| Offset Timestamp JSON parse | 51.88 | — | — | 1524.28 (29.38x) | 481.72 (9.29x) |
| PreEpoch Timestamp JSON stringify | 66.47 | — | — | 1062.84 (15.99x) | 421.95 (6.35x) |
| PreEpoch Timestamp JSON parse | 43.19 | — | — | 1466.74 (33.96x) | 419.17 (9.71x) |
| Max Timestamp JSON stringify | 78.65 | — | — | 1202.22 (15.29x) | 430.53 (5.47x) |
| Max Timestamp JSON parse | 51.47 | — | — | 1546.13 (30.04x) | 451.52 (8.77x) |
| Min Timestamp JSON stringify | 80.15 | — | — | 1069.62 (13.35x) | 409.01 (5.10x) |
| Min Timestamp JSON parse | 41.04 | — | — | 1453.98 (35.43x) | 416.49 (10.15x) |
| Empty JSON stringify | 20.85 | — | — | 506.82 (24.31x) | 78.96 (3.79x) |
| Empty JSON parse | 68.44 | — | — | 721.75 (10.55x) | 204.05 (2.98x) |
| Struct JSON stringify | 172.43 | — | — | 7761.24 (45.01x) | 2984.24 (17.31x) |
| Struct JSON parse | 845.62 | — | — | 11201.40 (13.25x) | 4536.51 (5.36x) |
| Struct Escape JSON parse | 897.90 | — | — | 11399.60 (12.70x) | 4802.84 (5.35x) |
| Struct NumberExponent JSON parse | 845.51 | — | — | 11064.00 (13.09x) | 4498.30 (5.32x) |
| Struct Surrogate JSON parse | 374.52 | — | — | 4804.49 (12.83x) | 1155.54 (3.09x) |
| Struct KeySurrogate JSON parse | 374.67 | — | — | 6730.33 (17.96x) | 1135.45 (3.03x) |
| EmptyStruct JSON stringify | 40.35 | — | — | 690.52 (17.11x) | 338.29 (8.38x) |
| EmptyStruct JSON parse | 87.20 | — | — | 2020.25 (23.17x) | 342.54 (3.93x) |
| Value JSON stringify | 176.39 | — | — | 6715.56 (38.07x) | 3119.80 (17.69x) |
| Value JSON parse | 868.74 | — | — | 18671.80 (21.49x) | 4885.72 (5.62x) |
| Value Escape JSON parse | 917.78 | — | — | 17402.20 (18.96x) | 5014.93 (5.46x) |
| Value NumberExponent JSON parse | 861.93 | — | — | 13255.20 (15.38x) | 4953.30 (5.75x) |
| Value Surrogate JSON parse | 396.37 | — | — | 7000.13 (17.66x) | 1431.72 (3.61x) |
| Value KeySurrogate JSON parse | 395.71 | — | — | 6800.84 (17.19x) | 1418.60 (3.58x) |
| NullValue JSON stringify | 40.25 | — | — | 2229.32 (55.39x) | 240.04 (5.96x) |
| NullValue JSON parse | 70.36 | — | — | 4581.83 (65.12x) | 331.10 (4.71x) |
| StringScalarValue JSON stringify | 47.42 | — | — | 1960.39 (41.34x) | 289.82 (6.11x) |
| StringScalarValue JSON parse | 140.62 | — | — | 3196.88 (22.73x) | 417.21 (2.97x) |
| StringScalarValue Escape JSON parse | 151.14 | — | — | 2146.18 (14.20x) | 453.09 (3.00x) |
| StringScalarValue Surrogate JSON parse | 148.84 | — | — | 2163.43 (14.54x) | 477.92 (3.21x) |
| EmptyStringScalarValue JSON stringify | 45.77 | — | — | 1354.19 (29.59x) | 254.76 (5.57x) |
| EmptyStringScalarValue JSON parse | 88.01 | — | — | 2436.40 (27.68x) | 340.00 (3.86x) |
| NumberValue JSON stringify | 73.31 | — | — | 1844.76 (25.16x) | 331.55 (4.52x) |
| NumberValue JSON parse | 133.71 | — | — | 2184.96 (16.34x) | 405.61 (3.03x) |
| NumberValue Exponent JSON parse | 136.72 | — | — | 2200.84 (16.10x) | 416.19 (3.04x) |
| NegativeNumberValue JSON stringify | 74.63 | — | — | 1557.90 (20.87x) | 321.57 (4.31x) |
| NegativeNumberValue JSON parse | 135.08 | — | — | 2181.47 (16.15x) | 404.22 (2.99x) |
| ZeroNumberValue JSON stringify | 50.97 | — | — | 1515.78 (29.74x) | 288.31 (5.66x) |
| ZeroNumberValue JSON parse | 130.56 | — | — | 2113.88 (16.19x) | 376.08 (2.88x) |
| BoolScalarValue JSON stringify | 40.30 | — | — | 1316.40 (32.67x) | 214.78 (5.33x) |
| BoolScalarValue JSON parse | 70.19 | — | — | 2018.38 (28.76x) | 321.40 (4.58x) |
| FalseBoolScalarValue JSON stringify | 40.30 | — | — | 1317.42 (32.69x) | 215.16 (5.34x) |
| FalseBoolScalarValue JSON parse | 70.73 | — | — | 2023.21 (28.60x) | 317.87 (4.49x) |
| ListKindValue JSON stringify | 137.06 | — | — | 7669.77 (55.96x) | 2429.05 (17.72x) |
| ListKindValue JSON parse | 671.99 | — | — | 11199.10 (16.67x) | 4064.88 (6.05x) |
| ListKindValue Escape JSON parse | 693.31 | — | — | 10873.10 (15.68x) | 4370.73 (6.30x) |
| ListKindValue Surrogate JSON parse | 321.62 | — | — | 5247.62 (16.32x) | 1136.03 (3.53x) |
| EmptyStructKindValue JSON stringify | 42.12 | — | — | 2991.80 (71.03x) | 523.47 (12.43x) |
| EmptyStructKindValue JSON parse | 110.83 | — | — | 6351.81 (57.31x) | 603.99 (5.45x) |
| EmptyListKindValue JSON stringify | 41.08 | — | — | 3120.97 (75.97x) | 368.77 (8.98x) |
| EmptyListKindValue JSON parse | 147.97 | — | — | 6424.19 (43.42x) | 600.43 (4.06x) |
| ListValue JSON stringify | 137.01 | — | — | 8763.97 (63.97x) | 2151.41 (15.70x) |
| ListValue JSON parse | 648.93 | — | — | 18081.00 (27.86x) | 3737.40 (5.76x) |
| ListValue Escape JSON parse | 676.11 | — | — | 20028.30 (29.62x) | 3727.74 (5.51x) |
| ListValue Surrogate JSON parse | 297.69 | — | — | 7229.83 (24.29x) | 895.02 (3.01x) |
| EmptyListValue JSON stringify | 40.22 | — | — | 1171.67 (29.13x) | 171.78 (4.27x) |
| EmptyListValue JSON parse | 125.16 | — | — | 3548.03 (28.35x) | 282.33 (2.26x) |
| DoubleValue JSON stringify | 69.57 | — | — | 1526.53 (21.94x) | 188.57 (2.71x) |
| DoubleValue JSON parse | 111.23 | — | — | 2052.95 (18.46x) | 291.79 (2.62x) |
| DoubleValue String JSON parse | 111.80 | — | — | 2055.75 (18.39x) | 362.94 (3.25x) |
| DoubleValue Exponent JSON parse | 114.27 | — | — | 2162.93 (18.93x) | 284.31 (2.49x) |
| NegativeDoubleValue JSON stringify | 68.16 | — | — | 1675.75 (24.59x) | 190.98 (2.80x) |
| NegativeDoubleValue JSON parse | 112.92 | — | — | 2353.46 (20.84x) | 276.15 (2.45x) |
| ZeroDoubleValue JSON stringify | 47.27 | — | — | 1472.69 (31.15x) | 143.43 (3.03x) |
| ZeroDoubleValue JSON parse | 108.05 | — | — | 1986.99 (18.39x) | 251.35 (2.33x) |
| DoubleValue NaN JSON stringify | 47.93 | — | — | 1115.70 (23.28x) | 131.61 (2.75x) |
| DoubleValue NaN JSON parse | 104.86 | — | — | 1861.94 (17.76x) | 300.40 (2.86x) |
| DoubleValue Infinity JSON stringify | 49.38 | — | — | 1071.05 (21.69x) | 132.53 (2.68x) |
| DoubleValue Infinity JSON parse | 105.79 | — | — | 1866.04 (17.64x) | 269.97 (2.55x) |
| DoubleValue NegativeInfinity JSON stringify | 49.63 | — | — | 1003.31 (20.22x) | 129.06 (2.60x) |
| DoubleValue NegativeInfinity JSON parse | 108.04 | — | — | 1114.19 (10.31x) | 302.86 (2.80x) |
| FloatValue JSON stringify | 70.59 | — | — | 1459.48 (20.68x) | 288.02 (4.08x) |
| FloatValue JSON parse | 112.35 | — | — | 2174.15 (19.35x) | 272.53 (2.43x) |
| FloatValue String JSON parse | 111.08 | — | — | 2097.66 (18.88x) | 368.51 (3.32x) |
| FloatValue Exponent JSON parse | 114.49 | — | — | 2134.15 (18.64x) | 283.92 (2.48x) |
| NegativeFloatValue JSON stringify | 71.00 | — | — | 1390.43 (19.58x) | 193.09 (2.72x) |
| NegativeFloatValue JSON parse | 113.61 | — | — | 2117.97 (18.64x) | 300.35 (2.64x) |
| ZeroFloatValue JSON stringify | 47.56 | — | — | 1410.31 (29.65x) | 146.57 (3.08x) |
| ZeroFloatValue JSON parse | 109.18 | — | — | 1980.89 (18.14x) | 278.07 (2.55x) |
| FloatValue NaN JSON stringify | 47.88 | — | — | 994.78 (20.78x) | 122.43 (2.56x) |
| FloatValue NaN JSON parse | 105.15 | — | — | 1725.22 (16.41x) | 271.14 (2.58x) |
| FloatValue Infinity JSON stringify | 49.47 | — | — | 981.64 (19.84x) | 132.62 (2.68x) |
| FloatValue Infinity JSON parse | 106.74 | — | — | 1724.25 (16.15x) | 256.67 (2.40x) |
| FloatValue NegativeInfinity JSON stringify | 49.63 | — | — | 1059.98 (21.36x) | 130.42 (2.63x) |
| FloatValue NegativeInfinity JSON parse | 108.08 | — | — | 1736.29 (16.06x) | 267.95 (2.48x) |
| Int64Value JSON stringify | 49.91 | — | — | 692.92 (13.88x) | 292.20 (5.85x) |
| Int64Value JSON parse | 124.58 | — | — | 1243.47 (9.98x) | 465.15 (3.73x) |
| Int64Value Number JSON parse | 127.37 | — | — | 1293.16 (10.15x) | 366.32 (2.88x) |
| Int64Value Exponent JSON parse | 117.71 | — | — | 1236.86 (10.51x) | 419.59 (3.56x) |
| ZeroInt64Value JSON stringify | 41.69 | — | — | 627.15 (15.04x) | 188.65 (4.53x) |
| ZeroInt64Value JSON parse | 105.50 | — | — | 1097.41 (10.40x) | 333.51 (3.16x) |
| NegativeInt64Value JSON stringify | 48.47 | — | — | 690.61 (14.25x) | 278.61 (5.75x) |
| NegativeInt64Value JSON parse | 126.39 | — | — | 1225.22 (9.69x) | 459.88 (3.64x) |
| MinInt64Value JSON stringify | 49.52 | — | — | 699.94 (14.13x) | 284.10 (5.74x) |
| MinInt64Value JSON parse | 134.85 | — | — | 1267.79 (9.40x) | 472.65 (3.51x) |
| MaxInt64Value JSON stringify | 49.41 | — | — | 1096.96 (22.20x) | 287.45 (5.82x) |
| MaxInt64Value JSON parse | 135.86 | — | — | 2137.19 (15.73x) | 489.67 (3.60x) |
| UInt64Value JSON stringify | 50.34 | — | — | 680.23 (13.51x) | 457.97 (9.10x) |
| UInt64Value JSON parse | 124.59 | — | — | 1216.62 (9.76x) | 817.65 (6.56x) |
| UInt64Value Number JSON parse | 126.87 | — | — | 1279.47 (10.08x) | 562.22 (4.43x) |
| UInt64Value Exponent JSON parse | 116.76 | — | — | 1232.95 (10.56x) | 546.08 (4.68x) |
| ZeroUInt64Value JSON stringify | 41.79 | — | — | 611.89 (14.64x) | 203.20 (4.86x) |
| ZeroUInt64Value JSON parse | 106.05 | — | — | 1102.05 (10.39x) | 328.34 (3.10x) |
| MaxUInt64Value JSON stringify | 50.93 | — | — | 680.95 (13.37x) | 341.76 (6.71x) |
| MaxUInt64Value JSON parse | 137.64 | — | — | 1278.85 (9.29x) | 536.83 (3.90x) |
| Int32Value JSON stringify | 46.25 | — | — | 661.44 (14.30x) | 140.63 (3.04x) |
| Int32Value JSON parse | 134.12 | — | — | 1737.25 (12.95x) | 296.54 (2.21x) |
| Int32Value String JSON parse | 137.24 | — | — | 1953.33 (14.23x) | 383.97 (2.80x) |
| Int32Value Exponent JSON parse | 136.45 | — | — | 2274.53 (16.67x) | 364.50 (2.67x) |
| ZeroInt32Value JSON stringify | 45.99 | — | — | 624.58 (13.58x) | 141.94 (3.09x) |
| ZeroInt32Value JSON parse | 129.38 | — | — | 1149.63 (8.89x) | 257.47 (1.99x) |
| NegativeInt32Value JSON stringify | 46.09 | — | — | 660.88 (14.34x) | 132.86 (2.88x) |
| NegativeInt32Value JSON parse | 133.55 | — | — | 1202.32 (9.00x) | 309.10 (2.31x) |
| MinInt32Value JSON stringify | 46.82 | — | — | 999.83 (21.35x) | 134.79 (2.88x) |
| MinInt32Value JSON parse | 138.81 | — | — | 1404.54 (10.12x) | 334.26 (2.41x) |
| MaxInt32Value JSON stringify | 46.81 | — | — | 989.82 (21.15x) | 187.74 (4.01x) |
| MaxInt32Value JSON parse | 139.02 | — | — | 1952.19 (14.04x) | 343.54 (2.47x) |
| UInt32Value JSON stringify | 46.06 | — | — | 1003.05 (21.78x) | 180.17 (3.91x) |
| UInt32Value JSON parse | 132.11 | — | — | 2015.49 (15.26x) | 351.26 (2.66x) |
| UInt32Value String JSON parse | 137.18 | — | — | 1135.69 (8.28x) | 387.20 (2.82x) |
| UInt32Value Exponent JSON parse | 136.55 | — | — | 1230.71 (9.01x) | 365.31 (2.68x) |
| ZeroUInt32Value JSON stringify | 45.92 | — | — | 631.48 (13.75x) | 126.00 (2.74x) |
| ZeroUInt32Value JSON parse | 128.40 | — | — | 1156.15 (9.00x) | 250.10 (1.95x) |
| MaxUInt32Value JSON stringify | 46.42 | — | — | 645.34 (13.90x) | 129.80 (2.80x) |
| MaxUInt32Value JSON parse | 137.96 | — | — | 1215.66 (8.81x) | 334.33 (2.42x) |
| BoolValue JSON stringify | 44.35 | — | — | 616.38 (13.90x) | 143.07 (3.23x) |
| BoolValue JSON parse | 60.11 | — | — | 1544.76 (25.70x) | 204.99 (3.41x) |
| FalseBoolValue JSON stringify | 44.25 | — | — | 604.99 (13.67x) | 122.85 (2.78x) |
| FalseBoolValue JSON parse | 60.13 | — | — | 1193.34 (19.85x) | 247.02 (4.11x) |
| StringValue JSON stringify | 51.39 | — | — | 1109.83 (21.60x) | 183.64 (3.57x) |
| StringValue JSON parse | 120.52 | — | — | 1974.63 (16.38x) | 325.03 (2.70x) |
| StringValue Escape JSON parse | 129.87 | — | — | 2028.16 (15.62x) | 360.81 (2.78x) |
| StringValue Surrogate JSON parse | 128.17 | — | — | 2050.63 (16.00x) | 336.53 (2.63x) |
| EmptyStringValue JSON stringify | 48.56 | — | — | 1037.05 (21.36x) | 168.69 (3.47x) |
| EmptyStringValue JSON parse | 65.91 | — | — | 1939.37 (29.42x) | 211.13 (3.20x) |
| BytesValue JSON stringify | 50.10 | — | — | 1082.73 (21.61x) | 220.74 (4.41x) |
| BytesValue JSON parse | 124.38 | — | — | 2095.89 (16.85x) | 364.68 (2.93x) |
| BytesValue URL JSON parse | 140.14 | — | — | 2061.89 (14.71x) | 327.53 (2.34x) |
| BytesValue StandardBase64 JSON parse | 122.84 | — | — | 2114.68 (17.21x) | 341.51 (2.78x) |
| BytesValue Unpadded JSON parse | 122.55 | — | — | 2058.63 (16.80x) | 333.12 (2.72x) |
| EmptyBytesValue JSON stringify | 41.61 | — | — | 1066.12 (25.62x) | 193.26 (4.64x) |
| EmptyBytesValue JSON parse | 67.96 | — | — | 2028.16 (29.84x) | 302.10 (4.45x) |
| TextFormat format | 179.41 | — | — | 3550.28 (19.79x) | 2499.47 (13.93x) |
| TextFormat parse | 685.14 | — | — | 6494.41 (9.48x) | 6725.96 (9.82x) |
| packed fixed32 encode | 2.06 | 556.13 (269.97x) | 544.16 (264.16x) | 90.86 (44.11x) | 588.39 (285.63x) |
| packed fixed32 decode | 4.66 | 1055.38 (226.48x) | 1924.31 (412.94x) | 99.44 (21.34x) | 1738.97 (373.17x) |
| packed fixed64 encode | 2.06 | 575.90 (279.56x) | 563.25 (273.42x) | 155.28 (75.38x) | 413.15 (200.56x) |
| packed fixed64 decode | 4.65 | 1073.73 (230.91x) | 7962.88 (1712.45x) | 164.09 (35.29x) | 2583.35 (555.56x) |
| packed sfixed32 encode | 2.01 | 568.74 (282.96x) | 540.29 (268.80x) | 90.35 (44.95x) | 396.32 (197.17x) |
| packed sfixed32 decode | 4.53 | 1060.14 (234.03x) | 1970.23 (434.93x) | 96.23 (21.24x) | 1467.69 (323.99x) |
| packed sfixed64 encode | 2.01 | 575.74 (286.44x) | 561.83 (279.52x) | 155.85 (77.54x) | 452.43 (225.09x) |
| packed sfixed64 decode | 4.54 | 1003.41 (221.02x) | 7501.12 (1652.23x) | 161.50 (35.57x) | 2036.84 (448.64x) |
| packed float encode | 2.17 | 817.04 (376.52x) | 539.88 (248.79x) | 90.44 (41.68x) | 360.80 (166.27x) |
| packed float decode | 4.76 | 1050.05 (220.60x) | 2097.34 (440.62x) | 96.21 (20.21x) | 1538.45 (323.20x) |
| packed double encode | 2.02 | 833.65 (412.70x) | 563.84 (279.13x) | 155.23 (76.85x) | 361.28 (178.85x) |
| packed double decode | 4.54 | 990.51 (218.17x) | 2060.90 (453.94x) | 161.26 (35.52x) | 2141.94 (471.79x) |
| packed uint64 encode | 1289.04 | 4610.07 (3.58x) | 4238.17 (3.29x) | 3136.44 (2.43x) | 3586.54 (2.78x) |
| packed uint64 decode | 1782.78 | 2847.30 (1.60x) | 8880.36 (4.98x) | 4986.40 (2.80x) | 7002.26 (3.93x) |
| packed uint32 encode | 1001.96 | 3646.83 (3.64x) | 3285.81 (3.28x) | 2665.04 (2.66x) | 2905.90 (2.90x) |
| packed uint32 decode | 1305.39 | 2448.06 (1.88x) | 3274.31 (2.51x) | 3287.88 (2.52x) | 5630.83 (4.31x) |
| packed int64 encode | 1383.12 | 11080.91 (8.01x) | 6092.35 (4.40x) | 3011.74 (2.18x) | 4180.63 (3.02x) |
| packed int64 decode | 2745.20 | 3382.69 (1.23x) | 10270.30 (3.74x) | 4858.18 (1.77x) | 10194.47 (3.71x) |
| packed sint32 encode | 782.06 | 3130.96 (4.00x) | 2891.40 (3.70x) | 2682.49 (3.43x) | 3441.25 (4.40x) |
| packed sint32 decode | 926.02 | 2565.00 (2.77x) | 3348.45 (3.62x) | 1167.37 (1.26x) | 3780.65 (4.08x) |
| packed sint64 encode | 1429.65 | 4962.98 (3.47x) | 4323.40 (3.02x) | 3431.16 (2.40x) | 6324.82 (4.42x) |
| packed sint64 decode | 2044.46 | 3069.36 (1.50x) | 9676.28 (4.73x) | 4004.99 (1.96x) | 6760.92 (3.31x) |
| packed bool encode | 2.01 | 1313.62 (653.54x) | 525.54 (261.46x) | 17.20 (8.56x) | 2469.70 (1228.71x) |
| packed bool decode | 263.03 | 1535.33 (5.84x) | 2574.71 (9.79x) | 981.83 (3.73x) | 1715.02 (6.52x) |
| packed enum encode | 271.80 | 2725.72 (10.03x) | 1818.38 (6.69x) | 2270.60 (8.35x) | 2606.79 (9.59x) |
| packed enum decode | 156.34 | 1540.55 (9.85x) | 2832.13 (18.12x) | 1215.72 (7.78x) | 2022.50 (12.94x) |
| large map encode | 4003.12 | 16351.22 (4.08x) | 9998.66 (2.50x) | 21960.00 (5.49x) | 198826.66 (49.67x) |
| shuffled large map deterministic binary encode | 28295.85 | — | — | 100501.00 (3.55x) | 387092.09 (13.68x) |
| large map decode | 23624.63 | 91349.17 (3.87x) | 92010.79 (3.89x) | 120660.00 (5.11x) | 268936.62 (11.38x) |
| LargeMap JSON stringify | 20377.31 | — | — | 121601.00 (5.97x) | 618364.30 (30.35x) |
| LargeMap JSON parse | 193586.21 | — | — | 759087.00 (3.92x) | 560323.81 (2.89x) |

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
