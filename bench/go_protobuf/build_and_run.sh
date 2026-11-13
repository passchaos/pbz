#!/usr/bin/env sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
cd "$ROOT"
# google.golang.org/protobuf v1.36 requires Go >= 1.23. Pin the toolchain used
# for the comparison so it does not silently follow whichever Go happens to be
# installed; override with PBZ_GO_TOOLCHAIN.
GOTOOLCHAIN="${PBZ_GO_TOOLCHAIN:-go1.27.4}"
export GOTOOLCHAIN
GEN_GO="$(command -v protoc-gen-go || true)"
if [ -z "$GEN_GO" ] && [ -x "$HOME/go/bin/protoc-gen-go" ]; then
  GEN_GO="$HOME/go/bin/protoc-gen-go"
fi
if [ -z "$GEN_GO" ]; then
  echo "protoc-gen-go not found; install with: go install google.golang.org/protobuf/cmd/protoc-gen-go@v1.36.12" >&2
  exit 1
fi
PATH="$(dirname "$GEN_GO"):$PATH" protoc \
  --go_out=bench/go_protobuf \
  --go_opt=module=github.com/pbz/bench \
  --proto_path=bench/go_protobuf \
  bench/go_protobuf/person.proto
(cd bench/go_protobuf && go mod tidy && go run .)
