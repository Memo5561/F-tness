import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'camera.dart';
import 'exercise_animation.dart';
import 'math3d.dart';
import 'props.dart';
import 'render_items.dart';
import 'scene_items.dart';
import 'skeleton.dart';
import 'style.dart';

/// Body dimensions (world units; torso hip->neck = 24).
class Dims {
  // Limbs narrow into their joint balls (wooden-mannequin look); the balls
  // are about as big as the limb's widest section, so end-on views do not
  // show stepped rings.
  static const double shoulderBall = 2.6, elbowBall = 1.92, wristBall = 1.36;
  static const double hipBall = 3.05, kneeBall = 2.34, ankleBall = 1.5;

  /// Wrist ball of a gripping hand (forearm-to-fist transition).
  static const double gripWristBall = 1.25;

  /// The deltoid ball is drawn this far down the torso axis and out from the
  /// shoulder joint (visual only; the skeleton is unchanged), so the top of
  /// the shoulder sits below the chin and the trapezius slopes from the neck.
  static const double deltoidDown = 1.0, deltoidOut = 0.4;

  static const List<double> upperArm = [2.1, 2.42, 1.62];
  static const double upperArmMid = 0.3;
  static const List<double> foreArm = [1.5, 1.86, 1.18];
  static const double foreArmMid = 0.28;
  static const List<double> thigh = [2.75, 2.95, 1.95];
  static const double thighMid = 0.3;
  static const List<double> shin = [1.85, 2.25, 1.25];
  static const double shinMid = 0.3;

  /// Visual floor sits this far below the 2D floor line (ankle/wrist height).
  static const double floorOffset = 2.6;

  /// A joint ball is painted before (under) an attached limb that comes
  /// toward the viewer more steeply than this (view-space z of the limb
  /// direction); otherwise after it, with an exact "bite".
  static const double ballUnderLimb = 0.35;

  /// Middle joints (elbow, knee) whose two limbs both point along the view
  /// axis: the ball shrinks to the limb radius between these |view z| values
  /// and is dropped above the upper one (no concentric "telescope" rings).
  static const double endOn0 = 0.55, endOn1 = 0.8;

  /// Distance of the visual wrist from the grip axis (the hand wraps the bar).
  static const double gripWrist = 2.0;
}

/// One torso ellipsoid in the torso frame: centre hip + T*t + F*f, semi-axes
/// L*rl, T*rt, F*rf (T torso axis, F chest-forward, L lateral). The pieces
/// overlap strongly and are cut where they meet ([TorsoCut]), so the stack
/// renders as one sculpted torso (pelvis, waist, ribcage, chest) with crease
/// lines, no bead-like pinches and no overlapping outlines.
/// tool/pose_check.py mirrors these numbers.
class TorsoPart {
  final double t, f, rl, rt, rf;
  const TorsoPart(this.t, this.f, this.rl, this.rt, this.rf);

  // fitted (tool/torso_fit/fit_torso.py) to an athletic front/side profile with
  // near-zero silhouette steps at the cuts
  static const pelvis = TorsoPart(1.35, -0.45, 6.13, 6.62, 3.78);
  static const abdomen = TorsoPart(6.64, 0.3, 5.73, 9.07, 3.42);
  static const ribcage = TorsoPart(16.81, 0.37, 7.46, 9.09, 4.42);
  static const chest = TorsoPart(20.11, 0.37, 8.21, 5.59, 4.84);
  static const List<TorsoPart> stack = [pelvis, abdomen, ribcage, chest];

  /// Cut planes between consecutive pieces of [stack] (torso coordinates).
  static final List<TorsoCut> cuts = [
    for (var i = 0; i + 1 < stack.length; i++) TorsoCut.between(stack[i], stack[i + 1])
  ];

  /// Whether piece [i] of [stack] is kept at torso coordinates (t, f), with
  /// the cut planes moved out by [margin].
  static bool keeps(int i, double t, double f, [double margin = 0]) {
    if (i > 0) {
      final c = cuts[i - 1];
      if (c.nT * t + c.nF * f < c.off - margin) return false;
    }
    if (i < cuts.length) {
      final c = cuts[i];
      if (c.nT * t + c.nF * f > c.off + margin) return false;
    }
    return true;
  }

  /// Spheres (t, f, radius in torso coordinates) along the torso axis that
  /// bound the cut stack: used for the auto-fit and the floor shadow.
  static final List<(double, double, double)> stations = _stations();

  static List<(double, double, double)> _stations() {
    final out = <(double, double, double)>[];
    for (var t = -6.0; t <= 27.0; t += 3) {
      var lo = double.infinity, hi = -double.infinity, w = 0.0;
      for (var i = 0; i < stack.length; i++) {
        final p = stack[i];
        final u = (t - p.t) / p.rt;
        if (u.abs() >= 1) continue;
        final q = math.sqrt(1 - u * u);
        for (var k = 0; k <= 8; k++) {
          final f = p.f + p.rf * q * (-1 + k / 4);
          if (!keeps(i, t, f)) continue;
          lo = math.min(lo, f);
          hi = math.max(hi, f);
          final g = (f - p.f) / (p.rf * q);
          w = math.max(w, p.rl * q * math.sqrt(math.max(0.0, 1 - g * g)));
        }
      }
      if (!lo.isFinite) continue;
      out.add((t, (lo + hi) / 2, math.max(w, (hi - lo) / 2)));
    }
    return out;
  }
}

/// Plane nT*t + nF*f = off in torso coordinates (t along T, f along F; the
/// plane contains the lateral axis) through the front and back points where
/// two torso ellipsoids intersect in the mid-sagittal plane. Each piece is
/// cut there (plus a small overlap), so the stack renders as the union of
/// the solids: crease lines instead of overlapping outlines.
class TorsoCut {
  final double nT, nF, off;
  const TorsoCut(this.nT, this.nF, this.off);

  factory TorsoCut.between(TorsoPart a, TorsoPart b) {
    double g(double th) {
      final t = a.t + a.rt * math.cos(th), f = a.f + a.rf * math.sin(th);
      final u = (t - b.t) / b.rt, w = (f - b.f) / b.rf;
      return u * u + w * w - 1;
    }

    const n = 1440;
    var front = const Offset(0, -1e9), back = const Offset(0, 1e9);
    var prev = g(0);
    for (var i = 1; i <= n; i++) {
      final th = 2 * math.pi * i / n;
      final cur = g(th);
      if ((prev < 0) != (cur < 0)) {
        var lo = 2 * math.pi * (i - 1) / n, hi = th;
        final sLo = prev < 0;
        for (var k = 0; k < 40; k++) {
          final m = (lo + hi) / 2;
          if ((g(m) < 0) == sLo) {
            lo = m;
          } else {
            hi = m;
          }
        }
        final p = Offset(a.t + a.rt * math.cos(lo), a.f + a.rf * math.sin(lo));
        if (p.dy > front.dy) front = p;
        if (p.dy < back.dy) back = p;
      }
      prev = cur;
    }
    var nt = front.dy - back.dy, nf = -(front.dx - back.dx);
    final l = math.sqrt(nt * nt + nf * nf);
    nt /= l;
    nf /= l;
    if (nt < 0) {
      nt = -nt;
      nf = -nf;
    }
    return TorsoCut(nt, nf, nt * front.dx + nf * front.dy);
  }

  /// Overlap (world units) of neighbouring pieces past the cut, so no crack
  /// shows where their cross-sections differ slightly.
  static const double overlap = 0.15;

