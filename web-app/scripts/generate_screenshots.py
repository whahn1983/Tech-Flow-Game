#!/usr/bin/env python3
"""Generate PWA screenshot PNGs for Tech Flow Runner (no external deps).

Produces:
  screenshots/screenshot-wide.png   1280x720  (landscape / desktop)
  screenshots/screenshot-narrow.png 720x1280  (portrait  / mobile)
"""

from __future__ import annotations

import binascii
import math
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# ---------------------------------------------------------------------------
# Palette (matching game colours)
# ---------------------------------------------------------------------------
BG       = (10,  19,  48)   # #0a1330  – main background
BG_DARK  = (5,    9,  16)   # #050910
GROUND   = (22,  35,  63)   # #16233f
CYAN     = (46, 248, 255)   # #2ef8ff
PURPLE   = (142, 92, 255)   # #8e5cff
RED_OBS  = (255, 90, 124)   # #ff5a7c
PINK     = (255, 46, 220)
TEXT     = (233, 246, 255)  # #e9f6ff
YELLOW   = (255, 200,  50)
WHITE    = (255, 255, 255)
GREEN    = ( 30, 180,  30)


# ---------------------------------------------------------------------------
# Canvas
# ---------------------------------------------------------------------------
class Canvas:
    """Simple RGBA framebuffer with fast bulk-row operations."""

    def __init__(self, w: int, h: int) -> None:
        self.w = w
        self.h = h
        self.data = bytearray(w * h * 4)

    # -- direct write (no blend) -------------------------------------------
    def set(self, x: int, y: int, r: int, g: int, b: int, a: int = 255) -> None:
        if 0 <= x < self.w and 0 <= y < self.h:
            i = (y * self.w + x) * 4
            self.data[i:i + 4] = bytes((r, g, b, a))

    def fill_row(self, y: int, x0: int, x1: int,
                 r: int, g: int, b: int, a: int = 255) -> None:
        if y < 0 or y >= self.h:
            return
        x0 = max(0, x0)
        x1 = min(self.w, x1)
        if x1 <= x0:
            return
        segment = bytes((r, g, b, a)) * (x1 - x0)
        i = (y * self.w + x0) * 4
        self.data[i:i + len(segment)] = segment

    def fill_rect(self, x0: int, y0: int, x1: int, y1: int,
                  r: int, g: int, b: int, a: int = 255) -> None:
        for y in range(max(0, y0), min(self.h, y1)):
            self.fill_row(y, x0, x1, r, g, b, a)

    # -- alpha blend --------------------------------------------------------
    def blend(self, x: int, y: int, r: int, g: int, b: int, a: int) -> None:
        if a <= 0 or not (0 <= x < self.w and 0 <= y < self.h):
            return
        i = (y * self.w + x) * 4
        d = self.data
        sa = a / 255.0
        da = d[i + 3] / 255.0
        oa = sa + da * (1.0 - sa)
        if oa > 0.0:
            inv = 1.0 / oa
            d[i]     = max(0, min(255, int((r * sa + d[i]     * da * (1 - sa)) * inv)))
            d[i + 1] = max(0, min(255, int((g * sa + d[i + 1] * da * (1 - sa)) * inv)))
            d[i + 2] = max(0, min(255, int((b * sa + d[i + 2] * da * (1 - sa)) * inv)))
            d[i + 3] = max(0, min(255, int(oa * 255)))

    def blend_row(self, y: int, x0: int, x1: int,
                  r: int, g: int, b: int, a: int) -> None:
        for x in range(max(0, x0), min(self.w, x1)):
            self.blend(x, y, r, g, b, a)

    # -- PNG export ---------------------------------------------------------
    def save_png(self, path: Path) -> None:
        w, h = self.w, self.h
        raw = bytearray()
        for y in range(h):
            raw.append(0)
            raw.extend(self.data[y * w * 4:(y + 1) * w * 4])
        comp = zlib.compress(bytes(raw), 6)

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
        print(f"  Saved {path.relative_to(ROOT)}  ({w}x{h}, {len(png) // 1024} KB)")


