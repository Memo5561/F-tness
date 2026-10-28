"""Dump the 2D exercise animations to JSON and apply 3D tweaks (abduction etc.).

Usage: python3 tool/make_fixture.py assets/exercises.json

The 2D source (/home/user/F-tness/tool/custom_exercises.py) stays untouched; only
this prototype's fixture copy gets anatomical fixes and 3D-only poses.
"""
import json, sys, copy, math
sys.path.insert(0, '/home/user/F-tness/tool')
import custom_exercises as C

out = {}
for e in C.EX:
    out[e['id']] = copy.deepcopy(e['anim'])

def fr(at, **a):
    return {'at': list(at), 'a': a}

# ---------------------------------------------------------------- 3D helpers
def _n(v):
    l = math.sqrt(sum(x * x for x in v))
    return tuple(x / l for x in v)

def _add(*terms):
    return tuple(sum(s * v[i] for s, v in terms) for i in range(3))

def torso_frame(t, tb=0.0):
    """Same body frame as rig.dart: T up the torso, F chest-forward, L = F x T (side 1)."""
    t, tb = math.radians(t), math.radians(tb)
    T = (math.cos(t) * math.cos(tb), math.sin(t) * math.cos(tb), math.sin(tb))
    F = (math.sin(t), -math.cos(t), 0.0)
    L = (F[1] * T[2] - F[2] * T[1], F[2] * T[0] - F[0] * T[2], F[0] * T[1] - F[1] * T[0])
    return T, F, L

def seg(d, side):
    """Direction (pre-ry world) -> (angle a, abduction b) for the given side (+1/-1)."""
    d = _n(d)
    b = math.degrees(math.asin(max(-1.0, min(1.0, side * d[2]))))
    a = math.degrees(math.atan2(d[1], d[0])) % 360 if abs(d[2]) < 0.9999 else 90.0
    return round(a, 2), round(b, 2)

def sagittal(T, F, L, side, flex, spread=0.0):
    """Limb direction `flex` deg from -T toward F (hip/shoulder flexion), rotated
    `spread` deg away from the midline (toward side*L)."""
    f, s = math.radians(flex), math.radians(spread)
    d = _n(_add((math.cos(f), tuple(-x for x in T)), (math.sin(f), F)))
    return _n(_add((math.cos(s), d), (side * math.sin(s), L)))

# ----------------------------------------------------------- jumping jack
# Arms move in the frontal plane (abduction), legs straddle. Arms-up is a
# slight "Y" so every channel moves < 150 deg per transition.
out['cal_jumping_jack']['frames'] = [
    fr((50, 56), t=90, ua1=270, la1=270, ua2=270, la2=270, ua1b=8, la1b=6, ua2b=8, la2b=6,
       th1=270, sh1=270, th2=270, sh2=270, th1b=2, sh1b=0, th2b=2, sh2b=0),
    fr((50, 54), t=90, ua1=270, la1=270, ua2=270, la2=270, ua1b=154, la1b=155, ua2b=154, la2b=155,
       th1=270, sh1=270, th2=270, sh2=270, th1b=17, sh1b=15, th2b=17, sh2b=15),
]

# -------------------------------------------------------------- human flag
# Torso leans sideways (tb=90 -> torso along +z, lateral axis vertical), then
# the whole figure is turned about the vertical axis (ry=-90) so the chest
# faces the default camera and the head points to the pole (-x). Side 1 ends
# up at the bottom, so w1 = lower (pushing) hand. Legs: hip flexion `hip`,
# knee flexion `knee` (0/0 = straight flag, ~125/140 = tuck flag).
def flag(tb, arm, spread, hip=0.0, knee=0.0):
    b = 90 - arm   # arm angle off the body axis -> abduction from the sagittal plane
    T, F, L = torso_frame(90, tb)
    a = dict(t=90, tb=tb, ry=-90,
             ua1=270, la1=270, ua1b=b, la1b=b + 2,
             ua2=90, la2=90, ua2b=-b, la2b=-b - 2)
    for s, side in (('1', 1), ('2', -1)):
        a['th' + s], a['th' + s + 'b'] = seg(sagittal(T, F, L, side, hip, spread), side)
        a['sh' + s], a['sh' + s + 'b'] = seg(sagittal(T, F, L, side, hip - knee, spread), side)
    return a

