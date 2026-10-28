import math, sys
from PIL import Image, ImageDraw

def inter_tf(A, B):
    """Intersections of the T-F sections (l=0) of torso ellipsoids A, B: list of (t,f)."""
    ta, fa, la, rta, rfa = A['t'], A['f'], A['rl'], A['rt'], A['rf']
    tb, fb, lb, rtb, rfb = B['t'], B['f'], B['rl'], B['rt'], B['rf']
    def g(th):
        t = ta + rta * math.cos(th); f = fa + rfa * math.sin(th)
        return ((t - tb) / rtb) ** 2 + ((f - fb) / rfb) ** 2 - 1, t, f
    N = 3600
    out = []
    prev = g(0)
    for i in range(1, N + 1):
        th = 2 * math.pi * i / N
        cur = g(th)
        if (prev[0] < 0) != (cur[0] < 0):
            # bisect
            lo, hi = 2 * math.pi * (i - 1) / N, th
            for _ in range(40):
                m = (lo + hi) / 2
                if (g(m)[0] < 0) == (g(lo)[0] < 0): lo = m
                else: hi = m
            out.append(g(lo)[1:])
        prev = cur
    return out

def plane(A, B):
    pts = inter_tf(A, B)
    front = max(pts, key=lambda p: p[1]); back = min(pts, key=lambda p: p[1])
    dt, df = front[0] - back[0], front[1] - back[1]
    n = (df, -dt)  # normal in (t, f)
    l = math.hypot(*n); n = (n[0] / l, n[1] / l)
    if n[0] < 0: n = (-n[0], -n[1])
    off = n[0] * front[0] + n[1] * front[1]
    return n, off, front, back

def lat_at_plane(P, n, off):
    # max l over the intersection of the plane with ellipsoid P
    best = 0
    for i in range(2001):
        f = P['f'] - P['rf'] + 2 * P['rf'] * i / 2000
        t = (off - n[1] * f) / n[0]
        s = 1 - ((t - P['t']) / P['rt']) ** 2 - ((f - P['f']) / P['rf']) ** 2
        if s > 0: best = max(best, P['rl'] * math.sqrt(s))
    return best

def design(parts, name='design', scale=10, delta=0.0):
    planes = []
    for A, B in zip(parts, parts[1:]):
        n, off, fr, bk = plane(A, B)
        la, lb = lat_at_plane(A, n, off), lat_at_plane(B, n, off)
        planes.append((n, off))
        print('%s|%s plane n=(%.3f,%.3f) off=%.2f front=(%.2f,%.2f) back=(%.2f,%.2f) lat %.2f vs %.2f (diff %.2f) tilt %.1f deg'
              % (A['n'], B['n'], n[0], n[1], off, fr[0], fr[1], bk[0], bk[1], la, lb, la - lb, math.degrees(math.atan2(n[1], n[0]))))
    # kept test for part i at (t, f)
    def kept(i, t, f):
        if i > 0:
            n, off = planes[i - 1]
            if n[0] * t + n[1] * f < off - delta: return False
        if i < len(parts) - 1:
            n, off = planes[i]
            if n[0] * t + n[1] * f > off + delta: return False
        return True
    W = 30 * scale; H = 36 * scale
    cols = [(200, 120, 120), (120, 200, 120), (120, 120, 220), (210, 200, 110), (200, 120, 200)]
    imgs = []
    for view in ('front', 'side'):
        im = Image.new('RGB', (W, H), (20, 20, 20))
        px = im.load()
        for y in range(H):
            t = 30 - y / scale
            for x in range(W):
                h = (x - W / 2) / scale
                hit = None
                for i, P in enumerate(parts):
                    if view == 'front':
                        l = h
                        s = 1 - (l / P['rl']) ** 2 - ((t - P['t']) / P['rt']) ** 2
                        if s <= 0: continue
                        rng = P['rf'] * math.sqrt(s)
                        fs = [P['f'] - rng + 2 * rng * k / 12 for k in range(13)]
                        if any(kept(i, t, f) for f in fs): hit = i; break
                    else:
                        f = h
                        s = 1 - ((f - P['f']) / P['rf']) ** 2 - ((t - P['t']) / P['rt']) ** 2
                        if s <= 0: continue
                        if kept(i, t, f): hit = i; break
                if hit is not None: px[x, y] = cols[hit]
        d = ImageDraw.Draw(im)
        for tt in range(-5, 31, 5):
            yy = int((30 - tt) * scale); d.line([(0, yy), (8, yy)], fill=(90, 90, 90))
        imgs.append(im)
    out = Image.new('RGB', (2 * W + 10, H), (60, 60, 60)); out.paste(imgs[0], (0, 0)); out.paste(imgs[1], (W + 10, 0))
    out.save(name + '.png')
    return planes

def P(n, t, f, rl, rt, rf): return dict(n=n, t=t, f=f, rl=rl, rt=rt, rf=rf)
if __name__ == '__main__':
    exec(open(sys.argv[1]).read())