# ---------------------------------------------------------------------------
# Pseudo-random (deterministic LCG)
# ---------------------------------------------------------------------------
class LCG:
    def __init__(self, seed: int = 42) -> None:
        self.state = seed & 0xFFFFFFFF

    def next(self) -> float:
        self.state = (self.state * 1664525 + 1013904223) & 0xFFFFFFFF
        return self.state / 0xFFFFFFFF

    def int_range(self, lo: int, hi: int) -> int:
        return lo + int(self.next() * (hi - lo))


# ---------------------------------------------------------------------------
# Terrain
# ---------------------------------------------------------------------------
def terrain_at(x_world: int, canvas_h: int, base_ratio: float = 0.75) -> int:
    base = canvas_h * base_ratio
    w1 = math.sin(x_world * 0.008) * canvas_h * 0.04
    w2 = math.sin(x_world * 0.020 + 1.3) * canvas_h * 0.025
    w3 = math.sin(x_world * 0.005 - 0.8) * canvas_h * 0.05
    return int(base + w1 + w2 + w3)


# ---------------------------------------------------------------------------
# Draw helpers
# ---------------------------------------------------------------------------
def draw_background_gradient(c: Canvas) -> None:
    """Vertical gradient: deep navy at top, very dark at edges."""
    for y in range(c.h):
        t = y / c.h  # 0 = top, 1 = bottom
        r = int(BG[0] * (1 - t * 0.25) + BG_DARK[0] * t * 0.25)
        g = int(BG[1] * (1 - t * 0.25) + BG_DARK[1] * t * 0.25)
        b = int(BG[2] * (1 - t * 0.25) + BG_DARK[2] * t * 0.25)
        c.fill_row(y, 0, c.w, r, g, b)


def draw_stars(c: Canvas, sky_h: int, seed: int = 42) -> None:
    rng = LCG(seed)
    count = c.w * sky_h // 600
    for _ in range(count):
        x = int(rng.next() * c.w)
        y = int(rng.next() * sky_h)
        bright = rng.int_range(80, 220)
        if rng.next() > 0.65:
            c.set(x, y, 46, bright, 255, bright)          # cyan-ish
        else:
            c.set(x, y, bright, bright, bright, bright)   # white


def draw_buildings(c: Canvas, sky_top: int, ground_y: int, seed: int = 7) -> None:
    """Simple silhouette skyline in two depth layers."""
    for layer in range(2):
        rng = LCG(seed + layer * 1000)
        x = 0
        while x < c.w:
            bw = rng.int_range(int(c.w * 0.04), int(c.w * 0.12))
            bh = rng.int_range(int((ground_y - sky_top) * 0.12),
                               int((ground_y - sky_top) * 0.60))
            by = ground_y - bh
            if layer == 0:
                br, bg, bb = 18, 12, 52
            else:
                br, bg, bb = 24, 17, 68
            c.fill_rect(x, by, x + bw, ground_y, br, bg, bb)
            # Windows
            wrng = LCG(rng.int_range(0, 99999))
            for wy in range(by + 5, ground_y - 5, 9):
                for wx in range(x + 4, x + bw - 4, 9):
                    if wrng.next() > 0.52:
                        if wrng.next() > 0.5:
                            c.set(wx, wy, 180, 220, 90, 130)
                        else:
                            c.set(wx, wy, CYAN[0], CYAN[1], CYAN[2], 110)
            x += bw + rng.int_range(0, 8)


def draw_terrain_section(c: Canvas, x0: int, x1: int,
                         canvas_h: int, base_ratio: float,
                         x_offset: int = 0) -> list[int]:
    """Draw ground terrain for columns x0..x1. Returns list of terrain heights."""
    heights = []
    for x in range(x0, x1):
        ty = terrain_at(x + x_offset, canvas_h, base_ratio)
        heights.append(ty)
        # Fill ground below terrain
        for y in range(ty, canvas_h):
            t = min(1.0, (y - ty) / max(1, canvas_h - ty))
            r = int(GROUND[0] * (1 - t * 0.35))
            g = int(GROUND[1] * (1 - t * 0.35))
            b = int(GROUND[2] * (1 - t * 0.35))
            c.set(x, y, r, g, b)
        # Terrain surface glow
        for gy in range(max(0, ty - 3), min(canvas_h, ty + 2)):
            alpha = int(255 * max(0, 1 - abs(gy - ty) / 4.0))
            c.blend(x, gy, CYAN[0], CYAN[1], CYAN[2], alpha)
    return heights


