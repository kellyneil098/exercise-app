"""Generates the app icon ("Hunny-pot kettlebell": a Hundred-Acre-Wood honey pot with a kettlebell handle).

    python3 tools/icon/app_icon.py            # writes the 1024x1024 PNG into the AppIcon asset catalog
    python3 tools/icon/app_icon.py out.png    # or anywhere else
    python3 tools/icon/app_icon.py --svg      # prints the SVG instead (handy for tweaking in a browser)

The drawing is original vector art in a storybook ink-line style: a round-bellied paper-white pot with a honey
kettlebell handle, honey dripping over the rim, a rotated "HUNNY" label and one bee on a dotted flight path, on
parchment with a soft honey watercolour wash. Palette = the Hundred Acre Wood theme tokens: parchment #FBF3E1,
paper #FFFBF2, ink #3B2A1A, honey #F2B134 / #E59A1C / #FFD56B, sky #A9D3EA.

The SVG is rendered with headless Chrome (google-chrome / chromium on PATH, or the macOS app bundle); if no Chrome
is found it falls back to rsvg-convert or cairosvg. iOS applies its own rounded mask, so the PNG is square,
full-bleed and opaque (no alpha, no pre-rounded corners).
"""
from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT = ROOT / "ios/WorkoutApp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
SIZE = 1024
CREAM, PAPER, INK = "#FBF3E1", "#FFFBF2", "#3B2A1A"
HONEY, HONEY_DEEP, HONEY_LIGHT, SKY = "#F2B134", "#E59A1C", "#FFD56B", "#A9D3EA"
FONT = "'Chalkboard SE','Marker Felt','Comic Sans MS',cursive"
CHROME_CANDIDATES = ["google-chrome", "google-chrome-stable", "chromium", "chromium-browser",
                     "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"]


def bee(x: int, y: int) -> str:
    return (f'<g transform="translate({x} {y})">'
            f'<ellipse cx="-14" cy="-40" rx="30" ry="18" fill="{SKY}" stroke="{INK}" stroke-width="8" transform="rotate(-25)"/>'
            f'<ellipse cx="18" cy="-42" rx="26" ry="16" fill="{SKY}" stroke="{INK}" stroke-width="8" transform="rotate(20)"/>'
            f'<clipPath id="bee"><ellipse cx="0" cy="0" rx="46" ry="32"/></clipPath>'
            f'<ellipse cx="0" cy="0" rx="46" ry="32" fill="{HONEY_LIGHT}"/>'
            f'<g clip-path="url(#bee)" fill="{INK}"><rect x="-22" y="-40" width="16" height="80"/><rect x="8" y="-40" width="16" height="80"/></g>'
            f'<ellipse cx="0" cy="0" rx="46" ry="32" fill="none" stroke="{INK}" stroke-width="9"/>'
            f'<circle cx="-50" cy="-4" r="20" fill="{INK}"/><circle cx="-56" cy="-10" r="4" fill="{PAPER}"/>'
            f'<path d="M44 0 L62 -6" stroke="{INK}" stroke-width="7" stroke-linecap="round"/></g>')


