import 'dart:math' as math;

/// Small immutable 3D vector. World: x right, y up, z toward the default camera.
class V3 {
  final double x, y, z;
  const V3(this.x, this.y, this.z);

  static const V3 zero = V3(0, 0, 0);
  static const V3 unitX = V3(1, 0, 0);
  static const V3 unitY = V3(0, 1, 0);
  static const V3 unitZ = V3(0, 0, 1);

  V3 operator +(V3 o) => V3(x + o.x, y + o.y, z + o.z);
  V3 operator -(V3 o) => V3(x - o.x, y - o.y, z - o.z);
  V3 operator -() => V3(-x, -y, -z);
  V3 operator *(double s) => V3(x * s, y * s, z * s);

  double dot(V3 o) => x * o.x + y * o.y + z * o.z;
  V3 cross(V3 o) =>
      V3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get length => math.sqrt(x * x + y * y + z * z);
  double get length2 => x * x + y * y + z * z;

  V3 get unit {
    final l = length;
    return l < 1e-12 ? const V3(0, 0, 0) : V3(x / l, y / l, z / l);
  }

  /// a + (b - a) * t
  static V3 lerp(V3 a, V3 b, double t) =>
      V3(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t);

  /// a + d * s
  V3 addScaled(V3 d, double s) => V3(x + d.x * s, y + d.y * s, z + d.z * s);

  @override
  String toString() =>
      'V3(${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)}, ${z.toStringAsFixed(2)})';
}

const double deg2rad = math.pi / 180.0;

/// Segment direction from sagittal angle [aDeg] (0 = +x, 90 = up) and abduction
/// [bDeg] out of the sagittal plane, away from the midline (side 1 -> +z, side 2 -> -z).
V3 segDir(double aDeg, double bDeg, double sideSign) {
  final a = aDeg * deg2rad, b = bDeg * deg2rad;
  final cb = math.cos(b);
  return V3(math.cos(a) * cb, math.sin(a) * cb, sideSign * math.sin(b));
}

double clampD(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);
