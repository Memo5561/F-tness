import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'camera.dart';
import 'math3d.dart';
import 'style.dart';

enum MatKind { body, joint, prop }

/// Shared per-frame drawing state (paints/paths are reused).
class RenderCtx {
  ViewCam cam;
  MannequinStyle style;
  RenderCtx(this.cam, this.style);

  final Paint fill = Paint()..isAntiAlias = true;
  static const Color _opaque = Color(0xFF000000);
  final Paint plus = Paint()
    ..isAntiAlias = true
    ..blendMode = BlendMode.plus;
  final Path path = Path();
  final Path path2 = Path();

  Rgb albedo(MatKind m) => m == MatKind.body
      ? style.body
      : (m == MatKind.joint ? style.joint : style.prop);

  static int _c(double v) => v <= 0 ? 0 : (v >= 1 ? 255 : (v * 255).round());

  /// Shade a (view-space, unit) normal.
  Color shade(MatKind m, double nx, double ny, double nz) {
    final s = style;
    final al = albedo(m);
    final nzc = nz < 0 ? 0.0 : (nz > 1 ? 1.0 : nz);
    final e = 1 - nzc;
    var i = s.ambient + s.k.x * nx + s.k.y * ny + s.k.z * nz - s.edgeDark * e * e;
    var spec = 0.0;
    if (m == MatKind.prop) {
      // metal: a bit more contrast and a specular highlight (half vector key/view)
      i = 0.25 + 1.25 * (i - 0.25);
      final h = _halfKey;
      final nh = nx * h.x + ny * h.y + nz * h.z;
      if (nh > 0) spec = s.propSpec * math.pow(nh, 28).toDouble();
    }
    var dirF = 0.0;
    final nxy = math.sqrt(nx * nx + ny * ny);
    if (nxy > 1e-6) {
      dirF = (nx * s.rimDirX + ny * s.rimDirY) / nxy;
      if (dirF < 0) dirF = 0;
    }
    final rim = s.rimStrength * e * e * e * (s.rimUniform + (1 - s.rimUniform) * dirF);
    return Color.fromARGB(
      255,
      _c(al.r * i + s.rim.r * rim + spec),
      _c(al.g * i + s.rim.g * rim + spec),
      _c(al.b * i + s.rim.b * rim + spec),
    );
  }

  V3 get _halfKey => (style.k.unit + const V3(0, 0, 1)).unit;

  // ---------------------------------------------------------------- spheres
  static const List<double> radialStops = [
    0, 0.2, 0.4, 0.55, 0.68, 0.78, 0.86, 0.92, 0.96, 0.985, 1.0
  ];
  final List<Color> _radCols = List.filled(11, const Color(0xFF000000));

  // Unit-space sphere shaders per material, rebuilt only when the style changes.
  MannequinStyle? _cacheStyle;
  final Map<MatKind, (ui.Shader, ui.Shader, ui.Shader?)> _unitSphere = {};

  void _computeRadial(MatKind m) {
    final s = style;
    final al = albedo(m);
    final kx = s.k.x, ky = s.k.y;
    final kxy = math.sqrt(kx * kx + ky * ky);
    final isProp = m == MatKind.prop;
    for (var i = 0; i < radialStops.length; i++) {
      final rho = radialStops[i];
      final w = math.sqrt(math.max(0.0, 1 - rho * rho));
      final e = 1 - w;
      var inten = s.ambient - kxy + s.k.z * w - s.edgeDark * e * e;
      if (isProp) inten = 0.25 + 1.25 * (inten - 0.25);
      final rim = s.rimStrength * s.rimUniform * e * e * e;
      _radCols[i] = Color.fromARGB(255, _c(al.r * inten + s.rim.r * rim),
          _c(al.g * inten + s.rim.g * rim), _c(al.b * inten + s.rim.b * rim));
    }
  }

  Color _linearTop(MatKind m) {
    final s = style;
    final al = albedo(m);
    final kxy = math.sqrt(s.k.x * s.k.x + s.k.y * s.k.y);
    final lk = m == MatKind.prop ? 1.25 : 1.0;
    return Color.fromARGB(255, _c(al.r * 2 * kxy * lk), _c(al.g * 2 * kxy * lk),
        _c(al.b * 2 * kxy * lk));
  }

