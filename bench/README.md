# pbz benchmarks

Run the current pbz baseline with:

```sh
zig build bench -Doptimize=ReleaseFast
```

Run pbz plus every available cross-language baseline with:

```sh
bench/run_compare.sh
```

The benchmark currently measures pbz generated and dynamic paths for:

- binary encode/decode
- packed repeated integer encode/decode
- packed fixed-width `fixed32` encode/decode
- JSON stringify/parse
- TextFormat format/parse

The cross-language binary baselines use the same `Person` payload and the same
`Packed { repeated int32 values = 1; }` and
`FixedPacked { repeated fixed32 values = 1; }` payloads. Treat results as local
machine baselines; use the same schema, payloads, optimization mode, and
hardware when comparing.

Each timed benchmark does a short warmup and reports the best elapsed sample out
of three measured samples. This reduces one-off cold-cache and scheduler noise;
compare complete `bench/run_compare.sh` runs rather than individual lines copied
from different runs.

Cross-language baselines:

- `bench/rust_prost`: Rust `prost` binary encode/decode for the same schema and
  payload shapes. It does not require `protoc`; the Rust message types are
  declared directly with `prost` derives.
- `bench/rust_quick_protobuf`: Rust `quick-protobuf` binary encode/decode for
  the same schema and payload shapes. It hand-writes `MessageRead` /
  `MessageWrite`, does not require `protoc`, and represents a faster Rust
  protobuf baseline than `prost` for several workloads.
- `bench/cpp_protobuf`: C++ protobuf generated-code binary encode/decode for
  the same schema. It requires `protoc`, a C++ compiler, protobuf headers, and
  libprotobuf. It measures both `SerializeToString` and caller-provided buffer
  `SerializeToArray` reuse paths, plus decode into fresh and reused message
  objects. `bench/cpp_protobuf/build_and_run.sh` generates C++ sources into an
  ignored `bench/cpp_protobuf/generated/` directory before compiling.
- `bench/go_protobuf`: Go `google.golang.org/protobuf` generated-code binary
  encode/decode for the same schema. It requires Go, `protoc`, and
  `protoc-gen-go`; generated Go protobuf sources are written to the ignored
  `bench/go_protobuf/personpb/` directory.
