import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:PiliPlus/common/widgets/liquid_glass/glass_surfaces.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:PiliPlus/models/common/video_glass_mode.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

// The player's glass is dark whatever the theme: its icons are white. Over
// the video alone, it stays clear, as iOS's, so that its rim bends what lies
// under it; it darkens over bright video, for the icons.
const _darkStyle = LiquidGlassStyle(
  tint: Color(0x2E000000),
  contrast: -0.4,
  blur: 2.5,
  saturation: 1.6,
  dispersion: 3,
  rim: 0.45,
  rimWidth: 1.2,
  rimTail: 0.17,
  rimFocus: 1,
  rimAdded: 0.38,
  hairlineSide: 0.5,
);

// The glass shader's pixels to a dp at most: past it, as at the 4 of a phone
// with a 1440p screen, it runs a frame's time over a bar, for an edge too
// fine to tell apart. It bends at this, then draws up.
const double _bendTexelsPerDp = 2;

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
    this.note = false,
    this.refract = true,
    this.child,
  });

  /// A pane as round as it is short.
  const VideoGlass.capsule({
    super.key,
    this.t = 1,
    this.style,
    this.rim,
    this.note = false,
    this.refract = true,
    this.child,
  }) : radius = null;

  /// A disc [size] across, [child] at its center.
  VideoGlass.circle({
    super.key,
    double size = 44,
    this.t = 1,
    this.style,
    this.rim,
    this.note = false,
    this.refract = true,
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

  /// Whether this is a small note or button rather than a bar, which the
  /// 播放器小浮层用玻璃 setting can leave as a bare tint.
  final bool note;

  /// Whether the pane may bend what lies under it. A thick pane, as a
  /// panel's, shows little of the bending, which over a wide pane costs much.
  final bool refract;
  final Widget? child;

  /// Replaces a button's fill with the glass, keeping its focus and
  /// semantics; a press lights it a little and no ripple spreads.
  static ButtonStyle buttonStyle({bool note = false}) => ButtonStyle(
    backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    splashFactory: NoSplash.splashFactory,
    foregroundColor: const WidgetStatePropertyAll(Colors.white),
    backgroundBuilder: (context, states, child) => VideoGlass.capsule(
      note: note,
      child: states.contains(WidgetState.pressed)
          ? ColoredBox(color: const Color(0x1FFFFFFF), child: child)
          : child,
    ),
  );

  /// Around a bottom bar over the full-screen video: a tenth of the width
  /// each side, so that on a phone the bar keeps over a 16:9 video rather
  /// than the black either side of it, where the glass hardly shows.
  static EdgeInsets fullScreenBarPadding(BuildContext context) {
    final side = math.max(16.0, MediaQuery.sizeOf(context).width * 0.1);
    return EdgeInsets.fromLTRB(
      side,
      0,
      side,
      math.max(12, MediaQuery.viewPaddingOf(context).bottom),
    );
  }

  static final _darkSchemes = <Color, ColorScheme>{};

  /// [theme] for the controls on this glass: dark, as the glass is in either
  /// theme, so that their menus read so too, and without ripples.
  static ThemeData controlsTheme(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    if (colorScheme.brightness == Brightness.dark) {
      return GlassSurfaces.withoutRipples(theme);
    }
    final dark = _darkSchemes.putIfAbsent(
      colorScheme.primary,
      () => ColorScheme.fromSeed(
        seedColor: colorScheme.primary,
        brightness: Brightness.dark,
      ),
    );
    // The text and icons too, or a menu item without a color of its own
    // stays dark on the dark glass.
    return GlassSurfaces.withoutRipples(
      theme.copyWith(
        colorScheme: dark,
        textTheme: theme.textTheme.apply(
          bodyColor: dark.onSurface,
          displayColor: dark.onSurface,
        ),
        iconTheme: theme.iconTheme.copyWith(color: dark.onSurfaceVariant),
      ),
    );
  }

  /// What the widest pane over the video last drew, for the performance
  /// overlay to show while measuring on a device.
  static final debugInfo = ValueNotifier<String>('');

  /// Whether to fill [debugInfo], as the performance overlay is on.
  static var debugDescribing = false;

  @override
  Widget build(BuildContext context) {
    return _VideoGlassPane(
      radius: radius,
      t: VideoGlassHidden.of(context) ? 0 : t.clamp(0.0, 1.0),
      style: style ?? _darkStyle,
      rim: rim,
      // Bending costs a shader pass a pane each frame; frosting, one blur;
      // a tint, nothing.
      mode: switch (Pref.videoGlassMode) {
        _ when note && !Pref.videoGlassNotes => VideoGlassMode.tint,
        VideoGlassMode.refract when !refract => VideoGlassMode.frost,
        final mode => mode,
      },
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      backdropKey: BackdropGroup.of(context)?.backdropKey,
      source: VideoGlassSource.of(context)?.video,
      changes: VideoGlassSource.of(context)?.changes,
      child: child,
    );
  }
}

/// Where the video under the [VideoGlass] below lies: [video] keys a box
/// holding its [Texture].
///
/// Glass over the video then draws the video's texture again itself, frosted
/// or bent, in place of a backdrop filter. Impeller draws a frame holding
/// any backdrop filter offscreen, ends and redraws the whole screen's pass to
/// read it, and copies it on screen at the end, a few milliseconds a frame on
/// a phone; a layer filtering only what the pane draws again costs a pass the
/// pane's size. What the player draws over the video, as danmaku, does not
/// show through.
class VideoGlassSource extends InheritedWidget {
  const VideoGlassSource({
    super.key,
    required this.video,
    this.changes,
    required super.child,
  });

  final GlobalKey video;

  /// Notifies as the video's texture or its size changes, as the player
  /// outputs anew when the screen turns, for the panes to draw it again.
  final Listenable? changes;

  /// The player on screen, for glass over its video from outside its tree,
  /// as a panel slid in over the full-screen video in a route of its own.
  static ({GlobalKey video, Listenable changes})? player;

  /// [child] over the video of the [player] on screen, if one is.
  static Widget overPlayer({required Widget child}) => switch (player) {
    (:final video, :final changes) => VideoGlassSource(
      video: video,
      changes: changes,
      child: child,
    ),
    null => child,
  };

  static VideoGlassSource? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<VideoGlassSource>();

  @override
  bool updateShouldNotify(VideoGlassSource oldWidget) =>
      video != oldWidget.video || changes != oldWidget.changes;
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
    required this.mode,
    required this.devicePixelRatio,
    required this.backdropKey,
    required this.source,
    required this.changes,
    super.child,
  });

  final double? radius;
  final double t;
  final LiquidGlassStyle style;
  final LiquidGlassRim? rim;
  final VideoGlassMode mode;
  final double devicePixelRatio;
  final BackdropKey? backdropKey;
  final GlobalKey? source;
  final Listenable? changes;

  @override
  _RenderVideoGlass createRenderObject(BuildContext context) =>
      _RenderVideoGlass(
        radius: radius,
        t: t,
        style: style,
        rim: rim,
        mode: mode,
        devicePixelRatio: devicePixelRatio,
        backdropKey: backdropKey,
        source: source,
        changes: changes,
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
      ..mode = mode
      ..devicePixelRatio = devicePixelRatio
      ..backdropKey = backdropKey
      ..source = source
      ..changes = changes;
  }
}

