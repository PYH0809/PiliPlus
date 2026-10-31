import 'dart:ui' show lerpDouble;

import 'package:PiliPlus/common/widgets/liquid_glass/glass_menu_morph.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/video_glass.dart';
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
// The rows show once the card has grown past this share of the way.
const double _contentFrom = 0.35;
// Closing, the card is gone by this share of the time the route has left
// to return, which lasts as long as a menu's drop back into its button.
// This card only shrinks and fades, and over all of it trailed a faint,
// empty pane.
const double _goneBy = 0.6;

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
    with GlassMenuPressTarget<VideoGlassMenu> {
  late final _grow = CurvedAnimation(
    parent: widget.animation,
    curve: Curves.easeOutCubic,
  );

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
    widget.animation
      ..addListener(_onGrow)
      ..addStatusListener(_onStatus);
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.reverse) {
      _closingFrom ??= (
        time: glassMenuRouteTime(widget.animation),
        t: _grow.value,
      );
    }
  }

  // Closing, the card from where it stood, on the route's own time: under
  // Material's curve the route holds still for the first third of its
  // return, and a menu closed as it still grew would follow its opening
  // curve back till the route ends.
  double _closing(({double time, double t}) from) {
    if (from.time <= 0) return 0;
    final gone = from.time * (1 - _goneBy);
    final left =
        (glassMenuRouteTime(widget.animation) - gone) / (from.time - gone);
    return from.t * Curves.easeIn.transform(left.clamp(0.0, 1.0));
  }

  // Opening, the rows wait for the card to have room for them.
  static double _rowsOpening(double t) =>
      ((t - _contentFrom) / (1 - _contentFrom)).clamp(0.0, 1.0);

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
    widget.animation
      ..removeListener(_onGrow)
      ..removeStatusListener(_onStatus);
    _grow.dispose();
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
      animation: _grow,
      builder: (context, child) {
        // With animations off, as the menus' own glass, it stands grown.
        final still = MediaQuery.disableAnimationsOf(context);
        final from = _closingFrom;
        final t = still
            ? 1.0
            : from == null
            ? _grow.value
            : _closing(from);
        // Closing, the rows fade with the card from where they stood, not
        // before it, so that no empty card goes on shrinking after them.
        final rows = still || from == null || from.t <= 0
            ? _rowsOpening(t)
            : _rowsOpening(from.t) * (t / from.t).clamp(0.0, 1.0);
        final origin = _anchorIn(context);
        final glass = VideoGlass(
          radius: widget.radius,
          t: t,
          // A card this wide shows little of a bend, which costs a shader
          // pass over it every frame.
          refract: false,
          style: style,
          rim: rim.scale(t),
          child: Opacity(opacity: rows, child: child),
        );
        return Transform.scale(
          scale: lerpDouble(_fromScale, 1, t)!,
          alignment: origin == null ? Alignment.center : Alignment.topLeft,
          origin: origin,
          child: _onPlayer(context)
              ? VideoGlassSource.overPlayer(child: glass)
              : glass,
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

  @override
  void paint(Canvas canvas, Size size) => canvas.drawRSuperellipse(
    RSuperellipse.fromRectAndRadius(row, const Radius.circular(16)),
    Paint()..color = color,
  );

  @override
  bool shouldRepaint(_PressedRow oldDelegate) =>
      row != oldDelegate.row || color != oldDelegate.color;
}
