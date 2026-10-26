// After FlClash's alert and menu cards (https://github.com/chen08209/FlClash,
// lib/ui/dialog.dart and lib/ui/popup.dart, GPL-3.0).

import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

/// A panel of liquid glass under [child], with iOS's rim around it and a wide
/// shadow, as an iOS menu or alert: [child] is clipped to its [radius].
class GlassPanel extends SingleChildRenderObjectWidget {
  const GlassPanel({
    super.key,
    required this.style,
    required this.radius,
    this.rim,
    this.shadows = const [],
    super.child,
  });

  final LiquidGlassStyle style;
  final double radius;
  final LiquidGlassRim? rim;
  final List<BoxShadow> shadows;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderGlassPanel(style, radius, rim, shadows);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderGlassPanel)
      ..style = style
      ..radius = radius
      ..rim = rim
      ..shadows = shadows;
  }
}

class _RenderGlassPanel extends RenderProxyBox {
  _RenderGlassPanel(this._style, this._radius, this._rim, this._shadows);

  late final _pane = LiquidGlassPane(markNeedsPaint);
  final _clip = LayerHandle<ClipPathLayer>();

  LiquidGlassStyle _style;
  set style(LiquidGlassStyle value) {
    if (value == _style) {
      return;
    }
    _style = value;
    markNeedsPaint();
  }

  double _radius;
  set radius(double value) {
    if (value == _radius) {
      return;
    }
    _radius = value;
    markNeedsPaint();
  }

  LiquidGlassRim? _rim;
  set rim(LiquidGlassRim? value) {
    if (value == _rim) {
      return;
    }
    _rim = value;
    markNeedsPaint();
  }

  List<BoxShadow> _shadows;
  set shadows(List<BoxShadow> value) {
    if (listEquals(value, _shadows)) {
      return;
    }
    _shadows = value;
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void dispose() {
    _pane.dispose();
    _clip.layer = null;
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null || size.isEmpty) {
      _pane.clear();
      _clip.layer = null;
      return;
    }
    final rect = offset & size;
    _pane.paint(
      context,
      rect,
      shape: LiquidGlassCorners.circular(_radius),
      style: _style,
      shadows: _shadows,
      rim: _rim,
    );
    _rim?.paintLine(context.canvas, rect, _radius);
    final bounds = Offset.zero & size;
    _clip.layer = context.pushClipPath(
      needsCompositing,
      offset,
      bounds,
      Path()..addRSuperellipse(
        RSuperellipse.fromRectAndRadius(bounds, Radius.circular(_radius)),
      ),
      super.paint,
      oldLayer: _clip.layer,
    );
  }
}
