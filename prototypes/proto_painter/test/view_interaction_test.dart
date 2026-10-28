import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mannequin_proto/mannequin/camera.dart';
import 'package:mannequin_proto/mannequin/exercise_animation.dart';
import 'package:mannequin_proto/mannequin/mannequin_renderer.dart';
import 'package:mannequin_proto/mannequin/mannequin_view.dart';
import 'package:mannequin_proto/mannequin/math3d.dart';

void main() {
  ExerciseAnimation load(String id) {
    final list = jsonDecode(File('assets/exercises.json').readAsStringSync()) as List;
    return ExerciseAnimation.fromJson(
        (list.firstWhere((e) => e['id'] == id) as Map).cast<String, dynamic>());
  }

  testWidgets('plays and rotates with drag', (tester) async {
    final anim = load('cal_negative_dip');
    tester.view.physicalSize = const Size(400, 400);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Mannequin3DView(animation: anim, initialYaw: 0),
    ));
    // animation ticks
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    final painterFinder = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is MannequinPainter);
    expect(painterFinder, findsOneWidget);
    double yaw() => ((tester.widget(painterFinder) as CustomPaint).painter as MannequinPainter).yaw;
    double pitch() => ((tester.widget(painterFinder) as CustomPaint).painter as MannequinPainter).pitch;
    expect(yaw(), 0);
    await tester.drag(find.byType(Mannequin3DView), const Offset(100, 0));
    await tester.pump();
    expect(yaw(), greaterThan(20));
    await tester.drag(find.byType(Mannequin3DView), const Offset(0, 1000));
    await tester.pump();
    expect(pitch(), 60); // clamped
    // loop timing helpers
    expect(anim.duration, closeTo(2 * 1.5 / 0.45, 1e-9));
  });

  test('pose interpolation uses shortest angle path + ease', () {
    final a = ExerciseAnimation.fromJson({
      'anchor': 'hip',
      'loop': 'cycle',
      'speed': 1.0,
      'frames': [
        {'at': [0, 0], 'a': {'t': 350}},
        {'at': [10, 0], 'a': {'t': 10}},
      ],
      'props': [],
    });
    final p = Pose();
    a.sampleInto(a.timeAtFrame(0, 0.5), p);
    expect(p.a[PoseKeys.t] % 360, closeTo(0, 1e-9)); // via 360, not 180
    expect(p.atX, closeTo(5, 1e-9));
    a.sampleInto(a.timeAtFrame(0, 0.25), p);
    expect(p.atX, closeTo(10 * (0.25 * 0.25 * (3 - 0.5)), 1e-9)); // smoothstep
  });

  // Camera framing (FitMode.loop, the default): one scale per loop (no
  // rescaling between frames), never larger than a standing figure (k_ref),
  // continuous in yaw, frozen while dragging (it may only shrink to keep the
  // figure in view) and the displayed pose always inside the viewport.
  test('auto-fit: loop scale, k_ref clamp, drag freeze, pose in view', () {
    for (final id in ['cal_strict_muscle_up', 'cal_front_lever', 'cal_tuck_front_lever', 'cal_pistol_squat']) {
      final anim = load(id);
      final fit = MannequinFitData(anim);
      final r = MannequinRenderer()..setProps(anim.props, anim.floorY);
      final cam = ViewCam()
        ..pivot = fit.pivot
        ..persp = 9 * fit.radius;
      const size = Size(360, 640);
      final kRef = MannequinFitData.refScale(size, 0.84);
      final pts = <V3>[];
      final rad = <double>[];
      final pose = Pose();
      double kAt(double t, double yaw, FitMode mode, {double? from, double blend = 1}) {
        anim.sampleInto(t, pose);
        r.setPose(pose, anim.anchor);
        pts.clear();
        rad.clear();
        r.collectFitPoints(pts, rad);
        cam.setAngles(yaw, 12);
        fit.apply(cam, size, t, mode, 0.84, pts, rad, scaleFromYaw: from, scaleBlend: blend);
        // displayed pose inside the viewport
        for (var i = 0; i < pts.length; i++) {
          final s = cam.toScreen(cam.toView(pts[i]));
          final rp = rad[i] * cam.pxScale(cam.toView(pts[i]).z);
          expect(s.dx - rp, greaterThan(-1), reason: '$id t=$t yaw=$yaw');
          expect(s.dx + rp, lessThan(size.width + 1), reason: '$id t=$t yaw=$yaw');
          expect(s.dy - rp, greaterThan(-1), reason: '$id t=$t yaw=$yaw');
          expect(s.dy + rp, lessThan(size.height + 1), reason: '$id t=$t yaw=$yaw');
        }
        return cam.k;
      }

      for (final mode in [FitMode.loop, FitMode.follow, FitMode.pose]) {
        for (var yaw = 0.0; yaw < 360; yaw += 30) {
          expect(kAt(anim.duration * 0.37, yaw, mode), lessThanOrEqualTo(kRef * (1 + 1e-9)),
              reason: '$id $mode yaw=$yaw');
        }
      }
      // loop: no rescaling over time at a fixed yaw
      final kl = kAt(0, 30, FitMode.loop);
      for (var f = 1; f < 12; f++) {
        expect(kAt(anim.duration * f / 12, 30, FitMode.loop), closeTo(kl, kl * 1e-9));
      }
      // continuous in yaw (no pumping when the yaw changes slowly)
      var prev = kAt(0, 0, FitMode.loop);
      for (var yaw = 1.0; yaw <= 360; yaw += 1) {
        final k = kAt(0, yaw, FitMode.loop);
        expect((k - prev).abs() / prev, lessThan(0.02), reason: '$id yaw=$yaw');
        prev = k;
      }
      // dragging from yaw 30: never zooms in beyond the drag-start scale
      final k30 = kAt(0, 30, FitMode.loop);
      for (var yaw = 30.0; yaw <= 390; yaw += 5) {
        expect(kAt(0, yaw, FitMode.loop, from: 30, blend: 0), lessThanOrEqualTo(k30 * (1 + 1e-9)),
            reason: '$id drag yaw=$yaw');
      }
      // released: eases to the scale of the new yaw
      expect(kAt(0, 120, FitMode.loop, from: 30, blend: 1), closeTo(kAt(0, 120, FitMode.loop), 1e-9));
      // follow mode: smooth over time (60 fps)
      prev = kAt(0, 30, FitMode.follow);
      for (var f = 1; f < anim.duration * 60; f++) {
        final k = kAt(f / 60, 30, FitMode.follow);
        expect((k - prev).abs() / prev, lessThan(0.01), reason: '$id frame $f');
        prev = k;
      }
    }
  });

  testWidgets('drag freezes the zoom, release eases it', (tester) async {
    final anim = load('cal_front_lever');
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Mannequin3DView(animation: anim, initialYaw: 25, playing: false),
    ));
    final painterFinder = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is MannequinPainter);
    MannequinPainter painter() => (tester.widget(painterFinder) as CustomPaint).painter as MannequinPainter;
    expect(painter().scaleFromYaw, isNull);
    final g = await tester.startGesture(const Offset(180, 320));
    await g.moveBy(const Offset(40, 0));
    await tester.pump();
    await g.moveBy(const Offset(40, 0));
    await tester.pump();
    expect(painter().scaleFromYaw, isNotNull);
    expect(painter().scaleBlend, 0);
    await g.up();
    await tester.pump(); // the ease starts on the next frame
    await tester.pump(const Duration(milliseconds: 120));
    expect(painter().scaleBlend, inExclusiveRange(0, 1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(painter().scaleFromYaw, isNull);
  });
}
