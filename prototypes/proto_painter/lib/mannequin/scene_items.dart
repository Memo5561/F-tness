import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'math3d.dart';
import 'render_items.dart';

/// A depth-sortable drawable. Geometry is in world space; [prepare] derives
/// view-space data (x right, y up, z toward the viewer).
abstract class Item {
  String name;
  Item(this.name);

  bool enabled = true;

  /// Sort key: view z of the centre (larger = nearer).
  double depth = 0;

  /// 2D core segment (view units) + radius for overlap tests.
  double ax = 0, ay = 0, az = 0, bx = 0, by = 0, bz = 0, rr = 0;
  double minX = 0, maxX = 0, minY = 0, maxY = 0;

  /// Items that must be painted before this one.
  final List<Item> after = [];

  /// Items for which no pairwise depth test should be done.
  final Set<Item> noTest = {};

  // topo-sort scratch
  int indeg = 0;
  final List<Item> succ = [];
  final List<Item> pred = [];
  bool emitted = false;
  int mark = 0;

  void prepare(RenderCtx ctx);

  /// Front-surface view z at view point (px, py); NaN if outside.
  double frontZ(double px, double py);

  void paint(ui.Canvas c, RenderCtx ctx);

  void setCore(double x0, double y0, double z0, double x1, double y1, double z1,
      double r) {
    ax = x0;
    ay = y0;
    az = z0;
    bx = x1;
    by = y1;
    bz = z1;
    rr = r;
    minX = math.min(x0, x1) - r;
    maxX = math.max(x0, x1) + r;
    minY = math.min(y0, y1) - r;
    maxY = math.max(y0, y1) + r;
  }

  void resetLinks() {
    after.clear();
    noTest.clear();
  }
}

// ---------------------------------------------------------------- sphere
class Attach {
  /// World unit direction from the ball centre along the attached limb.
  V3 dir = V3.unitY;

  /// Cut distance along [dir] where the limb surface enters the ball.
  double h = 0;
  bool active = true;

  /// The attached limb and which of its ends (0 = start, 1 = end) sits here.
  LimbItem? limb;
  int end = 0;
}

class SphereItem extends Item {
  V3 c = V3.zero;
  double r = 1;
  MatKind mat;
  final List<Attach> attach = [];

  /// Free cap mode: draw only the cap beyond plane through centre along capDir.
  SphereItem(super.name, this.mat);

  V3 _cv = V3.zero;
  Offset _sc = Offset.zero;
  double _s = 1;

  static double cutH(double rBall, double r0, double k) {
    // h^2 + (r0 + k h)^2 = R^2
    final a = 1 + k * k, b = 2 * r0 * k, cc = r0 * r0 - rBall * rBall;
    final disc = b * b - 4 * a * cc;
    if (disc < 0) return 0;
    return (-b + math.sqrt(disc)) / (2 * a);
  }

  @override
  void prepare(RenderCtx ctx) {
    _cv = ctx.cam.toView(c);
    _s = ctx.cam.pxScale(_cv.z);
    _sc = ctx.cam.toScreen(_cv);
    depth = _cv.z;
    setCore(_cv.x, _cv.y, _cv.z, _cv.x, _cv.y, _cv.z, r);
  }

  @override
  double frontZ(double px, double py) {
    final dx = px - _cv.x, dy = py - _cv.y;
    final q = r * r - dx * dx - dy * dy;
    return q < 0 ? double.nan : _cv.z + math.sqrt(q);
  }

  final List<CutPlane> _planes = [];
  final List<ui.Path> _paths = [ui.Path(), ui.Path(), ui.Path()];

