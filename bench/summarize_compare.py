#!/usr/bin/env python3
"""Summarize pbz cross-language benchmark output.

Usage:
  bench/run_compare.sh 2>&1 | tee /tmp/pbz-compare.log
  python3 bench/summarize_compare.py /tmp/pbz-compare.log

The script parses the ``ns/op`` lines emitted by ``bench/run_compare.sh`` and
compares the fastest relevant public pbz path against each available
cross-language implementation for the same workload. It is intentionally a
summary/audit tool: by default it exits successfully even when pbz loses a row or
when a baseline is missing; use ``--fail-on-loss`` for CI-style gating.
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path

LINE_RE = re.compile(r"^(?P<name>[^:]+): best of \d+ x \d+ iters, (?:\d+ bytes/iter, )?(?P<ns>[0-9.]+) ns/op")

# Keep this in sync with bench/COVERAGE.md so the self-test catches accidental
# benchmark-matrix drift instead of silently weakening the comparison evidence.
EXPECTED_WORKLOAD_COUNT = 404


@dataclass(frozen=True)
class Workload:
    name: str
    pbz: tuple[str, ...]
    baselines: dict[str, tuple[str, ...]]


def json_workload_pair(label: str) -> tuple[Workload, Workload]:
    """Return direct pbz-vs-C++/Go JSON stringify and parse workloads.

    Most well-known-type JSON rows follow the same public row-name pattern in
    every implementation.  Keeping that convention in one helper makes future
    WKT coverage additions less error-prone: the self-test still guards the
    expected matrix size, while the helper avoids copy/paste drift between
    stringify and parse rows.
    """

    return (
        Workload(
            f"{label} JSON stringify",
            (f"pbz {label} JSON stringify",),
            {
                "c++ protobuf": (f"c++ protobuf {label} JSON stringify",),
                "go protobuf": (f"go protobuf {label} JSON stringify",),
            },
        ),
        Workload(
            f"{label} JSON parse",
            (f"pbz {label} JSON parse",),
            {
                "c++ protobuf": (f"c++ protobuf {label} JSON parse",),
                "go protobuf": (f"go protobuf {label} JSON parse",),
            },
        ),
    )


def json_parse_workload(label: str) -> Workload:
    """Return a parse-only JSON workload for legal non-canonical inputs.

    Some protobuf JSON forms are accepted on input but canonicalized on output
    (for example Timestamp timezone offsets). These should not be represented as
    stringify/parse pairs because the stringify side cannot preserve the
    non-canonical spelling being tested.
    """

    return Workload(
        f"{label} JSON parse",
        (f"pbz {label} JSON parse",),
        {
            "c++ protobuf": (f"c++ protobuf {label} JSON parse",),
            "go protobuf": (f"go protobuf {label} JSON parse",),
        },
    )


def json_sample_pair(
    label: str,
    bytes_per_iter: int,
    stringify_ns: tuple[float, float, float],
    parse_ns: tuple[float, float, float],
) -> tuple[str, ...]:
    """Return self-test benchmark lines for a direct JSON workload pair."""

    pbz_stringify, cpp_stringify, go_stringify = stringify_ns
    pbz_parse, cpp_parse, go_parse = parse_ns
    return (
        benchmark_line(f"pbz {label} JSON stringify", bytes_per_iter, pbz_stringify),
        benchmark_line(f"c++ protobuf {label} JSON stringify", bytes_per_iter, cpp_stringify),
        benchmark_line(f"go protobuf {label} JSON stringify", bytes_per_iter, go_stringify),
        benchmark_line(f"pbz {label} JSON parse", bytes_per_iter, pbz_parse),
        benchmark_line(f"c++ protobuf {label} JSON parse", bytes_per_iter, cpp_parse),
        benchmark_line(f"go protobuf {label} JSON parse", bytes_per_iter, go_parse),
    )


def benchmark_line(name: str, bytes_per_iter: int, ns: float) -> str:
    return f"{name}: best of 3 x 10 iters, {bytes_per_iter} bytes/iter, {ns:.2f} ns/op, 1 ops/s, 1 MiB/s"


# Self-test WKT rows intentionally mirror the production naming convention used
# by json_workload_pair().  Adding a future direct WKT JSON workload should only
# require one extra tuple here plus the production workload declaration.
JSON_SELF_TEST_SPECS: tuple[tuple[str, int, tuple[float, float, float], tuple[float, float, float]], ...] = (
    ("Any WKT", 73, (60.0, 300.0, 350.0), (80.0, 400.0, 500.0)),
    ("Any MicroDuration WKT", 76, (60.0, 300.0, 350.0), (80.0, 400.0, 500.0)),
    ("Any NanoDuration WKT", 79, (60.0, 300.0, 350.0), (80.0, 400.0, 500.0)),
    ("Any NegativeDuration WKT", 74, (60.0, 300.0, 350.0), (80.0, 400.0, 500.0)),
    ("Any FractionalNegativeDuration WKT", 74, (60.0, 300.0, 350.0), (80.0, 400.0, 500.0)),
    ("Any MaxDuration WKT", 80, (60.0, 300.0, 350.0), (80.0, 400.0, 500.0)),
    ("Any MinDuration WKT", 81, (60.0, 300.0, 350.0), (80.0, 400.0, 500.0)),
    ("Any ZeroDuration WKT", 69, (60.0, 300.0, 350.0), (80.0, 400.0, 500.0)),
    ("Any FieldMask WKT", 87, (100.0, 600.0, 550.0), (150.0, 850.0, 800.0)),
    ("Any EmptyFieldMask WKT", 68, (80.0, 450.0, 400.0), (110.0, 700.0, 650.0)),
    ("Any Timestamp WKT", 92, (100.0, 600.0, 550.0), (150.0, 850.0, 800.0)),
    ("Any Micro Timestamp WKT", 95, (100.0, 600.0, 550.0), (150.0, 850.0, 800.0)),
    ("Any Nano Timestamp WKT", 98, (100.0, 600.0, 550.0), (150.0, 850.0, 800.0)),
    ("Any PreEpoch Timestamp WKT", 88, (100.0, 600.0, 550.0), (150.0, 850.0, 800.0)),
    ("Any Max Timestamp WKT", 98, (100.0, 600.0, 550.0), (150.0, 850.0, 800.0)),
    ("Any Min Timestamp WKT", 88, (100.0, 600.0, 550.0), (150.0, 850.0, 800.0)),
    ("Any Empty WKT", 53, (80.0, 450.0, 400.0), (110.0, 700.0, 650.0)),
    ("Any Struct WKT", 121, (120.0, 1000.0, 900.0), (180.0, 1200.0, 1100.0)),
    ("Any EmptyStruct WKT", 65, (80.0, 450.0, 400.0), (110.0, 700.0, 650.0)),
    ("Any Value WKT", 120, (120.0, 1000.0, 900.0), (180.0, 1200.0, 1100.0)),
    ("Any NullValue WKT", 66, (80.0, 450.0, 400.0), (110.0, 700.0, 650.0)),
    ("Any StringScalarValue WKT", 67, (90.0, 500.0, 450.0), (120.0, 700.0, 650.0)),
    ("Any EmptyStringScalarValue WKT", 64, (80.0, 450.0, 400.0), (110.0, 700.0, 650.0)),
    ("Any NumberValue WKT", 65, (90.0, 500.0, 450.0), (140.0, 750.0, 700.0)),
    ("Any NegativeNumberValue WKT", 66, (90.0, 500.0, 450.0), (140.0, 750.0, 700.0)),
    ("Any ZeroNumberValue WKT", 63, (80.0, 450.0, 400.0), (110.0, 700.0, 650.0)),
    ("Any BoolScalarValue WKT", 66, (80.0, 450.0, 400.0), (110.0, 700.0, 650.0)),
    ("Any FalseBoolScalarValue WKT", 67, (80.0, 450.0, 400.0), (110.0, 700.0, 650.0)),
    ("Any ListKindValue WKT", 102, (120.0, 1000.0, 900.0), (180.0, 1200.0, 1100.0)),
    ("Any EmptyStructKindValue WKT", 64, (80.0, 450.0, 400.0), (110.0, 700.0, 650.0)),
    ("Any EmptyListKindValue WKT", 64, (80.0, 450.0, 400.0), (110.0, 700.0, 650.0)),
    ("Any DoubleValue WKT", 72, (90.0, 500.0, 450.0), (140.0, 800.0, 750.0)),
    ("Any NegativeDoubleValue WKT", 73, (90.0, 500.0, 450.0), (140.0, 800.0, 750.0)),
    ("Any ZeroDoubleValue WKT", 69, (90.0, 500.0, 450.0), (140.0, 800.0, 750.0)),
    ("Any DoubleValue NaN WKT", 73, (90.0, 500.0, 450.0), (140.0, 800.0, 750.0)),
    ("Any DoubleValue Infinity WKT", 78, (90.0, 500.0, 450.0), (140.0, 800.0, 750.0)),
    ("Any DoubleValue NegativeInfinity WKT", 79, (90.0, 500.0, 450.0), (140.0, 800.0, 750.0)),
    ("Any FloatValue WKT", 70, (90.0, 500.0, 450.0), (140.0, 800.0, 750.0)),
    ("Any NegativeFloatValue WKT", 71, (90.0, 500.0, 450.0), (140.0, 800.0, 750.0)),
    ("Any ZeroFloatValue WKT", 68, (90.0, 500.0, 450.0), (140.0, 800.0, 750.0)),
    ("Any FloatValue NaN WKT", 72, (90.0, 500.0, 450.0), (140.0, 800.0, 750.0)),
    ("Any FloatValue Infinity WKT", 77, (90.0, 500.0, 450.0), (140.0, 800.0, 750.0)),
    ("Any FloatValue NegativeInfinity WKT", 78, (90.0, 500.0, 450.0), (140.0, 800.0, 750.0)),
    ("Any Int64Value WKT", 85, (90.0, 500.0, 450.0), (140.0, 800.0, 750.0)),
    ("Any ZeroInt64Value WKT", 70, (90.0, 500.0, 450.0), (140.0, 800.0, 750.0)),
    ("Any NegativeInt64Value WKT", 86, (90.0, 500.0, 450.0), (140.0, 800.0, 750.0)),
    ("Any MinInt64Value WKT", 89, (90.0, 500.0, 450.0), (140.0, 800.0, 750.0)),
    ("Any MaxInt64Value WKT", 88, (90.0, 500.0, 450.0), (140.0, 800.0, 750.0)),
    ("Any UInt64Value WKT", 86, (90.0, 500.0, 450.0), (140.0, 800.0, 750.0)),
    ("Any ZeroUInt64Value WKT", 71, (90.0, 500.0, 450.0), (140.0, 800.0, 750.0)),
    ("Any MaxUInt64Value WKT", 90, (90.0, 500.0, 450.0), (140.0, 800.0, 750.0)),
    ("Any Int32Value WKT", 72, (90.0, 500.0, 450.0), (140.0, 800.0, 750.0)),
    ("Any ZeroInt32Value WKT", 68, (90.0, 500.0, 450.0), (140.0, 800.0, 750.0)),
    ("Any NegativeInt32Value WKT", 73, (90.0, 500.0, 450.0), (140.0, 800.0, 750.0)),
    ("Any MinInt32Value WKT", 78, (90.0, 500.0, 450.0), (140.0, 800.0, 750.0)),
    ("Any MaxInt32Value WKT", 77, (90.0, 500.0, 450.0), (140.0, 800.0, 750.0)),
    ("Any UInt32Value WKT", 73, (90.0, 500.0, 450.0), (140.0, 800.0, 750.0)),
    ("Any ZeroUInt32Value WKT", 69, (90.0, 500.0, 450.0), (140.0, 800.0, 750.0)),
    ("Any MaxUInt32Value WKT", 78, (90.0, 500.0, 450.0), (140.0, 800.0, 750.0)),
    ("Any BoolValue WKT", 70, (80.0, 450.0, 400.0), (110.0, 700.0, 650.0)),
    ("Any FalseBoolValue WKT", 71, (80.0, 450.0, 400.0), (110.0, 700.0, 650.0)),
    ("Any StringValue WKT", 75, (90.0, 500.0, 450.0), (120.0, 700.0, 650.0)),
    ("Any EmptyStringValue WKT", 70, (90.0, 500.0, 450.0), (120.0, 700.0, 650.0)),
    ("Any BytesValue WKT", 73, (90.0, 500.0, 450.0), (140.0, 750.0, 700.0)),
    ("Any EmptyBytesValue WKT", 69, (90.0, 500.0, 450.0), (140.0, 750.0, 700.0)),
    ("Nested Any WKT", 135, (140.0, 1500.0, 900.0), (200.0, 2200.0, 1400.0)),
    ("Duration", 8, (30.0, 200.0, 250.0), (35.0, 220.0, 260.0)),
    ("MicroDuration", 11, (30.0, 200.0, 250.0), (35.0, 220.0, 260.0)),
    ("NanoDuration", 14, (30.0, 200.0, 250.0), (35.0, 220.0, 260.0)),
    ("NegativeDuration", 9, (30.0, 200.0, 250.0), (35.0, 220.0, 260.0)),
    ("FractionalNegativeDuration", 9, (30.0, 200.0, 250.0), (35.0, 220.0, 260.0)),
    ("MaxDuration", 15, (30.0, 200.0, 250.0), (35.0, 220.0, 260.0)),
    ("MinDuration", 16, (30.0, 200.0, 250.0), (35.0, 220.0, 260.0)),
    ("ZeroDuration", 4, (30.0, 200.0, 250.0), (35.0, 220.0, 260.0)),
    ("FieldMask", 21, (40.0, 230.0, 270.0), (45.0, 240.0, 280.0)),
    ("EmptyFieldMask", 2, (30.0, 210.0, 240.0), (35.0, 220.0, 260.0)),
    ("Timestamp", 28, (55.0, 250.0, 300.0), (65.0, 260.0, 320.0)),
    ("Micro Timestamp", 29, (55.0, 250.0, 300.0), (65.0, 260.0, 320.0)),
    ("Nano Timestamp", 32, (55.0, 250.0, 300.0), (65.0, 260.0, 320.0)),
    ("PreEpoch Timestamp", 22, (55.0, 250.0, 300.0), (65.0, 260.0, 320.0)),
    ("Max Timestamp", 32, (55.0, 250.0, 300.0), (65.0, 260.0, 320.0)),
    ("Min Timestamp", 22, (55.0, 250.0, 300.0), (65.0, 260.0, 320.0)),
    ("Empty", 2, (20.0, 200.0, 180.0), (30.0, 210.0, 190.0)),
    ("Struct", 58, (90.0, 900.0, 800.0), (120.0, 1000.0, 900.0)),
    ("EmptyStruct", 2, (20.0, 200.0, 180.0), (30.0, 210.0, 190.0)),
    ("Value", 58, (90.0, 900.0, 800.0), (120.0, 1000.0, 900.0)),
    ("NullValue", 4, (20.0, 200.0, 180.0), (30.0, 210.0, 190.0)),
    ("StringScalarValue", 5, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("EmptyStringScalarValue", 2, (20.0, 200.0, 180.0), (30.0, 210.0, 190.0)),
    ("NumberValue", 3, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("NegativeNumberValue", 4, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("ZeroNumberValue", 1, (20.0, 200.0, 180.0), (30.0, 210.0, 190.0)),
    ("BoolScalarValue", 4, (20.0, 200.0, 180.0), (30.0, 210.0, 190.0)),
    ("FalseBoolScalarValue", 5, (20.0, 200.0, 180.0), (30.0, 210.0, 190.0)),
    ("ListKindValue", 40, (80.0, 850.0, 760.0), (110.0, 950.0, 850.0)),
    ("EmptyStructKindValue", 2, (20.0, 200.0, 180.0), (30.0, 210.0, 190.0)),
    ("EmptyListKindValue", 2, (20.0, 200.0, 180.0), (30.0, 210.0, 190.0)),
    ("ListValue", 40, (80.0, 850.0, 760.0), (110.0, 950.0, 850.0)),
    ("EmptyListValue", 2, (20.0, 200.0, 180.0), (30.0, 210.0, 190.0)),
    ("DoubleValue", 4, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("NegativeDoubleValue", 5, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("ZeroDoubleValue", 1, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("DoubleValue NaN", 5, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("DoubleValue Infinity", 10, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("DoubleValue NegativeInfinity", 11, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("FloatValue", 3, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("NegativeFloatValue", 4, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("ZeroFloatValue", 1, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("FloatValue NaN", 5, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("FloatValue Infinity", 10, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("FloatValue NegativeInfinity", 11, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("Int64Value", 18, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("ZeroInt64Value", 3, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("NegativeInt64Value", 19, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("MinInt64Value", 22, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("MaxInt64Value", 21, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("UInt64Value", 18, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("ZeroUInt64Value", 3, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("MaxUInt64Value", 22, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("Int32Value", 5, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("ZeroInt32Value", 1, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("NegativeInt32Value", 6, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("MinInt32Value", 11, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("MaxInt32Value", 10, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("UInt32Value", 5, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("ZeroUInt32Value", 1, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("MaxUInt32Value", 10, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("BoolValue", 4, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("FalseBoolValue", 5, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("StringValue", 7, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("EmptyStringValue", 2, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("BytesValue", 6, (35.0, 230.0, 250.0), (70.0, 240.0, 280.0)),
    ("EmptyBytesValue", 2, (35.0, 230.0, 250.0), (70.0, 240.0, 280.0)),
)


WORKLOADS: tuple[Workload, ...] = (
    Workload(
        "binary encode",
        (
            "generated binary encode",
            "generated binary writeToAssumeCapacity reuse",
            "generated binary encodeIntoAssumeCapacity buffer reuse",
            "generated binary trusted UTF-8 encodeIntoAssumeCapacity buffer reuse",
        ),
        {
            "rust prost": ("prost binary encode",),
            "rust quick-protobuf": ("quick-protobuf binary encode", "quick-protobuf binary encode reuse"),
            "c++ protobuf": (
                "c++ protobuf binary encode",
                "c++ protobuf binary encode reuse",
                "c++ protobuf binary SerializeToArray reuse",
            ),
            "go protobuf": ("go protobuf binary encode", "go protobuf binary encode reuse"),
        },
    ),
    Workload(
        "binary decode",
        ("generated binary decode", "generated binary decode reuse"),
        {
            "rust prost": ("prost binary decode",),
            "rust quick-protobuf": ("quick-protobuf binary decode",),
            "c++ protobuf": ("c++ protobuf binary decode", "c++ protobuf binary decode reuse"),
            "go protobuf": ("go protobuf binary decode",),
        },
    ),
    Workload(
        "unknown fields count by number",
        (
            "generated unknown fields count by number",
            "generated unknown field number sidecar count",
            "generated unknown field number run sidecar count",
            "dynamic unknown fields count by number",
            "dynamic unknown field number sidecar count",
            "dynamic unknown field number run sidecar count",
        ),
        {
            "c++ protobuf": ("c++ protobuf unknown fields count by number",),
        },
    ),
    Workload(
        "deterministic binary encode",
        (
            "generated deterministic binary encode",
            "generated deterministic binary encodeIntoAssumeCapacity buffer reuse",
        ),
        {
            "c++ protobuf": ("c++ protobuf deterministic binary encode reuse",),
            "go protobuf": ("go protobuf deterministic binary encode reuse",),
        },
    ),



    Workload(
        "scalarmix encode",
        (
            "generated scalarmix encode",
            "generated scalarmix writeToAssumeCapacity reuse",
            "generated scalarmix encodeIntoAssumeCapacity buffer reuse",
        ),
        {
            "rust prost": ("prost scalarmix encode",),
            "rust quick-protobuf": ("quick-protobuf scalarmix encode", "quick-protobuf scalarmix encode reuse"),
            "c++ protobuf": ("c++ protobuf scalarmix encode", "c++ protobuf scalarmix SerializeToArray reuse"),
            "go protobuf": ("go protobuf scalarmix encode", "go protobuf scalarmix encode reuse"),
        },
    ),
    Workload(
        "scalarmix decode",
        ("generated scalarmix decode", "generated scalarmix decode reuse", "generated scalarmix fast known-schema decode reuse"),
        {
            "rust prost": ("prost scalarmix decode",),
            "rust quick-protobuf": ("quick-protobuf scalarmix decode",),
            "c++ protobuf": ("c++ protobuf scalarmix decode", "c++ protobuf scalarmix decode reuse"),
            "go protobuf": ("go protobuf scalarmix decode",),
        },
    ),
    Workload(
        "textbytes encode",
        (
            "generated textbytes encode",
            "generated textbytes writeToAssumeCapacity reuse",
            "generated textbytes trusted UTF-8 writeToAssumeCapacity reuse",
            "generated textbytes encodeIntoAssumeCapacity buffer reuse",
            "generated textbytes trusted UTF-8 encodeIntoAssumeCapacity buffer reuse",
            "generated textbytes borrowed slices encode",
        ),
        {
            "rust prost": ("prost textbytes encode",),
            "rust quick-protobuf": ("quick-protobuf textbytes encode", "quick-protobuf textbytes encode reuse"),
            "c++ protobuf": (
                "c++ protobuf textbytes encode",
                "c++ protobuf textbytes encode reuse",
                "c++ protobuf textbytes SerializeToArray reuse",
            ),
            "go protobuf": ("go protobuf textbytes encode", "go protobuf textbytes encode reuse"),
        },
    ),
    Workload(
        "textbytes decode",
        ("generated textbytes decode", "generated textbytes decode reuse"),
        {
            "rust prost": ("prost textbytes decode",),
            "rust quick-protobuf": ("quick-protobuf textbytes decode",),
            "c++ protobuf": ("c++ protobuf textbytes decode", "c++ protobuf textbytes decode reuse"),
            "go protobuf": ("go protobuf textbytes decode",),
        },
    ),
    Workload(
        "largebytes encode",
        (
            "generated largebytes encode",
            "generated largebytes writeToAssumeCapacity reuse",
            "generated largebytes encodeIntoAssumeCapacity buffer reuse",
            "generated largebytes borrowed slices encode",
        ),
        {
            "rust prost": ("prost largebytes encode",),
            "rust quick-protobuf": ("quick-protobuf largebytes encode", "quick-protobuf largebytes encode reuse"),
            "c++ protobuf": (
                "c++ protobuf largebytes encode",
                "c++ protobuf largebytes encode reuse",
                "c++ protobuf largebytes SerializeToArray reuse",
            ),
            "go protobuf": ("go protobuf largebytes encode", "go protobuf largebytes encode reuse"),
        },
    ),
    Workload(
        "largebytes decode",
        ("generated largebytes decode", "generated largebytes decode reuse", "generated largebytes borrowed view decode"),
        {
            "rust prost": ("prost largebytes decode",),
            "rust quick-protobuf": ("quick-protobuf largebytes decode",),
            "c++ protobuf": ("c++ protobuf largebytes decode", "c++ protobuf largebytes decode reuse"),
            "go protobuf": ("go protobuf largebytes decode",),
        },
    ),
    Workload(
        "presencemix encode",
        (
            "generated presencemix encode",
            "generated presencemix writeToAssumeCapacity reuse",
            "generated presencemix encodeIntoAssumeCapacity buffer reuse",
            "generated presencemix trusted UTF-8 encodeIntoAssumeCapacity buffer reuse",
        ),
        {
            "rust prost": ("prost presencemix encode",),
            "rust quick-protobuf": ("quick-protobuf presencemix encode", "quick-protobuf presencemix encode reuse"),
            "c++ protobuf": (
                "c++ protobuf presencemix encode",
                "c++ protobuf presencemix encode reuse",
                "c++ protobuf presencemix SerializeToArray reuse",
            ),
            "go protobuf": ("go protobuf presencemix encode", "go protobuf presencemix encode reuse"),
        },
    ),
    Workload(
        "presencemix decode",
        ("generated presencemix decode", "generated presencemix decode reuse"),
        {
            "rust prost": ("prost presencemix decode",),
            "rust quick-protobuf": ("quick-protobuf presencemix decode",),
            "c++ protobuf": ("c++ protobuf presencemix decode", "c++ protobuf presencemix decode reuse"),
            "go protobuf": ("go protobuf presencemix decode",),
        },
    ),
    Workload(
        "complex encode",
        (
            "generated complex encode",
            "generated complex writeToAssumeCapacity reuse",
            "generated complex encodeIntoAssumeCapacity buffer reuse",
            "generated complex trusted UTF-8 encodeIntoAssumeCapacity buffer reuse",
        ),
        {
            "rust prost": ("prost complex encode",),
            "rust quick-protobuf": ("quick-protobuf complex encode", "quick-protobuf complex encode reuse"),
            "c++ protobuf": (
                "c++ protobuf complex encode",
                "c++ protobuf complex encode reuse",
                "c++ protobuf complex SerializeToArray reuse",
            ),
            "go protobuf": ("go protobuf complex encode", "go protobuf complex encode reuse"),
        },
    ),
    Workload(
        "complex decode",
        ("generated complex decode", "generated complex decode reuse"),
        {
            "rust prost": ("prost complex decode",),
            "rust quick-protobuf": ("quick-protobuf complex decode",),
            "c++ protobuf": ("c++ protobuf complex decode", "c++ protobuf complex decode reuse"),
            "go protobuf": ("go protobuf complex decode",),
        },
    ),


    Workload(
        "complex deterministic binary encode",
        (
            "generated complex deterministic binary encode",
            "generated complex deterministic binary encodeIntoAssumeCapacity buffer reuse",
        ),
        {
            "c++ protobuf": ("c++ protobuf complex deterministic binary encode reuse",),
            "go protobuf": ("go protobuf complex deterministic binary encode reuse",),
        },
    ),
    Workload(
        "complex JSON stringify",
        ("generated complex JSON stringify",),
        {
            "c++ protobuf": ("c++ protobuf complex JSON stringify", "c++ protobuf complex JSON stringify reuse"),
            "go protobuf": ("go protobuf complex JSON stringify",),
        },
    ),
    Workload(
        "complex JSON parse",
        ("generated complex JSON parse",),
        {
            "c++ protobuf": ("c++ protobuf complex JSON parse", "c++ protobuf complex JSON parse reuse"),
            "go protobuf": ("go protobuf complex JSON parse",),
        },
    ),
    Workload(
        "complex TextFormat format",
        ("generated complex TextFormat format",),
        {
            "c++ protobuf": ("c++ protobuf complex TextFormat format", "c++ protobuf complex TextFormat format reuse"),
            "go protobuf": ("go protobuf complex TextFormat format",),
        },
    ),
    Workload(
        "complex TextFormat parse",
        ("generated complex TextFormat parse",),
        {
            "c++ protobuf": ("c++ protobuf complex TextFormat parse", "c++ protobuf complex TextFormat parse reuse"),
            "go protobuf": ("go protobuf complex TextFormat parse",),
        },
    ),
    Workload(
        "packed int32 encode",
        (
            "generated packed encode",
            "generated packed writeToAssumeCapacity reuse",
            "generated packed encodeIntoAssumeCapacity buffer reuse",
        ),
        {
            "rust prost": ("prost packed encode",),
            "rust quick-protobuf": ("quick-protobuf packed encode", "quick-protobuf packed encode reuse"),
            "c++ protobuf": (
                "c++ protobuf packed encode",
                "c++ protobuf packed encode reuse",
                "c++ protobuf packed SerializeToArray reuse",
            ),
            "go protobuf": ("go protobuf packed encode", "go protobuf packed encode reuse"),
        },
    ),
    Workload(
        "packed int32 decode",
        (
            "generated packed decode",
            "generated packed fast known-schema decode reuse",
            "generated int32 packed iterator decode",
        ),
        {
            "rust prost": ("prost packed decode",),
            "rust quick-protobuf": ("quick-protobuf packed decode",),
            "c++ protobuf": ("c++ protobuf packed decode", "c++ protobuf packed decode reuse"),
            "go protobuf": ("go protobuf packed decode",),
        },
    ),
    Workload(
        "JSON stringify",
        ("generated JSON stringify",),
        {
            "c++ protobuf": ("c++ protobuf JSON stringify", "c++ protobuf JSON stringify reuse"),
            "go protobuf": ("go protobuf JSON stringify",),
        },
    ),
    Workload(
        "AlwaysPrint JSON stringify",
        ("generated AlwaysPrint JSON stringify",),
        {
            "c++ protobuf": ("c++ protobuf AlwaysPrint JSON stringify",),
            "go protobuf": ("go protobuf AlwaysPrint JSON stringify",),
        },
    ),
    Workload(
        "ProtoName JSON stringify",
        ("generated ProtoName JSON stringify",),
        {
            "c++ protobuf": ("c++ protobuf ProtoName JSON stringify",),
            "go protobuf": ("go protobuf ProtoName JSON stringify",),
        },
    ),
    Workload(
        "JSON parse",
        ("generated JSON parse",),
        {
            "c++ protobuf": ("c++ protobuf JSON parse", "c++ protobuf JSON parse reuse"),
            "go protobuf": ("go protobuf JSON parse",),
        },
    ),
    Workload(
        "MapKeySurrogate JSON parse",
        ("generated MapKeySurrogate JSON parse",),
        {
            "c++ protobuf": ("c++ protobuf MapKeySurrogate JSON parse",),
            "go protobuf": ("go protobuf MapKeySurrogate JSON parse",),
        },
    ),
    Workload(
        "NullFields JSON parse",
        ("generated NullFields JSON parse",),
        {
            "c++ protobuf": ("c++ protobuf NullFields JSON parse",),
            "go protobuf": ("go protobuf NullFields JSON parse",),
        },
    ),
    Workload(
        "OpenEnum JSON parse",
        ("generated OpenEnum JSON parse",),
        {
            "c++ protobuf": ("c++ protobuf OpenEnum JSON parse",),
            "go protobuf": ("go protobuf OpenEnum JSON parse",),
        },
    ),
    Workload(
        "EnumName JSON parse",
        ("generated EnumName JSON parse",),
        {
            "c++ protobuf": ("c++ protobuf EnumName JSON parse",),
            "go protobuf": ("go protobuf EnumName JSON parse",),
        },
    ),
    Workload(
        "ProtoName JSON parse",
        ("generated ProtoName JSON parse",),
        {
            "c++ protobuf": ("c++ protobuf ProtoName JSON parse",),
            "go protobuf": ("go protobuf ProtoName JSON parse",),
        },
    ),
    Workload(
        "IntExponent JSON parse",
        ("generated IntExponent JSON parse",),
        {
            "c++ protobuf": ("c++ protobuf IntExponent JSON parse",),
            "go protobuf": ("go protobuf IntExponent JSON parse",),
        },
    ),
    *json_workload_pair("Any WKT"),
    json_parse_workload("Any Duration Escape WKT"),
    json_parse_workload("Any PlusDuration WKT"),
    json_parse_workload("Any ShortFractionDuration WKT"),
    *json_workload_pair("Any MicroDuration WKT"),
    *json_workload_pair("Any NanoDuration WKT"),
    *json_workload_pair("Any NegativeDuration WKT"),
    *json_workload_pair("Any FractionalNegativeDuration WKT"),
    *json_workload_pair("Any MaxDuration WKT"),
    *json_workload_pair("Any MinDuration WKT"),
    *json_workload_pair("Any ZeroDuration WKT"),
    *json_workload_pair("Any FieldMask WKT"),
    json_parse_workload("Any FieldMask Escape WKT"),
    *json_workload_pair("Any EmptyFieldMask WKT"),
    *json_workload_pair("Any Timestamp WKT"),
    json_parse_workload("Any Timestamp Escape WKT"),
    json_parse_workload("Any ShortFraction Timestamp WKT"),
    *json_workload_pair("Any Micro Timestamp WKT"),
    *json_workload_pair("Any Nano Timestamp WKT"),
    json_parse_workload("Any Offset Timestamp WKT"),
    *json_workload_pair("Any PreEpoch Timestamp WKT"),
    *json_workload_pair("Any Max Timestamp WKT"),
    *json_workload_pair("Any Min Timestamp WKT"),
    *json_workload_pair("Any Empty WKT"),
    *json_workload_pair("Any Struct WKT"),
    json_parse_workload("Any Struct Escape WKT"),
    json_parse_workload("Any Struct NumberExponent WKT"),
    json_parse_workload("Any Struct Surrogate WKT"),
    json_parse_workload("Any Struct KeySurrogate WKT"),
    *json_workload_pair("Any EmptyStruct WKT"),
    *json_workload_pair("Any Value WKT"),
    json_parse_workload("Any Value Escape WKT"),
    json_parse_workload("Any Value NumberExponent WKT"),
    json_parse_workload("Any Value Surrogate WKT"),
    json_parse_workload("Any Value KeySurrogate WKT"),
    *json_workload_pair("Any NullValue WKT"),
    *json_workload_pair("Any StringScalarValue WKT"),
    json_parse_workload("Any StringScalarValue Escape WKT"),
    json_parse_workload("Any StringScalarValue Surrogate WKT"),
    *json_workload_pair("Any EmptyStringScalarValue WKT"),
    *json_workload_pair("Any NumberValue WKT"),
    json_parse_workload("Any NumberValue Exponent WKT"),
    *json_workload_pair("Any NegativeNumberValue WKT"),
    *json_workload_pair("Any ZeroNumberValue WKT"),
    *json_workload_pair("Any BoolScalarValue WKT"),
    *json_workload_pair("Any FalseBoolScalarValue WKT"),
    *json_workload_pair("Any ListKindValue WKT"),
    json_parse_workload("Any ListKindValue Escape WKT"),
    json_parse_workload("Any ListKindValue Surrogate WKT"),
    *json_workload_pair("Any EmptyStructKindValue WKT"),
    *json_workload_pair("Any EmptyListKindValue WKT"),
    *json_workload_pair("Any DoubleValue WKT"),
    json_parse_workload("Any DoubleValue String WKT"),
    json_parse_workload("Any DoubleValue Exponent WKT"),
    *json_workload_pair("Any NegativeDoubleValue WKT"),
    *json_workload_pair("Any ZeroDoubleValue WKT"),
    *json_workload_pair("Any DoubleValue NaN WKT"),
    *json_workload_pair("Any DoubleValue Infinity WKT"),
    *json_workload_pair("Any DoubleValue NegativeInfinity WKT"),
    *json_workload_pair("Any FloatValue WKT"),
    json_parse_workload("Any FloatValue String WKT"),
    json_parse_workload("Any FloatValue Exponent WKT"),
    *json_workload_pair("Any NegativeFloatValue WKT"),
    *json_workload_pair("Any ZeroFloatValue WKT"),
    *json_workload_pair("Any FloatValue NaN WKT"),
    *json_workload_pair("Any FloatValue Infinity WKT"),
    *json_workload_pair("Any FloatValue NegativeInfinity WKT"),
    *json_workload_pair("Any Int64Value WKT"),
    json_parse_workload("Any Int64Value Number WKT"),
    json_parse_workload("Any Int64Value Exponent WKT"),
    *json_workload_pair("Any ZeroInt64Value WKT"),
    *json_workload_pair("Any NegativeInt64Value WKT"),
    *json_workload_pair("Any MinInt64Value WKT"),
    *json_workload_pair("Any MaxInt64Value WKT"),
    *json_workload_pair("Any UInt64Value WKT"),
    json_parse_workload("Any UInt64Value Number WKT"),
    json_parse_workload("Any UInt64Value Exponent WKT"),
    *json_workload_pair("Any ZeroUInt64Value WKT"),
    *json_workload_pair("Any MaxUInt64Value WKT"),
    *json_workload_pair("Any Int32Value WKT"),
    json_parse_workload("Any Int32Value String WKT"),
    json_parse_workload("Any Int32Value Exponent WKT"),
    *json_workload_pair("Any ZeroInt32Value WKT"),
    *json_workload_pair("Any NegativeInt32Value WKT"),
    *json_workload_pair("Any MinInt32Value WKT"),
    *json_workload_pair("Any MaxInt32Value WKT"),
    *json_workload_pair("Any UInt32Value WKT"),
    json_parse_workload("Any UInt32Value String WKT"),
    json_parse_workload("Any UInt32Value Exponent WKT"),
    *json_workload_pair("Any ZeroUInt32Value WKT"),
    *json_workload_pair("Any MaxUInt32Value WKT"),
    *json_workload_pair("Any BoolValue WKT"),
    *json_workload_pair("Any FalseBoolValue WKT"),
    *json_workload_pair("Any StringValue WKT"),
    json_parse_workload("Any StringValue Escape WKT"),
    json_parse_workload("Any StringValue Surrogate WKT"),
    *json_workload_pair("Any EmptyStringValue WKT"),
    *json_workload_pair("Any BytesValue WKT"),
    json_parse_workload("Any BytesValue URL WKT"),
    json_parse_workload("Any BytesValue StandardBase64 WKT"),
    json_parse_workload("Any BytesValue Unpadded WKT"),
    *json_workload_pair("Any EmptyBytesValue WKT"),
    *json_workload_pair("Nested Any WKT"),
    *json_workload_pair("Duration"),
    json_parse_workload("Duration Escape"),
    json_parse_workload("PlusDuration"),
    json_parse_workload("ShortFractionDuration"),
    *json_workload_pair("MicroDuration"),
    *json_workload_pair("NanoDuration"),
    *json_workload_pair("NegativeDuration"),
    *json_workload_pair("FractionalNegativeDuration"),
    *json_workload_pair("MaxDuration"),
    *json_workload_pair("MinDuration"),
    *json_workload_pair("ZeroDuration"),
    *json_workload_pair("FieldMask"),
    json_parse_workload("FieldMask Escape"),
    *json_workload_pair("EmptyFieldMask"),
    *json_workload_pair("Timestamp"),
    json_parse_workload("Timestamp Escape"),
    json_parse_workload("ShortFraction Timestamp"),
    *json_workload_pair("Micro Timestamp"),
    *json_workload_pair("Nano Timestamp"),
    json_parse_workload("Offset Timestamp"),
    *json_workload_pair("PreEpoch Timestamp"),
    *json_workload_pair("Max Timestamp"),
    *json_workload_pair("Min Timestamp"),
    *json_workload_pair("Empty"),
    *json_workload_pair("Struct"),
    json_parse_workload("Struct Escape"),
    json_parse_workload("Struct NumberExponent"),
    json_parse_workload("Struct Surrogate"),
    json_parse_workload("Struct KeySurrogate"),
    *json_workload_pair("EmptyStruct"),
    *json_workload_pair("Value"),
    json_parse_workload("Value Escape"),
    json_parse_workload("Value NumberExponent"),
    json_parse_workload("Value Surrogate"),
    json_parse_workload("Value KeySurrogate"),
    *json_workload_pair("NullValue"),
    *json_workload_pair("StringScalarValue"),
    json_parse_workload("StringScalarValue Escape"),
    json_parse_workload("StringScalarValue Surrogate"),
    *json_workload_pair("EmptyStringScalarValue"),
    *json_workload_pair("NumberValue"),
    json_parse_workload("NumberValue Exponent"),
    *json_workload_pair("NegativeNumberValue"),
    *json_workload_pair("ZeroNumberValue"),
    *json_workload_pair("BoolScalarValue"),
    *json_workload_pair("FalseBoolScalarValue"),
    *json_workload_pair("ListKindValue"),
    json_parse_workload("ListKindValue Escape"),
    json_parse_workload("ListKindValue Surrogate"),
    *json_workload_pair("EmptyStructKindValue"),
    *json_workload_pair("EmptyListKindValue"),
    *json_workload_pair("ListValue"),
    json_parse_workload("ListValue Escape"),
    json_parse_workload("ListValue Surrogate"),
    *json_workload_pair("EmptyListValue"),
    *json_workload_pair("DoubleValue"),
    json_parse_workload("DoubleValue String"),
    json_parse_workload("DoubleValue Exponent"),
    *json_workload_pair("NegativeDoubleValue"),
    *json_workload_pair("ZeroDoubleValue"),
    *json_workload_pair("DoubleValue NaN"),
    *json_workload_pair("DoubleValue Infinity"),
    *json_workload_pair("DoubleValue NegativeInfinity"),
    *json_workload_pair("FloatValue"),
    json_parse_workload("FloatValue String"),
    json_parse_workload("FloatValue Exponent"),
    *json_workload_pair("NegativeFloatValue"),
    *json_workload_pair("ZeroFloatValue"),
    *json_workload_pair("FloatValue NaN"),
    *json_workload_pair("FloatValue Infinity"),
    *json_workload_pair("FloatValue NegativeInfinity"),
    *json_workload_pair("Int64Value"),
    json_parse_workload("Int64Value Number"),
    json_parse_workload("Int64Value Exponent"),
    *json_workload_pair("ZeroInt64Value"),
    *json_workload_pair("NegativeInt64Value"),
    *json_workload_pair("MinInt64Value"),
    *json_workload_pair("MaxInt64Value"),
    *json_workload_pair("UInt64Value"),
    json_parse_workload("UInt64Value Number"),
    json_parse_workload("UInt64Value Exponent"),
    *json_workload_pair("ZeroUInt64Value"),
    *json_workload_pair("MaxUInt64Value"),
    *json_workload_pair("Int32Value"),
    json_parse_workload("Int32Value String"),
    json_parse_workload("Int32Value Exponent"),
    *json_workload_pair("ZeroInt32Value"),
    *json_workload_pair("NegativeInt32Value"),
    *json_workload_pair("MinInt32Value"),
    *json_workload_pair("MaxInt32Value"),
    *json_workload_pair("UInt32Value"),
    json_parse_workload("UInt32Value String"),
    json_parse_workload("UInt32Value Exponent"),
    *json_workload_pair("ZeroUInt32Value"),
    *json_workload_pair("MaxUInt32Value"),
    *json_workload_pair("BoolValue"),
    *json_workload_pair("FalseBoolValue"),
    *json_workload_pair("StringValue"),
    json_parse_workload("StringValue Escape"),
    json_parse_workload("StringValue Surrogate"),
    *json_workload_pair("EmptyStringValue"),
    *json_workload_pair("BytesValue"),
    json_parse_workload("BytesValue URL"),
    json_parse_workload("BytesValue StandardBase64"),
    json_parse_workload("BytesValue Unpadded"),
    *json_workload_pair("EmptyBytesValue"),
    Workload(
        "TextFormat format",
        ("generated TextFormat format",),
        {
            "c++ protobuf": ("c++ protobuf TextFormat format", "c++ protobuf TextFormat format reuse"),
            "go protobuf": ("go protobuf TextFormat format",),
        },
    ),
    Workload(
        "TextFormat parse",
        ("generated TextFormat parse",),
        {
            "c++ protobuf": ("c++ protobuf TextFormat parse", "c++ protobuf TextFormat parse reuse"),
            "go protobuf": ("go protobuf TextFormat parse",),
        },
    ),
    Workload(
        "packed fixed32 encode",
        (
            "generated fixed32 packed encode",
            "generated fixed32 packed encodeIntoAssumeCapacity buffer reuse",
            "generated fixed32 packed borrowed slices encode",
        ),
        {
            "rust prost": ("prost fixed32 packed encode",),
            "rust quick-protobuf": (
                "quick-protobuf fixed32 packed encode",
                "quick-protobuf fixed32 packed encode reuse",
            ),
            "c++ protobuf": (
                "c++ protobuf fixed32 packed encode",
                "c++ protobuf fixed32 packed SerializeToArray reuse",
            ),
            "go protobuf": ("go protobuf fixed32 packed encode", "go protobuf fixed32 packed encode reuse"),
        },
    ),
    Workload(
        "packed fixed32 decode",
        (
            "generated fixed32 packed decode",
            "generated fixed32 packed fast known-schema decode reuse",
            "generated fixed32 packed borrowed view decode",
        ),
        {
            "rust prost": ("prost fixed32 packed decode",),
            "rust quick-protobuf": ("quick-protobuf fixed32 packed decode",),
            "c++ protobuf": ("c++ protobuf fixed32 packed decode", "c++ protobuf fixed32 packed decode reuse"),
            "go protobuf": ("go protobuf fixed32 packed decode",),
        },
    ),
    Workload(
        "packed fixed64 encode",
        (
            "generated fixed64 packed encode",
            "generated fixed64 packed encodeIntoAssumeCapacity buffer reuse",
            "generated fixed64 packed borrowed slices encode",
        ),
        {
            "rust prost": ("prost fixed64 packed encode",),
            "rust quick-protobuf": (
                "quick-protobuf fixed64 packed encode",
                "quick-protobuf fixed64 packed encode reuse",
            ),
            "c++ protobuf": (
                "c++ protobuf fixed64 packed encode",
                "c++ protobuf fixed64 packed SerializeToArray reuse",
            ),
            "go protobuf": ("go protobuf fixed64 packed encode", "go protobuf fixed64 packed encode reuse"),
        },
    ),
    Workload(
        "packed fixed64 decode",
        (
            "generated fixed64 packed decode",
            "generated fixed64 packed fast known-schema decode reuse",
            "generated fixed64 packed borrowed view decode",
        ),
        {
            "rust prost": ("prost fixed64 packed decode",),
            "rust quick-protobuf": ("quick-protobuf fixed64 packed decode",),
            "c++ protobuf": ("c++ protobuf fixed64 packed decode", "c++ protobuf fixed64 packed decode reuse"),
            "go protobuf": ("go protobuf fixed64 packed decode",),
        },
    ),
    Workload(
        "packed sfixed32 encode",
        (
            "generated sfixed32 packed encode",
            "generated sfixed32 packed encodeIntoAssumeCapacity buffer reuse",
            "generated sfixed32 packed borrowed slices encode",
        ),
        {
            "rust prost": ("prost sfixed32 packed encode",),
            "rust quick-protobuf": (
                "quick-protobuf sfixed32 packed encode",
                "quick-protobuf sfixed32 packed encode reuse",
            ),
            "c++ protobuf": (
                "c++ protobuf sfixed32 packed encode",
                "c++ protobuf sfixed32 packed SerializeToArray reuse",
            ),
            "go protobuf": ("go protobuf sfixed32 packed encode", "go protobuf sfixed32 packed encode reuse"),
        },
    ),
    Workload(
        "packed sfixed32 decode",
        (
            "generated sfixed32 packed decode",
            "generated sfixed32 packed fast known-schema decode reuse",
            "generated sfixed32 packed borrowed view decode",
        ),
        {
            "rust prost": ("prost sfixed32 packed decode",),
            "rust quick-protobuf": ("quick-protobuf sfixed32 packed decode",),
            "c++ protobuf": ("c++ protobuf sfixed32 packed decode", "c++ protobuf sfixed32 packed decode reuse"),
            "go protobuf": ("go protobuf sfixed32 packed decode",),
        },
    ),
    Workload(
        "packed sfixed64 encode",
        (
            "generated sfixed64 packed encode",
            "generated sfixed64 packed encodeIntoAssumeCapacity buffer reuse",
            "generated sfixed64 packed borrowed slices encode",
        ),
        {
            "rust prost": ("prost sfixed64 packed encode",),
            "rust quick-protobuf": (
                "quick-protobuf sfixed64 packed encode",
                "quick-protobuf sfixed64 packed encode reuse",
            ),
            "c++ protobuf": (
                "c++ protobuf sfixed64 packed encode",
                "c++ protobuf sfixed64 packed SerializeToArray reuse",
            ),
            "go protobuf": ("go protobuf sfixed64 packed encode", "go protobuf sfixed64 packed encode reuse"),
        },
    ),
    Workload(
        "packed sfixed64 decode",
        (
            "generated sfixed64 packed decode",
            "generated sfixed64 packed fast known-schema decode reuse",
            "generated sfixed64 packed borrowed view decode",
        ),
        {
            "rust prost": ("prost sfixed64 packed decode",),
            "rust quick-protobuf": ("quick-protobuf sfixed64 packed decode",),
            "c++ protobuf": ("c++ protobuf sfixed64 packed decode", "c++ protobuf sfixed64 packed decode reuse"),
            "go protobuf": ("go protobuf sfixed64 packed decode",),
        },
    ),
    Workload(
        "packed float encode",
        (
            "generated float packed encode",
            "generated float packed encodeIntoAssumeCapacity buffer reuse",
            "generated float packed borrowed slices encode",
        ),
        {
            "rust prost": ("prost float packed encode",),
            "rust quick-protobuf": (
                "quick-protobuf float packed encode",
                "quick-protobuf float packed encode reuse",
            ),
            "c++ protobuf": (
                "c++ protobuf float packed encode",
                "c++ protobuf float packed SerializeToArray reuse",
            ),
            "go protobuf": ("go protobuf float packed encode", "go protobuf float packed encode reuse"),
        },
    ),
    Workload(
        "packed float decode",
        (
            "generated float packed decode",
            "generated float packed fast known-schema decode reuse",
            "generated float packed borrowed view decode",
        ),
        {
            "rust prost": ("prost float packed decode",),
            "rust quick-protobuf": ("quick-protobuf float packed decode",),
            "c++ protobuf": ("c++ protobuf float packed decode", "c++ protobuf float packed decode reuse"),
            "go protobuf": ("go protobuf float packed decode",),
        },
    ),
    Workload(
        "packed double encode",
        (
            "generated double packed encode",
            "generated double packed encodeIntoAssumeCapacity buffer reuse",
            "generated double packed borrowed slices encode",
        ),
        {
            "rust prost": ("prost double packed encode",),
            "rust quick-protobuf": (
                "quick-protobuf double packed encode",
                "quick-protobuf double packed encode reuse",
            ),
            "c++ protobuf": (
                "c++ protobuf double packed encode",
                "c++ protobuf double packed SerializeToArray reuse",
            ),
            "go protobuf": ("go protobuf double packed encode", "go protobuf double packed encode reuse"),
        },
    ),
    Workload(
        "packed double decode",
        (
            "generated double packed decode",
            "generated double packed fast known-schema decode reuse",
            "generated double packed borrowed view decode",
        ),
        {
            "rust prost": ("prost double packed decode",),
            "rust quick-protobuf": ("quick-protobuf double packed decode",),
            "c++ protobuf": ("c++ protobuf double packed decode", "c++ protobuf double packed decode reuse"),
            "go protobuf": ("go protobuf double packed decode",),
        },
    ),
    Workload(
        "packed uint64 encode",
        (
            "generated uint64 packed encode",
            "generated uint64 packed encodeIntoAssumeCapacity buffer reuse",
        ),
        {
            "rust prost": ("prost uint64 packed encode",),
            "rust quick-protobuf": (
                "quick-protobuf uint64 packed encode",
                "quick-protobuf uint64 packed encode reuse",
            ),
            "c++ protobuf": (
                "c++ protobuf uint64 packed encode",
                "c++ protobuf uint64 packed SerializeToArray reuse",
            ),
            "go protobuf": ("go protobuf uint64 packed encode", "go protobuf uint64 packed encode reuse"),
        },
    ),
    Workload(
        "packed uint64 decode",
        (
            "generated uint64 packed decode",
            "generated uint64 packed decode reuse",
            "generated uint64 packed fast known-schema decode reuse",
            "generated uint64 packed iterator decode",
        ),
        {
            "rust prost": ("prost uint64 packed decode",),
            "rust quick-protobuf": ("quick-protobuf uint64 packed decode",),
            "c++ protobuf": ("c++ protobuf uint64 packed decode", "c++ protobuf uint64 packed decode reuse"),
            "go protobuf": ("go protobuf uint64 packed decode",),
        },
    ),
    Workload(
        "packed uint32 encode",
        (
            "generated uint32 packed encode",
            "generated uint32 packed encodeIntoAssumeCapacity buffer reuse",
        ),
        {
            "rust prost": ("prost uint32 packed encode",),
            "rust quick-protobuf": (
                "quick-protobuf uint32 packed encode",
                "quick-protobuf uint32 packed encode reuse",
            ),
            "c++ protobuf": (
                "c++ protobuf uint32 packed encode",
                "c++ protobuf uint32 packed SerializeToArray reuse",
            ),
            "go protobuf": ("go protobuf uint32 packed encode", "go protobuf uint32 packed encode reuse"),
        },
    ),
    Workload(
        "packed uint32 decode",
        (
            "generated uint32 packed decode",
            "generated uint32 packed decode reuse",
            "generated uint32 packed fast known-schema decode reuse",
            "generated uint32 packed iterator decode",
        ),
        {
            "rust prost": ("prost uint32 packed decode",),
            "rust quick-protobuf": ("quick-protobuf uint32 packed decode",),
            "c++ protobuf": ("c++ protobuf uint32 packed decode", "c++ protobuf uint32 packed decode reuse"),
            "go protobuf": ("go protobuf uint32 packed decode",),
        },
    ),
    Workload(
        "packed int64 encode",
        (
            "generated int64 packed encode",
            "generated int64 packed encodeIntoAssumeCapacity buffer reuse",
        ),
        {
            "rust prost": ("prost int64 packed encode",),
            "rust quick-protobuf": (
                "quick-protobuf int64 packed encode",
                "quick-protobuf int64 packed encode reuse",
            ),
            "c++ protobuf": (
                "c++ protobuf int64 packed encode",
                "c++ protobuf int64 packed SerializeToArray reuse",
            ),
            "go protobuf": ("go protobuf int64 packed encode", "go protobuf int64 packed encode reuse"),
        },
    ),
    Workload(
        "packed int64 decode",
        (
            "generated int64 packed decode",
            "generated int64 packed fast known-schema decode reuse",
            "generated int64 packed iterator decode",
        ),
        {
            "rust prost": ("prost int64 packed decode",),
            "rust quick-protobuf": ("quick-protobuf int64 packed decode",),
            "c++ protobuf": ("c++ protobuf int64 packed decode", "c++ protobuf int64 packed decode reuse"),
            "go protobuf": ("go protobuf int64 packed decode",),
        },
    ),
    Workload(
        "packed sint32 encode",
        (
            "generated sint32 packed encode",
            "generated sint32 packed encodeIntoAssumeCapacity buffer reuse",
        ),
        {
            "rust prost": ("prost sint32 packed encode",),
            "rust quick-protobuf": (
                "quick-protobuf sint32 packed encode",
                "quick-protobuf sint32 packed encode reuse",
            ),
            "c++ protobuf": (
                "c++ protobuf sint32 packed encode",
                "c++ protobuf sint32 packed SerializeToArray reuse",
            ),
            "go protobuf": ("go protobuf sint32 packed encode", "go protobuf sint32 packed encode reuse"),
        },
    ),
    Workload(
        "packed sint32 decode",
        (
            "generated sint32 packed decode",
            "generated sint32 packed fast known-schema decode reuse",
            "generated sint32 packed iterator decode",
        ),
        {
            "rust prost": ("prost sint32 packed decode",),
            "rust quick-protobuf": ("quick-protobuf sint32 packed decode",),
            "c++ protobuf": ("c++ protobuf sint32 packed decode", "c++ protobuf sint32 packed decode reuse"),
            "go protobuf": ("go protobuf sint32 packed decode",),
        },
    ),
    Workload(
        "packed sint64 encode",
        (
            "generated sint64 packed encode",
            "generated sint64 packed encodeIntoAssumeCapacity buffer reuse",
        ),
        {
            "rust prost": ("prost sint64 packed encode",),
            "rust quick-protobuf": (
                "quick-protobuf sint64 packed encode",
                "quick-protobuf sint64 packed encode reuse",
            ),
            "c++ protobuf": (
                "c++ protobuf sint64 packed encode",
                "c++ protobuf sint64 packed SerializeToArray reuse",
            ),
            "go protobuf": ("go protobuf sint64 packed encode", "go protobuf sint64 packed encode reuse"),
        },
    ),
    Workload(
        "packed sint64 decode",
        (
            "generated sint64 packed decode",
            "generated sint64 packed fast known-schema decode reuse",
            "generated sint64 packed iterator decode",
        ),
        {
            "rust prost": ("prost sint64 packed decode",),
            "rust quick-protobuf": ("quick-protobuf sint64 packed decode",),
            "c++ protobuf": ("c++ protobuf sint64 packed decode", "c++ protobuf sint64 packed decode reuse"),
            "go protobuf": ("go protobuf sint64 packed decode",),
        },
    ),
    Workload(
        "packed bool encode",
        (
            "generated bool packed encode",
            "generated bool packed encodeIntoAssumeCapacity buffer reuse",
            "generated bool packed borrowed slices encode",
        ),
        {
            "rust prost": ("prost bool packed encode",),
            "rust quick-protobuf": (
                "quick-protobuf bool packed encode",
                "quick-protobuf bool packed encode reuse",
            ),
            "c++ protobuf": (
                "c++ protobuf bool packed encode",
                "c++ protobuf bool packed SerializeToArray reuse",
            ),
            "go protobuf": ("go protobuf bool packed encode", "go protobuf bool packed encode reuse"),
        },
    ),
    Workload(
        "packed bool decode",
        (
            "generated bool packed decode",
            "generated bool packed fast known-schema decode reuse",
        ),
        {
            "rust prost": ("prost bool packed decode",),
            "rust quick-protobuf": ("quick-protobuf bool packed decode",),
            "c++ protobuf": ("c++ protobuf bool packed decode", "c++ protobuf bool packed decode reuse"),
            "go protobuf": ("go protobuf bool packed decode",),
        },
    ),
    Workload(
        "packed enum encode",
        (
            "generated enum packed encode",
            "generated enum packed encodeIntoAssumeCapacity buffer reuse",
        ),
        {
            "rust prost": ("prost enum packed encode",),
            "rust quick-protobuf": (
                "quick-protobuf enum packed encode",
                "quick-protobuf enum packed encode reuse",
            ),
            "c++ protobuf": (
                "c++ protobuf enum packed encode",
                "c++ protobuf enum packed SerializeToArray reuse",
            ),
            "go protobuf": ("go protobuf enum packed encode", "go protobuf enum packed encode reuse"),
        },
    ),
    Workload(
        "packed enum decode",
        (
            "generated enum packed decode",
            "generated enum packed decode reuse",
            "generated enum packed fast known-schema decode reuse",
        ),
        {
            "rust prost": ("prost enum packed decode",),
            "rust quick-protobuf": ("quick-protobuf enum packed decode",),
            "c++ protobuf": ("c++ protobuf enum packed decode", "c++ protobuf enum packed decode reuse"),
            "go protobuf": ("go protobuf enum packed decode",),
        },
    ),
    Workload(
        "large map encode",
        (
            "generated large map encode",
            "generated large map writeToAssumeCapacity reuse",
            "generated large map encodeIntoAssumeCapacity buffer reuse",
        ),
        {
            "rust prost": ("prost large map encode",),
            "rust quick-protobuf": ("quick-protobuf large map encode", "quick-protobuf large map encode reuse"),
            "c++ protobuf": ("c++ protobuf large map encode", "c++ protobuf large map SerializeToArray reuse"),
            "go protobuf": ("go protobuf large map encode", "go protobuf large map encode reuse"),
        },
    ),
    Workload(
        "shuffled large map deterministic binary encode",
        ("generated shuffled large map deterministic encodeIntoAssumeCapacity buffer reuse",),
        {
            "c++ protobuf": ("c++ protobuf shuffled large map deterministic binary encode reuse",),
            "go protobuf": ("go protobuf shuffled large map deterministic binary encode reuse",),
        },
    ),
    Workload(
        "large map decode",
        ("generated large map decode", "generated large map decode reuse"),
        {
            "rust prost": ("prost large map decode",),
            "rust quick-protobuf": ("quick-protobuf large map decode",),
            "c++ protobuf": ("c++ protobuf large map decode", "c++ protobuf large map decode reuse"),
            "go protobuf": ("go protobuf large map decode",),
        },
    ),
)


def validate_workloads() -> None:
    assert len(WORKLOADS) == EXPECTED_WORKLOAD_COUNT, (len(WORKLOADS), EXPECTED_WORKLOAD_COUNT)

    names = [workload.name for workload in WORKLOADS]
    duplicate_names = sorted({name for name in names if names.count(name) > 1})
    assert not duplicate_names, duplicate_names

    for workload in WORKLOADS:
        assert workload.pbz, workload.name
        assert len(set(workload.pbz)) == len(workload.pbz), workload.name
        assert workload.baselines, workload.name
        for impl, candidates in workload.baselines.items():
            assert impl, workload.name
            assert candidates, (workload.name, impl)
            assert len(set(candidates)) == len(candidates), (workload.name, impl)


def parse_results(text: str) -> dict[str, float]:
    results: dict[str, float] = {}
    for line in text.splitlines():
        match = LINE_RE.match(line.strip())
        if match:
            results[match.group("name")] = float(match.group("ns"))
    return results


def best(results: dict[str, float], names: tuple[str, ...]) -> tuple[str, float] | None:
    available = [(name, results[name]) for name in names if name in results]
    if not available:
        return None
    return min(available, key=lambda item: item[1])


def summarize(results: dict[str, float]) -> tuple[str, bool]:
    rows: list[tuple[str, str, str, float, str, float, float, str]] = []
    uncovered: list[tuple[str, str, tuple[str, ...]]] = []
    has_gap = False
    for workload in WORKLOADS:
        pbz_best = best(results, workload.pbz)
        if pbz_best is None:
            uncovered.append((workload.name, "pbz", workload.pbz))
            has_gap = True
            continue
        pbz_name, pbz_ns = pbz_best
        for impl, names in workload.baselines.items():
            baseline_best = best(results, names)
            if baseline_best is None:
                uncovered.append((workload.name, impl, names))
                has_gap = True
                continue
            baseline_name, baseline_ns = baseline_best
            ratio = baseline_ns / pbz_ns if pbz_ns else float("inf")
            status = "WIN" if pbz_ns < baseline_ns else "LOSS"
            has_gap = has_gap or status == "LOSS"
            rows.append((workload.name, impl, pbz_name, pbz_ns, baseline_name, baseline_ns, ratio, status))

    if not rows:
        details = ""
        if uncovered:
            details = "\nUncovered rows:\n" + "\n".join(
                f"- {workload} / {impl}: expected one of {', '.join(names)}"
                for workload, impl, names in uncovered
            )
        return "No comparable benchmark rows found." + details, True

    lines = [
        "| workload | baseline | pbz best ns/op | baseline best ns/op | baseline/pbz | status |",
        "|---|---:|---:|---:|---:|---|",
    ]
    for workload, impl, pbz_name, pbz_ns, baseline_name, baseline_ns, ratio, status in rows:
        lines.append(
            f"| {workload} | {impl} | {pbz_ns:.2f} (`{pbz_name}`) | "
            f"{baseline_ns:.2f} (`{baseline_name}`) | {ratio:.2f}x | {status} |"
        )
    losses = [row for row in rows if row[-1] == "LOSS"]
    if losses:
        lines.append("")
        lines.append("Remaining performance gaps:")
        for workload, impl, _pbz_name, pbz_ns, baseline_name, baseline_ns, _ratio, _status in losses:
            lines.append(f"- {workload} vs {impl}: pbz {pbz_ns:.2f} ns/op, {baseline_name} {baseline_ns:.2f} ns/op")
    if uncovered:
        lines.append("")
        lines.append("Uncovered benchmark rows:")
        for workload, impl, names in uncovered:
            lines.append(f"- {workload} / {impl}: expected one of {', '.join(names)}")
    if not losses and not uncovered:
        lines.append("")
        lines.append("All parsed cross-language rows are pbz wins.")
    return "\n".join(lines), has_gap


def summarize_pivot(results: dict[str, float]) -> tuple[str, bool]:
    """Return a README-friendly workload-by-baseline comparison table.

    This intentionally uses the same workload matrix and gap accounting as the
    default detailed summary, but pivots each workload into one row so humans can
    scan README updates without manually transposing the fail-on-loss output.
    Missing baseline cells are rendered as em dashes while still contributing to
    ``has_gap`` for callers that also pass ``--fail-on-loss``.
    """

    baseline_order = ("rust prost", "rust quick-protobuf", "c++ protobuf", "go protobuf")
    rows: list[tuple[str, float, dict[str, tuple[float, float]]]] = []
    has_gap = False

    for workload in WORKLOADS:
        pbz_best = best(results, workload.pbz)
        if pbz_best is None:
            has_gap = True
            continue
        _pbz_name, pbz_ns = pbz_best
        baseline_cells: dict[str, tuple[float, float]] = {}
        for impl, names in workload.baselines.items():
            baseline_best = best(results, names)
            if baseline_best is None:
                has_gap = True
                continue
            _baseline_name, baseline_ns = baseline_best
            if pbz_ns >= baseline_ns:
                has_gap = True
            baseline_cells[impl] = (baseline_ns, baseline_ns / pbz_ns if pbz_ns else float("inf"))
        rows.append((workload.name, pbz_ns, baseline_cells))

    if not rows:
        return "No comparable benchmark rows found.", True

    lines = [
        "| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |",
        "|---|---:|---:|---:|---:|---:|",
    ]
    for workload, pbz_ns, baseline_cells in rows:
        cells = []
        for impl in baseline_order:
            if impl in baseline_cells:
                baseline_ns, ratio = baseline_cells[impl]
                cells.append(f"{baseline_ns:.2f} ({ratio:.2f}x)")
            else:
                cells.append("—")
        lines.append(f"| {workload} | {pbz_ns:.2f} | " + " | ".join(cells) + " |")
    return "\n".join(lines), has_gap


def self_test() -> None:
    validate_workloads()

    sample_lines = [
        benchmark_line("generated binary encodeIntoAssumeCapacity buffer reuse", 47, 40.0),
        benchmark_line("generated binary decode", 47, 200.0),
        benchmark_line("generated unknown field number run sidecar count", 4016, 5.0),
        benchmark_line("dynamic unknown field number run sidecar count", 4016, 6.0),
        benchmark_line("c++ protobuf unknown fields count by number", 4016, 100.0),
        benchmark_line("generated textbytes borrowed slices encode", 134, 20.0),
        benchmark_line("quick-protobuf textbytes encode reuse", 134, 30.0),
        benchmark_line("generated AlwaysPrint JSON stringify", 32, 90.0),
        benchmark_line("c++ protobuf AlwaysPrint JSON stringify", 32, 650.0),
        benchmark_line("go protobuf AlwaysPrint JSON stringify", 32, 350.0),
        benchmark_line("generated ProtoName JSON stringify", 180, 120.0),
        benchmark_line("c++ protobuf ProtoName JSON stringify", 180, 700.0),
        benchmark_line("go protobuf ProtoName JSON stringify", 180, 400.0),
        benchmark_line("generated MapKeySurrogate JSON parse", 29, 70.0),
        benchmark_line("c++ protobuf MapKeySurrogate JSON parse", 29, 400.0),
        benchmark_line("go protobuf MapKeySurrogate JSON parse", 29, 250.0),
        benchmark_line("generated NullFields JSON parse", 51, 75.0),
        benchmark_line("c++ protobuf NullFields JSON parse", 51, 450.0),
        benchmark_line("go protobuf NullFields JSON parse", 51, 275.0),
        benchmark_line("generated OpenEnum JSON parse", 12, 80.0),
        benchmark_line("c++ protobuf OpenEnum JSON parse", 12, 450.0),
        benchmark_line("go protobuf OpenEnum JSON parse", 12, 275.0),
        benchmark_line("generated EnumName JSON parse", 26, 85.0),
        benchmark_line("c++ protobuf EnumName JSON parse", 26, 475.0),
        benchmark_line("go protobuf EnumName JSON parse", 26, 290.0),
        benchmark_line("generated ProtoName JSON parse", 62, 95.0),
        benchmark_line("c++ protobuf ProtoName JSON parse", 62, 500.0),
        benchmark_line("go protobuf ProtoName JSON parse", 62, 325.0),
        benchmark_line("generated IntExponent JSON parse", 203, 90.0),
        benchmark_line("c++ protobuf IntExponent JSON parse", 203, 500.0),
        benchmark_line("go protobuf IntExponent JSON parse", 203, 300.0),
    ]
    for label, bytes_per_iter, stringify_ns, parse_ns in JSON_SELF_TEST_SPECS:
        sample_lines.extend(json_sample_pair(label, bytes_per_iter, stringify_ns, parse_ns))
    for label, bytes_per_iter in (
        ("Any Struct Escape WKT", 130),
        ("Any Value Escape WKT", 129),
        ("Any Struct NumberExponent WKT", 123),
        ("Any Value NumberExponent WKT", 122),
        ("Any Struct Surrogate WKT", 87),
        ("Any Value Surrogate WKT", 86),
        ("Any Struct KeySurrogate WKT", 84),
        ("Any Value KeySurrogate WKT", 83),
        ("Any StringScalarValue Escape WKT", 72),
        ("Any ListKindValue Escape WKT", 112),
        ("Any ListKindValue Surrogate WKT", 78),
        ("Struct Escape", 67),
        ("Struct NumberExponent", 60),
        ("Struct Surrogate", 24),
        ("Struct KeySurrogate", 21),
        ("Value Escape", 67),
        ("Value NumberExponent", 60),
        ("Value Surrogate", 24),
        ("Value KeySurrogate", 21),
        ("StringScalarValue Escape", 10),
        ("Any StringValue Surrogate WKT", 82),
        ("StringValue Surrogate", 14),
        ("Any StringScalarValue Surrogate WKT", 76),
        ("StringScalarValue Surrogate", 14),
        ("Any NumberValue Exponent WKT", 67),
        ("NumberValue Exponent", 5),
        ("Any DoubleValue Exponent WKT", 74),
        ("DoubleValue Exponent", 6),
        ("Any FloatValue Exponent WKT", 72),
        ("FloatValue Exponent", 5),
        ("Any Int64Value Exponent WKT", 75),
        ("Int64Value Exponent", 8),
        ("Any UInt64Value Exponent WKT", 76),
        ("UInt64Value Exponent", 8),
        ("Any Int32Value Exponent WKT", 75),
        ("Int32Value Exponent", 8),
        ("Any UInt32Value Exponent WKT", 76),
        ("UInt32Value Exponent", 8),
        ("Any BytesValue StandardBase64 WKT", 72),
        ("BytesValue StandardBase64", 5),
        ("Any BytesValue Unpadded WKT", 72),
        ("BytesValue Unpadded", 5),
        ("ListKindValue Escape", 50),
        ("ListKindValue Surrogate", 16),
        ("ListValue Escape", 50),
        ("ListValue Surrogate", 16),
    ):
        sample_lines.extend(
            (
                benchmark_line(f"pbz {label} JSON parse", bytes_per_iter, 130.0),
                benchmark_line(f"c++ protobuf {label} JSON parse", bytes_per_iter, 900.0),
                benchmark_line(f"go protobuf {label} JSON parse", bytes_per_iter, 800.0),
            )
        )
    sample_lines.extend(
        (
            benchmark_line("quick-protobuf binary encode reuse", 47, 50.0),
            benchmark_line("quick-protobuf binary decode", 47, 150.0),
        )
    )
    sample = "\n".join(sample_lines)
    results = parse_results(sample)
    output, has_loss = summarize(results)
    assert "binary encode" in output
    assert "unknown fields count by number" in output
    assert "generated unknown field number run sidecar count" in output
    assert "dynamic unknown field number run sidecar count" not in output
    assert "c++ protobuf unknown fields count by number" in output
    assert "textbytes encode" in output
    assert "generated textbytes borrowed slices encode" in output
    assert "quick-protobuf textbytes encode reuse" in output
    for label, _bytes_per_iter, _stringify_ns, _parse_ns in JSON_SELF_TEST_SPECS:
        assert f"{label} JSON stringify" in output
        assert f"pbz {label} JSON stringify" in output
        assert f"c++ protobuf {label} JSON stringify" in output
        assert f"go protobuf {label} JSON stringify" in output
        assert f"{label} JSON parse" in output
        assert f"pbz {label} JSON parse" in output
        assert f"c++ protobuf {label} JSON parse" in output
        assert f"go protobuf {label} JSON parse" in output
    assert "WIN" in output
    assert "LOSS" in output
    assert "Uncovered benchmark rows" in output
    assert has_loss

    dynamic_unknown_sample = """
    dynamic unknown field number run sidecar count: best of 3 x 10 iters, 4016 bytes/iter, 4.00 ns/op, 1 ops/s, 1 MiB/s
    c++ protobuf unknown fields count by number: best of 3 x 10 iters, 4016 bytes/iter, 100.00 ns/op, 1 ops/s, 1 MiB/s
    """
    dynamic_output, dynamic_has_loss = summarize(parse_results(dynamic_unknown_sample))
    assert "dynamic unknown field number run sidecar count" in dynamic_output
    assert "unknown fields count by number" in dynamic_output
    assert dynamic_has_loss

    pivot_output, pivot_has_loss = summarize_pivot(results)
    assert "| workload | pbz ns/op | Rust prost | Rust quick-protobuf | C++ protobuf | Go protobuf |" in pivot_output
    assert "| binary encode |" in pivot_output
    assert "50.00 (1.25x)" in pivot_output
    assert "| Any WKT JSON stringify |" in pivot_output
    assert "| EmptyBytesValue JSON parse |" in pivot_output
    assert pivot_has_loss


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", nargs="?", help="run_compare output log; stdin is used when omitted")
    parser.add_argument("--fail-on-loss", action="store_true", help="exit non-zero if any parsed row is a pbz loss or missing baseline")
    parser.add_argument("--pivot", action="store_true", help="print a README-friendly workload-by-baseline table")
    parser.add_argument("--self-test", action="store_true", help="run parser self-test")
    args = parser.parse_args(argv)

    if args.self_test:
        self_test()
        return 0

    if args.log:
        text = Path(args.log).read_text(encoding="utf-8")
    else:
        text = sys.stdin.read()
    results = parse_results(text)
    output, has_loss = summarize_pivot(results) if args.pivot else summarize(results)
    print(output)
    return 1 if args.fail_on_loss and has_loss else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
