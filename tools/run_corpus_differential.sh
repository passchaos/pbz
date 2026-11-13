#!/usr/bin/env sh
# Compare pbz's source parsing, strict option validation, and descriptor
# round-trip against the protoc release pinned by the conformance cache.
#
# Usage: tools/run_corpus_differential.sh
# Env:   PROTOBUF_CONFORMANCE_VERSION (default 36.2)
#        PBZ_CONFORMANCE_CACHE
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
VERSION="${PROTOBUF_CONFORMANCE_VERSION:-36.2}"
CACHE="${PBZ_CONFORMANCE_CACHE:-$ROOT/.zig-cache/pbz-conformance}"
SRC="$CACHE/protobuf-$VERSION"
BUILD="$CACHE/build-$VERSION"
if [ ! -d "$SRC" ] || [ ! -x "$BUILD/protoc" ] && [ ! -x "$BUILD/protoc-$VERSION" ]; then
  "$ROOT/tools/fetch_conformance_runner.sh" >/dev/null
fi
PROTOC="$BUILD/protoc"
if [ ! -x "$PROTOC" ]; then PROTOC="$BUILD/protoc-$VERSION"; fi
if [ ! -x "$PROTOC" ]; then
  echo "protoc for protobuf $VERSION not found in $BUILD" >&2
  exit 2
fi
TMP="$(mktemp -d "${TMPDIR:-/tmp}/pbz-corpus-differential.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

echo "== building differential tool ==" >&2
zig build-exe -O Debug --dep pbz -Mroot="$ROOT/tools/corpus_differential.zig" -Mpbz="$ROOT/src/root.zig" -femit-bin="$TMP/pbz-corpus-differential"

( cd "$SRC" && find src editions -name '*.proto' | sort ) > "$TMP/files.txt"

echo "== protoc accept/reject ==" >&2
: > "$TMP/protoc.txt"
while IFS= read -r f; do
  if ( cd "$SRC" && "$PROTOC" -I src -I . --descriptor_set_out="$TMP/one.desc" "$f" >/dev/null 2>&1 ); then
    printf 'OK\t%s\n' "$f" >> "$TMP/protoc.txt"
  else
    printf 'ERR\t%s\n' "$f" >> "$TMP/protoc.txt"
  fi
done < "$TMP/files.txt"

echo "== pbz parse and strict load ==" >&2
"$TMP/pbz-corpus-differential" parse "$SRC" "$TMP/files.txt" > "$TMP/parse.txt" 2>&1 || true
"$TMP/pbz-corpus-differential" strict "$SRC" "$TMP/files.txt" > "$TMP/strict.txt" 2>&1 || true

echo "== descriptor round-trip ==" >&2
: > "$TMP/roundtrip-errors.txt"
: > "$TMP/roundtrip-diffs.txt"
while IFS="$(printf '\t')" read -r result f; do
  [ "$result" = "OK" ] || continue
  ( cd "$SRC" && "$PROTOC" -I src -I . --include_imports --descriptor_set_out="$TMP/in.desc" "$f" >/dev/null 2>&1 ) || continue
  if ! "$TMP/pbz-corpus-differential" roundtrip "$TMP/in.desc" "$TMP/out.desc" >/dev/null 2>&1; then
    printf '%s\n' "$f" >> "$TMP/roundtrip-errors.txt"
    continue
  fi
  ( cd "$SRC" && "$PROTOC" -I src --decode=google.protobuf.FileDescriptorSet src/google/protobuf/descriptor.proto < "$TMP/in.desc" > "$TMP/in.txt" 2>/dev/null )
  ( cd "$SRC" && "$PROTOC" -I src --decode=google.protobuf.FileDescriptorSet src/google/protobuf/descriptor.proto < "$TMP/out.desc" > "$TMP/out.txt" 2>/dev/null )
  python3 - "$TMP/in.txt" "$TMP/out.txt" <<'PY' || printf '%s\n' "$f" >> "$TMP/roundtrip-diffs.txt"
import re, sys
def norm(path):
    s = open(path).read()
    prev = None
    while prev != s:
        prev = s
        s = re.sub(r'(?m)^(\s*)features \{\n\s*\}\n', '', s)
        s = re.sub(r'(?m)^(\s*)options \{\n\s*\}\n', '', s)
    return s
sys.exit(0 if norm(sys.argv[1]) == norm(sys.argv[2]) else 1)
PY
done < "$TMP/protoc.txt"

python3 - "$TMP" <<'PY'
import sys
tmp = sys.argv[1]

def load(name):
    out = {}
    for line in open(f"{tmp}/{name}"):
        parts = line.rstrip("\n").split("\t")
        if len(parts) < 2:
            continue
        path = parts[1]
        if path.startswith("src/"):
            path = path[4:]
        out[path] = parts[0]
    return out

protoc = load("protoc.txt")
parse = load("parse.txt")
strict = load("strict.txt")
parse_false = sorted(p for p in protoc if protoc[p] == "OK" and parse.get(p) == "ERR")
strict_false = sorted(p for p in protoc if protoc[p] == "OK" and strict.get(p) == "ERR")
strict_extra = sorted(p for p in protoc if protoc[p] == "ERR" and strict.get(p) == "OK")
rt_errors = [l.strip() for l in open(f"{tmp}/roundtrip-errors.txt") if l.strip()]
rt_diffs = [l.strip() for l in open(f"{tmp}/roundtrip-diffs.txt") if l.strip()]

print(f"files: {len(protoc)}  protoc OK: {sum(1 for v in protoc.values() if v == 'OK')}")
print(f"parser false rejections: {len(parse_false)}")
for p in parse_false:
    print(f"  parse rejected, protoc accepted: {p}")
print(f"strict false rejections: {len(strict_false)}")
for p in strict_false:
    print(f"  strict rejected, protoc accepted: {p}")
print(f"strict extra acceptances: {len(strict_extra)}")
for p in strict_extra:
    print(f"  strict accepted, protoc rejected: {p}")
print(f"descriptor round-trip errors: {len(rt_errors)}")
for p in rt_errors:
    print(f"  round-trip failed: {p}")
print(f"descriptor round-trip text differences: {len(rt_diffs)}")
for p in rt_diffs:
    print(f"  round-trip differs: {p}")
failed = parse_false or strict_false or strict_extra or rt_errors or rt_diffs
sys.exit(1 if failed else 0)
PY