  /// Sets cut [slot] (0 or 1) of [e] (a piece built from [p]) to keep the side
  /// below (keepBelow) or above this plane.
  void applyTo(EllipsoidItem e, TorsoPart p, int slot, bool keepBelow) {
    final d = V3(0, nT * p.rt, nF * p.rf);
    final l = d.length;
    final h = (off + (keepBelow ? overlap : -overlap) - nT * p.t - nF * p.f) / l;
    if (slot == 0) {
      e.cutD = d * (1 / l);
      e.cutH = h;
      e.cutKeepLess = keepBelow;
    } else {
      e.cut2D = d * (1 / l);
      e.cut2H = h;
      e.cut2KeepLess = keepBelow;
    }
  }
}

/// Distance from point [p] to segment [a]-[b].
double segPointDist(V3 a, V3 b, V3 p) {
  final d = b - a;
  final l2 = d.length2;
  final t = l2 > 1e-12 ? ((p - a).dot(d) / l2).clamp(0.0, 1.0) : 0.0;
  return (a + d * t - p).length;
}

/// Grip target (cylinder axis) a hand can hold.
class GripAxis {
  final V3 a, b;
  final double r;
  final String kind;
  GripAxis(this.a, this.b, this.r, [this.kind = '']);

  double distTo(V3 p) => segPointDist(a, b, p);

  V3 get dir => (b - a).unit;

  /// Closest point on the axis to [p].
  V3 closest(V3 p) {
    final d = b - a;
    final l2 = d.length2;
    final t = l2 > 1e-12 ? ((p - a).dot(d) / l2).clamp(0.0, 1.0) : 0.0;
    return a + d * t;
  }
}

/// A bar upright: fine pieces near the bar (depth-sorted against the body)
/// ending in a piece that fades out, plus one merged piece used while the
/// upright is translucent (lined up with the grip).
class _Upright {
  final List<CylItem> pieces = [];
  late final CylItem whole;
  final V3 base;
  _Upright(this.base);
}

/// Builds the render items for a pose and paints them with a painter's
/// algorithm (pairwise occlusion tests + topological sort).
class MannequinRenderer {
  MannequinRenderer();

  // ---- body items (reused between frames)
  final pelvis = EllipsoidItem('pelvis', MatKind.body);
  final abdomen = EllipsoidItem('abdomen', MatKind.body);
  final ribcage = EllipsoidItem('ribcage', MatKind.body);
  final chest = EllipsoidItem('chest', MatKind.body);
  final neck = LimbItem('neck', MatKind.body);
  final head = EllipsoidItem('head', MatKind.body);

  /// Small nose on the face: shows which way the head faces.
  final nose = EllipsoidItem('nose', MatKind.body);
  final List<SphereItem> shBall = [SphereItem('shoulder1', MatKind.joint), SphereItem('shoulder2', MatKind.joint)];
  final List<SphereItem> elBall = [SphereItem('el1', MatKind.joint), SphereItem('el2', MatKind.joint)];
  final List<SphereItem> wrBall = [SphereItem('wr1', MatKind.joint), SphereItem('wr2', MatKind.joint)];
  final List<SphereItem> hpBall = [SphereItem('hp1', MatKind.joint), SphereItem('hp2', MatKind.joint)];
  final List<SphereItem> knBall = [SphereItem('kn1', MatKind.joint), SphereItem('kn2', MatKind.joint)];
  final List<SphereItem> anBall = [SphereItem('an1', MatKind.joint), SphereItem('an2', MatKind.joint)];
  final List<LimbItem> upperArm = [LimbItem('ua1', MatKind.body), LimbItem('ua2', MatKind.body)];
  final List<LimbItem> foreArm = [LimbItem('la1', MatKind.body), LimbItem('la2', MatKind.body)];

  /// Mitten / flat hand, or (gripping) the half of the fist on one side of
  /// the grip axis; [hand2] is the other half (only used while gripping).
  final List<EllipsoidItem> hand = [EllipsoidItem('hand1', MatKind.body), EllipsoidItem('hand2', MatKind.body)];
  final List<EllipsoidItem> hand2 = [EllipsoidItem('fist1', MatKind.body), EllipsoidItem('fist2', MatKind.body)];
  final List<LimbItem> thigh = [LimbItem('th1', MatKind.body), LimbItem('th2', MatKind.body)];
  final List<LimbItem> shin = [LimbItem('sh1', MatKind.body), LimbItem('sh2', MatKind.body)];

  /// Foot = heel + wider, flatter forefoot (a readable wedge from any side).
  final List<EllipsoidItem> heel = [EllipsoidItem('heel1', MatKind.body), EllipsoidItem('heel2', MatKind.body)];
  final List<EllipsoidItem> foot = [EllipsoidItem('foot1', MatKind.body), EllipsoidItem('foot2', MatKind.body)];

  late final List<Item> bodyItems = [
    pelvis, abdomen, ribcage, chest, neck, head, nose, //
    ...shBall, ...elBall, ...wrBall, ...hpBall, ...knBall, ...anBall,
    ...upperArm, ...foreArm, ...hand, ...hand2, ...thigh, ...shin, ...heel, ...foot,
  ];
  late final List<SphereItem> _balls = [
    ...shBall, ...elBall, ...wrBall, ...hpBall, ...knBall, ...anBall
  ];
  late final List<LimbItem> _limbs = [...upperArm, ...foreArm, ...thigh, ...shin];

  /// Items casting floor shadows (joints, torso, head, hands, feet).
  late final List<Item> _shadowItems = [
    pelvis, abdomen, ribcage, chest, head, ..._balls, ...hand, ...hand2, ...heel, ...foot,
  ];

  // ---- props (rebuilt when the animation changes)
  final List<Item> propItems = [];
  final List<GripAxis> grips = [];
  final List<_Upright> _uprights = [];

  /// Floor contact points of props (pole and post bases) + radius.
  final List<V3> _contacts = [];
  final List<double> _contactR = [];
  double? floorY; // world y of the visual floor
  List<PropSpec>? _propsFor;
  bool _compactFor = false;
  _Wall? _wall;

  /// Short uprights fading out just above the bar (thumbnails), so the frame
  /// does not dominate small cells.
  bool compactProps = false;

  final Skeleton skel = Skeleton();

  /// Debug only: item names not to paint.
  static Set<String> debugHide = {};
  static bool debugPrintOrder = false;
  int _cycles = 0;
  int _markGen = 0;

