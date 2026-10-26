import 'package:material_ui/material_ui.dart';

/// The soft, wide drop under floating glass, as FlClash's dock casts: three
/// times as strong in dark, where it reads less.
List<BoxShadow> floatingGlassShadows(ColorScheme colorScheme) {
  final strength = colorScheme.brightness == Brightness.dark ? 3.0 : 1.0;
  return [
    BoxShadow(
      color: colorScheme.shadow.withValues(alpha: 0.08 * strength),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
    BoxShadow(
      color: colorScheme.shadow.withValues(alpha: 0.04 * strength),
      blurRadius: 3,
      offset: const Offset(0, 1),
    ),
  ];
}

/// What marks the current item on glass at rest, as iOS's tab bars do: a
/// neutral shade, darker on light glass and lighter on dark, leaving the
/// item's own color to say which it is.
Color glassPlatterColor(ColorScheme colorScheme) =>
    colorScheme.brightness == Brightness.dark
    ? const Color(0x24FFFFFF)
    : const Color(0x1A000000);