  Offset get _keyDir2 {
    final kx = style.k.x, ky = style.k.y;
    final kxy = math.sqrt(kx * kx + ky * ky);
    return kxy > 1e-6 ? Offset(kx / kxy, -ky / kxy) : const Offset(1, 0);
  }

  (ui.Shader, ui.Shader, ui.Shader?) _sphereShaders(MatKind m) {
    if (!identical(_cacheStyle, style)) {
      _cacheStyle = style;
      _unitSphere.clear();
    }
    return _unitSphere.putIfAbsent(m, () {
      _computeRadial(m);
      final radial = ui.Gradient.radial(Offset.zero, 1, _radCols, radialStops);
      final dir = _keyDir2;
      final linear = ui.Gradient.linear(
          -dir, dir, [const Color(0xFF000000), _linearTop(m)]);
      ui.Shader? cres;
      if (style.rimStrength > 0) {
        final rd = Offset(style.rimDirX, -style.rimDirY);
        setCrescent(-rd * 0.35, 1.35, null);
        cres = plus.shader;
      }
      return (radial, linear, cres);
    });
  }

  /// Draws a sphere disc (or [region] path if given) with exact wrap-lighting:
  /// radial part (depends on nz) + linear part (K_xy . n_xy) added with
  /// BlendMode.plus, plus an additive rim crescent. Without a region the
  /// cached unit-space shaders are used (no per-call shader allocation).
  void drawSphere(Canvas c, Offset center, double rPx, MatKind m,
      {Path? region}) {
    if (rPx <= 0.05) return;
    fill.color = _opaque; // shader output is modulated by the paint alpha
    if (region == null) {
      final (radial, linear, cres) = _sphereShaders(m);
      c.save();
      c.translate(center.dx, center.dy);
      c.scale(rPx);
      fill.shader = radial;
      c.drawCircle(Offset.zero, 1, fill);
      plus.shader = linear;
      c.drawCircle(Offset.zero, 1, plus);
      if (cres != null) {
        plus.shader = cres;
        c.drawCircle(Offset.zero, 1, plus);
      }
      c.restore();
      return;
    }
    final s = style;
    _computeRadial(m);
    fill.shader = ui.Gradient.radial(center, rPx, _radCols, radialStops);
    final dir = _keyDir2;
    plus.shader = ui.Gradient.linear(center - dir * rPx, center + dir * rPx,
        [const Color(0xFF000000), _linearTop(m)]);
    c.drawPath(region, fill);
    c.drawPath(region, plus);
    if (s.rimStrength > 0) {
      final rd = Offset(s.rimDirX, -s.rimDirY);
      setCrescent(center - rd * (0.35 * rPx), 1.35 * rPx, null);
      c.drawPath(region, plus);
    }
  }

  static const List<double> _crescStops = [0.0, 0.7, 0.83, 0.92, 1.0];
  final List<Color> _crescCols = List.filled(5, const Color(0xFF000000));

  /// Sets [plus] to an additive rim crescent gradient (centre offset away from
  /// the rim side, so only the rim-side silhouette reaches t = 1).
  void setCrescent(Offset center, double radius, Float64List? matrix) {
    final s = style;
    final amt = s.rimStrength * (1 - s.rimUniform);
    const f = [0.0, 0.0, 0.18, 0.5, 1.0];
    for (var i = 0; i < 5; i++) {
      final a = amt * f[i];
      _crescCols[i] = Color.fromARGB(
          255, _c(s.rim.r * a), _c(s.rim.g * a), _c(s.rim.b * a));
    }
    plus.shader = ui.Gradient.radial(
        center, radius, _crescCols, _crescStops, TileMode.clamp, matrix);
  }

  // ---------------------------------------------------------------- cylinders
  static const List<double> latS = [
    -1, -0.97, -0.9, -0.78, -0.6, -0.32, 0, 0.32, 0.6, 0.78, 0.9, 0.97, 1
  ];
  final List<Color> _latCols = List.filled(13, const Color(0xFF000000));
  final List<double> _latStops = List.filled(13, 0.0);
  final Float64List _m4 = Float64List(16);

