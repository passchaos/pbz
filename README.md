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

Latest accepted comparison (`/tmp/pbz-compare-after-stringvalue-json.log`,
summarized in `/tmp/pbz-summary-after-stringvalue-json.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 23.50 | 97.96 (4.17x) | 52.07 (2.22x) | 100.69 (4.28x) | 833.32 (35.46x) |
| binary decode | 132.49 | 244.71 (1.85x) | 226.21 (1.71x) | 225.54 (1.70x) | 924.02 (6.97x) |
| unknown count by number | 3.57 | — | — | 151.23 (42.36x) | — |
| scalarmix encode | 18.70 | 110.22 (5.89x) | 48.21 (2.58x) | 30.57 (1.63x) | 229.93 (12.30x) |
| scalarmix decode | 39.00 | 135.69 (3.48x) | 197.60 (5.07x) | 85.83 (2.20x) | 308.04 (7.90x) |
| textbytes encode | 9.52 | 76.72 (8.06x) | 35.27 (3.70x) | 117.14 (12.30x) | 145.32 (15.26x) |
| complex decode | 171.28 | 389.72 (2.28x) | 344.99 (2.01x) | 388.18 (2.27x) | 1491.23 (8.71x) |
| complex JSON parse | 2376.87 | — | — | 12109.30 (5.09x) | 7941.96 (3.34x) |
| Any WKT JSON stringify | 150.44 | — | — | 1873.00 (12.45x) | 927.82 (6.17x) |
| Any WKT JSON parse | 515.32 | — | — | 3077.79 (5.97x) | 1473.04 (2.86x) |
| Duration JSON stringify | 57.76 | — | — | 988.73 (17.12x) | 342.23 (5.93x) |
| Duration JSON parse | 7.94 | — | — | 1446.16 (182.14x) | 395.46 (49.81x) |
| FieldMask JSON stringify | 115.00 | — | — | 897.74 (7.81x) | 625.32 (5.44x) |
| FieldMask JSON parse | 146.37 | — | — | 1644.52 (11.24x) | 879.02 (6.01x) |
| Timestamp JSON stringify | 95.73 | — | — | 1143.18 (11.94x) | 444.54 (4.64x) |
| Timestamp JSON parse | 41.49 | — | — | 1502.84 (36.22x) | 439.46 (10.59x) |
| StringValue JSON stringify | 47.36 | — | — | 663.88 (14.02x) | 176.50 (3.73x) |
| StringValue JSON parse | 135.21 | — | — | 1142.77 (8.45x) | 281.44 (2.08x) |
| TextFormat parse | 708.25 | — | — | 5007.02 (7.07x) | 6805.18 (9.61x) |
| packed int32 decode | 688.02 | 1909.70 (2.78x) | 3209.00 (4.66x) | 949.39 (1.38x) | 3520.50 (5.12x) |
| packed bool encode | 2.01 | 1350.61 (671.95x) | 518.88 (258.15x) | 16.26 (8.09x) | 2221.06 (1105.00x) |
| packed bool decode | 264.14 | 1518.67 (5.75x) | 2551.93 (9.66x) | 807.59 (3.06x) | 2044.74 (7.74x) |
| largebytes decode | 89.37 | 5577.64 (62.41x) | 3005.53 (33.63x) | 2794.66 (31.27x) | 23637.23 (264.49x) |
| large map decode | 25612.42 | 90610.35 (3.54x) | 89546.16 (3.50x) | 91118.00 (3.56x) | 276288.43 (10.79x) |
| shuffled large map deterministic binary encode | 28038.65 | — | — | 94770.40 (3.38x) | 391180.88 (13.95x) |

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
