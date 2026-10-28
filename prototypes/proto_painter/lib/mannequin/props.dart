import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'math3d.dart';
import 'render_items.dart';
import 'scene_items.dart';
import 'style.dart';

/// Cylinder piece of a prop (bar, upright, pole...). Flat cut ends; [discA] /
/// [discB] draw the end faces (real ends of the cylinder). Shaded with a
/// cached unit-space gradient drawn under a canvas transform (no per-piece
/// shader allocation).
class CylItem extends Item {
  V3 a = V3.zero, b = V3.zero;
  double r = 1;
  bool discA = false, discB = false;
  MatKind mat = MatKind.prop;

  /// Opacity (uprights fade out while they line up with the grip).
  double alpha = 1;

  /// Fraction along a -> b where the piece starts fading out into the
  /// background (fully gone at b); > 1 = no fade.
  double fadeFrom = 2;

  /// Overlap extension at interior cut ends (px) to hide AA seams.
  static const double seamPx = 0.6;

  CylItem(super.name);

  V3 _av = V3.zero, _bv = V3.zero;
  Offset _as = Offset.zero, _bs = Offset.zero;
  double _ar = 1, _br = 1;
  final ui.Path _p = ui.Path();
  final Float64List _m = Float64List(16);
  ui.Shader? _fadeShader;
  MannequinStyle? _fadeStyle;

  @override
  void prepare(RenderCtx ctx) {
    _av = ctx.cam.toView(a);
    _bv = ctx.cam.toView(b);
    _as = ctx.cam.toScreen(_av);
    _bs = ctx.cam.toScreen(_bv);
    _ar = r * ctx.cam.pxScale(_av.z);
    _br = r * ctx.cam.pxScale(_bv.z);
    depth = (_av.z + _bv.z) / 2;
    setCore(_av.x, _av.y, _av.z, _bv.x, _bv.y, _bv.z, r);
  }

  /// Screen-space bounds check (for culling pieces far outside the view).
  bool onScreen(ui.Size size) {
    final m = math.max(_ar, _br) + 2;
    final x0 = math.min(_as.dx, _bs.dx) - m, x1 = math.max(_as.dx, _bs.dx) + m;
    final y0 = math.min(_as.dy, _bs.dy) - m, y1 = math.max(_as.dy, _bs.dy) + m;
    return x1 >= 0 && y1 >= 0 && x0 <= size.width && y0 <= size.height;
  }

  @override
  double frontZ(double px, double py) {
    final dx = _bv.x - _av.x, dy = _bv.y - _av.y;
    final l2 = dx * dx + dy * dy;
    var t = l2 > 1e-12 ? ((px - _av.x) * dx + (py - _av.y) * dy) / l2 : 0.0;
    if (t < 0 || t > 1) return double.nan;
    final cx = _av.x + dx * t, cy = _av.y + dy * t;
    final cz = _av.z + (_bv.z - _av.z) * t;
    final q = r * r - (px - cx) * (px - cx) - (py - cy) * (py - cy);
    return q < 0 ? double.nan : cz + math.sqrt(q);
  }

  @override
  void paint(ui.Canvas c, RenderCtx ctx) {
    if (alpha <= 0.01) return;
    final d = (_bv - _av).unit;
    final dx = _bs.dx - _as.dx, dy = _bs.dy - _as.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    final paintA = alpha < 1 ? (alpha * 255).round() : 255;
    if (len > 0.25) {
      // local frame: x along the axis (0..1 = a..b), y across in units of the
      // mean radius; the piece is a trapezoid (perspective taper)
      final ux = dx / len, uy = dy / len;
      final rm = (_ar + _br) / 2;
      final m = _m;
      m.fillRange(0, 16, 0);
      m[0] = ux * len;
      m[1] = uy * len;
      m[4] = -uy * rm;
      m[5] = ux * rm;
      m[10] = 1;
      m[12] = _as.dx;
      m[13] = _as.dy;
      m[15] = 1;
      // translucent pieces must not overlap (double blending at the seams)
      final seam = alpha < 1 ? 0.0 : seamPx / len;
      final x0 = discA ? 0.0 : -seam, x1 = fadeFrom <= 1 || discB ? 1.0 : 1 + seam;
      final ya = _ar / rm, yb = _br / rm;
      _p
        ..reset()
        ..moveTo(x0, -ya)
        ..lineTo(x1, -yb)
        ..lineTo(x1, yb)
        ..lineTo(x0, ya)
        ..close();
      c.save();
      c.transform(m);
      ctx.fill.shader = ctx.cylShader(mat, d);
      ctx.fill.color = Color.fromARGB(paintA, 0, 0, 0);
      c.drawPath(_p, ctx.fill);
      if (fadeFrom <= 1) {
        // fade into the background toward b
        if (!identical(_fadeStyle, ctx.style) || _fadeShader == null) {
          _fadeStyle = ctx.style;
          final bg = ctx.style.background;
          _fadeShader = ui.Gradient.linear(Offset(fadeFrom, 0), const Offset(1, 0),
              [bg.withValues(alpha: 0), bg.withValues(alpha: 1)]);
        }
        ctx.fill.shader = _fadeShader;
        ctx.fill.color = const Color(0xFF000000);
        c.drawPath(_p, ctx.fill);
      }
      c.restore();
    }
    // end discs facing the viewer
    if (discA && -d.z > 0.02) _disc(c, ctx, _as, _ar, -d, paintA);
    if (discB && d.z > 0.02) _disc(c, ctx, _bs, _br, d, paintA);
  }