  /// Fills [path] (a tapered capsule hull between screen circles c1/r1 and
  /// c2/r2) with cylindrical shading. d = unit 3D view axis (c1 -> c2),
  /// tanBeta = (R1 - R2) / L (3D taper).
  void fillCylinder(Canvas c, Path path, Offset c1, double r1, Offset c2,
      double r2, V3 d, double tanBeta, MatKind m, {double alpha = 1}) {
    final dx = c2.dx - c1.dx, dy = c2.dy - c1.dy;
    final dl = math.sqrt(dx * dx + dy * dy);
    if (dl < 1e-6) return;
    fill.color = _opaque;
    final ux = dx / dl, uy = dy / dl; // screen axis
    final epx = -uy, epy = ux; // screen perpendicular (u rotated +90deg)
    // view-space basis for the normal: e1 (in screen plane), e2 (toward viewer)
    final e1 = V3(epx, -epy, 0);
    var e2 = V3(-d.z * d.x, -d.z * d.y, 1 - d.z * d.z);
    final l2 = e2.length;
    e2 = l2 < 1e-6 ? const V3(0, 0, 1) : e2 * (1 / l2);
    final tb = tanBeta.clamp(-0.6, 0.6);

    Color col(double sLat) => _cylCol(m, sLat, e1, e2, d, tb, alpha);

    final dr = r1 - r2;
    final maxR = math.max(r1, r2);
    if (dr.abs() < 0.015 * maxR + 0.02) {
      // ~cylinder: linear gradient across
      final rm = (r1 + r2) / 2;
      final mx = (c1.dx + c2.dx) / 2, my = (c1.dy + c2.dy) / 2;
      for (var i = 0; i < latS.length; i++) {
        _latCols[i] = col(latS[i]);
        _latStops[i] = (latS[i] + 1) / 2;
      }
      fill.shader = ui.Gradient.linear(Offset(mx - epx * rm, my - epy * rm),
          Offset(mx + epx * rm, my + epy * rm), _latCols, _latStops);
    } else {
      // cone: sweep gradient around the apex of the two tangent lines
      final apexDist = r1 * dl / dr; // signed, along u from c1
      final ax = c1.dx + ux * apexDist, ay = c1.dy + uy * apexDist;
      final sinA = (dr.abs() / dl).clamp(0.0, 0.999);
      final alpha = math.asin(sinA);
      final tanA = math.tan(alpha);
      // direction from apex toward the limb
      final wSign = dr > 0 ? -1.0 : 1.0; // w = wSign * u
      final wAng = math.atan2(uy * wSign, ux * wSign);
      // increasing angle == toward rot90(w) == wSign * e'
      for (var i = 0; i < latS.length; i++) {
        final sp = latS[i]; // lateral coordinate along rot90(w)
        final th = math.atan(sp * tanA);
        _latStops[i] = (th + alpha) / (2 * alpha);
        _latCols[i] = col(sp * wSign);
      }
      final phi = wAng - math.pi;
      final cs = math.cos(phi), sn = math.sin(phi);
      final m4 = _m4;
      m4.fillRange(0, 16, 0);
      m4[0] = cs;
      m4[1] = sn;
      m4[4] = -sn;
      m4[5] = cs;
      m4[10] = 1;
      m4[12] = ax - cs * ax + sn * ay;
      m4[13] = ay - sn * ax - cs * ay;
      m4[15] = 1;
      fill.shader = ui.Gradient.sweep(Offset(ax, ay), _latCols, _latStops,
          TileMode.clamp, math.pi - alpha, math.pi + alpha, m4);
    }
    c.drawPath(path, fill);
  }

  // Unit-space cylinder shaders for props (constant radius): keyed by the
  // view-space axis direction; rebuilt only when the camera or style changes.
  final Map<(int, int, int, int), ui.Shader> _cylCache = {};
  MannequinStyle? _cylStyle;