  // ------------------------------------------------------------------ props
  void setProps(List<PropSpec> props, double? floorData) {
    if (identical(props, _propsFor) && _compactFor == compactProps) return;
    _propsFor = props;
    _compactFor = compactProps;
    propItems.clear();
    grips.clear();
    _uprights.clear();
    _contacts.clear();
    _contactR.clear();
    _wall = null;
    floorY = floorData == null ? null : -(floorData + Dims.floorOffset);
    final fy = floorY ?? -(88 + Dims.floorOffset);
    for (final p in props) {
      switch (p.kind) {
        case 'bar':
          final x = p.get('x', 50), y = -p.get('y', 12);
          const r = 1.2, half = 21.0;
          _addCyl(V3(x, y, -half), V3(x, y, half), r, 'bar', pieces: 10, discs: true);
          grips.add(GripAxis(V3(x, y, -half), V3(x, y, half), r, 'bar'));
          // uprights: fine pieces near the bar, then a piece that fades out
          final fadeStart = compactProps ? 5.0 : 34.0;
          final top = compactProps ? 14.0 : 74.0;
          for (final zz in [-19.5, 19.5]) {
            final u = _Upright(V3(x, y, zz));
            final y0 = y - 1.6;
            var yy = y0;
            var i = 0;
            while (yy < y + fadeStart - 1e-6) {
              final y1 = math.min(y + fadeStart, yy + 10);
              final c = CylItem('upright${zz > 0 ? 'N' : 'F'}$i')
                ..a = V3(x, yy, zz)
                ..b = V3(x, y1, zz)
                ..r = 0.85
                ..discA = i == 0;
              u.pieces.add(c);
              yy = y1;
              i++;
            }
            u.pieces.add(CylItem('upright${zz > 0 ? 'N' : 'F'}fade')
              ..a = V3(x, y + fadeStart, zz)
              ..b = V3(x, y + top, zz)
              ..r = 0.85
              ..fadeFrom = 0);
            u.whole = CylItem('upright${zz > 0 ? 'N' : 'F'}')
              ..a = V3(x, y0, zz)
              ..b = V3(x, y + top, zz)
              ..r = 0.85
              ..discA = true
              ..fadeFrom = (fadeStart + 1.6) / (top + 1.6);
            propItems.addAll(u.pieces);
            propItems.add(u.whole);
            _uprights.add(u);
          }
          break;
        case 'pbars':
          final y = -p.get('y', 52);
          final x1 = p.get('x1', 25), x2 = p.get('x2', 80);
          const r = 1.3;
          for (final zz in [-10.0, 10.0]) {
            _addCyl(V3(x1, y, zz), V3(x2, y, zz), r, 'pbar', pieceLen: 6, discs: true);
            grips.add(GripAxis(V3(x1, y, zz), V3(x2, y, zz), r, 'pbar'));
            for (final px in [x1 + 4, x2 - 4]) {
              _addCyl(V3(px, y - 0.8, zz), V3(px, fy, zz), 1.05, 'post',
                  pieceLen: 8, discs: false);
              _contacts.add(V3(px, fy, zz));
              _contactR.add(1.05);
            }
          }
          break;
        case 'pole':
          final x = p.get('x', 30);
          // fine pieces where the body can be, one piece above
          _addCyl(V3(x, fy, 0), V3(x, fy + 140, 0), 1.7, 'pole', pieceLen: 7, discs: false);
          _addCyl(V3(x, fy + 140, 0), V3(x, fy + 260, 0), 1.7, 'poleTop', pieces: 1, discs: false);
          grips.add(GripAxis(V3(x, fy, 0), V3(x, fy + 260, 0), 1.7, 'pole'));
          _contacts.add(V3(x, fy, 0));
          _contactR.add(1.7);
          break;
        case 'box':
          final b = BoxItem('box');
          final x = p.get('x'), y = p.get('y'), w = p.get('w'), h = p.get('h');
          // 2D (x, y top, w, h) with y down; extend to the visual floor if it touches it
          var yBottom = -(y + h);
          if (floorData != null && (y + h - floorData).abs() < 0.5) yBottom = fy;
          b.lo = V3(x, yBottom, -10);
          b.hi = V3(x + w, -y, 10);
          propItems.add(b);
          break;
        case 'wall':
          _wall = _Wall(p.get('x', 80), fy);
          break;
      }
    }
  }

  void _addCyl(V3 a, V3 b, double r, String name,
      {int? pieces, double pieceLen = 6, bool discs = false}) {
    final len = (b - a).length;
    final n = pieces ?? math.max(1, (len / pieceLen).ceil());
    for (var i = 0; i < n; i++) {
      final c = CylItem('$name$i');
      c.a = V3.lerp(a, b, i / n);
      c.b = V3.lerp(a, b, (i + 1) / n);
      c.r = r;
      c.discA = discs && i == 0;
      c.discB = discs && i == n - 1;
      propItems.add(c);
    }
  }

  // ------------------------------------------------------------------ body
  /// Visual upper-arm direction (from the deltoid ball centre to the elbow).
  final List<V3> _uaVis = [V3.unitX, V3.unitX];

  /// Visual end of the forearm (the wrist; moved off the grip axis while
  /// gripping).
  final List<V3> _wrVis = [V3.zero, V3.zero];

  bool _torsoCutsSet = false;

  void _torso(EllipsoidItem e, TorsoPart p, Skeleton s) {
    final T = s.tAxis, F = s.fwd, L = s.lat;
    e.set(s.hip + T * p.t + F * p.f, L * p.rl, T * p.rt, F * p.rf);
  }

  /// Build body item geometry from the solved skeleton.
  void buildBody(Skeleton s) {
    final T = s.tAxis, L = s.lat;
    // sculpted torso: pelvis, waist, lower ribcage and chest overlap strongly
    // (no bead-like pinches); the chest is the widest piece (V-taper)
    _torso(pelvis, TorsoPart.pelvis, s);
    _torso(abdomen, TorsoPart.abdomen, s);
    _torso(ribcage, TorsoPart.ribcage, s);
    _torso(chest, TorsoPart.chest, s);
    if (!_torsoCutsSet) {
      // cuts live in each piece's local frame: constant
      _torsoCutsSet = true;
      final pieces = [pelvis, abdomen, ribcage, chest];
      for (var i = 0; i < pieces.length; i++) {
        final p = TorsoPart.stack[i];
        if (i + 1 < pieces.length) TorsoPart.cuts[i].applyTo(pieces[i], p, 0, true);
        if (i > 0) TorsoPart.cuts[i - 1].applyTo(pieces[i], p, 1, false);
      }
    }

    final hA = s.hAxis, hF = s.hFwd;
    final hL = hF.cross(hA).unit;
    // head raised so ~2.5 units of neck show between the chest and the jaw
    final headC = s.head + hA * 0.7;
    neck.set([s.neck - T * 3.0, s.neck + hA * 5.4], [2.5, 2.25]);
    // single-ellipsoid head, tilted so the chin is slightly forward
    const tilt = 10 * deg2rad;
    final hUp = (hA * math.cos(tilt) - hF * math.sin(tilt)).unit;
    final hFw = (hF * math.cos(tilt) + hA * math.sin(tilt)).unit;
    head.set(headC, hL * 4.0, hUp * 4.85, hFw * 4.5);
    // nose: centre just inside the face surface (protrudes ~0.45)
    nose.set(headC + hFw * 4.22 - hUp * 0.55, hL * 0.68, hUp * 1.1, hFw * 0.7);
    nose.rimScale = 0;

    for (var i = 0; i < 2; i++) {
      final side = i == 0 ? 1.0 : -1.0;
      // arms
      final sh = s.shoulder[i], el = s.elbow[i];
      final shV = sh - T * Dims.deltoidDown + L * (side * Dims.deltoidOut);
      _uaVis[i] = (el - shV).unit;
      shBall[i]
        ..c = shV
        ..r = Dims.shoulderBall
        ..enabled = true;
      elBall[i]
        ..c = el
        ..r = Dims.elbowBall
        ..enabled = true;
      _buildHand(s, i);
      final wr = _wrVis[i];
      wrBall[i]
        ..c = wr
        ..r = _handMode[i] == 2 ? Dims.gripWristBall : Dims.wristBall
        ..enabled = true;
      upperArm[i].set(
          [shV, V3.lerp(shV, el, Dims.upperArmMid), el], Dims.upperArm);
      foreArm[i].set([el, V3.lerp(el, wr, Dims.foreArmMid), wr], Dims.foreArm);
      upperArm[i].trimStart = Dims.shoulderBall * 0.8;
      upperArm[i].trimEnd = Dims.elbowBall * 0.8;
      foreArm[i].trimStart = Dims.elbowBall * 0.8;
      foreArm[i].trimEnd = Dims.wristBall * 0.8;

      // legs
      final hp = s.hipJ[i], kn = s.knee[i], an = s.ankle[i];
      hpBall[i]
        ..c = hp
        ..r = Dims.hipBall
        ..enabled = true;
      knBall[i]
        ..c = kn
        ..r = Dims.kneeBall
        ..enabled = true;
      anBall[i]
        ..c = an
        ..r = Dims.ankleBall
        ..enabled = true;
      // deep knee flexion (tucks): slim the calf/thigh bulges so the folded
      // leg does not swell into a blob
      final fold = _smooth(-0.5, -0.92, s.thDir[i].dot(s.shDir[i]));
      thigh[i].set([hp, V3.lerp(hp, kn, Dims.thighMid), kn],
          [Dims.thigh[0], Dims.thigh[1] - 0.4 * fold, Dims.thigh[2]]);
      shin[i].set([kn, V3.lerp(kn, an, Dims.shinMid), an],
          [Dims.shin[0], Dims.shin[1] - 0.3 * fold, Dims.shin[2]]);
      thigh[i].trimStart = Dims.hipBall * 0.8;
      thigh[i].trimEnd = Dims.kneeBall * 0.8;
      shin[i].trimStart = Dims.kneeBall * 0.8;
      shin[i].trimEnd = Dims.ankleBall * 0.8;

      _buildFoot(s, i);
    }
    _attachAll();
  }

