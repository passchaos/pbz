#!/usr/bin/env sh
# Build and run the upb (protobuf C runtime) benchmark against the same
# protobuf release used by the upstream conformance suite (default v36.2).
# upb is the C implementation behind Google's production protobuf runtimes
# (C++, Ruby, PHP) and is the closest "latest C implementation" baseline.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
VERSION="${PROTOBUF_VERSION:-36.2}"
CACHE_DIR="${PBZ_CONFORMANCE_CACHE:-$ROOT/.zig-cache/pbz-conformance}"
SRC_DIR="$CACHE_DIR/protobuf-$VERSION"
BUILD_DIR="$CACHE_DIR/build-$VERSION"
OUT="$ROOT/bench/upb_protobuf/generated"

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

# The upb code generators are part of the CMake build but are not needed by the
# conformance runner, so build them on demand.
if [ ! -x "$BUILD_DIR/protoc-gen-upb" ] || [ ! -x "$BUILD_DIR/protoc-gen-upb_minitable" ] || [ ! -x "$BUILD_DIR/protoc-gen-upbdefs" ]; then
  if ! command -v ninja >/dev/null 2>&1; then
    echo "ninja is required to build protoc-gen-upb plugins" >&2
    exit 2
  fi
  (cd "$BUILD_DIR" && ninja protoc-gen-upb protoc-gen-upb_minitable protoc-gen-upbdefs)
fi

mkdir -p "$OUT"
"$PROTOC" \
  --plugin=protoc-gen-upb="$BUILD_DIR/protoc-gen-upb" \
  --plugin=protoc-gen-upb_minitable="$BUILD_DIR/protoc-gen-upb_minitable" \
  --plugin=protoc-gen-upbdefs="$BUILD_DIR/protoc-gen-upbdefs" \
  --upb_out="$OUT" --upb_minitable_out="$OUT" --upbdefs_out="$OUT" \
  --proto_path="$ROOT/examples/proto" \
  "$ROOT/examples/proto/person.proto"

CC="${CC:-cc}"
CXX="${CXX:-c++}"
INCLUDES="-I$SRC_DIR -I$BUILD_DIR -I$SRC_DIR/upb/reflection/cmake -I$OUT"

# shellcheck disable=SC2086
"$CC" -O3 -DNDEBUG -std=c11 $INCLUDES -c \
  "$OUT/person.upb_minitable.c" -o "$OUT/person.upb_minitable.o"
# shellcheck disable=SC2086
"$CC" -O3 -DNDEBUG -std=c11 $INCLUDES -c \
  "$OUT/person.upbdefs.c" -o "$OUT/person.upbdefs.o"
# shellcheck disable=SC2086
"$CXX" -O3 -DNDEBUG -std=c++17 $INCLUDES -c \
  "$ROOT/bench/upb_protobuf/main.cc" -o "$OUT/main.o"

"$CXX" -O3 -DNDEBUG -std=c++17 \
  "$OUT/main.o" "$OUT/person.upb_minitable.o" "$OUT/person.upbdefs.o" \
  "$BUILD_DIR/libupb.a" \
  "$BUILD_DIR/third_party/utf8_range/libutf8_range.a" \
  "$BUILD_DIR/third_party/utf8_range/libutf8_validity.a" \
  -o "$OUT/upb_protobuf_bench"

"$OUT/upb_protobuf_bench"
