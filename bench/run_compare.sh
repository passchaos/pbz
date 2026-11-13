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
  if [ -z "${GOMAXPROCS:-}" ]; then
    GOMAXPROCS="$(printf '%s\n' "$PBZ_COMPARE_CPUSET" | awk -F, '{
      count = 0
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^[0-9]+-[0-9]+$/) {
          split($i, range, "-")
          count += range[2] - range[1] + 1
        } else if ($i ~ /^[0-9]+$/) {
          count += 1
        }
      }
      print (count > 0 ? count : 1)
    }')"
    export GOMAXPROCS
    echo "Setting GOMAXPROCS=$GOMAXPROCS for pinned Go benchmark runs"
  fi
fi

if [ -z "${PBZ_COMPARE_DRY_RUN:-}" ]; then
  echo "== Toolchain versions =="
  printf 'Zig: '
  zig version
  if command -v rustc >/dev/null 2>&1; then
    printf 'Rust: '
    rustc --version
  fi
  if command -v cargo >/dev/null 2>&1; then
    printf 'Cargo: '
    cargo --version
  fi
  if command -v go >/dev/null 2>&1; then
    printf 'Go: '
    go version
  fi
  printf 'Go benchmark toolchain: %s\n' "${PBZ_GO_TOOLCHAIN:-go1.27.4}"
  if command -v protoc >/dev/null 2>&1; then
    printf 'protoc: '
    protoc --version
  fi
  if command -v c++ >/dev/null 2>&1; then
    printf 'C++: '
    c++ --version | head -n 1
  fi
  echo
fi

run_pinned() {
  if [ "${PBZ_COMPARE_DRY_RUN:-}" ]; then
    printf 'DRY RUN:'
    if [ "${PBZ_COMPARE_CPUSET:-}" ]; then
      printf ' taskset -c %s' "$PBZ_COMPARE_CPUSET"
    fi
    printf ' %s' "$@"
    printf '\n'
    return 0
  fi
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

if [ "${PBZ_COMPARE_LATEST_CPP:-0}" = "1" ]; then
  echo
  echo "== C++ protobuf latest (conformance-pinned) baseline =="
  if ! run_pinned bench/cpp_protobuf/build_latest.sh; then
    echo "latest C++ protobuf baseline failed; install cmake/ninja or run tools/fetch_conformance_runner.sh" >&2
  fi
fi

if [ "${PBZ_COMPARE_UPB:-0}" = "1" ]; then
  echo
  echo "== upb protobuf (conformance-pinned) baseline =="
  if ! run_pinned bench/upb_protobuf/build_and_run.sh; then
    echo "upb protobuf baseline failed; install ninja and run tools/fetch_conformance_runner.sh" >&2
  fi
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
