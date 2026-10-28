"""Quick 3D FK + prop-clearance checker (mirrors lib/mannequin/skeleton.dart and
the torso/head ellipsoids of mannequin_renderer.dart buildBody()).

Usage: python3 -B tool/pose_check.py [exercise_id ...]
Prints the minimum clearance (normalised; >= 1 means no contact) between each
grip prop axis and the chest/pelvis/abdomen/head ellipsoids, per key frame and
for intermediate samples of each transition.
"""
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
D = math.pi / 180


def v(x, y, z):
    return (x, y, z)


def add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def mul(a, s):
    return (a[0] * s, a[1] * s, a[2] * s)


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def unit(a):
    l = math.sqrt(dot(a, a))
    return mul(a, 1 / l) if l > 1e-12 else a


def seg(a, b, sign):
    a, b = a * D, b * D
    return (math.cos(a) * math.cos(b), math.sin(a) * math.cos(b), sign * math.sin(b))


KEYS = ['t', 'hd', 'tb', 'ua1', 'la1', 'ua2', 'la2', 'th1', 'sh1', 'th2', 'sh2',
        'ua1b', 'la1b', 'ua2b', 'la2b', 'th1b', 'sh1b', 'th2b', 'sh2b']


def pose_of(frame):
    a = frame['a']
    t = a.get('t', 90)
    p = {'t': t, 'hd': a.get('hd', t), 'tb': a.get('tb', 0)}
    for k in KEYS[3:]:
        p[k] = a.get(k, 0 if k.endswith('b') else 270)
    at = frame['at']
    return p, (at[0], at[1], at[2] if len(at) > 2 else None)


def solve(p, at, anchor):
    t, tb, hd = p['t'] * D, p['tb'] * D, p['hd'] * D
    t0 = (math.cos(t), math.sin(t), 0)
    T = add(mul(t0, math.cos(tb)), (0, 0, math.sin(tb)))
    F = (math.sin(t), -math.cos(t), 0)
    L = sub((0, 0, math.cos(tb)), mul(t0, math.sin(tb)))
    h0 = (math.cos(hd), math.sin(hd), 0)
    HA = add(mul(h0, math.cos(tb)), (0, 0, math.sin(tb)))
    HF = (math.sin(hd), -math.cos(hd), 0)
    j = {'hip': (0, 0, 0)}
    j['neck'] = mul(T, 24)
    j['head'] = add(j['neck'], mul(HA, 8))
    for s, sign in (('1', 1), ('2', -1)):
        sh = add(j['neck'], mul(L, 7 * sign))
        hp = mul(L, 4.5 * sign)
        j['s' + s] = sh
        j['e' + s] = add(sh, mul(seg(p['ua' + s], p['ua' + s + 'b'], sign), 12))
        j['w' + s] = add(j['e' + s], mul(seg(p['la' + s], p['la' + s + 'b'], sign), 11))
        j['h' + s] = hp
        j['k' + s] = add(hp, mul(seg(p['th' + s], p['th' + s + 'b'], sign), 16))
        j['f' + s] = add(j['k' + s], mul(seg(p['sh' + s], p['sh' + s + 'b'], sign), 16))
    an = j['sh' if anchor == 'sh' else anchor] if anchor != 'sh' else j['neck']
    tgt = (at[0], -at[1], an[2] if at[2] is None else at[2])
    off = sub(tgt, an)
    j = {k: add(q, off) for k, q in j.items()}
    return j, T, F, L, HA, HF


# torso parts (t, f, rl, rt, rf) -- keep in sync with TorsoPart in
# lib/mannequin/mannequin_renderer.dart
TORSO = {
    'pelvis': (1.35, -0.45, 6.13, 6.62, 3.78),
    'abdomen': (6.64, 0.3, 5.73, 9.07, 3.42),
    'ribcage': (16.81, 0.37, 7.46, 9.09, 4.42),
    'chest': (20.11, 0.37, 8.21, 5.59, 4.84),
}


