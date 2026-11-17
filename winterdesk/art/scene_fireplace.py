"""Cozy fireplace room: stone hearth, mantel garland, stockings, wreath, snowy windows."""
import json
import math
import numpy as np
from paint import *


def window(cv, r, x0, y0, x1, y1, feats):
    # night view through the window
    view = vgrad([(0, (0.05, 0.07, 0.2)), (1, (0.2, 0.22, 0.45))])
    m = Mask(); m.rect(x0, y0, x1, y1); wm = m.get(0.8)
    comp(cv, wm, view)
    sub = cv.copy()
    stars(sub, 5 + x0, 60, y1)
    comp(cv, wm, sub)
    hills = y1 - 120 + 30 * np.sin(np.arange(W) / 80.0)
    comp(cv, below_line_mask(hills, 2) * wm, (0.62, 0.64, 0.88))
    mb, ms = Mask(), Mask()
    for k in range(5):
        pine(mb, ms, x0 + 40 + k * (x1 - x0 - 80) / 4 + r.uniform(-15, 15), y1 - 70, r.uniform(110, 190), r, snow=0.9)
    comp(cv, mb.get(0.8) * wm, (0.05, 0.09, 0.14))
    comp(cv, ms.get(0.8) * wm, (0.75, 0.77, 0.96))
    # frame and mullions
    fr = Mask()
    fr.rect(x0 - 26, y0 - 26, x1 + 26, y0); fr.rect(x0 - 26, y1, x1 + 26, y1 + 30)
    fr.rect(x0 - 26, y0, x0, y1); fr.rect(x1, y0, x1 + 26, y1)
    fr.rect((x0 + x1) / 2 - 8, y0, (x0 + x1) / 2 + 8, y1); fr.rect(x0, (y0 + y1) / 2 - 8, x1, (y0 + y1) / 2 + 8)
    comp(cv, fr.get(0.8), (0.30, 0.17, 0.10))
    sill = Mask()
    for x in range(int(x0), int(x1), 18):
        sill.ellipse(x, y1 - 4, 16, 9)
    snow_fill(cv, sill.get(1.2), (0.9, 0.9, 1.0), (0.6, 0.6, 0.85), rim=4)
    glow(cv, (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) * 0.6, (0.12, 0.14, 0.3), 0.25)


