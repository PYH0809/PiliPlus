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
  const VideoGlassMenus({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<VideoGlassMenus>() != null;

  @override
  Widget wrap(BuildContext context, Widget child) =>
      VideoGlassMenus(child: child);

  @override
  bool updateShouldNotify(VideoGlassMenus oldWidget) => false;
}

// The card grows out of its button from this share of its size.
const double _fromScale = 0.6;
// The rows show once the card has grown past this share of the way.
const double _contentFrom = 0.35;

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
    reverseCurve: Curves.easeInCubic,
  );

  @override
  Animation<double> get menuAnimation => widget.animation;

  @override
  void dispose() {
    _grow.dispose();
    super.dispose();
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
    final rows = pressed == null
        ? widget.child
        : CustomPaint(
            painter: _PressedRow(pressed, theme.highlightColor),
            child: widget.child,
          );
    return AnimatedBuilder(
      animation: _grow,
      builder: (context, child) {
        final t = _grow.value;
        final origin = _anchorIn(context);
        return Transform.scale(
          scale: lerpDouble(_fromScale, 1, t)!,
          alignment: origin == null ? Alignment.center : Alignment.topLeft,
          origin: origin,
          child: VideoGlassSource.overPlayer(
            child: VideoGlass(
              radius: widget.radius,
              t: t,
              // A card this wide shows little of a bend, which costs a
              // shader pass over it every frame.
              refract: false,
              style: style,
              rim: rim.scale(t),
              child: Opacity(
                opacity: ((t - _contentFrom) / (1 - _contentFrom)).clamp(
                  0.0,
                  1.0,
                ),
                child: child,
              ),
            ),
          ),
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
