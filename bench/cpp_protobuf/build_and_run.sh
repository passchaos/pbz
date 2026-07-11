#!/usr/bin/env sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
cd "$ROOT"
OUT="bench/cpp_protobuf/generated"
mkdir -p "$OUT"
protoc --cpp_out="$OUT" --proto_path=examples/proto examples/proto/person.proto
c++ -O3 -DNDEBUG -std=c++17 -I"$OUT" bench/cpp_protobuf/main.cc "$OUT/person.pb.cc" -lprotobuf -pthread -o "$OUT/cpp_protobuf_bench"
"$OUT/cpp_protobuf_bench"
