import 'dart:math' as math;
import 'dart:typed_data';

import 'exercise_animation.dart';

/// Tiny mutable 3D vector (preallocated, no per-frame allocations).
class V3 {
  double x, y, z;
  V3([this.x = 0, this.y = 0, this.z = 0]);
  V3 set(double ax, double ay, double az) {
    x = ax;
    y = ay;
    z = az;
    return this;
  }

  V3 setFrom(V3 o) => set(o.x, o.y, o.z);
  V3 addScaled(V3 o, double s) => set(x + o.x * s, y + o.y * s, z + o.z * s);
  V3 setAddScaled(V3 a, V3 o, double s) => set(a.x + o.x * s, a.y + o.y * s, a.z + o.z * s);
  V3 setSub(V3 a, V3 b) => set(a.x - b.x, a.y - b.y, a.z - b.z);
  V3 setCross(V3 a, V3 b) => set(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);
  double dot(V3 o) => x * o.x + y * o.y + z * o.z;
  double get length => math.sqrt(x * x + y * y + z * z);
  V3 normalize([V3? fallback]) {
    final l = length;
    if (l < 1e-6) return fallback != null ? setFrom(fallback) : set(0, 1, 0);
    return set(x / l, y / l, z / l);
  }

  /// Rotate about the world y axis by [c]=cos, [s]=sin.
  void rotY(double c, double s) {
    final nx = x * c + z * s;
    final nz = -x * s + z * c;
    x = nx;
    z = nz;
  }

  double distTo(V3 o) {
    final dx = x - o.x, dy = y - o.y, dz = z - o.z;
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }

  @override
  String toString() => '(${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)}, ${z.toStringAsFixed(2)})';
}

/// Oriented rounded box (hands, feet). X = length (fingers/toes), Y = width,
/// Z = thickness / up (hands: back-of-hand normal; feet: instep up).
class OBox {
  final V3 c = V3(), ax = V3(), ay = V3(), az = V3(), ext = V3();

  /// Shape code for the shader (hands: side * 1 = open mitten, side * 2 = fist).
  double code = 0;
  void tip(V3 out) => out.setAddScaled(c, ax, ext.x);
  void tail(V3 out) => out.setAddScaled(c, ax, -ext.x);
}

/// World-space props (3D). Shared by rig (contacts), camera fit and shader.
class SceneProps {
  /// Ground plane sits this far below the 2D "contact" line (ankle/wrist
  /// points touch y=FLOOR in the 2D data; soles/palms are below the joint).
  static const double sole = 1.5;

  bool hasFloor = false;
  double floorY = -89.1;
  bool hasBar = false;
  double barX = 0, barY = 0, barHalf = 20;
  bool hasPbars = false;
  double pbY = 0, pbX1 = 0, pbX2 = 0, pbZ = 10, pbFloor = -89.1;
  bool hasPole = false;
  double poleX = 0, poleZ = 0, poleFloor = -89.1;
  bool hasWall = false;
  double wallX = 0, wallFloor = -89.1, wallSide = -1; // side: normal dir (x) toward the figure
  bool hasBox = false;
  double boxX0 = 0, boxX1 = 0, boxY0 = 0, boxY1 = 0, boxZ = 10;

  /// Ground plane: the floor prop, or the floor the parallel-bar posts /
  /// pole stand on (drawn as soft ground so posts do not end in mid-air).
  bool hasGround = false;
  double groundY = -89.1;

  /// Set by the scene: the ground is close enough to be part of the framing.
  bool groundInFit = false;

  SceneProps.from(List<PropSpec> props) {
    for (final p in props) {
      switch (p.kind) {
        case PropKind.floor:
          hasFloor = true;
          floorY = -p.y - sole;
        case PropKind.bar:
          hasBar = true;
          barX = p.x;
          barY = -p.y;
        case PropKind.pbars:
          hasPbars = true;
          pbY = -p.y;
          pbX1 = math.min(p.x1, p.x2);
          pbX2 = math.max(p.x1, p.x2);
          pbFloor = -p.floor - sole;
        case PropKind.pole:
          hasPole = true;
          poleX = p.x;
          poleFloor = -p.floor - sole;
        case PropKind.wall:
          hasWall = true;
          wallX = p.x;
          wallFloor = -p.floor - sole;
        case PropKind.box:
          hasBox = true;
          boxX0 = p.x;
          boxX1 = p.x + p.w;
          boxY1 = -p.y - sole;
          boxY0 = -(p.y + p.h) - sole;
      }
    }
    if (hasFloor) {
      hasGround = true;
      groundY = floorY;
    } else if (hasPbars || hasPole) {
      hasGround = true;
      groundY = hasPbars ? pbFloor : poleFloor;
    }
  }
}

