#!/usr/bin/env sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
VERSION="${PROTOBUF_CONFORMANCE_VERSION:-35.1}"
TAG="v${VERSION}"
CACHE_DIR="${PBZ_CONFORMANCE_CACHE:-$ROOT/.zig-cache/pbz-conformance}"
SRC_DIR="$CACHE_DIR/protobuf-$VERSION"
ARCHIVE="$CACHE_DIR/protobuf-$VERSION.tar.gz"
BUILD_DIR="$CACHE_DIR/build-$VERSION"
RUNNER="$BUILD_DIR/conformance_test_runner"
DESC="$BUILD_DIR/conformance/test_messages.desc"
URL="https://github.com/protocolbuffers/protobuf/releases/download/$TAG/protobuf-$VERSION.tar.gz"

mkdir -p "$CACHE_DIR"
if [ ! -f "$ARCHIVE" ]; then
  echo "downloading $URL" >&2
  curl -L --fail -o "$ARCHIVE" "$URL"
fi
if [ ! -d "$SRC_DIR" ]; then
  echo "extracting $ARCHIVE" >&2
  tar -C "$CACHE_DIR" -xzf "$ARCHIVE"
fi
if [ ! -x "$RUNNER" ]; then
  echo "configuring protobuf conformance runner" >&2
  if [ ! -f "$BUILD_DIR/CMakeCache.txt" ]; then
    cmake -S "$SRC_DIR" -B "$BUILD_DIR" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -Dprotobuf_BUILD_CONFORMANCE=ON \
    -Dprotobuf_BUILD_TESTS=OFF \
    -Dprotobuf_BUILD_EXAMPLES=OFF \
    -Dprotobuf_BUILD_PROTOC_BINARIES=ON \
    -Dprotobuf_BUILD_LIBPROTOC=ON \
    -Dprotobuf_INSTALL=OFF \
    -Dprotobuf_FORCE_FETCH_DEPENDENCIES="${PROTOBUF_FORCE_FETCH_DEPENDENCIES:-ON}" \
    -Dprotobuf_LOCAL_DEPENDENCIES_ONLY=OFF \
    1>&2
  fi
  echo "building conformance_test_runner" >&2
  cmake --build "$BUILD_DIR" --target conformance_test_runner 1>&2
fi
if [ ! -f "$DESC" ]; then
  PROTOC="$BUILD_DIR/protoc"
  if [ ! -x "$PROTOC" ]; then
    for candidate in "$BUILD_DIR"/protoc-*; do
      if [ -x "$candidate" ]; then
        PROTOC="$candidate"
        break
      fi
    done
  fi
  if [ ! -x "$PROTOC" ]; then
    if command -v protoc >/dev/null 2>&1; then
      PROTOC="$(command -v protoc)"
    else
      echo "protoc not found; install protoc or enable protobuf_BUILD_PROTOC_BINARIES" >&2
      exit 2
    fi
  fi
  echo "building conformance descriptor set" >&2
  mkdir -p "$(dirname "$DESC")"
  "$PROTOC" \
    --descriptor_set_out="$DESC" \
    --include_imports \
    --proto_path="$SRC_DIR" \
    --proto_path="$SRC_DIR/src" \
    "$SRC_DIR/src/google/protobuf/test_messages_proto2.proto" \
    "$SRC_DIR/src/google/protobuf/test_messages_proto3.proto" \
    "$SRC_DIR/editions/golden/test_messages_proto2_editions.proto" \
    "$SRC_DIR/editions/golden/test_messages_proto3_editions.proto" \
    "$SRC_DIR/conformance/conformance.proto"
fi
printf '%s\n' "$RUNNER"
printf '%s\n' "$DESC"