def draw_ground_markers(c: Canvas, heights: list[int], x0: int,
                        spacing: int = 80, x_offset: int = 0) -> None:
    for mx in range(0, x0 + len(heights) + spacing, spacing):
        sx = mx - (x_offset % spacing)
        hx = sx - x0
        if hx < 0 or hx >= len(heights):
            continue
        ty = heights[hx]
        c.fill_rect(sx - 2, ty + 2, sx + 3, ty + 9,
                    CYAN[0], CYAN[1], CYAN[2], 200)


def draw_player(c: Canvas, px: int, py: int) -> None:
    pw, ph = 48, 58
    corner = 6
    for dy in range(ph):
        t = dy / ph
        r = int(CYAN[0] * (1 - t) + PURPLE[0] * t)
        g = int(CYAN[1] * (1 - t) + PURPLE[1] * t)
        b = int(CYAN[2] * (1 - t) + PURPLE[2] * t)
        for dx in range(pw):
            # Rounded-corner mask
            in_corner = False
            for cdx, cdy, lim in [
                (dx - corner,       dy - corner,       True),
                (dx - (pw-corner-1), dy - corner,      True),
                (dx - corner,       dy - (ph-corner-1), True),
                (dx - (pw-corner-1), dy - (ph-corner-1), True),
            ]:
                if (abs(cdx) > 0 or abs(cdy) > 0):
                    if cdx**2 + cdy**2 > corner**2:
                        # Only clip if we're in the corner zone
                        if abs(cdx) <= corner and abs(cdy) <= corner:
                            in_corner = True
                            break
            if not in_corner:
                c.set(px + dx, py + dy, r, g, b, 240)

    # Glow border
    for gy in range(py - 4, py + ph + 5):
        for gx in range(px - 4, px + pw + 5):
            dist = min(
                abs(gx - px) if gx < px else (abs(gx - px - pw + 1) if gx >= px + pw else pw),
                abs(gy - py) if gy < py else (abs(gy - py - ph + 1) if gy >= py + ph else ph),
            )
            if 0 < dist <= 4:
                alpha = int(70 * (1 - dist / 5.0))
                c.blend(gx, gy, CYAN[0], CYAN[1], CYAN[2], alpha)

    # </> symbol (pixel art, 3 strokes)
    cx = px + pw // 2
    cy = py + ph // 2
    for i in range(5):                          # "<"
        c.set(cx - 12 + i, cy - 4 + i, 255, 255, 255, 200)
        c.set(cx - 12 + i, cy + 4 - i, 255, 255, 255, 200)
    for i in range(9):                          # "/"
        c.set(cx - 3 + i, cy + 4 - i, 255, 255, 255, 200)
    for i in range(5):                          # ">"
        c.set(cx + 7 + i, cy - 4 + i, 255, 255, 255, 200)
        c.set(cx + 7 + i, cy + 4 - i, 255, 255, 255, 200)


def draw_server(c: Canvas, ox: int, oy: int) -> None:
    ow, oh = 36, 52
    c.fill_rect(ox, oy, ox + ow, oy + oh, RED_OBS[0], RED_OBS[1], RED_OBS[2])
    for sy in range(oy + 6, oy + oh - 4, 10):
        c.fill_rect(ox + 3, sy, ox + ow - 3, sy + 4, 30, 10, 20)
        c.set(ox + ow - 6, sy + 2, 46, 255, 100, 200)   # LED


def draw_laser(c: Canvas, ox: int, oy: int) -> None:
    ow, oh = 62, 24
    for dx in range(ow):
        t = dx / ow
        r = int(255 * (1 - t * 0.2))
        g = int(40 + t * 15)
        b = int(240 - t * 20)
        for dy in range(oh):
            edge = abs(dy - oh / 2) / (oh / 2)
            alpha = int(230 * (1 - edge * 0.55))
            c.blend(ox + dx, oy + dy, r, g, b, alpha)
    # outer glow
    for dx in range(ow):
        for glow in range(1, 5):
            a = int(55 / glow)
            c.blend(ox + dx, oy - glow, 255, 46, 200, a)
            c.blend(ox + dx, oy + oh + glow - 1, 255, 46, 200, a)


