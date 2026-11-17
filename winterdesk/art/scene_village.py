"""Snowy village at night: cottages with glowing windows, a church, a lit tree, lamps."""
import json
import math
import numpy as np
from paint import *


def cottage(cv, r, x, base, w, h, wall, feats, chimney=True):
    roof_h = w * 0.55
    body = Mask(); body.rect(x - w / 2, base - h, x + w / 2, base); bm = body.get(0.8)
    comp(cv, bm, wall)
    comp(cv, bm, (0.0, 0.0, 0.05), 0.0)
    # timber lines for character
    tl = Mask()
    tl.rect(x - w / 2, base - h, x - w / 2 + 6, base); tl.rect(x + w / 2 - 6, base - h, x + w / 2, base)
    tl.rect(x - w / 2, base - h * 0.52, x + w / 2, base - h * 0.52 + 5)
    comp(cv, tl.get(0.8), (0.25, 0.15, 0.10), 0.85)
    if chimney:
        cx = x + w * 0.22
        ch = Mask(); ch.rect(cx - 12, base - h - roof_h * 0.9, cx + 12, base - h - roof_h * 0.3); comp(cv, ch.get(0.8), (0.32, 0.18, 0.14))
        cs = Mask(); cs.ellipse(cx, base - h - roof_h * 0.9, 18, 8); snow_fill(cv, cs.get(1), (0.9, 0.9, 1.0), (1.0, 0.7, 0.55), rim=4)
        feats["smoke"].append([cx / W, (base - h - roof_h * 0.9 - 10) / H])
    roof = Mask(); roof.poly([(x - w / 2 - 22, base - h + 6), (x, base - h - roof_h), (x + w / 2 + 22, base - h + 6)])
    comp(cv, roof.get(0.8), (0.26, 0.12, 0.10))
    rs = Mask()
    for t in np.linspace(0, 1, 30):
        for (ax, ay, bx, by) in [(x - w / 2 - 26, base - h + 4, x, base - h - roof_h - 6), (x, base - h - roof_h - 6, x + w / 2 + 26, base - h + 4)]:
            rs.ellipse(ax + (bx - ax) * t, ay + (by - ay) * t - 6, w * 0.09, w * 0.065)
    snow_fill(cv, rs.get(1.5), (0.88, 0.87, 1.0), (1.0, 0.68, 0.52), rim=int(w * 0.04) + 3, shade_px=3)
    # windows
    for wx in (x - w * 0.24, x + w * 0.24):
        wy = base - h * 0.32
        ww, wh = w * 0.16, h * 0.24
        glow(cv, wx, wy, w * 0.35, (0.5, 0.25, 0.06), 0.35)
        m = Mask(); m.rect(wx - ww / 2, wy - wh / 2, wx + ww / 2, wy + wh / 2); comp(cv, m.get(0.6), (1.0, 0.80, 0.42))
        mu = Mask(); mu.rect(wx - 2, wy - wh / 2, wx + 2, wy + wh / 2); mu.rect(wx - ww / 2, wy - 2, wx + ww / 2, wy + 2)
        comp(cv, mu.get(0.6), (0.3, 0.16, 0.08))
        feats["glows"].append([wx / W, wy / H, w * 0.5 / W])
    gw = Mask(); gw.ellipse(x, base - h - roof_h * 0.35, w * 0.07, w * 0.07); comp(cv, gw.get(0.8), (1.0, 0.82, 0.45))
    door = Mask(); door.rect(x - w * 0.07, base - h * 0.38, x + w * 0.07, base); comp(cv, door.get(0.8), (0.28, 0.14, 0.08))


