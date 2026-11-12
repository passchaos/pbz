#!/usr/bin/env sh
# Generate Zig modules for the upstream conformance test messages.
#
# Usage: generate_conformance_messages.sh PROTOC_GEN_PBZ OUTPUT_DIR
#
# Requires the conformance source/build cache created by
# tools/fetch_conformance_runner.sh; this script fetches it when missing.
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PLUGIN="$1"
OUT="$2"
case "$PLUGIN" in
  /*) ;;
  *) PLUGIN="$(pwd)/$PLUGIN" ;;
esac
case "$OUT" in
  /*) ;;
  *) OUT="$(pwd)/$OUT" ;;
esac
VERSION="${PROTOBUF_CONFORMANCE_VERSION:-35.1}"
CACHE="${PBZ_CONFORMANCE_CACHE:-$ROOT/.zig-cache/pbz-conformance}"
SRC="$CACHE/protobuf-$VERSION"
BUILD="$CACHE/build-$VERSION"

if [ ! -d "$SRC" ] || [ ! -d "$BUILD" ]; then
  "$ROOT/tools/fetch_conformance_runner.sh" >/dev/null
fi

PROTOC="$BUILD/protoc"
if [ ! -x "$PROTOC" ]; then
  PROTOC="$BUILD/protoc-$VERSION"
fi
if [ ! -x "$PROTOC" ]; then
  echo "protoc for protobuf $VERSION not found in $BUILD" >&2
  exit 2
fi

mkdir -p "$OUT"
(
  cd "$SRC"
  "$PROTOC" \
    --plugin=protoc-gen-pbz="$PLUGIN" \
    --pbz_out="$OUT" \
    --proto_path=src \
    --proto_path=. \
    google/protobuf/test_messages_proto3.proto \
    google/protobuf/test_messages_proto2.proto \
    editions/golden/test_messages_proto2_editions.proto \
    editions/golden/test_messages_proto3_editions.proto \
    google/protobuf/any.proto \
    google/protobuf/duration.proto \
    google/protobuf/empty.proto \
    google/protobuf/field_mask.proto \
    google/protobuf/struct.proto \
    google/protobuf/timestamp.proto \
    google/protobuf/wrappers.proto
)

cat > "$OUT/root.zig" <<'ZIG'
pub const proto3 = @import("google/protobuf/test_messages_proto3.pb.zig");
pub const proto2 = @import("google/protobuf/test_messages_proto2.pb.zig");
pub const editions_proto2 = @import("editions/golden/test_messages_proto2_editions.pb.zig");
pub const editions_proto3 = @import("editions/golden/test_messages_proto3_editions.pb.zig");
ZIG
