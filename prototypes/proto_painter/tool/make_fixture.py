"""Dump the exercise animations from the reference repo to JSON and apply 3D pose overrides.

Usage: python3 -B tool/make_fixture.py  (writes assets/exercises.json)
The reference module is only imported (read-only).

The 2D stick-figure data ignores body thickness; poses where a bar/pole runs
through the torso are re-designed here with a small inverse-kinematics helper
(place the torso relative to the grip, solve the arm). tool/pose_check.py and
test/prop_clearance_test.dart verify that no grip axis intersects the torso
or head.
"""
import copy
import json
import math
import os
import sys

sys.path.insert(0, '/home/user/F-tness/tool')
import custom_exercises as C  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'assets', 'exercises.json')

ex = {e['id']: copy.deepcopy(e) for e in C.EX}
D = math.pi / 180
UA, LA = 12.0, 11.0


def frames(eid):
    return ex[eid]['anim']['frames']


def ang(dx, dy):
    return math.degrees(math.atan2(dy, dx)) % 360


def arm_ik(sx, sy, wx, wy, elbow='back'):
    """2-link IK in the sagittal plane (world coords, y up). Returns (ua, la)."""
    dx, dy = wx - sx, wy - sy
    d = math.hypot(dx, dy)
    base = math.atan2(dy, dx)
    if d >= UA + LA - 1e-6:
        a = ang(dx, dy)
        return round(a, 1), round(a, 1)
    al = math.acos(max(-1.0, min(1.0, (UA * UA + d * d - LA * LA) / (2 * UA * d))))
    cands = []
    for s in (1, -1):
        ex_, ey_ = sx + UA * math.cos(base + s * al), sy + UA * math.sin(base + s * al)
        cands.append((ex_, ey_))
    key = {'back': lambda e: e[0], 'front': lambda e: -e[0],
           'down': lambda e: e[1], 'up': lambda e: -e[1]}[elbow]
    ex_, ey_ = min(cands, key=key)
    return round(ang(ex_ - sx, ey_ - sy), 1), round(ang(wx - ex_, wy - ey_), 1)


def grip_pose(bar, t, tau, phi, elbow='back'):
    """Torso at angle t (deg) with the grip (bar centre, 2D data coords) at
    hip + T*tau + F*phi (T = torso axis, F = chest-forward). Both hands on the
    grip. Returns the arm angles (ua, la)."""
    bx, by = bar[0], -bar[1]
    tr = t * D
    T = (math.cos(tr), math.sin(tr))
    F = (math.sin(tr), -math.cos(tr))
    hx = bx - T[0] * tau - F[0] * phi
    hy = by - T[1] * tau - F[1] * phi
    sx, sy = hx + T[0] * 24, hy + T[1] * 24
    return arm_ik(sx, sy, bx, by, elbow)


def side_dir(dx, dy, dz, sign):
    """Pose angles (a, b) of a segment pointing along (dx, dy, dz) for side sign."""
    l = math.sqrt(dx * dx + dy * dy + dz * dz)
    dx, dy, dz = dx / l, dy / l, dz / l
    b = math.degrees(math.asin(max(-1.0, min(1.0, sign * dz))))
    a = ang(dx, dy)
    return round(a, 1), round(b, 1)


def bar_frame(t, tau, phi, elbow='back', legs=(262, 262), **extra):
    ua, la = grip_pose((50, 12), t, tau, phi, elbow)
    a = dict(t=t, ua1=ua, ua2=ua, la1=la, la2=la, th1=legs[0], th2=legs[0], sh1=legs[1], sh2=legs[1])
    a.update(extra)
    return {'at': [50, 12], 'a': a}


HANG = {'at': [50, 12], 'a': dict(t=90, ua1=94, ua2=94, la1=94, la2=94, th1=268, th2=268, sh1=268, sh2=268)}
# muscle-up hang: body slightly behind the bar so the arms swing through the
# front (not through the body) on the way to the pull and back from support
MU_HANG = {'at': [50, 12], 'a': dict(t=91, ua1=86, ua2=86, la1=86, la2=86, th1=266, th2=266, sh1=266, sh2=266)}
# pull-up top: bar in front of the upper chest, chin over the bar, elbows down
PULL_TOP = bar_frame(97, 20.5, 7.6, 'down', legs=(263, 263))
# high pull for the muscle-up: slight lean back, bar at the lower chest
MU_PULL = bar_frame(104, 15.5, 7.8, 'down', legs=(258, 258))
# turnover: chest swings forward over the bar, bar at the upper belly,
# elbows behind/above the bar, hips flexing so the legs come under the bar
MU_TURN = bar_frame(60, 10.5, 6.2, 'back', legs=(288, 272))
# deep transition (catch): torso leaning over the bar, elbows high behind it,
# hips flexed and legs slightly forward so the centre of mass is over the
# hands (tool/pose_check.py checks |CoM.x - bar.x| < 3)
MU_TRANS = bar_frame(46, 8.0, 6.0, 'back', legs=(300, 275))
# support on top: straight arms, bar in front of the hips
MU_SUPPORT = bar_frame(74, 1.5, 6.4, 'back', legs=(274, 274))

