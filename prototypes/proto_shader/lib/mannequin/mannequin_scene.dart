import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'exercise_animation.dart';
import 'rig.dart';

/// Camera looking at the figure. yaw 0 = side view (camera on +z), positive
/// yaw swings the camera toward +x (the figure's front), 90 = front view.
/// pitch > 0 = looking from above.
class OrbitCamera {
  /// Narrow field of view = mild perspective (near limbs are not blown up
  /// when the camera looks along a horizontal body).
  static const double fovYDeg = 10;
  static final double focal = 1 / math.tan(fovYDeg * math.pi / 360);

  final V3 pos = V3(), right = V3(), up = V3(), fwd = V3(), back = V3();
  final V3 target = V3();
  double distance = 100;
  double yaw = 30, pitch = 12, aspect = 1;

  void setAngles(double yawDeg, double pitchDeg) {
    yaw = yawDeg;
    pitch = pitchDeg;
    final y = yawDeg * math.pi / 180, p = pitchDeg * math.pi / 180;
    back.set(math.sin(y) * math.cos(p), math.sin(p), math.cos(y) * math.cos(p));
    fwd.set(-back.x, -back.y, -back.z);
    right.set(math.cos(y), 0, -math.sin(y));
    up.setCross(right, fwd);
  }

  void place() => pos.setAddScaled(target, back, distance);
}

/// Render quality tiers (march step budget, AO taps, interior edge AA).
enum MannequinQuality {
  low(48, 2, 0),
  medium(64, 3, 1),
  high(80, 4, 1);

  final int maxSteps, aoTaps, interiorEdges;
  const MannequinQuality(this.maxSteps, this.aoTaps, this.interiorEdges);
}

/// Everything needed to render one exercise: rig, props, camera framing and
/// the uniform layout of `shaders/mannequin.frag`.
///
/// Framing: the projected bounding box over ALL frames of the animation is
/// fitted for the current yaw / pitch (so the figure fills ~85 % of the view
/// and never rescales between frames). While the user drags, the view blends
/// to a yaw-invariant framing (fixed target, the distance that fits every
/// yaw) so rotating never zooms; it eases back to the per-yaw framing after
/// release. With [fitPoseTime] the fit covers only that pose (thumbnails).
class MannequinScene {
  final ExerciseAnimation animation;
  final SceneProps props;
  late final MannequinRig rig;
  final OrbitCamera camera = OrbitCamera();

  /// Fit only the pose at this time (seconds) for the exact yaw (thumbnails).
  final double? fitPoseTime;

  final Float64List _angles = Float64List(PoseChannel.count);
  final Float64List _at = Float64List(3);

  /// Fit points over the whole animation (or [fitPoseTime]): x, y, z, radius.
  late final Float64List _fitPts;

  /// Figure-only extents over the animation (x, y, z) -> view hints.
  double _ex = 0, _ey = 0, _ez = 0;

  /// Largest |torso up . world up| over the animation (0 = always horizontal).
  double _maxTorsoUp = 1;

  /// Floor "stage" centre (x, z) and radius for the floor spot / fade.
  double stageX = 0, stageZ = 0, stageR = 60;

  final _UniformWriter _writer = _UniformWriter();
  final Map<int, Float64List> _fitCache = {};
  final Float64List _rest = Float64List(4);
  double _restYaw = double.nan, _restPitch = double.nan, _restAspect = double.nan;
  double _lastYaw = double.nan,
      _lastPitch = double.nan,
      _lastFitYaw = double.nan,
      _lastFitPitch = double.nan,
      _lastAspect = double.nan,
      _lastBlend = double.nan;

  /// Fraction of the viewport the figure should fill.
  static const double fill = 0.85;

  /// Yaw step of the framing sweep.
  static const double yawSweepStep = 15;

  MannequinScene(this.animation, {this.fitPoseTime}) : props = SceneProps.from(animation.props) {
    rig = MannequinRig(props);
    _buildFitPoints();
  }

  void pose(double seconds) {
    animation.sample(seconds, _angles, _at);
    rig.solve(_angles, animation.anchor, _at);
  }

  /// True when the torso stays roughly horizontal for the whole animation
  /// (levers incl. tucks, planche, flag) or the figure is long and flat
  /// along x: the front view (yaw ~90) looks down the body.
  bool get isHorizontalBody => _maxTorsoUp < 0.5 || (_ex > 1.25 * _ey && _ex > 1.25 * _ez);