  /// Linear gradient across a unit cylinder (from local y = -1 to +1) for a
  /// prop whose view-space axis is [d].
  ui.Shader cylShader(MatKind m, V3 d) {
    if (!identical(_cylStyle, style)) {
      _cylStyle = style;
      _cylCache.clear();
    }
    final key = (m.index, (d.x * 2000).round(), (d.y * 2000).round(), (d.z * 2000).round());
    final hit = _cylCache[key];
    if (hit != null) return hit;
    if (_cylCache.length > 24) _cylCache.clear();
    // screen axis (y down) and its perpendicular, as in fillCylinder
    var l = math.sqrt(d.x * d.x + d.y * d.y);
    double ux = 1, uy = 0;
    if (l > 1e-6) {
      ux = d.x / l;
      uy = -d.y / l;
    }
    final e1 = V3(-uy, -ux, 0);
    var e2 = V3(-d.z * d.x, -d.z * d.y, 1 - d.z * d.z);
    l = e2.length;
    e2 = l < 1e-6 ? const V3(0, 0, 1) : e2 * (1 / l);
    final cols = List<Color>.filled(latS.length, const Color(0xFF000000));
    final stops = List<double>.filled(latS.length, 0);
    for (var i = 0; i < latS.length; i++) {
      cols[i] = _cylCol(m, latS[i], e1, e2, d, 0, 1);
      stops[i] = (latS[i] + 1) / 2;
    }
    final sh = ui.Gradient.linear(const Offset(0, -1), const Offset(0, 1), cols, stops);
    _cylCache[key] = sh;
    return sh;
  }

  Color _cylCol(MatKind m, double sLat, V3 e1, V3 e2, V3 d, double tb, double alpha) {
    final q = math.sqrt(math.max(0.0, 1 - sLat * sLat));
    var nx = e1.x * sLat + e2.x * q + d.x * tb;
    var ny = e1.y * sLat + e2.y * q + d.y * tb;
    var nz = e1.z * sLat + e2.z * q + d.z * tb;
    final nl = math.sqrt(nx * nx + ny * ny + nz * nz);
    nx /= nl;
    ny /= nl;
    nz /= nl;
    final col = shade(m, nx, ny, nz);
    return alpha < 1 ? col.withValues(alpha: alpha) : col;
  }

  ui.Shader? _bevel, _discHi;
  MannequinStyle? _discStyle;

  /// Bevel ring + highlight for a prop end disc drawn as the unit circle
  /// under the current canvas transform. [n] = view-space disc normal.
  void drawDiscDetail(Canvas c, V3 n, double alpha) {
    if (!identical(_discStyle, style) || _bevel == null) {
      _discStyle = style;
      _bevel = ui.Gradient.radial(Offset.zero, 1, const [
        Color(0x00000000),
        Color(0x00000000),
        Color(0x47000000),
        Color(0x80000000),
      ], const [0, 0.62, 0.86, 1]);
      _discHi = ui.Gradient.radial(Offset.zero, 1, const [
        Color(0xFF8A8A8A),
        Color(0xFF3A3A3A),
        Color(0xFF000000),
      ], const [0, 0.35, 0.8]);
    }
    fill.shader = _bevel;
    fill.color = Color.fromARGB((alpha * 255).round(), 0, 0, 0);
    c.drawCircle(Offset.zero, 1, fill);
    final h = _halfKey;
    final nh = n.x * h.x + n.y * h.y + n.z * h.z;
    final a = nh <= 0 ? 0.0 : math.pow(nh, 4).toDouble() * alpha * style.propSpec * 1.4;
    if (a > 0.01) {
      plus.shader = _discHi;
      plus.color = Color.fromARGB((a.clamp(0.0, 1.0) * 255).round(), 0, 0, 0);
      c.drawCircle(Offset.zero, 1, plus);
      plus.color = _opaque;
    }
  }

