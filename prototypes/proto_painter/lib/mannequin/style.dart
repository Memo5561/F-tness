import 'dart:ui';

import 'math3d.dart';

/// RGB triple in 0..1.
class Rgb {
  final double r, g, b;
  const Rgb(this.r, this.g, this.b);
  factory Rgb.hex(int v) => Rgb(((v >> 16) & 0xff) / 255.0,
      ((v >> 8) & 0xff) / 255.0, (v & 0xff) / 255.0);
}

/// Visual style: material colours + lighting (view-space, linear "wrap" model
/// I = ambient + K.n so it can be reproduced exactly by gradients).
class MannequinStyle {
  final Color background;
  final Rgb body;
  final Rgb joint;
  final Rgb prop;

  /// Lighting: I(n) = ambient + K.n - edgeDark*(1-nz)^2 ; plus rim*(1-nz)^3.
  final double ambient;
  final V3 k;
  final double edgeDark;
  final Rgb rim;
  final double rimStrength;

  /// View-space 2D direction (y up) of the rim light's edge highlight.
  final double rimDirX, rimDirY;

  /// Fraction of the rim that is uniform around the silhouette.
  final double rimUniform;

  /// Specular for props (metal bars).
  final double propSpec;

  final Color floorColor;
  final Color gridColor;
  final double shadowOpacity;
  final bool isDark;

  const MannequinStyle({
    required this.background,
    required this.body,
    required this.joint,
    required this.prop,
    required this.ambient,
    required this.k,
    required this.edgeDark,
    required this.rim,
    required this.rimStrength,
    this.rimDirX = 0.86,
    this.rimDirY = 0.51,
    this.rimUniform = 0.12,
    required this.propSpec,
    required this.floorColor,
    required this.gridColor,
    required this.shadowOpacity,
    required this.isDark,
  });

  static final V3 _keyDir = const V3(-0.62, 0.6, 0.5).unit;

  static MannequinStyle dark({Color background = const Color(0xFF121212)}) =>
      MannequinStyle(
        background: background,
        body: Rgb.hex(0xE6DACB),
        joint: Rgb.hex(0xCBBFB0),
        prop: Rgb.hex(0x8E969E),
        ambient: 0.53,
        k: _keyDir * 0.47,
        edgeDark: 0.08,
        rim: Rgb.hex(0xC8DAFF),
        rimStrength: 0.3,
        propSpec: 0.55,
        floorColor: const Color(0xFF2C2C2C),
        gridColor: const Color(0x30FFFFFF),
        shadowOpacity: 0.9,
        isDark: true,
      );

  static MannequinStyle light({Color background = const Color(0xFFF5F5F5)}) =>
      MannequinStyle(
        background: background,
        body: Rgb.hex(0xDCCFBF),
        joint: Rgb.hex(0xC2B5A5),
        prop: Rgb.hex(0x7D858D),
        ambient: 0.6,
        k: _keyDir * 0.44,
        edgeDark: 0.2,
        rim: Rgb.hex(0x000000),
        rimStrength: 0.0,
        propSpec: 0.45,
        floorColor: const Color(0xFFE6E6E6),
        gridColor: const Color(0x22000000),
        shadowOpacity: 0.45,
        isDark: false,
      );

  static final Map<int, MannequinStyle> _cache = {};

  /// Style for a background colour (canonical instance per colour, so cached
  /// shaders survive widget rebuilds).
  static MannequinStyle forBackground(Color bg) {
    return _cache.putIfAbsent(bg.toARGB32(), () {
      final lum = bg.computeLuminance();
      return lum < 0.4 ? dark(background: bg) : light(background: bg);
    });
  }
}
