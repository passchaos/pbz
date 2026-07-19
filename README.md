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
```

Latest accepted comparison (`/tmp/pbz-compare-scalar-value-json-isolated.log`,
summarized in `/tmp/pbz-summary-scalar-value-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 22.81 | 125.05 (5.48x) | 60.51 (2.65x) | 128.45 (5.63x) | 935.37 (41.01x) |
| binary decode | 128.33 | 328.52 (2.56x) | 297.67 (2.32x) | 268.49 (2.09x) | 1011.07 (7.88x) |
| unknown fields count by number | 5.02 | — | — | 214.61 (42.75x) | — |
| scalarmix encode | 26.82 | 114.99 (4.29x) | 69.82 (2.60x) | 45.62 (1.70x) | 239.02 (8.91x) |
| scalarmix decode | 50.51 | 199.23 (3.94x) | 207.37 (4.11x) | 112.69 (2.23x) | 366.28 (7.25x) |
| textbytes encode | 13.30 | 91.96 (6.91x) | 43.24 (3.25x) | 146.84 (11.04x) | 172.26 (12.95x) |
| largebytes decode | 125.45 | 8620.13 (68.71x) | 4555.57 (36.31x) | 4027.25 (32.10x) | 24324.69 (193.90x) |
| complex decode | 231.60 | 494.40 (2.13x) | 429.37 (1.85x) | 478.83 (2.07x) | 1602.16 (6.92x) |
| complex JSON parse | 2729.77 | — | — | 16569.80 (6.07x) | 10506.62 (3.85x) |
| packed int32 decode | 1029.23 | 2999.44 (2.91x) | 4224.74 (4.10x) | 1367.00 (1.33x) | 4351.56 (4.23x) |
| Any WKT JSON stringify | 178.68 | — | — | 3288.57 (18.40x) | 1352.65 (7.57x) |
| Any WKT JSON parse | 574.65 | — | — | 4927.51 (8.57x) | 2142.86 (3.73x) |
| Any NegativeDuration WKT JSON stringify | 187.74 | — | — | 3296.68 (17.56x) | 1413.54 (7.53x) |
| Any NegativeDuration WKT JSON parse | 578.71 | — | — | 5057.55 (8.74x) | 2221.35 (3.84x) |
| Any FractionalNegativeDuration WKT JSON stringify | 176.46 | — | — | 3245.00 (18.39x) | 1393.49 (7.90x) |
| Any FractionalNegativeDuration WKT JSON parse | 571.86 | — | — | 5011.13 (8.76x) | 2147.40 (3.76x) |
| Any MaxDuration WKT JSON stringify | 161.19 | — | — | 2904.06 (18.02x) | 1360.62 (8.44x) |
| Any MaxDuration WKT JSON parse | 600.52 | — | — | 4861.29 (8.10x) | 2144.89 (3.57x) |
| Any MinDuration WKT JSON stringify | 163.91 | — | — | 2937.07 (17.92x) | 1394.89 (8.51x) |
| Any MinDuration WKT JSON parse | 601.39 | — | — | 4972.29 (8.27x) | 2158.80 (3.59x) |
| Any ZeroDuration WKT JSON stringify | 144.52 | — | — | 1411.27 (9.77x) | 1244.24 (8.61x) |
| Any ZeroDuration WKT JSON parse | 526.23 | — | — | 3547.49 (6.74x) | 1959.27 (3.72x) |
| Any FieldMask WKT JSON stringify | 281.98 | — | — | 2647.01 (9.39x) | 1768.62 (6.27x) |
| Any FieldMask WKT JSON parse | 801.86 | — | — | 5193.72 (6.48x) | 2976.21 (3.71x) |
| Any EmptyFieldMask WKT JSON stringify | 150.27 | — | — | 1424.28 (9.48x) | 899.78 (5.99x) |
| Any EmptyFieldMask WKT JSON parse | 497.83 | — | — | 3435.54 (6.90x) | 1676.65 (3.37x) |
| Any Timestamp WKT JSON stringify | 245.22 | — | — | 3219.08 (13.13x) | 1370.86 (5.59x) |
| Any Timestamp WKT JSON parse | 641.48 | — | — | 4985.42 (7.77x) | 2255.14 (3.52x) |
| Any PreEpoch Timestamp WKT JSON stringify | 198.62 | — | — | 3127.81 (15.75x) | 1304.53 (6.57x) |
| Any PreEpoch Timestamp WKT JSON parse | 624.71 | — | — | 5053.38 (8.09x) | 2255.17 (3.61x) |
| Any Max Timestamp WKT JSON stringify | 222.78 | — | — | 3257.58 (14.62x) | 1359.07 (6.10x) |
| Any Max Timestamp WKT JSON parse | 656.92 | — | — | 5123.08 (7.80x) | 2303.35 (3.51x) |
| Any Min Timestamp WKT JSON stringify | 232.16 | — | — | 3089.17 (13.31x) | 1321.12 (5.69x) |
| Any Min Timestamp WKT JSON parse | 623.18 | — | — | 4987.32 (8.00x) | 2249.24 (3.61x) |
| Any Empty WKT JSON stringify | 122.83 | — | — | 1410.22 (11.48x) | 767.79 (6.25x) |
| Any Empty WKT JSON parse | 377.73 | — | — | 3347.80 (8.86x) | 1672.08 (4.43x) |
| Any Struct WKT JSON stringify | 791.88 | — | — | 9678.91 (12.22x) | 8702.58 (10.99x) |
| Any Struct WKT JSON parse | 2011.83 | — | — | 18327.40 (9.11x) | 12592.34 (6.26x) |
| Any Value WKT JSON stringify | 799.23 | — | — | 9705.35 (12.14x) | 8889.50 (11.12x) |
| Any Value WKT JSON parse | 2055.23 | — | — | 17682.60 (8.60x) | 13082.62 (6.37x) |
| Any NullValue WKT JSON stringify | 165.31 | — | — | 3467.24 (20.97x) | 1268.49 (7.67x) |
| Any NullValue WKT JSON parse | 521.58 | — | — | 6091.93 (11.68x) | 2252.23 (4.32x) |
| Any StringScalarValue WKT JSON stringify | 194.46 | — | — | 3191.01 (16.41x) | 1400.71 (7.20x) |
| Any StringScalarValue WKT JSON parse | 573.39 | — | — | 5376.23 (9.38x) | 2330.32 (4.06x) |
| Any NumberValue WKT JSON stringify | 238.57 | — | — | 3868.97 (16.22x) | 1465.95 (6.14x) |
| Any NumberValue WKT JSON parse | 556.49 | — | — | 5685.71 (10.22x) | 2455.18 (4.41x) |
| Any BoolScalarValue WKT JSON stringify | 164.76 | — | — | 3122.22 (18.95x) | 1259.33 (7.64x) |
| Any BoolScalarValue WKT JSON parse | 521.70 | — | — | 5370.43 (10.29x) | 2178.67 (4.18x) |
| Any DoubleValue WKT JSON stringify | 251.97 | — | — | 2859.15 (11.35x) | 1007.88 (4.00x) |
| Any DoubleValue WKT JSON parse | 578.16 | — | — | 4323.91 (7.48x) | 2055.42 (3.56x) |
| Any NegativeDoubleValue WKT JSON stringify | 253.93 | — | — | 2834.69 (11.16x) | 942.96 (3.71x) |
| Any NegativeDoubleValue WKT JSON parse | 578.20 | — | — | 4414.92 (7.64x) | 2035.05 (3.52x) |
| Any ZeroDoubleValue WKT JSON stringify | 203.81 | — | — | 1264.78 (6.21x) | 828.71 (4.07x) |
| Any ZeroDoubleValue WKT JSON parse | 578.72 | — | — | 3145.41 (5.44x) | 1898.24 (3.28x) |
| Any DoubleValue NaN WKT JSON stringify | 199.06 | — | — | 2271.27 (11.41x) | 845.63 (4.25x) |
| Any DoubleValue NaN WKT JSON parse | 575.25 | — | — | 4032.29 (7.01x) | 1945.47 (3.38x) |
| Any DoubleValue Infinity WKT JSON stringify | 203.10 | — | — | 2189.97 (10.78x) | 817.05 (4.02x) |
| Any DoubleValue Infinity WKT JSON parse | 578.34 | — | — | 3977.58 (6.88x) | 1937.38 (3.35x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 206.63 | — | — | 2243.35 (10.86x) | 823.91 (3.99x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 590.18 | — | — | 4070.05 (6.90x) | 1945.03 (3.30x) |
| Any FloatValue WKT JSON stringify | 259.67 | — | — | 2764.66 (10.65x) | 961.74 (3.70x) |
| Any FloatValue WKT JSON parse | 580.09 | — | — | 4313.54 (7.44x) | 1962.94 (3.38x) |
| Any NegativeFloatValue WKT JSON stringify | 259.62 | — | — | 2765.34 (10.65x) | 920.54 (3.55x) |
| Any NegativeFloatValue WKT JSON parse | 581.33 | — | — | 4349.09 (7.48x) | 1926.81 (3.31x) |
| Any ZeroFloatValue WKT JSON stringify | 207.28 | — | — | 1280.48 (6.18x) | 836.19 (4.03x) |
| Any ZeroFloatValue WKT JSON parse | 578.91 | — | — | 3122.03 (5.39x) | 1853.70 (3.20x) |
| Any FloatValue NaN WKT JSON stringify | 201.81 | — | — | 2249.14 (11.14x) | 834.33 (4.13x) |
| Any FloatValue NaN WKT JSON parse | 574.20 | — | — | 4019.88 (7.00x) | 1866.12 (3.25x) |
| Any FloatValue Infinity WKT JSON stringify | 208.23 | — | — | 2195.68 (10.54x) | 823.26 (3.95x) |
| Any FloatValue Infinity WKT JSON parse | 578.27 | — | — | 4010.03 (6.93x) | 1928.70 (3.34x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 209.19 | — | — | 2190.98 (10.47x) | 829.44 (3.97x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 591.56 | — | — | 4054.20 (6.85x) | 1921.08 (3.25x) |
| Any Int64Value WKT JSON stringify | 204.91 | — | — | 2156.95 (10.53x) | 1177.23 (5.75x) |
| Any Int64Value WKT JSON parse | 624.23 | — | — | 4159.81 (6.66x) | 2316.04 (3.71x) |
| Any ZeroInt64Value WKT JSON stringify | 195.31 | — | — | 1295.73 (6.63x) | 1038.11 (5.32x) |
| Any ZeroInt64Value WKT JSON parse | 579.64 | — | — | 3167.55 (5.46x) | 2069.04 (3.57x) |
| Any NegativeInt64Value WKT JSON stringify | 206.41 | — | — | 2178.11 (10.55x) | 1175.40 (5.69x) |
| Any NegativeInt64Value WKT JSON parse | 622.99 | — | — | 4308.02 (6.92x) | 2313.15 (3.71x) |
| Any MinInt64Value WKT JSON stringify | 211.10 | — | — | 2165.66 (10.26x) | 1172.23 (5.55x) |
| Any MinInt64Value WKT JSON parse | 632.90 | — | — | 4301.86 (6.80x) | 2402.24 (3.80x) |
| Any MaxInt64Value WKT JSON stringify | 211.86 | — | — | 2184.05 (10.31x) | 1169.65 (5.52x) |
| Any MaxInt64Value WKT JSON parse | 640.09 | — | — | 4232.77 (6.61x) | 2319.00 (3.62x) |
| Any UInt64Value WKT JSON stringify | 216.42 | — | — | 2201.66 (10.17x) | 1157.33 (5.35x) |
| Any UInt64Value WKT JSON parse | 631.61 | — | — | 4261.62 (6.75x) | 2267.57 (3.59x) |
| Any ZeroUInt64Value WKT JSON stringify | 212.84 | — | — | 1312.04 (6.16x) | 1015.27 (4.77x) |
| Any ZeroUInt64Value WKT JSON parse | 586.25 | — | — | 3214.80 (5.48x) | 2038.72 (3.48x) |
| Any MaxUInt64Value WKT JSON stringify | 220.03 | — | — | 2193.52 (9.97x) | 1154.87 (5.25x) |
| Any MaxUInt64Value WKT JSON parse | 645.68 | — | — | 4292.89 (6.65x) | 2315.83 (3.59x) |
| Any Int32Value WKT JSON stringify | 206.77 | — | — | 2211.84 (10.70x) | 911.84 (4.41x) |
| Any Int32Value WKT JSON parse | 597.09 | — | — | 4121.21 (6.90x) | 2063.90 (3.46x) |
| Any ZeroInt32Value WKT JSON stringify | 208.48 | — | — | 1281.21 (6.15x) | 828.80 (3.98x) |
| Any ZeroInt32Value WKT JSON parse | 590.72 | — | — | 3215.94 (5.44x) | 1955.95 (3.31x) |
| Any NegativeInt32Value WKT JSON stringify | 216.61 | — | — | 2193.22 (10.13x) | 888.01 (4.10x) |
| Any NegativeInt32Value WKT JSON parse | 598.54 | — | — | 4176.90 (6.98x) | 2094.42 (3.50x) |
| Any MinInt32Value WKT JSON stringify | 215.86 | — | — | 2236.99 (10.36x) | 877.20 (4.06x) |
| Any MinInt32Value WKT JSON parse | 608.80 | — | — | 4190.55 (6.88x) | 2105.94 (3.46x) |
| Any MaxInt32Value WKT JSON stringify | 212.45 | — | — | 2242.72 (10.56x) | 865.52 (4.07x) |
| Any MaxInt32Value WKT JSON parse | 609.94 | — | — | 4433.54 (7.27x) | 2052.48 (3.37x) |
| Any UInt32Value WKT JSON stringify | 217.48 | — | — | 2380.89 (10.95x) | 912.07 (4.19x) |
| Any UInt32Value WKT JSON parse | 601.84 | — | — | 4441.34 (7.38x) | 2057.54 (3.42x) |
| Any ZeroUInt32Value WKT JSON stringify | 215.68 | — | — | 1435.37 (6.66x) | 832.36 (3.86x) |
| Any ZeroUInt32Value WKT JSON parse | 595.08 | — | — | 3396.25 (5.71x) | 1919.11 (3.22x) |
| Any MaxUInt32Value WKT JSON stringify | 220.76 | — | — | 2366.63 (10.72x) | 882.40 (4.00x) |
| Any MaxUInt32Value WKT JSON parse | 615.76 | — | — | 4404.07 (7.15x) | 2040.30 (3.31x) |
| Any BoolValue WKT JSON stringify | 212.54 | — | — | 2348.93 (11.05x) | 837.89 (3.94x) |
| Any BoolValue WKT JSON parse | 551.29 | — | — | 4251.06 (7.71x) | 1742.26 (3.16x) |
| Any FalseBoolValue WKT JSON stringify | 212.61 | — | — | 1430.15 (6.73x) | 817.62 (3.85x) |
| Any FalseBoolValue WKT JSON parse | 556.24 | — | — | 3391.44 (6.10x) | 1719.81 (3.09x) |
| Any StringValue WKT JSON stringify | 245.19 | — | — | 2199.46 (8.97x) | 924.98 (3.77x) |
| Any StringValue WKT JSON parse | 611.52 | — | — | 4058.44 (6.64x) | 1934.55 (3.16x) |
| Any EmptyStringValue WKT JSON stringify | 224.05 | — | — | 1318.06 (5.88x) | 870.54 (3.89x) |
| Any EmptyStringValue WKT JSON parse | 575.24 | — | — | 3168.84 (5.51x) | 1714.81 (2.98x) |
| Any BytesValue WKT JSON stringify | 225.15 | — | — | 2259.16 (10.03x) | 981.21 (4.36x) |
| Any BytesValue WKT JSON parse | 619.15 | — | — | 4248.47 (6.86x) | 1977.73 (3.19x) |
| Any EmptyBytesValue WKT JSON stringify | 217.70 | — | — | 1298.98 (5.97x) | 856.93 (3.94x) |
| Any EmptyBytesValue WKT JSON parse | 580.22 | — | — | 3176.10 (5.47x) | 1849.89 (3.19x) |
| Nested Any WKT JSON stringify | 384.36 | — | — | 3366.68 (8.76x) | 1624.28 (4.23x) |
| Nested Any WKT JSON parse | 1005.28 | — | — | 6177.61 (6.15x) | 3602.49 (3.58x) |
| Duration JSON stringify | 64.46 | — | — | 1558.88 (24.18x) | 401.69 (6.23x) |
| Duration JSON parse | 11.29 | — | — | 2334.39 (206.77x) | 423.25 (37.49x) |
| NegativeDuration JSON stringify | 64.63 | — | — | 1784.93 (27.62x) | 466.25 (7.21x) |
| NegativeDuration JSON parse | 11.38 | — | — | 2585.03 (227.16x) | 434.43 (38.17x) |
| FractionalNegativeDuration JSON stringify | 64.66 | — | — | 1567.72 (24.25x) | 462.28 (7.15x) |
| FractionalNegativeDuration JSON parse | 12.29 | — | — | 2335.46 (190.03x) | 416.74 (33.91x) |
| MaxDuration JSON stringify | 54.30 | — | — | 1303.28 (24.00x) | 447.00 (8.23x) |
| MaxDuration JSON parse | 29.19 | — | — | 2236.37 (76.61x) | 439.88 (15.07x) |
| MinDuration JSON stringify | 54.57 | — | — | 1342.53 (24.60x) | 475.11 (8.71x) |
| MinDuration JSON parse | 29.44 | — | — | 2261.52 (76.82x) | 442.83 (15.04x) |
| ZeroDuration JSON stringify | 47.46 | — | — | 1283.42 (27.04x) | 366.17 (7.72x) |
| ZeroDuration JSON parse | 8.79 | — | — | 2181.47 (248.18x) | 369.55 (42.04x) |
| FieldMask JSON stringify | 94.58 | — | — | 1316.10 (13.92x) | 744.72 (7.87x) |
| FieldMask JSON parse | 183.20 | — | — | 2712.33 (14.81x) | 1079.57 (5.89x) |
| EmptyFieldMask JSON stringify | 41.89 | — | — | 946.55 (22.60x) | 233.20 (5.57x) |
| EmptyFieldMask JSON parse | 3.52 | — | — | 1460.76 (414.99x) | 201.08 (57.12x) |
| Timestamp JSON stringify | 129.98 | — | — | 1710.84 (13.16x) | 463.99 (3.57x) |
| Timestamp JSON parse | 56.73 | — | — | 2294.52 (40.45x) | 478.80 (8.44x) |
| PreEpoch Timestamp JSON stringify | 86.45 | — | — | 1583.14 (18.31x) | 462.60 (5.35x) |
| PreEpoch Timestamp JSON parse | 54.82 | — | — | 2290.84 (41.79x) | 459.97 (8.39x) |
| Max Timestamp JSON stringify | 103.82 | — | — | 1763.16 (16.98x) | 468.10 (4.51x) |
| Max Timestamp JSON parse | 64.30 | — | — | 2357.97 (36.67x) | 499.23 (7.76x) |
| Min Timestamp JSON stringify | 118.42 | — | — | 1581.56 (13.36x) | 461.82 (3.90x) |
| Min Timestamp JSON parse | 52.72 | — | — | 2269.24 (43.04x) | 456.03 (8.65x) |
| Empty JSON stringify | 22.55 | — | — | 685.68 (30.41x) | 98.18 (4.35x) |
| Empty JSON parse | 73.03 | — | — | 1097.88 (15.03x) | 253.17 (3.47x) |
| Struct JSON stringify | 274.13 | — | — | 9083.57 (33.14x) | 3877.91 (14.15x) |
| Struct JSON parse | 943.29 | — | — | 17086.20 (18.11x) | 6356.52 (6.74x) |
| Value JSON stringify | 278.71 | — | — | 9710.30 (34.84x) | 4029.69 (14.46x) |
| Value JSON parse | 967.58 | — | — | 17704.90 (18.30x) | 6609.84 (6.83x) |
| NullValue JSON stringify | 42.46 | — | — | 1742.37 (41.04x) | 231.25 (5.45x) |
| NullValue JSON parse | 66.00 | — | — | 3794.18 (57.49x) | 371.56 (5.63x) |
| StringScalarValue JSON stringify | 54.50 | — | — | 1919.48 (35.22x) | 289.19 (5.31x) |
| StringScalarValue JSON parse | 125.25 | — | — | 3134.52 (25.03x) | 512.93 (4.10x) |
| NumberValue JSON stringify | 112.36 | — | — | 2347.69 (20.89x) | 357.24 (3.18x) |
| NumberValue JSON parse | 122.85 | — | — | 3339.66 (27.18x) | 456.65 (3.72x) |
| BoolScalarValue JSON stringify | 42.74 | — | — | 1781.51 (41.68x) | 229.39 (5.37x) |
| BoolScalarValue JSON parse | 62.47 | — | — | 2959.43 (47.37x) | 375.27 (6.01x) |
| ListValue JSON stringify | 198.80 | — | — | 7552.81 (37.99x) | 2689.26 (13.53x) |
| ListValue JSON parse | 745.62 | — | — | 13769.50 (18.47x) | 5225.56 (7.01x) |
| DoubleValue JSON stringify | 97.76 | — | — | 1508.56 (15.43x) | 215.43 (2.20x) |
| DoubleValue JSON parse | 113.15 | — | — | 2125.55 (18.79x) | 335.73 (2.97x) |
| NegativeDoubleValue JSON stringify | 97.44 | — | — | 1493.81 (15.33x) | 220.41 (2.26x) |
| NegativeDoubleValue JSON parse | 113.78 | — | — | 2128.56 (18.71x) | 324.13 (2.85x) |
| ZeroDoubleValue JSON stringify | 52.31 | — | — | 1380.85 (26.40x) | 162.86 (3.11x) |
| ZeroDoubleValue JSON parse | 115.26 | — | — | 1849.11 (16.04x) | 299.59 (2.60x) |
| DoubleValue NaN JSON stringify | 52.61 | — | — | 986.39 (18.75x) | 152.23 (2.89x) |
| DoubleValue NaN JSON parse | 101.34 | — | — | 1700.48 (16.78x) | 332.14 (3.28x) |
| DoubleValue Infinity JSON stringify | 56.33 | — | — | 990.64 (17.59x) | 157.07 (2.79x) |
| DoubleValue Infinity JSON parse | 104.04 | — | — | 1719.97 (16.53x) | 322.56 (3.10x) |
| DoubleValue NegativeInfinity JSON stringify | 57.76 | — | — | 987.77 (17.10x) | 149.20 (2.58x) |
| DoubleValue NegativeInfinity JSON parse | 108.85 | — | — | 1742.57 (16.01x) | 327.41 (3.01x) |
| FloatValue JSON stringify | 101.39 | — | — | 1414.62 (13.95x) | 204.33 (2.02x) |
| FloatValue JSON parse | 113.10 | — | — | 2129.61 (18.83x) | 322.45 (2.85x) |
| NegativeFloatValue JSON stringify | 102.25 | — | — | 1387.93 (13.57x) | 199.92 (1.96x) |
| NegativeFloatValue JSON parse | 114.14 | — | — | 2145.47 (18.80x) | 307.60 (2.69x) |
| ZeroFloatValue JSON stringify | 52.54 | — | — | 1335.54 (25.42x) | 175.42 (3.34x) |
| ZeroFloatValue JSON parse | 116.09 | — | — | 1867.85 (16.09x) | 291.08 (2.51x) |
| FloatValue NaN JSON stringify | 52.71 | — | — | 969.19 (18.39x) | 154.99 (2.94x) |
| FloatValue NaN JSON parse | 102.17 | — | — | 1705.32 (16.69x) | 308.98 (3.02x) |
| FloatValue Infinity JSON stringify | 56.37 | — | — | 958.17 (17.00x) | 156.05 (2.77x) |
| FloatValue Infinity JSON parse | 104.38 | — | — | 1710.06 (16.38x) | 311.53 (2.98x) |
| FloatValue NegativeInfinity JSON stringify | 57.65 | — | — | 958.94 (16.63x) | 171.35 (2.97x) |
| FloatValue NegativeInfinity JSON parse | 109.75 | — | — | 1721.33 (15.68x) | 320.69 (2.92x) |
| Int64Value JSON stringify | 54.10 | — | — | 998.54 (18.46x) | 296.42 (5.48x) |
| Int64Value JSON parse | 147.54 | — | — | 1969.46 (13.35x) | 522.42 (3.54x) |
| ZeroInt64Value JSON stringify | 43.74 | — | — | 918.44 (21.00x) | 200.07 (4.57x) |
| ZeroInt64Value JSON parse | 103.71 | — | — | 1817.76 (17.53x) | 382.44 (3.69x) |
| NegativeInt64Value JSON stringify | 54.43 | — | — | 1005.80 (18.48x) | 307.14 (5.64x) |
| NegativeInt64Value JSON parse | 147.74 | — | — | 1966.78 (13.31x) | 529.20 (3.58x) |
| MinInt64Value JSON stringify | 57.68 | — | — | 1003.96 (17.41x) | 326.29 (5.66x) |
| MinInt64Value JSON parse | 157.20 | — | — | 2015.50 (12.82x) | 549.83 (3.50x) |
| MaxInt64Value JSON stringify | 57.67 | — | — | 1013.45 (17.57x) | 314.16 (5.45x) |
| MaxInt64Value JSON parse | 156.41 | — | — | 1992.73 (12.74x) | 534.40 (3.42x) |
| UInt64Value JSON stringify | 53.58 | — | — | 1008.63 (18.82x) | 309.90 (5.78x) |
| UInt64Value JSON parse | 146.20 | — | — | 1938.75 (13.26x) | 505.99 (3.46x) |
| ZeroUInt64Value JSON stringify | 42.87 | — | — | 928.70 (21.66x) | 206.67 (4.82x) |
| ZeroUInt64Value JSON parse | 102.08 | — | — | 1772.85 (17.37x) | 377.26 (3.70x) |
| MaxUInt64Value JSON stringify | 57.20 | — | — | 997.98 (17.45x) | 335.10 (5.86x) |
| MaxUInt64Value JSON parse | 159.32 | — | — | 2002.04 (12.57x) | 530.00 (3.33x) |
| Int32Value JSON stringify | 48.41 | — | — | 1000.98 (20.68x) | 174.41 (3.60x) |
| Int32Value JSON parse | 128.96 | — | — | 1936.37 (15.02x) | 363.13 (2.82x) |
| ZeroInt32Value JSON stringify | 48.49 | — | — | 993.10 (20.48x) | 152.62 (3.15x) |
| ZeroInt32Value JSON parse | 122.87 | — | — | 1889.04 (15.37x) | 302.08 (2.46x) |
| NegativeInt32Value JSON stringify | 48.61 | — | — | 1010.03 (20.78x) | 168.81 (3.47x) |
| NegativeInt32Value JSON parse | 125.92 | — | — | 1901.08 (15.10x) | 353.00 (2.80x) |
| MinInt32Value JSON stringify | 49.44 | — | — | 989.82 (20.02x) | 175.10 (3.54x) |
| MinInt32Value JSON parse | 137.00 | — | — | 1929.24 (14.08x) | 378.15 (2.76x) |
| MaxInt32Value JSON stringify | 49.14 | — | — | 999.92 (20.35x) | 173.23 (3.53x) |
| MaxInt32Value JSON parse | 139.44 | — | — | 1912.92 (13.72x) | 361.76 (2.59x) |
| UInt32Value JSON stringify | 48.10 | — | — | 1010.74 (21.01x) | 157.28 (3.27x) |
| UInt32Value JSON parse | 129.37 | — | — | 2040.42 (15.77x) | 359.97 (2.78x) |
| ZeroUInt32Value JSON stringify | 48.94 | — | — | 999.55 (20.42x) | 155.30 (3.17x) |
| ZeroUInt32Value JSON parse | 122.81 | — | — | 1981.31 (16.13x) | 301.70 (2.46x) |
| MaxUInt32Value JSON stringify | 49.24 | — | — | 1007.78 (20.47x) | 163.12 (3.31x) |
| MaxUInt32Value JSON parse | 139.48 | — | — | 2065.27 (14.81x) | 374.55 (2.69x) |
| BoolValue JSON stringify | 46.39 | — | — | 988.09 (21.30x) | 156.52 (3.37x) |
| BoolValue JSON parse | 58.95 | — | — | 1824.89 (30.96x) | 258.03 (4.38x) |
| FalseBoolValue JSON stringify | 46.45 | — | — | 980.93 (21.12x) | 148.35 (3.19x) |
| FalseBoolValue JSON parse | 59.24 | — | — | 1844.78 (31.14x) | 253.93 (4.29x) |
| StringValue JSON stringify | 58.36 | — | — | 1101.84 (18.88x) | 205.09 (3.51x) |
| StringValue JSON parse | 130.26 | — | — | 1960.71 (15.05x) | 360.56 (2.77x) |
| EmptyStringValue JSON stringify | 52.62 | — | — | 1030.05 (19.58x) | 204.50 (3.89x) |
| EmptyStringValue JSON parse | 73.71 | — | — | 1915.22 (25.98x) | 270.71 (3.67x) |
| BytesValue JSON stringify | 48.87 | — | — | 925.72 (18.94x) | 237.71 (4.86x) |
| BytesValue JSON parse | 142.72 | — | — | 1967.89 (13.79x) | 373.98 (2.62x) |
| EmptyBytesValue JSON stringify | 43.00 | — | — | 967.20 (22.49x) | 221.76 (5.16x) |
| EmptyBytesValue JSON parse | 83.40 | — | — | 1881.52 (22.56x) | 326.54 (3.92x) |
| TextFormat parse | 830.32 | — | — | 5481.26 (6.60x) | 7987.65 (9.62x) |
| packed bool encode | 2.26 | 2079.81 (920.27x) | 540.48 (239.15x) | 22.75 (10.07x) | 4388.77 (1941.93x) |
| packed bool decode | 271.60 | 2244.27 (8.26x) | 4119.68 (15.17x) | 1108.56 (4.08x) | 2818.96 (10.38x) |
| shuffled large map deterministic binary encode | 35991.12 | — | — | 112224.00 (3.12x) | 456579.63 (12.69x) |
| large map decode | 37693.85 | 123507.17 (3.28x) | 132120.87 (3.51x) | 118654.00 (3.15x) | 296206.58 (7.86x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded zero/positive/integer-negative/fractional-negative/min-max-bound `Duration`, `Struct`, object/scalar `Value`,
`FieldMask` (non-empty and empty), min/pre/post/max-bound `Timestamp`, `Empty`, min/zero/positive/negative/max `Int64Value`, negative/zero/positive finite `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), negative/zero/positive finite `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), zero/normal/max `UInt64Value`, min/zero/positive/negative/max `Int32Value`, zero/normal/max `UInt32Value`, true/false `BoolValue`, non-empty/empty `StringValue`, base64/empty `BytesValue`, and recursive nested `Any` payloads), direct zero/positive/integer-negative/fractional-negative/min-max-bound Duration and min/pre/post/max-bound Timestamp WKT JSON plus other direct WKT JSON, TextFormat, packed scalars, large bytes,
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
