import math
import numpy as np
TH = np.linspace(0, 2 * math.pi, 1441)

def plane(A, B):
    t = A['t'] + A['rt'] * np.cos(TH); f = A['f'] + A['rf'] * np.sin(TH)
    g = ((t - B['t']) / B['rt']) ** 2 + ((f - B['f']) / B['rf']) ** 2 - 1
    idx = np.nonzero(np.sign(g[:-1]) != np.sign(g[1:]))[0]
    if len(idx) < 2: raise ValueError
    pts = []
    for i in idx:
        w = g[i] / (g[i] - g[i + 1])
        pts.append((t[i] + (t[i + 1] - t[i]) * w, f[i] + (f[i + 1] - f[i]) * w))
    front = max(pts, key=lambda p: p[1]); back = min(pts, key=lambda p: p[1])
    dt, df = front[0] - back[0], front[1] - back[1]
    n = (df, -dt); l = math.hypot(*n); n = (n[0] / l, n[1] / l)
    if n[0] < 0: n = (-n[0], -n[1])
    return n, n[0] * front[0] + n[1] * front[1], front, back

def lat_at_plane(P, n, off):
    f = P['f'] + P['rf'] * np.linspace(-1, 1, 401)
    t = (off - n[1] * f) / n[0]
    s = 1 - ((t - P['t']) / P['rt']) ** 2 - ((f - P['f']) / P['rf']) ** 2
    s = s[s > 0]
    return float(P['rl'] * math.sqrt(s.max())) if len(s) else 0.0
