import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mannequin_proto/mannequin/exercise_animation.dart';
import 'package:mannequin_proto/mannequin/mannequin_view.dart';

const dark = Color(0xFF121212);
const light = Color(0xFFF5F5F5);

Map<String, ExerciseAnimation> loadAll() {
  final list = jsonDecode(File('assets/exercises.json').readAsStringSync()) as List;
  return {
    for (final e in list)
      (e as Map)['id'] as String:
          ExerciseAnimation.fromJson(e.cast<String, dynamic>())
  };
}

/// Required exercises with the time to render (seconds).
List<(String, double)> required(Map<String, ExerciseAnimation> a) => [
      ('cal_front_lever', 0),
      // transition (turnover): chest crossing the bar, elbows above it
      ('cal_strict_muscle_up', a['cal_strict_muscle_up']!.timeAtFrame(2)),
      ('cal_full_planche', 0),
      ('cal_handstand', 0),
      ('cal_pistol_squat', a['cal_pistol_squat']!.timeAtFrame(1)),
      ('cal_jumping_jack', a['cal_jumping_jack']!.timeAtFrame(1)),
      ('cal_human_flag', 0),
      ('cal_tuck_front_lever', 0),
      ('cal_negative_dip', a['cal_negative_dip']!.timeAtFrame(1)),
      ('cal_dead_hang', 0),
    ];

const yaws = [0.0, 35.0, 90.0];

Widget cell(ExerciseAnimation anim, double t, double yaw, Color bg, double size) =>
    SizedBox(
      width: size,
      height: size,
      child: ColoredBox(
        color: bg,
        child: Mannequin3DView(
          animation: anim,
          fixedTime: t,
          initialYaw: yaw,
          interactive: false,
          background: bg,
        ),
      ),
    );

Widget sheet(Map<String, ExerciseAnimation> all, List<(String, double)> items,
    Color bg, {int perRow = 2, double size = 320, List<double> yaws = yaws}) {
  final rows = <Widget>[];
  for (var i = 0; i < items.length; i += perRow) {
    final children = <Widget>[];
    for (var j = i; j < i + perRow && j < items.length; j++) {
      final (id, t) = items[j];
      for (final y in yaws) {
        children.add(cell(all[id]!, t, y, bg, size));
      }
      if (j + 1 < i + perRow) children.add(Container(width: 4, height: size, color: const Color(0xFF555555)));
    }
    rows.add(Row(mainAxisSize: MainAxisSize.min, children: children));
    rows.add(Container(height: 4, color: const Color(0xFF555555)));
  }
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Align(
      alignment: Alignment.topLeft,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: rows),
    ),
  );
}

Future<void> shoot(WidgetTester tester, Widget w, Size size, String file,
    {double dpr = 1}) async {
  tester.view.physicalSize = size * dpr;
  tester.view.devicePixelRatio = dpr;
  final key = GlobalKey();
  await tester.pumpWidget(RepaintBoundary(key: key, child: w));
  await tester.pump();
  await expectLater(find.byKey(key), matchesGoldenFile(file));
}

void main() {
  final all = loadAll();
  final req = required(all);
  final only = Platform.environment['ONLY'];

  testWidgets('sheet dark', (tester) async {
    if (only != null && only != 'dark') return;
    final rows = (req.length / 2).ceil();
    await shoot(tester, sheet(all, req, dark), Size(6 * 320 + 4.0, rows * 324.0),
        '../out/sheet_dark.png');
  });

  testWidgets('sheet light', (tester) async {
    if (only != null && only != 'light') return;
    final pick = [req[0], req[2], req[4], req[6]];
    await shoot(tester, sheet(all, pick, light), Size(6 * 320 + 4.0, 2 * 324.0),
        '../out/sheet_light.png');
  });

  testWidgets('strips', (tester) async {
    if (only != null && only != 'strips') return;
    for (final (id, t) in req) {
      await shoot(tester, sheet(all, [(id, t)], dark, perRow: 1),
          const Size(3 * 320.0, 324), '../out/strips/$id.png');
    }
  });

  testWidgets('hires', (tester) async {
    if (only != 'hires') return;
    final ids = (Platform.environment['IDS'] ?? 'cal_front_lever').split(',');
    for (final id in ids) {
      final t = req.firstWhere((e) => e.$1 == id).$2;
      await shoot(tester, sheet(all, [(id, t)], dark, perRow: 1, size: 800),
          const Size(3 * 800.0, 804), '../out/hires/$id.png');
    }
  });

  testWidgets('thumbs', (tester) async {
    if (only != null && only != 'thumbs') return;
    final pick = [req[0], req[1], req[2], req[4], req[5], req[6]];
    Widget row(Color bg) => Row(mainAxisSize: MainAxisSize.min, children: [
          for (final (id, t) in pick)
            SizedBox(
              width: 100,
              height: 100,
              child: Mannequin3DView(
                  animation: all[id]!,
                  fixedTime: t,
                  initialYaw: all[id]!.initialYaw,
                  interactive: false,
                  background: bg,
                  fitMode: FitMode.pose),
            ),
        ]);
    await shoot(
        tester,
        Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
                alignment: Alignment.topLeft,
                child: Column(mainAxisSize: MainAxisSize.min, children: [row(dark), row(light)]))),
        const Size(600, 200),
        '../out/thumb_100px.png');
  });
}
