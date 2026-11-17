"""Small painting toolkit (numpy + Pillow) used to render WinterDesk's backgrounds."""
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

W, H = 2560, 1600


def rng(seed):
    return np.random.default_rng(seed)


def col(*c):
    return np.array(c, np.float32)


def canvas(color=(0, 0, 0)):
    c = np.zeros((H, W, 3), np.float32)
    c[:] = color
    return c


def vgrad(stops):
    """stops: list of (y_fraction, (r,g,b)). Returns HxWx3."""
    ys = np.linspace(0, 1, H, dtype=np.float32)
    out = np.zeros((H, 3), np.float32)
    fr = [s[0] for s in stops]
    for ch in range(3):
        out[:, ch] = np.interp(ys, fr, [s[1][ch] for s in stops])
    return np.repeat(out[:, None, :], W, axis=1)


class Mask:
    """Draw many shapes onto one anti-aliased mask."""

    def __init__(self, ss=2):
        self.ss = ss
        self.img = Image.new("L", (W * ss, H * ss), 0)
        self.d = ImageDraw.Draw(self.img)

    def poly(self, pts, v=255):
        s = self.ss
        self.d.polygon([(x * s, y * s) for x, y in pts], fill=v)

    def ellipse(self, cx, cy, rx, ry, v=255):
        s = self.ss
        self.d.ellipse([(cx - rx) * s, (cy - ry) * s, (cx + rx) * s, (cy + ry) * s], fill=v)

    def rect(self, x0, y0, x1, y1, v=255):
        s = self.ss
        self.d.rectangle([x0 * s, y0 * s, x1 * s, y1 * s], fill=v)

    def line(self, pts, width, v=255):
        s = self.ss
        self.d.line([(x * s, y * s) for x, y in pts], fill=v, width=max(1, int(width * s)), joint="curve")

    def get(self, blur=0.0):
        img = self.img.resize((W, H), Image.LANCZOS)
        if blur > 0:
            img = img.filter(ImageFilter.GaussianBlur(blur))
        return np.asarray(img, np.float32) / 255.0


def comp(cv, mask, color, alpha=1.0):
    m = (mask * alpha)[..., None]
    if not isinstance(color, np.ndarray) or color.ndim == 1:
        color = np.asarray(color, np.float32)
    cv *= (1 - m)
    cv += m * color


def glow(cv, cx, cy, r, color, strength=1.0, add=True):
    """Soft gaussian light, added (light) or blended."""
    x0, x1 = int(max(0, cx - 3 * r)), int(min(W, cx + 3 * r))
    y0, y1 = int(max(0, cy - 3 * r)), int(min(H, cy + 3 * r))
    if x1 <= x0 or y1 <= y0:
        return
    yy, xx = np.mgrid[y0:y1, x0:x1].astype(np.float32)
    g = np.exp(-((xx - cx) ** 2 + (yy - cy) ** 2) / (2 * r * r)) * strength
    patch = cv[y0:y1, x0:x1]
    if add:
        patch += g[..., None] * np.asarray(color, np.float32)
    else:
        m = np.clip(g, 0, 1)[..., None]
        patch *= (1 - m)
        patch += m * np.asarray(color, np.float32)


def noise(seed, cells_x, cells_y=None, octaves=4, persistence=0.5):
    """Smooth value noise in 0..1, HxW."""
    r = rng(seed)
    cells_y = cells_y or max(2, int(cells_x * H / W))
    total = np.zeros((H, W), np.float32)
    amp, norm = 1.0, 0.0
    for o in range(octaves):
        cx, cy = cells_x * 2 ** o, cells_y * 2 ** o
        g = (r.random((cy + 1, cx + 1)) * 255).astype(np.uint8)
        img = Image.fromarray(g).resize((W, H), Image.BICUBIC)
        total += np.asarray(img, np.float32) / 255.0 * amp
        norm += amp
        amp *= persistence
    return total / norm


def ridge(seed, y_base, amp, rough=0.55, points=1025):
    """1D fractal ridge line (midpoint displacement), returns y for each x pixel."""
    r = rng(seed)
    n = points
    ys = np.zeros(n, np.float32)
    ys[0], ys[-1] = r.uniform(-1, 1), r.uniform(-1, 1)
    step, scale = n - 1, 1.0
    while step > 1:
        half = step // 2
        for i in range(half, n - 1, step):
            ys[i] = (ys[i - half] + ys[i + half]) / 2 + r.uniform(-1, 1) * scale
        step = half
        scale *= rough
    ys = ys / (np.abs(ys).max() + 1e-6)
    xs = np.linspace(0, W, n)
    return y_base + np.interp(np.arange(W), xs, ys) * amp


def below_line_mask(line_y, blur=1.0):
    yy = np.arange(H, dtype=np.float32)[:, None]
    m = np.clip(yy - line_y[None, :] + 0.5, 0, 1)
    if blur:
        img = Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(blur))
        m = np.asarray(img, np.float32) / 255
    return m


def stars(cv, seed, count, y_max, bright=1.0):
    r = rng(seed)
    for _ in range(count):
        x, y = r.uniform(0, W), r.uniform(0, y_max) ** 1.0
        b = r.uniform(0.25, 1.0) ** 2 * bright
        size = r.uniform(0.7, 1.6) if b < 0.6 else r.uniform(1.2, 2.4)
        glow(cv, x, y, size, (b, b, b * 0.95), 1.0)
        if b > 0.7:
            glow(cv, x, y, size * 4, (0.5, 0.55, 0.8), 0.08)


