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

The first cross-language baseline is `bench/rust_prost`, a Rust `prost` binary
encode/decode benchmark for the same `Person` schema and payload shape as the
pbz generated/dynamic benchmark. It does not require `protoc`; the Rust message
type is declared directly with `prost` derives.