  /// Hull of two end "discs" (screen centres c1/c2, half-widths r1/r2). An end
  /// with squash s < 1 is the projection of a circle perpendicular to the
  /// axis (an ellipse with semi-axis r across and r*s along the axis); s = 1
  /// is a round (spherical) end. Returns false if one end contains the other.
  static bool hullPathEx(Path p, Offset c1, double r1, double s1, Offset c2,
      double r2, double s2) {
    if (s1 >= 0.999 && s2 >= 0.999) return hullPath(p, c1, r1, c2, r2);
    p.reset();
    final dx = c2.dx - c1.dx, dy = c2.dy - c1.dy;
    final dl = math.sqrt(dx * dx + dy * dy);
    if (dl <= (r1 - r2).abs() + 1e-3) return false;
    final ux = dx / dl, uy = dy / dl;
    final ex = -uy, ey = ux;
    final sa = ((r1 - r2) / dl).clamp(-0.95, 0.95);
    final ca = math.sqrt(1 - sa * sa);
    final phi1 = math.atan2(ca, sa); // normal angle of tangent line 1 (from u toward e)
    // point on an end ellipse with outward normal angle phi
    Offset at(Offset c, double r, double sq, double phi) {
      final a = r, b = r * math.max(0.02, sq);
      final cp = math.cos(phi), sp = math.sin(phi);
      final den = math.sqrt(b * b * cp * cp + a * a * sp * sp);
      final pu = b * b * cp / den, pe = a * a * sp / den;
      return Offset(c.dx + ux * pu + ex * pe, c.dy + uy * pu + ey * pe);
    }

    void arc(Offset c, double r, double sq, double from, double to) {
      if (sq >= 0.999) {
        // circle: exact arc (angles measured from u toward e)
        final base = math.atan2(uy, ux);
        // screen angle of direction (cos f) u + (sin f) e  = base + f (e = rot90(u))
        p.arcTo(Rect.fromCircle(center: c, radius: r), base + from, to - from, false);
        return;
      }
      const n = 14;
      for (var i = 1; i <= n; i++) {
        final o = at(c, r, sq, from + (to - from) * i / n);
        p.lineTo(o.dx, o.dy);
      }
    }

    final a0 = at(c1, r1, s1, phi1);
    p.moveTo(a0.dx, a0.dy);
    final b0 = at(c2, r2, s2, phi1);
    p.lineTo(b0.dx, b0.dy);
    arc(c2, r2, s2, phi1, -phi1);
    final a1 = at(c1, r1, s1, -phi1);
    p.lineTo(a1.dx, a1.dy);
    arc(c1, r1, s1, 2 * math.pi - phi1, phi1);
    p.close();
    return true;
  }

  /// Builds the hull path of two circles into [p]. Returns false if one circle
  /// contains the other (degenerate: limb points at the camera).
  static bool hullPath(Path p, Offset c1, double r1, Offset c2, double r2,
      {double extend1 = 0, double extend2 = 0, bool flat1 = false, bool flat2 = false}) {
    p.reset();
    final dx = c2.dx - c1.dx, dy = c2.dy - c1.dy;
    final dl = math.sqrt(dx * dx + dy * dy);
    if (dl <= (r1 - r2).abs() + 1e-3) return false;
    final ux = dx / dl, uy = dy / dl;
    final ex = -uy, ey = ux;
    final sa = (r1 - r2) / dl;
    final ca = math.sqrt(math.max(0.0, 1 - sa * sa));
    // unit normals of the two tangent lines
    final n1x = sa * ux + ca * ex, n1y = sa * uy + ca * ey;
    final n2x = sa * ux - ca * ex, n2y = sa * uy - ca * ey;
    final base = math.atan2(uy, ux);
    final half = math.pi / 2 - math.asin(sa.clamp(-1.0, 1.0));
    if (flat1) {
      // flat end: cut perpendicular to the axis (slightly extended for overlap)
      final bx = c1.dx - ux * extend1, by = c1.dy - uy * extend1;
      p.moveTo(bx + ex * r1, by + ey * r1);
    } else {
      p.moveTo(c1.dx + n1x * r1, c1.dy + n1y * r1);
    }
    if (flat2) {
      final bx = c2.dx + ux * extend2, by = c2.dy + uy * extend2;
      p.lineTo(bx + ex * r2, by + ey * r2);
      p.lineTo(bx - ex * r2, by - ey * r2);
    } else {
      p.lineTo(c2.dx + n1x * r2, c2.dy + n1y * r2);
      p.arcTo(Rect.fromCircle(center: c2, radius: r2), base + half, -2 * half,
          false);
    }
    if (flat1) {
      final bx = c1.dx - ux * extend1, by = c1.dy - uy * extend1;
      p.lineTo(bx - ex * r1, by - ey * r1);
    } else {
      p.lineTo(c1.dx + n2x * r1, c1.dy + n2y * r1);
      p.arcTo(Rect.fromCircle(center: c1, radius: r1), base - half,
          -(2 * math.pi - 2 * half), false);
    }
    p.close();
    return true;
  }
}