def draw_bug(c: Canvas, ox: int, oy: int) -> None:
    # Body (green ellipse)
    for dy in range(28):
        for dx in range(28):
            ex = (dx - 14) / 14
            ey = (dy - 14) / 10
            if ex * ex + ey * ey <= 1:
                c.blend(ox + dx, oy + dy, GREEN[0], GREEN[1], GREEN[2], 230)
    # Red head
    for dy in range(7):
        for dx in range(7):
            if (dx - 3) ** 2 + (dy - 3) ** 2 <= 10:
                c.set(ox + 11 + dx, oy + 1 + dy, 230, 30, 30)
    # Eyes
    c.set(ox + 11, oy + 3, 255, 255, 0)
    c.set(ox + 16, oy + 3, 255, 255, 0)
    # Antennae
    c.set(ox + 10, oy - 4, GREEN[0], GREEN[1], GREEN[2])
    c.set(ox + 10, oy - 3, GREEN[0], GREEN[1], GREEN[2])
    c.set(ox + 18, oy - 4, GREEN[0], GREEN[1], GREEN[2])
    c.set(ox + 18, oy - 3, GREEN[0], GREEN[1], GREEN[2])


def draw_drone(c: Canvas, ox: int, oy: int) -> None:
    """Drone – floats above ground (player must not jump)."""
    ow, oh = 72, 22
    # Main body
    for dy in range(oh):
        t = dy / oh
        r = int(200 + t * 30)
        g = int(170 + t * 10)
        b = int(20)
        c.fill_row(oy + dy, ox, ox + ow, r, g, b)
    # Slot on top
    c.fill_rect(ox + 10, oy + 3, ox + ow - 10, oy + 7, 30, 25, 5)
    # Landing feet
    c.fill_rect(ox + 8,  oy + oh,     ox + 14, oy + oh + 5, YELLOW[0], YELLOW[1], YELLOW[2])
    c.fill_rect(ox + ow - 14, oy + oh, ox + ow - 8, oy + oh + 5, YELLOW[0], YELLOW[1], YELLOW[2])
    # Propellers (thin lines)
    c.fill_row(oy - 3, ox - 8, ox + 10, 180, 180, 180, 180)
    c.fill_row(oy - 3, ox + ow - 10, ox + ow + 8, 180, 180, 180, 180)


def draw_hud_chip(c: Canvas, x: int, y: int, w: int, h: int,
                  value_dots: int = 6, label_dots: int = 4) -> None:
    """Frosted-glass HUD chip."""
    c.fill_rect(x, y, x + w, y + h, 8, 16, 45, 170)
    # Border
    c.fill_row(y, x, x + w, CYAN[0], CYAN[1], CYAN[2], 210)
    c.fill_row(y + h - 1, x, x + w, CYAN[0], CYAN[1], CYAN[2], 140)
    for ry in range(y, y + h):
        c.blend(x, ry, CYAN[0], CYAN[1], CYAN[2], 200)
        c.blend(x + w - 1, ry, CYAN[0], CYAN[1], CYAN[2], 150)
    # Glow above
    c.blend_row(y - 1, x, x + w, CYAN[0], CYAN[1], CYAN[2], 70)
    c.blend_row(y - 2, x, x + w, CYAN[0], CYAN[1], CYAN[2], 25)
    # Label bar (dim)
    c.fill_rect(x + 7, y + 5, x + w - 7, y + 11, CYAN[0], CYAN[1], CYAN[2], 90)
    # Value bar (bright)
    c.fill_rect(x + 7, y + 15, x + w - 7, y + 23, CYAN[0], CYAN[1], CYAN[2], 190)


def draw_neon_border(c: Canvas, thickness: int = 3) -> None:
    for t in range(1, thickness + 6):
        alpha = int(220 * max(0, 1 - (t - 1) / (thickness + 5)))
        c.fill_row(t - 1, 0, c.w, CYAN[0], CYAN[1], CYAN[2], alpha)
        c.fill_row(c.h - t, 0, c.w, CYAN[0], CYAN[1], CYAN[2], alpha)
        for ry in range(c.h):
            c.blend(t - 1, ry, CYAN[0], CYAN[1], CYAN[2], alpha)
            c.blend(c.w - t, ry, CYAN[0], CYAN[1], CYAN[2], alpha)


