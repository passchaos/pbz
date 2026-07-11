# pbz benchmarks

Run the current pbz baseline with:

```sh
zig build bench -Doptimize=ReleaseFast
```

Run pbz plus every available cross-language baseline with:

```sh
bench/run_compare.sh
```

Summarize a full comparison log with:

```sh
bench/run_compare.sh 2>&1 | tee /tmp/pbz-compare.log
python3 bench/summarize_compare.py /tmp/pbz-compare.log
```

Use `--fail-on-loss` when a CI-style non-zero exit is desired for any parsed
row where the fastest pbz generated path is still slower than the fastest
baseline path for the same workload.

The benchmark currently measures pbz generated and dynamic paths for:

- binary encode/decode
- deterministic binary encode
- scalar mix encode/decode
- string/bytes and repeated string/bytes encode/decode
- complex nested message / oneof / map-message encode/decode, deterministic encode, plus JSON/TextFormat stringify/parse
- large `map<string, int32>` encode/decode
- packed repeated integer encode/decode
- packed fixed-width `fixed32` / `fixed64` / `sfixed32` / `sfixed64` / `float` / `double` encode/decode
- packed `uint32` / `uint64` / `int64` / `sint32` / `sint64` varint, `bool`, and enum encode/decode
- zero-copy borrowed payload views for packed fixed-width fields when the
  caller only needs to inspect the wire buffer
- JSON stringify/parse
- TextFormat format/parse

The cross-language binary, JSON, and TextFormat baselines use the same `Person` payload, a `TextBytes` payload with string/bytes and repeated string/bytes fields, a `Complex` payload with nested messages, oneof, repeated message fields, and `map<string, message>`, and the same
`Packed { repeated int32 values = 1; }` and
`FixedPacked { repeated fixed32 values = 1; }` and
`Fixed64Packed { repeated fixed64 values = 1; }` and
`SFixedPacked { repeated sfixed32 values = 1; }` and
`SFixed64Packed { repeated sfixed64 values = 1; }` and
`FloatPacked { repeated float values = 1; }` and
`DoublePacked { repeated double values = 1; }` and
`UInt64Packed { repeated uint64 values = 1; }` and
`UInt32Packed { repeated uint32 values = 1; }` and
`Int64Packed { repeated int64 values = 1; }` and
`SInt32Packed { repeated sint32 values = 1; }` and
`SInt64Packed { repeated sint64 values = 1; }` and
`BoolPacked { repeated bool values = 1; }` and
`EnumPacked { repeated BenchKind values = 1; }` and
`LargeMap { map<string, int32> counts = 1; }` payloads. Treat results as
local machine baselines; use the same schema, payloads, optimization mode, and
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
  `SerializeToArray` reuse paths, deterministic `CodedOutputStream` encoding,
  protobuf util JSON stringify/parse, protobuf TextFormat format/parse, plus decode into fresh and reused message
  objects. `bench/cpp_protobuf/build_and_run.sh` generates C++ sources into an
  ignored `bench/cpp_protobuf/generated/` directory before compiling.
- `bench/go_protobuf`: Go `google.golang.org/protobuf` generated-code binary
  encode/decode, deterministic `MarshalOptions`, plus `protojson`
  stringify/parse and `prototext` format/parse for the same schema. It requires Go, `protoc`, and
  `protoc-gen-go`; generated Go protobuf sources are written to the ignored
  `bench/go_protobuf/personpb/` directory.