def main():
    r = rng(21)
    feats = {"fire": None, "candles": [], "lights": [], "glows": []}
    cv = vgrad([(0, (0.13, 0.05, 0.05)), (0.6, (0.28, 0.10, 0.07)), (1, (0.28, 0.10, 0.07))])
    # damask-ish wallpaper
    pat = noise(3, 40, octaves=3)
    stripes = (np.sin(np.arange(W) / 18.0) > 0.6).astype(np.float32)[None, :]
    cv *= (0.92 + 0.12 * pat[..., None]) * (1 - 0.06 * stripes[..., None])
    # wainscot and floor
    wain = Mask(); wain.rect(0, 1050, W, 1260); comp(cv, wain.get(0.8), (0.20, 0.10, 0.06))
    panels = Mask()
    for x in range(30, W, 260):
        panels.rect(x, 1080, x + 220, 1230)
    comp(cv, panels.get(1.0), (0.26, 0.13, 0.08))
    trim = Mask(); trim.rect(0, 1040, W, 1058); comp(cv, trim.get(0.8), (0.36, 0.19, 0.10))
    floor = vgrad([(0, (0.2, 0.1, 0.05)), (0.78, (0.22, 0.11, 0.06)), (1, (0.32, 0.17, 0.09))])
    fm = Mask(); fm.rect(0, 1260, W, H); comp(cv, fm.get(0.5), floor)
    boards = Mask()
    for y in range(1290, H, 46):
        boards.line([(0, y), (W, y)], 2)
    comp(cv, boards.get(0.8), (0.1, 0.05, 0.03), 0.7)
    # rug
    rug = Mask(); rug.ellipse(1280, 1460, 760, 150); comp(cv, rug.get(2), (0.45, 0.07, 0.10))
    rug2 = Mask(); rug2.ellipse(1280, 1460, 700, 125); comp(cv, rug2.get(2), (0.42, 0.08, 0.10))
    rugp = Mask(); rugp.ellipse(1280, 1460, 560, 92); comp(cv, rugp.get(3), (0.70, 0.45, 0.25), 0.18)

    window(cv, r, 140, 300, 560, 880, feats)
    window(cv, r, 2000, 300, 2420, 880, feats)

    # stone fireplace
    fx0, fx1, fy0, fy1 = 760, 1800, 540, 1270
    stone = Mask(); stone.rect(fx0, fy0, fx1, fy1); sm = stone.get(0.8)
    comp(cv, sm, (0.22, 0.20, 0.20))
    groups = [Mask(), Mask(), Mask(), Mask()]
    for row, y in enumerate(range(fy0, fy1, 58)):
        x = fx0 + (0 if row % 2 else -40)
        while x < fx1:
            w = r.uniform(70, 140)
            cx, cy, rx, ry = x + w / 2, y + 29 + r.uniform(-4, 4), w / 2 - 5, r.uniform(21, 27)
            pts = []
            for k in range(14):
                a = k / 14 * 2 * math.pi
                f = r.uniform(0.85, 1.08)
                pts.append((cx + rx * f * math.cos(a), cy + ry * f * math.sin(a)))
            groups[r.integers(0, 4)].poly(pts)
            x += w
    tone = noise(9, 60, octaves=3)[..., None]
    for g, base in zip(groups, [(0.36, 0.32, 0.30), (0.42, 0.36, 0.31), (0.31, 0.29, 0.29), (0.46, 0.40, 0.34)]):
        gm = g.get(1.2) * sm
        comp(cv, gm, np.array(base) * (0.85 + 0.3 * tone))
        comp(cv, np.clip(gm - shifted(gm, -5), 0, 1), (0.70, 0.60, 0.52), 0.35)
        comp(cv, np.clip(gm - shifted(gm, 5), 0, 1), (0.08, 0.06, 0.06), 0.45)
    # firebox arch
    ox0, ox1, oy0, oy1 = 1010, 1550, 820, 1240
    arch = Mask()
    arch.rect(ox0, oy0 + 120, ox1, oy1)
    arch.ellipse((ox0 + ox1) / 2, oy0 + 130, (ox1 - ox0) / 2, 140)
    am = arch.get(1.0)
    comp(cv, am, (0.04, 0.02, 0.02))
    inner = vgrad([(0, (0.03, 0.02, 0.02)), (0.6, (0.05, 0.03, 0.02)), (0.76, (0.22, 0.07, 0.02)), (1, (0.32, 0.11, 0.03))])
    comp(cv, am, inner, 0.8)
    archrim = Mask(); archrim.ellipse((ox0 + ox1) / 2, oy0 + 130, (ox1 - ox0) / 2 + 30, 170); archrim.rect(ox0 - 30, oy0 + 130, ox1 + 30, oy1)
    ar = np.clip(archrim.get(1.0) - am, 0, 1)
    comp(cv, ar, (0.32, 0.27, 0.25), 0.8)
    # logs and grate
    logs = Mask()
    logs.poly([(1090, 1200), (1440, 1170), (1450, 1205), (1100, 1232)])
    logs.poly([(1130, 1170), (1480, 1205), (1470, 1235), (1120, 1200)])
    comp(cv, logs.get(1.0), (0.22, 0.12, 0.07))
    ends = Mask(); ends.ellipse(1095, 1216, 16, 16); ends.ellipse(1475, 1220, 16, 15)
    comp(cv, ends.get(1.0), (0.6, 0.38, 0.2))
    grate = Mask()
    for x in range(1060, 1520, 34):
        grate.rect(x, 1232, x + 8, 1250)
    grate.rect(1050, 1240, 1520, 1250)
    comp(cv, grate.get(0.8), (0.06, 0.05, 0.05))
    glow(cv, 1280, 1170, 200, (0.8, 0.32, 0.06), 0.35)
    comp(cv, logs.get(1.0), (0.14, 0.08, 0.05))
    ember = np.clip(logs.get(1.0) - shifted(logs.get(1.0), 7), 0, 1)
    comp(cv, ember, (1.0, 0.45, 0.1), 0.8)
    feats["fire"] = [1280 / W, 1185 / H, (ox1 - ox0) / W]
    # hearth
    hearth = Mask(); hearth.rect(fx0 - 50, fy1 - 10, fx1 + 50, fy1 + 40); comp(cv, hearth.get(0.8), (0.40, 0.37, 0.35))
    comp(cv, np.clip(hearth.get(0.8) - shifted(hearth.get(0.8), 8), 0, 1), (0.6, 0.55, 0.5), 0.6)
    # mantel beam
    mant = Mask(); mant.rect(fx0 - 70, fy0 - 70, fx1 + 70, fy0 + 4); mm = mant.get(0.8)
    grain = noise(17, 6, 80, octaves=3)[..., None]
    comp(cv, mm, np.concatenate([0.32 + 0.12 * grain, 0.17 + 0.06 * grain, 0.09 + 0.03 * grain], axis=2))
    comp(cv, np.clip(mm - shifted(mm, -8), 0, 1), (0.6, 0.38, 0.2), 0.5)
    comp(cv, np.clip(mm - shifted(mm, 10), 0, 1), (0.1, 0.05, 0.03), 0.6)

    # garland drooping along the mantel with lights
    gar, gsnow = Mask(), Mask()
    segs = 6
    for k in range(segs):
        a, b = fx0 - 60 + k * (fx1 - fx0 + 120) / segs, fx0 - 60 + (k + 1) * (fx1 - fx0 + 120) / segs
        for t in np.linspace(0, 1, 26):
            x = a + (b - a) * t
            y = fy0 + 6 + 60 * math.sin(math.pi * t)
            for _ in range(3):
                gar.ellipse(x + r.uniform(-10, 10), y + r.uniform(-8, 8), r.uniform(14, 22), r.uniform(9, 14))
        for t in np.linspace(0.1, 0.9, 4):
            x = a + (b - a) * t
            y = fy0 + 6 + 60 * math.sin(math.pi * t) + 12
            feats["lights"].append([x / W, y / H])
    comp(cv, gar.get(1.0), (0.06, 0.22, 0.12))
    needles = Mask()
    for _ in range(2500):
        k = r.integers(0, segs); t = r.random()
        a, b = fx0 - 60 + k * (fx1 - fx0 + 120) / segs, fx0 - 60 + (k + 1) * (fx1 - fx0 + 120) / segs
        x, y = a + (b - a) * t, fy0 + 6 + 60 * math.sin(math.pi * t)
        ang = r.uniform(0, 2 * math.pi)
        needles.line([(x, y), (x + 18 * math.cos(ang), y + 14 * math.sin(ang))], 2)
    comp(cv, needles.get(0.6), (0.10, 0.32, 0.18), 0.8)
    for (u, v) in feats["lights"]:
        glow(cv, u * W, v * H, 14, (0.8, 0.6, 0.3), 0.35)
    # stockings
    for i, c in enumerate([(0.78, 0.10, 0.13), (0.12, 0.42, 0.24), (0.78, 0.10, 0.13), (0.85, 0.82, 0.78)]):
        sx = fx0 + 120 + i * (fx1 - fx0 - 240) / 3
        top = fy0 + 40
        sock = Mask()
        sock.poly([(sx - 32, top), (sx + 32, top), (sx + 32, top + 150), (sx + 85, top + 175), (sx + 80, top + 215),
                   (sx - 10, top + 215), (sx - 32, top + 180)])
        sk = sock.get(1.0)
        comp(cv, sk, c)
        comp(cv, np.clip(sk - shifted(sk, -10), 0, 1) * 0 + np.clip(sk - shifted(sk, 6), 0, 1), (0, 0, 0), 0.25)
        cuff = Mask(); cuff.rect(sx - 38, top - 6, sx + 38, top + 36); comp(cv, cuff.get(1.5), (0.95, 0.94, 0.92))
    # candles and wreath
    for (cx, h) in [(fx0 - 20, 150), (fx0 + 45, 110), (fx1 - 20, 130)]:
        c = Mask(); c.rect(cx - 16, fy0 - 70 - h, cx + 16, fy0 - 70); comp(cv, c.get(0.8), (0.95, 0.90, 0.80))
        glow(cv, cx, fy0 - 70 - h - 18, 60, (0.7, 0.4, 0.12), 0.35)
        feats["candles"].append([cx / W, (fy0 - 70 - h - 16) / H])
    wr = Mask()
    for k in range(180):
        a = k / 180 * 2 * math.pi
        x, y = 1280 + 150 * math.cos(a), 300 + 150 * math.sin(a)
        wr.ellipse(x + r.uniform(-12, 12), y + r.uniform(-12, 12), r.uniform(26, 40), r.uniform(18, 28))
    comp(cv, wr.get(1.0), (0.05, 0.20, 0.11))
    wn = Mask()
    for _ in range(1800):
        a = r.uniform(0, 2 * math.pi); rr = r.uniform(110, 195)
        x, y = 1280 + rr * math.cos(a), 300 + rr * math.sin(a)
        ang = r.uniform(0, 2 * math.pi)
        wn.line([(x, y), (x + 16 * math.cos(ang), y + 16 * math.sin(ang))], 2.2)
    comp(cv, wn.get(0.6), (0.12, 0.36, 0.2), 0.8)
    berries = Mask()
    for _ in range(40):
        a = r.uniform(0, 2 * math.pi); rr = r.uniform(130, 175)
        berries.ellipse(1280 + rr * math.cos(a), 300 + rr * math.sin(a), 8, 8)
    comp(cv, berries.get(0.8), (0.85, 0.08, 0.12))
    bow = Mask()
    bow.poly([(1280, 440), (1200, 400), (1210, 480)]); bow.poly([(1280, 440), (1360, 400), (1350, 480)])
    bow.poly([(1270, 440), (1240, 560), (1265, 550)]); bow.poly([(1290, 440), (1320, 560), (1295, 550)])
    comp(cv, bow.get(1.0), (0.80, 0.08, 0.12))

    # warm light from the fire across the room
    glow(cv, 1280, 1150, 700, (0.30, 0.12, 0.03), 0.35)
    glow(cv, 1280, 1420, 600, (0.25, 0.10, 0.02), 0.25)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    v = 1 - 0.45 * (((xx - W / 2) / (W * 0.65)) ** 2 + ((yy - H * 0.6) / (H * 0.8)) ** 2)
    cv *= np.clip(v, 0.45, 1)[..., None]
    save(cv, "../Resources/bg-fireplace.jpg")
    json.dump(feats, open("../Resources/bg-fireplace.json", "w"))


if __name__ == "__main__":
    main()
