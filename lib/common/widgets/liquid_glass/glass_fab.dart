import 'package:PiliPlus/common/widgets/liquid_glass/glass_surfaces.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/glass_theme.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass.dart';
import 'package:PiliPlus/common/widgets/liquid_glass/liquid_glass_button.dart';
import 'package:material_ui/material_ui.dart';

/// A page's floating action button. With the liquid glass switch on, a drop
/// of glass in the theme's color that swells under the finger, as the reply
/// buttons are; with it off, Material's [FloatingActionButton], as before.
///
/// On glass it keeps Material's footprint, 56 dp high and padded as Material
/// pads it, a circle or a capsule, so a page lays it out and slides it away
/// just as it did the Material one.
class GlassFab extends StatelessWidget {
  /// A round button holding [child], as [FloatingActionButton.new].
  const GlassFab({
    super.key,
    required this.onPressed,
    this.tooltip,
    required Widget this.child,
    this.shadowRoom = true,
  }) : icon = null,
       label = null;

  /// A capsule holding [icon] before [label], as
  /// [FloatingActionButton.extended].
  const GlassFab.extended({
    super.key,
    required this.onPressed,
    this.tooltip,
    this.icon,
    required Widget this.label,
    this.shadowRoom = true,
  }) : child = null;

  static const size = 56.0;

  /// How far the shadow on glass reaches above the button.
  static const shadowReach = 24.0;

  final VoidCallback? onPressed;
  final String? tooltip;
  final Widget? child;
  final Widget? icon;
  final Widget? label;

  /// Whether, on glass, the button keeps [shadowReach] free above it, so that
  /// a [SlideTransition] by its own height takes the shadow out of sight with
  /// it. A button stacked right under another leaves it out, as it would
  /// widen the gap between them.
  final bool shadowRoom;

  @override
  Widget build(BuildContext context) {
    if (!GlassSurfaces.installed) {
      if (label case final label?) {
        return FloatingActionButton.extended(
          onPressed: onPressed,
          tooltip: tooltip,
          icon: icon,
          label: label,
        );
      }
      return FloatingActionButton(
        onPressed: onPressed,
        tooltip: tooltip,
        child: child,
      );
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final foreground = colorScheme.onPrimary;
    Widget content;
    if (label case final label?) {
      // As Material pads an extended button.
      content = SizedBox(
        height: size,
        child: Padding(
          padding: .directional(start: icon == null ? 20 : 16, end: 20),
          child: Row(
            mainAxisSize: .min,
            spacing: 8,
            children: [?icon, label],
          ),
        ),
      );
    } else {
      content = SizedBox.square(
        dimension: size,
        child: Center(child: child),
      );
    }

    Widget button = LiquidGlassButton(
      tooltip: tooltip,
      onTap: onPressed,
      styleOf: (_) => LiquidGlassStyle.tinted(colorScheme, colorScheme.primary),
      shadows: floatingGlassShadows(colorScheme),
      child: IconTheme.merge(
        data: IconThemeData(color: foreground, size: 24),
        child: DefaultTextStyle(
          style: theme.textTheme.labelLarge!.copyWith(color: foreground),
          child: content,
        ),
      ),
    );
    // The focus ring is drawn in the primary color, which the tint would
    // swallow; in the content's color it shows.
    button = Theme(
      data: theme.copyWith(
        colorScheme: colorScheme.copyWith(primary: foreground),
      ),
      child: button,
    );
    if (shadowRoom) {
      button = Padding(
        padding: const .only(top: shadowReach),
        child: button,
      );
    }
    return MergeSemantics(child: button);
  }
}
