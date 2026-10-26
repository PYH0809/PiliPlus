import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:PiliPlus/common/widgets/liquid_glass/glass_surfaces.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

// The player's glass is dark whatever the theme: its icons are white. Its
// frost blurs the danmaku passing under them.
const _style = LiquidGlassStyle(
  tint: Color(0x47000000),
  blur: 10,
  saturation: 1.6,
  rim: 0.28,
  rimWidth: 1.2,
  rimTail: 0.17,
  rimFocus: 1,
  rimAdded: 0.38,
  hairlineSide: 0.5,
);

// Without shader filters the glass frosts: a wide blur, livelier colors.
const double _frostSigma = 20;
const double _frostSaturation = 1.6;

/// Glass over the video, after iOS's player controls.
///
/// The video is a texture, which [LiquidGlassHost] cannot replay, so this
/// glass is a backdrop filter over what is on screen: with Impeller's shader
/// filters it bends it as [LiquidGlass] does, otherwise it frosts it. Its
/// tint is dark in either theme. [t] eases it in from bare air; at 0 it
/// filters nothing. Put several under one [BackdropGroup], which on Impeller
/// reads the screen once for all of them, and never one inside another.
///
/// A [style] in place of the dark one, with a [rim], makes a thicker pane
/// over the video, as a panel slid in over it.
class VideoGlass extends StatelessWidget {
  const VideoGlass({
    super.key,
    required double this.radius,
    this.t = 1,
    this.style,
    this.rim,
    this.child,
  });

  /// A pane as round as it is short.
  const VideoGlass.capsule({
    super.key,
    this.t = 1,
    this.style,
    this.rim,
    this.child,
  }) : radius = null;

  /// A disc [size] across, [child] at its center.
  VideoGlass.circle({
    super.key,
    double size = 44,
    this.t = 1,
    this.style,
    this.rim,
    Widget? child,
  }) : radius = null,
       child = SizedBox.square(
         dimension: size,
         child: Center(child: child),
       );

  /// The corner radius, or null for a capsule.
  final double? radius;
  final double t;
  final LiquidGlassStyle? style;
  final LiquidGlassRim? rim;
  final Widget? child;

  /// Replaces a button's fill with the glass, keeping its focus and
  /// semantics; a press lights it a little and no ripple spreads.
  static ButtonStyle buttonStyle() => ButtonStyle(
    backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    splashFactory: NoSplash.splashFactory,
    foregroundColor: const WidgetStatePropertyAll(Colors.white),
    backgroundBuilder: (context, states, child) => VideoGlass.capsule(
      child: states.contains(WidgetState.pressed)
          ? ColoredBox(color: const Color(0x1FFFFFFF), child: child)
          : child,
    ),
  );

  static final _darkSchemes = <Color, ColorScheme>{};

