import 'package:flutter_test/flutter_test.dart';
import 'render_helpers.dart';

void main() {
  testWidgets('hero', (t) async {
    await preloadShader(t);
    final ps = loadExercise('cal_pistol_squat');
    await renderCell(t, 'hero_pistol', ps, time: ps.timeOfFrame(1), yaw: 40, size: 640);
    final jj = loadExercise('cal_jumping_jack');
    await renderCell(t, 'hero_jj', jj, time: 0, yaw: 60, size: 640);
    final pl = loadExercise('cal_full_planche');
    await renderCell(t, 'hero_planche', pl, time: 0, yaw: 25, pitch: 20, size: 640, bg: lightBg);
    final fl = loadExercise('cal_human_flag');
    await renderCell(t, 'hero_flag', fl, time: 0, yaw: 20, size: 640);
  });
}
