#!/usr/bin/env python3
"""Generate the 1024x1024 iOS app icon for Tech Flow Runner.

Renders the neon "runner" mark on a dark radial-gradient background that
matches the in-app Theme palette. The artwork is drawn at 4x and downscaled
for clean anti-aliasing, and saved as a fully opaque RGB PNG (no alpha) as
required for App Store icons.

Usage: python3 generate_app_icon.py
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "TechFlowRunner" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon-1024.png"

SIZE = 1024
SS = 4  # supersample factor
S = SIZE * SS

# Theme palette (see TechFlowRunner/UI/Theme.swift)
BG_EDGE = (3, 6, 15)        # 0x03060F
BG_CENTER = (22, 44, 96)    # brighter navy core for depth
CYAN = (46, 248, 255)       # 0x2EF8FF
RUNNER = (233, 246, 255)    # 0xE9F6FF


def lerp(a: int, b: int, t: float) -> int:
    return int(round(a + (b - a) * t))


def make_background() -> Image.Image:
    """Radial gradient from a bright navy core to the near-black Theme bg."""
    img = Image.new("RGB", (S, S))
    px = img.load()
    cx = cy = S / 2
    max_d = (cx ** 2 + cy ** 2) ** 0.5
    for y in range(S):
        for x in range(S):
            d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5 / max_d
            t = min(1.0, d * 1.15)
            px[x, y] = (
                lerp(BG_CENTER[0], BG_EDGE[0], t),
                lerp(BG_CENTER[1], BG_EDGE[1], t),
                lerp(BG_CENTER[2], BG_EDGE[2], t),
            )
    return img


def draw_glow(base: Image.Image, painter, blur: int, passes: int = 1) -> None:
    """Draw `painter` onto a transparent layer, blur it, and composite for glow."""
    for _ in range(passes):
        layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        painter(ImageDraw.Draw(layer))
        layer = layer.filter(ImageFilter.GaussianBlur(blur))
        base.paste(layer, (0, 0), layer)


def main() -> None:
    img = make_background().convert("RGBA")

    # Layout in a 180-unit design space, scaled up to the supersampled canvas.
    u = S / 180.0

    def P(x: float, y: float) -> tuple[float, float]:
        return (x * u, y * u)

    # --- Neon platform bar near the bottom ---
    bar_top, bar_bot = 134 * u, 146 * u
    bar_l, bar_r = 30 * u, 150 * u
    radius = (bar_bot - bar_top) / 2

    def paint_bar(d: ImageDraw.ImageDraw, color) -> None:
        d.rounded_rectangle([bar_l, bar_top, bar_r, bar_bot], radius=radius, fill=color)

    # soft outer glow, then the crisp neon bar on top
    draw_glow(img, lambda d: paint_bar(d, (*CYAN, 180)), blur=int(16 * u), passes=2)
    paint_bar(ImageDraw.Draw(img), (*CYAN, 255))

    # --- Runner stick figure ---
    cap = int(6 * u)  # limb half-thickness

    def paint_runner(d: ImageDraw.ImageDraw, color, t: int) -> None:
        def seg(p0, p1):
            d.line([P(*p0), P(*p1)], fill=color, width=t * 2, joint="curve")
            for p in (p0, p1):
                cx, cy = P(*p)
                d.ellipse([cx - t, cy - t, cx + t, cy + t], fill=color)

        # head
        hx, hy, hr = 96 * u, 50 * u, 15 * u
        d.ellipse([hx - hr, hy - hr, hx + hr, hy + hr], fill=color)
        # torso
        seg((96, 66), (86, 100))
        # legs (running stride)
        seg((86, 100), (60, 120))
        seg((86, 100), (112, 126))
        # arms (driving forward/back)
        seg((90, 80), (118, 86))
        seg((90, 82), (66, 70))

    # glow pass then crisp pass
    draw_glow(img, lambda d: paint_runner(d, (*CYAN, 110), cap), blur=int(10 * u))
    paint_runner(ImageDraw.Draw(img), (*RUNNER, 255), cap)

    # Downscale for anti-aliasing and flatten to opaque RGB.
    final = img.convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    final.save(OUT, "PNG")
    print(f"Wrote {OUT} ({final.size[0]}x{final.size[1]}, mode={final.mode})")


if __name__ == "__main__":
    main()
