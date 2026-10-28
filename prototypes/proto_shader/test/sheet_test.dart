// Renders all contact-sheet cells as goldens (flutter test --update-goldens
// test/sheet_test.dart), then tool/compose_sheets.py stitches + labels them.
import 'package:flutter_test/flutter_test.dart';
import 'render_helpers.dart';

/// exercise id -> keyframe position (fractional = between keyframes).
const shots = <String, double>{
  'cal_front_lever': 0,
  'cal_strict_muscle_up': 2, // transition keyframe (chest over the bar)
  'cal_full_planche': 0,
  'cal_handstand': 0,
  'cal_pistol_squat': 1,
  'cal_jumping_jack': 1,
  'cal_human_flag': 0,
  'cal_tuck_front_lever': 0,
  'cal_negative_dip': 1,
  'cal_dead_hang': 0,
};
const yaws = [0.0, 35.0, 90.0];

/// Static cells looking along the sagittal plane (yaw >= 75) are rendered
/// from a little higher so the depth of levers / dips / flags still shows.
double pitchFor(double yaw) => yaw >= 75 ? 22 : 12;
const lightSet = ['cal_front_lever', 'cal_strict_muscle_up', 'cal_pistol_squat', 'cal_human_flag'];
const thumbSet = ['cal_front_lever', 'cal_full_planche', 'cal_handstand', 'cal_pistol_squat', 'cal_human_flag', 'cal_strict_muscle_up'];

void main() {
  final only = const String.fromEnvironment('ONLY');
  for (final e in shots.entries) {
    if (only.isNotEmpty && !only.split(',').contains(e.key)) continue;
    testWidgets('dark ${e.key}', (t) async {
      await preloadShader(t);
      final a = loadExercise(e.key);
      for (final y in yaws) {
        await renderCell(t, 'dark_${e.key}_${y.toInt()}', a, time: a.timeOfFrame(e.value), yaw: y, pitch: pitchFor(y));
      }
    });
  }
  for (final id in lightSet) {
    if (only.isNotEmpty && !only.split(',').contains(id)) continue;
    testWidgets('light $id', (t) async {
      await preloadShader(t);
      final a = loadExercise(id);
      for (final y in yaws) {
        await renderCell(t, 'light_${id}_${y.toInt()}', a, time: a.timeOfFrame(shots[id]!), yaw: y, pitch: pitchFor(y), bg: lightBg);
      }
    });
  }
  // animation phases (interpolation / easing / loop) at yaw 35
  for (final id in ['cal_strict_muscle_up', 'cal_jumping_jack']) {
    if (only.isNotEmpty && !only.split(',').contains(id)) continue;
    testWidgets('anim $id', (t) async {
      await preloadShader(t);
      final a = loadExercise(id);
      for (var i = 0; i < 8; i++) {
        await renderCell(t, 'anim_${id}_$i', a, time: a.periodSeconds * i / 8, yaw: 35, size: 200);
      }
    });
  }
  for (final id in thumbSet) {
    if (only.isNotEmpty && !only.split(',').contains(id)) continue;
    testWidgets('thumb $id', (t) async {
      await preloadShader(t);
      final a = loadExercise(id);
      // thumbnails: representative pose only, at the exercise's preferred yaw
      await renderCell(t, 'thumb_dark_$id', a, time: a.timeOfFrame(shots[id]!), yaw: null, size: 100, fitToPose: true);
      await renderCell(t, 'thumb_light_$id', a, time: a.timeOfFrame(shots[id]!), yaw: null, size: 100, bg: lightBg, fitToPose: true);
    });
  }
}
