import 'dart:math' as math;
import 'dart:typed_data';

/// Pose channels (degrees). Order is fixed; values live in a [Float64List].
///
/// Angle convention (same as the 2D data): 0 = +x (right), 90 = up.
/// `*b` channels = abduction out of the sagittal plane, away from the body
/// midline (side 1 -> +z, side 2 -> -z). `tb` = torso lateral lean toward +z.
/// `ry` = extra yaw of the whole figure about the vertical axis (optional,
/// used e.g. for the human flag so the chest faces the default camera).
class PoseChannel {
  static const int t = 0, hd = 1, tb = 2;
  static const int ua1 = 3, la1 = 4, ua2 = 5, la2 = 6;
  static const int th1 = 7, sh1 = 8, th2 = 9, sh2 = 10;
  static const int ua1b = 11, la1b = 12, ua2b = 13, la2b = 14;
  static const int th1b = 15, sh1b = 16, th2b = 17, sh2b = 18;
  static const int ry = 19;
  static const int count = 20;
  static const List<String> names = [
    't', 'hd', 'tb', //
    'ua1', 'la1', 'ua2', 'la2', 'th1', 'sh1', 'th2', 'sh2', //
    'ua1b', 'la1b', 'ua2b', 'la2b', 'th1b', 'sh1b', 'th2b', 'sh2b', //
    'ry',
  ];
}

class PoseKeyframe {
  /// Anchor target in 2D screen coords (y down); [atZ] optional world z.
  final double atX, atY;
  final double? atZ;
  final Float64List angles;
  PoseKeyframe(this.atX, this.atY, this.atZ, this.angles);

  factory PoseKeyframe.fromJson(Map<String, dynamic> j) {
    final at = (j['at'] as List).cast<num>();
    final a = (j['a'] as Map).cast<String, dynamic>();
    final v = Float64List(PoseChannel.count);
    for (var i = 0; i < PoseChannel.count; i++) {
      final n = PoseChannel.names[i];
      final raw = a[n];
      double d;
      if (raw != null) {
        d = (raw as num).toDouble();
      } else if (n == 't') {
        d = 90;
      } else if (n == 'hd') {
        d = ((a['t'] ?? 90) as num).toDouble();
      } else if (n.endsWith('b') || n == 'tb' || n == 'ry') {
        d = 0;
      } else {
        d = 270; // limbs hang down by default
      }
      v[i] = d;
    }
    return PoseKeyframe(at[0].toDouble(), at[1].toDouble(), at.length > 2 ? at[2].toDouble() : null, v);
  }
}

enum PropKind { bar, pbars, floor, wall, box, pole }

class PropSpec {
  final PropKind kind;
  final double x, y, w, h, x1, x2, floor;
  const PropSpec(this.kind, {this.x = 0, this.y = 0, this.w = 0, this.h = 0, this.x1 = 0, this.x2 = 0, this.floor = 88});

  static PropSpec? fromJson(Map<String, dynamic> j) {
    double g(String k, [double d = 0]) => ((j[k] ?? d) as num).toDouble();
    switch (j['k']) {
      case 'bar':
        return PropSpec(PropKind.bar, x: g('x', 50), y: g('y', 12));
      case 'pbars':
        return PropSpec(PropKind.pbars, y: g('y', 52), x1: g('x1', 25), x2: g('x2', 80), floor: g('floor', 88));
      case 'floor':
        return PropSpec(PropKind.floor, y: g('y', 88));
      case 'wall':
        return PropSpec(PropKind.wall, x: g('x', 80), floor: g('floor', 88));
      case 'box':
        return PropSpec(PropKind.box, x: g('x'), y: g('y'), w: g('w', 10), h: g('h', 10));
      case 'pole':
        return PropSpec(PropKind.pole, x: g('x', 30), floor: g('floor', 88));
    }
    return null;
  }
}

/// Optional per-exercise camera hints (`"view": {"yaw": 35, "avoid": [75, 105]}`).
class ViewHint {
  /// Default yaw when the widget is not given one.
  final double? yaw;

