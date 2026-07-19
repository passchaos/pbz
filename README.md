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
python3 bench/summarize_compare.py --fail-on-loss /tmp/pbz-compare.log
```

Latest accepted comparison (`/tmp/pbz-compare-after-any-int32-json-isolated.log`,
summarized in `/tmp/pbz-summary-after-any-int32-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 23.46 | 125.72 (5.36x) | 65.38 (2.79x) | 130.11 (5.55x) | 951.62 (40.56x) |
| binary decode | 131.59 | 296.30 (2.25x) | 313.18 (2.38x) | 267.69 (2.03x) | 981.26 (7.46x) |
| unknown count by number | 5.02 | — | — | 213.21 (42.47x) | — |
| scalarmix encode | 26.84 | 114.51 (4.27x) | 69.43 (2.59x) | 45.75 (1.70x) | 239.23 (8.91x) |
| scalarmix decode | 50.48 | 161.35 (3.20x) | 222.40 (4.41x) | 112.40 (2.23x) | 362.41 (7.18x) |
| textbytes encode | 13.29 | 91.28 (6.87x) | 43.13 (3.25x) | 146.94 (11.06x) | 170.37 (12.82x) |
| complex decode | 222.53 | 474.57 (2.13x) | 433.66 (1.95x) | 489.41 (2.20x) | 1614.02 (7.25x) |
| complex JSON parse | 2724.26 | — | — | 16782.40 (6.16x) | 10391.48 (3.81x) |
| Any WKT JSON stringify | 174.60 | — | — | 3016.31 (17.28x) | 1341.87 (7.69x) |
| Any WKT JSON parse | 566.76 | — | — | 4535.68 (8.00x) | 2172.15 (3.83x) |
| Any FieldMask WKT JSON stringify | 282.82 | — | — | 2396.27 (8.47x) | 1743.44 (6.16x) |
| Any FieldMask WKT JSON parse | 784.91 | — | — | 4845.46 (6.17x) | 3005.92 (3.83x) |
| Any Timestamp WKT JSON stringify | 242.50 | — | — | 2980.93 (12.29x) | 1327.37 (5.47x) |
| Any Timestamp WKT JSON parse | 638.15 | — | — | 4705.29 (7.37x) | 2295.90 (3.60x) |
| Any Empty WKT JSON stringify | 120.51 | — | — | 1305.75 (10.84x) | 655.69 (5.44x) |
| Any Empty WKT JSON parse | 372.60 | — | — | 3138.46 (8.42x) | 1741.98 (4.68x) |
| Any Struct WKT JSON stringify | 803.55 | — | — | 8952.78 (11.14x) | 8875.08 (11.04x) |
| Any Struct WKT JSON parse | 1953.84 | — | — | 16608.70 (8.50x) | 12612.82 (6.46x) |
| Any Value WKT JSON stringify | 828.45 | — | — | 9031.99 (10.90x) | 9312.60 (11.24x) |
| Any Value WKT JSON parse | 2018.84 | — | — | 16714.10 (8.28x) | 13055.07 (6.47x) |
| Any DoubleValue WKT JSON stringify | 251.54 | — | — | 2871.24 (11.41x) | 889.49 (3.54x) |
| Any DoubleValue WKT JSON parse | 570.79 | — | — | 4423.39 (7.75x) | 2050.61 (3.59x) |
| Any FloatValue WKT JSON stringify | 255.34 | — | — | 2796.85 (10.95x) | 861.38 (3.37x) |
| Any FloatValue WKT JSON parse | 569.99 | — | — | 4418.25 (7.75x) | 1996.46 (3.50x) |
| Any Int64Value WKT JSON stringify | 203.48 | — | — | 2251.11 (11.06x) | 1104.25 (5.43x) |
| Any Int64Value WKT JSON parse | 617.84 | — | — | 4295.97 (6.95x) | 2403.07 (3.89x) |
| Any UInt64Value WKT JSON stringify | 214.88 | — | — | 2233.00 (10.39x) | 1130.86 (5.26x) |
| Any UInt64Value WKT JSON parse | 622.64 | — | — | 4294.93 (6.90x) | 2342.64 (3.76x) |
| Any Int32Value WKT JSON stringify | 208.40 | — | — | 2214.22 (10.62x) | 878.98 (4.22x) |
| Any Int32Value WKT JSON parse | 589.49 | — | — | 4089.52 (6.94x) | 2097.33 (3.56x) |
| Any BoolValue WKT JSON stringify | 207.28 | — | — | 2159.49 (10.42x) | 768.15 (3.71x) |
| Any BoolValue WKT JSON parse | 544.43 | — | — | 4021.43 (7.39x) | 1784.38 (3.28x) |
| Any StringValue WKT JSON stringify | 243.79 | — | — | 2199.22 (9.02x) | 891.28 (3.66x) |
| Any StringValue WKT JSON parse | 604.77 | — | — | 4128.02 (6.83x) | 2006.32 (3.32x) |
| Any BytesValue WKT JSON stringify | 221.49 | — | — | 2262.92 (10.22x) | 917.79 (4.14x) |
| Any BytesValue WKT JSON parse | 611.55 | — | — | 4239.12 (6.93x) | 2032.23 (3.32x) |
| Nested Any WKT JSON stringify | 379.52 | — | — | 3409.32 (8.98x) | 1567.53 (4.13x) |
| Nested Any WKT JSON parse | 984.47 | — | — | 6159.32 (6.26x) | 3602.85 (3.66x) |
| Duration JSON stringify | 63.74 | — | — | 1550.56 (24.33x) | 381.76 (5.99x) |
| Duration JSON parse | 11.28 | — | — | 2275.48 (201.73x) | 422.16 (37.43x) |
| FieldMask JSON stringify | 93.07 | — | — | 1302.94 (14.00x) | 727.25 (7.81x) |
| FieldMask JSON parse | 177.79 | — | — | 2649.69 (14.90x) | 1081.12 (6.08x) |
| Timestamp JSON stringify | 127.68 | — | — | 1701.67 (13.33x) | 472.41 (3.70x) |
| Timestamp JSON parse | 57.92 | — | — | 2327.05 (40.18x) | 476.35 (8.22x) |
| Empty JSON stringify | 22.53 | — | — | 676.98 (30.05x) | 106.68 (4.74x) |
| Empty JSON parse | 72.68 | — | — | 1087.59 (14.96x) | 263.39 (3.62x) |
| Struct JSON stringify | 272.45 | — | — | 8905.53 (32.69x) | 4257.60 (15.63x) |
| Struct JSON parse | 932.78 | — | — | 16803.70 (18.01x) | 6334.33 (6.79x) |
| Value JSON stringify | 274.89 | — | — | 9900.16 (36.01x) | 4387.49 (15.96x) |
| Value JSON parse | 943.67 | — | — | 17667.40 (18.72x) | 6689.83 (7.09x) |
| ListValue JSON stringify | 200.41 | — | — | 7588.50 (37.86x) | 2872.44 (14.33x) |
| ListValue JSON parse | 742.78 | — | — | 13423.10 (18.07x) | 5286.86 (7.12x) |
| DoubleValue JSON stringify | 75.57 | — | — | 1483.79 (19.63x) | 232.05 (3.07x) |
| DoubleValue JSON parse | 113.88 | — | — | 2108.99 (18.52x) | 334.65 (2.94x) |
| FloatValue JSON stringify | 99.17 | — | — | 1402.55 (14.14x) | 218.88 (2.21x) |
| FloatValue JSON parse | 112.29 | — | — | 2165.73 (19.29x) | 344.73 (3.07x) |
| Int64Value JSON stringify | 44.47 | — | — | 1010.18 (22.72x) | 297.71 (6.69x) |
| Int64Value JSON parse | 136.92 | — | — | 1989.11 (14.53x) | 510.49 (3.73x) |
| UInt64Value JSON stringify | 44.45 | — | — | 1014.23 (22.82x) | 308.63 (6.94x) |
| UInt64Value JSON parse | 137.37 | — | — | 1933.27 (14.07x) | 512.98 (3.73x) |
| Int32Value JSON stringify | 45.42 | — | — | 976.19 (21.49x) | 143.77 (3.17x) |
| Int32Value JSON parse | 134.80 | — | — | 1932.84 (14.34x) | 350.07 (2.60x) |
| UInt32Value JSON stringify | 45.26 | — | — | 921.16 (20.35x) | 149.47 (3.30x) |
| UInt32Value JSON parse | 134.26 | — | — | 1925.42 (14.34x) | 349.19 (2.60x) |
| BoolValue JSON stringify | 42.11 | — | — | 914.87 (21.73x) | 130.69 (3.10x) |
| BoolValue JSON parse | 62.22 | — | — | 1718.53 (27.62x) | 264.55 (4.25x) |
| StringValue JSON stringify | 53.83 | — | — | 1016.38 (18.88x) | 214.13 (3.98x) |
| StringValue JSON parse | 126.17 | — | — | 1811.26 (14.36x) | 360.19 (2.85x) |
| BytesValue JSON stringify | 47.77 | — | — | 950.39 (19.90x) | 222.40 (4.66x) |
| BytesValue JSON parse | 145.61 | — | — | 1990.90 (13.67x) | 388.96 (2.67x) |
| TextFormat parse | 844.18 | — | — | 5378.32 (6.37x) | 8101.98 (9.60x) |
| packed int32 decode | 1028.79 | 2988.30 (2.90x) | 4241.32 (4.12x) | 1383.98 (1.35x) | 4386.71 (4.26x) |
| packed bool encode | 2.51 | 2079.25 (828.39x) | 540.10 (215.18x) | 22.73 (9.06x) | 4382.52 (1746.02x) |
| packed bool decode | 271.79 | 2058.40 (7.57x) | 4053.27 (14.91x) | 1108.28 (4.08x) | 2666.59 (9.81x) |
| largebytes decode | 124.85 | 8439.90 (67.60x) | 4565.03 (36.56x) | 3948.06 (31.62x) | 23443.67 (187.77x) |
| large map decode | 37703.60 | 128321.42 (3.40x) | 127849.18 (3.39x) | 116208.00 (3.08x) | 293127.73 (7.77x) |
| shuffled large map deterministic binary encode | 35952.68 | — | — | 111125.00 (3.09x) | 455345.64 (12.67x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded `Duration`, `Struct`, `Value`,
`FieldMask`, `Timestamp`, `Empty`, `Int64Value`, `DoubleValue`, `FloatValue`, `UInt64Value`, `BoolValue`, `StringValue`, `BytesValue`, and recursive nested `Any` payloads), direct WKT JSON, TextFormat, packed scalars, large bytes,
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
python3 bench/summarize_compare.py --fail-on-loss /tmp/pbz-compare.log
```
