# pbz benchmarks

Run the current pbz baseline with:

```sh
zig build bench -Doptimize=ReleaseFast
```

The benchmark currently measures pbz generated and dynamic paths for:

- binary encode/decode
- JSON stringify/parse
- TextFormat format/parse

This is the foundation for comparing against C++ protobuf and Rust prost in a
future cross-language benchmark. Treat results as local machine baselines; use
the same schema, payloads, optimization mode, and hardware when comparing.
