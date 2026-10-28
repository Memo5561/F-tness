import 'dart:math' as math;
import 'dart:typed_data';

/// Pose keys understood by the 3D skeleton. Angles in degrees.
///  t   hip->neck line, hd neck->head (default t), tb torso lateral lean
///  ua/la upper/lower arm, th/sh thigh/shin (suffix 1 = near side, 2 = far side)
///  ...b  abduction out of the sagittal plane, away from the midline (default 0)
class PoseKeys {
  static const List<String> names = [
    't', 'hd', 'tb', //
    'ua1', 'la1', 'ua2', 'la2', 'th1', 'sh1', 'th2', 'sh2', //
    'ua1b', 'la1b', 'ua2b', 'la2b', 'th1b', 'sh1b', 'th2b', 'sh2b',
  ];
  static const int count = 19;
  static const int t = 0, hd = 1, tb = 2;
  static const int ua1 = 3, la1 = 4, ua2 = 5, la2 = 6;
  static const int th1 = 7, sh1 = 8, th2 = 9, sh2 = 10;
  static const int ua1b = 11, la1b = 12, ua2b = 13, la2b = 14;
  static const int th1b = 15, sh1b = 16, th2b = 17, sh2b = 18;
}

/// A sampled pose: angles + anchor target (2D data coords: x right, y DOWN).
class Pose {
  final Float64List a = Float64List(PoseKeys.count);
  double atX = 0, atY = 0;

  /// Optional z for the anchor (extension: 'at' with 3 numbers). NaN = keep FK z.
  double atZ = double.nan;

  void copyFrom(Pose o) {
    a.setAll(0, o.a);
    atX = o.atX;
    atY = o.atY;
    atZ = o.atZ;
  }
}

class PropSpec {
  final String kind;
  final Map<String, double> p;
  const PropSpec(this.kind, this.p);

  double get(String k, [double def = 0]) => p[k] ?? def;

  factory PropSpec.fromJson(Map<String, dynamic> j) {
    final m = <String, double>{};
    j.forEach((k, v) {
      if (v is num) m[k] = v.toDouble();
    });
    return PropSpec(j['k'] as String, m);
  }
}

class KeyFrame {
  final Pose pose;
  KeyFrame(this.pose);
}

/// Animation of one exercise: key frames, anchor joint, props and loop mode.
class ExerciseAnimation {
  final String id;
  final String anchor;
  final List<KeyFrame> frames;
  final List<PropSpec> props;

  /// 'pingpong' (0->n->0) or 'cycle' (0->n, then n->0 directly).
  final String loop;
  final double speed;

  /// Preferred initial camera yaw for this skill (optional 'yaw' in the anim
  /// JSON), e.g. ~80 for the human flag, ~25 for levers and planches.
  final double? preferredYaw;

  /// Yaw to start the view / thumbnail with.
  double get initialYaw => preferredYaw ?? 30;

  /// Base seconds per frame transition at speed 1.
  static const double baseTransitionSeconds = 1.5;

  ExerciseAnimation({
    this.id = '',
    required this.anchor,
    required this.frames,
    this.props = const [],
    this.loop = 'pingpong',
    this.speed = 1.0,
    this.preferredYaw,
  });

