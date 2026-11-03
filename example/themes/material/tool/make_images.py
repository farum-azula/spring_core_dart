#!/usr/bin/env python3
"""Makes the two small pictures of assets/images/ (standard library only).

  neon-grid.png  a dark night with a faint grid (the background of the
                 neon theme)
  badge.png      a round badge with a ring (an image token)

Run it from the app's folder: python3 tool/make_images.py
"""
import math
import struct
import zlib


def png(path, width, height, pixel):
    """Writes an RGBA PNG; pixel(x, y) returns (r, g, b, a)."""
    rows = bytearray()
    for y in range(height):
        rows.append(0)
        for x in range(width):
            rows.extend(pixel(x, y))

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
                + chunk(b"IDAT", zlib.compress(bytes(rows), 9)) + chunk(b"IEND", b""))


def lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


W, H = 960, 640
STEP = 40


def grid(x, y):
    """Near-black blue with thin cyan lines every STEP pixels."""
    base = lerp((11, 13, 20), (22, 26, 44), y / (H - 1))
    if x % STEP == 0 or y % STEP == 0:
        return (*lerp(base, (0, 229, 255), 0.35), 255)
    return (*base, 255)


S = 128


def badge(x, y):
    d = math.hypot(x - S / 2, y - S / 2)
    if d > S / 2 - 4:
        return (0, 0, 0, 0)
    if 24 <= d <= 32 or d <= 12:
        return (255, 255, 255, 255)
    return (63, 81, 181, 255)


png("assets/images/neon-grid.png", W, H, grid)
png("assets/images/badge.png", S, S, badge)
