import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _P extends CustomPainter {
  final ui.FragmentShader s;
  _P(this.s);
  @override
  void paint(Canvas c, Size size) {
    s.setFloat(0, size.width);
    s.setFloat(1, size.height);
    s.setFloat(2, 0); s.setFloat(3, 0); s.setFloat(4, 0.5); s.setFloat(5, 1);
    s.setFloat(6, 0); s.setFloat(7, 0); s.setFloat(8, 0.2); s.setFloat(9, 0);
    c.drawRect(Offset.zero & size, Paint()..shader = s);
  }
  @override
  bool shouldRepaint(covariant CustomPainter o) => true;
}

void main() {
  testWidgets('trivial shader', (t) async {
    t.view.physicalSize = const Size(200, 200);
    t.view.devicePixelRatio = 1;
    late ui.FragmentProgram prog;
    await t.runAsync(() async {
      prog = await ui.FragmentProgram.fromAsset('shaders/trivial.frag');
    });
    await t.pumpWidget(RepaintBoundary(child: CustomPaint(painter: _P(prog.fragmentShader()), size: const Size(200, 200))));
    await expectLater(find.byType(RepaintBoundary).first, matchesGoldenFile('goldens/trivial.png'));
  });
}
