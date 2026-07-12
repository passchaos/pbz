#!/usr/bin/env sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
RUNNER="${CONFORMANCE_TEST_RUNNER:-}"
DESCRIPTOR_SET="${PBZ_CONFORMANCE_DESCRIPTOR_SET:-}"
OUTPUT_DIR="${PBZ_CONFORMANCE_OUTPUT_DIR:-$ROOT/.zig-cache/pbz-conformance/results}"
if [ -z "$RUNNER" ] || [ -z "$DESCRIPTOR_SET" ]; then
  FETCH_OUTPUT="$($ROOT/tools/fetch_conformance_runner.sh)"
  RUNNER="${RUNNER:-$(printf '%s\n' "$FETCH_OUTPUT" | sed -n '1p')}"
  DESCRIPTOR_SET="${DESCRIPTOR_SET:-$(printf '%s\n' "$FETCH_OUTPUT" | sed -n '2p')}"
fi
if command -v "$RUNNER" >/dev/null 2>&1; then
  RUNNER="$(command -v "$RUNNER")"
elif [ ! -x "$RUNNER" ]; then
  echo "conformance-test-runner not found or not executable: $RUNNER" >&2
  exit 2
fi
if [ ! -f "$DESCRIPTOR_SET" ]; then
  echo "descriptor set not found: $DESCRIPTOR_SET" >&2
  exit 2
fi
mkdir -p "$OUTPUT_DIR"
zig build -Doptimize=ReleaseFast >/dev/null
exec "$RUNNER" \
  --enforce_recommended \
  --output_dir "$OUTPUT_DIR" \
  --failure_list /dev/null \
  --text_format_failure_list /dev/null \
  "$ROOT/zig-out/bin/pbz-conformance" \
  --descriptor_set "$DESCRIPTOR_SET"