def icon_svg() -> str:
    defs = (f'<radialGradient id="paper" cx="50%" cy="45%" r="70%"><stop offset="0" stop-color="{PAPER}"/>'
            f'<stop offset="1" stop-color="{CREAM}"/></radialGradient>'
            '<filter id="wash" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="38"/></filter>')
    wash = f'<ellipse cx="512" cy="640" rx="330" ry="300" fill="{HONEY_LIGHT}" opacity="0.55" filter="url(#wash)"/>'
    arc = "M400 392 C 400 120, 624 120, 624 392"
    handle = (f'<path d="{arc}" fill="none" stroke="{INK}" stroke-width="108" stroke-linecap="round"/>'
              f'<path d="{arc}" fill="none" stroke="{HONEY_DEEP}" stroke-width="64" stroke-linecap="round"/>'
              f'<path d="M418 340 C 428 153, 596 153, 606 340" fill="none" stroke="{HONEY_LIGHT}" stroke-width="14" '
              'stroke-linecap="round" opacity="0.9"/>')
    body = ('<path d="M388 420 C 300 470, 226 560, 236 670 C 246 800, 300 886, 356 904 C 440 926, 584 926, 668 904 '
            'C 724 886, 778 800, 788 670 C 798 560, 724 470, 636 420 Z" '
            f'fill="{PAPER}" stroke="{INK}" stroke-width="20" stroke-linejoin="round"/>')
    rim = f'<rect x="346" y="336" width="332" height="96" rx="42" fill="{PAPER}" stroke="{INK}" stroke-width="20"/>'
    honey = ('<path d="M346 384 C 372 318, 652 318, 678 384 L 678 400 C 678 440, 650 440, 650 404 L 650 396 '
             'L 604 396 C 604 540, 556 540, 556 396 L 520 396 C 520 450, 486 450, 486 396 L 430 396 C 430 500, 392 500, 392 396 '
             'L 374 396 C 374 426, 346 426, 346 400 Z" '
             f'fill="{HONEY}" stroke="{INK}" stroke-width="18" stroke-linejoin="round"/>'
             f'<path d="M410 366 C 450 336, 574 336, 614 366" fill="none" stroke="{HONEY_LIGHT}" stroke-width="14" stroke-linecap="round"/>')
    label = (f'<g transform="rotate(-3 512 705)"><rect x="352" y="640" width="320" height="130" rx="50" fill="{CREAM}" '
             f'stroke="{INK}" stroke-width="16"/><text x="512" y="738" text-anchor="middle" font-family="{FONT}" '
             f'font-weight="700" font-size="84" fill="{INK}">HUNNY</text></g>')
    flight = (f'<path d="M700 300 C 760 240, 860 250, 850 180" fill="none" stroke="{INK}" stroke-width="7" '
              'stroke-dasharray="2 22" stroke-linecap="round" opacity="0.8"/>')
    art = f'<g transform="translate(512 528) scale(1.08) translate(-512 -528)">{handle}{body}{rim}{honey}{label}</g>'
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{SIZE}" height="{SIZE}" viewBox="0 0 {SIZE} {SIZE}">'
            f'<defs>{defs}</defs><rect width="{SIZE}" height="{SIZE}" fill="url(#paper)"/>'
            f'{wash}{art}{flight}{bee(850, 160)}</svg>')


def find_chrome() -> str | None:
    for c in CHROME_CANDIDATES:
        if Path(c).is_file() or shutil.which(c):
            return c
    return None


def render(svg: str, out: Path) -> None:
    with tempfile.TemporaryDirectory() as td:
        shot = Path(td) / "shot.png"
        if chrome := find_chrome():
            page = Path(td) / "icon.html"
            page.write_text(f'<html><body style="margin:0;background:{CREAM}">{svg}</body></html>')
            subprocess.run([chrome, "--headless=new", "--no-sandbox", "--disable-gpu", "--hide-scrollbars",
                            f"--user-data-dir={td}/profile", f"--window-size={SIZE},{SIZE}", f"--screenshot={shot}",
                            f"file://{page}"], check=True, capture_output=True, timeout=120)
        elif shutil.which("rsvg-convert"):
            subprocess.run(["rsvg-convert", "-w", str(SIZE), "-h", str(SIZE), "-o", str(shot)],
                           input=svg.encode(), check=True)
        else:
            import cairosvg  # type: ignore  # last resort: pip install cairosvg
            cairosvg.svg2png(bytestring=svg.encode(), write_to=str(shot), output_width=SIZE, output_height=SIZE)
        im = Image.open(shot).convert("RGB")       # App Store icons must be opaque
        assert im.size == (SIZE, SIZE), im.size
        out.parent.mkdir(parents=True, exist_ok=True)
        im.save(out, "PNG", optimize=True)


if __name__ == "__main__":
    if "--svg" in sys.argv:
        print(icon_svg())
        sys.exit(0)
    target = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_OUT
    render(icon_svg(), target)
    print(target)