def pine(m_body, m_snow, x, base, h, r, snow=0.8, lean=0.0):
    """A snowy pine: jagged dark body + lumpy snow on the upper side of each tier."""
    tiers = int(np.clip(h / 20, 5, 13))
    top = base - h
    trunk_w = max(1.5, h * 0.022)
    m_body.rect(x - trunk_w, base - h * 0.12, x + trunk_w, base)
    left, right = [(x, top)], []
    step = h * 0.9 / tiers
    for i in range(tiers):
        t = (i + 1) / tiers
        yb = top + h * 0.9 * t
        w = h * (0.04 + 0.27 * t) * r.uniform(0.85, 1.12)
        inner = w * r.uniform(0.2, 0.4)
        droop = step * r.uniform(0.1, 0.35)
        left += [(x - w * 0.8, yb - droop * 0.5), (x - w, yb + droop), (x - inner, yb - step * 0.45)]
        right += [(x + w * 0.8, yb - droop * 0.5), (x + w, yb + droop), (x + inner, yb - step * 0.45)]
        if snow > 0:
            for side in (-1, 1):
                if r.random() > snow:
                    continue
                n = r.integers(2, 5)
                for k in range(n):
                    f = (k + 0.5) / n
                    ex = x + side * (inner + (w - inner) * f * 0.95)
                    ey = yb - step * 0.42 + (step * 0.42 + droop) * f * 0.8
                    m_snow.ellipse(ex, ey, w * r.uniform(0.12, 0.22), step * r.uniform(0.13, 0.2))
    m_body.poly(left + list(reversed(right)))
    m_snow.ellipse(x, top + h * 0.05, h * 0.02, h * 0.035)


def shifted(m, dy):
    out = np.zeros_like(m)
    if dy > 0:
        out[:-dy] = m[dy:]
    else:
        out[-dy:] = m[:dy]
    return out


def snow_fill(cv, m, top_color, rim_color, rim=10, shade=(0.55, 0.55, 0.85), shade_px=0):
    """Fill a snow mask: bright body, warm/lit rim along its bottom edge."""
    comp(cv, m, top_color)
    if rim:
        rimm = np.clip(m - shifted(m, rim), 0, 1)
        comp(cv, rimm, rim_color, 0.9)
    if shade_px:
        sh = np.clip(m - shifted(m, -shade_px), 0, 1)  # top edge
        comp(cv, sh, (1, 1, 1), 0.25)


def jag(a, b, r, rough, n=6):
    """Jagged line from a to b via midpoint displacement (perpendicular)."""
    pts = [a, b]
    amp = math.hypot(b[0] - a[0], b[1] - a[1]) * rough
    for _ in range(n):
        new = [pts[0]]
        for p, q in zip(pts, pts[1:]):
            mx, my = (p[0] + q[0]) / 2, (p[1] + q[1]) / 2
            dx, dy = q[0] - p[0], q[1] - p[1]
            L = math.hypot(dx, dy) + 1e-6
            off = r.uniform(-1, 1) * amp
            new += [(mx - dy / L * off, my + dx / L * off), q]
        pts = new
        amp *= 0.5
    return pts


def mountain_range(cv, r, peaks, base_y, lit, shadow, snow_lit, snow_shadow, haze=None, haze_amt=0.0):
    """peaks: list of (x, apex_y, half_width). Light comes from the right."""
    for (px, py, bw) in peaks:
        apex = (px, py)
        L, R = (px - bw, base_y), (px + bw, base_y)
        left = jag(apex, L, r, 0.06)
        right = jag(apex, R, r, 0.06)
        mid = jag(apex, (px + r.uniform(-0.15, 0.15) * bw, base_y), r, 0.05)
        body = Mask(); body.poly(left + list(reversed(right))); bm = body.get(0.8)
        comp(cv, bm, lit)
        sh = Mask(); sh.poly(left + list(reversed(mid))); comp(cv, sh.get(1.0), shadow)
        # snow cap: down to a jagged line ~40% of the height
        cap_h = (base_y - py) * r.uniform(0.32, 0.5)
        drip = []
        steps = 18
        for i in range(steps + 1):
            t = i / steps
            x = px - bw * (cap_h / (base_y - py)) * (1 - 2 * t) * 1.0
            y = py + cap_h * (0.65 + 0.35 * r.random()) + (r.uniform(0, 1) ** 2) * cap_h * 0.6 * (i % 2)
            drip.append((x, y))
        capl = [p for p in left if p[1] <= py + cap_h * 1.1]
        capr = [p for p in right if p[1] <= py + cap_h * 1.1]
        cap = Mask(); cap.poly(capl + drip + list(reversed(capr))); cm = cap.get(0.8) * bm
        comp(cv, cm, snow_lit)
        capsh = Mask(); capsh.poly(left + list(reversed(mid))); comp(cv, cm * capsh.get(1.0), snow_shadow)
        # streaks of snow in the gullies below the cap
        st = Mask()
        for _ in range(int(bw / 14)):
            x0 = px + r.uniform(-0.8, 0.8) * bw * 0.6
            y0 = py + cap_h * r.uniform(0.7, 1.1)
            st.line(jag((x0, y0), (x0 + r.uniform(-30, 30), y0 + r.uniform(40, 160)), r, 0.15, 3), r.uniform(2, 5))
        comp(cv, st.get(1.2) * bm, snow_lit, 0.55)
        if haze is not None:
            comp(cv, bm, haze, haze_amt)


def save(cv, path, quality=88):
    img = Image.fromarray((np.clip(cv, 0, 1) * 255).astype(np.uint8))
    img.save(path, quality=quality, optimize=True, progressive=True)
    return img
