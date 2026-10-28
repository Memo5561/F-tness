import 'dart:math' as math;

import 'exercise_animation.dart';
import 'math3d.dart';

/// Segment lengths (data units, same as the 2D stick figure).
class BodyLengths {
  static const double neck = 3, head = 5, torso = 24;
  static const double upperArm = 12, foreArm = 11, thigh = 16, shin = 16;
  static const double shoulderHalf = 7, hipHalf = 4.5;
}

/// 3D forward kinematics result (world space: x right, y up, z toward camera).
class Skeleton {
  V3 hip = V3.zero, neck = V3.zero, head = V3.zero;

  /// Body frame: torso axis (hip->neck), chest-forward axis, lateral axis (side 1).
  V3 tAxis = V3.unitY, fwd = V3.unitX, lat = V3.unitZ;

  /// Head axis (neck->head) and head-forward.
  V3 hAxis = V3.unitY, hFwd = V3.unitX;

  // index 0 = side 1 (near, +z), index 1 = side 2 (far, -z)
  final List<V3> shoulder = [V3.zero, V3.zero];
  final List<V3> elbow = [V3.zero, V3.zero];
  final List<V3> wrist = [V3.zero, V3.zero];
  final List<V3> hipJ = [V3.zero, V3.zero];
  final List<V3> knee = [V3.zero, V3.zero];
  final List<V3> ankle = [V3.zero, V3.zero];

  /// Directions of segments.
  final List<V3> uaDir = [V3.zero, V3.zero];
  final List<V3> laDir = [V3.zero, V3.zero];
  final List<V3> thDir = [V3.zero, V3.zero];
  final List<V3> shDir = [V3.zero, V3.zero];

  /// "Front" of the forearm / shin: perpendicular to the segment in its
  /// sagittal plane (unaffected by abduction), pointing to the body's front.
  final List<V3> laFront = [V3.zero, V3.zero];
  final List<V3> shFront = [V3.zero, V3.zero];

  /// World point for an anchor name ('w1', 'f2', 'hip', 'sh', 'e1', 'k2', 'head').
  V3 joint(String name) {
    switch (name) {
      case 'hip':
        return hip;
      case 'sh':
      case 'neck':
        return neck;
      case 'head':
        return head;
    }
    final side = name.length > 1 && name[name.length - 1] == '2' ? 1 : 0;
    switch (name[0]) {
      case 'w':
        return wrist[side];
      case 'e':
        return elbow[side];
      case 'f':
        return ankle[side];
      case 'k':
        return knee[side];
      case 's':
        return shoulder[side];
    }
    return hip;
  }

  /// Solves the pose; anchors the given joint at the pose's 'at' target.
  void solve(Pose p, String anchor) {
    final a = p.a;
    final t = a[PoseKeys.t] * deg2rad;
    final tb = a[PoseKeys.tb] * deg2rad;
    final hd = a[PoseKeys.hd] * deg2rad;
    final ctb = math.cos(tb), stb = math.sin(tb);

    final t0 = V3(math.cos(t), math.sin(t), 0);
    tAxis = t0 * ctb + V3.unitZ * stb;
    fwd = V3(math.sin(t), -math.cos(t), 0);
    lat = V3.unitZ * ctb - t0 * stb;

    final h0 = V3(math.cos(hd), math.sin(hd), 0);
    hAxis = h0 * ctb + V3.unitZ * stb;
    hFwd = V3(math.sin(hd), -math.cos(hd), 0);

    const origin = V3.zero;
    final nk = origin + tAxis * BodyLengths.torso;
    final hdC = nk + hAxis * (BodyLengths.neck + BodyLengths.head);

    final sh = [
      nk + lat * BodyLengths.shoulderHalf,
      nk - lat * BodyLengths.shoulderHalf
    ];
    final hj = [
      origin + lat * BodyLengths.hipHalf,
      origin - lat * BodyLengths.hipHalf
    ];

    final el = <V3>[V3.zero, V3.zero], wr = <V3>[V3.zero, V3.zero];
    final kn = <V3>[V3.zero, V3.zero], an = <V3>[V3.zero, V3.zero];
    for (var s = 0; s < 2; s++) {
      final sign = s == 0 ? 1.0 : -1.0;
      final ua = s == 0 ? PoseKeys.ua1 : PoseKeys.ua2;
      final la = s == 0 ? PoseKeys.la1 : PoseKeys.la2;
      final th = s == 0 ? PoseKeys.th1 : PoseKeys.th2;
      final sn = s == 0 ? PoseKeys.sh1 : PoseKeys.sh2;
      final uab = s == 0 ? PoseKeys.ua1b : PoseKeys.ua2b;
      final lab = s == 0 ? PoseKeys.la1b : PoseKeys.la2b;
      final thb = s == 0 ? PoseKeys.th1b : PoseKeys.th2b;
      final snb = s == 0 ? PoseKeys.sh1b : PoseKeys.sh2b;

      uaDir[s] = segDir(a[ua], a[uab], sign);
      laDir[s] = segDir(a[la], a[lab], sign);
      thDir[s] = segDir(a[th], a[thb], sign);
      shDir[s] = segDir(a[sn], a[snb], sign);
      final lar = a[la] * deg2rad, snr = a[sn] * deg2rad;
      laFront[s] = V3(-math.sin(lar), math.cos(lar), 0);
      shFront[s] = V3(-math.sin(snr), math.cos(snr), 0);

      el[s] = sh[s] + uaDir[s] * BodyLengths.upperArm;
      wr[s] = el[s] + laDir[s] * BodyLengths.foreArm;
      kn[s] = hj[s] + thDir[s] * BodyLengths.thigh;
      an[s] = kn[s] + shDir[s] * BodyLengths.shin;
    }

    // anchor placement
    hip = origin;
    neck = nk;
    head = hdC;
    for (var s = 0; s < 2; s++) {
      shoulder[s] = sh[s];
      elbow[s] = el[s];
      wrist[s] = wr[s];
      hipJ[s] = hj[s];
      knee[s] = kn[s];
      ankle[s] = an[s];
    }
    final anc = joint(anchor);
    final target = V3(p.atX, -p.atY, p.atZ.isNaN ? anc.z : p.atZ);
    final off = target - anc;
    hip = hip + off;
    neck = neck + off;
    head = head + off;
    for (var s = 0; s < 2; s++) {
      shoulder[s] = shoulder[s] + off;
      elbow[s] = elbow[s] + off;
      wrist[s] = wrist[s] + off;
      hipJ[s] = hipJ[s] + off;
      knee[s] = knee[s] + off;
      ankle[s] = ankle[s] + off;
    }
  }
}
