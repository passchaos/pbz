#!/usr/bin/env sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"

echo "== pbz Zig baseline =="
zig build bench -Doptimize=ReleaseFast

echo
if command -v cargo >/dev/null 2>&1; then
  echo "== Rust prost baseline =="
  cargo run --release --manifest-path bench/rust_prost/Cargo.toml
else
  echo "cargo not found; skipping Rust prost benchmark" >&2
fi


echo
if command -v protoc >/dev/null 2>&1 && command -v c++ >/dev/null 2>&1; then
  echo "== C++ protobuf baseline =="
  bench/cpp_protobuf/build_and_run.sh
else
  echo "protoc or c++ not found; skipping C++ protobuf benchmark" >&2
fi


echo
if command -v go >/dev/null 2>&1 && command -v protoc >/dev/null 2>&1; then
  echo "== Go protobuf baseline =="
  if bench/go_protobuf/build_and_run.sh; then
    :
  else
    echo "Go protobuf benchmark failed; ensure protoc-gen-go is installed" >&2
  fi
else
  echo "go or protoc not found; skipping Go protobuf benchmark" >&2
fi