  /// Yaw window (degrees, mod 180) that reads badly, e.g. looking straight
  /// down a horizontal body. The interactive view snaps out of it on release.
  final double? avoidFrom, avoidTo;
  const ViewHint({this.yaw, this.avoidFrom, this.avoidTo});

  static ViewHint? fromJson(Object? j) {
    if (j is! Map) return null;
    final av = j['avoid'];
    return ViewHint(
      yaw: (j['yaw'] as num?)?.toDouble(),
      avoidFrom: av is List && av.length == 2 ? (av[0] as num).toDouble() : null,
      avoidTo: av is List && av.length == 2 ? (av[1] as num).toDouble() : null,
    );
  }
}

/// How one channel moved in one transition (see [ExerciseAnimation.describeTransitions]).
class ChannelMove {
  final int transition, channel;
  final double delta;

  /// True when the direction was picked by shortest path (no joint range
  /// decided it) -- deltas near 180 deg are then a coin flip.
  final bool ambiguous;
  const ChannelMove(this.transition, this.channel, this.delta, this.ambiguous);
  @override
  String toString() => 'T$transition ${PoseChannel.names[channel]} ${delta.toStringAsFixed(1)}${ambiguous ? ' (ambiguous)' : ''}';
}

/// A keyframed exercise animation (parsed from the app's `anim` JSON).
///
/// Interpolation runs in *joint space*: limb angles are expressed relative to
/// their parent segment (shoulder/hip flexion relative to the torso, elbow and
/// knee flexion relative to the upper segment) and each keyframe value is
/// unwrapped into the joint's anatomical range. The lerp therefore never
/// swings an arm backwards over the head or bends a knee the wrong way, even
/// when the absolute angles differ by ~180 deg. Torso angle and figure yaw
/// use the shortest path; abduction/lean channels are plain linear.
class ExerciseAnimation {
  final String anchor;
  final List<PoseKeyframe> frames;
  final List<PropSpec> props;
  final bool pingpong;
  final double speed;
  final ViewHint? view;

  /// Base duration of one keyframe transition at speed 1.
  static const double baseTransitionSeconds = 1.5;

  /// Anatomical ranges in joint space (degrees): [lo, hi].
  static const List<double> shoulderRange = [-100, 200]; // flexion: 0 = arm down, 90 = forward, 180 = overhead
  static const List<double> elbowRange = [-30, 178]; // flexion (forearm folds toward the front of the upper arm)
  static const List<double> hipRange = [-60, 178]; // flexion: 0 = leg continues the torso, 90 = L-sit
  static const List<double> kneeRange = [-30, 178]; // flexion (shin folds backward)
  static const List<double> neckRange = [-100, 100]; // head relative to the torso line

  late final List<Float64List> _start; // per transition: joint-space start values
  late final List<Float64List> _delta; // per transition: joint-space deltas
  late final List<Uint8List> _ambiguous;

  ExerciseAnimation({required this.anchor, required this.frames, required this.props, this.pingpong = true, this.speed = 1, this.view}) {
    _prepare();
  }

  factory ExerciseAnimation.fromJson(Map<String, dynamic> j) {
    final frames = (j['frames'] as List).map((f) => PoseKeyframe.fromJson((f as Map).cast<String, dynamic>())).toList();
    final props = <PropSpec>[];
    for (final p in (j['props'] as List? ?? const [])) {
      final s = PropSpec.fromJson((p as Map).cast<String, dynamic>());
      if (s != null) props.add(s);
    }
    return ExerciseAnimation(
      anchor: (j['anchor'] ?? 'hip') as String,
      frames: frames,
      props: props,
      pingpong: (j['loop'] ?? 'pingpong') != 'cycle',
      speed: ((j['speed'] ?? 1) as num).toDouble(),
      view: ViewHint.fromJson(j['view']),
    );
  }

  double get transitionSeconds => baseTransitionSeconds / (speed <= 0 ? 1 : speed);

  int get transitionCount {
    final n = frames.length;
    if (n <= 1) return 1;
    return pingpong ? 2 * (n - 1) : n;
  }

  double get periodSeconds => transitionCount * transitionSeconds;

