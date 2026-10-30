import 'dart:ui' as ui;

import 'package:PiliPlus/common/widgets/liquid_glass/video_glass.dart';
import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

class AppBarAni extends StatelessWidget {
  const AppBarAni({
    super.key,
    required this.child,
    required this.controller,
    required this.isTop,
    required this.isFullScreen,
    required this.removeSafeArea,
    this.glass = false,
  });

  final Widget child;
  final AnimationController controller;
  final bool isTop;
  final bool isFullScreen;
  final bool removeSafeArea;

  /// Whether the bar floats on glass, under a faint shade at the top for its
  /// title and none at the bottom.
  final bool glass;

  static final _topPos = Tween<Offset>(
    begin: const Offset(0.0, -1.0),
    end: Offset.zero,
  );

  static const _topDecoration = LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: <Color>[
      Colors.transparent,
      Color(0xBF000000),
    ],
    tileMode: TileMode.mirror,
  );

  static const _glassTopDecoration = LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: <Color>[
      Colors.transparent,
      Color(0x59000000),
    ],
  );

  static final _bottomPos = Tween<Offset>(
    begin: const Offset(0, 1.2),
    end: Offset.zero,
  );

  static const _bottomDecoration = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[
      Colors.transparent,
      Color(0xBF000000),
    ],
    tileMode: TileMode.mirror,
  );

  @override
  Widget build(BuildContext context) {
    final bar = _slide();
    if (!glass) {
      return bar;
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) =>
          VideoGlassHidden(hidden: controller.isDismissed, child: child!),
      child: bar,
    );
  }

  Widget _slide() {
    final position = isTop ? _topPos : _bottomPos;
    // A BoxDecoration takes taps over its whole box, so the bars keep one
    // even bare, lest a tap between their panes reach the player.
    final bar = DecoratedBox(
      decoration: BoxDecoration(
        gradient: glass
            ? (isTop ? _glassTopDecoration : null)
            : (isTop ? _topDecoration : _bottomDecoration),
      ),
      child: removeSafeArea
          ? child
          : ViewSafeArea(
              left: isFullScreen,
              right: isFullScreen,
              child: child,
            ),
    );
    if (glass) {
      return _GlassSlide(
        animation: controller,
        from: position.begin!,
        child: bar,
      );
    }
    return SlideTransition(
      position: controller.drive(position),
      child: bar,
    );
  }
}

/// Slides [child] in from [from], a fraction of its size, as
/// [SlideTransition] does, but draws it from a snapshot taken at rest while
/// it moves.
///
/// The glass over the video draws the video again each frame, which on a
/// slow phone takes about a 120 Hz frame by itself, and a pane crossing the
/// player's edge gets offscreen textures of a new size every frame, where
/// Impeller reuses only those of the same size. An image only moves. The
/// snapshot is taken, and the bar drawn live again, while it stands still:
/// as it sets off, and the frame after it lands. Over the slide the glass
/// shows the video as it was when the slide set off.
class _GlassSlide extends SingleChildRenderObjectWidget {
  const _GlassSlide({
    required this.animation,
    required this.from,
    super.child,
  });

  final Animation<double> animation;
  final Offset from;

  @override
  _RenderGlassSlide createRenderObject(BuildContext context) =>
      _RenderGlassSlide(
        animation: animation,
        from: from,
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderGlassSlide renderObject,
  ) {
    renderObject
      ..animation = animation
      ..from = from
      ..devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
  }
}

class _RenderGlassSlide extends RenderProxyBox {
  _RenderGlassSlide({
    required this._animation,
    required this._from,
    required this._devicePixelRatio,
  });

  Animation<double> _animation;
  set animation(Animation<double> value) {
    if (_animation == value) return;
    if (attached) {
      _animation.removeListener(_onSlide);
      value.addListener(_onSlide);
    }
    _animation = value;
    _dropSnapshot();
    _onSlide();
  }

  Offset _from;
  set from(Offset value) {
    if (_from == value) return;
    _from = value;
    _onSlide();
  }

  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    _dropSnapshot();
    markNeedsPaint();
  }

  ui.Image? _snapshot;
  Size? _snapshotSize;
  // A platform view, which no image holds, keeps the bar live.
  bool _unsnappable = false;
  // Painting the snapshot: the bar lies at rest, for the glass to draw what
  // lies under it there.
  bool _atRest = false;
  bool _goingLive = false;

  Offset get _shift {
    if (_atRest) return Offset.zero;
    final fraction = _from * (1 - _animation.value);
    return Offset(fraction.dx * size.width, fraction.dy * size.height);
  }

  // The bar moves: where it is drawn, and where assistive technology finds
  // it, as FractionalTranslation tells both.
  void _onSlide() {
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _animation.addListener(_onSlide);
  }

  @override
  void detach() {
    _animation.removeListener(_onSlide);
    _dropSnapshot();
    super.detach();
  }

  @override
  void dispose() {
    _dropSnapshot();
    super.dispose();
  }

  void _dropSnapshot() {
    _snapshot?.dispose();
    _snapshot = null;
    _snapshotSize = null;
  }

  ui.Image? _takeSnapshot(RenderBox child) {
    if (_unsnappable || size.isEmpty) return null;
    final layer = OffsetLayer();
    _atRest = true;
    try {
      // As SnapshotWidget paints its child to take it.
      PaintingContext(layer, Offset.zero & size)
        ..paintChild(child, Offset.zero)
        // ignore: invalid_use_of_protected_member
        ..stopRecordingIfNeeded();
    } finally {
      _atRest = false;
    }
    if (!layer.supportsRasterization()) {
      layer.dispose();
      _unsnappable = true;
      return null;
    }
    final snapshot = layer.toImageSync(
      Offset.zero & size,
      pixelRatio: _devicePixelRatio,
    );
    layer.dispose();
    _snapshotSize = size;
    return snapshot;
  }

  // Out of sight, as the slide ends hidden, the glass is off and costs
  // nothing: no snapshot to show.
  bool get _hidden => _animation.isDismissed;

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    if (_snapshotSize != size) _dropSnapshot();
    final moving = _animation.isAnimating;
    // The first frame of a slide, the bar stands where it sets off from.
    if (moving && _snapshot == null) _snapshot = _takeSnapshot(child);
    final snapshot = _snapshot;
    if (snapshot == null || _hidden) {
      _dropSnapshot();
      context.paintChild(child, offset + _shift);
      return;
    }
    if (!moving && !_goingLive) {
      // Landed, this frame still moving it: the next draws it live.
      _goingLive = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _goingLive = false;
        if (!attached || _animation.isAnimating) return;
        _dropSnapshot();
        markNeedsPaint();
      });
    }
    context.canvas.drawImageRect(
      snapshot,
      Offset.zero & Size(snapshot.width.toDouble(), snapshot.height.toDouble()),
      (offset + _shift) & size,
      Paint()..filterQuality = FilterQuality.low,
    );
  }

  // As FractionalTranslation, the bar takes taps where it is drawn, out of
  // its own box.
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      hitTestChildren(result, position: position);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      result.addWithPaintOffset(
        offset: _shift,
        position: position,
        hitTest: (result, position) =>
            super.hitTestChildren(result, position: position),
      );

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final shift = _shift;
    transform.translateByDouble(shift.dx, shift.dy, 0, 1);
  }
}