  void _disc(ui.Canvas c, RenderCtx ctx, Offset center, double rPx, V3 n, int paintA) {
    // ellipse: axis along the screen projection of n is foreshortened by |n.z|
    final sx = n.x, sy = -n.y;
    final l = math.sqrt(sx * sx + sy * sy);
    final ang = l > 1e-6 ? math.atan2(sy, sx) : 0.0;
    c.save();
    c.translate(center.dx, center.dy);
    c.rotate(ang);
    c.scale(rPx * n.z.abs(), rPx);
    ctx.fill.shader = null;
    final col = ctx.shade(mat, n.x, n.y, n.z);
    ctx.fill.color = col.withAlpha(paintA);
    c.drawCircle(Offset.zero, 1, ctx.fill);
    // machined end: darker bevel ring + soft highlight when facing the key
    ctx.drawDiscDetail(c, n, paintA / 255);
    c.restore();
  }
}

/// Axis-aligned (world) box prop.
class BoxItem extends Item {
  V3 lo = V3.zero, hi = V3.zero;
  BoxItem(super.name);

  final List<V3> _cv = List.filled(8, V3.zero);
  final List<Offset> _cs = List.filled(8, Offset.zero);
  V3 _center = V3.zero;
  final ui.Path _p = ui.Path();

  V3 _corner(int i) => V3(i & 1 == 0 ? lo.x : hi.x, i & 2 == 0 ? lo.y : hi.y,
      i & 4 == 0 ? lo.z : hi.z);

  @override
  void prepare(RenderCtx ctx) {
    var x0 = double.infinity, x1 = -double.infinity;
    var y0 = double.infinity, y1 = -double.infinity;
    for (var i = 0; i < 8; i++) {
      final v = ctx.cam.toView(_corner(i));
      _cv[i] = v;
      _cs[i] = ctx.cam.toScreen(v);
      x0 = math.min(x0, v.x);
      x1 = math.max(x1, v.x);
      y0 = math.min(y0, v.y);
      y1 = math.max(y1, v.y);
    }
    _center = ctx.cam.toView((lo + hi) * 0.5);
    depth = _center.z;
    final r = math.min(x1 - x0, y1 - y0) / 2;
    final w = (x1 - x0) / 2 - r, h = (y1 - y0) / 2 - r;
    // core: horizontal or vertical segment through the centre
    if (w >= h) {
      setCore(_center.x - w, _center.y, _center.z, _center.x + w, _center.y,
          _center.z, r);
    } else {
      setCore(_center.x, _center.y - h, _center.z, _center.x, _center.y + h,
          _center.z, r);
    }
    minX = x0;
    maxX = x1;
    minY = y0;
    maxY = y1;
    _ctx = ctx;
  }

  RenderCtx? _ctx;

  @override
  double frontZ(double px, double py) {
    final ctx = _ctx;
    if (ctx == null) return double.nan;
    // ray from (px, py, +inf) toward -z in view space -> world
    const zTop = 1000.0;
    final o = ctx.cam.rotInv(V3(px, py, zTop)) + ctx.cam.pivot;
    final dir = ctx.cam.rotInv(const V3(0, 0, -1));
    var tmin = -double.infinity, tmax = double.infinity;
    for (var ax = 0; ax < 3; ax++) {
      final oo = ax == 0 ? o.x : (ax == 1 ? o.y : o.z);
      final dd = ax == 0 ? dir.x : (ax == 1 ? dir.y : dir.z);
      final l = ax == 0 ? lo.x : (ax == 1 ? lo.y : lo.z);
      final h = ax == 0 ? hi.x : (ax == 1 ? hi.y : hi.z);
      if (dd.abs() < 1e-12) {
        if (oo < l || oo > h) return double.nan;
      } else {
        var t1 = (l - oo) / dd, t2 = (h - oo) / dd;
        if (t1 > t2) {
          final tt = t1;
          t1 = t2;
          t2 = tt;
        }
        tmin = math.max(tmin, t1);
        tmax = math.min(tmax, t2);
      }
    }
    if (tmin > tmax) return double.nan;
    return zTop - tmin;
  }

  static const List<List<int>> _faces = [
    [0, 2, 6, 4], // -x
    [1, 5, 7, 3], // +x
    [0, 4, 5, 1], // -y
    [2, 3, 7, 6], // +y
    [0, 1, 3, 2], // -z
    [4, 6, 7, 5], // +z
  ];
  static const List<V3> _normals = [
    V3(-1, 0, 0), V3(1, 0, 0), V3(0, -1, 0), V3(0, 1, 0), V3(0, 0, -1), V3(0, 0, 1)
  ];

  @override
  void paint(ui.Canvas c, RenderCtx ctx) {
    for (var f = 0; f < 6; f++) {
      final n = ctx.cam.rot(_normals[f]);
      if (n.z <= 1e-4) continue;
      final idx = _faces[f];
      _p.reset();
      _p.moveTo(_cs[idx[0]].dx, _cs[idx[0]].dy);
      for (var i = 1; i < 4; i++) {
        _p.lineTo(_cs[idx[i]].dx, _cs[idx[i]].dy);
      }
      _p.close();
      ctx.fill.shader = null;
      ctx.fill.color = ctx.shade(MatKind.prop, n.x, n.y, n.z);
      c.drawPath(_p, ctx.fill);
    }
  }
}
