#!/usr/bin/env python3
"""Validate repository-local Markdown links without making network requests."""

from __future__ import annotations

import re
import sys
import urllib.parse
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LINK_RE = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")
HEADING_RE = re.compile(r"^#{1,6}\s+(.+?)\s*#*\s*$")
EXTERNAL_SCHEMES = ("http://", "https://", "mailto:", "tel:")


def github_slug(heading: str) -> str:
    heading = re.sub(r"<[^>]+>", "", heading).strip().lower()
    heading = re.sub(r"[^\w\- ]", "", heading, flags=re.UNICODE)
    return re.sub(r"-+", "-", heading.replace(" ", "-"))


def anchors_for(path: Path) -> set[str]:
    anchors: set[str] = set()
    counts: dict[str, int] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        match = HEADING_RE.match(line)
        if not match:
            continue
        base = github_slug(match.group(1))
        count = counts.get(base, 0)
        counts[base] = count + 1
        anchors.add(base if count == 0 else f"{base}-{count}")
    return anchors


def destination_only(raw: str) -> str:
    raw = raw.strip()
    if raw.startswith("<") and ">" in raw:
        return raw[1 : raw.index(">")]
    return raw.split(maxsplit=1)[0]


def main() -> int:
    errors: list[str] = []
    markdown_files = sorted(ROOT.rglob("*.md"))

    for source in markdown_files:
        text = source.read_text(encoding="utf-8")
        for match in LINK_RE.finditer(text):
            destination = destination_only(match.group(1))
            if not destination or destination.startswith(EXTERNAL_SCHEMES):
                continue

            path_text, separator, fragment = destination.partition("#")
            decoded_path = urllib.parse.unquote(path_text)
            if decoded_path:
                target = (source.parent / decoded_path).resolve()
            else:
                target = source.resolve()

            try:
                target.relative_to(ROOT)
            except ValueError:
                errors.append(f"{source.relative_to(ROOT)}: link escapes repository: {destination}")
                continue

            if not target.exists():
                errors.append(f"{source.relative_to(ROOT)}: missing target: {destination}")
                continue

            if separator and fragment and target.is_file() and target.suffix.lower() == ".md":
                decoded_fragment = urllib.parse.unquote(fragment).lower()
                if decoded_fragment not in anchors_for(target):
                    errors.append(
                        f"{source.relative_to(ROOT)}: missing anchor #{fragment} in {target.relative_to(ROOT)}"
                    )

    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1

    print(f"PASS: local Markdown links ({len(markdown_files)} files)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
