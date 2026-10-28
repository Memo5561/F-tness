import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mannequin_proto/mannequin/exercise_animation.dart';
import 'package:mannequin_proto/mannequin/mannequin_view.dart';

import 'render_sheets_test.dart' show loadAll, shoot, dark;

/// Regression golden for limbs pointing at the camera (no concentric
/// "telescope" rings, compact end-on hands/feet): pistol squat bottom
/// (arms and free leg forward) and front lever, both seen from the front.
void main() {
  testWidgets('end-on limbs golden', (tester) async {
    final all = loadAll();
    final pistol = all['cal_pistol_squat']!;
    final lever = all['cal_front_lever']!;
    Widget cell(ExerciseAnimation anim, double t, double yaw) => SizedBox(
          width: 400,
          height: 400,
          child: Mannequin3DView(
              animation: anim, fixedTime: t, initialYaw: yaw, interactive: false, background: dark),
        );
    await shoot(
        tester,
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              cell(pistol, pistol.timeAtFrame(1), 90),
              cell(pistol, pistol.timeAtFrame(1), 70),
              cell(lever, 0, 90),
            ]),
          ),
        ),
        const Size(1200, 400),
        'goldens/endon.png');
  });
}