  /// Time (s) at which keyframe [i] is reached during the first pass.
  double timeOfFrame(num i) => i * transitionSeconds;

  /// True for holds (front lever, planche ...) whose keyframes differ only by
  /// a breathing wobble: the view can repaint at a lower rate.
  late final bool isNearlyStatic = () {
    if (frames.length <= 1) return true;
    for (var k = 0; k < _delta.length; k++) {
      for (final d in _delta[k]) {
        if (d.abs() > 8) return false;
      }
    }
    final f0 = frames.first;
    for (final f in frames) {
      if ((f.atX - f0.atX).abs() + (f.atY - f0.atY).abs() > 1.5) return false;
    }
    return true;
  }();

  int _seqIndex(int k) {
    final n = frames.length;
    if (pingpong) {
      final m = k % (2 * (n - 1));
      return m < n ? m : 2 * (n - 1) - m;
    }
    return k % n;
  }

  // ------------------------------------------------------------ joint space
  static double _wrap180(double d) {
    var x = d % 360.0;
    if (x < 0) x += 360;
    if (x > 180) x -= 360;
    return x;
  }

  /// Representative of [v] (mod 360) inside [r], or NaN if none.
  static double _inRange(double v, List<double> r) {
    var x = v - 360.0 * ((v - r[0]) / 360.0).floor(); // x in [lo, lo+360)
    return x <= r[1] ? x : double.nan;
  }

  /// Representative of [v] (mod 360) closest to the range [r].
  static double _nearRange(double v, List<double> r) {
    final x = v - 360.0 * ((v - r[0]) / 360.0).floor(); // [lo, lo+360)
    return (x - r[1]) <= (r[0] + 360 - x) ? x : x - 360;
  }

  static List<double>? _range(int c) {
    switch (c) {
      case PoseChannel.hd:
        return neckRange;
      case PoseChannel.ua1:
      case PoseChannel.ua2:
        return shoulderRange;
      case PoseChannel.la1:
      case PoseChannel.la2:
        return elbowRange;
      case PoseChannel.th1:
      case PoseChannel.th2:
        return hipRange;
      case PoseChannel.sh1:
      case PoseChannel.sh2:
        return kneeRange;
    }
    return null;
  }

  static bool _circular(int c) => c == PoseChannel.t || c == PoseChannel.ry;

  /// Absolute channel angles -> joint space (unwrapped later per transition).
  static void _toJoint(Float64List a, Float64List j) {
    for (var i = 0; i < PoseChannel.count; i++) {
      j[i] = a[i];
    }
    final t = a[PoseChannel.t];
    j[PoseChannel.hd] = a[PoseChannel.hd] - t;
    for (var s = 0; s < 2; s++) {
      final ua = s == 0 ? PoseChannel.ua1 : PoseChannel.ua2;
      final la = s == 0 ? PoseChannel.la1 : PoseChannel.la2;
      final th = s == 0 ? PoseChannel.th1 : PoseChannel.th2;
      final sh = s == 0 ? PoseChannel.sh1 : PoseChannel.sh2;
      j[ua] = a[ua] - t - 180;
      j[la] = a[la] - a[ua];
      j[th] = a[th] - t - 180;
      j[sh] = a[th] - a[sh];
    }
  }

  /// Joint space -> absolute channel angles (inverse of [_toJoint]).
  static void _fromJoint(Float64List j, Float64List a) {
    for (var i = 0; i < PoseChannel.count; i++) {
      a[i] = j[i];
    }
    final t = j[PoseChannel.t];
    a[PoseChannel.hd] = j[PoseChannel.hd] + t;
    for (var s = 0; s < 2; s++) {
      final ua = s == 0 ? PoseChannel.ua1 : PoseChannel.ua2;
      final la = s == 0 ? PoseChannel.la1 : PoseChannel.la2;
      final th = s == 0 ? PoseChannel.th1 : PoseChannel.th2;
      final sh = s == 0 ? PoseChannel.sh1 : PoseChannel.sh2;
      a[ua] = j[ua] + t + 180;
      a[la] = j[la] + a[ua];
      a[th] = j[th] + t + 180;
      a[sh] = a[th] - j[sh];
    }
  }

