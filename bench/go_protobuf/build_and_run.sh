#!/usr/bin/env sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
cd "$ROOT"
GEN_GO="$(command -v protoc-gen-go || true)"
if [ -z "$GEN_GO" ] && [ -x "$HOME/go/bin/protoc-gen-go" ]; then
  GEN_GO="$HOME/go/bin/protoc-gen-go"
fi
if [ -z "$GEN_GO" ]; then
  echo "protoc-gen-go not found; install with: go install google.golang.org/protobuf/cmd/protoc-gen-go@v1.34.2" >&2
  exit 1
fi
PATH="$(dirname "$GEN_GO"):$PATH" protoc \
  --go_out=bench/go_protobuf \
  --go_opt=module=github.com/pbz/bench \
  --proto_path=bench/go_protobuf \
  bench/go_protobuf/person.proto
(cd bench/go_protobuf && go mod tidy && go run .)
