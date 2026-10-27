// After FlClash's popup morph (https://github.com/chen08209/FlClash,
// lib/ui/popup.dart, GPL-3.0), carried over to pages: a page grows out of
// the glass button that opens it, and returns into it as a drop of glass.

import 'dart:math' as math;
import 'dart:ui' as ui show ImageFilter, lerpDouble;

import 'package:PiliPlus/common/widgets/liquid_glass/glass_droplet.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/goo.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass_button.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

// As FlClash's popup opens, measured on iOS: one spring, with a little
// overshoot, carries the card out of its button; its corners follow on a
// second a moment later, and it dips as it leaves.
final _open = SpringSimulation(
  SpringDescription.withDampingRatio(mass: 1, stiffness: 400, ratio: 0.754),
  0,
  1,
  0,
);
final _corners = SpringSimulation(
  SpringDescription.withDampingRatio(mass: 1, stiffness: 324, ratio: 0.75),
  1,
  0,
  0,
);
const _cornersDelay = 0.07;
const _cornersReach = 0.48;
const _rimDepth = 8.0;

// Long enough for both springs to settle. The route keeps the time, rather
// than springs of its own, so the navigator knows when the page has opened.
const _openDuration = Duration(milliseconds: 500);
final _openSeconds = _openDuration.inMicroseconds / 1e6;

// The page leaves this soon into the return, its fill a little later.
const _contentOut = 0.1;
const _fillOut = 0.16;

// A blur the page takes below this does not show, so it takes none.
const _blurUnseen = 0.5;

/// A [LiquidGlassButton] that opens a page out of itself, as FlClash's and
/// iOS's buttons open their popovers: the page grows out of the button's
/// glass, and returns into it as a drop of glass as it closes. [onTap] opens
/// it with [GlassMorphButtonState.toNamed]. While the page is open the button
/// stands hidden, the morph drawing it: [child] is built there too, so it
/// holds no [GlobalKey].
class GlassMorphButton extends StatefulWidget {
  const GlassMorphButton({
    super.key,
    required this.onTap,
    required this.child,
    this.styleOf = LiquidGlassStyle.regular,
    this.shadows = const [],
    this.tooltip,
  });

  final void Function(GlassMorphButtonState button) onTap;
  final Widget child;
  final LiquidGlassStyle Function(ColorScheme colorScheme) styleOf;
  final List<BoxShadow> shadows;
  final String? tooltip;

  @override
  State<GlassMorphButton> createState() => GlassMorphButtonState();
}

class GlassMorphButtonState extends State<GlassMorphButton> {
  // The page open out of this button, which stands hidden from when the page
  // first shows until it has closed.
  TransitionRoute<dynamic>? _route;
  bool _hidden = false;

  RenderBox? get _box {
    if (!mounted) {
      return null;
    }
    final box = context.findRenderObject();
    return box is RenderBox && box.attached && box.hasSize ? box : null;
  }

