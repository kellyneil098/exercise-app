"""Generates the app icon ("Kettlebell buddy": a brass kettlebell with the mannequin's eyes, brows and smile).

    python3 tools/icon/app_icon.py            # writes the 1024x1024 PNG into the AppIcon asset catalog
    python3 tools/icon/app_icon.py out.png    # or anywhere else

The SVG is rendered with headless Chrome so the output matches what the review page showed. iOS applies its own
rounded mask, so the PNG is square, full-bleed and opaque (no alpha, no pre-rounded corners). Colours are the
Theme.swift tokens: canvas #0B0B0C and brass #D4B275.
"""
from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT = ROOT / "ios/WorkoutApp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
SIZE = 1024
CANVAS, BRASS = "#0B0B0C", "#D4B275"


def icon_svg() -> str:
    cx, cy, r = 512, 630, 296       # body
    stroke = CANVAS
    face = (
        f'<circle cx="{cx - 92}" cy="{cy - 44}" r="38" fill="{stroke}"/>'
        f'<circle cx="{cx + 92}" cy="{cy - 44}" r="38" fill="{stroke}"/>'
        f'<path d="M{cx - 156} {cy - 122} Q{cx - 92} {cy - 156} {cx - 28} {cy - 122}" fill="none" stroke="{stroke}" stroke-width="32" stroke-linecap="round"/>'
        f'<path d="M{cx + 28} {cy - 122} Q{cx + 92} {cy - 156} {cx + 156} {cy - 122}" fill="none" stroke="{stroke}" stroke-width="32" stroke-linecap="round"/>'
        f'<path d="M{cx - 78} {cy + 70} Q{cx} {cy + 150} {cx + 78} {cy + 70}" fill="none" stroke="{stroke}" stroke-width="32" stroke-linecap="round"/>'
    )
    handle = (f'<path d="M{cx - 178} {cy - 200} C{cx - 250} {cy - 580} {cx + 250} {cy - 580} {cx + 178} {cy - 200}" '
              f'fill="none" stroke="{BRASS}" stroke-width="92" stroke-linecap="round"/>')
    body = f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{BRASS}"/>'
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{SIZE}" height="{SIZE}" viewBox="0 0 {SIZE} {SIZE}">'
            f'<rect width="{SIZE}" height="{SIZE}" fill="{CANVAS}"/>{handle}{body}{face}</svg>')


def render(svg: str, out: Path) -> None:
    with tempfile.TemporaryDirectory() as td:
        page = Path(td) / "icon.html"
        page.write_text(f'<html><body style="margin:0;background:{CANVAS}">{svg}</body></html>')
        shot = Path(td) / "shot.png"
        subprocess.run(["google-chrome", "--headless=new", "--no-sandbox", "--disable-gpu", "--hide-scrollbars",
                        f"--user-data-dir={td}/profile", f"--window-size={SIZE},{SIZE}", f"--screenshot={shot}",
                        f"file://{page}"], check=True, capture_output=True)
        im = Image.open(shot).convert("RGB")       # App Store icons must be opaque
        assert im.size == (SIZE, SIZE), im.size
        out.parent.mkdir(parents=True, exist_ok=True)
        im.save(out, "PNG", optimize=True)


if __name__ == "__main__":
    target = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_OUT
    render(icon_svg(), target)
    print(target)