  static double _smooth(double e0, double e1, double x) {
    final t = clampD((x - e0) / (e1 - e0), 0, 1);
    return t * t * (3 - 2 * t);
  }

  /// Ball attachments (cut planes where the limbs enter the balls).
  void _attachAll() {
    final s = skel;
    for (var i = 0; i < 2; i++) {
      final la = (_wrVis[i] - s.elbow[i]).unit;
      _attach(shBall[i], 0, _uaVis[i], upperArm[i], 0);
      _attach(elBall[i], 0, -_uaVis[i], upperArm[i], 2);
      _attach(elBall[i], 1, la, foreArm[i], 0);
      _attach(wrBall[i], 0, -la, foreArm[i], 2);
      _attach(hpBall[i], 0, s.thDir[i], thigh[i], 0);
      _attach(knBall[i], 0, -s.thDir[i], thigh[i], 2);
      _attach(knBall[i], 1, s.shDir[i], shin[i], 0);
      _attach(anBall[i], 0, -s.shDir[i], shin[i], 2);
    }
  }

  void _attach(SphereItem ball, int slot, V3 dir, LimbItem limb, int endIdx) {
    while (ball.attach.length <= slot) {
      ball.attach.add(Attach());
    }
    final a = ball.attach[slot];
    a.dir = dir;
    a.active = true;
    a.limb = limb;
    a.end = endIdx == 0 ? 0 : 1;
    // radius at the ball end and taper rate going away from the ball
    final n = limb.pts.length;
    final r0 = limb.rad[endIdx];
    final nextIdx = endIdx == 0 ? 1 : n - 2;
    final l = (limb.pts[nextIdx] - limb.pts[endIdx]).length;
    final k = l > 1e-6 ? (limb.rad[nextIdx] - r0) / l : 0.0;
    a.h = SphereItem.cutH(ball.r, r0, k);
  }

  // hand: fist around a grip, flat on the floor, or a free mitten
  final List<int> _handMode = [0, 0]; // 0 mitten, 1 flat, 2 fist

  void _buildHand(Skeleton s, int i) {
    final wr = s.wrist[i];
    final la = s.laDir[i];
    GripAxis? grip;
    for (final g in grips) {
      if (g.distTo(wr) < g.r + 2.2) {
        grip = g;
        break;
      }
    }
    if (grip != null) {
      // Fist in two halves straddling the grip axis (knuckle line along the
      // axis); the gripped prop piece is painted between them, so the bar
      // visibly passes through the hand. The forearm ends at a visual wrist
      // just off the bar.
      _handMode[i] = 2;
      final gd = grip.dir;
      final gc = grip.closest(wr);
      var up = la - gd * la.dot(gd);
      if (up.length < 0.2) {
        up = s.fwd - gd * s.fwd.dot(gd);
        if (up.length < 0.2) up = s.lat - gd * s.lat.dot(gd);
      }
      up = up.unit;
      var th = gd.cross(up).unit;
      // fingers wrap the side of the bar facing away from the body
      if (th.dot(s.fwd) - 0.3 * th.dot(s.tAxis) < 0) th = -th;
      _grip[i] = (gc, gd, up, th, grip.r);
      _setFist(i, 0);
      _wrVis[i] = wr - la * Dims.gripWrist;
      return;
    }
    hand2[i].enabled = false;
    hand[i].enabled = true;
    _wrVis[i] = wr;
    final fy = floorY;
    if (fy != null && wr.y - fy < 4.2) {
      _handMode[i] = 1;
      var f = V3(s.fwd.x, 0, s.fwd.z);
      if (f.length < 0.5) f = V3(s.tAxis.x, 0, s.tAxis.z);
      if (f.length < 0.2) f = V3.unitX;
      f = f.unit;
      final side = V3(-f.z, 0, f.x);
      final c = V3(wr.x, fy + 1.25, wr.z) + f * 1.9;
      hand[i].set(c, f * 2.6, side * 1.65, const V3(0, 1.25, 0));
      return;
    }
    _handMode[i] = 0;
    var w = s.laFront[i] - la * s.laFront[i].dot(la);
    if (w.length < 1e-3) w = s.fwd;
    w = w.unit;
    final th = la.cross(w).unit;
    _mitW[i] = w;
    _mitTh[i] = th;
    hand[i].set(wr + la * 2.45, la * 2.8, w * 1.75, th * 1.08);
  }

  /// Grip frame per side: axis point, axis direction, up (toward the knuckles,
  /// away from the forearm), across (finger side), grip radius.
  final List<(V3, V3, V3, V3, double)> _grip = List.filled(2, (V3.zero, V3.unitZ, V3.unitY, V3.unitX, 1.5));

  /// Fist around the grip axis: [hand] = curled fingers (a band over the
  /// bar on the side away from the body), [hand2] = palm / back of the hand
  /// (taller, knuckles above the bar, heel down to the wrist). [merge] 0..1
  /// blends both into one rounded fist centred on the axis (used when the
  /// grip axis points at the camera, where two lobes read as knobs).
  void _setFist(int i, double merge) {
    final (gc, gd, up, th, r) = _grip[i];
    final m = merge, k = 1 - merge;
    // merged fist
    final mc = gc - up * 0.25;
    hand[i]
      ..set(gc + th * ((r + 0.3) * k) + up * (0.05 * k) + (mc - gc) * m, gd * 2.05,
          up * (1.5 * k + 2.25 * m), th * (0.95 * k + 1.95 * m))
      ..enabled = true;
    hand2[i]
      ..set(gc - th * (0.55 * k) - up * (0.85 * k) + (mc - gc) * m, gd * 2.0,
          up * (2.2 * k + 2.25 * m), th * (1.35 * k + 1.95 * m))
      ..enabled = merge < 0.999;
  }