  /// Opens the page named [page] out of this button, as [Get.toNamed] does.
  /// With animations turned off, or no route by that name, it is
  /// [Get.toNamed].
  Future<T?>? toNamed<T>(
    String page, {
    Map<String, String>? parameters,
    dynamic arguments,
  }) {
    if (page == Get.currentRoute) {
      return null;
    }
    final navigator = Get.key.currentState;
    if (navigator == null ||
        _box == null ||
        MediaQuery.disableAnimationsOf(context)) {
      return Get.toNamed(page, parameters: parameters, arguments: arguments);
    }
    final name = parameters == null
        ? page
        : Uri(path: page, queryParameters: parameters).toString();
    // As Get.toNamed's pushNamed resolves it.
    final redirect = PageRedirect(
      settings: RouteSettings(name: name, arguments: arguments),
    );
    while (redirect.needRecheck()) {}
    final target = redirect.route;
    if (redirect.isUnknown || target == null) {
      return Get.toNamed(page, parameters: parameters, arguments: arguments);
    }
    final route = _GlassMorphRoute<T>(
      source: this,
      page: target.page,
      parameter: target.parameters,
      settings: redirect.settings,
      binding: target.binding,
      bindings: target.bindings,
      middlewares: target.middlewares,
    );
    final opened = navigator.push(route);
    _route?.animation?.removeStatusListener(_handleRouteStatus);
    route.animation?.addStatusListener(_handleRouteStatus);
    route.completed.whenComplete(() => _shown(route));
    _route = route;
    // A route spends its first frame offstage, for heroes to measure, so
    // the button hides as the page first shows, a frame on.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(_route, route)) {
        setState(() => _hidden = true);
      }
    });
    return opened;
  }

  void _handleRouteStatus(AnimationStatus status) {
    if (status.isDismissed) {
      _shown(_route);
    }
  }

  void _shown(TransitionRoute<dynamic>? route) {
    if (route == null || !identical(route, _route)) {
      return;
    }
    route.animation?.removeStatusListener(_handleRouteStatus);
    _route = null;
    if (mounted) {
      setState(() => _hidden = false);
    }
  }

  @override
  void dispose() {
    _route?.animation?.removeStatusListener(_handleRouteStatus);
    _route = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Hidden, it takes no taps either: as its page returns, the route lets
    // taps through to the page below, which would open it again.
    return IgnorePointer(
      ignoring: _hidden,
      child: Opacity(
        opacity: _hidden ? 0 : 1,
        child: LiquidGlassButton(
          styleOf: widget.styleOf,
          shadows: widget.shadows,
          tooltip: widget.tooltip,
          onTap: () => widget.onTap(this),
          child: widget.child,
        ),
      ),
    );
  }
}

class _GlassMorphRoute<T> extends GetPageRoute<T> {
  _GlassMorphRoute({
    required this.source,
    super.settings,
    super.page,
    super.parameter,
    super.binding,
    super.bindings,
    super.middlewares,
  });

  final GlassMorphButtonState source;

  @override
  Duration get transitionDuration => _openDuration;

  @override
  Duration get reverseTransitionDuration => glassDropletReturn;

  // The page under it stays still as this one grows out of its button.
  @override
  DelegatedTransitionBuilder? get delegatedTransition => null;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _PageMorph(
      animation: animation,
      source: source,
      // A page opened over this one moves it as the app's transition does.
      child: super.buildTransitions(
        context,
        kAlwaysCompleteAnimation,
        secondaryAnimation,
        child,
      ),
    );
  }
}

class _PageMorph extends StatefulWidget {
  const _PageMorph({
    required this.animation,
    required this.source,
    required this.child,
  });

  final Animation<double> animation;
  final GlassMorphButtonState source;
  final Widget child;

  @override
  State<_PageMorph> createState() => _PageMorphState();
}

class _PageMorphState extends State<_PageMorph> {
  // Where the route stood when it began to close.
  double? _closedFrom;
  RenderBox? _sourceBox;

  @override
  void initState() {
    super.initState();
    widget.animation.addStatusListener(_handleStatus);
  }