/// Joint ids (see [MannequinRig.joints]).
class J {
  static const hip = 0, neck = 1, head = 2;
  static const sh1 = 3, el1 = 4, wr1 = 5, sh2 = 6, el2 = 7, wr2 = 8;
  static const hp1 = 9, kn1 = 10, an1 = 11, hp2 = 12, kn2 = 13, an2 = 14;
  static const count = 15;

  static int? byAnchor(String a) {
    switch (a) {
      case 'hip':
        return hip;
      case 'sh':
      case 'neck':
        return neck;
      case 'head':
        return head;
      case 'e1':
        return el1;
      case 'w1':
        return wr1;
      case 'e2':
        return el2;
      case 'w2':
        return wr2;
      case 'k1':
        return kn1;
      case 'f1':
        return an1;
      case 'k2':
        return kn2;
      case 'f2':
        return an2;
    }
    return null;
  }
}

/// 3D forward kinematics of the mannequin.
class MannequinRig {
  // Segment lengths (same units as the 2D data).
  static const double torsoLen = 24, uaLen = 12, laLen = 11, thLen = 16, shLen = 16;
  static const double headDist = 7.0; // neck point -> head centre
  static const double shoulderHalf = 7.0, hipHalf = 4.5;

  /// Gripping hand: distance from the drawn wrist joint to the grip axis
  /// (the fist wraps the cylinder, the wrist sits just outside it).
  static const double gripOffset = 2.3;

  /// Half width of a fist along the grip axis.
  static const double fistHalfWidth = 1.8;

  /// Radii of the grip cylinders (must match the shader's props).
  static const double barRadius = 1.2, pbarRadius = 1.1, poleRadius = 1.4;

  final SceneProps props;
  final List<V3> joints = List.generate(J.count, (_) => V3());
  final V3 T = V3(), F = V3(), L = V3(); // torso frame (up, chest-forward, lateral)
  // ignore: non_constant_identifier_names
  final V3 HU = V3(), HF = V3(), HL = V3(); // head frame
  final OBox hand1 = OBox(), hand2 = OBox(), foot1 = OBox(), foot2 = OBox();

  /// Bounding spheres (x,y,z,r) for: torso, head+neck, arm1, arm2, leg1, leg2.
  final Float64List bounds = Float64List(24);

  /// Figure AABB (min xyz, max xyz).
  final Float64List aabb = Float64List(6);

  // scratch
  final V3 _d = V3(), _e = V3(), _f = V3(), _g = V3(), _h = V3();

  MannequinRig(this.props);

  V3 get hip => joints[J.hip];
  V3 get neck => joints[J.neck];
  V3 get head => joints[J.head];

  static double _rad(double d) => d * math.pi / 180.0;
  static double _hypot(double a, double b) => math.sqrt(a * a + b * b);

  static void segDir(V3 out, double aDeg, double bDeg, double side) {
    final a = _rad(aDeg), b = _rad(bDeg);
    final cb = math.cos(b);
    out.set(math.cos(a) * cb, math.sin(a) * cb, side * math.sin(b));
  }