  /// Mitten frame (width / thickness directions) per side.
  final List<V3> _mitW = [V3.unitX, V3.unitX];
  final List<V3> _mitTh = [V3.unitZ, V3.unitZ];

  /// Foot forward direction per side (heel / forefoot paint order).
  final List<V3> _footFwd = [V3.unitX, V3.unitX];

  void _buildFoot(Skeleton s, int i) {
    final an = s.ankle[i];
    final sd = s.shDir[i];
    var f0 = s.shFront[i];
    // foot frame: forward fv, sole-down dv
    final fy = floorY;
    final h = fy == null ? 99.0 : an.y - fy;
    // groundedness 1 = flat on floor
    final g = fy == null ? 0.0 : clampD(1 - (h - 3.2) / 4.0, 0, 1);
    // pointed frame: nearly in line with the shin (gymnastic point) when the
    // leg is straight or the shin is held up (levers, tucks); relaxed (30 deg
    // off the shin) when the shin hangs down
    final straight = clampD((s.thDir[i].dot(sd) - 0.85) / 0.12, 0, 1);
    final held = clampD((sd.y + 0.75) / 0.4, 0, 1);
    final relaxed = clampD((-sd.y - 0.8) / 0.15, 0, 1);
    final folded = _smooth(-0.5, -0.85, s.thDir[i].dot(sd));
    var point = math.max(math.max(straight * (1 - relaxed), held), folded);
    point = point * point * (3 - 2 * point);
    final pf = (60 + 18 * point) * deg2rad;
    final fvP = (f0 * math.cos(pf) + sd * math.sin(pf)).unit;
    final dvP = (sd * math.cos(pf) - f0 * math.sin(pf)).unit;
    // flat frame
    var fh = V3(f0.x, 0, f0.z);
    if (fh.length < 0.3) fh = V3(s.fwd.x, 0, s.fwd.z);
    if (fh.length < 0.3) fh = V3.unitX;
    fh = fh.unit;
    const dvF = V3(0, -1, 0);
    final fv = (fvP * (1 - g) + fh * g).unit;
    final dv = (dvP * (1 - g) + dvF * g).unit;
    var side = fv.cross(dv);
    side = side.length < 1e-6 ? s.lat : side.unit;
    final dv2 = side.cross(fv).unit; // re-orthogonalised sole normal
    _footFwd[i] = fv;
    // heel under the ankle; wider forefoot in front, its long axis tilted
    // down toward the toes so the instep rises to the ankle (a wedge from
    // the front and the side)
    heel[i].set(an + dv2 * 1.0 - fv * 0.25, fv * 1.85, side * 1.45, dv2 * 1.32);
    const tilt = 6 * deg2rad;
    final fvT = fv * math.cos(tilt) + dv2 * math.sin(tilt);
    final dvT = dv2 * math.cos(tilt) - fv * math.sin(tilt);
    foot[i].set(an + dv2 * 1.4 + fv * 3.25, fvT * 3.9, side * 2.15, dvT * 0.92);
  }

  // ------------------------------------------------------------------ view
  /// View-dependent tweaks (called every frame before linking): joints whose
  /// limbs point at the camera lose their balls (no telescope rings), and a
  /// free mitten pointing at the camera is centred on the wrist.
  void _viewAdjust(ViewCam cam) {
    final s = skel;
    for (var i = 0; i < 2; i++) {
      final la = (_wrVis[i] - s.elbow[i]).unit;
      final zUa = cam.rot(_uaVis[i]).z.abs();
      final zLa = cam.rot(la).z.abs();
      final zTh = cam.rot(s.thDir[i]).z.abs();
      final zSh = cam.rot(s.shDir[i]).z.abs();
      _endOnBall(elBall[i], math.min(zUa, zLa), (Dims.upperArm[2] + Dims.foreArm[0]) / 2);
      _endOnBall(knBall[i], math.min(zTh, zSh), (Dims.thigh[2] + Dims.shin[0]) / 2);
      if (_handMode[i] == 0) {
        // the hand covers the wrist when the forearm points at the camera
        _endOnBall(wrBall[i], zLa, Dims.foreArm[2]);
        // seen end-on, the mitten is a compact rounded oval on the wrist
        final b = _smooth(0.55, 0.85, zLa);
        if (b > 0) {
          final la0 = s.laDir[i];
          hand[i].set(s.wrist[i] + la0 * (2.45 - 1.65 * b), la0 * 2.8,
              _mitW[i] * (1.75 - 0.3 * b), _mitTh[i] * (1.08 + 0.27 * b));
        }
      }
      if (_handMode[i] == 2) {
        final gz = cam.rot(_grip[i].$2).z.abs();
        _setFist(i, _smooth(0.55, 0.85, gz));
      }
      // ankle: the foot covers it when the shin points at the camera
      _endOnBall(anBall[i], zSh, Dims.shin[2]);
    }
    _attachAll();
  }

  void _endOnBall(SphereItem b, double z, double rLimb) {
    final t = _smooth(Dims.endOn0, Dims.endOn1, z);
    if (t >= 0.999) {
      b.enabled = false;
      return;
    }
    b.r = b.r + (math.min(b.r, rLimb) - b.r) * t;
  }

