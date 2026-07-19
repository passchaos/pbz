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

Latest accepted comparison (`/tmp/pbz-compare-after-any-bool-json-isolated.log`,
summarized in `/tmp/pbz-summary-after-any-bool-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 24.93 | 124.82 (5.01x) | 67.89 (2.72x) | 131.45 (5.27x) | 945.14 (37.91x) |
| binary decode | 138.20 | 306.43 (2.22x) | 300.93 (2.18x) | 273.20 (1.98x) | 998.17 (7.22x) |
| unknown count by number | 6.02 | — | — | 177.75 (29.53x) | — |
| scalarmix encode | 27.07 | 114.47 (4.23x) | 66.77 (2.47x) | 46.56 (1.72x) | 237.93 (8.79x) |
| scalarmix decode | 50.26 | 162.80 (3.24x) | 208.78 (4.15x) | 113.92 (2.27x) | 358.45 (7.13x) |
| textbytes encode | 13.29 | 92.07 (6.93x) | 43.26 (3.26x) | 148.68 (11.19x) | 170.22 (12.81x) |
| complex decode | 228.17 | 462.28 (2.03x) | 429.57 (1.88x) | 494.62 (2.17x) | 1621.89 (7.11x) |
| complex JSON parse | 2756.87 | — | — | 16653.70 (6.04x) | 10672.00 (3.87x) |
| Any WKT JSON stringify | 170.61 | — | — | 3043.91 (17.84x) | 1318.28 (7.73x) |
| Any WKT JSON parse | 569.54 | — | — | 4629.84 (8.13x) | 2056.47 (3.61x) |
| Any FieldMask WKT JSON stringify | 278.37 | — | — | 2434.76 (8.75x) | 1764.55 (6.34x) |
| Any FieldMask WKT JSON parse | 791.36 | — | — | 4926.57 (6.23x) | 2885.39 (3.65x) |
| Any Timestamp WKT JSON stringify | 236.61 | — | — | 2986.58 (12.62x) | 1336.90 (5.65x) |
| Any Timestamp WKT JSON parse | 639.67 | — | — | 4672.96 (7.31x) | 2226.81 (3.48x) |
| Any Empty WKT JSON stringify | 114.46 | — | — | 1304.84 (11.40x) | 714.69 (6.24x) |
| Any Empty WKT JSON parse | 374.76 | — | — | 3087.21 (8.24x) | 1619.91 (4.32x) |
| Any Struct WKT JSON stringify | 774.62 | — | — | 8925.66 (11.52x) | 8882.85 (11.47x) |
| Any Struct WKT JSON parse | 1961.79 | — | — | 16547.50 (8.43x) | 12617.11 (6.43x) |
| Any Value WKT JSON stringify | 808.59 | — | — | 8959.88 (11.08x) | 9207.76 (11.39x) |
| Any Value WKT JSON parse | 2024.11 | — | — | 16979.40 (8.39x) | 12990.00 (6.42x) |
| Any Int64Value WKT JSON stringify | 199.36 | — | — | 2176.30 (10.92x) | 1123.39 (5.63x) |
| Any Int64Value WKT JSON parse | 621.44 | — | — | 4230.18 (6.81x) | 2305.84 (3.71x) |
| Any UInt64Value WKT JSON stringify | 209.09 | — | — | 2220.16 (10.62x) | 1115.93 (5.34x) |
| Any UInt64Value WKT JSON parse | 628.05 | — | — | 4272.43 (6.80x) | 2194.81 (3.49x) |
| Any BoolValue WKT JSON stringify | 208.36 | — | — | 2138.93 (10.27x) | 762.90 (3.66x) |
| Any BoolValue WKT JSON parse | 547.89 | — | — | 3968.33 (7.24x) | 1722.96 (3.14x) |
| Any StringValue WKT JSON stringify | 233.03 | — | — | 2246.17 (9.64x) | 874.60 (3.75x) |
| Any StringValue WKT JSON parse | 611.11 | — | — | 4000.62 (6.55x) | 1868.99 (3.06x) |
| Any BytesValue WKT JSON stringify | 221.92 | — | — | 2262.55 (10.20x) | 939.04 (4.23x) |
| Any BytesValue WKT JSON parse | 618.45 | — | — | 4188.88 (6.77x) | 1937.41 (3.13x) |
| Nested Any WKT JSON stringify | 353.53 | — | — | 3370.42 (9.53x) | 1590.02 (4.50x) |
| Nested Any WKT JSON parse | 1001.82 | — | — | 5955.56 (5.94x) | 3585.09 (3.58x) |
| Duration JSON stringify | 63.88 | — | — | 1522.55 (23.83x) | 371.36 (5.81x) |
| Duration JSON parse | 11.99 | — | — | 2317.41 (193.28x) | 439.84 (36.68x) |
| FieldMask JSON stringify | 93.51 | — | — | 1302.10 (13.92x) | 721.62 (7.72x) |
| FieldMask JSON parse | 183.21 | — | — | 2637.54 (14.40x) | 1045.01 (5.70x) |
| Timestamp JSON stringify | 126.10 | — | — | 1675.98 (13.29x) | 461.89 (3.66x) |
| Timestamp JSON parse | 57.98 | — | — | 2270.63 (39.16x) | 477.71 (8.24x) |
| Empty JSON stringify | 22.76 | — | — | 704.15 (30.94x) | 103.16 (4.53x) |
| Empty JSON parse | 75.58 | — | — | 1121.99 (14.85x) | 265.00 (3.51x) |
| Struct JSON stringify | 264.04 | — | — | 8765.70 (33.20x) | 4140.40 (15.68x) |
| Struct JSON parse | 967.21 | — | — | 16471.40 (17.03x) | 6313.76 (6.53x) |
| Value JSON stringify | 268.12 | — | — | 9812.31 (36.60x) | 4308.27 (16.07x) |
| Value JSON parse | 968.55 | — | — | 17765.10 (18.34x) | 6637.20 (6.85x) |
| ListValue JSON stringify | 197.23 | — | — | 7565.39 (38.36x) | 2816.04 (14.28x) |
| ListValue JSON parse | 756.18 | — | — | 13431.20 (17.76x) | 5240.61 (6.93x) |
| DoubleValue JSON stringify | 75.78 | — | — | 1483.96 (19.58x) | 199.03 (2.63x) |
| DoubleValue JSON parse | 114.78 | — | — | 2070.65 (18.04x) | 316.46 (2.76x) |
| FloatValue JSON stringify | 99.85 | — | — | 1391.76 (13.94x) | 192.85 (1.93x) |
| FloatValue JSON parse | 113.25 | — | — | 2116.33 (18.69x) | 315.55 (2.79x) |
| Int64Value JSON stringify | 42.32 | — | — | 1003.99 (23.72x) | 293.23 (6.93x) |
| Int64Value JSON parse | 140.77 | — | — | 1959.08 (13.92x) | 510.71 (3.63x) |
| UInt64Value JSON stringify | 42.41 | — | — | 1000.30 (23.59x) | 296.95 (7.00x) |
| UInt64Value JSON parse | 140.88 | — | — | 1951.87 (13.85x) | 509.57 (3.62x) |
| Int32Value JSON stringify | 46.49 | — | — | 955.20 (20.55x) | 155.67 (3.35x) |
| Int32Value JSON parse | 133.91 | — | — | 1867.04 (13.94x) | 349.27 (2.61x) |
| UInt32Value JSON stringify | 46.65 | — | — | 913.04 (19.57x) | 148.89 (3.19x) |
| UInt32Value JSON parse | 134.00 | — | — | 1898.39 (14.17x) | 348.84 (2.60x) |
| BoolValue JSON stringify | 43.19 | — | — | 894.50 (20.71x) | 127.86 (2.96x) |
| BoolValue JSON parse | 54.97 | — | — | 1681.82 (30.60x) | 262.56 (4.78x) |
| StringValue JSON stringify | 54.26 | — | — | 1020.00 (18.80x) | 204.11 (3.76x) |
| StringValue JSON parse | 133.73 | — | — | 1838.21 (13.75x) | 359.51 (2.69x) |
| BytesValue JSON stringify | 48.18 | — | — | 972.33 (20.18x) | 210.99 (4.38x) |
| BytesValue JSON parse | 139.57 | — | — | 1951.33 (13.98x) | 376.89 (2.70x) |
| TextFormat parse | 857.36 | — | — | 5519.40 (6.44x) | 8191.66 (9.55x) |
| packed int32 decode | 1030.72 | 2976.16 (2.89x) | 4237.90 (4.11x) | 1436.78 (1.39x) | 4380.48 (4.25x) |
| packed bool encode | 2.26 | 2081.60 (921.06x) | 543.67 (240.56x) | 22.69 (10.04x) | 4379.48 (1937.82x) |
| packed bool decode | 272.77 | 2059.70 (7.55x) | 3853.14 (14.13x) | 1108.70 (4.06x) | 2694.93 (9.88x) |
| largebytes decode | 142.91 | 8410.91 (58.85x) | 4545.64 (31.81x) | 4016.35 (28.10x) | 23742.03 (166.13x) |
| large map decode | 38822.21 | 129675.47 (3.34x) | 129485.65 (3.34x) | 123155.00 (3.17x) | 294567.25 (7.59x) |
| shuffled large map deterministic binary encode | 37090.89 | — | — | 116821.00 (3.15x) | 450054.22 (12.13x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded `Duration`, `Struct`, `Value`,
`FieldMask`, `Timestamp`, `Empty`, `Int64Value`, `UInt64Value`, `BoolValue`, `StringValue`, `BytesValue`, and recursive nested `Any` payloads), direct WKT JSON, TextFormat, packed scalars, large bytes,
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
