// The few FlClash helpers that liquid_glass.dart uses, from FlClash's
// lib/ui/color.dart, lib/ui/context.dart and lib/ui/shape.dart (GPL-3.0).
import 'package:flutter/foundation.dart' show clampDouble;
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:material_ui/material_ui.dart';

extension GlassColorTone on Color {
  Color shiftTone(double delta) {
    final hct = Hct.fromInt(toARGB32());
    return Color(
      Hct.from(
        hct.hue,
        hct.chroma,
        clampDouble(hct.tone + delta, 0, 100),
      ).toInt(),
    );
  }
}

extension GlassMotion on BuildContext {
  Duration motionDuration(Duration duration) =>
      MediaQuery.maybeDisableAnimationsOf(this) ?? false
      ? Duration.zero
      : duration;
}

abstract final class AppRadius {
  static BorderRadius all(double corner) => BorderRadius.circular(corner);
}

abstract final class AppShape {
  static RoundedSuperellipseBorder of(BorderRadius borderRadius) =>
      RoundedSuperellipseBorder(borderRadius: borderRadius);
}
