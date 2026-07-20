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
python3 bench/summarize_compare.py /tmp/pbz-compare.log --pivot > /tmp/pbz-compare-pivot.md
```

Use `--fail-on-loss` when a CI-style non-zero exit is desired for any parsed
row where the fastest relevant public pbz path is still slower than the fastest
baseline path for the same workload. Use `--pivot` to emit the README-style
workload-by-baseline table without manually transposing the detailed summary.
The summary compares the fastest relevant public pbz path against Rust
`prost`, Rust `quick-protobuf`, C++ protobuf, and Go protobuf rows when present.
See [`COVERAGE.md`](COVERAGE.md) for the current feature/performance audit
checklist and the remaining non-goal/open-audit items.

The benchmark currently measures pbz generated and dynamic paths for:

- binary encode/decode
- generated/dynamic unknown-field stress decode and count-by-number query,
  including optional generated and dynamic raw-field-number / compact run
  sidecars for repeated queries
- deterministic binary encode
- scalar mix encode/decode
- string/bytes and repeated string/bytes encode/decode, including generated
  borrowed slices for copy-free output paths
- large bytes and repeated large bytes encode/decode, including generated
  borrowed slices/views for copy-free payload paths
- proto3 optional presence plus oneof encode/decode
- complex nested message / oneof / map-message encode/decode, deterministic encode, plus JSON/TextFormat stringify/parse
- `google.protobuf.Any` with embedded well-known-type JSON values, including
  zero/escaped-input parse/explicit-plus parse/short-fraction parse/positive/micro/nano/integer-negative/fractional-negative/min-max-bound `Duration`, camel-case, escaped JSON parse input, and empty `FieldMask`, escaped-input parse/short-fraction parse/micro/nano/offset/min/pre/post/max-bound `Timestamp`, canonical `Empty`, non-empty/escaped-input parse/number-exponent parse/surrogate-pair value parse/surrogate-pair key parse/empty `Struct`, object/escaped-object parse/object-number-exponent/object-surrogate-pair value parse/object-surrogate-pair key parse/list/escaped-list/surrogate-list/string-scalar/escaped-string-scalar/surrogate-string-scalar/number-exponent/negative-number `Value` (including default-like scalar and empty object/list kinds), 64-bit min/zero/positive/number-input parse/numeric-exponent parse/negative/max `Int64Value`, negative/zero/positive finite/string-input parse/numeric-exponent parse `DoubleValue`, non-finite `DoubleValue` (`NaN`, `Infinity`, `-Infinity`), negative/zero/positive finite/string-input parse/numeric-exponent parse `FloatValue`, non-finite `FloatValue` (`NaN`, `Infinity`, `-Infinity`), min/zero/positive/string-input parse/numeric-exponent parse/negative/max `Int32Value`, zero/normal/string-input parse/numeric-exponent parse/max unsigned `UInt32Value`, zero/normal/number-input parse/numeric-exponent parse/max unsigned `UInt64Value`, true/false `BoolValue`, non-empty/escape-input parse/surrogate-pair parse/empty `StringValue`, padded-standard/base64url/unpadded-base64 parse/empty `BytesValue`, and recursive nested `Any`, stringify/parse
- direct zero, escaped-input parse, explicit-plus parse, short-fraction parse, positive, micro, nano, integer-negative, fractional-negative, min-bound, and max-bound `google.protobuf.Duration` JSON stringify/parse
- direct non-empty, escaped-input parse, and empty `google.protobuf.FieldMask` JSON stringify/parse
- direct escaped-input parse, short-fraction parse, micro, nano, timezone-offset parse, min-bound, pre-epoch, post-epoch, and max-bound `google.protobuf.Timestamp` JSON stringify/parse
- direct `google.protobuf.Empty`, non-empty/escaped-input parse/number-exponent parse/surrogate-pair value parse/surrogate-pair key parse/empty `Struct`, object/escaped-object parse/object-number-exponent/object-surrogate-pair value parse/object-surrogate-pair key parse/list/escaped-list/surrogate-list/string-scalar/escaped-string-scalar/surrogate-string-scalar/number-exponent/negative-number `Value` (including default-like scalar and empty object/list kinds), and escaped/surrogate-pair/non-empty/empty `ListValue` JSON stringify/parse
- direct scalar wrapper JSON stringify/parse for `DoubleValue`, `FloatValue`,
  min/zero/positive/number-input parse/numeric-exponent parse/negative/max `Int64Value`, zero/normal/number-input parse/numeric-exponent parse/max `UInt64Value`, min/zero/positive/string-input parse/numeric-exponent parse/negative/max `Int32Value`, zero/normal/string-input parse/numeric-exponent parse/max `UInt32Value`, true/false `BoolValue`, plus negative/zero/positive finite, finite string-input parse, numeric-exponent parse, and non-finite `DoubleValue` and `FloatValue` (`NaN`, `Infinity`, `-Infinity`),
  non-empty/escape-input parse/surrogate-pair parse/empty `StringValue`, and padded-standard/base64url/unpadded-base64 parse/empty `BytesValue`
- large `map<string, int32>` encode/decode
- shuffled large `map<string, int32>` deterministic encode against C++/Go
- packed repeated integer encode/decode
- packed fixed-width `fixed32` / `fixed64` / `sfixed32` / `sfixed64` / `float` / `double` encode/decode
- packed `uint32` / `uint64` / `int64` / `sint32` / `sint64` varint, `bool`, and enum encode/decode
- generated zero-copy borrowed payload views for packed fixed-width fields when
  the caller only needs to inspect the wire buffer
- generated borrowed packed bool slices for copy-free output of trusted bool
  arrays
- generated typed iterators for packed varint fields
- generated known-schema decode reuse for trusted same-schema hot paths,
  including packed repeated scalar and open-enum messages with reusable destination storage
- JSON stringify/parse, including generated `map<string, int32>` surrogate-pair key parse, generated null-field parse, generated enum-name parse, generated proto-name stringify, generated proto-name parse, generated open-enum numeric parse, and generated integer numeric-exponent token parse
- TextFormat format/parse

The unknown-field stress rows are pbz regression signals. Generated messages
preserve exact raw-field byte slices; callers that need to issue repeated
number queries over those raw fields can build either a parallel field-number
sidecar with `pbz.wire.rawFieldNumbersAlloc` /
`pbz.wire.rawFieldNumberCount` or a compact sorted run sidecar with
`pbz.wire.rawFieldNumberRunsAlloc` / `pbz.wire.rawFieldNumberRunCount`.
Dynamic messages expose the same sidecar shape directly from their already
decoded `UnknownField.number` metadata via `unknownFieldNumbersAlloc` and
`unknownFieldNumberRunsAlloc`, avoiding raw tag re-decode for reflection-heavy
callers.
`bench/summarize_compare.py` includes the C++ `UnknownFieldSet`
count-by-number row in the fail-on-loss matrix when comparing against the
compact run sidecar. The C++ unknown-field decode row remains manual context:
C++ exposes parsed unknown fields, while pbz preserves exact raw-field byte
slices.

The cross-language binary, JSON, and TextFormat baselines use the same `Person` payload, a `TextBytes` payload with string/bytes and repeated string/bytes fields, a `LargeBytes` payload with a 64 KiB bytes field plus repeated 4 KiB chunks, a `PresenceMix` payload with proto3 optional scalar/string/bytes fields plus oneof, a `Complex` payload with nested messages, oneof, repeated message fields, and `map<string, message>`, and the same
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
`LargeMap { map<string, int32> counts = 1; }` payloads, including a shuffled
insertion-order large map for deterministic map encoding. Treat results as
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
  protobuf util JSON stringify/parse, protobuf TextFormat format/parse,
  UnknownFieldSet stress decode/count rows, plus decode into fresh and reused
  message objects. `bench/cpp_protobuf/build_and_run.sh` generates C++ sources into an
  ignored `bench/cpp_protobuf/generated/` directory before compiling.
- `bench/go_protobuf`: Go `google.golang.org/protobuf` generated-code binary
  encode/decode, deterministic `MarshalOptions`, plus `protojson`
  stringify/parse and `prototext` format/parse for the same schema. It requires Go, `protoc`, and
  `protoc-gen-go`; generated Go protobuf sources are written to the ignored
  `bench/go_protobuf/personpb/` directory.