  @override
  void didUpdateWidget(_PageMorph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      oldWidget.animation.removeStatusListener(_handleStatus);
      widget.animation.addStatusListener(_handleStatus);
    }
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_handleStatus);
    super.dispose();
  }

  void _handleStatus(AnimationStatus status) {
    switch (status) {
      case AnimationStatus.reverse:
        _closedFrom ??= _linear(widget.animation);
      case AnimationStatus.forward:
        _closedFrom = null;
      default:
    }
  }

  static double _linear(Animation<double> animation) => switch (animation) {
    ProxyAnimation(:final parent?) => _linear(parent),
    CurvedAnimation(:final parent) => _linear(parent),
    _ => animation.value,
  };

  // Closing follows the route from its linear progress. A page closed before
  // it opened all the way plays the whole return in the time its route has
  // left.
  double? get _returnTime {
    final from = _closedFrom ?? 1;
    if (from <= 0) {
      return glassDropletReturnSeconds;
    }
    final left = _linear(widget.animation) / from;
    return (1 - left).clamp(0.0, 1.0) * glassDropletReturnSeconds;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final source = widget.source;
    // The button's face, drawn in the glass as it leaves and as it returns.
    final face = ExcludeSemantics(
      child: IgnorePointer(
        child: Material(
          type: MaterialType.transparency,
          child: source.widget.child,
        ),
      ),
    );
    return AnimatedBuilder(
      animation: widget.animation,
      builder: (context, child) {
        if (source._box case final box?) {
          _sourceBox = box;
        }
        final status = widget.animation.status;
        return _Morph(
          openTime: status == AnimationStatus.forward
              ? _linear(widget.animation) * _openSeconds
              : null,
          returnTime: status.isForwardOrCompleted ? null : _returnTime,
          source: _sourceBox,
          faceSize: _sourceBox?.size ?? Size.zero,
          buttonStyle: source.widget.styleOf(colorScheme),
          pageStyle: LiquidGlassStyle.menu(colorScheme),
          buttonShadows: source.widget.shadows,
          colorScheme: colorScheme,
          children: [child!, face],
        );
      },
      child: widget.child,
    );
  }
}

class _Morph extends MultiChildRenderObjectWidget {
  const _Morph({
    required this.openTime,
    required this.returnTime,
    required this.source,
    required this.faceSize,
    required this.buttonStyle,
    required this.pageStyle,
    required this.buttonShadows,
    required this.colorScheme,
    required super.children,
  });

  /// Seconds into the page's opening, or its return, if under way.
  final double? openTime;
  final double? returnTime;

  /// The button, whose rect the page grows from and returns into.
  final RenderBox? source;
  final Size faceSize;
  final LiquidGlassStyle buttonStyle;
  final LiquidGlassStyle pageStyle;
  final List<BoxShadow> buttonShadows;
  final ColorScheme colorScheme;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMorph()..update(this);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderMorph).update(this);
  }
}

class _MorphParentData extends ContainerBoxParentData<RenderBox> {}

/// The page, its first child, morphing out of and into its button, whose
/// face is its second.
class _RenderMorph extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _MorphParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _MorphParentData> {
  late final _pane = LiquidGlassPane(markNeedsPaint);
  final _clip = LayerHandle<ClipPathLayer>();
  final _transform = LayerHandle<TransformLayer>();
  final _filter = LayerHandle<ImageFilterLayer>();
  final _faceOpacity = LayerHandle<OpacityLayer>();

  _Morph? _config;

  // How the page stands in its platter while it morphs, and where the face
  // stands; for hit tests and transforms as for paint.
  Matrix4? _pageTransform;

  // Whether the page is morphing, or opening, as last painted. While it
  // morphs it takes hits only where it is drawn, and while it opens it
  // takes the rest, so that a tap does not reach the hidden button.
  bool _morphing = false;
  bool _opening = false;
  Offset _faceOffset = Offset.zero;

  // Where the button last was, and the page as it began to return.
  Rect? _lastAnchor;
  Rect? _lastPlatter;
  double _lastRadius = 0;
  double _lastContent = 1;
  double _lastFill = 1;
  Rect? _returnFrom;
  double _returnRadius = 0;
  double _returnContent = 1;
  double _returnFill = 1;

  RenderBox get _page => firstChild!;
  RenderBox get _face => lastChild!;

