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

Latest accepted comparison (`/tmp/pbz-compare-proto-name-stringify-final.log`,
summarized in `/tmp/pbz-summary-proto-name-stringify-final.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Pivoted rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 28.38 | 131.64 (4.64x) | 51.52 (1.82x) | 129.96 (4.58x) | 810.82 (28.57x) |
| binary decode | 87.18 | 277.49 (3.18x) | 229.26 (2.63x) | 229.39 (2.63x) | 918.36 (10.53x) |
| unknown fields count by number | 3.67 | — | — | 162.26 (44.21x) | — |
| deterministic binary encode | 69.68 | — | — | 132.89 (1.91x) | 1145.93 (16.45x) |
| scalarmix encode | 28.67 | 98.01 (3.42x) | 80.48 (2.81x) | 30.32 (1.06x) | 247.42 (8.63x) |
| scalarmix decode | 38.97 | 161.39 (4.14x) | 191.75 (4.92x) | 104.70 (2.69x) | 313.69 (8.05x) |
| textbytes encode | 11.53 | 97.34 (8.44x) | 35.34 (3.07x) | 117.24 (10.17x) | 148.69 (12.90x) |
| textbytes decode | 58.18 | 382.44 (6.57x) | 240.39 (4.13x) | 173.28 (2.98x) | 648.39 (11.14x) |
| largebytes encode | 17.59 | 2743.11 (155.95x) | 2933.06 (166.75x) | 2888.30 (164.20x) | 2920.55 (166.03x) |
| largebytes decode | 89.47 | 5991.92 (66.97x) | 3245.02 (36.27x) | 2801.49 (31.31x) | 34747.47 (388.37x) |
| presencemix encode | 16.77 | 67.50 (4.03x) | 35.83 (2.14x) | 53.21 (3.17x) | 226.84 (13.53x) |
| presencemix decode | 56.39 | 131.26 (2.33x) | 109.24 (1.94x) | 162.76 (2.89x) | 530.81 (9.41x) |
| complex encode | 50.06 | 139.34 (2.78x) | 94.27 (1.88x) | 157.50 (3.15x) | 915.07 (18.28x) |
| complex decode | 169.65 | 439.14 (2.59x) | 345.81 (2.04x) | 391.02 (2.30x) | 1657.00 (9.77x) |
| complex deterministic binary encode | 95.35 | — | — | 212.75 (2.23x) | 1193.66 (12.52x) |
| complex JSON stringify | 277.35 | — | — | 5911.44 (21.31x) | 7671.24 (27.66x) |
| complex JSON parse | 2391.73 | — | — | 14622.10 (6.11x) | 9188.66 (3.84x) |
| complex TextFormat format | 417.15 | — | — | 4573.23 (10.96x) | 6494.89 (15.57x) |
| complex TextFormat parse | 2559.43 | — | — | 8193.84 (3.20x) | 10770.85 (4.21x) |
| packed int32 encode | 638.65 | 3790.33 (5.93x) | 2767.55 (4.33x) | 1338.85 (2.10x) | 3432.37 (5.37x) |
| packed int32 decode | 754.45 | 2307.59 (3.06x) | 3507.60 (4.65x) | 1125.58 (1.49x) | 4361.92 (5.78x) |
| JSON stringify | 206.15 | — | — | 3594.72 (17.44x) | 2805.60 (13.61x) |
| ProtoName JSON stringify | 423.28 | — | — | 5802.90 (13.71x) | 4450.62 (10.51x) |
| JSON parse | 1743.73 | — | — | 8931.21 (5.12x) | 5689.26 (3.26x) |
| MapKeySurrogate JSON parse | 479.61 | — | — | 4245.91 (8.85x) | 1288.76 (2.69x) |
| NullFields JSON parse | 596.87 | — | — | 2421.51 (4.06x) | 801.45 (1.34x) |
| OpenEnum JSON parse | 331.22 | — | — | 4363.96 (13.18x) | 515.31 (1.56x) |
| EnumName JSON parse | 333.62 | — | — | 4443.74 (13.32x) | 807.94 (2.42x) |
| ProtoName JSON parse | 637.09 | — | — | 4728.97 (7.42x) | 1403.40 (2.20x) |
| IntExponent JSON parse | 1858.84 | — | — | 8746.44 (4.71x) | 4877.37 (2.62x) |
| Any WKT JSON stringify | 212.26 | — | — | 2657.71 (12.52x) | 1324.09 (6.24x) |
| Any WKT JSON parse | 600.40 | — | — | 3915.85 (6.52x) | 2075.43 (3.46x) |
| Any Duration Escape WKT JSON parse | 566.12 | — | — | 3761.69 (6.64x) | 2036.23 (3.60x) |
| Any PlusDuration WKT JSON parse | 540.14 | — | — | 3894.11 (7.21x) | 1906.94 (3.53x) |
| Any ShortFractionDuration WKT JSON parse | 519.50 | — | — | 3932.64 (7.57x) | 1803.01 (3.47x) |
| Any MicroDuration WKT JSON stringify | 141.25 | — | — | 2383.55 (16.87x) | 1318.07 (9.33x) |
| Any MicroDuration WKT JSON parse | 524.20 | — | — | 3553.11 (6.78x) | 2058.19 (3.93x) |
| Any NanoDuration WKT JSON stringify | 133.66 | — | — | 3072.95 (22.99x) | 1330.91 (9.96x) |
| Any NanoDuration WKT JSON parse | 531.06 | — | — | 3650.87 (6.87x) | 1909.10 (3.59x) |
| Any NegativeDuration WKT JSON stringify | 133.51 | — | — | 2330.73 (17.46x) | 1388.35 (10.40x) |
| Any NegativeDuration WKT JSON parse | 528.44 | — | — | 3543.25 (6.71x) | 2016.36 (3.82x) |
| Any FractionalNegativeDuration WKT JSON stringify | 127.26 | — | — | 2312.60 (18.17x) | 1376.59 (10.82x) |
| Any FractionalNegativeDuration WKT JSON parse | 526.60 | — | — | 3595.51 (6.83x) | 2030.26 (3.86x) |
| Any MaxDuration WKT JSON stringify | 221.79 | — | — | 2149.60 (9.69x) | 1132.13 (5.10x) |
| Any MaxDuration WKT JSON parse | 895.03 | — | — | 3448.48 (3.85x) | 2043.67 (2.28x) |
| Any MinDuration WKT JSON stringify | 236.94 | — | — | 2163.34 (9.13x) | 1218.78 (5.14x) |
| Any MinDuration WKT JSON parse | 622.21 | — | — | 3741.55 (6.01x) | 2055.55 (3.30x) |
| Any ZeroDuration WKT JSON stringify | 167.70 | — | — | 971.32 (5.79x) | 1150.85 (6.86x) |
| Any ZeroDuration WKT JSON parse | 489.92 | — | — | 2636.03 (5.38x) | 1823.74 (3.72x) |
| Any FieldMask WKT JSON stringify | 237.25 | — | — | 2150.02 (9.06x) | 1723.41 (7.26x) |
| Any FieldMask WKT JSON parse | 734.28 | — | — | 3677.97 (5.01x) | 2815.31 (3.83x) |
| Any FieldMask Escape WKT JSON parse | 756.17 | — | — | 3723.02 (4.92x) | 3168.38 (4.19x) |
| Any EmptyFieldMask WKT JSON stringify | 118.92 | — | — | 932.99 (7.85x) | 807.72 (6.79x) |
| Any EmptyFieldMask WKT JSON parse | 453.45 | — | — | 2627.38 (5.79x) | 1595.48 (3.52x) |
| Any Timestamp WKT JSON stringify | 180.61 | — | — | 2890.43 (16.00x) | 1182.06 (6.54x) |
| Any Timestamp WKT JSON parse | 575.80 | — | — | 3495.95 (6.07x) | 1963.24 (3.41x) |
| Any Timestamp Escape WKT JSON parse | 872.27 | — | — | 3706.41 (4.25x) | 2214.80 (2.54x) |
| Any ShortFraction Timestamp WKT JSON parse | 967.48 | — | — | 3552.98 (3.67x) | 1913.74 (1.98x) |
| Any Micro Timestamp WKT JSON stringify | 223.65 | — | — | 2645.36 (11.83x) | 1289.12 (5.76x) |
| Any Micro Timestamp WKT JSON parse | 804.36 | — | — | 3638.35 (4.52x) | 2160.37 (2.69x) |
| Any Nano Timestamp WKT JSON stringify | 177.05 | — | — | 2400.95 (13.56x) | 1255.60 (7.09x) |
| Any Nano Timestamp WKT JSON parse | 586.09 | — | — | 3507.53 (5.98x) | 2290.82 (3.91x) |
| Any Offset Timestamp WKT JSON parse | 596.97 | — | — | 3802.47 (6.37x) | 2079.11 (3.48x) |
| Any PreEpoch Timestamp WKT JSON stringify | 142.47 | — | — | 2515.96 (17.66x) | 1217.10 (8.54x) |
| Any PreEpoch Timestamp WKT JSON parse | 564.53 | — | — | 3600.56 (6.38x) | 2300.32 (4.07x) |
| Any Max Timestamp WKT JSON stringify | 163.54 | — | — | 2651.84 (16.22x) | 1188.43 (7.27x) |
| Any Max Timestamp WKT JSON parse | 590.09 | — | — | 3741.92 (6.34x) | 2226.47 (3.77x) |
| Any Min Timestamp WKT JSON stringify | 165.60 | — | — | 2308.87 (13.94x) | 1069.22 (6.46x) |
| Any Min Timestamp WKT JSON parse | 563.55 | — | — | 3579.58 (6.35x) | 1946.53 (3.45x) |
| Any Empty WKT JSON stringify | 93.67 | — | — | 1076.59 (11.49x) | 645.33 (6.89x) |
| Any Empty WKT JSON parse | 335.73 | — | — | 2480.77 (7.39x) | 1669.43 (4.97x) |
| Any Struct WKT JSON stringify | 864.86 | — | — | 6974.40 (8.06x) | 8284.03 (9.58x) |
| Any Struct WKT JSON parse | 1879.11 | — | — | 13581.00 (7.23x) | 12860.42 (6.84x) |
| Any Struct Escape WKT JSON parse | 1774.30 | — | — | 13680.10 (7.71x) | 11784.02 (6.64x) |
| Any Struct NumberExponent WKT JSON parse | 1750.66 | — | — | 13767.60 (7.86x) | 11538.18 (6.59x) |
| Any Struct Surrogate WKT JSON parse | 1114.03 | — | — | 7534.83 (6.76x) | 3757.83 (3.37x) |
| Any Struct KeySurrogate WKT JSON parse | 760.24 | — | — | 7288.53 (9.59x) | 4524.07 (5.95x) |
| Any EmptyStruct WKT JSON stringify | 123.00 | — | — | 1019.82 (8.29x) | 1109.52 (9.02x) |
| Any EmptyStruct WKT JSON parse | 447.65 | — | — | 2588.17 (5.78x) | 2079.30 (4.64x) |
| Any Value WKT JSON stringify | 661.08 | — | — | 7045.25 (10.66x) | 8688.22 (13.14x) |
| Any Value WKT JSON parse | 1863.08 | — | — | 13704.20 (7.36x) | 12357.90 (6.63x) |
| Any Value Escape WKT JSON parse | 2333.11 | — | — | 13992.60 (6.00x) | 11488.73 (4.92x) |
| Any Value NumberExponent WKT JSON parse | 1867.92 | — | — | 14185.70 (7.59x) | 11761.93 (6.30x) |
| Any Value Surrogate WKT JSON parse | 821.61 | — | — | 7876.85 (9.59x) | 5018.22 (6.11x) |
| Any Value KeySurrogate WKT JSON parse | 825.81 | — | — | 7650.28 (9.26x) | 4753.60 (5.76x) |
| Any NullValue WKT JSON stringify | 207.28 | — | — | 2774.68 (13.39x) | 1250.72 (6.03x) |
| Any NullValue WKT JSON parse | 765.74 | — | — | 5145.66 (6.72x) | 2102.06 (2.75x) |
| Any StringScalarValue WKT JSON stringify | 240.63 | — | — | 2629.35 (10.93x) | 1111.98 (4.62x) |
| Any StringScalarValue WKT JSON parse | 539.17 | — | — | 4288.57 (7.95x) | 2156.54 (4.00x) |
| Any StringScalarValue Escape WKT JSON parse | 616.92 | — | — | 4376.59 (7.09x) | 2198.74 (3.56x) |
| Any StringScalarValue Surrogate WKT JSON parse | 535.75 | — | — | 4429.21 (8.27x) | 2521.96 (4.71x) |
| Any EmptyStringScalarValue WKT JSON stringify | 138.29 | — | — | 2878.87 (20.82x) | 1110.02 (8.03x) |
| Any EmptyStringScalarValue WKT JSON parse | 488.42 | — | — | 4585.18 (9.39x) | 2000.47 (4.10x) |
| Any NumberValue WKT JSON stringify | 172.96 | — | — | 2963.93 (17.14x) | 1118.26 (6.47x) |
| Any NumberValue WKT JSON parse | 514.71 | — | — | 4684.07 (9.10x) | 1776.64 (3.45x) |
| Any NumberValue Exponent WKT JSON parse | 517.41 | — | — | 4444.72 (8.59x) | 2104.73 (4.07x) |
| Any NegativeNumberValue WKT JSON stringify | 176.64 | — | — | 2881.74 (16.31x) | 1593.94 (9.02x) |
| Any NegativeNumberValue WKT JSON parse | 516.54 | — | — | 4388.96 (8.50x) | 3529.78 (6.83x) |
| Any ZeroNumberValue WKT JSON stringify | 243.20 | — | — | 3409.56 (14.02x) | 1587.97 (6.53x) |
| Any ZeroNumberValue WKT JSON parse | 818.27 | — | — | 4999.06 (6.11x) | 4481.45 (5.48x) |
| Any BoolScalarValue WKT JSON stringify | 203.44 | — | — | 2694.03 (13.24x) | 2217.88 (10.90x) |
| Any BoolScalarValue WKT JSON parse | 687.40 | — | — | 4448.88 (6.47x) | 3452.56 (5.02x) |
| Any FalseBoolScalarValue WKT JSON stringify | 172.15 | — | — | 2653.64 (15.41x) | 1591.12 (9.24x) |
| Any FalseBoolScalarValue WKT JSON parse | 641.54 | — | — | 4512.66 (7.03x) | 3293.34 (5.13x) |
| Any ListKindValue WKT JSON stringify | 511.20 | — | — | 6773.51 (13.25x) | 7603.07 (14.87x) |
| Any ListKindValue WKT JSON parse | 1439.84 | — | — | 12628.40 (8.77x) | 10454.31 (7.26x) |
| Any ListKindValue Escape WKT JSON parse | 1436.75 | — | — | 12242.60 (8.52x) | 10321.11 (7.18x) |
| Any ListKindValue Surrogate WKT JSON parse | 1231.06 | — | — | 5858.53 (4.76x) | 4181.63 (3.40x) |
| Any EmptyStructKindValue WKT JSON stringify | 149.96 | — | — | 3392.65 (22.62x) | 2043.89 (13.63x) |
| Any EmptyStructKindValue WKT JSON parse | 693.78 | — | — | 6631.12 (9.56x) | 2939.81 (4.24x) |
| Any EmptyListKindValue WKT JSON stringify | 221.04 | — | — | 3712.73 (16.80x) | 1560.95 (7.06x) |
| Any EmptyListKindValue WKT JSON parse | 508.27 | — | — | 5378.31 (10.58x) | 2587.19 (5.09x) |
| Any DoubleValue WKT JSON stringify | 189.67 | — | — | 2168.12 (11.43x) | 850.40 (4.48x) |
| Any DoubleValue WKT JSON parse | 529.01 | — | — | 3340.03 (6.31x) | 1630.01 (3.08x) |
| Any DoubleValue String WKT JSON parse | 538.38 | — | — | 3355.82 (6.23x) | 1655.50 (3.07x) |
| Any DoubleValue Exponent WKT JSON parse | 535.55 | — | — | 3147.55 (5.88x) | 1813.91 (3.39x) |
| Any NegativeDoubleValue WKT JSON stringify | 193.20 | — | — | 2181.14 (11.29x) | 967.98 (5.01x) |
| Any NegativeDoubleValue WKT JSON parse | 530.10 | — | — | 3537.57 (6.67x) | 1724.57 (3.25x) |
| Any ZeroDoubleValue WKT JSON stringify | 163.72 | — | — | 967.06 (5.91x) | 767.00 (4.68x) |
| Any ZeroDoubleValue WKT JSON parse | 528.59 | — | — | 2589.91 (4.90x) | 1822.85 (3.45x) |
| Any DoubleValue NaN WKT JSON stringify | 163.78 | — | — | 1955.87 (11.94x) | 716.34 (4.37x) |
| Any DoubleValue NaN WKT JSON parse | 847.89 | — | — | 3044.48 (3.59x) | 1837.29 (2.17x) |
| Any DoubleValue Infinity WKT JSON stringify | 250.66 | — | — | 1848.66 (7.38x) | 733.36 (2.93x) |
| Any DoubleValue Infinity WKT JSON parse | 708.54 | — | — | 3203.31 (4.52x) | 1786.97 (2.52x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 210.15 | — | — | 1935.27 (9.21x) | 769.69 (3.66x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 717.43 | — | — | 3159.53 (4.40x) | 1777.27 (2.48x) |
| Any FloatValue WKT JSON stringify | 199.22 | — | — | 2089.97 (10.49x) | 769.91 (3.86x) |
| Any FloatValue WKT JSON parse | 533.91 | — | — | 3066.42 (5.74x) | 1949.38 (3.65x) |
| Any FloatValue String WKT JSON parse | 591.15 | — | — | 3166.24 (5.36x) | 1712.44 (2.90x) |
| Any FloatValue Exponent WKT JSON parse | 585.98 | — | — | 3262.30 (5.57x) | 1707.75 (2.91x) |
| Any NegativeFloatValue WKT JSON stringify | 211.07 | — | — | 2104.75 (9.97x) | 844.86 (4.00x) |
| Any NegativeFloatValue WKT JSON parse | 547.08 | — | — | 3119.91 (5.70x) | 1707.26 (3.12x) |
| Any ZeroFloatValue WKT JSON stringify | 172.28 | — | — | 934.21 (5.42x) | 757.94 (4.40x) |
| Any ZeroFloatValue WKT JSON parse | 599.05 | — | — | 2698.16 (4.50x) | 1631.53 (2.72x) |
| Any FloatValue NaN WKT JSON stringify | 252.10 | — | — | 1934.74 (7.67x) | 796.19 (3.16x) |
| Any FloatValue NaN WKT JSON parse | 829.05 | — | — | 2978.65 (3.59x) | 1675.15 (2.02x) |
| Any FloatValue Infinity WKT JSON stringify | 164.45 | — | — | 1861.94 (11.32x) | 709.76 (4.32x) |
| Any FloatValue Infinity WKT JSON parse | 597.51 | — | — | 3067.80 (5.13x) | 1840.82 (3.08x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 221.74 | — | — | 2738.28 (12.35x) | 750.51 (3.38x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 615.08 | — | — | 7702.64 (12.52x) | 1795.35 (2.92x) |
| Any Int64Value WKT JSON stringify | 217.17 | — | — | 3161.62 (14.56x) | 874.24 (4.03x) |
| Any Int64Value WKT JSON parse | 574.12 | — | — | 4755.69 (8.28x) | 1947.13 (3.39x) |
| Any Int64Value Number WKT JSON parse | 576.19 | — | — | 3427.52 (5.95x) | 1815.21 (3.15x) |
| Any Int64Value Exponent WKT JSON parse | 560.25 | — | — | 4734.92 (8.45x) | 2035.09 (3.63x) |
| Any ZeroInt64Value WKT JSON stringify | 171.53 | — | — | 1549.08 (9.03x) | 966.09 (5.63x) |
| Any ZeroInt64Value WKT JSON parse | 542.58 | — | — | 3711.03 (6.84x) | 1784.73 (3.29x) |
| Any NegativeInt64Value WKT JSON stringify | 176.37 | — | — | 2003.61 (11.36x) | 922.73 (5.23x) |
| Any NegativeInt64Value WKT JSON parse | 562.47 | — | — | 3445.47 (6.13x) | 2092.24 (3.72x) |
| Any MinInt64Value WKT JSON stringify | 222.97 | — | — | 1996.19 (8.95x) | 903.07 (4.05x) |
| Any MinInt64Value WKT JSON parse | 657.98 | — | — | 3372.82 (5.13x) | 2217.56 (3.37x) |
| Any MaxInt64Value WKT JSON stringify | 269.37 | — | — | 1687.41 (6.26x) | 848.13 (3.15x) |
| Any MaxInt64Value WKT JSON parse | 938.30 | — | — | 3263.83 (3.48x) | 2219.44 (2.37x) |
| Any UInt64Value WKT JSON stringify | 221.27 | — | — | 2247.63 (10.16x) | 1030.12 (4.66x) |
| Any UInt64Value WKT JSON parse | 659.38 | — | — | 6353.54 (9.64x) | 2003.20 (3.04x) |
| Any UInt64Value Number WKT JSON parse | 597.59 | — | — | 8182.50 (13.69x) | 1987.91 (3.33x) |
| Any UInt64Value Exponent WKT JSON parse | 546.26 | — | — | 5704.33 (10.44x) | 1959.49 (3.59x) |
| Any ZeroUInt64Value WKT JSON stringify | 172.59 | — | — | 1837.94 (10.65x) | 909.02 (5.27x) |
| Any ZeroUInt64Value WKT JSON parse | 536.28 | — | — | 2695.89 (5.03x) | 1761.49 (3.28x) |
| Any MaxUInt64Value WKT JSON stringify | 179.43 | — | — | 2968.09 (16.54x) | 961.78 (5.36x) |
| Any MaxUInt64Value WKT JSON parse | 572.86 | — | — | 5496.77 (9.60x) | 2121.08 (3.70x) |
| Any Int32Value WKT JSON stringify | 175.77 | — | — | 3283.54 (18.68x) | 801.25 (4.56x) |
| Any Int32Value WKT JSON parse | 548.62 | — | — | 4914.33 (8.96x) | 1976.37 (3.60x) |
| Any Int32Value String WKT JSON parse | 546.65 | — | — | 4788.58 (8.76x) | 1850.40 (3.38x) |
| Any Int32Value Exponent WKT JSON parse | 904.35 | — | — | 5199.40 (5.75x) | 1657.34 (1.83x) |
| Any ZeroInt32Value WKT JSON stringify | 203.83 | — | — | 1596.94 (7.83x) | 708.91 (3.48x) |
| Any ZeroInt32Value WKT JSON parse | 719.76 | — | — | 2763.43 (3.84x) | 1466.94 (2.04x) |
| Any NegativeInt32Value WKT JSON stringify | 223.39 | — | — | 2569.27 (11.50x) | 757.66 (3.39x) |
| Any NegativeInt32Value WKT JSON parse | 550.93 | — | — | 4271.91 (7.75x) | 1801.14 (3.27x) |
| Any MinInt32Value WKT JSON stringify | 173.18 | — | — | 2704.86 (15.62x) | 817.93 (4.72x) |
| Any MinInt32Value WKT JSON parse | 554.80 | — | — | 4735.99 (8.54x) | 1868.51 (3.37x) |
| Any MaxInt32Value WKT JSON stringify | 179.77 | — | — | 2656.27 (14.78x) | 742.69 (4.13x) |
| Any MaxInt32Value WKT JSON parse | 556.85 | — | — | 4978.86 (8.94x) | 1880.76 (3.38x) |
| Any UInt32Value WKT JSON stringify | 184.97 | — | — | 2525.99 (13.66x) | 738.64 (3.99x) |
| Any UInt32Value WKT JSON parse | 546.68 | — | — | 4704.60 (8.61x) | 1888.22 (3.45x) |
| Any UInt32Value String WKT JSON parse | 552.47 | — | — | 4595.62 (8.32x) | 1625.29 (2.94x) |
| Any UInt32Value Exponent WKT JSON parse | 904.97 | — | — | 4699.00 (5.19x) | 1859.94 (2.06x) |
| Any ZeroUInt32Value WKT JSON stringify | 265.30 | — | — | 1001.26 (3.77x) | 732.27 (2.76x) |
| Any ZeroUInt32Value WKT JSON parse | 712.76 | — | — | 2608.32 (3.66x) | 1790.16 (2.51x) |
| Any MaxUInt32Value WKT JSON stringify | 231.09 | — | — | 1960.72 (8.48x) | 802.12 (3.47x) |
| Any MaxUInt32Value WKT JSON parse | 613.20 | — | — | 3101.43 (5.06x) | 1980.52 (3.23x) |
| Any BoolValue WKT JSON stringify | 174.78 | — | — | 1720.25 (9.84x) | 744.63 (4.26x) |
| Any BoolValue WKT JSON parse | 494.43 | — | — | 3077.69 (6.22x) | 1435.72 (2.90x) |
| Any FalseBoolValue WKT JSON stringify | 172.44 | — | — | 913.41 (5.30x) | 702.32 (4.07x) |
| Any FalseBoolValue WKT JSON parse | 485.54 | — | — | 2547.82 (5.25x) | 1539.88 (3.17x) |
| Any StringValue WKT JSON stringify | 203.80 | — | — | 1939.19 (9.52x) | 881.47 (4.33x) |
| Any StringValue WKT JSON parse | 557.22 | — | — | 3163.25 (5.68x) | 2178.59 (3.91x) |
| Any StringValue Escape WKT JSON parse | 561.67 | — | — | 3162.71 (5.63x) | 1941.60 (3.46x) |
| Any StringValue Surrogate WKT JSON parse | 565.98 | — | — | 3079.74 (5.44x) | 1879.79 (3.32x) |
| Any EmptyStringValue WKT JSON stringify | 196.95 | — | — | 915.71 (4.65x) | 976.54 (4.96x) |
| Any EmptyStringValue WKT JSON parse | 533.74 | — | — | 2590.60 (4.85x) | 1665.00 (3.12x) |
| Any BytesValue WKT JSON stringify | 277.37 | — | — | 1973.34 (7.11x) | 1132.73 (4.08x) |
| Any BytesValue WKT JSON parse | 865.92 | — | — | 3463.74 (4.00x) | 2010.16 (2.32x) |
| Any BytesValue URL WKT JSON parse | 745.27 | — | — | 3066.65 (4.11x) | 1629.20 (2.19x) |
| Any BytesValue StandardBase64 WKT JSON parse | 573.82 | — | — | 3083.56 (5.37x) | 1728.48 (3.01x) |
| Any BytesValue Unpadded WKT JSON parse | 569.62 | — | — | 3075.45 (5.40x) | 1911.37 (3.36x) |
| Any EmptyBytesValue WKT JSON stringify | 190.80 | — | — | 1097.59 (5.75x) | 834.89 (4.38x) |
| Any EmptyBytesValue WKT JSON parse | 533.68 | — | — | 2557.08 (4.79x) | 1534.39 (2.88x) |
| Nested Any WKT JSON stringify | 302.51 | — | — | 3111.82 (10.29x) | 1724.14 (5.70x) |
| Nested Any WKT JSON parse | 883.14 | — | — | 5196.43 (5.88x) | 3616.65 (4.10x) |
| Duration JSON stringify | 57.57 | — | — | 986.08 (17.13x) | 365.99 (6.36x) |
| Duration JSON parse | 19.95 | — | — | 1748.81 (87.66x) | 596.82 (29.92x) |
| Duration Escape JSON parse | 40.15 | — | — | 1542.90 (38.43x) | 459.70 (11.45x) |
| PlusDuration JSON parse | 18.20 | — | — | 1813.08 (99.62x) | 427.48 (23.49x) |
| ShortFractionDuration JSON parse | 14.54 | — | — | 1815.62 (124.87x) | 413.06 (28.41x) |
| MicroDuration JSON stringify | 59.61 | — | — | 987.54 (16.57x) | 392.91 (6.59x) |
| MicroDuration JSON parse | 20.34 | — | — | 1672.00 (82.20x) | 375.44 (18.46x) |
| NanoDuration JSON stringify | 57.14 | — | — | 1056.39 (18.49x) | 465.62 (8.15x) |
| NanoDuration JSON parse | 23.98 | — | — | 1796.98 (74.94x) | 429.95 (17.93x) |
| NegativeDuration JSON stringify | 84.36 | — | — | 1108.67 (13.14x) | 403.70 (4.79x) |
| NegativeDuration JSON parse | 30.43 | — | — | 1753.46 (57.62x) | 437.76 (14.39x) |
| FractionalNegativeDuration JSON stringify | 84.03 | — | — | 1021.13 (12.15x) | 427.17 (5.08x) |
| FractionalNegativeDuration JSON parse | 30.30 | — | — | 1909.32 (63.01x) | 474.79 (15.67x) |
| MaxDuration JSON stringify | 69.37 | — | — | 997.93 (14.39x) | 502.81 (7.25x) |
| MaxDuration JSON parse | 52.67 | — | — | 1805.81 (34.29x) | 589.21 (11.19x) |
| MinDuration JSON stringify | 70.85 | — | — | 957.05 (13.51x) | 575.89 (8.13x) |
| MinDuration JSON parse | 54.84 | — | — | 1578.09 (28.78x) | 609.71 (11.12x) |
| ZeroDuration JSON stringify | 62.90 | — | — | 807.06 (12.83x) | 401.94 (6.39x) |
| ZeroDuration JSON parse | 22.58 | — | — | 1526.83 (67.62x) | 467.61 (20.71x) |
| FieldMask JSON stringify | 124.95 | — | — | 1020.77 (8.17x) | 1038.06 (8.31x) |
| FieldMask JSON parse | 233.25 | — | — | 2038.00 (8.74x) | 1453.19 (6.23x) |
| FieldMask Escape JSON parse | 329.72 | — | — | 2109.09 (6.40x) | 1929.07 (5.85x) |
| EmptyFieldMask JSON stringify | 55.09 | — | — | 629.67 (11.43x) | 397.66 (7.22x) |
| EmptyFieldMask JSON parse | 8.37 | — | — | 1081.41 (129.20x) | 329.34 (39.35x) |
| Timestamp JSON stringify | 164.57 | — | — | 1405.86 (8.54x) | 595.63 (3.62x) |
| Timestamp JSON parse | 80.24 | — | — | 1839.35 (22.92x) | 810.23 (10.10x) |
| Timestamp Escape JSON parse | 92.16 | — | — | 1948.78 (21.15x) | 717.28 (7.78x) |
| ShortFraction Timestamp JSON parse | 44.98 | — | — | 1741.61 (38.72x) | 715.74 (15.91x) |
| Micro Timestamp JSON stringify | 160.34 | — | — | 1313.74 (8.19x) | 465.99 (2.91x) |
| Micro Timestamp JSON parse | 86.23 | — | — | 1783.88 (20.69x) | 583.02 (6.76x) |
| Nano Timestamp JSON stringify | 127.02 | — | — | 1385.66 (10.91x) | 553.79 (4.36x) |
| Nano Timestamp JSON parse | 80.85 | — | — | 1863.22 (23.05x) | 566.81 (7.01x) |
| Offset Timestamp JSON parse | 83.56 | — | — | 1885.44 (22.56x) | 581.48 (6.96x) |
| PreEpoch Timestamp JSON stringify | 66.89 | — | — | 1272.16 (19.02x) | 501.44 (7.50x) |
| PreEpoch Timestamp JSON parse | 43.01 | — | — | 1809.96 (42.08x) | 440.38 (10.24x) |
| Max Timestamp JSON stringify | 125.71 | — | — | 1343.93 (10.69x) | 575.15 (4.58x) |
| Max Timestamp JSON parse | 93.56 | — | — | 1884.80 (20.15x) | 506.98 (5.42x) |
| Min Timestamp JSON stringify | 145.54 | — | — | 1140.63 (7.84x) | 478.58 (3.29x) |
| Min Timestamp JSON parse | 65.42 | — | — | 1595.36 (24.39x) | 415.85 (6.36x) |
| Empty JSON stringify | 21.26 | — | — | 498.84 (23.46x) | 110.55 (5.20x) |
| Empty JSON parse | 68.51 | — | — | 738.54 (10.78x) | 194.32 (2.84x) |
| Struct JSON stringify | 173.93 | — | — | 7927.72 (45.58x) | 3534.11 (20.32x) |
| Struct JSON parse | 851.41 | — | — | 13817.20 (16.23x) | 6334.24 (7.44x) |
| Struct Escape JSON parse | 898.82 | — | — | 13778.50 (15.33x) | 6380.99 (7.10x) |
| Struct NumberExponent JSON parse | 845.67 | — | — | 13057.90 (15.44x) | 6968.26 (8.24x) |
| Struct Surrogate JSON parse | 383.70 | — | — | 5833.17 (15.20x) | 1639.37 (4.27x) |
| Struct KeySurrogate JSON parse | 380.87 | — | — | 5573.77 (14.63x) | 1894.18 (4.97x) |
| EmptyStruct JSON stringify | 41.13 | — | — | 699.51 (17.01x) | 401.66 (9.77x) |
| EmptyStruct JSON parse | 91.95 | — | — | 2411.66 (26.23x) | 371.74 (4.04x) |
| Value JSON stringify | 176.82 | — | — | 7862.97 (44.47x) | 4062.82 (22.98x) |
| Value JSON parse | 961.06 | — | — | 18714.00 (19.47x) | 6605.09 (6.87x) |
| Value Escape JSON parse | 1281.43 | — | — | 15175.20 (11.84x) | 6933.23 (5.41x) |
| Value NumberExponent JSON parse | 888.06 | — | — | 14745.90 (16.60x) | 6339.07 (7.14x) |
| Value Surrogate JSON parse | 399.74 | — | — | 8611.78 (21.54x) | 2050.75 (5.13x) |
| Value KeySurrogate JSON parse | 400.13 | — | — | 8157.42 (20.39x) | 2127.77 (5.32x) |
| NullValue JSON stringify | 41.02 | — | — | 1708.31 (41.65x) | 264.60 (6.45x) |
| NullValue JSON parse | 70.80 | — | — | 3060.37 (43.23x) | 378.81 (5.35x) |
| StringScalarValue JSON stringify | 48.38 | — | — | 1535.61 (31.74x) | 278.87 (5.76x) |
| StringScalarValue JSON parse | 141.22 | — | — | 2406.19 (17.04x) | 599.30 (4.24x) |
| StringScalarValue Escape JSON parse | 150.83 | — | — | 2972.58 (19.71x) | 506.39 (3.36x) |
| StringScalarValue Surrogate JSON parse | 149.69 | — | — | 2818.43 (18.83x) | 549.47 (3.67x) |
| EmptyStringScalarValue JSON stringify | 46.64 | — | — | 1710.74 (36.68x) | 345.54 (7.41x) |
| EmptyStringScalarValue JSON parse | 89.28 | — | — | 2648.63 (29.67x) | 389.08 (4.36x) |
| NumberValue JSON stringify | 73.19 | — | — | 1829.20 (24.99x) | 355.04 (4.85x) |
| NumberValue JSON parse | 140.60 | — | — | 2997.26 (21.32x) | 431.96 (3.07x) |
| NumberValue Exponent JSON parse | 143.05 | — | — | 2915.36 (20.38x) | 439.94 (3.08x) |
| NegativeNumberValue JSON stringify | 74.29 | — | — | 1933.50 (26.03x) | 388.16 (5.22x) |
| NegativeNumberValue JSON parse | 142.14 | — | — | 2711.77 (19.08x) | 414.57 (2.92x) |
| ZeroNumberValue JSON stringify | 51.27 | — | — | 1971.55 (38.45x) | 333.74 (6.51x) |
| ZeroNumberValue JSON parse | 137.83 | — | — | 2474.77 (17.96x) | 386.87 (2.81x) |
| BoolScalarValue JSON stringify | 41.04 | — | — | 1693.76 (41.27x) | 232.71 (5.67x) |
| BoolScalarValue JSON parse | 70.71 | — | — | 2359.28 (33.37x) | 361.59 (5.11x) |
| FalseBoolScalarValue JSON stringify | 40.99 | — | — | 1610.00 (39.28x) | 238.05 (5.81x) |
| FalseBoolScalarValue JSON parse | 71.26 | — | — | 2432.09 (34.13x) | 368.59 (5.17x) |
| ListKindValue JSON stringify | 136.49 | — | — | 7297.63 (53.47x) | 2605.56 (19.09x) |
| ListKindValue JSON parse | 828.68 | — | — | 13239.40 (15.98x) | 5404.78 (6.52x) |
| ListKindValue Escape JSON parse | 929.55 | — | — | 14703.20 (15.82x) | 5548.62 (5.97x) |
| ListKindValue Surrogate JSON parse | 405.10 | — | — | 5979.51 (14.76x) | 1580.52 (3.90x) |
| EmptyStructKindValue JSON stringify | 55.83 | — | — | 2320.77 (41.57x) | 525.35 (9.41x) |
| EmptyStructKindValue JSON parse | 112.69 | — | — | 4477.02 (39.73x) | 713.44 (6.33x) |
| EmptyListKindValue JSON stringify | 41.77 | — | — | 2307.55 (55.24x) | 369.31 (8.84x) |
| EmptyListKindValue JSON parse | 182.07 | — | — | 4807.70 (26.41x) | 720.54 (3.96x) |
| ListValue JSON stringify | 234.34 | — | — | 5699.32 (24.32x) | 2506.02 (10.69x) |
| ListValue JSON parse | 657.44 | — | — | 10424.10 (15.86x) | 4943.25 (7.52x) |
| ListValue Escape JSON parse | 679.45 | — | — | 11472.80 (16.89x) | 5280.98 (7.77x) |
| ListValue Surrogate JSON parse | 305.58 | — | — | 3851.01 (12.60x) | 1317.83 (4.31x) |
| EmptyListValue JSON stringify | 40.38 | — | — | 735.12 (18.21x) | 184.98 (4.58x) |
| EmptyListValue JSON parse | 130.02 | — | — | 2668.11 (20.52x) | 379.74 (2.92x) |
| DoubleValue JSON stringify | 67.96 | — | — | 875.91 (12.89x) | 203.18 (2.99x) |
| DoubleValue JSON parse | 111.31 | — | — | 1500.82 (13.48x) | 297.80 (2.68x) |
| DoubleValue String JSON parse | 111.45 | — | — | 1250.28 (11.22x) | 376.53 (3.38x) |
| DoubleValue Exponent JSON parse | 115.34 | — | — | 1552.19 (13.46x) | 297.55 (2.58x) |
| NegativeDoubleValue JSON stringify | 67.62 | — | — | 1169.02 (17.29x) | 273.05 (4.04x) |
| NegativeDoubleValue JSON parse | 112.80 | — | — | 1671.85 (14.82x) | 288.71 (2.56x) |
| ZeroDoubleValue JSON stringify | 47.37 | — | — | 964.07 (20.35x) | 155.19 (3.28x) |
| ZeroDoubleValue JSON parse | 108.95 | — | — | 1409.64 (12.94x) | 268.74 (2.47x) |
| DoubleValue NaN JSON stringify | 46.88 | — | — | 672.75 (14.35x) | 162.06 (3.46x) |
| DoubleValue NaN JSON parse | 104.73 | — | — | 1157.54 (11.05x) | 267.45 (2.55x) |
| DoubleValue Infinity JSON stringify | 48.38 | — | — | 724.86 (14.98x) | 119.67 (2.47x) |
| DoubleValue Infinity JSON parse | 105.76 | — | — | 1201.93 (11.36x) | 281.58 (2.66x) |
| DoubleValue NegativeInfinity JSON stringify | 48.67 | — | — | 671.09 (13.79x) | 137.67 (2.83x) |
| DoubleValue NegativeInfinity JSON parse | 107.64 | — | — | 1131.71 (10.51x) | 292.02 (2.71x) |
| FloatValue JSON stringify | 71.87 | — | — | 871.91 (12.13x) | 198.92 (2.77x) |
| FloatValue JSON parse | 111.39 | — | — | 1375.52 (12.35x) | 296.07 (2.66x) |
| FloatValue String JSON parse | 138.88 | — | — | 1227.21 (8.84x) | 419.05 (3.02x) |
| FloatValue Exponent JSON parse | 146.94 | — | — | 1531.19 (10.42x) | 303.26 (2.06x) |
| NegativeFloatValue JSON stringify | 126.69 | — | — | 1138.43 (8.99x) | 194.58 (1.54x) |
| NegativeFloatValue JSON parse | 140.81 | — | — | 1495.70 (10.62x) | 274.52 (1.95x) |
| ZeroFloatValue JSON stringify | 70.69 | — | — | 759.10 (10.74x) | 189.24 (2.68x) |
| ZeroFloatValue JSON parse | 132.93 | — | — | 1150.08 (8.65x) | 266.60 (2.01x) |
| FloatValue NaN JSON stringify | 68.62 | — | — | 651.51 (9.49x) | 155.35 (2.26x) |
| FloatValue NaN JSON parse | 128.20 | — | — | 1169.41 (9.12x) | 280.17 (2.19x) |
| FloatValue Infinity JSON stringify | 74.03 | — | — | 651.51 (8.80x) | 131.29 (1.77x) |
| FloatValue Infinity JSON parse | 133.72 | — | — | 1263.12 (9.45x) | 292.63 (2.19x) |
| FloatValue NegativeInfinity JSON stringify | 75.06 | — | — | 647.15 (8.62x) | 122.53 (1.63x) |
| FloatValue NegativeInfinity JSON parse | 138.15 | — | — | 1585.29 (11.48x) | 315.91 (2.29x) |
| Int64Value JSON stringify | 67.07 | — | — | 1564.34 (23.32x) | 269.00 (4.01x) |
| Int64Value JSON parse | 176.39 | — | — | 5766.83 (32.69x) | 519.33 (2.94x) |
| Int64Value Number JSON parse | 132.69 | — | — | 5286.50 (39.84x) | 351.84 (2.65x) |
| Int64Value Exponent JSON parse | 127.57 | — | — | 4922.14 (38.58x) | 390.16 (3.06x) |
| ZeroInt64Value JSON stringify | 56.04 | — | — | 1063.35 (18.97x) | 189.60 (3.38x) |
| ZeroInt64Value JSON parse | 129.48 | — | — | 2099.39 (16.21x) | 334.95 (2.59x) |
| NegativeInt64Value JSON stringify | 52.88 | — | — | 1195.47 (22.61x) | 277.18 (5.24x) |
| NegativeInt64Value JSON parse | 163.05 | — | — | 1226.92 (7.52x) | 516.40 (3.17x) |
| MinInt64Value JSON stringify | 66.12 | — | — | 699.21 (10.57x) | 282.86 (4.28x) |
| MinInt64Value JSON parse | 136.32 | — | — | 1243.69 (9.12x) | 530.21 (3.89x) |
| MaxInt64Value JSON stringify | 68.15 | — | — | 690.79 (10.14x) | 336.56 (4.94x) |
| MaxInt64Value JSON parse | 184.78 | — | — | 1337.12 (7.24x) | 514.29 (2.78x) |
| UInt64Value JSON stringify | 65.82 | — | — | 689.62 (10.48x) | 260.12 (3.95x) |
| UInt64Value JSON parse | 142.06 | — | — | 1213.04 (8.54x) | 515.11 (3.63x) |
| UInt64Value Number JSON parse | 127.65 | — | — | 1293.07 (10.13x) | 370.95 (2.91x) |
| UInt64Value Exponent JSON parse | 116.85 | — | — | 1647.51 (14.10x) | 345.59 (2.96x) |
| ZeroUInt64Value JSON stringify | 41.73 | — | — | 1164.94 (27.92x) | 184.90 (4.43x) |
| ZeroUInt64Value JSON parse | 106.03 | — | — | 2314.28 (21.83x) | 400.40 (3.78x) |
| MaxUInt64Value JSON stringify | 50.08 | — | — | 1214.17 (24.24x) | 304.07 (6.07x) |
| MaxUInt64Value JSON parse | 135.98 | — | — | 2773.39 (20.40x) | 502.15 (3.69x) |
| Int32Value JSON stringify | 46.48 | — | — | 1269.85 (27.32x) | 138.48 (2.98x) |
| Int32Value JSON parse | 133.28 | — | — | 2289.15 (17.18x) | 400.96 (3.01x) |
| Int32Value String JSON parse | 136.45 | — | — | 2053.79 (15.05x) | 406.11 (2.98x) |
| Int32Value Exponent JSON parse | 136.04 | — | — | 3631.31 (26.69x) | 349.68 (2.57x) |
| ZeroInt32Value JSON stringify | 46.23 | — | — | 1160.73 (25.11x) | 129.79 (2.81x) |
| ZeroInt32Value JSON parse | 128.53 | — | — | 2153.43 (16.75x) | 297.04 (2.31x) |
| NegativeInt32Value JSON stringify | 46.19 | — | — | 654.44 (14.17x) | 184.62 (4.00x) |
| NegativeInt32Value JSON parse | 131.69 | — | — | 1509.77 (11.46x) | 313.03 (2.38x) |
| MinInt32Value JSON stringify | 46.97 | — | — | 1090.72 (23.22x) | 207.76 (4.42x) |
| MinInt32Value JSON parse | 138.51 | — | — | 2140.83 (15.46x) | 360.67 (2.60x) |
| MaxInt32Value JSON stringify | 47.06 | — | — | 1108.23 (23.55x) | 159.51 (3.39x) |
| MaxInt32Value JSON parse | 138.74 | — | — | 2189.90 (15.78x) | 345.61 (2.49x) |
| UInt32Value JSON stringify | 46.27 | — | — | 1072.82 (23.19x) | 149.61 (3.23x) |
| UInt32Value JSON parse | 133.59 | — | — | 2215.47 (16.58x) | 355.51 (2.66x) |
| UInt32Value String JSON parse | 136.60 | — | — | 2055.93 (15.05x) | 416.66 (3.05x) |
| UInt32Value Exponent JSON parse | 137.21 | — | — | 2350.42 (17.13x) | 438.28 (3.19x) |
| ZeroUInt32Value JSON stringify | 46.35 | — | — | 1007.37 (21.73x) | 139.25 (3.00x) |
| ZeroUInt32Value JSON parse | 129.35 | — | — | 1544.51 (11.94x) | 283.40 (2.19x) |
| MaxUInt32Value JSON stringify | 47.12 | — | — | 655.57 (13.91x) | 147.00 (3.12x) |
| MaxUInt32Value JSON parse | 138.78 | — | — | 1213.24 (8.74x) | 318.08 (2.29x) |
| BoolValue JSON stringify | 44.71 | — | — | 682.29 (15.26x) | 122.67 (2.74x) |
| BoolValue JSON parse | 59.53 | — | — | 1248.58 (20.97x) | 222.45 (3.74x) |
| FalseBoolValue JSON stringify | 44.71 | — | — | 614.46 (13.74x) | 200.19 (4.48x) |
| FalseBoolValue JSON parse | 60.14 | — | — | 1055.81 (17.56x) | 226.73 (3.77x) |
| StringValue JSON stringify | 52.13 | — | — | 670.87 (12.87x) | 180.63 (3.46x) |
| StringValue JSON parse | 122.01 | — | — | 1297.24 (10.63x) | 309.02 (2.53x) |
| StringValue Escape JSON parse | 131.12 | — | — | 2064.53 (15.75x) | 386.23 (2.95x) |
| StringValue Surrogate JSON parse | 133.98 | — | — | 2045.66 (15.27x) | 421.72 (3.15x) |
| EmptyStringValue JSON stringify | 48.92 | — | — | 653.91 (13.37x) | 166.18 (3.40x) |
| EmptyStringValue JSON parse | 66.91 | — | — | 1154.56 (17.26x) | 239.36 (3.58x) |
| BytesValue JSON stringify | 49.58 | — | — | 671.87 (13.55x) | 229.78 (4.63x) |
| BytesValue JSON parse | 126.11 | — | — | 1176.20 (9.33x) | 313.05 (2.48x) |
| BytesValue URL JSON parse | 180.84 | — | — | 1326.80 (7.34x) | 333.73 (1.85x) |
| BytesValue StandardBase64 JSON parse | 155.20 | — | — | 1533.23 (9.88x) | 342.91 (2.21x) |
| BytesValue Unpadded JSON parse | 155.68 | — | — | 1366.85 (8.78x) | 328.05 (2.11x) |
| EmptyBytesValue JSON stringify | 55.89 | — | — | 650.83 (11.64x) | 192.43 (3.44x) |
| EmptyBytesValue JSON parse | 84.40 | — | — | 1470.15 (17.42x) | 286.52 (3.39x) |
| TextFormat format | 292.51 | — | — | 2903.02 (9.92x) | 2984.24 (10.20x) |
| TextFormat parse | 1196.85 | — | — | 5852.48 (4.89x) | 7561.70 (6.32x) |
| packed fixed32 encode | 2.88 | 552.45 (191.82x) | 545.23 (189.32x) | 44.62 (15.49x) | 613.73 (213.10x) |
| packed fixed32 decode | 4.54 | 1173.14 (258.40x) | 2299.44 (506.48x) | 50.60 (11.14x) | 2326.85 (512.52x) |
| packed fixed64 encode | 2.01 | 575.93 (286.53x) | 561.14 (279.17x) | 75.67 (37.65x) | 393.03 (195.54x) |
| packed fixed64 decode | 4.53 | 1027.57 (226.84x) | 8542.42 (1885.74x) | 90.13 (19.90x) | 3676.04 (811.49x) |
| packed sfixed32 encode | 2.88 | 549.02 (190.63x) | 542.89 (188.50x) | 44.17 (15.34x) | 489.06 (169.81x) |
| packed sfixed32 decode | 9.25 | 1166.65 (126.12x) | 2294.91 (248.10x) | 48.86 (5.28x) | 2226.34 (240.69x) |
| packed sfixed64 encode | 2.76 | 573.70 (207.86x) | 587.26 (212.78x) | 91.24 (33.06x) | 493.76 (178.90x) |
| packed sfixed64 decode | 4.54 | 1239.79 (273.08x) | 7990.86 (1760.10x) | 157.06 (34.59x) | 3075.74 (677.48x) |
| packed float encode | 2.01 | 820.75 (408.33x) | 574.06 (285.60x) | 90.65 (45.10x) | 378.55 (188.33x) |
| packed float decode | 4.53 | 1220.92 (269.52x) | 2302.20 (508.21x) | 45.30 (10.00x) | 2277.81 (502.83x) |
| packed double encode | 2.01 | 830.04 (412.96x) | 569.63 (283.40x) | 75.84 (37.73x) | 439.37 (218.59x) |
| packed double decode | 4.54 | 1005.73 (221.53x) | 2370.78 (522.20x) | 79.48 (17.51x) | 3438.95 (757.48x) |
| packed uint64 encode | 1547.68 | 5567.72 (3.60x) | 5003.87 (3.23x) | 2643.57 (1.71x) | 4308.00 (2.78x) |
| packed uint64 decode | 1790.31 | 3525.25 (1.97x) | 9733.03 (5.44x) | 3386.73 (1.89x) | 11090.31 (6.19x) |
| packed uint32 encode | 959.21 | 4255.57 (4.44x) | 3867.99 (4.03x) | 2194.56 (2.29x) | 3618.47 (3.77x) |
| packed uint32 decode | 1378.78 | 3310.92 (2.40x) | 3812.81 (2.77x) | 2385.04 (1.73x) | 8240.73 (5.98x) |
| packed int64 encode | 1396.49 | 13336.21 (9.55x) | 7202.07 (5.16x) | 3740.78 (2.68x) | 5695.35 (4.08x) |
| packed int64 decode | 2812.04 | 4175.33 (1.48x) | 11314.04 (4.02x) | 5733.16 (2.04x) | 13803.51 (4.91x) |
| packed sint32 encode | 781.13 | 3768.61 (4.82x) | 3212.73 (4.11x) | 1666.59 (2.13x) | 4458.85 (5.71x) |
| packed sint32 decode | 922.19 | 3040.43 (3.30x) | 3751.33 (4.07x) | 1269.57 (1.38x) | 5338.80 (5.79x) |
| packed sint64 encode | 1431.15 | 5857.78 (4.09x) | 5228.95 (3.65x) | 2892.82 (2.02x) | 5017.12 (3.51x) |
| packed sint64 decode | 2038.15 | 3670.07 (1.80x) | 10521.58 (5.16x) | 3455.78 (1.70x) | 11696.10 (5.74x) |
| packed bool encode | 2.06 | 1505.90 (731.02x) | 522.34 (253.56x) | 15.95 (7.74x) | 2921.16 (1418.04x) |
| packed bool decode | 263.64 | 1855.42 (7.04x) | 2937.48 (11.14x) | 901.43 (3.42x) | 2276.51 (8.63x) |
| packed enum encode | 277.31 | 3288.69 (11.86x) | 1994.73 (7.19x) | 1104.55 (3.98x) | 3055.42 (11.02x) |
| packed enum decode | 156.73 | 1939.10 (12.37x) | 3260.12 (20.80x) | 702.91 (4.48x) | 3368.17 (21.49x) |
| large map encode | 5600.80 | 17147.97 (3.06x) | 9719.25 (1.74x) | 25371.80 (4.53x) | 230274.26 (41.11x) |
| shuffled large map deterministic binary encode | 37827.23 | — | — | 98402.70 (2.60x) | 449489.78 (11.88x) |
| large map decode | 37630.89 | 107474.48 (2.86x) | 102082.14 (2.71x) | 113363.00 (3.01x) | 335911.38 (8.93x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON (including generated `map<string, int32>` surrogate-pair key parse, null-field parse, enum-name parse, proto-name stringify, proto-name parse, open-enum numeric parse, and integer numeric-exponent parse), Any/WKT JSON (including embedded zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound `Duration`, non-empty/escaped-input parse/number-exponent parse/surrogate-pair value parse/surrogate-pair key parse and empty `Struct`, object/escaped-object parse/object-number-exponent/object-surrogate-pair value parse/object-surrogate-pair key parse/list/escaped-list/surrogate-list/string-scalar/escaped-string-scalar/surrogate-string-scalar/number-exponent/negative-number `Value` (including default-like scalar and empty object/list kinds),
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