  /// Default yaw for this exercise (fixture hint, else 35 for horizontal
  /// bodies, else 30).
  double get preferredYaw => animation.view?.yaw ?? (isHorizontalBody ? 35 : 30);

  /// Yaw window (degrees, applied mod 180) the interactive view snaps out of
  /// after a drag, or null.
  (double, double)? get avoidYaw {
    final v = animation.view;
    if (v?.avoidFrom != null && v?.avoidTo != null) return (v!.avoidFrom!, v.avoidTo!);
    return isHorizontalBody ? (72.0, 108.0) : null;
  }

  /// Nearest yaw outside [avoidYaw] (identity when not inside it).
  double snapYaw(double yaw) {
    final w = avoidYaw;
    if (w == null) return yaw;
    final m = yaw - 180.0 * (yaw / 180.0).floor(); // [0, 180)
    if (m <= w.$1 || m >= w.$2) return yaw;
    return (m - w.$1 < w.$2 - m) ? yaw - (m - w.$1) : yaw + (w.$2 - m);
  }

  void _buildFitPoints() {
    final pts = <double>[];
    final single = fitPoseTime != null;
    final n = single || animation.frames.length <= 1 ? 1 : animation.transitionCount;
    final sub = single ? 1 : 4;
    var minX = 1e9, minY = 1e9, maxX = -1e9, maxY = -1e9, minZ = 1e9, maxZ = -1e9;
    var sx = 0.0, sz = 0.0, cnt = 0;
    var maxTy = 0.0;
    for (var k = 0; k < n; k++) {
      for (var s = 0; s < sub; s++) {
        pose(single ? fitPoseTime! : (k + s / sub) * animation.transitionSeconds);
        if (cnt == 0 && props.hasWall) {
          props.wallSide = rig.hip.x < props.wallX ? -1 : 1;
        }
        rig.forEachFitPoint((x, y, z, r) {
          pts.addAll([x, y, z, r]);
          minX = math.min(minX, x - r);
          maxX = math.max(maxX, x + r);
          minY = math.min(minY, y - r);
          maxY = math.max(maxY, y + r);
          minZ = math.min(minZ, z - r);
          maxZ = math.max(maxZ, z + r);
        });
        sx += rig.hip.x;
        sz += rig.hip.z;
        maxTy = math.max(maxTy, rig.T.y.abs());
        cnt++;
      }
    }
    if (single) {
      // view hints still come from the whole animation
      final full = MannequinScene(animation);
      _ex = full._ex;
      _ey = full._ey;
      _ez = full._ez;
      _maxTorsoUp = full._maxTorsoUp;
    } else {
      _ex = maxX - minX;
      _ey = maxY - minY;
      _ez = maxZ - minZ;
      _maxTorsoUp = maxTy;
    }
    stageX = sx / cnt;
    stageZ = sz / cnt;
    stageR = 18 + 0.5 * math.max(maxX - minX, maxZ - minZ);
    void add(double x, double y, double z, double r) => pts.addAll([x, y, z, r]);
    if (props.hasBar) {
      for (final z in [-10.0, 0.0, 10.0]) {
        add(props.barX, props.barY, z, 1.4);
      }
    }
    if (props.hasPbars) {
      final x0 = math.max(props.pbX1, minX - 6), x1 = math.min(props.pbX2, maxX + 6);
      for (final z in [props.pbZ, -props.pbZ]) {
        add(x0, props.pbY, z, 1.2);
        add(x1, props.pbY, z, 1.2);
      }
    }
    if (props.hasPole) {
      add(props.poleX, minY - 2, props.poleZ, 1.4);
      add(props.poleX, maxY + 2, props.poleZ, 1.4);
    }
    if (props.hasBox) {
      for (final x in [props.boxX0, props.boxX1]) {
        for (final y in [props.boxY0, props.boxY1]) {
          for (final z in [-props.boxZ, props.boxZ]) {
            add(x, y, z, 0);
          }
        }
      }
    }
    // Ground: show it (and where posts stand on it) when it is close enough
    // to the figure; otherwise it stays out of frame (the pole / posts fade
    // out at the bottom border instead of shrinking the figure).
    final groundGap = minY - props.groundY;
    final showGround = props.hasGround && (groundGap < 14 || (props.hasPbars && groundGap < 24));
    props.groundInFit = showGround;
    if (showGround) {
      for (final z in [-7.0, 7.0]) {
        add(minX - 2, props.groundY, z, 0);
        add(maxX + 2, props.groundY, z, 0);
      }
      if (props.hasPbars) {
        final x0 = math.max(props.pbX1, minX - 6) + 2.5, x1 = math.min(props.pbX2, maxX + 6) - 2.5;
        for (final z in [props.pbZ, -props.pbZ]) {
          add(x0, props.groundY, z, 1);
          add(x1, props.groundY, z, 1);
        }
      }
      if (props.hasPole) add(props.poleX, props.groundY, props.poleZ, 2);
    }
    if (props.hasWall) {
      final gap = props.wallSide < 0 ? props.wallX - maxX : minX - props.wallX;
      if (gap < 15) {
        add(props.wallX, minY, 0, 0);
        add(props.wallX, maxY, 0, 0);
      }
    }
    _fitPts = Float64List.fromList(pts);
  }

