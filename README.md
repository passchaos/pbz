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

Latest accepted comparison (`/tmp/pbz-compare-after-any-wkt-json.log`,
summarized in `/tmp/pbz-summary-after-any-wkt-json.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 16.87 | 110.62 (6.56x) | 64.81 (3.84x) | 130.97 (7.76x) | 807.79 (47.88x) |
| binary decode | 90.25 | 251.69 (2.79x) | 268.51 (2.98x) | 221.78 (2.46x) | 854.49 (9.47x) |
| unknown count by number | 3.57 | — | — | 153.50 (43.00x) | — |
| scalarmix encode | 19.08 | 109.31 (5.73x) | 51.02 (2.67x) | 30.57 (1.60x) | 210.14 (11.01x) |
| scalarmix decode | 38.49 | 172.20 (4.47x) | 184.55 (4.79x) | 89.81 (2.33x) | 284.76 (7.40x) |
| textbytes encode | 16.12 | 94.58 (5.87x) | 34.31 (2.13x) | 120.80 (7.49x) | 142.75 (8.86x) |
| complex decode | 178.45 | 399.28 (2.24x) | 347.02 (1.94x) | 389.93 (2.19x) | 1261.69 (7.07x) |
| complex JSON parse | 2374.27 | — | — | 11922.80 (5.02x) | 6945.32 (2.93x) |
| Any WKT JSON parse | 520.34 | — | — | 2997.30 (5.76x) | 1423.98 (2.74x) |
| TextFormat parse | 703.34 | — | — | 4992.53 (7.10x) | 6032.92 (8.58x) |
| packed int32 decode | 677.61 | 1904.19 (2.81x) | 3212.47 (4.74x) | 967.00 (1.43x) | 2898.93 (4.28x) |
| packed bool encode | 2.01 | 1356.01 (674.63x) | 518.48 (257.95x) | 15.95 (7.93x) | 2454.58 (1221.18x) |
| packed bool decode | 262.49 | 1572.95 (5.99x) | 2550.01 (9.71x) | 813.17 (3.10x) | 1651.76 (6.29x) |
| largebytes decode | 93.45 | 5596.87 (59.89x) | 3003.77 (32.14x) | 2757.74 (29.51x) | 20946.21 (224.14x) |
| large map decode | 25585.68 | 90807.37 (3.55x) | 89779.50 (3.51x) | 92012.60 (3.60x) | 280116.01 (10.95x) |
| shuffled large map deterministic binary encode | 27989.56 | — | — | 92479.60 (3.30x) | 368340.30 (13.16x) |

The matrix covers binary encode/decode, unknown-field count-by-number, deterministic
encode, JSON, Any/WKT JSON, TextFormat, packed scalars, large bytes, maps,
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