  @override
  void paint(ui.Canvas c, RenderCtx ctx) {
    final rPx = r * _s;
    _planes.clear();
    for (final a in attach) {
      if (!a.active) continue;
      _planes.add(CutPlane(ctx.cam.rot(a.dir), a.h, true));
    }
    if (_planes.isEmpty) {
      ctx.drawSphere(c, _sc, rPx, mat);
      return;
    }
    ui.Path? region;
    var nClip = 0;
    for (var i = 0; i < _planes.length && i < 3; i++) {
      final res = sphereCutRegion(_paths[i], _sc, _s, r, _planes[i]);
      if (res == 0) {
        // fully hidden
        for (var j = 0; j < nClip; j++) {
          c.restore();
        }
        return;
      }
      if (res == 1) continue;
      if (region == null) {
        region = _paths[i];
      } else {
        c.save();
        c.clipPath(_paths[i]);
        nClip++;
      }
    }
    ctx.drawSphere(c, _sc, rPx, mat, region: region);
    for (var i = 0; i < nClip; i++) {
      c.restore();
    }
  }
}

// ---------------------------------------------------------------- limb
/// Tapered multi-piece capsule along a straight axis (points pts, radii rad).
class LimbItem extends Item {
  final List<V3> pts = [];
  final List<double> rad = [];
  MatKind mat;

  /// Trim at start/end (world units) for the sorting core (covered by balls).
  double trimStart = 0, trimEnd = 0;

  /// Free ends get a spherical cap shading.
  bool capStart = false, capEnd = false;

  /// "Entry" ends: when >= 0 the hull starts (ends) where the limb surface
  /// enters its joint ball, at this distance along the axis from pts.first
  /// (pts.last), with the end drawn as the projected entry circle. Used when
  /// the ball is painted before the limb (limb coming toward the viewer).
  double entryStart = -1, entryEnd = -1;

  LimbItem(super.name, this.mat);

  final List<V3> _pv = [];
  // effective profile (mid points blended away / dropped when end-on)
  final List<V3> _ev = [];
  final List<double> _er = [];
  final List<Offset> _es = [];
  final List<double> _epx = [];
  final List<int> _order = [];
  final ui.Path _hull = ui.Path();
  final ui.Path _cap = ui.Path();
  V3 _axis = V3.unitX;

  void set(List<V3> p, List<double> r) {
    pts
      ..clear()
      ..addAll(p);
    rad
      ..clear()
      ..addAll(r);
  }

  static double _smooth(double e0, double e1, double x) {
    final t = clampD((x - e0) / (e1 - e0), 0, 1);
    return t * t * (3 - 2 * t);
  }

  @override
  void prepare(RenderCtx ctx) {
    final n = pts.length;
    _pv.clear();
    var maxR = 0.0;
    var zs = 0.0;
    for (var i = 0; i < n; i++) {
      final v = ctx.cam.toView(pts[i]);
      _pv.add(v);
      maxR = math.max(maxR, rad[i]);
      zs += v.z;
    }
    depth = zs / n;
    final a = _pv.first, b = _pv.last;
    final len = (b - a).length;
    _axis = len > 1e-9 ? (b - a) * (1 / len) : V3.unitZ;
    final az = _axis.z.abs();
    // Seen nearly end-on, the mid bulge would add a ring: blend the interior
    // radii toward the straight taper, and drop the interior points entirely
    // once the limb points (almost) at the camera.
    final bl = _smooth(0.5, 0.85, az);
    _ev.clear();
    _er.clear();
    for (var i = 0; i < n; i++) {
      final interior = i > 0 && i < n - 1;
      if (interior && az > 0.85) continue;
      var r = rad[i];
      if (interior && bl > 0) {
        final f = len > 1e-9 ? (_pv[i] - a).length / len : 0.5;
        final rl = rad[0] + (rad[n - 1] - rad[0]) * f;
        r += (rl - r) * bl;
      }
      _ev.add(_pv[i]);
      _er.add(r);
    }
    // entry ends
    if (entryStart >= 0 && _ev.length >= 2) {
      final l01 = (_ev[1] - _ev[0]).length;
      final h = math.min(entryStart, l01 * 0.8);
      final f = l01 > 1e-9 ? h / l01 : 0.0;
      _er[0] = _er[0] + (_er[1] - _er[0]) * f;
      _ev[0] = V3.lerp(_ev[0], _ev[1], f);
    }
    if (entryEnd >= 0 && _ev.length >= 2) {
      final m = _ev.length - 1;
      final l = (_ev[m] - _ev[m - 1]).length;
      final h = math.min(entryEnd, l * 0.8);
      final f = l > 1e-9 ? h / l : 0.0;
      _er[m] = _er[m] + (_er[m - 1] - _er[m]) * f;
      _ev[m] = V3.lerp(_ev[m], _ev[m - 1], f);
    }
    _es.clear();
    _epx.clear();
    for (var i = 0; i < _ev.length; i++) {
      _es.add(ctx.cam.toScreen(_ev[i]));
      _epx.add(_er[i] * ctx.cam.pxScale(_ev[i].z));
    }
    var t0 = len > 1e-6 ? trimStart / len : 0.0;
    var t1 = len > 1e-6 ? 1 - trimEnd / len : 1.0;
    if (t1 < t0) {
      t0 = t1 = (t0 + t1) / 2;
    }
    final p0 = V3.lerp(a, b, t0), p1 = V3.lerp(a, b, t1);
    setCore(p0.x, p0.y, p0.z, p1.x, p1.y, p1.z, maxR);
  }

