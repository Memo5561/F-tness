import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'exercise_animation.dart';
import 'mannequin_scene.dart';

/// Loads and caches the mannequin fragment program.
class MannequinShader {
  static const String asset = 'shaders/mannequin.frag';
  static ui.FragmentProgram? _program;
  static Future<ui.FragmentProgram>? _loading;

  static ui.FragmentProgram? get cached => _program;

  static Future<ui.FragmentProgram> load() {
    if (_program != null) return SynchronousFuture(_program!);
    return _loading ??= ui.FragmentProgram.fromAsset(asset).then((p) => _program = p);
  }
}

/// Mutable view state shared by the widget and its painter (repaint trigger).
class MannequinViewState extends ChangeNotifier {
  double time;
  double yaw;
  double pitch;

  /// Yaw the per-yaw framing is solved for; null = [yaw]. Frozen at the
  /// drag-start yaw while dragging, the snapped target yaw after release.
  double? fitYaw;

  /// Pitch the camera framing is solved for (lags behind [pitch] during a
  /// drag so the view never zooms while the finger is down).
  double fitPitch;

  /// 0 = per-yaw framing (at rest), 1 = yaw-invariant framing (dragging).
  double frameBlend;
  MannequinViewState({this.time = 0, this.yaw = 30, this.pitch = 12, double? fitPitch, this.fitYaw, this.frameBlend = 0})
      : fitPitch = fitPitch ?? pitch;
  void update({double? time, double? yaw, double? pitch, double? fitPitch, double? frameBlend}) {
    if (time != null) this.time = time;
    if (yaw != null) this.yaw = yaw;
    if (pitch != null) this.pitch = pitch;
    if (fitPitch != null) this.fitPitch = fitPitch;
    if (frameBlend != null) this.frameBlend = frameBlend;
    notifyListeners();
  }
}

/// Paints the SDF mannequin with the fragment shader. Can be driven directly
/// (tests, thumbnails) via [MannequinViewState].
class MannequinPainter extends CustomPainter {
  final MannequinScene scene;
  final ui.FragmentShader shader;
  final MannequinViewState state;
  final Color background;
  final MannequinQuality quality;

  /// Fraction of the physical resolution to raymarch at (1 = full). Below 1
  /// the shader renders into an offscreen image which is scaled up.
  final double resolutionScale;
  final double devicePixelRatio;
  final Paint _paint = Paint();
  final Paint _blit = Paint()..filterQuality = FilterQuality.medium;

  // reduced-resolution path: the last offscreen image is reused while
  // nothing changed (static view, holds between their 30 fps ticks)
  ui.Image? _img;
  int _imgKey = 0;

  MannequinPainter({
    required this.scene,
    required this.shader,
    required this.state,
    required this.background,
    this.quality = MannequinQuality.medium,
    this.resolutionScale = 1,
    this.devicePixelRatio = 1,
  }) : super(repaint: state);