  void _prepare() {
    final n = transitionCount;
    _start = List.generate(n, (_) => Float64List(PoseChannel.count));
    _delta = List.generate(n, (_) => Float64List(PoseChannel.count));
    _ambiguous = List.generate(n, (_) => Uint8List(PoseChannel.count));
    if (frames.length <= 1) return;
    final ja = Float64List(PoseChannel.count), jb = Float64List(PoseChannel.count);
    for (var k = 0; k < n; k++) {
      _toJoint(frames[_seqIndex(k)].angles, ja);
      _toJoint(frames[_seqIndex(k + 1)].angles, jb);
      for (var c = 0; c < PoseChannel.count; c++) {
        final r = _range(c);
        double a, d;
        var amb = false;
        if (r != null) {
          final ia = _inRange(ja[c], r), ib = _inRange(jb[c], r);
          a = ia.isNaN ? _nearRange(ja[c], r) : ia;
          if (!ib.isNaN) {
            d = ib - a;
          } else {
            d = _wrap180(jb[c] - a);
          }
          amb = ia.isNaN || ib.isNaN;
        } else if (_circular(c)) {
          a = ja[c];
          d = _wrap180(jb[c] - ja[c]);
          amb = true;
        } else {
          a = ja[c];
          d = jb[c] - ja[c];
        }
        _start[k][c] = a;
        _delta[k][c] = d;
        _ambiguous[k][c] = amb ? 1 : 0;
      }
    }
  }

  /// Every channel move of every transition (for tests / debugging).
  List<ChannelMove> describeTransitions() => [
        for (var k = 0; k < (frames.length <= 1 ? 0 : transitionCount); k++)
          for (var c = 0; c < PoseChannel.count; c++) ChannelMove(k, c, _delta[k][c], _ambiguous[k][c] == 1),
      ];

  final Float64List _j = Float64List(PoseChannel.count);

  /// Samples the pose at [seconds]. Writes [PoseChannel.count] angles into
  /// [angles] and the anchor target (x, y screen coords, z or NaN) into [at].
  void sample(double seconds, Float64List angles, Float64List at) {
    final n = frames.length;
    if (n == 1) {
      final f = frames[0];
      angles.setAll(0, f.angles);
      at[0] = f.atX;
      at[1] = f.atY;
      at[2] = f.atZ ?? double.nan;
      return;
    }
    final total = transitionCount;
    var phase = seconds / transitionSeconds;
    phase = phase % total;
    if (phase < 0) phase += total;
    var k = phase.floor();
    if (k >= total) k = total - 1;
    final f = phase - k;
    final e = 0.5 - 0.5 * math.cos(math.pi * f); // ease in-out
    final a = frames[_seqIndex(k)];
    final b = frames[_seqIndex(k + 1)];
    final s0 = _start[k], d0 = _delta[k];
    for (var i = 0; i < PoseChannel.count; i++) {
      _j[i] = s0[i] + d0[i] * e;
    }
    _fromJoint(_j, angles);
    at[0] = a.atX + (b.atX - a.atX) * e;
    at[1] = a.atY + (b.atY - a.atY) * e;
    final az = a.atZ, bz = b.atZ;
    at[2] = (az != null && bz != null) ? az + (bz - az) * e : (az ?? bz ?? double.nan);
  }

  /// Joint-space value of channel [c] for absolute angles [a] (e.g. shoulder
  /// flexion for ua1), unwrapped into its anatomical range when possible.
  static double jointAngle(Float64List a, int c) {
    final j = Float64List(PoseChannel.count);
    _toJoint(a, j);
    final r = _range(c);
    if (r == null) return j[c];
    final x = _inRange(j[c], r);
    return x.isNaN ? _nearRange(j[c], r) : x;
  }

  static double lerpAngle(double a, double b, double t) {
    var d = (b - a) % 360.0;
    if (d < 0) d += 360;
    if (d > 180) d -= 360;
    return a + d * t;
  }
}
