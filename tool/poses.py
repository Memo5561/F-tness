"""Strichfiguren-Kinematik für Calisthenics-Animationen (identisch zu lib/widgets/pose_painter.dart)."""
import math

L = dict(neck=3, head=5, torso=24, ua=12, la=11, th=16, sh=16)

def _v(a, l):
    r = math.radians(a)
    return (math.cos(r) * l, -math.sin(r) * l)

def fk(a):
    """a: Winkel in Grad (0=rechts, 90=oben). Liefert Gelenkpositionen relativ zur Hüfte."""
    hip = (0.0, 0.0)
    def add(p, ang, l):
        d = _v(ang, l)
        return (p[0] + d[0], p[1] + d[1])
    sh = add(hip, a['t'], L['torso'])
    head = add(sh, a.get('hd', a['t']), L['neck'] + L['head'])
    j = dict(hip=hip, sh=sh, head=head)
    for s in '12':
        j['e' + s] = add(sh, a['ua' + s], L['ua'])
        j['w' + s] = add(j['e' + s], a['la' + s], L['la'])
        j['k' + s] = add(hip, a['th' + s], L['th'])
        j['f' + s] = add(j['k' + s], a['sh' + s], L['sh'])
    return j

def place(frame, anchor):
    j = fk(frame['a'])
    ax, ay = j[anchor]
    tx, ty = frame['at']
    return {k: (x - ax + tx, y - ay + ty) for k, (x, y) in j.items()}
