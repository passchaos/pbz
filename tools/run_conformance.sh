#!/usr/bin/env sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
RUNNER="${CONFORMANCE_TEST_RUNNER:-conformance-test-runner}"
DESCRIPTOR_SET="${PBZ_CONFORMANCE_DESCRIPTOR_SET:-}"
if [ -z "$DESCRIPTOR_SET" ]; then
  echo "PBZ_CONFORMANCE_DESCRIPTOR_SET must point to a FileDescriptorSet used by the upstream conformance runner" >&2
  exit 2
fi
if ! command -v "$RUNNER" >/dev/null 2>&1; then
  echo "conformance-test-runner not found; set CONFORMANCE_TEST_RUNNER=/path/to/runner" >&2
  exit 2
fi
zig build -Doptimize=ReleaseFast >/dev/null
exec "$RUNNER" --enforce_recommended --failure_list /dev/null "$ROOT/zig-out/bin/pbz-conformance --descriptor_set $DESCRIPTOR_SET"
