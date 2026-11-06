import sys

import numpy as np
from PIL import Image

WIDTH, HEIGHT = 2560, 1600
BASE = np.array([10, 12, 18], dtype=np.float32)
GLOWS = (
    ((0.88, 0.30), (0.50, 0.50), np.array([84, 20, 36], dtype=np.float32), 0.70),
    ((0.66, 0.04), (0.35, 0.25), np.array([56, 16, 44], dtype=np.float32), 0.35),
    ((0.08, 0.92), (0.60, 0.45), np.array([10, 40, 58], dtype=np.float32), 0.70),
    ((0.30, 0.55), (0.70, 0.55), np.array([16, 20, 34], dtype=np.float32), 0.60),
)


def main(out):
    y, x = np.mgrid[0:HEIGHT, 0:WIDTH].astype(np.float32)
    u, v = x / WIDTH, y / HEIGHT
    image = np.broadcast_to(BASE, (HEIGHT, WIDTH, 3)).copy()
    for (cx, cy), (rx, ry), color, strength in GLOWS:
        d = ((u - cx) / rx) ** 2 + ((v - cy) / ry) ** 2
        image += color[None, None, :] * (strength * np.exp(-d * 2.2))[..., None]
    vignette = 1 - 0.45 * np.clip(((u - 0.5) ** 2 + (v - 0.5) ** 2) * 1.6, 0, 1)
    image *= vignette[..., None]
    scan = 1 - 0.035 * (np.floor(y) % 3 == 0)
    image *= scan[..., None]
    rng = np.random.default_rng(7)
    image += rng.normal(0, 2.4, (HEIGHT, WIDTH, 1)).astype(np.float32)
    Image.fromarray(np.clip(image, 0, 255).astype(np.uint8)).save(out, quality=90, optimize=True)


if __name__ == "__main__":
    main(sys.argv[1])
