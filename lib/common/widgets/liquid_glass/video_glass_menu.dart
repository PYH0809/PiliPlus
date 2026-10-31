import 'dart:ui' as ui;
import 'dart:ui' show lerpDouble;

import 'package:PiliPlus/common/widgets/liquid_glass/glass_menu_morph.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_spring.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/video_glass.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

/// Marks the player's controls, so that a popup menu out of them is drawn as a
/// [VideoGlassMenu]. It is an [InheritedTheme] so that the menu's route,
/// which captures its button's themes, carries it.
class VideoGlassMenus extends InheritedTheme {
  const VideoGlassMenus({super.key, required super.child}) : _routes = 0;

  const VideoGlassMenus._(this._routes, {required super.child});

  /// How many routes carried the mark here from the controls: a menu
  /// straight out of them is one, a menu out of a dialog they opened two,
  /// which lies over the dialog, not the video.
  final int _routes;

  /// Whether [context] is in a menu straight out of the player's controls.
  static bool of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<VideoGlassMenus>()?._routes == 1;

  /// Whether the route built below [context], a popup's, came straight out
  /// of the player's controls, as their menus and dialogs do.
  static bool outOfControls(BuildContext context) {
    var found = false;
    void visit(Element element) {
      if (found) return;
      if (element.widget case VideoGlassMenus(_routes: 1)) {
        found = true;
        return;
      }
      element.visitChildElements(visit);
    }

    context.visitChildElements(visit);
    return found;
  }

  @override
  Widget wrap(BuildContext context, Widget child) =>
      VideoGlassMenus._(_routes + 1, child: child);

  @override
  bool updateShouldNotify(VideoGlassMenus oldWidget) => false;
}

// The card grows out of its button from this share of its size.
const double _fromScale = 0.6;
// Drawn from an image, the card covers what lies under it, as its glass
// does, once it has come this far; nearer nothing the video drawn again under
// it fades with it, lest a hole in the controls trail a card all but gone.
const double _coversFrom = 0.3;