class _RenderVideoGlass extends RenderProxyBox {
  _RenderVideoGlass({
    required this._radius,
    required this._t,
    required this._style,
    required this._rim,
    required this._mode,
    required this._devicePixelRatio,
    required this._backdropKey,
    required this._source,
    required this._changes,
  });

  Listenable? _changes;
  set changes(Listenable? value) {
    if (_changes == value) return;
    if (attached) {
      _changes?.removeListener(_onVideoChanged);
      value?.addListener(_onVideoChanged);
    }
    _changes = value;
  }

  // The texture or its size changed: draw the new one, once laid out.
  void _onVideoChanged() {
    _video = null;
    if (attached) markNeedsPaint();
  }

  GlobalKey? _source;
  set source(GlobalKey? value) {
    if (_source == value) return;
    _source = value;
    _video = null;
    if (attached) _track();
    markNeedsPaint();
  }

  // The video's texture under the pane, and where it lay from the pane
  // when last painted.
  TextureBox? _video;
  Matrix4? _videoAt;
  // The texture, and its size, as last painted: the player swaps them as
  // the screen turns, as hardware decoding outputs anew.
  int? _videoTexture;
  Size? _videoSize;

  // From the video's coordinates to this pane's, through the root: the
  // video is no ancestor of the pane, and getTransformTo between cousins
  // composes them the wrong way round on this SDK, off by the video's scale.
  Matrix4 _fromVideo(TextureBox video) {
    final toPane = getTransformTo(null)..invert();
    return toPane..multiply(video.getTransformTo(null));
  }