# --- muscle-up family --------------------------------------------------------
ex['cal_strict_muscle_up']['anim']['frames'] = copy.deepcopy([MU_HANG, MU_PULL, MU_TURN, MU_TRANS, MU_SUPPORT])
ex['cal_negative_muscle_up']['anim']['frames'] = copy.deepcopy([MU_SUPPORT, MU_TRANS, MU_TURN, MU_PULL, MU_HANG])

# --- pull-up tops: the bar sits in front of the upper chest -------------------
for eid in ('cal_flexed_arm_hang',):
    fr = frames(eid)
    fr[0] = copy.deepcopy(PULL_TOP)
    fr[1] = copy.deepcopy(PULL_TOP)
    fr[1]['a']['t'] = 99
    ua, la = grip_pose((50, 12), 99, 20.5, 7.6, 'down')
    fr[1]['a'].update(ua1=ua, ua2=ua, la1=la, la2=la, th1=265, th2=265, sh1=265, sh2=265)
frames('cal_negative_pullup')[0] = copy.deepcopy(PULL_TOP)
# mid position of the negative: bar just above the forehead, elbows forward
ua, la = grip_pose((50, 12), 93, 36.0, 6.0, 'front')
frames('cal_negative_pullup')[1]['a'].update(ua1=ua, ua2=ua, la1=la, la2=la)

# archer: pull with side 1, side 2 straight along the bar (abduction)
arch = frames('cal_archer_pullup')[1]
arch['a'] = dict(PULL_TOP['a'])
arch['at'] = [50, 12, 9.0]
# shoulder 2 position (world) for that pose, then aim arm 2 at the bar at z=-24
_t = arch['a']['t'] * D
_T = (math.cos(_t), math.sin(_t))
_F = (math.sin(_t), -math.cos(_t))
_hip = (50 - _T[0] * 20.5 - _F[0] * 7.6, -12 - _T[1] * 20.5 - _F[1] * 7.6)
_sh = (_hip[0] + _T[0] * 24, _hip[1] + _T[1] * 24)
# body z: hand 1 at z=9 is straight above shoulder 1 (z = body + 7) -> body z = 2
_s2z = 2.0 - 7.0
_dx, _dy = 50 - _sh[0], -12 - _sh[1]
_dz = -math.sqrt(max(1.0, (UA + LA) ** 2 - _dx * _dx - _dy * _dy))
a2, b2 = side_dir(_dx, _dy, _dz, -1)
arch['a'].update(ua2=a2, la2=a2, ua2b=b2, la2b=b2)

# straight bar dip (bar at y=40): support top -> deep dip leaning over the bar
sbd = frames('cal_straight_bar_dip')
ua, la = grip_pose((50, 40), 74, 1.5, 6.4, 'back')
sbd[0]['a'].update(t=74, ua1=ua, ua2=ua, la1=la, la2=la, th1=272, th2=272, sh1=272, sh2=272)
ua, la = grip_pose((50, 40), 52, 11.0, 6.4, 'back')
sbd[1]['a'].update(t=52, ua1=ua, ua2=ua, la1=la, la2=la, th1=252, th2=252, sh1=262, sh2=262)

# --- front lever family: arms angled so the bar is above the lower chest ------
for eid in ('cal_front_lever', 'cal_tuck_front_lever', 'cal_adv_tuck_front_lever',
            'cal_one_leg_front_lever', 'cal_straddle_front_lever'):
    for f in frames(eid):
        if abs(f['a'].get('ua1', 0) - 88) < 3:
            f['a'].update(ua1=72, ua2=72, la1=72, la2=72)

# tuck front lever: knees to chest (original thighs pointed away from the chest)
tfl = frames('cal_tuck_front_lever')
# heels to the glutes: knee interior angle ~22 deg (thigh r 2.95 + shin r 2.25
# need >= ~19 deg), toes pointed (renderer)
tfl[0]['a'].update(dict(th1=128, th2=128, sh1=330, sh2=330))
tfl[1]['a'].update(dict(th1=130, th2=130, sh1=332, sh2=332))