  // ------------------------------------------------------------------ links
  void _link(RenderCtx ctx) {
    for (final it in bodyItems) {
      it.resetLinks();
    }
    for (final it in propItems) {
      it.resetLinks();
    }
    void after(Item later, Item earlier) {
      later.after.add(earlier);
      later.noTest.add(earlier);
      earlier.noTest.add(later);
    }

    final cam = ctx.cam;
    after(head, neck);
    after(chest, neck);
    // nose on the face: over the head when the face is (partly) visible
    if (cam.rot(skel.hFwd).z > -0.3) {
      after(nose, head);
    } else {
      after(head, nose);
    }
    // torso stack (cut where the pieces meet, so they only overlap in a thin
    // band): the end nearer to the viewer is painted last
    final tz = cam.rot(skel.tAxis).z;
    final up = tz >= 0;
    void pair(EllipsoidItem lower, EllipsoidItem upper) {
      if (up) {
        after(upper, lower);
      } else {
        after(lower, upper);
      }
    }

    pair(pelvis, abdomen);
    pair(abdomen, ribcage);
    pair(ribcage, chest);
    pair(pelvis, ribcage);
    pair(abdomen, chest);
    pair(pelvis, chest);

    // joint balls vs limbs: limb toward the viewer -> ball underneath, limb
    // drawn on top with its projected entry circle; otherwise ball on top
    // with an exact bite where the limb enters it
    for (final l in _limbs) {
      l.entryStart = -1;
      l.entryEnd = -1;
    }
    for (final ball in _balls) {
      if (!ball.enabled) continue;
      for (final a in ball.attach) {
        final limb = a.limb;
        if (limb == null) continue;
        final dz = cam.rot(a.dir).z;
        if (dz > Dims.ballUnderLimb) {
          a.active = false;
          after(limb, ball);
          if (a.end == 0) {
            limb.entryStart = a.h;
          } else {
            limb.entryEnd = a.h;
          }
        } else {
          a.active = true;
          after(ball, limb);
        }
      }
    }

    for (var i = 0; i < 2; i++) {
      // thigh tops tuck under the pelvis unless the thigh points at the viewer
      // (the waist piece continues the pelvis surface where the cut plane
      // dips low at the front, so it follows the same rule)
      final tzd = cam.rot(skel.thDir[i]).z;
      for (final t in [pelvis, abdomen]) {
        if (tzd > 0.3) {
          after(thigh[i], t);
          after(hpBall[i], t);
        } else {
          after(t, thigh[i]);
          after(t, hpBall[i]);
        }
      }
      // heel / forefoot: the nearer one last
      if (cam.rot(_footFwd[i]).z > 0) {
        after(foot[i], heel[i]);
      } else {
        after(heel[i], foot[i]);
      }
      // the shin enters the foot from above: over it when the ankle end is
      // the farther one, under it otherwise (same for the ankle ball)
      final ankleFar = cam.rot(skel.shDir[i]).z < 0;
      for (final f in [heel[i], foot[i]]) {
        if (ankleFar) {
          after(shin[i], f);
          if (anBall[i].enabled) after(anBall[i], f);
        } else {
          after(f, shin[i]);
          if (anBall[i].enabled) after(f, anBall[i]);
        }
      }
      if (_handMode[i] == 2) {
        // fist halves: far half, then forearm / wrist / gripped prop piece,
        // then the near half (one merged fist: after the gripped piece)
        final a = hand[i], b = hand2[i];
        final merged = !b.enabled;
        final aNear = merged || cam.toView(a.c).z > cam.toView(b.c).z;
        final near = aNear ? a : b, far = aNear ? b : a;
        if (!merged) {
          after(near, far);
          after(foreArm[i], far);
          if (wrBall[i].enabled) after(wrBall[i], far);
        }
        after(near, foreArm[i]);
        if (wrBall[i].enabled) after(near, wrBall[i]);
        final w = skel.wrist[i];
        for (final p in propItems) {
          if (p is! CylItem) continue;
          // the prop piece that holds the grip point
          final d = p.b - p.a;
          final l2 = d.length2;
          if (l2 < 1e-9) continue;
          final t = (w - p.a).dot(d) / l2;
          if (t < -0.02 || t > 1.02) continue;
          if ((p.a + d * t - w).length > p.r + 1.0) continue;
          if (!merged) after(p, far);
          after(near, p);
          // the forearm / wrist reach the bar from the palm side
          after(foreArm[i], p);
          if (wrBall[i].enabled) after(wrBall[i], p);
        }
      }
    }
  }

  /// Translucent prop pieces never paint over the body.
  void _linkTranslucent() {
    for (final p in _active) {
      if (p is CylItem && p.alpha < 0.999) {
        for (final b in bodyItems) {
          if (!b.enabled) continue;
          b.after.add(p);
          b.noTest.add(p);
          p.noTest.add(b);
        }
      }
    }
  }

  // ------------------------------------------------------------------ sort
  final List<Item> _active = [];
  final List<Item> _order = [];

  void _sort() {
    final items = _active;
    final n = items.length;
    for (final it in items) {
      it.succ.clear();
      it.pred.clear();
      it.indeg = 0;
      it.emitted = false;
    }
    void edge(Item before, Item later) {
      before.succ.add(later);
      later.pred.add(before);
      later.indeg++;
    }

    for (final it in items) {
      for (final e in it.after) {
        if (e.enabled && _activeSet.contains(e)) edge(e, it);
      }
    }
    for (var i = 0; i < n; i++) {
      final a = items[i];
      for (var j = i + 1; j < n; j++) {
        final b = items[j];
        if (a.maxX < b.minX || b.maxX < a.minX || a.maxY < b.minY || b.maxY < a.minY) {
          continue;
        }
        if (a.noTest.contains(b)) continue;
        if (a is CylItem && b is CylItem) continue; // props among themselves
        final r = _compare(a, b);
        if (r > 0) {
          edge(b, a);
        } else if (r < 0) {
          edge(a, b);
        }
      }
    }
    // Kahn with farthest-first priority; cycles broken by depth
    _order.clear();
    _cycles = 0;
    var remaining = n;
    while (remaining > 0) {
      Item? best;
      for (final it in items) {
        if (it.emitted || it.indeg > 0) continue;
        if (best == null || it.depth < best.depth) best = it;
      }
      if (best == null) {
        // cycle: walk unemitted predecessors from the farthest blocked item
        // until a node repeats, then emit the farthest item of that cycle
        // only (items outside the cycle keep their constraints)
        _cycles++;
        Item? start;
        for (final it in items) {
          if (it.emitted) continue;
          if (start == null || it.depth < start.depth) start = it;
        }
        _markGen++;
        var cur = start!;
        while (cur.mark != _markGen) {
          cur.mark = _markGen;
          Item? next;
          for (final p in cur.pred) {
            if (!p.emitted) {
              next = p;
              break;
            }
          }
          if (next == null) break;
          cur = next;
        }
        // cur is on the cycle: collect it
        final c0 = cur;
        best = cur;
        var guard = 0;
        final names = debugPrintOrder ? <String>[cur.name] : null;
        do {
          Item? next;
          for (final p in cur.pred) {
            if (!p.emitted) {
              next = p;
              break;
            }
          }
          if (next == null) break;
          cur = next;
          names?.add(cur.name);
          if (cur.depth < best!.depth) best = cur;
        } while (!identical(cur, c0) && ++guard < n);
        if (names != null) {
          // ignore: avoid_print
          print('cycle: ${names.join(' <- ')}');
        }
      }
      best!.emitted = true;
      remaining--;
      _order.add(best);
      for (final s in best.succ) {
        s.indeg--;
      }
    }
  }

  final Set<Item> _activeSet = {};

