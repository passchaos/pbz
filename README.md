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

Latest accepted comparison (`/tmp/pbz-compare-after-any-timestamp-json-isolated.log`,
summarized in `/tmp/pbz-summary-after-any-timestamp-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 24.35 | 102.32 (4.20x) | 50.51 (2.07x) | 105.22 (4.32x) | 881.28 (36.19x) |
| binary decode | 96.63 | 254.46 (2.63x) | 227.49 (2.35x) | 225.09 (2.33x) | 899.59 (9.31x) |
| unknown count by number | 3.57 | — | — | 152.61 (42.75x) | — |
| scalarmix encode | 18.72 | 103.90 (5.55x) | 46.93 (2.51x) | 30.57 (1.63x) | 213.66 (11.41x) |
| scalarmix decode | 43.19 | 134.92 (3.12x) | 173.61 (4.02x) | 87.55 (2.03x) | 305.21 (7.07x) |
| textbytes encode | 9.27 | 76.56 (8.26x) | 33.34 (3.60x) | 115.63 (12.47x) | 151.61 (16.35x) |
| complex decode | 172.51 | 402.98 (2.34x) | 335.14 (1.94x) | 391.05 (2.27x) | 1344.79 (7.80x) |
| complex JSON parse | 2424.37 | — | — | 12022.10 (4.96x) | 7604.34 (3.14x) |
| Any WKT JSON stringify | 126.54 | — | — | 1882.44 (14.88x) | 985.72 (7.79x) |
| Any WKT JSON parse | 524.54 | — | — | 2987.32 (5.70x) | 1524.87 (2.91x) |
| Any FieldMask WKT JSON stringify | 232.71 | — | — | 1751.71 (7.53x) | 1421.14 (6.11x) |
| Any FieldMask WKT JSON parse | 728.68 | — | — | 3178.79 (4.36x) | 2068.84 (2.84x) |
| Any Timestamp WKT JSON stringify | 169.61 | — | — | 2021.43 (11.92x) | 1021.10 (6.02x) |
| Any Timestamp WKT JSON parse | 570.47 | — | — | 3026.39 (5.31x) | 1593.97 (2.79x) |
| Any Struct WKT JSON stringify | 615.87 | — | — | 5841.02 (9.48x) | 6074.64 (9.86x) |
| Any Struct WKT JSON parse | 1752.21 | — | — | 11489.30 (6.56x) | 8699.05 (4.96x) |
| Any Value WKT JSON stringify | 643.56 | — | — | 5932.83 (9.22x) | 6415.46 (9.97x) |
| Any Value WKT JSON parse | 1822.38 | — | — | 11614.00 (6.37x) | 9112.33 (5.00x) |
| Any StringValue WKT JSON stringify | 160.12 | — | — | 1572.48 (9.82x) | 814.76 (5.09x) |
| Any StringValue WKT JSON parse | 561.20 | — | — | 2671.77 (4.76x) | 1445.72 (2.58x) |
| Any BytesValue WKT JSON stringify | 146.40 | — | — | 1587.33 (10.84x) | 853.44 (5.83x) |
| Any BytesValue WKT JSON parse | 570.98 | — | — | 2688.42 (4.71x) | 1476.04 (2.59x) |
| Nested Any WKT JSON stringify | 253.27 | — | — | 2471.48 (9.76x) | 1448.93 (5.72x) |
| Nested Any WKT JSON parse | 870.78 | — | — | 4290.24 (4.93x) | 2861.76 (3.29x) |
| Duration JSON stringify | 57.95 | — | — | 961.52 (16.59x) | 387.18 (6.68x) |
| Duration JSON parse | 7.82 | — | — | 1455.99 (186.19x) | 396.24 (50.67x) |
| FieldMask JSON stringify | 90.13 | — | — | 889.50 (9.87x) | 648.02 (7.19x) |
| FieldMask JSON parse | 146.82 | — | — | 1670.96 (11.38x) | 875.12 (5.96x) |
| Timestamp JSON stringify | 94.39 | — | — | 1152.59 (12.21x) | 418.66 (4.44x) |
| Timestamp JSON parse | 42.62 | — | — | 1493.52 (35.04x) | 448.30 (10.52x) |
| Empty JSON stringify | 21.07 | — | — | 503.64 (23.90x) | 79.98 (3.80x) |
| Empty JSON parse | 68.30 | — | — | 725.58 (10.62x) | 205.31 (3.01x) |
| Struct JSON stringify | 176.39 | — | — | 5796.26 (32.86x) | 3043.65 (17.26x) |
| Struct JSON parse | 855.54 | — | — | 10914.20 (12.76x) | 4666.99 (5.46x) |
| Value JSON stringify | 176.03 | — | — | 6627.64 (37.65x) | 3245.75 (18.44x) |
| Value JSON parse | 886.65 | — | — | 12115.00 (13.66x) | 4994.22 (5.63x) |
| ListValue JSON stringify | 132.85 | — | — | 4755.98 (35.80x) | 2143.24 (16.13x) |
| ListValue JSON parse | 679.52 | — | — | 8518.84 (12.54x) | 3807.21 (5.60x) |
| DoubleValue JSON stringify | 59.37 | — | — | 846.09 (14.25x) | 199.24 (3.36x) |
| DoubleValue JSON parse | 111.74 | — | — | 1226.73 (10.98x) | 293.58 (2.63x) |
| FloatValue JSON stringify | 70.28 | — | — | 796.67 (11.34x) | 182.47 (2.60x) |
| FloatValue JSON parse | 111.79 | — | — | 1214.89 (10.87x) | 296.37 (2.65x) |
| Int64Value JSON stringify | 40.59 | — | — | 676.55 (16.67x) | 278.10 (6.85x) |
| Int64Value JSON parse | 137.82 | — | — | 1223.07 (8.87x) | 464.91 (3.37x) |
| UInt64Value JSON stringify | 44.31 | — | — | 672.60 (15.18x) | 282.43 (6.37x) |
| UInt64Value JSON parse | 126.73 | — | — | 1214.17 (9.58x) | 459.31 (3.62x) |
| Int32Value JSON stringify | 42.76 | — | — | 634.05 (14.83x) | 138.35 (3.24x) |
| Int32Value JSON parse | 128.69 | — | — | 1190.62 (9.25x) | 311.34 (2.42x) |
| UInt32Value JSON stringify | 42.71 | — | — | 632.49 (14.81x) | 138.72 (3.25x) |
| UInt32Value JSON parse | 128.78 | — | — | 1191.97 (9.26x) | 312.43 (2.43x) |
| BoolValue JSON stringify | 40.67 | — | — | 614.75 (15.12x) | 120.90 (2.97x) |
| BoolValue JSON parse | 66.66 | — | — | 1061.20 (15.92x) | 233.78 (3.51x) |
| StringValue JSON stringify | 47.63 | — | — | 656.01 (13.77x) | 180.74 (3.79x) |
| StringValue JSON parse | 136.61 | — | — | 1143.01 (8.37x) | 316.77 (2.32x) |
| BytesValue JSON stringify | 48.38 | — | — | 665.94 (13.76x) | 220.21 (4.55x) |
| BytesValue JSON parse | 152.75 | — | — | 1175.09 (7.69x) | 355.46 (2.33x) |
| TextFormat parse | 729.53 | — | — | 4975.66 (6.82x) | 6680.49 (9.16x) |
| packed int32 decode | 684.41 | 1909.55 (2.79x) | 3208.69 (4.69x) | 1009.83 (1.48x) | 2590.06 (3.78x) |
| packed bool encode | 2.01 | 1346.89 (670.09x) | 521.07 (259.24x) | 15.83 (7.87x) | 2426.41 (1207.17x) |
| packed bool decode | 262.74 | 1530.07 (5.82x) | 2585.83 (9.84x) | 820.69 (3.12x) | 1578.48 (6.01x) |
| largebytes decode | 90.48 | 5486.85 (60.64x) | 3029.04 (33.48x) | 2724.77 (30.11x) | 20314.20 (224.52x) |
| large map decode | 25699.45 | 91015.29 (3.54x) | 91849.10 (3.57x) | 91305.80 (3.55x) | 266078.70 (10.35x) |
| shuffled large map deterministic binary encode | 27939.33 | — | — | 105423.00 (3.77x) | 442244.73 (15.83x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON (including embedded `Duration`, `Struct`, `Value`,
`FieldMask`, `Timestamp`, `StringValue`, `BytesValue`, and recursive nested `Any` payloads), direct WKT JSON, TextFormat, packed scalars, large bytes,
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