  /// [theme] for the controls on this glass: dark, as the glass is in either
  /// theme, so that their menus read so too, and without ripples.
  static ThemeData controlsTheme(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    return GlassSurfaces.withoutRipples(
      colorScheme.brightness == Brightness.dark
          ? theme
          : theme.copyWith(
              colorScheme: _darkSchemes.putIfAbsent(
                colorScheme.primary,
                () => ColorScheme.fromSeed(
                  seedColor: colorScheme.primary,
                  brightness: Brightness.dark,
                ),
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _VideoGlassPane(
      radius: radius,
      t: VideoGlassHidden.of(context) ? 0 : t.clamp(0.0, 1.0),
      style: style ?? _style,
      rim: rim,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      backdropKey: BackdropGroup.of(context)?.backdropKey,
      child: child,
    );
  }
}

/// Turns off the [VideoGlass] below while its controls are out of sight, as
/// a backdrop filter reads the screen every frame wherever it lies.
class VideoGlassHidden extends InheritedWidget {
  const VideoGlassHidden({
    super.key,
    required this.hidden,
    required super.child,
  });

  final bool hidden;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<VideoGlassHidden>()?.hidden ??
      false;

  @override
  bool updateShouldNotify(VideoGlassHidden oldWidget) =>
      hidden != oldWidget.hidden;
}

class _VideoGlassPane extends SingleChildRenderObjectWidget {
  const _VideoGlassPane({
    required this.radius,
    required this.t,
    required this.style,
    required this.rim,
    required this.devicePixelRatio,
    required this.backdropKey,
    super.child,
  });

  final double? radius;
  final double t;
  final LiquidGlassStyle style;
  final LiquidGlassRim? rim;
  final double devicePixelRatio;
  final BackdropKey? backdropKey;

  @override
  _RenderVideoGlass createRenderObject(BuildContext context) =>
      _RenderVideoGlass(
        radius: radius,
        t: t,
        style: style,
        rim: rim,
        devicePixelRatio: devicePixelRatio,
        backdropKey: backdropKey,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderVideoGlass renderObject,
  ) {
    renderObject
      ..radius = radius
      ..t = t
      ..style = style
      ..rim = rim
      ..devicePixelRatio = devicePixelRatio
      ..backdropKey = backdropKey;
  }
}

class _RenderVideoGlass extends RenderProxyBox {
  _RenderVideoGlass({
    required this._radius,
    required this._t,
    required this._style,
    required this._rim,
    required this._devicePixelRatio,
    required this._backdropKey,
  });

  double? get radius => _radius;
  double? _radius;
  set radius(double? value) {
    if (_radius == value) return;
    _radius = value;
    markNeedsPaint();
  }

  double get t => _t;
  double _t;
  set t(double value) {
    if (_t == value) return;
    final wasOn = _t > 0;
    _t = value;
    if (wasOn != value > 0) {
      markNeedsCompositingBitsUpdate();
    }
    markNeedsPaint();
  }

  LiquidGlassStyle get style => _style;
  LiquidGlassStyle _style;
  set style(LiquidGlassStyle value) {
    if (_style == value) return;
    _style = value;
    markNeedsPaint();
  }

  LiquidGlassRim? get rim => _rim;
  LiquidGlassRim? _rim;
  set rim(LiquidGlassRim? value) {
    if (_rim == value) return;
    _rim = value;
    markNeedsPaint();
  }

  double get devicePixelRatio => _devicePixelRatio;
  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  BackdropKey? get backdropKey => _backdropKey;
  BackdropKey? _backdropKey;
  set backdropKey(BackdropKey? value) {
    if (_backdropKey == value) return;
    _backdropKey = value;
    markNeedsPaint();
  }

  ui.FragmentProgram? _program;
  ui.FragmentShader? _shader;
  final _clip = LayerHandle<ClipRSuperellipseLayer>();
  final _backdrop = LayerHandle<BackdropFilterLayer>();
  final _frost = LayerHandle<BackdropFilterLayer>();

  // Where the shader last placed the pane on screen, in logical pixels.
  Offset? _placed;
  bool _awaitingPaint = false;

  bool get _bends => _program != null;

  void _onProgram() {
    _program = liquidGlassProgram(_onProgram);
    if (attached) {
      _track();
      markNeedsPaint();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _program = liquidGlassProgram(_onProgram);
    _track();
  }

  @override
  void detach() {
    forgetLiquidGlassProgram(_onProgram);
    _tracked.remove(this);
    super.detach();
  }

  @override
  void dispose() {
    _shader?.dispose();
    _shader = null;
    _clip.layer = null;
    _backdrop.layer = null;
    _frost.layer = null;
    super.dispose();
  }

  @override
  bool get alwaysNeedsCompositing => _t > 0;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_t <= 0 || size.isEmpty) {
      _clip.layer = null;
      _backdrop.layer = null;
      _frost.layer = null;
      _placed = null;
      super.paint(context, offset);
      return;
    }
    final bounds = Offset.zero & size;
    final corners = BorderRadius.circular(
      math.min(_radius ?? double.infinity, size.shortestSide / 2),
    );
    _clip.layer = context.pushClipRSuperellipse(
      needsCompositing,
      offset,
      bounds,
      corners.toRSuperellipse(bounds),
      (context, offset) => _paintGlass(context, offset, corners),
      oldLayer: _clip.layer,
    );
    // Unclipped, as a progress bar's thumb glows past the pane.
    super.paint(context, offset);
  }

  void _paintGlass(
    PaintingContext context,
    Offset offset,
    BorderRadius corners,
  ) {
    if (!_bends) {
      _frost.layer = null;
      final layer = (_backdrop.layer ??= BackdropFilterLayer())
        ..filter = _frostFilter()
        ..backdropKey = _backdropKey;
      context.pushLayer(
        layer,
        (context, offset) =>
            _paintFrost(context.canvas, offset & size, corners),
        offset,
      );
      return;
    }
    // The engine frosts the screen under the pane, alike for every pane of
    // the group, then the shader bends the frost and tints it. Impeller on
    // OpenGL ES drops a blur composed under a shader filter, and the
    // shader's own frost costs too much over a pane this wide. Nested so,
    // the shader reads the frost's layer, which lies the right way up even
    // where the screen itself lies upside down, as on OpenGL ES.
    final sigma = _style.blur * _t;
    final frost = (_frost.layer ??= BackdropFilterLayer())
      ..filter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma)
      ..backdropKey = _backdropKey;
    context.pushLayer(frost, (context, offset) {
      final bend = (_backdrop.layer ??= BackdropFilterLayer())
        ..filter = _bendFilter(corners, sigma);
      context.pushLayer(bend, (_, _) {}, offset);
    }, offset);
  }

  ui.ImageFilter _frostFilter() {
    final sigma = math.max(_frostSigma, _style.blur) * _t;
    return ui.ImageFilter.compose(
      outer: ColorFilter.matrix(
        _saturate(1 + (_frostSaturation - 1) * _t),
      ),
      inner: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
    );
  }

  // The pane in screen pixels, as the backdrop's texture holds the screen:
  // the shader reads glass coordinates in dp from the pane's top left.
  ui.ImageFilter _bendFilter(BorderRadius corners, double frost) {
    final style = _style.scale(_t);
    final dpr = _devicePixelRatio;
    final origin = localToGlobal(Offset.zero);
    _placed = origin;
    _awaitingPaint = false;
    final shader = _shader ??= _program!.fragmentShader();
    final toGlass = [-origin.dx, -origin.dy, 1 / dpr, 1 / dpr];
    const everywhere = [0.5, 0.5, 1e6, 1e6];
    final uniforms = [
      ...toGlass, // uFrame
      ...toGlass, // uSample
      ...everywhere, // uClamp
      1 / dpr, frost * dpr, // uTexels: the frost the screen holds

      ...toGlass, // uHazeSample
      ...everywhere, // uHazeClamp
      0.0, // uHaze
      0.0, 0.0, 0.0, 0.0, // uVeil
      ...liquidGlassLook(size, corners, style, rim: _rim?.scale(_t)),
    ];
    // The engine fills the first two, the texture's size.
    for (final (index, value) in uniforms.indexed) {
      shader.setFloat(2 + index, value);
    }
    return ui.ImageFilter.shader(shader);
  }

  // As LiquidGlass draws its frost: the tint, a rim lit from the top left,
  // and a dark hairline.
  void _paintFrost(Canvas canvas, Rect rect, BorderRadius corners) {
    final style = _style.scale(_t);
    final shape = corners.toRSuperellipse(rect);
    final rim = style.rim;
    canvas
      ..drawRSuperellipse(shape, Paint()..color = style.tint)
      ..drawRSuperellipse(
        shape.deflate(style.rimWidth / 2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = style.rimWidth
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: rim),
              Colors.white.withValues(alpha: rim * 0.15),
              Colors.white.withValues(alpha: rim * 0.5),
            ],
          ).createShader(rect),
      )
      ..drawRSuperellipse(
        shape.deflate(0.335),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.67
          ..color = Colors.black.withValues(
            alpha: (style.hairline + (style.hairlineSide ?? 0)) / 2 * 0.3,
          ),
      );
  }

  // The shader reads where the pane lies on screen, which moves without a
  // repaint when an ancestor's transform does, as a route slides in. Every
  // frame, each pane that bends checks it still lies where it was painted.
  static final _tracked = <_RenderVideoGlass>{};
  static var _checking = false;

  void _track() {
    if (!_bends) return;
    _tracked.add(this);
    if (!_checking) {
      _checking = true;
      SchedulerBinding.instance.addPersistentFrameCallback((_) {
        for (final pane in _tracked) {
          pane._checkPlace();
        }
      });
    }
  }

  void _checkPlace() {
    final placed = _placed;
    if (placed == null || _awaitingPaint || !attached || !hasSize) return;
    if (localToGlobal(Offset.zero) != placed) {
      _awaitingPaint = true;
      markNeedsPaint();
    }
  }
}

List<double> _saturate(double saturation) {
  const red = 0.2126;
  const green = 0.7152;
  const blue = 0.0722;
  final rest = 1 - saturation;
  return [
    red * rest + saturation, green * rest, blue * rest, 0, 0, //
    red * rest, green * rest + saturation, blue * rest, 0, 0,
    red * rest, green * rest, blue * rest + saturation, 0, 0,
    0, 0, 0, 1, 0,
  ];
}