/// Plane cutting a sphere: keeps the visible sphere surface where
/// (x - c).d < h (keepLess) or > h.
class CutPlane {
  V3 d; // view-space unit
  double h;
  bool keepLess;
  CutPlane(this.d, this.h, this.keepLess);
}

/// Builds the screen-space path of the part of a sphere's visible (front)
/// surface that satisfies [pl]. Returns 0 = nothing visible, 1 = whole disc,
/// 2 = path written to [out].
int sphereCutRegion(Path out, Offset sc, double s, double R, CutPlane pl) {
  final d = pl.d, h = pl.h;
  out.reset();
  out.fillType = PathFillType.nonZero;
  bool keep(double v) => pl.keepLess ? v < h : v > h;
  final rho2 = R * R - h * h;
  if (rho2 <= 1e-9) {
    // plane misses the sphere
    return keep(h >= R ? -R : R) ? 1 : 0; // any point (e.g. centre-ish) test
  }
  final rho = math.sqrt(rho2);
  // u = d x z (horizontal), w = d x u
  var ux = d.y, uy = -d.x;
  final ul = math.sqrt(ux * ux + uy * uy);
  if (ul < 1e-4) {
    // C parallel to the screen
    final zc = h * d.z;
    if (zc <= 0) {
      return keep(R * d.z) ? 1 : 0;
    }
    // ring vs inner disc (radius rho)
    final innerIsGreater = h > 0; // silhouette (x.d=0) is on the "less" side
    final keepInner = pl.keepLess ? !innerIsGreater : innerIsGreater;
    if (keepInner) {
      out.addOval(Rect.fromCircle(center: sc, radius: rho * s));
    } else {
      out.fillType = PathFillType.evenOdd;
      out.addOval(Rect.fromCircle(center: sc, radius: R * s));
      out.addOval(Rect.fromCircle(center: sc, radius: rho * s));
    }
    return 2;
  }
  ux /= ul;
  uy /= ul;
  // w = d x u, u = (ux, uy, 0)
  final wx = d.y * 0 - d.z * uy;
  final wy = d.z * ux - d.x * 0;
  final wz = d.x * uy - d.y * ux;
  final cz = h * d.z;
  final amp = rho * wz;
  Offset ptAt(double psi) {
    final cp = math.cos(psi), sp = math.sin(psi);
    final x = h * d.x + rho * (cp * ux + sp * wx);
    final y = h * d.y + rho * (cp * uy + sp * wy);
    return Offset(sc.dx + x * s, sc.dy - y * s);
  }

  if (amp.abs() <= cz.abs()) {
    if (cz < 0) {
      // C entirely behind the silhouette plane
      return keep(R * d.z) ? 1 : 0;
    }
    // C entirely in front: projected ellipse = inner region
    final innerIsGreater = h > 0;
    final keepInner = pl.keepLess ? !innerIsGreater : innerIsGreater;
    if (!keepInner) {
      out.fillType = PathFillType.evenOdd;
      out.addOval(Rect.fromCircle(center: sc, radius: R * s));
    }
    const n = 32;
    for (var i = 0; i <= n; i++) {
      final o = ptAt(2 * math.pi * i / n);
      if (i == 0) {
        out.moveTo(o.dx, o.dy);
      } else {
        out.lineTo(o.dx, o.dy);
      }
    }
    out.close();
    return 2;
  }
  // crossing: front arc where z(psi) = cz + amp*sin(psi) >= 0
  final s0 = (-cz / amp).clamp(-1.0, 1.0);
  final pa = math.asin(s0);
  double a0, a1; // arc from a0 to a1 (increasing)
  if (amp > 0) {
    a0 = pa;
    a1 = math.pi - pa;
  } else {
    a0 = math.pi - pa;
    a1 = 2 * math.pi + pa;
  }
  const n = 20;
  final p0 = ptAt(a0);
  out.moveTo(p0.dx, p0.dy);
  for (var i = 1; i <= n; i++) {
    final o = ptAt(a0 + (a1 - a0) * i / n);
    out.lineTo(o.dx, o.dy);
  }
  // silhouette arc from end point back to start point through the kept side.
  // angles in view space (y up)
  final ex1 = h * d.x + rho * (math.cos(a1) * ux + math.sin(a1) * wx);
  final ey1 = h * d.y + rho * (math.cos(a1) * uy + math.sin(a1) * wy);
  final sx0 = h * d.x + rho * (math.cos(a0) * ux + math.sin(a0) * wx);
  final sy0 = h * d.y + rho * (math.cos(a0) * uy + math.sin(a0) * wy);
  final thB = math.atan2(ey1, ex1);
  final thA = math.atan2(sy0, sx0);
  var sweep = (thA - thB) % (2 * math.pi);
  if (sweep < 0) sweep += 2 * math.pi;
  final mid = thB + sweep / 2;
  final mv = R * (math.cos(mid) * d.x + math.sin(mid) * d.y);
  if (!keep(mv)) sweep -= 2 * math.pi;
  // screen angles are negated (y flip)
  out.arcTo(Rect.fromCircle(center: sc, radius: R * s), -thB, -sweep, false);
  out.close();
  return 2;
}

