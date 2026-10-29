import 'package:PiliPlus/common/widgets/liquid_glass/glass_theme.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass_button.dart';
import 'package:material_ui/material_ui.dart';

/// The bar of actions at the bottom of a dynamic, an article or a song.
///
/// Without [glass], [child] lies on the surface from edge to edge, over
/// [bottom], the view's padding. With it, [child] floats on a capsule of glass
/// [sideInset] more than 14 in from the sides and 12 above [bottom], at most
/// [maxWidth] wide and at the end.
class DynActionBar extends StatelessWidget {
  const DynActionBar({
    super.key,
    required this.glass,
    required this.bottom,
    required this.child,
    this.sideInset = 0,
    this.maxWidth,
  });

  static const height = 52.0;
  static const margin = 14.0;
  static const gap = 12.0;

  final bool glass;
  final double bottom;
  final double sideInset;
  final double? maxWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    if (!glass) {
      return Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: colorScheme.outline.withValues(alpha: 0.08),
            ),
          ),
        ),
        padding: EdgeInsets.only(bottom: bottom),
        child: child,
      );
    }
    Widget bar = SizedBox(
      height: height,
      child: LiquidGlass(
        style: LiquidGlassStyle.regular(colorScheme),
        shadows: floatingGlassShadows(colorScheme),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: child,
        ),
      ),
    );
    if (maxWidth case final maxWidth?) {
      bar = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: bar,
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(
        margin + sideInset,
        0,
        margin + sideInset,
        gap + bottom,
      ),
      child: bar,
    );
  }
}

/// The action bar's buttons on glass: no ripples, a platter under a press, as
/// rows on glass have.
ButtonStyle glassActionButtonStyle(ColorScheme colorScheme) {
  final platter = glassPlatterColor(colorScheme);
  return TextButton.styleFrom(
    tapTargetSize: .padded,
    padding: const EdgeInsets.symmetric(horizontal: 15),
    foregroundColor: colorScheme.onSurfaceVariant,
    splashFactory: NoSplash.splashFactory,
    shape: const StadiumBorder(),
  ).copyWith(
    overlayColor: WidgetStateProperty.resolveWith(
      (states) =>
          states.contains(WidgetState.pressed) ||
              states.contains(WidgetState.focused)
          ? platter
          : Colors.transparent,
    ),
  );
}

/// The button to write a reply on glass: a circle of the action bar's glass,
/// the icon in the theme's color, as iOS 26 floats a compose button by its
/// toolbar. Tinted the theme's color, the glass hid what lay behind it and
/// read as a plain disc over the bar.
///
/// Its glass is a little thicker than the bar's, as its icon alone, in color,
/// says what it does: the bar's lets enough of a vivid picture through to
/// drown it, as bright magenta drowns a light icon in dark mode.
class GlassReplyButton extends StatelessWidget {
  const GlassReplyButton({super.key, required this.onTap});

  static const size = 56.0;

  // How much of the glass is tint, the bar's being 0.54 in light and 0.62 in
  // dark: enough that the icon keeps 3:1 over any color, with shader filters
  // or without.
  static const _tintAlpha = 0.8;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return SizedBox.square(
      dimension: size,
      child: LiquidGlassButton(
        tooltip: '评论',
        onTap: onTap,
        styleOf: (_) {
          final glass = LiquidGlassStyle.regular(colorScheme);
          return glass.copyWith(
            tint: glass.tint.withValues(alpha: _tintAlpha),
          );
        },
        shadows: floatingGlassShadows(colorScheme),
        child: Center(
          child: Icon(Icons.reply, color: colorScheme.primary),
        ),
      ),
    );
  }
}

/// The replies' sort order on a small capsule of glass.
class GlassSortButton extends StatelessWidget {
  const GlassSortButton({
    super.key,
    required this.label,
    required this.onTap,
  });

  final Widget label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final secondary = ColorScheme.of(context).secondary;
    return SizedBox(
      height: 30,
      child: LiquidGlassButton(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.sort, size: 16, color: secondary),
              const SizedBox(width: 4),
              label,
            ],
          ),
        ),
      ),
    );
  }
}