  TextureBox? _findVideo() {
    if (_video case final video? when video.attached) {
      return video;
    }
    TextureBox? found;
    void visit(RenderObject child) {
      if (found != null) return;
      if (child is TextureBox) {
        found = child;
      } else {
        child.visitChildren(visit);
      }
    }

    if (_source?.currentContext?.findRenderObject() case final box?) {
      visit(box);
    }
    return _video = found;
  }

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

  /// Whether the pane bends the video, where shader filters allow, frosts
  /// it, or only tints it.
  VideoGlassMode get mode => _mode;
  VideoGlassMode _mode;
  set mode(VideoGlassMode value) {
    if (_mode == value) return;
    final filtered = _filters;
    _mode = value;
    if (attached) _track();
    if (filtered != _filters) {
      markNeedsCompositingBitsUpdate();
    }
    markNeedsPaint();
  }

  bool get _filters => _mode != VideoGlassMode.tint;

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
  final _blur = LayerHandle<ImageFilterLayer>();
  final _bend = LayerHandle<ImageFilterLayer>();
  final _videoTransform = LayerHandle<TransformLayer>();
  final _unseen = LayerHandle<LiquidGlassUnseenLayer>();
  final _drawUp = LayerHandle<ImageFilterLayer>();
  final _drawDown = LayerHandle<TransformLayer>();

  void _dropLayers() {
    _clip.layer = null;
    _backdrop.layer = null;
    _frost.layer = null;
    _blur.layer = null;
    _bend.layer = null;
    _videoTransform.layer = null;
    _unseen.layer = null;
    _drawUp.layer = null;
    _drawDown.layer = null;
  }

  // Where the shader last placed the pane on screen, in logical pixels.
  Offset? _placed;
  bool _awaitingPaint = false;

