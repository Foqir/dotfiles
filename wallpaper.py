"""
Абстрактные обои Tokyo Night: тёмный градиент, светящиеся волны, точечная сетка.
usage: python wallpaper.py <out.png> [ширина высота] [seed]
"""
import sys

import numpy as np
from PIL import Image

out = sys.argv[1]
W, H = (int(sys.argv[2]), int(sys.argv[3])) if len(sys.argv) >= 4 else (1920, 1200)
rng = np.random.default_rng(int(sys.argv[4]) if len(sys.argv) >= 5 else 44)

hexrgb = lambda h: np.array([int(h[i:i + 2], 16) for i in (1, 3, 5)], dtype=np.float32) / 255
BG_TOP, BG_BOT = hexrgb("#1a1b26"), hexrgb("#0c0c13")
PALETTE = [hexrgb(c) for c in ("#7aa2f7", "#bb9af7", "#7dcfff", "#2ac3de", "#9d7cd8")]

y, x = np.mgrid[0:H, 0:W].astype(np.float32)
u, v = x / W, y / H

# фон: вертикальный градиент + мягкие цветные пятна
img = BG_TOP * (1 - v[..., None]) + BG_BOT * v[..., None]
for (cx, cy, r, col, a) in [(0.78, 0.28, 0.45, "#bb9af7", 0.10), (0.18, 0.80, 0.50, "#7aa2f7", 0.08)]:
    d2 = ((u - cx) * W / H) ** 2 + (v - cy) ** 2
    img += hexrgb(col) * (a * np.exp(-d2 / r**2))[..., None]

# волны: каждая — центральная линия с узким ядром и широким свечением
for i in range(7):
    f1, f2 = rng.uniform(0.6, 1.4), rng.uniform(1.8, 3.2)
    p1, p2 = rng.uniform(0, 2 * np.pi, 2)
    base = 0.50 + 0.035 * (i - 3)
    yc = H * (base + 0.10 * np.sin(2 * np.pi * f1 * u + p1) + 0.03 * np.sin(2 * np.pi * f2 * u + p2))
    d = np.abs(y - yc)
    width = H * rng.uniform(0.0012, 0.0022)
    core = np.exp(-(d / width) ** 2)
    glow = np.exp(-(d / (width * 10)) ** 2) * 0.14
    fade = np.clip(np.sin(np.pi * u) * 1.3, 0, 1) ** 0.8          # волны гаснут к краям
    t = (u + i / 7) % 1                                            # цвет плывёт вдоль линии
    k = t * (len(PALETTE) - 1)
    i0 = np.floor(k).astype(int); w1 = (k - i0)[..., None]
    pal = np.stack(PALETTE)
    col = pal[i0] * (1 - w1) + pal[np.minimum(i0 + 1, len(PALETTE) - 1)] * w1
    img += col * ((core * 1.1 + glow) * fade * 0.85)[..., None]

# точечная сетка
step = max(24, W // 60)
dots = ((x % step) < 1.5) & ((y % step) < 1.5)
img += 0.05 * dots[..., None]

# мягкая тонокоррекция + шум против полос градиента
img = 1 - np.exp(-img * 1.15)
img += rng.normal(0, 0.004, img.shape).astype(np.float32)
Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)).save(out, optimize=True)
print(out, f"{W}x{H}")