  @override
  double frontZ(double px, double py) {
    var best = double.nan;
    for (var i = 0; i + 1 < _ev.length; i++) {
      final a = _ev[i], b = _ev[i + 1];
      final dx = b.x - a.x, dy = b.y - a.y;
      final l2 = dx * dx + dy * dy;
      var t = l2 > 1e-12 ? ((px - a.x) * dx + (py - a.y) * dy) / l2 : 0.0;
      t = t.clamp(0.0, 1.0);
      final cx = a.x + dx * t, cy = a.y + dy * t, cz = a.z + (b.z - a.z) * t;
      final r = _er[i] + (_er[i + 1] - _er[i]) * t;
      final q = r * r - (px - cx) * (px - cx) - (py - cy) * (py - cy);
      if (q < 0) continue;
      final z = cz + math.sqrt(q);
      if (best.isNaN || z > best) best = z;
    }
    return best;
  }

  @override
  void paint(ui.Canvas c, RenderCtx ctx) {
    final n = _ev.length;
    if (n < 2) return;
    // piece order: far first
    _order.clear();
    for (var i = 0; i + 1 < n; i++) {
      _order.add(i);
    }
    if (n > 2) {
      _order.sort((i, j) => ((_ev[i].z + _ev[i + 1].z) - (_ev[j].z + _ev[j + 1].z))
          .sign
          .toInt());
    }
    final axis = _axis;
    // one taper for the whole limb so shading is continuous across pieces
    final lTot = (_pv.last - _pv.first).length;
    final tanBeta = lTot > 1e-6 ? (rad.first - rad.last) / lTot : 0.0;
    final sq = math.max(0.02, axis.z.abs());
    for (final i in _order) {
      final s0 = (i == 0 && entryStart >= 0) ? sq : 1.0;
      final s1 = (i == n - 2 && entryEnd >= 0) ? sq : 1.0;
      final ok = RenderCtx.hullPathEx(
          _hull, _es[i], _epx[i], s0, _es[i + 1], _epx[i + 1], s1);
      if (!ok) {
        // pointing at the camera: draw the bigger end as a sphere
        final bi = _epx[i] > _epx[i + 1] ? i : i + 1;
        ctx.drawSphere(c, _es[bi], _epx[bi], mat);
        continue;
      }
      ctx.fillCylinder(
          c, _hull, _es[i], _epx[i], _es[i + 1], _epx[i + 1], axis, tanBeta, mat);
    }
    // free end caps (sphere shading beyond the tangency plane)
    if (capStart) _paintCap(c, ctx, 0, -axis);
    if (capEnd) _paintCap(c, ctx, n - 1, axis);
  }

