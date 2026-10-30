"""Home-screen preview of the app icon: the 1024 render masked with an iOS squircle at 180/120/60 px on a light and
a dark mock, so legibility at tap-target size can be checked before committing.

    python3 tools/icon/preview.py [icon.png] [out.png]     # defaults: the asset-catalog PNG -> tools/icon/preview.png
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_ICON = ROOT / "ios/WorkoutApp/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
SIZES = (180, 120, 60)


def squircle_mask(size: int, n: float = 5.0, supersample: int = 4) -> Image.Image:
    s = size * supersample
    mask = Image.new("L", (s, s), 0)
    draw = ImageDraw.Draw(mask)
    a = s / 2
    for y in range(s):
        t = abs((y + 0.5 - a) / a)
        if t < 1:
            half = a * (1 - t**n) ** (1 / n)
            draw.line([(a - half, y), (a + half, y)], fill=255)
    return mask.resize((size, size), Image.LANCZOS)


def masked(icon: Image.Image, size: int) -> Image.Image:
    small = icon.resize((size, size), Image.LANCZOS).convert("RGBA")
    small.putalpha(squircle_mask(size))
    return small


def row(icon: Image.Image, background: tuple[int, int, int]) -> Image.Image:
    gap, pad = 48, 40
    width = sum(SIZES) + gap * (len(SIZES) - 1) + 2 * pad
    canvas = Image.new("RGBA", (width, SIZES[0] + 2 * pad), background + (255,))
    x = pad
    for size in SIZES:
        canvas.alpha_composite(masked(icon, size), (x, pad + (SIZES[0] - size) // 2))
        x += size + gap
    return canvas


def composite(icon: Image.Image) -> Image.Image:
    light, dark = row(icon, (229, 231, 237)), row(icon, (18, 18, 22))
    out = Image.new("RGBA", (light.width, light.height + dark.height))
    out.alpha_composite(light, (0, 0))
    out.alpha_composite(dark, (0, light.height))
    return out


if __name__ == "__main__":
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_ICON
    dst = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(__file__).with_name("preview.png")
    composite(Image.open(src).convert("RGB")).save(dst, "PNG", optimize=True)
    print(dst)
