#!/usr/bin/env python3
"""Validate committed SVG diagrams for XML safety and accessibility."""

from __future__ import annotations

import sys
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SVG_NAMESPACE = "http://www.w3.org/2000/svg"
XLINK_NAMESPACE = "http://www.w3.org/1999/xlink"


def local_name(tag: str) -> str:
    return tag.rsplit("}", maxsplit=1)[-1]


def main() -> int:
    errors: list[str] = []
    svg_files = sorted((ROOT / "diagrams").glob("*.svg"))
    if not svg_files:
        print("No SVG diagrams found", file=sys.stderr)
        return 1

    for path in svg_files:
        relative = path.relative_to(ROOT)
        try:
            tree = ET.parse(path)
        except ET.ParseError as error:
            errors.append(f"{relative}: invalid XML: {error}")
            continue

        root = tree.getroot()
        if root.tag != f"{{{SVG_NAMESPACE}}}svg":
            errors.append(f"{relative}: root element is not an SVG")
        if not root.get("viewBox"):
            errors.append(f"{relative}: missing viewBox")
        if not root.get("role"):
            errors.append(f"{relative}: missing accessibility role")

        titles = [element for element in root.iter() if local_name(element.tag) == "title"]
        descriptions = [element for element in root.iter() if local_name(element.tag) == "desc"]
        if not any("".join(element.itertext()).strip() for element in titles):
            errors.append(f"{relative}: missing non-empty title")
        if not any("".join(element.itertext()).strip() for element in descriptions):
            errors.append(f"{relative}: missing non-empty description")

        for element in root.iter():
            name = local_name(element.tag)
            if name in {"script", "foreignObject"}:
                errors.append(f"{relative}: disallowed <{name}> element")
            for attribute in element.attrib:
                if local_name(attribute).lower().startswith("on"):
                    errors.append(f"{relative}: disallowed event-handler attribute {attribute}")
            href = element.get("href") or element.get(f"{{{XLINK_NAMESPACE}}}href")
            if href and href.startswith(("http://", "https://", "//", "data:", "javascript:")):
                errors.append(f"{relative}: disallowed external or embedded-raster reference")

        source = path.with_suffix(".mmd")
        if not source.is_file():
            errors.append(f"{relative}: missing editable Mermaid source {source.name}")

    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1

    print(f"PASS: accessible SVG XML ({len(svg_files)} files)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