  /// Positions the camera at ([yaw], [pitch]). The framing (look-at target
  /// and distance) is the per-yaw fit for [fitYaw] / [fitPitch] (default:
  /// the view angles) blended with the yaw-invariant framing by [blend]:
  /// 0 = per-yaw (rest, static renders), 1 = yaw-invariant (while dragging).
  void fit(double yaw, double pitch, double aspect, {double? fitYaw, double? fitPitch, double blend = 0}) {
    final fy = fitYaw ?? yaw;
    final fp = fitPitch ?? pitch;
    if (yaw == _lastYaw &&
        pitch == _lastPitch &&
        fy == _lastFitYaw &&
        fp == _lastFitPitch &&
        aspect == _lastAspect &&
        blend == _lastBlend) {
      return;
    }
    _lastYaw = yaw;
    _lastPitch = pitch;
    _lastFitYaw = fy;
    _lastFitPitch = fp;
    _lastAspect = aspect;
    _lastBlend = blend;
    var tx = 0.0, ty = 0.0, tz = 0.0, dist = 0.0;
    if (blend < 1) {
      if (fy != _restYaw || fp != _restPitch || aspect != _restAspect) {
        _restYaw = fy;
        _restPitch = fp;
        _restAspect = aspect;
        _solvePerYaw(fy, fp, aspect, _rest);
      }
      final w = 1 - blend;
      tx += _rest[0] * w;
      ty += _rest[1] * w;
      tz += _rest[2] * w;
      dist += _rest[3] * w;
    }
    if (blend > 0) {
      final key = (fp * 64).round() * 1000003 + (aspect * 4096).round();
      var fr = _fitCache[key];
      if (fr == null) {
        if (_fitCache.length > 16) _fitCache.clear();
        fr = _fitCache[key] = _solveYawInvariant(fp, aspect);
      }
      tx += fr[0] * blend;
      ty += fr[1] * blend;
      tz += fr[2] * blend;
      dist += fr[3] * blend;
    }
    final c = camera..setAngles(yaw, pitch);
    c.target.set(tx, ty, tz);
    c.distance = dist;
    c.place();
  }

  /// Per-yaw framing (target x, y, z, distance) for this yaw / pitch.
  Float64List framingFor(double yaw, double pitch, double aspect) {
    final out = Float64List(4);
    _solvePerYaw(yaw, pitch, aspect, out);
    return out;
  }

  /// Yaw-invariant framing (target x, y, z, distance) used while dragging.
  Float64List invariantFraming(double pitch, double aspect) => _solveYawInvariant(pitch, aspect);