  /// Accepts either the exercise object (with 'anim') or the anim object itself.
  factory ExerciseAnimation.fromJson(Map<String, dynamic> json) {
    final anim = (json['anim'] is Map)
        ? (json['anim'] as Map).cast<String, dynamic>()
        : json;
    final frames = <KeyFrame>[];
    for (final f in (anim['frames'] as List)) {
      final fm = (f as Map).cast<String, dynamic>();
      final pose = Pose();
      final at = (fm['at'] as List).map((e) => (e as num).toDouble()).toList();
      pose.atX = at[0];
      pose.atY = at[1];
      if (at.length > 2) pose.atZ = at[2];
      final am = (fm['a'] as Map).cast<String, dynamic>();
      double g(String k, double def) =>
          am[k] is num ? (am[k] as num).toDouble() : def;
      final t = g('t', 90);
      pose.a[PoseKeys.t] = t;
      pose.a[PoseKeys.hd] = g('hd', t);
      pose.a[PoseKeys.tb] = g('tb', 0);
      for (var i = 3; i < PoseKeys.count; i++) {
        final name = PoseKeys.names[i];
        final isAbd = name.endsWith('b');
        pose.a[i] = g(name, isAbd ? 0 : 270);
      }
      frames.add(KeyFrame(pose));
    }
    final props = <PropSpec>[];
    for (final p in (anim['props'] as List? ?? const [])) {
      props.add(PropSpec.fromJson((p as Map).cast<String, dynamic>()));
    }
    return ExerciseAnimation(
      id: (json['id'] as String?) ?? '',
      anchor: (anim['anchor'] as String?) ?? 'hip',
      frames: frames,
      props: props,
      loop: (anim['loop'] as String?) ?? 'pingpong',
      speed: (anim['speed'] as num?)?.toDouble() ?? 1.0,
      preferredYaw: (anim['yaw'] as num?)?.toDouble(),
    );
  }

  double get transitionSeconds => baseTransitionSeconds / (speed <= 0 ? 1 : speed);

  /// Ordered list of frame indices visited in one loop (last returns to first).
  int get segmentCount {
    final n = frames.length;
    if (n <= 1) return 1;
    return loop == 'cycle' ? n : 2 * (n - 1);
  }

  /// Duration of one full loop in seconds.
  double get duration => segmentCount * transitionSeconds;

  /// Frame index of the start of segment [s].
  int _segFrame(int s) {
    final n = frames.length;
    if (n <= 1) return 0;
    if (loop == 'cycle') return s % n;
    final m = s % (2 * (n - 1));
    return m < n ? m : 2 * (n - 1) - m;
  }

  /// Time (s) at which key frame [i] is shown (first visit), optionally plus a
  /// fraction [u] of the following transition.
  double timeAtFrame(int i, [double u = 0]) => (i + u) * transitionSeconds;

  static double _ease(double u) => u * u * (3 - 2 * u); // smoothstep ease-in-out

  static double _lerpAngle(double a, double b, double u) {
    var d = (b - a) % 360.0;
    if (d > 180) d -= 360;
    if (d < -180) d += 360;
    return a + d * u;
  }

  /// Samples the pose at time [t] seconds into [out].
  void sampleInto(double t, Pose out) {
    final n = frames.length;
    if (n == 1) {
      out.copyFrom(frames[0].pose);
      return;
    }
    final segT = transitionSeconds;
    var tt = t % duration;
    if (tt < 0) tt += duration;
    var s = (tt / segT).floor();
    if (s >= segmentCount) s = segmentCount - 1;
    final u = _ease(((tt - s * segT) / segT).clamp(0.0, 1.0));
    final pa = frames[_segFrame(s)].pose;
    final pb = frames[_segFrame(s + 1)].pose;
    for (var i = 0; i < PoseKeys.count; i++) {
      out.a[i] = _lerpAngle(pa.a[i], pb.a[i], u);
    }
    out.atX = pa.atX + (pb.atX - pa.atX) * u;
    out.atY = pa.atY + (pb.atY - pa.atY) * u;
    if (pa.atZ.isNaN || pb.atZ.isNaN) {
      out.atZ = double.nan;
    } else {
      out.atZ = pa.atZ + (pb.atZ - pa.atZ) * u;
    }
  }

  /// Sample times used for the stable auto-fit bounding box.
  List<double> fitSampleTimes({int perSegment = 8}) {
    if (frames.length <= 1) return const [0];
    final res = <double>[];
    final total = segmentCount * perSegment;
    for (var i = 0; i < total; i++) {
      res.add(duration * i / total);
    }
    return res;
  }

  bool hasProp(String kind) => props.any((p) => p.kind == kind);

  /// Floor height in data coordinates (y down), if any prop defines one.
  double? get floorY {
    for (final p in props) {
      if (p.kind == 'floor') return p.get('y', 88);
    }
    for (final p in props) {
      if (p.p.containsKey('floor')) return p.get('floor');
    }
    return null;
  }

  static double degToRad(double d) => d * math.pi / 180;
}
