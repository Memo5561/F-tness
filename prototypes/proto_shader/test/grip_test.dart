// Gripping hands wrap their bar / pole: the fist is centred on the grip axis
// and its SDF (a Dart mirror of the fist branch of handD in
// shaders/mannequin.frag) encloses a ring just outside the cylinder for at
// least 270 degrees. Also checks that the drawn wrist sits outside the
// cylinder, [MannequinRig.gripOffset] back along the forearm.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mannequin_proto/mannequin/exercise_animation.dart';
import 'package:mannequin_proto/mannequin/rig.dart';

double _smin(double a, double b, double k) {
  final h = math.max(k - (a - b).abs(), 0.0) / k;
  return math.min(a, b) - h * h * k * 0.25;
}

double _len3(double x, double y, double z) => math.sqrt(x * x + y * y + z * z);

double _sdRBox(double qx, double qy, double qz, double bx, double by, double bz, double r) {
  final dx = qx.abs() - bx + r, dy = qy.abs() - by + r, dz = qz.abs() - bz + r;
  return _len3(math.max(dx, 0), math.max(dy, 0), math.max(dz, 0)) + math.min(math.max(dx, math.max(dy, dz)), 0.0) - r;
}

double _sdCap(List<double> p, List<double> a, List<double> b, double r) {
  final pa = [p[0] - a[0], p[1] - a[1], p[2] - a[2]], ba = [b[0] - a[0], b[1] - a[1], b[2] - a[2]];
  final h = ((pa[0] * ba[0] + pa[1] * ba[1] + pa[2] * ba[2]) / (ba[0] * ba[0] + ba[1] * ba[1] + ba[2] * ba[2])).clamp(0.0, 1.0);
  return _len3(pa[0] - ba[0] * h, pa[1] - ba[1] * h, pa[2] - ba[2] * h) - r;
}

double _smoothstep(double e0, double e1, double x) {
  final t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// Mirror of the fist branch of handD (hand frame coordinates).
double fistSdf(double qx, double qy, double qz, double ey, double rc, double side) {
  final rho = math.sqrt(qx * qx + qz * qz);
  final rwx = (rho - rc - 0.42).abs() - 0.12, rwy = qy.abs() - ey + 0.4;
  var cuff = math.min(math.max(rwx, rwy), 0.0) + math.sqrt(math.pow(math.max(rwx, 0), 2) + math.pow(math.max(rwy, 0), 2)) - 0.4;
  cuff += 0.07 * (1 - math.sin(qy * math.pi / (ey * 0.5)).abs()) * _smoothstep(rc + 0.2, rc + 0.9, rho);
  final back = _sdRBox(qx + rc + 0.45, qy, qz, 1.05, ey * 0.86, rc * 0.62 + 0.4, 0.62);
  var d = _smin(cuff, back, 0.8);
  final q = [qx, qy, qz];
  d = _smin(d, _sdCap(q, [-0.25, -0.72 * ey, rc + 0.55], [-0.25, 0.72 * ey, rc + 0.55], 0.62), 0.6);
  d = _smin(d, _sdCap(q, [-rc - 0.9, side * 0.85 * ey, -rc * 0.35], [-0.2, side * ey, -rc - 0.55], 0.5), 0.5);
  return d;
}

void main() {
  final all = (jsonDecode(File('assets/exercises.json').readAsStringSync()) as Map<String, dynamic>)
      .map((k, v) => MapEntry(k, ExerciseAnimation.fromJson((v as Map).cast<String, dynamic>())));

  final cases = <String, double>{
    'cal_dead_hang': 0,
    'cal_front_lever': 0,
    'cal_tuck_front_lever': 0,
    'cal_strict_muscle_up': 2,
    'cal_human_flag': 0,
    'cal_negative_dip': 1,
  };
  for (final e in cases.entries) {
    test('${e.key}: both fists wrap the grip cylinder', () {
      final a = all[e.key]!;
      final rig = MannequinRig(SceneProps.from(a.props));
      final angles = Float64List(PoseChannel.count), at = Float64List(3);
      a.sample(a.timeOfFrame(e.value), angles, at);
      rig.solve(angles, a.anchor, at);
      for (final (h, wrId) in [(rig.hand1, J.wr1), (rig.hand2, J.wr2)]) {
        expect(h.code.abs(), 2, reason: 'fist');
        final rc = h.ext.z, ey = h.ext.y;
        expect(rc, inInclusiveRange(1.0, 1.5));
        // the real prop axis through the hand: the fist centre must lie on it
        final p = rig.props;
        final ax = <double>[0, 0, 0];
        if (p.hasBar && (h.c.x - p.barX).abs() + (h.c.y - p.barY).abs() < 1e-6) {
          ax[2] = 1;
        } else if (p.hasPole && (h.c.x - p.poleX).abs() + (h.c.z - p.poleZ).abs() < 1e-6) {
          ax[1] = 1;
        } else if (p.hasPbars && (h.c.y - p.pbY).abs() + (h.c.z.abs() - p.pbZ).abs() < 1e-6) {
          ax[0] = 1;
        } else {
          fail('${e.key}: fist centre ${h.c} is not on a grip axis');
        }
        expect(h.ay.x.abs() * ax[0] + h.ay.y.abs() * ax[1] + h.ay.z.abs() * ax[2], closeTo(1, 1e-9), reason: 'hand y = grip axis');
        // drawn wrist: gripOffset from the axis, outside the cylinder
        final wr = rig.joints[wrId];
        final wx = wr.x - h.c.x, wy = wr.y - h.c.y, wz = wr.z - h.c.z;
        final along = wx * h.ay.x + wy * h.ay.y + wz * h.ay.z;
        final radial = math.sqrt(math.max(0, wx * wx + wy * wy + wz * wz - along * along));
        expect(radial, closeTo(MannequinRig.gripOffset, 1e-6));
        expect(radial, greaterThan(rc + 0.6));
        // ring of radius rc + 0.2 around the axis, at three positions across the hand
        for (final y in [0.0, 0.6 * ey, -0.6 * ey]) {
          var inside = 0;
          const n = 72;
          for (var i = 0; i < n; i++) {
            final ang = 2 * math.pi * i / n;
            final qx = (rc + 0.2) * math.cos(ang), qz = (rc + 0.2) * math.sin(ang);
            if (fistSdf(qx, y, qz, ey, rc, h.code.sign) < 0) inside++;
          }
          expect(inside * 360 / n, greaterThanOrEqualTo(270), reason: '${e.key} ring at y=$y');
        }
      }
    });
  }
}