  void update(_Morph config) {
    final old = _config;
    _config = config;
    if (old?.faceSize != config.faceSize) {
      markNeedsLayout();
    }
    markNeedsPaint();
    if (config.returnTime == null) {
      _returnFrom = null;
    }
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _MorphParentData) {
      child.parentData = _MorphParentData();
    }
  }

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void performLayout() {
    size = constraints.biggest;
    _page.layout(BoxConstraints.tight(size));
    _face.layout(BoxConstraints.tight(_config!.faceSize));
  }

  @override
  void dispose() {
    _pane.dispose();
    _clear();
    super.dispose();
  }

  void _clear() {
    _pane.clear();
    _clip.layer = null;
    _transform.layer = null;
    _filter.layer = null;
    _faceOpacity.layer = null;
  }

  /// The button's rect in this box, or where it last was.
  Rect? _anchor() {
    if (_config?.source case final source? when source.attached) {
      final rect = MatrixUtils.transformRect(
        source.getTransformTo(this),
        Offset.zero & source.size,
      );
      if (rect.isFinite && !rect.isEmpty) {
        _lastAnchor = rect;
      }
    }
    return _lastAnchor;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final config = _config!;
    final anchor = _anchor();
    _pageTransform = null;
    _morphing =
        anchor != null &&
        (config.openTime != null || config.returnTime != null);
    _opening = _morphing && config.returnTime == null;
    if (anchor == null || !_morphing) {
      _clear();
      context.paintChild(_page, offset);
      return;
    }
    if (config.returnTime case final time?) {
      _paintReturn(context, offset, anchor, time);
    } else {
      _paintOpen(context, offset, anchor, config.openTime!);
    }
  }

  /// The opening [time] seconds on: the button's glass swells into the page,
  /// a platter growing out of it while the button's own drop sinks into it.
  void _paintOpen(
    PaintingContext context,
    Offset offset,
    Rect anchor,
    double time,
  ) {
    final config = _config!;
    final card = Offset.zero & size;
    final progress = _open.x(time);
    final settled = progress.clamp(0.0, 1.0);
    final scale = ui.lerpDouble(
      glassPlatterInControl * anchor.shortestSide / card.width,
      1,
      progress,
    )!;
    final height = ui.lerpDouble(card.width, card.height, progress)!;
    final toCard = card.center.dy - anchor.center.dy;
    final dip =
        toCard.sign *
        (math.min(1.0, toCard.abs() / 30) * 23 + 0.124 * toCard.abs()) *
        glassRiseAndFall(time, 0.098, 3.3);
    final platter = Rect.fromCenter(
      center:
          Offset.lerp(anchor.center, card.center, progress)! + Offset(0, dip),
      width: math.max(0.0, card.width * scale),
      height: math.max(0.0, height * scale),
    );
    final corners =
        card.width *
        _cornersReach *
        _corners.x(math.max(0.0, time - _cornersDelay));
    final radius = math.max(0.0, math.min(height / 2, corners) * scale);
    final extent = anchor.size * ui.lerpDouble(1, glassDropletShare, progress)!;
    final sunk = Offset.lerp(anchor.center, card.center, glassDropletShare)!;
    final droplet = Rect.fromCenter(
      center: Offset.lerp(
        anchor.center,
        _within(
          sunk,
          card.deflate(
            anchor.longestSide * glassDropletShare / 2 +
                glassDropletBlend +
                _rimDepth,
          ),
        ),
        progress,
      )!,
      width: extent.width,
      height: extent.height,
    );
    _lastPlatter = platter;
    _lastRadius = radius;
    _lastContent = Curves.easeOut.transform(_interval(0.15, 0.6, settled));
    _lastFill = Curves.easeIn.transform(_interval(0.2, 0.85, settled));
    _paintMorph(
      context,
      offset,
      anchor: anchor,
      platter: platter,
      radius: radius,
      droplet: droplet,
      blend: glassDropletBlend,
      style: LiquidGlassStyle.lerp(
        config.buttonStyle,
        config.pageStyle,
        settled,
      ),
      platterShadows: menuShadows(config.colorScheme, settled),
      dropletShadows: _scaled(config.buttonShadows, 1 - settled),
      fill: _lastFill,
      content: _lastContent,
      blur: math.sqrt(
        math.pow(4 * (1 - settled), 2) +
            math.pow(1.9 * glassRiseAndFall(time, 0.069, 2.1), 2),
      ),
      face: 1 - math.min(1.0, settled / 0.25),
      faceAt: anchor,
    );
  }

  /// The return into the button [time] seconds on, as a menu's: the page
  /// leaves at once and its platter dips away and shrinks toward the button,
  /// while a droplet flows out of it and rises into the button, re-forming
  /// it.
  void _paintReturn(
    PaintingContext context,
    Offset offset,
    Rect anchor,
    double time,
  ) {
    final config = _config!;
    if (_returnFrom == null) {
      _returnFrom = _lastPlatter ?? Offset.zero & size;
      _returnRadius = _lastPlatter == null ? 0 : _lastRadius;
      _returnContent = _lastPlatter == null ? 1 : _lastContent;
      _returnFill = _lastPlatter == null ? 1 : _lastFill;
    }
    final (
      :platter,
      :radius,
      :droplet,
      :blend,
      :progress,
      :absorbed,
    ) = glassDropletReturnAt(
      from: _returnFrom!,
      fromRadius: _returnRadius,
      anchor: anchor,
      time: time,
    );
    final remaining = (1 - progress).clamp(0.0, 1.0);
    _paintMorph(
      context,
      offset,
      anchor: anchor,
      platter: platter,
      radius: radius,
      droplet: droplet,
      blend: blend,
      style: LiquidGlassStyle.lerp(
        config.buttonStyle,
        config.pageStyle,
        remaining,
      ),
      platterShadows: menuShadows(config.colorScheme, remaining),
      dropletShadows: _scaled(config.buttonShadows, progress.clamp(0.0, 1.0)),
      fill:
          _returnFill *
          (1 - Curves.easeOut.transform((time / _fillOut).clamp(0.0, 1.0))),
      content:
          _returnContent *
          (1 - Curves.easeOut.transform((time / _contentOut).clamp(0.0, 1.0))),
      blur: 4 * Curves.easeOut.transform((time / _contentOut).clamp(0.0, 1.0)),
      face: absorbed,
      faceAt: droplet,
    );
  }

  void _paintMorph(
    PaintingContext context,
    Offset offset, {
    required Rect anchor,
    required Rect platter,
    required double radius,
    required Rect droplet,
    required double blend,
    required LiquidGlassStyle style,
    required List<BoxShadow> platterShadows,
    required List<BoxShadow> dropletShadows,
    required double fill,
    required double content,
    required double blur,
    required double face,
    required Rect faceAt,
  }) {
    final config = _config!;
    final outline = gooPairOutline(platter, radius, droplet, blend);
    final shape = outline.getBounds();
    if (shape.isEmpty) {
      _clear();
      return;
    }
    final card = Offset.zero & size;
    // Under a full fill the glass would not show: most of the opening.
    if (fill < 1) {
      _pane.paint(
        context,
        shape.shift(offset),
        shape: LiquidGlassGoo(
          outline.shift(-shape.topLeft),
          [platter.shift(-shape.topLeft), droplet.shift(-shape.topLeft)],
          [blend],
          firstRadius: math.max(radius, 1e-3),
        ),
        style: style,
        // One capture as it grows, at the lighter glass's frost, which the
        // shader frosts past: the glass thickens from the button's to the
        // page's, and a capture taken at each would redraw what lies
        // behind, the whole screen, frame after frame.
        hold: card
            .expandToInclude(anchor.inflate(anchor.longestSide))
            .inflate(size.longestSide * 0.1)
            .shift(offset),
        holdFrost: math.min(config.buttonStyle.blur, config.pageStyle.blur),
      );
    } else {
      _pane.clear();
    }
    final canvas = context.canvas;
    final path = outline.shift(offset);
    paintGlassShadowsOutside(
      canvas,
      path,
      platter.shift(offset),
      radius,
      platterShadows,
    );
    paintGlassShadowsOutside(
      canvas,
      path,
      droplet.shift(offset),
      droplet.shortestSide / 2,
      dropletShadows,
    );
    if (fill > 0) {
      canvas.drawPath(
        path,
        Paint()..color = config.colorScheme.surface.withValues(alpha: fill),
      );
    }
    _paintFace(context, offset, faceAt, face);
    _paintPage(context, offset, platter, radius, content, blur);
  }

  // The button's face, centred where the button stands or its droplet is.
  void _paintFace(
    PaintingContext context,
    Offset offset,
    Rect at,
    double opacity,
  ) {
    _faceOffset =
        at.center - Offset(_face.size.width / 2, _face.size.height / 2);
    if (opacity <= 0) {
      _faceOpacity.layer = null;
      return;
    }
    _faceOpacity.layer = context.pushOpacity(
      offset + _faceOffset,
      (opacity * 255).round(),
      (context, offset) => context.paintChild(_face, offset),
      oldLayer: _faceOpacity.layer,
    );
  }

  // The page, shrunk into its platter and clipped to it.
  void _paintPage(
    PaintingContext context,
    Offset offset,
    Rect platter,
    double radius,
    double opacity,
    double blur,
  ) {
    if (opacity <= 0 || platter.isEmpty) {
      _clip.layer = null;
      _transform.layer = null;
      _filter.layer = null;
      return;
    }
    // The fade and the blur in one pass offscreen, the page's size, and none
    // once a blur would no longer show.
    ui.ImageFilter? filter;
    if (blur > _blurUnseen) {
      filter = ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur);
    }
    if (opacity < 1) {
      final fade = ColorFilter.matrix([
        ...[1, 0, 0, 0, 0],
        ...[0, 1, 0, 0, 0],
        ...[0, 0, 1, 0, 0],
        ...[0, 0, 0, opacity, 0],
      ]);
      filter = filter == null
          ? fade
          : ui.ImageFilter.compose(outer: fade, inner: filter);
    }
    final scale = platter.width / size.width;
    final transform = Matrix4.identity()
      ..translateByDouble(platter.left, platter.top, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
    _pageTransform = transform;
    _clip.layer = context.pushClipPath(
      needsCompositing,
      offset,
      platter,
      Path()..addRSuperellipse(
        RSuperellipse.fromRectAndRadius(platter, Radius.circular(radius)),
      ),
      (context, offset) {
        _transform.layer = context.pushTransform(
          needsCompositing,
          offset,
          transform,
          (context, offset) {
            if (filter == null) {
              _filter.layer = null;
              context.paintChild(_page, offset);
            } else {
              context.pushLayer(
                (_filter.layer ??= ImageFilterLayer())..imageFilter = filter,
                (context, offset) => context.paintChild(_page, offset),
                offset,
              );
            }
          },
          oldLayer: _transform.layer,
        );
      },
      oldLayer: _clip.layer,
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    if (identical(child, _face)) {
      transform.translateByDouble(_faceOffset.dx, _faceOffset.dy, 0, 1);
    } else if (_pageTransform case final page?) {
      transform.multiply(page);
    }
  }

  @override
  bool hitTestSelf(Offset position) => _opening;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final transform = _pageTransform;
    if (transform == null) {
      return !_morphing && _page.hitTest(result, position: position);
    }
    return result.addWithPaintTransform(
      transform: transform,
      position: position,
      hitTest: (result, position) => _page.hitTest(result, position: position),
    );
  }

  static double _interval(double begin, double end, double t) =>
      ((t - begin) / (end - begin)).clamp(0.0, 1.0);

  static Offset _within(Offset point, Rect rect) => Offset(
    rect.width >= 0 ? point.dx.clamp(rect.left, rect.right) : rect.center.dx,
    rect.height >= 0 ? point.dy.clamp(rect.top, rect.bottom) : rect.center.dy,
  );

  static List<BoxShadow> _scaled(List<BoxShadow> shadows, double amount) => [
    for (final shadow in shadows)
      shadow.copyWith(
        color: shadow.color.withValues(alpha: shadow.color.a * amount),
      ),
  ];
}