def _cut(a, b, n=1440):
    """Plane (nT, nF, off) through the front/back intersection points of the
    mid-sagittal sections of torso parts a, b (mirrors TorsoCut.between)."""
    def g(th):
        t = a[0] + a[3] * math.cos(th)
        f = a[1] + a[4] * math.sin(th)
        return ((t - b[0]) / b[3]) ** 2 + ((f - b[1]) / b[4]) ** 2 - 1
    pts = []
    prev = g(0)
    for i in range(1, n + 1):
        th = 2 * math.pi * i / n
        cur = g(th)
        if (prev < 0) != (cur < 0):
            lo, hi = 2 * math.pi * (i - 1) / n, th
            s_lo = prev < 0
            for _ in range(40):
                m = (lo + hi) / 2
                if (g(m) < 0) == s_lo:
                    lo = m
                else:
                    hi = m
            pts.append((a[0] + a[3] * math.cos(lo), a[1] + a[4] * math.sin(lo)))
        prev = cur
    front = max(pts, key=lambda q: q[1])
    back = min(pts, key=lambda q: q[1])
    nt, nf = front[1] - back[1], -(front[0] - back[0])
    l = math.hypot(nt, nf)
    nt, nf = nt / l, nf / l
    if nt < 0:
        nt, nf = -nt, -nf
    return nt, nf, nt * front[0] + nf * front[1]


ORDER = ['pelvis', 'abdomen', 'ribcage', 'chest']
CUTS = [_cut(TORSO[ORDER[i]], TORSO[ORDER[i + 1]]) for i in range(3)]


def keeps(i, t, f, margin=0.0):
    if i > 0:
        nt, nf, off = CUTS[i - 1]
        if nt * t + nf * f < off - margin:
            return False
    if i < 3:
        nt, nf, off = CUTS[i]
        if nt * t + nf * f > off + margin:
            return False
    return True


def ellipsoids(j, T, F, L, HA, HF):
    hip = j['hip']
    out = {}
    for name, (t, f, rl, rt, rf) in TORSO.items():
        out[name] = (add(hip, add(mul(T, t), mul(F, f))), [mul(L, rl), mul(T, rt), mul(F, rf)])
    out['head'] = (add(j['head'], mul(HA, 0.7)), [mul(unit(cross(HF, HA)), 4.0), mul(HA, 4.85), mul(HF, 4.5)])
    return out


def norm_dist(p, c, axes, infl):
    d = sub(p, c)
    s = 0
    for a in axes:
        l = math.sqrt(dot(a, a))
        u = dot(d, a) / l
        s += (u / (l + infl)) ** 2
    return math.sqrt(s)


def grips(props):
    g = []
    fy = None
    for p in props:
        if p['k'] == 'floor':
            fy = -(p.get('y', 88) + 2.6)
        if 'floor' in p:
            fy = -(p['floor'] + 2.6)
    for p in props:
        if p['k'] == 'bar':
            x, y = p.get('x', 50), -p.get('y', 12)
            g.append(('bar', (x, y, -21), (x, y, 21), 1.2))
        elif p['k'] == 'pole':
            x = p.get('x', 30)
            f = fy if fy is not None else -90.6
            g.append(('pole', (x, f, 0), (x, f + 260, 0), 1.7))
        elif p['k'] == 'pbars':
            y = -p.get('y', 52)
            for zz in (-10, 10):
                g.append(('pbar', (p.get('x1', 25), y, zz), (p.get('x2', 80), y, zz), 1.3))
    return g


def clearance(j, T, F, L, HA, HF, gl, margin=0.3):
    ell = ellipsoids(j, T, F, L, HA, HF)
    worst = (99, '')
    for name, a, b, r in gl:
        n = 400
        for i in range(n + 1):
            p = add(a, mul(sub(b, a), i / n))
            rel = sub(p, j['hip'])
            for en, (c, axes) in ell.items():
                if en in ORDER and not keeps(ORDER.index(en), dot(rel, T), dot(rel, F), r + margin):
                    continue
                d = norm_dist(p, c, axes, r + margin)
                if d < worst[0]:
                    worst = (d, '%s~%s' % (name, en))
    return worst


