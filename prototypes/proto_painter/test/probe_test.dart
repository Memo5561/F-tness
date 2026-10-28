import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mannequin_proto/mannequin/mannequin_renderer.dart';

import 'render_sheets_test.dart';

void main() {
  // Ad-hoc renders for inspection (tool/probe.sh); skipped unless PROBE is set.
  testWidgets('probe', (tester) async {
    if (Platform.environment['PROBE'] == null) return;
    final all = loadAll();
    MannequinRenderer.debugPrintOrder = Platform.environment['ORDER'] != null;
    MannequinRenderer.debugHide = (Platform.environment['HIDE'] ?? '').split(',').toSet();
    final spec = Platform.environment['PROBE'] ?? 'cal_strict_muscle_up@2';
    final items = <(String, double)>[];
    for (final p in spec.split(',')) {
      final parts = p.split('@');
      final a = all[parts[0]]!;
      items.add((parts[0], a.timeAtFrame(int.parse(parts[1].split('.')[0]), parts[1].contains('.') ? double.parse('0.${parts[1].split('.')[1]}') : 0)));
    }
    final bg = Platform.environment['BG'] == 'light' ? light : dark;
    final ys = (Platform.environment['YAWS'] ?? '0,35,90').split(',').map(double.parse).toList();
    await shoot(tester, sheet(all, items, bg, perRow: 1, size: 400, yaws: ys),
        Size(ys.length * 400.0, items.length * 404.0), '../out/probe.png');
  });
}
