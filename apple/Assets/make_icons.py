"""
Generates the YouTube Library app icon and launch-screen logo from scratch
so the repo doesn't have to commit a separate design tool. Run this script
once after changing the design constants below — it writes:

  Assets.xcassets/AppIcon.appiconset/icon-1024.png  (App Store source)
  Assets.xcassets/LaunchLogo.imageset/launch-logo.png  (transparent)

Usage (from apple/):
  python3 Assets/make_icons.py
"""

from __future__ import annotations

import os
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


# ----------------------------------------------------------------------------
# Design constants — change here, rerun the script.
# ----------------------------------------------------------------------------

# Warm music-app red (Tailwind rose-600). Used for the icon background and
# for the LaunchBackground color set.
BG_TOP = (244, 63, 94)      # rose-500
BG_BOTTOM = (190, 18, 60)   # rose-700

FG_WHITE = (255, 255, 255, 255)


def vertical_gradient(size: int, top: tuple, bottom: tuple) -> Image.Image:
    """Solid RGB image with a smooth vertical gradient from top to bottom."""
    img = Image.new("RGB", (size, size), top)
    px = img.load()
    for y in range(size):
        t = y / (size - 1)
        r = round(top[0] * (1 - t) + bottom[0] * t)
        g = round(top[1] * (1 - t) + bottom[1] * t)
        b = round(top[2] * (1 - t) + bottom[2] * t)
        for x in range(size):
            px[x, y] = (r, g, b)
    return img


def play_triangle_mask(size: int, fill_color=FG_WHITE) -> Image.Image:
    """Centred white right-pointing play triangle on a transparent canvas."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    cx, cy = size / 2, size / 2
    r = size * 0.34

    # Equilateral-ish triangle pointing right. Slight optical centring
    # nudge: the apparent centroid of a right-pointing triangle is
    # shifted left of geometric centre.
    cx -= size * 0.025

    points = [
        (cx - r * 0.6, cy - r),
        (cx - r * 0.6, cy + r),
        (cx + r, cy),
    ]
    draw.polygon(points, fill=fill_color)
    return img


def round_corners(img: Image.Image, radius: int) -> Image.Image:
    """Return a copy with rounded corners (transparent outside)."""
    size = img.size
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [(0, 0), (size[0] - 1, size[1] - 1)], radius=radius, fill=255
    )
    out = Image.new("RGBA", size, (0, 0, 0, 0))
    out.paste(img.convert("RGBA"), (0, 0), mask)
    return out


# ----------------------------------------------------------------------------
# Build the App Icon (1024 × 1024 PNG, no transparency).
# ----------------------------------------------------------------------------

def build_app_icon(out_path: Path) -> None:
    size = 1024
    bg = vertical_gradient(size, BG_TOP, BG_BOTTOM)

    # Subtle radial-ish highlight so the icon doesn't read flat.
    highlight = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    hd = ImageDraw.Draw(highlight)
    hd.ellipse(
        [(-size * 0.4, -size * 0.6), (size * 1.4, size * 0.4)],
        fill=(255, 255, 255, 50),
    )
    highlight = highlight.filter(ImageFilter.GaussianBlur(radius=size * 0.06))
    bg = Image.alpha_composite(bg.convert("RGBA"), highlight)

    triangle = play_triangle_mask(size)
    # Drop shadow under the triangle.
    shadow = play_triangle_mask(size, fill_color=(0, 0, 0, 110)).filter(
        ImageFilter.GaussianBlur(radius=size * 0.012)
    )
    shadow_offset = round(size * 0.006)
    icon = bg.copy()
    icon.alpha_composite(shadow, dest=(0, shadow_offset))
    icon.alpha_composite(triangle)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    # App Icon must be opaque — strip the alpha.
    icon.convert("RGB").save(out_path, "PNG", optimize=True)


# ----------------------------------------------------------------------------
# Build the Launch Logo (transparent PNG with just the triangle).
# ----------------------------------------------------------------------------

def build_launch_logo(out_path: Path) -> None:
    size = 600
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    triangle = play_triangle_mask(size)
    canvas.alpha_composite(triangle)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out_path, "PNG", optimize=True)


# ----------------------------------------------------------------------------

if __name__ == "__main__":
    here = Path(__file__).parent.parent
    assets = here / "Assets.xcassets"
    build_app_icon(assets / "AppIcon.appiconset" / "icon-1024.png")
    build_launch_logo(assets / "LaunchLogo.imageset" / "launch-logo.png")
    print("Wrote:")
    print(" ", assets / "AppIcon.appiconset" / "icon-1024.png")
    print(" ", assets / "LaunchLogo.imageset" / "launch-logo.png")
