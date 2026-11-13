#!/usr/bin/env python3
"""Merge benchmark logs by keeping the fastest ns/op row per benchmark name.

Usage:
  python3 bench/merge_best.py /tmp/run1.log /tmp/run2.log ... > /tmp/best.log

On shared machines a single long benchmark run can be inflated by a load spike.
Running the same binaries several times and keeping the fastest observed row per
name gives a more stable "achievable" comparison than any single run. Rows that
appear in only one log are passed through unchanged.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

LINE_RE = re.compile(
    r"^(?P<name>[^:]+): best of \d+ x \d+ iters, (?:\d+ bytes/iter, )?(?P<ns>[0-9.]+) ns/op"
)


def main(argv: list[str]) -> int:
    if not argv:
        print(__doc__, file=sys.stderr)
        return 2
    best: dict[str, tuple[float, str]] = {}
    order: list[str] = []
    for path in argv:
        for line in Path(path).read_text(encoding="utf-8", errors="replace").splitlines():
            match = LINE_RE.match(line.strip())
            if not match:
                continue
            name = match.group("name")
            ns = float(match.group("ns"))
            if name not in best:
                order.append(name)
                best[name] = (ns, line)
            elif ns < best[name][0]:
                best[name] = (ns, line)
    for name in order:
        print(best[name][1])
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