  void _fit(Size size) => scene.fit(state.yaw, state.pitch, size.width / size.height,
      fitYaw: state.fitYaw, fitPitch: state.fitPitch, blend: state.frameBlend);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    _paint.shader = shader;
    if (resolutionScale >= 0.999) {
      _fit(size);
      scene.pose(state.time);
      scene.writeUniforms(shader, size.width, size.height, devicePixelRatio, background, quality);
      canvas.drawRect(Offset.zero & size, _paint);
      return;
    }
    final physical = devicePixelRatio * resolutionScale;
    final w = (size.width * physical).ceilToDouble();
    final h = (size.height * physical).ceilToDouble();
    final key = Object.hash(w, h, state.time, state.yaw, state.pitch, state.fitYaw, state.fitPitch, state.frameBlend);
    var img = _img;
    if (img == null || key != _imgKey) {
      _fit(size);
      scene.pose(state.time);
      scene.writeUniforms(shader, w, h, 1, background, quality);
      final rec = ui.PictureRecorder();
      Canvas(rec).drawRect(Rect.fromLTWH(0, 0, w, h), _paint);
      final pic = rec.endRecording();
      img = pic.toImageSync(w.toInt(), h.toInt());
      pic.dispose();
      _img?.dispose();
      _img = img;
      _imgKey = key;
    }
    canvas.drawImageRect(img, Rect.fromLTWH(0, 0, w, h), Offset.zero & size, _blit);
  }

  /// Releases the cached offscreen image (reduced-resolution path).
  void dispose() {
    _img?.dispose();
    _img = null;
  }

  /// Renders one static frame into an image of [size] logical pixels at
  /// [pixelRatio] (thumbnails / list items: no per-frame shader cost).
  ui.Image renderImage(Size size, double pixelRatio) {
    final w = (size.width * pixelRatio).ceil(), h = (size.height * pixelRatio).ceil();
    _fit(size);
    scene.pose(state.time);
    scene.writeUniforms(shader, w.toDouble(), h.toDouble(), 1, background, quality);
    _paint.shader = shader;
    final rec = ui.PictureRecorder();
    Canvas(rec).drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), _paint);
    final pic = rec.endRecording();
    final img = pic.toImageSync(w, h);
    pic.dispose();
    return img;
  }

  @override
  bool shouldRepaint(covariant MannequinPainter old) =>
      old.scene != scene ||
      old.background != background ||
      old.resolutionScale != resolutionScale ||
      old.shader != shader ||
      old.quality != quality;
}

/// Default raymarch resolution scale for a device pixel ratio: full
/// resolution up to dpr 2, above that 2 physical px per logical px, clamped
/// to at least 0.75 of the physical resolution.
double autoResolutionScale(double dpr) => dpr <= 2.0 ? 1.0 : (2.0 / dpr).clamp(0.75, 1.0);

/// Animated, rotatable 3D mannequin for an exercise.
class Mannequin3DView extends StatefulWidget {
  final ExerciseAnimation animation;

  /// Horizontal drag = yaw, vertical drag = pitch (clamped).
  final bool interactive;
  final bool playing;

  /// Start yaw (deg).
  final double initialYaw;

  /// Start at the exercise's preferred yaw instead of [initialYaw] (fixture
  /// `view.yaw`, 35 for horizontal bodies like levers / planche / flag).
  final bool usePreferredYaw;
  final double initialPitch;

  /// Background (also used for the floor fade). Defaults to the scaffold colour.
  final Color? background;

  /// Render a fixed animation time (seconds) instead of playing.
  final double? fixedTime;

  /// Raymarch resolution relative to physical pixels. null = auto: full
  /// resolution up to 2 physical px per logical px, above that scaled to
  /// 2 px per logical px but never below 0.75 (bilinear upscale).
  final double? resolutionScale;

  /// March-step / AO budget. medium = 64 steps, 3 AO taps.
  final MannequinQuality quality;

  /// Frame only the displayed pose for the exact yaw (static thumbnails)
  /// instead of the whole animation for all yaws.
  final bool fitToPose;

  const Mannequin3DView({
    super.key,
    required this.animation,
    this.interactive = true,
    this.playing = true,
    this.initialYaw = 30,
    this.usePreferredYaw = false,
    this.initialPitch = 12,
    this.background,
    this.fixedTime,
    this.resolutionScale,
    this.quality = MannequinQuality.medium,
    this.fitToPose = false,
  });

  @override
  State<Mannequin3DView> createState() => _Mannequin3DViewState();
}

class _Mannequin3DViewState extends State<Mannequin3DView> with SingleTickerProviderStateMixin {
  late MannequinScene _scene;
  late final MannequinViewState _state;
  ui.FragmentShader? _shader;
  Ticker? _ticker;
  Duration _lastTick = Duration.zero;
  double _time = 0;
  double _sincePaint = 0;
  bool _dragging = false;

  // post-drag easing (yaw snap out of the avoid window, framing pitch)
  double _easeT = 1, _yawFrom = 0, _yawTo = 0, _fitFrom = 0, _fitTo = 0;
  static const double _easeSeconds = 0.35;

  // framing blend per-yaw <-> yaw-invariant (eases in on touch, out on release)
  double _blendT = 1, _blendFrom = 0, _blendTo = 0, _blendSeconds = 0.25;
  MannequinPainter? _painter;