  void solve(Float64List ang, String anchor, Float64List at) {
    final t = _rad(ang[PoseChannel.t]);
    final tb = _rad(ang[PoseChannel.tb]);
    final hd = _rad(ang[PoseChannel.hd]);
    final ctb = math.cos(tb), stb = math.sin(tb);
    T.set(math.cos(t) * ctb, math.sin(t) * ctb, stb);
    F.set(math.sin(t), -math.cos(t), 0);
    L.setCross(F, T);
    HU.set(math.cos(hd) * ctb, math.sin(hd) * ctb, stb);
    HF.set(math.sin(hd), -math.cos(hd), 0);
    HL.setCross(HF, HU);

    hip.set(0, 0, 0);
    neck.setAddScaled(hip, T, torsoLen);
    head.setAddScaled(neck, HU, headDist);
    // arms
    for (var s = 0; s < 2; s++) {
      final side = s == 0 ? 1.0 : -1.0;
      final sh = joints[s == 0 ? J.sh1 : J.sh2];
      final el = joints[s == 0 ? J.el1 : J.el2];
      final wr = joints[s == 0 ? J.wr1 : J.wr2];
      sh.setAddScaled(neck, L, shoulderHalf * side);
      segDir(_d, ang[s == 0 ? PoseChannel.ua1 : PoseChannel.ua2], ang[s == 0 ? PoseChannel.ua1b : PoseChannel.ua2b], side);
      el.setAddScaled(sh, _d, uaLen);
      segDir(_d, ang[s == 0 ? PoseChannel.la1 : PoseChannel.la2], ang[s == 0 ? PoseChannel.la1b : PoseChannel.la2b], side);
      wr.setAddScaled(el, _d, laLen);

      final hp = joints[s == 0 ? J.hp1 : J.hp2];
      final kn = joints[s == 0 ? J.kn1 : J.kn2];
      final an = joints[s == 0 ? J.an1 : J.an2];
      hp.setAddScaled(hip, L, hipHalf * side);
      segDir(_d, ang[s == 0 ? PoseChannel.th1 : PoseChannel.th2], ang[s == 0 ? PoseChannel.th1b : PoseChannel.th2b], side);
      kn.setAddScaled(hp, _d, thLen);
      segDir(_d, ang[s == 0 ? PoseChannel.sh1 : PoseChannel.sh2], ang[s == 0 ? PoseChannel.sh1b : PoseChannel.sh2b], side);
      an.setAddScaled(kn, _d, shLen);
    }

    // optional whole-figure yaw
    final ry = ang[PoseChannel.ry];
    if (ry != 0) {
      final c = math.cos(_rad(ry)), s = math.sin(_rad(ry));
      for (final j in joints) {
        j.rotY(c, s);
      }
      T.rotY(c, s);
      F.rotY(c, s);
      L.rotY(c, s);
      HU.rotY(c, s);
      HF.rotY(c, s);
      HL.rotY(c, s);
    }

    // anchor placement: (x, y) from the 2D target, z kept from FK (unless given)
    final ai = J.byAnchor(anchor) ?? J.hip;
    final a = joints[ai];
    final dx = at[0] - a.x;
    final dy = -at[1] - a.y;
    final dz = at[2].isNaN ? 0.0 : at[2] - a.z;
    for (final j in joints) {
      j.x += dx;
      j.y += dy;
      j.z += dz;
    }
    // A wrist anchored on a grip (bar / parallel bar / pole): the 2D data put
    // the wrist joint ON the grip axis. The fist wraps the cylinder, so the
    // whole figure moves back along the forearm by [gripOffset].
    if (ai == J.wr1 || ai == J.wr2) {
      final el = joints[ai == J.wr1 ? J.el1 : J.el2];
      if (_findGrip(a) != 0) {
        final len = _gripLen(el, a);
        for (final j in joints) {
          j.addScaled(len, -gripOffset);
        }
      }
    }

    _solveHand(hand1, joints[J.el1], joints[J.wr1], 1);
    _solveHand(hand2, joints[J.el2], joints[J.wr2], -1);
    _solveFoot(foot1, joints[J.hp1], joints[J.kn1], joints[J.an1]);
    _solveFoot(foot2, joints[J.hp2], joints[J.kn2], joints[J.an2]);
    _computeBounds();
  }

  /// Height of the supporting surface under (x, z), or null.
  double? _surfaceBelow(double x, double y, double z) {
    double? best;
    if (props.hasFloor) best = props.floorY;
    if (props.hasBox && x >= props.boxX0 - 1 && x <= props.boxX1 + 1 && z.abs() <= props.boxZ + 1 && y >= props.boxY1 - 2) {
      best = props.boxY1;
    }
    return best;
  }

  void _horizontalForward(V3 out) {
    out.set(F.x, 0, F.z);
    if (out.length < 0.3) {
      out.set(T.x, 0, T.z);
      if (out.length < 0.3) out.set(1, 0, 0);
    }
    out.normalize();
  }

  // grip search result (see [_findGrip])
  final V3 _gAxis = V3(), _gPoint = V3();
  double _gRadius = 1.2;

