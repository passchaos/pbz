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
EXPECTED_WORKLOAD_COUNT = 190


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
    ("Any NegativeDuration WKT", 74, (60.0, 300.0, 350.0), (80.0, 400.0, 500.0)),
    ("Any FractionalNegativeDuration WKT", 74, (60.0, 300.0, 350.0), (80.0, 400.0, 500.0)),
    ("Any MaxDuration WKT", 80, (60.0, 300.0, 350.0), (80.0, 400.0, 500.0)),
    ("Any MinDuration WKT", 81, (60.0, 300.0, 350.0), (80.0, 400.0, 500.0)),
    ("Any ZeroDuration WKT", 69, (60.0, 300.0, 350.0), (80.0, 400.0, 500.0)),
    ("Any FieldMask WKT", 87, (100.0, 600.0, 550.0), (150.0, 850.0, 800.0)),
    ("Any Timestamp WKT", 92, (100.0, 600.0, 550.0), (150.0, 850.0, 800.0)),
    ("Any PreEpoch Timestamp WKT", 88, (100.0, 600.0, 550.0), (150.0, 850.0, 800.0)),
    ("Any Max Timestamp WKT", 98, (100.0, 600.0, 550.0), (150.0, 850.0, 800.0)),
    ("Any Min Timestamp WKT", 88, (100.0, 600.0, 550.0), (150.0, 850.0, 800.0)),
    ("Any Empty WKT", 53, (80.0, 450.0, 400.0), (110.0, 700.0, 650.0)),
    ("Any Struct WKT", 121, (120.0, 1000.0, 900.0), (180.0, 1200.0, 1100.0)),
    ("Any Value WKT", 120, (120.0, 1000.0, 900.0), (180.0, 1200.0, 1100.0)),
    ("Any DoubleValue WKT", 72, (90.0, 500.0, 450.0), (140.0, 800.0, 750.0)),
    ("Any DoubleValue NaN WKT", 73, (90.0, 500.0, 450.0), (140.0, 800.0, 750.0)),
    ("Any DoubleValue Infinity WKT", 78, (90.0, 500.0, 450.0), (140.0, 800.0, 750.0)),
    ("Any DoubleValue NegativeInfinity WKT", 79, (90.0, 500.0, 450.0), (140.0, 800.0, 750.0)),
    ("Any FloatValue WKT", 70, (90.0, 500.0, 450.0), (140.0, 800.0, 750.0)),
    ("Any FloatValue NaN WKT", 72, (90.0, 500.0, 450.0), (140.0, 800.0, 750.0)),
    ("Any FloatValue Infinity WKT", 77, (90.0, 500.0, 450.0), (140.0, 800.0, 750.0)),
    ("Any FloatValue NegativeInfinity WKT", 78, (90.0, 500.0, 450.0), (140.0, 800.0, 750.0)),
    ("Any Int64Value WKT", 85, (90.0, 500.0, 450.0), (140.0, 800.0, 750.0)),
    ("Any NegativeInt64Value WKT", 86, (90.0, 500.0, 450.0), (140.0, 800.0, 750.0)),
    ("Any UInt64Value WKT", 86, (90.0, 500.0, 450.0), (140.0, 800.0, 750.0)),
    ("Any MaxUInt64Value WKT", 90, (90.0, 500.0, 450.0), (140.0, 800.0, 750.0)),
    ("Any Int32Value WKT", 72, (90.0, 500.0, 450.0), (140.0, 800.0, 750.0)),
    ("Any NegativeInt32Value WKT", 73, (90.0, 500.0, 450.0), (140.0, 800.0, 750.0)),
    ("Any UInt32Value WKT", 73, (90.0, 500.0, 450.0), (140.0, 800.0, 750.0)),
    ("Any MaxUInt32Value WKT", 78, (90.0, 500.0, 450.0), (140.0, 800.0, 750.0)),
    ("Any BoolValue WKT", 70, (80.0, 450.0, 400.0), (110.0, 700.0, 650.0)),
    ("Any StringValue WKT", 75, (90.0, 500.0, 450.0), (120.0, 700.0, 650.0)),
    ("Any BytesValue WKT", 73, (90.0, 500.0, 450.0), (140.0, 750.0, 700.0)),
    ("Nested Any WKT", 135, (140.0, 1500.0, 900.0), (200.0, 2200.0, 1400.0)),
    ("Duration", 8, (30.0, 200.0, 250.0), (35.0, 220.0, 260.0)),
    ("NegativeDuration", 9, (30.0, 200.0, 250.0), (35.0, 220.0, 260.0)),
    ("FractionalNegativeDuration", 9, (30.0, 200.0, 250.0), (35.0, 220.0, 260.0)),
    ("MaxDuration", 15, (30.0, 200.0, 250.0), (35.0, 220.0, 260.0)),
    ("MinDuration", 16, (30.0, 200.0, 250.0), (35.0, 220.0, 260.0)),
    ("ZeroDuration", 4, (30.0, 200.0, 250.0), (35.0, 220.0, 260.0)),
    ("FieldMask", 21, (40.0, 230.0, 270.0), (45.0, 240.0, 280.0)),
    ("Timestamp", 28, (55.0, 250.0, 300.0), (65.0, 260.0, 320.0)),
    ("PreEpoch Timestamp", 22, (55.0, 250.0, 300.0), (65.0, 260.0, 320.0)),
    ("Max Timestamp", 32, (55.0, 250.0, 300.0), (65.0, 260.0, 320.0)),
    ("Min Timestamp", 22, (55.0, 250.0, 300.0), (65.0, 260.0, 320.0)),
    ("Empty", 2, (20.0, 200.0, 180.0), (30.0, 210.0, 190.0)),
    ("Struct", 58, (90.0, 900.0, 800.0), (120.0, 1000.0, 900.0)),
    ("Value", 58, (90.0, 900.0, 800.0), (120.0, 1000.0, 900.0)),
    ("ListValue", 40, (80.0, 850.0, 760.0), (110.0, 950.0, 850.0)),
    ("DoubleValue", 4, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("DoubleValue NaN", 5, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("DoubleValue Infinity", 10, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("DoubleValue NegativeInfinity", 11, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("FloatValue", 3, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("FloatValue NaN", 5, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("FloatValue Infinity", 10, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("FloatValue NegativeInfinity", 11, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("Int64Value", 18, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("NegativeInt64Value", 19, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("UInt64Value", 18, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("MaxUInt64Value", 22, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("Int32Value", 5, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("NegativeInt32Value", 6, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("UInt32Value", 5, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("MaxUInt32Value", 10, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("BoolValue", 4, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("StringValue", 7, (25.0, 210.0, 240.0), (55.0, 220.0, 260.0)),
    ("BytesValue", 6, (35.0, 230.0, 250.0), (70.0, 240.0, 280.0)),
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
        "JSON parse",
        ("generated JSON parse",),
        {
            "c++ protobuf": ("c++ protobuf JSON parse", "c++ protobuf JSON parse reuse"),
            "go protobuf": ("go protobuf JSON parse",),
        },
    ),
    *json_workload_pair("Any WKT"),
    *json_workload_pair("Any NegativeDuration WKT"),
    *json_workload_pair("Any FractionalNegativeDuration WKT"),
    *json_workload_pair("Any MaxDuration WKT"),
    *json_workload_pair("Any MinDuration WKT"),
    *json_workload_pair("Any ZeroDuration WKT"),
    *json_workload_pair("Any FieldMask WKT"),
    *json_workload_pair("Any Timestamp WKT"),
    *json_workload_pair("Any PreEpoch Timestamp WKT"),
    *json_workload_pair("Any Max Timestamp WKT"),
    *json_workload_pair("Any Min Timestamp WKT"),
    *json_workload_pair("Any Empty WKT"),
    *json_workload_pair("Any Struct WKT"),
    *json_workload_pair("Any Value WKT"),
    *json_workload_pair("Any DoubleValue WKT"),
    *json_workload_pair("Any DoubleValue NaN WKT"),
    *json_workload_pair("Any DoubleValue Infinity WKT"),
    *json_workload_pair("Any DoubleValue NegativeInfinity WKT"),
    *json_workload_pair("Any FloatValue WKT"),
    *json_workload_pair("Any FloatValue NaN WKT"),
    *json_workload_pair("Any FloatValue Infinity WKT"),
    *json_workload_pair("Any FloatValue NegativeInfinity WKT"),
    *json_workload_pair("Any Int64Value WKT"),
    *json_workload_pair("Any NegativeInt64Value WKT"),
    *json_workload_pair("Any UInt64Value WKT"),
    *json_workload_pair("Any MaxUInt64Value WKT"),
    *json_workload_pair("Any Int32Value WKT"),
    *json_workload_pair("Any NegativeInt32Value WKT"),
    *json_workload_pair("Any UInt32Value WKT"),
    *json_workload_pair("Any MaxUInt32Value WKT"),
    *json_workload_pair("Any BoolValue WKT"),
    *json_workload_pair("Any StringValue WKT"),
    *json_workload_pair("Any BytesValue WKT"),
    *json_workload_pair("Nested Any WKT"),
    *json_workload_pair("Duration"),
    *json_workload_pair("NegativeDuration"),
    *json_workload_pair("FractionalNegativeDuration"),
    *json_workload_pair("MaxDuration"),
    *json_workload_pair("MinDuration"),
    *json_workload_pair("ZeroDuration"),
    *json_workload_pair("FieldMask"),
    *json_workload_pair("Timestamp"),
    *json_workload_pair("PreEpoch Timestamp"),
    *json_workload_pair("Max Timestamp"),
    *json_workload_pair("Min Timestamp"),
    *json_workload_pair("Empty"),
    *json_workload_pair("Struct"),
    *json_workload_pair("Value"),
    *json_workload_pair("ListValue"),
    *json_workload_pair("DoubleValue"),
    *json_workload_pair("DoubleValue NaN"),
    *json_workload_pair("DoubleValue Infinity"),
    *json_workload_pair("DoubleValue NegativeInfinity"),
    *json_workload_pair("FloatValue"),
    *json_workload_pair("FloatValue NaN"),
    *json_workload_pair("FloatValue Infinity"),
    *json_workload_pair("FloatValue NegativeInfinity"),
    *json_workload_pair("Int64Value"),
    *json_workload_pair("NegativeInt64Value"),
    *json_workload_pair("UInt64Value"),
    *json_workload_pair("MaxUInt64Value"),
    *json_workload_pair("Int32Value"),
    *json_workload_pair("NegativeInt32Value"),
    *json_workload_pair("UInt32Value"),
    *json_workload_pair("MaxUInt32Value"),
    *json_workload_pair("BoolValue"),
    *json_workload_pair("StringValue"),
    *json_workload_pair("BytesValue"),
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
    ]
    for label, bytes_per_iter, stringify_ns, parse_ns in JSON_SELF_TEST_SPECS:
        sample_lines.extend(json_sample_pair(label, bytes_per_iter, stringify_ns, parse_ns))
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


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", nargs="?", help="run_compare output log; stdin is used when omitted")
    parser.add_argument("--fail-on-loss", action="store_true", help="exit non-zero if any parsed row is a pbz loss or missing baseline")
    parser.add_argument("--self-test", action="store_true", help="run parser self-test")
    args = parser.parse_args(argv)

    if args.self_test:
        self_test()
        return 0

    if args.log:
        text = Path(args.log).read_text(encoding="utf-8")
    else:
        text = sys.stdin.read()
    output, has_loss = summarize(parse_results(text))
    print(output)
    return 1 if args.fail_on_loss and has_loss else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
