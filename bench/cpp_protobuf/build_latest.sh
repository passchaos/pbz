#!/usr/bin/env sh
# Build and run the C++ binary benchmark against the same protobuf release used
# by the upstream conformance suite (default v36.2), instead of the system
# libprotobuf. Requires cmake, ninja, a C++17 compiler, and network access on
# the first run.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
VERSION="${PROTOBUF_VERSION:-36.2}"
CACHE_DIR="${PBZ_CONFORMANCE_CACHE:-$ROOT/.zig-cache/pbz-conformance}"
SRC_DIR="$CACHE_DIR/protobuf-$VERSION"
BUILD_DIR="$CACHE_DIR/build-$VERSION"
OUT="$ROOT/bench/cpp_protobuf/generated_latest"

if [ ! -d "$SRC_DIR" ] || { [ ! -x "$BUILD_DIR/protoc" ] && [ ! -x "$BUILD_DIR/protoc-$VERSION" ]; }; then
  echo "protobuf $VERSION build not found; running tools/fetch_conformance_runner.sh" >&2
  "$ROOT/tools/fetch_conformance_runner.sh" >/dev/null
fi

PROTOC="$BUILD_DIR/protoc"
if [ ! -x "$PROTOC" ]; then
  PROTOC="$BUILD_DIR/protoc-$VERSION"
fi
if [ ! -x "$PROTOC" ]; then
  echo "protoc for protobuf $VERSION not found in $BUILD_DIR" >&2
  exit 2
fi

mkdir -p "$OUT"
"$PROTOC" --cpp_out="$OUT" --proto_path="$ROOT/examples/proto" \
  "$ROOT/examples/proto/person.proto"

CXX="${CXX:-c++}"
INCLUDES="-I$SRC_DIR/src -I$BUILD_DIR/_deps/absl-src -I$SRC_DIR/third_party/utf8_range -I$OUT"
# shellcheck disable=SC2086
"$CXX" -O3 -DNDEBUG -std=c++17 $INCLUDES -c \
  "$ROOT/bench/cpp_protobuf/main.cc" -o "$OUT/main.o"
# shellcheck disable=SC2086
"$CXX" -O3 -DNDEBUG -std=c++17 $INCLUDES -c \
  "$OUT/person.pb.cc" -o "$OUT/person.pb.o"

LINK_CMD="$(cd "$BUILD_DIR" && ninja -t commands conformance_test_runner | tail -n 1)"
python3 - "$BUILD_DIR" "$OUT/main.o" "$OUT/person.pb.o" \
  "$OUT/cpp_protobuf_latest_bench" "$LINK_CMD" <<'PY'
import re
import subprocess
import sys

build_dir, mini_obj, person_obj, output, command = sys.argv[1:]
command = command.removeprefix(": && ")
command = re.sub(r"CMakeFiles/conformance_test_runner\.dir/\S+\.o\s+", "", command)
command = command.replace(
    "-Wl,--dependency-file=CMakeFiles/conformance_test_runner.dir/link.d ", ""
)
command = command.replace("liblibconformance_common.a", "")
command = command.replace(
    "-o conformance_test_runner", f"{mini_obj} {person_obj} -o {output}"
)
subprocess.run(command, shell=True, cwd=build_dir, check=True)
PY

"$OUT/cpp_protobuf_latest_bench"
