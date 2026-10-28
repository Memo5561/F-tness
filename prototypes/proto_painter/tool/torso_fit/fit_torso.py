"""Fits the four torso ellipsoids (pelvis, waist, ribcage, chest) to a target
front/side profile for the cut-plane union renderer (TorsoPart/TorsoCut in
lib/mannequin/mannequin_renderer.dart). Penalises silhouette steps at the cuts
and slope changes (SW), limits the waist/ribcage length (RTMAX).

Usage: cd tool/torso_fit && RTMAX=9 SW=1.0 OUT=fit python3 fit_torso.py
Prints the parameters (t, f, rl, rt, rf per piece) and writes OUT.png
(front | side silhouettes coloured by piece). The shipped values are the
RTMAX=9 SW=1.0 result. Needs numpy.
"""
import math, sys, json
import numpy as np
from cutdesign import design, P
from fastcut import plane, lat_at_plane

TL = [(-3, 4.6), (-1, 5.5), (1, 5.85), (3, 5.85), (5, 5.7), (7, 5.55), (9, 5.5), (11, 5.75), (13, 6.4),
      (15, 7.1), (17, 7.75), (19, 8.15), (21, 8.2), (23, 7.5), (24.5, 5.8)]
TF = [(-3, 2.6), (-1, 3.4), (1, 3.7), (3, 3.7), (5, 3.5), (7, 3.45), (9, 3.55), (11, 3.85), (13, 4.3),
      (15, 4.75), (17, 5.0), (19, 5.15), (21, 5.0), (23, 4.3), (24.5, 3.0)]
TB = [(-3, -3.4), (-1, -4.3), (1, -4.45), (3, -4.1), (5, -3.5), (7, -3.15), (9, -3.1), (11, -3.3), (13, -3.6),
      (15, -3.9), (17, -4.1), (19, -4.2), (21, -4.1), (23, -3.6), (24.5, -2.6)]
NAMES = ['pelvis', 'abdomen', 'ribcage', 'chest']
RTMAX = float(__import__('os').environ.get('RTMAX', '99'))
SW = float(__import__('os').environ.get('SW', '0.6'))

def parts_of(x):
    return [P(NAMES[i], *x[5*i:5*i+5]) for i in range(4)]

def model(x):
    parts = parts_of(x)
    for p in parts:
        if min(p['rl'], p['rt'], p['rf']) < 0.5: return None
    planes = []
    mis = 0
    for A, B in zip(parts, parts[1:]):
        try:
            n, off, fr, bk = plane(A, B)
        except ValueError:
            return None
        planes.append((n, off))
        mis += (lat_at_plane(A, n, off) - lat_at_plane(B, n, off)) ** 2
    def kept(i, t, f):
        if i > 0:
            n, off = planes[i-1]
            if n[0]*t + n[1]*f < off - 1e-9: return False
        if i < 3:
            n, off = planes[i]
            if n[0]*t + n[1]*f > off + 1e-9: return False
        return True
    return parts, planes, kept, mis

def lat(parts, kept, t):
    best = 0
    for i, p in enumerate(parts):
        s = 1 - ((t - p['t'])/p['rt'])**2
        if s <= 0: continue
        if kept(i, t, p['f']): best = max(best, p['rl']*math.sqrt(s))
    return best

def edge(parts, kept, t, sign):
    best = None
    for i, p in enumerate(parts):
        s = 1 - ((t - p['t'])/p['rt'])**2
        if s <= 0: continue
        f = p['f'] + sign * p['rf'] * math.sqrt(s)
        if kept(i, t, f):
            if best is None or sign * f > sign * best: best = f
    return best

def cost(x):
    m = model(x)
    if m is None: return 1e9
    parts, planes, kept, mis = m
    c = 30 * mis
    for t, w in TL:
        c += (lat(parts, kept, t) - w) ** 2
    for t, w in TF:
        e = edge(parts, kept, t, 1); c += 4 if e is None else (e - w) ** 2
    for t, w in TB:
        e = edge(parts, kept, t, -1); c += 4 if e is None else (e - w) ** 2
    bot = parts[0]['t'] - parts[0]['rt']; top = parts[3]['t'] + parts[3]['rt']
    for p_ in parts[1:3]:
        if p_['rt'] > RTMAX: c += 3 * (p_['rt'] - RTMAX) ** 2
    c += 0.5 * (bot + 5.0) ** 2 + 2 * (top - 25.2) ** 2
    # tangent joins (front and side silhouettes) where possible
    for k, (n, off) in enumerate(planes):
        A, B = parts[k], parts[k + 1]
        tc = off / n[0]
        def slope(Pp, key, t):
            u = (t - Pp['t']) / Pp['rt']
            if abs(u) >= 0.999: return 9.0
            return -Pp[key] * u / (Pp['rt'] * math.sqrt(1 - u * u))
        c += SW * ((slope(A, 'rl', tc) - slope(B, 'rl', tc)) ** 2 + 0.5 * (slope(A, 'rf', tc) - slope(B, 'rf', tc)) ** 2)
    # cut planes inside sensible ranges (t at f=0)
    for (n, off), lo, hi in zip(planes, (3.5, 9.5, 15.0), (7.0, 13.0, 18.5)):
        tc = off / n[0]
        if tc < lo: c += 5 * (lo - tc) ** 2
        if tc > hi: c += 5 * (tc - hi) ** 2
    return c

def nelder_mead(f, x0, step=0.5, iters=4000, tol=1e-7):
    n = len(x0)
    pts = [np.array(x0, float)]
    for i in range(n):
        y = np.array(x0, float); y[i] += step; pts.append(y)
    vals = [f(p) for p in pts]
    for it in range(iters):
        order = np.argsort(vals); pts = [pts[i] for i in order]; vals = [vals[i] for i in order]
        if abs(vals[-1] - vals[0]) < tol: break
        c = np.mean(pts[:-1], axis=0)
        xr = c + (c - pts[-1]); fr = f(xr)
        if fr < vals[0]:
            xe = c + 2 * (c - pts[-1]); fe = f(xe)
            if fe < fr: pts[-1], vals[-1] = xe, fe
            else: pts[-1], vals[-1] = xr, fr
        elif fr < vals[-2]:
            pts[-1], vals[-1] = xr, fr
        else:
            xc = c + 0.5 * (pts[-1] - c); fc = f(xc)
            if fc < vals[-1]: pts[-1], vals[-1] = xc, fc
            else:
                for i in range(1, len(pts)):
                    pts[i] = pts[0] + 0.5 * (pts[i] - pts[0]); vals[i] = f(pts[i])
    i = int(np.argmin(vals))
    return pts[i], vals[i]

if __name__ == '__main__':
    x = [1.5, -0.4, 6.3, 6.0, 4.2, 8.6, 0.35, 5.25, 7.2, 3.75, 15.0, 0.5, 7.0, 5.8, 4.4, 19.8, 0.5, 8.2, 5.0, 4.75]
    print('start', cost(x))
    for rnd in range(6):
        x, v = nelder_mead(cost, x, step=0.6 if rnd < 3 else 0.2)
        print('round', rnd, v, json.dumps([round(float(q), 3) for q in x]), flush=True)
    print(json.dumps([round(float(v), 2) for v in x]))
    parts = parts_of(x)
    for p in parts: print(p)
    design(parts, __import__('os').environ.get('OUT', 'fit1'))