def lerp_angle(a, b, u):
    d = (b - a) % 360
    if d > 180:
        d -= 360
    return a + d * u


def ease(u):
    return u * u * (3 - 2 * u)


def interp(f0, f1, u):
    p0, a0 = pose_of(f0)
    p1, a1 = pose_of(f1)
    e = ease(u)
    p = {k: lerp_angle(p0[k], p1[k], e) for k in p0}
    at = (a0[0] + (a1[0] - a0[0]) * e, a0[1] + (a1[1] - a0[1]) * e,
          None if a0[2] is None or a1[2] is None else a0[2] + (a1[2] - a0[2]) * e)
    return p, at


def check(ex, verbose=True):
    an = ex['anim']
    gl = grips(an.get('props', []))
    frames = an['frames']
    bad = []
    if not gl:
        return bad
    n = len(frames)
    segs = [(i, (i + 1) % n) for i in range(n)] if an.get('loop') == 'cycle' else [(i, i + 1) for i in range(n - 1)]
    for i, f in enumerate(frames):
        p, at = pose_of(f)
        r = clearance(*solve(p, at, an['anchor']), gl)
        if verbose:
            print('  frame %d: %.2f %s' % (i, r[0], r[1]))
        if r[0] < 1:
            bad.append(('f%d' % i, r))
    for a, b in segs:
        for u in (0.25, 0.5, 0.75):
            p, at = interp(frames[a], frames[b], u)
            r = clearance(*solve(p, at, an['anchor']), gl)
            if verbose:
                print('  %d->%d @%.2f: %.2f %s' % (a, b, u, r[0], r[1]))
            if r[0] < 1:
                bad.append(('%d->%d@%.2f' % (a, b, u), r))
    return bad


def com(j, T):
    """Approximate centre of mass (segment mass fractions)."""
    def mid(a, b, f=0.5):
        return add(j[a], mul(sub(j[b], j[a]), f))
    parts = [(0.08, j['head']), (0.50, add(j['hip'], mul(T, 11.0)))]
    for s in '12':
        parts += [(0.028, mid('s' + s, 'e' + s, 0.44)), (0.022, mid('e' + s, 'w' + s, 0.6)),
                  (0.10, mid('h' + s, 'k' + s, 0.43)), (0.06, mid('k' + s, 'f' + s, 0.55))]
    m = sum(p[0] for p in parts)
    return tuple(sum(p[0] * p[1][i] for p in parts) / m for i in range(3))


# static balance checks: (exercise, frame index, support joint, max |dx|)
BALANCE = [
    ('cal_strict_muscle_up', 3, 'bar', 3.0),
    ('cal_negative_muscle_up', 1, 'bar', 3.0),
    ('cal_full_planche', 0, 'w1', 2.0),
    ('cal_full_planche', 1, 'w1', 2.0),
]


def check_balance(data):
    ex = {e['id']: e for e in data}
    bad = []
    for eid, fi, sup, lim in BALANCE:
        an = ex[eid]['anim']
        p, at = pose_of(an['frames'][fi])
        j, T, F, L, HA, HF = solve(p, at, an['anchor'])
        c = com(j, T)
        if sup == 'bar':
            sx = [q for q in an['props'] if q['k'] == 'bar'][0].get('x', 50)
        else:
            sx = j[sup][0]
        if abs(c[0] - sx) > lim:
            bad.append('%s f%d CoM.x %.1f vs support %.1f' % (eid, fi, c[0], sx))
    return bad


if __name__ == '__main__':
    data = json.load(open(os.path.join(HERE, '..', 'assets', 'exercises.json')))
    ids = sys.argv[1:]
    if not ids:
        for b in check_balance(data):
            print('BALANCE', b)
    for ex in data:
        if ids and ex['id'] not in ids:
            continue
        if not ids:
            bad = check(ex, verbose=False)
            if bad:
                print(ex['id'], 'BAD', ['%s %.2f %s' % (k, r[0], r[1]) for k, r in bad][:4])
        else:
            print(ex['id'])
            check(ex)
