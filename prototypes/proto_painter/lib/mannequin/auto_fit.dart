import 'dart:math' as math;
import 'dart:ui';

import 'camera.dart';
import 'exercise_animation.dart';
import 'mannequin_renderer.dart';
import 'math3d.dart';

/// How the camera frames an animation.
enum FitMode {
  /// Default. One scale for the whole loop (the bounding volume of all
  /// frames plus the relevant props fits; nothing rescales between frames).
  /// The scale is the minimum over a +-[MannequinFitData.yawWindow] window
  /// around the yaw, so end-on views of horizontal skills are not left tiny;
  /// while dragging it is frozen at the drag-start value (it only shrinks if
  /// the figure would otherwise leave the view) and eases to the new value
  /// when the drag ends.
  loop,

  /// Scale and centre follow the action: a time-local window of the loop,
  /// smoothed over time, never showing more than the loop bounds. The scale
  /// is yaw-invariant.
  follow,

  /// Fit only the displayed pose at the current yaw (static thumbnails).
  pose,
}

/// Precomputed per-animation data for the auto-fit (sampled body volume over
/// the loop, grip props, floor contact) and the rotation pivot, plus the
/// camera-dependent fit caches.
class MannequinFitData {
  /// Body points (+ radii) of all samples, concatenated; sample i owns
  /// [sampleStart[i], sampleStart[i + 1]).
  final List<V3> points = [];
  final List<double> radii = [];
  final List<int> sampleStart = [];
  final List<double> sampleTimes = [];

  /// Prop geometry that must stay in frame (grip region, posts...).
  final List<V3> staticPoints = [];
  final List<double> staticRadii = [];

  V3 pivot = V3.zero;
  double radius = 40;
  double duration = 1;

  /// Half-width (in samples; 8 samples per transition) of the follow window.
  static const int window = 4;

  /// Temporal smoothing of the follow fit (Gaussian sigma, in samples).
  static const double sigma = 2.5;

  /// Yaw samples used for the scale (15 degree steps).
  static const int yawSteps = 24;

  /// Half-width (degrees) of the yaw window whose minimum scale is used.
  static const double yawWindow = 40;

  /// No animation is drawn larger than a standing figure: the scale is
  /// clamped to fill * min(w, h) / [refHeight] (world units).
  static const double refHeight = 78;

  MannequinFitData(ExerciseAnimation anim) {
    final r = MannequinRenderer();
    r.setProps(anim.props, anim.floorY);
    final fy = r.floorY;
    final pose = Pose();
    final wrists = <V3>[];
    duration = anim.duration;
    for (final t in anim.fitSampleTimes()) {
      anim.sampleInto(t, pose);
      r.setPose(pose, anim.anchor);
      sampleStart.add(points.length);
      sampleTimes.add(t);
      final n0 = points.length;
      r.collectFitPoints(points, radii);
      if (fy != null) {
        // floor contact + contact-shadow margin under low body parts
        final n1 = points.length;
        for (var i = n0; i < n1; i++) {
          final p = points[i];
          if (p.y - radii[i] - fy < 8) {
            points.add(V3(p.x, fy, p.z));
            radii.add(radii[i] + 2.5);
          }
        }
      }
      wrists
        ..add(r.skel.wrist[0])
        ..add(r.skel.wrist[1]);
    }
    sampleStart.add(points.length);
    r.collectPropFitPoints(wrists, staticPoints, staticRadii);

    var mn = const V3(double.infinity, double.infinity, double.infinity);
    var mx = const V3(-double.infinity, -double.infinity, -double.infinity);
    void acc(V3 p, double rr) {
      mn = V3(math.min(mn.x, p.x - rr), math.min(mn.y, p.y - rr), math.min(mn.z, p.z - rr));
      mx = V3(math.max(mx.x, p.x + rr), math.max(mx.y, p.y + rr), math.max(mx.z, p.z + rr));
    }

    for (var i = 0; i < points.length; i++) {
      acc(points[i], radii[i]);
    }
    for (var i = 0; i < staticPoints.length; i++) {
      acc(staticPoints[i], staticRadii[i]);
    }
    pivot = (mn + mx) * 0.5;
    radius = (mx - mn).length / 2;
    final n = sampleCount;
    _bx0 = List.filled(n, 0);
    _bx1 = List.filled(n, 0);
    _by0 = List.filled(n, 0);
    _by1 = List.filled(n, 0);
    _kSample = List.filled(n, 1);
    _cx = List.filled(n, 0);
    _cy = List.filled(n, 0);
  }

  int get sampleCount => sampleTimes.length;

  // ---------------------------------------------------------------- caches
  late List<double> _bx0, _bx1, _by0, _by1; // per-sample boxes (scratch)
  late List<double> _kSample; // yaw-invariant scale per sample window
  final List<double> _kYaw = List.filled(yawSteps, 1); // loop scale per yaw sample
  late List<double> _cx, _cy; // window centres at the cached yaw
  double _kUnion = 1;
  double _ucx = 0, _ucy = 0;
  final List<double> _scaleKey = List.filled(5, double.nan);
  final List<double> _centreKey = List.filled(3, double.nan);
  final ViewCam _tmp = ViewCam();