  void _paintCap(ui.Canvas c, RenderCtx ctx, int i, V3 dirOut) {
    final pl = CutPlane(dirOut, 0, false);
    final s = ctx.cam.pxScale(_ev[i].z);
    final res = sphereCutRegion(_cap, _es[i], s, _er[i], pl);
    if (res == 0) return;
    ctx.drawSphere(c, _es[i], _epx[i], mat, region: res == 2 ? _cap : null);
  }
}

// ---------------------------------------------------------------- ellipsoid
/// Projected-ellipsoid data in view space (ortho), see EllipsoidItem.
class _EllGeom {
  double s11 = 1, s12 = 0, s22 = 1; // projected shape matrix S
  double qx = 0, qy = 0, qzz = 1;
  double majA = 1, minB = 1, ang = 0; // semi-axes (view units), angle (view, y up)
  double ux = 1, uy = 0;

  void compute(V3 v1, V3 v2, V3 v3) {
    var q11 = 0.0, q12 = 0.0, q13 = 0.0, q22 = 0.0, q23 = 0.0, q33 = 0.0;
    void acc(V3 v) {
      final l2 = v.length2;
      final w = 1 / (l2 * l2);
      q11 += v.x * v.x * w;
      q12 += v.x * v.y * w;
      q13 += v.x * v.z * w;
      q22 += v.y * v.y * w;
      q23 += v.y * v.z * w;
      q33 += v.z * v.z * w;
    }

    acc(v1);
    acc(v2);
    acc(v3);
    qx = q13;
    qy = q23;
    qzz = q33;
    s11 = q11 - q13 * q13 / q33;
    s12 = q12 - q13 * q23 / q33;
    s22 = q22 - q23 * q23 / q33;
    final tr = s11 + s22;
    final det = s11 * s22 - s12 * s12;
    final disc = math.sqrt(math.max(0.0, tr * tr / 4 - det));
    final l1 = tr / 2 - disc; // smaller eigenvalue -> major axis
    final l2 = tr / 2 + disc;
    majA = 1 / math.sqrt(math.max(1e-9, l1));
    minB = 1 / math.sqrt(math.max(1e-9, l2));
    double ex, ey;
    if (s12.abs() > 1e-12) {
      ex = l1 - s22;
      ey = s12;
    } else if (s11 <= s22) {
      ex = 1;
      ey = 0;
    } else {
      ex = 0;
      ey = 1;
    }
    final el = math.sqrt(ex * ex + ey * ey);
    ux = ex / el;
    uy = ey / el;
    ang = math.atan2(uy, ux);
  }

  /// Length of the un-normalised normal at the centre of the projected
  /// ellipse (exact) and its mean value on the rim. The shading interpolates
  /// between them by the radial coordinate, which stays exact for spheres and
  /// is good for elongated ellipsoids seen end-on (where a single constant
  /// made the centre far too dark).
  double get normC {
    final sq = math.sqrt(qzz);
    final qpx = qx / sq, qpy = qy / sq;
    return math.sqrt(qpx * qpx + qpy * qpy + qzz);
  }

  double get normR => math.sqrt(0.5 * (1 / (majA * majA) + 1 / (minB * minB)));
}

class EllipsoidItem extends Item {
  V3 c = V3.zero;

  /// Semi-axis vectors (world, mutually orthogonal).
  V3 a1 = V3.unitX, a2 = V3.unitY, a3 = V3.unitZ;
  MatKind mat;
  EllipsoidItem(super.name, this.mat);

  /// Optional cuts in local unit-sphere space (u = coefficients of
  /// a1,a2,a3): cut k keeps u.cutD[k] < cutH[k] (cutKeepLess[k]) or > cutH[k].
  /// Used to render overlapping torso pieces as an exact union (each piece is
  /// cut where it meets its neighbour, so no internal outlines show).
  V3? cutD;
  double cutH = 0;
  bool cutKeepLess = true;
  V3? cut2D;
  double cut2H = 0;
  bool cut2KeepLess = true;

  /// Scale of the rim-light passes (pieces that mostly show internal edges
  /// get less, so their outlines do not read as seams).
  double rimScale = 1;

  void set(V3 center, V3 x, V3 y, V3 z) {
    c = center;
    a1 = x;
    a2 = y;
    a3 = z;
  }

