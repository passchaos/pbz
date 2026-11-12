#!/usr/bin/env python3
"""Smoke-test the pbz encode/decode/convert/describe CLI."""
from __future__ import annotations

import argparse
import json
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exe", required=True, help="path to the built pbz CLI executable")
    args = parser.parse_args(argv)

    exe = Path(args.exe).resolve()
    with tempfile.TemporaryDirectory(prefix="pbz-cli-") as tmp_name:
        tmp = Path(tmp_name)
        descriptor = tmp / "person.desc"
        subprocess.run(
            [
                "protoc",
                f"--descriptor_set_out={descriptor}",
                "--include_imports",
                f"--proto_path={ROOT / 'examples' / 'proto'}",
                str(ROOT / "examples" / "proto" / "person.proto"),
            ],
            cwd=ROOT,
            check=True,
        )

        text_input = (
            b'id: 7\n'
            b'name: "Zig"\n'
            b'scores: 10\n'
            b'scores: 20\n'
            b'counts { key: "red" value: 1 }\n'
        )
        binary = subprocess.run(
            [str(exe), "encode", "--descriptor-set", str(descriptor), "--type", "demo.Person"],
            input=text_input,
            stdout=subprocess.PIPE,
            check=True,
        ).stdout
        if not binary:
            raise AssertionError("encode produced no output")

        json_bytes = subprocess.run(
            [str(exe), "decode", "--descriptor-set", str(descriptor), "--type", "demo.Person", "--json"],
            input=binary,
            stdout=subprocess.PIPE,
            check=True,
        ).stdout
        parsed = json.loads(json_bytes)
        if parsed.get("id") != 7 or parsed.get("name") != "Zig":
            raise AssertionError(f"unexpected decoded JSON: {parsed!r}")
        if parsed.get("scores") != [10, 20] or parsed.get("counts") != {"red": 1}:
            raise AssertionError(f"unexpected decoded fields: {parsed!r}")

        text_bytes = subprocess.run(
            [
                str(exe),
                "convert",
                "--descriptor-set",
                str(descriptor),
                "--type",
                "demo.Person",
                "--from",
                "json",
                "--to",
                "text",
            ],
            input=b'{"id":7,"name":"Zig"}',
            stdout=subprocess.PIPE,
            check=True,
        ).stdout
        if b"id: 7" not in text_bytes or b'name: "Zig"' not in text_bytes:
            raise AssertionError(f"unexpected converted text: {text_bytes!r}")

        described = subprocess.run(
            [str(exe), "describe", "--descriptor-set", str(descriptor), "--type", "demo.Person"],
            stdout=subprocess.PIPE,
            check=True,
        ).stdout
        if b"message demo.Person" not in described or b"map<string, int32>" not in described:
            raise AssertionError(f"unexpected describe output: {described!r}")

    print("pbz CLI smoke test passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
