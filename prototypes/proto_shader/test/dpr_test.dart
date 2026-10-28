// Verifies both paint paths at devicePixelRatio > 1:
//  - direct (resolutionScale 1): shader runs per physical pixel, local coords
//  - reduced (auto scale): offscreen toImageSync + bilinear upscale
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mannequin_proto/mannequin/mannequin_view.dart';
import 'render_helpers.dart';

void main() {
  for (final scale in <double?>[1.0, null]) {
    testWidgets('dpr 2.5 scale $scale', (t) async {
      await preloadShader(t);
      final a = loadExercise('cal_handstand');
      t.view.physicalSize = const Size(400, 400);
      t.view.devicePixelRatio = 2.5;
      final key = GlobalKey();
      await t.pumpWidget(MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 2.5),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 160,
                height: 160,
                child: Mannequin3DView(animation: a, fixedTime: 0, background: darkBg, resolutionScale: scale),
              ),
            ),
          ),
        ),
      ));
      await expectLater(find.byKey(key), matchesGoldenFile('goldens/cells/dpr_${scale == null ? 'auto' : 'full'}.png'));
    });
  }

  // Static cached thumbnail widget (lists): the shader runs once, then it is a plain image.
  testWidgets('MannequinSnapshot at dpr 2', (t) async {
    await preloadShader(t);
    final a = loadExercise('cal_full_planche');
    t.view.physicalSize = const Size(240, 240);
    t.view.devicePixelRatio = 2;
    final key = GlobalKey();
    await t.pumpWidget(MediaQuery(
      data: const MediaQueryData(devicePixelRatio: 2),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox(width: 100, height: 100, child: MannequinSnapshot(animation: a, background: darkBg)),
          ),
        ),
      ),
    ));
    await expectLater(find.byKey(key), matchesGoldenFile('goldens/cells/snapshot_planche.png'));
  });
}
