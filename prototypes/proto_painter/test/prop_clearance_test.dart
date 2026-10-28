import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mannequin_proto/mannequin/exercise_animation.dart';
import 'package:mannequin_proto/mannequin/mannequin_renderer.dart';
import 'package:mannequin_proto/mannequin/math3d.dart';
import 'package:mannequin_proto/mannequin/scene_items.dart';

/// Normalised distance of [p] from ellipsoid [e] with every semi-axis
/// inflated by [infl] (>= 1: outside).
double _normDist(EllipsoidItem e, V3 p, double infl) {
  final d = p - e.c;
  var s = 0.0;
  for (final a in [e.a1, e.a2, e.a3]) {
    final l = a.length;
    final u = d.dot(a) / l;
    s += math.pow(u / (l + infl), 2);
  }
  return math.sqrt(s);
}

/// The 2D stick-figure data ignores body thickness. This checks, for every
/// exercise, every key frame and intermediate samples of every transition,
/// that no grip prop (bar, pole, parallel bars) passes through the chest,
/// waist, pelvis or head.
void main() {
  test('grip props never run through torso or head', () {
    final list = jsonDecode(File('assets/exercises.json').readAsStringSync()) as List;
    final failures = <String>[];
    var checked = 0;
    for (final e in list) {
      final anim = ExerciseAnimation.fromJson((e as Map).cast<String, dynamic>());
      final r = MannequinRenderer();
      r.setProps(anim.props, anim.floorY);
      if (r.grips.isEmpty) continue;
      final pose = Pose();
      final times = <double>[];
      for (var i = 0; i < anim.segmentCount; i++) {
        for (final u in const [0.0, 0.25, 0.5, 0.75]) {
          times.add((i + u) * anim.transitionSeconds);
        }
      }
      for (final t in times) {
        anim.sampleInto(t, pose);
        r.setPose(pose, anim.anchor);
        checked++;
        for (final g in r.grips) {
          final parts = [r.pelvis, r.abdomen, r.ribcage, r.chest, r.head];
          for (var k = 0; k < parts.length; k++) {
            final part = parts[k];
            var worst = double.infinity;
            const n = 200;
            for (var i = 0; i <= n; i++) {
              final p = V3.lerp(g.a, g.b, i / n);
              if (k < 4) {
                // torso pieces are cut where they meet their neighbours
                final d = p - r.skel.hip;
                if (!TorsoPart.keeps(k, d.dot(r.skel.tAxis), d.dot(r.skel.fwd), g.r + 0.2)) continue;
              }
              worst = math.min(worst, _normDist(part, p, g.r + 0.2));
            }
            if (worst < 1) {
              failures.add('${anim.id} t=${t.toStringAsFixed(2)} ${g.kind}~${part.name} '
                  '(${worst.toStringAsFixed(2)})');
            }
          }
        }
      }
    }
    expect(checked, greaterThan(50));
    expect(failures, isEmpty, reason: failures.take(20).join('\n'));
  });
}