  // bbox accumulator
  double _x0 = 0, _x1 = 0, _y0 = 0, _y1 = 0;
  void _reset() {
    _x0 = _y0 = double.infinity;
    _x1 = _y1 = -double.infinity;
  }

  void _add(ViewCam cam, V3 p, double r) {
    final v = cam.toView(p);
    final f = cam.persFactor(v.z);
    final a = (v.x - r) * f, b = (v.x + r) * f;
    final c = (v.y - r) * f, d = (v.y + r) * f;
    if (a < _x0) _x0 = a;
    if (b > _x1) _x1 = b;
    if (c < _y0) _y0 = c;
    if (d > _y1) _y1 = d;
  }

  /// Per-sample boxes (each including the static props) under [cam].
  void _sampleBoxes(ViewCam cam) {
    _reset();
    for (var j = 0; j < staticPoints.length; j++) {
      _add(cam, staticPoints[j], staticRadii[j]);
    }
    final sx0 = _x0, sx1 = _x1, sy0 = _y0, sy1 = _y1;
    for (var i = 0; i < sampleCount; i++) {
      _x0 = sx0;
      _x1 = sx1;
      _y0 = sy0;
      _y1 = sy1;
      for (var j = sampleStart[i]; j < sampleStart[i + 1]; j++) {
        _add(cam, points[j], radii[j]);
      }
      _bx0[i] = _x0;
      _bx1[i] = _x1;
      _by0[i] = _y0;
      _by1[i] = _y1;
    }
  }

  /// Union of the sample boxes in the window around sample i (into _x0..).
  void _window(int i) {
    final n = sampleCount;
    _reset();
    final w = math.min(window, (n - 1) ~/ 2);
    for (var o = -w; o <= w; o++) {
      final j = ((i + o) % n + n) % n;
      if (_bx0[j] < _x0) _x0 = _bx0[j];
      if (_bx1[j] > _x1) _x1 = _bx1[j];
      if (_by0[j] < _y0) _y0 = _by0[j];
      if (_by1[j] > _y1) _y1 = _by1[j];
    }
  }

  void _union() {
    _reset();
    for (var j = 0; j < sampleCount; j++) {
      if (_bx0[j] < _x0) _x0 = _bx0[j];
      if (_bx1[j] > _x1) _x1 = _bx1[j];
      if (_by0[j] < _y0) _y0 = _by0[j];
      if (_by1[j] > _y1) _y1 = _by1[j];
    }
  }

  double _scaleOf(Size size) => math.min(size.width / math.max(1e-3, _x1 - _x0),
      size.height / math.max(1e-3, _y1 - _y0));

  bool _keyChanged(List<double> key, List<double> v) {
    var changed = false;
    for (var i = 0; i < v.length; i++) {
      if (key[i] != v[i]) {
        key[i] = v[i];
        changed = true;
      }
    }
    return changed;
  }

  /// Yaw-invariant scales (min over yaw samples) for the current pitch/size.
  void _ensureScale(ViewCam cam, Size size, double fill) {
    if (!_keyChanged(_scaleKey, [cam.pitchDeg, size.width, size.height, cam.persp, fill])) {
      return;
    }
    final n = sampleCount;
    for (var i = 0; i < n; i++) {
      _kSample[i] = double.infinity;
    }
    var ku = double.infinity;
    _tmp
      ..pivot = pivot
      ..persp = cam.persp
      ..k = 1;
    for (var m = 0; m < yawSteps; m++) {
      _tmp.setAngles(360.0 * m / yawSteps, cam.pitchDeg);
      _sampleBoxes(_tmp);
      for (var i = 0; i < n; i++) {
        _window(i);
        _kSample[i] = math.min(_kSample[i], _scaleOf(size));
      }
      _union();
      _kYaw[m] = fill * _scaleOf(size);
      ku = math.min(ku, _scaleOf(size));
    }
    _kUnion = fill * ku;
    for (var i = 0; i < n; i++) {
      _kSample[i] = math.max(_kUnion, fill * _kSample[i]);
    }
  }

  /// Loop scale at [yaw] (piecewise linear between the yaw samples).
  double _kYawAt(double yaw) {
    const step = 360.0 / yawSteps;
    final f = yaw / step;
    final i = f.floor();
    final u = f - i;
    final a = _kYaw[((i % yawSteps) + yawSteps) % yawSteps];
    final b = _kYaw[(((i + 1) % yawSteps) + yawSteps) % yawSteps];
    return a + (b - a) * u;
  }

  /// Minimum loop scale over the yaw window around [yaw] (continuous in yaw).
  double windowScale(double yaw) {
    const step = 360.0 / yawSteps;
    var k = math.min(_kYawAt(yaw - yawWindow), _kYawAt(yaw + yawWindow));
    final lo = ((yaw - yawWindow) / step).ceil(), hi = ((yaw + yawWindow) / step).floor();
    for (var i = lo; i <= hi; i++) {
      k = math.min(k, _kYaw[((i % yawSteps) + yawSteps) % yawSteps]);
    }
    return k;
  }