  /// Finds a grip cylinder within reach of the wrist [wr]. Returns 0 (none),
  /// 1 bar (z axis), 2 parallel bar (x axis), 3 pole (y axis) and sets
  /// [_gAxis], [_gPoint] (closest axis point) and [_gRadius].
  int _findGrip(V3 wr) {
    double bestDist = 3.4;
    int kind = 0;
    if (props.hasBar) {
      final dd = _hypot(wr.x - props.barX, wr.y - props.barY);
      if (dd < bestDist && wr.z.abs() <= props.barHalf + 2) {
        bestDist = dd;
        kind = 1;
        _gPoint.set(props.barX, props.barY, wr.z);
        _gAxis.set(0, 0, 1);
        _gRadius = barRadius;
      }
    }
    if (props.hasPbars) {
      for (var k = 0; k < 2; k++) {
        final zz = k == 0 ? props.pbZ : -props.pbZ;
        final dd = _hypot(wr.y - props.pbY, wr.z - zz);
        if (dd < bestDist && wr.x >= props.pbX1 - 2 && wr.x <= props.pbX2 + 2) {
          bestDist = dd;
          kind = 2;
          _gPoint.set(wr.x, props.pbY, zz);
          _gAxis.set(1, 0, 0);
          _gRadius = pbarRadius;
        }
      }
    }
    if (props.hasPole) {
      final dd = _hypot(wr.x - props.poleX, wr.z - props.poleZ);
      if (dd < bestDist) {
        bestDist = dd;
        kind = 3;
        _gPoint.set(props.poleX, wr.y, props.poleZ);
        _gAxis.set(0, 1, 0);
        _gRadius = poleRadius;
      }
    }
    return kind;
  }

  /// Forearm direction orthogonal to the grip axis (wrist -> axis), in [_gl].
  final V3 _gl = V3();
  V3 _gripLen(V3 el, V3 wr) {
    final a = _gl.setSub(wr, el).normalize();
    a.addScaled(_gAxis, -a.dot(_gAxis));
    if (a.length < 0.2) {
      a.setFrom(F).addScaled(_gAxis, -F.dot(_gAxis));
    }
    return a.normalize();
  }

  void _solveHand(OBox h, V3 el, V3 wr, double side) {
    // 1) fist around a grip cylinder: centred ON the axis, the drawn wrist
    //    [gripOffset] back along the forearm (moves the wrist joint itself,
    //    which the shader draws; the anchored hand already sits there)
    if (_findGrip(wr) != 0) {
      final len = _gripLen(el, wr);
      h.ax.setFrom(len);
      h.ay.setFrom(_gAxis);
      h.az.setCross(h.ax, h.ay);
      h.c.setFrom(_gPoint);
      h.ext.set(gripOffset, fistHalfWidth, _gRadius);
      h.code = side * 2;
      wr.setAddScaled(_gPoint, len, -gripOffset);
      return;
    }
    final a = _d.setSub(wr, el).normalize(); // forearm dir
    // 2) flat on a supporting surface (floor / box top)
    final surf = _surfaceBelow(wr.x, wr.y, wr.z);
    if (surf != null && wr.y - surf < SceneProps.sole + 2.0 && a.y < -0.15) {
      final fwd = _f;
      _horizontalForward(fwd);
      // fingers slightly turned outwards
      fwd.addScaled(_g.set(L.x, 0, L.z), side * 0.35).normalize();
      h.ax.setFrom(fwd);
      h.az.set(0, 1, 0);
      h.ay.setCross(h.az, h.ax);
      h.c.setAddScaled(wr, fwd, 2.9);
      h.c.y = surf + 0.85;
      h.ext.set(3.5, 1.85, 0.85);
      h.code = side;
      return;
    }
    // 3) flat against a wall
    if (props.hasWall && (wr.x - props.wallX).abs() < SceneProps.sole + 2.0) {
      final n = props.wallSide; // wall normal (x) pointing to the figure
      h.az.set(n, 0, 0);
      h.ax.set(0, 1, 0);
      h.ay.setCross(h.az, h.ax);
      h.c.set(props.wallX + n * 0.85, wr.y + 2.9, wr.z);
      h.ext.set(3.5, 1.85, 0.85);
      h.code = side;
      return;
    }
    // 4) free hand: continue the forearm, palm facing the body midline
    //    (az = back of the hand, pointing away from the midline)
    h.ax.setFrom(a);
    final pn = _g.set(L.x * side, L.y * side, L.z * side).addScaled(a, -side * L.dot(a));
    if (pn.length < 0.2) pn.setFrom(F).addScaled(a, -F.dot(a)).set(-pn.x, -pn.y, -pn.z);
    pn.normalize();
    h.az.setFrom(pn);
    h.ay.setCross(h.az, h.ax);
    h.c.setAddScaled(wr, a, 3.4);
    h.ext.set(3.6, 1.85, 1.0);
    h.code = side;
  }