def main():
    r = rng(33)
    feats = {"lights": [], "glows": [], "smoke": []}
    cv = vgrad([(0, (0.03, 0.05, 0.16)), (0.35, (0.08, 0.10, 0.28)), (0.6, (0.22, 0.20, 0.45)), (1, (0.3, 0.26, 0.5))])
    stars(cv, 2, 1000, 850)
    glow(cv, 2050, 260, 260, (0.25, 0.27, 0.4), 0.5)
    moon = Mask(); moon.ellipse(2050, 260, 70, 70); comp(cv, moon.get(1.5), (0.98, 0.96, 0.86))
    crater = Mask(); crater.ellipse(2030, 245, 14, 12); crater.ellipse(2075, 285, 10, 9); crater.ellipse(2060, 230, 7, 7)
    comp(cv, crater.get(2), (0.85, 0.83, 0.75), 0.6)
    far = [(x + r.uniform(-150, 150), r.uniform(420, 600), r.uniform(350, 520)) for x in np.linspace(-200, W + 200, 6)]
    mountain_range(cv, r, far, 1050, (0.24, 0.23, 0.48), (0.15, 0.15, 0.36), (0.80, 0.78, 0.96), (0.52, 0.52, 0.80),
                   haze=(0.30, 0.27, 0.54), haze_amt=0.45)
    # rolling hills
    for k, (base, amp, c) in enumerate([(900, 50, (0.50, 0.52, 0.80)), (1010, 40, (0.62, 0.62, 0.88)), (1180, 35, (0.72, 0.71, 0.93))]):
        line = base + amp * np.sin(np.arange(W) / (300 + 90 * k) + k * 1.7)
        comp(cv, below_line_mask(line, 1.5), c)
        mb, ms = Mask(), Mask()
        for _ in range(240 - k * 70):
            x = r.uniform(0, W)
            pine(mb, ms, x, line[int(x) % W] + r.uniform(4, 30), r.uniform(25, 60) * (1 + k * 0.6), r, snow=0.75)
        comp(cv, mb.get(0.6), (0.05 + 0.02 * k, 0.09, 0.18))
        comp(cv, ms.get(0.6), (0.62 + 0.08 * k, 0.64 + 0.08 * k, 0.9))
    # church
    cx, cb = 1500, 1010
    ch = Mask(); ch.rect(cx - 70, cb - 170, cx + 70, cb); comp(cv, ch.get(0.8), (0.82, 0.78, 0.72))
    tw = Mask(); tw.rect(cx - 34, cb - 330, cx + 34, cb - 160); comp(cv, tw.get(0.8), (0.86, 0.82, 0.76))
    sp = Mask(); sp.poly([(cx - 42, cb - 325), (cx, cb - 470), (cx + 42, cb - 325)]); comp(cv, sp.get(0.8), (0.28, 0.14, 0.12))
    sps = Mask(); sps.poly([(cx - 46, cb - 322), (cx, cb - 470), (cx + 46, cb - 322), (cx + 30, cb - 330), (cx, cb - 420), (cx - 30, cb - 330)])
    snow_fill(cv, sps.get(1.2), (0.9, 0.9, 1.0), (1.0, 0.7, 0.55), rim=4)
    cr = Mask(); cr.rect(cx - 3, cb - 505, cx + 3, cb - 465); cr.rect(cx - 12, cb - 495, cx + 12, cb - 489); comp(cv, cr.get(0.8), (0.9, 0.8, 0.5))
    for wy in (cb - 280, cb - 110):
        glow(cv, cx, wy, 60, (0.5, 0.3, 0.08), 0.4)
        m = Mask(); m.rect(cx - 12, wy - 24, cx + 12, wy + 24); m.ellipse(cx, wy - 24, 12, 12); comp(cv, m.get(0.6), (1.0, 0.82, 0.45))
        feats["glows"].append([cx / W, wy / H, 90 / W])
    crs = Mask(); crs.poly([(cx - 80, cb - 165), (cx, cb - 230), (cx + 80, cb - 165)]); comp(cv, crs.get(0.8), (0.28, 0.14, 0.12))
    crs2 = Mask()
    for t in np.linspace(0, 1, 16):
        crs2.ellipse(cx - 84 + 84 * t, cb - 168 - 66 * t, 12, 9); crs2.ellipse(cx + 84 * t, cb - 234 + 66 * t, 12, 9)
    snow_fill(cv, crs2.get(1.2), (0.9, 0.9, 1.0), (1.0, 0.7, 0.55), rim=4)

    # cottages along the lane
    walls = [(0.80, 0.70, 0.55), (0.62, 0.22, 0.18), (0.40, 0.48, 0.60), (0.85, 0.80, 0.68), (0.55, 0.36, 0.22), (0.70, 0.30, 0.22)]
    spots = [(260, 1200, 300, 200), (640, 1150, 240, 170), (980, 1190, 260, 180), (1880, 1170, 250, 175), (2230, 1210, 300, 210), (1220, 1110, 180, 130)]
    for (x, b, w, h), c in sorted(zip(spots, walls), key=lambda t: t[0][1]):
        cottage(cv, r, x, b, w, h, c, feats)
    # village tree with lights
    tx, tb = 1560, 1260
    mb, ms = Mask(), Mask()
    pine(mb, ms, tx, tb, 330, r, snow=0.5)
    comp(cv, mb.get(0.8), (0.05, 0.22, 0.12))
    comp(cv, ms.get(0.8), (0.85, 0.86, 1.0))
    for _ in range(40):
        t = r.uniform(0.08, 0.95)
        y = tb - 330 + 330 * 0.9 * t
        x = tx + r.uniform(-1, 1) * 330 * (0.04 + 0.26 * t) * 0.85
        feats["lights"].append([x / W, y / H])
        glow(cv, x, y, 8, (0.9, 0.7, 0.4), 0.5)
    star = Mask(); star.ellipse(tx, tb - 335, 12, 12); comp(cv, star.get(1), (1.0, 0.9, 0.5)); glow(cv, tx, tb - 335, 40, (0.8, 0.6, 0.2), 0.6)
    # string lights between cottages
    for (a, b) in [((260 + 150, 1000), (640 - 120, 980)), ((980 + 130, 1010), (1220 - 90, 980)), ((1880 + 125, 995), (2230 - 150, 990))]:
        ctrl = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2 + 60)
        wire = Mask()
        pts = []
        for t in np.linspace(0, 1, 30):
            u = 1 - t
            pts.append((u * u * a[0] + 2 * u * t * ctrl[0] + t * t * b[0], u * u * a[1] + 2 * u * t * ctrl[1] + t * t * b[1]))
        wire.line(pts, 2)
        comp(cv, wire.get(0.6), (0.08, 0.08, 0.1))
        for p in pts[2:-2:3]:
            feats["lights"].append([p[0] / W, (p[1] + 6) / H])
            glow(cv, p[0], p[1] + 6, 10, (0.9, 0.7, 0.4), 0.45)
    # lamp posts
    for lx in (470, 1380, 2060):
        post = Mask(); post.rect(lx - 5, 1190, lx + 5, 1370); post.rect(lx - 16, 1160, lx + 16, 1196); comp(cv, post.get(0.8), (0.1, 0.1, 0.12))
        lamp = Mask(); lamp.rect(lx - 11, 1166, lx + 11, 1190); comp(cv, lamp.get(0.8), (1.0, 0.85, 0.5))
        glow(cv, lx, 1178, 130, (0.55, 0.32, 0.1), 0.5)
        glow(cv, lx, 1380, 160, (0.4, 0.22, 0.08), 0.3)
        feats["glows"].append([lx / W, 1178 / H, 160 / W])
    # foreground snow with path
    fg = 1330 + 30 * np.sin(np.arange(W) / 230.0 + 2)
    comp(cv, below_line_mask(fg, 3), (0.70, 0.69, 0.92))
    for _ in range(450):
        x, y = r.uniform(0, W), r.uniform(1200, H)
        glow(cv, x, y, r.uniform(0.6, 1.3), (1, 1, 1), r.uniform(0.3, 0.9))
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    v = 1 - 0.35 * (((xx - W / 2) / (W * 0.7)) ** 2 + ((yy - H / 2) / (H * 0.75)) ** 2)
    cv *= np.clip(v, 0.55, 1)[..., None]
    save(cv, "../Resources/bg-village.jpg")
    json.dump(feats, open("../Resources/bg-village.json", "w"))


if __name__ == "__main__":
    main()
