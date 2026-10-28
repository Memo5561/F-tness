import 'dart:math' as math;
import 'dart:ui';

import 'math3d.dart';

/// Orbit camera. yaw: rotation about the vertical axis (0 = side view like the
/// 2D data, +90 = looking at the figure's front from +x). pitch: elevation
/// (positive = looking down from above). View space: x right, y up, z toward
/// the viewer (larger z = nearer).
class ViewCam {
  double yawDeg = 30, pitchDeg = 12;
  V3 pivot = V3.zero;

  /// Pixels per world unit (before perspective).
  double k = 1;

  /// Screen position of the pivot.
  double ox = 0, oy = 0;

  /// Perspective camera distance in world units (0 = orthographic).
  double persp = 0;

  double _cy = 1, _sy = 0, _cp = 1, _sp = 0;

  void setAngles(double yaw, double pitch) {
    yawDeg = yaw;
    pitchDeg = pitch;
    final y = yaw * deg2rad, p = pitch * deg2rad;
    _cy = math.cos(y);
    _sy = math.sin(y);
    _cp = math.cos(p);
    _sp = math.sin(p);
  }

  /// Rotation only (world direction -> view direction).
  V3 rot(V3 v) {
    final x1 = v.x * _cy - v.z * _sy;
    final z1 = v.x * _sy + v.z * _cy;
    return V3(x1, v.y * _cp - z1 * _sp, v.y * _sp + z1 * _cp);
  }

  /// Inverse rotation (view direction -> world direction).
  V3 rotInv(V3 v) {
    final y1 = v.y * _cp + v.z * _sp;
    final z1 = -v.y * _sp + v.z * _cp;
    return V3(v.x * _cy + z1 * _sy, y1, -v.x * _sy + z1 * _cy);
  }

  V3 toView(V3 p) => rot(p - pivot);

  double persFactor(double zv) =>
      persp <= 0 ? 1.0 : persp / math.max(persp * 0.2, persp - zv);

  double pxScale(double zv) => k * persFactor(zv);

  Offset toScreen(V3 v) {
    final s = k * persFactor(v.z);
    return Offset(ox + v.x * s, oy - v.y * s);
  }

  /// Auto-fit: points (world) with radii; fills [fill] of the viewport.
  void fit(List<V3> pts, List<double> radii, Size size, {double fill = 0.85}) {
    var minX = double.infinity, maxX = -double.infinity;
    var minY = double.infinity, maxY = -double.infinity;
    for (var i = 0; i < pts.length; i++) {
      final v = toView(pts[i]);
      final f = persFactor(v.z);
      final r = radii[i];
      final x0 = (v.x - r) * f, x1 = (v.x + r) * f;
      final y0 = (v.y - r) * f, y1 = (v.y + r) * f;
      if (x0 < minX) minX = x0;
      if (x1 > maxX) maxX = x1;
      if (y0 < minY) minY = y0;
      if (y1 > maxY) maxY = y1;
    }
    if (!minX.isFinite) {
      k = 1;
      ox = size.width / 2;
      oy = size.height / 2;
      return;
    }
    final bw = math.max(1e-3, maxX - minX), bh = math.max(1e-3, maxY - minY);
    k = fill * math.min(size.width / bw, size.height / bh);
    ox = size.width / 2 - k * (minX + maxX) / 2;
    oy = size.height / 2 + k * (minY + maxY) / 2;
  }
}
