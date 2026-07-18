#!/usr/bin/env python3
"""Smoke-test pbz-conformance without the upstream conformance-test-runner."""
from __future__ import annotations

import argparse
import os
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def key(number: int, wire_type: int) -> bytes:
    return varint((number << 3) | wire_type)


def varint(value: int) -> bytes:
    out = bytearray()
    while value >= 0x80:
        out.append((value & 0x7F) | 0x80)
        value >>= 7
    out.append(value)
    return bytes(out)


def field_varint(number: int, value: int) -> bytes:
    return key(number, 0) + varint(value)


def field_bytes(number: int, value: bytes) -> bytes:
    return key(number, 2) + varint(len(value)) + value


def run_framed(exe: list[str], request: bytes) -> bytes:
    framed_request = struct.pack("<I", len(request)) + request
    proc = subprocess.run(
        exe,
        input=framed_request,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )
    if len(proc.stdout) < 4:
        raise AssertionError(f"missing response frame, stderr={proc.stderr!r}")
    (response_len,) = struct.unpack("<I", proc.stdout[:4])
    response = proc.stdout[4:]
    if len(response) != response_len:
        raise AssertionError(f"bad response length {len(response)} != {response_len}, stderr={proc.stderr!r}")
    return response


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--exe",
        help="path to a prebuilt pbz-conformance executable; when omitted the script builds it first",
    )
    args = parser.parse_args(argv)

    with tempfile.TemporaryDirectory(prefix="pbz-conformance-") as tmp:
        tmp_path = Path(tmp)
        proto = tmp_path / "smoke.proto"
        descriptor = tmp_path / "smoke.desc"
        proto.write_text('syntax = "proto3"; package demo; message Event { int32 id = 1; }\n', encoding="utf-8")
        subprocess.run(
            [
                "protoc",
                f"--descriptor_set_out={descriptor}",
                f"--proto_path={tmp_path}",
                str(proto),
            ],
            check=True,
        )
        if args.exe:
            conformance_exe = Path(args.exe).resolve()
        else:
            subprocess.run(["zig", "build", "-Doptimize=ReleaseFast"], cwd=ROOT, check=True)
            conformance_exe = ROOT / "zig-out/bin/pbz-conformance"

        exe = [str(conformance_exe), "--descriptor_set", str(descriptor)]

        # ConformanceRequest:
        #   json_payload = {"id":7}
        #   requested_output_format = PROTOBUF (1)
        #   message_type = demo.Event
        #   test_category = JSON_TEST (2)
        request = b"".join(
            [
                field_bytes(2, b'{"id":7}'),
                field_varint(3, 1),
                field_bytes(4, b"demo.Event"),
                field_varint(5, 2),
            ]
        )
        response = run_framed(exe, request)
        # ConformanceResponse.protobuf_payload is field 3, length-delimited.
        expected = field_bytes(3, field_varint(1, 7))
        if response != expected:
            raise AssertionError(f"unexpected protobuf response {response!r}, expected {expected!r}")

        # TEXT_FORMAT is WireFormat value 4 in upstream conformance.proto.
        text_request = b"".join(
            [
                field_bytes(2, b'{"id":7}'),
                field_varint(3, 4),
                field_bytes(4, b"demo.Event"),
                field_varint(5, 2),
            ]
        )
        text_response = run_framed(exe, text_request)
        expected_text = field_bytes(8, b"id: 7\n")
        if text_response != expected_text:
            raise AssertionError(f"unexpected text response {text_response!r}, expected {expected_text!r}")
    print("pbz-conformance smoke test passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
