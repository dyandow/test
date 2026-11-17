"""Snowy log cabin at night: big snowy branch, mountains, forest, warm lights."""
import json
import math
import numpy as np
from paint import *


def snow_branch(cv, r):
    """Snow-laden pine branch hanging in from the top-left: separate pillowy clumps of snow
    with dark needles between them, lit warm from below."""
    m_needles, m_mass, m_snow, m_twig = Mask(), Mask(), Mask(), Mask()
    main = [(-120 + t * 1250, -10 + 300 * math.sin(t * 1.35) + 40 * t) for t in np.linspace(0, 1, 30)]
    m_twig.line(main, 24)
    clumps = []
    for i, (x, y) in enumerate(main[::3]):
        fade = 1 - i / 16
        clumps.append((x, y + 30, r.uniform(200, 260) * fade))
        for side in (-1, 1):
            if r.random() < 0.75:
                ang = (0.55 + r.uniform(0, 0.5)) if side > 0 else (math.pi - 0.4 - r.uniform(0, 0.5))
                L = r.uniform(220, 360) * fade
                pts = [(x, y)]
                for k in range(1, 6):
                    t = k / 5
                    pts.append((x + math.cos(ang) * L * t, y + math.sin(ang) * L * t + 25 * t * t))
                m_twig.line(pts, 9)
                ex, ey = pts[-1]
                clumps.append((ex, ey + 10, r.uniform(140, 200) * fade))
    for (x, y, s) in clumps:
        m_mass.ellipse(x, y + s * 0.12, s * 0.75, s * 0.38)
        for _ in range(int(s * 0.5)):
            a = r.uniform(0.15, math.pi - 0.15)
            L = r.uniform(0.35, 0.9) * s
            sx, sy = x + r.uniform(-0.6, 0.6) * s, y + r.uniform(-0.05, 0.25) * s
            m_needles.line([(sx, sy), (sx + math.cos(a) * L * 0.6, sy + math.sin(a) * L * 0.5)], 4)
        for _ in range(r.integers(3, 5)):
            m_snow.ellipse(x + r.uniform(-0.35, 0.35) * s, y - s * r.uniform(0.05, 0.22),
                           s * r.uniform(0.3, 0.45), s * r.uniform(0.2, 0.28))
    comp(cv, m_mass.get(2.0), (0.04, 0.09, 0.10))
    comp(cv, m_needles.get(0.8), (0.06, 0.13, 0.12))
    comp(cv, m_twig.get(1.0), (0.13, 0.08, 0.07))
    snow_fill(cv, m_snow.get(2.0), (0.82, 0.78, 0.97), (1.0, 0.62, 0.44), rim=26, shade_px=10)