  static const double minPitch = -8, maxPitch = 65;

  MannequinScene _makeScene() =>
      MannequinScene(widget.animation, fitPoseTime: widget.fitToPose ? (widget.fixedTime ?? 0) : null);

  @override
  void initState() {
    super.initState();
    _scene = _makeScene();
    _time = widget.fixedTime ?? 0;
    _state = MannequinViewState(
        time: _time, yaw: widget.usePreferredYaw ? _scene.preferredYaw : widget.initialYaw, pitch: widget.initialPitch);
    final cached = MannequinShader.cached;
    if (cached != null) {
      _shader = cached.fragmentShader();
    } else {
      MannequinShader.load().then((p) {
        if (mounted) setState(() => _shader = p.fragmentShader());
      });
    }
    _ticker = createTicker(_onTick);
    _syncTicker();
  }

  bool get _animating => widget.playing && widget.fixedTime == null && TickerMode.valuesOf(context).enabled;

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _lastTick = elapsed;
    var changed = false;
    double? yaw, fitPitch, blend;
    if (_easeT < 1) {
      _easeT = math.min(1, _easeT + dt / _easeSeconds);
      final e = 1 - math.pow(1 - _easeT, 3).toDouble(); // ease-out cubic
      yaw = _yawFrom + (_yawTo - _yawFrom) * e;
      fitPitch = _fitFrom + (_fitTo - _fitFrom) * e;
      changed = true;
    }
    if (_blendT < 1) {
      _blendT = math.min(1, _blendT + dt / _blendSeconds);
      final e = 0.5 - 0.5 * math.cos(math.pi * _blendT); // ease in-out
      blend = _blendFrom + (_blendTo - _blendFrom) * e;
      changed = true;
    }
    if (_animating) {
      _time += dt;
      _sincePaint += dt;
      // holds barely move: 30 fps is plenty while nobody touches the view
      final minInterval = (widget.animation.isNearlyStatic && !_dragging && _easeT >= 1 && _blendT >= 1) ? 1 / 30 - 0.004 : 0.0;
      if (_sincePaint >= minInterval) changed = true;
    }
    if (changed) {
      _sincePaint = 0;
      _state.update(time: _time, yaw: yaw, fitPitch: fitPitch, frameBlend: blend);
    }
    if (!_animating && _easeT >= 1 && _blendT >= 1) _ticker!.stop();
  }

  bool get _easing => _easeT < 1 || _blendT < 1;

  void _syncTicker() {
    final run = _animating || _easing;
    if (run && !_ticker!.isActive) {
      _lastTick = Duration.zero;
      _ticker!.start();
    } else if (!run && _ticker!.isActive) {
      _ticker!.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ticker != null) _syncTicker();
  }

  @override
  void didUpdateWidget(Mannequin3DView old) {
    super.didUpdateWidget(old);
    if (old.animation != widget.animation || old.fitToPose != widget.fitToPose) {
      _scene = _makeScene();
      _time = 0;
    }
    if (widget.fixedTime != null) {
      _time = widget.fixedTime!;
      _state.update(time: _time);
    }
    _syncTicker();
  }

  @override
  void dispose() {
    _painter?.dispose();
    _ticker?.dispose();
    _shader?.dispose();
    _state.dispose();
    super.dispose();
  }

  void _startBlend(double to, double seconds) {
    _blendFrom = _state.frameBlend;
    _blendTo = to;
    _blendSeconds = seconds;
    _blendT = _blendFrom == to ? 1 : 0;
  }

  void _onPanStart(DragStartDetails d) {
    _dragging = true;
    _easeT = 1; // finger wins over a running snap
    // keep the rest framing of the current yaw, blend to the yaw-invariant
    // framing (so the rotation itself never zooms)
    _state.fitYaw = _state.fitYaw ?? _state.yaw;
    _startBlend(1, 0.25);
    _syncTicker();
  }

  void _onPan(DragUpdateDetails d) {
    _state.update(
      yaw: _state.yaw + d.delta.dx * 0.6,
      pitch: (_state.pitch + d.delta.dy * 0.4).clamp(minPitch, maxPitch),
    );
  }

  void _onPanEnd([Object? _]) {
    _dragging = false;
    _yawFrom = _state.yaw;
    _yawTo = _scene.snapYaw(_state.yaw);
    _fitFrom = _state.fitPitch;
    _fitTo = _state.pitch;
    // ease back to the per-yaw framing of the final (snapped) yaw
    _state.fitYaw = _yawTo;
    _startBlend(0, _easeSeconds);
    if (_yawFrom != _yawTo || _fitFrom != _fitTo) _easeT = 0;
    _syncTicker();
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.background ?? Theme.of(context).scaffoldBackgroundColor;
    final shader = _shader;
    if (shader == null) return ColoredBox(color: bg);
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    final scale = widget.resolutionScale ?? autoResolutionScale(dpr);
    final old = _painter;
    final painter = MannequinPainter(
      scene: _scene,
      shader: shader,
      state: _state,
      background: bg,
      quality: widget.quality,
      resolutionScale: scale,
      devicePixelRatio: dpr,
    );
    if (old != null && !old.shouldRepaint(painter)) {
      painter._img = old._img; // keep the cached offscreen image
      painter._imgKey = old._imgKey;
      old._img = null;
    }
    old?.dispose();
    _painter = painter;
    Widget child = RepaintBoundary(
      child: CustomPaint(painter: painter, child: const SizedBox.expand()),
    );
    if (widget.interactive) {
      child = GestureDetector(
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: _onPanStart,
        onPanUpdate: _onPan,
        onPanEnd: _onPanEnd,
        onPanCancel: _onPanEnd,
        child: child,
      );
    }
    return child;
  }
}

