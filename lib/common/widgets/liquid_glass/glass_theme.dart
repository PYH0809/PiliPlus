import 'package:material_color_utilities/material_color_utilities.dart';
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

/// What marks the current item on glass at rest, as FlClash's platter: the
/// secondary hue at tone 90, or 4 in dark, which sinks it below the glass.
Color glassPlatterColor(ColorScheme colorScheme) {
  final dark = colorScheme.brightness == Brightness.dark;
  final hct = Hct.fromInt(colorScheme.secondary.toARGB32())
    ..tone = dark ? 4.0 : 90.0;
  return Color(hct.toInt()).withValues(alpha: 0.85);
}
