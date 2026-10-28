// Pose-data / interpolation regression tests (pure Dart, no rendering).
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mannequin_proto/mannequin/exercise_animation.dart';
import 'package:mannequin_proto/mannequin/rig.dart';

void main() {
  final all = (jsonDecode(File('assets/exercises.json').readAsStringSync()) as Map<String, dynamic>)
      .map((k, v) => MapEntry(k, ExerciseAnimation.fromJson((v as Map).cast<String, dynamic>())));

  double wrap(double d) {
    var x = d % 360.0;
    if (x > 180) x -= 360;
    return x;
  }

  test('no channel moves >= 150 deg unless a joint range decides the direction', () {
    final bad = <String>[];
    all.forEach((id, a) {
      for (final m in a.describeTransitions()) {
        final rangeResolved = !m.ambiguous && _hasRange(m.channel);
        if (!rangeResolved && m.delta.abs() >= 150) bad.add('$id $m');
      }
    });
    expect(bad, isEmpty);
  });

  test('sampled poses are continuous over a whole loop (incl. wrap / pingpong turn)', () {
    final angles = Float64List(PoseChannel.count), prev = Float64List(PoseChannel.count);
    final at = Float64List(3);
    final bad = <String>[];
    all.forEach((id, a) {
      const steps = 600;
      final dt = a.periodSeconds / steps;
      a.sample(0, prev, at);
      for (var i = 1; i <= steps + 1; i++) {
        a.sample(i * dt, angles, at);
        for (var c = 0; c < PoseChannel.count; c++) {
          // max speed: 180 deg per transition with ease (peak pi/2 x mean)
          final limit = 180 * math.pi / 2 / steps * a.transitionCount + 0.5;
          if (wrap(angles[c] - prev[c]).abs() > limit) {
            bad.add('$id t=${(i * dt).toStringAsFixed(2)} ${PoseChannel.names[c]} jumps ${wrap(angles[c] - prev[c]).toStringAsFixed(1)}');
            break;
          }
        }
        prev.setAll(0, angles);
      }
    });
    expect(bad, isEmpty);
  });

  test('muscle-up: arms swing forward (never back over the head) during the whole loop', () {
    final a = all['cal_strict_muscle_up']!;
    final angles = Float64List(PoseChannel.count), at = Float64List(3);
    for (var i = 0; i <= 400; i++) {
      a.sample(a.periodSeconds * i / 400, angles, at);
      final flex = ExerciseAnimation.jointAngle(angles, PoseChannel.ua1);
      expect(flex, inInclusiveRange(-60, 190), reason: 'shoulder flexion at sample $i');
      final elbow = ExerciseAnimation.jointAngle(angles, PoseChannel.la1);
      expect(elbow, inInclusiveRange(-5, 160), reason: 'elbow flexion at sample $i');
    }
  });

  MannequinRig solve(String id, double frame) {
    final a = all[id]!;
    final rig = MannequinRig(SceneProps.from(a.props));
    final angles = Float64List(PoseChannel.count), at = Float64List(3);
    a.sample(a.timeOfFrame(frame), angles, at);
    rig.solve(angles, a.anchor, at);
    return rig;
  }

  test('muscle-up transition keyframe: chest over the bar', () {
    final r = solve('cal_strict_muscle_up', 2);
    final p = r.props;
    final above = r.neck.y - p.barY;
    expect(above, inInclusiveRange(4, 10), reason: 'shoulders a few units above the bar');
    // bar in front of the torso axis (chest side), not inside the chest
    final fx = (p.barX - r.neck.x) * r.F.x + (p.barY - r.neck.y) * r.F.y;
    expect(fx, greaterThan(5.0));
  });

  test('tuck front lever: knees over the chest, feet above the back line', () {
    final r = solve('cal_tuck_front_lever', 0);
    for (final k in [J.kn1, J.kn2]) {
      final kn = r.joints[k];
      expect(kn.y, greaterThan(r.hip.y + 6), reason: 'knee above the torso');
      // knee between hip and neck along the body (toward the head)
      final along = (kn.x - r.hip.x) * r.T.x + (kn.y - r.hip.y) * r.T.y;
      expect(along, greaterThan(6));
    }
    for (final k in [J.an1, J.an2]) {
      expect(r.joints[k].y, greaterThan(r.hip.y + 2), reason: 'feet above the back line');
    }
  });

  test('muscle-up transition: hips flexed (strict turnover, not a plank)', () {
    final a = all['cal_strict_muscle_up']!;
    final angles = Float64List(PoseChannel.count), at = Float64List(3);
    a.sample(a.timeOfFrame(2), angles, at);
    final hip = ExerciseAnimation.jointAngle(angles, PoseChannel.th1);
    expect(hip, inInclusiveRange(40, 65), reason: 'hip flexion');
    final r = solve('cal_strict_muscle_up', 2);
    // feet slightly in front of (under) the bar side, not swept behind
    expect(r.joints[J.an1].x, greaterThan(r.hip.x - 2));
  });

  test('full planche: shoulders well in front of the hands', () {
    final r = solve('cal_full_planche', 0);
    const armLen = MannequinRig.uaLen + MannequinRig.laLen;
    for (final (sh, wr) in [(J.sh1, J.wr1), (J.sh2, J.wr2)]) {
      final dx = r.joints[sh].x - r.joints[wr].x;
      expect(dx, greaterThan(0.5 * armLen), reason: 'horizontal shoulder-to-wrist offset');
    }
    // body horizontal: hips level with the shoulders
    expect((r.hip.y - r.neck.y).abs(), lessThan(3));
  });

  test('front levers: the bar is between shoulders and hips', () {
    for (final id in ['cal_front_lever', 'cal_tuck_front_lever']) {
      final r = solve(id, 0);
      final bx = r.props.barX;
      final lo = math.min(r.neck.x, r.hip.x), hi = math.max(r.neck.x, r.hip.x);
      expect(bx, inExclusiveRange(lo, hi), reason: id);
      // arms tilted toward the hips (12-18 deg from vertical)
      final sh = r.joints[J.sh1], wr = r.joints[J.wr1];
      final tilt = math.atan2((wr.x - sh.x).abs(), wr.y - sh.y) * 180 / math.pi;
      expect(tilt, inInclusiveRange(12, 18), reason: id);
    }
  });

  test('pistol bottom: hip below the support knee', () {
    final r = solve('cal_pistol_squat', 1);
    expect(r.hip.y, lessThan(r.joints[J.kn1].y - 1));
  });
}

bool _hasRange(int c) =>
    c == PoseChannel.hd || (c >= PoseChannel.ua1 && c <= PoseChannel.sh2);