out['cal_human_flag']['frames'] = [
    fr((30, 59), **flag(90, 23, 2)),
    fr((30, 59), **flag(88, 23, 3)),
]
out['cal_human_flag']['anchor'] = 'w1'
# Tuck flag: same 3D flag body, knees pulled to the chest (the 2D data had
# only ~20 deg hip flexion with the shins folded back past the thighs).
out['cal_tuck_human_flag']['frames'] = [
    fr((30, 59), **flag(90, 23, 4, hip=118, knee=135)),
    fr((30, 59), **flag(88, 23, 5, hip=121, knee=138)),
]
out['cal_tuck_human_flag']['anchor'] = 'w1'

# -------------------------------------------------------- tuck front lever
# 2D data: th=40 / sh=235 = only ~40 deg hip flexion with over-folded knees
# (less tuck than the advanced tuck). Real tuck: knees over the sternum,
# heels at the glutes.
for i, f in enumerate(out['cal_tuck_front_lever']['frames']):
    f['a'].update(th1=138 + 2 * i, th2=138 + 2 * i, sh1=350 + 2 * i, sh2=350 + 2 * i)

# ------------------------------------------------- lever / planche arm angles
# Front lever (t=180, head at -x): the bar sits over the lower chest, so the
# straight arms tilt ~16 deg from vertical toward the hips (2D data: 88 =
# almost vertical). Same arms for the tuck lever.
for k in ('cal_front_lever', 'cal_tuck_front_lever'):
    for f in out[k]['frames']:
        f['a'].update(ua1=74, ua2=74, la1=74, la2=74)
# Full planche (t=0, head at +x): shoulders well in front of the hands, the
# hands under the lower ribs (~33 deg forward lean; 2D data: 15 deg, which
# read as an elevated plank). Anchor w1 keeps the hands on the floor.
for f in out['cal_full_planche']['frames']:
    f['a'].update(ua1=237, ua2=237, la1=237, la2=237)

# ------------------------------------------------------------- muscle-ups
# 2D frame 2 (ua=200, la=60) was really a chest-to-bar pull with the bar
# behind the head and a hyper-extended elbow. Real transition: chest over
# the bar, shoulders ~6 above it, elbows behind, torso leaning forward.
MU_HANG = dict(t=90, ua1=94, ua2=94, la1=94, la2=94, th1=268, th2=268, sh1=268, sh2=268)
MU_PULL = dict(t=108, ua1=305, ua2=305, la1=75, la2=75, th1=258, th2=258, sh1=258, sh2=258)
# Transition: chest over the bar, head forward over it, hips flexed ~50 deg
# with the legs hollow and slightly in front under the bar (strict turnover,
# not a kipping plank).
MU_TRANS = dict(t=55, hd=60, ua1=232, ua2=232, la1=18, la2=18, th1=290, th2=290, sh1=284, sh2=284)
MU_SUPP = dict(t=80, ua1=270, ua2=270, la1=270, la2=270, th1=262, th2=262, sh1=262, sh2=262)
mu = [MU_HANG, MU_PULL, MU_TRANS, MU_SUPP]
out['cal_strict_muscle_up']['frames'] = [fr((50, 12), **a) for a in mu]
out['cal_strict_muscle_up']['loop'] = 'pingpong'   # up, then the same path down (no 180 deg wrap)
out['cal_negative_muscle_up']['frames'] = [fr((50, 12), **a) for a in reversed(mu)]
out['cal_negative_muscle_up']['loop'] = 'pingpong'

# Straight bar dip bottom: 2D had the elbow folded 180 deg (wrist at the shoulder).
out['cal_straight_bar_dip']['frames'][1]['a'].update(t=56, hd=66, ua1=215, ua2=215, la1=310, la2=310)

# ---------------------------------------------------------------- pistol
# Bottom was a parallel squat (hip above the knee). Real pistol: hip below
# the knee, torso leaning forward, free leg straight out in front.
out['cal_pistol_squat']['frames'][1]['a'].update(t=54, th1=12, sh1=243, th2=8, sh2=8, ua1=8, ua2=8, la1=8, la2=8)

# ------------------------------------------------------------------ dips
# Hands must reach the parallel bars at z = +-10 -> slight abduction.
for k in ('cal_negative_dip', 'cal_support_hold'):
    for f in out[k]['frames']:
        f['a'].update(ua1b=8, la1b=7, ua2b=8, la2b=7)

json.dump(out, open(sys.argv[1], 'w'), indent=1)
print('wrote', len(out))
