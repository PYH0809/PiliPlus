import 'dart:ui' show lerpDouble;

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
/// its button and back into it.
///
/// The menus' own glass, [LiquidGlass], reads what the host captured, which
/// holds no video texture: over the video it showed black, and the host
/// capturing the screen again for every frame of the moving video cost the
/// menu frames as it opened. [VideoGlass] draws the video itself, frosted.
class VideoGlassMenu extends StatelessWidget {
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

  /// Where [anchor]'s center lies in the menu, once it has been laid out.
  Offset? _anchorIn(BuildContext context) {
    final anchor = this.anchor;
    final menu = context.findRenderObject();
    final page = context
        .findAncestorRenderObjectOfType<RenderCustomSingleChildLayoutBox>();
    if (anchor == null || menu is! RenderBox || page == null) return null;
    if (!menu.hasSize) return null;
    return anchor.center - menu.localToGlobal(.zero, ancestor: page);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final style = LiquidGlassStyle.menu(colorScheme);
    final rim = LiquidGlassRim.menu(colorScheme);
    final grow = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return AnimatedBuilder(
      animation: grow,
      builder: (context, child) {
        final t = grow.value;
        final origin = _anchorIn(context);
        return Transform.scale(
          scale: lerpDouble(_fromScale, 1, t)!,
          alignment: origin == null ? Alignment.center : Alignment.topLeft,
          origin: origin,
          child: VideoGlassSource.overPlayer(
            child: VideoGlass(
              radius: radius,
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
      child: child,
    );
  }
}
