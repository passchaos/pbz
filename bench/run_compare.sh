#!/usr/bin/env sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"

if [ "${PBZ_COMPARE_CPUSET:-}" ]; then
  if ! command -v taskset >/dev/null 2>&1; then
    echo "PBZ_COMPARE_CPUSET is set but taskset was not found" >&2
    exit 127
  fi
  echo "Pinning benchmark commands to CPU set: $PBZ_COMPARE_CPUSET"
fi

run_pinned() {
  if [ "${PBZ_COMPARE_CPUSET:-}" ]; then
    taskset -c "$PBZ_COMPARE_CPUSET" "$@"
  else
    "$@"
  fi
}

echo "== pbz Zig baseline =="
run_pinned zig build bench -Doptimize=ReleaseFast

echo
if command -v cargo >/dev/null 2>&1; then
  echo "== Rust prost baseline =="
  run_pinned cargo run --release --manifest-path bench/rust_prost/Cargo.toml

  echo
  echo "== Rust quick-protobuf baseline =="
  run_pinned cargo run --release --manifest-path bench/rust_quick_protobuf/Cargo.toml
else
  echo "cargo not found; skipping Rust prost and quick-protobuf benchmarks" >&2
fi


echo
if command -v protoc >/dev/null 2>&1 && command -v c++ >/dev/null 2>&1; then
  echo "== C++ protobuf baseline =="
  run_pinned bench/cpp_protobuf/build_and_run.sh
else
  echo "protoc or c++ not found; skipping C++ protobuf benchmark" >&2
fi


echo
if command -v go >/dev/null 2>&1 && command -v protoc >/dev/null 2>&1; then
  echo "== Go protobuf baseline =="
  if run_pinned bench/go_protobuf/build_and_run.sh; then
    :
  else
    echo "Go protobuf benchmark failed; ensure protoc-gen-go is installed" >&2
  fi
else
  echo "go or protoc not found; skipping Go protobuf benchmark" >&2
fi