/// A popup menu over the player's video, on the video's glass, growing out of
/// its button and back into it. As [GlassMenuMorph], a press carried on into
/// it from its button lights the row under the finger and picks it on
/// release.
///
/// The menus' own glass, [LiquidGlass], reads what the host captured, which
/// holds no video texture: over the video it showed black, and the host
/// capturing the screen again for every frame of the moving video cost the
/// menu frames as it opened. [VideoGlass] draws the video itself, frosted.
class VideoGlassMenu extends StatefulWidget {
  const VideoGlassMenu({
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
  State<VideoGlassMenu> createState() => _VideoGlassMenuState();
}

class _VideoGlassMenuState extends State<VideoGlassMenu>
    with SingleTickerProviderStateMixin, GlassMenuPressTarget<VideoGlassMenu> {
  // How far the card has grown, on the spring the menus' own glass opens on:
  // its little overshoot carries the card's size past its own, not its glass.
  late final _open = GlassSpring(this, 0);
  bool _started = false;
  late final _motion = Listenable.merge([_open, widget.animation]);

  @override
  Animation<double> get menuAnimation => widget.animation;

  // The rows, inside the growing transform: a row lit while the menu still
  // grows stands where it will be once grown.
  final _rows = GlobalKey();

  @override
  RenderBox? get pressedRowsBox =>
      _rows.currentContext?.findRenderObject() as RenderBox?;

  // Where the route's own time and the card stood as it set off closing,
  // which the card shrinks from, its rows fading with it.
  ({double time, double t})? _closingFrom;

  @override
  void initState() {
    super.initState();
    widget.animation.addStatusListener(_onStatus);
    _open.addListener(_onGrow);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      if (MediaQuery.disableAnimationsOf(context)) {
        _open.jumpTo(1);
      } else {
        _open.springTo(1, glassMenuOpenSpring);
      }
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.reverse && _closingFrom == null) {
      _closingFrom = (
        time: glassMenuRouteTime(widget.animation),
        t: _open.value,
      );
      // The card shrinks from here on, as it stands.
      if (_open.isAnimating) _open.jumpTo(_open.value);
    }
  }

  // Closing, the card shrinks back into where it opened from, as the menus'
  // own glass does with no button to return into, from where it stood and on
  // the route's own time: under Material's curve the route holds still for
  // the first third of its return. It is all but gone well before the route:
  // under a 255th of itself from 85% of the way.
  double _closing(({double time, double t}) from) =>
      from.t *
      glassMenuShrink(glassMenuReturnTime(widget.animation, from.time));

  // Opening, the rows wait for the card to have room for them.
  static double _rowsOpening(double t) =>
      ((t - glassMenuContentFrom) / (1 - glassMenuContentFrom)).clamp(0.0, 1.0);

  // The rows move as the menu grows: a press held still on one finds its row
  // again once they are laid out where they now are.
  void _onGrow() {
    if (menuClosing) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) trackAgain();
    });
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_onStatus);
    _open
      ..removeListener(_onGrow)
      ..dispose();
    super.dispose();
  }

  /// Whether the menu lies on the player, where the video's glass draws its
  /// video and the black around it; a menu reaching past it, as a tall one
  /// out of a small player's bar, reads the screen instead, page and all.
  /// The menu's place, once laid out, before its scale, against what shows
  /// of the player.
  bool _onPlayer(BuildContext context) {
    final menu = context.findRenderObject();
    final player = VideoGlassSource.player?.video.currentContext
        ?.findRenderObject();
    if (menu is! RenderBox || !menu.hasSize) return true;
    if (player is! RenderBox || !player.attached || !player.hasSize) {
      return true;
    }
    Rect onScreen(RenderBox box) => MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
    // What shows of the player: a video zoomed in reaches past it, clipped.
    var bounds = onScreen(player);
    for (RenderObject? node = player.parent; node != null; node = node.parent) {
      if (node is RenderClipRect || node is RenderClipRRect) {
        bounds = bounds.intersect(onScreen(node as RenderBox));
      }
    }
    bounds = bounds.inflate(0.5);
    final rect = onScreen(menu);
    return bounds.contains(rect.topLeft) && bounds.contains(rect.bottomRight);
  }

  /// Where the anchor's center lies in the menu, once it has been laid out.
  Offset? _anchorIn(BuildContext context) {
    final anchor = widget.anchor;
    final menu = context.findRenderObject();
    final page = context
        .findAncestorRenderObjectOfType<RenderCustomSingleChildLayoutBox>();
    if (anchor == null || menu is! RenderBox || page == null) return null;
    if (!menu.hasSize) return null;
    return anchor.center - menu.localToGlobal(.zero, ancestor: page);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final style = LiquidGlassStyle.menu(colorScheme);
    final rim = LiquidGlassRim.menu(colorScheme);
    // A press slid on into the menu stands its row on a platter, as a tap
    // does.
    final pressed = pressedRect;
    final rows = CustomPaint(
      key: _rows,
      painter: pressed == null
          ? null
          : _PressedRow(pressed, theme.highlightColor),
      child: widget.child,
    );
    return AnimatedBuilder(
      animation: _motion,
      builder: (context, child) {
        // With animations off, as the menus' own glass, it stands grown.
        final still = MediaQuery.disableAnimationsOf(context);
        final from = _closingFrom;
        final t = still
            ? 1.0
            : from == null
            ? _open.value
            : _closing(from);
        // The glass and the fades stop at whole; only the size overshoots.
        final settled = t.clamp(0.0, 1.0);
        // Closing, the rows fade with the card from where they stood, not
        // before it, so that no empty card goes on shrinking after them.
        final rowsOpacity = still || from == null || from.t <= 0
            ? _rowsOpening(t)
            : _rowsOpening(from.t) * (t / from.t).clamp(0.0, 1.0);
        final scale = lerpDouble(_fromScale, 1, t)!;
        final origin = _anchorIn(context);
        final moving =
            !still && (_open.isAnimating || widget.animation.isAnimating);
        final onPlayer = _onPlayer(context);
        Widget overPlayer(Widget pane) =>
            onPlayer ? VideoGlassSource.overPlayer(child: pane) : pane;
        // On the move over the player, the card is drawn from an image of
        // its glass at rest, fading in over the video drawn again under it:
        // the glass grown and thinned frame by frame took offscreen passes
        // of new sizes each frame. A backdrop filter, off the player or
        // with none to draw from, reads nothing in an image.
        final drawn = moving && onPlayer && VideoGlassSource.player != null;
        return Stack(
          children: [
            Positioned.fill(
              child: _Growing(
                scale: scale,
                origin: origin,
                opacity: (settled / _coversFrom).clamp(0.0, 1.0),
                child: drawn && settled > 0
                    ? overPlayer(VideoGlass.bare(radius: widget.radius))
                    : null,
              ),
            ),
            Positioned.fill(
              child: _Growing(
                scale: scale,
                origin: origin,
                opacity: drawn ? settled : 1,
                drawn: drawn,
                child: overPlayer(
                  VideoGlass(
                    radius: widget.radius,
                    t: drawn ? 1 : settled,
                    // A card this wide shows little of a bend, which costs a
                    // shader pass over it every frame.
                    refract: false,
                    style: style,
                    rim: drawn ? rim : rim.scale(settled),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
            _GrowingRows(
              scale: scale,
              origin: origin,
              opacity: rowsOpacity,
              drawn: moving,
              fades: widget.animation,
              child: child,
            ),
          ],
        );
      },
      child: rows,
    );
  }
}

class _PressedRow extends CustomPainter {
  const _PressedRow(this.row, this.color);

  final Rect row;
  final Color color;

  static RSuperellipse shape(Rect row) =>
      RSuperellipse.fromRectAndRadius(row, const Radius.circular(16));

  @override
  void paint(Canvas canvas, Size size) =>
      canvas.drawRSuperellipse(shape(row), Paint()..color = color);

  @override
  bool shouldRepaint(_PressedRow oldDelegate) =>
      row != oldDelegate.row || color != oldDelegate.color;
}

/// Scales [child] about [origin], a point in its box, or its center, and
/// fades it by [opacity]; while [drawn], from an image of it at rest, taken
/// as it sets off.
///
/// An image only moves: the glass in it, grown and faded frame by frame,
/// took offscreen passes of new sizes every frame, which Impeller allocates
/// anew. The child draws as at rest into the image, unscaled, so that glass
/// in it draws the video under where it will stand.
class _Growing extends SingleChildRenderObjectWidget {
  const _Growing({
    required this.scale,
    required this.origin,
    this.opacity = 1,
    this.drawn = false,
    super.child,
  });

  final double scale;
  final Offset? origin;
  final double opacity;
  final bool drawn;

  @override
  _RenderGrowing createRenderObject(BuildContext context) => _RenderGrowing(
    scale: scale,
    origin: origin,
    opacity: opacity,
    drawn: drawn,
    devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
  );

  @override
  void updateRenderObject(BuildContext context, _RenderGrowing renderObject) {
    renderObject
      ..scale = scale
      ..origin = origin
      ..opacity = opacity
      ..drawn = drawn
      ..devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
  }
}

class _RenderGrowing extends RenderProxyBox {
  _RenderGrowing({
    required this._scale,
    required this._origin,
    required this._opacity,
    required this._drawn,
    required this._devicePixelRatio,
  });

  double _scale;
  set scale(double value) {
    if (_scale == value) return;
    _scale = value;
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  Offset? _origin;
  set origin(Offset? value) {
    if (_origin == value) return;
    _origin = value;
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  double _opacity;
  set opacity(double value) {
    if (_opacity == value) return;
    _opacity = value;
    markNeedsPaint();
  }

  bool _drawn;
  set drawn(bool value) {
    if (_drawn == value) return;
    _drawn = value;
    if (!value) _dropImage();
    markNeedsPaint();
  }

  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    _dropImage();
    markNeedsPaint();
  }

  ui.Image? _image;
  Size? _imageSize;
  // A platform view, which no image holds, keeps the child live.
  bool _unsnappable = false;
  // Drawing the image: the child stands at rest, unscaled.
  bool _atRest = false;
  final _transformLayer = LayerHandle<TransformLayer>();
  final _opacityLayer = LayerHandle<OpacityLayer>();

  void _dropImage() {
    _image?.dispose();
    _image = null;
    _imageSize = null;
  }

  @override
  void detach() {
    _dropImage();
    super.detach();
  }

  @override
  void dispose() {
    _dropImage();
    _transformLayer.layer = null;
    _opacityLayer.layer = null;
    super.dispose();
  }

  Matrix4 get _transform {
    if (_atRest || _scale == 1) return Matrix4.identity();
    final origin = _origin ?? size.center(Offset.zero);
    return Matrix4.translationValues(origin.dx, origin.dy, 0)
      ..scaleByDouble(_scale, _scale, 1, 1)
      ..translateByDouble(-origin.dx, -origin.dy, 0, 1);
  }

  /// Paints what the image holds of [child], as at rest.
  void paintImage(PaintingContext context, RenderBox child) =>
      context.paintChild(child, Offset.zero);

  ui.Image? _takeImage(RenderBox child) {
    if (_unsnappable) return null;
    final layer = OffsetLayer();
    _atRest = true;
    try {
      // As SnapshotWidget paints its child to take it.
      final context = PaintingContext(layer, Offset.zero & size);
      paintImage(context, child);
      // ignore: invalid_use_of_protected_member
      context.stopRecordingIfNeeded();
    } finally {
      _atRest = false;
    }
    if (!layer.supportsRasterization()) {
      layer.dispose();
      _unsnappable = true;
      return null;
    }
    final image = layer.toImageSync(
      Offset.zero & size,
      pixelRatio: _devicePixelRatio,
    );
    layer.dispose();
    _imageSize = size;
    return image;
  }

  /// Draws [image], the child's at rest, faded by [opacity].
  void drawImage(Canvas canvas, ui.Image image, double opacity) =>
      canvas.drawImageRect(
        image,
        Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
        Offset.zero & size,
        Paint()
          ..color = Color.fromRGBO(0, 0, 0, opacity)
          ..filterQuality = FilterQuality.low,
      );

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null || _opacity <= 0) {
      _transformLayer.layer = null;
      _opacityLayer.layer = null;
      return;
    }
    if (_drawn) {
      if (_imageSize != size) _dropImage();
      if (_image ??= _takeImage(child) case final image?) {
        _transformLayer.layer = null;
        _opacityLayer.layer = null;
        final canvas = context.canvas
          ..save()
          ..translate(offset.dx, offset.dy)
          ..transform(_transform.storage);
        drawImage(canvas, image, _opacity);
        canvas.restore();
        return;
      }
    }
    void paintFaded(PaintingContext context, Offset offset) {
      if (_opacity >= 1) {
        _opacityLayer.layer = null;
        context.paintChild(child, offset);
        return;
      }
      _opacityLayer.layer = context.pushOpacity(
        offset,
        (_opacity * 255).round(),
        (context, offset) => context.paintChild(child, offset),
        oldLayer: _opacityLayer.layer,
      );
    }

    if (_scale == 1) {
      _transformLayer.layer = null;
      paintFaded(context, offset);
      return;
    }
    _transformLayer.layer = context.pushTransform(
      needsCompositing,
      offset,
      _transform,
      paintFaded,
      oldLayer: _transformLayer.layer,
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      result.addWithPaintTransform(
        transform: _transform,
        position: position,
        hitTest: (result, position) =>
            super.hitTestChildren(result, position: position),
      );

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) =>
      transform.multiply(_transform);
}

/// [_Growing] for the menu's rows, which Material fades in and out one
/// after another, each on a layer of its own while it fades, as text never
/// takes a fade drawn straight: drawn, each row's part of the image takes
/// its fade instead, and the platter under a pressed row is drawn live.
class _GrowingRows extends _Growing {
  const _GrowingRows({
    required super.scale,
    required super.origin,
    super.opacity,
    super.drawn,
    required this.fades,
    super.child,
  });

  /// What Material's fades of the rows run on, the menu's route: the rows'
  /// parts of the image take them as it ticks, though the card stand still.
  final Listenable fades;

  @override
  _RenderGrowingRows createRenderObject(BuildContext context) =>
      _RenderGrowingRows(
        scale: scale,
        origin: origin,
        opacity: opacity,
        drawn: drawn,
        fades: fades,
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      );

  @override
  void updateRenderObject(BuildContext context, _RenderGrowing renderObject) {
    super.updateRenderObject(context, renderObject);
    (renderObject as _RenderGrowingRows).fades = fades;
  }
}

class _RenderGrowingRows extends _RenderGrowing {
  _RenderGrowingRows({
    required super.scale,
    required super.origin,
    required super.opacity,
    required super.drawn,
    required this._fades,
    required super.devicePixelRatio,
  });

  Listenable _fades;
  set fades(Listenable value) {
    if (_fades == value) return;
    if (attached) {
      _fades.removeListener(_onFade);
      value.addListener(_onFade);
    }
    _fades = value;
  }

  void _onFade() {
    if (_drawn) markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _fades.addListener(_onFade);
  }

  @override
  void detach() {
    _fades.removeListener(_onFade);
    super.detach();
  }

  // Each row fading in or out as Material has it, outermost first.
  List<RenderAnimatedOpacity> _fadingRows(RenderObject rows) {
    final found = <RenderAnimatedOpacity>[];
    void visit(RenderObject child) {
      if (child is RenderAnimatedOpacity) {
        found.add(child);
      } else {
        child.visitChildren(visit);
      }
    }

    rows.visitChildren(visit);
    return found;
  }

  Rect _rectOf(RenderBox row, RenderBox rows) => MatrixUtils.transformRect(
    row.getTransformTo(rows),
    Offset.zero & row.size,
  );

  List<Rect> _rowRects(RenderBox rows) => [
    for (final row in _fadingRows(rows)) _rectOf(row, rows),
  ];

  // Where the rows stood as the image was taken. A long menu scrolled as it
  // opens has them elsewhere, its taps on other rows than the image shows
  // there: the image is taken again.
  List<Rect>? _imaged;

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (_image != null &&
        child != null &&
        !listEquals(_imaged, _rowRects(child))) {
      _dropImage();
    }
    super.paint(context, offset);
  }

  // The rows unfaded, which they are not as the menu sets off opening.
  @override
  void paintImage(PaintingContext context, RenderBox child) {
    final fading = _fadingRows(child);
    _imaged = _rowRects(child);
    if (fading.isEmpty) return super.paintImage(context, child);
    for (final row in fading) {
      if (row.child case final RenderBox content) {
        context.paintChild(content, _rectOf(row, child).topLeft);
      }
    }
  }

  @override
  void drawImage(Canvas canvas, ui.Image image, double opacity) {
    final child = this.child!;
    final fading = _fadingRows(child);
    if (fading.isEmpty) return super.drawImage(canvas, image, opacity);
    if (child case RenderCustomPaint(
      painter: _PressedRow(:final row, :final color),
    )) {
      canvas.drawRSuperellipse(
        _PressedRow.shape(row),
        Paint()..color = color.withValues(alpha: color.a * opacity),
      );
    }
    final bounds = Offset.zero & size;
    final paint = Paint()..filterQuality = FilterQuality.low;
    for (final row in fading) {
      final alpha = opacity * row.opacity.value;
      final rect = _rectOf(row, child).intersect(bounds);
      if (alpha <= 0 || rect.isEmpty) continue;
      final pixels = Rect.fromLTRB(
        rect.left * _devicePixelRatio,
        rect.top * _devicePixelRatio,
        rect.right * _devicePixelRatio,
        rect.bottom * _devicePixelRatio,
      );
      canvas.drawImageRect(
        image,
        pixels,
        rect,
        paint..color = Color.fromRGBO(0, 0, 0, alpha.clamp(0.0, 1.0)),
      );
    }
  }
}
