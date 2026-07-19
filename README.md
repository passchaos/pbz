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

Latest accepted comparison (`/tmp/pbz-compare-after-max-duration-json-isolated.log`,
summarized in `/tmp/pbz-summary-after-max-duration-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 22.50 | 125.37 (5.57x) | 67.73 (3.01x) | 125.51 (5.58x) | 945.16 (42.01x) |
| binary decode | 128.76 | 297.93 (2.31x) | 294.47 (2.29x) | 268.97 (2.09x) | 997.94 (7.75x) |
| unknown count by number | 4.84 | — | — | 175.84 (36.33x) | — |
| scalarmix encode | 27.16 | 114.19 (4.20x) | 69.39 (2.55x) | 45.75 (1.68x) | 239.95 (8.83x) |
| scalarmix decode | 50.25 | 164.20 (3.27x) | 220.49 (4.39x) | 112.33 (2.24x) | 362.48 (7.21x) |
| textbytes encode | 13.28 | 93.76 (7.06x) | 43.27 (3.26x) | 146.49 (11.03x) | 171.15 (12.89x) |
| complex decode | 230.61 | 465.07 (2.02x) | 429.96 (1.86x) | 500.83 (2.17x) | 1629.57 (7.07x) |
| complex JSON parse | 2754.58 | — | — | 16734.50 (6.08x) | 10465.55 (3.80x) |
| Any WKT JSON stringify | 179.84 | — | — | 3062.95 (17.03x) | 1348.37 (7.50x) |
| Any WKT JSON parse | 581.50 | — | — | 4624.53 (7.95x) | 2056.35 (3.54x) |
| Any NegativeDuration WKT JSON stringify | 187.08 | — | — | 3069.97 (16.41x) | 1400.13 (7.48x) |
| Any NegativeDuration WKT JSON parse | 586.48 | — | — | 4684.84 (7.99x) | 2148.16 (3.66x) |
| Any FractionalNegativeDuration WKT JSON stringify | 177.06 | — | — | 3008.25 (16.99x) | 1365.46 (7.71x) |
| Any FractionalNegativeDuration WKT JSON parse | 577.93 | — | — | 4616.35 (7.99x) | 2065.90 (3.57x) |
| Any MaxDuration WKT JSON stringify | 162.79 | — | — | 2700.50 (16.59x) | 1320.77 (8.11x) |
| Any MaxDuration WKT JSON parse | 606.70 | — | — | 4488.53 (7.40x) | 2102.04 (3.46x) |
| Any FieldMask WKT JSON stringify | 283.15 | — | — | 2420.65 (8.55x) | 1755.36 (6.20x) |
| Any FieldMask WKT JSON parse | 803.42 | — | — | 4861.49 (6.05x) | 2890.17 (3.60x) |
| Any Timestamp WKT JSON stringify | 245.42 | — | — | 3020.13 (12.31x) | 1315.73 (5.36x) |
| Any Timestamp WKT JSON parse | 647.12 | — | — | 4599.92 (7.11x) | 2192.08 (3.39x) |
| Any PreEpoch Timestamp WKT JSON stringify | 200.05 | — | — | 2888.60 (14.44x) | 1256.88 (6.28x) |
| Any PreEpoch Timestamp WKT JSON parse | 631.82 | — | — | 4646.67 (7.35x) | 2175.69 (3.44x) |
| Any Max Timestamp WKT JSON stringify | 223.17 | — | — | 3010.24 (13.49x) | 1322.13 (5.92x) |
| Any Max Timestamp WKT JSON parse | 663.99 | — | — | 4604.32 (6.93x) | 2241.29 (3.38x) |
| Any Min Timestamp WKT JSON stringify | 231.67 | — | — | 2908.43 (12.55x) | 1276.55 (5.51x) |
| Any Min Timestamp WKT JSON parse | 629.35 | — | — | 4572.39 (7.27x) | 2192.90 (3.48x) |
| Any Empty WKT JSON stringify | 122.59 | — | — | 1296.62 (10.58x) | 665.28 (5.43x) |
| Any Empty WKT JSON parse | 383.46 | — | — | 3100.40 (8.09x) | 1630.60 (4.25x) |
| Any Struct WKT JSON stringify | 786.99 | — | — | 9001.84 (11.44x) | 8886.04 (11.29x) |
| Any Struct WKT JSON parse | 1977.85 | — | — | 16852.20 (8.52x) | 12440.44 (6.29x) |
| Any Value WKT JSON stringify | 808.72 | — | — | 8985.82 (11.11x) | 9228.55 (11.41x) |
| Any Value WKT JSON parse | 2052.45 | — | — | 16654.90 (8.11x) | 12923.72 (6.30x) |
| Any DoubleValue WKT JSON stringify | 254.60 | — | — | 2840.30 (11.16x) | 901.36 (3.54x) |
| Any DoubleValue WKT JSON parse | 584.39 | — | — | 4340.12 (7.43x) | 1927.91 (3.30x) |
| Any DoubleValue NaN WKT JSON stringify | 198.80 | — | — | 2288.15 (11.51x) | 783.47 (3.94x) |
| Any DoubleValue NaN WKT JSON parse | 579.79 | — | — | 4039.64 (6.97x) | 1805.77 (3.11x) |
| Any DoubleValue Infinity WKT JSON stringify | 206.39 | — | — | 2226.49 (10.79x) | 808.29 (3.92x) |
| Any DoubleValue Infinity WKT JSON parse | 584.40 | — | — | 4088.65 (7.00x) | 1854.82 (3.17x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 205.33 | — | — | 2227.68 (10.85x) | 788.66 (3.84x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 587.47 | — | — | 4099.11 (6.98x) | 1859.63 (3.17x) |
| Any FloatValue WKT JSON stringify | 259.60 | — | — | 2781.07 (10.71x) | 938.13 (3.61x) |
| Any FloatValue WKT JSON parse | 584.21 | — | — | 4331.13 (7.41x) | 1888.96 (3.23x) |
| Any FloatValue NaN WKT JSON stringify | 210.69 | — | — | 2251.27 (10.69x) | 805.68 (3.82x) |
| Any FloatValue NaN WKT JSON parse | 582.86 | — | — | 4017.78 (6.89x) | 1833.40 (3.15x) |
| Any FloatValue Infinity WKT JSON stringify | 207.27 | — | — | 2210.04 (10.66x) | 783.91 (3.78x) |
| Any FloatValue Infinity WKT JSON parse | 586.24 | — | — | 4001.12 (6.83x) | 1829.22 (3.12x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 208.58 | — | — | 2189.13 (10.50x) | 779.74 (3.74x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 588.49 | — | — | 4089.29 (6.95x) | 1837.91 (3.12x) |
| Any Int64Value WKT JSON stringify | 205.87 | — | — | 2158.35 (10.48x) | 1155.70 (5.61x) |
| Any Int64Value WKT JSON parse | 630.45 | — | — | 4278.49 (6.79x) | 2331.90 (3.70x) |
| Any UInt64Value WKT JSON stringify | 215.01 | — | — | 2171.62 (10.10x) | 1122.84 (5.22x) |
| Any UInt64Value WKT JSON parse | 637.32 | — | — | 4291.46 (6.73x) | 2223.53 (3.49x) |
| Any Int32Value WKT JSON stringify | 208.38 | — | — | 2228.66 (10.70x) | 890.81 (4.27x) |
| Any Int32Value WKT JSON parse | 601.71 | — | — | 4096.41 (6.81x) | 1957.85 (3.25x) |
| Any UInt32Value WKT JSON stringify | 217.31 | — | — | 2184.36 (10.05x) | 877.07 (4.04x) |
| Any UInt32Value WKT JSON parse | 608.58 | — | — | 4157.01 (6.83x) | 1935.14 (3.18x) |
| Any BoolValue WKT JSON stringify | 212.62 | — | — | 2162.75 (10.17x) | 802.91 (3.78x) |
| Any BoolValue WKT JSON parse | 557.91 | — | — | 4020.90 (7.21x) | 1713.53 (3.07x) |
| Any StringValue WKT JSON stringify | 245.33 | — | — | 2225.42 (9.07x) | 927.98 (3.78x) |
| Any StringValue WKT JSON parse | 621.23 | — | — | 4021.98 (6.47x) | 1919.01 (3.09x) |
| Any BytesValue WKT JSON stringify | 225.24 | — | — | 2233.50 (9.92x) | 953.90 (4.24x) |
| Any BytesValue WKT JSON parse | 628.51 | — | — | 4229.28 (6.73x) | 1958.52 (3.12x) |
| Nested Any WKT JSON stringify | 387.91 | — | — | 3466.07 (8.94x) | 1565.41 (4.04x) |
| Nested Any WKT JSON parse | 1002.92 | — | — | 6097.14 (6.08x) | 3596.69 (3.59x) |
| Duration JSON stringify | 64.37 | — | — | 1528.54 (23.75x) | 363.89 (5.65x) |
| Duration JSON parse | 11.29 | — | — | 2273.95 (201.41x) | 419.10 (37.12x) |
| NegativeDuration JSON stringify | 64.83 | — | — | 1613.94 (24.89x) | 446.04 (6.88x) |
| NegativeDuration JSON parse | 11.78 | — | — | 2399.69 (203.71x) | 435.51 (36.97x) |
| FractionalNegativeDuration JSON stringify | 64.87 | — | — | 1554.00 (23.96x) | 438.32 (6.76x) |
| FractionalNegativeDuration JSON parse | 11.78 | — | — | 2294.30 (194.76x) | 416.94 (35.39x) |
| MaxDuration JSON stringify | 54.95 | — | — | 1273.01 (23.17x) | 424.98 (7.73x) |
| MaxDuration JSON parse | 29.21 | — | — | 2209.52 (75.64x) | 441.63 (15.12x) |
| FieldMask JSON stringify | 93.61 | — | — | 1293.14 (13.81x) | 732.92 (7.83x) |
| FieldMask JSON parse | 179.93 | — | — | 2676.66 (14.88x) | 1068.04 (5.94x) |
| Timestamp JSON stringify | 128.63 | — | — | 1731.82 (13.46x) | 459.54 (3.57x) |
| Timestamp JSON parse | 56.94 | — | — | 2312.01 (40.60x) | 478.38 (8.40x) |
| PreEpoch Timestamp JSON stringify | 86.51 | — | — | 1622.11 (18.75x) | 452.10 (5.23x) |
| PreEpoch Timestamp JSON parse | 54.77 | — | — | 2285.29 (41.73x) | 461.78 (8.43x) |
| Max Timestamp JSON stringify | 104.51 | — | — | 1757.80 (16.82x) | 466.70 (4.47x) |
| Max Timestamp JSON parse | 64.34 | — | — | 2323.31 (36.11x) | 488.25 (7.59x) |
| Min Timestamp JSON stringify | 118.10 | — | — | 1593.29 (13.49x) | 452.13 (3.83x) |
| Min Timestamp JSON parse | 52.75 | — | — | 2270.70 (43.05x) | 457.69 (8.68x) |
| Empty JSON stringify | 22.77 | — | — | 704.77 (30.95x) | 109.10 (4.79x) |
| Empty JSON parse | 74.34 | — | — | 1112.03 (14.96x) | 250.40 (3.37x) |
| Struct JSON stringify | 273.74 | — | — | 8988.51 (32.84x) | 4147.69 (15.15x) |
| Struct JSON parse | 946.13 | — | — | 16993.70 (17.96x) | 6364.55 (6.73x) |
| Value JSON stringify | 275.17 | — | — | 9677.88 (35.17x) | 4354.71 (15.83x) |
| Value JSON parse | 957.91 | — | — | 17605.50 (18.38x) | 6689.78 (6.98x) |
| ListValue JSON stringify | 199.95 | — | — | 7566.81 (37.84x) | 2824.55 (14.13x) |
| ListValue JSON parse | 736.28 | — | — | 13595.30 (18.46x) | 5246.45 (7.13x) |
| DoubleValue JSON stringify | 98.14 | — | — | 1483.74 (15.12x) | 200.46 (2.04x) |
| DoubleValue JSON parse | 113.02 | — | — | 2109.47 (18.66x) | 326.50 (2.89x) |
| DoubleValue NaN JSON stringify | 53.34 | — | — | 1011.45 (18.96x) | 132.60 (2.49x) |
| DoubleValue NaN JSON parse | 101.39 | — | — | 1712.16 (16.89x) | 317.20 (3.13x) |
| DoubleValue Infinity JSON stringify | 56.83 | — | — | 981.75 (17.28x) | 136.59 (2.40x) |
| DoubleValue Infinity JSON parse | 104.61 | — | — | 1742.57 (16.66x) | 329.43 (3.15x) |
| DoubleValue NegativeInfinity JSON stringify | 58.24 | — | — | 983.55 (16.89x) | 146.70 (2.52x) |
| DoubleValue NegativeInfinity JSON parse | 108.31 | — | — | 1754.73 (16.20x) | 315.35 (2.91x) |
| FloatValue JSON stringify | 102.64 | — | — | 1428.81 (13.92x) | 202.05 (1.97x) |
| FloatValue JSON parse | 121.87 | — | — | 2123.62 (17.43x) | 333.29 (2.73x) |
| FloatValue NaN JSON stringify | 52.79 | — | — | 955.55 (18.10x) | 140.05 (2.65x) |
| FloatValue NaN JSON parse | 110.46 | — | — | 1727.81 (15.64x) | 308.72 (2.79x) |
| FloatValue Infinity JSON stringify | 55.93 | — | — | 974.30 (17.42x) | 132.29 (2.37x) |
| FloatValue Infinity JSON parse | 113.55 | — | — | 1737.99 (15.31x) | 310.43 (2.73x) |
| FloatValue NegativeInfinity JSON stringify | 57.73 | — | — | 959.02 (16.61x) | 146.03 (2.53x) |
| FloatValue NegativeInfinity JSON parse | 116.68 | — | — | 1762.64 (15.11x) | 318.80 (2.73x) |
| Int64Value JSON stringify | 41.74 | — | — | 1009.42 (24.18x) | 298.62 (7.15x) |
| Int64Value JSON parse | 138.35 | — | — | 1963.23 (14.19x) | 511.38 (3.70x) |
| UInt64Value JSON stringify | 41.96 | — | — | 1011.35 (24.10x) | 297.13 (7.08x) |
| UInt64Value JSON parse | 140.16 | — | — | 1986.35 (14.17x) | 500.86 (3.57x) |
| Int32Value JSON stringify | 46.18 | — | — | 969.34 (20.99x) | 141.74 (3.07x) |
| Int32Value JSON parse | 130.29 | — | — | 1910.39 (14.66x) | 336.81 (2.59x) |
| UInt32Value JSON stringify | 45.91 | — | — | 925.06 (20.15x) | 150.15 (3.27x) |
| UInt32Value JSON parse | 129.85 | — | — | 1946.61 (14.99x) | 342.25 (2.64x) |
| BoolValue JSON stringify | 42.19 | — | — | 902.18 (21.38x) | 137.51 (3.26x) |
| BoolValue JSON parse | 58.97 | — | — | 1722.24 (29.21x) | 261.91 (4.44x) |
| StringValue JSON stringify | 54.24 | — | — | 1004.90 (18.53x) | 191.04 (3.52x) |
| StringValue JSON parse | 129.80 | — | — | 1821.46 (14.03x) | 353.67 (2.72x) |
| BytesValue JSON stringify | 47.63 | — | — | 966.80 (20.30x) | 231.67 (4.86x) |
| BytesValue JSON parse | 142.66 | — | — | 1962.32 (13.76x) | 371.41 (2.60x) |
| TextFormat parse | 835.28 | — | — | 5405.70 (6.47x) | 8013.10 (9.59x) |
| packed int32 decode | 1029.63 | 2975.88 (2.89x) | 4240.25 (4.12x) | 1342.72 (1.30x) | 4358.12 (4.23x) |
| packed bool encode | 2.26 | 2080.03 (920.37x) | 539.81 (238.85x) | 22.56 (9.98x) | 4382.52 (1939.17x) |
| packed bool decode | 271.91 | 2089.54 (7.68x) | 4044.60 (14.87x) | 1108.31 (4.08x) | 2694.42 (9.91x) |
| largebytes decode | 137.73 | 8594.23 (62.40x) | 4538.22 (32.95x) | 4086.05 (29.67x) | 23927.79 (173.73x) |
| large map decode | 37218.58 | 129077.05 (3.47x) | 128696.97 (3.46x) | 117060.00 (3.15x) | 296461.55 (7.97x) |
| shuffled large map deterministic binary encode | 36062.40 | — | — | 112538.00 (3.12x) | 456818.46 (12.67x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded positive/integer-negative/fractional-negative/max-bound `Duration`, `Struct`, `Value`,
`FieldMask`, min/pre/post/max-bound `Timestamp`, `Empty`, `Int64Value`, `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), `UInt64Value`, `Int32Value`, `UInt32Value`, `BoolValue`, `StringValue`, `BytesValue`, and recursive nested `Any` payloads), direct positive/integer-negative/fractional-negative/max-bound Duration and min/pre/post/max-bound Timestamp WKT JSON plus other direct WKT JSON, TextFormat, packed scalars, large bytes,
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