  void _solveFoot(OBox f, V3 hp, V3 kn, V3 an) {
    final s = _d.setSub(an, kn).normalize(); // shin dir
    // toe direction perpendicular to the shin, toward the body front
    final perp = _e.setFrom(F).addScaled(s, -F.dot(s));
    if (perp.length < 0.25) perp.setFrom(T).addScaled(s, -T.dot(s));
    perp.normalize();
    // free (hanging / in the air): toes pointed (down-forward along the shin)
    final pointed = _f.setFrom(perp).addScaled(s, 0.85).normalize();
    // A free leg held out in front with a near-horizontal shin (pistol, L-sit)
    // keeps the foot flexed: toes up, perpendicular to the shin.
    final thigh = _t1.setSub(kn, hp).normalize();
    final flexW = _smooth(0.45, 0.8, thigh.dot(F)) * (1 - _smooth(0.45, 0.8, s.y.abs()));
    if (flexW > 0) {
      final upP = _t2.set(0, 1, 0).addScaled(s, -s.y);
      if (upP.length > 0.2) {
        upP.normalize().addScaled(perp, 0.25).normalize();
        pointed
            .set(pointed.x + (upP.x - pointed.x) * flexW, pointed.y + (upP.y - pointed.y) * flexW, pointed.z + (upP.z - pointed.z) * flexW)
            .normalize(perp);
      }
    }
    // grounded: flat on the surface
    final surf = _surfaceBelow(an.x, an.y, an.z);
    double g = 0;
    if (surf != null) {
      final hgt = an.y - surf - SceneProps.sole;
      g = (1.0 - hgt / 5.0).clamp(0.0, 1.0);
      g = g * g * (3 - 2 * g);
    }
    final fd = _g;
    if (g > 0) {
      final flat = _h;
      _horizontalForward(flat);
      fd.set(pointed.x + (flat.x - pointed.x) * g, pointed.y + (flat.y - pointed.y) * g, pointed.z + (flat.z - pointed.z) * g).normalize(flat);
    } else {
      fd.setFrom(pointed);
    }
    // foot "up" = -shin orthogonalised against toe dir (flat: world up)
    final up = _h.set(-s.x, -s.y, -s.z);
    if (g > 0) {
      up.set(up.x + (0 - up.x) * g, up.y + (1 - up.y) * g, up.z + (0 - up.z) * g);
    }
    up.addScaled(fd, -up.dot(fd)).normalize();
    f.ax.setFrom(fd);
    f.az.setFrom(up);
    f.ay.setCross(f.az, f.ax);
    f.ext.set(4.6, 1.75, 1.15);
    // sole bottom exactly `sole` below the ankle joint
    f.c.setAddScaled(an, fd, 2.45).addScaled(up, f.ext.z - SceneProps.sole);
  }

