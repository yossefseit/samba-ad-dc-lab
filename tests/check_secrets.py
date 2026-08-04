#!/usr/bin/env python3
"""Catch common credential material in tracked and new repository files."""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PATTERNS = {
    "private key": re.compile("-----BEGIN" + r"(?: [A-Z0-9]+)? PRIVATE KEY-----"),
    "AWS access key": re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
    "GitHub token": re.compile(r"\bgh[pousr]_[A-Za-z0-9]{30,}\b"),
    "assigned secret": re.compile(
        r"\b(?:password|passwd|secret|token)\s*=\s*[\"'][^\"'<][^\"']{5,}[\"']",
        re.IGNORECASE,
    ),
}


def repository_files() -> list[Path]:
    output = subprocess.check_output(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        cwd=ROOT,
    )
    return [ROOT / name.decode() for name in output.split(b"\0") if name]


def main() -> int:
    findings: list[str] = []
    scanned = 0
    for path in repository_files():
        if not path.is_file() or ".git" in path.parts:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        scanned += 1
        for line_number, line in enumerate(text.splitlines(), start=1):
            for label, pattern in PATTERNS.items():
                if pattern.search(line):
                    findings.append(f"{path.relative_to(ROOT)}:{line_number}: possible {label}")

    if findings:
        print("\n".join(findings), file=sys.stderr)
        return 1
    print(f"PASS: common secret patterns ({scanned} text files)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
