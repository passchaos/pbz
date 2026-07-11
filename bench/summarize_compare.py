#!/usr/bin/env python3
"""Summarize pbz cross-language benchmark output.

Usage:
  bench/run_compare.sh 2>&1 | tee /tmp/pbz-compare.log
  python3 bench/summarize_compare.py /tmp/pbz-compare.log

The script parses the ``ns/op`` lines emitted by ``bench/run_compare.sh`` and
compares the fastest relevant pbz generated path against each available
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


@dataclass(frozen=True)
class Workload:
    name: str
    pbz: tuple[str, ...]
    baselines: dict[str, tuple[str, ...]]


WORKLOADS: tuple[Workload, ...] = (
    Workload(
        "binary encode",
        (
            "generated binary encode",
            "generated binary writeToAssumeCapacity reuse",
            "generated binary encodeIntoAssumeCapacity buffer reuse",
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
        ("generated binary decode",),
        {
            "rust prost": ("prost binary decode",),
            "rust quick-protobuf": ("quick-protobuf binary decode",),
            "c++ protobuf": ("c++ protobuf binary decode", "c++ protobuf binary decode reuse"),
            "go protobuf": ("go protobuf binary decode",),
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
        ("generated packed decode",),
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
        ("generated fixed32 packed decode", "wire fixed32 packed borrowed view decode"),
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
        ("generated fixed64 packed decode", "wire fixed64 packed borrowed view decode"),
        {
            "rust prost": ("prost fixed64 packed decode",),
            "rust quick-protobuf": ("quick-protobuf fixed64 packed decode",),
            "c++ protobuf": ("c++ protobuf fixed64 packed decode", "c++ protobuf fixed64 packed decode reuse"),
            "go protobuf": ("go protobuf fixed64 packed decode",),
        },
    ),
)


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
    sample = """
    generated binary encodeIntoAssumeCapacity buffer reuse: best of 3 x 10 iters, 47 bytes/iter, 40.00 ns/op, 1 ops/s, 1 MiB/s
    generated binary decode: best of 3 x 10 iters, 47 bytes/iter, 200.00 ns/op, 1 ops/s, 1 MiB/s
    quick-protobuf binary encode reuse: best of 3 x 10 iters, 47 bytes/iter, 50.00 ns/op, 1 ops/s, 1 MiB/s
    quick-protobuf binary decode: best of 3 x 10 iters, 47 bytes/iter, 150.00 ns/op, 1 ops/s, 1 MiB/s
    """
    results = parse_results(sample)
    output, has_loss = summarize(results)
    assert "binary encode" in output
    assert "WIN" in output
    assert "LOSS" in output
    assert "Uncovered benchmark rows" in output
    assert has_loss


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