/// Closest points between 2D segments p1-q1 and p2-q2. Returns (s, t).
(double, double) closestSegSeg(double p1x, double p1y, double q1x, double q1y,
    double p2x, double p2y, double q2x, double q2y) {
  final d1x = q1x - p1x, d1y = q1y - p1y;
  final d2x = q2x - p2x, d2y = q2y - p2y;
  final rx = p1x - p2x, ry = p1y - p2y;
  final a = d1x * d1x + d1y * d1y;
  final e = d2x * d2x + d2y * d2y;
  final f = d2x * rx + d2y * ry;
  double s, t;
  const eps = 1e-9;
  if (a <= eps && e <= eps) return (0, 0);
  if (a <= eps) {
    s = 0;
    t = (f / e).clamp(0.0, 1.0);
  } else {
    final c = d1x * rx + d1y * ry;
    if (e <= eps) {
      t = 0;
      s = (-c / a).clamp(0.0, 1.0);
    } else {
      final b = d1x * d2x + d1y * d2y;
      final denom = a * e - b * b;
      s = denom > eps ? ((b * f - c * e) / denom).clamp(0.0, 1.0) : 0.0;
      t = (b * s + f) / e;
      if (t < 0) {
        t = 0;
        s = (-c / a).clamp(0.0, 1.0);
      } else if (t > 1) {
        t = 1;
        s = ((b - c) / a).clamp(0.0, 1.0);
      }
    }
  }
  return (s, t);
}

