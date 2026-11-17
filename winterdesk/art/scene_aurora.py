"""Northern lights over snowy mountains and a frozen lake."""
import json
import math
import numpy as np
from PIL import Image, ImageFilter
from paint import *


def aurora_band(seed, base, amp, wl, height, colors):
    """Returns an additive light layer for one curtain of aurora."""
    xs = np.arange(W, dtype=np.float32)
    curve = base + amp * np.sin(xs / wl + seed) + amp * 0.4 * np.sin(xs / (wl * 0.37) + seed * 2)
    yy = np.arange(H, dtype=np.float32)[:, None]
    up = (curve[None, :] - yy) / height            # 0 at the lower edge, 1 at the top of the curtain
    lower = np.clip((yy - curve[None, :] + 18) / 18, 0, 1)
    below = np.clip((yy - curve[None, :]) / 40, 0, None)
    fade = np.where(up >= 0, np.exp(-up * 2.2), np.exp(-below * 2.5) * 0.9)
    edge = np.clip(1 - np.abs(up) * 6, 0, 1) * 0.6
    streak = noise(seed + 400, 260, 3, octaves=3)
    streak = np.clip((streak - 0.35) * 2.2, 0, 1)
    inten = np.clip(fade * (0.35 + 0.9 * streak) + edge * streak, 0, 1.4)
    c0, c1 = np.array(colors[0]), np.array(colors[1])
    t = np.clip(up, 0, 1)[..., None]
    col = c0 * (1 - t) + c1 * t
    return inten[..., None] * col, curve


def main():
    r = rng(44)
    feats = {"bands": []}
    cv = vgrad([(0, (0.01, 0.02, 0.07)), (0.45, (0.03, 0.07, 0.15)), (0.7, (0.06, 0.14, 0.22)), (1, (0.06, 0.12, 0.2))])
    stars(cv, 3, 1400, 1000)
    light = np.zeros_like(cv)
    for seed, base, amp, wl, hgt, cols in [(1, 700, 120, 420, 480, ((0.25, 1.0, 0.55), (0.25, 0.55, 0.95))),
                                          (2, 430, 80, 300, 300, ((0.25, 0.85, 0.75), (0.65, 0.35, 1.0)))]:
        l, curve = aurora_band(seed, base, amp, wl, hgt, cols)
        light += l * 0.55
        feats["bands"].append({"base": base / H, "amp": amp / H, "wl": wl / W, "seed": seed, "height": hgt / H,
                               "c0": list(cols[0]), "c1": list(cols[1])})
    img = Image.fromarray((np.clip(light, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(3))
    light = np.asarray(img, np.float32) / 255
    cv += light
    peaks = [(x + r.uniform(-120, 120), r.uniform(700, 860), r.uniform(280, 420)) for x in np.linspace(-150, W + 150, 7)]
    mountain_range(cv, r, peaks, 1180, (0.10, 0.13, 0.20), (0.05, 0.07, 0.12), (0.62, 0.72, 0.80), (0.32, 0.40, 0.52),
                   haze=(0.08, 0.16, 0.20), haze_amt=0.2)
    # glow of the aurora on the snowy peaks
    cv += np.clip(light * 0.25, 0, 1) * below_line_mask(np.full(W, 760.0), 80)[..., None]
    # frozen lake reflecting the sky
    lake_top = 1180
    lake = Mask(); lake.rect(0, lake_top, W, H); lm = lake.get(1)
    refl = cv[lake_top - (H - lake_top):lake_top][::-1].copy()
    lake_col = np.zeros_like(cv)
    lake_col[lake_top:] = refl[: H - lake_top] * 0.45 + np.array([0.04, 0.08, 0.12])
    streaks = noise(70, 8, 120, octaves=3)[..., None]
    lake_col *= (0.85 + 0.3 * streaks)
    comp(cv, lm, lake_col)
    # shoreline pines and snowy banks
    mb, ms = Mask(), Mask()
    for _ in range(140):
        x = r.uniform(0, W)
        pine(mb, ms, x, lake_top + r.uniform(-2, 8), r.uniform(40, 120), r, snow=0.5)
    comp(cv, mb.get(0.6), (0.02, 0.04, 0.06))
    comp(cv, ms.get(0.6), (0.45, 0.55, 0.62))
    bank = 1420 + 60 * np.sin(np.arange(W) / 300.0) - np.clip((np.arange(W) - 1500) / 4, 0, 200)
    comp(cv, below_line_mask(bank, 2), (0.70, 0.78, 0.86))
    comp(cv, below_line_mask(bank + 14, 8), (0.55, 0.64, 0.74), 0.5)
    mb, ms = Mask(), Mask()
    for x in (1900, 2050, 2200, 2380, 2500):
        pine(mb, ms, x + r.uniform(-30, 30), bank[min(W - 1, x)] + 10, r.uniform(260, 420), r, snow=0.85)
    comp(cv, mb.get(1), (0.02, 0.05, 0.07))
    snow_fill(cv, ms.get(1.2), (0.75, 0.85, 0.92), (0.35, 0.6, 0.55), rim=5)
    for _ in range(300):
        x, y = r.uniform(0, W), r.uniform(1350, H)
        glow(cv, x, y, r.uniform(0.6, 1.2), (1, 1, 1), r.uniform(0.3, 0.8))
    save(cv, "../Resources/bg-aurora.jpg")
    json.dump(feats, open("../Resources/bg-aurora.json", "w"))


if __name__ == "__main__":
    main()
