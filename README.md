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

Latest accepted comparison (`/tmp/pbz-compare-after-struct-value-json-isolated.log`,
summarized in `/tmp/pbz-summary-after-struct-value-json-isolated.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 20.15 | 104.44 (5.18x) | 50.09 (2.49x) | 98.30 (4.88x) | 867.32 (43.04x) |
| binary decode | 88.22 | 271.88 (3.08x) | 305.37 (3.46x) | 206.65 (2.34x) | 894.47 (10.14x) |
| unknown count by number | 3.57 | — | — | 151.36 (42.40x) | — |
| scalarmix encode | 17.95 | 100.25 (5.58x) | 48.14 (2.68x) | 29.22 (1.63x) | 214.78 (11.97x) |
| scalarmix decode | 34.70 | 138.04 (3.98x) | 179.42 (5.17x) | 83.50 (2.41x) | 306.96 (8.85x) |
| textbytes encode | 11.53 | 89.54 (7.77x) | 33.46 (2.90x) | 120.50 (10.45x) | 142.05 (12.32x) |
| complex decode | 169.06 | 394.98 (2.34x) | 340.20 (2.01x) | 402.71 (2.38x) | 1351.44 (7.99x) |
| complex JSON parse | 2401.84 | — | — | 11928.50 (4.97x) | 7458.29 (3.11x) |
| Any WKT JSON stringify | 120.92 | — | — | 1879.89 (15.55x) | 985.64 (8.15x) |
| Any WKT JSON parse | 528.09 | — | — | 2981.64 (5.65x) | 1533.76 (2.90x) |
| Duration JSON stringify | 57.49 | — | — | 963.11 (16.75x) | 378.27 (6.58x) |
| Duration JSON parse | 8.04 | — | — | 1459.12 (181.48x) | 393.22 (48.91x) |
| FieldMask JSON stringify | 65.70 | — | — | 889.96 (13.55x) | 639.27 (9.73x) |
| FieldMask JSON parse | 146.93 | — | — | 1653.81 (11.26x) | 877.63 (5.97x) |
| Timestamp JSON stringify | 96.40 | — | — | 1147.29 (11.90x) | 416.46 (4.32x) |
| Timestamp JSON parse | 41.62 | — | — | 1488.87 (35.77x) | 446.85 (10.74x) |
| Empty JSON stringify | 20.90 | — | — | 495.16 (23.69x) | 87.88 (4.20x) |
| Empty JSON parse | 68.22 | — | — | 720.51 (10.56x) | 217.72 (3.19x) |
| Struct JSON stringify | 169.41 | — | — | 5808.46 (34.29x) | 3043.16 (17.96x) |
| Struct JSON parse | 856.16 | — | — | 10905.40 (12.74x) | 4683.18 (5.47x) |
| Value JSON stringify | 176.84 | — | — | 6612.68 (37.39x) | 3210.24 (18.15x) |
| Value JSON parse | 878.09 | — | — | 12197.00 (13.89x) | 4931.60 (5.62x) |
| ListValue JSON stringify | 136.36 | — | — | 4782.52 (35.07x) | 2098.33 (15.39x) |
| ListValue JSON parse | 664.01 | — | — | 8517.02 (12.83x) | 3779.63 (5.69x) |
| DoubleValue JSON stringify | 59.72 | — | — | 864.20 (14.47x) | 190.73 (3.19x) |
| DoubleValue JSON parse | 110.36 | — | — | 1230.42 (11.15x) | 287.96 (2.61x) |
| FloatValue JSON stringify | 69.93 | — | — | 808.63 (11.56x) | 185.30 (2.65x) |
| FloatValue JSON parse | 110.01 | — | — | 1224.78 (11.13x) | 286.89 (2.61x) |
| Int64Value JSON stringify | 40.67 | — | — | 679.19 (16.70x) | 284.99 (7.01x) |
| Int64Value JSON parse | 126.14 | — | — | 1229.96 (9.75x) | 464.05 (3.68x) |
| UInt64Value JSON stringify | 40.88 | — | — | 678.09 (16.59x) | 280.97 (6.87x) |
| UInt64Value JSON parse | 125.76 | — | — | 1213.10 (9.65x) | 465.98 (3.71x) |
| Int32Value JSON stringify | 43.16 | — | — | 633.28 (14.67x) | 134.24 (3.11x) |
| Int32Value JSON parse | 129.44 | — | — | 1189.25 (9.19x) | 309.85 (2.39x) |
| UInt32Value JSON stringify | 43.29 | — | — | 647.55 (14.96x) | 139.33 (3.22x) |
| UInt32Value JSON parse | 129.53 | — | — | 1193.32 (9.21x) | 314.57 (2.43x) |
| BoolValue JSON stringify | 41.73 | — | — | 615.11 (14.74x) | 126.94 (3.04x) |
| BoolValue JSON parse | 59.39 | — | — | 1060.53 (17.86x) | 223.85 (3.77x) |
| StringValue JSON stringify | 47.16 | — | — | 676.11 (14.34x) | 183.78 (3.90x) |
| StringValue JSON parse | 136.89 | — | — | 1150.48 (8.40x) | 328.87 (2.40x) |
| BytesValue JSON stringify | 48.56 | — | — | 663.29 (13.66x) | 214.43 (4.42x) |
| BytesValue JSON parse | 146.76 | — | — | 1176.21 (8.01x) | 351.51 (2.40x) |
| TextFormat parse | 697.12 | — | — | 4995.92 (7.17x) | 6557.58 (9.41x) |
| packed int32 decode | 687.69 | 1912.57 (2.78x) | 3219.19 (4.68x) | 953.14 (1.39x) | 2598.61 (3.78x) |
| packed bool encode | 2.01 | 1331.34 (662.36x) | 521.79 (259.60x) | 16.06 (7.99x) | 2212.66 (1100.83x) |
| packed bool decode | 262.80 | 1534.77 (5.84x) | 2561.30 (9.75x) | 809.85 (3.08x) | 1599.31 (6.09x) |
| largebytes decode | 92.67 | 5554.52 (59.94x) | 3047.50 (32.89x) | 2723.28 (29.39x) | 20347.94 (219.57x) |
| large map decode | 25826.53 | 90160.49 (3.49x) | 89756.37 (3.48x) | 90275.30 (3.50x) | 268129.18 (10.38x) |
| shuffled large map deterministic binary encode | 28578.46 | — | — | 90806.90 (3.18x) | 441866.74 (15.46x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON, direct WKT JSON, TextFormat, packed scalars, large bytes, maps,
oneof/optional workloads, and complex nested messages. Benchmark results are hardware-sensitive; compare full same-machine
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