  bool get _bends => _mode == VideoGlassMode.refract && _program != null;

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
    _changes?.addListener(_onVideoChanged);
    _track();
  }

  @override
  void detach() {
    forgetLiquidGlassProgram(_onProgram);
    _changes?.removeListener(_onVideoChanged);
    _tracked.remove(this);
    super.detach();
  }

  @override
  void dispose() {
    _shader?.dispose();
    _shader = null;
    _dropLayers();
    super.dispose();
  }

  @override
  bool get alwaysNeedsCompositing => _t > 0 && _filters;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_t <= 0 || size.isEmpty) {
      _dropLayers();
      _placed = null;
      _videoAt = null;
      super.paint(context, offset);
      return;
    }
    final bounds = Offset.zero & size;
    final corners = BorderRadius.circular(
      math.min(_radius ?? double.infinity, size.shortestSide / 2),
    );
    // Over the video, the pane draws the video again itself; until its
    // texture shows, as while it loads, only the tint.
    final video = _filters && _source != null ? _findVideo() : null;
    if (video != null) {
      _paintOverVideo(context, offset, corners, video);
      super.paint(context, offset);
      return;
    }
    if (!_filters || _source != null) {
      // No backdrop to read: the tint thickens to stand in for the frost,
      // as LiquidGlass's does without shader filters.
      _dropLayers();
      _placed = null;
      _videoAt = null;
      final canvas = context.canvas
        ..save()
        ..clipRSuperellipse(corners.toRSuperellipse(offset & size));
      _paintFrost(canvas, offset & size, corners, thicken: 0.2);
      canvas.restore();
      super.paint(context, offset);
      return;
    }
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
    // A pane easing in filters unlike the rest of its group, so it joins
    // the group only once it is whole.
    final group = _t == 1 ? _backdropKey : null;
    if (!_bends) {
      _frost.layer = null;
      final layer = (_backdrop.layer ??= BackdropFilterLayer())
        ..filter = _frostFilter()
        ..backdropKey = group;
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
      ..backdropKey = group;
    context.pushLayer(frost, (context, offset) {
      // Never in the group: it reads the frost's layer, not the screen, and
      // the frost may have left the group's key on this layer.
      final bend = (_backdrop.layer ??= BackdropFilterLayer())
        ..filter = _bendFilter(corners, sigma)
        ..backdropKey = null;
      context.pushLayer(bend, (_, _) {}, offset);
    }, offset);
  }

  void _paintOverVideo(
    PaintingContext context,
    Offset offset,
    BorderRadius corners,
    TextureBox video,
  ) {
    _backdrop.layer = null;
    _frost.layer = null;
    final toPane = _fromVideo(video);
    _debugDescribe(video, toPane);
    _videoAt = toPane;
    _videoTexture = video.textureId;
    _videoSize = video.size;
    _awaitingPaint = false;
    final bends = _bends;
    final bounds = Offset.zero & size;
    final sigma =
        (bends ? _style.blur : math.max(_frostSigma, _style.blur)) * _t;
    // The video as the player lays it out, over its black.
    void paintVideo(PaintingContext context, Offset offset) {
      context.canvas.drawRect(
        offset & size,
        Paint()..color = const Color(0xFF000000),
      );
      _videoTransform.layer = context.pushTransform(
        true,
        offset,
        toPane,
        (context, offset) => context.addLayer(
          TextureLayer(
            rect: offset & video.size,
            textureId: video.textureId,
          ),
        ),
        oldLayer: _videoTransform.layer,
      );
    }

    _clip.layer = context.pushClipRSuperellipse(
      needsCompositing,
      offset,
      bounds,
      corners.toRSuperellipse(bounds),
      (context, offset) {
        final blur = (_blur.layer ??= ImageFilterLayer())
          ..imageFilter = bends
              ? ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma)
              : _frostFilter();
        // A glass host, as a menu's over the player, replays what lies
        // behind it but never sees the texture: it leaves this out.
        final unseen = _unseen.layer ??= LiquidGlassUnseenLayer();
        if (!bends) {
          _bend.layer = null;
          context.pushLayer(
            unseen,
            (context, offset) => context.pushLayer(blur, paintVideo, offset),
            offset,
          );
          _paintFrost(context.canvas, offset & size, corners);
          return;
        }
        // The shader bends the blurred copy, its pixels starting at the
        // pane's corner, as its layer covers the pane alone; past
        // _bendTexelsPerDp, it bends a copy drawn down, which a matrix
        // filter draws up again about the corner.
        final down = math.min(1.0, _bendTexelsPerDp / _devicePixelRatio);
        final bend = (_bend.layer ??= ImageFilterLayer())
          ..imageFilter = _bendFilter(
            corners,
            sigma,
            texture: localToGlobal(Offset.zero),
            texelsPerDp: _devicePixelRatio * down,
          );
        void paintBend(PaintingContext context, Offset offset) =>
            context.pushLayer(
              bend,
              (context, offset) => context.pushLayer(blur, paintVideo, offset),
              offset,
            );
        context.pushLayer(unseen, (context, offset) {
          if (down == 1) {
            _drawUp.layer = null;
            _drawDown.layer = null;
            paintBend(context, offset);
            return;
          }
          final up = (_drawUp.layer ??= ImageFilterLayer())
            ..imageFilter = ui.ImageFilter.matrix(
              (Matrix4.translationValues(offset.dx, offset.dy, 0)
                    ..scaleByDouble(1 / down, 1 / down, 1, 1)
                    ..translateByDouble(-offset.dx, -offset.dy, 0, 1))
                  .storage,
              filterQuality: FilterQuality.low,
            );
          context.pushLayer(up, (context, offset) {
            _drawDown.layer = context.pushTransform(
              true,
              offset,
              Matrix4.diagonal3Values(down, down, 1),
              paintBend,
              oldLayer: _drawDown.layer,
            );
          }, offset);
        }, offset);
      },
      oldLayer: _clip.layer,
    );
  }

  void _debugDescribe(TextureBox video, Matrix4 toPane) {
    // The bottom bar: the widest pane, while the overlay shows.
    if (!VideoGlass.debugDescribing || size.width < 300) return;
    String f(double v) => v.toStringAsFixed(1);
    final m = toPane.storage;
    final shown = MatrixUtils.transformRect(toPane, Offset.zero & video.size);
    final info =
        'tex ${video.textureId} · video ${f(video.size.width)}×'
        '${f(video.size.height)} · pane ${f(size.width)}×${f(size.height)}\n'
        'scale ${m[0].toStringAsFixed(3)},${m[5].toStringAsFixed(3)} '
        'skew ${m[1].toStringAsFixed(2)},${m[4].toStringAsFixed(2)} · '
        'shown ${f(shown.left)},${f(shown.top)} ${f(shown.width)}×'
        '${f(shown.height)} · ${_bends ? '折射' : '磨砂'}';
    if (VideoGlass.debugInfo.value != info) {
      SchedulerBinding.instance.addPostFrameCallback(
        (_) => VideoGlass.debugInfo.value = info,
      );
    }
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
  // [texture] is where the pixels the shader reads start on screen: the
  // screen's corner for a backdrop, a layer's own for a layer's filter.
  ui.ImageFilter _bendFilter(
    BorderRadius corners,
    double frost, {
    Offset texture = Offset.zero,
    double? texelsPerDp,
  }) {
    final style = _style.scale(_t);
    final dpr = texelsPerDp ?? _devicePixelRatio;
    final placed = localToGlobal(Offset.zero);
    _placed = placed;
    _awaitingPaint = false;
    final origin = placed - texture;
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
  void _paintFrost(
    Canvas canvas,
    Rect rect,
    BorderRadius corners, {
    double thicken = 0,
  }) {
    final style = _style.scale(_t);
    final shape = corners.toRSuperellipse(rect);
    final rim = style.rim;
    final tint = style.tint;
    canvas
      ..drawRSuperellipse(
        shape,
        Paint()
          ..color = tint.withValues(
            alpha: math.min(1, tint.a + thicken * _t),
          ),
      )
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
    if (!_bends && _source == null) {
      _tracked.remove(this);
      return;
    }
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
    // Tinted till the video's texture shows, as while it loads.
    if (_source != null && _filters && _videoAt == null) {
      if (_t > 0 && !_awaitingPaint && attached && _findVideo() != null) {
        _awaitingPaint = true;
        markNeedsPaint();
      }
      return;
    }
    // Over the video, what matters is where the video lies from the pane.
    if (_videoAt case final at?) {
      if (_awaitingPaint || !attached || !hasSize) return;
      final video = _video;
      if (video == null ||
          !video.attached ||
          video.textureId != _videoTexture ||
          !video.hasSize ||
          video.size != _videoSize ||
          _fromVideo(video) != at) {
        _awaitingPaint = true;
        markNeedsPaint();
      }
      return;
    }
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
