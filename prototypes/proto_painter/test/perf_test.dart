import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:mannequin_proto/mannequin/exercise_animation.dart';
import 'package:mannequin_proto/mannequin/mannequin_renderer.dart';
import 'package:mannequin_proto/mannequin/mannequin_view.dart';
import 'package:mannequin_proto/mannequin/style.dart';

/// Measures the UI-thread (Dart) cost of one animation frame: pose sampling,
/// FK, building primitives, pairwise sort and recording the canvas commands.
/// (Raster cost is GPU-side and not measured here.)
void main() {
  test('paint cost per frame', () {
    final list = jsonDecode(File('assets/exercises.json').readAsStringSync()) as List;
    final ids = ['cal_front_lever', 'cal_strict_muscle_up', 'cal_negative_dip', 'cal_pistol_squat', 'cal_human_flag'];
    for (final id in ids) {
      final e = list.firstWhere((x) => x['id'] == id) as Map;
      final anim = ExerciseAnimation.fromJson(e.cast<String, dynamic>());
      final fit = MannequinFitData(anim);
      final renderer = MannequinRenderer();
      final style = MannequinStyle.dark();
      const size = ui.Size(400, 400);
      // warm-up
      for (var i = 0; i < 200; i++) {
        _frame(anim, fit, renderer, style, size, i / 60.0, 30 + i * 0.5);
      }
      const n = 600;
      final sw = Stopwatch()..start();
      for (var i = 0; i < n; i++) {
        _frame(anim, fit, renderer, style, size, i / 60.0, 30 + i * 0.5);
      }
      sw.stop();
      final us = sw.elapsedMicroseconds / n;
      // ignore: avoid_print
      print('$id: ${us.toStringAsFixed(0)} us/frame (JIT, desktop)');
    }
  });
}

void _frame(ExerciseAnimation anim, MannequinFitData fit, MannequinRenderer r,
    MannequinStyle style, ui.Size size, double t, double yaw) {
  final rec = ui.PictureRecorder();
  final canvas = ui.Canvas(rec);
  final p = MannequinPainter(
      animation: anim, fit: fit, renderer: r, yaw: yaw, pitch: 12, style: style, fixedTime: t);
  p.paint(canvas, size);
  rec.endRecording().dispose();
}
