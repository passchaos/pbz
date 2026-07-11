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
- JSON stringify/parse
- TextFormat format/parse

This is the foundation for comparing against C++ protobuf and Rust prost in a
future cross-language benchmark. Treat results as local machine baselines; use
the same schema, payloads, optimization mode, and hardware when comparing.

Cross-language baselines:

- `bench/rust_prost`: Rust `prost` binary encode/decode for the same `Person`
  schema and payload shape. It does not require `protoc`; the Rust message type
  is declared directly with `prost` derives.
- `bench/cpp_protobuf`: C++ protobuf generated-code binary encode/decode for
  the same schema. It requires `protoc`, a C++ compiler, protobuf headers, and
  libprotobuf. `bench/cpp_protobuf/build_and_run.sh` generates C++ sources into
  an ignored `bench/cpp_protobuf/generated/` directory before compiling.
