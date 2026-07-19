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

Latest accepted comparison (`/tmp/pbz-compare-after-fractional-negative-duration-json-isolated.log`,
summarized in `/tmp/pbz-summary-after-fractional-negative-duration-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 27.89 | 125.26 (4.49x) | 62.12 (2.23x) | 135.96 (4.88x) | 954.10 (34.21x) |
| binary decode | 132.94 | 296.77 (2.23x) | 298.55 (2.25x) | 266.39 (2.00x) | 1017.46 (7.65x) |
| unknown count by number | 5.22 | — | — | 212.49 (40.71x) | — |
| scalarmix encode | 26.32 | 113.43 (4.31x) | 69.33 (2.63x) | 45.21 (1.72x) | 237.95 (9.04x) |
| scalarmix decode | 56.08 | 163.09 (2.91x) | 227.91 (4.06x) | 108.42 (1.93x) | 365.98 (6.53x) |
| textbytes encode | 11.78 | 91.44 (7.76x) | 43.34 (3.68x) | 147.47 (12.52x) | 172.81 (14.67x) |
| complex decode | 222.83 | 470.37 (2.11x) | 442.02 (1.98x) | 478.73 (2.15x) | 1625.07 (7.29x) |
| complex JSON parse | 2753.99 | — | — | 16673.20 (6.05x) | 10585.71 (3.84x) |
| Any WKT JSON stringify | 168.48 | — | — | 3091.41 (18.35x) | 1372.15 (8.14x) |
| Any WKT JSON parse | 564.68 | — | — | 4543.03 (8.05x) | 2098.87 (3.72x) |
| Any NegativeDuration WKT JSON stringify | 175.39 | — | — | 3093.01 (17.64x) | 1422.75 (8.11x) |
| Any NegativeDuration WKT JSON parse | 569.77 | — | — | 4653.02 (8.17x) | 2177.53 (3.82x) |
| Any FractionalNegativeDuration WKT JSON stringify | 165.09 | — | — | 3049.04 (18.47x) | 1376.70 (8.34x) |
| Any FractionalNegativeDuration WKT JSON parse | 562.74 | — | — | 4634.41 (8.24x) | 2086.81 (3.71x) |
| Any FieldMask WKT JSON stringify | 273.37 | — | — | 2444.00 (8.94x) | 1753.65 (6.41x) |
| Any FieldMask WKT JSON parse | 781.55 | — | — | 4876.47 (6.24x) | 2935.11 (3.76x) |
| Any Timestamp WKT JSON stringify | 236.94 | — | — | 3014.30 (12.72x) | 1365.09 (5.76x) |
| Any Timestamp WKT JSON parse | 635.51 | — | — | 4610.79 (7.26x) | 2242.86 (3.53x) |
| Any PreEpoch Timestamp WKT JSON stringify | 187.13 | — | — | 2876.71 (15.37x) | 1290.92 (6.90x) |
| Any PreEpoch Timestamp WKT JSON parse | 627.04 | — | — | 4724.99 (7.54x) | 2191.61 (3.50x) |
| Any Max Timestamp WKT JSON stringify | 214.43 | — | — | 3032.54 (14.14x) | 1337.80 (6.24x) |
| Any Max Timestamp WKT JSON parse | 659.88 | — | — | 4770.68 (7.23x) | 2292.18 (3.47x) |
| Any Min Timestamp WKT JSON stringify | 220.43 | — | — | 2897.13 (13.14x) | 1270.54 (5.76x) |
| Any Min Timestamp WKT JSON parse | 624.03 | — | — | 4703.04 (7.54x) | 2198.88 (3.52x) |
| Any Empty WKT JSON stringify | 115.33 | — | — | 1301.06 (11.28x) | 722.79 (6.27x) |
| Any Empty WKT JSON parse | 377.24 | — | — | 3135.66 (8.31x) | 1639.50 (4.35x) |
| Any Struct WKT JSON stringify | 790.90 | — | — | 8982.32 (11.36x) | 8938.89 (11.30x) |
| Any Struct WKT JSON parse | 1975.22 | — | — | 17252.20 (8.73x) | 12552.27 (6.35x) |
| Any Value WKT JSON stringify | 799.41 | — | — | 9128.00 (11.42x) | 9989.09 (12.50x) |
| Any Value WKT JSON parse | 2018.94 | — | — | 16757.30 (8.30x) | 14419.61 (7.14x) |
| Any DoubleValue WKT JSON stringify | 241.58 | — | — | 2804.94 (11.61x) | 949.45 (3.93x) |
| Any DoubleValue WKT JSON parse | 565.17 | — | — | 4382.70 (7.75x) | 2096.93 (3.71x) |
| Any DoubleValue NaN WKT JSON stringify | 184.67 | — | — | 2274.34 (12.32x) | 917.61 (4.97x) |
| Any DoubleValue NaN WKT JSON parse | 563.49 | — | — | 4035.02 (7.16x) | 2027.51 (3.60x) |
| Any DoubleValue Infinity WKT JSON stringify | 189.95 | — | — | 2270.45 (11.95x) | 890.74 (4.69x) |
| Any DoubleValue Infinity WKT JSON parse | 568.39 | — | — | 4087.00 (7.19x) | 2052.83 (3.61x) |
| Any DoubleValue NegativeInfinity WKT JSON stringify | 190.18 | — | — | 2324.49 (12.22x) | 900.37 (4.73x) |
| Any DoubleValue NegativeInfinity WKT JSON parse | 571.98 | — | — | 4151.88 (7.26x) | 2079.88 (3.64x) |
| Any FloatValue WKT JSON stringify | 247.33 | — | — | 2796.74 (11.31x) | 924.64 (3.74x) |
| Any FloatValue WKT JSON parse | 565.52 | — | — | 4335.77 (7.67x) | 1987.46 (3.51x) |
| Any FloatValue NaN WKT JSON stringify | 187.22 | — | — | 2221.56 (11.87x) | 811.13 (4.33x) |
| Any FloatValue NaN WKT JSON parse | 562.54 | — | — | 4021.20 (7.15x) | 1981.86 (3.52x) |
| Any FloatValue Infinity WKT JSON stringify | 192.01 | — | — | 2155.67 (11.23x) | 861.93 (4.49x) |
| Any FloatValue Infinity WKT JSON parse | 567.63 | — | — | 4020.46 (7.08x) | 1937.06 (3.41x) |
| Any FloatValue NegativeInfinity WKT JSON stringify | 193.40 | — | — | 2178.09 (11.26x) | 822.00 (4.25x) |
| Any FloatValue NegativeInfinity WKT JSON parse | 573.62 | — | — | 4061.48 (7.08x) | 1913.41 (3.34x) |
| Any Int64Value WKT JSON stringify | 200.79 | — | — | 2269.95 (11.31x) | 1145.97 (5.71x) |
| Any Int64Value WKT JSON parse | 616.82 | — | — | 4500.83 (7.30x) | 2383.53 (3.86x) |
| Any UInt64Value WKT JSON stringify | 209.85 | — | — | 2257.18 (10.76x) | 1131.30 (5.39x) |
| Any UInt64Value WKT JSON parse | 633.32 | — | — | 4462.43 (7.05x) | 2239.68 (3.54x) |
| Any Int32Value WKT JSON stringify | 207.38 | — | — | 2392.37 (11.54x) | 882.20 (4.25x) |
| Any Int32Value WKT JSON parse | 591.79 | — | — | 4407.60 (7.45x) | 1969.54 (3.33x) |
| Any UInt32Value WKT JSON stringify | 211.93 | — | — | 2284.32 (10.78x) | 886.59 (4.18x) |
| Any UInt32Value WKT JSON parse | 596.59 | — | — | 4178.14 (7.00x) | 1981.07 (3.32x) |
| Any BoolValue WKT JSON stringify | 206.64 | — | — | 2154.09 (10.42x) | 815.91 (3.95x) |
| Any BoolValue WKT JSON parse | 540.44 | — | — | 4007.80 (7.42x) | 1766.09 (3.27x) |
| Any StringValue WKT JSON stringify | 233.56 | — | — | 2205.09 (9.44x) | 1021.99 (4.38x) |
| Any StringValue WKT JSON parse | 605.49 | — | — | 4069.43 (6.72x) | 2399.84 (3.96x) |
| Any BytesValue WKT JSON stringify | 222.00 | — | — | 2291.30 (10.32x) | 1023.24 (4.61x) |
| Any BytesValue WKT JSON parse | 611.38 | — | — | 4223.58 (6.91x) | 2210.11 (3.61x) |
| Nested Any WKT JSON stringify | 352.10 | — | — | 3459.67 (9.83x) | 2081.57 (5.91x) |
| Nested Any WKT JSON parse | 986.41 | — | — | 6032.84 (6.12x) | 4144.35 (4.20x) |
| Duration JSON stringify | 65.06 | — | — | 1535.13 (23.60x) | 467.33 (7.18x) |
| Duration JSON parse | 11.95 | — | — | 2313.41 (193.59x) | 504.31 (42.20x) |
| NegativeDuration JSON stringify | 66.06 | — | — | 1593.11 (24.12x) | 500.40 (7.57x) |
| NegativeDuration JSON parse | 12.30 | — | — | 2372.41 (192.88x) | 520.46 (42.31x) |
| FractionalNegativeDuration JSON stringify | 65.78 | — | — | 1546.61 (23.51x) | 507.95 (7.72x) |
| FractionalNegativeDuration JSON parse | 12.29 | — | — | 2286.47 (186.04x) | 478.56 (38.94x) |
| FieldMask JSON stringify | 94.06 | — | — | 1294.99 (13.77x) | 824.91 (8.77x) |
| FieldMask JSON parse | 175.69 | — | — | 2642.81 (15.04x) | 1210.38 (6.89x) |
| Timestamp JSON stringify | 129.66 | — | — | 1707.95 (13.17x) | 515.66 (3.98x) |
| Timestamp JSON parse | 57.31 | — | — | 2321.01 (40.50x) | 545.89 (9.53x) |
| PreEpoch Timestamp JSON stringify | 86.75 | — | — | 1569.83 (18.10x) | 502.69 (5.79x) |
| PreEpoch Timestamp JSON parse | 54.75 | — | — | 2262.88 (41.33x) | 494.82 (9.04x) |
| Max Timestamp JSON stringify | 104.26 | — | — | 1761.50 (16.90x) | 523.75 (5.02x) |
| Max Timestamp JSON parse | 65.27 | — | — | 2314.66 (35.46x) | 556.93 (8.53x) |
| Min Timestamp JSON stringify | 119.94 | — | — | 1572.10 (13.11x) | 504.31 (4.20x) |
| Min Timestamp JSON parse | 52.71 | — | — | 2265.34 (42.98x) | 518.33 (9.83x) |
| Empty JSON stringify | 22.76 | — | — | 699.74 (30.74x) | 121.86 (5.35x) |
| Empty JSON parse | 74.35 | — | — | 1107.24 (14.89x) | 288.87 (3.89x) |
| Struct JSON stringify | 259.39 | — | — | 8826.07 (34.03x) | 4356.10 (16.79x) |
| Struct JSON parse | 976.00 | — | — | 16700.90 (17.11x) | 6661.63 (6.83x) |
| Value JSON stringify | 262.77 | — | — | 9954.97 (37.88x) | 4466.04 (17.00x) |
| Value JSON parse | 949.43 | — | — | 17617.40 (18.56x) | 7042.97 (7.42x) |
| ListValue JSON stringify | 195.53 | — | — | 7550.92 (38.62x) | 2948.14 (15.08x) |
| ListValue JSON parse | 769.18 | — | — | 13543.70 (17.61x) | 5512.69 (7.17x) |
| DoubleValue JSON stringify | 98.77 | — | — | 1489.98 (15.09x) | 196.38 (1.99x) |
| DoubleValue JSON parse | 114.06 | — | — | 2100.31 (18.41x) | 324.80 (2.85x) |
| DoubleValue NaN JSON stringify | 52.74 | — | — | 964.99 (18.30x) | 171.94 (3.26x) |
| DoubleValue NaN JSON parse | 102.20 | — | — | 1729.00 (16.92x) | 380.23 (3.72x) |
| DoubleValue Infinity JSON stringify | 56.45 | — | — | 980.32 (17.37x) | 158.07 (2.80x) |
| DoubleValue Infinity JSON parse | 104.73 | — | — | 1735.18 (16.57x) | 372.21 (3.55x) |
| DoubleValue NegativeInfinity JSON stringify | 58.04 | — | — | 992.95 (17.11x) | 147.01 (2.53x) |
| DoubleValue NegativeInfinity JSON parse | 107.57 | — | — | 1774.44 (16.50x) | 351.40 (3.27x) |
| FloatValue JSON stringify | 102.70 | — | — | 1430.39 (13.93x) | 210.15 (2.05x) |
| FloatValue JSON parse | 114.09 | — | — | 2145.97 (18.81x) | 340.84 (2.99x) |
| FloatValue NaN JSON stringify | 52.73 | — | — | 989.10 (18.76x) | 149.76 (2.84x) |
| FloatValue NaN JSON parse | 103.09 | — | — | 1687.53 (16.37x) | 328.92 (3.19x) |
| FloatValue Infinity JSON stringify | 56.60 | — | — | 966.39 (17.07x) | 154.85 (2.74x) |
| FloatValue Infinity JSON parse | 105.04 | — | — | 1708.66 (16.27x) | 338.00 (3.22x) |
| FloatValue NegativeInfinity JSON stringify | 57.76 | — | — | 968.42 (16.77x) | 151.15 (2.62x) |
| FloatValue NegativeInfinity JSON parse | 108.58 | — | — | 1683.43 (15.50x) | 335.39 (3.09x) |
| Int64Value JSON stringify | 42.76 | — | — | 1015.07 (23.74x) | 302.89 (7.08x) |
| Int64Value JSON parse | 139.07 | — | — | 1969.96 (14.17x) | 539.22 (3.88x) |
| UInt64Value JSON stringify | 41.95 | — | — | 1027.84 (24.50x) | 309.66 (7.38x) |
| UInt64Value JSON parse | 139.65 | — | — | 2100.54 (15.04x) | 520.73 (3.73x) |
| Int32Value JSON stringify | 45.85 | — | — | 1746.60 (38.09x) | 153.99 (3.36x) |
| Int32Value JSON parse | 133.15 | — | — | 2779.05 (20.87x) | 354.15 (2.66x) |
| UInt32Value JSON stringify | 45.70 | — | — | 983.44 (21.52x) | 153.37 (3.36x) |
| UInt32Value JSON parse | 133.04 | — | — | 1998.61 (15.02x) | 352.08 (2.65x) |
| BoolValue JSON stringify | 43.17 | — | — | 916.62 (21.23x) | 132.03 (3.06x) |
| BoolValue JSON parse | 54.87 | — | — | 1699.87 (30.98x) | 250.14 (4.56x) |
| StringValue JSON stringify | 53.72 | — | — | 1029.73 (19.17x) | 206.72 (3.85x) |
| StringValue JSON parse | 132.09 | — | — | 1819.40 (13.77x) | 357.51 (2.71x) |
| BytesValue JSON stringify | 48.43 | — | — | 981.66 (20.27x) | 218.68 (4.52x) |
| BytesValue JSON parse | 137.94 | — | — | 1966.15 (14.25x) | 389.79 (2.83x) |
| TextFormat parse | 851.43 | — | — | 5461.14 (6.41x) | 8042.48 (9.45x) |
| packed int32 decode | 995.47 | 2983.58 (3.00x) | 5502.81 (5.53x) | 1341.75 (1.35x) | 4386.91 (4.41x) |
| packed bool encode | 2.51 | 2080.40 (828.84x) | 539.80 (215.06x) | 22.78 (9.08x) | 4385.40 (1747.17x) |
| packed bool decode | 271.63 | 2061.18 (7.59x) | 3851.34 (14.18x) | 1108.35 (4.08x) | 2675.75 (9.85x) |
| largebytes decode | 128.20 | 8529.42 (66.53x) | 4555.81 (35.54x) | 4008.57 (31.27x) | 24077.65 (187.81x) |
| large map decode | 38727.26 | 121450.54 (3.14x) | 130037.55 (3.36x) | 117626.00 (3.04x) | 296670.83 (7.66x) |
| shuffled large map deterministic binary encode | 36621.50 | — | — | 117857.00 (3.22x) | 452757.66 (12.36x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded positive/integer-negative/fractional-negative `Duration`, `Struct`, `Value`,
`FieldMask`, min/pre/post/max-bound `Timestamp`, `Empty`, `Int64Value`, `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), `UInt64Value`, `Int32Value`, `UInt32Value`, `BoolValue`, `StringValue`, `BytesValue`, and recursive nested `Any` payloads), direct positive/integer-negative/fractional-negative Duration and min/pre/post/max-bound Timestamp WKT JSON plus other direct WKT JSON, TextFormat, packed scalars, large bytes,
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