  /// Fixed target (centre of the fit points' vertical bounding cylinder,
  /// vertically balanced) + the largest distance any yaw needs.
  Float64List _solveYawInvariant(double pitch, double aspect) {
    final p = _fitPts;
    final n = p.length ~/ 4;
    final f = OrbitCamera.focal;
    var x0 = 1e9, x1 = -1e9, y0 = 1e9, y1 = -1e9, z0 = 1e9, z1 = -1e9;
    for (var i = 0; i < n; i++) {
      final x = p[i * 4], y = p[i * 4 + 1], z = p[i * 4 + 2], r = p[i * 4 + 3];
      x0 = math.min(x0, x - r);
      x1 = math.max(x1, x + r);
      y0 = math.min(y0, y - r);
      y1 = math.max(y1, y + r);
      z0 = math.min(z0, z - r);
      z1 = math.max(z1, z + r);
    }
    final tx = (x0 + x1) / 2, tz = (z0 + z1) / 2;
    var ty = (y0 + y1) / 2;
    final c = OrbitCamera();
    var dist = 0.0;
    for (var iter = 0; iter < 3; iter++) {
      dist = 0;
      for (var yaw = 0.0; yaw < 360; yaw += yawSweepStep) {
        c.setAngles(yaw, pitch);
        for (var i = 0; i < n; i++) {
          final x = p[i * 4] - tx, y = p[i * 4 + 1] - ty, z = p[i * 4 + 2] - tz, r = p[i * 4 + 3];
          final u = x * c.right.x + z * c.right.z;
          final v = x * c.up.x + y * c.up.y + z * c.up.z;
          final w = x * c.back.x + y * c.back.y + z * c.back.z;
          dist = math.max(dist, w + f * (u.abs() + r) / (fill * aspect));
          dist = math.max(dist, w + f * (v.abs() + r) / fill);
        }
      }
      // balance the vertical margins over all yaws
      var vMin = 1e9, vMax = -1e9;
      for (var yaw = 0.0; yaw < 360; yaw += yawSweepStep) {
        c.setAngles(yaw, pitch);
        for (var i = 0; i < n; i++) {
          final x = p[i * 4] - tx, y = p[i * 4 + 1] - ty, z = p[i * 4 + 2] - tz, r = p[i * 4 + 3];
          final v = x * c.up.x + y * c.up.y + z * c.up.z;
          final w = x * c.back.x + y * c.back.y + z * c.back.z;
          final s = f / (dist - w);
          vMin = math.min(vMin, (v - r) * s);
          vMax = math.max(vMax, (v + r) * s);
        }
      }
      final shift = (vMin + vMax) / 2 * dist / f;
      if (shift.abs() < 0.05) break;
      ty += shift / math.max(0.3, math.cos(pitch * math.pi / 180));
    }
    return Float64List.fromList([tx, ty, tz, dist]);
  }

  final OrbitCamera _fitCam = OrbitCamera();

  /// Per-yaw fit, re-centred on the projected extent at this yaw: writes the
  /// target (x, y, z) and the distance into [out].
  void _solvePerYaw(double yaw, double pitch, double aspect, Float64List out) {
    final c = _fitCam..setAngles(yaw, pitch);
    final f = OrbitCamera.focal;
    final p = _fitPts;
    final n = p.length ~/ 4;
    var uMin = 1e9, uMax = -1e9, vMin = 1e9, vMax = -1e9, wMin = 1e9, wMax = -1e9;
    for (var i = 0; i < n; i++) {
      final x = p[i * 4], y = p[i * 4 + 1], z = p[i * 4 + 2], r = p[i * 4 + 3];
      final u = x * c.right.x + y * c.right.y + z * c.right.z;
      final v = x * c.up.x + y * c.up.y + z * c.up.z;
      final w = x * c.back.x + y * c.back.y + z * c.back.z;
      uMin = math.min(uMin, u - r);
      uMax = math.max(uMax, u + r);
      vMin = math.min(vMin, v - r);
      vMax = math.max(vMax, v + r);
      wMin = math.min(wMin, w);
      wMax = math.max(wMax, w);
    }
    var uc = (uMin + uMax) / 2, vc = (vMin + vMax) / 2;
    final wc = (wMin + wMax) / 2;
    var dist = 0.0;
    for (var iter = 0; iter < 4; iter++) {
      dist = 0;
      for (var i = 0; i < n; i++) {
        final x = p[i * 4], y = p[i * 4 + 1], z = p[i * 4 + 2], r = p[i * 4 + 3];
        final u = x * c.right.x + y * c.right.y + z * c.right.z - uc;
        final v = x * c.up.x + y * c.up.y + z * c.up.z - vc;
        final w = x * c.back.x + y * c.back.y + z * c.back.z - wc;
        dist = math.max(dist, w + f * (u.abs() + r) / (fill * aspect));
        dist = math.max(dist, w + f * (v.abs() + r) / fill);
      }
      var xMin = 1e9, xMax = -1e9, yMin = 1e9, yMax = -1e9;
      for (var i = 0; i < n; i++) {
        final x = p[i * 4], y = p[i * 4 + 1], z = p[i * 4 + 2], r = p[i * 4 + 3];
        final u = x * c.right.x + y * c.right.y + z * c.right.z - uc;
        final v = x * c.up.x + y * c.up.y + z * c.up.z - vc;
        final w = x * c.back.x + y * c.back.y + z * c.back.z - wc;
        final s = f / (dist - w);
        xMin = math.min(xMin, (u - r) * s);
        xMax = math.max(xMax, (u + r) * s);
        yMin = math.min(yMin, (v - r) * s);
        yMax = math.max(yMax, (v + r) * s);
      }
      uc += (xMin + xMax) / 2 * dist / f;
      vc += (yMin + yMax) / 2 * dist / f;
    }
    out[0] = c.right.x * uc + c.up.x * vc + c.back.x * wc;
    out[1] = c.right.y * uc + c.up.y * vc + c.back.y * wc;
    out[2] = c.right.z * uc + c.up.z * vc + c.back.z * wc;
    out[3] = dist;
  }

