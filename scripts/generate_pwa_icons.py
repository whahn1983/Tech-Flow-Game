#!/usr/bin/env python3
"""Generate PNG app icons from built-in runner artwork (no external deps)."""

from __future__ import annotations

import binascii
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def write_png(path: Path, size: int) -> None:
    w = h = size
    pix = bytearray([0, 0, 0, 0]) * (w * h)

    def set_px(x: int, y: int, r: int, g: int, b: int, a: int = 255) -> None:
        if 0 <= x < w and 0 <= y < h:
            i = (y * w + x) * 4
            pix[i : i + 4] = bytes((r, g, b, a))

    cx = cy = w / 2
    for y in range(h):
        for x in range(w):
            dx = (x - cx) / w
            dy = (y - cy) / h
            d = (dx * dx + dy * dy) ** 0.5
            t = min(1, max(0, d * 2.2))
            r = int(25 * (1 - t) + 5 * t)
            g = int(45 * (1 - t) + 9 * t)
            b = int(95 * (1 - t) + 28 * t)
            set_px(x, y, r, g, b, 255)

    for y in range(int(h * 0.78), int(h * 0.86)):
        for x in range(int(w * 0.12), int(w * 0.88)):
            set_px(x, y, 46, 248, 255, 235)

    scale = w / 180

    def circle(cx: int, cy: int, rad: int, color: tuple[int, int, int, int]) -> None:
        for y in range(int(cy - rad), int(cy + rad) + 1):
            for x in range(int(cx - rad), int(cx + rad) + 1):
                if (x - cx) ** 2 + (y - cy) ** 2 <= rad * rad:
                    set_px(x, y, *color)

    def line(x0: float, y0: float, x1: float, y1: float, t: int, color: tuple[int, int, int, int]) -> None:
        steps = int(max(abs(x1 - x0), abs(y1 - y0)) * 2) + 1
        for i in range(steps + 1):
            p = i / steps
            x = x0 + (x1 - x0) * p
            y = y0 + (y1 - y0) * p
            for yy in range(int(y - t), int(y + t) + 1):
                for xx in range(int(x - t), int(x + t) + 1):
                    if (xx - x) ** 2 + (yy - y) ** 2 <= t * t:
                        set_px(xx, yy, *color)

    c = (235, 246, 255, 255)
    circle(int(92 * scale), int(54 * scale), int(13 * scale), c)
    thickness = max(1, int(5 * scale))
    line(92 * scale, 70 * scale, 84 * scale, 98 * scale, thickness, c)
    line(84 * scale, 98 * scale, 62 * scale, 118 * scale, thickness, c)
    line(84 * scale, 98 * scale, 109 * scale, 124 * scale, thickness, c)
    line(87 * scale, 82 * scale, 112 * scale, 86 * scale, thickness, c)
    line(87 * scale, 84 * scale, 68 * scale, 72 * scale, thickness, c)

    raw = bytearray()
    for y in range(h):
        raw.append(0)
        start = y * w * 4
        raw.extend(pix[start : start + w * 4])

    comp = zlib.compress(bytes(raw), 9)

    def chunk(typ: bytes, data: bytes) -> bytes:
        crc = binascii.crc32(typ + data) & 0xFFFFFFFF
        return struct.pack("!I", len(data)) + typ + data + struct.pack("!I", crc)

    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack("!IIBBBBB", w, h, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", comp)
        + chunk(b"IEND", b"")
    )

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)


def main() -> None:
    write_png(ROOT / "apple-touch-icon.png", 180)
    write_png(ROOT / "icons" / "icon-192.png", 192)
    write_png(ROOT / "icons" / "icon-512.png", 512)
    print("Generated apple-touch-icon.png, icons/icon-192.png, icons/icon-512.png")


if __name__ == "__main__":
    main()