  V3 _cv = V3.zero, _v1 = V3.unitX, _v2 = V3.unitY, _v3 = V3.unitZ;
  final _EllGeom _g = _EllGeom();

  @override
  void prepare(RenderCtx ctx) {
    _cv = ctx.cam.toView(c);
    depth = _cv.z;
    _v1 = ctx.cam.rot(a1);
    _v2 = ctx.cam.rot(a2);
    _v3 = ctx.cam.rot(a3);
    _g.compute(_v1, _v2, _v3);
    final half = math.max(0.0, _g.majA - _g.minB);
    setCore(_cv.x - _g.ux * half, _cv.y - _g.uy * half, _cv.z,
        _cv.x + _g.ux * half, _cv.y + _g.uy * half, _cv.z, _g.minB);
    minX = _cv.x - _g.majA;
    maxX = _cv.x + _g.majA;
    minY = _cv.y - _g.majA;
    maxY = _cv.y + _g.majA;
  }

  @override
  double frontZ(double px, double py) {
    final g = _g;
    final dx = px - _cv.x, dy = py - _cv.y;
    final rho2 = dx * (g.s11 * dx + g.s12 * dy) + dy * (g.s12 * dx + g.s22 * dy);
    if (rho2 > 1) return double.nan;
    final lin = -(g.qx * dx + g.qy * dy) / g.qzz;
    final z = _cv.z + lin + math.sqrt(1 - rho2) / math.sqrt(g.qzz);
    final cd = cutD, cd2 = cut2D;
    if (cd != null || cd2 != null) {
      // local coordinate of the surface point along the cut direction
      final x = V3(dx, dy, z - _cv.z);
      final u = V3(x.dot(_v1) / _v1.length2, x.dot(_v2) / _v2.length2,
          x.dot(_v3) / _v3.length2);
      if (cd != null) {
        final val = u.dot(cd);
        if (cutKeepLess ? val > cutH : val < cutH) return double.nan;
      }
      if (cd2 != null) {
        final val = u.dot(cd2);
        if (cut2KeepLess ? val > cut2H : val < cut2H) return double.nan;
      }
    }
    return z;
  }

  final List<Color> _cols = List.filled(11, const Color(0xFF000000));
  final ui.Path _region = ui.Path();
  final ui.Path _region2 = ui.Path();
  final Float64List _m4 = Float64List(16);