  static double _smooth(double a, double b, double x) {
    final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  // bounding sphere accumulation (no allocations)
  double _bx0 = 0, _by0 = 0, _bz0 = 0, _bx1 = 0, _by1 = 0, _bz1 = 0;
  final List<V3> _pts = List.generate(8, (_) => V3());
  int _np = 0;

  void _p(V3 v) => _pts[_np++].setFrom(v);

  void _sphere(int slot, double margin) {
    var minX = 1e9, minY = 1e9, minZ = 1e9, maxX = -1e9, maxY = -1e9, maxZ = -1e9;
    for (var i = 0; i < _np; i++) {
      final p = _pts[i];
      minX = math.min(minX, p.x);
      minY = math.min(minY, p.y);
      minZ = math.min(minZ, p.z);
      maxX = math.max(maxX, p.x);
      maxY = math.max(maxY, p.y);
      maxZ = math.max(maxZ, p.z);
    }
    final cx = (minX + maxX) / 2, cy = (minY + maxY) / 2, cz = (minZ + maxZ) / 2;
    var r = 0.0;
    for (var i = 0; i < _np; i++) {
      final p = _pts[i];
      final dx = p.x - cx, dy = p.y - cy, dz = p.z - cz;
      r = math.max(r, math.sqrt(dx * dx + dy * dy + dz * dz));
    }
    final o = slot * 4;
    bounds[o] = cx;
    bounds[o + 1] = cy;
    bounds[o + 2] = cz;
    bounds[o + 3] = r + margin;
    _np = 0;
  }

  void _grow(double x, double y, double z, double r) {
    _bx0 = math.min(_bx0, x - r);
    _by0 = math.min(_by0, y - r);
    _bz0 = math.min(_bz0, z - r);
    _bx1 = math.max(_bx1, x + r);
    _by1 = math.max(_by1, y + r);
    _bz1 = math.max(_bz1, z + r);
  }

  final V3 _t1 = V3(), _t2 = V3();
  late final void Function(double, double, double, double) _growFn = _grow;

  void _computeBounds() {
    // group bounding spheres (used by the shader to skip far groups)
    // torso group = core + neck + both whole thighs
    _p(_t1.setAddScaled(hip, T, -4.5));
    _p(_t2.setAddScaled(neck, T, 2.5));
    _p(_t3.setAddScaled(head, HU, -1.5));
    _p(joints[J.kn1]);
    _p(joints[J.kn2]);
    _sphere(0, 9.8);
    _p(_t1.setAddScaled(head, HU, -4.0));
    _p(_t2.setAddScaled(head, HU, 4.0));
    _p(_t3.setAddScaled(head, HF, 4.4));
    _sphere(1, 4.2);
    for (var s = 0; s < 2; s++) {
      final h = s == 0 ? hand1 : hand2;
      _p(joints[s == 0 ? J.sh1 : J.sh2]);
      _p(joints[s == 0 ? J.el1 : J.el2]);
      _p(joints[s == 0 ? J.wr1 : J.wr2]);
      h.tip(_t1);
      _p(_t1);
      _sphere(2 + s, 2.8);
    }
    for (var s = 0; s < 2; s++) {
      final f = s == 0 ? foot1 : foot2;
      _p(joints[s == 0 ? J.kn1 : J.kn2]);
      _p(joints[s == 0 ? J.an1 : J.an2]);
      f.tip(_t1);
      _p(_t1);
      f.tail(_t2);
      _p(_t2);
      _sphere(4 + s, 3.8);
    }
    // tight AABB from the surface sample points (+ margin)
    _bx0 = _by0 = _bz0 = 1e9;
    _bx1 = _by1 = _bz1 = -1e9;
    forEachFitPoint(_growFn);
    const m = 1.5;
    aabb[0] = _bx0 - m;
    aabb[1] = _by0 - m;
    aabb[2] = _bz0 - m;
    aabb[3] = _bx1 + m;
    aabb[4] = _by1 + m;
    aabb[5] = _bz1 + m;
  }

  late final List<OBox> _boxes = [hand1, hand2, foot1, foot2];
  final V3 _t3 = V3();

  /// Visits representative surface points (centre, radius) that enclose the
  /// figure: used for camera fitting and the shader's AABB.
  void forEachFitPoint(void Function(double x, double y, double z, double r) f) {
    f(hip.x, hip.y, hip.z, 6.6);
    _t3.setAddScaled(hip, T, 9);
    f(_t3.x, _t3.y, _t3.z, 6.2);
    _t3.setAddScaled(hip, T, 16.5);
    f(_t3.x, _t3.y, _t3.z, 7.8);
    _t3.setAddScaled(hip, T, 22);
    f(_t3.x, _t3.y, _t3.z, 8.8);
    f(neck.x, neck.y, neck.z, 4);
    f(head.x, head.y, head.z, 5.6);
    for (var j = J.sh1; j <= J.an2; j++) {
      final p = joints[j];
      final r = (j == J.sh1 || j == J.sh2)
          ? 3.0
          : (j == J.hp1 || j == J.hp2)
              ? 4.0
              : (j == J.el1 || j == J.el2 || j == J.kn1 || j == J.kn2)
                  ? 2.4
                  : 1.6;
      f(p.x, p.y, p.z, r);
    }
    // limb mid-points (muscle bulge)
    for (var s = 0; s < 2; s++) {
      final o = s == 0 ? 0 : 3;
      for (var k = 0; k < 2; k++) {
        final a = joints[J.sh1 + o + k], b = joints[J.sh1 + o + k + 1];
        f((a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2, k == 0 ? 2.8 : 2.2);
        final c = joints[J.hp1 + o + k], d = joints[J.hp1 + o + k + 1];
        f((c.x + d.x) / 2, (c.y + d.y) / 2, (c.z + d.z) / 2, k == 0 ? 3.9 : 2.7);
      }
    }
    for (final b in _boxes) {
      f(b.c.x, b.c.y, b.c.z, b.ext.y + 0.6);
      b.tip(_t3);
      f(_t3.x, _t3.y, _t3.z, 1.6);
      b.tail(_t3);
      f(_t3.x, _t3.y, _t3.z, 1.8);
    }
  }
}