def draw_score_row(c: Canvas, x0: int, y0: int, w: int,
                   accent: bool = False, row_idx: int = 0) -> None:
    """Leaderboard score row."""
    h = 34
    bg_alpha = 160 if accent else 130
    c.fill_rect(x0, y0, x0 + w, y0 + h, 10, 18, 48, bg_alpha)
    accent_col = CYAN if accent else (30, 60, 100)
    c.fill_rect(x0, y0, x0 + 6, y0 + h, accent_col[0], accent_col[1], accent_col[2], 180)
    # Name placeholder
    name_w = w // 3
    c.fill_rect(x0 + 12, y0 + 9, x0 + 12 + name_w, y0 + 22,
                TEXT[0], TEXT[1], TEXT[2], 100)
    # Score placeholder
    score_w = w // 4
    score_a = 160 if accent else 100
    c.fill_rect(x0 + w - score_w - 10, y0 + 9, x0 + w - 10, y0 + 22,
                CYAN[0], CYAN[1], CYAN[2], score_a)


# ---------------------------------------------------------------------------
# Wide screenshot  1280 × 720
# ---------------------------------------------------------------------------
def generate_wide() -> None:
    W, H = 1280, 720
    c = Canvas(W, H)

    draw_background_gradient(c)
    draw_stars(c, int(H * 0.72), seed=12345)

    ground_y = int(H * 0.75)
    draw_buildings(c, int(H * 0.05), ground_y, seed=99)

    heights = draw_terrain_section(c, 0, W, H, 0.75)
    draw_ground_markers(c, heights, 0, spacing=90)

    # --- Player ---
    player_x = 120
    player_y = heights[player_x] - 58
    draw_player(c, player_x, player_y)

    # --- Obstacles ---
    laser_x = 370
    laser_y = heights[min(laser_x, W - 1)] - 24
    draw_laser(c, laser_x, laser_y)

    server_x = 620
    server_y = heights[min(server_x, W - 1)] - 52
    draw_server(c, server_x, server_y)

    bug_x = 920
    bug_y = heights[min(bug_x, W - 1)] - 28
    draw_bug(c, bug_x, bug_y)

    drone_x = 1100
    drone_y = heights[min(drone_x, W - 1)] - 70  # floats high
    draw_drone(c, drone_x, drone_y)

    # --- HUD ---
    chip_w, chip_h = 118, 42
    gap = 18
    total = 3 * chip_w + 2 * gap
    hud_x = (W - total) // 2
    hud_y = 14
    for i in range(3):
        draw_hud_chip(c, hud_x + i * (chip_w + gap), hud_y, chip_w, chip_h)

    draw_neon_border(c)

    c.save_png(ROOT / "screenshots" / "screenshot-wide.png")