# --- full planche: ~49 deg shoulder lean so the hands sit under the centre
# of mass (hip region); tool/pose_check.py checks |CoM.x - hands.x| < 2 ---
for f in frames('cal_full_planche'):
    f['a'].update(ua1=221, ua2=221, la1=221, la2=221)

# --- pistol squat bottom: hip below the knee, free leg straight forward -------
ps = frames('cal_pistol_squat')
ps[1]['a'].update(t=52, th1=25, sh1=248, th2=8, sh2=8, ua1=8, ua2=8, la1=8, la2=8)

# --- jumping jack: real frontal-plane pose using abduction ------------------
jj = frames('cal_jumping_jack')
jj[0]['at'] = [50, 56]
jj[0]['a'].update(dict(t=90, ua1=270, la1=270, ua2=270, la2=270, ua1b=9, la1b=9, ua2b=9, la2b=9,
                       th1=270, sh1=270, th2=270, sh2=270, th1b=2, sh1b=2, th2b=2, sh2b=2))
jj[1]['at'] = [50, 56.6]
jj[1]['a'].update(dict(t=90, ua1=90, la1=90, ua2=90, la2=90, ua1b=32, la1b=35, ua2b=32, la2b=35,
                       th1=270, sh1=270, th2=270, sh2=270, th1b=12, sh1b=12, th2b=12, sh2b=12))


# --- human flag: body horizontal sideways (tb=-90 -> torso along -z, side 1 up,
# chest +x). Both hands on the pole (x=30, z=0); top hand = w1 (side 1).
# Straight arms ~40 deg from horizontal put the shoulders ~17.5 units from the
# pole; the body plane sits ~3 units in front (+x) of the pole.
def flag_arms(elev=40.0, back=3.0):
    dx = -back / 23.0
    k = math.sqrt(1 - dx * dx)
    dy, dz = k * math.sin(elev * D), -k * math.cos(elev * D)
    a1, b1 = side_dir(dx, dy, dz, 1)
    a2, b2 = side_dir(dx, -dy, dz, -1)
    return dict(ua1=a1, ua1b=b1, la1=a1, la1b=b1, ua2=a2, ua2b=b2, la2=a2, la2b=b2)


for i, f in enumerate(frames('cal_human_flag')):
    d = 1.5 * i
    f['at'] = [30, 22, 0]
    f['a'] = dict(t=90, hd=90, tb=-90 + d, **flag_arms(40 - d))
    f['a'].update(th1=270, th1b=87, sh1=270, sh1b=87, th2=270, th2b=-87, sh2=270, sh2b=-87)
for i, f in enumerate(frames('cal_tuck_human_flag')):
    d = 1.5 * i
    f['at'] = [30, 22, 0]
    f['a'] = dict(t=90, hd=90, tb=-90 + d, **flag_arms(40 - d))
    f['a'].update(th1=0, th1b=60, sh1=270, sh1b=-30, th2=0, th2b=-60, sh2=270, sh2b=30)

# --- dips: hands on bars at z=+-10 need slight arm abduction (shoulders at +-7)
for eid in ('cal_negative_dip', 'cal_support_hold'):
    for f in frames(eid):
        f['a'].update(dict(ua1b=7.5, la1b=7.5, ua2b=7.5, la2b=7.5))
# negative dip bottom: upper arm ~parallel to the floor, forearm ~vertical
frames('cal_negative_dip')[1]['a'].update(t=72, ua1=182, ua2=182, la1=285, la2=285,
                                          th1=258, th2=258, sh1=196, sh2=196)
# the 2D parallel bars are only ~36 units (~75 cm) high, so the knees would
# reach the floor at the bottom of a dip: raise them to ~48 units (~1 m)
for eid in ('cal_negative_dip', 'cal_support_hold'):
    for pr in ex[eid]['anim']['props']:
        if pr['k'] == 'pbars':
            pr['y'] = 40
    for f in frames(eid):
        f['at'] = [f['at'][0], 40]

# --- preferred initial yaw per exercise (camera angle that reads best) -------
for eid, e in ex.items():
    yaw = None
    if 'human_flag' in eid:
        yaw = 80
    elif eid == 'cal_jumping_jack':
        yaw = 60
    elif 'lever' in eid or 'planche' in eid:
        yaw = 25
    elif 'muscle_up' in eid:
        yaw = 30
    if yaw is not None:
        e['anim']['yaw'] = yaw

json.dump(list(ex.values()), open(OUT, 'w'), ensure_ascii=False, indent=1)
print('wrote', OUT, len(ex), 'exercises')
