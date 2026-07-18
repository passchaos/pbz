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

Latest accepted comparison (`/tmp/pbz-compare-after-bytesvalue-json.log`,
summarized in `/tmp/pbz-summary-after-bytesvalue-json.txt`) ended with:

```text
All parsed cross-language rows are pbz wins.
```

Representative rows from that run. Baseline cells show `ns/op (baseline / pbz)`:

| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |
|---|---:|---:|---:|---:|---:|
| binary encode | 20.43 | 120.21 (5.88x) | 53.14 (2.60x) | 102.78 (5.03x) | 859.87 (42.09x) |
| binary decode | 91.95 | 254.41 (2.77x) | 228.28 (2.48x) | 211.55 (2.30x) | 900.86 (9.80x) |
| unknown count by number | 3.57 | — | — | 153.71 (43.05x) | — |
| scalarmix encode | 27.00 | 106.26 (3.94x) | 49.55 (1.84x) | 29.06 (1.08x) | 201.15 (7.45x) |
| scalarmix decode | 36.16 | 134.47 (3.72x) | 179.53 (4.96x) | 83.37 (2.31x) | 284.00 (7.85x) |
| textbytes encode | 13.54 | 79.17 (5.85x) | 33.59 (2.48x) | 121.83 (9.00x) | 148.37 (10.96x) |
| complex decode | 170.47 | 402.00 (2.36x) | 338.59 (1.99x) | 394.38 (2.31x) | 1375.25 (8.07x) |
| complex JSON parse | 2364.98 | — | — | 12024.20 (5.08x) | 7781.43 (3.29x) |
| Any WKT JSON stringify | 134.78 | — | — | 1941.21 (14.40x) | 1037.29 (7.70x) |
| Any WKT JSON parse | 519.40 | — | — | 3023.87 (5.82x) | 1552.93 (2.99x) |
| Duration JSON stringify | 57.77 | — | — | 970.24 (16.79x) | 350.43 (6.07x) |
| Duration JSON parse | 7.80 | — | — | 1479.35 (189.66x) | 376.39 (48.26x) |
| FieldMask JSON stringify | 117.62 | — | — | 909.97 (7.74x) | 669.35 (5.69x) |
| FieldMask JSON parse | 149.73 | — | — | 1671.00 (11.16x) | 971.45 (6.49x) |
| Timestamp JSON stringify | 95.39 | — | — | 1136.12 (11.91x) | 440.52 (4.62x) |
| Timestamp JSON parse | 41.69 | — | — | 1492.73 (35.81x) | 430.87 (10.34x) |
| StringValue JSON stringify | 47.14 | — | — | 655.93 (13.91x) | 180.38 (3.83x) |
| StringValue JSON parse | 137.45 | — | — | 1144.70 (8.33x) | 294.15 (2.14x) |
| BytesValue JSON stringify | 48.66 | — | — | 676.90 (13.91x) | 189.77 (3.90x) |
| BytesValue JSON parse | 147.64 | — | — | 1170.91 (7.93x) | 310.25 (2.10x) |
| TextFormat parse | 722.62 | — | — | 4978.57 (6.89x) | 6643.21 (9.19x) |
| packed int32 decode | 767.89 | 1916.71 (2.50x) | 3272.70 (4.26x) | 958.25 (1.25x) | 9462.94 (12.32x) |
| packed bool encode | 2.01 | 1336.72 (665.03x) | 520.40 (258.91x) | 15.98 (7.95x) | 2221.36 (1105.15x) |
| packed bool decode | 264.04 | 1538.50 (5.83x) | 2565.26 (9.72x) | 810.12 (3.07x) | 2084.64 (7.90x) |
| largebytes decode | 87.82 | 5779.63 (65.81x) | 2999.32 (34.15x) | 2813.79 (32.04x) | 23549.49 (268.16x) |
| large map decode | 25574.63 | 90439.43 (3.54x) | 89597.54 (3.50x) | 95565.90 (3.74x) | 272413.86 (10.65x) |
| shuffled large map deterministic binary encode | 34142.60 | — | — | 94723.60 (2.77x) | 386668.84 (11.33x) |

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