def main():
    r = rng(7)
    feats = {"lights": [], "glows": [], "smoke": [], "twinkleBand": [0.0, 0.5]}

    cv = vgrad([(0, (0.03, 0.05, 0.16)), (0.30, (0.07, 0.09, 0.26)), (0.52, (0.18, 0.17, 0.42)),
                (0.62, (0.30, 0.25, 0.50)), (1, (0.30, 0.25, 0.50))])
    stars(cv, 1, 1100, 900)

    # mountains: distinct peaks lit from the right, hazier further back
    far = [(x + r.uniform(-120, 120), r.uniform(330, 560), r.uniform(320, 520)) for x in np.linspace(-150, W + 150, 6)]
    mountain_range(cv, r, far, 1000, (0.24, 0.23, 0.48), (0.15, 0.15, 0.36), (0.80, 0.78, 0.96), (0.52, 0.52, 0.80),
                   haze=(0.30, 0.27, 0.54), haze_amt=0.35)
    near = [(x + r.uniform(-100, 100), r.uniform(560, 700), r.uniform(260, 420)) for x in np.linspace(300, W + 100, 5)]
    mountain_range(cv, r, near, 1100, (0.16, 0.17, 0.38), (0.09, 0.10, 0.26), (0.70, 0.70, 0.92), (0.42, 0.44, 0.74),
                   haze=(0.24, 0.22, 0.48), haze_amt=0.15)
    # forest blanket on the lower slopes
    mb, ms = Mask(), Mask()
    for _ in range(1400):
        x = r.uniform(0, W)
        yb = r.uniform(880, 1120)
        pine(mb, ms, x, yb, r.uniform(16, 42) * (0.6 + (yb - 880) / 400), r, snow=0.6)
    comp(cv, mb.get(0.6), (0.06, 0.09, 0.20))
    comp(cv, ms.get(0.6), (0.48, 0.50, 0.78), 0.85)

    # snowy ground with drifts
    ground = 1150 + 30 * np.sin(np.arange(W) / 260.0) + 18 * np.sin(np.arange(W) / 97.0 + 1.3)
    gm = below_line_mask(ground, 1.5)
    gcol = vgrad([(0, (0.42, 0.42, 0.72)), (0.72, (0.47, 0.46, 0.76)), (1, (0.62, 0.58, 0.86))])
    tex = noise(31, 60, octaves=4)[..., None]
    comp(cv, gm, gcol * (0.9 + 0.2 * tex))
    for k, (y0, a) in enumerate([(1260, 60), (1380, 70), (1500, 55)]):
        line = y0 + a * np.sin(np.arange(W) / (180 + 50 * k) + k * 2)
        m = below_line_mask(line, 6)
        comp(cv, m, (0.36, 0.36, 0.66), 0.35)
        hl = below_line_mask(line, 2) - below_line_mask(line + 10, 6)
        comp(cv, np.clip(hl, 0, 1), (0.82, 0.80, 0.98), 0.45)

    # mid-distance snowy pines
    mb, ms = Mask(), Mask()
    for x in list(np.linspace(760, 2500, 14)) + list(r.uniform(700, 2560, 10)):
        x += r.uniform(-50, 50)
        h = r.uniform(220, 460)
        pine(mb, ms, x, 1150 + r.uniform(-10, 40), h, r, snow=0.95)
    comp(cv, mb.get(1.0), (0.04, 0.09, 0.13))
    snow_fill(cv, ms.get(1.2), (0.74, 0.75, 0.95), (0.45, 0.45, 0.75), rim=5, shade_px=3)

    # ---- cabin ----
    log, dark, glass = (0.27, 0.15, 0.09), (0.12, 0.07, 0.04), (1.0, 0.78, 0.40)
    walls = Mask()
    walls.poly([(-10, 860), (300, 590), (610, 860), (610, 1190), (-10, 1190)])
    comp(cv, walls.get(1), log)
    logs = Mask()
    for y in range(600, 1190, 22):
        logs.line([(-10, y), (610, y)], 2.5)
    comp(cv, logs.get(0.8) * walls.get(1), dark, 0.75)
    # windows
    wins = [(200, 650, 400, 820), (40, 930, 250, 1110), (360, 930, 570, 1110)]
    for (x0, y0, x1, y1) in wins:
        glow(cv, (x0 + x1) / 2, (y0 + y1) / 2, 130, (0.45, 0.22, 0.06), 0.3)
        w = Mask(); w.rect(x0 - 10, y0 - 10, x1 + 10, y1 + 10); comp(cv, w.get(0.8), (0.25, 0.14, 0.08))
        w = Mask(); w.rect(x0, y0, x1, y1); comp(cv, w.get(0.6), glass)
        glow(cv, (x0 + x1) / 2, (y0 + y1) / 2 + 20, (x1 - x0) * 0.35, (0.35, 0.15, 0.0), 0.6)
        mull = Mask()
        mull.rect((x0 + x1) / 2 - 4, y0, (x0 + x1) / 2 + 4, y1)
        mull.rect(x0, (y0 + y1) / 2 - 4, x1, (y0 + y1) / 2 + 4)
        comp(cv, mull.get(0.6), (0.30, 0.16, 0.08))
        feats["glows"].append([(x0 + x1) / 2 / W, (y0 + y1) / 2 / H, (x1 - x0) * 1.2 / W])
    # roof: thick snow on the A-frame, warm-lit underside
    roof = Mask()
    roof.poly([(-80, 880), (300, 520), (680, 880), (650, 905), (300, 575), (-50, 905)])
    comp(cv, roof.get(1), (0.22, 0.11, 0.07))
    snow_roof_low, snow_roof_top = Mask(), Mask()
    for t in np.linspace(0, 1, 60):
        for (ax, ay, bx, by) in [(-90, 870, 300, 505), (300, 505, 690, 870)]:
            x, y = ax + (bx - ax) * t, ay + (by - ay) * t
            snow_roof_low.ellipse(x, y - 4, 44, 30)
            snow_roof_top.ellipse(x, y - 18, 40, 24)
    snow_fill(cv, np.maximum(snow_roof_low.get(2), snow_roof_top.get(2.5)), (0.86, 0.84, 0.99), (1.0, 0.64, 0.46), rim=18, shade_px=6)
    # chimney (smoke is animated in the app)
    ch = Mask(); ch.rect(430, 560, 490, 700); comp(cv, ch.get(0.8), (0.30, 0.16, 0.12))
    bricks = Mask()
    for yy in range(565, 700, 16):
        bricks.line([(430, yy), (490, yy)], 1.5)
    comp(cv, bricks.get(0.6), (0.18, 0.09, 0.07), 0.8)
    chs = Mask(); chs.ellipse(460, 560, 40, 16); snow_fill(cv, chs.get(1.5), (0.88, 0.86, 1.0), (1.0, 0.66, 0.5), rim=6)
    feats["smoke"] = [[460 / W, 545 / H]]

    # string lights under the eaves
    for (ax, ay, bx, by) in [(-60, 905, 300, 580), (300, 580, 660, 905)]:
        for t in np.linspace(0.04, 0.96, 13):
            x, y = ax + (bx - ax) * t, ay + (by - ay) * t + 14
            glow(cv, x, y, 16, (0.9, 0.6, 0.25), 0.45)
            glow(cv, x, y, 3.5, (1, 0.95, 0.75), 1.4)
            feats["lights"].append([x / W, y / H])
    # porch, posts, railing, lanterns, steps
    porch = Mask(); porch.rect(-10, 1180, 760, 1205); comp(cv, porch.get(0.8), (0.30, 0.17, 0.09))
    posts = Mask()
    for x in (300, 520, 740):
        posts.rect(x - 9, 1000, x + 9, 1185)
    posts.rect(-10, 990, 760, 1004)
    for x in range(600, 760, 26):
        posts.rect(x - 3, 1100, x + 3, 1182)
    posts.rect(590, 1095, 760, 1104)
    comp(cv, posts.get(0.8), (0.33, 0.19, 0.10))
    porch_snow = Mask()
    for x in range(-10, 770, 24):
        porch_snow.ellipse(x, 990, 18, 9)
        porch_snow.ellipse(x, 1180, 22, 10)
        if x > 590:
            porch_snow.ellipse(x, 1094, 16, 7)
    comp(cv, porch_snow.get(1.5), (0.95, 0.80, 0.85))
    for (lx, ly) in [(410, 1040), (640, 1040)]:
        glow(cv, lx, ly, 120, (0.6, 0.35, 0.1), 0.6)
        lan = Mask(); lan.rect(lx - 13, ly - 22, lx + 13, ly + 22); comp(cv, lan.get(0.8), (0.12, 0.08, 0.06))
        lan = Mask(); lan.rect(lx - 9, ly - 16, lx + 9, ly + 16); comp(cv, lan.get(0.8), (1, 0.82, 0.45))
        feats["glows"].append([lx / W, ly / H, 140 / W])
    steps = Mask()
    for k in range(4):
        steps.rect(470 - k * 6, 1205 + k * 26, 740 + k * 6, 1218 + k * 26)
    comp(cv, steps.get(0.8), (0.28, 0.16, 0.09))
    st_snow = Mask()
    for k in range(4):
        for x in range(470 - k * 6, 745 + k * 6, 20):
            st_snow.ellipse(x, 1205 + k * 26, 16, 8)
    comp(cv, st_snow.get(1.5), (0.98, 0.78, 0.70))
    # warm light spilling onto the snow
    for (gx, gy, rad, s) in [(330, 1260, 330, 0.35), (620, 1320, 260, 0.3), (150, 1240, 250, 0.3)]:
        glow(cv, gx, gy, rad, (0.75, 0.40, 0.15), s)

    # fence trailing off to the right
    fence, fsnow = Mask(), Mask()
    for i, x in enumerate(range(800, 1450, 70)):
        y = 1225 + i * 6
        fence.rect(x - 7, y - 70, x + 7, y)
        fsnow.ellipse(x, y - 72, 11, 7)
    fence.line([(800, 1180), (1450, 1230)], 9)
    fence.line([(800, 1205), (1450, 1255)], 7)
    comp(cv, fence.get(0.8), (0.24, 0.15, 0.10))
    comp(cv, fsnow.get(1.2), (0.92, 0.82, 0.92))

    # foreground drifts and sparkles
    fg = 1480 + 40 * np.sin(np.arange(W) / 210.0 + 0.6)
    comp(cv, below_line_mask(fg, 3), (0.55, 0.53, 0.82))
    for _ in range(500):
        x, y = r.uniform(0, W), r.uniform(1180, H)
        glow(cv, x, y, r.uniform(0.6, 1.3), (1, 1, 1), r.uniform(0.3, 0.9))

    snow_branch(cv, r)
    # gentle vignette
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    v = 1 - 0.35 * (((xx - W / 2) / (W * 0.7)) ** 2 + ((yy - H / 2) / (H * 0.75)) ** 2)
    cv *= np.clip(v, 0.55, 1)[..., None]

    save(cv, "../Resources/bg-cabin.jpg")
    json.dump(feats, open("../Resources/bg-cabin.json", "w"))


if __name__ == "__main__":
    main()