/// Static, cached render of one pose (exercise lists / thumbnails): the
/// shader runs once per size/theme, afterwards it is a plain image.
class MannequinSnapshot extends StatefulWidget {
  final ExerciseAnimation animation;

  /// Animation time (s) of the pose to show.
  final double time;

  /// null = the exercise's preferred yaw.
  final double? yaw;
  final double pitch;
  final Color? background;

  /// true (default): frame just this pose at this yaw (fills the tile).
  final bool fitToPose;
  final MannequinQuality quality;

  const MannequinSnapshot({
    super.key,
    required this.animation,
    this.time = 0,
    this.yaw,
    this.pitch = 12,
    this.background,
    this.fitToPose = true,
    this.quality = MannequinQuality.high,
  });

  @override
  State<MannequinSnapshot> createState() => _MannequinSnapshotState();
}

class _MannequinSnapshotState extends State<MannequinSnapshot> {
  ui.Image? _image;
  Object? _key;
  ui.FragmentProgram? _program = MannequinShader.cached;

  @override
  void initState() {
    super.initState();
    if (_program == null) {
      MannequinShader.load().then((p) {
        if (mounted) setState(() => _program = p);
      });
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  ui.Image? _render(Size size, double dpr, Color bg) {
    final key = Object.hash(size, dpr, bg, widget.animation, widget.time, widget.yaw, widget.pitch, widget.fitToPose, widget.quality);
    if (key == _key && _image != null) return _image;
    final prog = _program;
    if (prog == null || size.isEmpty) return null;
    final scene = MannequinScene(widget.animation, fitPoseTime: widget.fitToPose ? widget.time : null);
    final shader = prog.fragmentShader();
    final painter = MannequinPainter(
      scene: scene,
      shader: shader,
      state: MannequinViewState(time: widget.time, yaw: widget.yaw ?? scene.preferredYaw, pitch: widget.pitch),
      background: bg,
      quality: widget.quality,
    );
    _image?.dispose();
    _image = painter.renderImage(size, dpr);
    shader.dispose();
    _key = key;
    return _image;
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.background ?? Theme.of(context).scaffoldBackgroundColor;
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    return LayoutBuilder(builder: (context, c) {
      final img = _render(c.biggest, dpr, bg);
      if (img == null) return ColoredBox(color: bg);
      return RawImage(image: img, width: c.biggest.width, height: c.biggest.height, fit: BoxFit.fill);
    });
  }
}