/// Region of the visible (front) surface of an ellipsoid satisfying a cut in
/// its local unit-sphere space (u = coefficients of the semi-axis vectors
/// a1, a2, a3 given in VIEW space): keeps u.d < h (keepLess) or u.d > h.
/// [sc] is the screen position of the centre, [s] the px scale.
/// Returns 0 = nothing visible, 1 = whole ellipse, 2 = path written to [out].
int ellipsoidCutRegion(Path out, Offset sc, double s, V3 a1, V3 a2, V3 a3,
    V3 d, double h, bool keepLess) {
  out.reset();
  out.fillType = PathFillType.nonZero;
  bool keep(double v) => keepLess ? v < h : v > h;
  // view direction in local space: M^-1 z
  final v = V3(a1.z / a1.length2, a2.z / a2.length2, a3.z / a3.length2).unit;
  Offset map(V3 u) {
    final x = a1.x * u.x + a2.x * u.y + a3.x * u.z;
    final y = a1.y * u.x + a2.y * u.y + a3.y * u.z;
    return Offset(sc.dx + x * s, sc.dy - y * s);
  }

  // orthonormal basis (g1, g2) of the silhouette great circle (perp. to v)
  var g1 = d - v * d.dot(v);
  if (g1.length < 1e-6) {
    g1 = v.cross(const V3(1, 0, 0));
    if (g1.length < 1e-6) g1 = v.cross(const V3(0, 1, 0));
  }
  g1 = g1.unit;
  final g2 = v.cross(g1);
  void silhouette(double th0, double sweep, int n, bool move) {
    for (var i = 0; i <= n; i++) {
      final th = th0 + sweep * i / n;
      final o = map(g1 * math.cos(th) + g2 * math.sin(th));
      if (i == 0 && move) {
        out.moveTo(o.dx, o.dy);
      } else {
        out.lineTo(o.dx, o.dy);
      }
    }
  }

  final rho2 = 1 - h * h;
  if (rho2 <= 1e-9) return keep(h >= 1 ? -1 : 1) ? 1 : 0;
  final rho = math.sqrt(rho2);
  final dv = d.dot(v);
  var uc = d.cross(v);
  final ul = uc.length;
  const nFull = 48;

  void circleC(V3 uu, V3 ww) {
    for (var i = 0; i <= nFull; i++) {
      final psi = 2 * math.pi * i / nFull;
      final o = map(d * h + uu * (rho * math.cos(psi)) + ww * (rho * math.sin(psi)));
      if (i == 0) {
        out.moveTo(o.dx, o.dy);
      } else {
        out.lineTo(o.dx, o.dy);
      }
    }
    out.close();
  }

  if (ul < 1e-4) {
    // C parallel to the silhouette circle
    if (h * dv <= 0) return keep(dv) ? 1 : 0;
    final keepInner = keepLess ? !(h > 0) : (h > 0);
    final uu = g1, ww = g2;
    if (!keepInner) {
      out.fillType = PathFillType.evenOdd;
      silhouette(0, 2 * math.pi, nFull, true);
      out.close();
    }
    circleC(uu, ww);
    return 2;
  }
  uc = uc * (1 / ul);
  final wc = d.cross(uc);
  final cz = h * dv;
  final amp = rho * wc.dot(v);
  V3 cAt(double psi) =>
      d * h + uc * (rho * math.cos(psi)) + wc * (rho * math.sin(psi));
  if (amp.abs() <= cz.abs()) {
    if (cz < 0) return keep(dv) ? 1 : 0;
    final keepInner = keepLess ? !(h > 0) : (h > 0);
    if (!keepInner) {
      out.fillType = PathFillType.evenOdd;
      silhouette(0, 2 * math.pi, nFull, true);
      out.close();
    }
    circleC(uc, wc);
    return 2;
  }
  final s0 = (-cz / amp).clamp(-1.0, 1.0);
  final pa = math.asin(s0);
  double ps0, ps1;
  if (amp > 0) {
    ps0 = pa;
    ps1 = math.pi - pa;
  } else {
    ps0 = math.pi - pa;
    ps1 = 2 * math.pi + pa;
  }
  const n = 24;
  for (var i = 0; i <= n; i++) {
    final o = map(cAt(ps0 + (ps1 - ps0) * i / n));
    if (i == 0) {
      out.moveTo(o.dx, o.dy);
    } else {
      out.lineTo(o.dx, o.dy);
    }
  }
  final pEnd = cAt(ps1), pStart = cAt(ps0);
  final thB = math.atan2(pEnd.dot(g2), pEnd.dot(g1));
  final thA = math.atan2(pStart.dot(g2), pStart.dot(g1));
  var sweep = (thA - thB) % (2 * math.pi);
  if (sweep < 0) sweep += 2 * math.pi;
  final mid = thB + sweep / 2;
  final dg1 = d.dot(g1);
  if (!keep(math.cos(mid) * dg1)) sweep -= 2 * math.pi;
  silhouette(thB, sweep, 32, false);
  out.close();
  return 2;
}
