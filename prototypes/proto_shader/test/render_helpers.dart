import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mannequin_proto/mannequin/exercise_animation.dart';
import 'package:mannequin_proto/mannequin/mannequin_scene.dart';
import 'package:mannequin_proto/mannequin/mannequin_view.dart';

const darkBg = Color(0xFF121212);
const lightBg = Color(0xFFF5F5F5);

Map<String, dynamic>? _fixture;
ExerciseAnimation loadExercise(String id) {
  _fixture ??= jsonDecode(File('assets/exercises.json').readAsStringSync()) as Map<String, dynamic>;
  return ExerciseAnimation.fromJson((_fixture![id] as Map).cast<String, dynamic>());
}

Future<void> preloadShader(WidgetTester t) async {
  await t.runAsync(() => MannequinShader.load());
}

/// Renders one cell and writes it as golden `goldens/cells/<name>.png`.
Future<void> renderCell(WidgetTester t, String name, ExerciseAnimation anim,
    {required double time,
    required double? yaw,
    double pitch = 12,
    Color bg = darkBg,
    double size = 320,
    bool fitToPose = false,
    MannequinQuality quality = MannequinQuality.medium}) async {
  t.view.physicalSize = Size(size, size);
  t.view.devicePixelRatio = 1;
  final key = GlobalKey();
  await t.pumpWidget(Directionality(
    textDirection: TextDirection.ltr,
    child: RepaintBoundary(
      key: key,
      child: SizedBox(
        width: size,
        height: size,
        child: Mannequin3DView(
          key: ValueKey(name),
          animation: anim,
          fixedTime: time,
          initialYaw: yaw ?? 30,
          usePreferredYaw: yaw == null,
          initialPitch: pitch,
          background: bg,
          interactive: false,
          resolutionScale: 1,
          fitToPose: fitToPose,
          quality: quality,
        ),
      ),
    ),
  ));
  await expectLater(find.byKey(key), matchesGoldenFile('goldens/cells/$name.png'));
}
