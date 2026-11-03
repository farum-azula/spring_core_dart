#!/usr/bin/env python3
"""Makes the two small pictures of assets/images/ (standard library only).

  sunset-sky.png  a warm vertical gradient with a soft sun (the background
                  of the sunset theme)
  badge.png       a round badge with a ring (an image token)

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
TOP, MID, LOW = (255, 94, 58), (255, 149, 120), (255, 241, 230)


def sky(x, y):
    t = y / (H - 1)
    c = lerp(TOP, MID, t * 2) if t < 0.5 else lerp(MID, LOW, (t - 0.5) * 2)
    # A soft sun: white that fades with the distance from its centre.
    d = math.hypot(x - W / 2, y - H * 0.62)
    glow = max(0.0, 1 - d / 240) ** 2 * 0.55
    return (*lerp(c, (255, 255, 255), glow), 255)


S = 128


def badge(x, y):
    d = math.hypot(x - S / 2, y - S / 2)
    if d > S / 2 - 4:
        return (0, 0, 0, 0)
    if 24 <= d <= 32 or d <= 12:
        return (255, 255, 255, 255)
    return (0, 122, 255, 255)


png("assets/images/sunset-sky.png", W, H, sky)
png("assets/images/badge.png", S, S, badge)
