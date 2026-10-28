// Measures raymarch cost: renders the debug shader variant and reports
// average march steps per pixel (all pixels / marched pixels).
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mannequin_proto/mannequin/mannequin_scene.dart';
import 'render_helpers.dart';

void main() {
  final quality = MannequinQuality.values.byName(String.fromEnvironment('QUALITY', defaultValue: 'medium'));
  testWidgets('cost (${quality.name})', (t) async {
    late ui.FragmentProgram prog;
    await t.runAsync(() async => prog = await ui.FragmentProgram.fromAsset('shaders/mannequin_debug.frag'));
    const size = 320.0;
    final ids = ['cal_front_lever', 'cal_strict_muscle_up', 'cal_full_planche', 'cal_handstand', 'cal_pistol_squat',
      'cal_jumping_jack', 'cal_human_flag', 'cal_tuck_front_lever', 'cal_negative_dip', 'cal_dead_hang'];
    for (final id in ids) {
      for (final yaw in [0.0, 35.0, 90.0]) {
        final a = loadExercise(id);
        final scene = MannequinScene(a)..fit(yaw, 12, 1)..pose(0);
        final sh = prog.fragmentShader();
        scene.writeUniforms(sh, size, size, 1, darkBg, quality);
        final rec = ui.PictureRecorder();
        Canvas(rec).drawRect(const Rect.fromLTWH(0, 0, size, size), Paint()..shader = sh);
        final pic = rec.endRecording();
        ByteData? bd;
        await t.runAsync(() async {
          final img = await pic.toImage(size.toInt(), size.toInt());
          bd = await img.toByteData();
        });
        final px = bd!.buffer.asUint8List();
        var sum = 0.0, marched = 0, hit = 0;
        for (var i = 0; i < px.length; i += 4) {
          final steps = px[i] / 255 * 80;
          sum += steps;
          if (px[i + 2] > 127) marched++;
          if (px[i + 1] > 127) hit++;
        }
        final n = px.length / 4;
        // ignore: avoid_print
        print('$id yaw $yaw: avg steps/pixel ${(sum / n).toStringAsFixed(1)}, '
            'marched ${(100 * marched / n).toStringAsFixed(0)}% (avg ${(sum / (marched == 0 ? 1 : marched)).toStringAsFixed(1)} steps), '
            'body ${(100 * hit / n).toStringAsFixed(0)}%');
      }
    }
  });
}
