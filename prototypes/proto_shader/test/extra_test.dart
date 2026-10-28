// Extra verification renders (not on the contact sheets): other fixed poses,
// close-ups of hands / feet / joints, quality tiers. Writes goldens/cells/extra_*.png.
import 'package:flutter_test/flutter_test.dart';
import 'package:mannequin_proto/mannequin/mannequin_scene.dart';
import 'render_helpers.dart';

void main() {
  final only = const String.fromEnvironment('ONLY');
  final shots = <String, (String, double, double?, double, bool)>{
    // name: (exercise, keyframe, yaw, pitch, fitToPose)
    'tuck_flag_20': ('cal_tuck_human_flag', 0, 20, 12, false),
    'adv_tuck_fl_35': ('cal_adv_tuck_front_lever', 0, 35, 12, false),
    'neg_mu_trans_35': ('cal_negative_muscle_up', 1, 35, 12, false),
    'sb_dip_35': ('cal_straight_bar_dip', 1, 35, 12, false),
    'mu_trans_60': ('cal_strict_muscle_up', 2, 60, 12, true),
    'deadhang_front': ('cal_dead_hang', 0, 90, 5, true),
    'jj_front_close': ('cal_jumping_jack', 0, 90, 5, true),
    'pistol_close': ('cal_pistol_squat', 1, 55, 12, true),
    'planche_close': ('cal_full_planche', 0, 30, 18, true),
    'handstand_close': ('cal_handstand', 0, 40, 10, true),
    'dip_close': ('cal_negative_dip', 1, 40, 12, true),
    'tuck_fl_close': ('cal_tuck_front_lever', 0, 20, 12, true),
    'flag_close': ('cal_human_flag', 0, 15, 8, true),
    'burpee_plank': ('cal_burpee', 2, 30, 12, false),
  };
  for (final e in shots.entries) {
    if (only.isNotEmpty && !only.split(',').any((o) => e.key.contains(o))) continue;
    testWidgets('extra ${e.key}', (t) async {
      await preloadShader(t);
      final (id, frame, yaw, pitch, fit) = e.value;
      final a = loadExercise(id);
      await renderCell(t, 'extra_${e.key}', a, time: a.timeOfFrame(frame), yaw: yaw, pitch: pitch, size: 480, fitToPose: fit,
          quality: MannequinQuality.high);
    });
  }
}
