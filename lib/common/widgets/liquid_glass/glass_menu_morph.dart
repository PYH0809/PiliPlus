// After FlClash's popup morph (https://github.com/chen08209/FlClash,
// lib/ui/popup.dart, GPL-3.0): its opening, the press that slides across the
// rows, and its return into the button as a drop of glass.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui show Image;
import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:PiliPlus/common/widgets/liquid_glass/glass_droplet.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_spring.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/goo.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

// As measured on iOS by FlClash: one spring, with a little overshoot, opens a
// menu out of its button.
final _openSpring = SpringDescription.withDampingRatio(
  mass: 1,
  stiffness: 400,
  ratio: 0.754,
);

// The rows show once the card has grown past this share of the way.
const _contentFrom = 0.3;

/// How long a menu takes to return into its button.
const glassMenuReturn = glassDropletReturn;

// The rows leave this soon into the return.
const _dropletContentOut = 0.1;

// The button's snapshot comes back into the droplet over this long.
const _dropletGlyphIn = 0.47;
const _dropletGlyphCurve = Cubic(0.25, 0.1, 0.25, 1);

// Opening, the button's snapshot sinks under the card by this share of the
// way, blurring as it goes.
const _glyphUnderAt = 0.25;
const _glyphBlur = 4.0;

/// The button a menu opens out of, as FlClash's popup source: while its menu
/// is open it is hidden, and the menu draws it from a snapshot instead, sinking
/// into the card as it opens and coming back in the droplet that returns into
/// it, so the button takes over where the droplet lands. A menu takes the
/// source [GlassMenuSourceState.arm]ed for it, or else the one standing where
/// it opens from, as when its button opens it from the keyboard or for
/// assistive technology.
class GlassMenuSource extends StatefulWidget {
  const GlassMenuSource({super.key, required this.child});

  final Widget child;

  @override
  State<GlassMenuSource> createState() => GlassMenuSourceState();
}

class GlassMenuSourceState extends State<GlassMenuSource> {
  static GlassMenuSourceState? _armed;
  static final _sources = <GlassMenuSourceState>{};

  final _boundary = GlobalKey();
  final _hidden = ValueNotifier(false);
  Completer<void>? _landed;

  /// Makes this the button of the menu about to open; call it just before
  /// opening the menu.
  void arm() {
    _armed = this;
    // A menu that did not open by the next frame takes no button.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (identical(_armed, this)) {
        _armed = null;
      }
    });
  }

  /// Completes once the menu has returned into this button and it shows
  /// again, so that a value picked in it changes in place, not under the
  /// returning droplet.
  Future<void> get landed => _landed?.future ?? Future.value();

  @override
  void initState() {
    super.initState();
    _sources.add(this);
  }

  static GlassMenuSourceState? _take(Rect anchor) {
    final armed = _armed;
    _armed = null;
    if (armed != null && armed.mounted) {
      return armed;
    }
    for (final source in _sources) {
      if (source._isAt(anchor)) {
        return source;
      }
    }
    return null;
  }

  // Whether this stands at [anchor], a rect in its navigator's overlay, on a
  // page that shows: a covered page keeps its buttons, offstage.
  bool _isAt(Rect anchor) {
    if (!mounted || !TickerMode.getValuesNotifier(context).value.enabled) {
      return false;
    }
    final box = context.findRenderObject();
    final overlay = Navigator.maybeOf(
      context,
    )?.overlay?.context.findRenderObject();
    if (box is! RenderBox ||
        !box.attached ||
        !box.hasSize ||
        overlay is! RenderBox) {
      return false;
    }
    final rect = box.localToGlobal(.zero, ancestor: overlay) & box.size;
    return (rect.left - anchor.left).abs() < 1 &&
        (rect.top - anchor.top).abs() < 1 &&
        (rect.width - anchor.width).abs() < 1 &&
        (rect.height - anchor.height).abs() < 1;
  }

  ui.Image? _capture() {
    final boundary = _boundary.currentContext?.findRenderObject();
    if (!mounted || boundary is! RenderRepaintBoundary || !boundary.hasSize) {
      return null;
    }
    final image = LiquidGlass.withoutPanes(
      () => boundary.toImageSync(
        pixelRatio: MediaQuery.devicePixelRatioOf(context),
      ),
    );
    _landed ??= Completer();
    _hidden.value = true;
    return image;
  }

  void _reveal() {
    if (mounted) {
      _hidden.value = false;
    }
    _landed?.complete();
    _landed = null;
  }

  @override
  void dispose() {
    if (identical(_armed, this)) {
      _armed = null;
    }
    _sources.remove(this);
    _landed?.complete();
    _landed = null;
    _hidden.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: _hidden,
      builder: (context, hidden, child) =>
          Opacity(opacity: hidden ? 0 : 1, child: child),
      child: RepaintBoundary(key: _boundary, child: widget.child),
    );
  }
}