  /// Writes all uniforms (order must match the shader!).
  void writeUniforms(ui.FragmentShader s, double w, double h, double pixelsPerUnit, ui.Color bg,
      [MannequinQuality quality = MannequinQuality.medium]) {
    final u = _writer;
    u.begin(s);
    final c = camera;
    final f = OrbitCamera.focal;
    u.f2(w, h);
    u.v(c.pos, f);
    u.v(c.right, 2.0 / (h * pixelsPerUnit * f));
    final lum = 0.2126 * bg.r + 0.7152 * bg.g + 0.0722 * bg.b;
    u.v(c.up, ((lum - 0.15) / 0.6).clamp(0.0, 1.0));
    u.v(c.fwd, 0);
    u.f4(bg.r, bg.g, bg.b, 1);
    // lights: camera relative (key upper-front-left, fill right, rim behind)
    final bx = math.sin(c.yaw * math.pi / 180), bz = math.cos(c.yaw * math.pi / 180);
    _light(u, -0.62, 0.78, 0.42, bx, bz, 1.45);
    _light(u, 0.85, 0.15, 0.35, bx, bz, 0.32);
    _light(u, 0.35, 0.55, -0.85, bx, bz, 0.55);
    final r = rig;
    final bb = r.aabb;
    u.f4(bb[0], bb[1], bb[2], 0);
    u.f4(bb[3], bb[4], bb[5], 0);
    u.v(r.hip, 0);
    u.v(r.T, 0);
    u.v(r.F, 0);
    u.v(r.L, 0);
    u.v(r.neck, 0);
    u.v(r.head, 0);
    u.v(r.HU, 0);
    u.v(r.HF, 0);
    u.v(r.HL, 0);
    for (var j = J.sh1; j <= J.an2; j++) {
      u.v(r.joints[j], 0);
    }
    for (var i = 0; i < 4; i++) {
      final b = i == 0 ? r.hand1 : i == 1 ? r.hand2 : i == 2 ? r.foot1 : r.foot2;
      u.v(b.c, b.code);
      u.v(b.ax, b.ext.x);
      u.v(b.ay, b.ext.y);
      u.v(b.az, b.ext.z);
    }
    for (var i = 0; i < 24; i++) {
      u.f(r.bounds[i]);
    }
    final p = props;
    u.f4(p.groundY, p.hasGround ? 1 : 0, stageX, stageZ);
    u.f4(p.barX, p.barY, p.barHalf, p.hasBar ? 1 : 0);
    u.f4(p.pbY, p.pbX1, p.pbX2, p.hasPbars ? 1 : 0);
    u.f4(p.pbZ, p.pbFloor, 0, 0);
    u.f4(p.poleX, p.poleZ, p.poleFloor, p.hasPole ? 1 : 0);
    u.f4(p.wallX, p.wallFloor, p.wallSide, p.hasWall ? 1 : 0);
    u.f4(p.boxX0, p.boxY0, -p.boxZ, p.hasBox ? 1 : 0);
    u.f4(p.boxX1, p.boxY1, p.boxZ, 0);
    u.f4(quality.maxSteps.toDouble(), quality.aoTaps.toDouble(), quality.interiorEdges.toDouble(), stageR);
  }

  void _light(_UniformWriter u, double lx, double ly, double lz, double bx, double bz, double intensity) {
    // camera-space (x right, y world-up, z toward camera, horizontal)
    final c = camera;
    var x = c.right.x * lx + bx * lz;
    var y = ly;
    var z = c.right.z * lx + bz * lz;
    final l = math.sqrt(x * x + y * y + z * z);
    x /= l;
    y /= l;
    z /= l;
    u.f4(x, y, z, intensity);
  }
}

class _UniformWriter {
  late ui.FragmentShader s;
  int i = 0;
  void begin(ui.FragmentShader shader) {
    s = shader;
    i = 0;
  }

  void f(double v) => s.setFloat(i++, v);
  void f2(double a, double b) {
    f(a);
    f(b);
  }

  void f4(double a, double b, double c, double d) {
    f(a);
    f(b);
    f(c);
    f(d);
  }

  void v(V3 p, double w) => f4(p.x, p.y, p.z, w);
}
