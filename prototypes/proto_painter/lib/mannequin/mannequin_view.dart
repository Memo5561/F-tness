import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'auto_fit.dart';
import 'camera.dart';
import 'exercise_animation.dart';
import 'mannequin_renderer.dart';
import 'math3d.dart';
import 'style.dart';

export 'auto_fit.dart' show FitMode, MannequinFitData;

/// Paints one exercise animation at a given time from a given camera.
/// Can be driven directly (e.g. in tests) without the widget.
class MannequinPainter extends CustomPainter {
  final ExerciseAnimation animation;
  final MannequinFitData fit;
  final MannequinRenderer renderer;
  final ValueListenable<double>? timeListenable;
  final double fixedTime;
  final double yaw, pitch;
  final MannequinStyle style;
  final bool perspective;
  final double fillFraction;
  final FitMode fitMode;

  /// [FitMode.loop]: yaw at which the current drag started (null = idle) and
  /// the 0..1 ease from the frozen drag scale to the scale at [yaw].
  final double? scaleFromYaw;
  final double scaleBlend;
  final ViewCam _cam = ViewCam();
  final Pose _pose = Pose();
  final List<V3> _posePts = [];
  final List<double> _poseRadii = [];

  MannequinPainter({
    required this.animation,
    required this.fit,
    required this.renderer,
    required this.yaw,
    required this.pitch,
    required this.style,
    this.timeListenable,
    this.fixedTime = 0,
    this.perspective = true,
    this.fillFraction = 0.84,
    this.fitMode = FitMode.loop,
    this.scaleFromYaw,
    this.scaleBlend = 1,
  }) : super(repaint: timeListenable);

  @override
  void paint(Canvas canvas, Size size) {
    final t = timeListenable?.value ?? fixedTime;
    renderer.compactProps = fitMode == FitMode.pose;
    renderer.setProps(animation.props, animation.floorY);
    animation.sampleInto(t, _pose);
    renderer.setPose(_pose, animation.anchor);
    _cam.setAngles(yaw, pitch);
    _cam.pivot = fit.pivot;
    _cam.persp = perspective ? math.max(320.0, fit.radius * 9.0) : 0;
    _posePts.clear();
    _poseRadii.clear();
    if (fitMode != FitMode.loop) renderer.collectFitPoints(_posePts, _poseRadii);
    fit.apply(_cam, size, t, fitMode, fillFraction, _posePts, _poseRadii,
        scaleFromYaw: scaleFromYaw, scaleBlend: scaleBlend);
    renderer.paint(canvas, size, _cam, style);
  }

  @override
  bool shouldRepaint(MannequinPainter old) =>
      old.yaw != yaw ||
      old.pitch != pitch ||
      old.fixedTime != fixedTime ||
      !identical(old.animation, animation) ||
      old.style != style ||
      old.fitMode != fitMode ||
      old.scaleFromYaw != scaleFromYaw ||
      old.scaleBlend != scaleBlend ||
      old.timeListenable != timeListenable;
}

/// Interactive 3D mannequin view: plays the exercise animation; horizontal
/// drag rotates (yaw), vertical drag tilts (pitch, clamped). Pass
/// `initialYaw: animation.initialYaw` to start at the skill's preferred angle.
class Mannequin3DView extends StatefulWidget {
  final ExerciseAnimation animation;
  final bool interactive;
  final bool playing;
  final double initialYaw;
  final double initialPitch;
  final Color? background;

  /// If set, renders this fixed time (seconds into the loop); no ticker.
  final double? fixedTime;

  /// Optional style override (otherwise derived from [background]).
  final MannequinStyle? style;
  final bool perspective;

  /// Camera framing (default: one scale per loop, see [FitMode.loop]).
  final FitMode fitMode;

  const Mannequin3DView({
    super.key,
    required this.animation,
    this.interactive = true,
    this.playing = true,
    this.initialYaw = 30,
    this.initialPitch = 12,
    this.background,
    this.fixedTime,
    this.style,
    this.perspective = true,
    this.fitMode = FitMode.loop,
  });

  @override
  State<Mannequin3DView> createState() => _Mannequin3DViewState();
}

class _Mannequin3DViewState extends State<Mannequin3DView>
    with TickerProviderStateMixin {
  late double _yaw = widget.initialYaw;
  late double _pitch = widget.initialPitch;
  late MannequinFitData _fit = MannequinFitData(widget.animation);
  final MannequinRenderer _renderer = MannequinRenderer();
  final ValueNotifier<double> _time = ValueNotifier(0);
  Ticker? _ticker;
  Duration _last = Duration.zero;
  double _acc = 0;

  // zoom handling while dragging (FitMode.loop): frozen at the drag start,
  // eased to the new yaw's scale when the drag ends
  double? _scaleFromYaw;
  late final AnimationController _settle = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 250))
    ..addListener(() => setState(() {}))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) setState(() => _scaleFromYaw = null);
    });

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _syncTicker();
  }

  void _syncTicker() {
    final run = widget.playing && widget.fixedTime == null;
    if (run && !(_ticker!.isActive)) {
      _last = Duration.zero;
      _ticker!.start();
    } else if (!run && _ticker!.isActive) {
      _ticker!.stop();
    }
    if (widget.fixedTime != null) _time.value = widget.fixedTime!;
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    _acc += dt;
    _time.value = _acc;
  }

  @override
  void didUpdateWidget(Mannequin3DView old) {
    super.didUpdateWidget(old);
    if (!identical(old.animation, widget.animation)) {
      _fit = MannequinFitData(widget.animation);
      _acc = 0;
    }
    _syncTicker();
  }

  @override
  void dispose() {
    _settle.dispose();
    _ticker?.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.background ?? const Color(0xFF121212);
    final style = widget.style ?? MannequinStyle.forBackground(bg);
    Widget paint = CustomPaint(
      painter: MannequinPainter(
        animation: widget.animation,
        fit: _fit,
        renderer: _renderer,
        yaw: _yaw,
        pitch: _pitch,
        style: style,
        timeListenable: widget.fixedTime == null ? _time : null,
        fixedTime: widget.fixedTime ?? 0,
        perspective: widget.perspective,
        fitMode: widget.fitMode,
        scaleFromYaw: _scaleFromYaw,
        scaleBlend: _scaleFromYaw == null
            ? 1
            : Curves.easeInOut.transform(_settle.value),
      ),
      size: Size.infinite,
      isComplex: true,
      willChange: widget.fixedTime == null,
    );
    paint = RepaintBoundary(child: paint);
    if (!widget.interactive) return paint;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      onPanStart: (_) {
        _settle.stop();
        _settle.value = 0;
        setState(() => _scaleFromYaw = _yaw);
      },
      onPanEnd: (_) => _settle.forward(from: 0),
      onPanCancel: () => _settle.forward(from: 0),
      onPanUpdate: (d) {
        setState(() {
          _yaw += d.delta.dx * 0.6;
          _pitch = (_pitch + d.delta.dy * 0.4).clamp(-8.0, 60.0);
        });
      },
      child: paint,
    );
  }
}
