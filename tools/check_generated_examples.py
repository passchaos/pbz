#!/usr/bin/env python3
"""Verify checked-in generated example modules match protoc-gen-pbz output."""

from __future__ import annotations

import argparse
import difflib
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
PROTO_DIR = REPO_ROOT / "examples" / "proto"
GENERATED_DIR = REPO_ROOT / "examples" / "generated"
DIFF_LINE_LIMIT = 240


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--plugin",
        required=True,
        help="Path to the protoc-gen-pbz executable to validate against.",
    )
    parser.add_argument(
        "--protoc",
        default="protoc",
        help="protoc executable name/path (default: protoc).",
    )
    return parser.parse_args()


def output_name_for_proto(proto_rel: Path) -> Path:
    """Mirror pbz's default output_suffix=.pb.zig, strip_proto_ext=true naming."""

    rel = proto_rel.as_posix()
    if rel.endswith(".proto"):
        rel = rel[: -len(".proto")]
    return Path(rel + ".pb.zig")


def checked_in_generated_files() -> set[Path]:
    return {path.relative_to(GENERATED_DIR) for path in GENERATED_DIR.rglob("*.pb.zig")}


def proto_files() -> list[Path]:
    return sorted(path.relative_to(PROTO_DIR) for path in PROTO_DIR.rglob("*.proto"))


def unified_diff(expected_path: Path, actual_path: Path) -> list[str]:
    expected = expected_path.read_text().splitlines(keepends=True)
    actual = actual_path.read_text().splitlines(keepends=True)
    lines = list(
        difflib.unified_diff(
            expected,
            actual,
            fromfile=str(expected_path.relative_to(REPO_ROOT)),
            tofile=f"regenerated/{actual_path.relative_to(actual_path.parents[1])}",
        )
    )
    if len(lines) > DIFF_LINE_LIMIT:
        return lines[:DIFF_LINE_LIMIT] + [f"... diff truncated after {DIFF_LINE_LIMIT} lines ...\n"]
    return lines


def main() -> int:
    args = parse_args()
    plugin = Path(args.plugin)
    if not plugin.exists():
        print(f"error: protoc-gen-pbz plugin not found: {plugin}", file=sys.stderr)
        return 2
    if shutil.which(args.protoc) is None and not Path(args.protoc).exists():
        print(f"error: protoc executable not found: {args.protoc}", file=sys.stderr)
        return 2

    protos = proto_files()
    expected_outputs = {output_name_for_proto(proto) for proto in protos}
    checked_in_outputs = checked_in_generated_files()
    missing_checked_in = sorted(expected_outputs - checked_in_outputs)
    extra_checked_in = sorted(checked_in_outputs - expected_outputs)
    if missing_checked_in or extra_checked_in:
        for path in missing_checked_in:
            print(f"missing checked-in generated file for proto: examples/generated/{path}", file=sys.stderr)
        for path in extra_checked_in:
            print(f"extra checked-in generated file without matching proto: examples/generated/{path}", file=sys.stderr)
        return 1

    with tempfile.TemporaryDirectory(prefix="pbz-generated-examples-") as tmp_name:
        tmp = Path(tmp_name)
        cmd = [
            args.protoc,
            f"--plugin=protoc-gen-pbz={plugin}",
            f"--pbz_out={tmp}",
            f"--proto_path={PROTO_DIR}",
            *(proto.as_posix() for proto in protos),
        ]
        subprocess.run(cmd, cwd=REPO_ROOT, check=True)

        failed = False
        for rel in sorted(expected_outputs):
            checked_in = GENERATED_DIR / rel
            regenerated = tmp / rel
            if not regenerated.exists():
                print(f"regeneration did not produce: {rel}", file=sys.stderr)
                failed = True
                continue
            if checked_in.read_bytes() != regenerated.read_bytes():
                failed = True
                print(f"generated example drift detected: examples/generated/{rel}", file=sys.stderr)
                sys.stderr.writelines(unified_diff(checked_in, regenerated))

        if failed:
            print(
                "checked-in generated examples are stale; regenerate examples/generated/*.pb.zig with protoc-gen-pbz",
                file=sys.stderr,
            )
            return 1

    print(f"checked {len(expected_outputs)} generated example file(s); no drift")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