  @override
  void paint(ui.Canvas canvas, RenderCtx ctx) {
    final g = _g;
    final s = ctx.cam.pxScale(_cv.z);
    final sc = ctx.cam.toScreen(_cv);
    final st = ctx.style;
    final al = ctx.albedo(mat);
    final isProp = mat == MatKind.prop;
    // n_un = (S d + q' w, sqrt(Qzz) w) ; normalisation N (approximate)
    final sq = math.sqrt(g.qzz);
    final qpx = g.qx / sq, qpy = g.qy / sq;
    final nC = g.normC, nR = g.normR;
    final kx = st.k.x, ky = st.k.y, kz = st.k.z;
    // the linear (K_xy . S d) part matters toward the rim: rim normalisation
    final gx = (g.s11 * kx + g.s12 * ky) / nR; // linear part gradient (view)
    final gy = (g.s12 * kx + g.s22 * ky) / nR;
    final m = math.sqrt(math.max(
            0.0, kx * (g.s11 * kx + g.s12 * ky) + ky * (g.s12 * kx + g.s22 * ky))) /
        nR;
    final cw0 = kx * qpx + ky * qpy + kz * sq;
    for (var i = 0; i < RenderCtx.radialStops.length; i++) {
      final rho = RenderCtx.radialStops[i];
      final w = math.sqrt(math.max(0.0, 1 - rho * rho));
      final nN = math.sqrt(w * w * nC * nC + rho * rho * nR * nR);
      final nz = (sq * w / nN).clamp(0.0, 1.0);
      final e = 1 - nz;
      var inten = st.ambient - m + cw0 * w / nN - st.edgeDark * e * e;
      if (isProp) inten = 0.25 + 1.25 * (inten - 0.25);
      final rim = st.rimStrength * rimScale * st.rimUniform * e * e * e;
      _cols[i] = Color.fromARGB(
          255,
          _c(al.r * inten + st.rim.r * rim),
          _c(al.g * inten + st.rim.g * rim),
          _c(al.b * inten + st.rim.b * rim));
    }
    // unit circle -> screen ellipse
    final aPx = g.majA * s, bPx = g.minB * s;
    final th = -g.ang;
    final ct = math.cos(th), stt = math.sin(th);
    final m4 = _m4;
    m4.fillRange(0, 16, 0);
    m4[0] = aPx * ct;
    m4[1] = aPx * stt;
    m4[4] = -bPx * stt;
    m4[5] = bPx * ct;
    m4[10] = 1;
    m4[12] = sc.dx;
    m4[13] = sc.dy;
    m4[15] = 1;

    // region to fill: a cut region (screen space) or the whole ellipse, drawn
    // as the unit circle under the ellipse transform (no path allocation)
    ui.Path? region;
    ui.Path? clip;
    final cd = cutD;
    if (cd != null) {
      final res = ellipsoidCutRegion(
          _region, sc, s, _v1, _v2, _v3, cd, cutH, cutKeepLess);
      if (res == 0) return;
      if (res == 2) region = _region;
    }
    final cd2 = cut2D;
    if (cd2 != null) {
      final res = ellipsoidCutRegion(
          _region2, sc, s, _v1, _v2, _v3, cd2, cut2H, cut2KeepLess);
      if (res == 0) return;
      if (res == 2) {
        if (region == null) {
          region = _region2;
        } else {
          clip = _region2;
        }
      }
    }
    if (clip != null) {
      canvas.save();
      canvas.clipPath(clip);
    }
    final Float64List? mat4 = region == null ? null : m4;
    void draw(Paint p) {
      if (region != null) {
        canvas.drawPath(region, p);
      } else {
        canvas.drawCircle(Offset.zero, 1, p);
      }
    }

    if (region == null) {
      canvas.save();
      canvas.transform(m4);
    }
    ctx.fill.color = const Color(0xFF000000);
    ctx.fill.shader = ui.Gradient.radial(
        Offset.zero, 1.0, _cols, RenderCtx.radialStops, TileMode.clamp, mat4);
    draw(ctx.fill);

    // linear part in unit space: grad_u = E^T g_s
    final gsx = gx / s, gsy = -gy / s; // per screen px
    final gux = aPx * (ct * gsx + stt * gsy);
    final guy = bPx * (-stt * gsx + ct * gsy);
    final gl = math.sqrt(gux * gux + guy * guy);
    final lk = isProp ? 1.25 : 1.0;
    if (gl > 1e-9 && m > 1e-6) {
      final ux = gux / gl, uy = guy / gl;
      final top = Color.fromARGB(255, _c(al.r * 2 * m * lk),
          _c(al.g * 2 * m * lk), _c(al.b * 2 * m * lk));
      ctx.plus.shader = ui.Gradient.linear(Offset(-ux, -uy), Offset(ux, uy),
          [const Color(0xFF000000), top], null, TileMode.clamp, mat4);
      draw(ctx.plus);
    }
    if (st.rimStrength > 0 && rimScale > 0.5) {
      final rx = st.rimDirX, ry = -st.rimDirY;
      var lx = aPx * (ct * rx + stt * ry), ly = bPx * (-stt * rx + ct * ry);
      final ll = math.sqrt(lx * lx + ly * ly);
      lx /= ll;
      ly /= ll;
      ctx.setCrescent(Offset(-0.35 * lx, -0.35 * ly), 1.35, mat4);
      draw(ctx.plus);
    }
    if (region == null) canvas.restore();
    if (clip != null) canvas.restore();
  }

  static int _c(double v) => v <= 0 ? 0 : (v >= 1 ? 255 : (v * 255).round());
}
