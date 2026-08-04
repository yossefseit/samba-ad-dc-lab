# Architecture diagram

`samba-ad-dc-architecture.mmd` is the editable source of truth. The committed SVG is the accessible, optimized export used by the root README.

Regenerate both deterministically with the pinned tools:

```bash
npx --yes @mermaid-js/mermaid-cli@11.12.0 \
  --configFile diagrams/mermaid-config.json \
  --input diagrams/samba-ad-dc-architecture.mmd \
  --output diagrams/samba-ad-dc-architecture.svg \
  --backgroundColor transparent \
  --width 1600
npx --yes svgo@4.0.0 --config diagrams/svgo.config.mjs \
  --input diagrams/samba-ad-dc-architecture.svg \
  --output diagrams/samba-ad-dc-architecture.svg
python3 tests/check_svg.py
```

The Mermaid accessibility directives supply the SVG title and description. HTML labels are disabled so the export remains native SVG without `foreignObject` content.
