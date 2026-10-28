// Drag behaviour of Mannequin3DView: per-yaw framing at rest, yaw-invariant
// framing while dragging (no zoom during the rotation), snap out of the
// end-on yaw window for horizontal bodies, preferred default yaw, and
// vertical drags inside a scrollable page still scroll the page.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mannequin_proto/mannequin/mannequin_view.dart';
import 'render_helpers.dart';

void main() {
  MannequinPainter painterOf(WidgetTester t) =>
      t.widget<CustomPaint>(find.descendant(of: find.byType(Mannequin3DView), matching: find.byType(CustomPaint))).painter!
          as MannequinPainter;

  Future<void> pumpView(WidgetTester t, String id, {bool preferred = false}) async {
    await preloadShader(t);
    t.view.physicalSize = const Size(320, 320);
    t.view.devicePixelRatio = 1;
    await t.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Mannequin3DView(
          animation: loadExercise(id), playing: false, background: darkBg, resolutionScale: 1, usePreferredYaw: preferred),
    ));
  }

  Future<void> settle(WidgetTester t, [int frames = 40]) async {
    for (var i = 0; i < frames; i++) {
      await t.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('horizontal body: preferred yaw 35, per-yaw framing at rest, constant framing while dragging, snap', (t) async {
    await pumpView(t, 'cal_front_lever', preferred: true);
    final p = painterOf(t);
    final s = p.scene;
    expect(p.state.yaw, 35);
    expect(s.isHorizontalBody, isTrue);
    // at rest: the per-yaw framing of yaw 35 (tighter than the yaw-invariant one)
    final rest = s.framingFor(35, 12, 1);
    final inv = s.invariantFraming(12, 1);
    expect(s.camera.distance, closeTo(rest[3], 1e-9));
    expect(rest[3], lessThan(inv[3] * 0.97));

    // touch + hold: blends to the yaw-invariant framing within ~0.25 s
    final g = await t.startGesture(const Offset(160, 160));
    await g.moveBy(const Offset(1, 0));
    await settle(t, 20);
    expect(p.state.frameBlend, 1.0);
    final d0 = s.camera.distance;
    final target0 = s.camera.target.toString();
    expect(d0, closeTo(inv[3], 1e-9));

    // drag right by 100 px -> yaw ~95 (inside the 72..108 window), plus tilt:
    // distance and target stay bit-identical during the rotation
    for (var i = 0; i < 10; i++) {
      await g.moveBy(const Offset(10, 3));
      await t.pump(const Duration(milliseconds: 16));
      expect(s.camera.distance, d0, reason: 'no zoom during drag (step $i)');
      expect(s.camera.target.toString(), target0);
    }
    expect(p.state.yaw, greaterThan(72));
    expect(p.state.yaw, lessThan(108));
    final pitchAfterDrag = p.state.pitch;
    await g.up();
    await settle(t);
    final m = p.state.yaw % 180;
    expect(m <= 72.001 || m >= 107.999, isTrue, reason: 'yaw ${p.state.yaw} should leave the end-on window');
    // framing eased back to the per-yaw fit of the final yaw / pitch
    expect(p.state.fitPitch, closeTo(pitchAfterDrag, 1e-6));
    expect(p.state.frameBlend, 0.0);
    final fin = s.framingFor(p.state.yaw, p.state.pitch, 1);
    expect(s.camera.distance, closeTo(fin[3], 1e-6));
  });

  testWidgets('tucked lever counts as a horizontal body', (t) async {
    await pumpView(t, 'cal_tuck_front_lever', preferred: true);
    final p = painterOf(t);
    expect(p.scene.isHorizontalBody, isTrue);
    expect(p.state.yaw, 35);
  });

  testWidgets('upright body: default initialYaw 30, no snap', (t) async {
    await pumpView(t, 'cal_dead_hang');
    final p = painterOf(t);
    expect(p.state.yaw, 30);
    expect(p.scene.isHorizontalBody, isFalse);
    final g = await t.startGesture(const Offset(160, 160));
    for (var i = 0; i < 10; i++) {
      await g.moveBy(const Offset(10, 0));
      await t.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await settle(t, 30);
    expect(p.state.yaw, closeTo(90, 1e-6));
  });

  testWidgets('inside a vertical ListView: vertical drags scroll the page, horizontal drags rotate', (t) async {
    await preloadShader(t);
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    final ctrl = ScrollController();
    await t.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: ListView(
        controller: ctrl,
        children: [
          const SizedBox(height: 100),
          SizedBox(
            height: 300,
            child: Mannequin3DView(
                animation: loadExercise('cal_handstand'), playing: false, background: darkBg, resolutionScale: 1),
          ),
          const SizedBox(height: 900),
        ],
      ),
    ));
    final p = painterOf(t);
    final yaw0 = p.state.yaw, pitch0 = p.state.pitch;
    await t.timedDrag(find.byType(Mannequin3DView), const Offset(0, -150), const Duration(milliseconds: 300));
    await settle(t, 10);
    expect(ctrl.offset, greaterThan(100), reason: 'the page scrolled');
    expect(p.state.yaw, yaw0);
    expect(p.state.pitch, pitch0);

    await settle(t, 120); // let the fling come to rest
    final off = ctrl.offset;
    await t.timedDrag(find.byType(Mannequin3DView), const Offset(120, 6), const Duration(milliseconds: 300));
    await settle(t, 30);
    expect(ctrl.offset, off, reason: 'a horizontal drag does not scroll');
    expect(p.state.yaw, greaterThan(yaw0 + 30));
  });
}