  /// +1: a in front of b (paint a after b); -1: b in front; 0: no overlap.
  int _compare(Item a, Item b) {
    final (s, t) = closestSegSeg(a.ax, a.ay, a.bx, a.by, b.ax, b.ay, b.bx, b.by);
    final pax = a.ax + (a.bx - a.ax) * s, pay = a.ay + (a.by - a.ay) * s;
    final pbx = b.ax + (b.bx - b.ax) * t, pby = b.ay + (b.by - b.ay) * t;
    final dx = pbx - pax, dy = pby - pay;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist > a.rr + b.rr) return 0;
    final w = a.rr / (a.rr + b.rr);
    final px = pax + dx * w, py = pay + dy * w;
    var za = a.frontZ(px, py), zb = b.frontZ(px, py);
    if (za.isNaN || zb.isNaN) {
      // fall back to the core points
      za = a.az + (a.bz - a.az) * s + a.rr;
      zb = b.az + (b.bz - b.az) * t + b.rr;
      final za2 = a.frontZ(pax, pay), zb2 = b.frontZ(pax, pay);
      if (!za2.isNaN && !zb2.isNaN) {
        za = za2;
        zb = zb2;
      } else {
        final za3 = a.frontZ(pbx, pby), zb3 = b.frontZ(pbx, pby);
        if (!za3.isNaN && !zb3.isNaN) {
          za = za3;
          zb = zb3;
        } else if (za2.isNaN && za3.isNaN || zb2.isNaN && zb3.isNaN) {
          // silhouettes do not really overlap near the probes
          if (dist > (a.rr + b.rr) * 0.85) return 0;
        }
      }
    }
    if (za > zb + 1e-6) return 1;
    if (zb > za + 1e-6) return -1;
    return a.depth >= b.depth ? 1 : -1;
  }

  // ------------------------------------------------------------------ paint
  RenderCtx? _ctx;

  /// Uprights fade out (to nothing) while they line up on screen with the
  /// hands, so the figure never seems to hang from a vertical pole; while
  /// translucent they are drawn as one piece, under the body.
  void _updateUprights(ViewCam cam) {
    for (final u in _uprights) {
      var off = double.infinity;
      for (var i = 0; i < 2; i++) {
        if (_handMode[i] != 2) continue;
        off = math.min(off, cam.rot(u.base - skel.wrist[i]).x.abs());
      }
      if (!off.isFinite) {
        off = cam.rot(u.base - V3(u.base.x, u.base.y, 0)).x.abs();
      }
      final t = clampD((off - 2.5) / 3.5, 0, 1);
      var alpha = t * t * (3 - 2 * t);
      if (alpha < 0.05) alpha = 0;
      final opaque = alpha >= 0.999;
      for (final p in u.pieces) {
        p.alpha = opaque ? 1 : 0;
      }
      u.whole.alpha = opaque ? 0 : alpha;
    }
  }

  void paint(ui.Canvas canvas, ui.Size size, ViewCam cam, MannequinStyle style,
      {bool drawBackground = true}) {
    final ctx = _ctx ??= RenderCtx(cam, style);
    ctx.cam = cam;
    ctx.style = style;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    if (drawBackground) {
      canvas.drawColor(style.background, BlendMode.src);
    }
    _viewAdjust(cam);
    if (floorY != null) _paintFloor(canvas, size, ctx);

    _active.clear();
    _activeSet.clear();
    _link(ctx);
    _updateUprights(cam);
    for (final it in bodyItems) {
      if (!it.enabled) continue;
      it.prepare(ctx);
      _active.add(it);
    }
    for (final it in propItems) {
      if (it is CylItem && it.alpha <= 0.01) continue;
      it.prepare(ctx);
      if (it is CylItem && !it.onScreen(size)) continue;
      _active.add(it);
    }
    _activeSet.addAll(_active);
    _linkTranslucent();

    final wall = _wall;
    var wallFront = false;
    if (wall != null) {
      wallFront = wall.isInFront(cam, skel.hip);
      if (!wallFront) wall.paint(canvas, ctx, 1.0);
    }
    _sort();
    if (debugPrintOrder) {
      // ignore: avoid_print
      print('order: ${_order.map((e) => e.name).join(' ')}  cycles=$_cycles');
    }
    for (final it in _order) {
      if (debugHide.contains(it.name)) continue;
      it.paint(canvas, ctx);
    }
    if (wall != null && wallFront) wall.paint(canvas, ctx, 0.22);
    canvas.restore();
  }

  // ------------------------------------------------------------------ floor
  final Paint _shadowPaint = Paint()..isAntiAlias = true;
  final Paint _floorPaint = Paint()..isAntiAlias = true;
  final Paint _gridPaint = Paint()
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;
  final Float64List _fm = Float64List(16);
  ui.Shader? _blobShader;

  // cached floor disc + grid (depends on the camera only)
  ui.Picture? _floorPic;
  final List<double> _floorKey = List.filled(11, double.nan);
  MannequinStyle? _floorStyle;

  void _floorMatrix(ViewCam cam, V3 p, double r, Float64List m) {
    final v = cam.toView(p);
    final s = cam.pxScale(v.z);
    final xv = cam.rot(V3.unitX), zv = cam.rot(V3.unitZ);
    final sc = cam.toScreen(v);
    m.fillRange(0, 16, 0);
    m[0] = xv.x * s * r;
    m[1] = -xv.y * s * r;
    m[4] = zv.x * s * r;
    m[5] = -zv.y * s * r;
    m[10] = 1;
    m[12] = sc.dx;
    m[13] = sc.dy;
    m[15] = 1;
  }

  bool _floorKeyMatches(ViewCam cam, ui.Size size) {
    final k = [
      cam.yawDeg, cam.pitchDeg, cam.k, cam.ox, cam.oy, cam.persp, //
      cam.pivot.x, cam.pivot.y, cam.pivot.z, size.width, size.height
    ];
    var same = true;
    for (var i = 0; i < k.length; i++) {
      if (_floorKey[i] != k[i]) {
        same = false;
        _floorKey[i] = k[i];
      }
    }
    return same;
  }

  void _paintFloor(ui.Canvas canvas, ui.Size size, RenderCtx ctx) {
    final cam = ctx.cam;
    final keyOk = _floorKeyMatches(cam, size) && identical(_floorStyle, ctx.style);
    if (!keyOk || _floorPic == null) {
      _floorPic?.dispose();
      _floorStyle = ctx.style;
      final rec = ui.PictureRecorder();
      _recordFloor(ui.Canvas(rec), ctx);
      _floorPic = rec.endRecording();
    }
    canvas.drawPicture(_floorPic!);
    _paintShadows(canvas, ctx);
  }

  void _recordFloor(ui.Canvas canvas, RenderCtx ctx) {
    final cam = ctx.cam;
    final fy = floorY!;
    final st = ctx.style;
    final center = V3(cam.pivot.x, fy, cam.pivot.z);
    const radius = 62.0;
    // soft ground disc
    _floorMatrix(cam, center, radius, _fm);
    canvas.save();
    canvas.transform(_fm);
    _floorPaint.shader = ui.Gradient.radial(Offset.zero, 1, [
      st.floorColor,
      st.floorColor.withValues(alpha: st.floorColor.a * 0.55),
      st.floorColor.withValues(alpha: 0),
    ], const [0, 0.55, 1]);
    canvas.drawCircle(Offset.zero, 1, _floorPaint);
    canvas.restore();

    // grid lines fading out
    const g = 8.0;
    final path = ui.Path();
    const nLines = 7;
    for (var i = -nLines; i <= nLines; i++) {
      final o = i * g;
      final half = math.sqrt(math.max(0.0, radius * radius - o * o));
      final a1 = cam.toScreen(cam.toView(V3(center.x + o, fy, center.z - half)));
      final b1 = cam.toScreen(cam.toView(V3(center.x + o, fy, center.z + half)));
      path.moveTo(a1.dx, a1.dy);
      path.lineTo(b1.dx, b1.dy);
      final a2 = cam.toScreen(cam.toView(V3(center.x - half, fy, center.z + o)));
      final b2 = cam.toScreen(cam.toView(V3(center.x + half, fy, center.z + o)));
      path.moveTo(a2.dx, a2.dy);
      path.lineTo(b2.dx, b2.dy);
    }
    _floorMatrix(cam, center, radius, _fm);
    _gridPaint
      ..strokeWidth = math.max(0.6, cam.k * 0.1)
      ..shader = ui.Gradient.radial(Offset.zero, 1, [
        st.gridColor,
        st.gridColor.withValues(alpha: 0),
      ], const [0.15, 1.0], TileMode.clamp, _fm);
    canvas.drawPath(path, _gridPaint);
  }

  /// Contact shadows: soft blobs under joints, torso, head, hands and feet
  /// (a few limb mid points when a limb lies low) and at the floor contacts
  /// of props. No offscreen layer: each blob is drawn with its own
  /// pre-scaled opacity.
  void _paintShadows(ui.Canvas canvas, RenderCtx ctx) {
    final cam = ctx.cam;
    final fy = floorY!;
    final st = ctx.style;
    _blobShader ??= ui.Gradient.radial(Offset.zero, 1, const [
      Color(0xFF000000),
      Color(0xB0000000),
      Color(0x40000000),
      Color(0x00000000),
    ], const [0, 0.35, 0.7, 1]);
    _shadowPaint.shader = _blobShader;
    final op = st.shadowOpacity;
    void disc(V3 p, double r, double a) {
      _floorMatrix(cam, V3(p.x, fy, p.z), r, _fm);
      canvas.save();
      canvas.transform(_fm);
      _shadowPaint.color = Color.fromRGBO(0, 0, 0, a);
      canvas.drawCircle(Offset.zero, 1, _shadowPaint);
      canvas.restore();
    }

    void blob(V3 p, double r) {
      final h = p.y - r - fy;
      const hMax = 30.0;
      if (h > hMax) return;
      final hh = math.max(0.0, h);
      // soft ambient-occlusion-like shadow, widening with height and fading
      // out steeply, so raised limbs do not leave detached smudges
      final rb = r * 1.35 + hh * 0.4;
      final f = 1 - hh / hMax;
      final a = f * f * f * 0.42 * op;
      disc(p, rb, a);
      // tight dark contact shadow near the floor
      if (hh < 3.5) {
        final ac = (1 - hh / 3.5) * 0.75 * op;
        disc(p, r * 0.95 + hh * 0.3, ac);
      }
    }

    _tsP.clear();
    _tsR.clear();
    _torsoSpheres(_tsP, _tsR);
    for (var i = 0; i < _tsP.length; i += 2) {
      blob(_tsP[i], _tsR[i] * 0.85);
    }
    for (final it in _shadowItems) {
      if (!it.enabled || _torsoItems.contains(it)) continue;
      if (it is SphereItem) {
        blob(it.c, it.r);
      } else if (it is EllipsoidItem) {
        final r = (it.a1.length + it.a2.length + it.a3.length) / 3;
        blob(it.c, r);
      }
    }
    // limbs lying low: fill the gap between their end joints
    for (final l in _limbs) {
      final a = l.pts.first, b = l.pts.last;
      if (math.min(a.y, b.y) - fy > 8) continue;
      for (final f in const [0.33, 0.67]) {
        final m = V3.lerp(a, b, f);
        blob(m, l.rad[1] * 0.9);
      }
    }
    // props standing on the floor: soft AO ring + tight contact
    for (var i = 0; i < _contacts.length; i++) {
      final r = _contactR[i];
      disc(_contacts[i], r * 3.2, 0.32 * op);
      disc(_contacts[i], r * 1.5, 0.6 * op);
    }
  }

  // ------------------------------------------------------------------ fit
  /// World points + radii describing the body volume (for auto-fit).
  void collectFitPoints(List<V3> pts, List<double> radii) {
    _torsoSpheres(pts, radii);
    for (final it in bodyItems) {
      if (!it.enabled || _torsoItems.contains(it)) continue;
      if (it is SphereItem) {
        pts.add(it.c);
        radii.add(it.r);
      } else if (it is EllipsoidItem) {
        pts.add(it.c);
        radii.add(math.max(it.a1.length, math.max(it.a2.length, it.a3.length)));
      } else if (it is LimbItem) {
        for (var i = 0; i < it.pts.length; i++) {
          pts.add(it.pts[i]);
          radii.add(it.rad[i]);
        }
      }
    }
  }

  late final Set<Item> _torsoItems = {pelvis, abdomen, ribcage, chest};

  /// Bounding spheres of the (cut) torso stack in world space.
  void _torsoSpheres(List<V3> pts, List<double> radii) {
    final s = skel;
    for (final (t, f, r) in TorsoPart.stations) {
      pts.add(s.hip + s.tAxis * t + s.fwd * f);
      radii.add(r);
    }
  }

  final List<V3> _tsP = [];
  final List<double> _tsR = [];

  /// Static prop geometry worth keeping in frame (the grip region of bars
  /// and poles, parallel bars with their posts down to the floor, boxes),
  /// given all wrist positions over the loop.
  void collectPropFitPoints(List<V3> wrists, List<V3> pts, List<double> radii) {
    final fy = floorY ?? -(88 + Dims.floorOffset);
    for (final p in _propsFor ?? const <PropSpec>[]) {
      switch (p.kind) {
        case 'bar':
          final x = p.get('x', 50), y = -p.get('y', 12);
          var z0 = double.infinity, z1 = -double.infinity;
          for (final w in wrists) {
            if ((w.x - x).abs() + (w.y - y).abs() > 6) continue;
            z0 = math.min(z0, w.z);
            z1 = math.max(z1, w.z);
          }
          if (!z0.isFinite) {
            z0 = -6;
            z1 = 6;
          }
          for (final z in [math.max(-21.0, z0 - 6), math.min(21.0, z1 + 6)]) {
            pts.add(V3(x, y, z));
            radii.add(1.6);
          }
          break;
        case 'pole':
          final x = p.get('x', 30);
          var y0 = double.infinity, y1 = -double.infinity;
          for (final w in wrists) {
            if ((w.x - x).abs() > 6 || w.z.abs() > 6) continue;
            y0 = math.min(y0, w.y);
            y1 = math.max(y1, w.y);
          }
          if (y0.isFinite) {
            pts.add(V3(x, math.max(fy, y0 - 6), 0));
            radii.add(1.7);
            pts.add(V3(x, y1 + 6, 0));
            radii.add(1.7);
          }
          break;
        case 'pbars':
          final y = -p.get('y', 52);
          final x1 = p.get('x1', 25), x2 = p.get('x2', 80);
          for (final zz in [-10.0, 10.0]) {
            for (final px in [x1, x2]) {
              pts.add(V3(px, y, zz));
              radii.add(1.3);
            }
            for (final px in [x1 + 4, x2 - 4]) {
              pts.add(V3(px, fy, zz));
              radii.add(1.6);
            }
          }
          break;
        case 'box':
          final x = p.get('x'), y = p.get('y'), w = p.get('w'), h = p.get('h');
          for (final xx in [x, x + w]) {
            for (final yy in [-y, -(y + h)]) {
              for (final zz in [-10.0, 10.0]) {
                pts.add(V3(xx, yy, zz));
                radii.add(0.5);
              }
            }
          }
          break;
      }
    }
  }

  /// Solve + build for a pose (call before paint).
  void setPose(Pose p, String anchor) {
    skel.solve(p, anchor);
    buildBody(skel);
  }
}

class _Wall {
  final double x, fy;
  _Wall(this.x, this.fy);

  bool isInFront(ViewCam cam, V3 bodyRef) {
    // camera direction in world
    final camDir = cam.rotInv(const V3(0, 0, 1));
    final side = (bodyRef.x - x).sign;
    return camDir.x * side < -0.05;
  }

  final ui.Path _p = ui.Path();

  void paint(ui.Canvas c, RenderCtx ctx, double alpha) {
    final cam = ctx.cam;
    final corners = [
      V3(x, fy, -30), V3(x, fy, 30), V3(x, fy + 140, 30), V3(x, fy + 140, -30)
    ];
    final p = _p..reset();
    for (var i = 0; i < 4; i++) {
      final s = cam.toScreen(cam.toView(corners[i]));
      if (i == 0) {
        p.moveTo(s.dx, s.dy);
      } else {
        p.lineTo(s.dx, s.dy);
      }
    }
    p.close();
    final n = cam.rot(const V3(-1, 0, 0));
    final col = ctx.shade(MatKind.prop, n.x, n.y, n.z.abs());
    ctx.fill.shader = null;
    ctx.fill.color = col.withValues(alpha: alpha * 0.55);
    c.drawPath(p, ctx.fill);
  }
}