# ---------------------------------------------------------------------------
# Narrow screenshot  720 × 1280
# ---------------------------------------------------------------------------
def generate_narrow() -> None:
    W, H = 720, 1280
    c = Canvas(W, H)

    # Game viewport occupies top portion, UI panel below
    game_h = 560
    panel_y = game_h + 2

    draw_background_gradient(c)
    draw_stars(c, int(game_h * 0.72), seed=54321)

    ground_ratio = 0.74
    ground_y_abs = int(game_h * ground_ratio)
    draw_buildings(c, int(game_h * 0.05), ground_y_abs, seed=77)

    heights = draw_terrain_section(c, 0, W, game_h, ground_ratio, x_offset=200)
    draw_ground_markers(c, heights, 0, spacing=85, x_offset=200)

    # --- Player ---
    player_x = 110
    player_y = heights[player_x] - 58
    draw_player(c, player_x, player_y)

    # --- Obstacles ---
    server_x = 380
    server_y = heights[min(server_x, W - 1)] - 52
    draw_server(c, server_x, server_y)

    bug_x = 580
    bug_y = heights[min(bug_x, W - 1)] - 28
    draw_bug(c, bug_x, bug_y)

    # --- HUD ---
    chip_w, chip_h = 110, 40
    gap = 14
    total = 3 * chip_w + 2 * gap
    hud_x = (W - total) // 2
    draw_hud_chip(c, hud_x, 12, chip_w, chip_h)
    draw_hud_chip(c, hud_x + chip_w + gap, 12, chip_w, chip_h)
    draw_hud_chip(c, hud_x + 2 * (chip_w + gap), 12, chip_w, chip_h)

    # --- Divider between game area and UI panel ---
    c.fill_row(game_h,     0, W, CYAN[0], CYAN[1], CYAN[2], 160)
    c.fill_row(game_h + 1, 0, W, CYAN[0], CYAN[1], CYAN[2], 60)

    # --- UI Panel ---
    c.fill_rect(0, panel_y, W, H, 5, 9, 25, 240)

    # Leaderboard header
    header_y = panel_y + 16
    c.fill_rect(18, header_y, W - 18, header_y + 28, 10, 20, 55, 180)
    c.fill_row(header_y, 18, W - 18, CYAN[0], CYAN[1], CYAN[2], 160)
    c.fill_row(header_y + 28, 18, W - 18, CYAN[0], CYAN[1], CYAN[2], 90)
    # Title bar inside header
    c.fill_rect(70, header_y + 8, W - 70, header_y + 20, CYAN[0], CYAN[1], CYAN[2], 170)

    # Score rows
    row_x0 = 18
    row_w = W - 36
    for row in range(5):
        ry = header_y + 36 + row * 44
        draw_score_row(c, row_x0, ry, row_w, accent=(row == 0), row_idx=row)
        # Separator
        c.fill_row(ry + 34, row_x0, row_x0 + row_w, CYAN[0], CYAN[1], CYAN[2], 30)

    # Input field
    input_y = header_y + 265
    c.fill_rect(18, input_y, W - 18, input_y + 42, 8, 15, 42, 210)
    c.fill_row(input_y, 18, W - 18, CYAN[0], CYAN[1], CYAN[2], 180)
    c.fill_row(input_y + 41, 18, W - 18, CYAN[0], CYAN[1], CYAN[2], 110)
    for ry in range(input_y, input_y + 42):
        c.blend(18, ry, CYAN[0], CYAN[1], CYAN[2], 150)
        c.blend(W - 19, ry, CYAN[0], CYAN[1], CYAN[2], 150)
    # Cursor in input
    c.fill_rect(30, input_y + 12, 34, input_y + 30, CYAN[0], CYAN[1], CYAN[2], 200)

    # Save Score button
    btn_y = input_y + 54
    c.fill_rect(18, btn_y, W - 18, btn_y + 50,
                int(CYAN[0] * 0.35), int(CYAN[1] * 0.65), int(CYAN[2] * 0.85), 230)
    c.fill_row(btn_y, 18, W - 18, 255, 255, 255, 50)
    c.fill_rect(W // 4, btn_y + 16, W * 3 // 4, btn_y + 30, 255, 255, 255, 100)

    # Two secondary buttons
    btn2_y = btn_y + 62
    half = (W - 36 - 10) // 2
    for bx in [18, 18 + half + 10]:
        c.fill_rect(bx, btn2_y, bx + half, btn2_y + 44, 10, 20, 55, 200)
        c.fill_row(btn2_y, bx, bx + half, CYAN[0], CYAN[1], CYAN[2], 160)
        c.fill_row(btn2_y + 43, bx, bx + half, CYAN[0], CYAN[1], CYAN[2], 80)
        for ry in range(btn2_y, btn2_y + 44):
            c.blend(bx, ry, CYAN[0], CYAN[1], CYAN[2], 120)
            c.blend(bx + half - 1, ry, CYAN[0], CYAN[1], CYAN[2], 120)
        c.fill_rect(bx + half // 4, btn2_y + 14,
                    bx + half * 3 // 4, btn2_y + 28,
                    CYAN[0], CYAN[1], CYAN[2], 160)

    draw_neon_border(c)

    c.save_png(ROOT / "screenshots" / "screenshot-narrow.png")


# ---------------------------------------------------------------------------
def main() -> None:
    print("Generating screenshots …")
    generate_wide()
    generate_narrow()
    print("Done.")


if __name__ == "__main__":
    main()