  /// Upper bound of the scale (a standing figure fills [fill] of the view).
  static double refScale(Size size, double fill) =>
      fill * math.min(size.width, size.height) / refHeight;

  /// Window centres (view units) at the current yaw/pitch.
  void _ensureCentres(ViewCam cam) {
    if (!_keyChanged(_centreKey, [cam.yawDeg, cam.pitchDeg, cam.persp])) return;
    _sampleBoxes(cam);
    for (var i = 0; i < sampleCount; i++) {
      _window(i);
      _cx[i] = (_x0 + _x1) / 2;
      _cy[i] = (_y0 + _y1) / 2;
    }
    _union();
    _ucx = (_x0 + _x1) / 2;
    _ucy = (_y0 + _y1) / 2;
  }

  /// Sets cam.k / ox / oy. [posePts]/[poseRadii]: the displayed pose (used by
  /// [FitMode.pose] and to guarantee that [FitMode.follow] keeps it in view).
  ///
  /// [FitMode.loop] only: [scaleFromYaw] is the yaw at which the current drag
  /// started (null when idle). With [scaleBlend] = 0 (dragging) the scale is
  /// min(window scale at scaleFromYaw, window scale now): frozen, shrinking
  /// only if needed; [scaleBlend] going 0 -> 1 after the drag eases it to the
  /// window scale at the current yaw.
  void apply(ViewCam cam, Size size, double t, FitMode mode, double fill,
      List<V3> posePts, List<double> poseRadii,
      {double? scaleFromYaw, double scaleBlend = 1}) {
    double k, cx, cy;
    final kRef = refScale(size, fill);
    if (mode == FitMode.pose || sampleCount == 0) {
      _reset();
      for (var j = 0; j < staticPoints.length; j++) {
        _add(cam, staticPoints[j], staticRadii[j]);
      }
      for (var j = 0; j < posePts.length; j++) {
        _add(cam, posePts[j], poseRadii[j]);
      }
      if (!_x0.isFinite) {
        cam
          ..k = 1
          ..ox = size.width / 2
          ..oy = size.height / 2;
        return;
      }
      k = math.min(kRef, fill * _scaleOf(size));
      cx = (_x0 + _x1) / 2;
      cy = (_y0 + _y1) / 2;
    } else {
      _ensureScale(cam, size, fill);
      _ensureCentres(cam);
      if (mode == FitMode.loop || sampleCount == 1) {
        final kNow = windowScale(cam.yawDeg);
        k = kNow;
        if (scaleFromYaw != null) {
          final k0 = math.min(windowScale(scaleFromYaw), kNow);
          final b = scaleBlend.clamp(0.0, 1.0);
          k = math.exp(math.log(k0) + (math.log(kNow) - math.log(k0)) * b);
        }
        k = math.min(k, kRef);
        cx = _ucx;
        cy = _ucy;
      } else {
        final n = sampleCount;
        var u = (t / duration) % 1.0;
        if (u < 0) u += 1;
        final pos = u * n;
        var ws = 0.0, lk = 0.0, sx = 0.0, sy = 0.0;
        for (var i = 0; i < n; i++) {
          var d = pos - i;
          d -= n * (d / n).roundToDouble();
          final w = math.exp(-d * d / (2 * sigma * sigma));
          ws += w;
          lk += w * math.log(_kSample[i]);
          sx += w * _cx[i];
          sy += w * _cy[i];
        }
        k = math.min(kRef, math.max(_kUnion, math.exp(lk / ws)));
        cx = sx / ws;
        cy = sy / ws;
      }
    }
    var ox = size.width / 2 - k * cx;
    var oy = size.height / 2 + k * cy;
    if (mode == FitMode.follow && posePts.isNotEmpty) {
      // keep the displayed pose inside the viewport (rarely active)
      _reset();
      for (var j = 0; j < posePts.length; j++) {
        _add(cam, posePts[j], poseRadii[j]);
      }
      final mX = size.width * 0.03, mY = size.height * 0.03;
      final bw = _x1 - _x0, bh = _y1 - _y0;
      if (k * bw > size.width - 2 * mX) {
        k = (size.width - 2 * mX) / bw;
        ox = size.width / 2 - k * (_x0 + _x1) / 2;
        oy = size.height / 2 + k * cy;
      }
      if (k * bh > size.height - 2 * mY) {
        k = (size.height - 2 * mY) / bh;
        ox = size.width / 2 - k * cx;
        oy = size.height / 2 + k * (_y0 + _y1) / 2;
      }
      final left = ox + k * _x0, right = ox + k * _x1;
      if (left < mX) ox += mX - left;
      if (right > size.width - mX) ox -= right - (size.width - mX);
      final top = oy - k * _y1, bottom = oy - k * _y0;
      if (top < mY) oy += mY - top;
      if (bottom > size.height - mY) oy -= bottom - (size.height - mY);
    }
    cam
      ..k = k
      ..ox = ox
      ..oy = oy;
  }
}
