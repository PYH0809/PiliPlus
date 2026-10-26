// After FlClash's popup morph (https://github.com/chen08209/FlClash,
// lib/ui/popup.dart, GPL-3.0), without its droplet or its press that slides
// across the rows.

import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:PiliPlus/common/widgets/liquid_glass/glass_spring.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/rendering.dart';
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

/// A popup menu that grows out of [anchor], its button, as an iOS menu does:
/// the button's capsule of glass swells into the card, its glass turning to
/// the menu's and its corners to [radius], and the rows fade in. The menu
/// goes back into its button as it closes, on the route's [animation].
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

  @override
  State<GlassMenuMorph> createState() => _GlassMenuMorphState();
}

class _GlassMenuMorphState extends State<GlassMenuMorph>
    with SingleTickerProviderStateMixin {
  late final _open = GlassSpring(this, 0);
  bool _started = false;

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
    _open.dispose();
    super.dispose();
  }

  // Closing follows the route, which then takes the menu away; from its
  // linear progress, since Material's curve holds the menu still for the
  // first third, and fast at first, as an iOS menu leaves.
  double get _progress {
    final route = widget.animation;
    if (route.status != AnimationStatus.reverse &&
        route.status != AnimationStatus.dismissed) {
      return _open.value;
    }
    return math.min(
      _open.value,
      1 - Curves.easeOutCubic.transform(1 - _linear(route)),
    );
  }

  static double _linear(Animation<double> animation) => switch (animation) {
    ProxyAnimation(:final parent?) => _linear(parent),
    CurvedAnimation(:final parent) => _linear(parent),
    _ => animation.value,
  };

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final from = LiquidGlassStyle.regular(colorScheme);
    final to = LiquidGlassStyle.menu(colorScheme);
    final rim = LiquidGlassRim.menu(colorScheme);
    return AnimatedBuilder(
      animation: Listenable.merge([_open, widget.animation]),
      builder: (context, child) {
        final progress = _progress;
        final settled = progress.clamp(0.0, 1.0);
        return _MenuMorph(
          progress: progress,
          anchor: widget.anchor,
          radius: widget.radius,
          style: LiquidGlassStyle.lerp(from, to, settled),
          rim: rim.scale(settled),
          shadows: menuShadows(colorScheme, settled),
          contentOpacity: ((progress - _contentFrom) / (1 - _contentFrom))
              .clamp(0.0, 1.0),
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
    required this.anchor,
    required this.radius,
    required this.style,
    required this.rim,
    required this.shadows,
    required this.contentOpacity,
    super.child,
  });

  final double progress;
  final Rect? anchor;
  final double radius;
  final LiquidGlassStyle style;
  final LiquidGlassRim rim;
  final List<BoxShadow> shadows;
  final double contentOpacity;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderMenuMorph()
    ..progress = progress
    ..anchor = anchor
    ..radius = radius
    ..style = style
    ..rim = rim
    ..shadows = shadows
    ..contentOpacity = contentOpacity;

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderMenuMorph)
      ..progress = progress
      ..anchor = anchor
      ..radius = radius
      ..style = style
      ..rim = rim
      ..shadows = shadows
      ..contentOpacity = contentOpacity;
  }
}

class _RenderMenuMorph extends RenderProxyBox {
  late final _pane = LiquidGlassPane(markNeedsPaint);
  final _clip = LayerHandle<ClipPathLayer>();
  final _opacity = LayerHandle<OpacityLayer>();

  double _progress = 1;
  set progress(double value) {
    if (value != _progress) {
      _progress = value;
      markNeedsPaint();
    }
  }

  Rect? _anchor;
  set anchor(Rect? value) {
    if (value != _anchor) {
      _anchor = value;
      markNeedsPaint();
    }
  }

  double _radius = 0;
  set radius(double value) {
    if (value != _radius) {
      _radius = value;
      markNeedsPaint();
    }
  }

  LiquidGlassStyle? _style;
  set style(LiquidGlassStyle value) {
    if (value != _style) {
      _style = value;
      markNeedsPaint();
    }
  }

  LiquidGlassRim? _rim;
  set rim(LiquidGlassRim value) {
    if (value != _rim) {
      _rim = value;
      markNeedsPaint();
    }
  }

  List<BoxShadow> _shadows = const [];
  set shadows(List<BoxShadow> value) {
    if (!listEquals(value, _shadows)) {
      _shadows = value;
      markNeedsPaint();
    }
  }

  double _contentOpacity = 1;
  set contentOpacity(double value) {
    if (value != _contentOpacity) {
      _contentOpacity = value;
      markNeedsPaint();
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

  /// The rect the card grows from, in this box: its button's, or a point
  /// where the menu was opened at a position rather than from a button.
  Rect _from() {
    final anchor = _anchor;
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
    final child = this.child;
    final style = _style;
    if (child == null || style == null || size.isEmpty) {
      _pane.clear();
      _clip.layer = null;
      _opacity.layer = null;
      return;
    }
    final from = _from();
    final rect = Rect.lerp(from, Offset.zero & size, _progress)!;
    if (rect.width <= 0 || rect.height <= 0) {
      _pane.clear();
      _clip.layer = null;
      _opacity.layer = null;
      return;
    }
    final radius = lerpDouble(
      from.shortestSide / 2,
      _radius,
      _progress.clamp(0.0, 1.0),
    )!.clamp(0.0, rect.shortestSide / 2);
    final placed = rect.shift(offset);
    _pane.paint(
      context,
      placed,
      shape: LiquidGlassCorners.circular(radius),
      style: style,
      shadows: _shadows,
      rim: _rim,
    );
    _rim?.paintLine(context.canvas, placed, radius);
    _clip.layer = context.pushClipPath(
      needsCompositing,
      offset,
      rect,
      Path()..addRSuperellipse(
        RSuperellipse.fromRectAndRadius(rect, Radius.circular(radius)),
      ),
      _paintContent,
      oldLayer: _clip.layer,
    );
  }

  void _paintContent(PaintingContext context, Offset offset) {
    if (_contentOpacity >= 1) {
      _opacity.layer = null;
      super.paint(context, offset);
    } else if (_contentOpacity > 0) {
      _opacity.layer = context.pushOpacity(
        offset,
        (_contentOpacity * 255).round(),
        super.paint,
        oldLayer: _opacity.layer,
      );
    } else {
      _opacity.layer = null;
    }
  }
}