/// A popup menu that grows out of [anchor], its button, as an iOS menu does:
/// the button's capsule of glass swells into the card, its glass turning to
/// the menu's and its corners to [radius], and the rows fade in. A press
/// carried on into it from its button lights the row under the finger and
/// picks it on release. As it closes it returns into its button as a drop of
/// glass, on the route's [animation].
class GlassMenuMorph extends StatefulWidget {
  const GlassMenuMorph({
    super.key,
    required this.animation,
    required this.anchor,
    required this.radius,
    required this.child,
  });

  final Animation<double> animation;

  /// Where the menu opens from, in the coordinates of the box the menu is
  /// laid out in.
  final Rect? anchor;

  final double radius;
  final Widget child;

  static _GlassMenuMorphState? _active;

  /// Lights the row of the open menu under [position], a global one, or none.
  static void track(Offset? position) => _active?._track(position);

  /// Picks the row of the open menu under [position], a global one.
  static void release(Offset position) => _active?._release(position);

  @override
  State<GlassMenuMorph> createState() => _GlassMenuMorphState();
}

class _GlassMenuMorphState extends State<GlassMenuMorph>
    with SingleTickerProviderStateMixin {
  late final _open = GlassSpring(this, 0);
  bool _started = false;
  // Where the route stood when it began to close.
  double? _closedFrom;
  PopupMenuItemState<dynamic, PopupMenuItem<dynamic>>? _pressed;
  Rect? _pressedRect;
  GlassMenuSourceState? _source;
  ui.Image? _sourceImage;

  @override
  void initState() {
    super.initState();
    GlassMenuMorph._active = this;
    widget.animation.addStatusListener(_handleStatus);
    if (widget.anchor case final anchor?) {
      _source = GlassMenuSourceState._take(anchor);
    }
    // The button may still paint the press that opened the menu, so it is
    // taken once this frame has painted.
    if (_source != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_closing) {
          setState(() => _sourceImage = _source?._capture());
        }
      });
    }
  }

  @override
  void didUpdateWidget(GlassMenuMorph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      oldWidget.animation.removeStatusListener(_handleStatus);
      widget.animation.addStatusListener(_handleStatus);
    }
  }

  void _handleStatus(AnimationStatus status) {
    if (status == AnimationStatus.reverse) {
      _closedFrom ??= _linear(widget.animation);
    } else if (status == AnimationStatus.dismissed) {
      // Landed: the button takes over from its snapshot on the frame the
      // menu goes.
      _source?._reveal();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      if (MediaQuery.disableAnimationsOf(context)) {
        _open.jumpTo(1);
      } else {
        _open.springTo(1, _openSpring);
      }
    }
  }

  @override
  void dispose() {
    if (identical(GlassMenuMorph._active, this)) {
      GlassMenuMorph._active = null;
    }
    widget.animation.removeStatusListener(_handleStatus);
    _source?._reveal();
    _sourceImage?.dispose();
    _open.dispose();
    super.dispose();
  }

  bool get _closing {
    final status = widget.animation.status;
    return status == AnimationStatus.reverse ||
        status == AnimationStatus.dismissed;
  }

  // The item, and its row in this box, under a global position.
  (PopupMenuItemState<dynamic, PopupMenuItem<dynamic>>, Rect)? _itemAt(
    Offset position,
  ) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) {
      return null;
    }
    final result = BoxHitTestResult();
    box.hitTest(result, position: box.globalToLocal(position));
    for (final entry in result.path) {
      if (entry.target
          case RenderMetaData(
            metaData: final PopupMenuItemState<dynamic, PopupMenuItem<dynamic>>
            item,
          )
          when item.mounted && item.widget.enabled) {
        final row = entry.target as RenderBox;
        return (item, row.localToGlobal(.zero, ancestor: box) & row.size);
      }
    }
    return null;
  }

  void _track(Offset? position) {
    if (_closing) {
      return;
    }
    final found = position == null ? null : _itemAt(position);
    if (!identical(found?.$1, _pressed)) {
      if (found != null) {
        HapticFeedback.selectionClick();
      }
      setState(() {
        _pressed = found?.$1;
        _pressedRect = found?.$2;
      });
    }
  }

  // As PopupMenuItemState.handleTap does for a tap on the row.
  void _release(Offset position) {
    _track(null);
    if (_closing) {
      return;
    }
    if (_itemAt(position)?.$1 case final item?) {
      Navigator.pop(item.context, item.widget.value);
      item.widget.onTap?.call();
    }
  }

  // Closing follows the route, which then takes the menu away, from its
  // linear progress: Material's curve would hold it still at first. A menu
  // closed before it opened all the way plays the whole return in the time
  // its route has left.
  double? get _returnTime {
    if (!_closing) {
      return null;
    }
    final from = _closedFrom ?? 1;
    if (from <= 0) {
      return glassDropletReturnSeconds;
    }
    final left = _linear(widget.animation) / from;
    return (1 - left).clamp(0.0, 1.0) * glassDropletReturnSeconds;
  }

  static double _linear(Animation<double> animation) => switch (animation) {
    ProxyAnimation(:final parent?) => _linear(parent),
    CurvedAnimation(:final parent) => _linear(parent),
    _ => animation.value,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final from = LiquidGlassStyle.regular(colorScheme);
    final to = LiquidGlassStyle.menu(colorScheme);
    final rim = LiquidGlassRim.menu(colorScheme);
    return AnimatedBuilder(
      animation: Listenable.merge([_open, widget.animation]),
      builder: (context, child) {
        final progress = _open.value;
        final settled = progress.clamp(0.0, 1.0);
        return _MenuMorph(
          progress: progress,
          returnTime: _returnTime,
          anchor: widget.anchor,
          radius: widget.radius,
          style: LiquidGlassStyle.lerp(from, to, settled),
          buttonStyle: from,
          menuStyle: to,
          rim: rim.scale(settled),
          shadows: menuShadows(colorScheme, settled),
          colorScheme: colorScheme,
          contentOpacity: ((progress - _contentFrom) / (1 - _contentFrom))
              .clamp(0.0, 1.0),
          pressed: _pressedRect,
          pressColor: theme.highlightColor,
          sourceImage: _sourceImage,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _MenuMorph extends SingleChildRenderObjectWidget {
  const _MenuMorph({
    required this.progress,
    required this.returnTime,
    required this.anchor,
    required this.radius,
    required this.style,
    required this.buttonStyle,
    required this.menuStyle,
    required this.rim,
    required this.shadows,
    required this.colorScheme,
    required this.contentOpacity,
    required this.pressed,
    required this.pressColor,
    required this.sourceImage,
    super.child,
  });

  final double progress;
  final double? returnTime;
  final Rect? anchor;
  final double radius;
  final LiquidGlassStyle style;
  final LiquidGlassStyle buttonStyle;
  final LiquidGlassStyle menuStyle;
  final LiquidGlassRim rim;
  final List<BoxShadow> shadows;
  final ColorScheme colorScheme;
  final double contentOpacity;
  final Rect? pressed;
  final Color pressColor;

  /// The button, drawn in its place while it is hidden.
  final ui.Image? sourceImage;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMenuMorph()..update(this);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderMenuMorph).update(this);
  }
}

class _RenderMenuMorph extends RenderProxyBox {
  late final _pane = LiquidGlassPane(markNeedsPaint);
  final _clip = LayerHandle<ClipPathLayer>();
  final _opacity = LayerHandle<OpacityLayer>();

  _MenuMorph? _config;

  // Where the card stood as it began to close, to return from.
  Rect? _lastRect;
  double _lastRadius = 0;
  Rect? _returnFrom;
  double _returnRadius = 0;

  void update(_MenuMorph config) {
    final old = _config;
    _config = config;
    if (old == null ||
        old.progress != config.progress ||
        old.returnTime != config.returnTime ||
        old.anchor != config.anchor ||
        old.radius != config.radius ||
        old.style != config.style ||
        old.rim != config.rim ||
        !listEquals(old.shadows, config.shadows) ||
        old.contentOpacity != config.contentOpacity ||
        old.pressed != config.pressed ||
        old.pressColor != config.pressColor ||
        old.sourceImage != config.sourceImage) {
      markNeedsPaint();
    }
    if (config.returnTime == null) {
      _returnFrom = null;
    }
  }

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void dispose() {
    _pane.dispose();
    _clip.layer = null;
    _opacity.layer = null;
    super.dispose();
  }

  void _clear() {
    _pane.clear();
    _clip.layer = null;
    _opacity.layer = null;
  }

  /// The rect the card grows from, in this box: its button's, or a point
  /// where the menu was opened at a position rather than from a button.
  Rect _from() {
    final anchor = _config?.anchor;
    RenderObject? page = parent;
    while (page != null && page is! RenderCustomSingleChildLayoutBox) {
      page = page.parent;
    }
    if (anchor == null || page == null) {
      return Rect.zero;
    }
    final inPage = MatrixUtils.transformPoint(getTransformTo(page), .zero);
    final local = anchor.shift(-inPage);
    // A point given as a rect from the screen's edges is no button.
    final isButton =
        local.width >= 0 &&
        local.height >= 0 &&
        local.width <= size.width &&
        local.height <= size.height;
    return isButton ? local : Rect.fromLTWH(local.left, local.top, 0, 0);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final config = _config;
    if (child == null || config == null || size.isEmpty) {
      _clear();
      return;
    }
    final from = _from();
    final time = config.returnTime;
    if (time != null && !from.isEmpty) {
      _returnFrom ??= _lastRect ?? Offset.zero & size;
      _returnRadius = _returnFrom == _lastRect ? _lastRadius : config.radius;
      _paintReturn(context, offset, from, time);
      return;
    }
    // A menu opened at a point, with no button to return into, shrinks back
    // to the point as the route closes.
    final progress = time == null
        ? config.progress
        : math.min(
            config.progress,
            1 - Curves.easeOutCubic.transform(time / glassDropletReturnSeconds),
          );
    final rect = Rect.lerp(from, Offset.zero & size, progress)!;
    if (rect.width <= 0 || rect.height <= 0) {
      _clear();
      return;
    }
    final radius = lerpDouble(
      from.shortestSide / 2,
      config.radius,
      progress.clamp(0.0, 1.0),
    )!.clamp(0.0, rect.shortestSide / 2);
    _lastRect = rect;
    _lastRadius = radius;
    final placed = rect.shift(offset);
    _pane.paint(
      context,
      placed,
      shape: LiquidGlassCorners.circular(radius),
      style: config.style,
      shadows: config.shadows,
      rim: config.rim,
    );
    config.rim.paintLine(context.canvas, placed, radius);
    // The button, hidden meanwhile, shrinks and sinks under the card as a
    // droplet would, blurring away.
    if (config.sourceImage case final image? when time == null) {
      final under = math.min(1.0, progress.clamp(0.0, 1.0) / _glyphUnderAt);
      final extent = from.size * lerpDouble(1, glassDropletShare, progress)!;
      final sunk = Offset.lerp(
        from.center,
        size.center(.zero),
        glassDropletShare,
      )!;
      _paintSource(
        context.canvas,
        image,
        Rect.fromCenter(
          center: Offset.lerp(from.center, sunk, progress)!,
          width: math.max(0.0, extent.width),
          height: math.max(0.0, extent.height),
        ).shift(offset),
        1 - under,
        blur: _glyphBlur * under,
      );
    }
    _paintContent(context, offset, rect, radius, config.contentOpacity);
  }

  void _paintSource(
    Canvas canvas,
    ui.Image image,
    Rect rect,
    double opacity, {
    double blur = 0,
  }) {
    if (rect.isEmpty || Color.getAlphaFromOpacity(opacity) == 0) {
      return;
    }
    canvas.drawImageRect(
      image,
      Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
      rect,
      Paint()
        ..color = Color.fromRGBO(0, 0, 0, opacity)
        ..filterQuality = .medium
        ..imageFilter = blur > 0
            ? ImageFilter.blur(sigmaX: blur, sigmaY: blur)
            : null,
    );
  }

  void _paintContent(
    PaintingContext context,
    Offset offset,
    Rect rect,
    double radius,
    double opacity,
  ) {
    final config = _config!;
    _clip.layer = context.pushClipPath(
      needsCompositing,
      offset,
      rect,
      Path()..addRSuperellipse(
        RSuperellipse.fromRectAndRadius(rect, Radius.circular(radius)),
      ),
      (context, offset) {
        void paintRows(PaintingContext context, Offset offset) {
          // A press slid on into the menu stands its row on a platter, as
          // a tap does.
          if (config.pressed case final row?) {
            context.canvas.drawRSuperellipse(
              RSuperellipse.fromRectAndRadius(
                row.shift(offset),
                const Radius.circular(16),
              ),
              Paint()..color = config.pressColor,
            );
          }
          super.paint(context, offset);
        }

        if (opacity >= 1) {
          _opacity.layer = null;
          paintRows(context, offset);
        } else if (opacity > 0) {
          _opacity.layer = context.pushOpacity(
            offset,
            (opacity * 255).round(),
            paintRows,
            oldLayer: _opacity.layer,
          );
        } else {
          _opacity.layer = null;
        }
      },
      oldLayer: _clip.layer,
    );
  }

  /// The return into the button [time] seconds on: the platter dips away and
  /// shrinks toward it while a droplet flows out of it and rises into the
  /// button, the two one surface until the droplet lands.
  void _paintReturn(
    PaintingContext context,
    Offset offset,
    Rect anchor,
    double time,
  ) {
    final config = _config!;
    final from = _returnFrom!;
    final frame = glassDropletReturnAt(
      from: from,
      fromRadius: _returnRadius,
      anchor: anchor,
      time: time,
    );
    final (:platter, :radius, :droplet, :blend, :progress, :absorbed) = frame;
    final outline = gooPairOutline(platter, radius, droplet, blend);
    final shape = outline.getBounds();
    // The button comes back in the droplet, which lands on it, so the button
    // takes over just where it was.
    void paintSource() {
      if (config.sourceImage case final image?) {
        _paintSource(
          context.canvas,
          image,
          droplet.shift(offset),
          lerpDouble(
            0.2,
            1,
            _dropletGlyphCurve.transform(
              (time / _dropletGlyphIn).clamp(0.0, 1.0),
            ),
          )!,
        );
      }
    }

    // Inside the button by then, the droplet dissolves into it, as the
    // button here is no glass of its own.
    if (shape.isEmpty || absorbed >= 1) {
      _clear();
      paintSource();
      return;
    }
    final remaining = (1 - progress).clamp(0.0, 1.0);
    _pane.paint(
      context,
      shape.shift(offset),
      shape: LiquidGlassGoo(
        outline.shift(-shape.topLeft),
        [platter.shift(-shape.topLeft), droplet.shift(-shape.topLeft)],
        [blend],
        firstRadius: math.max(radius, 1e-3),
      ),
      style: LiquidGlassStyle.lerp(
        config.buttonStyle,
        config.menuStyle,
        remaining,
      ).scale(1 - absorbed),
      hold: (Offset.zero & size)
          .expandToInclude(from)
          .expandToInclude(anchor.inflate(anchor.longestSide))
          .inflate(size.longestSide * 0.1)
          .shift(offset),
    );
    paintGlassShadowsOutside(
      context.canvas,
      outline.shift(offset),
      platter.shift(offset),
      radius,
      menuShadows(config.colorScheme, remaining),
    );
    paintSource();
    // The rows leave at once, inside the platter as it starts to shrink.
    final reveal =
        1 -
        Curves.easeOut.transform((time / _dropletContentOut).clamp(0.0, 1.0));
    if (reveal > 0) {
      _paintContent(context, offset, platter, radius, reveal);
    } else {
      _clip.layer = null;
      _opacity.layer = null;
    }
  }
}
